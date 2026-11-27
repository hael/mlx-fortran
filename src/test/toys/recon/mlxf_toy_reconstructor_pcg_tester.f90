!@descr: tests of the toy reconstructor_pcg: the operator, preconditioner, kernel and right-hand side against the host oracle
! SIMPLE's assembly (new, set_window_sphere, set_lambda_relative, set_raw_accum, end_accum) on the full-coverage
! fixture of mlxf_oracle_recon_fixture, held to mlxf_oracle_recon_pcg in double precision, which is given the
! accumulators the toy receives (rounded once to float32) widened. The small fixture (n = 8, 4 n planes) runs on
! both devices against explicit matrices; the named-only one (n = 32) against the oracle's matrix-free products.
! Each inexact gate has a tolerance in RECON_PCG_TOLERANCES: while it is not frozen, only seed 1 runs, against the
! ceiling, and the errors printed are its calibration.
module mlxf_toy_reconstructor_pcg_tester
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,                       only: mlx_array, mlx_from, mlx_to, mlx_eval, mlx_set_default_device, mlx_live_count, &
                                      mlx_active_memory, mlx_synchronize
use mlxf_test_defs,             only: RECON_PCG_N_SMALL, RECON_PCG_N_NAMED, RECON_PCG_MSKRAD_SMALL, &
                                      RECON_PCG_MSKRAD_NAMED, RECON_PCG_PLANES_PER_N, RECON_PCG_LAMBDA_REL, &
                                      RECON_PCG_TOLERANCES, parameters
use mlxf_toy_reconstructor_pcg, only: reconstructor_pcg
use mlxf_oracle_recon_fixture,  only: oracle_recon_fixture_accum
use mlxf_oracle_recon_pcg,      only: oracle_recon_problem, oracle_recon_dense_matrices, &
                                      oracle_recon_reference_spectrum
use mlxf_oracle_gridding,       only: oracle_grid_envelope, oracle_grid_reciprocal
use mlxf_test_utils,            only: assert_true, device_name, test_devices, family_seeds, seeded_uniform, bits_equal
use mlxf_test_reduce,           only: nan_maxval, nan_max
implicit none
private
public :: run_all_reconstructor_pcg_tests, run_all_reconstructor_pcg_n32_tests

! the unit vectors of the explicit operator built before one evaluation; the lifecycle's cycles; the fixed vectors
! of the named-only fixture
integer, parameter :: NCOLS    = 64
integer, parameter :: NCYCLES  = 100
integer, parameter :: NVEC_N32 = 8
! the gates of the operator, and those of the solve, in RECON_PCG_TOLERANCES
integer, parameter :: NOP_GATES   = 9
integer, parameter :: SOLVE_FIRST = 10
integer, parameter :: SOLVE_LAST  = 16

! one fixture of a box and seed: the toy's accumulators (float32) and the oracle's (the same values widened)
type :: recon_fixture
    integer                      :: n    = 0
    integer                      :: seed = 0
    real(real64)                 :: mskrad = 0._real64
    complex(real32), allocatable :: b32(:,:,:)
    real(real32),    allocatable :: d32(:,:,:)
    complex(real64), allocatable :: b64(:,:,:)
    real(real64),    allocatable :: d64(:,:,:)
end type recon_fixture

interface
    ! the solve's gates on the small fixture (one device, one seed) and on the named-only one, the
    ! repeatability of the assembly under rule E (one device) and the history comparator's negative controls
    module subroutine test_solve_small( fx )
        type(recon_fixture), intent(in) :: fx
    end subroutine test_solve_small

    module subroutine test_solve_n32( fx )
        type(recon_fixture), intent(in) :: fx
    end subroutine test_solve_n32

    module subroutine test_repeatability( fx )
        type(recon_fixture), intent(in) :: fx
    end subroutine test_repeatability

    module subroutine test_history_controls( fx )
        type(recon_fixture), intent(in) :: fx
    end subroutine test_history_controls

    module function tol( name ) result(t)
        character(len=*), intent(in) :: name
        real(real64) :: t
    end function tol

    module subroutine make_fixture( n, mskrad, seed, fx )
        integer,             intent(in)    :: n, seed
        real(real64),        intent(in)    :: mskrad
        type(recon_fixture), intent(inout) :: fx
    end subroutine make_fixture

    module subroutine assemble( fx, rec )
        type(recon_fixture),     intent(in)    :: fx
        type(reconstructor_pcg), intent(inout) :: rec
    end subroutine assemble

    module function fixed_volume( n, k ) result(v)
        integer, intent(in) :: n, k
        real(real32) :: v(n, n, n)
    end function fixed_volume

    module function rel2( a, ref ) result(e)
        real(real64), intent(in) :: a(:), ref(:)
        real(real64) :: e
    end function rel2

    module subroutine report( label, fx, err, limit )
        character(len=*),    intent(in) :: label
        type(recon_fixture), intent(in) :: fx
        real(real64),        intent(in) :: err, limit
    end subroutine report

    module function device_name_now() result(name)
        character(len=:), allocatable :: name
    end function device_name_now

    ! the device forms of the operator, by the operator the reconstructor hands out (get_pcg_operator): the
    ! product H x (P H P with a support), the preconditioner's product and the device half of the inner product
    ! (the partial sums of the lines), each on device vectors and unevaluated
    module function device_apply( rec, x ) result(y)
        type(reconstructor_pcg), target, intent(inout) :: rec
        type(mlx_array),                 intent(in)    :: x
        type(mlx_array) :: y
    end function device_apply

    module function device_precond( rec, r ) result(z)
        type(reconstructor_pcg), target, intent(inout) :: rec
        type(mlx_array),                 intent(in)    :: r
        type(mlx_array) :: z
    end function device_precond

    module function device_dot( rec, a, b ) result(d)
        type(reconstructor_pcg), target, intent(inout) :: rec
        type(mlx_array),                 intent(in)    :: a, b
        type(mlx_array) :: d
    end function device_dot
end interface

contains

    subroutine run_all_reconstructor_pcg_tests
        integer, allocatable :: devs(:), seeds(:)
        type(recon_fixture)  :: fx
        integer              :: is, id
        write(*,'(a)') '**** running all reconstructor_pcg tests ****'
        call test_devices(devs)
        seeds = family_seeds()
        do is = 1, size(seeds)
            call make_fixture(RECON_PCG_N_SMALL, RECON_PCG_MSKRAD_SMALL, seeds(is), fx)
            do id = 1, size(devs)
                call mlx_set_default_device(devs(id))
                if( any(judged_seeds(1, NOP_GATES) == seeds(is)) ) call test_operator_small(fx)
                if( any(judged_seeds(SOLVE_FIRST, SOLVE_LAST) == seeds(is)) ) call test_solve_small(fx)
            end do
        end do
        do id = 1, size(devs)
            call mlx_set_default_device(devs(id))
            call test_lifecycle(fx)
            call test_repeatability(fx)
            call test_history_controls(fx)
            call test_host_forms(fx)
        end do
    end subroutine run_all_reconstructor_pcg_tests

    ! the named-only fixture: n = 32 against the oracle's matrix-free products, on every device
    subroutine run_all_reconstructor_pcg_n32_tests
        integer, allocatable :: devs(:), seeds(:)
        type(recon_fixture)  :: fx
        integer              :: is, id
        write(*,'(a)') '**** running all reconstructor_pcg_n32 tests ****'
        call test_devices(devs)
        seeds = family_seeds()
        do is = 1, size(seeds)
            call make_fixture(RECON_PCG_N_NAMED, RECON_PCG_MSKRAD_NAMED, seeds(is), fx)
            do id = 1, size(devs)
                call mlx_set_default_device(devs(id))
                if( any(judged_seeds(1, NOP_GATES) == seeds(is)) ) call test_operator_n32(fx)
                if( any(judged_seeds(SOLVE_FIRST, SOLVE_LAST) == seeds(is)) ) call test_solve_n32(fx)
            end do
        end do
    end subroutine run_all_reconstructor_pcg_n32_tests

    ! ---- fixtures and helpers ------------------------------------------------------------------------------

    ! the seeds a group of gates judges: all three once their tolerances are frozen, else the calibration seed
    function judged_seeds( first, last ) result(seeds)
        integer, intent(in) :: first, last
        integer, allocatable :: seeds(:)
        seeds = family_seeds()
        if( any(.not. (RECON_PCG_TOLERANCES(first:last)%frozen > 0._real64)) ) seeds = seeds(1:1)
    end function judged_seeds

    ! the fixture of box n and seed: 4 n planes from the seed's variates, the accumulators rounded once
    module subroutine make_fixture( n, mskrad, seed, fx )
        integer,             intent(in)    :: n, seed
        real(real64),        intent(in)    :: mskrad
        type(recon_fixture), intent(inout) :: fx
        real(real64), allocatable :: u(:)
        if( allocated(fx%b32) ) deallocate(fx%b32, fx%d32, fx%b64, fx%d64)
        fx%n      = n
        fx%seed   = seed
        fx%mskrad = mskrad
        allocate(fx%b64(n+1, 2*n, 2*n), fx%d64(n+1, 2*n, 2*n))
        u = seeded_uniform(3 * RECON_PCG_PLANES_PER_N * n + 3, seed)
        call oracle_recon_fixture_accum(n, u, fx%b64, fx%d64)
        fx%b32 = cmplx(real(fx%b64, real32), real(aimag(fx%b64), real32), real32)
        fx%d32 = real(fx%d64, real32)
        fx%b64 = cmplx(real(real(fx%b32), real64), real(aimag(fx%b32), real64), real64)
        fx%d64 = real(fx%d32, real64)
    end subroutine make_fixture

    ! the columns of a device operator on the n-cube, one unit vector each, NCOLS built before one evaluation
    subroutine device_columns( rec, n, which, cols )
        type(reconstructor_pcg), intent(inout) :: rec
        integer,                 intent(in)    :: n
        character(len=*),        intent(in)    :: which
        real(real64),            intent(out)   :: cols(:,:)
        type(mlx_array)           :: e, outs(NCOLS)
        real(real32)              :: v(n, n, n), y(n**3)
        integer                   :: j0, j, nb
        do j0 = 1, n**3, NCOLS
            nb = min(NCOLS, n**3 - j0 + 1)
            do j = 1, nb
                v = 0._real32
                v(modulo(j0 + j - 2, n) + 1, modulo((j0 + j - 2) / n, n) + 1, (j0 + j - 2) / n**2 + 1) = 1._real32
                e = mlx_from(v)
                if( which == 'operator' )then
                    outs(j) = device_apply(rec, e)
                else
                    outs(j) = device_precond(rec, e)
                endif
            end do
            call mlx_eval(outs(1:nb))
            do j = 1, nb
                call mlx_to(y, outs(j))
                cols(:, j0 + j - 1) = real(y, real64)
            end do
        end do
    end subroutine device_columns

    ! ---- the small fixture ---------------------------------------------------------------------------------

    ! O1 to O8 on one device: the mask, window and envelopes; the kernel, the spectrum and its zeros, the ridge, the
    ! right-hand side; the operator and the preconditioner against their explicit matrices with the zeros outside
    ! the mask; symmetry on fixed vectors
    subroutine test_operator_small( fx )
        type(recon_fixture), intent(in) :: fx
        type(reconstructor_pcg)    :: rec
        type(oracle_recon_problem) :: prob
        real(real32), allocatable  :: supp(:,:,:), khat(:,:,:), pre(:,:,:), b(:,:,:), env(:,:,:), invenv(:,:,:)
        real(real64), allocatable  :: hd(:,:), pd(:,:), hc(:,:), pc(:,:), kref(:,:,:), pref(:,:,:), eref(:,:,:), &
                                      pmask(:), bref(:)
        real(real64)               :: err, sym, e1(fx%n)
        integer                    :: n, m, i, i1, i2, i3, nbad
        logical,      allocatable  :: inside(:)
        n = fx%n
        m = 2 * n
        write(*,'(a,i0,a,a)') 'test_operator_small seed=', fx%seed, ' ', device_name_now()
        call prob%new(fx%d64, fx%mskrad, real(RECON_PCG_LAMBDA_REL, real64), .true.)
        call assemble(fx, rec)
        call assert_true(len(rec%message()) == 0, 'reconstructor_pcg: the small fixture assembles: '//rec%message())
        ! O1: the mask exactly, the window, the envelope and its reciprocal
        call rec%get_solve_support(supp)
        call assert_true(all(bits_equal(real(supp, real64), prob%support())), &
            'O1: the support equals the oracle''s (window > 0) voxel for voxel')
        err = nan_maxval(abs(real(rec%window, real64) - prob%window()))
        call report('window', fx, err, tol('window'))
        call assert_true(err <= tol('window'), 'O1: the soft window matches the oracle''s')
        allocate(khat(n+1, m, m), pre(n+1, m, m), b(n, n, n), env(n, n, n), invenv(n, n, n), eref(n, n, n))
        call rec%copy_spectra(khat, pre)
        call rec%copy_volumes(b, env, invenv)
        e1 = oracle_grid_envelope([(i - 1 - n / 2, i=1, n)], m)
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    eref(i1, i2, i3) = e1(i1) * e1(i2) * e1(i3)
                end do
            end do
        end do
        err = nan_max(nan_maxval(abs(real(env, real64) - eref)), nan_maxval(abs(real(invenv, real64) - &
                  oracle_grid_reciprocal(eref))))
        call report('envelope', fx, err, tol('envelope'))
        call assert_true(err <= tol('envelope'), 'O1: the envelope and its reciprocal match the oracle''s')
        ! O2: the kernel spectrum, relative to its largest value
        kref = prob%kernel()
        err  = nan_maxval(abs(real(khat, real64) - kref(1:n+1, :, :))) / nan_maxval(abs(kref(1:n+1, :, :)))
        call report('kernel', fx, err, tol('kernel'))
        call assert_true(err <= tol('kernel'), 'O2: the kernel spectrum matches the oracle''s')
        ! O3: the preconditioner's spectrum, its zeros exactly, its other entries relative
        pref = prob%spectrum()
        call assert_true(all((abs(pre) > 0._real32) .eqv. (abs(pref(1:n+1, :, :)) > 0._real64)), &
            'O3: the preconditioner''s spectrum is zero exactly where the oracle''s is')
        err = nan_maxval(merge(abs(real(pre, real64) - pref(1:n+1, :, :)) / max(abs(pref(1:n+1, :, :)), tiny(1._real64)), &
                               0._real64, abs(pref(1:n+1, :, :)) > 0._real64))
        call report('spectrum', fx, err, tol('spectrum'))
        call assert_true(err <= tol('spectrum'), 'O3: the preconditioner''s spectrum matches the oracle''s')
        ! O4: the relative ridge
        err = abs(real(rec%get_effective_lambda(), real64) - prob%ridge()) / prob%ridge()
        call report('ridge', fx, err, tol('ridge'))
        call assert_true(err <= tol('ridge'), 'O4: the relative ridge matches the oracle''s')
        ! O5: the right-hand side
        bref = prob%rhs(fx%b64)
        err  = rel2(real(reshape(b, [n**3]), real64), bref)
        call report('rhs', fx, err, tol('rhs'))
        call assert_true(err <= tol('rhs'), 'O5: the right-hand side matches the oracle''s')
        ! O6 and O8: the explicit matrices, columns of unit vectors
        allocate(hd(n**3, n**3), pd(n**3, n**3), hc(n**3, n**3), pc(n**3, n**3))
        call oracle_recon_dense_matrices(kref, oracle_recon_reference_spectrum(fx%d64, n), prob%ridge(), hd, pd)
        call device_columns(rec, n, 'operator', hc)
        call device_columns(rec, n, 'precond', pc)
        err = rel2(reshape(hc, [n**6]), reshape(hd, [n**6]))
        call report('operator', fx, err, tol('operator'))
        call assert_true(err <= tol('operator'), 'O6: the operator matches the explicit matrix P (K + lambda I) P')
        pmask  = reshape(prob%support(), [n**3])
        inside = pmask > 0._real64
        nbad   = 0
        do i = 1, n**3
            if( .not. inside(i) )then
                if( any(abs(hc(i, :)) > 0._real64) ) nbad = nbad + 1
                if( any(abs(hc(:, i)) > 0._real64) ) nbad = nbad + 1
            endif
        end do
        call assert_true(nbad == 0, 'O6: the operator''s rows and columns outside the mask are zero exactly')
        err = rel2(reshape(pc, [n**6]), reshape(pd, [n**6]))
        call report('precond', fx, err, tol('precond'))
        call assert_true(err <= tol('precond'), 'O8: the preconditioner matches its explicit matrix')
        sym = support_asymmetry(pc, inside)
        call report('precond symmetry', fx, sym, tol('symmetry'))
        call assert_true(sym <= tol('symmetry'), 'O8: the preconditioner is symmetric on the support')
        ! O7: <u, H v> = <H u, v> on fixed vectors
        err = symmetry_defect(rec, n)
        call report('symmetry', fx, err, tol('symmetry'))
        call assert_true(err <= tol('symmetry'), 'O7: the operator is symmetric on fixed vectors')
        call rec%kill()
        call prob%kill()
    end subroutine test_operator_small

    ! |Z_s - Z_s^T| / |Z_s| of a matrix's support block, Frobenius
    real(real64) function support_asymmetry( z, inside ) result(e)
        real(real64), intent(in) :: z(:,:)
        logical,      intent(in) :: inside(:)
        real(real64) :: num, den
        integer      :: i, j
        num = 0._real64
        den = 0._real64
        do j = 1, size(z, 2)
            if( .not. inside(j) ) cycle
            do i = 1, size(z, 1)
                if( .not. inside(i) ) cycle
                num = num + (z(i, j) - z(j, i))**2
                den = den + z(i, j)**2
            end do
        end do
        e = sqrt(num / den)
    end function support_asymmetry

    ! the defect of <u, H v> = <H u, v> on two fixed vectors over |u| |H v| + |H u| |v|, in double from the device's
    ! products
    real(real64) function symmetry_defect( rec, n ) result(e)
        type(reconstructor_pcg), intent(inout) :: rec
        integer,                 intent(in)    :: n
        type(mlx_array) :: ud, vd, hu, hv
        real(real32)    :: u(n, n, n), v(n, n, n), hu_h(n, n, n), hv_h(n, n, n)
        real(real64)    :: a, b
        u  = fixed_volume(n, 1)
        v  = fixed_volume(n, 2)
        ud = mlx_from(u)
        vd = mlx_from(v)
        hu = device_apply(rec, ud)
        hv = device_apply(rec, vd)
        call mlx_to(hu_h, hu)
        call mlx_to(hv_h, hv)
        a = sum(real(u, real64) * real(hv_h, real64))
        b = sum(real(hu_h, real64) * real(v, real64))
        e = abs(a - b) / (norm2(real(u, real64)) * norm2(real(hv_h, real64)) + norm2(real(hu_h, real64)) * &
                          norm2(real(v, real64)))
    end function symmetry_defect

    ! 100 cycles of new, end_accum, one application and kill leave the live handles and the active memory as they
    ! were. The device releases a buffer when the work that used it completes: each sample waits for the stream.
    subroutine test_lifecycle( fx )
        type(recon_fixture), intent(in) :: fx
        type(reconstructor_pcg) :: rec
        type(mlx_array)         :: v, hv
        real(real32)            :: y(fx%n, fx%n, fx%n)
        integer(int64)          :: mem0, mem1
        integer                 :: live0, live1, k
        write(*,'(a,a)') 'test_lifecycle ', device_name_now()
        call assemble(fx, rec)
        v  = mlx_from(fixed_volume(fx%n, 3))
        hv = device_apply(rec, v)
        call mlx_to(y, hv)
        call rec%kill()
        call hv%kill()
        call mlx_synchronize()
        live0 = mlx_live_count()
        mem0  = mlx_active_memory()
        do k = 1, NCYCLES
            call assemble(fx, rec)
            hv = device_apply(rec, v)
            call mlx_to(y, hv)
            call rec%kill()
            call hv%kill()
        end do
        call mlx_synchronize()
        live1 = mlx_live_count()
        mem1  = mlx_active_memory()
        call assert_true(live1 == live0, 'reconstructor_pcg: 100 cycles of new, end_accum, apply and kill leave '//&
            'the live handles as they were')
        call assert_true(mem1 == mem0, 'reconstructor_pcg: 100 cycles of new, end_accum, apply and kill leave '//&
            'the active memory as it was')
    end subroutine test_lifecycle

    ! the five procedures of the operator on host volumes (SIMPLE's dummy lists) against the device forms the engine
    ! solves with, brought to the host: byte for byte, since a host form is its device form between two copies.
    ! apply_normal_kernel, taken with the support set, is held to the operator once the support is cleared, where
    ! the operator is the kernel's product alone, and differs from the masked operator's; mask_mul is held to the
    ! preconditioner's product before end_accum, which is P r. On the host backend, where the toy makes no
    ! reconstructor, each of the five is refused with its message
    subroutine test_host_forms( fx )
        type(recon_fixture), intent(in) :: fx
        type(reconstructor_pcg)       :: rec
        type(mlx_array)               :: ud, vd, yd
        real(real32)                  :: u(fx%n, fx%n, fx%n), v(fx%n, fx%n, fx%n), ref(fx%n, fx%n, fx%n)
        real(real32)                  :: part(fx%n * fx%n)
        real(real32),     allocatable :: y(:,:,:), hk(:,:,:)
        real(real64)                  :: d, dref
        character(len=:), allocatable :: dev
        dev = ' ('//device_name_now()//')'
        write(*,'(a,a)') 'test_host_forms ', device_name_now()
        u  = fixed_volume(fx%n, 7)
        v  = fixed_volume(fx%n, 8)
        ud = mlx_from(u)
        vd = mlx_from(v)
        call assemble(fx, rec)
        y  = rec%apply_normal(u)
        yd = device_apply(rec, ud)
        call mlx_to(ref, yd)
        call assert_true(same_volume(y, ref) .and. .not. same_volume(y, u), 'reconstructor_pcg%apply_normal of a host '//&
            'volume is the device form''s product brought to the host, byte for byte'//dev)
        hk  = rec%apply_normal_kernel(u)
        ref = kernel_reference(rec, ud)
        call assert_true(same_volume(hk, ref) .and. .not. same_volume(hk, y), &
            'reconstructor_pcg%apply_normal_kernel of a host volume is the device form''s product (the operator '//&
            'once the support is cleared), byte for byte, and not the masked operator''s'//dev)
        call rec%kill()
        call assemble(fx, rec)
        y  = rec%apply_precond(u)
        yd = device_precond(rec, ud)
        call mlx_to(ref, yd)
        call assert_true(same_volume(y, ref) .and. .not. same_volume(y, u), 'reconstructor_pcg%apply_precond of a '//&
            'host volume is the device form''s product brought to the host, byte for byte'//dev)
        d  = rec%dot_real_volume(u, v)
        yd = device_dot(rec, ud, vd)
        call mlx_to(part, yd)
        dref = sum(real(part, real64))
        call assert_true(bits_equal(d, dref) .and. abs(dref) > 0._real64, 'reconstructor_pcg%dot_real_volume of host '//&
            'volumes is the device form''s line sums added in double, byte for byte'//dev)
        call rec%kill()
        call rec%new(fx%n)
        call rec%set_window_sphere(real(fx%mskrad, real32))
        y  = u
        call rec%mask_mul(y)
        yd = device_precond(rec, ud)
        call mlx_to(ref, yd)
        call assert_true(same_volume(y, ref) .and. .not. same_volume(y, u), 'reconstructor_pcg%mask_mul of a host '//&
            'volume is the device form''s P v (the preconditioner before end_accum), byte for byte'//dev)
        call rec%kill()
        call rec%new(fx%n, params=parameters(l_mlx=.false.))
        y = rec%apply_normal(u)
        call assert_true(size(y) == 0 .and. index(rec%message(), 'apply_normal: refused: the toy has no host route') > 0, &
            'reconstructor_pcg%apply_normal is refused on the host backend: '//rec%message()//dev)
        y = rec%apply_normal_kernel(u)
        call assert_true(size(y) == 0 .and. index(rec%message(), 'apply_normal_kernel: refused: the toy has no host '//&
            'route') > 0, 'reconstructor_pcg%apply_normal_kernel is refused on the host backend: '//rec%message()//dev)
        y = rec%apply_precond(u)
        call assert_true(size(y) == 0 .and. index(rec%message(), 'apply_precond: refused: the toy has no host route') > 0, &
            'reconstructor_pcg%apply_precond is refused on the host backend: '//rec%message()//dev)
        d = rec%dot_real_volume(u, v)
        call assert_true(bits_equal(d, 0._real64) .and. index(rec%message(), 'dot_real_volume: refused: the toy has no '//&
            'host route') > 0, 'reconstructor_pcg%dot_real_volume is refused on the host backend: '//rec%message()//dev)
        y = u
        call rec%mask_mul(y)
        call assert_true(same_volume(y, u) .and. index(rec%message(), 'mask_mul: refused: the toy has no host route') > 0, &
            'reconstructor_pcg%mask_mul is refused on the host backend, the volume as it came: '//rec%message()//dev)
        call rec%kill()
    end subroutine test_host_forms

    ! the kernel's product H u of a finalised reconstructor by the device form the engine solves with: the support
    ! is cleared (a non-positive radius), which leaves the operator as the kernel's product alone
    function kernel_reference( rec, ud ) result(ref)
        type(reconstructor_pcg), intent(inout) :: rec
        type(mlx_array),         intent(in)    :: ud
        real(real32)    :: ref(rec%box, rec%box, rec%box)
        type(mlx_array) :: yd
        call rec%set_window_sphere(0._real32)
        yd = device_apply(rec, ud)
        call mlx_to(ref, yd)
    end function kernel_reference

    ! whether a host volume has the shape and the bytes of another
    pure logical function same_volume( y, ref )
        real(real32), intent(in) :: y(:,:,:), ref(:,:,:)
        same_volume = .false.
        if( any(shape(y) /= shape(ref)) ) return
        same_volume = all(bits_equal(y, ref))
    end function same_volume

    ! ---- the named-only fixture ----------------------------------------------------------------------------

    ! O10 at n = 32: O2 to O5 against the oracle; the operator and the preconditioner on fixed vectors against the
    ! oracle's apply and precond; O7
    subroutine test_operator_n32( fx )
        type(recon_fixture), intent(in) :: fx
        type(reconstructor_pcg)    :: rec
        type(oracle_recon_problem) :: prob
        type(mlx_array)            :: vd, hv, zv
        real(real32), allocatable  :: khat(:,:,:), pre(:,:,:), b(:,:,:), env(:,:,:), invenv(:,:,:), y(:,:,:)
        real(real64), allocatable  :: kref(:,:,:), pref(:,:,:), ref(:)
        real(real64)               :: err, eop, epc
        integer                    :: n, m, k
        n = fx%n
        m = 2 * n
        write(*,'(a,i0,a,a)') 'test_operator_n32 seed=', fx%seed, ' ', device_name_now()
        call prob%new(fx%d64, fx%mskrad, real(RECON_PCG_LAMBDA_REL, real64), .true.)
        call assemble(fx, rec)
        call assert_true(len(rec%message()) == 0, 'reconstructor_pcg_n32: the fixture assembles: '//rec%message())
        allocate(khat(n+1, m, m), pre(n+1, m, m), b(n, n, n), env(n, n, n), invenv(n, n, n), y(n, n, n), ref(n**3))
        call rec%copy_spectra(khat, pre)
        call rec%copy_volumes(b, env, invenv)
        kref = prob%kernel()
        err  = nan_maxval(abs(real(khat, real64) - kref(1:n+1, :, :))) / nan_maxval(abs(kref(1:n+1, :, :)))
        call report('kernel', fx, err, tol('kernel'))
        call assert_true(err <= tol('kernel'), 'O10: the kernel spectrum matches the oracle''s at n = 32')
        pref = prob%spectrum()
        call assert_true(all((abs(pre) > 0._real32) .eqv. (abs(pref(1:n+1, :, :)) > 0._real64)), &
            'O10: the preconditioner''s spectrum is zero exactly where the oracle''s is, at n = 32')
        err = nan_maxval(merge(abs(real(pre, real64) - pref(1:n+1, :, :)) / max(abs(pref(1:n+1, :, :)), tiny(1._real64)), &
                               0._real64, abs(pref(1:n+1, :, :)) > 0._real64))
        call report('spectrum', fx, err, tol('spectrum'))
        call assert_true(err <= tol('spectrum'), 'O10: the preconditioner''s spectrum matches the oracle''s at n = 32')
        err = abs(real(rec%get_effective_lambda(), real64) - prob%ridge()) / prob%ridge()
        call report('ridge', fx, err, tol('ridge'))
        call assert_true(err <= tol('ridge'), 'O10: the relative ridge matches the oracle''s at n = 32')
        err = rel2(real(reshape(b, [n**3]), real64), prob%rhs(fx%b64))
        call report('rhs', fx, err, tol('rhs'))
        call assert_true(err <= tol('rhs'), 'O10: the right-hand side matches the oracle''s at n = 32')
        eop = 0._real64
        epc = 0._real64
        do k = 1, NVEC_N32
            vd = mlx_from(fixed_volume(n, k))
            hv = device_apply(rec, vd)
            zv = device_precond(rec, vd)
            call mlx_to(y, hv)
            call prob%apply(real(reshape(fixed_volume(n, k), [n**3]), real64), ref)
            eop = max(eop, rel2(real(reshape(y, [n**3]), real64), ref))
            call mlx_to(y, zv)
            call prob%precond(real(reshape(fixed_volume(n, k), [n**3]), real64), ref)
            epc = max(epc, rel2(real(reshape(y, [n**3]), real64), ref))
        end do
        call report('operator', fx, eop, tol('operator'))
        call assert_true(eop <= tol('operator'), 'O10: the operator matches the oracle''s apply on fixed vectors')
        call report('precond', fx, epc, tol('precond'))
        call assert_true(epc <= tol('precond'), 'O10: the preconditioner matches the oracle''s on fixed vectors')
        err = symmetry_defect(rec, n)
        call report('symmetry', fx, err, tol('symmetry'))
        call assert_true(err <= tol('symmetry'), 'O7: the operator is symmetric on fixed vectors at n = 32')
        call rec%kill()
        call prob%kill()
    end subroutine test_operator_n32

end module mlxf_toy_reconstructor_pcg_tester
