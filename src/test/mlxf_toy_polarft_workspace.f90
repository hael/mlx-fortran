!@descr: the polar calculator's GPU workspace (test only): one parity's resident reference tiles, the entries' graph, the shift maps
! Every MLX handle and compiled function of the toy calculator lives here: the references of one parity as
! resident tiles, and the blocks queued against them, each scored into one entry (distance, rotation) per pair
! with the rotation drawn from the pair's posterior on the device. The calculator owns the host memos and hands
! them in; a block that does not match the tiles is refused before anything is queued. Written against mlxf as
! a user writes; lifecycle, scoring and the shift maps are submodules.
module mlxf_toy_polarft_workspace
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,           only: mlx_array, mlx_function
use mlxf_test_defs, only: NSHIFTMAPS, polarft_tile_spec, polarft_block_spec, polarft_map_spec, polarft_map_block, &
                          polar_map_results
implicit none

public :: polarft_workspace
private

! the slots a caller may have in flight: one scored synchronously, or two overlapped
integer, parameter :: POLARFT_NSLOTS = 2

! the graph of one submitted block, until it is collected: its entries padded to (rpad, bpad)
type :: polarft_workspace_slot
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
end type polarft_workspace_slot

! one shift map's grid and resident data: the references' full-ring spectra over the band in rfull (nkb, nrots,
! nrefs) and their squared-modulus memos (pftsz+1, nkb, nrefs), the real Bessel weights of every order in wfold
! (nkb, 1, norder+1, nrho, 1, 1), the phase of each order's shift per rotation in ffold (1, norder+1, 1, nrots,
! 1), the band's weights (1, nkb, 1), the cells' shift components and squared radius, the radii and the area of
! one cell per radius, and the compiled selection (mode, loss) and separate reductions (width, evidence) of a
! tile's maps
type :: polarft_workspace_map
    logical                   :: ready  = .false.
    integer                   :: pftsz  = 0
    integer                   :: nrots  = 0
    integer                   :: nrefs  = 0
    integer                   :: nkb    = 0
    integer                   :: nrho   = 0
    integer                   :: nalpha = 0
    integer                   :: norder = 0
    real(real64), allocatable :: rho(:)
    real(real64), allocatable :: area(:)
    integer,      allocatable :: nharm(:)
    type(mlx_array)           :: rfull
    type(mlx_array)           :: ref2b
    type(mlx_array)           :: wfold
    type(mlx_array)           :: ffold
    type(mlx_array)           :: wband
    type(mlx_array)           :: cellx
    type(mlx_array)           :: celly
    type(mlx_array)           :: cellr2
    type(mlx_function)        :: map_select
    type(mlx_function)        :: map_reduce
    type(mlx_function)        :: map_evidence
end type polarft_workspace_map

! the workspace of one parity: refs holds the reference tiles (4nk, 2rt, pftsz+1, ntiles) real: a tile G of every
! bin, rows 1..nk ft_ref2 and rows nk+1..2nk conj(ft_ref), packed as [[Re G, Im G], [-Im G, Re G]], so that a
! tile's complex sums of every bin are one real product; tail the compiled distances and draw; stage_s the
! profiled stages' seconds: particle terms, products, inverse transform, distances and draw, concatenation;
! rows_host the full rows of the last block collected with them; maps the shift maps, and mstage_s their
! profiled seconds: construction, mode, width, copy-out
type :: polarft_workspace
    private
    logical                       :: prepared   = .false.
    integer                       :: pftsz      = 0
    integer                       :: nk         = 0
    integer                       :: nrots      = 0
    integer                       :: rt         = 0
    integer                       :: bt         = 0
    integer                       :: nrefs      = 0
    integer                       :: ntiles     = 0
    real(real64)                  :: stage_s(5) = 0._real64
    real(real64)                  :: mstage_s(4) = 0._real64
    type(polarft_workspace_map)   :: maps(NSHIFTMAPS)
    real(real32),     allocatable :: rows_host(:,:,:)
    type(mlx_array)               :: refs
    type(mlx_function)            :: tail
    type(polarft_workspace_slot)  :: slots(POLARFT_NSLOTS)
    character(len=:), allocatable :: msg
  contains
    procedure :: new           => polarft_workspace_new
    procedure :: kill          => polarft_workspace_kill
    procedure :: submit        => polarft_workspace_submit
    procedure :: collect       => polarft_workspace_collect
    procedure :: take_rows
    procedure :: message
    procedure :: stage_seconds
    procedure :: prepare_maps  => polarft_workspace_prepare_maps
    procedure :: score_maps    => polarft_workspace_score_maps
    procedure :: kill_map      => polarft_workspace_drop_map
    procedure :: kill_maps
    procedure :: map_order
    procedure :: map_term_counts
    procedure :: map_seconds
    final     :: polarft_workspace_final
end type polarft_workspace

interface
    ! the resident tiles of one parity's reference memos (pftsz+1, nk, references) under the tile plan of spec
    ! (validated first; a failure leaves the workspace unprepared)
    module subroutine polarft_workspace_new( self, spec, ft_ref, ft_ref2, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_tile_spec),  intent(in)    :: spec
        complex(real32),          intent(in)    :: ft_ref(:,:,:), ft_ref2(:,:,:)
        integer,                  intent(out)   :: status
    end subroutine polarft_workspace_new

    ! idempotent teardown: tiles, pending slots and the record of the preparation
    module subroutine polarft_workspace_kill( self )
        class(polarft_workspace), intent(inout) :: self
    end subroutine polarft_workspace_kill

    module subroutine polarft_workspace_final( self )
        type(polarft_workspace), intent(inout) :: self
    end subroutine polarft_workspace_final

    ! the reason of the last refusal or failure
    pure module function message( self ) result(msg)
        class(polarft_workspace), intent(in) :: self
        character(len=:), allocatable :: msg
    end function message

    ! the compiled tail's callback: (raw rows, 1/(2 wsq), inverse temperatures, variates) to (rows, distances,
    ! rotations); a separate module procedure, since the preparation compiles what the scoring defines
    module subroutine polar_tail_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
    end subroutine polar_tail_callback

    ! the profiled stages' accumulated seconds (see stage_s)
    pure module function stage_seconds( self ) result(t)
        class(polarft_workspace), intent(in) :: self
        real(real64) :: t(5)
    end function stage_seconds

    ! validates a block against the tiles and queues its graph in the block's slot (1 or 2); the particles'
    ! memos (pftsz+1, nk, particles of the batch) are read at the block's batch slots; nothing is queued on a
    ! refusal (status /= 0)
    module subroutine polarft_workspace_submit( self, blk, ft_ctf2, ft_ptcl_ctf, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_block_spec), intent(in)    :: blk
        complex(real32),          intent(in)    :: ft_ctf2(:,:,:), ft_ptcl_ctf(:,:,:)
        integer,                  intent(out)   :: status
    end subroutine polarft_workspace_submit

    ! waits for slot's block and copies its entries into dists and irots (references, particles of the block),
    ! which a refusal leaves as they are; the slot is free afterwards
    module subroutine polarft_workspace_collect( self, slot, dists, irots, status )
        class(polarft_workspace), intent(inout) :: self
        integer,                  intent(in)    :: slot
        real(real32),             intent(inout) :: dists(:,:)
        integer,                  intent(inout) :: irots(:,:)
        integer,                  intent(out)   :: status
    end subroutine polarft_workspace_collect

    ! hands over the full rows (rotations, references, particles) of the last block collected with rows; rows is
    ! left unallocated when there are none
    module subroutine take_rows( self, rows )
        class(polarft_workspace),  intent(inout) :: self
        real(real32), allocatable, intent(out)   :: rows(:,:,:)
    end subroutine take_rows

    ! map spec%imap's grid and resident data from one parity's reference memos; the map's earlier state is
    ! dropped first, so a refusal or failure leaves no such map, the others and the scoring intact
    module subroutine polarft_workspace_prepare_maps( self, spec, ft_ref, ft_ref2, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_map_spec),   intent(in)    :: spec
        complex(real32),          intent(in)    :: ft_ref(:,:,:), ft_ref2(:,:,:)
        integer,                  intent(out)   :: status
    end subroutine polarft_workspace_prepare_maps

    ! drops one map's resident data and grid; the preparation, a failed one and the teardown call it
    module subroutine polarft_workspace_drop_map( self, imap )
        class(polarft_workspace), intent(inout) :: self
        integer,                  intent(in)    :: imap
    end subroutine polarft_workspace_drop_map

    ! drops every map
    module subroutine kill_maps( self )
        class(polarft_workspace), intent(inout) :: self
    end subroutine kill_maps

    ! the shift maps of a block's candidate pairs, reduced on the device to their modes, widths and optional
    ! evidence; the particles' memos are read at the block's batch slots; a refusal or failure leaves its
    ! reason in message(), which is empty otherwise
    module subroutine polarft_workspace_score_maps( self, mblk, ft_ctf2, ft_ptcl_ctf, res )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_map_block),  intent(in)    :: mblk
        complex(real32),          intent(in)    :: ft_ctf2(:,:,:), ft_ptcl_ctf(:,:,:)
        type(polar_map_results),  intent(out)   :: res
    end subroutine polarft_workspace_score_maps

    ! the Bessel orders 0..map_order(imap) the map keeps
    pure module integer function map_order( self, imap )
        class(polarft_workspace), intent(in) :: self
        integer,                  intent(in) :: imap
    end function map_order

    ! the radius-order terms of a map's contraction: those the truncation keeps, and those executed (every
    ! radius padded to the largest order)
    pure module function map_term_counts( self, imap ) result(counts)
        class(polarft_workspace), intent(in) :: self
        integer,                  intent(in) :: imap
        integer(int64) :: counts(2)
    end function map_term_counts

    ! the profiled map stages' accumulated seconds (see mstage_s)
    pure module function map_seconds( self ) result(t)
        class(polarft_workspace), intent(in) :: self
        real(real64) :: t(4)
    end function map_seconds
end interface

end module mlxf_toy_polarft_workspace
