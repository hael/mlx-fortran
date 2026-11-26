!@descr: shared storage: mlx_view (read-only borrowing after evaluation) and mlx_alloc (writable initialisation of page-aligned memory)
submodule(mlxf_transfer) mlxf_transfer_borrow
use, intrinsic :: iso_c_binding, only: c_null_ptr, c_associated, c_f_pointer, c_funloc, c_sizeof
use mlxf_c_array, only: mlxc_array_new_data_managed_payload, mlxc_array_size, mlxc_array_dtype, mlxc_array_eval, &
                        mlxc_internal_array_is_row_contiguous
use mlxf_c_types, only: MLXC_BOOL, MLXC_INT8, MLXC_INT16, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, &
                        MLXC_COMPLEX64
use mlxf_libc,    only: c_posix_memalign, c_free
use mlxf_error,   only: mlxf_check, mlxf_report
use mlxf_device,  only: mlxf_enter, mlxf_require_device
use mlxf_array,   only: mlxf_adopt, mlxf_handle
implicit none

integer(c_size_t), parameter :: PAGE_BYTES = 16384_c_size_t

! who frees a buffer mlx_alloc hands to MLX. MLX's deleter frees it: at once when MLX copies it, or when the
! array dies. A deleter run inside the creating call (a copy, or a failure after MLX took the buffer) only
! marks it freed, so mlx_alloc knows whether a failed call left the buffer to it
type, bind(c) :: buffer_owner
    type(c_ptr)    :: buf     = c_null_ptr
    integer(c_int) :: in_call = 0
    integer(c_int) :: freed   = 0
end type buffer_owner

contains

    ! evaluates a and returns its storage when a is row-contiguous and of the view's kind and rank; null
    ! (status set) otherwise. The view is valid until the next statement that assigns to, kills or ends
    ! the scope of a, and is never written through.
    function view_target( a, vrank, dtype, s, status ) result(p)
        type(mlx_array),      intent(in)  :: a
        integer,              intent(in)  :: vrank
        integer(c_int),       intent(in)  :: dtype
        integer, allocatable, intent(out) :: s(:)
        integer, optional,    intent(out) :: status
        character(len=*), parameter :: PROC = 'mlx_view'
        type(c_ptr)                 :: p
        type(mlxc_array)            :: h
        logical(c_bool)             :: row
        integer(c_int)              :: ierr
        p = c_null_ptr
        h = mlxf_handle(a, PROC)
        s = a%shape()
        if( mlxc_array_dtype(h) /= dtype .or. size(s) /= vrank )then
            call mlxf_report(PROC, 'the pointer and the mlx_array differ in kind or rank', status)
            return
        endif
        if( mlxc_array_size(h) == 0_c_size_t )then
            call mlxf_report(PROC, 'the mlx_array has no element to view', status)
            return
        endif
        ierr = mlxc_array_eval(h)
        row  = .false.
        if( ierr == 0 ) ierr = mlxc_internal_array_is_row_contiguous(row, h)
        call mlxf_check(ierr, PROC, status)
        if( ierr /= 0 ) return
        if( .not. row )then
            call mlxf_report(PROC, 'the mlx_array is not contiguous in Fortran order (a strided view): copy it '//&
                &'with mlx_to', status)
            return
        endif
        p = data_pointer(h, dtype)
        if( .not. c_associated(p) ) call mlxf_report(PROC, 'MLX returned no storage for the mlx_array', status)
    end function view_target

    ! points p, of rank 0 to 7, at q with the Fortran shape s; p is null when q is (a refused view or
    ! allocation) and after the refusal of a rank above 7, so a failed call leaves no stale association. One copy
    ! per kind, each rank its own case: Fortran has no procedure generic over either, and an assumed-rank pointer
    ! can be nullified only in a case of its rank
    subroutine point_r32( q, s, p, proc, status )
        type(c_ptr),           intent(in)    :: q
        integer,               intent(in)    :: s(:)
        real(real32), pointer, intent(inout) :: p(..)
        character(len=*),      intent(in)    :: proc
        integer, optional,     intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_r32

    subroutine point_r64( q, s, p, proc, status )
        type(c_ptr),           intent(in)    :: q
        integer,               intent(in)    :: s(:)
        real(real64), pointer, intent(inout) :: p(..)
        character(len=*),      intent(in)    :: proc
        integer, optional,     intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_r64

    subroutine point_c32( q, s, p, proc, status )
        type(c_ptr),              intent(in)    :: q
        integer,                  intent(in)    :: s(:)
        complex(real32), pointer, intent(inout) :: p(..)
        character(len=*),         intent(in)    :: proc
        integer, optional,        intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_c32

    subroutine point_i32( q, s, p, proc, status )
        type(c_ptr),             intent(in)    :: q
        integer,                 intent(in)    :: s(:)
        integer(int32), pointer, intent(inout) :: p(..)
        character(len=*),        intent(in)    :: proc
        integer, optional,       intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_i32

    subroutine point_i8( q, s, p, proc, status )
        type(c_ptr),      intent(in)              :: q
        integer,          intent(in)              :: s(:)
        integer(int8),    pointer, intent(inout)  :: p(..)
        character(len=*), intent(in)              :: proc
        integer,          optional, intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_i8

    subroutine point_i16( q, s, p, proc, status )
        type(c_ptr),             intent(in)    :: q
        integer,                 intent(in)    :: s(:)
        integer(int16), pointer, intent(inout) :: p(..)
        character(len=*),        intent(in)    :: proc
        integer, optional,       intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_i16

    subroutine point_i64( q, s, p, proc, status )
        type(c_ptr),             intent(in)    :: q
        integer,                 intent(in)    :: s(:)
        integer(int64), pointer, intent(inout) :: p(..)
        character(len=*),        intent(in)    :: proc
        integer, optional,       intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_i64

    subroutine point_l( q, s, p, proc, status )
        type(c_ptr),              intent(in)    :: q
        integer,                  intent(in)    :: s(:)
        logical(c_bool), pointer, intent(inout) :: p(..)
        character(len=*),         intent(in)    :: proc
        integer, optional,        intent(inout) :: status
        select rank( p )
            rank(0)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p)
            rank(1)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:1))
            rank(2)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:2))
            rank(3)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:3))
            rank(4)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:4))
            rank(5)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:5))
            rank(6)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:6))
            rank(7)
                nullify(p)
                if( c_associated(q) ) call c_f_pointer(q, p, s(1:7))
            rank(8)
                nullify(p)
            rank(9)
                nullify(p)
            rank(10)
                nullify(p)
            rank(11)
                nullify(p)
            rank(12)
                nullify(p)
            rank(13)
                nullify(p)
            rank(14)
                nullify(p)
            rank(15)
                nullify(p)
        end select
        if( rank(p) > 7 .and. c_associated(q) ) call mlxf_report(proc, 'a pointer of rank above 7', status)
    end subroutine point_l

    module subroutine view_r32( a, p, status )
        type(mlx_array)      , intent(in)    :: a
        real(real32), pointer, intent(inout) :: p(..)
        integer, optional    , intent(out)   :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_FLOAT32, s, status)
        call point_r32(q, s, p, 'mlx_view', status)
    end subroutine view_r32

    module subroutine view_r64( a, p, status )
        type(mlx_array)      , intent(in)    :: a
        real(real64), pointer, intent(inout) :: p(..)
        integer, optional    , intent(out)   :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_FLOAT64, s, status)
        call point_r64(q, s, p, 'mlx_view', status)
    end subroutine view_r64

    module subroutine view_c32( a, p, status )
        type(mlx_array)         , intent(in)    :: a
        complex(real32), pointer, intent(inout) :: p(..)
        integer, optional       , intent(out)   :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_COMPLEX64, s, status)
        call point_c32(q, s, p, 'mlx_view', status)
    end subroutine view_c32

    module subroutine view_i32( a, p, status )
        type(mlx_array)        , intent(in)    :: a
        integer(int32), pointer, intent(inout) :: p(..)
        integer, optional      , intent(out)   :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_INT32, s, status)
        call point_i32(q, s, p, 'mlx_view', status)
    end subroutine view_i32

    module subroutine view_i8( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int8),   pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_INT8, s, status)
        call point_i8(q, s, p, 'mlx_view', status)
    end subroutine view_i8

    module subroutine view_i16( a, p, status )
        type(mlx_array)        , intent(in)    :: a
        integer(int16), pointer, intent(inout) :: p(..)
        integer, optional      , intent(out)   :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_INT16, s, status)
        call point_i16(q, s, p, 'mlx_view', status)
    end subroutine view_i16

    module subroutine view_i64( a, p, status )
        type(mlx_array)        , intent(in)    :: a
        integer(int64), pointer, intent(inout) :: p(..)
        integer, optional      , intent(out)   :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_INT64, s, status)
        call point_i64(q, s, p, 'mlx_view', status)
    end subroutine view_i64

    module subroutine view_l( a, p, status )
        type(mlx_array)         , intent(in)    :: a
        logical(c_bool), pointer, intent(inout) :: p(..)
        integer, optional       , intent(out)   :: status
        integer, allocatable :: s(:)
        type(c_ptr)          :: q
        call mlxf_enter('mlx_view')
        q = view_target(a, rank(p), MLXC_BOOL, s, status)
        call point_l(q, s, p, 'mlx_view', status)
    end subroutine view_l

    ! page-aligned host memory handed to MLX (zero-copy when Metal accepts it; otherwise MLX copies it and
    ! frees the buffer at once); returns the storage the caller may fill until a is first passed to the library
    function alloc_target( a, fshape, dtype, status, zero_copy ) result(p)
        type(mlx_array),   intent(inout) :: a
        integer,           intent(in)    :: fshape(:)
        integer(c_int),    intent(in)    :: dtype
        integer, optional, intent(out)   :: status
        logical, optional, intent(out)   :: zero_copy
        character(len=*), parameter :: PROC = 'mlx_alloc'
        type(c_ptr)                 :: p, buf, rec
        type(buffer_owner), pointer :: owner
        type(buffer_owner)          :: blank
        type(mlxc_array)            :: h
        integer(c_int)              :: cshape(MAX_RANK)
        integer(c_size_t)           :: nbytes
        integer                     :: n
        p = c_null_ptr
        if( present(zero_copy) ) zero_copy = .false.
        call mlxf_require_device(PROC)
        n = size(fshape)
        if( n > 7 .or. any(fshape < 0) )then
            call mlxf_report(PROC, 'a shape of rank above 7 or with a negative extent', status)
            return
        endif
        ! whole pages: Metal maps whole pages without a copy, so the buffer covers only memory the library owns.
        ! A shape whose bytes do not fit is refused: a wrapped count would allocate less than MLX addresses
        nbytes = buffer_bytes(fshape, itemsize(dtype))
        if( nbytes < 0_c_size_t )then
            call mlxf_report(PROC, 'a shape whose size in bytes is not representable', status)
            return
        endif
        if( c_posix_memalign(buf, PAGE_BYTES, nbytes) /= 0 )then
            call mlxf_report(PROC, 'posix_memalign failed', status)
            return
        endif
        if( c_posix_memalign(rec, 16_c_size_t, int(c_sizeof(blank), c_size_t)) /= 0 )then
            call c_free(buf)
            call mlxf_report(PROC, 'posix_memalign failed', status)
            return
        endif
        call c_f_pointer(rec, owner)
        owner%buf     = buf
        owner%in_call = 1
        owner%freed   = 0
        cshape(1:n) = int(fshape(n:1:-1), c_int)
        h = mlxc_array_new_data_managed_payload(buf, cshape, int(n, c_int), dtype, rec, c_funloc(release_buffer))
        owner%in_call = 0
        if( .not. c_associated(h%ctx) )then
            ! a failure: the buffer is still ours unless MLX took it and its deleter already ran
            if( owner%freed == 0 ) call c_free(buf)
            call c_free(rec)
            call mlxf_check(1_c_int, PROC, status)
            return
        endif
        ! when MLX copied the buffer, its deleter ran in the call and left the record to us; otherwise the
        ! deleter frees the record with the buffer when the array dies
        if( owner%freed /= 0 ) call c_free(rec)
        call mlxf_adopt(a, h, PROC)
        if( present(status) ) status = 0
        p = data_pointer(h, dtype)
        if( present(zero_copy) ) zero_copy = c_associated(p, buf)
    end function alloc_target

    ! MLX's deleter of a buffer mlx_alloc handed it, given its buffer_owner: frees the buffer, and the record
    ! too unless the creating call is still running (mlx_alloc then frees it). C++ calls it: it never stops
    subroutine release_buffer( rec ) bind(c, name='mlxf_release_alloc_buffer')
        type(c_ptr), value :: rec
        type(buffer_owner), pointer :: owner
        call c_f_pointer(rec, owner)
        call c_free(owner%buf)
        if( owner%in_call /= 0 )then
            owner%freed = 1
        else
            call c_free(rec)
        endif
    end subroutine release_buffer

    ! the bytes of a buffer for fshape of elements of isz bytes, rounded up to whole pages and at least one;
    ! -1 when a product or the rounding would pass the largest size the kind holds
    pure integer(c_size_t) function buffer_bytes( fshape, isz ) result(nbytes)
        integer,           intent(in) :: fshape(:)
        integer(c_size_t), intent(in) :: isz
        integer(c_size_t) :: count, limit
        integer           :: i
        nbytes = -1_c_size_t
        limit  = huge(nbytes) - PAGE_BYTES + 1_c_size_t
        count  = 1_c_size_t
        do i = 1, size(fshape)
            if( fshape(i) == 0 )then
                count = 0_c_size_t
                exit
            endif
            if( count > limit / int(fshape(i), c_size_t) ) return
            count = count * int(fshape(i), c_size_t)
        end do
        if( count > limit / isz ) return
        nbytes = max(1_c_size_t, count * isz)
        nbytes = PAGE_BYTES * ((nbytes + PAGE_BYTES - 1_c_size_t) / PAGE_BYTES)
    end function buffer_bytes

    module function alloc_r32( fshape, mold, view, status, zero_copy ) result(a)
        integer              , intent(in)    :: fshape(:)
        real(real32)         , intent(in)    :: mold
        real(real32), pointer, intent(inout) :: view(..)
        integer, optional    , intent(out)   :: status
        logical, optional    , intent(out)   :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_FLOAT32, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_r32(q, fshape, view, 'mlx_alloc', status)
    end function alloc_r32

    module function alloc_r64( fshape, mold, view, status, zero_copy ) result(a)
        integer              , intent(in)    :: fshape(:)
        real(real64)         , intent(in)    :: mold
        real(real64), pointer, intent(inout) :: view(..)
        integer, optional    , intent(out)   :: status
        logical, optional    , intent(out)   :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_FLOAT64, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_r64(q, fshape, view, 'mlx_alloc', status)
    end function alloc_r64

    module function alloc_c32( fshape, mold, view, status, zero_copy ) result(a)
        integer                 , intent(in)    :: fshape(:)
        complex(real32)         , intent(in)    :: mold
        complex(real32), pointer, intent(inout) :: view(..)
        integer, optional       , intent(out)   :: status
        logical, optional       , intent(out)   :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_COMPLEX64, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_c32(q, fshape, view, 'mlx_alloc', status)
    end function alloc_c32

    module function alloc_i32( fshape, mold, view, status, zero_copy ) result(a)
        integer                , intent(in)    :: fshape(:)
        integer(int32)         , intent(in)    :: mold
        integer(int32), pointer, intent(inout) :: view(..)
        integer, optional      , intent(out)   :: status
        logical, optional      , intent(out)   :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_INT32, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_i32(q, fshape, view, 'mlx_alloc', status)
    end function alloc_i32

    module function alloc_i8( fshape, mold, view, status, zero_copy ) result(a)
        integer,       intent(in)             :: fshape(:)
        integer(int8), intent(in)             :: mold
        integer(int8), pointer, intent(inout) :: view(..)
        integer,       optional, intent(out)  :: status
        logical,       optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_INT8, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_i8(q, fshape, view, 'mlx_alloc', status)
    end function alloc_i8

    module function alloc_i16( fshape, mold, view, status, zero_copy ) result(a)
        integer                , intent(in)    :: fshape(:)
        integer(int16)         , intent(in)    :: mold
        integer(int16), pointer, intent(inout) :: view(..)
        integer, optional      , intent(out)   :: status
        logical, optional      , intent(out)   :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_INT16, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_i16(q, fshape, view, 'mlx_alloc', status)
    end function alloc_i16

    module function alloc_i64( fshape, mold, view, status, zero_copy ) result(a)
        integer                , intent(in)    :: fshape(:)
        integer(int64)         , intent(in)    :: mold
        integer(int64), pointer, intent(inout) :: view(..)
        integer, optional      , intent(out)   :: status
        logical, optional      , intent(out)   :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_INT64, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_i64(q, fshape, view, 'mlx_alloc', status)
    end function alloc_i64

    module function alloc_l( fshape, mold, view, status, zero_copy ) result(a)
        integer                 , intent(in)    :: fshape(:)
        logical(c_bool)         , intent(in)    :: mold
        logical(c_bool), pointer, intent(inout) :: view(..)
        integer, optional       , intent(out)   :: status
        logical, optional       , intent(out)   :: zero_copy
        type(mlx_array) :: a
        type(c_ptr)     :: q
        call mlxf_enter('mlx_alloc')
        q = c_null_ptr
        if( rank(view) == size(fshape) )then
            q = alloc_target(a, fshape, MLXC_BOOL, status, zero_copy)
        else
            call mlxf_report('mlx_alloc', 'the view''s rank differs from the size of the shape', status)
        endif
        call point_l(q, fshape, view, 'mlx_alloc', status)
    end function alloc_l

end submodule mlxf_transfer_borrow
