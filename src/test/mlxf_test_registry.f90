!@descr: the area suites and guard groups of mlxf_test_exec: sub-suites per area, and the members of each guard group
! A tester runs only from here; scripts/check_test_registry.py holds the areas to the CTest entries of
! test/CMakeLists.txt, every run_all_<x>_tests of a tester to a row, and the guard groups to the table below.
! A guard member is a stop the library makes by contract: it runs in a child process (mlxf_test_exec
! expect_aborts <group>) and its last reachable statement is the guarded call.
module mlxf_test_registry
use, intrinsic :: iso_fortran_env,     only: int32, real32, real64
use mlxf,                              only: mlx_array, mlx_from, mlx_eval, mlx_live_count, mlx_last_error, &
                                             mlx_set_default_device, MLX_DEVICES, exp, mlx_fft, mlx_fft2, mlx_astype, &
                                             mlx_zeros, mlx_arange, mlx_metal_kernel, mlx_metal_kernel_spec, &
                                             mlx_segmented_mm, mlx_qr, mlx_eigvalsh, mlx_conv2d, mlx_conv_spec, &
                                             mlx_as_strided, matmul
use mlxf_array_tester,                 only: run_all_array_tests
use mlxf_device_tester,                only: run_all_device_tests
use mlxf_error_tester,                 only: run_all_error_tests, run_all_recovery_half_tests
use mlxf_memory_tester,                only: run_all_memory_tests
use mlxf_registry_tester,              only: run_all_registry_tests
use mlxf_version_tester,               only: run_all_version_tests
use mlxf_ops_tester,                   only: run_all_ops_tests
use mlxf_ops_math_tester,              only: run_all_ops_math_tests
use mlxf_ops_logic_tester,             only: run_all_ops_logic_tests
use mlxf_ops_create_tester,            only: run_all_ops_create_tests
use mlxf_ops_reduce_tester,            only: run_all_ops_reduce_tests
use mlxf_ops_sort_tester,              only: run_all_ops_sort_tests
use mlxf_ops_shape_tester,             only: run_all_ops_shape_tests
use mlxf_ops_index_tester,             only: run_all_ops_index_tests
use mlxf_linalg_tester,                only: run_all_linalg_tests
use mlxf_linalg_mm_tester,             only: run_all_linalg_mm_tests
use mlxf_linalg_products_tester,       only: run_all_linalg_products_tests
use mlxf_linalg_matrix_tester,         only: run_all_linalg_matrix_tests
use mlxf_conv_tester,                  only: run_all_conv_tests
use mlxf_fft_tester,                   only: run_all_fft_tests
use mlxf_fft_nd_tester,                only: run_all_fft_nd_tests
use mlxf_fast_tester,                  only: run_all_fast_tests
use mlxf_compile_tester,               only: run_all_compile_tests
use mlxf_toy_polarft_calc_tester,      only: run_all_polarft_calc_tests
use mlxf_toy_polarft_shiftmap_tester,  only: run_all_polar_shiftmap_tests, run_all_polar_shiftmap_accuracy_tests
use mlxf_toy_eul_prob_tab_tester,      only: run_all_eul_prob_tab_tests
use mlxf_toy_polarft_tail_tester,      only: run_all_polarft_tail_tests
use mlxf_oracle_projection_tester,     only: run_all_oracle_projection_tests
use mlxf_toy_projector_tester,         only: run_all_projector_tests, run_all_projector_chain_tests
use mlxf_toy_reconstructor_pcg_tester, only: run_all_reconstructor_pcg_tests, run_all_reconstructor_pcg_n32_tests
use mlxf_toy_pcg_solver_tester,        only: run_all_pcg_solver_tests
use mlxf_bench_polar_table,            only: run_bench_polar_table
use mlxf_bench_recon_pcg,              only: run_bench_recon_pcg
use mlxf_bench_projector,              only: run_bench_projector
use mlxf_bench_insert_probe,           only: run_bench_insert_probe
use mlxf_test_utils,                   only: begin_test_suite, end_test_suite
implicit none
private

public :: run_area, list_areas, run_guard, guard_members, run_bench

abstract interface
    subroutine tester_entry()
    end subroutine tester_entry
end interface

character(len=*), parameter :: AREAS(8) = [character(len=16) :: 'core', 'array', 'ops', 'linalg', 'fft', 'compile', &
    &'fast', 'kernels']
! the measure-only benchmarks, run by hand (never by CTest): mlxf_test_exec test=bench_<x> suite=<mode>
character(len=*), parameter :: BENCHES(4) = [character(len=32) :: 'polar_table', 'recon_pcg', 'projector', &
    &'insert_probe']
! sub-suites an area runs only when suite= names them (too costly for the fast gate)
character(len=*), parameter :: NAMED_ONLY(3) = [character(len=32) :: 'recovery_half', 'polar_shiftmap_accuracy', &
    &'reconstructor_pcg_n32']

type :: guard_member
    character(len=32) :: name  = ''
    character(len=32) :: group = ''
end type guard_member

type(guard_member), parameter :: GUARDS(21) = [&
    &guard_member('guard_empty_operation',   'object_contracts'), &
    &guard_member('guard_stale_handle',      'object_contracts'), &
    &guard_member('guard_openmp_region',     'object_contracts'), &
    &guard_member('guard_float64_on_gpu',    'object_contracts'), &
    &guard_member('guard_region_empty_eval', 'object_contracts'), &
    &guard_member('guard_region_live_count', 'object_contracts'), &
    &guard_member('guard_region_last_error', 'object_contracts'), &
    &guard_member('guard_region_private',    'object_contracts'), &
    &guard_member('guard_fft_norm',          'object_contracts'), &
    &guard_member('guard_fft2_norm',         'object_contracts'), &
    &guard_member('guard_dtype_astype',      'object_contracts'), &
    &guard_member('guard_dtype_zeros',       'object_contracts'), &
    &guard_member('guard_dtype_arange',      'object_contracts'), &
    &guard_member('guard_kernel_spec',       'object_contracts'), &
    &guard_member('guard_kernel_empty',      'object_contracts'), &
    &guard_member('guard_segments_shape',    'object_contracts'), &
    &guard_member('guard_matrix_rank',       'object_contracts'), &
    &guard_member('guard_eigh_uplo',         'object_contracts'), &
    &guard_member('guard_conv_spec',         'object_contracts'), &
    &guard_member('guard_strided_span',      'object_contracts'), &
    &guard_member('guard_matmul_integer',    'object_contracts')]

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
                call run_suite('ops',        run_all_ops_tests,        suite, ran)
                call run_suite('ops_math',   run_all_ops_math_tests,   suite, ran)
                call run_suite('ops_logic',  run_all_ops_logic_tests,  suite, ran)
                call run_suite('ops_create', run_all_ops_create_tests, suite, ran)
                call run_suite('ops_reduce', run_all_ops_reduce_tests, suite, ran)
                call run_suite('ops_sort',   run_all_ops_sort_tests,   suite, ran)
                call run_suite('ops_shape',  run_all_ops_shape_tests,  suite, ran)
                call run_suite('ops_index',  run_all_ops_index_tests,  suite, ran)
            case('linalg')
                call run_suite('linalg', run_all_linalg_tests, suite, ran)
                call run_suite('linalg_mm', run_all_linalg_mm_tests, suite, ran)
                call run_suite('linalg_products', run_all_linalg_products_tests, suite, ran)
                call run_suite('linalg_matrix', run_all_linalg_matrix_tests, suite, ran)
                call run_suite('conv', run_all_conv_tests, suite, ran)
            case('fft')
                call run_suite('fft', run_all_fft_tests, suite, ran)
                call run_suite('fft_nd', run_all_fft_nd_tests, suite, ran)
            case('compile')
                call run_suite('compile', run_all_compile_tests, suite, ran)
            case('fast')
                call run_suite('fast', run_all_fast_tests, suite, ran)
            case('kernels')
                call run_suite('polarft_calc', run_all_polarft_calc_tests, suite, ran)
                call run_suite('polar_shiftmap', run_all_polar_shiftmap_tests, suite, ran)
                call run_suite('polar_shiftmap_accuracy', run_all_polar_shiftmap_accuracy_tests, suite, ran)
                call run_suite('eul_prob_tab', run_all_eul_prob_tab_tests, suite, ran)
                call run_suite('polarft_tail', run_all_polarft_tail_tests, suite, ran)
                call run_suite('oracle_projection', run_all_oracle_projection_tests, suite, ran)
                ! projector: above 0.5 s in Release: the oracle's explicit matrices and DFTs for every fixture, and
                ! the GPU's first compilation of the fused gather
                call run_suite('projector', run_all_projector_tests, suite, ran)
                call run_suite('projector_chain', run_all_projector_chain_tests, suite, ran)
                call run_suite('pcg_solver', run_all_pcg_solver_tests, suite, ran)
                ! reconstructor_pcg: above 0.5 s in Release: the oracle's explicit matrices of 512 unknowns per seed,
                ! the operator's 512 columns on each device, and the fixed solves of every iterate up to the stop
                call run_suite('reconstructor_pcg', run_all_reconstructor_pcg_tests, suite, ran)
                call run_suite('reconstructor_pcg_n32', run_all_reconstructor_pcg_n32_tests, suite, ran)
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
            case('recon_pcg')
                call run_bench_recon_pcg(mode, found)
            case('projector')
                call run_bench_projector(mode, found)
            case('insert_probe')
                call run_bench_insert_probe(mode, found)
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
            case('guard_dtype_astype')
                call guard_dtype_astype
            case('guard_dtype_zeros')
                call guard_dtype_zeros
            case('guard_dtype_arange')
                call guard_dtype_arange
            case('guard_kernel_spec')
                call guard_kernel_spec
            case('guard_kernel_empty')
                call guard_kernel_empty
            case('guard_segments_shape')
                call guard_segments_shape
            case('guard_matrix_rank')
                call guard_matrix_rank
            case('guard_eigh_uplo')
                call guard_eigh_uplo
            case('guard_conv_spec')
                call guard_conv_spec
            case('guard_strided_span')
                call guard_strided_span
            case('guard_matmul_integer')
                call guard_matmul_integer
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

    ! a dtype outside MLX_DTYPES stops before it reaches mlx-c, which indexes a table with it unchecked
    subroutine guard_dtype_astype
        type(mlx_array) :: a, r
        write(*,'(a)') 'guard_dtype_astype: mlx_astype to a dtype outside MLX_DTYPES'
        a = mlx_from([1._real32, 2._real32])
        r = mlx_astype(a, 99)
    end subroutine guard_dtype_astype

    ! as guard_dtype_astype, through mlx_zeros
    subroutine guard_dtype_zeros
        type(mlx_array) :: r
        write(*,'(a)') 'guard_dtype_zeros: mlx_zeros of a dtype outside MLX_DTYPES'
        r = mlx_zeros([2, 3], dtype=-1)
    end subroutine guard_dtype_zeros

    ! as guard_dtype_astype, through mlx_arange
    subroutine guard_dtype_arange
        type(mlx_array) :: r
        write(*,'(a)') 'guard_dtype_arange: mlx_arange of a dtype outside MLX_DTYPES'
        r = mlx_arange(0.d0, 4.d0, dtype=99)
    end subroutine guard_dtype_arange

    ! a Metal kernel spec that names no output stops when the kernel is built
    subroutine guard_kernel_spec
        type(mlx_metal_kernel_spec) :: spec
        type(mlx_metal_kernel)      :: k
        write(*,'(a)') 'guard_kernel_spec: a Metal kernel built from a spec without outputs'
        spec%name = 'mlxf_guard_no_output'
        spec%source = 'uint elem = thread_position_in_grid.x;'
        k = mlx_metal_kernel(spec)
    end subroutine guard_kernel_spec

    ! applying a declared, never-built Metal kernel stops, with or without a status
    subroutine guard_kernel_empty
        type(mlx_metal_kernel)       :: k
        type(mlx_array)              :: none(0)
        type(mlx_array), allocatable :: outputs(:)
        integer                      :: st
        write(*,'(a)') 'guard_kernel_empty: applying an empty Metal kernel'
        call k%apply(none, outputs, status=st)
    end subroutine guard_kernel_empty

    ! segments whose first dimension is not of extent 2 stop: the shift of their bounds would broadcast a (1, n)
    ! array into pairs before MLX saw it
    subroutine guard_segments_shape
        type(mlx_array) :: a, b, r
        write(*,'(a)') 'guard_segments_shape: mlx_segmented_mm with a (1, 3) array of segments'
        a = mlx_from(reshape([1._real32, 2._real32, 3._real32, 4._real32], [2, 2]))
        b = mlx_from(reshape([1._real32, 2._real32, 3._real32, 4._real32], [2, 2]))
        r = mlx_segmented_mm(a, b, mlx_from(reshape([1, 2, 1], [1, 3])))
    end subroutine guard_segments_shape

    ! a factorisation of an array without a second dimension stops
    subroutine guard_matrix_rank
        type(mlx_array) :: a, q, r
        write(*,'(a)') 'guard_matrix_rank: mlx_qr of a rank-1 array'
        a = mlx_from([1._real32, 2._real32, 3._real32])
        call mlx_qr(a, q, r)
    end subroutine guard_matrix_rank

    ! a triangle that is neither 'L' nor 'U' stops
    subroutine guard_eigh_uplo
        type(mlx_array) :: a, r
        write(*,'(a)') 'guard_eigh_uplo: mlx_eigvalsh with the triangle X'
        a = mlx_from(reshape([2._real32, 1._real32, 1._real32, 3._real32], [2, 2]))
        r = mlx_eigvalsh(a, uplo='X')
    end subroutine guard_eigh_uplo

    ! a list of the convolution spec with neither one value nor one per spatial dimension stops
    subroutine guard_conv_spec
        type(mlx_array) :: a, w, r
        real(real32)    :: x(1, 4, 4, 1), k(1, 2, 2, 1)
        write(*,'(a)') 'guard_conv_spec: mlx_conv2d with three strides'
        x = 1._real32
        k = 1._real32
        a = mlx_from(x)
        w = mlx_from(k)
        r = mlx_conv2d(a, w, mlx_conv_spec(stride=[1, 1, 1]))
    end subroutine guard_conv_spec

    ! a strided view that reaches one element past the end of its input stops
    subroutine guard_strided_span
        type(mlx_array) :: a, r
        real(real32)    :: x(3, 4)
        write(*,'(a)') 'guard_strided_span: mlx_as_strided reaching past the last element'
        x = 1._real32
        a = mlx_from(x)
        r = mlx_as_strided(a, [3, 4], [1, 3], offset=1)
    end subroutine guard_strided_span

    ! MLX multiplies inexact matrices only: matmul of two integer arrays stops, unlike Fortran's
    subroutine guard_matmul_integer
        type(mlx_array) :: a, b, r
        integer(int32)  :: x(2, 2)
        write(*,'(a)') 'guard_matmul_integer: matmul of two int32 arrays'
        x = 1
        a = mlx_from(x)
        b = mlx_from(x)
        r = matmul(a, b)
    end subroutine guard_matmul_integer

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
