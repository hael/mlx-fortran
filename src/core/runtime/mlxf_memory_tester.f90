!@descr: tests of mlxf_memory: active, peak and cache memory follow an array's life; the limits are set and restored
module mlxf_memory_tester
use, intrinsic :: iso_fortran_env, only: int64, real32
use mlxf,            only: mlx_array, mlx_from, mlx_eval, mlx_synchronize, mlx_active_memory, mlx_peak_memory, &
                           mlx_reset_peak_memory, mlx_cache_memory, mlx_clear_cache, mlx_set_memory_limit, &
                           mlx_set_cache_limit
use mlxf_test_utils, only: assert_true, assert_int, test_devices
implicit none
private

public :: run_all_memory_tests

integer, parameter :: N = 1000000

contains

    subroutine run_all_memory_tests
        write(*,'(A)') '**** running all memory tests ****'
        call test_array_life
        call test_limits
    end subroutine run_all_memory_tests

    ! an array of N float32 holds at least 4 N bytes while it lives; once killed its buffer is cached, and
    ! clearing the cache returns the active memory to where it was
    subroutine test_array_life
        integer, allocatable      :: devs(:)
        real(real32), allocatable :: x(:)
        type(mlx_array)           :: a
        integer(int64)            :: m0, m1, peak
        write(*,'(A)') 'test_array_life'
        call test_devices(devs)
        if( size(devs) == 0 ) return
        allocate(x(N))
        x = 1.5_real32
        call mlx_synchronize()
        call mlx_clear_cache()
        m0 = mlx_active_memory()
        a  = mlx_from(x)
        call mlx_eval(a)
        m1 = mlx_active_memory()
        call assert_true(m1 - m0 >= 4_int64 * N, 'a live array of N float32 adds at least 4 N bytes of active memory')
        peak = mlx_peak_memory()
        call assert_true(peak >= m1, 'the peak memory is at least the active memory')
        call a%kill()
        call assert_true(mlx_active_memory() == m0, 'killing the array returns the active memory')
        call mlx_clear_cache()
        call assert_true(mlx_cache_memory() == 0_int64, 'clearing the cache leaves none')
        call mlx_reset_peak_memory()
        call assert_true(mlx_peak_memory() == mlx_active_memory(), 'a reset peak equals the active memory')
    end subroutine test_array_life

    ! the limits belong to the Metal allocator: without a device there is nothing to set (skipped, or a failure
    ! under MLXF_REQUIRE_GPU)
    subroutine test_limits
        integer, allocatable :: devs(:)
        integer(int64)       :: previous, back
        integer              :: st
        write(*,'(A)') 'test_limits'
        call test_devices(devs)
        if( size(devs) == 0 ) return
        call mlx_set_memory_limit(2_int64**33, previous=previous, status=st)
        call assert_int(0, st, 'setting the memory limit succeeds')
        call mlx_set_memory_limit(previous, previous=back)
        call assert_true(back == 2_int64**33, 'the memory limit reads back as set')
        call mlx_set_cache_limit(2_int64**30, previous=previous)
        call mlx_set_cache_limit(previous, previous=back)
        call assert_true(back == 2_int64**30, 'the cache limit reads back as set')
    end subroutine test_limits

end module mlxf_memory_tester
