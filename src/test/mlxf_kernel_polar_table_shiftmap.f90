!@descr: the particle-reusing shift-map contraction, the direction transform and requested posterior outputs
! The particle carries the order shift Y[m'+n], shared across candidates. Shell sums contract the particle's
! spectra, weighted by the real Bessel weights, with every candidate's over the shells: one product per tile.
! The ring FFT needs the phase exp(-2 pi i n r/nrots); folded orders then sample the original direction grid.
! Mode selection uses tempered temperature, physical moments may be cut off, and evidence is optional.
submodule (mlxf_kernel_polar_table) mlxf_kernel_polar_table_shiftmap
use, intrinsic :: iso_fortran_env, only: int32
use mlxf,           only: mlx_compile, mlx_from, mlx_to, mlx_eval, mlx_permute, reshape, matmul, mlx_irfft, mlx_fft, &
                          mlx_concatenate, mlx_slice, mlx_take_along_dim, mlx_take, mlx_bitcast, MLX_DTYPES, merge, &
                          minval, minloc, sum, sqrt, exp, real, aimag, mlx_logsumexp, max
use mlxf_test_defs, only: POLAR_BESSEL_JTOL, POLAR_MAP_LOG_CUT
implicit none

! the device arrays every tile of a block shares: the particles' full-ring spectra, real parts then imaginary
! parts along the shells (nrots, 2 nkb, nptcls), and
! band CTF memos (pftsz+1, nkb, nptcls), the rotations' cosines and sines (nrots, 1), the particle's ring index
! shifted by each order, (m' + n) modulo nrots (nrots, 1, 1, norder+1)
type :: map_shared
    type(mlx_array) :: ydev
    type(mlx_array) :: c2dev
    type(mlx_array) :: cosr
    type(mlx_array) :: sinr
    type(mlx_array) :: shiftidx
end type map_shared

! one tile of particles with every candidate of each: the particles' places in the block and their candidates'
! places in the prepared list (ncand, particles), and per pair (candidate fastest) its reference's place and
! particle (inputs); the flat mode index, loss, width and log evidence per pair, and the maps when asked (outputs)
type :: map_tile
    integer,      allocatable :: ptcls(:)
    integer,      allocatable :: cands(:,:)
    integer,      allocatable :: pref(:)
    integer,      allocatable :: pptcl(:)
    integer,      allocatable :: idx(:)
    real(real32), allocatable :: loss(:)
    real(real32), allocatable :: sdev(:)
    real(real32), allocatable :: logz(:)
    real(real32), allocatable :: maps(:,:,:,:)
end type map_tile

contains

    module subroutine polar_table_prepare_maps( self, refs, spec, status )
        class(polar_table),     intent(inout) :: self
        type(polar_table_refs), intent(in)    :: refs
        type(polar_map_spec),   intent(in)    :: spec
        integer,                intent(out)   :: status
        complex(real32), allocatable :: rfull(:,:,:), ephase(:,:,:)
        real(real32),    allocatable :: wres(:,:,:), cellx(:,:,:), celly(:,:,:), cellr2(:,:,:), cellprior(:,:,:)
        real(real64),    allocatable :: area(:), jn(:)
        real(real64)                 :: alpha, lmax, s, fac
        integer,         allocatable :: nharm(:)
        type(mlx_function)           :: ftail
        integer                      :: nkb, nrho, nalpha, norder, n1, r, k, m, n, ir, j, ierr
        status = 1
        ! the previous maps go first: a refused or failed preparation leaves no maps, the scoring intact
        call polar_table_drop_maps(self)
        call check_map_spec(self, refs, spec, self%msg)
        if( len(self%msg) > 0 ) return
        n1     = self%pftsz + 1
        nkb    = spec%kstop - spec%kfrom + 1
        nrho   = size(spec%rho)
        nalpha = spec%nalpha
        ! the orders each radius keeps (SIMPLE's truncation at the band's last shell), and the largest
        allocate(nharm(nrho))
        do ir = 1, nrho
            nharm(ir) = harmonic_order(2._real64 * acos(-1._real64) * real(spec%kstop, real64) * spec%rho(ir) / &
                &real(spec%box, real64))
        end do
        norder = maxval(nharm)
        ! the references' full-ring spectra over the band, F[nrots - m] = (-1)^m conj(F[m]), laid out (shell, ring
        ! position, reference): a candidate's spectra are one contiguous slab
        allocate(rfull(nkb, self%nrots, self%nrefs), stat=ierr)
        if( ierr /= 0 )then
            self%msg = 'polar_table%prepare_maps: the host staging of the reference spectra could not be allocated'
            return
        endif
        do r = 1, self%nrefs
            do k = 1, nkb
                rfull(k, 1:n1, r) = refs%ft_ref(:, k, r)
                do m = 1, self%pftsz - 1
                    rfull(k, self%nrots - m + 1, r) = real(1 - 2 * mod(m, 2), real32) * conjg(refs%ft_ref(m + 1, k, r))
                end do
            end do
        end do
        ! the Bessel weights fac_n w_k J_n(2 pi k rho / box) of the orders each radius keeps (zero beyond), real64
        ! rounded once (order 0 enters with a half), laid out (shell, order, radius); and the phase of the order's
        ! shift at rotation r, exp(-2 pi i n r / nrots), laid out (order, rotation)
        allocate(wres(nkb, norder + 1, nrho), ephase(norder + 1, 1, self%nrots), jn(0:norder))
        do r = 1, self%nrots
            do n = 0, norder
                alpha = -2._real64 * acos(-1._real64) * real(n, real64) * real(r - 1, real64) / real(self%nrots, real64)
                ephase(n + 1, 1, r) = cmplx(cos(alpha), sin(alpha), real32)
            end do
        end do
        do ir = 1, nrho
            do k = 1, nkb
                jn = bessel_jn(0, norder, 2._real64 * acos(-1._real64) * real(spec%kfrom + k - 1, real64) * &
                    &spec%rho(ir) / real(spec%box, real64))
                do n = 0, norder
                    fac = 1._real64
                    if( n == 0 ) fac = 0.5_real64
                    if( n > nharm(ir) ) fac = 0._real64
                    wres(k, n + 1, ir) = real(fac * spec%weights(k) * jn(n), real32)
                end do
            end do
        end do
        ! the cells: shift components, squared radius, and prior with the log area of one cell per radius
        area = cell_areas(spec%rho, nalpha)
        allocate(cellx(nalpha, 1, nrho), celly(nalpha, 1, nrho), cellr2(1, 1, nrho), cellprior(1, 1, nrho))
        do ir = 1, nrho
            do j = 1, nalpha
                alpha          = 2._real64 * acos(-1._real64) * real(j - 1, real64) / real(nalpha, real64)
                cellx(j, 1, ir) = real(spec%rho(ir) * cos(alpha), real32)
                celly(j, 1, ir) = real(spec%rho(ir) * sin(alpha), real32)
            end do
            cellr2(1, 1, ir)    = real(spec%rho(ir)**2, real32)
            cellprior(1, 1, ir) = real(-spec%prior_w * spec%rho(ir)**2 + log(area(ir)), real32)
        end do
        ! the prior's log normaliser over every cell (direction, rotation, radius)
        lmax = maxval(-spec%prior_w * spec%rho**2 + log(area))
        s    = 0._real64
        do ir = 1, nrho
            if( -spec%prior_w * spec%rho(ir)**2 + log(area(ir)) - lmax > POLAR_MAP_LOG_CUT ) s = s + &
                &real(self%nrots, real64) * real(nalpha, real64) * exp(-spec%prior_w * spec%rho(ir)**2 + &
                &log(area(ir)) - lmax)
        end do
        self%rfull     = mlx_from(rfull)
        self%ref2b     = mlx_from(refs%ft_ref2(:, 1:nkb, :))
        self%wfold     = mlx_from(reshape(wres, [nkb, 1, norder + 1, nrho, 1, 1]))
        self%ffold     = mlx_from(reshape(ephase, [1, norder + 1, 1, self%nrots, 1]))
        self%wband     = mlx_from(reshape(real(spec%weights, real32), [1, nkb, 1]))
        self%cellx     = mlx_from(reshape(cellx, [nalpha, 1, nrho, 1]))
        self%celly     = mlx_from(reshape(celly, [nalpha, 1, nrho, 1]))
        self%cellr2    = mlx_from(reshape(cellr2, [1, 1, nrho, 1]))
        self%cellprior = mlx_from(reshape(cellprior, [1, 1, nrho, 1]))
        call mlx_eval([self%rfull, self%ref2b, self%wfold, self%ffold, self%wband, self%cellx, self%celly, self%cellr2, &
            &self%cellprior], status=ierr)
        if( ierr /= 0 )then
            self%msg = 'polar_table%prepare_maps: the maps'' resident data could not be evaluated'
            call polar_table_drop_maps(self)
            return
        endif
        ! the selection and the reduction of a tile's maps, each compiled into one graph per tile shape
        ftail           = mlx_function(map_select_callback)
        self%map_select = mlx_compile(ftail, shapeless=.false.)
        ftail           = mlx_function(map_reduce_callback)
        self%map_reduce = mlx_compile(ftail, shapeless=.false.)
        ftail           = mlx_function(map_evidence_callback)
        self%map_evidence = mlx_compile(ftail, shapeless=.false.)
        self%map_nkb       = nkb
        self%map_nrho      = nrho
        self%map_nalpha    = nalpha
        self%map_norder    = norder
        self%map_lse_prior = lmax + log(s)
        self%map_rho       = spec%rho
        self%map_nharm     = nharm
        self%maps_ready    = .true.
        status             = 0
    end subroutine polar_table_prepare_maps

    ! the reason the maps cannot be prepared, or an empty string
    subroutine check_map_spec( self, refs, spec, msg )
        class(polar_table),            intent(in)  :: self
        type(polar_table_refs),        intent(in)  :: refs
        type(polar_map_spec),          intent(in)  :: spec
        character(len=:), allocatable, intent(out) :: msg
        msg = ''
        if( .not. self%prepared )then
            msg = 'polar_table%prepare_maps: refused: no prepared references'
        else if( refs%generation /= self%generation .or. refs%half /= self%half )then
            msg = 'polar_table%prepare_maps: refused: the references are not the prepared ones (generation, half)'
        else if( .not. allocated(refs%ids) .or. .not. allocated(refs%ft_ref) .or. .not. allocated(refs%ft_ref2) )then
            msg = 'polar_table%prepare_maps: refused: the references lack their memos'
        else if( spec%box < 2 .or. spec%nalpha < 1 .or. spec%kfrom < 1 )then
            msg = 'polar_table%prepare_maps: the grid needs a box, a first shell and a direction'
        else if( spec%kstop < spec%kfrom .or. spec%kstop - spec%kfrom + 1 > self%nk )then
            msg = 'polar_table%prepare_maps: the band must lie in the references'' shells'
        else if( .not. allocated(spec%rho) .or. .not. allocated(spec%weights) )then
            msg = 'polar_table%prepare_maps: the grid lacks its radii or the band its weights'
        else if( spec%prior_w < 0._real64 )then
            msg = 'polar_table%prepare_maps: the prior''s weight is not negative'
        endif
        if( len(msg) > 0 ) return
        if( size(refs%ids) /= self%nrefs )then
            msg = 'polar_table%prepare_maps: refused: the references are not the prepared ones (list)'
        else if( any(refs%ids /= self%ids) )then
            msg = 'polar_table%prepare_maps: refused: the references are not the prepared ones (list)'
        else if( refs%pftsz /= self%pftsz .or. refs%nk /= self%nk )then
            msg = 'polar_table%prepare_maps: refused: the references'' geometry (pftsz, nk) is not the prepared one'
        else if( any(shape(refs%ft_ref) /= [self%pftsz + 1, self%nk, self%nrefs]) .or. &
            &any(shape(refs%ft_ref2) /= [self%pftsz + 1, self%nk, self%nrefs]) )then
            msg = 'polar_table%prepare_maps: refused: the reference memos are not (pftsz+1, nk, references)'
        else if( size(spec%rho) < 1 .or. size(spec%weights) /= spec%kstop - spec%kfrom + 1 )then
            msg = 'polar_table%prepare_maps: the grid needs a radius and one weight per band shell'
        else if( any(spec%rho < 0._real64) )then
            msg = 'polar_table%prepare_maps: the radii are not negative'
        else if( size(spec%rho) > 1 )then
            if( any(spec%rho(2:) <= spec%rho(:size(spec%rho)-1)) ) &
                &msg = 'polar_table%prepare_maps: the radii ascend strictly'
        endif
    end subroutine check_map_spec

    ! the highest order kept at argument z, SIMPLE's rule: J_n(z) falls with n past z, so the orders from the
    ! first one at or past z whose |J_n(z)| is below POLAR_BESSEL_JTOL on are dropped
    integer function harmonic_order( z )
        real(real64), intent(in) :: z
        integer :: n
        n = max(0, ceiling(z))
        do while( abs(bessel_jn(n, z)) >= POLAR_BESSEL_JTOL )
            n = n + 1
        end do
        harmonic_order = max(0, n - 1)
    end function harmonic_order

    ! the translation area of one cell at each radius: the ring between the midpoints to the neighbouring radii
    ! (the edges half a step beyond the smallest and the largest, never below zero) over the directions; the
    ! radii are ascending
    pure function cell_areas( rho, nalpha ) result(area)
        real(real64), intent(in) :: rho(:)
        integer,      intent(in) :: nalpha
        real(real64) :: area(size(rho))
        real(real64) :: lo(size(rho)), hi(size(rho))
        integer      :: nr
        nr = size(rho)
        if( nr == 1 )then
            lo(1) = max(0._real64, rho(1) - 0.5_real64 * max(rho(1), 1._real64))
            hi(1) = rho(1) + 0.5_real64 * max(rho(1), 1._real64)
        else
            lo(1)    = max(0._real64, rho(1) - 0.5_real64 * (rho(2) - rho(1)))
            lo(2:nr) = 0.5_real64 * (rho(1:nr-1) + rho(2:nr))
            hi(1:nr-1) = lo(2:nr)
            hi(nr)     = rho(nr) + 0.5_real64 * (rho(nr) - rho(nr-1))
        endif
        area = acos(-1._real64) * (hi * hi - lo * lo) / real(nalpha, real64)
    end function cell_areas

    pure module integer function map_order( self )
        class(polar_table), intent(in) :: self
        map_order = self%map_norder
    end function map_order

    pure module function map_term_counts( self ) result(counts)
        class(polar_table), intent(in) :: self
        integer(int64) :: counts(2)
        counts = 0_int64
        if( .not. self%maps_ready ) return
        counts(1) = sum(int(self%map_nharm + 1, int64))
        counts(2) = int(self%map_norder + 1, int64) * int(self%map_nrho, int64)
    end function map_term_counts

    pure module function map_seconds( self ) result(t)
        class(polar_table), intent(in) :: self
        real(real64) :: t(4)
        t = self%mstage_s
    end function map_seconds

    module subroutine polar_table_score_maps( self, mblk, res, status )
        class(polar_table),      intent(inout) :: self
        type(polar_map_block),   intent(in)    :: mblk
        type(polar_map_results), intent(out)   :: res
        integer,                 intent(out)   :: status
        complex(real32), allocatable :: yfull(:,:,:)
        real(real32),    allocatable :: ypk(:,:,:)
        integer,         allocatable :: pos(:,:)
        real(real32)                 :: cs(self%nrots), sn(self%nrots)
        type(map_shared)             :: sh
        type(map_tile)               :: tl
        integer                      :: nb, ncand, n1, b, c, m, k, b0, b1, pt, p, i
        status = 1
        call check_map_block(self, mblk, self%msg)
        if( len(self%msg) > 0 ) return
        n1     = self%pftsz + 1
        nb     = size(mblk%ptcl_ids)
        ncand  = size(mblk%cands, 1)
        ! the candidates' places in the prepared list (the check has found every one)
        allocate(pos(ncand, nb))
        do b = 1, nb
            do c = 1, ncand
                pos(c, b) = findloc(self%ids, mblk%cands(c, b), dim=1)
            end do
        end do
        ! the particles' full-ring spectra over the band, conjugated: Y^[m] = conj(F[m]), Y^[nrots - m] = (-1)^m F[m]
        allocate(yfull(self%nrots, self%map_nkb, nb))
        do b = 1, nb
            do k = 1, self%map_nkb
                yfull(1:n1, k, b) = conjg(mblk%xctf(:, k, b))
                do m = 1, self%pftsz - 1
                    yfull(self%nrots - m + 1, k, b) = real(1 - 2 * mod(m, 2), real32) * mblk%xctf(m + 1, k, b)
                end do
            end do
        end do
        do m = 1, self%nrots
            cs(m) = real(cos(2._real64 * acos(-1._real64) * real(m - 1, real64) / real(self%nrots, real64)), real32)
            sn(m) = real(sin(2._real64 * acos(-1._real64) * real(m - 1, real64) / real(self%nrots, real64)), real32)
        end do
        allocate(ypk(self%nrots, 2 * self%map_nkb, nb))
        ypk(:, 1:self%map_nkb, :)                    = real(yfull)
        ypk(:, self%map_nkb + 1:2 * self%map_nkb, :) = aimag(yfull)
        sh%ydev     = mlx_from(ypk)
        sh%c2dev    = mlx_from(mblk%ctf2(:, 1:self%map_nkb, :))
        sh%cosr     = mlx_from(reshape(cs, [self%nrots, 1]))
        sh%sinr     = mlx_from(reshape(sn, [self%nrots, 1]))
        sh%shiftidx = mlx_from(reshape(shift_table(self%nrots, self%map_norder), &
            &[self%nrots, 1, 1, self%map_norder + 1]))
        allocate(res%loss(ncand, nb), res%sdev(ncand, nb), res%irot(ncand, nb), res%irho(ncand, nb), &
            &res%ialpha(ncand, nb))
        if( mblk%evidence ) allocate(res%logz(ncand, nb))
        if( mblk%maps ) allocate(res%maps(self%map_nalpha, self%nrots, self%map_nrho, ncand, nb))
        ! the particles in graphs of at most ptcl_tile, each with all its candidates; pairs candidate fastest
        do b0 = 1, nb, mblk%ptcl_tile
            b1 = min(nb, b0 + mblk%ptcl_tile - 1)
            pt = b1 - b0 + 1
            allocate(tl%ptcls(pt), tl%cands(ncand, pt), tl%pref(pt * ncand), tl%pptcl(pt * ncand))
            tl%ptcls = [(b, b = b0, b1)]
            tl%cands = pos(:, b0:b1)
            do p = 1, pt * ncand
                tl%pref(p)  = pos(mod(p - 1, ncand) + 1, b0 + (p - 1) / ncand)
                tl%pptcl(p) = b0 + (p - 1) / ncand
            end do
            call tile_maps(self, mblk, sh, tl, status)
            if( status /= 0 ) return
            do p = 1, pt * ncand
                i = p
                c = mod(p - 1, ncand) + 1
                b = b0 + (p - 1) / ncand
                res%loss(c, b)   = tl%loss(i)
                res%sdev(c, b)   = tl%sdev(i)
                res%ialpha(c, b) = mod(tl%idx(i) - 1, self%map_nalpha) + 1
                res%irot(c, b)   = mod((tl%idx(i) - 1) / self%map_nalpha, self%nrots) + 1
                res%irho(c, b)   = (tl%idx(i) - 1) / (self%map_nalpha * self%nrots) + 1
                if( mblk%evidence ) res%logz(c, b) = tl%logz(i)
                if( mblk%maps ) res%maps(:, :, :, c, b) = tl%maps(:, :, :, i)
            end do
            deallocate(tl%ptcls, tl%cands, tl%pref, tl%pptcl, tl%idx, tl%loss, tl%sdev, tl%logz)
            if( allocated(tl%maps) ) deallocate(tl%maps)
        end do
        status = 0
    end subroutine polar_table_score_maps

    ! the particle's ring index shifted by every order: (m' + n) modulo nrots, 1-based, for m' = 1..nrots and
    ! n = 0..norder
    pure function shift_table( nrots, norder ) result(t)
        integer, intent(in) :: nrots, norder
        integer(int32) :: t(nrots, norder + 1)
        integer        :: m, n
        do n = 0, norder
            do m = 1, nrots
                t(m, n + 1) = int(modulo(m - 1 + n, nrots) + 1, int32)
            end do
        end do
    end function shift_table

    ! the reason a block of maps cannot be scored, or an empty string
    subroutine check_map_block( self, mblk, msg )
        class(polar_table),            intent(in)  :: self
        type(polar_map_block),         intent(in)  :: mblk
        character(len=:), allocatable, intent(out) :: msg
        integer :: nb, n1
        msg = ''
        if( .not. self%prepared )then
            msg = 'polar_table%score_maps: refused: no prepared references'
        else if( .not. self%maps_ready )then
            msg = 'polar_table%score_maps: refused: no prepared maps'
        else if( mblk%generation /= self%generation )then
            msg = 'polar_table%score_maps: refused: the block''s reference generation differs from the prepared one'
        else if( mblk%half /= self%half )then
            msg = 'polar_table%score_maps: refused: the block''s half differs from the prepared one'
        else if( mblk%ptcl_tile < 1 )then
            msg = 'polar_table%score_maps: refused: a tile holds at least one particle'
        else if( .not. allocated(mblk%ptcl_ids) .or. .not. allocated(mblk%cands) .or. .not. allocated(mblk%ctf2) &
            &.or. .not. allocated(mblk%xctf) .or. .not. allocated(mblk%ptclpow) .or. .not. allocated(mblk%temps) &
            &.or. .not. allocated(mblk%temps_phys) )then
            msg = 'polar_table%score_maps: refused: the block lacks an input'
        endif
        if( len(msg) > 0 ) return
        nb = size(mblk%ptcl_ids)
        n1 = self%pftsz + 1
        if( nb < 1 .or. size(mblk%cands, 1) < 1 .or. size(mblk%cands, 2) /= nb .or. &
            &any(shape(mblk%ctf2) /= [n1, self%nk, nb]) .or. any(shape(mblk%xctf) /= [n1, self%nk, nb]) .or. &
            &size(mblk%ptclpow) /= nb .or. size(mblk%temps) /= nb .or. size(mblk%temps_phys) /= nb )then
            msg = 'polar_table%score_maps: refused: the block''s shapes do not match the prepared references'
        else if( any(mblk%ptcl_ids < 1) )then
            msg = 'polar_table%score_maps: refused: particle IDs are global and positive'
        else if( any(.not. (mblk%ptclpow > 0._real64)) )then
            msg = 'polar_table%score_maps: refused: a particle''s weighted square sum is not positive'
        else if( .not. all_prepared(mblk%cands, self%ids) )then
            msg = 'polar_table%score_maps: refused: a candidate is not among the prepared references'
        endif
        if( len(msg) > 0 ) return
        if( allocated(mblk%width_cutoff) )then
            if( any(shape(mblk%width_cutoff) /= shape(mblk%cands)) ) &
                &msg = 'polar_table%score_maps: refused: width cutoffs must match the candidate lists'
        endif
    end subroutine check_map_block

    pure logical function all_prepared( cands, ids )
        integer, intent(in) :: cands(:,:), ids(:)
        integer :: b, c
        all_prepared = .true.
        do b = 1, size(cands, 2)
            do c = 1, size(cands, 1)
                if( .not. any(ids == cands(c, b)) ) all_prepared = .false.
            end do
        end do
    end function all_prepared

    ! one tile's maps on the device: the particles' order-expanded weighted spectra, their contraction with every
    ! candidate's, the transforms over the ring position and the orders, the loss L; then the mode (the first
    ! largest log mass in Fortran order), the width at the physical temperature (the moments of the cells' shifts,
    ! each rotation's turned into the particle's axes) and the log evidence; the results copied back
    subroutine tile_maps( self, mblk, sh, tl, status )
        class(polar_table),    intent(inout) :: self
        type(polar_map_block), intent(in)    :: mblk
        type(map_shared),      intent(in)    :: sh
        type(map_tile),        intent(inout) :: tl
        integer,               intent(out)   :: status
        type(mlx_array)              :: iref, iptcl, itile, icand, y, ysh, z, bref, gpk, gp, f, h, d, gout, c2, r2, cr, rp
        type(mlx_array)              :: pp, tt, tp, br, bi, top, bot, parts(2)
        type(mlx_array)              :: lp, idx, loss, sdev, logz, lse, width_maps, active_idx
        type(mlx_array), allocatable :: outs(:)
        real(real32),    allocatable :: pw(:), t(:), tph(:), widths(:), cuts(:)
        integer, allocatable         :: active(:)
        real(real64)                 :: t0
        integer                      :: np, pt, ncand, nrots, nalpha, nrho, nkb, nord, b, nactive
        np     = size(tl%pref)
        pt     = size(tl%ptcls)
        ncand  = size(tl%cands, 1)
        nrots  = self%nrots
        nalpha = self%map_nalpha
        nrho   = self%map_nrho
        nkb    = self%map_nkb
        nord   = self%map_norder + 1
        allocate(pw(np), t(np), tph(np))
        do b = 1, np
            pw(b)  = real(mblk%ptclpow(tl%pptcl(b)), real32)
            t(b)   = mblk%temps(tl%pptcl(b))
            tph(b) = mblk%temps_phys(tl%pptcl(b))
        end do
        t0    = clock_s()
        iref  = mlx_from(reshape(int(tl%pref, int32), [1, 1, np]))
        iptcl = mlx_from(reshape(int(tl%pptcl, int32), [1, 1, np]))
        itile = mlx_from(int(tl%ptcls, int32))
        icand = mlx_from(int(tl%cands, int32))
        ! per particle once: Z[(k, t), (n, rho), m'] = w_k J_n Y^_k[m' + n], the real parts (t = 1) then the
        ! imaginary parts along the shells (the weights are real), (2 nkb, nord nrho, nrots, pt)
        y    = mlx_take(sh%ydev, itile, 3)
        ysh  = mlx_take_along_dim(reshape(y, [nrots, 2 * nkb, pt, 1]), sh%shiftidx, 1)
        z    = reshape(self%wfold * reshape(mlx_permute(ysh, [2, 4, 1, 3]), [nkb, 2, nord, 1, nrots, pt]), &
            &[2 * nkb, nord * nrho, nrots, pt])
        ! per tile one real contraction over the shells against every candidate, batched over (m', particle):
        ! row (s, c) of the left operand is [Re R_c, -Im R_c] for s = 1 and [Im R_c, Re R_c] for s = 2, so that
        ! the product's rows alternate the real and the imaginary parts of G'_n[m', rho] = sum_k R^_k[m'] Z =
        ! G_n[m' + n, rho]: read as complex64 without a copy, (ncand, nord nrho, nrots, pt)
        bref     = mlx_take(self%rfull, icand, 3)
        br       = reshape(mlx_permute(real(bref), [3, 1, 2, 4]), [1, ncand, nkb, 1, nrots, pt])
        bi       = reshape(mlx_permute(aimag(bref), [3, 1, 2, 4]), [1, ncand, nkb, 1, nrots, pt])
        parts(1) = br
        parts(2) = -bi
        top      = mlx_concatenate(parts, 4)
        parts(1) = bi
        parts(2) = br
        bot      = mlx_concatenate(parts, 4)
        parts(1) = top
        parts(2) = bot
        gpk      = matmul(reshape(mlx_concatenate(parts, 1), [2 * ncand, 2 * nkb, nrots, pt]), z)
        gp       = mlx_bitcast(gpk, MLX_DTYPES%complex64)
        ! the forward transform over m' and the phase of the order's shift, H_n[r] = exp(-2 pi i n r / nrots)
        ! FFT(G'_n)[r]; then the orders onto the directions, D[a, r] = sum_n exp(-2 pi i n a / nalpha) H_n[r]:
        ! the orders folded modulo nalpha, as the sum of the transforms of each run of nalpha orders (the last
        ! one zero-padded by the transform)
        f  = mlx_fft(gp, 3)
        h  = reshape(f, [ncand, nord, nrho, nrots, pt]) * self%ffold
        d  = complex_directions(h, nalpha)
        ! (direction, rotation, radius, pair), pairs candidate fastest
        gout = reshape(mlx_permute(real(d), [2, 4, 3, 1, 5]), [nalpha, nrots, nrho, np])
        ! the reference's weighted power under the rotated CTF, half ring: the inverse real transform over 2
        c2   = mlx_take_along_dim(sh%c2dev, iptcl, 3)
        r2   = mlx_take_along_dim(self%ref2b, iref, 3)
        cr   = sum(c2 * r2 * self%wband, 2)
        rp   = reshape(mlx_irfft(cr, 1, n=nrots) * 0.5_real32, [1, nrots, 1, np])
        pp   = mlx_from(reshape(pw, [1, 1, 1, np]))
        ! L = 1 + (refpow - 2 C) / ptclpow, C = gout / nrots, (direction, rotation, radius, pair)
        lp   = (rp - gout * (2._real32 / real(nrots, real32))) / pp + 1._real32
        if( mblk%profile ) call map_stage_done(self, 1, t0, [lp])
        t0   = clock_s()
        tt   = mlx_from(reshape(t, [1, 1, 1, np]))
        call self%map_select%apply([lp, tt, self%cellprior], outs, status)
        if( status /= 0 )then
            self%msg = 'polar_table%score_maps: a tile''s selection could not be built'
            return
        endif
        idx  = outs(1)
        loss = outs(2)
        if( mblk%profile ) call map_stage_done(self, 2, t0, [idx, loss])
        t0   = clock_s()
        allocate(tl%idx(np), tl%loss(np), tl%sdev(np), tl%logz(np))
        active = [(b, b = 1, np)]
        if( allocated(mblk%width_cutoff) )then
            ! One synchronization per tile supplies every cutoff decision; no moment graph for rejected pairs.
            call mlx_to(tl%idx, idx, status=status)
            if( status == 0 ) call mlx_to(tl%loss, loss, status=status)
            if( status /= 0 ) return
            cuts = reshape(mblk%width_cutoff(:, tl%ptcls), [np])
            active = pack(active, tl%loss <= cuts)
        endif
        nactive = size(active)
        if( nactive > 0 )then
            width_maps = lp
            if( nactive < np )then
                active_idx = mlx_from(int(active, int32))
                width_maps = mlx_take(lp, active_idx, 4)
            endif
            tp = mlx_from(reshape(tph(active), [1, 1, 1, nactive]))
            call self%map_reduce%apply([width_maps, tp, self%cellprior, self%cellx, self%celly, self%cellr2, &
                &sh%cosr, sh%sinr], outs, status)
            if( status /= 0 )then
                self%msg = 'polar_table%score_maps: a tile''s width reduction could not be built'
                return
            endif
            sdev = outs(1)
            if( mblk%profile ) call mlx_eval([sdev])
        endif
        ! Separate compiled graphs ensure unrequested evidence is never evaluated with the width.
        if( mblk%evidence )then
            lse = mlx_from(real(self%map_lse_prior, real32))
            call self%map_evidence%apply([lp, tt, self%cellprior, lse], outs, status)
            if( status /= 0 )then
                self%msg = 'polar_table%score_maps: a tile''s evidence reduction could not be built'
                return
            endif
            logz = outs(1)
            if( mblk%profile ) call mlx_eval([logz])
        endif
        if( mblk%profile ) self%mstage_s(3) = self%mstage_s(3) + clock_s() - t0
        t0 = clock_s()
        if( .not. allocated(mblk%width_cutoff) )then
            call mlx_to(tl%idx, idx, status=status)
            if( status == 0 ) call mlx_to(tl%loss, loss, status=status)
        endif
        tl%sdev = -1._real32
        if( status == 0 .and. nactive > 0 )then
            allocate(widths(nactive))
            call mlx_to(widths, sdev, status=status)
            tl%sdev(active) = widths
        endif
        if( status == 0 .and. mblk%evidence ) call mlx_to(tl%logz, logz, status=status)
        if( status == 0 .and. mblk%maps )then
            allocate(tl%maps(nalpha, nrots, nrho, np))
            call mlx_to(tl%maps, lp, status=status)
        endif
        if( status /= 0 ) self%msg = 'polar_table%score_maps: a tile could not be evaluated'
        ! profiled, every result is evaluated before the copies: their seconds are the transfer's
        if( mblk%profile ) self%mstage_s(4) = self%mstage_s(4) + (clock_s() - t0)
    end subroutine tile_maps

    function complex_directions( h, nalpha ) result(d)
        type(mlx_array), intent(in) :: h
        integer,         intent(in) :: nalpha
        type(mlx_array) :: d
        integer         :: shp(5), q, nq
        shp = h%shape()
        nq = (shp(2) + nalpha - 1) / nalpha
        d = mlx_fft(mlx_slice(h, [1, 1, 1, 1, 1], [shp(1), min(nalpha, shp(2)), shp(3), shp(4), shp(5)]), 2, n=nalpha)
        do q = 2, nq
            d = d + mlx_fft(mlx_slice(h, [1, (q-1)*nalpha+1, 1, 1, 1], &
                &[shp(1), min(q*nalpha, shp(2)), shp(3), shp(4), shp(5)]), 2, n=nalpha)
        end do
    end function complex_directions

    ! the compiled selection: inputs (the maps L (nalpha, nrots, nrho, np), the tempered inverse temperatures
    ! (1, 1, 1, np), the cells' prior with the log area (1, 1, nrho, 1)); outputs (the flat index of the mode, the
    ! first largest log mass in Fortran order, and its loss), each (np)
    subroutine map_select_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
        type(mlx_array) :: flat, idx
        integer         :: shp(4), ncell, np
        status = 1
        if( size(inputs) /= 3 ) return
        shp   = inputs(1)%shape()
        ncell = shp(1) * shp(2) * shp(3)
        np    = shp(4)
        flat  = reshape(inputs(3) - inputs(1) * inputs(2), [ncell, np])
        idx   = minloc(-flat, 1)
        allocate(outputs(2))
        outputs(1) = idx
        outputs(2) = reshape(mlx_take_along_dim(reshape(inputs(1), [ncell, np]), reshape(idx, [1, np]), 1), [np])
        status = 0
    end subroutine map_select_callback

    ! Width inputs: maps, physical inverse temperatures, prior, shift x/y/radius squared and rotation cos/sin.
    ! The moments rotate each cell into the particle frame; negligible mass is cut before summing.
    subroutine map_reduce_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
        type(mlx_array) :: lph, mp, a, w, w0, w1x, w1y, mx, my, w2, var, zero
        integer         :: shp(4), ncell, np
        status = 1
        if( size(inputs) /= 8 ) return
        shp   = inputs(1)%shape()
        ncell = shp(1) * shp(2) * shp(3)
        np    = shp(4)
        lph   = inputs(3) - inputs(1) * inputs(2)
        mp    = reshape(-minval(reshape(-lph, [ncell, np]), 1), [1, 1, 1, np])
        a     = lph - mp
        zero  = mlx_from(0._real32)
        w     = merge(exp(a), zero, a > real(POLAR_MAP_LOG_CUT, real32))
        w0    = sum(reshape(w, [ncell, np]), 1)
        w1x   = sum(sum(w * inputs(4), 3), 1)
        w1y   = sum(sum(w * inputs(5), 3), 1)
        mx    = sum(w1x * inputs(7) - w1y * inputs(8), 1)
        my    = sum(w1x * inputs(8) + w1y * inputs(7), 1)
        w2    = sum(reshape(w * inputs(6), [ncell, np]), 1)
        var   = (w2 - (mx * mx + my * my) / w0) / w0
        allocate(outputs(1))
        outputs(1) = sqrt(max(var, 0._real32))
        status = 0
    end subroutine map_reduce_callback

    ! Evidence uses the tempered temperature and the prior normalizer, independently of the width graph.
    subroutine map_evidence_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
        integer :: shp(4), ncell
        status = 1
        if( size(inputs) /= 4 ) return
        shp = inputs(1)%shape()
        ncell = product(shp(1:3))
        allocate(outputs(1))
        outputs(1) = mlx_logsumexp(reshape(inputs(3) - inputs(1) * inputs(2), [ncell, shp(4)]), 1) - inputs(4)
        status = 0
    end subroutine map_evidence_callback


    real(real64) function clock_s()
        integer(int64) :: count, rate
        call system_clock(count, rate)
        clock_s = real(count, real64) / real(rate, real64)
    end function clock_s

    ! a profiled map stage: its arrays evaluated (a barrier), its seconds added to mstage_s(i)
    subroutine map_stage_done( self, i, t0, arrays )
        class(polar_table), intent(inout) :: self
        integer,            intent(in)    :: i
        real(real64),       intent(in)    :: t0
        type(mlx_array),    intent(in)    :: arrays(:)
        call mlx_eval(arrays)
        self%mstage_s(i) = self%mstage_s(i) + (clock_s() - t0)
    end subroutine map_stage_done

end submodule mlxf_kernel_polar_table_shiftmap
