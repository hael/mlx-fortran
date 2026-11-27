!@descr: the C library entry points the library calls (strlen, memcpy, posix_memalign, free, fopen, fclose, dup, fdopen, rename, unlink, chmod, lstat, getpid, geteuid; symlink, link, mkdir, rmdir for the tests), C-string copies and a file's facts
module mlxf_libc
use, intrinsic :: iso_c_binding, only: c_char, c_int, c_int8_t, c_int16_t, c_int32_t, c_ptr, c_size_t, c_associated, &
                                       c_f_pointer, c_null_char
use mlxf_defs, only: mlxf_file_info
implicit none

public :: c_strlen, c_memcpy, c_posix_memalign, c_free, c_string_copy, c_fopen, c_fclose, c_dup, c_fdopen, c_rename, &
    &c_unlink, c_chmod, c_getpid, c_geteuid, c_file_info, c_symlink, c_link, c_mkdir, c_rmdir
private

! macOS's struct stat (144 bytes on arm64): st_mode is the uint16 at byte offset 4, st_nlink the uint16 at 6,
! st_uid the uint32 at 16; S_IFMT, S_IFLNK and S_IFREG are the file-type bits of st_mode
integer, parameter :: STAT_BYTES = 256, S_IFMT = int(o'170000'), S_IFLNK = int(o'120000'), S_IFREG = int(o'100000')

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

    function c_fopen( path, mode ) bind(c, name='fopen') result(f)
        import :: c_ptr, c_char
        character(kind=c_char), intent(in) :: path(*), mode(*)
        type(c_ptr) :: f
    end function c_fopen

    function c_fclose( f ) bind(c, name='fclose') result(ierr)
        import :: c_ptr, c_int
        type(c_ptr), value :: f
        integer(c_int) :: ierr
    end function c_fclose

    function c_dup( fd ) bind(c, name='dup') result(copy)
        import :: c_int
        integer(c_int), value :: fd
        integer(c_int) :: copy
    end function c_dup

    function c_fdopen( fd, mode ) bind(c, name='fdopen') result(f)
        import :: c_ptr, c_int, c_char
        integer(c_int),         value      :: fd
        character(kind=c_char), intent(in) :: mode(*)
        type(c_ptr) :: f
    end function c_fdopen

    function c_rename( old, new ) bind(c, name='rename') result(ierr)
        import :: c_int, c_char
        character(kind=c_char), intent(in) :: old(*), new(*)
        integer(c_int) :: ierr
    end function c_rename

    function c_unlink( path ) bind(c, name='unlink') result(ierr)
        import :: c_int, c_char
        character(kind=c_char), intent(in) :: path(*)
        integer(c_int) :: ierr
    end function c_unlink

    function c_chmod( path, mode ) bind(c, name='chmod') result(ierr)
        import :: c_int, c_int16_t, c_char
        character(kind=c_char), intent(in) :: path(*)
        integer(c_int16_t),     value      :: mode
        integer(c_int) :: ierr
    end function c_chmod

    function c_lstat( path, buf ) bind(c, name='lstat') result(ierr)
        import :: c_int, c_int8_t, c_char
        character(kind=c_char), intent(in)  :: path(*)
        integer(c_int8_t),      intent(out) :: buf(*)
        integer(c_int) :: ierr
    end function c_lstat

    function c_getpid() bind(c, name='getpid') result(pid)
        import :: c_int
        integer(c_int) :: pid
    end function c_getpid

    function c_geteuid() bind(c, name='geteuid') result(uid)
        import :: c_int32_t
        integer(c_int32_t) :: uid
    end function c_geteuid

    ! the tests make the destinations a save refuses with these (a symbolic link, a second hard link, a directory)
    function c_symlink( target, path ) bind(c, name='symlink') result(ierr)
        import :: c_int, c_char
        character(kind=c_char), intent(in) :: target(*), path(*)
        integer(c_int) :: ierr
    end function c_symlink

    function c_link( existing, path ) bind(c, name='link') result(ierr)
        import :: c_int, c_char
        character(kind=c_char), intent(in) :: existing(*), path(*)
        integer(c_int) :: ierr
    end function c_link

    function c_mkdir( path, mode ) bind(c, name='mkdir') result(ierr)
        import :: c_int, c_int16_t, c_char
        character(kind=c_char), intent(in) :: path(*)
        integer(c_int16_t),     value      :: mode
        integer(c_int) :: ierr
    end function c_mkdir

    function c_rmdir( path ) bind(c, name='rmdir') result(ierr)
        import :: c_int, c_char
        character(kind=c_char), intent(in) :: path(*)
        integer(c_int) :: ierr
    end function c_rmdir
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

    ! the facts lstat gives of path (a Fortran string, trailing blanks dropped); exists is false when lstat fails
    function c_file_info( path ) result(info)
        character(len=*), intent(in) :: path
        type(mlxf_file_info) :: info
        integer(c_int8_t)    :: buf(STAT_BYTES)
        integer              :: mode
        buf = 0_c_int8_t
        if( c_lstat(trim(path)//c_null_char, buf) /= 0 ) return
        info%exists  = .true.
        mode         = unsigned16(buf(5:6))
        info%link    = iand(mode, S_IFMT) == S_IFLNK
        info%regular = iand(mode, S_IFMT) == S_IFREG
        info%mode    = iand(mode, int(o'7777'))
        info%nlink   = unsigned16(buf(7:8))
        info%uid     = int(transfer(buf(17:20), 0_c_int32_t))
    end function c_file_info

    ! the little-endian unsigned 16-bit value of two bytes
    integer function unsigned16( b )
        integer(c_int8_t), intent(in) :: b(2)
        unsigned16 = iand(int(b(1)), 255) + 256*iand(int(b(2)), 255)
    end function unsigned16

end module mlxf_libc
