# K4, the shift lattice and the map reductions: the report of run `mlxf_kernel_k4`

Run `mlxf_kernel_k4`, 2026-11-26 to 2026-11-27, unattended on the M5 Ultra (macOS, GPU `applegpu_g17d`, GNU Fortran
16.2.0, MLX 0.32.4, mlx-c 0.8.0), base `90f5932f10197247baf001a1087682fc34bd353d` (rank 2g committed), everything in
the working tree. The plan is [`planned/mlxf_kernel_k4.md`](../planned/mlxf_kernel_k4.md); its Progress section
holds every phase's numbers and evidence paths (the evidence lives under
`/Users/hael/agent_runs/mlxf_kernel_k4/scratch/keep/`). Rulings applied: the plan's decisions as recommended
(roadmap decision 18, which rules decision 1 B), the standing ruling of roadmap decision 19 (MLX-centric), R1 (the
file table's row of the reductions' submodule lists Phase 3) and R2 ("Judge each vs oracle", decision 12 amended).

## What was learned

- **Neither shift lattice replaces the Fourier-Bessel maps.** Both were built as graphs on the dense score's
  resident tiles and reproduce the oracle's cells to float32 rounding (6.4e-7). The **reference-side** lattice
  (SIMPLE's cells) reaches 0.18 of the Fourier-Bessel form's ceiling: 351 ring transforms per pair on the screen grid,
  nothing shared at the benchmark's candidates (construction 219 us per screen map against 33 us). The
  **particle-side** lattice is the fast one: 1.29 times the Fourier-Bessel graph on the canonical driver (1.72 on the
  window, 1.21 on the screen) and 1.39 times its ceiling, and it holds no reference data (7.15e9 B against 9.77e9 B
  prepared). It **failed the decision-level test** frozen before timing: its start shifts differ from SIMPLE's by
  more than one map step more often than a control lattice turned by half a direction step, by more than the
  allowed one pair, in 2 of 12 judged rows (4 against 2, 29 against 23), although summed over the judged rows it moved
  fewer (98 against 108).
- **Fused map reductions are correct but not worth a second path.** Four Metal kernels (a thread per (rotation,
  pair), a SIMD group per pair, compensated sums, cutoffs decided on the device) reproduce the graph's losses bit for
  bit, its modes and its evidence to 3.3e-7, and run the canonical driver 1.23 times faster at one, three and six
  processes, against a ceiling of 1.42 and the 1.30 rule T asks.
- **The width compared between two float32 forms measures the graph's own error** on small widths (the stop of
  Phase 4, answered by R2): against the oracle the fused width was the closer one.
- **Compensated sums buy nothing measurable at these sizes,** and cost nothing: plain sums gave the same results to
  every gate's resolution, also at the M5's own sizes.
- **Memory:** three processes on case `2500_4` hold 6.6e10 B summed, above the roadmap's 5.15e10 B line; six
  processes on `2500_4` are refused by the launcher's guard.

## What changed, phase by phase

| Phase | Diff | What |
| --- | --- | --- |
| 0 | `/Users/hael/agent_runs/mlxf_kernel_k4/review/phase_0.diff` | The base measured (counts, the identity set twice, the baseline 7.83e4 / 1.99e4 maps/s), the queue and checks 1 to 15 re-read, the probes; new tester `mlxf_oracle_polar_tester.f90` (sub-suite `oracle_polar`, 46 checks) |
| 1 | `review/phase_1.diff` | Both lattices as graphs (submodule `_workspace_lattice`), the reductions split into `_workspace_mapreduce` (decision 23), `set_shiftmap_form`, `shiftmap_shifts`, sub-suite `polar_lattice`, `polar_shiftmap` per form, the seam's cycles and refusals, the off-state check; decision 12's tolerances frozen |
| 2 | `review/phase_2.diff` | The decision-level test `polar_lattice_decision` (host, double precision): the particle-side lattice fails 2 of 12 judged rows |
| 3 | `review/phase_3.diff` | `bench_polar_table suite=maps` (the part mode in the launcher's layout); the ceilings; both lattices removed (decisions 10 and 17); ruling R1 |
| 4 | `review/phase_4.diff` | The fused map reductions (`_workspace_maptail`) and their gates; stopped once on decision 12's width, resumed under ruling R2; the sweep |
| 5 | `review/phase_5.diff` | The verdict at one, three and six processes (measurement only): the fused reductions not kept |
| 6 | `review/phase_6.diff` (the driver writes it) | The fused reductions, their selector `set_shiftmap_form` and the benchmark's `form=` and `tail=` deleted; the families note, the roadmap, the test policy, the index, the history, the README; the last-phase gates; this report |

What remains of the run in the tree: the oracles' self-checks asserted (`oracle_polar`); the modes' shifts in the
reference's axes (`shiftmap_shifts`, `polar_map_results%shifts`, carried by `batch_map_results`); the maps'
reductions in their own submodule; `suite=maps`; an exact-tie test and a seeded width test of the maps; the
host-backend refusal of the maps in the off-state program; 100 map cycles in `seam`.

## Decisions taken under delegation

Each is recorded with its reason in the plan's Progress entry of its phase.

- **Phase 0:** the base measured from a pristine copy (an edit during the first Release build broke it); the identity
  set by the earlier runs' tool; the baseline at `ptiles=4,16`; `2500_1` with a grid file of `nrefs = 2500`; the plant
  on the check with the largest error.
- **Phase 1:** the reductions moved to `_workspace_mapreduce` (decision 23), the tile's maps a component of the tile
  record (rule `arity`); `mlxf_toy_polarft_calc.f90` not split (the parent of the interfaces, 724 lines at the base);
  no new glue procedure; the fused tail refused until Phase 4; a map refused without current tiles; decision 12's
  measures on the oracle's fixtures, tolerance twice the calibration, the shift's floor 1e-12; the particle-side
  known-pose check on the poses that are lattice cells (2 of 3); plant 3 without an exact tie; the shifts in real64;
  the fixtures' keyed noise; a Release-only diagnostic avoided by a fixed-size record.
- **Phase 2:** T3's relative difference completed as |a - b| / max(a, b) after seed 1 showed a division by a zero
  width; T2 and T3's count on the retention class; every table by the oracle's ring route; the noise levels, prior and
  fixtures (*guessed*, frozen before the first run); the failing suite kept until Phase 3.
- **Phase 3:** both lattices removed in Phase 3, the vocabulary and the selector kept to Phase 6; the shift-map tester
  restored from HEAD; the ceilings through `suite=maps`; the particle-side lattice measured at two tiles per grid; the
  identity reference moved to Phase 3's file (a benchmark assertion count).
- **Phase 4:** no cell-to-row table (no lattice); kernels per map for the block's full tile with the count in an int32
  input; cutoffs on the device; seeded analytic fixtures for decision 13's seeds; "kernel 3 without the cut" as the
  pairs' cutoff; a variant replaces the frozen form only above 5 %.
- **Phase 5:** "two invocations each" met by five pairs; six processes on `2500_1`; the launcher's load threshold 4.
- **Phase 6:** `set_shiftmap_form` deleted with the losers (nothing left to select); the exact-tie and seeded-width
  tests kept for the survivor; `suite=maps` kept without `form=` and `tail=`; the reductions' submodule kept.

## Deviations from the plan, and why

- **Rulings R1 and R2.** R1: the fence stopped Phase 3's end on `_workspace_mapreduce.f90`, whose row omitted Phase 3.
  R2: decision 12's last row compared the width of two float32 forms; the run stopped, and the width is now judged per
  form against the oracle.
- **File table.** Rows were extended before their edits: `mlxf_toy_polarft_core.f90` (Phase 1); Phase 3 on ten rows
  for the removal; Phase 4 on the calculator's parent, its shift-map submodule and the shift-map tester.
- **The lattices' removal in Phase 3** reached files the table gave to later phases (the parent, the testers, the
  defs, the ledgers); recorded there.
- **Decision 13's oracle calibration fixtures** lived in the lattice tester that Phase 3 removed; Phase 4 used keyed
  noise on the analytic fixture for the seeds.
- **The plant "compensation removed" does not fail** (Phase 4): plain and compensated sums agree to every gate's
  resolution, also at the M5's sizes.
- **Decision 18** did not apply (no lattice kept): the device route's refusal of the maps stays.
- **Decision 2's T3 relative difference** saturates at 1 on its fixtures; the absolute differences are reported.

## Evidence against the baseline

- **Builds and gates** at every phase's end: Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, the fast
  gate 13 of 13, `check_tree.sh`. Phase 6 adds `check_embed.sh`, `check_toy_offstate.sh --exec`, `check_install.sh`,
  `release_gate.sh --allow-dirty` and the Release fast gate 10 times (Progress, Phase 6).
- **Counts:** every area as the base's; `unit_kernels` 1,953 at the base, 2,053 at the end (`oracle_polar` 46,
  `polar_shiftmap` 794 to 834, `eul_prob_tab` 105 to 111, `seam` 88 to 96).
- **The identity set** (decision 20, 364 lines: the dense table on both devices and tails, the device route, the
  Fourier-Bessel maps on both grids, the off-state table) equals the base byte for byte at the end (SHA-256
  `e2d65e88...4d33dba5`); in Phases 3 to 5 only a benchmark assertion count differed.
- **The baseline and the verdict** (one process, canonical driver, 32,000 maps per grid): Fourier-Bessel graph 1.99 s
  (7.84e4 / 2.02e4 maps/s, the Phase 0 baseline 7.83e4 / 1.99e4); fused reductions 1.62 s; the reference-side lattice
  8.60 s; the particle-side lattice 1.54 s (graph reductions). SIMPLE's rates (grid file, commit `0a8b0903e`, context):
  1.09e5 and 2.05e4 maps/s on 30 threads.
- **Plants:** Phase 0 1 of 1, Phase 1 10 of 10, Phase 2 3 of 3, Phase 4 3 of 4 (above), Phase 5 2 of 2 fail their gates.

## For a CUDA twin

No custom kernel of this run is kept, so nothing new needs a CUDA counterpart. The removed fused reductions used
SIMD-group functions (`simd_max`, `simd_min`, `simd_shuffle_down`; CUDA: `__reduce_max_sync`-style warp reductions
or `__shfl_down_sync` trees over 32 lanes), no `threadgroup` memory and no atomics; their source, launch specs and
graph form were kept together in one submodule, as the standing ruling asks. The lattices were pure MLX graphs
(`mlx_fft`, `mlx_ifft`, `mlx_irfft`, `matmul`, `mlx_take`).

## Open for the maintainer

- **The particle-side lattice's test.** It is the faster construction (1.29 times on the graph, 1.39 the ceiling),
  failed by two counts in two of twelve rows, while summed over the judged rows it moved fewer start shifts than the
  control. Whether decision 2's per-row bound (the control plus one pair) is what decision-level agreement should mean
  is the maintainer's; the code is in `scratch/keep/phase3/removed/` and in `review/phase_1.diff`.
- **Whether the reductions' submodule stays split** (it holds the graph reductions alone now).
- **Memory at three processes** above the roadmap's line (6.6e10 B).
- **Proposals for the skills and `CLAUDE.md`** (not edited): the testing reference could say that a comparison of two
  float32 forms of a cancelling quantity (a width from moments) is judged per form against the oracle; the
  `mlxf-agent-runs` skill could say that a benchmark's timed child processes must not overlap with any other
  `mlxf_test_exec` (the launcher discards such rows), and that a statistic with a ratio must define its value at a zero
  denominator before it is frozen.

## Commit message

```
K4: shift lattice and fused map reductions measured, not kept (run mlxf_kernel_k4)

Both shift lattices of family A3 were built on the dense score's resident tiles and
reproduce the shift-map oracle's cells to float32 rounding. The reference-side
lattice reaches 0.18 of the Fourier-Bessel form's ceiling; the particle-side one
(1.29 times the Fourier-Bessel graph) failed the decision-level test frozen before
timing. Fused map reductions (four Metal kernels) gave 1.23, below the 1.30 a
second path needs. The Fourier-Bessel maps with the compiled graph reductions stay.

Kept: the host oracles' self-checks asserted (sub-suite oracle_polar), the modes'
shifts in the reference's axes (polarft_calc%shiftmap_shifts,
polar_map_results%shifts), the maps' reductions in their own submodule,
bench_polar_table suite=maps (one part of one map in the launcher's layout), an
exact-tie and a seeded-width test of the maps, the host-backend refusal of the maps
in the off-state program, 100 map cycles in sub-suite seam. Rulings R1 and R2.

New files:
  src/test/oracles/mlxf_oracle_polar_tester.f90
  src/test/toys/polar/mlxf_toy_polarft_workspace_mapreduce.f90
  doc/implementation_notes/completed/mlxf_kernel_k4_report.md
```
