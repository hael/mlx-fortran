!@descr: signature-class helpers for shaped, indexed, closeness, reduction and Fourier operations; power and logic operators
submodule(mlxf_array) mlxf_array_operations
use, intrinsic :: iso_c_binding, only: c_null_char, c_null_ptr
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_ops,    only: mlxc_power, mlxc_equal, mlxc_logical_xor, mlxc_positive
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_c_vector, only: mlxc_vector_array_free, mlxc_vector_array_new
use mlxf_defs,     only: MLX_DTYPES, MLX_FFT_NORMS
use mlxf_device,   only: mlxf_require_device, mlxf_default_stream
use mlxf_error,    only: mlxf_check, mlxf_fail
implicit none

contains

    ! r = f(a, dtype) for every int f(mlx_array* res, const mlx_array a, mlx_dtype dtype, const mlx_stream s):
    ! the dtype is checked against MLX_DTYPES first, then mlxf_int_op
    module subroutine mlxf_dtype_op( r, f, a, dtype, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int_op)          :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: dtype
        character(len=*), intent(in)    :: proc
        call mlxf_require_device(proc)
        call check_dtype(dtype, proc)
        call mlxf_int_op(r, f, a, dtype, proc)
    end subroutine mlxf_dtype_op

    ! r = f(a, option) on the default device, for every int f(mlx_array* res, const mlx_array a, int option,
    ! const mlx_stream s); a dtype option goes through mlxf_dtype_op
    module subroutine mlxf_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int_op)          :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_int_op

    ! r = f(a, option) for every int f(mlx_array* res, const mlx_array a, const int* shape, size_t shape_num,
    ! const mlx_stream s); option goes to MLX as given, already in its order
    module subroutine mlxf_vector_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_vector_op)       :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option, c_int), int(size(option), c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_vector_op

    ! r = f(a) along Fortran dimension option%dim (MLX axis rank - dim), which the result loses unless
    ! option%keepdims, for every int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, const mlx_stream s)
    module subroutine mlxf_reduce_op( r, f, a, option, proc )
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
        call check_dim(a, option%dim, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_reduce_op

    ! r = f(a(1), a(2), a(3)) for every int f(mlx_array* res, const mlx_array condition, const mlx_array x,
    ! const mlx_array y, const mlx_stream s)
    module subroutine mlxf_ternary_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_ternary_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlxf_handle(a(1), proc), mlxf_handle(a(2), proc), mlxf_handle(a(3), proc), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_ternary_op

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
        call check_dim(a(1), option, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlxf_handle(a(1), proc), mlxf_handle(a(2), proc), int(a(1)%ndim()-option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_take_op

    ! the scan of a along Fortran dimension option%dim, in its dtype, reversed or exclusive as option says, for every
    ! int f(mlx_array* res, const mlx_array a, int axis, bool reverse, bool inclusive, mlx_optional_dtype
    ! dtype, const mlx_stream s)
    module subroutine mlxf_scan_op( r, f, a, option, proc )
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
        call check_dim(a, option%dim, proc)
        dtype%has_value = .false._c_bool
        dtype%value = 0_c_int
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%reverse, c_bool), logical(option%inclusive, c_bool), dtype, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_scan_op

    ! the slice of a from Fortran's inclusive, 1-based bounds and strides, translated by slice_bounds, for every
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
        call slice_bounds(a, option, b, proc)
        n = int(size(b, 1), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, b(:, 1), n, b(:, 2), n, b(:, 3), n, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
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
        v = vector_of(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, v, int(option, c_int), s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_concat_op

    ! r = f(shape), the shape reversed to MLX's order, for every int f(mlx_array* res, const int* shape,
    ! size_t shape_num, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_zeros_op( r, f, shape, dtype, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_zeros_op)        :: f
        integer,          intent(in)    :: shape(:), dtype
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_dtype(dtype, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, int(shape(size(shape):1:-1), c_int), int(size(shape), c_size_t), int(dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_zeros_op

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
        call check_dtype(option%dtype, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, option%start, option%stop, option%step, int(option%dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_range_op

    ! r = f(a) of length option%n(1) along Fortran dimension option%dims(1), for every int f(mlx_array* res,
    ! const mlx_array a, int n, int axis, mlx_fft_norm norm, const mlx_stream s); the norm is checked first
    module subroutine mlxf_fft_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_fft_op)             :: f
        type(mlx_array),     intent(in)    :: a
        type(mlxf_fft_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_fft_norm(option%norm, proc)
        ha = mlxf_handle(a, proc)
        call check_dim(a, option%dims(1), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option%n(1), c_int), int(a%ndim()-option%dims(1), c_int), int(option%norm, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_fft_op

    ! r = f(a) over Fortran dimensions option%dims with lengths option%n, for every int f(mlx_array* res,
    ! const mlx_array a, const int* n, size_t n_num, const int* axes, size_t axes_num, mlx_fft_norm norm,
    ! const mlx_stream s)
    module subroutine mlxf_fft2_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_fft2_op)            :: f
        type(mlx_array),     intent(in)    :: a
        type(mlxf_fft_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_fft_norm(option%norm, proc)
        ha = mlxf_handle(a, proc)
        call check_dim(a, option%dims(1), proc)
        call check_dim(a, option%dims(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option%n, c_int), 2_c_size_t, int(a%ndim()-option%dims, c_int), 2_c_size_t, int(option%norm, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_fft2_op

    ! r = f(a(1), a(2)) with the tolerances of option, for every int f(mlx_array* res, const mlx_array a,
    ! const mlx_array b, double rtol, double atol, bool equal_nan, const mlx_stream s)
    module subroutine mlxf_close_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_close_op)             :: f
        type(mlx_array),       intent(in)    :: a(:)
        type(mlxf_close_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlxf_handle(a(1), proc), mlxf_handle(a(2), proc), option%rtol, option%atol, &
            &logical(option%equal_nan, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_close_op

    ! r = f(a(1), a(2)) with NaNs equal when option holds, for every int f(mlx_array* res, const mlx_array a,
    ! const mlx_array b, bool equal_nan, const mlx_stream s)
    module subroutine mlxf_compare_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_compare_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlxf_handle(a(1), proc), mlxf_handle(a(2), proc), logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_compare_op

    ! r = f(a) with the replacements of option, for every int f(mlx_array* res, const mlx_array a, float nan,
    ! mlx_optional_float posinf, mlx_optional_float neginf, const mlx_stream s)
    module subroutine mlxf_nan_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_nan_op)             :: f
        type(mlx_array),     intent(in)    :: a
        type(mlxf_nan_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)          :: ha
        type(mlxc_optional_float) :: posinf, neginf
        type(mlxc_array)          :: res
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        posinf%value = option%posinf
        posinf%has_value = logical(option%has_posinf, c_bool)
        neginf%value = option%neginf
        neginf%has_value = logical(option%has_neginf, c_bool)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, option%nan, posinf, neginf, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_nan_op

    ! the arrays of f(a(1), a(2)), in MLX's order, for every int f(mlx_vector_array* res, const mlx_array a,
    ! const mlx_array b, const mlx_stream s); the vector is freed after its arrays are adopted
    module subroutine mlxf_binary_vector_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_binary_vector_op)           :: f
        type(mlx_array),  intent(in)               :: a(:)
        character(len=*), intent(in)               :: proc
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlxf_handle(a(1), proc), mlxf_handle(a(2), proc), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_binary_vector_op

    ! r = f(option%shape, a) as option%dtype, the shape reversed to MLX's order, for every int f(mlx_array* res,
    ! const int* shape, size_t shape_num, const mlx_array vals, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_full_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_full_op)              :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_shape_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: n
        call mlxf_require_device(proc)
        call check_dtype(option%dtype, proc)
        ha = mlxf_handle(a, proc)
        n = size(option%shape)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, int(option%shape(n:1:-1), c_int), int(n, c_size_t), ha, int(option%dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_full_op

    ! r = f(a(1), a(2), option) for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! mlx_dtype dtype, const mlx_stream s); option, the dtype, is checked first
    module subroutine mlxf_binary_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_int_op)   :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_dtype(option, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlxf_handle(a(1), proc), mlxf_handle(a(2), proc), int(option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_binary_int_op

    ! r = f(a) over every dimension, for every int f(mlx_array* res, const mlx_array a, bool keepdims,
    ! const mlx_stream s); the flag is option%keepdims (a softmax passes its precise flag there, a contiguous
    ! copy false for row-major order)
    module subroutine mlxf_reduce_all_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_flag_op)               :: f
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
        ierr = f(res, ha, logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_reduce_all_op

    ! r = f(a) over the Fortran dimensions option%dims, each translated to its MLX axis, for every
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool keepdims, const mlx_stream s)
    module subroutine mlxf_reduce_dims_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_reduce_dims_op)        :: f
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
        axes = axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, axes, int(size(axes), c_size_t), logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_reduce_dims_op

    ! r = f(a) over every dimension with option%ddof delta degrees of freedom, for every
    ! int f(mlx_array* res, const mlx_array a, bool keepdims, int ddof, const mlx_stream s)
    module subroutine mlxf_var_all_op( r, f, a, option, proc )
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
        call adopt(r, res, proc)
    end subroutine mlxf_var_all_op

    ! r = f(a) along Fortran dimension option%dim with option%ddof delta degrees of freedom, for every
    ! int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, int ddof, const mlx_stream s)
    module subroutine mlxf_var_op( r, f, a, option, proc )
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
        call check_dim(a, option%dim, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%keepdims, c_bool), int(option%ddof, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_var_op

    ! r = f(a) over the Fortran dimensions option%dims with option%ddof delta degrees of freedom, for every
    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool keepdims, int ddof,
    ! const mlx_stream s)
    module subroutine mlxf_var_dims_op( r, f, a, option, proc )
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
        axes = axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, axes, int(size(axes), c_size_t), logical(option%keepdims, c_bool), int(option%ddof, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_var_dims_op

    ! r = f(a, option(1), option(2)) for every int f(mlx_array* res, const mlx_array a, int i, int j,
    ! const mlx_stream s); the integers go to MLX as given, an axis among them already translated
    module subroutine mlxf_int2_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int2_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(1), c_int), int(option(2), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_int2_op

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
        call adopt(r, res, proc)
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
        call check_dtype(option(4), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option(1), c_int), int(option(2), c_int), int(option(3), c_int), int(option(4), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_trace_op

    ! the scan of a in array element order, a rank-1 result in a's dtype, for every int f(mlx_array* res,
    ! const mlx_array a, bool reverse, bool inclusive, mlx_optional_dtype dtype, const mlx_stream s)
    module subroutine mlxf_scan_all_op( r, f, a, option, proc )
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
        call adopt(r, res, proc)
    end subroutine mlxf_scan_all_op

    ! the scan of a along Fortran dimension option%dim, for every int f(mlx_array* res, const mlx_array a,
    ! int axis, bool reverse, bool inclusive, const mlx_stream s)
    module subroutine mlxf_scan_plain_op( r, f, a, option, proc )
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
        call check_dim(a, option%dim, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option%dim, c_int), logical(option%reverse, c_bool), logical(option%inclusive, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_scan_plain_op

    ! the scan of a in array element order, a rank-1 result, for every int f(mlx_array* res,
    ! const mlx_array a, bool reverse, bool inclusive, const mlx_stream s)
    module subroutine mlxf_scan_plain_all_op( r, f, a, option, proc )
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
        call adopt(r, res, proc)
    end subroutine mlxf_scan_plain_all_op

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
        call adopt(r, res, proc)
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
        call adopt(r, res, proc)
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
        call adopt(r, res, proc)
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
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: n
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        n = size(option%shape)
        if( size(option%strides) /= n ) call mlxf_fail(proc, 'one stride per dimension of the shape')
        if( any(option%shape < 0) .or. option%offset < 0 ) call mlxf_fail(proc, 'negative extent or offset')
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option%shape(n:1:-1), c_int), int(n, c_size_t), int(option%strides(n:1:-1), c_int64_t), int(n, c_size_t), int(option%offset, c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_strided_op

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
        call check_dtype(option%dtype, proc)
        axes = axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, axes, int(size(axes), c_size_t), logical(option%inverted, c_bool), int(option%dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_count_op

    ! r = f(option) for every int f(mlx_array* res, int M, const mlx_stream s)
    module subroutine mlxf_window_op( r, f, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_window_op)       :: f
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, int(option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_window_op

    ! r = f(option(1)) as dtype option(2), checked first, for every int f(mlx_array* res, int n,
    ! mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_identity_op( r, f, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_identity_op)     :: f
        integer,          intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_dtype(option(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, int(option(1), c_int), int(option(2), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_identity_op

    ! r = f(n, m, k) as a dtype, from option in that order as MLX takes them, the dtype checked first, for
    ! every int f(mlx_array* res, int n, int m, int k, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_eye_op( r, f, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_eye_op)          :: f
        integer,          intent(in)    :: option(4)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_dtype(option(4), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, int(option(1), c_int), int(option(2), c_int), int(option(3), c_int), int(option(4), c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_eye_op

    ! r = f(start, stop, num) of option, its dtype checked first, for every int f(mlx_array* res,
    ! double start, double stop, int num, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_linspace_op( r, f, option, proc )
        type(mlx_array),          intent(inout) :: r
        procedure(mlxc_linspace_op)             :: f
        type(mlxf_linspace_spec), intent(in)    :: option
        character(len=*),         intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_dtype(option%dtype, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, option%start, option%stop, int(option%num, c_int), int(option%dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_linspace_op

    ! r = f(start, stop, num, endpoint) of option, its dtype checked first, for every int f(mlx_array* res,
    ! double start, double stop, int num, bool endpoint, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_linspace_endpoint_op( r, f, option, proc )
        type(mlx_array),          intent(inout) :: r
        procedure(mlxc_linspace_endpoint_op)    :: f
        type(mlxf_linspace_spec), intent(in)    :: option
        character(len=*),         intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call check_dtype(option%dtype, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, option%start, option%stop, int(option%num, c_int), logical(option%endpoint, c_bool), int(option%dtype, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_linspace_endpoint_op

    ! r = f(a) for every int f(mlx_array* res, const mlx_vector_array arrays, const mlx_stream s); the list
    ! goes to MLX as a vector freed after the call
    module subroutine mlxf_list_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_list_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: proc
        type(mlxc_vector_array) :: v
        type(mlxc_array)        :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        call mlxf_require_device(proc)
        if( size(a) == 0 ) call mlxf_fail(proc, 'empty list')
        v = vector_of(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, v, s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_list_op

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
        v = vector_of(a, proc)
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

    ! the grids of f(a) in matrix indexing, sparse when option holds, in MLX's order, for every
    ! int f(mlx_vector_array* res, const mlx_vector_array arrays, bool sparse, const char* indexing,
    ! const mlx_stream s)
    module subroutine mlxf_meshgrid_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_meshgrid_op)                :: f
        type(mlx_array),  intent(in)               :: a(:)
        logical,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
        type(mlxc_vector_array) :: v
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        if( size(a) == 0 ) call mlxf_fail(proc, 'empty list')
        v = vector_of(a, proc)
        res = mlxc_vector_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, v, logical(option, c_bool), 'ij'//c_null_char, s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_meshgrid_op

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
        call adopt(r, res, proc)
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
        call adopt(r, res, proc)
    end subroutine mlxf_pad_width_op

    ! r = f(a(1), a(2:)) with the axes and slice sizes of option, all as MLX takes them, for every int f(mlx_array*
    ! res, const mlx_array a, const mlx_vector_array indices, const int* axes, size_t axes_num, const int* slice_sizes,
    ! size_t slice_sizes_num, const mlx_stream s)
    module subroutine mlxf_gather_op( r, f, a, option, proc )
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
        v = vector_of(a(2:), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, v, int(option%axes, c_int), int(size(option%axes), c_size_t), int(option%sizes, c_int), int(size(option%sizes), c_size_t), s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_gather_op

    ! r = f(a(1), a(2)) with the one axis and the slice sizes of option, as MLX takes them, for every
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, int axis, const int* slice_sizes,
    ! size_t slice_sizes_num, const mlx_stream s)
    module subroutine mlxf_gather_single_op( r, f, a, option, proc )
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
        call adopt(r, res, proc)
    end subroutine mlxf_gather_single_op

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
        call adopt(r, res, proc)
    end subroutine mlxf_slice_dynamic_op

    ! r = f(a(1), a(3:), a(2)): an array, its updates and then the index arrays, with the axes option as MLX takes
    ! them, for every int f(mlx_array* res, const mlx_array a, const mlx_vector_array indices, const mlx_array
    ! updates, const int* axes, size_t axes_num, const mlx_stream s)
    module subroutine mlxf_scatter_op( r, f, a, option, proc )
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
        v = vector_of(a(3:), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, v, hb, int(option, c_int), int(size(option), c_size_t), s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_scatter_op

    ! r = f(a(1), a(2), a(3), option): an array, indices and values, with the axis as MLX takes it, for every
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, const mlx_array values, int axis,
    ! const mlx_stream s)
    module subroutine mlxf_put_op( r, f, a, option, proc )
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
        call adopt(r, res, proc)
    end subroutine mlxf_put_op

    ! r = f(a(1), a(2), a(3), option): three arrays and a list as MLX takes it, for every int f(mlx_array* res,
    ! const mlx_array src, const mlx_array update, const mlx_array start, const int* axes, size_t axes_num,
    ! const mlx_stream s)
    module subroutine mlxf_ternary_vector_op( r, f, a, option, proc )
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
        call adopt(r, res, proc)
    end subroutine mlxf_ternary_vector_op

    ! r = f(a(1), a(2), option) for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! const char* text, const mlx_stream s)
    module subroutine mlxf_text_op( r, f, a, option, proc )
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
        call adopt(r, res, proc)
    end subroutine mlxf_text_op

    ! a(1) with its section of option, Fortran's inclusive 1-based bounds and strides as mlxf_slice_op takes them,
    ! updated by a(2), for every int f(mlx_array* res, const mlx_array src, const mlx_array update, const int* start,
    ! size_t start_num, const int* stop, size_t stop_num, const int* strides, size_t strides_num, const mlx_stream s)
    module subroutine mlxf_slice_update_op( r, f, a, option, proc )
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
        call slice_bounds(a(1), option, b, proc)
        n = int(size(b, 1), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, b(:, 1), n, b(:, 2), n, b(:, 3), n, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_slice_update_op

    ! the unique values of a(1) in option slots with their first positions, inverse positions and counts, in
    ! MLX's order and 0-based, padded with a(2) when it is given, for every int f(mlx_vector_array* res, const mlx_array
    ! a, int size, bool return_index, bool return_inverse, bool return_counts, const mlx_array fill_value, const mlx_stream s)
    module subroutine mlxf_unique_op( r, f, a, option, proc )
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

    ! unary plus: a new node with a's values
    module function pos_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_positive, a, 'operator(+)')
    end function pos_array

    ! lhs**rhs elementwise; a scalar operand is weak and takes the array's kind
    module function pow_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_power, lhs, rhs, 'operator(**)')
    end function pow_aa

    module function pow_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(**)')
        call mlxf_binary(r, mlxc_power, lhs, s, 'operator(**)')
    end function pow_as

    module function pow_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(**)')
        call mlxf_binary(r, mlxc_power, s, rhs, 'operator(**)')
    end function pow_sa

    module function pow_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, rhs, 'operator(**)')
        call mlxf_binary(r, mlxc_power, lhs, s, 'operator(**)')
    end function pow_ad

    module function pow_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, lhs, 'operator(**)')
        call mlxf_binary(r, mlxc_power, s, rhs, 'operator(**)')
    end function pow_da

    ! .eqv. and .neqv. of boolean arrays
    module function eqv_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_equal, lhs, rhs, 'operator(.eqv.)')
    end function eqv_aa

    module function neqv_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_logical_xor, lhs, rhs, 'operator(.neqv.)')
    end function neqv_aa

    ! a normalisation outside MLX_FFT_NORMS stops before it reaches mlx-c as an enum value
    subroutine check_fft_norm( norm, proc )
        integer,          intent(in) :: norm
        character(len=*), intent(in) :: proc
        if( all(norm /= [MLX_FFT_NORMS%backward, MLX_FFT_NORMS%forward, MLX_FFT_NORMS%ortho]) ) &
            &call mlxf_fail(proc, 'normalization must be a member of MLX_FFT_NORMS')
    end subroutine check_fft_norm

    ! stops unless dtype is a member of MLX_DTYPES: mlx-c converts it through a table it indexes unchecked
    subroutine check_dtype( dtype, proc )
        integer,          intent(in) :: dtype
        character(len=*), intent(in) :: proc
        if( all(dtype /= [MLX_DTYPES%bool, MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, &
            &MLX_DTYPES%uint8, MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64, MLX_DTYPES%float16, &
            &MLX_DTYPES%bfloat16, MLX_DTYPES%float32, MLX_DTYPES%float64, MLX_DTYPES%complex64]) ) &
            &call mlxf_fail(proc, 'the dtype must be a member of MLX_DTYPES')
    end subroutine check_dtype

    ! the MLX axes of the Fortran dimensions dims of a, each checked against its rank
    function axes_of( a, dims, proc ) result(axes)
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dims(:)
        character(len=*), intent(in) :: proc
        integer(c_int), allocatable :: axes(:)
        integer                     :: i, nd
        nd = a%ndim()
        allocate(axes(size(dims)))
        do i = 1, size(dims)
            if( dims(i) < 1 .or. dims(i) > nd ) call mlxf_fail(proc, 'dimension outside array rank')
            axes(i) = int(nd-dims(i), c_int)
        end do
    end function axes_of

    ! MLX's start, stop and strides (the columns of b) of the section option of a: Fortran's inclusive 1-based
    ! bounds reversed, 0-based and stop excluded; with a negative stride the stop is upper - 2, moved below
    ! -extent when negative so that MLX's negative-index rule leaves it before the first element
    subroutine slice_bounds( a, option, b, proc )
        type(mlx_array),       intent(in)               :: a
        type(mlxf_slice_spec), intent(in)               :: option
        integer(c_int),        allocatable, intent(out) :: b(:,:)
        character(len=*),      intent(in)               :: proc
        integer, allocatable :: sh(:)
        integer              :: n, j, k
        n = a%ndim()
        sh = a%shape()
        if( size(option%lower) /= n .or. size(option%upper) /= n .or. size(option%stride) /= n ) &
            &call mlxf_fail(proc, 'bounds and stride must match rank')
        if( any(option%stride == 0) ) call mlxf_fail(proc, 'zero stride')
        if( any(option%lower < 1) .or. any(option%lower > sh) .or. any(option%upper < 1) .or. any(option%upper > sh) ) &
            &call mlxf_fail(proc, 'slice bounds outside array')
        allocate(b(n, 3))
        do j = 1, n
            k = n+1-j
            b(j, 1) = int(option%lower(k)-1, c_int)
            b(j, 3) = int(option%stride(k), c_int)
            b(j, 2) = int(option%upper(k), c_int)
            if( b(j, 3) < 0 )then
                b(j, 2) = b(j, 2)-2
                if( b(j, 2) < 0 ) b(j, 2) = b(j, 2)-int(sh(k), c_int)
            endif
        end do
    end subroutine slice_bounds

    ! stops unless dim is a dimension of a (1 to its rank)
    module subroutine check_dim( a, dim, proc )
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dim
        character(len=*), intent(in) :: proc
        integer :: nd
        nd = a%ndim()
        if( dim < 1 .or. dim > nd ) call mlxf_fail(proc, 'dimension outside array rank')
    end subroutine check_dim

end submodule mlxf_array_operations
