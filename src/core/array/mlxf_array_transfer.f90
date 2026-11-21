!@descr: copies between Fortran arrays and mlx_arrays: mlx_from, mlx_to, mlx_to_alloc
submodule (mlxf_array) mlxf_array_transfer
use, intrinsic :: iso_c_binding, only: c_null_ptr, c_loc
use mlxf_c_types,  only: MLXC_BOOL, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, MLXC_COMPLEX64
use mlxf_c_array,  only: mlxc_array_free, mlxc_array_new_data, mlxc_array_size, mlxc_array_dtype, mlxc_array_eval, &
                         mlxc_array_new, mlxc_array_data_bool, mlxc_array_data_int32, mlxc_array_data_int64, &
                         mlxc_array_data_float32, mlxc_array_data_float64, mlxc_array_data_complex64, &
                         mlxc_internal_array_is_row_contiguous
use mlxf_c_ops,    only: mlxc_contiguous
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_libc,     only: c_memcpy
use mlxf_error,    only: mlxf_check, mlxf_fail, mlxf_report
use mlxf_device,   only: mlxf_enter, mlxf_require_device, mlxf_default_stream
implicit none

contains

    ! a new MLX array holding a copy of n bytes at p (null when the array has no element), Fortran shape fshape
    subroutine new_from_data( a, p, fshape, dtype, proc )
        type(mlx_array),  intent(inout) :: a
        type(c_ptr),      intent(in)    :: p
        integer(int64),   intent(in)    :: fshape(:)
        integer(c_int),   intent(in)    :: dtype
        character(len=*), intent(in)    :: proc
        integer(c_int) :: cshape(MAX_RANK)
        integer        :: n
        call mlxf_require_device(proc)
        n = size(fshape)
        if( n > MAX_RANK ) call mlxf_fail(proc, 'rank above 15')
        if( any(fshape > int(huge(1_c_int), int64)) ) call mlxf_fail(proc, 'a dimension above 2**31 - 1')
        cshape(1:n) = int(fshape(n:1:-1), c_int)
        call adopt(a, mlxc_array_new_data(p, cshape, int(n, c_int), dtype), proc)
    end subroutine new_from_data

    module function from_r32( x ) result(a)
        real(real32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
        call mlxf_enter('mlx_from')
        if( size(x, kind=int64) == 0_int64 )then
            call new_from_data(a, c_null_ptr, shape(x, kind=int64), MLXC_FLOAT32, 'mlx_from')
        else
            call new_from_data(a, c_loc(x), shape(x, kind=int64), MLXC_FLOAT32, 'mlx_from')
        endif
    end function from_r32

    module function from_r64( x ) result(a)
        real(real64), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
        call mlxf_enter('mlx_from')
        if( size(x, kind=int64) == 0_int64 )then
            call new_from_data(a, c_null_ptr, shape(x, kind=int64), MLXC_FLOAT64, 'mlx_from')
        else
            call new_from_data(a, c_loc(x), shape(x, kind=int64), MLXC_FLOAT64, 'mlx_from')
        endif
    end function from_r64

    module function from_c32( x ) result(a)
        complex(real32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
        call mlxf_enter('mlx_from')
        if( size(x, kind=int64) == 0_int64 )then
            call new_from_data(a, c_null_ptr, shape(x, kind=int64), MLXC_COMPLEX64, 'mlx_from')
        else
            call new_from_data(a, c_loc(x), shape(x, kind=int64), MLXC_COMPLEX64, 'mlx_from')
        endif
    end function from_c32

    module function from_i32( x ) result(a)
        integer(int32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
        call mlxf_enter('mlx_from')
        if( size(x, kind=int64) == 0_int64 )then
            call new_from_data(a, c_null_ptr, shape(x, kind=int64), MLXC_INT32, 'mlx_from')
        else
            call new_from_data(a, c_loc(x), shape(x, kind=int64), MLXC_INT32, 'mlx_from')
        endif
    end function from_i32

    module function from_i64( x ) result(a)
        integer(int64), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
        call mlxf_enter('mlx_from')
        if( size(x, kind=int64) == 0_int64 )then
            call new_from_data(a, c_null_ptr, shape(x, kind=int64), MLXC_INT64, 'mlx_from')
        else
            call new_from_data(a, c_loc(x), shape(x, kind=int64), MLXC_INT64, 'mlx_from')
        endif
    end function from_i64

    module function from_l( x ) result(a)
        logical(c_bool), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
        call mlxf_enter('mlx_from')
        if( size(x, kind=int64) == 0_int64 )then
            call new_from_data(a, c_null_ptr, shape(x, kind=int64), MLXC_BOOL, 'mlx_from')
        else
            call new_from_data(a, c_loc(x), shape(x, kind=int64), MLXC_BOOL, 'mlx_from')
        endif
    end function from_l

    ! evaluates a and copies its n elements of type dtype, in Fortran order, to p
    subroutine copy_out( a, p, n, dtype, status )
        type(mlx_array),   intent(in)  :: a
        type(c_ptr),       intent(in)  :: p
        integer(int64),    intent(in)  :: n
        integer(c_int),    intent(in)  :: dtype
        integer, optional, intent(out) :: status
        character(len=*), parameter :: PROC = 'mlx_to'
        type(mlxc_array)            :: h, hc
        type(mlxc_stream)           :: s
        type(c_ptr)                 :: q
        logical(c_bool)             :: row
        integer(c_int)              :: ierr
        h = mlxf_handle(a, PROC)
        if( mlxc_array_dtype(h) /= dtype )then
            call mlxf_report(PROC, 'the Fortran array and the mlx_array differ in kind', status)
            return
        endif
        if( int(mlxc_array_size(h), int64) /= n )then
            call mlxf_report(PROC, 'the Fortran array and the mlx_array differ in size', status)
            return
        endif
        ierr = mlxc_array_eval(h)
        if( ierr == 0 .and. n > 0_int64 )then
            row  = .false.
            ierr = mlxc_internal_array_is_row_contiguous(row, h)
        endif
        call mlxf_check(ierr, PROC, status)
        if( ierr /= 0 .or. n == 0_int64 ) return
        hc = h
        if( .not. row )then
            ! a strided view (a transpose): copy it into row-major order first
            hc   = mlxc_array_new()
            s    = mlxf_default_stream(PROC)
            ierr = mlxc_contiguous(hc, h, .false._c_bool, s)
            call mlxf_check(mlxc_stream_free(s), PROC)
            if( ierr == 0 ) ierr = mlxc_array_eval(hc)
            if( ierr /= 0 ) call mlxf_check(mlxc_array_free(hc), PROC)
            call mlxf_check(ierr, PROC, status)
            if( ierr /= 0 ) return
        endif
        q = c_memcpy(p, data_pointer(hc, dtype), int(n, c_size_t) * itemsize(dtype))
        if( .not. row ) call mlxf_check(mlxc_array_free(hc), PROC)
    end subroutine copy_out

    module function data_pointer( h, dtype ) result(p)
        type(mlxc_array), intent(in) :: h
        integer(c_int),   intent(in) :: dtype
        type(c_ptr) :: p
        select case( dtype )
            case( MLXC_FLOAT32 )
                p = mlxc_array_data_float32(h)
            case( MLXC_FLOAT64 )
                p = mlxc_array_data_float64(h)
            case( MLXC_COMPLEX64 )
                p = mlxc_array_data_complex64(h)
            case( MLXC_INT32 )
                p = mlxc_array_data_int32(h)
            case( MLXC_INT64 )
                p = mlxc_array_data_int64(h)
            case default
                p = mlxc_array_data_bool(h)
        end select
    end function data_pointer

    module pure integer(c_size_t) function itemsize( dtype )
        integer(c_int), intent(in) :: dtype
        select case( dtype )
            case( MLXC_FLOAT64, MLXC_COMPLEX64, MLXC_INT64 )
                itemsize = 8_c_size_t
            case( MLXC_FLOAT32, MLXC_INT32 )
                itemsize = 4_c_size_t
            case default
                itemsize = 1_c_size_t
        end select
    end function itemsize

    ! evaluates a and copies it into y, a Fortran array of the same size and kind
    module subroutine to_r32( y, a, status )
        real(real32), target, contiguous, intent(inout) :: y(..)
        type(mlx_array),                  intent(in)    :: a
        integer, optional,                intent(out)   :: status
        call mlxf_enter('mlx_to')
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_FLOAT32, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_FLOAT32, status)
        endif
    end subroutine to_r32

    module subroutine to_r64( y, a, status )
        real(real64), target, contiguous, intent(inout) :: y(..)
        type(mlx_array),                  intent(in)    :: a
        integer, optional,                intent(out)   :: status
        call mlxf_enter('mlx_to')
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_FLOAT64, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_FLOAT64, status)
        endif
    end subroutine to_r64

    module subroutine to_c32( y, a, status )
        complex(real32), target, contiguous, intent(inout) :: y(..)
        type(mlx_array),                     intent(in)    :: a
        integer, optional,                   intent(out)   :: status
        call mlxf_enter('mlx_to')
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_COMPLEX64, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_COMPLEX64, status)
        endif
    end subroutine to_c32

    module subroutine to_i32( y, a, status )
        integer(int32), target, contiguous, intent(inout) :: y(..)
        type(mlx_array),                    intent(in)    :: a
        integer, optional,                  intent(out)   :: status
        call mlxf_enter('mlx_to')
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_INT32, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_INT32, status)
        endif
    end subroutine to_i32

    module subroutine to_i64( y, a, status )
        integer(int64), target, contiguous, intent(inout) :: y(..)
        type(mlx_array),                    intent(in)    :: a
        integer, optional,                  intent(out)   :: status
        call mlxf_enter('mlx_to')
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_INT64, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_INT64, status)
        endif
    end subroutine to_i64

    module subroutine to_l( y, a, status )
        logical(c_bool), target, contiguous, intent(inout) :: y(..)
        type(mlx_array),                     intent(in)    :: a
        integer, optional,                   intent(out)   :: status
        call mlxf_enter('mlx_to')
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_BOOL, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_BOOL, status)
        endif
    end subroutine to_l

    ! the Fortran shape an allocatable of rank yrank receives from a; false (status set) when the ranks differ
    logical function alloc_shape( a, yrank, s, status )
        type(mlx_array),      intent(in)  :: a
        integer,              intent(in)  :: yrank
        integer, allocatable, intent(out) :: s(:)
        integer, optional,    intent(out) :: status
        s = a%shape()
        alloc_shape = size(s) == yrank
        if( .not. alloc_shape ) call mlxf_report('mlx_to_alloc', 'the allocatable and the mlx_array differ in rank', &
            &status)
    end function alloc_shape

    ! allocates y (rank 1 to 7) to a's shape and copies a into it
    module subroutine to_alloc_r32( y, a, status )
        real(real32), allocatable, target, intent(inout) :: y(..)
        type(mlx_array),                   intent(in)    :: a
        integer, optional,                 intent(out)   :: status
        integer, allocatable :: s(:)
        integer              :: ast
        call mlxf_enter('mlx_to_alloc')
        if( .not. alloc_shape(a, rank(y), s, status) ) return
        ast = 0
        select rank( y )
            rank(1)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1)), stat=ast)
            rank(2)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2)), stat=ast)
            rank(3)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3)), stat=ast)
            rank(4)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4)), stat=ast)
            rank(5)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5)), stat=ast)
            rank(6)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6)), stat=ast)
            rank(7)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6), s(7)), stat=ast)
            rank default
                call mlxf_report('mlx_to_alloc', 'the allocatable has a rank outside 1 to 7', status)
                return
        end select
        if( ast /= 0 )then
            call mlxf_report('mlx_to_alloc', 'the destination could not be allocated', status)
            return
        endif
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_FLOAT32, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_FLOAT32, status)
        endif
    end subroutine to_alloc_r32

    module subroutine to_alloc_r64( y, a, status )
        real(real64), allocatable, target, intent(inout) :: y(..)
        type(mlx_array),                   intent(in)    :: a
        integer, optional,                 intent(out)   :: status
        integer, allocatable :: s(:)
        integer              :: ast
        call mlxf_enter('mlx_to_alloc')
        if( .not. alloc_shape(a, rank(y), s, status) ) return
        ast = 0
        select rank( y )
            rank(1)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1)), stat=ast)
            rank(2)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2)), stat=ast)
            rank(3)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3)), stat=ast)
            rank(4)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4)), stat=ast)
            rank(5)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5)), stat=ast)
            rank(6)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6)), stat=ast)
            rank(7)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6), s(7)), stat=ast)
            rank default
                call mlxf_report('mlx_to_alloc', 'the allocatable has a rank outside 1 to 7', status)
                return
        end select
        if( ast /= 0 )then
            call mlxf_report('mlx_to_alloc', 'the destination could not be allocated', status)
            return
        endif
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_FLOAT64, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_FLOAT64, status)
        endif
    end subroutine to_alloc_r64

    module subroutine to_alloc_c32( y, a, status )
        complex(real32), allocatable, target, intent(inout) :: y(..)
        type(mlx_array),                      intent(in)    :: a
        integer, optional,                    intent(out)   :: status
        integer, allocatable :: s(:)
        integer              :: ast
        call mlxf_enter('mlx_to_alloc')
        if( .not. alloc_shape(a, rank(y), s, status) ) return
        ast = 0
        select rank( y )
            rank(1)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1)), stat=ast)
            rank(2)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2)), stat=ast)
            rank(3)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3)), stat=ast)
            rank(4)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4)), stat=ast)
            rank(5)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5)), stat=ast)
            rank(6)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6)), stat=ast)
            rank(7)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6), s(7)), stat=ast)
            rank default
                call mlxf_report('mlx_to_alloc', 'the allocatable has a rank outside 1 to 7', status)
                return
        end select
        if( ast /= 0 )then
            call mlxf_report('mlx_to_alloc', 'the destination could not be allocated', status)
            return
        endif
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_COMPLEX64, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_COMPLEX64, status)
        endif
    end subroutine to_alloc_c32

    module subroutine to_alloc_i32( y, a, status )
        integer(int32), allocatable, target, intent(inout) :: y(..)
        type(mlx_array),                     intent(in)    :: a
        integer, optional,                   intent(out)   :: status
        integer, allocatable :: s(:)
        integer              :: ast
        call mlxf_enter('mlx_to_alloc')
        if( .not. alloc_shape(a, rank(y), s, status) ) return
        ast = 0
        select rank( y )
            rank(1)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1)), stat=ast)
            rank(2)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2)), stat=ast)
            rank(3)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3)), stat=ast)
            rank(4)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4)), stat=ast)
            rank(5)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5)), stat=ast)
            rank(6)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6)), stat=ast)
            rank(7)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6), s(7)), stat=ast)
            rank default
                call mlxf_report('mlx_to_alloc', 'the allocatable has a rank outside 1 to 7', status)
                return
        end select
        if( ast /= 0 )then
            call mlxf_report('mlx_to_alloc', 'the destination could not be allocated', status)
            return
        endif
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_INT32, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_INT32, status)
        endif
    end subroutine to_alloc_i32

    module subroutine to_alloc_i64( y, a, status )
        integer(int64), allocatable, target, intent(inout) :: y(..)
        type(mlx_array),                     intent(in)    :: a
        integer, optional,                   intent(out)   :: status
        integer, allocatable :: s(:)
        integer              :: ast
        call mlxf_enter('mlx_to_alloc')
        if( .not. alloc_shape(a, rank(y), s, status) ) return
        ast = 0
        select rank( y )
            rank(1)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1)), stat=ast)
            rank(2)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2)), stat=ast)
            rank(3)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3)), stat=ast)
            rank(4)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4)), stat=ast)
            rank(5)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5)), stat=ast)
            rank(6)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6)), stat=ast)
            rank(7)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6), s(7)), stat=ast)
            rank default
                call mlxf_report('mlx_to_alloc', 'the allocatable has a rank outside 1 to 7', status)
                return
        end select
        if( ast /= 0 )then
            call mlxf_report('mlx_to_alloc', 'the destination could not be allocated', status)
            return
        endif
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_INT64, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_INT64, status)
        endif
    end subroutine to_alloc_i64

    module subroutine to_alloc_l( y, a, status )
        logical(c_bool), allocatable, target, intent(inout) :: y(..)
        type(mlx_array),                      intent(in)    :: a
        integer, optional,                    intent(out)   :: status
        integer, allocatable :: s(:)
        integer              :: ast
        call mlxf_enter('mlx_to_alloc')
        if( .not. alloc_shape(a, rank(y), s, status) ) return
        ast = 0
        select rank( y )
            rank(1)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1)), stat=ast)
            rank(2)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2)), stat=ast)
            rank(3)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3)), stat=ast)
            rank(4)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4)), stat=ast)
            rank(5)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5)), stat=ast)
            rank(6)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6)), stat=ast)
            rank(7)
                if( allocated(y) ) deallocate(y)
                allocate(y(s(1), s(2), s(3), s(4), s(5), s(6), s(7)), stat=ast)
            rank default
                call mlxf_report('mlx_to_alloc', 'the allocatable has a rank outside 1 to 7', status)
                return
        end select
        if( ast /= 0 )then
            call mlxf_report('mlx_to_alloc', 'the destination could not be allocated', status)
            return
        endif
        if( size(y, kind=int64) == 0_int64 )then
            call copy_out(a, c_null_ptr, 0_int64, MLXC_BOOL, status)
        else
            call copy_out(a, c_loc(y), size(y, kind=int64), MLXC_BOOL, status)
        endif
    end subroutine to_alloc_l

end submodule mlxf_array_transfer
