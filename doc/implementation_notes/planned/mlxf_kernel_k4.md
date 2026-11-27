# K4: the shift lattice and the map reductions (A3) of the toy polar calculator (run `mlxf_kernel_k4`, on the M5 Ultra)

Status, 2026-11-26: planned; ruled as recommended by Hans, 2026-11-26 ("Rule as recommended"), every decision of section 3 and the run order K4, K3, K5, K6, K7; revised after ranks 2d to 2f (runs `mlxf_refactor`, `mlxf_toy_layout`,
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

None is ruled. Each is dated 2026-11-26 and carries its recommendation; the maintainer's choices are collected
at the end of the section.

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
| `src/test/toys/polar/mlxf_toy_polarft_lattice_tester.f90` (new) | sub-suites `polar_lattice` and `polar_lattice_decision` | 1, 2, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace.f90` | the map record's members, the interfaces of the new module procedures | 1, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_shiftmap.f90` | the form's branch; the reductions fed by either construction; decision 17's deletion | 1, 4, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_calc.f90` | the additions' interfaces, the form's members | 1, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap.f90` | `set_shiftmap_form`, `shiftmap_shifts`; decision 18's refusal | 1, 6 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap_mlx.f90` | the glue's bodies and stubs of the same | 1, 4, 6 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab.f90` | `batch_map_results` with the shifts | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap_tester.f90` | the tests per form, the private oracle's frame; `test_folding` with decision 17 | 1, 3, 6 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab_tester.f90` | the driver's map results per form | 1, 6 |
| `src/test/toys/mlxf_toy_seam_tester.f90` | the cycles and refusals of decision 19 | 1, 6 |
| `src/test/toys/polar/mlxf_toy_*.f90` (new, decision 23) | submodules of a toy file that passes 700 lines | 1, 4, 6 |
| `src/test/framework/mlxf_test_defs.f90` | `POLARFT_MAP_FORMS`, the record's component, decision 12's tolerances, decision 2's constants | 0, 1, 2, 4, 6 |
| `src/test/framework/mlxf_test_registry.f90` | rows `oracle_polar`, `polar_lattice`, `polar_lattice_decision`; one `NAMED_ONLY` name | 0, 1, 2 |
| `src/test/bench/mlxf_bench_polar_table.f90` | `suite=maps`; `form=` and `tail=`; the rows; decision 17's columns | 3, 4, 5, 6 |
| `src/test/toys/polar/polar.inf` | the folder's description: the lattice and the fused reductions | 1, 4, 6 |
| `src/test/oracles/oracles.inf` | the folder's description: the oracles' tester | 0 |
| `doc/code_base_map.md` | regenerated by `scripts/generate_codeoverview.py` in each phase that adds or deletes a Fortran file or edits an `.inf` (the static gate checks it) | 0, 1, 2, 3, 4, 6 |
| `test/offstate/mlxf_offstate_exec.f90` | one check: the maps refuse the host backend | 1 |
| `scripts/toy_mirror.txt` | the additions' lines; the declared difference of `ialpha`; decision 17's lines | 1, 6 |
| `scripts/toy_seam.txt` | the two device submodules | 1, 4, 6 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | sections 3 and 8, the seam facts | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | decision 13's ruling and outcome; section 5 | 6 |
| `doc/policies/test_environment_policy.md` | the suites, the benchmark, the unread-key sentence | 6 |
| `doc/implementation_notes/README.md` | the index | 6 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 6 |
| `README.md` | the status, where it names the maps | 6 |
| `doc/collaboration/apple_questions.md` | if a question arises (decision 24) | 0, 3, 4, 5 |
| `doc/implementation_notes/planned/mlxf_kernel_k4.md` | this note: Progress, decision 23's rows | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/completed/mlxf_kernel_k4_report.md` (new) | the report | 6 |

`mlxf_test_defs.f90`, `mlxf_test_registry.f90`, the folders' `.inf` files, `doc/code_base_map.md`, both
ledgers, `test/offstate/`, the families note, the polar toy's files and `mlxf_bench_polar_table.f90` are shared
with the other kernel runs of this batch: this run starts from a commit that holds every earlier run's result
and rank 2g's.

## Progress

(one entry per phase, written by the run: date and times, machine, base, files changed, each exit item and how
it was shown, the frozen numbers with their origin, the plants and the checks that failed on them, the load
records, the decisions taken under delegation with their reasons, and every log's path)
