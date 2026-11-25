# Kernel families as toy examples: polar matching, the 3D Fourier gather and scatter, and the PCG solve

Status, 2026-11-24: design note, accepted. Hans ruled the roadmap's decisions 6 to 9 on 2026-11-24
([`mlxf_roadmap.md`](mlxf_roadmap.md)): the families are milestone 2, the order K1 to K7 is accepted, and the
PCG solve entered as family D. Each deliverable becomes its own plan before work starts. Written at
`3a13403`, with SIMPLE read at `d354efee2`. Supersedes: examples 2 and 3 of
[`mlxf_scientific_examples.md`](mlxf_scientific_examples.md). The fixtures and oracle design of its example
3 and of its PCG problem are kept here by reference; its filter bank is deferred. Depends on: the custom Metal kernel wrapper, the n-dimensional FFTs, the gathered
and masked matrix products, and parity Phases 2 and 3 (validated: no; roadmap ranks 1a and 1b).

## 1. Why four families

SIMPLE's time goes to the probabilistic search, to reconstruction, and to reprojection: the reprojection
model before each iteration and, on the fly, inside continuous refinement. Four computations carry all of it,
and each fits a GPU for its own structural reason:

| Family | SIMPLE work it serves | Why it fits |
| --- | --- | --- |
| **A. Polar matching** | every discrete polar mode: dense and neighbourhood tables, the classic strategies, 2D; with or without the shift search; `objfun=cc` or `euclid` | many particles share the same references, so the work is large matrix products |
| **B. 3D Fourier gather** | the reprojection model; reprojection on the fly in continuous refinement | one read-only volume shared by every particle; no write conflicts; small outputs |
| **C. 3D Fourier scatter** | the insertion of particle planes in reconstruction (`rec_backend=gridding`, the default) | large independent work per plane; the one problem is accumulating without races |
| **D. The PCG solve** | reconstruction by `rec_backend=pcg` | 3D FFTs, element-wise work and reductions on volumes that stay resident |

The dense score of family A is proved (milestone 1: 4.69 times SIMPLE's 30-thread rate, *measured*). Everything
else here is design. SIMPLE's own proposal of 2026-11-16
(`doc/implementation_notes/planned/next_release/apple_silicon_gpu_port.md` in SIMPLE) sets out the dense
score, the projection and the insertion's options; this note extends it with what the M5 run and the reading
of `d354efee2` added.

## 2. Rules for every toy

- **Toy, test-only, and shaped like SIMPLE.** The code lives in `src/test/` and imports the public `mlxf`
  as a user does. It mirrors SIMPLE's classes, method names, data conventions and layering
  (`doc/policies/toy_example_policy.md`; section 2a names each family's counterparts). The library gains
  only general operations, and no SIMPLE name enters it.
- **An independent oracle.** Each kernel is judged against plain Fortran in double precision that shares no
  index, weight or layout code with it. Tolerances are frozen in `src/test/mlxf_test_defs.f90` before the run
  they judge. Each gate has a planted violation shown to fail.
- **Two sizes.** A small fixture runs in the fast gate on both devices. A bench size, named-only, is timed.
- **Two forms, in order.**
  1. A graph form from library operations, which is the reference and the CPU path.
  2. A fused custom Metal kernel, timed against the graph form on the same machine and case. It is kept
     only above a measured 30 % gain. A Metal kernel has no CPU path, so the graph form always stays.
- **Timed as SIMPLE runs.** Each bench runs alone and as 3 and 6 simultaneous processes. It reports the
  total rate, the rate per process and one process's resident memory, which multiplies by `nparts`.
- **Repeatability is its own gate:** repeated runs on one GPU configuration and tile shape are compared bit
  for bit, separately from agreement with the oracle.
- **Precision.** Arrays are float32 and complex64 at full precision. The accelerated mode is not used.
  Double-precision decisions (an optimizer step, a cumulative sum near a boundary) stay on the host or use
  compensated sums, and the toy says which.

## 2a. What each toy mirrors in SIMPLE

| Family | Domain object (SIMPLE's class) | Methods kept | Driver (SIMPLE's caller) |
| --- | --- | --- | --- |
| A | `polarft_calc` (`pftc/simple_polarft_calc.f90` and its submodules) | `new`, `kill`, `reallocate_ptcls`, `set_ref_pft`, `set_ptcl_pft`, `set_ptcl_ctfmat`, `set_eo`, `memoize_refs`, `memoize_ptcls`, `memoize_ref_bins`, `score_block_posterior`, `new_shiftmap`, `setup_shiftmaps`, `kill_shiftmap`, `gen_shiftmap`, `shiftmap_mode`, and the inquiries `get_nrefs`, `get_pftsz`, `ptcl_iseven`, `wsqsum_ptcl_band` (built: `src/test/mlxf_toy_polarft_calc.f90`) | `eul_prob_tab` with `new_pipeline`, `fill_tab_range` (its steps `cut_blocks`, `process_block`, `finish_particle_map`) and `kill` (built: `src/test/mlxf_toy_eul_prob_tab.f90`); later `eul_prob_tab_neigh` and `shiftmap_srch` |
| B1 | `projector` (`image/simple_projector.f90`, `simple_projector_pft_batch.f90`) | `fproject_polar_batch_opt` | the reprojection model's `vol_pad2ref_pfts_opt`, which fills `polarft_calc` through `set_ref_pft` |
| B2 | `cartft_calc` (`cftc/simple_cartft_calc.f90`) | `new`, `kill`, `set_ref`, `new_ptcls`, the particle setters, `pose_normal_terms`, `shift_normal_terms` | `cartft_pose_opt` (`cftc/simple_cartft_pose_opt.f90`) |
| C | `reconstructor` (`volume/simple_reconstructor.f90`) | `insert_plane_oversamp`, `compress_exp`, `sampl_dens_correct` | `calc_3Drec` (`strategies/search/simple_matcher_3Drec.f90`) with its batches of prepared planes |
| D | `reconstructor_pcg` (`volume/simple_reconstructor_pcg.f90`) | `apply_normal_kernel`, `apply_precond`, `dot_real_volume` | `pcg_solve` (`opt/simple_pcg_solver.f90`) |

For each toy, its plan fixes the seam (which component holds the MLX state, what stays resident, where the
host waits) and lists the differences from SIMPLE. Family A's toy was refactored to this form by the roadmap's
rank 0b (run `mlxf_toy_arch`, 2026-11-24); its seam and its differences are in section 3.

## 3. Family A: polar matching

**What it computes.** For particle `i` and reference `j`, with the memoised ring transforms of SIMPLE
(`A = FFT(X·CTF)`, `C = FFT(CTF²)` per particle; `B = FFT(R)`, `D = conj(FFT(|R|²))` per reference), over the
angular bins `p` and shells `k`:

```
cross(p; i,j)  = sum_k w_k A(p,k,i) conj(B(p,k,j))        refpow(p; i,j) = sum_k w_k C(p,k,i) D(p,k,j)
euclid:  dist(r) = 1 + (refpow(r) - 2 cross(r)) / ptclpow(i)          w_k = k / sigma2(k)
cc:      corr(r) = cross(r) / sqrt(refpow(r) ptclpow(i))              w_k = k
```

with `cross(r)` and `refpow(r)` the inverse real transforms over `p` at the `nrots` rotations. The two
objectives share the contraction and differ in the weights and the finishing formula.

SIMPLE has two correlations (read at `d354efee2`, 2026-11-24). The memoised one (`gen_corrs`) carries no
shell weight: `w_k = 1`, normalised by the particle's unweighted power. The direct double-precision form and
the shift map's weight by `k`, as written above. A4's plan says which one its kernel reproduces; the oracle
has both ([`mlxf_oracles2.md`](mlxf_oracles2.md), section 9.1.4).

**Its three degrees of freedom.**
- **Which pairs.**
  - Dense: every reference, as large matrix products. This is milestone 1's kernel.
  - Arbitrary sets: per-particle lists, covered by tiles of particles × references. Only the tiles that
    hold a needed pair are computed, with the unneeded pairs masked (`mlx_gather_mm`,
    `mlx_block_masked_mm`).
  - Efficiency is tile occupancy: needed pairs over computed pairs. It depends on ordering particles by
    orientation and references along their spiral.
- **Which shifts.**
  - None, or one per particle: a phase on the particle side. `C` does not change.
  - A lattice of shifts: the same kernel on U shifted copies. This replaces the Fourier-Bessel shift map.
- **Which reduction.**
  - Per pair: the best rotation and its score; a keyed posterior draw; a map's mode, loss, width and
    optional evidence.
  - Per particle, across references: the best, the best k, or a draw.

**What exists.** In `src/test/`:
- `mlxf_toy_polarft_calc.f90`, the toy `polarft_calc`, with its submodules `mlxf_toy_polarft_core` (`new`,
  `kill`), `_memo` (the setters and the memoization), `_block` (`score_block_posterior`, the submission and
  collection of a block) and `_shiftmap` (`new_shiftmap`, `setup_shiftmaps`, `gen_shiftmap`, `shiftmap_mode`);
- `mlxf_toy_polarft_workspace.f90`, the type `polarft_workspace` that holds every MLX handle and compiled
  function, with its submodules `_lifecycle`, `_score` (the dense score with its compiled tail and tiling) and
  `_shiftmap` (the Fourier-Bessel maps);
- `mlxf_toy_eul_prob_tab.f90`, the driver `eul_prob_tab` with `fill_tab_range`;
- `mlxf_oracle_polar.f90`, the oracle, and `mlxf_bench_polar_table.f90`, the benchmark, whose suites fill
  their tables through the driver.

The unit fixture keeps SIMPLE's structure at small size (pftsz 32, 10 shells).

**The seam** (measured at case `2500_4`: 10,000 references per half, 2,000 particles, pftsz 182, 61 shells,
tile plan 64 by 250, on the M5 Ultra):
- **Who owns the device state.** `polarft_calc%ws`, one `polarft_workspace` per reference parity, made in
  `new` and released in `kill`. Nothing else holds an MLX handle: the driver and the fixtures hold none.
- **What is resident, and from when.** The reference tiles of both parities, 7.14e9 B (*derived*: 2 parities
  of 40 tiles of 244 by 500 by 183 single-precision values), from `memoize_ref_bins` until `kill_ref_bins`,
  `kill` or the next `memoize_ref_bins`: one iteration of a part process. A shift map adds 2.63e9 B for both
  parities (*measured*: 9.77e9 B of active memory with the tiles) from `new_shiftmap` or `setup_shiftmaps`
  until `kill_shiftmap`. A block in flight holds its graph: the MLX peak is 10.26e9 B while a half of 1,000
  particles is scored, and MLX keeps 3.28e9 B in its cache afterwards (*measured*).
- **What stays on the host.** The memos of the references (`ft_ref`, `ft_ref2`, both parities: 3.57e9 B) and
  of the particles (0.36e9 B) (*derived*). The raw sections do not stay: the setters stage 64 at a time and
  memoize them.
- **Where the host waits.** In `memoize_ref_bins` and `new_shiftmap` (the tiles and the maps' tables are
  evaluated), in `collect_block` (a block's entries are copied out; `score_block_posterior` is a submission
  and its collection), and in `shiftmap_mode`, once per tile of particles. `submit_block` returns while the
  device works, so one block or two can be in flight.
- **What a part process holds.** 20.81e9 B of peak footprint for all 2,000 particles and 20.11e9 B for a third
  of them (*measured*): the references dominate, and each part holds all of them.

**Differences from SIMPLE** (read at `d354efee2`; the ledger `scripts/toy_mirror.txt` lists every procedure
as mirrored or as an addition with its reason):
- **Dummies dropped:** `new` has no `nmany_refs` and `fftw_measure`; `memoize_refs` no `eulspace`;
  `new_pipeline` no `block_memo`. `params` is the record `parameters` of the test definitions, with SIMPLE's
  member names for the members read (`pftsz`, `box`, `nthr`, `prob_beta`, `shift_sigma`, `smpd`, `trs`).
- **Kinds:** `set_ref_pft` takes its section in `complex(real64)`, because the benchmark's reference rings
  are double precision and rounding them changes the scores' bits; `parameters%prob_beta` is `real(real64)`.
- **Shapes:** a section spans the shells `kfromto(1):kfromto(2)` (SIMPLE's reach `interpklim`). `gen_shiftmap`
  and `shiftmap_mode` take the pairs of a block as rank-1 arrays, every particle's candidates in turn.
- **Public where SIMPLE's are private:** `set_ptcl_ctfmat`, `new_shiftmap`, `kill_shiftmap`. The fixtures hand
  their map grids in through `new_shiftmap`; `setup_shiftmaps` builds SIMPLE's grids by SIMPLE's rule.
- **Staging:** `pfts_refs`, `pfts_ptcls` and `ctfmats` hold 64 sections, not every section, and a particle's
  CTF is set before its section. The weighted square sum is made in `memoize_ptcls`.
- **The block:** all the references in their order (`irefs` = 1..`nrefs`; arbitrary lists are deliverable
  K3's), any number of particles of one half, tiled by `set_tile_plan`; SIMPLE's block is at most 16
  particles against tiles of 32 references.
- **What the fixture hands in through additions:** the shell weights `k / sigma2` (`set_sigma2_weights`;
  SIMPLE is given the spectra), the keys of the draws (`set_draw_keys`; SIMPLE takes its scope from the
  iteration), the dense temperatures (`set_temps`), the maps' candidates (`set_candidates`; SIMPLE's pool
  selects them) and, when it has one, its own map (`use_shiftmap`).
- **The maps:** they are built on the device when `shiftmap_mode` reads them, tile by tile; `gen_shiftmap`
  records the pairs. There is no `shiftmap_shift`, no `shiftmap_draw` and no in-cell refinement.
- **The driver:** one thread walks the blocks, one or two in flight on the device (SIMPLE: an OpenMP loop
  over the blocks); `new_pipeline` takes the calculator where SIMPLE takes its builder; no assignment, no
  states, no diagnostics. `set_fill_stages` lets the benchmark run the dense score or the maps alone.
- **Refusals:** where SIMPLE stops, the toy returns with a reason in `message()` and SIMPLE's invalid values
  in the results. The types have a `final` procedure where the house rule asks for one.

**What is new** (the deliverables of section 8):
- **A1, the fused tail.** One Metal kernel per pair row: the inverse real transform, the finishing formula
  and the reduction. In the profile at the verdict plan, the tail (distances and draw) is the largest stage:
  0.90 of 1.93 s, with a barrier after each stage (*measured*).
- **A2, arbitrary reference sets,** by tiles.
- **A3, the shift lattice,** with the map reductions. Two variants:
  - **Particle-side shifts:** one ring transform per (particle, shift), shared by all that particle's
    references. It samples SIMPLE's polar grid rotated by each rotation's angle. It therefore agrees with
    SIMPLE's map in distribution, not cell by cell.
  - **Reference-side shifts:** SIMPLE's exact cells, at one ring transform per (reference, shift), about
    1 Mflop at pftsz 182 and 61 shells (*derived*: 61 complex transforms of length 364). It pays only where
    many particles share the reference.
- **A4, the cc finish and the classic reductions:** the best pair, the best k, and the first improvement in
  a keyed random order (stochastic hill climbing evaluated in full, then decided in the CPU's order).

**Oracle.** The existing double-precision oracle, extended by direct evaluation at each shift. For A3, the
reference-side variant must also reproduce the Fourier-Bessel oracle's cells.

**Library needs.** The custom Metal kernel (A1); `mlx_gather_mm` or `mlx_block_masked_mm` (A2);
`mlx_argpartition` or `mlx_topk` (A4). Matrix products, the ring transforms and `mlx_take` exist.

**Numbers in hand.**
- **Dense score:** 1.76e7 pairs/s on the GPU against 3.75e6 on 30 threads (*measured*).
- **Fourier-Bessel maps on the GPU:** 7.46e4 (window) and 1.99e4 (screen) maps/s, against SIMPLE's 1.09e5
  and 2.05e4 (*measured*).
- **Direct shifts on the half ring:** 0.50 (window) and 0.77 (screen) of the multiply-adds of SIMPLE's
  Fourier-Bessel form at the M5 grids (*derived*).
- **Break-even tile occupancy** against 30 threads: about 21 % (*derived*: 1/4.69, if a masked tile costs
  what a dense one does).
- **Resident references** at pftsz 182, 61 shells, 2,500 directions, both halves: 0.9 GB per state
  (*derived*), before the scorer's reordered copy.

**Open decisions.**
- A3's variant: particle-side or reference-side shifts.
- Whether a pair's arithmetic may depend on its tile. This fixes what repeatability can promise for
  arbitrary sets.
- Which reductions enter first.
- The tile shapes.

## 4. Family B: the 3D Fourier gather

**What it computes.** Samples of a padded 3D Fourier volume at rotated coordinates, by a separable window.

- **B1, the polar projection** (the reprojection model).
  - Each output sample (direction, shell, angle) reads 27 voxels through a Kaiser-Bessel window of three
    per axis, with weights from a polynomial, normalised per axis.
  - No two outputs share a destination.
  - The output, followed by ring transforms, is family A's reference operand. Projected on the GPU, the
    references never leave GPU memory.
- **B2, the pose objective of continuous refinement.** For one particle at one trial pose, every pixel of
  the half plane reads 27 voxels through a quadratic B-spline window, three taps per axis around the nearest
  grid point, giving the value and three derivatives. The kernel forms the residual of the CTF-weighted,
  shifted model against the particle and reduces to the objective, a 5-component gradient and a 5 × 5 matrix.
  - The five parameters are a rotation-vector increment applied on the right of the current rotation, and
    two shifts.
  - The matrix SIMPLE returns is the Gauss-Newton matrix times a clamped regression slope, not the plain
    Gauss-Newton matrix.
  - Corrected on 2026-11-24 from a reading of `gather_packed_bspline3_window_grad` and `pose_normal_terms`
    at `d354efee2`: this note first said 64 voxels and a cubic window.
  - Fused, one threadgroup serves one (particle, pose) and returns 21 numbers.
  - The optimizer runs in lockstep across particles, with its small step solved on the host in double
    precision.

**SIMPLE anchors** (reading references only): `fproject_polar_batch_opt`
(`image/simple_projector_pft_batch.f90`), `apod_fast_device` (`interp/simple_kbinterpol.f90`),
`memoize_one_ref` (`pftc/simple_polarft_memo.f90`); `pose_normal_terms` and
`gather_packed_bspline3_window_grad` (`cftc/simple_cartft_calc.f90`).

**Fixture and oracle.**
- **B1** takes example 3 of the scientific examples note as designed:
  - the asymmetric two-blob phantom on 6³, padded to 12³;
  - three explicit rotations;
  - an independent host matrix G built from scalar geometry;
  - its negative controls.
- **B2** adds a host double-precision B-spline evaluation of the objective, gradient and Gauss-Newton
  matrix at planted poses, and a recovery test: the lockstep optimizer returns planted poses within a frozen
  bound.

**Forms.** Graph: geometry and weights by ordinary operations, a 27-entry gather (`mlx_take`), a
reduction. Fused: one Metal kernel per family member.

**Library needs.** The custom Metal kernel; `mlx_take` (exists); `mlx_rfftn` for the volume transform at
bench size (the small fixture can use a host transform).

**Numbers in hand** (all *derived* from the code at `d354efee2`, unless tagged otherwise):
- **B1:**
  - about 480 flop and 27 reads per sample;
  - 26.6 GFLOP for 2,500 directions, both halves, pftsz 182, 61 shells, one state;
  - the padded volume is 132 MB as a Hermitian half at box 160;
  - SIMPLE's CPU reaches about 12 ns per sample at the margin (*derived* from a recorded run).
- **B2:** about 0.5 kflop per pixel, so about 3 Mflop per pose evaluation at 62 shells (about 6,000 pixels
  of the half plane). This is a rough count for 27 taps, to be redone in K5's plan; it replaces 2.1 kflop and
  13 Mflop, which assumed 64 taps.

**Open decisions.**
- Whether B1 writes straight into family A's layout or through an intermediate array.
- B2's accumulation precision on the GPU: float32 trees, or compensated sums.
- How the toy's lockstep optimizer treats converged particles.

## 5. Family C: the 3D Fourier scatter

**What it computes.** The adjoint of B1 with weights. Each Fourier component of each particle plane adds a
complex value (CTF times data) and a real weight (CTF²) to the 27 voxels around its rotated position, for
every inserted pose and symmetry copy. Planes in different orientations overlap everywhere, most of all at
low frequency.

**SIMPLE anchors:** `insert_plane_oversamp` (`volume/simple_reconstructor.f90`), `calc_3Drec`
(`strategies/search/simple_matcher_3Drec.f90`). SIMPLE's CPU avoids races by colouring lines within one
plane, so its result is identical at any thread count.

**An easy win, with a head start** (Hans, 2026-11-24). SIMPLE already holds GPU code for this step, the
batched offload insertion `calc_3Drec_gpu` (`volume/simple_reconstructor_openmpoffload.f90`), which
demonstrates the acceleration. Its structure is the toy's starting point:
- batches of packed planes;
- one GPU thread per plane and symmetry copy;
- grids that stay resident;
- the next batch prepared on the CPU while the kernel runs.

Its update of shared voxels is unprotected. The toy replaces that update with one of the forms below.

**Forms to compare.**
1. `mlx_scatter_add`: atomic additions, whose order changes from run to run. Its repeatability is measured,
   not assumed.
2. Sort the samples by voxel, then a segmented sum (`mlx_argsort`, the scans, gathers): deterministic by
   construction.
3. A tiled Metal kernel: samples sorted into blocks of the grid, one threadgroup per block accumulating in
   threadgroup memory in a fixed order. Deterministic, and able to follow the CPU's order.

**Fixture and oracle.** Example 3's adjoint part as designed:
- the adjoint identity against B1, `<G z, y> = <z, G^H y>`, tested against the independent host matrix;
- the numerator and the density tested separately;
- the packed Hermitian half against the full grid;
- the collision and repeatability measurements.

**Library needs.** `mlx_scatter_add`, `mlx_argsort`, the scans (parity Phases 2 and 3); the custom Metal
kernel.

**Numbers in hand** (*derived* from the code and a recorded run):
- about 550 flop per inserted sample, 58 % of it the window weights, and 81 float accumulations;
- about πN²/8 + 2N samples per pose and symmetry copy, so 5.7 Mflop at N = 160;
- SIMPLE's CPU reaches about 1.9 GFLOP/s per thread.

**Open decisions.**
- Whether bitwise identity with the CPU's order is required, or repeatability on the GPU is enough.
- The block size of form 3.

## 6. Family D: the PCG solve

**What it computes.** SIMPLE's `rec_backend=pcg`: the regularised normal equations of reconstruction, solved
by preconditioned conjugate gradients on volumes.
- **The operator:** pad the N³ volume to (2N)³, a forward real transform, a multiplication by the real kernel
  transform plus the prior, the inverse transform, a crop, the regulariser and the support window.
- **The preconditioner:** an envelope, the same pad and transforms around a division by the density plus a
  floor, a crop, the envelope and a mask.
- **The solver:** standard conjugate gradients. SIMPLE computes the dot products and step sizes in double
  precision.

**Why it fits** (Hans, 2026-11-24: "It is made for it. If it can be made to run very fast, we might just use
it all the time"). Every step is a 3D transform, element-wise work or a reduction, on volumes that never
leave the GPU. Only two or three scalars per iteration reach the host. The halves and the states are
independent, so they batch.

**SIMPLE anchors:** `apply_normal_kernel`, `apply_precond` and `dot_real_volume`
(`volume/simple_reconstructor_pcg.f90`), `opt/simple_pcg_solver.f90`, `volume/simple_pcg_lattice.f90`.

**Fixture and oracle.** The PCG problem of the scientific examples note (its section 4, part B) as designed:
- N = 4 padded to 8;
- the explicit 64 × 64 stencil matrix built on the host, not by applying the device operator;
- a manufactured solution solved independently by host Cholesky;
- the true residual recomputed by the host matrix;
- the termination and indefiniteness gates;
- a 16³ named-only variant for residency.

**Forms.** A graph form only, at first: `mlx_rfftn` and `mlx_irfftn`, element-wise operations, padding and
cropping by slices, reductions for the dot products. The transforms dominate, so a fused kernel is not
expected to pay; that is measured before any is written.

**Library needs.** The n-dimensional FFTs (roadmap rank 1b). Nothing else: no custom Metal kernel.

**Numbers in hand** (*derived* from the code at `d354efee2`):
- a solve of m iterations from a zero start takes 2 + 4m padded transforms: 10 at SIMPLE's 2 iterations;
- one half's assembly takes 21 in all: 1 to close the accumulation, 2 to finish the kernel transform, the
  solve's 10, 2 for the closed-form pair under the prior, and 6 that only compute diagnostic residuals;
- that is 42 per state: about 86 GFLOP at N = 160 and 380 GFLOP at N = 256, if all are of the padded size
  (2N)³, which K8's plan confirms against the code before it budgets anything;
- the solve holds about 170·N³ bytes per half: 1.4 GB for both halves at N = 160, 5.7 GB at N = 256;
- the work is bound by memory traffic, about 2.3 flop per byte in the transforms.

**Open decisions.**
- The dot products on the GPU: float32 tree reductions, compensated sums, or block partials summed on the
  host in double. It matters more if PCG runs "all the time" with more iterations.
- Whether both halves, and several states, are solved as one batch.
- The largest volume the toy must time: 256 (padded 512) needs the 5.7 GB above plus the transforms'
  working memory.

## 7. Across the families

- **Residency chain.** Volume → B1 → ring transforms → A's references; particles → A → shifts and
  reductions. A chained test shows that references projected by B1 and scored by A agree with the host
  oracle end to end.
- **Several processes.** Every bench of families A to C is repeated at 3 and 6 simultaneous processes. If
  the total rate falls well below one process's, the design question of one GPU-owning process opens
  (roadmap, section 5). Family D runs in the master between iterations, when the parts are idle, so it is
  timed alone.
- **Memory per process.** References dominate (section 3). Each toy reports its resident and peak MLX
  memory under a fixed caller budget.

## 8. Deliverables and their order

| | Deliverable | Needs from the library | Exit |
| --- | --- | --- | --- |
| K1 | A1: the fused tail of the dense score | Metal kernel wrapper; the refactored polar toy and its baseline (roadmap rank 0b) | the polar-table checks pass on the GPU at their recorded counts; judged on the canonical driver's elapsed time against the compiled graph tail (roadmap decision 15), alone and at 3 and 6 processes |
| K2 | B1: the polar projection | Metal kernel wrapper; `mlx_rfftn` for the bench | the host matrix oracle and controls pass; the chained test with A passes; timed at 2,500 directions, pftsz 182, 61 shells |
| K3 | A2: arbitrary reference sets | `mlx_gather_mm` or `mlx_block_masked_mm` | listed pairs equal the dense kernel's; occupancy and rate reported for cone-shaped sets, with and without orientation order |
| K4 | A3: the shift lattice and the map reductions | K1's tail | the reference-side variant reproduces the Fourier-Bessel oracle's cells; a particle-side variant passes a decision-level test frozen before timing (roadmap decision 13); the chosen variant passes the map gates; timed against milestone 1's maps at the M5 grids |
| K5 | B2: the pose objective with gradient and Gauss-Newton matrix | Metal kernel wrapper | the objective, gradient and matrix match the host oracle; planted poses are recovered; evaluations per second timed |
| K6 | C: the insertion, three forms | `mlx_scatter_add`, `mlx_argsort`, the scans, Metal kernel wrapper; K2 | the adjoint identity, numerator and density pass; the repeatability gate is applied to each form, and only a form that passes it is kept (roadmap decision 14); timed. A protected-update probe on a collision-heavy fixture follows K2 directly |
| K7 | A4: the cc finish and the classic reductions | `mlx_argpartition` or `mlx_topk` | both objectives and each reduction match the oracle |
| K8 | D: the PCG solve | `mlx_rfftn`, `mlx_irfftn` | the operator matches the explicit matrix; the solution and true residual match host Cholesky; the termination gates pass; judged by the time to the same true residual at N = 160 and 256, with the iteration count and peak memory beside it |

The order K1 to K7 is accepted (roadmap decision 7). K8 entered afterwards. It needs only the n-dimensional
FFTs and its own files, so its proposed slot is right after K2; that slot is open to a veto. A deliverable
may start when the wrappers in its own row are public; it does not wait for the others' (the rule on
disjoint files and the maintainer's review between items still hold).

Why this order:
- K1 exercises the Metal kernel wrapper on the best-understood kernel, at the stage known to be largest.
- K2 is a pure gather with no write conflicts, and it feeds family A.
- K3 and K4 complete the search's discrete stage.
- K5 covers continuous refinement.
- K6 follows K2 in design, since the insertion is the projection's adjoint. SIMPLE's existing offload
  insertion shortens its work; its open question is the protected update.
- K8 is independent of the others and of the Metal kernel wrapper.

## 9. Before SIMPLE is touched

A family is ready for a SIMPLE plan when:
- its deliverables have passed their exits on the M5;
- its timings at 3 and 6 processes and its memory per process are recorded (family D is the exception: it
  runs in the master while the parts are idle, so it is timed alone);
- its open decisions above are ruled.

The SIMPLE plan is then written by SIMPLE's rules, with SIMPLE's CPU route as the comparator and its own
scientific gates.

## Progress

(none yet: design note)
