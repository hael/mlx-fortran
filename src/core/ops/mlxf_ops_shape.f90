!@descr: shape operations through the array signature helpers
! Every dimension argument is a Fortran dimension, translated here to MLX axis rank - dim; shapes, repetitions
! and widths are per Fortran dimension and reversed for MLX; split positions are 1-based.
module mlxf_ops_shape
use, intrinsic :: iso_c_binding,   only: c_int64_t
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf_c_ops,        only: mlxc_arange, mlxc_as_strided, mlxc_atleast_1d, mlxc_atleast_2d, mlxc_atleast_3d, &
                             mlxc_broadcast_arrays, mlxc_broadcast_to, mlxc_contiguous, mlxc_concatenate, &
                             mlxc_concatenate_axis, mlxc_diag, mlxc_diagonal, mlxc_diff, mlxc_expand_dims, &
                             mlxc_expand_dims_axes, mlxc_flatten, mlxc_flip, mlxc_flip_axes, mlxc_flip_axis, &
                             mlxc_matrix_transpose, mlxc_moveaxis, mlxc_number_of_elements, mlxc_pad, &
                             mlxc_pad_symmetric, mlxc_repeat, mlxc_repeat_axis, mlxc_reshape, mlxc_roll, &
                             mlxc_roll_axes, mlxc_roll_axis, mlxc_slice, mlxc_split, mlxc_split_sections, mlxc_squeeze, &
                             mlxc_squeeze_axes, mlxc_squeeze_axis, mlxc_stack, mlxc_stack_axis, mlxc_swapaxes, &
                             mlxc_take, mlxc_take_along_axis, mlxc_take_axis, mlxc_tile, mlxc_trace, mlxc_trace_axes, &
                             mlxc_transpose, mlxc_transpose_axes, mlxc_tril, mlxc_triu, mlxc_unflatten, mlxc_unstack, &
                             mlxc_unstack_axis, mlxc_zeros, mlxc_slice_dynamic
use mlxf_c_signatures, only: mlxc_concat_op, mlxc_count_op, mlxc_int3_op, mlxc_pad_op, mlxc_pad_width_op, &
                             mlxc_range_op, mlxc_roll_op, mlxc_slice_dynamic_op, mlxc_slice_op, mlxc_split_op, &
                             mlxc_split_sections_op, mlxc_strided_op, mlxc_take_op, mlxc_trace_op, mlxc_unflatten_op, &
                             mlxc_unstack_dim_op, mlxc_unstack_op, mlxc_vector2_op, mlxc_vector_list_op
use mlxf_defs,         only: MLX_DTYPES, mlxf_slice_spec, mlxf_range_spec, mlxf_pad_spec, mlxf_strided_spec, &
                             mlxf_count_spec, mlxf_reduce_spec, mlxf_index_spec
use mlxf_error,        only: mlxf_fail
use mlxf_device,       only: mlxf_enter
use mlxf_array,        only: mlx_array
use mlxf_calls,        only: mlxf_binary, mlxf_int2_op, mlxf_int_op, mlxf_list_op, mlxf_reduce_all_op, mlxf_unary, &
                             mlxf_vector_op, mlxf_zero_based, mlxf_zeros_op
use mlxf_transfer,     only: mlx_from
implicit none

public :: reshape, mlx_permute, transpose, mlx_concatenate, mlx_slice, mlx_take_along_dim, mlx_take, mlx_zeros, &
    &mlx_arange, mlx_squeeze, mlx_expand_dims, mlx_flatten, mlx_unflatten, mlx_broadcast_to, mlx_broadcast_arrays, &
    &mlx_tile, mlx_repeat, mlx_pad, mlx_flip, cshift, mlx_movedim, mlx_swapdims, mlx_split, mlx_stack, mlx_unstack, &
    &mlx_atleast_1d, mlx_atleast_2d, mlx_atleast_3d, mlx_diag, mlx_diagonal, mlx_trace, mlx_tril, mlx_triu, mlx_diff, &
    &mlx_as_strided, mlx_number_of_elements, axis_of, axes_of
private

interface reshape
    module procedure reshape_array
end interface reshape

interface transpose
    module procedure transpose_array
end interface transpose

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

interface mlx_split
    module procedure split_equal, split_at
end interface mlx_split

! the signature helpers of the shape operations, implemented in mlxf_ops_shape_calls
interface
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, int axis, const mlx_stream s)
    module subroutine mlxf_take_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_take_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_take_op

    ! int f(mlx_array* res, const mlx_array a, const int* start, size_t start_num, const int* stop,
    ! size_t stop_num, const int* strides, size_t strides_num, const mlx_stream s)
    module subroutine mlxf_slice_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_slice_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_slice_op

    ! int f(mlx_array* res, const mlx_vector_array arrays, int axis, const mlx_stream s)
    module subroutine mlxf_concat_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_concat_op)       :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_concat_op

    ! int f(mlx_array* res, double start, double stop, double step, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_range_op( r, f, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_range_op)             :: f
        type(mlxf_range_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_range_op

    ! int f(mlx_array* res, const mlx_array a, int i, int j, int k, const mlx_stream s)
    module subroutine mlxf_int3_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int3_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(3)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_int3_op

    ! int f(mlx_array* res, const mlx_array a, int offset, int axis1, int axis2, mlx_dtype dtype, const mlx_stream
    ! s)
    module subroutine mlxf_trace_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_trace_op)        :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(4)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_trace_op

    ! int f(mlx_array* res, const mlx_array a, const int* shift, size_t shift_num, int axis, const mlx_stream s)
    module subroutine mlxf_roll_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_roll_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_roll_op

    ! int f(mlx_array* res, const mlx_array a, int axis, const int* shape, size_t shape_num, const mlx_stream s)
    module subroutine mlxf_unflatten_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unflatten_op)    :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_unflatten_op

    ! int f(mlx_array* res, const mlx_array a, const int* u, size_t u_num, const int* v, size_t v_num, const
    ! mlx_stream s)
    module subroutine mlxf_vector2_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_vector2_op)      :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:,:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_vector2_op

    ! int f(mlx_array* res, const mlx_array a, const int* shape, size_t shape_num, const int64_t* strides, size_t
    ! strides_num, size_t offset, const mlx_stream s)
    module subroutine mlxf_strided_op( r, f, a, option, proc )
        type(mlx_array),         intent(inout) :: r
        procedure(mlxc_strided_op)             :: f
        type(mlx_array),         intent(in)    :: a
        type(mlxf_strided_spec), intent(in)    :: option
        character(len=*),        intent(in)    :: proc
    end subroutine mlxf_strided_op

    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool inverted, mlx_dtype dtype,
    ! const mlx_stream s)
    module subroutine mlxf_count_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_count_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_count_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_count_op

    ! int f(mlx_vector_array* res, const mlx_vector_array inputs, const mlx_stream s)
    module subroutine mlxf_vector_list_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_vector_list_op)             :: f
        type(mlx_array),  intent(in)               :: a(:)
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_vector_list_op

    ! int f(mlx_vector_array* res, const mlx_array a, int num_splits, int axis, const mlx_stream s)
    module subroutine mlxf_split_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_split_op)                   :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option(2)
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_split_op

    ! int f(mlx_vector_array* res, const mlx_array a, const int* indices, size_t indices_num, int axis, const
    ! mlx_stream s)
    module subroutine mlxf_split_sections_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_split_sections_op)          :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option(:)
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_split_sections_op

    ! int f(mlx_vector_array* res, const mlx_array a, const mlx_stream s)
    module subroutine mlxf_unstack_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_op)                 :: f
        type(mlx_array),  intent(in)               :: a
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_unstack_op

    ! int f(mlx_vector_array* res, const mlx_array a, int axis, const mlx_stream s)
    module subroutine mlxf_unstack_dim_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_dim_op)             :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
    end subroutine mlxf_unstack_dim_op

    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, const int* low_pad_size, size_t
    ! low_pad_size_num, const int* high_pad_size, size_t high_pad_size_num, const mlx_array pad_value, const char*
    ! mode, const mlx_stream s)
    module subroutine mlxf_pad_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_pad_op)             :: f
        type(mlx_array),     intent(in)    :: a(:)
        type(mlxf_pad_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_pad_op

    ! int f(mlx_array* res, const mlx_array a, int pad_width, const mlx_array pad_value, const char* mode, const
    ! mlx_stream s)
    module subroutine mlxf_pad_width_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_pad_width_op)       :: f
        type(mlx_array),     intent(in)    :: a(:)
        type(mlxf_pad_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_pad_width_op

    ! int f(mlx_array* res, const mlx_array a, const mlx_array start, const int* axes, size_t axes_num, const int*
    ! slice_size, size_t slice_size_num, const mlx_stream s)
    module subroutine mlxf_slice_dynamic_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_dynamic_op)     :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_index_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_slice_dynamic_op
end interface

contains

    ! Fortran's column-major reshape: the reversed shape gives MLX's row-major reshape of the same bytes
    function reshape_array( a, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shape(:)
        type(mlx_array) :: r
        call mlxf_vector_op(r, mlxc_reshape, a, shape(size(shape):1:-1), 'reshape')
    end function reshape_array

    ! dimension i of the result is dimension order(i) of a; order is a permutation of 1 to the rank
    function mlx_permute( a, order ) result(r)
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

    ! swaps dimensions 1 and 2, every other dimension a batch; MLX's transpose of a matrix, its matrix
    ! transpose of a higher rank
    function transpose_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        integer         :: nd
        call mlxf_enter('transpose')
        nd = a%ndim()
        if( nd < 2 ) call mlxf_fail('transpose', 'rank must be at least two')
        if( nd == 2 )then
            call mlxf_unary(r, mlxc_transpose, a, 'transpose')
        else
            call mlxf_unary(r, mlxc_matrix_transpose, a, 'transpose')
        endif
    end function transpose_array

    ! the arrays joined along Fortran dimension dim, their other extents agreeing; without dim, the elements of
    ! each in array element order, joined into a rank-1 result
    function mlx_concatenate( arrays, dim ) result(r)
        type(mlx_array), intent(in)           :: arrays(:)
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_concatenate')
        if( size(arrays) == 0 ) call mlxf_fail('mlx_concatenate', 'empty list')
        if( present(dim) )then
            call mlxf_concat_op(r, mlxc_concatenate_axis, arrays, axis_of(arrays(1)%ndim(), dim, 'mlx_concatenate'), 'mlx_concatenate')
        else
            call mlxf_list_op(r, mlxc_concatenate, arrays, 'mlx_concatenate')
        endif
    end function mlx_concatenate

    ! the arrays, of one shape, joined along a new dimension at position dim of the result, the last when absent
    function mlx_stack( arrays, dim ) result(r)
        type(mlx_array), intent(in)           :: arrays(:)
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_stack')
        if( size(arrays) == 0 ) call mlxf_fail('mlx_stack', 'empty list')
        if( present(dim) )then
            call mlxf_concat_op(r, mlxc_stack_axis, arrays, axis_of(arrays(1)%ndim()+1, dim, 'mlx_stack'), 'mlx_stack')
        else
            call mlxf_list_op(r, mlxc_stack, arrays, 'mlx_stack')
        endif
    end function mlx_stack

    ! the slices of a along dim, the last dimension when absent, each without that dimension
    subroutine mlx_unstack( a, parts, dim )
        type(mlx_array), intent(in)               :: a
        type(mlx_array), allocatable, intent(out) :: parts(:)
        integer,         optional, intent(in)     :: dim
        call mlxf_enter('mlx_unstack')
        if( present(dim) )then
            call mlxf_unstack_dim_op(parts, mlxc_unstack_axis, a, axis_of(a%ndim(), dim, 'mlx_unstack'), 'mlx_unstack')
        else
            call mlxf_unstack_op(parts, mlxc_unstack, a, 'mlx_unstack')
        endif
    end subroutine mlx_unstack

    ! a cut into num equal parts along dim, the last dimension when absent
    subroutine split_equal( a, num, parts, dim )
        type(mlx_array), intent(in)               :: a
        integer,         intent(in)               :: num
        type(mlx_array), allocatable, intent(out) :: parts(:)
        integer,         optional, intent(in)     :: dim
        integer :: d
        call mlxf_enter('mlx_split')
        d = a%ndim()
        if( present(dim) ) d = dim
        call mlxf_split_op(parts, mlxc_split, a, [num, axis_of(a%ndim(), d, 'mlx_split')], 'mlx_split')
    end subroutine split_equal

    ! a cut along dim, the last dimension when absent, before each 1-based position of indices: indices [4, 7]
    ! give the parts 1:3, 4:6 and 7:
    subroutine split_at( a, indices, parts, dim )
        type(mlx_array), intent(in)               :: a
        integer,         intent(in)               :: indices(:)
        type(mlx_array), allocatable, intent(out) :: parts(:)
        integer,         optional, intent(in)     :: dim
        integer, allocatable :: option(:)
        integer              :: d
        call mlxf_enter('mlx_split')
        if( any(indices < 1) ) call mlxf_fail('mlx_split', 'cut positions start at 1')
        d = a%ndim()
        if( present(dim) ) d = dim
        allocate(option(size(indices)+1))
        option(1) = axis_of(a%ndim(), d, 'mlx_split')
        option(2:) = indices-1
        call mlxf_split_sections_op(parts, mlxc_split_sections, a, option, 'mlx_split')
    end subroutine split_at

    ! a without its dimensions of extent 1: all of them, or dimension dim
    function squeeze_array( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_squeeze')
        if( present(dim) )then
            call mlxf_int_op(r, mlxc_squeeze_axis, a, axis_of(a%ndim(), dim, 'mlx_squeeze'), 'mlx_squeeze')
        else
            call mlxf_unary(r, mlxc_squeeze, a, 'mlx_squeeze')
        endif
    end function squeeze_array

    ! a without the dimensions dims, each of extent 1
    function squeeze_dims( a, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_squeeze')
        call mlxf_vector_op(r, mlxc_squeeze_axes, a, axes_of(a%ndim(), dims, 'mlx_squeeze'), 'mlx_squeeze')
    end function squeeze_dims

    ! a with a new dimension of extent 1 at position dim of the result
    function expand_dims_one( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_expand_dims')
        call mlxf_int_op(r, mlxc_expand_dims, a, axis_of(a%ndim()+1, dim, 'mlx_expand_dims'), 'mlx_expand_dims')
    end function expand_dims_one

    ! a with new dimensions of extent 1 at the positions dims of the result
    function expand_dims_list( a, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_expand_dims')
        call mlxf_vector_op(r, mlxc_expand_dims_axes, a, axes_of(a%ndim()+size(dims), dims, 'mlx_expand_dims'), 'mlx_expand_dims')
    end function expand_dims_list

    ! dimensions start_dim to end_dim (1 and the rank by default) merged into one, in array element order
    function mlx_flatten( a, start_dim, end_dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: start_dim, end_dim
        type(mlx_array) :: r
        integer         :: nd, first, last
        call mlxf_enter('mlx_flatten')
        nd = a%ndim()
        if( nd == 0 )then
            call mlxf_int2_op(r, mlxc_flatten, a, [0, -1], 'mlx_flatten')
            return
        endif
        first = 1
        last = nd
        if( present(start_dim) ) first = start_dim
        if( present(end_dim) ) last = end_dim
        call mlxf_int2_op(r, mlxc_flatten, a, [axis_of(nd, last, 'mlx_flatten'), axis_of(nd, first, 'mlx_flatten')], 'mlx_flatten')
    end function mlx_flatten

    ! dimension dim split into the dimensions of Fortran shape shape, in array element order
    function mlx_unflatten( a, dim, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim, shape(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_unflatten')
        call mlxf_unflatten_op(r, mlxc_unflatten, a, [axis_of(a%ndim(), dim, 'mlx_unflatten'), shape(size(shape):1:-1)], 'mlx_unflatten')
    end function mlx_unflatten

    ! a broadcast to Fortran shape shape, its leading dimensions aligned
    function mlx_broadcast_to( a, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shape(:)
        type(mlx_array) :: r
        call mlxf_vector_op(r, mlxc_broadcast_to, a, shape(size(shape):1:-1), 'mlx_broadcast_to')
    end function mlx_broadcast_to

    ! the arrays broadcast against each other to one shape, their leading dimensions aligned
    subroutine mlx_broadcast_arrays( arrays, results )
        type(mlx_array), intent(in)               :: arrays(:)
        type(mlx_array), allocatable, intent(out) :: results(:)
        call mlxf_vector_list_op(results, mlxc_broadcast_arrays, arrays, 'mlx_broadcast_arrays')
    end subroutine mlx_broadcast_arrays

    ! a repeated reps(d) times along dimension d
    function mlx_tile( a, reps ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: reps(:)
        type(mlx_array) :: r
        call mlxf_vector_op(r, mlxc_tile, a, reps(size(reps):1:-1), 'mlx_tile')
    end function mlx_tile

    ! every element repeated repeats times along dim; without dim, of the elements in array element order (a
    ! rank-1 result)
    function mlx_repeat( a, repeats, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: repeats
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_repeat')
        if( present(dim) )then
            call mlxf_int2_op(r, mlxc_repeat_axis, a, [repeats, axis_of(a%ndim(), dim, 'mlx_repeat')], 'mlx_repeat')
        else
            call mlxf_int_op(r, mlxc_repeat, a, repeats, 'mlx_repeat')
        endif
    end function mlx_repeat

    ! a padded by width elements on both sides of every dimension, with value (zero by default) or, in mode
    ! 'edge', with the border elements
    function pad_width( a, width, value, mode ) result(r)
        type(mlx_array),  intent(in)           :: a
        integer,          intent(in)           :: width
        type(mlx_array),  optional, intent(in) :: value
        character(len=*), optional, intent(in) :: mode
        type(mlx_array)     :: r
        type(mlx_array)     :: fill
        type(mlxf_pad_spec) :: spec
        call mlxf_enter('mlx_pad')
        spec%width = width
        if( present(mode) ) spec%mode = mode
        if( present(value) )then
            call mlxf_pad_width_op(r, mlxc_pad_symmetric, [a, value], spec, 'mlx_pad')
        else
            fill = mlx_from(0._real32)
            call mlxf_pad_width_op(r, mlxc_pad_symmetric, [a, fill], spec, 'mlx_pad')
        endif
    end function pad_width

    ! a padded by low(d) elements before and high(d) elements after dimension d
    function pad_low_high( a, low, high, value, mode ) result(r)
        type(mlx_array),  intent(in)           :: a
        integer,          intent(in)           :: low(:), high(:)
        type(mlx_array),  optional, intent(in) :: value
        character(len=*), optional, intent(in) :: mode
        type(mlx_array)     :: r
        type(mlx_array)     :: fill
        type(mlxf_pad_spec) :: spec
        call mlxf_enter('mlx_pad')
        spec%low = low
        spec%high = high
        if( present(mode) ) spec%mode = mode
        if( present(value) )then
            call mlxf_pad_op(r, mlxc_pad, [a, value], spec, 'mlx_pad')
        else
            fill = mlx_from(0._real32)
            call mlxf_pad_op(r, mlxc_pad, [a, fill], spec, 'mlx_pad')
        endif
    end function pad_low_high

    ! a reversed along dim, or along every dimension without it
    function flip_array( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_flip')
        if( present(dim) )then
            call mlxf_int_op(r, mlxc_flip_axis, a, axis_of(a%ndim(), dim, 'mlx_flip'), 'mlx_flip')
        else
            call mlxf_unary(r, mlxc_flip, a, 'mlx_flip')
        endif
    end function flip_array

    ! a reversed along the dimensions dims
    function flip_dims( a, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_flip')
        call mlxf_vector_op(r, mlxc_flip_axes, a, axes_of(a%ndim(), dims, 'mlx_flip'), 'mlx_flip')
    end function flip_dims

    ! Fortran's cshift(a, shift, dim): element i of the result is element i + shift of a along dim (1 by
    ! default), circularly; MLX's roll by -shift
    function cshift_array( a, shift, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: shift
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        integer         :: d
        call mlxf_enter('cshift')
        if( .not. present(dim) )then
            if( a%ndim() == 1 )then
                call mlxf_vector_op(r, mlxc_roll, a, [-shift], 'cshift')
                return
            endif
        endif
        d = 1
        if( present(dim) ) d = dim
        call mlxf_roll_op(r, mlxc_roll_axis, a, [axis_of(a%ndim(), d, 'cshift'), -shift], 'cshift')
    end function cshift_array

    ! a circular shift by shift(i) along dimension dims(i), one after the other
    function cshift_dims( a, shift, dims ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shift(:), dims(:)
        type(mlx_array)      :: r
        integer, allocatable :: option(:,:)
        call mlxf_enter('cshift')
        if( size(shift) /= size(dims) ) call mlxf_fail('cshift', 'one shift per dimension')
        allocate(option(size(dims), 2))
        option(:, 1) = -shift
        option(:, 2) = axes_of(a%ndim(), dims, 'cshift')
        call mlxf_vector2_op(r, mlxc_roll_axes, a, option, 'cshift')
    end function cshift_dims

    ! dimension source moved to position destination, the others keeping their order
    function mlx_movedim( a, source, destination ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: source, destination
        type(mlx_array) :: r
        integer         :: nd
        call mlxf_enter('mlx_movedim')
        nd = a%ndim()
        call mlxf_int2_op(r, mlxc_moveaxis, a, [axis_of(nd, source, 'mlx_movedim'), axis_of(nd, destination, 'mlx_movedim')], 'mlx_movedim')
    end function mlx_movedim

    ! dimensions dim1 and dim2 exchanged
    function mlx_swapdims( a, dim1, dim2 ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim1, dim2
        type(mlx_array) :: r
        integer         :: nd
        call mlxf_enter('mlx_swapdims')
        nd = a%ndim()
        call mlxf_int2_op(r, mlxc_swapaxes, a, [axis_of(nd, dim1, 'mlx_swapdims'), axis_of(nd, dim2, 'mlx_swapdims')], 'mlx_swapdims')
    end function mlx_swapdims

    ! a with rank at least one: a scalar becomes shape (1)
    function mlx_atleast_1d( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_atleast_1d, a, 'mlx_atleast_1d')
    end function mlx_atleast_1d

    ! a with rank at least two: shape (n) becomes (n, 1)
    function mlx_atleast_2d( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_atleast_2d, a, 'mlx_atleast_2d')
    end function mlx_atleast_2d

    ! a with rank at least three, by MLX's rule read in Fortran order: (n) becomes (1, n, 1) and (m, n)
    ! becomes (1, m, n)
    function mlx_atleast_3d( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_atleast_3d, a, 'mlx_atleast_3d')
    end function mlx_atleast_3d

    ! of a vector, the matrix with it on diagonal k; of a matrix, its diagonal k. k > 0 is above the main
    ! diagonal of the Fortran matrix, elements (i, i + k), which is MLX's diagonal -k
    function mlx_diag( a, k ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: k
        type(mlx_array) :: r
        integer         :: offset
        call mlxf_enter('mlx_diag')
        offset = 0
        if( present(k) ) offset = k
        call mlxf_int_op(r, mlxc_diag, a, -offset, 'mlx_diag')
    end function mlx_diag

    ! the elements (i along dim1, i + offset along dim2) of a, dimensions 1 and 2 by default; the diagonal is
    ! dimension 1 of the result and the other dimensions follow in order
    function mlx_diagonal( a, offset, dim1, dim2 ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: offset, dim1, dim2
        type(mlx_array) :: r
        integer         :: option(3)
        call mlxf_enter('mlx_diagonal')
        option = diagonal_option(a, offset, dim1, dim2, 'mlx_diagonal')
        call mlxf_int3_op(r, mlxc_diagonal, a, option, 'mlx_diagonal')
    end function mlx_diagonal

    ! the sum of mlx_diagonal(a, offset, dim1, dim2), in a's dtype unless dtype is given
    function mlx_trace( a, offset, dim1, dim2, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: offset, dim1, dim2, dtype
        type(mlx_array) :: r
        integer         :: option(4)
        call mlxf_enter('mlx_trace')
        if( a%ndim() == 2 .and. .not. (present(offset) .or. present(dim1) .or. present(dim2) .or. present(dtype)) )then
            call mlxf_unary(r, mlxc_trace, a, 'mlx_trace')
            return
        endif
        option(1:3) = diagonal_option(a, offset, dim1, dim2, 'mlx_trace')
        option(4) = a%kind()
        if( present(dtype) ) option(4) = dtype
        call mlxf_trace_op(r, mlxc_trace_axes, a, option, 'mlx_trace')
    end function mlx_trace

    ! the lower triangle of the Fortran matrix in dimensions 1 and 2: elements (i, j) with j <= i + k, the
    ! others zero. MLX sees the transpose, so this is its upper triangle with diagonal -k
    function mlx_tril( a, k ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: k
        type(mlx_array) :: r
        integer         :: offset
        call mlxf_enter('mlx_tril')
        offset = 0
        if( present(k) ) offset = k
        call mlxf_int_op(r, mlxc_triu, a, -offset, 'mlx_tril')
    end function mlx_tril

    ! the upper triangle of the Fortran matrix in dimensions 1 and 2: elements (i, j) with j >= i + k
    function mlx_triu( a, k ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: k
        type(mlx_array) :: r
        integer         :: offset
        call mlxf_enter('mlx_triu')
        offset = 0
        if( present(k) ) offset = k
        call mlxf_int_op(r, mlxc_tril, a, -offset, 'mlx_triu')
    end function mlx_triu

    ! the n-th discrete difference along dim (1 and dimension 1 by default): a(i + 1) - a(i), applied n times
    function mlx_diff( a, n, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: n, dim
        type(mlx_array) :: r
        integer         :: order, d
        call mlxf_enter('mlx_diff')
        order = 1
        d = 1
        if( present(n) ) order = n
        if( present(dim) ) d = dim
        call mlxf_int2_op(r, mlxc_diff, a, [order, axis_of(a%ndim(), d, 'mlx_diff')], 'mlx_diff')
    end function mlx_diff

    ! a view of a's elements in array element order: element (i1, ..., ir) of the result is element
    ! 1 + offset + sum((i_d - 1)*strides(d)) of a, the strides in elements; nothing checks that it lies inside a.
    ! MLX strides over the buffer, so a strided a (a transpose, a flip) is made contiguous first
    function mlx_as_strided( a, shape, strides, offset ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: shape(:), strides(:)
        integer,         optional, intent(in) :: offset
        type(mlx_array)         :: r
        type(mlx_array)         :: dense
        type(mlxf_strided_spec) :: spec
        call mlxf_enter('mlx_as_strided')
        spec%shape = shape
        spec%strides = int(strides, c_int64_t)
        if( present(offset) ) spec%offset = int(offset, c_int64_t)
        call mlxf_reduce_all_op(dense, mlxc_contiguous, a, mlxf_reduce_spec(), 'mlx_as_strided')
        call mlxf_strided_op(r, mlxc_as_strided, dense, spec, 'mlx_as_strided')
    end function mlx_as_strided

    ! the product of the extents of the dimensions dims (all by default) as a rank-0 array, its reciprocal when
    ! inverted; float32 unless dtype is given
    function mlx_number_of_elements( a, dims, inverted, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:), dtype
        logical,         optional, intent(in) :: inverted
        type(mlx_array)       :: r
        type(mlxf_count_spec) :: spec
        integer               :: i
        call mlxf_enter('mlx_number_of_elements')
        if( present(dims) )then
            spec%dims = dims
        else
            spec%dims = [(i, i=1, a%ndim())]
        endif
        if( present(inverted) ) spec%inverted = inverted
        if( present(dtype) ) spec%dtype = dtype
        call mlxf_count_op(r, mlxc_number_of_elements, a, spec, 'mlx_number_of_elements')
    end function mlx_number_of_elements

    ! the MLX axis of Fortran dimension dim of a rank-rank array, checked
    function axis_of( rank, dim, proc ) result(axis)
        integer,          intent(in) :: rank, dim
        character(len=*), intent(in) :: proc
        integer :: axis
        if( dim < 1 .or. dim > rank ) call mlxf_fail(proc, 'dimension outside array rank')
        axis = rank-dim
    end function axis_of

    ! the MLX axes of the Fortran dimensions dims of a rank-rank array, each checked
    function axes_of( rank, dims, proc ) result(axes)
        integer,          intent(in) :: rank, dims(:)
        character(len=*), intent(in) :: proc
        integer, allocatable :: axes(:)
        integer              :: i
        allocate(axes(size(dims)))
        do i = 1, size(dims)
            axes(i) = axis_of(rank, dims(i), proc)
        end do
    end function axes_of

    ! offset and the MLX axes of dim1 and dim2 (dimensions 1 and 2 by default), as MLX's diagonal takes them
    function diagonal_option( a, offset, dim1, dim2, proc ) result(option)
        type(mlx_array),  intent(in)           :: a
        integer,          optional, intent(in) :: offset, dim1, dim2
        character(len=*), intent(in)           :: proc
        integer :: option(3)
        integer :: nd, d1, d2
        nd = a%ndim()
        option(1) = 0
        d1 = 1
        d2 = 2
        if( present(offset) ) option(1) = offset
        if( present(dim1) ) d1 = dim1
        if( present(dim2) ) d2 = dim2
        option(2) = axis_of(nd, d1, proc)
        option(3) = axis_of(nd, d2, proc)
    end function diagonal_option

    ! the section lower:upper:stride of a, inclusive and 1-based per dimension, stride 1 by default
    function slice_static( a, lower, upper, stride ) result(r)
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
    end function slice_static

    ! the section of a whose first element is at the 1-based positions start (a rank-1 integer array of the
    ! graph, one per listed dimension) and whose extents are slice_sizes, one per dimension of a; a section
    ! that leaves a is not checked and reads outside it
    function slice_dynamic( a, start, dims, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, start
        integer,         intent(in) :: dims(:), slice_sizes(:)
        type(mlx_array)       :: r
        type(mlx_array)       :: shifted
        type(mlxf_index_spec) :: spec
        call mlxf_enter('mlx_slice')
        call mlxf_zero_based(shifted, start, 'mlx_slice')
        spec%axes = axes_of(a%ndim(), dims, 'mlx_slice')
        spec%sizes = slice_sizes(size(slice_sizes):1:-1)
        call mlxf_slice_dynamic_op(r, mlxc_slice_dynamic, [a, shifted], spec, 'mlx_slice')
    end function slice_dynamic

    ! the elements of a at 1-based integer indices along dim; MLX checks no bounds, so an index of 0
    ! wraps to the last element
    function mlx_take_along_dim( a, indices, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        type(mlx_array) :: shifted
        call mlxf_enter('mlx_take_along_dim')
        call mlxf_zero_based(shifted, indices, 'mlx_take_along_dim')
        call mlxf_take_op(r, mlxc_take_along_axis, [a, shifted], dim, 'mlx_take_along_dim')
    end function mlx_take_along_dim

    ! the slices of a at 1-based integer indices along dim, the indices' Fortran shape taking the place of
    ! dimension dim: r(.., i1, .., ik, ..) = a(.., indices(i1, .., ik), ..). Without dim, the elements at 1-based
    ! positions in array element order, in the indices' shape. MLX checks no bounds: an index of 0 wraps to the end
    function mlx_take( a, indices, dim ) result(r)
        type(mlx_array), intent(in)           :: a, indices
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        type(mlx_array) :: shifted
        call mlxf_enter('mlx_take')
        call mlxf_zero_based(shifted, indices, 'mlx_take')
        if( present(dim) )then
            call mlxf_take_op(r, mlxc_take_axis, [a, shifted], dim, 'mlx_take')
        else
            call mlxf_binary(r, mlxc_take, a, shifted, 'mlx_take')
        endif
    end function mlx_take

    ! a zero array of Fortran shape shape, float32 unless dtype is given
    function mlx_zeros( shape, dtype ) result(r)
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
    function mlx_arange( start, stop, step, dtype ) result(r)
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

end module mlxf_ops_shape
