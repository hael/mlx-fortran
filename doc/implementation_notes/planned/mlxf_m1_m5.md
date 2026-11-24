# Run `mlxf_m1_m5`: milestone 1's measurements and verdicts on the M5 Ultra

Status, 2026-11-24: planned; decisions 1 to 14 ruled by Hans on 2026-11-24 (11 as amended, the others as
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
