# Implementation notes

Status reviewed on 2026-11-24 at `3a13403`, after the roadmap's rulings. `planned/` contains active contracts
and unfinished work; `completed/` contains delivered records and reviews. A completed batch does not close its parent milestone.

## Active work

| Note | Remaining work |
| --- | --- |
| [Roadmap](planned/mlxf_roadmap.md) | Ruled 2026-11-24: the priority ranking and the plan that owns each item. Start here. Decision 12 (the dense-driver baseline) is approved; decisions 13 to 15 (from [the review](planned/mlxf_roadmap_review.md)) await ruling |
| [Kernel families](planned/mlxf_kernel_families.md) | Milestone 2's design note: the toy kernels (polar matching, 3D Fourier gather and scatter, the PCG solve), deliverables K1 to K8; each needs its plan |
| [dell2 bring-up](planned/mlxf_dell2_bringup.md) | Planned: one phase of probes before any work is sent to dell2 (arun end to end, the static gate under Linux, plain Fortran without MLX) |
| [M5 preparation follow-up](planned/mlxf_m5_preparation.md) | Actual launch-spec/comparator audit and combined validation after parity Phase 3 |
| [mlx-c parity](planned/mlxf_mlxc_parity.md) | Phases 2–9 on the M5 Ultra; Phase 3 API hold unchanged; then the kernels' wrappers first (its decisions 26 and 27); Phases 0–1 delivered |
| [Scientific examples](planned/mlxf_scientific_examples.md) | Re-scoped by the kernel families: its example 3 and PCG fixtures stay the design basis; the filter bank is deferred; tutorials follow the kernels |
| [Fusing roadmap](planned/mlxf_fusing_note.md) | The M5 profile of the Fourier-Bessel maps (history); its direction is now the roadmap's and family A's |

## Completed work

| Record | Delivered scope |
| --- | --- |
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
