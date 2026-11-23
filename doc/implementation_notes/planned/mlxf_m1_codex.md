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
| SIMPLE: `scripts/simple_args_generator.pl` | accept the test-only `fftw_plans` command-line key | 4 |
| SIMPLE: `src/main/pftc/simple_polarft_calc.f90`, `src/main/pftc/simple_polarft_core.f90` | pass the benchmark's planner choice into the calculator before its eager plan creation | 4 |
| SIMPLE: `src/main/pftc/simple_polarft_block.f90` | report the block FFT plan's measured construction time | 4 |
| SIMPLE: `.codex/branch-context/master.md` | local verified milestone record required by SIMPLE's agent instructions | 4 |

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

### Phase 1, CI: 2026-11-22 - complete

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

**Pushed run:** the owner committed and pushed `69b64f32a613972438819f0d7c8bb7da927ffc8a`. Both matrix
jobs and their `Report device availability` steps succeeded in
[`45070808884`](https://github.com/hael/mlx-fortran/actions/runs/45070808884). The public jobs API
confirms the conclusions; the owner supplied the Debug job's signed-in log output. Its `brew list` reported
GCC 16.2.0, CMake 4.5.0, MLX 0.32.4 and mlx-c 0.8.0. Its verbose `unit_core` reported one GPU, an Apple
Paravirtual device with architecture `air64_v27`; the device suite passed, and CPU array tests ran. This is
the Debug runner's observation, not an assertion about the Release runner. Phase 2 research proceeded while
waiting for these lines. **History text:** The Debug and Release GitHub jobs passed with version and device
reporting; the Debug runner opened one Apple Paravirtual GPU and ran its device tests. The owner also
reported a GitHub warning that `actions/checkout@v4` targets deprecated Node.js 20 and is being run on
Node.js 24; the job still succeeded.

### Phase 2, new Mac setup: 2026-11-22 - complete

- **Files:** `doc/how2s/how2set_up_dev.md` (section 6) and this Progress entry. No packages were installed,
  upgraded, downgraded or unlinked on the laptop. A fresh M5 Ultra has not been tested.
- **Homebrew (measured 2026-11-22):** `HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2` reported MLX 0.32.4
  (runtime dependency `python@3.15`), mlx-c 0.8.0 (MLX), GCC 16.2.0 (gmp, isl, libmpc, mpfr, zstd),
  CMake 4.5.1 (none), FFTW 3.3.11 (libomp), libtiff 4.7.2 (jpeg-turbo, webp, xz, zstd), jpeg-turbo
  3.2.1 (none), and Python 3.15.2. Each of the first seven has an `arm64_tahoe` bottle. Raw formula output
  is in `/private/tmp/mlxf-m1-codex-20261122/brew-info.json` and `brew-image-info.json`.
- **Pin method (measured):** `HOMEBREW_CACHE=/private/tmp/mlxf-m1-codex-20261122/brew-cache brew fetch
  --force-bottle mlx mlx-c` fetched the macOS 26 arm64 bottles. Their SHA-256 values matched Homebrew's
  metadata: MLX `ffa4d6ec493da3452637f438860f42cbbf1fc689cea0c5f358a0d3053ba1d4fb`, mlx-c
  `c81ab3e3177acc5cbdcc27e2c7651afeaeec28509231f44bfedb985420868606`. The same versions are installed
  and passed Phase 0 on macOS 26 arm64. `brew-fetch.log` records the fetch. The guide recommends the
  current bottles with a version check; if they disappear, the pinned Xcode source build is the fallback,
  whose script and prerequisites were read, not executed in this phase.
- **Upstream release reading (exact):** the GitHub release API lists no MLX release after `v0.32.4`;
  mlx-c's release list is empty and its tags API lists `v0.8.0` as newest. Therefore no later release
  changes were found for CPU float64 FFT/transcendentals, `irfft`, NAX/TF32, the CMake package name, or
  `_mlx_array_is_row_contiguous`. API results: `mlx-releases.json`, `mlxc-releases.json`, and
  `mlxc-tags.json` in the temporary log directory; this says nothing about unreleased changes.
- **NAX (source, exact):** at MLX `v0.32.4`, `mlx/backend/metal/device_info.cpp:25-51` exposes
  `device_name` and `architecture`, not a NAX status key. `device.cpp:978-995` checks build support,
  macOS 26.2 and architecture generation (17 for Macs); `matmul.cpp:960-966` checks NAX availability,
  dtype and TF32; `mlx/utils.h:225-227` reads `MLX_ENABLE_TF32` once with default 1. The guide separates
  architecture-based eligibility from observed dispatch and requires a capture for the latter.
- **SIMPLE (source, exact):** at `3a595f42f`, `cmake/Dependencies.cmake` requires FFTW, TIFF, JPEG and
  zlib and fetches bundled OpenBLAS 0.3.34 at configuration. `compile_clean.sh` builds Release and runs
  its fast gate. The setup points to `agent_runs/SETUP.md` for arun.
- **History text:** A new-Mac guide records the currently available pinned MLX and mlx-c bottles, SIMPLE's
  dependencies and GPU/NAX checks; the actual M5 installation remains to be performed on that machine.

**What it means, in short:** the pinned pair is available for macOS 26 arm64 today, with a source-build
fallback; NAX capability and actual kernel use must be recorded separately on the new machine.

### Phase 3, gfortran reports: 2026-11-22 - complete, prepared for owner filing

- **Files:** `doc/compiler_issues/README.md` and this Progress entry. No upstream report was filed. The
  reproducer headers retain their accurate historical observations; the differing trunk result is recorded
  in the README. The two house formatters were probed on a scratch copy: the full restyler changes the
  reproducer body, which the file table does not permit, so no reproducer source was touched.
- **Trunk (measured):** with explicit owner approval, all five standalone reproducers were submitted to
  Compiler Explorer and executed using x86-64 Linux GNU Fortran 17.0.0 20261122, GCC commit
  `a3a3f32131a9fe59b6a3a555696b63094fdea323`. They all compiled; issue 4 passed its expected-value check,
  issues 1 to 3 still missed the specified assignments/finalizations, and issue 5 still showed an
  AddressSanitizer heap-use-after-free. The README quotes all five outputs, flags and exit codes. Complete
  request and response JSON files are `/private/tmp/mlxf-m1-codex-20261122/ce-issue<N>-{request,result}.json`.
- **GCC reports (exact):** Bugzilla's current statuses are 57696 NEW, 119802 UNCONFIRMED, 110626 REOPENED,
  37336 ASSIGNED, and 90068, 121472, 121475 and 128856 RESOLVED FIXED. The README links the relevant
  comments, classifies issue 1 as a duplicate of 57696, issue 4 as fixed on the tested snapshot, and issues
  2, 3 and 5 as related to existing fixed reports but still failing and suitable for new reports. It gives
  suggested filing text and leaves new upstream numbers for the owner. Raw Bugzilla responses are in the
  temporary log directory.
- **History text:** Five gfortran reproducers were run on trunk: the self-assignment case passed, the other
  four did not; the report index now records the related GCC issues and proposed filing text.

**What it means, in short:** the owner has the evidence to comment on the existing allocatable-component
report and file the three remaining cases. A passing trunk case is not proof that the installed 16.2 or
every architecture is fixed.

### Phase 4, measured FFTW planner: 2026-11-22 - complete, with largest-case timing qualification

- **Checkout:** the owner directed work straight in the repositories, with no branches. SIMPLE was clean on
  `master` at `ed0aaa3428b7ebe9d834418587f31354850cb99b`; the files named by the original plan are
  unchanged there from the working pin, but other SIMPLE files differ. To obtain an exact pin baseline,
  a temporary source copy was reconstructed at `3a595f42f928a366744094a28b62aeb6020099e4` by replacing the
  eleven changed tracked files from that commit; its Release test-executable build passed outside either
  checkout, with no compiler warnings observed (`simple-pin-build.log`). A small one-thread shift-map
  identity fixture (`nspace=100 nstates=1 nptcls=8`) completed at the pin; its identity files and log are
  under `/private/tmp/mlxf-m1-codex-20261122/pin-identity/`. This is a preliminary fixture, not the full
  planned comparison.
  The pinned scratch configuration selected `-mtune=native` while the existing checkout's Release cache
  uses `-mtune=generic`; both use GCC/GFortran 16.2, `-O3`, OpenMP and `USE_ARCHOPT=ON`. This difference
  must be considered if the byte comparison fails; timings compare planners within the same modified build.
- **Delivered changes:** `fftw_plans=estimate|measure` was added to the two named benchmark suites,
  with estimate as the default and measured planning under a fixed seed without wisdom-file I/O. The
  additional accepted-key generator and calculator interface/lifecycle files have rows in the table above.
  SIMPLE's existing checkout was built for validation; no branch, commit or push was made.
- **Formatter finding:** SIMPLE has neither of mlx-fortran's two formatters. Running those formatters on
  copies of the touched SIMPLE files produces broad unrelated restyling; the restyler refuses the benchmark
  driver because it contains a continued string. The originals were preserved. SIMPLE's own static checks
  passed. Owner ruling, 2026-11-22: use SIMPLE's own formatting checks. The owner also reported that
  nothing else was running on the laptop and authorized the remaining measurements when idle.
- **Build and checks (measured):** the modified Release `simple_test_exec` and full build completed;
  no compiler warnings were observed. The install refreshed `build/bin/simple_test_exec`, whose invalid
  planner check also failed as intended. After clarifying the UI help, the full fast gate was rerun and
  passed all 15 entries, followed by a full build and install. Logs in
  `/private/tmp/mlxf-m1-codex-20261122/`: `simple-modified-build.log`, `simple-ui-rebuild.log`,
  `simple-fast-gate-final.log`, `simple-full-build-final.log` and `simple-install-final.log`.
  For the small fixture above, both default and explicit
  `fftw_plans=estimate` produced window and screen identity files byte-for-byte equal to the pinned build.
  Both `shiftmap` and `block_prod` ran with `measure`, logged separate FFTW planning times and created no
  wisdom file; an invalid planner and use on `suite=per_pair` were rejected. In this small shift-map fixture,
  the measured and estimated plans gave the same rotation, radius and direction indices across 128 maps per
  type; the largest loss difference was `1.20e-7` and width differences were `8.11e-5` (screen) and
  `5.42e-5` (window). These are observations, not frozen accuracy bounds. Smoke logs and outputs are in
  the `simple-smoke-*` and `simple-block-smoke` directories under the temporary log directory.
  A second one-thread identity fixture at `nspace=1000 nstates=1 nptcls=16` also matched both map files
  byte for byte between the pin, the default and explicit `estimate` (`identity-1000-*` directories).
- **Production check:** `simple_test_exec` always calls `fix_test_seed`,
  and the benchmark itself sets a fixed seed, so that executable cannot exercise the unseeded production
  path. The unseeded wisdom-import/export branch was checked in the diff but not run.

**Full-size measurements, 2026-11-22:** the owner reported the laptop otherwise idle and ruled that
SIMPLE's own formatting checks apply. Runs are sequential at `nthr=11`, whose existing driver also measures
5 and 1 threads; the one-thread timing rows retain the suite's 200-particle cap. `OPENBLAS_NUM_THREADS=1`.
The pinned 2500-direction, 4-state, 2000-particle shift-map reference completed both team-identity checks
with zero maps differing and wrote both identity files. Its resource wrapper returned 1 after normal
completion because sandbox access to `kern.clockrate` was denied; those timing values are excluded from
the comparison. VM swapouts rose from 0 to 31148 pages during this reference invocation, so subsequent
timed invocations record VM counters and flag paging. Logs and TSVs are under
`/private/tmp/mlxf-m1-codex-20261122/full-bench/`; `driver.log` records each invocation and `manifest.json`
indexes the measured runs. The driver starts with the lower-memory block cases and reverses planner order
between repeats. No benchmark result is inferred from a paging-affected sample without qualification.

**Full-size exits:** all 16 block and all five modified shift-map invocations returned zero. The default
shift-map run and both explicit-estimate repeats match both verified pin identity files byte for byte
(1,024 map entries per file). All five modified shift-map invocations reported zero maps differing between
one and eleven threads. No invocation created a wisdom file. A final pinned run with working resource
counter access returned zero and reproduced the original reference files (`pin-shiftmap-verified/`),
closing the earlier wrapper-only failure. The two pinned runs are excluded from the planner timing table.

**Planner comparison (measured rates; derived ratios and spreads).** Each rate is the arithmetic mean
of two invocations, each taking its own best of three after a warm-up. Spread is
`100 * (maximum - minimum) / mean` across the two invocation rates. Rates are useful pairs/s for
`block_prod`, maps/s for screen/window. All rows below use 2,000 particles. For block scoring, the
11-thread run sweeps B=4,8,16 and its best B is used at five threads; B=16 was selected in every run.
The capped one-thread rows remain in the raw TSVs and are not mixed into these comparisons.

| Suite/case (directions x states) | Threads | Estimate /s | Measure /s | Measure/estimate | Spread E / M (%) |
| --- | ---: | ---: | ---: | ---: | ---: |
| block_prod 1000x1 | 5 | 674,029.0 | 677,924.5 | 1.0058 | 3.90 / 1.22 |
| block_prod 1000x1 | 11 | 978,166.5 | 970,060.0 | 0.9917 | 2.05 / 0.68 |
| block_prod 1000x4 | 5 | 725,605.0 | 720,945.5 | 0.9936 | 0.63 / 0.04 |
| block_prod 1000x4 | 11 | 1,057,800.0 | 1,062,320.0 | 1.0043 | 1.88 / 0.63 |
| block_prod 2500x1 | 5 | 677,766.0 | 671,195.5 | 0.9903 | 0.95 / 0.85 |
| block_prod 2500x1 | 11 | 985,686.0 | 965,439.0 | 0.9795 | 0.86 / 0.50 |
| block_prod 2500x4 * | 5 | 706,208.0 | 703,809.0 | 0.9966 | 1.24 / 0.21 |
| block_prod 2500x4 * | 11 | 1,050,640.0 | 1,045,850.0 | 0.9954 | 0.39 / 0.04 |
| screen 2500x4 | 5 | 2,255.8 | 2,411.2 | 1.0689 | 1.27 / 0.03 |
| screen 2500x4 | 11 | 3,263.1 | 3,460.3 | 1.0605 | 0.08 / 0.03 |
| window 2500x4 | 5 | 13,386.8 | 13,674.5 | 1.0215 | 0.98 / 0.16 |
| window 2500x4 | 11 | 19,554.7 | 19,858.2 | 1.0155 | 0.11 / 0.08 |

* The largest block case had system-wide swap-outs in 2 of its four invocations (`block-2500-4-estimate-r1`, `block-2500-4-measure-r2`).
Memory pressure limits the interpretation of its ratios; they do not establish a precise planner ranking.
The other timed invocations had 0 new swap-out pages in total. Some invocations had small system-wide
swap-in activity; the raw VM counters are retained. The maximum process memory footprint was 9.691 GiB.
These measurements are from the M3 Pro; the M5 needs its own run.

**Measured planning cost (seconds, range over the two measured-planner invocations).** The timer
surrounds FFTW plan creation before the scoring loops. The memo group includes its short setup
bookkeeping; no optional many-reference workspace was requested by these benchmark calls.

| Case | Memo plans | Block plan | Screen-map plan | Window-map plan |
| --- | ---: | ---: | ---: | ---: |
| block_prod 1000x1 | 0.011797–0.012522 | 0.000021–0.000023 | — | — |
| block_prod 2500x1 | 0.012459–0.013118 | 0.000019–0.000730 | — | — |
| block_prod 1000x4 | 0.011631–0.012677 | 0.000014–0.000020 | — | — |
| block_prod 2500x4 | 0.011229–0.012131 | 0.000018–0.000019 | — | — |
| shiftmap 2500x4 | 0.012085–0.014713 | 0.000019–0.000661 | 0.011333–0.011399 | 0.001341–0.001353 |

**History text:** On the M3 Pro, SIMPLE gained the test-only FFTW planner option with estimated plans as
the default. Release build, UI validation, installation and all 15 fast entries passed. Full-size default
and explicit-estimate shift-map files equal the SIMPLE pin byte for byte. Two invocations per planner
showed little block-throughput change and roughly 6–7 % screen-map and 1.5–2.2 % window-map improvement
with measured plans. The largest block case had system paging, so its small ratio differences are qualified.
The owner ruled that SIMPLE's own formatting checks apply. No commit, push, branch or M2 Ultra work was done.

**What it means, in short:** the laptop work is delivered with reproducible identity evidence and the
requested planner comparison. These numbers inform the M5 run specification; they do not choose its
SIMPLE working commit or planner policy. The largest block result needs its memory-pressure qualification.
