!@descr: tests of mlxf_device: the backend, device counts, the default device, device information
module mlxf_device_tester
use, intrinsic :: iso_fortran_env, only: int64, real32
use mlxf,            only: MLX_DEVICES, mlx_array, mlx_from, mlx_to, mlx_metal_is_available, mlx_device_count, &
                           mlx_default_device, mlx_set_default_device, mlx_device_info_size, mlx_device_info_string, &
                           mlx_last_error
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, gpu_present, gpu_only_skip
implicit none
private

public :: run_all_device_tests

contains

    subroutine run_all_device_tests
        write(*,'(A)') '**** running all device tests ****'
        call test_counts
        call test_backend
        call test_default_device
        call test_device_info
    end subroutine run_all_device_tests

    subroutine test_counts
        integer :: first, second
        write(*,'(A)') 'test_counts'
        first  = mlx_device_count(MLX_DEVICES%gpu)
        second = mlx_device_count(MLX_DEVICES%gpu)
        write(*,'(A,I0)') '    GPU devices: ', first
        call assert_true(first >= 0 .and. first == second, 'the GPU device count is a stable, non-negative number')
        call assert_int(1, mlx_device_count(MLX_DEVICES%cpu), 'MLX has one CPU device')
    end subroutine test_counts

    ! the Metal backend is compiled in or not, the same at every call; a GPU device is a Metal device here, and
    ! without the backend there is no GPU and the CPU device allocates (MLX's heap allocator)
    subroutine test_backend
        real(real32)    :: y(3)
        type(mlx_array) :: a
        logical         :: metal, again, gpu
        integer         :: st, original
        write(*,'(A)') 'test_backend'
        metal = mlx_metal_is_available()
        again = mlx_metal_is_available()
        gpu   = gpu_present()
        write(*,'(A,L1)') '    Metal backend: ', metal
        call assert_true(metal .eqv. again, 'whether the Metal backend is built in is stable')
        call assert_true(metal .or. .not. gpu, 'without the Metal backend MLX opens no GPU')
        if( metal ) return
        original = mlx_default_device()
        call mlx_set_default_device(MLX_DEVICES%cpu)
        a = mlx_from([1._real32, 2._real32, 3._real32]) * 2._real32
        call mlx_to(y, a, status=st)
        call assert_true(st == 0 .and. all(abs(y - [2._real32, 4._real32, 6._real32]) <= 0._real32), &
            &'a CPU-only MLX allocates and evaluates on the CPU device')
        call a%kill()
        call mlx_set_default_device(original)
    end subroutine test_backend

    subroutine test_default_device
        integer, allocatable :: devs(:)
        integer              :: original, i, st
        write(*,'(A)') 'test_default_device'
        call test_devices(devs)
        original = mlx_default_device()
        call assert_true(original == MLX_DEVICES%cpu .or. original == MLX_DEVICES%gpu, 'the default device is the CPU or the GPU')
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i), status=st)
            call assert_int(0, st, 'setting the default device to the '//device_name(devs(i))//' succeeds')
            call assert_int(devs(i), mlx_default_device(), 'the default device is then the '//device_name(devs(i)))
        end do
        call mlx_set_default_device(original)
        call assert_int(original, mlx_default_device(), 'the original default device is restored')
        if( .not. gpu_present() )then
            ! MLX 0.32 accepts an absent GPU as the default (the failure comes with the first allocation); a
            ! refusal is allowed too, and then carries a message. Either way the call returns
            call mlx_set_default_device(MLX_DEVICES%gpu, status=st)
            if( st == 0 )then
                call assert_int(MLX_DEVICES%gpu, mlx_default_device(), 'an absent GPU accepted as default reads back')
            else
                call assert_true(len(mlx_last_error()) > 0, 'an absent GPU refused as default comes with a message')
            endif
            call mlx_set_default_device(original)
        endif
    end subroutine test_default_device

    subroutine test_device_info
        character(len=:), allocatable :: msg, str
        integer(int64)                :: maxbuf, memsize, n
        integer                       :: st
        write(*,'(A)') 'test_device_info'
        ! a device type MLX does not know is refused before it reaches mlx-c (which indexes a table with it):
        ! a status and a message, and -1 never stands for the failure alone
        n   = mlx_device_info_size(7, 'memory_size', status=st)
        msg = mlx_last_error()
        call assert_true(n == -1_int64 .and. st /= 0 .and. index(msg, 'unknown device type') > 0, &
            &'device information of an unknown device type returns a status and a message')
        str = mlx_device_info_string(-1, 'device_name', status=st)
        call assert_true(len(str) == 0 .and. st /= 0, 'a device string of an unknown device type returns a status')
        call mlx_set_default_device(7, status=st)
        call assert_true(st /= 0, 'an unknown device type as the default device returns a status')
        if( .not. gpu_present() )then
            n = mlx_device_info_size(MLX_DEVICES%gpu, 'memory_size', status=st)
            call assert_true(n == -1_int64 .and. st == 0, 'an absent GPU gives -1 with status 0, not an error')
            if( mlx_metal_is_available() )then
                write(*,'(A)') '    SKIP: no GPU device'
            else
                call gpu_only_skip('the information of the GPU')
            endif
            return
        endif
        write(*,'(A)') '    GPU: '//mlx_device_info_string(MLX_DEVICES%gpu, 'device_name')//', '//&
            &mlx_device_info_string(MLX_DEVICES%gpu, 'architecture')
        maxbuf  = mlx_device_info_size(MLX_DEVICES%gpu, 'max_buffer_length')
        memsize = mlx_device_info_size(MLX_DEVICES%gpu, 'memory_size', status=st)
        write(*,'(A,I0,A,I0)') '    max_buffer_length ', maxbuf, ', memory_size ', memsize
        call assert_true(st == 0 .and. memsize > 0_int64, 'a present size key gives its value with status 0')
        call assert_true(len(mlx_device_info_string(MLX_DEVICES%gpu, 'architecture')) > 0, 'the GPU reports its architecture')
        call assert_true(maxbuf > 0_int64 .and. maxbuf <= memsize, &
            &'the GPU reports a maximum buffer length no larger than its memory')
        n = mlx_device_info_size(MLX_DEVICES%gpu, 'no_such_key', status=st)
        call assert_true(n == -1_int64 .and. st == 0, 'an absent size key gives -1 with status 0')
        str = mlx_device_info_string(MLX_DEVICES%gpu, 'no_such_key', status=st)
        call assert_true(len(str) == 0 .and. st == 0, 'an absent string key gives an empty string with status 0')
    end subroutine test_device_info

end module mlxf_device_tester
