# Run `mlxf_m1_m5`: milestone 1's measurements and verdicts on the M5 Ultra

Status, 2026-11-24: **delivered by run `mlxf_m1_m5`, Phases 0 to 4; at the hold with milestone 1** (scoring verdict
4.69, go; shift maps 0.971 and 0.683, negative; report `completed/mlxf_milestone1_report.md`). Planned the same
day; decisions 1 to 14 ruled by Hans on 2026-11-24 (11 as amended, the others as
recommended). Base: mlx-fortran
`0cfb128` (this note's commit is the run's HEAD). Measured sources: mlx-fortran
`4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47` and SIMPLE `0a8b0903eee151700305399e8e3ff53c2c21caae`.
Supersedes: none. It is the `mlxf_m1_m5` specification that [milestone 1](mlxf_milestone1.md) decision 6
and [the M5 preparation follow-up](mlxf_m5_preparation.md) Phase 2 refer to. Depends on: milestone 1
Phases 0–5c delivered (validated: yes, M2 Ultra and MacBook Pro); the M5 Ultra with MLX 0.32.4 and mlx-c
0.8.0 (validated: device probe below, no gate run yet); SIMPLE's pin (validated: present, not built here).

## 1. Why

Milestone 1 is open on three items, and all three need the M5 Ultra: Phase 5c's deferred measurements
(which shift-map graph and tiles to keep), Phase 6's verdicts (GPU scoring and the shift maps against SIMPLE
on all cores of the same machine, milestone decisions 14 and 18), and Phase 7's report, which ends at the
hold where Hans rules milestone 2 and parity Phase 4 onward. On the M2 Ultra, in full precision, the GPU
scored the verdict's case at 4.29 to 4.55 times SIMPLE's 24 cores and built the screen and window maps at
1.69 and 1.10 times (*measured*, context only: the M2 is not the verdict machine, and SIMPLE's maps became
1.28 and 1.16 times faster at `0a8b0903e` by its own record). This run makes those numbers verdicts.

## 2. Contract

- **Measurement and documentation only.** No file under `src/`, `test/`, `scripts/`, `cmake/` or
  `CMakeLists.txt` changes. Parity decision 25 has run `mlxf_m1_m5` edit no source, and parity Phases 2–3
  may be running on the M2 Ultra. A code consequence becomes a recommendation in the report.
- **The measured executable is built from `4706ecb` exported with `git archive`**, never from the run's
  working copy. The run's copy at HEAD is built only for correctness.
- **SIMPLE is read-only.** `~/src/SIMPLE` and its `build/` are the maintainer's: the pin is exported into
  scratch, and the OpenBLAS cache is copied out, never written in place.
- **Frozen numbers stay frozen.** Milestone 1's section 6 and its calibrations (Phases 4a, 5a, 5b-a) are
  not recalibrated on the M5. Thresholds are milestone decisions 14 and 18.
- **No timing from a flagged or gate-failing row** enters a verdict (decision 5).

### What the check found (2026-11-24, on the M5 Ultra, at `0cfb128`)

- **Machine** (*exact*): Apple M5 Ultra, 30 CPU cores in two levels (perflevel0 "Super" 10, perflevel1
  "Performance" 20; no efficiency cores), 64-core GPU, 103,079,215,104 B memory, macOS 27.2.1, Command Line
  Tools only at writing (no Xcode, no `xctrace`; Xcode may be installed before launch for decision 11).
  Homebrew: gcc 16.2.0, mlx 0.32.4, mlx-c 0.8.0, fftw 3.3.11 (the M2 had 3.3.10_2).
- **The GPU from a session** (*measured*, existing Release build in `build/`, 01:54): `unit_core` passes 82
  of 82 and reports "GPU devices: 1", `applegpu_g17d`, `max_buffer_length` 62,620,631,040 B, and
  `memory_size` 103,079,215,104 B. So `recovery_half` runs at 14,930 rows of 4 MiB, about 31.3 GB, and the
  memory budget (milestone decision 13, `POLAR_BUDGET_SHARE` 0.25) is 25.8 GB, against 48 GB on the M2
  (*derived*).
- **NAX**: architecture generation 17 and macOS ≥ 26.2 meet MLX 0.32.4's preconditions. Whether the bottle
  enables it, and whether an operation dispatches to it, show only in a trace of the workload. MLX 0.32.4
  names its NAX matrix-product kernels `steel_gemm_fused_nax_*`, `steel_gemm_splitk_nax_*` and
  `steel_gemm_thin_nax_*` (`mlx/backend/metal/matmul.cpp` at `v0.32.4`). A Metal System Trace from
  Xcode's `xctrace` lists the kernels that ran.
- **Sources**: `4706ecb` and SIMPLE's `0a8b0903e` exist; the pin is an ancestor of SIMPLE's HEAD
  `d354efee2`, so HEAD is not the comparator. Between `4706ecb` and `0cfb128` the kernel sources
  `src/test/mlxf_kernel_polar_table{,_lifecycle,_score,_shiftmap}.f90` are identical, and
  `mlxf_bench_polar_table.f90` differs in one line of whitespace. The library differs (parity Phase 1, dtype
  checks), so results are claimed for `4706ecb` only.
- **The build at `4706ecb`** reads no git metadata. `scripts/release_gate.sh` needs `.git`
  (`rev-parse`), so the export is built by hand with the gate's options (Phase 0).
- **The benchmark's parser at `4706ecb`**: suites `accuracy|time|profile|overlap|stream|shiftmap`; `nthr=`
  defaults to 24, so every invocation passes `nthr=30`; the accuracy mode's schedule identity uses teams
  1 and 24, built in. Case files hold `[case NAME]` blocks with `nspace nstates nrefs nptcls pftsz kfrom kto`.
  Grid files hold `[map window]`/`[map screen]` blocks with `pftsz nrots kfrom kscreen nrho nalpha norder
  nrefs nptcls ncand rho_max_px prior_w simple_commit fftw_plans maps_per_s_t24`. The last key is
  historical: it holds the full team's two rates whatever the team. Unknown keys are ignored, so no option
  outside this list exists.
- **SIMPLE at the pin**: suites `list block_prod check fills neigh shiftmap`; `nthr` defaults to
  `omp_get_num_procs`; `fftw_plans` defaults to `measure` for `block_prod` and `shiftmap`. Defaults
  `USE_ARCHOPT=ON`, `NICE=OFF`, `BUILD_TESTS=ON`; gate `scripts/run_fast_gate.sh`. OpenBLAS 0.3.34 is
  cached for GNU 16.2 and OpenMP under `~/src/SIMPLE/.deps/numerics`, with its tarball in `.deps/downloads`.
- **Missing inputs**: no production BENCH output on this Mac (`~/for_claude` absent), so s, f and the
  width share w stay unmeasured. The laptop's evidence root `~/agent_work/mlxf_m5_preparation/` is not here.
  Its command matrix is in the [completed record](../completed/mlxf_m5_preparation.md), Phase 2 Progress,
  and section 8 below follows it with the corrections listed there.
- **arun** is `~/src/agent_runs` with `HOST=local`. Its `hosts/local.md` says the maintainer may work on
  the machine during a run, hence decision 5's load rule.

## 3. Decisions and rulings

1. (2026-11-24, Hans: ruled as recommended) **Scope.** The run carries out milestone 1's deferred Phase 5c measurements,
   Phase 6 and Phase 7 as five arun phases (0–4, section 8). It ends at the hold of design decision 32.
2. (2026-11-24, Hans: ruled as recommended) **Sources.** Measured: `4706ecb` (exported to `scratch/keep/base_src`) and
   SIMPLE `0a8b0903e` (exported to `scratch/keep/simple_src`). Correctness only: the run's repository copy
   at its HEAD. Every row and sidecar names both full hashes.
3. (2026-11-24, Hans: ruled as recommended) **Teams.** The full team is `nthr=30` for every SIMPLE row and every
   benchmark's host team, with `OPENBLAS_NUM_THREADS=1`. One context invocation at `nthr=10` (the Super
   cores) for `block_prod` 2500_4 and `shiftmap` replaces the M2's 16-core rows; it is never a verdict input.
4. (2026-11-24, Hans: ruled as recommended) **Budget.** Milestone decision 13's quarter of memory, 25.8 GB here (*derived*).
   Configurations above it are pruned before allocation and recorded. It is a stop only when no
   oracle-passing configuration fits.
5. (2026-11-24, Hans: ruled as recommended; thresholds from milestone section 7 and the M2 run) **The timing protocol.**
   - One wrapper script in `scratch/keep/`. Each invocation gets its own directory with `uptime` before and
     after, `/usr/bin/time -l`, and a sidecar: both full hashes, the executable's and inputs' SHA-256, the
     command, `MLX_ENABLE_TF32` and the OpenMP variables, the team.
   - Before starting: wait until the 1-minute load is ≤ 4 and other processes take ≤ 250 % of a core, for
     at most 20 minutes (*guessed*).
   - During: sample every other process's CPU every 5 s. One sample above 400 % flags the invocation
     (milestone section 7). A flagged invocation is repeated up to twice. If it stays flagged it is kept,
     labelled `flagged`, and never used in a verdict or a retention decision.
   - One timed process at a time; nothing heavy of the run's own runs meanwhile. Other processes are never
     killed.
   - `MLX_ENABLE_TF32` is set before each process: 0 is full precision, 1 the accelerated mode. Two
     invocations per row family, each with its built-in warm-up and best of three.
6. (2026-11-24, Hans: ruled as recommended; milestone decisions 14 and 18 unchanged) **The verdict rule, fixed before any
   row.**
   - Ratio: the slower of the GPU's two clean invocations over the faster of SIMPLE's two at `nthr=30`.
   - GPU configuration: the one with the highest slower-of-two rate among clean configurations that pass
     their gates. The M2's canonical plan (B 64, R_t 250, formulation B with the compiled tail) is reported
     beside it.
   - CPU configuration: `block_prod`'s fastest measured block size (milestone decision 14).
   - Branches: ≥ 2.0 go, 1.0 to 2.0 lead, < 1.0 negative. A ratio closer to a threshold than the larger of
     the two sides' spreads is reported "at the boundary" and takes the lower branch.
   - Memory is reconciled before a go (milestone section 6); an unexplained gap turns go into lead.
   - The accelerated mode is reported apart, and counts only where it passes the same frozen gates.
7. (2026-11-24, Hans: ruled as recommended; milestone decision 27 with the 30 % rule of design decision 37) **Shift-map
   graph retention.**
   - The control is contraction 1, Hermitian 0.
   - An alternative is recommended for retention on a map only when its slower-of-two rate exceeds 1.30
     times the control's faster-of-two there; otherwise it is a negative result recommended for removal.
   - Per map, the verdict uses the fastest gate-passing graph: the control or a retained alternative.
   - Removing code is the maintainer's follow-up (decision 1), with the files named in the report.
8. (2026-11-24, Hans: ruled as recommended) **Comparisons are interleaved.** For Stage A of Phase 3 the order is control,
   (1,1), (2,0), (2,1), then the reverse. The control is re-timed beside any configuration that gets a
   second invocation.
9. (2026-11-24, Hans: ruled as recommended) **Formulation C** is timed on 2500_4 in both modes. It is recommended for
   removal unless it beats B by more than 30 % in the accelerated mode while passing the gates (milestone
   Phase 5's note).
10. (2026-11-24, Hans: ruled as recommended; from milestone decision 5) **Unmeasured shares.** s, f and w stay unmeasured unless Hans
    names a BENCH output in the rulings. The report gives decision 5's projection as a function of s and f,
    and omits decision 18's production-equivalent CPU cost.
11. (2026-11-24, Hans: "Yes, add trace step") **NAX: eligibility from the preconditions, dispatch from a
    trace.**
    - *Eligibility:* the architecture generation and the macOS version against MLX 0.32.4's preconditions.
    - *When traces run:* only if Phase 0 finds `/Applications/Xcode.app` and its `xctrace` lists a "Metal
      System Trace" template. Without Xcode, dispatch is recorded as unproven and the trace becomes an open
      item for the maintainer.
    - *How:* one trace per precision mode of a dense invocation (Phase 2) and of a shift-map invocation
      (Phase 3):
      `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer timeout 300 xcrun xctrace record
      --template 'Metal System Trace' --time-limit 180s --output scratch/keep/traces/<name>.trace --launch --
      <wrapper>`. The wrapper exports `MLX_ENABLE_TF32` and execs the executable with its arguments. The
      system's developer directory stays the Command Line Tools (`xcode-select` unchanged), so no build
      changes.
    - *How it is read:* `xctrace export --input <trace> --toc`, then the Metal or GPU tables the table of
      contents lists, searched for the `steel_gemm_*_nax_*` names and their `steel_gemm_*` non-NAX
      counterparts.
    - *What it means, fixed before the traces:*
      - a `_nax_` kernel in the accelerated trace: NAX dispatch observed for that workload;
      - only non-NAX `steel_gemm_` kernels named: not observed;
      - no kernel names in the export: "trace kept, unread", with its path for Instruments;
      - a `_nax_` kernel in a full-precision trace is a finding (the setup guide says
        `MLX_ENABLE_TF32=0` disables the float32 path) and a question for `apple_questions.md`.
    - *Never a timing:* tracing perturbs time. Traces run after their phase's timed rows and never enter a
      verdict. A trace that fails, is refused or hangs (an authorization prompt, for one) is recorded with
      its error; it is not a stop.
    - The TF32 0/1 profile timings (Phase 2) are reported beside the traces as indirect evidence only.
12. (2026-11-24, Hans: ruled as recommended; times *guessed*) **Time boxes.** Phase budgets in minutes: 0: 60, 1: 100,
    2: 100, 3: 110, 4: 60 (7.2 h; load waits count).
    - A phase past its budget skips its remaining items marked (deferrable), last listed first, and records
      them as open.
    - Skipping is not a stop. Items not so marked are always done.
13. (2026-11-24, Hans: ruled as recommended) **Where the record goes.**
    - Progress per phase goes in this note. Phase 4 adds one entry and a status banner to milestone 1.
    - arun's review report is milestone 1's report, `completed/mlxf_milestone1_report.md` (`PLAN_DONE`).
    - No plan is moved and `README.md` is not edited: moving milestone 1 rewrites links in the parity
      plan, which the other run edits. Hans moves both plans and updates the README status line at the hold.
14. (2026-11-24, Hans: ruled as recommended) **The current tree's failures are findings.** A HEAD gate failure, such as
    parity Phase 1's GPU `expm1` bound (frozen on the M2), is recorded for the maintainer. It is neither
    fixed nor a stop. The measured base's gates are the run's gates.

Defaults taken without a question: the run name; the `scratch/keep/` layout and script names; the 10-thread
context team; the 5-s sample interval; the 20-minute load wait; the deferrable order.

## 4. Not in this plan

- Any source, test, script or build change (decision 1), including removing experiments and fixing the
  laptop's `arg_int` finding.
- Parity Phases 2–9, the M5 preparation follow-up's Phase 5 (combined integration after parity Phase 3),
  packaging checks, scientific examples, Metal kernels, SIMPLE's integration.
- Writing to `~/src/SIMPLE`, `~/src/mlx`, `~/src/mlx-c` or the maintainer's `~/src/mlx-fortran`; `brew`
  install or upgrade.
- `xcode-select`, `sudo` or any Xcode setup step (installing, the license, the first launch and developer
  access are the maintainer's); a programmatic GPU capture; recalibrating any frozen number.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement: bring-up | measured base: Debug and Release fast gate 8/8, 0 skips, 0 warnings, GPU opened; named suites on both devices; HEAD's release gate recorded |
| 1 | measurement: CPU denominators | SIMPLE built and gated; `block_prod` and `shiftmap` two clean runs at 30 threads, spread ≤ 5 %; team identity 0; case and grid files written |
| 2 | measurement: dense verdict | accuracy within the frozen 5a bounds on both devices; `time` rows; verdict, branch and memory |
| 3 | measurement: shift maps | Stage A complete; retention per decision 7; per-map verdict; accelerated pass or fail |
| 4 | documentation: report | report, Progress, history; `scripts/check_tree.sh` passes; diff only in the file table |

## 6. Acceptance

- Milestone 1's section 6 holds unchanged; its frozen values are in `src/test/mlxf_test_defs.f90` at
  `4706ecb`. Examples: the block's e_cpu 7.2525524e-7, gated at 2 e_cpu; n_cpu 2, gated at max(2 n_cpu, 5);
  and decision 17's map caps.
- **Spread** ≤ 5 % between two full-team invocations (*guessed*, as on the M2, where it was ≤ 0.67 %). A case
  above it is repeated once, then recorded with both spreads.
- **SIMPLE's `check`** is passed as SIMPLE defines it (its ruling R7): argmin and losses within tolerance.
  At the particles' own temperatures, draw differences are known in advance (104 of 320,000 at 2500_4 on
  the M2) and are recorded, not judged.
- **Reported, not gated**: NAX dispatch (decision 11's traces, in `scratch/keep/traces/`); the overlap rows; cutoff and evidence sensitivity; the 10-thread
  rows; the M2 ratios beside the M5's.

## 7. Common rules and stop conditions

Rules: milestone 1's section 7 (files, frozen numbers, house rules, timed runs, git). Builds go under the
run directory's `scratch/`; long jobs run under nohup with logs. Verdict inputs are copied to `scratch/keep/`. Every
number in Progress carries its log path.

Stop when:

- the session sees no GPU device, or `brew` reports another MLX pair than 0.32.4 / 0.8.0;
- `4706ecb` or SIMPLE `0a8b0903e` is missing, or the SIMPLE pin does not build or lacks a suite;
- the measured base fails a gate in full precision: fast gate, `recovery_half`, `polar_table`,
  `polar_shiftmap`, `polar_shiftmap_accuracy`, the 64,000-pair accuracy block, schedule identity;
- `suite=shiftmap` reports a map differing between teams, or `check` fails in the verdict's case;
- no oracle-passing configuration fits the budget;
- a phase needs a file outside the table, or any source edit.

Gates no ruling may waive: milestone 1's list (leak, diagnosis and recovery gates; byte identity of data
movement; generator coverage; the oracle comparisons on both devices; the frozen tolerances; schedule
identity), and no verdict from a flagged or gate-failing row.

## 8. Phases

`$X` is the measured base's Release test executable (`scratch/keep/base_release/test/mlxf_test_exec`), `$S`
SIMPLE's installed `simple_test_exec`, `$C` and `$G` `scratch/keep/polar_case.txt` and `shiftmap_grid.txt`,
all as absolute paths.

### Phase 0, bring-up and the launch audit (budget 60 min)

1. Record the machine as milestone Phase 0 step 1 did, plus the perflevels and the GPU's `architecture`
   from `unit_core`. Also record the run's HEAD and `git status`, and `otool -L` of `libmlxc.dylib`. Record
   the SHA-256 of this note and of the run spec's four files. Record whether `/Applications/Xcode.app`
   exists: its version (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version`),
   `xcode-select -p`, and whether `xcrun xctrace list templates` (under that `DEVELOPER_DIR`) lists "Metal
   System Trace". This decides decision 11's trace steps.
2. `git archive 4706ecb` into `scratch/keep/base_src`, with a SHA-256 manifest. Build Debug and Release
   from scratch in `scratch/keep/base_{debug,release}`, using `release_gate.sh`'s options:
   `-DBUILD_TESTS=ON -DMLXF_REQUIRE_GPU=ON -DMLXF_WERROR=ON -DFORTLS=OFF`, then `cmake --build -j 30` and
   `base_src/scripts/run_fast_gate.sh <tree>`. Apply the release gate's checks: no `SKIP` in
   `Testing/Temporary/LastTest.log`, "GPU devices: 1" in it, and no compiler warning in the build logs.
   Record per-entry times.
3. In both base trees, with `MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE
   OMP_THREAD_LIMIT=4`, run:
   - `mlxf_test_exec test=unit_core suite=recovery_half`;
   - `test=unit_kernels suite=polar_table device=all`;
   - `test=unit_kernels suite=polar_shiftmap device=all` (it covers all four graph combinations);
   - `test=unit_kernels suite=polar_shiftmap_accuracy device=all`.

   Record the assertion counts beside the recorded ones (`polar_table` 231, `polar_shiftmap` 1,308,
   `polar_shiftmap_accuracy` 144 at `4706ecb`); explain any difference.
4. Current tree: `scripts/release_gate.sh --jobs 30` in the repository copy (its `build_release_gate/` is
   git-ignored; `--allow-dirty` once this run's documentation edits exist, which the log lists), then `polar_shiftmap` and `polar_shiftmap_accuracy` on both devices in its Release tree.
   Results go to Progress; failures are findings (decision 14).
5. The launch audit: a Progress entry in [the follow-up](mlxf_m5_preparation.md) (its Phase 2). It names
   this note as the actual specification, with checksums; the verified pins; the corrections to the
   laptop's matrix (section 2's findings: the hand-built export, the team of 30, the budget, the OpenBLAS
   cache, traces in place of a capture option); and the inputs still to come from Phase 1.

Exit: machine record; base trees 8/8 with 0 skips, 0 warnings and a GPU; step 3 passes on both devices in
both builds; HEAD's result recorded; the follow-up's entry written.

### Phase 1, SIMPLE's CPU denominators (budget 100 min)

1. `git -C ~/src/SIMPLE archive 0a8b0903e` into `scratch/keep/simple_src`. Copy
   `~/src/SIMPLE/.deps/{downloads,numerics}` into its `.deps/`. Configure Release with
   `-DBUILD_TESTS=ON -DFORTLS=OFF` (record `USE_ARCHOPT`, `NICE`), build with `-j 30`, and install into the
   tree. Record whether OpenBLAS came from the cache or was rebuilt. Run `scripts/run_fast_gate.sh <tree>`
   and record failures per case. Run `suite=list`, and record the linked BLAS and FFTW. Every SIMPLE
   command sets `SIMPLE_PATH`, `PATH` and `SIMPLE_QSYS=local` to this tree.
2. Timed (decision 5), with `OPENBLAS_NUM_THREADS=1 MLX_ENABLE_TF32=0`:
   `$S test=polar_matching_bench suite=block_prod nspace=<1000|2500> nstates=<1|4> nptcls=2000 nthr=30`.
   Run all four cases, then all four again. Then 2500_4 at `nthr=10` once. Name the fastest B.
3. `$S test=polar_matching_bench suite=shiftmap nspace=2500 nstates=4 nptcls=2000 nthr=30` twice, then
   once at `nthr=10`. Keep the TSVs and the team-identity lines.
4. `suite=check nthr=30` and `suite=fills nthr=30` once each. (deferrable) `suite=neigh nthr=30` twice.
5. Write `$C` and `$G` from these TSVs (values as printed, not M2 history). In `$G`, `simple_commit` is
   the full pin, `fftw_plans` is `measure`, and `maps_per_s_t24` holds the two 30-thread rates. Record
   their SHA-256. Compare the geometry with the M2's: pftsz 182, nrots 364, kfrom 2, kto 62, kscreen 31;
   window nrho 4, nalpha 14, norder 16, ρ_max 4.3548; screen 11, 35, 32, 14.5161, prior 2.11151e-2. It is
   case-determined, so a difference is a finding to explain.

Exit: SIMPLE built and gated, every suite listed; two clean 30-thread runs per dense case and per map with
spread ≤ 5 % (one repeat allowed); team identity 0 for both maps; `check` and `fills` pass as section 6
defines; `$C` and `$G` written with checksums.

### Phase 2, dense scoring: milestone decision 14 (budget 100 min)

1. `$X test=bench_polar_table suite=accuracy cases=$C case=2500_4 form=b device=all`,
   then `form=c`, in full precision: the frozen 5a gates and schedule identity on both devices. Then both
   forms with `MLX_ENABLE_TF32=1 device=gpu`, which sets the accelerated mode's pass or fail.
2. Timed: `suite=time cases=$C cases_list=2500_4 form=b nthr=30` twice (the verdict family). Then:
   - `form=c` once in full precision;
   - `form=b` and `form=c` twice each with `MLX_ENABLE_TF32=1`;
   - (deferrable) `cases_list=1000_1,1000_4,2500_1 form=b` twice.
3. `suite=profile cases=$C case=2500_4 form=b bt=<64|best> rt=<250|best> nthr=30 device=gpu` twice in full
   precision, and once with `MLX_ENABLE_TF32=1` (decision 11's indirect evidence).
4. Traces (decision 11), if Xcode is available, after every timed row of this phase. Trace step 3's
   invocation at the verdict configuration with `form=b`, once with `MLX_ENABLE_TF32=0` and once with 1,
   into `scratch/keep/traces/dense_tf32_<0|1>.trace`. Read them as decision 11 says.
5. (deferrable) `suite=overlap ... outer=250 load=none` once, then with a separate
   `suite=stream seconds=60 nthr=30` process and `load=stream` (that invocation skips the load wait).
6. Memory for the verdict configuration: estimate, MLX peak, host staging, resident references (7.1 GB
   *derived* at 2500_4) and process peak, with aliases counted once. Reconcile, or say what is unexplained.
7. The verdict by decision 6, with its branch, the M2's ratio beside it, and decision 5's projection as a
   function of s and f. Then C's recommendation (decision 9).

Exit: step 1 passes in full precision on both devices; two clean verdict invocations; verdict, branch and
memory recorded; the accelerated mode reported with pass or fail; the dense traces read, or their absence or
failure recorded.

### Phase 3, the shift maps: Phase 5c's measurements and milestone decision 18 (budget 110 min)

Every command is `$X test=bench_polar_table suite=shiftmap cases=$C case=2500_4 grid=$G
maps=window,screen widths=all evidence=0 revision=4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47 device=gpu
nthr=30`, plus the keys named below. Full precision unless stated.

1. **Stage A.** `contraction=<1|2> hermitian=<0|1> ctile=16 otile=4 compact=1 ptiles=4,16,64`, all four
   graphs, interleaved by decision 8, two invocations each.
2. **Stage B.** For contraction 2 at Stage A's better Hermitian setting (by the screen) and its best ptile:
   one invocation each of `ctile=<4|8|16> otile=<1|4|8>` at `compact=1`. Then (deferrable) the same at
   `compact=0`. `ctile` and `otile` take one value each. The two best by the screen get a second invocation,
   each next to a control invocation.
3. Retention by decision 7, per map, with useful and executed radius-order slots. Name the verdict graph
   and canonical ptile per map.
4. The verdict per map by decisions 6 and 18, against Phase 1's 30-thread rows, with decision 18's caveats.
   The production-equivalent CPU cost is omitted (decision 10). Clean Stage A/B invocations serve as the
   verdict rows; otherwise two more.
5. Accelerated mode: `unit_kernels suite=polar_shiftmap` and `suite=polar_shiftmap_accuracy` with
   `device=gpu MLX_ENABLE_TF32=1` decide pass or fail. Then time the verdict graphs and the control twice
   with `MLX_ENABLE_TF32=1`.
6. Traces (decision 11), if Xcode is available, after every timed row of this phase. Trace the verdict
   graph at its canonical ptile, both maps, once per mode, into `scratch/keep/traces/maps_tf32_<0|1>.trace`.
   If the maps' verdict graphs differ, use the screen's. Read them as decision 11 says.
7. Memory per verdict row: host payload, prepared device memory, estimate, MLX peak, process peak, and the
   transient full-half staging (16 · nrots · band shells · half particles bytes). Reconcile.
8. (deferrable) The verdict graph once each with `widths=quarter`, `widths=none` and `evidence=1`, labelled
   synthetic, with no CPU ratio.
9. Refresh [the fusing note](mlxf_fusing_note.md) from the final requested-output profile: which stages
   dominate, and which remain kernel candidates. No speedup is assumed.

Exit: Stage A complete with two clean invocations per graph; retention per decision 7 with its numbers;
per-map verdict, branch and caveats; the accelerated mode's pass or fail; the map traces read, or their
absence or failure recorded; memory; fusing note refreshed.

### Phase 4, milestone 1 Phase 7: summary, report, hold (budget 60 min)

1. Milestone 1's Progress: the interim summary of its Phase 7 step 1. It covers what was proved, both
   verdicts and their branches, peak memory, the kept formulation and tile plans, numerical sensitivity
   per temperature, profile gaps, and what SIMPLE's integration would take.
2. Milestone 1's status banner reads: Phases 5c (performance exit), 6 and 7 delivered by this run; at
   the hold. Update this note's banner, the index row in `doc/implementation_notes/README.md`, and the
   history.
3. The report `completed/mlxf_milestone1_report.md`, in the order of `doc/how2s/how2write_agent_plans.md`
   section 8. It cites every Progress entry. Its follow-ups name their files: experiments and C to remove,
   NAX dispatch as the traces left it (with the trace paths), s/f/w, and moving both plans and the README
   line (decision 13).
4. Setup-guide corrections found by the run (`doc/how2s/how2set_up_dev.md`), if any. MLX questions, if
   any, go to `doc/collaboration/apple_questions.md`.
5. `scripts/check_tree.sh` passes in the repository copy; `git status` shows only file-table paths.

Exit: the report exists and cites every entry; milestone 1's Progress and banner; history; the static gate
passes; no file outside the table.

### File table

| File | What | Phases |
| --- | --- | --- |
| `doc/implementation_notes/planned/mlxf_m1_m5.md` | this note: Progress, banner | each |
| `doc/implementation_notes/completed/mlxf_milestone1_report.md` (new) | milestone 1's report, arun's review report | 4 |
| `doc/implementation_notes/planned/mlxf_milestone1.md` | Progress entry and status banner | 4 |
| `doc/implementation_notes/planned/mlxf_m5_preparation.md` | the launch audit's Progress entry | 0, 4 |
| `doc/implementation_notes/planned/mlxf_fusing_note.md` | the fresh profile and remaining candidates | 3 |
| `doc/implementation_notes/README.md` | the index row | 4 |
| `doc/how2s/how2set_up_dev.md` | M5 setup corrections, if needed | 0, 4 |
| `doc/collaboration/apple_questions.md` | questions met, if any | each |
| `doc/history/2026-11.md` | the delivered batch | 4 |

## Progress

(one entry per phase, written by the run)

### Phase 0, bring-up and the launch audit, 2026-11-24 02:21–02:27 EST

Machine: Apple M5 Ultra (`HanssMacStudio`), macOS 27.2.1 (26B131). Run HEAD
`af0c23fefbaf0fb2b282a454bdda7a96d473c330` (`0cfb128` plus the commit that added this note), `git status`
clean at start. Measured sources: mlx-fortran `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47`, SIMPLE
`0a8b0903eee151700305399e8e3ff53c2c21caae`. Rulings: none. Load 2.1 to 2.7 throughout (nothing timed).
Evidence root `/Users/hael/agent_runs/mlxf_m1_m5/scratch/keep/` (below `keep/`).
Files changed: this note (Progress), `mlxf_m5_preparation.md` (the launch audit's entry).

1. **Machine record** (`keep/phase0_machine.txt`, *exact*): 30 cores, perflevel0 "Super" 10, perflevel1
   "Performance" 20 (L2 16 MiB and 8 MiB); 64-core GPU, Metal 4, architecture `applegpu_g17d` (from
   `unit_core`); 103,079,215,104 B. gcc/gfortran 16.2.0 (CMake selects `gfortran-16`/`gcc-16`), CMake 4.5.1,
   Python 3.15.2 (`MLXF_PYTHON3`); brew mlx 0.32.4, mlx-c 0.8.0, fftw 3.3.11. `libmlxc.dylib` links
   `/opt/homebrew/opt/mlx/lib/libmlx.dylib`, Metal, Foundation, QuartzCore, Accelerate; the base executables
   link brew's `libmlxc` by path, so a `brew upgrade` during the run would change the measured binary.
   SHA-256: this note at start `070eaf15…a2c5`; `spec/phases.md` `145bb8f8…302e`, `prompt.md` `16003163…20b1`,
   `rulings.md` `49d48252…6433`, `run.conf` `30321134…73c3` (full values in the record).
   **Xcode 27.2 (27B52) is installed**; `xcode-select -p` stays `/Library/Developer/CommandLineTools`;
   `xctrace` 27.2 lists "Metal System Trace". Decision 11's traces therefore run in Phases 2 and 3.
2. **Measured base**: `git archive 4706ecb` into `keep/base_src` (manifest `keep/base_src.sha256`, 121 files
   plus the `.claude/skills` symlink; manifest SHA-256 `98c6ff16…ff02`). Debug and Release configured with
   `-DBUILD_TESTS=ON -DMLXF_REQUIRE_GPU=ON -DMLXF_WERROR=ON -DFORTLS=OFF`, built with `-j 30` (72 objects
   each, 0 warnings: `keep/phase0_logs/base_{debug,release}_build.log`). `run_fast_gate.sh`: `check_tree`
   passes on the export without `.git`; 8/8 in both, 9.0 s each, 0 `SKIP`, "GPU devices: 1"
   (`keep/phase0_logs/base_*_fast_gate.log`, `base_*_LastTest.log`, `base_*_timing.txt`). Per entry, Debug /
   Release, s (*measured*): unit_array 9.03/9.01, unit_kernels 6.52/6.47, unit_compile 0.62/0.57,
   object_contracts 0.41/0.41, unit_core 0.32/0.28, unit_ops 0.30/0.27, unit_linalg 0.14/0.63, unit_fft
   0.14/0.29. Executables' SHA-256 in `keep/phase0_logs/base_exec.sha256` (Release `2787a932…d04b`).
3. **Named suites on both devices, both base trees** (`keep/phase0_step3/*.log`, full precision, the
   given OpenMP variables): `recovery_half` 12/12 (14,930 and 7,465 rows of 4 MiB; process peak
   31,338,627,072 B *measured*, matching section 2's 31.3 GB); `polar_table` 231/231; `polar_shiftmap`
   1,308/1,308; `polar_shiftmap_accuracy` 144/144. The counts equal the recorded ones; no difference to
   explain.
4. **HEAD** (`keep/phase0_step4/`): `scripts/release_gate.sh --jobs 30` on the clean tree before any edit:
   `RELEASE GATE PASSED: af0c23f`, Debug and Release 8/8, 0 skips, GPU devices 1, no warning
   (`release_gate_af0c23f.log`). GPU float32 `expm1` errors 168.2 eps32 at seeds 1–3, the Q20 defect at the
   M2's size (167.9), inside HEAD's committed bound, so not a failure here. In HEAD's Release tree:
   `polar_shiftmap` 1,364/1,364 (the laptop's 56 added assertions) and `polar_shiftmap_accuracy` 144/144,
   `device=all`.
5. **Launch audit**: entry written in [the follow-up](mlxf_m5_preparation.md), Progress.

Findings for later phases (no decision changed):

- At `4706ecb`, `suite=shiftmap` reads no `nthr` (only `time`, `profile`, `overlap` and `stream` do;
  `accuracy` uses teams 1 and 24 built in). Phase 3's `nthr=30` is inert: the map timing is the GPU with one
  submitting thread, and only the untimed synthetic data uses `omp_get_max_threads`. The sidecar records
  it as passed and ignored.
- `revision=` is only echoed into the shift-map rows, never checked: Phase 3 types it in full.

Exit: machine record yes; base trees 8/8, 0 skips, 0 warnings, GPU 1, both builds; step 3 passes on both
devices in both builds; HEAD's gate recorded (passed); the follow-up's entry written. Base trees kept in
`keep/base_{debug,release}` for every later phase; HEAD's `build_release_gate/` deleted after its logs
were copied.

What it means, in short: the M5 runs the measured base and HEAD cleanly on both devices with the recorded
assertion counts, Xcode's tracer is available for decision 11, and nothing blocks Phase 1.

### Phase 1, SIMPLE's CPU denominators, 2026-11-24 02:26–03:19 EST

Machine: the M5 Ultra as in Phase 0. Sources: SIMPLE `0a8b0903eee151700305399e8e3ff53c2c21caae` (exported to
`keep/simple_src`), mlx-fortran `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47` (not run in this phase). Rulings:
none. Files changed: this note (Progress). Evidence root as in Phase 0 (`keep/` below); every invocation's
directory holds `stdout.log`, `time_stderr.log` (`/usr/bin/time -l`), `samples.tsv` and `sidecar.txt`.

1. **SIMPLE built and gated.** `cmake ... -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=ON -DNICE=OFF
   -DUSE_ARCHOPT=ON -DFORTLS=OFF` in `keep/simple_release`, `make -j30`, installed into the tree
   (`keep/phase1_logs/simple_{configure,build,install}.log`). OpenBLAS 0.3.34 **came from the copied cache**
   ("Reusing the cached OpenBLAS; no OpenBLAS build is scheduled"), linked statically, OpenMP flavour; FFTW
   is brew's 3.3.11 (`libfftw3`, `libfftw3f`, `libfftw3f_threads`; `keep/phase1_logs/simple_otool.txt`).
   0 compiler warnings. Fast gate 15/15, 8.6 s, no failure (`simple_fast_gate.log`). `suite=list`: per_pair,
   replica, blocked, states_inner, matrix, matrix_t, block_prod, per_pair_cc, check, identity, fills, neigh,
   shiftmap (`keep/phase1_runs/list_a1/stdout.log`). The banner's "SIMPLE Git Commit" is empty (an export has
   no `.git`); the sidecars carry the full pin. Every command set `SIMPLE_PATH` and `PATH` to this tree and
   `SIMPLE_QSYS=local`, `OPENBLAS_NUM_THREADS=1`, `MLX_ENABLE_TF32=0`, and left `OMP_*` unset.
2. **The timing wrapper** of decision 5 is `keep/timed_run.sh`; the driver of this phase's sequence is
   `keep/phase1_logs/timed_phase1.sh`. Decision taken under delegation: "other processes" is the sum of
   `%CPU` over every process except the timed process tree and the sampler's `top`, from `top -l 2 -s 5`
   (the second sample, a true 5-s interval), for both the wait threshold (250 %) and the flag (400 %).
   Reason: per-process `ps` values are decaying averages, and a sum is the stricter reading. The run's own
   heavy jobs count as "other" in the wait; the 1-minute load includes the previous timed process, so most
   waits were 1 to 2 minutes of its decay.
3. **All 17 timed invocations are clean at the first attempt** (largest other-process sample 169.5 %, in
   `bp_2500_1_t30_r1`; load before each 1.8 to 3.9). `keep/phase1_logs/summary_final.txt`
   (from `summarize_phase1.py`) holds the tables below.
   - **`block_prod`, nthr 30, measured plans** (*measured*, best of 3 after a warm-up; wall s, run 1 / run 2,
     spread = difference over the faster):

     | Case | B 4 | B 8 | B 16 | B 16 pairs/s, faster | spread at B 16 |
     | --- | --- | --- | --- | --- | --- |
     | 1000_1 | 1.3522 / 1.3595 | 0.8021 / 0.8062 | 0.5427 / 0.5454 | 3.68558e6 | 0.50 % |
     | 1000_4 | 5.3790 / 5.3787 | 3.1546 / 3.1508 | 2.1463 / 2.1354 | 3.74637e6 | 0.51 % |
     | 2500_1 | 3.4136 / 3.3787 | 2.0101 / 1.9909 | 1.3586 / 1.3534 | 3.69445e6 | 0.38 % |
     | 2500_4 | 13.5068 / 13.4863 | 7.9419 / 7.9411 | 5.3909 / 5.3291 | 3.75296e6 | 1.16 % |

     Every spread is ≤ 1.16 % (exit ≤ 5 %, no repeat needed). **The fastest measured B is 16 in every case
     and both runs** (milestone decision 14's CPU configuration). R is 32 throughout. At 2500_4 the 2.0e7
     pairs take 5.33 s here against the M2's 8.70 s at 24 threads (*measured*, context). The driver's
     half-team (15) and one-thread 200-particle rows are kept in the TSVs and not compared.
     Runs: `keep/phase1_runs/bp_<case>_t30_r<1|2>_a1/polar_matching_bench.tsv`.
   - **Context, nthr 10** (the Super cores, never a verdict input), 2500_4 at B 16: 12.3565 s, 1.61859e6
     pairs/s, 0.43 of the 30-thread rate (*derived*) (`bp_2500_4_t10_a1`).
   - **`shiftmap` 2500 × 4, nthr 30, measured plans** (*measured*; maps/s run 1 / run 2): window
     1.08994e5 / 1.08259e5 (wall 0.2936 / 0.2956 s, spread 0.68 %); screen 2.05392e4 / 2.05274e4 (wall
     1.5580 / 1.5589 s, spread 0.06 %). **Team identity: "0 maps differ"** for both maps in both runs (64
     particles × 16 candidates, 1 against 30 threads), and at 10 threads. Under measured plans no identity
     file is written, as decision 22 defines. nthr 10 context: window 4.31294e4, screen 8.26743e3 maps/s.
     Runs: `keep/phase1_runs/sm_t30_r<1|2>_a1/`, `sm_t10_a1/`.
4. **`check` nthr 30** (`keep/phase1_runs/check_t30_a1/`, 472 s): six cases, rc 0.
   - `polar_matching_check.tsv`: every layout reproduces its own one-thread rows (0 differing);
     per_pair, replica, blocked and states_inner equal production byte for byte; matrix and matrix_t differ
     by at most 4.05e-7 relative, with at most 6 minimising rotations differing (6 of 320,000 at 2500 × 4).
   - `polar_block_check.tsv`, block_prod against production's per-pair draws: losses within 4.05e-7
     relative (bound 1e-6), 0 invalid mismatches, entries identical across 30 threads in five repeats and
     across B 4, 8, 16. At the argmin (temperature scale 1e25) the rotation differs in 0 to 4 pairs (4 of
     320,000 at 2500 × 4, allowed 6): within tolerance; at a tenth of the temperatures 0 to 6 (6 allowed):
     within tolerance.
   - At the particles' own temperatures the drawn rotation differs in 22 to 107 pairs (**107 of 320,000 at
     2500 × 4**; the M2 had 104) and the TSV says `within_tolerance` no. As section 6 says, this is known in
     advance and recorded, not judged: **`check` passes as SIMPLE's R7 defines it.**
   - **`fills` nthr 30** (`fills_t30_a1/`, 187 s): eight routes, 96 rows, 0 differences in all seven
     categories, "the fill harness gives identical rows, selections and extras in every configuration".
   - **`neigh` nthr 30, twice** (`neigh_t30_r<1|2>_a1/`, 231 s each): all 24 check rows `within_tolerance`
     yes and `identical` yes; best rotation differs in at most 7 (allowed 15) at 756,000 representative
     pairs. Block wall for representatives 0.107 to 0.222 s, block over per-pair wall 0.71 to 0.79
     (representatives), 3.2 to 3.6 (members), 4.0 to 7.7 (cones); run-to-run within 1.5 %.
5. **`$C` and `$G`** written by `summarize_phase1.py ... write` from these TSVs, values as printed:
   `keep/polar_case.txt` (SHA-256 `90a974fa0842a35d5eee6fe3a07a37405bbbd5849ed3eb7818c129d7dacff1d9`),
   four `[case]` blocks; `keep/shiftmap_grid.txt` (SHA-256
   `aa05ca2773e6eb5d688dcd75ef1756a24940bea8d079c7daf59cdf77bc902eca`), `simple_commit` the full pin,
   `fftw_plans = measure`, `maps_per_s_t24` the two 30-thread rates per map. **The geometry equals the
   M2's** (*exact*): pftsz 182, nrots 364, kfrom 2, kto 62, kscreen 31; window nrho 4, nalpha 14, norder
   16, ρ_max 4.3548; screen 11, 35, 32, 14.5161, prior 2.11151e-2; nrefs = nspace × nstates; 2,000
   particles.

Exit: SIMPLE built and gated, every suite listed; two clean 30-thread runs per dense case (spread ≤ 1.16 %)
and per map (≤ 0.68 %), no repeat; team identity 0 for both maps; `check` and `fills` pass as section 6
defines (draws at own temperatures recorded); `neigh` twice, done; `$C` and `$G` written with checksums.
No job left running.

What it means, in short: on the M5 Ultra's 30 cores SIMPLE scores the verdict case at 3.75e6 pairs/s
(B 16) and builds 1.09e5 window and 2.05e4 screen maps/s, reproducibly within 1.2 %; these are the
denominators of Phases 2 and 3, with the same geometry as on the M2.

### Phase 2, dense scoring: milestone decision 14, 2026-11-24 03:19–03:51 EST

Machine: the M5 Ultra as in Phase 0. Sources: mlx-fortran `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47` (`$X`, the
Release base tree, SHA-256 `2787a932…d04b`), SIMPLE `0a8b0903eee151700305399e8e3ff53c2c21caae` (Phase 1's
rows). Inputs `$C` (`90a974fa…f1d9`). Rulings: none. Files changed: this note (Progress). Evidence under
`keep/phase2_runs/` (one directory per invocation with `sidecar.txt`, `samples.tsv`, `/usr/bin/time -l`) and
`keep/phase2_logs/` (the driver scripts and `summarize_time.py`). The verdict rule is decision 6 as written,
fixed before the first row. Every timed invocation is clean at its first attempt (largest other-process
sample 66.8 %, load before 1.2 to 2.3).

1. **Accuracy** (`keep/phase2_runs/acc_*/stdout.log`, untimed, block 64 × 1,000 on seed 2, frozen bounds
   2 e_cpu = 1.4505e-6 and max(2 n_cpu, 5) = 5):
   - Full precision, `device=all`, **form B: PASS 192/192**; CPU row error 6.654e-7, GPU 6.514e-7, 0
     rotations differing on both; the tile-shape, partial-edge, position and list variants within bounds;
     schedule identity (three repeats, outer batches 32/16, teams 1/24, two slots) holds on both devices.
     **Form C: PASS 192/192**; CPU 1.261e-6, GPU 1.324e-6, 0 rotations differing.
   - The CPU calibration printed beside the gates (reported, not recalibrated: section 2's frozen-numbers
     rule): e_cpu 7.2525524211e-7 (frozen 7.2525524223e-7, *measured* on the M2) and **n_cpu 3** (frozen 2).
     The judged bound stays max(2·2, 5) = 5, and the judged counts are 0, so nothing depends on it.
   - Reported, not gated: GPU form B's entries differ from the canonical run by global pair for reversed
     particles in 2,872 of 64,000 (CPU 0; form C 0), inside the row and draw gates.
   - The verdict configuration's own gates (`acc_tf32_0_form_b_all_bt64_rt250/`, `bt=64 rt=250`): PASS
     192/192, the same errors. Decision taken under delegation: step 1 runs the block's default tile
     (B 16, R 250); since decision 6 asks for a configuration "that passes its gates", the chosen one was
     judged at its own tile as well.
   - **Accelerated mode, `MLX_ENABLE_TF32=1 device=gpu`: FAIL** for both forms, 14 of 93 assertions:
     form B row error 4.223e-4 (291 × the bound) with 38 rotations differing; form C 8.970e-4 with 46.
     The row, draw-validity and identity assertions hold; only the frozen error and rotation bounds fail.
     **The accelerated mode does not count** for any verdict (decision 6).
2. **`suite=time` 2500 × 4** (`keep/phase2_logs/summarize_time.py`, rates in pairs/s, *measured*, best of 3
   after a warm-up, both halves from prepared memos to entries in Fortran arrays, `nthr=30`):
   - **Full precision, form B, twice** (`time_b_tf0_r{1,2}_a1/bench_polar_table.tsv`): 15 configurations
     timed, 5 pruned as B above the 1,000 particles per half, 3 pruned beyond the 25.8 GB budget (500 ×
     2,500, 1,000 × 1,000, 1,000 × 2,500). **Best by the slower of two: B 64, R 250, 1.76686e7 / 1.76097e7
     (spread 0.33 %)**; next 64 × 500 (1.69682e7), 250 × 64 (1.68615e7), 500 × 64 (1.65728e7); worst timed
     250 × 2,500 (1.45409e7). Every configuration's two runs agree within 1.63 %.
   - Form C once, full precision (`time_c_tf0_r1_a1/`): best 64 × 500 at 1.62004e7, 64 × 250 at 1.61397e7,
     0.92 of B.
   - Accelerated, twice each (rows reported only, the mode fails its gates): form B best 64 × 250,
     1.78014e7 / 1.77906e7 (+1.0 % over full precision); form C best 64 × 250, 1.73824e7 / 1.73795e7.
   - (deferrable, done) The other cases, form B, twice (`timeo_b_tf0_r{1,2}_a1/`): best 64 × 250 in each;
     1000_1 1.62327e7 / 1.62072e7, 1000_4 1.77160e7 / 1.77235e7, 2500_1 1.78399e7 / 1.78494e7 (spreads
     ≤ 0.16 %). Against Phase 1's faster `block_prod` B 16: 4.40, 4.73 and 4.83 (*derived*, context).
3. **Profile** at the verdict configuration, which is the canonical plan (B 64, R 250), so step 3's
   `<64|best>` and `<250|best>` are one row (`prof_b_tf{0,1}_r*_a1/bench_polar_table_profile.tsv`, s,
   both halves, with a barrier after every stage):

   | mode | wall | terms | products | transform | distances and draw | concat | copy-out, host | prep | cold first |
   | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
   | full, run 1 | 1.9312 | 0.0160 | 0.5613 | 0.4196 | 0.9037 | 0.0028 | 0.0277 | 1.0932 | 2.0905 |
   | full, run 2 | 1.9571 | 0.0113 | 0.5747 | 0.4229 | 0.9196 | 0.0029 | 0.0257 | 1.0972 | 2.1050 |
   | accelerated | 1.9402 | 0.0098 | 0.5387 | 0.4291 | 0.9342 | 0.0028 | 0.0256 | 1.0835 | 2.0950 |

   The barriers cost 0.8 s against the 1.13 s unbarriered pass. The distances and draw (compiled) are the
   largest stage, then the products and the inverse FFT; the accelerated mode shortens the products by
   4 % (*measured*, indirect evidence only) and leaves the total unchanged. Against the M2 (3.04 s, products
   0.67, transform 0.69, distances 1.60) every stage is faster, the distances most (1.8 ×).
4. **Traces** (decision 11; after every timed row): `keep/traces/dense_tf32_{0,1}.trace` (exit 0 both,
   223 and 158 MB), read through `xctrace export --toc` and the `metal-shader-profiler-shader-list` table
   filtered to the benchmark process (`keep/traces/dense_traces_reading.txt`):
   - full precision: `steel_gemm_fused_nn_float32_float32_bm64_bn64_bk16_…` only, no `_nax_` kernel;
   - accelerated: `steel_gemm_fused_nax_nn_float32_float32_bm64_bn128_bk512_…` only.
   **NAX dispatch is observed for the dense workload in the accelerated mode, and not in full precision**
   (as the setup guide says `MLX_ENABLE_TF32=0` should); no question for Apple arises.
5. (deferrable, done) **Overlap** (`ovl_b_tf0_{none,stream}_a1/bench_polar_table_overlap.tsv`, canonical
   plan, outer 250): no load, synchronous 1.1420 s, two slots 1.1141 s (2.4 % faster; hidden share
   0.0256); under a concurrent `suite=stream seconds=60 nthr=30` (554.5 GB/s triad, `stream_load/`, which
   outlived the overlap invocation: 03:41:46–03:42:46 against an end at 03:42:18), 1.3478 and 1.3052 s: the
   GPU path slows by 18 % under a 30-thread memory-streaming load. Decision taken under delegation: the
   wrapper gained opt-in `NOWAIT`, `EXCLUDE_PIDS` and `MAX_ATTEMPTS` so the loaded row skips the load wait,
   does not count the deliberate load as interference and runs once (the Phase 1 version is kept as
   `keep/phase2_logs/timed_run.sh.phase1`; the defaults are unchanged).
6. **Memory at the verdict configuration** (one configuration per invocation: `mem_b_tf0_64x250_a1/`;
   region split `mem_regions/{vmmap,footprint}_{1,2}.txt` taken while it scores; RSS timeline
   `mem_timeline/rss.txt`):
   - Estimate (pruning formula) 7.918e9 B (*exact* from the formula): resident reference tiles 7.144e9
     (*derived*: 2 halves × 4 × 61 shells × 10,000 × 183 bins × 8 B, the M2's 7.1 GB), host-staged inputs
     of a call 0.448e9 (particle terms of 1,024 padded particles and the variates), one tile's scratch
     0.326e9.
   - MLX peak (active, after the warm pass) 10.257e9 B (*measured*), 2.34 GB above the estimate: the
     estimate counts one tile's scratch while several tiles are queued at once (the M2's finding at small
     tiles), about 7 tiles' worth here (*derived*).
   - Process (*measured*): peak footprint 21.05e9 B, maximum RSS 18.04e9 B. The RSS timeline is 4.01 GiB
     through data generation, 12.3 GiB during preparation and a 16.8 GiB plateau from the first scoring
     pass to the exit, so the peak is steady scoring, not a preparation transient.
   - Reconciled by region at the plateau (`footprint`): IOAccelerator (graphics) dirty 9,952 MB, the Metal
     buffers counted in the footprint, against MLX's active peak 10.26e9 B; Malloc Large 9,886 MB, of which
     4.2 GiB live (the benchmark's synthetic data, 3.93e9 B *derived*: memos 3.572e9 and particle terms
     0.357e9, plus the output tables) and 5.4 GiB freed host blocks the malloc zone keeps dirty (`vmmap`
     "Malloc Large (empty)": host copies made by the benchmark's data handling and preparation, released
     but not returned); 0.2 GB owned unmapped graphics memory. **No unexplained gap**: every GB of the
     footprint is in a named region; the part beyond the pipeline's live bytes is freed host memory.
   - Budget: the pipeline's live bytes (MLX peak 10.26e9 plus host staging) are far inside the 25.8 GB
     budget, and so is the single-configuration process peak (21.05e9). A whole 25-configuration sweep
     peaks at 27.16e9 B (`time_b_tf0_r*`), above the budget, because it holds the freed host blocks and
     the larger configurations' buffers; the budget applies per configuration, as milestone decision 13
     defines it.
7. **The verdict (decision 6, milestone decision 14).** GPU: B 64, R 250, formulation B with the compiled
   tail, full precision, the slower of two 1.76097e7 pairs/s; CPU: `block_prod` B 16 at 30 threads, the
   faster of two 3.75296e6 (Phase 1). **Ratio 4.69 (*derived*); spreads 0.33 % (GPU) and 1.16 % (CPU), far
   from the 2.0 threshold; memory reconciled. Branch: go.** The M2's canonical plan is the chosen
   configuration here, so the canonical row is the verdict row. Beside it (context, never the verdict): the
   M2 Ultra's 4.29 to 4.55 against its own 24 cores (section 1); the accelerated mode would give 4.74 but
   fails its gates. Decision 5's projection, with g = 4.69 and s, f unmeasured (decision 10),
   `1 / (1 - s f + s f / g)`:

   | s \ f | 0.10 | 0.23 | 0.50 | 0.80 | 1.00 |
   | --- | --- | --- | --- | --- | --- |
   | 0.20 | 1.016 | 1.038 | 1.085 | 1.144 | 1.187 |
   | 0.37 | 1.030 | 1.072 | 1.170 | 1.304 | 1.411 |
   | 0.50 | 1.041 | 1.099 | 1.245 | 1.459 | 1.649 |
   | 0.80 | 1.067 | 1.169 | 1.459 | 2.015 | 2.699 |
   | 1.00 | 1.085 | 1.221 | 1.649 | 2.699 | 4.692 |

   The design plan's pre-production context values (s 0.37, f 0.23) give 1.07; it is not a measurement
   of the production scorer.
8. **Formulation C (decision 9): recommended for removal.** In the accelerated mode it does not beat B
   (1.73795e7 against 1.77906e7, 0.98 ×, and the mode fails its gates); in full precision it is 0.92 × B.

Exit: step 1 passes in full precision on both devices (B and C, and B at the verdict tile); two clean
verdict invocations (spread 0.33 %); verdict 4.69, branch go, memory reconciled; the accelerated mode
reported as fail (with its rates); the dense traces read (NAX in the accelerated mode only). Deferrable items
2 (other cases) and 5 (overlap) done. No job left running.

What it means, in short: on the M5 Ultra in full precision the GPU scores the verdict case 4.69 times as fast
as SIMPLE on all 30 cores, a go; the accelerated mode does use NAX but buys 1 % and breaks the frozen
accuracy bounds, so it is not worth having here; formulation C can go.

### Phase 3, the shift maps: Phase 5c's measurements and milestone decision 18, 2026-11-24 03:51–04:31 EST

Machine: the M5 Ultra as in Phase 0. Sources: mlx-fortran `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47` (`$X`, the
Release base tree), SIMPLE `0a8b0903eee151700305399e8e3ff53c2c21caae` (Phase 1's rows). Inputs `$C`
(`90a974fa…f1d9`) and `$G` (`aa05ca27…2eca`; its `maps_per_s_t24` holds Phase 1's two 30-thread rates, and
the rows' `cpu_maps_per_s` is the faster of them). Rulings: none. Files changed: this note (Progress) and
[the fusing note](mlxf_fusing_note.md) (status and a new section 1a). Evidence under `keep/phase3_runs/` (one
directory per invocation, with `sidecar.txt`, `samples.tsv`, `/usr/bin/time -l`) and `keep/phase3_logs/`
(the driver scripts `stage{A,B,C}.sh`, `mem_regions.sh`, `summarize_maps.py` and its outputs
`stage{A,B}_summary.txt`). **All 35 timed invocations are clean at their first attempt** (largest
other-process sample 153.7 %, 1-minute load before 1.50 to 3.43). As section 2 found, `nthr=30` is passed
and ignored by this suite; the timed path is the GPU with one submitting thread.

1. **Stage A** (`A_c{1,2}h{0,1}_r{1,2}_a1`, order control, (1,1), (2,0), (2,1), then the reverse; maps/s,
   *measured*, best of 3 after a warm-up; slower / faster of two; the screen at ptile 64 is pruned for every
   graph, its estimate 46.0 GB beyond the 25.8 GB budget):

   | graph (contraction, Hermitian) | screen ptile 4 | screen ptile 16 | window ptile 4 | window ptile 16 | window ptile 64 |
   | --- | --- | --- | --- | --- | --- |
   | **control (1, 0)** | **1.99418e4 / 1.99643e4** | 1.89284e4 / 1.89582e4 | 5.03617e4 / 5.04897e4 | **7.44959e4 / 7.47856e4** | 7.06305e4 / 7.07359e4 |
   | (1, 1) | 1.92835e4 / 1.94172e4 | 1.83806e4 / 1.84618e4 | 4.87965e4 / 4.95520e4 | 7.42122e4 / 7.43374e4 | 7.17312e4 / 7.19499e4 |
   | (2, 0) | 8.32950e3 / 8.54415e3 | 1.22573e4 / 1.23773e4 | 1.79095e4 / 1.85809e4 | 3.66067e4 / 3.71510e4 | 4.90258e4 / 4.90661e4 |
   | (2, 1) | 8.25218e3 / 8.34476e3 | 1.20559e4 / 1.20612e4 | 1.82170e4 / 1.83628e4 | 3.67020e4 / 3.67060e4 | 4.96262e4 / 4.97012e4 |

   Spreads 0.01 to 3.75 % (the largest (2, 0) at window ptile 4). Radius-order slots, useful / executed: the
   window 43 / 68 and the screen 229 / 363 for contraction 1; contraction 2 with compact radii executes
   49 and 245 (`active_radius_orders`, `executed_radius_orders`).
2. **Stage B** (`B_c2h0_ct*_ot*_cp*_r1_a1`, `stageB_summary.txt`): contraction 2 at Hermitian 0 (better
   by the screen: 1.22573e4 against 1.20559e4 at ptile 16) and ptile 16 (its best on the screen). One
   invocation per `ctile` × `otile`, at compact 1 and then (deferrable, done) compact 0. The order tile
   dominates: on the screen otile 1 / 4 / 8 give 4.2–7.4e3 / 0.92–1.23e4 / 1.13–1.46e4 maps/s; compact 0
   and 1 agree within 2.4 % on the screen (window up to 6.5 %). Executed slots: compact 1 runs 229, 245 and
   265 on the screen for otile 1, 4 and 8 (window 43, 49, 57); compact 0 runs all 363 (68). The two best
   by the screen, run a second time each next to a control (`Bc_ctrl_r{3,4}_a1`): ctile 16, otile 8,
   compact 1: screen 1.45048e4 / 1.45868e4, window 4.29629e4 / 4.30429e4; compact 0: screen 1.45340e4 /
   1.45575e4, window 4.31487e4 / 4.38055e4. The control's third and fourth invocations agree with Stage A
   (screen ptile 4 1.99446e4 and 1.99495e4; window ptile 16 7.43792e4 and 7.52858e4).
3. **Retention (decision 7): no alternative is retained on either map.** The rule is an alternative's
   slower-of-two above 1.30 times the control's faster-of-two. Each graph at its best ptile against the
   control at its best (*derived*):

   | alternative | screen | window |
   | --- | --- | --- |
   | (1, 1) Hermitian | 1.92835e4 / 1.99643e4 = 0.966 | 7.42122e4 / 7.47856e4 = 0.992 |
   | (2, 0) Stage A | 1.22573e4 / 1.99643e4 = 0.614 | 4.90258e4 / 7.47856e4 = 0.656 |
   | (2, 0) Stage B best, ctile 16, otile 8 | 1.45340e4 / 1.99643e4 = 0.728 | 4.31487e4 / 7.47856e4 = 0.577 (ptile 16 only) |
   | (2, 1) | 1.20559e4 / 1.99643e4 = 0.604 | 4.96262e4 / 7.47856e4 = 0.664 |

   At equal ptiles the best alternative is (1, 1) on the window at ptile 64: 1.014 times the control there.
   **All three alternatives are negative results recommended for removal.** That means the real-weights
   contraction, the Hermitian direction transform, the candidate/order tiles and the compact radii, which
   only contraction 2 uses. The files are `src/test/mlxf_kernel_polar_table_shiftmap.f90`, its
   `_tester.f90`, `src/test/mlxf_bench_polar_table.f90` (the `contraction`, `hermitian`, `ctile`, `otile`
   and `compact` keys) and `src/test/mlxf_test_defs.f90` (`POLAR_MAP_FORMS`, `POLAR_MAP_CTILES`,
   `POLAR_MAP_OTILES`). Removing them is the maintainer's follow-up (decision 1).
   **The verdict graph is the control on both maps; the canonical ptile is 4 on the screen and 16 on the
   window.**
4. **The verdict per map (decisions 6 and 18)**, from the Stage A control pair (the verdict rows), against
   Phase 1's faster 30-thread SIMPLE rate:
   - **screen: 1.99418e4 / 2.05392e4 = 0.971; negative.** Spreads 0.11 % (GPU) and 0.06 % (CPU); the
     distance to 1.0 is 2.9 %, outside both, so it is not at the boundary. With all four control
     invocations the slower is the same row.
   - **window: 7.44959e4 / 1.08994e5 = 0.683; negative.** Spreads 0.39 % and 0.68 %. With all four control
     invocations, 7.43792e4 gives 0.682.
   - Context, never the verdict: on the M2 the GPU built the screen and the window at 1.69 and 1.10 times
     SIMPLE's previous kernel at 24 threads (section 1). SIMPLE's committed kernel is 1.28 and 1.16 times
     faster on its own record, and runs here on 30 cores.
   - Decision 18's caveats stand beside the numbers. SIMPLE plans with `FFTW_MEASURE` but without
     production's wisdom file. It builds maps back to back with warm per-thread arrays, while production
     interleaves them with block scoring. Its width column is production's worst case: production skips
     the width above the best loss, so `w` is unmeasured. The production-equivalent CPU cost
     `us_construct + us_select + w * us_reduce` is omitted (decision 10), and so is the ratio it would give.
     Preparation is reported apart: references 0.82 s (screen) and 1.19 s (window); maps' tables 0.33 to
     0.36 s; cold first pass 1.66 s and 0.45 s.
5. **The accelerated mode: fail.** The suites were run with `MLX_ENABLE_TF32=1 device=gpu`
   (`unit_tf32_1_polar_shiftmap{,_accuracy}/stdout.log`, untimed):
   - `polar_shiftmap`: 570 of 654 assertions pass and 84 fail, all on map accuracy (normalised L2 caps,
     selected losses, the zero-radius map, folding, Nyquist).
   - `polar_shiftmap_accuracy`: 28 of 72 pass and 44 fail (selected losses, production-geometry frozen cap).

   Rows, reported only (`T1_ctrl_r{1,2}_a1`, the control twice): screen ptile 4 2.00000e4 / 2.00392e4
   (+0.3 %), window ptile 16 7.70911e4 / 7.73410e4 (+3.5 %). The mode does not count.
6. **Traces** (decision 11, after every timed row), in `keep/traces/maps_tf32_{0,1}.trace` (exit 0, 589 and
   564 MB). They trace the control at ptiles 4 and 16 with both maps (screen 4, window 16), and are read in
   `keep/traces/maps_traces_reading.txt` from the `metal-shader-profiler-shader-list` table of the
   benchmark process:
   - full precision: only `steel_gemm_fused_nn_float32_float32_bm64_bn64_bk16_…`;
   - accelerated: only `steel_gemm_fused_nax_nn_float32_float32_bm64_bn128_bk512_…`;
   - FFTs `fft_mem_256` (n 14, 35) and `fft_mem_512` (n 364) in both.

   **NAX dispatch is observed for the map workload in the accelerated mode only.**
7. **Memory per verdict row** (the row columns; process measured one row per invocation in
   `mem_{screen_p4,window_p16}/` with `footprint`/`vmmap` snapshots every 1.5 s; those snapshots slowed the
   screen row to 1.21e4 maps/s, so that rate is not a timing):

   | | screen ptile 4 | window ptile 16 |
   | --- | --- | --- |
   | host payload (`host_bytes`) | 4.288e9 | 4.288e9 |
   | prepared device memory | 9.770e9 | 9.770e9 |
   | tile cache estimate | 1.721e9 | 1.218e9 |
   | estimate (pruning) | 20.18e9 | 19.68e9 |
   | MLX peak | 10.715e9 | 10.738e9 |
   | process peak footprint / max RSS, single row | 22.65e9 / 21.47e9 | 22.90e9 / 21.47e9 |
   | full-half staging, 16 · 364 · 30 shells · 1,000 (*derived*) | 0.175e9 | 0.175e9 |

   Reconciled by region at the screen row's plateau (`fp_9.txt`, `vm_9.txt`):
   - IOAccelerator (graphics) 10.1 GiB dirty, the Metal buffers, against MLX's peak of 10.7e9 B;
   - Malloc Large 4.2 GiB live, the host payload;
   - 6.5 GiB "Malloc Large (empty)", freed host blocks the allocator keeps;
   - 0.2 GB unmapped graphics memory.

   No gap is unexplained. The estimate exceeds the MLX peak by 9.5 GB, so it is conservative. A single row
   stays inside the 25.8 GB budget. A whole Stage A invocation (both maps, three ptiles) peaks at 27.75e9 B
   footprint, with the freed blocks and the larger tiles' buffers; the budget is per configuration.
8. (deferrable, done) **Synthetic sensitivity** of the control at the canonical ptiles, one invocation each
   (`S_{quarter,none,evidence}_a1`). These are labelled synthetic and carry no CPU ratio: the work is not
   SIMPLE's, so they give no equivalent-work speedup.

   | variant | screen | window |
   | --- | --- | --- |
   | `widths=quarter` | 2.20386e4 (+10 %) | 7.86206e4 (+6 %) |
   | `widths=none` | 2.53245e4 (+27 %) | 8.73928e4 (+17 %) |
   | `evidence=1` | 1.82906e4 (−8 %) | 6.94580e4 (−7 %) |

   The percentages compare with the Stage A control's first invocation.
9. **The fusing note refreshed** (its section 1a) from the requested-output profile of the verdict rows,
   with SIMPLE's stages beside it.
   - Construction is 69 to 70 % of the GPU's time per map and is where it loses: 1.25 times SIMPLE's on the
     screen, 1.54 times on the window.
   - The width reduction is already faster than SIMPLE's.
   - The remaining candidate is a fused construction kernel. No speedup is assumed.

Exit:
- Stage A is complete, with two clean invocations per graph.
- Retention follows decision 7, with its numbers: none retained, so three negative results.
- Per-map verdict: screen 0.971 and window 0.683, both negative and not at the boundary; decision 18's
  caveats are stated.
- The accelerated mode is a fail.
- The map traces are read: NAX in the accelerated mode only.
- Memory is reconciled.
- The fusing note is refreshed.
- Deferrable items done: Stage B at compact 0, and step 8.
- No job is left running.

What it means, in short: on the M5 Ultra the GPU's shift maps no longer beat SIMPLE. The committed CPU kernel
on 30 cores builds the screen 1.03 times and the window 1.46 times as fast as the GPU's best graph, so both
verdicts are negative. None of Phase 5c's graph alternatives earns its keep, and construction is the one
stage a kernel would have to fix.

### Phase 4, milestone 1 Phase 7: summary, report, hold, 2026-11-24 04:31–04:34 EST

Documentation only; nothing built or run beyond the static gate. Sources as before (`4706ecb`, SIMPLE
`0a8b0903e`). Rulings: none.

Files changed:
- `planned/mlxf_milestone1.md`: status banner and the interim summary in Progress;
- this note: banner and this entry;
- `planned/mlxf_m5_preparation.md`: the Phase 2 inputs delivered and observed NAX dispatch;
- `doc/implementation_notes/README.md`: the milestone 1 row, and a row for this note;
- `doc/history/2026-11.md`: the delivered batch;
- `doc/how2s/how2set_up_dev.md`: the M5 corrections;
- `completed/mlxf_milestone1_report.md` (new): the report.

1. Milestone 1's Progress holds the interim summary of its Phase 7 step 1:
   - what was proved;
   - both verdicts and their branches;
   - peak memory;
   - the kept formulation and tile plans;
   - sensitivity per temperature;
   - the profile gaps;
   - what SIMPLE's integration would take.
2. Banners:
   - milestone 1: "Phases 5c (performance exit), 6 and 7 delivered by run `mlxf_m1_m5` …; at the hold";
   - this note: delivered and at the hold;
   - the index row in `doc/implementation_notes/README.md`;
   - the history entry.

   Decision taken under delegation: the phase note's "do not edit README.md" and decision 13's "the README
   status line" are read as the root `README.md`, which is unchanged. The index row in
   `doc/implementation_notes/README.md` is edited as step 2 and the file table say, and the index gained a
   row for this note, which it did not list.
3. The report, `completed/mlxf_milestone1_report.md`, follows `doc/how2s/how2write_agent_plans.md` section
   8 and cites the Progress entries of Phases 0 to 4.
4. Setup-guide corrections (`how2set_up_dev.md`, before "For arun itself"):
   - the hand-built export in place of `release_gate.sh`;
   - SIMPLE built offline from the copied OpenBLAS cache;
   - which suites read `nthr`;
   - the trace recipe and what it showed.

   MLX questions: none. Every trace matched decision 11's expectation, so `apple_questions.md` is unchanged.
5. `scripts/check_tree.sh` passes in the repository copy. `git status` shows only files in the table: the
   seven above and `planned/mlxf_fusing_note.md` (Phase 3).

Exit: the report exists and cites every entry; milestone 1's Progress and banner; history; the static gate
passes; no file outside the table. Neither plan is moved (decision 13).

What it means, in short: milestone 1 is at its hold. GPU scoring is a go at 4.69 times SIMPLE on the M5
Ultra, the GPU shift maps are a negative result against SIMPLE's committed kernel, and the experiments to
remove are named.
