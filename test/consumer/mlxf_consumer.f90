!@descr: outside install consumer: public array transfers, matrix product and exact handle teardown
! mlxf_consumer [require-gpu]: runs on every device MLX can allocate on: both with a GPU, the CPU alone on a
! CPU-only MLX; on Metal or CUDA without a GPU (headless, sandboxed, virtual, none visible to CUDA) none, and it
! prints SKIP and exits 0.
! require-gpu makes a missing GPU a failure.
program mlxf_consumer
use, intrinsic :: iso_fortran_env, only: real32
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
use mlxf, only: mlx_array, mlx_from, mlx_to_alloc, matmul, exp, mlx_live_count, mlx_device_count, MLX_DEVICES, &
                mlx_set_default_device, mlx_metal_is_available, mlx_cuda_is_available, mlxf_runtime_description
implicit none
type(mlx_array)           :: a, b, c
real(real32)              :: x(2, 3), y(3, 2), expected(2, 2)
real(real32), allocatable :: z(:,:)
character(len=32)         :: arg
logical                   :: require_gpu, gpu_backend
integer, allocatable      :: devs(:)
integer                   :: before, st, i
require_gpu = .false.
if( command_argument_count() > 0 )then
    call get_command_argument(1, arg)
    if( command_argument_count() > 1 .or. trim(arg) /= 'require-gpu' ) error stop 'usage: mlxf_consumer [require-gpu]'
    require_gpu = .true.
endif
gpu_backend = mlx_metal_is_available()
if( mlx_cuda_is_available() ) gpu_backend = .true.
if( mlx_device_count(MLX_DEVICES%gpu) > 0 )then
    devs = [MLX_DEVICES%cpu, MLX_DEVICES%gpu]
else if( require_gpu )then
    error stop 'consumer: require-gpu, and no GPU device in this session'
else if( .not. gpu_backend )then
    devs = [MLX_DEVICES%cpu]
else
    write(*,'(a)') 'SKIP: consumer: no GPU device in this session; a Metal or CUDA build of MLX cannot allocate'
    stop
endif
x = reshape([1._real32, 2._real32, 3._real32, 4._real32, 5._real32, 6._real32], shape(x))
y = reshape([.125_real32, .25_real32, .5_real32, .25_real32, .125_real32, .5_real32], shape(y))
expected = exp(-matmul(x, y))
do i = 1, size(devs)
    call mlx_set_default_device(devs(i))
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
