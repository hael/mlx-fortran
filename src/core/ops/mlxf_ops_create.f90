!@descr: constructors: ones, fills, arrays shaped like another, identity and triangular matrices, grids and windows
! A scalar fill value becomes a 0-d array of the result's kind (float64 only for a float64 result), so that
! building it never needs the GPU to convert from float64.
submodule(mlxf_ops) mlxf_ops_create
use mlxf_c_ops,  only: mlxc_bartlett, mlxc_blackman, mlxc_eye, mlxc_full, mlxc_full_like, mlxc_hamming, mlxc_hanning, &
                       mlxc_identity, mlxc_linspace, mlxc_linspace_endpoint, mlxc_meshgrid, mlxc_ones, mlxc_ones_like, &
                       mlxc_ones_like_dtype, mlxc_transpose, mlxc_tri, mlxc_zeros_like, mlxc_zeros_like_dtype
use mlxf_defs,   only: MLX_DTYPES, mlxf_shape_spec, mlxf_linspace_spec
use mlxf_array,  only: mlx_from, mlxf_binary_int_op, mlxf_eye_op, mlxf_full_op, mlxf_dtype_op, mlxf_identity_op, &
                       mlxf_linspace_endpoint_op, mlxf_linspace_op, mlxf_meshgrid_op, mlxf_unary, mlxf_window_op, &
                       mlxf_zeros_op
use mlxf_device, only: mlxf_enter
use mlxf_error,  only: mlxf_fail
implicit none

contains

    ! an array of ones of Fortran shape shape, float32 unless dtype is given
    module function mlx_ones( shape, dtype ) result(r)
        integer, intent(in)           :: shape(:)
        integer, optional, intent(in) :: dtype
        type(mlx_array) :: r
        integer         :: kind
        call mlxf_enter('mlx_ones')
        kind = MLX_DTYPES%float32
        if( present(dtype) ) kind = dtype
        call mlxf_zeros_op(r, mlxc_ones, shape, kind, 'mlx_ones')
    end function mlx_ones

    ! an array of Fortran shape shape filled with vals, broadcast with leading dimensions aligned; the kind is
    ! vals' unless dtype is given
    module function full_array( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        type(mlx_array), intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array)       :: r
        type(mlxf_shape_spec) :: spec
        call mlxf_enter('mlx_full')
        spec%shape = shape
        spec%dtype = vals%kind()
        if( present(dtype) ) spec%dtype = dtype
        call mlxf_full_op(r, mlxc_full, vals, spec, 'mlx_full')
    end function full_array

    ! the scalar fills: float32 for a real value and int32 for an integer one unless dtype is given
    module function full_s( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        real(real32),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array)       :: r
        type(mlx_array)       :: v
        type(mlxf_shape_spec) :: spec
        call mlxf_enter('mlx_full')
        spec%shape = shape
        if( present(dtype) ) spec%dtype = dtype
        v = real_fill(real(vals, real64), spec%dtype)
        call mlxf_full_op(r, mlxc_full, v, spec, 'mlx_full')
    end function full_s

    module function full_d( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        real(real64),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array)       :: r
        type(mlx_array)       :: v
        type(mlxf_shape_spec) :: spec
        call mlxf_enter('mlx_full')
        spec%shape = shape
        if( present(dtype) ) spec%dtype = dtype
        v = real_fill(vals, spec%dtype)
        call mlxf_full_op(r, mlxc_full, v, spec, 'mlx_full')
    end function full_d

    module function full_i( shape, vals, dtype ) result(r)
        integer,         intent(in)           :: shape(:)
        integer,         intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array)       :: r
        type(mlx_array)       :: v
        type(mlxf_shape_spec) :: spec
        call mlxf_enter('mlx_full')
        spec%shape = shape
        spec%dtype = MLX_DTYPES%int32
        if( present(dtype) ) spec%dtype = dtype
        v = mlx_from(int(vals, int32))
        call mlxf_full_op(r, mlxc_full, v, spec, 'mlx_full')
    end function full_i

    ! zeros of a's shape, of a's kind unless dtype is given
    module function mlx_zeros_like( a, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
        call mlxf_enter('mlx_zeros_like')
        if( present(dtype) )then
            call mlxf_dtype_op(r, mlxc_zeros_like_dtype, a, dtype, 'mlx_zeros_like')
        else
            call mlxf_unary(r, mlxc_zeros_like, a, 'mlx_zeros_like')
        endif
    end function mlx_zeros_like

    ! ones of a's shape, of a's kind unless dtype is given
    module function mlx_ones_like( a, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
        call mlxf_enter('mlx_ones_like')
        if( present(dtype) )then
            call mlxf_dtype_op(r, mlxc_ones_like_dtype, a, dtype, 'mlx_ones_like')
        else
            call mlxf_unary(r, mlxc_ones_like, a, 'mlx_ones_like')
        endif
    end function mlx_ones_like

    ! vals broadcast to a's shape, of a's kind unless dtype is given
    module function full_like_array( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        type(mlx_array), intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
        integer         :: kind
        call mlxf_enter('mlx_full_like')
        kind = a%kind()
        if( present(dtype) ) kind = dtype
        call mlxf_binary_int_op(r, mlxc_full_like, [a, vals], kind, 'mlx_full_like')
    end function full_like_array

    module function full_like_s( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        real(real32),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
        type(mlx_array) :: v
        integer         :: kind
        call mlxf_enter('mlx_full_like')
        kind = a%kind()
        if( present(dtype) ) kind = dtype
        v = real_fill(real(vals, real64), kind)
        call mlxf_binary_int_op(r, mlxc_full_like, [a, v], kind, 'mlx_full_like')
    end function full_like_s

    module function full_like_d( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        real(real64),    intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
        type(mlx_array) :: v
        integer         :: kind
        call mlxf_enter('mlx_full_like')
        kind = a%kind()
        if( present(dtype) ) kind = dtype
        v = real_fill(vals, kind)
        call mlxf_binary_int_op(r, mlxc_full_like, [a, v], kind, 'mlx_full_like')
    end function full_like_d

    module function full_like_i( a, vals, dtype ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: vals
        integer,         optional, intent(in) :: dtype
        type(mlx_array) :: r
        type(mlx_array) :: v
        integer         :: kind
        call mlxf_enter('mlx_full_like')
        kind = a%kind()
        if( present(dtype) ) kind = dtype
        v = mlx_from(int(vals, int32))
        call mlxf_binary_int_op(r, mlxc_full_like, [a, v], kind, 'mlx_full_like')
    end function full_like_i

    ! a real fill value as a 0-d array: float64 for a float64 result, float32 otherwise (MLX converts it)
    function real_fill( x, dtype ) result(v)
        real(real64), intent(in) :: x
        integer,      intent(in) :: dtype
        type(mlx_array) :: v
        if( dtype == MLX_DTYPES%float64 )then
            v = mlx_from(x)
        else
            v = mlx_from(real(x, real32))
        endif
    end function real_fill

    ! the n by n identity matrix, float32 unless dtype is given
    module function mlx_identity( n, dtype ) result(r)
        integer, intent(in)           :: n
        integer, optional, intent(in) :: dtype
        type(mlx_array) :: r
        integer         :: kind
        call mlxf_enter('mlx_identity')
        kind = MLX_DTYPES%float32
        if( present(dtype) ) kind = dtype
        call mlxf_identity_op(r, mlxc_identity, [n, kind], 'mlx_identity')
    end function mlx_identity

    ! an (n, m) matrix (m = n by default) with ones on diagonal k, elements (i, i + k), and zeros elsewhere;
    ! MLX builds its transpose: m rows, n columns and diagonal -k
    module function mlx_eye( n, m, k, dtype ) result(r)
        integer, intent(in)           :: n
        integer, optional, intent(in) :: m, k, dtype
        type(mlx_array) :: r
        integer         :: option(4)
        call mlxf_enter('mlx_eye')
        option = [n, n, 0, MLX_DTYPES%float32]
        if( present(m) ) option(1) = m
        if( present(k) ) option(3) = -k
        if( present(dtype) ) option(4) = dtype
        call mlxf_eye_op(r, mlxc_eye, option, 'mlx_eye')
    end function mlx_eye

    ! an (n, m) matrix (m = n by default) with ones at and below diagonal k, elements (i, j) with j <= i + k;
    ! MLX's (n, m) triangle is the Fortran view's transpose, so one transpose node (a view) follows it
    module function mlx_tri( n, m, k, dtype ) result(r)
        integer, intent(in)           :: n
        integer, optional, intent(in) :: m, k, dtype
        type(mlx_array) :: r
        type(mlx_array) :: t
        integer         :: option(4)
        call mlxf_enter('mlx_tri')
        option = [n, n, 0, MLX_DTYPES%float32]
        if( present(m) ) option(2) = m
        if( present(k) ) option(3) = k
        if( present(dtype) ) option(4) = dtype
        call mlxf_eye_op(t, mlxc_tri, option, 'mlx_tri')
        call mlxf_unary(r, mlxc_transpose, t, 'mlx_tri')
    end function mlx_tri

    ! num (50 by default) evenly spaced values from start to stop, stop included unless endpoint is false;
    ! float32 unless dtype is given
    module function mlx_linspace( start, stop, num, endpoint, dtype ) result(r)
        real(real64), intent(in)           :: start, stop
        integer,      optional, intent(in) :: num, dtype
        logical,      optional, intent(in) :: endpoint
        type(mlx_array)          :: r
        type(mlxf_linspace_spec) :: spec
        call mlxf_enter('mlx_linspace')
        spec%start = start
        spec%stop = stop
        if( present(num) ) spec%num = num
        if( present(dtype) ) spec%dtype = dtype
        if( present(endpoint) )then
            spec%endpoint = endpoint
            call mlxf_linspace_endpoint_op(r, mlxc_linspace_endpoint, spec, 'mlx_linspace')
        else
            call mlxf_linspace_op(r, mlxc_linspace, spec, 'mlx_linspace')
        endif
    end function mlx_linspace

    ! the coordinate grids of rank-1 arrays in matrix indexing: grid i has shape (n1, ..., nk) and varies along
    ! dimension i (extent 1 along the others when sparse). MLX numbers axes in the reverse order, so the list
    ! goes to it reversed and comes back reversed
    module subroutine mlx_meshgrid( arrays, grids, sparse )
        type(mlx_array), intent(in)               :: arrays(:)
        type(mlx_array), allocatable, intent(out) :: grids(:)
        logical,         optional, intent(in)     :: sparse
        type(mlx_array), allocatable :: reversed(:), results(:)
        logical                      :: thin
        integer                      :: i, n
        call mlxf_enter('mlx_meshgrid')
        n = size(arrays)
        thin = .false.
        if( present(sparse) ) thin = sparse
        allocate(reversed(n))
        do i = 1, n
            reversed(i) = arrays(n+1-i)
        end do
        call mlxf_meshgrid_op(results, mlxc_meshgrid, reversed, thin, 'mlx_meshgrid')
        if( size(results) /= n ) call mlxf_fail('mlx_meshgrid', 'one grid per array expected')
        allocate(grids(n))
        do i = 1, n
            grids(i) = results(n+1-i)
        end do
    end subroutine mlx_meshgrid

    ! the Bartlett (triangular) window of m points, float32
    module function mlx_bartlett( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
        call mlxf_window_op(r, mlxc_bartlett, m, 'mlx_bartlett')
    end function mlx_bartlett

    ! the Blackman window of m points, float32
    module function mlx_blackman( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
        call mlxf_window_op(r, mlxc_blackman, m, 'mlx_blackman')
    end function mlx_blackman

    ! the Hamming window of m points, float32
    module function mlx_hamming( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
        call mlxf_window_op(r, mlxc_hamming, m, 'mlx_hamming')
    end function mlx_hamming

    ! the Hann window of m points, float32
    module function mlx_hanning( m ) result(r)
        integer, intent(in) :: m
        type(mlx_array) :: r
        call mlxf_window_op(r, mlxc_hanning, m, 'mlx_hanning')
    end function mlx_hanning

end submodule mlxf_ops_create
