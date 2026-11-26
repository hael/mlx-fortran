!@descr: the README's first program: two arrays, exp(-matmul(a, b)) on MLX's default device, copied back with a status
program mlxf_example_first
use, intrinsic :: iso_fortran_env, only: real32
use mlxf, only: mlx_array, mlx_from, mlx_to_alloc, matmul, exp, mlx_last_error, mlxf_runtime_description
implicit none
type(mlx_array)           :: a, b, c
real(real32)              :: x(2, 3), y(3, 2)
real(real32), allocatable :: z(:,:)
integer                   :: status
x = reshape([1., 2., 3., 4., 5., 6.], shape(x)) / 10.
y = 0.5
a = mlx_from(x)                         ! a copy in MLX, still a (2, 3) array in Fortran's view
b = mlx_from(y)
c = exp(-matmul(a, b))                  ! a lazy graph: nothing is computed yet
call mlx_to_alloc(z, c, status=status)  ! evaluates on the default device, then copies into z
if( status /= 0 )then
    write(*,'(a)') 'mlxf_example_first: '//mlx_last_error()
    error stop 1
endif
write(*,'(a)') mlxf_runtime_description()
write(*,'(2f10.6)') transpose(z)
! MLX's GPU may multiply float32 matrices at reduced precision (TF32) unless MLX_ENABLE_TF32=0
if( .not. all(abs(z - exp(-matmul(x, y))) <= 1.e-3) ) error stop 'mlxf_example_first: wrong values'
end program mlxf_example_first
