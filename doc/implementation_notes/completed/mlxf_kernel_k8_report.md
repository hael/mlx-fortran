# Report: K8, the PCG solve of the reconstruction (run `mlxf_kernel_k8`)

Run on the M5 Ultra on 2026-11-25, in the session, in a scratch copy of the maintainer's tree. Phase 0 ran from 09:16
to 09:48 on `6a4d5f9` plus 60 lines of `git status --porcelain` and stopped at decision 10 (ruling R1). Phases 1
and 2 ran from 13:24 to 14:15 on the maintainer's checkout of that moment (`6a4d5f9` plus 78 lines, holding K1, K2
and Phase 0) and stopped at gate (b) (ruling R2). Phases 3 to 6 ran from 14:21 to 16:30. Plan:
[`mlxf_kernel_k8.md`](../planned/mlxf_kernel_k8.md), with one Progress entry per phase, both rulings and every
log's path. SIMPLE read at `d354efee2`. Nothing is committed.

## 1. What was learned

**At SIMPLE's iterations the toy reproduces SIMPLE's assembly and solve on the GPU, and fast.** One half's
assembly, from the master's raw packed accumulators to the shipped map (`new`, `set_window_sphere`,
`set_raw_accum`, `end_accum`, `solve_accum`, `kill`), takes on the M5's GPU (*measured*, best of three, two
invocations bit for bit equal):

| n (padded) | 2 iterations (production) | 5 iterations (final map) | end_accum within | MLX peak |
| --- | --- | --- | --- | --- |
| 160 (320³) | 0.084 s | 0.105 s | 0.058 to 0.061 s | 3.39e9 B |
| 256 (512³) | 0.332 s | 0.413 s | 0.231 to 0.247 s | 1.14e10 B |

MLX's CPU device with the same graph takes 1.99 s and 3.82 s at n = 160 and 8.52 s (2 iterations) at n = 256, on one
core: the GPU is 24 to 36 times faster. SIMPLE itself was not measured, and no record of its PCG solve at these
boxes is in hand.

**Accurate and repeatable.** The operator, the preconditioner, the kernel and preconditioner spectra, the ridge
and the right-hand side agree with the double-precision oracle within one or two float32 roundings (largest 4.9e-7
relative at n = 8 and 32, 3.0e-7 at n = 160 and 2.5e-7 at n = 256). Under SIMPLE's 2 and 5 iterations the iterates agree
with the oracle's within 6e-6 at n = 8 and 32, and the reported residuals with the oracle's true ones within 2.1e-7 of
|b| at n = 160 and 7.7e-8 at n = 256. The device stops where the oracle stops, by the same test. Maps and histories are bit
for bit equal across passes and across invocations at n = 160 and 256.

**Nothing to fuse.** The transforms are 46 to 50 % of the solve under 2 iterations and 64 % under 5. The time is in
`end_accum` (56 to 74 % of the driver at n = 256: the host's statistics of the density and the finalisation's
three transforms). Ceilings measured on the driver bound what each second path could gain at
n = 256: a free pointwise kernel 1.13 (F2) and 1.19 (F5) times, waits removed 0.3 to 0.5 %. Decision 18 entered
Phase 4 (f is 0.35 to 0.50), but no kernel could pass the 30 % rule, so none was written.

**The scalars and waits are settled.** Inner products as n² float32 line sums added in double (S2) lie within 6.4e-9
of the double sum at n = 160 and 256. A wait costs 0.17 ms, under 1 % of an iteration. The float32 drift of the
recursive residual over 50 iterations is under 2.3e-8 of |b|.

**SIMPLE's preconditioner hurts on a fully covered fixture.** Found in Phase 0: the preconditioned support block's
condition number is 1.3e6 against 122 without it, and CG needs 104 to 127 iterations to 1e-4 against 21. It came back
in Phase 2: the preconditioned solve needs about 1,300 iterations, not 200, to reach float32's floor (3.3e-7). Under
R1 the effect where SIMPLE uses it: after 2 and 5 iterations of system R the iterates are 0.40 to 0.42 and 0.28 to
0.30 from the exact solution with it, 0.23 and 0.14 without it (n = 8; 0.68 / 0.36 against 0.31 / 0.19 at n = 32).
Under SIMPLE's absolute ridge, 5 iterations are far from the exact solution of the near-singular system either way.
These are reported for SIMPLE, not gates of the port.

**MLX's GPU transforms need much working memory.** One padded forward and inverse pair at 512³ peaks at 6.0e9 B, and
the solve at n = 256 at 1.14e10 B against a derived resident set of 1.08e9 B (Apple question 25).

## 2. What changed, phase by phase

| Phase | What | Files |
| --- | --- | --- |
| 0 | the oracle's four exports, the full-coverage fixture, `suite=transform`, Apple question 25 | `src/test/mlxf_oracle_recon_pcg.f90`, `src/test/mlxf_oracle_recon_fixture.f90` (new), `src/test/mlxf_bench_recon_pcg.f90` (new), `src/test/mlxf_test_defs.f90`, `src/test/mlxf_test_registry.f90`, `doc/collaboration/apple_questions.md` |
| 1 | the toy, its workspace, the engine; the operator's suites; the ledger | `src/test/mlxf_toy_reconstructor_pcg.f90`, `src/test/mlxf_toy_reconstructor_pcg_workspace.f90`, `src/test/mlxf_toy_pcg_solver.f90`, `src/test/mlxf_toy_reconstructor_pcg_tester.f90` (all new), `mlxf_test_defs.f90`, `mlxf_test_registry.f90`, `scripts/toy_mirror.txt` |
| 2 (and R2) | the engine's suite, the solve's gates, then their re-statement | `src/test/mlxf_toy_pcg_solver_tester.f90`, `src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90` (both new), the Phase 1 files |
| 3 | the benchmark's suites `time`, `profile`, `probe`, `accuracy` | `src/test/mlxf_bench_recon_pcg.f90` |
| 4 | entered, nothing written (the ceiling) | none |
| 5 | measurements and plants | none |
| 6 | the record | `mlxf_kernel_families.md` (sections 2a, 6, 8), `doc/policies/test_environment_policy.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md`, `src/test/test.inf`, `README.md`, this report, the plan's Progress |

Counts (*measured*, Debug and Release, the final from-scratch builds): `unit_kernels` 1,496 to 1,732 (`pcg_solver`
84, 0.25 s Release; `reconstructor_pcg` 152, 2.95 s Release with its registration comment). Every other area is at
the base's count: `unit_fast` 94, `unit_fft` 194, `unit_linalg` 632, `unit_ops` 2,462, `unit_array` 193,
`unit_compile` 63, `unit_core` 80 to 82 (it moves between runs). The named-only `reconstructor_pcg_n32` has 96
checks and passes. The CTest entries and their budget of 9 did not move. Nothing under `src/core` or `src/defs`
changed.

## 3. Decisions taken under delegation

Each one is in Progress with its reason. The main ones:
- Phase 0:
  - the exports are generic interfaces;
  - the fixture's variates and conventions;
  - F2's diagnosis in a scratch driver.
- Phase 1:
  - the inquiries `copy_spectra` and `copy_volumes`;
  - the lattice's members are public, as SIMPLE's are;
  - the density statistics run over a device view, with a float32 shell index.
- Phase 2:
  - rules R4 and T reach the engine through a test-only operator;
  - the host's waits are counted from the engine's schedule;
  - a non-finite |b| reaches the curvature test, as in SIMPLE;
  - the tester's solve gates live in a submodule.
- Phase 3:
  - W0, W1 and C are judged by measured ceilings, not built;
  - S3 is not reached by the rule, so it was not built.
- Phase 4: not built, by its ceiling.
- Phase 5:
  - R4 is timed through the engine;
  - the CPU device's set of rules;
  - the true residual comes from an untimed solve of equal arithmetic;
  - `suite=accuracy` gates where SIMPLE runs (F2, F5) and reports E and R4.

## 4. Deviations from the plan

- **Two stops and two rulings:**
  - R1: F2 is reported, P = 4N, and the solver and timing are judged at 2 and 5 iterations of system P.
  - R2: gate (b) is reported, and gate (a) at n = 32 judges k = 1, 2, 5 and the stop.
- Phase 4 wrote no kernel and W0, W1, C and S3 were not written. Measured ceilings or the plan's own ladder
  decided each.
- The file-table row of the tester's submodule was added after the file existed.
- The engine module came in Phase 1, because the reconstructor's adapter needs it.
- Decision 20's hypothesis on the peak (at most 4.3e9 B at n = 256) is refuted: 1.14e10 B.
- R4 does not reach its rtol in 200 iterations at n = 32, 160 or 256.
- The benchmark is one file of about 1,060 lines. Decision 23 covers only the toy's files, so it was not split.

## 5. Evidence

- **Builds:** Debug and Release from scratch with `MLXF_WERROR=ON` at every phase's end and after R2. 0 warnings,
  fast gate 9 of 9, `scripts/check_tree.sh` passing, both formatters run on every touched Fortran file. Paths are
  under the run's `scratch/keep/`.
- **Tolerances:** calibrated on seed 1 on both devices and both builds, and frozen before seeds 2 and 3 ran (Phase 1
  and 2 Progress).
- **Plants:** 7 in Phase 1, 9 in Phase 2 and 2 in Phase 5, each failing its named gate, every file restored to its
  checksum.
- **Timed runs:** each started at a one-minute load of at most 4 (1.3 to 1.9), recorded `uptime` before and after,
  saw no other compiler or test process, and ran under `/usr/bin/time -l`.

## 6. Left open for the maintainer

- **For SIMPLE:**
  - Whether SIMPLE's preconditioner (`finalize_density_accum`'s `1 / (rho + floor)` with its zero beyond the
    native Nyquist sphere) also worsens the 2- and 5-iteration iterates at SIMPLE's boxes on real data.
  - SIMPLE's `PCG_ASSEMBLE_BENCH` at box 160 or 256, to set beside the toy's times.
- **Reported, not gated:**
  - rule T and the float32 floor;
  - the n = 32 stop iterate;
  - F2's condition numbers;
  - the iterate errors against the exact solution;
  - every time and byte count;
  - E and R4 at bench size.
- **Follow-up:**
  - batching the two halves (the design needs one half's resident 1.08e9 B and peak 1.14e10 B; the waits are 7 or
    13 per solve);
  - the host's density statistics in `end_accum` (0.17 s of 0.25 s at n = 256) are the next target if the
    assembly is to go faster;
  - Apple question 25.
- **Reserved:** whether the miniature reads like SIMPLE. The differences are in `mlxf_kernel_families.md`,
  section 6.

## 7. A commit message

```
K8: the PCG solve of the reconstruction as a toy reconstructor_pcg

A miniature of SIMPLE's reconstructor_pcg and simple_pcg_solver from the
master's raw packed accumulators to the shipped map: the host keeps the
envelopes, the window and the density's shell statistics; the device holds
the kernel and preconditioner spectra, the mask and the right-hand side;
the engine forms its scalars in double from the device's line sums and
waits twice per iteration. Graph form only.

Against the double-precision oracle the operator, preconditioner, spectra,
ridge and right-hand side agree within one or two float32 roundings; under
SIMPLE's 2 and 5 iterations the iterates agree within 6e-6 at n = 8 and 32
and the reported residuals with the oracle's true ones at n = 160 and 256;
the engine's stops are exact; maps repeat bit for bit within and across
invocations; 18 planted defects fail. Rulings R1 and R2 (SIMPLE never runs
more than 5 iterations) made system P at 2 and 5 iterations the judge.

On the M5 Ultra's GPU the driver takes 0.084 and 0.105 s at n = 160 and
0.33 and 0.41 s at n = 256 (2 and 5 iterations), 24 to 36 times MLX's CPU
device; no fused, wait-free or compiled form can gain 30 %. SIMPLE's
preconditioner worsens the iterates on the full-coverage fixture (reported).

New files: src/test/mlxf_oracle_recon_fixture.f90,
src/test/mlxf_bench_recon_pcg.f90, src/test/mlxf_toy_reconstructor_pcg.f90,
src/test/mlxf_toy_reconstructor_pcg_workspace.f90,
src/test/mlxf_toy_pcg_solver.f90, src/test/mlxf_toy_pcg_solver_tester.f90,
src/test/mlxf_toy_reconstructor_pcg_tester.f90,
src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90,
doc/implementation_notes/completed/mlxf_kernel_k8_report.md.

Run mlxf_kernel_k8; plan doc/implementation_notes/planned/mlxf_kernel_k8.md.
```
