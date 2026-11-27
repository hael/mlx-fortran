# Run `mlxf_kernel_k3`: arbitrary reference sets for polar matching (A2), report

Run of [the K3 plan](../planned/mlxf_kernel_k3.md) on the M5 Ultra, in the session, 2026-11-27, in the working
tree at base `07b86bc` (nothing committed). The plan's Progress section holds every number with its origin and log;
this report is the summary to read in one sitting. Each phase's diff is in the run's review directory
(`~/agent_runs/mlxf_kernel_k3/review/phase_N.diff`), the cumulative diff in `full_after_N.diff`.

## What was built and what it gave

- **The list route of the calculator.** `score_block_posterior` takes any list of references on both backends;
  `set_block_refs` gives the list of a queued block. On the MLX backend one `mlx_gather` over the resident tiles
  (read as a view, never copied) writes list tiles in the resident layout, which the dense route's tile graph
  scores unchanged; every reference in order stays the dense route, so the dense digests cannot move.
- **The driver `eul_prob_tab_neigh`** (extends `eul_prob_tab`, as SIMPLE's does): SIMPLE's `geom` cones and its
  `state` fill (the shared representatives, the peaks and pools on the host by SIMPLE's rule, then the pooled cells'
  members), SIMPLE's block order or the batch's, the covers `route`, `dense` (decision 9's baseline: each half
  against every reference, then the selection) and `pairs`; with `srchspace_map` and `cone_view_dist`.
- **The oracle of the lists** `mlxf_oracle_neigh` (double precision, no shared code) with its self-checks.
- **Suite `neigh`** of `bench_polar_table` (`lists=route|dense|pairs`, `check=1` on the accuracy block).
- **The pair-list kernel** (decision 10's candidate B): a SIMD group per (pair, bin) reads each listed pair's two
  packed columns from the resident tiles; the inverse transform and either tail follow on the listed rows only.
  Built for the cones only (`set_block_pairs`, cover `pairs`, GPU only).

**Verdicts** (decision 18's protocol, seed 2, `2500_4`, bt 64, rt 64, fused tail; *measured*):

| Configuration | Route vs dense fill with selection | Pair-list kernel vs route | Occupancy of the route |
| --- | --- | --- | --- |
| `geom`, 10 degrees, SIMPLE's order | **2.49** (0.267 against 0.667 s) | **3.65** (0.073 against 0.266 s) | 5.3 % |
| `state` fill | **1.84** (0.368 against 0.676 s) | not built (its product alone 0.87 s) | 69 % |

Every judged pair was above 1.30, every control within 0.01. The list route is kept for both configurations, the
pair-list kernel for the cones. The masked tail (candidate A) was not built: its ceilings were 1.15 and 1.21.

## Phase by phase

- **Phase 0** (`phase_0.diff`): the base measured. Builds without warnings; the unit counts (they replaced decision
  21's); the 364-line identity set and decision 20's digests twice, byte for byte `ae7d623`'s; the dense pass at bt 16
  and 64 by rt 64 and 250, both tails. The queue's premises held; the differences (seam ledger 27 entries,
  `SUITE_KEYS` 7 rows, `BENCHES` 7, Apple questions up to 38) were each named by K4, rank 2g or rank 2h.
- **Phase 1** (`phase_1.diff`, this note only): the four layouts probed at `2500_4`'s geometry. The gathered union
  (L2) won decision 3's rule under both tails; one generic `mlx_gather_mm` (L3) was within 10 % and lost to L2; the
  sorted single-column route (L4) runs and equals `matmul` but reaches 0.40 times L2 per listed pair. A reference at
  two positions of one tile shape changes no bits; on the GPU bits move with the tile's width and the particles'
  grouping. Frozen: 7(b) exact on the host and the CPU device, 7(c) the tail's tolerance on the GPU.
- **Phase 2** (`phase_2.diff`): the list route; the new sub-suite `eul_prob_tab_neigh` (calculator part).
  `POLAR_NEIGH_ERR_CPU` frozen on seed 1, seeds 2 and 3 judged; listed entries equal the dense ones bit for bit on
  the host and the CPU device and within the tail's tolerance on the GPU (identical when the block holds the same
  particles); decision 16; refusals; three plants.
- **Phase 3** (`phase_3.diff`): the driver, the oracle, the helpers, the seam and off-state checks. The lists,
  columns, pools, members and padded covers equal the oracle's exactly on seeds 1 to 3, both devices, both tails
  and the host backend; 1,000 seam cycles; the off-state program writes the neighbourhood tables and
  `check_toy_offstate.sh --exec` compares 402 lines; 13 plants.
- **Phase 4** (`phase_4.diff`): suite `neigh`, the accuracy block (`POLAR_NEIGH_BLOCK_*` frozen on seed 1), the
  canonical shapes (bt 64, rt 64, fused tail), the two verdicts, decision 6's table (64 rows), decision 19's splits.
  The fence stopped the phase at its end on `scripts/toy_mirror.txt`; **ruling R1** (the row lists Phase 4, an
  omission of the table) let it stand.
- **Phase 5** (`phase_5.diff`): the two ceilings, the probe of candidate B, the kernel built for the cones, its gates
  (`POLAR_NEIGH_PAIR_ROW_TOL` frozen on seed 1, seeds 2 and 3 judged), three plants, its verdict and splits.
- **Phase 6**: the documents (families note, roadmap, lessons note, toy and test policies, binding contract, Apple
  question 39, history, index, README), the last-phase gates, this report.

## Evidence against the baseline

- **The dense route did not move:** the 364-line identity set, which holds decision 20's digests, is byte for byte
  the base's (`e2d65e88...4d33dba5`) at the end of every phase, Phase 6 included.
- **Counts:** every unit area keeps the base's count (core 214 to 216, its known range); `unit_kernels` grew from
  2,053 to 4,070: `eul_prob_tab_neigh` 1,990, `oracle_neigh` 7, `seam` 96 to 116; the other sub-suites unchanged.
  `polarft_calc` kept 333 (two assertions now assert the new contract, below).
- **Gates:** Debug and Release from scratch with `MLXF_WERROR` and 0 warnings at the end of every phase;
  `check_tree`; the embed, off-state, install and release gates and the Release fast gate 10 times (Phase 6's
  Progress).
- **Repeatability:** every timed configuration gives one digest over invocations, host teams and repeats.

## Decisions taken under delegation

Each is recorded in the Progress subsection of its phase.

- Phase 0: Phase 0's counts replace decision 21's; no CUDA source is written (the standing ruling and the roadmap
  ask for the report's section below, the Linux report's "both sources" is not a ruling).
- Phase 1: the direct gather form (same time, half the peak); 7(c) stays a tolerance (identity fails for what the
  route does); the predictions' pools a random model.
- Phase 2: the list form of `submit` is the dense `submit` with its tiles chosen; the identity list is the dense
  route; list tiles at the plan's rt; 7(a)'s oracle `polar_memo_rows` on memos made from the fixture; the fixture's
  spiral and hashed orientations; the two `polarft_calc` assertions of the removed refusal now assert that such
  blocks are scored (file added to the table); `mlxf_toy_polarft_core.f90` added to the table.
- Phase 3: `eul_prob_tab`'s components public for its extension; `get_tile_plan`; the record `polar_list_entries`;
  the previous direction the nearest one, the cone with its edge; 7(a) through the driver at the drawn rotation;
  the fused tail's fills not compared with the compiled dense table; the off-state tables chosen.
- Phase 4: the dense baseline as the driver's dense cover at the dense route's canonical shape; the faster tail
  canonical; drawn rotations counted in the accuracy check; key `seed=`; three `geom` processes on `2500_1` (the
  guard); the host loops on the team (the first sweep kept).
- Phase 5: candidate B's ceiling by a shared list of each mode's mean size; decision 10 applied per mode (the kernel
  serves the cones); the capacity grown before the pass, no pass redone; two waits a pass (one per parity); no seed
  banks or rows in the kernel; `passes=125` for its verdict.

## Deviations from the plan

- **The run order** was K4 before K3 (roadmap decision 18); the queue section's re-check covered it.
- **Files added to the file table** before they were edited: `mlxf_toy_polarft_core.f90` and
  `mlxf_toy_polarft_calc_tester.f90` (Phase 2); calculator and core for Phase 3; the neigh tester and the fixture
  for Phase 4; eight files for Phase 5's kernel. The mirror ledger's Phase 4 by ruling R1.
- **The existing `polarft_calc` tester** asserted the refusal the plan removes; its two assertions now assert the
  new contract (count unchanged). The plan's search had looked for the message only.
- **Decision 19:** three `geom` processes of `2500_4` were refused by the memory guard (35.7e9 B a process) as six
  were; both ran on `2500_1`.
- **The accuracy block's rotation count** counts drawn rotations, not minimising ones (the driver keeps no rows).
- **Section 6's hypotheses that failed:** the factor above 5 (2.49 and 1.84); three and six processes sharing the
  GPU without loss (the route's splits lose; the kernel's splits gain on `2500_1`).

## After the run

- Owner ruling after the run (2026-11-27, Hans: "Bits where measured"): decision 7(b)'s bit identity on the CPU
  device holds on Apple's CPU (Accelerate), where Phase 1 measured it, and not on Linux, where MLX's CPU products go
  through OpenBLAS, which blocks by shape: on dell2's CPU-only build 96 of the neighbourhood sub-suite's checks failed
  (entries and rows of list tiles against dense tiles, the dense cover's digest), while every oracle gate (7(a))
  passed. The CPU device is now judged bit for bit where the test executable is built on Apple (`MLXF_ACCELERATE_CPU`
  in `test/CMakeLists.txt`, read by `cpu_matmul_shape_exact` in `mlxf_test_utils`) and by 7(c)'s frozen tail
  tolerances elsewhere, with the differing entries counted; no new number. Checked by the controller: on the M5
  `unit_kernels` 4,070 in Debug and Release (the bit checks active); on dell2's CPU-only Linux build Debug and
  Release with zero warnings and the fast gate 13 of 13.
- Fixed after an independent review (2026-11-27, the controller): with the pair-list cover a half whose columns list
  no pair (a cone of 0 degrees, or a small cone no previous orientation of that half meets) was pushed as a job, and
  `set_block_pairs` refused the whole fill ("a pair at least"); the route and dense covers skip such a block. A half
  is now a job only when it lists a pair, and a test (geom, cone 0, pairs, on the GPU, both tails, seeds 1 to 3)
  holds it: it fails 6 times on the old code and passes on the fix, with the fast gate 13 of 13.

## For a CUDA twin

One kernel was kept, the pair-list kernel (`mlxf_toy_polarft_workspace_lists.f90`, `PAIR_SRC`, `pair_spec`).
Its Metal-specific features and their CUDA counterparts:

- `thread_index_in_simdgroup` and a 32-wide SIMD group per (pair, bin): a warp (`threadIdx.x % 32`; the width 32
  is the same, so the arithmetic carries).
- `simd_sum`: `__reduce_add_sync` is integer-only, so a `__shfl_down_sync` tree or `cg::reduce(tile, x,
  cg::plus<float>())`.
- `init_value = 0` on the output (the padding past the pairs): MLX's CUDA kernel spec has the same field; else a
  zero fill before the launch.
- No threadgroup memory, no atomics. The grid guard `if (g >= np * n1) return` already holds a rounded-up CUDA
  grid. The fused tail it calls is K1's, whose twin rank 5 already owes.

## Left open for the maintainer

- Whether the miniature reads like SIMPLE's neighbourhood fill (declared differences: decision 11, and the covers
  by blocks where SIMPLE scores per pair).
- What the occupancies mean for a GPU route of `refine=*neigh*`: at the 10-degree cone the GPU's list route stays
  below 30 threads' dense block rate (5.7e5 listed pairs per second) and the pair-list kernel reaches about 2.1e6;
  the `state` fill runs at 7.1e6 to 7.5e6 listed pairs per second, about twice 30 threads' dense block rate.
- Whether to keep the pair-list kernel beside the list route: it is the faster form for sparse lists, and a CUDA
  twin would be owed for it.
- K7's tail forms must also serve list tiles: the one place the tail is applied to them is the dense
  `polarft_workspace_submit`'s tile loop (the list tiles take the dense graph); the pair-list kernel calls the
  tail on (1, capacity) rows in `polarft_workspace_submit_pairs`.

## Proposals for the skills and the register (not applied)

- `mlxf-modern-fortran`: an extension in another module needs its parent's components public; state it beside
  the visibility rule for test code.
- `mlxf-agent-runs`: `rsync -a` keeps the source's times, so a scratch copy rebuilt incrementally can keep a
  previous plant's object: touch the planted files.
- A plan's file table should name every file the change's ledgers require in the same change (rule `mirror`):
  ruling R1's omission.

## Commit message

```
K3: arbitrary reference sets for polar matching (run mlxf_kernel_k3)

The polar toy scores any list of references on both backends: on the MLX
backend the listed references are gathered from the resident tiles into list
tiles of the dense graph. The driver eul_prob_tab_neigh fills SIMPLE's geom
cones and its two-stage state fill, held exactly to a new oracle of the lists.
On 2500_4 the list route is 2.49 times faster than the dense fill with
selection at the 10-degree cone and 1.84 times for the state fill; a pair-list
kernel is 3.65 times faster than the route at the cone. The masked tail was
not built. The dense route's identity set is unchanged.

New files:
  src/test/toys/polar/mlxf_toy_polarft_workspace_lists.f90
  src/test/toys/polar/mlxf_toy_eul_prob_tab_neigh.f90
  src/test/toys/polar/mlxf_toy_eul_prob_tab_neigh_tester.f90
  src/test/toys/polar/mlxf_toy_eul_prob_tab_utils.f90
  src/test/toys/polar/mlxf_toy_srchspace_map.f90
  src/test/oracles/mlxf_oracle_neigh.f90
  src/test/oracles/mlxf_oracle_neigh_tester.f90
  doc/implementation_notes/completed/mlxf_kernel_k3_report.md
```
