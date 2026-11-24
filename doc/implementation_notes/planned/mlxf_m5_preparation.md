# M5 preparation: remaining launch audit and parity integration

Status, 2026-11-24: active follow-up. Local Phases 0–4 are delivered in `b99eb43`; this checkout includes
parity Phase 1 in `26387c1`, but not the final Phase 3 output. The external M5 launch audit and combined
integration validation remain open. The measured source stays `4706ecb`; no benchmark is authorized here.

The [completed laptop record](../completed/mlxf_m5_preparation.md) holds the original contract,
decisions 1–9, source hashes, command/artifact matrix and local validation. Its
[report](../completed/mlxf_m5_preparation_report.md) records the delivery and limitations. This file
retains the original active path and the unfinished phase numbers; completed implementation is not repeated.

## 1. Why

The stronger shiftmap tests, install package and independent host references are delivered. The remaining
work is to check the actual external run specification and reconcile the final parity output with those
changes. Neither was available at the laptop handoff, so their validation cannot be inferred from it.

## 2. Contract

- Preserve the M5 measurement baseline `4706ecb` and SIMPLE comparator
  `0a8b0903eee151700305399e8e3ff53c2c21caae`. Record the correctness supplement separately from the measured
  source and from the later packaging/parity tree.
- Keep all benchmarks deferred. This follow-up audits commands and runs bounded correctness/install
  gates after integration; it does not launch or modify the M5 run or a job on the M2 Ultra.
- Keep the frozen numerical bounds, existing architecture and one library/one unit-test executable.
  No kernel, wrapper or ownership redesign is part of the documentation handoff.
- The evidence root remains `~/agent_work/mlxf_m5_preparation/4706ecb/`. The local command matrix is in
  completed Phase 2; it is a dry-reviewed template, not proof of an executed or audited external run.

## 3. Decisions and rulings

Decisions 1–9 remain in the completed record, with their original numbers and scope.

10. (2026-11-24, Hans: move completed documentation; splitting allowed) Archive the delivered local
    preparation and report. Keep the actual launch audit and combined integration at this active path.
    This is a documentation split, not completion of either remaining gate.

## 4. Not in this follow-up

Reimplementing completed Phases 0–4; changing the M5 source/dependency pins; benchmarks; production SIMPLE
integration; new scientific device examples; Git mutations; remote autonomous-run changes.

## 5. Change types and gates

| Phase | Remaining work | Gate |
| --- | --- | --- |
| 2 | External launch-spec audit and comparator verification | Actual spec/path/checksum and verified inputs match the archived command matrix |
| 5 | Combined parity review, validation and final handoff | Recorded integrated source, Debug/Release correctness and isolated consumer checks |

## 6. Acceptance and stop conditions

Required for a pass: zero compiler warnings with `MLXF_WERROR=ON`; static and fast gates; observed CPU
and Metal results; both named shiftmap suites at unchanged caps; isolated CMake/pkg-config consumer
checks; evidence naming the actual integrated source and dependencies. A skipped GPU check is not a pass.

The original baseline's eight CTest entries may grow only through the separately authorized parity plan;
use its declared current budget at integration. Do not relax assertions or demand the old assertion count
after the deliberate test additions. Missing spec, comparator or final Phase 3 output leaves its specific
exit pending. A kernel defect or conflicting concurrent edit needs diagnosis outside this handoff scope.

## 7. Remaining phases

### Phase 2, finish the external launch audit

1. Obtain the actual `mlxf_m1_m5` specification; record its location/checksum and exact source base.
2. Verify the required SIMPLE revision and compare the real commands with completed Phase 2's matrix:
   dense scoring, both map grids, four graph combinations, tiles/memory pruning, requested outputs,
   measured FFTW plans, full CPU team, precision modes, repeats, source identity and artifact provenance.
3. Account for every mismatch in this Progress and the setup guide. The M5 run owner applies external
   corrections. Obtain/check the fresh same-machine case/grid inputs when the M5 baseline runs;
   do not manufacture them from another machine's measurements.
4. Keep the test-only supplement and its source proof distinct from the measured executable. Record
   NAX eligibility and actual dispatch as separate future observations.

Exit: the actual spec and comparator inputs are verified, or their absence remains explicitly pending.
Only the former supports launch readiness. No benchmark or remote run is started by this follow-up.

### Phase 5, integrate and close the preparation handoff

1. After Claude's Phase 3 hold, review its final diff together with the laptop delivery. Preserve both
   sets of changes; the owner performs Git integration. Reconcile the deferred README package paragraph
   recorded in completed Phase 5 with the parity API description and serialize shared history edits.
2. Record the integrated commit/diff. In separate Debug and Release build directories, build with GPU
   required and warnings as errors, run the static/fast gates, `polar_shiftmap` and
   `polar_shiftmap_accuracy` on both devices, and `scripts/check_install.sh` against both installs.
3. Record every result and any pending launch item. Produce a separate final follow-up report rather
   than overwrite the completed laptop report. The M5 measurement checkout remains unchanged.

Exit: combined review and validation are recorded and the launch-readiness status is explicit.
Close this follow-up only after its required launch audit and integration work are done. M5 measurements
and the milestone verdict remain owned by [milestone 1](mlxf_milestone1.md).

### File table

| File | Purpose | Phases |
| --- | --- | --- |
| `doc/implementation_notes/planned/mlxf_m5_preparation.md` | Remaining contract, audit and integration evidence | 2, 5 |
| `doc/how2s/how2set_up_dev.md` | Actual-spec/setup corrections if needed | 2 |
| `README.md` | Reconcile the delivered package paragraph after the parity hold | 5 |
| `doc/history/2026-11.md` | Serialized final delivery record | 5 |
| `doc/implementation_notes/completed/mlxf_m5_preparation_followup_report.md` | Final follow-up report at closure | 5 |

The external spec and evidence directories are inputs/artifacts, not authorization to edit an autonomous
run. Source changes outside this table are separately scoped fixes, not permission to alter its baseline.

## Progress

### Local preparation delivered, 2026-11-23

See the completed record/report for 1,364 strengthened shiftmap and 144 sampled-geometry assertions per
build across CPU/Metal, isolated package consumers, 247 host-reference checks, negative controls and
source hashes. These are historical observed results, not a new validation of the parity-integrated tree.

### Documentation split, 2026-11-24

Archived the completed laptop work and kept the unresolved launch audit and integration here. Parity
Phase 1 is committed; the final Phase 3 integration and actual external-spec audit are still pending.
No implementation, correctness run, benchmark or autonomous-run change was performed for this split.
