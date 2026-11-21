!@descr: the helpers of the C signature classes, weak scalars, and the elementwise operations + - * and exp
submodule (mlxf_array) mlxf_array_elementwise
use, intrinsic :: iso_c_binding, only: c_float, c_double
use mlxf_c_types,  only: MLXC_FLOAT64, MLXC_COMPLEX64
use mlxf_c_array,  only: mlxc_array_free, mlxc_array_new_float32, mlxc_array_new_float64, mlxc_array_new_complex, &
                         mlxc_array_dtype, mlxc_array_new
use mlxf_c_ops,    only: mlxc_add, mlxc_subtract, mlxc_multiply, mlxc_exp
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_error,    only: mlxf_check
use mlxf_device,   only: mlxf_require_device, mlxf_default_stream
implicit none

contains

    ! r = f(a) on the default device, for every int f(mlx_array* res, const mlx_array a, const mlx_stream s)
    module subroutine mlxf_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, ha
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha   = mlxf_handle(a, proc)
        res  = mlxc_array_new()
        s    = mlxf_default_stream(proc)
        ierr = f(res, ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_unary

    ! r = f(a, b) on the default device, for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! const mlx_stream s)
    module subroutine mlxf_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, ha, hb
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha   = mlxf_handle(a, proc)
        hb   = mlxf_handle(b, proc)
        res  = mlxc_array_new()
        s    = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_binary

    ! a Fortran scalar as a 0-d array of a's kind: weak, so it never changes the result's kind (float32
    ! with integer and boolean arrays)
    subroutine weak_scalar( r, a, x, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        real(real32),     intent(in)    :: x
        character(len=*), intent(in)    :: proc
        call mlxf_require_device(proc)
        select case( mlxc_array_dtype(mlxf_handle(a, proc)) )
            case( MLXC_FLOAT64 )
                call adopt(r, mlxc_array_new_float64(real(x, c_double)), proc)
            case( MLXC_COMPLEX64 )
                call adopt(r, mlxc_array_new_complex(real(x, c_float), 0._c_float), proc)
            case default
                call adopt(r, mlxc_array_new_float32(real(x, c_float)), proc)
        end select
    end subroutine weak_scalar

    module function add_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_add, lhs, rhs, 'operator(+)')
    end function add_aa

    module function add_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call weak_scalar(s, lhs, rhs, 'operator(+)')
        call mlxf_binary(r, mlxc_add, lhs, s, 'operator(+)')
    end function add_as

    module function add_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call weak_scalar(s, rhs, lhs, 'operator(+)')
        call mlxf_binary(r, mlxc_add, s, rhs, 'operator(+)')
    end function add_sa

    module function sub_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_subtract, lhs, rhs, 'operator(-)')
    end function sub_aa

    module function sub_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call weak_scalar(s, lhs, rhs, 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, lhs, s, 'operator(-)')
    end function sub_as

    module function sub_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call weak_scalar(s, rhs, lhs, 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, s, rhs, 'operator(-)')
    end function sub_sa

    module function mul_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_multiply, lhs, rhs, 'operator(*)')
    end function mul_aa

    module function mul_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call weak_scalar(s, lhs, rhs, 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, lhs, s, 'operator(*)')
    end function mul_as

    module function mul_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call weak_scalar(s, rhs, lhs, 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, s, rhs, 'operator(*)')
    end function mul_sa

    module function exp_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_exp, a, 'exp')
    end function exp_array

end submodule mlxf_array_elementwise
