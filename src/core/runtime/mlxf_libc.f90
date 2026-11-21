!@descr: the C library entry points the library calls (strlen, memcpy, posix_memalign, free) and C-string copies
module mlxf_libc
use, intrinsic :: iso_c_binding, only: c_char, c_int, c_ptr, c_size_t, c_associated, c_f_pointer
implicit none

public :: c_strlen, c_memcpy, c_posix_memalign, c_free, c_string_copy
private

interface
    function c_strlen( s ) bind(c, name='strlen') result(n)
        import :: c_ptr, c_size_t
        type(c_ptr), value :: s
        integer(c_size_t) :: n
    end function c_strlen

    function c_memcpy( dst, src, n ) bind(c, name='memcpy') result(p)
        import :: c_ptr, c_size_t
        type(c_ptr),       value :: dst, src
        integer(c_size_t), value :: n
        type(c_ptr) :: p
    end function c_memcpy

    function c_posix_memalign( memptr, alignment, size ) bind(c, name='posix_memalign') result(ierr)
        import :: c_ptr, c_size_t, c_int
        type(c_ptr),       intent(out) :: memptr
        integer(c_size_t), value       :: alignment, size
        integer(c_int) :: ierr
    end function c_posix_memalign

    subroutine c_free( p ) bind(c, name='free')
        import :: c_ptr
        type(c_ptr), value :: p
    end subroutine c_free
end interface

contains

    ! a Fortran copy of a NUL-terminated C string; empty for a null pointer
    function c_string_copy( p ) result(s)
        type(c_ptr), intent(in) :: p
        character(len=:),       allocatable :: s
        character(kind=c_char), pointer     :: chars(:)
        integer                             :: n, i
        if( .not. c_associated(p) )then
            s = ''
            return
        endif
        n = int(c_strlen(p))
        call c_f_pointer(p, chars, [n])
        s = repeat(' ', n)
        do i = 1, n
            s(i:i) = chars(i)
        end do
    end function c_string_copy

end module mlxf_libc
