!@descr: evaluation and what it settles: mlx_eval, mlx_async_eval, mlx_synchronize, the sizes of an array and of its buffer
submodule (mlxf_array) mlxf_array_evaluation
use mlxf_c_array,      only: mlxc_array_eval, mlxc_array_nbytes, mlxc_array_itemsize
use mlxf_c_memory,     only: mlxc_get_array_buffer_size
use mlxf_c_stream,     only: mlxc_synchronize_default
use mlxf_c_transforms, only: mlxc_eval, mlxc_async_eval
use mlxf_c_vector,     only: mlxc_vector_array_new_data, mlxc_vector_array_free
use mlxf_defs,         only: MLX_DEVICES
use mlxf_error,        only: mlxf_check
use mlxf_device,       only: mlxf_enter, mlxf_synchronize_device, mlx_default_device, mlx_device_count
implicit none

contains

    module subroutine eval_one( a, status )
        type(mlx_array),   intent(in)  :: a
        integer, optional, intent(out) :: status
        call mlxf_enter('mlx_eval')
        call mlxf_check(mlxc_array_eval(mlxf_handle(a, 'mlx_eval')), 'mlx_eval', status)
    end subroutine eval_one

    ! evaluates the arrays together (shared work is done once)
    module subroutine eval_list( arrays, status )
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        type(mlxc_vector_array) :: v
        integer(c_int)          :: ierr
        call mlxf_enter('mlx_eval')
        v    = mlxf_vector_of(arrays, 'mlx_eval')
        ierr = mlxc_eval(v)
        call mlxf_check(mlxc_vector_array_free(v), 'mlx_eval')
        call mlxf_check(ierr, 'mlx_eval', status)
    end subroutine eval_list

    ! queues the evaluation and returns at once; mlx_eval, mlx_to or mlx_view later wait for it
    module subroutine async_eval_one( a, status )
        type(mlx_array),   intent(in)  :: a
        integer, optional, intent(out) :: status
        type(mlx_array) :: one(1)
        call mlxf_enter('mlx_async_eval')
        one(1) = a
        call async_eval_list(one, status)
    end subroutine async_eval_one

    module subroutine async_eval_list( arrays, status )
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        type(mlxc_vector_array) :: v
        integer(c_int)          :: ierr
        call mlxf_enter('mlx_async_eval')
        v    = mlxf_vector_of(arrays, 'mlx_async_eval')
        ierr = mlxc_async_eval(v)
        call mlxf_check(mlxc_vector_array_free(v), 'mlx_async_eval')
        call mlxf_check(ierr, 'mlx_async_eval', status)
    end subroutine async_eval_list

    module function mlxf_vector_of( arrays, proc ) result(v)
        type(mlx_array),  intent(in) :: arrays(:)
        character(len=*), intent(in) :: proc
        type(mlxc_vector_array)       :: v
        type(mlxc_array), allocatable :: hs(:)
        integer                       :: i
        allocate(hs(max(1, size(arrays))))
        do i = 1, size(arrays)
            hs(i) = mlxf_handle(arrays(i), proc)
        end do
        v = mlxc_vector_array_new_data(hs, int(size(arrays), c_size_t))
    end function mlxf_vector_of

    ! waits for the work queued on the default stream of every device present: the default device's, where
    ! operations run, then the other device's. A device type that opens no device has no stream and is skipped
    module subroutine synchronize_all( status )
        integer, optional, intent(out) :: status
        integer :: st, device, other
        call mlxf_enter('mlx_synchronize')
        device = mlx_default_device()
        other = MLX_DEVICES%cpu
        if( device == MLX_DEVICES%cpu ) other = MLX_DEVICES%gpu
        st = 0
        if( mlx_device_count(device) > 0 ) call mlxf_check(mlxc_synchronize_default(), 'mlx_synchronize', status=st)
        if( st == 0 ) call mlxf_synchronize_device(other, 'mlx_synchronize', st)
        call mlxf_check(int(st, c_int), 'mlx_synchronize', status)
    end subroutine synchronize_all

    ! the bytes of the array's elements: its size times the size of one element
    module integer(int64) function array_nbytes( self )
        class(mlx_array), intent(in) :: self
        call mlxf_enter('nbytes')
        array_nbytes = int(mlxc_array_nbytes(mlxf_handle(self, 'nbytes')), int64)
    end function array_nbytes

    ! the bytes of one element
    module integer function array_itemsize( self )
        class(mlx_array), intent(in) :: self
        call mlxf_enter('itemsize')
        array_itemsize = int(mlxc_array_itemsize(mlxf_handle(self, 'itemsize')))
    end function array_itemsize

    ! the bytes of the buffers the arrays hold, after evaluating them (MLX counts evaluated arrays only); with
    ! status, a failure returns -1
    module function mlx_buffer_size( arrays, status ) result(n)
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        integer(int64)          :: n
        type(mlxc_vector_array) :: v
        integer(c_size_t)       :: bytes
        integer(c_int)          :: ierr
        call mlxf_enter('mlx_buffer_size')
        n = -1_int64
        v = mlxf_vector_of(arrays, 'mlx_buffer_size')
        bytes = 0
        ierr = mlxc_eval(v)
        if( ierr == 0 ) ierr = mlxc_get_array_buffer_size(bytes, v)
        call mlxf_check(mlxc_vector_array_free(v), 'mlx_buffer_size')
        call mlxf_check(ierr, 'mlx_buffer_size', status)
        if( ierr == 0 ) n = int(bytes, int64)
    end function mlx_buffer_size

end submodule mlxf_array_evaluation
