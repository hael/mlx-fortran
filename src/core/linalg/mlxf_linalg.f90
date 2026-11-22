!@descr: matrix multiplication with Fortran matrix dimensions and leading-dimension broadcasting
module mlxf_linalg
use mlxf_c_ops, only: mlxc_matmul
use mlxf_array, only: mlx_array, mlxf_binary
implicit none
public :: matmul
private
interface matmul
    module procedure matmul_array
end interface matmul

contains

    ! Fortran's matmul(a, b), batched over dimensions 3 and up: in MLX's reversed view of the bytes this is
    ! matmul(b, a)
    function matmul_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_matmul, b, a, 'matmul')
    end function matmul_array
end module mlxf_linalg
