!@descr: elementwise operations through the array signature helpers
submodule(mlxf_ops) mlxf_ops_elementwise
use mlxf_c_ops,  only: mlxc_add, mlxc_astype, mlxc_conjugate, mlxc_imag, mlxc_maximum, mlxc_real, mlxc_sqrt, mlxc_where
use mlxf_defs,   only: MLX_DTYPES
use mlxf_array,  only: mlx_from, mlxf_binary, mlxf_int_op, mlxf_ternary_op, mlxf_unary, mlxf_weak_scalar
use mlxf_device, only: mlxf_enter
implicit none

contains

    ! Fortran's real(a): the real part of a complex array, otherwise a float32 copy, as Fortran's default real
    module function real_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_enter('real')
        if( a%kind() == MLX_DTYPES%complex64 )then
            call mlxf_unary(r, mlxc_real, a, 'real')
        else
            call mlxf_int_op(r, mlxc_astype, a, MLX_DTYPES%float32, 'real')
        endif
    end function real_array

    ! the imaginary part of a complex array
    module function aimag_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_imag, a, 'aimag')
    end function aimag_array

    ! the complex conjugate
    module function conjg_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_conjugate, a, 'conjg')
    end function conjg_array

    ! the elementwise square root
    module function sqrt_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_sqrt, a, 'sqrt')
    end function sqrt_array

    ! a converted to dtype, one of MLX_DTYPES
    module function mlx_astype( a, dtype ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dtype
        type(mlx_array) :: r
        call mlxf_int_op(r, mlxc_astype, a, dtype, 'mlx_astype')
    end function mlx_astype

    ! Fortran's max(a, b) elementwise; a scalar operand is weak and takes the array's kind
    module function max_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_maximum, a, b, 'max')
    end function max_array

    module function max_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(b, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, a, s, 'max')
    end function max_ass

    module function max_sas( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real32),    intent(in) :: a
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, real(a, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, b, s, 'max')
    end function max_sas

    module function max_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(b, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, a, s, 'max')
    end function max_asd

    module function max_sad( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real64),    intent(in) :: a
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, real(a, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, b, s, 'max')
    end function max_sad

    ! Fortran's merge(tsource, fsource, mask) elementwise, mask a boolean array
    module function merge_array( tsource, fsource, mask ) result(r)
        type(mlx_array), intent(in) :: tsource, fsource, mask
        type(mlx_array) :: r
        call mlxf_ternary_op(r, mlxc_where, [mask, tsource, fsource], 'merge')
    end function merge_array

    ! Fortran's cmplx(x, y) as x + i y in complex64; a non-finite y spoils the real part too
    module function cmplx_array( x, y ) result(r)
        type(mlx_array), intent(in) :: x, y
        type(mlx_array) :: r
        type(mlx_array) :: imaginary, z
        call mlxf_enter('cmplx')
        imaginary = mlx_from(cmplx(0._real32, 1._real32, real32))
        z = imaginary*y
        call mlxf_binary(r, mlxc_add, x, z, 'cmplx')
    end function cmplx_array

end submodule mlxf_ops_elementwise
