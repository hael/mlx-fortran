!@descr: the dtype-and-result table of doc/quickstart.md: one block per row, each asserting its row and printing D<n>: ok
! mlxf_example_differences [require-gpu]: on the GPU when one opens (the float64 rows on the CPU device), on the CPU
! of a CPU-only MLX; on Metal or CUDA without a GPU it prints SKIP and exits 0, unless require-gpu is given. A failed row
! exits 1. The rows D3 and D15 are stops, the guards guard_matmul_integer and guard_float64_on_gpu.
program mlxf_example_differences
use, intrinsic :: iso_fortran_env, only: int32, real32, real64
use, intrinsic :: iso_c_binding,   only: c_bool
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_positive_inf
use mlxf, only: mlx_array, mlx_from, mlx_to_alloc, mlx_astype, mlx_floor_divide, mlx_mean, mlx_round, mlx_take, &
                mlx_set_default_device, mlx_default_device, mlx_device_count, mlx_metal_is_available, &
                mlx_cuda_is_available, MLX_DEVICES, MLX_DTYPES, matmul, transpose, real, cmplx, sum, count, all, &
                maxloc, modulo, exp, mlx_random_key, mlx_random_uniform, mlx_random_seed
implicit none
type(mlx_array)              :: a, b, c, f, z, key
integer(int32),  allocatable :: i1(:)
real(real32),    allocatable :: r1(:), r2(:,:), r3(:,:,:), u1(:), u2(:), u3(:)
real(real64),    allocatable :: d1(:)
complex(real32), allocatable :: z1(:)
logical(c_bool), allocatable :: l1(:)
real(real32)                 :: x3(2, 2, 2), y3(2, 2, 2), want3(2, 2, 2)
character(len=32)            :: arg
integer                      :: k, device, nfailed
logical                      :: gpu_backend
nfailed = 0
call get_command_argument(1, arg)
gpu_backend = mlx_metal_is_available()
if( mlx_cuda_is_available() ) gpu_backend = .true.
if( mlx_device_count(MLX_DEVICES%gpu) > 0 )then
    device = MLX_DEVICES%gpu
else if( trim(arg) == 'require-gpu' )then
    error stop 'mlxf_example_differences: require-gpu, and no GPU device in this session'
else if( .not. gpu_backend )then
    device = MLX_DEVICES%cpu
else
    write(*,'(a)') 'SKIP: mlxf_example_differences: no GPU device in this session; Metal or CUDA MLX cannot allocate'
    stop
endif
call mlx_set_default_device(device)
a = mlx_from([7_int32, -7_int32])
b = mlx_from([2_int32, 2_int32])

! D1: / of two integer arrays is true division to float32 (Fortran's 7/2 is 3)
c = a / b
call mlx_to_alloc(r1, c)
call row(1, c%kind() == MLX_DTYPES%float32 .and. all(abs(r1 - [3.5, -3.5]) <= 0.))

! D2: mlx_floor_divide keeps the integer kind and floors (Fortran's -7/2 truncates to -3)
c = mlx_floor_divide(a, b)
call mlx_to_alloc(i1, c)
call row(2, c%kind() == MLX_DTYPES%int32 .and. all(i1 == [3, -4]))

! D4: matmul of an integer and a real matrix promotes, as Fortran's does
z = mlx_from(reshape([1_int32, 2_int32, 3_int32, 4_int32], [2, 2]))
f = mlx_from(reshape([.5, .25, 1., 2.], [2, 2]))
c = matmul(z, f)
call mlx_to_alloc(r2, c)
call row(4, c%kind() == MLX_DTYPES%float32 .and. &
    &all(abs(r2 - matmul(reshape([1., 2., 3., 4.], [2, 2]), reshape([.5, .25, 1., 2.], [2, 2]))) <= 1.e-6))

! D5: a real64 scalar with a float32 array stays float32 (Fortran's mixed expression is real64)
c = mlx_from([1., 2.]) + 0.1_real64
call mlx_to_alloc(r1, c)
call row(5, c%kind() == MLX_DTYPES%float32 .and. all(abs(r1 - [1.1, 2.1]) <= 1.e-6))

! D6: a half-precision array keeps its kind with a real scalar
f = mlx_astype(mlx_from([1., 2.]), MLX_DTYPES%float16)
c = f + 1.0
call row(6, c%kind() == MLX_DTYPES%float16)

! D7: an integer array with a real scalar gives float32, also for a real64 scalar
c = a + 0.5_real64
call mlx_to_alloc(r1, c)
call row(7, c%kind() == MLX_DTYPES%float32 .and. all(abs(r1 - [7.5, -6.5]) <= 0.))

! D8: a real scalar with a complex64 array gives complex64
c = mlx_from([(1., 2.)]) + 1.0
call mlx_to_alloc(z1, c)
call row(8, c%kind() == MLX_DTYPES%complex64 .and. all(abs(z1 - [(2., 2.)]) <= 0.))

! D9: real() gives float32 from every numeric kind, real64 (on the CPU device) and complex64 included
call mlx_set_default_device(MLX_DEVICES%cpu)
c = real(mlx_from([1.25_real64, -2.5_real64]))
call mlx_to_alloc(r1, c)
k = c%kind()
call mlx_set_default_device(device)
z = real(mlx_from([(3., 4.)]))
call row(9, k == MLX_DTYPES%float32 .and. all(abs(r1 - [1.25, -2.5]) <= 0.) .and. z%kind() == MLX_DTYPES%float32)

! D10: cmplx(x, y) is x + i*y in complex64: exact for finite parts; an infinite y makes the real part NaN
c = cmplx(mlx_from([1., 2.]), mlx_from([3., 4.]))
call mlx_to_alloc(z1, c)
k = merge(1, 0, c%kind() == MLX_DTYPES%complex64 .and. all(abs(z1 - [(1., 3.), (2., 4.)]) <= 0.))
c = cmplx(mlx_from([1.]), mlx_from([ieee_value(1., ieee_positive_inf)]))
call mlx_to_alloc(z1, c)
call row(10, k == 1 .and. ieee_is_nan(real(z1(1))))

! D11: sum and count of integers are int32; mlx_mean of integers is float32
c = sum(a)
z = count(a > b)
f = mlx_mean(a)
call row(11, c%kind() == MLX_DTYPES%int32 .and. z%kind() == MLX_DTYPES%int32 .and. f%kind() == MLX_DTYPES%float32)

! D12: all() gives a rank-0 boolean array; maxloc(a) the one-based int32 subscripts of the first maximum
c = all(a > b)
z = maxloc(mlx_from(reshape([1., 5., 3., 5.], [2, 2])))
call mlx_to_alloc(i1, z)
call row(12, c%ndim() == 0 .and. c%kind() == MLX_DTYPES%bool .and. z%kind() == MLX_DTYPES%int32 .and. &
    &all(i1 == [2, 1]))

! D13: mlx_round rounds halves to even, nint and anint away from zero
c = mlx_round(mlx_from([0.5, 1.5, 2.5, -0.5]))
call mlx_to_alloc(r1, c)
call row(13, all(abs(r1 - [0., 2., 2., 0.]) <= 0.) .and. all(nint([0.5, 1.5, 2.5, -0.5]) == [1, 2, 3, -1]))

! D14: modulo takes the divisor's sign, as Fortran's
c = modulo(mlx_from([-7_int32, 7_int32]), mlx_from([2_int32, -2_int32]))
call mlx_to_alloc(i1, c)
call row(14, all(i1 == modulo([-7, 7], [2, -2])))

! D16: float64 exists on the CPU device only, and MLX computes exp of float64 in float32 there
call mlx_set_default_device(MLX_DEVICES%cpu)
c = exp(mlx_from([0.5_real64, 1.5_real64]))
call mlx_to_alloc(d1, c)
call mlx_set_default_device(device)
call row(16, c%kind() == MLX_DTYPES%float64 .and. &
    &all(abs(d1 - exp([0.5_real64, 1.5_real64])) <= 1.e-6_real64 * exp(1.5_real64)))

! D17: mlx_take's one-based indices are not checked: 0 wraps to the last element (Fortran's a(0) is out of bounds)
c = mlx_take(mlx_from([10., 20., 30.]), mlx_from([1_int32, 3_int32, 0_int32]))
call mlx_to_alloc(r1, c)
call row(17, all(abs(r1 - [10., 30., 30.]) <= 0.))

! D18: a comparison gives a boolean array, which copies out as logical(c_bool)
c = mlx_from([1., 2., 3.]) > 1.5
call mlx_to_alloc(l1, c)
call row(18, c%kind() == MLX_DTYPES%bool .and. all(l1 .eqv. [.false., .true., .true.]))

! D19: matmul and transpose batch over dimensions 3 and up (Fortran's take rank 2 only)
x3 = reshape([(real(k), k = 1, 8)], shape(x3))
y3 = reshape([(real(9 - k), k = 1, 8)], shape(y3))
do k = 1, 2
    want3(:,:, k) = matmul(transpose(x3(:,:, k)), y3(:,:, k))
end do
c = matmul(transpose(mlx_from(x3)), mlx_from(y3))
call mlx_to_alloc(r3, c)
call row(19, all(shape(r3) == [2, 2, 2]) .and. all(abs(r3 - want3) <= 0.))

! D20: a random sample is a function of its key and its shape; without a key the global key is used and advanced
key = mlx_random_key(42)
c = mlx_random_uniform([8], key=key)
call mlx_to_alloc(u1, c)
c = mlx_random_uniform([8], key=key)
call mlx_to_alloc(u2, c)
call mlx_random_seed(42)
c = mlx_random_uniform([8])
call mlx_to_alloc(r1, c)
c = mlx_random_uniform([8])
call mlx_to_alloc(u3, c)
call row(20, c%kind() == MLX_DTYPES%float32 .and. all(abs(u1 - u2) <= 0.) .and. any(abs(r1 - u3) > 0.) &
    &.and. all(u1 >= 0.) .and. all(u1 < 1.))

! D21: a default-integer scalar takes an integer array's kind exactly (a + 1 is int32) and a real array's kind
! (2 * x stays float32); an integer scalar the array's kind cannot hold stops instead of wrapping
a = mlx_from([1, 2, 3])
c = a + 1
call mlx_to_alloc(i1, c)
f = 2 * mlx_from([0.5, 1.5])
call mlx_to_alloc(r1, f)
call row(21, c%kind() == MLX_DTYPES%int32 .and. all(i1 == [2, 3, 4]) .and. f%kind() == MLX_DTYPES%float32 &
    &.and. all(abs(r1 - [1., 3.]) <= 0.))

if( nfailed > 0 ) error stop 1
write(*,'(a)') 'mlxf_example_differences: every row holds, on the '// &
    &merge('gpu', 'cpu', mlx_default_device() == MLX_DEVICES%gpu)

contains

    subroutine row( n, ok )
        integer, intent(in) :: n
        logical, intent(in) :: ok
        if( ok )then
            write(*,'(a,i0,a)') 'D', n, ': ok'
        else
            write(*,'(a,i0,a)') 'D', n, ': FAILED'
            nfailed = nfailed + 1
        endif
    end subroutine row

end program mlxf_example_differences
