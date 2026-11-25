!@descr: host oracle of the pose objective: prepared reference, quadratic B-spline gather, objectives, derivatives, solve
! A real box**3 volume is embedded in n = 2 box per side with its origin at index n/2 + 1, divided by the window's
! transform and transformed with 1 / box**3; frequency q is stored at 1 + modulo(q, n). Fourier pixel (h, k) reads it
! at loc = 2 R^T (h, k, 0) through a quadratic B-spline on 27 voxels, times the CTF modulus and the shift's phase
! exp(+2 pi i (h s1 + k s2) / box). Pixel arrays are (box + 1, box + 1), pixel (h, k) at (h + box/2 + 1, k + box/2 + 1);
! rotation increments are rotation vectors applied on the right. Plain Fortran on intrinsic modules and the oracles.
module mlxf_oracle_pose
use, intrinsic :: iso_fortran_env, only: real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_quiet_nan
use mlxf_oracle_dft, only: oracle_dft_3d, oracle_finite_or_inf
implicit none

public :: oracle_pose_problem, oracle_pose_euler, oracle_pose_rotate, oracle_pose_reference, oracle_pose_gather, &
          oracle_pose_fixture, oracle_pose_fixture_pose, oracle_pose_selfcheck
private

real(real64),    parameter :: PI    = acos(-1._real64)
real(real64),    parameter :: TWOPI = 2._real64 * PI
complex(real64), parameter :: CZERO = (0._real64, 0._real64)
! the padding of the reference, and the shape of the Kaiser-Bessel window whose envelope prepares it
integer,         parameter :: PADFAC  = 2
real(real64),    parameter :: KB_BETA = PI * sqrt(2.25_real64 * 1.5_real64**2 - 0.8_real64)
integer,         parameter :: MAXTERM = 500
! a power not above this has no objective; the clamp of the curvature scale
real(real64),    parameter :: EPS       = epsilon(1._real64)
real(real64),    parameter :: POW_FLOOR = EPS**2
real(real64),    parameter :: SCALE_MIN = 0.05_real64
real(real64),    parameter :: SCALE_MAX = 20._real64
! the solve: parameter scaling, the stops, the caps of a step, the acceptance ratios and the damping schedule
real(real64),    parameter :: SOLVE_SC(5)  = [0.1_real64, 0.1_real64, 0.1_real64, 1._real64, 1._real64]
real(real64),    parameter :: GRAD_STOP    = 1.e-8_real64
real(real64),    parameter :: PRED_STOP    = 1.e-6_real64
real(real64),    parameter :: STEP_STOP    = 1.e-8_real64
real(real64),    parameter :: REL_STOP     = 1.e-6_real64
real(real64),    parameter :: ROT_CAP      = 0.1_real64
real(real64),    parameter :: SHIFT_CAP    = 1._real64
real(real64),    parameter :: ACCEPT_RATIO = 0.25_real64
real(real64),    parameter :: RELAX_RATIO  = 0.75_real64
real(real64),    parameter :: MU_START     = 1.e-3_real64
real(real64),    parameter :: MULT_START   = 4._real64
integer,         parameter :: MAX_REJECT   = 8
integer,         parameter :: MAXITER      = 40
! why a solve ended: gradient below its stop, small step or small relative decrease after an accepted step,
! predicted decrease below its stop, a pivot of the matrix not above its floor, rejections in a row, iterations.
! A solve's trace holds per iteration: the objective held after it, the damping of its step, 1 or 0 for
! accepted, the step's rotation and shift lengths, the predicted decrease, the trial objective (NaN if none)
integer,         parameter :: STATUS_GRADIENT  = 0
integer,         parameter :: STATUS_STEP      = 1
integer,         parameter :: STATUS_PREDICTED = 2
integer,         parameter :: STATUS_NOT_PD    = 3
integer,         parameter :: STATUS_REJECTED  = 4
integer,         parameter :: STATUS_LIMIT     = 5
! the fixture: a box of 16 with three Gaussian blobs (amplitude, centre in centred coordinates, width) by columns
integer, parameter :: FIX_BOX = 16
real(real64),    parameter :: BLOBS(5, 3) = reshape([1._real64, 1.5_real64, -1._real64, 0.5_real64, 1.2_real64, &
    0.7_real64, -2._real64, 1.5_real64, -1._real64, 1.6_real64, 0.5_real64, 0.5_real64, 2._real64, 2.5_real64, &
    0.9_real64], [5, 3])
! its bands: shells 1 to 7 for the Euclidean objective, 0 to 7 for the correlation
integer, parameter :: FIX_KTO = 7
! its planted pose (Euler angles and shift), the displacement of the start (a rotation vector on the right and a
! shift), and the factor of the particle that is a multiple of the model
real(real64),    parameter :: PLANT_EULER(3)    = [0.6_real64, 1._real64, -0.4_real64]
real(real64),    parameter :: PLANT_SHIFT(2)    = [0.8_real64, -1.3_real64]
real(real64),    parameter :: DISPLACE_OMEGA(3) = 0.05_real64 * [2._real64, -1._real64, 2._real64] / 3._real64
real(real64),    parameter :: DISPLACE_SHIFT(2) = [0.3_real64, -0.4_real64]
real(real64),    parameter :: MULTIPLE          = 2.5_real64
! the self-check: the step of central differences, the least distance of a coordinate from a half-integer where
! they are taken, the points of the trapezoid rule for I0, the window's two weights as they are quoted to seven
! decimals where the window is specified, and the limits
real(real64),    parameter :: DIFF_STEP   = 1.e-5_real64
real(real64),    parameter :: MIN_MARGIN  = 1.e-3_real64
integer,         parameter :: NTRAP       = 64
real(real64),    parameter :: W0_PRINTED  = 0.6906488_real64
real(real64),    parameter :: W1_PRINTED  = 0.1546756_real64
real(real64),    parameter :: TOL_ROUTE   = 1.e-12_real64
real(real64),    parameter :: TOL_DIFF    = 1.e-7_real64
real(real64),    parameter :: TOL_CELL    = 1.e-10_real64
real(real64),    parameter :: TOL_SOLVE   = 1.e-6_real64
real(real64),    parameter :: TOL_PRINTED = 5.e-8_real64
! a step of the solve is short below this length in both parts; its predicted decrease is compared with the
! actual one when it is above the rounding of an objective, to this relative limit
real(real64),    parameter :: SHORT_STEP      = 1.e-3_real64
real(real64),    parameter :: LEAST_PREDICTED = 1.e-10_real64
real(real64),    parameter :: TOL_PREDICTED   = 1.e-2_real64
! the limit on a first step recomputed by another elimination of the same five equations
real(real64),    parameter :: TOL_FIRST_STEP  = 1.e-9_real64
integer,         parameter :: NCHECK    = 32
integer,         parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'counts', 'i0 series', 'kb weights printed', 'envelopes by hand', 'euler and increment', 'transform vs sum', &
    'hermitian', 'gather vs kernel sum', 'gather at lattice', 'gather slope in cell', 'margins', &
    'model at lattice', 'powers by count', 'objectives vs plane', 'euclid zero residual', 'euclid multiple', &
    'euclid matrix', 'euclid gradient', 'cc zero residual', 'cc multiple', 'cc matrix', 'cc gradient', &
    'shift terms euclid', 'shift terms cc', 'nan floor', 'solve euclid rotation', 'solve euclid shift', &
    'solve cc rotation', 'solve cc shift', 'solve history', 'solve at solution', 'solve rules']
real(real64),    parameter :: CHECK_LIMITS(NCHECK) = [0._real64, TOL_ROUTE, TOL_PRINTED, TOL_ROUTE, TOL_ROUTE, &
    TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_CELL, 0._real64, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, &
    TOL_ROUTE, TOL_DIFF, TOL_DIFF, TOL_ROUTE, TOL_ROUTE, TOL_DIFF, TOL_DIFF, TOL_ROUTE, TOL_ROUTE, 0._real64, &
    TOL_SOLVE, TOL_SOLVE, TOL_SOLVE, TOL_SOLVE, 0._real64, 0._real64, 0._real64]

! one particle against one reference: the prepared reference, the band, the objective, and the particle's pixels
! and CTF modulus with the objective's weights applied
type :: oracle_pose_problem
    private
    integer                      :: box = 0, kfrom = 0, kto = 0
    logical                      :: euclid = .true., exists = .false.
    complex(real64), allocatable :: f(:,:,:), x(:,:)
    real(real64),    allocatable :: t(:,:)
  contains
    procedure :: new => pose_new
    procedure :: kill => pose_kill
    procedure :: set_particle => pose_set_particle
    procedure :: npixels => pose_npixels
    procedure :: power => pose_power
    procedure :: model => pose_model
    procedure :: objective => pose_objective
    procedure :: derivatives => pose_derivatives
    procedure :: shift_derivatives => pose_shift_derivatives
    procedure :: scale => pose_scale
    procedure :: solve => pose_solve
end type oracle_pose_problem

! the sums of one evaluation, each over the half plane doubled plus the central pixel where it counts
type :: pose_sums
    real(real64) :: ppow = 0._real64, res = 0._real64, cross = 0._real64, mm = 0._real64, wc = 0._real64
    real(real64) :: wpow = 0._real64, g(5) = 0._real64, gx(5) = 0._real64, mg(5) = 0._real64, h(5, 5) = 0._real64
end type pose_sums

contains

    ! a problem from a real cube vol(box, box, box), box even, on the shells kfrom .. kto, kto below box/2; the
    ! objective is the correlation for 'cc' and the Euclidean one otherwise. No particle until set_particle
    subroutine pose_new( self, vol, kfrom, kto, objective )
        class(oracle_pose_problem), intent(inout) :: self
        real(real64),               intent(in)    :: vol(:,:,:)
        integer,                    intent(in)    :: kfrom, kto
        character(len=*),           intent(in)    :: objective
        integer :: b2
        call self%kill()
        self%box    = size(vol, 1)
        self%kfrom  = kfrom
        self%kto    = kto
        self%euclid = objective /= 'cc'
        b2          = self%box / 2
        allocate(self%f(PADFAC*self%box, PADFAC*self%box, PADFAC*self%box), self%x(-b2:b2, -b2:b2), self%t(-b2:b2, -b2:b2))
        self%f      = oracle_pose_reference(vol)
        self%x      = CZERO
        self%t      = 0._real64
        self%exists = .true.
    end subroutine pose_new

    ! release the arrays; idempotent
    subroutine pose_kill( self )
        class(oracle_pose_problem), intent(inout) :: self
        if( .not. self%exists ) return
        deallocate(self%f, self%x, self%t)
        self%box    = 0
        self%exists = .false.
    end subroutine pose_kill

    ! the particle: Fourier pixels observed(box + 1, box + 1), the CTF ctf of the same shape, of which the modulus
    ! is taken, and the noise variances sigma2(1 + shell), kto + 1 of them, read by the Euclidean objective only
    subroutine pose_set_particle( self, observed, ctf, sigma2 )
        class(oracle_pose_problem), intent(inout) :: self
        complex(real64),            intent(in)    :: observed(:,:)
        real(real64),               intent(in)    :: ctf(:,:), sigma2(:)
        real(real64) :: w
        integer      :: h, k, b2, sh
        if( .not. self%exists ) return
        b2     = self%box / 2
        self%x = CZERO
        self%t = 0._real64
        do k = -b2, b2
            do h = -b2, b2
                sh = shell_of(h, k, self%box)
                if( sh < self%kfrom .or. sh > self%kto ) cycle
                w = 1._real64
                if( self%euclid ) w = 1._real64 / sqrt(sigma2(1 + sh))
                self%x(h, k) = observed(h + b2 + 1, k + b2 + 1) * w
                self%t(h, k) = abs(ctf(h + b2 + 1, k + b2 + 1)) * w
            end do
        end do
    end subroutine pose_set_particle

    ! the number of pixels the objective sums: the half plane's pixels in the band, and the central pixel when
    ! the band starts at shell 0
    pure function pose_npixels( self ) result(n)
        class(oracle_pose_problem), intent(in) :: self
        integer :: n, h, k
        n = 0
        do k = -self%kto, self%kto
            do h = merge(0, 1, k > 0), self%kto
                if( in_band(self, h, k) ) n = n + 1
            end do
        end do
        if( self%kfrom == 0 ) n = n + 1
    end function pose_npixels

    ! the particle's weighted power: twice the half plane's sum of |X|**2, plus the central pixel's when the band
    ! starts at shell 0
    pure function pose_power( self ) result(pw)
        class(oracle_pose_problem), intent(in) :: self
        real(real64) :: pw
        integer      :: h, k
        pw = 0._real64
        do k = -self%kto, self%kto
            do h = merge(0, 1, k > 0), self%kto
                if( in_band(self, h, k) ) pw = pw + 2._real64 * abs(self%x(h, k))**2
            end do
        end do
        if( self%kfrom == 0 ) pw = pw + abs(self%x(0, 0))**2
    end function pose_power

    ! the unweighted model at a pose on every pixel within box/2 of the centre, zero outside: the shift's phase
    ! times the modulus of ctf(box + 1, box + 1) times the gathered reference. A particle made of it has no
    ! residual at that pose
    function pose_model( self, ctf, r, shift ) result(m)
        class(oracle_pose_problem), intent(in) :: self
        real(real64),               intent(in) :: ctf(:,:), r(3, 3), shift(2)
        complex(real64) :: m(self%box+1, self%box+1), v, dv(3)
        integer         :: h, k, b2
        b2 = self%box / 2
        m  = CZERO
        do k = -b2, b2
            do h = -b2, b2
                if( shell_of(h, k, self%box) < 0 ) cycle
                call oracle_pose_gather(self%f, pixel_loc(h, k, r), v, dv)
                m(h + b2 + 1, k + b2 + 1) = pixel_phase(h, k, shift, self%box) * abs(ctf(h + b2 + 1, k + b2 + 1)) * v
            end do
        end do
    end function pose_model

    ! the objective at rotation r and shift (pixels of the box): the Euclidean loss, the residual's power over
    ! the particle's, or one minus the correlation; NaN when a power it divides by is not above the floor
    function pose_objective( self, r, shift ) result(f)
        class(oracle_pose_problem), intent(in) :: self
        real(real64),               intent(in) :: r(3, 3), shift(2)
        real(real64)    :: f
        type(pose_sums) :: s
        call full_sums(self, r, shift, s)
        if( no_objective(self, s) )then
            f = ieee_value(1._real64, ieee_quiet_nan)
        else if( self%euclid )then
            f = s%res / s%ppow
        else
            f = 1._real64 - s%cross / sqrt(s%ppow * s%mm)
        endif
    end function pose_objective

    ! the gradient in the order (three rotation components, two shift components) and the 5 by 5 symmetric
    ! matrix of the solve: the Gauss-Newton matrix times the clamped curvature scale, for the correlation its
    ! projected form; NaN with the objective
    subroutine pose_derivatives( self, r, shift, grad, mat )
        class(oracle_pose_problem), intent(in)  :: self
        real(real64),               intent(in)  :: r(3, 3), shift(2)
        real(real64),               intent(out) :: grad(5), mat(5, 5)
        type(pose_sums) :: s
        real(real64)    :: nrm
        integer         :: a, b
        call full_sums(self, r, shift, s)
        if( no_objective(self, s) )then
            grad = ieee_value(1._real64, ieee_quiet_nan)
            mat  = ieee_value(1._real64, ieee_quiet_nan)
        else if( self%euclid )then
            grad = 2._real64 * s%g / s%ppow
            mat  = scale_of(self, s) * 2._real64 * s%h / s%ppow
        else
            nrm  = sqrt(s%ppow * s%mm)
            grad = -s%gx / nrm + s%cross * s%mg / (nrm * s%mm)
            do b = 1, 5
                do a = 1, 5
                    mat(a, b) = scale_of(self, s) * (s%h(a, b) / s%mm - s%mg(a) * s%mg(b) / s%mm**2)
                end do
            end do
        endif
    end subroutine pose_derivatives

    ! the shift's two entries of the gradient and its 2 by 2 block of the matrix, from the sums that need no
    ! derivative of the gather
    subroutine pose_shift_derivatives( self, r, shift, grad, mat )
        class(oracle_pose_problem), intent(in)  :: self
        real(real64),               intent(in)  :: r(3, 3), shift(2)
        real(real64),               intent(out) :: grad(2), mat(2, 2)
        type(pose_sums) :: s
        real(real64)    :: nrm
        call shift_sums(self, r, shift, s)
        if( no_objective(self, s) )then
            grad = ieee_value(1._real64, ieee_quiet_nan)
            mat  = ieee_value(1._real64, ieee_quiet_nan)
        else if( self%euclid )then
            grad = 2._real64 * s%g(4:5) / s%ppow
            mat  = scale_of(self, s) * 2._real64 * s%h(4:5, 4:5) / s%ppow
        else
            nrm  = sqrt(s%ppow * s%mm)
            grad = s%g(4:5) / nrm
            mat  = scale_of(self, s) * s%h(4:5, 4:5) / s%mm
        endif
    end subroutine pose_shift_derivatives

    ! the curvature scale of the matrix at a pose, clamped to [0.05, 20]; NaN with the objective
    function pose_scale( self, r, shift ) result(sc)
        class(oracle_pose_problem), intent(in) :: self
        real(real64),               intent(in) :: r(3, 3), shift(2)
        real(real64)    :: sc
        type(pose_sums) :: s
        call full_sums(self, r, shift, s)
        if( no_objective(self, s) )then
            sc = ieee_value(1._real64, ieee_quiet_nan)
        else
            sc = scale_of(self, s)
        endif
    end function pose_scale

    ! a damped least-squares solve from the pose in r and shift, which return the result if its objective is
    ! strictly below the start's and the start otherwise; trace holds a column of seven numbers per iteration
    ! and status the stop, both as the status constants' comment lists them
    subroutine pose_solve( self, r, shift, trace, status )
        class(oracle_pose_problem), intent(in)    :: self
        real(real64),               intent(inout) :: r(3, 3), shift(2)
        real(real64), allocatable,  intent(out)   :: trace(:,:)
        integer,                    intent(out)   :: status
        real(real64) :: tr(7, MAXITER), r0(3, 3), s0(2), rt(3, 3), st(2), g(5), c(5, 5), gs(5), cs(5, 5), damped(5, 5)
        real(real64) :: l(5, 5), d(5), f, f0, ft, mu, mult, cmax, pred, actual, dnorm
        integer      :: it, niter, nrej, a
        logical      :: ok, accepted, small
        r0     = r
        s0     = shift
        f      = self%objective(r, shift)
        f0     = f
        mu     = MU_START
        mult   = MULT_START
        nrej   = 0
        niter  = 0
        status = STATUS_LIMIT
        call self%derivatives(r, shift, g, c)
        do it = 1, MAXITER
            gs = SOLVE_SC * g
            do a = 1, 5
                cs(:, a) = SOLVE_SC * c(:, a) * SOLVE_SC(a)
            end do
            if( norm2(gs) < GRAD_STOP )then
                status = STATUS_GRADIENT
                exit
            endif
            cmax = maxval(abs(cs))
            call cholesky_factor(cs, sqrt(EPS) * cmax, l, ok)
            if( .not. ok )then
                status = STATUS_NOT_PD
                exit
            endif
            damped = cs
            do a = 1, 5
                damped(a, a) = damped(a, a) + mu * max(cs(a, a), sqrt(EPS) * cmax, EPS**2)
            end do
            call cholesky_factor(damped, 0._real64, l, ok)
            if( .not. ok )then
                status = STATUS_NOT_PD
                exit
            endif
            d = SOLVE_SC * cholesky_solve(l, -gs)
            ! each part's length is capped apart
            dnorm = norm2(d(1:3))
            if( dnorm > ROT_CAP ) d(1:3) = d(1:3) * ROT_CAP / dnorm
            dnorm = norm2(d(4:5))
            if( dnorm > SHIFT_CAP ) d(4:5) = d(4:5) * SHIFT_CAP / dnorm
            pred     = -dot_product(g, d) - 0.5_real64 * dot_product(d, matmul(c, d))
            niter    = it
            accepted = .false.
            actual   = 0._real64
            ft       = ieee_value(1._real64, ieee_quiet_nan)
            if( pred > 0._real64 )then
                if( pred < PRED_STOP * max(abs(f), EPS**2) )then
                    tr(:, it) = [f, mu, 0._real64, norm2(d(1:3)), norm2(d(4:5)), pred, ieee_value(1._real64, ieee_quiet_nan)]
                    status    = STATUS_PREDICTED
                    exit
                endif
                rt     = oracle_pose_rotate(r, d(1:3))
                st     = shift + d(4:5)
                ft     = self%objective(rt, st)
                actual = f - ft
                ! a trial objective that is not a number fails both comparisons
                if( actual > 0._real64 )then
                    accepted = actual / pred >= ACCEPT_RATIO
                endif
            endif
            if( accepted )then
                tr(:, it) = [ft, mu, 1._real64, norm2(d(1:3)), norm2(d(4:5)), pred, ft]
                if( actual / pred > RELAX_RATIO ) mu = max(mu / 2._real64, EPS)
                mult  = MULT_START
                nrej  = 0
                small = (norm2(d(1:3)) < STEP_STOP .and. norm2(d(4:5)) < STEP_STOP) .or. actual < REL_STOP * abs(f)
                r     = rt
                shift = st
                f     = ft
                call self%derivatives(r, shift, g, c)
                if( small )then
                    status = STATUS_STEP
                    exit
                endif
            else
                tr(:, it) = [f, mu, 0._real64, norm2(d(1:3)), norm2(d(4:5)), pred, ft]
                mu   = min(mu * mult, 1._real64 / EPS)
                mult = 2._real64 * mult
                nrej = nrej + 1
                if( nrej == MAX_REJECT )then
                    status = STATUS_REJECTED
                    exit
                endif
            endif
        end do
        if( .not. (f < f0) )then
            r     = r0
            shift = s0
        endif
        allocate(trace(7, niter))
        trace = tr(:, 1:niter)
    end subroutine pose_solve

    ! the rotation matrix of the Euler angles (e1, e2, e3): Rz(e3) Ry(e2) Rz(e1), with rows [c, s, 0], [-s, c, 0],
    ! [0, 0, 1] in Rz and [c, 0, -s], [0, 1, 0], [s, 0, c] in Ry
    pure function oracle_pose_euler( e1, e2, e3 ) result(r)
        real(real64), intent(in) :: e1, e2, e3
        real(real64) :: r(3, 3), z1(3, 3), y2(3, 3), z3(3, 3)
        z1 = rot_z(e1)
        y2 = rot_y(e2)
        z3 = rot_z(e3)
        r  = matmul(z3, matmul(y2, z1))
    end function oracle_pose_euler

    ! the rotation r incremented on the right by the rotation vector omega: r exp([omega]x), by Rodrigues'
    ! formula with [omega]x of rows [0, -o3, o2], [o3, 0, -o1], [-o2, o1, 0]
    pure function oracle_pose_rotate( r, omega ) result(rnew)
        real(real64), intent(in) :: r(3, 3), omega(3)
        real(real64) :: rnew(3, 3), k(3, 3), e(3, 3), theta, a, b
        integer      :: i
        theta = norm2(omega)
        k     = cross_matrix(omega)
        if( theta > 0._real64 )then
            a = sin(theta) / theta
            b = 2._real64 * (sin(theta / 2._real64) / theta)**2
        else
            a = 1._real64
            b = 0.5_real64
        endif
        e = a * k + b * matmul(k, k)
        do i = 1, 3
            e(i, i) = e(i, i) + 1._real64
        end do
        rnew = matmul(r, e)
    end function oracle_pose_rotate

    ! the prepared reference of a real cube: embedded at the centre of twice its side with the origin at index
    ! n/2 + 1, multiplied by the Kaiser-Bessel envelope over the B-spline's along each axis, and transformed
    ! with a negative exponent and 1 / box**3; frequency q of an axis is stored at 1 + modulo(q, n)
    function oracle_pose_reference( vol ) result(f)
        real(real64), intent(in) :: vol(:,:,:)
        complex(real64) :: f(PADFAC*size(vol, 1), PADFAC*size(vol, 1), PADFAC*size(vol, 1))
        real(real64)    :: rho(PADFAC*size(vol, 1))
        integer         :: box, n, c, off, i1, i2, i3, j(3), x
        box = size(vol, 1)
        n   = PADFAC * box
        c   = n / 2 + 1
        off = (n - box) / 2
        do x = 1, n
            rho(x) = kb_env(x, n) / bspline_env(x, n)
        end do
        f = CZERO
        do i3 = 1, box
            do i2 = 1, box
                do i1 = 1, box
                    j = 1 + modulo([i1, i2, i3] + off - c, n)
                    f(j(1), j(2), j(3)) = cmplx(vol(i1, i2, i3) * rho(i1 + off) * rho(i2 + off) * rho(i3 + off), &
                                                0._real64, real64)
                end do
            end do
        end do
        f = oracle_dft_3d(f) / real(box, real64)**3
    end function oracle_pose_reference

    ! the gather at loc (units of the padded lattice): per axis the nearest point m and its two neighbours,
    ! wrapped, with weights (t - 1/2)**2 / 2, 3/4 - t**2, (t + 1/2)**2 / 2 at t = loc - m; v is the sum over the
    ! 27 voxels, dv(a) the same with axis a's weights replaced by their slopes t - 1/2, -2 t, t + 1/2
    pure subroutine oracle_pose_gather( f, loc, v, dv )
        complex(real64), intent(in)  :: f(:,:,:)
        real(real64),    intent(in)  :: loc(3)
        complex(real64), intent(out) :: v, dv(3)
        complex(real64) :: fv
        real(real64)    :: w(3, 3), s(3, 3), t
        integer         :: tap(3, 3), a, m, j1, j2, j3
        do a = 1, 3
            m         = nint(loc(a))
            t         = loc(a) - real(m, real64)
            tap(:, a) = 1 + modulo(m + [-1, 0, 1], size(f, a))
            w(:, a)   = [(t - 0.5_real64)**2 / 2._real64, 0.75_real64 - t**2, (t + 0.5_real64)**2 / 2._real64]
            s(:, a)   = [t - 0.5_real64, -2._real64 * t, t + 0.5_real64]
        end do
        v  = CZERO
        dv = CZERO
        do j3 = 1, 3
            do j2 = 1, 3
                do j1 = 1, 3
                    fv    = f(tap(j1, 1), tap(j2, 2), tap(j3, 3))
                    v     = v + w(j1, 1) * w(j2, 2) * w(j3, 3) * fv
                    dv(1) = dv(1) + s(j1, 1) * w(j2, 2) * w(j3, 3) * fv
                    dv(2) = dv(2) + w(j1, 1) * s(j2, 2) * w(j3, 3) * fv
                    dv(3) = dv(3) + w(j1, 1) * w(j2, 2) * s(j3, 3) * fv
                end do
            end do
        end do
    end subroutine oracle_pose_gather

    ! the fixture's problem for objective 'euclid' (shells 1 to 7) or 'cc' (shells 0 to 7): the three-blob
    ! volume, and a particle that is the model at the planted pose, times 2.5 for the correlation
    subroutine oracle_pose_fixture( objective, prob )
        character(len=*),          intent(in)    :: objective
        type(oracle_pose_problem), intent(inout) :: prob
        complex(real64) :: observed(FIX_BOX+1, FIX_BOX+1)
        real(real64)    :: r(3, 3), shift(2)
        call prob%new(fixture_volume(), merge(0, 1, objective == 'cc'), FIX_KTO, objective)
        call oracle_pose_fixture_pose(.false., r, shift)
        observed = prob%model(fixture_ctf(), r, shift)
        if( objective == 'cc' ) observed = MULTIPLE * observed
        call prob%set_particle(observed, fixture_ctf(), fixture_sigma2())
    end subroutine oracle_pose_fixture

    ! the fixture's planted pose, or the start displaced from it by 0.05 rad and 0.5 pixel
    subroutine oracle_pose_fixture_pose( displaced, r, shift )
        logical,      intent(in)  :: displaced
        real(real64), intent(out) :: r(3, 3), shift(2)
        r     = oracle_pose_euler(PLANT_EULER(1), PLANT_EULER(2), PLANT_EULER(3))
        shift = PLANT_SHIFT
        if( displaced )then
            r     = oracle_pose_rotate(r, DISPLACE_OMEGA)
            shift = shift + DISPLACE_SHIFT
        endif
    end subroutine oracle_pose_fixture_pose

    ! the checks against hand values, closed forms, second routes and central differences, as named largest
    ! errors and their limits; a limit is not applied here
    subroutine oracle_pose_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        limits = CHECK_LIMITS
        errors = 0._real64
        call check_counts(errors(1), errors(11))
        call check_window(errors(2:4))
        call check_rotations(errors(5))
        call check_reference(errors(6:7))
        call check_gather(errors(8:10))
        call check_model(errors(12))
        call check_powers(errors(13))
        call check_plane(errors(14))
        call check_euclid(errors(15:18))
        call check_cc(errors(19:22))
        call check_shift_terms('euclid', errors(23))
        call check_shift_terms('cc', errors(24))
        call check_floor(errors(25))
        call check_solve('euclid', errors(26:27), errors(30))
        call check_solve('cc', errors(28:29), errors(30))
        call check_solved(errors(31))
        call check_solve_rules(errors(32))
    end subroutine oracle_pose_selfcheck

    ! the shell of pixel (h, k): nint of its radius where h**2 + k**2 <= (box/2)**2, -1 outside
    pure function shell_of( h, k, box ) result(sh)
        integer, intent(in) :: h, k, box
        integer :: sh
        if( h * h + k * k <= (box / 2)**2 )then
            sh = nint(sqrt(real(h * h + k * k, real64)))
        else
            sh = -1
        endif
    end function shell_of

    ! whether pixel (h, k) lies on a shell of the problem's band
    pure function in_band( self, h, k ) result(yes)
        class(oracle_pose_problem), intent(in) :: self
        integer,                    intent(in) :: h, k
        logical :: yes
        integer :: sh
        sh  = shell_of(h, k, self%box)
        yes = sh >= self%kfrom .and. sh <= self%kto
    end function in_band

    ! where pixel (h, k) reads the padded reference under rotation r: 2 r^T (h, k, 0)
    pure function pixel_loc( h, k, r ) result(loc)
        integer,      intent(in) :: h, k
        real(real64), intent(in) :: r(3, 3)
        real(real64) :: loc(3)
        loc = real(PADFAC, real64) * (real(h, real64) * r(1, :) + real(k, real64) * r(2, :))
    end function pixel_loc

    ! the shift's phase at pixel (h, k): exp(+2 pi i (h s1 + k s2) / box)
    pure function pixel_phase( h, k, shift, box ) result(p)
        integer,      intent(in) :: h, k, box
        real(real64), intent(in) :: shift(2)
        complex(real64) :: p
        real(real64)    :: arg
        arg = TWOPI * (real(h, real64) * shift(1) + real(k, real64) * shift(2)) / real(box, real64)
        p   = cmplx(cos(arg), sin(arg), real64)
    end function pixel_phase

    ! every sum of an evaluation at a pose, from the model M = phase T V and its five derivatives: three by the
    ! gather's gradient crossed with loc, two by i times the pixel's frequency times M. The central pixel has no
    ! phase and no derivative and enters once, when the band starts at shell 0
    subroutine full_sums( self, r, shift, s )
        class(oracle_pose_problem), intent(in)  :: self
        real(real64),               intent(in)  :: r(3, 3), shift(2)
        type(pose_sums),            intent(out) :: s
        complex(real64) :: v, dv(3), wp, m, jac(5), res, x
        real(real64)    :: loc(3), fh, fk
        integer         :: h, k, a, b
        do k = -self%kto, self%kto
            do h = merge(0, 1, k > 0), self%kto
                if( .not. in_band(self, h, k) ) cycle
                x   = self%x(h, k)
                loc = pixel_loc(h, k, r)
                call oracle_pose_gather(self%f, loc, v, dv)
                fh     = TWOPI * real(h, real64) / real(self%box, real64)
                fk     = TWOPI * real(k, real64) / real(self%box, real64)
                wp     = pixel_phase(h, k, shift, self%box) * self%t(h, k)
                m      = wp * v
                jac(1) = wp * (dv(2) * loc(3) - dv(3) * loc(2))
                jac(2) = wp * (dv(3) * loc(1) - dv(1) * loc(3))
                jac(3) = wp * (dv(1) * loc(2) - dv(2) * loc(1))
                jac(4) = cmplx(0._real64, fh, real64) * m
                jac(5) = cmplx(0._real64, fk, real64) * m
                res    = m - x
                s%ppow  = s%ppow + 2._real64 * abs(x)**2
                s%res   = s%res + 2._real64 * abs(res)**2
                s%cross = s%cross + 2._real64 * real(conjg(x) * m)
                s%mm    = s%mm + 2._real64 * abs(m)**2
                s%wc    = s%wc + 2._real64 * (fh**2 + fk**2) * real(conjg(x) * m)
                s%wpow  = s%wpow + 2._real64 * (fh**2 + fk**2) * abs(m)**2
                do a = 1, 5
                    s%g(a)  = s%g(a) + 2._real64 * real(conjg(jac(a)) * res)
                    s%gx(a) = s%gx(a) + 2._real64 * real(conjg(x) * jac(a))
                    s%mg(a) = s%mg(a) + 2._real64 * real(conjg(m) * jac(a))
                    do b = a, 5
                        s%h(a, b) = s%h(a, b) + 2._real64 * real(conjg(jac(a)) * jac(b))
                    end do
                end do
            end do
        end do
        ! the matrix is symmetric, and a shift does not change the model's power
        do a = 1, 5
            do b = a + 1, 5
                s%h(b, a) = s%h(a, b)
            end do
        end do
        s%mg(4:5) = 0._real64
        if( self%kfrom == 0 )then
            x = self%x(0, 0)
            call oracle_pose_gather(self%f, [0._real64, 0._real64, 0._real64], v, dv)
            m       = self%t(0, 0) * v
            s%ppow  = s%ppow + abs(x)**2
            s%res   = s%res + abs(m - x)**2
            s%cross = s%cross + real(conjg(x) * m)
            s%mm    = s%mm + abs(m)**2
        endif
    end subroutine full_sums

    ! the sums of the shift-only terms, without the gather's gradient: with q = Im(conj(X) M) and m2 = |M|**2,
    ! the gradient sums of the frequencies times q and the matrix sums of their products times m2
    subroutine shift_sums( self, r, shift, s )
        class(oracle_pose_problem), intent(in)  :: self
        real(real64),               intent(in)  :: r(3, 3), shift(2)
        type(pose_sums),            intent(out) :: s
        complex(real64) :: v, dv(3), m, x
        real(real64)    :: f(2), q, m2
        integer         :: h, k
        do k = -self%kto, self%kto
            do h = merge(0, 1, k > 0), self%kto
                if( .not. in_band(self, h, k) ) cycle
                x = self%x(h, k)
                call oracle_pose_gather(self%f, pixel_loc(h, k, r), v, dv)
                m  = pixel_phase(h, k, shift, self%box) * self%t(h, k) * v
                f  = TWOPI * real([h, k], real64) / real(self%box, real64)
                q  = aimag(conjg(x) * m)
                m2 = abs(m)**2
                s%ppow      = s%ppow + 2._real64 * abs(x)**2
                s%cross     = s%cross + 2._real64 * real(conjg(x) * m)
                s%mm        = s%mm + 2._real64 * m2
                s%wc        = s%wc + 2._real64 * sum(f**2) * real(conjg(x) * m)
                s%wpow      = s%wpow + 2._real64 * sum(f**2) * m2
                s%g(4:5)    = s%g(4:5) + 2._real64 * f * q
                s%h(4, 4)   = s%h(4, 4) + 2._real64 * f(1)**2 * m2
                s%h(4, 5)   = s%h(4, 5) + 2._real64 * f(1) * f(2) * m2
                s%h(5, 5)   = s%h(5, 5) + 2._real64 * f(2)**2 * m2
            end do
        end do
        s%h(5, 4) = s%h(4, 5)
        if( self%kfrom == 0 )then
            x = self%x(0, 0)
            call oracle_pose_gather(self%f, [0._real64, 0._real64, 0._real64], v, dv)
            m       = self%t(0, 0) * v
            s%ppow  = s%ppow + abs(x)**2
            s%cross = s%cross + real(conjg(x) * m)
            s%mm    = s%mm + abs(m)**2
        endif
    end subroutine shift_sums

    ! whether the sums give no objective: the particle's power, or for the correlation the model's, not above
    ! the floor
    pure function no_objective( self, s ) result(none)
        class(oracle_pose_problem), intent(in) :: self
        type(pose_sums),            intent(in) :: s
        logical :: none
        none = .not. (s%ppow > POW_FLOOR)
        if( .not. self%euclid )then
            if( .not. (s%mm > POW_FLOOR) ) none = .true.
        endif
    end function no_objective

    ! the curvature scale: the frequency-weighted cross term over the model's frequency-weighted power, for
    ! the correlation times the root of the model's power over the particle's, clamped; one when the weighted
    ! power is not above the floor
    pure function scale_of( self, s ) result(sc)
        class(oracle_pose_problem), intent(in) :: self
        type(pose_sums),            intent(in) :: s
        real(real64) :: sc
        sc = 1._real64
        if( s%wpow > POW_FLOOR )then
            sc = s%wc / s%wpow
            if( .not. self%euclid ) sc = sc * sqrt(s%mm / s%ppow)
            sc = min(SCALE_MAX, max(SCALE_MIN, sc))
        endif
    end function scale_of

    ! the lower Cholesky factor of a symmetric matrix; ok is false, and the factor unfinished, at the first
    ! pivot that is not above the floor
    pure subroutine cholesky_factor( a, floor_pivot, l, ok )
        real(real64), intent(in)  :: a(:,:), floor_pivot
        real(real64), intent(out) :: l(size(a, 1), size(a, 1))
        logical,      intent(out) :: ok
        real(real64) :: d
        integer      :: i, j
        l  = 0._real64
        ok = .false.
        do j = 1, size(a, 1)
            d = a(j, j) - sum(l(j, 1:j-1)**2)
            if( .not. (d > floor_pivot) ) return
            l(j, j) = sqrt(d)
            do i = j + 1, size(a, 1)
                l(i, j) = (a(i, j) - sum(l(i, 1:j-1) * l(j, 1:j-1))) / l(j, j)
            end do
        end do
        ok = .true.
    end subroutine cholesky_factor

    ! the solution of l l^T x = b by a forward and a back substitution
    pure function cholesky_solve( l, b ) result(x)
        real(real64), intent(in) :: l(:,:), b(:)
        real(real64) :: x(size(b)), y(size(b))
        integer      :: i, n
        n = size(b)
        do i = 1, n
            y(i) = (b(i) - sum(l(i, 1:i-1) * y(1:i-1))) / l(i, i)
        end do
        do i = n, 1, -1
            x(i) = (y(i) - sum(l(i+1:n, i) * x(i+1:n))) / l(i, i)
        end do
    end function cholesky_solve

    ! the rotation about z by a, rows [c, s, 0], [-s, c, 0], [0, 0, 1]
    pure function rot_z( a ) result(r)
        real(real64), intent(in) :: a
        real(real64) :: r(3, 3)
        r = reshape([cos(a), sin(a), 0._real64, -sin(a), cos(a), 0._real64, 0._real64, 0._real64, 1._real64], [3, 3], &
                    order=[2, 1])
    end function rot_z

    ! the rotation about y by a, rows [c, 0, -s], [0, 1, 0], [s, 0, c]
    pure function rot_y( a ) result(r)
        real(real64), intent(in) :: a
        real(real64) :: r(3, 3)
        r = reshape([cos(a), 0._real64, -sin(a), 0._real64, 1._real64, 0._real64, sin(a), 0._real64, cos(a)], [3, 3], &
                    order=[2, 1])
    end function rot_y

    ! the matrix [omega]x of the cross product, rows [0, -o3, o2], [o3, 0, -o1], [-o2, o1, 0]
    pure function cross_matrix( omega ) result(k)
        real(real64), intent(in) :: omega(3)
        real(real64) :: k(3, 3)
        k = reshape([0._real64, -omega(3), omega(2), omega(3), 0._real64, -omega(1), -omega(2), omega(1), 0._real64], &
                    [3, 3], order=[2, 1])
    end function cross_matrix

    ! the B-spline's envelope at index x of n: 3/4 + cos(2 pi (x - c) / n) / 4, c = n/2 + 1
    pure function bspline_env( x, n ) result(e)
        integer, intent(in) :: x, n
        real(real64) :: e
        e = 0.75_real64 + 0.25_real64 * cos(TWOPI * real(x - n / 2 - 1, real64) / real(n, real64))
    end function bspline_env

    ! the Kaiser-Bessel envelope at index x of n: the sum over q = -1, 0, 1 of w_q cos(2 pi q (x - c) / n), over
    ! its value at c
    pure function kb_env( x, n ) result(e)
        integer, intent(in) :: x, n
        real(real64) :: e, w(-1:1)
        integer      :: q
        w = kb_weights()
        e = 0._real64
        do q = -1, 1
            e = e + w(q) * cos(TWOPI * real(q * (x - n / 2 - 1), real64) / real(n, real64))
        end do
        e = e / sum(w)
    end function kb_env

    ! the window's values at -1, 0, 1 over their sum: I0(beta sqrt(1 - (2 q / 3)**2)) / 3
    pure function kb_weights() result(w)
        real(real64) :: w(-1:1)
        integer      :: q
        do q = -1, 1
            w(q) = i0_series(KB_BETA * sqrt(1._real64 - (2._real64 * real(q, real64) / 3._real64)**2)) / 3._real64
        end do
        w = w / sum(w)
    end function kb_weights

    ! I0 by its power series, summed until a term no longer changes the sum
    pure function i0_series( x ) result(s)
        real(real64), intent(in) :: x
        real(real64) :: s, term
        integer      :: k
        s    = 1._real64
        term = 1._real64
        do k = 1, MAXTERM
            term = term * (x / 2._real64)**2 / real(k, real64)**2
            s    = s + term
            if( term < epsilon(s) * s ) exit
        end do
    end function i0_series

    ! I0 by the trapezoid rule on one turn of exp(x cos u), which converges spectrally: an independent evaluation
    pure function i0_trapezoid( x ) result(s)
        real(real64), intent(in) :: x
        real(real64) :: s
        integer      :: j
        s = 0._real64
        do j = 0, NTRAP - 1
            s = s + exp(x * cos(TWOPI * real(j, real64) / real(NTRAP, real64)))
        end do
        s = s / real(NTRAP, real64)
    end function i0_trapezoid

    ! the fixture's volume: three Gaussian blobs at centred coordinates x = i - 1 - box/2
    pure function fixture_volume() result(v)
        real(real64) :: v(FIX_BOX, FIX_BOX, FIX_BOX), x(3)
        integer      :: i1, i2, i3, b
        do i3 = 1, FIX_BOX
            do i2 = 1, FIX_BOX
                do i1 = 1, FIX_BOX
                    x             = real([i1, i2, i3] - 1 - FIX_BOX / 2, real64)
                    v(i1, i2, i3) = 0._real64
                    do b = 1, size(BLOBS, 2)
                        v(i1, i2, i3) = v(i1, i2, i3) + BLOBS(1, b) * exp(-sum((x - BLOBS(2:4, b))**2) / &
                                                                           (2._real64 * BLOBS(5, b)**2))
                    end do
                end do
            end do
        end do
    end function fixture_volume

    ! a broadband volume from integers, for the checks that must see every frequency of the reference
    pure function fixture_spikes() result(v)
        real(real64) :: v(FIX_BOX, FIX_BOX, FIX_BOX)
        integer      :: i1, i2, i3
        do i3 = 1, FIX_BOX
            do i2 = 1, FIX_BOX
                do i1 = 1, FIX_BOX
                    v(i1, i2, i3) = real(modulo(7 * i1 + 3 * i2 + 5 * i3 + i1 * i2 * i3, 11) - 5, real64) / 4._real64
                end do
            end do
        end do
    end function fixture_spikes

    ! the fixture's CTF, signed, the same at a pixel and at its Friedel mate
    pure function fixture_ctf() result(c)
        real(real64) :: c(FIX_BOX+1, FIX_BOX+1)
        integer      :: h, k, b2
        b2 = FIX_BOX / 2
        do k = -b2, b2
            do h = -b2, b2
                c(h + b2 + 1, k + b2 + 1) = -sin(0.3_real64 + 0.09_real64 * real(h * h, real64) + &
                                                 0.07_real64 * real(k * k, real64) + 0.02_real64 * real(h * k, real64))
            end do
        end do
    end function fixture_ctf

    ! the fixture's noise variances per shell, 1 + shell / 4
    pure function fixture_sigma2() result(s)
        real(real64) :: s(FIX_BOX/2+1)
        integer      :: sh
        do sh = 0, FIX_BOX / 2
            s(1 + sh) = 1._real64 + 0.25_real64 * real(sh, real64)
        end do
    end function fixture_sigma2

    ! the full plane's pixels per shell against hand counts, the pixels each objective sums, and the reference's
    ! shape; then, apart, the coordinates of the two fixture poses that lie within the margin of a half-integer
    subroutine check_counts( err, err_margin )
        real(real64), intent(inout) :: err, err_margin
        type(oracle_pose_problem) :: prob
        real(real64)              :: r(3, 3), shift(2), loc(3)
        integer                   :: counts(0:FIX_KTO), h, k, sh, nbad, ipose, b2
        integer, parameter        :: HAND(0:FIX_KTO) = [1, 8, 12, 16, 32, 28, 40, 40]
        b2     = FIX_BOX / 2
        counts = 0
        do k = -b2, b2
            do h = -b2, b2
                sh = shell_of(h, k, FIX_BOX)
                if( sh >= 0 .and. sh <= FIX_KTO ) counts(sh) = counts(sh) + 1
            end do
        end do
        nbad = count(counts /= HAND)
        if( shell_of(b2, 1, FIX_BOX) /= -1 .or. shell_of(0, b2, FIX_BOX) /= b2 ) nbad = nbad + 1
        call oracle_pose_fixture('euclid', prob)
        if( prob%npixels() /= 88 ) nbad = nbad + 1
        if( any(shape(prob%f) /= 2 * FIX_BOX) ) nbad = nbad + 1
        call oracle_pose_fixture('cc', prob)
        if( prob%npixels() /= 89 ) nbad = nbad + 1
        err  = max(err, real(nbad, real64))
        nbad = 0
        do ipose = 1, 2
            call oracle_pose_fixture_pose(ipose == 2, r, shift)
            do k = -FIX_KTO, FIX_KTO
                do h = merge(0, 1, k > 0), FIX_KTO
                    sh = shell_of(h, k, FIX_BOX)
                    if( sh < 0 .or. sh > FIX_KTO ) cycle
                    loc  = pixel_loc(h, k, r)
                    nbad = nbad + count(abs(modulo(loc, 1._real64) - 0.5_real64) < MIN_MARGIN)
                end do
            end do
        end do
        err_margin = max(err_margin, real(nbad, real64))
        call prob%kill()
    end subroutine check_counts

    ! I0 by its series against the trapezoid rule; the window's weights against the printed ones; and the two
    ! envelopes at the origin, a quarter and a half of the padded side on, where their cosines are 1, 0 and -1
    subroutine check_window( err )
        real(real64), intent(inout) :: err(3)
        real(real64) :: w(-1:1), wt(-1:1), x
        integer      :: q, n, c
        do q = -1, 1
            x      = KB_BETA * sqrt(1._real64 - (2._real64 * real(q, real64) / 3._real64)**2)
            wt(q)  = i0_trapezoid(x)
            err(1) = max(err(1), oracle_finite_or_inf(abs(i0_series(x) - wt(q)) / wt(q)))
        end do
        wt     = wt / sum(wt)
        w      = kb_weights()
        err(2) = max(err(2), oracle_finite_or_inf(abs(w(0) - W0_PRINTED)), oracle_finite_or_inf(abs(w(1) - W1_PRINTED)), &
                     oracle_finite_or_inf(abs(w(-1) - W1_PRINTED)))
        n      = PADFAC * FIX_BOX
        c      = n / 2 + 1
        err(3) = max(err(3), oracle_finite_or_inf(abs(bspline_env(c, n) - 1._real64)), &
                     oracle_finite_or_inf(abs(bspline_env(c + n / 4, n) - 0.75_real64)), &
                     oracle_finite_or_inf(abs(bspline_env(c - n / 2, n) - 0.5_real64)), &
                     oracle_finite_or_inf(abs(kb_env(c, n) - 1._real64)), &
                     oracle_finite_or_inf(abs(kb_env(c + n / 4, n) - wt(0))), &
                     oracle_finite_or_inf(abs(kb_env(c - n / 2, n) - (wt(0) - 2._real64 * wt(1)))))
    end subroutine check_window

    ! the Euler matrix against its product written out and against two quarter-turn cases by hand; its
    ! orthonormality; the increment against the exponential's power series, and a zero increment
    subroutine check_rotations( err )
        real(real64), intent(inout) :: err
        real(real64) :: r(3, 3), ref(3, 3), k(3, 3), term(3, 3), e(3), c(3), s(3), omega(3)
        integer      :: i, j
        e   = PLANT_EULER
        c   = cos(e)
        s   = sin(e)
        r   = oracle_pose_euler(e(1), e(2), e(3))
        ref = reshape([c(3) * c(2) * c(1) - s(3) * s(1), c(3) * c(2) * s(1) + s(3) * c(1), -c(3) * s(2), &
                       -s(3) * c(2) * c(1) - c(3) * s(1), -s(3) * c(2) * s(1) + c(3) * c(1), s(3) * s(2), &
                       s(2) * c(1), s(2) * s(1), c(2)], [3, 3], order=[2, 1])
        err = max(err, matrix_error(r, ref), matrix_error(matmul(r, transpose(r)), identity3()))
        ! a quarter turn about z has rows [0, 1, 0], [-1, 0, 0], [0, 0, 1]; followed by a quarter turn about y,
        ! rows [0, 0, -1], [-1, 0, 0], [0, 1, 0]
        ref = reshape([0._real64, 1._real64, 0._real64, -1._real64, 0._real64, 0._real64, 0._real64, 0._real64, &
                       1._real64], [3, 3], order=[2, 1])
        err = max(err, matrix_error(oracle_pose_euler(PI / 2._real64, 0._real64, 0._real64), ref))
        ref = reshape([0._real64, 0._real64, -1._real64, -1._real64, 0._real64, 0._real64, 0._real64, 1._real64, &
                       0._real64], [3, 3], order=[2, 1])
        err = max(err, matrix_error(oracle_pose_euler(PI / 2._real64, PI / 2._real64, 0._real64), ref))
        ! r exp([omega]x) with the exponential by its power series, for a large and a small rotation vector
        do j = 1, 2
            omega = [0.7_real64, -1.1_real64, 0.4_real64]
            if( j == 2 ) omega = DISPLACE_OMEGA * 1.e-3_real64
            k    = reshape([0._real64, -omega(3), omega(2), omega(3), 0._real64, -omega(1), -omega(2), omega(1), &
                            0._real64], [3, 3], order=[2, 1])
            ref  = identity3()
            term = identity3()
            do i = 1, 40
                term = matmul(term, k) / real(i, real64)
                ref  = ref + term
            end do
            err = max(err, matrix_error(oracle_pose_rotate(r, omega), matmul(r, ref)))
        end do
        err = max(err, matrix_error(oracle_pose_rotate(r, [0._real64, 0._real64, 0._real64]), r))
    end subroutine check_rotations

    ! the prepared reference of the fixture's volume and of a broadband one: against the defining triple sum at
    ! a few frequencies, the largest difference over the largest value; and its Hermitian symmetry
    subroutine check_reference( err )
        real(real64), intent(inout) :: err(2)
        complex(real64), allocatable :: f(:,:,:)
        complex(real64)              :: ref
        real(real64)                 :: vol(FIX_BOX, FIX_BOX, FIX_BOX), rho(PADFAC*FIX_BOX), scale, worst
        integer                      :: n, c, off, i1, i2, i3, iq, ivol, q(3), j(3)
        integer, parameter           :: FREQS(3, 5) = reshape([0, 0, 0, 1, 2, 3, -3, 5, -7, 15, -16, 4, 31, 0, 33], [3, 5])
        n   = PADFAC * FIX_BOX
        c   = n / 2 + 1
        off = (n - FIX_BOX) / 2
        allocate(f(n, n, n))
        do i1 = 1, n
            rho(i1) = kb_env(i1, n) / bspline_env(i1, n)
        end do
        do ivol = 1, 2
            if( ivol == 1 )then
                vol = fixture_volume()
            else
                vol = fixture_spikes()
            endif
            f = oracle_pose_reference(vol)
            ! the defining sum at frequency q, read where q is stored; the last frequency is beyond one period
            scale = 0._real64
            worst = 0._real64
            do iq = 1, size(FREQS, 2)
                q   = FREQS(:, iq)
                ref = CZERO
                do i3 = 1, FIX_BOX
                    do i2 = 1, FIX_BOX
                        do i1 = 1, FIX_BOX
                            j   = [i1, i2, i3] + off
                            ref = ref + vol(i1, i2, i3) * rho(j(1)) * rho(j(2)) * rho(j(3)) * &
                                  exp(cmplx(0._real64, -TWOPI * real(dot_product(q, j - c), real64) / real(n, real64), real64))
                        end do
                    end do
                end do
                ref   = ref / real(FIX_BOX, real64)**3
                j     = 1 + modulo(q, n)
                worst = max(worst, oracle_finite_or_inf(abs(f(j(1), j(2), j(3)) - ref)))
                scale = max(scale, abs(ref))
            end do
            err(1) = max(err(1), oracle_finite_or_inf(worst / scale))
            ! F(-q) is the conjugate of F(q)
            scale = maxval(abs(f))
            worst = 0._real64
            do i3 = 1, n
                do i2 = 1, n
                    do i1 = 1, n
                        j     = 1 + modulo(1 - [i1, i2, i3], n)
                        worst = max(worst, oracle_finite_or_inf(abs(f(i1, i2, i3) - conjg(f(j(1), j(2), j(3))))))
                    end do
                end do
            end do
            err(2) = max(err(2), oracle_finite_or_inf(worst / scale))
        end do
    end subroutine check_reference

    ! the gather on the reference of a broadband volume, which is of one size at every frequency: against a sum
    ! over the B-spline kernel; at lattice points against the transform of the volume times the Kaiser-Bessel
    ! envelope; its slopes against differences inside a cell. Each as the largest difference over the largest value
    subroutine check_gather( err )
        real(real64), intent(inout) :: err(3)
        complex(real64), allocatable :: f(:,:,:)
        complex(real64)              :: v, dv(3), vk, dvk(3), vp, vm, ref
        real(real64)                 :: vol(FIX_BOX, FIX_BOX, FIX_BOX), loc(3), e(3), scale(2), worst(2)
        integer                      :: n, iq, a
        integer, parameter           :: NODES(3, 6) = reshape([0, 0, 0, 2, -4, 6, -14, 0, 10, 16, -16, 16, -16, 0, 15, &
                                                               3, 16, -1], [3, 6])
        real(real64), parameter      :: LOCS(3, 5) = reshape([0.3_real64, -0.2_real64, 0.1_real64, 5.375_real64, &
            -7.25_real64, 2.125_real64, -12.625_real64, 3.3_real64, 15.75_real64, 0.5_real64, -0.5_real64, &
            1.5_real64, -15.9_real64, 15.6_real64, -8.45_real64], [3, 5])
        real(real64), parameter      :: INSIDE(3, 3) = reshape([0.25_real64, -0.375_real64, 0.125_real64, 7.375_real64, &
            -3.25_real64, 11._real64, -15.625_real64, 14.3_real64, -0.3_real64], [3, 3])
        vol = fixture_spikes()
        n   = PADFAC * FIX_BOX
        allocate(f(n, n, n))
        f = oracle_pose_reference(vol)
        ! the value and the gradient against the kernel sum, half-integers and the wrap included
        scale = 0._real64
        worst = 0._real64
        do iq = 1, size(LOCS, 2)
            call oracle_pose_gather(f, LOCS(:, iq), v, dv)
            call kernel_gather(f, LOCS(:, iq), vk, dvk)
            worst = max(worst, [oracle_finite_or_inf(abs(v - vk)), oracle_finite_or_inf(sum(abs(dv - dvk)))])
            scale = max(scale, [abs(vk), maxval(abs(dvk))])
        end do
        err(1) = max(err(1), oracle_finite_or_inf(maxval(worst / scale)))
        ! at a lattice point the three taps weigh 1/8, 3/4, 1/8, whose transform is the B-spline's envelope: the
        ! gather is the transform of the volume times the Kaiser-Bessel envelope alone; three points wrap
        scale = 0._real64
        worst = 0._real64
        do iq = 1, size(NODES, 2)
            call oracle_pose_gather(f, real(NODES(:, iq), real64), v, dv)
            ref      = lattice_value(vol, NODES(:, iq))
            worst(1) = max(worst(1), oracle_finite_or_inf(abs(v - ref)))
            scale(1) = max(scale(1), abs(ref))
        end do
        err(2) = max(err(2), oracle_finite_or_inf(worst(1) / scale(1)))
        ! inside a cell the value is a quadratic along an axis, so a central difference of any step is its slope
        scale = 0._real64
        worst = 0._real64
        do iq = 1, size(INSIDE, 2)
            loc = INSIDE(:, iq)
            call oracle_pose_gather(f, loc, v, dv)
            do a = 1, 3
                e    = 0._real64
                e(a) = 0.0625_real64
                call oracle_pose_gather(f, loc + e, vp, dvk)
                call oracle_pose_gather(f, loc - e, vm, dvk)
                worst(1) = max(worst(1), oracle_finite_or_inf(abs((vp - vm) / 0.125_real64 - dv(a))))
                scale(1) = max(scale(1), abs(dv(a)))
            end do
        end do
        err(3) = max(err(3), oracle_finite_or_inf(worst(1) / scale(1)))
    end subroutine check_gather

    ! the model at two rotations that put every pixel on a lattice point, against a sum written from the volume
    ! with the coordinates stated by hand: Euler (pi/2, 0, 0) reads 2 (-k, h, 0), (pi/2, pi/2, 0) reads 2 (-k, 0, -h)
    subroutine check_model( err )
        real(real64), intent(inout) :: err
        type(oracle_pose_problem) :: prob
        complex(real64)           :: m(FIX_BOX+1, FIX_BOX+1), ref
        real(real64)              :: vol(FIX_BOX, FIX_BOX, FIX_BOX), ctf(FIX_BOX+1, FIX_BOX+1), r(3, 3), arg, worst, scale
        integer                   :: icase, h, k, b2, loc(3)
        b2  = FIX_BOX / 2
        vol = fixture_volume()
        ctf = fixture_ctf()
        call prob%new(vol, 0, FIX_KTO, 'cc')
        do icase = 1, 2
            if( icase == 1 )then
                r = oracle_pose_euler(PI / 2._real64, 0._real64, 0._real64)
            else
                r = oracle_pose_euler(PI / 2._real64, PI / 2._real64, 0._real64)
            endif
            m     = prob%model(ctf, r, PLANT_SHIFT)
            worst = 0._real64
            scale = 0._real64
            do k = -b2, b2
                do h = -b2, b2
                    if( h * h + k * k > b2 * b2 )then
                        ref = CZERO
                    else
                        loc = merge([-2 * k, 2 * h, 0], [-2 * k, 0, -2 * h], icase == 1)
                        arg = TWOPI * (real(h, real64) * PLANT_SHIFT(1) + real(k, real64) * PLANT_SHIFT(2)) / &
                              real(FIX_BOX, real64)
                        ref = exp(cmplx(0._real64, arg, real64)) * abs(ctf(h + b2 + 1, k + b2 + 1)) * lattice_value(vol, loc)
                    endif
                    worst = max(worst, oracle_finite_or_inf(abs(m(h + b2 + 1, k + b2 + 1) - ref)))
                    scale = max(scale, abs(ref))
                end do
            end do
            err = max(err, oracle_finite_or_inf(worst / scale))
        end do
        call prob%kill()
    end subroutine check_model

    ! the power of a particle that is one on every pixel: the pixel count of the band for the correlation, and
    ! the counts over the variances 2**shell for the Euclidean objective, without and with the central pixel
    subroutine check_powers( err )
        real(real64), intent(inout) :: err
        type(oracle_pose_problem) :: prob
        complex(real64)           :: ones(FIX_BOX+1, FIX_BOX+1)
        real(real64)              :: ctf(FIX_BOX+1, FIX_BOX+1), sigma2(FIX_BOX/2+1)
        integer                   :: sh
        ones = (1._real64, 0._real64)
        ctf  = 1._real64
        do sh = 0, FIX_BOX / 2
            sigma2(1 + sh) = 2._real64**sh
        end do
        call prob%new(fixture_volume(), 0, FIX_KTO, 'cc')
        call prob%set_particle(ones, ctf, sigma2)
        err = max(err, oracle_finite_or_inf(abs(prob%power() - 177._real64) / 177._real64))
        call prob%new(fixture_volume(), 1, FIX_KTO, 'euclid')
        call prob%set_particle(ones, ctf, sigma2)
        err = max(err, oracle_finite_or_inf(abs(prob%power() - 12.8125_real64) / 12.8125_real64))
        call prob%new(fixture_volume(), 0, FIX_KTO, 'euclid')
        call prob%set_particle(ones, ctf, sigma2)
        err = max(err, oracle_finite_or_inf(abs(prob%power() - 13.8125_real64) / 13.8125_real64))
        call prob%kill()
    end subroutine check_powers

    ! both objectives at the displaced pose, for the particle planted at the other, against plain sums over the
    ! full plane, every pixel of the band once: the Euclidean one with and without the central pixel
    subroutine check_plane( err )
        real(real64), intent(inout) :: err
        type(oracle_pose_problem) :: prob
        complex(real64)           :: obs(FIX_BOX+1, FIX_BOX+1), m(FIX_BOX+1, FIX_BOX+1)
        real(real64)              :: ctf(FIX_BOX+1, FIX_BOX+1), sigma2(FIX_BOX/2+1), r0(3, 3), s0(2), r1(3, 3), s1(2)
        real(real64)              :: w2, num, den, cross, mm, ref
        integer                   :: icase, kfrom, h, k, b2, sh
        b2     = FIX_BOX / 2
        ctf    = fixture_ctf()
        sigma2 = fixture_sigma2()
        call oracle_pose_fixture_pose(.false., r0, s0)
        call oracle_pose_fixture_pose(.true., r1, s1)
        do icase = 1, 3
            kfrom = merge(1, 0, icase == 1)
            call prob%new(fixture_volume(), kfrom, FIX_KTO, merge('cc    ', 'euclid', icase == 3))
            obs = prob%model(ctf, r0, s0)
            m   = prob%model(ctf, r1, s1)
            call prob%set_particle(obs, ctf, sigma2)
            num   = 0._real64
            den   = 0._real64
            cross = 0._real64
            mm    = 0._real64
            do k = -b2, b2
                do h = -b2, b2
                    sh = nint(sqrt(real(h * h + k * k, real64)))
                    if( h * h + k * k > b2 * b2 .or. sh < kfrom .or. sh > FIX_KTO ) cycle
                    w2    = 1._real64 / sigma2(1 + sh)
                    num   = num + w2 * abs(m(h + b2 + 1, k + b2 + 1) - obs(h + b2 + 1, k + b2 + 1))**2
                    den   = den + w2 * abs(obs(h + b2 + 1, k + b2 + 1))**2
                    cross = cross + real(conjg(obs(h + b2 + 1, k + b2 + 1)) * m(h + b2 + 1, k + b2 + 1))
                    mm    = mm + abs(m(h + b2 + 1, k + b2 + 1))**2
                end do
            end do
            if( icase == 3 )then
                ! the unweighted particle power is the sum of w2 |obs|**2 at unit variances; recomputed plainly
                den = sum(abs(obs)**2, mask=band_mask(kfrom))
                ref = 1._real64 - cross / sqrt(den * mm)
            else
                ref = num / den
            endif
            err = max(err, oracle_finite_or_inf(abs(prob%objective(r1, s1) - ref) / abs(ref)))
        end do
        call prob%kill()
    end subroutine check_plane

    ! the Euclidean objective: zero residual at the planted pose (root of the loss, gradient, scale less one);
    ! multiples of the model (loss, scale with its clamps, matrix as the scale times the unscaled one); a factor
    ! per shell (scale against a full-plane sum); matrix and gradient against central differences
    subroutine check_euclid( err )
        real(real64), intent(inout) :: err(4)
        type(oracle_pose_problem) :: prob
        complex(real64)           :: obs(FIX_BOX+1, FIX_BOX+1)
        complex(real64)           :: scaled(FIX_BOX+1, FIX_BOX+1)
        real(real64)              :: r0(3, 3), s0(2), r1(3, 3), s1(2), grad(5), mat(5, 5), mat1(5, 5), lambda(4), sc(4)
        real(real64)              :: sigma2(FIX_BOX/2+1), factor, weight, num, den
        integer                   :: i, h, k, b2, sh
        call oracle_pose_fixture('euclid', prob)
        call oracle_pose_fixture_pose(.false., r0, s0)
        call oracle_pose_fixture_pose(.true., r1, s1)
        call prob%derivatives(r0, s0, grad, mat1)
        err(1) = max(err(1), oracle_finite_or_inf(sqrt(abs(prob%objective(r0, s0)))), vector_size(grad), &
                     oracle_finite_or_inf(abs(prob%scale(r0, s0) - 1._real64)))
        err(3) = max(err(3), matrix_difference(prob, r0, s0))
        err(4) = max(err(4), gradient_difference(prob, r1, s1))
        ! multiples of the model: the scale is lambda inside the clamp, 20 above it and 0.05 below it
        obs    = prob%model(fixture_ctf(), r0, s0)
        lambda = [MULTIPLE, 40._real64, 0.02_real64, -1._real64]
        sc     = [MULTIPLE, SCALE_MAX, SCALE_MIN, SCALE_MIN]
        do i = 1, 4
            call prob%set_particle(lambda(i) * obs, fixture_ctf(), fixture_sigma2())
            call prob%derivatives(r0, s0, grad, mat)
            err(2) = max(err(2), oracle_finite_or_inf(abs(prob%objective(r0, s0) - (1._real64 - 1._real64 / lambda(i))**2) / &
                                                      (1._real64 - 1._real64 / lambda(i))**2), &
                         oracle_finite_or_inf(abs(prob%scale(r0, s0) - sc(i)) / sc(i)), &
                         matrix_error(mat * lambda(i)**2 / sc(i), mat1))
        end do
        ! the model times 1 + shell / 10: the scale is the mean of that factor under the weight (h**2 + k**2)
        ! |model|**2 / sigma2, summed here over the full plane, every pixel of the band once
        b2     = FIX_BOX / 2
        sigma2 = fixture_sigma2()
        scaled = obs
        num    = 0._real64
        den    = 0._real64
        do k = -b2, b2
            do h = -b2, b2
                sh = nint(sqrt(real(h * h + k * k, real64)))
                if( h * h + k * k > b2 * b2 .or. sh < 1 .or. sh > FIX_KTO ) cycle
                factor = 1._real64 + 0.1_real64 * real(sh, real64)
                weight = real(h * h + k * k, real64) * abs(obs(h + b2 + 1, k + b2 + 1))**2 / sigma2(1 + sh)
                num    = num + factor * weight
                den    = den + weight
                scaled(h + b2 + 1, k + b2 + 1) = factor * obs(h + b2 + 1, k + b2 + 1)
            end do
        end do
        call prob%set_particle(scaled, fixture_ctf(), sigma2)
        err(2) = max(err(2), oracle_finite_or_inf(abs(prob%scale(r0, s0) - num / den) / (num / den)))
        call prob%kill()
    end subroutine check_euclid

    ! the correlation objective. For the particle that is 2.5 times the model at the planted pose: the
    ! objective, the gradient and the scale less one; for minus the model: the objective 2, the scale's lower
    ! clamp and the matrix as 0.05 times the first; the matrix and the gradient against central differences
    subroutine check_cc( err )
        real(real64), intent(inout) :: err(4)
        type(oracle_pose_problem) :: prob
        real(real64)              :: r0(3, 3), s0(2), r1(3, 3), s1(2), grad(5), mat(5, 5), mat1(5, 5)
        call oracle_pose_fixture('cc', prob)
        call oracle_pose_fixture_pose(.false., r0, s0)
        call oracle_pose_fixture_pose(.true., r1, s1)
        call prob%derivatives(r0, s0, grad, mat1)
        err(1) = max(err(1), oracle_finite_or_inf(abs(prob%objective(r0, s0))), vector_size(grad), &
                     oracle_finite_or_inf(abs(prob%scale(r0, s0) - 1._real64)))
        err(3) = max(err(3), matrix_difference(prob, r0, s0))
        err(4) = max(err(4), gradient_difference(prob, r1, s1))
        call prob%set_particle(-prob%model(fixture_ctf(), r0, s0), fixture_ctf(), fixture_sigma2())
        call prob%derivatives(r0, s0, grad, mat)
        err(2) = max(err(2), oracle_finite_or_inf(abs(prob%objective(r0, s0) - 2._real64)), &
                     oracle_finite_or_inf(abs(prob%scale(r0, s0) - SCALE_MIN) / SCALE_MIN), &
                     matrix_error(mat / SCALE_MIN, mat1))
        call prob%kill()
    end subroutine check_cc

    ! the shift-only terms against entries 4 and 5 of the full gradient and the lower right block of the full
    ! matrix, at the planted and at the displaced pose
    subroutine check_shift_terms( objective, err )
        character(len=*), intent(in)    :: objective
        real(real64),     intent(inout) :: err
        type(oracle_pose_problem) :: prob
        real(real64)              :: r(3, 3), shift(2), grad(5), mat(5, 5), grad2(2), mat2(2, 2)
        integer                   :: ipose
        call oracle_pose_fixture(objective, prob)
        do ipose = 1, 2
            call oracle_pose_fixture_pose(ipose == 2, r, shift)
            call prob%derivatives(r, shift, grad, mat)
            call prob%shift_derivatives(r, shift, grad2, mat2)
            err = max(err, matrix_error(mat2, mat(4:5, 4:5)))
            ! at the planted pose the gradient is zero, so its entries are measured against the displaced one's
            if( ipose == 2 )then
                err = max(err, oracle_finite_or_inf(vector_size(grad2 - grad(4:5)) / vector_size(grad)))
            else
                err = max(err, vector_size(grad2 - grad(4:5)))
            endif
        end do
        call prob%kill()
    end subroutine check_shift_terms

    ! the floor on the powers: a particle or a model 1e-12 times smaller leaves the correlation as it was; 1e-20
    ! times smaller, every result is NaN, except the Euclidean ones under a small model: a loss of one and a
    ! scale of one. Counted when it is not so
    subroutine check_floor( err )
        real(real64), intent(inout) :: err
        type(oracle_pose_problem) :: prob
        complex(real64)           :: obs(FIX_BOX+1, FIX_BOX+1)
        real(real64)              :: r0(3, 3), s0(2), r(3, 3), shift(2), grad(5), mat(5, 5), grad2(2), mat2(2, 2), ref
        integer                   :: icase, nbad
        nbad = 0
        call oracle_pose_fixture_pose(.false., r0, s0)
        call oracle_pose_fixture_pose(.true., r, shift)
        do icase = 1, 2
            call oracle_pose_fixture(merge('cc    ', 'euclid', icase == 1), prob)
            obs = prob%model(fixture_ctf(), r0, s0)
            call prob%set_particle(obs, fixture_ctf(), fixture_sigma2())
            ref = prob%objective(r, shift)
            ! above the floor
            call prob%set_particle(1.e-12_real64 * obs, fixture_ctf(), fixture_sigma2())
            if( ieee_is_nan(prob%objective(r, shift)) ) nbad = nbad + 1
            if( icase == 1 )then
                if( .not. (abs(prob%objective(r, shift) - ref) <= TOL_ROUTE * abs(ref)) ) nbad = nbad + 1
                call prob%set_particle(obs, 1.e-12_real64 * fixture_ctf(), fixture_sigma2())
                if( .not. (abs(prob%objective(r, shift) - ref) <= TOL_ROUTE * abs(ref)) ) nbad = nbad + 1
            endif
            ! a particle power below the floor
            call prob%set_particle(1.e-20_real64 * obs, fixture_ctf(), fixture_sigma2())
            call prob%derivatives(r, shift, grad, mat)
            call prob%shift_derivatives(r, shift, grad2, mat2)
            if( .not. ieee_is_nan(prob%objective(r, shift)) ) nbad = nbad + 1
            if( .not. ieee_is_nan(prob%scale(r, shift)) ) nbad = nbad + 1
            nbad = nbad + count(.not. ieee_is_nan(grad)) + count(.not. ieee_is_nan(mat)) + &
                   count(.not. ieee_is_nan(grad2)) + count(.not. ieee_is_nan(mat2))
            ! a model power below the floor
            call prob%set_particle(obs, 1.e-20_real64 * fixture_ctf(), fixture_sigma2())
            call prob%derivatives(r, shift, grad, mat)
            call prob%shift_derivatives(r, shift, grad2, mat2)
            if( icase == 1 )then
                if( .not. ieee_is_nan(prob%objective(r, shift)) ) nbad = nbad + 1
                if( .not. ieee_is_nan(prob%scale(r, shift)) ) nbad = nbad + 1
                nbad = nbad + count(.not. ieee_is_nan(grad)) + count(.not. ieee_is_nan(mat)) + &
                       count(.not. ieee_is_nan(grad2)) + count(.not. ieee_is_nan(mat2))
            else
                if( .not. (abs(prob%objective(r, shift) - 1._real64) <= TOL_ROUTE) ) nbad = nbad + 1
                if( .not. (abs(prob%scale(r, shift) - 1._real64) <= 0._real64) ) nbad = nbad + 1
                nbad = nbad + count(ieee_is_nan(grad)) + count(ieee_is_nan(mat)) + count(ieee_is_nan(grad2)) + &
                       count(ieee_is_nan(mat2))
            endif
        end do
        err = max(err, real(nbad, real64))
        call prob%kill()
    end subroutine check_floor

    ! the solve from the displaced start: the rotation (radians) and the shift (pixels) left to the planted pose;
    ! and, counted: a history that is not monotone, a short step whose decrease is not the predicted one, a first
    ! step that a recomputation does not give, an end that is not a convergence, a result not below the start
    subroutine check_solve( objective, err, err_history )
        character(len=*), intent(in)    :: objective
        real(real64),     intent(inout) :: err(2), err_history
        type(oracle_pose_problem) :: prob
        real(real64), allocatable :: trace(:,:)
        real(real64)              :: rt(3, 3), st(2), r(3, 3), s(2), r1(3, 3), s1(2), f0, held
        integer                   :: status, it, nbad, nquad
        call oracle_pose_fixture(objective, prob)
        call oracle_pose_fixture_pose(.false., rt, st)
        call oracle_pose_fixture_pose(.true., r1, s1)
        r  = r1
        s  = s1
        f0 = prob%objective(r, s)
        call prob%solve(r, s, trace, status)
        err(1) = max(err(1), oracle_finite_or_inf(2._real64 * asin(min(1._real64, sqrt(sum((r - rt)**2)) / sqrt(8._real64)))))
        err(2) = max(err(2), oracle_finite_or_inf(norm2(s - st)))
        nbad   = 0
        held   = f0
        nquad  = 0
        do it = 1, size(trace, 2)
            if( trace(3, it) > 0.5_real64 )then
                if( .not. (trace(1, it) < held) ) nbad = nbad + 1
                ! near a solution without residual the quadratic model is exact to third order: a short step
                ! decreases the objective by what was predicted, to a part in a hundred
                if( max(trace(4, it), trace(5, it)) < SHORT_STEP .and. trace(6, it) > LEAST_PREDICTED )then
                    nquad = nquad + 1
                    if( .not. (abs((held - trace(1, it)) / trace(6, it) - 1._real64) <= TOL_PREDICTED) ) nbad = nbad + 1
                endif
                held = trace(1, it)
            else if( .not. (abs(trace(1, it) - held) <= 0._real64) )then
                nbad = nbad + 1
            endif
        end do
        if( .not. (prob%objective(r, s) < f0) ) nbad = nbad + 1
        ! the returned pose has the objective held last, to the rounding of an objective of the start's size:
        ! near zero residual a second evaluation may round differently
        if( .not. (abs(prob%objective(r, s) - held) <= TOL_ROUTE * f0) ) nbad = nbad + 1
        ! it ends on an accepted step, by the gradient's stop or the step's
        if( size(trace, 2) < 1 .or. size(trace, 2) > MAXITER )then
            nbad = nbad + 1
        else
            if( .not. (trace(3, size(trace, 2)) > 0.5_real64) ) nbad = nbad + 1
            if( first_step_error(prob, r1, s1, trace(4:6, 1)) > TOL_FIRST_STEP ) nbad = nbad + 1
        endif
        if( status /= STATUS_GRADIENT .and. status /= STATUS_STEP ) nbad = nbad + 1
        if( nquad < 1 ) nbad = nbad + 1
        err_history = max(err_history, real(nbad, real64))
        call prob%kill()
    end subroutine check_solve

    ! started at the planted pose, where the gradient is zero, the solve takes no step and returns the pose
    subroutine check_solved( err )
        real(real64), intent(inout) :: err
        type(oracle_pose_problem) :: prob
        real(real64), allocatable :: trace(:,:)
        real(real64)              :: rt(3, 3), st(2), r(3, 3), s(2)
        integer                   :: status, nbad
        nbad = 0
        call oracle_pose_fixture('euclid', prob)
        call oracle_pose_fixture_pose(.false., rt, st)
        r = rt
        s = st
        call prob%solve(r, s, trace, status)
        if( status /= STATUS_GRADIENT .or. size(trace, 2) /= 0 ) nbad = nbad + 1
        nbad = nbad + count(.not. (abs(r - rt) <= 0._real64)) + count(.not. (abs(s - st) <= 0._real64))
        err  = max(err, real(nbad, real64))
        call prob%kill()
    end subroutine check_solved

    ! the solve's rules replayed on its trace, for particles 40 and 400 times the model: there the clamp of the
    ! scale leaves the matrix too small, and steps are capped and rejected. Counted: an acceptance, a held
    ! objective, a damping or a step length the rules do not give, and a rule the two solves never exercise
    subroutine check_solve_rules( err )
        real(real64), intent(inout) :: err
        type(oracle_pose_problem) :: prob
        complex(real64)           :: obs(FIX_BOX+1, FIX_BOX+1)
        real(real64), allocatable :: trace(:,:)
        real(real64)              :: r0(3, 3), s0(2), r(3, 3), s(2), r1(3, 3), s1(2), held, mu, mult, actual, lambda(2)
        integer                   :: status, it, irun, nbad, nrej, seen(6)
        logical                   :: accepted, expected
        call oracle_pose_fixture('euclid', prob)
        call oracle_pose_fixture_pose(.false., r0, s0)
        obs    = prob%model(fixture_ctf(), r0, s0)
        lambda = [40._real64, 400._real64]
        nbad   = 0
        seen   = 0
        do irun = 1, 2
            call prob%set_particle(lambda(irun) * obs, fixture_ctf(), fixture_sigma2())
            call oracle_pose_fixture_pose(.true., r, s)
            held = prob%objective(r, s)
            call prob%solve(r, s, trace, status)
            if( size(trace, 2) < 1 )then
                nbad = nbad + 1
                cycle
            endif
            ! the first step, capped in its rotation part, recomputed from the derivatives at the start
            call oracle_pose_fixture_pose(.true., r1, s1)
            if( first_step_error(prob, r1, s1, trace(4:6, 1)) > TOL_FIRST_STEP ) nbad = nbad + 1
            ! the damping starts at 1e-3 and its multiplier at 4
            mu   = 1.e-3_real64
            mult = 4._real64
            nrej = 0
            do it = 1, size(trace, 2)
                accepted = trace(3, it) > 0.5_real64
                if( .not. (abs(trace(2, it) - mu) <= 1.e-12_real64 * mu) ) nbad = nbad + 1
                ! the caps: 0.1 rad and 1 pixel
                if( .not. (trace(4, it) <= 0.1_real64 * (1._real64 + 1.e-12_real64)) ) nbad = nbad + 1
                if( .not. (trace(5, it) <= 1._real64 + 1.e-12_real64) ) nbad = nbad + 1
                if( abs(trace(4, it) - 0.1_real64) <= 1.e-12_real64 ) seen(1) = 1
                if( abs(trace(5, it) - 1._real64) <= 1.e-12_real64 ) seen(2) = 1
                expected = .false.
                actual   = 0._real64
                if( ieee_is_nan(trace(7, it)) )then
                    ! no trial: the predicted decrease is not positive, or it is below 1e-6 of the objective,
                    ! which ends the solve with status 2
                    if( trace(6, it) > 0._real64 )then
                        if( .not. (trace(6, it) < 1.e-6_real64 * abs(held)) ) nbad = nbad + 1
                        if( it /= size(trace, 2) .or. status /= 2 ) nbad = nbad + 1
                    endif
                else
                    ! a trial is not evaluated below the stop on the predicted decrease
                    if( trace(6, it) < 1.e-6_real64 * abs(held) ) nbad = nbad + 1
                    ! accepted when the decrease is positive and at least a quarter of the predicted one
                    actual = held - trace(7, it)
                    if( trace(6, it) > 0._real64 .and. actual > 0._real64 ) expected = actual / trace(6, it) >= 0.25_real64
                endif
                if( accepted .neqv. expected ) nbad = nbad + 1
                if( accepted )then
                    ! the damping halves above three quarters; the multiplier returns to 4
                    held = trace(7, it)
                    if( actual / trace(6, it) > 0.75_real64 )then
                        mu      = max(mu / 2._real64, epsilon(mu))
                        seen(3) = 1
                    else
                        seen(4) = 1
                    endif
                    if( nrej > 0 ) seen(5) = 1
                    mult = 4._real64
                    nrej = 0
                else
                    ! a rejection multiplies the damping, and doubles the multiplier
                    mu   = min(mu * mult, 1._real64 / epsilon(mu))
                    mult = 2._real64 * mult
                    nrej = nrej + 1
                    if( nrej >= 3 ) seen(6) = 1
                endif
                if( .not. (abs(trace(1, it) - held) <= 0._real64) ) nbad = nbad + 1
            end do
            if( .not. (abs(prob%objective(r, s) - held) <= TOL_ROUTE * abs(held)) ) nbad = nbad + 1
        end do
        ! exercised: both caps, an acceptance with and without the halving, one after a rejection, and three
        ! rejections in a row
        nbad = nbad + count(seen == 0)
        err  = max(err, real(nbad, real64))
        call prob%kill()
    end subroutine check_solve_rules

    ! the first step of a solve recomputed from the derivatives at its start: (C + mu diag(C)) d = -g at the
    ! starting damping by elimination with pivoting, each part scaled down to its cap, and the predicted decrease
    ! -g.d - d.C d / 2; the largest relative difference from step = [rotation length, shift length, predicted]
    function first_step_error( prob, r, shift, step ) result(e)
        type(oracle_pose_problem), intent(in) :: prob
        real(real64),              intent(in) :: r(3, 3), shift(2), step(3)
        real(real64) :: e, g(5), c(5, 5), a(5, 6), row(6), d(5), mine(3)
        integer      :: i, j, p
        call prob%derivatives(r, shift, g, c)
        a(:, 1:5) = c
        do i = 1, 5
            a(i, i) = a(i, i) + 1.e-3_real64 * c(i, i)
        end do
        a(:, 6) = -g
        do j = 1, 5
            p       = j - 1 + maxloc(abs(a(j:5, j)), 1)
            row     = a(j, :)
            a(j, :) = a(p, :)
            a(p, :) = row
            do i = j + 1, 5
                a(i, :) = a(i, :) - a(i, j) / a(j, j) * a(j, :)
            end do
        end do
        do i = 5, 1, -1
            d(i) = (a(i, 6) - sum(a(i, i+1:5) * d(i+1:5))) / a(i, i)
        end do
        ! the caps: 0.1 rad and 1 pixel
        if( norm2(d(1:3)) > 0.1_real64 ) d(1:3) = d(1:3) * 0.1_real64 / norm2(d(1:3))
        if( norm2(d(4:5)) > 1._real64 ) d(4:5) = d(4:5) / norm2(d(4:5))
        mine = [norm2(d(1:3)), norm2(d(4:5)), -dot_product(g, d) - 0.5_real64 * dot_product(d, matmul(c, d))]
        e    = vector_size((mine - step) / step)
    end function first_step_error

    ! the gradient at a pose against central differences of the objective along the five parameters, the
    ! largest difference over the largest component
    function gradient_difference( prob, r, shift ) result(e)
        type(oracle_pose_problem), intent(in) :: prob
        real(real64),              intent(in) :: r(3, 3), shift(2)
        real(real64) :: e, grad(5), mat(5, 5), fd(5), d(5), fp, fm
        integer      :: a
        call prob%derivatives(r, shift, grad, mat)
        do a = 1, 5
            d     = 0._real64
            d(a)  = DIFF_STEP
            fp    = prob%objective(oracle_pose_rotate(r, d(1:3)), shift + d(4:5))
            fm    = prob%objective(oracle_pose_rotate(r, -d(1:3)), shift - d(4:5))
            fd(a) = (fp - fm) / (2._real64 * DIFF_STEP)
        end do
        if( any(ieee_is_nan(grad)) .or. any(ieee_is_nan(fd)) )then
            e = oracle_finite_or_inf(ieee_value(1._real64, ieee_quiet_nan))
        else
            e = oracle_finite_or_inf(maxval(abs(grad - fd)) / maxval(abs(grad)))
        endif
    end function gradient_difference

    ! the matrix at a pose against central differences of the gradient along the five parameters, the largest
    ! difference over the largest entry
    function matrix_difference( prob, r, shift ) result(e)
        type(oracle_pose_problem), intent(in) :: prob
        real(real64),              intent(in) :: r(3, 3), shift(2)
        real(real64) :: e, grad(5), mat(5, 5), fd(5, 5), d(5), gp(5), gm(5), dummy(5, 5)
        integer      :: b
        call prob%derivatives(r, shift, grad, mat)
        do b = 1, 5
            d    = 0._real64
            d(b) = DIFF_STEP
            call prob%derivatives(oracle_pose_rotate(r, d(1:3)), shift + d(4:5), gp, dummy)
            call prob%derivatives(oracle_pose_rotate(r, -d(1:3)), shift - d(4:5), gm, dummy)
            fd(:, b) = (gp - gm) / (2._real64 * DIFF_STEP)
        end do
        e = matrix_error(mat, fd)
    end function matrix_difference

    ! the largest |a - ref| over the largest |ref|; +Inf when either holds a NaN
    pure function matrix_error( a, ref ) result(e)
        real(real64), intent(in) :: a(:,:), ref(:,:)
        real(real64) :: e
        if( any(ieee_is_nan(a)) .or. any(ieee_is_nan(ref)) )then
            e = oracle_finite_or_inf(ieee_value(1._real64, ieee_quiet_nan))
        else
            e = oracle_finite_or_inf(maxval(abs(a - ref)) / maxval(abs(ref)))
        endif
    end function matrix_error

    ! the largest magnitude of a vector that should be zero; +Inf when it holds a NaN
    pure function vector_size( a ) result(e)
        real(real64), intent(in) :: a(:)
        real(real64) :: e
        if( any(ieee_is_nan(a)) )then
            e = oracle_finite_or_inf(ieee_value(1._real64, ieee_quiet_nan))
        else
            e = oracle_finite_or_inf(maxval(abs(a)))
        endif
    end function vector_size

    ! the 3 by 3 identity
    pure function identity3() result(e)
        real(real64) :: e(3, 3)
        e = reshape([1._real64, 0._real64, 0._real64, 0._real64, 1._real64, 0._real64, 0._real64, 0._real64, 1._real64], &
                    [3, 3])
    end function identity3

    ! the pixels of the fixture's plane on the shells kfrom to the fixture's last
    pure function band_mask( kfrom ) result(mask)
        integer, intent(in) :: kfrom
        logical :: mask(FIX_BOX+1, FIX_BOX+1)
        integer :: h, k, b2, sh
        b2 = FIX_BOX / 2
        do k = -b2, b2
            do h = -b2, b2
                sh = nint(sqrt(real(h * h + k * k, real64)))
                mask(h + b2 + 1, k + b2 + 1) = h * h + k * k <= b2 * b2 .and. sh >= kfrom .and. sh <= FIX_KTO
            end do
        end do
    end function band_mask

    ! the quadratic B-spline kernel at distance d: 3/4 - d**2 up to 1/2, (|d| - 3/2)**2 / 2 up to 3/2, zero beyond
    pure function bspline_kernel( d ) result(b)
        real(real64), intent(in) :: d
        real(real64) :: b
        if( abs(d) <= 0.5_real64 )then
            b = 0.75_real64 - d**2
        else if( abs(d) <= 1.5_real64 )then
            b = (abs(d) - 1.5_real64)**2 / 2._real64
        else
            b = 0._real64
        endif
    end function bspline_kernel

    ! the kernel's derivative: -2 d up to 1/2, sign(d) (|d| - 3/2) up to 3/2, zero beyond
    pure function bspline_slope( d ) result(b)
        real(real64), intent(in) :: d
        real(real64) :: b
        if( abs(d) <= 0.5_real64 )then
            b = -2._real64 * d
        else if( abs(d) <= 1.5_real64 )then
            b = (abs(d) - 1.5_real64) * sign(1._real64, d)
        else
            b = 0._real64
        endif
    end function bspline_slope

    ! the gather and its gradient as a sum of the kernel over the four lattice points per axis that can lie
    ! within its support, by their distances: no rounding rule and none of the tap formulas
    pure subroutine kernel_gather( f, loc, v, dv )
        complex(real64), intent(in)  :: f(:,:,:)
        real(real64),    intent(in)  :: loc(3)
        complex(real64), intent(out) :: v, dv(3)
        complex(real64) :: fv
        real(real64)    :: b(4, 3), s(4, 3)
        integer         :: base(3), a, j, j1, j2, j3
        base = floor(loc) - 2
        do a = 1, 3
            do j = 1, 4
                b(j, a) = bspline_kernel(loc(a) - real(base(a) + j, real64))
                s(j, a) = bspline_slope(loc(a) - real(base(a) + j, real64))
            end do
        end do
        v  = CZERO
        dv = CZERO
        do j3 = 1, 4
            do j2 = 1, 4
                do j1 = 1, 4
                    fv    = f(1 + modulo(base(1) + j1, size(f, 1)), 1 + modulo(base(2) + j2, size(f, 2)), &
                              1 + modulo(base(3) + j3, size(f, 3)))
                    v     = v + b(j1, 1) * b(j2, 2) * b(j3, 3) * fv
                    dv(1) = dv(1) + s(j1, 1) * b(j2, 2) * b(j3, 3) * fv
                    dv(2) = dv(2) + b(j1, 1) * s(j2, 2) * b(j3, 3) * fv
                    dv(3) = dv(3) + b(j1, 1) * b(j2, 2) * s(j3, 3) * fv
                end do
            end do
        end do
    end subroutine kernel_gather

    ! the gather's value at lattice point m, written from the volume: the transform at m of the padded volume
    ! times the Kaiser-Bessel envelope w0 + 2 w1 cos(2 pi (x - c) / n) along each axis, the weights from I0 by
    ! the trapezoid rule, with 1 / box**3
    pure function lattice_value( vol, m ) result(v)
        real(real64), intent(in) :: vol(:,:,:)
        integer,      intent(in) :: m(3)
        complex(real64) :: v
        real(real64)    :: w0, w1, kb(size(vol, 1)), x
        integer         :: box, n, i, i1, i2, i3
        box = size(vol, 1)
        n   = PADFAC * box
        w0  = i0_trapezoid(KB_BETA)
        w1  = i0_trapezoid(KB_BETA * sqrt(5._real64) / 3._real64)
        ! the volume's index i sits at the centred coordinate x = i - 1 - box/2 of the padded lattice
        do i = 1, box
            x     = real(i - 1 - box / 2, real64)
            kb(i) = (w0 + 2._real64 * w1 * cos(TWOPI * x / real(n, real64))) / (w0 + 2._real64 * w1)
        end do
        v = CZERO
        do i3 = 1, box
            do i2 = 1, box
                do i1 = 1, box
                    v = v + vol(i1, i2, i3) * kb(i1) * kb(i2) * kb(i3) * &
                        exp(cmplx(0._real64, -TWOPI * real(dot_product(m, [i1, i2, i3] - 1 - box / 2), real64) / &
                                             real(n, real64), real64))
                end do
            end do
        end do
        v = v / real(box, real64)**3
    end function lattice_value

end module mlxf_oracle_pose
