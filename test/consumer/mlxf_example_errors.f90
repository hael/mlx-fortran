!@descr: failures and ownership a caller handles: a status with mlx_last_error(), the named owner of mlx_view, the session's devices
! mlxf_example_errors [require-gpu]: tells the three sessions apart (Metal with a GPU, Metal without one, a CPU-only
! MLX), runs where MLX can allocate, prints SKIP and exits 0 where it cannot (a failure under require-gpu).
program mlxf_example_errors
use, intrinsic :: iso_fortran_env, only: real32
use mlxf, only: mlx_array, mlx_from, mlx_to, mlx_view, mlx_last_error, mlx_metal_is_available, mlx_device_count, &
                mlx_set_default_device, MLX_DEVICES, exp
implicit none
type(mlx_array)       :: a, w
real(real32)          :: x(6), y(5)
real(real32), pointer :: p(:)
character(len=32)     :: arg
integer               :: status
call get_command_argument(1, arg)
! the session: a GPU opens; or Metal is built in but no GPU opens (MLX cannot allocate at all); or MLX is CPU-only
if( mlx_device_count(MLX_DEVICES%gpu) > 0 )then
    write(*,'(a)') 'session: Metal with a GPU; both devices allocate'
    call mlx_set_default_device(MLX_DEVICES%gpu)
else if( trim(arg) == 'require-gpu' )then
    error stop 'mlxf_example_errors: require-gpu, and no GPU device in this session'
else if( .not. mlx_metal_is_available() )then
    write(*,'(a)') 'session: a CPU-only MLX; the CPU device allocates'
    call mlx_set_default_device(MLX_DEVICES%cpu)
else
    write(*,'(a)') 'SKIP: mlxf_example_errors: Metal without a GPU (headless, sandboxed, virtual); MLX cannot allocate'
    stop
endif
x = [1., 2., 3., 4., 5., 6.]
a = mlx_from(x)
! a recoverable failure: a checked procedure returns a status and leaves the message in mlx_last_error()
call mlx_to(y, a, status=status)
if( status == 0 ) error stop 'mlxf_example_errors: copying 6 elements into 5 was accepted'
write(*,'(a)') 'refused with a status: '//mlx_last_error()
! the library and MLX stay usable after it
call mlx_to(x, a, status=status)
if( status /= 0 ) error stop 'mlxf_example_errors: the copy after the refusal failed'
! mlx_view points at MLX's storage; its owner is a named variable, so p is valid while w is unchanged
! (call mlx_view(exp(a), p) would dangle: the expression's result is finalized when the statement ends)
w = exp(a)
call mlx_view(w, p, status=status)
if( status /= 0 ) error stop 'mlxf_example_errors: the view was refused'
if( .not. all(abs(p - exp(x)) <= 1.e-6 * exp(x)) ) error stop 'mlxf_example_errors: wrong values through the view'
write(*,'(a,6f9.4)') 'through the view of w: ', p
call w%kill()
nullify(p)
write(*,'(a)') 'mlxf_example_errors: passed'
end program mlxf_example_errors
