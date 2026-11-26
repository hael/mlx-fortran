# The review's fixes, then the toys in the shape of SIMPLE's integration (run `mlxf_toy_seam`, M5 Ultra)

Status, 2026-11-25: planned and ruled (Hans: "Yes, go", on the decisions of section 3 as recommended); it
launches when release hardening's result is committed. Ordered by Hans on 2026-11-25: "We should implement the toy examples in mlx-fortran in the
same way so that we can model safely over here and make the integration easier downstream", and the same day:
"integrate the follow-up review items in your plan" (Codex's review of `0071f5a`, findings F1 to F4:
[`mlxf_quality_review_followup.md`](../completed/mlxf_quality_review_followup.md)). Base: the commit that holds
the result of run `mlxf_release_hardening` (the run pins its hash in Phase 0); the plan was checked against
`271c241`, whose sources are those of `0071f5a`. SIMPLE is read at `d354efee2` with
`git -C ~/src/SIMPLE show d354efee2:<path>`, never its working tree, and is never edited. Machine: the M5 Ultra
only. Supersedes: none. Depends on:
- run `mlxf_release_hardening` (validated: yes, delivered 2026-11-25; rebuilt from scratch in the session, the
  release gate passing with `--allow-dirty`). It edited `test/CMakeLists.txt`,
  `src/test/mlxf_test_registry.f90`, `scripts/release_gate.sh` and the two policies this plan edits, so this run
  starts from its commit and Phase 0 re-reads those files. It met F4 in 6 gate runs, each passing when rerun;
- the three toys as delivered: K1 and the polar calculator, K2's projector, K8's reconstructor (validated: yes,
  `unit_kernels` 1,732 on `0071f5a`, Debug and Release);
- Homebrew's `gcc@14` 14.4.0 beside `gcc` 16.2.0 (validated: installed 2026-11-25), for the probe of Phase 0.

## 1. Why

The toys show a kernel and where its GPU state lives (the toy policy's seam), but not how the code would sit in
SIMPLE's build and call tree. A read of SIMPLE at `d354efee2` found what the integration needs beyond a
workspace component:

- **A build without MLX.** SIMPLE builds on Linux, where there is no MLX. Its testers are dropped by a filename
  filter (`src/CMakeLists.txt`, line 150) because no production code calls them. Device code is called from
  production, so it needs a body in every build. SIMPLE's precedent is a body under a preprocessor definition
  with a stub beside it (`simple_reconstructor_openmpoffload.f90`, `simple_projector_pft_batch.f90`).
- **A parent module that does not import MLX.** A type that holds `type(mlx_array)` components makes its module,
  and every module that imports it, depend on `mlxf.mod`. In the toys today the calculator's parent imports the
  workspace type (`mlxf_toy_polarft_calc.f90`: `type(polarft_workspace), allocatable :: ws(:)`), and
  `mlxf_toy_polarft_core`, `mlxf_toy_projector_pft_batch`, `mlxf_toy_reconstructor_pcg` and `mlxf_toy_pcg_solver`
  import `mlxf` directly.
- **A caller with two shapes.** SIMPLE's `fill_tab_range` calls `score_block_posterior` from inside a parallel
  region, one block per thread (`simple_eul_prob_tab.f90`, lines 373 and 483). MLX is called by one thread from
  outside any parallel region, with blocks in flight (the toy's `submit_block` and `collect_block`). The fill
  needs both branches.

Each of these is a risk better met here, on small examples with oracles, than in SIMPLE.

**The review comes first.** Codex's follow-up review reproduced four defects in the code this run refactors: a
comparator that accepts a NaN (F1), a route switch that scores against stale memos (F2), a kernel cache that
ignores the volume's size (F3) and a memory check that races the GPU and failed the Release fast gate once in
two runs (F4). A refactoring judged by byte identity and by the fast gate needs them fixed before it starts.

## 2. Contract

- **The device route does not move.** Phase 1 changes behaviour only where the review found it wrong: a route
  switch after memoization and a resized volume. From Phase 2 on this is a refactoring of working code. Every
  sub-suite keeps the count it has at the end of Phase 1 and its frozen tolerances, and the identity cases of
  decision 13, which use fixed routes and sizes, stay byte for byte equal through every phase.
- **The off state.** With `l_mlx` false, no statement of a glue or device file runs. In a build without
  `USE_MLX` those bodies do not exist: the host set and the glue's stubs compile and link without the library,
  and the polar host route gives the same bytes there as in the full build (decision 6).
- **The library is not touched.** No file under `src/core` or `src/defs` changes; no public name is added.
- **The toy policy holds:** SIMPLE's names, dummy lists and call order; every difference declared; the mirror
  ledger current.
- **The house rules hold:** zero warnings in Debug and Release, one library target, the CTest budget of 9, no
  environment variable, no call into the library from a parallel region.

### What the check found (2026-11-25, on `271c241` and SIMPLE `d354efee2`)

| Toy file | Imports today | Class after (decision 2) |
| --- | --- | --- |
| `mlxf_toy_polarft_calc` (parent) | `mlxf_toy_polarft_workspace`, `mlxf_toy_projector` | host |
| `mlxf_toy_polarft_core` | `mlxf` (`mlx_array`), `mlxf_toy_projector_pft_batch` | host, its device part to glue |
| `mlxf_toy_polarft_memo`, `_block`, `_shiftmap` | `mlxf_test_defs` only; they call the workspace's bindings | host, those calls to glue |
| `mlxf_toy_eul_prob_tab` | `mlxf_test_defs`, the calculator | host |
| `mlxf_toy_polarft_workspace` and its four submodules | `mlxf` | device |
| `mlxf_toy_projector` (parent) | `mlxf_toy_projector_workspace` | host |
| `mlxf_toy_projector_pft_batch` | `mlxf` (`mlx_array`, `mlx_to`, `reshape`) | host, its device part to glue |
| `mlxf_toy_projector_workspace` | `mlxf` | device |
| `mlxf_toy_reconstructor_pcg` | `mlxf`; its adapter's bindings carry `mlx_array` dummies | host, those to glue |
| `mlxf_toy_reconstructor_pcg_workspace` | `mlxf` | device |
| `mlxf_toy_pcg_solver` | `mlxf`; the operator's interface is on `mlx_array` | device (decision 12) |

- `mlxf_test_defs` has no `use` statement, so the host set can import it.
- SIMPLE's `polarft_calc` is a parent with submodules by concern; `reconstructor_pcg` (2,793 lines) and
  `projector` are single modules with none.
- SIMPLE declares its tester entries in the parent's last interface block (`simple_polarft_calc.f90`), with the
  bodies in tester submodules. The glue follows that form.
- The toy's `score_block_posterior` is today a submission to the first slot and its collection: there is no host
  kernel in the toy.
- "Host route" and "device route" already name how K2's references reach the calculator
  (`POLARFT_REF_ROUTES`). This plan's switch is called the backend, to keep the two apart.
- The review's four locations hold at `271c241`:
  - F1: `history_errors` (`mlxf_toy_reconstructor_pcg_tester_solve.f90`) accumulates with scalar `max`, and rule
    `nanmax` matches `maxval(abs(` only. `rg '= max\(.*abs\('` finds 107 such lines under `src/test`
    (*measured*).
  - F2: `set_ref_route` (`mlxf_toy_polarft_core.f90`) refuses only while references are pending, and on a
    switch resets only the bins' generation.
  - F3: `kern_conf(3, 2)` in `mlxf_toy_projector_workspace.f90` holds `[npts, tn, tg]`, without `m`.
  - F4: `test_lifecycle` (`mlxf_toy_reconstructor_pcg_tester.f90`) samples `mlx_active_memory()` with no
    `mlx_synchronize()`, which is public. Eight more files under `src/test` read the active memory.

## 3. Decisions and rulings

1. (2026-11-25, Hans) **The toys take the shape SIMPLE's integration will have,** so that the integration is
   modelled here first. The shape is decisions 2 to 8.
2. (2026-11-25, recommended) **Three classes of toy file.** Testers are outside the classes.
   - *host*: the parents, their host submodules and the drivers. They import no MLX name and compile without
     the library.
   - *glue*: submodules of a toy class, the only files of the class that import `mlxf` or a device module.
   - *device*: ordinary modules that hold MLX state and kernels (the workspaces, the device PCG engine). They
     know nothing of the class that uses them.
3. (2026-11-25, recommended) **One opaque component.** A new host module `mlxf_toy_device_work` declares
   `type, abstract :: device_work` with one deferred binding, `kill`. A toy class holds its device state as
   `class(device_work), allocatable` (the calculator's `ws(:)` stays an array of two, one per half). The
   workspaces extend it. A holder calls `kill` on each element before it deallocates, so the release of MLX
   handles never rests on the compiler's finalization of a polymorphic component (decision 16).
4. (2026-11-25, recommended) **The glue sits beside the host code it serves.** One glue submodule per host
   submodule that crosses the seam, named `<host submodule>_mlx` (`mlxf_toy_polarft_block_mlx` beside
   `mlxf_toy_polarft_block`); a class without submodules gets `mlxf_toy_<stem>_mlx`. Its procedures are module
   procedures named `<host procedure>_mlx`, private to the class, declared in the parent in one interface block
   headed "MLX". The host procedure's whole knowledge of the device is a guarded call, `if( self%l_mlx ) call
   <name>_mlx(self, ...)`. No dummy of a host-class interface has an MLX type.
5. (2026-11-25, recommended) **`USE_MLX`, as SIMPLE's `USE_OPENMP_OFFLOAD`.** A glue file holds its body under
   `#ifdef USE_MLX` and, under `#else`, stubs that set the status and the message "built without MLX" and return.
   The definition is set on `mlxf_test_exec`, always. It appears in glue files only, once per file. Rejected: a
   stub twin file chosen by CMake, because the stub and the interface it must match would sit apart.
6. (2026-11-25, recommended) **The off-state build is proved by the compiler.** `test/offstate/` is a standalone
   CMake project that compiles the host set, the glue files without `USE_MLX`, `mlxf_test_defs` and the program
   `mlxf_offstate_exec`, with the project's flags, no path to the library's modules and no link to the library.
   `scripts/check_toy_offstate.sh` builds it in Debug and Release and runs the program, which:
   - runs the polar host route on the fixture of sub-suite `polarft_host` and writes its table;
   - asks each toy class for the MLX backend and checks the refusal and its message.

   The table equals, byte for byte, the one `mlxf_test_exec` writes with `l_mlx` false (Release, one thread).
   The script runs in `scripts/release_gate.sh` after `check_embed.sh`, and at every phase exit of this run. It
   is not a CTest entry.
7. (2026-11-25, recommended) **Rule `seam` and the ledger `scripts/toy_seam.txt`.** One line per `mlxf_toy_*`
   file that is not a tester: its class, or `pending`. The rule fails when:
   - such a file has no line;
   - a host file imports `mlxf`, a generated module or a device module, or names `USE_MLX`;
   - a glue file has such an import outside its `#ifdef USE_MLX` branch, or more than one `#ifdef`;
   - a device file imports a host or glue module of a toy class;
   - the number of `pending` lines grows.

   Each of the four kinds of violation is planted and shown to fail. `pending` is 0 at the end of Phase 6.
8. (2026-11-25, recommended) **The backend is chosen at `new`,** from a member `l_mlx` of the toy's `parameters`
   record (an addition; the name of SIMPLE's parameter is the maintainer's). It defaults to true in the toy, so
   every existing suite runs what it ran. In a build without `USE_MLX`, `new` with `l_mlx` true is refused with
   the stub's message. No environment variable is read.
9. (2026-11-25, recommended; it sets the run's size) **The polar toy gains a host route, and the fill both
   branches.**
   - `score_block_posterior` becomes host code with SIMPLE's dummy list: a miniature of SIMPLE's block kernel
     (`simple_polarft_block.f90`) with per-thread work, the sums per angular bin, each pair's inverse transform
     and the shared tail with the host's keyed variate, in single precision as in SIMPLE.
   - Its inverse transform is a direct sum. No FFT library enters the toy.
   - `fill_tab_range` selects once: the host branch calls `score_block_posterior` from inside
     `!$omp parallel do` over the blocks, as SIMPLE does; the MLX branch is today's serial submission and
     collection.
   - The host route is a model of control flow. It is never timed and no speed is claimed for it.
10. (2026-11-25, recommended) **The projector and the reconstructor get no host route.** Their callers keep one
    shape in SIMPLE, and SIMPLE's host code for them exists and is not modelled here. With `l_mlx` false their
    `new` is refused with "the toy has no host route". This is declared as a difference.
11. (2026-11-25, recommended) **What one class hands another on the device crosses as `class(device_work)`.**
    K2's device route passes the projector's sections to the calculator without leaving the GPU; the two glue
    submodules resolve the dynamic type with `select type`, and a wrong type is a refusal with a message.
12. (2026-11-25, recommended) **The device PCG engine is a device module.** `mlxf_toy_pcg_solver` is renamed
    `mlxf_toy_pcg_solver_mlx`: it is the engine SIMPLE would gain beside `simple_pcg_solver`, whose host engine
    the toy does not model. Its ledger lines keep their mirrored names. The reconstructor's adapter and every
    procedure with an `mlx_array` dummy move to the glue `mlxf_toy_reconstructor_pcg_mlx`.
13. (2026-11-25, recommended) **Identity cases.** Phase 0 names, for each toy, the output it compares: the
    digests `bench_projector` prints, and the tables and maps `bench_polar_table` and `bench_recon_pcg` write at
    their smallest timed setting. Each is produced twice on the base and must be equal there. After Phases 1, 3,
    5 and 6 each equals the base byte for byte, in Release on the GPU. A case is never rerun until it passes.
14. (2026-11-25, recommended) **The keep rule for speed.** Phase 0 times each of the three benchmarks twice at
    one process, at the setting its report gives. After Phase 6, the median rate of two runs is not more than
    max(the base's difference between its two runs, 2 %) below the base's (*measured* spread; 2 % *guessed*).
15. (2026-11-25, recommended) **New checks go to two new sub-suites of `unit_kernels`:** `seam` (the opaque
    component's lifecycle, the refusals, 1,000 cycles of `new` and `kill` per class with the registry's count
    unchanged) and `polarft_host` (decision 9's gates). Each takes at most 0.5 s in Release or says why in its
    registration comment.
16. (2026-11-25, recommended) **The compiler is probed before the design is used,** with GNU Fortran 16.2.0 and
    14.4.0, in standalone programs kept under the run's `scratch/keep/`:
    - a scalar and an array `class(device_work), allocatable` component whose dynamic type has a `final`
      procedure, through explicit `kill` and deallocation, scope exit and an `intent(out)` dummy, counting the
      calls;
    - a glue submodule compiled with and without `USE_MLX`;
    - `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` on a file with `#ifdef`, `#else` and
      `#endif`.

    A compiler defect gets a reproducer and an entry in `doc/compiler_issues/`. Extra or missing finalizations
    are tolerated, because `kill` is idempotent and explicit (decision 3).
17. (2026-11-25, recommended) **The gates of the host route** (sub-suite `polarft_host`):
    - against the oracle `mlxf_oracle_polar`, the distances and the drawn rotations, by the checks and at the
      tolerances the MLX backend's suite already has (*measured*, frozen in milestone 1 and K1);
    - the table is byte for byte the same with a team of 1 and of 4 threads;
    - the fill's two branches agree within those tolerances on seeds 1, 2 and 3.
18. (2026-11-25, recommended) **The order is the calculator, then the projector, then the reconstructor,**
    because the projector's hand-off needs the calculator's opaque component.
19. (2026-11-25, recommended) **Rank:** after release hardening and before the rest of parity, because the next
    kernels and SIMPLE's integration build on this shape and no consumer waits for parity's remaining functions.
20. (2026-11-25, recommended) **The record SIMPLE's integration reads.** `doc/how2s/how2use_from_simple.md`
    gains a table: for each toy file its class and the SIMPLE file it stands for (an existing file that gains a
    guarded call, or a new file beside it), and for each mirrored host procedure the statements it gained.

21. (2026-11-25, Hans: "integrate the follow-up review items in your plan") **The review's four findings are
    fixed in Phase 1, before any refactoring.** Each fix comes with the regression test the review asks for and
    a negative control shown to fail. The counts are frozen again at the end of Phase 1.
22. (2026-11-25, recommended) **F1: no error is reduced with a bare `max`.**
    - `history_errors` checks that both histories are allocated, long enough and finite, then reduces with
      `nan_maxval`.
    - `mlxf_test_reduce` gains a scalar `nan_max(a, b)`, which returns +infinity when either is a NaN.
    - Rule `nanmax` also fails on `x = max(x, abs(...))` in test code, with a plant. Every line it finds (107
      on the base, *measured*) is converted to `nan_max` or `nan_maxval`. None is exempted.
    - Negative controls: the comparator is called on copies of a real outcome with one NaN planted at the first,
      a middle and the last entry of each history. All 6 cases must give +infinity.
    - The review's mutation of the engine is repeated once in scratch and must fail `reconstructor_pcg` and
      `pcg_solver`.
23. (2026-11-25, recommended) **F2: a route switch that would leave stale memos is refused.** `set_ref_route`
    accepts a change only while no reference memo is current: before the first `memoize_refs`, or after the
    references were set anew. Otherwise it returns a message and changes nothing. Rejected: carrying the device
    memos to the host, a transfer SIMPLE has no counterpart for. Tests: both directions after projection, after
    memoization and after the bins exist (6 cases). Each either keeps the rows within the existing gate or is
    refused, and the review's sequence is refused.
24. (2026-11-25, recommended) **F3: the padded size enters the kernel's cache key.** `kern_conf` holds
    `[npts, tn, tg, m]`. Test: the review's case, an 8-cube then a 16-cube through one fused workspace. The
    reused workspace equals a fresh one byte for byte, and both agree with the graph form within the existing
    gate.
25. (2026-11-25, recommended) **F4: memory is sampled after the stream is synchronized.** `test_lifecycle` calls
    `mlx_synchronize()` before both samples, after releasing its temporaries. The exact equality and the
    live-handle assertion stay. The same holds for every other test that compares two samples of the active
    memory (eight more files read it; each is fixed or says why it needs no wait). Gate: the Release fast gate
    run 20 times in a row with `ctest --parallel 4` passes 20 times (*guessed* count; the review saw one failure
    in two runs). Decision 15's cycles follow the same practice.
26. (2026-11-25, recommended) **F4 in Phase 0 is a known failure of the base.** If the Release fast gate fails at
    the lifecycle assertion of `reconstructor_pcg` before Phase 1's fix, the failure is recorded with its log
    and the gate is run once more. Any other failure is judged as written.
27. (2026-11-25, recommended; from run `mlxf_release_hardening`) **GNU Fortran 16.2 is the gate; 14.4 is
    reported.** Release hardening found that 14.4 builds the library but not the test executable: it does not
    link a submodule's own plain procedures (`mlxf_toy_reconstructor_pcg_tester_solve`) and raises a false
    `-Wuninitialized` (`mlxf_bench_polar_table.f90`). So decision 16's probes and the off-state project are
    built with both compilers, and judged with 16.2. A 14.4 failure is recorded with its kind. A host or glue
    file this run writes keeps to the form 14.4 links (a module procedure with its interface in the parent)
    where that costs no mirrored dummy list.

Defaults taken without a question: the names `device_work`, `mlxf_toy_device_work`, the suffix `_mlx`, `USE_MLX`,
`l_mlx`, `toy_seam.txt`, rule `seam`, `mlxf_offstate_exec`, `check_toy_offstate.sh`, the sub-suites `seam` and
`polarft_host`, `nan_max`.

## 4. Not in this plan

- SIMPLE is not edited, and no SIMPLE source is copied in.
- No file under `src/core` or `src/defs`; no public name; no new kernel; no change to a Metal source.
- No oracle's arithmetic is edited.
- No host route for the projector or the reconstructor; no FFT library; no timing of the host route.
- No other accelerator (CUDA, OpenMP offload).
- K3 to K7: they are written in this shape from the start, by the policy's new section.
- The workflow and the release gate beyond the one added line (run `mlxf_release_hardening` owns them).

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement, probes | the base builds and passes (decision 26); identity cases equal twice; the probes recorded |
| 1 | fixes of the review; result-changing only in the two transitions | the common gate; decisions 22 to 25, each negative control failing; decision 13's cases; the counts frozen again |
| 2 | tests-only (the module, the rule, the off-state project) | the common gate; four plants fail; the off-state project builds |
| 3 | identical | the common gate; decision 13's polar case; `pending` down by the polar files |
| 4 | additive (the host route) | the common gate; decision 17; decision 6's byte comparison |
| 5 | identical | the common gate; decision 13's projector case; the refusals of decision 10 |
| 6 | identical | the common gate; decision 13's reconstruction case; `pending` is 0; decision 14 |
| 7 | documents | the static gate; the release gate with `--allow-dirty` |

The common gate: Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, the fast gate 9 of 9, every unit
area with `MLX_ENABLE_TF32=0`, every sub-suite of `unit_kernels` at its count at the end of Phase 1,
`scripts/check_tree.sh`, `scripts/check_embed.sh` and, from Phase 2 on, `scripts/check_toy_offstate.sh`.

## 6. Acceptance

- The review's four findings are closed: each regression test passes, each negative control fails, and the
  Release fast gate passes 20 times of 20 (decision 25).
- Every count frozen at the end of Phase 1 is kept (*exact*), and from Phase 2 on `unit_kernels` grows by the
  two new sub-suites only.
- Decision 13's cases are equal byte for byte (*exact*).
- Decision 14's rule holds for each of the three benchmarks.
- Rule `seam` passes with no `pending` line; the off-state project builds without the library in Debug and
  Release with GNU Fortran 16.2, and its program passes (decision 27 for 14.4).
- No tolerance is new. If the host route cannot meet a tolerance the MLX backend meets, that is a stop.
- Reported, not gated: the lines each mirrored host procedure gained (decision 20); the off-state build's time;
  the probes' counts of finalizations.

## 7. Common rules and stop conditions

- No file outside the table; no tolerance loosened and no test removed to pass; a fix found on the way gets a
  table row first. Timed steps follow the kernel runs' protocol: a one-minute load of at most 4, nothing else
  running, `uptime` before and after, never repeated until they pass.
- Read-only: `~/src/SIMPLE`, `~/src/mlx`, `~/src/mlx-c`, the maintainer's checkout, Homebrew. Git is read-only.

**Stops:**
- an identity case differs after any phase and the cause is not a defect of the base;
- a fix of Phase 1 would change a result at a fixed route and size, or a converted reduction (decision 22)
  makes a check of the base fail: the failure is a finding, reported with its evidence;
- the Release fast gate fails within decision 25's 20 runs after the fix;
- a count or a frozen tolerance of the base would have to move;
- decision 14's rule fails;
- a probe shows a handle that stays registered after an explicit `kill`, or a form the design needs that GNU
  Fortran 16.2 rejects;
- a host file cannot be freed of an MLX name without changing a mirrored dummy list;
- a change under `src/core` or `src/defs`, or a tenth CTest entry, would be needed;
- the base lacks run `mlxf_release_hardening`'s result.

**Gates no ruling may waive:** zero warnings; the static gate; byte identity of the device route; the off-state
project built without the library; the CTest budget; the mirror ledger current.

## 8. Phases

### Phase 0, the base, the identity cases and the probes

1. Record the machine, the base commit and the toolchain. Build Debug and Release from scratch; record every
   area's count per build and every sub-suite's count of `unit_kernels`.
2. Re-run the census of section 2 on the base (every `use` of every `mlxf_toy_*` file) and correct the table.
3. Name decision 13's cases, produce each twice, compare; time decision 14's benchmarks twice.
4. Run decision 16's probes with both compilers.
5. Freeze the counts, the cases' checksums and the base rates in Progress, each with its origin.

**Exit:** the numbers are frozen; the cases are equal twice; the probes are recorded and none is a stop.

### Phase 1, the follow-up review's fixes

Decisions 22 to 25, in the order F4, F1, F3, F2, so that the gate is steady before the other fixes are judged
by it. Each fix is one step: the regression test written and failing on the base, the fix, the test passing,
the negative control. Then the counts of every area and sub-suite are recorded again, and the review's file
gains a status line per finding.

**Exit:** the phase's gate of section 5; the counts frozen again in Progress, each with what it gained.

### Phase 2, the seam's parts

`mlxf_toy_device_work`; `scripts/toy_seam.txt` with every toy file `pending` or classed as it stands; rule `seam`
and its four plants; `USE_MLX` on `mlxf_test_exec`; `test/offstate/` with a program that so far only starts;
`scripts/check_toy_offstate.sh`; sub-suite `seam` with the abstract type's lifecycle on a test double.

**Exit:** the phase's gate of section 5.

### Phase 3, the polar calculator and its driver

The opaque `ws(:)`; the glue submodules of `_core`, `_memo`, `_block` and `_shiftmap`; the parent's "MLX"
interface block; `l_mlx` in `parameters` and in `new`; the mirror ledger's new lines.

**Exit:** the phase's gate; the calculator's and the driver's files are classed.

### Phase 4, the polar host route and the fill's two branches

Decision 9; sub-suite `polarft_host` with decision 17's gates, tolerances read from the existing suite; the
off-state program's table and refusals; decision 6's byte comparison.

**Exit:** the phase's gate.

### Phase 5, the projector

`mlxf_toy_projector` and `mlxf_toy_projector_pft_batch` as host files with their glue; decision 11's hand-off;
decision 10's refusal.

**Exit:** the phase's gate; K2's sub-suites `projector`, `projector_chain` and `oracle_projection` at their counts.

### Phase 6, the reconstructor

Decision 12; `mlxf_toy_reconstructor_pcg` as a host file with its glue; decision 10's refusal; decision 14's
timings.

**Exit:** the phase's gate; `pcg_solver`, `reconstructor_pcg` and `reconstructor_pcg_n32` at their counts.

### Phase 7, the record

1. The toy policy's new section "The integration shape" (the three classes, the opaque component, the glue's
   form, the off-state build, the backend switch), and the seam sections of `mlxf_kernel_families.md`.
2. Decision 20's table in `doc/how2s/how2use_from_simple.md`; the test policy's lines on the two sub-suites and
   the off-state check and on synchronizing before a memory sample; the roadmap's row; the history entry; the
   plans' index.
3. The report in the order of `doc/how2s/how2write_agent_plans.md`, section 8, with a commit message that names
   every new file and carries no attribution or co-author line.

**Exit:** the release gate passes with `--allow-dirty`; the report exists; `git status` shows only file-table
paths.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90`, `src/test/mlxf_toy_reconstructor_pcg_tester.f90`, `src/test/mlxf_toy_pcg_solver_tester.f90` | F1's comparator and controls; F4's synchronization | 1 |
| `src/test/mlxf_test_reduce.f90` | `nan_max` | 1 |
| every file under `src/test` and every `*_tester.f90` that rule `nanmax` names, or that compares two samples of the active memory | decision 22's conversion; decision 25's wait; no other change | 1 |
| `src/test/mlxf_toy_polarft_core.f90`, `src/test/mlxf_toy_polarft_memo.f90`, `src/test/mlxf_toy_projector_tester.f90` | F2's refusal and its six cases | 1 |
| `src/test/mlxf_toy_projector_workspace.f90` | F3's cache key (its test in `mlxf_toy_projector_tester.f90`) | 1 |
| `doc/implementation_notes/completed/mlxf_quality_review_followup.md` | a status line per finding | 1 |
| `src/test/mlxf_toy_device_work.f90` (new) | the abstract opaque type | 2 |
| `scripts/toy_seam.txt` (new), `scripts/check_rules.py` | rule `nanmax`'s scalar form (Phase 1); the ledger and rule `seam` | 1 to 6 |
| `test/offstate/CMakeLists.txt`, `test/offstate/mlxf_offstate_exec.f90`, `test/offstate/offstate.inf` (new) | the off-state project | 2, 4 to 6 |
| `scripts/check_toy_offstate.sh` (new), `scripts/release_gate.sh` | the off-state check and its one line in the release gate | 2 |
| `test/CMakeLists.txt` | `USE_MLX` on `mlxf_test_exec` | 2 |
| `src/test/mlxf_toy_polarft_calc.f90`, `_core`, `_memo`, `_block`, `_shiftmap` | host files | 3, 4 |
| `src/test/mlxf_toy_polarft_core_mlx.f90`, `_memo_mlx`, `_block_mlx`, `_shiftmap_mlx` (new; fewer if a host submodule does not cross the seam) | the calculator's glue | 3, 4 |
| `src/test/mlxf_toy_polarft_workspace.f90` and its submodules | extends `device_work`; no other change | 3 |
| `src/test/mlxf_toy_eul_prob_tab.f90` | the fill's two branches | 3, 4 |
| `src/test/mlxf_toy_projector.f90`, `mlxf_toy_projector_pft_batch.f90` | host files | 5 |
| `src/test/mlxf_toy_projector_mlx.f90`, `mlxf_toy_projector_pft_batch_mlx.f90` (new) | the projector's glue | 5 |
| `src/test/mlxf_toy_projector_workspace.f90` | extends `device_work` | 5 |
| `src/test/mlxf_toy_reconstructor_pcg.f90` | a host file | 6 |
| `src/test/mlxf_toy_reconstructor_pcg_mlx.f90` (new) | the reconstructor's glue | 6 |
| `src/test/mlxf_toy_pcg_solver.f90` to `mlxf_toy_pcg_solver_mlx.f90` (renamed) | the device engine | 6 |
| `src/test/mlxf_toy_reconstructor_pcg_workspace.f90` | extends `device_work` | 6 |
| `src/test/mlxf_toy_seam_tester.f90`, `src/test/mlxf_toy_polarft_host_tester.f90` (new) | the two sub-suites | 2, 4 |
| the existing testers and benchmarks of the three toys | `l_mlx` where they build `parameters`; a renamed import; no check changed | 3 to 6, if needed |
| `src/test/mlxf_test_defs.f90`, `src/test/mlxf_test_registry.f90`, `src/test/test.inf` | `l_mlx`, the sub-suites' rows, the new files' lines | 2 to 6 |
| `scripts/toy_mirror.txt` | the additions and the renamed module | 3 to 6 |
| `doc/compiler_issues/` | a reproducer, if a probe finds a defect | 0 |
| `doc/policies/toy_example_policy.md`, `doc/policies/test_environment_policy.md`, `doc/how2s/how2use_from_simple.md`, `doc/implementation_notes/planned/mlxf_kernel_families.md`, `doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md`, `README.md` | the record | 7 |
| `doc/implementation_notes/completed/mlxf_toy_seam_report.md` (new) | the report | 7 |
| this plan | Progress | every phase |

## Progress

(one entry per phase, written by the run)
