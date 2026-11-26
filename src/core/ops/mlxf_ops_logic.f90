!@descr: predicates, closeness and equality tests, and the integer and bitwise functions
! Predicates and tests return boolean arrays; the bitwise functions take integer arrays, and an integer scalar
! operand takes the array's integer kind.
module mlxf_ops_logic
use, intrinsic :: iso_c_binding,   only: c_bool, c_int
use, intrinsic :: iso_fortran_env, only: real64, int32
use mlxf_c_array,         only: mlxc_array_new, mlxc_array_free
use mlxf_c_ops,           only: mlxc_allclose, mlxc_array_equal, mlxc_bitwise_and, mlxc_bitwise_invert, &
                                mlxc_bitwise_or, mlxc_bitwise_xor, mlxc_isclose, mlxc_isfinite, mlxc_isinf, mlxc_isnan, &
                                mlxc_isneginf, mlxc_isposinf, mlxc_left_shift, mlxc_right_shift
use mlxf_c_signatures,    only: mlxc_close_op, mlxc_compare_op
use mlxf_c_stream,        only: mlxc_stream_free
use mlxf_c_types,         only: mlxc_array, mlxc_stream
use mlxf_defs,            only: mlxf_close_spec
use mlxf_error,           only: mlxf_check
use mlxf_device,          only: mlxf_enter, mlxf_require_device, mlxf_default_stream
use mlxf_array,           only: mlx_array, mlxf_handle, mlxf_adopt
use mlxf_ops_elementwise, only: mlx_astype
use mlxf_calls,           only: mlxf_binary, mlxf_unary
use mlxf_transfer,        only: mlx_from
implicit none

public :: mlx_isnan, mlx_isinf, mlx_isfinite, mlx_isposinf, mlx_isneginf, mlx_isclose, mlx_allclose, mlx_array_equal, &
    &iand, ior, ieor, not, shiftl, mlx_right_shift
private

interface iand
    module procedure iand_array, iand_ai, iand_ia
end interface iand

interface ior
    module procedure ior_array, ior_ai, ior_ia
end interface ior

interface ieor
    module procedure ieor_array, ieor_ai, ieor_ia
end interface ieor

interface not
    module procedure bitwise_not_array
end interface not

interface shiftl
    module procedure shiftl_array, shiftl_ai
end interface shiftl

interface mlx_right_shift
    module procedure right_shift_array, right_shift_ai
end interface mlx_right_shift

contains

    ! true where a is NaN
    function mlx_isnan( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isnan, a, 'mlx_isnan')
    end function mlx_isnan

    ! true where a is infinite, of either sign
    function mlx_isinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isinf, a, 'mlx_isinf')
    end function mlx_isinf

    ! true where a is neither infinite nor NaN
    function mlx_isfinite( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isfinite, a, 'mlx_isfinite')
    end function mlx_isfinite

    ! true where a is +Inf
    function mlx_isposinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isposinf, a, 'mlx_isposinf')
    end function mlx_isposinf

    ! true where a is -Inf
    function mlx_isneginf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_isneginf, a, 'mlx_isneginf')
    end function mlx_isneginf

    ! |a - b| <= atol + rtol |b| elementwise (defaults rtol = 1e-5, atol = 1e-8); NaNs are
    ! unequal unless equal_nan
    function mlx_isclose( a, b, rtol, atol, equal_nan ) result(r)
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
    function mlx_allclose( a, b, rtol, atol, equal_nan ) result(r)
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
    function mlx_array_equal( a, b, equal_nan ) result(r)
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
    function iand_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_bitwise_and, i, j, 'iand')
    end function iand_array

    function iand_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('iand')
        s = integer_scalar(i, j)
        call mlxf_binary(r, mlxc_bitwise_and, i, s, 'iand')
    end function iand_ai

    function iand_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('iand')
        s = integer_scalar(j, i)
        call mlxf_binary(r, mlxc_bitwise_and, s, j, 'iand')
    end function iand_ia

    ! bitwise or
    function ior_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_bitwise_or, i, j, 'ior')
    end function ior_array

    function ior_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ior')
        s = integer_scalar(i, j)
        call mlxf_binary(r, mlxc_bitwise_or, i, s, 'ior')
    end function ior_ai

    function ior_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ior')
        s = integer_scalar(j, i)
        call mlxf_binary(r, mlxc_bitwise_or, s, j, 'ior')
    end function ior_ia

    ! bitwise exclusive or
    function ieor_array( i, j ) result(r)
        type(mlx_array), intent(in) :: i, j
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_bitwise_xor, i, j, 'ieor')
    end function ieor_array

    function ieor_ai( i, j ) result(r)
        type(mlx_array), intent(in) :: i
        integer,         intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ieor')
        s = integer_scalar(i, j)
        call mlxf_binary(r, mlxc_bitwise_xor, i, s, 'ieor')
    end function ieor_ai

    function ieor_ia( i, j ) result(r)
        integer,         intent(in) :: i
        type(mlx_array), intent(in) :: j
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_enter('ieor')
        s = integer_scalar(j, i)
        call mlxf_binary(r, mlxc_bitwise_xor, s, j, 'ieor')
    end function ieor_ia

    ! the bitwise complement, as Fortran's not
    function bitwise_not_array( i ) result(r)
        type(mlx_array), intent(in) :: i
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_bitwise_invert, i, 'not')
    end function bitwise_not_array

    ! i shifted left by shift bits, zeros shifted in, as Fortran's shiftl
    function shiftl_array( i, shift ) result(r)
        type(mlx_array), intent(in) :: i, shift
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_left_shift, i, shift, 'shiftl')
    end function shiftl_array

    function shiftl_ai( i, shift ) result(r)
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
    function right_shift_array( i, shift ) result(r)
        type(mlx_array), intent(in) :: i, shift
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_right_shift, i, shift, 'mlx_right_shift')
    end function right_shift_array

    function right_shift_ai( i, shift ) result(r)
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

    ! r = f(a(1), a(2)) with the tolerances of option, for every int f(mlx_array* res, const mlx_array a,
    ! const mlx_array b, double rtol, double atol, bool equal_nan, const mlx_stream s)
    subroutine mlxf_close_op( r, f, a, option, proc )
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
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_close_op

    ! r = f(a(1), a(2)) with NaNs equal when option holds, for every int f(mlx_array* res, const mlx_array a,
    ! const mlx_array b, bool equal_nan, const mlx_stream s)
    subroutine mlxf_compare_op( r, f, a, option, proc )
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
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_compare_op

end module mlxf_ops_logic
