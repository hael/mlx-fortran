# Codex beside run `mlxf_m1`: CI, the M5 Ultra bring-up, the gfortran reports, a fair FFTW comparator

Status, 2026-11-22: planned. Decision 6 was ruled by Hans the same day (Phase 4 goes ahead) and decision 2
was revised by him (he pushes Codex's work to GitHub). Base: the maintainer's commit that adds this plan, on
top of `0a1eec2`. SIMPLE pin: `3a595f42f928a366744094a28b62aeb6020099e4`, a working point for now
(decision 6). Supersedes: none.

Depends on:

- Phases 1 to 3 of `mlxf_milestone1.md` (validated: yes, Apple M3 Pro, 2026-11-22).
- Run `mlxf_m1` (Phases 0, 4, 5 and 5b of that plan) running on the M2 Ultra FWM-S116118 meanwhile
  (validated: no; launched after this plan is committed).
- The M5 Ultra, delivery expected 2026-11-25 (validated: no).

Written for Codex on a machine other than the M2 Ultra. That is the Apple M3 Pro of Phases 1 to 3 unless
Phase 0 records another.

## 1. Why

While run `mlxf_m1` builds the polar pipeline on the M2 Ultra, four pieces of work are open that need neither
that machine nor the files the run edits:

- **CI.** The workflow has never been seen running on GitHub's runners (`mlxf_milestone1.md`, "What the code
  check found"). It installs whatever `mlx-c` Homebrew ships that day.
- **The M5 Ultra's setup.** Run `mlxf_m1_m5` needs the M5 Ultra set up (milestone decision 6): GCC 16,
  CMake, the pinned pair MLX 0.32.4 and mlx-c 0.8.0, and SIMPLE's build dependencies. No written procedure
  exists yet, and a fresh `brew install` may no longer give the pinned pair.
- **The gfortran reports.** The five reports of `doc/compiler_issues/README.md` were written without access
  to GCC Bugzilla. Issue 4 may already be fixed on trunk (PR 110626). Milestone decision 9 has Hans file
  them.
- **The CPU comparator.** The verdict of milestone decisions 14 and 18 compares the GPU with SIMPLE's
  benchmark. Under the test executable's fixed seed, that benchmark plans its FFTs with `FFTW_ESTIMATE`;
  production plans with `FFTW_MEASURE` (`simple_polarft_memo.f90` and `simple_polarft_shiftmap.f90`, under
  `has_global_seed()`, at the pin). Decision 18 names this caveat without measuring it. If the gap is large,
  a "go" on the M5 Ultra could be the planner's doing.

This plan does those four, so that they are ready before run `mlxf_m1_m5`.

## 2. Contract

- **The run is not disturbed** (milestone decision 6). Codex edits no file the run may edit (section 4).
  It runs nothing on the M2 Ultra: no ssh, no job, no build, since the run's timed benchmarks need that
  machine idle. Codex's files are disjoint from the run's, so Hans's pushes of Codex's work during the run
  touch nothing the run edits (decision 2).
- **The house rules hold:** `AGENTS.md`, `CLAUDE.md`, `doc/architecture_principles.md`, and the skill
  `mlxf-modern-fortran` for any Fortran. In SIMPLE, they are SIMPLE's `AGENTS.md`/`CLAUDE.md` and its skills.
- **The pins hold:**
  - MLX 0.32.4 and mlx-c 0.8.0 stay installed on the Codex machine; no package there is upgraded,
    downgraded or unlinked.
  - The SIMPLE pin is read only, except on Phase 4's branch after its ruling.
- **No library behaviour changes.** The library is in the run's hands. Phase 1 changes the workflow, and
  touches dependency discovery only if needed.

## 3. Decisions and rulings

1. (2026-11-22) **Window and order.** Phases 0 to 4 run while run `mlxf_m1` runs, in this order. Phase 2 is
   due before 2026-11-25, the M5 Ultra's expected delivery. Phase 4's timed runs wait until the Codex machine
   is otherwise idle.
2. (2026-11-22, revised by Hans the same day: "I will push to GitHub") **Git.**
   - Codex makes no commit, push, branch or other state-changing git command (the house rule). Read-only
     git carries `--no-optional-locks`.
   - Hans commits Codex's work and pushes it to GitHub himself, as each phase is done, during the run
     included. Its files are disjoint from the run's (section 4). The run works on a copy made at launch, so
     it never sees these commits, and its diff still applies on top of them. This narrows milestone decision
     6's "no edit reaches the repository while a phase runs" to the run's own files (ruling R1 of the run).
   - Phase 1's GitHub run is the run of Hans's push.
3. (2026-11-22) **History.** `doc/history/2026-11.md` belongs to the run's file table, so Codex does not
   edit it. Each Progress entry of this plan carries a one-paragraph history text, which Hans adds when he
   commits.
4. (2026-11-22) **The pinned pair on the M5 Ultra.** The default is MLX 0.32.4 with mlx-c 0.8.0, as on both
   Macs so far (milestone plan, "Depends on").
   - If Homebrew no longer installs that pair, Phase 2 writes the method that does (a local tap with
     `brew extract`, or `scripts/build_mlx_deps.sh` with Xcode), with its cost.
   - Moving to a newer pair is Hans's ruling, never a default. It would change the milestone's dependency
     and need a revalidation of Phases 1 to 3.
5. (2026-11-22) **Bugzilla.** Codex reads it and files nothing (milestone decision 9).
6. (2026-11-22, Hans: "No point of pinning. SIMPLE will change most likely and we will have to adopt. We can
   pin for now and go ahead with phase 4.") **A measured planner in SIMPLE's benchmark: Phase 4 goes ahead.**
   - *Pins.* A pin is a working point, not a commitment: SIMPLE will move, and mlx-fortran's comparator
     follows it. For now Phase 4 works from the pin `3a595f42f`, so that its numbers compare with run
     `mlxf_m1`'s Phase 0.
   - *What Phase 4 adds:* a test-UI key `fftw_plans=estimate|measure` for `polar_matching_bench`'s
     `block_prod` and `shiftmap` suites (default `estimate`, unchanged). It lives on a SIMPLE branch from
     the pin, which Hans creates, commits and pushes.
   - *What it measures:* the ratio on the Codex machine.
   - *Phase 6:* whether it measures with `fftw_plans=measure`, and at which SIMPLE commit, is decided when
     run `mlxf_m1_m5`'s spec is written, from Phase 4's numbers. This plan writes no decision into
     `mlxf_milestone1.md`.

Defaults taken without a question: the plan's name; the section name in `how2set_up_dev.md` ("New Mac for
a run"); the key name `fftw_plans`.

## 4. Not in this plan

- **Every file run `mlxf_m1` may edit** (the run's fence for its Phases 0, 4 and 5):
  - `doc/implementation_notes/planned/mlxf_milestone1.md`, its `_report.md` and `mlxf_scientific_examples.md`;
  - `doc/history/`;
  - `doc/architecture_principles.md`, `doc/collaboration/apple_questions.md` and `doc/policies/`;
  - `.github/skills/`;
  - `scripts/check_rules.py`, `scripts/check_test_registry.py` and `scripts/gen_mlxc_bindings.py`;
  - `src/core/mlxf.f90`, `src/core/array/mlxf_array.f90` with its tester, `src/core/ops/` and `src/core/fft/`;
  - everything under `src/test/`;
  - `test/CMakeLists.txt` and `test/mlxf_test_exec.f90`.

  Findings that belong there are written into this plan's Progress for after the run.
- Library code of any kind, including the open review items. Two need Hans's rulings: `mlx_to` checks size,
  not shape; and about 900 lines are duplicated per kind in `array/`. One is a policy wording: assignment
  from an empty array empties the left side, which copying derived types with empty handles relies on. All
  come after the run.
- Run `mlxf_m1_m5`'s arun spec, which Claude writes, and the M5 Ultra itself: Phase 2 writes the procedure,
  Hans carries it out.
- Upstream changes to MLX, mlx-c or GCC. A question for Apple goes into Progress, for
  `apple_questions.md` after the run.
- SIMPLE beyond Phase 4's branch.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement only | Debug and Release from scratch on the Codex machine, zero warnings, fast gate |
| 1 | CI workflow (dependency discovery if needed); library behaviour identical | a green GitHub run of both matrix entries for Hans's push of the fix; the local headless gate |
| 2 | documentation | every version and command in the section from a recorded command output; the pinned pair's installability established |
| 3 | documentation | each issue classified against the PRs it cites; each reproducer run on gfortran trunk with the revision recorded |
| 4 | SIMPLE test code (decision 6) | default `estimate` byte-identical to the pin; `measure` timed twice per case; production path unchanged |

## 6. Acceptance

Every number carries its origin: *exact*, *measured*, *derived* or *guessed*.

- **Phase 0.**
  - Zero compiler warnings, *exact*.
  - The fast gate's seven entries pass, *exact*; the count is seven at `0a1eec2`.
- **Phase 1.**
  - Both matrix entries (debug, release) green on GitHub for the pushed fix, *exact*.
  - The runner's installed `gcc`, `cmake`, `mlx` and `mlx-c` versions recorded from the run log.
  - Whether the runner opened a Metal device: `unit_core`'s device count or skip line, recorded.
  - The headless gate on the Codex machine: `sandbox-exec -p "(version 1)(allow default)(deny iokit-open)"`
    around a `-DMLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON` build, as reproduced on 2026-11-21. It passes with
    the workflow's commands.
- **Phase 2.**
  - Every version string in the new section is copied from a command output recorded in Progress. Sources:
    `brew info --json=v2`; the git history of homebrew-core's `Formula/m/mlx.rb` and `mlx-c.rb`; the MLX and
    mlx-c release pages.
  - The pinned pair is shown installable on macOS 26 arm64 by a named method, or shown not to be, with the
    reason.
- **Phase 3.**
  - Each issue's status is "duplicate of PR n", "related to PR n, file as new" or "fixed on trunk at
    revision r". It cites the PR text read (title, status, the comment that decides).
  - Each reproducer is compiled and run on gfortran trunk: Compiler Explorer's execution, or a local trunk
    build. The trunk revision or date and the output are quoted.
- **Phase 4.**
  - *Identity:* with `fftw_plans` absent or `estimate`, the identity files `polar_shiftmap_identity_<map>.bin`
    of the branch equal the pin's byte for byte, *exact*.
  - *Production:* the production path (no fixed seed) keeps `FFTW_MEASURE` with wisdom import, unchanged,
    *exact*. Shown by reading the diff and by one run without a fixed seed, if the test executable allows
    one.
  - *Timings:* `maps_per_s` for both maps and `pairs_per_s` for the four dense `block_prod` cases, under
    each planner. Two invocations each, best of 3 after a warm-up (the suites' own protocol), the spread
    reported.
  - *Planning cost:* the planning time of `measure` is reported separately; timed loops exclude it.
  - *Context, not a gate:* the ratio `measure`/`estimate` per map and per case, on the Codex machine
    (*measured*). The Codex machine is not the verdict machine.

## 7. Common rules and stop conditions

Rules:

- A file outside section 8's table gets a row first. A file of section 4's list never does.
- Before a phase is done: its exit is checked and recorded, and every touched Fortran file has been through
  the repository's two formatters. The mlx-fortran static gate (`scripts/check_tree.sh`) passes after
  Phases 1 to 3; SIMPLE's gates after Phase 4.
- Timed runs (Phase 4) on an idle Codex machine, with `uptime` before and after.
- Python: standard library, 3.7 or newer.

Stop when:

- a phase needs a file of section 4's list or any library source: write the finding into Progress and
  stop the phase;
- CI fails because of library code or a test rather than the workflow or the runner's dependencies: record
  the log and the cause, and stop Phase 1;
- the pinned pair cannot be installed on macOS 26 arm64 by any method within reach (Homebrew tap, source
  build with Xcode): record the evidence and stop Phase 2 for decision 4's ruling;
- Phase 4's option would change the production path or the default bench output;
- anything would need the M2 Ultra.

Gates no ruling may waive: Phase 4's byte identity of the default, and the unchanged production path.

## 8. Phases

### Phase 0, the baseline (Codex machine)

1. Record the machine: chip, memory, macOS, GFortran, CMake, Python, `brew list --versions mlx mlx-c gcc
   cmake fftw`.
2. Check out the base. Record `git --no-optional-locks log -1` and `status --short --branch`.
3. Build Debug and Release from scratch in trees outside the repository with `-DMLXF_WERROR=ON
   -DFORTLS=OFF`, then run `scripts/run_fast_gate.sh` on each.

Exit: the machine record; both trees with zero warnings and seven passing entries; the per-entry times.

### Phase 1, CI on GitHub

1. List the workflow's runs for `hael/mlx-fortran` (`gh run list`, or the Actions page) for the pushes of
   `0d3537b`, `2862201` and `0a1eec2`, and record each matrix entry's result.
2. If a run is red, read its log and classify the failure:
   - the runner's dependencies;
   - the workflow;
   - the build;
   - a test.

   Reproduce it locally under the headless gate where it can be reproduced.
3. Fix the workflow, and `cmake/Dependencies.cmake` only if dependency discovery is the cause. Candidates
   to judge, not to assume:
   - record the runner's versions (`brew list --versions` as a step);
   - decide whether the runner installs the pinned pair (decision 4's method from Phase 2) or follows
     Homebrew;
   - ensure `install_name_tool` is the system one (the M3 Pro needed
     `-DCMAKE_INSTALL_NAME_TOOL=/usr/bin/install_name_tool`).
4. Hans commits and pushes the fix (decision 2), and its GitHub run is read back.

Exit: a green run of both matrix entries for the pushed fix, its URL in Progress, with the runner's versions
and Metal line; the headless gate passes locally; the changed files listed. If every run was already green:
the URLs and versions, and no change.

### Phase 2, the M5 Ultra bring-up kit (due 2026-11-25)

1. What Homebrew ships today for `mlx`, `mlx-c`, `gcc`, `cmake` and `fftw`: versions, bottles for macOS 26
   arm64, dependencies.
2. If today's `mlx`/`mlx-c` is not 0.32.4/0.8.0, list the methods that give the pinned pair, each with its
   requirement and cost:
   - a local tap made with `brew extract` (does it pour a bottle, or build from source, which needs Xcode's
     Metal compiler?);
   - `scripts/build_mlx_deps.sh` (needs Xcode).

   Recommend one under decision 4.
3. Read the MLX and mlx-c releases after the pinned pair for changes that touch milestone 1's decisions:
   - CPU float64 FFT and `exp`, `sin`, `cos`;
   - `irfft`'s default length and normalisation (Apple question 19);
   - NAX and `MLX_ENABLE_TF32`;
   - the `find_package_handle_standard_args` name in `MLXCConfig.cmake`;
   - the internal `_mlx_array_is_row_contiguous`, whose disappearance fails the build by design.
4. How to tell on the M5 Ultra whether NAX is present and used: the device-info keys and values MLX 0.32.4
   reports, and where MLX reads `MLX_ENABLE_TF32`. Cite the source at tag `v0.32.4` with file and line.
5. Write the section "New Mac for a run" in `doc/how2s/how2set_up_dev.md`, in order:
   - Command Line Tools or Xcode, and which step needs which;
   - Homebrew packages with exact versions and the pinning method;
   - the Python floor;
   - SIMPLE's build at the pin (FFTW from Homebrew; the bundled OpenBLAS fetched at configure time, so the
     network is needed);
   - the GPU check: `mlxf_test_exec test=unit_core` reports one GPU device, from a Terminal session, since a
     sandboxed or headless session sees none;
   - the NAX check;
   - a pointer to `agent_runs`' `SETUP.md` for arun, without copying it.

Exit: the section exists; every version and command in it is backed by a recorded output in Progress; the
pinned pair's method is named with its evidence, or decision 4's ruling is asked; the release reading lists
each relevant change, or says "none", per item of step 3.

### Phase 3, the gfortran reports

1. For each of the five issues in `doc/compiler_issues/README.md`, read the PRs it cites (57696, 119802,
   110626, 37336, 90068, 121472, 121475, 128856), and any duplicate they point to.
2. Run each reproducer on gfortran trunk: Compiler Explorer with execution, or a local trunk build. Record
   the revision or date and the output. Run issue 4 first; the README asks for exactly this before filing.
3. In the README, per issue, add the status of section 6, the trunk result and the final text to file.
   Fill the "Upstream numbers" table's status column, leaving the numbers to Hans. Update a reproducer's
   "versions seen" header line only if trunk changes it.

Exit: five classifications with citations; five trunk outputs quoted; the README ready for Hans to file;
the static gate passes.

### Phase 4, a measured planner in SIMPLE's benchmark (decision 6)

1. In a SIMPLE checkout on a branch Hans creates from the pin `3a595f42f`, read SIMPLE's agent instructions
   and the skills they route to for test commanders.
2. Add `fftw_plans=estimate|measure` to the test UI of `polar_matching_bench` for the suites `block_prod`
   and `shiftmap`. `measure` gives the calculator and the shift maps `FFTW_MEASURE` plans under the test
   executable's fixed seed. It does not import or write a wisdom file. The default keeps every byte of the
   pin's output.
3. Build Release, run SIMPLE's fast gate, then:
   - the identity check of section 6 under the default;
   - `block_prod` (the four dense cases) and `shiftmap`, under each planner, twice each, at the Codex
     machine's full team and its performance cores.
4. Record the TSV rows, the planning time and the ratio per map and per case in Progress, with the
   machine's core counts.

Exit: the default's identity files equal the pin's; the production path is unchanged (diff and run); the
ratio table exists with spreads; SIMPLE's fast gate passes; the branch's files are listed.

### File table

| File | What | Phases |
| --- | --- | --- |
| `doc/implementation_notes/planned/mlxf_m1_codex.md` | this plan: Progress only | each |
| `.github/workflows/ci.yml` | the CI fix | 1 |
| `cmake/Dependencies.cmake` | dependency discovery, if needed | 1 |
| `doc/how2s/how2set_up_dev.md` | the section "New Mac for a run" | 2 |
| `doc/compiler_issues/README.md` | classifications, trunk results, final texts | 3 |
| `doc/compiler_issues/gfortran_*.f90` | the "versions seen" header line only, if needed | 3 |
| SIMPLE: `src/main/commanders/test/simple_polar_matching_bench.f90`, `src/main/commanders/test/simple_commanders_test_highlevel_matchbench.f90`, `src/main/ui/simple_test/simple_test_ui_highlevel.f90`, `doc/policies/test_environment_policy.md` | the `fftw_plans` key, on Phase 4's branch | 4 |
| SIMPLE: `src/main/pftc/simple_polarft_memo.f90`, `src/main/pftc/simple_polarft_shiftmap.f90` | the planner choice under a fixed seed, if needed; production path unchanged | 4 |

## Progress

(One entry per phase, written by Codex: date, machine, base, files changed, each exit item and how it was
met, log paths, decisions taken under delegation, the history text for decision 3, and "what it means, in
short".)

### Phase 0, the baseline: 2026-11-22 - complete

- **Machine (measured):** Apple M3 Pro MacBook Pro, 11 CPU cores (5 performance, 6 efficiency), 18 GB;
  macOS 26.7.3 (25G342), Command Line Tools, GFortran 16.2.0, CMake 4.4.3, Python 3.12.2. Homebrew:
  MLX 0.32.4, mlx-c 0.8.0, GCC 16.2.0, CMake 4.4.3, FFTW 3.3.11.
- **Base (exact):** clean worktree at `27d80aa2183cf3590c68c2ad9569f740b25b68b0` on `main`; the only
  change from the plan-adding commit `5944901` is the revised plan itself, so the code under test is the
  pinned base. No checkout or state-changing git command was used. User instruction: work directly in the
  repositories, with no branches; this supersedes the SIMPLE branch requirement of decision 6.
- **Build and gate (measured):** clean Debug and Release trees, `MLXF_WERROR=ON`, `FORTLS=OFF`, and
  `CMAKE_INSTALL_NAME_TOOL=/usr/bin/install_name_tool`. Both compiled with no compiler warnings; the
  static gate passed and all seven fast entries passed with Metal access. The Debug `unit_core` reported
  one GPU (`applegpu_g15s`). Debug / Release per-entry seconds: core 0.46 / 0.64, array 8.26 / 11.80,
  ops 0.29 / 0.52, linalg 0.15 / 0.34, FFT 0.16 / 0.60, compile 3.24 / 1.07, object contracts
  0.56 / 0.78. Total real seconds were 8.27 / 11.81. These timings are observations, not performance
  comparisons. The sandbox initially saw zero GPUs and all seven GPU-required Debug entries failed;
  the successful gates ran with access to the laptop's Metal device.
- **Files and evidence:** this Progress entry only. Trees and configure, build, gate and GPU-check logs are
  under `/private/tmp/mlxf-m1-codex-20261122/`; timing tables are in each tree's `test_runs/`.
- **History text:** On the M3 Pro laptop, Codex rebuilt the milestone baseline in Debug and Release with
  warnings as errors; both static and seven-entry fast gates passed with an observed Metal device.

**What it means, in short:** the local baseline is established; no work was run on the M2 Ultra.

### Phase 1, CI: 2026-11-22 - evidence incomplete

- **GitHub results (exact):** both matrix jobs succeeded for [`0d3537b`](https://github.com/hael/mlx-fortran/actions/runs/44957271541),
  [`2862201`](https://github.com/hael/mlx-fortran/actions/runs/45036228067), and
  [`0a1eec2`](https://github.com/hael/mlx-fortran/actions/runs/45055765218). Both also succeeded for
  [`27d80aa`](https://github.com/hael/mlx-fortran/actions/runs/45068157819). The public jobs API returned
  their conclusions; its JSON is in `/private/tmp/mlxf-m1-codex-20261122/`.
- **Headless reproduction (measured):** in a temporary source copy, the workflow's `compile_debug.sh`
  and `compile_clean.sh` commands, with its `MLXF_CMAKE_ARGS` and the documented `sandbox-exec` policy,
  built, passed all seven fast entries and installed successfully. A verbose Release core run reported
  zero GPU devices and the expected skip. Logs: `headless-debug.log`, `headless-release.log` and
  `headless-core.log` in `/private/tmp/mlxf-m1-codex-20261122/`. No installed package was changed.
- **Outstanding evidence:** GitHub's job page requires sign-in to view logs, and the unauthenticated
  job-log API returned HTTP 403. Runner dependency versions and Metal status are therefore unverified.
  Moreover, the workflow's fast gate uses `ctest --output-on-failure`, so successful jobs do not print
  `unit_core`'s GPU count or skip line; the requested Metal line cannot be recovered from those successful
  logs as the workflow stands. A workflow instrumentation change would conflict with this phase's
  instruction to make no change if every run is green. The owner subsequently chose the instrumentation
  change below.
- **Files and decision:** this Progress entry and `.github/workflows/ci.yml`. No commit, push or branch was
  made. Phase 1 is not marked complete while the required runner evidence remains missing.
- **History text:** The three milestone CI runs had successful Debug and Release jobs, and both workflow
  commands passed a local headless reproduction; runner versions and Metal status remain unverified.

**What it means, in short:** the CI failures anticipated by the plan did not occur. Its requirement to
record a Metal line from a successful run needs an instrumented workflow or a revised exit criterion.

**Owner ruling, 2026-11-22:** add the missing CI logging despite the green runs. The workflow now prints
the installed GCC, CMake, MLX and mlx-c versions, then runs `unit_core` verbosely so a successful job shows
its GPU count or skip. The Debug workflow and the verbose core step passed in the headless source copy;
the Release workflow and the same verbose core step passed there as well. The new command's output shows
`GPU devices: 0` and the expected skips locally. Logs: `headless-versions.log`,
`headless-debug-logging.log`, `headless-debug-core.log`, `headless-release-logging.log` and
`headless-release-core.log`
under `/private/tmp/mlxf-m1-codex-20261122/`. The owner will commit and push; the new GitHub run and its
runner versions and device line are still required to close the phase.
