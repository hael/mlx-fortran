!@descr: reduce operations through the array signature helpers
submodule(mlxf_ops) mlxf_ops_reduce
use mlxf_c_ops,  only: mlxc_add, mlxc_argmin_axis, mlxc_cumsum_axis, mlxc_logsumexp_axis, mlxc_min_axis, mlxc_sum_axis
use mlxf_defs,   only: MLX_DTYPES
use mlxf_array,  only: mlx_from, mlxf_binary, mlxf_reduce_op, mlxf_scan_op
use mlxf_device, only: mlxf_enter
use mlxf_error,  only: mlxf_fail
implicit none

contains

    ! Fortran's sum(a, dim), which loses dimension dim
    module function sum_array( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_reduce_op(r, mlxc_sum_axis, a, dim, 'sum')
    end function sum_array

    ! Fortran's minval(a, dim)
    module function minval_array( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_reduce_op(r, mlxc_min_axis, a, dim, 'minval')
    end function minval_array

    ! log(sum(exp(a))) along dim, computed stably by MLX
    module function mlx_logsumexp( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_reduce_op(r, mlxc_logsumexp_axis, a, dim, 'mlx_logsumexp')
    end function mlx_logsumexp

    ! the inclusive running sum along dim
    module function mlx_cumsum( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_scan_op(r, mlxc_cumsum_axis, a, dim, 'mlx_cumsum')
    end function mlx_cumsum

    ! Fortran's minloc(a, dim): 1-based int32 positions, the first on ties; a zero-size a gives zeros of the
    ! reduced shape, as Fortran does, since MLX's argmin refuses a zero-size array
    module function minloc_array( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array)      :: r
        type(mlx_array)      :: idx, cast, one
        integer, allocatable :: s(:)
        integer              :: i
        call mlxf_enter('minloc')
        if( a%size() == 0 )then
            s = a%shape()
            if( dim < 1 .or. dim > size(s) ) call mlxf_fail('minloc', 'dimension outside array rank')
            r = mlx_zeros(pack(s, [(i /= dim, i=1, size(s))]), dtype=MLX_DTYPES%int32)
            return
        endif
        call mlxf_reduce_op(idx, mlxc_argmin_axis, a, dim, 'minloc')
        cast = mlx_astype(idx, MLX_DTYPES%int32)
        one = mlx_from(1_int32)
        call mlxf_binary(r, mlxc_add, cast, one, 'minloc')
    end function minloc_array

end submodule mlxf_ops_reduce
