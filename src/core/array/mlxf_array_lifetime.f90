!@descr: the lifetime of an mlx_array: the defined assignment, release, kill, finalization, adoption, the handle check, the getters
submodule (mlxf_array) mlxf_array_lifetime
use, intrinsic :: iso_c_binding, only: c_intptr_t, c_null_ptr, c_associated, c_f_pointer
use mlxf_c_array,  only: mlxc_array_free, mlxc_array_ndim, mlxc_array_shape, mlxc_array_size, mlxc_array_dtype
use mlxf_error,    only: mlxf_check, mlxf_fail, mlxf_guard_thread
use mlxf_registry, only: registry_add, registry_retain, registry_release, registry_is_live
use mlxf_device,   only: mlxf_enter
implicit none

character(len=*), parameter :: STALE_MSG  = 'stale mlx_array: copied without defined assignment (an allocatable '//&
    &'component of a derived type, allocate(source=), an array intrinsic, an overlapping section assignment, or a '//&
    &'self-assignment of a derived type holding handles)'
character(len=*), parameter :: EMPTY_MSG  = 'operation on an empty mlx_array (declared, never assigned, or killed)'

contains

    integer(int64) function key_of( h )
        type(mlxc_array), intent(in) :: h
        key_of = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function key_of

    ! the defined assignment: shares the right side's MLX object and counts the reference. With a live handle on
    ! either side it updates the registry and refuses a parallel region; between empty handles it touches no
    ! shared state and runs anywhere (a derived type holding empty handles may be copied inside an OpenMP loop)
    module impure elemental subroutine assign_array( lhs, rhs )
        class(mlx_array), intent(inout) :: lhs
        class(mlx_array), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx) .or. c_associated(rhs%h%ctx) ) call mlxf_guard_thread('assignment(=)')
        if( c_associated(lhs%h%ctx, rhs%h%ctx) .and. lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(key_of(rhs%h), rhs%serial) ) call mlxf_fail('assignment(=)', STALE_MSG)
        endif
        call release(lhs)
        lhs%h      = rhs%h
        lhs%serial = rhs%serial
    end subroutine assign_array

    ! drops this reference; the last one frees the MLX object. A stale copy frees nothing (the registry
    ! counts its release).
    impure elemental subroutine release( a )
        class(mlx_array), intent(inout) :: a
        if( .not. c_associated(a%h%ctx) ) return
        if( registry_release(key_of(a%h), a%serial) ) call mlxf_check(mlxc_array_free(a%h), 'mlx_array release')
        a%h%ctx  = c_null_ptr
        a%serial = 0_int64
    end subroutine release

    ! releases this reference; on a live handle it refuses a parallel region, on an empty one it does nothing
    module impure elemental subroutine kill_array( self )
        class(mlx_array), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('kill')
        call release(self)
    end subroutine kill_array

    ! a live handle finalized inside an OpenMP region (an OpenMP private copy, made bitwise) would update the
    ! registry from several threads: it stops instead; an empty one has nothing to release
    module impure elemental subroutine finalize_array( self )
        type(mlx_array), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('finalization')
        call release(self)
    end subroutine finalize_array

    ! makes a the owner of a new MLX object h (count 1); h with a null ctx is the failure of the call made it.
    ! A failure stops, or with status returns it, a empty and h still the caller's to free (the closure
    ! trampolines take that path, since they must not stop)
    module subroutine adopt( a, h, proc, status )
        type(mlx_array),   intent(inout) :: a
        type(mlxc_array),  intent(in)    :: h
        character(len=*),  intent(in)    :: proc
        integer, optional, intent(out)   :: status
        integer(int64) :: serial
        if( present(status) ) status = 0
        if( .not. c_associated(h%ctx) )then
            call mlxf_check(1_c_int, proc, status)
            return
        endif
        call release(a)
        serial = registry_add(key_of(h), status)
        if( serial == 0_int64 ) return
        a%h      = h
        a%serial = serial
    end subroutine adopt

    ! the MLX handle of a live array: stops on an empty array or a stale copy. A check, not an entry: every
    ! caller has entered (the static rule entry holds each public procedure to it)
    module function mlxf_handle( a, proc ) result(h)
        class(mlx_array), intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
        if( .not. c_associated(a%h%ctx) ) call mlxf_fail(proc, EMPTY_MSG)
        if( .not. registry_is_live(key_of(a%h), a%serial) ) call mlxf_fail(proc, STALE_MSG)
        h = a%h
    end function mlxf_handle

    ! whether a holds a live MLX object (false when empty, or a copy made without the defined assignment)
    module logical function mlx_is_live( a )
        type(mlx_array), intent(in) :: a
        call mlxf_enter('mlx_is_live')
        mlx_is_live = .false.
        if( c_associated(a%h%ctx) ) mlx_is_live = registry_is_live(key_of(a%h), a%serial)
    end function mlx_is_live

    module function array_shape( self ) result(s)
        class(mlx_array), intent(in) :: self
        integer,        allocatable :: s(:)
        type(mlxc_array)            :: h
        integer(c_int), pointer     :: cs(:)
        integer                     :: n, i
        call mlxf_enter('shape')
        h = mlxf_handle(self, 'shape')
        n = int(mlxc_array_ndim(h))
        allocate(s(n))
        if( n == 0 ) return
        call c_f_pointer(mlxc_array_shape(h), cs, [n])
        do i = 1, n
            s(i) = int(cs(n + 1 - i))
        end do
    end function array_shape

    module integer function array_ndim( self )
        class(mlx_array), intent(in) :: self
        call mlxf_enter('ndim')
        array_ndim = int(mlxc_array_ndim(mlxf_handle(self, 'ndim')))
    end function array_ndim

    module integer(int64) function array_size( self )
        class(mlx_array), intent(in) :: self
        call mlxf_enter('size')
        array_size = int(mlxc_array_size(mlxf_handle(self, 'size')), int64)
    end function array_size

    ! the element type, one of MLX_DTYPES (mlxf_defs)
    module integer function array_kind( self )
        class(mlx_array), intent(in) :: self
        call mlxf_enter('kind')
        array_kind = int(mlxc_array_dtype(mlxf_handle(self, 'kind')))
    end function array_kind

end submodule mlxf_array_lifetime
