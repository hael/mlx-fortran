!@descr: the unary and binary signature classes and weak scalars, the helpers the operators share
submodule(mlxf_calls) mlxf_calls_elementwise
use, intrinsic :: iso_c_binding,   only: c_double, c_float
use, intrinsic :: iso_fortran_env, only: int32, int64
use mlxf_c_array,  only: mlxc_array_dtype, mlxc_array_free, mlxc_array_new, mlxc_array_new_complex, &
                         mlxc_array_new_float32, mlxc_array_new_float64
use mlxf_c_ops,    only: mlxc_astype
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_c_types,  only: MLXC_BFLOAT16, MLXC_COMPLEX64, MLXC_FLOAT16, MLXC_FLOAT64, MLXC_BOOL, MLXC_INT8, MLXC_INT16, &
                         MLXC_INT32, MLXC_INT64, MLXC_UINT8, MLXC_UINT16, MLXC_UINT32, MLXC_UINT64
use mlxf_error,    only: mlxf_check, mlxf_fail
use mlxf_device,   only: mlxf_default_stream, mlxf_require_device
use mlxf_array,    only: mlxf_handle, mlxf_adopt
use mlxf_transfer, only: mlx_from
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

    ! a default-integer scalar for an operator with a: for an integer array a 0-d array of a's kind holding i exactly
    ! (never through a real kind), a value outside the kind's range a stop rather than a wrapped value; int32 for a
    ! boolean array (MLX then promotes the booleans to int32); for a real or complex array a weak scalar, as a real
    ! one is (mlxf_weak_scalar)
    module subroutine mlxf_integer_scalar( r, a, i, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: i
        character(len=*), intent(in)    :: proc
        type(mlx_array)   :: t
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: dtype, ierr
        integer(int64)    :: lo, hi
        character(len=24) :: text
        call mlxf_require_device(proc)
        dtype = mlxc_array_dtype(mlxf_handle(a, proc))
        lo = -huge(1_int64)-1_int64
        hi = huge(1_int64)
        select case( dtype )
            case( MLXC_INT8 )
                lo = -128_int64
                hi = 127_int64
            case( MLXC_INT16 )
                lo = -32768_int64
                hi = 32767_int64
            case( MLXC_UINT8 )
                lo = 0_int64
                hi = 255_int64
            case( MLXC_UINT16 )
                lo = 0_int64
                hi = 65535_int64
            case( MLXC_UINT32, MLXC_UINT64 )
                lo = 0_int64
            case( MLXC_INT32, MLXC_INT64 )
            case( MLXC_BOOL )
                r = mlx_from(int(i, int32))
                return
            case default
                call mlxf_weak_scalar(r, a, real(i, real64), proc)
                return
        end select
        if( int(i, int64) < lo .or. int(i, int64) > hi )then
            write(text, '(i0)') i
            call mlxf_fail(proc, 'the integer scalar '//trim(text)//' does not fit the integer array''s kind (it '//&
                &'would wrap): convert the array, or use a scalar in range')
        endif
        t = mlx_from(int(i, int32))
        if( dtype == MLXC_INT32 )then
            r = t
            return
        endif
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = mlxc_astype(res, mlxf_handle(t, proc), dtype, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_integer_scalar

end submodule mlxf_calls_elementwise
