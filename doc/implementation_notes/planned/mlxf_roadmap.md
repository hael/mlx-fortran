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
  - The generated layer covers the 680 names of mlx-c 0.8.0's headers: 673 interfaces and 7 names skipped with
    a reason (*exact*, `build/gen/mlxc_coverage.txt` and the generator's count). Name coverage, not ABI
    verification.
  - The Fortran layer offers 315 public names (*exact*, the public block of `src/core/mlxf.f90`, 2026-11-26).
  - The parity ledger (`scripts/mlxc_parity.txt`) counts 399 mlx-c functions public, 90 plumbing, 101
    internal, 90 excluded and **none pending** (*exact*, 2026-11-26, after run `mlxf_parity_rest`; it stood at
    125 public and 274 pending when this roadmap was written).
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
| 2 | **The toy kernels**, deliverables K1 to K8 | [`mlxf_kernel_families.md`](mlxf_kernel_families.md), then one plan per deliverable or family: [K1](mlxf_kernel_k1.md), [K2](mlxf_kernel_k2.md) and [K8](mlxf_kernel_k8.md) are planned and ruled (2026-11-25); K1 is delivered and kept ([report](../completed/mlxf_kernel_k1_report.md)); K2 is delivered, its fused gather and device route kept ([report](../completed/mlxf_kernel_k2_report.md)); K8 is delivered in its graph form under rulings R1 and R2 ([report](../completed/mlxf_kernel_k8_report.md)); K4 is delivered with nothing kept ([report](../completed/mlxf_kernel_k4_report.md)); [K3](mlxf_kernel_k3.md) is delivered (2026-11-27), its list route kept for cones and the `state` fill and its pair-list kernel kept for cones ([report](../completed/mlxf_kernel_k3_report.md)); [K5](mlxf_kernel_k5.md), [K6](mlxf_kernel_k6.md) and [K7](mlxf_kernel_k7.md) (and [K4](mlxf_kernel_k4.md)) are drafted (2026-11-26), revised the same day after ranks 2d to 2f (paths, counts, SIMPLE's memo layout at `28c753993`, the kernel forms measured by run `mlxf_kernel_forms`), ruled as recommended by Hans the same day with the run order K4, K3, K5, K6, K7 (decision 18), and wait behind rank 2g (decisions 16 and 17) | each deliverable's own wrappers (design note, section 8), not the whole of rank 1b; decisions 6 to 9 | each deliverable's exit in the design note |
| 2b | **Release hardening** (from the outside review of `c6ea867`; Hans, 2026-11-25: "Yes, plan it"): the installed package as the artifact under test, the mlx-c version in the package config, a CPU-only device mode, feedback on pull requests, a dtype table and quickstart, a contributor's path, ABI checks of representative signatures | [`mlxf_release_hardening.md`](../completed/mlxf_release_hardening.md); delivered 2026-11-25 by run `mlxf_release_hardening` ([report](../completed/mlxf_release_hardening_report.md)): the release gate passes in `--allow-dirty` mode on the M5 and in release mode on the M2 Ultra (2026-11-27); closed. When to tag a release is the maintainer's decision, outside the plans (Hans, 2026-11-27) | the review's five release fixes verified (2026-11-25); after K2 on the M5 | the plan's release criterion: from a clean committed tree an outside program installs, links and passes the installed-consumer test on an Apple-silicon GPU, with the documented dtype and failure behaviour |
| 2c | **The follow-up review's four fixes, then the toys take the shape of SIMPLE's integration** (the fixes: Codex's review of `0071f5a`, findings F1 to F4, as the run's Phase 1; the shape: Hans, 2026-11-25: "implement the toy examples in mlx-fortran in the same way so that we can model safely over here and make the integration easier downstream"): host files free of MLX, glue submodules beside them under `USE_MLX` with stubs, device modules behind one opaque component, a build without the library, the polar fill's two branches (delivered in the working tree, 2026-11-26, by run `mlxf_toy_seam`: [report](../completed/mlxf_toy_seam_report.md); its Phase 6 stop was ruled in the session under the maintainer's go, rulings R1 to R6, open to his review; awaits his read) | [`mlxf_toy_seam.md`](mlxf_toy_seam.md) | rank 2b committed (shared files); K1, K2 and K8 delivered | the review's four regression tests pass and the Release fast gate passes 20 times of 20; rule `seam` passes with no `pending` line; the device route byte for byte unchanged; the off-state project builds and runs without the library |
| 2d | **Refactoring of the library and of the test tree** (Hans, 2026-11-26, decision 16): `mlxf_array` and `mlxf_ops` split by concern and made readable; every `.inf` with its `!@descr:`; the code-base map generated as in SIMPLE and XEMA; `src/test/` in subfolders; what `mlxf_linalg` offers against BLAS stated, with a decision on a BLAS-shaped layer | [`mlxf_refactor.md`](mlxf_refactor.md) (run `mlxf_refactor`); delivered in the working tree on the M5 Ultra, 2026-11-26, [report](../completed/mlxf_refactor_report.md); awaits the maintainer's read | the two delivered runs committed | its plan's exit; no public name of `mlxf` changes unless the plan's API read says so |
| 2e | **The polar toys catch up with SIMPLE's memo layout** (Hans, 2026-11-26, decision 16): SIMPLE's `23eb95cc2` (2026-11-25) replaced `ft_ref`, `ft_ref2` and `ft_ref_bins` by `ft_ref_terms (2nk, pftsz+1, nrefs, half)` and added the particle terms; the toys mirror the layout of `d354efee2` | [`mlxf_toy_layout.md`](mlxf_toy_layout.md) (run `mlxf_toy_layout`); delivered in the working tree on the M5 Ultra, 2026-11-26, [report](../completed/mlxf_toy_layout_report.md): one reference memo `ft_ref_terms` and the particle terms in SIMPLE's layout, tiles made by `memoize_refs`, ledger pinned at `28c753993`; every digest bit for bit; the dense times 4 to 10 % shorter; awaits the maintainer's read | rank 2d (the test tree's folders) | the toys, their oracles' fixtures and the benches read the new layout; the mirror ledger's pin moves; the dense baselines measured again |
| 2f | **Review against mlx3D, with experiments on the ways of writing a kernel** (Hans, 2026-11-26, decision 16): [`mlxf_mlx3d_lessons.md`](mlxf_mlx3d_lessons.md) is the starting note; mlx3D is in `~/src/mlx3D` at `7101ec3` | [`mlxf_kernel_forms.md`](mlxf_kernel_forms.md) (run `mlxf_kernel_forms`); delivered in the working tree on the M5 Ultra, 2026-11-26, [report](../completed/mlxf_kernel_forms_report.md): the named-only bench `bench_kernel_forms` (seven suites); a SIMD group per pair makes K1's tail kernel 3.3 times faster, a threadgroup tree makes K5's reduction 8 times faster than one thread per evaluation, a SIMD group per particle makes K7's selection 2 to 4 times faster than the graph, sizes as an int32 input cost nothing per launch and 3 ms instead of 42 ms per new value, one wait per pass beats one per tile 2.4 times, and the pulled insertion is exact but 6 to 15 times slower than the atomic push at small n; no toy default changed; awaits the maintainer's read | rank 2e for the polar kernels | each kernel form in use here set beside mlx3D's form of the same pattern and measured; the drafts of K3 to K7 revised by what was found |
| 2g | **User-facing hardening from Claude's and Codex's prospective-user reviews**: integer statistics, failed-save preservation, explicit index/lifetime safeguards, numerical boundaries and user guidance | [`mlxf_user_hardening.md`](mlxf_user_hardening.md), C1–C14; local hardening delivered on the M5, second-architecture validation closed on the M2 on 2026-11-27 ([report](../completed/mlxf_user_hardening_report.md)); benchmark correctness follow-up validated. C7 remains deferred. RB1 (empty host-array constructors) closed and RB2 (a tagged gate) withdrawn on 2026-11-27 | rank 2f (one run at a time on the M5; 2d→2e→2f keep decision 16's order); decision 17. Rank 4 waits for its Phases 0 to 2 | the plan's local P1 actions and release gates pass; deferred API changes and open upstream issues remain explicit |
| 2h | **Linux, CPU only, on dell2** (Hans, 2026-11-26, decision 19): MLX and mlx-c built on Linux, the library and its suite on the CPU device, the install checks, a Linux CI job, and the inventory of Apple assumptions the CUDA step meets (delivered in the working tree on dell2, 2026-11-26, by run `mlxf_linux`, no ruling: [report](../completed/mlxf_linux_report.md) with the CUDA inventory; every unit area passes on Linux's CPU device in Debug and Release, five GPU-only skips, no Linux-only one; three portability fixes, one of them a real bug of file checks on Linux; awaits the controller's macOS gates on the M5 and the maintainer's read) | [`mlxf_linux.md`](mlxf_linux.md) (run `mlxf_linux`, on dell2) | nothing on the M5: it runs beside the K runs; `liblapacke-dev` on dell2 (its decision 3) | its plan's acceptance; the macOS gates unchanged when the result is fetched |
| 3 | **The rest of parity** (the rest of Phase 4, the random half of Phase 5, Phase 6, the other `fast` functions, Phases 8 and 9) (delivered in the working tree, 2026-11-26, by run `mlxf_parity_rest`: [report](../completed/mlxf_mlxc_parity_report.md), section 10; the ledger has no pending line; rulings R5 and R6 were taken in the session under the maintainer's go, open to his review; the API of Phases 5 to 8 was not read at a hold and awaits his read) | the parity plan | rank 1b and rank 2b (Hans, 2026-11-25: release hardening before parity's remaining phases); after rank 2c (Hans, 2026-11-25: "Yes, go" on the plan's order: the next kernels and SIMPLE's integration build on the toys' shape) | no `pending` line; the parity report |
| 4 | **SIMPLE's integration**, designed and measured on the Mac with the seam's bytes per part recorded (decision 20) | a SIMPLE plan, written by SIMPLE's rules | ranks 2d, 2e and 2f (decision 16) and Phases 0 to 2 of rank 2g (decision 17), then rank 2 for the family concerned | not started here |
| 5 | **CUDA on NVIDIA Blackwell** (Hans, 2026-11-26, decision 19; split 2026-11-27, decision 20): MLX's CUDA backend under mlx-fortran, the suite on the CUDA device, one kernel type for Metal and CUDA sources, CUDA twins of the kept fused kernels judged by the 30 % rule against their graph forms, and the measurements rank 4 needs from a PCIe card (transfer costs, parts sharing one card) | [`mlxf_cuda.md`](mlxf_cuda.md) (ruled 2026-11-27: the kernel type `mlx_custom_kernel`, the toolkit chosen at work): Part A `mlxf_cuda_prep` on dell2 (rank 5a), Part B `mlxf_cuda_twins` on dell2 after K7, Part C `mlxf_cuda_blackwell` on a Blackwell machine at work with Claude Code there | rank 2h; dell2's CUDA 12.9 toolkit and cuDNN (installed 2026-11-27); for Part C, Hans at a Blackwell machine | its plan's acceptance |
| 5a | **CUDA, Part A: the preparation on dell2, without a GPU**: `build_mlx_deps.sh --cuda`, the backend query `mlx_cuda_is_available` and the fourth test session, the kernel type `mlx_custom_kernel` for Metal and CUDA sources (the old `mlx_metal_kernel` renamed), the CUDA sources compiled as MLX compiles them, the card's memory in `run_parts.sh`, the session script for work, the record (delivered in the working tree on dell2, 2026-11-27, by run `mlxf_cuda_prep`, ruling R1: [report](../completed/mlxf_cuda_report.md); CPU-only counts unchanged, the CUDA build links with zero warnings, nothing run on a GPU; Apple question 40 found; awaits the controller's macOS gates on the M5 and the maintainer's read) | [`mlxf_cuda.md`](mlxf_cuda.md), Part A (Phases 0 to 5) | rank 2h; dell2's CUDA 12.9 and cuDNN 9 | its plan's acceptance 1; the macOS gates unchanged when the result is fetched |

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
13. (2026-11-24, proposed from the review; **ruled B** on 2026-11-26 by decision 18: decision-level agreement
    accepted) **What K4's maps must agree with, decided before any timing.**
    - The reference-side variant is judged cell by cell against the Fourier-Bessel oracle, in any case.
    - The particle-side variant changes which cells exist, so a correct calculation can still change which
      candidates survive screening. It is admitted only with a decision-level test frozen before timing:
      the mode's displacement and the retention of candidates, on representative and near-tie fixtures,
      against a stated bound.
    - To rule: are SIMPLE's exact cells required (then the reference-side variant is the kernel), or is
      decision-level agreement accepted?
    - **Outcome (run `mlxf_kernel_k4`, 2026-11-27,
      [report](../completed/mlxf_kernel_k4_report.md)):** the particle-side variant failed the frozen test (its
      start shifts moved more often than a half-step control's plus one in 2 of 12 judged rows), so the plan went
      on as under exact cells; the reference-side variant reproduces the oracle's cells but reaches 0.18 of the
      Fourier-Bessel form's ceiling and was removed. The particle-side variant was the fast one (1.29 times the
      Fourier-Bessel graph). The fused map reductions gave 1.23, below 1.30, and were removed; the Fourier-Bessel
      maps with the graph reductions stay.
14. (2026-11-24, proposed from the review; stands as recommended since the maintainer's go of that day, open to
    the review) **K6's repeatability, and an early probe.**
    - Bitwise repeatability on one GPU configuration is a gate for the form that is kept (the family rule).
      Reproducing the CPU's summation order is a separate property and is not required unless ruled.
    - Right after K2, one protected update is tried on a collision-heavy fixture: numerator, density,
      repeatability and peak scratch memory. SIMPLE's offload insertion shows the opportunity; its
      shared-voxel updates are unprotected, so it does not show the speed of a correct scatter. The probe
      tests the premise of an easy win without moving K6 forward.
    - Recommended: yes.
    - Measured by K2's probe (2026-11-25): one thread per (pixel, plane) with atomic float32 additions inserts
      1,000 planes at n = 160 (2.84e8 deposits) in 0.037 s per batch of 500; plain additions lose 59 % to 98 % of
      the mass. Against the gridding oracle its error is 1.07e-4 of a voxel's terms, above the probe's cap 1e-5
      (outcome C by the letter), but the same deposits in double precision from float32 coordinates are 1.09e-4
      off: the coordinates set the floor, and the update itself varies by at most 2.4e-6 and is not bit-repeatable
      (B in character). **Ruled B** (Hans, 2026-11-25: "B for the probe, keep the defaults"): K6 needs a deterministic form, with the atomic kernel as
      its speed reference and its cap judged against a reference on the kernel's own float32 coordinates.
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
    - Measured by K1 (2026-11-25): the compiled tail is about 0.65 s of the 1.13 s unbarriered pass (the
      ceiling 2.98 and 2.31 at the judged splits) and the fused tail takes the pass to 0.63 s. Summed
      per-process medians over-count when parts on the shared GPU drift apart; a rate of several parts is
      read on the time from go to the last exit. Per-part memory is reported, not judged: SIMPLE trades it
      against the number of parts (Hans, 2026-11-25).

16. (2026-11-26, Hans) **Integration is not next; three things come first.** "I do not agree that we will be ready
    for integration so soon." In his order: (1) refactoring (rank 2d): `mlxf_array` and `mlxf_ops` are very large
    and read as piled up, with interfaces set without a line between them; the `.inf` files lack `!@descr:`; the
    code-base map machinery of XEMA and SIMPLE is lifted over; `mlxf_linalg` is looked at against the aim of
    replacing BLAS; the test folder is divided into subfolders. (2) The toy tests catch up with SIMPLE's new
    memory layout of the polar Fourier transforms, so that tests and benchmarks run on the same layout (rank
    2e). (3) The developments are reviewed against mlx3D, with experiments on different ways of writing the
    kernels (rank 2f). The drafts of K3 to K7 wait behind these and are revised by them.

17. (2026-11-26, Hans requested the consolidation and prioritized plan; ordering below **recommended, not ruled**)
    **User-facing hardening has one owning plan:** [`mlxf_user_hardening.md`](mlxf_user_hardening.md).
    Its C1–C14 reconcile Claude's ten findings with Codex's integer-statistics, failed-save, numeric-range
    and empty-reduction findings, distinguishing MLX defects, gfortran limitations and library API choices.
    Recommend its baseline/guidance, integer-statistics/save fixes and explicit bounds/lifetime safeguards
    before another public release. Source work is serialized immediately before rank 2d if it is unstarted,
    otherwise remapped after it; this proposal does not silently override the already authorized rank-2d
    slot or reorder 2d→2e→2f. Reference generation and cost measurements consume their results. Upstream
    reports are prepared alongside local work; no submission or implementation launch is authorized by
    this planning request. The new API/semantic choices are recommendations in the owning plan.
    - Placed 2026-11-26 at Hans's request ("put this in the appropriate place in the dev plan"): **rank 2g,
      the run after rank 2f**, the whole plan as one run. Rank 2d was delivered first, so the plan's file table
      was remapped to the delivered owners (`src/test/framework/`, `mlxf_calls`, the eight `mlxf_ops_*`
      modules), as its decision 2 asks. Why after 2f: decision 16's order stands, and 2e and 2f touch only
      `src/test/` while this plan changes `src/core/`, so nothing of it is undone by them. Why before K3 to K7:
      Phases 1 and 2 are silent wrong results and lost checkpoints, which come before new kernels. Rank 4
      waits for Phases 0 to 2 (the plan's own recommendation); Phase 6's second-architecture
      check may stay open without holding K3. Alternative: run it between 2e and 2f, which puts the P1 fixes a
      run earlier at the cost of decision 16's order. Its API choices (the plan's decisions 3 to 9) were ruled as
      recommended by Hans the same day.
    - Closed 2026-11-27 at Hans's request: Phase 6's second-architecture condition now has M5 and M2
      evidence, including RoPE and installed consumers. RB1 (empty host-array constructors at the
      compiler/transfer boundary) was closed the same day under Hans's ruling (a): `mlx_from` refuses an array
      of unknown size. RB2 (a clean tagged release gate) is withdrawn: when to tag a release is the maintainer's decision, outside the plans (hans, 2026-11-27).
      No upstream submission was made.

18. (2026-11-26, Hans: "Rule as recommended") **The K3 to K7 plans, as revised after ranks 2d to 2f.** Every
    decision of section 3 of each plan stands as recommended, the K7 plan's reserved decision 11 (a keyed hill-climb
    order, which changes SIMPLE's random stream at integration) and its new decision 27 (K1's tail judged inside K7)
    included. The runs go K4, K3, K5, K6, K7, one at a time on the M5 Ultra, after rank 2g's result is committed;
    each from the commit holding the previous run's verified result.

19. (2026-11-26, Hans) **Linux and CUDA come off the not-planned list.** "Yes, Linux and CUDA should come off the
    not-planned list, I have three machines at work with Blackwell GPUs but no one right here now. Any prep work we
    can do on dell2 would be useful, however." Rank 2h is the CPU-only Linux build on dell2, beside the K runs;
    rank 5 is CUDA, planned from rank 2h's inventory when a Blackwell machine is reachable. The graph forms the
    toys keep (decision 15) are the portable path; each kept fused Metal kernel needs a CUDA twin or falls back.
    - **The design stays MLX-centric** (Hans, the same day: "We want an MLX-centric design, however, with minimal
      code changes to transfer to NVIDIA chips. I understand the metal kernels will have to be replaced, but we
      should try and stay as close to the MLX philosophy as possible"). In practice: MLX operations and `fast`
      functions first, a custom kernel only where the 30 % rule keeps it; a kept kernel is MLX's custom-kernel
      mechanism (source text plus a launch spec, inputs and outputs MLX arrays), never a hand-written host path
      around it; its source, its spec and its graph form sit together so that the CUDA step adds a CUDA source
      and spec beside the Metal one and changes nothing else; no toy or library code branches on the platform
      outside the kernel's source and the device checks of the tests. Each K run reports what its kept kernels
      would need for a CUDA twin.

20. (2026-11-27, Hans: "1. PCIe. 2. no. 3. Both, but Mac has priority") **SIMPLE's platforms, and what that means
    for ranks 4 and 5.** The Blackwell machines at work are PCIe cards in x86 hosts; none can be reached from here;
    SIMPLE will run on both platforms, the Mac first. Hence (recommended, not ruled):
    - **Rank 4 is designed and measured on the Mac** and does not wait for rank 5. Two rules keep the NVIDIA
      platform open: the references a part needs stay on the GPU across the calls of an iteration, and each call
      does a large piece of work; and the integration plan measures, on the Mac, the bytes that cross the seam
      between SIMPLE and the library per part per iteration. Over PCIe those bytes are the cost, so rank 5's
      measured seconds per byte predict the NVIDIA price before integration is ported. One GPU state per part
      process, as all the Mac work assumes; a shared GPU server is a question for discrete cards, answered by rank
      5's parts measurement if at all.
    - **Rank 5 in three runs** ([`mlxf_cuda.md`](mlxf_cuda.md), ruled by Hans the same day: option A for the
      kernel type, the toolkit chosen at work by the plan's rule, every other decision as recommended): what needs no GPU is done on dell2 first (the
      CUDA build, the backend query, a fourth test session, one kernel type, the memory guard, a session script),
      the kernels' CUDA sources after K7, and the session at work is bring-up and measurement, with Claude Code on
      that machine since nothing there is reachable from here.
    - dell2 holds a compile-only CUDA setup (Hans, 2026-11-27): CUDA 12.9 in `/opt/cuda-12.9` (the runfile's
      components; its installer needs `libxml2.so.2`, absent on Ubuntu 26.04), cuDNN 9.28 in
      `/opt/cudnn-9-cuda12`, `gcc-14`, and six declarations of `crt/math_functions.h` given `noexcept (true)` for
      glibc 2.43.

## 5. Not planned

- Any change to SIMPLE before rank 4.
- The nonuniform filter and the volume assembly on the GPU.
- More graph-level work on the Fourier-Bessel maps. Family A replaced their formulation in neither of K4's
  lattices (run `mlxf_kernel_k4`: the particle-side one failed the decision-level test, the reference-side one
  its ceiling), nor did fused reductions (1.23); the Fourier-Bessel maps stay as they are until a ruling reopens
  the particle-side lattice's test.
- The accelerated mode (TF32, NAX).
- New profiling runs of SIMPLE.
- A single process that owns the GPU and serves every part. It is decided only after the toys' multi-process
  timings show how well parts share the GPU.
- Compilers other than gfortran (the parity plan's section 4 stands for them). Linux and CUDA left this list on
  2026-11-26 (decision 19).

## 6. Keeping this note current

When an item closes, its row gains the commit and the report's path, and the next row's "depends on" is
checked. A ruling is written into its decision here and applied in the plan it names in the same change. A
new item enters only with a rank and an owning plan.
