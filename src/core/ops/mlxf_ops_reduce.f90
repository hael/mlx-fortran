!@descr: reductions, scans, softmax and extremum positions through the array signature helpers
! A reduction takes one dimension (dim), a list (dims) or neither (every dimension); keepdims keeps the reduced
! dimensions with extent 1. Positions are 1-based int32, and the position in a whole array is its subscripts.
submodule(mlxf_ops) mlxf_ops_reduce
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_ops,  only: mlxc_add, mlxc_argmax, mlxc_argmax_axis, mlxc_argmin, mlxc_argmin_axis, mlxc_floor_divide, &
                       mlxc_remainder, mlxc_softmax, mlxc_softmax_axes, mlxc_softmax_axis, mlxc_stack, mlxc_all, &
                       mlxc_all_axes, mlxc_all_axis, mlxc_any, mlxc_any_axes, mlxc_any_axis, mlxc_count_nonzero, &
                       mlxc_count_nonzero_axes, mlxc_count_nonzero_axis, mlxc_cummax, mlxc_cummax_axis, mlxc_cummin, &
                       mlxc_cummin_axis, mlxc_cumprod, mlxc_cumprod_axis, mlxc_cumsum, mlxc_cumsum_axis, &
                       mlxc_logcumsumexp, mlxc_logcumsumexp_axis, mlxc_logsumexp, mlxc_logsumexp_axes, &
                       mlxc_logsumexp_axis, mlxc_max, mlxc_max_axes, mlxc_max_axis, mlxc_mean, mlxc_mean_axes, &
                       mlxc_mean_axis, mlxc_median, mlxc_median_axes, mlxc_median_axis, mlxc_min, mlxc_min_axes, &
                       mlxc_min_axis, mlxc_prod, mlxc_prod_axes, mlxc_prod_axis, mlxc_std, mlxc_std_axes, &
                       mlxc_std_axis, mlxc_sum, mlxc_sum_axes, mlxc_sum_axis, mlxc_var, mlxc_var_axes, mlxc_var_axis
use mlxf_defs,   only: MLX_DTYPES, mlxf_reduce_spec, mlxf_scan_spec
use mlxf_array,  only: mlx_from, mlxf_binary, mlxf_list_op, mlxf_reduce_all_op, mlxf_reduce_dims_op, mlxf_reduce_op, &
                       mlxf_scan_all_op, mlxf_scan_op, mlxf_scan_plain_all_op, mlxf_scan_plain_op, mlxf_var_all_op, &
                       mlxf_var_dims_op, mlxf_var_op
use mlxf_device, only: mlxf_enter
use mlxf_error,  only: mlxf_fail
implicit none

contains

    ! Fortran's sum: along dim, or over every dimension without it
    module function sum_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('sum')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_sum_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'sum')
        else
            call mlxf_reduce_all_op(r, mlxc_sum, a, reduce_spec(keepdims=keepdims), 'sum')
        endif
    end function sum_array

    ! sum over the dimensions dims
    module function sum_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('sum')
        call mlxf_reduce_dims_op(r, mlxc_sum_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'sum')
    end function sum_dims

    ! Fortran's product: along dim, or over every dimension without it
    module function product_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('product')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_prod_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'product')
        else
            call mlxf_reduce_all_op(r, mlxc_prod, a, reduce_spec(keepdims=keepdims), 'product')
        endif
    end function product_array

    ! product over the dimensions dims
    module function product_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('product')
        call mlxf_reduce_dims_op(r, mlxc_prod_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'product')
    end function product_dims

    ! Fortran's maxval: along dim, or over every dimension without it
    module function maxval_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('maxval')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_max_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'maxval')
        else
            call mlxf_reduce_all_op(r, mlxc_max, a, reduce_spec(keepdims=keepdims), 'maxval')
        endif
    end function maxval_array

    ! maxval over the dimensions dims
    module function maxval_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('maxval')
        call mlxf_reduce_dims_op(r, mlxc_max_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'maxval')
    end function maxval_dims

    ! Fortran's minval: along dim, or over every dimension without it
    module function minval_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('minval')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_min_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'minval')
        else
            call mlxf_reduce_all_op(r, mlxc_min, a, reduce_spec(keepdims=keepdims), 'minval')
        endif
    end function minval_array

    ! minval over the dimensions dims
    module function minval_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('minval')
        call mlxf_reduce_dims_op(r, mlxc_min_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'minval')
    end function minval_dims

    ! Fortran's all, a nonzero element counting as true: along dim, or over every dimension without it
    module function all_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('all')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_all_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'all')
        else
            call mlxf_reduce_all_op(r, mlxc_all, a, reduce_spec(keepdims=keepdims), 'all')
        endif
    end function all_array

    ! all over the dimensions dims
    module function all_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('all')
        call mlxf_reduce_dims_op(r, mlxc_all_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'all')
    end function all_dims

    ! Fortran's any, a nonzero element counting as true: along dim, or over every dimension without it
    module function any_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('any')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_any_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'any')
        else
            call mlxf_reduce_all_op(r, mlxc_any, a, reduce_spec(keepdims=keepdims), 'any')
        endif
    end function any_array

    ! any over the dimensions dims
    module function any_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('any')
        call mlxf_reduce_dims_op(r, mlxc_any_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'any')
    end function any_dims

    ! Fortran's count of the true (nonzero) elements, int32: along dim, or over every dimension without it
    module function count_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('count')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_count_nonzero_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'count')
        else
            call mlxf_reduce_all_op(r, mlxc_count_nonzero, a, reduce_spec(keepdims=keepdims), 'count')
        endif
    end function count_array

    ! count over the dimensions dims
    module function count_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('count')
        call mlxf_reduce_dims_op(r, mlxc_count_nonzero_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'count')
    end function count_dims

    ! the arithmetic mean: along dim, or over every dimension without it
    module function mean_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_mean')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_mean_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'mlx_mean')
        else
            call mlxf_reduce_all_op(r, mlxc_mean, a, reduce_spec(keepdims=keepdims), 'mlx_mean')
        endif
    end function mean_array

    ! mlx_mean over the dimensions dims
    module function mean_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_mean')
        call mlxf_reduce_dims_op(r, mlxc_mean_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'mlx_mean')
    end function mean_dims

    ! the median, the mean of the two middle elements of an even count: along dim, or over every dimension without it
    module function median_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_median')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_median_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'mlx_median')
        else
            call mlxf_reduce_all_op(r, mlxc_median, a, reduce_spec(keepdims=keepdims), 'mlx_median')
        endif
    end function median_array

    ! mlx_median over the dimensions dims
    module function median_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_median')
        call mlxf_reduce_dims_op(r, mlxc_median_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'mlx_median')
    end function median_dims

    ! log(sum(exp(a))), computed stably by MLX: along dim, or over every dimension without it
    module function logsumexp_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_logsumexp')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_logsumexp_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'mlx_logsumexp')
        else
            call mlxf_reduce_all_op(r, mlxc_logsumexp, a, reduce_spec(keepdims=keepdims), 'mlx_logsumexp')
        endif
    end function logsumexp_array

    ! mlx_logsumexp over the dimensions dims
    module function logsumexp_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_logsumexp')
        call mlxf_reduce_dims_op(r, mlxc_logsumexp_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'mlx_logsumexp')
    end function logsumexp_dims

    ! the variance, its divisor the count less ddof (0 by default): along dim, or over every dimension without it
    module function var_array( a, dim, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        call mlxf_enter('mlx_var')
        if( present(dim) )then
            call mlxf_var_op(r, mlxc_var_axis, a, reduce_spec(dim=dim, keepdims=keepdims, ddof=ddof), 'mlx_var')
        else
            call mlxf_var_all_op(r, mlxc_var, a, reduce_spec(keepdims=keepdims, ddof=ddof), 'mlx_var')
        endif
    end function var_array

    ! mlx_var over the dimensions dims
    module function var_dims( a, dims, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        call mlxf_enter('mlx_var')
        call mlxf_var_dims_op(r, mlxc_var_axes, a, reduce_spec(dims=dims, keepdims=keepdims, ddof=ddof), 'mlx_var')
    end function var_dims

    ! the standard deviation, the square root of mlx_var: along dim, or over every dimension without it
    module function std_array( a, dim, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        call mlxf_enter('mlx_std')
        if( present(dim) )then
            call mlxf_var_op(r, mlxc_std_axis, a, reduce_spec(dim=dim, keepdims=keepdims, ddof=ddof), 'mlx_std')
        else
            call mlxf_var_all_op(r, mlxc_std, a, reduce_spec(keepdims=keepdims, ddof=ddof), 'mlx_std')
        endif
    end function std_array

    ! mlx_std over the dimensions dims
    module function std_dims( a, dims, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        call mlxf_enter('mlx_std')
        call mlxf_var_dims_op(r, mlxc_std_axes, a, reduce_spec(dims=dims, keepdims=keepdims, ddof=ddof), 'mlx_std')
    end function std_dims

    ! the running sum along dim; without dim, of the elements in array element order, rank 1.
    ! reverse scans from the last element; an exclusive scan leaves each element out of its own result
    module function mlx_cumsum( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
        call mlxf_enter('mlx_cumsum')
        if( present(dim) )then
            call mlxf_scan_op(r, mlxc_cumsum_axis, a, scan_spec(dim=dim, reverse=reverse, inclusive=inclusive), 'mlx_cumsum')
        else
            call mlxf_scan_all_op(r, mlxc_cumsum, a, scan_spec(reverse=reverse, inclusive=inclusive), 'mlx_cumsum')
        endif
    end function mlx_cumsum

    ! the running product along dim; without dim, of the elements in array element order, rank 1.
    ! reverse scans from the last element; an exclusive scan leaves each element out of its own result
    module function mlx_cumprod( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
        call mlxf_enter('mlx_cumprod')
        if( present(dim) )then
            call mlxf_scan_op(r, mlxc_cumprod_axis, a, scan_spec(dim=dim, reverse=reverse, inclusive=inclusive), 'mlx_cumprod')
        else
            call mlxf_scan_all_op(r, mlxc_cumprod, a, scan_spec(reverse=reverse, inclusive=inclusive), 'mlx_cumprod')
        endif
    end function mlx_cumprod

    ! the running maximum along dim; without dim, of the elements in array element order, rank 1.
    ! reverse scans from the last element; an exclusive scan leaves each element out of its own result
    module function mlx_cummax( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
        call mlxf_enter('mlx_cummax')
        if( present(dim) )then
            call mlxf_scan_plain_op(r, mlxc_cummax_axis, a, scan_spec(dim=dim, reverse=reverse, inclusive=inclusive), 'mlx_cummax')
        else
            call mlxf_scan_plain_all_op(r, mlxc_cummax, a, scan_spec(reverse=reverse, inclusive=inclusive), 'mlx_cummax')
        endif
    end function mlx_cummax

    ! the running minimum along dim; without dim, of the elements in array element order, rank 1.
    ! reverse scans from the last element; an exclusive scan leaves each element out of its own result
    module function mlx_cummin( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
        call mlxf_enter('mlx_cummin')
        if( present(dim) )then
            call mlxf_scan_plain_op(r, mlxc_cummin_axis, a, scan_spec(dim=dim, reverse=reverse, inclusive=inclusive), 'mlx_cummin')
        else
            call mlxf_scan_plain_all_op(r, mlxc_cummin, a, scan_spec(reverse=reverse, inclusive=inclusive), 'mlx_cummin')
        endif
    end function mlx_cummin

    ! the running log(sum(exp(a))) (MLX's stable form) along dim; without dim, of the elements in array element order, rank 1.
    ! reverse scans from the last element; an exclusive scan leaves each element out of its own result
    module function mlx_logcumsumexp( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
        call mlxf_enter('mlx_logcumsumexp')
        if( present(dim) )then
            call mlxf_scan_plain_op(r, mlxc_logcumsumexp_axis, a, scan_spec(dim=dim, reverse=reverse, inclusive=inclusive), 'mlx_logcumsumexp')
        else
            call mlxf_scan_plain_all_op(r, mlxc_logcumsumexp, a, scan_spec(reverse=reverse, inclusive=inclusive), 'mlx_logcumsumexp')
        endif
    end function mlx_logcumsumexp

    ! the softmax along dim, dimension 1 when it is absent; precise computes it in a more stable, slower form
    module function softmax_array( a, dim, precise ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: precise
        type(mlx_array) :: r
        call mlxf_enter('mlx_softmax')
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_softmax_axis, a, reduce_spec(dim=dim, keepdims=precise), 'mlx_softmax')
        else if( a%ndim() > 1 )then
            call mlxf_reduce_op(r, mlxc_softmax_axis, a, reduce_spec(dim=1, keepdims=precise), 'mlx_softmax')
        else
            call mlxf_reduce_all_op(r, mlxc_softmax, a, reduce_spec(keepdims=precise), 'mlx_softmax')
        endif
    end function softmax_array

    ! the softmax over the dimensions dims jointly
    module function softmax_dims( a, dims, precise ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: precise
        type(mlx_array) :: r
        call mlxf_enter('mlx_softmax')
        call mlxf_reduce_dims_op(r, mlxc_softmax_axes, a, reduce_spec(dims=dims, keepdims=precise), 'mlx_softmax')
    end function softmax_dims

    ! Fortran's maxloc(a, dim): 1-based int32 positions, the first on ties
    module function maxloc_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('maxloc')
        call loc_along(r, mlxc_argmax_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'maxloc')
    end function maxloc_array

    ! Fortran's maxloc(a): the subscripts of the first maximum in array element order, a rank-1 int32 array
    module function maxloc_all( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_enter('maxloc')
        call loc_whole(r, mlxc_argmax, a, 'maxloc')
    end function maxloc_all

    ! Fortran's minloc(a, dim): 1-based int32 positions, the first on ties
    module function minloc_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('minloc')
        call loc_along(r, mlxc_argmin_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'minloc')
    end function minloc_array

    ! Fortran's minloc(a): the subscripts of the first minimum in array element order, a rank-1 int32 array
    module function minloc_all( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_enter('minloc')
        call loc_whole(r, mlxc_argmin, a, 'minloc')
    end function minloc_all

    ! MLX's 0-based positions as Fortran's: int32, one added
    module subroutine index_result( r, idx, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: idx
        character(len=*), intent(in)    :: proc
        type(mlx_array) :: cast, one
        cast = mlx_astype(idx, MLX_DTYPES%int32)
        one = mlx_from(1_int32)
        call mlxf_binary(r, mlxc_add, cast, one, proc)
    end subroutine index_result

    ! the positions of the extremum f finds along option%dim; a zero-size a gives zeros of the reduced shape,
    ! as Fortran does, since MLX's argmin and argmax refuse a zero-size array
    subroutine loc_along( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_argmin_axis)           :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlx_array)      :: idx
        integer, allocatable :: s(:)
        integer              :: i
        if( a%size() == 0 )then
            s = a%shape()
            if( option%dim < 1 .or. option%dim > size(s) ) call mlxf_fail(proc, 'dimension outside array rank')
            if( option%keepdims )then
                s(option%dim) = 1
            else
                s = pack(s, [(i /= option%dim, i=1, size(s))])
            endif
            r = mlx_zeros(s, dtype=MLX_DTYPES%int32)
            return
        endif
        call mlxf_reduce_op(idx, f, a, option, proc)
        call index_result(r, idx, proc)
    end subroutine loc_along

    ! the subscripts of the extremum f finds in the whole array: MLX's position in its row-major order is the
    ! position in Fortran's array element order, which the extents turn into one subscript per dimension
    subroutine loc_whole( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_argmin)          :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlx_array), allocatable :: subs(:)
        type(mlx_array)              :: idx, pos, step, extent, quotient, rest, one, stacked
        integer,         allocatable :: s(:)
        integer(int64)               :: stride
        integer                      :: d, nd
        s = a%shape()
        nd = size(s)
        if( nd == 0 ) call mlxf_fail(proc, 'rank must be at least one')
        if( a%size() == 0 )then
            r = mlx_zeros([nd], dtype=MLX_DTYPES%int32)
            return
        endif
        call mlxf_reduce_all_op(idx, f, a, reduce_spec(), proc)
        pos = mlx_astype(idx, MLX_DTYPES%int64)
        one = mlx_from(1_int64)
        allocate(subs(nd))
        stride = 1_int64
        do d = 1, nd
            step = mlx_from(stride)
            extent = mlx_from(int(s(d), int64))
            call mlxf_binary(quotient, mlxc_floor_divide, pos, step, proc)
            call mlxf_binary(rest, mlxc_remainder, quotient, extent, proc)
            call mlxf_binary(subs(d), mlxc_add, rest, one, proc)
            stride = stride*int(s(d), int64)
        end do
        call mlxf_list_op(stacked, mlxc_stack, subs, proc)
        r = mlx_astype(stacked, MLX_DTYPES%int32)
    end subroutine loc_whole

    ! the record a reduction helper takes, from a wrapper's optional arguments
    function reduce_spec( dim, dims, keepdims, ddof ) result(spec)
        integer, optional, intent(in) :: dim, dims(:), ddof
        logical, optional, intent(in) :: keepdims
        type(mlxf_reduce_spec) :: spec
        if( present(dim) ) spec%dim = dim
        if( present(dims) ) spec%dims = dims
        if( present(keepdims) ) spec%keepdims = keepdims
        if( present(ddof) ) spec%ddof = ddof
    end function reduce_spec

    ! the record a scan helper takes, from a wrapper's optional arguments
    function scan_spec( dim, reverse, inclusive ) result(spec)
        integer, optional, intent(in) :: dim
        logical, optional, intent(in) :: reverse, inclusive
        type(mlxf_scan_spec) :: spec
        if( present(dim) ) spec%dim = dim
        if( present(reverse) ) spec%reverse = reverse
        if( present(inclusive) ) spec%inclusive = inclusive
    end function scan_spec

end submodule mlxf_ops_reduce
