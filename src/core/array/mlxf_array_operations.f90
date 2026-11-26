!@descr: signature-class helpers for shaped, indexed, closeness, reduction and Fourier operations; power and logic operators
submodule(mlxf_array) mlxf_array_operations
use, intrinsic :: iso_c_binding, only: c_null_char, c_null_ptr, c_associated
use mlxf_c_types,  only: mlxc_device, MLXC_CPU
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_device, only: mlxc_device_new_type, mlxc_device_free
use mlxf_c_ops,    only: mlxc_power, mlxc_equal, mlxc_logical_xor, mlxc_positive, mlxc_subtract, mlxc_astype, mlxc_add
use mlxf_c_stream, only: mlxc_stream_free, mlxc_stream_new, mlxc_get_default_stream
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
        call mlxf_check_dtype(dtype, proc)
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
        call mlxf_check_dtype(dtype, proc)
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
        call mlxf_check_dtype(option%dtype, proc)
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

    ! r = f(a) over the Fortran dimensions option%dims with the lengths option%n, in the order given (MLX halves a
    ! real transform along the last), for every int f(mlx_array* res, const mlx_array a, const int* n, size_t n_num,
    ! const int* axes, size_t axes_num, mlx_fft_norm norm, const mlx_stream s); the norm is checked first
    module subroutine mlxf_fftn_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_fftn_op)             :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_fftn_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)            :: ha
        integer(c_int), allocatable :: axes(:)
        integer(c_size_t)           :: n
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        call mlxf_require_device(proc)
        call check_fft_norm(option%norm, proc)
        ha = mlxf_handle(a, proc)
        if( size(option%n) /= size(option%dims) ) call mlxf_fail(proc, 'one length per transformed dimension is needed')
        axes = mlxf_axes_of(a, option%dims, proc)
        n = int(size(axes), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(option%n, c_int), n, axes, n, int(option%norm, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_fftn_op

    ! r = f(n, d) for every int f(mlx_array* res, int n, double d, const mlx_stream s)
    module subroutine mlxf_freq_op( r, f, n, d, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_freq_op)         :: f
        integer,          intent(in)    :: n
        real(c_double),   intent(in)    :: d
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, int(n, c_int), d, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_freq_op

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
        call mlxf_check_dtype(option%dtype, proc)
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
        call mlxf_check_dtype(option, proc)
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
        axes = mlxf_axes_of(a, option%dims, proc)
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
        axes = mlxf_axes_of(a, option%dims, proc)
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
        call mlxf_check_dtype(option(4), proc)
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
        call adopt(r, res, proc)
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
        call mlxf_check_dtype(option(2), proc)
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
        call mlxf_check_dtype(option(4), proc)
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
        call mlxf_check_dtype(option%dtype, proc)
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
        call mlxf_check_dtype(option%dtype, proc)
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

    ! r = f(a(1), a(2)) with the matrices of each operand chosen by the 0-based index arrays a(3) and a(4), an
    ! empty one being none, for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! const mlx_array lhs_indices, const mlx_array rhs_indices, bool sorted_indices, const mlx_stream s)
    module subroutine mlxf_gather_mm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_gather_mm_op)    :: f
        type(mlx_array),  intent(in)    :: a(4)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(4)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: i
        call mlxf_require_device(proc)
        do i = 1, 4
            if( i <= 2 .or. c_associated(a(i)%h%ctx) ) h(i) = mlxf_handle(a(i), proc)
        end do
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), h(3), h(4), logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_gather_mm_op

    ! r = f(a(1), a(2)) with blocks of option rows and columns masked: a(3) masks the result, a(4) and a(5) the
    ! operands, an empty one being none, for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! int block_size, const mlx_array mask_out, const mlx_array mask_lhs, const mlx_array mask_rhs, const mlx_stream s)
    module subroutine mlxf_masked_mm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_masked_mm_op)    :: f
        type(mlx_array),  intent(in)    :: a(5)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(5)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: i
        call mlxf_require_device(proc)
        do i = 1, 5
            if( i <= 2 .or. c_associated(a(i)%h%ctx) ) h(i) = mlxf_handle(a(i), proc)
        end do
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), int(option, c_int), h(3), h(4), h(5), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_masked_mm_op

    ! r = f(a) on the CPU's default stream whatever the default device, for a function of mlxc_unary_op's signature
    ! that MLX implements on the CPU only
    module subroutine mlxf_cpu_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res, ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_cpu_unary

    ! r = f(a, b) on the CPU's default stream, for a function of mlxc_binary_op's signature that MLX implements on
    ! the CPU only
    module subroutine mlxf_cpu_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha, hb
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        hb = mlxf_handle(b, proc)
        res = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res, ha, hb, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_cpu_binary

    ! r = f(a, option) on the CPU's default stream, for every int f(mlx_array* res, const mlx_array a, bool flag,
    ! const mlx_stream s) that MLX implements on the CPU only; the flag goes to MLX as given
    module subroutine mlxf_cpu_flag_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_flag_op)         :: f
        type(mlx_array),  intent(in)    :: a
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res, ha, logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_cpu_flag_op

    ! r = f(a(1), a(2), option) on the CPU's default stream, for every int f(mlx_array* res, const mlx_array a,
    ! const mlx_array b, bool flag, const mlx_stream s) that MLX implements on the CPU only
    module subroutine mlxf_cpu_compare_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_compare_op)      :: f
        type(mlx_array),  intent(in)    :: a(2)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        res = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res, h(1), h(2), logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_cpu_compare_op

    ! the two results of f(a), in MLX's order, on the CPU's default stream, for every int f(mlx_array* res_0,
    ! mlx_array* res_1, const mlx_array a, const mlx_stream s)
    module subroutine mlxf_cpu_pair_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_op)         :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res(2)
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res(1) = mlxc_array_new()
        res(2) = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res(1), res(2), ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 )then
            call mlxf_check(mlxc_array_free(res(1)), proc)
            call mlxf_check(mlxc_array_free(res(2)), proc)
        endif
        call mlxf_check(ierr, proc)
        call adopt(r(1), res(1), proc)
        call adopt(r(2), res(2), proc)
    end subroutine mlxf_cpu_pair_op

    ! the two results of f(a, option), in MLX's order, on the CPU's default stream, for every int f(mlx_array* res_0,
    ! mlx_array* res_1, const mlx_array a, const char* text, const mlx_stream s)
    module subroutine mlxf_cpu_pair_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_text_op)    :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res(2)
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res(1) = mlxc_array_new()
        res(2) = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res(1), res(2), ha, trim(option)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 )then
            call mlxf_check(mlxc_array_free(res(1)), proc)
            call mlxf_check(mlxc_array_free(res(2)), proc)
        endif
        call mlxf_check(ierr, proc)
        call adopt(r(1), res(1), proc)
        call adopt(r(2), res(2), proc)
    end subroutine mlxf_cpu_pair_text_op

    ! r = f(a, option) on the CPU's default stream, for every int f(mlx_array* res, const mlx_array a,
    ! const char* text, const mlx_stream s)
    module subroutine mlxf_cpu_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_text_op)   :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res, ha, trim(option)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_cpu_text_op

    ! the arrays of f(a), in MLX's order, on the CPU's default stream, for a function of mlxc_unstack_op's signature
    ! that MLX implements on the CPU only
    module subroutine mlxf_cpu_unstack_op( r, f, a, proc )
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
        s = cpu_stream(proc)
        ierr = f(res, ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_cpu_unstack_op

    ! the arrays of f(a, option), in MLX's order, on the CPU's default stream, for every int f(mlx_vector_array* res,
    ! const mlx_array a, bool flag, const mlx_stream s)
    module subroutine mlxf_cpu_svd_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_vector_flag_op)             :: f
        type(mlx_array),  intent(in)               :: a
        logical,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_vector_array_new()
        s = cpu_stream(proc)
        ierr = f(res, ha, logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_cpu_svd_op

    ! the norm of order option%ord of a over the Fortran dimensions option%dims, each translated to its MLX axis in the
    ! order given (of two, the first is the rows'), on the CPU's default stream when option%on_cpu, for every
    ! int f(mlx_array* res, const mlx_array a, double ord, const int* axis, size_t axis_num, bool keepdims, const mlx_stream s)
    module subroutine mlxf_norm_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_norm_op)             :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_norm_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)            :: ha
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:)
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        axes = mlxf_axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        if( option%on_cpu )then
            s = cpu_stream(proc)
        else
            s = mlxf_default_stream(proc)
        endif
        ierr = f(res, ha, option%ord, axes, int(size(axes), c_size_t), logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_norm_op

    ! the matrix norm named option%name of a over the Fortran dimensions option%dims, as mlxf_norm_op takes them, for
    ! every int f(mlx_array* res, const mlx_array a, const char* ord, const int* axis, size_t axis_num, bool keepdims,
    ! const mlx_stream s)
    module subroutine mlxf_norm_text_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_norm_text_op)        :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_norm_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)            :: ha
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:)
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        axes = mlxf_axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        if( option%on_cpu )then
            s = cpu_stream(proc)
        else
            s = mlxf_default_stream(proc)
        endif
        ierr = f(res, ha, trim(option%name)//c_null_char, axes, int(size(axes), c_size_t), logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_norm_text_op

    ! r = f(a(1), a(2), option) for a function of mlxc_take_op's signature whose integer goes to MLX as given: an axis
    ! already translated (a negative one counts from the last, so that it serves operands of different ranks) or a count
    module subroutine mlxf_binary_axis_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_take_op)         :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), int(option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_binary_axis_op

    ! r = f(a, option), an absent option being MLX's default, for every int f(mlx_array* res, const mlx_array a,
    ! mlx_optional_float scale, const mlx_stream s)
    module subroutine mlxf_optional_float_op( r, f, a, proc, option )
        type(mlx_array),  intent(inout)        :: r
        procedure(mlxc_optional_float_op)      :: f
        type(mlx_array),  intent(in)           :: a
        character(len=*), intent(in)           :: proc
        real(real32),     optional, intent(in) :: option
        type(mlxc_array)          :: ha
        type(mlxc_optional_float) :: scale
        type(mlxc_array)          :: res
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        scale%value = 0
        scale%has_value = present(option)
        if( present(option) ) scale%value = real(option, c_float_kind)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, scale, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_optional_float_op

    ! r = option(1)*(a(2) times a(3)) + option(2)*a(1), a matrix product in MLX's view, for every int f(mlx_array* res,
    ! const mlx_array c, const mlx_array a, const mlx_array b, float alpha, float beta, const mlx_stream s)
    module subroutine mlxf_addmm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_addmm_op)        :: f
        type(mlx_array),  intent(in)    :: a(3)
        real(real32),     intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(3)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: i
        call mlxf_require_device(proc)
        do i = 1, 3
            h(i) = mlxf_handle(a(i), proc)
        end do
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), h(3), real(option(1), c_float_kind), real(option(2), c_float_kind), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_addmm_op

    ! r = f(option, a), the subscripts already in MLX's axis order, for every int f(mlx_array* res,
    ! const char* subscripts, const mlx_vector_array operands, const mlx_stream s)
    module subroutine mlxf_einsum_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_einsum_op)       :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: option
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
        ierr = f(res, trim(option)//c_null_char, v, s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_einsum_op

    ! r = f(a(1), a(2)) contracting the axes option(:, 1) of a(1) with the axes option(:, 2) of a(2), as MLX takes them,
    ! for every int f(mlx_array* res, const mlx_array a, const mlx_array b, const int* axes_a, size_t axes_a_num,
    ! const int* axes_b, size_t axes_b_num, const mlx_stream s)
    module subroutine mlxf_tensordot_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_tensordot_op)    :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option(:,:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)            :: h(2)
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:,:)
        integer(c_size_t)           :: n
        call mlxf_require_device(proc)
        if( size(option, 2) /= 2 ) call mlxf_fail(proc, 'two lists of axes are needed')
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        axes = int(option, c_int)
        n = int(size(axes, 1), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), axes(:, 1), n, axes(:, 2), n, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_tensordot_op

    ! the convolution of a(1) with the kernels a(2) over one spatial dimension, with the stride, padding, dilation and
    ! groups of option, for every function of mlx_conv1d's signature
    module subroutine mlxf_conv1d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv1d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(1), pd(1), dl(1)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 1, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. allocated(option%output_padding) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general, output_padding to the transposed convolutions')
        st = conv_list(option%stride, 1, 1, proc)
        pd = conv_list(option%padding, 1, 0, proc)
        dl = conv_list(option%dilation, 1, 1, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), pd(1), dl(1), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_conv1d_op

    ! the convolution over two spatial dimensions: option's lists, given per Fortran dimension, reach MLX reversed, for
    ! every function of mlx_conv2d's signature
    module subroutine mlxf_conv2d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv2d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(2), pd(2), dl(2)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 2, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. allocated(option%output_padding) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general, output_padding to the transposed convolutions')
        st = conv_list(option%stride, 2, 1, proc)
        pd = conv_list(option%padding, 2, 0, proc)
        dl = conv_list(option%dilation, 2, 1, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), pd(1), pd(2), dl(1), dl(2), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_conv2d_op

    ! the convolution over three spatial dimensions, option's lists reversed, for every function of mlx_conv3d's signature
    module subroutine mlxf_conv3d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv3d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(3), pd(3), dl(3)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 3, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. allocated(option%output_padding) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general, output_padding to the transposed convolutions')
        st = conv_list(option%stride, 3, 1, proc)
        pd = conv_list(option%padding, 3, 0, proc)
        dl = conv_list(option%dilation, 3, 1, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), st(3), pd(1), pd(2), pd(3), dl(1), dl(2), dl(3), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_conv3d_op

    ! the general convolution over one to three spatial dimensions: padding before and after (padding_hi, or the same),
    ! the kernel's and the input's dilation, groups and a reversed kernel, option's lists reversed, for every function of
    ! mlx_conv_general's signature
    module subroutine mlxf_conv_general_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv_general_op)    :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)            :: h(2)
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: st(:), lo(:), hi(:), dl(:), il(:)
        integer(c_size_t)           :: n
        integer                     :: nsp
        call mlxf_require_device(proc)
        nsp = a(1)%ndim()-2
        call conv_operands(h, a, nsp, option%groups, proc)
        if( allocated(option%output_padding) ) call mlxf_fail(proc, 'output_padding belongs to the transposed convolutions')
        st = conv_list(option%stride, nsp, 1, proc)
        lo = conv_list(option%padding, nsp, 0, proc)
        if( allocated(option%padding_hi) )then
            hi = conv_list(option%padding_hi, nsp, 0, proc)
        else
            hi = lo
        endif
        dl = conv_list(option%dilation, nsp, 1, proc)
        il = conv_list(option%input_dilation, nsp, 1, proc)
        n = int(nsp, c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st, n, lo, n, hi, n, dl, n, il, n, int(option%groups, c_int), logical(option%flip, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_conv_general_op

    ! the transposed convolution over one spatial dimension, with the stride, padding, dilation, output padding and
    ! groups of option, for every function of mlx_conv_transpose1d's signature
    module subroutine mlxf_conv_transpose1d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose1d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(1), pd(1), dl(1), op(1)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 1, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general')
        st = conv_list(option%stride, 1, 1, proc)
        pd = conv_list(option%padding, 1, 0, proc)
        dl = conv_list(option%dilation, 1, 1, proc)
        op = conv_list(option%output_padding, 1, 0, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), pd(1), dl(1), op(1), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_conv_transpose1d_op

    ! the transposed convolution over two spatial dimensions, option's lists reversed, for every function of
    ! mlx_conv_transpose2d's signature
    module subroutine mlxf_conv_transpose2d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose2d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(2), pd(2), dl(2), op(2)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 2, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general')
        st = conv_list(option%stride, 2, 1, proc)
        pd = conv_list(option%padding, 2, 0, proc)
        dl = conv_list(option%dilation, 2, 1, proc)
        op = conv_list(option%output_padding, 2, 0, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), pd(1), pd(2), dl(1), dl(2), op(1), op(2), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_conv_transpose2d_op

    ! the transposed convolution over three spatial dimensions, option's lists reversed, for every function of
    ! mlx_conv_transpose3d's signature
    module subroutine mlxf_conv_transpose3d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose3d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(3), pd(3), dl(3), op(3)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 3, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general')
        st = conv_list(option%stride, 3, 1, proc)
        pd = conv_list(option%padding, 3, 0, proc)
        dl = conv_list(option%dilation, 3, 1, proc)
        op = conv_list(option%output_padding, 3, 0, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), st(3), pd(1), pd(2), pd(3), dl(1), dl(2), dl(3), op(1), op(2), op(3), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_conv_transpose3d_op

    ! the handles of a convolution's input a(1) and kernels a(2), both of rank n + 2 for n spatial dimensions (1 to
    ! 3); MLX divides by the groups unchecked, so they are checked here
    subroutine conv_operands( h, a, n, groups, proc )
        type(mlxc_array), intent(out) :: h(2)
        type(mlx_array),  intent(in)  :: a(2)
        integer,          intent(in)  :: n, groups
        character(len=*), intent(in)  :: proc
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        if( groups < 1 ) call mlxf_fail(proc, 'groups must be at least 1')
        if( n < 1 .or. n > 3 ) call mlxf_fail(proc, 'a convolution has one to three spatial dimensions: an input of rank 3 to 5')
        if( a(1)%ndim() /= n+2 ) call mlxf_fail(proc, 'the input needs the rank (channels, the spatial dimensions, batch)')
        if( a(2)%ndim() /= n+2 ) call mlxf_fail(proc, 'the kernels need the rank (input channels, the spatial dimensions, kernels)')
    end subroutine conv_operands

    ! one list of a convolution's options as MLX takes it: a value per spatial dimension, the Fortran order reversed;
    ! an absent list is fill everywhere and a list of one value serves every dimension
    function conv_list( list, n, fill, proc ) result(v)
        integer, allocatable, intent(in) :: list(:)
        integer,              intent(in) :: n, fill
        character(len=*),     intent(in) :: proc
        integer(c_int) :: v(n)
        v = int(fill, c_int)
        if( .not. allocated(list) ) return
        if( size(list) == 1 )then
            v = int(list(1), c_int)
        else if( size(list) == n )then
            v = int(list(n:1:-1), c_int)
        else
            call mlxf_fail(proc, 'a list of the convolution spec needs one value, or one per spatial dimension')
        endif
    end function conv_list

    ! the default stream of the CPU, where MLX runs what it implements on the CPU only whatever the default
    ! device; the caller frees it with mlxc_stream_free
    module function cpu_stream( proc ) result(s)
        character(len=*), intent(in) :: proc
        type(mlxc_stream) :: s
        type(mlxc_device) :: dev
        dev = mlxc_device_new_type(MLXC_CPU, 0_c_int)
        s = mlxc_stream_new()
        call mlxf_check(mlxc_get_default_stream(s, dev), proc)
        call mlxf_check(mlxc_device_free(dev), proc)
    end function cpu_stream

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
    module subroutine mlxf_check_dtype( dtype, proc )
        integer,          intent(in) :: dtype
        character(len=*), intent(in) :: proc
        if( all(dtype /= [MLX_DTYPES%bool, MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, &
            &MLX_DTYPES%uint8, MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64, MLX_DTYPES%float16, &
            &MLX_DTYPES%bfloat16, MLX_DTYPES%float32, MLX_DTYPES%float64, MLX_DTYPES%complex64]) ) &
            &call mlxf_fail(proc, 'the dtype must be a member of MLX_DTYPES')
    end subroutine mlxf_check_dtype

    ! 1-based integer positions as MLX's: one subtracted in the graph, or the amounts less, broadcast along
    ! dimension 1; a non-integer array stops. uint64 goes through int64 first, since MLX promotes uint64 with a
    ! signed integer to a float
    module subroutine mlxf_zero_based( r, indices, proc, less )
        type(mlx_array),  intent(inout)        :: r
        type(mlx_array),  intent(in)           :: indices
        character(len=*), intent(in)           :: proc
        integer,          optional, intent(in) :: less(:)
        type(mlx_array) :: offset, signed
        integer         :: dtype
        dtype = indices%kind()
        if( all(dtype /= [MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, MLX_DTYPES%uint8, &
            &MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64]) ) call mlxf_fail(proc, 'indices must be integers')
        if( present(less) )then
            offset = mlx_from(int(less, int32))
        else
            offset = mlx_from(1_int32)
        endif
        if( dtype == MLX_DTYPES%uint64 )then
            call mlxf_int_op(signed, mlxc_astype, indices, MLX_DTYPES%int64, proc)
            call mlxf_binary(r, mlxc_subtract, signed, offset, proc)
        else
            call mlxf_binary(r, mlxc_subtract, indices, offset, proc)
        endif
    end subroutine mlxf_zero_based

    ! MLX's 0-based positions as Fortran's: int32, one added in the graph
    module subroutine mlxf_one_based( r, idx, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: idx
        character(len=*), intent(in)    :: proc
        type(mlx_array) :: cast, one
        call mlxf_int_op(cast, mlxc_astype, idx, MLX_DTYPES%int32, proc)
        one = mlx_from(1_int32)
        call mlxf_binary(r, mlxc_add, cast, one, proc)
    end subroutine mlxf_one_based

    ! the MLX axes of the Fortran dimensions dims of a, each checked against its rank
    module function mlxf_axes_of( a, dims, proc ) result(axes)
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
    end function mlxf_axes_of

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
