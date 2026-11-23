# MacBook Pro preparation for the M5 Ultra

Status, 2026-11-23: planned; no implementation phase has started. Supersedes: none. Written at mlx-fortran
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
  [milestone 1](mlxf_milestone1.md); the home Mac's baseline has not been run).
- Claude's `mlxf_parity`, Phases 1–3 on the M2 Ultra (validated: scope read in
  [decision 25](mlxf_mlxc_parity.md); completion and its final API are not assumed).
- The M5 run `mlxf_m1_m5` at `4706ecb` (validated: base supplied by Hans; external run specification
  not inspected, and the M5 hardware not available).
- [Scientific examples 2 and 3](mlxf_scientific_examples.md) and their applied review (validated:
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
| `doc/implementation_notes/planned/mlxf_m5_preparation_report.md` (new at handoff) | Final report; move with this plan when complete | 5 |
| `~/agent_work/mlxf_m5_preparation/4706ecb/` (external) | Logs, source manifests, disposable mutation copies, test supplement and host reference sources | 0, 1, 2, 3, 4, 5 |

## Progress

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
