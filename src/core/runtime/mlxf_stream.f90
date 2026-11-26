!@descr: streams: a device's queue of work behind a counted handle, the default stream of a device, and waiting for one
! Operations take no stream: they run on the default stream of the default device. A program that wants its work
! on a queue of its own makes a stream and sets it as its device's default.
module mlxf_stream
use, intrinsic :: iso_c_binding,   only: c_int, c_intptr_t, c_null_ptr, c_associated
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,  only: mlxc_stream, mlxc_device, MLXC_CPU, MLXC_GPU
use mlxf_c_device, only: mlxc_device_new_type, mlxc_device_free
use mlxf_c_stream, only: mlxc_stream_new_device, mlxc_stream_free, mlxc_default_cpu_stream_new, &
                         mlxc_default_gpu_stream_new, mlxc_set_default_stream, mlxc_synchronize
use mlxf_device,   only: mlxf_enter, mlxf_require_device
use mlxf_error,    only: mlxf_check, mlxf_fail, mlxf_guard_thread
use mlxf_registry, only: registry_add, registry_retain, registry_release, registry_is_live
implicit none
public :: mlx_stream, mlx_new_stream, mlx_default_stream, mlx_set_default_stream, mlx_synchronize
private

type :: mlx_stream
    private
    type(mlxc_stream) :: h
    integer(int64)    :: serial = 0_int64
  contains
    procedure          :: kill => stream_kill
    procedure, private :: stream_assign
    generic            :: assignment(=) => stream_assign
    final              :: stream_final
end type mlx_stream

interface mlx_synchronize
    module procedure synchronize_stream
end interface mlx_synchronize

contains

    ! a new stream on a device type, MLX_DEVICES%cpu or %gpu: a queue of its own
    function mlx_new_stream( device_type ) result(s)
        integer, intent(in) :: device_type
        type(mlx_stream)  :: s
        type(mlxc_device) :: dev
        call mlxf_require_device('mlx_new_stream')
        call require_device_type(device_type, 'mlx_new_stream')
        dev = mlxc_device_new_type(int(device_type, c_int), 0_c_int)
        s%h = mlxc_stream_new_device(dev)
        call mlxf_check(mlxc_device_free(dev), 'mlx_new_stream')
        call adopt_stream(s, 'mlx_new_stream')
    end function mlx_new_stream

    ! a device type's default stream as it is now: the one operations on that device run on
    function mlx_default_stream( device_type ) result(s)
        integer, intent(in) :: device_type
        type(mlx_stream) :: s
        call mlxf_require_device('mlx_default_stream')
        call require_device_type(device_type, 'mlx_default_stream')
        if( device_type == int(MLXC_GPU) )then
            s%h = mlxc_default_gpu_stream_new()
        else
            s%h = mlxc_default_cpu_stream_new()
        endif
        call adopt_stream(s, 'mlx_default_stream')
    end function mlx_default_stream

    ! makes stream the default of its device: the operations built on that device from now on run on it
    subroutine mlx_set_default_stream( stream )
        type(mlx_stream), intent(in) :: stream
        call mlxf_require_device('mlx_set_default_stream')
        call require_stream(stream, 'mlx_set_default_stream')
        call mlxf_check(mlxc_set_default_stream(stream%h), 'mlx_set_default_stream')
    end subroutine mlx_set_default_stream

    ! waits for the work queued on stream; with status, a failure returns with MLX usable
    subroutine synchronize_stream( stream, status )
        type(mlx_stream),  intent(in)  :: stream
        integer, optional, intent(out) :: status
        call mlxf_enter('mlx_synchronize')
        call require_stream(stream, 'mlx_synchronize')
        call mlxf_check(mlxc_synchronize(stream%h), 'mlx_synchronize', status)
    end subroutine synchronize_stream

    ! a counted copy of the handle; the thread guard runs only when a live handle is involved
    impure elemental subroutine stream_assign( lhs, rhs )
        class(mlx_stream), intent(inout) :: lhs
        class(mlx_stream), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx).or.c_associated(rhs%h%ctx) ) call mlxf_guard_thread('mlx_stream assignment')
        if( c_associated(lhs%h%ctx, rhs%h%ctx).and.lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(stream_key(rhs%h), rhs%serial) ) &
                &call mlxf_fail('mlx_stream assignment', 'stale stream copy')
        endif
        call stream_release(lhs)
        lhs%h = rhs%h
        lhs%serial = rhs%serial
    end subroutine stream_assign

    ! releases the handle; idempotent, and without the thread guard for an empty one. MLX keeps the stream itself
    impure elemental subroutine stream_kill( self )
        class(mlx_stream), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('mlx_stream kill')
        call stream_release(self)
    end subroutine stream_kill

    ! finalization releases as kill does
    impure elemental subroutine stream_final( self )
        type(mlx_stream), intent(inout) :: self
        call self%kill()
    end subroutine stream_final

    ! drops one count, the last freeing the mlx-c handle; the handle is empty afterwards
    impure elemental subroutine stream_release( self )
        class(mlx_stream), intent(inout) :: self
        if( .not. c_associated(self%h%ctx) ) return
        if( registry_release(stream_key(self%h), self%serial) ) &
            &call mlxf_check(mlxc_stream_free(self%h), 'mlx_stream release')
        self%h%ctx = c_null_ptr
        self%serial = 0_int64
    end subroutine stream_release

    ! registers a handle mlx-c just returned; a null one stops
    subroutine adopt_stream( s, proc )
        type(mlx_stream), intent(inout) :: s
        character(len=*), intent(in)    :: proc
        if( .not. c_associated(s%h%ctx) ) call mlxf_fail(proc, 'the stream could not be made')
        s%serial = registry_add(stream_key(s%h))
    end subroutine adopt_stream

    ! stops unless s holds a live stream
    subroutine require_stream( s, proc )
        type(mlx_stream), intent(in) :: s
        character(len=*), intent(in) :: proc
        if( .not. c_associated(s%h%ctx) ) call mlxf_fail(proc, 'empty mlx_stream')
        if( .not. registry_is_live(stream_key(s%h), s%serial) ) call mlxf_fail(proc, 'stale mlx_stream')
    end subroutine require_stream

    ! stops unless device_type is MLX_DEVICES%cpu or %gpu: mlx-c indexes a table with it unchecked
    subroutine require_device_type( device_type, proc )
        integer,          intent(in) :: device_type
        character(len=*), intent(in) :: proc
        if( device_type /= int(MLXC_CPU) .and. device_type /= int(MLXC_GPU) ) &
            &call mlxf_fail(proc, 'an unknown device type (MLX_DEVICES%cpu or %gpu)')
    end subroutine require_device_type

    ! the registry's key of a stream handle: its context address
    integer(int64) function stream_key( h ) result(key)
        type(mlxc_stream), intent(in) :: h
        key = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function stream_key

end module mlxf_stream
