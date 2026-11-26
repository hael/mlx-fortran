!@descr: NaN-safe maximum for test code: a NaN anywhere makes the result +infinity, so no tolerance accepts it
! Fortran's maxval may skip a NaN among finite values (gfortran does), and max(acc, NaN) may keep acc, so an
! error reduced with them can pass with a corrupt element. Test code reduces errors and scales with nan_maxval
! and accumulates them with nan_max (rule nanmax); +infinity fails every comparison err <= tol. One specific per
! rank: gfortran passes an empty pack() result to an assumed-rank dummy with a corrupt descriptor.
module mlxf_test_reduce
use, intrinsic :: iso_fortran_env, only: real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_positive_inf
implicit none
public :: nan_maxval, nan_max
private

interface nan_maxval
    module procedure nan_maxval_r64_1, nan_maxval_r64_2, nan_maxval_r64_3, nan_maxval_r64_4, nan_maxval_r64_5
    module procedure nan_maxval_r32_1, nan_maxval_r32_2, nan_maxval_r32_3, nan_maxval_r32_4, nan_maxval_r32_5
end interface nan_maxval

interface nan_max
    module procedure nan_max_r64, nan_max_r32
end interface nan_max

contains

    ! max(a, b), +infinity when either operand is a NaN; elemental, as max is
    elemental function nan_max_r64( a, b ) result(r)
        real(real64), intent(in) :: a, b
        real(real64) :: r
        r = max(a, b)
        if( ieee_is_nan(a) .or. ieee_is_nan(b) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_max_r64

    elemental function nan_max_r32( a, b ) result(r)
        real(real32), intent(in) :: a, b
        real(real32) :: r
        r = max(a, b)
        if( ieee_is_nan(a) .or. ieee_is_nan(b) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_max_r32

    ! maxval(x), +infinity when any element is a NaN (-huge when x is empty)
    pure function nan_maxval_r64_1( x ) result(r)
        real(real64), intent(in) :: x(:)
        real(real64) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r64_1

    pure function nan_maxval_r64_2( x ) result(r)
        real(real64), intent(in) :: x(:,:)
        real(real64) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r64_2

    pure function nan_maxval_r64_3( x ) result(r)
        real(real64), intent(in) :: x(:,:,:)
        real(real64) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r64_3

    pure function nan_maxval_r64_4( x ) result(r)
        real(real64), intent(in) :: x(:,:,:,:)
        real(real64) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r64_4

    pure function nan_maxval_r64_5( x ) result(r)
        real(real64), intent(in) :: x(:,:,:,:,:)
        real(real64) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r64_5

    pure function nan_maxval_r32_1( x ) result(r)
        real(real32), intent(in) :: x(:)
        real(real32) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r32_1

    pure function nan_maxval_r32_2( x ) result(r)
        real(real32), intent(in) :: x(:,:)
        real(real32) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r32_2

    pure function nan_maxval_r32_3( x ) result(r)
        real(real32), intent(in) :: x(:,:,:)
        real(real32) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r32_3

    pure function nan_maxval_r32_4( x ) result(r)
        real(real32), intent(in) :: x(:,:,:,:)
        real(real32) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r32_4

    pure function nan_maxval_r32_5( x ) result(r)
        real(real32), intent(in) :: x(:,:,:,:,:)
        real(real32) :: r
        r = maxval(x)
        if( any(ieee_is_nan(x)) ) r = ieee_value(r, ieee_positive_inf)
    end function nan_maxval_r32_5

end module mlxf_test_reduce
