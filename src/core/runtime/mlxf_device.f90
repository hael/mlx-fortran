!@descr: devices and initialisation: the device count, the default device, device information, the default stream
! The first public call installs the error handler. A GPU is present when MLX can open one; without one a
! Metal build of MLX cannot allocate on either device, and the first operation that would allocate stops.
module mlxf_device
use, intrinsic :: iso_c_binding, only: c_bool, c_int, c_null_char, c_ptr, c_size_t
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,  only: mlxc_device, mlxc_device_info, mlxc_stream, MLXC_GPU
use mlxf_c_device, only: mlxc_device_new, mlxc_device_new_type, mlxc_device_free, mlxc_get_default_device, &
                         mlxc_set_default_device, mlxc_device_get_type, mlxc_device_count, mlxc_device_info_new, &
                         mlxc_device_info_get, mlxc_device_info_free, mlxc_device_info_get_size, &
                         mlxc_device_info_get_string, mlxc_device_info_has_key
use mlxf_c_metal,  only: mlxc_metal_is_available
use mlxf_c_stream, only: mlxc_stream_new, mlxc_get_default_stream, mlxc_stream_free, mlxc_synchronize
use mlxf_libc,     only: c_string_copy
use mlxf_error,    only: mlxf_check, mlxf_fail, mlxf_install_error_handler, mlxf_guard_thread
implicit none

public :: mlx_device_count, mlx_default_device, mlx_set_default_device, mlx_device_info_size
public :: mlx_device_info_string, mlxf_enter, mlxf_require_device, mlxf_default_stream, mlxf_synchronize_device
private

integer, parameter :: NOT_INITIALISED = 0, WITH_DEVICE = 1, WITHOUT_DEVICE = 2

! whether the library has initialised (error handler installed) and whether it can allocate on a device
integer :: init_state = NOT_INITIALISED

contains

    ! every public entry: the one-thread guard, then initialisation on the first call
    subroutine mlxf_enter( proc )
        character(len=*), intent(in) :: proc
        logical(c_bool) :: metal
        integer(c_int)  :: n
        call mlxf_guard_thread(proc)
        if( init_state /= NOT_INITIALISED ) return
        call mlxf_install_error_handler()
        init_state = WITH_DEVICE
        metal = .false.
        call mlxf_check(mlxc_metal_is_available(metal), proc)
        if( .not. metal ) return
        n = 0
        call mlxf_check(mlxc_device_count(n, MLXC_GPU), proc)
        if( n == 0 ) init_state = WITHOUT_DEVICE
    end subroutine mlxf_enter

    ! an operation that allocates: stops when MLX cannot allocate in this session
    subroutine mlxf_require_device( proc )
        character(len=*), intent(in) :: proc
        call mlxf_enter(proc)
        if( init_state == WITHOUT_DEVICE ) call mlxf_fail(proc, 'no Metal device can be opened in this session '//&
            &'(headless, sandboxed or virtual); a Metal build of MLX cannot allocate on either device')
    end subroutine mlxf_require_device

    ! the number of devices of a type (MLX_DEVICES%cpu or %gpu) MLX can open here
    integer function mlx_device_count( device_type )
        integer, intent(in) :: device_type
        integer(c_int) :: n
        call mlxf_enter('mlx_device_count')
        n = 0
        call mlxf_check(mlxc_device_count(n, int(device_type, c_int)), 'mlx_device_count')
        mlx_device_count = int(n)
    end function mlx_device_count

    ! the type of MLX's default device: MLX_DEVICES%cpu or %gpu
    integer function mlx_default_device()
        type(mlxc_device) :: dev
        integer(c_int)    :: dtype
        call mlxf_enter('mlx_default_device')
        dev = mlxc_device_new()
        call mlxf_check(mlxc_get_default_device(dev), 'mlx_default_device')
        dtype = 0
        call mlxf_check(mlxc_device_get_type(dtype, dev), 'mlx_default_device')
        call mlxf_check(mlxc_device_free(dev), 'mlx_default_device')
        mlx_default_device = int(dtype)
    end function mlx_default_device

    ! makes a device type (MLX_DEVICES%cpu or %gpu) MLX's default for the operations that follow
    subroutine mlx_set_default_device( device_type, status )
        integer,           intent(in)  :: device_type
        integer, optional, intent(out) :: status
        type(mlxc_device) :: dev
        integer(c_int)    :: ierr
        call mlxf_enter('mlx_set_default_device')
        dev  = mlxc_device_new_type(int(device_type, c_int), 0_c_int)
        ierr = mlxc_set_default_device(dev)
        call mlxf_check(mlxc_device_free(dev), 'mlx_set_default_device')
        call mlxf_check(ierr, 'mlx_set_default_device', status)
    end subroutine mlx_set_default_device

    ! a size MLX reports for a device (max_buffer_length, memory_size, ...); -1 when the key is absent
    function mlx_device_info_size( device_type, key ) result(n)
        integer,          intent(in) :: device_type
        character(len=*), intent(in) :: key
        integer(int64)         :: n
        type(mlxc_device_info) :: info
        integer(c_size_t)      :: v
        call mlxf_enter('mlx_device_info_size')
        n = -1_int64
        if( .not. info_of(device_type, key, info, 'mlx_device_info_size') ) return
        v = 0
        if( mlxc_device_info_get_size(v, info, trim(key)//c_null_char) == 0 ) n = int(v, int64)
        call mlxf_check(mlxc_device_info_free(info), 'mlx_device_info_size')
    end function mlx_device_info_size

    ! a string MLX reports for a device (device_name, architecture, ...); empty when the key is absent
    function mlx_device_info_string( device_type, key ) result(s)
        integer,          intent(in) :: device_type
        character(len=*), intent(in) :: key
        character(len=:), allocatable :: s
        type(mlxc_device_info)        :: info
        type(c_ptr)                   :: p
        call mlxf_enter('mlx_device_info_string')
        s = ''
        if( .not. info_of(device_type, key, info, 'mlx_device_info_string') ) return
        if( mlxc_device_info_get_string(p, info, trim(key)//c_null_char) == 0 ) s = c_string_copy(p)
        call mlxf_check(mlxc_device_info_free(info), 'mlx_device_info_string')
    end function mlx_device_info_string

    ! the information of a device that holds key; false (nothing to free) otherwise
    logical function info_of( device_type, key, info, proc )
        integer,                intent(in)    :: device_type
        character(len=*),       intent(in)    :: key, proc
        type(mlxc_device_info), intent(inout) :: info
        type(mlxc_device) :: dev
        logical(c_bool)   :: has
        integer(c_int)    :: ierr
        call mlxf_enter(proc)
        info_of = .false.
        if( mlx_device_count(device_type) == 0 ) return
        dev  = mlxc_device_new_type(int(device_type, c_int), 0_c_int)
        info = mlxc_device_info_new()
        ierr = mlxc_device_info_get(info, dev)
        call mlxf_check(mlxc_device_free(dev), proc)
        has = .false.
        if( ierr == 0 ) ierr = mlxc_device_info_has_key(has, info, trim(key)//c_null_char)
        info_of = ierr == 0 .and. logical(has)
        if( .not. info_of ) call mlxf_check(mlxc_device_info_free(info), proc)
    end function info_of

    ! the default stream of the default device; the caller frees it with mlxc_stream_free
    function mlxf_default_stream( proc ) result(s)
        character(len=*), intent(in) :: proc
        type(mlxc_stream) :: s
        type(mlxc_device) :: dev
        dev = mlxc_device_new()
        call mlxf_check(mlxc_get_default_device(dev), proc)
        s = mlxc_stream_new()
        call mlxf_check(mlxc_get_default_stream(s, dev), proc)
        call mlxf_check(mlxc_device_free(dev), proc)
    end function mlxf_default_stream

    ! waits for the work queued on the default stream of a device type present here
    subroutine mlxf_synchronize_device( device_type, proc, status )
        integer,           intent(in)  :: device_type
        character(len=*),  intent(in)  :: proc
        integer, optional, intent(out) :: status
        type(mlxc_device) :: dev
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        if( present(status) ) status = 0
        if( mlx_device_count(device_type) == 0 ) return
        dev  = mlxc_device_new_type(int(device_type, c_int), 0_c_int)
        s    = mlxc_stream_new()
        ierr = mlxc_get_default_stream(s, dev)
        if( ierr == 0 ) ierr = mlxc_synchronize(s)
        call mlxf_check(mlxc_stream_free(s), proc)
        call mlxf_check(mlxc_device_free(dev), proc)
        call mlxf_check(ierr, proc, status)
    end subroutine mlxf_synchronize_device

end module mlxf_device
