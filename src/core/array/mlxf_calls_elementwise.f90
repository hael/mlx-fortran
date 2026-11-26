!@descr: the unary and binary signature classes and weak scalars, the helpers the operators share
submodule(mlxf_calls) mlxf_calls_elementwise
use, intrinsic :: iso_c_binding, only: c_double, c_float
use mlxf_c_array,  only: mlxc_array_dtype, mlxc_array_free, mlxc_array_new, mlxc_array_new_complex, &
                         mlxc_array_new_float32, mlxc_array_new_float64
use mlxf_c_ops,    only: mlxc_astype
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_c_types,  only: MLXC_BFLOAT16, MLXC_COMPLEX64, MLXC_FLOAT16, MLXC_FLOAT64
use mlxf_error,    only: mlxf_check
use mlxf_device,   only: mlxf_default_stream, mlxf_require_device
use mlxf_array,    only: mlxf_handle, mlxf_adopt
implicit none

contains

    ! r = f(a) on the default device, for every int f(mlx_array* res, const mlx_array a, const mlx_stream s)
    module subroutine mlxf_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, ha
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha   = mlxf_handle(a, proc)
        res  = mlxc_array_new()
        s    = mlxf_default_stream(proc)
        ierr = f(res, ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_unary

    ! r = f(a, b) on the default device, for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! const mlx_stream s)
    module subroutine mlxf_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, ha, hb
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha   = mlxf_handle(a, proc)
        hb   = mlxf_handle(b, proc)
        res  = mlxc_array_new()
        s    = mlxf_default_stream(proc)
        ierr = f(res, ha, hb, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_binary

    ! a Fortran scalar as a 0-d array of a's kind: weak, so it never changes the result's kind (float32
    ! with integer and boolean arrays). A 0-d array is not weak in MLX: a float32 one would promote a half
    ! array to float32, so a half array's scalar is made in its own dtype (rounded through float32)
    module subroutine mlxf_weak_scalar( r, a, x, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        real(real64),     intent(in)    :: x
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h, res
        type(mlxc_stream) :: s
        integer(c_int)    :: dtype, ierr
        call mlxf_require_device(proc)
        dtype = mlxc_array_dtype(mlxf_handle(a, proc))
        select case( dtype )
            case( MLXC_FLOAT64 )
                call mlxf_adopt(r, mlxc_array_new_float64(real(x, c_double)), proc)
            case( MLXC_COMPLEX64 )
                call mlxf_adopt(r, mlxc_array_new_complex(real(x, c_float), 0._c_float), proc)
            case( MLXC_FLOAT16, MLXC_BFLOAT16 )
                h = mlxc_array_new_float32(real(x, c_float))
                res = mlxc_array_new()
                s = mlxf_default_stream(proc)
                ierr = mlxc_astype(res, h, dtype, s)
                call mlxf_check(mlxc_stream_free(s), proc)
                call mlxf_check(mlxc_array_free(h), proc)
                if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
                call mlxf_check(ierr, proc)
                call mlxf_adopt(r, res, proc)
            case default
                call mlxf_adopt(r, mlxc_array_new_float32(real(x, c_float)), proc)
        end select
    end subroutine mlxf_weak_scalar

end submodule mlxf_calls_elementwise
