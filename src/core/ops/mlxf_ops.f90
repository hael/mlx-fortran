!@descr: elementwise, shape, index and reduction operations in Fortran conventions
module mlxf_ops
use, intrinsic :: iso_fortran_env, only: real32, real64, int32
use mlxf_array, only: mlx_array
implicit none
public :: real, &
    &aimag, &
    &conjg, &
    &sqrt, &
    &mlx_astype, &
    &mlx_bitcast, &
    &max, &
    &merge, &
    &cmplx, &
    &reshape, &
    &mlx_permute, &
    &transpose, &
    &mlx_concatenate, &
    &mlx_slice, &
    &mlx_take_along_dim, &
    &mlx_take, &
    &sum, &
    &minval, &
    &mlx_logsumexp, &
    &mlx_cumsum, &
    &minloc, &
    &mlx_zeros, &
    &mlx_arange, &
    &abs, &
    &sin, &
    &cos, &
    &tan, &
    &sinh, &
    &cosh, &
    &tanh, &
    &log, &
    &log10, &
    &erf, &
    &asin, &
    &acos, &
    &atan, &
    &asinh, &
    &acosh, &
    &atanh, &
    &floor, &
    &ceiling, &
    &aint, &
    &mlx_sign, &
    &mlx_sigmoid, &
    &mlx_square, &
    &mlx_reciprocal, &
    &mlx_rsqrt, &
    &mlx_expm1, &
    &mlx_log1p, &
    &mlx_log2, &
    &mlx_erfinv, &
    &mlx_degrees, &
    &mlx_radians, &
    &mlx_stop_gradient, &
    &mlx_copy, &
    &mlx_isnan, &
    &mlx_isinf, &
    &mlx_isfinite, &
    &mlx_isposinf, &
    &mlx_isneginf, &
    &mlx_round, &
    &mlx_clip, &
    &mlx_nan_to_num, &
    &atan2, &
    &modulo, &
    &min, &
    &mlx_logaddexp, &
    &mlx_floor_divide, &
    &mlx_divmod, &
    &mlx_isclose, &
    &mlx_allclose, &
    &mlx_array_equal, &
    &iand, &
    &ior, &
    &ieor, &
    &not, &
    &shiftl, &
    &mlx_right_shift, &
    &mlx_ones, &
    &mlx_full, &
    &mlx_zeros_like, &
    &mlx_ones_like, &
    &mlx_full_like, &
    &product, &
    &maxval, &
    &all, &
    &any, &
    &count, &
    &maxloc, &
    &mlx_mean, &
    &mlx_median, &
    &mlx_var, &
    &mlx_std, &
    &mlx_cumprod, &
    &mlx_cummax, &
    &mlx_cummin, &
    &mlx_logcumsumexp, &
    &mlx_softmax, &
    &mlx_sort, &
    &mlx_argsort, &
    &mlx_partition, &
    &mlx_argpartition, &
    &mlx_topk, &
    &mlx_squeeze, &
    &mlx_expand_dims, &
    &mlx_flatten, &
    &mlx_unflatten, &
    &mlx_broadcast_to, &
    &mlx_broadcast_arrays, &
    &mlx_tile, &
    &mlx_repeat, &
    &mlx_pad, &
    &mlx_flip, &
    &cshift, &
    &mlx_movedim, &
    &mlx_swapdims, &
    &mlx_split, &
    &mlx_stack, &
    &mlx_unstack, &
    &mlx_atleast_1d, &
    &mlx_atleast_2d, &
    &mlx_atleast_3d, &
    &mlx_diag, &
    &mlx_diagonal, &
    &mlx_trace, &
    &mlx_tril, &
    &mlx_triu, &
    &mlx_diff, &
    &mlx_as_strided, &
    &mlx_number_of_elements, &
    &mlx_identity, &
    &mlx_eye, &
    &mlx_tri, &
    &mlx_linspace, &
    &mlx_meshgrid, &
    &mlx_bartlett, &
    &mlx_blackman, &
    &mlx_hamming, &
    &mlx_hanning, &
    &mlx_gather, &
    &mlx_scatter, &
    &mlx_scatter_add, &
    &mlx_scatter_max, &
    &mlx_scatter_min, &
    &mlx_scatter_prod, &
    &mlx_put_along_dim, &
    &mlx_masked_scatter, &
    &mlx_searchsorted, &
    &mlx_unique, &
    &mlx_slice_update, &
    &mlx_slice_update_add, &
    &mlx_slice_update_max, &
    &mlx_slice_update_min, &
    &mlx_slice_update_prod
private
interface real
    module procedure real_array
end interface real

interface aimag
    module procedure aimag_array
end interface aimag

interface conjg
    module procedure conjg_array
end interface conjg

interface sqrt
    module procedure sqrt_array
end interface sqrt

interface max
    module procedure max_array, max_ass, max_sas, max_asd, max_sad
end interface max

interface merge
    module procedure merge_array
end interface merge

interface cmplx
    module procedure cmplx_array
end interface cmplx

interface reshape
    module procedure reshape_array
end interface reshape

interface transpose
    module procedure transpose_array
end interface transpose

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

interface mlx_squeeze
    module procedure squeeze_array, squeeze_dims
end interface mlx_squeeze

interface mlx_expand_dims
    module procedure expand_dims_one, expand_dims_list
end interface mlx_expand_dims

interface mlx_pad
    module procedure pad_width, pad_low_high
end interface mlx_pad

interface mlx_flip
    module procedure flip_array, flip_dims
end interface mlx_flip

interface cshift
    module procedure cshift_array, cshift_dims
end interface cshift

interface mlx_slice
    module procedure slice_static, slice_dynamic
end interface mlx_slice

interface mlx_slice_update
    module procedure slice_update_static, slice_update_dynamic
end interface mlx_slice_update

interface mlx_gather
    module procedure gather_list, gather_one
end interface mlx_gather

interface mlx_scatter
    module procedure scatter_list, scatter_one
end interface mlx_scatter

interface mlx_scatter_add
    module procedure scatter_add_list, scatter_add_one
end interface mlx_scatter_add

interface mlx_scatter_max
    module procedure scatter_max_list, scatter_max_one
end interface mlx_scatter_max

interface mlx_scatter_min
    module procedure scatter_min_list, scatter_min_one
end interface mlx_scatter_min

interface mlx_scatter_prod
    module procedure scatter_prod_list, scatter_prod_one
end interface mlx_scatter_prod

interface mlx_split
    module procedure split_equal, split_at
end interface mlx_split

interface abs
    module procedure abs_array
end interface abs

interface sin
    module procedure sin_array
end interface sin

interface cos
    module procedure cos_array
end interface cos

interface tan
    module procedure tan_array
end interface tan

interface sinh
    module procedure sinh_array
end interface sinh

interface cosh
    module procedure cosh_array
end interface cosh

interface tanh
    module procedure tanh_array
end interface tanh

interface log
    module procedure log_array
end interface log

interface log10
    module procedure log10_array
end interface log10

interface erf
    module procedure erf_array
end interface erf

interface asin
    module procedure asin_array
end interface asin

interface acos
    module procedure acos_array
end interface acos

interface atan
    module procedure atan_array
end interface atan

interface asinh
    module procedure asinh_array
end interface asinh

interface acosh
    module procedure acosh_array
end interface acosh

interface atanh
    module procedure atanh_array
end interface atanh

interface floor
    module procedure floor_array
end interface floor

interface ceiling
    module procedure ceiling_array
end interface ceiling

interface aint
    module procedure aint_array
end interface aint

interface mlx_clip
    module procedure clip_array, clip_s, clip_d
end interface mlx_clip

interface atan2
    module procedure atan2_array, atan2_ass, atan2_sas, atan2_asd, atan2_sad
end interface atan2

interface modulo
    module procedure modulo_array, modulo_ass, modulo_sas, modulo_asd, modulo_sad
end interface modulo

interface min
    module procedure min_array, min_ass, min_sas, min_asd, min_sad
end interface min

interface mlx_logaddexp
    module procedure logaddexp_array, logaddexp_ass, logaddexp_sas, logaddexp_asd, logaddexp_sad
end interface mlx_logaddexp

interface mlx_floor_divide
    module procedure floor_divide_array, floor_divide_ass, floor_divide_sas, floor_divide_asd, floor_divide_sad
end interface mlx_floor_divide

interface iand
    module procedure iand_array, iand_ai, iand_ia
end interface iand

interface ior
    module procedure ior_array, ior_ai, ior_ia
end interface ior

interface ieor
    module procedure ieor_array, ieor_ai, ieor_ia
end interface ieor

interface not
    module procedure bitwise_not_array
end interface not

interface shiftl
    module procedure shiftl_array, shiftl_ai
end interface shiftl

interface mlx_right_shift
    module procedure right_shift_array, right_shift_ai
end interface mlx_right_shift

interface mlx_full
    module procedure full_array, full_s, full_d, full_i
end interface mlx_full

interface mlx_full_like
    module procedure full_like_array, full_like_s, full_like_d, full_like_i
end interface mlx_full_like

interface
    module function real_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function real_array
    module function aimag_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function aimag_array
    module function conjg_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function conjg_array
    module function sqrt_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function sqrt_array
    module function mlx_astype( a, dtype ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_astype
    module function mlx_bitcast( a, dtype ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_bitcast
    module function max_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
    end function max_array
    module function max_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
    end function max_ass
    module function max_sas( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real32),    intent(in) :: a
        type(mlx_array) :: r
    end function max_sas
    module function max_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
    end function max_asd
    module function max_sad( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real64),    intent(in) :: a
        type(mlx_array) :: r
    end function max_sad
    module function merge_array( tsource, fsource, mask ) result(r)
        type(mlx_array), intent(in) :: tsource, fsource, mask
        type(mlx_array) :: r
    end function merge_array
    module function cmplx_array( x, y ) result(r)
        type(mlx_array), intent(in) :: x, y
        type(mlx_array) :: r
    end function cmplx_array
    module function reshape_array( a, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shape(:)
        type(mlx_array) :: r
    end function reshape_array
    module function mlx_permute( a, order ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: order(:)
        type(mlx_array) :: r
    end function mlx_permute
    module function transpose_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function transpose_array
    module function mlx_take_along_dim( a, indices, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_take_along_dim
    module function mlx_zeros( shape, dtype ) result(r)
        integer, intent(in)           :: shape(:)
        integer, optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_zeros
    module function mlx_arange( start, stop, step, dtype ) result(r)
        real(real64), intent(in)           :: start, stop
        real(real64), optional, intent(in) :: step
        integer,      optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_arange
    module function abs_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function abs_array
    module function sin_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function sin_array
    module function cos_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function cos_array
    module function tan_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function tan_array
    module function sinh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function sinh_array
    module function cosh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function cosh_array
    module function tanh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function tanh_array
    module function log_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function log_array
    module function log10_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function log10_array
    module function erf_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function erf_array
    module function asin_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function asin_array
    module function acos_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function acos_array
    module function atan_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function atan_array
    module function asinh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function asinh_array
    module function acosh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function acosh_array
    module function atanh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function atanh_array
    module function floor_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function floor_array
    module function ceiling_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function ceiling_array
    module function aint_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function aint_array
    module function mlx_sign( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_sign
    module function mlx_sigmoid( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_sigmoid
    module function mlx_square( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_square
    module function mlx_reciprocal( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_reciprocal
    module function mlx_rsqrt( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_rsqrt
    module function mlx_expm1( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_expm1
    module function mlx_log1p( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_log1p
    module function mlx_log2( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_log2
    module function mlx_erfinv( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_erfinv
    module function mlx_degrees( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_degrees
    module function mlx_radians( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_radians
    module function mlx_stop_gradient( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_stop_gradient
    module function mlx_copy( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_copy
    module function mlx_isnan( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_isnan
    module function mlx_isinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_isinf
    module function mlx_isfinite( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_isfinite
    module function mlx_isposinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_isposinf
    module function mlx_isneginf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_isneginf
    module function mlx_round( a, decimals ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: decimals
        type(mlx_array) :: r
    end function mlx_round
    module function clip_array( a, a_min, a_max ) result(r)
        type(mlx_array), intent(in) :: a, a_min, a_max
        type(mlx_array) :: r
    end function clip_array
    module function clip_s( a, a_min, a_max ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: a_min, a_max
        type(mlx_array) :: r
    end function clip_s
    module function clip_d( a, a_min, a_max ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: a_min, a_max
        type(mlx_array) :: r
    end function clip_d
    module function mlx_nan_to_num( a, nan, posinf, neginf ) result(r)
        type(mlx_array), intent(in)           :: a
        real(real32),    optional, intent(in) :: nan, posinf, neginf
        type(mlx_array) :: r
    end function mlx_nan_to_num
    module function atan2_array( y, x ) result(r)
        type(mlx_array), intent(in) :: y, x
        type(mlx_array) :: r
    end function atan2_array
    module function atan2_ass( y, x ) result(r)
        type(mlx_array), intent(in) :: y
        real(real32),    intent(in) :: x
        type(mlx_array) :: r
    end function atan2_ass
    module function atan2_sas( y, x ) result(r)
        real(real32),    intent(in) :: y
        type(mlx_array), intent(in) :: x
        type(mlx_array) :: r
    end function atan2_sas
    module function atan2_asd( y, x ) result(r)
        type(mlx_array), intent(in) :: y
        real(real64),    intent(in) :: x
        type(mlx_array) :: r
    end function atan2_asd
    module function atan2_sad( y, x ) result(r)
        real(real64),    intent(in) :: y
        type(mlx_array), intent(in) :: x
        type(mlx_array) :: r
    end function atan2_sad
    module function modulo_array( a, p ) result(r)
        type(mlx_array), intent(in) :: a, p
        type(mlx_array) :: r
    end function modulo_array
    module function modulo_ass( a, p ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: p
        type(mlx_array) :: r
    end function modulo_ass
    module function modulo_sas( a, p ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: p
        type(mlx_array) :: r
    end function modulo_sas
    module function modulo_asd( a, p ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: p
        type(mlx_array) :: r
    end function modulo_asd
    module function modulo_sad( a, p ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: p
        type(mlx_array) :: r
    end function modulo_sad
    module function min_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
    end function min_array
    module function min_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
    end function min_ass
    module function min_sas( a, b ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
    end function min_sas
    module function min_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
    end function min_asd
    module function min_sad( a, b ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
    end function min_sad
    module function logaddexp_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
    end function logaddexp_array
    module function logaddexp_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
    end function logaddexp_ass
    module function logaddexp_sas( a, b ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
    end function logaddexp_sas
    module function logaddexp_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
    end function logaddexp_asd
    module function logaddexp_sad( a, b ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
    end function logaddexp_sad
    module function floor_divide_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
    end function floor_divide_array
    module function floor_divide_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
    end function floor_divide_ass
    module function floor_divide_sas( a, b ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
    end function floor_divide_sas
    module function floor_divide_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
    end function floor_divide_asd
    module function floor_divide_sad( a, b ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
    end function floor_divide_sad
    module subroutine mlx_divmod( a, b, quotient, remainder )
        type(mlx_array), intent(in)  :: a, b
        type(mlx_array), intent(out) :: quotient, remainder
    end subroutine mlx_divmod
    module function mlx_isclose( a, b, rtol, atol, equal_nan ) result(r)
        type(mlx_array), intent(in)           :: a, b
        real(real64),    optional, intent(in) :: rtol, atol
        logical,         optional, intent(in) :: equal_nan
        type(mlx_array) :: r
    end function mlx_isclose
    module function mlx_allclose( a, b, rtol, atol, equal_nan ) result(r)
        type(mlx_array), intent(in)           :: a, b
        real(real64),    optional, intent(in) :: rtol, atol
        logical,         optional, intent(in) :: equal_nan
        type(mlx_array) :: r
    end function mlx_allclose
    module function mlx_array_equal( a, b, equal_nan ) result(r)
        type(mlx_array), intent(in)           :: a, b
        logical,         optional, intent(in) :: equal_nan
        type(mlx_array) :: r
    end function mlx_array_equal
    module function iand_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
    end function iand_array
    module function iand_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
    end function iand_ai
    module function iand_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
    end function iand_ia
    module function ior_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
    end function ior_array
    module function ior_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
    end function ior_ai
    module function ior_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
    end function ior_ia
    module function ieor_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
    end function ieor_array
    module function ieor_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
    end function ieor_ai
    module function ieor_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
    end function ieor_ia
    module function bitwise_not_array( i ) result(r)
        type(mlx_array), intent(in) :: i
        type(mlx_array) :: r
    end function bitwise_not_array
    module function shiftl_array( i, shift ) result(r)
        type(mlx_array), intent(in) :: i, shift
        type(mlx_array) :: r
    end function shiftl_array
    module function shiftl_ai( i, shift ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: shift
        type(mlx_array) :: r
    end function shiftl_ai
    module function right_shift_array( i, shift ) result(r)
        type(mlx_array), intent(in) :: i, shift
        type(mlx_array) :: r
    end function right_shift_array
    module function right_shift_ai( i, shift ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: shift
        type(mlx_array) :: r
    end function right_shift_ai
    module function mlx_ones( shape, dtype ) result(r)
        integer, intent(in)           :: shape(:)
        integer, optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_ones
    module function full_array( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        type(mlx_array), intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_array
    module function full_s( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        real(real32),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_s
    module function full_d( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        real(real64),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_d
    module function full_i( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        integer,         intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_i
    module function mlx_zeros_like( a, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_zeros_like
    module function mlx_ones_like( a, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_ones_like
    module function full_like_array( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        type(mlx_array), intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_like_array
    module function full_like_s( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        real(real32),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_like_s
    module function full_like_d( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        real(real64),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_like_d
    module function full_like_i( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function full_like_i
    module function sum_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function sum_array
    module function sum_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function sum_dims
    module function product_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function product_array
    module function product_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function product_dims
    module function maxval_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function maxval_array
    module function maxval_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function maxval_dims
    module function minval_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function minval_array
    module function minval_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function minval_dims
    module function all_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function all_array
    module function all_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function all_dims
    module function any_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function any_array
    module function any_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function any_dims
    module function count_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function count_array
    module function count_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function count_dims
    module function mean_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function mean_array
    module function mean_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function mean_dims
    module function median_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function median_array
    module function median_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function median_dims
    module function logsumexp_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function logsumexp_array
    module function logsumexp_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function logsumexp_dims
    module function var_array( a, dim, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
    end function var_array
    module function var_dims( a, dims, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
    end function var_dims
    module function std_array( a, dim, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
    end function std_array
    module function std_dims( a, dims, keepdims, ddof ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        integer,         optional, intent(in) :: ddof
        type(mlx_array) :: r
    end function std_dims
    module function mlx_cumsum( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
    end function mlx_cumsum
    module function mlx_cumprod( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
    end function mlx_cumprod
    module function mlx_cummax( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
    end function mlx_cummax
    module function mlx_cummin( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
    end function mlx_cummin
    module function mlx_logcumsumexp( a, dim, reverse, inclusive ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: reverse, inclusive
        type(mlx_array) :: r
    end function mlx_logcumsumexp
    module function softmax_array( a, dim, precise ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: precise
        type(mlx_array) :: r
    end function softmax_array
    module function softmax_dims( a, dims, precise ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: precise
        type(mlx_array) :: r
    end function softmax_dims
    module function maxloc_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function maxloc_array
    module function maxloc_all( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function maxloc_all
    module function minloc_array( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
    end function minloc_array
    module function minloc_all( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function minloc_all
    module function mlx_sort( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_sort
    module function mlx_argsort( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_argsort
    module function mlx_partition( a, kth, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: kth
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_partition
    module function mlx_argpartition( a, kth, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: kth
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_argpartition
    module function mlx_topk( a, k, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: k
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_topk
    module function mlx_concatenate( arrays, dim ) result(r)
        type(mlx_array), intent(in)           :: arrays(:)
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_concatenate
    module function mlx_stack( arrays, dim ) result(r)
        type(mlx_array), intent(in)           :: arrays(:)
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_stack
    module subroutine mlx_unstack( a, parts, dim )
        type(mlx_array), intent(in)               :: a
        type(mlx_array), allocatable, intent(out) :: parts(:)
        integer,         optional, intent(in)     :: dim
    end subroutine mlx_unstack
    module subroutine split_equal( a, num, parts, dim )
        type(mlx_array), intent(in)               :: a
        integer,         intent(in)               :: num
        type(mlx_array), allocatable, intent(out) :: parts(:)
        integer,         optional, intent(in)     :: dim
    end subroutine split_equal
    module subroutine split_at( a, indices, parts, dim )
        type(mlx_array), intent(in)               :: a
        integer,         intent(in)               :: indices(:)
        type(mlx_array), allocatable, intent(out) :: parts(:)
        integer,         optional, intent(in)     :: dim
    end subroutine split_at
    module function squeeze_array( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function squeeze_array
    module function squeeze_dims( a, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function squeeze_dims
    module function expand_dims_one( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function expand_dims_one
    module function expand_dims_list( a, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function expand_dims_list
    module function mlx_flatten( a, start_dim, end_dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: start_dim, end_dim
        type(mlx_array) :: r
    end function mlx_flatten
    module function mlx_unflatten( a, dim, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim, shape(:)
        type(mlx_array) :: r
    end function mlx_unflatten
    module function mlx_broadcast_to( a, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shape(:)
        type(mlx_array) :: r
    end function mlx_broadcast_to
    module subroutine mlx_broadcast_arrays( arrays, results )
        type(mlx_array), intent(in)               :: arrays(:)
        type(mlx_array), allocatable, intent(out) :: results(:)
    end subroutine mlx_broadcast_arrays
    module function mlx_tile( a, reps ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: reps(:)
        type(mlx_array) :: r
    end function mlx_tile
    module function mlx_repeat( a, repeats, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: repeats
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_repeat
    module function pad_width( a, width, value, mode ) result(r)
        type(mlx_array),  intent(in)           :: a
        integer,          intent(in)           :: width
        type(mlx_array),  optional, intent(in) :: value
        character(len=*), optional, intent(in) :: mode
        type(mlx_array) :: r
    end function pad_width
    module function pad_low_high( a, low, high, value, mode ) result(r)
        type(mlx_array),  intent(in)           :: a
        integer,          intent(in)           :: low(:), high(:)
        type(mlx_array),  optional, intent(in) :: value
        character(len=*), optional, intent(in) :: mode
        type(mlx_array) :: r
    end function pad_low_high
    module function flip_array( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function flip_array
    module function flip_dims( a, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function flip_dims
    module function cshift_array( a, shift, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: shift
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function cshift_array
    module function cshift_dims( a, shift, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shift(:), dims(:)
        type(mlx_array) :: r
    end function cshift_dims
    module function mlx_movedim( a, source, destination ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: source, destination
        type(mlx_array) :: r
    end function mlx_movedim
    module function mlx_swapdims( a, dim1, dim2 ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim1, dim2
        type(mlx_array) :: r
    end function mlx_swapdims
    module function mlx_atleast_1d( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_atleast_1d
    module function mlx_atleast_2d( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_atleast_2d
    module function mlx_atleast_3d( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function mlx_atleast_3d
    module function mlx_diag( a, k ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: k
        type(mlx_array) :: r
    end function mlx_diag
    module function mlx_diagonal( a, offset, dim1, dim2 ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: offset, dim1, dim2
        type(mlx_array) :: r
    end function mlx_diagonal
    module function mlx_trace( a, offset, dim1, dim2, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: offset, dim1, dim2, dtype
        type(mlx_array) :: r
    end function mlx_trace
    module function mlx_tril( a, k ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: k
        type(mlx_array) :: r
    end function mlx_tril
    module function mlx_triu( a, k ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: k
        type(mlx_array) :: r
    end function mlx_triu
    module function mlx_diff( a, n, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: n, dim
        type(mlx_array) :: r
    end function mlx_diff
    module function mlx_as_strided( a, shape, strides, offset ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: shape(:), strides(:)
        integer,         optional, intent(in) :: offset
        type(mlx_array) :: r
    end function mlx_as_strided
    module function mlx_number_of_elements( a, dims, inverted, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:), dtype
        logical,         optional, intent(in) :: inverted
        type(mlx_array) :: r
    end function mlx_number_of_elements
    module function axis_of( rank, dim, proc ) result(axis)
        integer,          intent(in) :: rank, dim
        character(len=*), intent(in) :: proc
        integer :: axis
    end function axis_of
    module function axes_of( rank, dims, proc ) result(axes)
        integer,          intent(in) :: rank, dims(:)
        character(len=*), intent(in) :: proc
        integer, allocatable :: axes(:)
    end function axes_of
    module function mlx_identity( n, dtype ) result(r)
        integer, intent(in)           :: n
        integer, optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_identity
    module function mlx_eye( n, m, k, dtype ) result(r)
        integer, intent(in)           :: n
        integer, optional, intent(in) :: m, k, dtype
        type(mlx_array) :: r
    end function mlx_eye
    module function mlx_tri( n, m, k, dtype ) result(r)
        integer, intent(in)           :: n
        integer, optional, intent(in) :: m, k, dtype
        type(mlx_array) :: r
    end function mlx_tri
    module function mlx_linspace( start, stop, num, endpoint, dtype ) result(r)
        real(real64), intent(in)           :: start, stop
        integer,      optional, intent(in) :: num, dtype
        logical,      optional, intent(in) :: endpoint
        type(mlx_array) :: r
    end function mlx_linspace
    module subroutine mlx_meshgrid( arrays, grids, sparse )
        type(mlx_array), intent(in)               :: arrays(:)
        type(mlx_array), allocatable, intent(out) :: grids(:)
        logical,         optional, intent(in)     :: sparse
    end subroutine mlx_meshgrid
    module function mlx_bartlett( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
    end function mlx_bartlett
    module function mlx_blackman( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
    end function mlx_blackman
    module function mlx_hamming( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
    end function mlx_hamming
    module function mlx_hanning( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
    end function mlx_hanning
    module function gather_list( a, indices, dims, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, indices(:)
        integer,         intent(in) :: dims(:), slice_sizes(:)
        type(mlx_array) :: r
    end function gather_list
    module function gather_one( a, indices, dim, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, indices
        integer,         intent(in) :: dim, slice_sizes(:)
        type(mlx_array) :: r
    end function gather_one
    module function scatter_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function scatter_list
    module function scatter_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function scatter_one
    module function scatter_add_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function scatter_add_list
    module function scatter_add_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function scatter_add_one
    module function scatter_max_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function scatter_max_list
    module function scatter_max_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function scatter_max_one
    module function scatter_min_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function scatter_min_list
    module function scatter_min_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function scatter_min_one
    module function scatter_prod_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function scatter_prod_list
    module function scatter_prod_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function scatter_prod_one
    module function mlx_put_along_dim( a, indices, values, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, values
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_put_along_dim
    module function mlx_masked_scatter( a, mask, src ) result(r)
        type(mlx_array), intent(in) :: a, mask, src
        type(mlx_array) :: r
    end function mlx_masked_scatter
    module function mlx_searchsorted( sorted, values, side ) result(r)
        type(mlx_array),  intent(in)           :: sorted, values
        character(len=*), optional, intent(in) :: side
        type(mlx_array) :: r
    end function mlx_searchsorted
    module subroutine mlx_unique( a, size, results, fill )
        type(mlx_array), intent(in)               :: a
        integer,         intent(in)               :: size
        type(mlx_array), allocatable, intent(out) :: results(:)
        type(mlx_array), optional, intent(in)     :: fill
    end subroutine mlx_unique
    module function slice_dynamic( a, start, dims, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, start
        integer,         intent(in) :: dims(:), slice_sizes(:)
        type(mlx_array) :: r
    end function slice_dynamic
    module function slice_update_static( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
    end function slice_update_static
    module function slice_update_dynamic( a, update, start, dims ) result(r)
        type(mlx_array), intent(in) :: a, update, start
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
    end function slice_update_dynamic
    module function mlx_slice_update_add( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
    end function mlx_slice_update_add
    module function mlx_slice_update_max( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
    end function mlx_slice_update_max
    module function mlx_slice_update_min( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
    end function mlx_slice_update_min
    module function mlx_slice_update_prod( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
    end function mlx_slice_update_prod
    module function slice_static( a, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
    end function slice_static
    module function mlx_take( a, indices, dim ) result(r)
        type(mlx_array), intent(in)           :: a, indices
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_take
end interface

end module mlxf_ops
