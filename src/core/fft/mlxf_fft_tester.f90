!@descr: independent two-device checks of fft values and Fortran conventions
module mlxf_fft_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                           MLX_FFT_NORMS, sqrt, real, cmplx, reshape, sum, mlx_fft, mlx_ifft, mlx_fft2, mlx_ifft2, &
                           mlx_rfft, mlx_irfft
use mlxf_test_utils, only: assert_true, test_devices, device_name
implicit none
private
public :: run_all_fft_tests

contains

    subroutine run_all_fft_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all fft tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_complex_fft
            call test_real_fft
            call test_batched_fft2
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_fft_tests

    ! the reference: a direct double-precision DFT with MLX's sign and normalisation conventions
    function dft( x, n, inverse, norm ) result(y)
        complex(real64), intent(in) :: x(:)
        integer,         intent(in) :: n, norm
        logical,         intent(in) :: inverse
        complex(real64) :: y(n), phase
        real(real64)    :: angle, sgn, scale
        integer         :: j, k
        sgn = -1
        if( inverse ) sgn = 1
        scale = 1
        if( norm == MLX_FFT_NORMS%ortho ) scale = 1/sqrt(real(n, real64))
        if( norm == MLX_FFT_NORMS%forward .and. .not. inverse ) scale = 1/real(n, real64)
        if( norm == MLX_FFT_NORMS%backward .and. inverse ) scale = 1/real(n, real64)
        do k = 1, n
            y(k) = cmplx(0.d0, 0.d0, real64)
            do j = 1, min(n, size(x))
                angle = sgn*2*acos(-1.d0)*real((j-1)*(k-1), real64)/real(n, real64)
                phase = cmplx(cos(angle), sin(angle), real64)
                y(k) = y(k)+x(j)*phase
            end do
            y(k) = y(k)*scale
        end do
    end function dft

    ! a against the reference within ||err||_2 <= 1e-5 log2(n) ||x||_2
    subroutine check_fft( a, want, input_norm, n, label )
        type(mlx_array),  intent(in) :: a
        complex(real64),  intent(in) :: want(:)
        real(real64),     intent(in) :: input_norm
        integer,          intent(in) :: n
        character(len=*), intent(in) :: label
        complex(real32) :: y(size(want))
        real(real64)    :: err, bound
        call mlx_to(y, a)
        err = sqrt(sum(abs(cmplx(y, kind=real64)-want)**2))
        bound = 1.d-5*log(real(n, real64))/log(2.d0)*input_norm
        call assert_true(err <= bound, label)
    end subroutine check_fft

    ! FFT and IFFT signs, normalisations and dimensions, explicit padding, and the 2D transform's axes
    subroutine test_complex_fft
        type(mlx_array) :: a, r
        complex(real32) :: x(3, 4)
        complex(real64) :: w(3, 4), expected(3, 4), tmp(3, 4), padded(6, 4)
        integer         :: i, j, norm
        real(real64)    :: nx
        write(*,'(a)') 'test_complex_fft'
        x = reshape([(cmplx(real(i, real32)/16, real(mod(i, 3), real32)/8, real32), i=1, 12)], shape(x))
        w = cmplx(x, kind=real64)
        nx = sqrt(sum(abs(w)**2))
        a = mlx_from(x)
        do norm = MLX_FFT_NORMS%backward, MLX_FFT_NORMS%forward
            do j = 1, 4
                expected(:, j) = dft(w(:, j), 3, .false., norm)
            end do
            r = mlx_fft(a, 1, norm=norm)
            call check_fft(r, reshape(expected, [12]), nx, 3, 'FFT negative sign along dimension one')
            do i = 1, 3
                expected(i, :) = dft(w(i, :), 4, .true., norm)
            end do
            r = mlx_ifft(a, 2, norm=norm)
            call check_fft(r, reshape(expected, [12]), nx, 4, 'IFFT positive sign, backward 1/n, dimension two')
            do j = 1, 4
                tmp(:, j) = dft(w(:, j), 3, .false., norm)
            end do
            do i = 1, 3
                expected(i, :) = dft(tmp(i, :), 4, .false., norm)
            end do
            r = mlx_fft2(a, [1, 2], norm=norm)
            call check_fft(r, reshape(expected, [12]), nx, 12, 'two-dimensional FFT norm and axes')
            do j = 1, 4
                tmp(:, j) = dft(w(:, j), 3, .true., norm)
            end do
            do i = 1, 3
                expected(i, :) = dft(tmp(i, :), 4, .true., norm)
            end do
            r = mlx_ifft2(a, [2, 1], norm=norm)
            call check_fft(r, reshape(expected, [12]), nx, 12, 'two-dimensional IFFT order and normalization')
        end do
        do j = 1, 4
            padded(:, j) = dft(w(:, j), 6, .false., MLX_FFT_NORMS%backward)
        end do
        r = mlx_fft(a, 1, n=6)
        call assert_true(all(r%shape() == [6, 4]), 'FFT explicit n pads the selected dimension')
        call check_fft(r, reshape(padded, [24]), nx, 6, 'FFT zero padding against DFT')
        r = mlx_fft2(a, [1, 2], n=[6, 4])
        do i = 1, 6
            padded(i, :) = dft(padded(i, :), 4, .false., MLX_FFT_NORMS%backward)
        end do
        call check_fft(r, reshape(padded, [24]), nx, 24, 'FFT2 explicit lengths stay paired with dimensions')
    end subroutine test_complex_fft

    ! a rank-three FFT2 transforms Fortran dimensions 1 and 2 and leaves the batch dimension alone
    subroutine test_batched_fft2
        type(mlx_array) :: a, r
        complex(real32) :: x(3, 4, 5)
        complex(real64) :: w(3, 4, 5), tmp(3, 4, 5), expected(3, 4, 5)
        integer         :: i, j, k
        real(real64)    :: nx
        write(*,'(a)') 'test_batched_fft2'
        x = reshape([(cmplx(real(i, real32)/13, real(mod(i, 7), real32)/11, real32), i=1, 60)], shape(x))
        w = cmplx(x, kind=real64)
        nx = sqrt(sum(abs(w)**2))
        do k = 1, 5
            do j = 1, 4
                tmp(:, j, k) = dft(w(:, j, k), 3, .false., MLX_FFT_NORMS%backward)
            end do
            do i = 1, 3
                expected(i, :, k) = dft(tmp(i, :, k), 4, .false., MLX_FFT_NORMS%backward)
            end do
        end do
        a = mlx_from(x)
        r = mlx_fft2(a, [1, 2])
        call assert_true(all(r%shape() == [3, 4, 5]), 'rank-three FFT2 preserves distinct transform and batch extents')
        call check_fft(r, reshape(expected, [60]), nx, 12, 'batched FFT2 transforms dimensions one and two, not the batch')
    end subroutine test_batched_fft2

    ! RFFT's half spectrum and sign, IRFFT's default length and 1/n scaling, and float64's float32 bound on
    ! the CPU
    subroutine test_real_fft
        type(mlx_array) :: a, r, b
        real(real32)    :: x(5, 3), got(5, 3), even(4, 3), got4(4, 3)
        complex(real64) :: w(5), expected(3, 3), expected4(3, 3), spectrum(5)
        real(real64)    :: nx, bound
        integer         :: i, j, norm
        write(*,'(a)') 'test_real_fft'
        x = reshape([(real(i, real32)/16, i=1, 15)], shape(x))
        nx = sqrt(sum(real(x, real64)**2))
        a = mlx_from(x)
        do norm = MLX_FFT_NORMS%backward, MLX_FFT_NORMS%forward
            do j = 1, 3
                w = cmplx(real(x(:, j), real64), 0.d0, real64)
                spectrum = dft(w, 5, .false., norm)
                expected(:, j) = spectrum(:3)
            end do
            r = mlx_rfft(a, 1, norm=norm)
            call assert_true(all(r%shape() == [3, 3]), 'RFFT stores floor(n/2)+1 coefficients')
            call check_fft(r, reshape(expected, [9]), nx, 5, 'RFFT sign and odd-length half spectrum')
            b = mlx_from(cmplx(expected, kind=real32))
            r = mlx_irfft(b, 1, n=5, norm=norm)
            call mlx_to(got, r)
            bound = 1.d-5*log(5.d0)/log(2.d0)*sqrt(sum(abs(expected)**2))
            call assert_true(sqrt(sum((real(got, real64)-real(x, real64))**2)) <= bound, &
                &'IRFFT independent DFT input, explicit odd n and normalization')
        end do
        even = x(:4, :)
        a = mlx_from(even)
        do j = 1, 3
            spectrum(:4) = dft(cmplx(real(even(:, j), real64), 0.d0, real64), 4, .false., MLX_FFT_NORMS%backward)
            expected4(:, j) = spectrum(:3)
        end do
        b = mlx_from(cmplx(expected4, kind=real32))
        r = mlx_irfft(b, 1)
        call assert_true(all(r%shape() == [4, 3]), 'IRFFT default length is twice last stored frequency index')
        call mlx_to(got4, r)
        call assert_true(sqrt(sum((real(got4, real64)-real(even, real64))**2)) <= 2.d-5*nx, 'IRFFT backward is 1/n')
        if( mlx_default_device() == MLX_DEVICES%cpu )then
            a = mlx_from(real(even, real64))
            r = mlx_rfft(a, 1)
            call check_fft(r, reshape(expected4, [9]), nx, 4, 'CPU float64 FFT uses documented float32 bound')
        endif
    end subroutine test_real_fft
end module mlxf_fft_tester
