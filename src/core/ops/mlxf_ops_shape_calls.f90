!@descr: the signature helpers of the shape operations: one per C signature class of mlx-c's shape functions
submodule(mlxf_ops_shape) mlxf_ops_shape_calls
use, intrinsic :: iso_c_binding, only: c_null_char, c_bool, c_int, c_size_t
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_c_types,  only: mlxc_array, mlxc_stream, mlxc_vector_array
use mlxf_c_vector, only: mlxc_vector_array_free, mlxc_vector_array_new
use mlxf_error,    only: mlxf_check
use mlxf_device,   only: mlxf_require_device, mlxf_default_stream
use mlxf_array,    only: mlxf_vector_import, mlxf_handle, mlxf_adopt, mlxf_vector_of
use mlxf_calls,    only: mlxf_check_dim, mlxf_slice_bounds, mlxf_axes_of, mlxf_check_dtype
implicit none

contains

    ! r = f(a(1), a(2)) along Fortran dimension option, for every int f(mlx_array* res, const mlx_array a,
    ! const mlx_array indices, int axis, const mlx_stream s); the indices are already 0-based
    module subroutine mlxf_take_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_take_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call mlxf_check_dim(a(1), option, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlxf_handle(a(1), proc), mlxf_handle(a(2), proc), int(a(1)%ndim()-option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_take_op

    ! the slice of a from Fortran's inclusive, 1-based bounds and strides, translated by mlxf_slice_bounds, for every
    ! int f(mlx_array* res, const mlx_array a, const int* start, size_t start_num, const int* stop, size_t stop_num,
    ! const int* strides, size_t strides_num, const mlx_stream s)
    module subroutine mlxf_slice_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_slice_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)            :: ha
        integer(c_int), allocatable :: b(:,:)
        integer(c_size_t)           :: n
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call mlxf_slice_bounds(a, option, b, proc)
        n = int(size(b, 1), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, b(:, 1), n, b(:, 2), n, b(:, 3), n, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_slice_op

    ! r = f(a, option) for every int f(mlx_array* res, const mlx_vector_array arrays, int axis, const mlx_stream s);
    ! the axis goes to MLX as given, already translated, and the list as a vector freed after the call
    module subroutine mlxf_concat_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_concat_op)       :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_vector_array) :: v
        type(mlxc_array)        :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        call mlxf_require_device(proc)
        if( size(a) == 0 ) call mlxf_fail(proc, 'empty list')
        v = mlxf_vector_of(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, v, int(option, c_int), s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_concat_op

    ! r = f(start, stop, step) for every int f(mlx_array* res, double start, double stop, double step,
    ! mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_range_op( r, f, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_range_op)             :: f
        type(mlxf_range_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call mlxf_check_dtype(option%dtype, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, option%start, option%stop, option%step, int(option%dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_range_op

    ! r = f(a, option(1), option(2), option(3)) for every int f(mlx_array* res, const mlx_array a, int i,
    ! int j, int k, const mlx_stream s); the integers go to MLX as given
    module subroutine mlxf_int3_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int3_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(3)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(1), c_int), int(option(2), c_int), int(option(3), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_int3_op

    ! r = f(a, offset, axis1, axis2, dtype) from option in that order, for every int f(mlx_array* res,
    ! const mlx_array a, int offset, int axis1, int axis2, mlx_dtype dtype, const mlx_stream s); the axes go
    ! to MLX as given and the dtype is checked first
    module subroutine mlxf_trace_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_trace_op)        :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(4)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call mlxf_check_dtype(option(4), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(1), c_int), int(option(2), c_int), int(option(3), c_int), int(option(4), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_trace_op

    ! r = f(a, option(2:), option(1)): a list and then an axis, both as MLX takes them, for every
    ! int f(mlx_array* res, const mlx_array a, const int* shift, size_t shift_num, int axis, const mlx_stream s)
    module subroutine mlxf_roll_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_roll_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        if( size(option) < 2 ) call mlxf_fail(proc, 'an axis and at least one value are needed')
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(2:), c_int), int(size(option)-1, c_size_t), int(option(1), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_roll_op

    ! r = f(a, option(1), option(2:)): an axis and then a list, both as MLX takes them, for every
    ! int f(mlx_array* res, const mlx_array a, int axis, const int* shape, size_t shape_num, const mlx_stream s)
    module subroutine mlxf_unflatten_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unflatten_op)    :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        if( size(option) < 2 ) call mlxf_fail(proc, 'an axis and at least one value are needed')
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(1), c_int), int(option(2:), c_int), int(size(option)-1, c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_unflatten_op

    ! r = f(a, option(:,1), option(:,2)): two lists of one length, as MLX takes them, for every
    ! int f(mlx_array* res, const mlx_array a, const int* u, size_t u_num, const int* v, size_t v_num,
    ! const mlx_stream s)
    module subroutine mlxf_vector2_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_vector2_op)      :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:,:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_size_t) :: n
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        if( size(option, 2) /= 2 ) call mlxf_fail(proc, 'two lists are needed')
        n = int(size(option, 1), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(:, 1), c_int), n, int(option(:, 2), c_int), n, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_vector2_op

    ! the view of a's elements with the Fortran shape and the strides, in elements per dimension, of option,
    ! both reversed to MLX's order, for every int f(mlx_array* res, const mlx_array a, const int* shape,
    ! size_t shape_num, const int64_t* strides, size_t strides_num, size_t offset, const mlx_stream s)
    module subroutine mlxf_strided_op( r, f, a, option, proc )
        type(mlx_array),         intent(inout) :: r
        procedure(mlxc_strided_op)             :: f
        type(mlx_array),         intent(in)    :: a
        type(mlxf_strided_spec), intent(in)    :: option
        character(len=*),        intent(in)    :: proc
        type(mlxc_array)   :: ha
        type(mlxc_array)   :: res
        type(mlxc_stream)  :: s
        integer(c_int)     :: ierr
        integer            :: n
        integer(c_int64_t) :: lo, hi, na
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        n = size(option%shape)
        if( size(option%strides) /= n ) call mlxf_fail(proc, 'one stride per dimension of the shape')
        if( any(option%shape < 0) .or. option%offset < 0 ) call mlxf_fail(proc, 'negative extent or offset')
        ! MLX reads whatever the strides address: every element a non-empty view reaches must be one of a's
        if( all(option%shape > 0) )then
            if( .not. strided_reach(option%shape, option%strides, option%offset, lo, hi) )then
                call mlxf_fail(proc, 'the elements the view reaches lie beyond the 64-bit range')
            endif
            na = a%size()
            if( lo < 0 .or. hi >= na ) call mlxf_fail(proc, 'the view reaches elements outside a')
        endif
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option%shape(n:1:-1), c_int), int(n, c_size_t), int(option%strides(n:1:-1), c_int64_t), int(n, c_size_t), int(option%offset, c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_strided_op

    ! the lowest and highest element order, from 0, that a view of positive extents reaches through its
    ! strides from offset; false when a product or a sum would leave the 64-bit range
    logical function strided_reach( shape, strides, offset, lo, hi )
        integer,            intent(in)  :: shape(:)
        integer(c_int64_t), intent(in)  :: strides(:), offset
        integer(c_int64_t), intent(out) :: lo, hi
        integer(c_int64_t) :: span, step
        integer            :: i
        lo = offset
        hi = offset
        strided_reach = .false.
        do i = 1, size(shape)
            span = int(shape(i) - 1, c_int64_t)
            step = strides(i)
            if( step < -huge(step) ) return
            if( span > 0 )then
                if( abs(step) > huge(step) / span ) return
            endif
            step = span * step
            if( step > 0 )then
                if( hi > huge(hi) - step ) return
                hi = hi + step
            else
                if( lo < -huge(lo) - step ) return
                lo = lo + step
            endif
        end do
        strided_reach = .true.
    end function strided_reach

    ! r = f(a) over the Fortran dimensions option%dims as option%dtype, checked first, for every
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool inverted, mlx_dtype dtype,
    ! const mlx_stream s)
    module subroutine mlxf_count_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_count_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_count_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)            :: ha
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:)
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call mlxf_check_dtype(option%dtype, proc)
        axes = mlxf_axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, axes, int(size(axes), c_size_t), logical(option%inverted, c_bool), int(option%dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_count_op

    ! the arrays of f(a), in MLX's order, for every int f(mlx_vector_array* res, const mlx_vector_array
    ! inputs, const mlx_stream s)
    module subroutine mlxf_vector_list_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_vector_list_op)             :: f
        type(mlx_array),  intent(in)               :: a(:)
        character(len=*), intent(in)               :: proc
        type(mlxc_vector_array) :: v
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        if( size(a) == 0 ) call mlxf_fail(proc, 'empty list')
        v = mlxf_vector_of(a, proc)
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, v, s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_vector_list_op

    ! the arrays of f(a, option(1), option(2)), the integers as MLX takes them, for every
    ! int f(mlx_vector_array* res, const mlx_array a, int num_splits, int axis, const mlx_stream s)
    module subroutine mlxf_split_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_split_op)                   :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option(2)
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(1), c_int), int(option(2), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_split_op

    ! the arrays of f(a, option(2:), option(1)): a list and then an axis, both as MLX takes them, for every
    ! int f(mlx_vector_array* res, const mlx_array a, const int* indices, size_t indices_num, int axis,
    ! const mlx_stream s)
    module subroutine mlxf_split_sections_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_split_sections_op)          :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option(:)
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        if( size(option) < 1 ) call mlxf_fail(proc, 'an axis is needed')
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(2:), c_int), int(size(option)-1, c_size_t), int(option(1), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_split_sections_op

    ! the arrays of f(a), in MLX's order, for every int f(mlx_vector_array* res, const mlx_array a,
    ! const mlx_stream s)
    module subroutine mlxf_unstack_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_op)                 :: f
        type(mlx_array),  intent(in)               :: a
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_unstack_op

    ! the arrays of f(a, option), the axis as MLX takes it, for every int f(mlx_vector_array* res,
    ! const mlx_array a, int axis, const mlx_stream s)
    module subroutine mlxf_unstack_dim_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_dim_op)             :: f
        type(mlx_array),  intent(in)               :: a
        integer,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_unstack_dim_op

    ! a(1) padded with a(2) by option%low and option%high elements per Fortran dimension, reversed to MLX's
    ! axes, for every int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, const int* low,
    ! size_t low_num, const int* high, size_t high_num, const mlx_array pad_value, const char* mode, const mlx_stream s)
    module subroutine mlxf_pad_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_pad_op)             :: f
        type(mlx_array),     intent(in)    :: a(:)
        type(mlxf_pad_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: ha, hb
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: n, j
        integer(c_size_t) :: nc
        call mlxf_require_device(proc)
        if( size(a) /= 2 ) call mlxf_fail(proc, 'an array and a fill value are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        n = a(1)%ndim()
        if( size(option%low) /= n .or. size(option%high) /= n ) call mlxf_fail(proc, 'one low and one high width per dimension')
        if( any(option%low < 0) .or. any(option%high < 0) ) call mlxf_fail(proc, 'negative pad width')
        nc = int(n, c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, [(int(j, c_int), j=0, n-1)], nc, int(option%low(n:1:-1), c_int), nc, int(option%high(n:1:-1), c_int), nc, hb, trim(option%mode)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_pad_op

    ! a(1) padded with a(2) by option%width elements on both sides of every dimension, for every
    ! int f(mlx_array* res, const mlx_array a, int pad_width, const mlx_array pad_value, const char* mode,
    ! const mlx_stream s)
    module subroutine mlxf_pad_width_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_pad_width_op)       :: f
        type(mlx_array),     intent(in)    :: a(:)
        type(mlxf_pad_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: ha, hb
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        if( size(a) /= 2 ) call mlxf_fail(proc, 'an array and a fill value are needed')
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        if( option%width < 0 ) call mlxf_fail(proc, 'negative pad width')
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option%width, c_int), hb, trim(option%mode)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_pad_width_op

    ! r = f(a(1), a(2)) with the axes and slice sizes of option, as MLX takes them, for every int f(mlx_array* res,
    ! const mlx_array a, const mlx_array start, const int* axes, size_t axes_num, const int* slice_size,
    ! size_t slice_size_num, const mlx_stream s)
    module subroutine mlxf_slice_dynamic_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_dynamic_op)     :: f
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
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, int(option%axes, c_int), int(size(option%axes), c_size_t), int(option%sizes, c_int), int(size(option%sizes), c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_slice_dynamic_op

end submodule mlxf_ops_shape_calls
