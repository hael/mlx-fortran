!@descr: the polar table's GPU scoring workspace (test only): prepared references, validated specs, the entries' graph
! A model of the workspace SIMPLE's polar calculator would own: one half's references prepared once as resident
! tiles with their generation, half, shape and ordered global IDs; particle blocks scored against them into one
! entry (distance, rotation) per pair, the rotation drawn from each pair's posterior on the device. A block that
! does not match the preparation is refused before scoring. Written against mlxf as a user writes; lifecycle and
! scoring are submodules.
module mlxf_kernel_polar_table
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,           only: mlx_array, mlx_function
use mlxf_test_defs, only: polar_table_refs, polar_table_block, polar_table_entries, polar_map_spec, polar_map_block, &
                          polar_map_results
implicit none

public :: polar_table
private

! the slots a caller may have in flight: one scored synchronously, or two overlapped
integer, parameter :: POLAR_TABLE_NSLOTS = 2

! the graph of one submitted block, until it is collected: its entries padded to (rpad, bpad)
type :: polar_table_slot
    logical         :: busy   = .false.
    logical         :: l_rows = .false.
    integer         :: nrefs  = 0
    integer         :: nptcls = 0
    integer         :: nrots  = 0
    integer         :: rpad   = 0
    integer         :: bpad   = 0
    type(mlx_array) :: dists
    type(mlx_array) :: irots
    type(mlx_array) :: rows
end type polar_table_slot

! the workspace of one half: refs holds the reference tiles (4nk, 2rt, pftsz+1, ntiles) real: a tile G of every
! bin, rows 1..nk ft_ref2 and rows nk+1..2nk conj(ft_ref), packed as [[Re G, Im G], [-Im G, Re G]], so that a
! tile's complex sums of every bin are one real product; tail the compiled distances and draw; stage_s the
! profiled stages' seconds: particle terms, products, inverse transform, distances and draw, concatenation
type :: polar_table
    private
    logical                       :: prepared   = .false.
    integer                       :: pftsz      = 0
    integer                       :: nk         = 0
    integer                       :: nrots      = 0
    integer                       :: half       = 0
    integer                       :: rt         = 0
    integer                       :: bt         = 0
    integer                       :: nrefs      = 0
    integer                       :: ntiles     = 0
    integer(int64)                :: generation = -1_int64
    real(real64)                  :: stage_s(5) = 0._real64
    ! the shift maps' grid and resident data: the references' full-ring spectra over the band in rfull (nkb,
    ! nrots, nrefs) and their squared-modulus memos (pftsz+1, nkb, nrefs), the real Bessel weights of every
    ! order in wfold (nkb, 1, norder+1, nrho, 1, 1), the phase of each order's shift per rotation in ffold
    ! (1, norder+1, 1, nrots, 1), the band's weights (1, nkb, 1), the compiled selection (mode, loss) and
    ! separate reductions (width and optional evidence) of a tile's maps, the cells' shift components and the prior
    ! with the log area (nalpha, 1, nrho); mstage_s the profiled seconds: construction, mode, width, copy-out
    logical                       :: maps_ready  = .false.
    integer                       :: map_nkb     = 0
    integer                       :: map_nrho    = 0
    integer                       :: map_nalpha  = 0
    integer                       :: map_norder  = 0
    real(real64)                  :: map_lse_prior = 0._real64
    real(real64)                  :: mstage_s(4) = 0._real64
    real(real64),     allocatable :: map_rho(:)
    integer,          allocatable :: map_nharm(:)
    type(mlx_array)               :: rfull
    type(mlx_array)               :: ref2b
    type(mlx_array)               :: wfold
    type(mlx_array)               :: ffold
    type(mlx_array)               :: wband
    type(mlx_array)               :: cellx
    type(mlx_array)               :: celly
    type(mlx_array)               :: cellr2
    type(mlx_array)               :: cellprior
    type(mlx_function)            :: map_select
    type(mlx_function)            :: map_reduce
    type(mlx_function)            :: map_evidence
    integer,          allocatable :: ids(:)
    type(mlx_array)               :: refs
    type(mlx_function)            :: tail
    type(polar_table_slot)        :: slots(POLAR_TABLE_NSLOTS)
    character(len=:), allocatable :: msg
  contains
    procedure :: new        => polar_table_new
    procedure :: invalidate => polar_table_invalidate
    procedure :: kill       => polar_table_kill
    procedure :: submit     => polar_table_submit
    procedure :: collect    => polar_table_collect
    procedure :: score      => polar_table_score
    procedure :: prepared_now
    procedure :: message
    procedure :: stage_seconds
    procedure :: prepare_maps  => polar_table_prepare_maps
    procedure :: score_maps    => polar_table_score_maps
    procedure :: map_order
    procedure :: map_term_counts
    procedure :: map_seconds
    final     :: polar_table_final
end type polar_table

interface
    ! prepares the references of one half (validated first; a failure leaves the workspace unprepared)
    module subroutine polar_table_new( self, refs, status )
        class(polar_table),     intent(inout) :: self
        type(polar_table_refs), intent(in)    :: refs
        integer,                intent(out)   :: status
    end subroutine polar_table_new

    ! the references changed: drop them; scoring is refused until the next new
    module subroutine polar_table_invalidate( self )
        class(polar_table), intent(inout) :: self
    end subroutine polar_table_invalidate

    ! idempotent teardown: references, pending slots and the record of the preparation
    module subroutine polar_table_kill( self )
        class(polar_table), intent(inout) :: self
    end subroutine polar_table_kill

    module subroutine polar_table_final( self )
        type(polar_table), intent(inout) :: self
    end subroutine polar_table_final

    ! drops the shift maps' resident data and grid (they belong to the references); the lifecycle and every
    ! failed preparation of the maps call it
    module subroutine polar_table_drop_maps( self )
        class(polar_table), intent(inout) :: self
    end subroutine polar_table_drop_maps

    pure module logical function prepared_now( self )
        class(polar_table), intent(in) :: self
    end function prepared_now

    ! the reason of the last refusal or failure
    pure module function message( self ) result(msg)
        class(polar_table), intent(in) :: self
        character(len=:), allocatable :: msg
    end function message

    ! the compiled tail's callback: (raw rows, 1/(2 wsq), inverse temperatures, variates) to (rows, distances,
    ! rotations); a separate module procedure, since the preparation compiles what the scoring defines
    module subroutine polar_tail_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
    end subroutine polar_tail_callback

    ! the shift maps' grid and resident data for the prepared references, whose memos refs holds again (its
    ! IDs, generation, geometry and memo shapes must be the prepared ones); any earlier maps are dropped first,
    ! so a refusal or failure leaves the maps unprepared, the scoring intact
    module subroutine polar_table_prepare_maps( self, refs, spec, status )
        class(polar_table),     intent(inout) :: self
        type(polar_table_refs), intent(in)    :: refs
        type(polar_map_spec),   intent(in)    :: spec
        integer,                intent(out)   :: status
    end subroutine polar_table_prepare_maps

    ! the shift maps of a block's candidate pairs, reduced on the device to their modes, widths and optional
    ! evidence; refused (status /= 0) when the block does not match the preparation
    module subroutine polar_table_score_maps( self, mblk, res, status )
        class(polar_table),      intent(inout) :: self
        type(polar_map_block),   intent(in)    :: mblk
        type(polar_map_results), intent(out)   :: res
        integer,                 intent(out)   :: status
    end subroutine polar_table_score_maps

    ! the Bessel orders 0..map_order() the prepared maps keep
    pure module integer function map_order( self )
        class(polar_table), intent(in) :: self
    end function map_order

    ! the radius-order terms of a map's contraction: those the truncation keeps, and those executed (every
    ! radius padded to the largest order)
    pure module function map_term_counts( self ) result(counts)
        class(polar_table), intent(in) :: self
        integer(int64) :: counts(2)
    end function map_term_counts

    ! the profiled map stages' accumulated seconds (see mstage_s)
    pure module function map_seconds( self ) result(t)
        class(polar_table), intent(in) :: self
        real(real64) :: t(4)
    end function map_seconds

    ! the profiled stages' accumulated seconds (see stage_s)
    pure module function stage_seconds( self ) result(t)
        class(polar_table), intent(in) :: self
        real(real64) :: t(5)
    end function stage_seconds

    ! validates a block against the preparation and queues its graph in slot (1 or 2); nothing is queued on a
    ! refusal (status /= 0)
    module subroutine polar_table_submit( self, blk, slot, status )
        class(polar_table),      intent(inout) :: self
        type(polar_table_block), intent(in)    :: blk
        integer,                 intent(in)    :: slot
        integer,                 intent(out)   :: status
    end subroutine polar_table_submit

    ! waits for slot's block and copies its entries out; the slot is free afterwards
    module subroutine polar_table_collect( self, slot, entries, status )
        class(polar_table),        intent(inout) :: self
        integer,                   intent(in)    :: slot
        type(polar_table_entries), intent(out)   :: entries
        integer,                   intent(out)   :: status
    end subroutine polar_table_collect

    ! a block scored synchronously: submit to the first slot, then collect it
    module subroutine polar_table_score( self, blk, entries, status )
        class(polar_table),        intent(inout) :: self
        type(polar_table_block),   intent(in)    :: blk
        type(polar_table_entries), intent(out)   :: entries
        integer,                   intent(out)   :: status
    end subroutine polar_table_score
end interface

end module mlxf_kernel_polar_table
