!@descr: host oracle of the polar shift map: grid, cell, truncated Bessel form, areas, mode and width
! A map covers the shells kfrom .. kstop of a polar pair and a disc of shifts: rings rho_i = (i - 1) step with
! step = box / kstop / 4, and nalpha directions alpha_j = (j - 1) 2 pi / nalpha. Cell (ialpha, irot, irho) is the
! Euclidean loss 1 + (refpow - 2 cross) / ptclpow on the band, at the shift rho_i (cos alpha_j, sin alpha_j) in the
! reference's frame and rotation irot, where the shift's phase is exp(i z sin(theta - alpha)), z = 2 pi k rho / box.
! The truncated form keeps a ring's Bessel orders up to nharm. Plain Fortran on intrinsic modules and the oracles.
module mlxf_oracle_polar_shiftmap
use, intrinsic :: iso_fortran_env, only: real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_quiet_nan
use mlxf_oracle_dft,          only: oracle_finite_or_inf
use mlxf_oracle_polar_objfun, only: oracle_polar_pair, oracle_polar_fixture, oracle_polar_frame
use mlxf_test_reduce,         only: nan_maxval, nan_max
implicit none

public :: oracle_shiftmap, oracle_shiftmap_kscreen, oracle_shiftmap_temps, oracle_shiftmap_selfcheck
private

real(real64), parameter :: PI    = acos(-1._real64)
real(real64), parameter :: TWOPI = 2._real64 * PI
! rings per unit of box / kstop
real(real64), parameter :: STEP_DIVISOR = 4._real64
! Bessel orders are kept while the function at the band's last shell is at least this
real(real64), parameter :: BESSEL_FLOOR = 1.e-8_real64
! cells whose log weight relative to the largest is at most this are left out of the width
real(real64), parameter :: LOG_WEIGHT_FLOOR = -40._real64
! the factor of production's temperature
real(real64), parameter :: PROB_BETA = 0.3_real64
! the self-check's maps: fixture size, kstop, then the hand-worked nrho and nalpha; radius and hand-worked step
integer, parameter :: NCASE = 7
integer,      parameter :: CASE_INT(4, NCASE) = reshape([1, 4, 3, 12, 1, 4, 4, 14, 1, 4, 2, 7, 2, 3, 3, 12, 2, 3, 5, 18, &
                                                        1, 5, 4, 14, 3, 4, 3, 12], [4, NCASE])
real(real64), parameter :: CASE_REAL(2, NCASE) = reshape([5._real64, 2._real64, 7._real64, 2._real64, 1.5_real64, &
    1.5_real64, 5._real64, 2._real64, 9._real64, 2._real64, 5._real64, 1.6_real64, 6._real64, 2.5_real64], [2, NCASE])
! the hand-worked number of Bessel orders per ring of each map, -1 beyond its rings
integer, parameter :: MAXRING = 5
integer,      parameter :: NHARM_HAND(MAXRING, NCASE) = reshape([0, 10, 13, -1, -1, 0, 10, 13, 16, -1, 0, 9, -1, -1, -1, &
    0, 10, 13, -1, -1, 0, 10, 13, 16, 19, 0, 10, 13, 16, -1, 0, 10, 13, -1, -1], [MAXRING, NCASE])
! the map of the hand-made tables and of the retyped Bessel sum, its largest order, and the map with a quarter
! turn among its directions
integer,      parameter :: CASE_TABLES  = 2
integer,      parameter :: NHARM_MAX    = 16
integer,      parameter :: CASE_QUARTER = 1
! points of the trapezoid rule for the Bessel integral
integer, parameter :: NTRAP = 128
! the self-check's limits: identities and closed forms, and the truncated form against the direct cell; exact
! checks have limit 0
real(real64), parameter :: TOL_ROUTE  = 1.e-12_real64
real(real64), parameter :: TOL_BESSEL = 1.e-6_real64
integer,      parameter :: NCHECK    = 21
integer,      parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'kscreen', 'smooth sizes', 'grid counts', 'grid values', 'areas per ring', 'areas sum', 'bessel vs integral', &
    'nharm by hand', 'band power', 'cell vs direct loss', 'cc cell vs direct cc', 'bessel vs direct cell', &
    'bessel cc vs direct', 'bessel vs retyped sum', 'mode ties', 'mode by terms', 'width by hand', 'width skip', &
    'width cutoff', 'temperatures', 'zero power']
real(real64), parameter :: CHECK_LIMITS(NCHECK) = [0._real64, 0._real64, 0._real64, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, &
    TOL_ROUTE, 0._real64, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_BESSEL, TOL_BESSEL, TOL_ROUTE, 0._real64, 0._real64, &
    TOL_ROUTE, TOL_ROUTE, 0._real64, TOL_ROUTE, 0._real64]

! one map: the pair's arrays, the band, the grid and the prior on the shift's length
type :: oracle_shiftmap
    private
    integer                      :: pftsz = 0, kfrom = 0, kstop = 0, box = 0, nband = 0, nrho = 0, nalpha = 0
    real(real64)                 :: ring_step = 0._real64, prior_w = 0._real64
    complex(real64), allocatable :: ref(:,:), ptcl(:,:)
    real(real64),    allocatable :: ctf(:,:), sigma2(:)
    logical                      :: exists = .false.
  contains
    procedure :: new => map_new
    procedure :: kill => map_kill
    procedure :: set_prior => map_set_prior
    procedure :: dims => map_dims
    procedure :: step => map_step
    procedure :: rho => map_rho
    procedure :: alpha => map_alpha
    procedure :: area => map_area
    procedure :: nharm => map_nharm
    procedure :: ptclpow => map_ptclpow
    procedure :: cell => map_cell
    procedure :: cell_cc => map_cell_cc
    procedure :: cell_bessel => map_cell_bessel
    procedure :: cell_cc_bessel => map_cell_cc_bessel
    procedure :: table => map_table
    procedure :: mode => map_mode
    procedure :: width => map_width
end type oracle_shiftmap

contains

    ! the map of a pair on its shells up to kstop, one of the pair's shells, for shifts within radius pixels; no
    ! prior until set_prior
    subroutine map_new( self, pair, kstop, radius )
        class(oracle_shiftmap),  intent(inout) :: self
        type(oracle_polar_pair), intent(in)    :: pair
        integer,                 intent(in)    :: kstop
        real(real64),            intent(in)    :: radius
        real(real64) :: rho_max
        integer      :: g(4)
        call self%kill()
        g          = pair%geometry()
        self%pftsz = g(1)
        self%kfrom = g(2)
        self%kstop = kstop
        self%box   = g(4)
        self%nband = kstop - g(2) + 1
        call pair%arrays(self%ref, self%ptcl, self%ctf, self%sigma2)
        self%ring_step = real(self%box, real64) / real(kstop, real64) / STEP_DIVISOR
        self%nrho      = floor(radius / self%ring_step) + 1
        if( self%nrho < 2 )then
            self%nrho      = 2
            self%ring_step = radius
        endif
        rho_max      = real(self%nrho - 1, real64) * self%ring_step
        self%nalpha  = smooth_size(2 * ceiling(TWOPI * real(kstop, real64) * rho_max / real(self%box, real64)) + 3)
        self%prior_w = 0._real64
        self%exists  = .true.
    end subroutine map_new

    ! release the arrays; idempotent
    subroutine map_kill( self )
        class(oracle_shiftmap), intent(inout) :: self
        if( .not. self%exists ) return
        deallocate(self%ref, self%ptcl, self%ctf, self%sigma2)
        self%pftsz  = 0
        self%nband  = 0
        self%nrho   = 0
        self%nalpha = 0
        self%exists = .false.
    end subroutine map_kill

    ! the prior on the shift's length, weight 1 / (2 sigma_px**2) on rho**2
    subroutine map_set_prior( self, sigma_px )
        class(oracle_shiftmap), intent(inout) :: self
        real(real64),           intent(in)    :: sigma_px
        self%prior_w = 1._real64 / (2._real64 * sigma_px**2)
    end subroutine map_set_prior

    ! the shape of a table of cells: [nalpha, rotations, nrho]
    pure function map_dims( self ) result(d)
        class(oracle_shiftmap), intent(in) :: self
        integer :: d(3)
        d = [self%nalpha, 2 * self%pftsz, self%nrho]
    end function map_dims

    ! the distance between rings, in pixels
    pure function map_step( self ) result(s)
        class(oracle_shiftmap), intent(in) :: self
        real(real64) :: s
        s = self%ring_step
    end function map_step

    ! the radius of ring irho, (irho - 1) step
    pure function map_rho( self, irho ) result(r)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: irho
        real(real64) :: r
        r = real(irho - 1, real64) * self%ring_step
    end function map_rho

    ! the direction ialpha, (ialpha - 1) 2 pi / nalpha
    pure function map_alpha( self, ialpha ) result(a)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: ialpha
        real(real64) :: a
        a = real(ialpha - 1, real64) * TWOPI / real(self%nalpha, real64)
    end function map_alpha

    ! the area of a cell of ring irho: the annulus between the midpoints to its neighbours, from zero on the
    ! first ring and to half a step beyond the last, shared by the nalpha directions
    pure function map_area( self, irho ) result(a)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: irho
        real(real64) :: a, lo, hi
        lo = max(0._real64, self%rho(irho) - self%ring_step / 2._real64)
        hi = self%rho(irho) + self%ring_step / 2._real64
        a  = PI * (hi**2 - lo**2) / real(self%nalpha, real64)
    end function map_area

    ! the largest Bessel order kept on ring irho, from the argument z at the band's last shell: from
    ! max(0, ceiling(z)) the order rises while |J| is at least the floor, and the one before is kept
    pure function map_nharm( self, irho ) result(nh)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: irho
        real(real64) :: z
        integer      :: nh, m
        z = TWOPI * real(self%kstop, real64) * self%rho(irho) / real(self%box, real64)
        m = max(0, ceiling(z))
        do while( abs(bessel_jn(m, z)) >= BESSEL_FLOOR )
            m = m + 1
        end do
        nh = max(0, m - 1)
    end function map_nharm

    ! the particle's power on the band with the Euclidean weights k / sigma2
    pure function map_ptclpow( self ) result(w)
        class(oracle_shiftmap), intent(in) :: self
        real(real64) :: w
        w = power_sum(self, .true.)
    end function map_ptclpow

    ! the Euclidean cell: 1 + (refpow - 2 cross) / ptclpow on the band; NaN when the band's power is not positive
    pure function map_cell( self, ialpha, irot, irho ) result(l)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: ialpha, irot, irho
        real(real64) :: l
        l = loss_of(self, [ialpha, irot, irho], .false.)
    end function map_cell

    ! the correlation cell: cross / sqrt(refpow ptclpow) on the band, every shell weighted by its radius
    pure function map_cell_cc( self, ialpha, irot, irho ) result(cc)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: ialpha, irot, irho
        real(real64) :: cc
        cc = correlation_of(self, [ialpha, irot, irho], .false.)
    end function map_cell_cc

    ! the Euclidean cell with the shift's phase replaced by its Bessel series up to the ring's kept order
    pure function map_cell_bessel( self, ialpha, irot, irho ) result(l)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: ialpha, irot, irho
        real(real64) :: l
        l = loss_of(self, [ialpha, irot, irho], .true.)
    end function map_cell_bessel

    ! the correlation cell with the truncated Bessel series
    pure function map_cell_cc_bessel( self, ialpha, irot, irho ) result(cc)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: ialpha, irot, irho
        real(real64) :: cc
        cc = correlation_of(self, [ialpha, irot, irho], .true.)
    end function map_cell_cc_bessel

    ! every Euclidean cell, lmap(ialpha, irot, irho), direct or by the truncated Bessel series
    pure function map_table( self, truncated ) result(lmap)
        class(oracle_shiftmap), intent(in) :: self
        logical,                intent(in) :: truncated
        real(real64) :: lmap(self%nalpha, 2*self%pftsz, self%nrho)
        integer      :: ialpha, irot, irho
        do irho = 1, self%nrho
            do irot = 1, 2 * self%pftsz
                do ialpha = 1, self%nalpha
                    lmap(ialpha, irot, irho) = loss_of(self, [ialpha, irot, irho], truncated)
                end do
            end do
        end do
    end function map_table

    ! the mode of a table of cells at temperature temp: the first strict maximum of
    ! -temp L - prior rho**2 + log(area), rings outermost, then rotations, directions innermost; best =
    ! [irot, irho, ialpha] and loss is that cell's L. NaN cells are passed over; without any other, zeros and NaN
    subroutine map_mode( self, lmap, temp, best, loss )
        class(oracle_shiftmap), intent(in)  :: self
        real(real64),           intent(in)  :: lmap(:,:,:), temp
        integer,                intent(out) :: best(3)
        real(real64),           intent(out) :: loss
        real(real64) :: l, lbest
        integer      :: ialpha, irot, irho
        best  = 0
        loss  = ieee_value(loss, ieee_quiet_nan)
        lbest = 0._real64
        do irho = 1, self%nrho
            do irot = 1, 2 * self%pftsz
                do ialpha = 1, self%nalpha
                    l = log_weight(self, lmap(ialpha, irot, irho), temp, irho)
                    if( ieee_is_nan(l) ) cycle
                    if( best(1) == 0 )then
                        lbest = l
                        best  = [irot, irho, ialpha]
                    else if( l > lbest )then
                        lbest = l
                        best  = [irot, irho, ialpha]
                    endif
                end do
            end do
        end do
        if( best(1) > 0 ) loss = lmap(best(3), best(1), best(2))
    end subroutine map_mode

    ! the width of the shift distribution at the temperature tphys: -1 when a cutoff is given and loss exceeds
    ! it; else the root of the weighted mean of rho**2 less the squared mean shift, each rotation's shifts taken
    ! to the particle's frame, cells at or below the weight floor left out; NaN when the table holds a NaN
    function map_width( self, lmap, tphys, loss, cutoff ) result(sdev)
        class(oracle_shiftmap), intent(in) :: self
        real(real64),           intent(in) :: lmap(:,:,:), tphys, loss
        real(real64), optional, intent(in) :: cutoff
        real(real64) :: sdev, lmax, lphys, w, w0, w2, w1(2, 2*self%pftsz), mean(2), rho
        integer      :: ialpha, irot, irho, nrots
        logical      :: nan_cell
        if( present(cutoff) )then
            if( loss > cutoff )then
                sdev = -1._real64
                return
            endif
        endif
        nrots    = 2 * self%pftsz
        nan_cell = .false.
        lmax     = -huge(lmax)
        do irho = 1, self%nrho
            do irot = 1, nrots
                do ialpha = 1, self%nalpha
                    lphys = log_weight(self, lmap(ialpha, irot, irho), tphys, irho)
                    if( ieee_is_nan(lphys) ) nan_cell = .true.
                    lmax = max(lmax, lphys)
                end do
            end do
        end do
        if( nan_cell )then
            sdev = ieee_value(sdev, ieee_quiet_nan)
            return
        endif
        w0 = 0._real64
        w1 = 0._real64
        w2 = 0._real64
        do irho = 1, self%nrho
            rho = self%rho(irho)
            do irot = 1, nrots
                do ialpha = 1, self%nalpha
                    lphys = log_weight(self, lmap(ialpha, irot, irho), tphys, irho) - lmax
                    if( lphys <= LOG_WEIGHT_FLOOR ) cycle
                    w           = exp(lphys)
                    w0          = w0 + w
                    w1(:, irot) = w1(:, irot) + w * rho * [cos(self%alpha(ialpha)), sin(self%alpha(ialpha))]
                    w2          = w2 + w * rho**2
                end do
            end do
        end do
        mean = 0._real64
        do irot = 1, nrots
            mean = mean + matmul(w1(:, irot), oracle_polar_frame(irot, nrots))
        end do
        if( w0 > 0._real64 )then
            mean = mean / w0
            sdev = sqrt(max(0._real64, w2 / w0 - sum(mean**2)))
        else
            sdev = ieee_value(sdev, ieee_quiet_nan)
        endif
    end function map_width

    ! the last shell of the band production's maps share: max(kfrom + 1, kto / 2) in integers
    pure function oracle_shiftmap_kscreen( kfrom, kto ) result(kscreen)
        integer, intent(in) :: kfrom, kto
        integer :: kscreen
        kscreen = max(kfrom + 1, kto / 2)
    end function oracle_shiftmap_kscreen

    ! production's temperatures from the band's power: temp = beta pi wsq_band / (2 pftsz), temp_phys = temp / beta
    pure subroutine oracle_shiftmap_temps( wsq_band, pftsz, temp, temp_phys )
        real(real64), intent(in)  :: wsq_band
        integer,      intent(in)  :: pftsz
        real(real64), intent(out) :: temp, temp_phys
        temp      = PROB_BETA * PI * wsq_band / real(2 * pftsz, real64)
        temp_phys = temp / PROB_BETA
    end subroutine oracle_shiftmap_temps

    ! the checks against hand-worked numbers, closed forms and the polar oracle's direct loss, as named largest
    ! errors and their limits; a limit is not applied here
    subroutine oracle_shiftmap_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        integer :: icase
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        limits = CHECK_LIMITS
        errors = 0._real64
        call check_scalars(errors(1:2), errors(20))
        call check_bessel(errors(7))
        do icase = 1, NCASE
            call check_grid(icase, errors(3:6), errors(8))
            call check_cells(icase, errors(9:13))
        end do
        call check_retyped(errors(14))
        call check_mode(errors(15:16))
        call check_width(errors(17:19))
        call check_guard(errors(21))
    end subroutine oracle_shiftmap_selfcheck

    ! the smallest integer at least lo whose prime factors are all among 2, 3, 5 and 7
    pure function smooth_size( lo ) result(m)
        integer, intent(in) :: lo
        integer            :: m, r, j
        integer, parameter :: PRIMES(4) = [2, 3, 5, 7]
        m = max(1, lo)
        do
            r = m
            do j = 1, size(PRIMES)
                do while( modulo(r, PRIMES(j)) == 0 )
                    r = r / PRIMES(j)
                end do
            end do
            if( r == 1 ) exit
            m = m + 1
        end do
    end function smooth_size

    ! the weight of band column i: its shell's radius over its noise variance for the Euclidean cell, the radius
    ! alone for the correlation
    pure function band_weight( self, i, euclid ) result(w)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: i
        logical,                intent(in) :: euclid
        real(real64) :: w
        w = real(self%kfrom + i - 1, real64)
        if( euclid ) w = w / self%sigma2(i)
    end function band_weight

    ! the particle's weighted power on the band
    pure function power_sum( self, euclid ) result(pw)
        class(oracle_shiftmap), intent(in) :: self
        logical,                intent(in) :: euclid
        real(real64) :: pw
        integer      :: i
        pw = 0._real64
        do i = 1, self%nband
            pw = pw + band_weight(self, i, euclid) * sum(abs(self%ptcl(:, i))**2)
        end do
    end function power_sum

    ! the rotated reference's weighted power under the CTF modulus on the band; a shift does not change it
    pure function refpow_sum( self, irot, euclid ) result(rp)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: irot
        logical,                intent(in) :: euclid
        real(real64) :: rp, s
        integer      :: i, p
        rp = 0._real64
        do i = 1, self%nband
            s = 0._real64
            do p = 1, self%pftsz
                s = s + self%ctf(p, i)**2 * abs(self%ref(1 + modulo(p - irot, self%pftsz), i))**2
            end do
            rp = rp + band_weight(self, i, euclid) * s
        end do
    end function refpow_sum

    ! the weighted sum of Re(conj(X) C R(S A)) on the band at cell = [ialpha, irot, irho]: sample p reads the
    ! reference's full ring at q = p - (irot - 1), where the phase is exp(i z sin(theta_q - alpha)) or its
    ! truncated series, and the reference is conjugated on the second half
    pure function cross_sum( self, cell, euclid, truncated ) result(cross)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: cell(3)
        logical,                intent(in) :: euclid, truncated
        real(real64)              :: cross, s, z, phi
        real(real64), allocatable :: jm(:)
        complex(real64)           :: phase, a
        integer                   :: i, p, q, nh, nrots
        nrots = 2 * self%pftsz
        nh    = 0
        if( truncated ) nh = self%nharm(cell(3))
        allocate(jm(0:nh))
        cross = 0._real64
        do i = 1, self%nband
            z = TWOPI * real(self%kfrom + i - 1, real64) * self%rho(cell(3)) / real(self%box, real64)
            if( truncated ) jm = bessel_jn(0, nh, z)
            s = 0._real64
            do p = 1, self%pftsz
                q   = 1 + modulo(p - cell(2), nrots)
                phi = TWOPI * real(q - 1, real64) / real(nrots, real64) - self%alpha(cell(1))
                if( truncated )then
                    phase = bessel_phase(jm, phi)
                else
                    phase = cmplx(cos(z * sin(phi)), sin(z * sin(phi)), real64)
                endif
                if( q <= self%pftsz )then
                    a = self%ref(q, i)
                else
                    a = conjg(self%ref(q - self%pftsz, i))
                endif
                s = s + real(conjg(self%ptcl(p, i)) * self%ctf(p, i) * phase * a)
            end do
            cross = cross + band_weight(self, i, euclid) * s
        end do
    end function cross_sum

    ! the sum over the orders -nh .. nh of J_m exp(i m phi), given J_0 .. J_nh, with J_-m = (-1)**m J_m
    pure function bessel_phase( jm, phi ) result(s)
        real(real64), intent(in) :: jm(0:), phi
        complex(real64) :: s
        integer         :: m
        s = cmplx(jm(0), 0._real64, real64)
        do m = 1, ubound(jm, 1)
            if( modulo(m, 2) == 0 )then
                s = s + jm(m) * cmplx(2._real64 * cos(real(m, real64) * phi), 0._real64, real64)
            else
                s = s + jm(m) * cmplx(0._real64, 2._real64 * sin(real(m, real64) * phi), real64)
            endif
        end do
    end function bessel_phase

    ! the Euclidean cell, direct or truncated
    pure function loss_of( self, cell, truncated ) result(l)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: cell(3)
        logical,                intent(in) :: truncated
        real(real64) :: l, pw
        pw = power_sum(self, .true.)
        if( pw > 0._real64 )then
            l = 1._real64 + (refpow_sum(self, cell(2), .true.) - 2._real64 * cross_sum(self, cell, .true., truncated)) / pw
        else
            l = ieee_value(l, ieee_quiet_nan)
        endif
    end function loss_of

    ! the correlation cell, direct or truncated; NaN when a power is not positive
    pure function correlation_of( self, cell, truncated ) result(cc)
        class(oracle_shiftmap), intent(in) :: self
        integer,                intent(in) :: cell(3)
        logical,                intent(in) :: truncated
        real(real64) :: cc, pw, rp
        pw = power_sum(self, .false.)
        rp = refpow_sum(self, cell(2), .false.)
        if( pw > 0._real64 .and. rp > 0._real64 )then
            cc = cross_sum(self, cell, .false., truncated) / sqrt(rp * pw)
        else
            cc = ieee_value(cc, ieee_quiet_nan)
        endif
    end function correlation_of

    ! the log weight of a cell of ring irho with loss l at temperature t: -t l - prior rho**2 + log(area)
    pure function log_weight( self, l, t, irho ) result(lw)
        class(oracle_shiftmap), intent(in) :: self
        real(real64),           intent(in) :: l, t
        integer,                intent(in) :: irho
        real(real64) :: lw
        lw = -t * l - self%prior_w * self%rho(irho)**2 + log(self%area(irho))
    end function log_weight

    ! J_m(z) for any integer order by the trapezoid rule on (1 / 2 pi) int cos(m t - z sin t) dt over one turn,
    ! which converges spectrally: an evaluation independent of the intrinsic
    pure function bessel_integral( m, z ) result(j)
        integer,      intent(in) :: m
        real(real64), intent(in) :: z
        real(real64) :: j, t
        integer      :: it
        j = 0._real64
        do it = 0, NTRAP - 1
            t = TWOPI * real(it, real64) / real(NTRAP, real64)
            j = j + cos(real(m, real64) * t - z * sin(t))
        end do
        j = j / real(NTRAP, real64)
    end function bessel_integral

    ! kscreen on both branches, the 7-smooth sizes, and the temperatures against literals
    subroutine check_scalars( err, err_temps )
        real(real64), intent(inout) :: err(2), err_temps
        real(real64) :: temp, temp_phys
        integer      :: nbad
        nbad = 0
        if( oracle_shiftmap_kscreen(2, 9) /= 4 ) nbad = nbad + 1
        if( oracle_shiftmap_kscreen(5, 9) /= 6 ) nbad = nbad + 1
        if( oracle_shiftmap_kscreen(2, 7) /= 3 ) nbad = nbad + 1
        if( oracle_shiftmap_kscreen(3, 7) /= 4 ) nbad = nbad + 1
        if( oracle_shiftmap_kscreen(1, 4) /= 2 ) nbad = nbad + 1
        err(1) = real(nbad, real64)
        err(2) = real(count([smooth_size(1), smooth_size(7), smooth_size(11), smooth_size(13), smooth_size(17), &
                             smooth_size(23), smooth_size(29), smooth_size(37), smooth_size(43), smooth_size(51), &
                             smooth_size(97)] /= [1, 7, 12, 14, 18, 24, 30, 40, 45, 54, 98]), real64)
        ! a band power of 64 at pftsz 16: 0.6 pi and 2 pi
        call oracle_shiftmap_temps(64._real64, 16, temp, temp_phys)
        err_temps = nan_max(oracle_finite_or_inf(abs(temp - 1.8849555921538759_real64)), &
                        oracle_finite_or_inf(abs(temp_phys - 6.2831853071795862_real64)))
    end subroutine check_scalars

    ! the intrinsic Bessel function against the integral, orders 0 to 20 at arguments up to two turns of pi
    subroutine check_bessel( err )
        real(real64), intent(inout) :: err
        real(real64) :: z(6)
        integer      :: m, iz
        z = [0._real64, 1.178_real64, PI / 2._real64, PI, 1.5_real64 * PI, TWOPI]
        do iz = 1, size(z)
            do m = 0, 20
                err = nan_max(err, oracle_finite_or_inf(abs(bessel_jn(m, z(iz)) - bessel_integral(m, z(iz)))))
            end do
        end do
    end subroutine check_bessel

    ! one map's grid against its hand-worked numbers: counts, step, radii and directions, each ring's area, the
    ! areas' sum, and the kept Bessel orders
    subroutine check_grid( icase, err, err_nharm )
        integer,      intent(in)    :: icase
        real(real64), intent(inout) :: err(4), err_nharm
        type(oracle_polar_pair) :: pair
        type(oracle_shiftmap)   :: map
        real(real64)            :: step, rho, area_ref, total
        integer                 :: nrho, nalpha, d(3), i, nbad, g(4)
        nrho   = CASE_INT(3, icase)
        nalpha = CASE_INT(4, icase)
        step   = CASE_REAL(2, icase)
        call oracle_polar_fixture(CASE_INT(1, icase), 1, 1, pair)
        call map%new(pair, CASE_INT(2, icase), CASE_REAL(1, icase))
        g      = pair%geometry()
        d      = map%dims()
        err(1) = max(err(1), real(count(d /= [nalpha, 2 * g(1), nrho]), real64))
        if( any(d /= [nalpha, 2 * g(1), nrho]) )then
            ! the values below are indexed by the hand-worked counts
            err(2:4)  = max(err(2:4), 1._real64)
            err_nharm = max(err_nharm, 1._real64)
            return
        endif
        err(2) = nan_max(err(2), oracle_finite_or_inf(abs(map%step() - step)))
        total  = 0._real64
        nbad   = 0
        do i = 1, nrho
            rho    = real(i - 1, real64) * step
            err(2) = nan_max(err(2), oracle_finite_or_inf(abs(map%rho(i) - rho)))
            if( i == 1 )then
                area_ref = PI * step**2 / 4._real64 / real(nalpha, real64)
            else
                area_ref = TWOPI * rho * step / real(nalpha, real64)
            endif
            err(3) = nan_max(err(3), oracle_finite_or_inf(abs(map%area(i) - area_ref) / area_ref))
            total  = total + real(nalpha, real64) * map%area(i)
            if( map%nharm(i) /= NHARM_HAND(i, icase) ) nbad = nbad + 1
        end do
        do i = 1, nalpha
            err(2) = nan_max(err(2), oracle_finite_or_inf(abs(map%alpha(i) - real(i - 1, real64) * TWOPI / real(nalpha, real64))))
        end do
        area_ref  = PI * (real(nrho - 1, real64) * step + step / 2._real64)**2
        err(4)    = nan_max(err(4), oracle_finite_or_inf(abs(total - area_ref) / area_ref))
        err_nharm = max(err_nharm, real(nbad, real64))
        call map%kill()
        call pair%kill()
    end subroutine check_grid

    ! one map's cells on two fixture pairs: the band's power and both cells against the polar oracle's direct
    ! sums on the band, at shifts made from the hand-worked grid; the truncated forms against the direct cells
    subroutine check_cells( icase, err )
        integer,      intent(in)    :: icase
        real(real64), intent(inout) :: err(5)
        type(oracle_polar_pair)   :: pair, band
        type(oracle_shiftmap)     :: map
        real(real64), allocatable :: tab(:,:,:), tabb(:,:,:)
        real(real64)              :: shift(2), alpha, l, cc, lmax, ccmax, dl, dcc, direct
        integer                   :: ip, ialpha, irot, irho, g(4), d(3)
        do ip = 1, 2
            call oracle_polar_fixture(CASE_INT(1, icase), ip, ip, pair)
            call pair%band(CASE_INT(2, icase), band)
            call map%new(pair, CASE_INT(2, icase), CASE_REAL(1, icase))
            d = map%dims()
            if( any(d /= [CASE_INT(4, icase), band%nrots(), CASE_INT(3, icase)]) )then
                err = max(err, 1._real64)
                cycle
            endif
            ! the tables hold the cells
            if( allocated(tab) ) deallocate(tab, tabb)
            allocate(tab(d(1), d(2), d(3)), tabb(d(1), d(2), d(3)))
            tab    = map%table(.false.)
            tabb   = map%table(.true.)
            g      = band%geometry()
            err(1) = nan_max(err(1), oracle_finite_or_inf(abs(map%ptclpow() - band%wsq()) / band%wsq()))
            lmax   = 0._real64
            ccmax  = 0._real64
            dl     = 0._real64
            dcc    = 0._real64
            do irho = 1, CASE_INT(3, icase)
                do ialpha = 1, CASE_INT(4, icase)
                    alpha = real(ialpha - 1, real64) * TWOPI / real(CASE_INT(4, icase), real64)
                    shift = real(irho - 1, real64) * CASE_REAL(2, icase) * [cos(alpha), sin(alpha)]
                    do irot = 1, 2 * g(1)
                        l      = map%cell(ialpha, irot, irho)
                        cc     = map%cell_cc(ialpha, irot, irho)
                        direct = band%dist(irot, shift)
                        lmax   = nan_max(lmax, abs(direct))
                        dl     = nan_maxval([dl, oracle_finite_or_inf(abs(l - direct)), &
                                     oracle_finite_or_inf(abs(tab(ialpha, irot, irho) - l)), &
                                     oracle_finite_or_inf(abs(tabb(ialpha, irot, irho) - map%cell_bessel(ialpha, irot, irho)))])
                        direct = band%cc_weighted(irot, shift)
                        ccmax  = nan_max(ccmax, abs(direct))
                        dcc    = nan_max(dcc, oracle_finite_or_inf(abs(cc - direct)))
                        err(4) = nan_max(err(4), oracle_finite_or_inf(abs(map%cell_bessel(ialpha, irot, irho) - l)))
                        err(5) = nan_max(err(5), oracle_finite_or_inf(abs(map%cell_cc_bessel(ialpha, irot, irho) - cc)))
                    end do
                end do
            end do
            err(2) = max(err(2), oracle_finite_or_inf(dl / lmax))
            err(3) = max(err(3), oracle_finite_or_inf(dcc / ccmax))
        end do
        call map%kill()
        call pair%kill()
        call band%kill()
    end subroutine check_cells

    ! the truncated Euclidean cell against the retyped sum on a fixture pair, and on a pair whose reference and
    ! particle are single samples: there every order weighs alike, so one order too many or too few shows
    subroutine check_retyped( err )
        real(real64), intent(inout) :: err
        type(oracle_polar_pair)      :: pair, spike
        complex(real64), allocatable :: ref(:,:), ptcl(:,:)
        real(real64),    allocatable :: ctf(:,:), sigma2(:)
        integer                      :: g(4)
        call oracle_polar_fixture(CASE_INT(1, CASE_TABLES), 1, 1, pair)
        call retyped_error(pair, err)
        call pair%arrays(ref, ptcl, ctf, sigma2)
        g           = pair%geometry()
        ref         = (0._real64, 0._real64)
        ptcl        = (0._real64, 0._real64)
        ref(3, :)   = (1._real64, 2._real64)
        ptcl(5, :)  = (2._real64, -1._real64)
        ptcl(12, :) = (-1._real64, 0.5_real64)
        call spike%new(g(4), g(2), ref, ptcl)
        call spike%set_weights(ctf, sigma2)
        call retyped_error(spike, err)
        call pair%kill()
        call spike%kill()
    end subroutine check_retyped

    ! the truncated Euclidean cell of a pair's map against a sum retyped here over the orders -nh .. nh, nh the
    ! hand-worked count, with the Bessel functions of every order by the integral and the grid's hand-worked
    ! numbers; the largest difference over the largest retyped value, folded into err
    subroutine retyped_error( pair, err )
        type(oracle_polar_pair), intent(in)    :: pair
        real(real64),            intent(inout) :: err
        type(oracle_shiftmap)        :: map
        complex(real64), allocatable :: ref(:,:), ptcl(:,:)
        real(real64),    allocatable :: ctf(:,:), sigma2(:), jt(:,:)
        complex(real64)              :: phase, a
        real(real64)                 :: w, pw, rp, cross, s, phi, alpha, lref, dl, lmax
        integer                      :: g(4), nb, np, nh, i, p, q, m, ialpha, irot, irho
        call map%new(pair, CASE_INT(2, CASE_TABLES), CASE_REAL(1, CASE_TABLES))
        call pair%arrays(ref, ptcl, ctf, sigma2)
        g  = pair%geometry()
        np = g(1)
        nb = CASE_INT(2, CASE_TABLES) - g(2) + 1
        if( any(map%dims() /= [CASE_INT(4, CASE_TABLES), 2 * np, CASE_INT(3, CASE_TABLES)]) )then
            err = max(err, 1._real64)
            return
        endif
        allocate(jt(-NHARM_MAX:NHARM_MAX, nb))
        pw = 0._real64
        do i = 1, nb
            pw = pw + real(g(2) + i - 1, real64) / sigma2(i) * sum(abs(ptcl(:, i))**2)
        end do
        dl   = 0._real64
        lmax = 0._real64
        do irho = 1, CASE_INT(3, CASE_TABLES)
            nh = NHARM_HAND(irho, CASE_TABLES)
            jt = 0._real64
            do i = 1, nb
                do m = -nh, nh
                    jt(m, i) = bessel_integral(m, TWOPI * real(g(2) + i - 1, real64) * real(irho - 1, real64) * &
                                                  CASE_REAL(2, CASE_TABLES) / real(g(4), real64))
                end do
            end do
            do irot = 1, 2 * np
                do ialpha = 1, CASE_INT(4, CASE_TABLES)
                    alpha = real(ialpha - 1, real64) * TWOPI / real(CASE_INT(4, CASE_TABLES), real64)
                    rp    = 0._real64
                    cross = 0._real64
                    do i = 1, nb
                        w = real(g(2) + i - 1, real64) / sigma2(i)
                        s = 0._real64
                        do p = 1, np
                            q   = 1 + modulo(p - irot, 2 * np)
                            phi = TWOPI * real(p - irot, real64) / real(2 * np, real64) - alpha
                            if( q <= np )then
                                a = ref(q, i)
                            else
                                a = conjg(ref(q - np, i))
                            endif
                            phase = (0._real64, 0._real64)
                            do m = -nh, nh
                                phase = phase + jt(m, i) * exp(cmplx(0._real64, real(m, real64) * phi, real64))
                            end do
                            s  = s + real(conjg(ptcl(p, i)) * ctf(p, i) * phase * a)
                            rp = rp + w * ctf(p, i)**2 * abs(a)**2
                        end do
                        cross = cross + w * s
                    end do
                    lref = 1._real64 + (rp - 2._real64 * cross) / pw
                    lmax = nan_max(lmax, abs(lref))
                    dl   = nan_max(dl, oracle_finite_or_inf(abs(map%cell_bessel(ialpha, irot, irho) - lref)))
                end do
            end do
        end do
        err = max(err, oracle_finite_or_inf(dl / lmax))
        call map%kill()
    end subroutine retyped_error

    ! the mode on hand-made tables: four tied cells that every wrong loop order and a non-strict comparison
    ! would resolve differently, then tables without ties in which the prior, the area and the temperature
    ! each decide the ring
    subroutine check_mode( err )
        real(real64), intent(inout) :: err(2)
        type(oracle_polar_pair)   :: pair
        type(oracle_shiftmap)     :: map
        real(real64), allocatable :: lmap(:,:,:)
        real(real64)              :: loss
        integer                   :: d(3), best(3), nbad
        call oracle_polar_fixture(CASE_INT(1, CASE_TABLES), 1, 1, pair)
        call map%new(pair, CASE_INT(2, CASE_TABLES), CASE_REAL(1, CASE_TABLES))
        d = map%dims()
        if( any(d /= [14, 32, 4]) )then
            err = max(err, 1._real64)
            return
        endif
        allocate(lmap(d(1), d(2), d(3)))
        ! ties: a loss of -1e30 absorbs the prior and the area, so the four cells weigh the same exactly; the
        ! first in the order rings, rotations, directions is (ialpha 2, irot 4, irho 1)
        call map%set_prior(sqrt(10._real64))
        lmap          = 0._real64
        lmap(3, 5, 1) = -1.e30_real64
        lmap(1, 2, 2) = -1.e30_real64
        lmap(1, 5, 1) = -1.e30_real64
        lmap(2, 4, 1) = -1.e30_real64
        call map%mode(lmap, 1._real64, best, loss)
        err(1) = max(err(1), real(count(best /= [4, 1, 2]), real64))
        if( .not. (abs(loss + 1.e30_real64) <= 0._real64) ) err(1) = max(err(1), 1._real64)
        ! no ties, rings at 0, 2, 4 and 6 with areas as 1, 8, 16 and 24, prior weight 0.05: a constant loss puts
        ! the mode on the third ring, at its first rotation and direction
        nbad = 0
        lmap = 0._real64
        call map%mode(lmap, 1._real64, best, loss)
        nbad = nbad + count(best /= [1, 3, 1])
        if( .not. (abs(loss) <= 0._real64) ) nbad = nbad + 1
        ! one cell of the second ring half a unit lower: the temperature 1 lifts it above the third ring, the
        ! temperature 0.1 does not
        lmap(2, 3, 2) = -0.5_real64
        call map%mode(lmap, 1._real64, best, loss)
        nbad = nbad + count(best /= [3, 2, 2])
        if( .not. (abs(loss + 0.5_real64) <= 0._real64) ) nbad = nbad + 1
        call map%mode(lmap, 0.1_real64, best, loss)
        nbad = nbad + count(best /= [1, 3, 1])
        if( .not. (abs(loss) <= 0._real64) ) nbad = nbad + 1
        ! the last cell of the table five units lower: every loop reaches its end
        lmap            = 0._real64
        lmap(14, 32, 4) = -5._real64
        call map%mode(lmap, 1._real64, best, loss)
        nbad = nbad + count(best /= [32, 4, 14])
        if( .not. (abs(loss + 5._real64) <= 0._real64) ) nbad = nbad + 1
        err(2) = max(err(2), real(nbad, real64))
        call map%kill()
        call pair%kill()
    end subroutine check_mode

    ! the width on hand-made tables: two cells whose shifts meet head-on only in the particle's frame; two rings
    ! weighed by the prior and the area; the weight floor; the cutoff
    subroutine check_width( err )
        real(real64), intent(inout) :: err(3)
        type(oracle_polar_pair)   :: pair
        type(oracle_shiftmap)     :: map
        real(real64), allocatable :: lmap(:,:,:)
        real(real64)              :: sdev, wa, w
        integer                   :: d(3), nbad
        ! twelve directions and 32 rotations: direction 10 and rotation 25 are three quarter turns; rings at 0, 2, 4
        call oracle_polar_fixture(CASE_INT(1, CASE_QUARTER), 1, 1, pair)
        call map%new(pair, CASE_INT(2, CASE_QUARTER), CASE_REAL(1, CASE_QUARTER))
        d = map%dims()
        if( any(d /= [12, 32, 3]) )then
            err = max(err, 1._real64)
            return
        endif
        allocate(lmap(d(1), d(2), d(3)))
        ! weights 1 and 1/2 on the second ring: the shift (2, 0) unrotated, and the shift (0, -2) at three quarters
        ! of a turn, which is (-2, 0) in the particle's frame: mean 2/3, mean square 4, width sqrt(32) / 3; at
        ! twice the temperature the weights are 1 and 1/4, the mean 1.2 and the width 1.6
        lmap            = 1000._real64
        lmap(1, 1, 2)   = 0._real64
        lmap(10, 25, 2) = log(2._real64)
        sdev   = map%width(lmap, 1._real64, 0._real64)
        err(1) = nan_max(err(1), oracle_finite_or_inf(abs(sdev - sqrt(32._real64) / 3._real64)))
        sdev   = map%width(lmap, 2._real64, 0._real64)
        err(1) = nan_max(err(1), oracle_finite_or_inf(abs(sdev - 1.6_real64)))
        ! the cutoff: -1 only when the loss exceeds it
        nbad = 0
        w    = map%width(lmap, 2._real64, 0.3_real64, cutoff=0.2_real64)
        if( .not. (abs(w + 1._real64) <= 0._real64) ) nbad = nbad + 1
        w    = map%width(lmap, 2._real64, 0.3_real64, cutoff=0.3_real64)
        if( .not. (abs(w - sdev) <= 0._real64) ) nbad = nbad + 1
        w    = map%width(lmap, 2._real64, 0.3_real64, cutoff=0.4_real64)
        if( .not. (abs(w - sdev) <= 0._real64) ) nbad = nbad + 1
        err(3) = max(err(3), real(nbad, real64))
        ! equal losses on the rings at 2 and 4 along one direction, prior weight 0.05: the outer cell weighs 1
        ! and the inner wa = exp(0.6) / 2 (the prior's 0.05 (16 - 4) against the areas' factor 2), so the width
        ! of the two points 2 apart is 2 sqrt(wa) / (1 + wa)
        call map%set_prior(sqrt(10._real64))
        lmap          = 1000._real64
        lmap(1, 1, 2) = 0._real64
        lmap(1, 1, 3) = 0._real64
        wa     = exp(0.6_real64) / 2._real64
        sdev   = map%width(lmap, 1._real64, 0._real64)
        err(1) = nan_max(err(1), oracle_finite_or_inf(abs(sdev - 2._real64 * sqrt(wa) / (1._real64 + wa))))
        ! the weight floor, without a prior: all weight on the centre ring and one cell of the last ring (6
        ! pixels out, 24 times the centre's area) at a log weight of -41, which is left out, so the width is
        ! exactly zero; at -39 it is kept and the width is 6 sqrt(w) / (1 + w)
        call oracle_polar_fixture(CASE_INT(1, CASE_TABLES), 1, 1, pair)
        call map%new(pair, CASE_INT(2, CASE_TABLES), CASE_REAL(1, CASE_TABLES))
        d = map%dims()
        if( any(d /= [14, 32, 4]) )then
            err(2) = max(err(2), 1._real64)
            return
        endif
        deallocate(lmap)
        allocate(lmap(d(1), d(2), d(3)))
        lmap          = 1000._real64
        lmap(1, 1, 1) = 0._real64
        lmap(1, 1, 4) = 41._real64 + log(24._real64)
        err(2) = nan_max(err(2), oracle_finite_or_inf(abs(map%width(lmap, 1._real64, 0._real64))))
        lmap(1, 1, 4) = 39._real64 + log(24._real64)
        w      = 6._real64 * sqrt(exp(-39._real64)) / (1._real64 + exp(-39._real64))
        err(2) = nan_max(err(2), oracle_finite_or_inf(abs(map%width(lmap, 1._real64, 0._real64) - w) / w))
        ! a log weight of exactly -40 is left out too. At losses near -2**52 a log weight is an integer: the
        ! centre's, 1000 + log(pi / 14), rounds to 999 and the last ring's, 957 + log(24 pi / 14), to 959, above
        ! the common 2**52. Kept, that cell would give a width of 6 exp(-20)
        lmap(1, 1, 1) = -(2._real64**52 + 1000._real64)
        lmap(1, 1, 4) = -(2._real64**52 + 957._real64)
        err(2) = nan_max(err(2), oracle_finite_or_inf(abs(map%width(lmap, 1._real64, 0._real64))))
        call map%kill()
        call pair%kill()
    end subroutine check_width

    ! a zero particle has no defined cell: NaN, counted when it is not; NaN cells in the mode and the width
    subroutine check_guard( err )
        real(real64), intent(inout) :: err
        type(oracle_polar_pair)      :: pair, empty
        type(oracle_shiftmap)        :: map
        complex(real64), allocatable :: ref(:,:), ptcl(:,:)
        real(real64),    allocatable :: ctf(:,:), sigma2(:), lmap(:,:,:)
        real(real64)                 :: loss
        integer                      :: g(4), d(3), best(3), nbad
        call oracle_polar_fixture(1, 1, 1, pair)
        call pair%arrays(ref, ptcl, ctf, sigma2)
        g    = pair%geometry()
        ptcl = (0._real64, 0._real64)
        call empty%new(g(4), g(2), ref, ptcl)
        call empty%set_weights(ctf, sigma2)
        call map%new(empty, 4, 5._real64)
        nbad = 0
        if( .not. ieee_is_nan(map%cell(2, 3, 2)) ) nbad = nbad + 1
        if( .not. ieee_is_nan(map%cell_cc(2, 3, 2)) ) nbad = nbad + 1
        if( .not. ieee_is_nan(map%cell_bessel(2, 3, 2)) ) nbad = nbad + 1
        if( .not. ieee_is_nan(map%cell_cc_bessel(2, 3, 2)) ) nbad = nbad + 1
        ! its table is NaN throughout: no mode, and no width
        d = map%dims()
        allocate(lmap(d(1), d(2), d(3)))
        lmap = map%table(.false.)
        call map%mode(lmap, 1._real64, best, loss)
        if( any(best /= 0) .or. .not. ieee_is_nan(loss) ) nbad = nbad + 1
        if( .not. ieee_is_nan(map%width(lmap, 1._real64, 0._real64)) ) nbad = nbad + 1
        ! one NaN cell in a table of zeros is passed over by the mode and makes the width NaN
        lmap          = 0._real64
        lmap(1, 1, 1) = loss
        call map%mode(lmap, 1._real64, best, loss)
        if( any(best /= [1, 3, 1]) ) nbad = nbad + 1
        if( .not. ieee_is_nan(map%width(lmap, 1._real64, 0._real64)) ) nbad = nbad + 1
        err = max(err, real(nbad, real64))
        call map%kill()
        call pair%kill()
        call empty%kill()
    end subroutine check_guard

end module mlxf_oracle_polar_shiftmap
