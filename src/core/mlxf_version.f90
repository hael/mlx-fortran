!@descr: versions of mlx-fortran, of the mlx-c it was built against and of the MLX it runs on
! Holds the few mlx-c entry points it calls as its own bind(c) interfaces.
module mlxf_version
use, intrinsic :: iso_c_binding, only: c_char, c_int, c_ptr, c_size_t, c_associated, c_f_pointer
implicit none
private

public :: mlxf_version_string, mlxf_build_description, mlx_runtime_version, mlx_gpu_device_count

#include "mlxf_build_info.inc"

! mlx_device_type of mlx-c: MLX_CPU, MLX_GPU
integer(c_int), parameter :: MLXC_GPU = 1_c_int

! mlx_string of mlx-c: an opaque handle passed by value
type, bind(c) :: mlxc_string
    type(c_ptr) :: ctx
end type mlxc_string

interface
    function mlxc_string_new() bind(c, name='mlx_string_new') result(str)
        import :: mlxc_string
        type(mlxc_string) :: str
    end function mlxc_string_new

    function mlxc_string_data( str ) bind(c, name='mlx_string_data') result(p)
        import :: mlxc_string, c_ptr
        type(mlxc_string), value :: str
        type(c_ptr) :: p
    end function mlxc_string_data

    function mlxc_string_free( str ) bind(c, name='mlx_string_free') result(ierr)
        import :: mlxc_string, c_int
        type(mlxc_string), value :: str
        integer(c_int) :: ierr
    end function mlxc_string_free

    function mlxc_version( str ) bind(c, name='mlx_version') result(ierr)
        import :: mlxc_string, c_int
        type(mlxc_string), intent(inout) :: str
        integer(c_int) :: ierr
    end function mlxc_version

    function mlxc_device_count( count, dtype ) bind(c, name='mlx_device_count') result(ierr)
        import :: c_int
        integer(c_int), intent(out) :: count
        integer(c_int), value       :: dtype
        integer(c_int) :: ierr
    end function mlxc_device_count

    function c_strlen( s ) bind(c, name='strlen') result(n)
        import :: c_ptr, c_size_t
        type(c_ptr), value :: s
        integer(c_size_t) :: n
    end function c_strlen
end interface

contains

    ! the mlx-fortran release
    pure function mlxf_version_string() result(v)
        character(len=:), allocatable :: v
        v = BUILD_INFO_RELEASE
    end function mlxf_version_string

    ! the release, build type and Fortran compiler, and the mlx-c the library was configured with
    pure function mlxf_build_description() result(d)
        character(len=:), allocatable :: d
        d = 'mlx-fortran '//BUILD_INFO_RELEASE//' ('//BUILD_INFO_BUILD_TYPE//', '//BUILD_INFO_FC//&
            &', mlx-c '//BUILD_INFO_MLXC//')'
    end function mlxf_build_description

    ! the version of the MLX library loaded at run time; empty when mlx-c reports an error
    function mlx_runtime_version() result(v)
        character(len=:), allocatable :: v
        type(mlxc_string)             :: str
        integer(c_int)                :: ierr
        v    = ''
        str  = mlxc_string_new()
        ierr = mlxc_version(str)
        if( ierr == 0 ) v = c_string_copy(mlxc_string_data(str))
        ierr = mlxc_string_free(str)
    end function mlx_runtime_version

    ! the number of GPU devices MLX can open here: 0 in a headless, sandboxed or virtual session
    integer function mlx_gpu_device_count()
        integer(c_int) :: count
        mlx_gpu_device_count = 0
        if( mlxc_device_count(count, MLXC_GPU) == 0 ) mlx_gpu_device_count = int(count)
    end function mlx_gpu_device_count

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
        allocate(character(len=n) :: s)
        do i = 1, n
            s(i:i) = chars(i)
        end do
    end function c_string_copy

end module mlxf_version
