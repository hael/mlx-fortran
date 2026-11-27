!@descr: the operators of mlx_array: arithmetic, powers, comparisons, boolean operators, unary signs, and exp
submodule (mlxf_array) mlxf_array_elementwise
use mlxf_c_ops,  only: mlxc_add, mlxc_subtract, mlxc_multiply, mlxc_divide, mlxc_less, mlxc_less_equal, mlxc_greater, &
                       mlxc_greater_equal, mlxc_equal, mlxc_not_equal, mlxc_logical_and, mlxc_logical_or, &
                       mlxc_negative, mlxc_logical_not, mlxc_exp, mlxc_logical_xor, mlxc_positive, mlxc_power
use mlxf_calls,  only: mlxf_binary, mlxf_unary, mlxf_weak_scalar, mlxf_integer_scalar
use mlxf_device, only: mlxf_enter
implicit none

contains

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function add_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(+)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(+)')
        call mlxf_binary(r, mlxc_add, lhs, s, 'operator(+)')
    end function add_ai

    module function add_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(+)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(+)')
        call mlxf_binary(r, mlxc_add, s, rhs, 'operator(+)')
    end function add_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function sub_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(-)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, lhs, s, 'operator(-)')
    end function sub_ai

    module function sub_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(-)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(-)')
        call mlxf_binary(r, mlxc_subtract, s, rhs, 'operator(-)')
    end function sub_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function mul_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(*)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, lhs, s, 'operator(*)')
    end function mul_ai

    module function mul_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(*)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(*)')
        call mlxf_binary(r, mlxc_multiply, s, rhs, 'operator(*)')
    end function mul_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function div_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(/)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(/)')
        call mlxf_binary(r, mlxc_divide, lhs, s, 'operator(/)')
    end function div_ai

    module function div_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(/)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(/)')
        call mlxf_binary(r, mlxc_divide, s, rhs, 'operator(/)')
    end function div_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function lt_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(<)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(<)')
        call mlxf_binary(r, mlxc_less, lhs, s, 'operator(<)')
    end function lt_ai

    module function lt_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(<)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(<)')
        call mlxf_binary(r, mlxc_less, s, rhs, 'operator(<)')
    end function lt_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function le_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(<=)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(<=)')
        call mlxf_binary(r, mlxc_less_equal, lhs, s, 'operator(<=)')
    end function le_ai

    module function le_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(<=)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(<=)')
        call mlxf_binary(r, mlxc_less_equal, s, rhs, 'operator(<=)')
    end function le_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function gt_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(>)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(>)')
        call mlxf_binary(r, mlxc_greater, lhs, s, 'operator(>)')
    end function gt_ai

    module function gt_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(>)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(>)')
        call mlxf_binary(r, mlxc_greater, s, rhs, 'operator(>)')
    end function gt_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function ge_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(>=)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(>=)')
        call mlxf_binary(r, mlxc_greater_equal, lhs, s, 'operator(>=)')
    end function ge_ai

    module function ge_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(>=)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(>=)')
        call mlxf_binary(r, mlxc_greater_equal, s, rhs, 'operator(>=)')
    end function ge_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function eq_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(==)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(==)')
        call mlxf_binary(r, mlxc_equal, lhs, s, 'operator(==)')
    end function eq_ai

    module function eq_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(==)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(==)')
        call mlxf_binary(r, mlxc_equal, s, rhs, 'operator(==)')
    end function eq_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function ne_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(/=)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(/=)')
        call mlxf_binary(r, mlxc_not_equal, lhs, s, 'operator(/=)')
    end function ne_ai

    module function ne_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(/=)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(/=)')
        call mlxf_binary(r, mlxc_not_equal, s, rhs, 'operator(/=)')
    end function ne_ia

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

    ! a default-integer scalar: exact in an integer array's kind (out of range, a stop), int32 with booleans, weak
    ! otherwise (mlxf_integer_scalar)
    module function pow_ai( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        integer,          intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(**)')
        call mlxf_integer_scalar(s, lhs, rhs, 'operator(**)')
        call mlxf_binary(r, mlxc_power, lhs, s, 'operator(**)')
    end function pow_ai

    module function pow_ia( lhs, rhs ) result(r)
        integer,          intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r, s
        call mlxf_enter('operator(**)')
        call mlxf_integer_scalar(s, rhs, lhs, 'operator(**)')
        call mlxf_binary(r, mlxc_power, s, rhs, 'operator(**)')
    end function pow_ia

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

end submodule mlxf_array_elementwise
