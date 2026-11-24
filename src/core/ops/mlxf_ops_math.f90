!@descr: elementwise arithmetic and transcendental functions, rounding, clipping and NaN replacement
! Scalar operands of the binary functions are weak, as with the operators: they take the array's kind.
submodule(mlxf_ops) mlxf_ops_math
use mlxf_c_ops,  only: mlxc_abs, mlxc_arccos, mlxc_arccosh, mlxc_arcsin, mlxc_arcsinh, mlxc_arctan, mlxc_arctan2, &
                       mlxc_arctanh, mlxc_ceil, mlxc_clip, mlxc_copy, mlxc_cos, mlxc_cosh, mlxc_degrees, mlxc_divmod, &
                       mlxc_erf, mlxc_erfinv, mlxc_expm1, mlxc_floor, mlxc_floor_divide, mlxc_log, mlxc_log10, &
                       mlxc_log1p, mlxc_log2, mlxc_logaddexp, mlxc_minimum, mlxc_nan_to_num, mlxc_radians, &
                       mlxc_reciprocal, mlxc_remainder, mlxc_round, mlxc_rsqrt, mlxc_sigmoid, mlxc_sign, mlxc_sin, &
                       mlxc_sinh, mlxc_square, mlxc_stop_gradient, mlxc_tan, mlxc_tanh, mlxc_trunc
use mlxf_defs,   only: mlxf_nan_spec
use mlxf_array,  only: mlxf_binary, mlxf_binary_vector_op, mlxf_int_op, mlxf_nan_op, mlxf_ternary_op, mlxf_unary, &
                       mlxf_weak_scalar
use mlxf_device, only: mlxf_enter
implicit none

contains

    ! the absolute value (the modulus of a complex64 array, as float32)
    module function abs_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_abs, a, 'abs')
    end function abs_array

    module function sin_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_sin, a, 'sin')
    end function sin_array

    module function cos_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_cos, a, 'cos')
    end function cos_array

    module function tan_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_tan, a, 'tan')
    end function tan_array

    module function sinh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_sinh, a, 'sinh')
    end function sinh_array

    module function cosh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_cosh, a, 'cosh')
    end function cosh_array

    module function tanh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_tanh, a, 'tanh')
    end function tanh_array

    ! the natural logarithm
    module function log_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_log, a, 'log')
    end function log_array

    module function log10_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_log10, a, 'log10')
    end function log10_array

    module function erf_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_erf, a, 'erf')
    end function erf_array

    ! the inverse functions, as Fortran's intrinsics
    module function asin_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_arcsin, a, 'asin')
    end function asin_array

    module function acos_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_arccos, a, 'acos')
    end function acos_array

    module function atan_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_arctan, a, 'atan')
    end function atan_array

    module function asinh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_arcsinh, a, 'asinh')
    end function asinh_array

    module function acosh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_arccosh, a, 'acosh')
    end function acosh_array

    module function atanh_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_arctanh, a, 'atanh')
    end function atanh_array

    ! floor, ceiling and aint (truncation) keep the input's kind: a float result, unlike Fortran's integer floor and ceiling
    module function floor_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_floor, a, 'floor')
    end function floor_array

    module function ceiling_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_ceil, a, 'ceiling')
    end function ceiling_array

    module function aint_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_trunc, a, 'aint')
    end function aint_array

    ! the signum: -1, 0 or 1 (one argument, unlike Fortran's sign(a, b))
    module function mlx_sign( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_sign, a, 'mlx_sign')
    end function mlx_sign

    ! 1 / (1 + exp(-a))
    module function mlx_sigmoid( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_sigmoid, a, 'mlx_sigmoid')
    end function mlx_sigmoid

    ! a*a
    module function mlx_square( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_square, a, 'mlx_square')
    end function mlx_square

    ! 1 / a
    module function mlx_reciprocal( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_reciprocal, a, 'mlx_reciprocal')
    end function mlx_reciprocal

    ! 1 / sqrt(a)
    module function mlx_rsqrt( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_rsqrt, a, 'mlx_rsqrt')
    end function mlx_rsqrt

    ! exp(a) - 1, accurate near 0
    module function mlx_expm1( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_expm1, a, 'mlx_expm1')
    end function mlx_expm1

    ! log(1 + a), accurate near 0
    module function mlx_log1p( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_log1p, a, 'mlx_log1p')
    end function mlx_log1p

    ! the base-2 logarithm
    module function mlx_log2( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_log2, a, 'mlx_log2')
    end function mlx_log2

    ! the inverse of erf on (-1, 1)
    module function mlx_erfinv( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_erfinv, a, 'mlx_erfinv')
    end function mlx_erfinv

    ! radians to degrees
    module function mlx_degrees( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_degrees, a, 'mlx_degrees')
    end function mlx_degrees

    ! degrees to radians
    module function mlx_radians( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_radians, a, 'mlx_radians')
    end function mlx_radians

    ! a with no gradient flowing through it (its values unchanged)
    module function mlx_stop_gradient( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_stop_gradient, a, 'mlx_stop_gradient')
    end function mlx_stop_gradient

    ! a new graph node holding a copy of a (assignment shares the node instead)
    module function mlx_copy( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_copy, a, 'mlx_copy')
    end function mlx_copy

    ! rounded to decimals places (default 0), halves to even: 0.5 -> 0, 1.5 -> 2, 2.5 -> 2 (unlike anint)
    module function mlx_round( a, decimals ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: decimals
        type(mlx_array) :: r
        integer         :: places
        call mlxf_enter('mlx_round')
        places = 0
        if( present(decimals) ) places = decimals
        call mlxf_int_op(r, mlxc_round, a, places, 'mlx_round')
    end function mlx_round

    ! a limited to [a_min, a_max] elementwise; the bounds broadcast, and scalar bounds are weak
    module function clip_array( a, a_min, a_max ) result(r)
        type(mlx_array), intent(in) :: a, a_min, a_max
        type(mlx_array) :: r
        call mlxf_ternary_op(r, mlxc_clip, [a, a_min, a_max], 'mlx_clip')
    end function clip_array

    module function clip_s( a, a_min, a_max ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: a_min, a_max
        type(mlx_array) :: r
        type(mlx_array) :: lo, hi
        call mlxf_weak_scalar(lo, a, real(a_min, real64), 'mlx_clip')
        call mlxf_weak_scalar(hi, a, real(a_max, real64), 'mlx_clip')
        call mlxf_ternary_op(r, mlxc_clip, [a, lo, hi], 'mlx_clip')
    end function clip_s

    module function clip_d( a, a_min, a_max ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: a_min, a_max
        type(mlx_array) :: r
        type(mlx_array) :: lo, hi
        call mlxf_weak_scalar(lo, a, a_min, 'mlx_clip')
        call mlxf_weak_scalar(hi, a, a_max, 'mlx_clip')
        call mlxf_ternary_op(r, mlxc_clip, [a, lo, hi], 'mlx_clip')
    end function clip_d

    ! NaN replaced by nan (default 0), the infinities by posinf and neginf (default the largest finite values
    ! of a's kind)
    module function mlx_nan_to_num( a, nan, posinf, neginf ) result(r)
        type(mlx_array), intent(in)           :: a
        real(real32),    optional, intent(in) :: nan, posinf, neginf
        type(mlx_array)     :: r
        type(mlxf_nan_spec) :: spec
        call mlxf_enter('mlx_nan_to_num')
        if( present(nan) ) spec%nan = nan
        if( present(posinf) )then
            spec%posinf = posinf
            spec%has_posinf = .true.
        endif
        if( present(neginf) )then
            spec%neginf = neginf
            spec%has_neginf = .true.
        endif
        call mlxf_nan_op(r, mlxc_nan_to_num, a, spec, 'mlx_nan_to_num')
    end function mlx_nan_to_num

    ! atan2(y, x), the angle of (x, y), in Fortran's argument order
    module function atan2_array( y, x ) result(r)
        type(mlx_array), intent(in) :: y, x
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_arctan2, y, x, 'atan2')
    end function atan2_array

    module function atan2_ass( y, x ) result(r)
        type(mlx_array), intent(in) :: y
        real(real32),    intent(in) :: x
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, y, real(x, real64), 'atan2')
        call mlxf_binary(r, mlxc_arctan2, y, s, 'atan2')
    end function atan2_ass

    module function atan2_sas( y, x ) result(r)
        real(real32),    intent(in) :: y
        type(mlx_array), intent(in) :: x
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, x, real(y, real64), 'atan2')
        call mlxf_binary(r, mlxc_arctan2, s, x, 'atan2')
    end function atan2_sas

    module function atan2_asd( y, x ) result(r)
        type(mlx_array), intent(in) :: y
        real(real64),    intent(in) :: x
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, y, x, 'atan2')
        call mlxf_binary(r, mlxc_arctan2, y, s, 'atan2')
    end function atan2_asd

    module function atan2_sad( y, x ) result(r)
        real(real64),    intent(in) :: y
        type(mlx_array), intent(in) :: x
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, x, y, 'atan2')
        call mlxf_binary(r, mlxc_arctan2, s, x, 'atan2')
    end function atan2_sad

    ! Fortran's modulo(a, p): a - floor(a/p) p, with the sign of p
    module function modulo_array( a, p ) result(r)
        type(mlx_array), intent(in) :: a, p
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_remainder, a, p, 'modulo')
    end function modulo_array

    module function modulo_ass( a, p ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: p
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(p, real64), 'modulo')
        call mlxf_binary(r, mlxc_remainder, a, s, 'modulo')
    end function modulo_ass

    module function modulo_sas( a, p ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: p
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, p, real(a, real64), 'modulo')
        call mlxf_binary(r, mlxc_remainder, s, p, 'modulo')
    end function modulo_sas

    module function modulo_asd( a, p ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: p
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, p, 'modulo')
        call mlxf_binary(r, mlxc_remainder, a, s, 'modulo')
    end function modulo_asd

    module function modulo_sad( a, p ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: p
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, p, a, 'modulo')
        call mlxf_binary(r, mlxc_remainder, s, p, 'modulo')
    end function modulo_sad

    ! Fortran's min(a, b) elementwise
    module function min_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_minimum, a, b, 'min')
    end function min_array

    module function min_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(b, real64), 'min')
        call mlxf_binary(r, mlxc_minimum, a, s, 'min')
    end function min_ass

    module function min_sas( a, b ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, real(a, real64), 'min')
        call mlxf_binary(r, mlxc_minimum, s, b, 'min')
    end function min_sas

    module function min_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, b, 'min')
        call mlxf_binary(r, mlxc_minimum, a, s, 'min')
    end function min_asd

    module function min_sad( a, b ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, a, 'min')
        call mlxf_binary(r, mlxc_minimum, s, b, 'min')
    end function min_sad

    ! log(exp(a) + exp(b)) without overflow
    module function logaddexp_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_logaddexp, a, b, 'mlx_logaddexp')
    end function logaddexp_array

    module function logaddexp_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(b, real64), 'mlx_logaddexp')
        call mlxf_binary(r, mlxc_logaddexp, a, s, 'mlx_logaddexp')
    end function logaddexp_ass

    module function logaddexp_sas( a, b ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, real(a, real64), 'mlx_logaddexp')
        call mlxf_binary(r, mlxc_logaddexp, s, b, 'mlx_logaddexp')
    end function logaddexp_sas

    module function logaddexp_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, b, 'mlx_logaddexp')
        call mlxf_binary(r, mlxc_logaddexp, a, s, 'mlx_logaddexp')
    end function logaddexp_asd

    module function logaddexp_sad( a, b ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, a, 'mlx_logaddexp')
        call mlxf_binary(r, mlxc_logaddexp, s, b, 'mlx_logaddexp')
    end function logaddexp_sad

    ! floor(a / b), the quotient of modulo
    module function floor_divide_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_floor_divide, a, b, 'mlx_floor_divide')
    end function floor_divide_array

    module function floor_divide_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(b, real64), 'mlx_floor_divide')
        call mlxf_binary(r, mlxc_floor_divide, a, s, 'mlx_floor_divide')
    end function floor_divide_ass

    module function floor_divide_sas( a, b ) result(r)
        real(real32),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, real(a, real64), 'mlx_floor_divide')
        call mlxf_binary(r, mlxc_floor_divide, s, b, 'mlx_floor_divide')
    end function floor_divide_sas

    module function floor_divide_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, b, 'mlx_floor_divide')
        call mlxf_binary(r, mlxc_floor_divide, a, s, 'mlx_floor_divide')
    end function floor_divide_asd

    module function floor_divide_sad( a, b ) result(r)
        real(real64),    intent(in) :: a
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, a, 'mlx_floor_divide')
        call mlxf_binary(r, mlxc_floor_divide, s, b, 'mlx_floor_divide')
    end function floor_divide_sad

    ! the quotient floor(a / b) and the remainder modulo(a, b) of one MLX node
    module subroutine mlx_divmod( a, b, quotient, remainder )
        type(mlx_array), intent(in)  :: a, b
        type(mlx_array), intent(out) :: quotient, remainder
        type(mlx_array), allocatable :: qr(:)
        call mlxf_binary_vector_op(qr, mlxc_divmod, [a, b], 'mlx_divmod')
        quotient = qr(1)
        remainder = qr(2)
    end subroutine mlx_divmod

end submodule mlxf_ops_math
