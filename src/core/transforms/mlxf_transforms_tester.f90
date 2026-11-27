!@descr: the function transforms against closed-form derivatives: gradients, vector-Jacobian and Jacobian-vector products, custom rules
! Three fixed functions on seeded operands: a polynomial, exp(a x) and a chain of two matrix products. Each
! derivative is written out in real64 from its closed form, never by differences, and a result is judged by its
! largest error relative to max(1, a sum of magnitudes that bounds it, or its own magnitude). Custom rules,
! positions among the inputs, the results' shapes and the refusals are exact.
module mlxf_transforms_tester
use, intrinsic :: iso_fortran_env, only: real32, real64, int64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
use mlxf,             only: mlx_array, mlx_function, mlx_grad_function, mlx_value_and_grad, mlx_vjp, mlx_jvp, &
                            mlx_custom_vjp, mlx_custom_function, mlx_checkpoint, mlx_depends, mlx_stop_gradient, &
                            mlx_compile, mlx_from, mlx_to, mlx_live_count, mlx_last_error, mlx_set_default_device, &
                            mlx_default_device, MLX_DEVICES, sum, exp, matmul, mlx_eval, mlx_synchronize, &
                            mlx_active_memory, mlx_function_exporter, mlx_imported_function, norm2, mlx_mean
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name, bits_equal, judge_error, &
                            find_tolerance, family_seeds, seeded_uniform, seeded_array, shaped_error
use mlxf_test_defs,   only: ELEM_CEILING, GRAD_TOLERANCES, elem_tolerance
use mlxf_test_reduce, only: nan_max
implicit none
private
public :: run_all_transforms_tests

! the extents of the fixtures: the vectors, and the chain a(M, K) b(K, N) v(N)
integer, parameter :: NV = 48, M = 4, K = 3, N = 5

contains

    subroutine run_all_transforms_tests
        integer, allocatable :: devs(:), seeds(:)
        integer              :: i, s, original, live0
        write(*,'(a)') '**** running all transforms tests ****'
        call assert_true(all(GRAD_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a transform is within the ceiling of 64 float32 epsilons')
        call test_empty_grad_functions_parallel
        call test_devices(devs)
        original = mlx_default_device()
        seeds = family_seeds()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            do s = 1, size(seeds)
                call test_value_and_grad(seeds(s), .false.)
                call test_products(seeds(s), .false.)
                call test_scaled_gradients(seeds(s), .false.)
                if( devs(i) == MLX_DEVICES%cpu )then
                    call test_scaled_gradients(seeds(s), .true.)
                    call test_value_and_grad(seeds(s), .true.)
                    call test_products(seeds(s), .true.)
                endif
            end do
            call test_positions_and_outputs
            call test_custom_rules
            call test_stop_gradient_and_depends
            call test_lifecycle_and_failures
            call test_higher_order
            call test_no_leak
            call assert_int(live0, mlx_live_count(), 'functions, their transforms and their arrays leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_transforms_tests

    ! copying, killing and finalizing empty gradient functions inside an OpenMP region does not stop
    subroutine test_empty_grad_functions_parallel
        integer :: i, completed(8)
        write(*,'(a)') 'test_empty_grad_functions_parallel'
        completed = 0
        !$omp parallel do num_threads(2) default(shared) private(i) schedule(static) proc_bind(close)
        do i = 1, size(completed)
            call empty_grad_scope
            completed(i) = 1
        end do
        !$omp end parallel do
        call assert_true(all(completed == 1), 'empty gradient functions, exporters and imported functions are copied, killed and finalized safely in parallel')
    end subroutine test_empty_grad_functions_parallel

    ! an empty gradient function copied, killed and finalized on leaving the scope
    subroutine empty_grad_scope
        type(mlx_grad_function)     :: g, copy
        type(mlx_function_exporter) :: e, ecopy
        type(mlx_imported_function) :: h, hcopy
        copy = g
        call copy%kill()
        ecopy = e
        call ecopy%kill()
        hcopy = h
        call hcopy%kill()
    end subroutine empty_grad_scope

    ! the gradients of the scaled reductions, whose graphs hold a stopped scale: norm2's is x/norm2(x) and the
    ! mean's 1/n, judged by the frozen tolerance of mlx_value_and_grad; norm2's also for x scaled by 1e20 in float32
    ! (1e200 in float64), where the plain norm's square overflowed. At zero neither norm has a derivative: the
    ! gradient there is printed, not judged
    subroutine test_scaled_gradients( seed, wide )
        integer, intent(in) :: seed
        logical, intent(in) :: wide
        type(mlx_function)           :: f
        type(mlx_grad_function)      :: g
        type(mlx_array)              :: x
        type(mlx_array), allocatable :: values(:), grads(:)
        type(elem_tolerance)         :: tol
        real(real64)                 :: xs(NV), err, limit, nrm, big
        real(real32)                 :: gz(NV)
        write(*,'(a,i0,a,l1)') 'test_scaled_gradients seed=', seed, ' wide=', wide
        tol = find_tolerance(GRAD_TOLERANCES, 'mlx_value_and_grad')
        limit = merge(tol%f64, tol%f32, wide)
        err = 0._real64
        xs = seeded_uniform(NV, seed+500)
        nrm = sqrt(sum(xs**2))
        f = mlx_function(norm_value)
        g = mlx_value_and_grad(f)
        x = seeded_array(xs, wide)
        call g%apply([x], values, grads)
        err = nan_max(err, shaped_error(values(1), nrm, nrm))
        err = nan_max(err, shaped_error(grads(1), xs/nrm, abs(xs)/nrm))
        big = merge(1.e200_real64, 1.e20_real64, wide)
        x = seeded_array(xs*big, wide)
        call g%apply([x], values, grads)
        err = nan_max(err, shaped_error(values(1)*(1._real64/big), nrm, nrm))
        err = nan_max(err, shaped_error(grads(1), xs/nrm, abs(xs)/nrm))
        f = mlx_function(mean_value)
        g = mlx_value_and_grad(f)
        x = seeded_array(xs, wide)
        call g%apply([x], values, grads)
        err = nan_max(err, shaped_error(values(1), sum(xs)/NV, sum(abs(xs))/NV))
        err = nan_max(err, shaped_error(grads(1), spread(1._real64/NV, 1, NV), spread(1._real64/NV, 1, NV)))
        call judge_error(err, limit, 'scaled norm2 and mean gradients', merge('float64', 'float32', wide), seed)
        if( .not. wide .and. seed == 1 )then
            f = mlx_function(norm_value)
            g = mlx_value_and_grad(f)
            x = seeded_array(spread(0._real64, 1, NV), wide)
            call g%apply([x], values, grads)
            call mlx_to(gz, grads(1))
            write(*,'(a,l1)') '    the gradient of norm2 at zero is finite: ', all(ieee_is_finite(gz))
        endif
    end subroutine test_scaled_gradients

    ! values and gradients of the three functions; float64 operands (wide) for the polynomial and the chain,
    ! which MLX computes in float64 on the CPU device
    subroutine test_value_and_grad( seed, wide )
        integer, intent(in) :: seed
        logical, intent(in) :: wide
        type(mlx_function)           :: f
        type(mlx_grad_function)      :: g
        type(mlx_array)              :: x, a, b, v
        type(mlx_array), allocatable :: values(:), grads(:)
        type(elem_tolerance)         :: tol
        real(real64)                 :: xs(NV), as(NV), am(M, K), bm(K, N), vv(N), ones(M), err, limit
        real(real64)                 :: da(M, K), db(K, N), dv(N)
        integer                      :: i, j
        write(*,'(a,i0,a,l1)') 'test_value_and_grad seed=', seed, ' wide=', wide
        tol = find_tolerance(GRAD_TOLERANCES, 'mlx_value_and_grad')
        limit = merge(tol%f64, tol%f32, wide)
        err = 0._real64
        xs = seeded_uniform(NV, seed)
        as = seeded_uniform(NV, seed+100)
        am = reshape(seeded_uniform(M*K, seed+200), [M, K])
        bm = reshape(seeded_uniform(K*N, seed+300), [K, N])
        vv = seeded_uniform(N, seed+400)
        x = seeded_array(xs, wide)
        f = mlx_function(poly_sum)
        g = mlx_value_and_grad(f)
        call g%apply([x], values, grads)
        call assert_int(1, size(grads), 'one gradient for the one input a polynomial is differentiated by')
        err = nan_max(err, shaped_error(values(1), sum(poly(xs)), sum(poly_magnitude(xs))))
        err = nan_max(err, shaped_error(grads(1), poly_slope(xs), poly_slope_magnitude(xs)))
        if( .not. wide )then
            a = seeded_array(as, wide)
            f = mlx_function(exp_sum)
            g = mlx_value_and_grad(f, [1, 2])
            call g%apply([a, x], values, grads)
            call assert_int(2, size(grads), 'two gradients for argnums [1, 2]')
            err = nan_max(err, shaped_error(values(1), sum(exp(as*xs)), sum(exp(as*xs))))
            err = nan_max(err, shaped_error(grads(1), xs*exp(as*xs), abs(xs)*exp(as*xs)))
            err = nan_max(err, shaped_error(grads(2), as*exp(as*xs), abs(as)*exp(as*xs)))
        endif
        a = seeded_array(am, wide)
        b = seeded_array(bm, wide)
        v = seeded_array(vv, wide)
        f = mlx_function(chain_sum)
        g = mlx_value_and_grad(f, [1, 2, 3])
        call g%apply([a, b, v], values, grads)
        call assert_int(3, size(grads), 'three gradients for argnums [1, 2, 3]')
        ones = 1._real64
        do j = 1, K
            do i = 1, M
                da(i, j) = dot_product(bm(j, :), vv)
            end do
        end do
        do j = 1, N
            do i = 1, K
                db(i, j) = sum(am(:, i))*vv(j)
            end do
        end do
        dv = matmul(transpose(bm), matmul(transpose(am), ones))
        err = nan_max(err, shaped_error(values(1), sum(matmul(am, matmul(bm, vv))), sum(matmul(abs(am), matmul(abs(bm), abs(vv))))))
        err = nan_max(err, shaped_error(grads(1), da, spread(matmul(abs(bm), abs(vv)), 1, M)))
        err = nan_max(err, shaped_error(grads(2), db, abs(db)))
        err = nan_max(err, shaped_error(grads(3), dv, matmul(transpose(abs(bm)), matmul(transpose(abs(am)), ones))))
        call judge_error(err, limit, 'mlx_value_and_grad', merge('float64', 'float32', wide), seed)
    end subroutine test_value_and_grad

    ! vector-Jacobian and Jacobian-vector products of the three functions in their array-valued forms
    subroutine test_products( seed, wide )
        integer, intent(in) :: seed
        logical, intent(in) :: wide
        type(mlx_function)           :: f
        type(mlx_array)              :: x, a, b, v, w, ta, tb, tv
        type(mlx_array), allocatable :: outputs(:), products(:)
        type(elem_tolerance)         :: tolv, tolj
        real(real64)                 :: xs(NV), as(NV), ws(NV), ts(NV), us(NV), e(NV), errv, errj
        real(real64)                 :: am(M, K), bm(K, N), vv(N), wm(M), tam(M, K), tbm(K, N), tvv(N), y(M), ybound(M)
        real(real64)                 :: da(M, K), db(K, N), dv(N), jv(M), jbound(M)
        integer                      :: i, j
        write(*,'(a,i0,a,l1)') 'test_products seed=', seed, ' wide=', wide
        tolv = find_tolerance(GRAD_TOLERANCES, 'mlx_vjp')
        tolj = find_tolerance(GRAD_TOLERANCES, 'mlx_jvp')
        errv = 0._real64
        errj = 0._real64
        xs = seeded_uniform(NV, seed)
        as = seeded_uniform(NV, seed+100)
        ws = seeded_uniform(NV, seed+500)
        ts = seeded_uniform(NV, seed+600)
        us = seeded_uniform(NV, seed+700)
        x = seeded_array(xs, wide)
        w = seeded_array(ws, wide)
        tv = seeded_array(ts, wide)
        f = mlx_function(poly_each)
        call mlx_vjp(f, [x], [w], outputs, products)
        errv = nan_max(errv, shaped_error(outputs(1), poly(xs), poly_magnitude(xs)))
        errv = nan_max(errv, shaped_error(products(1), ws*poly_slope(xs), abs(ws)*poly_slope_magnitude(xs)))
        call mlx_jvp(f, [x], [tv], outputs, products)
        errj = nan_max(errj, shaped_error(outputs(1), poly(xs), poly_magnitude(xs)))
        errj = nan_max(errj, shaped_error(products(1), ts*poly_slope(xs), abs(ts)*poly_slope_magnitude(xs)))
        if( .not. wide )then
            a = seeded_array(as, wide)
            ta = seeded_array(us, wide)
            e = exp(as*xs)
            f = mlx_function(exp_each)
            call mlx_vjp(f, [a, x], [w], outputs, products)
            call assert_int(2, size(products), 'a vector-Jacobian product has one array per input')
            errv = nan_max(errv, shaped_error(outputs(1), e, e))
            errv = nan_max(errv, shaped_error(products(1), ws*xs*e, abs(ws*xs)*e))
            errv = nan_max(errv, shaped_error(products(2), ws*as*e, abs(ws*as)*e))
            call mlx_jvp(f, [a, x], [ta, tv], outputs, products)
            call assert_int(1, size(products), 'a Jacobian-vector product has one array per output')
            errj = nan_max(errj, shaped_error(products(1), e*(xs*us+as*ts), e*(abs(xs*us)+abs(as*ts))))
        endif
        am = reshape(seeded_uniform(M*K, seed+200), [M, K])
        bm = reshape(seeded_uniform(K*N, seed+300), [K, N])
        vv = seeded_uniform(N, seed+400)
        wm = seeded_uniform(M, seed+800)
        tam = reshape(seeded_uniform(M*K, seed+900), [M, K])
        tbm = reshape(seeded_uniform(K*N, seed+1000), [K, N])
        tvv = seeded_uniform(N, seed+1100)
        a = seeded_array(am, wide)
        b = seeded_array(bm, wide)
        v = seeded_array(vv, wide)
        w = seeded_array(wm, wide)
        y = matmul(am, matmul(bm, vv))
        ybound = matmul(abs(am), matmul(abs(bm), abs(vv)))
        do j = 1, K
            do i = 1, M
                da(i, j) = wm(i)*dot_product(bm(j, :), vv)
            end do
        end do
        do j = 1, N
            do i = 1, K
                db(i, j) = dot_product(am(:, i), wm)*vv(j)
            end do
        end do
        dv = matmul(transpose(bm), matmul(transpose(am), wm))
        f = mlx_function(chain_each)
        call mlx_vjp(f, [a, b, v], [w], outputs, products)
        call assert_int(3, size(products), 'the chain''s vector-Jacobian product has three arrays')
        errv = nan_max(errv, shaped_error(outputs(1), y, ybound))
        errv = nan_max(errv, shaped_error(products(1), da, abs(da)))
        errv = nan_max(errv, shaped_error(products(2), db, matmul(reshape(matmul(transpose(abs(am)), abs(wm)), [K, 1]), reshape(abs(vv), [1, N]))))
        errv = nan_max(errv, shaped_error(products(3), dv, matmul(transpose(abs(bm)), matmul(transpose(abs(am)), abs(wm)))))
        ta = seeded_array(tam, wide)
        tb = seeded_array(tbm, wide)
        tv = seeded_array(tvv, wide)
        jv = matmul(tam, matmul(bm, vv))+matmul(am, matmul(tbm, vv))+matmul(am, matmul(bm, tvv))
        jbound = matmul(abs(tam), matmul(abs(bm), abs(vv)))+matmul(abs(am), matmul(abs(tbm), abs(vv)))+matmul(abs(am), matmul(abs(bm), abs(tvv)))
        call mlx_jvp(f, [a, b, v], [ta, tb, tv], outputs, products)
        errj = nan_max(errj, shaped_error(outputs(1), y, ybound))
        errj = nan_max(errj, shaped_error(products(1), jv, jbound))
        call judge_error(errv, merge(tolv%f64, tolv%f32, wide), 'mlx_vjp', merge('float64', 'float32', wide), seed)
        call judge_error(errj, merge(tolj%f64, tolj%f32, wide), 'mlx_jvp', merge('float64', 'float32', wide), seed)
    end subroutine test_products

    ! argnums are one-based positions among the inputs; every output of the function comes back in values
    subroutine test_positions_and_outputs
        type(mlx_function)           :: f, f3
        type(mlx_grad_function)      :: g
        type(mlx_array)              :: p, q, a3, b3, v3
        type(mlx_array), allocatable :: values(:), grads(:)
        real(real32)                 :: x(3), y(3), got(3), total(1)
        integer                      :: st, i
        write(*,'(a)') 'test_positions_and_outputs'
        x = [1._real32, 2._real32, 3._real32]
        y = [5._real32, 7._real32, 11._real32]
        p = mlx_from(x)
        q = mlx_from(y)
        f = mlx_function(product_sum)
        g = mlx_value_and_grad(f)
        call g%apply([p, q], values, grads)
        call assert_int(2, size(values), 'every output of the function comes back: the scalar and its companion')
        call assert_int(1, size(grads), 'without argnums, the gradient with respect to the first input')
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, y)), 'the gradient of sum(p q) with respect to input 1 is q')
        call mlx_to(total, values(1))
        call assert_true(bits_equal(total(1), 52._real32), 'the first value is the scalar that was differentiated')
        call mlx_to(got, values(2))
        call assert_true(all(bits_equal(got, x+y)), 'the second value is the function''s second output')
        g = mlx_value_and_grad(f, [2])
        call g%apply([p, q], values, grads)
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, x)), 'argnums [2] is the second input: the gradient is p')
        g = mlx_value_and_grad(f, [2, 1])
        call g%apply([p, q], values, grads)
        call assert_int(2, size(grads), 'two positions give two gradients')
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, x)), 'the gradients come in the order of argnums: first with respect to input 2')
        call mlx_to(got, grads(2))
        call assert_true(all(bits_equal(got, y)), 'then with respect to input 1')
        g = mlx_value_and_grad(f, [1, 1])
        call g%apply([p, q], values, grads, status=st)
        call assert_true(st /= 0, 'a repeated position is refused at the application, with a status')
        f3 = mlx_function(chain_sum)
        g = mlx_value_and_grad(f3, [2, 3, 1])
        a3 = mlx_from(reshape([(real(i, real32), i=1, M*K)], [M, K]))
        b3 = mlx_from(reshape([(real(i, real32), i=1, K*N)], [K, N]))
        v3 = mlx_from([(real(i, real32), i=1, N)])
        call g%apply([a3, b3, v3], values, grads)
        call assert_true(all(grads(1)%shape() == [K, N]), 'argnums [2, 3, 1]: the first gradient has the second input''s shape')
        call assert_true(all(grads(2)%shape() == [N]), 'the second gradient has the third input''s shape')
        call assert_true(all(grads(3)%shape() == [M, K]), 'the third gradient has the first input''s shape')
        f = mlx_compile(f)
        g = mlx_value_and_grad(f, [2])
        call g%apply([p, q], values, grads)
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, x)), 'a compiled function is differentiated as its callback is')
    end subroutine test_positions_and_outputs

    ! a custom rule replaces MLX's own derivative and leaves the values alone; an absent rule stays MLX's
    subroutine test_custom_rules
        type(mlx_function)           :: f, g
        type(mlx_grad_function)      :: gr
        type(mlx_array)              :: p, q, w, tp, tq
        type(mlx_array), allocatable :: outputs(:), products(:), plain(:), grads(:)
        real(real32)                 :: x(3), y(3), c(3), t(3), u(3), got(3), want(3)
        integer                      :: st, before
        write(*,'(a)') 'test_custom_rules'
        x = [1._real32, 2._real32, 3._real32]
        y = [5._real32, 7._real32, 11._real32]
        c = [2._real32, -1._real32, 4._real32]
        t = [1._real32, 3._real32, -2._real32]
        u = [4._real32, 1._real32, 2._real32]
        p = mlx_from(x)
        q = mlx_from(y)
        w = mlx_from(c)
        tp = mlx_from(t)
        tq = mlx_from(u)
        f = mlx_function(square)
        g = mlx_custom_vjp(f, tripled_cotangent)
        call g%apply([p], outputs)
        call f%apply([p], plain)
        call mlx_to(got, outputs(1))
        call mlx_to(want, plain(1))
        call assert_true(all(bits_equal(got, want)), 'a function with a custom vjp returns the function''s values')
        call mlx_vjp(g, [p], [w], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 3._real32*c)), 'its vector-Jacobian product is the custom rule''s: three times the cotangent')
        call mlx_vjp(f, [p], [w], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 2._real32*x*c)), 'the plain function keeps MLX''s rule, 2 x times the cotangent')
        gr = mlx_value_and_grad(mlx_function(sum_of_custom))
        call gr%apply([p], outputs, grads)
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, 3._real32)), 'a gradient through a custom vjp built inside a callback uses the custom rule')
        g = mlx_custom_vjp(f, mixed_rule)
        call mlx_vjp(g, [p], [w], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, c*x+x*x)), 'a custom vjp receives the inputs, the cotangents and the outputs, in that order')
        g = mlx_custom_vjp(f, short_rule)
        gr = mlx_value_and_grad(mlx_function(sum_of_short))
        call gr%apply([p], outputs, grads, status=st)
        call assert_true(st /= 0, 'a custom vjp that does not return one array per input is refused with a status')
        g = mlx_custom_function(f, vjp=tripled_cotangent)
        call mlx_vjp(g, [p], [w], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 3._real32*c)), 'mlx_custom_function with a vjp uses it')
        call mlx_jvp(g, [p], [tp], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 2._real32*x*t)), 'and keeps MLX''s Jacobian-vector product when no jvp is given')
        f = mlx_function(product_each)
        g = mlx_custom_function(f, jvp=marked_tangents)
        call mlx_jvp(g, [p, q], [tp, tq], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, t+20._real32*u)), 'a custom jvp receives the tangents and their one-based positions 1 and 2')
        call mlx_to(got, outputs(1))
        call assert_true(all(bits_equal(got, x*y)), 'and the function''s values are unchanged')
        call mlx_vjp(g, [p, q], [w], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, c*y)), 'with a jvp only, the vector-Jacobian product stays MLX''s')
        f = mlx_function(constant_first)
        call mlx_jvp(f, [q], [tq], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 2._real32*u)), 'a custom jvp given one tangent, of its second input, receives the position 2')
        f = mlx_function(product_sum)
        g = mlx_checkpoint(f)
        gr = mlx_value_and_grad(g, [1, 2])
        before = f%trace_count()
        call gr%apply([p, q], outputs, grads)
        call assert_int(before+2, g%trace_count(), 'a checkpointed function runs its callback again for the gradient, and shares the function''s trace count')
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, y)), 'a checkpointed function has the function''s gradient with respect to input 1')
        call mlx_to(got, grads(2))
        call assert_true(all(bits_equal(got, x)), 'and with respect to input 2')
    end subroutine test_custom_rules

    ! mlx_stop_gradient holds an operand constant in a derivative; mlx_depends returns its inputs' values
    subroutine test_stop_gradient_and_depends
        type(mlx_grad_function)      :: g
        type(mlx_array)              :: p, q
        type(mlx_array), allocatable :: values(:), grads(:), outs(:)
        real(real32)                 :: x(3), y(3), got(3)
        write(*,'(a)') 'test_stop_gradient_and_depends'
        x = [1._real32, 2._real32, 3._real32]
        y = [5._real32, 7._real32, 11._real32]
        p = mlx_from(x)
        q = mlx_from(y)
        g = mlx_value_and_grad(mlx_function(half_stopped))
        call g%apply([p], values, grads)
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, x)), 'the gradient of sum(x stop_gradient(x)) is x, not 2 x')
        call mlx_depends([p, q], [q], outs)
        call assert_int(2, size(outs), 'mlx_depends returns one array per input')
        call mlx_to(got, outs(1))
        call assert_true(all(bits_equal(got, x)), 'the first has the first input''s values')
        call mlx_to(got, outs(2))
        call assert_true(all(bits_equal(got, y)), 'the second has the second input''s values')
    end subroutine test_stop_gradient_and_depends

    ! a gradient function is one counted object; a failing callback returns a status and leaves MLX usable
    subroutine test_lifecycle_and_failures
        type(mlx_function)            :: f
        type(mlx_grad_function)       :: g, copy
        type(mlx_array)               :: p
        type(mlx_array),  allocatable :: values(:), grads(:)
        real(real32)                  :: x(3), got(3)
        integer                       :: live0, st
        character(len=:), allocatable :: message
        write(*,'(a)') 'test_lifecycle_and_failures'
        x = [1._real32, 2._real32, 3._real32]
        p = mlx_from(x)
        live0 = mlx_live_count()
        f = mlx_function(poly_sum)
        g = mlx_value_and_grad(f)
        call assert_int(live0+2, mlx_live_count(), 'a function and its gradient function are two live objects')
        copy = g
        call assert_int(live0+2, mlx_live_count(), 'a copy of a gradient function shares the object')
        call g%kill()
        call g%kill()
        call f%kill()
        call copy%apply([p], values, grads, status=st)
        call assert_int(0, st, 'a copy outlives the original and the function it was made from')
        call mlx_to(got, grads(1))
        call assert_true(all(bits_equal(got, 9._real32*x*x-4._real32*x+1._real32)), 'and gives the gradient of the polynomial')
        deallocate(values, grads)
        call copy%kill()
        call assert_int(live0, mlx_live_count(), 'killing the last copy frees the gradient function')
        f = mlx_function(failing)
        g = mlx_value_and_grad(f)
        call g%apply([p], values, grads, status=st)
        call assert_true(st /= 0, 'a failure inside the callback returns through the gradient function as a status')
        call assert_true(.not. allocated(values), 'a failed gradient publishes no values')
        call assert_true(.not. allocated(grads), 'a failed gradient publishes no gradients')
        message = mlx_last_error()
        call assert_true(len(message) > 0, 'the failure leaves a message')
        f = mlx_function(vector_valued)
        g = mlx_value_and_grad(f)
        call g%apply([p], values, grads, status=st)
        call assert_true(st /= 0, 'a function whose first output is not a scalar is refused with a status')
        f = mlx_function(poly_sum)
        g = mlx_value_and_grad(f, [2])
        call g%apply([p], values, grads, status=st)
        call assert_true(st /= 0, 'a position beyond the inputs is refused with a status')
        g = mlx_value_and_grad(f)
        call g%apply([p], values, grads, status=st)
        call assert_int(0, st, 'MLX remains usable after the failures')
    end subroutine test_lifecycle_and_failures

    ! a derivative of a derivative: a callback that takes a gradient or a product is itself differentiated
    subroutine test_higher_order
        type(mlx_function)           :: f
        type(mlx_array)              :: p, w
        type(mlx_array), allocatable :: outputs(:), products(:)
        real(real32)                 :: x(3), c(3), got(3)
        write(*,'(a)') 'test_higher_order'
        x = [1._real32, 2._real32, 3._real32]
        c = [2._real32, -1._real32, 4._real32]
        p = mlx_from(x)
        w = mlx_from(c)
        f = mlx_function(slope_by_grad)
        call mlx_vjp(f, [p], [w], outputs, products)
        call mlx_to(got, outputs(1))
        call assert_true(all(bits_equal(got, 3._real32*x*x)), 'a callback that applies a gradient function returns the slope of x**3')
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 6._real32*x*c)), 'and its vector-Jacobian product is the second derivative, 6 x, times the cotangent')
        f = mlx_function(slope_by_vjp)
        call mlx_vjp(f, [p], [w], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 6._real32*x*c)), 'mlx_vjp of a callback that calls mlx_vjp is the second derivative')
        call mlx_jvp(f, [p], [w], outputs, products)
        call mlx_to(got, products(1))
        call assert_true(all(bits_equal(got, 6._real32*x*c)), 'mlx_jvp of a callback that calls mlx_vjp is the second derivative too')
    end subroutine test_higher_order

    ! many applications of every transform leave the active memory and the live handles where they were: no
    ! vector, closure or array is left behind
    subroutine test_no_leak
        type(mlx_function)           :: f, g
        type(mlx_grad_function)      :: gr
        type(mlx_array)              :: p, w
        type(mlx_array), allocatable :: outputs(:), products(:), outs(:)
        real(real32)                 :: x(4096)
        integer(int64)               :: memory0
        integer                      :: k, live0
        integer, parameter           :: NLOOP = 300
        write(*,'(a)') 'test_no_leak'
        x = 0.5_real32
        p = mlx_from(x)
        w = mlx_from(x)
        f = mlx_function(square)
        do k = 0, NLOOP
            if( k == 1 )then
                call mlx_synchronize()
                memory0 = mlx_active_memory()
                live0 = mlx_live_count()
            endif
            gr = mlx_value_and_grad(mlx_function(poly_sum))
            call gr%apply([p], outputs, products)
            call mlx_eval(products)
            call mlx_vjp(f, [p], [w], outputs, products)
            call mlx_eval(products)
            call mlx_jvp(f, [p], [w], outputs, products)
            call mlx_eval(products)
            g = mlx_custom_function(f, vjp=tripled_cotangent, jvp=doubled_tangent)
            call mlx_vjp(g, [p], [w], outputs, products)
            call mlx_eval(products)
            call mlx_jvp(g, [p], [w], outputs, products)
            call mlx_eval(products)
            g = mlx_checkpoint(f)
            call g%apply([p], outputs)
            call mlx_depends([p], [w], outs)
            call mlx_eval(outs)
            deallocate(outputs, products, outs)
            call g%kill()
            call gr%kill()
        end do
        call mlx_synchronize()
        call assert_true(mlx_active_memory() == memory0, 'the active memory after 300 rounds of every transform is what it was after the first')
        call assert_int(live0, mlx_live_count(), 'and so is the number of live handles')
    end subroutine test_no_leak

    ! the polynomial 3 x**3 - 2 x**2 + x - 5 elementwise, its slope, and the sums of the magnitudes of their terms
    elemental function poly( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 3._real64*x**3-2._real64*x**2+x-5._real64
    end function poly

    elemental function poly_magnitude( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 3._real64*abs(x)**3+2._real64*x**2+abs(x)+5._real64
    end function poly_magnitude

    elemental function poly_slope( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 9._real64*x**2-4._real64*x+1._real64
    end function poly_slope

    elemental function poly_slope_magnitude( x ) result(y)
        real(real64), intent(in) :: x
        real(real64) :: y
        y = 9._real64*x**2+4._real64*abs(x)+1._real64
    end function poly_slope_magnitude

    ! the polynomial of the first input, elementwise
    subroutine poly_each( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 1 ) return
        allocate(outputs(1))
        outputs(1) = inputs(1)*inputs(1)*inputs(1)*3._real32-inputs(1)*inputs(1)*2._real32+inputs(1)-5._real32
        status = 0
    end subroutine poly_each

    ! the sum of the polynomial over the first input: a scalar
    subroutine poly_sum( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable :: each(:)
        call poly_each(inputs, each, status)
        if( status /= 0 ) return
        allocate(outputs(1))
        outputs(1) = sum(each(1))
    end subroutine poly_sum

    ! exp(a x) of the two inputs, elementwise
    subroutine exp_each( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 2 ) return
        allocate(outputs(1))
        outputs(1) = exp(inputs(1)*inputs(2))
        status = 0
    end subroutine exp_each

    ! norm2 of the one input
    subroutine norm_value( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 0
        allocate(outputs(1))
        outputs(1) = norm2(inputs(1))
    end subroutine norm_value

    ! mlx_mean of the one input
    subroutine mean_value( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 0
        allocate(outputs(1))
        outputs(1) = mlx_mean(inputs(1))
    end subroutine mean_value

    ! sum(exp(a x)) of the two inputs
    subroutine exp_sum( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable :: each(:)
        call exp_each(inputs, each, status)
        if( status /= 0 ) return
        allocate(outputs(1))
        outputs(1) = sum(each(1))
    end subroutine exp_sum

    ! matmul(a, matmul(b, v)) of the three inputs: a vector
    subroutine chain_each( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 3 ) return
        allocate(outputs(1))
        outputs(1) = matmul(inputs(1), matmul(inputs(2), inputs(3)))
        status = 0
    end subroutine chain_each

    ! the sum of the chain's vector
    subroutine chain_sum( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable :: each(:)
        call chain_each(inputs, each, status)
        if( status /= 0 ) return
        allocate(outputs(1))
        outputs(1) = sum(each(1))
    end subroutine chain_sum

    ! sum(p q) and, as a second output, p + q
    subroutine product_sum( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 2 ) return
        allocate(outputs(2))
        outputs(1) = sum(inputs(1)*inputs(2))
        outputs(2) = inputs(1)+inputs(2)
        status = 0
    end subroutine product_sum

    ! p q elementwise
    subroutine product_each( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 2 ) return
        allocate(outputs(1))
        outputs(1) = inputs(1)*inputs(2)
        status = 0
    end subroutine product_each

    ! x x elementwise
    subroutine square( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 1 ) return
        allocate(outputs(1))
        outputs(1) = inputs(1)*inputs(1)
        status = 0
    end subroutine square

    ! the sum of the square with the tripled-cotangent rule, built and applied inside the callback
    subroutine sum_of_custom( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_function)           :: f, g
        type(mlx_array), allocatable :: each(:)
        f = mlx_function(square)
        g = mlx_custom_vjp(f, tripled_cotangent)
        call g%apply(inputs, each, status=status)
        if( status /= 0 ) return
        allocate(outputs(1))
        outputs(1) = sum(each(1))
    end subroutine sum_of_custom

    ! sum(x stop_gradient(x))
    subroutine half_stopped( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 1 ) return
        allocate(outputs(1))
        outputs(1) = sum(inputs(1)*mlx_stop_gradient(inputs(1)))
        status = 0
    end subroutine half_stopped

    ! a callback that fails through its status
    subroutine failing( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        allocate(outputs(0))
        status = 7+0*size(inputs)
    end subroutine failing

    ! a function whose first output is not a scalar: nothing a gradient can be taken of
    subroutine vector_valued( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        allocate(outputs(1))
        outputs(1) = inputs(1)*2._real32
        status = 0
    end subroutine vector_valued

    ! a rule that is not the derivative, so that its use shows: three times the cotangent for the one input
    subroutine tripled_cotangent( primals, cotangents, outputs, vjps, status )
        type(mlx_array), intent(in)               :: primals(:), cotangents(:), outputs(:)
        type(mlx_array), allocatable, intent(out) :: vjps(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(primals) /= 1 .or. size(cotangents) /= 1 .or. size(outputs) /= 1 ) return
        allocate(vjps(1))
        vjps(1) = cotangents(1)*3._real32
        status = 0
    end subroutine tripled_cotangent

    ! a rule that uses its three lists differently: cotangent times input plus output
    subroutine mixed_rule( primals, cotangents, outputs, vjps, status )
        type(mlx_array), intent(in)               :: primals(:), cotangents(:), outputs(:)
        type(mlx_array), allocatable, intent(out) :: vjps(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(primals) /= 1 .or. size(cotangents) /= 1 .or. size(outputs) /= 1 ) return
        allocate(vjps(1))
        vjps(1) = cotangents(1)*primals(1)+outputs(1)
        status = 0
    end subroutine mixed_rule

    ! a rule that returns no array for its one input
    subroutine short_rule( primals, cotangents, outputs, vjps, status )
        type(mlx_array), intent(in)               :: primals(:), cotangents(:), outputs(:)
        type(mlx_array), allocatable, intent(out) :: vjps(:)
        integer,         intent(out)              :: status
        allocate(vjps(0))
        status = 0*(size(primals)+size(cotangents)+size(outputs))
    end subroutine short_rule

    ! the sum of the square under the rule that returns no array
    subroutine sum_of_short( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_function)           :: f, g
        type(mlx_array), allocatable :: each(:)
        f = mlx_function(square)
        g = mlx_custom_vjp(f, short_rule)
        call g%apply(inputs, each, status=status)
        if( status /= 0 ) return
        allocate(outputs(1))
        outputs(1) = sum(each(1))
    end subroutine sum_of_short

    ! twice the tangent of the one input
    subroutine doubled_tangent( primals, tangents, argnums, jvps, status )
        type(mlx_array), intent(in)               :: primals(:), tangents(:)
        integer,         intent(in)               :: argnums(:)
        type(mlx_array), allocatable, intent(out) :: jvps(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(primals) /= 1 .or. size(tangents) /= 1 .or. size(argnums) /= 1 ) return
        allocate(jvps(1))
        jvps(1) = tangents(1)*2._real32
        status = 0
    end subroutine doubled_tangent

    ! a rule for one tangent: the tangent times the position of the input it belongs to
    subroutine position_times_tangent( primals, tangents, argnums, jvps, status )
        type(mlx_array), intent(in)               :: primals(:), tangents(:)
        integer,         intent(in)               :: argnums(:)
        type(mlx_array), allocatable, intent(out) :: jvps(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(primals) /= 2 .or. size(tangents) /= 1 .or. size(argnums) /= 1 ) return
        allocate(jvps(1))
        jvps(1) = tangents(1)*real(argnums(1), real32)
        status = 0
    end subroutine position_times_tangent

    ! the product of a constant and the input, through a custom function whose jvp shows the position it is given
    subroutine constant_first( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_function) :: f, g
        type(mlx_array)    :: fixed
        fixed = mlx_from([1._real32, 1._real32, 1._real32])
        f = mlx_function(product_each)
        g = mlx_custom_function(f, jvp=position_times_tangent)
        call g%apply([fixed, inputs(1)], outputs, status=status)
    end subroutine constant_first

    ! the sum of x**3 over the first input
    subroutine cube_sum( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        allocate(outputs(1))
        outputs(1) = sum(inputs(1)*inputs(1)*inputs(1))
        status = 0
    end subroutine cube_sum

    ! x**3 elementwise
    subroutine cube_each( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        allocate(outputs(1))
        outputs(1) = inputs(1)*inputs(1)*inputs(1)
        status = 0
    end subroutine cube_each

    ! the slope of x**3, 3 x**2, as the gradient of its sum taken inside the callback
    subroutine slope_by_grad( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_grad_function)      :: g
        type(mlx_array), allocatable :: values(:)
        g = mlx_value_and_grad(mlx_function(cube_sum))
        call g%apply(inputs, values, outputs, status=status)
    end subroutine slope_by_grad

    ! the slope of x**3 as a vector-Jacobian product with a cotangent of ones, taken inside the callback
    subroutine slope_by_vjp( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable :: values(:)
        type(mlx_array)              :: ones
        ones = mlx_from([1._real32, 1._real32, 1._real32])
        call mlx_vjp(mlx_function(cube_each), inputs, [ones], values, outputs)
        status = 0
    end subroutine slope_by_vjp

    ! a rule that shows the positions it was given: tangent 1 times its position plus tangent 2 times ten times its
    subroutine marked_tangents( primals, tangents, argnums, jvps, status )
        type(mlx_array), intent(in)               :: primals(:), tangents(:)
        integer,         intent(in)               :: argnums(:)
        type(mlx_array), allocatable, intent(out) :: jvps(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(primals) /= 2 .or. size(tangents) /= 2 .or. size(argnums) /= 2 ) return
        allocate(jvps(1))
        jvps(1) = tangents(1)*real(argnums(1), real32)+tangents(2)*real(10*argnums(2), real32)
        status = 0
    end subroutine marked_tangents

end module mlxf_transforms_tester
