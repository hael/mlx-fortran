!@descr: predicates, closeness and equality tests, and the integer and bitwise functions
! Predicates and tests return boolean arrays; the bitwise functions take integer arrays, and an integer scalar
! operand takes the array's integer kind.
submodule(mlxf_ops) mlxf_ops_logic
use mlxf_c_ops,  only: mlxc_allclose, mlxc_array_equal, mlxc_bitwise_and, mlxc_bitwise_invert, mlxc_bitwise_or, &
                       mlxc_bitwise_xor, mlxc_isclose, mlxc_isfinite, mlxc_isinf, mlxc_isnan, mlxc_isneginf, &
                       mlxc_isposinf, mlxc_left_shift, mlxc_right_shift
use mlxf_defs,   only: mlxf_close_spec
use mlxf_array,  only: mlx_from, mlxf_binary, mlxf_close_op, mlxf_compare_op, mlxf_unary
use mlxf_device, only: mlxf_enter
implicit none

contains

    ! true where a is NaN
    module function mlx_isnan( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isnan, a, 'mlx_isnan')
    end function mlx_isnan

    ! true where a is infinite, of either sign
    module function mlx_isinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isinf, a, 'mlx_isinf')
    end function mlx_isinf

    ! true where a is neither infinite nor NaN
    module function mlx_isfinite( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isfinite, a, 'mlx_isfinite')
    end function mlx_isfinite

    ! true where a is +Inf
    module function mlx_isposinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isposinf, a, 'mlx_isposinf')
    end function mlx_isposinf

    ! true where a is -Inf
    module function mlx_isneginf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isneginf, a, 'mlx_isneginf')
    end function mlx_isneginf

    ! |a - b| <= atol + rtol |b| elementwise (defaults rtol = 1e-5, atol = 1e-8); NaNs are
    ! unequal unless equal_nan
    module function mlx_isclose( a, b, rtol, atol, equal_nan ) result(r)
        type(mlx_array), intent(in)           :: a, b
        real(real64),    optional, intent(in) :: rtol, atol
        logical,         optional, intent(in) :: equal_nan
        type(mlx_array)       :: r
        type(mlxf_close_spec) :: spec
        call mlxf_enter('mlx_isclose')
        if( present(rtol) ) spec%rtol = rtol
        if( present(atol) ) spec%atol = atol
        if( present(equal_nan) ) spec%equal_nan = equal_nan
        call mlxf_close_op(r, mlxc_isclose, [a, b], spec, 'mlx_isclose')
    end function mlx_isclose

    ! whether mlx_isclose holds everywhere: a rank-0 boolean array
    module function mlx_allclose( a, b, rtol, atol, equal_nan ) result(r)
        type(mlx_array), intent(in)           :: a, b
        real(real64),    optional, intent(in) :: rtol, atol
        logical,         optional, intent(in) :: equal_nan
        type(mlx_array)       :: r
        type(mlxf_close_spec) :: spec
        call mlxf_enter('mlx_allclose')
        if( present(rtol) ) spec%rtol = rtol
        if( present(atol) ) spec%atol = atol
        if( present(equal_nan) ) spec%equal_nan = equal_nan
        call mlxf_close_op(r, mlxc_allclose, [a, b], spec, 'mlx_allclose')
    end function mlx_allclose

    ! whether a and b have the same shape and values (of any dtypes): a rank-0 boolean array
    module function mlx_array_equal( a, b, equal_nan ) result(r)
        type(mlx_array), intent(in)           :: a, b
        logical,         optional, intent(in) :: equal_nan
        type(mlx_array) :: r
        logical         :: nan_equal
        call mlxf_enter('mlx_array_equal')
        nan_equal = .false.
        if( present(equal_nan) ) nan_equal = equal_nan
        call mlxf_compare_op(r, mlxc_array_equal, [a, b], nan_equal, 'mlx_array_equal')
    end function mlx_array_equal

    ! the bitwise and, or and exclusive or of integer arrays, as Fortran's iand, ior and ieor
    module function iand_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_bitwise_and, i, j, 'iand')
    end function iand_array

    module function iand_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('iand')
        s = integer_scalar(i, j)
        call mlxf_binary(r, mlxc_bitwise_and, i, s, 'iand')
    end function iand_ai

    module function iand_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('iand')
        s = integer_scalar(j, i)
        call mlxf_binary(r, mlxc_bitwise_and, s, j, 'iand')
    end function iand_ia

    ! bitwise or
    module function ior_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_bitwise_or, i, j, 'ior')
    end function ior_array

    module function ior_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ior')
        s = integer_scalar(i, j)
        call mlxf_binary(r, mlxc_bitwise_or, i, s, 'ior')
    end function ior_ai

    module function ior_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ior')
        s = integer_scalar(j, i)
        call mlxf_binary(r, mlxc_bitwise_or, s, j, 'ior')
    end function ior_ia

    ! bitwise exclusive or
    module function ieor_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_bitwise_xor, i, j, 'ieor')
    end function ieor_array

    module function ieor_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ieor')
        s = integer_scalar(i, j)
        call mlxf_binary(r, mlxc_bitwise_xor, i, s, 'ieor')
    end function ieor_ai

    module function ieor_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ieor')
        s = integer_scalar(j, i)
        call mlxf_binary(r, mlxc_bitwise_xor, s, j, 'ieor')
    end function ieor_ia

    ! the bitwise complement, as Fortran's not
    module function bitwise_not_array( i ) result(r)
        type(mlx_array), intent(in) :: i
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_bitwise_invert, i, 'not')
    end function bitwise_not_array

    ! i shifted left by shift bits, zeros shifted in, as Fortran's shiftl
    module function shiftl_array( i, shift ) result(r)
        type(mlx_array), intent(in) :: i, shift
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_left_shift, i, shift, 'shiftl')
    end function shiftl_array

    module function shiftl_ai( i, shift ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: shift
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('shiftl')
        s = integer_scalar(i, shift)
        call mlxf_binary(r, mlxc_left_shift, i, s, 'shiftl')
    end function shiftl_ai

    ! i shifted right by shift bits: arithmetic (the sign bit copied in) on signed integers,
    ! as Fortran's shifta, unlike its logical shiftr
    module function right_shift_array( i, shift ) result(r)
        type(mlx_array), intent(in) :: i, shift
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_right_shift, i, shift, 'mlx_right_shift')
    end function right_shift_array

    module function right_shift_ai( i, shift ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: shift
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('mlx_right_shift')
        s = integer_scalar(i, shift)
        call mlxf_binary(r, mlxc_right_shift, i, s, 'mlx_right_shift')
    end function right_shift_ai

    ! a Fortran integer as a 0-d array of a's kind, so that it never changes the kind of the result
    function integer_scalar( a, x ) result(s)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: x
        type(mlx_array) :: s
        s = mlx_astype(mlx_from(int(x, int32)), a%kind())
    end function integer_scalar

end submodule mlxf_ops_logic
