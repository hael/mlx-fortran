!@descr: signature-class helpers of the distributed operations: an array or a shape, a peer, a group that may be absent
! A group handle with a null context is MLX's default group. Ranks arrive as MLX wants them, zero-based. MLX
! exchanges on the CPU only (Metal has no implementation), so the nodes are built on the CPU's default stream
! whatever the default device.
submodule(mlxf_distributed) mlxf_distributed_calls
use, intrinsic :: iso_c_binding, only: c_size_t
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_c_types,  only: mlxc_array, mlxc_stream
use mlxf_calls,    only: mlxf_check_dtype, mlxf_cpu_stream
use mlxf_array,    only: mlxf_adopt, mlxf_handle
implicit none

contains

    ! r = f(a) within option%group, for every int f(mlx_array* res, const mlx_array x,
    ! const mlx_distributed_group group, const mlx_stream s); with status, a failure returns with r empty
    module subroutine mlxf_group_op( r, f, a, option, status )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_group_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_group_spec), intent(in)    :: option
        integer, optional,     intent(out)   :: status
        type(mlxc_array)  :: res, ha
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(option%proc)
        ha = mlxf_handle(a, option%proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(option%proc)
        ierr = f(res, ha, option%group, s)
        call mlxf_check(mlxc_stream_free(s), option%proc)
        call group_done(r, res, ierr, option, status)
    end subroutine mlxf_group_op

    ! r = f(a, option%peer) within option%group, for every int f(mlx_array* res, const mlx_array x, int peer,
    ! const mlx_distributed_group group, const mlx_stream s)
    module subroutine mlxf_group_peer_op( r, f, a, option, status )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_group_peer_op)        :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_group_spec), intent(in)    :: option
        integer, optional,     intent(out)   :: status
        type(mlxc_array)  :: res, ha
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(option%proc)
        ha = mlxf_handle(a, option%proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(option%proc)
        ierr = f(res, ha, int(option%peer, c_int), option%group, s)
        call mlxf_check(mlxc_stream_free(s), option%proc)
        call group_done(r, res, ierr, option, status)
    end subroutine mlxf_group_peer_op

    ! r = f(shape, dtype, option%peer) within option%group, the Fortran shape reversed, for every int
    ! f(mlx_array* res, const int* shape, size_t shape_num, mlx_dtype dtype, int src,
    ! const mlx_distributed_group group, const mlx_stream s)
    module subroutine mlxf_group_recv_op( r, f, option, status )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_group_recv_op)        :: f
        type(mlxf_group_spec), intent(in)    :: option
        integer, optional,     intent(out)   :: status
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(option%proc)
        call mlxf_check_dtype(option%dtype, option%proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(option%proc)
        ierr = f(res, int(option%shape(size(option%shape):1:-1), c_int), int(size(option%shape), c_size_t), &
            &int(option%dtype, c_int), int(option%peer, c_int), option%group, s)
        call mlxf_check(mlxc_stream_free(s), option%proc)
        call group_done(r, res, ierr, option, status)
    end subroutine mlxf_group_recv_op

    ! after the C call: a failure frees the result and returns the status (or stops without one); success
    ! registers the result
    subroutine group_done( r, res, ierr, option, status )
        type(mlx_array),       intent(inout) :: r
        type(mlxc_array),      intent(inout) :: res
        integer(c_int),        intent(in)    :: ierr
        type(mlxf_group_spec), intent(in)    :: option
        integer, optional,     intent(out)   :: status
        if( ierr /= 0 )then
            call mlxf_check(mlxc_array_free(res), option%proc)
            call mlxf_check(ierr, option%proc, status)
            return
        endif
        call mlxf_adopt(r, res, option%proc, status)
    end subroutine group_done

end submodule mlxf_distributed_calls
