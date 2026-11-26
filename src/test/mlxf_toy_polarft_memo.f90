!@descr: the toy polar calculator's memoization: the setters' staging, the ring transforms of references and particles, the reference bins
! The transforms are direct sums in double precision over the full ring (the half ring, then its conjugate),
! rounded once to single precision: the values the scorer's fixtures have always been given. The setters stage
! a few sections at a time; a full staging is turned into memos at once, by the whole team, and memoize_refs
! and memoize_ptcls finish what is staged.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_memo
!$ use omp_lib, only: omp_get_thread_num, omp_get_max_threads
implicit none

contains

    module subroutine reallocate_ptcls( self, nptcls, pinds )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: nptcls
        integer,             intent(in)    :: pinds(nptcls)
        integer :: i
        if( .not. self%existence )then
            self%msg = 'polarft_calc%reallocate_ptcls: refused: no calculator (new)'
            return
        endif
        if( nptcls < 1 )then
            self%msg = 'polarft_calc%reallocate_ptcls: refused: a batch has at least one particle'
            return
        endif
        if( any(pinds < 1) )then
            self%msg = 'polarft_calc%reallocate_ptcls: refused: particle indices are positive'
            return
        endif
        self%msg     = ''
        self%sm_imap = 0
        self%pfromto = [minval(pinds), maxval(pinds)]
        self%nptcls  = nptcls
        call kill_ptcls(self)
        call alloc_ptcls(self)
        deallocate(self%pinds)
        allocate(self%pinds(self%pfromto(1):self%pfromto(2)), source=0)
        do i = 1, nptcls
            self%pinds(pinds(i)) = i
        end do
        self%ptcl_gen = self%ptcl_gen + 1_int64
    end subroutine reallocate_ptcls

    ! the transform's factors and the staging arrays, made at the first setter call
    subroutine alloc_staging( self )
        class(polarft_calc), intent(inout) :: self
        if( .not. allocated(self%dft_e) ) self%dft_e = dft_factors(self%nrots, self%pftsz + 1)
        if( .not. allocated(self%pfts_refs) )then
            allocate(self%pfts_refs(self%pftsz, self%kfromto(1):self%kfromto(2), POLARFT_STAGE_N))
            self%nref_staged = 0
        endif
        if( .not. allocated(self%pfts_ptcls) )then
            allocate(self%pfts_ptcls(self%pftsz, self%kfromto(1):self%kfromto(2), POLARFT_STAGE_N), &
                &self%ctfmats(self%pftsz, self%kfromto(1):self%kfromto(2), POLARFT_STAGE_N))
            self%nptcl_staged = 0
        endif
    end subroutine alloc_staging

    module subroutine set_ref_pft( self, iref, pft, iseven )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iref
        complex(real64),     intent(in)    :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
        logical,             intent(in)    :: iseven
        integer :: ieo, j, jj
        if( .not. self%existence )then
            self%msg = 'polarft_calc%set_ref_pft: refused: no calculator (new)'
            return
        endif
        if( iref < 1 .or. iref > self%nrefs )then
            self%msg = 'polarft_calc%set_ref_pft: refused: the reference is outside 1..nrefs'
            return
        endif
        self%msg = ''
        call alloc_staging(self)
        ieo = merge(REF_EVEN, REF_ODD, iseven)
        ! a reference set twice keeps its place in the staging; a full staging is memoized first
        j = 0
        do jj = 1, self%nref_staged
            if( self%stage_ref(1, jj) == iref .and. self%stage_ref(2, jj) == ieo ) j = jj
        end do
        if( j == 0 )then
            if( self%nref_staged == POLARFT_STAGE_N ) call flush_refs(self)
            self%nref_staged = self%nref_staged + 1
            j                = self%nref_staged
        endif
        self%stage_ref(:, j)    = [iref, ieo]
        self%pfts_refs(:, :, j) = pft
        self%l_refs_pending     = .true.
    end subroutine set_ref_pft

    module subroutine get_ref_pft( self, iref, iseven, pft )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iref
        logical,             intent(in)    :: iseven
        complex(real32),     intent(inout) :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
        integer :: ieo, j
        pft = cmplx(0._real32, 0._real32, real32)
        if( .not. self%existence )then
            self%msg = 'polarft_calc%get_ref_pft: refused: no calculator (new)'
            return
        endif
        if( iref < 1 .or. iref > self%nrefs )then
            self%msg = 'polarft_calc%get_ref_pft: refused: the reference is outside 1..nrefs'
            return
        endif
        ieo      = merge(REF_EVEN, REF_ODD, iseven)
        self%msg = ''
        if( self%l_mlx .and. self%route == POLARFT_REF_ROUTES%device )then
            call get_ref_pft_mlx(self, iref, iseven, pft)
            return
        endif
        do j = 1, self%nref_staged
            if( self%stage_ref(1, j) == iref .and. self%stage_ref(2, j) == ieo )then
                pft = cmplx(self%pfts_refs(:, :, j), kind=real32)
                return
            endif
        end do
        self%msg = 'polarft_calc%get_ref_pft: refused: the host route keeps only the memos of a memoized reference'
    end subroutine get_ref_pft

    ! the staged references become their memos
    subroutine flush_refs( self )
        class(polarft_calc), intent(inout) :: self
        complex(real64), allocatable :: zw(:,:), yw(:,:)
        integer                      :: nthr, idx, j, k, iref, ieo, ithr
        if( self%nref_staged == 0 ) return
        nthr = 1
        !$ nthr = omp_get_max_threads()
        allocate(zw(self%pftsz, nthr), yw(self%pftsz + 1, nthr))
        !$omp parallel do default(shared) private(idx, j, k, iref, ieo, ithr) schedule(dynamic, 16) proc_bind(close)
        do idx = 1, self%nref_staged * self%nk
            ithr = thread_index()
            j    = (idx - 1) / self%nk + 1
            k    = self%kfromto(1) + mod(idx - 1, self%nk)
            iref = self%stage_ref(1, j)
            ieo  = self%stage_ref(2, j)
            zw(:, ithr) = self%pfts_refs(:, k, j)
            call ring_bins(self%dft_e, zw(:, ithr), yw(:, ithr))
            self%ft_ref(:, k, iref, ieo) = cmplx(yw(:, ithr), kind=real32)
            zw(:, ithr) = cmplx(abs(self%pfts_refs(:, k, j))**2, 0._real64, real64)
            call ring_bins(self%dft_e, zw(:, ithr), yw(:, ithr))
            self%ft_ref2(:, k, iref, ieo) = cmplx(conjg(yw(:, ithr)), kind=real32)
        end do
        !$omp end parallel do
        self%nref_staged = 0
    end subroutine flush_refs

    ! the staging place of the particle in batch slot i: its own when it is staged, else a new one with the CTF
    ! at 1 and no section (a full staging is memoized first); 0 when the staging is full of particles that
    ! still wait for their sections
    integer function stage_place( self, i )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: i
        integer :: jj
        stage_place = 0
        do jj = 1, self%nptcl_staged
            if( self%stage_ptcl(jj) == i ) stage_place = jj
        end do
        if( stage_place > 0 ) return
        if( self%nptcl_staged == POLARFT_STAGE_N ) call flush_ptcls(self)
        if( self%nptcl_staged == POLARFT_STAGE_N ) return
        self%nptcl_staged = self%nptcl_staged + 1
        stage_place       = self%nptcl_staged
        self%stage_ptcl(stage_place)       = i
        self%l_stage_pft(stage_place)      = .false.
        self%ctfmats(:, :, stage_place)    = 1._real32
        self%pfts_ptcls(:, :, stage_place) = cmplx(0._real32, 0._real32, real32)
    end function stage_place

    module subroutine set_ptcl_pft( self, iptcl, pft )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        complex(real32),     intent(in)    :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
        integer :: i, j, k
        i = ptcl_slot(self, iptcl)
        if( i == 0 )then
            self%msg = 'polarft_calc%set_ptcl_pft: refused: the particle is not in the batch'
            return
        endif
        call alloc_staging(self)
        j = stage_place(self, i)
        if( j == 0 )then
            self%msg = 'polarft_calc%set_ptcl_pft: refused: the staging is full of CTFs that wait for their sections'
            return
        endif
        self%msg                 = ''
        self%pfts_ptcls(:, :, j) = pft
        self%l_stage_pft(j)      = .true.
        self%l_ptcl_set(i)       = .true.
        do k = self%kfromto(1), self%kfromto(2)
            self%kshell_sqsums_ptcls(k, i) = sum(abs(cmplx(pft(:, k), kind=real64))**2)
        end do
        self%ptcl_gen = self%ptcl_gen + 1_int64
    end subroutine set_ptcl_pft

    module subroutine set_ptcl_ctfmat( self, iptcl, ctfmat )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        real(real32),        intent(in)    :: ctfmat(self%pftsz, self%kfromto(1):self%kfromto(2))
        integer :: i, j
        i = ptcl_slot(self, iptcl)
        if( i == 0 )then
            self%msg = 'polarft_calc%set_ptcl_ctfmat: refused: the particle is not in the batch'
            return
        endif
        if( self%l_ptcl_set(i) )then
            self%msg = 'polarft_calc%set_ptcl_ctfmat: refused: a particle''s CTF is set before its section'
            return
        endif
        call alloc_staging(self)
        j = stage_place(self, i)
        if( j == 0 )then
            self%msg = 'polarft_calc%set_ptcl_ctfmat: refused: the staging is full of CTFs that wait for their sections'
            return
        endif
        self%msg              = ''
        self%ctfmats(:, :, j) = ctfmat
        self%ptcl_gen         = self%ptcl_gen + 1_int64
    end subroutine set_ptcl_ctfmat

    ! the staged particles whose sections came become their memos; those that still wait for their sections
    ! move to the front of the staging
    subroutine flush_ptcls( self )
        class(polarft_calc), intent(inout) :: self
        complex(real64), allocatable :: zw(:,:), yw(:,:)
        integer                      :: nthr, idx, j, k, i, ithr, nkeep
        if( self%nptcl_staged == 0 ) return
        nthr = 1
        !$ nthr = omp_get_max_threads()
        allocate(zw(self%pftsz, nthr), yw(self%pftsz + 1, nthr))
        !$omp parallel do default(shared) private(idx, j, k, i, ithr) schedule(dynamic, 16) proc_bind(close)
        do idx = 1, self%nptcl_staged * self%nk
            ithr = thread_index()
            j    = (idx - 1) / self%nk + 1
            k    = self%kfromto(1) + mod(idx - 1, self%nk)
            i    = self%stage_ptcl(j)
            if( .not. self%l_stage_pft(j) ) cycle
            zw(:, ithr) = cmplx(real(self%ctfmats(:, k, j), real64)**2, 0._real64, real64)
            call ring_bins(self%dft_e, zw(:, ithr), yw(:, ithr))
            self%ft_ctf2(:, k, i) = cmplx(yw(:, ithr), kind=real32)
            zw(:, ithr) = cmplx(self%pfts_ptcls(:, k, j), kind=real64) * real(self%ctfmats(:, k, j), real64)
            call ring_bins(self%dft_e, zw(:, ithr), yw(:, ithr))
            self%ft_ptcl_ctf(:, k, i) = cmplx(yw(:, ithr), kind=real32)
        end do
        !$omp end parallel do
        nkeep = 0
        do j = 1, self%nptcl_staged
            if( self%l_stage_pft(j) ) cycle
            nkeep = nkeep + 1
            if( nkeep == j ) cycle
            self%stage_ptcl(nkeep)       = self%stage_ptcl(j)
            self%l_stage_pft(nkeep)      = .false.
            self%ctfmats(:, :, nkeep)    = self%ctfmats(:, :, j)
            self%pfts_ptcls(:, :, nkeep) = self%pfts_ptcls(:, :, j)
        end do
        self%nptcl_staged = nkeep
    end subroutine flush_ptcls

    ! the forward DFT's factors (negative exponent) of the first nbins bins of a ring of n samples
    function dft_factors( n, nbins ) result(e)
        integer, intent(in) :: n, nbins
        complex(real64) :: e(nbins, n)
        real(real64)    :: angle
        integer         :: p, m
        do m = 1, n
            do p = 1, nbins
                angle   = -2._real64 * acos(-1._real64) * real(mod((p - 1) * (m - 1), n), real64) / real(n, real64)
                e(p, m) = cmplx(cos(angle), sin(angle), real64)
            end do
        end do
    end function dft_factors

    ! the first size(e,1) bins of the forward DFT of the full ring of half ring z (the samples, then their
    ! conjugates), summed in ring order; no allocation (OpenMP regions call it)
    pure subroutine ring_bins( e, z, y )
        complex(real64), intent(in)  :: e(:,:), z(:)
        complex(real64), intent(out) :: y(:)
        integer :: p, m, n
        n = size(z)
        do p = 1, size(e, 1)
            y(p) = (0._real64, 0._real64)
            do m = 1, n
                y(p) = y(p) + z(m) * e(p, m)
            end do
            do m = 1, n
                y(p) = y(p) + conjg(z(m)) * e(p, n + m)
            end do
        end do
    end subroutine ring_bins

    ! the calling thread's number from 1 (OpenMP), 1 without OpenMP
    integer function thread_index()
        thread_index = 1
        !$ thread_index = omp_get_thread_num() + 1
    end function thread_index

    module subroutine memoize_refs( self )
        class(polarft_calc), intent(inout) :: self
        if( .not. self%existence )then
            self%msg = 'polarft_calc%memoize_refs: refused: no calculator (new)'
            return
        endif
        self%msg = ''
        if( self%l_mlx .and. self%route == POLARFT_REF_ROUTES%device )then
            call memoize_refs_mlx(self)
            if( len(self%msg) > 0 ) return
        else
            call flush_refs(self)
        endif
        ! from here the route is fixed: the memos of the references that waited exist on this route only
        if( self%l_refs_pending ) self%l_refs_memoized = .true.
        self%l_refs_pending = .false.
        self%ref_gen        = self%ref_gen + 1_int64
    end subroutine memoize_refs

    module subroutine memoize_ptcls( self )
        class(polarft_calc), intent(inout) :: self
        real(real64) :: wsq
        integer      :: i, k, ih
        if( .not. self%existence )then
            self%msg = 'polarft_calc%memoize_ptcls: refused: no calculator (new)'
            return
        endif
        self%msg = ''
        ! a CTF whose section never came is dropped with the staging
        call flush_ptcls(self)
        self%nptcl_staged = 0
        self%l_ptcl_set   = .false.
        ! the weighted square sum over the shells, from the half's weights
        do i = 1, self%nptcls
            ih  = merge(REF_EVEN, REF_ODD, self%iseven(i))
            wsq = 0._real64
            do k = self%kfromto(1), self%kfromto(2)
                wsq = wsq + self%sigma2_wk8(k, ih) * self%kshell_sqsums_ptcls(k, i)
            end do
            self%wsqsums_ptcls(i) = wsq
        end do
        self%ptcl_gen_memo = self%ptcl_gen
    end subroutine memoize_ptcls

    module subroutine memoize_ref_bins( self )
        class(polarft_calc), intent(inout) :: self
        if( .not. self%existence )then
            self%msg = 'polarft_calc%memoize_ref_bins: refused: no calculator (new)'
            return
        endif
        if( self%l_refs_pending )then
            self%msg = 'polarft_calc%memoize_ref_bins: refused: references were set and not memoized (memoize_refs)'
            return
        endif
        self%msg          = ''
        self%ref_gen_bins = -1_int64
        if( self%l_mlx )then
            call memoize_ref_bins_mlx(self)
        else
            call host_ref_bins(self)
        endif
        if( len(self%msg) > 0 ) return
        self%ref_gen_bins = self%ref_gen
    end subroutine memoize_ref_bins

    ! SIMPLE's bin-major memo of the references: per angular bin the 2nk shell terms of every reference, rows
    ! 1..nk conj(ft_ref2) and rows nk+1..2nk ft_ref, so that a block's sums of a bin read contiguous memory
    subroutine host_ref_bins( self )
        class(polarft_calc), intent(inout) :: self
        integer :: iref, ieo, j, k, kk, ierr
        if( .not. allocated(self%ft_ref_bins) )then
            allocate(self%ft_ref_bins(2 * self%nk, self%nrefs, self%pftsz + 1, N_REF_PARITIES), stat=ierr)
            if( ierr /= 0 )then
                self%msg = 'polarft_calc%memoize_ref_bins: the bin-major memo could not be allocated'
                return
            endif
        endif
        !$omp parallel do default(shared) private(iref, ieo, j, k, kk) schedule(static) proc_bind(close)
        do iref = 1, self%nrefs
            do ieo = REF_EVEN, REF_ODD
                do j = 1, self%pftsz + 1
                    do k = self%kfromto(1), self%kfromto(2)
                        kk = k - self%kfromto(1) + 1
                        self%ft_ref_bins(kk, iref, j, ieo)           = conjg(self%ft_ref2(j, k, iref, ieo))
                        self%ft_ref_bins(self%nk + kk, iref, j, ieo) = self%ft_ref(j, k, iref, ieo)
                    end do
                end do
            end do
        end do
        !$omp end parallel do
    end subroutine host_ref_bins

    module subroutine kill_ref_bins( self )
        class(polarft_calc), intent(inout) :: self
        integer :: ieo
        self%msg          = ''
        self%ref_gen_bins = -1_int64
        self%slot_ieo     = 0
        if( allocated(self%ft_ref_bins) ) deallocate(self%ft_ref_bins)
        if( .not. allocated(self%ws) ) return
        do ieo = 1, size(self%ws)
            call self%ws(ieo)%kill()
        end do
    end subroutine kill_ref_bins

    pure module logical function ref_bins_current( self )
        class(polarft_calc), intent(in) :: self
        ref_bins_current = self%existence .and. self%ref_gen_bins == self%ref_gen
    end function ref_bins_current

end submodule mlxf_toy_polarft_memo
