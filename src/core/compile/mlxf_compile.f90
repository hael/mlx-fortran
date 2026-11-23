!@descr: owned Fortran callbacks as MLX closures and compiled functions
module mlxf_compile
use, intrinsic :: iso_c_binding,   only: c_ptr, c_int, c_bool, c_intptr_t, c_null_ptr, c_associated, c_loc, &
                                         c_f_pointer, c_funloc
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,   only: mlxc_closure, mlxc_vector_array
use mlxf_c_closure, only: mlxc_closure_new, mlxc_closure_new_func_payload, mlxc_closure_free, mlxc_closure_apply
use mlxf_c_compile, only: mlxc_compile
use mlxf_c_vector,  only: mlxc_vector_array_new, mlxc_vector_array_free
use mlxf_array,     only: mlx_array, mlxf_vector_import, mlxf_vector_export
use mlxf_device,    only: mlxf_enter, mlxf_require_device
use mlxf_error,     only: mlxf_check, mlxf_fail, mlxf_report, mlxf_guard_thread
use mlxf_registry,  only: registry_add, registry_retain, registry_release, registry_is_live
implicit none
public :: mlx_function, mlx_compile
private
abstract interface
    subroutine array_callback( inputs, outputs, status )
        import :: mlx_array
        type(mlx_array), intent(in)               :: inputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable, intent(out) :: outputs(:)
    end subroutine array_callback
end interface

type :: callback_payload
    procedure(array_callback), pointer, nopass :: callback => null()
    integer :: traces = 0
end type callback_payload

type :: mlx_function
    private
    type(mlxc_closure)              :: h
    integer(int64)                  :: serial = 0_int64
    type(callback_payload), pointer :: payload => null()
  contains
    procedure          :: new => function_new
    procedure          :: kill => function_kill
    procedure          :: apply => function_apply
    procedure          :: trace_count => function_trace_count
    procedure, private :: function_assign
    generic            :: assignment(=) => function_assign
    final              :: function_final
end type mlx_function

interface mlx_function
    module procedure function_from_callback
end interface mlx_function

contains

    ! an mlx_function from a checked subroutine callback(inputs, outputs, status)
    function function_from_callback( callback ) result(f)
        procedure(array_callback) :: callback
        type(mlx_function) :: f
        call mlxf_enter('mlx_function')
        call f%new(callback)
    end function function_from_callback

    ! wraps callback in an mlx-c closure whose payload holds the procedure pointer; MLX frees the payload
    ! through delete_payload when the last closure sharing it dies, compiled ones included
    subroutine function_new( self, callback )
        class(mlx_function), intent(inout) :: self
        procedure(array_callback)          :: callback
        integer :: status
        call mlxf_require_device('mlx_function new')
        call self%kill()
        allocate(self%payload, stat=status)
        if( status /= 0 ) call mlxf_fail('mlx_function', 'cannot allocate callback payload')
        self%payload%callback => callback
        self%h = mlxc_closure_new_func_payload(c_funloc(invoke_callback), c_loc(self%payload), c_funloc(delete_payload))
        if( .not. c_associated(self%h%ctx) ) call mlxf_fail('mlx_function', 'closure construction failed')
        self%serial = registry_add(closure_key(self%h))
    end subroutine function_new

    ! the compiled form of f, shapeless keeping one trace across input shapes; it shares f's payload, which
    ! MLX keeps alive after f is killed
    function mlx_compile( f, shapeless ) result(g)
        type(mlx_function), intent(in)           :: f
        logical,            optional, intent(in) :: shapeless
        type(mlx_function) :: g
        logical(c_bool)    :: dynamic
        integer(c_int)     :: ierr
        call mlxf_require_device('mlx_compile')
        call require_function(f, 'mlx_compile')
        dynamic = .false._c_bool
        if( present(shapeless) ) dynamic = logical(shapeless, c_bool)
        g%h = mlxc_closure_new()
        ierr = mlxc_compile(g%h, f%h, dynamic)
        if( ierr /= 0 ) call mlxf_check(mlxc_closure_free(g%h), 'mlx_compile cleanup')
        call mlxf_check(ierr, 'mlx_compile')
        g%serial = registry_add(closure_key(g%h))
        g%payload => f%payload
    end function mlx_compile

    ! the callback or its compiled graph on inputs; with status, a failure returns with outputs unallocated
    ! and MLX usable. Recursive: a callback may apply another function
    recursive subroutine function_apply( self, inputs, outputs, status )
        class(mlx_function), intent(in)               :: self
        type(mlx_array),     intent(in)               :: inputs(:)
        type(mlx_array),     allocatable, intent(out) :: outputs(:)
        integer,             optional, intent(out)    :: status
        type(mlxc_vector_array) :: vin, vout
        integer                 :: st, cleanup
        call mlxf_require_device('mlx_function apply')
        call require_function(self, 'mlx_function apply')
        vin = mlxc_vector_array_new()
        vout = mlxc_vector_array_new()
        call mlxf_vector_export(vin, inputs, st)
        if( st == 0 ) call mlxf_check(mlxc_closure_apply(vout, self%h, vin), 'mlx_function apply', status=st)
        if( st == 0 ) call mlxf_vector_import(outputs, vout, st)
        call mlxf_check(mlxc_vector_array_free(vin), 'mlx_function input cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(vout), 'mlx_function output cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st /= 0 )then
            if( allocated(outputs) ) deallocate(outputs)
        endif
        call mlxf_check(int(st, c_int), 'mlx_function apply', status=status)
    end subroutine function_apply

    ! how often the callback has run, shared by the copies and compiled forms of the function
    integer function function_trace_count( self ) result(n)
        class(mlx_function), intent(in) :: self
        call mlxf_enter('mlx_function trace_count')
        call require_function(self, 'mlx_function trace_count')
        n = self%payload%traces
    end function function_trace_count

    ! a counted copy of the closure handle; the thread guard runs only when a live handle is involved, so
    ! empty functions may be copied anywhere
    impure elemental subroutine function_assign( lhs, rhs )
        class(mlx_function), intent(inout) :: lhs
        class(mlx_function), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx).or.c_associated(rhs%h%ctx) ) call mlxf_guard_thread('mlx_function assignment')
        if( c_associated(lhs%h%ctx, rhs%h%ctx).and.lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(closure_key(rhs%h), rhs%serial) ) &
                &call mlxf_fail('mlx_function assignment', 'stale function copy')
        endif
        call function_release(lhs)
        lhs%h = rhs%h
        lhs%serial = rhs%serial
        lhs%payload => rhs%payload
    end subroutine function_assign

    ! releases the handle; idempotent, and without the thread guard for an empty function
    impure elemental subroutine function_kill( self )
        class(mlx_function), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('mlx_function kill')
        call function_release(self)
    end subroutine function_kill

    ! finalization releases as kill does
    impure elemental subroutine function_final( self )
        type(mlx_function), intent(inout) :: self
        call self%kill()
    end subroutine function_final

    ! drops one count, the last freeing the mlx-c closure; the function is empty afterwards
    impure elemental subroutine function_release( self )
        class(mlx_function), intent(inout) :: self
        if( .not. c_associated(self%h%ctx) ) return
        if( registry_release(closure_key(self%h), self%serial) ) &
            &call mlxf_check(mlxc_closure_free(self%h), 'mlx_function release')
        self%h%ctx = c_null_ptr
        self%serial = 0_int64
        nullify(self%payload)
    end subroutine function_release

    ! stops unless f holds a live closure (empty and stale copies are refused)
    subroutine require_function( f, proc )
        class(mlx_function), intent(in) :: f
        character(len=*),    intent(in) :: proc
        if( .not. c_associated(f%h%ctx) ) call mlxf_fail(proc, 'empty mlx_function')
        if( .not. registry_is_live(closure_key(f%h), f%serial) ) call mlxf_fail(proc, 'stale mlx_function')
    end subroutine require_function

    ! the registry's key of a closure: its context address
    integer(int64) function closure_key( h ) result(key)
        type(mlxc_closure), intent(in) :: h
        key = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function closure_key

    ! the C trampoline mlx-c calls: imports the inputs, runs the Fortran callback, exports its outputs and
    ! returns the status; it never stops, as it runs inside MLX's C++ frames
    recursive integer(c_int) function invoke_callback( res, input, payload ) bind(c) result(ierr)
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_vector_array), value         :: input
        type(c_ptr),             value         :: payload
        type(callback_payload), pointer     :: state
        type(mlx_array),        allocatable :: inputs(:), outputs(:)
        integer                             :: st
        call c_f_pointer(payload, state)
        call mlxf_vector_import(inputs, input, st)
        if( st == 0 )then
            state%traces = state%traces+1
            call state%callback(inputs, outputs, st)
            if( st == 0 )then
                if( allocated(outputs) )then
                    call mlxf_vector_export(res, outputs, st)
                else
                    call mlxf_report('mlx_function callback', 'callback did not allocate outputs', status=st)
                endif
            endif
        endif
        ierr = int(st, c_int)
    end function invoke_callback

    ! the payload destructor mlx-c calls when the last closure sharing it dies; it reports, never stops
    subroutine delete_payload( payload ) bind(c)
        type(c_ptr), value :: payload
        type(callback_payload), pointer :: state
        integer                         :: st
        call c_f_pointer(payload, state)
        deallocate(state, stat=st)
        if( st /= 0 ) call mlxf_report('closure destructor', 'payload deallocation failed', status=st)
    end subroutine delete_payload
end module mlxf_compile
