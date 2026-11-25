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
! the seeds of the polar calibrations and of the runs they judge (the fixture's and the accuracy block's)
integer, parameter :: POLAR_SEED_CALIBRATION = 1
integer, parameter :: POLAR_SEED_JUDGED      = 2
! the benchmark's timing sweep: particles and references per tile
integer, parameter :: POLAR_GRID_B(5) = [64, 250, 500, 1000, 2000]
integer, parameter :: POLAR_GRID_R(5) = [64, 250, 500, 1000, 2500]
! the memory budget of one benchmark configuration, checked before allocation: this share of the machine's
! memory as the GPU reports it (memory_size; unified on Apple silicon)
real(real64), parameter :: POLAR_BUDGET_SHARE = 0.25_real64
! the canonical tile plan (particles and references per tile), measured fastest on the M2 Ultra; the timing
! modes profile and overlap use it
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
! plan (references and particles per tile, every tile padded to them)
type :: polar_table_refs
    integer                      :: pftsz      = 0
    integer                      :: nk         = 0
    integer                      :: half       = 0
    integer                      :: rt         = 0
    integer                      :: bt         = 0
    integer(int64)               :: generation = 0_int64
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

! the references, and the particles, the toy calculator's setters stage before it memoizes them: a staging
! array of every section, once released, would stay in the process's footprint
integer, parameter :: POLARFT_STAGE_N = 64

! the shift maps a polar calculator holds, SIMPLE's: the full band's, the screen's over the disk, the window's
integer, parameter :: SHIFTMAP_FULL   = 1
integer, parameter :: SHIFTMAP_SCREEN = 2
integer, parameter :: SHIFTMAP_WINDOW = 3
integer, parameter :: NSHIFTMAPS      = 3

! the members of SIMPLE's parameters object that the polar toy reads, under SIMPLE's names: the polar section's
! half ring, the box whose pixels the shifts are in, the host team, the tempering factor of the shift maps, and
! what sets up the two coarse maps: the shift prior's width and the window's radius (Angstrom and pixels) and
! the sampling distance; for the reprojection, the directions and states of the reference bank and the cropped
! box the projected volumes have
type :: parameters
    integer      :: pftsz       = 0
    integer      :: box         = 0
    integer      :: nthr        = 1
    real(real64) :: prob_beta   = POLAR_PROB_BETA
    real(real32) :: shift_sigma = 0._real32
    real(real32) :: smpd        = 1._real32
    real(real32) :: trs         = 0._real32
    integer      :: nspace      = 0
    integer      :: nstates     = 1
    integer      :: box_crop    = 0
end type parameters

! SIMPLE's Kaiser-Bessel window of the oversampled gather and scatter (simple_defs: the half-width KBWINSZ, the
! oversampling KBALPHA, which is the padding factor OSMPL_PAD_FAC) and its batch of inserted planes
! (MAXIMGBATCHSZ), restated
real(real32), parameter :: KBWINSZ       = 1.5_real32
integer,      parameter :: OSMPL_PAD_FAC = 2
real(real32), parameter :: KBALPHA       = real(OSMPL_PAD_FAC, real32)
integer,      parameter :: MAXIMGBATCHSZ = 500

! the forms of the polar projection's gather: the graph of library operations, the reference, the CPU path and the
! default; and the fused Metal kernel, GPU only
type :: projector_forms
    integer :: graph = 1
    integer :: fused = 2
end type projector_forms
type(projector_forms), parameter :: PROJ_FORMS = projector_forms()
! a projection's directions per tile and the fused kernel's threads per threadgroup, by default: family A's
! reference tile, and the group the bench's sweep measured fastest (its canonical tiles: 64 directions for the
! graph form, all 2,500 for the fused one)
integer, parameter :: PROJ_TILE_DEFAULT = POLAR_CANON_RT
integer, parameter :: PROJ_TG_DEFAULT   = 64
! a sample is near a tie when a coordinate, in double precision from the single-precision inputs, lies this close
! to a half-integer: the stencil's base may round apart there, and the sample is counted, not judged
real(real64), parameter :: PROJ_TIE_MARGIN = 1.e-4_real64
! the projection's fixtures against the oracle: a sample's |toy - oracle| over the sum of |w f| of its 27 terms,
! the largest over the judged samples of the phantom (its edge and boundary queries included) and the seeded cube,
! calibrated on seed 1 on both devices and frozen (the GPU's edge queries, where the phantom's spectrum is
! smallest beside the transform's rounding); the gate is POLAR_ROW_FACTOR times it
real(real64), parameter :: PROJ_FIXTURE_ERR = 1.502975125e-06_real64
! the chain's dense rows against the oracle chain, per route: a pair's largest distance error over the largest |d|
! of its oracle row (family A's measure), calibrated on seed 1 on both devices and both forms and frozen (the GPU's
! graph form on both routes); the gate is POLAR_ROW_FACTOR times it
real(real64), parameter :: PROJ_CHAIN_ERR_HOST   = 3.750339276e-07_real64
real(real64), parameter :: PROJ_CHAIN_ERR_DEVICE = 4.168030557e-07_real64
! the bench's accuracy (16 directions of the spiral at box 160 padded to 320, against the oracle on the device's
! own padded transform): a sample's |toy - oracle| over the sum of |w f| of its 27 terms, the largest over the
! samples that are not near a tie; calibrated on seed 1 on both devices and both forms and frozen (the GPU's graph
! form: the float32 coordinates near 124 carry it); the gate is POLAR_ROW_FACTOR times it
real(real64), parameter :: PROJ_BENCH_ERR = 1.451613272e-05_real64
! the protected-update probe: the atomic insertion's numerator and density against the gridding oracle, a voxel's
! error over the sum of |terms| of its deposits (a probe's bound, guessed: the scientific examples' cap)
real(real64), parameter :: PROBE_ERR_CAP = 1.e-5_real64
! the device bytes one benchmark process may plan for before anything is allocated
real(real64), parameter :: PROJ_BUDGET_B = 8.e9_real64

! one projection for a projector's workspace: the polar geometry (pftsz, nk shells up to kto), the directions to
! project and those the caller holds (nspace, noris), the shape of the caller's bank of sections, the padded polar
! points hk (2, pftsz nk; point fastest within a shell) and the directions' rotation rows rot (2, 3, nspace)
type :: fproject_spec
    integer                   :: pftsz         = 0
    integer                   :: nk            = 0
    integer                   :: kto           = 0
    integer                   :: nspace        = 0
    integer                   :: noris         = 0
    integer                   :: refs_shape(3) = 0
    real(real32), allocatable :: hk(:,:)
    real(real32), allocatable :: rot(:,:,:)
end type fproject_spec

! the routes of the projected references into the polar calculator: through the host's sections and memos, the
! reference, or resident on the device from the bank to the tiles
type :: polarft_routes
    integer :: host   = 1
    integer :: device = 2
end type polarft_routes
type(polarft_routes), parameter :: POLARFT_REF_ROUTES = polarft_routes()

! a shift map's grid for a workspace: which map, the box (pixels the shifts are in), the absolute shell numbers
! kfrom (the references' first shell) and kstop (the band's last), the radii rho (pixels, ascending), nalpha
! directions over the turn, and the parity's shell weights over the band (real64)
type :: polarft_map_spec
    integer                   :: imap   = 0
    integer                   :: box    = 0
    integer                   :: kfrom  = 0
    integer                   :: kstop  = 0
    integer                   :: nalpha = 0
    real(real64), allocatable :: rho(:)
    real(real64), allocatable :: weights(:)
end type polarft_map_spec

! one block of shift maps for a workspace: the map, the batch slots of its particles in the calculator's memos,
! each particle's candidate references (ncand, particles; repeats allowed) and weighted square sum over the
! map's band, the prior's weight on the squared radius, and per pair (candidate, particle) the tempered and the
! physical inverse temperatures and, when present, the loss above which a pair's width is skipped; widths asks
! for the widths at the physical temperature, maps for every map (nalpha, nrots, nrho) as well, evidence for the
! log evidence; ptcl_tile is the particles of one graph, each with all its candidates
type :: polarft_map_block
    integer                   :: imap      = 0
    integer                   :: ptcl_tile = 16
    logical                   :: widths    = .false.
    logical                   :: maps      = .false.
    logical                   :: evidence  = .false.
    logical                   :: profile   = .false.
    real(real64)              :: prior_w   = 0._real64
    integer,      allocatable :: islots(:)
    integer,      allocatable :: cands(:,:)
    real(real64), allocatable :: ptclpow(:)
    real(real32), allocatable :: temps(:,:)
    real(real32), allocatable :: temps_phys(:,:)
    real(real32), allocatable :: width_cutoff(:,:)
end type polarft_map_block

! the forms of the dense score's tail (the distances and the posterior draw of a tile): the compiled graph, the
! reference, the CPU path and the default; and the fused Metal kernel, GPU only
type :: polarft_tail_forms
    integer :: graph = 1
    integer :: metal = 2
end type polarft_tail_forms
type(polarft_tail_forms), parameter :: POLARFT_TAILS = polarft_tail_forms()
! the fused tail's threads per threadgroup (one pair each), measured on a canonical tile and frozen
integer, parameter :: POLARFT_TAIL_TG = 64
! the fused tail against the compiled one on the same rows, calibrated on seed 1 on the GPU and frozen: the rows'
! largest difference relative to the compiled row's largest valid |d|, max(2 x seed 1's, 2^-23); the pairs whose
! drawn rotation differs, max(2 x seed 1's count, the house floor) on the fixture (floor 1) and the block (5)
real(real64), parameter :: POLARFT_TAIL_ROW_TOL = 2.3816146966584994e-07_real64
integer,      parameter :: POLARFT_TAIL_ROT_FIX = 1
integer,      parameter :: POLARFT_TAIL_ROT_BLK = 5

! the tile plan a workspace's reference tiles are prepared under: the polar geometry (pftsz, nk shells), the
! references and particles per tile, every tile padded to them, and the form of the tail
type :: polarft_tile_spec
    integer :: pftsz = 0
    integer :: nk    = 0
    integer :: rt    = 0
    integer :: bt    = 0
    integer :: tail  = POLARFT_TAILS%graph
end type polarft_tile_spec

! one block for a workspace: the slot it is queued in, the batch slots of its particles in the calculator's
! memos, their parity's shell weights, weighted square sums and inverse temperatures, each pair's variate
! (references, particles), and the seed banks that replace a particle's memo where l_bank; rows asks for the
! full rows of distances as well; profile evaluates after every stage and adds the stages' seconds
type :: polarft_block_spec
    integer                      :: slot    = 1
    logical                      :: rows    = .false.
    logical                      :: profile = .false.
    integer,         allocatable :: islots(:)
    real(real32),    allocatable :: weights(:)
    real(real64),    allocatable :: wsq(:)
    real(real32),    allocatable :: temps(:)
    real(real32),    allocatable :: u(:,:)
    complex(real32), allocatable :: banks(:,:,:)
    logical,         allocatable :: l_bank(:)
end type polarft_block_spec

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
! back), frozen: e_cpu, the largest error of a pair's distances relative to the largest |d| of its oracle row,
! and n_cpu, the pairs whose minimising rotation differs from the oracle's
real(real64), parameter :: POLAR_FIXTURE_ERR_CPU = 2.3972463973750171e-07_real64
integer,      parameter :: POLAR_FIXTURE_ROT_CPU = 0
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

! the elementwise testers: points per function, the calibration seed and the seeds it judges
integer, parameter :: ELEM_NPOINTS          = 1024
integer, parameter :: ELEM_SEED_CALIBRATION = 1
integer, parameter :: ELEM_SEEDS_JUDGED(2)  = [2, 3]
! the ceiling of a float32 tolerance (64 epsilons) and the floors of every tolerance (4 epsilons of the result's
! kind), errors relative to max(1, |reference|)
real(real64), parameter :: ELEM_CEILING = 64._real64*real(epsilon(1._real32), real64)
real(real64), parameter :: ELEM_FLOOR32 = 4._real64*real(epsilon(1._real32), real64)
real(real64), parameter :: ELEM_FLOOR64 = 4._real64*epsilon(1._real64)
! a function's largest error relative to max(1, |reference|): f32 for float32 results on either device, f64 for
! float64 results on the CPU device
type :: elem_tolerance
    character(len=24) :: name = ''
    real(real64)      :: f32  = 0._real64
    real(real64)      :: f64  = 0._real64
end type elem_tolerance

! calibrated on seed 1 and frozen: max(2 x the largest error on either device, the floor of the result's
! kind); a float64 result MLX computes in float32 on the CPU (sin, cos, erf, sigmoid, erfinv, logaddexp) is held
! to the float32 bound
type(elem_tolerance), parameter :: ELEM_TOLERANCES(41) = [&
    &elem_tolerance('abs', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('sin', 4.768371582e-07_real64, 4.768371582e-07_real64), &
    &elem_tolerance('cos', 4.768371582e-07_real64, 4.768371582e-07_real64), &
    &elem_tolerance('tan', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('sinh', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('cosh', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('tanh', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('log', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('log10', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('erf', 1.509527616e-06_real64, 7.614142292e-07_real64), &
    &elem_tolerance('asin', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('acos', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('atan', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('asinh', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('acosh', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('atanh', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('floor', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('ceiling', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('aint', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_round', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_sign', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_sigmoid', 4.768371582e-07_real64, 4.768371582e-07_real64), &
    &elem_tolerance('mlx_square', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_reciprocal', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_rsqrt', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_expm1', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_log1p', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_log2', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_erfinv', 4.768371582e-07_real64, 4.768371582e-07_real64), &
    &elem_tolerance('mlx_degrees', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_radians', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_stop_gradient', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_copy', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('operator(+)', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('atan2', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('modulo', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('min', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('operator(**)', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_logaddexp', 4.768371582e-07_real64, 4.768371582e-07_real64), &
    &elem_tolerance('mlx_floor_divide', 4.768371582e-07_real64, 8.881784197e-16_real64), &
    &elem_tolerance('mlx_divmod', 4.768371582e-07_real64, 8.881784197e-16_real64)]

! MLX's GPU expm1 loses accuracy as its argument grows (an upstream defect): its float32 GPU results are held
! to this separate bound, twice the largest error of seed 1 on the GPU; the CPU keeps its tolerance above
real(real64), parameter :: ELEM_GPU_EXPM1 = 4.010555858e-05_real64

! the reduction testers' fixtures per seed: a form with dimensions runs on this many at once, so that a seed's
! largest error is taken over about a thousand reduced values
integer, parameter :: REDUCE_NBATCH = 16
! the reductions, scans, softmax, linspace and windows, an error relative to max(1, |reference|) over every form
! of the function: calibrated on seed 1 and frozen as ELEM_TOLERANCES is, max(2 x the largest error on either
! device, the floor of the result's kind); a float64 result MLX computes in float32 on the CPU (logsumexp,
! logcumsumexp, softmax) is held to the float32 bound. The windows are float32 only
type(elem_tolerance), parameter :: REDUCE_TOLERANCES(16) = [&
    &elem_tolerance('sum', 1.795589924e-06_real64, ELEM_FLOOR64), &
    &elem_tolerance('product', ELEM_FLOOR32, 2.251676254e-15_real64), &
    &elem_tolerance('mlx_mean', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_median', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_var', 8.436885142e-07_real64, 1.117111451e-15_real64), &
    &elem_tolerance('mlx_std', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_logsumexp', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_cumsum', 3.725346026e-06_real64, ELEM_FLOOR64), &
    &elem_tolerance('mlx_cumprod', 6.648052118e-07_real64, ELEM_FLOOR64), &
    &elem_tolerance('mlx_logcumsumexp', 5.597391568e-07_real64, ELEM_FLOOR32), &
    &elem_tolerance('mlx_softmax', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_linspace', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_bartlett', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_blackman', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_hamming', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_hanning', ELEM_FLOOR32, ELEM_FLOOR64)]

! the transform testers' fixtures per seed, along a fourth dimension: a seed's largest error is taken over about
! a thousand transformed values
integer, parameter :: FFT_NBATCH = 8
! the transforms over several dimensions and the frequencies, over every form of the function: a transform's
! largest error relative to max(1, the largest |reference| of its result), a frequency's relative to
! max(1, |reference|). Calibrated on seed 1 on both devices and frozen as ELEM_TOLERANCES is, max(2 x the largest
! error on either device, the float32 floor); MLX transforms in float32 whatever its input, so a float64 input
! on the CPU is held to the float32 bound
type(elem_tolerance), parameter :: FFT_TOLERANCES(8) = [&
    &elem_tolerance('mlx_fftn', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_ifftn', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_rfftn', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_irfftn', 4.979893410e-07_real64, 4.979893410e-07_real64), &
    &elem_tolerance('mlx_rfft2', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_irfft2', 4.796738626e-07_real64, 4.796738626e-07_real64), &
    &elem_tolerance('mlx_fftfreq', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_rfftfreq', ELEM_FLOOR32, ELEM_FLOOR32)]

! the gathered, block-masked and segmented matrix products: an element's error relative to
! max(1, (|a| |b|)(i, j)), the scale of a dot product's rounding, over every form of the function. Calibrated on
! seed 1 on both devices and frozen as ELEM_TOLERANCES is. MLX evaluates the first two in float32 only; the
! segmented product's float64 column is its float64 result on the CPU
type(elem_tolerance), parameter :: MM_TOLERANCES(3) = [&
    &elem_tolerance('mlx_gather_mm', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_block_masked_mm', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_segmented_mm', ELEM_FLOOR32, ELEM_FLOOR64)]

! the products of linear algebra: an element's error relative to max(1, the same product of the magnitudes), over
! every form of the function. Calibrated on seed 1 on both devices and frozen as ELEM_TOLERANCES is: no function
! reached a float32 epsilon, so each holds the floor of its kind. MLX evaluates the Hadamard transform in float32
! only; its float64 column judges nothing
type(elem_tolerance), parameter :: PRODUCT_TOLERANCES(9) = [&
    &elem_tolerance('mlx_inner', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_outer', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_kron', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_vecdot', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_cross', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_tensordot', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_einsum', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_addmm', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_hadamard_transform', ELEM_FLOOR32, ELEM_FLOOR64)]

! the bound of a backward-stable factorisation or solve: this many times the matrix order times the epsilon of the
! result's kind, for a backward error, a residual and the departure of a factor from orthogonal
real(real64), parameter :: LINALG_RESIDUAL_FACTOR = 10._real64
! determinants and norms: a value's error relative to max(1, |reference|), over every form of the function.
! Calibrated on seed 1 on both devices and frozen as ELEM_TOLERANCES is: none reached a float32 epsilon (or two
! float64 epsilons), so each holds the floor of its kind
type(elem_tolerance), parameter :: MATRIX_TOLERANCES(5) = [&
    &elem_tolerance('mlx_det', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_slogdet', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('norm2', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_norm', ELEM_FLOOR32, ELEM_FLOOR64), &
    &elem_tolerance('mlx_norm_matrix', ELEM_FLOOR32, ELEM_FLOOR64)]

! the convolutions: an output element's error relative to max(1, the same sum of magnitudes), over every form of
! the function. Calibrated on seed 1 on both devices and frozen as ELEM_TOLERANCES is: none passed 1.1 float32
! epsilons, so each holds the float32 floor. MLX computes a convolution in float32 whatever its operands (and
! refuses most float64 ones), so the float64 column holds the float32 bound and judges nothing
type(elem_tolerance), parameter :: CONV_TOLERANCES(7) = [&
    &elem_tolerance('mlx_conv1d', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_conv2d', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_conv3d', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_conv_general', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_conv_transpose1d', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_conv_transpose2d', ELEM_FLOOR32, ELEM_FLOOR32), &
    &elem_tolerance('mlx_conv_transpose3d', ELEM_FLOOR32, ELEM_FLOOR32)]

! the reconstruction's PCG benchmark: its native boxes n, each solved on the padded lattice of m = 2 n
integer, parameter :: RECON_PCG_BENCH_N(2) = [160, 256]

end module mlxf_test_defs
