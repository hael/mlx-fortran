!@descr: devices and initialisation: the device count, the default device, device information, the default stream
! The first public call installs the error handler. A GPU is present when MLX can open one; without one a
! Metal build of MLX cannot allocate on either device, and the first operation that would allocate stops.
module mlxf_device
use, intrinsic :: iso_c_binding,   only: c_bool, c_int, c_null_char, c_ptr, c_size_t
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,  only: mlxc_device, mlxc_device_info, mlxc_stream, MLXC_CPU, MLXC_GPU
use mlxf_c_device, only: mlxc_device_new, mlxc_device_new_type, mlxc_device_free, mlxc_get_default_device, &
                         mlxc_set_default_device, mlxc_device_get_type, mlxc_device_count, mlxc_device_info_new, &
                         mlxc_device_info_get, mlxc_device_info_free, mlxc_device_info_get_size, &
                         mlxc_device_info_get_string, mlxc_device_info_has_key
use mlxf_c_metal,  only: mlxc_metal_is_available
use mlxf_c_stream, only: mlxc_stream_new, mlxc_get_default_stream, mlxc_stream_free, mlxc_synchronize
use mlxf_libc,     only: c_string_copy
use mlxf_error,    only: mlxf_check, mlxf_fail, mlxf_report, mlxf_install_error_handler, mlxf_guard_thread
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
        mlx_device_count = 0
        if( .not. known_device(device_type, 'mlx_device_count') ) return
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
        if( .not. known_device(device_type, 'mlx_set_default_device', status) ) return
        dev  = mlxc_device_new_type(int(device_type, c_int), 0_c_int)
        ierr = mlxc_set_default_device(dev)
        call mlxf_check(mlxc_device_free(dev), 'mlx_set_default_device')
        call mlxf_check(ierr, 'mlx_set_default_device', status)
    end subroutine mlx_set_default_device

    ! a size MLX reports for a device (max_buffer_length, memory_size, ...); -1 with status 0 when the device or
    ! the key is absent. A failure inside MLX is an error, never a -1 alone: the status, or a stop without one
    function mlx_device_info_size( device_type, key, status ) result(n)
        integer,           intent(in)  :: device_type
        character(len=*),  intent(in)  :: key
        integer, optional, intent(out) :: status
        integer(int64)         :: n
        type(mlxc_device_info) :: info
        integer(c_size_t)      :: v
        integer(c_int)         :: ierr
        logical                :: has
        call mlxf_enter('mlx_device_info_size')
        n = -1_int64
        if( .not. known_device(device_type, 'mlx_device_info_size', status) ) return
        call info_of(device_type, key, info, has, ierr)
        if( has )then
            v    = 0
            ierr = mlxc_device_info_get_size(v, info, trim(key)//c_null_char)
            if( ierr == 0 ) n = int(v, int64)
            call free_info(info, ierr)
        endif
        call mlxf_check(ierr, 'mlx_device_info_size', status)
    end function mlx_device_info_size

    ! a string MLX reports for a device (device_name, architecture, ...); empty with status 0 when the device or
    ! the key is absent. A failure inside MLX is an error, never an empty string alone: the status, or a stop
    function mlx_device_info_string( device_type, key, status ) result(s)
        integer,           intent(in)  :: device_type
        character(len=*),  intent(in)  :: key
        integer, optional, intent(out) :: status
        character(len=:), allocatable :: s
        type(mlxc_device_info)        :: info
        type(c_ptr)                   :: p
        integer(c_int)                :: ierr
        logical                       :: has
        call mlxf_enter('mlx_device_info_string')
        s = ''
        if( .not. known_device(device_type, 'mlx_device_info_string', status) ) return
        call info_of(device_type, key, info, has, ierr)
        if( has )then
            ierr = mlxc_device_info_get_string(p, info, trim(key)//c_null_char)
            if( ierr == 0 ) s = c_string_copy(p)
            call free_info(info, ierr)
        endif
        call mlxf_check(ierr, 'mlx_device_info_string', status)
    end function mlx_device_info_string

    ! the information of a device and whether it holds key; has is true only on success, and then the caller
    ! frees info. ierr is MLX's first failure (0 for an absent device or key), and a failure leaves nothing to free
    subroutine info_of( device_type, key, info, has, ierr )
        integer,                intent(in)    :: device_type
        character(len=*),       intent(in)    :: key
        type(mlxc_device_info), intent(inout) :: info
        logical,                intent(out)   :: has
        integer(c_int),         intent(out)   :: ierr
        type(mlxc_device) :: dev
        logical(c_bool)   :: has_key
        integer(c_int)    :: ndev, ierr_free
        has  = .false.
        ndev = 0
        ierr = mlxc_device_count(ndev, int(device_type, c_int))
        if( ierr /= 0 .or. ndev == 0 ) return
        dev       = mlxc_device_new_type(int(device_type, c_int), 0_c_int)
        info      = mlxc_device_info_new()
        ierr      = mlxc_device_info_get(info, dev)
        ierr_free = mlxc_device_free(dev)
        if( ierr == 0 ) ierr = ierr_free
        has_key = .false.
        if( ierr == 0 ) ierr = mlxc_device_info_has_key(has_key, info, trim(key)//c_null_char)
        has = ierr == 0 .and. logical(has_key)
        if( .not. has ) call free_info(info, ierr)
    end subroutine info_of

    ! whether device_type is MLX_DEVICES%cpu or %gpu; another value is reported (the status, or a stop), since
    ! mlx-c indexes a table with it unchecked
    logical function known_device( device_type, proc, status )
        integer,           intent(in)  :: device_type
        character(len=*),  intent(in)  :: proc
        integer, optional, intent(out) :: status
        known_device = device_type == int(MLXC_CPU) .or. device_type == int(MLXC_GPU)
        if( known_device )then
            if( present(status) ) status = 0
        else
            call mlxf_report(proc, 'an unknown device type (MLX_DEVICES%cpu or %gpu)', status)
        endif
    end function known_device

    ! frees device information, keeping the first failure in ierr
    subroutine free_info( info, ierr )
        type(mlxc_device_info), intent(inout) :: info
        integer(c_int),         intent(inout) :: ierr
        integer(c_int) :: ierr_free
        ierr_free = mlxc_device_info_free(info)
        if( ierr == 0 ) ierr = ierr_free
    end subroutine free_info

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
