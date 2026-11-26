!@descr: the toy reconstructor_pcg's solve gates: iterates against the oracle under rules E, F2, F5 and T, start and ship, repeatability
! The iterate after k iterations is the oracle's solve under fixed k iterations; the step quantity of iteration k
! is |x_k - x_(k-1)| / max(|x_k|, epsilon) from two of them. System R (relative ridge) runs SIMPLE's engine rules
! (E) and rule T past them; system P (SIMPLE's absolute ridge) runs SIMPLE's production, two and five iterations.
! Rule T and the residual floor reach the engine through a test operator over the toy's public procedures.
submodule (mlxf_toy_reconstructor_pcg_tester) mlxf_toy_reconstructor_pcg_tester_solve
use mlxf_test_defs,        only: PCG_LAMBDA, RECON_PCG_RTOL_T, pcg_solver_options
use mlxf_toy_pcg_solver,   only: pcg_operator, pcg_solver_outcome, pcg_solve
use mlxf_oracle_recon_pcg, only: oracle_recon_support_index, oracle_recon_symmetric_eigenvalues
use mlxf_oracle_pcg,       only: oracle_pcg_cholesky
implicit none

! SIMPLE's engine rules (E) and production's iterations (F2, F5); rule T's iterations; the residual floor's samples
real(real64), parameter :: RTOL_E   = 1.e-4_real64
real(real64), parameter :: XTOL_E   = 1.5e-2_real64
integer,      parameter :: MAXITS_E = 50
integer,      parameter :: MAXITS_F = 5
integer,      parameter :: MAXITS_T = 200
! the oracle's reasons of the rules judged here: rtol, xtol
integer,      parameter :: REASON_RTOL = 1
integer,      parameter :: REASON_XTOL = 2
! the calibration seed: its stop under rule E is reported and not gated (its margin under 5 %)
integer, parameter :: SEED_STOP_REPORTED = 1

! the toy's public operator, preconditioner and dot as the engine's client
type, extends(pcg_operator) :: test_operator
    type(reconstructor_pcg), pointer :: rec => null()
  contains
    procedure :: size    => test_size
    procedure :: apply   => test_apply
    procedure :: precond => test_precond
    procedure :: dot     => test_dot
end type test_operator

contains

    integer function test_size( self ) result(n)
        class(test_operator), intent(in) :: self
        n = self%rec%box**3
    end function test_size

    subroutine test_apply( self, x, y )
        class(test_operator), intent(inout) :: self
        type(mlx_array),      intent(in)    :: x
        type(mlx_array),      intent(out)   :: y
        y = self%rec%apply_normal(x)
    end subroutine test_apply

    subroutine test_precond( self, r, z )
        class(test_operator), intent(inout) :: self
        type(mlx_array),      intent(in)    :: r
        type(mlx_array),      intent(out)   :: z
        z = self%rec%apply_precond(r)
    end subroutine test_precond

    function test_dot( self, a, b ) result(d)
        class(test_operator), intent(in) :: self
        type(mlx_array),      intent(in) :: a, b
        type(mlx_array) :: d
        d = self%rec%dot_real_volume(a, b)
    end function test_dot

    ! the oracle's iterates u(:, k), k = 0 .. kmax, of fixed solves from zero, and their step quantities
    subroutine oracle_iterates( prob, b, kmax, u, step )
        type(oracle_recon_problem), intent(inout) :: prob
        real(real64),               intent(in)    :: b(:)
        integer,                    intent(in)    :: kmax
        real(real64), allocatable,  intent(out)   :: u(:,:), step(:)
        real(real64), allocatable :: h(:)
        integer                   :: k, info(2)
        allocate(u(size(b), 0:kmax), step(kmax))
        u = 0._real64
        do k = 1, kmax
            call prob%set_rules(0._real64, 0._real64, k)
            call prob%solve(b, u(:, k), h, info)
            step(k) = norm2(u(:, k) - u(:, k-1)) / max(norm2(u(:, k)), epsilon(1._real64))
        end do
    end subroutine oracle_iterates

    ! the toy's shipped map after k fixed iterations from x0 (a shipped map)
    subroutine toy_iterate( rec, x0, k, x, outcome )
        type(reconstructor_pcg),  intent(inout) :: rec
        real(real32),             intent(in)    :: x0(:,:,:)
        integer,                  intent(in)    :: k
        real(real32),             intent(out)   :: x(:,:,:)
        type(pcg_solver_outcome), intent(out)   :: outcome
        x = x0
        call rec%solve_accum(x, maxits=k, rtol=0._real32, outcome=outcome)
    end subroutine toy_iterate

    ! the system P of a fixture: SIMPLE's absolute ridge, the same support and accumulators
    subroutine assemble_production( fx, rec )
        type(recon_fixture),     intent(in)    :: fx
        type(reconstructor_pcg), intent(inout) :: rec
        call rec%new(fx%n, lambda=PCG_LAMBDA)
        call rec%set_window_sphere(real(fx%mskrad, real32))
        call rec%set_raw_accum(fx%b32, fx%d32)
        call rec%end_accum(.true.)
    end subroutine assemble_production

    ! the iterates of k = 1 .. kmax against the oracle's shipped ones, the largest relative error
    real(real64) function iterate_error( rec, prob, u, kmax, n ) result(e)
        type(reconstructor_pcg),    intent(inout) :: rec
        type(oracle_recon_problem), intent(in)    :: prob
        real(real64),               intent(in)    :: u(:, 0:)
        integer,                    intent(in)    :: kmax, n
        type(pcg_solver_outcome) :: oc
        real(real32)             :: x(n, n, n), z(n, n, n)
        integer                  :: k
        z = 0._real32
        e = 0._real64
        do k = 1, kmax
            call toy_iterate(rec, z, k, x, oc)
            e = max(e, rel2(real(reshape(x, [n**3]), real64), prob%ship(u(:, k))))
        end do
    end function iterate_error

    ! the residual and step histories of a toy outcome against the oracle's, the largest absolute differences
    ! (residual, step)
    function history_errors( oc, hist, step, kmax ) result(e)
        type(pcg_solver_outcome), intent(in) :: oc
        real(real64),             intent(in) :: hist(0:), step(:)
        integer,                  intent(in) :: kmax
        real(real64) :: e(2)
        integer      :: k
        e = huge(1._real64)
        if( .not. allocated(oc%rel_residual_history) ) return
        if( size(oc%rel_residual_history) < kmax ) return
        e = 0._real64
        do k = 1, kmax
            e(1) = max(e(1), abs(real(oc%rel_residual_history(k), real64) - hist(k)))
            e(2) = max(e(2), abs(real(oc%rel_update_history(k), real64) - step(k)))
        end do
    end function history_errors

    ! the small fixture on one device: O9; gate (a) under rule E on system R (the stop iteration and reason, every
    ! iterate, residual and step); gate (a') under F2 and F5 on system P; start and ship; gate (b) under rule T, or
    ! while rule T's tolerance is unmeasured, the lowest true residual of 200 iterations
    module subroutine test_solve_small( fx )
        type(recon_fixture), intent(in) :: fx
        type(reconstructor_pcg), target :: rec
        type(oracle_recon_problem)      :: probr, probp
        type(pcg_solver_outcome)        :: oc
        real(real64), allocatable       :: b(:), u(:,:), step(:), hist(:), hist_e(:), x0(:)
        real(real32), allocatable       :: x(:,:,:), z(:,:,:), xs(:,:,:), bt(:,:,:), env(:,:,:), invenv(:,:,:)
        real(real64)                    :: e, eres, estep, eh(2)
        integer                         :: n, info(2), kstop
        n = fx%n
        write(*,'(a,i0,a,a)') 'test_solve_small seed=', fx%seed, ' ', device_name_now()
        allocate(x(n, n, n), z(n, n, n), xs(n, n, n), bt(n, n, n), env(n, n, n), invenv(n, n, n))
        z = 0._real32
        call probr%new(fx%d64, fx%mskrad, real(RECON_PCG_LAMBDA_REL, real64), .true.)
        call probp%new(fx%d64, fx%mskrad, real(PCG_LAMBDA, real64), .false.)
        b = probr%rhs(fx%b64)
        ! gate (a): rule E on system R
        x0 = 0._real64 * b
        call probr%set_rules(RTOL_E, XTOL_E, MAXITS_E)
        call probr%solve(b, x0, hist_e, info)
        kstop = info(1)
        call oracle_iterates(probr, b, kstop, u, step)
        call assemble(fx, rec)
        x = 0._real32
        call rec%solve_accum(x, maxits=MAXITS_E, rtol=real(RTOL_E, real32), outcome=oc)
        write(*,'(a,i0,a,a,a,i0,a,i0)') '    rule E seed=', fx%seed, ': toy ', trim(oc%stop_reason), ' at ', &
            oc%iteration_count, ', oracle reason ', info(2)
        if( fx%seed /= SEED_STOP_REPORTED )then
            call assert_true(oc%iteration_count == kstop, '(a): the device stops at the oracle''s iteration under rule E')
            call assert_true((trim(oc%stop_reason) == 'xtol' .and. info(2) == REASON_XTOL) .or. &
                (trim(oc%stop_reason) == 'rtol' .and. info(2) == REASON_RTOL), '(a): the device stops by the oracle''s test')
        endif
        eh    = history_errors(oc, hist_e, step, min(kstop, oc%iteration_count))
        eres  = eh(1)
        estep = eh(2)
        call report('residual history E', fx, eres, tol('residual history'))
        call assert_true(eres <= tol('residual history'), '(a): the residual history agrees with the oracle''s (rule E)')
        call report('step E', fx, estep, tol('step'))
        call assert_true(estep <= tol('step'), '(a): the step quantities agree with the oracle''s (rule E)')
        e = iterate_error(rec, probr, u, kstop, n)
        call report('iterate E', fx, e, tol('iterate'))
        call assert_true(e <= tol('iterate'), '(a): every iterate up to the stop agrees with the oracle''s (rule E)')
        ! O9: the device half of the inner product finished in double
        e = dot_error(rec, n)
        call report('dot', fx, e, tol('dot'))
        call assert_true(e <= tol('dot'), 'O9: dot_real_volume finished in double matches the host''s double sum')
        ! start and ship: a shipped map as the start, two iterations, the map shipped
        call rec%copy_volumes(bt, env, invenv)
        xs = fixed_volume(n, 4) * rec%window
        call toy_iterate(rec, xs, 2, x, oc)
        x0 = probr%start(real(reshape(xs, [n**3]), real64))
        call probr%set_rules(0._real64, 0._real64, 2)
        call probr%solve(b, x0, hist, info)
        e = rel2(real(reshape(x, [n**3]), real64), probr%ship(x0))
        call report('start and ship', fx, e, tol('iterate'))
        call assert_true(e <= tol('iterate'), 'start and ship: a shipped start is divided by the window and the map '//&
            'shipped with the window once, as the oracle''s')
        call rule_t(fx, rec, probr, bt)
        call rec%kill()
        ! gate (a'): system P under F2 and F5, iterates k = 1 .. 5
        call oracle_iterates(probp, b, MAXITS_F, u, step)
        x0 = 0._real64 * b
        call probp%set_rules(0._real64, 0._real64, MAXITS_F)
        call probp%solve(b, x0, hist, info)
        call assemble_production(fx, rec)
        call toy_iterate(rec, z, MAXITS_F, x, oc)
        call assert_true(trim(oc%stop_reason) == 'fixed_iterations' .and. oc%iteration_count == MAXITS_F, &
            '(a''): F5 runs exactly five iterations')
        eh   = history_errors(oc, hist, step, MAXITS_F)
        eres = eh(1)
        call report('residual history F5', fx, eres, tol('residual history'))
        call assert_true(eres <= tol('residual history'), '(a''): the residual history agrees with the oracle''s (F5)')
        e = iterate_error(rec, probp, u, MAXITS_F, n)
        call report('iterate F5', fx, e, tol('iterate'))
        call assert_true(e <= tol('iterate'), '(a''): iterates 1 to 5 agree with the oracle''s on system P')
        call toy_iterate(rec, z, 2, x, oc)
        call assert_true(trim(oc%stop_reason) == 'fixed_iterations' .and. oc%iteration_count == 2, &
            '(a''): F2 runs exactly two iterations')
        call rec%kill()
        call probr%kill()
        call probp%kill()
    end subroutine test_solve_small

    ! O9: dot_real_volume of two fixed vectors, its partial sums added in double, against the host's double sum
    real(real64) function dot_error( rec, n ) result(e)
        type(reconstructor_pcg), intent(inout) :: rec
        integer,                 intent(in)    :: n
        type(mlx_array) :: ud, vd, d
        real(real32)    :: u(n, n, n), v(n, n, n), part(n * n)
        real(real64)    :: ref, val
        u   = fixed_volume(n, 5)
        v   = fixed_volume(n, 6)
        ud  = mlx_from(u)
        vd  = mlx_from(v)
        d   = rec%dot_real_volume(ud, vd)
        call mlx_to(part, d)
        val = sum(real(part, real64))
        ref = sum(real(u, real64) * real(v, real64))
        e   = abs(val - ref) / abs(ref)
    end function dot_error

    ! the device's iterate u (not shipped) after a solve of the test operator from zero under the given rules
    subroutine engine_solve( rec, bt, opts, u, outcome )
        type(reconstructor_pcg), target, intent(inout) :: rec
        real(real32),                    intent(in)    :: bt(:,:,:)
        type(pcg_solver_options),        intent(in)    :: opts
        real(real64),                    intent(out)   :: u(:)
        type(pcg_solver_outcome),        intent(out)   :: outcome
        type(test_operator) :: op
        type(mlx_array)     :: bd, xd
        real(real32)        :: y(size(u))
        op%rec => rec
        bd = mlx_from(bt)
        xd = mlx_from(0._real32 * bt)
        call pcg_solve(op, bd, xd, opts, outcome)
        call mlx_to(y, xd)
        u = real(y, real64)
    end subroutine engine_solve

    ! the true residual of the device's u against the device's own right-hand side, by the explicit matrix
    real(real64) function true_residual( hd, bv, u ) result(r)
        real(real64), intent(in) :: hd(:,:), bv(:), u(:)
        r = norm2(bv - matmul(hd, u)) / norm2(bv)
    end function true_residual

    ! the explicit operator of system R with the oracle's dense matrices
    subroutine dense_operator( prob, fx, hd )
        type(oracle_recon_problem), intent(in)  :: prob
        type(recon_fixture),        intent(in)  :: fx
        real(real64), allocatable,  intent(out) :: hd(:,:)
        real(real64), allocatable :: pd(:,:)
        integer                   :: n
        n = fx%n
        allocate(hd(n**3, n**3), pd(n**3, n**3))
        call oracle_recon_dense_matrices(prob%kernel(), oracle_recon_reference_spectrum(fx%d64, n), prob%ridge(), hd, pd)
    end subroutine dense_operator

    ! gate (b): rule T on system R (no step test, at most 200 iterations; with rtol_t unfrozen exactly 200): the true
    ! residual by the explicit matrix against the device's own right-hand side, the reported residual's distance from
    ! it, the solution's from Cholesky on the support block; gated only once rtol_t is frozen, reported until then
    subroutine rule_t( fx, rec, prob, bt )
        type(recon_fixture),        intent(in)    :: fx
        type(reconstructor_pcg),    intent(inout) :: rec
        type(oracle_recon_problem), intent(in)    :: prob
        real(real32),               intent(in)    :: bt(:,:,:)
        type(pcg_solver_options)  :: opts
        type(pcg_solver_outcome)  :: oc
        real(real64), allocatable :: hd(:,:), u(:), bv(:), hs(:,:), xs(:), ev(:)
        integer,      allocatable :: idx(:)
        real(real64)              :: r, minpivot, erep, esol, cond
        call dense_operator(prob, fx, hd)
        bv = real(reshape(bt, [size(bt)]), real64)
        allocate(u(size(bv)))
        opts%maxits = MAXITS_T
        opts%rtol   = real(RECON_PCG_RTOL_T, real32)
        opts%xtol   = 0._real32
        call engine_solve(rec, bt, opts, u, oc)
        r    = true_residual(hd, bv, u)
        erep = abs(real(oc%final_rel_residual, real64) - r)
        idx  = oracle_recon_support_index(fx%n)
        hs   = hd(idx, idx)
        allocate(xs(size(idx)))
        call oracle_pcg_cholesky(hs, bv(idx), xs, minpivot)
        ev   = oracle_recon_symmetric_eigenvalues(hs)
        cond = maxval(ev) / minval(ev)
        esol = norm2(u(idx) - xs) / norm2(xs)
        write(*,'(a,i0,a,a,a,a,a,i0,a,es12.5,a,es12.5,a,es12.5,a,es10.3)') '    rule T seed=', fx%seed, ' ', &
            device_name_now(), ': ', trim(oc%stop_reason), ' at ', oc%iteration_count, ', true residual ', r, &
            ', |reported - true| ', erep, ', solution against Cholesky ', esol, ', cond ', cond
        if( .not. (RECON_PCG_RTOL_T > 0._real64) ) return
        call assert_true(trim(oc%stop_reason) == 'rtol' .and. r <= RECON_PCG_RTOL_T, &
            '(b): rule T stops on rtol with a true residual of at most rtol_t')
        call assert_true(erep <= 0.1_real64 * RECON_PCG_RTOL_T, '(b): the reported residual agrees with the true one')
        call assert_true(esol <= min(1.e-3_real64, 10._real64 * RECON_PCG_RTOL_T * cond), &
            '(b): the solution agrees with Cholesky on the support block')
    end subroutine rule_t

    ! decision 17's fast form: the assembly under rule E three times from new to kill on one device, the map and
    ! both histories bit for bit, the count and the reason equal
    module subroutine test_repeatability( fx )
        type(recon_fixture), intent(in) :: fx
        type(reconstructor_pcg)   :: rec
        type(pcg_solver_outcome)  :: oc, oc1
        real(real32), allocatable :: x(:,:,:), x1(:,:,:)
        integer                   :: rep
        logical                   :: same
        write(*,'(a,a)') 'test_repeatability ', device_name_now()
        allocate(x(fx%n, fx%n, fx%n))
        same = .true.
        do rep = 1, 3
            call assemble(fx, rec)
            x = 0._real32
            call rec%solve_accum(x, maxits=MAXITS_E, rtol=real(RTOL_E, real32), outcome=oc)
            call rec%kill()
            if( rep == 1 )then
                x1  = x
                oc1 = oc
                cycle
            endif
            same = same .and. all(bits_equal(x, x1)) .and. oc%iteration_count == oc1%iteration_count .and. &
                   trim(oc%stop_reason) == trim(oc1%stop_reason)
            if( same ) same = all(bits_equal(oc%rel_residual_history, oc1%rel_residual_history)) .and. &
                              all(bits_equal(oc%rel_update_history, oc1%rel_update_history))
        end do
        call assert_true(same, 'decision 17: three assemblies under rule E give the map, the residual and update '//&
            'histories bit for bit, the same count and reason')
    end subroutine test_repeatability

    ! the named-only fixture: gate (a) under rule E at k = 1, 2, 5 and the stop, the final true residual by the
    ! oracle's apply; gate (a') on system P, k = 1 .. 5
    module subroutine test_solve_n32( fx )
        type(recon_fixture), intent(in) :: fx
        type(reconstructor_pcg), target :: rec
        type(oracle_recon_problem)      :: probr, probp
        type(pcg_solver_outcome)        :: oc
        type(pcg_solver_options)        :: opts
        real(real64), allocatable       :: b(:), xo(:), hist_e(:), hist(:), u(:), hu(:), up(:,:), step(:)
        real(real32), allocatable       :: x(:,:,:), z(:,:,:), bt(:,:,:), env(:,:,:), invenv(:,:,:)
        real(real64)                    :: e, ek, eres, eh(2), r
        integer                         :: n, info(2), kstop, ks(4), i
        n = fx%n
        write(*,'(a,i0,a,a)') 'test_solve_n32 seed=', fx%seed, ' ', device_name_now()
        allocate(x(n, n, n), z(n, n, n), bt(n, n, n), env(n, n, n), invenv(n, n, n), hu(n**3))
        z = 0._real32
        call probr%new(fx%d64, fx%mskrad, real(RECON_PCG_LAMBDA_REL, real64), .true.)
        b  = probr%rhs(fx%b64)
        xo = 0._real64 * b
        call probr%set_rules(RTOL_E, XTOL_E, MAXITS_E)
        call probr%solve(b, xo, hist_e, info)
        kstop = info(1)
        call assemble(fx, rec)
        x = 0._real32
        call rec%solve_accum(x, maxits=MAXITS_E, rtol=real(RTOL_E, real32), outcome=oc)
        write(*,'(a,i0,a,a,a,i0,a,i0,a,i0)') '    rule E n=32 seed=', fx%seed, ': toy ', trim(oc%stop_reason), ' at ', &
            oc%iteration_count, ', oracle reason ', info(2), ' at ', kstop
        call assert_true(oc%iteration_count == kstop, '(a): at n = 32 the device stops at the oracle''s iteration')
        call assert_true((trim(oc%stop_reason) == 'xtol' .and. info(2) == REASON_XTOL) .or. &
            (trim(oc%stop_reason) == 'rtol' .and. info(2) == REASON_RTOL), '(a): at n = 32 the device stops by the '//&
            'oracle''s test')
        e = 0._real64
        do i = 1, min(oc%iteration_count, kstop)
            e = max(e, abs(real(oc%rel_residual_history(i), real64) - hist_e(i+1)))
        end do
        call report('residual history E', fx, e, tol('residual history'))
        call assert_true(e <= tol('residual history'), '(a): at n = 32 the residual history agrees with the oracle''s')
        ks = [1, 2, 5, kstop]
        e  = 0._real64
        do i = 1, 4
            call toy_iterate(rec, z, ks(i), x, oc)
            xo = 0._real64 * b
            call probr%set_rules(0._real64, 0._real64, ks(i))
            call probr%solve(b, xo, hist, info)
            ek = rel2(real(reshape(x, [n**3]), real64), probr%ship(xo))
            if( i < 4 ) e = max(e, ek)
        end do
        call report('iterate E k=1,2,5', fx, e, tol('iterate'))
        call assert_true(e <= tol('iterate'), '(a): at n = 32 the iterates 1, 2 and 5 agree with the oracle''s')
        call report('iterate E at the stop (reported)', fx, ek, tol('iterate'))
        ! the final true residual by the oracle's apply, against the device's own right-hand side
        call rec%copy_volumes(bt, env, invenv)
        allocate(u(n**3))
        opts%maxits = kstop
        opts%rtol   = 0._real32
        call engine_solve(rec, bt, opts, u, oc)
        call probr%apply(u, hu)
        r = norm2(real(reshape(bt, [n**3]), real64) - hu) / norm2(real(reshape(bt, [n**3]), real64))
        e = abs(real(oc%final_rel_residual, real64) - r)
        write(*,'(a,es12.5,a,es12.5)') '    n=32 final true residual by the oracle''s apply ', r, ', reported ', &
            oc%final_rel_residual
        call assert_true(e <= tol('residual history'), '(a): at n = 32 the reported residual is the true one by the '//&
            'oracle''s apply')
        call rec%kill()
        ! gate (a') on system P
        call probp%new(fx%d64, fx%mskrad, real(PCG_LAMBDA, real64), .false.)
        call oracle_iterates(probp, b, MAXITS_F, up, step)
        xo = 0._real64 * b
        call probp%set_rules(0._real64, 0._real64, MAXITS_F)
        call probp%solve(b, xo, hist, info)
        call assemble_production(fx, rec)
        call toy_iterate(rec, z, MAXITS_F, x, oc)
        eh   = history_errors(oc, hist, step, MAXITS_F)
        eres = eh(1)
        call report('residual history F5', fx, eres, tol('residual history'))
        call assert_true(eres <= tol('residual history'), '(a''): at n = 32 the residual history agrees (F5)')
        e = iterate_error(rec, probp, up, MAXITS_F, n)
        call report('iterate F5', fx, e, tol('iterate'))
        call assert_true(e <= tol('iterate'), '(a''): at n = 32 iterates 1 to 5 agree with the oracle''s on system P')
        call rec%kill()
        call probr%kill()
        call probp%kill()
    end subroutine test_solve_n32

end submodule mlxf_toy_reconstructor_pcg_tester_solve
