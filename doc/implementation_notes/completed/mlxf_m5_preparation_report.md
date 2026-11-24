# M5 preparation: laptop delivery

Archive disposition, 2026-11-24: the laptop delivery report is complete. The outstanding launch
audit and combined parity validation remain in [the active follow-up](../planned/mlxf_m5_preparation.md).
Archiving this report does not mark those checks passed.

Status, 2026-11-23: local Phases 0–4 validated on the M3 Pro; combined parity integration and the external
M5 launch audit remain open. The [completed laptop record](mlxf_m5_preparation.md) owns the original contract,
command matrix, source hashes and Progress. No benchmark or remote job was run.

## What was learned

The stronger shiftmap fixtures pass the unchanged `4706ecb` library on CPU and Metal, while each of the
three previously missed faults now fails assertions and exits 1 on each device. Candidate reuse causes
81 failures, wrong survivor temperatures 5, and omitted interior harmonics 41 plus 49 sampled-geometry
failures per device. The same frozen caps and exact lifecycle checks remain in force.

The library can be consumed from an isolated install using only `mlxf.mod` and `mlxf::mlxf`, with shared
mlx-c found transitively. Debug/Release, spaces in the install prefix, compiler refusal, private-module
exclusion and pkg-config linking all pass. A producer without OpenMP also passes without requiring it.

The independent host equations pass 247 checks at `1e-12`; maximum normalized error is `4.018729e-15`.
Six altered sources fail named checks. These are host references, not scientific device results or GPU
tolerance calibration.

The actual `mlxf_m1_m5` specification and SIMPLE `0a8b0903e` source are unavailable locally. The launch
matrix and setup corrections are delivered with that explicit finding; M5 launch readiness is open.

## Changes by phase

| Phase | Delivery | Repository files |
| --- | --- | ---: |
| 0 | Pinned baseline snapshot, hardware/toolchain manifest, Debug/Release correctness logs | Living plan; evidence external |
| 1 | Heterogeneous candidates/temperatures, diagonal survivor mask, broadband angular fixtures, non-vacuous modes | 1 tester, plus plan |
| 2 | Setup pins, supplementary correctness provenance, dry-reviewed command/artifact matrix and missing-input finding | 1 guide, plus plan |
| 3 | CMake config/export/version/pkg-config wiring, explicit outside consumer/check and consumer guide | 10 files, plus plan |
| 4 | Portable standard-library references and controls; scientific Progress evidence | 1 scientific note, plus plan; probes external |
| 5 | This report, serialized history and integration hold | Report/history/plan |

There are 16 distinct repository files in the delivery. Every path is in the plan's file table; no
library Fortran, kernel, benchmark, tolerance, shared test registry/definition, test CMake, parity plan,
binding policy or README was edited. No branch or git state change was made.

## Delegated choices

- Validate the exact measurement base through a source snapshot exported with read-only `git show`.
  The checkout already contained post-base fixes; measuring it as `4706ecb` would lose source identity.
- Keep packaging validation in separate `build_m5prep_current_*` directories. The baseline supplement's
  manifest proves all 121 other tracked baseline files unchanged; packaging does not enter that source.
- Use `CONFIG QUIET` with an actionable `_FOUND` failure in the repository consumer, to satisfy the
  mandatory `findpkg` rule. The user guide shows the usual downstream `CONFIG REQUIRED` form.
- Put explicit shared mlx-c link metadata in `Libs.private`: its Homebrew package has no pkg-config
  file. `--static` describes the Fortran archive's link requirements and does not statically link mlx-c.
- Reconstruct the missing old host probe; record analytic ideal-mode checks and rounded-input
  quantization corrections separately. Cholesky supplies the solve reference; no optional host PCG was
  needed. The plan's Phase 3/4 Progress records the reasons and results.

## Deviations and limits

The actual external specification could not be audited and its updated SIMPLE pin could not be inspected
on this laptop. Phase 2 explicitly permits delivery with that pending finding. Its source-checked parser
matrix identifies the historical `maps_per_s_t24` key, missing dense-row provenance and required sidecars.
It also records `arg_int`'s undefined `ios` read for an omitted key; its default result is initialized,
but the parser hygiene fix remains separate from the pinned benchmark source.
The matrix contains future commands only; no throughput smoke test was used to validate them.

Claude's parity Phases 1–3 run independently on the M2; their final output is not in this checkout.
Combined integration validation remained a handoff hold at delivery. On 2026-11-24 the completed local
record/report were archived, with the hold retained in [the active follow-up](../planned/mlxf_m5_preparation.md).
The separately available scientific-example pin `7ec7e2972` was used to verify its source anchors;
this does not substitute for the missing measurement comparator. No file outside the table changed.

## Evidence against the baseline

All evidence is under `~/agent_work/mlxf_m5_preparation/4706ecb/`, with exact commands, return codes,
source checksums and logs. The laptop is an 18-GB M3 Pro MacBook Pro, macOS 26.7.3; GFortran 16.2.0,
CMake 4.5.1, Python 3.12.2, MLX 0.32.4 and mlx-c 0.8.0. Observed GPU: Apple M3 Pro, `applegpu_g15s`.

| Check | Result |
| --- | --- |
| Original pinned Debug/Release static/fast gates | Pass; 8/8 CTest entries per build, zero compiler warnings |
| Original named shiftmap / accuracy suites | Pass; 1,308 / 144 checks across CPU and Metal per build |
| Strengthened pinned Debug/Release suites | Pass; 1,364 / 144 checks across CPU and Metal per build |
| Three fault controls on CPU/Metal | All rejected through assertions, exit 1 |
| Current-tree Debug/Release builds/gates/accuracy | Pass; 8/8 and 144 sampled-geometry checks, zero compiler warnings |
| Outside consumer, CMake and pkg-config | Pass on CPU/Metal for both builds, isolated prefixes with spaces |
| Compiler/private-module/broken-consumer controls | Intended refusals; broken consumer propagates exit 1 |
| OpenMP-disabled producer | Build and outside install checks pass; no OpenMP consumer flags |
| Host references / six fault controls | 247 pass / all controls rejected at their named assertions |

Final static, shell syntax, Markdown link/fence and whitespace checks pass. Final consumers were rerun
after the last script/program edits for Debug, Release and the OpenMP-disabled producer; all exit 0.

The test-only patch and source proof are `shiftmap-test-supplement.patch` and
`supplement-sources.json`; the plan records both SHA-256 values. Host references and their portable
manifest are in `host_references/`. No timing spread or speedup is reported because benchmarks were
explicitly deferred.

## Left open

- **Integration:** review Claude's final Phase 3 diff with this delivery, merge shared documentation by
  hand, then run combined Debug/Release fast, accuracy and consumer checks in separate builds.
- **Launch inputs:** obtain/checksum the actual M5 spec, verify SIMPLE `0a8b0903e`, reconcile commands
  against the matrix and generate fresh same-machine CPU case/grid files. Keep measured `4706ecb`
  separate from the correctness supplement and subsequent packaging/parity changes.
- **Reported, not gated here:** M5/NAX dispatch, throughput, tiles, overlap and memory verdicts belong
  to milestone 1. Scientific device implementation/calibration and production SIMPLE integration keep
  their existing holds. Full 3D FFT wrappers belong to parity Phase 5.

## Suggested commit message

```text
test: strengthen shiftmap regressions and prepare M5 consumers

Cover heterogeneous candidate tiles, survivor temperatures and broadband rings.
Export the Fortran package and verify isolated CMake/pkg-config consumers.
Record portable host references and the pending M5 launch/integration checks.
```
