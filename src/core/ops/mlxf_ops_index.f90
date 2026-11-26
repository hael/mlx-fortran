!@descr: gathers, scatters, section updates, searches and unique values through the array signature helpers
! Index values and positions are 1-based for the user and shifted here, inside the graph, to MLX's 0-based ones;
! MLX checks no index against the extents. A gathered or scattered slab keeps a's dimensions in order and the
! dimensions of the index arrays follow it, which is MLX's layout read in Fortran order.
module mlxf_ops_index
use, intrinsic :: iso_c_binding, only: c_null_char, c_null_ptr, c_bool, c_int, c_size_t
use mlxf_c_array,      only: mlxc_array_new, mlxc_array_free
use mlxf_c_ops,        only: mlxc_gather, mlxc_gather_single, mlxc_masked_scatter, mlxc_put_along_axis, mlxc_scatter, &
                             mlxc_scatter_add, mlxc_scatter_add_axis, mlxc_scatter_add_single, mlxc_scatter_max, &
                             mlxc_scatter_max_single, mlxc_scatter_min, mlxc_scatter_min_single, mlxc_scatter_prod, &
                             mlxc_scatter_prod_single, mlxc_scatter_single, mlxc_searchsorted, mlxc_slice_update, &
                             mlxc_slice_update_add, mlxc_slice_update_dynamic, mlxc_slice_update_max, &
                             mlxc_slice_update_min, mlxc_slice_update_prod, mlxc_unique
use mlxf_c_signatures, only: mlxc_gather_op, mlxc_gather_single_op, mlxc_put_op, mlxc_scatter_op, mlxc_slice_update_op, &
                             mlxc_ternary_vector_op, mlxc_text_op, mlxc_unique_op
use mlxf_c_stream,     only: mlxc_stream_free
use mlxf_c_types,      only: mlxc_array, mlxc_stream, mlxc_vector_array
use mlxf_c_vector,     only: mlxc_vector_array_free, mlxc_vector_array_new
use mlxf_defs,         only: mlxf_slice_spec, mlxf_index_spec
use mlxf_error,        only: mlxf_fail, mlxf_check
use mlxf_device,       only: mlxf_enter, mlxf_require_device, mlxf_default_stream
use mlxf_array,        only: mlx_array, mlxf_vector_import, mlxf_handle, mlxf_adopt, mlxf_vector_of
use mlxf_ops_shape,    only: axis_of, axes_of
use mlxf_calls,        only: mlxf_slice_bounds, mlxf_one_based, mlxf_ternary_op, mlxf_zero_based
implicit none

public :: mlx_gather, mlx_scatter, mlx_scatter_add, mlx_scatter_max, mlx_scatter_min, mlx_scatter_prod, &
    &mlx_put_along_dim, mlx_masked_scatter, mlx_searchsorted, mlx_unique, mlx_slice_update, mlx_slice_update_add, &
    &mlx_slice_update_max, mlx_slice_update_min, mlx_slice_update_prod
private

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

contains

    ! the slabs of a at the 1-based positions of one index array per listed dimension: a slab has extent
    ! slice_sizes(d) along dimension d of a and starts at the given positions along dims; the result has the
    ! slab's shape, then the index arrays' (broadcast) shape
    function gather_list( a, indices, dims, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, indices(:)
        integer,         intent(in) :: dims(:), slice_sizes(:)
        type(mlx_array)              :: r
        type(mlx_array), allocatable :: ops(:)
        type(mlxf_index_spec)        :: spec
        integer                      :: i
        call mlxf_enter('mlx_gather')
        if( size(indices) /= size(dims) ) call mlxf_fail('mlx_gather', 'one index array per dimension')
        allocate(ops(size(indices)+1))
        ops(1) = a
        do i = 1, size(indices)
            call mlxf_zero_based(ops(i+1), indices(i), 'mlx_gather')
        end do
        spec%axes = axes_of(a%ndim(), dims, 'mlx_gather')
        spec%sizes = slice_sizes(size(slice_sizes):1:-1)
        call mlxf_gather_op(r, mlxc_gather, ops, spec, 'mlx_gather')
    end function gather_list

    ! mlx_gather along one dimension
    function gather_one( a, indices, dim, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, indices
        integer,         intent(in) :: dim, slice_sizes(:)
        type(mlx_array)       :: r
        type(mlx_array)       :: shifted
        type(mlxf_index_spec) :: spec
        call mlxf_enter('mlx_gather')
        call mlxf_zero_based(shifted, indices, 'mlx_gather')
        spec%axes = [axis_of(a%ndim(), dim, 'mlx_gather')]
        spec%sizes = slice_sizes(size(slice_sizes):1:-1)
        call mlxf_gather_single_op(r, mlxc_gather_single, [a, shifted], spec, 'mlx_gather')
    end function gather_one

    ! a with the slabs of updates written at the 1-based positions of one index array per listed dimension;
    ! updates has a's shape with extent 1 along dims, then the index arrays' shape. Where positions repeat,
    ! which update stays is not defined
    function scatter_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter')
        call scatter_many(r, mlxc_scatter, [a, updates, indices], dims, 'mlx_scatter')
    end function scatter_list

    function scatter_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter')
        call scatter_single(r, mlxc_scatter_single, [a, indices, updates], dim, 'mlx_scatter')
    end function scatter_one

    ! as mlx_scatter, the updates added to a: repeated positions accumulate
    function scatter_add_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_add')
        call scatter_many(r, mlxc_scatter_add, [a, updates, indices], dims, 'mlx_scatter_add')
    end function scatter_add_list

    ! one index array along dim: updates of rank(indices) + rank(a) are always slabs, as mlx_scatter's; otherwise
    ! indices and updates have a's rank and each update is added at its own position along dim, as
    ! mlx_put_along_dim writes it (the inverse of mlx_take_along_dim)
    function scatter_add_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_add')
        if( updates%ndim() == indices%ndim()+a%ndim() )then
            call scatter_single(r, mlxc_scatter_add_single, [a, indices, updates], dim, 'mlx_scatter_add')
        else
            call scatter_single(r, mlxc_scatter_add_axis, [a, indices, updates], dim, 'mlx_scatter_add')
        endif
    end function scatter_add_one

    ! as mlx_scatter, keeping the larger of a and every update at a position
    function scatter_max_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_max')
        call scatter_many(r, mlxc_scatter_max, [a, updates, indices], dims, 'mlx_scatter_max')
    end function scatter_max_list

    function scatter_max_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_max')
        call scatter_single(r, mlxc_scatter_max_single, [a, indices, updates], dim, 'mlx_scatter_max')
    end function scatter_max_one

    ! as mlx_scatter, keeping the smaller of a and every update at a position
    function scatter_min_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_min')
        call scatter_many(r, mlxc_scatter_min, [a, updates, indices], dims, 'mlx_scatter_min')
    end function scatter_min_list

    function scatter_min_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_min')
        call scatter_single(r, mlxc_scatter_min_single, [a, indices, updates], dim, 'mlx_scatter_min')
    end function scatter_min_one

    ! as mlx_scatter, a multiplied by every update at a position
    function scatter_prod_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_prod')
        call scatter_many(r, mlxc_scatter_prod, [a, updates, indices], dims, 'mlx_scatter_prod')
    end function scatter_prod_list

    function scatter_prod_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_prod')
        call scatter_single(r, mlxc_scatter_prod_single, [a, indices, updates], dim, 'mlx_scatter_prod')
    end function scatter_prod_one

    ! a with values written at 1-based indices along dim, element by element: the inverse of mlx_take_along_dim;
    ! indices and values have a's rank and broadcast against it outside dim
    function mlx_put_along_dim( a, indices, values, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, values
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_put_along_dim')
        call scatter_single(r, mlxc_put_along_axis, [a, indices, values], dim, 'mlx_put_along_dim')
    end function mlx_put_along_dim

    ! a with the elements where mask holds replaced by the elements of src, taken in array element order; a mask
    ! of lower rank has the shape of a's last dimensions
    function mlx_masked_scatter( a, mask, src ) result(r)
        type(mlx_array), intent(in) :: a, mask, src
        type(mlx_array) :: r
        call mlxf_ternary_op(r, mlxc_masked_scatter, [a, mask, src], 'mlx_masked_scatter')
    end function mlx_masked_scatter

    ! where each value would be inserted into the ascending rank-1 array sorted to keep it sorted: 1-based int32
    ! positions from 1 to size + 1; side 'left' (the default) is before equal elements, 'right' after them
    function mlx_searchsorted( sorted, values, side ) result(r)
        type(mlx_array),  intent(in)           :: sorted, values
        character(len=*), optional, intent(in) :: side
        type(mlx_array) :: r
        type(mlx_array) :: idx
        call mlxf_enter('mlx_searchsorted')
        if( present(side) )then
            call mlxf_text_op(idx, mlxc_searchsorted, [sorted, values], side, 'mlx_searchsorted')
        else
            call mlxf_text_op(idx, mlxc_searchsorted, [sorted, values], 'left', 'mlx_searchsorted')
        endif
        call mlxf_one_based(r, idx, 'mlx_searchsorted')
    end function mlx_searchsorted

    ! the distinct values of a, ascending, in size slots (unused ones hold fill, the smallest value by default),
    ! then the 1-based position in array element order of each first occurrence, the 1-based slot of every
    ! element (a's shape) and the count of each value (zero in an unused slot)
    subroutine mlx_unique( a, size, results, fill )
        type(mlx_array), intent(in)               :: a
        integer,         intent(in)               :: size
        type(mlx_array), allocatable, intent(out) :: results(:)
        type(mlx_array), optional, intent(in)     :: fill
        type(mlx_array), allocatable :: raw(:)
        call mlxf_enter('mlx_unique')
        if( present(fill) )then
            call mlxf_unique_op(raw, mlxc_unique, [a, fill], size, 'mlx_unique')
        else
            call mlxf_unique_op(raw, mlxc_unique, [a], size, 'mlx_unique')
        endif
        if( ubound(raw, 1) /= 4 ) call mlxf_fail('mlx_unique', 'four results expected')
        allocate(results(4))
        results(1) = raw(1)
        call mlxf_one_based(results(2), raw(2), 'mlx_unique')
        call mlxf_one_based(results(3), raw(3), 'mlx_unique')
        results(4) = raw(4)
    end subroutine mlx_unique

    ! a with its section lower:upper:stride (as mlx_slice takes them) replaced by update, broadcast to the section
    function slice_update_static( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update')
        call mlxf_slice_update_op(r, mlxc_slice_update, [a, update], section(lower, upper, stride), 'mlx_slice_update')
    end function slice_update_static

    ! a with update written from the 1-based positions start (a rank-1 integer array of the graph, one per listed
    ! dimension); update's extents are the section's
    function slice_update_dynamic( a, update, start, dims ) result(r)
        type(mlx_array), intent(in) :: a, update, start
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        type(mlx_array) :: shifted
        call mlxf_enter('mlx_slice_update')
        call mlxf_zero_based(shifted, start, 'mlx_slice_update')
        call mlxf_ternary_vector_op(r, mlxc_slice_update_dynamic, [a, update, shifted], axes_of(a%ndim(), dims, 'mlx_slice_update'), 'mlx_slice_update')
    end function slice_update_dynamic

    ! a with update added to its section lower:upper:stride
    function mlx_slice_update_add( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_add')
        call mlxf_slice_update_op(r, mlxc_slice_update_add, [a, update], section(lower, upper, stride), 'mlx_slice_update_add')
    end function mlx_slice_update_add

    ! a with its section lower:upper:stride replaced by the larger of it and update
    function mlx_slice_update_max( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_max')
        call mlxf_slice_update_op(r, mlxc_slice_update_max, [a, update], section(lower, upper, stride), 'mlx_slice_update_max')
    end function mlx_slice_update_max

    ! a with its section lower:upper:stride replaced by the smaller of it and update
    function mlx_slice_update_min( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_min')
        call mlxf_slice_update_op(r, mlxc_slice_update_min, [a, update], section(lower, upper, stride), 'mlx_slice_update_min')
    end function mlx_slice_update_min

    ! a with its section lower:upper:stride multiplied by update
    function mlx_slice_update_prod( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_prod')
        call mlxf_slice_update_op(r, mlxc_slice_update_prod, [a, update], section(lower, upper, stride), 'mlx_slice_update_prod')
    end function mlx_slice_update_prod

    ! a scatter of ops(2), the updates, into ops(1) at the 1-based index arrays ops(3:), one per dimension of dims
    subroutine scatter_many( r, f, ops, dims, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_scatter)         :: f
        type(mlx_array),  intent(in)    :: ops(:)
        integer,          intent(in)    :: dims(:)
        character(len=*), intent(in)    :: proc
        type(mlx_array), allocatable :: shifted(:)
        integer                      :: i
        if( size(ops) /= size(dims)+2 ) call mlxf_fail(proc, 'one index array per dimension')
        allocate(shifted(size(ops)))
        shifted(1) = ops(1)
        shifted(2) = ops(2)
        do i = 3, size(ops)
            call mlxf_zero_based(shifted(i), ops(i), proc)
        end do
        call mlxf_scatter_op(r, f, shifted, axes_of(ops(1)%ndim(), dims, proc), proc)
    end subroutine scatter_many

    ! a scatter of ops(3) into ops(1) at the 1-based index array ops(2) along dim
    subroutine scatter_single( r, f, ops, dim, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_scatter_single)  :: f
        type(mlx_array),  intent(in)    :: ops(3)
        integer,          intent(in)    :: dim
        character(len=*), intent(in)    :: proc
        type(mlx_array) :: shifted
        call mlxf_zero_based(shifted, ops(2), proc)
        call mlxf_put_op(r, f, [ops(1), shifted, ops(3)], axis_of(ops(1)%ndim(), dim, proc), proc)
    end subroutine scatter_single

    ! the bounds record of a section, stride 1 by default
    function section( lower, upper, stride ) result(spec)
        integer, intent(in)           :: lower(:), upper(:)
        integer, optional, intent(in) :: stride(:)
        type(mlxf_slice_spec) :: spec
        spec%lower = lower
        spec%upper = upper
        allocate(spec%stride(size(lower)))
        spec%stride = 1
        if( present(stride) ) spec%stride = stride
    end function section

    ! r = f(a(1), a(2:)) with the axes and slice sizes of option, all as MLX takes them, for every int f(mlx_array*
    ! res, const mlx_array a, const mlx_vector_array indices, const int* axes, size_t axes_num, const int* slice_sizes,
    ! size_t slice_sizes_num, const mlx_stream s)
    subroutine mlxf_gather_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_gather_op)            :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_index_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: v
        type(mlxc_array)        :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        call mlxf_require_device(proc)
        if( size(a) < 2 ) call mlxf_fail(proc, 'an array and at least one index array are needed')
        ha = mlxf_handle(a(1), proc)
        v = mlxf_vector_of(a(2:), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, v, int(option%axes, c_int), int(size(option%axes), c_size_t), int(option%sizes, c_int), int(size(option%sizes), c_size_t), s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_gather_op

    ! r = f(a(1), a(2)) with the one axis and the slice sizes of option, as MLX takes them, for every
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, int axis, const int* slice_sizes,
    ! size_t slice_sizes_num, const mlx_stream s)
    subroutine mlxf_gather_single_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_gather_single_op)     :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_index_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)  :: ha, hb
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        if( size(a) /= 2 ) call mlxf_fail(proc, 'two arrays are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        if( size(option%axes) /= 1 ) call mlxf_fail(proc, 'one axis is needed')
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, int(option%axes(1), c_int), int(option%sizes, c_int), int(size(option%sizes), c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_gather_single_op

    ! r = f(a(1), a(3:), a(2)): an array, its updates and then the index arrays, with the axes option as MLX takes
    ! them, for every int f(mlx_array* res, const mlx_array a, const mlx_vector_array indices, const mlx_array
    ! updates, const int* axes, size_t axes_num, const mlx_stream s)
    subroutine mlxf_scatter_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_scatter_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)        :: ha, hb
        type(mlxc_vector_array) :: v
        type(mlxc_array)        :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        call mlxf_require_device(proc)
        if( size(a) < 3 ) call mlxf_fail(proc, 'an array, its updates and at least one index array are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        v = mlxf_vector_of(a(3:), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, v, hb, int(option, c_int), int(size(option), c_size_t), s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_scatter_op

    ! r = f(a(1), a(2), a(3), option): an array, indices and values, with the axis as MLX takes it, for every
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, const mlx_array values, int axis,
    ! const mlx_stream s)
    subroutine mlxf_put_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_put_op)          :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha, hb, hc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        if( size(a) /= 3 ) call mlxf_fail(proc, 'three arrays are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        hc = mlxf_handle(a(3), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, hc, int(option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_put_op

    ! r = f(a(1), a(2), a(3), option): three arrays and a list as MLX takes it, for every int f(mlx_array* res,
    ! const mlx_array src, const mlx_array update, const mlx_array start, const int* axes, size_t axes_num,
    ! const mlx_stream s)
    subroutine mlxf_ternary_vector_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout)   :: r
        procedure(mlxc_ternary_vector_op) :: f
        type(mlx_array),  intent(in)      :: a(:)
        integer,          intent(in)      :: option(:)
        character(len=*), intent(in)      :: proc
        type(mlxc_array)  :: ha, hb, hc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        if( size(a) /= 3 ) call mlxf_fail(proc, 'three arrays are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        hc = mlxf_handle(a(3), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, hc, int(option, c_int), int(size(option), c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_ternary_vector_op

    ! r = f(a(1), a(2), option) for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! const char* text, const mlx_stream s)
    subroutine mlxf_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_text_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha, hb
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        if( size(a) /= 2 ) call mlxf_fail(proc, 'two arrays are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, trim(option)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_text_op

    ! a(1) with its section of option, Fortran's inclusive 1-based bounds and strides as mlxf_slice_op takes them,
    ! updated by a(2), for every int f(mlx_array* res, const mlx_array src, const mlx_array update, const int* start,
    ! size_t start_num, const int* stop, size_t stop_num, const int* strides, size_t strides_num, const mlx_stream s)
    subroutine mlxf_slice_update_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_update_op)      :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_slice_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)            :: ha, hb
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: b(:,:)
        integer(c_size_t)           :: n
        call mlxf_require_device(proc)
        if( size(a) /= 2 ) call mlxf_fail(proc, 'two arrays are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        call mlxf_slice_bounds(a(1), option, b, proc)
        n = int(size(b, 1), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, b(:, 1), n, b(:, 2), n, b(:, 3), n, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_slice_update_op

    ! the unique values of a(1) in option slots with their first positions, inverse positions and counts, in
    ! MLX's order and 0-based, padded with a(2) when it is given, for every int f(mlx_vector_array* res, const mlx_array
    ! a, int size, bool return_index, bool return_inverse, bool return_counts, const mlx_array fill_value, const mlx_stream s)
    subroutine mlxf_unique_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unique_op)                  :: f
        type(mlx_array),  intent(in)               :: a(:)
        integer,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha, hb
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        if( size(a) < 1 .or. size(a) > 2 ) call mlxf_fail(proc, 'an array and at most a fill value are needed')
        if( option < 0 ) call mlxf_fail(proc, 'negative size')
        ha = mlxf_handle(a(1), proc)
        hb%ctx = c_null_ptr
        if( size(a) == 2 ) hb = mlxf_handle(a(2), proc)
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option, c_int), .true._c_bool, .true._c_bool, .true._c_bool, hb, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_unique_op

end module mlxf_ops_index
