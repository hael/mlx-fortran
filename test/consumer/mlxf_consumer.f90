!@descr: outside install consumer: public array transfers, matrix product and exact handle teardown
program mlxf_consumer
use, intrinsic :: iso_fortran_env, only: real32
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
use mlxf, only: mlx_array, mlx_from, mlx_to_alloc, matmul, exp, mlx_live_count, mlx_device_count, MLX_DEVICES, &
                mlx_set_default_device, mlxf_runtime_description
implicit none
type(mlx_array)           :: a, b, c
real(real32)              :: x(2, 3), y(3, 2), expected(2, 2)
real(real32), allocatable :: z(:,:)
integer                   :: before, st, dev
if( mlx_device_count(MLX_DEVICES%gpu) < 1 ) error stop 'consumer needs a Metal device'
x = reshape([1._real32, 2._real32, 3._real32, 4._real32, 5._real32, 6._real32], shape(x))
y = reshape([.125_real32, .25_real32, .5_real32, .25_real32, .125_real32, .5_real32], shape(y))
expected = exp(-matmul(x, y))
do dev = 1, 2
    if( dev == 1 ) call mlx_set_default_device(MLX_DEVICES%cpu)
    if( dev == 2 ) call mlx_set_default_device(MLX_DEVICES%gpu)
    before = mlx_live_count()
    a = mlx_from(x)
    b = mlx_from(y)
    c = exp(-matmul(a, b))
    call mlx_to_alloc(z, c, status=st)
    if( st /= 0 ) error stop 'consumer transfer failed'
    if( any(shape(z) /= shape(expected)) ) error stop 'consumer shape mismatch'
    if( .not. all(ieee_is_finite(z)) ) error stop 'consumer non-finite result'
    ! all() of the comparisons: a NaN fails it, where maxval may skip one
    if( .not. all(abs(z - expected) <= 1.e-6_real32) ) error stop 'consumer result mismatch'
    call a%kill()
    call b%kill()
    call c%kill()
    if( mlx_live_count() /= before ) error stop 'consumer leaked a handle'
    write(*,'(a)') 'consumer passed: '//mlxf_runtime_description()
end do
end program mlxf_consumer
