!@descr: evaluation: mlx_eval, mlx_async_eval, mlx_synchronize
submodule (mlxf_array) mlxf_array_evaluation
use mlxf_c_array,      only: mlxc_array_eval
use mlxf_c_transforms, only: mlxc_eval, mlxc_async_eval
use mlxf_c_vector,     only: mlxc_vector_array_new_data, mlxc_vector_array_free
use mlxf_defs,         only: MLX_DEVICES
use mlxf_error,        only: mlxf_check
use mlxf_device,       only: mlxf_enter, mlxf_synchronize_device
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
        v    = vector_of(arrays, 'mlx_eval')
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
        v    = vector_of(arrays, 'mlx_async_eval')
        ierr = mlxc_async_eval(v)
        call mlxf_check(mlxc_vector_array_free(v), 'mlx_async_eval')
        call mlxf_check(ierr, 'mlx_async_eval', status)
    end subroutine async_eval_list

    module function vector_of( arrays, proc ) result(v)
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
    end function vector_of

    ! waits for the work queued on every device present
    module subroutine mlx_synchronize( status )
        integer, optional, intent(out) :: status
        integer :: st
        call mlxf_enter('mlx_synchronize')
        call mlxf_synchronize_device(MLX_DEVICES%cpu, 'mlx_synchronize', st)
        if( st == 0 ) call mlxf_synchronize_device(MLX_DEVICES%gpu, 'mlx_synchronize', st)
        call mlxf_check(int(st, c_int), 'mlx_synchronize', status)
    end subroutine mlx_synchronize

end submodule mlxf_array_evaluation
