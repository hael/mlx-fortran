# Report: the review's fixes, then the toys in the shape of SIMPLE's integration (run `mlxf_toy_seam`)

Run on the M5 Ultra on 2026-11-26, 01:09 to 03:30 (stopped from 02:49 to 02:52), in the session, in a scratch
copy of the repository at `6f1af0d` (clean). Plan: [`mlxf_toy_seam.md`](../planned/mlxf_toy_seam.md), whose Progress has one entry per
phase with every log's path. Phases 0, 1, 2, 3, 5 and 4 ran in that order, each to its exit. **Phase 6 stopped
before any edit at 02:49, on section 7, was ruled in the session (R1 to R6, below), and was then carried to its
exit with Phase 7.** SIMPLE read at `d354efee2`. Nothing is committed. Evidence: the run's
`scratch/keep/phase{0..7}/`; the journal is the run's `state/journal.md`.

**The rulings.** R1 to R6 of the run's `spec/rulings.md` were taken in the session on 2026-11-26 under the
maintainer's go ("Yes, go"), on the run's own recommendations at the Phase 6 stop. Each stands as recommended and
is open to the maintainer's review. Section 6 lists what they decided.

## 1. What was learned

**All three toys have the shape, and the device route did not move.** The polar calculator with its driver, the
projector with its batch projector and the reconstructor with its engine are 11 host files (with the opaque
type's module) that import no MLX name, 7 glue submodules, and device modules whose arithmetic did not change.
The seam ledger has no `pending` line. After Phases 1, 3, 5, 4 and 6 the eleven identity invocations (the polar
digests on both devices and both tails, the shift maps, the projector's banks and chains, the reconstruction's
maps and histories) equal the base byte for byte; no case was run twice.

**The reconstructor could not take the shape as decided, and the stop was the plan's.** Five public, mirrored
bindings of `reconstructor_pcg` (`mask_mul`, `apply_normal`, `apply_normal_kernel`, `apply_precond`,
`dot_real_volume`) took and returned `type(mlx_array)`, and a binding's interface stands in the module of its
type. SIMPLE's own five take host arrays. Under R1 the toy's five now do too, which removed a declared
difference: each is a round trip to the device, and the solve goes round them, through the device forms in the
glue, so its bytes are K8's. The testers and the benchmark, which need device vectors without a host round trip,
take the reconstructor's operator as one opaque object.

**The five host forms are held to their device forms, byte for byte.** Ten new checks per device: each host
form's result against the device form's brought to the host, and each one's refusal on the host backend. A
defect planted in each of the five glue twins fails its own check. The first form of the kernel's check could
not tell a twin that applied the mask (on an assembly without a support the two operators are one); it was
replaced before the exit by one that can (the run's decision 30).

**The polar toy runs with MLX switched off, and in a build that has no MLX.** `score_block_posterior` on the
host backend is a miniature of SIMPLE's block kernel in single precision, and `fill_tab_range` has SIMPLE's two
shapes. At its first run, with nothing tuned, the host route met the bounds the MLX backend's fixture has
(4.794e-7 of a row's largest valid |d|):

| Gate (decision 17) | Seed 1 | Seed 2 | Seed 3 |
| --- | --- | --- | --- |
| host rows against a ring oracle in double precision (*measured*) | 2.264e-7 | 2.321e-7 | 2.770e-7 |
| minimising rotations off, entries of other validity, draws off their own rows (of 1,760 pairs) | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| a team of four against one thread | equal bytes | equal bytes | equal bytes |
| the fill's two branches, rows (CPU device; GPU) | 2.819e-7; 2.819e-7 | 2.845e-7; 2.825e-7 | 3.164e-7; 2.825e-7 |

The off-state project compiles the 18 host and glue files with the library's flags, no path to its modules and no
link to it. Its program's table equals `mlxf_test_exec`'s byte for byte (5,280 entries, GNU Fortran 16.2.0,
Release), and every class refuses the MLX backend there with "built without MLX".

**The classes' host builds are not independent.** The calculator's parent imports the projector's module (the
type of `vol_pad`) and its core imports the batch projector, so the calculator compiles without the library only
when the projector's files are host files too. Phase 5 therefore ran before Phase 4.

**A mirrored record and its device engine cannot share a module.** `pcg_solver_outcome` is a dummy of the host
`solve_accum`; `pcg_solve` works on device vectors. The engine is two modules beside `simple_pcg_solver` (R2),
and rule `mirror` accepts the second only because the seam ledger classes it as device.

**The review's four findings are closed, each with a test that fails without its fix.** The base's Release fast
gate failed once in 20 runs at the lifecycle assertion (F4); with the fix it passed 20 of 20, twice. Rule `nanmax`
now reads scalar accumulations; it found 112 statements under `src/test` (the plan counted 107 lines), all
converted, and 30 more in five testers under `src/core`, which this run may not edit: they are in a ledger that
may only shrink.

**The compilers.** A scalar `class(device_work), allocatable` component is finalized at scope exit; an array one
is not, because a rank-1 array has no matching scalar `final` procedure (the standard's rule). That is the case
the explicit `kill` of decision 3 covers, and it suffices. GNU Fortran 16.2.0 and 14.4.0 both refuse a submodule's
own procedure that has the name of a private procedure of its module ("already defined"; a probe, either order),
so the glue's clock has its own name; whether the standard allows it was not settled, and no compiler-issue entry
was made. GNU Fortran 14.4.0 builds and runs the off-state project; its table differs from 16.2's in 658 of
5,280 distances' bits and in no rotation (Phase 4; with the reconstructor's files its table is the same).

## 2. What changed, phase by phase

| Phase | What | Files |
| --- | --- | --- |
| 0 | the base measured: counts, 11 identity invocations twice, three rates twice, three probes with two compilers | the plan |
| 1 | F4 (synchronized samples), F1 (`history_errors`, `nan_max`, rule `nanmax`'s scalar form, 112 conversions), F3 (the cache key), F2 (the refusal), each with its test and negative control | 27 changed |
| 2 | `device_work`, the seam ledger and rule `seam` with nine plants, `USE_MLX`, the off-state project and its script, sub-suite `seam` | 7 new, 6 changed |
| 3 | the calculator: opaque `ws(:)`, `l_mlx`, four glue submodules, fifteen glue procedures | 4 new, 11 changed |
| 5 | the projector and the batch projector: glue (eleven procedures), the opaque bank of the hand-off, decision 10's refusal | 2 new, 9 changed |
| 4 | the host kernel, the fill's two branches, sub-suite `polarft_host`, the off-state table | 2 new, 12 changed |
| 6 | stopped; ruled; then the engine's two halves, the reconstructor's host file and glue (eighteen procedures), the five on host arrays, the opaque operator, R1's checks, rules `mirror` and `seam` | 2 new, 14 changed |
| 7 | the toy policy's section 8, the kernel-families note, the how-to's tables, the test policy, the roadmap, the history, the index, the README's sentence, this report | 8 changed, and this report |

In all: 50 files changed, 18 new (14 under `src/test` and `scripts`, the three of `test/offstate/`, and
this report), none renamed, none deleted. `unit_kernels` went from 1,732 to 1,955: +50 in Phase 1 (`projector` 96
to 100, `projector_chain` 75 to 99, `pcg_solver` 84 to 86, `reconstructor_pcg` 152 to 172), `seam` 88,
`polarft_host` 65, and R1's 20 in `reconstructor_pcg`. The CTest budget stayed 9. Nothing under `src/core` or
`src/defs` changed.

## 3. Decisions taken under delegation

Numbered as in the plan's Progress, where each has its reason.

| No. | Phase | Decision |
| --- | --- | --- |
| 1 | 0 | the reconstruction's judged rate is one number: four assemblies over the sum of the four rows' best times |
| 2 | 0 | `passes=9` for the two launcher benchmarks, frozen before any judged run |
| 3, 4 | 0 | a shift-map identity case on a grid written for the run; the accuracy suites join the identity cases |
| 5 | 0 | rule `nanmax`'s scalar form keeps the rule's scope, with a ledger for the five testers under `src/core` |
| 6 | 1 | F2: the route is fixed from the first memoization until `kill` and `new`; "set anew" has no reachable state |
| 7, 8 | 1 | longer `max` lists become `nan_maxval([...])`; two more controls; `pcg_solver` checks the histories' soundness |
| 9 | 2 | the host table is written as hexadecimal lines of standard output, compared by the script |
| 10 | 2 | rule `arity` exempts the `_mlx` twin of a mirrored procedure, and nothing else |
| 11, 12 | 2 | the off-state project takes flags and sources from the repository; a file stays `pending` until its phase |
| 13 | 3 | **Phase 5 before Phase 4** (the dependency above; confirmed by R5) |
| 14, 15 | 3 | on the host backend the device route, the shift maps and blocks in flight are refused; `kill` needs no glue |
| 16 | 5 | the backend reaches `projector%new` through an optional last dummy `params` (R5: stays, for the maintainer's read) |
| 17 | 5 | the projector's message lives in the projector; the workspace's unused `set_message` is deleted |
| 18, 19 | 5 | the batch projector guards on `allocated(vol_pad%ws)`; the bank's wrong type has no test |
| 20 | 4 | **a file outside the table,** `src/test/mlxf_polarft_host_fixture.f90`, its row added first (confirmed by R5) |
| 21 to 24 | 4 | the host kernel takes any reference list; its own analytic fixture; the fill's backend is the driver's parameters'; single precision throughout |
| 25 | 6 | a device module `<stem>_mlx` may import `<stem>`, its own host half, and no other host module of a toy class |
| 26 | 6 | `pcg_operator` has a default `kill` that releases nothing (an addition), so the engine tester's two operators keep their code |
| 27 | 6 | `self` is `intent(inout)` in the five, so that a refusal leaves its message (SIMPLE's `mask_mul` and `dot_real_volume` are pure) |
| 28 | 6 | the addition is `get_pcg_operator`; testers and benchmark reach the device forms through three small functions each |
| 29 | 6 | two glue procedures for `end_accum`; the rule of a given-up solve is one private `nopass` binding, `solve_stopped` |
| 30 | 6 | the kernel's check clears the support to reach its device form, and requires a difference from the masked operator's |
| 31 | 6 | one refusal check per procedure: ten new checks per device |
| 32 | 6 | `reconstructor_pcg%kill` returns the lattice's scalars to their initial values |
| 33 | 6 | no wrong-type check for the reconstructor: its `ws` is private, as SIMPLE's state is |

## 4. Deviations from the plan

- **The order of the phases:** 0, 1, 2, 3, 5, 4, 6, 7 (decision 13). Decision 18's order of the classes is kept.
- **The stop and the rulings.** Phase 6 stopped before any edit; R1 changes the five's dummies to SIMPLE's (the
  plan's decisions 4 and 12 could not both hold), R2 replaces decision 12's rename, R3 widens a row of the file
  table, R4 restates the phase's exit for the added checks.
- **Files outside the table:** `src/test/mlxf_polarft_host_fixture.f90` (row added in Phase 4);
  `src/test/mlxf_toy_pcg_solver_mlx.f90` is a new file under R2 where the table had a rename (row added at the
  resumption). Within the table but beyond a row's words: `scripts/toy_mirror.txt` in Phase 2 (the opaque type's
  two lines; its row says 3 to 6); `mlxf_toy_projector_workspace.f90` gained the type `projector_bank` and lost
  `set_message` (its row says "extends `device_work`"); `scripts/release_gate.sh` has its one line and three lines
  of its header; `scripts/check_toy_offstate.sh` was corrected in Phase 6 (a relative `--exec`; its row has the
  word).
- **Counts that moved under a ruling:** `reconstructor_pcg` 172 to 192 (R1's checks, R4); `seam` 66 to 88.
- **The Progress headers of Phases 5 and 4 and of the stop** carried times a few minutes off; they are corrected
  to the journal's and the logs' file times.
- **The census:** F4's count was 6 more files under `src/test`, not 8; F1's 107 lines are 112 statements.
- **Expected and not found:** F4 in Phase 0's two gate runs (it showed in the 20-run series, once); a compiler
  defect in the probes; a need for double precision in the host kernel.
- **Found and not expected:** the phase order's dependency; the reconstructor's stop; two flaws of the run's own
  plant runner (files restored with old times; `make` comparing times by the second), which contaminated one
  planted run. It was run again, and every build-and-run plant of Phases 1, 3 and 5 was run again with the
  corrected runner and fails as recorded. A defect of `scripts/check_toy_offstate.sh`, found by the session's
  rebuild of the stopped state and corrected in Phase 6.

## 5. Evidence against the baseline

- **Builds:** every phase ended with Debug and Release from scratch with `MLXF_WERROR=ON`, 0 warnings, the fast
  gate 9 of 9, `scripts/check_tree.sh` and `scripts/check_embed.sh` passing, from Phase 2 on
  `scripts/check_toy_offstate.sh`; both formatters run on every touched Fortran file
  (`scratch/keep/phase{1..6}/exit/summary.txt`, `scratch/keep/final2/exit/summary.txt`).
- **Counts at the end** (*measured*, Debug and Release equal; `scratch/keep/final2/exit/`): `unit_core` 181 to 183
  (a property of the base: its sub-suite `registry` asserts once more per device when the allocator reuses an
  address, 35 to 37 over the run's gates), `unit_array` 193, `unit_ops`
  2,462, `unit_linalg` 632, `unit_fft` 194, `unit_compile` 63, `unit_fast` 94, `unit_kernels` 1,955:
  `polarft_calc` 327, `polar_shiftmap` 794, `eul_prob_tab` 105, `polarft_tail` 55, `oracle_projection` 44,
  `projector` 100, `projector_chain` 99, `pcg_solver` 86, `reconstructor_pcg` 192, `seam` 88, `polarft_host` 65.
  Named-only, Release: `reconstructor_pcg_n32` 96 (168 s) at Phase 6's exit; `polar_shiftmap_accuracy` 48 at
  Phase 1's exit.
- **Decision 13:** `identity.txt` (57 lines, SHA-256 `7d8d7bfc...a77d5a`) equal to the base's after Phases 1, 3, 5,
  4 and 6; never rerun.
- **Decision 25:** the Release fast gate with `ctest --parallel 4`, 20 runs: the base 19 of 20; F4's fix alone 20
  of 20; Phase 1's final tree 20 of 20.
- **Decision 14, after Phase 6** (*measured*, two runs each, the load 1.3 to 3.3, nothing else running;
  `scratch/keep/phase6/timing_exit/`):

  | Benchmark | Base | After Phase 6 (run a, run b) | Change | Floor (2 % below) | |
  | --- | --- | --- | --- | --- | --- |
  | `bench_polar_table`, `2500_4`, graph tail (pairs/s) | 1.763595e7 | 1.764525e7 (1.76600e7, 1.76305e7) | +0.05 % | 1.728323e7 | holds |
  | `bench_projector`, fused, all directions (samples/s) | 1.408895e9 | 1.410675e9 (1.41247e9, 1.40888e9) | +0.13 % | 1.380717e9 | holds |
  | `bench_recon_pcg`, system P, n = 160 and 256 (assemblies/s) | 4.30710 | 4.29841 (4.24899, 4.34783) | -0.20 % | 4.22096 | holds |

  The reconstruction's two runs differ by 2.3 % (the row n = 160, F5: 0.1133 and 0.1033 s); the lower one is
  1.35 % below the base, above the floor. The launcher's rates step by the median's 0.1 ms.

  At the stop, before the reconstructor was touched, the three were +0.17 %, -0.88 % and +0.04 %.
- **Plants:** 46 planted defects and controls, each a patched copy built apart
  (`scratch/keep/phase*/plants/`): 7 in Phase 1, 12 in Phase 2 (two of them controls that pass), 2 in Phase 3, 3 in
  Phase 5, 7 in Phase 4, 15 in Phase 6 (one a control that passes); then 2 compile probes of the stop, and the
  reruns.
- **The release gate** with `--allow-dirty` passes on the final tree (72 s), its off-state line included.

## 6. Left open for the maintainer

**The rulings, for review** (taken in the session under the maintainer's go; each as the run recommended):

| Ruling | What it decided | What to look at |
| --- | --- | --- |
| R1 | the five operator procedures take SIMPLE's host arrays through guarded calls; the device forms are private in the glue; the operator is handed out as `class(device_work)`; ten new checks per device | `src/test/mlxf_toy_reconstructor_pcg.f90`, `_mlx.f90`; `test_host_forms` in the tester |
| R2 | the engine is a host module (the record) and a device module (`mlxf_toy_pcg_solver_mlx`); rule `mirror`'s exception for a device module | `scripts/check_rules.py` (`read_mirror`), `scripts/toy_mirror.txt` |
| R3 | 25 call sites in two testers and the benchmark use the opaque operator; no check changed | the three files' diffs |
| R4 | the exit restated: 86, 192 (172 + 20), 96; `pending` 0; decision 14 judged | sections 2 and 5 |
| R5 | Phase 5 before Phase 4 and the fixture file stand | the plan's Progress |
| R6 | Phase 7 and this report | |

**To confirm or change:**
- the optional `params` dummy of `projector%new` (decision 16) and now of `reconstructor_pcg%new`, against another
  way to hand a class its backend (SIMPLE's classes read their parameters object without a dummy);
- the name `l_mlx` for SIMPLE's parameter (the plan left it to the maintainer);
- `self` as `intent(inout)` in the five (decision 27): the alternative is `intent(in)` as SIMPLE's two pure ones,
  with a refusal that leaves no message;
- the device engine's import of its host half (decision 25), which is an exception written into rule `seam`;
- whether the plan's next version puts the projector before the host route.

**A follow-up, not this run's:** the 30 scalar `max` accumulations in five testers under `src/core`
(`NANMAX_LEDGER` of `scripts/check_rules.py`), for a change that may edit `src/core`.

**Reported, not gated:** the off-state build takes 1 to 3 s per build type; the probes' counts of finalizations
(Phase 0); GNU Fortran 14.4.0's results; in an integration the reconstructor's five would keep SIMPLE's host
bodies and only the solve would cross (the toy has no host route, so its five cross).

**Not verified:** the host route on Linux or on a machine without MLX (the off-state project was built on this
Mac only, where the library is absent from its build but present on the machine); the timed benchmarks at more
than one process; `polar_shiftmap_accuracy` after Phase 1 (it ran once, at Phase 1's exit: 48 checks); the glue's
refusal of a device state of another type for the reconstructor (decision 33) and for the projector's bank
(decision 19); the cost of the five's round trips (no caller times them).

**Proposals, not edited.**
- The agent-runs skill could say that an incremental rebuild after a file is changed back needs a second's wait
  and a fresh file time (the run's plant runner met both).
- The how-to for plans could ask a plan that orders classes to check their modules' imports of one another, and
  a plan that moves procedures across a seam to list the public bindings whose dummies have the type that may not
  cross.
- `CLAUDE.md`, "Structure" or "The library's rules": one line on the three classes of a toy file, the two ledgers
  and `scripts/check_toy_offstate.sh`; the skill `mlxf-modern-fortran`'s `references/testing.md`: the seam's
  sub-suites.

## 7. A commit message

```
Review fixes F1 to F4; the toys in the shape of SIMPLE's integration

The follow-up review's four findings are fixed, each with a test that
fails without its fix: the PCG history comparator refuses a missing,
short or non-finite history (F1; nan_max in mlxf_test_reduce, rule nanmax
now reads x = max(x, abs(...)), 112 statements converted, 30 in testers
under src/core held by a ledger); set_ref_route refuses a change once a
reference is memoized (F2); the padded box is in the fused gather's cache
key (F3); the lifecycle test synchronizes before both memory samples
(F4; the Release fast gate 20 of 20 where the base gave 19).

The three toys (the polar calculator with its driver, the projector with
its batch projector, the PCG reconstructor with its engine) take three
classes of file: host files that import no MLX name, glue submodules
<name>_mlx that hold their bodies under USE_MLX with stubs beside them,
and device modules. A class holds its device state as
class(device_work), allocatable, and kills every element before it
deallocates. The backend is chosen at new (parameters%l_mlx).

The polar toy gains a host route: score_block_posterior is a miniature
of SIMPLE's block kernel, and fill_tab_range scores its blocks from
inside a parallel region on the host backend and queues them from one
thread on the MLX backend. The projector and the reconstructor have no
host route and refuse the host backend. The projected bank and the
reconstructor's operator cross as opaque objects.

The reconstructor's five operator procedures (mask_mul, apply_normal,
apply_normal_kernel, apply_precond, dot_real_volume) take and return
SIMPLE's host arrays; each is a round trip to the device, held to its
device form byte for byte. The solve goes through the device forms in
the glue, unchanged. The engine is the host module mlxf_toy_pcg_solver
(the record pcg_solver_outcome) and the device module
mlxf_toy_pcg_solver_mlx (pcg_operator, pcg_solve); rule mirror accepts a
module <stem>_mlx beside simple_<stem> when the seam ledger classes it
as device.

New files: src/test/mlxf_toy_device_work.f90 (the opaque type),
src/test/mlxf_toy_polarft_core_mlx.f90, mlxf_toy_polarft_memo_mlx.f90,
mlxf_toy_polarft_block_mlx.f90, mlxf_toy_polarft_shiftmap_mlx.f90 (the
calculator's glue), src/test/mlxf_toy_projector_mlx.f90,
mlxf_toy_projector_pft_batch_mlx.f90 (the projector's glue),
src/test/mlxf_toy_reconstructor_pcg_mlx.f90 (the reconstructor's glue),
src/test/mlxf_toy_pcg_solver_mlx.f90 (the device engine),
src/test/mlxf_polarft_host_fixture.f90 (the host route's fixture),
src/test/mlxf_toy_seam_tester.f90 (sub-suite seam),
src/test/mlxf_toy_polarft_host_tester.f90 (sub-suite polarft_host),
scripts/toy_seam.txt (the seam ledger, rule seam),
scripts/check_toy_offstate.sh, test/offstate/CMakeLists.txt,
test/offstate/mlxf_offstate_exec.f90, test/offstate/offstate.inf (the
build without MLX), doc/implementation_notes/completed/
mlxf_toy_seam_report.md (the report).

The off-state project compiles the 18 host and glue files without the
library, and its table of the host route equals mlxf_test_exec's byte
for byte; the release gate runs it. unit_kernels 1,732 to 1,955; the
seam ledger has no pending line; the identity cases equal the base after
every phase; the three
benchmarks within 0.2 % of the base.

The Phase 6 stop was ruled in the session under the maintainer's go
(R1 to R6 in the plan's Progress), open to his review.

Run mlxf_toy_seam; plan doc/implementation_notes/planned/mlxf_toy_seam.md.
```
