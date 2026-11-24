# mlx-fortran milestone 1: the Phase 1 follow-ups, the tiled polar pipeline and the shift maps

Current disposition, 2026-11-24: active contract and remaining work. Completed phase instructions
and Progress have moved to [the M2 delivery record](../completed/mlxf_milestone1_m2.md).
Decision numbers, this path and the file table remain stable for the run tooling. The full Phase 5c
contract below is retained because its performance exit is still open; implementation is already delivered.

Status, 2026-11-23: Phases 0 to 5b and the review fixes are delivered. Phase 5c's implementation and
correctness validation are delivered; benchmarking and the retention decision are deferred at the owner's
request. Phases 6 and 7 remain open. Review base: mlx-fortran `c93ee0d602fcd9d3f9d1c422c4d448a26f4f6f26`;
SIMPLE `0a8b0903eee151700305399e8e3ff53c2c21caae`. Decision 27 brings SIMPLE's committed shift-map
optimizations into the GPU model. No new throughput result is claimed.

Original launch record, 2026-11-22: Decisions 3 to 7 ruled by Hans as recommended;
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
    - *Evidence* (Codex's side-quest plan [`mlxf_m1_codex.md`](../completed/mlxf_m1_codex.md), Phase 4; M3 Pro, 2,000 particles, two
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
      Superseded by decision 27: SIMPLE adopted the per-order real-weight contraction, not this Z formulation.

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

27. (2026-11-23, Hans: the recent SIMPLE shift-map optimizations "need to become part of our toy modeling
    efforts"; Codex's review and proposed execution order) **Model the committed CPU optimizations before
    making custom Metal the next step.** Phase 5c is the graph-based follow-up, in this living plan.
    - *Baseline:* SIMPLE `0a8b0903eee151700305399e8e3ff53c2c21caae` replaces decision 22's
      `67c6a05e2` for future comparisons, including Phase 6. Keep the earlier measurements labelled by
      their actual pin. The CPU prototype's ratios in the fusing note are not results against this commit.
      Rebuild and measure `block_prod` and `shiftmap` with measured FFTW plans on the same Mac as the GPU.
    - *What transfers:* `gen_shiftmap_kernel` now contracts the complex shell products, viewed as
      interleaved reals, against real Bessel weights; it caches those weights, contracts only radii that
      retain an order, and packs the folded Hermitian half without a whole-map `gin` intermediate.
      `nharm` and the active-radius ranges are prepared once. SIMPLE's `shell_sums` row bound
      `SGEMM_ONE_THREAD_MNK=124999` is an OpenBLAS threading/identity constraint, not a GPU tile size.
    - *Keep particle reuse:* decision 25's shifted particle spectra remain reusable across candidates.
      Compare the current weighted-Z formulation with a bounded per-order formulation: gather
      `Y^[m'+n]` once per particle/order tile; form `R^[m'] Y^[m'+n]` in a candidate tile; contract its
      interleaved real/imaginary rows over shells against the real weights of the active radii. Stream
      order/candidate tiles instead of retaining a block-wide pair-by-order product. Preserve the
      `exp(-2 pi i n r / nrots)` correction after the m' transform. This is a measured alternative,
      not an assumption that the CPU's contraction wins on GPU matrix units.
    - *Do not equate zero weights with skipped work:* the current Z/GEMM spans every order/radius slot,
      including weights zeroed above `nharm(rho)`. Compare compact active ranges or groups with padding;
      report useful and executed order/radius slots and bytes. Retain padding only where it measures
      better. Decision 23's numerical truncation and the oracle caps stay fixed.
    - *Transform experiment using existing operations:* after the ring FFT and its phase correction,
      fold orders modulo `nalpha` in coefficient space. For the resulting F(n,r,rho), construct
      `H(n) = (conjg(F(n)) + F((-n) modulo nalpha))/2` for `0 <= n <= floor(nalpha/2)`, at each
      rotation/radius/pair. `mlx_irfft(H, direction_dim, n=nalpha, norm=MLX_FFT_NORMS%forward)` then
      gives the unscaled real forward direction transform. The zero-order half factor is already in
      the weights; do not apply it twice. This models SIMPLE's Hermitian packing without requiring
      an unimplemented 2D real-transform wrapper. Compare it with the current complex direction FFTs.
    - *Ownership:* all prepared tables and any active-range metadata belong to `polar_table` and its
      submodules. Weights already persist across `score_maps`; keep that reuse. A changed half, band,
      box/grid or shell-weight content must rebuild the dependent tables. Reference generations retain
      their existing checks. No module globals, SIMPLE types in the library or second resource owner.
    - *Requested work:* first correct profiling so `evidence=.false.` does not explicitly evaluate log
      evidence. Check the compiled graph's actual work too; copying fewer outputs alone is not proof.
      Keep the matched all-width/no-evidence benchmark. Also model SIMPLE's optional `width_cutoff`:
      loss strictly above the cutoff returns width -1 and skips moments; equality computes the width.
      Treat a supplied per-pair cutoff as an input, keep selection unchanged and report the survivor
      fraction. A synthetic cutoff experiment does not reproduce production's sequential best-so-far
      dependency or establish its width frequency. No per-pair host synchronization to decide the mask.
    - *Gates and verdict:* decision 17's fixed map/loss/evidence/variance bounds and exact lifecycle gates
      apply. Preserve canonical-schedule identity; changed tile shapes are judged by those bounds and
      clear-margin modes, not CPU/GPU byte identity. Retain a second computation path only under the
      existing measured gain above 30 percent rule; record losing experiments and remove their paths.
      Decisions 14 and 18 keep their 2.0-times CPU/GPU go thresholds. Metal remains separate follow-up
      work after the generic wrapper and fresh profiles justify it; the milestone verdict uses MLX ops.

Defaults taken without a question: Phase 5c's name and experiment order (reorder from its measured profile),
the folder and submodule names of decision 10, the vocabulary name
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
| 5c | test-model optimization; rounding may change | decision 27: unchanged oracle caps, requested-output and cache/refusal checks, matched baseline at SIMPLE `0a8b0903e`, graph experiments and two-invocation timings; budget 8 |
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

### Phases 0–5b, delivered

The completed instructions, calibration freezes and execution records are in
[the M2 delivery record](../completed/mlxf_milestone1_m2.md); the original run's report is
[the M2 batch report](../completed/mlxf_milestone1_m2_report.md). They are historical evidence, not
instructions to rerun completed implementation. Phase 5c's remaining measurements and Phases 6–7 follow.

### Phase 5c, SIMPLE's optimized shift maps in the GPU model (decision 27; implementation/validation)

Owner update, 2026-11-23: implement and validate now; defer all benchmarking until the machine is available.
The alternative graphs remain explicitly selected test-model experiments, with the weighted-particle/complex
FFT graph as the default control. This temporarily holds the measured-gain retention decision open; it does
not adopt either alternative or satisfy the performance exit. Preserve the benchmark commands and provenance
requirements below for the resumed measurements. No M2 or M5 performance conclusion follows from validation.

1. Freeze the source snapshots and artifacts: this review's mlx-fortran base, SIMPLE at decision 27's pin,
   compiler/MLX versions, machine, precision, case, grid, cutoff/evidence modes and tile dimensions.
   Run the base's Debug/Release fast gates and 64,000-pair accuracy gate. Fix the profiling mismatch before
   profiling alternatives, proving profile on/off returns the same requested results. Time the unchanged
   graph and refreshed SIMPLE baseline twice, with measured FFTW plans and preparation outside the warm loop.
2. Add the contract cases to `polar_shiftmap`, including changed shell weights with unchanged references,
   changed grid/band and half, zero radius, odd/even direction counts, Nyquist, orders wrapping beyond both
   ring and directions, duplicate/permuted candidates and partial tiles. The toy accepts ascending radii;
   test refusal of an unsorted list rather than silently assuming SIMPLE's broader contract. Use a compact
   direct-oracle sample at the actual benchmark shell/grid geometry as well as the small analytic fixtures;
   the expensive sample belongs to a manual accuracy mode of the same executable, not a new fast entry.
3. Measure the two contraction forms and the Hermitian direction transform separately and together.
   Start with particle tiles 4/16/64 (measured earlier), candidate tiles 4/8/16 and order tiles 1/4/8
   (guessed search grid, not an optimum); prune from the existing quarter-memory budget before allocation.
   Report host staging, prepared weights/references, live intermediates, MLX peak and process peak, as well
   as time. Do not replace the ring's 364-point transform with a padded transform without proving that the
   original rotation grid and normalization are recovered: padding alone changes the sampled problem.
4. Add the optional cutoff to the test-only request and oracle. Test disabled, none/some/all survivors,
   strict boundary equality and sentinel -1; preserve the tempered mode and physical-temperature moments.
   Benchmark all-width/no-evidence for the matched verdict, and cutoff/evidence cases separately. A CPU
   cutoff throughput ratio requires the same cutoff inputs and outputs on both sides; otherwise report GPU
   sensitivity and the production-profile width fraction as unmeasured, not as an equivalent-work speedup.
5. On the same Mac, warm up, best of three, two invocations, load recorded, full precision; interleave the
   candidate and incumbent. Include input construction, evaluation and copy-out, report preparation/cold
   compilation separately. Keep only justified paths, archive negative results and refresh the fusing note
   from the final requested-output profile. The current graph is the control; no assumed Metal speedup.

Exit: Debug and Release fast gates, 64,000-pair accuracy and the expanded shift-map suite pass on CPU/GPU;
negative controls fail for phase sign, omitted Nyquist/folding contribution, zero returned loss, stale
weights and wrong cutoff inequality; no caps relaxed, lifecycle exact, budget 8, zero warnings. Baseline
and candidate rows identify both commits and work modes, include both maps and the two runs, and obey the
memory budget. Record a measured winner or a negative result. Phase 6 repeats against this SIMPLE pin.

### Phase 6, the M5 Ultra (run `mlxf_m1_m5`)

1. Record the machine and dependencies as in Phase 0 step 1, with the GPU's `architecture` as
   `unit_core` prints it and the macOS version: the NAX preconditions of `doc/how2s/how2set_up_dev.md`,
   section 6. MLX reports no NAX-in-use key, so NAX use is stated only from a Metal capture of the
   workload; without one it is recorded as unproven, never inferred from the architecture.
2. Build Debug and Release from scratch at Phase 6's base. Run the fast gate, `recovery_half` (if
   decision 3 is ruled yes), `unit_kernels suite=polar_table` and `suite=polar_shiftmap` on both devices,
   and `bench_polar_table suite=accuracy`. The frozen bounds of Phases 4a, 5a and 5b-a are unchanged.
3. Repeat [the archived Phase 0](../completed/mlxf_milestone1_m2.md) steps 3 to 5 and 7 there:
   the SIMPLE pin (decision 27), `block_prod` twice per dense
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
| `src/test/mlxf_kernel_polar_table.f90`, `src/test/mlxf_kernel_polar_table_lifecycle.f90`, `src/test/mlxf_kernel_polar_table_shiftmap.f90`, `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90` | decision 27: owned active-range metadata, graph experiments, requested outputs/cutoff, independent tests | 5c |
| `src/test/mlxf_test_defs.f90`, `src/test/mlxf_bench_polar_table.f90`, `src/test/mlxf_test_registry.f90` | decision 27: test-only requests/tunables, benchmark provenance and work counts, manual accuracy dispatch if needed | 5c |
| `doc/policies/test_environment_policy.md` | decision 27's manual accuracy and work modes; no new CTest entry | 5c |
| `doc/implementation_notes/planned/mlxf_fusing_note.md` | fresh profile and remaining kernel candidates; roadmap only | 5c |

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
- **packaging for consumers**: delivered in [laptop preparation Phase 3](../completed/mlxf_m5_preparation.md),
  including `mlxf::mlxf`, compiler checks, an external consumer and `scripts/check_install.sh`; combined
  parity integration remains in the preparation follow-up;
- **SIMPLE's integration plan**, if the verdict is go or lead and Hans rules it.

## Progress

### Delivered implementation and validation, through 2026-11-23

Phases 0–5b, the review fixes, particle-shift reuse and Phase 5c implementation/validation are recorded in
[the completed M2 record](../completed/mlxf_milestone1_m2.md). Its entries preserve the frozen calibration
values, source pins, measurements, negative results and limitations. The stronger regression tests and
consumer package are recorded in [the completed laptop preparation](../completed/mlxf_m5_preparation.md).

### Remaining work, 2026-11-24

- Phase 5c: benchmarks, requested-output profiling, tile selection and the retention decision remain deferred.
- Phases 6–7: the M5 run and final milestone report/verdict are pending; the M2 report is not the final report.
- Launch auditing and combined parity integration are tracked in
  [the preparation follow-up](mlxf_m5_preparation.md).

Append new execution evidence here. Completed records are linked above rather than duplicated.
