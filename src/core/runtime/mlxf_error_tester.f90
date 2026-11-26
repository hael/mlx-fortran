!@descr: tests of mlxf_error: recorded messages, checked statuses, and recovery from a failed evaluation
module mlxf_error_tester
use, intrinsic :: iso_fortran_env, only: int64, real32
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_eval, mlx_synchronize, mlx_clear_cache, mlx_active_memory, &
                           mlx_live_count, mlx_last_error, mlx_set_default_device, mlx_default_device, &
                           mlx_device_info_size, MLX_DEVICES
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, gpu_check_runs
implicit none
private

public :: run_all_error_tests, run_all_recovery_half_tests

! one row of the recovery graph: 2**20 float32, 4 MiB
integer, parameter :: ROW = 2**20
! the rows of the graph the fast gate evaluates after the failure: 1 GiB
integer, parameter :: SMALL_ROWS = 256

contains

    subroutine run_all_error_tests
        write(*,'(A)') '**** running all error tests ****'
        call test_checked_status
        call test_recovery
    end subroutine run_all_error_tests

    ! the half-batch form of the recovery gate, run only when named: it allocates half the maximum buffer
    subroutine run_all_recovery_half_tests
        write(*,'(A)') '**** running all recovery_half tests ****'
        call test_recovery_half
    end subroutine run_all_recovery_half_tests

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

    ! the recovery gate of the fast gate: the failing evaluation is refused before its output is allocated, and
    ! the same graph at 1 GiB then evaluates
    subroutine test_recovery
        write(*,'(A)') 'test_recovery'
        call recovery_gate(half_batch=.false.)
    end subroutine test_recovery

    ! the recovery gate with the evaluation after the failure at half the failing batch (half the maximum buffer)
    subroutine test_recovery_half
        write(*,'(A)') 'test_recovery_half'
        call recovery_gate(half_batch=.true.)
    end subroutine test_recovery_half

    ! an evaluation needing one buffer beyond the device's maximum returns a status whose message names the
    ! allocation; the same graph at a batch that fits then evaluates (half the failing batch, or 1 GiB); the
    ! live count and active memory return to where they were. The maximum is the Metal allocator's, which serves
    ! both devices: a CPU-only MLX allocates on the heap, so the gate is a GPU-only check there
    subroutine recovery_gate( half_batch )
        logical, intent(in) :: half_batch
        integer, allocatable          :: devs(:)
        real(real32), allocatable     :: x(:,:), xb(:,:), probe(:)
        character(len=:), allocatable :: msg
        character(len=64)             :: fits
        type(mlx_array)               :: a, b, c
        integer(int64)                :: maxbuf, mem0
        integer                       :: i, nfull, nok, live0, st, original
        call test_devices(devs)
        if( size(devs) == 0 ) return
        if( .not. gpu_check_runs('the recovery gate (the maximum buffer of the Metal allocator)') ) return
        maxbuf = mlx_device_info_size(MLX_DEVICES%gpu, 'max_buffer_length')
        if( maxbuf <= 0_int64 )then
            write(*,'(A)') '    SKIP: the device reports no maximum buffer length'
            return
        endif
        nfull = int(maxbuf / (4_int64 * ROW)) + 1
        if( half_batch )then
            nok = (nfull + 1) / 2
        else
            nok = min(SMALL_ROWS, (nfull + 1) / 2)
        endif
        write(fits,'(I0,A)') nok, ' rows of 4 MiB'
        write(*,'(A,I0,A,I0,A,I0,A)') '    max_buffer_length ', maxbuf, ' B: batches of ', nfull, ' and ', nok, &
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
            allocate(xb(1, nok))
            xb = 2.0_real32
            b = mlx_from(xb)
            c = a + b
            call mlx_eval(c, status=st)
            call assert_int(0, st, device_name(devs(i))//': the same graph at '//trim(fits)//' evaluates')
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
    end subroutine recovery_gate

end module mlxf_error_tester
