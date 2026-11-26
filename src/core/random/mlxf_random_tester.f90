!@descr: the random keys and samplers: keys and determinism, Fortran shapes, moments of every sampler, one-based categories and permutations
! A sampler is judged by the mean and the variance of a large sample against the distribution's own values, each
! within RANDOM_SIGMAS standard errors (the normal approximation of an estimator's error); the moments are
! computed here in real64 from the values brought to the host. Keys come from fixed seeds, so a run is repeatable.
! Categories, permutations, shapes, dtypes and the bytes of a repeated draw are exact.
module mlxf_random_tester
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64, output_unit
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_astype, mlx_live_count, mlx_set_default_device, &
                            mlx_default_device, MLX_DEVICES, MLX_DTYPES, mlx_random_seed, mlx_random_key, &
                            mlx_random_split, mlx_random_bits, mlx_random_uniform, mlx_random_normal, &
                            mlx_random_laplace, mlx_random_gumbel, mlx_random_truncated_normal, mlx_random_randint, &
                            mlx_random_bernoulli, mlx_random_multivariate_normal, mlx_random_categorical, &
                            mlx_random_permutation, mlx_unstack
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name, bits_equal, family_seeds
use mlxf_test_defs,   only: RANDOM_NSAMPLES, RANDOM_SIGMAS
use mlxf_test_reduce, only: nan_max
implicit none
private
public :: run_all_random_tests

real(real64), parameter :: PI = 3.14159265358979323846_real64
real(real64), parameter :: EULER_GAMMA = 0.57721566490153286061_real64

! the mean, the variance and the fourth central moment of a distribution
type :: moments
    real(real64) :: mean = 0._real64, var = 1._real64, fourth = 3._real64
end type moments

contains

    subroutine run_all_random_tests
        integer, allocatable :: devs(:), seeds(:)
        integer              :: i, k, original, live0
        write(*,'(a)') '**** running all random tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        seeds = family_seeds()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            call test_keys
            call test_seed
            call test_shapes
            call test_dtypes(devs(i))
            call test_categorical_exact
            call test_permutation
            do k = 1, size(seeds)
                call test_real_samplers(seeds(k))
                call test_broadcast_parameters(seeds(k))
                call test_integer_samplers(seeds(k))
                call test_multivariate_normal(seeds(k))
                call test_categorical_frequencies(seeds(k))
            end do
            call assert_int(live0, mlx_live_count(), 'keys, parameters and samples leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_random_tests

    ! a key is the two 32-bit halves of its seed; split keys are new keys; the same key gives the same bytes
    subroutine test_keys
        type(mlx_array) :: key, wide, first, second, three, r, k64
        integer(int64)  :: words(2), other(2), many(2, 3)
        real(real32)    :: u(1000), v(1000)
        write(*,'(a)') 'test_keys'
        key = mlx_random_key(42)
        call assert_true(key%kind() == MLX_DTYPES%uint32, 'a key is a uint32 array')
        call assert_true(all(key%shape() == [2]), 'a key has two elements')
        k64 = mlx_astype(key, MLX_DTYPES%int64)
        call mlx_to(words, k64)
        call assert_true(all(words == [0_int64, 42_int64]), 'the key of seed 42 is (0, 42): the high and the low word')
        wide = mlx_random_key(4294967301_int64)
        k64 = mlx_astype(wide, MLX_DTYPES%int64)
        call mlx_to(words, k64)
        call assert_true(all(words == [1_int64, 5_int64]), 'the key of the 64-bit seed 2**32 + 5 is (1, 5)')
        wide = mlx_random_key(-1)
        k64 = mlx_astype(wide, MLX_DTYPES%int64)
        call mlx_to(words, k64)
        call assert_true(all(words == [4294967295_int64, 4294967295_int64]), 'a negative default-integer seed is extended with its sign: the key of -1 is (2**32 - 1, 2**32 - 1)')
        call mlx_random_split(key, first, second)
        call assert_true(first%kind() == MLX_DTYPES%uint32, 'the first key of a split is uint32')
        call assert_true(second%kind() == MLX_DTYPES%uint32, 'the second key of a split is uint32')
        call assert_true(all(first%shape() == [2]), 'the first key of a split has two elements')
        call assert_true(all(second%shape() == [2]), 'the second key of a split has two elements')
        k64 = mlx_astype(first, MLX_DTYPES%int64)
        call mlx_to(words, k64)
        k64 = mlx_astype(second, MLX_DTYPES%int64)
        call mlx_to(other, k64)
        call assert_true(any(words /= other), 'the two keys of a split differ')
        call assert_true(any(words /= [0_int64, 42_int64]) .and. any(other /= [0_int64, 42_int64]), 'and differ from their parent')
        call mlx_random_split(key, 3, three)
        call assert_true(all(three%shape() == [2, 3]), 'a split into 3 is a (2, 3) array: key i is keys(:, i)')
        k64 = mlx_astype(three, MLX_DTYPES%int64)
        call mlx_to(many, k64)
        call assert_true(any(many(:, 1) /= many(:, 2)) .and. any(many(:, 2) /= many(:, 3)), 'the keys of a split into 3 differ')
        r = mlx_random_uniform([1000], key=key)
        call mlx_to(u, r)
        r = mlx_random_uniform([1000], key=key)
        call mlx_to(v, r)
        call assert_true(all(bits_equal(u, v)), 'the same key gives the same sample, bit for bit')
        r = mlx_random_uniform([1000], key=first)
        call mlx_to(v, r)
        call assert_true(count(bits_equal(u, v)) < 10, 'a split key gives another sample')
        r = mlx_random_uniform([1000], key=second)
        call mlx_to(u, r)
        call assert_true(count(bits_equal(u, v)) < 10, 'the two keys of a split give different samples')
    end subroutine test_keys

    ! the global key: seeding it repeats the draws that follow, and every draw advances it
    subroutine test_seed
        type(mlx_array) :: r, key, first, second
        real(real32)    :: a(16), b(16), c(16)
        write(*,'(a)') 'test_seed'
        call mlx_random_seed(7)
        r = mlx_random_uniform([16])
        call mlx_to(a, r)
        r = mlx_random_uniform([16])
        call mlx_to(c, r)
        call mlx_random_seed(7)
        r = mlx_random_uniform([16])
        call mlx_to(b, r)
        call assert_true(all(bits_equal(a, b)), 'the first draw after mlx_random_seed(7) repeats, bit for bit')
        call assert_true(count(bits_equal(a, c)) < 4, 'the second draw without a key is another sample')
        call mlx_random_seed(7_int64)
        r = mlx_random_uniform([16])
        call mlx_to(b, r)
        call assert_true(all(bits_equal(a, b)), 'a 64-bit seed of the same value seeds the same key')
        call mlx_random_seed(8)
        r = mlx_random_uniform([16])
        call mlx_to(b, r)
        call assert_true(count(bits_equal(a, b)) < 4, 'another seed gives another sample')
        key = mlx_random_key(4294967301_int64)
        call mlx_random_split(key, first, second)
        r = mlx_random_uniform([16], key=second)
        call mlx_to(a, r)
        call mlx_random_seed(4294967301_int64)
        r = mlx_random_uniform([16])
        call mlx_to(b, r)
        call assert_true(all(bits_equal(a, b)), 'the first draw after a seed uses the second key of the split of that seed''s key, all 64 bits of it')
        call test_keyless
        call test_keyed
    end subroutine test_seed

    ! every sampler honours the key it is given: two draws with one key are the same sample, whatever the global
    ! key did in between
    subroutine test_keyed
        type(mlx_array) :: r(11), again(11), key, logits, loc
        real(real32)    :: x(8), y(8)
        integer         :: pass, i
        logical         :: same
        write(*,'(a)') 'test_keyed'
        key = mlx_random_key(77)
        logits = mlx_from([0._real32, 0.5_real32, 1._real32])
        loc = mlx_from([1._real32, 2._real32])
        do pass = 1, 2
            r(1) = mlx_random_normal([8], key=key)
            r(2) = mlx_random_normal([2, 4], loc, key=key)
            r(3) = mlx_random_laplace([8], key=key)
            r(4) = mlx_random_gumbel([8], key=key)
            r(5) = mlx_astype(mlx_random_bits([8], width=2, key=key), MLX_DTYPES%float32)
            r(6) = mlx_astype(mlx_random_bernoulli([8], mlx_from(0.5_real32), key=key), MLX_DTYPES%float32)
            r(7) = mlx_astype(mlx_random_permutation(8, key=key), MLX_DTYPES%float32)
            r(8) = mlx_astype(mlx_random_categorical(logits, num_samples=8, key=key), MLX_DTYPES%float32)
            r(9) = mlx_astype(mlx_random_categorical(logits, shape=[8], key=key), MLX_DTYPES%float32)
            r(10) = mlx_random_truncated_normal([8], mlx_from(-1._real32), mlx_from(1._real32), key=key)
            r(11) = mlx_astype(mlx_random_randint([8], mlx_from(0_int32), mlx_from(1000_int32), key=key), MLX_DTYPES%float32)
            if( pass == 1 )then
                do i = 1, 11
                    again(i) = r(i)
                end do
            endif
        end do
        same = .true.
        do i = 1, 11
            call mlx_to(x, again(i))
            call mlx_to(y, r(i))
            if( .not. all(bits_equal(x, y)) ) same = .false.
        end do
        call assert_true(same, 'eleven samplers give the same sample twice with one key')
    end subroutine test_keyed

    ! every sampler draws from the global key when it is given none: the draws repeat after the same seed
    subroutine test_keyless
        type(mlx_array) :: r(11), again(11), logits, loc
        real(real32)    :: x(8), y(8)
        integer(int32)  :: n(8)
        integer         :: pass, i
        logical         :: same
        write(*,'(a)') 'test_keyless'
        logits = mlx_from([0._real32, 0.5_real32, 1._real32])
        loc = mlx_from([1._real32, 2._real32])
        do pass = 1, 2
            call mlx_random_seed(21)
            r(1) = mlx_random_normal([8])
            r(2) = mlx_random_normal([2, 4], loc)
            r(3) = mlx_random_laplace([8])
            r(4) = mlx_random_gumbel([8])
            r(5) = mlx_astype(mlx_random_bits([8], width=2), MLX_DTYPES%float32)
            r(6) = mlx_astype(mlx_random_bernoulli([8], mlx_from(0.5_real32)), MLX_DTYPES%float32)
            r(7) = mlx_astype(mlx_random_permutation(8), MLX_DTYPES%float32)
            r(8) = mlx_astype(mlx_random_categorical(logits, num_samples=8), MLX_DTYPES%float32)
            r(9) = mlx_astype(mlx_random_categorical(logits, shape=[8]), MLX_DTYPES%float32)
            r(10) = mlx_random_truncated_normal([8], mlx_from(-1._real32), mlx_from(1._real32))
            r(11) = mlx_astype(mlx_random_randint([8], mlx_from(0_int32), mlx_from(1000_int32)), MLX_DTYPES%float32)
            if( pass == 1 )then
                do i = 1, 11
                    again(i) = r(i)
                end do
            endif
        end do
        same = .true.
        do i = 1, 11
            call mlx_to(x, again(i))
            call mlx_to(y, r(i))
            if( .not. all(bits_equal(x, y)) ) same = .false.
        end do
        call assert_true(same, 'eleven samplers without a key repeat their draws after the same seed')
        call mlx_to(n, mlx_random_permutation(8))
        call assert_true(sum(n) == 36 .and. minval(n) == 1 .and. maxval(n) == 8, 'a permutation of 1 to 8 without a key holds 1 to 8')
    end subroutine test_keyless

    ! a sample has the Fortran shape asked for and, under one key, the same elements in array element order
    ! whatever the shape
    subroutine test_shapes
        type(mlx_array) :: key, r
        real(real32)    :: grid(4, 3), line(12), one
        write(*,'(a)') 'test_shapes'
        key = mlx_random_key(11)
        r = mlx_random_uniform([4, 3], key=key)
        call assert_true(all(r%shape() == [4, 3]), 'a sample of shape [4, 3] is a (4, 3) array')
        call mlx_to(grid, r)
        r = mlx_random_uniform([12], key=key)
        call mlx_to(line, r)
        call assert_true(all(bits_equal(reshape(grid, [12]), line)), 'a (4, 3) and a (12) sample of one key hold the same elements in array element order')
        r = mlx_random_normal([integer ::], key=key)
        call assert_int(0, r%ndim(), 'an empty shape gives a rank-0 sample')
        call mlx_to(line(1:1), r)
        one = line(1)
        r = mlx_random_normal([1], key=key)
        call mlx_to(line(1:1), r)
        call assert_true(bits_equal(one, line(1)), 'the rank-0 sample of a key is the first element of its rank-1 sample')
        r = mlx_random_gumbel([2, 3, 4], key=key)
        call assert_true(all(r%shape() == [2, 3, 4]), 'a rank-3 sample has its three extents in Fortran order')
        r = mlx_random_normal([2, 3, 4], key=key)
        call assert_true(all(r%shape() == [2, 3, 4]), 'a rank-3 normal sample has its three extents in Fortran order')
        r = mlx_random_laplace([2, 3], key=key)
        call assert_true(all(r%shape() == [2, 3]), 'a rank-2 Laplace sample has its two extents in Fortran order')
        r = mlx_random_bits([3, 2], key=key)
        call assert_true(all(r%shape() == [3, 2]), 'random bits have the shape asked for')
        r = mlx_random_bernoulli([5, 2], mlx_from(0.5_real32), key=key)
        call assert_true(all(r%shape() == [5, 2]), 'a boolean sample has the shape asked for')
        r = mlx_random_randint([2, 7], mlx_from(0_int32), mlx_from(9_int32), key=key)
        call assert_true(all(r%shape() == [2, 7]), 'an integer sample has the shape asked for')
    end subroutine test_shapes

    ! the dtypes of the samples: what MLX defaults to and what dtype= asks for
    subroutine test_dtypes( device )
        integer, intent(in) :: device
        type(mlx_array) :: key, r, wide
        integer(int32)  :: bytes(4096)
        write(*,'(a)') 'test_dtypes'
        key = mlx_random_key(5)
        r = mlx_random_bits([8], key=key)
        call assert_true(r%kind() == MLX_DTYPES%uint32, 'random bits are uint32 by default')
        r = mlx_random_bits([8], width=2, key=key)
        call assert_true(r%kind() == MLX_DTYPES%uint16, 'random bits of width 2 are uint16')
        r = mlx_random_bits([4096], width=1, key=key)
        call assert_true(r%kind() == MLX_DTYPES%uint8, 'random bits of width 1 are uint8')
        wide = mlx_astype(r, MLX_DTYPES%int32)
        call mlx_to(bytes, wide)
        call assert_true(minval(bytes) >= 0 .and. maxval(bytes) <= 255 .and. maxval(bytes) > 127, 'random bytes lie in 0 to 255 and use the high bit')
        r = mlx_random_uniform([8], key=key)
        call assert_true(r%kind() == MLX_DTYPES%float32, 'a uniform sample is float32 by default')
        r = mlx_random_uniform([8], dtype=MLX_DTYPES%float16, key=key)
        call assert_true(r%kind() == MLX_DTYPES%float16, 'a uniform sample takes a 16-bit float dtype')
        r = mlx_random_gumbel([8], key=key)
        call assert_true(r%kind() == MLX_DTYPES%float32, 'a Gumbel sample is float32 by default')
        r = mlx_random_laplace([8], key=key)
        call assert_true(r%kind() == MLX_DTYPES%float32, 'a Laplace sample is float32 by default')
        r = mlx_random_randint([8], mlx_from(0_int32), mlx_from(5_int32), key=key)
        call assert_true(r%kind() == MLX_DTYPES%int32, 'random integers are int32 by default')
        r = mlx_random_randint([8], mlx_from(0_int32), mlx_from(5_int32), dtype=MLX_DTYPES%int64, key=key)
        call assert_true(r%kind() == MLX_DTYPES%int64, 'random integers take an integer dtype')
        r = mlx_random_bernoulli([8], mlx_from(0.5_real32), key=key)
        call assert_true(r%kind() == MLX_DTYPES%bool, 'a Bernoulli sample is boolean')
        r = mlx_random_gumbel([8], dtype=MLX_DTYPES%float16, key=key)
        call assert_true(r%kind() == MLX_DTYPES%float16, 'a Gumbel sample takes a 16-bit float dtype')
        r = mlx_random_normal([2], mlx_from([1._real32, 2._real32]), dtype=MLX_DTYPES%float16, key=key)
        call assert_true(r%kind() == MLX_DTYPES%float16, 'a normal sample with an array mean takes a 16-bit float dtype')
        r = mlx_random_truncated_normal([8], mlx_from(-1._real32), mlx_from(1._real32), dtype=MLX_DTYPES%float16, key=key)
        call assert_true(r%kind() == MLX_DTYPES%float16, 'a truncated normal sample takes a 16-bit float dtype')
        if( device == MLX_DEVICES%cpu )then
            r = mlx_random_normal([8], dtype=MLX_DTYPES%float64, key=key)
            call assert_true(r%kind() == MLX_DTYPES%float64, 'a normal sample is float64 on the CPU device when asked')
            r = mlx_random_laplace([8], dtype=MLX_DTYPES%float64, key=key)
            call assert_true(r%kind() == MLX_DTYPES%float64, 'a Laplace sample is float64 on the CPU device when asked')
        endif
    end subroutine test_dtypes

    ! the real samplers with scalar parameters, each on RANDOM_NSAMPLES values of one key
    subroutine test_real_samplers( seed )
        integer, intent(in) :: seed
        type(mlx_array)              :: key, keys, r
        type(mlx_array), allocatable :: part(:)
        real(real32),    allocatable :: x(:), unit(:)
        real(real64)                 :: lo, hi, b
        write(*,'(a,i0)') 'test_real_samplers seed=', seed
        allocate(x(RANDOM_NSAMPLES))
        key = mlx_random_key(seed)
        call mlx_random_split(key, 6, keys)
        call mlx_unstack(keys, part)
        call assert_int(6, size(part), 'mlx_unstack turns a split into 6 into a list of 6 keys')
        r = mlx_random_uniform([RANDOM_NSAMPLES], key=part(1))
        call mlx_to(x, r)
        call judge_moments(real(x, real64), uniform_moments(0._real64, 1._real64), 'mlx_random_uniform', seed)
        call assert_true(minval(x) >= 0._real32 .and. maxval(x) < 1._real32, 'a uniform sample lies in [0, 1)')
        lo = -1._real64
        hi = 3._real64
        r = mlx_random_uniform([RANDOM_NSAMPLES], low=mlx_from(-1._real32), high=mlx_from(3._real32), key=part(2))
        call mlx_to(x, r)
        call judge_moments(real(x, real64), uniform_moments(lo, hi), 'mlx_random_uniform bounds', seed)
        call assert_true(minval(x) >= -1._real32 .and. maxval(x) < 3._real32, 'a uniform sample lies in [low, high)')
        r = mlx_random_uniform([RANDOM_NSAMPLES], key=part(2))
        allocate(unit(RANDOM_NSAMPLES))
        call mlx_to(unit, r)
        call assert_true(all(abs(real(x, real64)-(4._real64*real(unit, real64)-1._real64)) <= 1.e-6_real64), 'a uniform sample is low + (high - low) u, u the unit sample of the same key')
        r = mlx_random_normal([RANDOM_NSAMPLES], key=part(3))
        call mlx_to(x, r)
        call judge_moments(real(x, real64), moments(0._real64, 1._real64, 3._real64), 'mlx_random_normal', seed)
        r = mlx_random_normal([RANDOM_NSAMPLES], loc=1.5_real32, scale=2._real32, key=part(3))
        call mlx_to(x, r)
        call judge_moments(real(x, real64), moments(1.5_real64, 4._real64, 48._real64), 'mlx_random_normal loc scale', seed)
        b = 0.75_real64
        r = mlx_random_laplace([RANDOM_NSAMPLES], loc=-2._real32, scale=0.75_real32, key=part(4))
        call mlx_to(x, r)
        call judge_moments(real(x, real64), moments(-2._real64, 2._real64*b**2, 24._real64*b**4), 'mlx_random_laplace', seed)
        r = mlx_random_gumbel([RANDOM_NSAMPLES], key=part(5))
        call mlx_to(x, r)
        call judge_moments(real(x, real64), moments(EULER_GAMMA, PI**2/6._real64, 5.4_real64*(PI**2/6._real64)**2), 'mlx_random_gumbel', seed)
        lo = -1._real64
        hi = 2._real64
        r = mlx_random_truncated_normal([RANDOM_NSAMPLES], mlx_from(-1._real32), mlx_from(2._real32), key=part(6))
        call mlx_to(x, r)
        call judge_moments(real(x, real64), truncated_moments(lo, hi), 'mlx_random_truncated_normal', seed)
        call assert_true(minval(x) >= -1._real32 .and. maxval(x) <= 2._real32, 'a truncated normal sample lies in [lower, upper]')
    end subroutine test_real_samplers

    ! parameters that are arrays broadcast with leading Fortran dimensions aligned: a (2, 1) mean and deviation
    ! give two rows of a (2, n) sample their own distributions
    subroutine test_broadcast_parameters( seed )
        integer, intent(in) :: seed
        type(mlx_array)           :: key, k1, k2, loc, scale, low, high, r
        real(real32), allocatable :: x(:, :)
        real(real32)              :: centre(2, 1), width(2, 1)
        integer                   :: half
        write(*,'(a,i0)') 'test_broadcast_parameters seed=', seed
        half = RANDOM_NSAMPLES/2
        allocate(x(2, half))
        key = mlx_random_key(seed)
        call mlx_random_split(key, k1, k2)
        centre(:, 1) = [-1._real32, 2._real32]
        width(:, 1) = [0.5_real32, 3._real32]
        loc = mlx_from(centre)
        scale = mlx_from(width)
        r = mlx_random_normal([2, half], loc, scale, key=k1)
        call assert_true(all(r%shape() == [2, half]), 'a normal sample with array parameters has the shape asked for')
        call mlx_to(x, r)
        call judge_moments(real(x(1, :), real64), moments(-1._real64, 0.25_real64, 0.1875_real64), 'mlx_random_normal arrays row 1', seed)
        call judge_moments(real(x(2, :), real64), moments(2._real64, 9._real64, 243._real64), 'mlx_random_normal arrays row 2', seed)
        r = mlx_random_normal([2, half], loc, key=k1)
        call mlx_to(x, r)
        call judge_moments(real(x(1, :), real64), moments(-1._real64, 1._real64, 3._real64), 'mlx_random_normal loc array row 1', seed)
        call judge_moments(real(x(2, :), real64), moments(2._real64, 1._real64, 3._real64), 'mlx_random_normal loc array row 2', seed)
        centre(:, 1) = [-1._real32, 10._real32]
        width(:, 1) = [3._real32, 12._real32]
        low = mlx_from(centre)
        high = mlx_from(width)
        r = mlx_random_uniform([2, half], low=low, high=high, key=k2)
        call mlx_to(x, r)
        call judge_moments(real(x(1, :), real64), uniform_moments(-1._real64, 3._real64), 'mlx_random_uniform arrays row 1', seed)
        call judge_moments(real(x(2, :), real64), uniform_moments(10._real64, 12._real64), 'mlx_random_uniform arrays row 2', seed)
    end subroutine test_broadcast_parameters

    ! integers, booleans and bits: the moments of the discrete uniform and of the Bernoulli distribution
    subroutine test_integer_samplers( seed )
        integer, intent(in) :: seed
        type(mlx_array)              :: key, keys, r, wide
        type(mlx_array), allocatable :: part(:)
        integer(int32),  allocatable :: n(:)
        integer(int64),  allocatable :: big(:)
        real(real64)                 :: p, two32
        integer                      :: v
        logical                      :: every
        write(*,'(a,i0)') 'test_integer_samplers seed=', seed
        allocate(n(RANDOM_NSAMPLES), big(RANDOM_NSAMPLES))
        key = mlx_random_key(seed)
        call mlx_random_split(key, 3, keys)
        call mlx_unstack(keys, part)
        r = mlx_random_randint([RANDOM_NSAMPLES], mlx_from(-3_int32), mlx_from(7_int32), key=part(1))
        call mlx_to(n, r)
        call assert_true(minval(n) == -3 .and. maxval(n) == 6, 'random integers run from low to high - 1')
        every = .true.
        do v = -3, 6
            if( count(n == v) == 0 ) every = .false.
        end do
        call assert_true(every, 'every integer from low to high - 1 is drawn')
        call judge_moments(real(n, real64), integer_moments(-3._real64, 10._real64), 'mlx_random_randint', seed)
        p = 0.3_real64
        r = mlx_random_bernoulli([RANDOM_NSAMPLES], mlx_from(0.3_real32), key=part(2))
        wide = mlx_astype(r, MLX_DTYPES%int32)
        call mlx_to(n, wide)
        call assert_true(all(n == 0 .or. n == 1), 'a Bernoulli sample holds false and true only')
        call judge_moments(real(n, real64), moments(p, p*(1._real64-p), p*(1._real64-p)*(1._real64-3._real64*p*(1._real64-p))), 'mlx_random_bernoulli', seed)
        r = mlx_random_bits([RANDOM_NSAMPLES], key=part(3))
        wide = mlx_astype(r, MLX_DTYPES%int64)
        call mlx_to(big, wide)
        two32 = 2._real64**32
        call assert_true(minval(big) >= 0_int64 .and. maxval(big) < 4294967296_int64, 'random bits of width 4 lie in 0 to 2**32 - 1')
        call judge_moments(real(big, real64), integer_moments(0._real64, two32), 'mlx_random_bits', seed)
    end subroutine test_integer_samplers

    ! vectors along dimension 1 with a given mean and covariance; a (3, 2) mean gives each of two batches its own
    subroutine test_multivariate_normal( seed )
        integer, intent(in) :: seed
        type(mlx_array)           :: key, k1, k2, mean, cov, means, r
        real(real32), allocatable :: x(:, :), xb(:, :, :)
        real(real32)              :: mu(3), sigma(3, 3), mus(3, 2)
        real(real64)              :: z, zmax, zcov, m(3), c, se
        integer                   :: i, j, n, nb, b
        character(len=160)        :: line
        write(*,'(a,i0)') 'test_multivariate_normal seed=', seed
        n = RANDOM_NSAMPLES/4
        nb = RANDOM_NSAMPLES/8
        allocate(x(3, n), xb(3, 2, nb))
        mu = [1._real32, -2._real32, 0.5_real32]
        sigma = reshape([2._real32, 0.6_real32, 0._real32, 0.6_real32, 1._real32, -0.3_real32, 0._real32, -0.3_real32, 0.5_real32], [3, 3])
        key = mlx_random_key(seed)
        call mlx_random_split(key, k1, k2)
        mean = mlx_from(mu)
        cov = mlx_from(sigma)
        r = mlx_random_multivariate_normal(mean, cov, shape=[n], key=k1)
        call assert_true(all(r%shape() == [3, n]), 'n vectors of 3 components are a (3, n) array: a vector along dimension 1')
        call assert_true(r%kind() == MLX_DTYPES%float32, 'a multivariate normal sample is float32')
        call mlx_to(x, r)
        zmax = 0._real64
        zcov = 0._real64
        do i = 1, 3
            m(i) = sum(real(x(i, :), real64))/real(n, real64)
            z = abs(m(i)-real(mu(i), real64))/sqrt(real(sigma(i, i), real64)/real(n, real64))
            zmax = nan_max(zmax, z)
        end do
        do j = 1, 3
            do i = 1, 3
                c = sum((real(x(i, :), real64)-m(i))*(real(x(j, :), real64)-m(j)))/real(n-1, real64)
                se = sqrt((real(sigma(i, i), real64)*real(sigma(j, j), real64)+real(sigma(i, j), real64)**2)/real(n, real64))
                zcov = nan_max(zcov, abs(c-real(sigma(i, j), real64))/se)
            end do
        end do
        write(line,'(a,i0,a,f7.3,a,f7.3)') '    moments mlx_random_multivariate_normal '//device_name(mlx_default_device())//' seed=', seed, &
            &': mean z=', zmax, ', covariance z=', zcov
        write(output_unit,'(a)') trim(line)
        call assert_true(zmax <= RANDOM_SIGMAS, 'the means of a multivariate normal sample are within the standard errors allowed')
        call assert_true(zcov <= RANDOM_SIGMAS, 'the covariances of a multivariate normal sample are within the standard errors allowed')
        mus(:, 1) = mu
        mus(:, 2) = [-4._real32, 3._real32, 8._real32]
        means = mlx_from(mus)
        r = mlx_random_multivariate_normal(means, cov, shape=[2, nb], key=k2)
        call assert_true(all(r%shape() == [3, 2, nb]), 'a (3, 2) mean and a batch shape [2, nb] give a (3, 2, nb) array')
        call mlx_to(xb, r)
        zmax = 0._real64
        do b = 1, 2
            do i = 1, 3
                z = abs(sum(real(xb(i, b, :), real64))/real(nb, real64)-real(mus(i, b), real64))/sqrt(real(sigma(i, i), real64)/real(nb, real64))
                zmax = nan_max(zmax, z)
            end do
        end do
        write(line,'(a,i0,a,f7.3)') '    moments mlx_random_multivariate_normal batches '//device_name(mlx_default_device())//' seed=', seed, &
            &': mean z=', zmax
        write(output_unit,'(a)') trim(line)
        call assert_true(zmax <= RANDOM_SIGMAS, 'each batch of a multivariate normal sample has the mean of its column of means')
        r = mlx_random_multivariate_normal(mean, cov, key=k1)
        call assert_true(all(r%shape() == [3]), 'without a shape a multivariate normal draw is one vector')
        r = mlx_random_multivariate_normal(means, cov)
        call assert_true(all(r%shape() == [3, 2]), 'without a shape and a key, one vector per column of means')
        call mlx_to(xb(:, :, 1), r)
        call assert_true(all(abs(xb(:, :, 1)) < 100._real32), 'a multivariate normal draw from the global key evaluates')
    end subroutine test_multivariate_normal

    ! the frequencies of the categories against the probabilities the logits give, along dimension 1 and along 2
    subroutine test_categorical_frequencies( seed )
        integer, intent(in) :: seed
        type(mlx_array)             :: key, k1, k2, logits, r
        integer(int32), allocatable :: c(:), cb(:, :)
        real(real32)                :: prob(3), probs(2, 3)
        real(real64)                :: z, zmax, f, p
        integer                     :: i, j, half
        character(len=160)          :: line
        write(*,'(a,i0)') 'test_categorical_frequencies seed=', seed
        half = RANDOM_NSAMPLES/2
        allocate(c(RANDOM_NSAMPLES), cb(half, 2))
        key = mlx_random_key(seed)
        call mlx_random_split(key, k1, k2)
        prob = [0.2_real32, 0.5_real32, 0.3_real32]
        logits = mlx_from(log(prob))
        r = mlx_random_categorical(logits, num_samples=RANDOM_NSAMPLES, key=k1)
        call assert_true(r%kind() == MLX_DTYPES%int32, 'categories are int32')
        call assert_true(all(r%shape() == [RANDOM_NSAMPLES]), 'num_samples draws of one distribution are a rank-1 array')
        call mlx_to(c, r)
        call assert_true(minval(c) == 1 .and. maxval(c) == 3, 'three categories are numbered 1 to 3')
        zmax = 0._real64
        do i = 1, 3
            p = real(prob(i), real64)
            f = real(count(c == i), real64)/real(RANDOM_NSAMPLES, real64)
            z = abs(f-p)/sqrt(p*(1._real64-p)/real(RANDOM_NSAMPLES, real64))
            zmax = nan_max(zmax, z)
        end do
        probs(1, :) = [0.7_real32, 0.2_real32, 0.1_real32]
        probs(2, :) = [0.1_real32, 0.1_real32, 0.8_real32]
        logits = mlx_from(log(probs))
        r = mlx_random_categorical(logits, dim=2, num_samples=half, key=k2)
        call assert_true(all(r%shape() == [half, 2]), 'num_samples draws of two distributions along dimension 2 are a (num_samples, 2) array')
        call mlx_to(cb, r)
        call assert_true(minval(cb) == 1 .and. maxval(cb) == 3, 'categories along dimension 2 are numbered 1 to 3')
        do j = 1, 2
            do i = 1, 3
                p = real(probs(j, i), real64)
                f = real(count(cb(:, j) == i), real64)/real(half, real64)
                z = abs(f-p)/sqrt(p*(1._real64-p)/real(half, real64))
                zmax = nan_max(zmax, z)
            end do
        end do
        write(line,'(a,i0,a,f7.3)') '    moments mlx_random_categorical '//device_name(mlx_default_device())//' seed=', seed, &
            &': frequency z=', zmax
        write(output_unit,'(a)') trim(line)
        call assert_true(zmax <= RANDOM_SIGMAS, 'the frequencies of the categories are within the standard errors allowed')
    end subroutine test_categorical_frequencies

    ! logits with one overwhelming category per distribution give that category, numbered from 1, in the layout
    ! each form documents
    subroutine test_categorical_exact
        type(mlx_array)    :: key, logits, r
        real(real32)       :: sure(3, 4), across(4, 3)
        integer(int32)     :: got(4), many(5, 4), shaped(4, 5)
        integer            :: j
        integer, parameter :: WINNER(4) = [2, 3, 1, 3]
        write(*,'(a)') 'test_categorical_exact'
        sure = 0._real32
        across = 0._real32
        do j = 1, 4
            sure(WINNER(j), j) = 60._real32
            across(j, WINNER(j)) = 60._real32
        end do
        key = mlx_random_key(3)
        logits = mlx_from(sure)
        r = mlx_random_categorical(logits, key=key)
        call assert_true(all(r%shape() == [4]), 'one category per distribution: the logits'' other dimensions')
        call mlx_to(got, r)
        call assert_true(all(got == WINNER), 'the category along dimension 1 is one-based: the row of the largest logit')
        r = mlx_random_categorical(logits)
        call mlx_to(got, r)
        call assert_true(all(got == WINNER), 'without a key the global key draws the same certain categories')
        r = mlx_random_categorical(logits, num_samples=5, key=key)
        call assert_true(all(r%shape() == [5, 4]), 'num_samples is a new first dimension')
        call mlx_to(many, r)
        call assert_true(all(many == spread(WINNER, 1, 5)), 'every draw of a distribution is its certain category')
        r = mlx_random_categorical(logits, shape=[4, 5], key=key)
        call assert_true(all(r%shape() == [4, 5]), 'a shape whose first extent is the number of distributions is the sample''s shape')
        call mlx_to(shaped, r)
        call assert_true(all(shaped == spread(WINNER, 2, 5)), 'the distributions lie along the first dimension of a shaped sample')
        logits = mlx_from(across)
        r = mlx_random_categorical(logits, dim=2, key=key)
        call assert_true(all(r%shape() == [4]), 'categories along dimension 2 leave dimension 1')
        call mlx_to(got, r)
        call assert_true(all(got == WINNER), 'the category along dimension 2 is the column of the largest logit')
        r = mlx_random_categorical(logits, dim=2, shape=[4, 5], key=key)
        call mlx_to(shaped, r)
        call assert_true(all(shaped == spread(WINNER, 2, 5)), 'a shaped sample of categories along dimension 2 keeps the distributions along its first dimension')
        r = mlx_random_categorical(logits, dim=2, num_samples=5, key=key)
        call mlx_to(many, r)
        call assert_true(all(many == spread(WINNER, 1, 5)), 'num_samples draws of categories along dimension 2 are a new first dimension')
    end subroutine test_categorical_exact

    ! a permutation of 1 to n holds every number once; an array is permuted by whole slices along a dimension
    subroutine test_permutation
        type(mlx_array) :: key, r, a
        integer(int32)  :: p(1024), q(1024), cols(2, 64), rows(64, 2), moved(2, 64), down(64, 2)
        logical         :: seen(1024), whole
        integer         :: i, j
        write(*,'(a)') 'test_permutation'
        key = mlx_random_key(9)
        r = mlx_random_permutation(1024, key=key)
        call assert_true(r%kind() == MLX_DTYPES%int32, 'a permutation of 1 to n is int32')
        call assert_true(all(r%shape() == [1024]), 'a permutation of 1 to n has n elements')
        call mlx_to(p, r)
        seen = .false.
        do i = 1, 1024
            if( p(i) >= 1 .and. p(i) <= 1024 ) seen(p(i)) = .true.
        end do
        call assert_true(all(seen), 'a permutation of 1 to 1024 holds every number from 1 to 1024 once')
        call assert_true(count(p == [(i, i=1, 1024)]) < 32, 'and is not the identity')
        r = mlx_random_permutation(1024, key=key)
        call mlx_to(q, r)
        call assert_true(all(p == q), 'the same key gives the same permutation')
        do j = 1, 64
            cols(:, j) = [j, 100+j]
            rows(j, :) = [j, 100+j]
        end do
        a = mlx_from(cols)
        r = mlx_random_permutation(a, key=key)
        call assert_true(all(r%shape() == [2, 64]), 'a permuted array keeps its shape')
        call mlx_to(moved, r)
        whole = all(moved(2, :) == moved(1, :)+100)
        seen = .false.
        do j = 1, 64
            if( moved(1, j) >= 1 .and. moved(1, j) <= 64 ) seen(moved(1, j)) = .true.
        end do
        call assert_true(whole .and. all(seen(1:64)), 'without dim the slices along the last dimension are permuted whole: the columns of a matrix')
        call assert_true(count(moved(1, :) == cols(1, :)) < 16, 'and they change places')
        a = mlx_from(rows)
        r = mlx_random_permutation(a, dim=1, key=key)
        call mlx_to(down, r)
        whole = all(down(:, 2) == down(:, 1)+100)
        seen = .false.
        do j = 1, 64
            if( down(j, 1) >= 1 .and. down(j, 1) <= 64 ) seen(down(j, 1)) = .true.
        end do
        call assert_true(whole .and. all(seen(1:64)), 'with dim=1 the rows of a matrix are permuted whole')
        call assert_true(count(down(:, 1) == rows(:, 1)) < 16, 'and they change places')
        r = mlx_random_permutation(a, dim=2, key=key)
        call mlx_to(down, r)
        call assert_true(all(down(:, 1) == rows(:, 1) .and. down(:, 2) == rows(:, 2)) .or. all(down(:, 1) == rows(:, 2) .and. down(:, 2) == rows(:, 1)), &
            &'with dim=2 the two columns stay whole, in either order')
    end subroutine test_permutation

    ! the sample mean and the unbiased sample variance of x against a distribution's, each in standard errors of
    ! its estimator: sqrt(var/n) for the mean, sqrt((fourth - var**2)/n) for the variance
    subroutine judge_moments( x, want, label, seed )
        real(real64),     intent(in) :: x(:)
        type(moments),    intent(in) :: want
        character(len=*), intent(in) :: label
        integer,          intent(in) :: seed
        real(real64)       :: n, mean, var, zmean, zvar
        character(len=160) :: line
        n = real(size(x), real64)
        mean = sum(x)/n
        var = sum((x-mean)**2)/(n-1._real64)
        zmean = abs(mean-want%mean)/sqrt(want%var/n)
        zvar = abs(var-want%var)/sqrt((want%fourth-want%var**2)/n)
        write(line,'(a,i0,a,f7.3,a,f7.3)') '    moments '//trim(label)//' '//device_name(mlx_default_device())//' seed=', seed, &
            &': mean z=', zmean, ', variance z=', zvar
        write(output_unit,'(a)') trim(line)
        call assert_true(zmean <= RANDOM_SIGMAS, trim(label)//': the sample mean is within the standard errors allowed')
        call assert_true(zvar <= RANDOM_SIGMAS, trim(label)//': the sample variance is within the standard errors allowed')
    end subroutine judge_moments

    ! the uniform distribution on [lo, hi)
    function uniform_moments( lo, hi ) result(m)
        real(real64), intent(in) :: lo, hi
        type(moments) :: m
        m%mean = 0.5_real64*(lo+hi)
        m%var = (hi-lo)**2/12._real64
        m%fourth = (hi-lo)**4/80._real64
    end function uniform_moments

    ! the uniform distribution on the count consecutive integers from first
    function integer_moments( first, count ) result(m)
        real(real64), intent(in) :: first, count
        type(moments) :: m
        m%mean = first+0.5_real64*(count-1._real64)
        m%var = (count**2-1._real64)/12._real64
        m%fourth = (count**2-1._real64)*(3._real64*count**2-7._real64)/240._real64
    end function integer_moments

    ! the standard normal distribution kept inside [lo, hi]: its raw moments follow from
    ! m(k) = (k-1) m(k-2) - (hi**(k-1) phi(hi) - lo**(k-1) phi(lo))/z, with z the probability of the interval
    function truncated_moments( lo, hi ) result(m)
        real(real64), intent(in) :: lo, hi
        type(moments) :: m
        real(real64)  :: z, raw(0:4), plo, phi
        integer       :: k
        plo = exp(-0.5_real64*lo**2)/sqrt(2._real64*PI)
        phi = exp(-0.5_real64*hi**2)/sqrt(2._real64*PI)
        z = 0.5_real64*(erfc(-hi/sqrt(2._real64))-erfc(-lo/sqrt(2._real64)))
        raw(0) = 1._real64
        raw(1) = -(phi-plo)/z
        do k = 2, 4
            raw(k) = real(k-1, real64)*raw(k-2)-(hi**(k-1)*phi-lo**(k-1)*plo)/z
        end do
        m%mean = raw(1)
        m%var = raw(2)-raw(1)**2
        m%fourth = raw(4)-4._real64*raw(1)*raw(3)+6._real64*raw(1)**2*raw(2)-3._real64*raw(1)**4
    end function truncated_moments

end module mlxf_random_tester
