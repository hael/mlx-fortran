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
| `scripts/check_toy_offstate.sh` (new), `scripts/release_gate.sh` | the off-state check and its one line in the release gate; (Phase 6, a defect the session's rebuild found) a relative `--exec` or `--fc` path is made absolute when the option is read | 2, 6 |
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
| (ruling R2, replacing the row above) `src/test/mlxf_toy_pcg_solver.f90`; `src/test/mlxf_toy_pcg_solver_mlx.f90` (new) | the host half, which keeps `pcg_solver_outcome`; the device engine (`pcg_operator`, `pcg_solve`) | 6 |
| `src/test/mlxf_toy_reconstructor_pcg_workspace.f90` | extends `device_work` | 6 |
| `src/test/mlxf_toy_seam_tester.f90`, `src/test/mlxf_toy_polarft_host_tester.f90` (new) | the two sub-suites | 2, 4 |
| `src/test/mlxf_polarft_host_fixture.f90` (new; row added by the run in Phase 4, before the file) | the host route's fixture, its fill through the driver and the table's lines, shared by sub-suite `polarft_host` and the off-state program | 4 |
| the existing testers and benchmarks of the three toys | `l_mlx` where they build `parameters`; a renamed import; no check changed | 3 to 6, if needed |
| (ruling R3) `src/test/mlxf_toy_reconstructor_pcg_tester.f90`, `src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90`, `src/test/mlxf_bench_recon_pcg.f90` | the call sites of the five operator procedures change form to the opaque operator; ruling R1's new checks; no existing check, tolerance or expected value changes | 6 |
| `src/test/mlxf_test_defs.f90`, `src/test/mlxf_test_registry.f90`, `src/test/test.inf` | `l_mlx`, the sub-suites' rows, the new files' lines | 2 to 6 |
| `scripts/toy_mirror.txt` | the additions and the renamed module | 3 to 6 |
| `doc/compiler_issues/` | a reproducer, if a probe finds a defect | 0 |
| `doc/policies/toy_example_policy.md`, `doc/policies/test_environment_policy.md`, `doc/how2s/how2use_from_simple.md`, `doc/implementation_notes/planned/mlxf_kernel_families.md`, `doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md`, `README.md` | the record | 7 |
| `doc/implementation_notes/completed/mlxf_toy_seam_report.md` (new) | the report | 7 |
| this plan | Progress | every phase |

## Progress

(one entry per phase, written by the run)

### Phase 0, the base, the identity cases and the probes (2026-11-26, 01:09 to 01:26, M5 Ultra)

Base `6f1af0d` (clean; it holds run `mlxf_release_hardening`'s result). Apple M5 Ultra, 30 cores, 96 GiB, macOS
27.2.1; GNU Fortran 16.2.0 (the gate) and 14.4.0 (reported), CMake 4.5.1, MLX 0.32.4, mlx-c 0.8.0; one GPU device
(`applegpu_g17d`). The run works in a scratch copy; logs are under the run's `scratch/keep/phase0/` (paths below are
relative to `scratch/keep/`). Files changed: this plan (Progress). The rulings file is empty.

**Exit items.**
- **The base builds and passes** (`phase0/base_{debug,release}.{configure,build,gate,install}.log`): Debug and
  Release from scratch with `MLXF_WERROR=ON`, 0 warnings, the fast gate 9 of 9 in both, on the first run. Decision
  26's known failure (F4) did not show in these two gate runs. `scripts/check_tree.sh` passes;
  `scripts/check_embed.sh` passes (`phase0/check_embed.log`).
- **The counts** (*measured*, Debug and Release equal; `phase0/areas_{debug,release}_<area>.log`,
  `phase0/kernels_subsuites_{debug,release}.txt`): `unit_core` 182 or 183 (its sub-suite `registry` asserts once
  more when the allocator reuses an address: 36 or 37 run to run, a property of the base, in `src/core`),
  `unit_array` 193, `unit_ops` 2,462, `unit_linalg` 632, `unit_fft` 194, `unit_compile` 63, `unit_fast` 94,
  `unit_kernels` 1,732: `polarft_calc` 327, `polar_shiftmap` 794, `eul_prob_tab` 105, `polarft_tail` 55,
  `oracle_projection` 44, `projector` 96, `projector_chain` 75, `pcg_solver` 84, `reconstructor_pcg` 152.
- **The census** (`phase0/census_use.txt`): the table of section 2 holds, with the imports it leaves out:
  `mlxf_toy_polarft_calc` also imports `mlxf_test_defs`; `mlxf_toy_projector_pft_batch` also `mlxf_test_defs`,
  `mlxf_toy_projector` and `mlxf_toy_polarft_calc`; `mlxf_toy_reconstructor_pcg` also `mlxf_test_defs`,
  `mlxf_toy_pcg_solver` and its workspace; `mlxf_toy_pcg_solver` also `mlxf_test_defs`. `mlxf_test_defs` has no
  `use` statement. F1's count holds (107 lines under `src/test`, 84 of them in the oracle files, which already
  import `mlxf_test_reduce` for `nan_maxval`); **30 more such lines are in five testers under `src/core`**
  (`mlxf_linalg_products_tester` 12, `mlxf_linalg_matrix_tester` 12, `mlxf_fft_nd_tester` 3, `mlxf_linalg_mm_tester`
  2, `mlxf_ops_math_tester` 1), where this run may not edit. F4's count is corrected: besides the lifecycle test,
  six files under `src/test` read the active memory (three benchmarks, the testers of `polarft_calc`, the shift
  maps and the projector), and three testers under `src/core` (array, error, memory), not eight under `src/test`.
- **Decision 13's cases, named** (`tools/identity.sh`, Release, 11 invocations, 57 lines in
  `identity_base.txt`, SHA-256 `7d8d7bfc...a77d5a`; the two base sets `phase0/identity_{a,b}/` are equal byte for
  byte):
  - polar: the digest lines of `bench_polar_table` `suite=time case=1000_1 bt=64 rt=250 nthr=30 device=gpu` with
    `tail=graph` and `tail=metal`; of `suite=accuracy case=2500_4` on both devices (graph) and on the GPU
    (`tail=metal`), 155 and 98 assertions passing; of `suite=shiftmap case=1000_1 maps=window,screen ptiles=16
    device=gpu` on a grid written for this run (`identity_grid.txt`: the M5 run's window and screen geometry, 4
    candidates; never timed against SIMPLE);
  - projector: the digest lines of `bench_projector` `suite=time` (`form=fused tile=2500 tg=64`, and `form=graph`)
    and `suite=chain` on `route=device` and `route=host`;
  - reconstruction: `bench_recon_pcg suite=time n=160 out=map` for `system=P` (F2, F5) and `system=R` (E, R4): the
    four maps' SHA-256 and the history lines in hexadecimal.
  The case file `polar_case.txt` is the kernel runs' (four cases of SIMPLE's `block_prod` rows).
- **Decision 14's base rates** (*measured*, one process, 30 threads, each twice, the load 2.2 to 3.7 before each,
  no other test or build process; `phase0/timing/`, `tools/timing.sh`):

  | Benchmark, setting | Run a | Run b | Base (their mean) | Base's difference | Floor after Phase 6 |
  | --- | --- | --- | --- | --- | --- |
  | `bench_polar_table suite=time case=2500_4 bt=64 rt=250 passes=9 tail=graph` through `scripts/run_parts.sh`: summed median pairs/s | 1.76305e7 | 1.76414e7 | 1.763595e7 | 0.06 % | 1.728323e7 (2 % below) |
  | `bench_projector suite=time form=fused tile=2500 tg=64 passes=9` through `scripts/run_parts.sh`: summed median samples/s | 1.41247e9 | 1.40532e9 | 1.408895e9 | 0.51 % | 1.380717e9 (2 % below) |
  | `bench_recon_pcg suite=time system=P` (n = 160 and 256, F2 and F5): 4 assemblies over the sum of the four best-of-three driver times | 4.31081 /s (0.9279 s) | 4.30339 /s (0.9295 s) | 4.30710 /s | 0.17 % | 4.22096 /s (2 % below) |

  The reconstruction's rows: 0.0838 and 0.0836 s (160, F2), 0.1037 and 0.1013 s (160, F5), 0.3287 and 0.3316 s
  (256, F2), 0.4117 and 0.4130 s (256, F5), the passes bit for bit equal.
- **Decision 16's probes** (`phase0/probes/`, GNU Fortran 16.2.0 and 14.4.0, each with the Debug and the Release
  flags of the project and `-Werror`; the two compilers agree in every count):
  - `final/`: a scalar and an array `class(device_work), allocatable` component whose dynamic type has a scalar
    `final` procedure. Explicit `kill` of every element, then `deallocate`: every handle released (3 of 3), one
    more call of the final procedure for the scalar component and none for the array (a rank-1 array has no
    matching final procedure, which is the standard's rule, not a defect). Without an explicit `kill`, scope exit
    and an `intent(out)` dummy release the scalar component's handle (1 final call) and leave the array's two
    registered. A holder that has its own `final` procedure calling `kill`, the toy classes' form, releases all
    three at scope exit and through `intent(out)`. **The array component is the reason decision 3's explicit `kill`
    is required, and it suffices.**
  - `seam/`: a host parent with a guarded call, a host submodule, a glue submodule with its body under `#ifdef
    USE_MLX` and stubs under `#else`, a device module holding real `mlx_array` handles. With `USE_MLX`, linked
    with the library (16.2: the base's; 14.4: the library alone built with 14.4, `phase0/lib14.build.log`): the
    device score is right, `mlx_live_count()` is back after an explicit `kill`, after 1,000 cycles (active memory
    0 B before and after, synchronized), after scope exit and after an `intent(out)` dummy. Without `USE_MLX`,
    with no path to the library's modules and no link to it: the host route runs, `new` with the MLX backend is
    refused with "built without MLX", and the program has no undefined MLX symbol.
  - `format/`: `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` leave a glue file in house form
    unchanged and bring a file written without the layout into it, both branches, without touching a
    preprocessor line. A glue-form submodule of `mlxf_toy_polarft_calc` planted in a copy of the base passes
    `scripts/check_tree.sh` (one `#ifdef`, two `implicit none`, two `contains`).
  - No compiler defect was found; `doc/compiler_issues/` gains nothing. No probe is a stop.

**Decisions taken under delegation.**
1. **The reconstruction's judged rate is one number,** four assemblies over the sum of the four rows' best-of-three
   driver times of one invocation (decision 14 asks for one rule per benchmark; the rows are reported).
2. **`passes=9` for the two launcher benchmarks** (the polar bench as in K1's verdict rows; the projector's
   report used 3): the fused projector's pass is 0.04 s, and nine passes give a steadier median. Frozen here,
   before any judged run.
3. **A shift-map identity case on a grid written for this run** (the M5 geometry on case `1000_1`, 4 candidates):
   the calculator's shift-map glue crosses the seam and the dense digests do not see it. Its digests are compared,
   never timed.
4. **The accuracy suites join the identity cases** (their digests on both devices): they add the CPU device and
   the frozen bounds' 155 and 98 assertions to each comparison.
5. **Rule `nanmax`'s scalar form will keep the existing rule's scope** (all test code) **with a ledger for the five
   testers under `src/core`** (30 lines), which may only shrink: the plan's count of 107 is that of `src/test`,
   the contract and the run's instructions forbid an edit under `src/core`, and a rule that silently left those
   testers out would let the class regrow there. The 30 lines are left for the maintainer (the report).

**What it means, in short.** The base is sound on this machine: both builds clean, the gate steady in two runs, the
eleven identity invocations bit for bit repeatable, the three rates within 0.5 % between two runs. The design's
forms compile and behave alike under both compilers, and the one thing the compiler will not do for a polymorphic
component, finalizing an array through a scalar final procedure, is what the explicit `kill` covers.

### Phase 1, the follow-up review's fixes (2026-11-26, 01:26 to 01:53, M5 Ultra)

Base `6f1af0d`; the rulings file is empty. Order: F4, F1, F3, F2. Logs under `scratch/keep/phase1/`; the plants are
patched copies of the working tree built apart (`tools/plant.sh`, `phase1/plants/<name>.{log,diff}`), the repository
never edited for one. Files changed: 27 (`phase1/git_status.txt`): `scripts/check_rules.py`,
`src/test/mlxf_test_reduce.f90`, the three polar files of F2 (`mlxf_toy_polarft_calc.f90`, `_core`, `_memo`),
`mlxf_toy_projector_workspace.f90`, the testers of the projector, the PCG engine and the reconstructor (two files),
15 more files that rule `nanmax` named (9 oracles, 3 benchmarks, 3 testers), the review's file and this plan.

**F4, memory sampled after the stream is synchronized (decision 25).**
- **The base fails:** the Release fast gate with `ctest --parallel 4`, 20 runs in a row on the base: 19 passed, run 2
  failed at the lifecycle assertion of `reconstructor_pcg`, 1,731 of 1,732 (`phase1/f4_base_gate20/`; the counting
  script's first summary line was wrong and is corrected beside it). *measured*: 1 failure in 20.
- **The fix:** `test_lifecycle` calls `mlx_synchronize()` before both samples, after its temporaries are released;
  the exact equality and the live-handle assertion stay.
- **The gate:** 20 of 20 with the fix alone (`phase1/f4_fixed_gate20_first/`), and 20 of 20 on the phase's final
  tree built from scratch (`phase1/gate20/`).
- **Negative control:** a handle left alive by the cycles fails both assertions on both devices, 4 of 172
  (`plants/f4_leak`).
- **The other tests that compare two samples:** the lifecycle tests of `polarft_calc`, the shift maps and the
  projector already synchronize before both; the three benchmarks read one sample for a row and compare nothing;
  the three testers under `src/core` synchronize before every pair (read, not edited). No other file needed a wait.

**F1, no error reduced with a bare `max` (decision 22).**
- `history_errors` returns +infinity for both histories when either is unallocated, shorter than asked or holds
  a value that is not finite, then reduces with `nan_maxval`. `mlxf_test_reduce` has the elemental `nan_max(a, b)`
  for real32 and real64.
- **Rule `nanmax`, scalar form:** an assignment whose right side opens with `max(` and holds an `abs(`, read on the
  whole statement. It finds 112 statements under `src/test` (*measured*; the plan's 107 counted lines, and five
  statements have their `abs(` on a continuation line), all converted: 88 two-operand ones to `nan_max`, 23 longer
  ones to `nan_maxval([...])`, one (which rule `ctorexpr` refuses inside a constructor) to nested `nan_max`. None
  is exempted. The 30 statements in five testers under `src/core` are in `NANMAX_LEDGER` (Phase 0, decision 5).
  Plants: one accumulation added to a tester fails the static gate (`plants/rule_nanmax_scalar`); one more in a
  ledger file fails it as above its entry (`plants/rule_nanmax_ledger`).
- **No converted reduction made a check of the base fail:** every area and sub-suite passes, both builds.
- **Negative controls, in the suite:** `test_history_controls` (per device) plants one NaN at the first, a middle
  and the last entry of each history of a real outcome (system P, five iterations): all 6 give +infinity; a missing
  and a short history give it too. With the base's comparator under these controls all 6 fail, and the process
  then stops in the base's read of an unallocated history (`plants/f1_old_comparator`).
- **The review's mutation,** repeated once on the fixed tree: `reconstructor_pcg` fails 20 of 172 and `pcg_solver`
  2 of 86 (`plants/f1_engine_mutation`). `pcg_solver` gained the check it fails on: both histories hold one finite
  value per iteration.
- The named-size history check (`test_solve_n32`) refuses a missing or short history and accumulates with `nan_max`.

**F3, the padded size in the cache key (decision 24).** `kern_conf` holds `[npts, tn, tg, m]`. Test
`test_workspace_resize` (GPU): the review's case through one fused workspace. Before the fix it fails 2 of 100 (the
reused workspace differs from a fresh one; 1.52 of a sample's scale against the gate 3.0e-6:
`phase1/f3_before_fix_projector.log`, and again as `plants/f3_key_without_m`); with it the reused workspace equals
the fresh one bit for bit and both are within 3.0e-8 of the graph form (gate `POLAR_ROW_FACTOR * PROJ_FIXTURE_ERR`,
the fixtures' own; the scale of a sample is `OSMPL_PAD_FAC**3 / M**3`, *exact* for a unit voxel).

**F2, a route switch that would leave stale memos is refused (decision 23).** `set_ref_route` refuses a change once
a reference is memoized (`l_refs_memoized`, set by the `memoize_refs` that memoized one, cleared by `kill`); the
refusal while references wait stays. Test `test_chain_route_switch` (both devices): from either route, after the
projection, after `memoize_refs` and after `memoize_ref_bins` (6 cases), each is refused and the run's rows equal
those of a run that never asked, bit for bit. The review's sequence (device to host after `memoize_refs`) is one of
them. Without the new refusal 8 of the 12 checks of a device fail (`plants/f2_no_refusal`).

**The counts, frozen again** (*measured*, Debug and Release equal; `phase1/exit/`): `unit_core` 182 or 183,
`unit_array` 193, `unit_ops` 2,462, `unit_linalg` 632, `unit_fft` 194, `unit_compile` 63, `unit_fast` 94,
`unit_kernels` 1,782 (+50): `polarft_calc` 327, `polar_shiftmap` 794, `eul_prob_tab` 105, `polarft_tail` 55,
`oracle_projection` 44, `projector` 100 (+4: F3's test on the GPU), `projector_chain` 99 (+24: F2's 12 per device),
`pcg_solver` 86 (+2: the histories' soundness per device), `reconstructor_pcg` 172 (+20: F1's 10 per device).
Named-only, Release: `reconstructor_pcg_n32` 96 (173 s), `polar_shiftmap_accuracy` 48.

**Exit items.**
- The common gate (`phase1/exit/summary.txt`): Debug and Release from scratch, `MLXF_WERROR`, 0 warnings, the fast
  gate 9 of 9 in both, every area passing outside CTest, `check_tree.sh` and `check_embed.sh` passing.
- Decision 13: the eleven identity invocations on the Phase 1 Release build equal the base byte for byte
  (`phase1/identity/identity.txt`).
- Decision 25: 20 of 20.
- The review's file has a status line per finding.

**Decisions taken under delegation.**
6. **F2's "after the references were set anew" has no reachable state:** a reference set anew waits to be
   memoized, which the base already refuses (its test stays), and setting one reference anew leaves the others'
   memos current on the old route. So the route is fixed from the first memoization until `kill` and `new`; the
   message says so.
7. **The longer `max` lists become `nan_maxval([...])`,** not nested `nan_max`: one reduction, the line structure
   kept.
8. **F1's controls test two more cases** (a missing and a short history), and `pcg_solver` checks the histories'
   soundness rather than a new tolerance on their values.

**What it means, in short.** The four findings are closed with a test each that fails without its fix, the gate is
steady (20 of 20 where the base gave 19), and nothing at a fixed route and size moved: the identity cases are the
base's bytes.

### Phase 2, the seam's parts (2026-11-26, 01:53 to 02:00, M5 Ultra)

Base `6f1af0d` with Phase 1; the rulings file is empty. Logs under `scratch/keep/phase2/`. Files: new
`src/test/mlxf_toy_device_work.f90`, `src/test/mlxf_toy_seam_tester.f90`, `scripts/toy_seam.txt`,
`scripts/check_toy_offstate.sh`, `test/offstate/{CMakeLists.txt, mlxf_offstate_exec.f90, offstate.inf}`; changed
`scripts/check_rules.py`, `scripts/toy_mirror.txt` (the opaque type's two lines), `scripts/release_gate.sh` (one
line and its header), `test/CMakeLists.txt` (`USE_MLX`), `src/test/mlxf_test_registry.f90`, `src/test/test.inf`.

**What was built.**
- `device_work`, abstract, one deferred binding `kill`.
- The ledger: 18 files, 1 host (`mlxf_toy_device_work`), 7 device (the three workspaces with the polar one's four
  submodules), 10 pending (`SEAM_PENDING = 10`).
- Rule `seam` (the docstring of `scripts/check_rules.py` states it). A host file may not name `USE_MLX`; a device
  file may import `mlxf_toy_device_work`, the type it extends, and no other host module.
- `USE_MLX` is a compile definition of `mlxf_test_exec`.
- `test/offstate/`: a project of its own that includes the library's `cmake/CompilerConfig.cmake` for its flags
  and reads the ledger for its sources (every file classed host or glue), so that a class in the ledger is a
  claim the compiler checks. Its program so far starts.
- `scripts/check_toy_offstate.sh`: Debug and Release in a scratch directory, `MLXF_WERROR`, no warning, no
  undefined MLX symbol, the program run; with `--exec` the host route's table against `mlxf_test_exec`'s (Phase
  4). 1 to 2 s per build (*measured*).
- Sub-suite `seam`, 22 checks (11 per device): the opaque components of a holder on a test double with a real
  `mlx_array`; explicit `kill` and idempotence, `new` on a holder in use, scope exit and an `intent(out)` dummy
  through the holder's final procedure, 1,000 cycles with the live handles and the synchronized active memory as
  they were, a device state of another type refused with a message. 0.03 s in Release.

**Exit items.**
- The common gate (`phase2/exit/summary.txt`): both builds from scratch, 0 warnings, 9 of 9, every area passing,
  `unit_kernels` 1,804 = Phase 1's 1,782 plus `seam` 22, every other sub-suite at its Phase 1 count;
  `check_tree.sh`, `check_embed.sh` and `check_toy_offstate.sh` passing.
- The plants (`phase2/plants/`), each failing the static gate with its own message: a host file that imports
  `mlxf`, one that imports a device module, one that names `USE_MLX`; a glue file with an import under `#else`,
  with one before its `#ifdef`, with a second `#ifdef`; a device file that imports a host module; a pending count
  that grows; a file without a line. Two controls pass (a glue file in its form; a new host module nothing
  imports).
- The off-state project builds and runs with GNU Fortran 16.2.0 (the gate) and 14.4.0
  (`phase2/offstate_gfortran14/`), Debug and Release.

**Decisions taken under delegation.**
9. **The table of the host route is written as lines of standard output in hexadecimal** (`polarft_host ...`), by
   the off-state program and by sub-suite `polarft_host` alike, and the script compares the lines. `mlxf_test_exec`
   refuses an argument a unit test does not know, its program is not in the file table, and a fast test leaves no
   file behind.
10. **Rule `arity` exempts the `_mlx` twin of a mirrored procedure** (and nothing else: a six-dummy `_mlx` procedure
    that mirrors nothing fails, `plants/arity_twin_only`): a guarded call hands the glue the host procedure's own
    list, which is what SIMPLE's integration would write.
11. **The off-state project takes its flags and its sources from the repository** (`CompilerConfig.cmake`, the
    ledger) instead of restating them.
12. **Until its phase, a file that already passes its class's rule stays `pending`** when its class is not yet true
    in fact (the host submodules that still call the workspace's bindings, the engine before its rename).

**What it means, in short.** The seam's parts exist and are checked before any toy uses them: the type, the
ledger with its rule and nine failing plants, the definition, and a second build that needs no library.

### Phase 3, the polar calculator and its driver (2026-11-26, 02:00 to 02:12, M5 Ultra)

Base `6f1af0d` with Phases 1 and 2; the rulings file is empty. Logs under `scratch/keep/phase3/`. Files: new
`src/test/mlxf_toy_polarft_{core,memo,block,shiftmap}_mlx.f90`; changed `mlxf_toy_polarft_calc.f90`, `_core`,
`_memo`, `_block`, `_shiftmap`, `mlxf_toy_polarft_workspace.f90` (it extends `device_work`; nothing else),
`mlxf_test_defs.f90` (`parameters%l_mlx`, default true), `mlxf_toy_seam_tester.f90`, `scripts/toy_seam.txt`,
`scripts/check_rules.py` (`SEAM_PENDING` 4), `test/offstate/CMakeLists.txt` (see decision 13). The driver
`mlxf_toy_eul_prob_tab.f90` needed no edit to be a host file; no tester or benchmark of the polar toy changed.

**What was built.**
- The parent imports `mlxf_toy_device_work` and no longer the workspace; `ws(:)` is `class(device_work),
  allocatable`, allocated on the MLX backend only; `l_mlx` is taken from `parameters` in `new`. `kill` and
  `kill_ref_bins` kill every element through the deferred binding, then deallocate: no glue for them.
- Fifteen glue procedures in four submodules, declared in the parent's last interface block, "MLX":
  `new_mlx`, `vol_pad2ref_pfts_opt_mlx` (core); `get_ref_pft_mlx`, `memoize_refs_mlx`, `memoize_ref_bins_mlx`
  (memo); `score_block_posterior_mlx`, `submit_block_mlx`, `collect_block_mlx`, `stage_seconds_mlx` (block);
  `new_shiftmap_mlx`, `kill_shiftmap_mlx`, `shiftmap_mode_mlx` and three inquiries (shift maps). Each resolves the
  dynamic type with `select type`, and each has a stub under `#else` that refuses with "built without MLX".
- One host helper became a module procedure, `prepare_block` (a block's checks and host inputs, the former
  `queue_block` less its submission): the glue and, from Phase 4, the host kernel share it.
- On the host backend: the device route, a shift map and a block in flight are refused with a message that names
  the MLX backend; `score_block_posterior` is refused until Phase 4 gives it its kernel.
- Sub-suite `seam` gained the calculator: 46 checks (23 per device), 0.05 s in Release: 1,000 cycles of `new` and
  `kill` (every hundredth with references and device tiles) leave the live handles and the synchronized active
  memory as they were; the host backend makes no device object from `new` to `kill`; its four refusals.

**Exit items.**
- The common gate (`phase3/exit/summary.txt`): both builds from scratch, 0 warnings, 9 of 9, every area passing;
  `unit_kernels` 1,828 = 1,782 + `seam` 46, every sub-suite of Phase 1 at its count; `check_tree.sh`,
  `check_embed.sh`, `check_toy_offstate.sh` passing.
- Decision 13: all eleven identity invocations (the polar ones and the others) equal the base byte for byte
  (`phase3/identity/identity.txt`).
- The ledger: 22 files, 7 host, 4 glue, 7 device, 4 pending (`mlxf_toy_pcg_solver`, `mlxf_toy_projector`,
  `mlxf_toy_projector_pft_batch`, `mlxf_toy_reconstructor_pcg`); the calculator's and the driver's files are
  classed.
- Plants (`phase3/plants/`): the glue collecting from the other parity's workspace fails `polarft_calc` and
  `eul_prob_tab`; the reference bins made through the glue whatever the backend fail `seam`.

**Decisions taken under delegation.**
13. **Phase 5 runs before Phase 4, and until it has run the off-state project holds the calculator's files back.**
    The calculator's parent imports `mlxf_toy_projector` (the type of `vol_pad`) and its core submodule imports
    `mlxf_toy_projector_pft_batch` (`fproject_polar_batch_opt`, the host route of `vol_pad2ref_pfts_opt`), so the
    calculator compiles without the library only once the projector's files are host files too. Phase 4's
    off-state table therefore cannot be built before Phase 5. Decision 18's order of the classes (calculator,
    projector, reconstructor) is kept; only the host route moves behind the projector. The transient list
    `_held_back` in `test/offstate/CMakeLists.txt` goes with Phase 5.
14. **The backend's refusals on the host backend:** the device route of the references, the shift maps and blocks
    in flight have no host form in the toy and are refused with a message; decision 9 gives the host backend the
    dense score only.
15. **`kill` needs no glue:** the deferred `kill` of `device_work` is the one thing a host file calls on its
    device state.

**What it means, in short.** The calculator's host files no longer name MLX, the device route's bytes did not
move, and the first dependency the plan had not seen showed up: the calculator's host files import the
projector's, so the classes' host builds are not independent and the host route waits for Phase 5.

### Phase 5, the projector (2026-11-26, 02:12 to 02:22, M5 Ultra; before Phase 4, by decision 13 of Phase 3)

Base `6f1af0d` with Phases 1 to 3; the rulings file is empty. Logs under `scratch/keep/phase5/`. Files: new
`src/test/mlxf_toy_projector_mlx.f90`, `src/test/mlxf_toy_projector_pft_batch_mlx.f90`; changed
`mlxf_toy_projector.f90`, `mlxf_toy_projector_pft_batch.f90`, `mlxf_toy_projector_workspace.f90`,
`mlxf_toy_polarft_core_mlx.f90` (the hand-off's receiving side), `mlxf_toy_seam_tester.f90`,
`scripts/toy_seam.txt`, `scripts/toy_mirror.txt`, `scripts/check_rules.py` (`SEAM_PENDING` 2),
`test/offstate/CMakeLists.txt` (the transient list is gone). No tester or benchmark of the projector changed.

**What was built.**
- `projector` holds `ws` as `class(device_work), allocatable` (public, as before) and its own `msg`; nine glue
  procedures in `mlxf_toy_projector_mlx` (`new_mlx`, `get_cmat_mlx`, `pad_fft_mlx`, `expand_cmat_mlx`,
  `is_expanded_mlx`, `kill_expanded_mlx`, `set_fproject_form_mlx`, `set_fproject_tile_mlx`,
  `fproject_seconds_mlx`). The message of the last refusal moved from the workspace to the projector, so that a
  projector without a device state can still say why; each glue procedure copies the workspace's message where
  the workspace sets one.
- **Decision 10:** `new` takes the toy's `parameters` as an optional last dummy and refuses `l_mlx` false with
  "the toy has no host route"; absent, the backend is MLX.
- The batch projector's preparation (the padded polar coordinates and the rotation rows) is host code; the gather
  is in the glue `mlxf_toy_projector_pft_batch_mlx` (`fproject_polar_batch_opt_mlx`,
  `fproject_polar_batch_resident_mlx`).
- **Decision 11:** the resident bank crosses as `class(device_work), allocatable`: the device type
  `projector_bank` (in the projector's workspace module) carries the sections; the projector's glue makes it,
  the calculator's glue (`vol_pad2ref_pfts_opt_mlx`) resolves it and its own workspace with `select type`, kills
  and deallocates it, and a wrong type on either side is a refusal with a message.
- Sub-suite `seam`: 66 checks (33 per device), 0.06 s: the projector's 1,000 cycles (every hundredth padded,
  transformed and expanded), decision 10's refusal with no device object made, a projector whose device state
  has another type refusing with a message and still released by `kill`.

**Exit items.**
- The common gate (`phase5/exit/summary.txt`): both builds from scratch, 0 warnings, 9 of 9, every area passing;
  `unit_kernels` 1,848 = 1,782 + `seam` 66; `projector` 100, `projector_chain` 99, `oracle_projection` 44 at their
  counts, as every other sub-suite; `check_tree.sh`, `check_embed.sh`, `check_toy_offstate.sh` passing.
- **The off-state project now compiles 15 files** (9 host, 6 glue: the calculator's, the driver, the projector's
  and the batch projector's, the opaque type) **without the library**, Debug and Release, with GNU Fortran 16.2.0
  and with 14.4.0 (`phase5/offstate_gfortran14/`): 14.4 links every form this run wrote.
- Decision 13: the eleven identity invocations equal the base byte for byte (`phase5/identity/identity.txt`).
- Plants (`phase5/plants/`): a `kill` that leaves the device state fails `seam` (the projector's own suite still
  passes it, because the compiler finalizes a scalar component at scope exit: the cycles on one variable are what
  tell); the host backend accepted at `new` fails `seam`; the bank handed to the other parity's workspace fails
  `projector_chain`.

**Decisions taken under delegation.**
16. **The backend reaches a class whose `new` has no `parameters` through an optional last dummy `params`**
    (the projector here, the reconstructor in Phase 6): SIMPLE's classes read their parameters object without a
    dummy, and the toy has no such global. Existing calls are unchanged. Declared as a difference.
17. **The projector's message lives in the projector, and the workspace's `set_message` is deleted** (no caller is
    left; the build proves it); the batch projector writes its refusals through a new binding
    `projector%set_message` (an addition, in the mirror ledger).
18. **The batch projector guards its glue call with `allocated(vol_pad%ws)`:** the backend flag is private to the
    projector's module, the device state is public as SIMPLE's `cmat_exp` is, and it exists on the MLX backend only.
19. **The wrong type of the handed-over bank has no test:** no public path makes a bank of another type; the
    projector's wrong device state has one.

**What it means, in short.** The calculator and the projector are both free of MLX names and compile together
without the library; the device route's bytes did not move; the hand-off between two classes on the device is an
opaque object that only glue opens.

### Phase 4, the polar host route and the fill's two branches (2026-11-26, 02:22 to 02:40, M5 Ultra; after Phase 5)

Base `6f1af0d` with Phases 1 to 3 and 5; the rulings file is empty. Logs under `scratch/keep/phase4/`. Files: new
`src/test/mlxf_toy_polarft_host_tester.f90`, `src/test/mlxf_polarft_host_fixture.f90` (a file-table row added
first: decision 20 below); changed `mlxf_toy_polarft_calc.f90`, `_core`, `_memo`, `_block`, `_block_mlx`,
`mlxf_toy_eul_prob_tab.f90`, `mlxf_test_defs.f90`, `mlxf_test_registry.f90`, `test.inf`,
`test/offstate/{CMakeLists.txt, mlxf_offstate_exec.f90}`, `scripts/toy_mirror.txt` (four additions).

**What was built (decision 9).**
- **`score_block_posterior` on the host backend** is a miniature of SIMPLE's block kernel with SIMPLE's dummy list,
  in single precision: the particle terms of every bin; per tile of `PFTC_BLOCK_NR` = 32 references the sums of
  every bin over the 2nk shell terms against SIMPLE's bin-major memo `ft_ref_bins` (made by `memoize_ref_bins`,
  SIMPLE's layout); each pair's inverse real transform as a direct sum; SIMPLE's distances and row draw with the
  pair's keyed variate in double precision. It works in the calling thread's work (`bwork`, made in `new` for the
  parameters' `nthr`, as SIMPLE's) and writes nothing else of the calculator. On the MLX backend its first
  statement is the guarded call of `score_block_posterior_mlx`; the list checks of the device (all the references
  in order) moved to the glue with it.
- **`fill_tab_range` selects once** on the parameters' `l_mlx`: the host branch scores the blocks from inside
  `!$omp parallel do` (`num_threads(nthr)`, `schedule(dynamic)`), one block a thread, writing each block's columns;
  the MLX branch is the serial submission and collection as it was.
- Where SIMPLE stops inside the region, the toy cannot write a message from several threads: a refused block
  leaves SIMPLE's invalid entries, and `check_block_work` (an addition) asks the same questions before the region.
  Outside a region a refused block leaves its message as elsewhere.
- Additions on the calculator, in the mirror ledger: `set_draw_keys` (the host kernel draws inside the calculator,
  as SIMPLE's from its scope), `check_block_work`, `copy_block_rows` (the thread's rows without an allocation),
  and the module function `keyed_variate` (the driver's former private copy; one copy now).
- The host route is not timed and no speed is claimed for it.

**Sub-suite `polarft_host`** (65 checks; 0.08 s in Release, 0.31 s in Debug), on an analytic fixture seeded by an
integer hash (40 references per half, 44 particles, pftsz 16, shells 2 to 7: more than one reference tile and more
than one block per half, one particle whose rows are invalid), seeds 1, 2 and 3. **The first run passed; nothing
was tuned** (the bounds are the MLX backend's fixture's, frozen before this run: `POLAR_ROW_FACTOR` x
`POLAR_FIXTURE_ERR_CPU` = 4.794e-7 of a row's largest valid |d|, at most 1 minimising rotation off):

| Decision 17's gate | Seed 1 | Seed 2 | Seed 3 |
| --- | --- | --- | --- |
| host rows against the ring oracle (*measured*; Release) | 2.264e-7, 0 of 1,760 rotations | 2.321e-7, 0 | 2.770e-7, 0 |
| every entry valid or invalid as the oracle; the draw holds on the host's own rows | 0 off, 0 off | 0, 0 | 0, 0 |
| a team of four against one thread: entries and rows | equal bytes | equal bytes | equal bytes |
| the two branches' rows, CPU device | 2.819e-7, 0 rotations | 2.845e-7, 0 | 3.164e-7, 0 |
| the two branches' rows, GPU | 2.819e-7, 0 | 2.825e-7, 0 | 2.825e-7, 0 |

In Debug the largest is 3.363e-7 (the branches, CPU device, seed 3). The drawn rotations of the two branches differ
in 0 of 1,760 pairs on every seed and device (reported). Also checked: a direct call outside any region gives the
fill's entries bit for bit; the host backend makes no device object; seven refusals (no keys, a block above
`PFTC_BLOCK_NB`, mixed halves, a team above the calculator's, the driver's block size, the shift maps, a driver on
the other backend).

**Exit items.**
- The common gate (`phase4/exit/summary.txt`): both builds from scratch, 0 warnings, 9 of 9, every area passing;
  `unit_kernels` 1,913 = 1,782 + `seam` 66 + `polarft_host` 65, every sub-suite of Phase 1 at its count;
  `check_tree.sh`, `check_embed.sh` passing.
- **Decision 6:** `scripts/check_toy_offstate.sh --exec` on the Phase 4 Release build: the off-state program's
  table (three seeds, 135 lines, 5,280 entries) equals `mlxf_test_exec`'s byte for byte
  (`phase4/exit/check_toy_offstate_exec.log`); the program's twelve checks pass: the table filled, a team of four
  equal to one thread, `polarft_calc` and `projector` refusing the MLX backend with "built without MLX", the
  projector without a host route.
- **GNU Fortran 14.4.0** (reported, decision 27): the off-state project builds and its program passes, Debug and
  Release (`phase4/offstate_gfortran14/`). Its Release table differs from the 16.2 build's in 658 of 5,280
  distances' bits and in no rotation: two compilers' code, not decision 6's comparison. The Debug and the Release
  tables of one compiler differ too (the comparison is Release against Release).
- The eleven identity invocations equal the base byte for byte (`phase4/identity/identity.txt`).
- Plants (`phase4/plants/`): the cross term weighted 1e-4 too much fails the oracle and the branches, and the
  repository's off-state check against that executable fails; the inverse transform without its last bin fails the
  oracle; a variate that depends on the thread fails the team's table, and only it (3 of 65); a stub that does not
  refuse fails the off-state program; a host submodule importing `mlxf` fails the static gate and does not build
  off-state; the bins made through the glue whatever the backend fail `seam` and `polarft_host`.
- **The plant runner had two flaws, found and corrected in this phase:** it restored files with their old times,
  and `make` compares times by the second, so a file changed back within the second its object was written was
  not rebuilt. One run was contaminated (the thread-dependent variate showed the previous plant's failures) and
  was run again. Every build-and-run plant of Phases 1, 3 and 5 was run again on the current tree with the
  corrected runner and fails as recorded (`phase4/replant.out`, `phase4/plants/recheck/`).

**Decisions taken under delegation.**
20. **A file outside the table: `src/test/mlxf_polarft_host_fixture.f90`,** with its row added before the file. The
    off-state program and the sub-suite must run one fixture and write the table with one piece of code, the
    sub-suite's tester imports `mlxf` through the test library, and a second copy of a fixture is a defect. Its
    two records are in `mlxf_test_defs` (rule `defs`).
21. **The host kernel accepts any list of references** (SIMPLE's does); the MLX backend keeps its restriction, in
    its glue.
22. **The host fixture is its own** (not the calculator tester's, which is private to that tester and random):
    analytic values from an integer hash, so that two builds and two compilers make the same fixture.
23. **The backend of a fill is the driver's parameters';** a driver and a calculator on different backends are
    refused by the calculator with a message (both ways), so no inquiry of the backend was added.
24. **The host kernel's inverse transform and sums stay in single precision** (decision 9's letter): no double
    accumulator was needed to meet the bounds.

**What it means, in short.** The polar toy now runs with MLX switched off, through SIMPLE's two shapes of the
fill, and in a build that has no MLX at all it gives the same bytes; the host kernel met the MLX backend's bounds
at its first run.

### Phase 6, the reconstructor: stopped before any edit (2026-11-26, 02:40 to 02:49, M5 Ultra)

Base `6f1af0d` with Phases 1 to 5; the rulings file is empty (read again before the stop). **Stopped on section 7:
"a host file cannot be freed of an MLX name without changing a mirrored dummy list."** No file of the
reconstructor or of the engine was edited; the tree is the one Phase 4 left, gated. Evidence under
`scratch/keep/phase6/`.

**What was found.**
1. **Five public, mirrored bindings of `reconstructor_pcg` take and return device arrays:** `mask_mul(self, v)`,
   `apply_normal(self, p) result(hp)`, `apply_normal_kernel(self, p) result(hp)`, `apply_precond(self, r)
   result(z)` and `dot_real_volume(self, a, b) result(d)`, all `type(mlx_array)` (the mirror ledger's lines 155
   and 158 to 161). A binding's interface stands in the module that defines the type, so the parent cannot be a
   host file while they keep these dummies. In SIMPLE at `d354efee2` the same five take and return host arrays
   (`real :: p(self%box, self%box, self%box)`; `dot_real_volume` returns `real(dp)`). Decision 12 moves "every
   procedure with an `mlx_array` dummy" to the glue, and decision 4 allows a glue procedure no MLX dummy and no
   public name: the two cannot both hold for these five without changing their dummies' type or taking them out of
   the class.
2. **They are called with device arrays from outside the toy:** 12 call sites in the reconstructor's two testers
   (the explicit operator's columns built before one evaluation, the lifecycle, the test operator of rule T
   inside the engine) and 13 in `bench_recon_pcg` (its own operator, the profile's and the probe's loops, which
   measure pieces without a host round trip). The file table allows those files "`l_mlx` where they build
   `parameters`; a renamed import; no check changed".
3. **`pcg_solver_outcome` cannot follow the engine into a device module:** it is a dummy of the host, mirrored
   `solve_accum`, and it is mirrored itself with its binding `kill`, so it can go neither to the device module (a
   host file would import it) nor to `mlxf_test_defs` (a class). And rule `mirror` refuses decision 12's rename as
   written: `mlxf_toy_pcg_solver_mlx` is not `mlxf_toy_<stem>` beside `simple_pcg_solver` (8 lines fail).
4. The compiler agrees with the reading: without its import of `mlxf` the parent has 66 errors, in the five
   bindings, `add_ridge`, `deapod_mul`, the adapter's three bindings, `end_accum` and `solve_accum`
   (`phase6/evidence/plants/host_parent_without_mlxf.build.log`); the rename alone fails the static gate
   (`phase6/evidence/plants/engine_rename_static.log`).

**The ruling needed, with a recommendation.**
- **R1, how the five cross the seam.**
  1. *Recommended:* the five public bindings take SIMPLE's host arrays, as SIMPLE's do, each a guarded call (which
     removes a declared difference); their device forms become procedures of the glue, private, and the adapter
     calls those, so the solve's graph and bytes do not change. The testers and the benchmark that need device
     arrays without a host round trip get the reconstructor's operator as one opaque object: `pcg_operator`
     extends `device_work`, and one glue-backed addition hands the adapter out.
  2. Opaque volumes: the five keep one form with `class(device_work)` dummies and results, a device type carrying
     the array; every outside call wraps and unwraps.
  3. The reconstructor stays an MLX class: classed `device`, absent from the off-state build; `pending` then ends
     at 0 without a host file for it, and the off-state program cannot ask it for a refusal.
- **R2, the engine's two halves.** *Recommended:* `mlxf_toy_pcg_solver` stays, as a host module that keeps the
  mirrored record `pcg_solver_outcome` with its `kill`; `pcg_operator` and `pcg_solve` go to the device module
  `mlxf_toy_pcg_solver_mlx`; rule `mirror` accepts `mlxf_toy_<stem>_mlx` beside `simple_<stem>` for a module the
  seam ledger classes as device.
- **R3, the testers and the benchmark.** Under R1's options 1 and 2 about 25 call sites in three files change
  form (no check changes); the file table's row for them needs the word.

**Decision 14, measured on the tree as it stands** (*measured*; the Phase 4 Release build, the protocol of Phase 0,
two runs each, the load 1.7 to 3.8, no other test or build process; `phase6/timing/`). The rule is Phase 6's; it
is reported here for the three benchmarks, the reconstruction's code being the base's:

| Benchmark | Run a | Run b | Mean | Base | Change | Floor | |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `bench_polar_table` (pairs/s) | 1.76600e7 | 1.76710e7 | 1.76655e7 | 1.763595e7 | +0.17 % | 1.728323e7 | holds |
| `bench_projector` (samples/s) | 1.39123e9 | 1.40177e9 | 1.39650e9 | 1.408895e9 | -0.88 % | 1.380717e9 | holds |
| `bench_recon_pcg` (assemblies/s) | 4.31779 | 4.30015 | 4.30897 | 4.30710 | +0.04 % | 4.22096 | holds |

**The final gate** on the tree as it stands, with the report written (`final/exit/summary.txt`): Debug and Release
from scratch, 0 warnings, 9 of 9, every area passing (`unit_core` 181 to 183 over the run's gates: `registry` has 35
to 37 checks by the allocator's reuse of an address, on either device), `unit_kernels` 1,913, `check_tree.sh`,
`check_embed.sh` and `check_toy_offstate.sh --exec` passing.

**Also run at the stop, for the record:** `scripts/release_gate.sh --allow-dirty` passes on the tree as it stands
(73 s; Debug and Release, the fast gate, the installed package, `check_embed.sh`, `check_toy_offstate.sh --exec`
with the table equal; `phase6/release_gate.out`). The ledger holds 2 pending lines (`mlxf_toy_pcg_solver`,
`mlxf_toy_reconstructor_pcg`); Phase 7's documents are not written.

**What it means, in short.** Two of the three toys have the shape, with a host route, a build without MLX and
the device route's bytes untouched. The third cannot take it as decided: its mirrored operator procedures speak
device arrays to its testers and its benchmark, which is a question about the toy's interface, not about the
seam's mechanics.

### The rulings of the Phase 6 stop (2026-11-26, the run's `spec/rulings.md`, R1 to R6)

Taken in the session on 2026-11-26 under the maintainer's go ("Yes, go"), on the run's own recommendations at the
Phase 6 stop. Each stands as recommended and is open to the maintainer's review.

- **R1, option 1.** The five operator procedures take and return SIMPLE's host arrays with SIMPLE's dummy lists at
  `d354efee2`, each a guarded call to its glue twin, which sends the volume to the device, applies the device form
  and brings the result back; on the host backend each is refused with decision 10's message. The device forms
  are private procedures of the glue, which the adapter calls, so the solve's graph and bytes do not change. The
  operator is handed out as one opaque `class(device_work)` by one glue-backed addition. Added to the
  recommendation: for each of the five, one new check that its result equals the device form's brought to the
  host, byte for byte, and one check of the host backend's refusal; a planted defect in a glue twin fails its
  check; the mirror ledger declares what stays different.
- **R2, as recommended.** `mlxf_toy_pcg_solver` stays as the host module of the mirrored record
  `pcg_solver_outcome`; `pcg_operator` and `pcg_solve` are the device module `mlxf_toy_pcg_solver_mlx`; rule
  `mirror` accepts `mlxf_toy_<stem>_mlx` beside `simple_<stem>` for a module the seam ledger classes as device, and
  for nothing else, with a plant. It replaces decision 12's rename as written.
- **R3.** The call sites of the five in the two testers and the benchmark change form to the opaque operator; no
  existing check, tolerance or expected value changes; the file table's row got the word before the edit.
- **R4.** `pcg_solver`, `reconstructor_pcg` and `reconstructor_pcg_n32` keep every check they had at the stop (86,
  172, 96) and gain only R1's; `reconstructor_pcg_n32` is run in Release at the exit; `pending` is 0; decision 14
  is judged for the three benchmarks by Phase 0's protocol against the base's frozen numbers.
- **R5.** Confirmed as taken: Phase 5 before Phase 4 (the run's decision 13) and the file outside the table with its
  row first (decision 20). The optional `params` dummy of `projector%new` (decision 16) and the name `l_mlx` stay
  and are listed in the report for the maintainer's read.
- **R6.** Then Phase 7; the report covers the whole run; the 30 statements of `NANMAX_LEDGER` stay and are listed
  as a follow-up.

### Phase 6, the reconstructor (2026-11-26, 02:52 to 03:24, M5 Ultra; resumed under rulings R1 to R4)

Base `6f1af0d` with Phases 1 to 5; the rulings file read whole at the resumption and again before the exit. Logs
under `scratch/keep/phase6/`. Files: new `src/test/mlxf_toy_reconstructor_pcg_mlx.f90`,
`src/test/mlxf_toy_pcg_solver_mlx.f90`; changed `mlxf_toy_reconstructor_pcg.f90`, `mlxf_toy_pcg_solver.f90`,
`mlxf_toy_reconstructor_pcg_workspace.f90` (`extends(device_work)` and its import), the two reconstructor testers,
`mlxf_toy_pcg_solver_tester.f90` (the import), `mlxf_bench_recon_pcg.f90`, `mlxf_toy_seam_tester.f90`, `test.inf`,
`test/offstate/mlxf_offstate_exec.f90`, `scripts/check_rules.py`, `scripts/toy_seam.txt`, `scripts/toy_mirror.txt`,
`scripts/check_toy_offstate.sh`.

**What was built.**
- **The engine's two halves (R2).** `mlxf_toy_pcg_solver` keeps `pcg_solver_outcome` with its `kill` and imports no
  MLX name. `mlxf_toy_pcg_solver_mlx` is the device module: `pcg_operator`, now `extends(device_work)` with a
  `kill` that releases nothing by default, and `pcg_solve`, whose statements are the base's.
- **The reconstructor's host file.** `mlxf_toy_reconstructor_pcg.f90` imports `mlxf_test_defs`,
  `mlxf_toy_device_work` and the engine's host half; `ws` is `class(device_work), allocatable`, killed before it is
  deallocated. It keeps SIMPLE's host work as it was (the envelopes, the window and the mask, the density's shell
  statistics, the options, the window at the start and the exit of the solve) and reaches the device through
  eighteen glue procedures, declared in the interface block "MLX", each called on the MLX backend only.
- **The glue** `mlxf_toy_reconstructor_pcg_mlx.f90`: the eighteen procedures `<name>_mlx` with their stubs; the
  device forms of the five (`mask_mul_device`, `apply_normal_device`, `apply_normal_kernel_device`,
  `apply_precond_device`, `dot_real_volume_device`), whose statements are the base's bindings'; the adapter
  (`reconstructor_pcg_adapter`, with a `kill` that lets the client go), which calls the device forms.
- **The five on host arrays (R1).** `mask_mul(self, v)`, `apply_normal(self, p) result(hp)`,
  `apply_normal_kernel(self, p) result(hp)`, `apply_precond(self, r) result(z)` with `real :: v(self%box, self%box,
  self%box)` and allocatable results, and `dot_real_volume(self, a, b) result(d)` in double. A result is of size
  zero where the device form refuses (no kernel before `end_accum`).
- **`get_pcg_operator(self, op)`** (the addition): `op` is `class(device_work), allocatable, intent(out)`, the
  adapter bound to the reconstructor; not allocated on a refusal.
- **`new(self, box, lambda, params)`**: the backend from the optional `params` (the MLX one when absent), as
  `projector%new`; with `l_mlx` false it is refused with "the toy has no host route" before anything is made.
  `kill` now also returns the lattice's scalars (`box`, `boxpd`, `pad_off`, `Rnat`, `padsc`, `iwinsz`) to their
  initial values, so that the five's explicit-shape dummies have size zero without a reconstructor.
- **The call sites (R3):** the 12 of the two testers and the 13 of the benchmark. Nineteen now call `device_apply`,
  `device_precond` or `device_dot`, which take the operator with `get_pcg_operator`, resolve it to `pcg_operator`
  and apply it to device vectors; the six inside the two types that wrapped the five for the engine
  (`test_operator`, `bench_operator`) went with those types, since `pcg_solve` is given the toy's own operator.
- **Rules.** `mirror` reads the seam ledger for R2's exception; `seam` lets a device module `<stem>_mlx` import
  `<stem>`, its own host half (decision 25 below); `SEAM_PENDING` is 0.
- **`scripts/check_toy_offstate.sh`:** a relative `--exec` passed the script's test and failed after it changed
  directory (found by the session's rebuild of the stopped state). `--exec`, and `--fc` when it is a path, are made
  absolute where the option is read; `--keep` already was.

**The checks added, and only these** (R4):
- `reconstructor_pcg`, 172 to 192: per device 10 checks in `test_host_forms`.
  1. `apply_normal` of a host volume equals the device form's product brought to the host, byte for byte.
  2. `apply_normal_kernel`, taken with the support set, equals the operator once the support is cleared (the
     kernel's product alone), byte for byte, and differs from the masked operator's.
  3. `apply_precond` equals the device form's product, byte for byte.
  4. `dot_real_volume` equals the device form's line sums added in double, bit for bit.
  5. `mask_mul` equals the device form's `P v` (the preconditioner's product before `end_accum`), byte for byte.
  6. to 10. On the host backend each of the five is refused with its message ("...: refused: the toy has no host
     route"), the result of size zero, zero, or the volume as it came.
- `seam`, 66 to 88: per device 11 checks of the reconstructor (device arrays after `end_accum`; the operator
  handed out, holding no device object; `kill`; 1,000 cycles with the live handles and the active memory as they
  were; the host backend refused at `new` with no device object and no operator).
- `pcg_solver` 86 and `reconstructor_pcg_n32` 96: no check added, none changed.
- The off-state program: three more checks (the reconstructor refuses the MLX backend with "built without MLX",
  has no host route, and applies no operator without a reconstructor).

**Exit items.**
- The common gate (`phase6/exit/summary.txt`): both builds from scratch, 0 warnings, 9 of 9, every area passing;
  `unit_kernels` 1,955 = 1,913 + 20 + 22; `check_tree.sh`, `check_embed.sh`, `check_toy_offstate.sh --exec` passing
  (18 host and glue files; the program's 15 checks; the table equal, 135 lines). `scripts/check_toy_offstate.sh
  --exec build/bin/mlxf_test_exec` run from the repository's root passes (`phase6/exit/offstate_relative.log`;
  `build` was a link to the phase's Release tree for that run, removed after it).
- GNU Fortran 14.4.0 (reported): the off-state project of 18 files builds and its 15 checks pass, Debug and
  Release; its table is its Phase 4 table (`phase6/offstate_gfortran14/`).
- A probe (`phase6/probe_submodule_name/`): GNU Fortran 16.2.0 and 14.4.0 both refuse a submodule's own procedure
  that has the name of a private procedure of its module ("already defined"), whichever comes first. The glue's
  clock is therefore `glue_clock_s`. Whether the standard allows the redefinition was not settled, so no entry
  was made in `doc/compiler_issues/`.
- **The identity cases** (decision 13): the eleven invocations, run once, equal the base byte for byte (`phase6/identity/identity.txt`,
  57 lines, SHA-256 `7d8d7bfc...a77d5a`).
- **`reconstructor_pcg_n32`** in Release: 96 checks, 96 passed (168 s; `phase6/n32/n32.out`): the count it had at Phase 1's exit.
- **Decision 14** (*measured*; the Phase 6 Release build, the protocol of Phase 0, two runs each; `phase6/timing_exit/`):

  | Benchmark | Run a | Run b | Mean | Base | Change | Floor | |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | `bench_polar_table` (pairs/s) | 1.76600e7 | 1.76305e7 | 1.764525e7 | 1.763595e7 | +0.05 % | 1.728323e7 | holds |
  | `bench_projector` (samples/s) | 1.41247e9 | 1.40888e9 | 1.410675e9 | 1.408895e9 | +0.13 % | 1.380717e9 | holds |
  | `bench_recon_pcg` (assemblies/s) | 4.24899 | 4.34783 | 4.29841 | 4.30710 | -0.20 % | 4.22096 | holds |

  The load before each was 1.3 to 3.3, with no other test or build process. The launcher's rates step by the
  median's 0.1 ms, so two runs can print the same rate. The reconstruction's runs differ by 2.3 % (0.9414 and
  0.9200 s for the four assemblies; the row n = 160, F5 took 0.1133 and 0.1033 s); its lower run is 1.35 % below
  the base and above the floor. The maps and histories of both runs are the base's (the identity cases). **The
  rule holds for the three benchmarks.**
- Plants (`phase6/plants/`), 14 that fail and 1 control:
  - a defect in each of the five glue twins (the preconditioner's twin applying the operator; the mask's twin
    skipping the device form; the inner product's twin adding in single precision; the kernel's twin applying the
    masked operator; the operator's twin dropping the support) fails its own check and no other, except the last,
    which also fails the kernel's (its "differs from the masked operator's");
  - `new` ignoring the backend fails `seam` (4 per device), `reconstructor_pcg` (the five refusals) and the
    off-state program; a stub of `new_mlx` that reports success fails the off-state program;
  - the host file importing `mlxf` fails rule `seam` and does not build off-state; the engine's host half
    importing its device half fails rule `seam`; the device engine importing another class's host module fails
    rule `seam` (the exception is its own host half only);
  - R2's plant: the device engine classed `pending` fails rule `mirror` on its four mirrored lines beside
    `simple_pcg_solver`; a new module `mlxf_toy_plant_mlx` classed `host` and listed beside `simple_plant` fails
    rule `mirror`; the same module classed `device` passes (the control).

**Decisions taken under delegation.**
25. **A device module `<stem>_mlx` may import `<stem>`, its own host half.** `pcg_solve` fills
    `pcg_solver_outcome`, which R2 keeps in the host module; rule `seam` allows that one import and still refuses
    any other host module of a toy class (planted).
26. **`pcg_operator` has a default `kill` that releases nothing.** It must have one to extend `device_work`; a
    default keeps the two operators of the engine's tester as they are (their import alone changed). The
    reconstructor's adapter overrides it. It is an addition in the mirror ledger.
27. **`self` is `intent(inout)` in all five,** so that a refusal can leave its message; SIMPLE's `mask_mul` and
    `dot_real_volume` are pure with `self` `intent(in)`. Declared in the mirror ledger's comment and in the
    kernel-families note.
28. **The addition is named `get_pcg_operator`,** and the testers reach the device forms through it with three
    small functions each (`device_apply`, `device_precond`, `device_dot`), which take the operator, apply it and
    let it go; the benchmark has its own three, since a benchmark does not import a tester.
29. **Two glue procedures for `end_accum`** (`end_accum_mlx`, `end_accum_wait_mlx`): the host's statistics run
    between the right-hand side and the wait. And one private binding, `solve_stopped` (`nopass`), holds the rule
    of a given-up solve for the host procedure and its twin: a submodule calls no private plain procedure of its
    module.
30. **The check of `apply_normal_kernel` clears the support to reach its device form** (the opaque operator
    applies `P H P`): taken with the support set, the host form must equal the operator after
    `set_window_sphere(0.)` and differ from the masked operator's. A first form of the check, on an assembly
    without a support, could not tell a twin that applied the mask; it was replaced before the exit.
31. **Refusal checks: one per procedure,** ten new checks per device where R1 asks for "five at least" and "one
    check of the host backend's refusal".
32. **`reconstructor_pcg%kill` resets the lattice's scalars** (above); no existing check read them after `kill`.
33. **The ledger's wrong-type check is not repeated for the reconstructor:** its `ws` is private, as SIMPLE's
    state is, so a tester cannot plant another type; the glue's refusal is there and is not reached by a test.

**What it means, in short.** The third toy has the shape, and with it the seam ledger has no pending line: every toy class
is host files, glue and device modules, and builds without MLX. The reconstructor's five operator procedures now
speak SIMPLE's host arrays, which removed a difference instead of adding one; the solve's bytes are the base's and
the three benchmarks' rates are within 0.2 % of it.

### Phase 7, the record (2026-11-26, 03:17 to 03:30, M5 Ultra)

Written while Phase 6's measurements ran and after them; no source file changed.
- `doc/policies/toy_example_policy.md`: section 8, "The integration shape" (the three classes, the opaque
  component, the glue's form, the backend, the device engine beside a host module, the build without MLX, how a
  new toy enters), and section 4's line on rule `mirror`'s exception.
- `doc/implementation_notes/planned/mlxf_kernel_families.md`: the shape as a rule for every toy; "The seam in
  files" for families A, B1 and D; the differences that changed (the host route's additions, the backend, the
  reconstructor's five on host arrays, the engine's two halves).
- `doc/how2s/how2use_from_simple.md`: decision 20's two tables (each toy file, its class and the SIMPLE file it
  stands for at `d354efee2`; what each mirrored host procedure gained).
- `doc/policies/test_environment_policy.md`: the sub-suites `seam` and `polarft_host`, the off-state check, the
  reconstructor's new checks, `nan_max`, and synchronizing before two memory samples are compared.
- The roadmap's row 2c, the plans' index, `doc/history/2026-11.md` (2026-11-26), one sentence of `README.md`.
- The report, rewritten for the whole run: `doc/implementation_notes/completed/mlxf_toy_seam_report.md`.

**Exit.**
- `scripts/release_gate.sh --allow-dirty` passes on the final tree (72 s; `phase7/release_gate.out`); its build
  directory is removed.
- The report exists, with a commit message that names the 18 new files and carries no attribution line.
- `git status` shows 50 changed and 18 new paths, each in the file table; nothing is committed.
- The final gate (`final2/exit/summary.txt`): Debug and Release from scratch, 0 warnings, 9 of 9, every area
  passing (`unit_kernels` 1,955; `unit_core` 183 in Debug and 182 in Release this time, the base's 181 to 183),
  `check_tree.sh`, `check_embed.sh` and `check_toy_offstate.sh --exec` passing; both formatters left the 48 touched
  Fortran files unchanged.
- The plan stays in `planned/` until the maintainer has read the result and the rulings.
