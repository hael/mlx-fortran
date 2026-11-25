!@descr: the toy polar calculator (test only): a miniature of SIMPLE's polarft_calc with its GPU workspace as one component
! The type, its procedures and their dummy arguments carry SIMPLE's names; scripts/toy_mirror.txt lists each
! as mirrored or as an addition with its reason. The host side is SIMPLE's: references and particles are set one
! at a time in SIMPLE's shapes, memoized into the transforms the scorer reads, and scored in blocks of one
! half. All MLX state sits in ws, one workspace per reference parity, created in new and released in kill.
! Core, memoization, block scoring and the shift maps are submodules, as in SIMPLE.
module mlxf_toy_polarft_calc
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_test_defs,             only: POLAR_CANON_BT, POLAR_CANON_RT, POLARFT_STAGE_N, NSHIFTMAPS, parameters
use mlxf_toy_polarft_workspace, only: polarft_workspace
implicit none

public :: polarft_calc
private

! the reference parities, and the slots a caller may have in flight
integer, parameter :: REF_EVEN       = 1
integer, parameter :: REF_ODD        = 2
integer, parameter :: N_REF_PARITIES = 2
integer, parameter :: NSLOTS         = 2

! SIMPLE's members under SIMPLE's names, for the members the toy has. pfts_refs, pfts_ptcls and ctfmats are
! staging of POLARFT_STAGE_N sections: they hold what the setters were given (stage_ref: the reference and its
! parity; stage_ptcl: the batch slot; l_stage_pft: the section came) until the staging fills or the next
! memoization, which turns them into memos. The memos are those of the scorer: ft_ref and ft_ref2 per parity,
! ft_ptcl_ctf and ft_ctf2 per particle of the batch; dft_e holds the transform's factors. The rest serves the
! additions: the tile plan, the options, variates, seed banks and rows of a block, the parity of the block in
! each slot, the reason of the last refusal. Of the shift maps the calculator keeps what tells whether a map
! is that of the memoized references and weights (map_ref_gen, map_wk_gen), its band's last shell, the pairs
! gen_shiftmap was given (sm_*), the options and the requested outputs of the last modes.
type :: polarft_calc
    private
    integer                              :: nptcls     = 1
    integer                              :: nrefs      = 1
    integer                              :: nrots      = 0
    integer                              :: pftsz      = 0
    integer                              :: pfromto(2) = 0
    integer                              :: kfromto(2) = 0
    integer                              :: nk         = 0
    integer                              :: ldim(3)    = 0
    integer,                 allocatable :: pinds(:)
    logical,                 allocatable :: iseven(:)
    real(real64),            allocatable :: wsqsums_ptcls(:)
    real(real64),            allocatable :: kshell_sqsums_ptcls(:,:)
    real(real32),            allocatable :: sigma2_wk(:,:)
    real(real64),            allocatable :: sigma2_wk8(:,:)
    real(real32),            allocatable :: ctfmats(:,:,:)
    complex(real64),         allocatable :: pfts_refs(:,:,:)
    complex(real32),         allocatable :: pfts_ptcls(:,:,:)
    complex(real32),         allocatable :: ft_ptcl_ctf(:,:,:)
    complex(real32),         allocatable :: ft_ctf2(:,:,:)
    complex(real32),         allocatable :: ft_ref(:,:,:,:)
    complex(real32),         allocatable :: ft_ref2(:,:,:,:)
    integer(int64)                       :: ref_gen       = 0_int64
    integer(int64)                       :: ref_gen_bins  = -1_int64
    integer(int64)                       :: ptcl_gen      = 0_int64
    integer(int64)                       :: ptcl_gen_memo = -1_int64
    logical                              :: existence     = .false.
    integer                              :: nref_staged      = 0
    integer                              :: nptcl_staged     = 0
    integer                              :: stage_ref(2, POLARFT_STAGE_N) = 0
    integer                              :: stage_ptcl(POLARFT_STAGE_N)  = 0
    logical                              :: l_stage_pft(POLARFT_STAGE_N) = .false.
    logical                              :: l_refs_pending   = .false.
    logical,                 allocatable :: l_ptcl_set(:)
    complex(real64),         allocatable :: dft_e(:,:)
    logical                              :: l_weights        = .false.
    integer                              :: bt               = POLAR_CANON_BT
    integer                              :: rt               = POLAR_CANON_RT
    logical                              :: l_rows           = .false.
    logical                              :: l_profile        = .false.
    integer                              :: slot_ieo(NSLOTS) = 0
    real(real32),            allocatable :: u_next(:,:)
    complex(real32),         allocatable :: banks_next(:,:,:)
    logical,                 allocatable :: l_bank_next(:)
    real(real32),            allocatable :: rows(:,:,:)
    integer(int64)                       :: wk_gen                  = 0_int64
    integer(int64)                       :: map_ref_gen(NSHIFTMAPS) = -1_int64
    integer(int64)                       :: map_wk_gen(NSHIFTMAPS)  = -1_int64
    integer                              :: map_kstop(NSHIFTMAPS)   = 0
    integer                              :: sm_imap                 = 0
    integer                              :: sm_ieo                  = 0
    integer,                 allocatable :: sm_islots(:)
    integer,                 allocatable :: sm_cands(:,:)
    integer                              :: sm_ptcl_tile            = 16
    logical                              :: sm_l_maps               = .false.
    logical                              :: sm_l_evidence           = .false.
    logical                              :: sm_l_profile            = .false.
    real(real32),            allocatable :: sm_logz(:,:)
    real(real32),            allocatable :: sm_maps(:,:,:,:,:)
    character(len=:),        allocatable :: msg
    type(polarft_workspace), allocatable :: ws(:)
  contains
    ! core
    procedure :: new
    procedure :: kill
    procedure :: set_eo
    procedure :: set_sigma2_weights
    procedure :: set_tile_plan
    procedure :: message
    procedure :: get_nrefs
    procedure :: get_pftsz
    procedure :: ptcl_iseven
    ! memoization
    procedure :: reallocate_ptcls
    procedure :: set_ref_pft
    procedure :: set_ptcl_pft
    procedure :: set_ptcl_ctfmat
    procedure :: memoize_refs
    procedure :: memoize_ptcls
    procedure :: memoize_ref_bins
    procedure :: kill_ref_bins
    procedure :: ref_bins_current
    ! block scoring
    procedure :: score_block_posterior
    procedure :: set_block_variates
    procedure :: set_block_banks
    procedure :: set_block_options
    procedure :: submit_block
    procedure :: collect_block
    procedure :: block_rows
    procedure :: stage_seconds
    ! shift maps
    procedure :: new_shiftmap
    procedure :: setup_shiftmaps
    procedure :: kill_shiftmap
    procedure :: gen_shiftmap
    procedure :: shiftmap_mode
    procedure :: set_shiftmap_options
    procedure :: shiftmap_evidence
    procedure :: shiftmap_maps
    procedure :: wsqsum_ptcl_band
    procedure :: shiftmap_kstop
    procedure :: shiftmap_order
    procedure :: shiftmap_term_counts
    procedure :: shiftmap_seconds
    final     :: polarft_calc_final
end type polarft_calc

interface
    ! ---- core ----

    ! a calculator of nrefs references per parity and the particles pfromto(1)..pfromto(2), over the shells
    ! kfromto(1)..kfromto(2); a refusal (message) leaves it not existing
    module subroutine new( self, params, nrefs, pfromto, kfromto )
        class(polarft_calc), intent(inout) :: self
        type(parameters),    intent(in)    :: params
        integer,             intent(in)    :: nrefs
        integer,             intent(in)    :: pfromto(2), kfromto(2)
    end subroutine new

    ! idempotent teardown: the workspaces first, then every host array
    module subroutine kill( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine kill

    module subroutine polarft_calc_final( self )
        type(polarft_calc), intent(inout) :: self
    end subroutine polarft_calc_final

    ! the half of particle iptcl (project index)
    module subroutine set_eo( self, iptcl, is_even )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        logical,             intent(in)    :: is_even
    end subroutine set_eo

    ! the shell weights k / sigma2 of both halves (shells, 2), column 1 the even half's; the block scorer reads
    ! them rounded to single precision, the shift maps as they are
    module subroutine set_sigma2_weights( self, sigma2_wk8 )
        class(polarft_calc), intent(inout) :: self
        real(real64),        intent(in)    :: sigma2_wk8(:,:)
    end subroutine set_sigma2_weights

    ! the particles (bt) and references (rt) of a tile of the workspace; the reference bins follow it
    module subroutine set_tile_plan( self, bt, rt )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: bt, rt
    end subroutine set_tile_plan

    ! the reason the last call was refused, or an empty string when it was carried out
    pure module function message( self ) result(msg)
        class(polarft_calc), intent(in) :: self
        character(len=:), allocatable :: msg
    end function message

    pure module integer function get_nrefs( self )
        class(polarft_calc), intent(in) :: self
    end function get_nrefs

    pure module integer function get_pftsz( self )
        class(polarft_calc), intent(in) :: self
    end function get_pftsz

    ! whether particle iptcl (project index) is of the even half; false when the calculator does not hold it
    pure module logical function ptcl_iseven( self, iptcl )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: iptcl
    end function ptcl_iseven

    ! the per-particle arrays of a batch of self%nptcls particles, and their release (new, kill and
    ! reallocate_ptcls share them)
    module subroutine alloc_ptcls( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine alloc_ptcls

    module subroutine kill_ptcls( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine kill_ptcls

    ! the batch slot of particle iptcl (project index), 0 when the calculator does not hold it
    pure module integer function ptcl_slot( self, iptcl )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: iptcl
    end function ptcl_slot

    ! ---- memoization ----

    ! a new batch of nptcls particles with the project indices pinds; their memos start empty
    module subroutine reallocate_ptcls( self, nptcls, pinds )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: nptcls
        integer,             intent(in)    :: pinds(nptcls)
    end subroutine reallocate_ptcls

    ! the polar section of reference iref of one parity; memoize_refs follows the last one
    module subroutine set_ref_pft( self, iref, pft, iseven )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iref
        complex(real64),     intent(in)    :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
        logical,             intent(in)    :: iseven
    end subroutine set_ref_pft

    ! the polar section of particle iptcl, a project index, set after its CTF; its square sum per shell is
    ! memoized here; memoize_ptcls follows the last one
    module subroutine set_ptcl_pft( self, iptcl, pft )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        complex(real32),     intent(in)    :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
    end subroutine set_ptcl_pft

    ! the CTF of particle iptcl on its polar section, set before the section (1 when not set)
    module subroutine set_ptcl_ctfmat( self, iptcl, ctfmat )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        real(real32),        intent(in)    :: ctfmat(self%pftsz, self%kfromto(1):self%kfromto(2))
    end subroutine set_ptcl_ctfmat

    ! the references set since the last call have their memos: the first pftsz+1 bins of the full ring's
    ! transform, and the conjugated transform of its squared modulus, in double precision, rounded once
    module subroutine memoize_refs( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine memoize_refs

    ! the particles set since the last call have their memos (the particle times its CTF, and the squared
    ! CTF), and every particle's weighted square sum is made from its half's shell weights
    module subroutine memoize_ptcls( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine memoize_ptcls

    ! the block scorer's layout of the reference memos: the resident tiles of both workspaces, on the current
    ! device, under the tile plan; follows memoize_refs
    module subroutine memoize_ref_bins( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine memoize_ref_bins

    ! releases the reference bins (the device's tiles); the host memos stay, and memoize_ref_bins makes them again
    module subroutine kill_ref_bins( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine kill_ref_bins

    ! whether the reference bins are those of the memoized references and the tile plan
    pure module logical function ref_bins_current( self )
        class(polarft_calc), intent(in) :: self
    end function ref_bins_current

    ! ---- block scoring ----

    ! the particles iptcls (project indices of one half) against the references irefs (all of them, in order):
    ! per pair the distance at the rotation drawn from its posterior at the particle's inverse temperature, and
    ! that rotation (1..nrots). A refused block (message) leaves dists at huge and irots at 1.
    module subroutine score_block_posterior( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )
        class(polarft_calc),       intent(inout) :: self
        integer,                   intent(in)    :: nb, nr
        integer,                   intent(in)    :: iptcls(nb), irefs(nr)
        real(real32),              intent(in)    :: temps(nb)
        real(real32),              intent(out)   :: dists(nr, nb)
        integer,                   intent(out)   :: irots(nr, nb)
        complex(real32), optional, intent(in)    :: banks(:,:,:)
        logical,         optional, intent(in)    :: l_bank(nb)
    end subroutine score_block_posterior

    ! each pair's variate in [0, 1) of the next block (references, particles); the array is taken over, not
    ! copied, and the block consumes it
    module subroutine set_block_variates( self, u )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(inout) :: u(:,:)
    end subroutine set_block_variates

    ! the seed banks of the next block queued by submit_block: banks (pftsz+1, shells, particles of the block)
    ! replaces a particle's memo where l_bank; copied, and consumed by that block
    module subroutine set_block_banks( self, banks, l_bank )
        class(polarft_calc), intent(inout) :: self
        complex(real32),     intent(in)    :: banks(:,:,:)
        logical,             intent(in)    :: l_bank(:)
    end subroutine set_block_banks

    ! what the following blocks do besides scoring: keep their full rows of distances for block_rows; evaluate
    ! after every stage and add the stages' seconds
    module subroutine set_block_options( self, rows, profile )
        class(polarft_calc), intent(inout) :: self
        logical,             intent(in)    :: rows, profile
    end subroutine set_block_options

    ! queues the block of particles iptcls against all the references in slot (1 or 2) and returns while the
    ! device works; nothing is queued on a refusal
    module subroutine submit_block( self, slot, nb, iptcls, temps )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot, nb
        integer,             intent(in)    :: iptcls(nb)
        real(real32),        intent(in)    :: temps(nb)
    end subroutine submit_block

    ! waits for slot's block and copies its entries into dists and irots (references, particles of the block),
    ! which a refusal leaves as they are; the slot is free afterwards
    module subroutine collect_block( self, slot, dists, irots )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot
        real(real32),        intent(inout) :: dists(:,:)
        integer,             intent(inout) :: irots(:,:)
    end subroutine collect_block

    ! hands over the full rows (rotations, references, particles) of the last block collected with rows
    module subroutine block_rows( self, rows )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: rows(:,:,:)
    end subroutine block_rows

    ! the profiled stages' accumulated seconds of both workspaces: particle terms, products, inverse transform,
    ! distances and draw, concatenation
    pure module function stage_seconds( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(5)
    end function stage_seconds

    ! ---- shift maps ----

    ! map imap of both parities: its shift grid (rho in pixels of the box the shift matrices act on, ascending;
    ! nalpha directions) over the shells kfromto(1)..kstop, from the memoized references and the shell weights.
    ! A refusal leaves no such map.
    module subroutine new_shiftmap( self, imap, rho, nalpha, kstop )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: imap
        real(real64),        intent(in)    :: rho(:)
        integer,             intent(in)    :: nalpha, kstop
    end subroutine new_shiftmap

    ! the two coarse maps of the probability tables, each on SIMPLE's grid: the screen over the disk of
    ! radius_px and the window of radius_win, both on the band ending at kscreen, radii a quarter of the band's
    ! wavelength apart; prior_w is the weight 1 / (2 sigma_px**2) of a prior of width sigma_px on the squared
    ! displacement (all in pixels)
    module subroutine setup_shiftmaps( self, sigma_px, radius_px, radius_win, prior_w, kscreen )
        class(polarft_calc), intent(inout) :: self
        real(real64),        intent(in)    :: sigma_px, radius_px, radius_win
        real(real64),        intent(out)   :: prior_w
        integer,             intent(out)   :: kscreen
    end subroutine setup_shiftmaps

    ! every map released, on both parities
    module subroutine kill_shiftmap( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine kill_shiftmap

    ! the pairs whose maps on imap's grid the next shiftmap_mode reads: reference iref(p) against particle
    ! iptcl(p) (project index), every particle's candidates in turn, the same number for each, all of one half.
    ! The device constructs the maps when the modes are read.
    module subroutine gen_shiftmap( self, imap, iref, iptcl )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: imap
        integer,             intent(in)    :: iref(:), iptcl(:)
    end subroutine gen_shiftmap

    ! per generated pair the cell of the largest mass exp(-temp L - prior_w rho**2) times the cell's area: its
    ! rotation (1..nrots), radius and direction indices, and its loss L; with temp_phys and sdev, the width of
    ! the shift's distribution at the physical temperature (pixels), -1 where the mode's loss is above
    ! width_cutoff. A refusal (message) leaves the indices at 1, loss at huge and sdev at -1.
    module subroutine shiftmap_mode( self, imap, temp, prior_w, irot, irho, ialpha, loss, temp_phys, sdev, width_cutoff )
        class(polarft_calc),    intent(inout) :: self
        integer,                intent(in)    :: imap
        real(real64),           intent(in)    :: temp(:), prior_w
        integer,                intent(out)   :: irot(:), irho(:), ialpha(:)
        real(real32),           intent(out)   :: loss(:)
        real(real64), optional, intent(in)    :: temp_phys(:)
        real(real32), optional, intent(out)   :: sdev(:)
        real(real32), optional, intent(in)    :: width_cutoff(:)
    end subroutine shiftmap_mode

    ! what the following modes do besides: the particles of one graph (each with all its candidates), every
    ! map kept for shiftmap_maps, the log evidence kept for shiftmap_evidence, the stages profiled
    module subroutine set_shiftmap_options( self, ptcl_tile, maps, evidence, profile )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: ptcl_tile
        logical,             intent(in)    :: maps, evidence, profile
    end subroutine set_shiftmap_options

    ! per pair of the last modes, the log evidence under the tempered temperature and the prior; unallocated
    ! when it was not asked for
    module subroutine shiftmap_evidence( self, logz )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: logz(:)
    end subroutine shiftmap_evidence

    ! per pair of the last modes, the map of the loss (directions, rotations, radii, pairs); unallocated when
    ! the maps were not asked for
    module subroutine shiftmap_maps( self, maps )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: maps(:,:,:,:)
    end subroutine shiftmap_maps

    ! particle iptcl's weighted square sum over the shells kfromto(1)..kstop under its half's shell weights; 0
    ! when the calculator does not hold the particle
    pure module function wsqsum_ptcl_band( self, iptcl, kstop ) result(wsq)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: iptcl, kstop
        real(real64) :: wsq
    end function wsqsum_ptcl_band

    ! the last shell of map imap's band, 0 when there is no such map
    pure module integer function shiftmap_kstop( self, imap )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
    end function shiftmap_kstop

    ! the Bessel orders 0..shiftmap_order(imap) the map keeps
    pure module integer function shiftmap_order( self, imap )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
    end function shiftmap_order

    ! the radius-order terms of a map's contraction: those the truncation keeps, and those executed
    pure module function shiftmap_term_counts( self, imap ) result(counts)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        integer(int64) :: counts(2)
    end function shiftmap_term_counts

    ! the profiled map stages' accumulated seconds of both workspaces: construction, mode, width, copy-out
    pure module function shiftmap_seconds( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(4)
    end function shiftmap_seconds
end interface

end module mlxf_toy_polarft_calc
