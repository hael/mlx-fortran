!@descr: the C library entry points the library calls (strlen, memcpy, posix_memalign, free, fopen, fclose, dup, fdopen, rename, unlink, chmod, lstat through a C helper, getpid, geteuid; symlink, link, mkdir, rmdir for the tests), C-string copies and a file's facts
module mlxf_libc
use, intrinsic :: iso_c_binding, only: c_char, c_int, c_int16_t, c_int32_t, c_ptr, c_size_t, c_associated, c_f_pointer, &
                                       c_null_char
use mlxf_defs, only: mlxf_file_info
implicit none

public :: c_strlen, c_memcpy, c_posix_memalign, c_free, c_string_copy, c_fopen, c_fclose, c_dup, c_fdopen, c_rename, &
    &c_unlink, c_chmod, c_getpid, c_geteuid, c_file_info, c_symlink, c_link, c_mkdir, c_rmdir
private

! the file types the lstat helper reports (mlxf_libc_lstat.c); anything else is 0
integer, parameter :: LSTAT_LINK = 1, LSTAT_REGULAR = 2

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

    ! lstat through the C helper, which reads the platform's own struct stat (its layout differs between macOS and
    ! glibc): the file type, the permission bits with set-id and sticky, the hard links and the owner
    function c_lstat_facts( path, ftype, perm, nlink, uid ) bind(c, name='mlxf_lstat_facts') result(ierr)
        import :: c_int, c_int32_t, c_char
        character(kind=c_char), intent(in)  :: path(*)
        integer(c_int32_t),     intent(out) :: ftype, perm, nlink, uid
        integer(c_int) :: ierr
    end function c_lstat_facts

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
        integer(c_int32_t)   :: ftype, perm, nlink, uid
        if( c_lstat_facts(trim(path)//c_null_char, ftype, perm, nlink, uid) /= 0 ) return
        info%exists  = .true.
        info%link    = ftype == LSTAT_LINK
        info%regular = ftype == LSTAT_REGULAR
        info%mode    = int(perm)
        info%nlink   = int(nlink)
        info%uid     = int(uid)
    end function c_file_info

end module mlxf_libc
