!@descr: the polar workspace's shift maps: the particle-reusing contraction, the direction transform and requested posterior outputs
! The particle carries the order shift Y[m'+n], shared across candidates. Shell sums contract the particle's
! spectra, weighted by the real Bessel weights, with every candidate's over the shells: one product per tile.
! The ring FFT needs the phase exp(-2 pi i n r/nrots); folded orders then sample the original direction grid.
! Mode selection uses tempered temperature, physical moments may be cut off, and evidence is optional.
submodule (mlxf_toy_polarft_workspace) mlxf_toy_polarft_workspace_shiftmap
use, intrinsic :: iso_fortran_env, only: int32, int64
use mlxf,           only: mlx_compile, mlx_from, mlx_eval, mlx_permute, reshape, matmul, mlx_irfft, mlx_fft, &
                          mlx_concatenate, mlx_slice, mlx_take_along_dim, mlx_take, mlx_bitcast, MLX_DTYPES, sum, real, &
                          aimag
use mlxf_test_defs, only: POLAR_BESSEL_JTOL, POLAR_MAP_LOG_CUT, polar_map_results
implicit none

contains

    module subroutine polarft_workspace_prepare_maps( self, spec, ft_ref_terms, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_map_spec),   intent(in)    :: spec
        complex(real32),          intent(in)    :: ft_ref_terms(:,:,:)
        integer,                  intent(out)   :: status
        complex(real32), allocatable :: rfull(:,:,:), ref2b(:,:,:), ephase(:,:,:)
        real(real32),    allocatable :: wres(:,:,:), cellx(:,:,:), celly(:,:,:), cellr2(:,:,:)
        real(real64),    allocatable :: jn(:)
        real(real64)                 :: alpha, fac
        integer,         allocatable :: nharm(:)
        type(mlx_function)           :: ftail
        integer                      :: im, pftsz, nrots, nrefs, nkb, nrho, nalpha, norder, n1, nk, r, k, m, n, ir, j, ierr
        status = 1
        if( spec%imap < 1 .or. spec%imap > NSHIFTMAPS )then
            self%msg = 'polarft_workspace%prepare_maps: no such shift map'
            return
        endif
        im = spec%imap
        ! the previous map goes first: a refused or failed preparation leaves no map, the scoring intact
        call polarft_workspace_drop_map(self, im)
        call check_map_spec(spec, shape(ft_ref_terms), self%msg)
        if( len(self%msg) > 0 ) return
        nk     = size(ft_ref_terms, 1) / 2
        n1     = size(ft_ref_terms, 2)
        pftsz  = n1 - 1
        nrots  = 2 * pftsz
        nrefs  = size(ft_ref_terms, 3)
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
        ! the references' full-ring spectra over the band (memo rows nk+1..), F[nrots - m] = (-1)^m conj(F[m]), laid
        ! out (shell, ring position, reference): a candidate's spectra are one contiguous slab; and the squared
        ! modulus's memos of the band (rows 1..) conjugated, laid out (bin, shell, reference)
        allocate(rfull(nkb, nrots, nrefs), ref2b(n1, nkb, nrefs), stat=ierr)
        if( ierr /= 0 )then
            self%msg = 'polarft_workspace%prepare_maps: the host staging of the reference spectra could not be allocated'
            return
        endif
        do r = 1, nrefs
            do k = 1, nkb
                rfull(k, 1:n1, r) = ft_ref_terms(nk + k, :, r)
                do m = 1, pftsz - 1
                    rfull(k, nrots - m + 1, r) = real(1 - 2 * mod(m, 2), real32) * conjg(ft_ref_terms(nk + k, m + 1, r))
                end do
                ref2b(:, k, r) = conjg(ft_ref_terms(k, :, r))
            end do
        end do
        ! the Bessel weights fac_n w_k J_n(2 pi k rho / box) of the orders each radius keeps (zero beyond), real64
        ! rounded once (order 0 enters with a half), laid out (shell, order, radius); and the phase of the order's
        ! shift at rotation r, exp(-2 pi i n r / nrots), laid out (order, rotation)
        allocate(wres(nkb, norder + 1, nrho), ephase(norder + 1, 1, nrots), jn(0:norder))
        do r = 1, nrots
            do n = 0, norder
                alpha = -2._real64 * acos(-1._real64) * real(n, real64) * real(r - 1, real64) / real(nrots, real64)
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
        ! the cells: shift components and squared radius
        allocate(cellx(nalpha, 1, nrho), celly(nalpha, 1, nrho), cellr2(1, 1, nrho))
        do ir = 1, nrho
            do j = 1, nalpha
                alpha          = 2._real64 * acos(-1._real64) * real(j - 1, real64) / real(nalpha, real64)
                cellx(j, 1, ir) = real(spec%rho(ir) * cos(alpha), real32)
                celly(j, 1, ir) = real(spec%rho(ir) * sin(alpha), real32)
            end do
            cellr2(1, 1, ir) = real(spec%rho(ir)**2, real32)
        end do
        self%maps(im)%rfull  = mlx_from(rfull)
        self%maps(im)%ref2b  = mlx_from(ref2b)
        self%maps(im)%wfold  = mlx_from(reshape(wres, [nkb, 1, norder + 1, nrho, 1, 1]))
        self%maps(im)%ffold  = mlx_from(reshape(ephase, [1, norder + 1, 1, nrots, 1]))
        self%maps(im)%wband  = mlx_from(reshape(real(spec%weights, real32), [1, nkb, 1]))
        self%maps(im)%cellx  = mlx_from(reshape(cellx, [nalpha, 1, nrho, 1]))
        self%maps(im)%celly  = mlx_from(reshape(celly, [nalpha, 1, nrho, 1]))
        self%maps(im)%cellr2 = mlx_from(reshape(cellr2, [1, 1, nrho, 1]))
        call mlx_eval([self%maps(im)%rfull, self%maps(im)%ref2b, self%maps(im)%wfold, self%maps(im)%ffold, &
            &self%maps(im)%wband, self%maps(im)%cellx, self%maps(im)%celly, self%maps(im)%cellr2], status=ierr)
        if( ierr /= 0 )then
            self%msg = 'polarft_workspace%prepare_maps: the map''s resident data could not be evaluated'
            call polarft_workspace_drop_map(self, im)
            return
        endif
        ! the selection and the reduction of a tile's maps, each compiled into one graph per tile shape
        ftail                      = mlx_function(map_select_callback)
        self%maps(im)%map_select   = mlx_compile(ftail, shapeless=.false.)
        ftail                      = mlx_function(map_reduce_callback)
        self%maps(im)%map_reduce   = mlx_compile(ftail, shapeless=.false.)
        ftail                      = mlx_function(map_evidence_callback)
        self%maps(im)%map_evidence = mlx_compile(ftail, shapeless=.false.)
        self%maps(im)%pftsz        = pftsz
        self%maps(im)%nrots        = nrots
        self%maps(im)%nrefs        = nrefs
        self%maps(im)%nkb          = nkb
        self%maps(im)%nrho         = nrho
        self%maps(im)%nalpha       = nalpha
        self%maps(im)%norder       = norder
        self%maps(im)%rho          = spec%rho
        self%maps(im)%area         = cell_areas(spec%rho, nalpha)
        self%maps(im)%nharm        = nharm
        self%maps(im)%ready        = .true.
        status                     = 0
    end subroutine polarft_workspace_prepare_maps

    ! the reason a map cannot be prepared from memos of shapes shpr and shpr2, or an empty string
    subroutine check_map_spec( spec, shpr, msg )
        type(polarft_map_spec),        intent(in)  :: spec
        integer,                       intent(in)  :: shpr(3)
        character(len=:), allocatable, intent(out) :: msg
        msg = ''
        if( shpr(2) < 3 .or. mod(shpr(2), 2) /= 1 .or. shpr(3) < 1 .or. shpr(1) < 2 .or. mod(shpr(1), 2) /= 0 )then
            msg = 'polarft_workspace%prepare_maps: refused: the reference memos are not (2nk, pftsz+1, references)'
        else if( spec%box < 2 .or. spec%nalpha < 1 .or. spec%kfrom < 1 )then
            msg = 'polarft_workspace%prepare_maps: the grid needs a box, a first shell and a direction'
        else if( spec%kstop < spec%kfrom .or. spec%kstop - spec%kfrom + 1 > shpr(1) / 2 )then
            msg = 'polarft_workspace%prepare_maps: the band must lie in the references'' shells'
        else if( .not. allocated(spec%rho) .or. .not. allocated(spec%weights) )then
            msg = 'polarft_workspace%prepare_maps: the grid lacks its radii or the band its weights'
        endif
        if( len(msg) > 0 ) return
        if( size(spec%rho) < 1 .or. size(spec%weights) /= spec%kstop - spec%kfrom + 1 )then
            msg = 'polarft_workspace%prepare_maps: the grid needs a radius and one weight per band shell'
        else if( any(spec%rho < 0._real64) )then
            msg = 'polarft_workspace%prepare_maps: the radii are not negative'
        else if( size(spec%rho) > 1 )then
            if( any(spec%rho(2:) <= spec%rho(:size(spec%rho)-1)) ) &
                &msg = 'polarft_workspace%prepare_maps: the radii ascend strictly'
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

    module subroutine polarft_workspace_drop_map( self, imap )
        class(polarft_workspace), intent(inout) :: self
        integer,                  intent(in)    :: imap
        call self%maps(imap)%rfull%kill()
        call self%maps(imap)%ref2b%kill()
        call self%maps(imap)%wfold%kill()
        call self%maps(imap)%ffold%kill()
        call self%maps(imap)%wband%kill()
        call self%maps(imap)%cellx%kill()
        call self%maps(imap)%celly%kill()
        call self%maps(imap)%cellr2%kill()
        call self%maps(imap)%map_select%kill()
        call self%maps(imap)%map_reduce%kill()
        call self%maps(imap)%map_evidence%kill()
        if( allocated(self%maps(imap)%rho) ) deallocate(self%maps(imap)%rho)
        if( allocated(self%maps(imap)%area) ) deallocate(self%maps(imap)%area)
        if( allocated(self%maps(imap)%nharm) ) deallocate(self%maps(imap)%nharm)
        self%maps(imap)%ready  = .false.
        self%maps(imap)%pftsz  = 0
        self%maps(imap)%nrots  = 0
        self%maps(imap)%nrefs  = 0
        self%maps(imap)%nkb    = 0
        self%maps(imap)%nrho   = 0
        self%maps(imap)%nalpha = 0
        self%maps(imap)%norder = 0
    end subroutine polarft_workspace_drop_map

    module subroutine kill_maps( self )
        class(polarft_workspace), intent(inout) :: self
        integer :: imap
        do imap = 1, NSHIFTMAPS
            call polarft_workspace_drop_map(self, imap)
        end do
    end subroutine kill_maps

    pure module integer function map_order( self, imap )
        class(polarft_workspace), intent(in) :: self
        integer,                  intent(in) :: imap
        map_order = 0
        if( imap >= 1 .and. imap <= NSHIFTMAPS ) map_order = self%maps(imap)%norder
    end function map_order

    pure module function map_term_counts( self, imap ) result(counts)
        class(polarft_workspace), intent(in) :: self
        integer,                  intent(in) :: imap
        integer(int64) :: counts(2)
        counts = 0_int64
        if( imap < 1 .or. imap > NSHIFTMAPS ) return
        if( .not. self%maps(imap)%ready ) return
        counts(1) = sum(int(self%maps(imap)%nharm + 1, int64))
        counts(2) = int(self%maps(imap)%norder + 1, int64) * int(self%maps(imap)%nrho, int64)
    end function map_term_counts

    pure module function map_seconds( self ) result(t)
        class(polarft_workspace), intent(in) :: self
        real(real64) :: t(4)
        t = self%mstage_s
    end function map_seconds

    module subroutine polarft_workspace_score_maps( self, mblk, ft_ctf2, ft_ptcl_ctf, res )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_map_block),  intent(in)    :: mblk
        complex(real32),          intent(in)    :: ft_ctf2(:,:,:), ft_ptcl_ctf(:,:,:)
        type(polar_map_results),  intent(out)   :: res
        complex(real32), allocatable :: yfull(:,:,:), c2(:,:,:)
        real(real32),    allocatable :: ypk(:,:,:), cellprior(:,:,:), cs(:), sn(:)
        real(real64)                 :: lmax, s, th
        type(map_shared)             :: sh
        type(map_tile)               :: tl
        integer                      :: im, nb, ncand, n1, nrots, pftsz, nkb, nrho, b, c, m, k, b0, b1, pt, p, i, ir, status
        call check_map_block(self, mblk, shape(ft_ctf2), shape(ft_ptcl_ctf), self%msg)
        if( len(self%msg) > 0 ) return
        im     = mblk%imap
        pftsz  = self%maps(im)%pftsz
        nrots  = self%maps(im)%nrots
        nkb    = self%maps(im)%nkb
        nrho   = self%maps(im)%nrho
        n1     = pftsz + 1
        nb     = size(mblk%islots)
        ncand  = size(mblk%cands, 1)
        ! the particles' full-ring spectra over the band, conjugated: Y^[m] = conj(F[m]), Y^[nrots - m] = (-1)^m F[m]
        allocate(yfull(nrots, nkb, nb), c2(n1, nkb, nb), cs(nrots), sn(nrots))
        do b = 1, nb
            do k = 1, nkb
                yfull(1:n1, k, b) = conjg(ft_ptcl_ctf(:, k, mblk%islots(b)))
                do m = 1, pftsz - 1
                    yfull(nrots - m + 1, k, b) = real(1 - 2 * mod(m, 2), real32) * ft_ptcl_ctf(m + 1, k, mblk%islots(b))
                end do
                c2(:, k, b) = ft_ctf2(:, k, mblk%islots(b))
            end do
        end do
        do m = 1, nrots
            cs(m) = real(cos(2._real64 * acos(-1._real64) * real(m - 1, real64) / real(nrots, real64)), real32)
            sn(m) = real(sin(2._real64 * acos(-1._real64) * real(m - 1, real64) / real(nrots, real64)), real32)
        end do
        allocate(ypk(nrots, 2 * nkb, nb))
        ypk(:, 1:nkb, :)           = real(yfull)
        ypk(:, nkb + 1:2 * nkb, :) = aimag(yfull)
        ! the prior with the log area of one cell per radius, and its log normaliser over every cell (direction,
        ! rotation, radius)
        allocate(cellprior(1, 1, nrho))
        do ir = 1, nrho
            cellprior(1, 1, ir) = real(-mblk%prior_w * self%maps(im)%rho(ir)**2 + log(self%maps(im)%area(ir)), real32)
        end do
        lmax = maxval(-mblk%prior_w * self%maps(im)%rho**2 + log(self%maps(im)%area))
        s    = 0._real64
        do ir = 1, nrho
            if( -mblk%prior_w * self%maps(im)%rho(ir)**2 + log(self%maps(im)%area(ir)) - lmax > POLAR_MAP_LOG_CUT ) &
                &s = s + real(nrots, real64) * real(self%maps(im)%nalpha, real64) * exp(-mblk%prior_w * &
                &self%maps(im)%rho(ir)**2 + log(self%maps(im)%area(ir)) - lmax)
        end do
        sh%lse_prior = lmax + log(s)
        sh%cellprior = mlx_from(reshape(cellprior, [1, 1, nrho, 1]))
        sh%ydev      = mlx_from(ypk)
        sh%c2dev     = mlx_from(c2)
        sh%cosr      = mlx_from(reshape(cs, [nrots, 1]))
        sh%sinr      = mlx_from(reshape(sn, [nrots, 1]))
        sh%shiftidx  = mlx_from(reshape(shift_table(nrots, self%maps(im)%norder), &
            &[nrots, 1, 1, self%maps(im)%norder + 1]))
        allocate(res%loss(ncand, nb), res%sdev(ncand, nb), res%irot(ncand, nb), res%irho(ncand, nb), &
            &res%ialpha(ncand, nb), res%shifts(2, ncand, nb))
        if( mblk%evidence ) allocate(res%logz(ncand, nb))
        if( mblk%maps ) allocate(res%maps(self%maps(im)%nalpha, nrots, nrho, ncand, nb))
        ! the particles in graphs of at most ptcl_tile, each with all its candidates; pairs candidate fastest
        do b0 = 1, nb, mblk%ptcl_tile
            b1 = min(nb, b0 + mblk%ptcl_tile - 1)
            pt = b1 - b0 + 1
            allocate(tl%ptcls(pt), tl%cands(ncand, pt), tl%pref(pt * ncand), tl%pptcl(pt * ncand))
            tl%ptcls = [(b, b = b0, b1)]
            tl%cands = mblk%cands(:, b0:b1)
            do p = 1, pt * ncand
                tl%pref(p)  = mblk%cands(mod(p - 1, ncand) + 1, b0 + (p - 1) / ncand)
                tl%pptcl(p) = b0 + (p - 1) / ncand
            end do
            call tile_maps(self, mblk, sh, tl, status)
            if( status /= 0 )then
                if( len(self%msg) == 0 ) self%msg = 'polarft_workspace%score_maps: a tile could not be evaluated'
                return
            endif
            do p = 1, pt * ncand
                i = p
                c = mod(p - 1, ncand) + 1
                b = b0 + (p - 1) / ncand
                res%loss(c, b)   = tl%loss(i)
                res%sdev(c, b)   = tl%sdev(i)
                res%ialpha(c, b) = mod(tl%idx(i) - 1, self%maps(im)%nalpha) + 1
                res%irot(c, b)   = mod((tl%idx(i) - 1) / self%maps(im)%nalpha, nrots) + 1
                res%irho(c, b)   = (tl%idx(i) - 1) / (self%maps(im)%nalpha * nrots) + 1
                ! the mode's shift in the reference's axes
                th = 2._real64 * acos(-1._real64) * real(res%ialpha(c, b) - 1, real64) / real(self%maps(im)%nalpha, real64)
                res%shifts(:, c, b) = self%maps(im)%rho(res%irho(c, b)) * [cos(th), sin(th)]
                if( mblk%evidence ) res%logz(c, b) = tl%logz(i)
                if( mblk%maps ) res%maps(:, :, :, c, b) = tl%maps(:, :, :, i)
            end do
            deallocate(tl%ptcls, tl%cands, tl%pref, tl%pptcl, tl%idx, tl%loss, tl%sdev, tl%logz)
            call tl%lp%kill()
            if( allocated(tl%maps) ) deallocate(tl%maps)
        end do
    end subroutine polarft_workspace_score_maps

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

    ! the reason a block of maps cannot be scored against memos of shapes shp2 and shpx, or an empty string
    subroutine check_map_block( self, mblk, shp2, shpx, msg )
        class(polarft_workspace),      intent(in)  :: self
        type(polarft_map_block),       intent(in)  :: mblk
        integer,                       intent(in)  :: shp2(3), shpx(3)
        character(len=:), allocatable, intent(out) :: msg
        integer :: nb, ncand, n1, im
        msg = ''
        if( mblk%imap < 1 .or. mblk%imap > NSHIFTMAPS )then
            msg = 'polarft_workspace%score_maps: refused: no such shift map'
            return
        endif
        im = mblk%imap
        if( .not. self%maps(im)%ready )then
            msg = 'polarft_workspace%score_maps: refused: no prepared maps'
        else if( mblk%ptcl_tile < 1 )then
            msg = 'polarft_workspace%score_maps: refused: a tile holds at least one particle'
        else if( .not. allocated(mblk%islots) .or. .not. allocated(mblk%cands) .or. .not. allocated(mblk%ptclpow) &
            &.or. .not. allocated(mblk%temps) .or. (mblk%widths .and. .not. allocated(mblk%temps_phys)) )then
            msg = 'polarft_workspace%score_maps: refused: the block lacks an input'
        else if( mblk%prior_w < 0._real64 )then
            msg = 'polarft_workspace%score_maps: refused: the prior''s weight is not negative'
        endif
        if( len(msg) > 0 ) return
        nb    = size(mblk%islots)
        ncand = size(mblk%cands, 1)
        n1    = self%maps(im)%pftsz + 1
        if( nb < 1 .or. ncand < 1 .or. size(mblk%cands, 2) /= nb .or. shp2(1) /= n1 .or. &
            &shp2(2) < self%maps(im)%nkb .or. any(shpx /= shp2) .or. size(mblk%ptclpow) /= nb .or. &
            &any(shape(mblk%temps) /= [ncand, nb]) )then
            msg = 'polarft_workspace%score_maps: refused: the block''s shapes do not match the prepared map'
        else if( any(mblk%islots < 1 .or. mblk%islots > shp2(3)) )then
            msg = 'polarft_workspace%score_maps: refused: a particle of the block is outside the batch'
        else if( any(.not. (mblk%ptclpow > 0._real64)) )then
            msg = 'polarft_workspace%score_maps: refused: a particle''s weighted square sum is not positive'
        else if( any(mblk%cands < 1 .or. mblk%cands > self%maps(im)%nrefs) )then
            msg = 'polarft_workspace%score_maps: refused: a candidate is not among the prepared references'
        endif
        if( len(msg) > 0 ) return
        if( mblk%widths )then
            if( any(shape(mblk%temps_phys) /= [ncand, nb]) )then
                msg = 'polarft_workspace%score_maps: refused: the block''s shapes do not match the prepared map'
                return
            endif
        endif
        if( allocated(mblk%width_cutoff) )then
            if( any(shape(mblk%width_cutoff) /= shape(mblk%cands)) ) &
                &msg = 'polarft_workspace%score_maps: refused: width cutoffs must match the candidate lists'
        endif
    end subroutine check_map_block

    ! one tile's maps on the device: the particles' order-expanded weighted spectra, their contraction with every
    ! candidate's, the transforms over the ring position and the orders, the loss L; then the reductions, the
    ! results copied back
    subroutine tile_maps( self, mblk, sh, tl, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_map_block),  intent(in)    :: mblk
        type(map_shared),         intent(in)    :: sh
        type(map_tile),           intent(inout) :: tl
        integer,                  intent(out)   :: status
        type(mlx_array)           :: iref, iptcl, itile, icand, y, ysh, z, bref, gpk, gp, f, h, d, gout, c2, r2, cr, rp
        type(mlx_array)           :: pp, br, bi, top, bot, parts(2), lp
        real(real32), allocatable :: pw(:)
        real(real64)              :: t0
        integer                   :: im, np, pt, ncand, nrots, nalpha, nrho, nkb, nord, b
        status = 0
        im     = mblk%imap
        np     = size(tl%pref)
        pt     = size(tl%ptcls)
        ncand  = size(tl%cands, 1)
        nrots  = self%maps(im)%nrots
        nalpha = self%maps(im)%nalpha
        nrho   = self%maps(im)%nrho
        nkb    = self%maps(im)%nkb
        nord   = self%maps(im)%norder + 1
        allocate(pw(np))
        do b = 1, np
            pw(b) = real(mblk%ptclpow(tl%pptcl(b)), real32)
        end do
        t0    = map_clock()
        iref  = mlx_from(reshape(int(tl%pref, int32), [1, 1, np]))
        iptcl = mlx_from(reshape(int(tl%pptcl, int32), [1, 1, np]))
        itile = mlx_from(int(tl%ptcls, int32))
        icand = mlx_from(int(tl%cands, int32))
        ! per particle once: Z[(k, t), (n, rho), m'] = w_k J_n Y^_k[m' + n], the real parts (t = 1) then the
        ! imaginary parts along the shells (the weights are real), (2 nkb, nord nrho, nrots, pt)
        y    = mlx_take(sh%ydev, itile, 3)
        ysh  = mlx_take_along_dim(reshape(y, [nrots, 2 * nkb, pt, 1]), sh%shiftidx, 1)
        z    = reshape(self%maps(im)%wfold * reshape(mlx_permute(ysh, [2, 4, 1, 3]), [nkb, 2, nord, 1, nrots, pt]), &
            &[2 * nkb, nord * nrho, nrots, pt])
        ! per tile one real contraction over the shells against every candidate, batched over (m', particle):
        ! row (s, c) of the left operand is [Re R_c, -Im R_c] for s = 1 and [Im R_c, Re R_c] for s = 2, so that
        ! the product's rows alternate the real and the imaginary parts of G'_n[m', rho] = sum_k R^_k[m'] Z =
        ! G_n[m' + n, rho]: read as complex64 without a copy, (ncand, nord nrho, nrots, pt)
        bref     = mlx_take(self%maps(im)%rfull, icand, 3)
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
        h  = reshape(f, [ncand, nord, nrho, nrots, pt]) * self%maps(im)%ffold
        d  = complex_directions(h, nalpha)
        ! (direction, rotation, radius, pair), pairs candidate fastest
        gout = reshape(mlx_permute(real(d), [2, 4, 3, 1, 5]), [nalpha, nrots, nrho, np])
        ! the reference's weighted power under the rotated CTF, half ring: the inverse real transform over 2
        c2   = mlx_take_along_dim(sh%c2dev, iptcl, 3)
        r2   = mlx_take_along_dim(self%maps(im)%ref2b, iref, 3)
        cr   = sum(c2 * r2 * self%maps(im)%wband, 2)
        rp   = reshape(mlx_irfft(cr, 1, n=nrots) * 0.5_real32, [1, nrots, 1, np])
        pp   = mlx_from(reshape(pw, [1, 1, 1, np]))
        ! L = 1 + (refpow - 2 C) / ptclpow, C = gout / nrots, (direction, rotation, radius, pair)
        lp   = (rp - gout * (2._real32 / real(nrots, real32))) / pp + 1._real32
        if( mblk%profile ) call map_stage_done(self, 1, t0, [lp])
        tl%lp = lp
        call reduce_map_tile(self, mblk, sh, tl, status)
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

end submodule mlxf_toy_polarft_workspace_shiftmap
