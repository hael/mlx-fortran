# mlx-fortran: parity with mlx-c

Status, 2026-11-23: Phase 0 complete (interactive, decision 23); Phase 1 complete (run `mlxf_parity`);
Phases 2 and 3 run next in the same run (decision 25); Phases 4 to 9 planned.
Decisions 1 to 4 ruled by Hans on 2026-11-23 as recommended. The run waits for its base, the maintainer's commit that closes milestone 1 (Phase 7 of `mlxf_milestone1.md`, run `mlxf_m1_m5`), and the run
records its hash. Written against `309807c` plus the unstaged review of run `mlxf_m1` (2026-11-23), and
against mlx-c `v0.8.0` (`a26f2d5`, `~/src/mlx-c`) with MLX 0.32.4. Supersedes: none. Depends on: the handle
model and the generated C layer (validated: yes, design plan Phase 1 and milestone 1 Phases 1 to 3); the
operation helpers of `mlxf_array_operations` (validated: yes, milestone 1 Phase 2); `mlx_function` and its
trampoline (validated: yes, milestone 1 Phase 3); a Mac with a GPU (validated: yes, M2 Ultra).

## 1. Why

mlx-c is the reference for what MLX offers outside Python and C++. The generated layer of mlx-fortran already
binds all of it: 680 prototypes, each either generated or skipped for a stated reason, checked against an
independent list on every build. The hand-written Fortran layer exposes 40-odd public names and calls 128 of
those C functions. The reading below (section 2) puts about 230 of the 680 behind the handle model as
plumbing, about 35 outside any Fortran API, and leaves about 335 with no Fortran counterpart: 222 in
`ops.h`, all of `linalg`, `random`, `transforms` (gradients), `fast` (custom Metal kernels, attention, norms),
`io`, `export` and `distributed`, and 10 of 16 FFTs. A Fortran user who reads mlx-c's documentation cannot
yet do most of what it shows. Parity makes mlx-fortran a general Fortran front end for MLX, which is the
public half of its purpose. It also builds most of what milestone 2 asks for in advance (gather, scatter,
n-dimensional FFTs, PCG pieces), and it builds that under one set of rules rather than one pipeline at a time.
Size is a hypothesis to be measured: about 260 new public names once the `_axis`/`_axes` variants collapse
into one generic each. Phase 0 counts them exactly.

## 2. Contract

### Layers

Unchanged. The generated `bind(c)` layer (`build/gen/`) is not edited and its generator is not changed. Every
new public procedure is a hand-written wrapper in `src/core/<capability>/` that calls a generated `mlxc_`
procedure through a signature helper of the `mlxf_array` family (skill `mlxf-binding`, section 3). It is
re-exported by `mlxf.f90` only. New behaviourless records and vocabularies go in `src/defs/mlxf_defs.f90`.

### Invariants

- **Additive.** No existing public name changes its signature or results. Every existing test keeps its
  assertions and passes, and the kernels area keeps its counts (polar_table, polar_shiftmap, accuracy) on
  both devices.
- **The handle model is untouched.** The registry, `mlxf_array_lifetime`, the defined assignment and `final`
  of `mlx_array` do not change. A new type that holds an MLX object other than an array (stream, group,
  Metal kernel, gradient function, imported function) copies the pattern of `mlx_function`: a private handle
  and serial, `registry_add` with its own key, a guarded `impure elemental` assignment, and `new`/`kill`/
  `final`.
- **The Fortran view everywhere** (binding policy section 2). No public argument is a C-order shape, a 0-based
  axis, a 0-based index or position, or a row-major stride. The one exception stays the source text of a
  custom Metal kernel.
- **Errors as now** (binding policy section 6). Building a graph stops on error. Evaluation, data movement
  and the new file and distributed procedures take an optional `status`. A procedure that C++ calls never
  stops.
- **One submitting thread** and the entry first, on every new public procedure (rule `entry`).
- The library reads no environment variable of its own. `MLX_ENABLE_TF32` stays MLX's.

### What the reading found (2026-11-23, at `309807c` and mlx-c `a26f2d5`)

- The C functions the Fortran layer calls (`mlxc_` references under `src/core`, mapped to `mlx_`) are 128.
  They include `device_info_*`, `vector_array_*` and `closure_*` plumbing.
- A first classification by header and name pattern: about 228 plumbing (vector, map, string, closure,
  optional, io_types, `_new`/`_free`/`_set`/`_tostring`/`_equal`, `item_*`, node namers, kernel-config
  setters); about 29 excluded (CUDA, `detail_*`, thread-local and thread-unsafe streams, `_kwargs`, IO
  reader/writer vtables that the generator already skips); 8 quantisation and fp8 entries, excluded by decision 2;
  about 70 used for a public name; about 337 pending. This is a pattern count, not the ledger. Phase 0 writes
  the ledger name by name.
- mlx-c 0.8.0 has no public `vmap`; only `mlx_detail_vmap_replace` and `mlx_detail_vmap_trace`.
- `mlx_view` in `ops.h` is a dtype reinterpretation and collides with the existing `mlx_view` (a zero-copy
  Fortran view). `mlx_copy`, `mlx_array` and `mlx_stream` are also names the Fortran side holds or will hold.
- `mlx_print_graph` and `mlx_export_to_dot` take a C `FILE*`, which `mlxf_libc` can open.
  `mlx_load_safetensors` and `mlx_save_safetensors` pass dictionaries (`mlx_map_string_to_array`), and
  `mlx_fast_metal_kernel_new` takes `mlx_vector_string` names.
- The skill `mlxf-binding` (section 1) and `CLAUDE.md` ("the API grows only with a demonstrated need")
  forbid a wrapper that no pipeline uses. This plan needs decision 1 before it can run.

## 3. Decisions and rulings

Decisions 1 to 4 were ruled by Hans on 2026-11-23, each as recommended. None is taken under delegation.

1. (2026-11-23, Hans: yes) **Parity is a goal.** For every mlx-c function in the ledger's `public` class,
   the user-facing need is MLX's documented API, not a SIMPLE pipeline. The rule "no need, no wrapper" stays
   for anything outside the ledger. The ruling edits the skill `mlxf-binding` (section 1), `CLAUDE.md` (the
   sentence on growth) and the register `doc/architecture_principles.md` in Phase 0, in the same change as
   the ledger.
2. (2026-11-23, Hans: exclude) **Quantised matmuls and fp8** (`quantize`, `dequantize`,
   `quantized_matmul`, `gather_qmm`, `gather_qqmm`, `qqmm`, `to_fp8`, `from_fp8`) are excluded with the
   reason "inference formats with no Fortran data type".
3. (2026-11-23, Hans: before milestone 2) **Order with milestone 2.** Phases 1 to 5 run after milestone 1
   closes and before milestone 2 is converted to plan form, so milestone 2 consumes gather, scatter, `fftn`
   and linear algebra instead of building them. Phases 6 to 8 may run after or beside milestone 2 on a
   disjoint file table.
4. (2026-11-23, Hans: unattended arun on the M2 Ultra) **Execution.** One phase per run segment; the phases
   are mechanical and gate-checked. A hold follows Phase 3 so the maintainer can read the API before linear
   algebra and transforms.
5. **The ledger.** `scripts/mlxc_parity.txt` holds one line per name of the prototype list (680 at mlx-c
   0.8.0): `<mlx-c name> <class> <Fortran name or reason>`. Classes: `public` (a public Fortran name
   exists, with that name), `plumbing` (used only behind the handle model), `excluded` (with its reason),
   `pending <phase>`. Rule `parity` in `check_rules.py` fails when the ledger and the prototype list differ
   by a name, or a `public` name is not in `mlxf.f90`'s `public` lists. It also fails when a `pending` line
   names a phase the Progress has closed, or when the count of `pending` lines grows. The `pending` lines
   are a ledger that may only shrink.
6. **Names.** A wrapper keeps the Fortran intrinsic's name when the value semantics agree; the result being an
   array, and its kind following MLX's rules, does not count as disagreement. Otherwise it is
   `mlx_<mlx-c name>`, with `axis` read as `dim`. The table is fixed here and the run may not deviate:

   | mlx-c | Fortran | note |
   | --- | --- | --- |
   | `abs sin cos tan sinh cosh tanh log log10 exp sqrt erf` | same name | |
   | `arcsin arccos arctan arcsinh arccosh arctanh arctan2` | `asin acos atan asinh acosh atanh atan2` | `atan2(y, x)` order as Fortran |
   | `floor ceil trunc` | `floor ceiling aint` | result keeps the input's float kind |
   | `remainder` | `modulo` | sign of the divisor, as Fortran's `modulo`; checked in Phase 0 |
   | `power` | `operator(**)` | array and scalar on either side |
   | `logical_xor`, `equal` on booleans | `operator(.neqv.)`, `operator(.eqv.)` | |
   | `bitwise_and or xor invert`, `left_shift` | `iand ior ieor not shiftl` | integer arrays |
   | `right_shift` | `mlx_right_shift` | arithmetic on signed; Fortran's `shiftr` is logical |
   | `minimum`, `maximum` | `min`, `max` | |
   | `max min prod all any count_nonzero` (reductions) | `maxval minval product all any count` | `dim` optional |
   | `argmax`, `argmin` | `maxloc`, `minloc` | 1-based int32, first extremum |
   | `roll` | `cshift` | `cshift(a, shift, dim)` = `roll(a, -shift)`: Fortran's sign |
   | `round` | `mlx_round` | half to even, unlike `nint`/`anint` |
   | `sign` | `mlx_sign` | one argument (signum), unlike Fortran's `sign(a, b)` |
   | `inner`, `vecdot` | `mlx_inner`, `mlx_vecdot` | `dot_product` conjugates; whether `vecdot` does is a Phase 0 probe |
   | `linalg_norm_l2` along a dimension | `norm2` | real input; other norms `mlx_norm` |
   | `view` (dtype reinterpretation) | `mlx_bitcast` | `mlx_view` is taken |
   | `copy` | `mlx_copy` | a new graph node; assignment already shares |

7. **Axes.** The `_axis`, `_axes` and all-axes variants of a function collapse into one generic: an optional
   scalar `dim` or an optional array `dims` (both absent = every dimension). Dimension d of rank r is MLX axis
   `r - d`, and a list is translated element by element (skill `mlxf-binding`, section 4). `keepdims` is an
   optional logical, default false. `ddof` of `var`/`std` is an optional integer, default 0. A function whose
   MLX default is the last axis (softmax with an axis, the norms and `rope` of `fast`, attention) acts on
   Fortran dimension 1. The binding policy states this in Phase 1, before the first such wrapper.
8. **Indices and positions.** As binding policy section 2. Index arguments (`take`, `gather`, `scatter*`,
   `put_along_axis`, `argpartition`'s `kth`, `slice_update` starts, the dynamic slices) are 1-based and
   shifted inside the graph. Index results (`maxloc`, `mlx_argsort`, `mlx_argpartition`, `mlx_topk` indices,
   `mlx_searchsorted`, LU pivots) are 1-based int32. `mlx_searchsorted` returns positions 1 to n+1.
   Out-of-range indices are not checked; the documentation for `mlx_take_along_dim` is the model.
9. **Linear algebra in the Fortran view.** MLX sees the transpose of every Fortran matrix. The translation is
   fixed per function, and the run reports any function where it finds the table wrong:
   - free (no extra node): `inv`, `pinv`, `det`, `slogdet`, `tri_inv` (the `upper` flag flipped),
     `cholesky` and `cholesky_inv` (`upper` flipped), `eigvalsh` (`uplo` flipped), `norm` (dimensions
     translated), `cross` (dimension translated), `svd` (MLX's U and Vt swap roles: the Fortran U is MLX's
     Vt array read in the Fortran view, and the Fortran Vt is MLX's U);
   - one transpose node: `eigh` (eigenvectors), `qr`, `lu`, `lu_factor`, `solve`, `solve_triangular`, `eig`,
     `eigvals` (the input, so the eigenvectors are right eigenvectors of the Fortran matrix).
   A function that MLX 0.32.4 implements only on the CPU runs on the default CPU stream whatever the default
   device (unified memory, no copy). The list comes from a Phase 0 probe, never from belief. This internal
   stream choice is not an offer of explicit streams.
10. **Convolutions.** MLX's channels-last layouts read in Fortran order: input (C, W[, H[, D]], N), weight
    (C_in/groups, kW[, kH[, kD]], C_out), output (C_out, W', ...). Stride, padding, dilation and output padding
    are given per spatial dimension in Fortran order (W first) and reversed inside the wrapper. They travel
    in a spec record `mlxf_conv_spec` in `mlxf_defs` (five-dummy rule). `conv_general`'s flip and its
    separate input/kernel dilations are fields of the same record.
11. **Random.** `mlx_random_seed(seed)` sets MLX's global key. Every sampler takes an optional `key`
    (`type(mlx_array)`, from `mlx_random_key` or `mlx_random_split`) and a Fortran-order shape. A sample of
    Fortran shape (n1, ..., nr) has the bytes of MLX's sample of shape [nr, ..., n1] for the same key. The
    binding policy states this; the tests do not compare with Python.
12. **Transforms.** `mlx_value_and_grad(f, argnums)` returns a new type `mlx_grad_function` with `apply(inputs,
    values, grads[, status])`. `argnums` are 1-based positions in `inputs`. `mlx_vjp`, `mlx_jvp` take an
    `mlx_function` and arrays of handles. `mlx_custom_vjp`, `mlx_custom_function` (vjp and jvp only; the vmap
    closure is null) and `mlx_checkpoint` return `mlx_function`. `mlx_stop_gradient` and `mlx_depends` are
    operations. vmap is excluded ("mlx-c 0.8.0 exposes it only as `detail_`"). The callback rules of binding
    policy section 11 apply unchanged.
13. **Data types.** Transfers (`mlx_from`, `mlx_to`, `mlx_to_alloc`, `mlx_view`, `mlx_alloc`) gain
    `integer(int8)`, `integer(int16)` and `logical(c_bool)`, implemented in `mlxf_array_transfer` beside the
    existing kinds. That file is part of the transfer submodule, not of the handle model. Unsigned integers,
    float16 and bfloat16 exist on the device only (`mlx_astype` and new `MLX_DTYPES` entries). Fortran has no
    standard type for them, and the generator skips their scalar entry points. `mlx_item` returns a rank-0
    array's value for each transfer kind.
14. **Streams.** `type(mlx_stream)` (the handle invariant of section 2), `mlx_new_stream(device)`,
    `mlx_default_stream(device)`, `mlx_set_default_stream(stream)` and `mlx_synchronize(stream)` (an
    overload of the existing name). Operations take no stream argument; they use the default stream of the
    default device, as now. Thread-local and thread-unsafe streams are excluded (one submitting thread).
15. **IO.** `mlx_save(file, a)` and `mlx_load(file[, status])` handle `.npy`. `mlx_save_safetensors(file, names,
    arrays[, metadata])` and `mlx_load_safetensors(file, names, arrays[, status])` take a `character(len=*)`
    array of names and an array of handles. `mlx_load_gguf` returns arrays and names; its metadata is
    excluded ("typed metadata maps with no Fortran counterpart"). On disk the bytes are MLX's: a Fortran
    (m, n) array is a NumPy C-order (n, m) array, as in ordinary C interoperability. The binding policy states
    it.
16. **Export and import of functions.** `mlx_export_function(file, f, example_inputs[, shapeless])` and
    `type(mlx_imported_function)` with `apply`. The `_kwargs` variants are excluded ("Fortran has no keyword
    dictionaries").
17. **fast.** `mlx_layer_norm`, `mlx_rms_norm`, `mlx_rope`, `mlx_scaled_dot_product_attention` and
    `mlx_cross_entropy` act on Fortran dimension 1 (decision 7), with spec records where the arguments pass
    five. `mlx_gated_delta_update` is excluded unless its shape semantics fit one paragraph of the policy;
    the run decides that from the header and records the decision in Progress. The custom Metal kernel is a
    spec type `mlx_metal_kernel_spec` (name, input and output names, source, header, grid, threadgroup,
    template arguments, output shapes and dtypes in Fortran order, `ensure_row_contiguous`,
    `atomic_outputs`) and `type(mlx_metal_kernel)` with `apply` (binding policy section 9).
18. **Distributed.** `type(mlx_group)`, `mlx_distributed_init([backend, strict, status])`, `rank` and
    `size` (1-based rank), `split`, and the collectives `mlx_all_sum`, `mlx_all_max`, `mlx_all_min`,
    `mlx_all_gather`, `mlx_sum_scatter`, `mlx_send`, `mlx_recv`, `mlx_recv_like`. The gate tests the
    singleton group. A two-process test is reported, not gated (section 6).
19. **Leftovers.** `mlx_print_graph(arrays[, file])` and `mlx_export_to_dot(file, arrays)` use `mlxf_libc`'s
    `fopen`. `mlx_metal_start_capture(path)` and `mlx_metal_stop_capture()`. `mlx_device_is_available`.
    `mlx_memory_limit()` and `mlx_set_wired_limit`. Type-bound `a%nbytes()`, `a%itemsize()`. `mlx_enable_compile`,
    `mlx_disable_compile`, `mlx_set_compile_mode(mode)` with `MLX_COMPILE_MODES`. The metallib path setters
    are excluded ("build configuration, not API").
20. **Tests.** Each wrapper is tested on both devices against a plain Fortran double-precision oracle (skill
    `mlxf-binding`, section 7). Elementwise and reduction families use table-driven testers: an array of
    records holding a procedure pointer to the wrapper, a procedure pointer to the oracle, the input domain
    and the frozen tolerance. That makes one loop per family, not one test per name. Linear algebra is judged
    by residuals and orthogonality, never by comparing factors. Gradients are judged against analytic
    derivatives, never finite differences. Integer, boolean, index and shape results are exact.
21. **Test areas and budget.** New areas: `unit_random`, `unit_transforms`, `unit_io`, `unit_fast`,
    `unit_distributed`. `MLXF_CTEST_BUDGET` goes from 8 to at most 13; Phase 0 records the gate's time per
    area. Operations, linear algebra and FFTs grow inside `unit_ops`, `unit_linalg` and `unit_fft`.
22. **Upstream defects.** A function that crashes, throws through C, or disagrees with its documentation
    gets a numbered entry in `doc/collaboration/apple_questions.md` and a ledger line `excluded upstream
    defect, question <n>`. The phase continues. More than three such lines in one phase is a stop.
23. (2026-11-23, Hans: "Happy to do 1 & 2") **Phase 0 runs early and interactively**, while Codex carries out
    milestone 1's Phase 5c, on files disjoint from Phase 5c's table. Phase 0 adds checks and documents only.
    Phases 1 to 8 keep decisions 3 and 4: they run as arun on the M2 Ultra after milestone 1 closes.
    - Phase 0's build and gate measurements (per-area gate times, the Release clean build time twice) move to
      the start of Phase 1, at the run's base. Phase 5c's tree is in flux, so they would judge nothing.
    - Decision 5's classes gain `internal`: a C-level helper (vectors, maps, strings, closures, kernel
      configs, setters) with no Fortran counterpart and no call from the library yet. `plumbing` stays for
      functions the library calls. Rule `parity` keeps the two apart.
24. (2026-11-23, Hans: "a minimum version requirement without a hard fail") **mlx-c 0.8.0 is the ledger's
    minimum, not a pin.** Rule `parity` fails on headers of an older release. A newer release (CI's unpinned
    `brew install mlx-c`, for one) prints its added and removed names as warnings and passes. The ledger is
    brought up to that release in a later change. The release is read from Homebrew's Cellar path, the
    package config beside the headers, or the build's record. When none says, the build's record (0.8.0) is
    assumed and differences fail. CMake's version warning is unchanged.
25. (2026-11-23, Hans: "Run now, overlap OK"; "Parity Phases 1–3"; fast mode off) **Phases 1 to 3 run now**
    as arun `mlxf_parity` on the M2 Ultra, on base `4706ecb`. This replaces decision 3's "after milestone 1
    closes" for these three phases. Run `mlxf_m1_m5` measures `4706ecb` on the M5 independently and edits
    no source. The two diffs meet only in `README.md` and the history, merged by hand at review. The run
    ends at Phase 3's hold. Phases 4 to 9 keep decision 3. Phase 1 opens with the base measurements that
    decision 23 moved there. The file table lists phases one by one, because the run's fence reads only
    the numbers written.

Defaults taken without a question (cheap to veto): the ledger's path and format; the record names
`mlxf_conv_spec` and `mlx_metal_kernel_spec`; the new type names `mlx_grad_function`, `mlx_imported_function`,
`mlx_stream`, `mlx_group`; `mlx_bitcast`; `keepdims` and `ddof` as names; capability folders
`src/core/{random,transforms,fast,io,distributed}/`, with streams in `runtime/`.

## 4. Not in this plan

- Any change to the generated layer, its generator or the prototype lister. If a C type is unmapped, that is
  a stop.
- The handle model (registry, `mlxf_array_lifetime`, `mlx_array`'s assignment and `final`) and the existing
  public signatures.
- CUDA, Linux, flang, Windows, packaging (`mlxf::mlxf`, milestone 1 section 9).
- Performance work. No wrapper is tuned and no kernel is compiled for speed here. SIMPLE's kernels and
  benchmarks in `src/test/` are read-only.
- vmap, keyword-argument closures, IO through reader/writer callbacks, GGUF metadata, and anything decision 2
  excludes.
- Upstream changes to MLX or mlx-c. Read only: `~/src/mlx-c`, `~/src/mlx`, `~/src/SIMPLE`.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | tests-only and checks (ledger, rule `parity`, probes) | static gate with plants; base builds and gate unchanged |
| 1 to 8 | additive API | existing suites identical in assertions and passing on both devices; new tests on both devices; ledger `pending` count down by the phase's lines; Debug and Release with `MLXF_WERROR=ON` and zero warnings |
| 9 | documentation and report | static gate |

## 6. Acceptance

- **Tolerances (measured, then frozen).** For each floating-point family, sub-phase *a* runs the new tester
  on fixture seed 1 on both devices and records each function's largest error relative to `max(1, |ref|)`.
  It then freezes the tolerance at `max(2 × observed, 4 eps)` of the result kind in the tester and in
  Progress, before seeds 2 and 3 are judged in sub-phase *b*. Ceiling: 64 eps for float32 results (guessed).
  A function above it is a finding (decision 22), not a widened tolerance. CPU float64 results that MLX
  computes in float32 are held to the float32 bound and listed in the binding policy, as `exp` is now.
- **Linear algebra (literature, with a guessed constant).** Backward error `‖A − factors‖_F / ‖A‖_F ≤ 10 n
  eps` and orthogonality `‖QᵀQ − I‖_F ≤ 10 n eps` (Higham, *Accuracy and Stability of Numerical
  Algorithms*, for Householder QR and the symmetric eigensolver; the 10 is guessed). Inputs are seeded with
  condition number ≤ 1e3 for float32.
- **Random (literature).** For each sampler at 2^20 samples: mean and variance within 5 standard errors of
  the distribution's values (normal approximation; a false failure about 6e-7 per check). The same key gives
  identical bytes twice; split keys give samples that differ. `permutation` is a permutation of 1 to n.
- **Gradients (analytic).** `value_and_grad`, `vjp` and `jvp` of three fixed functions (a polynomial, `sum(exp(a
  * x))`, a `matmul` chain) against their closed-form derivatives, at the frozen float32 tolerance of the
  operations involved.
- **IO (exact).** Save and load round trips are byte-identical for every transfer kind and ranks 0 to 4. A
  `.npy` header written by the library reads back the reversed shape; this is checked by parsing the header
  in Fortran, with no Python.
- **Build and gate (guessed, frozen at Phase 0).** Release clean build time ≤ 2 × the Phase 0 time on the
  same machine. Fast gate total ≤ Phase 0 total + 30 s. Each new area ≤ 3 s in Release.
- **Reported, not gated.** A two-process `mlx_all_sum` on one Mac through MLX's ring backend (the run
  writes the command and the host file; the maintainer runs it); a Metal capture opened in Xcode; and the
  maintainer's read of the API at the hold after Phase 3.

## 7. Common rules and stop conditions

- No new public name outside the ledger. No ledger line moves from `pending` to `excluded` except under
  decisions 2, 12, 15 to 19 and 22.
- No tolerance or assertion is relaxed after its freeze, and no seed is changed to pass.
- Fix as you go, with a file table row before the edit. Dead code is proved by the compiler.
- Each phase updates the binding policy (section 10 and new sections) and the README's API table for its
  names; the policy is the truth, the plan is history.
- Every Fortran file touched goes through `restyle_fortran.py` and `format_use_blocks.py`.
- **Stops:** a Fortran-view translation that needs a copy not listed in decision 9; a C type the generator
  does not map; any edit to the handle model; a file outside the table; an existing test whose assertions or
  results change; a tolerance above the ceiling for more than three functions in one family; more than three
  upstream-defect lines in a phase; the budget or the build-time bound exceeded.
- **Gates no ruling may waive:** zero warnings in Debug and Release with `MLXF_WERROR=ON`;
  `scripts/check_tree.sh` including rule `parity`; both devices for every new floating-point test; the
  existing suites unchanged.

## 8. Phases

### Phase 0, the baseline and the ledger

Build Debug and Release on the base, run the fast gate, and record per-area times and the Release clean
build time (twice, for the spread). Write `scripts/mlxc_parity.txt` name by name for all prototypes. Add rule
`parity` with five plants (a missing name, an extra name, a `public` name not exported, a `pending` line of a
closed phase, a grown `pending` count) and show each one fails. Apply decision 1 to the skill, `CLAUDE.md`
and the register. Probes, each a scratch program whose output is recorded in Progress:

- which `linalg` functions refuse the GPU stream at MLX 0.32.4;
- the sign rule of `remainder`;
- `round` at .5;
- whether `vecdot` conjugates;
- the stability of `sort` and `argsort`;
- `searchsorted`'s side convention;
- whether `mlx_distributed_init` with no backend gives a singleton group.

Exit: the ledger has exactly the prototype list's names; `check_tree.sh` passes and each plant fails; the
probes are in Progress; base gates pass with their counts recorded.

### Phase 1, elementwise

The unary and binary operations, `clip`, `nan_to_num`, `isnan`/`isinf`/`isfinite`/`isposinf`/`isneginf`,
`isclose`, `allclose`, `array_equal`, `**`, `.eqv.`/`.neqv.`, the bitwise family, `sigmoid`, `square`,
`reciprocal`, `rsqrt`, `expm1`, `log1p`, `log2`, `logaddexp`, `erfinv`, `degrees`/`radians`, `divmod`,
`floor_divide`, `stop_gradient`, `mlx_copy`, `mlx_bitcast`, `full`/`ones`/`*_like`, `mlx_round`, `mlx_sign`.
Sub-phases 1a (calibrate, freeze) and 1b (judge).
Exit: no `pending 1` line; `unit_ops` passes on both devices; tolerances frozen in Progress before 1b.

### Phase 2, reductions, scans, sorting and shape

Every `_axis`/`_axes` family (decision 7): `maxval`, `minval`, `product`, `all`, `any`, `count`, `mlx_mean`,
`mlx_var`, `mlx_std`, `mlx_median`, `maxloc`, `mlx_logsumexp` (extended to `dims`), the scans (`cumsum`,
`cumprod`, `cummax`, `cummin`, `logcumsumexp`, with `reverse` and `inclusive`), `mlx_softmax`,
`mlx_sort`/`argsort`/`partition`/`argpartition`/`topk`. The shape operations: `squeeze`, `expand_dims`,
`flatten`, `unflatten`, `broadcast_to`, `broadcast_arrays`, `tile`, `repeat`, `pad`, `flip`, `cshift`,
`moveaxis`, `swapaxes`, `split`, `stack`, `unstack`, `atleast_*`, `diag`, `diagonal`, `trace`, `tril`,
`triu`, `tri`, `eye`/`identity`, `linspace`, `meshgrid`, the window functions, `diff`, `contiguous`.
Sub-phases 2a/2b. Exit: no `pending 2` line; `unit_ops` passes on both devices.

### Phase 3, indexing and data types

`take`, `gather`, `scatter` and its `add`/`max`/`min`/`prod` forms, `put_along_axis`, `masked_scatter`,
`slice_update` and its reduction forms, `slice_dynamic`, `slice_update_dynamic`, `searchsorted`, `unique`, `split_sections`.
Also the transfer kinds and `mlx_item` of
decision 13, and the device-only dtypes. Exit: no `pending 3` line; `unit_ops` and `unit_array` pass on
both devices; the leak gate of `unit_array` covers the new kinds. **Hold:** the maintainer reads the API.

### Phase 4, linear algebra, products and convolutions

All of `linalg` (decision 9, with the Phase 0 CPU list), `einsum`, `tensordot`, `mlx_inner`, `mlx_outer`,
`mlx_kron`, `mlx_vecdot`, `mlx_addmm`, `block_masked_mm`, `segmented_mm`, `gather_mm`,
`hadamard_transform`, and the convolutions (decision 10). Exit: no `pending 4` line; `unit_linalg` passes
on both devices by the residual bounds.

### Phase 5, FFTs and random

`fftn`, `ifftn`, `rfft2`, `irfft2`, `rfftn`, `irfftn`, `fftshift`, `ifftshift`, `fftfreq`, `rfftfreq`, and all
of `random` (decision 11). Exit: no `pending 5` line; `unit_fft` and `unit_random` pass.

### Phase 6, transforms, compilation controls, export

Decision 12, the compile controls of decision 19, and decision 16. Exit: no `pending 6` line;
`unit_transforms` passes on both devices; `unit_compile` unchanged.

### Phase 7, fast and custom Metal kernels

Decision 17. The Metal kernel test is a kernel that adds 1-based column indices to a float32 array, checked
exactly. Exit: no `pending 7` line; `unit_fast` passes on the GPU, and its CPU half where MLX supports the
CPU.

### Phase 8, IO, streams, distributed and the rest

Decisions 14, 15, 18 and 19. Exit: no `pending` line remains in the ledger; `unit_io`, `unit_distributed`
pass; the reported-not-gated commands are written in Progress.

### Phase 9, the report

`mlxf_mlxc_parity_report.md` in the order of `how2write_agent_plans.md` section 8: the ledger's final counts
by class, every exclusion with its reason, the upstream questions, the frozen tolerances, and build and gate
times against Phase 0. Exit: the report exists; `check_tree.sh` passes.

### File table

| File | What | Phases |
| --- | --- | --- |
| `scripts/mlxc_parity.txt` | the ledger (new) | 0, 1, 2, 3, 4, 5, 6, 7, 8 |
| `scripts/check_rules.py` | rule `parity`; `ENTRY_HELPERS` for new helpers | 0, 1, 2, 3, 4, 5, 6, 7, 8 |
| `scripts/probes/mlx_behaviour_probe.c` (new) | Phase 0's probes of MLX behaviour, re-run on a new MLX release or Mac; Phase 4 adds the linalg functions left unprobed | 0, 4 |
| `scripts/probes/expm1_gpu_probe.c` (new) | ruling R4: the GPU `expm1` defect's probe, quoted by the Apple entry | 1 |
| `.github/skills/mlxf-binding/SKILL.md`, `CLAUDE.md`, `doc/architecture_principles.md` | decision 1 | 0 |
| `src/core/array/mlxf_array.f90`, `mlxf_array_operations.f90` | interfaces and new signature helpers | 1, 2, 3, 4, 5, 6, 7, 8 |
| `src/core/array/mlxf_array_transfer.f90`, `mlxf_array_tester.f90` | decision 13 | 3 |
| `src/core/array/mlxf_array_tester.f90` | the use-block form the static gate checks (one line of the launch edit) | 1 |
| `src/core/ops/*` (existing and new submodules `mlxf_ops_math`, `mlxf_ops_index`, `mlxf_ops_sort`) | operations | 1, 2, 3, 4 |
| `src/core/linalg/*` | linear algebra, products, convolutions | 4 |
| `src/core/fft/*` | FFTs | 5 |
| `src/core/random/*` (new) | random | 5 |
| `src/core/transforms/*` (new), `src/core/compile/*` | transforms, compile controls, export | 6 |
| `src/core/fast/*` (new) | fast, Metal kernels | 7 |
| `src/core/io/*`, `src/core/distributed/*` (new), `src/core/runtime/mlxf_stream.f90` (new), `src/core/runtime/mlxf_device.f90`, `mlxf_memory.f90`, `mlxf_libc.f90` | decisions 14, 15, 18, 19 | 8 |
| `src/core/<dir>/<dir>.inf` | per new or changed folder | 1, 2, 3, 4, 5, 6, 7, 8 |
| `src/defs/mlxf_defs.f90` | spec records, vocabularies | 1, 2, 3, 4, 5, 6, 7, 8 |
| `src/core/mlxf.f90` | re-exports | 1, 2, 3, 4, 5, 6, 7, 8 |
| `src/test/mlxf_test_utils.f90`, `src/test/mlxf_test_defs.f90` (if needed) | assertions for the table-driven testers; frozen tolerances | 1, 2, 3, 4, 5, 6, 7, 8 |
| `src/test/mlxf_test_registry.f90`, `test/CMakeLists.txt`, `scripts/run_fast_gate.sh` (if needed) | areas, budget | 1, 2, 3, 4, 5, 6, 7, 8 |
| `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md` (if needed) | the contract | 1, 2, 3, 4, 5, 6, 7, 8 |
| `README.md` | API table | 1, 2, 3, 4, 5, 6, 7, 8 |
| `doc/collaboration/apple_questions.md` | decision 22 | 0, 1, 2, 3, 4, 5, 6, 7, 8 |
| `doc/history/2026-11.md`, `doc/history/2026-12.md` | delivered batches | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 |
| this plan (Progress), `mlxf_mlxc_parity_report.md` (new) | record | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 |

## Progress

(One entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was
met, frozen numbers, log paths, decisions taken under delegation, what it means in short.)

*Before launch, 2026-11-23 (Claude, on Hans's ruling).* `mlx_take` (Phase 3) and `mlx_bitcast` (decision 6)
entered the library early, with milestone 1's decision 26, for the shift maps. They follow this plan's
conventions: decision 6's name, and decision 8's one-based, unchecked indices. Phase 0's ledger lists both as
`public`; Phases 1 and 3 have nothing left to do for them.

### Phase 0, the ledger, rule `parity` and the probes: 2026-11-23 (interactive, Claude; decision 23) - complete

- *Machine and base.* The M2 Ultra through the build bridge, for the probes only. Working tree on `c93ee0d`
  with Codex's Phase 5c edits in progress (milestone plan, fusing note, history). Phase 0 touched none of them.
  MLX 0.32.4, mlx-c 0.8.0 (Homebrew), headers also read from the `v0.8.0` clone (`a26f2d5`).
- *Files.* `scripts/mlxc_parity.txt` (new), `scripts/check_rules.py` (rule `parity`), `scripts/check_tree.sh`
  (rule list), `.github/skills/mlxf-binding/SKILL.md` (section 1), `CLAUDE.md` (the growth sentence),
  `doc/architecture_principles.md` (section 4), this plan (decision 23, Progress). No Fortran file.
- *The ledger.* 680 lines, one per prototype: 60 `public`, 46 `plumbing`, 147 `internal`, 88 `excluded`,
  339 `pending`. Pending lines by phase: 1: 65, 2: 111, 3: 35, 4: 40, 5: 29, 6: 16, 7: 9, 8: 34.
  `PARITY_PENDING = 339`. The excluded reasons are decision 2 (8 quantised and fp8 functions), CUDA (14),
  `detail_` (6, vmap among them), vmap closures (6), keyword-argument closures and exports (9), reader/writer
  vtables (12), float16/bfloat16 and unsigned scalars (12), GGUF metadata (9), thread-local and
  thread-unsafe streams (6), stream registry management (2), custom distributed backends (2), metallib paths (2).
- *Rule `parity`.* It compares the ledger with the headers it finds (MLXC_ROOT, `.deps/install`, Homebrew)
  or the build's `build/gen/mlxc_prototypes.txt`. Checks: classes, a public name in `mlxf.f90`'s public
  block (the type for `T%b`), public/plumbing exactly when the library calls the function, pending lines
  only in phases Progress has not closed, and the pending ratchet. Seven plants on a scratch copy, each
  failing with its own message and the restored copy passing: a missing name, an extra name, a public name
  not exported, a pending line in a closed phase, a grown pending count, a called function classed
  `internal`, and a `plumbing` function the library does not call. `scripts/check_tree.sh` passes on the
  working tree, against the build's list and against the `v0.8.0` headers.
  Decision 24's version handling was tested on copies of the `v0.8.0` headers with one added prototype. In
  a Cellar-style `mlx-c/0.9.0` path it gives a warning and passes. In `mlx-c/0.7.0` it fails as older than the
  minimum. In a path that names no release, the build's 0.8.0 record applies and the difference fails.
- *Decision 1 applied.* The skill's section 1, `CLAUDE.md` and the register's section 4 say the ledger is the
  need for its pending functions; outside it, no need, no wrapper. `check_guide_imports.py` passes.
- *Probes* (`scripts/probes/mlx_behaviour_probe.c`, C against Homebrew's mlx-c, both streams; bridge jobs
  `20261123-141715` and `20261123-142501`, `-Wall` clean; its header has the build line):
  - `remainder` takes the divisor's sign on both devices, float32 and int32: `[-7, 7, -7, 7] % [3, -3, -3, 3] =
    [2, -2, -1, 1]`. That is Fortran's `modulo`, so decision 6's name holds.
  - `round` rounds half to even: `[.5, 1.5, 2.5, -.5, -1.5] -> [0, 2, 2, -0, -2]`. `mlx_round` holds;
    `anint` would differ.
  - `vecdot` conjugates its first operand (`[i]·[i] = 1`); `inner` does not (`-1`). So `vecdot` along one
    dimension is Fortran's `dot_product`. *Finding for Phase 4:* rank-1 `dot_product(a, b)` can map to
    `mlx_vecdot` under decision 6's rule, with `mlx_vecdot(a, b, dim)` for the batched form. The ledger keeps
    `mlx_vecdot` until Phase 4 decides.
  - `argsort` is stable on both devices: `[1,0,1,0,1,0] -> [1,3,5,0,2,4]`, and 4,096 alternating ties stay in
    order. Larger sizes are not probed; Phase 2 tests stability at its own sizes before the policy claims it.
  - `searchsorted` sides are NumPy's: left `[0,1,4]`, right `[0,3,4]` for `[1,2,2,3]` and `[0,2,4]`. Plus 1
    gives decision 8's positions 1 to n+1.
  - *Linear algebra on the GPU stream:* every `linalg` function probed refuses it ("not yet supported on the
    GPU. Explicitly pass a CPU stream"): inv, pinv, cholesky, cholesky_inv, tri_inv, qr, eigh, eigvalsh, eig,
    eigvals, lu, lu_factor, solve, solve_triangular, det, slogdet, svd. `norm_l2` runs on the GPU;
    `norm`, `norm_matrix` and `cross` were not probed. All run on the CPU stream. Decision 9's CPU-stream rule
    therefore covers every factorisation and solve; Phase 4 probes the three left before it relies on them.
  - `mlx_distributed_init(strict=false, no backend)` gives a singleton group, size 1, rank 0, and
    `mlx_distributed_is_available(NULL)` is true. Decision 18's gated test of the singleton group holds.
- *Not done here (decision 23):* the base build and gate measurements move to Phase 1.
- *History.* The entry is left to Hans's next history edit: Codex is editing `doc/history/2026-11.md` for
  Phase 5c, and two writers on one file would race. The text: "Parity Phase 0 (Claude, interactive): ledger of
  680 mlx-c functions with rule `parity` (7 plants), decision 1 applied to the skill, `CLAUDE.md` and the
  register; probes: modulo, half-to-even, vecdot conjugates, stable argsort, NumPy searchsorted, linalg
  CPU-only except norm, singleton distributed group."
- *What it means, in short:* the parity plan now has a checked inventory. Every later phase is measured by
  pending lines going to zero under a gate, and the probes settled the open semantic questions of decisions 6,
  8, 9 and 18 before any wrapper is written.

### Phase 1, the base measurements: 2026-11-23 15:54 EST (run mlxf_parity, Claude)

- *Machine and base.* FWM-S116118, the M2 Ultra (24 cores, 192 GB, macOS 26.7.3), Homebrew GFortran 16.2.0
  (`gfortran-16`), CMake 4.2.1, Homebrew MLX 0.32.4 and mlx-c 0.8.0. HEAD `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47`;
  launch `git status --short`: ` M doc/history/2026-11.md`, ` M doc/implementation_notes/planned/mlxf_mlxc_parity.md`,
  ` M src/core/array/mlxf_array.f90`, ` M src/core/array/mlxf_array_tester.f90`, the four launch edits of
  ruling R2 (decision 25 and the file table here, Codex's history entry, a one-line use-block alignment in the
  two array files). The run keeps them and builds on them.
- *Builds (ruling R1).* The plan's `compile_debug.sh` and `compile_clean.sh` are replaced by hand-configured
  trees with the same options: `cmake -S <src> -B <tree> -DCMAKE_BUILD_TYPE=<type> -DBUILD_TESTS=ON
  -DFORTLS=OFF -DMLXF_WERROR=ON -DCMAKE_INSTALL_PREFIX=<tree>`, `cmake --build <tree> -j 12`,
  `scripts/run_fast_gate.sh <tree>`, install. The base is `git archive HEAD` in
  `scratch/keep/base_src`; four trees from scratch, serial, nothing else of the run's running
  (`scratch/scripts/base_measure.sh`, log `scratch/logs/base_measure.log`, per-step logs
  `scratch/keep/base_meas/`; paths under `/Users/elmlundho/agent_work/arun/mlxf_parity`). Zero warnings in all
  four builds. The first `unit_core` reports `GPU devices: 1`.
- *Release clean build, configure plus build, wall:* 13.14 s (3.94 + 9.21; load 3.3 before, 4.5 after) and
  16.06 s (6.20 + 9.86; load 15.5 before, 17.6 after: the one-minute average still carried the preceding
  gate and kernel runs of the script). Debug: 8.89 s and 8.91 s.
- *Fast gate, per entry (s), Release run 1 / run 2:* unit_array 10.97 / 12.27, unit_kernels 8.49 / 5.18,
  unit_compile 0.99 / 0.30, object_contracts 0.90 / 0.75, unit_ops 0.57 / 0.30, unit_core 0.49 / 0.38,
  unit_linalg 0.33 / 0.24, unit_fft 0.33 / 0.27; total real time 11.0 / 12.3 s (budget 60 s). Debug totals
  11.1 / 14.7 s.
- *Assertion counts, both devices in one process (all four builds alike):* unit_core 82, unit_array 128,
  unit_ops 389, unit_linalg 32, unit_fft 57, unit_compile 63, unit_kernels 1539; object_contracts passes.
  unit_core gave 80 once (Release run 1): its registry sub-suite adds two checks only when the allocator
  reuses a freed address (35 or 37 checks), a property of the base, not of the run. Per device (Release run 2,
  `device=cpu` / `device=gpu`, device-independent checks counted in each): core 55 / 55, array 70 / 69,
  ops 246 / 143, linalg 17 / 15, fft 29 / 28, compile 32 / 32, kernels 781 / 765.
- *Frozen bounds (section 6), from these numbers:* Release clean build (configure plus build, from scratch,
  `-j 12`) at most **29.2 s**, twice the mean 14.6 s of the two runs. Fast gate total real time in Release
  at most **41.7 s**, the mean 11.65 s plus 30 s. A new area at most 3 s in Release.

### Phase 1a, the elementwise calibration: 2026-11-23 16:09 EST (run mlxf_parity, Claude)

- *How.* `mlxf_ops_math_tester` (the unary and binary families) built in Debug with its seed list held to the
  calibration seed alone, run as `mlxf_test_exec test=unit_ops suite=ops_math device=cpu` (log
  `scratch/logs/phase1a_calibration_cpu_seed1.log`, table `scratch/keep/phase1a_errors.txt` and
  `scratch/keep/phase1a_frozen.txt`). 1,024 points per function from its domain, rounded once to float32; error
  relative to `max(1, |reference|)` against plain Fortran real64 oracles. No GPU run and no seed 2 or 3 before
  this entry. The integer, predicate and constructor families are exact and need no calibration.
- *Observed on seed 1, CPU (float32 / float64), in float32 epsilons (2^-23):* every function at most 3.2 eps32
  in float32, so none reaches the 64 eps ceiling and there is no finding. Largest: `erf` 3.19, `tan` 1.31,
  `mlx_erfinv` 1.28, `asin` 1.25, `asinh` 1.15, `mlx_log2` 1.14, `mlx_log1p` 1.10, `acos` 1.03, `mlx_rsqrt` 1.01;
  the rest below 1. Exact (0): `abs`, `floor`, `ceiling`, `aint`, `mlx_round`, `mlx_sign`, `mlx_stop_gradient`,
  `mlx_copy`, unary `+`, `min`, `mlx_floor_divide`, `mlx_divmod` (both results). In float64 every function is
  within 2 eps64 except six that MLX 0.32.4 computes in float32 on the CPU: `sin` 0.45, `cos` 0.46, `erf` 3.19,
  `mlx_sigmoid` 0.17, `mlx_erfinv` 1.28 and `mlx_logaddexp` 0.23 eps32.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`ELEM_TOLERANCES`), `max(2 x observed, 4 eps)` of the result kind:
  float32 `erf` 7.614142292e-07, every other function the floor 4 eps32 = 4.768371582e-07; float64 the floor
  4 eps64 = 8.881784197e-16, except the six float32-computed functions, held to the float32 bound: `erf`
  7.614142292e-07, `sin`, `cos`, `mlx_sigmoid`, `mlx_erfinv`, `mlx_logaddexp` 4.768371582e-07. The same
  float32 tolerances judge the GPU in 1b.
- *The stop, and ruling R4 (Hans, 2026-11-23, received 22:46 EST).* The run's phase note had 1a calibrate on
  the CPU only; section 6 says seed 1 on both devices. 1b (16:12 EST, `scratch/logs/phase1b_unit_ops_debug.log`)
  then failed GPU `erf` (6.331 / 6.512 / 6.501 eps32 on seeds 1 / 2 / 3 against the frozen 6.387) and GPU
  `mlx_expm1` (168.2 eps32 on every seed), and the run stopped (16:15). R4: freeze by section 6 over both
  devices; keep `mlx_expm1` with its GPU defect documented and a separate named bound. **The GPU seed-1
  values below were observed before R4, in the same run that already showed seeds 2 and 3.**
- *Re-frozen under R4 (22:50 EST), `max(2 x the larger of the CPU and GPU seed-1 errors, 4 eps)`:* only `erf`
  changes, float32 **1.509527616e-06** (12.66 eps32, from GPU 7.547638081e-07); its float64 bound stays
  7.614142292e-07. Every other function's GPU seed-1 error is below 2 eps32 (largest `acos` 1.48, `cosh` 1.28,
  `mlx_log1p` 1.28), so its floor stands. `mlx_expm1` keeps its section 6 float32 tolerance on the CPU (the
  floor); its GPU float32 results are held to `ELEM_GPU_EXPM1` = **4.010555858e-05** (336.4 eps32), twice the
  GPU's seed-1 maximum 2.005277929e-05 (same log; the 1a log holds the CPU only). Question 20 of
  `doc/collaboration/apple_questions.md`, with `scripts/probes/expm1_gpu_probe.c`, reports the defect: the GPU
  error grows from about 20 eps32 at x = 0.5 to 168 at x = 9.9 while GPU `exp` stays below 1.
- *Re-judged (22:52 EST, Debug, both devices, seeds 1 to 3):* `unit_ops` 1,532 of 1,532
  (`scratch/logs/phase1b_rejudge_unit_ops_debug.log`): GPU `erf` 6.51 eps32 at most, GPU `mlx_expm1` 168.23.

### Phase 1, elementwise: 2026-11-23 (run mlxf_parity) - complete

- *Machine and base.* FWM-S116118, the M2 Ultra; HEAD `4706ecb` plus the launch edits of R2 (see the base
  measurements entry). Rulings applied: R1 (hand-configured build trees), R2 (launch edits), R3 (the timings
  are re-judged at the end of Phase 3; the numbers here are context), R4 (calibration on both devices, GPU
  `expm1`).
- *Files.* `src/defs/mlxf_defs.f90` (`mlxf_close_spec`, `mlxf_nan_spec`, `mlxf_shape_spec`);
  `src/core/array/mlxf_array.f90` and `mlxf_array_operations.f90` (six signature helpers, `mlxf_close_op`,
  `mlxf_compare_op`, `mlxf_nan_op`, `mlxf_binary_vector_op`, `mlxf_full_op`, `mlxf_binary_int_op`, and the
  type-bound `**`, `.eqv.`, `.neqv.`, unary `+`); `src/core/ops/mlxf_ops.f90` and the new submodules
  `mlxf_ops_math.f90`, `mlxf_ops_logic.f90`, `mlxf_ops_create.f90` with their testers; `src/core/mlxf.f90`;
  `src/test/mlxf_test_defs.f90` (`ELEM_*`), `src/test/mlxf_test_registry.f90` (rows `ops_math`, `ops_logic`,
  `ops_create` of area `ops`); `scripts/mlxc_parity.txt`, `scripts/check_rules.py` (`PARITY_PENDING` 274,
  `ENTRY_HELPERS`); `scripts/probes/expm1_gpu_probe.c` (new, R4); `doc/policies/binding_contract_policy.md`
  (sections 1, 5, 10); `README.md` (API table); `doc/collaboration/apple_questions.md` (question 20);
  `doc/history/2026-11.md`; this plan (file-table rows for `mlxf_array_tester.f90` and the probe, Progress).
- *Exit items.*
  - No `pending 1` line: all 65 are `public`; 274 pending lines remain, `PARITY_PENDING = 274`, rule `parity`
    passes.
  - Debug and Release from scratch, `-DMLXF_WERROR=ON`, zero warnings
    (`scratch/logs/final/build_{Debug,Release}.log`; driver log `scratch/logs/final_builds.log`). A first
    attempt failed in Release on `-Wfunction-elimination` (an impure call inside `.and.` in the math
    tester; `scratch/logs/final_attempt1/`); fixed with nested `if`s, then both rebuilt from scratch.
  - Fast gate passes in both (8 of 8 entries). Release total 10.4 s (unit_ops 0.66 s), configure plus build
    13.28 s, load 6.4 before and 8.6 after; Debug total 11.6 s. Within the Phase 1 bounds (29.2 s, 41.7 s);
    by R3 the bounds are judged again at the end of Phase 3.
  - `unit_ops` on both devices in both builds: 1,532 checks pass with both devices (948 with `device=cpu`, 585
    with `device=gpu`). That is the existing `ops` suite's 389, unchanged, plus `ops_math` 825, `ops_logic`
    217 and `ops_create` 101.
  - Existing areas unchanged in both builds (`scratch/logs/final/area_*`): core 82 (80 when the allocator
    reuses no freed address, as at the base), array 128, linalg 32, fft 57, compile 63, kernels 1539;
    object_contracts passes in the gate. `scripts/check_tree.sh` passes.
- *Frozen tolerances:* entry "Phase 1a, the elementwise calibration" (16:09 EST), re-frozen under R4 (22:50 EST):
  float32 `erf` 1.509527616e-06, every other function 4 eps32; float64 4 eps64 except the six float32-computed
  functions (`erf` 7.614142292e-07, `sin`, `cos`, `mlx_sigmoid`, `mlx_erfinv`, `mlx_logaddexp` 4 eps32); GPU
  `mlx_expm1` `ELEM_GPU_EXPM1` = 4.010555858e-05. Upstream-defect lines this phase: 1 (`expm1`, kept under R4).
- *Decisions under delegation.*
  - Layout: the new wrappers live in three submodules of `mlxf_ops`, `math` (unary and binary
    mathematics, `mlx_round`, `mlx_clip`, `mlx_nan_to_num`, `mlx_divmod`, `mlx_copy`, `mlx_stop_gradient`),
    `logic` (predicates, closeness, integers and bits) and `create` (constructors). The operators' bodies
    live in `mlxf_array_operations`, because `mlxf_array_elementwise` is outside the file table. Each
    submodule has a tester with one table per family (unary, binary, predicates, integers, constructors) and
    convention checks by name.
  - Scalars: the binary family and `mlx_clip` take real32 and real64 scalars on either side, as the
    operators do; no integer scalar for them, as for the operators (`a**2.0`, not `a**2`). The bitwise
    family takes a default integer, converted to the array's integer kind: on either side for `iand`, `ior`
    and `ieor`, as the shift for `shiftl` and `mlx_right_shift`.
  - Forms: `mlx_divmod` is a subroutine with two `intent(out)` results. `mlx_full` and `mlx_full_like` take an
    array or a real32, real64 or integer fill; a scalar fill is float32 or int32 unless `dtype` is given (a
    real64 value never makes float64 by itself). `mlx_nan_to_num` takes real32 replacements (C's `float`).
  - `mlxf_array.f90` imports `c_float` renamed as `c_float_kind`, because its submodule
    `mlxf_array_elementwise` imports `c_float` itself and gfortran refuses the clash.
  - The launch edit's aligned intrinsic `use` line (R2) fails `format_use_blocks.py --check`. The static gate
    is not waivable, so the formatter's form was restored in `mlxf_array.f90` and in `mlxf_array_tester.f90`,
    which is now equal to HEAD. A Phase 1 file-table row was added first.
- *What it means, in short:* Fortran users have MLX's elementwise API under Fortran names, with Fortran's
  argument order and sign conventions, on both devices. The tests found one MLX accuracy defect (GPU `expm1`),
  now documented and reported. Two thirds of the run's ledger lines remain for Phases 2 and 3.
