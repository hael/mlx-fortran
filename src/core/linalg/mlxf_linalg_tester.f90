!@descr: independent two-device checks of linalg values and Fortran conventions
module mlxf_linalg_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, real, &
                           cmplx, reshape, sum, matmul
use mlxf_test_utils, only: assert_true, test_devices, device_name
implicit none
private
public :: run_all_linalg_tests

contains

    subroutine run_all_linalg_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all linalg tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_matmul
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_linalg_tests

    ! batched, broadcast real and complex matmul against Fortran's intrinsic on non-square shapes
    subroutine test_matmul
        type(mlx_array) :: a, b, r
        real(real64)    :: x(3, 2, 2, 1), y(2, 4, 1, 3), expected(3, 4, 2, 3), bound(3, 4, 2, 3), got64(3, 4, 2, 3), tol
        real(real32)    :: got(3, 4, 2, 3)
        complex(real32) :: cx(3, 2), cy(2, 4), cz(3, 4)
        complex(real64) :: wx(3, 2), wy(2, 4), wz(3, 4)
        integer         :: i, j, k, l, pass, passes
        write(*,'(a)') 'test_matmul'
        x = reshape([(real(i, real64)/17, i=1, 12)], shape(x))
        y = reshape([(real(i, real64)/13-1, i=1, 24)], shape(y))
        do l = 1, 3
            do k = 1, 2
                expected(:,:, k, l) = matmul(x(:,:, k, 1), y(:,:, 1, l))
                bound(:,:, k, l) = matmul(abs(x(:,:, k, 1)), abs(y(:,:, 1, l)))
            end do
        end do
        passes = 1
        if( mlx_default_device() == MLX_DEVICES%cpu ) passes = 2
        do pass = 1, passes
            tol = 1.d-5
            if( pass == 1 )then
                a = mlx_from(real(x, real32))
                b = mlx_from(real(y, real32))
            else
                a = mlx_from(x)
                b = mlx_from(y)
                tol = 1.d-12
            endif
            r = matmul(a, b)
            call assert_true(all(r%shape() == [3, 4, 2, 3]), 'matmul broadcasts dimensions three and four')
            if( pass == 1 )then
                call mlx_to(got, r)
                got64 = real(got, real64)
            else
                call mlx_to(got64, r)
            endif
            call assert_true(all(abs(got64-expected) <= tol*bound), 'matmul(a,b) matches Fortran intrinsic operand order')
        end do
        cx = cmplx(real(x(:,:, 1, 1), real32), 0.25_real32, real32)
        cy = cmplx(real(y(:,:, 1, 1), real32), -0.125_real32, real32)
        wx = cmplx(cx, kind=real64)
        wy = cmplx(cy, kind=real64)
        wz = matmul(wx, wy)
        a = mlx_from(cx)
        b = mlx_from(cy)
        r = matmul(a, b)
        call mlx_to(cz, r)
        call assert_true(all(abs(cmplx(cz, kind=real64)-wz) <= 1.d-5*matmul(abs(wx), abs(wy))), &
            &'complex matmul does not conjugate its operands')
        do j = 1, 4
            do i = 1, 3
                call assert_true(abs(cmplx(cz(i, j), kind=real64)-wz(i, j)) <= &
                    &1.d-5*sum(abs(wx(i, :)*wy(:, j))), 'complex dot product reduction bound')
            end do
        end do
    end subroutine test_matmul
end module mlxf_linalg_tester
