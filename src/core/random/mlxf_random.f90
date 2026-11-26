!@descr: random keys and samplers: samples in Fortran shapes, parameters that broadcast, one-based categories and permutations
! MLX's generator is counter-based: a sample is a function of its key and its shape. A sampler given a key is
! deterministic; without one it takes MLX's global key, which mlx_random_seed sets and every draw advances. A
! sample of Fortran shape (n1, ..., nr) is MLX's sample of shape [nr, ..., n1] for the same key, read in
! Fortran's array element order.
module mlxf_random
use, intrinsic :: iso_c_binding,   only: c_int64_t
use, intrinsic :: iso_fortran_env, only: int32, int64, real32
use mlxf_c_random, only: mlxc_random_seed, mlxc_random_key, mlxc_random_split, mlxc_random_split_num, mlxc_random_bits, &
                         mlxc_random_uniform, mlxc_random_normal, mlxc_random_normal_broadcast, mlxc_random_laplace, &
                         mlxc_random_gumbel, mlxc_random_truncated_normal, mlxc_random_randint, mlxc_random_bernoulli, &
                         mlxc_random_multivariate_normal, mlxc_random_categorical, mlxc_random_categorical_num_samples, &
                         mlxc_random_categorical_shape, mlxc_random_permutation, mlxc_random_permutation_arange
use mlxf_defs,     only: MLX_DTYPES, mlxf_random_spec
use mlxf_array,    only: mlx_array, mlx_from, mlx_is_live, mlxf_check_dtype, mlxf_one_based, mlxf_int_op, mlxf_pair_op, &
                         mlxf_random_key_op, mlxf_random_shape_op, mlxf_random_float_op, mlxf_random_int_op, &
                         mlxf_random_array_op, mlxf_random_axis_op, mlxf_random_axis_shape_op, mlxf_random_axis_int_op, &
                         mlxf_random_binary_op, mlxf_random_broadcast_op
use mlxf_device,   only: mlxf_require_device
use mlxf_error,    only: mlxf_check, mlxf_fail
implicit none
public :: mlx_random_seed, mlx_random_key, mlx_random_split, mlx_random_bits, mlx_random_uniform, mlx_random_normal, &
    &mlx_random_laplace, mlx_random_gumbel, mlx_random_truncated_normal, mlx_random_randint, mlx_random_bernoulli, &
    &mlx_random_multivariate_normal, mlx_random_categorical, mlx_random_permutation
private

interface mlx_random_seed
    module procedure random_seed_i32, random_seed_i64
end interface mlx_random_seed

interface mlx_random_key
    module procedure random_key_i32, random_key_i64
end interface mlx_random_key

interface mlx_random_split
    module procedure random_split_pair, random_split_num
end interface mlx_random_split

interface mlx_random_normal
    module procedure random_normal_scalar, random_normal_array
end interface mlx_random_normal

interface mlx_random_permutation
    module procedure random_permutation_array, random_permutation_count
end interface mlx_random_permutation

contains

    ! sets MLX's global key, which the samplers called without a key draw from and advance
    subroutine random_seed_i32( seed )
        integer(int32), intent(in) :: seed
        call mlxf_require_device('mlx_random_seed')
        call mlxf_check(mlxc_random_seed(int(seed, c_int64_t)), 'mlx_random_seed')
    end subroutine random_seed_i32

    ! the same from a 64-bit seed, whose bits MLX reads as an unsigned integer
    subroutine random_seed_i64( seed )
        integer(int64), intent(in) :: seed
        call mlxf_require_device('mlx_random_seed')
        call mlxf_check(mlxc_random_seed(int(seed, c_int64_t)), 'mlx_random_seed')
    end subroutine random_seed_i64

    ! the key of a seed: a uint32 array of two elements, the seed's high and low 32 bits
    function random_key_i32( seed ) result(key)
        integer(int32), intent(in) :: seed
        type(mlx_array) :: key
        call mlxf_random_key_op(key, mlxc_random_key, int(seed, int64), 'mlx_random_key')
    end function random_key_i32

    function random_key_i64( seed ) result(key)
        integer(int64), intent(in) :: seed
        type(mlx_array) :: key
        call mlxf_random_key_op(key, mlxc_random_key, seed, 'mlx_random_key')
    end function random_key_i64

    ! two new keys from key, independent of it and of each other
    subroutine random_split_pair( key, first, second )
        type(mlx_array), intent(in)  :: key
        type(mlx_array), intent(out) :: first, second
        type(mlx_array) :: res(2)
        call mlxf_pair_op(res, mlxc_random_split, key, 'mlx_random_split')
        first = res(1)
        second = res(2)
    end subroutine random_split_pair

    ! num new keys from key as one uint32 array of shape (2, num): key i is keys(:, i)
    subroutine random_split_num( key, num, keys )
        type(mlx_array), intent(in)  :: key
        integer,         intent(in)  :: num
        type(mlx_array), intent(out) :: keys
        call mlxf_int_op(keys, mlxc_random_split_num, key, num, 'mlx_random_split')
    end subroutine random_split_num

    ! random bits as unsigned integers of width bytes (1, 2 or 4, the default: uint8, uint16 or uint32)
    function mlx_random_bits( shape, width, key ) result(r)
        integer,         intent(in)           :: shape(:)
        integer,         optional, intent(in) :: width
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, k(1)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_bits')
        spec%shape = shape
        spec%number = 4
        if( present(width) ) spec%number = width
        call take_key(k(1), 'mlx_random_bits', key)
        call mlxf_random_shape_op(r, mlxc_random_bits, k, spec, 'mlx_random_bits')
    end function mlx_random_bits

    ! uniform samples in [low, high): the bounds are arrays that broadcast to shape, 0 and 1 by default
    function mlx_random_uniform( shape, low, high, dtype, key ) result(r)
        integer,         intent(in)           :: shape(:)
        type(mlx_array), optional, intent(in) :: low, high, key
        integer,         optional, intent(in) :: dtype
        type(mlx_array)        :: r, a(3)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_uniform')
        spec = sample_spec(shape, dtype)
        if( present(low) )then
            a(1) = low
        else
            a(1) = mlx_from(0._real32)
        endif
        if( present(high) )then
            a(2) = high
        else
            a(2) = mlx_from(1._real32)
        endif
        call take_key(a(3), 'mlx_random_uniform', key)
        call mlxf_random_binary_op(r, mlxc_random_uniform, a, spec, 'mlx_random_uniform')
    end function mlx_random_uniform

    ! normal samples of mean loc and standard deviation scale, 0 and 1 by default
    function random_normal_scalar( shape, loc, scale, dtype, key ) result(r)
        integer,         intent(in)           :: shape(:)
        real(real32),    optional, intent(in) :: loc, scale
        integer,         optional, intent(in) :: dtype
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, k(1)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_normal')
        spec = sample_spec(shape, dtype)
        if( present(loc) ) spec%loc = loc
        if( present(scale) ) spec%scale = scale
        call take_key(k(1), 'mlx_random_normal', key)
        call mlxf_random_float_op(r, mlxc_random_normal, k, spec, 'mlx_random_normal')
    end function random_normal_scalar

    ! normal samples whose mean and standard deviation are arrays that broadcast to shape; scale is 1 by default.
    ! An empty handle would reach MLX as an absent parameter, so both are checked here; and MLX does not hold
    ! these two to shape, as it holds the parameters of the other samplers, so the result's shape is checked
    function random_normal_array( shape, loc, scale, dtype, key ) result(r)
        integer,         intent(in)           :: shape(:)
        type(mlx_array), intent(in)           :: loc
        type(mlx_array), optional, intent(in) :: scale, key
        integer,         optional, intent(in) :: dtype
        type(mlx_array)        :: r, a(3)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_normal')
        if( .not. mlx_is_live(loc) ) call mlxf_fail('mlx_random_normal', 'loc is an empty or stale array')
        spec = sample_spec(shape, dtype)
        a(1) = loc
        if( present(scale) )then
            if( .not. mlx_is_live(scale) ) call mlxf_fail('mlx_random_normal', 'scale is an empty or stale array')
            a(2) = scale
        endif
        call take_key(a(3), 'mlx_random_normal', key)
        call mlxf_random_broadcast_op(r, mlxc_random_normal_broadcast, a, spec, 'mlx_random_normal')
        if( r%ndim() /= size(shape) ) call mlxf_fail('mlx_random_normal', 'loc and scale must broadcast to shape')
        if( any(r%shape() /= shape) ) call mlxf_fail('mlx_random_normal', 'loc and scale must broadcast to shape')
    end function random_normal_array

    ! Laplace samples of mean loc and scale parameter scale (the variance is 2 scale**2), 0 and 1 by default
    function mlx_random_laplace( shape, loc, scale, dtype, key ) result(r)
        integer,         intent(in)           :: shape(:)
        real(real32),    optional, intent(in) :: loc, scale
        integer,         optional, intent(in) :: dtype
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, k(1)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_laplace')
        spec = sample_spec(shape, dtype)
        if( present(loc) ) spec%loc = loc
        if( present(scale) ) spec%scale = scale
        call take_key(k(1), 'mlx_random_laplace', key)
        call mlxf_random_float_op(r, mlxc_random_laplace, k, spec, 'mlx_random_laplace')
    end function mlx_random_laplace

    ! samples of the standard Gumbel distribution
    function mlx_random_gumbel( shape, dtype, key ) result(r)
        integer,         intent(in)           :: shape(:)
        integer,         optional, intent(in) :: dtype
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, k(1)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_gumbel')
        spec = sample_spec(shape, dtype)
        call mlxf_check_dtype(spec%dtype, 'mlx_random_gumbel')
        spec%number = spec%dtype
        call take_key(k(1), 'mlx_random_gumbel', key)
        call mlxf_random_shape_op(r, mlxc_random_gumbel, k, spec, 'mlx_random_gumbel')
    end function mlx_random_gumbel

    ! standard normal samples kept inside [lower, upper], arrays that broadcast to shape
    function mlx_random_truncated_normal( shape, lower, upper, dtype, key ) result(r)
        integer,         intent(in)           :: shape(:)
        type(mlx_array), intent(in)           :: lower, upper
        integer,         optional, intent(in) :: dtype
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, a(3)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_truncated_normal')
        spec = sample_spec(shape, dtype)
        a(1) = lower
        a(2) = upper
        call take_key(a(3), 'mlx_random_truncated_normal', key)
        call mlxf_random_binary_op(r, mlxc_random_truncated_normal, a, spec, 'mlx_random_truncated_normal')
    end function mlx_random_truncated_normal

    ! integers drawn uniformly from low to high - 1, arrays that broadcast to shape; int32 by default
    function mlx_random_randint( shape, low, high, dtype, key ) result(r)
        integer,         intent(in)           :: shape(:)
        type(mlx_array), intent(in)           :: low, high
        integer,         optional, intent(in) :: dtype
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, a(3)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_randint')
        spec%shape = shape
        spec%dtype = MLX_DTYPES%int32
        if( present(dtype) ) spec%dtype = dtype
        a(1) = low
        a(2) = high
        call take_key(a(3), 'mlx_random_randint', key)
        call mlxf_random_binary_op(r, mlxc_random_randint, a, spec, 'mlx_random_randint')
    end function mlx_random_randint

    ! booleans that are true with probability p, a real array that broadcasts to shape
    function mlx_random_bernoulli( shape, p, key ) result(r)
        integer,         intent(in)           :: shape(:)
        type(mlx_array), intent(in)           :: p
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, a(2)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_bernoulli')
        spec%shape = shape
        a(1) = p
        call take_key(a(2), 'mlx_random_bernoulli', key)
        call mlxf_random_array_op(r, mlxc_random_bernoulli, a, spec, 'mlx_random_bernoulli')
    end function mlx_random_bernoulli

    ! vectors along dimension 1 drawn from the normal distribution of mean (n, ...) and covariance cov (n, n, ...);
    ! shape is the shape of the batch of vectors, the result (n, shape) broadcast with the batches of mean and cov.
    ! MLX takes the root of cov by a singular value decomposition, so the whole draw runs on the CPU's stream
    function mlx_random_multivariate_normal( mean, cov, shape, dtype, key ) result(r)
        type(mlx_array), intent(in)           :: mean, cov
        integer,         optional, intent(in) :: shape(:), dtype
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, a(3)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_multivariate_normal')
        allocate(spec%shape(0))
        if( present(shape) ) spec%shape = shape
        if( present(dtype) ) spec%dtype = dtype
        spec%on_cpu = .true.
        a(1) = mean
        a(2) = cov
        call take_key(a(3), 'mlx_random_multivariate_normal', key)
        call mlxf_random_binary_op(r, mlxc_random_multivariate_normal, a, spec, 'mlx_random_multivariate_normal')
    end function mlx_random_multivariate_normal

    ! one-based int32 categories drawn with the unnormalised log-probabilities logits holds along dim (1 by
    ! default): one per distribution, the result having logits' other dimensions; with num_samples that many per
    ! distribution, along a new first dimension; with shape a sample of that Fortran shape, which the other
    ! dimensions of logits broadcast to
    function mlx_random_categorical( logits, dim, num_samples, shape, key ) result(r)
        type(mlx_array), intent(in)           :: logits
        integer,         optional, intent(in) :: dim, num_samples, shape(:)
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array)        :: r, raw, a(2)
        type(mlxf_random_spec) :: spec
        call mlxf_require_device('mlx_random_categorical')
        if( present(num_samples) .and. present(shape) ) &
            &call mlxf_fail('mlx_random_categorical', 'num_samples and shape are two forms: give one of them')
        if( present(dim) ) spec%dim = dim
        a(1) = logits
        call take_key(a(2), 'mlx_random_categorical', key)
        if( present(shape) )then
            spec%shape = shape
            call mlxf_random_axis_shape_op(raw, mlxc_random_categorical_shape, a, spec, 'mlx_random_categorical')
        else if( present(num_samples) )then
            spec%number = num_samples
            call mlxf_random_axis_int_op(raw, mlxc_random_categorical_num_samples, a, spec, 'mlx_random_categorical')
        else
            call mlxf_random_axis_op(raw, mlxc_random_categorical, a, spec%dim, 'mlx_random_categorical')
        endif
        call mlxf_one_based(r, raw, 'mlx_random_categorical')
    end function mlx_random_categorical

    ! x with its slices along dim in a random order (the last dimension by default, MLX's first axis)
    function random_permutation_array( x, dim, key ) result(r)
        type(mlx_array), intent(in)           :: x
        integer,         optional, intent(in) :: dim
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array) :: r, a(2)
        integer         :: d
        call mlxf_require_device('mlx_random_permutation')
        d = x%ndim()
        if( present(dim) ) d = dim
        a(1) = x
        call take_key(a(2), 'mlx_random_permutation', key)
        call mlxf_random_axis_op(r, mlxc_random_permutation, a, d, 'mlx_random_permutation')
    end function random_permutation_array

    ! a random permutation of 1 to n, int32
    function random_permutation_count( n, key ) result(r)
        integer,         intent(in)           :: n
        type(mlx_array), optional, intent(in) :: key
        type(mlx_array) :: r, raw, k(1)
        call mlxf_require_device('mlx_random_permutation')
        call take_key(k(1), 'mlx_random_permutation', key)
        call mlxf_random_int_op(raw, mlxc_random_permutation_arange, k, n, 'mlx_random_permutation')
        call mlxf_one_based(r, raw, 'mlx_random_permutation')
    end function random_permutation_count

    ! a sample's shape and dtype (float32 by default) as the helpers take them
    function sample_spec( shape, dtype ) result(spec)
        integer, intent(in)           :: shape(:)
        integer, optional, intent(in) :: dtype
        type(mlxf_random_spec) :: spec
        spec%shape = shape
        if( present(dtype) ) spec%dtype = dtype
    end function sample_spec

    ! the key a sampler hands on: a counted copy of key, or k left empty, which the helpers read as MLX's global
    ! key; a key that is given must be live
    subroutine take_key( k, proc, key )
        type(mlx_array),  intent(inout)        :: k
        character(len=*), intent(in)           :: proc
        type(mlx_array),  optional, intent(in) :: key
        if( .not. present(key) ) return
        if( .not. mlx_is_live(key) ) call mlxf_fail(proc, 'the key is an empty or stale array')
        k = key
    end subroutine take_key

end module mlxf_random
