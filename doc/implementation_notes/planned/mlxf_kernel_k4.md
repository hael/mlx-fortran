# K4: the shift lattice and the map reductions (A3) of the toy polar calculator (run `mlxf_kernel_k4`, on the M5 Ultra)

Status, 2026-11-27: **delivered by run `mlxf_kernel_k4`, nothing of the lattices or the fused reductions kept** ([report](../completed/mlxf_kernel_k4_report.md)); 2026-11-26: planned; ruled as recommended by Hans, 2026-11-26 ("Rule as recommended"), every decision of section 3 and the run order K4, K3, K5, K6, K7; revised after ranks 2d to 2f (runs `mlxf_refactor`, `mlxf_toy_layout`,
`mlxf_kernel_forms`). Base: the commit that holds this plan, after rank 2g's result (K4 runs before K3 by the ruling; the maintainer
commits this plan with the pending work; the run pins the hash in Phase 0 and records it). The revision was
checked against `ae7d623` (ranks 2d to 2f committed) with the three uncommitted document edits of 2026-11-26;
the draft was written at `b2c43a4`. SIMPLE is pinned at `28c753993`, the mirror ledger's pin since rank 2e, and
every SIMPLE fact below was re-read there. Machine: the M5 Ultra only (30 cores, 103.1 GB, the only GPU and the
only machine that builds the library), in the session, in a copy of the checkout, one run at a time.
Supersedes: none. Depends on:

- the polar toy on SIMPLE's memo layout (`ft_ref_terms (2nk, pftsz+1, nrefs, 2)`, the particle terms, tiles
  made by `memoize_refs`) with its Fourier-Bessel shift maps and its driver (validated: yes, runs
  `mlxf_toy_seam` and `mlxf_toy_layout`: `polar_shiftmap` 794 checks, `eul_prob_tab` 105, `polarft_tail` 55,
  `seam` 88 in `unit_kernels` 1,953 at `ae7d623`; `polar_shiftmap_accuracy` 48, named-only, last run at run
  `mlxf_toy_seam`'s Phase 1);
- the dense score's resident reference tiles and K1's fused tail (validated: yes, run `mlxf_kernel_k1`, kept
  under R1 and R2); K2's device route `set_ref_route` (validated: yes, run `mlxf_kernel_k2`);
- `mlx_fft`, `mlx_irfft`, `matmul`, `mlx_take`, `mlx_take_along_dim`, `mlx_compile` (validated: yes, `unit_fft`
  194, `unit_linalg` 632, `unit_ops` 2,462, `unit_compile` 63 at `ae7d623`, counts rank 2g may raise; **not**
  validated: the time of `mlx_fft` over arrays of 364 by 30 by 351 by 4 complex64 elements);
- `type(mlx_metal_kernel)` (validated: yes, `unit_fast` 152, K1's tail, K2's gather; a two-dimensional grid and
  two outputs are in `unit_fast`; the SIMD-group functions (`simd_sum`, `simd_min`, `simd_shuffle`, the lane
  attributes) and `threadgroup` arrays up to 32,768 B with barriers exact and repeatable through the wrapper,
  and a SIMD group per pair 3.3 times faster than one thread per pair on K1's tail (*measured*, run
  `mlxf_kernel_forms`, suites `probe` and `tail`, Apple question 26); **not** validated: a grid of 364 by 256
  threads with rank-2 float32 outputs read back by a second kernel);
- the measured kernel forms of run `mlxf_kernel_forms` (`completed/mlxf_kernel_forms_report.md`, "What the K
  plans take"): decision 9's launch shape and decision 4's sizes follow them;
- the oracles `mlxf_oracle_polar_objfun` (25 self-checks) and `mlxf_oracle_polar_shiftmap` (21) (validated:
  standalone, run `mlxf_oracles2`; **not** asserted by any registry row, and never compared with the toy);
- `scripts/run_parts.sh` (validated: for benchmarks that write its row layout; **not** for the shift maps,
  whose suite reads no `nparts=`, `part=` or `go=`);
- the recorded inputs of milestone 1, `~/agent_runs/mlxf_m1_m5/scratch/keep/shiftmap_grid.txt` (SHA-256
  `aa05ca2773e6eb5d688dcd75ef1756a24940bea8d079c7daf59cdf77bc902eca`) and `polar_case.txt` (SHA-256
  `90a974fa0842a35d5eee6fe3a07a37405bbbd5849ed3eb7818c129d7dacff1d9`);
- rank 2g's result (read in Phase 0: it changes `src/core/` and may add assertions to unit areas);
- the roadmap's decisions 7, 9, 12, 15, 16 and 17 (ruled or standing), and **decision 13, which awaits the
  maintainer's ruling and is decision 1 of this plan**.

K3 and K7 edit the same toy: K4 launches from the commit that holds K3's verified result (section 2, "The
queue").

## 1. Why

A shift map is the loss of one particle against one reference at every in-plane rotation and every shift of a
polar lattice. SIMPLE builds it with a Fourier-Bessel expansion (`gen_shiftmap_kernel` of
`src/main/pftc/simple_polarft_shiftmap.f90`) and reduces it to a mode, a loss, a width and, in tests, an
evidence (`shiftmap_mode`, `shiftmap_draw`). Milestone 1 put that expansion on the GPU as a graph. It reached
0.97 of SIMPLE's 30-thread rate on the screen grid and 0.68 on the window grid (1.99e4 and 7.46e4 maps per
second against 2.05e4 and 1.09e5, *measured*, `completed/mlxf_milestone1_report.md`; SIMPLE's rates are of
commit `0a8b0903e`, in the grid file). The roadmap plans no more graph-level work on that form (section 5) and
lets family A replace it.

Family A3 is the replacement: the dense kernel, which the toy already runs at 1.76e7 pairs per second on 61
shells (*measured*, `completed/mlxf_toy_seam_report.md`), evaluated on copies of one operand shifted to every
lattice point, followed by the map's reductions. The copies can be made of the reference, which gives SIMPLE's
cells exactly, or of the particle, which gives the same disc sampled in the particle's axes at one sixteenth of
the ring transforms when sixteen candidates share a particle (*derived*, decision 1). Which of the two is the
kernel is the roadmap's decision 13, and it is the maintainer's. This plan sets out the cost of both from the
code, defines the test that would admit the cheaper one, builds both on the small fixture, and times the chosen
one against milestone 1's maps at the M5's grids.

What success looks like: the maps run at least 30 % faster than milestone 1's on the canonical driver, at
frozen accuracy, alone and with three and six processes on the GPU, and the 2.63e9 B the Fourier-Bessel form
keeps resident per process (*measured*, the families note, section 3) are no longer needed. What failure looks
like, and is still a result: the lattice does not reach 30 %, it is removed, the Fourier-Bessel form stays, and
the report says which stage held it back.

## 2. Contract

- **Where the code lives:** `src/test/` only (rank 2d's tree): the polar toy's files and two new device
  submodules in `src/test/toys/polar/`, the oracles' tester in `src/test/oracles/`, against the public module
  `mlxf`. Every new Fortran file opens with its `!@descr:` line and `doc/code_base_map.md` is regenerated in
  the phase that adds or deletes one (the static gate checks it). No file under `src/core/` or `src/defs/` changes. A missing wrapper is a stop with a
  report. K4 brings no new class: the maps stay procedures of `polarft_calc` under SIMPLE's names.
- **What it mirrors,** read with `git -C ~/src/SIMPLE show 28c753993:<path>` (never the working tree; nothing
  is copied in; `simple_polarft_shiftmap.f90` changed between the draft's pin `d354efee2` and this one by
  `23eb95cc2`, check 5): `src/main/pftc/simple_polarft_shiftmap.f90` (`new_shiftmap`, `setup_shiftmaps` with its
  internal `build_map`, `kill_shiftmap`, `gen_shiftmap`, `shiftmap_mode`, `shiftmap_shift`, `shiftmap_draw`,
  `wsqsum_ptcl_band`); `src/main/pftc/simple_polar_shiftmap.f90` (type `polar_shiftmap`: the grid, the areas);
  reading references only: `fill_tab_range` with `finish_particle_map` in
  `src/main/strategies/search/probabilistic/simple_eul_prob_tab.f90`, `shiftmap_srch%srch` in
  `src/main/strategies/search/simple_shiftmap_srch.f90`, `update_screen_best` and `screen_pool_size` in
  `simple_eul_prob_tab_utils.f90`, `minimize_in_cell` and `grad_shsrch_minimize` in
  `src/main/pftc/simple_pftc_shsrch_grad.f90`.
- **The integration shape holds from the first edit** (toy policy, section 8): the host files
  (`mlxf_toy_polarft_shiftmap.f90`, the parent, the driver) import no MLX name; what crosses to the device goes
  through the glue `mlxf_toy_polarft_shiftmap_mlx.f90` with a stub beside every body; the new device code is
  submodules of `mlxf_toy_polarft_workspace`, behind the calculator's `class(device_work)` component; both
  ledgers and sub-suite `seam` follow in the same phase as the code.
- **Two forms, in order,** for the reductions: the graph form, kept always (the reference and the CPU path),
  then fused Metal kernels, kept only by decision 16's rule. The construction has one form, a graph.
- **Judged against** `mlxf_oracle_polar_shiftmap` and `mlxf_oracle_polar_objfun` in double precision. The toy
  imports no oracle module; only testers and the benchmark do.
- **The off-state invariant.** A program that does not select the lattice runs no line of it: until Phase 6 the
  Fourier-Bessel maps stay the default, and the polar toy's identity invocations of Phase 0 (decision 20) come
  back bit for bit after every phase. A calculator on the host backend refuses the maps as today.
- **Float32 and complex64 only** on the device, full precision (`MLX_ENABLE_TF32=0`).

### What the check found (2026-11-26)

Read in the working tree at `ae7d623` and in SIMPLE at `28c753993` (first read at `b2c43a4` and `d354efee2`;
checks 5, 11, 14 and 15 are revised for ranks 2e and 2f). A premise of the families note or of the mlx3D note
that the code contradicts is marked **differs**.

1. **The cells are in the reference's frame.** SIMPLE's `shiftmap_shift` returns "the shift of a grid point in
   the optimizer's frame: the reference's own"; the oracle's header (`mlxf_oracle_polar_objfun.f90`) states the
   same phase, and `oracle_polar_frame` gives the matrix that takes a shift in the particle's axes to the
   reference's at a rotation. The families note's statement on the particle-side variant ("agrees with SIMPLE's
   map in distribution, not cell by cell") holds, with one refinement: at a rotation whose angle is a multiple
   of the direction step the two lattices are the same points. That is 14 of 364 rotations on the window grid
   and 7 of 364 on the screen grid (*derived*: (irot - 1) nalpha / nrots is an integer), and 8 of 24 on the
   tester's small fixture.
2. **The grid rule is one rule, and the toy has it.** `build_map` in SIMPLE's `setup_shiftmaps` and in the
   toy's (`mlxf_toy_polarft_shiftmap.f90`): step = box / kstop / 4, nrho = floor(radius / step) + 1, nalpha the
   next product of 2, 3, 5 and 7 at or above 2 ceiling(2 pi kstop rho_max / box) + 3, both maps on the band that
   ends at kscreen = max(kfrom + 1, kto / 2). It follows that the largest phase argument is (pi / 2)(nrho - 1)
   whatever the box and the band (*derived*), so a fixture with few shells and a short ring has the M5 grids'
   nrho, nalpha and number of shifts.
3. **The M5's grids** (*exact*, the recorded grid file): pftsz 182, 364 rotations, shells 2 to 31 (30 shells),
   box 180 (`map_box` of the benchmark), step 1.4516 px. Window: nrho 4, nalpha 14, 56 cells per rotation, 43
   distinct shifts (the first ring is the origin in every direction), 20,384 cells. Screen: nrho 11, nalpha 35,
   385 cells per rotation, 351 distinct shifts, 140,140 cells.
4. **Differs: the reference-side cost of the families note.** It states "about 1 Mflop at pftsz 182 and 61
   shells (61 complex transforms of length 364)" per (reference, shift). The maps' band has 30 shells, not 61:
   30 transforms per shifted operand.
5. **The families note's 0.50 and 0.77 are reproduced as counts of terms:** 43 x 183 x 30 against 43 x 364 x
   30, and 351 x 183 x 30 against 229 x 364 x 30 (the Fourier-Bessel form's useful radius-order terms, 43 and
   229, *measured* in the milestone 1 report). They count the shell sums only. SIMPLE's sums multiply a complex
   by a real matrix (`shell_sums` in `gen_shiftmap_kernel`), the lattice's a complex by a complex one, and the
   count leaves out SIMPLE's products per order and every transform. It is not a ratio of costs. Since
   `23eb95cc2` SIMPLE's `gen_shiftmap_kernel` takes the reference spectra from `ft_ref_terms` (rows nk+1..2nk)
   and the reference power from the terms, one dot product per bin (`term_sums`) under the Euclidean objective;
   the toy's maps read the same rows of its memo (rank 2e) and keep their own order of the power's sum, a
   difference the families note records (rank 2e's report).
6. **Differs: the mlx3D note's section 4 on the particle-side variant** ("a thread holds one shifted particle
   and the reference rings stream past; the U shifted copies are never written"). A shifted particle on the
   band is 183 bins of 30 shells, 5,490 complex numbers: it does not fit a thread's registers. Every rotation
   of a pair comes from one inverse ring transform of length 364; a thread that evaluates one cell directly
   sums 182 x 30 = 5,460 complex terms, 7.65e8 for a screen map against 1.93e6 with the transform (*derived*).
   The copies are written: 1.54e7 B of spectra per particle on the screen grid (*derived*). The same sentence
   calls the maps bandwidth-bound; milestone 1's profile puts 69 % of the screen map's time in the construction
   (34.7 of 50.1 us, *measured*), which is arithmetic.
7. **What hangs on a map in SIMPLE.** `finish_particle_map`, `shiftmap_srch%srch` and the 2D table's two loops
   do the same four things with it: (a) the mode's shift, from `shiftmap_shift`, starts `minimize_in_cell`,
   which searches the box of that shift plus and minus one map step in the reference's axes; (b) the mode's
   loss orders the pool, and `minnloc` keeps the nbest for refinement; (c) the best losses so far bound which
   pairs get a width (`update_screen_best`: "the best losses bound width readout only; final candidate ordering
   is unchanged"); (d) the width feeds the next iteration's shift prior (`record_shift_state`). **The mode's
   rotation is not a decision:** every caller makes its search objects with `new_alternating`, and
   `grad_shsrch_minimize` then starts from the best rotation at the start shift (`maxloc` of `objfun_vals`).
   The roadmap's decision 13 names "the mode's displacement and the retention of candidates"; the reading adds
   the width and removes the rotation.
8. **The evidence and the disk draw have no production caller.** `shiftmap_draw` is private and `shiftmap_mode`
   is its only caller in the files read; the toy's `shiftmap_evidence` is a test hook. The evidence stays
   optional.
9. **The oracles were never wired to the toy.** No file under `src/` or `test/` imports
   `mlxf_oracle_polar_shiftmap` or `mlxf_oracle_polar_objfun` (searched with `rg`), and no registry row asserts
   `oracle_shiftmap_selfcheck` or `oracle_polar_selfcheck`. The shift-map tester has a private direct residual
   (`oracle_map`, `oracle_cell`, `summarize`). The oracles' report leaves both to this plan ("Testers and
   comparisons, owned by each kernel family's plan (K4, K5, K7)").
10. **The oracle has what both variants need.** `oracle_shiftmap%cell` and `%cell_bessel` give a cell of
    SIMPLE's lattice directly and by the truncated series (they differ by 2.1e-9 on its fixtures, *measured*,
    the oracles' report); `%mode` and `%width` reduce a table the caller gives. For a shift in the particle's
    axes, `oracle_polar_pair%dist(irot, shift)` with `oracle_polar_frame`, or a pair whose particle carries the
    phase and `%dists_by_rings` at zero shift, which gives every rotation at once. The oracle's `width` rotates
    each rotation's moment into the particle's axes; a table in the particle's axes needs no rotation, so its
    width is the tester's own double-precision sum.
11. **The maps read the host memos, and that is the whole reason for the device route's refusal.**
    `new_shiftmap` (`mlxf_toy_polarft_shiftmap.f90`) refuses under `POLARFT_REF_ROUTES%device` ("the maps read
    the host memos, which the device route does not make"); `new_shiftmap_mlx` hands one parity's memo
    `self%ft_ref_terms(:, :, :, ieo)` to `prepare_maps`, which builds the full-ring spectra from its rows
    nk+1..2nk and the power's terms from the conjugate of its rows 1..nk. The device memos are released by
    `new_from_memos` (`mlxf_toy_polarft_workspace_lifecycle.f90`). But both routes end in `finish_tiles` with
    the same resident array `self%refs`, which holds the conjugated memo of every shell and every bin, packed
    (rank 2e: on the host route packed from `ft_ref_terms` on the host): the band the maps need is a section
    of it.
12. **The benchmark cannot time the maps in parts today.** `suite=shiftmap` reads `cases case grid maps ptiles
    device evidence widths revision nthr` (`SUITE_KEYS` in `mlxf_bench_polar_table.f90`), refuses `nthr=` in
    `bench_shiftmap`, and writes `bench_polar_table_shiftmap.tsv` with the rate in column 23 (`write_map_row`).
    `scripts/run_parts.sh` passes `nparts=`, `part=`, `nthr=` and `go=` and reads the rate in column 20 of
    `bench_polar_table.tsv`.
13. **The test policy and the benchmark disagree on an unread key.** The policy says of the polar benchmark "a
    key a suite does not read is ignored"; `check_keys` stops with status 2. The code is the newer; Phase 6
    corrects the sentence.
14. **The Fourier-Bessel form's structure** (`mlxf_toy_polarft_workspace_shiftmap.f90`): resident full-ring
    reference spectra, Bessel weights and order phases per map (`polarft_workspace_prepare_maps`); per tile of
    particles a gather, a real-packed `matmul`, `mlx_fft` over the ring, direction transforms folded modulo
    nalpha, then three compiled reductions (`map_select`, `map_reduce`, `map_evidence`) and one wait per tile
    when cutoffs are given (`polarft_workspace_score_maps`, `tile_maps`). The reductions take the map as an
    array of losses; nothing in them is Fourier-Bessel.
15. **Apple question 26** now records run `mlxf_kernel_forms`'s probe through the wrapper: exact group sums
    for 32 to 1,024 threads with barriers, the SIMD-group functions exact, a fixed tree bit-repeatable, arrays
    up to 32,768 B. Only the named-only bench `bench_kernel_forms` uses the features; no toy does. This plan's
    kernels use SIMD-group functions and no `threadgroup` memory (decision 9), and plan no probe of either.

### The queue

Ranks 2d, 2e and 2f are delivered and committed (`ae7d623`); rank 2g, the user-facing hardening, runs next and
before this batch (roadmap decision 17). Then the runs go one at a time in the order K3, K4, K5, K6, K7, each
from the commit that holds the previous run's verified result. Only K3 precedes K4 in this batch. Phase 0
re-checks exactly these premises, and writes what changed:

- **Rank 2g may change the counts and some reductions.** It changes `src/core/` and no toy file: integer
  `mean`, `var` and `std` promoted first, the Euclidean norms and floating means in a scaled form, empty
  `maxval` and `minval` given Fortran's identities, integer-scalar operators, failed saves that keep the
  file, an index validator; it may add assertions to unit areas. Phase 0 reads its report, takes every area's
  count from the base (section 5), and records decision 20's identity invocations twice on the base; a digest
  that differs from `ae7d623`'s (the 364-line identity set of runs `mlxf_toy_layout` and `mlxf_kernel_forms`,
  SHA-256 `e2d65e88...4d33dba5`) is recorded with the operation 2g's report names, else it is a stop.

- **K3 may leave a scored list of pairs.** K3 delivers per-particle lists of references on the resident tiles.
  The lattice's sums are the dense kernel's sums for (shifted copy, listed candidate) pairs. If K3's report
  keeps a route that scores listed pairs from `self%refs`, decision 5's gather goes through it and no second
  gather is written; if K3 kept none, decision 5 stands as written.
- **K3 may change the tiles' layout, the tile plan or `polarft_tile_spec`** (`mlxf_toy_polarft_workspace.f90`,
  `_lifecycle.f90`, `_score.f90`). Decision 5 reads the layout; Phase 0 reads it again.
- **K3 may assert `oracle_polar_selfcheck`** in a tester of its own. Then decision 11's tester asserts the
  shift map's self-check only.
- **K3 edits** `mlxf_toy_eul_prob_tab.f90` (a second driver beside it is possible), `mlxf_bench_polar_table.f90`
  (`SUITE_KEYS`, new suites), `mlxf_test_defs.f90`, `mlxf_test_registry.f90`, both ledgers,
  `src/test/toys/polar/polar.inf`, `src/test/oracles/oracles.inf`, `doc/code_base_map.md`, `test/offstate/`
  and the families note. The counts of section 5 and the identity invocations of decision 20
  are taken from the base as K3 left it, not from this note.
- **K7 follows and reads this plan's result:** the reductions' kernels of decision 9 are per pair across a map,
  K7's are per particle across references; both are written a SIMD group per item, as run `mlxf_kernel_forms`
  found faster. They share K1's file `mlxf_toy_polarft_workspace_tail.f90` only if K7 chooses to; K4 does not
  edit that file. Whether K1's own tail moves to a SIMD group per pair is K7's decision 27.
- K5 and K6 bring classes of their own and touch the polar toy only through the shared files of the table.
- **If K4 runs before K3** (K3's plan gives a reason in its own queue section; the order is the maintainer's):
  nothing of the list above exists yet. Decision 5 stands as written, the counts and the identity invocations
  are the base's of this plan's commit, and K3 reads this run's report before its Phase 2.

## 3. Decisions and rulings

Each is dated 2026-11-26 and carries its recommendation; the maintainer's choices are collected at the end of
the section. **Ruled 2026-11-26** (Hans, "Rule as recommended", the roadmap's decision 18): every decision as
recommended, so decision 1 is **B** (decision-level agreement by decision 2's test); read by the run in Phase 0
(the run's `spec/rulings.md` was empty then). **Standing ruling, roadmap decision 19** (Hans, 2026-11-26, in the
run's `spec/rulings.md` from Phase 1): an MLX-centric design that ports to NVIDIA with minimal changes: MLX
operations and `fast` functions first; a custom kernel only where the keep rule keeps it, through
`mlx_metal_kernel` with MLX arrays in and out and no host path around it, its source, launch spec and graph form
kept together; no platform branch outside the kernel source and the tests' device checks; the report gains a
section "For a CUDA twin" (per kept kernel the Metal-specific features it uses and their CUDA counterparts).
It bears on decision 9 and Phase 4; Phases 1 to 3 build graphs only.

1. (2026-11-26, **awaits the ruling: the roadmap's decision 13**) **Which operand carries the shifts.**
   - **Reference-side.** Copies of the reference, shifted in its own frame. The cells are SIMPLE's. Shared
     operand: the shifted reference, by the particles of a tile that hold that reference as a candidate.
   - **Particle-side.** Copies of the particle times its CTF, shifted in the particle's axes. Same rings, same
     number of directions, same areas and prior; at rotation irot the directions are SIMPLE's turned by that
     rotation's angle (check 1). Shared operand: the shifted particle, by all its candidates.
   - **Cost per map at the M5's grids** (*derived* from check 3; a complex64 is 8 B):

     | Per map | Window | Screen |
     | --- | --- | --- |
     | distinct shifts | 43 | 351 |
     | sums: complex multiply-adds (shifts x 183 bins x 30 shells), either side | 2.36e5 | 1.93e6 |
     | inverse ring transforms (one per shift and pair), either side | 43 | 351 |
     | ring transforms of length 364, particle-side, 16 candidates per particle | 81 | 658 |
     | ring transforms of length 364, reference-side, one particle per reference | 1,290 | 10,530 |
     | transient bytes per particle, particle-side (copies, spectra, rows of 16 pairs) | 6.65e6 | 5.43e7 |
     | transient bytes per particle, reference-side (the same per pair, 16 pairs) | 9.1e7 | 7.46e8 |

     The reference-side count takes no sharing, which is the benchmark's case: `map_candidates` gives particle
     i the references i - 1 + 625 (c - 1), so no two particles of a tile of 4 or 16 share one (*derived*).
     How many particles share a candidate in a SIMPLE run: no record in hand. The reference-side copies cannot
     be resident: 351 x 43,920 B per reference is 1.54e7 B, 1.54e11 B for 10,000 references (*derived*).
   - **Exact cells from the particle side are not economical:** the directions would have to be those of every
     rotation, lcm(nalpha, nrots) of them, 364 on the window grid and 1,820 on the screen grid, 26 and 52 times
     the work (*derived*). Nor can SIMPLE's cells be interpolated from the particle-side ones: the maps keep
     Bessel orders to 16 and 32 (*exact*, the grid file's `norder`) on 14 and 35 directions.
   - **Recommended: decision-level agreement is accepted, and the particle-side lattice is the kernel if it
     passes decision 2's test.** Reasons: sixteen times fewer ring transforms at the benchmark's sharing; what
     SIMPLE takes from a map is a start shift for a search in a box one step wide, an order of losses and a
     width (check 7), none of which is a cell index; the direction origin of SIMPLE's own lattice is a
     convention, and the test measures the particle-side lattice against that convention's own effect.
   - **What the maintainer rules:** (A) SIMPLE's exact cells are required, or (B) decision-level agreement by
     decision 2's test is accepted.
   - **Under either answer** Phase 1 builds both lattices on the small fixture and holds the reference-side one
     to the Fourier-Bessel oracle's cells, as the accepted exit of the families note requires.
   - **Under A** the reference-side lattice is the candidate. Phase 2 runs decision 2's test and reports it,
     without effect. Phase 3 measures the reference-side ceiling (decision 10) and the plan goes on with it.
     Expected (*guessed*): it does not reach the Fourier-Bessel form, which is the economical way to SIMPLE's
     cells; the lattice is then removed and the fused reductions are judged on the Fourier-Bessel cells
     (decision 16).
   - **Under B** the particle-side lattice is the candidate when it passes decision 2's test on seeds 2 and 3.
     If it fails, the plan continues as under A and the failure is in the report with its numbers.

2. (2026-11-26, recommended; part of the ruling on decision 1) **The decision-level test.** It is a property of
   the lattice, so it is judged on the host in double precision with the oracle, with no device and before any
   timing.
   - **The three lattices of a pair:** R, SIMPLE's (`oracle_shiftmap%table`); P, the particle-side one (check
     10); R', the calibration control: SIMPLE's rings and direction count with the directions turned by half a
     direction step, in the reference's frame. R' is as valid a SIMPLE lattice as R, and P at any rotation lies
     between them.
   - **Geometry:** the M5's two grids' nrho, nalpha and shifts (check 2) on pftsz 52 (104 rotations) and 8
     shells, so that a screen table costs seconds (*guessed*; item 1 of Phase 2 times one and may shorten the
     ring, never the grid).
   - **Fixtures, per grid and seed:** 32 representative pairs (a reference copy with a planted shift anywhere
     in the disc, off the lattice, a planted rotation, the fixture's CTF, and noise at two levels) and 32
     near-tie pairs: the planted shift midway between two rings or two directions (12), a particle that is the
     sum of two shifted copies with amplitude ratios 1, 1 + 1e-3, 1 + 1e-2 and 1 + 1e-1 (12), and a reference
     with a twofold in-plane symmetry broken by the same three ratios (8). For retention, 8 particles with a
     pool of 16 candidates each, 8 of the 16 being one reference perturbed by 1e-3 to 1e-1 of its norm, and
     nbest = 4 (*guessed*: the toy has no `projs_ns`).
   - **Statistics,** each for P against R and for R' against R:
     - T1, the start of the refinement: the number of pairs whose two modes' shifts, both in the reference's
       axes, differ by more than one map step in either component. One step is the half-width of the box
       `minimize_in_cell` searches (*derived* from its code).
     - T2, retention: the number of particles whose nbest sets by the mode's loss differ.
     - T3, the width: the largest relative difference of `sdev` over the pairs that have one in both tables;
       and the number of pairs whose width is skipped in one table and not in the other under the sequential
       cutoff of `update_screen_best`.
   - **Bounds, frozen here:** on each judged seed, grid and fixture class, T1(P) <= T1(R') + 1 and T2(P) <=
     T2(R') + 1 (one pair of 32 and one particle of 8: *guessed*); T3's relative difference for P at most 1.5
     times the control's (*guessed*); T3's count at most the control's plus 1. Seed 1 is run first and
     reported; it changes no bound. The absolute values of every statistic are in the report: a control that
     itself moves many decisions is a finding about the maps, not about the lattice.
   - **Planted violations:** the mode's shift converted to the reference's axes with the transposed frame (T1
     must fail); a particle-side lattice on every second ring (T1 must fail); the candidates' losses compared
     after a permutation of two candidates (T2 must fail).

3. (2026-11-26, recommended) **The lattice is SIMPLE's grid.** The rings, the number of directions, the cells'
   areas and the prior are those of `new_shiftmap` and `setup_shiftmaps`, unchanged, for both maps. A lattice of
   the toy's own (a square grid, for one) would change the areas and every reduction, and no SIMPLE caller
   reads one. A map has U = nrho x nalpha cells per rotation (56 and 385) and U_d = (nrho - 1) nalpha + 1
   distinct shifts (43 and 351): the first ring is computed once and counted nalpha times with its own areas.
   The lattice belongs to the map, so it is the same for every particle (particle-side) or every reference
   (reference-side); the copies are per particle or per (reference, tile).

4. (2026-11-26, recommended) **The construction is a graph, in a new device submodule
   `mlxf_toy_polarft_workspace_lattice`.** Per tile of particles:
   - the unshifted operand's ring values on the band are recovered on the device from the memo's 183 bins (the
     ring's symmetry gives the other half) and checked against the fixture's rings in Phase 1;
   - they are multiplied by the map's resident phase table (364 x 30 x U_d complex64: 3.76e6 B for the window,
     3.07e7 B for the screen, *derived*) and transformed with `mlx_fft` over the ring; 183 bins are kept;
   - per bin, the sums over the 30 weighted shells of (copies) by (candidates) are one real-packed `matmul`, as
     in `polarft_workspace_submit`; `mlx_irfft` over the bins gives the cross term of every rotation;
   - the reference's power term does not depend on the shift on either side: it is computed once per pair, as
     the Fourier-Bessel form computes it today;
   - the losses are `1 + (refpow - 2 cross) / ptclpow`, in rows (rotation, distinct shift, pair).
   The particle tile stays the map's (`set_shiftmap_options`, default 16). Sizes that change per map reach a
   kernel in an int32 input, not a template (the mlx3D note's proposal 4, taken): equal per launch, and a new
   value costs about 3 ms in an input against 42 ms as a template (*measured*, run `mlxf_kernel_forms`, suite
   `sizes`).

5. (2026-11-26, recommended) **The references come from the dense score's resident tiles,** `self%refs` (the
   packed conjugated memo, rank 2e), by a gather of each particle's candidates on the map's 30 shells (check
   11), subject to the queue's K3 item.
   The lattice then keeps no reference data of its own, on either route. Fallback, if the gather from the
   packed tiles costs more than 20 % of the construction at the bench (*guessed*): a resident band of the
   memo's rows nk+1..2nk and of the conjugate of its rows 1..nk on the map's 30 shells (what `prepare_maps`
   reads of `ft_ref_terms` today, rank 2e), made in `prepare_maps` from the host memo (1.76e9 B for both
   parities of 10,000 references, *derived*: two arrays of 43,920 B per reference and parity), and decision 18
   falls to "no".

6. (2026-11-26, recommended) **The reductions kept are SIMPLE's four, in SIMPLE's order.** The mode (the first
   strict maximum of the tempered log posterior with the prior and the cell's log area, rings outermost, then
   rotations, directions innermost), the loss at the mode, the width at the physical temperature (cells below
   the maximum by more than `POLAR_MAP_LOG_CUT` dropped; skipped with `sdev = -1` above a pair's cutoff), and
   the optional evidence. Their graph form is the three compiled functions that exist (`map_select`,
   `map_reduce`, `map_evidence`), fed with the lattice's losses expanded to cells; they are edited only where
   the map's layout or the frame enters. On the particle-side lattice the width's moments are already in the
   particle's axes, so the rotation of each rotation's first moment is left out.

7. (2026-11-26, recommended) **The mode's shift is handed over in the reference's axes,** by an addition
   `shiftmap_shifts( self, xy )` beside `shiftmap_evidence` and `shiftmap_maps`: the shifts of the last modes,
   what SIMPLE's callers compute with `shiftmap_shift` at the mode's cell. `polar_map_results` gains the
   component. On the particle-side lattice `ialpha` counts directions in the particle's axes; this is a
   declared difference in the mirror ledger and in the families note, and a caller that uses
   `shiftmap_shifts` does not see it. No `shiftmap_shift` is added: its dummy list has no rotation.

8. (2026-11-26, recommended) **During the run the form is selected, after it nothing is.** A vocabulary
   `POLARFT_MAP_FORMS` (`bessel`, `lattice_ref`, `lattice_ptcl`) in `mlxf_test_defs.f90` and an addition
   `set_shiftmap_form( self, form, tail )`, with `tail` a member of `POLARFT_TAILS`. The default is `bessel`
   with the graph reductions until Phase 6. Phase 6 leaves one construction (decision 17); the vocabulary and
   the `form` dummy go with the losers. No other key, option or member enters the toy; alternatives live in
   the benchmark.

9. (2026-11-26, recommended; revised 2026-11-26 by run `mlxf_kernel_forms`) **The fused form of the reductions
   is four small kernels in two launch shapes, the per-pair ones a SIMD group per pair, without `threadgroup`
   memory,** in a new device submodule `mlxf_toy_polarft_workspace_maptail`, written only if decision 10
   admits it. One thread per pair scanning a whole screen map would run 64 threads of 140,140 cells each per
   tile; the work is therefore split by rotation.
   - Kernel 1, grid (rotation, pair): a thread scans its rotation's U cells in SIMPLE's order and writes the
     rotation's largest tempered log posterior with its first cell, and the largest physical one.
   - Kernel 2, a SIMD group per pair (T1's shape): its 32 lanes stride over the 364 partials, each keeping its
     first maximum, then `simd_max` and the least index among the maximal lanes give the mode in SIMPLE's
     order (ties to the lower ring, then rotation, then direction), the loss at the mode and the pair's
     physical maximum.
   - Kernel 3, grid (rotation, pair): its rotation's share of the width's moments and, when asked, of the
     evidence's sum, above the cut, with compensated sums and `metal::precise::exp`.
   - Kernel 4, a SIMD group per pair: the 364 shares, each lane's strided part in index order and the lanes in
     a fixed tree (`simd_sum` or `simd_shuffle` in a fixed order), the width and the evidence.
   - *Why a SIMD group per pair* (*measured*, run `mlxf_kernel_forms`, suite `tail`): on K1's tail, the same
     reduction of 364 rotations per pair, a SIMD group per pair was 3.28 / 3.28 times faster than one thread
     per pair (5 of 5 pairs), first minima exact, and 1.8 times faster from go to the last exit at six
     processes. Kernels 1 and 3 keep a thread per (rotation, pair), which fills the GPU already (23,296
     threads per tile of 64 pairs); a SIMD group per (rotation, pair) for the screen grid's 385 cells is a
     configuration of Phase 4's sweep, not a fifth kernel.
   - *Compensated sums* stay in kernel 3 and kernel 4: they are free where the kernel is not bound by its
     sums (2.8 % on K1's tail, suite `tail`) and cost 14 % in a reduction-bound kernel for 50 to 90 times the
     accuracy (suite `reduce`); the width and the evidence are differences of moments, and decision 12's last
     row is the tolerance they buy. A plain sum replaces them only if Phase 4 measures it more than 5 %
     faster on the canonical driver and decision 12's row still holds.
   The kernels read losses through an int32 table from cell to row, so they serve the lattice's rows and the
   Fourier-Bessel form's cells alike. Partials cross between kernels as rank-2 float32 outputs, which K2
   proved; nothing is atomic, so the form is repeatable by construction. **Fallback, named in advance:** if
   the four launches cost more than the graph reductions they replace, one SIMD group per pair scanning the
   whole map (T1's shape over all cells); if that is slower too, the graph reductions stay. `threadgroup`
   memory is not used (none of the four needs it) and is not probed: the wrapper's support is measured
   (Apple question 26).

10. (2026-11-26, recommended) **Ceilings before kernels,** in scratch copies of the tree with a null stage
    (the diff kept with the run's evidence; no repository key), at one process on both grids:
    - C1, the lattice's construction alone (the reductions return the first cell): the upper bound of the
      lattice with any reductions. Under ruling B for the particle-side lattice; the reference-side one is
      measured too, for decision 1's table as *measured*.
    - C2, each construction with null reductions against the same with the graph reductions: the upper bound
      of the fused form. For the Fourier-Bessel form the milestone 1 profile predicts 1.43 on the canonical
      driver (*derived*: 16.3 of 50.1 us and 2.9 of 13.4 us per map are reductions).
    - **The rules:** a lattice whose C1 is below 1.30 times the Fourier-Bessel form's best ceiling (its C2
      rate) is removed in Phase 3, and Phase 4 works on the Fourier-Bessel cells; Phase 4 is entered when C2
      is at least 1.30 for a construction still present, else it is recorded as "not entered".

11. (2026-11-26, recommended) **The oracles are wired.** A tester `mlxf_oracle_polar_tester.f90` with a
    sub-suite `oracle_polar` asserts `oracle_shiftmap_selfcheck` (21 checks) and, unless K3 did,
    `oracle_polar_selfcheck` (25) within their own limits. The lattice's tester builds an `oracle_polar_pair`
    from each fixture's rings, an `oracle_shiftmap` on it, and makes the toy's map on the oracle's grid
    (`%rho`, `%dims`) with `new_shiftmap`. The oracle modules are not edited; a suspected oracle fault is a
    stop with the evidence.

12. (2026-11-26, recommended) **Tolerances.**
    - The existing caps do not move: `POLAR_MAP_CAP_L2`, `POLAR_MAP_CAP_LOG` and `POLAR_MAP_CAP_VAR`, 1e-4
      each (*measured* and frozen in milestone 1). Every form present meets them in the tests that apply them.
    - New measures, each calibrated on the calibration fixtures and on seed 1 of decision 13 on both devices,
      frozen in `mlxf_test_defs.f90` and in Progress with a ceiling it may not exceed, then judged on the
      other fixtures and on seeds 2 and 3:

      | Measure | Ceiling |
      | --- | --- |
      | reference-side cells against `oracle_shiftmap%cell_bessel`, largest error | 1e-4 (*guessed*: the caps' size) |
      | reference-side cells against `%cell`, largest error | 1e-4 (*guessed*) |
      | particle-side cells against the direct loss at the cell's shift, largest error | 1e-4 (*guessed*) |
      | the two lattices at a coinciding rotation, largest difference | 2e-4 (*derived*: two forms within 1e-4) |
      | the mode's shift against the oracle's, in px | 1e-4 (*guessed*), where the mode's margin is above the cap |
      | fused reductions against the graph's: loss, `sdev`, evidence | 1e-5 (*guessed*); the mode's indices exact where the margin is above the cap |

    - The modes' indices are exact against the oracle where the oracle's margin to the runner-up is above
      `POLAR_MAP_CAP_LOG`; at a smaller margin either cell passes, and the count of such pairs is reported.
    - **Amended by ruling R2** (Hans, 2026-11-27, "Judge each vs oracle", after Phase 4 stopped on this row's width):
      the width of each form is judged against the oracle under the frozen `POLAR_MAP_CAP_VAR` (variance space, as
      the existing tests apply it) on the calibration fixtures and on seeds 2 and 3, on both devices where the form
      runs; the row "fused reductions against the graph's" keeps the losses (equal) and the evidence at its
      calibrated tolerance, and its width part is reported (the largest relative difference per fixture class), not
      gated. No new width measure or tolerance; nothing else of this decision changes.

13. (2026-11-26, recommended) **Fixtures and sizes.**
    - Fast gate, both devices, inside `unit_kernels`: the tester's two analytic fixtures (24 ring positions, 4
      shells, 16 directions; the folding case) and the oracle's three sizes (`oracle_polar_fixture`: pftsz 16,
      12, 12), and the oracle's size 1 with seeded noise on the particle (seeds 1, 2 and 3). Calibration: the
      unperturbed analytic fixture, the oracle's size 1 and seed 1. Judged: the perturbed fixture, the
      oracle's sizes 2 and 3, seeds 2 and 3.
    - Sub-suite `polar_shiftmap`: every test but `test_folding` runs for each form present, its private oracle
      evaluating the cell's shift in the form's frame. Sub-suite `polar_lattice` (new): decision 11's
      comparisons, the coinciding rotations, decision 7's shifts, decision 14, the fused form on the GPU and
      its refusal on the CPU device.
    - Named-only: `polar_shiftmap_accuracy` runs per form (sampled cells at the M5's two geometries, both
      devices); `polar_lattice_decision` is decision 2's test (host only, seeds 1 to 3).
    - Bound: the new and widened fast suites add at most 5 s to `unit_kernels` in Release (*guessed*; the
      measured times are recorded), and the fast gate stays under its 38.74 s. If the bound fails, the
      reference-side lattice's pass through `polar_shiftmap` becomes named-only.

14. (2026-11-26, recommended) **Repeatability is its own gate.** For each form that is kept: the maps' modes,
    losses, widths and evidence of one fixture block, bit for bit across two evaluations in one process and
    across two invocations, on the GPU at the kept particle tile; at the bench, the digests of two invocations
    (`digest_maps`). A form that is not repeatable is not kept, with the operation that differs named.

15. (2026-11-26, recommended) **The baseline and the canonical driver.**
    - The baseline is milestone 1's control: the toy driver's fill with the maps stage only
      (`set_fill_stages(.false., .true.)`), form `bessel`, graph reductions, `widths=all`, `evidence=0`,
      particle tiles 16 (window) and 4 (screen), case `2500_4`, the recorded grid file: 7.45e4 and 1.99e4 maps
      per second (*measured*, milestone 1). Phase 0 measures it twice on the base with `suite=shiftmap`; a
      rate more than 5 % from milestone 1's is recorded with its cause sought once, and the Phase 0 rate is
      the baseline either way.
    - **The canonical driver's elapsed time is the window row plus the screen row at equal maps** (32,000
      each: 2,000 particles of 16 candidates), 2.03 s at the baseline's rates (*derived*), of which the screen
      row is 79 %. Each grid's ratio is reported beside it.
    - A new suite `maps` of `bench_polar_table` times one part: keys `cases case grid maps ptiles device form
      tail nthr nparts part go passes revision`; `nthr` sizes the host team only; rows in
      `bench_polar_table.tsv` in the layout `scripts/run_parts.sh` reads (rate in maps per second in column
      20, work 21, MLX peak and cache 26 and 27, median pass 30). `scripts/run_parts.sh` is not edited
      (`RUN_PARTS_SUITE=maps`, `RUN_PARTS_UNIT=maps`). `suite=shiftmap` stays as it is, the baseline's
      instrument, and gains only `form=` and `tail=`.

16. (2026-11-26, recommended) **The verdict.**
    - **Protocol** (K1's, as ruled there): Release, `MLX_ENABLE_TF32=0`, nothing else built or run, the
      one-minute load at most 4 with `uptime` recorded; the configurations (particle tiles, the fused form's
      threadgroup, the row layout) frozen in Progress before the first verdict row; forms interleaved in
      pairs, 5 pairs per split, `passes=9`; two invocations each; at one process the ratio of best passes; at
      3 and 6 processes the ratio of the times from go to the last exit, a row counting only if its parts exit
      within one median pass of each other.
    - **Splits:** `2500_4` at 1 and 3 processes; 6 processes on `2500_4` if the launcher's memory guard admits
      it, else on `2500_1` with a one-process row of its own; a split the guard refuses is recorded as not run.
    - **Rule T, the reductions:** on a construction, the fused form is kept when the median ratio to the graph
      reductions is at least 1.30 at one process and at no judged split below 1.00.
    - **Rule C, the construction:** the lattice replaces the Fourier-Bessel form when its best kept form
      against the Fourier-Bessel form's best kept form is at least 1.30 at one process and at no judged split
      below 1.00. Otherwise the lattice is removed.
    - A ratio at or above 1.30 at one process with a judged split below 1.00 is a stop for a ruling, with the
      rows (K1's R1 and R2 are the precedent: "any gains we can maintain with many parts is linear speedup").
    - **Reported with the verdict:** per split the total rate, the rate per process, one process's footprint
      and MLX peak, the summed footprint, the roadmap's two reopening conditions (the total rate at 3 or 6
      below 0.8 of one process's; the summed footprint above 51.5e9 B), and both rate measures where they
      disagree. Memory is reported, never a reason to reject a faster form.

17. (2026-11-26, recommended; **the maintainer's**) **One construction survives the run.** If rule C keeps the
    lattice, Phase 6 deletes the Fourier-Bessel device form: the Bessel weights, order phases and direction
    transforms of `mlxf_toy_polarft_workspace_shiftmap.f90`, the additions `shiftmap_order` and
    `shiftmap_term_counts` with their ledger lines and bench columns, and `test_folding`. The compiled
    reductions, the grid rule and every mirrored procedure stay. If rule C removes the lattice, its submodule,
    its selector and its tests go, and its numbers stay in the report. Reasons: a second path for the same maps
    needs 30 %, the slower one would be more than 30 % behind; the roadmap's section 5 ends graph-level work on
    the Fourier-Bessel form; SIMPLE's exact cells stay available from the host oracle and from SIMPLE's own CPU
    path, which an integration keeps. The reference-side lattice, when it is not the candidate, is removed at
    the end of Phase 3 with its gate results and its measured ceiling in Progress.

18. (2026-11-26, recommended; **the maintainer's**) **The device route's refusal is lifted when the lattice is
    kept and reads the tiles** (decision 5 without its fallback): `new_shiftmap` then no longer refuses under
    `POLARFT_REF_ROUTES%device`. Gate: on the device route the lattice's maps meet the same oracle gates at the
    same frozen tolerances (not bit for bit against the host route's: the two routes' tiles differ in
    rounding), in `polar_lattice`, on references a small volume gives through `vol_pad2ref_pfts_opt` on the
    device route, as `projector_chain` sets them. If the Fourier-Bessel form stays, or the fallback of decision
    5 was taken, the refusal stays as it is.

19. (2026-11-26, recommended) **The host backend refuses the maps, as today.** `new_shiftmap` keeps its
    refusal under `l_mlx = .false.`, and the glue's stubs refuse in a build without MLX. A miniature of
    `gen_shiftmap_kernel` on the host is not in this plan: SIMPLE's CPU maps are the host route of an
    integration. The off-state program gains one check, that a host-backend calculator refuses `new_shiftmap`
    with the message of today, and sub-suite `seam` gains the new additions' refusals on the host backend and
    100 cycles of `new_shiftmap`, `gen_shiftmap`, `shiftmap_mode` and `kill_shiftmap` per form that leave
    `mlx_live_count` and the active memory where they were.

20. (2026-11-26, recommended) **The identity invocations.** Phase 0 records, twice each: the dense table's
    digests on both devices and both tails, the device route's, and the Fourier-Bessel maps' digests on both
    grids (the polar toy's invocations of the seam run's identity file). They come back bit for bit after
    Phases 1 to 5. Phase 6 retires the maps' lines if the Fourier-Bessel form is deleted, and only those.

21. (2026-11-26, recommended) **Every gate has a planted violation,** each built in a patched copy apart,
    shown to fail its named check, then discarded; the runner restores files with fresh times and waits a
    second before a rebuild (the seam run's lesson). The list is in section 6.

22. (2026-11-26, recommended) **Memory is measured and reported:** per form and grid the prepared device
    memory, the MLX peak and cache, one process's footprint; the families note's seam facts are rewritten with
    them (before rank 2e: a map adds 2.63e9 B for both parities, 9.77e9 B active with the tiles; Phase 0's
    baseline measures them on the base). Expected for a
    lattice on the tiles (*derived*): no reference data of its own, and the phase tables of decision 4.

23. (2026-11-26, recommended) **Files beyond the table.** A toy file that passes 700 lines is split into a
    further submodule of the same parent, its row added to the table before the edit, with both ledgers.
    Nothing else is outside the table.

24. (2026-11-26, recommended) **MLX and mlx-c findings** (a transform's time or working memory at these
    shapes, a kernel that returns wrong rows under the default math mode as in MLX issue #4603, the cost of
    several launches) become numbered entries of `doc/collaboration/apple_questions.md`, after the last one
    Phase 0 finds (37 and following at `ae7d623`), written by the run and never sent.

**Defaults taken without a question:**
- the grid, the candidates per particle (16) and the case are the recorded files'; no new measurement of SIMPLE;
- the losses' rows are float32; the phase tables are made on the host in double precision and rounded once;
- the particle tile of a map stays one number per map; the benchmark sweeps 4, 8, 16 and 32 before the freeze;
- the weights are the calculator's `k / sigma2` on the map's band, as `wsqsum_ptcl_band` uses them;
- the frame's sign is whatever makes the particle-side cell equal `oracle_polar_pair%dist` at
  `matmul(oracle_polar_frame(irot, nrots), u)`: Phase 1 fixes it by that check, not by this note;
- the driver is unchanged in what it does: `finish_particle_map` calls `gen_shiftmap` and `shiftmap_mode`, and
  `batch_map_results` hands over the results with the new component;
- the mlx3D note's proposal 5 (`apply` with a launch of its own) is not needed: a kernel object per map and
  tile shape costs about 3 ms once (a new object of an existing source, 2.6 to 3.1 ms at its first evaluation;
  MLX never recompiles for a new launch configuration; *measured*, run `mlxf_kernel_forms`, suite `sizes`).

**The choices that are the maintainer's,** each with what the other way costs:
- **Decision 1** (the roadmap's 13): A or B. A keeps SIMPLE's cells on the GPU and, by the derived costs, most
  likely keeps the Fourier-Bessel construction with at best fused reductions (ceiling 1.43). B admits a lattice
  with one sixteenth of the transforms whose cells are not SIMPLE's.
- **Decision 2:** whether this test, with these statistics and bounds, is what "decision-level agreement"
  means. A stricter bound (no excess over the control at all) costs nothing to state and may fail on one pair.
- **Decision 3:** SIMPLE's grid, not a lattice of the toy's own.
- **Decision 16:** the canonical elapsed time as the two grids at equal maps (decision 15), and "no judged
  split below 1.00". Weighting by SIMPLE's mix of window and screen particles needs a record that is not in
  hand.
- **Decision 17:** deleting the Fourier-Bessel device form when the lattice is kept. Keeping it costs a second
  path, 2.63e9 B per process when used, and the suite's time.
- **Decision 18:** lifting the device route's refusal in this run rather than in a later one.

## 4. Not in this plan

- Any change to `src/core/`, `src/defs/` or SIMPLE; a measurement of SIMPLE; production data.
- In-cell refinement (`minimize_in_cell`), the pool's selection (`screen_pool_size`), `shiftmap_draw`'s disk
  draw: the toy has none today and gains none. Decision 2 reads their rules to define its statistics only.
- The correlation objective on the maps: SIMPLE refuses it there (`shiftmap_draw`), and K7 owns `objfun=cc`.
- A host route for the maps (decision 19); a lattice of the toy's own (decision 3).
- K3's lists, beyond using what K3 kept (the queue); K7's per-particle reductions.
- More graph-level work on the Fourier-Bessel construction (the roadmap, section 5).
- `threadgroup` memory and atomic outputs (no kernel of decision 9 needs them); SIMD-group functions are used
  by kernels 2 and 4 only.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement on the base; one tests-only file | both builds without a warning; the counts; decision 20's digests twice; the baseline twice; the queue's premises; `oracle_polar` asserted; the probes answered |
| 1 | tests-only: the two lattices as graphs, selected only by `set_shiftmap_form` | decision 12's measures frozen on the calibration fixtures, then judged; the existing caps; decisions 14, 19 and 20; the Phase 1 plants |
| 2 | tests-only: the decision-level test on the host | decision 2's bounds on seeds 2 and 3; its three plants; no timing has been taken of a lattice |
| 3 | measurement; a deletion (the lattice that is not the candidate) | `polar_shiftmap_accuracy` per form; decision 10's ceilings and rules; the bench's part mode; decision 20 |
| 4 | tests-only: the fused reductions, if entered | the reductions' gates on the GPU under decision 12; the refusal on the CPU device; decision 14; the Phase 4 plants |
| 5 | measurement | decision 16's protocol, rules T and C; every split run or recorded as not run |
| 6 | result-changing for the maps' default; deletions; documentation | the survivor passes every map gate as the default; decision 18's gate; the last-phase gates; the report |

Every phase ends with Debug and Release built from scratch in the run's own hand-configured trees
(`-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`) with no warning, the fast gate passing in both (13 entries),
`scripts/check_tree.sh` passing (with rank 2d's rules `publist` and `size`, the `.inf` descriptions and the
code-base map), `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` run on every Fortran file
touched, and the areas' counts, Debug and Release alike, as Phase 0 finds them on the base (rank 2g and K3
may have changed them). At `ae7d623` (*measured*): `unit_core` 214 to 216, `unit_array` 193, `unit_ops`
2,462, `unit_fft` 194, `unit_linalg` 632, `unit_compile` 63, `unit_fast` 152, `unit_random` 486,
`unit_transforms` 274, `unit_io` 846, `unit_distributed` 55, and `unit_kernels` 1,953 (`polarft_calc` 333,
`projector_chain` 91 since rank 2e). `unit_kernels` is the base's count plus this run's checks, the new count
frozen at each exit.
Phase 6 adds `scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`,
`scripts/release_gate.sh --allow-dirty` and the Release fast gate 10 times of 10. Nothing is built while a step
is timed.

## 6. Acceptance

- **The exit of the families note's row K4:** the reference-side variant reproduces the Fourier-Bessel
  oracle's cells (Phase 1, decision 12's first row); a particle-side variant passes a decision-level test frozen
  before timing (Phase 2, decision 2, frozen in this note); the chosen variant passes the map gates (Phases 1,
  3 and 6); it is timed against milestone 1's maps at the M5's grids (Phases 3 and 5).
- **Numbers:** decisions 2, 10, 12, 13, 15 and 16, each frozen in this note or in Progress before the run it
  judges. A tolerance is never taken from the fixtures it judges; no seed, fixture or bound is changed to pass;
  a failing gate on a judged fixture or seed is a diagnosis, not a new calibration.
- **Exact gates:** the modes' indices where the margin allows (decision 12); the count and order of results;
  the refusals' messages; decision 14; decision 20; the ledgers (rules `mirror` and `seam`, `SEAM_PENDING` 0).
- **Planted violations,** each shown to fail the named gate:
  - Phase 0: a self-check's limit halved below its measured error (`oracle_polar`).
  - Phase 1: the shift phase with the opposite sign (cells against the oracle); the first ring counted once,
    not nalpha times (the evidence and the width); the mode's scan with directions outermost (the mode's
    indices on a tie fixture); the particle-side width with the reference-side rotation left in (the width);
    the frame transposed in `shiftmap_shifts` (the shift); the band one shell short (cells); a candidate
    gathered from the neighbouring tile column (cells); a public addition missing from the mirror ledger (rule
    `mirror`); the new device submodule classed `host` (rule `seam`); a term that depends on the call count
    added to a row (decision 14).
  - Phase 2: decision 2's three.
  - Phase 4: kernel 2's tie going to the higher rotation (the mode's indices); kernel 3 without the cut (the
    width); the compensation removed (decision 12's last row, on the broadband fixture); the fused form asked
    for on the CPU device (the refusal).
  - Phase 5: a part's key the suite does not read (`error stop 2`); a row whose parts exit apart (the
    validity test rejects it).
  - Phase 6: the device route with the refusal restored (decision 18's check expects a map).
- **Reported, not gated:** every time and byte count; the stages' microseconds per map; decision 2's absolute
  statistics and the control's; the count of modes inside the cap's margin; the suites' elapsed times; the
  splits that are not judged; the reopening conditions; what SIMPLE's rate is beside each row (the grid
  file's, of commit `0a8b0903e`, labelled).
- **Hypotheses, each with its test** (*guessed*; none is a criterion): the lattice's sums run near the dense
  score's rate per multiply-add (C1); the ring transforms, not the sums, bound the particle-side lattice (the
  stage profile); the reference-side lattice is slower than the Fourier-Bessel form (C1 under A); the graph
  reductions take a third of a screen map on the lattice too (C2); three processes share the GPU without loss
  (decision 16).
- **Reserved for the maintainer:** whether the miniature still reads like SIMPLE's maps with `ialpha` in the
  particle's axes; the weight of the two grids; any stop of decision 16.

## 7. Common rules and stop conditions

- No file outside the table, apart from decision 23's rows. No tolerance, ceiling, bound, fixture or seed
  changed to pass. A failing gate is a diagnosis task.
- No new key, option or member beyond those named here, in the toy. Alternatives live in the benchmark, and
  the benchmark holds no losing alternative after Phase 6.
- The oracle modules import no `mlxf` module and no toy module, and are not edited; the toy imports no oracle.
- MLX is called by one submitting thread, outside any OpenMP region. An executable run directly on the GPU
  runs with `MLX_ENABLE_TF32=0`. Timed runs are Release, on a machine with a one-minute load of at most 4.
- A large host array is not staged and released where a footprint is measured.
- The run writes its notes with the editor tools. Git is read-only: nothing is committed or pushed. SIMPLE is
  read at `28c753993` through `git show` and `git grep` only.

**Stops:**
- a wrapper is missing or refuses a call of decision 4, 5 or 9 (reported; never a private binding);
- a tolerance measured on the calibration fixtures is above its ceiling of decision 12, or a form fails an
  existing cap, after one attempt to find the fault in the toy;
- the reference-side lattice cannot be brought to the Fourier-Bessel oracle's cells (the exit's first clause);
- an oracle self-check fails on the unplanted code, or the oracle is suspected (the evidence, no edit);
- a digest of decision 20 moves before Phase 6;
- the graph form of a kept construction is not repeatable (decision 14), with the operation named;
- decision 16's mixed outcome (1.30 at one process, a judged split below 1.00);
- decision 1 is not ruled when Phase 0 reads the rulings;
- K3's result, rank 2g's or SIMPLE at `28c753993` contradicts a decision in a way no declared difference
  resolves; an identity digest of the base differs from `ae7d623`'s with no operation of 2g's report to
  explain it;
- a change to `src/core/`, `src/defs/` or `scripts/run_parts.sh` would be needed;
- the static gate fails on something the run did not touch.

Not stops, by decision: the particle-side lattice failing decision 2 (the plan continues as under A); a
ceiling below its rule (the form is removed or the phase recorded as not entered); a split the guard refuses.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
oracle shares no code with the toy; no SIMPLE source copied; a tolerance frozen before what it judges; decision
2 frozen before any lattice is timed; the graph reductions kept; repeatability of every kept form; the 30 % of
rules T and C.

## 8. Phases

### Phase 0, the base, the baseline and the probes (box: 90 min)

1. Record the machine, the base commit, SIMPLE's commit, the rulings (decision 1 above all) and the two
   recorded files' hashes. Build Debug and Release from scratch; run the gate; record section 5's counts.
2. Re-check the queue's premises against rank 2g's report, K3's report and code, and the premises of "What
   the check found" with `rg` and `git show`; write what changed. If decision 1 is not ruled, stop here.
3. Decision 20's identity invocations, twice each.
4. The baseline of decision 15, twice, with the stage profile; whether `read_map` admits case `2500_1` for
   decision 16's last split.
5. Add `mlxf_oracle_polar_tester.f90` and its registry row (decision 11); its plant.
6. Probes, in the benchmark's scratch or a scratch program, none kept in the repository: `mlx_fft` over
   (364, 30, 351, 4) and (364, 30, 43, 16) complex64 on both devices (it evaluates; its time; the MLX peak);
   the real-packed product at (2 x 351 x 30) by (2 x 30 x 16) per bin and particle; a kernel on a grid of 364
   by 256 threads with two rank-2 float32 outputs and an int32 input of more than 8 elements (one of fewer
   than 8 is measured, run `mlxf_kernel_forms`), read back by a SIMD-group-per-pair kernel; the gather of 16
   candidates' band from `self%refs` (the packed conjugated memo since rank 2e: the map's 30 shells in both
   row halves, conjugated back where the maps read the memo itself). No probe of `threadgroup` memory or of the SIMD-group functions: they
   are measured (Apple question 26), and kernels 2 and 4 re-check them in their own gates.
7. Freeze in Progress: the baseline, the fixtures' definitions of decisions 2 and 13, the probes' answers.

**Exit:** the counts, digests and baseline are in Progress; every premise is confirmed or its change written;
`oracle_polar` passes on the unplanted code and fails on its plant; no probe meets a stop; no lattice code
exists yet.

### Phase 1, the two lattices as graphs on the small fixtures (box: 240 min)

`mlxf_toy_polarft_workspace_lattice` with both frames; `set_shiftmap_form` and `shiftmap_shifts` through the
glue, with their stubs; `POLARFT_MAP_FORMS`, the new component of `polar_map_results`; both ledgers; the
tester's forms (decision 13) and the new sub-suite `polar_lattice`; `seam`'s cycles and refusals (decision 19).
Calibrate decision 12's measures, freeze them, then judge.

**Exit:** the reference-side lattice reproduces `oracle_shiftmap%cell_bessel` and `%cell` within the frozen
tolerances on both devices; the particle-side lattice reproduces the direct losses at its cells and equals the
reference-side one at the coinciding rotations; every reduction of both passes the existing caps; the modes'
shifts pass; decision 14 holds for both; the ten Phase 1 plants fail; rules `mirror` and `seam` pass; decision
20 holds; decision 13's time bound is met or its fallback taken.

### Phase 2, the decision-level test (box: 150 min)

1. Time one screen table of each lattice in the oracle at decision 2's geometry; predict the suite; shorten
   the ring if seeds 1 to 3 are predicted above 60 min.
2. `polar_lattice_decision`: seed 1 reported, then seeds 2 and 3 judged against decision 2's bounds; the three
   plants.
3. Apply decision 1's branch and write the candidate in Progress.

**Exit:** the statistics of P and of the control are in Progress per seed, grid and class; the verdict of
decision 2 is recorded; the candidate lattice is named by the ruling and this verdict; no lattice has been
timed.

### Phase 3, the bench size, the ceilings and the graph form's rate (box: 180 min)

1. `suite=maps` and `form=`, `tail=` in `suite=shiftmap` (decision 15); a part's row checked against the
   launcher's columns with one process and with two.
2. `polar_shiftmap_accuracy` for every form present, both devices.
3. The particle-tile sweep of the candidate, then decision 10's ceilings C1 (both lattices) and C2 (every
   construction present), each twice.
4. The graph form's rate of the candidate at one process on both grids, interleaved with the baseline, three
   pairs, with the stage profile and decision 22's bytes.
5. Apply decision 10's rules. Remove the lattice that is not the candidate (decision 17), after its numbers
   are in Progress.

**Exit:** the accuracy suite passes for every form that stays; C1 and C2 are in Progress with their rules'
outcomes; decision 1's table has a *measured* column; the benchmark and the toy hold the baseline and at most
one lattice; decision 20 holds.

### Phase 4, the fused reductions, only if decision 10 admits them (box: 210 min)

`mlxf_toy_polarft_workspace_maptail` (decision 9) behind `set_shiftmap_form`'s `tail`; its gates in
`polar_lattice` on the GPU, the graph form on the CPU device; the threadgroup, the row layout, kernels 1 and 3
as a thread or a SIMD group per (rotation, pair) on the screen grid, and decision 9's plain-sum variant swept
at the bench and frozen; the fallback taken by decision 9's rule if the four launches lose.

**Exit:** the fused form passes decision 12's last row and every reduction gate on the GPU for each
construction present, is refused on the CPU device with the graph form taking over, is repeatable (decision
14), and its four plants fail; or "not entered" stands with C2.

### Phase 5, the verdict at one, three and six processes (box: 210 min)

1. Freeze the configurations in Progress. Take one-process rows of every form present on both grids.
2. Decision 16's splits and pairs: the reductions' forms on each construction present, then the
   constructions' best forms. The launcher's guard decides which splits run.
3. Apply rule T, then rule C. Write the verdict table: per split, grid and form the total rate, the rate per
   process, the footprint, the MLX peak, the time from go to the last exit, the ratio and its validity.

**Exit:** both rules' outcomes are in Progress with their rows and load records; every split was run or
recorded as not run; the two invocations' digests agree per kept form; the two Phase 5 plants fail; or the run
stopped on decision 16's mixed outcome with the rows.

### Phase 6, the survivor and the record (box: 150 min)

1. Decision 17: the surviving construction becomes the default; the losers, the selector's `form` and the
   losing benchmark keys are deleted, with their ledger lines; "dead" is proved by a clean build.
2. Decision 18, if its condition holds: the refusal lifted, its gate and its plant.
3. The counts of `unit_kernels` and of each polar sub-suite frozen; decision 20 on what remains.
4. `planned/mlxf_kernel_families.md` (section 3's variants and numbers in hand, the seam facts with measured
   bytes, the differences from SIMPLE, section 8's row K4); the roadmap (decision 13's ruling and outcome,
   section 5); `doc/policies/test_environment_policy.md` (the suites, `suite=maps`, check 13's sentence); the
   plans' index; the history; `src/test/toys/polar/polar.inf` and `doc/code_base_map.md` for the files kept
   and deleted; the root `README.md` where it names the maps.
5. The last-phase gates of section 5.
6. The report `completed/mlxf_kernel_k4_report.md`, in the order of the how-to's section 8: what was learned,
   the changes per phase, decisions under delegation, deviations, evidence against the baseline, what is left
   open, proposals for the skills and `CLAUDE.md` (not edited), and a commit message that carries no
   attribution or co-author line and names every new file.

**Exit:** one construction of the maps exists and passes every map gate as the default on both devices; the
report exists; `scripts/check_tree.sh` and the last-phase gates pass; `git status` shows file-table paths only.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/oracles/mlxf_oracle_polar_tester.f90` (new) | sub-suite `oracle_polar`: the two self-checks asserted | 0 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_lattice.f90` (new) | device submodule: the lattice's preparation and construction | 1, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_maptail.f90` (new) | device submodule: the fused reductions' kernels | 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_lattice_tester.f90` (new) | sub-suites `polar_lattice` and `polar_lattice_decision` | 1, 2, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace.f90` | the map record's members, the interfaces of the new module procedures | 1, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_shiftmap.f90` | the form's branch; the reductions fed by either construction; decision 17's deletion | 1, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_calc.f90` | the additions' interfaces, the form's members | 1, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap.f90` | `set_shiftmap_form`, `shiftmap_shifts`; decision 18's refusal | 1, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_core.f90` (added in Phase 1) | `kill` resets the maps' form members and drops the last modes' shifts, as it does every other map member | 1, 3, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap_mlx.f90` | the glue's bodies and stubs of the same | 1, 4, 6 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab.f90` | `batch_map_results` with the shifts | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap_tester.f90` | the tests per form, the private oracle's frame; `test_folding` with decision 17 | 1, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab_tester.f90` | the driver's map results per form | 1, 3, 6 |
| `src/test/toys/mlxf_toy_seam_tester.f90` | the cycles and refusals of decision 19 | 1, 3, 4, 6 |
| `src/test/toys/polar/mlxf_toy_*.f90` (new, decision 23) | submodules of a toy file that passes 700 lines | 1, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_mapreduce.f90` (new, decision 23, Phase 1) | device submodule: the maps' reductions of a tile (selection, width, evidence, copy-out) and their compiled callbacks, moved out of `_workspace_shiftmap.f90` (699 lines) so that both constructions feed them | 1, 3, 4, 6 |
| `src/test/framework/mlxf_test_defs.f90` | `POLARFT_MAP_FORMS`, the record's component, decision 12's tolerances, decision 2's constants | 0, 1, 2, 3, 4, 6 |
| `src/test/framework/mlxf_test_registry.f90` | rows `oracle_polar`, `polar_lattice`, `polar_lattice_decision`; one `NAMED_ONLY` name | 0, 1, 2, 3 |
| `src/test/bench/mlxf_bench_polar_table.f90` | `suite=maps`; `form=` and `tail=`; the rows; decision 17's columns | 3, 4, 5, 6 |
| `src/test/toys/polar/polar.inf` | the folder's description: the lattice and the fused reductions | 1, 3, 4, 6 |
| `src/test/oracles/oracles.inf` | the folder's description: the oracles' tester | 0 |
| `doc/code_base_map.md` | regenerated by `scripts/generate_codeoverview.py` in each phase that adds or deletes a Fortran file or edits an `.inf` (the static gate checks it) | 0, 1, 2, 3, 4, 6 |
| `test/offstate/mlxf_offstate_exec.f90` | one check: the maps refuse the host backend | 1 |
| `scripts/toy_mirror.txt` | the additions' lines; the declared difference of `ialpha`; decision 17's lines | 1, 3, 6 |
| `scripts/toy_seam.txt` | the two device submodules | 1, 3, 4, 6 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | sections 3 and 8, the seam facts | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | decision 13's ruling and outcome; section 5 | 6 |
| `doc/policies/test_environment_policy.md` | the suites, the benchmark, the unread-key sentence | 6 |
| `doc/implementation_notes/README.md` | the index | 6 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 6 |
| `README.md` | the status, where it names the maps | 6 |
| `doc/collaboration/apple_questions.md` | if a question arises (decision 24) | 0, 3, 4, 5 |
| `doc/implementation_notes/planned/mlxf_kernel_k4.md` | this note: Progress, decision 23's rows | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/completed/mlxf_kernel_k4_report.md` (new) | the report | 6 |

Phase 3 was added to the rows above whose files the removal of the lattices (decisions 10 and 17, Phase 3's item
5) touches. Phase 4 was added to the calculator's parent, its shift-map submodule and the shift-map tester: with no
lattice left, the fused reductions' selection and gates live with the Fourier-Bessel maps. `mlxf_test_defs.f90`, `mlxf_test_registry.f90`, the folders' `.inf` files, `doc/code_base_map.md`, both
ledgers, `test/offstate/`, the families note, the polar toy's files and `mlxf_bench_polar_table.f90` are shared
with the other kernel runs of this batch: this run starts from a commit that holds every earlier run's result
and rank 2g's.

## Progress

(one entry per phase, written by the run: date and times, machine, base, files changed, each exit item and how
it was shown, the frozen numbers with their origin, the plants and the checks that failed on them, the load
records, the decisions taken under delegation with their reasons, and every log's path)

### Phase 0, 2026-11-26, 22:22 to 22:45 (the base, the baseline and the probes)

**Machine and base.** The M5 Ultra (30 cores, 103,079,215,104 B, macOS, GPU `applegpu_g17d`, 1 GPU device in
`unit_core`), GNU Fortran 16.2.0, CMake 4.5.1, MLX 0.32.4, mlx-c 0.8.0 from Homebrew (the maintainer's
`build/` uses the same). Base `90f5932f10197247baf001a1087682fc34bd353d` (rank 2g committed), worktree clean
at the start. SIMPLE `28c75399385fdf73909f350d00cf3019ec92d2a4`. Recorded inputs: `shiftmap_grid.txt`
`aa05ca27...2eca` and `polar_case.txt` `90a974fa...f1d9`, both equal to the plan's (*exact*). Builds: run
directory `scratch/build.sh` (the run's recipe: from scratch, `-DMLXF_WERROR=ON -DFORTLS=OFF
-DBUILD_TESTS=ON`, `-j 12`, the fast gate, the install).

**Rulings.** `spec/rulings.md` is empty. Decision 1 is ruled **B** by the roadmap's decision 18 ("every
decision of section 3 of each plan stands as recommended"); recorded at the head of section 3. The plan goes
on: no stop under "decision 1 is not ruled".

**Files changed:** `src/test/oracles/mlxf_oracle_polar_tester.f90` (new), `src/test/framework/mlxf_test_registry.f90`
(row `oracle_polar` after `oracle_projection`), `src/test/oracles/oracles.inf`, `doc/code_base_map.md`
(regenerated), this note.

**Exit items.**
- *Both builds without a warning, the gate, the counts.* The base, from a pristine copy of the base sources
  (`scratch/base_src`): Release 0 warnings, fast gate 13 of 13 (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/p0_build_base_release.log`); Debug 0
  warnings, 13 of 13 (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/../p0_build_debug.log`). The base's counts (*measured*), Debug / Release:
  `unit_core` 216 / 214, `unit_array` 232, `unit_ops` 2,988, `unit_fft` 194, `unit_linalg` 674, `unit_compile`
  63, `unit_fast` 152, `unit_random` 486, `unit_transforms` 283, `unit_io` 905, `unit_distributed` 55,
  `unit_kernels` 1,953 (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/counts_debug/`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/counts_base_release/`). Against section 5's `ae7d623`
  counts rank 2g raised `unit_array` (193 to 232), `unit_ops` (2,462 to 2,988), `unit_linalg` (632 to 674),
  `unit_transforms` (274 to 283) and `unit_io` (846 to 905); every other count, `unit_kernels` included, is
  unchanged. Phase 0's code, from scratch: Debug and Release 0 warnings, fast gate 13 of 13 (11.9 s of its
  60 s budget in Release), `scripts/check_tree.sh` passed (one warning: the new file is
  untracked, as nothing is committed) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/p0_final_build_debug.log`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/p0_final_build_release.log`);
  counts as the base's with **`unit_kernels` 1,999** in both builds (1,953 + 46), `unit_core` 216 in both
  (within its known 214 to 216) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/counts_final_debug/`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/counts_final_release/`). The counts the
  later phases hold: the base's above, `unit_kernels` 1,999 plus each phase's checks.
- *Decision 20's identity invocations, twice.* The 364-line identity set (the tool of runs `mlxf_toy_layout`,
  `mlxf_kernel_forms` and `mlxf_user_hardening`, copied to `scratch/keep/tools/identity.sh` with only paths
  changed; it holds the dense table's digests on both devices and both tails, the projector chain's device
  and host routes, the Fourier-Bessel maps on both grids at `ptiles=16` and the off-state table) on the base
  Release twice: equal, SHA-256 `e2d65e8861d23ef7d731960e17269c6ecaed23fc46d735a1dc37f0bb4d33dba5`, equal byte
  for byte to rank 2g's last copy (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/identity_ab.log`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/identity_a/`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/identity_b/`). Rank 2g moved
  no digest, so no operation of its report is needed. The same set on Phase 0's Release: equal to the
  base's (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/identity_final.log`).
- *The baseline, twice, with the stage profile* (decision 15; `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/baseline/run_baseline.sh`, base Release,
  `suite=shiftmap case=2500_4`, the recorded grid, `maps=window,screen ptiles=4,16 widths=all evidence=0
  device=gpu`). Load before / after: run 1 3.35 / 4.01 (after a 75 s wait), run 2 3.27 / 3.08; nothing else of
  the run ran. *Measured*, maps per second, run 1 / run 2:

  | Map | ptile | rate | construct / select / reduce, us per map | MLX peak, B | digest |
  | --- | --- | --- | --- | --- | --- |
  | window | 16 | 7.8451e4 / 7.8162e4 | 9.40 / 1.03 / 1.91 | 1.074e10 | `CCF8071F11C612F9` |
  | window | 4 | 5.2249e4 / 5.1779e4 | 10.83 / 3.42 / 4.60 | 1.011e10 | `CCF8071F11C612F9` |
  | screen | 4 | 1.9863e4 / 1.9893e4 | 33.57 / 4.73 / 11.30 | 1.072e10 | `3218B5567D7482E9` |
  | screen | 16 | 1.8888e4 / 1.8906e4 | 37.40 / 3.58 / 11.45 | 1.315e10 | `3218B5567D7482E9` |

  **The baseline (frozen): window 7.83e4 maps per second at ptile 16, screen 1.99e4 at ptile 4** (the mean of
  the two runs, *measured*). Prepared device memory 9.770e9 B with the tiles (9.77e9 in the families note:
  unchanged), host 3.930e9 B (*measured*, column `prepared_device_bytes`, `host_bytes`). The canonical
  driver's elapsed time at the baseline (decision 15): 32,000 / 7.83e4 + 32,000 / 1.99e4 = 0.409 + 1.608 =
  2.017 s, the screen 80 % (*derived*). The window rate is 5.1 % and 4.8 % above milestone 1's 7.46e4 (7.45e4
  in decision 15), run 1 beyond the 5 % mark; the screen rate is 0.2 % below. Cause sought once: no report
  after milestone 1 records a map rate (searched in `completed/`), the digests are the base's, and the code
  of the maps changed since milestone 1's `4706ecb` (runs `mlxf_toy_seam`, `mlxf_toy_layout`: the memo
  layout, the preparation from `ft_ref_terms`); no single cause is identified. The Phase 0 rate is the
  baseline, as the decision says. Bench logs and rows: `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/baseline/run1/`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/baseline/run2/`.
- *Case `2500_1` for decision 16's last split.* `read_case` reads it from `polar_case.txt` (nrefs 2,500,
  nptcls 2,000), but `check_map_case` stops with status 2 on the recorded grid file, whose maps carry nrefs
  10,000. Decided under delegation (below).
- *The queue's premises.* K3 has not run (no K3 report; the roadmap's decision 18 orders K4 first), so the
  queue's "If K4 runs before K3" holds: decision 5 stands as written, the counts and identity invocations are
  this base's, decision 11's tester asserts both self-checks (K3 asserted neither), and K3 reads this run's
  report before its Phase 2. Rank 2g changed `src/core/`, scripts and documents and no file under `src/test/`
  except the registry (its own benchmark row) and `bench.inf` (`git diff --stat ae7d623 90f5932 -- src/test
  test`); its report states the identity set unchanged, which Phase 0 confirms.
- *The premises of "What the check found",* re-read at the base and in SIMPLE at `28c753993` with `rg` and
  `git show`: checks 1 to 15 confirmed (the toy files did not change since `ae7d623`). Details worth keeping:
  `rho_max` is the last ring `(nrho - 1) step`, not the radius, in both codes; both use `nrho = 2, step =
  radius` when the disc is smaller than one step; `shiftmap_draw` is also called by SIMPLE's own tester
  submodule (not production); the last Apple question is 36, so this run's questions start at 37; question 26 says what
  check 15 states.
- *`oracle_polar` asserted* (decision 11): the new tester asserts `oracle_shiftmap_selfcheck` (21 checks) and
  `oracle_polar_selfcheck` (25) within their own limits: 46 of 46, Release 0.24 s, Debug 0.41 s
  (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/counts_final_release/unit_kernels.log`). Largest errors (*measured*): bessel vs direct cell 2.121e-9
  (limit 1e-6), bessel cc vs direct 1.112e-9 (1e-6); every other check at most 1.3e-15 or exact. The plant: a
  copy with `limits(12) = 0.5 errors(12)` (the bessel-vs-direct limit halved below its measured error) fails
  exactly that check, 45 of 46 (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/plant_oracle_polar.diff`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/plant_oracle_polar_run.log`).
- *The probes* (item 6; a scratch program against the base install, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/probes/k4_probes.f90`, runs
  `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/probes/probes_run1.log`, `probes_run2.log`; load 2.4 to 2.5; times are medians of 7 evaluations each
  with a wait, the first included, so a graph pays less; *measured*, from run 2):
  - `mlx_fft` over the ring, complex64: (364, 30, 351, 4) evaluates on both devices, GPU 0.75 ms (best 0.70),
    CPU 41.3 ms, MLX peak 245 MB; (364, 30, 43, 16) GPU 0.45 ms (best 0.40), CPU 20.1 ms, peak 120 MB. One
    column against a direct double-precision DFT: relative error 5.8e-7 (GPU), 1.6e-7 (CPU).
  - The real-packed product per bin and particle, (702 x 60) by (60 x 16) batched over 183 bins x 4
    particles: GPU best 0.77 ms (1.28 TFLOP/s), CPU 2.3 ms; the window's (86 x 60) by (60 x 16) over 183 x 16:
    GPU best 0.38 ms, CPU 1.3 ms; largest error against a double product 8.4e-6 on sums of 60 terms of [0, 1).
  - A kernel on a grid of 364 by 256 threads with two rank-2 float32 outputs and an int32 table of 385 (and
    56) cells, read back by a SIMD-group-per-pair kernel (`simd_max`, then `simd_min` of the least rotation
    among the maximal lanes): every partial (93,184) and every pair's mode, value, rotation and cell equal
    to the host's bit for bit; both launches 2.0 ms best (385 cells) and 0.26 ms (56 cells).
  - The gather of 16 candidates' band (rows 1..30 and nk+1..nk+30 of the first row block, columns c and rt +
    c, all 183 bins) from an array shaped like `self%refs` at the bench (244, 500, 183, 40), float32, by one
    `mlx_take` of element positions: exact on a small array (288 of 288 elements); 0.58 ms for 256 pairs (16
    particles), 0.29 ms for 64 pairs (4 particles). `mlx_take` without `dim` takes **1-based** positions, as
    its reference says (the probe's first run used 0-based ones and failed its own check: `probes_run1.log`).
  - What they say, *derived* and not a criterion: per screen map at ptile 4 the transform (0.70 ms / 64
    maps) and the product (0.77 / 64) are 11 and 12 us, against the Fourier-Bessel construction's 33.6 us;
    with the inverse transform, the phase product and the gather (0.29 / 64 = 4.6 us) the particle-side
    construction is near the Fourier-Bessel one, and C1's 1.30 is not in sight from these probes alone. The
    window's gather (0.58 ms) is larger than its transform and product together; decision 5's 20 % rule is
    judged on the construction in Phase 3, not here. No probe meets a stop: every wrapper evaluated.

**Frozen in Phase 0.**
- The baseline above (window 7.83e4 at ptile 16, screen 1.99e4 at ptile 4, *measured*), and the counts.
- Decision 2's fixtures as written in section 3, made concrete: pftsz 52 (104 rotations), 8 shells, the M5
  grids' (nrho, nalpha) = (4, 14) and (11, 35) with their 43 and 351 distinct shifts; per grid and seed 32
  representative and 32 near-tie pairs (12 midway, 12 two-copy at ratios 1, 1 + 1e-3, 1 + 1e-2, 1 + 1e-1, 8
  twofold-symmetric at the last three ratios); retention 8 particles x 16 candidates, 8 of them one reference
  perturbed by 1e-3 to 1e-1 of its norm, nbest 4; seed 1 reported, seeds 2 and 3 judged; the bounds and the
  three plants of decision 2, unchanged.
- Decision 13's fixtures as written: calibration the unperturbed analytic fixture, the oracle's size 1 and
  seed 1; judged the perturbed fixture, the oracle's sizes 2 and 3, seeds 2 and 3; the time bound: at most
  5 s added to `unit_kernels` in Release over Phase 0's 5.9 s alone (base 5.6 s; `oracle_polar` adds 0.3 s;
  load 5.7 to 7.2, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase0/kernels_time.log`; the gate's per-entry times run in parallel and vary, 6.3 s and
  9.7 s), and the fast gate under 38.74 s.
- The probes' answers above.

**Decisions taken under delegation.**
1. The base was measured from a pristine copy of the base sources (`scratch/base_src`, the repository's
   files with the run's edits taken back from HEAD) because an edit of the registry during the first Release
   build broke that build (the run's own error); the Debug base build had finished before any edit.
2. Decision 20's invocations are the 364-line identity set by the earlier runs' tool, paths changed only: it
   holds every invocation the decision names, and its digest is comparable with rank 2g's.
3. The baseline invocation runs `ptiles=4,16` on both maps (as milestone 1's traces did), so one invocation
   gives the window's row at 16 and the screen's at 4; the frozen rate is the mean of the two runs (they
   differ by 0.4 % and 0.2 %).
4. Decision 16's split on `2500_1`, if Phase 5 needs it, uses a scratch copy of the recorded grid file with
   `nrefs = 2500` in both map blocks and nothing else changed (the geometry is the case's; the file's SIMPLE
   rates do not apply to it and are not reported beside that row). The recorded file itself is not edited.
5. The plant of `oracle_polar` lowers the limit of the check with the largest measured error (bessel vs
   direct cell), since halving a zero limit cannot fail an exact check.

**What it means, in short.** The base is green, rank 2g moved counts but no toy output, the oracles are now
asserted by the registry, and the Fourier-Bessel maps run at 7.83e4 (window) and 1.99e4 (screen) maps per
second, 2.02 s for the canonical driver. Every operation the lattice needs evaluates and is exact where it
can be checked; the probes suggest the particle-side construction will be close to the Fourier-Bessel one,
which is what Phase 3's ceilings will decide.

### Phase 1, 2026-11-26, 22:39 to 23:20 (the two lattices as graphs on the small fixtures)

**Machine and base** as in Phase 0 (the M5 Ultra, base `90f5932`, Phase 0's working tree). The standing ruling of
the roadmap's decision 19 (MLX-centric, a CUDA twin section in the report) appeared in the run's
`spec/rulings.md` and is recorded at the head of section 3; Phase 1 builds graphs only.

**Files changed:** new `src/test/toys/polar/mlxf_toy_polarft_workspace_lattice.f90` (device: the lattice's
preparation and construction), `mlxf_toy_polarft_workspace_mapreduce.f90` (device, decision 23: the reductions
of a tile and their compiled callbacks, moved out of `_workspace_shiftmap.f90`), `mlxf_toy_polarft_lattice_tester.f90`
(sub-suite `polar_lattice`); edited `mlxf_toy_polarft_workspace.f90` (the map record's form, phase table and cell
rows; the shared tile records; the interfaces), `mlxf_toy_polarft_workspace_shiftmap.f90` (the form's branches,
the particle-side cosines, the modes' shifts), `mlxf_toy_polarft_calc.f90` (`set_shiftmap_form`,
`shiftmap_shifts`, the form members), `mlxf_toy_polarft_shiftmap.f90` (their bodies; the form recorded per map),
`mlxf_toy_polarft_core.f90` (row added to the table first: `kill` resets the new members),
`mlxf_toy_eul_prob_tab.f90` (`batch_map_results` with the shifts), the testers
`mlxf_toy_polarft_shiftmap_tester.f90`, `mlxf_toy_eul_prob_tab_tester.f90`, `mlxf_toy_seam_tester.f90`,
`test/offstate/mlxf_offstate_exec.f90`, `mlxf_test_defs.f90` (`POLARFT_MAP_FORMS`, `polarft_map_spec%form`,
`polar_map_results%shifts`, the lattice tolerances), `mlxf_test_registry.f90` (row `polar_lattice`), both
ledgers, `polar.inf`, `doc/code_base_map.md`, this note.

**What was built.** Both lattices follow the oracles' conventions, read in Phase 1: a shift multiplies a ring sample
by exp(i z sin(theta - alpha)), z = 2 pi k rho / box, and `oracle_polar_frame` is [[c, s], [-s, c]] (the plan's
default "the frame's sign is whatever makes the particle-side cell equal `oracle_polar_pair%dist`" is settled
as: a particle-side cell at shift u in the particle's axes is the loss at `matmul(oracle_polar_frame(irot,
nrots), u)`, and the particle copy carries the conjugate phase). Per tile the operand's ring is recovered from
its memo bins (F[nrots - m] = (-1)^m conj F[m]), multiplied by the map's resident phase table (nrots, nkb, nud),
transformed back to its 183 bins; the particle-side sums are one real-packed `matmul` per bin and particle
against the weighted candidates gathered from `self%refs` (one `mlx_take` of 1-based element positions per row
half), the reference-side sums an elementwise product per pair; `mlx_irfft` over the bins gives every rotation's
cross term; L = 1 + (refpow - cross) / ptclpow with the reference power computed once per pair from the tiles'
squared-modulus rows, as the Fourier-Bessel form computes it; the cells take their distinct shift's row
(`cellrow`) and feed the existing compiled reductions, the particle-side lattice with cosines 1 and sines 0
(its moments are in the particle's axes already). The Fourier-Bessel form's operations are unchanged
(decision 20 below).

**Exit items.**
- *The reference-side lattice reproduces `%cell_bessel` and `%cell` within the frozen tolerances on both
  devices; the particle-side lattice reproduces the direct losses at its cells and equals the reference-side one
  at the coinciding rotations; the modes' shifts pass.* Sub-suite `polar_lattice` on the oracle's fixtures
  (size 1 unseeded and seed 1 calibrate; sizes 2 and 3 and size 1 seeds 2 and 3 are judged), largest absolute
  errors (*measured*, Release, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/rel_kernels_run1.log`; Debug `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/counts_debug/unit_kernels.log`):

  | Measure | calibration cpu / gpu | judged cpu / gpu | frozen tolerance | ceiling |
  | --- | --- | --- | --- | --- |
  | reference-side against `%cell_bessel` | 5.24e-7 / 6.39e-7 | 5.06e-7 / 6.28e-7 | 1.2772e-6 | 1e-4 |
  | reference-side against `%cell` | 5.24e-7 / 6.39e-7 | 5.06e-7 / 6.28e-7 | 1.2772e-6 | 1e-4 |
  | particle-side against the direct loss | 5.28e-7 / 5.55e-7 | 5.64e-7 / 6.32e-7 | 1.1106e-6 | 1e-4 |
  | the two lattices at a coinciding rotation | 4.77e-7 / 4.77e-7 | 4.77e-7 / 4.77e-7 | 9.536e-7 | 2e-4 |
  | the mode's shift against the oracle's (px) | at most 2.2e-16 (0 in Release) | 2.2e-16 / 2.2e-16 | 1e-12 | 1e-4 |

  The calibration numbers are those of the first run, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/dbg_lattice_try1.log` (Debug); each tolerance is twice
  the largest calibration error over both devices (*derived*), the shift's at least 1e-12 for host rounding
  (*guessed*); the judged fixtures did not enter them. Modes judged where the oracle's margin exceeds
  `POLAR_MAP_CAP_LOG`: 8 of 8 per lattice and device on the calibration fixtures, 16 of 16 on the judged ones,
  none inside the margin.
- *Every reduction of both passes the existing caps.* In `polar_lattice`: the maps' L2 against the oracle's
  tables at most 1.27e-7 (cap 1e-4), the variance at most 1.93e-7 relative (cap 1e-4), the evidence at most
  6.98e-7 (cap 1e-4). In `polar_shiftmap`, which now runs every test but `test_folding` per construction with its
  private oracle reading a particle-side cell at its turned shift: every cap holds for the three forms on both
  devices (2,346 checks; largest map error 7.59e-7 normalised L2 on the particle-side lattice).
- *Decision 14 holds for both.* In one process the modes, losses, widths, evidence, maps and shifts of the
  fixture block are bit for bit equal across two evaluations on each lattice and device; across two invocations
  the printed digests agree (Release: `4529DEA7D7330CC0`, `1C56BF6DA9EA3CD6` cpu, `79F1D6C0A656F0E9`,
  `377B9DF958A789E8` gpu, forms 2 and 3; `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/time_kernels.log`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/rel_lattice_inv_a.log`, `_b.log`).
- *Decision 19.* `seam`: the host backend refuses `set_shiftmap_form` and `shiftmap_shifts` with the backend's
  message, and 100 cycles of `new_shiftmap`, `gen_shiftmap`, `shiftmap_mode` and `kill_shiftmap` per construction
  leave the live handles and the active memory where a warm cycle left them, on both devices (110 checks). The
  off-state program checks that a host-backend calculator refuses `new_shiftmap` with today's message ("the toy's
  shift maps run on the MLX backend only"): passed in its Debug and Release builds
  (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/identity/offstate/Debug.run.log`, `Release.run.log`).
- *The ten Phase 1 plants fail,* each in a patched copy built apart (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/plants/patch.py`, `run_plant.sh`,
  `run_all.sh`; diffs and logs `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/plants/<plant>.diff`, `.run.log`; a first pass on the code before the tester's
  last refactor in `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/plants/first_pass/`, the same outcome): the shift phase with the opposite sign
  (`polar_lattice`: every cell measure, the modes, the shifts); the first ring counted once (the evidence, the
  width, the maps); the mode's scan with directions outermost (the modes' indices and shifts in `polar_lattice`,
  the modes in `polar_shiftmap`); the particle-side width with the reference-side rotation left in (the width,
  on both devices, and nothing else); the frame transposed in `shiftmap_shifts` (the shifts in `polar_lattice` and
  the driver's in `eul_prob_tab`); the band one shell short (the cells, the modes, the reductions); a candidate
  gathered from the neighbouring tile column (`polar_shiftmap`'s cells and modes on the lattices); a public
  addition missing from the mirror ledger (rule `mirror`); the new device submodule classed `host` (rule `seam`);
  a term that depends on the call count added to a row (decision 14's bit-for-bit check, and the cells).
- *Rules `mirror` and `seam` pass:* `scripts/check_tree.sh` passed in both builds' gates (the warning names the
  four new files as untracked: nothing is committed).
- *Decision 20 holds:* the 364-line identity set on Phase 1's Release equals the base's byte for byte, SHA-256
  `e2d65e88...4d33dba5` (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/identity.log`).
- *Decision 13's time bound is met:* `unit_kernels` alone in Release 9.79 and 9.72 s against Phase 0's 5.86 and
  5.89 s, +3.9 s within the 5 s bound (*measured*, load 3.84 before and 3.30 after, nothing else of the run
  running; `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/time_kernels.log`); the fast gate 13.41 s (Release) under its 38.74 s. No fallback taken.
- *Builds:* Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, fast gate 13 of 13
  (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/p1_build_debug.log`, `p1_build_release.log`). Counts, Debug and Release alike: every area as Phase 0's
  base, **`unit_kernels` 3,799** (1,999 + 1,800: `polar_shiftmap` 794 to 2,346, `polar_lattice` 154 new,
  `eul_prob_tab` 105 to 177, `seam` 88 to 110) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/counts_debug/`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase1/counts_release/`).

**Frozen:** the five tolerances above in `mlxf_test_defs.f90`; `unit_kernels` 3,799.

**Decisions taken under delegation.**
1. The reductions and their callbacks moved to a new device submodule (`_workspace_mapreduce.f90`, decision 23,
   row added before the edit) so that both constructions feed them; the tile's maps became a component of the
   tile record so that the shared procedures keep five dummies (rule `arity`). The Fourier-Bessel form's graph is
   unchanged (identity holds).
2. `mlxf_toy_polarft_calc.f90` grows to 746 lines (724 at the base, already above decision 23's 700): it is the
   parent that declares the interfaces, which no submodule can hold; not split. The shift-map tester (1,298 lines
   at the base, 1,367 now) is a tester, which the size rules except.
3. `set_shiftmap_form` and `shiftmap_shifts` keep host state only; their device effect passes through the
   existing glue (`new_shiftmap_mlx` carries `spec%form`, `shiftmap_mode_mlx` returns the shifts), so no new glue
   procedure or stub was written.
4. `set_shiftmap_form` refuses `tail = metal` ("the compiled graph only") until Phase 4 builds the fused form; a map
   remembers its form, and `shiftmap_mode` refuses a map made in another form until it is made again.
5. A lattice map is refused without current reference tiles (it keeps no reference data, decision 5); the
   gather's 32-bit element positions are guarded (refused above 2^31 - 1).
6. Decision 12's measures are computed on the oracle's fixtures in `polar_lattice`; the analytic fixtures of
   `polar_shiftmap` judge the existing caps per form. Tolerance = twice the largest calibration error over both
   devices, the shift's floor 1e-12.
7. The particle-side lattice's known-pose check in `polar_shiftmap` judges only the planted poses that are cells of
   that lattice (at a coinciding rotation): 2 of the fixture's 3 (the pose at rotation 17 is not); the guard of at
   least three stays for the other forms.
8. Plant 3 ("the mode's scan with directions outermost") was built as the selection reading the maps in the
   directions-outermost order, which moves the decoded modes on every fixture; no exact-tie fixture was built (a
   float32 tie between cells of different rings and directions is not constructible on these grids). Recorded as a
   deviation from "on a tie fixture".
9. The modes' shifts are real64 (`polar_map_results%shifts`), computed on the host from the mode's indices.
10. The fixtures' noise (size 1, seeds 1 to 3) is a keyed variate per sample, 0.1 of the particle's rms, on the
    second particle; the calculator uses tiles of one reference (`set_tile_plan(2, 1)`), so the gather crosses tiles.
11. A Release-only `-Wuninitialized` diagnostic (a tester record with an allocatable component) was removed by
    keeping the record fixed-size; no flag was touched.

**What it means, in short.** Both lattices exist as graphs and are as exact as float32 allows: about 6e-7 from the
oracle's cells, the shifts exact, every mode the oracle's. The particle-side lattice equals the reference-side one
where their grids share points. Nothing of the Fourier-Bessel form moved. Phase 2 judges whether the particle-side
lattice's cells, which are not SIMPLE's, change any decision.

### Phase 2, 2026-11-26 23:14 to 2026-11-27 00:20 (the decision-level test)

**Machine and base** as before; the standing ruling of decision 19 changes nothing here (host-only test).

**Files changed:** `src/test/toys/polar/mlxf_toy_polarft_lattice_tester.f90` (the named-only sub-suite
`polar_lattice_decision`; the header names it), `src/test/framework/mlxf_test_defs.f90` (decision 2's constants,
`POLAR_DECISION_*`, as section 3 states them), `src/test/framework/mlxf_test_registry.f90` (row and `NAMED_ONLY`
name `polar_lattice_decision`), `doc/code_base_map.md` (the tester's description), this note.

**What the test does** (host only, double precision, the oracle): the geometry is pftsz 52 (104 rotations), 8 shells
(2 to 9), box 64, the window's and the screen's rings (nrho 4 and 11), which give the M5 grids' 14 and 35
directions (*exact*, asserted). Per seed and grid: 32 representative pairs (point-source references, a planted
rotation and an off-lattice shift anywhere in the disc, an astigmatic CTF, keyed noise at 0.1 and 0.5 of the
signal's rms, alternating); 32 near-tie pairs (12 shifts midway between two rings or two directions, 12 sums of
two shifted copies at amplitude ratios 1, 1 + 1e-3, 1 + 1e-2, 1 + 1e-1, three each, 8 twofold-symmetric
references broken by 1e-3 to 1e-1); 8 retention particles with pools of 16 (8 the particle's reference perturbed
by 1e-3 to 1e-1 of its norm, log-spaced, 8 others), nbest 4. The three lattices of a pair: R (SIMPLE's cells), P
(the particle-side lattice) and R' (SIMPLE's directions turned by half a step); every table by the oracle's ring
route (`dists_by_rings`), P with the particle carrying the conjugate phase of the cell's shift. The route is held
to the oracle's direct cells on one screen pair: R against `oracle_shiftmap%table` 3.6e-15, P against `pair%dist`
at the turned shift 2.4e-15 (*measured*). Modes by `oracle_shiftmap%mode` (tempered temperature, the screen with a
prior of width half the disc's radius, the window without, as SIMPLE's screen and window), widths at the
physical temperature (moments turned into the particle's axes on R and R'), the sequential width cutoff of
`update_screen_best` over the pool with nper = nbest.

**Exit items.**
- *Item 1, the time of one screen table* (Release, load 2.0): 1.16, 1.14, 1.14 s for R, P, R' (*measured*);
  predicted suite 33 min on the screen grids (*derived*), under 60: the ring was not shortened. The suite took
  2,402 s (load about 4.1 at its end; `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase2/decision_run1.log`).
- *The statistics of P and of the control per seed, grid and class* (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase2/decision_run1.log`; T1 the pairs whose
  modes' shifts differ from R's by more than one map step in a component, T2 the particles whose kept best differ,
  T3 count the widths skipped in one table and not the other; each "P / control"; the widths' largest absolute
  difference in pixels, reported):

  | seed | grid | class | pairs | T1 | T2 | T3 count | width abs. diff. (px) | bound |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | 1 | window | representative | 32 | 3 / 1 | - | - | 1.08 / 0.774 | reported |
  | 1 | window | near-tie | 32 | 4 / 7 | - | - | 1.03 / 2.84 | reported |
  | 1 | window | retention | 128 | 8 / 15 | 4 / 8 | 5 / 10 | 4.15 / 4.12 | reported |
  | 1 | screen | representative | 32 | 4 / 3 | - | - | 0.492 / 0.421 | reported |
  | 1 | screen | near-tie | 32 | 12 / 14 | - | - | 10.2 / 6.39 | reported |
  | 1 | screen | retention | 128 | 8 / 11 | 6 / 7 | 6 / 13 | 10.9 / 7.92 | reported |
  | 2 | window | representative | 32 | 0 / 3 | - | - | 0.606 / 1.25 | passes |
  | 2 | window | near-tie | 32 | 5 / 7 | - | - | 0.906 / 0.906 | passes |
  | 2 | window | retention | 128 | 9 / 11 | 5 / 6 | 9 / 10 | 1.92 / 2.86 | passes |
  | 2 | screen | representative | 32 | 4 / 2 | - | - | 0.74 / 0.858 | **fails T1** |
  | 2 | screen | near-tie | 32 | 9 / 12 | - | - | 11 / 13.6 | passes |
  | 2 | screen | retention | 128 | 17 / 16 | 5 / 7 | 11 / 14 | 10.4 / 12.8 | passes |
  | 3 | window | representative | 32 | 1 / 1 | - | - | 1.1 / 0.862 | passes |
  | 3 | window | near-tie | 32 | 5 / 7 | - | - | 2.62 / 0.947 | passes |
  | 3 | window | retention | 128 | 6 / 9 | 7 / 7 | 10 / 10 | 3.86 / 4.19 | passes |
  | 3 | screen | representative | 32 | 2 / 1 | - | - | 0.622 / 0.675 | passes |
  | 3 | screen | near-tie | 32 | 11 / 16 | - | - | 6.84 / 5.63 | passes |
  | 3 | screen | retention | 128 | 29 / 23 | 5 / 7 | 6 / 10 | 14.1 / 9.22 | **fails T1** |

  T3's relative difference is 1.000 for P and for the control in every row: in each class some pair has a width of 0
  in one table (all its mass in one cell) and not in the other. Summed over the judged rows T1 is 98 for P and 108
  for the control (*measured*).
- *The verdict of decision 2:* **the particle-side lattice fails** on the judged seeds: T1 exceeds the control's plus
  one in two of the twelve judged rows (seed 2, screen, representative: 4 against 2; seed 3, screen, retention: 29
  against 23); every T2, T3-count and T3-relative bound holds.
- *The candidate, by decision 1's branch B:* P failed decision 2's test, so the plan continues as under A: **the
  candidate lattice is the reference-side lattice** (SIMPLE's cells). Phase 3 removes the particle-side lattice after
  its numbers are in Progress (decision 17), measures the reference-side ceiling C1 and the Fourier-Bessel form's
  C2, and applies decision 10's rules.
- *The three plants fail* (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase2/plants/patch.py`, `run_plant.sh`, each built apart in Release; `<plant>.diff`,
  `.run.log`): the mode's shift converted with the transposed frame fails T1 in all 12 judged rows (12 failed
  checks against 2 unplanted); the particle-side lattice on every second ring fails T1 in 10 rows, T3 count in 3, and
  the route check; the candidates' losses compared after a permutation (the best and the worst swapped) fail T2
  (T2 of P 8 in every retention row; the bound fails in one judged row, since the control's T2 is 6 or 7 there).
- *No lattice has been timed:* only the oracle's tables were timed (item 1).
- *Builds:* Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, fast gate 13 of 13, `check_tree.sh`
  passed (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase2/p2_build_debug.log`, `p2_build_release.log`); counts as Phase 1's, `unit_kernels` 3,799 in both (the
  new sub-suite is named-only) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase2/counts_debug/`, `counts_release/`). Decision 20: the identity set equals the
  base's, `e2d65e88...4d33dba5` (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase2/final.log`).

**Frozen in Phase 2:** decision 2's constants in `mlxf_test_defs.f90` (as section 3 states them; the noise levels
0.1 and 0.5, the prior's width half the disc's radius on the screen and none on the window, *guessed*, frozen
before the first run).

**Decisions taken under delegation.**
1. T3's relative difference is |a - b| / max(a, b), 0 when both widths are 0. The first run divided by R's width,
   which is 0 for a pair whose mass sits in one cell, and printed 1e306 on seed 1; the run was stopped and the
   statistic completed before any judged seed ran (the stopped run's log, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase2/decision_run0_t3undefined.log`). Under
   this completion the statistic saturates at 1 on these fixtures; the absolute differences are reported beside it.
2. T2 and T3's count are taken on the retention class (the only one with pools); T1 and T3's relative difference on
   every class, the retention pairs included.
3. Every table by the oracle's ring route (the self-check's "direct vs rings" identity, re-checked on a screen pair)
   rather than per-cell sums, the same route for the three lattices so that near ties are not split by rounding.
4. The noise levels (0.1 and 0.5 of the signal's rms), the screen's prior (width half the disc's radius) and the
   fixtures' point sources, CTF and noise variances are this test's own (*guessed*); the toy has no `projs_ns`, so
   nbest = 4 and nper = nbest as decision 2 says.
5. The suite stays as a named-only sub-suite that fails on its judged rows: it records the verdict. It goes with the
   particle-side lattice in Phase 3 (decision 17).

**What it means, in short.** Judged by SIMPLE's own decisions, the particle-side lattice moves the start of the
refinement about as often as SIMPLE's lattice turned by half a direction step does (98 against 108 pairs over the
judged rows), but more often than that control plus one in two of twelve rows, so it does not pass the frozen test.
The run goes on with the reference-side lattice, whose cells are SIMPLE's. The retention fixture is nearly tied by
construction: even the control changes the kept best of most particles.

### Phase 3, 2026-11-27, 00:20 to 00:55 (the bench size, the ceilings, the graph form's rate)

**Machine and base** as before; no new ruling.

**Files changed:** `src/test/bench/mlxf_bench_polar_table.f90` (`suite=maps`: one map's maps of one part at one
particle tile, its row in `bench_polar_table.tsv` in the time suite's column order, a digest; `form=` and `tail=`
in `suite=shiftmap` and `suite=maps`); and the removal of both lattices (item 5, below): deleted
`src/test/toys/polar/mlxf_toy_polarft_workspace_lattice.f90` and `mlxf_toy_polarft_lattice_tester.f90` (copies kept
in `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/removed/`); edited `mlxf_toy_polarft_workspace.f90`, `_workspace_shiftmap.f90` (back to the base's
operations, with the moved records and reductions and the modes' shifts), `_workspace_mapreduce.f90` (header),
`mlxf_toy_polarft_calc.f90`, `_core.f90`, `_shiftmap.f90` (the form members and the form check go;
`set_shiftmap_form` accepts the Fourier-Bessel form and the graph reductions), `mlxf_toy_polarft_shiftmap_tester.f90`
(restored from HEAD), `mlxf_toy_eul_prob_tab_tester.f90` (the driver's shifts checked on the one form),
`mlxf_toy_seam_tester.f90`, `mlxf_test_defs.f90` (`POLARFT_MAP_FORMS` keeps `bessel`; the lattice tolerances and
decision 2's constants go; `POLAR_MAP_SHIFT_TOL`), `mlxf_test_registry.f90` (rows `polar_lattice` and
`polar_lattice_decision` go), both ledgers, `polar.inf`, `doc/code_base_map.md`, this note (Phase 3 added to the file
table's rows the removal touches, before the edits).

**Exit items.**
- *Item 1, the part mode.* `suite=maps` on the window at tile 16: 7.82e4 maps per second, as the baseline
  (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/maps_try/`). Through `scripts/run_parts.sh` (`RUN_PARTS_SUITE=maps RUN_PARTS_UNIT=maps`): one process
  7.84e4, two processes 4.82e4 and 4.82e4 (sum 9.64e4), every column the launcher reads in place
  (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/parts_check/run_parts.tsv`, `split_1/`, `split_2/`).
- *Item 2, `polar_shiftmap_accuracy` for every form present,* on both devices at the M5's geometries: passed, 144
  checks, largest sampled error 1.9e-7 (lattice_ref, GPU) against the cap 1e-4 (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/accuracy.log`); after the
  removal, the form that stays passes, 48 checks (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/accuracy_final.log`).
- *Item 3, the particle-tile sweep of the candidate* (the reference-side lattice, graph form, best pass of 3,
  *measured*, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/timed/sweep.log`): window 2.77e4, 2.97e4, 3.17e4, 3.19e4 maps per second at tiles 4, 8, 16, 32;
  screen 4.24e3, 4.02e3, 3.71e3, 3.65e3 (MLX peak 1.24e10 B at 4 to 4.80e10 B at 32). Frozen: window 32, screen 4.
- *Decision 10's ceilings, each twice* (null reductions: a scratch copy whose reductions return each pair's first
  cell, still evaluated and copied, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/null/patch_null.py`, `null_reductions.diff`; interleaved with the graph
  form; best pass of 3 per run, the mean of the two runs; `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/timed/ceilings.log`; the first series ran without the
  null binary and is kept as `ceilings_run0_nullpath.log`). The canonical driver is the window and the screen at
  32,000 maps each (*derived* from the rates):

  | construction | reductions | window (tile) | screen (tile) | canonical s |
  | --- | --- | --- | --- | --- |
  | Fourier-Bessel | graph | 7.84e4 (16) | 2.02e4 (4) | 1.991 |
  | Fourier-Bessel | null | 1.021e5 (16) | 2.93e4 (4) | 1.404 |
  | reference-side lattice | graph | 3.17e4 (32) | 4.21e3 (4) | 8.603 |
  | reference-side lattice | null | 3.45e4 (32) | 4.53e3 (4) | 7.992 |
  | particle-side lattice | graph | 1.345e5 (32) | 2.45e4 (16) | 1.544 |
  | particle-side lattice | null | 2.021e5 (32) | 3.76e4 (16) | 1.008 |

  (the particle-side lattice was also run at tiles 16 and 4: window 1.20e5 / 1.86e5, screen 2.32e4 / 3.63e4, graph /
  null). The two runs of each row agree within 1 %. Load: 3.6 at the start of each series (after a wait), rising to
  13 during them (*measured*, every row's load in the logs; the rates repeat within 1 % regardless).
  - **C2 (Fourier-Bessel) = 1.991 / 1.404 = 1.42** (*derived*; predicted 1.43). C2 (reference-side) 1.08, C2
    (particle-side) 1.53.
  - **C1 (reference-side) against the Fourier-Bessel form's ceiling: 1.404 / 7.992 = 0.18;** C1 (particle-side)
    1.404 / 1.008 = **1.39**. The particle-side lattice's graph form alone is 1.29 times the Fourier-Bessel graph on
    the canonical driver (1.72 on the window, 1.21 on the screen).
- *Item 4, the candidate's graph rate against the baseline,* three interleaved pairs per grid through
  `suite=shiftmap` (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/timed/item4.log`, rows in `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/timed/item4/<tag>/`): window 7.82e4, 7.81e4, 7.78e4 (Bessel,
  tile 16) against 3.18e4, 3.17e4, 3.12e4 (reference-side, tile 32), ratio 0.41; screen 2.02e4, 2.01e4, 2.00e4
  against 4.24e3, 4.20e3, 4.21e3, ratio 0.21 (*measured*). Stage profile, microseconds per map (construction,
  selection, reduction): Bessel window 9.37, 1.01, 1.84; reference-side window 28.7, 0.64, 1.82; Bessel screen
  33.1, 4.88, 10.95; reference-side screen 219.3, 4.79, 11.35. Decision 22's bytes: prepared device memory
  9.770e9 B (Bessel) against 7.152e9 / 7.206e9 B (reference-side, window / screen): the lattice holds no reference
  data of its own, 2.6e9 B less, as decision 5 predicted; MLX peak 1.07e10 against 1.25e10 / 1.24e10 B; host 3.93e9
  B both.
- **Decision 1's table, measured column** (the canonical case at the M5's grids): per map the construction takes
  9.4 / 33.1 us (Fourier-Bessel, window / screen), 28.7 / 219 us (reference-side) at one process; the particle-side
  lattice's whole graph map takes 7.4 / 40.8 us (the inverse of its rates).
- *Item 5, decision 10's rules and decision 17.* The reference-side lattice's C1 (0.18) is below 1.30: **removed**.
  The particle-side lattice is not the candidate (it failed decision 2's test in Phase 2): **removed** by decision
  17, after its numbers above, although its C1 (1.39) is above 1.30. **No lattice remains**; Phase 4 works on the
  Fourier-Bessel cells, and **Phase 4 is entered**: C2 of the Fourier-Bessel form is 1.42, at least 1.30.
- *The benchmark and the toy hold the baseline and at most one lattice:* none; `form=` takes `bessel` only, a
  lattice form is refused (`bench_polar_table: form=bessel`, exit 2, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/maps_try/final_refuse.log`).
- *Decision 20:* every digest, map hash and table line of the identity set equals the base's; the set's one other
  line, the assertion count of the `suite=shiftmap` invocation, is 24 against 22 (the benchmark's new check that the
  maps' form is set, once per map) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/identity_compare.txt`; SHA-256 of the Phase 3 set
  `6c718cf1aaf0e33660abc7480232c6fb06bd590423a554c6dfbd871e36ca8147`, the reference from here on).
- *Builds:* Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, fast gate 13 of 13, `check_tree.sh`
  passed (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/p3_build_debug.log`, `p3_build_release.log`). Counts, Debug and Release alike: as Phase 0's base,
  `unit_kernels` **2,015** (1,999 + 16: `eul_prob_tab` 105 to 111, the driver's shifts; `seam` 88 to 98, the host
  refusals and the 100 map cycles; `polar_shiftmap` 794 again) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase3/counts_debug/`, `counts_release/`).

**Ruling R1** (Hans, 2026-11-27, after the fence stopped Phase 3 at its end): the file table's row of
`mlxf_toy_polarft_workspace_mapreduce.f90` omitted Phase 3, whose removal of both lattices reaches the reductions they
fed (Phase 3 edited only that file's header comment). Ruled an omission of the table: the row lists Phases 1, 3, 4 and
6 (edited by the controller); Phase 3's work stands. No source changed between the fence stop and the resumption, so
the builds, gates, counts and identity above are those of the work as it stands (`check_tree.sh` passed again on
resumption). To be recorded in the report.

**Frozen:** the candidate's tiles (window 32, screen 4), now moot; the ceilings above; `unit_kernels` 2,015.

**Decisions taken under delegation.**
1. Both lattices are removed in Phase 3: the reference-side one by decision 10's rule, the particle-side one by
   decision 17 as the non-candidate. The vocabulary `POLARFT_MAP_FORMS` (now `bessel` alone), the `form` dummy of
   `set_shiftmap_form`, `shiftmap_shifts` and the shifts component stay: the `tail` selection serves Phase 4, the
   vocabulary and the `form` dummy go in Phase 6 by decision 8, and the shifts are decision 7's (SIMPLE's
   `shiftmap_shift` at the mode).
2. The shift-map tester is restored from HEAD: everything Phase 1 added to it served the lattices. The driver's
   shift check stays with its tolerance in the test defs (`POLAR_MAP_SHIFT_TOL`, 1e-12 px, host arithmetic on both
   sides).
3. The ceilings are measured through `suite=maps` at one process (its best pass of 3); the null reductions keep the
   construction's evaluation and one copy-out per tile.
4. The particle-side lattice was measured at tiles 16 and 32 (window) and 4 and 16 (screen) for decision 1's table,
   its best tile taken.
5. The identity set's reference becomes Phase 3's file, whose only difference from the base is the benchmark's
   assertion count.

**What it means, in short.** The reference-side lattice, SIMPLE's cells, is four to five times slower than the
Fourier-Bessel form: each pair's copies cost 351 ring transforms on the screen and nothing is shared. The
particle-side lattice is the fast one, 1.29 times the Fourier-Bessel graph and 1.39 times its ceiling, and it would
pass decision 10, but it failed the decision-level test by two counts in two of twelve rows, so it goes. What remains
is the Fourier-Bessel form, whose graph reductions take 29 % of the canonical time: the fused reductions of Phase 4
can win at most 1.42 there.

### Phase 4, 2026-11-27, 00:56 to 01:20 (the fused reductions): stopped for a ruling

**State.** The fused form of decision 9 exists on the Fourier-Bessel cells (no lattice remains): the new device
submodule `src/test/toys/polar/mlxf_toy_polarft_workspace_maptail.f90` (kernel 1 a thread per (rotation, pair), kernel
2 a SIMD group per pair, kernel 3 a thread per (rotation, pair) with compensated sums and `metal::precise::exp`,
kernel 4 a SIMD group per pair with a fixed shuffle tree; the pairs' width cutoffs decided on the device, so the graph
form's host synchronisation per tile goes; the kernels made per map for the block's full tile, the actual count of
pairs in an int32 input), selected by `set_shiftmap_form(form, tail)` with `tail = metal`, refused on the CPU device
(glue `check_shiftmap_tail_mlx` and the workspace's block check). Tests in `polar_shiftmap` (file table rows extended
to Phase 4 first): every test runs again with the fused reductions on the GPU, an exact-tie fixture, the fused form
against the graph, the refusal on the CPU device. Debug (*measured*, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/dbg_try1.log`, `dbg_try2.log`): 1,236 of
1,237 checks pass: every existing cap against the host oracle with the fused reductions, the tie's mode (1, 1, 1) on
both forms, the fused modes equal to the graph's where the oracle's margin exceeds `POLAR_MAP_CAP_LOG` (46 of 46),
the refusal, and the fused results' digest equal across two invocations (`2B4C6BBC43F11EE3`).

**What fails:** decision 12's last row on the judged fixtures. Fused against graph, relative to max(1, |graph|):
9.84e-7 on the calibration fixture (the noise-free analytic one), **2.63e-5** on the judged ones (the perturbed and
the two broadband fixtures), above the ceiling 1e-5 and above any tolerance the calibration gives. Diagnosis
(`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/diag_fused_vs_graph_vs_oracle.log`, patch `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/diag_patch.diff`): the losses are equal bit for bit and the log
evidence differs by at most 4.8e-7; the whole excess is in `sdev` of small widths on the broadband folding grid (sdev
0.036 px: the variances differ by 1.9e-6, which the square root of a cancelling difference of moments turns into
2.6e-5). Against the oracle's double-precision width the fused form is the closer one in 24 of 41 pairs (17 the
graph's); at the worst pair the fused error is 1.8e-5 against the graph's 4.4e-5, and the largest error against the
oracle is 5.8e-5 for both, both within `POLAR_MAP_CAP_VAR` as a variance. No fault of the fused form was found.

**Ruling needed.** Decision 12's row compares `sdev` directly; on small widths that measure is the graph's own float32
error. Recommended: judge the width in this comparison as the existing cap does, the variance's difference relative
to max(1, the largest radius squared) (here at most 3e-8), with the losses and the evidence at the calibrated
tolerance; or judge each form against the oracle under the existing caps alone. Not done before the ruling: the
freeze of `POLAR_MAPTAIL_TOL` (left at the ceiling 1e-5 as a placeholder), the four plants, the sweep of the
threadgroups, of a SIMD group per (rotation, pair) and of the plain sums, the Release build and the identity set.
Decision 13's calibration fixtures of the oracle (size 1, seed 1) lived in the lattice tester that Phase 3 removed;
the calibration here used the analytic noise-free fixture alone.

### Phase 4, resumed 2026-11-27, 01:37 to 02:00 under ruling R2 (the fused reductions)

**Ruling R2** (Hans, "Judge each vs oracle"), recorded under decision 12: each form's width is judged against the
oracle under `POLAR_MAP_CAP_VAR`; the "fused against graph" row keeps the losses (equal) and the evidence at its
calibrated tolerance, its width part reported.

**Files changed in Phase 4:** new `src/test/toys/polar/mlxf_toy_polarft_workspace_maptail.f90`; edited
`mlxf_toy_polarft_workspace.f90` (the map record's four kernels and their tile size, the tile's full count of pairs,
the interface), `_workspace_shiftmap.f90` (the fused form's refusal off the GPU, the tile's count, the kernels
dropped with the map), `_workspace_mapreduce.f90` (the dispatch), `mlxf_toy_polarft_calc.f90` (the glue's interface),
`_shiftmap.f90` (the block's tail; `set_shiftmap_form` accepts `tail = metal` on the GPU), `_shiftmap_mlx.f90` (glue
`check_shiftmap_tail_mlx` and its stub), `mlxf_toy_polarft_shiftmap_tester.f90`, `mlxf_test_defs.f90`
(`polarft_map_block%tail`, `POLARFT_MAPTAIL_TG`, `POLAR_MAPTAIL_TOL`; the tail vocabulary moved above its first use),
`scripts/toy_seam.txt`, `polar.inf`, `doc/code_base_map.md`, this note (rows extended to Phase 4 before the edits).

**Exit items.**
- *The fused form passes decision 12's last row as amended by R2 and every reduction gate on the GPU.* Every test of
  `polar_shiftmap` runs with the fused reductions on the GPU, against the host oracle under the frozen caps (maps,
  modes, losses, widths, evidence, cutoffs, tiles with a partial last tile, re-preparation, lifecycle); new: an
  exact-tie fixture (mode (1, 1, 1) on both forms), seeded fixtures (keyed noise, 0.05 of each ring's rms; seed 1
  calibrates, seeds 2 and 3 are judged) with each form's width and evidence against the oracle (variance error at most
  6.8e-7, evidence 1.7e-6, both caps 1e-4), and the fused form against the graph: the losses equal bit for bit on all
  seven fixtures, the evidence within **`POLAR_MAPTAIL_TOL` = 3.886e-7** (frozen: twice the largest calibration
  difference, 1.943e-7 on seed 1, the noise-free fixture 0, *derived*; ceiling 1e-5), judged 3.256e-7; the modes equal
  in 73 of 73 pairs where the oracle's margin allows (14 inside it); the widths' largest relative difference, reported:
  noise-free 9.8e-7, seed 1 1.3e-6, perturbed 3.0e-7, broadband 2.2e-6, broadband folding grid 2.6e-5, seeds 2 and 3
  6.6e-7 and 6.3e-7 (*measured*; the diagnosis of the stop applies: the graph's own float32 error on small widths).
  Release `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/rel_shiftmap_a.log`, Debug `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/dbg_r2_try1.log`; 1,301 checks.
- *Refused on the CPU device, the graph form taking over:* `set_shiftmap_form(..., metal)` is refused there ("the
  fused map reductions run on the GPU only") and the maps are scored by the graph; the workspace refuses a fused block
  off the GPU as well.
- *Repeatable (decision 14):* a repeated configuration is bit for bit equal in one process (the broadband test, each
  form), and the fused results' digest equals across two invocations (`B6E41467C910D75A`, Release, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/rel_shiftmap_a.log`,
  `_b.log`).
- *The four plants* (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/sweep/patch.py`, `build_variant.sh`, each built apart; `<plant>.diff`, `.check.log`):
  kernel 2's tie to the higher rotation fails "a tie goes to the first cell in SIMPLE's order"; kernel 3 without the
  pairs' cutoff fails "rejected widths are exactly -1"; the fused form asked for on the CPU device fails the refusal and
  the graph's take-over. **The compensation removed does not fail** (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/sweep/plain.check.log`): with plain sums
  every check passes, the evidence against the graph unchanged (3.256e-7 judged) — also at the M5's own sizes, added in
  a scratch copy (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/sweep/prod_case.py`, `prod_base.check.log`, `prod_plain.check.log`: evidence differences 0 and
  8.5e-8 with or without compensation). The sums' errors are below what any gate here resolves: a deviation, recorded.
- *The sweep* (patched copies, Release, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/timed/sweep.log`, two rounds interleaved with the graph reductions and the
  current form; load before 1.5, every row's load in the log): threadgroups of kernels 1 and 3 at 32, 128 and 256 and of
  kernels 2 and 4 at 32 and 128 all within 0.5 % of [64, 64]; plain sums 0 %; a SIMD group per (rotation, pair) for
  kernels 1 and 3: screen +2.7 %, window -1.8 %, canonical +1.6 %. **Frozen:** `POLARFT_MAPTAIL_TG = [64, 64]`, a thread
  per (rotation, pair), compensated sums. The rates (*measured*, mean of the two rounds' best passes): graph reductions
  7.84e4 (window, tile 16) and 2.02e4 (screen, tile 4) maps per second, fused 9.30e4 and 2.51e4; on the canonical driver
  1.992 s against 1.619 s, **1.23** (*derived*; rule T's verdict is Phase 5's). The four launches beat the graph
  reductions, so decision 9's fallback is not taken.
- *Builds:* Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, fast gate 13 of 13 (10.9 s), `check_tree.sh`
  passed (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/p4_build_debug.log`, `p4_build_release.log`). Counts: as Phase 3's, **`unit_kernels` 2,522** in both
  (`polar_shiftmap` 794 to 1,301) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/counts_debug/`, `counts_release/`). Decision 20: the identity set equals Phase
  3's byte for byte (`6c718cf1...8147`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase4/identity/identity.txt`).

**Frozen:** `POLAR_MAPTAIL_TOL` 3.886e-7; `POLARFT_MAPTAIL_TG` [64, 64]; the form (a thread per (rotation, pair),
compensated sums); `unit_kernels` 2,522.

**Decisions taken under delegation.**
1. With no lattice left the fused reductions serve the Fourier-Bessel cells alone, so the int32 table from cell to row
   of decision 9 is not built; the gates live in `polar_shiftmap` (its row extended to Phase 4).
2. The kernels are made per map for the block's full tile, the actual count of pairs reaches them in an int32 input
   (decision 4's rule): a partial last tile needs no second kernel object.
3. The pairs' width cutoffs are decided on the device from kernel 2's loss (the same float32 comparison as the graph
   form's host comparison), which removes the graph form's synchronisation per tile.
4. Decision 13's seeded calibration (seed 1) and judged seeds (2, 3) are keyed-noise versions of the perturbed analytic
   fixture: the oracle fixtures of decision 13 lived in the lattice tester Phase 3 removed.
5. The plant "kernel 3 without the cut" removes the pairs' width cutoff: dropping the -40 log-weight cut changes the sums
   by about e^-40, which no gate can see.
6. A variant replaces the frozen form only above the 5 % that decision 9 sets for the plain sums; none reached it.

**What it means, in short.** The fused reductions are correct (every oracle gate, the graph's losses bit for bit, its
modes, its evidence to 3.3e-7) and repeatable, and they take the canonical driver from 1.99 s to 1.62 s, 1.23 times,
against a ceiling of 1.42: probably not the 1.30 rule T asks, which Phase 5 measures at one, three and six processes.
Compensated sums buy nothing measurable at these sizes, and cost nothing either.

### Phase 5, 2026-11-27, 01:58 to 03:47 (the verdict at one, three and six processes)

**Machine and base** as before; no new ruling. **Files changed:** this note only (no source changed; the Release and
Debug trees of Phase 4's end, built from scratch, hold the current sources: no file under `src/`, `test/` or
`scripts/` is newer than that build).

**Frozen before the first verdict row:** the Fourier-Bessel construction (the only one); the graph reductions and the
fused reductions of Phase 4 (threadgroups [64, 64], a thread per (rotation, pair) for kernels 1 and 3, compensated
sums); particle tiles 16 (window) and 4 (screen) for both forms; `suite=maps` through `scripts/run_parts.sh`
(`RUN_PARTS_SUITE=maps RUN_PARTS_UNIT=maps RUN_PARTS_LOAD=4`), `passes=9`, Release, `MLX_ENABLE_TF32=0`; five pairs
per split, graph then fused, each form on the window and then the screen (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/verdict.sh`); the analysis
`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/analyse.py`: at one process the canonical time from the best passes (32,000 maps per grid), at more the sum of the
two grids' times from go to the last exit, a pair valid only when every run's parts exit within one median pass.

**Splits.** `2500_4` at one and three processes; six processes on `2500_4` were not run by the launcher's guard
(predicted summed footprint 1.355e11 B against 0.8 of the machine's memory, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/run_parts_2500_4.tsv`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/s6.log`),
so six processes ran on `2500_1` (the grid file with `nrefs = 2500`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/shiftmap_grid_2500_1.txt`, Phase 0's
decision) with its own one-process row. Every split ran or is recorded as not run. Load at the series' start 1.5, the
launcher waiting for at most 4 before each launch (every row's load in the series tables).

| Split | Canonical s, graph | Canonical s, fused | Ratio (median of pairs) | Valid pairs |
| --- | --- | --- | --- | --- |
| 1 process, 2500_4 (best passes) | 1.991 | 1.617 | **1.232** | 5 of 5 |
| 3 processes, 2500_4 (go to last exit) | 16.86 | 13.69 | **1.232** | 5 of 5 |
| 1 process, 2500_1 (best passes) | 1.993 | 1.645 | 1.212 | 5 of 5 |
| 6 processes, 2500_1 (go to last exit) | 16.65 | 13.29 | **1.253** | 4 of 5 (pair 1's graph window exited 0.35 s apart, above its median pass 0.31 s) |

(*measured*; `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/analysis_2500_4.txt`, `analysis_2500_1.txt`; the runs in `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/runs/`.) Per form and grid (median
of the five runs; total rate, rate per process, largest process footprint, summed footprint, largest MLX peak):

| Split | Form | Window maps/s | Screen maps/s | Footprint largest / summed B | MLX peak B |
| --- | --- | --- | --- | --- | --- |
| 1, 2500_4 | graph | 7.84e4 | 2.02e4 | 2.11e10 / 2.11e10 | 1.07e10 |
| 1, 2500_4 | fused | 9.31e4 | 2.51e4 | 2.10e10 / 2.10e10 | 1.07e10 |
| 3, 2500_4 | graph | 1.08e5 (3.59e4 each) | 2.49e4 (8.29e3 each) | 2.23e10 / 6.59e10 | 1.07e10 |
| 3, 2500_4 | fused | 1.25e5 (4.17e4 each) | 3.15e4 (1.05e4 each) | 2.20e10 / 6.50e10 | 1.06e10 |
| 1, 2500_1 | graph | 7.83e4 | 2.02e4 | 7.16e9 / 7.16e9 | 3.41e9 |
| 1, 2500_1 | fused | 9.23e4 | 2.47e4 | 7.03e9 / 7.03e9 | 3.39e9 |
| 6, 2500_1 | graph | 1.18e5 (1.97e4 each) | 2.49e4 (4.15e3 each) | 7.83e9 / 4.61e10 | 3.30e9 |
| 6, 2500_1 | fused | 1.29e5 (2.16e4 each) | 3.22e4 (5.37e3 each) | 7.39e9 / 4.37e10 | 3.28e9 |

SIMPLE's rates beside them, from the grid file (commit `0a8b0903e`, labelled context, not measured here): 1.09e5
(window) and 2.05e4 (screen) maps per second on 30 threads.

**Rule T** (the reductions, on the Fourier-Bessel construction): the median ratio at one process is 1.232, below 1.30;
no judged split is below 1.00 (1.212 to 1.253). **The fused reductions are not kept**; decision 16's mixed outcome
does not arise. **Rule C**: no lattice remains (Phase 3), so the Fourier-Bessel form stays; nothing to judge.

**Reported with the verdict:** the roadmap's reopening conditions: the total rate at three or six processes below 0.8
of one process's: not met (at three processes 1.38 and 1.23 times one process's on the window and the screen for the
graph, 1.34 and 1.25 for the fused; at six on `2500_1` 1.51 and 1.23, 1.40 and 1.31); the summed footprint above 5.15e10
B: **met at three processes on 2500_4** (6.59e10 B graph, 6.50e10 B fused), not at six on `2500_1` (4.61e10 B). The
rate measures agree in direction (best pass at one process, go to last exit at more).

**Exit items.** Both rules' outcomes are above with their rows and load records; every split was run or recorded as not
run; the two invocations' digests agree per form (every form's digests equal across all five pairs of every split,
`analyse.py`'s "digests equal"); the two Phase 5 plants fail: a key the suite does not read stops the benchmark
(`bt=64`: "suite=maps does not read bt=64", exit 2, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/plants/plant_unread_key.log`), and a row whose parts exit apart
is rejected by the validity test (a split-3 run with its exit spread set to 5 s: the pair "NOT VALID",
`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/plants/plant_spread.log`). Decision 20: the identity set equals Phase 3's byte for byte (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase5/identity/`);
`check_tree.sh` passed.

**Decisions taken under delegation.**
1. "Two invocations each" is met by the five pairs: each form ran five times per split, and their digests are compared.
2. Six processes on `2500_1` as decided in Phase 0 (a grid file with `nrefs = 2500`, nothing else changed).
3. The launcher's load threshold is 4 (`RUN_PARTS_LOAD=4`), the run's protocol, not its default 2.
4. No build in this phase: the sources are those of Phase 4's from-scratch builds.

**What it means, in short.** The fused map reductions make the maps 1.23 times faster on the canonical driver, alone
and with three or six processes sharing the GPU, which is short of the 1.30 a second path needs: Phase 6 removes them
and the Fourier-Bessel form with its compiled graph reductions stays. Three processes on the large case already pass
the roadmap's memory line (6.6e10 B summed).

### Phase 6, 2026-11-27, 03:47 to 04:00 (the survivor and the record)

**Machine and base** as before; no new ruling (standing 19, R1, R2).

**Files changed:** deleted `src/test/toys/polar/mlxf_toy_polarft_workspace_maptail.f90` (copy in `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/removed/`);
edited `mlxf_toy_polarft_workspace.f90`, `_workspace_shiftmap.f90`, `_workspace_mapreduce.f90` (the fused reductions'
members, dispatch and refusal removed), `mlxf_toy_polarft_calc.f90`, `_core.f90`, `_shiftmap.f90`,
`_shiftmap_mlx.f90` (back to HEAD: the selector `set_shiftmap_form` and its glue removed),
`mlxf_toy_polarft_shiftmap_tester.f90` (HEAD's tests and the exact-tie and seeded-width tests),
`mlxf_toy_seam_tester.f90`, `mlxf_test_defs.f90` (`POLARFT_MAP_FORMS`, `polarft_map_block%tail`, the fused form's
constants removed), `mlxf_bench_polar_table.f90` (`form=` and `tail=` removed), both ledgers, `polar.inf` (HEAD's),
`doc/code_base_map.md`, `planned/mlxf_kernel_families.md`, `planned/mlxf_roadmap.md`,
`doc/policies/test_environment_policy.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md`,
`README.md`, this note; new `completed/mlxf_kernel_k4_report.md`.

**Exit items.**
- *Decision 17: one construction of the maps, the default.* Rule C removed the lattices (Phase 3) and rule T the fused
  reductions (Phase 5): the Fourier-Bessel form with its compiled graph reductions is the only construction and
  reduction form; the selector, the vocabulary `POLARFT_MAP_FORMS`, the block's `tail`, the fused form's constants,
  the benchmark's `form=` and `tail=` and their ledger lines are deleted, "dead" proved by the clean builds below. The
  Fourier-Bessel form's own pieces (`shiftmap_order`, `shiftmap_term_counts`, `test_folding`) stay: decision 17
  deletes them only when the lattice is kept.
- *Decision 18:* its condition (a lattice kept that reads the tiles) does not hold: the device route's refusal of the
  maps stays as it is; no gate or plant applies.
- *The survivor passes every map gate as the default on both devices:* `polar_shiftmap` 834 checks (the base's 794,
  the exact tie, the seeded widths and evidence against the oracle on seeds 1 to 3), `polar_shiftmap_accuracy` as
  before, `eul_prob_tab` 111 (the driver's shifts), `seam` 96 (the 100 map cycles, the shifts' host refusal), the
  off-state check (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/counts_release/unit_kernels.log`, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/dbg_kernels.log`).
- *The counts, frozen:* every area as the base's (`unit_core` 215 in both builds this time, within its known 214 to
  216); **`unit_kernels` 2,053** (`polarft_calc` 333, `polar_shiftmap` 834, `eul_prob_tab` 111, `polarft_tail` 55,
  `oracle_projection` 44, `oracle_polar` 46, `projector` 100, `projector_chain` 91, `pcg_solver` 86,
  `reconstructor_pcg` 192, `seam` 96, `polarft_host` 65) (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/counts_debug/`, `counts_release/`).
- *Decision 20 on what remains:* the Fourier-Bessel form stays, so no line is retired; the 364-line identity set
  equals the base's byte for byte, `e2d65e88...4d33dba5` (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/identity/identity.txt`).
- *Documents:* the families note (A3's outcome, the seam facts with the measured bytes, the modes' shifts, row K4),
  the roadmap (decision 13's ruling and outcome, section 5, rank 2's row), the test policy (the shift-map suite's new
  tests, `oracle_polar`, `suite=maps`, check 13's sentence corrected: an unread key stops the benchmark), the plans'
  index, the history (2026-11-27), the README (the maps' status).
- *The last-phase gates:* Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, fast gate 13 of 13
  (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/p6_build_debug.log`, `p6_build_release.log`); `scripts/check_tree.sh` passed; `scripts/check_embed.sh` passed
  (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/gate_embed.log`); `scripts/check_toy_offstate.sh --exec` passed, the host route's table equal to the
  executable's (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/gate_offstate.log`); `scripts/check_install.sh` passed on Release with `--require-gpu` and on
  Debug (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/gate_install_release.log`, `gate_install_debug.log`); `scripts/release_gate.sh --allow-dirty` passed
  (`90f5932-dirty`, Debug and Release, 91 s, `/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/gate_release.log`); the Release fast gate 10 times of 10, 10.5 to
  11.2 s each (`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/phase6/fast_gate_1.log` to `_10.log`).
- *The report:* `completed/mlxf_kernel_k4_report.md`, with the commit message (no attribution line).
- *`git status`* shows the file table's paths only (and the report).

**Decisions taken under delegation.**
1. `set_shiftmap_form` goes with the losers (decision 8): with one construction and one reduction form nothing is
   left to select, and its `tail` was the fused form's.
2. The exact-tie and seeded-width tests stay in `polar_shiftmap`: they judge the survivor against the oracle (R2's
   seeds) and cost 40 checks.
3. `suite=maps` stays without `form=` and `tail=`: it is decision 15's instrument for the maps at several processes.
4. The reductions' submodule `_workspace_mapreduce` stays: the split keeps `_workspace_shiftmap.f90` under 700 lines
   (decision 23); whether to merge it back is left open.
5. The release gate's work directory `build_release_gate/` in the checkout (ignored by git) was deleted after the run.

**What it means, in short.** The maps are as they were before the run, the Fourier-Bessel form with compiled
reductions, identity bit for bit; what the run adds is the oracles' asserted self-checks, the modes' shifts SIMPLE's
callers need, a part-mode benchmark of the maps and two more map tests, and the measured answer that neither shift
lattice nor fused reductions earns its place at the M5's grids.
