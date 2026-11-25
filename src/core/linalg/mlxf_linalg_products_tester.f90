!@descr: the inner, outer, Kronecker, dot and cross products, contractions, Einstein sums, the added matrix product and the Hadamard transform against plain Fortran loops
! Seeded operands on every device, float32 and on the CPU float64 as well. The reference is the product written
! out in real64 loops over Fortran subscripts, so a result in another dimension order has another shape or other
! values. A result is judged by its largest error relative to max(1, the same product of the magnitudes), the
! scale of a sum of products' rounding; a permutation of elements is exact.
module mlxf_linalg_products_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                           mlx_inner, mlx_outer, mlx_kron, mlx_vecdot, mlx_cross, mlx_tensordot, mlx_einsum, mlx_addmm, &
                           mlx_hadamard_transform
use mlxf_test_utils, only: assert_true, test_devices, device_name, bits_equal, judge_error, find_tolerance, &
                           family_seeds, seeded_uniform, seeded_array, shaped_error
use mlxf_test_defs,  only: ELEM_CEILING, PRODUCT_TOLERANCES, elem_tolerance
implicit none
private
public :: run_all_linalg_products_tests

contains

    subroutine run_all_linalg_products_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all linalg_products tests ****'
        call assert_true(all(PRODUCT_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a product is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_inner
            call test_outer
            call test_kron
            call test_vecdot
            call test_cross
            call test_tensordot
            call test_einsum
            call test_einsum_conventions
            call test_addmm
            call test_hadamard_transform
            call test_complex_products
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_linalg_products_tests

    ! float32 on every device, float64 as well on the CPU
    integer function passes()
        passes = 1
        if( mlx_default_device() == MLX_DEVICES%cpu ) passes = 2
    end function passes

    ! one function's error in one dtype against the frozen tolerance of that dtype
    subroutine judge( err, tol, wide, seed )
        real(real64),         intent(in) :: err
        type(elem_tolerance), intent(in) :: tol
        logical,              intent(in) :: wide
        integer,              intent(in) :: seed
        if( wide )then
            call judge_error(err, tol%f64, trim(tol%name), 'float64', seed)
        else
            call judge_error(err, tol%f32, trim(tol%name), 'float32', seed)
        endif
    end subroutine judge

    ! sums over dimension 1 of both operands, a's remaining dimensions before b's; two vectors give a rank-0 sum
    subroutine test_inner
        integer, parameter   :: K = 4
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: r
        real(real64)         :: x(K, 3, 2), y(K, 5), u(K), v(K), ref(3, 2, 5), bound(3, 2, 5), err
        integer              :: s, pass, i, j, l
        logical              :: wide
        write(*,'(a)') 'test_inner'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_inner')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5000*seeds(s)+1), shape(x))
            y = reshape(seeded_uniform(size(y), 5000*seeds(s)+2), shape(y))
            u = seeded_uniform(K, 5000*seeds(s)+3)
            v = seeded_uniform(K, 5000*seeds(s)+4)
            do l = 1, 5
                do j = 1, 2
                    do i = 1, 3
                        ref(i, j, l) = sum(x(:, i, j)*y(:, l))
                        bound(i, j, l) = sum(abs(x(:, i, j)*y(:, l)))
                    end do
                end do
            end do
            do pass = 1, passes()
                wide = pass == 2
                r = mlx_inner(seeded_array(x, wide), seeded_array(y, wide))
                err = shaped_error(r, ref, bound)
                r = mlx_inner(seeded_array(u, wide), seeded_array(v, wide))
                err = max(err, shaped_error(r, sum(u*v), sum(abs(u*v))))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_inner

    ! r(i, j) = a(i)*b(j) over the elements of a (3, 2) array in array element order and of a vector
    subroutine test_outer
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: r
        real(real64)         :: x(3, 2), xf(6), y(4), ref(6, 4), err
        integer              :: s, pass, i, j
        logical              :: wide
        write(*,'(a)') 'test_outer'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_outer')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5100*seeds(s)+1), shape(x))
            y = seeded_uniform(size(y), 5100*seeds(s)+2)
            xf = reshape(x, [6])
            do j = 1, 4
                do i = 1, 6
                    ref(i, j) = xf(i)*y(j)
                end do
            end do
            do pass = 1, passes()
                wide = pass == 2
                r = mlx_outer(seeded_array(x, wide), seeded_array(y, wide))
                err = shaped_error(r, ref, abs(ref))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_outer

    ! every element of a times the whole of b; a vector with a matrix counts as a matrix of one column
    subroutine test_kron
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: r
        real(real64)         :: x(2, 3), y(4, 2), u(3), z(2, 2), ref(8, 6), ref2(6, 2), err
        integer              :: s, pass, i, j, k, l
        logical              :: wide
        write(*,'(a)') 'test_kron'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_kron')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5200*seeds(s)+1), shape(x))
            y = reshape(seeded_uniform(size(y), 5200*seeds(s)+2), shape(y))
            u = seeded_uniform(size(u), 5200*seeds(s)+3)
            z = reshape(seeded_uniform(size(z), 5200*seeds(s)+4), shape(z))
            do j = 1, 3
                do i = 1, 2
                    do l = 1, 2
                        do k = 1, 4
                            ref((i-1)*4+k, (j-1)*2+l) = x(i, j)*y(k, l)
                        end do
                    end do
                end do
            end do
            do i = 1, 3
                ref2((i-1)*2+1:i*2, :) = u(i)*z
            end do
            do pass = 1, passes()
                wide = pass == 2
                r = mlx_kron(seeded_array(x, wide), seeded_array(y, wide))
                err = shaped_error(r, ref, abs(ref))
                r = mlx_kron(seeded_array(u, wide), seeded_array(z, wide))
                err = max(err, shaped_error(r, ref2, abs(ref2)))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_kron

    ! the dot products along dimension 1 by default and along dimensions 2 and 3 when named
    subroutine test_vecdot
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: a, b, r
        real(real64)         :: x(4, 3, 2), y(4, 3, 2), err
        integer              :: s, pass
        logical              :: wide
        write(*,'(a)') 'test_vecdot'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_vecdot')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5300*seeds(s)+1), shape(x))
            y = reshape(seeded_uniform(size(y), 5300*seeds(s)+2), shape(y))
            do pass = 1, passes()
                wide = pass == 2
                a = seeded_array(x, wide)
                b = seeded_array(y, wide)
                r = mlx_vecdot(a, b)
                err = shaped_error(r, sum(x*y, dim=1), sum(abs(x*y), dim=1))
                r = mlx_vecdot(a, b, dim=2)
                err = max(err, shaped_error(r, sum(x*y, dim=2), sum(abs(x*y), dim=2)))
                r = mlx_vecdot(a, b, dim=3)
                err = max(err, shaped_error(r, sum(x*y, dim=3), sum(abs(x*y), dim=3)))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_vecdot

    ! the cross product of two 3-vectors, and the scale of its rounding
    pure function cross3( u, v ) result(c)
        real(real64), intent(in) :: u(3), v(3)
        real(real64) :: c(3)
        c = [u(2)*v(3)-u(3)*v(2), u(3)*v(1)-u(1)*v(3), u(1)*v(2)-u(2)*v(1)]
    end function cross3

    pure function cross3_bound( u, v ) result(c)
        real(real64), intent(in) :: u(3), v(3)
        real(real64) :: c(3)
        c = [abs(u(2)*v(3))+abs(u(3)*v(2)), abs(u(3)*v(1))+abs(u(1)*v(3)), abs(u(1)*v(2))+abs(u(2)*v(1))]
    end function cross3_bound

    ! cross products along dimension 1 by default and along dimension 2 when named, of a batch with one vector of a
    ! lower rank on either side, and of 2-vectors, whose third component counts as zero
    subroutine test_cross
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: r
        real(real64)         :: x(3, 5), y(3, 5), p(4, 3), q(4, 3), w(3), g(2, 4), h(2, 4)
        real(real64)         :: ref(3, 5), bound(3, 5), ref2(4, 3), bound2(4, 3), ref3(3, 5), bound3(3, 5)
        real(real64)         :: ref4(3, 5), ref5(3, 4), bound5(3, 4), err
        integer              :: s, pass, j
        logical              :: wide
        write(*,'(a)') 'test_cross'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_cross')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5400*seeds(s)+1), shape(x))
            y = reshape(seeded_uniform(size(y), 5400*seeds(s)+2), shape(y))
            p = reshape(seeded_uniform(size(p), 5400*seeds(s)+3), shape(p))
            q = reshape(seeded_uniform(size(q), 5400*seeds(s)+4), shape(q))
            w = seeded_uniform(size(w), 5400*seeds(s)+5)
            g = reshape(seeded_uniform(size(g), 5400*seeds(s)+6), shape(g))
            h = reshape(seeded_uniform(size(h), 5400*seeds(s)+7), shape(h))
            do j = 1, 5
                ref(:, j) = cross3(x(:, j), y(:, j))
                bound(:, j) = cross3_bound(x(:, j), y(:, j))
                ref3(:, j) = cross3(x(:, j), w)
                bound3(:, j) = cross3_bound(x(:, j), w)
                ref4(:, j) = cross3(w, x(:, j))
            end do
            do j = 1, 4
                ref2(j, :) = cross3(p(j, :), q(j, :))
                bound2(j, :) = cross3_bound(p(j, :), q(j, :))
                ref5(:, j) = [0._real64, 0._real64, g(1, j)*h(2, j)-g(2, j)*h(1, j)]
                bound5(:, j) = [0._real64, 0._real64, abs(g(1, j)*h(2, j))+abs(g(2, j)*h(1, j))]
            end do
            do pass = 1, passes()
                wide = pass == 2
                r = mlx_cross(seeded_array(x, wide), seeded_array(y, wide))
                err = shaped_error(r, ref, bound)
                r = mlx_cross(seeded_array(p, wide), seeded_array(q, wide), dim=2)
                err = max(err, shaped_error(r, ref2, bound2))
                r = mlx_cross(seeded_array(x, wide), seeded_array(w, wide))
                err = max(err, shaped_error(r, ref3, bound3))
                r = mlx_cross(seeded_array(w, wide), seeded_array(x, wide))
                err = max(err, shaped_error(r, ref4, bound3))
                r = mlx_cross(seeded_array(g, wide), seeded_array(h, wide))
                err = max(err, shaped_error(r, ref5, bound5))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_cross

    ! contractions of the last n dimensions of a with the first n of b (two by default, one, none) and of listed
    ! pairs of dimensions; the remaining dimensions of a come before those of b
    subroutine test_tensordot
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: r
        real(real64)         :: a(3, 4, 5), b(4, 5, 2), c(3, 4), v(2), d(5, 2, 3), e(4, 6)
        real(real64)         :: ref2(3, 2), bound2(3, 2), ref1(3, 5, 2), bound1(3, 5, 2), ref0(3, 4, 2)
        real(real64)         :: refd(4, 2), boundd(4, 2), refe(3, 5, 6), bounde(3, 5, 6), err
        integer              :: s, pass, i, j, k, l
        logical              :: wide
        write(*,'(a)') 'test_tensordot'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_tensordot')
        seeds = family_seeds()
        do s = 1, size(seeds)
            a = reshape(seeded_uniform(size(a), 5500*seeds(s)+1), shape(a))
            b = reshape(seeded_uniform(size(b), 5500*seeds(s)+2), shape(b))
            c = reshape(seeded_uniform(size(c), 5500*seeds(s)+3), shape(c))
            v = seeded_uniform(size(v), 5500*seeds(s)+4)
            d = reshape(seeded_uniform(size(d), 5500*seeds(s)+5), shape(d))
            e = reshape(seeded_uniform(size(e), 5500*seeds(s)+6), shape(e))
            do l = 1, 2
                do i = 1, 3
                    ref2(i, l) = sum(a(i, :, :)*b(:, :, l))
                    bound2(i, l) = sum(abs(a(i, :, :)*b(:, :, l)))
                    do k = 1, 5
                        ref1(i, k, l) = sum(c(i, :)*b(:, k, l))
                        bound1(i, k, l) = sum(abs(c(i, :)*b(:, k, l)))
                    end do
                    ref0(i, :, l) = c(i, :)*v(l)
                end do
                do j = 1, 4
                    refd(j, l) = sum(a(:, j, :)*transpose(d(:, l, :)))
                    boundd(j, l) = sum(abs(a(:, j, :)*transpose(d(:, l, :))))
                end do
            end do
            do l = 1, 6
                do k = 1, 5
                    do i = 1, 3
                        refe(i, k, l) = sum(a(i, :, k)*e(:, l))
                        bounde(i, k, l) = sum(abs(a(i, :, k)*e(:, l)))
                    end do
                end do
            end do
            do pass = 1, passes()
                wide = pass == 2
                r = mlx_tensordot(seeded_array(a, wide), seeded_array(b, wide))
                err = shaped_error(r, ref2, bound2)
                r = mlx_tensordot(seeded_array(c, wide), seeded_array(b, wide), n=1)
                err = max(err, shaped_error(r, ref1, bound1))
                r = mlx_tensordot(seeded_array(c, wide), seeded_array(v, wide), n=0)
                err = max(err, shaped_error(r, ref0, abs(ref0)))
                r = mlx_tensordot(seeded_array(a, wide), seeded_array(d, wide), [1, 3], [3, 1])
                err = max(err, shaped_error(r, refd, boundd))
                r = mlx_tensordot(seeded_array(a, wide), seeded_array(e, wide), [2], [1])
                err = max(err, shaped_error(r, refe, bounde))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_tensordot

    ! Einstein sums with the result named and not: a matrix product, the product in the other alphabetical order, a
    ! scalar product of matrices, a capital letter before a small one in the unnamed result, a trace, a bilinear form
    ! of three operands, and a batch through the ellipsis
    subroutine test_einsum
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: a, b, c, r
        real(real64)         :: x(3, 4), y(4, 5), w(3, 4), sq(4, 4), u(3), v(4), z(3, 4, 2), t(4, 5, 2)
        real(real64)         :: ref(3, 5), bound(3, 5), ref3(3, 5, 2), bound3(3, 5, 2), trace, trace_bound, err
        integer              :: s, pass, i, k
        logical              :: wide
        write(*,'(a)') 'test_einsum'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_einsum')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5600*seeds(s)+1), shape(x))
            y = reshape(seeded_uniform(size(y), 5600*seeds(s)+2), shape(y))
            w = reshape(seeded_uniform(size(w), 5600*seeds(s)+3), shape(w))
            sq = reshape(seeded_uniform(size(sq), 5600*seeds(s)+4), shape(sq))
            u = seeded_uniform(size(u), 5600*seeds(s)+5)
            v = seeded_uniform(size(v), 5600*seeds(s)+6)
            z = reshape(seeded_uniform(size(z), 5600*seeds(s)+7), shape(z))
            t = reshape(seeded_uniform(size(t), 5600*seeds(s)+8), shape(t))
            ref = matmul(x, y)
            bound = matmul(abs(x), abs(y))
            do k = 1, 2
                ref3(:, :, k) = matmul(z(:, :, k), t(:, :, k))
                bound3(:, :, k) = matmul(abs(z(:, :, k)), abs(t(:, :, k)))
            end do
            trace = 0._real64
            trace_bound = 0._real64
            do i = 1, 4
                trace = trace+sq(i, i)
                trace_bound = trace_bound+abs(sq(i, i))
            end do
            do pass = 1, passes()
                wide = pass == 2
                a = seeded_array(x, wide)
                b = seeded_array(y, wide)
                r = mlx_einsum('ij,jk->ik', [a, b])
                err = shaped_error(r, ref, bound)
                r = mlx_einsum(' ij , jk ', [a, b])
                err = max(err, shaped_error(r, ref, bound))
                r = mlx_einsum('ki,ij', [a, b])
                err = max(err, shaped_error(r, transpose(ref), transpose(bound)))
                b = seeded_array(w, wide)
                r = mlx_einsum('ij,ij->', [a, b])
                err = max(err, shaped_error(r, sum(x*w), sum(abs(x*w))))
                r = mlx_einsum('ja,jB', [a, b])
                err = max(err, shaped_error(r, matmul(transpose(w), x), matmul(transpose(abs(w)), abs(x))))
                b = seeded_array(sq, wide)
                r = mlx_einsum('ii', [b])
                err = max(err, shaped_error(r, trace, trace_bound))
                b = seeded_array(u, wide)
                c = seeded_array(v, wide)
                r = mlx_einsum('i,ij,j->', [b, a, c])
                err = max(err, shaped_error(r, dot_product(u, matmul(x, v)), dot_product(abs(u), matmul(abs(x), abs(v)))))
                a = seeded_array(z, wide)
                b = seeded_array(t, wide)
                r = mlx_einsum('ij...,jk...->ik...', [a, b])
                err = max(err, shaped_error(r, ref3, bound3))
                r = mlx_einsum('ij...,jk...', [a, b])
                err = max(err, shaped_error(r, ref3, bound3))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_einsum

    ! by name: a subscript is a Fortran dimension, so 'ij->ji' is the transpose and 'ii->i' the diagonal, exactly,
    ! and 'ij->j' sums over dimension 1
    subroutine test_einsum_conventions
        type(mlx_array) :: a, r
        real(real32)    :: x(3, 4), xt(4, 3), sq(4, 4), diag(4), cols(4)
        integer         :: i
        write(*,'(a)') 'test_einsum_conventions'
        x = real(reshape(seeded_uniform(size(x), 7201), shape(x)), real32)
        sq = real(reshape(seeded_uniform(size(sq), 7202), shape(sq)), real32)
        a = mlx_from(x)
        r = mlx_einsum('ij->ji', [a])
        call assert_true(all(r%shape() == [4, 3]), 'mlx_einsum ''ij->ji'' of a (3, 4) array is (4, 3)')
        call mlx_to(xt, r)
        call assert_true(all(bits_equal(xt, transpose(x))), 'mlx_einsum ''ij->ji'' is the transpose, bit for bit')
        r = mlx_einsum('ij->j', [a])
        call assert_true(all(r%shape() == [4]), 'mlx_einsum ''ij->j'' keeps dimension 2')
        call mlx_to(cols, r)
        call assert_true(all(abs(cols-sum(x, dim=1)) <= 4*epsilon(1._real32)*max(1._real32, sum(abs(x), dim=1))), &
            &'mlx_einsum ''ij->j'' sums over dimension 1, the first subscript')
        a = mlx_from(sq)
        r = mlx_einsum('ii->i', [a])
        call mlx_to(diag, r)
        call assert_true(all(bits_equal(diag, [(sq(i, i), i=1, 4)])), 'mlx_einsum ''ii->i'' is the diagonal, bit for bit')
    end subroutine test_einsum_conventions

    ! alpha*matmul(a, b) + beta*c: with both factors, with the defaults, with c a vector broadcast along the columns,
    ! over a batch of products, and with a vector as a (a row) and as b (a column)
    subroutine test_addmm
        integer,      parameter :: M = 3, K = 4, N = 5
        real(real64), parameter :: ALPHA = 0.5_real64, BETA = -2._real64
        integer, allocatable    :: seeds(:)
        type(elem_tolerance)    :: tol
        type(mlx_array)         :: a, b, c, r
        real(real64)            :: x(M, K, 2), y(K, N, 2), z(M, N), zv(M), ref(M, N), bound(M, N), ref3(M, N, 2)
        real(real64)            :: bound3(M, N, 2), err
        integer                 :: s, pass, j
        logical                 :: wide
        write(*,'(a)') 'test_addmm'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_addmm')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5700*seeds(s)+1), shape(x))
            y = reshape(seeded_uniform(size(y), 5700*seeds(s)+2), shape(y))
            z = reshape(seeded_uniform(size(z), 5700*seeds(s)+3), shape(z))
            zv = seeded_uniform(size(zv), 5700*seeds(s)+4)
            do pass = 1, passes()
                wide = pass == 2
                a = seeded_array(x(:, :, 1), wide)
                b = seeded_array(y(:, :, 1), wide)
                c = seeded_array(z, wide)
                r = mlx_addmm(c, a, b, alpha=real(ALPHA, real32), beta=real(BETA, real32))
                ref = ALPHA*matmul(x(:, :, 1), y(:, :, 1))+BETA*z
                bound = abs(ALPHA)*matmul(abs(x(:, :, 1)), abs(y(:, :, 1)))+abs(BETA*z)
                err = shaped_error(r, ref, bound)
                r = mlx_addmm(c, a, b)
                ref = matmul(x(:, :, 1), y(:, :, 1))+z
                bound = matmul(abs(x(:, :, 1)), abs(y(:, :, 1)))+abs(z)
                err = max(err, shaped_error(r, ref, bound))
                r = mlx_addmm(seeded_array(zv, wide), a, b, beta=real(BETA, real32))
                do j = 1, N
                    ref(:, j) = matmul(x(:, :, 1), y(:, j, 1))+BETA*zv
                    bound(:, j) = matmul(abs(x(:, :, 1)), abs(y(:, j, 1)))+abs(BETA*zv)
                end do
                err = max(err, shaped_error(r, ref, bound))
                r = mlx_addmm(c, seeded_array(x, wide), seeded_array(y, wide), alpha=real(ALPHA, real32))
                do j = 1, 2
                    ref3(:, :, j) = ALPHA*matmul(x(:, :, j), y(:, :, j))+z
                    bound3(:, :, j) = abs(ALPHA)*matmul(abs(x(:, :, j)), abs(y(:, :, j)))+abs(z)
                end do
                err = max(err, shaped_error(r, ref3, bound3))
                r = mlx_addmm(seeded_array(z(1, :), wide), seeded_array(x(1, :, 1), wide), b)
                err = max(err, shaped_error(r, matmul(x(1, :, 1), y(:, :, 1))+z(1, :), matmul(abs(x(1, :, 1)), abs(y(:, :, 1)))+abs(z(1, :))))
                r = mlx_addmm(seeded_array(zv, wide), a, seeded_array(y(:, 1, 1), wide))
                err = max(err, shaped_error(r, matmul(x(:, :, 1), y(:, 1, 1))+zv, matmul(abs(x(:, :, 1)), abs(y(:, 1, 1)))+abs(zv)))
                call judge(err, tol, wide, seeds(s))
            end do
        end do
    end subroutine test_addmm

    ! the Walsh-Hadamard transform along dimension 1 (extent 8; dimension 2, of extent 3, cannot be transformed):
    ! the Sylvester matrix over the square root of 8 by default, the matrix itself with a scale of 1, and twice the
    ! default transform is the identity. In float32 only: MLX evaluates no float64 transform
    subroutine test_hadamard_transform
        integer, parameter   :: N = 8
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol
        type(mlx_array)      :: a, r
        real(real64)         :: x(N, 3), h(N, N), ref(N, 3), bound(N, 3), err
        integer              :: s, i, j
        write(*,'(a)') 'test_hadamard_transform'
        tol = find_tolerance(PRODUCT_TOLERANCES, 'mlx_hadamard_transform')
        do j = 1, N
            do i = 1, N
                h(i, j) = real(1-2*modulo(popcnt(iand(i-1, j-1)), 2), real64)
            end do
        end do
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 5800*seeds(s)+1), shape(x))
            a = seeded_array(x, .false.)
            ref = matmul(h, x)/sqrt(real(N, real64))
            bound = matmul(abs(h), abs(x))/sqrt(real(N, real64))
            r = mlx_hadamard_transform(a)
            err = shaped_error(r, ref, bound)
            r = mlx_hadamard_transform(r)
            err = max(err, shaped_error(r, x, matmul(abs(h), bound)/sqrt(real(N, real64))))
            r = mlx_hadamard_transform(a, scale=1._real32)
            err = max(err, shaped_error(r, matmul(h, x), matmul(abs(h), abs(x))))
            call judge(err, tol, .false., seeds(s))
        end do
    end subroutine test_hadamard_transform

    ! by name, on complex operands whose products are exact in float32: mlx_vecdot conjugates its first operand, as
    ! dot_product does, and mlx_inner does not
    subroutine test_complex_products
        type(mlx_array) :: a, b, r
        complex(real32) :: x(2), y(2), got(1)
        write(*,'(a)') 'test_complex_products'
        x = [cmplx(1., 2., real32), cmplx(0., 1., real32)]
        y = [cmplx(3., -1., real32), cmplx(2., 4., real32)]
        a = mlx_from(x)
        b = mlx_from(y)
        r = mlx_vecdot(a, b)
        call mlx_to(got, r)
        call assert_true(bits_equal(got(1), dot_product(x, y)), 'mlx_vecdot conjugates its first operand: Fortran''s dot_product')
        r = mlx_inner(a, b)
        call mlx_to(got, r)
        call assert_true(bits_equal(got(1), sum(x*y)), 'mlx_inner does not conjugate')
        call assert_true(.not. bits_equal(dot_product(x, y), sum(x*y)), 'the two differ on this fixture')
    end subroutine test_complex_products

end module mlxf_linalg_products_tester
