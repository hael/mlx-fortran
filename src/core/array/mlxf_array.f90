!@descr: the mlx_array type: its interface; lifetime, transfer, borrowing, evaluation and operations in submodules
! A Fortran array of shape (n1, ..., nr) is the MLX array of shape [nr, ..., n1] over the same bytes. A copy is
! the defined assignment, which counts a reference; a copy made without it (an allocatable component of a
! derived type, allocate(source=), an array intrinsic) is detected through the registry and stops at its next
! use. One type and one ownership implementation; the submodules share only what this interface declares.
module mlxf_array
use, intrinsic :: iso_c_binding,   only: c_bool, c_int, c_ptr, c_size_t, c_double, c_char, c_int64_t, &
                                         c_float_kind => c_float
use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
use mlxf_c_types, only: mlxc_array, mlxc_stream, mlxc_vector_array, mlxc_optional_dtype, mlxc_optional_float, &
                        mlxc_distributed_group, mlxc_map_string_to_array, mlxc_io_gguf
use mlxf_defs,    only: mlxf_slice_spec, mlxf_fft_spec, mlxf_range_spec, mlxf_close_spec, mlxf_nan_spec, &
                        mlxf_shape_spec, mlxf_reduce_spec, mlxf_scan_spec, mlxf_pad_spec, mlxf_strided_spec, &
                        mlxf_count_spec, mlxf_linspace_spec, mlxf_index_spec, mlxf_fftn_spec, mlx_conv_spec, &
                        mlxf_norm_spec, mlxf_random_spec, mlx_rope_spec, mlx_attention_spec, mlxf_group_spec
implicit none

public :: mlx_array, mlx_from, mlx_to, mlx_to_alloc, mlx_item, mlx_view, mlx_alloc, mlx_eval, mlx_async_eval
public :: mlxf_int_op, mlxf_dtype_op, &
    &mlxf_vector_op, &
    &mlxf_reduce_op, &
    &mlxf_ternary_op, &
    &mlxf_take_op, &
    &mlxf_scan_op, &
    &mlxf_slice_op, &
    &mlxf_concat_op, &
    &mlxf_zeros_op, &
    &mlxf_range_op, &
    &mlxf_fft_op, &
    &mlxf_fftn_op, &
    &mlxf_freq_op, &
    &mlxf_close_op, &
    &mlxf_compare_op, &
    &mlxf_nan_op, &
    &mlxf_binary_vector_op, &
    &mlxf_full_op, &
    &mlxf_binary_int_op, &
    &mlxf_reduce_all_op, &
    &mlxf_reduce_dims_op, &
    &mlxf_var_all_op, &
    &mlxf_var_op, &
    &mlxf_var_dims_op, &
    &mlxf_int2_op, &
    &mlxf_int3_op, &
    &mlxf_trace_op, &
    &mlxf_scan_all_op, &
    &mlxf_scan_plain_op, &
    &mlxf_scan_plain_all_op, &
    &mlxf_roll_op, &
    &mlxf_unflatten_op, &
    &mlxf_vector2_op, &
    &mlxf_strided_op, &
    &mlxf_count_op, &
    &mlxf_window_op, &
    &mlxf_identity_op, &
    &mlxf_eye_op, &
    &mlxf_linspace_op, &
    &mlxf_linspace_endpoint_op, &
    &mlxf_list_op, &
    &mlxf_vector_list_op, &
    &mlxf_meshgrid_op, &
    &mlxf_split_op, &
    &mlxf_split_sections_op, &
    &mlxf_unstack_op, &
    &mlxf_unstack_dim_op, &
    &mlxf_pad_op, &
    &mlxf_pad_width_op, &
    &mlxf_gather_op, &
    &mlxf_gather_single_op, &
    &mlxf_slice_dynamic_op, &
    &mlxf_scatter_op, &
    &mlxf_put_op, &
    &mlxf_ternary_vector_op, &
    &mlxf_text_op, &
    &mlxf_slice_update_op, &
    &mlxf_unique_op, &
    &mlxf_gather_mm_op, &
    &mlxf_masked_mm_op, &
    &mlxf_cpu_unary, &
    &mlxf_cpu_binary, &
    &mlxf_cpu_flag_op, &
    &mlxf_cpu_compare_op, &
    &mlxf_cpu_pair_op, &
    &mlxf_cpu_pair_text_op, &
    &mlxf_cpu_text_op, &
    &mlxf_cpu_unstack_op, &
    &mlxf_cpu_svd_op, &
    &mlxf_norm_op, &
    &mlxf_norm_text_op, &
    &mlxf_binary_axis_op, &
    &mlxf_optional_float_op, &
    &mlxf_addmm_op, &
    &mlxf_einsum_op, &
    &mlxf_tensordot_op, &
    &mlxf_conv1d_op, &
    &mlxf_conv2d_op, &
    &mlxf_conv3d_op, &
    &mlxf_conv_general_op, &
    &mlxf_conv_transpose1d_op, &
    &mlxf_conv_transpose2d_op, &
    &mlxf_conv_transpose3d_op, &
    &mlxf_pair_op, &
    &mlxf_random_key_op, &
    &mlxf_random_shape_op, &
    &mlxf_random_float_op, &
    &mlxf_random_int_op, &
    &mlxf_random_array_op, &
    &mlxf_random_axis_op, &
    &mlxf_random_axis_shape_op, &
    &mlxf_random_axis_int_op, &
    &mlxf_random_binary_op, &
    &mlxf_random_broadcast_op, &
    &mlxf_layer_norm_op, &
    &mlxf_rms_norm_op, &
    &mlxf_rope_op, &
    &mlxf_rope_dynamic_op, &
    &mlxf_attention_op, &
    &mlxf_load_op, &
    &mlxf_map_arrays, &
    &mlxf_gguf_arrays, &
    &mlxf_cpu_stream, &
    &mlxf_group_op, &
    &mlxf_group_peer_op, &
    &mlxf_group_recv_op, &
    &mlx_buffer_size
public :: mlxf_vector_import, mlxf_vector_export, mlxf_check_dtype, mlxf_axes_of, mlxf_zero_based, mlxf_one_based
public :: mlxf_weak_scalar
public :: mlx_synchronize, mlx_is_live, exp, mlxf_handle, mlxf_unary, mlxf_binary, mlxc_unary_op, mlxc_binary_op
private

! the largest rank MLX takes; Fortran arrays up to rank 15 reach it through assumed rank
integer, parameter :: MAX_RANK = 15

type :: mlx_array
    private
    type(mlxc_array) :: h
    integer(int64)   :: serial = 0_int64
  contains
    procedure, private            :: assign_array
    generic                       :: assignment(=) => assign_array
    procedure                     :: shape => array_shape
    procedure                     :: ndim  => array_ndim
    procedure                     :: size  => array_size
    procedure                     :: kind  => array_kind
    procedure                     :: nbytes => array_nbytes
    procedure                     :: itemsize => array_itemsize
    procedure                     :: kill  => kill_array
    procedure, private            :: add_aa
    procedure, private            :: add_as
    procedure, private, pass(rhs) :: add_sa
    procedure, private            :: add_ad
    procedure, private, pass(rhs) :: add_da
    procedure, private            :: pos_array
    generic                       :: operator(+) => add_aa, add_as, add_sa, add_ad, add_da, pos_array
    procedure, private            :: sub_aa
    procedure, private            :: sub_as
    procedure, private, pass(rhs) :: sub_sa
    procedure, private            :: sub_ad
    procedure, private, pass(rhs) :: sub_da
    generic                       :: operator(-) => sub_aa, sub_as, sub_sa, sub_ad, sub_da, negate_array
    procedure, private            :: mul_aa
    procedure, private            :: mul_as
    procedure, private, pass(rhs) :: mul_sa
    procedure, private            :: mul_ad
    procedure, private, pass(rhs) :: mul_da
    generic                       :: operator(*) => mul_aa, mul_as, mul_sa, mul_ad, mul_da
    procedure, private            :: div_aa
    procedure, private            :: div_as
    procedure, private, pass(rhs) :: div_sa
    procedure, private            :: div_ad
    procedure, private, pass(rhs) :: div_da
    generic                       :: operator(/) => div_aa, div_as, div_sa, div_ad, div_da
    procedure, private            :: pow_aa
    procedure, private            :: pow_as
    procedure, private, pass(rhs) :: pow_sa
    procedure, private            :: pow_ad
    procedure, private, pass(rhs) :: pow_da
    generic                       :: operator(**) => pow_aa, pow_as, pow_sa, pow_ad, pow_da
    procedure, private            :: lt_aa
    procedure, private            :: lt_as
    procedure, private, pass(rhs) :: lt_sa
    procedure, private            :: lt_ad
    procedure, private, pass(rhs) :: lt_da
    generic                       :: operator(<) => lt_aa, lt_as, lt_sa, lt_ad, lt_da
    procedure, private            :: le_aa
    procedure, private            :: le_as
    procedure, private, pass(rhs) :: le_sa
    procedure, private            :: le_ad
    procedure, private, pass(rhs) :: le_da
    generic                       :: operator(<=) => le_aa, le_as, le_sa, le_ad, le_da
    procedure, private            :: gt_aa
    procedure, private            :: gt_as
    procedure, private, pass(rhs) :: gt_sa
    procedure, private            :: gt_ad
    procedure, private, pass(rhs) :: gt_da
    generic                       :: operator(>) => gt_aa, gt_as, gt_sa, gt_ad, gt_da
    procedure, private            :: ge_aa
    procedure, private            :: ge_as
    procedure, private, pass(rhs) :: ge_sa
    procedure, private            :: ge_ad
    procedure, private, pass(rhs) :: ge_da
    generic                       :: operator(>=) => ge_aa, ge_as, ge_sa, ge_ad, ge_da
    procedure, private            :: eq_aa
    procedure, private            :: eq_as
    procedure, private, pass(rhs) :: eq_sa
    procedure, private            :: eq_ad
    procedure, private, pass(rhs) :: eq_da
    generic                       :: operator(==) => eq_aa, eq_as, eq_sa, eq_ad, eq_da
    procedure, private            :: ne_aa
    procedure, private            :: ne_as
    procedure, private, pass(rhs) :: ne_sa
    procedure, private            :: ne_ad
    procedure, private, pass(rhs) :: ne_da
    generic                       :: operator(/=) => ne_aa, ne_as, ne_sa, ne_ad, ne_da
    procedure, private            :: land_aa
    generic                       :: operator(.and.) => land_aa
    procedure, private            :: lor_aa
    generic                       :: operator(.or.) => lor_aa
    procedure, private            :: eqv_aa
    generic                       :: operator(.eqv.) => eqv_aa
    procedure, private            :: neqv_aa
    generic                       :: operator(.neqv.) => neqv_aa
    procedure, private            :: negate_array
    procedure, private            :: not_array
    generic                       :: operator(.not. ) => not_array
    final                         :: finalize_array
end type mlx_array

abstract interface
    ! int f(mlx_array* res, const mlx_array a, const mlx_stream s)
    function mlxc_unary_op( res, a, s ) bind(c)
        import :: mlxc_array, mlxc_stream, c_int
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_unary_op
    end function mlxc_unary_op

    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s)
    function mlxc_binary_op( res, a, b, s ) bind(c)
        import :: mlxc_array, mlxc_stream, c_int
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a, b
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_binary_op
    end function mlxc_binary_op
end interface

abstract interface
    ! int f(mlx_array* res, const mlx_array a, mlx_dtype dtype, const mlx_stream s)
    function mlxc_int_op( res, a, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_int_op
    end function mlxc_int_op
    ! int f(mlx_array* res, const mlx_array a, const int* shape, size_t shape_num, const mlx_stream s)
    function mlxc_vector_op( res, a, shape, shape_num, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), intent(in)      :: shape(*)
        integer(c_size_t), value        :: shape_num
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_vector_op
    end function mlxc_vector_op
    ! int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, const mlx_stream s)
    function mlxc_reduce_op( res, a, axis, keepdims, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), value           :: axis
        logical(c_bool), value          :: keepdims
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_reduce_op
    end function mlxc_reduce_op
    ! int f(mlx_array* res, const mlx_array condition, const mlx_array x, const mlx_array y,
    ! const mlx_stream s)
    function mlxc_ternary_op( res, condition, x, y, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: condition
        type(mlxc_array), value         :: x
        type(mlxc_array), value         :: y
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_ternary_op
    end function mlxc_ternary_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, int axis, const mlx_stream s)
    function mlxc_take_op( res, a, indices, axis, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        type(mlxc_array), value         :: indices
        integer(c_int), value           :: axis
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_take_op
    end function mlxc_take_op
    ! int f(mlx_array* res, const mlx_array a, int axis, bool reverse, bool inclusive,
    ! mlx_optional_dtype dtype, const mlx_stream s)
    function mlxc_scan_op( res, a, axis, reverse, inclusive, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout)  :: res
        type(mlxc_array), value          :: a
        integer(c_int), value            :: axis
        logical(c_bool), value           :: reverse
        logical(c_bool), value           :: inclusive
        type(mlxc_optional_dtype), value :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_scan_op
    end function mlxc_scan_op
    ! int f(mlx_array* res, const mlx_array a, const int* start, size_t start_num, const int* stop,
    ! size_t stop_num, const int* strides, size_t strides_num, const mlx_stream s)
    function mlxc_slice_op( res, a, start, start_num, stop, stop_num, strides, strides_num, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), intent(in)      :: start(*)
        integer(c_size_t), value        :: start_num
        integer(c_int), intent(in)      :: stop(*)
        integer(c_size_t), value        :: stop_num
        integer(c_int), intent(in)      :: strides(*)
        integer(c_size_t), value        :: strides_num
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_slice_op
    end function mlxc_slice_op
    ! int f(mlx_array* res, const mlx_vector_array arrays, int axis, const mlx_stream s)
    function mlxc_concat_op( res, arrays, axis, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_vector_array), value  :: arrays
        integer(c_int), value           :: axis
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_concat_op
    end function mlxc_concat_op
    ! int f(mlx_array* res, const int* shape, size_t shape_num, mlx_dtype dtype, const mlx_stream s)
    function mlxc_zeros_op( res, shape, shape_num, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        integer(c_int), intent(in)      :: shape(*)
        integer(c_size_t), value        :: shape_num
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_zeros_op
    end function mlxc_zeros_op
    ! int f(mlx_array* res, double start, double stop, double step, mlx_dtype dtype, const mlx_stream s)
    function mlxc_range_op( res, start, stop, step, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        real(c_double), value           :: start
        real(c_double), value           :: stop
        real(c_double), value           :: step
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_range_op
    end function mlxc_range_op
    ! int f(mlx_array* res, const mlx_array a, int n, int axis, mlx_fft_norm norm, const mlx_stream s)
    function mlxc_fft_op( res, a, n, axis, norm, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), value           :: n
        integer(c_int), value           :: axis
        integer(c_int), value           :: norm
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_fft_op
    end function mlxc_fft_op
    ! int f(mlx_array* res, const mlx_array a, const int* n, size_t n_num, const int* axes,
    ! size_t axes_num, mlx_fft_norm norm, const mlx_stream s)
    function mlxc_fftn_op( res, a, n, n_num, axes, axes_num, norm, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), intent(in)      :: n(*)
        integer(c_size_t), value        :: n_num
        integer(c_int), intent(in)      :: axes(*)
        integer(c_size_t), value        :: axes_num
        integer(c_int), value           :: norm
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_fftn_op
    end function mlxc_fftn_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_array lhs_indices,
    ! const mlx_array rhs_indices, bool sorted_indices, const mlx_stream s)
    function mlxc_gather_mm_op( res, a, b, lhs_indices, rhs_indices, sorted_indices, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_array),  value         :: b
        type(mlxc_array),  value         :: lhs_indices
        type(mlxc_array),  value         :: rhs_indices
        logical(c_bool),   value         :: sorted_indices
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_gather_mm_op
    end function mlxc_gather_mm_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, int block_size, const mlx_array mask_out,
    ! const mlx_array mask_lhs, const mlx_array mask_rhs, const mlx_stream s)
    function mlxc_masked_mm_op( res, a, b, block_size, mask_out, mask_lhs, mask_rhs, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_array),  value         :: b
        integer(c_int),    value         :: block_size
        type(mlxc_array),  value         :: mask_out
        type(mlxc_array),  value         :: mask_lhs
        type(mlxc_array),  value         :: mask_rhs
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_masked_mm_op
    end function mlxc_masked_mm_op
    ! int f(mlx_array* res, int n, double d, const mlx_stream s)
    function mlxc_freq_op( res, n, d, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        integer(c_int),    value         :: n
        real(c_double),    value         :: d
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_freq_op
    end function mlxc_freq_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, double rtol, double atol, bool equal_nan,
    ! const mlx_stream s)
    function mlxc_close_op( res, a, b, rtol, atol, equal_nan, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        type(mlxc_array), value         :: b
        real(c_double), value           :: rtol
        real(c_double), value           :: atol
        logical(c_bool), value          :: equal_nan
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_close_op
    end function mlxc_close_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, bool equal_nan, const mlx_stream s)
    function mlxc_compare_op( res, a, b, equal_nan, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        type(mlxc_array), value         :: b
        logical(c_bool), value          :: equal_nan
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_compare_op
    end function mlxc_compare_op
    ! int f(mlx_array* res, const mlx_array a, float nan, mlx_optional_float posinf, mlx_optional_float neginf,
    ! const mlx_stream s)
    function mlxc_nan_op( res, a, nan, posinf, neginf, s ) bind(c)
        import
        type(mlxc_array), intent(inout)  :: res
        type(mlxc_array), value          :: a
        real(c_float_kind), value        :: nan
        type(mlxc_optional_float), value :: posinf
        type(mlxc_optional_float), value :: neginf
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_nan_op
    end function mlxc_nan_op
    ! int f(mlx_vector_array* res, const mlx_array a, const mlx_array b, const mlx_stream s)
    function mlxc_binary_vector_op( res, a, b, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_array), value                :: a
        type(mlxc_array), value                :: b
        type(mlxc_stream), value               :: s
        integer(c_int) :: mlxc_binary_vector_op
    end function mlxc_binary_vector_op
    ! int f(mlx_array* res, const int* shape, size_t shape_num, const mlx_array vals, mlx_dtype dtype,
    ! const mlx_stream s)
    function mlxc_full_op( res, shape, shape_num, vals, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        integer(c_int), intent(in)      :: shape(*)
        integer(c_size_t), value        :: shape_num
        type(mlxc_array), value         :: vals
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_full_op
    end function mlxc_full_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, mlx_dtype dtype, const mlx_stream s)
    function mlxc_binary_int_op( res, a, b, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        type(mlxc_array), value         :: b
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_binary_int_op
    end function mlxc_binary_int_op
    ! int f(mlx_array* res, const mlx_array a, bool keepdims, const mlx_stream s)
    function mlxc_flag_op( res, a, keepdims, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        logical(c_bool),   value         :: keepdims
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_flag_op
    end function mlxc_flag_op
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool keepdims, const mlx_stream
    ! s)
    function mlxc_reduce_dims_op( res, a, axes, axes_num, keepdims, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    intent(in)    :: axes(*)
        integer(c_size_t), value         :: axes_num
        logical(c_bool),   value         :: keepdims
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_reduce_dims_op
    end function mlxc_reduce_dims_op
    ! int f(mlx_array* res, const mlx_array a, bool keepdims, int ddof, const mlx_stream s)
    function mlxc_var_all_op( res, a, keepdims, ddof, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        logical(c_bool),   value         :: keepdims
        integer(c_int),    value         :: ddof
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_var_all_op
    end function mlxc_var_all_op
    ! int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, int ddof, const mlx_stream s)
    function mlxc_var_op( res, a, axis, keepdims, ddof, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    value         :: axis
        logical(c_bool),   value         :: keepdims
        integer(c_int),    value         :: ddof
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_var_op
    end function mlxc_var_op
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool keepdims, int ddof, const
    ! mlx_stream s)
    function mlxc_var_dims_op( res, a, axes, axes_num, keepdims, ddof, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    intent(in)    :: axes(*)
        integer(c_size_t), value         :: axes_num
        logical(c_bool),   value         :: keepdims
        integer(c_int),    value         :: ddof
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_var_dims_op
    end function mlxc_var_dims_op
    ! int f(mlx_array* res, const mlx_array a, int i, int j, const mlx_stream s)
    function mlxc_int2_op( res, a, i, j, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    value         :: i
        integer(c_int),    value         :: j
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_int2_op
    end function mlxc_int2_op
    ! int f(mlx_array* res, const mlx_array a, int i, int j, int k, const mlx_stream s)
    function mlxc_int3_op( res, a, i, j, k, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    value         :: i
        integer(c_int),    value         :: j
        integer(c_int),    value         :: k
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_int3_op
    end function mlxc_int3_op
    ! int f(mlx_array* res, const mlx_array a, int offset, int axis1, int axis2, mlx_dtype dtype, const mlx_stream
    ! s)
    function mlxc_trace_op( res, a, offset, axis1, axis2, dtype, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    value         :: offset
        integer(c_int),    value         :: axis1
        integer(c_int),    value         :: axis2
        integer(c_int),    value         :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_trace_op
    end function mlxc_trace_op
    ! int f(mlx_array* res, const mlx_array a, bool reverse, bool inclusive, mlx_optional_dtype dtype, const
    ! mlx_stream s)
    function mlxc_scan_all_op( res, a, reverse, inclusive, dtype, s ) bind(c)
        import
        type(mlxc_array),          intent(inout) :: res
        type(mlxc_array),          value         :: a
        logical(c_bool),           value         :: reverse
        logical(c_bool),           value         :: inclusive
        type(mlxc_optional_dtype), value         :: dtype
        type(mlxc_stream),         value         :: s
        integer(c_int) :: mlxc_scan_all_op
    end function mlxc_scan_all_op
    ! int f(mlx_array* res, const mlx_array a, int axis, bool reverse, bool inclusive, const mlx_stream s)
    function mlxc_scan_plain_op( res, a, axis, reverse, inclusive, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    value         :: axis
        logical(c_bool),   value         :: reverse
        logical(c_bool),   value         :: inclusive
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_scan_plain_op
    end function mlxc_scan_plain_op
    ! int f(mlx_array* res, const mlx_array a, bool reverse, bool inclusive, const mlx_stream s)
    function mlxc_scan_plain_all_op( res, a, reverse, inclusive, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        logical(c_bool),   value         :: reverse
        logical(c_bool),   value         :: inclusive
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_scan_plain_all_op
    end function mlxc_scan_plain_all_op
    ! int f(mlx_array* res, const mlx_array a, const int* shift, size_t shift_num, int axis, const mlx_stream s)
    function mlxc_roll_op( res, a, shift, shift_num, axis, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    intent(in)    :: shift(*)
        integer(c_size_t), value         :: shift_num
        integer(c_int),    value         :: axis
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_roll_op
    end function mlxc_roll_op
    ! int f(mlx_array* res, const mlx_array a, int axis, const int* shape, size_t shape_num, const mlx_stream s)
    function mlxc_unflatten_op( res, a, axis, shape, shape_num, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    value         :: axis
        integer(c_int),    intent(in)    :: shape(*)
        integer(c_size_t), value         :: shape_num
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_unflatten_op
    end function mlxc_unflatten_op
    ! int f(mlx_array* res, const mlx_array a, const int* u, size_t u_num, const int* v, size_t v_num, const
    ! mlx_stream s)
    function mlxc_vector2_op( res, a, u, u_num, v, v_num, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    intent(in)    :: u(*)
        integer(c_size_t), value         :: u_num
        integer(c_int),    intent(in)    :: v(*)
        integer(c_size_t), value         :: v_num
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_vector2_op
    end function mlxc_vector2_op
    ! int f(mlx_array* res, const mlx_array a, const int* shape, size_t shape_num, const int64_t* strides, size_t
    ! strides_num, size_t offset, const mlx_stream s)
    function mlxc_strided_op( res, a, shape, shape_num, strides, strides_num, offset, s ) bind(c)
        import
        type(mlxc_array),   intent(inout) :: res
        type(mlxc_array),   value         :: a
        integer(c_int),     intent(in)    :: shape(*)
        integer(c_size_t),  value         :: shape_num
        integer(c_int64_t), intent(in)    :: strides(*)
        integer(c_size_t),  value         :: strides_num
        integer(c_size_t),  value         :: offset
        type(mlxc_stream),  value         :: s
        integer(c_int) :: mlxc_strided_op
    end function mlxc_strided_op
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool inverted, mlx_dtype dtype,
    ! const mlx_stream s)
    function mlxc_count_op( res, a, axes, axes_num, inverted, dtype, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        integer(c_int),    intent(in)    :: axes(*)
        integer(c_size_t), value         :: axes_num
        logical(c_bool),   value         :: inverted
        integer(c_int),    value         :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_count_op
    end function mlxc_count_op
    ! int f(mlx_array* res, int M, const mlx_stream s)
    function mlxc_window_op( res, m, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        integer(c_int),    value         :: m
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_window_op
    end function mlxc_window_op
    ! int f(mlx_array* res, int n, mlx_dtype dtype, const mlx_stream s)
    function mlxc_identity_op( res, n, dtype, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        integer(c_int),    value         :: n
        integer(c_int),    value         :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_identity_op
    end function mlxc_identity_op
    ! int f(mlx_array* res, int n, int m, int k, mlx_dtype dtype, const mlx_stream s)
    function mlxc_eye_op( res, n, m, k, dtype, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        integer(c_int),    value         :: n
        integer(c_int),    value         :: m
        integer(c_int),    value         :: k
        integer(c_int),    value         :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_eye_op
    end function mlxc_eye_op
    ! int f(mlx_array* res, double start, double stop, int num, mlx_dtype dtype, const mlx_stream s)
    function mlxc_linspace_op( res, start, stop, num, dtype, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        real(c_double),    value         :: start
        real(c_double),    value         :: stop
        integer(c_int),    value         :: num
        integer(c_int),    value         :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_linspace_op
    end function mlxc_linspace_op
    ! int f(mlx_array* res, double start, double stop, int num, bool endpoint, mlx_dtype dtype, const mlx_stream
    ! s)
    function mlxc_linspace_endpoint_op( res, start, stop, num, endpoint, dtype, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        real(c_double),    value         :: start
        real(c_double),    value         :: stop
        integer(c_int),    value         :: num
        logical(c_bool),   value         :: endpoint
        integer(c_int),    value         :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_linspace_endpoint_op
    end function mlxc_linspace_endpoint_op
    ! int f(mlx_array* res, const mlx_vector_array arrays, const mlx_stream s)
    function mlxc_list_op( res, arrays, s ) bind(c)
        import
        type(mlxc_array),        intent(inout) :: res
        type(mlxc_vector_array), value         :: arrays
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_list_op
    end function mlxc_list_op
    ! int f(mlx_vector_array* res, const mlx_vector_array inputs, const mlx_stream s)
    function mlxc_vector_list_op( res, inputs, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_vector_array), value         :: inputs
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_vector_list_op
    end function mlxc_vector_list_op
    ! int f(mlx_vector_array* res, const mlx_vector_array arrays, bool sparse, const char* indexing, const
    ! mlx_stream s)
    function mlxc_meshgrid_op( res, arrays, sparse, indexing, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_vector_array), value         :: arrays
        logical(c_bool),         value         :: sparse
        character(kind=c_char),  intent(in)    :: indexing(*)
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_meshgrid_op
    end function mlxc_meshgrid_op
    ! int f(mlx_vector_array* res, const mlx_array a, int num_splits, int axis, const mlx_stream s)
    function mlxc_split_op( res, a, num_splits, axis, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_array),        value         :: a
        integer(c_int),          value         :: num_splits
        integer(c_int),          value         :: axis
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_split_op
    end function mlxc_split_op
    ! int f(mlx_vector_array* res, const mlx_array a, const int* indices, size_t indices_num, int axis, const
    ! mlx_stream s)
    function mlxc_split_sections_op( res, a, indices, indices_num, axis, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_array),        value         :: a
        integer(c_int),          intent(in)    :: indices(*)
        integer(c_size_t),       value         :: indices_num
        integer(c_int),          value         :: axis
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_split_sections_op
    end function mlxc_split_sections_op
    ! int f(mlx_vector_array* res, const mlx_array a, const mlx_stream s)
    function mlxc_unstack_op( res, a, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_array),        value         :: a
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_unstack_op
    end function mlxc_unstack_op
    ! int f(mlx_vector_array* res, const mlx_array a, int axis, const mlx_stream s)
    function mlxc_unstack_dim_op( res, a, axis, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_array),        value         :: a
        integer(c_int),          value         :: axis
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_unstack_dim_op
    end function mlxc_unstack_dim_op
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, const int* low_pad_size, size_t
    ! low_pad_size_num, const int* high_pad_size, size_t high_pad_size_num, const mlx_array pad_value, const char*
    ! mode, const mlx_stream s)
    function mlxc_pad_op( res, a, axes, axes_num, low_pad_size, low_pad_size_num, high_pad_size, high_pad_size_num, pad_value, mode, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res
        type(mlxc_array),       value         :: a
        integer(c_int),         intent(in)    :: axes(*)
        integer(c_size_t),      value         :: axes_num
        integer(c_int),         intent(in)    :: low_pad_size(*)
        integer(c_size_t),      value         :: low_pad_size_num
        integer(c_int),         intent(in)    :: high_pad_size(*)
        integer(c_size_t),      value         :: high_pad_size_num
        type(mlxc_array),       value         :: pad_value
        character(kind=c_char), intent(in)    :: mode(*)
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_pad_op
    end function mlxc_pad_op
    ! int f(mlx_array* res, const mlx_array a, int pad_width, const mlx_array pad_value, const char* mode, const
    ! mlx_stream s)
    function mlxc_pad_width_op( res, a, pad_width, pad_value, mode, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res
        type(mlxc_array),       value         :: a
        integer(c_int),         value         :: pad_width
        type(mlxc_array),       value         :: pad_value
        character(kind=c_char), intent(in)    :: mode(*)
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_pad_width_op
    end function mlxc_pad_width_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_vector_array indices, const int* axes, size_t axes_num,
    ! const int* slice_sizes, size_t slice_sizes_num, const mlx_stream s)
    function mlxc_gather_op( res, a, indices, axes, axes_num, slice_sizes, slice_sizes_num, s ) bind(c)
        import
        type(mlxc_array),        intent(inout) :: res
        type(mlxc_array),        value         :: a
        type(mlxc_vector_array), value         :: indices
        integer(c_int),          intent(in)    :: axes(*)
        integer(c_size_t),       value         :: axes_num
        integer(c_int),          intent(in)    :: slice_sizes(*)
        integer(c_size_t),       value         :: slice_sizes_num
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_gather_op
    end function mlxc_gather_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, int axis, const int* slice_sizes, size_t
    ! slice_sizes_num, const mlx_stream s)
    function mlxc_gather_single_op( res, a, indices, axis, slice_sizes, slice_sizes_num, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_array),  value         :: indices
        integer(c_int),    value         :: axis
        integer(c_int),    intent(in)    :: slice_sizes(*)
        integer(c_size_t), value         :: slice_sizes_num
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_gather_single_op
    end function mlxc_gather_single_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array start, const int* axes, size_t axes_num, const int*
    ! slice_size, size_t slice_size_num, const mlx_stream s)
    function mlxc_slice_dynamic_op( res, a, start, axes, axes_num, slice_size, slice_size_num, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_array),  value         :: start
        integer(c_int),    intent(in)    :: axes(*)
        integer(c_size_t), value         :: axes_num
        integer(c_int),    intent(in)    :: slice_size(*)
        integer(c_size_t), value         :: slice_size_num
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_slice_dynamic_op
    end function mlxc_slice_dynamic_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_vector_array indices, const mlx_array updates, const int*
    ! axes, size_t axes_num, const mlx_stream s)
    function mlxc_scatter_op( res, a, indices, updates, axes, axes_num, s ) bind(c)
        import
        type(mlxc_array),        intent(inout) :: res
        type(mlxc_array),        value         :: a
        type(mlxc_vector_array), value         :: indices
        type(mlxc_array),        value         :: updates
        integer(c_int),          intent(in)    :: axes(*)
        integer(c_size_t),       value         :: axes_num
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_scatter_op
    end function mlxc_scatter_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, const mlx_array values, int axis, const
    ! mlx_stream s)
    function mlxc_put_op( res, a, indices, values, axis, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_array),  value         :: indices
        type(mlxc_array),  value         :: values
        integer(c_int),    value         :: axis
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_put_op
    end function mlxc_put_op
    ! int f(mlx_array* res, const mlx_array src, const mlx_array update, const mlx_array start, const int* axes,
    ! size_t axes_num, const mlx_stream s)
    function mlxc_ternary_vector_op( res, src, update, start, axes, axes_num, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: src
        type(mlxc_array),  value         :: update
        type(mlxc_array),  value         :: start
        integer(c_int),    intent(in)    :: axes(*)
        integer(c_size_t), value         :: axes_num
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_ternary_vector_op
    end function mlxc_ternary_vector_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const char* text, const mlx_stream s)
    function mlxc_text_op( res, a, b, text, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res
        type(mlxc_array),       value         :: a
        type(mlxc_array),       value         :: b
        character(kind=c_char), intent(in)    :: text(*)
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_text_op
    end function mlxc_text_op
    ! int f(mlx_array* res, const mlx_array src, const mlx_array update, const int* start, size_t start_num, const
    ! int* stop, size_t stop_num, const int* strides, size_t strides_num, const mlx_stream s)
    function mlxc_slice_update_op( res, src, update, start, start_num, stop, stop_num, strides, strides_num, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: src
        type(mlxc_array),  value         :: update
        integer(c_int),    intent(in)    :: start(*)
        integer(c_size_t), value         :: start_num
        integer(c_int),    intent(in)    :: stop(*)
        integer(c_size_t), value         :: stop_num
        integer(c_int),    intent(in)    :: strides(*)
        integer(c_size_t), value         :: strides_num
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_slice_update_op
    end function mlxc_slice_update_op
    ! int f(mlx_vector_array* res, const mlx_array a, int size, bool return_index, bool return_inverse, bool
    ! return_counts, const mlx_array fill_value, const mlx_stream s)
    function mlxc_unique_op( res, a, size, return_index, return_inverse, return_counts, fill_value, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_array),        value         :: a
        integer(c_int),          value         :: size
        logical(c_bool),         value         :: return_index
        logical(c_bool),         value         :: return_inverse
        logical(c_bool),         value         :: return_counts
        type(mlxc_array),        value         :: fill_value
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_unique_op
    end function mlxc_unique_op
    ! int f(mlx_array* res_0, mlx_array* res_1, const mlx_array a, const mlx_stream s)
    function mlxc_pair_op( res_0, res_1, a, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res_0
        type(mlxc_array),  intent(inout) :: res_1
        type(mlxc_array),  value         :: a
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_pair_op
    end function mlxc_pair_op
    ! int f(mlx_array* res_0, mlx_array* res_1, const mlx_array a, const char* text, const mlx_stream s)
    function mlxc_pair_text_op( res_0, res_1, a, text, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res_0
        type(mlxc_array),       intent(inout) :: res_1
        type(mlxc_array),       value         :: a
        character(kind=c_char), intent(in)    :: text(*)
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_pair_text_op
    end function mlxc_pair_text_op
    ! int f(mlx_array* res, const mlx_array a, const char* text, const mlx_stream s)
    function mlxc_unary_text_op( res, a, text, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res
        type(mlxc_array),       value         :: a
        character(kind=c_char), intent(in)    :: text(*)
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_unary_text_op
    end function mlxc_unary_text_op
    ! int f(mlx_vector_array* res, const mlx_array a, bool flag, const mlx_stream s)
    function mlxc_vector_flag_op( res, a, flag, s ) bind(c)
        import
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_array),        value         :: a
        logical(c_bool),         value         :: flag
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_vector_flag_op
    end function mlxc_vector_flag_op
    ! int f(mlx_array* res, const mlx_array a, double ord, const int* axis, size_t axis_num, bool keepdims,
    ! const mlx_stream s)
    function mlxc_norm_op( res, a, ord, axis, axis_num, keepdims, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        real(c_double),    value         :: ord
        integer(c_int),    intent(in)    :: axis(*)
        integer(c_size_t), value         :: axis_num
        logical(c_bool),   value         :: keepdims
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_norm_op
    end function mlxc_norm_op
    ! int f(mlx_array* res, const mlx_array a, const char* ord, const int* axis, size_t axis_num, bool keepdims,
    ! const mlx_stream s)
    function mlxc_norm_text_op( res, a, ord, axis, axis_num, keepdims, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res
        type(mlxc_array),       value         :: a
        character(kind=c_char), intent(in)    :: ord(*)
        integer(c_int),         intent(in)    :: axis(*)
        integer(c_size_t),      value         :: axis_num
        logical(c_bool),        value         :: keepdims
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_norm_text_op
    end function mlxc_norm_text_op
    ! int f(mlx_array* res, const mlx_array a, mlx_optional_float scale, const mlx_stream s)
    function mlxc_optional_float_op( res, a, scale, s ) bind(c)
        import
        type(mlxc_array),          intent(inout) :: res
        type(mlxc_array),          value         :: a
        type(mlxc_optional_float), value         :: scale
        type(mlxc_stream),         value         :: s
        integer(c_int) :: mlxc_optional_float_op
    end function mlxc_optional_float_op
    ! int f(mlx_array* res, const mlx_array c, const mlx_array a, const mlx_array b, float alpha, float beta,
    ! const mlx_stream s)
    function mlxc_addmm_op( res, c, a, b, alpha, beta, s ) bind(c)
        import
        type(mlxc_array),   intent(inout) :: res
        type(mlxc_array),   value         :: c
        type(mlxc_array),   value         :: a
        type(mlxc_array),   value         :: b
        real(c_float_kind), value         :: alpha
        real(c_float_kind), value         :: beta
        type(mlxc_stream),  value         :: s
        integer(c_int) :: mlxc_addmm_op
    end function mlxc_addmm_op
    ! int f(mlx_array* res, const char* subscripts, const mlx_vector_array operands, const mlx_stream s)
    function mlxc_einsum_op( res, subscripts, operands, s ) bind(c)
        import
        type(mlxc_array),        intent(inout) :: res
        character(kind=c_char),  intent(in)    :: subscripts(*)
        type(mlxc_vector_array), value         :: operands
        type(mlxc_stream),       value         :: s
        integer(c_int) :: mlxc_einsum_op
    end function mlxc_einsum_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const int* axes_a, size_t axes_a_num,
    ! const int* axes_b, size_t axes_b_num, const mlx_stream s)
    function mlxc_tensordot_op( res, a, b, axes_a, axes_a_num, axes_b, axes_b_num, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_array),  value         :: b
        integer(c_int),    intent(in)    :: axes_a(*)
        integer(c_size_t), value         :: axes_a_num
        integer(c_int),    intent(in)    :: axes_b(*)
        integer(c_size_t), value         :: axes_b_num
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_tensordot_op
    end function mlxc_tensordot_op
    ! int f(mlx_array* res, const mlx_array input, const mlx_array weight, int stride, int padding, int dilation,
    ! int groups, const mlx_stream s)
    function mlxc_conv1d_op( res, input, weight, stride, padding, dilation, groups, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: input
        type(mlxc_array),  value         :: weight
        integer(c_int),    value         :: stride
        integer(c_int),    value         :: padding
        integer(c_int),    value         :: dilation
        integer(c_int),    value         :: groups
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_conv1d_op
    end function mlxc_conv1d_op
    ! int f(mlx_array* res, const mlx_array input, const mlx_array weight, int stride_0, int stride_1,
    ! int padding_0, int padding_1, int dilation_0, int dilation_1, int groups, const mlx_stream s)
    function mlxc_conv2d_op( res, input, weight, stride_0, stride_1, padding_0, padding_1, dilation_0, dilation_1, groups, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: input
        type(mlxc_array),  value         :: weight
        integer(c_int),    value         :: stride_0
        integer(c_int),    value         :: stride_1
        integer(c_int),    value         :: padding_0
        integer(c_int),    value         :: padding_1
        integer(c_int),    value         :: dilation_0
        integer(c_int),    value         :: dilation_1
        integer(c_int),    value         :: groups
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_conv2d_op
    end function mlxc_conv2d_op
    ! int f(mlx_array* res, const mlx_array input, const mlx_array weight, three strides, three paddings, three
    ! dilations, each an int, int groups, const mlx_stream s)
    function mlxc_conv3d_op( res, input, weight, stride_0, stride_1, stride_2, padding_0, padding_1, padding_2, dilation_0, dilation_1, dilation_2, groups, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: input
        type(mlxc_array),  value         :: weight
        integer(c_int),    value         :: stride_0
        integer(c_int),    value         :: stride_1
        integer(c_int),    value         :: stride_2
        integer(c_int),    value         :: padding_0
        integer(c_int),    value         :: padding_1
        integer(c_int),    value         :: padding_2
        integer(c_int),    value         :: dilation_0
        integer(c_int),    value         :: dilation_1
        integer(c_int),    value         :: dilation_2
        integer(c_int),    value         :: groups
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_conv3d_op
    end function mlxc_conv3d_op
    ! int f(mlx_array* res, const mlx_array input, const mlx_array weight, const int* stride, size_t stride_num,
    ! const int* padding_lo, size_t padding_lo_num, const int* padding_hi, size_t padding_hi_num,
    ! const int* kernel_dilation, size_t kernel_dilation_num, const int* input_dilation, size_t input_dilation_num,
    ! int groups, bool flip, const mlx_stream s)
    function mlxc_conv_general_op( res, input, weight, stride, stride_num, padding_lo, padding_lo_num, padding_hi, padding_hi_num, kernel_dilation, kernel_dilation_num, input_dilation, input_dilation_num, groups, flip, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: input
        type(mlxc_array),  value         :: weight
        integer(c_int),    intent(in)    :: stride(*)
        integer(c_size_t), value         :: stride_num
        integer(c_int),    intent(in)    :: padding_lo(*)
        integer(c_size_t), value         :: padding_lo_num
        integer(c_int),    intent(in)    :: padding_hi(*)
        integer(c_size_t), value         :: padding_hi_num
        integer(c_int),    intent(in)    :: kernel_dilation(*)
        integer(c_size_t), value         :: kernel_dilation_num
        integer(c_int),    intent(in)    :: input_dilation(*)
        integer(c_size_t), value         :: input_dilation_num
        integer(c_int),    value         :: groups
        logical(c_bool),   value         :: flip
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_conv_general_op
    end function mlxc_conv_general_op
    ! int f(mlx_array* res, const mlx_array input, const mlx_array weight, int stride, int padding, int dilation,
    ! int output_padding, int groups, const mlx_stream s)
    function mlxc_conv_transpose1d_op( res, input, weight, stride, padding, dilation, output_padding, groups, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: input
        type(mlxc_array),  value         :: weight
        integer(c_int),    value         :: stride
        integer(c_int),    value         :: padding
        integer(c_int),    value         :: dilation
        integer(c_int),    value         :: output_padding
        integer(c_int),    value         :: groups
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_conv_transpose1d_op
    end function mlxc_conv_transpose1d_op
    ! int f(mlx_array* res, const mlx_array input, const mlx_array weight, two strides, two paddings, two
    ! dilations, two output paddings, each an int, int groups, const mlx_stream s)
    function mlxc_conv_transpose2d_op( res, input, weight, stride_0, stride_1, padding_0, padding_1, dilation_0, dilation_1, output_padding_0, output_padding_1, groups, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: input
        type(mlxc_array),  value         :: weight
        integer(c_int),    value         :: stride_0
        integer(c_int),    value         :: stride_1
        integer(c_int),    value         :: padding_0
        integer(c_int),    value         :: padding_1
        integer(c_int),    value         :: dilation_0
        integer(c_int),    value         :: dilation_1
        integer(c_int),    value         :: output_padding_0
        integer(c_int),    value         :: output_padding_1
        integer(c_int),    value         :: groups
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_conv_transpose2d_op
    end function mlxc_conv_transpose2d_op
    ! int f(mlx_array* res, const mlx_array input, const mlx_array weight, three strides, three paddings, three
    ! dilations, three output paddings, each an int, int groups, const mlx_stream s)
    function mlxc_conv_transpose3d_op( res, input, weight, stride_0, stride_1, stride_2, padding_0, padding_1, padding_2, dilation_0, dilation_1, dilation_2, output_padding_0, output_padding_1, output_padding_2, groups, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: input
        type(mlxc_array),  value         :: weight
        integer(c_int),    value         :: stride_0
        integer(c_int),    value         :: stride_1
        integer(c_int),    value         :: stride_2
        integer(c_int),    value         :: padding_0
        integer(c_int),    value         :: padding_1
        integer(c_int),    value         :: padding_2
        integer(c_int),    value         :: dilation_0
        integer(c_int),    value         :: dilation_1
        integer(c_int),    value         :: dilation_2
        integer(c_int),    value         :: output_padding_0
        integer(c_int),    value         :: output_padding_1
        integer(c_int),    value         :: output_padding_2
        integer(c_int),    value         :: groups
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_conv_transpose3d_op
    end function mlxc_conv_transpose3d_op
end interface

interface exp
    module function exp_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function exp_array
end interface exp

interface mlx_from
    module function from_r32( x ) result(a)
        real(real32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_r32

    module function from_r64( x ) result(a)
        real(real64), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_r64

    module function from_c32( x ) result(a)
        complex(real32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_c32

    module function from_i32( x ) result(a)
        integer(int32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i32

    module function from_i8( x ) result(a)
        integer(int8), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i8

    module function from_i16( x ) result(a)
        integer(int16), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i16

    module function from_i64( x ) result(a)
        integer(int64), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i64

    module function from_l( x ) result(a)
        logical(c_bool), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_l
end interface mlx_from

interface mlx_to
    module subroutine to_r32( y, a, status )
        real(real32),    target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_r32

    module subroutine to_r64( y, a, status )
        real(real64),    target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_r64

    module subroutine to_c32( y, a, status )
        complex(real32), target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_c32

    module subroutine to_i32( y, a, status )
        integer(int32),  target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i32

    module subroutine to_i8( y, a, status )
        integer(int8),   target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i8

    module subroutine to_i16( y, a, status )
        integer(int16),  target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i16

    module subroutine to_i64( y, a, status )
        integer(int64),  target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i64

    module subroutine to_l( y, a, status )
        logical(c_bool), target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_l
end interface mlx_to

interface mlx_to_alloc
    module subroutine to_alloc_r32( y, a, status )
        real(real32),    allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_r32

    module subroutine to_alloc_r64( y, a, status )
        real(real64),    allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_r64

    module subroutine to_alloc_c32( y, a, status )
        complex(real32), allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_c32

    module subroutine to_alloc_i32( y, a, status )
        integer(int32),  allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i32

    module subroutine to_alloc_i8( y, a, status )
        integer(int8),   allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i8

    module subroutine to_alloc_i16( y, a, status )
        integer(int16),  allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i16

    module subroutine to_alloc_i64( y, a, status )
        integer(int64),  allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i64

    module subroutine to_alloc_l( y, a, status )
        logical(c_bool), allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_l
end interface mlx_to_alloc

interface mlx_item
    module subroutine item_r32( a, value, status )
        type(mlx_array), intent(in)            :: a
        real(real32),    intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_r32

    module subroutine item_r64( a, value, status )
        type(mlx_array), intent(in)            :: a
        real(real64),    intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_r64

    module subroutine item_c32( a, value, status )
        type(mlx_array), intent(in)            :: a
        complex(real32), intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_c32

    module subroutine item_i8( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int8),   intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i8

    module subroutine item_i16( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int16),  intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i16

    module subroutine item_i32( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int32),  intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i32

    module subroutine item_i64( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int64),  intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i64

    module subroutine item_l( a, value, status )
        type(mlx_array), intent(in)            :: a
        logical(c_bool), intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_l
end interface mlx_item

interface mlx_view
    module subroutine view_r32( a, p, status )
        type(mlx_array), intent(in)             :: a
        real(real32),    pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_r32

    module subroutine view_r64( a, p, status )
        type(mlx_array), intent(in)             :: a
        real(real64),    pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_r64

    module subroutine view_c32( a, p, status )
        type(mlx_array), intent(in)             :: a
        complex(real32), pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_c32

    module subroutine view_i32( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int32),  pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i32

    module subroutine view_i8( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int8),   pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i8

    module subroutine view_i16( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int16),  pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i16

    module subroutine view_i64( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int64),  pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i64

    module subroutine view_l( a, p, status )
        type(mlx_array), intent(in)             :: a
        logical(c_bool), pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_l
end interface mlx_view

interface mlx_alloc
    module function alloc_r32( fshape, mold, view, status, zero_copy ) result(a)
        integer,      intent(in)             :: fshape(:)
        real(real32), intent(in)             :: mold
        real(real32), pointer, intent(inout) :: view(..)
        integer,      optional, intent(out)  :: status
        logical,      optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_r32

    module function alloc_r64( fshape, mold, view, status, zero_copy ) result(a)
        integer,      intent(in)             :: fshape(:)
        real(real64), intent(in)             :: mold
        real(real64), pointer, intent(inout) :: view(..)
        integer,      optional, intent(out)  :: status
        logical,      optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_r64

    module function alloc_c32( fshape, mold, view, status, zero_copy ) result(a)
        integer,         intent(in)             :: fshape(:)
        complex(real32), intent(in)             :: mold
        complex(real32), pointer, intent(inout) :: view(..)
        integer,         optional, intent(out)  :: status
        logical,         optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_c32

    module function alloc_i32( fshape, mold, view, status, zero_copy ) result(a)
        integer,        intent(in)             :: fshape(:)
        integer(int32), intent(in)             :: mold
        integer(int32), pointer, intent(inout) :: view(..)
        integer,        optional, intent(out)  :: status
        logical,        optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i32

    module function alloc_i8( fshape, mold, view, status, zero_copy ) result(a)
        integer,       intent(in)             :: fshape(:)
        integer(int8), intent(in)             :: mold
        integer(int8), pointer, intent(inout) :: view(..)
        integer,       optional, intent(out)  :: status
        logical,       optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i8

    module function alloc_i16( fshape, mold, view, status, zero_copy ) result(a)
        integer,        intent(in)             :: fshape(:)
        integer(int16), intent(in)             :: mold
        integer(int16), pointer, intent(inout) :: view(..)
        integer,        optional, intent(out)  :: status
        logical,        optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i16

    module function alloc_i64( fshape, mold, view, status, zero_copy ) result(a)
        integer,        intent(in)             :: fshape(:)
        integer(int64), intent(in)             :: mold
        integer(int64), pointer, intent(inout) :: view(..)
        integer,        optional, intent(out)  :: status
        logical,        optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i64

    module function alloc_l( fshape, mold, view, status, zero_copy ) result(a)
        integer,         intent(in)             :: fshape(:)
        logical(c_bool), intent(in)             :: mold
        logical(c_bool), pointer, intent(inout) :: view(..)
        integer,         optional, intent(out)  :: status
        logical,         optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_l
end interface mlx_alloc

interface mlx_eval
    module subroutine eval_one( a, status )
        type(mlx_array), intent(in)            :: a
        integer,         optional, intent(out) :: status
    end subroutine eval_one

    module subroutine eval_list( arrays, status )
        type(mlx_array), intent(in)            :: arrays(:)
        integer,         optional, intent(out) :: status
    end subroutine eval_list
end interface mlx_eval

interface mlx_async_eval
    module subroutine async_eval_one( a, status )
        type(mlx_array), intent(in)            :: a
        integer,         optional, intent(out) :: status
    end subroutine async_eval_one

    module subroutine async_eval_list( arrays, status )
        type(mlx_array), intent(in)            :: arrays(:)
        integer,         optional, intent(out) :: status
    end subroutine async_eval_list
end interface mlx_async_eval

! waiting for queued work: on every device (here), or on one stream (the stream module's specific)
interface mlx_synchronize
    procedure synchronize_all
end interface mlx_synchronize

! the procedures the type binds, the helpers the submodules share, and mlx_synchronize
interface
    module impure elemental subroutine assign_array( lhs, rhs )
        class(mlx_array), intent(inout) :: lhs
        class(mlx_array), intent(in)    :: rhs
    end subroutine assign_array

    module impure elemental subroutine kill_array( self )
        class(mlx_array), intent(inout) :: self
    end subroutine kill_array

    module impure elemental subroutine finalize_array( self )
        type(mlx_array), intent(inout) :: self
    end subroutine finalize_array

    module subroutine adopt( a, h, proc, status )
        type(mlx_array),   intent(inout) :: a
        type(mlxc_array),  intent(in)    :: h
        character(len=*),  intent(in)    :: proc
        integer, optional, intent(out)   :: status
    end subroutine adopt

    module function mlxf_handle( a, proc ) result(h)
        class(mlx_array), intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
    end function mlxf_handle

    module logical function mlx_is_live( a )
        type(mlx_array), intent(in) :: a
    end function mlx_is_live

    module function array_shape( self ) result(s)
        class(mlx_array), intent(in) :: self
        integer, allocatable :: s(:)
    end function array_shape

    module integer function array_ndim( self )
        class(mlx_array), intent(in) :: self
    end function array_ndim

    module integer(int64) function array_size( self )
        class(mlx_array), intent(in) :: self
    end function array_size

    module integer function array_kind( self )
        class(mlx_array), intent(in) :: self
    end function array_kind

    module function data_pointer( h, dtype ) result(p)
        type(mlxc_array), intent(in) :: h
        integer(c_int),   intent(in) :: dtype
        type(c_ptr) :: p
    end function data_pointer

    module pure integer(c_size_t) function itemsize( dtype )
        integer(c_int), intent(in) :: dtype
    end function itemsize

    module subroutine synchronize_all( status )
        integer, optional, intent(out) :: status
    end subroutine synchronize_all

    module integer(int64) function array_nbytes( self )
        class(mlx_array), intent(in) :: self
    end function array_nbytes

    module integer function array_itemsize( self )
        class(mlx_array), intent(in) :: self
    end function array_itemsize

    module function mlx_buffer_size( arrays, status ) result(n)
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        integer(int64) :: n
    end function mlx_buffer_size

    module subroutine mlxf_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_unary

    module subroutine mlxf_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_binary

    module function add_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function add_aa
    module function add_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function add_as
    module function add_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function add_sa
    module function add_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function add_ad
    module function add_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function add_da
    module function sub_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function sub_aa
    module function sub_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_as
    module function sub_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_sa
    module function sub_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_ad
    module function sub_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_da
    module function mul_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function mul_aa
    module function mul_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_as
    module function mul_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_sa
    module function mul_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_ad
    module function mul_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_da
    module function div_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function div_aa
    module function div_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function div_as
    module function div_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function div_sa
    module function div_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function div_ad
    module function div_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function div_da
    module function lt_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function lt_aa
    module function lt_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_as
    module function lt_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_sa
    module function lt_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_ad
    module function lt_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_da
    module function le_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function le_aa
    module function le_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function le_as
    module function le_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function le_sa
    module function le_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function le_ad
    module function le_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function le_da
    module function gt_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function gt_aa
    module function gt_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_as
    module function gt_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_sa
    module function gt_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_ad
    module function gt_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_da
    module function ge_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function ge_aa
    module function ge_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_as
    module function ge_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_sa
    module function ge_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_ad
    module function ge_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_da
    module function eq_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function eq_aa
    module function eq_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_as
    module function eq_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_sa
    module function eq_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_ad
    module function eq_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_da
    module function ne_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function ne_aa
    module function ne_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_as
    module function ne_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_sa
    module function ne_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_ad
    module function ne_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_da
    module function land_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function land_aa
    module function lor_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function lor_aa
    module function pos_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function pos_array
    module function pow_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function pow_aa
    module function pow_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_as
    module function pow_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_sa
    module function pow_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_ad
    module function pow_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_da
    module function eqv_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function eqv_aa
    module function neqv_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function neqv_aa
    module function negate_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function negate_array
    module function not_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function not_array
end interface

interface
    module subroutine mlxf_weak_scalar( r, a, x, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        real(real64),     intent(in)    :: x
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_weak_scalar
end interface

interface
    module subroutine mlxf_dtype_op( r, f, a, dtype, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int_op)          :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: dtype
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_dtype_op
    module subroutine mlxf_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int_op)          :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_int_op
    module subroutine mlxf_vector_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_vector_op)       :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_vector_op
    module subroutine mlxf_reduce_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_reduce_op)             :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_reduce_op
    module subroutine mlxf_ternary_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_ternary_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_ternary_op
    module subroutine mlxf_take_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_take_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_take_op
    module subroutine mlxf_scan_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_op)             :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
    end subroutine mlxf_scan_op
    module subroutine mlxf_slice_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_slice_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_slice_op
    module subroutine mlxf_concat_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_concat_op)       :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_concat_op
    module subroutine mlxf_zeros_op( r, f, shape, dtype, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_zeros_op)        :: f
        integer,          intent(in)    :: shape(:), dtype
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_zeros_op
    module subroutine mlxf_range_op( r, f, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_range_op)             :: f
        type(mlxf_range_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_range_op
    module subroutine mlxf_fft_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_fft_op)             :: f
        type(mlx_array),     intent(in)    :: a
        type(mlxf_fft_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_fft_op
    module subroutine mlxf_fftn_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_fftn_op)             :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_fftn_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
    end subroutine mlxf_fftn_op
    module subroutine mlxf_freq_op( r, f, n, d, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_freq_op)         :: f
        integer,          intent(in)    :: n
        real(c_double),   intent(in)    :: d
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_freq_op
    module subroutine mlxf_close_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_close_op)             :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_close_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_close_op
    module subroutine mlxf_compare_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_compare_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_compare_op
    module subroutine mlxf_nan_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_nan_op)             :: f
        type(mlx_array),     intent(in)    :: a
        type(mlxf_nan_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_nan_op
    module subroutine mlxf_binary_vector_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_binary_vector_op)           :: f
        type(mlx_array),  intent(in)               :: a(:)
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_binary_vector_op
    module subroutine mlxf_full_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_full_op)              :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_shape_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_full_op
    module subroutine mlxf_binary_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_int_op)   :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_binary_int_op
    module subroutine mlxf_reduce_all_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_flag_op)               :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_reduce_all_op
    module subroutine mlxf_reduce_dims_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_reduce_dims_op)        :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_reduce_dims_op
    module subroutine mlxf_var_all_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_var_all_op)            :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_var_all_op
    module subroutine mlxf_var_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_var_op)                :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_var_op
    module subroutine mlxf_var_dims_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_var_dims_op)           :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_var_dims_op
    module subroutine mlxf_int2_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int2_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_int2_op
    module subroutine mlxf_int3_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int3_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(3)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_int3_op
    module subroutine mlxf_trace_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_trace_op)        :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(4)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_trace_op
    module subroutine mlxf_scan_all_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_all_op)         :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
    end subroutine mlxf_scan_all_op
    module subroutine mlxf_scan_plain_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_plain_op)       :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
    end subroutine mlxf_scan_plain_op
    module subroutine mlxf_scan_plain_all_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_scan_plain_all_op)   :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_scan_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
    end subroutine mlxf_scan_plain_all_op
    module subroutine mlxf_roll_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_roll_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_roll_op
    module subroutine mlxf_unflatten_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unflatten_op)    :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_unflatten_op
    module subroutine mlxf_vector2_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_vector2_op)      :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:,:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_vector2_op
    module subroutine mlxf_strided_op( r, f, a, option, proc )
        type(mlx_array),         intent(inout) :: r
        procedure(mlxc_strided_op)             :: f
        type(mlx_array),         intent(in)    :: a
        type(mlxf_strided_spec), intent(in)    :: option
        character(len=*),        intent(in)    :: proc
    end subroutine mlxf_strided_op
    module subroutine mlxf_count_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_count_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_count_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_count_op
    module subroutine mlxf_window_op( r, f, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_window_op)       :: f
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_window_op
    module subroutine mlxf_identity_op( r, f, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_identity_op)     :: f
        integer,          intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_identity_op
    module subroutine mlxf_eye_op( r, f, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_eye_op)          :: f
        integer,          intent(in)    :: option(4)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_eye_op
    module subroutine mlxf_linspace_op( r, f, option, proc )
        type(mlx_array),          intent(inout) :: r
        procedure(mlxc_linspace_op)             :: f
        type(mlxf_linspace_spec), intent(in)    :: option
        character(len=*),         intent(in)    :: proc
    end subroutine mlxf_linspace_op
    module subroutine mlxf_linspace_endpoint_op( r, f, option, proc )
        type(mlx_array),          intent(inout) :: r
        procedure(mlxc_linspace_endpoint_op)    :: f
        type(mlxf_linspace_spec), intent(in)    :: option
        character(len=*),         intent(in)    :: proc
    end subroutine mlxf_linspace_endpoint_op
    module subroutine mlxf_list_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_list_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_list_op
    module subroutine mlxf_vector_list_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_vector_list_op)             :: f
        type(mlx_array),  intent(in)               :: a(:)
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_vector_list_op
    module subroutine mlxf_meshgrid_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_meshgrid_op)                :: f
        type(mlx_array),  intent(in)               :: a(:)
        logical,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_meshgrid_op
    module subroutine mlxf_split_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_split_op)                   :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option(2)
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_split_op
    module subroutine mlxf_split_sections_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_split_sections_op)          :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option(:)
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_split_sections_op
    module subroutine mlxf_unstack_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_op)                 :: f
        type(mlx_array),  intent(in)               :: a
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_unstack_op
    module subroutine mlxf_unstack_dim_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_dim_op)             :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_unstack_dim_op
    module subroutine mlxf_pad_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_pad_op)             :: f
        type(mlx_array),     intent(in)    :: a(:)
        type(mlxf_pad_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_pad_op
    module subroutine mlxf_pad_width_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_pad_width_op)       :: f
        type(mlx_array),     intent(in)    :: a(:)
        type(mlxf_pad_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_pad_width_op
    module subroutine mlxf_gather_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_gather_op)            :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_index_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_gather_op
    module subroutine mlxf_gather_single_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_gather_single_op)     :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_index_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_gather_single_op
    module subroutine mlxf_slice_dynamic_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_dynamic_op)     :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_index_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_slice_dynamic_op
    module subroutine mlxf_scatter_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_scatter_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_scatter_op
    module subroutine mlxf_put_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_put_op)          :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_put_op
    module subroutine mlxf_ternary_vector_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout)   :: r
        procedure(mlxc_ternary_vector_op) :: f
        type(mlx_array),  intent(in)      :: a(:)
        integer,          intent(in)      :: option(:)
        character(len=*), intent(in)      :: proc
    end subroutine mlxf_ternary_vector_op
    module subroutine mlxf_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_text_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_text_op
    module subroutine mlxf_slice_update_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_update_op)      :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_slice_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_slice_update_op
    module subroutine mlxf_unique_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unique_op)                  :: f
        type(mlx_array),  intent(in)               :: a(:)
        integer,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_unique_op
    module subroutine check_dim( a, dim, proc )
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dim
        character(len=*), intent(in) :: proc
    end subroutine check_dim
    module subroutine mlxf_check_dtype( dtype, proc )
        integer,          intent(in) :: dtype
        character(len=*), intent(in) :: proc
    end subroutine mlxf_check_dtype
    module function mlxf_axes_of( a, dims, proc ) result(axes)
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dims(:)
        character(len=*), intent(in) :: proc
        integer(c_int), allocatable :: axes(:)
    end function mlxf_axes_of
    module subroutine mlxf_zero_based( r, indices, proc, less )
        type(mlx_array),  intent(inout)        :: r
        type(mlx_array),  intent(in)           :: indices
        character(len=*), intent(in)           :: proc
        integer,          optional, intent(in) :: less(:)
    end subroutine mlxf_zero_based
    module subroutine mlxf_gather_mm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_gather_mm_op)    :: f
        type(mlx_array),  intent(in)    :: a(4)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_gather_mm_op
    module subroutine mlxf_masked_mm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_masked_mm_op)    :: f
        type(mlx_array),  intent(in)    :: a(5)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_masked_mm_op
    module subroutine mlxf_one_based( r, idx, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: idx
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_one_based
    module subroutine mlxf_cpu_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_cpu_unary
    module subroutine mlxf_cpu_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_cpu_binary
    module subroutine mlxf_cpu_flag_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_flag_op)         :: f
        type(mlx_array),  intent(in)    :: a
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_cpu_flag_op
    module subroutine mlxf_cpu_compare_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_compare_op)      :: f
        type(mlx_array),  intent(in)    :: a(2)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_cpu_compare_op
    module subroutine mlxf_cpu_pair_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_op)         :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_cpu_pair_op
    module subroutine mlxf_cpu_pair_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_text_op)    :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_cpu_pair_text_op
    module subroutine mlxf_cpu_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_text_op)   :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_cpu_text_op
    module subroutine mlxf_cpu_unstack_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_op)                 :: f
        type(mlx_array),  intent(in)               :: a
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_cpu_unstack_op
    module subroutine mlxf_cpu_svd_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_vector_flag_op)             :: f
        type(mlx_array),  intent(in)               :: a
        logical,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_cpu_svd_op
    module subroutine mlxf_norm_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_norm_op)             :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_norm_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
    end subroutine mlxf_norm_op
    module subroutine mlxf_norm_text_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_norm_text_op)        :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_norm_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
    end subroutine mlxf_norm_text_op
    module subroutine mlxf_binary_axis_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_take_op)         :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_binary_axis_op
    module subroutine mlxf_optional_float_op( r, f, a, proc, option )
        type(mlx_array),  intent(inout)        :: r
        procedure(mlxc_optional_float_op)      :: f
        type(mlx_array),  intent(in)           :: a
        character(len=*), intent(in)           :: proc
        real(real32),     optional, intent(in) :: option
    end subroutine mlxf_optional_float_op
    module subroutine mlxf_addmm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_addmm_op)        :: f
        type(mlx_array),  intent(in)    :: a(3)
        real(real32),     intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_addmm_op
    module subroutine mlxf_einsum_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_einsum_op)       :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_einsum_op
    module subroutine mlxf_tensordot_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_tensordot_op)    :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option(:,:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_tensordot_op
    module subroutine mlxf_conv1d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv1d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_conv1d_op
    module subroutine mlxf_conv2d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv2d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_conv2d_op
    module subroutine mlxf_conv3d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv3d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_conv3d_op
    module subroutine mlxf_conv_general_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv_general_op)    :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_conv_general_op
    module subroutine mlxf_conv_transpose1d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose1d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
    end subroutine mlxf_conv_transpose1d_op
    module subroutine mlxf_conv_transpose2d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose2d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
    end subroutine mlxf_conv_transpose2d_op
    module subroutine mlxf_conv_transpose3d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose3d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
    end subroutine mlxf_conv_transpose3d_op
    module function vector_of( arrays, proc ) result(v)
        type(mlx_array),  intent(in) :: arrays(:)
        character(len=*), intent(in) :: proc
        type(mlxc_vector_array) :: v
    end function vector_of
end interface

abstract interface
    ! int f(mlx_array* res, uint64_t seed)
    function mlxc_random_key_op( res, seed ) bind(c)
        import
        type(mlxc_array),   intent(inout) :: res
        integer(c_int64_t), value         :: seed
        integer(c_int) :: mlxc_random_key_op
    end function mlxc_random_key_op
    ! int f(mlx_array* res, const int* shape, size_t shape_num, int number, const mlx_array key, const mlx_stream s)
    function mlxc_random_shape_op( res, shape, shape_num, number, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        integer(c_int),    intent(in)    :: shape(*)
        integer(c_size_t), value         :: shape_num
        integer(c_int),    value         :: number
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_shape_op
    end function mlxc_random_shape_op
    ! int f(mlx_array* res, const int* shape, size_t shape_num, mlx_dtype dtype, float loc, float scale,
    ! const mlx_array key, const mlx_stream s)
    function mlxc_random_float_op( res, shape, shape_num, dtype, loc, scale, key, s ) bind(c)
        import
        type(mlxc_array),   intent(inout) :: res
        integer(c_int),     intent(in)    :: shape(*)
        integer(c_size_t),  value         :: shape_num
        integer(c_int),     value         :: dtype
        real(c_float_kind), value         :: loc
        real(c_float_kind), value         :: scale
        type(mlxc_array),   value         :: key
        type(mlxc_stream),  value         :: s
        integer(c_int) :: mlxc_random_float_op
    end function mlxc_random_float_op
    ! int f(mlx_array* res, int x, const mlx_array key, const mlx_stream s)
    function mlxc_random_int_op( res, x, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        integer(c_int),    value         :: x
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_int_op
    end function mlxc_random_int_op
    ! int f(mlx_array* res, const mlx_array p, const int* shape, size_t shape_num, const mlx_array key,
    ! const mlx_stream s)
    function mlxc_random_array_op( res, p, shape, shape_num, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: p
        integer(c_int),    intent(in)    :: shape(*)
        integer(c_size_t), value         :: shape_num
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_array_op
    end function mlxc_random_array_op
    ! int f(mlx_array* res, const mlx_array x, int axis, const mlx_array key, const mlx_stream s)
    function mlxc_random_axis_op( res, x, axis, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: x
        integer(c_int),    value         :: axis
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_axis_op
    end function mlxc_random_axis_op
    ! int f(mlx_array* res, const mlx_array logits, int axis, const int* shape, size_t shape_num,
    ! const mlx_array key, const mlx_stream s)
    function mlxc_random_axis_shape_op( res, logits, axis, shape, shape_num, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: logits
        integer(c_int),    value         :: axis
        integer(c_int),    intent(in)    :: shape(*)
        integer(c_size_t), value         :: shape_num
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_axis_shape_op
    end function mlxc_random_axis_shape_op
    ! int f(mlx_array* res, const mlx_array logits, int axis, int num_samples, const mlx_array key,
    ! const mlx_stream s)
    function mlxc_random_axis_int_op( res, logits, axis, num_samples, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: logits
        integer(c_int),    value         :: axis
        integer(c_int),    value         :: num_samples
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_axis_int_op
    end function mlxc_random_axis_int_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const int* shape, size_t shape_num,
    ! mlx_dtype dtype, const mlx_array key, const mlx_stream s)
    function mlxc_random_binary_op( res, a, b, shape, shape_num, dtype, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_array),  value         :: b
        integer(c_int),    intent(in)    :: shape(*)
        integer(c_size_t), value         :: shape_num
        integer(c_int),    value         :: dtype
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_binary_op
    end function mlxc_random_binary_op
    ! int f(mlx_array* res, const int* shape, size_t shape_num, mlx_dtype dtype, const mlx_array loc,
    ! const mlx_array scale, const mlx_array key, const mlx_stream s)
    function mlxc_random_broadcast_op( res, shape, shape_num, dtype, loc, scale, key, s ) bind(c)
        import
        type(mlxc_array),  intent(inout) :: res
        integer(c_int),    intent(in)    :: shape(*)
        integer(c_size_t), value         :: shape_num
        integer(c_int),    value         :: dtype
        type(mlxc_array),  value         :: loc
        type(mlxc_array),  value         :: scale
        type(mlxc_array),  value         :: key
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_random_broadcast_op
    end function mlxc_random_broadcast_op
end interface

interface
    module function cpu_stream( proc ) result(s)
        character(len=*), intent(in) :: proc
        type(mlxc_stream) :: s
    end function cpu_stream
    module function optional_handle( a, proc ) result(h)
        type(mlx_array),  intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
    end function optional_handle
    module subroutine mlxf_pair_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_op)         :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_pair_op
    module subroutine mlxf_random_key_op( r, f, seed, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_random_key_op)   :: f
        integer(int64),   intent(in)    :: seed
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_random_key_op
    module subroutine mlxf_random_shape_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_shape_op)       :: f
        type(mlx_array),        intent(in)    :: a(1)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_random_shape_op
    module subroutine mlxf_random_float_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_float_op)       :: f
        type(mlx_array),        intent(in)    :: a(1)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_random_float_op
    module subroutine mlxf_random_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_random_int_op)   :: f
        type(mlx_array),  intent(in)    :: a(1)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_random_int_op
    module subroutine mlxf_random_array_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_array_op)       :: f
        type(mlx_array),        intent(in)    :: a(2)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_random_array_op
    module subroutine mlxf_random_axis_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_random_axis_op)  :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_random_axis_op
    module subroutine mlxf_random_axis_shape_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_axis_shape_op)  :: f
        type(mlx_array),        intent(in)    :: a(2)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_random_axis_shape_op
    module subroutine mlxf_random_axis_int_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_axis_int_op)    :: f
        type(mlx_array),        intent(in)    :: a(2)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_random_axis_int_op
    module subroutine mlxf_random_binary_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_binary_op)      :: f
        type(mlx_array),        intent(in)    :: a(3)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_random_binary_op
    module subroutine mlxf_random_broadcast_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_broadcast_op)   :: f
        type(mlx_array),        intent(in)    :: a(3)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_random_broadcast_op
end interface

abstract interface
    ! int f(mlx_array* res, const mlx_array x, const mlx_array weight, const mlx_array bias, float eps,
    ! const mlx_stream s)
    function mlxc_layer_norm_op( res, x, weight, bias, eps, s ) bind(c)
        import
        type(mlxc_array),   intent(inout) :: res
        type(mlxc_array),   value         :: x
        type(mlxc_array),   value         :: weight
        type(mlxc_array),   value         :: bias
        real(c_float_kind), value         :: eps
        type(mlxc_stream),  value         :: s
        integer(c_int) :: mlxc_layer_norm_op
    end function mlxc_layer_norm_op
    ! int f(mlx_array* res, const mlx_array x, const mlx_array weight, float eps, const mlx_stream s)
    function mlxc_rms_norm_op( res, x, weight, eps, s ) bind(c)
        import
        type(mlxc_array),   intent(inout) :: res
        type(mlxc_array),   value         :: x
        type(mlxc_array),   value         :: weight
        real(c_float_kind), value         :: eps
        type(mlxc_stream),  value         :: s
        integer(c_int) :: mlxc_rms_norm_op
    end function mlxc_rms_norm_op
    ! int f(mlx_array* res, const mlx_array x, int dims, bool traditional, mlx_optional_float base, float scale,
    ! int offset, const mlx_array freqs, const mlx_stream s)
    function mlxc_rope_op( res, x, dims, traditional, base, scale, offset, freqs, s ) bind(c)
        import
        type(mlxc_array),          intent(inout) :: res
        type(mlxc_array),          value         :: x
        integer(c_int),            value         :: dims
        logical(c_bool),           value         :: traditional
        type(mlxc_optional_float), value         :: base
        real(c_float_kind),        value         :: scale
        integer(c_int),            value         :: offset
        type(mlxc_array),          value         :: freqs
        type(mlxc_stream),         value         :: s
        integer(c_int) :: mlxc_rope_op
    end function mlxc_rope_op
    ! int f(mlx_array* res, const mlx_array x, int dims, bool traditional, mlx_optional_float base, float scale,
    ! const mlx_array offset, const mlx_array freqs, const mlx_stream s)
    function mlxc_rope_dynamic_op( res, x, dims, traditional, base, scale, offset, freqs, s ) bind(c)
        import
        type(mlxc_array),          intent(inout) :: res
        type(mlxc_array),          value         :: x
        integer(c_int),            value         :: dims
        logical(c_bool),           value         :: traditional
        type(mlxc_optional_float), value         :: base
        real(c_float_kind),        value         :: scale
        type(mlxc_array),          value         :: offset
        type(mlxc_array),          value         :: freqs
        type(mlxc_stream),         value         :: s
        integer(c_int) :: mlxc_rope_dynamic_op
    end function mlxc_rope_dynamic_op
    ! int f(mlx_array* res, const mlx_array queries, const mlx_array keys, const mlx_array values, float scale,
    ! const char* mask_mode, const mlx_array mask_arr, const mlx_array sinks, bool force_fused, const mlx_stream s)
    function mlxc_attention_op( res, queries, keys, values, scale, mask_mode, mask_arr, sinks, force_fused, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res
        type(mlxc_array),       value         :: queries
        type(mlxc_array),       value         :: keys
        type(mlxc_array),       value         :: values
        real(c_float_kind),     value         :: scale
        character(kind=c_char), intent(in)    :: mask_mode(*)
        type(mlxc_array),       value         :: mask_arr
        type(mlxc_array),       value         :: sinks
        logical(c_bool),        value         :: force_fused
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_attention_op
    end function mlxc_attention_op
end interface

interface
    module subroutine mlxf_layer_norm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_layer_norm_op)   :: f
        type(mlx_array),  intent(in)    :: a(3)
        real(real32),     intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_layer_norm_op
    module subroutine mlxf_rms_norm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_rms_norm_op)     :: f
        type(mlx_array),  intent(in)    :: a(2)
        real(real32),     intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_rms_norm_op
    module subroutine mlxf_rope_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_rope_op)            :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_rope_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_rope_op
    module subroutine mlxf_rope_dynamic_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_rope_dynamic_op)    :: f
        type(mlx_array),     intent(in)    :: a(3)
        type(mlx_rope_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_rope_dynamic_op
    module subroutine mlxf_attention_op( r, f, a, option, proc )
        type(mlx_array),          intent(inout) :: r
        procedure(mlxc_attention_op)            :: f
        type(mlx_array),          intent(in)    :: a(4)
        type(mlx_attention_spec), intent(in)    :: option
        character(len=*),         intent(in)    :: proc
    end subroutine mlxf_attention_op
end interface

abstract interface
    ! int f(mlx_array* res, const char* file, const mlx_stream s)
    function mlxc_load_op( res, file, s ) bind(c)
        import
        type(mlxc_array),       intent(inout) :: res
        character(kind=c_char), intent(in)    :: file(*)
        type(mlxc_stream),      value         :: s
        integer(c_int) :: mlxc_load_op
    end function mlxc_load_op
    ! int f(mlx_array* res, const mlx_array x, const mlx_distributed_group group, const mlx_stream s)
    function mlxc_group_op( res, x, group, s ) bind(c)
        import
        type(mlxc_array),             intent(inout) :: res
        type(mlxc_array),             value         :: x
        type(mlxc_distributed_group), value         :: group
        type(mlxc_stream),            value         :: s
        integer(c_int) :: mlxc_group_op
    end function mlxc_group_op
    ! int f(mlx_array* res, const mlx_array x, int peer, const mlx_distributed_group group, const mlx_stream s)
    function mlxc_group_peer_op( res, x, peer, group, s ) bind(c)
        import
        type(mlxc_array),             intent(inout) :: res
        type(mlxc_array),             value         :: x
        integer(c_int),               value         :: peer
        type(mlxc_distributed_group), value         :: group
        type(mlxc_stream),            value         :: s
        integer(c_int) :: mlxc_group_peer_op
    end function mlxc_group_peer_op
    ! int f(mlx_array* res, const int* shape, size_t shape_num, mlx_dtype dtype, int src,
    ! const mlx_distributed_group group, const mlx_stream s)
    function mlxc_group_recv_op( res, shape, shape_num, dtype, src, group, s ) bind(c)
        import
        type(mlxc_array),             intent(inout) :: res
        integer(c_int),               intent(in)    :: shape(*)
        integer(c_size_t),            value         :: shape_num
        integer(c_int),               value         :: dtype
        integer(c_int),               value         :: src
        type(mlxc_distributed_group), value         :: group
        type(mlxc_stream),            value         :: s
        integer(c_int) :: mlxc_group_recv_op
    end function mlxc_group_recv_op
end interface

interface
    module function mlxf_cpu_stream( proc ) result(s)
        character(len=*), intent(in) :: proc
        type(mlxc_stream) :: s
    end function mlxf_cpu_stream
    module subroutine mlxf_load_op( r, f, file, proc, status )
        type(mlx_array),   intent(inout) :: r
        procedure(mlxc_load_op)          :: f
        character(len=*),  intent(in)    :: file, proc
        integer, optional, intent(out)   :: status
    end subroutine mlxf_load_op
    module subroutine mlxf_map_arrays( names, arrays, m, status )
        character(len=:),               allocatable, intent(out) :: names(:)
        type(mlx_array),                allocatable, intent(out) :: arrays(:)
        type(mlxc_map_string_to_array), intent(in)               :: m
        integer,                        intent(out)              :: status
    end subroutine mlxf_map_arrays
    module subroutine mlxf_gguf_arrays( names, arrays, g, status )
        character(len=:),   allocatable, intent(out) :: names(:)
        type(mlx_array),    allocatable, intent(out) :: arrays(:)
        type(mlxc_io_gguf), intent(in)               :: g
        integer,            intent(out)              :: status
    end subroutine mlxf_gguf_arrays
    module subroutine mlxf_group_op( r, f, a, option, status )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_group_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_group_spec), intent(in)    :: option
        integer, optional,     intent(out)   :: status
    end subroutine mlxf_group_op
    module subroutine mlxf_group_peer_op( r, f, a, option, status )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_group_peer_op)        :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_group_spec), intent(in)    :: option
        integer, optional,     intent(out)   :: status
    end subroutine mlxf_group_peer_op
    module subroutine mlxf_group_recv_op( r, f, option, status )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_group_recv_op)        :: f
        type(mlxf_group_spec), intent(in)    :: option
        integer, optional,     intent(out)   :: status
    end subroutine mlxf_group_recv_op
end interface

interface
    module subroutine mlxf_vector_import( arrays, v, status )
        type(mlx_array),         allocatable, intent(out) :: arrays(:)
        type(mlxc_vector_array), intent(in)               :: v
        integer,                 intent(out)              :: status
    end subroutine mlxf_vector_import
    module subroutine mlxf_vector_export( v, arrays, status )
        type(mlxc_vector_array), intent(inout) :: v
        type(mlx_array),         intent(in)    :: arrays(:)
        integer,                 intent(out)   :: status
    end subroutine mlxf_vector_export
end interface

end module mlxf_array
