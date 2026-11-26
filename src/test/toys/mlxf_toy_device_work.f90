!@descr: the opaque device state of a toy class (test only): an abstract type with one deferred binding, kill
! A toy class that can run on MLX holds its device state as class(device_work), allocatable. The workspaces, in
! device modules, extend the type; the class's host files see only this module, so they compile without the
! library, and its glue submodules resolve the dynamic type. A holder calls kill on every element before it
! deallocates: the release of MLX handles never rests on the finalization of a polymorphic component.
module mlxf_toy_device_work
implicit none

public :: device_work
private

type, abstract :: device_work
  contains
    procedure(device_work_kill), deferred :: kill
end type device_work

abstract interface
    ! idempotent: releases every device object the extension holds
    subroutine device_work_kill( self )
        import :: device_work
        class(device_work), intent(inout) :: self
    end subroutine device_work_kill
end interface

end module mlxf_toy_device_work
