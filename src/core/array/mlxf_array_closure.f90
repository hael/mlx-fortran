!@descr: checked conversion between C closure vectors and owned Fortran arrays
submodule(mlxf_array) mlxf_array_closure
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_vector, only: mlxc_vector_array_size, mlxc_vector_array_get, mlxc_vector_array_set_data
use mlxf_error,    only: mlxf_check, mlxf_report
implicit none

contains

    ! the arrays of an mlx-c vector, each adopted as a new counted handle; a failure returns a status and
    ! frees the handle it was taking, since the C trampoline must not stop
    module subroutine mlxf_vector_import( arrays, v, status )
        type(mlx_array),         allocatable, intent(out) :: arrays(:)
        type(mlxc_vector_array), intent(in)               :: v
        integer,                 intent(out)              :: status
        type(mlxc_array) :: h
        integer          :: i, n, cleanup
        integer(c_int)   :: ierr
        n = int(mlxc_vector_array_size(v))
        allocate(arrays(n), stat=status)
        if( status /= 0 ) return
        do i = 1, n
            h = mlxc_array_new()
            ierr = mlxc_vector_array_get(h, v, int(i-1, c_size_t))
            call mlxf_check(ierr, 'closure vector import', status=status)
            if( status /= 0 )then
                call mlxf_check(mlxc_array_free(h), 'closure vector import cleanup', status=cleanup)
                return
            endif
            call adopt(arrays(i), h, 'closure vector import')
        end do
    end subroutine mlxf_vector_import

    ! the handles of arrays copied into an mlx-c vector; an empty or stale array returns a status, since
    ! the C trampoline must not stop
    module subroutine mlxf_vector_export( v, arrays, status )
        type(mlxc_vector_array), intent(inout) :: v
        type(mlx_array),         intent(in)    :: arrays(:)
        integer,                 intent(out)   :: status
        type(mlxc_array), allocatable :: hs(:)
        integer                       :: i
        allocate(hs(max(1, size(arrays))), stat=status)
        if( status /= 0 ) return
        do i = 1, size(arrays)
            if( .not. mlx_is_live(arrays(i)) )then
                call mlxf_report('closure vector export', 'callback returned an empty or stale array', status=status)
                return
            endif
            hs(i) = mlxf_handle(arrays(i), 'closure vector export')
        end do
        call mlxf_check(mlxc_vector_array_set_data(v, hs, int(size(arrays), c_size_t)), &
            &'closure vector export', status=status)
    end subroutine mlxf_vector_export

end submodule mlxf_array_closure
