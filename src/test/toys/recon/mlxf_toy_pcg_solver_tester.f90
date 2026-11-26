!@descr: tests of the toy PCG engine: its stops on constructed systems, and the stencil problem against host Cholesky
! The constructed systems are small diagonal ones whose iterates are known in rationals (mlxf_oracle_recon_pcg's
! cases, on the device in float32): every reason, count and the step test's epsilon is exact. The stencil problem is
! mlxf_oracle_pcg's, H = S C^T F^-1 diag(d) F C S + lambda I, through a test-only operator of library transforms,
! held to the oracle's explicit matrix, to Cholesky on the right-hand side rounded once to float32, and to the
! oracle's matrix-free solve at n = 8 in m = 16.
module mlxf_toy_pcg_solver_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan, ieee_is_finite
use mlxf,                    only: mlx_array, mlx_from, mlx_to, mlx_eval, mlx_rfftn, mlx_irfftn, mlx_slice, &
                                   mlx_set_default_device, mlx_default_device, matmul, reshape, sum
use mlxf_test_defs,          only: pcg_solver_options, RECON_PCG_TOLERANCES, ELEM_CEILING, PCG_STOP_INDEFINITE
use mlxf_toy_pcg_solver,     only: pcg_solver_outcome
use mlxf_toy_pcg_solver_mlx, only: pcg_operator, pcg_solve
use mlxf_oracle_pcg,         only: oracle_pcg_problem, oracle_pcg_true, oracle_pcg_cholesky
use mlxf_test_utils,         only: assert_true, assert_int, device_name, test_devices, bits_equal
use mlxf_test_reduce,        only: nan_maxval
implicit none
private
public :: run_all_pcg_solver_tests

real(real64), parameter :: PI = acos(-1._real64)
! the stencil problem's ridge and the solve's rules: the residual's tolerance, no step test, the iterations
real(real64), parameter :: STENCIL_LAMBDA = 0.25_real64
real(real32), parameter :: STENCIL_RTOL   = 1.e-6_real32
! the diagonal system of the recomputation's cases
integer, parameter :: NREC = 80
! the stencil's windows judged against the explicit matrix
character(len=8), parameter :: WINS(2) = [character(len=8) :: 'surface', 'face']

! a dense system on the device: y = A x, z = B x, A's applications counted, A + shift I from application `first`
type, extends(pcg_operator) :: dense_operator
    integer         :: n      = 0
    integer         :: napply = 0
    integer         :: first  = huge(1)
    real(real32)    :: shift  = 0._real32
    type(mlx_array) :: a
    type(mlx_array) :: b
  contains
    procedure :: size    => dense_size
    procedure :: apply   => dense_apply
    procedure :: precond => dense_precond
    procedure :: dot     => dense_dot
end type dense_operator

! the stencil problem on the device: the n-cube at the corner of the m-grid (a translation of the oracle's centre
! embedding, which the Fourier multiplier does not see), the window S, the packed spectrum d and 1 / (d + lambda)
type, extends(pcg_operator) :: stencil_operator
    integer         :: n   = 0
    integer         :: m   = 0
    real(real32)    :: sgn = 1._real32
    type(mlx_array) :: s
    type(mlx_array) :: d
    type(mlx_array) :: pinv
  contains
    procedure :: size    => stencil_size
    procedure :: apply   => stencil_apply
    procedure :: precond => stencil_precond
    procedure :: dot     => stencil_dot
end type stencil_operator

contains

    subroutine run_all_pcg_solver_tests
        integer, allocatable :: devs(:)
        integer              :: id
        write(*,'(a)') '**** running all pcg_solver tests ****'
        call test_devices(devs)
        do id = 1, size(devs)
            call mlx_set_default_device(devs(id))
            call test_constructed_stops
            call test_recomputation
            call test_stencil
        end do
    end subroutine run_all_pcg_solver_tests

    ! the tolerance of a named gate: frozen, or its ceiling while it is not
    real(real64) function tol( name )
        character(len=*), intent(in) :: name
        integer :: k
        tol = -1._real64
        do k = 1, size(RECON_PCG_TOLERANCES)
            if( trim(RECON_PCG_TOLERANCES(k)%name) /= name ) cycle
            tol = RECON_PCG_TOLERANCES(k)%ceiling
            if( RECON_PCG_TOLERANCES(k)%frozen > 0._real64 ) tol = RECON_PCG_TOLERANCES(k)%frozen
        end do
    end function tol

    ! ---- the dense operator ----------------------------------------------------------------------------------

    subroutine dense_new( op, d, scale )
        type(dense_operator), intent(inout) :: op
        real(real64),         intent(in)    :: d(:), scale
        real(real32) :: a(size(d), size(d)), b(size(d), size(d))
        integer      :: i
        a = 0._real32
        b = 0._real32
        do i = 1, size(d)
            a(i, i) = real(d(i), real32)
            b(i, i) = real(scale, real32)
        end do
        op%n      = size(d)
        op%napply = 0
        op%first  = huge(1)
        op%shift  = 0._real32
        op%a      = mlx_from(a)
        op%b      = mlx_from(b)
    end subroutine dense_new

    integer function dense_size( self ) result(n)
        class(dense_operator), intent(in) :: self
        n = self%n
    end function dense_size

    subroutine dense_apply( self, x, y )
        class(dense_operator), intent(inout) :: self
        type(mlx_array),       intent(in)    :: x
        type(mlx_array),       intent(out)   :: y
        self%napply = self%napply + 1
        y = reshape(matmul(self%a, reshape(x, [self%n, 1])), [self%n])
        if( self%napply >= self%first ) y = y + self%shift * x
    end subroutine dense_apply

    subroutine dense_precond( self, r, z )
        class(dense_operator), intent(inout) :: self
        type(mlx_array),       intent(in)    :: r
        type(mlx_array),       intent(out)   :: z
        z = reshape(matmul(self%b, reshape(r, [self%n, 1])), [self%n])
    end subroutine dense_precond

    function dense_dot( self, a, b ) result(d)
        class(dense_operator), intent(in) :: self
        type(mlx_array),       intent(in) :: a, b
        type(mlx_array) :: d
        d = reshape(a * b, [self%n])
    end function dense_dot

    ! one solve of a dense system from the host start in x, returning the iterate in x
    subroutine dense_solve( op, b, opts, x, outcome )
        type(dense_operator),     intent(inout) :: op
        real(real64),             intent(in)    :: b(:)
        type(pcg_solver_options), intent(in)    :: opts
        real(real32),             intent(inout) :: x(:)
        type(pcg_solver_outcome), intent(out)   :: outcome
        type(mlx_array) :: bd, xd
        bd = mlx_from(real(b, real32))
        xd = mlx_from(x)
        call pcg_solve(op, bd, xd, opts, outcome)
        call mlx_to(x, xd)
    end subroutine dense_solve

    logical function near( x, ref )
        real(real32), intent(in) :: x(:)
        real(real64), intent(in) :: ref(:)
        near = nan_maxval(abs(real(x, real64) - ref)) <= ELEM_CEILING * max(1._real64, nan_maxval(abs(ref)))
    end function near

    ! both histories allocated, one value per iteration, every value finite
    logical function histories_sound( oc )
        type(pcg_solver_outcome), intent(in) :: oc
        histories_sound = .false.
        if( .not. allocated(oc%rel_residual_history) ) return
        if( .not. allocated(oc%rel_update_history) ) return
        if( size(oc%rel_residual_history) /= oc%iteration_count ) return
        if( size(oc%rel_update_history) /= oc%iteration_count ) return
        histories_sound = all(ieee_is_finite(oc%rel_residual_history)) .and. all(ieee_is_finite(oc%rel_update_history))
    end function histories_sound

    function opts_of( rtol, xtol, maxits ) result(o)
        real(real64), intent(in) :: rtol, xtol
        integer,      intent(in) :: maxits
        type(pcg_solver_options) :: o
        o%rtol   = real(rtol, real32)
        o%xtol   = real(xtol, real32)
        o%maxits = maxits
    end function opts_of

    ! every stop on diag(1, 2, 3), identity preconditioner, b = 1 (residuals 1/sqrt(6), sqrt(2)/10, 0; steps 1,
    ! 0.408, 0.125 of |x|; x = (1/2, 1/2, 1/2), (9/10, 3/5, 3/10), (1, 1/2, 1/3)), and the refusals
    subroutine test_constructed_stops
        type(dense_operator)          :: op
        type(pcg_solver_outcome)      :: oc
        real(real64)                  :: b(3), x2(3), x3(3), z3(3)
        real(real32)                  :: x(3)
        character(len=:), allocatable :: dev
        dev = ' ('//device_name(mlx_default_device())//')'
        write(*,'(a,a)') 'test_constructed_stops', dev
        b  = 1._real64
        z3 = 0._real64
        x2 = [0.9_real64, 0.6_real64, 0.3_real64]
        x3 = [1._real64, 0.5_real64, 1._real64 / 3._real64]
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'rtol' .and. oc%iteration_count == 3 .and. op%napply == 3, &
            'pcg_solve: three distinct eigenvalues stop on rtol after three iterations and three applications'//dev)
        call assert_true(near(x, x3), 'pcg_solve: the third iterate is (1, 1/2, 1/3)'//dev)
        call assert_true(size(oc%rel_residual_history) == 3, 'pcg_solve: one residual per iteration'//dev)
        call assert_true(histories_sound(oc), 'pcg_solve: both histories hold one finite value per iteration'//dev)
        if( size(oc%rel_residual_history) == 3 ) call assert_true(abs(oc%rel_residual_history(1) - &
            real(1._real64 / sqrt(6._real64), real32)) <= 1.e-6_real32 .and. abs(oc%rel_residual_history(2) - &
            real(sqrt(2._real64) / 10._real64, real32)) <= 1.e-6_real32, 'pcg_solve: the residuals are 1/sqrt(6), '//&
            'sqrt(2)/10'//dev)
        ! rtol before xtol when both hold at iteration 3
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0.2_real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'rtol' .and. oc%iteration_count == 3, &
            'pcg_solve: rtol is reported before xtol when both hold'//dev)
        ! xtol at the step 0.408 against 0.45, not against 0.4
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-30_real64, 0.45_real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'xtol' .and. oc%iteration_count == 2 .and. near(x, x2), &
            'pcg_solve: the step 0.408 of |x| stops on xtol 0.45 at iteration 2'//dev)
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0.4_real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'rtol' .and. oc%iteration_count == 3, &
            'pcg_solve: against xtol 0.4 the solve goes on to stop on rtol at iteration 3'//dev)
        ! the step test's epsilon: an iterate below the double-precision epsilon is measured against it
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, 1.e-17_real64 * b, opts_of(1.e-30_real64, 0.45_real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'xtol' .and. oc%iteration_count == 1, &
            'pcg_solve: an iterate below epsilon(1d0) is measured against it and stops on the first step'//dev)
        ! maxits, and fixed iterations with no test made
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0._real64, 2), x, oc)
        call assert_true(trim(oc%stop_reason) == 'maxits' .and. oc%iteration_count == 2 .and. op%napply == 2 .and. &
            near(x, x2), 'pcg_solve: maxits stops at the limit with x as the second iterate'//dev)
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(0._real64, 0.45_real64, 3), x, oc)
        call assert_true(trim(oc%stop_reason) == 'fixed_iterations' .and. oc%iteration_count == 3 .and. near(x, x3), &
            'pcg_solve: rtol <= 0 runs exactly maxits iterations with neither test'//dev)
        ! an indefinite product at once, the start as it was; at iteration 2, x as the first step left it
        call dense_new(op, [-1._real64, -2._real64, -3._real64], 1._real64)
        x = real([0.5_real64, -0.25_real64, 2._real64], real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == PCG_STOP_INDEFINITE .and. oc%failure_iteration == 1 .and. &
            oc%iteration_count == 0, 'pcg_solve: an indefinite product at iteration 1 stops'//dev)
        call assert_true(all(bits_equal(x, [0.5_real32, -0.25_real32, 2._real32])), &
            'pcg_solve: an indefinite stop at iteration 1 leaves the start as it was'//dev)
        call dense_new(op, [1._real64, 2._real64, -1._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == PCG_STOP_INDEFINITE .and. oc%failure_iteration == 2 .and. &
            oc%iteration_count == 1 .and. near(x, [1.5_real64, 1.5_real64, 1.5_real64]), &
            'pcg_solve: an indefinite product at iteration 2 leaves x as the first step left it'//dev)
        ! a right-hand side that is not finite reaches the curvature test and stops there, as SIMPLE's does
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(z3, real32)
        call dense_solve(op, [1._real64, ieee_value(1._real64, ieee_quiet_nan), 1._real64], opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == PCG_STOP_INDEFINITE .and. oc%iteration_count == 0, &
            'pcg_solve: a right-hand side that is not finite stops as indefinite at once'//dev)
        ! the refusals: a zero right-hand side, a first r . z that is zero or negative; x untouched
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real(x2, real32)
        call dense_solve(op, 0._real64 * b, opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'zero_rhs' .and. op%napply == 0 .and. near(x, x2), &
            'pcg_solve: a zero right-hand side is refused, the start untouched and the operator not applied'//dev)
        call dense_new(op, [1._real64, 2._real64, 3._real64], 0._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'nonpositive_rz', &
            'pcg_solve: a preconditioner that returns zero is refused'//dev)
        call dense_new(op, [1._real64, 2._real64, 3._real64], -1._real64)
        x = real(z3, real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'nonpositive_rz', &
            'pcg_solve: a negative preconditioner is refused'//dev)
        ! a non-zero start is used: from (1, 0, 0) two iterations solve it after one application for the start
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        x = real([1._real64, 0._real64, 0._real64], real32)
        call dense_solve(op, b, opts_of(1.e-4_real64, 0._real64, 50), x, oc)
        call assert_true(trim(oc%stop_reason) == 'rtol' .and. oc%iteration_count == 2 .and. op%napply == 3 .and. &
            near(x, x3), 'pcg_solve: a non-zero start is used and two iterations solve from it'//dev)
        ! a start worse than start_max_rel_residual is replaced by zero
        call dense_new(op, [1._real64, 2._real64, 3._real64], 1._real64)
        call reject_case(op, b, x3, dev)
    end subroutine test_constructed_stops

    ! a start whose relative residual (here 10) exceeds start_max_rel_residual (1) is replaced by zero: the solve
    ! is the cold one, three iterations to (1, 1/2, 1/3)
    subroutine reject_case( op, b, x3, dev )
        type(dense_operator), intent(inout) :: op
        real(real64),         intent(in)    :: b(:), x3(:)
        character(len=*),     intent(in)    :: dev
        type(pcg_solver_options) :: o
        type(pcg_solver_outcome) :: oc
        real(real32)             :: x(3)
        o = opts_of(1.e-4_real64, 0._real64, 50)
        o%start_max_rel_residual = 1._real32
        x = real([10._real64, 10._real64, 10._real64], real32)
        call dense_solve(op, b, o, x, oc)
        call assert_true(oc%start_rejected .and. trim(oc%stop_reason) == 'rtol' .and. oc%iteration_count == 3 .and. &
            near(x, x3), 'pcg_solve: a start worse than start_max_rel_residual is replaced by zero'//dev)
    end subroutine reject_case

    ! the residual recomputed every 25 iterations on diag(1 .. 80), b = 1, fixed iterations: 24, 26, 31 and 52
    ! applications for 24, 25, 30 and 50 iterations; an operator changed from its 26th application on, whose
    ! residual the solve reports at iteration 25 and still at 30
    subroutine test_recomputation
        type(dense_operator)          :: op
        type(pcg_solver_outcome)      :: oc
        real(real64)                  :: d(NREC), b(NREC), ref
        real(real32)                  :: x(NREC)
        integer                       :: i, icase, its(6), napply(6)
        character(len=:), allocatable :: dev
        dev = ' ('//device_name(mlx_default_device())//')'
        write(*,'(a,a)') 'test_recomputation', dev
        d      = [(real(i, real64), i=1, NREC)]
        b      = 1._real64
        its    = [24, 25, 30, 50, 25, 30]
        napply = [24, 26, 31, 52, 26, 31]
        do icase = 1, 6
            call dense_new(op, d, 1._real64)
            ref = 0._real64
            if( icase > 4 )then
                op%first = 26
                op%shift = 0.5_real32
                ref      = 0.5_real64
            endif
            x = real(0._real64 * b, real32)
            call dense_solve(op, b, opts_of(0._real64, 0._real64, its(icase)), x, oc)
            call assert_int(napply(icase), op%napply, 'pcg_solve: the operator''s applications are the iterations '//&
                'plus one per recomputation'//dev)
            if( icase > 4 )then
                ref = norm2(b - (d + ref) * real(x, real64)) / norm2(b)
                call assert_true(abs(real(oc%final_rel_residual, real64) - ref) <= 1.e-5_real64, &
                    'pcg_solve: the residual reported after a recomputation is the changed operator''s'//dev)
            endif
        end do
    end subroutine test_recomputation

    ! ---- the stencil problem -----------------------------------------------------------------------------------

    subroutine stencil_new( op, prob, n, m, sgn )
        type(stencil_operator),   intent(inout) :: op
        type(oracle_pcg_problem), intent(in)    :: prob
        integer,                  intent(in)    :: n, m
        real(real64),             intent(in)    :: sgn
        real(real64) :: s1(m), d(m/2+1, m, m)
        integer      :: q, i, j, k
        do q = 0, m - 1
            s1(q+1) = sin(PI * real(q, real64) / real(m, real64))**2
        end do
        do k = 1, m
            do j = 1, m
                do i = 1, m / 2 + 1
                    d(i, j, k) = 1._real64 + 4._real64 * (s1(i) + s1(j) + s1(k))
                end do
            end do
        end do
        op%n    = n
        op%m    = m
        op%sgn  = real(sgn, real32)
        op%s    = mlx_from(real(prob%window(), real32))
        op%d    = mlx_from(real(d, real32))
        op%pinv = mlx_from(real(1._real64 / (d + STENCIL_LAMBDA), real32))
    end subroutine stencil_new

    integer function stencil_size( self ) result(n)
        class(stencil_operator), intent(in) :: self
        n = self%n**3
    end function stencil_size

    subroutine stencil_apply( self, x, y )
        class(stencil_operator), intent(inout) :: self
        type(mlx_array),         intent(in)    :: x
        type(mlx_array),         intent(out)   :: y
        type(mlx_array) :: g, c
        integer         :: m, n
        m = self%m
        n = self%n
        g = mlx_irfftn(mlx_rfftn(self%s * x, n=[m, m, m]) * self%d, n=[m, m, m])
        c = mlx_slice(g, [1, 1, 1], [n, n, n])
        y = self%sgn * (self%s * c + real(STENCIL_LAMBDA, real32) * x)
    end subroutine stencil_apply

    subroutine stencil_precond( self, r, z )
        class(stencil_operator), intent(inout) :: self
        type(mlx_array),         intent(in)    :: r
        type(mlx_array),         intent(out)   :: z
        type(mlx_array) :: g
        integer         :: m, n
        m = self%m
        n = self%n
        g = mlx_irfftn(mlx_rfftn(r, n=[m, m, m]) * self%pinv, n=[m, m, m])
        z = mlx_slice(g, [1, 1, 1], [n, n, n])
    end subroutine stencil_precond

    function stencil_dot( self, a, b ) result(d)
        class(stencil_operator), intent(in) :: self
        type(mlx_array),         intent(in) :: a, b
        type(mlx_array) :: d
        d = sum(reshape(a * b, [self%n, self%n, self%n]), dim=1)
    end function stencil_dot

    ! the device operator's columns on unit vectors
    subroutine stencil_columns( op, cols )
        type(stencil_operator), intent(inout) :: op
        real(real64),           intent(out)   :: cols(:,:)
        type(mlx_array) :: e, y
        real(real32)    :: v(op%n**3), w(op%n**3)
        integer         :: j
        do j = 1, op%n**3
            v    = 0._real32
            v(j) = 1._real32
            e    = mlx_from(reshape(v, [op%n, op%n, op%n]))
            call op%apply(e, y)
            call mlx_to(w, y)
            cols(:, j) = real(w, real64)
        end do
    end subroutine stencil_columns

    ! one stencil solve on the device from the start in x, returning the iterate in x
    subroutine stencil_solve( op, b, opts, x, outcome )
        type(stencil_operator),   intent(inout) :: op
        real(real32),             intent(in)    :: b(:)
        type(pcg_solver_options), intent(in)    :: opts
        real(real32),             intent(inout) :: x(:)
        type(pcg_solver_outcome), intent(out)   :: outcome
        type(mlx_array) :: bd, xd
        bd = mlx_from(reshape(b, [op%n, op%n, op%n]))
        xd = mlx_from(reshape(x, [op%n, op%n, op%n]))
        call pcg_solve(op, bd, xd, opts, outcome)
        call mlx_to(x, xd)
    end subroutine stencil_solve

    ! the stencil problem: the operator against the explicit matrix (padded, zero face); from zero and from a
    ! non-zero guess the solution and the true residual against Cholesky; the unpadded case in one iteration; -H
    ! refused before its division; the cap of two iterations; n = 8 in m = 16 against the oracle's solve
    subroutine test_stencil
        type(oracle_pcg_problem)      :: prob
        type(stencil_operator)        :: op
        type(pcg_solver_outcome)      :: oc
        type(pcg_solver_options)      :: o
        real(real64),     allocatable :: h(:,:), cols(:,:), hist(:)
        real(real64)                  :: xt(64), xc(64), minpivot, err, x8(8, 8, 8), b8(8, 8, 8)
        real(real32)                  :: b32(64), x(64), x0(64), y8(512)
        integer                       :: iwin, iguess, info(2), i, j, k
        character(len=:), allocatable :: dev
        dev = ' ('//device_name(mlx_default_device())//')'
        write(*,'(a,a)') 'test_stencil', dev
        o%rtol = STENCIL_RTOL
        o%xtol = 0._real32
        o%maxits = 64
        do iwin = 1, 2
            call prob%new(4, 8, trim(WINS(iwin)), 1._real64)
            call stencil_new(op, prob, 4, 8, 1._real64)
            h = prob%matrix()
            allocate(cols(64, 64))
            call stencil_columns(op, cols)
            err = norm2(cols - h) / norm2(h)
            write(*,'(a,a,a,es12.5)') '    error stencil operator ', trim(WINS(iwin)), dev//': ', err
            call assert_true(err <= tol('stencil operator'), 'stencil: the device operator matches the explicit '//&
                'matrix, window '//trim(WINS(iwin))//dev)
            deallocate(cols)
            xt  = reshape(oracle_pcg_true(4), [64])
            b32 = real(matmul(h, xt), real32)
            call oracle_pcg_cholesky(h, real(b32, real64), xc, minpivot)
            do iguess = 0, 1
                x0 = 0._real32
                if( iguess == 1 )then
                    do k = 0, 3
                        do j = 0, 3
                            do i = 0, 3
                                x0(1 + i + 4 * j + 16 * k) = real(modulo(2 * i + 3 * j + k, 5), real32) / 5._real32
                            end do
                        end do
                    end do
                endif
                x = x0
                call stencil_solve(op, b32, o, x, oc)
                err = norm2(real(x, real64) - xc) / norm2(xc)
                write(*,'(a,a,i0,a,es12.5)') '    error stencil solution ', trim(WINS(iwin))//' guess=', iguess, &
                    dev//': ', err
                call assert_true(err <= tol('stencil solution'), 'stencil: the solution matches Cholesky on the '//&
                    'float32 right-hand side, window '//trim(WINS(iwin))//dev)
                err = norm2(real(b32, real64) - matmul(h, real(x, real64))) / norm2(real(b32, real64))
                write(*,'(a,a,i0,a,es12.5)') '    error stencil residual ', trim(WINS(iwin))//' guess=', iguess, &
                    dev//': ', err
                call assert_true(err <= tol('stencil residual'), 'stencil: the true residual by the host matrix is '//&
                    'within its tolerance, window '//trim(WINS(iwin))//dev)
            end do
            ! the cap of two iterations
            o%maxits = 2
            x = 0._real32
            call stencil_solve(op, b32, o, x, oc)
            call assert_true(trim(oc%stop_reason) == 'maxits' .and. oc%iteration_count == 2, &
                'stencil: the cap of two iterations stops on maxits at 2'//dev)
            o%maxits = 64
        end do
        ! the unpadded case: the preconditioner is H^-1 and one iteration reaches x_true
        call prob%new(4, 4, 'identity', 1._real64)
        call stencil_new(op, prob, 4, 4, 1._real64)
        h   = prob%matrix()
        b32 = real(matmul(h, xt), real32)
        o%maxits = 1
        o%rtol   = 0._real32
        x = 0._real32
        call stencil_solve(op, b32, o, x, oc)
        err = norm2(real(x, real64) - xt) / norm2(xt)
        write(*,'(a,a,es12.5)') '    error stencil unpadded one step', dev//': ', err
        call assert_true(err <= tol('stencil solution') .and. oc%iteration_count == 1, &
            'stencil: unpadded, one iteration reaches the true solution'//dev)
        ! -H is refused before its division: the first product is negative
        call prob%new(4, 8, 'surface', -1._real64)
        call stencil_new(op, prob, 4, 8, -1._real64)
        h   = prob%matrix()
        b32 = real(matmul(h, xt), real32)
        o%maxits = 64
        o%rtol   = STENCIL_RTOL
        x = 0._real32
        call stencil_solve(op, b32, o, x, oc)
        call assert_true(trim(oc%stop_reason) == PCG_STOP_INDEFINITE .and. oc%failure_iteration == 1 .and. &
            .not. any(abs(x) > 0._real32), 'stencil: -H stops on its first product, before the division, x untouched'//dev)
        ! n = 8 in m = 16 against the oracle's matrix-free solve
        call prob%new(8, 16, 'surface', 1._real64)
        call stencil_new(op, prob, 8, 16, 1._real64)
        b8 = prob%apply(oracle_pcg_true(8))
        b8 = real(real(b8, real32), real64)
        x8 = 0._real64
        call prob%solve(b8, x8, hist, info)
        o%maxits = 512
        y8 = 0._real32
        call stencil_solve(op, real(reshape(b8, [512]), real32), o, y8, oc)
        err = norm2(real(y8, real64) - reshape(x8, [512])) / norm2(reshape(x8, [512]))
        write(*,'(a,a,es12.5)') '    error stencil solution n=8 m=16', dev//': ', err
        call assert_true(err <= tol('stencil solution'), 'stencil: n = 8 in m = 16 matches the oracle''s matrix-free '//&
            'solve'//dev)
        call prob%kill()
    end subroutine test_stencil

end module mlxf_toy_pcg_solver_tester
