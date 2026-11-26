!@descr: function transforms: values and gradients, vector-Jacobian and Jacobian-vector products, custom derivatives, checkpoints
! A transform takes an mlx_function and differentiates the graph its callback builds. Positions among a
! function's inputs are one-based. A transform that returns a function returns an mlx_function, which shares the
! callback of the function it was made from; mlx_value_and_grad returns its own counted handle, since it has
! two lists of results.
module mlxf_transforms
use, intrinsic :: iso_c_binding,   only: c_ptr, c_int, c_size_t, c_intptr_t, c_null_ptr, c_associated, c_loc, &
                                         c_f_pointer, c_funloc
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,      only: mlxc_closure, mlxc_closure_value_and_grad, mlxc_closure_custom, mlxc_closure_custom_jvp, &
                             mlxc_closure_custom_vmap, mlxc_vector_array
use mlxf_c_closure,    only: mlxc_closure_new, mlxc_closure_free, mlxc_closure_value_and_grad_new, &
                             mlxc_closure_value_and_grad_free, mlxc_closure_value_and_grad_apply, &
                             mlxc_closure_custom_new_func_payload, mlxc_closure_custom_free, &
                             mlxc_closure_custom_jvp_new_func_payload, mlxc_closure_custom_jvp_free
use mlxf_c_ops,        only: mlxc_depends
use mlxf_c_transforms, only: mlxc_value_and_grad, mlxc_vjp, mlxc_jvp, mlxc_custom_vjp, mlxc_custom_function, &
                             mlxc_checkpoint
use mlxf_c_vector,     only: mlxc_vector_array_new, mlxc_vector_array_free
use mlxf_array,        only: mlx_array, mlxf_vector_import, mlxf_vector_export
use mlxf_compile,      only: mlx_function, mlxf_function_handle, mlxf_function_adopt
use mlxf_device,       only: mlxf_require_device
use mlxf_error,        only: mlxf_check, mlxf_fail, mlxf_report, mlxf_guard_thread
use mlxf_registry,     only: registry_add, registry_retain, registry_release, registry_is_live
implicit none
public :: mlx_grad_function, mlx_value_and_grad, mlx_vjp, mlx_jvp, mlx_custom_vjp, mlx_custom_function, mlx_checkpoint, &
    &mlx_depends
private

abstract interface
    ! the vector-Jacobian product a custom function substitutes: from the inputs, the cotangents of the outputs
    ! and the outputs, one array per input
    subroutine vjp_callback( primals, cotangents, outputs, vjps, status )
        import :: mlx_array
        type(mlx_array), intent(in)               :: primals(:), cotangents(:), outputs(:)
        type(mlx_array), allocatable, intent(out) :: vjps(:)
        integer,         intent(out)              :: status
    end subroutine vjp_callback
    ! the Jacobian-vector product a custom function substitutes: from the inputs, the tangents, and the one-based
    ! positions of the inputs the tangents belong to, one array per output
    subroutine jvp_callback( primals, tangents, argnums, jvps, status )
        import :: mlx_array
        type(mlx_array), intent(in)               :: primals(:), tangents(:)
        integer,         intent(in)               :: argnums(:)
        type(mlx_array), allocatable, intent(out) :: jvps(:)
        integer,         intent(out)              :: status
    end subroutine jvp_callback
end interface

type :: vjp_payload
    procedure(vjp_callback), pointer, nopass :: callback => null()
end type vjp_payload

type :: jvp_payload
    procedure(jvp_callback), pointer, nopass :: callback => null()
end type jvp_payload

type :: mlx_grad_function
    private
    type(mlxc_closure_value_and_grad) :: h
    integer(int64)                    :: serial = 0_int64
    integer, allocatable              :: order(:)
  contains
    procedure          :: new => grad_function_new
    procedure          :: kill => grad_function_kill
    procedure          :: apply => grad_function_apply
    procedure, private :: grad_function_assign
    generic            :: assignment(=) => grad_function_assign
    final              :: grad_function_final
end type mlx_grad_function

contains

    ! the function that returns f's outputs and the gradients of its first output, a scalar, with respect to the
    ! inputs at the one-based positions argnums (the first input by default)
    function mlx_value_and_grad( f, argnums ) result(g)
        type(mlx_function), intent(in)           :: f
        integer,            optional, intent(in) :: argnums(:)
        type(mlx_grad_function) :: g
        call mlxf_require_device('mlx_value_and_grad')
        call g%new(f, argnums)
    end function mlx_value_and_grad

    ! makes self the value-and-gradient function of f; a position below 1 stops (MLX would count it from the end).
    ! MLX returns the gradients in the order of the inputs: order(i) is where it puts the gradient of argnums(i)
    subroutine grad_function_new( self, f, argnums )
        class(mlx_grad_function), intent(inout)        :: self
        type(mlx_function),       intent(in)           :: f
        integer,                  optional, intent(in) :: argnums(:)
        integer(c_int), allocatable :: positions(:)
        type(mlxc_closure)          :: hf
        integer(c_int)              :: ierr
        integer                     :: i
        call mlxf_require_device('mlx_value_and_grad')
        hf = mlxf_function_handle(f, 'mlx_value_and_grad')
        if( present(argnums) )then
            if( size(argnums) == 0 ) call mlxf_fail('mlx_value_and_grad', 'argnums names no input')
            if( any(argnums < 1) ) call mlxf_fail('mlx_value_and_grad', 'argnums are one-based positions among the inputs')
            positions = int(argnums-1, c_int)
        else
            positions = [0_c_int]
        endif
        call self%kill()
        self%h = mlxc_closure_value_and_grad_new()
        ierr = mlxc_value_and_grad(self%h, hf, positions, int(size(positions), c_size_t))
        if( ierr /= 0 )then
            call mlxf_check(mlxc_closure_value_and_grad_free(self%h), 'mlx_value_and_grad cleanup')
            self%h%ctx = c_null_ptr
        endif
        call mlxf_check(ierr, 'mlx_value_and_grad')
        self%serial = registry_add(grad_key(self%h))
        self%order = [(count(positions <= positions(i)), i=1, size(positions))]
    end subroutine grad_function_new

    ! f's outputs on inputs (values) and the gradients of the first with respect to the chosen inputs (grads),
    ! in the order of argnums and each with its input's shape; with status, a failure returns with both lists
    ! unallocated and MLX usable
    recursive subroutine grad_function_apply( self, inputs, values, grads, status )
        class(mlx_grad_function), intent(in)               :: self
        type(mlx_array),          intent(in)               :: inputs(:)
        type(mlx_array),          allocatable, intent(out) :: values(:), grads(:)
        integer,                  optional, intent(out)    :: status
        type(mlx_array), allocatable :: sorted(:)
        type(mlxc_vector_array)      :: vin, v0, v1
        integer                      :: st, cleanup, i
        call mlxf_require_device('mlx_grad_function apply')
        if( .not. c_associated(self%h%ctx) ) call mlxf_fail('mlx_grad_function apply', 'empty mlx_grad_function')
        if( .not. registry_is_live(grad_key(self%h), self%serial) ) &
            &call mlxf_fail('mlx_grad_function apply', 'stale mlx_grad_function')
        vin = mlxc_vector_array_new()
        v0 = mlxc_vector_array_new()
        v1 = mlxc_vector_array_new()
        call mlxf_vector_export(vin, inputs, st)
        if( st == 0 ) call mlxf_check(mlxc_closure_value_and_grad_apply(v0, v1, self%h, vin), 'mlx_grad_function apply', &
            &status=st)
        if( st == 0 ) call mlxf_vector_import(values, v0, st)
        if( st == 0 ) call mlxf_vector_import(sorted, v1, st)
        call mlxf_check(mlxc_vector_array_free(vin), 'mlx_grad_function input cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(v0), 'mlx_grad_function value cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(v1), 'mlx_grad_function gradient cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st == 0 )then
            if( size(sorted) /= size(self%order) ) call mlxf_report('mlx_grad_function apply', &
                &'MLX returned another number of gradients than argnums names', status=st)
        endif
        if( st == 0 ) allocate(grads(size(sorted)), stat=st)
        if( st == 0 )then
            do i = 1, size(sorted)
                grads(i) = sorted(self%order(i))
            end do
        else
            if( allocated(values) ) deallocate(values)
            if( allocated(grads) ) deallocate(grads)
        endif
        call mlxf_check(int(st, c_int), 'mlx_grad_function apply', status=status)
    end subroutine grad_function_apply

    ! a counted copy of the handle; the thread guard runs only when a live handle is involved
    impure elemental subroutine grad_function_assign( lhs, rhs )
        class(mlx_grad_function), intent(inout) :: lhs
        class(mlx_grad_function), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx).or.c_associated(rhs%h%ctx) ) call mlxf_guard_thread('mlx_grad_function assignment')
        if( c_associated(lhs%h%ctx, rhs%h%ctx).and.lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(grad_key(rhs%h), rhs%serial) ) &
                &call mlxf_fail('mlx_grad_function assignment', 'stale function copy')
        endif
        call grad_function_release(lhs)
        lhs%h = rhs%h
        lhs%serial = rhs%serial
        if( allocated(rhs%order) ) lhs%order = rhs%order
    end subroutine grad_function_assign

    ! releases the handle; idempotent, and without the thread guard for an empty one
    impure elemental subroutine grad_function_kill( self )
        class(mlx_grad_function), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('mlx_grad_function kill')
        call grad_function_release(self)
    end subroutine grad_function_kill

    ! finalization releases as kill does
    impure elemental subroutine grad_function_final( self )
        type(mlx_grad_function), intent(inout) :: self
        call self%kill()
    end subroutine grad_function_final

    ! drops one count, the last freeing the mlx-c object; the handle is empty afterwards
    impure elemental subroutine grad_function_release( self )
        class(mlx_grad_function), intent(inout) :: self
        if( .not. c_associated(self%h%ctx) ) return
        if( registry_release(grad_key(self%h), self%serial) ) &
            &call mlxf_check(mlxc_closure_value_and_grad_free(self%h), 'mlx_grad_function release')
        self%h%ctx = c_null_ptr
        self%serial = 0_int64
        if( allocated(self%order) ) deallocate(self%order)
    end subroutine grad_function_release

    ! the registry's key of a value-and-gradient function: its context address
    integer(int64) function grad_key( h ) result(key)
        type(mlxc_closure_value_and_grad), intent(in) :: h
        key = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function grad_key

    ! f's outputs on primals and, for the cotangents (one per output, of its shape), the products of the
    ! transposed Jacobian with them: one array per input, of its shape. A failure, the callback's included, stops.
    ! Recursive: the callback may itself take a product, for a derivative of a derivative
    recursive subroutine mlx_vjp( f, primals, cotangents, outputs, vjps )
        type(mlx_function), intent(in)               :: f
        type(mlx_array),    intent(in)               :: primals(:), cotangents(:)
        type(mlx_array),    allocatable, intent(out) :: outputs(:), vjps(:)
        type(mlxc_vector_array) :: v(4)
        type(mlxc_closure)      :: hf
        integer                 :: st
        call mlxf_require_device('mlx_vjp')
        hf = mlxf_function_handle(f, 'mlx_vjp')
        call open_lists(v, primals, cotangents, st)
        if( st == 0 ) call mlxf_check(mlxc_vjp(v(3), v(4), hf, v(1), v(2)), 'mlx_vjp', status=st)
        call close_lists(v, outputs, vjps, st, 'mlx_vjp')
    end subroutine mlx_vjp

    ! f's outputs on primals and, for the tangents (one per input, of its shape), the products of the Jacobian
    ! with them: one array per output, of its shape. A failure, the callback's included, stops. Recursive, as
    ! mlx_vjp is
    recursive subroutine mlx_jvp( f, primals, tangents, outputs, jvps )
        type(mlx_function), intent(in)               :: f
        type(mlx_array),    intent(in)               :: primals(:), tangents(:)
        type(mlx_array),    allocatable, intent(out) :: outputs(:), jvps(:)
        type(mlxc_vector_array) :: v(4)
        type(mlxc_closure)      :: hf
        integer                 :: st
        call mlxf_require_device('mlx_jvp')
        hf = mlxf_function_handle(f, 'mlx_jvp')
        call open_lists(v, primals, tangents, st)
        if( st == 0 ) call mlxf_check(mlxc_jvp(v(3), v(4), hf, v(1), v(2)), 'mlx_jvp', status=st)
        call close_lists(v, outputs, jvps, st, 'mlx_jvp')
    end subroutine mlx_jvp

    ! four mlx-c vectors: a and b exported into the first two, the last two empty for the results
    subroutine open_lists( v, a, b, st )
        type(mlxc_vector_array), intent(out) :: v(4)
        type(mlx_array),         intent(in)  :: a(:), b(:)
        integer,                 intent(out) :: st
        integer :: i
        do i = 1, 4
            v(i) = mlxc_vector_array_new()
        end do
        call mlxf_vector_export(v(1), a, st)
        if( st == 0 ) call mlxf_vector_export(v(2), b, st)
    end subroutine open_lists

    ! the results of a product transform out of the last two vectors when st is zero; the four vectors are freed
    ! either way, and a failure stops only then
    subroutine close_lists( v, r0, r1, st, proc )
        type(mlxc_vector_array), intent(inout)            :: v(4)
        type(mlx_array),         allocatable, intent(out) :: r0(:), r1(:)
        integer,                 intent(inout)            :: st
        character(len=*),        intent(in)               :: proc
        integer :: i, cleanup
        if( st == 0 ) call mlxf_vector_import(r0, v(3), st)
        if( st == 0 ) call mlxf_vector_import(r1, v(4), st)
        do i = 1, 4
            call mlxf_check(mlxc_vector_array_free(v(i)), proc, status=cleanup)
            if( st == 0 ) st = cleanup
        end do
        call mlxf_check(int(st, c_int), proc)
    end subroutine close_lists

    ! f with its vector-Jacobian product replaced by vjp, a checked subroutine
    ! (primals, cotangents, outputs, vjps, status); the values of f are unchanged
    function mlx_custom_vjp( f, vjp ) result(g)
        type(mlx_function), intent(in) :: f
        procedure(vjp_callback)        :: vjp
        type(mlx_function)        :: g
        type(mlxc_closure)        :: hf, res
        type(mlxc_closure_custom) :: hv
        integer(c_int)            :: ierr
        call mlxf_require_device('mlx_custom_vjp')
        hf = mlxf_function_handle(f, 'mlx_custom_vjp')
        hv = custom_vjp_closure(vjp, 'mlx_custom_vjp')
        res = mlxc_closure_new()
        ierr = mlxc_custom_vjp(res, hf, hv)
        call mlxf_check(mlxc_closure_custom_free(hv), 'mlx_custom_vjp cleanup')
        if( ierr /= 0 ) call mlxf_check(mlxc_closure_free(res), 'mlx_custom_vjp cleanup')
        call mlxf_check(ierr, 'mlx_custom_vjp')
        call mlxf_function_adopt(g, res, f)
    end function mlx_custom_vjp

    ! f with its vector-Jacobian product replaced by vjp and its Jacobian-vector product by jvp, a checked
    ! subroutine (primals, tangents, argnums, jvps, status); an absent one stays MLX's own
    function mlx_custom_function( f, vjp, jvp ) result(g)
        type(mlx_function),      intent(in) :: f
        procedure(vjp_callback), optional   :: vjp
        procedure(jvp_callback), optional   :: jvp
        type(mlx_function)             :: g
        type(mlxc_closure)             :: hf, res
        type(mlxc_closure_custom)      :: hv
        type(mlxc_closure_custom_jvp)  :: hj
        type(mlxc_closure_custom_vmap) :: none
        integer(c_int)                 :: ierr
        call mlxf_require_device('mlx_custom_function')
        hf = mlxf_function_handle(f, 'mlx_custom_function')
        hv%ctx = c_null_ptr
        hj%ctx = c_null_ptr
        none%ctx = c_null_ptr
        if( present(vjp) ) hv = custom_vjp_closure(vjp, 'mlx_custom_function')
        if( present(jvp) ) hj = custom_jvp_closure(jvp, 'mlx_custom_function')
        res = mlxc_closure_new()
        ierr = mlxc_custom_function(res, hf, hv, hj, none)
        if( present(vjp) ) call mlxf_check(mlxc_closure_custom_free(hv), 'mlx_custom_function cleanup')
        if( present(jvp) ) call mlxf_check(mlxc_closure_custom_jvp_free(hj), 'mlx_custom_function cleanup')
        if( ierr /= 0 ) call mlxf_check(mlxc_closure_free(res), 'mlx_custom_function cleanup')
        call mlxf_check(ierr, 'mlx_custom_function')
        call mlxf_function_adopt(g, res, f)
    end function mlx_custom_function

    ! f with the intermediate arrays of its gradient discarded and recomputed when the gradient is taken
    function mlx_checkpoint( f ) result(g)
        type(mlx_function), intent(in) :: f
        type(mlx_function) :: g
        type(mlxc_closure) :: hf, res
        integer(c_int)     :: ierr
        call mlxf_require_device('mlx_checkpoint')
        hf = mlxf_function_handle(f, 'mlx_checkpoint')
        res = mlxc_closure_new()
        ierr = mlxc_checkpoint(res, hf)
        if( ierr /= 0 ) call mlxf_check(mlxc_closure_free(res), 'mlx_checkpoint cleanup')
        call mlxf_check(ierr, 'mlx_checkpoint')
        call mlxf_function_adopt(g, res, f)
    end function mlx_checkpoint

    ! the inputs as arrays whose evaluation also evaluates the dependencies: outputs(i) has the values of
    ! inputs(i). An empty list of inputs stops: MLX reads the first one unchecked
    subroutine mlx_depends( inputs, dependencies, outputs )
        type(mlx_array), intent(in)               :: inputs(:), dependencies(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        type(mlxc_vector_array) :: vin, vdep, vout
        integer                 :: st, cleanup
        call mlxf_require_device('mlx_depends')
        if( size(inputs) == 0 ) call mlxf_fail('mlx_depends', 'inputs names no array')
        vin = mlxc_vector_array_new()
        vdep = mlxc_vector_array_new()
        vout = mlxc_vector_array_new()
        call mlxf_vector_export(vin, inputs, st)
        if( st == 0 ) call mlxf_vector_export(vdep, dependencies, st)
        if( st == 0 ) call mlxf_check(mlxc_depends(vout, vin, vdep), 'mlx_depends', status=st)
        if( st == 0 ) call mlxf_vector_import(outputs, vout, st)
        call mlxf_check(mlxc_vector_array_free(vin), 'mlx_depends', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(vdep), 'mlx_depends', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(vout), 'mlx_depends', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(int(st, c_int), 'mlx_depends')
    end subroutine mlx_depends

    ! an mlx-c closure that calls vjp; MLX frees its payload when the last function holding it dies
    function custom_vjp_closure( vjp, proc ) result(h)
        procedure(vjp_callback)      :: vjp
        character(len=*), intent(in) :: proc
        type(mlxc_closure_custom)  :: h
        type(vjp_payload), pointer :: payload
        integer                    :: status
        allocate(payload, stat=status)
        if( status /= 0 ) call mlxf_fail(proc, 'cannot allocate the callback payload')
        payload%callback => vjp
        h = mlxc_closure_custom_new_func_payload(c_funloc(invoke_vjp), c_loc(payload), c_funloc(delete_vjp_payload))
        if( .not. c_associated(h%ctx) ) call mlxf_fail(proc, 'closure construction failed')
    end function custom_vjp_closure

    ! an mlx-c closure that calls jvp; MLX frees its payload when the last function holding it dies
    function custom_jvp_closure( jvp, proc ) result(h)
        procedure(jvp_callback)      :: jvp
        character(len=*), intent(in) :: proc
        type(mlxc_closure_custom_jvp) :: h
        type(jvp_payload), pointer    :: payload
        integer                       :: status
        allocate(payload, stat=status)
        if( status /= 0 ) call mlxf_fail(proc, 'cannot allocate the callback payload')
        payload%callback => jvp
        h = mlxc_closure_custom_jvp_new_func_payload(c_funloc(invoke_jvp), c_loc(payload), c_funloc(delete_jvp_payload))
        if( .not. c_associated(h%ctx) ) call mlxf_fail(proc, 'closure construction failed')
    end function custom_jvp_closure

    ! the C trampoline of a custom vector-Jacobian product: imports the three lists, runs the Fortran callback,
    ! exports its products and returns the status; it never stops, as it runs inside MLX's C++ frames. MLX indexes
    ! the products by input without a check, so another number of them than inputs is refused here
    recursive integer(c_int) function invoke_vjp( res, primals, cotangents, outputs, payload ) bind(c) result(ierr)
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_vector_array), value         :: primals
        type(mlxc_vector_array), value         :: cotangents
        type(mlxc_vector_array), value         :: outputs
        type(c_ptr),             value         :: payload
        type(vjp_payload), pointer     :: state
        type(mlx_array),   allocatable :: p(:), c(:), o(:), products(:)
        integer                        :: st
        call c_f_pointer(payload, state)
        call mlxf_vector_import(p, primals, st)
        if( st == 0 ) call mlxf_vector_import(c, cotangents, st)
        if( st == 0 ) call mlxf_vector_import(o, outputs, st)
        if( st == 0 )then
            call state%callback(p, c, o, products, st)
            if( st == 0 )then
                if( .not. allocated(products) )then
                    call mlxf_report('custom vjp callback', 'callback did not allocate its products', status=st)
                else if( size(products) /= size(p) )then
                    call mlxf_report('custom vjp callback', 'callback did not return one product per input', status=st)
                else
                    call mlxf_vector_export(res, products, st)
                endif
            endif
        endif
        ierr = int(st, c_int)
    end function invoke_vjp

    ! the C trampoline of a custom Jacobian-vector product; the positions MLX passes become one-based
    recursive integer(c_int) function invoke_jvp( res, primals, tangents, argnums, num, payload ) bind(c) result(ierr)
        type(mlxc_vector_array), intent(inout) :: res
        type(mlxc_vector_array), value         :: primals
        type(mlxc_vector_array), value         :: tangents
        integer(c_int),          intent(in)    :: argnums(*)
        integer(c_size_t),       value         :: num
        type(c_ptr),             value         :: payload
        type(jvp_payload), pointer     :: state
        type(mlx_array),   allocatable :: p(:), t(:), products(:)
        integer,           allocatable :: positions(:)
        integer                        :: st, i
        call c_f_pointer(payload, state)
        call mlxf_vector_import(p, primals, st)
        if( st == 0 ) call mlxf_vector_import(t, tangents, st)
        if( st == 0 ) allocate(positions(int(num)), stat=st)
        if( st == 0 )then
            do i = 1, int(num)
                positions(i) = int(argnums(i))+1
            end do
            call state%callback(p, t, positions, products, st)
            if( st == 0 )then
                if( allocated(products) )then
                    call mlxf_vector_export(res, products, st)
                else
                    call mlxf_report('custom jvp callback', 'callback did not allocate its products', status=st)
                endif
            endif
        endif
        ierr = int(st, c_int)
    end function invoke_jvp

    ! the payload destructors mlx-c calls when the last closure sharing a payload dies; they report, never stop
    subroutine delete_vjp_payload( payload ) bind(c)
        type(c_ptr), value :: payload
        type(vjp_payload), pointer :: state
        integer                    :: st
        call c_f_pointer(payload, state)
        deallocate(state, stat=st)
        if( st /= 0 ) call mlxf_report('closure destructor', 'payload deallocation failed', status=st)
    end subroutine delete_vjp_payload

    subroutine delete_jvp_payload( payload ) bind(c)
        type(c_ptr), value :: payload
        type(jvp_payload), pointer :: state
        integer                    :: st
        call c_f_pointer(payload, state)
        deallocate(state, stat=st)
        if( st /= 0 ) call mlxf_report('closure destructor', 'payload deallocation failed', status=st)
    end subroutine delete_jvp_payload

end module mlxf_transforms
