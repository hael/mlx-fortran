# MacBook Pro preparation for the M5 Ultra

Archive disposition, 2026-11-24: **completed laptop delivery, split from its unfinished follow-up**.
Local Phases 0–4 and their report were committed in `b99eb43`. The original plan and delivery record
below are retained as history, including their explicit missing-spec finding. They do not claim the
external launch audit or combined parity integration passed. Those remaining Phase 2/5 tasks now live
in [the active follow-up](../planned/mlxf_m5_preparation.md). The earlier instruction to keep both
documents in `planned/` is replaced by this split at the owner's request.
The [delivery report](mlxf_m5_preparation_report.md) summarizes the completed evidence.

Status, 2026-11-23: local Phases 0–4 validated; handoff/integration hold. The actual M5 launch-spec audit
and combined validation after Claude's parity Phase 3 remain pending. Supersedes: none. Written at mlx-fortran
`4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47`, with the owner's uncommitted parity decision 25
read and preserved. SIMPLE reference: `0a8b0903eee151700305399e8e3ff53c2c21caae`.
Execution host: Hans's MacBook Pro at home; record its actual model and toolchain in Phase 0.
Target: Phase 1 and Phase 2 ready before the expected M5 arrival on Wednesday, 2026-11-25;
Phases 3 and 4 follow in priority order, without a promised completion date.

This is the single execution record for these four preparation tasks. It supplements milestone 1;
it does not replace its scientific contract or performance verdict. Packaging executes the outstanding
scope of the original design's Phase 5. Example equations remain in the scientific-examples note;
this plan owns only their independent host preparation. No second specification is introduced.

Depends on:

- Phase 5c at the base above (validated: implementation reviewed; previous CPU/Metal checks recorded in
  [milestone 1](../planned/mlxf_milestone1.md); the home Mac's baseline has not been run).
- Claude's `mlxf_parity`, Phases 1–3 on the M2 Ultra (validated: scope read in
  [decision 25](../planned/mlxf_mlxc_parity.md); completion and its final API are not assumed).
- The M5 run `mlxf_m1_m5` at `4706ecb` (validated: base supplied by Hans; external run specification
  not inspected, and the M5 hardware not available).
- [Scientific examples 2 and 3](../planned/mlxf_scientific_examples.md) and their applied review (validated:
  equations previously dry-run; durable scripts and host portability must be established in Phase 4).

## 1. Why

The Phase 5c review found three concrete test blind spots. Scratch mutations that reused the first
particle's candidates, gathered the wrong survivor temperatures, or removed middle reference harmonics
each passed the existing 654 shiftmap and 72 geometry assertions on CPU. Stronger fixtures caught
70, 4 and 59 failures respectively; the actual implementation passed the stronger fixtures on CPU and
Metal. Closing those gaps and checking the M5 launch package are the immediate priorities. Consumer
packaging and reusable host references then prepare the library for use and the next scientific models,
without competing with Claude's wrapper implementation or measuring a busy machine.

## 2. Contract

- Work runs locally on the MacBook Pro. No M2 job, remote build, package update or benchmark is started.
  The M5 run is prepared here and executed separately when the machine is ready.
- **Benchmarks remain deferred.** No throughput, profile, tile sweep, stream-load or overlap run belongs
  to this plan. Bounded correctness tests and build/test logs are allowed; their elapsed time is not a
  performance result. This narrows the plan-guide's usual Phase 0 production timing requirement under
  Hans's existing deferral.
- Preserve `4706ecb` as the M5 measurement baseline. A test-only supplement must name its own source
  revision or patch checksum and prove the library and polar kernel/benchmark sources match that base.
  Packaging, parity changes and host probes do not silently enter that measurement checkout.
- `polar_table` remains the test-only owner of prepared shiftmap state. Particle/order shifts remain
  shared across candidates; this plan changes its tests, not the kernel or selected defaults.
- Packaging exports the existing library and public `mlxf` module. It adds no installed internal module,
  API, hidden state, SIMPLE dependency or alternate ownership implementation.
- Phase 4 is host-only reference preparation outside the repository, as permitted by scientific-examples
  decision 10. Device kernels, scientific test registration and new wrappers wait for their own phases.
- Normal library behavior is unchanged in every phase. The new install check and host probes run only
  when explicitly invoked. They add no process to the eight-entry CTest budget at this base.

### What the source check established

- `test_formulations` repeats one candidate list and temperatures across particles; `test_width_cutoff`
  repeats survivor rows. `ring_value` contains reference harmonics 0–4 only, also in the 364-rotation check.
- All four combinations of weighted-particle/real-weight contraction and complex/Hermitian direction
  transform already exist. The named-only `polar_shiftmap_accuracy` entry also exists; no new entry is needed.
- `src/CMakeLists.txt` installs the library and `mlxf.mod`, but no package config/export or consumer check
  exists. `mlxf` links `mlxc` and optionally OpenMP; `mlxf_build_flags` is a private build dependency whose
  static-library export behavior needs checking.
- The Mac setup guide exists, but its SIMPLE paragraph still describes the earlier planner-option
  baseline. The release gate exists; it does not replace the named-only shiftmap accuracy check.
- Parity Phases 1–3 may edit core array/ops code, shared test definitions/registry, policies, README and
  history. This plan avoids those source files. Parity Phase 5 owns the n-dimensional FFT wrappers that
  full spectral-volume and projection examples will need.

## 3. Decisions and rulings

1. (2026-11-23, Hans) **Planning scope:** write a phased plan for the four recommended tasks, executable
   from the MacBook Pro at home. This delivery is the plan, not a claim that its phases have run.
2. (Existing owner instruction, retained) **No benchmarking now.** Phase 0 records correctness baselines;
   Phase 2 prepares later measurement commands without running them. Performance exits and the measured
   gain required to retain alternative graphs stay with milestone 1.
3. (Design choice) **Order:** Phase 0, then 1 and 2, then 3 and 4. Each phase is a resumable chunk with
   its own exit. Phase 2's documentation inspection can proceed if local GPU access blocks Phase 1,
   but no missing GPU validation is declared passed. Phase 4 does not depend on parity completion.
4. (Design choice) **Isolation:** dedicated `build_m5prep_debug` and `build_m5prep_release` directories;
   build concurrency two by default, not an optimized value. Never clean another run's build directory.
   Agents use read-only git and leave all changes unstaged. The owner handles commits and integration.
5. (Design choice) **Shared-file boundary:** no edits to the parity plan, core Fortran, shared test
   definitions/registry, test CMake, binding policy, README or Apple question register during this work.
   Deferred README wording is recorded here; the new consumer guide supplies usable instructions now.
   History updates are serialized at a handoff and preserve any intervening owner's text.
6. (Existing contract) **Frozen shiftmap gates:** use `POLAR_MAP_CAP_L2`, `POLAR_MAP_CAP_LOG` and
   `POLAR_MAP_CAP_VAR`, each `1e-4` at the base, with their existing scales. These are the previously
   calibrated/frozen milestone bounds, not new allowances. No reseeding, cap relaxation or removed checks.
7. (Design choice, following design Phase 5) **Package compatibility:** record the producing Fortran
   compiler ID and full version; reject a mismatch at consumer configure time. Import `mlxf::mlxf` via
   `find_package(mlxf CONFIG REQUIRED)`. Keep mlx-c shared and discover its dependency transitively;
   discover OpenMP only if the producer used it. Do not export project warning/debug flags to consumers.
8. (Existing scientific-examples decision 10) **Reference-only preparation:** retain the milestone-1
   hold for example implementation. Phase 4 produces durable external probes and an evidence manifest;
   it neither adds repository scientific code nor calibrates future GPU tolerances.
9. (Design choice) **Integration point:** after Claude's Phase 3 hold, inspect the combined diff and run
   the applicable gates before handing it back. Record this as a separate integration result; it does
   not revise the independent M5 baseline. The M5 run owner applies any external launch-spec correction.

Defaults taken without a question: this filename; the build directory names; the evidence directory
`~/agent_work/mlxf_m5_preparation/4706ecb/`; a compact deterministic broadband fixture rather than a
downloaded data set. These choices carry no performance claim.

## 4. Not in this plan

- Changing the scoring/shiftmap kernels, Bessel order rule, tiling defaults, model precision or SIMPLE.
- Implementing parity operations, custom Metal kernels, GPU projection/PCG/NU models, or SIMPLE integration.
- Starting or editing an external autonomous run, changing its base, or installing/upgrading toolchains.
- Running the memory-scaled `recovery_half` test, large accuracy sweeps or any `bench_*` entry on the laptop.
- Publishing a release, filing upstream issues, or committing/pushing changes.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | Baseline inspection and correctness | Pinned sources, Debug/Release builds, static/fast gates, named shiftmap suites; logs retained |
| 1 | Tests only | Four formulations against independent oracles, three new fault controls rejected, unchanged caps and kernel sources |
| 2 | Launch/setup documentation | Actual run-spec audit or an explicit missing-spec finding; complete dry-reviewed command and artifact matrix |
| 3 | Packaging/build integration | External install consumer passes, incompatible compiler rejected, internal modules unavailable, normal gates unchanged |
| 4 | External host reference probes | Independent equations, assertions and negative controls pass; portable sources and logs retained |
| 5 | Handoff/report | Every exit accounted for; shared-file integration status and M5-only work explicit |

## 6. Acceptance

- Phase 1 checks every contraction/transform combination on CPU and Metal, full precision, Debug and
  Release. Cover both fixture grids, differing candidate columns, differing physical/tempered temperatures,
  duplicate candidates and partial particle/candidate tiles. Keep existing degenerate and lifecycle checks.
- Cutoff decisions and sentinel `-1` are exact. Retained widths use the corresponding particle's physical
  temperature; mode/evidence are unchanged by the cutoff under the existing equality contract.
- Broadband references obey Friedel symmetry by construction. The full-map small oracle and the sampled
  production-geometry oracle remain direct host residual calculations on the same rounded inputs; neither
  may call the optimized contraction or Bessel expansion. Report how many mode comparisons have a clear
  margin, and assert a nonzero judged population in a fixture designed to test mode recovery.
- The three new mutations must each cause an assertion failure and nonzero exit on CPU and Metal.
  Historical failure counts motivate the fixtures; the new counts need not equal 70/4/59.
- Packaging checks use a separate temporary install prefix and an outside consumer with no build-tree
  module/include/library paths. Install exactly one Fortran module, `mlxf.mod`. The deliberately altered
  compiler metadata must fail configuration for the intended reason. A broken consumer must make the
  install-check script fail, rather than merely print an error.
- Phase 4's analytic/DFT, matrix/spectral and Cholesky comparisons use `1e-12` normwise as an initial
  host-real64 cap (inherited for the stencil/Cholesky check; a guessed extension for the other small host
  checks). Use explicit input/operator scales for zero references. Freeze formulas, inputs and these
  checks before judgment; diagnose failures instead of widening the cap. This is not a GPU calibration.
- Reported, not gated here: M5/NAX dispatch, M5 performance, hardware availability and the later
  scientific examples' device results. Their owners remain `mlxf_m1_m5` and the future example plan.

## 7. Common rules and stop conditions

Read `AGENTS.md`, `CLAUDE.md`, the architecture register, binding/test policies and relevant repository
skills before each implementation chunk. For Fortran, read `mlxf-modern-fortran` and its testing reference.
Keep the single library target, public-only `mlxf` usage and existing test process budget. Build and run
touched code; use the two formatters for touched Fortran. An external consumer program is the packaging
proof explicitly required by design Phase 5, not another repository unit-test executable or CTest entry.

Use full-precision correctness (`MLX_ENABLE_TF32=0`), one submitting thread, and the existing fast-gate
thread environment. Keep logs, patches, checksums and small reference sources in the durable evidence
directory, not solely `/private/tmp`. Record actual paths in Progress; do not hard-code another Mac's
absolute paths in scripts. Inspect git status before and after each phase and preserve unrelated work.

Pause only the affected work if it needs a kernel/handle-model change, a relaxed bound, an unlisted file,
a conflicting concurrent edit, a different dependency pair, or an unavailable required GPU/specification.
Record the diagnosis and continue independent phases. Never repair a baseline failure by weakening its
gate. If the base kernel is wrong, report the counterexample for a separately scoped fix and keep the M5
measurement status explicit.

Gates that may not be waived: zero warnings in Debug/Release with `MLXF_WERROR=ON`; the static gate;
observed Metal output for every claimed GPU pass; assertions reaching the exit status; frozen numerical
bounds; exact lifecycle checks; external consumer isolation; and the benchmark deferral.

## 8. Phases

### Phase 0, establish the home baseline

1. Record the Mac model, RAM, macOS, compiler/CMake/Python, linked MLX/mlx-c versions, GPU name and
   architecture. Verify the source base and dirty diff. The milestone dependency pair remains MLX 0.32.4
   with mlx-c 0.8.0; this is separate from parity's broader minimum-version policy. Do not alter packages.
2. Build the base in the dedicated directories, with `MLXF_REQUIRE_GPU=ON`, `MLXF_WERROR=ON`, tests
   enabled, and FORTLS left at the repository default. Keep the exact configure/build commands in Progress.
   Run `bash scripts/check_tree.sh` and `bash scripts/run_fast_gate.sh <build-directory>` per build.
3. In both builds run the following correctness suites, setting full precision before each process:

   ```bash
   MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=4 \
     build_m5prep_debug/test/mlxf_test_exec test=unit_kernels suite=polar_shiftmap device=all
   MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=4 \
     build_m5prep_debug/test/mlxf_test_exec test=unit_kernels suite=polar_shiftmap_accuracy device=all
   ```

   Repeat with `build_m5prep_release`. The accuracy suite samples the production geometry; it is not
   the large throughput workload. Record failures as base failures, separately from subsequent changes.
4. Check the Phase 1 fault descriptions against this exact source. Recover any earlier scratch probes
   if available; reconstruct them from the documented mutations if not. No laptop setup depends on `/tmp`.

Exit: both builds and required baseline checks are recorded, GPU access is observed, the file boundary is
confirmed, and the evidence manifest identifies sources and dependencies. No benchmark has run.

### Phase 1, close the Phase 5c regression gaps

1. Extend the existing tester, retaining its simple low-harmonic cases. In `test_formulations`, use
   different candidate columns within each particle tile and different temperatures, for example tempered
   `[3,9,27]` and physical `[7,30,90]` (fixture choices). The oracle reads each pair's actual candidate and
   temperatures. Keep duplicates, candidate tails and the two-particle tile with a final one-particle tail.
2. In `test_width_cutoff`, use heterogeneous physical temperatures and a mask such as retained pairs
   `(1,1), (3,2), (2,3)`. Keep disabled/all/none/partial/equality cases for all four formulations. Compare
   retained widths against independently checked, uncut results for the same inputs.
3. Add deterministic higher angular content with even real and odd imaginary harmonics. Include interior
   and higher bins on the 364-rotation fixture; retain explicit Nyquist tests. Choose the small fixture's
   bins deliberately to avoid accidental aliasing that removes the intended coverage. Preserve its symmetry
   and same-rounded-input contract. Use the existing direct oracle and fixed sample locations.
4. In disposable source copies, separately repeat the three review mutations: copy candidate column one
   across particles; substitute `tph(1:nactive)` for `tph(active)`; zero middle reference harmonics while
   retaining low modes and Nyquist. Log assertion failures and exit statuses, then discard the mutants.
5. Run Debug/Release static and fast gates plus both named suites on CPU/Metal. Confirm the diff contains
   no library, polar kernel, benchmark or tolerance changes. Store the test-only patch/checksum for Phase 2.

Exit: stronger fixtures pass all four alternatives at frozen bounds, all three mutants fail for their
intended reasons on both devices, and the supplement can validate the unchanged `4706ecb` kernel.

### Phase 2, audit and prepare the M5 launch package

1. Obtain and read the actual `mlxf_m1_m5` spec when accessible from home. Record its path/checksum and
   compare it with milestone decisions 14, 18, 22 and 27 and Phases 5c–7. If absent, record a precise
   pending audit item; do not infer its commands from its name or claim it is ready to launch.
2. Reconcile the existing setup guide with SIMPLE `0a8b0903e` and the M5 base `4706ecb`. Document version
   verification, GPU-visible Terminal execution and the release gate. Include the Phase 1 correctness
   supplement with separate provenance; preserve the measured executable's source identity.
3. Add a launch matrix here in Progress: dense scoring and both shiftmap grids; control and all three
   alternative combinations; particle/candidate/order tiles and memory pruning; compact/full radii;
   all-width/no-evidence comparator and separately labelled cutoff/evidence sensitivity. Reuse milestone
   1's existing cases and sweep grids; do not invent a new benchmark standard.
4. Check each command against the actual parser/source. Require measured FFTW plans and the correct full
   CPU team for SIMPLE; preparation/cold compilation separate from warm work; two invocations with the
   prescribed repeats; requested-output parity, load, host/device/peak memory and both revisions in output.
   Full-precision and accelerated modes use separate processes. NAX eligibility is distinct from observed
   dispatch; prepare the capture instructions without claiming the laptop proves M5 behavior.
5. Record missing inputs, stale options, required external-spec edits and expected artifact filenames.
   The M5 run owner applies external changes. No remote run or throughput smoke run is launched here.

Exit: setup instructions and the command/artifact matrix agree with the source; the actual spec has either
been audited with corrections accounted for, or is explicitly marked pending and not launch-ready.
Laptop preparation may be delivered with that finding; M5 launch readiness remains open until resolved.

### Phase 3, package the library for an external Fortran consumer

1. Add CMake config/version/export files and the planned pkg-config template. Export `mlxf::mlxf`, the
   installed module include path, shared mlx-c dependency and conditional OpenMP requirement. Handle the
   private `mlxf_build_flags` dependency without leaking build paths or compiler warning/debug flags.
   Preserve the existing supported library build mode; do not add a new static/shared variant here.
2. Implement the compiler-ID/full-version compatibility check before importing the target. Preserve
   dependency failure diagnostics and installed runtime discovery for the linked MLX pair.
3. Add `test/consumer/` as a separately configured outside project and `scripts/check_install.sh` as an
   explicit install/configure/build/run check. Its program uses only `mlxf`, exercises an existing array
   transfer and calculation with asserted results, and releases handles. It tests no unreleased parity API.
4. Run it against temporary Debug and Release installs using only `mlxf_DIR` for mlx-fortran discovery.
   Verify exactly `mlxf.mod` is installed; attempts to import an internal/generated module fail. Alter a
   disposable config's recorded compiler version and require the intended configure refusal. Verify the
   pkg-config metadata resolves the installed paths/dependencies, including at a prefix containing spaces.
5. Write `doc/how2s/how2use_from_simple.md` with the generic consumer commands and dependency/compiler
   requirements. Explain that production SIMPLE workspace integration awaits its own verdict and plan.
   Keep README changes as proposed text in Progress for integration after the parity hold.

Exit: clean Debug/Release builds and gates, isolated consumers pass, negative install checks fail as
intended, metadata contains no repository build paths, and no internal module or extra CTest entry appears.

### Phase 4, make the next examples' host references durable

1. Read the scientific-examples note and the corresponding SIMPLE sources at the recorded pin. Locate
   the old `check_mlxf_toy_design.py` if available; verify rather than trust its historical output. Store
   self-contained reference sources under the durable evidence directory, outside the repository. Prefer
   Python standard-library scripts for this preparatory calculation; no package installation is required.
2. Spectral filtering: reproduce analytic attenuation and an independent host DFT for the specified
   `8^3` and unequal `6 x 8 x 10` cases. Check DC, Hermitian reality, all labels, outside-support behavior
   and half-specific cost terms. Wrong transform scale and label origin must be detected.
3. PCG reference: build the independent 64-by-64 cropped/windowed seven-point stencil matrix for `N=4`,
   padded `M=8`, with `lambda=.25`; compare it with the direct spectral construction. Check symmetry and
   positive definiteness, form the rounded-input right-hand side, solve with host Cholesky and recompute
   the residual from the explicit matrix. Keep an optional host PCG dry run distinct from the reference
   solution; do not reuse the candidate operator to manufacture its expected answer.
4. Projection/adjoint: assemble explicit `G` from scalar geometry and a converged I0 series, separately
   from direct padded DFT evaluation. Check the specified proper rotations, half-away-from-zero rounding,
   periodic destinations, constant-field normalization, centered-point scaling, conjugated adjoint,
   density versus squared stencil weights, and packed-half multiplicities. Keep the fixture's `1e-4`
   half-integer margin (inherited guessed coordinate safeguard) and exact boundary cases distinct.
5. Plant wrong scale, missing adjoint conjugation and wrong packed-half weighting controls in independent
   copies; each must fail a named check. Store source checksums, commands, expected quantities, errors and
   logs in a portable manifest. Update the existing scientific-examples Progress with the evidence and
   operation dependencies; leave its GPU implementation phases and future tolerance calibration open.

Exit: probes reproduce the host equations with asserting exits, the negative controls fail, and the
sources/logs survive transfer to another Mac. No MLX/device numerical result or production scientific
equivalence is claimed. No new scientific Fortran module or wrapper is added to the repository.

### Phase 5, review and hand off

Review the complete diff and each phase's logs. If Claude's Phase 3 output is available, coordinate the
owner's integration and validate the combined tree in separate build directories; otherwise list that
integration check as pending. Leave the M5 measurement checkout unchanged. Serialize the history entry.
Write `mlxf_m5_preparation_report.md` in the plan-guide order: findings, phase changes, delegated choices,
deviations, evidence, remaining work and a suggested commit message. Move this plan/report to `completed/`
only when their required work is done; do not mark the M5 experiment or milestone 1 complete here.

Exit: the owner has a reviewable unstaged diff, portable evidence, an explicit M5 readiness status and a
list of later work owned by the parity, milestone-1 and scientific-example plans. No benchmark was run.

### File table

Paths are relative to the repository. A row grants only the stated purpose. External artifacts have a
separate row because Phase 4 intentionally does not implement repository scientific code.

| File | Purpose | Phases |
| --- | --- | --- |
| `doc/implementation_notes/planned/mlxf_m5_preparation.md` | Contract, execution record, launch matrix, proposed shared-file wording | 0, 1, 2, 3, 4, 5 |
| `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90` | Three regression gaps, existing suites only | 1 |
| `doc/how2s/how2set_up_dev.md` | Reconcile M5 setup and current source pins | 2 |
| `CMakeLists.txt`, `src/CMakeLists.txt` | Package generation/export/install wiring | 3 |
| `cmake/CompilerConfig.cmake`, `cmake/Dependencies.cmake` | Export/dependency wiring only if needed; preserve compiler flags and discovery behavior | 3 |
| `cmake/mlxfConfig.cmake.in`, `cmake/mlxf.pc.in` (new) | Package contract and metadata; version/targets files generated at build time | 3 |
| `test/consumer/CMakeLists.txt`, `test/consumer/mlxf_consumer.f90`, `test/consumer/consumer.inf` (new) | Outside install consumer, not registered in CTest | 3 |
| `scripts/check_install.sh` (new) | Explicit packaging check and negative cases | 3 |
| `doc/how2s/how2use_from_simple.md` (new) | Consumer instructions, no production integration | 3 |
| `doc/implementation_notes/planned/mlxf_scientific_examples.md` | Host-reference evidence and dependencies in Progress only | 4 |
| `doc/history/2026-11.md` | Planning/delivery entry, serialized with other writers | 0, 5 |
| `doc/implementation_notes/completed/mlxf_m5_preparation_report.md` (new at handoff) | Final report; move with this plan when complete | 5 |
| `~/agent_work/mlxf_m5_preparation/4706ecb/` (external) | Logs, source manifests, disposable mutation copies, test supplement and host reference sources | 0, 1, 2, 3, 4, 5 |

## Progress

### Phase 5, laptop handoff and integration hold, 2026-11-23

- The local work is delivered as an unstaged diff on `main`; no branch, commit, package update, benchmark
  or M2 action was made. Claude owns parity Phases 1–3, confirmed again by Hans. No library Fortran,
  shared test definitions/registry, test CMake, binding policy, README or parity-plan edit is included.
- This checkout remains based at `6ef5ec5`; Claude's final Phase 3 diff is not present here. The combined
  diff review and applicable Debug/Release/consumer gates must run after that output is integrated by the
  owner. This plan/report stay in `planned/` until that integration result is recorded. The independent
  measurement snapshot remains `4706ecb` regardless of that later integration.
- The actual launch spec and updated SIMPLE comparator are unavailable locally as detailed below.
  Phase 2's local exit is the explicit missing-spec finding plus the audited parser/matrix; launch
  readiness remains open. No future M5 run was started or changed.
- Deferred README wording, to integrate with Claude's text at handoff:
  “The installation includes `mlxf.mod`, the static Fortran library, CMake package files and pkg-config
  metadata. Enable Fortran, use `find_package(mlxf CONFIG REQUIRED)` and link `mlxf::mlxf`. The producing
  and consuming compiler ID/full version must match. See `doc/how2s/how2use_from_simple.md` for an isolated
  consumer and `scripts/check_install.sh` for the explicit installation check.”
- The report is `mlxf_m5_preparation_report.md`. The evidence root contains the test-only patch and its
  baseline-source proof separately from current-tree packaging artifacts. Host probes are portable,
  use the standard library only and need no sibling source checkout when run on another Mac.

### Phase 4, durable host references validated, 2026-11-23

- Reconstructed the missing old scratch probe from the scientific-examples equations. Read corresponding
  source anchors at that note's **available** SIMPLE pin `7ec7e2972`, recording eight source checksums;
  this is distinct from Phase 2's unavailable measurement pin `0a8b0903e`.
- Evidence: `host_references/check_mlxf_host_references.py`, `manifest.json`, per-control copies/logs and
  `host-reference-results.json` under the evidence root. Command: `python3 check_mlxf_host_references.py`
  in any writable directory. Probe SHA-256:
  `cbd573db5b3e193d94db72f17d297d62add04420870189586bee9a0630ef03f6`.
- All **247** checks pass. Largest normalized error `4.018729e-15` at the frozen initial host cap
  `1e-12`; explicit input/operator scales cover zero references. Spectral analytic/DFT errors are
  `1.95e-15` (8-cube) and `2.01e-15` (6×8×10). The independent full stencil/spectral matrices agree at
  `6.92e-16` / `6.70e-16` for the ordinary/zero-face windows; Cholesky rounded-RHS true residuals are
  `2.12e-16` / `1.33e-16`. No bound was widened.
- Projection covers proper rotations, half-away rounding, normalized scalar I0 stencils, direct padded
  DFT, the centered point, a Cartesian slice, conjugated weighted adjoints, density versus squared
  weights, periodic duplicates and Hermitian packing/multiplicities. The fixture's minimum half-integer
  distance is `0.021539`; boundary cases are separate. Six independently modified copies each fail a named
  assertion and exit 1: inverse scale, label origin, half inputs, padding scale, adjoint conjugation and
  packed multiplicity. The positive source exits 0.
- Updated only the scientific-examples Progress with evidence and operation dependencies. 3D FFTs remain
  parity Phase 5 work; scientific device code, scatter collision assessment, tolerances and performance
  remain at that note's existing hold. The optional host PCG iteration was not needed; Cholesky supplies
  the independent reference solution.

### Phase 3, external package validated, 2026-11-23

- Added config/version/export wiring, `mlxf::mlxf`, compiler ID/full-version refusal, conditional OpenMP
  discovery and pkg-config metadata. `mlxf_build_flags` remains available in the producing build only;
  no warning/debug/trap options or producer source/build paths reach the installed target.
- `test/consumer/` uses only `mlxf`, compares `exp(-matmul(a,b))` against host arithmetic, transfers
  results and releases every handle. It passes on CPU and the observed M3 Pro GPU in both configurations,
  through both CMake and pkg-config, installed into prefixes containing spaces.
- `scripts/check_install.sh` checks exactly one `.mod` (`mlxf.mod`), no `.smod`, isolation from producer
  paths/flags, refusal of internal/generated imports and edited compiler metadata. An independently
  broken consumer makes the script exit 1 at its intended `error stop`; its successful siblings exit 0.
  `doc/how2s/how2use_from_simple.md` documents the generic package without adding SIMPLE integration.
- Current-tree Debug/Release clean builds use `BUILD_TESTS=ON MLXF_REQUIRE_GPU=ON MLXF_WERROR=ON`,
  FORTLS default, two jobs. Both fast/static gates pass, 8/8; both broadband accuracy suites pass, 144
  checks. Full precision and existing thread environment apply. Zero compiler/CMake warnings in final
  configure/build/install logs; the static gate reports only the expected untracked new consumer source.
- An additional isolated Release library build with `USE_OPENMP=OFF BUILD_TESTS=OFF MLXF_WERROR=ON`
  passes the same external install check, with no OpenMP dependency/flags in its consumer.
- Exact commands/results are in `package-commands.json`, `extra-package-commands.json` and their logs.
  Initial install-check development caught CMake's compiler cache using `STRING` rather than `FILEPATH`,
  pkg-config's automatic space escaping, and preservation of the undefined FPHSA warning variable;
  these were corrected before the final successful results. Normal library algorithms are unchanged.

### Phase 2, launch audit and command/artifact matrix, 2026-11-23

**Readiness: preparation available; M5 launch remains pending.** Searched the repository, local
`~/agent_runs/{runs,templates,var}` and `~/agent_work`; no `mlxf_m1_m5` launch spec was present. Hans's
supplied commit link points to parity decision 25, already read: it authorizes independent measurements
at `4706ecb`, but supplies no launch commands. There is consequently no actual-spec checksum or claim
that the external run has been audited. Its owner must apply/verify the matrix below against that spec.

The clean local SIMPLE checkout is `67c6a05e22628b380fe0ca134b9c211f9f32cd76`; read-only
`git show -s 0a8b0903eee151700305399e8e3ff53c2c21caae` fails with `bad object`. No fetch, checkout, build
or remote job was attempted. Current local parser inspection confirms the earlier planner option;
the updated comparator's source and build must be checked at the required pin before launch.
The setup guide now distinguishes these two pins, the correctness supplement and measured executable,
the release gate and named accuracy suite, and measured versus identity FFTW plans.

The following commands are **dry-reviewed templates, not executed benchmarks**. `$exe` must name the
Release executable built from the unchanged measurement snapshot; `$simple` must name the installed
required SIMPLE comparator. `$cases` and `$grid` must be fresh absolute paths derived from that Mac's
CPU rows. `$team` is its observed full CPU count (not the M2's assumed 24). Run each invocation in its
own artifact directory, retain stdout/stderr and exit status, and use absolute executable/input paths.

| Work | Future command/arguments | Artifacts and conditions |
| --- | --- | --- |
| Source/device bring-up | `git --no-optional-locks log -1 --format='%H %s'`; `git --no-optional-locks status --short`; `sw_vers`; compiler/CMake/Python and installed/linked MLX pair; verbose `unit_core` | `sources.json`, source checksums/diff, `machine.log`, dependency linkage, one observed GPU name/architecture; external spec path/checksum still required |
| GPU-visible release checks | `bash scripts/release_gate.sh --jobs 2` in the intended clean source; separately build/check the test supplement in its own source copy | `release_gate_<commit>.log`, `supplement-sources.json`, patch and SHA-256; Debug/Release, 8/8 fast entries, no skips, both named shiftmap suites; the M5 owner's large recovery/64,000-pair accuracy gates remain required there |
| CPU correctness | `$simple test=polar_matching_bench suite=check\|fills\|neigh nspace=... nstates=... nptcls=2000 nthr=$team` (one actual suite value per process) | Separate logs; confirm geometry, half populations, matching entries and team identity; verify syntax on SIMPLE `0a8b0903e` before use |
| CPU dense denominator | `$simple test=polar_matching_bench suite=block_prod nspace=1000\|2500 nstates=1\|4 nptcls=2000 nthr=$team fftw_plans=measure` (one value per key) | Two invocations per four-case Cartesian product; `polar_block_prod_bench.tsv`, measured planner log, full/half/one-team rows and fastest measured CPU block; one-team cap does not replace full-team work |
| CPU maps denominator | `$simple test=polar_matching_bench suite=shiftmap nspace=2500 nstates=4 nptcls=2000 nthr=$team fftw_plans=measure` | Two invocations; `polar_shiftmap_bench.tsv`, window/screen geometry, 16 candidates, all widths, no evidence, measured planning separate; each team identity difference must be zero |
| Dense accuracy | `$exe test=bench_polar_table suite=accuracy cases=$cases case=2500_4 form=b\|c bt=... rt=... device=all` | M5-only 64,000-pair assertions, seed-1 diagnostics and frozen seed-2 gates, draw sensitivity and identity; no recalibration |
| Dense sweep | `$exe test=bench_polar_table suite=time cases=$cases cases_list=1000_1,1000_4,2500_1,2500_4 form=b\|c nthr=$team` | `bench_polar_table.tsv`; built-in B/R grids each `{64,250,500,1000,2000}` / `{64,250,500,1000,2500}`, pruned against populations and quarter-memory budget; B and C are existing dense formulations |
| Dense stages | `$exe test=bench_polar_table suite=profile cases=$cases case=2500_4 form=b\|c bt=... rt=... nthr=$team device=gpu` | `bench_polar_table_profile.tsv`, barriers/cold preparation separate from warm complete-work wall time |
| Dense overlap | `$exe test=bench_polar_table suite=overlap cases=$cases case=2500_4 form=b\|c bt=... rt=... outer=250 nthr=$team load=none\|stream device=gpu` | `bench_polar_table_overlap.tsv`; two slots versus sync, exact canonical identity; start a separately logged `suite=stream seconds=60 nthr=...` only under the M5 owner's load experiment, never here |
| Shiftmap control | `$exe test=bench_polar_table suite=shiftmap cases=$cases case=2500_4 grid=$grid maps=window,screen ptiles=4,16,64 contraction=1 hermitian=0 ctile=16 otile=4 compact=1 widths=all evidence=0 revision=4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47 device=gpu` | `bench_polar_table_shiftmap.tsv`; all-width/no-evidence is the matched CPU work; all rows retain precision, source revisions, requested outputs, work counts and pruning status |
| Three map alternatives | Same command, `(contraction,hermitian)` = `(1,1)`, `(2,0)`, `(2,1)` | Compare separately and jointly with control, interleaving candidate/control; no alternative becomes default from correctness validation |
| Map tile/radius experiments | For each applicable graph, `ptiles=4,16,64`; explicit loops over `ctile=4\|8\|16`, `otile=1\|4\|8`, `compact=0\|1` | Individual arguments take scalar values; do not pass a comma list to `ctile`/`otile`. Record useful/executed radius-order slots, host/prepared/live/peak bytes and all pruned configurations |
| Cutoff/evidence sensitivity | Same graph command with `widths=none\|quarter\|all` and `evidence=0\|1`, each combination distinctly labelled | Synthetic survivor fraction and work; ratios against the all-width CPU baseline are not equivalent-work speedups; production width frequency remains unmeasured |
| Dispatch evidence | In Xcode's Metal capture workflow select the pinned Release executable and its exact arguments/environment; capture representative full-precision and accelerated graph invocations separately | `.gputrace`/Instruments trace, capture settings, matched row IDs, named kernels/pipelines. Availability is not observed dispatch. The public Fortran API has no capture wrapper at this base; do not invent a `capture=` benchmark option |

All timing rows require **two invocations**, each using its built-in warm-up and three repeats; report the
spread and use the prescribed conservative CPU/GPU comparison. Set `MLX_ENABLE_TF32=0` or `=1` **before
each new process**, retaining both modes separately. Full precision judges the verdict. Accelerated
results count only at the same frozen accuracy caps; the architecture alone does not prove NAX dispatch.
Keep one submitting thread; CPU consumption may use the explicitly recorded team outside MLX calls.

Parser findings at the measurement source:

- Case sections are `[case NAME]`, with `nspace,nstates,nrefs,nptcls,pftsz,kfrom,kto` integer keys.
  Map sections are `[map window]`/`[map screen]`, with
  `pftsz,nrots,kfrom,kscreen,nrho,nalpha,norder,nrefs,nptcls,ncand,rho_max_px,prior_w`, plus
  `simple_commit`, `fftw_plans` and **`maps_per_s_t24`**. That last historical key parses the two actual
  full-team rates even when the M5 team is not 24; record the real team in the sidecar. A renamed key
  would silently leave rates missing. Export measured values rather than rounded historical geometry.
- `revision=` is emitted by shiftmap rows only. Dense rows lack both revisions, and neither family
  replaces OS process-peak/load evidence. Require a sidecar per invocation with both full commits,
  executable hashes, input hashes, full command/environment, actual team, load samples, `/usr/bin/time -l`
  peak footprint and swap information. Keep host, prepared/resident, estimated live, MLX peak and process
  peak distinct, reconcile aliases and the two overlap slots, and reject a go verdict with unexplained gaps.
- The benchmark parser ignores unknown keys, so invented `repeat=`, `capture=`, `candidate_tiles=` or
  `maps_per_s_t<actual-team>` options must not be used. Repeats are compiled into the implementation.
- Parser hygiene finding: `arg_int` tests `ios` after an omitted key without first initializing it.
  Its result is already the default in either branch, but this is still an undefined read. It was not
  changed in the pinned benchmark source; a separate fix must keep its source provenance explicit.
- Before launch, the owner must supply/audit the actual external spec, make the required SIMPLE source
  available, verify its parser/output against this matrix, generate fresh CPU case/grid files, and account
  for every row above in the command schedule. The expected verdict/report remains milestone 1 Phases 6–7,
  not this laptop delivery. No matrix command above has been timed or launched here.

### Phase 3 choices before validation, 2026-11-23

- CMake exports the existing static `mlxf` target, its sole installed public module and shared mlx-c;
  OpenMP is discovered only for a producer using it. The private flags target uses a build-only link
  interface, preserving its producer flags without exporting that target or its warning/debug options.
- The config checks compiler ID and **exact full version string** before dependency/target import.
  Consumer package discovery uses `CONFIG QUIET` plus an actionable `_FOUND` failure, following the
  mandatory `findpkg` static rule. The guide shows downstream users' normal `CONFIG REQUIRED` spelling.
  This resolves the plan's example/static-policy conflict without weakening the gate or editing it.
- mlx-c's Homebrew package supplies no pkg-config file. `mlxf.pc` therefore records its shared link and
  runtime-search flags directly in `Libs.private`, along with conditional OpenMP flags; `--static` is
  required when linking the installed Fortran archive. No MLX package update is involved.
- The consumer is explicitly configured outside the source/build trees and is not registered in CTest.
  Builds use `build_m5prep_current_debug` and `build_m5prep_current_release`; these validate the current
  checkout independently of the baseline/supplement snapshots. Results are still pending.

### Phase 1, regression supplement validated, 2026-11-23

- Retained all original low-harmonic, degenerate, Nyquist and lifecycle cases. The new broadband fixture
  adds real even/imaginary odd bins, using distinct bins at ring 24 (real 2/6/8/10, imaginary 5/7/9/11)
  and ring 364 (real 12/48/110/176, imaginary 11/37/95/173). The folding grid uses its representable
  bins 2/4 and 1/3. Thus Friedel symmetry is constructed before rounding once to complex32.
- Formulation tests use distinct candidate columns with duplicates, tempered `[3,9,27]`, physical
  `[7,30,90]`, particle tile 2 with a final one-particle tail, and existing candidate/order tile choices.
  Each pair's direct residual and independent moments use its own candidates and temperatures. Each
  configuration judges 16 clear-margin modes on the 24-ring grid and 7 on the folding grid; all match.
- The partial width mask retains `(1,1), (3,2), (2,3)`. Uncut heterogeneous widths/evidence are first
  checked independently; disabled, all/none/partial/equality cases preserve mode/evidence and exact `-1`.
- Both Debug and Release `MLXF_WERROR=ON` builds pass with zero compiler warnings. Both static/fast gates
  pass (8/8 processes), as do `polar_shiftmap` (1,364 checks across CPU/Metal) and the broadband
  `polar_shiftmap_accuracy` (144 checks). Frozen caps/scales and normal kernel behavior are unchanged.
- Separately compiled Release mutants all fail assertions and exit 1 on **each** device:

  | Fault | `polar_shiftmap` failures per device | Accuracy-sample failures per device |
  | --- | ---: | ---: |
  | Reuse the first particle's candidate column within a tile | 81 | Not run; the sample has one particle |
  | Gather `tph(1:nactive)` instead of `tph(active)` | 5 | Not applicable to the sample's uncut widths |
  | Zero interior harmonics above 4, retaining low modes and Nyquist | 41 | 49 |

- Evidence: `phase1-commands.json`, `mutation-commands.json`, the drivers and logs in the evidence root.
  `supplement-sources.json` verifies **all 121 other baseline files unchanged**, including the library,
  polar kernels, benchmark and frozen definitions. Test SHA-256:
  `741cebb38bdd5c9ea78d2f2a86209cd405f48ccba7ee18b20729e2749aac1fba`.
  `shiftmap-test-supplement.patch` SHA-256:
  `d8f0a2644593f206a4cd8990b1a4fa4d15896007a0c57578063cbfd380b378c7`.

### Phase 0 result, 2026-11-23

- Both pinned builds, static gates and 8-entry fast gates pass; zero compiler warnings. The original
  `polar_shiftmap` passes 1,308 checks and the original geometry sample 144 checks across both devices,
  in both build types. No baseline failure was found.
- GPU output was observed: `GPU devices: 1`, `Apple M3 Pro`, `applegpu_g15s`, runtime MLX 0.32.4,
  `MLX_ENABLE_TF32=0`. macOS 26.7.3 (`25G342`), GFortran 16.2.0, CMake 4.5.1, Python 3.12.2.
- Baseline logs/manifests retain exact commands and versions. Phase 0 is complete. No benchmark,
  memory-scaled recovery, package upgrade or remote action ran.

### Phase 0 started, 2026-11-23 (Codex, MacBook Pro)

- Owner authorized execution while Claude works on parity on the M2. No remote action or benchmark is
  started. Initial branch `main`, clean tree at `6ef5ec5`; no git state was changed.
- That head contains post-baseline library fixes. To preserve the experiment, exported the tracked
  `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47` sources with read-only `git show` into
  `~/agent_work/mlxf_m5_preparation/4706ecb/baseline_source/`. The source manifest records each file's
  SHA-256, the measurement base and the execution head. The source snapshot has no git worktree.
- Evidence root: `/Users/elmlundho/agent_work/mlxf_m5_preparation/4706ecb/`. The portable baseline driver,
  exact command/result manifest and per-step logs are retained there. The dedicated repository build
  directories use that snapshot; later current-tree validation will use separate directories.
- Observed host: MacBook Pro `Mac15,6`, Apple M3 Pro, 11 CPU cores (5 performance, 6 efficiency), 18 GB
  RAM, 14-core GPU, Metal 4. Installed dependencies remain MLX 0.32.4 and mlx-c 0.8.0, GCC 16.2.0;
  Homebrew CMake is 4.5.1 (the executable actually configured is recorded in its log).
- Configure per type: `cmake -S "$evidence/baseline_source" -B "build_m5prep_${type}"`
  with `-DCMAKE_BUILD_TYPE=Debug|Release -DBUILD_TESTS=ON -DMLXF_REQUIRE_GPU=ON -DMLXF_WERROR=ON`;
  FORTLS keeps its default. Build: `cmake --build "build_m5prep_${type}" --parallel 2`.
  Commands run with `MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE OMP_THREAD_LIMIT=4`.
  Builds and tests are still pending; no pass is claimed here.

### Plan written, 2026-11-23

- Hans requested the four-task phased plan for work from his MacBook Pro. Implementation has not started.
- Read the base's architecture, binding/test contracts, plan guide, milestone/parity scope, original
  packaging scope, scientific examples and existing setup/build/test code. The three shiftmap gaps and
  absent consumer package were checked in source. The external M5 run spec remains uninspected.
- The owner's dirty parity-plan change is preserved. The only delivery is this plan and its history entry;
  no code, package, build, device test, remote run or benchmark was changed or started.
- Documentation validation: `bash scripts/check_tree.sh` and `git --no-optional-locks diff --check` pass;
  relative links, phase headings and Markdown fences were checked. The parity plan's checksum is unchanged.
  No compilation or device testing was needed for this documentation-only delivery.
