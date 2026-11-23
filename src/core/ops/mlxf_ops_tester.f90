!@descr: independent two-device checks of ops values and Fortran conventions
module mlxf_ops_tester
use, intrinsic :: iso_fortran_env, only: real32, real64, int32, int64
use, intrinsic :: iso_c_binding,   only: c_bool
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                           MLX_DTYPES, exp, sqrt, real, aimag, conjg, cmplx, merge, max, reshape, transpose, sum, &
                           minval, minloc, mlx_astype, mlx_permute, mlx_slice, mlx_concatenate, mlx_take_along_dim, &
                           mlx_logsumexp, mlx_cumsum, mlx_zeros, mlx_arange, mlx_take, mlx_bitcast
use mlxf_test_utils, only: assert_true, assert_int, bits_equal, test_devices, device_name
implicit none
private
public :: run_all_ops_tests

contains

    subroutine run_all_ops_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_elementwise
            call test_shape_indices
            call test_reductions
            call test_long_minloc
            call test_real_conversion_and_precision
            call test_take_and_bitcast
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_tests

    ! a against want within bound, read back in float64 or float32 as a holds
    subroutine check_values( a, want, bound, label )
        type(mlx_array),  intent(in) :: a
        real(real64),     intent(in) :: want(:), bound(:)
        character(len=*), intent(in) :: label
        real(real32) :: y32(size(want))
        real(real64) :: y(size(want))
        if( a%kind() == MLX_DTYPES%float64 )then
            call mlx_to(y, a)
        else
            call mlx_to(y32, a)
            y = real(y32, real64)
        endif
        call assert_true(all(abs(y-want) <= bound), label)
    end subroutine check_values

    ! a equals want bit for bit
    subroutine check_exact( a, want, label )
        type(mlx_array),  intent(in) :: a
        real(real32),     intent(in) :: want(:)
        character(len=*), intent(in) :: label
        real(real32) :: y(size(want))
        call mlx_to(y, a)
        call assert_true(all(bits_equal(y, want)), label)
    end subroutine check_exact

    ! a is a boolean array equal to want
    subroutine check_bool( a, want, label )
        type(mlx_array),  intent(in) :: a
        logical,          intent(in) :: want(:)
        character(len=*), intent(in) :: label
        logical(c_bool) :: y(size(want))
        call mlx_to(y, a)
        call assert_true(all(y.eqv.want), label)
        call assert_int(MLX_DTYPES%bool, a%kind(), label//' gives bool')
    end subroutine check_bool

    ! operators, comparisons and functions against double precision, weak scalars keeping the array's
    ! dtype; float64 again on the CPU device
    subroutine test_elementwise
        type(mlx_array) :: a, b, r, c, m
        real(real64)    :: x(6), y(6), tol
        complex(real32) :: z(6), gotz(6)
        real(real32)    :: imag(6), got(6)
        integer         :: i, k, passes
        write(*,'(a)') 'test_elementwise'
        x = [0.125d0, 0.5d0, 1.d0, 2.d0, 3.d0, 4.d0]
        y = [0.5d0, 0.25d0, 1.d0, 3.d0, 2.d0, 4.d0]
        passes = 1
        if( mlx_default_device() == MLX_DEVICES%cpu ) passes = 2
        do k = 1, passes
            tol = 1.d-5
            if( k == 1 )then
                a = mlx_from(real(x, real32))
                b = mlx_from(real(y, real32))
            else
                a = mlx_from(x)
                b = mlx_from(y)
                tol = 1.d-12
            endif
            r = a+b
            call check_values(r, x+y, tol*(abs(x)+abs(y)), &
                &'arithmetic a+b')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a+2._real32
            call check_values(r, x+2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a+2._real32')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real32+a
            call check_values(r, 2.d0+x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real32+a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a+2._real64
            call check_values(r, x+2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a+2._real64')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real64+a
            call check_values(r, 2.d0+x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real64+a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a-b
            call check_values(r, x-y, tol*(abs(x)+abs(y)), &
                &'arithmetic a-b')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a-2._real32
            call check_values(r, x-2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a-2._real32')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real32-a
            call check_values(r, 2.d0-x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real32-a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a-2._real64
            call check_values(r, x-2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a-2._real64')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real64-a
            call check_values(r, 2.d0-x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real64-a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a*b
            call check_values(r, x*y, tol*(abs(x)+abs(y)), &
                &'arithmetic a*b')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a*2._real32
            call check_values(r, x*2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a*2._real32')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real32*a
            call check_values(r, 2.d0*x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real32*a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a*2._real64
            call check_values(r, x*2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a*2._real64')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real64*a
            call check_values(r, 2.d0*x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real64*a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a/b
            call check_values(r, x/y, tol*(abs(x)+abs(y)), &
                &'arithmetic a/b')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a/2._real32
            call check_values(r, x/2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a/2._real32')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real32/a
            call check_values(r, 2.d0/x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real32/a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = a/2._real64
            call check_values(r, x/2.d0, tol*(abs(x)+abs(2.d0)), &
                &'arithmetic a/2._real64')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = 2._real64/a
            call check_values(r, 2.d0/x, tol*(abs(2.d0)+abs(x)), &
                &'arithmetic 2._real64/a')
            call assert_int(a%kind(), r%kind(), 'weak scalar keeps array dtype')
            r = -a
            call check_values(r, -x, tol*abs(x), 'unary minus')
            r = a < b
            call check_bool(r, x < y, 'comparison a<b')
            r = a < 2._real64
            call check_bool(r, x < 2.d0, 'comparison a<2._real64')
            r = 2._real32 < a
            call check_bool(r, 2.d0 < x, 'comparison 2._real32<a')
            r = a <= b
            call check_bool(r, x <= y, 'comparison a<=b')
            r = a <= 2._real64
            call check_bool(r, x <= 2.d0, 'comparison a<=2._real64')
            r = 2._real32 <= a
            call check_bool(r, 2.d0 <= x, 'comparison 2._real32<=a')
            r = a > b
            call check_bool(r, x > y, 'comparison a>b')
            r = a > 2._real64
            call check_bool(r, x > 2.d0, 'comparison a>2._real64')
            r = 2._real32 > a
            call check_bool(r, 2.d0 > x, 'comparison 2._real32>a')
            r = a >= b
            call check_bool(r, x >= y, 'comparison a>=b')
            r = a >= 2._real64
            call check_bool(r, x >= 2.d0, 'comparison a>=2._real64')
            r = 2._real32 >= a
            call check_bool(r, 2.d0 >= x, 'comparison 2._real32>=a')
            r = a == b
            call check_bool(r, bits_equal(x, y), 'comparison a==b')
            r = a == 2._real64
            call check_bool(r, bits_equal(x, 2.d0), 'comparison a==2._real64')
            r = 2._real32 == a
            call check_bool(r, bits_equal(2.d0, x), 'comparison 2._real32==a')
            r = a /= b
            call check_bool(r, .not. bits_equal(x, y), 'comparison a/=b')
            r = a /= 2._real64
            call check_bool(r, .not. bits_equal(x, 2.d0), 'comparison a/=2._real64')
            r = 2._real32 /= a
            call check_bool(r, .not. bits_equal(2.d0, x), 'comparison 2._real32/=a')
            r = max(a, b)
            call check_values(r, max(x, y), 0.d0*x, 'max array is exact')
            r = max(a, 2._real64)
            call check_values(r, max(x, 2.d0), 0.d0*x, 'max right weak double scalar')
            r = max(2._real32, a)
            call check_values(r, max(x, 2.d0), 0.d0*x, 'max left weak single scalar')
            r = max(a, 2._real32)
            call check_values(r, max(x, 2.d0), 0.d0*x, 'max right weak single scalar')
            r = max(2._real64, a)
            call check_values(r, max(x, 2.d0), 0.d0*x, 'max left weak double scalar')
            r = exp(a)
            call check_values(r, exp(x), 1.d-5*max(1.d0, exp(x)), 'exp double reference')
            r = sqrt(a)
            call check_values(r, sqrt(x), tol*max(1.d0, sqrt(x)), 'sqrt double reference')
            m = (a < b).or.(a == b)
            r = merge(a, b, m)
            call check_values(r, merge(x, y, x <= y), 0.d0*x, 'merge selects bytes')
            r = (a < b).and.(.not. (a == b))
            call check_bool(r, x < y, 'boolean and/not')
        end do
        a = mlx_from(real(x, real32))
        imag = [(real(i, real32)/8, i=1, 6)]
        b = mlx_from(imag)
        z = cmplx(real(x, real32), imag, real32)
        c = cmplx(a, b)
        call mlx_to(gotz, c)
        call assert_true(all(bits_equal(gotz, z)), 'cmplx combines real and imaginary arrays')
        r = real(c)
        call mlx_to(got, r)
        call assert_true(all(bits_equal(got, real(z))), 'real extracts complex real part')
        r = aimag(c)
        call mlx_to(got, r)
        call assert_true(all(bits_equal(got, aimag(z))), 'aimag extracts imaginary part')
        r = conjg(c)
        call mlx_to(gotz, r)
        call assert_true(all(bits_equal(gotz, conjg(z))), 'conjg changes imaginary sign')
        r = mlx_astype(a, MLX_DTYPES%complex64)
        call mlx_to(gotz, r)
        call assert_true(all(bits_equal(gotz, cmplx(real(x, real32), 0._real32, real32))), 'explicit complex cast')
        r = c+2._real64
        call mlx_to(gotz, r)
        call assert_true(all(abs(cmplx(gotz, kind=real64)-(cmplx(z, kind=real64)+2)) &
            & <= 1.d-5*(abs(cmplx(z, kind=real64))+2)), 'weak double scalar remains complex64')
    end subroutine test_elementwise

    ! reshape, transpose, permute, slices, concatenation and take-along-dimension in Fortran's order and
    ! 1-based indices, byte for byte
    subroutine test_shape_indices
        type(mlx_array) :: a, b, r, idx
        real(real32)    :: x(3, 4, 2), y(4, 3, 2), p(2, 3, 4), v(3), flat(24)
        integer(int32)  :: indices(3, 4, 2)
        real(real32)    :: expected(3, 4, 2)
        integer         :: i, j, k
        write(*,'(a)') 'test_shape_indices'
        flat = [(real(i, real32)/8, i=1, 24)]
        x = reshape(flat, shape(x))
        a = mlx_from(x)
        r = reshape(a, [4, 6])
        call assert_true(all(r%shape() == [4, 6]), 'reshape output has Fortran shape')
        call check_exact(r, flat, 'reshape preserves column-major bytes')
        do k = 1, 2
            y(:,:, k) = transpose(x(:,:, k))
        end do
        r = transpose(a)
        call assert_true(all(r%shape() == [4, 3, 2]), 'transpose swaps dimensions one and two only')
        call check_exact(r, reshape(y, [24]), 'transpose bytes match Fortran')
        r = reshape(transpose(a), [6, 4])
        call check_exact(r, reshape(y, [24]), 'reshape traverses a strided input in Fortran order')
        do k = 1, 4
            do j = 1, 3
                do i = 1, 2
                    p(i, j, k) = x(j, k, i)
                end do
            end do
        end do
        r = mlx_permute(a, [3, 1, 2])
        call assert_true(all(r%shape() == [2, 3, 4]), 'permutation output dimension i comes from order(i)')
        call check_exact(r, reshape(p, [24]), 'permutation order bytes')
        r = mlx_slice(a, [1, 2, 1], [3, 4, 2], stride=[2, 2, 1])
        call assert_true(all(r%shape() == [2, 2, 2]), 'inclusive positive slice shape')
        call check_exact(r, reshape(x(1:3:2, 2:4:2, :), [8]), 'one-based inclusive slice')
        r = mlx_slice(a, [3, 4, 2], [1, 1, 1], stride=[-1, -2, -1])
        call check_exact(r, reshape(x(3:1:-1, 4:1:-2, 2:1:-1), [12]), 'negative stride includes element one')
        r = mlx_slice(a, [2, 1, 1], [1, 4, 2])
        call assert_true(r%size() == 0_int64, 'empty positive slice')
        r = mlx_slice(a, [1, 1, 1], [3, 2, 2])
        b = mlx_slice(a, [1, 3, 1], [3, 4, 2])
        r = mlx_concatenate([r, b], 2)
        call check_exact(r, flat, 'concatenate along Fortran dimension two')
        r = mlx_slice(a, [1, 1, 1], [1, 4, 2])
        b = mlx_slice(a, [2, 1, 1], [3, 4, 2])
        r = mlx_concatenate([r, b], 1)
        call assert_true(all(r%shape() == [3, 4, 2]), 'concatenate dimension one restores distinct extents')
        call check_exact(r, flat, 'concatenate dimension one preserves every byte')
        r = mlx_slice(a, [1, 1, 1], [3, 4, 1])
        b = mlx_slice(a, [1, 1, 2], [3, 4, 2])
        r = mlx_concatenate([r, b], 3)
        call assert_true(all(r%shape() == [3, 4, 2]), 'concatenate dimension three restores distinct extents')
        call check_exact(r, flat, 'concatenate dimension three preserves every byte')
        do k = 1, 2
            do j = 1, 4
                indices(:, j, k) = [3, 1, 2]
                expected(:, j, k) = x([3, 1, 2], j, k)
            end do
        end do
        idx = mlx_from(indices)
        r = mlx_take_along_dim(a, idx, 1)
        call check_exact(r, reshape(expected, [24]), 'gather uses one-based index values and dimension')
        indices = 0
        do k = 1, 2
            do j = 1, 4
                expected(:, j, k) = x(3, j, k)
            end do
        end do
        idx = mlx_from(indices)
        r = mlx_take_along_dim(a, idx, 1)
        call check_exact(r, reshape(expected, [24]), 'gather index zero wraps to the last element')
        v = [1._real32, 2._real32, 4._real32]
        b = mlx_from(v)
        r = a+b
        do k = 1, 2
            do j = 1, 4
                expected(:, j, k) = x(:, j, k)+v
            end do
        end do
        call check_exact(r, reshape(expected, [24]), 'broadcast aligns leading Fortran dimensions')
        r = mlx_zeros([2, 3])
        call check_exact(r, spread(0._real32, 1, 6), 'zeros shape and default float32')
        r = mlx_arange(1.d0, 4.d0, step=0.5d0)
        call check_exact(r, [1., 1.5, 2., 2.5, 3., 3.5], 'arange excludes stop')
        r = mlx_arange(3.d0, 0.d0, step=-1.d0, dtype=MLX_DTYPES%int32)
        call mlx_to(indices(:, 1, 1), r)
        call assert_true(all(indices(:, 1, 1) == [3, 2, 1]), 'arange negative step and integer dtype')
    end subroutine test_shape_indices

    ! sum, minval, logsumexp, cumsum and minloc along each dimension, and minloc's first-position ties
    subroutine test_reductions
        type(mlx_array) :: a, r
        real(real64)    :: x(3, 4), bound1(4), bound2(3), tol, cum(3, 4), logsum2(3), logsum1(4)
        integer(int32)  :: loc1(4), loc2(3)
        integer         :: k, passes, j
        write(*,'(a)') 'test_reductions'
        x = reshape([3.d0, 1.d0, 1.d0, 2.d0, 4.d0, 2.d0, 1.d0, 1.d0, 4.d0, 4.d0, 2.d0, 2.d0], [3, 4])
        passes = 1
        if( mlx_default_device() == MLX_DEVICES%cpu ) passes = 2
        do k = 1, passes
            tol = 1.d-5
            if( k == 1 )then
                a = mlx_from(real(x, real32))
            else
                a = mlx_from(x)
                tol = 1.d-12
            endif
            bound1 = tol*sum(abs(x), dim=1)
            bound2 = tol*sum(abs(x), dim=2)
            r = sum(a, dim=1)
            call check_values(r, sum(x, dim=1), bound1, 'sum dimension one')
            r = sum(a, dim=2)
            call check_values(r, sum(x, dim=2), bound2, 'sum dimension two')
            r = minval(a, dim=1)
            call check_values(r, minval(x, dim=1), 0.d0*bound1, 'minimum dimension one')
            r = minval(a, dim=2)
            call check_values(r, minval(x, dim=2), 0.d0*bound2, 'minimum dimension two')
            r = minloc(a, dim=1)
            call mlx_to(loc1, r)
            call assert_true(all(loc1 == minloc(x, dim=1)), 'minloc one-based first tie along dimension one')
            call assert_int(MLX_DTYPES%int32, r%kind(), 'minloc returns int32')
            r = minloc(a, dim=2)
            call mlx_to(loc2, r)
            call assert_true(all(loc2 == minloc(x, dim=2)), 'minloc dimension two')
            do j = 1, 3
                cum(j, :) = sum(x(:j, :), dim=1)
            end do
            r = mlx_cumsum(a, 1)
            call check_values(r, reshape(cum, [12]), tol*reshape(abs(cum), [12]), 'inclusive forward cumsum dimension one')
            do j = 1, 4
                cum(:, j) = sum(x(:,:j), dim=2)
            end do
            r = mlx_cumsum(a, 2)
            call check_values(r, reshape(cum, [12]), tol*reshape(abs(cum), [12]), 'inclusive forward cumsum dimension two')
            r = mlx_logsumexp(a, 2)
            logsum2 = log(sum(exp(x), dim=2))
            call check_values(r, logsum2, 1.d-5*max(1.d0, abs(logsum2)), 'logsumexp bound in log units')
        end do
        a = mlx_from(real(x+1000.d0, real32))
        r = mlx_logsumexp(a, 1)
        logsum1 = 1000.d0+log(sum(exp(x), dim=1))
        call check_values(r, logsum1, 1.d-5*max(1.d0, abs(logsum1)), &
            &'logsumexp remains finite for large offsets')
    end subroutine test_reductions

    ! minloc's first tie on a 4097-element axis, contiguous and strided, where the GPU reduces in parallel
    subroutine test_long_minloc
        integer, parameter :: N = 4097
        real(real32)       :: x(N, 3)
        integer(int32)     :: loc(3)
        type(mlx_array)    :: a, r
        write(*,'(a)') 'test_long_minloc'
        x = 1._real32
        x(2, 1) = -3._real32
        x(1025, 2) = -3._real32
        x(4096, 3) = -3._real32
        x(N, :) = -3._real32
        a = mlx_from(x)
        r = minloc(a, dim=1)
        call mlx_to(loc, r)
        call assert_true(all(loc == minloc(x, dim=1)), 'minloc first ties across a 4097-element contiguous axis')
        a = transpose(a)
        r = minloc(a, dim=2)
        call mlx_to(loc, r)
        call assert_true(all(loc == minloc(x, dim=1)), 'minloc first ties across a 4097-element strided axis')
    end subroutine test_long_minloc

    ! real() gives float32 as Fortran's default real, and integer arrays with real scalars
    ! give float32
    subroutine test_real_conversion_and_precision
        type(mlx_array) :: a, b, r
        real(real64)    :: x(6), y(6), cumulative(6)
        integer         :: i, kind
        write(*,'(a)') 'test_real_conversion_and_precision'
        a = mlx_from([1_int32, 2_int32, 3_int32])
        r = real(a)
        kind = r%kind()
        call assert_int(MLX_DTYPES%float32, kind, 'real(integer array) returns default real')
        if( kind == MLX_DTYPES%float32 ) call check_exact(r, [1._real32, 2._real32, 3._real32], 'real integer values')
        r = a+0.25_real64
        kind = r%kind()
        call assert_int(MLX_DTYPES%float32, kind, 'integer array plus real64 scalar gives float32')
        if( kind == MLX_DTYPES%float32 ) call check_exact(r, [1.25_real32, 2.25_real32, 3.25_real32], 'integer plus real values')
        r = 0.25_real32+a
        kind = r%kind()
        call assert_int(MLX_DTYPES%float32, kind, 'real32 scalar plus integer array gives float32')
        if( kind == MLX_DTYPES%float32 ) call check_exact(r, [1.25_real32, 2.25_real32, 3.25_real32], 'real plus integer values')
        if( mlx_default_device() /= MLX_DEVICES%cpu ) return
        x = [0.1d0, 0.3d0, 0.7d0, 0.9d0, 0.12d0, 0.34d0]
        y = [0.27d0, 0.63d0, 0.81d0, 0.56d0, 0.43d0, 0.19d0]
        a = mlx_from(x)
        b = mlx_from(y)
        r = a+b
        call check_values(r, x+y, 1.d-12*(abs(x)+abs(y)), 'CPU float64 nonbinary addition precision')
        r = a/b
        call check_values(r, x/y, 1.d-12*(abs(x)+abs(y)), 'CPU float64 nonbinary division precision')
        r = sum(a, dim=1)
        call check_values(r, [sum(x)], [1.d-12*sum(abs(x))], 'CPU float64 nonbinary reduction precision')
        do i = 1, 6
            cumulative(i) = sum(x(:i))
        end do
        r = mlx_cumsum(a, 1)
        call check_values(r, cumulative, 1.d-12*cumulative, 'CPU float64 nonbinary scan precision')
        r = real(a)
        kind = r%kind()
        call assert_int(MLX_DTYPES%float32, kind, 'real(real64 array) returns default real')
        if( kind == MLX_DTYPES%float32 ) call check_exact(r, real(x, real32), 'real real64 rounding follows Fortran')
    end subroutine test_real_conversion_and_precision

    ! mlx_take gathers whole slices at 1-based indices and puts the indices' shape in place of the dimension;
    ! mlx_bitcast reads the bytes as another dtype, scaling the first Fortran dimension by the item sizes
    subroutine test_take_and_bitcast
        type(mlx_array)    :: a, r, idx
        real(real32)       :: x(3, 4, 2), y(3, 2, 2, 2), got(3, 2, 2, 2), z(4, 3), w(6)
        complex(real32)    :: zc(2, 3), zg(3)
        integer(int32)     :: ind(2, 2), bits(4), back(4)
        integer            :: i, j, k, l
        write(*,'(a)') 'test_take_and_bitcast'
        x = reshape([(real(i, real32)/4, i=1, 24)], shape(x))
        a = mlx_from(x)
        ind = reshape([4, 1, 2, 4], [2, 2])
        idx = mlx_from(ind)
        r = mlx_take(a, idx, 2)
        call assert_true(all(r%shape() == [3, 2, 2, 2]), 'take puts the indices'' shape in place of the dimension')
        do k = 1, 2
            do l = 1, 2
                do j = 1, 2
                    y(:, j, l, k) = x(:, ind(j, l), k)
                end do
            end do
        end do
        call mlx_to(got, r)
        call assert_true(all(bits_equal(reshape(got, [24]), reshape(y, [24]))), 'take gathers whole slices at '//&
            &'one-based indices')
        idx = mlx_from([0_int32])
        r = mlx_take(mlx_from(reshape(x(:, :, 1), [3, 4])), idx, 2)
        call mlx_to(z(1:3, 1), r)
        call assert_true(all(bits_equal(z(1:3, 1), x(:, 4, 1))), 'take index zero wraps to the last slice')
        ! six float32 as three complex64: the pairs along dimension 1 are (real, imaginary)
        w  = [1.5_real32, -2._real32, 3._real32, 0.25_real32, -7._real32, 8._real32]
        r  = mlx_bitcast(mlx_from(reshape(w, [2, 3])), MLX_DTYPES%complex64)
        call assert_true(all(r%shape() == [1, 3]), 'bitcast to complex64 halves the first dimension')
        call assert_int(MLX_DTYPES%complex64, r%kind(), 'bitcast gives the requested dtype')
        call mlx_to(zg, r)
        call assert_true(all(bits_equal(transfer(zg, [0._real32], 6), w)), 'bitcast reads the pairs along '//&
            &'dimension 1 as (real, imaginary)')
        zc = reshape([(cmplx(real(i, real32), -real(i, real32), real32), i=1, 6)], shape(zc))
        r  = mlx_bitcast(mlx_from(zc), MLX_DTYPES%float32)
        call assert_true(all(r%shape() == [4, 3]), 'bitcast to float32 doubles the first dimension')
        call mlx_to(z, r)
        call assert_true(all(bits_equal(reshape(z, [12]), reshape(transfer(zc, [0._real32], 12), [12]))), &
            &'bitcast to float32 keeps every byte')
        bits = [1065353216_int32, -1073741824_int32, 0_int32, 2139095040_int32]
        r = mlx_bitcast(mlx_from(bits), MLX_DTYPES%float32)
        r = mlx_bitcast(r, MLX_DTYPES%int32)
        call mlx_to(back, r)
        call assert_true(all(back == bits), 'bitcast int32 to float32 and back keeps every bit')
    end subroutine test_take_and_bitcast
end module mlxf_ops_tester

