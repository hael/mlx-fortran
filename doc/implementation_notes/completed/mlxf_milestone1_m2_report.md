# Milestone 1, run `mlxf_m1`: review report

Status, 2026-11-24: completed report for the original M2 run, archived separately from the future
final milestone report. The dated results and then-open findings below are historical; later particle-tile,
Phase 5c and review work is in [the M2 delivery record](mlxf_milestone1_m2.md).
The current remaining work and M5 verdict belong to [the active plan](../planned/mlxf_milestone1.md).

Run `mlxf_m1`, unattended, on the M2 Ultra (FWM-S116118), 2026-11-22. Base `27d80aa`; SIMPLE pin
`3a595f42f`; GFortran 16.2, mlx-c 0.8.0 / MLX 0.32.4 (Homebrew). The run carried out Phase 0, Phase 4, and
arun's phase 5 (plan Phases 5 and 5b). Nothing was committed. Every changed file is in the working tree,
inside the plan's file table. The plan's Progress section holds the detail (one entry per phase, and the
5a and 5b-a calibration entries); this report is the reading guide.

## 1. What changed, phase by phase

| phase | diff | what |
| --- | --- | --- |
| 0 | `/Users/elmlundho/agent_work/arun/mlxf_m1/review/phase_0.diff` | No source change. The baseline: base trees and gates, SIMPLE's suites at the pin (`block_prod`, `check`, `fills`, `neigh`, `shiftmap`), the case file and the shift-map grid. Plan Progress and history only. |
| 4 | `/Users/elmlundho/agent_work/arun/mlxf_m1/review/phase_4.diff` | `polar_table`, the test-only scoring workspace (`src/test/mlxf_kernel_polar_table{,_lifecycle,_score}.f90`) and its tester. Area `kernels` (sub-suite `polar_table`), CTest budget 8. `src/test/mlxf_test_defs.f90` with the frozen 4a pair. Rule `defs` widened to the test defs module. Testing rule: fixtures computed in double and rounded once. |
| 5, 5b | `/Users/elmlundho/agent_work/arun/mlxf_m1/review/phase_5.diff` | Phase 5: `bench_polar_table` (`accuracy`, `time`, `profile`, `overlap`, `stream`); the shared oracle module `mlxf_kernel_polar_oracle.f90`; the registry's `BENCHES` table and `bench_` dispatch; the 5a block pair frozen; formulation B (real GEMM of packed parts) with a compiled draw tail kept, A and the uncompiled tail removed, C kept for Phase 6. Phase 5b: the shift-map submodule `mlxf_kernel_polar_table_shiftmap.f90` and its tester (sub-suite `polar_shiftmap`), the frozen caps, the mode `suite=shiftmap`, the policy paragraphs, and the examples' Progress. |

## 2. Decisions taken under delegation, and where they are recorded

Each phase's Progress entry has a "Decisions taken under delegation" list. In short:

- **Phase 0:**
  - run directories and summarisers;
  - SIMPLE runs wait on other processes' CPU as well as the load;
  - `check`'s third repeat skipped (no timing in it);
  - the polar-case file also carries the shared-representative cases.
- **Phase 4 and 4a:**
  - the workspace's layout and names;
  - the fixture's tile plan;
  - `kernels` registered before the CPU-only tester;
  - the bound's definitions (max|d| per pair, validity judged away from the threshold, fixtures in double);
  - NaN distances invalid;
  - pure getters.
- **Phase 5 and 5a:**
  - the benchmark's design;
  - the shared oracle;
  - one queued evaluation per tile;
  - the tile plans (block 16 x 250, timing 64 x 250);
  - the 30 % rule applied per precision mode, with C kept for Phase 6;
  - the CPU team of the identity;
  - `submit` timed apart;
  - the 5a pair frozen from the Debug value.
- **Phase 5b and 5b-a** (Progress entries "Phase 5b-a" and "Phase 5b"):
  - the workspace's map types and names;
  - the fixtures' shapes and the oracle;
  - the evidence's normaliser over every cell, rotations included (SIMPLE's);
  - the formulation kept after the calibration (section 3);
  - the tile of pairs of the benchmark;
  - the bench's own columns.

The owner's rulings applied (R1: Phase 5 and 5b in one arun phase; fence rows; s and f unmeasured; PorF and
exp_gate profiles unavailable) are in `doc/history/2026-11.md`.

## 3. Deviations from the plan, and why

- **Shift-map timed runs repeated twice for memory.** The first two pairs of invocations reached a process
  footprint of 66 GB and 57 GB, above the 48 GB budget: the mode had no pre-allocation estimate, and MLX's
  cache kept the previous tile's buffers. The mode now estimates (counting the cache), prunes before
  allocation (screen at 1,024 pairs) and clears the cache per configuration. The third pair stayed at
  35 GB. The rates of the superseded pairs agree within 0.6 %, and they are kept as evidence.
- **Formulation change after the 5b-a calibration.** The calibrated shift-map contraction was one dense
  complex matmul with the folded weights: (nkb (K+1)) x (nalpha nrho), almost all zeros. In the benchmark
  it ran at 0.25 x SIMPLE on the window. It was replaced by one real GEMM per order, with the pairs beside
  the ring position as rows, then a real fold and the 2D transform. The caps are unchanged and judge the new
  form: the tester passes on both devices with errors within a few percent of the calibration's. The five
  negative controls were re-run on it and fail as before. Two further variants measured slower and were
  reverted: a compiled product, and split parts with a cos/sin direction transform.
- **Phase 5 and 5b were one arun phase** (ruling R1), with their own Progress entries.
- **Files added to the file table during the run**, before they were edited:
  - Phase 4: the two submodules and `references/testing.md` (spelled out for the fence);
  - Phase 5: the oracle module;
  - Phase 5b: `test/CMakeLists.txt` (the kernels comment).
- **Not available on this machine** (R1):
  - the production-equivalent CPU cost per map (decision 18), which needs a production profile;
  - the PorF and exp_gate per-map context costs;
  - s and f.

## 4. Evidence against the baseline (M2 Ultra; full precision; context only, the verdicts are Phase 6's)

| measure | SIMPLE at the pin, 24 threads | mlx-fortran, GPU | ratio |
| --- | --- | --- | --- |
| dense block scoring, case 2500_4 (pairs/s) | 2.30e6 (`block_prod`) | 1.05e7 (B + compiled tail, tile 64 x 250) | 4.55 |
| shift maps, window (maps/s) | 4.46e4 | 2.59e4 (tile 1,024 pairs) | 0.58 |
| shift maps, screen (maps/s) | 7.54e3 | 8.40e3 (tile 256 pairs) | 1.11 |

The ratios take the slower GPU run over the faster SIMPLE run. The shift maps' preparation (references 1.4 to
1.6 s, Bessel tables 0.4 s) is reported apart; the copy-out, under 1 ms, is inside the timing. The MLX peak is
18 GB and the process footprint 35 GB.

Accuracy gates:

- Polar table: the 64,000-pair block's row error is 1.16e-6 on the GPU (B) against the bound 1.45e-6, with
  0 minimising rotations differing.
- Shift maps: map error at most 5.1e-7 normalised L2 against the cap 1e-4, and evidence and width errors at
  most 1.3e-6.

Base gates are unchanged: zero warnings in Debug and Release, the fast gate 8 of 8, the leak gate exact, and
`check_tree` passes.

## 5. Left open for the maintainer

- **The verdicts** of decisions 14 and 18 are Phase 6's, on the M5 Ultra.
- **Accelerated mode:** C is the candidate (gated, kept in code).
- **Shift maps.** The construction is bandwidth-bound on the order-expanded product: about 31 µs per map on
  the window and about 86 µs on the screen. The construction-breakdown table in the Phase 5b Progress entry
  has the steps. A form that shifts the particle once per particle, not once per pair, is the next lever.
  It needs a phase-corrected transform; not attempted.
- **Findings against the examples note:**
  - the flat-likelihood evidence is -T L under SIMPLE's normaliser, not log(Nrot) - T L;
  - the tail rule keeps more orders than SIMPLE's `JTOL` (K 21 against 16, and 41 against 32);
  - `width_cutoff` is not implemented.
- **Two slots hide about 1 % on the dense table**, because the submitting thread is busy throughout. A
  submission thread or a fused graph is the lever.
- **Earlier findings** (Phase 4 and 5 entries):
  - section 6's ring-oracle form for seed-bank particles;
  - validity judged in float32 against SIMPLE's float64;
  - the fixture-in-double rule, which has no reading check.
- **Housekeeping:** the scientific examples' dry-run evidence in `/private/tmp` (an earlier, interactive
  note).
