!@descr: the area suites and guard groups of mlxf_test_exec: sub-suites per area, and the members of each guard group
! A tester runs only from here; scripts/check_test_registry.py holds the areas to the CTest entries of
! test/CMakeLists.txt, every run_all_<x>_tests of a tester to a row, and the guard groups to the table below.
! A guard member is a stop the library makes by contract: it runs in a child process (mlxf_test_exec
! expect_aborts <group>) and its last reachable statement is the guarded call.
module mlxf_test_registry
use, intrinsic :: iso_fortran_env,           only: real32, real64
use mlxf,                                    only: mlx_array, mlx_from, mlx_eval, mlx_live_count, mlx_last_error, &
                                                   mlx_set_default_device, MLX_DEVICES, exp, mlx_fft, mlx_fft2
use mlxf_array_tester,                       only: run_all_array_tests
use mlxf_device_tester,                      only: run_all_device_tests
use mlxf_error_tester,                       only: run_all_error_tests, run_all_recovery_half_tests
use mlxf_memory_tester,                      only: run_all_memory_tests
use mlxf_registry_tester,                    only: run_all_registry_tests
use mlxf_version_tester,                     only: run_all_version_tests
use mlxf_ops_tester,                         only: run_all_ops_tests
use mlxf_linalg_tester,                      only: run_all_linalg_tests
use mlxf_fft_tester,                         only: run_all_fft_tests
use mlxf_compile_tester,                     only: run_all_compile_tests
use mlxf_kernel_polar_table_tester,          only: run_all_polar_table_tests
use mlxf_kernel_polar_table_shiftmap_tester, only: run_all_polar_shiftmap_tests, run_all_polar_shiftmap_accuracy_tests
use mlxf_bench_polar_table,                  only: run_bench_polar_table
use mlxf_test_utils,                         only: begin_test_suite, end_test_suite
implicit none
private

public :: run_area, list_areas, run_guard, guard_members, run_bench

abstract interface
    subroutine tester_entry()
    end subroutine tester_entry
end interface

character(len=*), parameter :: AREAS(7) = [character(len=16) :: 'core', 'array', 'ops', 'linalg', 'fft', 'compile', &
    &'kernels']
! the measure-only benchmarks, run by hand (never by CTest): mlxf_test_exec test=bench_<x> suite=<mode>
character(len=*), parameter :: BENCHES(1) = [character(len=32) :: 'polar_table']
! sub-suites an area runs only when suite= names them (too costly for the fast gate)
character(len=*), parameter :: NAMED_ONLY(2) = [character(len=32) :: 'recovery_half', 'polar_shiftmap_accuracy']

type :: guard_member
    character(len=32) :: name  = ''
    character(len=32) :: group = ''
end type guard_member

type(guard_member), parameter :: GUARDS(10) = [&
    &guard_member('guard_empty_operation',   'object_contracts'), &
    &guard_member('guard_stale_handle',      'object_contracts'), &
    &guard_member('guard_openmp_region',     'object_contracts'), &
    &guard_member('guard_float64_on_gpu',    'object_contracts'), &
    &guard_member('guard_region_empty_eval', 'object_contracts'), &
    &guard_member('guard_region_live_count', 'object_contracts'), &
    &guard_member('guard_region_last_error', 'object_contracts'), &
    &guard_member('guard_region_private',    'object_contracts'), &
    &guard_member('guard_fft_norm',          'object_contracts'), &
    &guard_member('guard_fft2_norm',         'object_contracts')]

contains

    ! runs the sub-suites of one area, or only the one named by suite (empty: all but the named-only ones)
    subroutine run_area( area, suite, found )
        character(len=*), intent(in)  :: area, suite
        logical,          intent(out) :: found
        logical :: ran
        found = .true.
        ran   = .false.
        select case( trim(area) )
            case('core')
                call run_suite('version',       run_all_version_tests,       suite, ran)
                call run_suite('device',        run_all_device_tests,        suite, ran)
                call run_suite('memory',        run_all_memory_tests,        suite, ran)
                call run_suite('registry',      run_all_registry_tests,      suite, ran)
                call run_suite('error',         run_all_error_tests,         suite, ran)
                call run_suite('recovery_half', run_all_recovery_half_tests, suite, ran)
            case('array')
                call run_suite('array',    run_all_array_tests,    suite, ran)
            case('ops')
                call run_suite('ops', run_all_ops_tests, suite, ran)
            case('linalg')
                call run_suite('linalg', run_all_linalg_tests, suite, ran)
            case('fft')
                call run_suite('fft', run_all_fft_tests, suite, ran)
            case('compile')
                call run_suite('compile', run_all_compile_tests, suite, ran)
            case('kernels')
                call run_suite('polar_table', run_all_polar_table_tests, suite, ran)
                call run_suite('polar_shiftmap', run_all_polar_shiftmap_tests, suite, ran)
                call run_suite('polar_shiftmap_accuracy', run_all_polar_shiftmap_accuracy_tests, suite, ran)
            case default
                found = .false.
                return
        end select
        if( len_trim(suite) > 0 .and. .not. ran ) found = .false.
    end subroutine run_area

    subroutine list_areas
        integer :: i
        write(*,'(A)') 'mlxf_test_exec test=<name> [suite=<sub-suite>] [device=cpu|gpu|all]; tests:'
        do i = 1, size(AREAS)
            write(*,'(A)') '    unit_'//trim(AREAS(i))
        end do
        write(*,'(A)') 'mlxf_test_exec expect_aborts <group> | expect_abort <member>; guard members:'
        do i = 1, size(GUARDS)
            write(*,'(A)') '    '//trim(GUARDS(i)%group)//': '//trim(GUARDS(i)%name)
        end do
        write(*,'(A)') 'benchmarks, by hand: mlxf_test_exec test=bench_<x> suite=<mode> [key=value ...]:'
        do i = 1, size(BENCHES)
            write(*,'(A)') '    bench_'//trim(BENCHES(i))
        end do
        write(*,'(A)') 'sub-suites run only when named (suite=<name>):'
        do i = 1, size(NAMED_ONLY)
            write(*,'(A)') '    '//trim(NAMED_ONLY(i))
        end do
    end subroutine list_areas

    ! runs one mode of a benchmark (found: the benchmark and the mode exist)
    subroutine run_bench( name, mode, found )
        character(len=*), intent(in)  :: name, mode
        logical,          intent(out) :: found
        found = .false.
        select case( trim(name) )
            case('polar_table')
                call run_bench_polar_table(mode, found)
        end select
    end subroutine run_bench

    subroutine run_suite( name, entry, only, ran )
        character(len=*), intent(in)    :: name, only
        procedure(tester_entry)         :: entry
        logical,          intent(inout) :: ran
        if( len_trim(only) > 0 )then
            if( trim(only) /= name ) return
        else
            if( any(NAMED_ONLY == name) ) return
        endif
        call begin_test_suite(name)
        call entry()
        call end_test_suite
        ran = .true.
    end subroutine run_suite

    ! the members of a guard group (none: no such group)
    function guard_members( group ) result(names)
        character(len=*), intent(in) :: group
        character(len=32), allocatable :: names(:)
        integer                        :: i
        allocate(names(0))
        do i = 1, size(GUARDS)
            if( trim(GUARDS(i)%group) == trim(group) ) names = [names, GUARDS(i)%name]
        end do
    end function guard_members

    ! runs one guard member in this process; returns only when the member did not stop
    subroutine run_guard( name, found )
        character(len=*), intent(in)  :: name
        logical,          intent(out) :: found
        found = .true.
        select case( trim(name) )
            case('guard_fft_norm')
                call guard_fft_norm
            case('guard_fft2_norm')
                call guard_fft2_norm
            case('guard_empty_operation')
                call guard_empty_operation
            case('guard_stale_handle')
                call guard_stale_handle
            case('guard_openmp_region')
                call guard_openmp_region
            case('guard_float64_on_gpu')
                call guard_float64_on_gpu
            case('guard_region_empty_eval')
                call guard_region_empty_eval
            case('guard_region_live_count')
                call guard_region_live_count
            case('guard_region_last_error')
                call guard_region_last_error
            case('guard_region_private')
                call guard_region_private
            case default
                found = .false.
        end select
    end subroutine run_guard

    ! an operation on a declared, never-assigned mlx_array stops
    ! a one-dimensional FFT with a normalisation outside MLX_FFT_NORMS stops
    subroutine guard_fft_norm
        type(mlx_array) :: a, r
        write(*,'(a)') 'guard_fft_norm: invalid one-dimensional FFT normalization'
        a = mlx_from([1._real32, 2._real32])
        r = mlx_fft(a, 1, norm=-42)
    end subroutine guard_fft_norm

    ! a two-dimensional FFT with a normalisation outside MLX_FFT_NORMS stops
    subroutine guard_fft2_norm
        type(mlx_array) :: a, r
        write(*,'(a)') 'guard_fft2_norm: invalid two-dimensional FFT normalization'
        a = mlx_from(reshape([1._real32, 2._real32, 3._real32, 4._real32], [2, 2]))
        r = mlx_fft2(a, [1, 2], norm=-42)
    end subroutine guard_fft2_norm

    subroutine guard_empty_operation
        type(mlx_array) :: a, b
        write(*,'(A)') 'guard_empty_operation: exp of an empty mlx_array'
        b = exp(a)
    end subroutine guard_empty_operation

    ! a copy made by allocate(source=) is used after its object was released: it stops as stale
    subroutine guard_stale_handle
        real(real32)                 :: x(3)
        type(mlx_array)              :: a, b
        type(mlx_array), allocatable :: s
        x = 1.0_real32
        a = mlx_from(x)
        allocate(s, source=a)
        call a%kill()
        write(*,'(A)') 'guard_stale_handle: exp of a stale copy'
        b = exp(s)
    end subroutine guard_stale_handle

    ! a library call from inside an OpenMP parallel region stops
    subroutine guard_openmp_region
        real(real32)    :: x(3)
        type(mlx_array) :: a
        x = 1.0_real32
        write(*,'(A)') 'guard_openmp_region: mlx_from inside a parallel region'
        !$omp parallel num_threads(2) default(shared) private(a)
        a = mlx_from(x)
        !$omp end parallel
    end subroutine guard_openmp_region

    ! a float64 operation built on the GPU stops (Metal has no float64)
    subroutine guard_float64_on_gpu
        real(real64)    :: x(3)
        type(mlx_array) :: a, b
        x = 1.0_real64
        call mlx_set_default_device(MLX_DEVICES%gpu)
        a = mlx_from(x)
        write(*,'(A)') 'guard_float64_on_gpu: a float64 addition on the GPU'
        b = a + a
    end subroutine guard_float64_on_gpu

    ! the one-thread guard runs before the operands are looked at: evaluating an empty list inside a parallel
    ! region stops although there is nothing to evaluate
    subroutine guard_region_empty_eval
        type(mlx_array) :: none(0)
        write(*,'(A)') 'guard_region_empty_eval: mlx_eval of an empty list inside a parallel region'
        !$omp parallel num_threads(2) default(shared)
        call mlx_eval(none)
        !$omp end parallel
    end subroutine guard_region_empty_eval

    ! the registry's count is read only from the thread that builds graphs
    subroutine guard_region_live_count
        integer :: n
        write(*,'(A)') 'guard_region_live_count: mlx_live_count inside a parallel region'
        !$omp parallel num_threads(2) default(shared) private(n)
        n = mlx_live_count()
        !$omp end parallel
    end subroutine guard_region_live_count

    ! the last error is process-global: it is read only from the thread that builds graphs
    subroutine guard_region_last_error
        character(len=:), allocatable :: msg
        write(*,'(A)') 'guard_region_last_error: mlx_last_error inside a parallel region'
        !$omp parallel num_threads(2) default(shared) private(msg)
        msg = mlx_last_error()
        !$omp end parallel
    end subroutine guard_region_last_error

    ! a live handle copied into a parallel region (firstprivate, a bitwise copy) and released there stops: the
    ! registry would be updated from several threads
    subroutine guard_region_private
        real(real32)    :: x(3)
        type(mlx_array) :: a
        x = 1.0_real32
        a = mlx_from(x)
        write(*,'(A)') 'guard_region_private: a firstprivate live handle inside a parallel region'
        !$omp parallel num_threads(2) default(shared) firstprivate(a)
        call a%kill()
        !$omp end parallel
    end subroutine guard_region_private

end module mlxf_test_registry
