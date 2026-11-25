!@descr: table-driven two-device checks of the elementwise arithmetic and transcendental functions
! Each function runs on seeded inputs of its domain against a plain Fortran real64 oracle: float32 on every
! device, float64 on the CPU, judged by the frozen tolerances of mlxf_test_defs (an error relative to
! max(1, |reference|)). The conventions are asserted by name: modulo's sign, half to even, weak scalars.
module mlxf_ops_math_tester
use, intrinsic :: iso_fortran_env, only: int32, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_quiet_nan, ieee_positive_inf, ieee_negative_inf
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                            MLX_DTYPES, abs, sin, cos, tan, sinh, cosh, tanh, log, log10, erf, asin, acos, atan, asinh, &
                            acosh, atanh, floor, ceiling, aint, mlx_round, mlx_sign, mlx_sigmoid, mlx_square, &
                            mlx_reciprocal, mlx_rsqrt, mlx_expm1, mlx_log1p, mlx_log2, mlx_erfinv, mlx_degrees, &
                            mlx_radians, mlx_stop_gradient, mlx_copy, atan2, modulo, min, max, mlx_logaddexp, &
                            mlx_floor_divide, mlx_divmod, mlx_clip, mlx_nan_to_num, mlx_astype
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name, set_fixed_seed, shaped_error
use mlxf_test_defs,   only: ELEM_NPOINTS, ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED, ELEM_TOLERANCES, ELEM_CEILING, &
                            ELEM_GPU_EXPM1, elem_tolerance
use mlxf_test_reduce, only: nan_maxval
implicit none
private
public :: run_all_ops_math_tests

abstract interface
    function array_unary( a ) result(r)
        import :: mlx_array
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function array_unary
    function real_unary( x ) result(y)
        import :: real64
        real(real64), intent(in) :: x
        real(real64) :: y
    end function real_unary
    function array_binary( a, b ) result(r)
        import :: mlx_array
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
    end function array_binary
    function real_binary( x, y ) result(z)
        import :: real64
        real(real64), intent(in) :: x, y
        real(real64) :: z
    end function real_binary
end interface

! a unary function, its oracle and its input domain [lo, hi]
type :: unary_case
    character(len=32)                         :: label = ''
    character(len=24)                         :: name  = ''
    procedure(array_unary), pointer, nopass   :: f      => null()
    procedure(real_unary),  pointer, nopass   :: oracle => null()
    real(real64)                              :: lo = 0._real64, hi = 0._real64
end type unary_case

! a binary function, its oracle and the domains of its operands; integral inputs are whole numbers, and a
! signed second operand alternates its sign
type :: binary_case
    character(len=32)                         :: label = ''
    character(len=24)                         :: name  = ''
    procedure(array_binary), pointer, nopass  :: f      => null()
    procedure(real_binary),  pointer, nopass  :: oracle => null()
    real(real64)                              :: lo(2) = 0._real64, hi(2) = 0._real64
    logical                                   :: integral = .false., signed = .false.
end type binary_case

contains

    subroutine run_all_ops_math_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops_math tests ****'
        call assert_true(all(ELEM_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_unary_family
            call test_binary_family
            call test_weak_scalars
            call test_math_conventions
            call test_error_reductions
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_math_tests

    ! the seeds every family runs: the calibration seed, then the judged ones
    function family_seeds() result(seeds)
        integer, allocatable :: seeds(:)
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
    end function family_seeds

    ! the frozen tolerances of a function on the default device (zero, failing every check, when it has none);
    ! the GPU's expm1, an upstream defect, has its own float32 bound
    function tolerance_of( name ) result(t)
        character(len=*), intent(in) :: name
        type(elem_tolerance) :: t
        integer              :: k
        t = elem_tolerance(name, 0._real64, 0._real64)
        do k = 1, size(ELEM_TOLERANCES)
            if( trim(ELEM_TOLERANCES(k)%name) == trim(name) ) t = ELEM_TOLERANCES(k)
        end do
        if( trim(name) == 'mlx_expm1' )then
            if( mlx_default_device() == MLX_DEVICES%gpu ) t%f32 = ELEM_GPU_EXPM1
        endif
    end function tolerance_of

    ! n points of [lo, hi] from a fixed seed, rounded once to float32 (whole numbers when integral)
    subroutine draw( x, lo, hi, seed, integral )
        real(real64), intent(out) :: x(:)
        real(real64), intent(in)  :: lo, hi
        integer,      intent(in)  :: seed
        logical,      intent(in)  :: integral
        real(real64) :: u(size(x))
        call set_fixed_seed(seed)
        call random_number(u)
        x = lo+(hi-lo)*u
        if( integral ) x = anint(x)
        x = real(real(x, real32), real64)
    end subroutine draw

    ! the largest error of r relative to max(1, |ref|), read back in r's kind; NaN where ref is finite is huge
    function rel_error( r, ref ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref(:)
        real(real64) :: err
        real(real32) :: y32(size(ref))
        real(real64) :: y(size(ref))
        if( r%kind() == MLX_DTYPES%float64 )then
            call mlx_to(y, r)
        else
            call mlx_to(y32, r)
            y = real(y32, real64)
        endif
        if( any(ieee_is_nan(y)) )then
            err = huge(1._real64)
        else
            err = nan_maxval(abs(y-ref)/max(1._real64, abs(ref)))
        endif
    end function rel_error

    ! one measured error against its tolerance, printed in float32 epsilons for the calibration record
    subroutine judge( err, tol, label, dtype, seed )
        real(real64),     intent(in) :: err, tol
        character(len=*), intent(in) :: label, dtype
        integer,          intent(in) :: seed
        character(len=160) :: line
        write(line,'(A,I0,A,ES16.9,A,F8.3,A)') '    error '//trim(label)//' '//device_name(mlx_default_device())// &
            &' '//dtype//' seed=', seed, ': ', err, ' (', err/real(epsilon(1._real32), real64), ' eps32)'
        write(*,'(A)') trim(line)
        call assert_true(err <= tol, trim(label)//' '//dtype//' within its frozen tolerance on the '// &
            &device_name(mlx_default_device()))
    end subroutine judge

    ! every unary function against its oracle on each seed: float32, and float64 on the CPU
    subroutine test_unary_family
        type(unary_case), allocatable :: cases(:)
        type(elem_tolerance)          :: tol
        type(mlx_array)               :: a, r
        integer,          allocatable :: seeds(:)
        real(real64)                  :: x(ELEM_NPOINTS), ref(ELEM_NPOINTS)
        integer                       :: c, k, j
        write(*,'(a)') 'test_unary_family'
        call unary_table(cases)
        seeds = family_seeds()
        do k = 1, size(seeds)
            do c = 1, size(cases)
                tol = tolerance_of(cases(c)%name)
                call draw(x, cases(c)%lo, cases(c)%hi, 1000*seeds(k)+c, .false.)
                do j = 1, size(x)
                    ref(j) = cases(c)%oracle(x(j))
                end do
                a = mlx_from(real(x, real32))
                r = cases(c)%f(a)
                call assert_int(MLX_DTYPES%float32, r%kind(), trim(cases(c)%label)//' keeps float32')
                call judge(rel_error(r, ref), tol%f32, cases(c)%label, 'float32', seeds(k))
                if( mlx_default_device() == MLX_DEVICES%cpu )then
                    a = mlx_from(x)
                    r = cases(c)%f(a)
                    call assert_int(MLX_DTYPES%float64, r%kind(), trim(cases(c)%label)//' keeps float64')
                    call judge(rel_error(r, ref), tol%f64, cases(c)%label, 'float64', seeds(k))
                endif
            end do
        end do
    end subroutine test_unary_family

    ! every binary function against its oracle on each seed: float32, and float64 on the CPU
    subroutine test_binary_family
        type(binary_case), allocatable :: cases(:)
        type(elem_tolerance)           :: tol
        type(mlx_array)                :: a, b, r
        integer,           allocatable :: seeds(:)
        real(real64)                   :: x(ELEM_NPOINTS), y(ELEM_NPOINTS), ref(ELEM_NPOINTS)
        integer                        :: c, k, j
        write(*,'(a)') 'test_binary_family'
        call binary_table(cases)
        seeds = family_seeds()
        do k = 1, size(seeds)
            do c = 1, size(cases)
                tol = tolerance_of(cases(c)%name)
                call draw(x, cases(c)%lo(1), cases(c)%hi(1), 1000*seeds(k)+100+c, cases(c)%integral)
                call draw(y, cases(c)%lo(2), cases(c)%hi(2), 1000*seeds(k)+200+c, cases(c)%integral)
                if( cases(c)%signed ) y(2::2) = -y(2::2)
                do j = 1, size(x)
                    ref(j) = cases(c)%oracle(x(j), y(j))
                end do
                a = mlx_from(real(x, real32))
                b = mlx_from(real(y, real32))
                r = cases(c)%f(a, b)
                call assert_int(MLX_DTYPES%float32, r%kind(), trim(cases(c)%label)//' keeps float32')
                call judge(rel_error(r, ref), tol%f32, cases(c)%label, 'float32', seeds(k))
                if( mlx_default_device() == MLX_DEVICES%cpu )then
                    a = mlx_from(x)
                    b = mlx_from(y)
                    r = cases(c)%f(a, b)
                    call assert_int(MLX_DTYPES%float64, r%kind(), trim(cases(c)%label)//' keeps float64')
                    call judge(rel_error(r, ref), tol%f64, cases(c)%label, 'float64', seeds(k))
                endif
            end do
        end do
    end subroutine test_binary_family

    ! a scalar on either side, real32 or real64, takes the array's kind and keeps its place in the argument order
    subroutine test_weak_scalars
        type(mlx_array) :: a, r
        real(real64)    :: x(8)
        integer         :: j
        write(*,'(a)') 'test_weak_scalars'
        x = [(real(real(0.7_real64*j-3.13_real64, real32), real64), j = 1, 8)]
        a = mlx_from(real(x, real32))
        r = atan2(a, 1.5_real32)
        call check_scalar(r, atan2(x, 1.5_real64), 'atan2', 'atan2(a, real32)')
        r = atan2(1.5_real64, a)
        call check_scalar(r, atan2(1.5_real64, x), 'atan2', 'atan2(real64, a)')
        r = modulo(a, -1.5_real32)
        call check_scalar(r, modulo(x, -1.5_real64), 'modulo', 'modulo(a, real32)')
        r = modulo(2.5_real64, a)
        call check_scalar(r, modulo(2.5_real64, x), 'modulo', 'modulo(real64, a)')
        r = min(a, 0.5_real32)
        call check_scalar(r, min(x, 0.5_real64), 'min', 'min(a, real32)')
        r = min(0.5_real64, a)
        call check_scalar(r, min(0.5_real64, x), 'min', 'min(real64, a)')
        r = abs(a)**1.5_real32
        call check_scalar(r, abs(x)**1.5_real64, 'operator(**)', 'a**real32')
        r = 2._real64**a
        call check_scalar(r, 2._real64**x, 'operator(**)', 'real64**a')
        r = mlx_logaddexp(a, 1._real32)
        call check_scalar(r, logaddexp_of_v(x, 1._real64), 'mlx_logaddexp', 'mlx_logaddexp(a, real32)')
        r = mlx_floor_divide(7._real64, a)
        call check_scalar(r, real(floor(7._real64/x), real64), 'mlx_floor_divide', 'mlx_floor_divide(real64, a)')
        call check_half_scalars(a, x, MLX_DTYPES%float16, 'float16')
        call check_true_division
        call check_half_scalars(a, x, MLX_DTYPES%bfloat16, 'bfloat16')
    end subroutine test_weak_scalars

    ! negative controls of the shared error reductions: one NaN among correct elements, at the first, a middle
    ! and the last position, makes the error +infinity, so no tolerance accepts it; so does an infinity
    subroutine test_error_reductions
        real(real32)     :: x(5)
        real(real64)     :: ref(5), one(5), e
        type(mlx_array)  :: a
        integer          :: k, pos(3)
        character(len=1) :: c
        write(*,'(a)') 'test_error_reductions'
        ref = [1._real64, 2._real64, 3._real64, 4._real64, 5._real64]
        one = 1._real64
        pos = [1, 3, 5]
        do k = 1, size(pos)
            write(c,'(i1)') pos(k)
            x = real(ref, real32)
            x(pos(k)) = ieee_value(0._real32, ieee_quiet_nan)
            a = mlx_from(x)
            e = shaped_error(a, ref, one)
            call assert_true(.not. (e <= 1._real64), 'shaped_error with a NaN at element '//c//' fails every tolerance')
            call assert_true(.not. (nan_maxval(abs(real(x, real64) - ref)) <= 1._real64), &
                &'nan_maxval with a NaN at element '//c//' fails every tolerance')
            x(pos(k)) = ieee_value(0._real32, ieee_positive_inf)
            a = mlx_from(x)
            e = shaped_error(a, ref, one)
            call assert_true(.not. (e <= 1._real64), 'shaped_error with an infinity at element '//c//' fails')
        end do
        x = real(ref, real32)
        a = mlx_from(x)
        e = shaped_error(a, ref, one)
        call assert_true(e <= tiny(1._real64), 'shaped_error of the exact values is 0')
        ref(2) = ieee_value(0._real64, ieee_quiet_nan)
        e = shaped_error(a, ref, one)
        call assert_true(.not. (e <= 1._real64), 'shaped_error refuses a reference that is not finite')
    end subroutine test_error_reductions

    ! operator(/) on two integer arrays is MLX's true division into float32, not Fortran's truncation
    subroutine check_true_division
        type(mlx_array) :: a, b, r
        real(real32)    :: y(3)
        a = mlx_from([7_int32, -7_int32, 6_int32])
        b = mlx_from([2_int32, 2_int32, 4_int32])
        r = a/b
        call assert_int(MLX_DTYPES%float32, r%kind(), 'int32 / int32 is float32 (true division)')
        call mlx_to(y, r)
        call assert_true(all(abs(y - [3.5_real32, -3.5_real32, 1.5_real32]) <= 1e-6_real32), &
            &'int32 / int32 divides exactly, without truncation')
    end subroutine check_true_division

    ! a scalar on either side of a half-precision array keeps the half kind (no promotion to float32), and
    ! the values are those of the half array; tol is a few units of the half kind's last place
    subroutine check_half_scalars( a, x, dtype, label )
        type(mlx_array),  intent(in) :: a
        real(real64),     intent(in) :: x(:)
        integer,          intent(in) :: dtype
        character(len=*), intent(in) :: label
        type(mlx_array) :: h, r, r32
        real(real32)    :: y(size(x))
        real(real64)    :: tol
        tol = merge(4._real64*2._real64**(-11), 4._real64*2._real64**(-8), dtype == MLX_DTYPES%float16)
        h = mlx_astype(a, dtype)
        r = h + 1._real32
        call assert_int(dtype, r%kind(), label//' + real32 scalar keeps '//label)
        r32 = mlx_astype(r, MLX_DTYPES%float32)
        call mlx_to(y, r32)
        call assert_true(nan_maxval(abs(real(y, real64) - (x + 1._real64))/max(1._real64, abs(x + 1._real64))) <= tol, &
            &label//' + real32 scalar has the half values')
        r = 2._real64*h
        call assert_int(dtype, r%kind(), 'real64 scalar * '//label//' keeps '//label)
        r = h/3._real32
        call assert_int(dtype, r%kind(), label//' / real32 scalar keeps '//label)
        r = 0.5_real64 - h
        call assert_int(dtype, r%kind(), 'real64 scalar - '//label//' keeps '//label)
        r = min(h, 0.5_real32)
        call assert_int(dtype, r%kind(), 'min('//label//', real32) keeps '//label)
        r = max(h, 0.1_real32)
        call assert_int(dtype, r%kind(), 'max('//label//', real32) keeps '//label)
    end subroutine check_half_scalars

    subroutine check_scalar( r, ref, name, label )
        type(mlx_array),  intent(in) :: r
        real(real64),     intent(in) :: ref(:)
        character(len=*), intent(in) :: name, label
        type(elem_tolerance) :: tol
        tol = tolerance_of(name)
        call assert_int(MLX_DTYPES%float32, r%kind(), label//': a weak scalar keeps float32')
        call assert_true(rel_error(r, ref) <= tol%f32, label//' against its oracle')
    end subroutine check_scalar

    ! the conventions by name: modulo takes the divisor's sign; mlx_round goes half to even; clip and
    ! nan_to_num; divmod is floor division with modulo's remainder
    subroutine test_math_conventions
        type(mlx_array) :: a, b, r, q, m
        real(real32)    :: y(5), z(4)
        integer(int32)  :: iy(4)
        real(real32)    :: nan, pinf, ninf
        write(*,'(a)') 'test_math_conventions'
        a = mlx_from([-7._real32, 7._real32, -7._real32, 7._real32])
        b = mlx_from([3._real32, -3._real32, -3._real32, 3._real32])
        r = modulo(a, b)
        call mlx_to(z, r)
        call assert_true(all(abs(z-[2._real32, -2._real32, -1._real32, 1._real32]) <= 0._real32), &
            &'modulo takes the sign of the divisor, as Fortran''s modulo (float32)')
        a = mlx_from([-7_int32, 7_int32, -7_int32, 7_int32])
        b = mlx_from([3_int32, -3_int32, -3_int32, 3_int32])
        r = modulo(a, b)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'modulo of int32 arrays is int32')
        call mlx_to(iy, r)
        call assert_true(all(iy == [2, -2, -1, 1]), 'modulo takes the sign of the divisor (int32)')
        call mlx_divmod(a, b, q, m)
        call mlx_to(iy, q)
        call assert_true(all(iy == [-3, -3, 2, 2]), 'mlx_divmod''s quotient is floor division (int32)')
        call mlx_to(iy, m)
        call assert_true(all(iy == [2, -2, -1, 1]), 'mlx_divmod''s remainder is modulo''s (int32)')
        a = mlx_from([0.5_real32, 1.5_real32, 2.5_real32, -0.5_real32, -1.5_real32])
        r = mlx_round(a)
        call mlx_to(y, r)
        call assert_true(all(abs(y-[0._real32, 2._real32, 2._real32, 0._real32, -2._real32]) <= 0._real32), &
            &'mlx_round rounds halves to even, unlike anint')
        a = mlx_from([0.25_real32, 0.75_real32, 1.25_real32, -0.25_real32])
        r = mlx_round(a, decimals=1)
        call mlx_to(z, r)
        call assert_true(all(abs(z-[0.2_real32, 0.8_real32, 1.2_real32, -0.2_real32]) <= epsilon(1._real32)), &
            &'mlx_round(a, decimals=1) rounds the tenths half to even')
        a = mlx_from([-3._real32, -1._real32, 0._real32, 2._real32, 5._real32])
        r = mlx_clip(a, -1.5_real32, 2.5_real32)
        call mlx_to(y, r)
        call assert_true(all(abs(y-[-1.5_real32, -1._real32, 0._real32, 2._real32, 2.5_real32]) <= 0._real32), &
            &'mlx_clip limits to [a_min, a_max] with real32 bounds')
        r = mlx_clip(a, -1.5_real64, 2.5_real64)
        call assert_int(MLX_DTYPES%float32, r%kind(), 'mlx_clip with real64 bounds keeps float32')
        call mlx_to(y, r)
        call assert_true(all(abs(y-[-1.5_real32, -1._real32, 0._real32, 2._real32, 2.5_real32]) <= 0._real32), &
            &'mlx_clip limits to [a_min, a_max] with real64 bounds')
        b = mlx_from([0._real32, 0._real32, 1._real32, 1._real32, 1._real32])
        q = mlx_from([1._real32, 1._real32, 1._real32, 1._real32, 4._real32])
        r = mlx_clip(a, b, q)
        call mlx_to(y, r)
        call assert_true(all(abs(y-[0._real32, 0._real32, 1._real32, 1._real32, 4._real32]) <= 0._real32), &
            &'mlx_clip limits elementwise with array bounds')
        nan = ieee_value(nan, ieee_quiet_nan)
        pinf = ieee_value(pinf, ieee_positive_inf)
        ninf = ieee_value(ninf, ieee_negative_inf)
        a = mlx_from([nan, pinf, ninf, 1.5_real32])
        r = mlx_nan_to_num(a)
        call mlx_to(z, r)
        call assert_true(all(abs(z-[0._real32, huge(1._real32), -huge(1._real32), 1.5_real32]) <= 0._real32), &
            &'mlx_nan_to_num defaults: NaN to 0, the infinities to the largest finite float32 values')
        r = mlx_nan_to_num(a, nan=-1._real32, posinf=9._real32, neginf=-9._real32)
        call mlx_to(z, r)
        call assert_true(all(abs(z-[-1._real32, 9._real32, -9._real32, 1.5_real32]) <= 0._real32), &
            &'mlx_nan_to_num replaces NaN and the infinities by the values given')
        r = mlx_sign(mlx_from([-2._real32, 0._real32, 3._real32]))
        call mlx_to(z(1:3), r)
        call assert_true(all(abs(z(1:3)-[-1._real32, 0._real32, 1._real32]) <= 0._real32), &
            &'mlx_sign is the signum of one argument')
    end subroutine test_math_conventions

    subroutine unary_table( cases )
        type(unary_case), allocatable, intent(out) :: cases(:)
        allocate(cases(34))
        cases(1) = unary_case('abs', 'abs', w_abs, o_abs, -20._real64, 20._real64)
        cases(2) = unary_case('sin', 'sin', w_sin, o_sin, -10._real64, 10._real64)
        cases(3) = unary_case('cos', 'cos', w_cos, o_cos, -10._real64, 10._real64)
        cases(4) = unary_case('tan', 'tan', w_tan, o_tan, -1.5_real64, 1.5_real64)
        cases(5) = unary_case('sinh', 'sinh', w_sinh, o_sinh, -10._real64, 10._real64)
        cases(6) = unary_case('cosh', 'cosh', w_cosh, o_cosh, -10._real64, 10._real64)
        cases(7) = unary_case('tanh', 'tanh', w_tanh, o_tanh, -10._real64, 10._real64)
        cases(8) = unary_case('log', 'log', w_log, o_log, 1.e-6_real64, 20._real64)
        cases(9) = unary_case('log10', 'log10', w_log10, o_log10, 1.e-6_real64, 20._real64)
        cases(10) = unary_case('erf', 'erf', w_erf, o_erf, -4._real64, 4._real64)
        cases(11) = unary_case('asin', 'asin', w_asin, o_asin, -1._real64, 1._real64)
        cases(12) = unary_case('acos', 'acos', w_acos, o_acos, -1._real64, 1._real64)
        cases(13) = unary_case('atan', 'atan', w_atan, o_atan, -20._real64, 20._real64)
        cases(14) = unary_case('asinh', 'asinh', w_asinh, o_asinh, -20._real64, 20._real64)
        cases(15) = unary_case('acosh', 'acosh', w_acosh, o_acosh, 1._real64, 20._real64)
        cases(16) = unary_case('atanh', 'atanh', w_atanh, o_atanh, -0.99_real64, 0.99_real64)
        cases(17) = unary_case('floor', 'floor', w_floor, o_floor, -20._real64, 20._real64)
        cases(18) = unary_case('ceiling', 'ceiling', w_ceiling, o_ceiling, -20._real64, 20._real64)
        cases(19) = unary_case('aint', 'aint', w_aint, o_aint, -20._real64, 20._real64)
        cases(20) = unary_case('mlx_round', 'mlx_round', w_mlx_round, o_mlx_round, -20._real64, 20._real64)
        cases(21) = unary_case('mlx_sign', 'mlx_sign', w_mlx_sign, o_mlx_sign, -20._real64, 20._real64)
        cases(22) = unary_case('mlx_sigmoid', 'mlx_sigmoid', w_mlx_sigmoid, o_mlx_sigmoid, -20._real64, 20._real64)
        cases(23) = unary_case('mlx_square', 'mlx_square', w_mlx_square, o_mlx_square, -20._real64, 20._real64)
        cases(24) = unary_case('mlx_reciprocal', 'mlx_reciprocal', w_mlx_reciprocal, o_mlx_reciprocal, 0.05_real64, 20._real64)
        cases(25) = unary_case('mlx_rsqrt', 'mlx_rsqrt', w_mlx_rsqrt, o_mlx_rsqrt, 0.05_real64, 20._real64)
        cases(26) = unary_case('mlx_expm1', 'mlx_expm1', w_mlx_expm1, o_mlx_expm1, -10._real64, 10._real64)
        cases(27) = unary_case('mlx_log1p', 'mlx_log1p', w_mlx_log1p, o_mlx_log1p, -0.99_real64, 20._real64)
        cases(28) = unary_case('mlx_log2', 'mlx_log2', w_mlx_log2, o_mlx_log2, 1.e-6_real64, 20._real64)
        cases(29) = unary_case('mlx_erfinv', 'mlx_erfinv', w_mlx_erfinv, o_mlx_erfinv, -0.99_real64, 0.99_real64)
        cases(30) = unary_case('mlx_degrees', 'mlx_degrees', w_mlx_degrees, o_mlx_degrees, -10._real64, 10._real64)
        cases(31) = unary_case('mlx_radians', 'mlx_radians', w_mlx_radians, o_mlx_radians, -1000._real64, 1000._real64)
        cases(32) = unary_case('mlx_stop_gradient', 'mlx_stop_gradient', w_mlx_stop_gradient, o_mlx_stop_gradient, -20._real64, 20._real64)
        cases(33) = unary_case('mlx_copy', 'mlx_copy', w_mlx_copy, o_mlx_copy, -20._real64, 20._real64)
        cases(34) = unary_case('unary +', 'operator(+)', w_plus, o_plus, -20._real64, 20._real64)
    end subroutine unary_table

    subroutine binary_table( cases )
        type(binary_case), allocatable, intent(out) :: cases(:)
        allocate(cases(8))
        cases(1) = binary_case('atan2', 'atan2', w_atan2, o_atan2, [-10._real64, -10._real64], [10._real64, 10._real64], .false., .false.)
        cases(2) = binary_case('modulo', 'modulo', w_modulo, o_modulo, [-20._real64, 0.5_real64], [20._real64, 5._real64], .false., .true.)
        cases(3) = binary_case('min', 'min', w_min, o_min, [-20._real64, -20._real64], [20._real64, 20._real64], .false., .false.)
        cases(4) = binary_case('**', 'operator(**)', w_pow, o_pow, [0.1_real64, -3._real64], [10._real64, 3._real64], .false., .false.)
        cases(5) = binary_case('mlx_logaddexp', 'mlx_logaddexp', w_mlx_logaddexp, o_mlx_logaddexp, [-20._real64, -20._real64], [20._real64, 20._real64], .false., .false.)
        cases(6) = binary_case('mlx_floor_divide', 'mlx_floor_divide', w_mlx_floor_divide, o_mlx_floor_divide, [-20._real64, 1._real64], [20._real64, 5._real64], .true., .true.)
        cases(7) = binary_case('mlx_divmod quotient', 'mlx_divmod', w_mlx_divmod_quotient, o_mlx_divmod_quotient, [-20._real64, 1._real64], [20._real64, 5._real64], .true., .true.)
        cases(8) = binary_case('mlx_divmod remainder', 'mlx_divmod', w_mlx_divmod_remainder, o_mlx_divmod_remainder, [-20._real64, 1._real64], [20._real64, 5._real64], .true., .true.)
    end subroutine binary_table

    function w_abs( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = abs(a)
    end function w_abs

    function o_abs( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = abs(x)
    end function o_abs

    function w_sin( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = sin(a)
    end function w_sin

    function o_sin( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = sin(x)
    end function o_sin

    function w_cos( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = cos(a)
    end function w_cos

    function o_cos( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = cos(x)
    end function o_cos

    function w_tan( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = tan(a)
    end function w_tan

    function o_tan( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = tan(x)
    end function o_tan

    function w_sinh( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = sinh(a)
    end function w_sinh

    function o_sinh( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = sinh(x)
    end function o_sinh

    function w_cosh( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = cosh(a)
    end function w_cosh

    function o_cosh( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = cosh(x)
    end function o_cosh

    function w_tanh( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = tanh(a)
    end function w_tanh

    function o_tanh( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = tanh(x)
    end function o_tanh

    function w_log( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = log(a)
    end function w_log

    function o_log( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = log(x)
    end function o_log

    function w_log10( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = log10(a)
    end function w_log10

    function o_log10( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = log10(x)
    end function o_log10

    function w_erf( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = erf(a)
    end function w_erf

    function o_erf( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = erf(x)
    end function o_erf

    function w_asin( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = asin(a)
    end function w_asin

    function o_asin( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = asin(x)
    end function o_asin

    function w_acos( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = acos(a)
    end function w_acos

    function o_acos( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = acos(x)
    end function o_acos

    function w_atan( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = atan(a)
    end function w_atan

    function o_atan( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = atan(x)
    end function o_atan

    function w_asinh( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = asinh(a)
    end function w_asinh

    function o_asinh( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = asinh(x)
    end function o_asinh

    function w_acosh( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = acosh(a)
    end function w_acosh

    function o_acosh( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = acosh(x)
    end function o_acosh

    function w_atanh( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = atanh(a)
    end function w_atanh

    function o_atanh( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = atanh(x)
    end function o_atanh

    function w_floor( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = floor(a)
    end function w_floor

    function o_floor( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = real(floor(x), real64)
    end function o_floor

    function w_ceiling( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = ceiling(a)
    end function w_ceiling

    function o_ceiling( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = real(ceiling(x), real64)
    end function o_ceiling

    function w_aint( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = aint(a)
    end function w_aint

    function o_aint( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = aint(x)
    end function o_aint

    function w_mlx_round( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_round(a)
    end function w_mlx_round

    function o_mlx_round( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = half_even(x)
    end function o_mlx_round

    function w_mlx_sign( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_sign(a)
    end function w_mlx_sign

    function o_mlx_sign( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = signum(x)
    end function o_mlx_sign

    function w_mlx_sigmoid( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_sigmoid(a)
    end function w_mlx_sigmoid

    function o_mlx_sigmoid( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 1._real64/(1._real64+exp(-x))
    end function o_mlx_sigmoid

    function w_mlx_square( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_square(a)
    end function w_mlx_square

    function o_mlx_square( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = x*x
    end function o_mlx_square

    function w_mlx_reciprocal( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_reciprocal(a)
    end function w_mlx_reciprocal

    function o_mlx_reciprocal( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 1._real64/x
    end function o_mlx_reciprocal

    function w_mlx_rsqrt( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_rsqrt(a)
    end function w_mlx_rsqrt

    function o_mlx_rsqrt( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 1._real64/sqrt(x)
    end function o_mlx_rsqrt

    function w_mlx_expm1( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_expm1(a)
    end function w_mlx_expm1

    function o_mlx_expm1( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = expm1_of(x)
    end function o_mlx_expm1

    function w_mlx_log1p( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_log1p(a)
    end function w_mlx_log1p

    function o_mlx_log1p( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = log1p_of(x)
    end function o_mlx_log1p

    function w_mlx_log2( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_log2(a)
    end function w_mlx_log2

    function o_mlx_log2( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = log(x)/log(2._real64)
    end function o_mlx_log2

    function w_mlx_erfinv( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_erfinv(a)
    end function w_mlx_erfinv

    function o_mlx_erfinv( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = erfinv_of(x)
    end function o_mlx_erfinv

    function w_mlx_degrees( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_degrees(a)
    end function w_mlx_degrees

    function o_mlx_degrees( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = x*(180._real64/acos(-1._real64))
    end function o_mlx_degrees

    function w_mlx_radians( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_radians(a)
    end function w_mlx_radians

    function o_mlx_radians( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = x*(acos(-1._real64)/180._real64)
    end function o_mlx_radians

    function w_mlx_stop_gradient( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_stop_gradient(a)
    end function w_mlx_stop_gradient

    function o_mlx_stop_gradient( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = x
    end function o_mlx_stop_gradient

    function w_mlx_copy( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = mlx_copy(a)
    end function w_mlx_copy

    function o_mlx_copy( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = x
    end function o_mlx_copy

    function w_plus( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        r = +a
    end function w_plus

    function o_plus( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = x
    end function o_plus

    function w_atan2( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = atan2(a, b)
    end function w_atan2

    function o_atan2( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = atan2(x, y)
    end function o_atan2

    function w_modulo( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = modulo(a, b)
    end function w_modulo

    function o_modulo( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = modulo(x, y)
    end function o_modulo

    function w_min( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = min(a, b)
    end function w_min

    function o_min( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = min(x, y)
    end function o_min

    function w_pow( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = a**b
    end function w_pow

    function o_pow( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = x**y
    end function o_pow

    function w_mlx_logaddexp( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = mlx_logaddexp(a, b)
    end function w_mlx_logaddexp

    function o_mlx_logaddexp( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = logaddexp_of(x, y)
    end function o_mlx_logaddexp

    function w_mlx_floor_divide( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = mlx_floor_divide(a, b)
    end function w_mlx_floor_divide

    function o_mlx_floor_divide( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = real(floor(x/y), real64)
    end function o_mlx_floor_divide

    function w_mlx_divmod_quotient( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = divmod_quotient(a, b)
    end function w_mlx_divmod_quotient

    function o_mlx_divmod_quotient( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = real(floor(x/y), real64)
    end function o_mlx_divmod_quotient

    function w_mlx_divmod_remainder( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        r = divmod_remainder(a, b)
    end function w_mlx_divmod_remainder

    function o_mlx_divmod_remainder( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = modulo(x, y)
    end function o_mlx_divmod_remainder

    function divmod_quotient( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        type(mlx_array) :: m
        call mlx_divmod(a, b, r, m)
    end function divmod_quotient

    function divmod_remainder( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        type(mlx_array) :: q
        call mlx_divmod(a, b, q, r)
    end function divmod_remainder

    ! the oracles' helpers, in real64
    function half_even( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = anint(x)
        if( abs(abs(x-aint(x))-0.5_real64) <= 0._real64 ) y = 2._real64*anint(x/2._real64)
    end function half_even

    function signum( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 0._real64
        if( x > 0._real64 ) y = 1._real64
        if( x < 0._real64 ) y = -1._real64
    end function signum

    ! exp(x) - 1 and log(1 + x) by their series near 0, where the direct forms cancel
    function expm1_of( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y, term
        integer      :: k
        if( abs(x) > 0.5_real64 )then
            y = exp(x)-1._real64
        else
            y = 0._real64
            term = 1._real64
            do k = 1, 30
                term = term*x/k
                y = y+term
            end do
        endif
    end function expm1_of

    function log1p_of( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 2._real64*atanh(x/(2._real64+x))
    end function log1p_of

    ! the inverse of erf on (-1, 1) by bisection to the last bit
    function erfinv_of( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y, lo, hi
        integer      :: k
        lo = -6._real64
        hi = 6._real64
        do k = 1, 200
            y = 0.5_real64*(lo+hi)
            if( erf(y) < x )then
                lo = y
            else
                hi = y
            endif
        end do
        y = 0.5_real64*(lo+hi)
    end function erfinv_of

    function logaddexp_of( x, y ) result(z)
        real(real64), intent(in) :: x, y
        real(real64) :: z
        z = max(x, y)+log(1._real64+exp(-abs(x-y)))
    end function logaddexp_of

    function logaddexp_of_v( x, y ) result(z)
        real(real64), intent(in) :: x(:), y
        real(real64) :: z(size(x))
        integer      :: j
        do j = 1, size(x)
            z(j) = logaddexp_of(x(j), y)
        end do
    end function logaddexp_of_v

end module mlxf_ops_math_tester
