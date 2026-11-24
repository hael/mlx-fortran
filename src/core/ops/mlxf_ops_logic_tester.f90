!@descr: table-driven two-device checks of the predicates, closeness and equality tests and the integer and bitwise functions
! Boolean and integer results are exact. The predicates run on IEEE special values against ieee_arithmetic,
! the bitwise functions on seeded int32 and int64 inputs against Fortran's intrinsics; isclose's defaults and
! the arithmetic right shift are asserted by name.
module mlxf_ops_logic_tester
use, intrinsic :: iso_c_binding,   only: c_bool
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_is_finite, ieee_class, ieee_value, ieee_quiet_nan, &
                                         ieee_positive_inf, ieee_negative_inf, operator(==)
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                           MLX_DTYPES, mlx_astype, mlx_isnan, mlx_isinf, mlx_isfinite, mlx_isposinf, mlx_isneginf, &
                           mlx_isclose, mlx_allclose, mlx_array_equal, iand, ior, ieor, not, shiftl, mlx_right_shift
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, set_fixed_seed
use mlxf_test_defs,  only: ELEM_NPOINTS, ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED
implicit none
private
public :: run_all_ops_logic_tests

abstract interface
    function array_unary( a ) result(r)
        import :: mlx_array
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function array_unary
    function real_predicate( x ) result(p)
        import :: real64
        real(real64), intent(in) :: x
        logical :: p
    end function real_predicate
    function array_binary( a, b ) result(r)
        import :: mlx_array
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
    end function array_binary
    function integer_binary( x, y ) result(z)
        import :: int64
        integer(int64), intent(in) :: x, y
        integer(int64) :: z
    end function integer_binary
end interface

! a predicate and its oracle
type :: predicate_case
    character(len=24)                          :: label = ''
    procedure(array_unary),    pointer, nopass :: f      => null()
    procedure(real_predicate), pointer, nopass :: oracle => null()
end type predicate_case

! an integer function of two operands (the second ignored by a unary one), its oracle and the operands'
! ranges [lo, hi]
type :: integer_case
    character(len=24)                          :: label = ''
    procedure(array_binary),   pointer, nopass :: f      => null()
    procedure(integer_binary), pointer, nopass :: oracle => null()
    integer(int64)                             :: lo(2) = 0_int64, hi(2) = 0_int64
end type integer_case

contains

    subroutine run_all_ops_logic_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops_logic tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_predicate_family
            call test_closeness_and_equality
            call test_integer_family
            call test_integer_conventions
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_logic_tests

    ! every predicate on the IEEE special values and ordinary numbers: float32, and float64 on the CPU
    subroutine test_predicate_family
        type(predicate_case) :: cases(5)
        type(mlx_array)      :: a, r
        real(real64)         :: x(10)
        real(real32)         :: x32(10)
        logical(c_bool)      :: got(10)
        logical              :: want(10)
        integer              :: c, j
        write(*,'(a)') 'test_predicate_family'
        cases(1) = predicate_case('mlx_isnan', w_isnan, o_isnan)
        cases(2) = predicate_case('mlx_isinf', w_isinf, o_isinf)
        cases(3) = predicate_case('mlx_isfinite', w_isfinite, o_isfinite)
        cases(4) = predicate_case('mlx_isposinf', w_isposinf, o_isposinf)
        cases(5) = predicate_case('mlx_isneginf', w_isneginf, o_isneginf)
        x(1) = ieee_value(x(1), ieee_quiet_nan)
        x(2) = ieee_value(x(2), ieee_positive_inf)
        x(3) = ieee_value(x(3), ieee_negative_inf)
        x(4:10) = [0._real64, -0._real64, 1.5_real64, -2.5_real64, real(huge(1._real32), real64), &
            &-real(huge(1._real32), real64), real(tiny(1._real32), real64)]
        x32 = real(x, real32)
        do c = 1, size(cases)
            do j = 1, size(x)
                want(j) = cases(c)%oracle(x(j))
            end do
            a = mlx_from(x32)
            r = cases(c)%f(a)
            call assert_int(MLX_DTYPES%bool, r%kind(), trim(cases(c)%label)//' returns bool')
            call mlx_to(got, r)
            call assert_true(all(got .eqv. want), trim(cases(c)%label)//' on float32 special values')
            if( mlx_default_device() == MLX_DEVICES%cpu )then
                a = mlx_from(x)
                r = cases(c)%f(a)
                call mlx_to(got, r)
                call assert_true(all(got .eqv. want), trim(cases(c)%label)//' on float64 special values')
            endif
        end do
    end subroutine test_predicate_family

    ! isclose's defaults (rtol 1e-5, atol 1e-8, NaNs unequal), its options, allclose, array_equal, .eqv., .neqv.
    subroutine test_closeness_and_equality
        type(mlx_array) :: a, b, r, p, q
        logical(c_bool) :: got(6), one, tt(4)
        real(real32)    :: nan
        write(*,'(a)') 'test_closeness_and_equality'
        nan = ieee_value(nan, ieee_quiet_nan)
        a = mlx_from([1._real32, 1._real32, 1._real32, 0._real32, 0._real32, nan])
        b = mlx_from([1._real32, 1.000009_real32, 1.000012_real32, 5.e-9_real32, 2.e-8_real32, nan])
        r = mlx_isclose(a, b)
        call assert_int(MLX_DTYPES%bool, r%kind(), 'mlx_isclose returns bool')
        call mlx_to(got, r)
        call assert_true(all(got .eqv. [.true., .true., .false., .true., .false., .false.]), &
            &'mlx_isclose defaults: rtol 1e-5 relative to b, atol 1e-8, NaNs unequal')
        r = mlx_isclose(a, b, equal_nan=.true.)
        call mlx_to(got, r)
        call assert_true(logical(got(6)), 'mlx_isclose(equal_nan=.true.) takes NaNs as equal')
        r = mlx_isclose(a, b, rtol=1.e-4_real64, atol=1.e-7_real64)
        call mlx_to(got, r)
        call assert_true(all(got .eqv. [.true., .true., .true., .true., .true., .false.]), &
            &'mlx_isclose with rtol and atol given')
        r = mlx_allclose(a, b)
        call assert_int(0, r%ndim(), 'mlx_allclose is rank 0')
        call mlx_to(one, r)
        call assert_false_c(one, 'mlx_allclose is false when one element is not close')
        r = mlx_allclose(a, b, rtol=1.e-4_real64, atol=1.e-7_real64, equal_nan=.true.)
        call mlx_to(one, r)
        call assert_true(logical(one), 'mlx_allclose is true when every element is close')
        b = mlx_from([1, 1, 1, 0, 0, 0])
        a = mlx_from([1._real32, 1._real32, 1._real32, 0._real32, 0._real32, 0._real32])
        r = mlx_array_equal(a, b)
        call assert_int(0, r%ndim(), 'mlx_array_equal is rank 0')
        call mlx_to(one, r)
        call assert_true(logical(one), 'mlx_array_equal compares values across dtypes')
        b = mlx_from(reshape([1._real32, 1._real32, 1._real32, 0._real32, 0._real32, 0._real32], [3, 2]))
        r = mlx_array_equal(a, b)
        call mlx_to(one, r)
        call assert_false_c(one, 'mlx_array_equal is false for the same values in another shape')
        a = mlx_from([1._real32, nan])
        r = mlx_array_equal(a, a)
        call mlx_to(one, r)
        call assert_false_c(one, 'mlx_array_equal takes NaNs as unequal by default')
        r = mlx_array_equal(a, a, equal_nan=.true.)
        call mlx_to(one, r)
        call assert_true(logical(one), 'mlx_array_equal(equal_nan=.true.) takes NaNs as equal')
        p = mlx_from([.true._c_bool, .true._c_bool, .false._c_bool, .false._c_bool])
        q = mlx_from([.true._c_bool, .false._c_bool, .true._c_bool, .false._c_bool])
        r = p .eqv. q
        call assert_int(MLX_DTYPES%bool, r%kind(), '.eqv. returns bool')
        call mlx_to(tt, r)
        call assert_true(all(tt .eqv. [.true., .false., .false., .true.]), '.eqv. is the truth table of equivalence')
        r = p .neqv. q
        call mlx_to(tt, r)
        call assert_true(all(tt .eqv. [.false., .true., .true., .false.]), '.neqv. is the truth table of exclusive or')
    end subroutine test_closeness_and_equality

    subroutine assert_false_c( x, msg )
        logical(c_bool),  intent(in) :: x
        character(len=*), intent(in) :: msg
        call assert_true(.not. logical(x), msg)
    end subroutine assert_false_c

    ! every integer function against Fortran's intrinsic on seeded int32 and int64 operands
    subroutine test_integer_family
        type(integer_case)   :: cases(6)
        type(mlx_array)      :: a, b, r
        integer, allocatable :: seeds(:)
        integer(int64)       :: x(ELEM_NPOINTS), y(ELEM_NPOINTS), want(ELEM_NPOINTS), got(ELEM_NPOINTS)
        integer(int32)       :: got32(ELEM_NPOINTS)
        integer              :: c, k, j
        write(*,'(a)') 'test_integer_family'
        cases(1) = integer_case('iand', w_iand, o_iand, [-2_int64**30, -2_int64**30], [2_int64**30, 2_int64**30])
        cases(2) = integer_case('ior', w_ior, o_ior, [-2_int64**30, -2_int64**30], [2_int64**30, 2_int64**30])
        cases(3) = integer_case('ieor', w_ieor, o_ieor, [-2_int64**30, -2_int64**30], [2_int64**30, 2_int64**30])
        cases(4) = integer_case('not', w_not, o_not, [-2_int64**30, 0_int64], [2_int64**30, 0_int64])
        cases(5) = integer_case('shiftl', w_shiftl, o_shiftl, [0_int64, 0_int64], [2_int64**20-1, 10_int64])
        cases(6) = integer_case('mlx_right_shift', w_right_shift, o_right_shift, [-2_int64**30, 0_int64], &
            &[2_int64**30, 30_int64])
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
        do k = 1, size(seeds)
            do c = 1, size(cases)
                call draw_integers(x, cases(c)%lo(1), cases(c)%hi(1), 1000*seeds(k)+300+c)
                call draw_integers(y, cases(c)%lo(2), cases(c)%hi(2), 1000*seeds(k)+400+c)
                do j = 1, size(x)
                    want(j) = cases(c)%oracle(x(j), y(j))
                end do
                a = mlx_from(int(x, int32))
                b = mlx_from(int(y, int32))
                r = cases(c)%f(a, b)
                call assert_int(MLX_DTYPES%int32, r%kind(), trim(cases(c)%label)//' keeps int32')
                call mlx_to(got32, r)
                call assert_true(all(int(got32, int64) == want), trim(cases(c)%label)//' on int32 operands')
                a = mlx_from(x)
                b = mlx_from(y)
                r = cases(c)%f(a, b)
                call assert_int(MLX_DTYPES%int64, r%kind(), trim(cases(c)%label)//' keeps int64')
                call mlx_to(got, r)
                call assert_true(all(got == want), trim(cases(c)%label)//' on int64 operands')
            end do
        end do
    end subroutine test_integer_family

    ! integer scalars on either side take the array's kind; the right shift is arithmetic (Fortran's shifta)
    subroutine test_integer_conventions
        type(mlx_array) :: a, r
        integer(int64)  :: x(4), got(4)
        integer(int32)  :: g32(4)
        write(*,'(a)') 'test_integer_conventions'
        x = [-8_int64, 5_int64, 1000_int64, -1_int64]
        a = mlx_from(x)
        r = iand(a, 255)
        call assert_int(MLX_DTYPES%int64, r%kind(), 'iand(a, integer) keeps int64')
        call mlx_to(got, r)
        call assert_true(all(got == iand(x, 255_int64)), 'iand(a, integer)')
        r = ior(16, a)
        call mlx_to(got, r)
        call assert_true(all(got == ior(16_int64, x)), 'ior(integer, a)')
        r = ieor(a, -1)
        call mlx_to(got, r)
        call assert_true(all(got == not(x)), 'ieor(a, -1) is not(a)')
        r = shiftl(a, 3)
        call mlx_to(got, r)
        call assert_true(all(got == shiftl(x, 3)), 'shiftl(a, integer)')
        r = mlx_right_shift(a, 2)
        call mlx_to(got, r)
        call assert_true(all(got == shifta(x, 2)), 'mlx_right_shift is arithmetic: the sign bit is copied in')
        a = mlx_from(int(x, int32))
        r = mlx_right_shift(a, 1)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_right_shift(a, integer) keeps int32')
        call mlx_to(g32, r)
        call assert_true(g32(1) == -4_int32, 'mlx_right_shift(-8, 1) is -4, unlike the logical shiftr')
        r = ieor(7, mlx_astype(a, MLX_DTYPES%int32))
        call mlx_to(g32, r)
        call assert_true(all(g32 == ieor(7_int32, int(x, int32))), 'ieor(integer, a)')
    end subroutine test_integer_conventions

    ! n integers of [lo, hi] from a fixed seed
    subroutine draw_integers( x, lo, hi, seed )
        integer(int64), intent(out) :: x(:)
        integer(int64), intent(in)  :: lo, hi
        integer,        intent(in)  :: seed
        real(real64) :: u(size(x))
        call set_fixed_seed(seed)
        call random_number(u)
        x = lo+min(hi-lo, int(real(hi-lo+1, real64)*u, int64))
    end subroutine draw_integers

    function w_isnan( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_isnan(a)
    end function w_isnan

    function w_isinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_isinf(a)
    end function w_isinf

    function w_isfinite( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_isfinite(a)
    end function w_isfinite

    function w_isposinf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_isposinf(a)
    end function w_isposinf

    function w_isneginf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_isneginf(a)
    end function w_isneginf

    logical function o_isnan( x )
        real(real64), intent(in) :: x
        o_isnan = ieee_is_nan(x)
    end function o_isnan

    logical function o_isinf( x )
        real(real64), intent(in) :: x
        o_isinf = .not. ieee_is_finite(x) .and. .not. ieee_is_nan(x)
    end function o_isinf

    logical function o_isfinite( x )
        real(real64), intent(in) :: x
        o_isfinite = ieee_is_finite(x)
    end function o_isfinite

    logical function o_isposinf( x )
        real(real64), intent(in) :: x
        o_isposinf = ieee_class(x) == ieee_positive_inf
    end function o_isposinf

    logical function o_isneginf( x )
        real(real64), intent(in) :: x
        o_isneginf = ieee_class(x) == ieee_negative_inf
    end function o_isneginf

    function w_iand( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = iand(a, b)
    end function w_iand

    function w_ior( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = ior(a, b)
    end function w_ior

    function w_ieor( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = ieor(a, b)
    end function w_ieor

    ! the bitwise complement; the second operand of the table's form is unused
    function w_not( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = not(a)
    end function w_not

    function w_shiftl( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = shiftl(a, b)
    end function w_shiftl

    function w_right_shift( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = mlx_right_shift(a, b)
    end function w_right_shift

    function o_iand( x, y ) result(z)
        integer(int64), intent(in) :: x, y
        integer(int64) :: z
        z = iand(x, y)
    end function o_iand

    function o_ior( x, y ) result(z)
        integer(int64), intent(in) :: x, y
        integer(int64) :: z
        z = ior(x, y)
    end function o_ior

    function o_ieor( x, y ) result(z)
        integer(int64), intent(in) :: x, y
        integer(int64) :: z
        z = ieor(x, y)
    end function o_ieor

    function o_not( x, y ) result(z)
        integer(int64), intent(in) :: x, y
        integer(int64) :: z
        z = not(x)
    end function o_not

    function o_shiftl( x, y ) result(z)
        integer(int64), intent(in) :: x, y
        integer(int64) :: z
        z = shiftl(x, int(y))
    end function o_shiftl

    function o_right_shift( x, y ) result(z)
        integer(int64), intent(in) :: x, y
        integer(int64) :: z
        z = shifta(x, int(y))
    end function o_right_shift

end module mlxf_ops_logic_tester
