!@descr: host oracle: direct discrete Fourier transforms in complex double precision, 1D and 3D, and their self-check
! Forward, unnormalised, negative exponent: X(k) = sum over m of x(m) exp(-2 pi i k m / n). Inverse, positive
! exponent, normalised by n: x(m) = (1/n) sum over k of X(k) exp(+2 pi i k m / n). In 3D the product over the
! three dimensions, the inverse normalised by n1 n2 n3. A 0-based index k or m is stored at k + 1, dimension 1
! fastest. Direct sums for small sizes; plain Fortran on intrinsic modules only, so it builds without the library.
! It also holds the error measures the oracle modules share, non-finite values reported as +Inf.
module mlxf_oracle_dft
use, intrinsic :: iso_fortran_env, only: real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_value, ieee_positive_inf
implicit none

public :: oracle_dft_1d, oracle_idft_1d, oracle_dft_3d, oracle_idft_3d, oracle_dft_selfcheck, oracle_flat, &
          oracle_rel_error, oracle_finite_or_inf, oracle_all_finite
private

real(real64),    parameter :: TWOPI = 2._real64 * acos(-1._real64)
complex(real64), parameter :: CZERO = (0._real64, 0._real64)
! the self-check's limit on every transform error, relative to the reference's largest magnitude
real(real64),    parameter :: TOL_TRANSFORM = 1.e-12_real64
integer,         parameter :: NCHECK    = 12
integer,         parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'dft1 impulse', 'dft1 mode', 'dft1 constant', 'dft1 parseval', 'dft1 round trip', 'idft1 impulse', &
    'dft3 impulse', 'dft3 mode', 'dft3 constant', 'dft3 parseval', 'dft3 round trip', 'idft3 impulse']
! the sizes of the 1D checks, and the shapes of the 3D checks: one with three unequal sizes, then cubes
integer,         parameter :: SIZES_1D(6)    = [4, 6, 8, 10, 12, 16]
integer,         parameter :: SHAPES_3D(3, 5) = reshape([6, 8, 10, 4, 4, 4, 8, 8, 8, 12, 12, 12, 16, 16, 16], [3, 5])
! the 0-based position of the impulses and the frequency of the modes: distinct per axis, so a swap shows
integer,         parameter :: AT(3) = [1, 2, 3]
complex(real64), parameter :: CONSTANT = (0.75_real64, -1.25_real64)

contains

    ! the forward transform of a vector
    pure function oracle_dft_1d( x ) result(y)
        complex(real64), intent(in) :: x(:)
        complex(real64) :: y(size(x))
        y = matvec(twiddles(size(x), -1), x)
    end function oracle_dft_1d

    ! the inverse transform of a vector, normalised by its length
    pure function oracle_idft_1d( x ) result(y)
        complex(real64), intent(in) :: x(:)
        complex(real64) :: y(size(x))
        y = matvec(twiddles(size(x), 1), x) / real(size(x), real64)
    end function oracle_idft_1d

    ! the forward transform of a volume
    pure function oracle_dft_3d( x ) result(y)
        complex(real64), intent(in) :: x(:,:,:)
        complex(real64) :: y(size(x, 1), size(x, 2), size(x, 3))
        y = separable(x, -1)
    end function oracle_dft_3d

    ! the inverse transform of a volume, normalised by its number of voxels
    pure function oracle_idft_3d( x ) result(y)
        complex(real64), intent(in) :: x(:,:,:)
        complex(real64) :: y(size(x, 1), size(x, 2), size(x, 3))
        y = separable(x, 1) / real(size(x), real64)
    end function oracle_idft_3d

    ! the n x n matrix exp(sgn 2 pi i k m / n), the product k m reduced modulo n in integers
    pure function twiddles( n, sgn ) result(w)
        integer, intent(in) :: n, sgn
        complex(real64) :: w(n, n)
        real(real64)    :: angle
        integer         :: k, m
        do m = 1, n
            do k = 1, n
                angle  = real(sgn, real64) * TWOPI * real(modulo((k - 1) * (m - 1), n), real64) / real(n, real64)
                w(k, m) = cmplx(cos(angle), sin(angle), real64)
            end do
        end do
    end function twiddles

    ! u = w v by explicit sums, in a fixed order
    pure function matvec( w, v ) result(u)
        complex(real64), intent(in) :: w(:,:), v(:)
        complex(real64) :: u(size(w, 1))
        integer         :: k, m
        do k = 1, size(w, 1)
            u(k) = CZERO
            do m = 1, size(v)
                u(k) = u(k) + w(k, m) * v(m)
            end do
        end do
    end function matvec

    ! the unnormalised 3D transform of sign sgn, one dimension after the other
    pure function separable( x, sgn ) result(y)
        complex(real64), intent(in) :: x(:,:,:)
        integer,         intent(in) :: sgn
        complex(real64) :: y(size(x, 1), size(x, 2), size(x, 3))
        complex(real64) :: w1(size(x, 1), size(x, 1)), w2(size(x, 2), size(x, 2)), w3(size(x, 3), size(x, 3))
        integer         :: i1, i2, i3
        w1 = twiddles(size(x, 1), sgn)
        w2 = twiddles(size(x, 2), sgn)
        w3 = twiddles(size(x, 3), sgn)
        do i3 = 1, size(x, 3)
            do i2 = 1, size(x, 2)
                y(:, i2, i3) = matvec(w1, x(:, i2, i3))
            end do
        end do
        do i3 = 1, size(x, 3)
            do i1 = 1, size(x, 1)
                y(i1, :, i3) = matvec(w2, y(i1, :, i3))
            end do
        end do
        do i2 = 1, size(x, 2)
            do i1 = 1, size(x, 1)
                y(i1, i2, :) = matvec(w3, y(i1, i2, :))
            end do
        end do
    end function separable

    ! the checks against closed forms; each error is the largest over the sizes and shapes, a limit is not
    ! applied here, and a non-finite result reports +Inf
    subroutine oracle_dft_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        integer :: i
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        errors = 0._real64
        limits = TOL_TRANSFORM
        do i = 1, size(SIZES_1D)
            call check_1d(SIZES_1D(i), errors(1:6))
        end do
        do i = 1, size(SHAPES_3D, 2)
            call check_3d(SHAPES_3D(:, i), errors(7:12))
        end do
    end subroutine oracle_dft_selfcheck

    ! the six 1D checks at length n, folded into err by maximum
    subroutine check_1d( n, err )
        integer,      intent(in)    :: n
        real(real64), intent(inout) :: err(6)
        complex(real64) :: x(n), ref(n)
        real(real64)    :: s
        integer         :: k
        ! an impulse at AT(1) has the phases exp(-2 pi i k AT(1) / n)
        x          = CZERO
        x(1+AT(1)) = (1._real64, 0._real64)
        do k = 1, n
            ref(k) = exp(cmplx(0._real64, -TWOPI * real((k - 1) * AT(1), real64) / real(n, real64), real64))
        end do
        err(1) = max(err(1), oracle_rel_error(oracle_dft_1d(x), ref))
        ! the mode exp(+2 pi i AT(1) m / n) is n at k = AT(1) and zero elsewhere
        do k = 1, n
            x(k) = exp(cmplx(0._real64, TWOPI * real((k - 1) * AT(1), real64) / real(n, real64), real64))
        end do
        ref          = CZERO
        ref(1+AT(1)) = cmplx(real(n, real64), 0._real64, real64)
        err(2) = max(err(2), oracle_rel_error(oracle_dft_1d(x), ref))
        ! a constant is n times itself at k = 0
        x      = CONSTANT
        ref    = CZERO
        ref(1) = real(n, real64) * CONSTANT
        err(3) = max(err(3), oracle_rel_error(oracle_dft_1d(x), ref))
        ! Parseval: the sum of |X|**2 is n times the sum of |x|**2
        x      = sequence_1d(n)
        s      = real(n, real64) * sum(abs(x)**2)
        err(4) = max(err(4), oracle_finite_or_inf(abs(sum(abs(oracle_dft_1d(x))**2) - s) / s))
        ! the inverse undoes the forward transform
        err(5) = max(err(5), oracle_rel_error(oracle_idft_1d(oracle_dft_1d(x)), x))
        ! the inverse of an impulse at AT(2) is exp(+2 pi i AT(2) m / n) / n
        x          = CZERO
        x(1+AT(2)) = (1._real64, 0._real64)
        do k = 1, n
            ref(k) = exp(cmplx(0._real64, TWOPI * real((k - 1) * AT(2), real64) / real(n, real64), real64)) / &
                     real(n, real64)
        end do
        err(6) = max(err(6), oracle_rel_error(oracle_idft_1d(x), ref))
    end subroutine check_1d

    ! the six 3D checks on one shape, folded into err by maximum
    subroutine check_3d( shp, err )
        integer,      intent(in)    :: shp(3)
        real(real64), intent(inout) :: err(6)
        complex(real64) :: x(shp(1), shp(2), shp(3)), ref(shp(1), shp(2), shp(3))
        real(real64)    :: s, phase
        integer         :: i1, i2, i3
        ! an impulse at AT has the phases exp(-2 pi i sum over axes of k AT / n)
        x                            = CZERO
        x(1+AT(1), 1+AT(2), 1+AT(3)) = (1._real64, 0._real64)
        do i3 = 1, shp(3)
            do i2 = 1, shp(2)
                do i1 = 1, shp(1)
                    phase           = TWOPI * plane_wave([i1 - 1, i2 - 1, i3 - 1], shp)
                    ref(i1, i2, i3) = exp(cmplx(0._real64, -phase, real64))
                end do
            end do
        end do
        err(1) = max(err(1), oracle_rel_error(oracle_flat(oracle_dft_3d(x)), oracle_flat(ref)))
        ! the mode exp(+2 pi i sum of AT m / n), the impulse's phases conjugated, is n1 n2 n3 at AT, zero elsewhere
        x                              = conjg(ref)
        ref                            = CZERO
        ref(1+AT(1), 1+AT(2), 1+AT(3)) = cmplx(real(size(x), real64), 0._real64, real64)
        err(2) = max(err(2), oracle_rel_error(oracle_flat(oracle_dft_3d(x)), oracle_flat(ref)))
        ! a constant is n1 n2 n3 times itself at the origin
        x            = CONSTANT
        ref          = CZERO
        ref(1, 1, 1) = real(size(x), real64) * CONSTANT
        err(3) = max(err(3), oracle_rel_error(oracle_flat(oracle_dft_3d(x)), oracle_flat(ref)))
        ! Parseval
        x      = sequence_3d(shp)
        s      = real(size(x), real64) * sum(abs(x)**2)
        err(4) = max(err(4), oracle_finite_or_inf(abs(sum(abs(oracle_dft_3d(x))**2) - s) / s))
        ! the inverse undoes the forward transform
        err(5) = max(err(5), oracle_rel_error(oracle_flat(oracle_idft_3d(oracle_dft_3d(x))), oracle_flat(x)))
        ! the inverse of an impulse at AT is exp(+2 pi i sum of k AT / n) / (n1 n2 n3)
        x                            = CZERO
        x(1+AT(1), 1+AT(2), 1+AT(3)) = (1._real64, 0._real64)
        do i3 = 1, shp(3)
            do i2 = 1, shp(2)
                do i1 = 1, shp(1)
                    phase           = TWOPI * plane_wave([i1 - 1, i2 - 1, i3 - 1], shp)
                    ref(i1, i2, i3) = exp(cmplx(0._real64, phase, real64)) / real(size(x), real64)
                end do
            end do
        end do
        err(6) = max(err(6), oracle_rel_error(oracle_flat(oracle_idft_3d(x)), oracle_flat(ref)))
    end subroutine check_3d

    ! a volume as a vector, in storage order
    pure function oracle_flat( x ) result(v)
        complex(real64), intent(in) :: x(:,:,:)
        complex(real64) :: v(size(x))
        v = reshape(x, [size(x)])
    end function oracle_flat

    ! sum over the axes of k AT / n, the phase in turns of the plane wave at AT
    pure function plane_wave( k, shp ) result(turns)
        integer, intent(in) :: k(3), shp(3)
        real(real64) :: turns
        turns = sum(real(k * AT, real64) / real(shp, real64))
    end function plane_wave

    ! a fixed complex sequence from integers, no random draw
    pure function sequence_1d( n ) result(x)
        integer, intent(in) :: n
        complex(real64) :: x(n)
        integer         :: m
        do m = 1, n
            x(m) = cmplx(modulo(7 * m + 3, 11) - 5, modulo(5 * m + 1, 13) - 6, real64) / 4._real64
        end do
    end function sequence_1d

    ! a fixed complex volume from integers, no random draw
    pure function sequence_3d( shp ) result(x)
        integer, intent(in) :: shp(3)
        complex(real64) :: x(shp(1), shp(2), shp(3))
        integer         :: i1, i2, i3
        do i3 = 1, shp(3)
            do i2 = 1, shp(2)
                do i1 = 1, shp(1)
                    x(i1, i2, i3) = cmplx(modulo(7 * i1 + 3 * i2 + 5 * i3 + 3, 11) - 5, &
                                          modulo(5 * i1 + 2 * i2 + 9 * i3 + 1, 13) - 6, real64) / 4._real64
                end do
            end do
        end do
    end function sequence_3d

    ! the largest |a - ref| relative to the largest |ref|; +Inf when a or ref holds a non-finite value
    pure function oracle_rel_error( a, ref ) result(e)
        complex(real64), intent(in) :: a(:), ref(:)
        real(real64) :: e
        ! maxval may pass over a NaN, so every value is tested first
        if( oracle_all_finite(a) .and. oracle_all_finite(ref) )then
            e = oracle_finite_or_inf(maxval(abs(a - ref)) / maxval(abs(ref)))
        else
            e = ieee_value(e, ieee_positive_inf)
        endif
    end function oracle_rel_error

    ! whether every real and imaginary part is finite
    pure function oracle_all_finite( a ) result(ok)
        complex(real64), intent(in) :: a(:)
        logical :: ok
        ok = all(ieee_is_finite(real(a)) .and. ieee_is_finite(aimag(a)))
    end function oracle_all_finite

    ! e itself when finite, else +Inf
    pure function oracle_finite_or_inf( e ) result(r)
        real(real64), intent(in) :: e
        real(real64) :: r
        r = e
        if( .not. ieee_is_finite(r) ) r = ieee_value(r, ieee_positive_inf)
    end function oracle_finite_or_inf

end module mlxf_oracle_dft
