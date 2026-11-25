!@descr: gathers, scatters, section updates, searches and unique values through the array signature helpers
! Index values and positions are 1-based for the user and shifted here, inside the graph, to MLX's 0-based ones;
! MLX checks no index against the extents. A gathered or scattered slab keeps a's dimensions in order and the
! dimensions of the index arrays follow it, which is MLX's layout read in Fortran order.
submodule(mlxf_ops) mlxf_ops_index
use mlxf_c_ops,  only: mlxc_gather, mlxc_gather_single, mlxc_masked_scatter, mlxc_put_along_axis, mlxc_scatter, &
                       mlxc_scatter_add, mlxc_scatter_add_axis, mlxc_scatter_add_single, mlxc_scatter_max, &
                       mlxc_scatter_max_single, mlxc_scatter_min, mlxc_scatter_min_single, mlxc_scatter_prod, &
                       mlxc_scatter_prod_single, mlxc_scatter_single, mlxc_searchsorted, mlxc_slice_dynamic, &
                       mlxc_slice_update, mlxc_slice_update_add, mlxc_slice_update_dynamic, mlxc_slice_update_max, &
                       mlxc_slice_update_min, mlxc_slice_update_prod, mlxc_subtract, mlxc_unique
use mlxf_defs,   only: MLX_DTYPES, mlxf_index_spec, mlxf_slice_spec
use mlxf_array,  only: mlx_from, mlxf_binary, mlxf_gather_op, mlxf_gather_single_op, mlxf_put_op, mlxf_scatter_op, &
                       mlxf_slice_dynamic_op, mlxf_slice_update_op, mlxf_ternary_op, mlxf_ternary_vector_op, &
                       mlxf_text_op, mlxf_unique_op
use mlxf_device, only: mlxf_enter
use mlxf_error,  only: mlxf_fail
implicit none

contains

    ! the slabs of a at the 1-based positions of one index array per listed dimension: a slab has extent
    ! slice_sizes(d) along dimension d of a and starts at the given positions along dims; the result has the
    ! slab's shape, then the index arrays' (broadcast) shape
    module function gather_list( a, indices, dims, slice_sizes ) result(r)
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
            call zero_based(ops(i+1), indices(i), 'mlx_gather')
        end do
        spec%axes = axes_of(a%ndim(), dims, 'mlx_gather')
        spec%sizes = slice_sizes(size(slice_sizes):1:-1)
        call mlxf_gather_op(r, mlxc_gather, ops, spec, 'mlx_gather')
    end function gather_list

    ! mlx_gather along one dimension
    module function gather_one( a, indices, dim, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, indices
        integer,         intent(in) :: dim, slice_sizes(:)
        type(mlx_array)       :: r
        type(mlx_array)       :: shifted
        type(mlxf_index_spec) :: spec
        call mlxf_enter('mlx_gather')
        call zero_based(shifted, indices, 'mlx_gather')
        spec%axes = [axis_of(a%ndim(), dim, 'mlx_gather')]
        spec%sizes = slice_sizes(size(slice_sizes):1:-1)
        call mlxf_gather_single_op(r, mlxc_gather_single, [a, shifted], spec, 'mlx_gather')
    end function gather_one

    ! a with the slabs of updates written at the 1-based positions of one index array per listed dimension;
    ! updates has a's shape with extent 1 along dims, then the index arrays' shape. Where positions repeat,
    ! which update stays is not defined
    module function scatter_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter')
        call scatter_many(r, mlxc_scatter, [a, updates, indices], dims, 'mlx_scatter')
    end function scatter_list

    module function scatter_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter')
        call scatter_single(r, mlxc_scatter_single, [a, indices, updates], dim, 'mlx_scatter')
    end function scatter_one

    ! as mlx_scatter, the updates added to a: repeated positions accumulate
    module function scatter_add_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_add')
        call scatter_many(r, mlxc_scatter_add, [a, updates, indices], dims, 'mlx_scatter_add')
    end function scatter_add_list

    ! one index array along dim: updates of rank(indices) + rank(a) are always slabs, as mlx_scatter's; otherwise
    ! indices and updates have a's rank and each update is added at its own position along dim, as
    ! mlx_put_along_dim writes it (the inverse of mlx_take_along_dim)
    module function scatter_add_one( a, indices, updates, dim ) result(r)
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
    module function scatter_max_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_max')
        call scatter_many(r, mlxc_scatter_max, [a, updates, indices], dims, 'mlx_scatter_max')
    end function scatter_max_list

    module function scatter_max_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_max')
        call scatter_single(r, mlxc_scatter_max_single, [a, indices, updates], dim, 'mlx_scatter_max')
    end function scatter_max_one

    ! as mlx_scatter, keeping the smaller of a and every update at a position
    module function scatter_min_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_min')
        call scatter_many(r, mlxc_scatter_min, [a, updates, indices], dims, 'mlx_scatter_min')
    end function scatter_min_list

    module function scatter_min_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_min')
        call scatter_single(r, mlxc_scatter_min_single, [a, indices, updates], dim, 'mlx_scatter_min')
    end function scatter_min_one

    ! as mlx_scatter, a multiplied by every update at a position
    module function scatter_prod_list( a, indices, updates, dims ) result(r)
        type(mlx_array), intent(in) :: a, indices(:), updates
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_prod')
        call scatter_many(r, mlxc_scatter_prod, [a, updates, indices], dims, 'mlx_scatter_prod')
    end function scatter_prod_list

    module function scatter_prod_one( a, indices, updates, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, updates
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_scatter_prod')
        call scatter_single(r, mlxc_scatter_prod_single, [a, indices, updates], dim, 'mlx_scatter_prod')
    end function scatter_prod_one

    ! a with values written at 1-based indices along dim, element by element: the inverse of mlx_take_along_dim;
    ! indices and values have a's rank and broadcast against it outside dim
    module function mlx_put_along_dim( a, indices, values, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices, values
        integer,         intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_put_along_dim')
        call scatter_single(r, mlxc_put_along_axis, [a, indices, values], dim, 'mlx_put_along_dim')
    end function mlx_put_along_dim

    ! a with the elements where mask holds replaced by the elements of src, taken in array element order; a mask
    ! of lower rank has the shape of a's last dimensions
    module function mlx_masked_scatter( a, mask, src ) result(r)
        type(mlx_array), intent(in) :: a, mask, src
        type(mlx_array) :: r
        call mlxf_ternary_op(r, mlxc_masked_scatter, [a, mask, src], 'mlx_masked_scatter')
    end function mlx_masked_scatter

    ! where each value would be inserted into the ascending rank-1 array sorted to keep it sorted: 1-based int32
    ! positions from 1 to size + 1; side 'left' (the default) is before equal elements, 'right' after them
    module function mlx_searchsorted( sorted, values, side ) result(r)
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
        call index_result(r, idx, 'mlx_searchsorted')
    end function mlx_searchsorted

    ! the distinct values of a, ascending, in size slots (unused ones hold fill, the smallest value by default),
    ! then the 1-based position in array element order of each first occurrence, the 1-based slot of every
    ! element (a's shape) and the count of each value (zero in an unused slot)
    module subroutine mlx_unique( a, size, results, fill )
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
        call index_result(results(2), raw(2), 'mlx_unique')
        call index_result(results(3), raw(3), 'mlx_unique')
        results(4) = raw(4)
    end subroutine mlx_unique

    ! the section of a whose first element is at the 1-based positions start (a rank-1 integer array of the
    ! graph, one per listed dimension) and whose extents are slice_sizes, one per dimension of a; a section
    ! that leaves a is not checked and reads outside it
    module function slice_dynamic( a, start, dims, slice_sizes ) result(r)
        type(mlx_array), intent(in) :: a, start
        integer,         intent(in) :: dims(:), slice_sizes(:)
        type(mlx_array)       :: r
        type(mlx_array)       :: shifted
        type(mlxf_index_spec) :: spec
        call mlxf_enter('mlx_slice')
        call zero_based(shifted, start, 'mlx_slice')
        spec%axes = axes_of(a%ndim(), dims, 'mlx_slice')
        spec%sizes = slice_sizes(size(slice_sizes):1:-1)
        call mlxf_slice_dynamic_op(r, mlxc_slice_dynamic, [a, shifted], spec, 'mlx_slice')
    end function slice_dynamic

    ! a with its section lower:upper:stride (as mlx_slice takes them) replaced by update, broadcast to the section
    module function slice_update_static( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update')
        call mlxf_slice_update_op(r, mlxc_slice_update, [a, update], section(lower, upper, stride), 'mlx_slice_update')
    end function slice_update_static

    ! a with update written from the 1-based positions start (a rank-1 integer array of the graph, one per listed
    ! dimension); update's extents are the section's
    module function slice_update_dynamic( a, update, start, dims ) result(r)
        type(mlx_array), intent(in) :: a, update, start
        integer,         intent(in) :: dims(:)
        type(mlx_array) :: r
        type(mlx_array) :: shifted
        call mlxf_enter('mlx_slice_update')
        call zero_based(shifted, start, 'mlx_slice_update')
        call mlxf_ternary_vector_op(r, mlxc_slice_update_dynamic, [a, update, shifted], axes_of(a%ndim(), dims, 'mlx_slice_update'), 'mlx_slice_update')
    end function slice_update_dynamic

    ! a with update added to its section lower:upper:stride
    module function mlx_slice_update_add( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_add')
        call mlxf_slice_update_op(r, mlxc_slice_update_add, [a, update], section(lower, upper, stride), 'mlx_slice_update_add')
    end function mlx_slice_update_add

    ! a with its section lower:upper:stride replaced by the larger of it and update
    module function mlx_slice_update_max( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_max')
        call mlxf_slice_update_op(r, mlxc_slice_update_max, [a, update], section(lower, upper, stride), 'mlx_slice_update_max')
    end function mlx_slice_update_max

    ! a with its section lower:upper:stride replaced by the smaller of it and update
    module function mlx_slice_update_min( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_min')
        call mlxf_slice_update_op(r, mlxc_slice_update_min, [a, update], section(lower, upper, stride), 'mlx_slice_update_min')
    end function mlx_slice_update_min

    ! a with its section lower:upper:stride multiplied by update
    module function mlx_slice_update_prod( a, update, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a, update
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_slice_update_prod')
        call mlxf_slice_update_op(r, mlxc_slice_update_prod, [a, update], section(lower, upper, stride), 'mlx_slice_update_prod')
    end function mlx_slice_update_prod

    ! 1-based integer positions as MLX's: one subtracted in the graph; a non-integer array stops. uint64 goes
    ! through int64 first, since MLX promotes uint64 with a signed integer to a float
    module subroutine zero_based( r, indices, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: indices
        character(len=*), intent(in)    :: proc
        type(mlx_array) :: one, signed
        integer         :: dtype
        dtype = indices%kind()
        if( all(dtype /= [MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, MLX_DTYPES%uint8, &
            &MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64]) ) call mlxf_fail(proc, 'indices must be integers')
        one = mlx_from(1_int32)
        if( dtype == MLX_DTYPES%uint64 )then
            signed = mlx_astype(indices, MLX_DTYPES%int64)
            call mlxf_binary(r, mlxc_subtract, signed, one, proc)
        else
            call mlxf_binary(r, mlxc_subtract, indices, one, proc)
        endif
    end subroutine zero_based

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
            call zero_based(shifted(i), ops(i), proc)
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
        call zero_based(shifted, ops(2), proc)
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

end submodule mlxf_ops_index
