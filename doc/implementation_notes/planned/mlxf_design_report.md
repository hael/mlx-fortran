# Report: run `mlxf_core`, Phases 0 and 1 of the design plan

Run `mlxf_core` (arun, unattended) on FWM-S116118, an M2 Ultra (16 performance and 8 efficiency cores, 76-core
GPU, 192 GB, macOS 26.7.3); base `86a43fae2`, the scaffold; 2026-11-20 to 2026-11-21. The plan
(`mlxf_design.md`, beside this report) holds the detail in its Progress section; this is the summary for the
review. Nothing is committed: the diff of each phase is
`/Users/elmlundho/agent_work/arun/mlxf_core/review/phase_N.diff`; evidence paths below are under
`/Users/elmlundho/agent_work/arun/mlxf_core/scratch`.

## 1. What changed, phase by phase

- **Phase 0, the baseline** (`review/phase_0.diff`; documentation only): the machine, the toolchain and
  Homebrew's shared MLX 0.32.4 and mlx-c 0.8.0 recorded; mlx-c's C examples (a custom Metal kernel included)
  run on the GPU; the scaffold's gate in Debug and Release, one GPU visible from the run's session; SIMPLE
  `5709265cb`'s polar matching baseline twice per case; SIMPLE's image-FFT planner flag; f of decision 28 from
  the owner's BENCH directory (ruling R2: 0.23); ruling R3 recorded as decision 38.
- **Phase 1, step 1, the probes** (stopped, 2026-11-21 01:00): three gfortran finalization defects beyond the
  known one (also in gfortran 13.4) made decision 8's leak gate impossible as written. The owner answered with
  ruling R4 (decision 39) at 07:20.
- **Phase 1, the core** (`review/phase_1.diff`, which includes the probes' record): the independent prototype
  list (680 names, frozen in Progress before the generator existed) and the generator of the `bind(c)` layer
  (673 interfaces + 7 skips = 680, checked on every build); `mlxf_libc`, `mlxf_error`, `mlxf_registry`,
  `mlxf_device`, `mlxf_memory`, `mlxf_array`, the user module `mlxf`, `mlxf_version` on the generated layer
  with `mlxf_runtime_description()`; testers for each; `mlxf_test_exec device=` and `expect_aborts` with the
  guard group `object_contracts`; CTest areas `core` and `array`, budget 3; `MLXF_REQUIRE_GPU`,
  `MLXF_CMAKE_ARGS`, the CI setting; rules `arity` and `ctorcall` and the `mlxc_` re-export check; the binding
  contract policy and the skill `mlxf-binding`; R4 recorded everywhere it asked to be.

## 2. Decisions taken under delegation

All are listed with their reasons in the Progress entries; the ones of substance:

| decision | where recorded |
| --- | --- |
| SIMPLE's load rule read as the load of other processes (the benchmark's own 24 threads raise the load average to about 24); a run with others above 400 % of a core repeated (one was) | Progress, Phase 0 |
| f's stages taken as runs of equal mode, `nspace` and `kto` (the records carry no stage number): reproduces R2's 8 stages and every figure | Progress, Phase 0; decision 28 |
| the generated types in one module, `mlxf_c_types` (the headers' types form a cycle) | Progress, Phase 1; the binding policy; the register |
| no `mlx_device` type (integers `MLX_CPU`, `MLX_GPU`); `mlx_device_info_size`/`_string` public for the runtime description and the recovery gate | Progress, Phase 1 |
| the default stream looked up per operation (no stream cache beyond the allowed state) | Progress, Phase 1 |
| `mlx_alloc(..., zero_copy)` reports whether Metal took the buffer; buffers rounded up to whole pages | Progress, Phase 1; the policy |
| the one-thread guard refuses any OpenMP region level (CTest runs a team of one) | Progress, Phase 1; the policy |
| byte identity: float32 at ranks 0 to 4 and 7, the other kinds at ranks 0, 2, 3 | Progress, Phase 1 |
| guard members in the suite registry (`GUARDS`), children through `guard=` | Progress, Phase 1; the test policy |
| the recovery gate as worded: it allocates half the GPU's maximum buffer per device (64.9 GB here) | Progress, Phase 1; `test/CMakeLists.txt` |
| the overlapping section assignment of handles listed as unsupported (it stops as stale) | Progress, Phase 1; the policy; the skill |

## 3. Deviations from the plan

- Decision 4.1 asks for one module per header with its types; the types are one module (above). No other
  deviation; every changed file is in the file table (the `doc/compiler_issues/` row was added by R4).
- The stop at step 1 was the plan's own rule ("a failed probe other than the known bug is a stop"), answered
  by R4; the leak gate's two cases that hit a defect now use their supported forms, as R4 rules.

## 4. Evidence against the baseline

- Base builds (`keep/base_{debug,release}`): gate passed, `unit_core` 5 checks, one GPU device. Phase 1
  builds (`p1_debug`, `p1_release`, clean): zero compiler warnings, fast gate 3 of 3 (`unit_core` 68 to 70 checks,
  `unit_array` 80, `object_contracts` 4 members), about 8 s (`logs/p1_{Debug,Release}_final.log`).
- Gates no ruling may waive: the leak gate (exact, 10,000 iterations per device), the diagnosis gate, the
  recovery gate, byte identity of data movement and generator coverage pass on both devices; the planted
  defects fail as they should (a guard's stop removed, a generator mapping removed, the budget at 2, each new
  static rule; `logs/plants_build.log`, `logs/plant_rules.log`, `logs/plant_test_registry.log`).
- SIMPLE's baseline on the M2 Ultra (Phase 0): `matrix_t` 2.91 to 2.95e6 pairs per second at 24 threads on
  the verdict's case (2,500 directions x 4 states), 2.60 to 2.62e6 on the 16 performance cores, `per_pair`
  1.22 to 1.23e6; run-to-run spread at most 2.1 % at the full teams (`keep/simple_baseline_m2ultra/`).
- Phase 1's measurements: a registry check 6.5 to 9.2 ns per operand; building one binary operation 0.50 to
  4.1 µs (MLX's side varies); `mlx_alloc` zero-copy at every size from 1 KiB to 64 MiB
  (`logs/p1_release_timed.log`).
- An independent read-only review of the Phase 1 diff found six defects in status and pointer paths of
  `mlx_alloc`, `mlx_view` and `mlx_to`, the zero-size address, a dead dimension check and the thread guard of
  the assignment; all fixed, pinned by eight new checks and re-gated (Progress, Phase 1).

## 5. Left open for the maintainer

- **Reported, not gated:** f = 0.23 bounds decision 20's end-to-end gain on the BENCH run at 1.09 (1.16 at
  the 60 % share); decision 38 already points the next pipelines at the shift refinement and the assembly.
- **Data- and machine-dependent:** the recovery gate allocates half the GPU's maximum buffer length per
  device in every fast gate (64.9 GB, about 7.5 s here); on a Mac with a larger maximum it allocates more.
  The CI path without a GPU (skips) was not exercised: this session has one.
- **To rule:** an overlapping section assignment of an array of handles (`v(2:3) = v(1:2)`) stops as stale
  (a bitwise temporary; no double free): listed as unsupported in the policy, or to be made to work. Operator
  results inside array constructors leak like function results and are not checked by `ctorcall`.
- **Follow-ups:** decision 34's upstream report should carry all four gfortran reproducers in
  `doc/compiler_issues/`; SIMPLE's baseline and the gates are to be re-run on the M5 Ultra (decision 27); the
  plan stays in `planned/` for Phases 2 to 6.

## 6. A commit message

```text
mlx-fortran: Phase 0 baseline and Phase 1 core (generated bind(c) layer, registry-counted mlx_array)

Phase 0 records the M2 Ultra toolchain, the shared MLX 0.32.4/mlx-c 0.8.0 pair, the scaffold's gate and
SIMPLE's polar matching baseline, and f = 0.23 from the BENCH run (rulings R2, R3).
Phase 1 adds the generator of the bind(c) layer with its independent coverage list, the error, registry,
device, memory and array modules with their gates on both devices, the object_contracts guard group, the
arity and ctorcall rules, the binding contract policy and the mlxf-binding skill, under ruling R4.
```
