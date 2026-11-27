!@descr: reductions, scans, softmax and extremum positions through the array signature helpers
! A reduction takes one dimension (dim), a list (dims) or neither (every dimension); keepdims keeps the reduced
! dimensions with extent 1. Positions are 1-based int32, and the position in a whole array is its subscripts.
module mlxf_ops_reduce
use, intrinsic :: iso_c_binding,   only: c_bool, c_int, c_size_t
use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
use mlxf_c_array,         only: mlxc_array_new, mlxc_array_free, mlxc_array_dtype
use mlxf_c_ops,           only: mlxc_add, mlxc_floor_divide, mlxc_remainder, mlxc_stack, mlxc_argmax, mlxc_argmax_axis, &
                                mlxc_argmin, mlxc_argmin_axis, mlxc_softmax, mlxc_softmax_axes, mlxc_softmax_axis, &
                                mlxc_all, mlxc_all_axes, mlxc_all_axis, mlxc_any, mlxc_any_axes, mlxc_any_axis, &
                                mlxc_count_nonzero, mlxc_count_nonzero_axes, mlxc_count_nonzero_axis, mlxc_cummax, &
                                mlxc_cummax_axis, mlxc_cummin, mlxc_cummin_axis, mlxc_cumprod, mlxc_cumprod_axis, &
                                mlxc_cumsum, mlxc_cumsum_axis, mlxc_logcumsumexp, mlxc_logcumsumexp_axis, &
                                mlxc_logsumexp, mlxc_logsumexp_axes, mlxc_logsumexp_axis, mlxc_max, mlxc_max_axes, &
                                mlxc_max_axis, mlxc_mean, mlxc_mean_axes, mlxc_mean_axis, mlxc_median, &
                                mlxc_median_axes, mlxc_median_axis, mlxc_min, mlxc_min_axes, mlxc_min_axis, mlxc_prod, &
                                mlxc_prod_axes, mlxc_prod_axis, mlxc_std, mlxc_std_axes, mlxc_std_axis, mlxc_sum, &
                                mlxc_sum_axes, mlxc_sum_axis, mlxc_var, mlxc_var_axes, mlxc_var_axis
use mlxf_c_signatures,    only: mlxc_reduce_op, mlxc_scan_all_op, mlxc_scan_op, mlxc_scan_plain_all_op, &
                                mlxc_scan_plain_op, mlxc_var_all_op, mlxc_var_dims_op, mlxc_var_op
use mlxf_c_stream,        only: mlxc_stream_free
use mlxf_c_types,         only: mlxc_array, mlxc_stream, mlxc_optional_dtype
use mlxf_defs,            only: MLX_DTYPES, mlxf_reduce_spec, mlxf_scan_spec
use mlxf_error,           only: mlxf_fail, mlxf_check
use mlxf_device,          only: mlxf_enter, mlxf_require_device, mlxf_default_stream
use mlxf_array,           only: mlx_array, mlxf_handle, mlxf_adopt
use mlxf_ops_elementwise, only: mlx_astype, merge, real, aimag, max
use mlxf_ops_math,        only: abs, mlx_stop_gradient
use mlxf_ops_logic,       only: mlx_isfinite
use mlxf_ops_create,      only: mlx_full, mlx_ones_like
use mlxf_ops_shape,       only: mlx_zeros, mlx_squeeze
use mlxf_calls,           only: mlxf_check_dim, mlxf_axes_of, mlxf_binary, mlxf_list_op, mlxf_one_based, &
                                mlxf_reduce_all_op, mlxf_reduce_dims_op
use mlxf_transfer,        only: mlx_from
implicit none

public :: sum, minval, mlx_logsumexp, mlx_cumsum, minloc, product, maxval, all, any, count, maxloc, mlx_mean, &
    &mlx_median, mlx_var, mlx_std, mlx_cumprod, mlx_cummax, mlx_cummin, mlx_logcumsumexp, mlx_softmax, mlxf_reduce_scale, &
    &mlxf_reduced_dims, mlxf_empty_reduction, mlxf_scaled_reduction
private

interface sum
    module procedure sum_array, sum_dims
end interface sum

interface product
    module procedure product_array, product_dims
end interface product

interface maxval
    module procedure maxval_array, maxval_dims
end interface maxval

interface minval
    module procedure minval_array, minval_dims
end interface minval

interface all
    module procedure all_array, all_dims
end interface all

interface any
    module procedure any_array, any_dims
end interface any

interface count
    module procedure count_array, count_dims
end interface count

interface mlx_mean
    module procedure mean_array, mean_dims
end interface mlx_mean

interface mlx_median
    module procedure median_array, median_dims
end interface mlx_median

interface mlx_logsumexp
    module procedure logsumexp_array, logsumexp_dims
end interface mlx_logsumexp

interface mlx_var
    module procedure var_array, var_dims
end interface mlx_var

interface mlx_std
    module procedure std_array, std_dims
end interface mlx_std

interface minloc
    module procedure minloc_array, minloc_all
end interface minloc

interface maxloc
    module procedure maxloc_array, maxloc_all
end interface maxloc

interface mlx_softmax
    module procedure softmax_array, softmax_dims
end interface mlx_softmax

contains

    ! Fortran's sum: along dim, or over every dimension without it
    function sum_array( a, dim, keepdims ) result(r)
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
    function sum_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('sum')
        call mlxf_reduce_dims_op(r, mlxc_sum_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'sum')
    end function sum_dims

    ! Fortran's product: along dim, or over every dimension without it
    function product_array( a, dim, keepdims ) result(r)
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
    function product_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('product')
        call mlxf_reduce_dims_op(r, mlxc_prod_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'product')
    end function product_dims

    ! Fortran's maxval: along dim, or over every dimension without it
    function maxval_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('maxval')
        if( mlxf_empty_reduction(a, mlxf_reduced_dims(a, dim=dim)) )then
            r = extremum_identity(a, mlxf_reduced_dims(a, dim=dim), keepdims, .true.)
            return
        endif
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_max_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'maxval')
        else
            call mlxf_reduce_all_op(r, mlxc_max, a, reduce_spec(keepdims=keepdims), 'maxval')
        endif
    end function maxval_array

    ! maxval over the dimensions dims
    function maxval_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('maxval')
        if( mlxf_empty_reduction(a, dims) )then
            r = extremum_identity(a, dims, keepdims, .true.)
            return
        endif
        call mlxf_reduce_dims_op(r, mlxc_max_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'maxval')
    end function maxval_dims

    ! Fortran's minval: along dim, or over every dimension without it
    function minval_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('minval')
        if( mlxf_empty_reduction(a, mlxf_reduced_dims(a, dim=dim)) )then
            r = extremum_identity(a, mlxf_reduced_dims(a, dim=dim), keepdims, .false.)
            return
        endif
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_min_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'minval')
        else
            call mlxf_reduce_all_op(r, mlxc_min, a, reduce_spec(keepdims=keepdims), 'minval')
        endif
    end function minval_array

    ! minval over the dimensions dims
    function minval_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('minval')
        if( mlxf_empty_reduction(a, dims) )then
            r = extremum_identity(a, dims, keepdims, .false.)
            return
        endif
        call mlxf_reduce_dims_op(r, mlxc_min_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'minval')
    end function minval_dims

    ! Fortran's all, a nonzero element counting as true: along dim, or over every dimension without it
    function all_array( a, dim, keepdims ) result(r)
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
    function all_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('all')
        call mlxf_reduce_dims_op(r, mlxc_all_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'all')
    end function all_dims

    ! Fortran's any, a nonzero element counting as true: along dim, or over every dimension without it
    function any_array( a, dim, keepdims ) result(r)
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
    function any_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('any')
        call mlxf_reduce_dims_op(r, mlxc_any_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'any')
    end function any_dims

    ! Fortran's count of the true (nonzero) elements, int32: along dim, or over every dimension without it
    function count_array( a, dim, keepdims ) result(r)
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
    function count_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('count')
        call mlxf_reduce_dims_op(r, mlxc_count_nonzero_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'count')
    end function count_dims

    ! the arithmetic mean: along dim, or over every dimension without it
    function mean_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        type(mlx_array) :: x
        call mlxf_enter('mlx_mean')
        x = statistic_operand(a, 'mlx_mean')
        if( mlxf_scaled_reduction(a, mlxf_reduced_dims(a, dim=dim)) )then
            r = scaled_mean(x, mlxf_reduced_dims(a, dim=dim), keepdims)
            return
        endif
        if( present(dim) )then
            call mlxf_reduce_op(r, mlxc_mean_axis, x, reduce_spec(dim=dim, keepdims=keepdims), 'mlx_mean')
        else
            call mlxf_reduce_all_op(r, mlxc_mean, x, reduce_spec(keepdims=keepdims), 'mlx_mean')
        endif
    end function mean_array

    ! mlx_mean over the dimensions dims
    function mean_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        type(mlx_array) :: x
        call mlxf_enter('mlx_mean')
        x = statistic_operand(a, 'mlx_mean')
        if( mlxf_scaled_reduction(a, dims) )then
            r = scaled_mean(x, dims, keepdims)
            return
        endif
        call mlxf_reduce_dims_op(r, mlxc_mean_axes, x, reduce_spec(dims=dims, keepdims=keepdims), 'mlx_mean')
    end function mean_dims

    ! the median, the mean of the two middle elements of an even count: along dim, or over every dimension without it
    function median_array( a, dim, keepdims ) result(r)
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
    function median_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_median')
        call mlxf_reduce_dims_op(r, mlxc_median_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'mlx_median')
    end function median_dims

    ! log(sum(exp(a))), computed stably by MLX: along dim, or over every dimension without it
    function logsumexp_array( a, dim, keepdims ) result(r)
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
    function logsumexp_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_logsumexp')
        call mlxf_reduce_dims_op(r, mlxc_logsumexp_axes, a, reduce_spec(dims=dims, keepdims=keepdims), 'mlx_logsumexp')
    end function logsumexp_dims

    ! the variance, its divisor the count less ddof (0 by default): along dim, or over every dimension without it
    function var_array( a, dim, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        type(mlx_array) :: x
        call mlxf_enter('mlx_var')
        x = statistic_operand(a, 'mlx_var')
        if( present(dim) )then
            call mlxf_var_op(r, mlxc_var_axis, x, reduce_spec(dim=dim, keepdims=keepdims, ddof=ddof), 'mlx_var')
        else
            call mlxf_var_all_op(r, mlxc_var, x, reduce_spec(keepdims=keepdims, ddof=ddof), 'mlx_var')
        endif
    end function var_array

    ! mlx_var over the dimensions dims
    function var_dims( a, dims, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        type(mlx_array) :: x
        call mlxf_enter('mlx_var')
        x = statistic_operand(a, 'mlx_var')
        call mlxf_var_dims_op(r, mlxc_var_axes, x, reduce_spec(dims=dims, keepdims=keepdims, ddof=ddof), 'mlx_var')
    end function var_dims

    ! the standard deviation, the square root of mlx_var: along dim, or over every dimension without it
    function std_array( a, dim, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        type(mlx_array) :: x
        call mlxf_enter('mlx_std')
        x = statistic_operand(a, 'mlx_std')
        if( present(dim) )then
            call mlxf_var_op(r, mlxc_std_axis, x, reduce_spec(dim=dim, keepdims=keepdims, ddof=ddof), 'mlx_std')
        else
            call mlxf_var_all_op(r, mlxc_std, x, reduce_spec(keepdims=keepdims, ddof=ddof), 'mlx_std')
        endif
    end function std_array

    ! mlx_std over the dimensions dims
    function std_dims( a, dims, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
        type(mlx_array) :: x
        call mlxf_enter('mlx_std')
        x = statistic_operand(a, 'mlx_std')
        call mlxf_var_dims_op(r, mlxc_std_axes, x, reduce_spec(dims=dims, keepdims=keepdims, ddof=ddof), 'mlx_std')
    end function std_dims

    ! the operand of mlx_mean, mlx_var and mlx_std: an integer or boolean array converted to float32 first, since
    ! MLX sums such input in its own kind, where a large total wraps; a floating or complex array is a itself
    function statistic_operand( a, proc ) result(x)
        type(mlx_array),  intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlx_array) :: x
        integer         :: k
        k = int(mlxc_array_dtype(mlxf_handle(a, proc)))
        if( any(k == [MLX_DTYPES%bool, MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, &
            &MLX_DTYPES%uint8, MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64]) )then
            x = mlx_astype(a, MLX_DTYPES%float32)
        else
            x = a
        endif
    end function statistic_operand

    ! the mean of a floating or complex x over the Fortran dimensions dims (kept when keepdims): s*mean(x/s), s the
    ! largest magnitude, so that no partial sum overflows; the plain mean where s is zero or not finite
    function scaled_mean( x, dims, keepdims ) result(r)
        type(mlx_array),   intent(in) :: x
        integer,           intent(in) :: dims(:)
        logical, optional, intent(in) :: keepdims
        type(mlx_array) :: r
        type(mlx_array) :: s, ok, scaled, plain, xs
        call mlxf_reduce_scale(x, dims, s, ok)
        xs = x/s
        call mlxf_reduce_dims_op(scaled, mlxc_mean_axes, xs, reduce_spec(dims=dims, keepdims=.true.), 'mlx_mean')
        call mlxf_reduce_dims_op(plain, mlxc_mean_axes, x, reduce_spec(dims=dims, keepdims=.true.), 'mlx_mean')
        r = merge(scaled*s, plain, ok)
        if( .not. chosen_flag(keepdims) ) r = mlx_squeeze(r, dims)
    end function scaled_mean

    ! the scale of a reduction over dims (kept): the largest magnitude (of the real and imaginary parts of a complex
    ! array), its gradient stopped; ok where it is finite and positive, and s is 1 elsewhere, a safe divisor
    subroutine mlxf_reduce_scale( a, dims, s, ok )
        type(mlx_array), intent(in)  :: a
        integer,         intent(in)  :: dims(:)
        type(mlx_array), intent(out) :: s, ok
        type(mlx_array) :: m
        if( a%kind() == MLX_DTYPES%complex64 )then
            m = max(maxval(abs(real(a)), dims, keepdims=.true.), maxval(abs(aimag(a)), dims, keepdims=.true.))
        else
            m = maxval(abs(a), dims, keepdims=.true.)
        endif
        m = mlx_stop_gradient(m)
        ok = mlx_isfinite(m) .and. m > 0._real32
        s = merge(m, mlx_ones_like(m), ok)
    end subroutine mlxf_reduce_scale

    ! the Fortran dimensions a reduction takes: dim, the list dims, or every dimension of a
    function mlxf_reduced_dims( a, dim, dims ) result(rd)
        type(mlx_array),   intent(in) :: a
        integer, optional, intent(in) :: dim, dims(:)
        integer, allocatable :: rd(:)
        integer              :: i
        if( present(dim) )then
            rd = [dim]
        else if( present(dims) )then
            rd = dims
        else
            rd = [(i, i = 1, a%ndim())]
        endif
    end function mlxf_reduced_dims

    ! whether a reduction of a over the Fortran dimensions rd takes an extent of zero (false for an invalid list)
    logical function mlxf_empty_reduction( a, rd )
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: rd(:)
        integer, allocatable :: sh(:)
        sh = a%shape()
        mlxf_empty_reduction = .false.
        if( any(rd < 1 .or. rd > size(sh)) ) return
        mlxf_empty_reduction = any(sh(rd) == 0)
    end function mlxf_empty_reduction

    ! maxval (low) or minval over an extent of zero, as Fortran: the most negative or the largest finite value of a's
    ! kind (false or true for booleans), in the reduction's shape (dimensions removed, or kept with extent 1)
    function extremum_identity( a, rd, keepdims, low ) result(r)
        type(mlx_array),   intent(in) :: a
        integer,           intent(in) :: rd(:)
        logical, optional, intent(in) :: keepdims
        logical,           intent(in) :: low
        type(mlx_array)      :: r, v
        integer, allocatable :: sh(:)
        integer              :: k
        logical, allocatable :: kept(:)
        k = a%kind()
        select case( k )
            case( MLX_DTYPES%float32 )
                v = mlx_from(merge(-huge(1._real32), huge(1._real32), low))
            case( MLX_DTYPES%float64 )
                v = mlx_from(merge(-huge(1._real64), huge(1._real64), low))
            case( MLX_DTYPES%float16, MLX_DTYPES%bfloat16 )
                v = mlx_astype(mlx_from(merge(-1._real32, 1._real32, low)*merge(65504._real32, 3.38953139e38_real32, &
                    &k == MLX_DTYPES%float16)), k)
            case( MLX_DTYPES%int8 )
                v = mlx_from(merge(-huge(1_int8)-1_int8, huge(1_int8), low))
            case( MLX_DTYPES%int16 )
                v = mlx_from(merge(-huge(1_int16)-1_int16, huge(1_int16), low))
            case( MLX_DTYPES%int32 )
                v = mlx_from(merge(-huge(1_int32)-1_int32, huge(1_int32), low))
            case( MLX_DTYPES%int64 )
                v = mlx_from(merge(-huge(1_int64)-1_int64, huge(1_int64), low))
            case( MLX_DTYPES%uint8, MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64, MLX_DTYPES%bool )
                ! 0 (false), or -1 converted: all bits set (true)
                v = mlx_astype(mlx_from(merge(0_int64, -1_int64, low)), k)
            case default
                if( low )then
                    call mlxf_reduce_dims_op(r, mlxc_max_axes, a, reduce_spec(dims=rd, keepdims=keepdims), 'maxval')
                else
                    call mlxf_reduce_dims_op(r, mlxc_min_axes, a, reduce_spec(dims=rd, keepdims=keepdims), 'minval')
                endif
                return
        end select
        sh = a%shape()
        allocate(kept(size(sh)), source=.true.)
        kept(rd) = .false.
        if( chosen_flag(keepdims) )then
            sh = merge(sh, 1, kept)
        else
            sh = pack(sh, kept)
        endif
        r = mlx_full(sh, v, k)
    end function extremum_identity

    ! whether a reduction of a over the Fortran dimensions rd is scaled: a floating or complex kind, a valid list of
    ! distinct dimensions over nonzero extents (the plain form refuses an invalid list under the wrapper's name)
    logical function mlxf_scaled_reduction( a, rd )
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: rd(:)
        integer :: i
        mlxf_scaled_reduction = .false.
        if( size(rd) == 0 ) return
        if( any(rd < 1) ) return
        if( any(rd > a%ndim()) ) return
        do i = 2, size(rd)
            if( any(rd(i) == rd(1:i-1)) ) return
        end do
        if( .not. any(a%kind() == [MLX_DTYPES%float16, MLX_DTYPES%bfloat16, MLX_DTYPES%float32, MLX_DTYPES%float64, &
            &MLX_DTYPES%complex64]) ) return
        mlxf_scaled_reduction = .not. mlxf_empty_reduction(a, rd)
    end function mlxf_scaled_reduction

    ! an optional flag, false when absent
    logical function chosen_flag( flag )
        logical, optional, intent(in) :: flag
        chosen_flag = .false.
        if( present(flag) ) chosen_flag = flag
    end function chosen_flag

    ! the running sum along dim; without dim, of the elements in array element order, rank 1.
    ! reverse scans from the last element; an exclusive scan leaves each element out of its own result
    function mlx_cumsum( a, dim, reverse, inclusive ) result(r)
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
    function mlx_cumprod( a, dim, reverse, inclusive ) result(r)
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
    function mlx_cummax( a, dim, reverse, inclusive ) result(r)
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
    function mlx_cummin( a, dim, reverse, inclusive ) result(r)
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
    function mlx_logcumsumexp( a, dim, reverse, inclusive ) result(r)
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
    function softmax_array( a, dim, precise ) result(r)
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
    function softmax_dims( a, dims, precise ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: precise
        type(mlx_array) :: r
        call mlxf_enter('mlx_softmax')
        call mlxf_reduce_dims_op(r, mlxc_softmax_axes, a, reduce_spec(dims=dims, keepdims=precise), 'mlx_softmax')
    end function softmax_dims

    ! Fortran's maxloc(a, dim): 1-based int32 positions, the first on ties
    function maxloc_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('maxloc')
        call loc_along(r, mlxc_argmax_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'maxloc')
    end function maxloc_array

    ! Fortran's maxloc(a): the subscripts of the first maximum in array element order, a rank-1 int32 array
    function maxloc_all( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_enter('maxloc')
        call loc_whole(r, mlxc_argmax, a, 'maxloc')
    end function maxloc_all

    ! Fortran's minloc(a, dim): 1-based int32 positions, the first on ties
    function minloc_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('minloc')
        call loc_along(r, mlxc_argmin_axis, a, reduce_spec(dim=dim, keepdims=keepdims), 'minloc')
    end function minloc_array

    ! Fortran's minloc(a): the subscripts of the first minimum in array element order, a rank-1 int32 array
    function minloc_all( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_enter('minloc')
        call loc_whole(r, mlxc_argmin, a, 'minloc')
    end function minloc_all

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
        call mlxf_one_based(r, idx, proc)
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

    ! r = f(a) along Fortran dimension option%dim (MLX axis rank - dim), which the result loses unless
    ! option%keepdims, for every int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, const mlx_stream s)
    subroutine mlxf_reduce_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_reduce_op)             :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call mlxf_check_dim(a, option%dim, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_reduce_op

    ! the scan of a along Fortran dimension option%dim, in its dtype, reversed or exclusive as option says, for every
    ! int f(mlx_array* res, const mlx_array a, int axis, bool reverse, bool inclusive, mlx_optional_dtype
    ! dtype, const mlx_stream s)
    subroutine mlxf_scan_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_op)             :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)          :: ha
        type(mlxc_optional_dtype) :: dtype
        type(mlxc_array)          :: res
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call mlxf_check_dim(a, option%dim, proc)
        dtype%has_value = .false._c_bool
        dtype%value = 0_c_int
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%reverse, c_bool), logical(option%inclusive, c_bool), dtype, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_scan_op

    ! r = f(a) over every dimension with option%ddof delta degrees of freedom, for every
    ! int f(mlx_array* res, const mlx_array a, bool keepdims, int ddof, const mlx_stream s)
    subroutine mlxf_var_all_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_var_all_op)            :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, logical(option%keepdims, c_bool), int(option%ddof, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_var_all_op

    ! r = f(a) along Fortran dimension option%dim with option%ddof delta degrees of freedom, for every
    ! int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, int ddof, const mlx_stream s)
    subroutine mlxf_var_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_var_op)                :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call mlxf_check_dim(a, option%dim, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%keepdims, c_bool), int(option%ddof, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_var_op

    ! r = f(a) over the Fortran dimensions option%dims with option%ddof delta degrees of freedom, for every
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool keepdims, int ddof,
    ! const mlx_stream s)
    subroutine mlxf_var_dims_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_var_dims_op)           :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)            :: ha
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:)
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        axes = mlxf_axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, axes, int(size(axes), c_size_t), logical(option%keepdims, c_bool), int(option%ddof, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_var_dims_op

    ! the scan of a in array element order, a rank-1 result in a's dtype, for every int f(mlx_array* res,
    ! const mlx_array a, bool reverse, bool inclusive, mlx_optional_dtype dtype, const mlx_stream s)
    subroutine mlxf_scan_all_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_all_op)         :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)          :: ha
        type(mlxc_array)          :: res
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        type(mlxc_optional_dtype) :: dtype
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        dtype%has_value = .false._c_bool
        dtype%value = 0_c_int
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, logical(option%reverse, c_bool), logical(option%inclusive, c_bool), dtype, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_scan_all_op

    ! the scan of a along Fortran dimension option%dim, for every int f(mlx_array* res, const mlx_array a,
    ! int axis, bool reverse, bool inclusive, const mlx_stream s)
    subroutine mlxf_scan_plain_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_plain_op)       :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call mlxf_check_dim(a, option%dim, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%reverse, c_bool), logical(option%inclusive, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_scan_plain_op

    ! the scan of a in array element order, a rank-1 result, for every int f(mlx_array* res,
    ! const mlx_array a, bool reverse, bool inclusive, const mlx_stream s)
    subroutine mlxf_scan_plain_all_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_plain_all_op)   :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, logical(option%reverse, c_bool), logical(option%inclusive, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_scan_plain_all_op

end module mlxf_ops_reduce
