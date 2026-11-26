!@descr: streams and the runtime controls added with them: device availability, the memory and wired limits, Metal capture
! Which stream carries an operation does not show in its result, and the library has no query of a stream's device:
! what is proved here of streams is their lifetime, their statuses and that work goes on across a change of the
! default stream, not on which queue it ran.
module mlxf_stream_tester
use, intrinsic :: iso_fortran_env, only: int64, real32
use mlxf,            only: mlx_array, mlx_stream, mlx_new_stream, mlx_default_stream, mlx_set_default_stream, &
                           mlx_synchronize, mlx_device_is_available, mlx_memory_limit, mlx_set_memory_limit, &
                           mlx_set_wired_limit, mlx_metal_start_capture, mlx_metal_stop_capture, mlx_from, mlx_to, &
                           mlx_live_count, mlx_last_error, mlx_set_default_device, mlx_default_device, MLX_DEVICES
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, bits_equal, gpu_present, gpu_check_runs
implicit none
private
public :: run_all_stream_tests

contains

    subroutine run_all_stream_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all stream tests ****'
        call test_empty_streams_parallel
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_streams(devs(i))
        end do
        call mlx_set_default_device(original)
        if( size(devs) > 0 )then
            call test_availability
            call test_limits
            call test_capture
        endif
    end subroutine run_all_stream_tests

    ! copying, killing and finalizing empty streams inside an OpenMP region does not stop
    subroutine test_empty_streams_parallel
        integer :: i, completed(8)
        write(*,'(a)') 'test_empty_streams_parallel'
        completed = 0
        !$omp parallel do num_threads(2) default(shared) private(i) schedule(static) proc_bind(close)
        do i = 1, size(completed)
            call empty_stream_scope
            completed(i) = 1
        end do
        !$omp end parallel do
        call assert_true(all(completed == 1), 'empty stream assignment, kill and finalization are safe in parallel')
    end subroutine test_empty_streams_parallel

    ! an empty stream copied, killed and finalized on leaving the scope
    subroutine empty_stream_scope
        type(mlx_stream) :: s, copy
        copy = s
        call copy%kill()
    end subroutine empty_stream_scope

    ! a stream of one's own becomes the device's default, carries the operations built after that, and is waited
    ! for; the device's first default is put back
    subroutine test_streams( device )
        integer, intent(in) :: device
        type(mlx_stream) :: mine, copy, first
        type(mlx_array)  :: a, r
        real(real32)     :: x(4), y(4)
        integer          :: live0, st
        write(*,'(a)') 'test_streams'
        x = [1._real32, 2._real32, 3._real32, 4._real32]
        a = mlx_from(x)
        r = a+a
        live0 = mlx_live_count()
        first = mlx_default_stream(device)
        mine = mlx_new_stream(device)
        call assert_int(live0+2, mlx_live_count(), 'two stream handles are two live objects')
        copy = mine
        call assert_int(live0+2, mlx_live_count(), 'a copy of a stream shares the handle')
        call mine%kill()
        call mine%kill()
        call mlx_set_default_stream(copy)
        r = a+a
        call mlx_synchronize(copy, status=st)
        call assert_int(0, st, 'waiting for a stream of one''s own returns status zero')
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, 2._real32*x)), 'operations built after mlx_set_default_stream are evaluated')
        call mlx_set_default_stream(first)
        r = a*a
        call mlx_synchronize(first, status=st)
        call assert_int(0, st, 'waiting for the device''s first default stream returns status zero')
        call mlx_synchronize(status=st)
        call assert_int(0, st, 'waiting for every device still returns status zero')
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x*x)), 'and so are those built once the first default stream is put back')
        call copy%kill()
        call first%kill()
        call assert_int(live0, mlx_live_count(), 'killing the stream handles leaves no live object')
    end subroutine test_streams

    ! the CPU device is available wherever MLX allocates, the GPU where one opens
    subroutine test_availability
        write(*,'(a)') 'test_availability'
        call assert_true(mlx_device_is_available(MLX_DEVICES%cpu), 'the CPU device is available')
        call assert_true(mlx_device_is_available(MLX_DEVICES%gpu) .eqv. gpu_present(), &
            &'the GPU device is available exactly when one opens')
    end subroutine test_availability

    ! the memory limit reads back what the setter reports; the wired limit returns the previous one and refuses
    ! more than the system allows
    subroutine test_limits
        integer(int64) :: limit, previous, wired0, back
        integer        :: st
        write(*,'(a)') 'test_limits'
        if( .not. gpu_check_runs('the memory and wired limits (Metal''s allocator)') ) return
        limit = mlx_memory_limit()
        call assert_true(limit > 0_int64, 'the memory limit is positive')
        call mlx_set_memory_limit(limit, previous=previous, status=st)
        call assert_int(0, st, 'setting the memory limit to itself succeeds')
        call assert_true(previous == limit, 'mlx_memory_limit is the limit the setter reports as previous')
        call mlx_set_wired_limit(2_int64**30, previous=wired0, status=st)
        call assert_int(0, st, 'a wired limit of 1 GiB is accepted')
        call mlx_set_wired_limit(2_int64**29, previous=back, status=st)
        call assert_int(0, st, 'and one of half a GiB after it')
        call assert_true(back == 2_int64**30, 'the setter returns the limit it replaces, not the one it is given')
        call mlx_set_wired_limit(wired0, previous=back, status=st)
        call assert_int(0, st, 'the wired limit is put back')
        call assert_true(back == 2_int64**29, 'and the setter returns the half GiB it replaces')
        call mlx_set_wired_limit(2_int64**50, previous=back, status=st)
        call assert_true(st /= 0, 'a wired limit above what the system allows is refused with a status')
        call assert_true(len(mlx_last_error()) > 0, 'and a message')
        call mlx_set_wired_limit(wired0, status=st)
        call assert_int(0, st, 'MLX remains usable after the refusal')
    end subroutine test_limits

    ! a capture is Metal's to grant: without MTL_CAPTURE_ENABLED=1 in the environment it is refused with a status
    subroutine test_capture
        character(len=8) :: enabled
        integer          :: st
        write(*,'(a)') 'test_capture'
        if( .not. gpu_check_runs('a Metal capture') ) return
        call get_environment_variable('MTL_CAPTURE_ENABLED', enabled)
        if( trim(enabled) == '1' )then
            write(*,'(a)') '    SKIP: MTL_CAPTURE_ENABLED=1: a capture would start and leave a trace behind'
            return
        endif
        call mlx_metal_start_capture('mlxf_stream_tester.gputrace', status=st)
        call assert_true(st /= 0, 'a capture without Metal''s capture layer is refused with a status')
        call assert_true(len(mlx_last_error()) > 0, 'and a message')
        call mlx_metal_stop_capture(status=st)
        call assert_int(0, st, 'stopping a capture that did not start returns status zero')
    end subroutine test_capture

end module mlxf_stream_tester
