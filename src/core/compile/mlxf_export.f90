!@descr: functions written to a file and read back: one trace or several, and the imported function as a counted handle
! An exported function is the graph its callback built on the example inputs, in MLX's own file format; the file
! holds MLX's shapes, which are the Fortran shapes reversed, and reads back as the same Fortran shapes. Writing
! and reading files are checked procedures.
module mlxf_export
use, intrinsic :: iso_c_binding,   only: c_int, c_bool, c_intptr_t, c_null_ptr, c_null_char, c_associated
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,  only: mlxc_closure, mlxc_function_exporter, mlxc_imported_function, mlxc_vector_array
use mlxf_c_export, only: mlxc_export_function, mlxc_function_exporter_new, mlxc_function_exporter_free, &
                         mlxc_function_exporter_apply, mlxc_imported_function_new, mlxc_imported_function_free, &
                         mlxc_imported_function_apply
use mlxf_c_vector, only: mlxc_vector_array_new, mlxc_vector_array_free
use mlxf_array,    only: mlx_array, mlxf_vector_import, mlxf_vector_export
use mlxf_compile,  only: mlx_function, mlxf_function_handle
use mlxf_device,   only: mlxf_require_device
use mlxf_error,    only: mlxf_check, mlxf_fail, mlxf_report, mlxf_guard_thread
use mlxf_registry, only: registry_add, registry_retain, registry_release, registry_is_live
implicit none
public :: mlx_export_function, mlx_function_exporter, mlx_imported_function
private

! what the copies of an exporter share besides the handle: whether an application has failed
type :: exporter_state
    logical :: failed = .false.
end type exporter_state

type :: mlx_function_exporter
    private
    type(mlxc_function_exporter)  :: h
    integer(int64)                :: serial = 0_int64
    type(exporter_state), pointer :: state => null()
  contains
    procedure          :: new => exporter_new
    procedure          :: kill => exporter_kill
    procedure          :: apply => exporter_apply
    procedure, private :: exporter_assign
    generic            :: assignment(=) => exporter_assign
    final              :: exporter_final
end type mlx_function_exporter

interface mlx_function_exporter
    module procedure exporter_from_function
end interface mlx_function_exporter

type :: mlx_imported_function
    private
    type(mlxc_imported_function) :: h
    integer(int64)               :: serial = 0_int64
  contains
    procedure          :: new => imported_new
    procedure          :: kill => imported_kill
    procedure          :: apply => imported_apply
    procedure, private :: imported_assign
    generic            :: assignment(=) => imported_assign
    final              :: imported_final
end type mlx_imported_function

interface mlx_imported_function
    module procedure imported_from_file
end interface mlx_imported_function

contains

    ! writes to file the graph f builds on inputs; with shapeless the graph serves other extents of the same
    ! ranks and dtypes. With status, a failure (the callback's, or the file's) returns with MLX usable
    subroutine mlx_export_function( file, f, inputs, shapeless, status )
        character(len=*),   intent(in)            :: file
        type(mlx_function), intent(in)            :: f
        type(mlx_array),    intent(in)            :: inputs(:)
        logical,            optional, intent(in)  :: shapeless
        integer,            optional, intent(out) :: status
        type(mlxc_vector_array) :: vin
        type(mlxc_closure)      :: hf
        logical(c_bool)         :: dynamic
        integer                 :: st, cleanup
        call mlxf_require_device('mlx_export_function')
        hf = mlxf_function_handle(f, 'mlx_export_function')
        dynamic = .false._c_bool
        if( present(shapeless) ) dynamic = logical(shapeless, c_bool)
        vin = mlxc_vector_array_new()
        call mlxf_vector_export(vin, inputs, st)
        if( st == 0 ) call mlxf_check(mlxc_export_function(trim(file)//c_null_char, hf, vin, dynamic), &
            &'mlx_export_function', status=st)
        call mlxf_check(mlxc_vector_array_free(vin), 'mlx_export_function cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(int(st, c_int), 'mlx_export_function', status=status)
    end subroutine mlx_export_function

    ! an exporter that writes to file one trace of f for each application
    function exporter_from_function( file, f, shapeless ) result(e)
        character(len=*),   intent(in)           :: file
        type(mlx_function), intent(in)           :: f
        logical,            optional, intent(in) :: shapeless
        type(mlx_function_exporter) :: e
        call mlxf_require_device('mlx_function_exporter')
        call e%new(file, f, shapeless)
    end function exporter_from_function

    ! opens file for the traces of f; with status, a file that cannot be written returns with self empty
    subroutine exporter_new( self, file, f, shapeless, status )
        class(mlx_function_exporter), intent(inout)         :: self
        character(len=*),             intent(in)            :: file
        type(mlx_function),           intent(in)            :: f
        logical,                      optional, intent(in)  :: shapeless
        integer,                      optional, intent(out) :: status
        type(mlxc_closure) :: hf
        logical(c_bool)    :: dynamic
        integer            :: st
        call mlxf_require_device('mlx_function_exporter new')
        hf = mlxf_function_handle(f, 'mlx_function_exporter new')
        dynamic = .false._c_bool
        if( present(shapeless) ) dynamic = logical(shapeless, c_bool)
        call self%kill()
        if( present(status) ) status = 0
        self%h = mlxc_function_exporter_new(trim(file)//c_null_char, hf, dynamic)
        if( .not. c_associated(self%h%ctx) )then
            call mlxf_check(1_c_int, 'mlx_function_exporter new', status)
            return
        endif
        allocate(self%state, stat=st)
        if( st /= 0 ) call mlxf_fail('mlx_function_exporter new', 'cannot allocate the exporter state')
        self%serial = registry_add(exporter_key(self%h))
    end subroutine exporter_new

    ! adds to the file the graph the function builds on inputs: another trace, for other shapes or dtypes. MLX
    ! leaves an exporter whose trace failed in a state it reads unchecked at the next one, so after a failed
    ! application every copy refuses further ones
    subroutine exporter_apply( self, inputs, status )
        class(mlx_function_exporter), intent(in)            :: self
        type(mlx_array),              intent(in)            :: inputs(:)
        integer,                      optional, intent(out) :: status
        type(mlxc_vector_array) :: vin
        integer                 :: st, cleanup
        call mlxf_require_device('mlx_function_exporter apply')
        if( .not. c_associated(self%h%ctx) ) call mlxf_fail('mlx_function_exporter apply', 'empty mlx_function_exporter')
        if( .not. registry_is_live(exporter_key(self%h), self%serial) ) &
            &call mlxf_fail('mlx_function_exporter apply', 'stale mlx_function_exporter')
        if( self%state%failed )then
            call mlxf_report('mlx_function_exporter apply', 'an earlier application failed: make a new exporter', status)
            return
        endif
        vin = mlxc_vector_array_new()
        call mlxf_vector_export(vin, inputs, st)
        if( st == 0 ) call mlxf_check(mlxc_function_exporter_apply(self%h, vin), 'mlx_function_exporter apply', status=st)
        call mlxf_check(mlxc_vector_array_free(vin), 'mlx_function_exporter cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st /= 0 ) self%state%failed = .true.
        call mlxf_check(int(st, c_int), 'mlx_function_exporter apply', status=status)
    end subroutine exporter_apply

    ! a counted copy of the handle; the thread guard runs only when a live handle is involved
    impure elemental subroutine exporter_assign( lhs, rhs )
        class(mlx_function_exporter), intent(inout) :: lhs
        class(mlx_function_exporter), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx).or.c_associated(rhs%h%ctx) ) call mlxf_guard_thread('mlx_function_exporter assignment')
        if( c_associated(lhs%h%ctx, rhs%h%ctx).and.lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(exporter_key(rhs%h), rhs%serial) ) &
                &call mlxf_fail('mlx_function_exporter assignment', 'stale exporter copy')
        endif
        call exporter_release(lhs)
        lhs%h = rhs%h
        lhs%serial = rhs%serial
        lhs%state => rhs%state
    end subroutine exporter_assign

    ! releases the handle, the last release closing the file; idempotent
    impure elemental subroutine exporter_kill( self )
        class(mlx_function_exporter), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('mlx_function_exporter kill')
        call exporter_release(self)
    end subroutine exporter_kill

    ! finalization releases as kill does
    impure elemental subroutine exporter_final( self )
        type(mlx_function_exporter), intent(inout) :: self
        call self%kill()
    end subroutine exporter_final

    ! drops one count, the last freeing the mlx-c exporter and the shared state; the handle is empty afterwards
    impure elemental subroutine exporter_release( self )
        class(mlx_function_exporter), intent(inout) :: self
        integer :: st
        if( .not. c_associated(self%h%ctx) ) return
        if( registry_release(exporter_key(self%h), self%serial) )then
            call mlxf_check(mlxc_function_exporter_free(self%h), 'mlx_function_exporter release')
            if( associated(self%state) ) deallocate(self%state, stat=st)
        endif
        self%h%ctx = c_null_ptr
        self%serial = 0_int64
        nullify(self%state)
    end subroutine exporter_release

    ! the registry's key of an exporter: its context address
    integer(int64) function exporter_key( h ) result(key)
        type(mlxc_function_exporter), intent(in) :: h
        key = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function exporter_key

    ! the function a file holds; a file that cannot be read stops (the binding new takes a status)
    function imported_from_file( file ) result(g)
        character(len=*), intent(in) :: file
        type(mlx_imported_function) :: g
        call mlxf_require_device('mlx_imported_function')
        call g%new(file)
    end function imported_from_file

    ! reads the function file holds; with status, a file that cannot be read returns with self empty
    subroutine imported_new( self, file, status )
        class(mlx_imported_function), intent(inout)         :: self
        character(len=*),             intent(in)            :: file
        integer,                      optional, intent(out) :: status
        call mlxf_require_device('mlx_imported_function new')
        call self%kill()
        if( present(status) ) status = 0
        self%h = mlxc_imported_function_new(trim(file)//c_null_char)
        if( .not. c_associated(self%h%ctx) )then
            call mlxf_check(1_c_int, 'mlx_imported_function new', status)
            return
        endif
        self%serial = registry_add(imported_key(self%h))
    end subroutine imported_new

    ! the imported graph on inputs, which must match one of its traces; with status, a failure returns with
    ! outputs unallocated and MLX usable
    subroutine imported_apply( self, inputs, outputs, status )
        class(mlx_imported_function), intent(in)               :: self
        type(mlx_array),              intent(in)               :: inputs(:)
        type(mlx_array),              allocatable, intent(out) :: outputs(:)
        integer,                      optional, intent(out)    :: status
        type(mlxc_vector_array) :: vin, vout
        integer                 :: st, cleanup
        call mlxf_require_device('mlx_imported_function apply')
        if( .not. c_associated(self%h%ctx) ) call mlxf_fail('mlx_imported_function apply', 'empty mlx_imported_function')
        if( .not. registry_is_live(imported_key(self%h), self%serial) ) &
            &call mlxf_fail('mlx_imported_function apply', 'stale mlx_imported_function')
        vin = mlxc_vector_array_new()
        vout = mlxc_vector_array_new()
        call mlxf_vector_export(vin, inputs, st)
        if( st == 0 ) call mlxf_check(mlxc_imported_function_apply(vout, self%h, vin), 'mlx_imported_function apply', &
            &status=st)
        if( st == 0 ) call mlxf_vector_import(outputs, vout, st)
        call mlxf_check(mlxc_vector_array_free(vin), 'mlx_imported_function input cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(vout), 'mlx_imported_function output cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st /= 0 )then
            if( allocated(outputs) ) deallocate(outputs)
        endif
        call mlxf_check(int(st, c_int), 'mlx_imported_function apply', status=status)
    end subroutine imported_apply

    ! a counted copy of the handle; the thread guard runs only when a live handle is involved
    impure elemental subroutine imported_assign( lhs, rhs )
        class(mlx_imported_function), intent(inout) :: lhs
        class(mlx_imported_function), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx).or.c_associated(rhs%h%ctx) ) call mlxf_guard_thread('mlx_imported_function assignment')
        if( c_associated(lhs%h%ctx, rhs%h%ctx).and.lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(imported_key(rhs%h), rhs%serial) ) &
                &call mlxf_fail('mlx_imported_function assignment', 'stale function copy')
        endif
        call imported_release(lhs)
        lhs%h = rhs%h
        lhs%serial = rhs%serial
    end subroutine imported_assign

    ! releases the handle; idempotent, and without the thread guard for an empty one
    impure elemental subroutine imported_kill( self )
        class(mlx_imported_function), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('mlx_imported_function kill')
        call imported_release(self)
    end subroutine imported_kill

    ! finalization releases as kill does
    impure elemental subroutine imported_final( self )
        type(mlx_imported_function), intent(inout) :: self
        call self%kill()
    end subroutine imported_final

    ! drops one count, the last freeing the mlx-c object; the handle is empty afterwards
    impure elemental subroutine imported_release( self )
        class(mlx_imported_function), intent(inout) :: self
        if( .not. c_associated(self%h%ctx) ) return
        if( registry_release(imported_key(self%h), self%serial) ) &
            &call mlxf_check(mlxc_imported_function_free(self%h), 'mlx_imported_function release')
        self%h%ctx = c_null_ptr
        self%serial = 0_int64
    end subroutine imported_release

    ! the registry's key of an imported function: its context address
    integer(int64) function imported_key( h ) result(key)
        type(mlxc_imported_function), intent(in) :: h
        key = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function imported_key

end module mlxf_export
