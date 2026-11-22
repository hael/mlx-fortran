!@descr: signature-class helpers for shaped, indexed, reduction and Fourier operations
submodule(mlxf_array) mlxf_array_operations
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_c_vector, only: mlxc_vector_array_free
use mlxf_defs,     only: MLX_FFT_NORMS
use mlxf_device,   only: mlxf_require_device, mlxf_default_stream
use mlxf_error,    only: mlxf_check, mlxf_fail
implicit none

contains

    ! r = f(a, option) on the default device, for every int f(mlx_array* res, const mlx_array a,
    ! mlx_dtype dtype, const mlx_stream s)
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

    ! r = f(a) along Fortran dimension option (MLX axis rank - option), which the result loses, for every
    ! int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, const mlx_stream s)
    module subroutine mlxf_reduce_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_reduce_op)       :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call check_dim(a, option, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option, c_int), .false._c_bool, s)
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

    ! the inclusive forward scan of a along Fortran dimension option, in its dtype, for every
    ! int f(mlx_array* res, const mlx_array a, int axis, bool reverse, bool inclusive, mlx_optional_dtype
    ! dtype, const mlx_stream s)
    module subroutine mlxf_scan_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_scan_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)          :: ha
        type(mlxc_optional_dtype) :: dtype
        type(mlxc_array)          :: res
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        call check_dim(a, option, proc)
        dtype%has_value = .false._c_bool
        dtype%value = 0_c_int
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a%ndim()-option, c_int), .false._c_bool, .true._c_bool, dtype, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_scan_op

    ! the slice of a from Fortran's inclusive, 1-based bounds and strides: MLX takes them reversed, 0-based and
    ! stop excluded; with a negative stride the stop is upper - 2, moved below -extent when negative so that
    ! MLX's negative-index rule leaves it before the first element
    module subroutine mlxf_slice_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_slice_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
        type(mlxc_array)            :: ha
        integer(c_int), allocatable :: lo(:), hi(:), stride(:)
        integer,        allocatable :: sh(:)
        integer                     :: n, j, k
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        n = a%ndim()
        sh = a%shape()
        if( size(option%lower) /= n .or. size(option%upper) /= n .or. size(option%stride) /= n ) &
            &call mlxf_fail(proc, 'bounds and stride must match rank')
        if( any(option%stride == 0) ) call mlxf_fail(proc, 'zero stride')
        if( any(option%lower < 1) .or. any(option%lower > sh) .or. any(option%upper < 1) .or. any(option%upper > sh) ) &
            &call mlxf_fail(proc, 'slice bounds outside array')
        allocate(lo(n), hi(n), stride(n))
        do j = 1, n
            k = n+1-j
            lo(j) = int(option%lower(k)-1, c_int)
            stride(j) = int(option%stride(k), c_int)
            hi(j) = int(option%upper(k), c_int)
            if( stride(j) < 0 )then
                hi(j) = hi(j)-2
                if( hi(j) < 0 ) hi(j) = hi(j)-int(sh(k), c_int)
            endif
        end do
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, lo, int(n, c_size_t), hi, int(n, c_size_t), stride, int(n, c_size_t), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_slice_op

    ! r = f(a) along Fortran dimension option, for every int f(mlx_array* res, const mlx_vector_array arrays,
    ! int axis, const mlx_stream s); the list goes to MLX as a vector freed after the call
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
        call check_dim(a(1), option, proc)
        v = vector_of(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, v, int(a(1)%ndim()-option, c_int), s)
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

    ! a normalisation outside MLX_FFT_NORMS stops before it reaches mlx-c as an enum value
    subroutine check_fft_norm( norm, proc )
        integer,          intent(in) :: norm
        character(len=*), intent(in) :: proc
        if( all(norm /= [MLX_FFT_NORMS%backward, MLX_FFT_NORMS%forward, MLX_FFT_NORMS%ortho]) ) &
            &call mlxf_fail(proc, 'normalization must be a member of MLX_FFT_NORMS')
    end subroutine check_fft_norm

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
