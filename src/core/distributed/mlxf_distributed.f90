!@descr: distributed computing: a group of processes behind a counted handle, and the collectives and messages between its members
! A group is made by mlx_distributed_init from what launched the processes (MLX's ring or JACCL backends, MPI
! where MLX was built with it); a process launched alone gets a group of one. Ranks are one-based here, as every
! position; MLX's are zero-based. The operations are nodes of the graph: the exchange happens at evaluation.
module mlxf_distributed
use, intrinsic :: iso_c_binding,   only: c_int, c_bool, c_intptr_t, c_null_ptr, c_null_char, c_associated
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,             only: mlxc_distributed_group
use mlxf_c_distributed,       only: mlxc_distributed_all_sum, mlxc_distributed_all_max, mlxc_distributed_all_min, &
                                    mlxc_distributed_all_gather, mlxc_distributed_sum_scatter, mlxc_distributed_send, &
                                    mlxc_distributed_recv, mlxc_distributed_recv_like
use mlxf_c_distributed_group, only: mlxc_distributed_group_new, mlxc_distributed_group_free, mlxc_distributed_init, &
                                    mlxc_distributed_group_get_rank, mlxc_distributed_group_get_size, &
                                    mlxc_distributed_group_split, mlxc_distributed_is_available
use mlxf_defs,                only: MLX_DTYPES, mlxf_group_spec
use mlxf_array,               only: mlx_array, mlxf_group_op, mlxf_group_peer_op, mlxf_group_recv_op
use mlxf_device,              only: mlxf_enter, mlxf_require_device
use mlxf_error,               only: mlxf_check, mlxf_fail, mlxf_report, mlxf_guard_thread
use mlxf_registry,            only: registry_add, registry_retain, registry_release, registry_is_live
implicit none
public :: mlx_group, mlx_distributed_init, mlx_distributed_is_available, mlx_all_sum, mlx_all_max, mlx_all_min, &
    &mlx_all_gather, mlx_sum_scatter, mlx_send, mlx_recv, mlx_recv_like
private

type :: mlx_group
    private
    type(mlxc_distributed_group) :: h
    integer(int64)               :: serial = 0_int64
  contains
    procedure          :: rank => group_rank
    procedure          :: size => group_size
    procedure          :: split => group_split
    procedure          :: kill => group_kill
    procedure, private :: group_assign
    generic            :: assignment(=) => group_assign
    final              :: group_final
end type mlx_group

contains

    ! the group of the processes this one was launched with, through backend ('any', the default, 'ring', 'jaccl',
    ! 'mpi', 'nccl'). Without strict, a process no backend launched gets a group of one; with it, that is a
    ! failure. With status, a failure returns an empty group
    function mlx_distributed_init( backend, strict, status ) result(g)
        character(len=*),  optional, intent(in) :: backend
        logical,           optional, intent(in) :: strict
        integer, optional, intent(out)          :: status
        type(mlx_group)               :: g
        character(len=:), allocatable :: name
        logical(c_bool)               :: must
        integer(c_int)                :: ierr
        call mlxf_require_device('mlx_distributed_init')
        name = 'any'
        if( present(backend) ) name = trim(backend)
        must = .false._c_bool
        if( present(strict) ) must = logical(strict, c_bool)
        g%h = mlxc_distributed_group_new()
        ierr = mlxc_distributed_init(g%h, must, name//c_null_char)
        if( ierr == 0 .and. .not. c_associated(g%h%ctx) ) ierr = 1_c_int
        if( ierr /= 0 )then
            if( c_associated(g%h%ctx) ) call mlxf_check(mlxc_distributed_group_free(g%h), 'mlx_distributed_init cleanup')
            g%h%ctx = c_null_ptr
            call mlxf_check(ierr, 'mlx_distributed_init', status)
            return
        endif
        if( present(status) ) status = 0
        g%serial = registry_add(group_key(g%h))
    end function mlx_distributed_init

    ! whether MLX has a distributed backend ('any', the default: whether it has one at all)
    logical function mlx_distributed_is_available( backend )
        character(len=*), optional, intent(in) :: backend
        character(len=:), allocatable :: name
        call mlxf_enter('mlx_distributed_is_available')
        name = 'any'
        if( present(backend) ) name = trim(backend)
        mlx_distributed_is_available = logical(mlxc_distributed_is_available(name//c_null_char))
    end function mlx_distributed_is_available

    ! this process's rank in the group, from 1 to its size
    integer function group_rank( self ) result(rank)
        class(mlx_group), intent(in) :: self
        integer(c_int) :: r
        call mlxf_enter('mlx_group rank')
        call require_group(self, 'mlx_group rank')
        r = 0
        call mlxf_check(mlxc_distributed_group_get_rank(r, self%h), 'mlx_group rank')
        rank = int(r)+1
    end function group_rank

    ! the number of processes in the group
    integer function group_size( self ) result(n)
        class(mlx_group), intent(in) :: self
        integer(c_int) :: r
        call mlxf_enter('mlx_group size')
        call require_group(self, 'mlx_group size')
        r = 0
        call mlxf_check(mlxc_distributed_group_get_size(r, self%h), 'mlx_group size')
        n = int(r)
    end function group_size

    ! the sub-group of the processes that give the same color, ordered by key (absent: by their rank here); with
    ! status, a failure (a group that cannot be split, as a group of one) returns an empty group
    function group_split( self, color, key, status ) result(g)
        class(mlx_group),  intent(in)           :: self
        integer,           intent(in)           :: color
        integer,           optional, intent(in) :: key
        integer, optional, intent(out)          :: status
        type(mlx_group) :: g
        integer(c_int)  :: ierr, order
        call mlxf_require_device('mlx_group split')
        call require_group(self, 'mlx_group split')
        order = -1_c_int
        if( present(key) ) order = int(key, c_int)
        g%h = mlxc_distributed_group_new()
        ierr = mlxc_distributed_group_split(g%h, self%h, int(color, c_int), order)
        if( ierr == 0 .and. .not. c_associated(g%h%ctx) ) ierr = 1_c_int
        if( ierr /= 0 )then
            if( c_associated(g%h%ctx) ) call mlxf_check(mlxc_distributed_group_free(g%h), 'mlx_group split cleanup')
            g%h%ctx = c_null_ptr
            call mlxf_check(ierr, 'mlx_group split', status)
            return
        endif
        if( present(status) ) status = 0
        g%serial = registry_add(group_key(g%h))
    end function group_split

    ! the sum of x over the processes of the group (MLX's default group when none is given), on each of them
    function mlx_all_sum( x, group, status ) result(r)
        type(mlx_array),   intent(in)           :: x
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array) :: r
        call mlxf_require_device('mlx_all_sum')
        call mlxf_group_op(r, mlxc_distributed_all_sum, x, peer_spec('mlx_all_sum', 1, group), status)
    end function mlx_all_sum

    ! the elementwise maximum of x over the processes of the group
    function mlx_all_max( x, group, status ) result(r)
        type(mlx_array),   intent(in)           :: x
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array) :: r
        call mlxf_require_device('mlx_all_max')
        call mlxf_group_op(r, mlxc_distributed_all_max, x, peer_spec('mlx_all_max', 1, group), status)
    end function mlx_all_max

    ! the elementwise minimum of x over the processes of the group
    function mlx_all_min( x, group, status ) result(r)
        type(mlx_array),   intent(in)           :: x
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array) :: r
        call mlxf_require_device('mlx_all_min')
        call mlxf_group_op(r, mlxc_distributed_all_min, x, peer_spec('mlx_all_min', 1, group), status)
    end function mlx_all_min

    ! the x of every process joined along the last dimension (MLX's first axis), in the order of the ranks
    function mlx_all_gather( x, group, status ) result(r)
        type(mlx_array),   intent(in)           :: x
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array) :: r
        call mlxf_require_device('mlx_all_gather')
        call mlxf_group_op(r, mlxc_distributed_all_gather, x, peer_spec('mlx_all_gather', 1, group), status)
    end function mlx_all_gather

    ! the sum of x over the processes, of which each keeps its own share along the last dimension
    function mlx_sum_scatter( x, group, status ) result(r)
        type(mlx_array),   intent(in)           :: x
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array) :: r
        call mlxf_require_device('mlx_sum_scatter')
        call mlxf_group_op(r, mlxc_distributed_sum_scatter, x, peer_spec('mlx_sum_scatter', 1, group), status)
    end function mlx_sum_scatter

    ! x, sent to the process of rank dst (one-based) when the result is evaluated; the result is x
    function mlx_send( x, dst, group, status ) result(r)
        type(mlx_array),   intent(in)           :: x
        integer,           intent(in)           :: dst
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array) :: r
        call mlxf_require_device('mlx_send')
        call mlxf_group_peer_op(r, mlxc_distributed_send, x, peer_spec('mlx_send', dst, group), status)
    end function mlx_send

    ! an array of the Fortran shape and the dtype given, received from the process of rank src (one-based)
    function mlx_recv( shape, dtype, src, group, status ) result(r)
        integer,           intent(in)           :: shape(:), dtype, src
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array)       :: r
        type(mlxf_group_spec) :: spec
        call mlxf_require_device('mlx_recv')
        spec = peer_spec('mlx_recv', src, group)
        spec%shape = shape
        spec%dtype = dtype
        call mlxf_group_recv_op(r, mlxc_distributed_recv, spec, status)
    end function mlx_recv

    ! an array of x's shape and dtype, received from the process of rank src (one-based)
    function mlx_recv_like( x, src, group, status ) result(r)
        type(mlx_array),   intent(in)           :: x
        integer,           intent(in)           :: src
        type(mlx_group),   optional, intent(in) :: group
        integer, optional, intent(out)          :: status
        type(mlx_array) :: r
        call mlxf_require_device('mlx_recv_like')
        call mlxf_group_peer_op(r, mlxc_distributed_recv_like, x, peer_spec('mlx_recv_like', src, group), status)
    end function mlx_recv_like

    ! what a distributed operation hands its helper: the group's handle (null without a group: MLX's default
    ! group), the peer's rank made zero-based, and the procedure's name. A group that is given must be live, and
    ! a rank below 1 stops (MLX would take 0 for the first)
    function peer_spec( proc, rank, group ) result(spec)
        character(len=*), intent(in)           :: proc
        integer,          intent(in)           :: rank
        type(mlx_group),  optional, intent(in) :: group
        type(mlxf_group_spec) :: spec
        spec%proc = proc
        spec%dtype = MLX_DTYPES%float32
        if( rank < 1 ) call mlxf_fail(proc, 'a rank is one-based')
        spec%peer = rank-1
        spec%group%ctx = c_null_ptr
        if( present(group) )then
            call require_group(group, proc)
            spec%group = group%h
        endif
    end function peer_spec

    ! a counted copy of the handle; the thread guard runs only when a live handle is involved
    impure elemental subroutine group_assign( lhs, rhs )
        class(mlx_group), intent(inout) :: lhs
        class(mlx_group), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx).or.c_associated(rhs%h%ctx) ) call mlxf_guard_thread('mlx_group assignment')
        if( c_associated(lhs%h%ctx, rhs%h%ctx).and.lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(group_key(rhs%h), rhs%serial) ) &
                &call mlxf_fail('mlx_group assignment', 'stale group copy')
        endif
        call group_release(lhs)
        lhs%h = rhs%h
        lhs%serial = rhs%serial
    end subroutine group_assign

    ! releases the handle; idempotent, and without the thread guard for an empty one
    impure elemental subroutine group_kill( self )
        class(mlx_group), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('mlx_group kill')
        call group_release(self)
    end subroutine group_kill

    ! finalization releases as kill does
    impure elemental subroutine group_final( self )
        type(mlx_group), intent(inout) :: self
        call self%kill()
    end subroutine group_final

    ! drops one count, the last freeing the mlx-c group; the handle is empty afterwards
    impure elemental subroutine group_release( self )
        class(mlx_group), intent(inout) :: self
        if( .not. c_associated(self%h%ctx) ) return
        if( registry_release(group_key(self%h), self%serial) ) &
            &call mlxf_check(mlxc_distributed_group_free(self%h), 'mlx_group release')
        self%h%ctx = c_null_ptr
        self%serial = 0_int64
    end subroutine group_release

    ! stops unless g holds a live group
    subroutine require_group( g, proc )
        class(mlx_group), intent(in) :: g
        character(len=*), intent(in) :: proc
        if( .not. c_associated(g%h%ctx) ) call mlxf_fail(proc, 'empty mlx_group')
        if( .not. registry_is_live(group_key(g%h), g%serial) ) call mlxf_fail(proc, 'stale mlx_group')
    end subroutine require_group

    ! the registry's key of a group: its context address
    integer(int64) function group_key( h ) result(key)
        type(mlxc_distributed_group), intent(in) :: h
        key = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function group_key

end module mlxf_distributed
