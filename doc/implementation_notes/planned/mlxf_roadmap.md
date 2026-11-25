# mlx-fortran roadmap: what comes first, and which plan owns it

Status, 2026-11-24: ruled. Hans ruled decisions 1 to 10 on 2026-11-24, decision 6 as amended (the PCG solve
is in; gridding insertion is an easy win), and added decision 11 the same day (toys mirror SIMPLE's
architecture; rank 0b). Rank 0 is carried out in the same change. An advisory review of the same day
([`mlxf_roadmap_review.md`](mlxf_roadmap_review.md)) is taken up in decisions 12 to 15. Hans approved
decision 12 that day; decisions 13 to 15 await ruling. Written at `3a13403`,
with SIMPLE read at `d354efee2`. This is not an implementation plan: it ranks the work, names the
plan that owns each item, and lists the rulings each one needs. An item becomes work only through its own
plan, written to `doc/how2s/how2write_agent_plans.md`.

## 1. Where we stand

- **The library.**
  - The generated layer binds all of mlx-c 0.8.0: 680 prototypes.
  - The Fortran layer offers 126 public names (*exact*, the public block of `src/core/mlxf.f90`).
  - The parity ledger (`scripts/mlxc_parity.txt`) counts 125 mlx-c functions public, 46 plumbing, 146
    internal, 89 excluded and **274 pending** (*exact*).
  - Pending by parity phase: 111 in Phase 2, 35 in Phase 3, 40 in Phase 4, 29 in Phase 5, 16 in Phase 6,
    9 in Phase 7 and 34 in Phase 8.
- **Milestone 1 is delivered and closed** (`completed/mlxf_milestone1_report.md`, run `mlxf_m1_m5`).
  On the M5 Ultra, against SIMPLE `0a8b0903e` on 30 threads (*measured*):
  - dense polar scoring runs at 4.69 times SIMPLE's rate;
  - the Fourier-Bessel shift maps, built from graph operations, run at 0.971 (screen) and 0.683 (window);
  - none of the graph alternatives for the maps earned its place;
  - the accelerated mode (TF32, NAX) fails the accuracy bounds and gains 0.3 to 3.5 %.
- **How those numbers are to be read.** SIMPLE never runs as one 30-thread process against the GPU. It runs
  as several part processes at once (`nparts` × `nthr`: 3 × 10 or 6 × 5 on 30 cores), and every part would
  use the GPU at the same time. The ratios above compare standalone rates: the GPU alone against 30 threads
  alone. They bound what the GPU could add to busy cores; they do not measure it. Two measured facts point
  at the gap: under a concurrent 30-thread memory-streaming load the GPU path slowed by 18 %, and one
  benchmark process had a footprint of 21 to 23 GB, which six parts would multiply.
- **SIMPLE's bottlenecks** (Hans, 2026-11-24):
  1. the probabilistic search;
  2. reconstruction.

  Further:
  - the reprojection model is a good GPU target;
  - continuous refinement is dominated by reprojection on the fly;
  - the insertion of `rec_backend=gridding` is an easy win, since SIMPLE already holds GPU code that
    demonstrates its acceleration;
  - the PCG solve is made for a GPU, and if it runs fast enough SIMPLE might use it all the time;
  - the nonuniform filter and the volume assembly are not bottlenecks.
- **The design that follows from it: four GPU kernel families.** They are polar matching, the gather from
  the 3D Fourier volume, the scatter into it, and the PCG solve.
  [`mlxf_kernel_families.md`](mlxf_kernel_families.md) is their design note.

## 2. Rules the ranking follows

1. **The library comes first.** A toy kernel is written against the public `mlxf` module, as a user writes.
   A kernel that needs a missing wrapper waits for the wrapper; no kernel gets a private binding.
2. **Toys before SIMPLE.** mlx-fortran holds only toy examples for development: test-only code in
   `src/test/`. No SIMPLE source changes until a family's toy has passed its correctness gates and its
   performance contract on the M5.
   - **A toy looks like SIMPLE** (decision 11; `doc/policies/toy_example_policy.md`): SIMPLE's classes,
     method names, data conventions and layering, so that integration can be designed on it.
   - The library is the opposite: no SIMPLE type, constant or naming enters it.
3. **Judge the GPU as SIMPLE runs.** Each toy is timed alone and as 3 and 6 simultaneous processes. Results
   are reported as capacity added, never as GPU against all cores.
4. **No new measurement of SIMPLE without a gap.** SIMPLE's costs come from the maintainer's benchmark
   records of the latest code. A new workload, when one is needed, is simulated by SIMPLE's own programs.
5. **One item at a time per set of files.** The maintainer reviews and commits between items.

## 3. The ranking

| Rank | Item | Owning plan | Depends on | Done when |
| --- | --- | --- | --- | --- |
| 0 | **Close milestone 1's hold** (done in the working tree, 2026-11-24; awaits the maintainer's commit) | [`mlxf_milestone1.md`](../completed/mlxf_milestone1.md), section 9, and its report, section 6 | decision 2 | both plans in `completed/`; the failed experiments gone; the benchmark's arguments fixed; `README.md` status current; gates pass |
| 0b | **Refactor milestone 1's toy to SIMPLE's architecture**, with the dense-driver baseline before and after (see below) (delivered in the working tree, 2026-11-24, by run `mlxf_toy_arch`: [report](../completed/mlxf_toy_architecture_report.md); awaits the maintainer's read) | [`mlxf_toy_architecture.md`](mlxf_toy_architecture.md) | rank 0 committed; decisions 11 and 12 | the polar toy is a miniature `polarft_calc` with its driver; the mirror ledger and rule `mirror` exist; the kernel suites keep their counts; both builds are free of warnings |
| 1a | **Parity Phases 2 and 3**, then the API hold (delivered 2026-11-24 by run `mlxf_parity`; the hold released by Hans the same day) | [`mlxf_mlxc_parity.md`](mlxf_mlxc_parity.md) | rank 0 (its base), decision 4 | no `pending 2` or `pending 3` line; the maintainer has read the API |
| 1b | **The wrappers the kernels need, ahead of their turn** (see below) | the parity plan, its decisions 27 and 28 (Phase 10; run `mlxf_parity_wrappers`; the hold is released, so it starts when rank 0b's result lands) | rank 1a, decision 5 | the named ledger lines are public and their area tests pass on both devices |
| 1c | **Housekeeping** (see below) | this note, then the notes it names | rank 0 | each sub-item closed or handed to a plan |
| 2 | **The toy kernels**, deliverables K1 to K8 | [`mlxf_kernel_families.md`](mlxf_kernel_families.md), then one plan per deliverable or family: [K1](mlxf_kernel_k1.md), [K2](mlxf_kernel_k2.md) and [K8](mlxf_kernel_k8.md) are planned (2026-11-25) and await their rulings | each deliverable's own wrappers (design note, section 8), not the whole of rank 1b; decisions 6 to 9 | each deliverable's exit in the design note |
| 3 | **The rest of parity** (the rest of Phase 4, the random half of Phase 5, Phase 6, the other `fast` functions, Phases 8 and 9) | the parity plan | rank 1b; runs beside rank 2 on a disjoint file table | no `pending` line; the parity report |
| 4 | **SIMPLE's integration** | a SIMPLE plan, written by SIMPLE's rules | rank 2 for the family concerned | not started here |

**Rank 0b: the refactoring.** Milestone 1's kernels model a GPU workspace beside SIMPLE's calculator, under
their own names. The refactoring turns them into a miniature of SIMPLE's `polarft_calc`, with a driver that
stands for the table fill:

| Today (`polar_table`) | SIMPLE's counterpart | After |
| --- | --- | --- |
| type `polar_table` | type `polarft_calc` | toy type `polarft_calc`, its MLX state in one workspace component |
| `new`, `invalidate`, `kill` | `new`, `kill`; the memo generations | `new`, `kill`; invalidation inside the memoisation |
| reference tiles prepared from `polar_table_refs` | `set_ref_pft`, `memoize_refs` | the same two names |
| particle blocks (`polar_table_block`) | `set_ptcl_pft`, `memoize_ptcls`, `pinds` | the same names |
| `score`, or `submit` and `collect` | `score_block_posterior` | `score_block_posterior`; submission and collection as recorded additions |
| `prepare_maps` | `setup_shiftmaps` | `setup_shiftmaps` |
| `score_maps` | `gen_shiftmap` then `shiftmap_mode`, per pair | the same names, in a batched form recorded as a difference |
| the loops in the tester and the benchmark | `eul_prob_tab%fill_tab_range` | a toy `eul_prob_tab` with `fill_tab_range` |

It touches `src/test/` only, so it can run beside parity (rank 1a) on a disjoint file table. It comes before
K1, because every family-A deliverable builds on this code. Each later toy is written under the policy from
the start.

**The dense-driver baseline** (decision 12, from the review). The refactoring is bracketed by one
measurement with the scorer already in hand: a fixed total workload, split among one, three and six
simultaneous processes, timed until the last one finishes. It answers what no kernel timing can: how parts
share the GPU and the memory. It also checks the refactoring for what the suites cannot see, an extra host
wait or a second resident copy.

**Rank 1b: the wrappers the kernels need.**
- **The custom Metal kernel:** `mlx_metal_kernel_spec` and `type(mlx_metal_kernel)` with `apply` (the kernel
  half of parity Phase 7, 2 pending lines plus their internal helpers). Every fused kernel of the
  families needs it, so it is the single most valuable wrapper.
- **The n-dimensional FFTs:** `mlx_rfftn`, `mlx_irfftn`, `mlx_fftn`, `mlx_rfft2`, `mlx_irfft2` (the FFT half
  of parity Phase 5). They serve the volume transforms of the gather and scatter toys, and they are all the
  PCG solve needs.
- **The gathered and masked matrix products:** `mlx_gather_mm`, `mlx_block_masked_mm`, `mlx_segmented_mm`
  (from parity Phase 4). They serve polar matching over arbitrary reference sets.

Phases 2 and 3 already deliver the rest: `mlx_argpartition`, `mlx_topk`, `mlx_argsort`, the scans, `mlx_take`
without a dimension, `mlx_gather` and the `mlx_scatter` family.

**Rank 1c: housekeeping.**
- **The run machine.** The M5 Ultra is the development machine and runs parity from here on (decision 4
  below; the parity plan's decision 26). Done with the rulings.
- **The preparation follow-up** ([`mlxf_m5_preparation.md`](mlxf_m5_preparation.md)). Its launch audit is
  delivered. Its Phase 5, the combined validation after parity Phase 3, closes with rank 1a.
- **The record's wording.** The milestone report and the fusing note judged the maps as GPU against 30
  cores. Decision 3 restates them as capacity. Done with the rulings.
- **The Apple questions** (`doc/collaboration/apple_questions.md`: 20 entries, all open, none sent). The M5
  run answers part of questions 9 to 11. The kernel families add at least two: how several processes share
  one GPU, and how custom kernels handle threadgroup memory and atomics.
- **`CLAUDE.md`'s "Where the decisions are"** gains a line for this note (done with the rulings).

## 4. Decisions and rulings

1. (2026-11-24, Hans: "the ranking looks good to me") **The ranking of section 3 and the rules of section 2.**
2. (2026-11-24, Hans: "do it, yes to all four") **Milestone 1's hold**, as one interactive change before
   anything else.
   - Move `mlxf_milestone1.md` and `mlxf_m1_m5.md` to `completed/` and rewrite the links to them (the
     parity plan cites milestone 1).
   - Update the status line of the root `README.md`, which still says "milestone 1, early".
   - Remove the failed experiments from the test code. The report's section 6 names the files:
     - formulation C;
     - the real-weights contraction and the Hermitian direction transform of the maps;
     - the candidate-tile, order-tile and compact-radius options.
   - Fix the benchmark:
     - `suite=shiftmap` reads `nthr` or rejects it;
     - it prints `mlx_cache_memory` beside the peak;
     - `arg_int` initialises its status.
   - Done on 2026-11-24 (history entry of that day). Left open: a key that a suite does not read is still
     ignored, so a removed key such as `contraction=2` runs the control without a word. The refactoring of
     rank 0b rewrites the benchmark's driver and takes a per-suite key check with it.
3. (2026-11-24, Hans: yes) **Restate the M5 verdicts as capacity.** One paragraph in the milestone report and in the fusing note:
   the ratios are what the GPU adds to the cores, and SIMPLE runs as several parts sharing it.
   The measured numbers do not change. Wording refined after the review: the ratios compare standalone
   rates, which bound what the GPU could add to busy cores and do not measure it.
4. (2026-11-24, Hans: "nothing exists that need to be brought over. This is the machine we are working on
   now") **Parity continues on the M5 Ultra.** This replaces the M2 Ultra in the parity plan's decision 4
   (its decision 26). No output of parity Phases 2 or 3 exists elsewhere.
5. (2026-11-24, Hans: yes) **Parity's order after the Phase 3 hold.**
   - Order: the custom Metal kernel first; then the n-dimensional FFTs; then `gather_mm`, `block_masked_mm`
     and `segmented_mm`; then everything else, in the plan's order.
   - The ledger rule already allows this: a phase's lines may become public before the phase closes, and
     the count of pending lines only shrinks.
   - It is the parity plan's decision 27.
6. (2026-11-24, Hans: yes, amended) **Milestone 2 is the kernel families.**
   [`mlxf_scientific_examples.md`](mlxf_scientific_examples.md) is re-scoped by
   [`mlxf_kernel_families.md`](mlxf_kernel_families.md):
   - example 1 (polar matching and shift maps) grows into family A;
   - example 3 (Fourier projection and its adjoint) becomes families B and C, with its fixtures and oracle
     design kept;
   - example 2 splits: its PCG solve becomes family D, with its fixture and oracle design kept; its filter
     bank is deferred without a date, since the nonuniform filter is not a bottleneck;
   - the tutorials follow the kernels they describe.

   The amendments, in Hans's words:
   - "we should not forget about rec_backend=gridding, we already have GPU code in the library demonstrating
     acceleration of this step, so it would be an easy win" (family C);
   - "The PCG solve should definitely go on the GPU. It is made for it. If it can be made to run very fast,
     we might just use it all the time" (family D).
7. (2026-11-24, Hans: accept) **The order of the toy deliverables** K1 to K7 (design note, section 8). K8,
   the PCG solve, entered with decision 6's amendment; its slot is the design note's proposal and is open
   to a veto.
   - (2026-11-25, Hans: "Go", on the recommendation) **The first three run K1, K8, K2**, one at a time on the
     M5 Ultra: K8 is independent of the polar toy's files, and K2 shares nine files with K1. The plans are
     [`mlxf_kernel_k1.md`](mlxf_kernel_k1.md), [`mlxf_kernel_k8.md`](mlxf_kernel_k8.md) and
     [`mlxf_kernel_k2.md`](mlxf_kernel_k2.md).
8. (2026-11-24, Hans: yes) **What a toy must agree with:**
   - an independent host oracle in double precision, within tolerances frozen before the judged run;
   - repeatability on one GPU configuration, as a separate gate;
   - SIMPLE's CPU code is a comparator only through SIMPLE's own matched benchmarks.
9. (2026-11-24, Hans: yes) **The performance contract of a toy:**
   - timed alone, and as 3 and 6 simultaneous processes;
   - the resident memory of one process reported, since it multiplies by `nparts`;
   - a second code path kept only above a measured 30 % gain (the standing rule);
   - a graph form always kept as the reference beside a fused kernel.
10. (2026-11-24, Hans: yes) **Where planning lives.** This note is the entry point for priorities. Each ranked item keeps its own
    plan. `doc/implementation_notes/README.md` stays the index of notes.

11. (2026-11-24, Hans: "make the toy code that is supposed to emulate SIMPLE look a whole lot more like it
    looks in SIMPLE so that we can begin to think about how this would be integrated on an architectural
    level as well. We should fit that refactoring into the plan and make it a policy for any new toy examples
    that come in") **Toys mirror SIMPLE's architecture.**
    - The policy is `doc/policies/toy_example_policy.md`.
    - The refactoring of milestone 1's toy is rank 0b, with its own plan.
    - (2026-11-24, Hans: "Accept all three") The policy's section 7 stands: the module prefix `mlxf_toy_`,
      the arity exemption for mirrored procedures, and a driver per strategy under the strategy's name.

12. (2026-11-24, from the review; Hans: "Approve") **The dense-driver baseline in rank 0b.**
    - **Workload:** the M5 run's case `2500_4` (2,000 particles against 10,000 references, both halves), with
      the driver's host preparation and collection, at the canonical tile plan and full precision.
    - **Splits:** the particles divided among 1, 3 and 6 simultaneous processes. Each process holds all the
      references, as a SIMPLE part does.
    - **Recorded:** the time until the last process finishes; pairs per second in total and per process;
      each process's footprint and MLX peak; the machine's peak memory use. Run twice, before and after the
      refactoring.
    - **The refactoring's bound:** at no split may the refactored driver be slower than the original by more
      than twice the spread of the two before-runs (*measured* when taken), and its footprint may not grow.
    - **What reopens the question of one GPU-owning process,** fixed before the first run:
      - the total rate at 3 or 6 processes falls below 0.8 of one process's rate (*guessed*);
      - or the processes' summed footprint exceeds half the machine's memory (*guessed*: 51.5 GB of 103 GB).
    - Results are toy throughput, not SIMPLE speedup.
13. (2026-11-24, proposed from the review; awaits ruling) **What K4's maps must agree with, decided before any
    timing.**
    - The reference-side variant is judged cell by cell against the Fourier-Bessel oracle, in any case.
    - The particle-side variant changes which cells exist, so a correct calculation can still change which
      candidates survive screening. It is admitted only with a decision-level test frozen before timing:
      the mode's displacement and the retention of candidates, on representative and near-tie fixtures,
      against a stated bound.
    - To rule: are SIMPLE's exact cells required (then the reference-side variant is the kernel), or is
      decision-level agreement accepted?
14. (2026-11-24, proposed from the review; stands as recommended since the maintainer's go of that day, open to
    the review) **K6's repeatability, and an early probe.**
    - Bitwise repeatability on one GPU configuration is a gate for the form that is kept (the family rule).
      Reproducing the CPU's summation order is a separate property and is not required unless ruled.
    - Right after K2, one protected update is tried on a collision-heavy fixture: numerator, density,
      repeatability and peak scratch memory. SIMPLE's offload insertion shows the opportunity; its
      shared-voxel updates are unprotected, so it does not show the speed of a correct scatter. The probe
      tests the premise of an easy win without moving K6 forward.
    - Recommended: yes.
15. (2026-11-24, proposed from the review; ruled 2026-11-25 with the K1 plan, Hans: "Go") **The 30 % rule's
    denominator.** K1's check found that the arithmetic below takes the barriered stages as additive; the
    driver's pass without barriers takes 1.13 s, so K1 judges on that pass's median and measures the ceiling
    first (its decisions 15, 18 and 19). A second code path
    is kept on the canonical driver's elapsed time at equal work and accuracy, with submission,
    synchronisation and collection included. A stage's own timing explains the result; it does not decide.
    - For K1: the tail took 0.90 of 1.93 s with a barrier after each stage. Taking those as additive, the
      tail must run about twice as fast for the whole score to gain 30 % (*derived*: 1.93 / (1.03 + 0.90/x)
      = 1.3 at x ≈ 2.0).
    - Recommended: yes.

## 5. Not planned

- Any change to SIMPLE before rank 4.
- The nonuniform filter and the volume assembly on the GPU.
- More graph-level work on the Fourier-Bessel maps. Family A replaces their formulation.
- The accelerated mode (TF32, NAX).
- New profiling runs of SIMPLE.
- A single process that owns the GPU and serves every part. It is decided only after the toys' multi-process
  timings show how well parts share the GPU.
- CUDA, Linux and other compilers (the parity plan's section 4 stands).

## 6. Keeping this note current

When an item closes, its row gains the commit and the report's path, and the next row's "depends on" is
checked. A ruling is written into its decision here and applied in the plan it names in the same change. A
new item enters only with a rank and an owning plan.
