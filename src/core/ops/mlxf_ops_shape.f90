!@descr: shape operations through the array signature helpers
submodule(mlxf_ops) mlxf_ops_shape
use mlxf_c_ops,  only: mlxc_arange, mlxc_concatenate_axis, mlxc_reshape, mlxc_slice, mlxc_take_along_axis, &
                       mlxc_transpose_axes, mlxc_zeros
use mlxf_defs,   only: MLX_DTYPES, mlxf_slice_spec, mlxf_range_spec
use mlxf_array,  only: mlx_from, mlxf_concat_op, mlxf_range_op, mlxf_slice_op, mlxf_take_op, mlxf_vector_op, &
                       mlxf_zeros_op
use mlxf_device, only: mlxf_enter
use mlxf_error,  only: mlxf_fail
implicit none

contains

    ! Fortran's column-major reshape: the reversed shape gives MLX's row-major reshape of the same bytes
    module function reshape_array( a, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shape(:)
        type(mlx_array) :: r
        call mlxf_vector_op(r, mlxc_reshape, a, shape(size(shape):1:-1), 'reshape')
    end function reshape_array

    ! dimension i of the result is dimension order(i) of a; order is a permutation of 1 to the rank
    module function mlx_permute( a, order ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: order(:)
        type(mlx_array) :: r
        integer         :: i, nd
        call mlxf_enter('mlx_permute')
        nd = a%ndim()
        if( size(order) /= nd ) call mlxf_fail('mlx_permute', 'order must match rank')
        do i = 1, nd
            if( count(order == i) /= 1 ) call mlxf_fail('mlx_permute', 'order is not a permutation')
        end do
        call mlxf_vector_op(r, mlxc_transpose_axes, a, nd-order(nd:1:-1), 'mlx_permute')
    end function mlx_permute

    ! swaps dimensions 1 and 2, every other dimension a batch
    module function transpose_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array)      :: r
        integer              :: i, nd
        integer, allocatable :: order(:)
        call mlxf_enter('transpose')
        nd = a%ndim()
        if( nd < 2 ) call mlxf_fail('transpose', 'rank must be at least two')
        order = [(i, i=1, nd)]
        order(1:2) = [2, 1]
        call mlxf_vector_op(r, mlxc_transpose_axes, a, nd-order(nd:1:-1), 'transpose')
    end function transpose_array

    ! the arrays joined along Fortran dimension dim; their other extents must agree
    module function mlx_concatenate( arrays, dim ) result(r)
        type(mlx_array), intent(in) :: arrays(:)
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_concat_op(r, mlxc_concatenate_axis, arrays, dim, 'mlx_concatenate')
    end function mlx_concatenate

    ! the section lower:upper:stride of a, inclusive and 1-based per dimension, stride 1 by default
    module function mlx_slice( a, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array)       :: r
        type(mlxf_slice_spec) :: spec
        call mlxf_enter('mlx_slice')
        spec%lower = lower
        spec%upper = upper
        allocate(spec%stride(size(lower)))
        spec%stride = 1
        if( present(stride) ) spec%stride = stride
        call mlxf_slice_op(r, mlxc_slice, a, spec, 'mlx_slice')
    end function mlx_slice

    ! the elements of a at 1-based integer indices along dim; MLX checks no bounds, so an index of 0
    ! wraps to the last element
    module function mlx_take_along_dim( a, indices, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        type(mlx_array) :: shifted, one
        integer         :: dtype
        call mlxf_enter('mlx_take_along_dim')
        dtype = indices%kind()
        if( dtype /= MLX_DTYPES%int32 .and. dtype /= MLX_DTYPES%int64 ) &
            &call mlxf_fail('mlx_take_along_dim', 'indices must be integers')
        one = mlx_from(1_int32)
        shifted = indices-one
        call mlxf_take_op(r, mlxc_take_along_axis, [a, shifted], dim, 'mlx_take_along_dim')
    end function mlx_take_along_dim

    ! a zero array of Fortran shape shape, float32 unless dtype is given
    module function mlx_zeros( shape, dtype ) result(r)
        integer, intent(in)           :: shape(:)
        integer, optional, intent(in) :: dtype
        type(mlx_array) :: r
        integer         :: kind
        call mlxf_enter('mlx_zeros')
        kind = MLX_DTYPES%float32
        if( present(dtype) ) kind = dtype
        call mlxf_zeros_op(r, mlxc_zeros, shape, kind, 'mlx_zeros')
    end function mlx_zeros

    ! start, start + step, ... below stop (stop excluded, as MLX's arange), float32 unless dtype is given
    module function mlx_arange( start, stop, step, dtype ) result(r)
        real(real64), intent(in)           :: start, stop
        real(real64), optional, intent(in) :: step
        integer,      optional, intent(in) :: dtype
        type(mlx_array)       :: r
        type(mlxf_range_spec) :: spec
        call mlxf_enter('mlx_arange')
        spec%start = start
        spec%stop = stop
        if( present(step) ) spec%step = step
        if( present(dtype) ) spec%dtype = dtype
        call mlxf_range_op(r, mlxc_arange, spec, 'mlx_arange')
    end function mlx_arange

end submodule mlxf_ops_shape
