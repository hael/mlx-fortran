!@descr: elementwise operations through the array signature helpers
module mlxf_ops_elementwise
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf_c_ops,    only: mlxc_add, mlxc_astype, mlxc_conjugate, mlxc_imag, mlxc_maximum, mlxc_real, mlxc_sqrt, &
                         mlxc_view, mlxc_where
use mlxf_defs,     only: MLX_DTYPES
use mlxf_device,   only: mlxf_enter
use mlxf_array,    only: mlx_array
use mlxf_calls,    only: mlxf_binary, mlxf_dtype_op, mlxf_ternary_op, mlxf_unary, mlxf_weak_scalar
use mlxf_transfer, only: mlx_from
implicit none

public :: real, aimag, conjg, sqrt, mlx_astype, mlx_bitcast, max, merge, cmplx, mlxf_widened, mlxf_narrowed
private

interface real
    module procedure real_array
end interface real

interface aimag
    module procedure aimag_array
end interface aimag

interface conjg
    module procedure conjg_array
end interface conjg

interface sqrt
    module procedure sqrt_array
end interface sqrt

interface max
    module procedure max_array, max_ass, max_sas, max_asd, max_sad
end interface max

interface merge
    module procedure merge_array
end interface merge

interface cmplx
    module procedure cmplx_array
end interface cmplx

contains

    ! Fortran's real(a): the real part of a complex array, otherwise a float32 copy, as Fortran's default real
    function real_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_enter('real')
        if( a%kind() == MLX_DTYPES%complex64 )then
            call mlxf_unary(r, mlxc_real, a, 'real')
        else
            call mlxf_dtype_op(r, mlxc_astype, a, MLX_DTYPES%float32, 'real')
        endif
    end function real_array

    ! the imaginary part of a complex array
    function aimag_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_imag, a, 'aimag')
    end function aimag_array

    ! the complex conjugate
    function conjg_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_conjugate, a, 'conjg')
    end function conjg_array

    ! the elementwise square root
    function sqrt_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_unary(r, mlxc_sqrt, a, 'sqrt')
    end function sqrt_array

    ! a converted to dtype, one of MLX_DTYPES
    function mlx_astype( a, dtype ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dtype
        type(mlx_array) :: r
        call mlxf_dtype_op(r, mlxc_astype, a, dtype, 'mlx_astype')
    end function mlx_astype

    ! a float16 or bfloat16 array as float32, the operand of a reduction whose answer the narrow kind holds but whose
    ! sum it does not accumulate (MLX sums in the operand's kind: the mean of 65,536 float16 ones came out 0.25 on the
    ! CPU and Inf on the GPU); any other array is a itself
    function mlxf_widened( a ) result(w)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: w
        if( any(a%kind() == [MLX_DTYPES%float16, MLX_DTYPES%bfloat16]) )then
            w = mlx_astype(a, MLX_DTYPES%float32)
        else
            w = a
        endif
    end function mlxf_widened

    ! r, computed on mlxf_widened's operand, in the operand's kind k: a float16 or bfloat16 statistic narrowed back,
    ! any other r itself
    function mlxf_narrowed( r, k ) result(n)
        type(mlx_array), intent(in) :: r
        integer,         intent(in) :: k
        type(mlx_array) :: n
        if( any(k == [MLX_DTYPES%float16, MLX_DTYPES%bfloat16]) )then
            n = mlx_astype(r, k)
        else
            n = r
        endif
    end function mlxf_narrowed

    ! a's bytes read as dtype, one of MLX_DTYPES (MLX's view; mlx_view is the Fortran pointer view): no value
    ! is converted. Where the item sizes differ, the first Fortran dimension scales by their ratio, so a float32
    ! (2 n, ...) array whose pairs along dimension 1 are (real, imaginary) reads as complex64 (n, ...)
    function mlx_bitcast( a, dtype ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dtype
        type(mlx_array) :: r
        call mlxf_dtype_op(r, mlxc_view, a, dtype, 'mlx_bitcast')
    end function mlx_bitcast

    ! Fortran's max(a, b) elementwise; a scalar operand is weak and takes the array's kind
    function max_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_maximum, a, b, 'max')
    end function max_array

    function max_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(b, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, a, s, 'max')
    end function max_ass

    function max_sas( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real32),    intent(in) :: a
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, real(a, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, b, s, 'max')
    end function max_sas

    function max_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, a, real(b, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, a, s, 'max')
    end function max_asd

    function max_sad( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real64),    intent(in) :: a
        type(mlx_array) :: r
        type(mlx_array) :: s
        call mlxf_weak_scalar(s, b, real(a, real64), 'max')
        call mlxf_binary(r, mlxc_maximum, b, s, 'max')
    end function max_sad

    ! Fortran's merge(tsource, fsource, mask) elementwise, mask a boolean array
    function merge_array( tsource, fsource, mask ) result(r)
        type(mlx_array), intent(in) :: tsource, fsource, mask
        type(mlx_array) :: r
        call mlxf_ternary_op(r, mlxc_where, [mask, tsource, fsource], 'merge')
    end function merge_array

    ! Fortran's cmplx(x, y) as x + i y in complex64; a non-finite y spoils the real part too
    function cmplx_array( x, y ) result(r)
        type(mlx_array), intent(in) :: x, y
        type(mlx_array) :: r
        type(mlx_array) :: imaginary, z
        call mlxf_enter('cmplx')
        imaginary = mlx_from(cmplx(0._real32, 1._real32, real32))
        z = imaginary*y
        call mlxf_binary(r, mlxc_add, x, z, 'cmplx')
    end function cmplx_array

end module mlxf_ops_elementwise
