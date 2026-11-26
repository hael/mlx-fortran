!@descr: the toy polar calculator (test only): a miniature of SIMPLE's polarft_calc with its device state as one opaque component
! The type, its procedures and their dummy arguments carry SIMPLE's names; scripts/toy_mirror.txt lists each
! as mirrored or as an addition with its reason. The host side is SIMPLE's: references and particles are set one
! at a time in SIMPLE's shapes, memoized into the transforms the scorer reads, and scored in blocks of one
! half. The backend is chosen in new (the parameters' l_mlx). All MLX state sits in ws, one workspace per
! reference parity, made in new and released in kill; this module and its host submodules (core, memoization,
! block scoring, the shift maps, as in SIMPLE) see it as class(device_work) and import no MLX name. Each host
! submodule that needs the device has a glue submodule <name>_mlx beside it, whose procedures the last
! interface block declares.
module mlxf_toy_polarft_calc
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_test_defs,       only: POLAR_CANON_BT, POLAR_CANON_RT, POLARFT_STAGE_N, NSHIFTMAPS, POLARFT_TAILS, &
                                POLARFT_REF_ROUTES, PFTC_BLOCK_NB, PFTC_BLOCK_NR, parameters, polarft_block_spec, &
                                polarft_map_spec, polarft_map_block, polar_map_results
use mlxf_toy_device_work, only: device_work
use mlxf_toy_projector,   only: projector
implicit none

public :: polarft_calc, vol_pad2ref_pfts_opt, keyed_variate
private

! the reference parities, and the slots a caller may have in flight
integer, parameter :: REF_EVEN       = 1
integer, parameter :: REF_ODD        = 2
integer, parameter :: N_REF_PARITIES = 2
integer, parameter :: NSLOTS         = 2

! the host block kernel's work of one thread (SIMPLE's): the particle terms of every bin (2nk, PFTC_BLOCK_NB,
! pftsz+1), a tile's sums (PFTC_BLOCK_NB, PFTC_BLOCK_NR, pftsz+1), one pair's bins and their inverse transform,
! the particles' norms, a row's distances and weights; the toy's own: the full rows of the thread's last block
! (rotations, references, particles) when they are kept, and that block's references and particles
type :: polarft_block_work
    complex(real32), allocatable :: pterms(:,:,:)
    complex(real32), allocatable :: prods(:,:,:)
    complex(real32), allocatable :: ct(:)
    real(real32),    allocatable :: out(:)
    real(real64),    allocatable :: norms(:)
    real(real32),    allocatable :: rot_dists(:)
    real(real32),    allocatable :: rot_cdf(:)
    real(real32),    allocatable :: rows(:,:,:)
    integer                      :: last(2) = 0
end type polarft_block_work

! SIMPLE's members under SIMPLE's names, for the members the toy has. pfts_refs, pfts_ptcls and ctfmats are
! staging of POLARFT_STAGE_N sections: they hold what the setters were given (stage_ref: the reference and its
! parity; stage_ptcl: the batch slot; l_stage_pft: the section came) until the staging fills or the next
! memoization, which turns them into memos (l_refs_pending: references wait for it; l_refs_memoized: a reference
! has its memo on the route in use). The memos are those of the scorer: ft_ref_terms per reference and parity
! (2nk, pftsz+1: rows 1..nk the transform of the squared modulus, rows nk+1..2nk that of the ring, SIMPLE's one
! layout, read in place by every kernel), ft_ptcl_ctf and ft_ctf2 per particle of the batch, and from them
! ft_ptcl_wterms, the particle's terms of the objective in the same layout (rows 1..nk w_k FT(CTF2), rows
! nk+1..2nk -2 w_k FT(X.CTF), SIMPLE's euclid terms); dft_e holds the transform's factors. The rest serves the
! additions: the tile plan, the options, variates, seed banks and rows of a block, the parity of the block in
! each slot, the reason of the last refusal. Of the shift maps the calculator keeps what tells whether a map
! is that of the memoized references and weights (map_ref_gen, map_wk_gen), its band's last shell, the pairs
! gen_shiftmap was given (sm_*), the options and the requested outputs of the last modes. l_mlx is the backend
! taken at new; ws the device state, allocated on the MLX backend only, whose reference tiles memoize_refs makes
! (ref_gen_tiles: the generation they are of). The host backend's: bwork, the block kernel's work of a team of
! nthr; idft_e, the inverse transform's factors; the keys of the draws (rnd_seed and each reference's full index).
type :: polarft_calc
    private
    integer        :: nptcls     = 1
    integer        :: nrefs      = 1
    integer        :: nrots      = 0
    integer        :: pftsz      = 0
    integer        :: pfromto(2) = 0
    integer        :: kfromto(2) = 0
    integer        :: nk         = 0
    integer        :: ldim(3)    = 0
    integer        :: nspace     = 0
    integer        :: nstates    = 1
    integer,                  allocatable :: pinds(:)
    logical,                  allocatable :: iseven(:)
    real(real64),             allocatable :: wsqsums_ptcls(:)
    real(real64),             allocatable :: kshell_sqsums_ptcls(:,:)
    real(real32),             allocatable :: sigma2_wk(:,:)
    real(real64),             allocatable :: sigma2_wk8(:,:)
    real(real32),             allocatable :: polar(:,:,:)
    real(real32),             allocatable :: ctfmats(:,:,:)
    complex(real64),          allocatable :: pfts_refs(:,:,:)
    complex(real32),          allocatable :: pfts_ptcls(:,:,:)
    complex(real32),          allocatable :: ft_ptcl_ctf(:,:,:)
    complex(real32),          allocatable :: ft_ctf2(:,:,:)
    complex(real32),          allocatable :: ft_ptcl_wterms(:,:,:)
    complex(real32),          allocatable :: ft_ref_terms(:,:,:,:)
    integer(int64) :: ref_gen       = 0_int64
    integer(int64) :: ref_gen_tiles = -1_int64
    integer(int64) :: ptcl_gen      = 0_int64
    integer(int64) :: ptcl_gen_memo = -1_int64
    logical        :: existence     = .false.
    logical        :: l_mlx         = .false.
    integer        :: nthr          = 1
    type(polarft_block_work), allocatable :: bwork(:)
    complex(real32),          allocatable :: idft_e(:,:)
    integer        :: rnd_seed      = 0
    integer,                  allocatable :: ref_full(:)
    logical        :: l_keys        = .false.
    integer        :: nref_staged      = 0
    integer        :: nptcl_staged     = 0
    integer        :: stage_ref(2, POLARFT_STAGE_N) = 0
    integer        :: stage_ptcl(POLARFT_STAGE_N)  = 0
    logical        :: l_stage_pft(POLARFT_STAGE_N) = .false.
    logical        :: l_refs_pending   = .false.
    logical        :: l_refs_memoized  = .false.
    logical,                  allocatable :: l_ptcl_set(:)
    complex(real64),          allocatable :: dft_e(:,:)
    logical        :: l_weights        = .false.
    integer        :: bt               = POLAR_CANON_BT
    integer        :: rt               = POLAR_CANON_RT
    integer        :: tail             = POLARFT_TAILS%graph
    integer        :: route            = POLARFT_REF_ROUTES%host
    logical        :: l_rows           = .false.
    logical        :: l_profile        = .false.
    integer        :: slot_ieo(NSLOTS) = 0
    real(real32),             allocatable :: u_next(:,:)
    complex(real32),          allocatable :: banks_next(:,:,:)
    logical,                  allocatable :: l_bank_next(:)
    real(real32),             allocatable :: rows(:,:,:)
    integer(int64) :: wk_gen                  = 0_int64
    integer(int64) :: map_ref_gen(NSHIFTMAPS) = -1_int64
    integer(int64) :: map_wk_gen(NSHIFTMAPS)  = -1_int64
    integer        :: map_kstop(NSHIFTMAPS)   = 0
    integer        :: sm_imap                 = 0
    integer        :: sm_ieo                  = 0
    integer,                  allocatable :: sm_islots(:)
    integer,                  allocatable :: sm_cands(:,:)
    integer        :: sm_ptcl_tile            = 16
    logical        :: sm_l_maps               = .false.
    logical        :: sm_l_evidence           = .false.
    logical        :: sm_l_profile            = .false.
    real(real32),             allocatable :: sm_logz(:,:)
    real(real32),             allocatable :: sm_maps(:,:,:,:,:)
    character(len=:),         allocatable :: msg
    class(device_work),       allocatable :: ws(:)
  contains
    ! core
    procedure :: new
    procedure :: kill
    procedure :: set_eo
    procedure :: set_sigma2_weights
    procedure :: set_tile_plan
    procedure :: set_tail_form
    procedure :: set_ref_route
    procedure :: message
    procedure :: get_nrefs
    procedure :: get_pftsz
    procedure :: get_kfromto
    procedure :: get_polar_coords
    procedure :: ptcl_iseven
    ! memoization
    procedure :: reallocate_ptcls
    procedure :: set_ref_pft
    procedure :: get_ref_pft
    procedure :: set_ptcl_pft
    procedure :: set_ptcl_ctfmat
    procedure :: memoize_refs
    procedure :: memoize_ptcls
    procedure :: kill_ref_tiles
    procedure :: ref_tiles_current
    ! block scoring
    procedure :: score_block_posterior
    procedure :: set_block_variates
    procedure :: set_block_banks
    procedure :: shifted_ptcl_terms
    procedure :: set_block_options
    procedure :: submit_block
    procedure :: collect_block
    procedure :: block_rows
    procedure :: copy_block_rows
    procedure :: set_draw_keys
    procedure :: check_block_work
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
    ! kfromto(1)..kfromto(2), on the backend params%l_mlx names; a refusal (message) leaves it not existing
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

    ! the particles (bt) and references (rt) of a tile of the workspace; the reference tiles follow it at the next
    ! memoize_refs
    module subroutine set_tile_plan( self, bt, rt )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: bt, rt
    end subroutine set_tile_plan

    ! the form of the dense score's tail (POLARFT_TAILS): the compiled graph, or the fused Metal kernel (GPU only);
    ! the reference tiles follow it at the next memoize_refs
    module subroutine set_tail_form( self, form )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: form
    end subroutine set_tail_form

    ! the route of the projected references (POLARFT_REF_ROUTES): through set_ref_pft and the host memos, the
    ! reference and the default; or resident on the device from the projected bank to the tiles, where the shift
    ! maps are refused; it needs the MLX backend. A change is refused while references wait to be memoized, and
    ! once a reference is memoized: its memo exists on one route only, and the other route's would be stale. The
    ! reference tiles follow the route
    module subroutine set_ref_route( self, route )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: route
    end subroutine set_ref_route

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

    pure module function get_kfromto( self ) result(kfromto)
        class(polarft_calc), intent(in) :: self
        integer :: kfromto(2)
    end function get_kfromto

    ! the polar coordinates of the half ring, dimension 1 (h = sin(a) k) or 2 (k = -cos(a) k) of every shell and
    ! angle a = (irot - 1) 2 pi / nrots, in single precision as SIMPLE's table; another dimension is refused
    ! (message) and gives zeros
    module subroutine get_polar_coords( self, dim, coords )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: dim
        real(real32),        intent(out)   :: coords(self%kfromto(1):self%kfromto(2), self%pftsz)
    end subroutine get_polar_coords

    ! the bank of state's nspace references (references (state - 1) nspace + 1 .. state nspace) of the parity
    ! iseven, projected from the expanded vol_pad under the rotation matrices eulspace(:, :, 1 .. nspace), handed
    ! to the calculator through set_ref_pft; memoize_refs follows. A refusal (message) sets no reference.
    module subroutine vol_pad2ref_pfts_opt( self, vol_pad, eulspace, state, iseven )
        class(polarft_calc), intent(inout) :: self
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        integer,             intent(in)    :: state
        logical,             intent(in)    :: iseven
    end subroutine vol_pad2ref_pfts_opt

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

    ! the polar section of reference iref of one parity: on the device route the projected section, copied from the
    ! device; on the host route the section while it is staged (the memos replace it); otherwise refused (message)
    ! with pft at zero
    module subroutine get_ref_pft( self, iref, iseven, pft )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iref
        logical,             intent(in)    :: iseven
        complex(real32),     intent(inout) :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
    end subroutine get_ref_pft

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

    ! the references set since the last call have their memos (2nk, pftsz+1): the first pftsz+1 bins of the
    ! transform of the full ring's squared modulus, then of the ring, in double precision, rounded once; on the
    ! MLX backend both parities' resident tiles follow, under the tile plan and tail, made again when none wait
    module subroutine memoize_refs( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine memoize_refs

    ! the particles set since the last call have their memos (the particle times its CTF, and the squared
    ! CTF), and every particle's weighted square sum and terms (2nk, pftsz+1) are made from its half's weights
    module subroutine memoize_ptcls( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine memoize_ptcls

    ! releases the device's reference tiles; the host memos stay, and memoize_refs makes the tiles again
    module subroutine kill_ref_tiles( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine kill_ref_tiles

    ! whether the reference tiles (on the host backend the memos themselves) are those of the memoized
    ! references, the tile plan and the tail, with no reference waiting to be memoized
    pure module logical function ref_tiles_current( self )
        class(polarft_calc), intent(in) :: self
    end function ref_tiles_current

    ! ---- block scoring ----

    ! the particles iptcls (project indices of one half) against the references irefs: per pair the distance at
    ! the rotation drawn from its posterior at the particle's inverse temperature, and that rotation (1..nrots).
    ! On the host backend it is SIMPLE's block kernel, thread-safe (the calling thread's work): at most
    ! PFTC_BLOCK_NB particles, any references, the variate keyed by set_draw_keys; inside a parallel region a
    ! refused block leaves SIMPLE's invalid entries and no message. On the MLX backend: all the references in
    ! order, the variates of set_block_variates, one calling thread. Seed banks (2nk, pftsz+1, nb), as
    ! shifted_ptcl_terms makes them, replace a particle's terms where l_bank. A refused block (message) leaves
    ! dists at huge and irots at 1.
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

    ! the block kernel's work of a team of nthr_team threads and the inverse transform's factors (the host
    ! backend makes them in new), and their release
    module subroutine new_block_work( self, nthr_team )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: nthr_team
    end subroutine new_block_work

    module subroutine kill_block_work( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine kill_block_work

    ! a deterministic variate in [0, 1) keyed by a seed, a particle's project index and a reference's full index,
    ! never by a place in a block or by a thread (a Lehmer generator over the key)
    pure module function keyed_variate( seed, iptcl, iref ) result(u)
        integer, intent(in) :: seed, iptcl, iref
        real(real64) :: u
    end function keyed_variate

    ! the keys of the host backend's draws: a pair's variate is keyed by seed, the particle's project index and
    ! the reference's full index ref_full(iref)
    module subroutine set_draw_keys( self, seed, ref_full )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: seed
        integer,             intent(in)    :: ref_full(:)
    end subroutine set_draw_keys

    ! whether a team of nthr_team threads may score blocks on the host backend now: a refusal (message) names
    ! what is missing. Called before the team's region, where a block cannot say why it was not scored.
    module subroutine check_block_work( self, nthr_team )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: nthr_team
    end subroutine check_block_work

    ! the full rows (rotations, references, particles) of the calling thread's last block on the host backend,
    ! copied into rows without an allocation; they are kept when set_block_options asked for them
    module subroutine copy_block_rows( self, rows )
        class(polarft_calc), intent(inout) :: self
        real(real32),        intent(inout) :: rows(:,:,:)
    end subroutine copy_block_rows

    ! each pair's variate in [0, 1) of the next block (references, particles); the array is taken over, not
    ! copied, and the block consumes it
    module subroutine set_block_variates( self, u )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(inout) :: u(:,:)
    end subroutine set_block_variates

    ! the seed banks of the next block queued by submit_block: banks (2nk, pftsz+1, particles of the block)
    ! replaces a particle's terms where l_bank; copied, and consumed by that block
    module subroutine set_block_banks( self, banks, l_bank )
        class(polarft_calc), intent(inout) :: self
        complex(real32),     intent(in)    :: banks(:,:,:)
        logical,             intent(in)    :: l_bank(:)
    end subroutine set_block_banks

    ! the seed bank of particle iptcl (project index) from its shifted FT(X.CTF) xctf (pftsz+1, shells): its
    ! memoized terms with the cross term rows nk+1..2nk -2 w_k xctf; a refusal (message) leaves bank at zero
    module subroutine shifted_ptcl_terms( self, iptcl, xctf, bank )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        complex(real32),     intent(in)    :: xctf(:,:)
        complex(real32),     intent(out)   :: bank(2 * self%nk, self%pftsz + 1)
    end subroutine shifted_ptcl_terms

    ! what the following blocks do besides scoring: keep their full rows of distances for block_rows (on the host
    ! backend in each thread's work, for copy_block_rows too); evaluate after every stage and add the stages'
    ! seconds (the MLX backend)
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

    ! hands over the full rows (rotations, references, particles) of the last block collected with rows; on the
    ! host backend those of the calling thread's last block
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

! MLX: the glue procedures, private to the class. A host procedure's whole knowledge of the device is a guarded
! call of its <name>_mlx; the bodies are in the glue submodules (mlxf_toy_polarft_<part>_mlx), which alone import
! mlxf and the workspace, and which a build without MLX compiles as stubs that refuse with "built without MLX"
interface
    ! ---- core ----

    ! the device state of a new calculator: one workspace per reference parity
    module subroutine new_mlx( self, status )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(out)   :: status
    end subroutine new_mlx

    ! the device route of vol_pad2ref_pfts_opt: the projected bank stays on the device, with the parity's workspace
    module subroutine vol_pad2ref_pfts_opt_mlx( self, vol_pad, eulspace, state, iseven )
        class(polarft_calc), intent(inout) :: self
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        integer,             intent(in)    :: state
        logical,             intent(in)    :: iseven
    end subroutine vol_pad2ref_pfts_opt_mlx

    ! ---- memoization ----

    ! the device route's projected section of a reference, copied to the host
    module subroutine get_ref_pft_mlx( self, iref, iseven, pft )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iref
        logical,             intent(in)    :: iseven
        complex(real32),     intent(inout) :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
    end subroutine get_ref_pft_mlx

    ! the device route's memos: the ring transforms of the projected sections, made where they are
    module subroutine memoize_refs_mlx( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine memoize_refs_mlx

    ! the resident tiles of both parities under the tile plan: from the host memos, or on the device route from
    ! the device memos, which they replace
    module subroutine memoize_ref_tiles_mlx( self )
        class(polarft_calc), intent(inout) :: self
    end subroutine memoize_ref_tiles_mlx

    ! ---- block scoring ----

    ! the block scored on the device: a submission to the first slot and its collection
    module subroutine score_block_posterior_mlx( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )
        class(polarft_calc),       intent(inout) :: self
        integer,                   intent(in)    :: nb, nr
        integer,                   intent(in)    :: iptcls(nb), irefs(nr)
        real(real32),              intent(in)    :: temps(nb)
        real(real32),              intent(out)   :: dists(nr, nb)
        integer,                   intent(out)   :: irots(nr, nb)
        complex(real32), optional, intent(in)    :: banks(:,:,:)
        logical,         optional, intent(in)    :: l_bank(nb)
    end subroutine score_block_posterior_mlx

    ! blk checked, given its host inputs and queued in its slot of its parity's workspace
    module subroutine submit_block_mlx( self, blk, iptcls )
        class(polarft_calc),      intent(inout) :: self
        type(polarft_block_spec), intent(inout) :: blk
        integer,                  intent(in)    :: iptcls(:)
    end subroutine submit_block_mlx

    ! the block of slot in the workspace of parity ieo, waited for and copied out, with its rows when kept
    module subroutine collect_block_mlx( self, slot, ieo, dists, irots )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot, ieo
        real(real32),        intent(inout) :: dists(:,:)
        integer,             intent(inout) :: irots(:,:)
    end subroutine collect_block_mlx

    pure module function stage_seconds_mlx( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(5)
    end function stage_seconds_mlx

    ! ---- shift maps ----

    ! map spec%imap's resident data on both parities, each from its memos and shell weights; a failure leaves no
    ! such map (message)
    module subroutine new_shiftmap_mlx( self, spec )
        class(polarft_calc),    intent(inout) :: self
        type(polarft_map_spec), intent(inout) :: spec
    end subroutine new_shiftmap_mlx

    ! map imap released on both parities; every map when imap is 0
    module subroutine kill_shiftmap_mlx( self, imap )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: imap
    end subroutine kill_shiftmap_mlx

    ! the maps of a block's pairs built and reduced on the device (the generated pairs' parity)
    module subroutine shiftmap_mode_mlx( self, mblk, res )
        class(polarft_calc),     intent(inout) :: self
        type(polarft_map_block), intent(in)    :: mblk
        type(polar_map_results), intent(out)   :: res
    end subroutine shiftmap_mode_mlx

    pure module integer function shiftmap_order_mlx( self, imap )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
    end function shiftmap_order_mlx

    pure module function shiftmap_term_counts_mlx( self, imap ) result(counts)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        integer(int64) :: counts(2)
    end function shiftmap_term_counts_mlx

    pure module function shiftmap_seconds_mlx( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(4)
    end function shiftmap_seconds_mlx
end interface

end module mlxf_toy_polarft_calc
