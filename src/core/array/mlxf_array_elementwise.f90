!@descr: unary and binary signature helpers, weak scalars, arithmetic, comparisons, boolean operators and exp
submodule (mlxf_array) mlxf_array_elementwise
use, intrinsic :: iso_c_binding, only: c_float
use mlxf_c_types,  only: MLXC_FLOAT64, MLXC_COMPLEX64
use mlxf_c_array,  only: mlxc_array_free, mlxc_array_new_float32, mlxc_array_new_float64, mlxc_array_new_complex, &
                         mlxc_array_dtype, mlxc_array_new
use mlxf_c_ops,    only: mlxc_add, mlxc_subtract, mlxc_multiply, mlxc_divide, mlxc_less, mlxc_less_equal, mlxc_greater, &
                         mlxc_greater_equal, mlxc_equal, mlxc_not_equal, mlxc_logical_and, mlxc_logical_or, &
                         mlxc_negative, mlxc_logical_not, mlxc_exp
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
    module subroutine mlxf_weak_scalar( r, a, x, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        real(real64),     intent(in)    :: x
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
    end subroutine mlxf_weak_scalar

    module function add_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_add, lhs, rhs, 'operator(+)')
    end function add_aa

    module function add_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(+)')
        call mlxf_binary(r, mlxc_add, lhs, s, 'operator(+)')
    end function add_as

    module function add_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(+)')
        call mlxf_binary(r, mlxc_add, s, rhs, 'operator(+)')
    end function add_sa

    ! the real64-scalar forms: the scalar is weak, takes the array's kind and never makes a float64 graph
    module function add_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(+)')
        call mlxf_binary(r, mlxc_add, lhs, s, 'operator(+)')
    end function add_ad

    module function add_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(+)')
        call mlxf_binary(r, mlxc_add, s, rhs, 'operator(+)')
    end function add_da

    module function sub_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_subtract, lhs, rhs, 'operator(-)')
    end function sub_aa

    module function sub_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, lhs, s, 'operator(-)')
    end function sub_as

    module function sub_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, s, rhs, 'operator(-)')
    end function sub_sa

    module function sub_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, lhs, s, 'operator(-)')
    end function sub_ad

    module function sub_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, s, rhs, 'operator(-)')
    end function sub_da

    module function mul_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_multiply, lhs, rhs, 'operator(*)')
    end function mul_aa

    module function mul_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, lhs, s, 'operator(*)')
    end function mul_as

    module function mul_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, s, rhs, 'operator(*)')
    end function mul_sa

    module function mul_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, lhs, s, 'operator(*)')
    end function mul_ad

    module function mul_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, s, rhs, 'operator(*)')
    end function mul_da

    ! division, with the scalar forms of + - *
    module function div_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_divide, lhs, rhs, 'operator(/)')
    end function div_aa

    module function div_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(/)')
        call mlxf_binary(r, mlxc_divide, lhs, s, 'operator(/)')
    end function div_as

    module function div_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(/)')
        call mlxf_binary(r, mlxc_divide, s, rhs, 'operator(/)')
    end function div_sa

    module function div_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(/)')
        call mlxf_binary(r, mlxc_divide, lhs, s, 'operator(/)')
    end function div_ad

    module function div_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(/)')
        call mlxf_binary(r, mlxc_divide, s, rhs, 'operator(/)')
    end function div_da

    ! comparisons give boolean arrays; a scalar operand is weak
    module function lt_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_less, lhs, rhs, 'operator(<)')
    end function lt_aa

    module function lt_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(<)')
        call mlxf_binary(r, mlxc_less, lhs, s, 'operator(<)')
    end function lt_as

    module function lt_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(<)')
        call mlxf_binary(r, mlxc_less, s, rhs, 'operator(<)')
    end function lt_sa

    module function lt_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(<)')
        call mlxf_binary(r, mlxc_less, lhs, s, 'operator(<)')
    end function lt_ad

    module function lt_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(<)')
        call mlxf_binary(r, mlxc_less, s, rhs, 'operator(<)')
    end function lt_da

    module function le_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_less_equal, lhs, rhs, 'operator(<=)')
    end function le_aa

    module function le_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(<=)')
        call mlxf_binary(r, mlxc_less_equal, lhs, s, 'operator(<=)')
    end function le_as

    module function le_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(<=)')
        call mlxf_binary(r, mlxc_less_equal, s, rhs, 'operator(<=)')
    end function le_sa

    module function le_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(<=)')
        call mlxf_binary(r, mlxc_less_equal, lhs, s, 'operator(<=)')
    end function le_ad

    module function le_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(<=)')
        call mlxf_binary(r, mlxc_less_equal, s, rhs, 'operator(<=)')
    end function le_da

    module function gt_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_greater, lhs, rhs, 'operator(>)')
    end function gt_aa

    module function gt_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(>)')
        call mlxf_binary(r, mlxc_greater, lhs, s, 'operator(>)')
    end function gt_as

    module function gt_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(>)')
        call mlxf_binary(r, mlxc_greater, s, rhs, 'operator(>)')
    end function gt_sa

    module function gt_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(>)')
        call mlxf_binary(r, mlxc_greater, lhs, s, 'operator(>)')
    end function gt_ad

    module function gt_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(>)')
        call mlxf_binary(r, mlxc_greater, s, rhs, 'operator(>)')
    end function gt_da

    module function ge_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_greater_equal, lhs, rhs, 'operator(>=)')
    end function ge_aa

    module function ge_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(>=)')
        call mlxf_binary(r, mlxc_greater_equal, lhs, s, 'operator(>=)')
    end function ge_as

    module function ge_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(>=)')
        call mlxf_binary(r, mlxc_greater_equal, s, rhs, 'operator(>=)')
    end function ge_sa

    module function ge_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(>=)')
        call mlxf_binary(r, mlxc_greater_equal, lhs, s, 'operator(>=)')
    end function ge_ad

    module function ge_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(>=)')
        call mlxf_binary(r, mlxc_greater_equal, s, rhs, 'operator(>=)')
    end function ge_da

    module function eq_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_equal, lhs, rhs, 'operator(==)')
    end function eq_aa

    module function eq_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(==)')
        call mlxf_binary(r, mlxc_equal, lhs, s, 'operator(==)')
    end function eq_as

    module function eq_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(==)')
        call mlxf_binary(r, mlxc_equal, s, rhs, 'operator(==)')
    end function eq_sa

    module function eq_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(==)')
        call mlxf_binary(r, mlxc_equal, lhs, s, 'operator(==)')
    end function eq_ad

    module function eq_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(==)')
        call mlxf_binary(r, mlxc_equal, s, rhs, 'operator(==)')
    end function eq_da

    module function ne_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_not_equal, lhs, rhs, 'operator(/=)')
    end function ne_aa

    module function ne_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(/=)')
        call mlxf_binary(r, mlxc_not_equal, lhs, s, 'operator(/=)')
    end function ne_as

    module function ne_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(/=)')
        call mlxf_binary(r, mlxc_not_equal, s, rhs, 'operator(/=)')
    end function ne_sa

    module function ne_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, lhs, real(rhs, real64), 'operator(/=)')
        call mlxf_binary(r, mlxc_not_equal, lhs, s, 'operator(/=)')
    end function ne_ad

    module function ne_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_weak_scalar(s, rhs, real(lhs, real64), 'operator(/=)')
        call mlxf_binary(r, mlxc_not_equal, s, rhs, 'operator(/=)')
    end function ne_da

    ! .and. and .or. of boolean arrays
    module function land_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_logical_and, lhs, rhs, 'operator(.and.)')
    end function land_aa

    module function lor_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_logical_or, lhs, rhs, 'operator(.or.)')
    end function lor_aa

    ! unary minus
    module function negate_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_negative, a, 'operator(-)')
    end function negate_array

    ! .not. of a boolean array
    module function not_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_logical_not, a, 'operator(.not.)')
    end function not_array

    module function exp_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_exp, a, 'exp')
    end function exp_array

end submodule mlxf_array_elementwise
