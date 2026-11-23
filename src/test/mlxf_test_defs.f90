!@descr: what test modules share: the polar pipeline's constants, tunables, tolerances and behaviourless records
! A defs module of test code: public by default, constants and behaviourless records only (the workspace that
! takes and returns the records is a class in its own module). The polar constants restate the production
! scorer's distance and draw rules (an entry above POLAR_DIST_MAX is invalid; weights below exp(-80) are zero).
module mlxf_test_defs
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
implicit none
private :: int64, real32, real64

! a rotation's distance above this is invalid: -log of single-precision 1e-10, evaluated in double precision
real(real64), parameter :: POLAR_DIST_MAX = -log(real(1.e-10_real32, real64))
! the distance of an invalid entry, and the bound below which a distance is valid
real(real32), parameter :: POLAR_DIST_INVALID = huge(1._real32)
real(real32), parameter :: POLAR_DIST_VALID   = 0.1_real32*huge(1._real32)
! a posterior weight exp(-arg) with arg at or above this is zero
real(real32), parameter :: POLAR_ARG_CUTOFF = 80._real32
! the least cumulative weight a drawn rotation reaches
real(real32), parameter :: POLAR_DRAW_FLOOR = tiny(1._real32)
! the draw on the device's own rows: u W lies in the drawn rotation's cumulative interval within this share of W
real(real64), parameter :: POLAR_DRAW_TOL = 1.e-4_real64
! an oracle distance this close to POLAR_DIST_MAX, relative to its row's largest |d|, may be judged valid in
! float64 and invalid in float32 (or the reverse): three orders above single-precision rounding
real(real64), parameter :: POLAR_VALID_MARGIN = 1.e-4_real64
! the polar table's formulations of a tile's sums and transform: b, the complex product of every bin as a real
! product of packed (Re, Im) parts, then the inverse real FFT (the full-precision formulation); c, as b, with the
! inverse transform a second real product against a fixed cosine and sine matrix, so that every product is real
type :: polar_form_codes
    integer :: b = 1
    integer :: c = 2
end type polar_form_codes

type(polar_form_codes), parameter :: POLAR_FORMS = polar_form_codes()

! the seeds of the polar calibrations and of the runs they judge (the fixture's and the accuracy block's)
integer, parameter :: POLAR_SEED_CALIBRATION = 1
integer, parameter :: POLAR_SEED_JUDGED      = 2
! the benchmark's timing sweep: particles and references per tile
integer, parameter :: POLAR_GRID_B(5) = [64, 250, 500, 1000, 2000]
integer, parameter :: POLAR_GRID_R(5) = [64, 250, 500, 1000, 2500]
! the memory budget of one benchmark configuration, checked before allocation: this share of the machine's
! memory as the GPU reports it (memory_size; unified on Apple silicon)
real(real64), parameter :: POLAR_BUDGET_SHARE = 0.25_real64
! the canonical tile plan of the kept formulation (particles and references per tile), measured fastest on the
! M2 Ultra; the timing modes profile and overlap use it
integer, parameter :: POLAR_CANON_BT = 64
integer, parameter :: POLAR_CANON_RT = 250
! the accuracy block's tile plan (particles and references per tile)
integer, parameter :: POLAR_BLOCK_BT = 16
integer, parameter :: POLAR_BLOCK_RT = 250
! production's tempering factor of the shift maps (SIMPLE's PROB_BETA): tempered temperature = POLAR_PROB_BETA
! times the physical
real(real64), parameter :: POLAR_PROB_BETA = 0.3_real64

! the references of one half, in the production memo's layout: for each shell k and angular bin p of the
! pftsz+1 bins, ft_ref the transform of the reference ring and ft_ref2 the conjugated transform of its squared
! modulus; ids the references' global IDs in the order their entries come back; rt and bt the canonical tile
! plan (references and particles per tile, every tile padded to them); formulation one of POLAR_FORMS
type :: polar_table_refs
    integer                      :: pftsz      = 0
    integer                      :: nk         = 0
    integer                      :: half       = 0
    integer                      :: rt         = 0
    integer                      :: bt         = 0
    integer(int64)               :: generation  = 0_int64
    integer                      :: formulation = POLAR_FORMS%b
    integer,         allocatable :: ids(:)
    complex(real32), allocatable :: ft_ref(:,:,:)
    complex(real32), allocatable :: ft_ref2(:,:,:)
end type polar_table_refs

! one block of particles of one half, against the prepared references: ctf2 the transform of the squared CTF
! ring, xctf of the particle times CTF ring, both (pftsz+1, nk, nptcls); banks replaces xctf where l_bank (a
! seed bank's shifted particle); weights the half's shell weights, wsq each particle's weighted square sum,
! temps the inverse temperatures, u the caller's variate of each pair (nrefs, nptcls); rows asks for the full
! rows of distances as well; profile evaluates after every stage and adds the stages' times to the workspace's
type :: polar_table_block
    integer                      :: half       = 0
    integer(int64)               :: generation = 0_int64
    integer,         allocatable :: ref_ids(:)
    integer,         allocatable :: ptcl_ids(:)
    real(real32),    allocatable :: weights(:)
    complex(real32), allocatable :: ctf2(:,:,:)
    complex(real32), allocatable :: xctf(:,:,:)
    complex(real32), allocatable :: banks(:,:,:)
    logical,         allocatable :: l_bank(:)
    real(real64),    allocatable :: wsq(:)
    real(real32),    allocatable :: temps(:)
    real(real32),    allocatable :: u(:,:)
    logical                      :: rows       = .false.
    logical                      :: profile    = .false.
end type polar_table_block

! a block's entries by (reference in prepared order, particle in block order): the drawn rotation's distance
! and the rotation (1..nrots), and the full rows (nrots, nrefs, nptcls) when the block asked for them
type :: polar_table_entries
    real(real32), allocatable :: dists(:,:)
    integer,      allocatable :: irots(:,:)
    real(real32), allocatable :: rows(:,:,:)
end type polar_table_entries

! a shift map's grid for the prepared references of one half: box (pixels the shifts are in), the absolute
! shell numbers kfrom (the references' first shell) and kstop (the band's last), the radii rho (pixels,
! ascending) and nalpha directions over the turn, the prior's weight on rho^2, and the half's shell weights
! over the band (real64)
type :: polar_map_spec
    integer                   :: box     = 0
    integer                   :: kfrom   = 0
    integer                   :: kstop   = 0
    integer                   :: nalpha  = 0
    real(real64)              :: prior_w = 0._real64
    real(real64), allocatable :: rho(:)
    real(real64), allocatable :: weights(:)
end type polar_map_spec

! the shift maps of particles against ordered candidate references (global IDs of the prepared list, cands
! (ncand, nptcls), repeats allowed): xctf and ctf2 as a scoring block's, ptclpow the weighted square sum over
! the map's band, temps the tempered and temps_phys the physical inverse temperatures; maps asks for every map
! (nalpha, nrots, nrho) as well, evidence for the log evidence; ptcl_tile is the particles of one graph, each
! with all its candidates
type :: polar_map_block
    integer                      :: half       = 0
    integer(int64)               :: generation = 0_int64
    integer                      :: ptcl_tile  = 16
    logical                      :: maps       = .false.
    logical                      :: evidence   = .false.
    logical                      :: profile    = .false.
    integer,         allocatable :: ptcl_ids(:)
    integer,         allocatable :: cands(:,:)
    complex(real32), allocatable :: ctf2(:,:,:)
    complex(real32), allocatable :: xctf(:,:,:)
    real(real64),    allocatable :: ptclpow(:)
    real(real32),    allocatable :: temps(:)
    real(real32),    allocatable :: temps_phys(:)
end type polar_map_block

! per (candidate, particle): the mode's loss, rotation, radius and direction (1-based), the physical width
! (pixels), the log evidence when asked, and the full maps (nalpha, nrots, nrho, ncand, nptcls) when asked
type :: polar_map_results
    real(real32), allocatable :: loss(:,:)
    real(real32), allocatable :: sdev(:,:)
    real(real32), allocatable :: logz(:,:)
    integer,      allocatable :: irot(:,:)
    integer,      allocatable :: irho(:,:)
    integer,      allocatable :: ialpha(:,:)
    real(real32), allocatable :: maps(:,:,:,:,:)
end type polar_map_results

! the comparison of a block's device rows and entries with an oracle
type :: polar_row_check
    real(real64) :: err        = 0._real64
    integer      :: argmin_off = 0
    integer      :: valid_off  = 0
    integer      :: npairs     = 0
    integer      :: draws_bad  = 0
    integer      :: mixed      = 0
    integer      :: invalid    = 0
end type polar_row_check

! the shift maps' Fourier-Bessel truncation, SIMPLE's: at each radius the orders from the first one past the
! largest argument z whose |J_n(z)| is below this on are dropped
real(real64), parameter :: POLAR_BESSEL_JTOL = 1.e-8_real64
! a shift map's cells whose log mass lies this far below the largest carry no mass
real(real64), parameter :: POLAR_MAP_LOG_CUT = -40._real64

! the shift maps' caps, confirmed on the CPU device and frozen: a complete map's error in L2 relative to the
! direct residual's; the log evidence's absolute error; the physical width's variance error, relative to
! max(1, the largest radius squared)
real(real64), parameter :: POLAR_MAP_CAP_L2  = 1.e-4_real64
real(real64), parameter :: POLAR_MAP_CAP_LOG = 1.e-4_real64
real(real64), parameter :: POLAR_MAP_CAP_VAR = 1.e-4_real64

! the polar fixture's calibration on the CPU device, fixture seed 1 (its seed banks the particles translated
! back), one pair per formulation (indexed by POLAR_FORMS: each formulation is judged against its own), frozen:
! e_cpu, the largest error of a pair's distances relative to the largest |d| of its oracle row, and n_cpu, the
! pairs whose minimising rotation differs from the oracle's
real(real64), parameter :: POLAR_FIXTURE_ERR_CPU(2) = [2.3972463973750171e-07_real64, 5.8318067127818633e-07_real64]
integer,      parameter :: POLAR_FIXTURE_ROT_CPU(2) = [0, 0]
! a device's rows are within this factor of e_cpu; its rotation disagreements at most
! max(factor * n_cpu, POLAR_FIXTURE_ROT_Q), q being the count a 1e-5 per-pair rate exceeds with probability
! below 1e-4 over the fixture's 96 pairs
real(real64), parameter :: POLAR_ROW_FACTOR      = 2._real64
integer,      parameter :: POLAR_FIXTURE_ROT_Q   = 1
! the accuracy block's calibration on the CPU device, block seed 1 (64 particles against 1,000 references per
! half at SIMPLE's case geometry), frozen as the fixture's pair is; q = 5 for its 64,000 pairs
real(real64), parameter :: POLAR_BLOCK_ERR_CPU = 7.2525524223032628e-07_real64
integer,      parameter :: POLAR_BLOCK_ROT_CPU = 2
integer,      parameter :: POLAR_BLOCK_ROT_Q   = 5

end module mlxf_test_defs
