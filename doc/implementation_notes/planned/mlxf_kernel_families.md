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
- **In the shape of SIMPLE's integration.** A toy class is host files that import no MLX name, a glue submodule
  `<unit>_mlx` beside each host unit that crosses to the device (stubs in a build without `USE_MLX`), and device
  modules behind one opaque component (`doc/policies/toy_example_policy.md`, section 8; the ledger
  `scripts/toy_seam.txt` and rule `seam`). The three toys built so far have it (run `mlxf_toy_seam`, 2026-11-26);
  each family's section says where its seam runs through the files.
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
| A | `polarft_calc` (`pftc/simple_polarft_calc.f90` and its submodules) | `new`, `kill`, `reallocate_ptcls`, `set_ref_pft`, `set_ptcl_pft`, `set_ptcl_ctfmat`, `set_eo`, `memoize_refs`, `memoize_ptcls`, `memoize_ref_bins`, `score_block_posterior`, `new_shiftmap`, `setup_shiftmaps`, `kill_shiftmap`, `gen_shiftmap`, `shiftmap_mode`, and the inquiries `get_nrefs`, `get_pftsz`, `ptcl_iseven`, `wsqsum_ptcl_band` (built: `src/test/mlxf_toy_polarft_calc.f90`) | `eul_prob_tab` with `new_pipeline`, `fill_tab_range` (its steps `cut_blocks`, `process_block`, `finish_particle_map`) and `kill` (built: `src/test/mlxf_toy_eul_prob_tab.f90`); `eul_prob_tab_neigh` with `new_neigh_pipeline`, `fill_tab_range` (modes `geom` and `state`, covers route, dense and pairs) and `kill` (built by K3: `src/test/toys/polar/mlxf_toy_eul_prob_tab_neigh.f90`, with `srchspace_map` and `cone_view_dist`); later `shiftmap_srch` |
| B1 | `projector` (`image/simple_projector.f90`, `simple_projector_pft_batch.f90`) | `new`, `set_rmat`, `get_cmat`, `pad_fft`, `expand_cmat`, `is_expanded`, `kill_expanded`, `kill`; `fproject_polar_batch_opt` (built: `src/test/mlxf_toy_projector.f90`, `_workspace.f90`, `_pft_batch.f90`, K2) | the reprojection model's `vol_pad2ref_pfts_opt`, which fills `polarft_calc` through `set_ref_pft`, or on the toy's device route through the workspace (built: `src/test/mlxf_toy_polarft_core.f90`) |
| B2 | `cartft_calc` (`cftc/simple_cartft_calc.f90`) | `new`, `kill`, `set_ref`, `new_ptcls`, the particle setters, `pose_normal_terms`, `shift_normal_terms` | `cartft_pose_opt` (`cftc/simple_cartft_pose_opt.f90`) |
| C | `reconstructor` (`volume/simple_reconstructor.f90`) | `insert_plane_oversamp`, `compress_exp`, `sampl_dens_correct` | `calc_3Drec` (`strategies/search/simple_matcher_3Drec.f90`) with its batches of prepared planes |
| D | `reconstructor_pcg` (`volume/simple_reconstructor_pcg.f90`, with the members of `volume/simple_pcg_lattice.f90` it reads) | `new`, `kill`, `set_window_sphere`, `mask_mul`, `set_lambda_relative`, `end_accum`, `apply_normal`, `apply_normal_kernel`, `apply_precond`, `dot_real_volume`, `solve_accum`, `get_effective_lambda`, `get_solve_support` (built: `src/test/mlxf_toy_reconstructor_pcg.f90` and its glue `_mlx.f90`) | `pcg_solve` with `pcg_operator` and `pcg_solver_outcome` (`opt/simple_pcg_solver.f90`; built: `src/test/mlxf_toy_pcg_solver.f90` for the record, `mlxf_toy_pcg_solver_mlx.f90` for the device engine); the master's assembly in `simple_rec3D_pcg_strategy.f90` is the canonical driver |

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
  function, with its submodules `_lifecycle`, `_score` (the dense score with its compiled tail and tiling),
  `_tail` (the fused tail, a custom Metal kernel per tile, the form `metal`) and `_shiftmap` (the Fourier-Bessel
  maps);
- `mlxf_toy_eul_prob_tab.f90`, the driver `eul_prob_tab` with `fill_tab_range`;
- `mlxf_oracle_polar.f90`, the oracle, and `mlxf_bench_polar_table.f90`, the benchmark, whose suites fill
  their tables through the driver.

The unit fixture keeps SIMPLE's structure at small size (pftsz 32, 10 shells).

**The seam** (measured at case `2500_4`: 10,000 references per half, 2,000 particles, pftsz 182, 61 shells,
tile plan 64 by 250, on the M5 Ultra):
- **Who owns the device state.** `polarft_calc%ws`, one `polarft_workspace` per reference parity, made in
  `new` and released in `kill`. Nothing else holds an MLX handle: the driver and the fixtures hold none.
- **What is resident, and from when.** The reference tiles of both parities, 7.14e9 B (*derived*: 2 parities
  of 40 tiles of 244 by 500 by 183 single-precision values), made by `memoize_refs` (packed on the host from the
  memo, 3.57e9 B of staging per parity while one is uploaded, *derived*) and held until `kill_ref_tiles`, `kill`
  or the next `memoize_refs`: one iteration of a part process. A shift map adds 2.63e9 B for both
  parities (*measured*: 9.77e9 B of active memory with the tiles, again in run `mlxf_kernel_k4`; a lattice on the
  tiles would have held 7.15e9 B, no reference data of its own) from `new_shiftmap` or `setup_shiftmaps`
  until `kill_shiftmap`. A process scoring the maps of case `2500_4` has a peak footprint of 2.1e10 B; three
  share the GPU at 6.6e10 B summed (*measured*, K4). A block in flight holds its graph: the MLX peak is 10.26e9 B while a half of 1,000
  particles is scored, and MLX keeps 3.28e9 B in its cache afterwards (*measured*). With the fused tail the peak
  is 16.71e9 B: a cheap tail lets the host queue more tiles ahead of the device (*measured*, K1).
- **What stays on the host.** The one memo of the references (`ft_ref_terms`, both parities: 3.57e9 B) and the
  particles' memos (`ft_ptcl_ctf` and `ft_ctf2`, 0.36e9 B, which the maps read, and the terms `ft_ptcl_wterms`,
  0.36e9 B) (*derived*). The bin-major copy of SIMPLE's earlier layout (3.57e9 B more on the host backend) is
  gone. The raw sections do not stay: the setters stage 64 at a time and
  memoize them.
- **Where the host waits.** In `memoize_refs` and `new_shiftmap` (the tiles and the maps' tables are
  evaluated), in `collect_block` (a block's entries are copied out; `score_block_posterior` is a submission
  and its collection), and in `shiftmap_mode`, once per tile of particles. `submit_block` returns while the
  device works, so one block or two can be in flight.
- **What a part process holds.** 19.03e9 B of peak footprint for all 2,000 particles and 18.32e9 B for a third
  of them, bt 64 and the compiled tail (*measured* on the one memo layout, before the particle terms; 20.81e9 and
  20.11e9 B in the earlier layout, whose host packing staged the tiles twice); the particle terms add 0.36e9 B
  (*derived*). The references dominate, and each part holds all of them.

**The seam in files** (run `mlxf_toy_seam`; `scripts/toy_seam.txt`):
- **Host:** `mlxf_toy_polarft_calc.f90` and its submodules `_core`, `_memo`, `_block`, `_shiftmap`, and the driver
  `mlxf_toy_eul_prob_tab.f90`. They import no MLX name; `ws(:)` is `class(device_work)`.
- **Glue:** `mlxf_toy_polarft_core_mlx.f90`, `_memo_mlx.f90`, `_block_mlx.f90`, `_shiftmap_mlx.f90`: fifteen
  procedures `<name>_mlx`, each the body of one guarded call, with stubs under `#else`.
- **Device:** `mlxf_toy_polarft_workspace.f90` and its submodules, unchanged but for `extends(device_work)`.
- **The backend** is `parameters%l_mlx`, read at `new`. On the host backend `score_block_posterior` is a miniature
  of SIMPLE's block kernel in single precision (the sums per angular bin, each pair's inverse transform as a
  direct sum, SIMPLE's distances and posterior draw with the host's keyed variate), with per-thread work, and
  `fill_tab_range` runs the blocks under `!$omp parallel do`; on the MLX backend it submits and collects
  serially. The host route is a model of control flow, never timed. The shift maps and the device route of the
  references need the MLX backend.
- **What the host route is held to** (sub-suite `polarft_host`): the oracle `mlxf_oracle_polar` at the MLX
  backend's tolerances, the same bytes from a team of 1 and of 4 threads, and both branches of the fill within
  those tolerances on three seeds. The build without MLX (`test/offstate/`) fills the same table byte for byte.

**Differences from SIMPLE** (read at `28c753993`; the ledger `scripts/toy_mirror.txt` lists every procedure
as mirrored or as an addition with its reason):
- **Dummies dropped:** `new` has no `nmany_refs` and `fftw_measure`; `memoize_refs` no `eulspace` (mirrored
  references are not modelled). `params` is the record `parameters` of the test definitions, with SIMPLE's
  member names for the members read (`pftsz`, `box`, `nthr`, `prob_beta`, `shift_sigma`, `smpd`, `trs`).
- **Kinds:** `set_ref_pft` takes its section in `complex(real64)`, because the benchmark's reference rings
  are double precision and rounding them changes the scores' bits; `parameters%prob_beta` is `real(real64)`.
- **Shapes:** a section spans the shells `kfromto(1):kfromto(2)` (SIMPLE's reach `interpklim`). `gen_shiftmap`
  and `shiftmap_mode` take the pairs of a block as rank-1 arrays, every particle's candidates in turn.
- **Public where SIMPLE's are private:** `set_ptcl_ctfmat`, `new_shiftmap`, `kill_shiftmap`. The fixtures hand
  their map grids in through `new_shiftmap`; `setup_shiftmaps` builds SIMPLE's grids by SIMPLE's rule.
- **Staging:** `pfts_refs`, `pfts_ptcls` and `ctfmats` hold 64 sections, not every section, and a particle's
  CTF is set before its section. The weighted square sum is made in `memoize_ptcls`.
- **The memos:** SIMPLE's one layout and names: `ft_ref_terms (2nk, pftsz+1, nrefs, 2)` (rows 1..nk the
  transform of the squared modulus, rows nk+1..2nk that of the ring) and the particle terms `ft_ptcl_wterms`
  (rows 1..nk `w_k FT(CTF2)`, rows nk+1..2nk `-2 w_k FT(X.CTF)`), made at the end of `memoize_ptcls`; the host
  kernel reads both in place. `ft_ptcl_ctf` and `ft_ctf2` stay for the maps; there is no `ft_ptcl_terms` (the
  toy is euclid only until K7).
- **The tiles:** the device's copy of the one memo, made by `memoize_refs` on the MLX backend under the tile
  plan and tail set before it (on the device route from the device's memo `memo_terms`), released by
  `kill_ref_tiles` and asked for by `ref_tiles_current` (additions); `new_pipeline` refuses a calculator whose
  tiles are not current, where SIMPLE's block kernel stops on references that are not memoized.
- **The counters:** the toy keeps `ref_gen` (its maps and tiles check it), `ref_gen_tiles`, `ptcl_gen` and
  `ptcl_gen_memo`, which SIMPLE no longer has; they make a stale memo a refusal where SIMPLE trusts the caller.
- **The seed banks:** particle terms `(2nk, pftsz+1, nb)` with a shifted cross term, as SIMPLE's
  `memoize_shifted_ptcl` returns them; the toy makes them with the addition `shifted_ptcl_terms` from a
  fixture's shifted FT(X.CTF), where SIMPLE shifts and transforms the particle itself.
- **The weights:** `set_sigma2_weights` (an addition) invalidates the particle memo, and `memoize_ptcls` makes the
  terms again; SIMPLE's `memoize_sigma2_weights` remakes them itself when the particle memo is current.
- **The block:** any list of the references without a repeat (K3: on the MLX backend gathered from the resident
  tiles into list tiles of the same plan, every reference in order staying the dense route; on the GPU also a
  pair list through the pair-list kernel, `set_block_pairs`), any number of particles of one half, tiled by
  `set_tile_plan`; SIMPLE's block is at most 16 particles against tiles of 32 references.
- **What the fixture hands in through additions:** the shell weights `k / sigma2` (`set_sigma2_weights`;
  SIMPLE is given the spectra), the keys of the draws (`set_draw_keys`; SIMPLE takes its scope from the
  iteration), the dense temperatures (`set_temps`), the maps' candidates (`set_candidates`; SIMPLE's pool
  selects them) and, when it has one, its own map (`use_shiftmap`).
- **The maps:** they are built on the device when `shiftmap_mode` reads them, tile by tile; `gen_shiftmap`
  records the pairs. There is no `shiftmap_shift` (its rotation-free dummy list), no `shiftmap_draw` and no
  in-cell refinement; `shiftmap_shifts` (an addition, K4) hands over the modes' shifts in the reference's axes,
  what SIMPLE's callers compute with `shiftmap_shift` at the mode, and `batch_map_results` carries them. They read the
  memo's rows, and the reference power keeps the toy's order (`sum(c2 r2 w)`); SIMPLE's euclid power multiplies
  the weighted CTF term by the reference term, an order K4 revisits.
- **The driver:** one thread walks the blocks, one or two in flight on the device (SIMPLE: an OpenMP loop
  over the blocks); `new_pipeline` takes the calculator where SIMPLE takes its builder; no assignment, no
  states, no diagnostics. `set_fill_stages` lets the benchmark run the dense score or the maps alone.
- **The tail's form:** `set_tail_form` (an addition) selects the compiled graph form (the default, the
  reference and the CPU path) or the fused Metal kernel (the GPU only); SIMPLE has one form, on the CPU.
- **Refusals:** where SIMPLE stops, the toy returns with a reason in `message()` and SIMPLE's invalid values
  in the results. The types have a `final` procedure where the house rule asks for one.
- **The host route's additions:** `check_block_work` (asked before a team's region, where SIMPLE stops inside
  it), `copy_block_rows` (the tester's reader of a thread's last block) and the module function `keyed_variate`
  (SIMPLE's `rnd_keyed`, which the toy does not model). The host kernel takes blocks of at most 16 particles
  against tiles of 32 references, as SIMPLE's.

**What is new** (the deliverables of section 8):
- **A1, the fused tail.** One Metal kernel per pair row: the inverse real transform, the finishing formula
  and the reduction. In the profile at the verdict plan, the tail (distances and draw) is the largest stage:
  0.90 of 1.93 s, with a barrier after each stage (*measured*). Delivered by K1 and kept: one thread per pair,
  1.65 to 1.80 times the compiled tail's rate on the driver (section 8).
- **A2, arbitrary reference sets,** by tiles.
- **A3, the shift lattice,** with the map reductions. Two variants:
  - **Particle-side shifts:** one ring transform per (particle, shift), shared by all that particle's
    references. It samples SIMPLE's polar grid rotated by each rotation's angle. It therefore agrees with
    SIMPLE's map in distribution, not cell by cell (exactly at the rotations whose angle is a whole number of
    direction steps).
  - **Reference-side shifts:** SIMPLE's exact cells, at one ring transform per (reference, shift) and map
    shell: 30 transforms of length 364 on the maps' band (shells 2 to 31), not the 61 of the full band.
  - **K4's outcome** (run `mlxf_kernel_k4`, [report](../completed/mlxf_kernel_k4_report.md)): both were built as
    graphs on the dense score's resident tiles and reproduce the oracle's cells to float32 rounding (6.4e-7).
    The reference-side lattice reaches 0.18 of the Fourier-Bessel form's ceiling (construction 219 us per screen
    map against 33 us: nothing is shared at the benchmark's candidates) and was removed. The particle-side lattice
    is the fast one, 1.29 times the Fourier-Bessel graph on the canonical driver and 1.39 times its ceiling, but it
    failed the decision-level test (roadmap decision 13, ruled B): its start shifts differ from SIMPLE's by more
    than a map step more often than a control lattice turned by half a direction step, by more than one pair, in two
    of twelve judged rows (98 against 108 pairs summed), and was removed. The fused map reductions (four Metal
    kernels) gave 1.23 times the graph reductions, below the 1.30 a second path needs, and were removed. The
    Fourier-Bessel form with its compiled graph reductions stays.
- **A4, the cc finish and the classic reductions:** the best pair, the best k, and the first improvement in
  a keyed random order (stochastic hill climbing evaluated in full, then decided in the CPU's order).

**Oracle.** The existing double-precision oracle, extended by direct evaluation at each shift. For A3, the
reference-side variant must also reproduce the Fourier-Bessel oracle's cells.

**Library needs.** The custom Metal kernel (A1); `mlx_gather_mm` or `mlx_block_masked_mm` (A2);
`mlx_argpartition` or `mlx_topk` (A4). Matrix products, the ring transforms and `mlx_take` exist.

**Numbers in hand.**
- **Dense score:** 1.76e7 pairs/s on the GPU against 3.75e6 on 30 threads (*measured*).
- **Fourier-Bessel maps on the GPU:** 7.46e4 (window) and 1.99e4 (screen) maps/s, against SIMPLE's 1.09e5
  and 2.05e4 (*measured*); 7.84e4 and 2.02e4 in run `mlxf_kernel_k4` (the canonical driver of 32,000 maps per grid
  in 1.99 s, of which the graph reductions take 0.59 s: 29 %).
- **Direct shifts on the half ring:** 0.50 (window) and 0.77 (screen) of the multiply-adds of SIMPLE's
  Fourier-Bessel form at the M5 grids (*derived*), counting the shell sums only; the measured lattices (K4) are
  bound by their ring transforms and their products.
- **Break-even tile occupancy** against 30 threads: about 21 % (*derived*: 1/4.69, if a masked tile costs
  what a dense one does).
- **Resident references** at pftsz 182, 61 shells, 2,500 directions, both halves: 0.9 GB per state
  (*derived*), before the scorer's reordered copy.

**Open decisions.**
- A3's variant: decided by K4 (roadmap decision 13, ruled B): neither lattice is kept; the Fourier-Bessel form
  stays.
- Whether a pair's arithmetic may depend on its tile: answered by K3 (decision 4, measured). On the host and the
  CPU device a listed pair is the dense entry bit for bit in any list, block and team; on the GPU its bits move
  with the tile's width and the particles' grouping (not with a reference's position in a tile), so the GPU's
  promise is the tail's tolerance; repeatability holds for fixed lists, order, plan, device and build.
- Which reductions enter first.
- The tile shapes: for the list route K3 measured bt 64 and rt 64 the fastest at the 10-degree cone and for the
  `state` fill (fused tail; [report](../completed/mlxf_kernel_k3_report.md)).

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

**B1 as built (K2, 2026-11-25; [plan](mlxf_kernel_k2.md), [report](../completed/mlxf_kernel_k2_report.md)).** A toy
`projector` with the `image` procedures the reprojection calls, `fproject_polar_batch_opt` and a miniature
`vol_pad2ref_pfts_opt` on the calculator. Two forms of the gather: the graph (27 positions and weights per sample,
one `mlx_take`, a sum), kept as the reference and the CPU path, and one fused Metal kernel with a thread per
sample, **kept: 24 times faster on the reprojection of a state at one process (0.040 s against 0.97 s for 2,500
directions of both parities), 5.3 and 6.3 times from go to the last exit at three processes** (*measured*). Two
routes into family A: the host route through `set_ref_pft` (the reference) and a device route (`set_ref_route`)
on which the projected bank, the ring transforms and the tiles never leave the device, **kept: 0.03 s against
1.05 s from the evaluated banks to the reference bins** (*measured*). Accuracy: 1.5e-6 of a sample's terms on the
small fixtures, 1.45e-5 at the bench (the float32 coordinates near 124), 4e-7 of a row on the chained dense score.

**The seam** (measured at the bench: box 160 padded to 320, pftsz 182, 61 shells, 2,500 directions, one state):

| Question | Answer |
| --- | --- |
| Who owns the device state | `projector%ws` (the padded transform, the expanded cube, the fused kernel's objects), made in `new`, released in `kill`; the bank passes to `polarft_calc%ws(ieo)` in `vol_pad2ref_pfts_opt` on the device route. No tester, benchmark or driver holds a handle |
| What is resident, and from when | From `expand_cmat` to `kill_expanded`: the expanded cube, 274,625,000 B (*derived*), one parity's at a time; the padded transform (131,891,200 B) from `pad_fft` to `expand_cmat`. On the device route the two banks, 444,104,960 B (*measured* active memory after the driver), until `memoize_refs` makes their memos and `memoize_ref_bins` the tiles (1.79e9 B for both parities, as on the host route) |
| What the projection adds | In flight, a graph tile (MLX peak 2.00e9 B at 64 directions) or nothing beyond the bank (MLX peak 1.94e9 B with the fused form) (*measured*) |
| What stays on the host | The two real volumes (16,384,000 B each) and the padded projector's real cube (131,072,000 B), the staging of its transform; the calculator's host memos (0.89e9 B) are allocated by `new` on either route |
| Where the host waits | `pad_fft` (the transform), `expand_cmat` (the cube), the projection (the bank; on the host route also its copy to `refs_state`), `memoize_refs` on the device route (the memos), `memoize_ref_bins` |
| What a part process holds | Peak footprint 4.15e9 B (fused) and 5.21e9 B (graph) for the reprojection; 9.36e9 B (host route) and 12.69e9 B (device route, 11.3e9 B of it MLX's cache) to the reference bins and a dense score (*measured*) |

**The seam in files** (run `mlxf_toy_seam`): `mlxf_toy_projector.f90` and `mlxf_toy_projector_pft_batch.f90` are
host files, with the glue `mlxf_toy_projector_mlx.f90` (nine procedures) and `mlxf_toy_projector_pft_batch_mlx.f90`
(two); the device module is `mlxf_toy_projector_workspace.f90`. On the device route the batch projector hands the
calculator a `projector_bank`, a device type of the workspace's module, as `class(device_work)`; the calculator's
glue resolves it and refuses another type. There is no host route: `new` with `l_mlx` false is refused with "the
toy has no host route" (SIMPLE's host projector exists and is not modelled here).

**Differences from SIMPLE (B1)** (read at `d354efee2`; the ledger lists each):
- **Types.** `projector` does not extend an `image` class: it carries the `image` procedures the reprojection
  calls (`new`, `set_rmat`, `get_cmat`, `pad_fft`, `kill`). `eulspace` is an array of rotation matrices
  `(3, 3, nspace)`, not an `oris` object.
- **The backend.** `new` takes an optional `params` after SIMPLE's dummies, for `l_mlx` (SIMPLE's classes read
  their parameters object without a dummy); `set_message` lets the batch projector keep its refusals with the
  projector's.
- **Dummies dropped:** `new`'s `wthreads`, `fft_nthreads`, `fft_measure`; `fproject_polar_batch_opt`'s
  `mirr_proj`. `fproject_polar_batch_opt` takes `vol_pad` with `intent(inout)` (its workspace builds kernels and
  adds seconds); `get_polar_coords` and `get_ref_pft` take `self` with `intent(inout)` (refusals); `get_cmat` is
  not pure (it copies from the device).
- **Members.** `cmat_exp` is a device array in `ws`; `ws` is public as SIMPLE's `cmat_exp` is; the padded
  transform is not kept after `expand_cmat`; there is no `kbwin` object (the window's 15 coefficients are
  computed in double precision and rounded once). `kill` releases the whole workspace, the cube with it, so
  SIMPLE's `kill_expanded` after `kill` finds nothing.
- **The transform** of `pad_fft` is the device's (`mlx_rfftn`, times the float32 reciprocal of M³), not FFTW's;
  the expansion is made by device gathers.
- **The fill.** SIMPLE writes the bank into a section of `pfts_refs`. The host route hands each section to
  `set_ref_pft` in `complex(real64)`; the device route (`set_ref_route`, an addition) hands the bank to the
  workspace, makes the memos by float32 FFTs there, and refuses the shift maps.
- **The loop** of `read_mask_filter_reproject_refvols` is written by the tester and the benchmark in SIMPLE's
  order; no centring, mask, filter or low-resolution blend.
- **Tiles and forms:** `set_fproject_form`, `set_fproject_tile`; SIMPLE has one loop nest and an offload
  directive. Seconds by `fproject_seconds`. Refusals through `message()` where SIMPLE stops; `final` procedures
  where the house rule asks for them.

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
  - the padded volume is 132 MB as a Hermitian half at box 160 (the expanded cube SIMPLE reads, and the toy
    keeps, is 274.6 MB: K2);
  - SIMPLE's CPU reaches about 12 ns per sample at the margin (*derived* from a recorded run).
- **B2:** about 0.5 kflop per pixel, so about 3 Mflop per pose evaluation at 62 shells (about 6,000 pixels
  of the half plane). This is a rough count for 27 taps, to be redone in K5's plan; it replaces 2.1 kflop and
  13 Mflop, which assumed 64 taps.

**Open decisions.**
- Closed by K2: B1 writes a bank of sections (the intermediate array), from which the device route makes the
  memos and the tiles on the device; the chain costs 0.03 s, so a kernel that writes ring transforms or tiles
  directly is not needed.
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

**The protected-update probe (K2's Phase 5, roadmap decision 14).** One thread per (pixel, plane) with 81 atomic
float32 additions per pixel, at n = 160 with two batches of 500 planes (2.84e8 deposits): 0.037 s per batch
(seeded orientations), against 0.0042 s for plain read-modify-write additions, which lose 59 % (98 % with one
orientation) of the density's mass. Against the gridding oracle the error is 1.07e-4 of a voxel's terms (8.1e-5
with one orientation), above the probe's cap 1e-5: **outcome C by decision 20's letter**. The same deposits in
double precision from float32 coordinates differ from the oracle by 1.09e-4 and 8.1e-5, so the excess is the
coordinates' rounding, which every form on float32 coordinates shares; the atomic update itself varies by at most
2.4e-6 between runs and is not bit-repeatable (49 % and 1.8 % of the voxels differ): **B in character**. **Ruled B**
(Hans, 2026-11-25: "B for the probe, keep the defaults"): K6 needs a deterministic form, the atomic kernel its speed reference.


**Open decisions.**
- Whether bitwise identity with the CPU's order is required, or repeatability on the GPU is enough.
- The block size of form 3.
- After the probe (ruled B): K6 requires a deterministic form, with the atomic kernel as its speed reference; its
  cap is judged against a reference on the kernel's own float32 coordinates (or coordinates kept in double).

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
- (K8) Answered: the scalars as line sums added in double (S2, within 6.4e-9); two waits per iteration (a wait costs
  0.17 ms); n = 256 timed (MLX's peak 1.14e10 B). Open: the halves and states as one batch; SIMPLE's own record at
  these boxes; the preconditioner of SIMPLE's `finalize_density_accum` on full coverage (worse iterates at 2 and 5,
  reported for SIMPLE).

**K8, delivered 2026-11-25** (run `mlxf_kernel_k8`, M5 Ultra; [report](../completed/mlxf_kernel_k8_report.md)). A toy
`reconstructor_pcg` (`src/test/mlxf_toy_reconstructor_pcg.f90`, its device state in
`mlxf_toy_reconstructor_pcg_workspace.f90`) and the engine `pcg_solve` (`mlxf_toy_pcg_solver.f90`): one half's
assembly from the raw packed accumulators to the shipped map, under SIMPLE's names, with the graph form only.

**The seam in files** (run `mlxf_toy_seam`, 2026-11-26, after rulings R1 and R2 of its Phase 6 stop):
- **Host:** `mlxf_toy_reconstructor_pcg.f90` (the envelopes, the window and its mask, the density's shell
  statistics, the options and the stop of the solve, the window at the start and at the exit) and
  `mlxf_toy_pcg_solver.f90`, which keeps the record `pcg_solver_outcome`.
- **Glue:** `mlxf_toy_reconstructor_pcg_mlx.f90`: eighteen procedures `<name>_mlx`, the device forms of the
  operator's five procedures (private there), and the adapter the engine solves through.
- **Device:** `mlxf_toy_reconstructor_pcg_workspace.f90`, and the engine `mlxf_toy_pcg_solver_mlx.f90`
  (`pcg_operator`, which extends `device_work`, and `pcg_solve`).
- **The five operator procedures keep SIMPLE's host arrays.** `mask_mul`, `apply_normal`, `apply_normal_kernel`,
  `apply_precond` and `dot_real_volume` take and return host volumes with SIMPLE's dummy lists; each is a guarded
  call whose glue sends the volume to the device, applies the device form and brings the result back. The solve
  does not go through them: the adapter calls the device forms, so its graph and its bytes are those of K8.
- **The operator for a caller on the device.** `get_pcg_operator` (an addition) hands the adapter out as
  `class(device_work)`; the testers and the benchmark resolve it to `pcg_operator` and apply it to device vectors
  without a host round trip.
- **No host route:** `new` with `l_mlx` false is refused with "the toy has no host route", and so is each of the
  five (SIMPLE's host solve exists and is not modelled here).

**The seam, with measured bytes** (*measured* at n = 160 and 256, the GPU, MLX 0.32.4):
- **Who owns the device state:** `reconstructor_pcg%ws`, made in `new` and released in `kill`; the engine holds `x`,
  `r`, `p`, `hp` and `z` for the length of one `pcg_solve`. After `kill` MLX's active memory is 0.
- **What is resident** from `end_accum` to `kill`: the kernel and the preconditioner's spectra, the envelope, the mask
  and the right-hand side (2.6e8 B and 1.08e9 B *derived* for one half with the solve's vectors). **What a solve
  peaks at:** MLX's peak 3.39e9 B (n = 160) and 1.14e10 B (n = 256) under SIMPLE's 2 and 5 iterations, 1.47e10 B at
  n = 256 under 28 to 200; the transforms' working memory dominates (one padded pair alone peaks at 6.0e9 B at 512³).
  The process's footprint with the fixture's generator: 2.24e10 B and 2.78e10 B.
- **What crosses:** in, `B` and `D` once (`set_raw_accum`, no host copy) and a non-zero start; out, per wait the
  inner products' n² line sums, and the map. **Where the host waits:** once at the end of `end_accum`, once before
  the loop, twice per iteration, once for the map: 7 waits under F2, 13 under F5; a wait costs 0.17 ms.
- **Host work that stays host work:** the density's shell statistics (the ridge's scale, the preconditioner's
  floors and thresholds) over a view of the device's density, the window and the mask, the stop tests. At n = 256
  the statistics and the finalisation's graph take about 0.17 s of `end_accum`'s 0.23 to 0.25 s.

**Differences from SIMPLE** (each is a line of `scripts/toy_mirror.txt` or below):
- One type: the lattice's members (`box`, `boxpd`, `padf`, `pad_off`, `Rnat`, `padsc`, `iwinsz`, `dep1d`, `mask`,
  `window`, `l_mask`) are `reconstructor_pcg`'s, public as `pcg_lattice`'s are; `set_window_sphere` and `mask_mul`
  are bound to it.
- `new(box, lambda)` drops `smpd` and `fft_nthreads` and takes an optional `params` for the backend;
  `end_accum(l_kernel)` drops `d_raw` and refuses the matrix-free operator; `solve_accum` keeps SIMPLE's eight
  dummies with `solve_core` folded in.
- `mask_mul`, `apply_normal`, `apply_normal_kernel`, `apply_precond` and `dot_real_volume` have SIMPLE's host
  arrays and dummy lists, and each body is a round trip to the device. `self` is `intent(inout)` in all five, so
  that a refusal leaves its message (SIMPLE's `mask_mul` and `dot_real_volume` are pure). `dot_real_volume` adds
  the device's float32 sums of the n² lines in double, where SIMPLE adds the products in double.
- The engine's `apply`, `precond` and `dot` take and return device arrays, and `dot` returns the n² line sums (the
  engine adds them in double). The engine is the device half, `mlxf_toy_pcg_solver_mlx`; its operator extends
  `device_work` and has a `kill`.
- The operator embeds at the corner of the padded cube through the transform's length (a translation of SIMPLE's
  centre embedding, which the Fourier multiplier does not see).
- Where SIMPLE stops (`THROW_HARD`), the toy returns with `x` untouched and the reason in `stop_reason` and
  `message`; the engine does not precondition after its last iteration under `maxits`.
- Additions: `set_raw_accum` (the master's reduction of the parts' files), `copy_spectra` and `copy_volumes`
  (the testers' readers), `message`, `stage_seconds`, `host_waits`, `get_pcg_operator`; the workspace's bindings.

**Numbers in hand** (*measured*, Release, the GPU, the canonical driver from `set_raw_accum` to the map on the host,
best of three, two invocations bit for bit equal; seed 1 of the full-coverage fixture):

| n | System, rule | Iterations | Driver | end_accum | Solve | Per iteration | MLX peak |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 160 | P, F2 (production) | 2 | 0.084 s | 0.060 s | 0.023 s | 0.012 s | 3.39e9 B |
| 160 | P, F5 (final) | 5 | 0.105 s | 0.058 s | 0.047 s | 0.009 s | 3.39e9 B |
| 256 | P, F2 | 2 | 0.332 s | 0.247 s | 0.085 s | 0.043 s | 1.14e10 B |
| 256 | P, F5 | 5 | 0.413 s | 0.231 s | 0.182 s | 0.036 s | 1.14e10 B |
| 160 | R, E (reported) | 31, `xtol` | 0.320 s | 0.060 s | 0.260 s | 0.008 s | 3.69e9 B |
| 256 | R, E (reported) | 28, `xtol` | 1.203 s | 0.251 s | 0.952 s | 0.034 s | 1.47e10 B |
| 160 | R, R4 (reported) | 200, `maxits` | 1.672 s | 0.057 s | 1.614 s | 0.008 s | 3.70e9 B |
| 256 | R, R4 (reported) | 200, `maxits` | 6.818 s | 0.247 s | 6.571 s | 0.033 s | 1.47e10 B |

MLX's CPU device with the same graph: 1.99 s (F2) and 3.82 s (F5) at n = 160, 8.52 s (F2) at n = 256, one core busy: the GPU 24 to 36 times faster. The transforms are 46 to 50 % of the solve under F2 and 64 % under
F5; no fused kernel, wait-free or compiled form can gain 30 % on the driver (the ceilings 1.13 to 1.19); the
inner products' line sums added in double are within 6.4e-9 of the double sum. SIMPLE was not measured: no record of
a PCG solve at box 160 or 256 is in hand.

**On this fixture SIMPLE's preconditioner (9.4) makes the iterates worse, not better:** after 2 and 5 iterations of
system R the error against the exact solution is 0.40 / 0.28 with it and 0.23 / 0.14 without it (n = 8; 0.68 / 0.36
against 0.31 / 0.19 at n = 32); under SIMPLE's absolute ridge (system P) five iterations are far from the exact
solution of the near-singular system either way. Reported for SIMPLE, not a K8 gate (ruling R2).


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
| K1 | A1: the fused tail of the dense score | Metal kernel wrapper; the refactored polar toy and its baseline (roadmap rank 0b) | the polar-table checks pass on the GPU at their recorded counts; judged on the canonical driver's elapsed time against the compiled graph tail (roadmap decision 15), alone and at 3 and 6 processes. **Kept** (2026-11-25, the maintainer's ruling): 1.80 (`2500_4`) and 1.65 (`2500_1`) at one process, 1.74 at six of `2500_1`; `2500_4` at three not resolved by per-process rates (1.52 to 1.59 on the time to the last exit); +6e9 B peak per process; selectable, the default `graph` ([report](../completed/mlxf_kernel_k1_report.md)) |
| K2 | B1: the polar projection | Metal kernel wrapper; `mlx_rfftn` for the bench | the host matrix oracle and controls pass; the chained test with A passes; timed at 2,500 directions, pftsz 182, 61 shells. **Delivered** (2026-11-25, [report](../completed/mlxf_kernel_k2_report.md)): the fused gather kept (24.6 and 24.4 at one process, 5.27 and 6.30 at three from go to the last exit), the device route kept (32.5 and 35.1); the probe's outcome C by the letter, B by the diagnosis, **ruled B**; the defaults kept (graph form, host route) |
| K3 | A2: arbitrary reference sets | `mlx_gather_mm` or `mlx_block_masked_mm` | listed pairs equal the dense kernel's; occupancy and rate reported for cone-shaped sets, with and without orientation order. **Delivered 2026-11-27, the list route and the pair-list kernel kept** ([report](../completed/mlxf_kernel_k3_report.md)): neither wrapper is used; the listed references are gathered (`mlx_gather`) into list tiles of the dense graph; on `2500_4` the route is 2.49 times faster than the dense fill with selection at the 10-degree cone and 1.84 times for the `state` fill; the pair-list kernel (a SIMD group per pair and bin) is 3.65 times faster than the route at the cone and is not built for `state`; occupancy 5 to 15 % at the cone, 67 to 80 % for `state` |
| K4 | A3: the shift lattice and the map reductions | K1's tail | the reference-side variant reproduces the Fourier-Bessel oracle's cells; a particle-side variant passes a decision-level test frozen before timing (roadmap decision 13); the chosen variant passes the map gates; timed against milestone 1's maps at the M5 grids. **Delivered 2026-11-27, nothing kept** ([report](../completed/mlxf_kernel_k4_report.md)): both lattices reproduce the oracle's cells; the particle-side one failed the decision-level test (2 of 12 rows) and the reference-side one its ceiling (0.18); the fused map reductions gave 1.23 (below 1.30, rulings R1 and R2); the Fourier-Bessel maps with the graph reductions stay; the oracles' self-checks and the modes' shifts (`shiftmap_shifts`) were added |
| K5 | B2: the pose objective with gradient and Gauss-Newton matrix | Metal kernel wrapper | the objective, gradient and matrix match the host oracle; planted poses are recovered; evaluations per second timed |
| K6 | C: the insertion, three forms | `mlx_scatter_add`, `mlx_argsort`, the scans, Metal kernel wrapper; K2 | the adjoint identity, numerator and density pass; the repeatability gate is applied to each form, and only a form that passes it is kept (roadmap decision 14); timed. A protected-update probe on a collision-heavy fixture follows K2 directly |
| K7 | A4: the cc finish and the classic reductions | `mlx_argpartition` or `mlx_topk` | both objectives and each reduction match the oracle |
| K8 | D: the PCG solve | `mlx_rfftn`, `mlx_irfftn` | the operator matches the explicit matrix; the solution and true residual match host Cholesky; the termination gates pass; judged by the time to the same true residual at N = 160 and 256, with the iteration count and peak memory beside it. **Delivered 2026-11-25** (rulings R1 and R2: judged at SIMPLE's 2 and 5 iterations; [report](../completed/mlxf_kernel_k8_report.md)) |

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

- 2026-11-26, run `mlxf_toy_seam`: section 2 (the integration shape as a rule for every toy), section 2a's row D,
  and "The seam in files" with the changed differences in sections 3, 4 and 6.
- 2026-11-25, run `mlxf_kernel_k2`: section 2a's row B1, section 4 (B1 as built, the seam, the differences, the
  intermediate array closed), section 5 (the probe) and section 8's row K2 updated from K2's report.
