# Implementation notes

Status reviewed on 2026-11-24 at `3a13403`, after the roadmap's rulings. `planned/` contains active contracts
and unfinished work; `completed/` contains delivered records and reviews. A completed batch does not close its parent milestone.

## Active work

| Note | Remaining work |
| --- | --- |
| [Roadmap](planned/mlxf_roadmap.md) | Ruled 2026-11-24: the priority ranking and the plan that owns each item. Start here. Decision 12 (the dense-driver baseline) is approved; decisions 14 and 15 (from [the review](planned/mlxf_roadmap_review.md)) stand as recommended; decision 13 (what K4's maps must agree with) awaits ruling |
| [Kernel families](planned/mlxf_kernel_families.md) | Milestone 2's design note: the toy kernels (polar matching, 3D Fourier gather and scatter, the PCG solve), deliverables K1 to K8; each needs its plan |
| [K1, the fused tail](planned/mlxf_kernel_k1.md) | Delivered 2026-11-25, kept by the maintainer's ruling (run `mlxf_kernel_k1`, M5; [report](completed/mlxf_kernel_k1_report.md)): the dense score's distances and draw as a custom Metal kernel beside the compiled graph tail, 1.65 to 1.80 times its rate, selectable, the default `graph` |
| [K2, the polar projection](planned/mlxf_kernel_k2.md) | Delivered 2026-11-25 (run `mlxf_kernel_k2`, M5; [report](completed/mlxf_kernel_k2_report.md)): a toy `projector` with `fproject_polar_batch_opt`; the fused gather kept (24 times the graph form's driver at one process, 5 to 6 at three), the device route into family A kept (32 to 35 times the host route's chain); the protected-update probe's outcome C by the letter, B by the diagnosis, a ruling for K6 |
| [K8, the PCG solve](planned/mlxf_kernel_k8.md) | Planned 2026-11-25, awaits the rulings and go (run `mlxf_kernel_k8`, M5): a toy `reconstructor_pcg` with `pcg_solve` from the raw accumulators to the shipped map, judged against the host oracles iterate by iterate and against Cholesky, timed alone at N = 160 and 256 |
| [Release hardening](planned/mlxf_release_hardening.md) | Planned 2026-11-25 (roadmap rank 2b, after K2; run `mlxf_release_hardening`, M5): the installed package as the artifact under test from a clean snapshot, the mlx-c version in the package config, a CPU-only MLX for pull-request feedback, the dtype table and quickstart with tested examples, CONTRIBUTING, ABI checks; ruled 2026-11-25 (all seven as recommended), runs after K2 |
| [dell2 bring-up](planned/mlxf_dell2_bringup.md) | Done on dell2, 2026-11-24: arun works end to end, the static gate passes under Linux, plain Fortran builds, the library cannot; moves to `completed/` once read |
| [Host oracles](planned/mlxf_oracles.md), [report](completed/mlxf_oracles_report.md) | Delivered on dell2, 2026-11-24 (run `mlxf_oracles`): `mlxf_oracle_dft`, `mlxf_oracle_projection` (K2, K6) and `mlxf_oracle_pcg` (K8), self-checked against closed forms and explicit constructions, built without a warning on the Mac under GNU Fortran 16.2. A review against SIMPLE's source found no internal error and six places where SIMPLE differs from the examples note they follow (the plan's last Progress entry); [Host oracles III](planned/mlxf_oracles3.md) adds SIMPLE's forms before K6 and K8 are planned. Awaits the maintainer's read |
| [Host oracles II](planned/mlxf_oracles2.md), [report](completed/mlxf_oracles2_report.md) | Delivered 2026-11-24, in the session on the Mac: `mlxf_oracle_polar_objfun` (the Euclidean loss, SIMPLE's two correlations and the reductions over references, K7), `mlxf_oracle_polar_shiftmap` (the grid, the direct cell, the truncated Bessel form, the mode and the width, K4) and `mlxf_oracle_pose` (the quadratic gather, both objectives with gradient and matrix, a reference solve, K5). Gradients and matrices are held to finite differences; no formula of its section 9 was contradicted. The distances and the shift-map cells agree with the existing polar oracle and the shift-map tester's evaluation to rounding. Not compared with SIMPLE's own numbers. Awaits the maintainer's read |
| [Host oracles III](planned/mlxf_oracles3.md), [report](completed/mlxf_oracles3_report.md) | Delivered 2026-11-24, in the session on the Mac (a launch on dell2 needed a commit that could not be made): `mlxf_oracle_gridding` (SIMPLE's gridding insertion, compression and density correction, K6), `mlxf_oracle_recon_pcg` (the lattice insertion, the masked operator, SIMPLE's preconditioner and solve, K8), SIMPLE's index map at the grid's edge and two repaired checks in `mlxf_oracle_projection`. Self-checked against dense constructions, every check shown able to fail; three contested choices read in SIMPLE at the review, one corrected. Not compared with SIMPLE's own numbers. Awaits the maintainer's read |
| [Toy architecture](planned/mlxf_toy_architecture.md), [report](completed/mlxf_toy_architecture_report.md) | The roadmap's rank 0b, delivered on the M5 Ultra, 2026-11-24 (run `mlxf_toy_arch`): the polar toy is a miniature of SIMPLE's `polarft_calc` with the driver `eul_prob_tab`, the mirror ledger and rule `mirror`; every result identical to the base; the dense-driver baseline at 1 and 3 part processes before and after (6 do not fit the memory). Awaits the maintainer's read of the architecture and of the report's open points; the plan then moves to `completed/` |
| [M5 preparation follow-up](planned/mlxf_m5_preparation.md) | Actual launch-spec/comparator audit and combined validation after parity Phase 3 |
| [mlx-c parity](planned/mlxf_mlxc_parity.md), [report of Phases 2–3](completed/mlxf_mlxc_parity_report.md) | Phases 2 and 3 delivered on the M5 Ultra, 2026-11-24 (run `mlxf_parity`): 146 functions public, 128 lines pending; the API hold released by Hans the same day. Next the kernels' wrappers (decisions 27 and 28: Phase 10, run `mlxf_parity_wrappers`, configured; it starts when the toy refactoring lands), then Phases 4–9 |
| [Scientific examples](planned/mlxf_scientific_examples.md) | Re-scoped by the kernel families: its example 3 and PCG fixtures stay the design basis; the filter bank is deferred; tutorials follow the kernels |
| [Fusing roadmap](planned/mlxf_fusing_note.md) | The M5 profile of the Fourier-Bessel maps (history); its direction is now the roadmap's and family A's |

## Completed work

| Record | Delivered scope |
| --- | --- |
| [Code quality review](completed/mlxf_quality_review.md) | Reviewed 2026-11-25 at `c6ea867` against local MLX and mlx-c: five reproduced findings remain open; Debug/Release CPU/Metal validation and its limits recorded |
| [Core design](completed/mlxf_design.md), [report](completed/mlxf_design_report.md) | Core/handle model; original numbered design decisions |
| [Milestone 1](completed/mlxf_milestone1.md), [M5 run](completed/mlxf_m1_m5.md), [report](completed/mlxf_milestone1_report.md) | Closed 2026-11-24: dense scoring at 4.69 times SIMPLE's 30-thread rate, Fourier-Bessel maps at 0.971 and 0.683 (standalone rates); failed experiments removed |
| [M2 milestone record](completed/mlxf_milestone1_m2.md), [M2 report](completed/mlxf_milestone1_m2_report.md) | Phases 0–5b, review fixes and Phase 5c implementation/validation; performance exit still open |
| [CI/setup/compiler/planner work](completed/mlxf_m1_codex.md) | Completed side work, with original evidence limitations retained |
| [Laptop preparation](completed/mlxf_m5_preparation.md), [report](completed/mlxf_m5_preparation_report.md) | Stronger tests, consumer packaging, host references and local launch preparation |
| [Parity Phases 0–1](completed/mlxf_mlxc_parity_phase1.md) | Ledger/probes, elementwise wrappers, calibration and continuing-run rulings |
| [Scientific preparation](completed/mlxf_scientific_examples_preparation.md), [review](completed/mlxf_scientific_examples_review.md) | Design review, example-1 design record and independent host-reference evidence |

The active paths and numbered decisions remain stable for run tooling. The parity plan retains the
completion headings consumed by its static ledger check; detailed evidence is in the completed record.
Historical observations have not been revalidated by moving these documents. Benchmarks remain deferred.
