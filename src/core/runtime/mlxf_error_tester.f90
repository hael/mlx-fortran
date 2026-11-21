!@descr: tests of mlxf_error: recorded messages, checked statuses, and recovery from a failed evaluation
module mlxf_error_tester
use, intrinsic :: iso_fortran_env, only: int64, real32
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_eval, mlx_synchronize, mlx_clear_cache, mlx_active_memory, &
                           mlx_live_count, mlx_last_error, mlx_set_default_device, mlx_default_device, &
                           mlx_device_count, mlx_device_info_size, MLX_DEVICES
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name
implicit none
private

public :: run_all_error_tests

! one row of the recovery graph: 2**20 float32, 4 MiB
integer, parameter :: ROW = 2**20

contains

    subroutine run_all_error_tests
        write(*,'(A)') '**** running all error tests ****'
        call test_checked_status
        call test_recovery
    end subroutine run_all_error_tests

    ! a checked procedure reports a failure through its status and records the message
    subroutine test_checked_status
        integer, allocatable      :: devs(:)
        real(real32), allocatable :: x(:), y(:)
        type(mlx_array)           :: a
        integer                   :: st
        write(*,'(A)') 'test_checked_status'
        call test_devices(devs)
        if( size(devs) == 0 ) return
        allocate(x(6), y(5))
        x = 1.0_real32
        a = mlx_from(x)
        call mlx_to(y, a, status=st)
        call assert_true(st /= 0, 'copying 6 elements into 5 returns a non-zero status')
        call assert_true(index(mlx_last_error(), 'differ in size') > 0, 'the message says the sizes differ')
    end subroutine test_checked_status

    ! the recovery gate: an evaluation needing one buffer beyond the device's maximum returns a status whose
    ! message names the allocation; the same graph at half the batch then evaluates (it allocates half the
    ! maximum buffer, the least the gate allows); the live count and active memory return to where they were
    subroutine test_recovery
        integer, allocatable          :: devs(:)
        real(real32), allocatable     :: x(:,:), xb(:,:), probe(:)
        character(len=:), allocatable :: msg
        type(mlx_array)               :: a, b, c
        integer(int64)                :: maxbuf, mem0
        integer                       :: i, nfull, nhalf, live0, st, original
        write(*,'(A)') 'test_recovery'
        call test_devices(devs)
        if( size(devs) == 0 ) return
        maxbuf = -1_int64
        if( mlx_device_count(MLX_DEVICES%gpu) > 0 ) maxbuf = mlx_device_info_size(MLX_DEVICES%gpu, 'max_buffer_length')
        if( maxbuf <= 0_int64 )then
            write(*,'(A)') '    SKIP: the device reports no maximum buffer length'
            return
        endif
        nfull = int(maxbuf / (4_int64 * ROW)) + 1
        nhalf = (nfull + 1) / 2
        write(*,'(A,I0,A,I0,A,I0,A)') '    max_buffer_length ', maxbuf, ' B: batches of ', nfull, ' and ', nhalf, &
            &' rows of 4 MiB'
        original = mlx_default_device()
        allocate(x(ROW, 1), probe(2))
        x = 1.0_real32
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            call mlx_synchronize()
            call mlx_clear_cache()
            live0 = mlx_live_count()
            mem0  = mlx_active_memory()
            a = mlx_from(x)
            allocate(xb(1, nfull))
            xb = 2.0_real32
            b = mlx_from(xb)
            c = a + b
            call mlx_eval(c, status=st)
            call assert_true(st /= 0, device_name(devs(i))//': a buffer beyond the maximum returns a status')
            msg = mlx_last_error()
            write(*,'(A)') '    '//device_name(devs(i))//': '//msg
            call assert_true(index(msg, 'allocate') > 0 .and. index(msg, 'maximum') > 0, &
                &device_name(devs(i))//': the message names the allocation and the maximum')
            deallocate(xb)
            allocate(xb(1, nhalf))
            xb = 2.0_real32
            b = mlx_from(xb)
            c = a + b
            call mlx_eval(c, status=st)
            call assert_int(0, st, device_name(devs(i))//': the same graph at half the batch evaluates')
            call c%kill()
            c = mlx_from(x(1:2, 1)) + 2.0_real32
            call mlx_to(probe, c, status=st)
            call assert_true(st == 0 .and. all(abs(probe - 3.0_real32) <= epsilon(1.0_real32)), &
                &device_name(devs(i))//': MLX and the library stay usable')
            call a%kill()
            call b%kill()
            call c%kill()
            deallocate(xb)
            call mlx_synchronize()
            call mlx_clear_cache()
            call assert_int(live0, mlx_live_count(), device_name(devs(i))//': the live count returns')
            call assert_true(mlx_active_memory() == mem0, device_name(devs(i))//': the active memory returns')
        end do
        call mlx_set_default_device(original)
    end subroutine test_recovery

end module mlxf_error_tester
