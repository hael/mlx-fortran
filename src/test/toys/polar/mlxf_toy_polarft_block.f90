!@descr: the toy polar calculator's block scoring: score_block_posterior with SIMPLE's block kernel, and the blocks in flight
! A block is the particles of one half against references of that parity. On the host backend
! score_block_posterior is a miniature of SIMPLE's kernel, in single precision: per tile of PFTC_BLOCK_NR
! references both sums of every angular bin over the 2nk shell terms, each pair's inverse transform (a direct
! sum; SIMPLE plans an FFT), the distances and the draw from the posterior with the pair's keyed variate. It is
! thread-safe: a thread writes its own work and its block's entries, nothing else. On the MLX backend the glue
! queues the block in the parity's workspace and the entries come back at collection.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_block
!$ use omp_lib,     only: omp_get_thread_num, omp_in_parallel
use mlxf_test_defs, only: POLAR_DIST_MAX, POLAR_DIST_INVALID, POLAR_DIST_VALID, POLAR_ARG_CUTOFF
implicit none

! why the host kernel cannot score a block (block_refusal's codes)
character(len=*), parameter :: BLOCK_REFUSALS(15) = [character(len=120) :: &
    &'polarft_calc: refused: no calculator on the host backend (new)', &
    &'polarft_calc: refused: references were set and not memoized (memoize_refs)', &
    &'polarft_calc: refused: the reference tiles are not those of the memoized references and tile plan (memoize_refs)', &
    &'polarft_calc: refused: the particle memos are not those of the particles set (memoize_ptcls)', &
    &'polarft_calc: refused: no shell weights (set_sigma2_weights)', &
    &'polarft_calc: refused: no keys of the draws (set_draw_keys)', &
    &'polarft_calc: refused: the team exceeds the block kernel''s work (the parameters'' nthr)', &
    &'polarft_calc%score_block_posterior: refused: a block holds 1 to PFTC_BLOCK_NB particles', &
    &'polarft_calc%score_block_posterior: refused: a reference is outside 1..nrefs', &
    &'polarft_calc%score_block_posterior: refused: banks and l_bank go together, the banks (2nk, pftsz+1, nb)', &
    &'polarft_calc: refused: a particle index is outside the calculator''s range', &
    &'polarft_calc: refused: a particle index is not in the batch', &
    &'polarft_calc: refused: the block mixes the two halves', &
    &'polarft_calc: refused: an empty reference list', &
    &'polarft_calc: refused: the reference list repeats a reference']

contains

    module subroutine score_block_posterior( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )
        class(polarft_calc),       intent(inout) :: self
        integer,                   intent(in)    :: nb, nr
        integer,                   intent(in)    :: iptcls(nb), irefs(nr)
        real(real32),              intent(in)    :: temps(nb)
        real(real32),              intent(out)   :: dists(nr, nb)
        integer,                   intent(out)   :: irots(nr, nb)
        complex(real32), optional, intent(in)    :: banks(:,:,:)
        logical,         optional, intent(in)    :: l_bank(nb)
        complex(real32) :: acc
        real(real64)    :: u
        integer         :: ithr, why, i, i1, ieo, b, j, kk, n1, r0, nt, ir, iref, irot
        logical         :: l_serial, l_banks, l_b
        if( self%l_mlx )then
            call score_block_posterior_mlx(self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank)
            return
        endif
        dists    = huge(dists)
        irots    = 1
        ithr     = 1
        l_serial = .true.
        !$ ithr     = omp_get_thread_num() + 1
        !$ l_serial = .not. omp_in_parallel()
        l_banks = present(banks)
        why     = block_refusal(self, iptcls, irefs, ithr)
        if( why == 0 .and. (l_banks .neqv. present(l_bank)) ) why = 10
        if( why == 0 .and. l_banks )then
            if( size(banks, 1) /= 2 * self%nk .or. size(banks, 2) /= self%pftsz + 1 .or. size(banks, 3) < nb ) why = 10
        endif
        ! where SIMPLE stops, the entries stay invalid; the reason is kept when no other thread can be writing it
        if( l_serial )then
            self%msg = ''
            if( why /= 0 ) self%msg = trim(BLOCK_REFUSALS(why))
        endif
        if( why /= 0 ) return
        n1  = self%pftsz + 1
        i1  = self%pinds(iptcls(1))
        ieo = merge(REF_EVEN, REF_ODD, self%iseven(i1))
        associate( bw => self%bwork(ithr) )
            ! the particle terms of every bin, copied from the memo (or the seed bank): rows 1..nk w_k FT(CTF2),
            ! rows nk+1..2nk -2 w_k FT(X.CTF)
            do b = 1, nb
                i           = self%pinds(iptcls(b))
                bw%norms(b) = self%wsqsums_ptcls(i) * real(2 * self%nrots, real64)
                l_b         = .false.
                if( l_banks ) l_b = l_bank(b)
                do j = 1, n1
                    if( l_b )then
                        bw%pterms(:, b, j) = banks(:, j, b)
                    else
                        bw%pterms(:, b, j) = self%ft_ptcl_wterms(:, j, i)
                    endif
                end do
            end do
            do r0 = 1, nr, PFTC_BLOCK_NR
                nt = min(PFTC_BLOCK_NR, nr - r0 + 1)
                ! D(b, ir) = sum_k conj(P(k, b)) G(k, ir) of every bin, the conjugate of the pair's sums; G is the
                ! reference's memo, read in place
                do j = 1, n1
                    do ir = 1, nt
                        iref = irefs(r0 + ir - 1)
                        do b = 1, nb
                            acc = cmplx(0._real32, 0._real32, real32)
                            do kk = 1, 2 * self%nk
                                acc = acc + conjg(bw%pterms(kk, b, j)) * self%ft_ref_terms(kk, j, iref, ieo)
                            end do
                            bw%prods(b, ir, j) = acc
                        end do
                    end do
                end do
                ! each pair's bins (the conjugate back), its inverse transform, its distances and its keyed draw
                do b = 1, nb
                    do ir = 1, nt
                        iref  = irefs(r0 + ir - 1)
                        bw%ct = conjg(bw%prods(b, ir, :))
                        call ring_inverse(self%idft_e, bw%ct, bw%out)
                        u = keyed_variate(self%rnd_seed, iptcls(b), self%ref_full(iref))
                        call euclid_dists_from_crvec(bw%out, bw%norms(b), bw%rot_dists)
                        ! a row without a valid rotation keeps rotation 1 at the invalid marker
                        call draw_posterior_row(bw%rot_dists, temps(b), bw%rot_cdf, u, irot)
                        if( irot > 0 )then
                            irots(r0 + ir - 1, b) = irot
                            dists(r0 + ir - 1, b) = bw%rot_dists(irot)
                        endif
                        if( self%l_rows ) bw%rows(:, r0 + ir - 1, b) = bw%rot_dists
                    end do
                end do
            end do
            bw%last = [nr, nb]
        end associate
    end subroutine score_block_posterior

    ! the code of the reason a block cannot be scored by the host kernel on thread ithr, 0 when it can
    ! (BLOCK_REFUSALS); it reads the calculator and writes nothing
    pure integer function block_refusal( self, iptcls, irefs, ithr ) result(why)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: iptcls(:), irefs(:), ithr
        integer :: b, i
        why = 0
        if( .not. self%existence .or. .not. allocated(self%bwork) )then
            why = 1
        else if( self%l_refs_pending )then
            why = 2
        else if( self%ref_gen_tiles /= self%ref_gen )then
            why = 3
        else if( self%ptcl_gen_memo /= self%ptcl_gen )then
            why = 4
        else if( .not. self%l_weights )then
            why = 5
        else if( .not. self%l_keys )then
            why = 6
        endif
        if( why /= 0 ) return
        if( ithr > size(self%bwork) )then
            why = 7
        else if( size(iptcls) < 1 .or. size(iptcls) > PFTC_BLOCK_NB )then
            why = 8
        else if( any(irefs < 1 .or. irefs > self%nrefs) )then
            why = 9
        else if( any(iptcls < self%pfromto(1) .or. iptcls > self%pfromto(2)) )then
            why = 11
        else if( size(irefs) < 1 )then
            why = 14
        else if( has_repeat(irefs, self%nrefs) )then
            why = 15
        endif
        if( why /= 0 ) return
        do b = 1, size(iptcls)
            i = self%pinds(iptcls(b))
            if( i < 1 )then
                why = 12
                return
            endif
            if( self%iseven(i) .neqv. self%iseven(self%pinds(iptcls(1))) ) why = 13
        end do
    end function block_refusal

    ! whether a list of references of 1..nrefs holds one twice
    pure logical function has_repeat( irefs, nrefs )
        integer, intent(in) :: irefs(:), nrefs
        logical :: seen(nrefs)
        integer :: r
        has_repeat = .false.
        seen       = .false.
        do r = 1, size(irefs)
            if( seen(irefs(r)) )then
                has_repeat = .true.
                return
            endif
            seen(irefs(r)) = .true.
        end do
    end function has_repeat

    pure module function block_list_refusal( self, irefs ) result(msg)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: irefs(:)
        character(len=:), allocatable :: msg
        msg = ''
        if( size(irefs) < 1 )then
            msg = trim(BLOCK_REFUSALS(14))
        else if( any(irefs < 1 .or. irefs > self%nrefs) )then
            msg = trim(BLOCK_REFUSALS(9))
        else if( has_repeat(irefs, self%nrefs) )then
            msg = trim(BLOCK_REFUSALS(15))
        endif
    end function block_list_refusal

    ! the nrots samples of the inverse real transform of a pair's pftsz+1 bins, unscaled, as a direct sum: the
    ! first and the last bin once (their imaginary parts are ignored, as an inverse real transform ignores them),
    ! the others twice
    pure subroutine ring_inverse( e, c, r )
        complex(real32), intent(in)  :: e(:,:), c(:)
        real(real32),    intent(out) :: r(:)
        real(real32) :: acc
        integer      :: n, p, n1
        n1 = size(c)
        do n = 1, size(r)
            acc = real(c(1)) + real(c(n1)) * real(e(n1, n))
            do p = 2, n1 - 1
                acc = acc + 2._real32 * (real(c(p)) * real(e(p, n)) - aimag(c(p)) * aimag(e(p, n)))
            end do
            r(n) = acc
        end do
    end subroutine ring_inverse

    ! SIMPLE's euclid_dists_from_crvec: the distances of the rotations from a pair's inverse transform, the invalid
    ! marker above the invalid distance
    pure subroutine euclid_dists_from_crvec( r, norm, dists )
        real(real32), intent(in)  :: r(:)
        real(real64), intent(in)  :: norm
        real(real32), intent(out) :: dists(:)
        real(real64) :: v
        integer      :: p
        do p = 1, size(r)
            v        = 1._real64 + real(r(p), real64) / norm
            dists(p) = real(min(v, POLAR_DIST_MAX), real32)
            if( v > POLAR_DIST_MAX ) dists(p) = POLAR_DIST_INVALID
        end do
    end subroutine euclid_dists_from_crvec

    ! SIMPLE's draw_posterior_row: one rotation from the posterior over a row at the inverse temperature temp, p_r
    ! proportional to exp(-temp (dist_r - dist_min)) over the valid distances (weights below
    ! exp(-POLAR_ARG_CUTOFF) are zero): the first rotation whose cumulative weight reaches u times the sum, else the
    ! minimising one; 0 when no distance is valid. w is the work array
    pure subroutine draw_posterior_row( dists, temp, w, u, which )
        real(real32), intent(in)    :: dists(:), temp
        real(real32), intent(inout) :: w(:)
        real(real64), intent(in)    :: u
        integer,      intent(out)   :: which
        real(real64) :: wsum, csum, tgt, arg
        real(real32) :: dmin
        integer      :: r, imin
        which = 0
        imin  = 0
        dmin  = huge(dmin)
        do r = 1, size(dists)
            if( dists(r) < POLAR_DIST_VALID .and. dists(r) < dmin )then
                dmin = dists(r)
                imin = r
            endif
        end do
        if( imin == 0 ) return
        wsum = 0._real64
        do r = 1, size(dists)
            w(r) = 0._real32
            if( dists(r) < POLAR_DIST_VALID )then
                arg = real(max(0._real32, temp), real64) * real(dists(r) - dmin, real64)
                if( arg < real(POLAR_ARG_CUTOFF, real64) )then
                    w(r) = real(exp(-arg), real32)
                    wsum = wsum + real(w(r), real64)
                endif
            endif
        end do
        tgt  = u * wsum
        csum = 0._real64
        do r = 1, size(dists)
            if( w(r) <= 0._real32 ) cycle
            csum = csum + real(w(r), real64)
            if( csum >= tgt )then
                which = r
                exit
            endif
        end do
        if( which == 0 ) which = imin
    end subroutine draw_posterior_row

    module subroutine new_block_work( self, nthr_team )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: nthr_team
        real(real64) :: angle
        integer      :: ithr, n1, p, n
        call kill_block_work(self)
        n1 = self%pftsz + 1
        allocate(self%bwork(nthr_team))
        do ithr = 1, nthr_team
            allocate(self%bwork(ithr)%pterms(2 * self%nk, PFTC_BLOCK_NB, n1), &
                &self%bwork(ithr)%prods(PFTC_BLOCK_NB, PFTC_BLOCK_NR, n1), self%bwork(ithr)%ct(n1), &
                &self%bwork(ithr)%out(self%nrots), self%bwork(ithr)%norms(PFTC_BLOCK_NB), &
                &self%bwork(ithr)%rot_dists(self%nrots), self%bwork(ithr)%rot_cdf(self%nrots))
        end do
        ! the inverse transform's factors (positive exponent), computed in double precision and rounded once
        allocate(self%idft_e(n1, self%nrots))
        do n = 1, self%nrots
            do p = 1, n1
                angle = 2._real64 * acos(-1._real64) * real(mod((p - 1) * (n - 1), self%nrots), real64) / &
                    &real(self%nrots, real64)
                self%idft_e(p, n) = cmplx(cos(angle), sin(angle), real32)
            end do
        end do
    end subroutine new_block_work

    module subroutine kill_block_work( self )
        class(polarft_calc), intent(inout) :: self
        if( allocated(self%bwork) ) deallocate(self%bwork)
        if( allocated(self%idft_e) ) deallocate(self%idft_e)
    end subroutine kill_block_work

    pure module function keyed_variate( seed, iptcl, iref ) result(u)
        integer, intent(in) :: seed, iptcl, iref
        real(real64)              :: u
        integer(int64), parameter :: M = 2147483647_int64, A = 48271_int64
        integer(int64)            :: x
        integer                   :: i
        x = mod(int(seed, int64) * 1000003_int64 + int(iptcl, int64) * 7919_int64 + int(iref, int64) * 104729_int64, M)
        if( x == 0_int64 ) x = 1_int64
        do i = 1, 4
            x = mod(A * x, M)
        end do
        u = real(x - 1_int64, real64) / real(M - 1_int64, real64)
    end function keyed_variate

    module subroutine set_draw_keys( self, seed, ref_full )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: seed
        integer,             intent(in)    :: ref_full(:)
        if( .not. self%existence )then
            self%msg = 'polarft_calc%set_draw_keys: refused: no calculator (new)'
            return
        endif
        if( size(ref_full) /= self%nrefs )then
            self%msg = 'polarft_calc%set_draw_keys: refused: one full index per reference'
            return
        endif
        self%msg      = ''
        self%rnd_seed = seed
        self%ref_full = ref_full
        self%l_keys   = .true.
    end subroutine set_draw_keys

    module subroutine check_block_work( self, nthr_team )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: nthr_team
        integer :: why
        self%msg = ''
        if( self%l_mlx )then
            self%msg = 'polarft_calc%check_block_work: refused: the calculator is on the MLX backend, whose blocks '// &
                &'one thread submits'
            return
        endif
        why = block_refusal(self, [integer ::], [integer ::], nthr_team)
        ! an empty block tells only whether the calculator and its team's work are ready
        if( why == 8 ) why = 0
        if( why /= 0 ) self%msg = trim(BLOCK_REFUSALS(why))
    end subroutine check_block_work

    module subroutine set_block_variates( self, u )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(inout) :: u(:,:)
        self%msg = ''
        if( allocated(self%u_next) ) deallocate(self%u_next)
        if( allocated(u) ) call move_alloc(u, self%u_next)
    end subroutine set_block_variates

    module subroutine set_block_refs( self, irefs )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: irefs(:)
        if( allocated(self%refs_next) ) deallocate(self%refs_next)
        self%msg = block_list_refusal(self, irefs)
        if( len(self%msg) == 0 ) self%refs_next = irefs
    end subroutine set_block_refs

    module subroutine set_block_pairs( self, ptr, irefs )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: ptr(:), irefs(:)
        integer :: nb
        if( allocated(self%refs_next) ) deallocate(self%refs_next)
        if( allocated(self%pair_ptr_next) ) deallocate(self%pair_ptr_next)
        self%msg = ''
        nb       = size(ptr) - 1
        if( nb < 1 .or. size(irefs) < 1 )then
            self%msg = 'polarft_calc%set_block_pairs: refused: a pair at least'
        else if( ptr(1) /= 1 .or. ptr(nb + 1) /= size(irefs) + 1 .or. any(ptr(2:) < ptr(:nb)) )then
            self%msg = 'polarft_calc%set_block_pairs: refused: the pointers are not a partition of the references'
        else if( any(irefs < 1 .or. irefs > self%nrefs) )then
            self%msg = trim(BLOCK_REFUSALS(9))
        endif
        if( len(self%msg) > 0 ) return
        self%pair_ptr_next = ptr
        self%refs_next     = irefs
    end subroutine set_block_pairs

    module subroutine set_block_banks( self, banks, l_bank )
        class(polarft_calc), intent(inout) :: self
        complex(real32),     intent(in)    :: banks(:,:,:)
        logical,             intent(in)    :: l_bank(:)
        self%msg         = ''
        self%banks_next  = banks
        self%l_bank_next = l_bank
    end subroutine set_block_banks

    module subroutine shifted_ptcl_terms( self, iptcl, xctf, bank )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        complex(real32),     intent(in)    :: xctf(:,:)
        complex(real32),     intent(out)   :: bank(2 * self%nk, self%pftsz + 1)
        real(real32) :: wk
        integer      :: i, ih, j, kk
        bank = cmplx(0._real32, 0._real32, real32)
        i    = ptcl_slot(self, iptcl)
        if( i == 0 )then
            self%msg = 'polarft_calc%shifted_ptcl_terms: refused: the particle is not in the batch'
            return
        endif
        if( size(xctf, 1) /= self%pftsz + 1 .or. size(xctf, 2) /= self%nk )then
            self%msg = 'polarft_calc%shifted_ptcl_terms: refused: the shifted transform is not (pftsz+1, shells)'
            return
        endif
        self%msg = ''
        ih       = merge(REF_EVEN, REF_ODD, self%iseven(i))
        do j = 1, self%pftsz + 1
            do kk = 1, self%nk
                wk = self%sigma2_wk(self%kfromto(1) + kk - 1, ih)
                bank(kk, j)           = self%ft_ptcl_wterms(kk, j, i)
                bank(self%nk + kk, j) = (-2._real32 * wk) * xctf(j, kk)
            end do
        end do
    end subroutine shifted_ptcl_terms

    module subroutine set_block_options( self, rows, profile )
        class(polarft_calc), intent(inout) :: self
        logical,             intent(in)    :: rows, profile
        integer :: ithr
        self%msg       = ''
        self%l_rows    = rows
        self%l_profile = profile
        ! the host kernel keeps a thread's rows in that thread's work
        if( .not. allocated(self%bwork) ) return
        do ithr = 1, size(self%bwork)
            if( allocated(self%bwork(ithr)%rows) ) deallocate(self%bwork(ithr)%rows)
            if( rows ) allocate(self%bwork(ithr)%rows(self%nrots, self%nrefs, PFTC_BLOCK_NB))
            self%bwork(ithr)%last = 0
        end do
    end subroutine set_block_options

    module subroutine submit_block( self, slot, nb, iptcls, temps )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot, nb
        integer,             intent(in)    :: iptcls(nb)
        real(real32),        intent(in)    :: temps(nb)
        type(polarft_block_spec) :: blk
        self%msg  = ''
        blk%slot  = slot
        blk%temps = temps
        if( self%l_mlx )then
            call submit_block_mlx(self, blk, iptcls)
        else
            self%msg = 'polarft_calc%submit_block: refused: a block is in flight on the MLX backend only'
        endif
    end subroutine submit_block

    module subroutine collect_block( self, slot, dists, irots )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot
        real(real32),        intent(inout) :: dists(:,:)
        integer,             intent(inout) :: irots(:,:)
        integer :: ieo
        self%msg = ''
        if( slot < 1 .or. slot > NSLOTS )then
            self%msg = 'polarft_calc%collect_block: refused: no such slot'
            return
        endif
        ieo = self%slot_ieo(slot)
        if( ieo == 0 .or. .not. self%existence )then
            self%msg = 'polarft_calc%collect_block: refused: the slot holds no block'
            return
        endif
        self%slot_ieo(slot) = 0
        if( self%l_mlx ) call collect_block_mlx(self, slot, ieo, dists, irots)
    end subroutine collect_block

    module subroutine block_rows( self, rows )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: rows(:,:,:)
        integer :: ithr
        self%msg = ''
        if( self%l_mlx )then
            if( allocated(self%rows) ) call move_alloc(self%rows, rows)
            return
        endif
        ithr = 1
        !$ ithr = omp_get_thread_num() + 1
        if( .not. allocated(self%bwork) ) return
        if( ithr > size(self%bwork) ) return
        associate( bw => self%bwork(ithr) )
            if( allocated(bw%rows) .and. all(bw%last > 0) ) rows = bw%rows(:, 1:bw%last(1), 1:bw%last(2))
        end associate
    end subroutine block_rows

    module subroutine copy_block_rows( self, rows )
        class(polarft_calc), intent(inout) :: self
        real(real32),        intent(inout) :: rows(:,:,:)
        integer :: ithr
        ithr = 1
        !$ ithr = omp_get_thread_num() + 1
        if( .not. allocated(self%bwork) ) return
        if( ithr > size(self%bwork) ) return
        associate( bw => self%bwork(ithr) )
            if( .not. allocated(bw%rows) ) return
            if( size(rows, 1) /= size(bw%rows, 1) .or. size(rows, 2) > bw%last(1) .or. size(rows, 3) > bw%last(2) ) return
            rows = bw%rows(:, 1:size(rows, 2), 1:size(rows, 3))
        end associate
    end subroutine copy_block_rows

    pure module function stage_seconds( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(5)
        t = 0._real64
        if( self%l_mlx ) t = stage_seconds_mlx(self)
    end function stage_seconds

end submodule mlxf_toy_polarft_block
