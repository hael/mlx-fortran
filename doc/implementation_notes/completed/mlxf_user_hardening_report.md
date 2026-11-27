# User-facing hardening: the report of run `mlxf_user_hardening`

Run `mlxf_user_hardening`, 2026-11-26, unattended on the M5 Ultra (macOS 27.2.1, GPU `applegpu_g17d`, GNU Fortran
16.2.0, MLX 0.32.4, mlx-c 0.8.0), base `ae7d62367facaffc88a2262f8cb9b34ffcd88cfc`, everything in the working tree.
The plan is [`planned/mlxf_user_hardening.md`](../planned/mlxf_user_hardening.md); its Progress section holds every
phase's detail, numbers and evidence paths (the evidence lives under
`/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/`). Rulings applied: R0 (decisions 3 to 9 as recommended),
R1 and R2 (two file-table rows after the driver's fence stopped Phases 2 and 4).

## In one paragraph

Every P1 defect the two user reviews found is closed locally: integer statistics are right (C1), a failed save no
longer destroys the old checkpoint (C2), untrusted indices have an explicit check (C3), and the silent gfortran
leaks have an installed checker that reports them at build time (C4). Norms and means near the ends of the floating
range are right, empty extrema behave as Fortran's (C5, C6), and `a + 1` compiles (C9). Recoverable graph
construction (C7) is designed and prototyped, deferred as R0 requires. A generated reference, a neutral installed-use
guide and a measured cost model answer C8 and C10 to C13. The release gate, the installed consumer and the CPU-only
CI pass; **release readiness stays open on the second Metal GPU architecture**, which this run does not have
(decision 12).

## What changed, phase by phase

| Phase | Diff | What |
| --- | --- | --- |
| 0 | `review/phase_0.diff` | Base pinned and green; C1 to C14 reproduced (C1, C5, C6 also through mlx-c alone: new `scripts/probes/user_statistics_probe.c`, `user_range_probe.c`; C4 through gfortran alone); bounds frozen before any fix; guidance S1 to S7 in the quickstart, run by the new `test/consumer/mlxf_example_user_safety.f90`; Apple questions 31, 33 to 35 updated |
| 1 | `review/phase_1.diff` | C1: `mlx_mean`, `mlx_var`, `mlx_std` convert integer and boolean input to float32. C2: the three array saves check the format's kinds, evaluate, write a hidden temporary sibling and rename it over the destination; symlinks, hard-linked files, non-regular and other users' files refused; permissions kept; libc bindings in `mlxf_libc` |
| 2 | `review/phase_2.diff` | C3: `mlx_check_indices` (one generic, element and slab forms, single arrays and lists, a required status, one evaluation). C4: the lifetime analysis moved into the new `scripts/mlxf_consumer_checks.py`, shared by `check_rules.py` and the new installed `scripts/check_consumer.py` (nine rules, scope-aware, a 21-fixture self-test), with `mlxf_check_lifetime(<target>)` in the package config |
| 3 | `review/phase_3.diff` | C5: `norm2` and the floating `mlx_mean` scale by the largest magnitude (one helper, its gradient stopped). C6: Fortran's identities for `maxval`/`minval` of an empty extent in 13 kinds. The empty-slice item closed by documentation |
| 4 | `review/phase_4.diff` | C9: default-integer scalars on the eleven operators, exact in integer kinds and refusing to wrap (three guards). C7: designs A (checked procedures) and B (validators), a scratch prototype, disposition deferred |
| 5 | `review/phase_5.diff` | C12: the new `scripts/generate_api_reference.py` and `doc/api_reference.md` (316 of 316 names, a staleness check and self-test in the static gate). C8, C10, C11, C13: the new `doc/how2s/how2use_installed.md`; the README leads with use. C11: the new named-only benchmark `src/test/bench/mlxf_bench_user_costs.f90` |
| 6 | `review/phase_6.diff` | The release gate, the installed checks and the CPU-only CI (Debug and Release, against a CPU-only MLX built from the pinned sources); a bytecode side effect of Phase 2's scripts fixed; an independent review of the new tests and the fixes it led to; MLX's main branch checked for the upstream items; the records and this report |

## Decisions taken under delegation

Each is recorded, with its reason, in the plan's Progress entry of its phase.

- **Phase 0**: failing reproducers kept outside the test executable (scratch programs and the C probes) until their
  fixes; checkpoint advice "save under a new name" while saves were unsafe; C11 not timed before Phase 5.
- **Phase 1**: hard-linked and other users' files refused as save destinations; a save into an unwritable directory
  fails even over a writable file; the kind preflight in the library; the transaction's two steps as the test seam
  (no failure switch); two shared types in `mlxf_defs` (rule `defs`); general integer fixtures judged by the family's
  tolerances on scaled data.
- **Phase 2**: one generic name for the validator, `status` required; default-integer extents; an `mlx_array`
  argument; uint64 values at or above 2^62 refused outright; the checker resolves names per scope; installed under
  `share/mlxf/`.
- **Phase 3**: the complex scale from real and imaginary parts; the scale's gradient stopped; MLX's plain result kept
  for zero and non-finite scales; half kinds keep their arithmetic; `mlxf_ops_reduce.f90` compacted to its
  1000-line limit rather than the limit raised; empty slices closed by documentation.
- **Phase 4**: the integer scalar built through `mlx_from` (the parity ledger keeps `mlx_array_new_int` internal);
  booleans with an integer promote to int32; only default-integer scalars; negative integer exponents follow MLX;
  validators recommended before checked procedures for C7.
- **Phase 5**: the reference links to the policy instead of copying it; private components left out; the guide
  shows the medians of two benchmark runs.
- **Phase 6**: a CPU-only MLX 0.32.4 / mlx-c 0.8.0 built in scratch from the exported sources the maintainer's own
  `build_mlx_deps.sh --cpu-only` had left (copied, never written), with that script's flags; the testers tightened
  after the review (no bound loosened); the two-architecture release rule not written into the test-environment
  policy, since it is not adopted until a second machine runs it.

## Deviations from the plan, and why

- **File table.** Rows were added before their edits, each recorded in Progress: `scripts/check_install.sh`, the
  binding policy and `doc/code_base_map.md` (Phase 0); `src/defs/mlxf_defs.f90` (Phase 1); the test registry and
  `bench.inf` (Phase 5); `mlxf_ops_index.f90` for one comment (Phase 5); the three Python scripts and five testers
  (Phase 6). Two omissions stopped the driver: `test/consumer/mlxf_api_names.f90` (R1) and
  `test/consumer/mlxf_example_differences.f90` (R2).
- **Costs not timed** in Phase 4 (no existing path changed) and Phase 0 (C11 belongs to Phase 5).
- **No new public name in Phase 4**: the integer scalars are private specifics of the existing operators, so R0's
  "names frozen in Phase 4" froze none; the matrix was frozen instead.
- **Release-only failures** (`-Werror=function-elimination`: an impure function as a later operand of
  `.and.`/`.or.`) in Phases 1, 2, 3 and 6 were fixed by separate statements; each first failing log is kept.

## Evidence against the baseline

- **Builds and gates** (each phase and at the end, from scratch with `MLXF_WERROR=ON`): 0 warnings in Debug and
  Release; the fast gate 13 of 13 within its 60 s budget; every unit area in both builds; `check_install.sh` on Debug
  and on Release with `--require-gpu`; `check_tree.sh` (with the new checker's and the reference's self-tests);
  `release_gate.sh --allow-dirty` (snapshot builds, installed consumer on the GPU, embedding, the toys' off-state
  table); `ci_cpu_job.sh` in Release and Debug against a CPU-only MLX. Logs: `phase6/`.
- **The toys' 364-line identity set** is byte for byte the base's after every phase (SHA-256 `e2d65e88...4d33dba5`).
- **Reproductions**: Phase 0's programs against the final install show every C1 and C5 case correct on both
  devices, failed saves preserving 99 and 80 bytes, empty extrema no longer stopping; C3's far index refused before
  it reaches `mlx_take`; the checker reports exactly the three forms that leak at run time.
- **Plants**: each fix removed in a copy built apart fails its tests (C1, C2, C3, C4's shared analysis, C5, C6, C9's
  range check, the reference's staleness check).
- **Costs** (*measured*, not floors): the integer mean about +5 %, a small save about +80 µs, larger saves faster;
  the index check about one evaluated `take`; the scaled norm and mean about +45 % (one more reduction pass); the user
  cost table in the guide.

## Open for the maintainer

1. **The second Metal GPU architecture** (decision 12): run `scripts/release_gate.sh` and the units (RoPE's cases in
   `unit_fast` included) on a machine of another generation (the M2 Ultra of the user review), record its
   `applegpu_*` identifier, compiler and dependency facts and the numerical logs; until then release readiness is not
   claimed. Nothing else blocks it.
2. **C7's follow-up**: whether to implement design B's validators (`mlx_check_broadcast`, `mlx_check_section`,
   `mlx_check_device`), then A's checked operations; rows and acceptance are in the plan.
3. **Upstream drafts, unsent**: Apple questions 31 (narrowed: MLX's main branch already writes saves through a
   temporary file, following symlinks), 33, 34 and 35 (each checked against MLX `5c8989446`: unchanged); GCC issues 2
   and 3 re-observed on the M5. Nothing was filed.
4. **Found outside the plan**: `mlx_from` of a zero-size host array stops (it asks Metal for 2^64 - 4 bytes, on the
   CPU device too); `mlxf_transfer` was in no phase's table.
5. **Residual test gaps** the Phase 6 review named and this run did not close (listed in Phase 6's Progress): a few
   one-sided operand orders for narrow-kind scalars, slab-form edge cases of the validator, a load-back of a replaced
   checkpoint, and an evaluation failure on the CPU device.
6. **Skill proposals** (not edited, per the run's rules): the Fortran skill could name `-Wfunction-elimination` among
   the traps (an impure function as a later operand of `.and.`/`.or.` is an error in Release), and say that a
   comment belongs to the procedure under it when inserting a new procedure before another.

## Commit message (proposed)

```
User-facing hardening (run mlxf_user_hardening, roadmap rank 2g)

Integer statistics in float32; array saves through a temporary sibling renamed
into place; mlx_check_indices; an installed lifetime checker sharing the
repository rules' analysis, with mlxf_check_lifetime; scaled norm2 and floating
mean; Fortran's empty maxval/minval; default-integer scalars on the operators;
recoverable graph construction designed and deferred; a generated API
reference, an installed-use guide and a cost benchmark. The second Metal GPU
architecture remains open.

New files: doc/api_reference.md, doc/how2s/how2use_installed.md,
doc/implementation_notes/completed/mlxf_user_hardening_report.md,
scripts/check_consumer.py, scripts/generate_api_reference.py,
scripts/mlxf_consumer_checks.py, scripts/probes/user_range_probe.c,
scripts/probes/user_statistics_probe.c,
src/test/bench/mlxf_bench_user_costs.f90,
test/consumer/mlxf_example_user_safety.f90.
```
