!@descr: the toy PCG engine on MLX (test only): SIMPLE's abstract operator and pcg_solve of simple_pcg_solver on device vectors with host scalars
! The device module of the engine: the half of the miniature that SIMPLE would gain beside simple_pcg_solver, whose
! host engine the toy does not model. The record pcg_solve fills, pcg_solver_outcome, is the host module's
! (mlxf_toy_pcg_solver). The operator extends device_work, so that a class can hand its operator to a caller as
! the opaque type its host files know. The client's dot returns the device half of an inner product (partial
! sums); the engine evaluates the dots of one wait together, copies them out and adds them in double, so alpha,
! beta and both stopping tests are host doubles that reach the device rounded once to float32, as SIMPLE applies
! its double scalars to single-precision vectors. The host waits once before the loop (twice from a non-zero
! start) and twice per iteration: for p . Hp, then for r . r, x . x, p . p and r . z. Where SIMPLE stops, the
! engine returns with x untouched and the reason in stop_reason.
module mlxf_toy_pcg_solver_mlx
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
use mlxf,                 only: mlx_array, mlx_eval, mlx_to, mlx_zeros_like
use mlxf_test_defs,       only: pcg_solver_options, PCG_STOP_INDEFINITE
use mlxf_toy_device_work, only: device_work
use mlxf_toy_pcg_solver,  only: pcg_solver_outcome
implicit none

public :: pcg_operator, pcg_solve
private

! the most arrays one wait evaluates: four dots and three vectors
integer, parameter :: MAX_WAIT = 7

! a client exposes its operator, preconditioner and the device half of its inner product on device vectors; kill
! releases what an extension holds (nothing here), so that a holder of the opaque type can let it go
type, abstract, extends(device_work) :: pcg_operator
  contains
    procedure(pcg_size_i),    deferred :: size
    procedure(pcg_apply_i),   deferred :: apply
    procedure(pcg_precond_i), deferred :: precond
    procedure(pcg_dot_i),     deferred :: dot
    procedure :: kill => pcg_operator_kill
end type pcg_operator

abstract interface
    integer function pcg_size_i( self ) result(n)
        import :: pcg_operator
        class(pcg_operator), intent(in) :: self
    end function pcg_size_i

    subroutine pcg_apply_i( self, x, y )
        import :: pcg_operator, mlx_array
        class(pcg_operator), intent(inout) :: self
        type(mlx_array),     intent(in)    :: x
        type(mlx_array),     intent(out)   :: y
    end subroutine pcg_apply_i

    subroutine pcg_precond_i( self, r, z )
        import :: pcg_operator, mlx_array
        class(pcg_operator), intent(inout) :: self
        type(mlx_array),     intent(in)    :: r
        type(mlx_array),     intent(out)   :: z
    end subroutine pcg_precond_i

    function pcg_dot_i( self, a, b ) result(d)
        import :: pcg_operator, mlx_array
        class(pcg_operator), intent(in) :: self
        type(mlx_array),     intent(in) :: a, b
        type(mlx_array) :: d
    end function pcg_dot_i
end interface

contains

    ! an operator without device objects of its own has nothing to release
    subroutine pcg_operator_kill( self )
        class(pcg_operator), intent(inout) :: self
    end subroutine pcg_operator_kill

    ! solves H x = b from the start in x; a refusal (sizes, options, a zero b, a non-positive first r . z) leaves x
    ! as it came and names itself in stop_reason
    subroutine pcg_solve( op, b, x, options, outcome )
        class(pcg_operator),      intent(inout) :: op
        type(mlx_array),          intent(in)    :: b
        type(mlx_array),          intent(inout) :: x
        type(pcg_solver_options), intent(in)    :: options
        type(pcg_solver_outcome), intent(out)   :: outcome
        type(mlx_array)           :: r, p, hp, z, z0, d(4), ev(MAX_WAIT)
        real(real32), allocatable :: rhist(:), xhist(:), thist(:)
        real(real64)              :: v(4), bnorm, rho, rho_new, phpv, alpha, beta, rnorm, xnorm, dxnorm, dxx, t0
        integer(int64)            :: nb, nx
        integer                   :: n, iter, n_done
        logical                   :: l_warm, last, stop_rtol, stop_xtol
        n  = op%size()
        nb = b%size()
        nx = x%size()
        outcome%requested_maxits = options%maxits
        if( n < 1 .or. nb /= int(n, int64) .or. nx /= int(n, int64) )then
            outcome%stop_reason = 'size_differs'
            return
        endif
        if( options%maxits < 1 .or. options%residual_replace < 1 .or. .not. ieee_is_finite(options%rtol) )then
            outcome%stop_reason = 'options_invalid'
            return
        endif
        if( .not. ieee_is_finite(options%xtol) )then
            outcome%stop_reason = 'options_invalid'
            return
        endif
        allocate(rhist(options%maxits), xhist(options%maxits), thist(options%maxits), source=0._real32)
        ! the first wait: |b|, |x|, and the cold start's preconditioned residual and r . z
        call op%precond(b, z0)
        d(1)  = op%dot(b, b)
        d(2)  = op%dot(x, x)
        d(3)  = op%dot(b, z0)
        ev(1) = z0
        call collect(d(1:3), ev(1:1), v(1:3))
        bnorm = sqrt(v(1))
        if( bnorm <= 0._real64 )then
            outcome%stop_reason = 'zero_rhs'
            return
        endif
        outcome%rhs_norm   = real(bnorm, real32)
        outcome%start_norm = real(sqrt(v(2)), real32)
        l_warm = outcome%start_norm > 0._real32
        outcome%initial_rel_residual = 1._real32
        rho = v(3)
        if( l_warm )then
            ! the second wait of a non-zero start: its residual and its r . z
            call op%apply(x, hp)
            r     = b - hp
            call op%precond(r, z)
            d(1)  = op%dot(r, r)
            d(2)  = op%dot(r, z)
            ev(1) = r
            ev(2) = z
            call collect(d(1:2), ev(1:2), v(1:2))
            outcome%initial_rel_residual = real(sqrt(v(1)) / bnorm, real32)
            rho = v(2)
            if( options%start_max_rel_residual >= 0._real32 .and. &
                &outcome%initial_rel_residual > options%start_max_rel_residual )then
                outcome%start_rejected       = .true.
                outcome%start_norm           = 0._real32
                outcome%initial_rel_residual = 1._real32
                l_warm = .false.
                rho    = v(3)
            endif
        endif
        if( .not. l_warm )then
            r = b
            z = z0
        endif
        if( rho <= 0._real64 )then
            outcome%stop_reason = 'nonpositive_rz'
            return
        endif
        if( outcome%start_rejected ) x = mlx_zeros_like(x)
        call z0%kill()
        outcome%stop_reason = 'maxits'
        if( .not. (options%rtol > 0._real32) ) outcome%stop_reason = 'fixed_iterations'
        p      = z
        n_done = 0
        dxx    = 0._real64
        rnorm  = bnorm * real(outcome%initial_rel_residual, real64)
        do iter = 1, options%maxits
            t0 = clock_s()
            ! the first wait of an iteration: p . Hp
            call op%apply(p, hp)
            d(1)  = op%dot(p, hp)
            ev(1) = hp
            ev(2) = p
            call collect(d(1:1), ev(1:2), v(1:1))
            phpv = v(1)
            if( .not. ieee_is_finite(phpv) .or. .not. (phpv > 0._real64) )then
                outcome%failure_curvature = phpv
                outcome%failure_iteration = iter
                outcome%stop_reason       = PCG_STOP_INDEFINITE
                outcome%converged         = .false.
                exit
            endif
            alpha = rho / phpv
            x     = x + real(alpha, real32) * p
            r     = r - real(alpha, real32) * hp
            if( modulo(iter, options%residual_replace) == 0 )then
                call op%apply(x, hp)
                r = b - hp
            endif
            n_done = iter
            last   = iter == options%maxits
            ! the second wait: r . r, x . x, p . p, and r . z unless no iteration follows
            d(1)  = op%dot(r, r)
            d(2)  = op%dot(x, x)
            d(3)  = op%dot(p, p)
            ev(1) = x
            ev(2) = r
            if( last )then
                call collect(d(1:3), ev(1:2), v(1:3))
            else
                call op%precond(r, z)
                d(4)  = op%dot(r, z)
                ev(3) = z
                call collect(d(1:4), ev(1:3), v(1:4))
            endif
            rnorm  = sqrt(v(1))
            xnorm  = sqrt(v(2))
            dxnorm = abs(alpha) * sqrt(v(3))
            dxx    = dxnorm / max(xnorm, epsilon(1._real64))
            rhist(iter) = real(rnorm / bnorm, real32)
            xhist(iter) = real(dxx, real32)
            stop_rtol   = options%rtol > 0._real32 .and. rnorm / bnorm <= real(options%rtol, real64)
            stop_xtol   = options%rtol > 0._real32 .and. dxx <= real(options%xtol, real64)
            thist(iter) = real(clock_s() - t0, real32)
            if( stop_rtol .or. stop_xtol .or. last )then
                if( stop_rtol )then
                    outcome%stop_reason = 'rtol'
                    outcome%converged   = .true.
                else if( stop_xtol )then
                    outcome%stop_reason = 'xtol'
                    outcome%converged   = .true.
                endif
                exit
            endif
            rho_new = v(4)
            beta    = rho_new / rho
            p       = z + real(beta, real32) * p
            rho     = rho_new
        end do
        outcome%iteration_count    = n_done
        outcome%final_rel_residual = real(rnorm / bnorm, real32)
        outcome%final_rel_update   = real(dxx, real32)
        outcome%rel_residual_history = rhist(1:n_done)
        outcome%rel_update_history   = xhist(1:n_done)
        outcome%iteration_seconds    = thist(1:n_done)
    end subroutine pcg_solve

    ! one host wait: evaluates the dots with the vectors that must be kept, copies each dot's partial sums out and
    ! adds them in double
    subroutine collect( dots, keep, vals )
        type(mlx_array), intent(in)  :: dots(:), keep(:)
        real(real64),    intent(out) :: vals(:)
        type(mlx_array)           :: ev(MAX_WAIT + 4)
        real(real32), allocatable :: part(:)
        integer                   :: i, k
        k = 0
        do i = 1, size(dots)
            k     = k + 1
            ev(k) = dots(i)
        end do
        do i = 1, size(keep)
            k     = k + 1
            ev(k) = keep(i)
        end do
        call mlx_eval(ev(1:k))
        do i = 1, size(dots)
            allocate(part(dots(i)%size()))
            call mlx_to(part, dots(i))
            vals(i) = sum(real(part, real64))
            deallocate(part)
        end do
    end subroutine collect

    real(real64) function clock_s()
        integer(int64) :: count, rate
        call system_clock(count, rate)
        clock_s = real(count, real64) / real(rate, real64)
    end function clock_s

end module mlxf_toy_pcg_solver_mlx
