# mlx-fortran milestone 1: the Phase 1 follow-ups, the tiled polar pipeline and the shift maps

Status, 2026-11-22: planned, not launched. Decisions 3 to 7 ruled by Hans on 2026-11-22 as recommended;
widened the same day by decision 15 (the shift maps of the scientific examples' example 1, Phase 5b), and
by decisions 19 and 20 (SIMPLE's matching shift-map benchmark; Phases 1 to 3 done interactively).
Phases 1 to 3 are complete, done interactively (Progress; decision 20), and were reviewed on 2026-11-22. Run
`mlxf_m1` starts at Phase 0 on the maintainer's commit of that work, with the SIMPLE pin of decision 19.
Decision 21 records the callback ruling of Phase 3. Decision 22 (2026-11-22) makes the CPU comparator's FFT
plans measured and moves the SIMPLE pin to Hans's commit of that option. Base: the maintainer's commit of the working tree on top of `0d3537b`, which holds the
`findpkg` change and the split of the design plan. That commit is a launch precondition, and the run records
its hash. Supersedes: Phases 2 to 6 of `doc/implementation_notes/completed/mlxf_design.md` ("the design
plan" below). Depends on: the handle model and the core (validated: yes, the design plan's Phase 1, commit
`0d3537b`); mlx-c 0.8.0 with MLX 0.32.4 as shared libraries from Homebrew (validated: yes, M2 Ultra);
SIMPLE's production block scorer `polarft_calc%score_block_posterior` at SIMPLE
`7ec7e29720b3e57c2a56a6a7ab754e6f6c57fe35` (validated: source read on 2026-11-21 for design decision 42;
not built or measured on a Mac yet; Phase 0 does both); SIMPLE's `polar_matching_bench suite=shiftmap`
(decision 19; written 2026-11-22 on top of `7ec7e2972`; built and smoke-run by Hans the same day at 200
directions, 64 particles and 4 threads, both maps 0 differing between teams; Hans's commit of it is "the SIMPLE
pin" below. Its production code equals `7ec7e2972`'s except that `stage_trslim` became public and the
shift map's width loop reads a per-map table of the grid's shifts instead of calling `shiftmap_shift` per
cell and rotation. That change is byte-identical on both maps (`cmp` of the dumps below, Hans, 2026-11-22)
and cuts the width reduction by 37 to 42 %); the M5 Ultra (delivery expected 2026-11-25; not
validated).

## 1. Why

mlx-fortran has its core: the generated `bind(c)` layer, checked on every build against an independent list
of 680 names, and an `mlx_array` whose lifetime is exact in every supported form, on both devices. It has
no operations yet beyond `+ - *` and `exp`. SIMPLE needs one pipeline, proved end to end, before an
integration plan is worth writing (design decision 32). That pipeline is the scoring stage of the polar
table fill. The CPU comparator is SIMPLE's production block scorer: per SIMPLE's report on the Dell, dense
scoring there costs 0.38 to 0.40 of the previous route and a whole bgal run is about 9 % shorter. These are
*reported* CPU numbers, not Mac or GPU measurements.

Scoring is not the largest part of the fill. In the two production profiles Hans supplied (PorF and
exp_gate, `~/for_claude/bench/{PorF,exp_gate}/BENCH`; commit and machine not recorded), dense scoring is
14.5 % and 8.5 % of the fill's thread-seconds, and building the polar shift maps is 35 % and 57 %. Proving
the binding on scoring alone would leave the larger share unmeasured, so the shift maps join this
milestone (decision 15) and the M5 Ultra session measures both.

The Phase 1 run also left open items for the maintainer. One of them is a cost: the recovery gate allocates
64.9 GB per device in every fast gate, 7.5 s of `unit_core`'s 7.8 s on the M2 Ultra (*measured*), and the
allocation grows with the GPU's maximum buffer length. The others are an unchecked leak form, a compiler
report not yet sent, and an unsupported form waiting for a ruling. This plan closes them first, while the
tree is small, and then builds milestone 1.

## 2. Contract

### Layers

Unchanged from the design plan (section 2) and `doc/policies/binding_contract_policy.md`, which is the truth
for the contract:

| Layer | Owns |
| --- | --- |
| SIMPLE (not touched here) | particle batches, candidate lists, seeds, refinement, assignment; later, the GPU workspace under `builder%pftc` |
| test-only polar pipeline (`src/test/`) | the model of that workspace: reference preparation, invalidation, teardown and scoring, written against `mlxf` as a user writes |
| public `mlxf` | Fortran array semantics, ownership, operations, evaluation, errors |
| generated `mlxc_*` | exact correspondence to the linked mlx-c headers; never public |
| MLX | graph execution, allocation, kernels |

### Invariants

- **A library, not a port.** No SIMPLE source, type, constant or name enters the library. SIMPLE's kernel
  lives in test-only code that is never installed (design decision 25). SIMPLE is read-only to the runs;
  its benchmark driver was extended before launch (decision 19).
- **Fortran's view.** Column-major arrays and 1-based dimensions, indices and positions. Every new operation
  translates them, and its tester asserts the translation (policy, sections on memory order and indices).
- **Off state.** A program that links the library and calls nothing pays nothing. Every new public
  procedure opens with the entry (rule `entry`).
- **The handle model is unchanged.** No phase edits the registry, the lifetime submodule or the defined
  assignment except to fix a defect found, which is a stop (section 7). The leak gate stays exact.
- **The arithmetic is MLX's.** New operations add no numerics beyond index and position shifts and weak
  scalars (design decisions 7 and 11).

### What the code check found (2026-11-22, at `0d3537b` with the working tree)

- The public block of `src/core/mlxf.f90` holds the version, error, device, memory and array names, and of
  operations only `exp` and the type-bound `+ - *` (array with array, scalar on either side). `/`, unary
  `-`, comparisons, reductions, shape operations, `matmul`, FFTs and compilation do not exist yet.
- CTest: `MLXF_TEST_AREAS` is `core array`; the guard group `object_contracts` has eight members; the budget
  is 3. `run_area` runs every sub-suite of an area when no `suite=` is given. No sub-suite can be excluded
  from the default run.
- The recovery gate is `test_recovery` in `src/core/runtime/mlxf_error_tester.f90`, area `core`, sub-suite
  `error`. On each device it builds a graph one buffer beyond `max_buffer_length` (it must fail), then the
  same graph at half the batch (it must evaluate).
- Rule `ctorcall` matches function names from the public block only. A defined-operator result inside a
  constructor, as in `[a*2.0, b]`, leaks the same way and is not checked. The policy says so in the
  paragraph after its list of unsupported uses.
- Unsupported use 6 of the policy, the overlapping section assignment `v(2:3) = v(1:2)`, stops as stale.
  No test pins it, because design decision 39.6 forbids a gate that pins a compiler defect.
- `scripts/check_test_registry.py` (run by `check_tree.sh`) fails unless the areas of `test/CMakeLists.txt`,
  the registry's `AREAS` table and its `case()` branches are identical. An area enters all three at once.
- `src/CMakeLists.txt` collects sources with `file(GLOB_RECURSE ... CONFIGURE_DEPENDS)`, so new folders
  need no edit there.
- `doc/compiler_issues/` holds four reproducers. No upstream report is recorded anywhere (no Bugzilla number
  in the files, the history or `apple_questions.md`).
- `.github/workflows/ci.yml` builds with `MLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON`. The headless gate was
  reproduced locally under `sandbox-exec` on 2026-11-21 (history). A run on GitHub's runners is not recorded.
- `scripts/check_rules.py` has the `findpkg` rule, and `cmake/Dependencies.cmake` reports a missing mlx-c,
  OpenMP or Python itself. Both are uncommitted on 2026-11-22 and part of the base once committed.
- SIMPLE could not be read from the session that wrote this plan at first. The scoring facts below are
  design decision 42's, read at `7ec7e2972` on 2026-11-21, and Phase 0 checks them again.
- For decision 15, SIMPLE was read at `7ec7e2972` on 2026-11-22 (the checkout had no later commit):
  - `simple_polarft_shiftmap.f90` builds a map as decision 15 describes.
  - `setup_shiftmaps` sets the production grid (decision 18).
  - `prob_fill_profile` (`simple_eul_prob_tab_utils.f90`) records the maps' construction, selection and
    reduction thread-seconds, counts and geometry in BENCH files.
  - `polar_matching_bench` timed no maps at `7ec7e2972`; its `fills` suite runs the dense route with the
    shift map on (`PMB_TRS` = 3 pixels) but writes no fill profile. Decision 19 adds `suite=shiftmap`.
  - The test executable fixes a process-wide seed (`fix_test_seed`, propagated through `SIMPLE_SEED`), so
    the calculator's FFTW plans are `FFTW_ESTIMATE` in every `polar_matching_bench` suite, `block_prod`
    included, where production plans with `FFTW_MEASURE`. Decision 22 makes measured plans the default of
    `block_prod` and `shiftmap`.

## 3. Decisions and rulings

Numbered, dated, never renumbered. "Design decision N" is decision N of the design plan.

1. (2026-11-22, Hans) **Scope.** This plan closes the Phase 1 follow-ups (its Phase 1) and then delivers
   milestone 1: the operations, compilation, the polar pipeline, its benchmark and the verdict (Phases 2 to
   7). It ends at the hold of design decision 32. What comes after is section 9's roadmap, rewritten into a
   plan of its own after that hold. Widened by decision 15: the shift maps (Phase 5b).
2. (2026-11-22) **Which design decisions bind.** For the contract, the binding policy is the truth (design
   decisions 6 to 18, 29, 30 and 39 live there).
   - *Still binding:* design decisions 1 to 5, 19, 20 as revised by 42, 24, 25, 26 as revised by 42, 27, 29,
     30, 31 as revised by 42 (`block_prod`, never `matrix_t`), 32, 35 to 38 and 40 to 42.
     - Design decision 32's "Phases 1 and 2" are the design plan's numbering. Here milestone 1 is this
       plan's Phases 0 to 7, and the hold follows Phase 7.
     - Design decision 38 (ruling R3) sets the roadmap of section 9.
   - *Superseded:* design decision 28's projection is replaced by 42.6.
   - *Moved to the roadmap:* design decisions 21 to 23 and 33.
   - *Replaced:* design decision 34 is replaced by decision 9 below.
3. (2026-11-22, Hans: ruled as recommended) **The recovery gate keeps its claim and drops its cost.**
   - In the fast gate, each device keeps its failing evaluation. It fails at once and allocates nothing
     (*measured* in the design plan's Phase 1: MLX refuses a buffer above `max_buffer_length` before
     allocating). After it, the same graph at 256 rows (1 GiB) evaluates, and the live count and active
     memory return to their values before (*guessed* size: large enough to need a fresh buffer, small
     enough for any Mac).
   - The half-batch form becomes sub-suite `recovery_half` of area `core`. `run_area` runs it only when
     it is named (`mlxf_test_exec test=unit_core suite=recovery_half`).
   - The run runs that sub-suite at Phase 1's exit, at Phase 6's bring-up and in the report. The policy
     names the sub-suite and when it runs.
   - The alternative is to keep the gate as it is: 7.5 s on the M2 Ultra, and more on a GPU with a larger
     maximum buffer.
   - Either way the recovery gate stays a gate no ruling may waive.
4. (2026-11-22, Hans: ruled as recommended) **The overlapping section assignment
   of handles stays unsupported and diagnosed** (policy, unsupported use 6). Making it work needs rank-1
   specifics that retain every element before releasing any: a second code path in the lifetime submodule
   for one form that a user avoids by assigning element by element. No test pins it (design decision 39.6
   forbids pinning a compiler defect).
5. (2026-11-22, Hans: ruled as recommended; no BENCH output named yet) **The production profile for the
   end-to-end projection.** Hans names a SIMPLE BENCH output made at or after `7ec7e2972`, with its data,
   stages, parts and teams. If none is named, s and f stay *unmeasured* and the report gives the projection
   `1 / (1 - s*f + s*f/g)` as a function of s and f (design decision 42.6). The BENCH run of design
   decision 28 (f = 0.23, s = 0.37) predates the production scorer and is context only.
6. (2026-11-22, Hans: ruled as recommended) **Two runs.**
   - Run `mlxf_m1` covers Phase 0 and Phases 4 to 5b on the M2 Ultra (FWM-S116118), unattended (arun).
     Phases 1 to 3 are done interactively before it (decision 20).
   - Run `mlxf_m1_m5` covers Phases 6 and 7 on the M5 Ultra once it is set up: Homebrew GCC 16, CMake and
     mlx-c, and the SIMPLE pin's build dependencies (decision 22).
   - Between the runs Hans reviews and commits. That commit is Phase 6's base, and no edit reaches the
     repository while a phase runs. Each run starts only on a clean working tree, and records
     `git --no-optional-locks status --short` at the start of every phase. A change it did not make is a
     stop.
   - Each run reads its rulings from arun's rulings file in the run's folder, as `mlxf_core` did.
   - If the M5 Ultra is not ready when Phase 5b ends, run `mlxf_m1` ends with Phase 5b complete, and Phase 6
     waits.
7. (2026-11-22, Hans: confirmed) **Rule `ctorexpr`, and `ctorcall` narrowed**, in `scripts/check_rules.py`.
   - *Handle names.* A file's handle names are every name declared `type(mlx_array)` or `class(mlx_array)`
     in that file, in any scope, and every component declared `type(mlx_array)` in a derived type defined
     in that file. The set is conservative: a name that is a handle anywhere in the file counts everywhere
     in it.
   - *A handle reference.* An element of an array constructor refers to a handle when it contains a handle
     name, whether alone (`a`) or as the last component of a chain (`w%r`). Not counted: a name followed by
     `%` and one of the getters `shape`, `ndim`, `size`, `kind`, which return integers.
   - *The rule.* An element that refers to a handle must be a bare designator: a name, a component chain
     `x%comp`, either with one subscript list (`v(i)`, `v(2:3)`, `w%r(i)`).
     - An implied-do `(expr, i = ...)` is checked through its `expr`.
     - A parenthesised element with no top-level comma, `(a)`, is an expression and fails.
   - *What it catches:* `[a*2.0, b]`, `[-a, b]`, `[a + b, c]`, `[(a), b]` and `[w%r*2.0, b]`.
   - *What it leaves alone:* `[a, b]`, `[v(1), v(2)]`, `[(v(i), i = 1, n)]`, `[a%ndim(), 1]`, constructors of
     reals or integers, and every file that declares no handle.
   - *`ctorcall` narrowed.* It matches only public names that are not the names of Fortran intrinsics: the
     `mlx_*` and `mlxf_*` procedures. Phase 2 makes `real`, `max`, `sum`, `merge`, `matmul` and others
     public generics, and plain-Fortran uses of them in constructors leak nothing. A generic extension of an
     intrinsic applied to a handle (`[exp(a), b]`) is caught by `ctorexpr` instead, because the element
     names a handle and is not bare.
   - Each listed form is shown failing on a planted violation, `[real(i), 1]` and `[(max(i, 2), i = 1, n)]`
     are shown passing, and the clean tree passes. This rule changes the scope of a check and no ledger;
     the record is in the history entry.
8. (2026-11-22) **The public API grows by the pipeline's need** (design decision 29). This is the whole
   list; nothing else is wrapped by hand.
   - **Elementwise:** `+ - * /` (array with array, scalar on either side, weak scalars), unary `-`,
     comparisons `< <= > >= == /=` giving boolean arrays, `.and. .or. .not.` on boolean arrays, `merge`,
     `max`, `exp`, `real`, `aimag`, `cmplx`, `conjg`, `mlx_astype`.
   - **Shape:** `reshape` (Fortran order), `transpose`, `mlx_permute`, `mlx_concatenate`, `mlx_slice`
     (inclusive, 1-based, optional stride), `mlx_take_along_dim` (1-based indices).
   - **Reductions and scans:** `sum` and `minval` along a dimension, `mlx_cumsum`.
   - **Fixtures:** `mlx_zeros`, `mlx_arange`.
   - **Linear algebra:** `matmul`, real and complex, batched and broadcast over dimensions 3 and up.
   - **FFTs:** `mlx_rfft` and `mlx_irfft` along one dimension, with optional `n` and `norm` (vocabulary
     `MLX_FFT_NORMS` in `src/defs`).
   - **Compilation:** `mlx_function` and `mlx_compile` (design decision 30).
   - A sibling enters only when a tester of one of these needs it. The report lists every name that
     entered, with the step that needed it.
9. (2026-11-22, default) **The gfortran report.**
   - The run writes `doc/compiler_issues/README.md`: one entry per reproducer with a title, the standard's
     clause, expected and observed output, the versions seen (13.4.0, 16.2.0) and the flags.
   - Hans files them in GCC Bugzilla and adds the numbers. No agent files anything.
   - The library does not depend on a fix, and no gate pins a defect.
10. (2026-11-22) **Placement.** Each new library folder adds its modules to the one library target, and
    `mlxf.f90` re-exports every public name. Shared constants go to `src/defs` (design decision 40).
    - `src/core/ops/`: `mlxf_ops`, a parent module with the interfaces, and implementation submodules
      `mlxf_ops_elementwise`, `mlxf_ops_shape` and `mlxf_ops_reduce`.
    - `src/core/linalg/mlxf_linalg.f90`, `src/core/fft/mlxf_fft.f90` and
      `src/core/compile/mlxf_compile.f90`.
    - The type-bound operators `/`, unary `-`, the comparisons and the logical operators extend
      `mlxf_array`'s generics, implemented in `mlxf_array_elementwise`.
11. (2026-11-22) **CTest.** Phase 2 adds areas `ops`, `linalg` and `fft`; Phase 3 adds `compile`; Phase 4
    adds `kernels` after the calibration entry. The budget goes from 3 to 8 (design decision 37). No new
    guard group. A new stop of the contract, if any, joins `object_contracts` as a member. The shift maps
    (decision 15) are a sub-suite of `kernels`; the budget stays 8.
12. (2026-11-22, from design decisions 20 and 42) **The pipeline.**
    - Formulation A comes first: one complex64 batched `matmul` over angular bins, a bin-major reference copy
      `(2 nk, R_t, P)`, batched `mlx_irfft` with `MLX_FFT_NORMS%backward`, the distances, and the draw on
      the device. One entry `(d(irot), irot)` comes back per pair.
    - Then B (real GEMM on packed (Re, Im)), then C (the inverse transform as a second real GEMM), each with
      and without `mlx_compile` of the elementwise tail.
    - The kernel that SIMPLE copies keeps one formulation per precision mode. A second one stays only where
      it is more than 30 % faster (design decision 37).
    - Variates are keyed by global particle and reference IDs, never by tile position.
13. (2026-11-22, from design decision 42.3) **Tiles.**
    - The GPU sweep is B in {64, 250, 500, 1,000, 2,000} and R_t in {64, 250, 500, 1,000, 2,500} (*guessed*
      grid). Configurations above the available particles per half, above the active references, or beyond
      the budget are pruned before allocation and recorded.
    - The budget is a quarter of machine memory (*guessed*). It covers all live allocations of the
      pipeline, both overlap slots included.
    - No tile size is searched by paging.
14. (2026-11-22, from design decisions 15, 26 and 42.6) **The verdict.**
    - Judged on the M5 Ultra in full precision (`MLX_ENABLE_TF32=0`), against `block_prod` at all cores on
      the same machine and case, at its fastest measured CPU block size.
    - Throughput in useful pairs per second: 2,500 directions times 4 states against 2,000 particles split
      between halves.
    - From prepared memos through entries in Fortran arrays, including GPU particle-term construction and
      upload. Best of 3 after a warm-up, two invocations per case.
    - At least 2.0 times is **go**, 1.0 to 2.0 is **lead**, below 1.0 is **negative** (Hans, design
      decision 26; denominator from 42).
    - The M2 Ultra's numbers are reported beside it, never as the verdict.
    - The accelerated mode (`MLX_ENABLE_TF32=1`, NAX) is recorded separately and counts only if it passes
      the same frozen gates.

15. (2026-11-22, Hans) **The shift maps join milestone 1.** They are example 1 of
    `doc/implementation_notes/planned/mlxf_scientific_examples.md`; its section 3 is the design reference,
    cited here, not copied.
    - *What:* for a particle and an ordered list of candidate references of its half, the normalised loss
      L(rotation, direction, radius) over a polar shift grid. It is built as SIMPLE builds it at
      `7ec7e2972` (`simple_polarft_shiftmap.f90`): the Fourier-Bessel expansion of the shift phase, the
      orders folded modulo the number of directions, and one 2D complex transform over (order, rotation)
      per radius. Then, per candidate and on the device: the mode (loss, rotation, shift), the physical
      width and the optional log evidence. Only the compact results come back.
    - *Not in it:* the stochastic disk draws, the continuous (gradient) shift search, and the fill's
      screen-then-window policy. The caller passes the radii, directions and shells.
    - *Owner:* the submodule `mlxf_kernel_polar_table_shiftmap` of Phase 4's workspace owner. It uses the
      same prepared references, halves and lifecycle; it is not another scorer.
    - *Fixture and oracle* (the note's section 3; analytic rings, no `random_number`):
      - full ring 24, shells 1 to 4, box 32, 5 particles, 7 references in each half;
      - candidates `[7, 2, 5]`, then a permutation and a duplicate;
      - radii `[0, .5, 1, 1.5]`, 16 directions;
      - a second case for the folding: ring 8, box 16, shells 1 to 3, radii `[0, 4, 8]`, 7 directions;
      - the oracle evaluates the residual directly at every grid point in real64, with no Bessel table and
        no FFT.
    - *Bessel weights:* computed on the host in real64 and rounded once. The truncation order K comes from
      the note's derived tail bound (≤ 1e-12; checked on 2026-11-22 to be valid and tight), never from
      observed GPU error.
    - *Tests:* sub-suite `polar_shiftmap` of area `kernels`, tester
      `mlxf_kernel_polar_table_shiftmap_tester.f90`. *Benchmark:* mode `shiftmap` of `bench_polar_table`.
16. (2026-11-22, by decision 15) **Operations added to decision 8 for the shift maps.**
    - Complex FFTs: `mlx_fft` and `mlx_ifft` along one dimension, and `mlx_fft2` and `mlx_ifft2` over two
      given dimensions, with `n` and `norm` as decision 8's FFTs. Only the forms the formulation uses enter.
    - `mlx_logsumexp` along a dimension.
    - `minloc` along a dimension: 1-based, the first position on ties. A map of more than one dimension is
      reshaped in Fortran order before it, and the tie rule is asserted on both devices.
    - `sqrt`.
    - Decision 8's sibling rule applies; the report lists every name.
    - They are general operations and are delivered in Phase 2 with decision 8's (decision 20); Phase 5b
      uses them.
17. (2026-11-22, from the scientific examples' section 6; caps *guessed*) **The shift maps' gates.**
    - A complete map against the direct oracle: normalised L2 error ≤ 1e-4, with the maximum error
      recorded beside it.
    - Log evidence, CDF and moments: absolute error ≤ 1e-4 in log or CDF units, and ≤ 1e-4 max(1, ρ_max²)
      for the variance.
    - Indices, padding exclusion and data movement are exact. A mode is judged only where the oracle's
      best-to-second margin exceeds twice the map bound.
    - Three repeated evaluations at fixed inputs give identical results (*exact*).
    - **Phase 5b's calibration entry** confirms every cap on the CPU device (unfused, run twice) before any
      GPU run, and freezes it in `src/test/mlxf_test_defs.f90`. A cap the CPU device does not meet is a
      stop and a finding, never a wider cap.
18. (2026-11-22, revised the same day by decision 19; the thresholds are a default by analogy with design
    decision 26, which Hans may veto) **The shift maps' verdict.**
    - *CPU:* `maps_per_s` of SIMPLE's `polar_matching_bench suite=shiftmap` at the full team, on the same
      machine and case, at the SIMPLE pin, two invocations (decision 19).
    - *GPU:* `maps_per_s` of `bench_polar_table suite=shiftmap` on the same case and grid, in full
      precision, best of 3 after a warm-up, two invocations. Reference preparation and the Bessel table are
      reported separately; per-particle work and the copy-out are inside the timing.
    - *Verdict*, per map (window and screen), separate from decision 14's: GPU over CPU ≥ 2.0 **go**, 1.0
      to 2.0 **lead**, < 1.0 **negative**. The report gives both maps; the screen carries most of the cost
      in the PorF and exp_gate profiles.
    - *Caveats stated beside the numbers:*
      - the CPU suite plans its FFTs with `FFTW_MEASURE`, as production does (decision 22; its
        `fftw_plans` column says so), but without production's wisdom file;
      - the CPU suite builds maps back to back with warm per-thread work arrays, while production
        interleaves them with block scoring and the shift refinement;
      - the CPU suite computes the width for every candidate, as the GPU does, while production skips the
        width of a candidate whose loss is above its best so far (`width_cutoff`), so the reduction column
        is production's worst case. The width was 40 % of the screen's CPU time per map in the smoke run
        (1,130 of 2,790 µs). So the report also gives a production-equivalent CPU cost per map,
        `us_construct + us_select + w * us_reduce`, with w the share of maps that compute a width in a
        production profile (`fill map widths` over `fill map selections`). That ratio is reported beside
        the verdict, not gated.
    - The PorF and exp_gate per-map costs are context only (machine and commit unrecorded).

19. (2026-11-22, Hans: "make the benchmarks match up in the two code bases") **Matched benchmarks.**
    - *SIMPLE side* (written interactively on 2026-11-22, committed by Hans before Phase 0):
      `simple_test_exec test=polar_matching_bench suite=shiftmap [nspace= nstates= nptcls= nthr=]`.
      - It runs on the same synthetic data and production calculator as `block_prod` (default 2,500
        directions times 4 states, 2,000 particles split by halves).
      - It builds the dense fill's two coarse maps with production's `setup_shiftmaps`: the screen over
        the disk of three prior widths (`disk_radius_px`), and the window at a refinement stage's shift
        limit (`stage_trslim` at `smpd_crop`, a 5.2-pixel radius here). Both grids step by `box/kscreen/4`
        (1.45 pixels at `kscreen` 31), so the smoke run's window had 4 radii to 4.35 pixels and 14
        directions, and its screen 11 radii to 14.5 pixels and 35 directions.
      - It times `gen_shiftmap` and `shiftmap_mode` with the physical width for 16 candidates per
        particle. Candidate c of particle i is `1 + mod(i-1 + (c-1)*(nrefs/16), nrefs)`.
      - The temperatures are production's: `prob_beta * posterior_temperature(wsqsum_ptcl_band(i,
        kscreen), pftsz)`. The prior applies on the screen only.
      - It covers the teams the driver sweeps (all, half and one thread, one thread capped at 200
        particles), best of 3 after a warm-up.
      - Rows go to `./polar_shiftmap_bench.tsv` with these columns: `map`, `nspace`, `nstates`, `nrefs`,
        `nptcls`, `ncand`, `nthr`, `pftsz`, `nrots`, `kfrom`, `kscreen`, `nrho`, `nalpha`, `norder`,
        `rho_max_px`, `prior_w`, `load1`, `wall_s`, `wall_rep1..3`, `us_map_thread`, `maps_per_s`,
        `us_construct`, `us_select`, `us_reduce`, `fftw_plans`.
      - The one-thread results of 64 particles (loss, width, the mode's rotation, radius and direction) go
        to `./polar_shiftmap_identity_<map>.bin` for comparing builds byte for byte, under
        `fftw_plans=estimate` (decision 22). A team-identity line compares them with the full team's under
        either planner (the mode draws nothing, so they must be identical).
    - *mlx-fortran side* (Phase 5b): `bench_polar_table suite=shiftmap` on the same case.
      - It reads the grid from SIMPLE's row: `pftsz`, `nrots`, `kfrom`, `kscreen`, `nrho`, `nalpha`,
        `rho_max_px`, `prior_w`. The radii are `(i-1) * rho_max_px / (nrho-1)`.
      - The candidate rule, the temperature formula and the screen-only prior are as above. The width is
        computed for every candidate.
      - Its rows carry the same column names for every shared quantity. `nthr` is replaced by `device` and
        `fftw_plans` by `precision`, and its own columns follow: `norder_used`, `mlx_peak_bytes`,
        `prep_s`, `copyout_s`.
      - `norder` (SIMPLE's Bessel order count) and `norder_used` (the order K from decision 15's tail
        rule) may differ. Decision 17's accuracy gate is what makes the work equivalent.
    - *Scoring* (Phase 5): the rows of `bench_polar_table suite=time` likewise carry `polar_matching_bench`'s
      case columns with the same names: `nspace`, `nstates`, `nrefs`, `nptcls`, `pftsz`, `nrots`, `kfrom`,
      `kto`, `load1`, `wall_s`, `wall_rep1..3`, `pairs_per_s`. Here B and R are the GPU tile, with `device`,
      `precision` and memory columns added, `precision` in the place of SIMPLE's `fftw_plans`. The case
      geometry is read from Phase 0's `block_prod` rows.
20. (2026-11-22, Hans) **Phases 1 to 3 are done interactively, with Codex**, on the Mac: Phase 1's open exit
    items, Phase 2 with decision 16's operations, and Phase 3. Each phase writes its Progress entry with the
    exits as written. Run `mlxf_m1` starts at Phase 0 on the commit that holds them, and then runs Phases 4
    to 5b.

21. (2026-11-22, Hans: "Use the checked callback subroutine (recommended)") **`mlx_function` wraps a checked
    subroutine.** This replaces design decision 30's "a Fortran function of arrays".
    - The callback is `subroutine callback(inputs, outputs, status)`: `inputs` an array of handles,
      `outputs` an allocatable `intent(out)` array of handles, and `status` an integer (0 on success).
    - It uses checked operations and returns failures through `status`. It never stops.
    - Why: gfortran 16.2 frees an allocatable array function result of a finalizable type before finalizing
      it, a heap-use-after-free under AddressSanitizer
      (`doc/compiler_issues/gfortran_finalize_allocatable_array_result.f90`, issue 5 of its README).
    - The binding policy's section on closure callbacks is the living rule. No gate was relaxed.

22. (2026-11-22, Hans: "we should make this default across the packages") **The CPU comparator plans its
    FFTs as production does.**
    - *SIMPLE:* `polar_matching_bench` plans the calculator's FFTs with `FFTW_MEASURE` by default in
      `suite=block_prod` and `suite=shiftmap` (`fftw_plans=measure`), as production does. `fftw_plans=estimate`
      gives reproducible output, and only it writes the identity files `polar_shiftmap_identity_<map>.bin`:
      measured plans can differ between runs in the last bits. Measured planning reads and writes no wisdom
      file and is logged apart from the timed loops. Both TSVs carry an `fftw_plans` column.
    - *Evidence* (Codex's side-quest plan `mlxf_m1_codex.md`, Phase 4; M3 Pro, 2,000 particles, two
      invocations per planner): measured plans left `block_prod` within its spread (−2 % to +0.6 %) and made
      the screen maps 6–7 % and the window maps 1.5–2 % faster. Planning took about 12 ms for the
      calculator's plans and 11 ms for a screen map's. With
      `estimate`, the full 2,500 × 4 case's identity files equal the pin's byte for byte.
    - *The pin:* decision 19's SIMPLE pin moves to Hans's commit of the planner option on top of
      `ed0aaa342`. The comparator's code (`pftc`, the benchmark, the probability tables, `stage_trslim`) is
      unchanged from `3a595f42f` there apart from the planner. That commit is a launch precondition of both
      runs, and Phase 0 records its hash.
    - *The runs:* Phases 0 and 6 run both suites with the default and keep the `fftw_plans` column. A byte
      comparison of SIMPLE builds uses `fftw_plans=estimate`. Decision 18's caveat on the FFTW planner is
      withdrawn.
    - *Later comparators:* an FFTW comparator in this repository (section 9's particle-stack FFTs) plans
      with `FFTW_MEASURE` too, and states SIMPLE's production planner for that transform beside it.
    - *Not changed:* SIMPLE's production planners. The polar calculator already measures, with wisdom.
      Particle-image FFTs use `FFTW_ESTIMATE` unless a caller asks for `fft_measure`. Changing them is a
      SIMPLE production change, judged by timing on its x86 target, and is not part of this plan.

23. (2026-11-23, Hans, review of run `mlxf_m1`: "SIMPLE's policy should be the default") **The shift maps keep
    SIMPLE's Bessel orders.** This replaces decision 15's truncation (K from a 1e-12 tail bound, one K for
    every radius).
    - *The rule:* at each radius rho, take z = 2 pi kstop rho / box. Starting at the order ceiling(z), drop
      every order from the first one whose |J_n(z)| is below `POLAR_BESSEL_JTOL` = 1e-8 (SIMPLE's
      `SHIFTMAP_JTOL`). The weights of orders above a radius's limit are zero; the transform spans the largest
      limit.
    - *Why:* the run's tail bound kept 21 orders against SIMPLE's 16 on the window and 41 against 32 on the
      screen, about 30 % more work than the comparator does.
    - *When more orders:* only where measured GPU scheduling makes them cheaper.
    - *Effect:* decision 17's frozen caps judge the result and are unchanged. Map errors stay at 5e-7; the
      folding case keeps orders 0..23 instead of 0..30.
24. (2026-11-23, Hans, ruling on the fixture's recalibration) **Each formulation is judged against its own
    fixture calibration.** On the CPU device at fixture seed 1, each formulation (B, C) gets its own frozen
    pair (e_cpu, n_cpu). The gate on seed 2 keeps factor 2 and q against the formulation's own pair.
    - *Why:* formulation C computes the inverse transform as a matrix product, and its rounding is its own.
      After the fixture's banks became translated particles, C's seed-2 error was 9.30e-7 on both the CPU
      and the GPU, the same value on both devices, against B's 2.40e-7.
    - *Scope:* the gate is meant to catch error the device adds, not the difference between formulations.
    - *The accuracy block:* its single pair is unchanged. Every formulation passes it.

25. (2026-11-23, Hans, review of run `mlxf_m1`: "do the tile here and then transfer to the SIMPLE CPU code if it
    works") **The shift maps are built in particle tiles.**
    - *Tiles:* a tile is a block of particles, each with all its candidates. `polar_map_block%ptcl_tile` (it
      was `ptile`, pairs) counts particles. The reference-frame grid of SIMPLE's map is unchanged.
    - *Per particle once:* the order-expanded, Bessel-weighted spectra Z[(n, rho), k, m'] = w_k J_n
      Y^_k[m' + n], built as real and imaginary parts. The order's shift sits on the particle here, not on
      each reference.
    - *Per tile:* one real product of packed parts, batched over (ring position m', particle):
      [Re Z, Im Z] times [[Re R, Im R], [-Im R, Re R]] over the candidates' spectra. This gives
      G'_n[m', rho] = G_n[m' + n, rho].
    - *Then:*
      - the forward transform over m';
      - the order's phase exp(-2 pi i n r / nrots), which accounts for the shift on the particle;
      - the orders folded onto the directions, as the sum of the transforms of each run of nalpha orders;
      - the selection and the reduction, each a compiled graph.
    - *Judged:* decision 17's frozen caps judge the new form, and the run's formulation is gone.
    - *For SIMPLE:* the same decomposition, a per-particle Z reused across the candidates through one small
      GEMM per ring position, is the candidate for SIMPLE's CPU code once the re-timing confirms it.

26. (2026-11-23, Hans: "Yes, do it") **`mlx_take` and `mlx_bitcast` enter now, ahead of the parity plan.**
    Both are on the parity ledger (`mlxf_mlxc_parity.md`, its decision 6 for `mlx_bitcast`, its Phase 3 for
    `take`). Both are general library operations, so the verdicts of decisions 14 and 18 keep their meaning.
    - `mlx_take(a, indices, dim)` gathers whole slices at one-based indices: the indices' shape replaces
      dimension `dim`.
    - `mlx_bitcast(a, dtype)` is MLX's `view`: the bytes read as another dtype, with the first Fortran
      dimension scaled by the ratio of the item sizes.
    - *In the shift maps:*
      - the contraction runs as the transposed product, with rows alternating the real and imaginary parts,
        so its output is read as complex64 without a copy;
      - the particles' and the candidates' spectra are gathered as slabs.
    - *The policy:* section 10 of the binding policy carries both conventions.

Defaults taken without a question: the folder and submodule names of decision 10, the vocabulary name
`MLX_FFT_NORMS`, the run names of decision 6, the file name of decision 9, the rule name `ctorexpr`, the
submodule, tester, sub-suite and mode names of decision 15, and decision 19's candidate count (16), check
size (64), file name and the mlx-fortran column names.

## 4. Not in this plan

- Any change to SIMPLE beyond decision 19's benchmark suite and decision 22's planner option, which are made
  before launch. SIMPLE's integration is a SIMPLE plan written after the hold (design decisions 32, 42).
- Transforms (`grad`, `vjp`, `vmap`), neural-network layers, explicit streams, IO, float16 and bfloat16,
  quantised operations, CUDA, Linux, flang, Windows, packaging and releases.
- n-dimensional FFTs beyond the shift maps' two-dimensional transform, gather and scatter, Metal kernels,
  packaging for consumers: section 9.
- The shift maps' stochastic disk draws, the continuous (gradient) shift search, and the fill's
  screen-then-window policy (decision 15).
- GPU scoring of sparse pooled members and `geom` cones. Shared representatives are in scope (design
  decision 42.3).
- Changes to the handle model: the registry, the lifetime submodule, the defined assignment and `final`.
- Upstream changes to mlx-c or MLX. A question that work meets goes to `doc/collaboration/apple_questions.md`.
- Out of bounds, read only: `~/src/mlx`, `~/src/mlx-c` and `~/src/SIMPLE`, with exports in scratch.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement only | base gate in Debug and Release; SIMPLE `block_prod` twice per dense case; `check`, `fills`, `neigh`; `shiftmap` twice with its team identity |
| 1 | tests, static gate, and the fixes `ctorexpr` asks for (an element assigned to a variable first; behaviour identical) | fast gate in Debug and Release; `recovery_half` (if decision 3 is ruled yes); `ctorexpr` and narrowed `ctorcall` plants; budget unchanged at 3 |
| 2 | new code: operations, `matmul`, FFTs | `unit_ops`, `unit_linalg`, `unit_fft` on both devices with section 6's tolerances; leak gate unchanged; budget 6 |
| 3 | new code: compilation | `unit_compile` on both devices; budget 7 |
| 4 | new test code: the polar pipeline at fixture size | fixture calibration frozen before any GPU run; `unit_kernels suite=polar_table` on both devices; budget 8 |
| 5 | new test code and measurement: the benchmark on the M2 Ultra | block calibration frozen before its GPU run; accuracy block on seed 2 within the frozen gates; schedule identity at block size; `time`, `profile`, `overlap` rows |
| 5b | new code and test code: the shift maps (decision 15) | the decision 16 operations' area tests on both devices; shift-map calibration confirmed on the CPU device before any GPU run; `unit_kernels suite=polar_shiftmap` on both devices; `bench_polar_table suite=shiftmap` rows; budget unchanged at 8 |
| 6 | measurement: bring-up and the verdicts on the M5 Ultra | fast gate there; baseline refresh there (`block_prod` and `shiftmap`); scoring verdict and shift-map verdicts recorded with their branches (decisions 14, 18) |
| 7 | report | the interim summary and the report exist; plan moved to `completed/` |

## 6. Acceptance

Every number carries its origin: *exact*, *measured*, *derived*, *literature* or *guessed*. Correctness runs
are in full precision. The numbers below are the design plan's section 6, frozen here. No ruling moves them,
and the calibrated quantities are fixed by their calibration entries (Phases 4a, 5a and 5b).

- **Fast gate.** Every entry passes. A total over 60 s warns (*measured* in SIMPLE). Zero compiler warnings
  in Debug and Release.
- **Exact gates.** The leak gate, the diagnosis gate and the recovery gate. Byte identity of data movement.
  Generator coverage (673 + 7 = 680 against the list frozen in the design plan's Progress, *exact*).
- **Single operations**, against plain Fortran double precision, with tolerance factor 1e-5 (*guessed*: two
  orders above float32 rounding, four below a wrong convention):

  | operation | float32 and complex64 bound | float64 on the CPU device |
  | --- | --- | --- |
  | elementwise arithmetic | \|err\| ≤ 1e-5 (\|a\| + \|b\|) | 1e-12 (\|a\| + \|b\|) |
  | elementwise functions on \|x\| ≤ 20 | \|err\| ≤ 1e-5 max(1, \|f(x)\|) | `exp`, `sin`, `cos`: the float32 bound (design decision 10) |
  | reductions and scans over n terms | \|err\| ≤ 1e-5 Σ\|terms\| | 1e-12 Σ\|terms\| |
  | `matmul` | \|err\| ≤ 1e-5 Σ_k \|a_ik b_kj\| | 1e-12 Σ_k \|a_ik b_kj\| |
  | FFT of length n | ‖err‖₂ ≤ 1e-5 log2(n) ‖x‖₂ | the float32 bound (MLX casts) |

  Data movement and index operations (`reshape`, `transpose`, `mlx_permute`, `mlx_concatenate`,
  `mlx_slice`, `mlx_take_along_dim`, `merge`, comparisons) are byte-exact (*exact*).
- **Conventions asserted** by name in the testers:
  - dimension numbering, and broadcasting that aligns leading Fortran dimensions;
  - `mlx_permute`'s order (dimension i of the result is dimension `order(i)`);
  - 1-based indices and positions in and out;
  - the FFT's sign and its `backward` 1/n normalisation;
  - weak scalars: `2.0_dp` never makes a float64 graph;
  - `matmul(a, b)` against Fortran's intrinsic on the same data.
- **The polar pipeline: oracles** (design section 6, unchanged).
  - *Fixture:* pftsz 32, nk 10, 8 references and 6 particles per half (96 pairs), temperatures 0, 1, 30 and
    1e4. The memo arrays are built by a double-precision DFT, and the ring oracle computes d directly as
    Σ_k w_k Σ_j |X_j − C_j R_(j−r)|² / (2 wsq).
  - *Accuracy block:* 64 particles against 1,000 references at SIMPLE's sizes (64,000 pairs), with a
    DFT-matrix oracle.
  - *Rows:* a calibration on the CPU device measures e_cpu, the largest error of d relative to max|d|,
    and n_cpu, the pairs whose minimising rotation differs from the oracle's. Each object has its own pair:
    the fixture on seed 1 (Phase 4a) and the accuracy block on seed 1 (Phase 5a). Each pair is frozen in
    Progress before that object's first GPU run.
  - *Judged on seed 2, every formulation, each object against its own pair:* error ≤ 2 e_cpu (factor
    *guessed*). Minimising-rotation disagreements ≤ max(2 n_cpu, q), with q = 1 for the fixture's 96 pairs
    and 5 for the block's 64,000. q is the Poisson count at SIMPLE's 1e-5 per pair (3 in 320,000,
    *measured* at `5709265cb`) exceeded with probability below 1e-4 (*guessed*).
  - *Reported, not gated:* per temperature, how often the device's irot differs from the draw on the
    oracle's rows with the same u. Also the effect of the caller's float32 u against SIMPLE's real64 keyed
    variate (design decision 42.5).
  - *The draw, given the device's own rows:* u W lies in the drawn rotation's cumulative interval within
    1e-4 W (*derived*: 364 × 2⁻²⁴ ≈ 2.2e-5, with a factor 4.5 to spare), the fallbacks hold, and the entry's
    distance is d(irot) exactly.
- **Production-contract coverage** (design section 6).
  - Cases: both halves, ordinary and shifted-bank particles, full and partial tiles, contiguous and listed
    references, one and several states, and the shared-representative subset with global IDs.
  - Edge cases: zero temperature, invalid rows, and the first-reaching rule with its fallback.
  - Mismatches of generation, half, shape or list are refused before scoring. References are rebuilt after
    they change.
  - Live count and active memory return to their warm values after teardown (*exact*).
  - The benchmark's memo dimensions, shells, dtypes, temperatures and half counts match Phase 0's recorded
    CPU case.
- **Schedule identity** (*exact*, a gate no ruling may waive). With inputs, variates, precision, formulation
  and the canonical tile mapping fixed, three repeats give identical entries by global pair ID. So do
  changes of outer batch, CPU team size (1 and 24), and synchronous against two-slot consumption. Checked
  at fixture size in Phase 4 (repeats, outer batch, slots) and on the accuracy block in Phase 5 (all four).
  Tile-shape and position changes, partial edges and shuffled reference lists are judged against the frozen
  row and draw gates. They are reported against the oracle and the canonical configuration, per
  temperature, never forced to identity.
- **Memory.** MLX peak, host staging, reference bytes, process peak and the estimated live total are
  recorded without counting aliased buffers twice. FFT and posterior scratch, arrays retained by
  compilation, and both slots when overlapping are included. The verdict's configuration stays under
  decision 13's budget. Retained bytes and the observed process growth are reconciled before a go verdict;
  a gap that cannot be explained turns go into lead.
- **The shift maps:** decision 17's gates, on both devices. The assertions are the note's section 3
  list:
  - every map, intermediate contractions included, against the direct oracle; the zero-radius map equals
    the dense unshifted row and does not depend on direction;
  - pose recovery in the noise-free case, where the margin allows it;
  - the Nyquist ring (loss 0 at identity, 4 after one step);
  - the folding case;
  - evidence and width against direct host log-sum-exp and grid moments, at zero prior, flat likelihood,
    and distinct physical and tempered temperatures;
  - half-specific references and weights, invalidation after a reference change, candidate permutations
    and duplicates, single-entry and non-divisible tiles, and padding never entering a reduction.

  Each of the note's negative controls (Nyquist omitted, shift sign reversed, halves mixed, cell area
  omitted, tempered temperature used for the physical width) is planted and shown to fail its assertion.
  After 100 create/use/kill cycles of the workspace with maps, the live count and active memory return to
  their warm values.
- **The verdict:** decision 14. On every branch the report gives the GPU stage profile; on lead and negative
  it also gives the mechanism that limits the ratio. A synthetic scoring verdict is not a measured
  end-to-end speedup and not a scientific acceptance of anything in SIMPLE.
- **Overlap** (reported, not gated): synchronous against two slots at the same canonical tile plan, with
  tile n+1 queued from outside any OpenMP region. Recorded: the fraction of CPU preparation and consumption
  hidden, and the GPU's slowdown under a concurrent CPU memory-streaming load.

## 7. Common rules and stop conditions

Rules:

- **Files.** No file outside the table; a needed file gets a row first and the report lists it.
- **Frozen numbers.** No tolerance, floor or threshold relaxed without a ruling; each is frozen in Progress
  before the run it judges.
- **House rules.** They hold (`doc/architecture_principles.md`, `CLAUDE.md`, the skills `mlxf-modern-fortran`
  and `mlxf-binding`). A new structural rule goes into `check_rules.py` with a planted violation shown to
  fail.
- **Before a phase is DONE:** `scripts/check_tree.sh` passes; every touched Fortran file has been through
  `restyle_fortran.py` and `format_use_blocks.py`; Debug and Release build from scratch with zero warnings;
  the fast gate passes; owner decisions and delivered batches are in `doc/history/2026-11.md` (or
  `2026-12.md`).
- **Timed runs.** In Release, on an idle Mac with the load recorded (others at most 400 % of a core, as in
  the design plan's Phase 0), best of 3 after a warm-up, the spread between two invocations reported, and
  the precision mode in every row.
- **Fixes and tools.** Bugs found are fixed in the phase that finds them. Python is standard library, 3.7 or
  newer.
- **Git.** No commit, no push, no state-changing git command; read-only git carries `--no-optional-locks`.
  Files edited with `sed -i` are checked with `git diff --summary` for lost execute bits.

Stop when:

- the base commit of the preconditions does not exist, or the working tree is not clean at launch or
  changes under the run (decision 6);
- the dependencies are missing or not shared, or the run's session sees no GPU device;
- the SIMPLE pin does not build, `suite=list` lacks `block_prod` or `shiftmap`, its `check` or `fills` suite
  fails in a case the verdict depends on, or `suite=shiftmap` reports a map differing between teams. Record
  the case; never substitute `matrix_t` or a profile;
- a phase needs to edit the handle model (section 2's invariant), or the leak gate fails;
- MLX contradicts a decision: an operation of decision 8 missing for float32 or complex64 on the GPU,
  `irfft`'s normalisation not `backward` 1/n, or a compiled closure that cannot call back into Fortran;
- gfortran cannot carry a decision beyond the four known defects. Stop with a reproducer;
- a tolerance, floor or threshold would have to move, or a file outside the table needs an edit;
- canonical scheduling cannot satisfy schedule identity, or no oracle-passing tile fits the budget. Report
  the offending pairs or configuration and the measured memory;
- a shift-map cap of decision 17 is not met on the CPU device at calibration, or MLX cannot give the
  first-position tie rule of `minloc` on a device.

Gates no ruling may waive: the leak, diagnosis and recovery gates; byte identity of data movement; generator
coverage; the oracle comparisons on both devices; the frozen tolerances; schedule identity.

## 8. Phases

**Launch precondition.** Hans has committed the working tree on top of `0d3537b`, including Phase 1's
interactive changes once they build and gate on the Mac. The run records the hash, and that Phase 1 is done
(its Progress entry).

### Phase 0, the baseline (run `mlxf_m1`, M2 Ultra)

1. Record the machine (chip, cores, GPU cores, memory, macOS, Command Line Tools or Xcode, GFortran, CMake,
   Python, load), the base commit and Homebrew's `mlx` and `mlx-c` versions.
2. Build the base in Debug and Release from scratch (`compile_debug.sh`, `compile_clean.sh`) and keep both
   trees. Record the fast gate's per-entry times (`ctest_fast.log.timing.txt`), with `unit_core`'s recovery
   share, and the zero-warning check.
3. Export the SIMPLE pin (decisions 19 and 22) into scratch and configure it by hand: Release, tests on,
   `-DFORTLS=OFF`. Build it, run its fast gate (record failures per case), and record the BLAS and FFTW it
   links. Confirm `block_prod`, `check`, `fills`, `neigh` and `shiftmap` with `simple_test_exec
   test=polar_matching_bench suite=list`.
4. Run each of the four dense cases twice, all of run 1 before run 2:
   `OPENBLAS_NUM_THREADS=1 simple_test_exec test=polar_matching_bench suite=block_prod
   nspace=<1000|2500> nstates=<1|4> nptcls=2000 nthr=24`. Add a run at `nthr=16` (the performance cores).
   Keep every TSV, the load record, B, the useful pairs and the spread. The rows' `fftw_plans` column reads
   `measure`, the default (decision 22). The driver's one-thread
   200-particle row is labelled as such and not compared with the all-core workload. Record the polar
   dimensions (pftsz, nk, nrots) and the reference residency for Phase 4's generator.
5. `suite=check nthr=24` and `suite=fills nthr=24` once each, with default sizes and all routes.
   `suite=neigh nthr=24` twice, keeping the representative, member and cone rows apart.
6. s and f per decision 5, or recorded as unmeasured.
7. `simple_test_exec test=polar_matching_bench suite=shiftmap nthr=24` twice, then once at `nthr=16`
   (decision 19), with the default measured plans. Keep both TSVs and the team-identity lines. The rows' grid
   columns (`kscreen`, `nrho`, `nalpha`, `rho_max_px`, `prior_w`, for the window and the screen) are the
   geometry Phase 5b's benchmark reads. Also record the per-map CPU costs of the PorF and exp_gate profiles
   (map construction, selection and reduction thread-seconds over their map counts), labelled with their
   unknown machine and commit.

Exit: the machine record and base hash; both base trees gate with zero warnings; the fast gate's per-entry
times are in Progress; SIMPLE built, its fast gate recorded, `block_prod` measured twice per dense case with
spread ≤ 5 % at the full team (*guessed*, above the 1.4 % `matrix_t` showed in the design plan's Phase 0).
A case above 5 % is repeated once; then the exit is met with both spreads recorded, since the verdict uses
Phase 6's baseline, not this one. `check` and `fills` pass in the verdict's cases; the `neigh` rows are
kept; the polar dimensions are recorded; s and f are measured or marked unmeasured; `suite=shiftmap` has two
runs per map at the full team, spread ≤ 5 % (*guessed*, as for `block_prod`, with the same repeat rule), and
its team-identity lines show 0 maps differing; the grid and the profiles' per-map costs are in Progress.

### Phase 1, the follow-ups (run `mlxf_m1`)

1. Decision 3 as ruled. If yes: in `test_recovery`, the fast form (failing evaluation, the same graph at
   256 rows, counters back); the sub-suite `recovery_half`, which `run_area` runs only when named; the
   policy and `test/CMakeLists.txt`'s comment updated. If no: nothing changes, and the reason goes to
   Progress.
2. Rule `ctorexpr` and the narrowed `ctorcall` (decision 7). `ctorexpr` is run on the tree before any
   other edit of this phase. Each finding is fixed by assigning the element to a variable first, which
   changes no behaviour, and is listed in Progress. Both rules are shown on the planted and allowed forms of
   decision 7. The policy's paragraph after its unsupported uses names both rules. `check_tree.sh`'s header
   lists the rule.
3. `doc/compiler_issues/README.md` (decision 9). Each reproducer is compiled and run once more with
   gfortran 16.2 (and 13.4 if installed), and the output it quotes is the output of that run.
4. Decision 4 recorded in the policy's unsupported use 6, with the reason ("stays unsupported, by ruling").

Exit: Debug and Release from scratch, zero warnings, fast gate passing with budget 3; `unit_core`'s time in
Progress beside Phase 0's; `mlxf_test_exec test=unit_core suite=recovery_half` passes on both devices (if
decision 3 is ruled yes); `ctorexpr` fails on the five plants of decision 7 and passes on its allowed
forms and the tree; `ctorcall` passes `[real(i), 1]` and still fails `[mlx_from(x), b]`; the README exists
and its outputs match a recorded run; the leak gate unchanged and passing.

### Phase 2, the operations (run `mlxf_m1`)

1. The elementwise, shape, reduction and fixture names of decision 8, in `mlxf_ops` and its submodules,
   and the operator extensions in `mlxf_array` and `mlxf_array_elementwise`. Each follows the skill
   `mlxf-binding`: the generated procedure, its signature class's helper, the translation of axes and
   indices, the entry, and a two-device test.
2. `mlxf_linalg`: `matmul` (decision 8, design decision 6's `mlx_matmul(b, a)`).
3. `mlxf_fft`: `mlx_rfft`, `mlx_irfft`; `MLX_FFT_NORMS` in `src/defs/mlxf_defs.f90`.
4. Testers `mlxf_ops_tester`, `mlxf_linalg_tester`, `mlxf_fft_tester` with section 6's bounds and
   conventions. CTest areas `ops`, `linalg`, `fft`; budget 6, shown to fail configuration at 5.
5. The leak gate gains one loop per new module (an expression of its operations, evaluated, 10,000
   iterations) in `mlxf_array_tester`. The gate stays exact.
6. The policy's sections on operations, linear algebra and FFTs: the conventions as living rules.

Exit: the three suites pass on both devices in Debug and Release; every convention of section 6 is asserted
by a named check; the leak gate passes with the new loops; budget 6; `check_tree.sh` passes (`entry`,
`arity`, `ctorcall`, `ctorexpr`, `defs` included); zero warnings.

### Phase 3, compilation (run `mlxf_m1`)

1. `mlxf_compile`: `mlx_function` (a `bind(c)` trampoline and a payload holding a procedure pointer; the
   trampoline never stops and returns a status, rule `cbstop`) and `mlx_compile(f, shapeless)`.
2. `mlxf_compile_tester`: a compiled elementwise function equals the uncompiled one byte for byte on each
   device; shapeless compilation over two tile sizes compiles once (the count recorded); an error inside the
   callback returns a status and leaves MLX usable; the leak gate gains a compiled-call loop. Area
   `compile`, budget 7.

Exit: `unit_compile` passes on both devices in Debug and Release; the callback error path returns a status;
the leak gate passes; budget 7; zero warnings.

### Phase 4, the polar pipeline at fixture size (run `mlxf_m1`)

1. `src/test/mlxf_kernel_polar_table.f90`: the workspace owner (a test-only type holding the prepared
   reference tile, its generation, half, shape and active reference mapping), its procedure interfaces and a
   validated input spec (design decision 39.1). Submodules `_lifecycle` (preparation, invalidation,
   idempotent teardown) and `_score` (formulation A; decision 12). It has no second ownership
   implementation: handles are `mlx_array`s.
2. `mlxf_kernel_polar_table_tester` (area `kernels`, suite `polar_table`): the independent fixture and ring
   oracle, the double-precision draw check, and the production-contract coverage of section 6. The area
   enters `test/CMakeLists.txt`, the registry's `AREAS` table and its `case()` branches together, so that
   `check_test_registry.py` holds, and the budget becomes 8. Until step 3's entry exists, the tester runs
   the pipeline on the CPU device only: its GPU branch is not written yet.
3. **Phase 4a, the fixture calibration**, on the CPU device, before any GPU run of the pipeline: fixture
   seed 1 gives the fixture's e_cpu and n_cpu. They are written to Progress with the derived bounds and to
   `src/test/mlxf_test_defs.f90` as constants, and from then on they are frozen.
4. The tester's GPU branch: the pipeline on the GPU on seed 2 against the frozen bounds. Schedule identity at
   fixture size: three repeats, two outer batch sizes, synchronous against two slots.

Exit: the Phase 4a entry precedes the first GPU run (Progress timestamps and logs); `unit_kernels
suite=polar_table` passes on both devices in Debug and Release with the frozen bounds; the lifecycle and
mismatch checks pass; schedule identity holds; budget 8; zero warnings.

### Phase 5, the benchmark on the M2 Ultra (run `mlxf_m1`)

1. `src/test/mlxf_bench_polar_table.f90`, `mlxf_test_exec test=bench_polar_table suite=<mode>`. It owns the
   outer batches and submission and appends rows to `./bench_polar_table.tsv`. Its `accuracy` mode carries
   the 64,000-pair generator and the DFT-matrix oracle. Its modes:
   - `time`: the four dense cases and a shared-representative case matching Phase 0's `neigh` rows, swept
     over decision 13's grid.
   - `profile`: evaluation barriers between stages, reported separately.
   - `accuracy`: the 64,000-pair block on seed 2 against the DFT-matrix oracle and the block's frozen
     bounds; the sensitivity to tile shape, partial edges, position, shuffled reference lists and
     compilation; schedule identity on the block (three repeats, two outer batch sizes, CPU teams 1 and 24,
     synchronous against two slots).
   - `overlap`: section 6's overlap measurement, including the run under a CPU memory-streaming load.
2. **Phase 5a, the block calibration**, on the CPU device, before the first GPU run of `accuracy`: block
   seed 1 gives the block's e_cpu and n_cpu, written to Progress and to `src/test/mlxf_test_defs.f90`, and
   from then on frozen.
3. Formulations B and C, and compilation of the tail, added to the pipeline's `_score` submodule after A
   passes `accuracy`. Each one passes the frozen gates before its timings count. The 30 % rule (decision 12)
   decides which stay. One that is dropped is recorded in Progress with its numbers and removed from the
   code.
4. Reference preparation, cold compilation, warm throughput and amortised preparation are recorded
   separately. Memory follows section 6.

Exit: the Phase 5a entry precedes the first GPU run of `accuracy`; `accuracy` passes the block's frozen gates
for every counted formulation; schedule identity holds on the block; `time` rows exist for every case
with memory, useful and padded pairs, and precision mode; the kept formulation and canonical tile plan are
named; the overlap rows exist; the M2 Ultra's ratio against Phase 0's `block_prod` is recorded as context.

### Phase 5b, the shift maps (run `mlxf_m1`, M2 Ultra; decisions 15 to 18)

1. The operations of decision 16 are delivered by Phase 2 (decision 20); this step checks that
   `unit_fft` and `unit_ops` cover them on both devices and adds what the formulation needs beyond them,
   with its area test (no new CTest entry).
2. `src/test/mlxf_kernel_polar_table_shiftmap.f90`, a submodule of the workspace owner: the Bessel-weight
   table (host real64, K from the tail rule, rounded once) prepared with the references; the shell
   contractions, the folding modulo the directions and the 2D transform per radius; then the mode, width and
   evidence reductions on the device. Compact results come back.
3. `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90`, sub-suite `polar_shiftmap` of `kernels`: the
   fixtures, the direct oracle and the assertions of section 6, CPU device only until step 4's entry exists.
4. **Phase 5b-a, the shift-map calibration**, on the CPU device: the unfused implementation run twice
   against the oracle. Every cap of decision 17 is confirmed and frozen in `src/test/mlxf_test_defs.f90`,
   in a Progress entry that precedes the first GPU run. Then the GPU branch of the tester. The negative
   controls are planted and shown to fail.
5. `bench_polar_table suite=shiftmap` on the M2 Ultra on decision 19's case, grid and columns, read from
   Phase 0's `polar_shiftmap_bench.tsv` rows: maps per second, with preparation (references, Bessel table),
   resident compute, output transfer and memory separate, best of 3 after a warm-up, two invocations. The
   ratio against Phase 0's full-team `maps_per_s` is recorded per map as context (the verdict is Phase 6's).

Exit: the decision 16 operations pass their area tests on both devices in Debug and Release; the Phase 5b-a
entry precedes the first GPU run of `polar_shiftmap`; `unit_kernels suite=polar_shiftmap` passes on both
devices with the frozen caps; every negative control fails its assertion; the 100-cycle lifecycle returns to
baseline; the leak gate passes; the `shiftmap` rows exist with memory and precision mode; budget 8; zero
warnings.

### Phase 6, the M5 Ultra (run `mlxf_m1_m5`)

1. Record the machine and dependencies as in Phase 0 step 1, with the GPU's `architecture` as
   `unit_core` prints it and the macOS version: the NAX preconditions of `doc/how2s/how2set_up_dev.md`,
   section 6. MLX reports no NAX-in-use key, so NAX use is stated only from a Metal capture of the
   workload; without one it is recorded as unproven, never inferred from the architecture.
2. Build Debug and Release from scratch at Phase 6's base. Run the fast gate, `recovery_half` (if
   decision 3 is ruled yes), `unit_kernels suite=polar_table` and `suite=polar_shiftmap` on both devices,
   and `bench_polar_table suite=accuracy`. The frozen bounds of Phases 4a, 5a and 5b-a are unchanged.
3. Repeat Phase 0 steps 3 to 5 and 7 there: the SIMPLE pin (decision 22), `block_prod` twice per dense
   case, `check`, `fills`, `neigh` and `suite=shiftmap` twice at the full team, both suites with measured
   plans. Recheck the polar dimensions, half counts and the shift-map grid against Phase 0's.
4. `bench_polar_table` on the M5 Ultra in full precision (`time`, `accuracy`, `profile`, `overlap`), then
   `time` and `accuracy` in accelerated mode. The accelerated mode is reported, and counts only within the
   frozen gates.
5. Memory reconciled as section 6 requires, then the verdict of decision 14 with its branch, and the
   projection of decision 5.
6. `bench_polar_table suite=shiftmap` on the M5 Ultra in full precision, then in accelerated mode, on
   decision 19's case and grid. The shift maps' verdict of decision 18 per map, against step 3's full-team
   `suite=shiftmap` rows, with its caveats stated.

Exit: the M5 Ultra's gates pass; its `block_prod` baseline is recorded twice per case; the scoring verdict
and its branch are recorded from rows that meet section 6; the shift maps' verdict is recorded per map with
its branch and caveats; the accelerated mode is reported with pass or fail.

### Phase 7, the interim summary and the report (run `mlxf_m1_m5`)

1. The interim summary for the hold of design decision 32, in Progress:
   - what milestone 1 proved, the scoring verdict and its branch, the shift-map measurement and its verdict
     or context ratio, and peak memory;
   - the kept formulation and the canonical tile plan;
   - numerical sensitivity per temperature, and the profile gaps;
   - what SIMPLE's integration would take: a calculator-owned workspace and a schedule split into
     preparation, submission and consumption.
2. `doc/implementation_notes/completed/mlxf_milestone1_report.md` in the order of section 8 of
   `doc/how2s/how2write_agent_plans.md`; this plan moves to `completed/`. Hold.

Exit: the summary and the report exist; the report cites every Progress entry and lists every file changed
outside the table; the plan is in `completed/`.

### File table

Paths from the repository root. A listed `x.f90` also covers `x_tester.f90`. "(new)" marks a file that does
not exist at the base.

| File | What | Phases |
| --- | --- | --- |
| `src/core/runtime/mlxf_error.f90` | the recovery gate's tester only (decision 3) | 1 |
| `src/test/mlxf_test_registry.f90` | named-only sub-suites; areas `ops`, `linalg`, `fft`, `compile`, `kernels`; sub-suite `polar_shiftmap`; benchmark entry | 1, 2, 3, 4, 5, 5b |
| `src/test/mlxf_test_utils.f90` | assertions for complex values, boolean arrays, tolerance helpers | 2, 4, 5b |
| `src/test/mlxf_test_defs.f90` (new) | shared test tolerances and the frozen calibration constants | 4, 5, 5b |
| `test/mlxf_test_exec.f90` | `bench_<x>` dispatch | 5 |
| `test/CMakeLists.txt` | areas, budget 3 → 8, comments (5b added 2026-11-22: the kernels comment names the shift maps) | 1, 2, 3, 4, 5b |
| `scripts/check_rules.py` | rule `ctorexpr`, `ctorcall` narrowed; rules learned | 1, each |
| any file under `src/` or `test/` that `ctorexpr` flags | the fix only: the element assigned to a variable first | 1 |
| `scripts/check_tree.sh` | the rule list in its header | 1 |
| `scripts/check_test_registry.py` | named-only sub-suites, benchmark rows; if needed for an area | 1, 2, 3, 4, 5, 5b |
| `scripts/gen_mlxc_bindings.py` | if a signature the new wrappers use is unmapped | 2, 3, 5b |
| `src/defs/mlxf_defs.f90` | `MLX_FFT_NORMS` and shared constants | 2 |
| `src/core/mlxf.f90` | re-exports | 2, 3, 5b |
| `src/core/array/mlxf_array.f90`, `src/core/array/mlxf_array_elementwise.f90` | operator generics: `/`, unary `-`, comparisons, logicals | 2 |
| `src/core/array/mlxf_array.f90` (tester only) | leak-gate loops for new modules | 2, 3, 5b |
| `src/core/array/mlxf_array_operations.f90` (new; row added after the fact, 2026-11-22) | the operations' signature-class helpers (design decision 4.2), a submodule of `mlxf_array` | 2 |
| `src/core/array/mlxf_array_closure.f90` (new; row added after the fact, 2026-11-22) | closure vectors to and from owned arrays, for `mlx_function` | 3 |
| `src/core/ops/` (new folder: `mlxf_ops.f90`, `mlxf_ops_{elementwise,shape,reduce}.f90`, `ops.inf`) | operations; `mlx_logsumexp`, `minloc`, `sqrt` (decision 16) | 2, 5b |
| `src/core/linalg/` (new folder: `mlxf_linalg.f90`, `linalg.inf`) | `matmul` | 2 |
| `src/core/fft/` (new folder: `mlxf_fft.f90`, `fft.inf`) | FFTs; the complex FFTs of decision 16 | 2, 5b |
| `src/core/compile/` (new folder: `mlxf_compile.f90`, `compile.inf`) | `mlx_function`, `mlx_compile` | 3 |
| `src/core/core.inf` | the capability folders it names | 2, 3 |
| `src/test/mlxf_kernel_polar_table.f90`, `src/test/mlxf_kernel_polar_table_{lifecycle,score}.f90` (new) | the test-only workspace and scoring | 4, 5, 5b |
| `src/test/mlxf_kernel_polar_table_lifecycle.f90` (new; the row above spelled out for the fence, ruling R1) | the test-only workspace and scoring | 4, 5, 5b |
| `src/test/mlxf_kernel_polar_table_score.f90` (new; the row above spelled out for the fence, ruling R1) | the test-only workspace and scoring | 4, 5, 5b |
| `src/test/mlxf_kernel_polar_table_shiftmap.f90` (new; its tester `mlxf_kernel_polar_table_shiftmap_tester.f90`) | the shift maps: submodule of the workspace, fixtures and direct oracle | 5b |
| `src/test/mlxf_bench_polar_table.f90` (new) | the benchmark, the accuracy block's generator and oracle; mode `shiftmap` | 5, 5b |
| `src/test/mlxf_kernel_polar_oracle.f90` (new; row added 2026-11-22 in Phase 5: the tester and the benchmark share it) | the polar fixtures' DFT, keyed variates, memo-level DFT-matrix oracle and the checks of rows and draws against an oracle | 5, 5b |
| `doc/policies/binding_contract_policy.md` | unsupported uses 3 and 6; operations, linear algebra, FFTs, compilation | 1, 2, 3, 5b |
| `doc/policies/test_environment_policy.md` | named-only sub-suites; areas; the benchmark (Phase 4 added 2026-11-22: area `kernels` and budget 8 change its text) | 1, 2, 4, 5, 5b |
| `doc/compiler_issues/README.md` (new) | the upstream report texts | 1 |
| `doc/how2s/how2set_up_dev.md` | the recovery gate's cost and its named-only form | 1 |
| `.github/skills/mlxf-binding/SKILL.md` | patterns learned while wrapping | 2, 3, 5b |
| `.github/skills/mlxf-modern-fortran/SKILL.md`, `references/testing.md` | rules learned | each |
| `.github/skills/mlxf-modern-fortran/references/testing.md` (the row above spelled out for the fence, ruling R1) | rules learned | each |
| `doc/architecture_principles.md` | a rule learned, with its check | each |
| `doc/collaboration/apple_questions.md` | questions met, answers recorded | each |
| `doc/history/2026-11.md`, `doc/history/2026-12.md` | owner decisions, delivered batches | each |
| `CLAUDE.md`, `AGENTS.md` | the Structure sections: the new capability folders | 2, 3 |
| `README.md` | status line | 7 |
| `doc/implementation_notes/planned/mlxf_milestone1.md` | Progress | each |
| `doc/implementation_notes/planned/mlxf_scientific_examples.md` | its Progress: example 1 delivered here | 5b, 7 |

SIMPLE (`~/src/SIMPLE`) is outside this table: the runs read it and export it into scratch, never edit it.
Decision 19's suite touched `src/main/commanders/test/simple_polar_matching_bench.f90`,
`src/main/commanders/test/simple_commanders_test_highlevel_matchbench.f90`,
`src/main/ui/simple_test/simple_test_ui_highlevel.f90`, `src/utils/filter/simple_estimate_ssnr.f90` (one name
made public) and `doc/policies/test_environment_policy.md`, before launch.
| `doc/implementation_notes/completed/mlxf_milestone1.md`, `..._report.md` | the plan, moved; the report | 7 |

## 9. After the hold (roadmap, not phases)

Hans rules the order at the hold (design decisions 32 and 38). The next plan, milestone 2, is
`doc/implementation_notes/planned/mlxf_scientific_examples.md`, converted to plan form at the hold. Its
examples 2 and 3 take the first items below; the rest become plans of their own, written from SIMPLE's
code at a new pin:

- **the master's assembly** (example 2): the nonuniform filter bank and its local composition, and a PCG
  solve with an FFT operator and a spectral preconditioner (37 % of refine3D in the BENCH run of design
  decision 28);
- **Fourier projection and its adjoint** (example 3): reprojection by gather, gridding by scatter-add,
  the n-dimensional FFTs and the gather and scatter operations they need (design decisions 22 and 33);
- **the continuous shift search** that follows the shift maps (decision 15 left it out);
- **n-dimensional FFTs of particle stacks** (design decisions 21 and 23; SIMPLE uses single-threaded
  `FFTW_ESTIMATE` plans in an OpenMP loop, per the design plan's Phase 0; the FFTW comparator plans with
  `FFTW_MEASURE`, decision 22) and **Metal kernels** (design
  decision 18), where a measured bottleneck asks for them;
- **packaging for consumers**: a CMake package config `mlxf::mlxf` with a compiler-version check, a
  consumer project and `scripts/check_install.sh` (the design plan's Phase 5);
- **SIMPLE's integration plan**, if the verdict is go or lead and Hans rules it.

## Progress

(One entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was
met, log paths, decisions taken under delegation, and what it means in short.)

### Phase 1, the follow-ups: 2026-11-22 (interactive, before launch) - complete

Session in the Cowork sandbox (Linux, Python 3.10, no gfortran, CMake or MLX), on `0d3537b` with the
uncommitted `findpkg` change and the split of the design plan. Rulings of decisions 3 to 7 by Hans the same
day ("I agree"). The Python rules and the registry check were run here; the Fortran was not compiled.

Files changed: `src/core/runtime/mlxf_error_tester.f90`, `src/test/mlxf_test_registry.f90`,
`scripts/check_rules.py`, `scripts/check_test_registry.py`, `scripts/check_tree.sh`, `test/CMakeLists.txt`
(comment only), `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md`,
`doc/how2s/how2set_up_dev.md` (row added to the file table first), `doc/compiler_issues/README.md` (new),
`doc/architecture_principles.md`, the skills `mlxf-modern-fortran` (`SKILL.md`, `references/testing.md`) and
`mlxf-binding` (one sentence each: the rules' names, the named-only entry), `doc/history/2026-11.md`, this
plan.

- **Step 1, the recovery gate (decision 3): written, not compiled.** `test_recovery` and the new
  `test_recovery_half` call one `recovery_gate(half_batch=)`: the failing evaluation as before, then the
  same graph at `min(256, half)` rows of 4 MiB in the fast gate, or at half the failing batch. The
  assertion text names the rows. The registry's table `NAMED_ONLY` holds `recovery_half`, `run_suite`
  skips it unless `suite=` names it, and `test=list` lists it. `check_test_registry.py` now holds every
  `NAMED_ONLY` name to a row. It fails on a misspelt name and on a table written without its type-spec,
  and the tree passes ("2 areas, 7 sub-suites, 7 tester entries, 1 guard groups of 8 members agree").
- **Step 2, `ctorexpr` and the narrowed `ctorcall` (decision 7): met here.**
  - Run on the tree before any other edit of the phase: no finding. Only one constructor in the tree holds
    handles (`[c, d]`, `mlxf_array_tester.f90`), and it is bare.
  - Planted file (a copy is `plant_ctor.f90` in the session's outputs): 14 violations fail. They are
    decision 7's five forms; `[exp(a), b]` (the leak plant of the design plan's Phase 1); `[mlx_from(x), b]`
    (`ctorcall`); `[.not.a, b]`; a comment line inside a continuation; same-file functions with a handle
    result (`result(r)` and the function-name forms); an implied-do over an operator result; `(/ a*2.0, b
    /)`; and a nested `[[a*2.0], b]`.
  - Allowed forms that pass, 13: `[a, b]`, `[v(1), v(2)]`, `[(v(i), i = 1, n)]`, `[w%r, a]`, `[a%ndim(), 1]`,
    `[v(1)%ndim(), 1]`, `[storage_size(a), 1]`, `[size(v), 1]`, `[real(i), ...]`,
    `[(max(real(i), 2.0), i = 1, 3)]`, `[exp(x(1)), ...]` on reals, `[1.e5, ...]`, `[mlx_array :: a, b]`.
  - The committed checker on the same plant: it caught only `exp(a)` and `mlx_from(x)`, and it flagged the
    real `[exp(x(1)), ...]`.
  - Found on the way and fixed: `logical_lines` ended a statement at a blank, comment-only or `#` line
    inside a continuation. It is shared by every rule, and the tree passes before and after the fix.
- **Step 3, `doc/compiler_issues/README.md` (decision 9): written. The outputs are the reproducers'
  recorded ones; not re-run, as there is no gfortran here.**
  - The README holds the four report texts, and for each the GCC reports the mailing-list archives point to
    (Bugzilla itself was not reachable). Issue 1 matches PR 57696. Issue 4 may be fixed by PR 110626's
    August 2026 commit. Issues 2 and 3 have related reports (PR 37336, 90068, 121472, 121475, 128856) to
    read before filing.
  - Exit item open: the run loop at the top of the README, run on the Mac, gives the outputs to compare.
- **Step 4 (decision 4): met.** The policy's unsupported use 6 records the ruling with its reason. The
  paragraph after the list names both rules.
- **Independent review** (read-only; the Fortran checked by reading). No P1. Fixed from it:
  - the `.not.a` hole;
  - the continuation fix above;
  - same-file handle functions;
  - the getter after a subscript, and more inquiry intrinsics;
  - the unparsed-table check;
  - the assertion text on a GPU whose maximum buffer is under 2 GiB;
  - the policy's and the skills' sentences on testers and on the rules.

  Left as documented limits of a reading check: components declared in another file, and functions defined
  in another file.
- **Exit items open, for the Mac:**
  - `./compile_debug.sh` and `./compile_clean.sh` from scratch with zero warnings, and the fast gate (budget
    3);
  - `build/bin/mlxf_test_exec test=unit_core` and its time, beside the design plan's 7.8 s;
  - `build/bin/mlxf_test_exec test=unit_core suite=recovery_half` on both devices;
  - `build/bin/mlxf_test_exec test=list`, which shows the named-only sub-suite;
  - the compiler-issues loop;
  - the leak gate (in `unit_array`, unchanged).
- **What it means, in short.** The fast gate keeps the recovery claim at a fixed cost instead of 65 GB per
  device. The leak form the policy called unchecked (`[a*2.0, b]`) is checked, along with its variants, and
  the generics Phase 2 makes public no longer trip `ctorcall`. The four compiler reports are written and
  pointed at existing GCC reports. Phase 1 is done once the Mac build confirms the Fortran.


**Mac exit validation, 2026-11-22.** On `28622018de6560002ec1b0a9b8b0a3166f42b7fb`,
Apple M3 Pro (18 GiB), GNU Fortran 16.2.0, mlx-c 0.8.0 / MLX 0.32.4:
`./compile_debug.sh` and `./compile_clean.sh` rebuilt from scratch with
`MLXF_WERROR=ON`; zero warnings and all three fast entries passed (Debug 2.58 s,
Release 2.19 s wall time). `CMAKE_INSTALL_NAME_TOOL=/usr/bin/install_name_tool`
avoids PATH selecting Anaconda's cctools and its install-time signature warning.
Neither previously uncompiled tester needed a source correction.

`test=unit_core`: 68 assertions, **0.93 s elapsed** (Debug, standalone), beside the
earlier **7.8 s on the M2 Ultra**; these are different machines, not a speedup
measurement. `test=unit_core suite=recovery_half`: 12 assertions passed across CPU
and GPU (1.56 s suite time), failing at 2558 rows and recovering at 1279 rows of
4 MiB. `test=list` lists `recovery_half` separately as named-only. The unchanged
`unit_array` exact leak gate passed in both builds.

The five decision-7 plants were rejected; all six allowed forms, including
`[real(i),1]` and `[(max(i,2),i=1,n)]`, passed; `ctorcall` still rejects
`[mlx_from(x),b]`. Both full static gates passed. All four README compiler
reproducers compiled with `gfortran-16 -std=f2018 -Wall` without warnings and ran
in a temporary directory: assignment counts 1/0/0/0/1, constructor finalization
counts 2/0/2, scalar-to-array assignment/finalization 1/1 and 3/0, self-assignment
id 0. These match the quoted defects. gfortran-13 is not installed. All Phase 1
exit items above are now closed. No compiler-defect assertion was added.


**Validation logs:** `/Users/elmlundho/for_claude/mlxf-review-2026-11-22/prior-phases-1-3/mlxf-p1-{debug,release,core,half,list,probes}.log`
(the brace notation names six files); the originals are also in `/private/tmp/`. The README loop's
four outputs are in `mlxf-p1-probes.log`. **What it means, in short:** the previously uncompiled
Phase 1 changes now meet their Mac exits; this records correctness and gate cost, not performance
against the M2 Ultra.

### Phase 2, the operations: 2026-11-22 - complete

**Machine and base:** Apple M3 Pro, 18 GiB, macOS 26.7.3; GNU Fortran 16.2.0,
CMake 4.4.3, mlx-c 0.8.0 / MLX 0.32.4. Base `28622018de6560002ec1b0a9b8b0a3166f42b7fb`,
branch `main`, with the owner's existing documentation edits preserved. This is the interactive
bring-up of decision 20, not a timed benchmark run.

**Files changed:** `src/core/ops/` (parent, elementwise/shape/reduce submodules, tester and `ops.inf`),
`src/core/linalg/` and `src/core/fft/` (each parent, tester and `.inf`);
`src/core/array/mlxf_array.f90`, `mlxf_array_elementwise.f90`, `mlxf_array_operations.f90`,
`mlxf_array_evaluation.f90`, `mlxf_array_tester.f90`; `src/core/mlxf.f90`,
`src/defs/mlxf_defs.f90`, `src/test/mlxf_test_registry.f90`, `test/CMakeLists.txt`,
`scripts/check_rules.py`, `.github/skills/mlxf-binding/SKILL.md`, and the operation and test-budget
sections of the binding and test policies. This Progress entry records delivery; the capability
maps and history are updated with Phase 3 below.

**Outside the original file table:** `src/core/array/mlxf_array_operations.f90` was added before
it had a row, to keep signature-class helpers in the array family rather than duplicate handle
ownership in capability modules. Claude subsequently added its row. The existing
`mlxf_array_evaluation.f90` was also edited to share the checked vector builder with concatenation.


Implemented exactly decisions 8 and 16's operation names: arithmetic `+ - * /`, unary minus,
comparisons and boolean operators; `merge`, `max`, `exp`, `sqrt`, `real`, `aimag`, `cmplx`, `conjg`,
`mlx_astype`; `reshape`, `transpose`, `mlx_permute`, `mlx_concatenate`, `mlx_slice`,
`mlx_take_along_dim`; `sum`, `minval`, `minloc`, `mlx_cumsum`, `mlx_logsumexp`; `mlx_zeros`,
`mlx_arange`; `matmul`; `mlx_fft`, `mlx_ifft`, `mlx_fft2`, `mlx_ifft2`, `mlx_rfft`, `mlx_irfft`.
The array family owns one helper per generated C signature class; multi-option records live in defs.
The binding skill lists those helpers. The ops parent has elementwise, shape and reduction submodules;
linalg and fft are separate capability modules in the single library target. No sibling operation was added.

Named two-device checks cover column-major/strided reshape, leading-dimension broadcasting, permutation
order, positive/negative/empty inclusive slices, one-based gather and first-tie int32 minloc, weak real64
scalars, independent real/complex batched matmul, FFT sign, all three normalizations, odd/even real
transforms and explicit padding. CPU float64 uses the frozen bounds. Oracles are plain double Fortran
and explicit DFTs. Initial FFT tests exposed that the C API does not infer lengths from -1; omitted
lengths are now resolved before the call. Release warnings exposed impure metadata getters in logical
expressions; these are now evaluated before the expression. No bound changed.

Final clean `./compile_debug.sh` and `./compile_clean.sh`, both with `MLXF_WERROR=ON` and the system
install-name tool: zero compiler warnings, static gates passed, all **6** fast entries passed (7.25 s
Debug; 6.54 s Release). Explicit Release area runs: ops **339**, linalg **32**, FFT **53** assertions,
all passing on CPU and GPU. `unit_array` now has **100** assertions, including three additional evaluated
10,000-iteration loops per device; active memory, live handles and stale releases return exactly.
A scratch source copy with budget **5** failed CMake with "6 CTest entries do not match the budget of 5".
The budget at the Phase 2 exit was **6**; Phase 3 raises it to **7**. Policy sections and binding skill updated; all touched Fortran files formatted.
The static gate warns only that the new sources are untracked, as expected under the no-commit instruction.

**Final semantic review during Phase 3:** `real(a)` must return default real (float32), including
integer and float64 inputs. A regression test first failed three assertions (CPU integer/float64,
GPU integer); the wrapper now casts noncomplex inputs to float32 and extracts the component of
complex64 inputs. Additional CPU float64 arithmetic, reduction and scan checks, and fractional
matmul fixtures, exercise nonbinary values against independent double-precision expectations.
The final ops count is **349**, linalg **32**, FFT **53**, passing on both devices in both final
builds. No numerical bound was relaxed.

**Logs:** under `/Users/elmlundho/for_claude/mlxf-review-2026-11-22/prior-phases-1-3/`, `mlxf-p2-debug-final.log`,
`mlxf-p2-release-final.log`, `mlxf-p2-release-areas.log`, `mlxf-p2-array.log` and
`mlxf-p2-budget5.log`; the intended failing and passing conversion regression is recorded in
`mlxf-real-before.log` and `mlxf-real-after.log`. The final Phase 3 gates below include the correction.
The originals are in `/private/tmp/`; `index.txt` in the log directory identifies the final results.
These earlier logs were copied out before the review rebuilds so they remain available.

**What it means, in short:** decisions 8 and 16's operations meet the Fortran conventions,
independent numerical checks and exact lifetime gates on the CPU and GPU. These are binding
results, not evidence of a polar-pipeline speedup.

### Phase 3, compilation: 2026-11-22 - complete under the owner's callback ruling

**Machine and base:** Apple M3 Pro, 18 GiB, macOS 26.7.3; GNU Fortran 16.2.0,
CMake 4.4.3, mlx-c 0.8.0 / MLX 0.32.4. Base `28622018de6560002ec1b0a9b8b0a3166f42b7fb`,
branch `main`, with Phase 2 and the owner's documentation edits in the working tree.

**Compiler finding and ruling:** the allocatable array function-result callback encountered a
new gfortran 16.2 defect. The standalone diagnostic
`python3 scripts/probe_callback_array_result.py` reduces it to a finalizable derived type and a
procedure-pointer function result, with no MLX dependency: AddressSanitizer reports a
heap-use-after-free in finalization (return code -6). A checked subroutine producing an allocatable
`intent(out)` array passes the same consumer and teardown (return code 0). Work stopped for the
required ruling; Hans answered **"Use the checked callback subroutine (recommended)"**.
The public callback is therefore `subroutine callback(inputs, outputs, status)`, with an input
array, allocatable output array and integer output status. The callback uses checked operations
and reports errors through status. No decision or phase text was edited and no gate was waived.
The probe is a diagnostic, not a compiler-defect assertion in CTest; no upstream report was sent.

**Implementation:** `mlx_function` owns a C closure with a procedure-pointer payload and a
`bind(c)` trampoline. It supports construction, defined assignment, checked `apply`, idempotent
`kill`, finalization and `trace_count`; `mlx_compile(f, shapeless)` retains the callback through
the C closure. The existing handle registry owns function handles; no new global ledger or
change to the registry/lifetime implementation was needed. Checked vector import/export stays
in the array family. The trampoline returns a C status on checked callback failure or missing
outputs; a public call with `status=` recovers without publishing outputs. User callbacks must
also follow the documented checked-call contract. Static constructor checks now recognize
`mlx_function`: a variable-only `[f,g]` passes and the planted `[(f),g]` is rejected.

**Files changed:** `src/core/compile/` (`mlxf_compile.f90`, `mlxf_compile_tester.f90`,
`compile.inf`), `src/core/array/mlxf_array_closure.f90`, the array parent and tester,
`src/core/mlxf.f90`, `src/test/mlxf_test_registry.f90`, `test/CMakeLists.txt`,
`scripts/check_rules.py`, `scripts/probe_callback_array_result.py`,
`.github/skills/mlxf-binding/SKILL.md`, and the compilation and budget sections of the binding
and test policies. The final Phase 2 semantic review also touched `mlxf_ops_elementwise.f90`,
`mlxf_ops_tester.f90` and `mlxf_linalg_tester.f90`. Capability maps in `src/core/core.inf` and the
Structure sections of `CLAUDE.md` and `AGENTS.md` now name ops, linalg, fft and compile. The public
export list has spaces after commas. `doc/collaboration/apple_questions.md` and
`doc/history/2026-11.md` record the findings and delivery; this plan is edited only in Progress.

**Outside the original file table:** `src/core/array/mlxf_array_closure.f90` was added to keep
closure-vector ownership and adoption inside the array family; Claude subsequently added its
row. The standalone `scripts/probe_callback_array_result.py` was announced before creation to
make the new compiler finding reproducible, with the approved subroutine as its control. It
uses only the Python standard library at the repository's Python 3.7 floor. The log directory
is an ignored build artifact, not a new source or test target.

**Exits and verification:**

- Clean `./compile_debug.sh` and `./compile_clean.sh`, with
  `MLXF_CMAKE_ARGS='-DMLXF_WERROR=ON -DCMAKE_INSTALL_NAME_TOOL=/usr/bin/install_name_tool'`
  and `CMAKE_BUILD_PARALLEL_LEVEL=12`, pass all **7/7** fast entries: **8.21 s Debug**,
  **7.39 s Release**, zero compiler warnings. `check_tree.sh` passes. Its only notices are the
  untracked new sources, which remain unstaged under the no-commit instruction. All touched
  Fortran files passed through both formatting scripts.
- `unit_compile`: **54 assertions** across CPU and GPU in each build. The compiled and uncompiled
  two-output fixture is byte-identical and matches independent expected values. Shapeless calls
  at shapes **(4,7)** and **(4,3)** trace **once on CPU and once on GPU**. Default shaped
  compilation and copied-handle lifetime after the original is killed also pass.
- Checked errors in direct and compiled callbacks return a nonzero status with an error message,
  publish no outputs, and leave a subsequent valid compiled graph usable. Empty handles and
  unallocated output arrays also return errors.
- `unit_array`: **112 assertions**, including the three operation-module loops and a compiled-call
  loop of **10,000 evaluated iterations per device**. Active bytes, live handles and stale releases
  return exactly after the loops and after full closure teardown. The handle-model implementation
  and the exact gate were not relaxed.
- Explicit Release area runs pass ops **349**, linalg **32**, FFT **53**, compile **54** assertions,
  on both devices. `test=list` lists six areas and the existing eight-member object-contract group;
  the CTest budget is **7**. `recovery_half` remains named-only. Generated coverage remains
  **673 + 7 = 680** declarations; no generator or C ABI change was needed.

**Logs:** `/Users/elmlundho/for_claude/mlxf-review-2026-11-22/prior-phases-1-3/index.txt` indexes the results. Phase 3's logs there are
`mlxf-p3-debug-final.log`, `mlxf-p3-release-final.log`, `mlxf-p3-debug-compile-final.log`,
`mlxf-p3-release-areas.log`, `mlxf-p3-array.log`, `mlxf-p3-list.log` and
`mlxf-p3-reproducer.log`. `mlxf-final-static.log` records the final tree check. Originals are
also in `/private/tmp/`; the copies above survive clean builds.

**Apple question 19:** the C FFT interface requires a positive transform length, whereas Python
accepts `n=None` and infers it. The original `-1` assumption was our wrapper error, not an MLX
failure. The Python `irfft` documentation also states a default-length formula different from
the C++ implementation. The numbered question cites both and asks for clarification; meanwhile
Fortran resolves forward lengths from the input extent and inverse-real lengths as
`2*(extent-1)`. It records a question for discussion, not an outbound message.

**What it means, in short:** Phases 1 to 3 are ready for the maintainer's review and commit,
including usable checked Fortran callbacks and compiled graphs on both devices. Work stops
here. Phase 4 awaits Phase 0's measured polar dimensions and the new SIMPLE benchmark pin;
run `mlxf_m1` starts at Phase 0 on the commit that contains this work. No commit was made,
no file in SIMPLE was edited, and no Linux/BOX or M2/M5 benchmark result is claimed.

*Review note (Claude, 2026-11-22).* The ruling is recorded as decision 21. The probe now lives with the other
reproducers as `doc/compiler_issues/gfortran_finalize_allocatable_array_result.f90`. It is one Fortran
program with the control first, plus issue 5 of the README. `scripts/probe_callback_array_result.py` was
removed, and the policy, the binding skill and the Apple notes point at the new file. An independent code
review found no P1. It found two P2s to fix before commit: empty-handle guards in `mlx_function`'s
lifetime bindings, and a concatenate test that cannot tell the axis mapping apart. It also listed P3s
(history, 2026-11-22).


**Review fixes and revalidation, 2026-11-22 (Codex).** On the same Apple M3 Pro, 18 GiB,
macOS 26.7.3, GNU Fortran 16.2.0, CMake 4.4.3, mlx-c 0.8.0 / MLX 0.32.4, base
`28622018de6560002ec1b0a9b8b0a3166f42b7fb`. Claude's updated decision 21, compiler-issue files,
history and review note were read first and preserved. No file was added to the repository in this round.

- **Required P2 fixes:** function assignment guards only when either context is associated; `kill`
  guards only an associated context, and finalization delegates to it. Empty lifetime operations
  never enter or initialize the runtime. Both bindings are in `ENTRY_IF_LIVE`. A two-thread test
  copies, kills and finalizes empty local functions: it stopped with status 86 on the previous
  implementation and passes after the fix. Static plants removing either conditional guard are rejected.
  Rank-three concatenation now checks dimensions 1 and 3 on shape `(3,4,2)`, with exact output shape
  and bytes; independently planted wrong mappings are rejected on both dimensions.
- **P3 checks and contracts:** a batched `(3,4,5)` complex FFT2 over dimensions 1 and 2 matches separate
  double DFTs for each batch. Logsumexp uses `1e-5 * max(1, abs(expected_logsumexp))`, in log units;
  float64 `sqrt` passes `1e-12 * max(1, abs(sqrt(x)))`, so no float32 exception was needed. `minloc`
  chooses the first tied minimum on 4097-element contiguous and strided axes on CPU and GPU.
  The compiled fixture uses decimal inputs `i/10`; compiled/uncompiled bytes and independent expected
  values still agree, with one shapeless trace per device over `(4,7)` and `(4,3)`.
- `function_apply` and `invoke_callback` are recursive. Nested checked apply, both direct and during
  compiled tracing, passes on both devices. The two FFT signature helpers validate `norm` against
  the three `MLX_FFT_NORMS` members. Two added members of the existing guard group confirm the
  Fortran normalization diagnostic; mlx-c already rejected these values before the explicit check.
  Integer arrays with real32/real64 scalars give float32, with exact values. A gather index of 0 is
  tested to wrap to the last element. The policy records this and the `x + i*y` limitation of `cmplx`
  for non-finite imaginary parts, with host complex construction as the preserving route.
- **Compiler issue 5:** the merged Fortran reproducer was built with exactly the header's
  `gfortran-16 -std=f2018 -Wall -O0 -g -fsanitize=address` and run with `ASAN_OPTIONS=symbolize=0`.
  Compilation returned 0 with no warnings. It printed the subroutine control's PASS, then reported
  an AddressSanitizer heap-use-after-free, WRITE of size 4, and SIGABRT (subprocess return -6), before
  the function PASS line. The header and README issue 5 now record this observed merged-program run.
- **Files changed:** `src/core/compile/mlxf_compile.f90` and its tester;
  `src/core/ops/mlxf_ops_tester.f90`, `src/core/fft/mlxf_fft_tester.f90`,
  `src/core/array/mlxf_array_operations.f90`, `src/test/mlxf_test_registry.f90`,
  `scripts/check_rules.py`, `test/CMakeLists.txt`, the binding/test policies,
  `doc/compiler_issues/gfortran_finalize_allocatable_array_result.f90` and its README, this Progress
  entry and `doc/history/2026-11.md`. The array lifetime/registry implementation is unchanged.
- **Final exits:** clean Debug and Release with `MLXF_WERROR=ON` and the system install-name tool:
  **7/7 gates**, **8.51 s Debug**, **8.08 s Release**, **zero compiler warnings**. Verbose results
  confirm both devices: ops **371**, FFT **57**, compile **63**, linalg **32** checks. The exact array
  lifetime gate remains **112** checks, including 10,000-iteration loops; all **10** object-contract
  members stop with the hard-error status. Budget remains **7**. `test=list`, the static gate and
  both formatting scripts pass. The static gate's only notice is the 13 deliberately untracked
  sources; nothing was staged. No numerical bound was widened.

**Review logs:** `/Users/elmlundho/for_claude/mlxf-review-2026-11-22/index.txt` indexes
`debug-clean.log`, `release-clean.log`, `debug-areas.log`, `release-tests.log`, both gate timing
files, `static.log`, `list.log`, `compiler-issue5.log` and the negative-control logs. All are outside
`build/`; earlier phase logs were copied into `prior-phases-1-3/` before rebuilding, and their paths
above now point to those copies.

**What it means, in short:** both required review fixes and every listed P3 item are closed by
implementation, tests or the requested policy clarification. Phases 1 to 3 are ready for review and
commit again. No commit or SIMPLE edit was made; Phase 4 remains untouched and still awaits Phase 0.

### Phase 0, the baseline: 2026-11-22 (run `mlxf_m1`, unattended) - complete

Machine FWM-S116118. Base `27d80aa2183cf3590c68c2ad9569f740b25b68b0`: it and `5944901` add only
`mlxf_m1_codex.md` on top of `0a1eec2`, the maintainer's commit of Phases 1 to 3 (ruling R1). The working tree
was clean at the start (`git --no-optional-locks status --short` empty). SIMPLE pin
`3a595f42f928a366744094a28b62aeb6020099e4` (parent `7ec7e2972`). Paths below are under
`/Users/elmlundho/agent_work/arun/mlxf_m1/scratch`. No source file was edited. Files changed: this entry and
`doc/history/2026-11.md`.

Rulings applied here for the first time (R1):
- the plan's `compile_debug.sh` and `compile_clean.sh` were carried out as hand-configured trees with the
  same options (`-DCMAKE_BUILD_TYPE=<Debug|Release> -DBUILD_TESTS=ON -DFORTLS=OFF -DMLXF_WERROR=ON`, the
  install prefix the tree itself; `build_base.sh`);
- decision 6's "no edit reaches the repository while a phase runs" is narrowed to this run's file table:
  Hans commits and pushes Codex's parallel work (`mlxf_m1_codex.md`, files outside the table) while the run
  runs. This copy never sees those commits, and the run's own clean-tree check is unchanged;
- decision 5: no BENCH output at or after `7ec7e2972` is named, so s and f stay unmeasured (step 6);
- the PorF and exp_gate profiles are not on this Mac (step 7).

- **Step 1, the machine and the base: met.**
  - Apple M2 Ultra: 16 performance and 8 efficiency cores (`hw.ncpu` 24), 76-core GPU (Metal 4,
    `applegpu_g14d`), 192 GB (206,158,430,208 B).
  - macOS 26.7.3 (25G342), Command Line Tools 27.0 only (no Xcode).
  - GNU Fortran 16.2.0 (Homebrew GCC 16.2.0), CMake 4.2.1, Apple clang 21.0.0, `python3` 3.14.6 (Homebrew;
    the build's `MLXF_PYTHON3`), `/usr/bin/python3` 3.9.6.
  - `brew list --versions`: cmake 4.2.1, fftw 3.3.10_2, gcc 16.2.0, mlx 0.32.4, mlx-c 0.8.0. The same at the
    end; nothing was installed.
  - `otool -L` of `libmlxc.dylib`: the shared `libmlx.dylib`, Metal, Foundation, QuartzCore, Accelerate,
    libc++ and libSystem.
  - Load at the start 2.94 (1 min). Endpoint agents (Defender, Cylance, SEHA, Jamf) take 1 to 2 cores at
    rest; Druva inSync backups and Spotlight come and go (step 4).
- **Step 2, the base in Debug and Release: met.** `keep/base_src` (`git archive HEAD`), trees
  `keep/base_debug` and `keep/base_release` (`build_base.sh`, `build_both_base.sh`; logs
  `logs/base_{debug,release}.log`).
  - Configure, build, fast gate and install all exit 0. `check_tree: passed`. **Zero compiler warnings**: the
    only "warning" in either log is the configuration line "Warnings as errors: ON".
  - Generator coverage: 673 generated + 7 skipped = 680.
  - Fast gate, 7 of 7 entries, per-entry seconds (`<tree>/test_runs/ctest_fast.log.timing.txt`), *measured*:

    | entry | Debug | Release |
    | --- | --- | --- |
    | `unit_array` | 11.80 | 10.76 |
    | `unit_linalg` | 1.26 | 0.33 |
    | `object_contracts` | 1.18 | 1.09 |
    | `unit_compile` | 1.15 | 1.03 |
    | `unit_ops` | 0.88 | 0.72 |
    | `unit_core` | 0.60 | 0.47 |
    | `unit_fft` | 0.46 | 0.34 |
    | total real time (budget 60 s) | 11.8 | 10.8 |

  - **`unit_core`'s recovery share**: standalone `unit_core` takes 0.21 s (Release) and 0.47 s (Debug), 69
    assertions. Its `error` sub-suite, which holds decision 3's fast recovery gate, takes 0.13 s in both: the
    failing evaluation at 30,966 rows of 4 MiB, then recovery at 256 rows (`logs/base_*_unit_core.log`). The
    design plan's figure was 7.5 s of `unit_core`'s 7.8 s on this machine.
  - **The GPU from the run's session**: `unit_core` reports "GPU devices: 1" (Apple M2 Ultra,
    `applegpu_g14d`); `max_buffer_length` 129,879,801,856 B.
  - **`recovery_half`** (`mlxf_test_exec test=unit_core suite=recovery_half`): passes on both devices in
    Release and Debug, 12 checks each in 7.34 s. It fails at 30,966 rows and recovers at 15,483 rows of 4 MiB
    (64.9 GB); peak footprint 64,988,821,440 B (`logs/base_{release,debug}_recovery_half.log`).
- **Step 3, SIMPLE at the pin: met.** `git archive 3a595f42f` into `keep/simple_src`, configured by hand
  (Release, `-DBUILD_TESTS=ON -DFORTLS=OFF`), built and installed into `keep/simple_release`
  (`build_simple.sh`, `logs/simple_build.log`). Exit 0, zero compiler warnings (the one hit is the installed
  `fix_warnings.py`).
  - Links: Homebrew FFTW 3.3.10 (`libfftw3f.3`, `libfftw3.3`, `libfftw3f_threads.3`) and SIMPLE's bundled
    static OpenBLAS 0.3.34. That OpenBLAS was fetched by its CMake into the export's `.deps`, with
    `USE_OPENMP=1`, `NUM_THREADS=128` and core `VORTEX`. Also libgomp and libgfortran of GCC 16.2.
  - Fast gate `run_tests.sh --build-dir keep/simple_release`: 15 of 15 passed, 13.8 s, no failure
    (`logs/simple_fastgate.log`).
  - `suite=list`: `per_pair, replica, blocked, states_inner, matrix, matrix_t, block_prod, per_pair_cc, check,
    identity, fills, neigh, shiftmap`. All five required suites are present (`logs/simple_bench_list.log`).
- **How the SIMPLE runs were made** (steps 4, 5 and 7). Scripts: `run_simple_case.sh`, `run_simple_all.sh`
  and `run_simple_repeats.sh`. Rows: `keep/simple_baseline/<case>/` (TSVs, `run.log`, `uptime.txt`,
  `sampler.txt`, `cmd.txt`) and `keep/simple_baseline/summary.txt`.
  - Every invocation used `OPENBLAS_NUM_THREADS=1` and `MLX_ENABLE_TF32=0`, one at a time, with nothing else of
    the run's own running.
  - Before each run the script waited until the 1-minute load was at most 4 (and, from the repeats on, until
    other processes took at most 250 %). During the run it sampled every 5 s the CPU of every other process
    (the first case every 30 s).
  - A run in which other processes exceeded 400 % of a core was repeated. Seven runs were flagged and
    repeated, and every repeated case ended clean:
    - `block_prod` 2,500 x 4 at `nthr=24`: run 1 twice, run 2 once;
    - `block_prod` 1,000 x 4 at `nthr=16`: twice;
    - `block_prod` 2,500 x 1 at `nthr=16`: once;
    - `neigh` run 1: once;
    - `check` (see step 5).
  - The flags were single 5-s samples of Druva inSync (up to 214 %), Spotlight (`corespotlightd`, `mds`),
    `spindump`, `log` and the endpoint agents. The flagged runs are kept as `<case>.prev_<time>`.
  - Two maxima were first misread when per-process lines entered the sampler log. They were recomputed (418
    and 453 %) and those runs repeated (journal).
  - Summaries: `keep/summarize_baseline.py` gives `keep/simple_baseline/baseline_summary.txt`;
    `keep/summarize_check.py` gives `keep/simple_baseline/check_summary.txt`.
- **Step 4, `block_prod`: met.** `suite=block_prod nspace=<1000|2500> nstates=<1|4> nptcls=2000`.
  - Runs: `nthr=24` twice (all of run 1 before run 2), then `nthr=16` once.
  - Each invocation times its team, half of it and one thread, best of 3 after a warm-up. The full team sweeps
    B in {4, 8, 16} at R = 32 (`PFTC_BLOCK_NR`, fixed in the kernel); the other teams time the best B.
  - The fastest B is 16 in every run (B 8: 1.54 to 1.57e6 pairs/s at 24 threads; B 4: 0.90 to 0.92e6).
  - Pairs per second, run 1 / run 2 (*measured*). The full-team spread is (max - min) / min:

    | case (directions x states) | 24 threads | spread | 16 (P-cores) | 12 (from `nthr=24`) | 1 thread, 200 particles |
    | --- | --- | --- | --- | --- | --- |
    | 1,000 x 1 | 2.297e6 / 2.300e6 | 0.14 % | 2.083e6 | 1.546e6 / 1.535e6 | 1.450e5 / 1.352e5 |
    | 1,000 x 4 | 2.306e6 / 2.321e6 | 0.67 % | 2.119e6 | 1.557e6 / 1.564e6 | 1.456e5 / 1.361e5 |
    | 2,500 x 1 | 2.309e6 / 2.316e6 | 0.30 % | 2.103e6 | 1.562e6 / 1.557e6 | 1.415e5 / 1.417e5 |
    | 2,500 x 4 (the verdict's case) | 2.299e6 / 2.295e6 | 0.21 % | 2.103e6 | 1.566e6 / 1.549e6 | 1.438e5 / 1.404e5 |

  - Thread-µs per pair: 10.34 to 10.46 at 24 threads, 7.55 to 7.68 at 16, 6.9 to 7.4 at one thread. The
    one-thread rows run 200 particles and are not compared with the all-core workload.
  - Every full-team spread is at most 0.67 %, so the ≤ 5 % exit holds without the repeat rule. The flagged
    runs above were repeated for the load rule, not for spread.
  - At the verdict's case, 2,500 x 4: the 24-thread wall is 8.698 / 8.716 s for 2.0e7 pairs.
  - The 16 performance cores give 0.91 to 0.92 of the 24-core rate.
- **The polar dimensions** (Phase 4's generator and Phase 5's benchmark read `keep/polar_case.txt`, one
  block per case, each value with its source TSV and line):
  - all four dense cases: pftsz 182, nrots 364, kfrom 2, kto 62, nk 61;
  - references nrefs = nspace x nstates (1,000, 4,000, 2,500, 10,000);
  - 2,000 particles: the even half is particle i with `mod(i,2) == 1`, 1,000 per half
    (`simple_polar_matching_bench.f90`, `new`), so B = 16 blocks never mix halves;
  - dtypes: complex64 memos (`ft_ref`, `ft_ref2` (pftsz+1, nk, nrefs, half) and the block kernel's bin-major
    `ft_ref_bins` (2nk, nrefs, pftsz+1, half)), real64 shell weights (`sigma2_wk8`).
  - Reference residency (*derived* from the shapes, not measured): `ft_ref` with `ft_ref2` take 0.357,
    1.429, 0.893 and 3.572 GB, and `ft_ref_bins` the same again. That is 0.714, 2.858, 1.786 and 7.144 GB for
    1,000 x 1, 1,000 x 4, 2,500 x 1 and 2,500 x 4. The benchmark's `memo_GB` column (references plus one
    particle copy) is 0.714, 1.786, 1.250 and 3.929.
  - The shared-representative cases are in the same file (`neigh_reps_<pgrp>_<nstates>`): pftsz 140,
    nrots 280, k 2 to 81 (nk 80), 252 representatives per state, 1,200 particles (600 per half, B 12 per
    half).
- **Step 5, `check`, `fills`, `neigh`: met.**
  - **`check nthr=24`** (`keep/simple_baseline/check_t24/`; run 1 kept as `check_t24.prev_173755`): six
    cases, nspace {1,000, 2,500} x nstates {1, 2, 4}, rc 0.
    - Both runs were flagged by the load rule. The rerun's identity and tolerance columns are identical to
      the first run's (columns 1 to 14 of both TSVs), so it was not run a third time: no number from `check`
      is a timing.
    - Every layout reproduces its own one-thread rows at 24 threads (0 rows differing). `per_pair`,
      `replica`, `blocked` and `states_inner` equal production's rows byte for byte. `matrix` and `matrix_t`
      differ by at most 4.06e-7 relative, with 0 to 6 minimising rotations differing (6 of 320,000 at
      2,500 x 4).
    - `block_prod` against production's per-pair draws (`polar_block_check.tsv`), in every case:
      - the losses agree within 4.05e-7 relative (bound 1e-6), with 0 invalid mismatches;
      - entries are identical across 24 threads in five repeats and across B 4, 8 and 16 (0 differing);
      - at the argmin (temperature scale 1e25) the rotation differs in 0 to 4 pairs (4 of 320,000 at
        2,500 x 4; allowed 6): `within_tolerance` yes;
      - at a tenth of the temperatures, also within tolerance.
    - **At the particles' own temperatures** the drawn rotation differs in 27 to 104 pairs (104 of 320,000
      at 2,500 x 4), and the TSV says `within_tolerance` no. SIMPLE's own record at the pin expects exactly
      this: `prob_table_matrix_scoring.md` measured 70 of 320,000 (lines 580 to 597). Its ruling R7 (lines
      238 to 245) compares the argmin and the losses, and reports the draw at these temperatures without
      gating it, because the draw multiplies last-bit loss differences by the temperature. So the check
      passes as SIMPLE defines it, and this is not a stop. Phase 4's oracle is the draw on the device's own
      rows (section 6), not cross-route draw identity.
  - **`fills nthr=24`**, defaults (200 directions, nstates 1 and 2, 64 particles): rc 0. Its eight routes
    each run 6 configurations, all with 0 differences in all seven categories: "the fill harness gives
    identical rows, selections and extras in every configuration" (`fills_t24/polar_fill_identity.tsv`,
    96 rows).
  - **`neigh nthr=24`** twice (5,000 directions, c1 and d2, nstates 1 and 2): every one of the 24 check rows
    of the two runs is `within_tolerance` yes and `identical` yes. The best rotation differs in at most 7 of
    604,800 (allowed 12), with losses within 7.1e-7.
    - The representative (`a_reps`), member (`b_members`) and cone (`c_cone`) rows are kept apart in
      `neigh_t24_r{1,2}/polar_neigh_bench.tsv`; per-path tables are in `baseline_summary.txt`.
    - At 24 threads `block_wall` is 0.149 to 0.153 s for 302,400 representative pairs, and 0.300 to 0.310 s
      for 604,800. Block over per-pair wall: 0.60 to 0.63 for representatives, 2.9 to 3.3 for members, 3.5
      to 7.1 for cones. Spread between the runs: at most 3.0 %.
- **Step 6, s and f: unmeasured** (decision 5, ruling R1). No BENCH output at or after `7ec7e2972` is named.
  The end-to-end projection is `1 / (1 - s*f + s*f/g)`, where:
  - s is the fill's share of the run's wall time;
  - f is the scoring share of the fill;
  - g is the GPU-over-CPU scoring ratio of decision 14.

  The design plan's BENCH run (f = 0.23, s = 0.37) predates the production scorer and is not used.
- **Step 7, `shiftmap`: met.** `nthr=24` twice, then `nthr=16` once. Each invocation times its team, half of
  it and one thread (200 particles), best of 3 after a warm-up. The maps are 2,000 particles x 16
  candidates on 2,500 x 4 (10,000 references). `fftw_plans` is `estimate`. All three runs were clean.
  - Maps per second (*measured*):

    | map | 24 threads, run 1 / run 2 | spread | 16 threads | 12 | 1 thread |
    | --- | --- | --- | --- | --- | --- |
    | window | 4.456e4 / 4.439e4 | 0.39 % | 3.801e4 | 2.859e4 / 2.852e4 | 2.720e3 / 2.720e3 |
    | screen | 7.504e3 / 7.537e3 | 0.43 % | 6.425e3 | 4.870e3 / 4.860e3 | 452.2 / 451.9 |

  - Thread-µs per map at 24 threads, run 1 (construct, select, reduce): window 359.3, 22.5 and 152.7 (sum
    538.6); screen 2,003.8, 144.2 and 1,040.2 (sum 3,198.1). At one thread: window 257.4, 14.2, 95.9;
    screen 1,414.5, 95.1, 701.3. The width (reduce) is 33 % of the screen's per-map cost at 24 threads.
  - **Team identity**: "0 maps differ" for both maps in all three invocations (64 particles x 16 candidates,
    one thread against 24, and against 16).
  - The identity files are byte-identical across the three runs: `polar_shiftmap_identity_window.bin`
    sha256 `26628b44...` and `polar_shiftmap_identity_screen.bin` `471ee999...`, 40,960 B each.
  - **The grid** (Phase 5b reads `keep/shiftmap_grid.txt`). Both maps: pftsz 182, nrots 364, kfrom 2,
    kscreen 31, nrefs 10,000, nptcls 2,000, ncand 16.

    | map | nrho | nalpha | norder | rho_max_px | prior_w |
    | --- | --- | --- | --- | --- | --- |
    | window | 4 | 14 | 16 | 4.3548 | 0 |
    | screen | 11 | 35 | 32 | 14.5161 | 2.11151e-2 |

  - **The profiles' per-map costs: not available on the M2 Ultra** (ruling R1).
    `~/for_claude/bench/{PorF,exp_gate}/BENCH` do not exist on this Mac. Other BENCH directories under
    `~/for_claude` (the design plan's BENCH run, a `PorF_refine3D_local_tests` run) are not identified as
    these profiles and were not used.
- **Decisions taken under delegation.**
  - The run directories and the summarisers are named as above.
  - The SIMPLE runs waited for low background CPU, not only for load.
  - `check`'s third repeat was skipped: its outputs other than timings were identical, and none of its
    numbers is a timing.
  - The polar-case file also holds the shared-representative cases and the derived residency of the bin-major
    copy, so that Phase 5 reads both from one place.
- **What it means, in short.** The base builds and gates cleanly on the M2 Ultra in both build types with
  zero warnings. The fast gate takes 11 s, and `unit_core`'s recovery gate is now 0.13 s instead of 7.5 s.
  The half-batch form still passes on both devices at 64.9 GB. SIMPLE's pin builds, passes its gate and has
  every suite. Its production block scorer runs 2.30e6 pairs per second on all 24 cores in every dense
  case, with spreads under 1 %. Its fills are identical across teams, batches and parts, and its shift maps
  are identical across teams. The screen map costs 3.2 ms and the window 0.54 ms per map and thread at the
  full team. These are the CPU side of Phase 5's and 5b's context ratios on this machine. The verdicts use
  Phase 6's baseline on the M5 Ultra.

### Phase 4a, the fixture calibration: 2026-11-22 18:32 EST (run `mlxf_m1`) - frozen

Written at 2026-11-22 18:32:12 EST, before any GPU run of the pipeline. Until this entry, the tester's device
list was the CPU device alone and no GPU branch existed. The CTest entry of area `kernels` did not exist
either, so no gate ran the tester.

- **What was calibrated.** The fixture of section 6, built with fixture seed 1: pftsz 32 (nrots 64), nk 10, 8
  references and 6 particles per half, both halves, temperatures 0, 1, 30 and 1e4. It holds one particle with
  no valid rotation, one seed-bank particle per half, and one mixed-validity particle per half (some rotations
  above -log(1e-10)).
  - The memos come from a double-precision DFT of the ring samples, rounded once to single precision.
  - The ring oracle computes every rotation's distance on the full rings in double precision.
  - The workspace runs formulation A with the canonical tile plan (rt 3, bt 4: partial tiles on both sides),
    on the CPU device.
- **The pair, as measured.** Each value is the same in two runs per build. The Debug and Release values agree
  to ten digits once the fixture's host arithmetic was made build-independent (decision below). Log:
  `/Users/elmlundho/agent_work/arun/mlxf_m1/scratch/keep/phase4/phase4a_calibration_cpu.log`, sha256
  `8b363b22...`.
  - e_cpu = **4.3124235321748868e-7**, *measured* (Debug; Release 4.3124235306e-7). It is the largest error
    of a pair's distances relative to the largest |d| of that pair's valid oracle row, taken over the 96
    pairs.
  - n_cpu = **0** of 96 pairs whose minimising rotation differs from the oracle's, *measured*.
- **Frozen in `src/test/mlxf_test_defs.f90`.** `POLAR_FIXTURE_ERR_CPU = 4.3124235321748868e-07`,
  `POLAR_FIXTURE_ROT_CPU = 0`, `POLAR_ROW_FACTOR = 2` (*guessed*, section 6), `POLAR_FIXTURE_ROT_Q = 1`
  (section 6).
  - **Derived bounds for seed 2, every device and configuration of the fixture:** row error ≤ 8.6248e-7;
    minimising-rotation disagreements ≤ max(2 x 0, 1) = 1 per judged case.
  - The draw on the device's own rows stays within 1e-4 W (`POLAR_DRAW_TOL`, *derived*, section 6).
- **Context (not a gate).** Seed 2 on the CPU device: row error 4.426e-7 and 0 rotations differing, in both
  builds (same log).
- **Definitions fixed with the calibration** (delegation):
  - "max|d|" is per pair: the largest |d| of the pair's valid oracle row, so that the mixed rows (|d| up to
    about 45) do not loosen the bound of ordinary rows (|d| about 2).
  - Validity is compared away from the threshold. An oracle entry within 1e-4 x max|d| of -log(1e-10) may be
    judged differently in float32 and float64.
  - The fixture's single-precision values are computed in double precision and rounded once. Before that,
    `-O3` contracted the CTF's `0.2 + 0.8 x` into a fused multiply-add and `-O0` did not, so the fixture,
    and e_cpu with it, differed between Debug and Release (1.83e-7 against 1.65e-7 on the earlier fixture).
    The rule is in `references/testing.md`.
- **Before freezing,** an independent review compared the code with SIMPLE's `score_block_posterior`,
  `euclid_dists_from_crvec`, `draw_posterior_row` and memos at the pin. It found no defect in the algebra,
  memo conventions, rotation convention or draw. It found four weak tests, which were strengthened, and the
  fixture recalibrated, before this entry:
  - row values were only printed; they are now gated (below);
  - no row had mixed validity; the two mixed particles fill that gap;
  - unchecked statuses could let a test pass on unallocated arrays;
  - the cutoff at 80 was exercised only by chance; a constructed case now gives a rotation before the
    minimum the argument 82, so it must carry no weight.

  Two planted defects now fail: dropping `valid` from the weight mask fails the draw check, and dropping the
  cutoff fails the cutoff assertion (`scratch/logs/p4_plant_{nokeepvalid,nocutoff}.log`).

### Phase 4, the polar pipeline at fixture size: 2026-11-22 (run `mlxf_m1`, unattended) - complete

Machine FWM-S116118 (Phase 0's record). Base `27d80aa2183cf3590c68c2ad9569f740b25b68b0` with Phase 0's two
documentation edits; `git --no-optional-locks status --short` at the start showed only those. Paths below are
under `/Users/elmlundho/agent_work/arun/mlxf_m1/scratch`.

**Files changed.**
- New: `src/test/mlxf_kernel_polar_table.f90`, `_lifecycle.f90`, `_score.f90`, `_tester.f90`, and
  `src/test/mlxf_test_defs.f90`.
- Changed: `src/test/mlxf_test_registry.f90` (area `kernels`, row `polar_table`); `test/CMakeLists.txt`
  (area `kernels`, budget 8, registration comment); `scripts/check_rules.py` (rule `defs`, below);
  `doc/policies/test_environment_policy.md` (budget 8, the kernels area); the skill reference
  `.github/skills/mlxf-modern-fortran/references/testing.md` (one rule); `doc/history/2026-11.md`; this
  plan (the file table and Progress).
- File table, ruling R1 applied for the first time here: the rows `src/test/mlxf_kernel_polar_table_lifecycle.f90`
  and `..._score.f90` (Phases 4, 5, 5b) and `.github/skills/mlxf-modern-fortran/references/testing.md` (each)
  spell out rows the table already held in brace and relative notation, so the fence can read them.
- `doc/policies/test_environment_policy.md` got Phase 4 in its row: the new area and the budget change its
  text, and section 2's rule "plan is history, policy is truth" needs the policy current. It is not a new file.

**What was built.**
- `polar_table`, a test-only workspace written against `mlxf` as a user writes. It holds one half's prepared
  references as one resident handle: tiles (2nk, rt, pftsz+1, ntiles), with rows 1..nk `ft_ref2` and rows
  nk+1..2nk `conj(ft_ref)`, zero-padded. It records their generation, half, shape and ordered global IDs,
  and keeps two slots of plain handle components. There are no allocatable handle components, so no
  defined-assignment trap and no second ownership implementation. Procedures: `new`, `invalidate`,
  idempotent `kill` and `final`, `submit(blk, slot)`, `collect(slot, entries)`, and `score` (submit, then
  collect).
- The specs (decision 39.1) are validated before anything is queued:
  - `polar_table_refs`: pftsz, nk, half, generation, the tile plan rt and bt, IDs and memos;
  - `polar_table_block`: half, generation, reference list, particle IDs, weights, `ctf2`, `xctf`, optional
    banks with `l_bank`, wsq, temperatures, per-pair float32 variates, and a rows flag.
  - The result `polar_table_entries` holds dists, irots and the optional rows.
- Formulation A (decision 12) runs per particle tile and reference tile, both always padded to (bt, rt):
  1. the particle terms are built on the device: w_k CTF2 and -2 w_k X.CTF, or the bank;
  2. `matmul` (bt, 2nk, P) x (2nk, rt, P) is batched over the P = pftsz+1 bins;
  3. a permute gives (P, rt, bt), then `mlx_irfft` with n = nrots (backward 1/n), then d = 1 + rows/(2 wsq);
  4. above -log(1e-10), or NaN, d becomes the invalid marker `huge`;
  5. the draw runs on the device: valid d < 0.1 huge; w = exp(-max(T,0)(d - dmin)) where the argument is
     below 80; the first rotation whose cumulative sum reaches max(u W, tiny), else the first minimum;
     (huge, 1) without a valid rotation;
  6. one entry (d(irot), irot) per pair is copied back; the rows are copied back only when a block asks.
- The production semantics were read at the pin (`score_block_posterior`, `euclid_dists_from_crvec`,
  `draw_posterior_row`, the memos) and checked by the independent review recorded in Phase 4a.
- Room for Phase 5b: lifecycle and scoring are separate submodules. The shift-map submodule joins the same
  parent, prepared references and halves.
- Numerical constants that several test modules share (the invalid distance, the markers, the cutoff, the
  draw floor and tolerance, and the frozen pair) are in `src/test/mlxf_test_defs.f90`.

**Exit items.**
- **The Phase 4a entry precedes the first GPU run: met.** The entry was written at 18:32:12 EST from the
  calibration log of 18:32:03 to 18:32:04 (`keep/phase4/phase4a_calibration_cpu.log`, CPU device only). The
  first GPU run of the pipeline started at 18:33:37 (`keep/phase4/first_gpu_run.log`). Until the entry the
  tester listed the CPU device alone, and area `kernels` was not a CTest entry.
- **`unit_kernels suite=polar_table` on both devices, Debug and Release, with the frozen bounds: met.** 194
  checks pass in each build (`keep/phase4/exit_{debug,release}_polar_table.log`; fresh trees `p4_debug` and
  `p4_release`).
  - Seed 2: row error 4.426e-7 on the CPU and 3.605e-7 on the GPU (bound 8.625e-7). Minimising rotation
    differing: 0 of 96 on each device (bound 1).
  - Every entry's validity matches the oracle: 8 pairs have no valid rotation and 16 have mixed validity.
  - The draw on the device's own rows holds for every pair, within 1e-4 W, with the entry's distance bit for
    bit the row's.
  - One state (references 1 to 4), the shared representatives [7, 2, 5] and full tiles (rt 8, bt 6) meet the
    same bounds.
  - Reported, not gated: per temperature (0, 1, 30, 1e4), the device's rotation equals the draw on the
    oracle's rows with the same u in every pair on both devices, and rounding the real64 keyed variate to
    float32 changed no oracle draw.
- **Lifecycle and mismatch checks: met** (same logs). Refused before scoring, with nothing queued (the live
  count is unchanged):
  - no prepared references, and a block after invalidation;
  - another generation, including the old generation against rebuilt references;
  - the other half; another shape; the reference list in another order, and another list;
  - banks without flags; a non-positive wsq; non-positive particle IDs;
  - a slot outside 1..2, a busy slot, and an empty slot to collect.

  References that change are invalidated and prepared again: the new generation meets the bounds against
  the new oracle, and its rows differ from the old. After a warm cycle, three create/use/kill cycles (kill
  twice each) and one workspace left to finalization return the live count and the active memory exactly
  to their warm values, on both devices.
- **Schedule identity at fixture size: met** on both devices, in both halves. With the canonical tile plan
  (rt 3, bt 4), entries are bit-identical by global pair:
  - in three repeats;
  - for outer batches of 6 and of 4 then 2 (batches aligned to bt, so every particle keeps its tile
    position);
  - synchronously and with two slots in flight.
- **Budget 8: met.** A scratch copy with budget 7 fails configuration: "8 CTest entries do not match the
  budget of 7" (`logs/p4_budget7.log`).
- **Zero warnings: met.** Debug and Release from scratch (`logs/p4_{debug,release}.log`).
  - `check_tree: passed`. Its only notice is the five untracked new sources, left unstaged.
  - Fast gate 8 of 8 on the final source: Debug 11.4 s and Release 10.7 s
    (`p4_*/test_runs/ctest_fast.log.timing.txt`; `unit_array` 11.40 s and 10.73 s).
  - `unit_kernels` takes 1.25 s in Debug and 0.68 s in Release (0.84 s in the run before the last comment
    edit); its registration comment says why.
  - The leak gate (`unit_array`) is unchanged and passes.

**Production-contract coverage (section 6)**, as listed in the tester:
- both halves, with their own references and weights;
- ordinary particles and seed-bank particles: the bank replaces X.CTF and the particle's own wsq stays;
- full and partial tiles on both sides; contiguous and listed references with global IDs; one and several
  states (IDs (s-1) x 4 + p over two states);
- the shared-representative subset;
- edge cases: zero temperature; invalid rows and mixed rows; the first-reaching rule (u = 0 takes the first
  rotation of positive weight), its fallback (u = 1.5 takes the first minimum) and the cutoff (a constructed
  argument of 82 carries no weight);
- the mismatches, rebuilding, and the lifecycle above;
- an independent check of the rotation convention: every ordinary particle, built from its reference
  rotated by s samples, has its minimum at rotation s + 1.

Dtypes and halves against Phase 0's record:
- The workspace takes complex64 memos in the production layout and builds the bin-major (2nk, R, P) copy of
  `ft_ref_bins`. Weights are real32, as the block kernel's `sigma2_wk`; wsq is real64, temperatures are
  real32, and u is float32 from the caller.
- **Correction of Phase 0's entry:** its polar dimensions named the shell weights "real64 (`sigma2_wk8`)".
  `score_block_posterior` reads `sigma2_wk`, which is real(sp). `scratch/keep/polar_case.txt` and its
  summariser are corrected.
- The fixture splits halves as SIMPLE's benchmark does (odd global IDs in the even half), and Phase 0's cases
  have 1,000 particles per half.

**Rule `defs` (`scripts/check_rules.py`).**
- It now treats `src/test/mlxf_test_defs.f90` as the defs module of test code, under the defs form: public by
  default, constants only, intrinsic imports listed private. The register and the skill already sent shared
  test constants there; before the change the rule flagged every import of them (13 findings on the tree).
- Plants (`logs/p4_plant_defs.log`) fail as intended: a tester constant imported by the registry; and, in the
  test defs module, a `public` statement, a `contains`, an import of `mlxf`, and that import not listed
  private. The tree passes.

**Decisions taken under delegation.**
- The workspace layout and names above.
- The canonical tile plan of the fixture (rt 3, bt 4) and identity batches aligned to bt.
- Area `kernels` entered the registry first, so that the CPU-only tester could run. `test/CMakeLists.txt`
  and the budget followed after the Phase 4a entry (decision 11), and no gate ran in between.
- The definitions fixed with the calibration (Phase 4a).
- NaN distances are invalid, as SIMPLE's draw skips non-finite distances.
- `prepared_now` and `message` are pure, because Release's `-Werror=function-elimination` rejects an impure
  getter in a logical expression.

**Findings for the maintainer.**
- Section 6 states the ring oracle as Σ_k w_k Σ_j |X_j - C_j R_(j-r)|² / (2 wsq). That equals SIMPLE's distance
  only while wsq is the particle's own: for a seed-bank particle SIMPLE keeps the particle's wsq. The tester
  uses the expanded form 1 + Σ_k w_k Σ_j [C_j² |R_(j-r)|² - 2 Re(X_j C_j conj(R_(j-r)))] / (2 wsq), and
  checks it against the squared-distance form for an ordinary particle (≤ 1e-12 relative).
- The device judges validity in float32 and SIMPLE in float64: they can differ only within float32
  rounding of -log(1e-10).
- The new testing rule (a fixture computed in double precision and rounded once) cannot be checked by
  reading, because a regular expression cannot know a term's kind. It has no `check_rules.py` rule.

**What it means, in short.** The polar table's scoring stage runs on both devices through the public
`mlxf` operations alone: one complex product per bin, an inverse real transform and the posterior draw. It
reproduces SIMPLE's block scorer to 4e-7 of each pair's distances, with no minimising rotation differing and
every draw consistent with its own rows. Mismatched blocks are refused before scoring, the schedule does not
change any entry, and the workspace leaves nothing behind. These are fixture-size results; speed and the
64,000-pair accuracy block are Phase 5's.

### Phase 5a, the block calibration: 2026-11-22 18:54 EST (run `mlxf_m1`) - frozen

Written at 2026-11-22 18:54:44 EST, before any GPU run of `bench_polar_table suite=accuracy`. Every run so far used
`device=cpu`.

- **What was calibrated.** The accuracy block of section 6: 64 particles (32 per half) against 1,000
  references per half, 64,000 pairs, at SIMPLE's case geometry. That geometry is case `2500_4` of
  Phase 0's `scratch/keep/polar_case.txt`: pftsz 182 (nrots 364), shells 2 to 62 (nk 61).
  - The data are synthetic and seeded (block seed 1): reference rings with amplitude decaying over the
    shells, and particles made as the CTF in [0.2, 1) times a rotated reference of their half plus noise at
    0.3 of the shell's amplitude. Memos come from a double-precision DFT, rounded once to single precision.
    Shell weights are k/σ², with real32 weights and real64 wsq, as in SIMPLE.
  - The inverse temperatures cycle over 1, 30, 420 (about the production median) and 1e4.
  - The oracle is the DFT-matrix oracle (`polar_memo_rows` in `src/test/mlxf_kernel_polar_oracle.f90`). It
    computes c = Σ_k w_k [ctf2 ft_ref2 - 2 xctf conj(ft_ref)] in double precision from the memos, then
    d = 1 + irdft(c)/(2 wsq) by a direct inverse real DFT.
  - The workspace runs formulation A with the block's canonical tile plan (bt 16, rt 250) on the CPU device.
- **The pair, as measured.** The same in both Release runs; Debug agrees to ten digits. Log:
  `/Users/elmlundho/agent_work/arun/mlxf_m1/scratch/keep/phase5/phase5a_calibration_cpu.log` (Release
  18:52:56 and 18:53:09, Debug 18:53:28).
  - e_cpu = **7.2525524223032628e-7**, *measured* (Debug; Release 7.2525524211e-7). It is the largest
    error of a pair's distances relative to the largest |d| of its oracle row, as for the fixture.
  - n_cpu = **2** of 64,000 pairs whose minimising rotation differs, *measured*.
  - Every entry is valid, and the draw on the device's rows holds for every pair.
- **Frozen in `src/test/mlxf_test_defs.f90`.** `POLAR_BLOCK_ERR_CPU = 7.2525524223032628e-07`,
  `POLAR_BLOCK_ROT_CPU = 2`, `POLAR_BLOCK_ROT_Q = 5` (section 6), with `POLAR_ROW_FACTOR = 2`.
  - **Derived bounds for block seed 2, every device and formulation:** row error ≤ 1.4505e-6; minimising
    rotation differing in at most max(2 x 2, 5) = 5 of 64,000 pairs.
  - The draw stays within 1e-4 W, as for the fixture.
- **Context (not a gate).** Seed 2 on the CPU device: row error 6.654e-7 and 0 rotations differing (same log).

### Phase 5, the benchmark on the M2 Ultra: 2026-11-22 (run `mlxf_m1`, unattended) - complete

Machine FWM-S116118 (Phase 0's record), full precision (`MLX_ENABLE_TF32=0`) in every row. Base `27d80aa` with
Phases 0 and 4 in the working tree. Paths below are under `/Users/elmlundho/agent_work/arun/mlxf_m1/scratch`.

Ruling R1, applied here for the first time: arun numbers phases with integers, so its phase 5 carries this Phase 5
and then Phase 5b. Each gets its own Progress entry, and Phase 5b-a's entry precedes Phase 5b's first GPU run.

**Files changed.**
- New: `src/test/mlxf_bench_polar_table.f90`, and `src/test/mlxf_kernel_polar_oracle.f90` (row added to the
  file table first; the tester and the benchmark share it).
- Changed:
  - the workspace (`src/test/mlxf_kernel_polar_table{,_lifecycle,_score}.f90`) and its tester;
  - `src/test/mlxf_test_defs.f90`;
  - `src/test/mlxf_test_registry.f90` (the `BENCHES` table, `run_bench`);
  - `test/mlxf_test_exec.f90` (the `bench_<x>` dispatch; a benchmark's key=value arguments are allowed in
    any order);
  - `scripts/check_test_registry.py` (`BENCHES` held to `run_bench`);
  - `doc/policies/test_environment_policy.md` (benchmarks; the judging accuracy mode);
  - `doc/history/2026-11.md`; this plan.

**What was built.**
- `mlxf_test_exec test=bench_polar_table suite=<accuracy|time|profile|overlap|stream>`. It reads the case
  geometry from Phase 0's `scratch/keep/polar_case.txt` (`cases=`, `case=`) and generates synthetic seeded
  data: reference rings, and particles as the CTF times a rotated reference plus noise. Memos come from a
  double-precision DFT, rounded once.
- Rows go to `./bench_polar_table{,_profile,_overlap}.tsv`, with decision 19's case columns (`nspace`,
  `nstates`, `nrefs`, `nptcls`, `pftsz`, `nrots`, `kfrom`, `kto`, `load1`, `wall_s`, `wall_rep1..3`,
  `pairs_per_s`). After them come B, R, the formulation, `device`, `precision`, preparation, the host's
  seconds, estimated and MLX peak bytes, useful and padded pairs, and the status (timed, or pruned with its
  reason).
- The shared module holds the ring DFT, the keyed variates, the checks of rows and draws, and the DFT-matrix
  oracle `polar_memo_rows`: c from the memos in double precision, then a direct inverse real DFT.
- The workspace gained formulations B and C and the compiled tail, an evaluation barrier per stage (profile),
  and two changes to how a block is queued:
  - **every tile is queued (`mlx_async_eval`) as it is built.** Building a whole block's graph first let MLX
    hold about 2.5 full-half row arrays at once: 36.9 GB of MLX peak at B 500, R 1000 on 2,500 x 4, against
    11.1 GB per tile, and 4.58 s against 4.39 s.
  - **a tile's rows are referenced only when the block asks for rows;** before, every tile's rows stayed
    alive.

**Exit items.**
- **The Phase 5a entry precedes the first GPU run of `accuracy`: met.** The entry was written at 18:54 EST from
  the CPU-only calibration log (18:52 to 18:53). The first GPU run of `accuracy` was at 18:54:55
  (`keep/phase5/first_gpu_accuracy_A.log`).
- **`accuracy` passes the block's frozen gates for every counted formulation: met.** On the 64,000-pair block,
  seed 2, both devices: row error ≤ 1.4505e-6, minimising rotation differing in ≤ 5 pairs, every entry's
  validity as in the oracle, and the draw on the device's rows within 1e-4 W.

  | formulation | CPU row error | GPU row error | rotations differing (CPU, GPU) | log |
  | --- | --- | --- | --- | --- |
  | A | 6.654e-7 | 1.056e-6 | 0, 0 | `keep/phase5/first_gpu_accuracy_A.log` |
  | B | 6.654e-7 | 1.161e-6 | 0, 0 | `keep/phase5/accuracy_form_b.log` |
  | C | 1.261e-6 | 1.324e-6 | 0, 0 | `keep/phase5/accuracy_form_c.log` |
  | **B + compiled tail (kept), final tree** | 6.654e-7 | 1.161e-6 | 0, 0 | `keep/phase5/exit_accuracy_form_b.log` |
  | C + compiled tail, final tree | 1.261e-6 | 1.324e-6 | 0, 0 | `keep/phase5/exit_accuracy_form_c.log` |

  - The compiled tail met the same gates on both devices with A, B and C, as a sensitivity run before the
    uncompiled tail was removed.
  - Sensitivity, every case within the same gates on both devices: tile shape 32 x 1000; partial edges
    12 x 300; particles in reversed order; references prepared in a shuffled order with their global IDs.
  - Reported against the canonical run by global pair:
    - on the CPU, every one of these gives bit-identical entries;
    - on the GPU, reversed particles change 7,524 (A) and 7,596 (B) entries, C's 0;
    - shuffled references change none.
  - Reported per temperature (B, final tree): the device's rotation differs from the draw on the oracle's rows
    with the same u in 2 of 16,000 pairs at T 420 on both devices, and in 2 of 16,000 at T 1 on the CPU only;
    0 at T 30 and 1e4. Rounding the real64 keyed variate to float32 changed no oracle draw.
  - The fixture's gates also hold for B and C (`unit_kernels`, 218 checks, both devices; B is now every
    fixture test's formulation).
- **Schedule identity holds on the block: met.** For every formulation and both devices, entries are
  bit-identical by global pair:
  - in three repeats;
  - for outer batches of 32 and 16 particles;
  - for CPU teams of 1 and 24 (the host's block preparation and consumption under OpenMP);
  - synchronously and with two slots.
- **`time` rows exist for every case: met.**
  - Grid: decision 13's B in {64, 250, 500, 1,000, 2,000} x R_t in {64, 250, 500, 1,000, 2,500}.
  - Cases: the four dense ones, and the shared-representative case `neigh_reps_c1_1` (5,000 directions, 252
    representatives, 1,200 particles, pftsz 140, shells 2 to 81).
  - The kept formulation has two invocations per case (`keep/phase5/bench/time_<case>_b1_r{1,2}/`). A,
    dropped, has one sweep (`time_<case>_a0_r1/`).
  - Each row carries memory (estimated, MLX peak), useful and padded pairs, and the precision mode.
  - Pruned before allocation, with the reason in each row:
    - B 2,000, above the particles per half, in every case;
    - R_t 2,500, above the references (1,000 x 1, 1,000 x 4, the representative case), and R_t ≥ 500 for the
      representatives;
    - B 1,000 x R_t 2,500 on 1,000 x 4, 2,500 x 1 and 2,500 x 4: the estimate of 52 GB is beyond the 48 GB
      budget.
  - Kept formulation, pairs per second, run 1 / run 2 (*measured*; `keep/phase5/bench/phase5_summary.txt`):

    | case | canonical B 64, R_t 250 | best tile | context ratio to Phase 0's `block_prod` (24 threads) |
    | --- | --- | --- | --- |
    | 1,000 x 1 | 9.458e6 / 9.518e6 | 64 x 250 | 4.11 |
    | 1,000 x 4 | 9.891e6 / 9.827e6 | 64 x 1,000: 1.0164e7 / 1.0176e7 | 4.23 (canonical) |
    | 2,500 x 1 | 1.0136e7 / 1.0361e7 | 64 x 250 | 4.38 |
    | **2,500 x 4 (the verdict's case)** | **1.0465e7 / 1.0493e7** | 64 x 250 | **4.55** |
    | shared representatives (252) | 4.028e6 / 4.037e6 | 64 x 64: 6.029e6 | 2.01 (canonical); 3.00 at 64 x 64 |

  - Spread between the two runs: at most 4.3 % over every configuration of every case, 0.27 % at the
    canonical plan on the verdict's case.
  - Largest MLX peak: 24.8 GB (2,500 x 4, B 500, R_t 2,500); 10.3 GB at the canonical plan.
  - The context ratio compares the slower GPU run with the faster CPU run. It is context only: the verdict is
    Phase 6's, on the M5 Ultra.
  - The representative case pads its 252 references to 500 at R_t 250, which is why it is slower there.
- **The kept formulation and the canonical tile plan: named.**
  - **B with the compiled tail** is the full-precision formulation: one real GEMM of packed (Re, Im) parts
    per bin, the inverse real FFT, and the distances and draw as one compiled function.
  - **The canonical tile plan is B 64, R_t 250**: the fastest on the verdict's case and on 1,000 x 1 and
    2,500 x 1, and within 3 % of the best on 1,000 x 4.
  - The 30 % rule (decision 12), on the verdict's case. Two runs each; the ratios use the slower run of the
    faster formulation against the faster run of the slower one.

    | at B x R_t | A | A + compiled | B | B + compiled | C | C + compiled |
    | --- | --- | --- | --- | --- | --- | --- |
    | 64 x 64 | 5.16e6 / 5.19e6 | 5.80e6 / 5.77e6 | 7.38e6 / 7.40e6 | 9.75e6 / 9.74e6 | 7.26e6 / 7.29e6 | 9.66e6 / 9.67e6 |
    | 64 x 250 (canonical) | 5.05e6 / 5.05e6 | - | 7.83e6 / 7.83e6 | 1.0465e7 / 1.0493e7 | - | 1.0135e7 / 1.0193e7 |
    | 250 x 1,000 | 4.60e6 / 4.60e6 | 5.25e6 / 5.25e6 | 7.26e6 / 7.23e6 | 9.30e6 / 9.42e6 | 7.10e6 / 7.10e6 | 9.11e6 / 8.83e6 |

    - B with the compiled tail is **2.07 x A**, and **1.336 x B uncompiled** at the canonical plan (1.316 at
      64 x 64, 1.28 at 250 x 1,000).
    - **Dropped and removed from the code:** formulation A (the complex product), and the uncompiled tail.
      The tail now runs only through `mlx_compile`, and the plain graph is the compiled function's body.
    - **C** (the inverse transform as a real GEMM) with the compiled tail is 0.97 x B in full precision, so it
      is not the full-precision formulation. Decision 12 keeps one formulation per precision mode, and C's
      purpose is the accelerated mode (every product real, NAX-eligible), which this M2 cannot measure. C
      therefore stays in the code, gated (it passes the block's and the fixture's gates on both devices), for
      Phase 6 to time in the accelerated mode. If it is not 30 % faster there, Phase 6 removes it.
- **The overlap rows exist: met** (`keep/phase5/bench/overlap2_2500_4_*`; canonical plan, outer batches of 250).
  - Synchronous 1.915 s, two slots 1.895 s.
  - The host's block preparation and consumption take 0.015 s. The host spends 1.866 s in `submit` (staging
    and graph building), so the two slots hide about 1 % of the host's time.
  - The submitting thread is busy for nearly the whole scoring. Measured: the wall time is spent inside
    `submit`. Hypothesis, unverified: with one queued evaluation per tile, MLX paces the submitting thread.
    Overlap is therefore not available to this schedule as built. That matters for SIMPLE's integration (a
    submitter thread apart from the CPU team), and is not gated.
  - Under the run's own CPU memory-streaming load (16 threads, 328 GB/s, `suite=stream`), the GPU's scoring
    slows by 25 %: 2.393 s synchronous, 2.392 s with two slots.
  - The first overlap rows (`overlap_*`, without the `submit` column) are superseded by `overlap2_*`.
- **The M2 Ultra's ratio against Phase 0's `block_prod`: recorded as context** (the table above).
- **Profile, preparation, cold compilation, memory** (`keep/phase5/bench/profile_2500_4_r{1,2}`, canonical
  plan, verdict's case; with an evaluation barrier after every stage):

  | stage | seconds |
  | --- | --- |
  | particle terms | 0.017 |
  | products (real GEMM) | 0.67 to 0.68 |
  | inverse FFT | 0.69 to 0.70 |
  | distances and draw (compiled) | 1.60 to 1.61 |
  | concatenation | 0.02 to 0.03 |
  | copy-out and the host | 0.04 |
  | total with barriers (without: 1.91) | 3.04 / 3.08 |

  - Reference preparation (both halves, 10,000 references each): 1.53 / 1.55 s. The first, cold pass is
    3.24 s against 3.04 s for a warm pass with the same barriers, so cold compilation costs about 0.2 s.
  - Preparation amortises over the outer batches that share the references. Over one batch of 2,000
    particles it is 45 % of the work; over 50 batches it is under 2 %.
  - Memory at the canonical plan: MLX peak 10.3 GB. The resident reference tiles are 7.1 GB, derived: two
    halves x 4nk x 2 x 10,000 x 183 bins x 4 B. Host staging per call is 0.22 GB. The process peak footprint
    is 18.6 to 19.9 GB, which includes the benchmark's synthetic memos.
  - The pruning estimate is conservative for large tiles but below the measured peak for small ones, where
    many tiles are queued at once (9.2 GB measured against 4.1 GB estimated at 64 x 64). Both stay far
    under the budget.
  - Reconciling retained bytes with process growth is Phase 6's, before a go verdict.
- **Debug and Release from scratch, zero warnings, fast gate: met** (`p5_debug`, `p5_release`;
  `logs/p5_{debug,release}.log`).
  - Gate: 8 of 8 entries, 11.4 s and 10.9 s; `unit_kernels` 3.16 s in Debug and 0.58 s in Release.
  - `check_tree: passed`.
  - `unit_kernels suite=polar_table`: 218 checks on both devices in both builds
    (`keep/phase5/exit_{debug,release}_polar_table.log`).

**Timed runs.**
- `scratch/run_bench_case.sh` ran each invocation in its own directory: `uptime.txt` before and after,
  `sampler.txt` of the other processes' CPU every 5 s, and `/usr/bin/time -l` in `run.log`. Before each it
  waited for a 1-minute load ≤ 4 and other processes ≤ 250 %.
- Flags and repeats:
  - time 2,500 x 1 A run 1: 808 %;
  - time 2,500 x 4 B run 1: 621, 547 and 401 % before a clean fourth attempt;
  - time 1,000 x 1 and 1,000 x 4 B run 2: 475 and 849 %.

  The sources were Defender, Cylance, Nessus and Spotlight, not the run. Every kept row is from a clean
  invocation; flagged ones are kept as `*.prev_<time>`.
- The overlap-under-load runs skipped the load wait (`OWN_LOAD=1`): their own stream process is the load
  being measured.

**Rule check added.** `check_test_registry.py` holds the registry's `BENCHES` table to `run_bench`'s case
branches. Two plants fail as intended (`logs/p5_plant_bench.log`): a listed name without a branch, and a branch
without a name.

**Decisions taken under delegation.**
- The benchmark's design and names.
- The shared oracle module.
- One queued evaluation per tile.
- The block's canonical plan for `accuracy` (bt 16, rt 250; outer batches 32 and 16 aligned to bt) and the
  timing canonical plan (64 x 250).
- The 30 % rule's application per precision mode, with C kept for Phase 6.
- The CPU team of identity: the host's block preparation and consumption under OpenMP.
- `submit` timed apart in the overlap rows.
- The 5a pair frozen from the Debug value, as in Phase 4a.

**Findings for the maintainer.**
- MLX's complex64 `matmul` is the slow part of formulation A on the GPU: a real GEMM of packed parts is
  1.43 x faster on its own.
- The draw tail is the largest stage even compiled: elementwise passes over every rotation's distance.
- The single-thread submission bounds overlap (above).
- After the change to B, the CPU calibration line of the block (block seed 1, reported) reads n 3 for B
  against the frozen n_cpu 2 from A. The frozen pair is the object's, measured with A before its first GPU
  run, and every formulation is judged against it.

**What it means, in short.** On the M2 Ultra, the GPU scores the verdict's case (2,500 directions x 4 states
against 2,000 particles) at 1.05e7 useful pairs per second, from prepared memos to entries in Fortran arrays,
in full precision. That is 4.55 times SIMPLE's production block scorer on all 24 CPU cores here, with every
gate held. It does so with one real GEMM per bin, an inverse FFT and a compiled draw. Preparing the
references costs 1.5 s, a share that falls as more batches use them. The verdict, and the accelerated mode,
are Phase 6's on the M5 Ultra.

### Phase 5b-a, the shift-map calibration: 2026-11-22 20:31 EST (run `mlxf_m1`) - confirmed and frozen

Written at 2026-11-22 20:31:16 EST, before any GPU run of the shift maps. The tester `mlxf_kernel_polar_table_shiftmap_tester`
(sub-suite `polar_shiftmap`) listed the CPU device alone, and no GPU branch existed.

- **What ran.** The unfused implementation (`src/test/mlxf_kernel_polar_table_shiftmap.f90`) against the
  direct oracle, twice in Debug and twice in Release, on the CPU device: 287 checks each.
  Log: `/Users/elmlundho/agent_work/arun/mlxf_m1/scratch/keep/phase5b/phase5b_a_calibration_cpu.log`
  (20:30:57 to 20:30:59). The implementation:
  - builds the Bessel weights on the host in real64 and rounds them once; K comes from the note's tail rule
    (≤ 1e-12), never from an observed error;
  - gathers the shifted spectra, contracts them with the folded weights in one complex matmul per tile, then
    runs `mlx_fft2`, the loss, and the mode, width and evidence reductions;
  - uses no compilation.
- **The fixtures** are the scientific examples' section 3, analytic:
  - Nrot 24, shells 1 to 4, box 32, 5 particles and 7 references in each of two halves, radii
    [0, .5, 1, 1.5], 16 directions, noise-free and perturbed;
  - the folding case: Nrot 8, box 16, shells 1 to 3, radii [0, 4, 8], 7 directions, with orders 0 to 30
    kept, beyond both transform axes;
  - the Nyquist ring.

  The oracle evaluates the residual directly at every grid point in real64, with no Bessel table and no FFT.
- **Measured on the CPU device**, identical in all four runs:

  | quantity | measured | cap (decision 17) |
  | --- | --- | --- |
  | a map against the oracle, normalised L2 (noise-free / perturbed / folding) | 4.68e-7 / 5.05e-7 / 9.21e-8 | 1e-4 |
  | the same, largest absolute error | 5.39e-7 | recorded |
  | zero-radius map against the dense row (relative to the row's max), and across directions | 1.50e-6, 0 | 1e-4 |
  | log evidence (no prior / screen prior / flat likelihood) | 1.05e-6 / 1.19e-6 / 9.5e-7 | 1e-4 |
  | width variance (same cases) | 3.0e-7 / 5.3e-7 / 3.3e-7 | 1e-4 x max(1, ρ_max²) = 2.25e-4 |
  | Nyquist ring: loss at identity, one step | 0, 4.00000 | 4e-4 |
  | modes judged (oracle margin > twice the map's bound) / equal | 8 / 8 per fixture | exact |
  | the noise-free known poses recovered | all judged | exact |
  | indices across permuted and duplicated candidates, tiles of 1 and 4 pairs | equal | exact |
  | three repeats | bit-identical | exact |

- **Frozen in `src/test/mlxf_test_defs.f90`**, as decision 17 sets them (*guessed*, now confirmed on the CPU
  device): `POLAR_MAP_CAP_L2 = 1e-4`, `POLAR_MAP_CAP_LOG = 1e-4`, `POLAR_MAP_CAP_VAR = 1e-4`; with
  `POLAR_BESSEL_TAIL = 1e-12` (the tail rule) and `POLAR_MAP_LOG_CUT = -40` (SIMPLE's cut).
  - Every cap is met with a margin of at least 80 times.
  - No CDF cap applies: the maps return their modes, and the disk draws are outside decision 15.

### Phase 5b, the shift maps: 2026-11-22 (run `mlxf_m1`, unattended, M2 Ultra) - complete

**Machine and base.**
- Machine: M2 Ultra FWM-S116118; GFortran 16.2, mlx-c 0.8.0 / MLX 0.32.4.
- Base: the working tree on top of `27d80aa` with Phases 4 and 5.
- Build: hand-configured trees, as in Phase 0.
- Logs: `/Users/elmlundho/agent_work/arun/mlxf_m1/scratch/keep/phase5b/`, called `phase5b/` below.

**Files changed.**
- `src/test/mlxf_kernel_polar_table.f90`: the map types, the maps' components and interfaces.
- `src/test/mlxf_kernel_polar_table_lifecycle.f90`: the maps dropped with the references.
- `src/test/mlxf_kernel_polar_table_shiftmap.f90` (new) and `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90` (new).
- `src/test/mlxf_test_defs.f90`: the tail, the log cut and the frozen caps.
- `src/test/mlxf_test_registry.f90`: the row `polar_shiftmap`.
- `src/test/mlxf_bench_polar_table.f90`: the mode `shiftmap`, and per-shell square sums in the bench data;
  `wsq` is bit-identical.
- `test/CMakeLists.txt`: the kernels comment; its row gained 5b first.
- `doc/policies/test_environment_policy.md`.
- `doc/implementation_notes/planned/mlxf_scientific_examples.md`: Progress.
- `doc/history/2026-11.md`, this plan, and the review report `mlxf_milestone1_report.md` (new).

**Exit items.**
- **The decision 16 operations pass their area tests on both devices in Debug and Release: met.**
  `unit_ops` passes 371 checks and `unit_fft` 57, on the CPU and the GPU, in both final exit trees
  (`phase5b/exit_{debug,release}_unit_{ops,fft}.log`). The maps use only public `mlxf` operations:
  - `mlx_take_along_dim`, with a broadcast index;
  - batched `matmul` with broadcast batch dimensions;
  - `mlx_fft2`, `mlx_irfft`, `real`, `cmplx`, `mlx_permute`;
  - `minloc`, `minval`, `sum`, `merge`, `exp`, `sqrt`, `max`, `mlx_logsumexp`.

  Nothing beyond them was needed.
- **The Phase 5b-a entry precedes the first GPU run: met.**
  - The entry was written at 20:31:16.
  - The first GPU run was at 20:31:31 (`phase5b/first_gpu_shiftmap.log`, 574 of 574 checks).
- **`unit_kernels suite=polar_shiftmap` passes on both devices with the frozen caps: met.** It passes 574
  checks in Debug (1.45 s) and Release (1.11 s); the logs are `phase5b/exit_{debug,release}_polar_shiftmap.log`
  and `exit_{debug,release}_unit_kernels.log`, with `polar_table` 218. The largest errors against the
  oracle, with every cap at 1e-4:

  | quantity | CPU | GPU |
  | --- | --- | --- |
  | map, normalised L2 (noise-free / perturbed / folding) | 4.68e-7 / 5.05e-7 / 7.6e-8 | 5.07e-7 / 5.10e-7 / 8.0e-8 |
  | log evidence | ≤ 1.19e-6 | ≤ 1.29e-6 |
  | width variance | ≤ 5.3e-7 | ≤ 7.6e-7 |
  | modes judged, equal | 8 of 8 per fixture | 8 of 8 per fixture |
  | Nyquist ring (loss at the identity, one step away) | 0 and 4 | 0 and 4 |
- **Every negative control fails its assertion: met.**
  - Each control was planted by a temporary edit (`scratch/plant_5b.sh`, `scratch/patch/plant_5b.py`), built,
    run on the CPU device, and restored. After every restore the sources are byte-identical to the kept
    ones.
  - Logs, each with the planted diff: `phase5b/negative_controls/plant_<x>.log`, on the kept form. The same
    counts on the calibrated form are in `negative_controls_v1/`.

  | control | the plant | checks failing (of 287) | first failure |
  | --- | --- | --- | --- |
  | Nyquist omitted | the references' Nyquist bin zeroed | 3 | the folded maps match the direct residual |
  | shift sign reversed | J_n's argument negated | 7 | the map L2 cap; modes 0 of 8; poses 0 of 3 |
  | halves mixed | the other half's references prepared | 12 | the map L2 cap; mode mismatch |
  | cell area omitted | log area dropped from the prior | 8 | modes 2 and 3 of 8; the log evidence |
  | tempered T for the width | T in place of T_phys | 2 | the physical width's variance |
- **The 100-cycle lifecycle returns to baseline: met.** `test_lifecycle` passes on both devices: live handles
  and active memory return to their warm values over 100 cycles of prepare, score, invalidate and rebuild.
- **The leak gate passes: met.** `unit_array`'s exact gate passes in the fast gate of both exit trees. It is
  unchanged, since no library module was added.
- **The `shiftmap` rows exist, with memory and precision mode: met.** See below.
- **Budget 8 and zero warnings: met.**
  - Final Debug and Release trees from scratch (`scratch/p5b_debug`, `scratch/p5b_release`,
    `scratch/logs/p5b_{debug,release}.log`): zero compiler warnings, fast gate 8 of 8. `unit_kernels` took
    2.64 s in Debug and 1.69 s in Release; its CMake comment says why it is above 0.5 s.
  - `check_tree.sh` passes, and both formatters rewrite nothing.
  - Phase 5's `accuracy` block passes unchanged on the final Release tree
    (`phase5b/exit_release_accuracy_form_b.log`: GPU 1.161e-6, 0 rotations, 192 of 192).

**The benchmark** (`bench_polar_table suite=shiftmap`; decision 19's case 2500_4 and grid, read from
`scratch/keep/shiftmap_grid.txt`).
- Inputs: 16 candidates per particle by the rule; T = 0.3 π wsq_band / (2 pftsz) with T_phys = T / 0.3; the
  prior on the screen only; box 180 from the grid's step.
- Device and precision: GPU, full precision (`MLX_ENABLE_TF32=0`).
- Timing: best of 3 after a warm-up, then one profiled pass for the stages.
- Kept rows: `phase5b/bench/shiftmap3_r{1,2}/bench_polar_table_shiftmap.tsv` (21:09 to 21:12, other
  processes at most 173 %, load at most 3.1).
- Summary: `phase5b/bench/phase5b_summary.txt` (`scratch/keep/summarize_phase5b.py`).

| map | ptile | maps/s (run 1, run 2) | spread | µs/map construct, select, reduce, host | SIMPLE 24 threads | ratio (context) |
| --- | --- | --- | --- | --- | --- | --- |
| window | 64 | 1.924e4, 1.928e4 | 0.2 % | 36.3, 5.4, 8.6, 1.8 | 4.456e4 | 0.432 |
| window | 256 | 2.516e4, 2.518e4 | 0.1 % | 32.2, 1.9, 3.9, 1.7 | | 0.565 |
| window | **1024** | **2.591e4, 2.589e4** | 0.05 % | 31.5, 1.7, 3.6, 1.7 | | **0.581** |
| screen | 64 | 8.026e3, 8.012e3 | 0.2 % | 87.7, 10.1, 24.7, 1.8 | 7.537e3 | 1.063 |
| screen | **256** | **8.418e3, 8.399e3** | 0.2 % | 86.5, 9.2, 21.2, 1.8 | | **1.114** |
| screen | 1024 | pruned: estimate 66.9 GB beyond the 48 GB budget | | | | |

- The ratio is the slower GPU run over the faster SIMPLE run (context only; the verdict of decision 18 is
  Phase 6's).
- **Preparation**, apart from the timing, per invocation and both halves: the references (the dense
  workspace) take 1.40 s on the screen and 1.60 s on the window, and the Bessel tables and the maps' resident
  data 0.41 to 0.44 s.
- **Copy-out** is at most 0.4 ms per pass.
- **Memory:** the MLX active peak is 17.97 GB (window, ptile 1024) and 15.58 GB (screen, ptile 256). The
  process peak footprint is 35.2 GB and the maximum RSS 21.5 GB.
- **K:** the tail rule keeps 21 orders on the window and 41 on the screen; SIMPLE's `JTOL` keeps 16 and 32
  (`norder` and `norder_used` in the rows).
- **Decision 18's production-equivalent CPU cost:** not available (R1: no production profile on this Mac).
  SIMPLE's own split at 24 threads, in µs per map and thread:
  - window: construction 359, selection 22.5, reduction 153;
  - screen: construction 2,004, selection 144, reduction 1,040.

**Superseded timed pairs, kept as evidence.**
- `shiftmap_r{1,2}` reached a 66.0 GB process footprint and `shiftmap2_r{1,2}` 57.3 GB, above the 48 GB
  budget. The mode had no pre-allocation estimate, then counted only the tile in use while MLX's cache keeps
  the previous tile's buffers. The estimate now counts the dense workspace and the maps' resident data of
  both halves, plus twice the tile. The mode prunes before allocation and clears the cache after every
  configuration.
- Their rates agree with pair 3 within 0.6 %.
- `shiftmap2_r1`'s first attempt was flagged (other processes at 601 %) and repeated clean.

**The formulation: changed after the calibration, judged by the same caps.**
- The calibrated form contracted the shifted products with the folded weights in one dense complex matmul:
  (nkb (K+1)) x (nalpha nrho), mostly zeros. It ran the window at 1.11e4 maps per second, 0.25 x SIMPLE.
- Measured on the window at ptile 256, outside the timed-run protocol (`scratch/runs/p5b_explore`, load 2 to 4):
  - a per-order batched complex matmul: 7.0e3;
  - **kept:** per order one real GEMM over the shells, with the pairs beside the ring position as rows (the
    weights are real), a real fold onto the directions, then `mlx_fft2`: 2.53e4, screen 8.45e3;
  - the shifted product compiled: no change, so reverted;
  - the real and imaginary parts resident apart, a compiled product, and a cos/sin direction transform
    with a 1D FFT: 2.35e4 and 8.08e3, so reverted.
- The kept form passed the tester on both devices before any timed run, and the negative controls were re-run
  on it.
- Its construction, in seconds over both halves on the window / screen, with barriers after every step:

  | step | window | screen |
  | --- | --- | --- |
  | the gathers | 0.05 | 0.06 |
  | the shifted gather | 0.24 | 0.44 |
  | the product | 0.21 | 0.37 |
  | the real and imaginary parts | 0.27 | 0.49 |
  | the GEMMs | 0.20 | 0.38 |
  | the fold and the 2D transform | 0.18 | 1.17 |

  The construction is bandwidth-bound on the order-expanded product.

**Decisions taken under delegation.**
- The workspace's map types and names: `polar_map_spec`, `polar_map_block`, `polar_map_results`,
  `prepare_maps`, `score_maps`, `map_order`, `map_seconds`.
- The maps belong to the references: they are dropped on invalidation and refused after a rebuild.
- The fixtures' shapes, the direct oracle and the folding case.
- The evidence normalised over every cell, rotations included, as SIMPLE's `shiftmap_prior`.
- The kept formulation (above).
- The benchmark's tiles 64, 256 and 1024, with the best by the slower run: 1024 on the window, 256 on the screen.
- The estimate.
- The bench's own columns after decision 19's: `ptile`, `prep_refs_s`, `prep_maps_s`, `us_copyout`,
  `us_host`, `profile_wall_s`, `cpu_maps_per_s`, `ratio_cpu`, `est_bytes`, `status`. `us_map_thread`
  holds the device's microseconds per map.

**Findings for the maintainer.**
- Under SIMPLE's normaliser, a flat likelihood's log evidence is -T L, not the examples note's
  log(Nrot) - T L. The tester follows SIMPLE.
- The tail rule (≤ 1e-12) keeps more Bessel orders than SIMPLE's `JTOL` (1e-8): 21 against 16, and 41
  against 32.
- No CDF cap applies, since the maps return modes. `width_cutoff` is not implemented: the width is computed
  for every candidate, as in SIMPLE's benchmark.
- MLX's compile did not speed up the shifted product. MLX's complex64 `matmul` is slow, as in Phase 5.
- The next lever: shift the particle once per particle instead of once per pair. That needs the transform
  over the ring done before the fold, with a phase per order.

**What it means, in short.** The shift maps of SIMPLE's coarse search run on the device through the public
`mlxf` operations alone. They reproduce a direct double-precision evaluation to 5e-7 and fail all five
planted errors. On the M2 Ultra in full precision, the screen map, which carries most of production's cost,
runs 1.11 times SIMPLE's 24 threads. The window runs 0.58 times. The verdict is Phase 6's.

### Owner's review of run `mlxf_m1`: 2026-11-23 (interactive, Claude; M2 Ultra through the build bridge)

Base: `309807c` with the run's diff applied unstaged (history, 2026-11-23). Hans's review raised four P2
items, one P3 and two directions; every item listed here was built and run.

**Changes:**

- **Types and constants placed by XEMA's and SIMPLE's rules.** The register (section 2), the skill and rule
  `defs` changed. The workspace's records, the oracle's `polar_row_check`, the shared seeds and the
  benchmark's tunables moved to `src/test/mlxf_test_defs.f90`. This includes the accuracy block's tile plan
  `POLAR_BLOCK_BT`/`_RT` (the P3).
- **Memory budget.** `POLAR_BUDGET_SHARE` (0.25) of the GPU's reported `memory_size`, computed at run time
  (decision 13's quarter: 51.5 GB on the M2 Ultra) instead of a hard-coded 48 GB. The value is printed by the
  time and shift-map modes and named in a pruned row's status. The run's prunings (estimates of 52 GB and
  more) are unchanged by it.
- **P2, the returned loss.** It is now checked against the direct oracle at the returned pose, with and
  without map output. A plant that returns zero losses fails three checks.
- **P2, the failed preparation.** `prepare_maps` drops any earlier maps first, through
  `polar_table_drop_maps`, a separate module procedure the lifecycle and the shift maps share. So a refused
  or failed preparation leaves no maps and the dense scoring intact. A plant without the drop fails "after a
  refused preparation the earlier maps are gone".
- **P2, the memo shapes.** Map preparation now checks the references' geometry (pftsz, nk) and both memo
  shapes before reading them, with refusal tests for `ft_ref`, `ft_ref2` and the geometry. A plant without
  the shape check aborts in Debug with an index out of range.
- **P2, the seed-bank fixture.** A particle with a bank is its signal translated by a nonzero 2D shift in its
  own frame before the noise (`BOX` = 64; the production shift matrix exp(i 2 pi k (sin theta sx − cos theta
  sy) / box)). Its bank is the same particle translated back, rounded once.
  - New `test_bank_fixture`:
    - the bank keeps the particle's weighted power (2.6e-9 relative);
    - each bank's row against its source reference is least at the known rotation;
    - each bank aligns better than its translated particle.
  - Plants: a reversed shift sign fails both alignment checks, and a bank scaled by 1.01 fails the power
    check.
  - The mixed particles' scale is unchanged. The fixture keeps 11 rows of mixed validity and 13 without a
    valid rotation.
- **Bessel orders: decision 23.**

**Recalibration of the fixture.** The fixture changed, so its pair was measured again on the CPU device at
seed 1 (Debug, two identical runs) before the fixture's first GPU run:

- *00:15:48 EST, formulation B:* e_cpu = 2.3972463973750171e-07, n_cpu = 0
  (`~/for_claude/mlxf-review-2026-11-23/recalibration_cpu.log`). An earlier attempt with a wrong scale for
  the mixed particles is kept as `recalibration_cpu_attempt1_wrong_scale.log`.
- *00:17:17, the first GPU run:* B's GPU error was 2.96e-7, within 2 e_cpu. C's error was 9.30e-7 on both
  devices and failed against B's pair.
- *00:20:13, formulation C (decision 24):* calibrated on the CPU at seed 1 by the same procedure, giving
  e_cpu = 5.8318067127818633e-07 and n_cpu = 0 (`recalibration_cpu_per_formulation.log`).
  - C's GPU number had been seen before its pair existed. No number was chosen from it: the procedure (CPU
    device, seed 1, factor 2) was fixed before.

**Verified:**

- Debug and Release from scratch with warnings as errors: zero warnings, fast gate 8 of 8.
- `unit_kernels`: `polar_table` 231 of 231 and `polar_shiftmap` 594 of 594, on both devices in both builds.
- The 64,000-pair accuracy block: 192 of 192, unchanged.
- Logs: `~/for_claude/mlxf-review-2026-11-23/final_*`.

**Not done here, for the next step:**

- *The shift maps' work decomposition.* Shift once per particle: bounded particle/shift tiles reused across
  reference tiles, instead of the order-expanded product per pair in `tile_maps`. Then re-time both maps
  against SIMPLE's measured FFTW plans (decision 22).
- *The M2 context ratios.* They wait for that re-timing.

**What it means, in short.** The shift-map tests now check every number they return against the
independent oracle, map preparation keeps its ownership contract, and the dense fixture's seed banks are
what SIMPLE's calculator feeds. The shift maps now use SIMPLE's truncation, so GPU and CPU do the same Bessel
work. The timings that would guide architecture are next.

### The shift maps in particle tiles (decision 25): 2026-11-23 (interactive, Claude; M2 Ultra through the build bridge)

Base: as the review entry above. Files changed:

- `src/test/mlxf_kernel_polar_table_shiftmap.f90` (the construction, the compiled selection and reduction);
- `src/test/mlxf_kernel_polar_table.f90` (the components' layouts; `map_select` and `map_reduce`);
- `src/test/mlxf_kernel_polar_table_lifecycle.f90` (their release);
- `src/test/mlxf_test_defs.f90` (`ptcl_tile`);
- `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90` (tiles of one and two particles);
- `src/test/mlxf_bench_polar_table.f90` (`ptiles=` as particles, the column `ptcl_tile`, the estimate).

**Correctness.** `unit_kernels suite=polar_shiftmap`, Debug with warnings as errors, CPU and GPU: 594 of
594 at every step below, against the same oracle and the frozen caps.

- Map errors stay at 5e-7 normalised L2, and the returned losses at 4e-7.
- The five negative controls fail on the particle-tile form before compiling the tail: 3, 10, 15, 8 and
  2 checks (`~/for_claude/mlxf-review-2026-11-23/negative_controls_tiles/`).

**Exploratory timings: not the protocol.** The machine was loaded (load average 3 to 7); these are single
invocations of `bench_polar_table suite=shiftmap`, case 2500_4 at the run's grid, Release, GPU, full
precision. The profile is per stage, summed over both maps' 252 tiles.

| form | window maps/s | screen maps/s |
| --- | --- | --- |
| the run's (per-pair order-expanded products), Phase 5b | 2.59e4 | 8.40e3 |
| particle tiles, complex GEMM over the candidates, per-rotation phase DFT | 1.45e4 | 4.42e3 |
| packed real GEMM; phase, then fold and FFT over the directions | 1.94e4 | 8.76e3 |
| Z built packed; candidates gathered complex, then packed | 3.46e4 | 1.10e4 |
| fold as the sum of zero-padded FFTs over runs of orders | 4.28e4 | 1.12e4 |
| compiled selection and reduction (the current form) | 4.47e4 | 1.22e4 |

- *What did not work:*
  - the complex GEMM: M = nord nrho, K = nkb, N = 16 candidates; its batched small products took 3.4 s of
    6.2 s;
  - the per-rotation phase DFT over the orders, as a GEMM, took 2.1 s;
  - a resident packed copy of the references, whose candidate gather was slower (1.6 s) than gathering
    complex and packing.
- *The current profile* (s, both maps):
  - Z 0.39, the particle's order gather 0.13, the candidates' gather and packing 0.10;
  - the real GEMM 0.42, unpacking to complex 0.49;
  - the transform over m' 0.29, the order's phase 0.22, the fold and the direction transforms 0.42;
  - the final reordering 0.22.
- *Screen per map:* construction 71 µs, selection 5 µs, reduction 19 µs.
- *What is left:* unpacking and the reordering are the overheads a fused kernel would remove (section 9's
  Metal kernels).
- *Context only:* against SIMPLE's Phase 0 rates with estimated FFTW plans, the window is at 1.0 and the
  screen at 1.6.

**Final form verified** (2026-11-23 01:02, `~/for_claude/mlxf-review-2026-11-23/tiles_final/`):

- Debug and Release from scratch with warnings as errors: zero warnings, fast gate 8 of 8.
- `polar_table` 231 of 231 and `polar_shiftmap` 594 of 594, on both devices in both builds.
- The accuracy block: 192 of 192.
- The five negative controls fail again (3, 10, 15, 8 and 2 checks), restored byte for byte.

**Re-timing, 2026-11-23 01:14-01:43** (M2 Ultra; SIMPLE at the pin `67c6a05e2` of decision 22, measured FFTW
plans; full precision; each case waited for a load of at most 4; logs and TSVs in
`~/for_claude/mlxf-retime-2026-11-23/`, scripts `retime_a.sh`, `summary.txt`):

| measure | SIMPLE, 24 threads (r1, r2) | mlx-fortran, GPU (r1, r2) | ratio |
| --- | --- | --- | --- |
| shift maps, window (maps/s) | 4.41e4, 4.46e4 | 4.53e4, 4.49e4 (16 particles a tile) | 1.01 |
| shift maps, screen (maps/s) | 7.51e3, 7.54e3 | 1.21e4, 1.21e4 (16 particles a tile) | 1.60 |
| dense scoring, 2500_4 (pairs/s) | 2.30e6, 2.29e6 (`block_prod`, B 16) | 1.03e7, 9.85e6 (64 x 250) | 4.29 |

- *How the ratio is taken:* the slower GPU run over the faster SIMPLE run. It is context; the verdicts are
  Phase 6's.
- *The CPU baseline:* SIMPLE's measured plans changed none of its rates against Phase 0's estimated plans on
  this machine (4.46e4, 7.54e3, 2.30e6).
- *Against the run's form* (2.59e4, 8.40e3), the particle tiles are 1.73 times faster on the window and 1.44
  times on the screen.
- *Tile sizes:* 16 particles a tile is the fastest for both maps; 4 and 64 are 3 to 32 % slower.
- *Memory:* the MLX peak is 13 GB at 16 particles a tile.
- *Flags:* `tiles_shiftmap_r2` was flagged twice for other processes' CPU (406 and 639 % at one sample). Its
  three invocations agree with r1 within 1 %, and the table uses the last.

**The `mlx_bitcast` and `mlx_take` form (decision 26), 2026-11-23 01:48-01:52** (`retime_b.sh`, logs in
`verify_b/` and `cases/bitcast_shiftmap_r{1,2}/`):

- *Verified:* Debug and Release from scratch with warnings as errors, zero warnings, fast gate 8 of 8.
  `unit_ops` passes 389 checks, including `mlx_take` and `mlx_bitcast`; `polar_table` 231 and
  `polar_shiftmap` 594, on both devices in both builds. The accuracy block passes 192 of 192, and the five
  negative controls fail again (3, 10, 15, 8, 2).
- *Timed,* two invocations, both unflagged, on the same machine and case as the table above:
  - window 4.92e4 and 4.90e4 maps/s at 64 particles a tile: 1.10 times SIMPLE, and 9 % above the
    particle tiles before;
  - screen 1.31e4 and 1.28e4 at 16 particles a tile: 1.69 times SIMPLE, 5 % above.
- *Construction per screen map:* 54 µs (59 before). The MLX peak is 13 GB at 16 particles a tile.

**Open:**

- Kept from the earlier plan for this step:
  - SIMPLE at the new pin `67c6a05e2` (decision 22, measured FFTW plans): `shiftmap` and `block_prod`
    (2500_4) twice at 24 threads;
  - `bench_polar_table suite=shiftmap ptiles=4,16,64` and the canonical `suite=time` twice.

**What it means, in short.** Building the order expansion once per particle and reusing it across the
candidates, through one real GEMM, makes the GPU maps about 1.7 times (window) and 1.45 times (screen)
faster than the run's form, on a loaded machine. The decomposition is the candidate to carry into SIMPLE's
CPU code. The numbers become measurements at the re-timing.

