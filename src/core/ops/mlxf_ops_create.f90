!@descr: constructors: arrays of ones or of a fill value, and arrays shaped like another
! A scalar fill value becomes a 0-d array of the result's kind (float64 only for a float64 result), so that
! building it never needs the GPU to convert from float64.
submodule(mlxf_ops) mlxf_ops_create
use mlxf_c_ops,  only: mlxc_full, mlxc_full_like, mlxc_ones, mlxc_ones_like, mlxc_ones_like_dtype, mlxc_zeros_like, &
                       mlxc_zeros_like_dtype
use mlxf_defs,   only: MLX_DTYPES, mlxf_shape_spec
use mlxf_array,  only: mlx_from, mlxf_binary_int_op, mlxf_full_op, mlxf_dtype_op, mlxf_unary, mlxf_zeros_op
use mlxf_device, only: mlxf_enter
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

end submodule mlxf_ops_create
