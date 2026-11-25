# mlx-fortran: parity with mlx-c

Status, 2026-11-24 (later): Phases 0 to 3 complete; the run `mlxf_parity` stands at the hold after Phase 3
(decision 4): the maintainer reads the API in the Phase 3 Progress entry. Report:
[`mlxf_mlxc_parity_report.md`](../completed/mlxf_mlxc_parity_report.md). After the hold, the wrappers that
milestone 2's kernels need come first (decision 27).

Earlier status, 2026-11-24: Phases 0 and 1 complete. Phases 2 and 3 run next, on the M5 Ultra (decision 26), from the
maintainer's commit that closes milestone 1's hold. After the Phase 3 hold, the wrappers that milestone 2's
kernels need come first (decision 27).

Earlier status, 2026-11-23: Phase 0 complete (interactive, decision 23); Phase 1 complete (run `mlxf_parity`);
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

26. (2026-11-24, Hans: "This is the machine we are working on now"; roadmap decision 4) **The runs continue
    on the M5 Ultra.** This replaces the M2 Ultra of decisions 4, 23 and 25. No output of Phases 2 or 3
    exists on another machine. Phase 2 opens with the base measurements on the M5 (the gate's time per area,
    the Release clean build twice), since Phase 1's were taken on the M2 Ultra.
27. (2026-11-24, Hans: yes; roadmap decision 5) **The order after the Phase 3 hold.** The wrappers that
    milestone 2's kernels need run first ([`mlxf_kernel_families.md`](mlxf_kernel_families.md)):
    - the custom Metal kernel of decision 17 (`mlx_metal_kernel_spec` and `type(mlx_metal_kernel)`, over
      `mlx_fast_metal_kernel_new` and `mlx_fast_metal_kernel_apply`), with Phase 7's test of it;
    - the FFT lines of Phase 5 (`mlx_fftn`, `mlx_ifftn`, `mlx_rfft2`, `mlx_irfft2`, `mlx_rfftn`, `mlx_irfftn`
      and the shift and frequency helpers);
    - `mlx_gather_mm`, `mlx_block_masked_mm` and `mlx_segmented_mm` of Phase 4.

    The remaining lines of Phases 4 to 8 follow in the plan's order, beside milestone 2 on a disjoint file
    table. This replaces decision 3's order for these lines. Rule `parity` is unchanged: a phase's lines may
    become public before the phase closes, the count of pending lines only shrinks, and Progress closes a
    phase only when no line names it.

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

### Phases 0 and 1, delivered

The ledger/probe work and 65 elementwise wrappers are complete. Their original instructions, base
measurements, Phase 1a tolerance freeze and rulings R1–R4 are in
[the completed Phase 1 record](../completed/mlxf_mlxc_parity_phase1.md). Read those measurements and
rulings before continuing Phase 2. No `pending 1` entry remains; 274 entries remain across later phases.

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
| `src/core/array/mlxf_array_borrow.f90` | decision 13's `mlx_view` and `mlx_alloc` of int8 and int16, which live in the borrowing submodule and not in `mlxf_array_transfer` (row added by the run in Phase 3, before the edit) | 3 |
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

### Phase 0, the ledger, rule `parity` and the probes: 2026-11-23 - complete

Delivered evidence and the pre-launch `mlx_take`/`mlx_bitcast` adoption are in
[the completed record](../completed/mlxf_mlxc_parity_phase1.md).

### Phase 1, elementwise: 2026-11-23 - complete

All 65 Phase 1 ledger entries are public; 274 remain pending. The completed record contains the base
measurements, Phase 1a calibration, R1–R4, final builds/tests and the GPU `expm1` exception. Preserve
those frozen values; R3 still requires the combined timing check at the Phase 3 hold.

These completion headings remain here because the static parity gate reads them. Append Phase 2 and
later execution records below; do not duplicate the archived Phase 0/1 evidence.

### Phase 2, the base measurements on the M5 Ultra: 2026-11-24 09:11 EST (run mlxf_parity, Claude)

- *Machine and base.* HanssMacStudio, the M5 Ultra of decision 26 (30 cores, 96 GB, macOS 27.2.1), Homebrew
  GFortran 16.2.0, CMake 4.5.1, Homebrew MLX 0.32.4 and mlx-c 0.8.0. HEAD
  `8305556ebf4f28ee36cce361580d7e47d673a770`, clean working tree. No ruling in the run's rulings file; R1 to R4
  of the Phase 1 record apply.
- *How.* As the Phase 1 record took them (R1): a `git archive HEAD` export in `scratch/keep/base_src`, four
  trees from scratch (Release, Debug, Release, Debug), serial, nothing else of the run running, each timed step
  started with the one-minute load at most 4 (`scratch/scripts/base_measure.sh`, log
  `scratch/logs/base_measure.log`, per-step logs `scratch/keep/base_meas/`; paths under
  `/Users/hael/agent_runs/mlxf_parity`). `-DMLXF_WERROR=ON`, `-j 12`. Zero warnings in the four builds. The first
  `unit_core` reports `GPU devices: 1`. Every number below is *measured*, the bounds *derived* from them.
- *Release clean build, configure plus build, wall:* 7.091 s (1.715 + 5.376; load 1.37 before, 2.94 after) and
  6.985 s (1.616 + 5.369; load 2.82 before, 3.10 after). Debug: 4.116 s and 4.222 s.
- *Fast gate, per entry (s), Release run 1 / run 2:* unit_array 8.75 / 8.71, unit_kernels 4.56 / 1.68,
  object_contracts 0.50 / 0.46, unit_core 0.26 / 0.19, unit_ops 0.21 / 0.18, unit_compile 0.14 / 0.10,
  unit_fft 0.12 / 0.08, unit_linalg 0.11 / 0.08; total real time 8.75 / 8.72 s (budget 60 s; the script with
  its static gate 10.08 / 9.96 s; load 2.94 and 3.10 before, 2.72 and 3.22 after). Debug totals 9.36 / 9.54 s.
- *Assertion counts, both devices in one process (the four builds alike):* unit_core 82 (80 to 82: the
  registry sub-suite's two address-reuse checks, as at the Phase 1 base), unit_array 128, unit_ops 1536,
  unit_linalg 32, unit_fft 57, unit_compile 63, unit_kernels 993; object_contracts passes. Per device
  (`device=cpu` / `device=gpu`, device-independent checks counted in each): core 56 / 56 (55 without the reuse
  check), array 70 / 69, ops 950 / 587, linalg 17 / 15, fft 29 / 28, compile 32 / 32, kernels 504 / 496. The
  counts of unit_ops and unit_kernels differ from the Phase 1 record's (1,532 and 1,539): the base moved from
  `4706ecb` to `8305556`; these are the counts the existing suites keep in this run.
- *Frozen bounds (section 6) on this machine, before any wrapper of Phase 2:* Release clean build (configure
  plus build, from scratch, `-j 12`) at most **14.08 s**, twice the mean 7.038 s of the two runs. Fast gate
  total real time in Release at most **38.74 s**, the mean 8.735 s plus 30 s. A new area at most 3 s in
  Release. By R3 they are judged at the end of Phase 3. The M2 Ultra's bounds (29.2 s, 41.7 s) are context only.

### Phase 2a, the calibration of reductions, scans, softmax, linspace and windows: 2026-11-24 09:37 EST (run mlxf_parity, Claude)

- *How.* The new testers `mlxf_ops_reduce_tester` (reductions, scans, softmax) and `mlxf_ops_create_tester`
  (linspace, the four windows) built in Debug with their seed lists held to the calibration seed alone, run as
  `mlxf_test_exec test=unit_ops suite=ops_reduce|ops_create device=cpu|gpu` (logs
  `scratch/keep/phase2a_ops_{reduce,create}_{cpu,gpu}_seed1.log`, table `scratch/keep/phase2a_frozen.txt`,
  script `scratch/scripts/freeze_phase2a.py`; load 1.99). Both devices on seed 1, as R4 rules; no seed 2 or 3
  ran before this entry. Error relative to `max(1, |reference|)` against plain Fortran real64 oracles, the
  largest over every form of a function (each dimension, lists of dimensions, the whole array, keepdims; scans
  forward and reversed, inclusive and exclusive). Extrema, logical reductions, counts, positions, sorting and
  every shape operation are exact and need no calibration.
- *The fixture, changed once before the freeze.* A first draft ran one (5, 4, 3) fixture per seed
  (`scratch/logs/phase2a_draft/`): a seed's maximum was then taken over about 80 reduced values, and over one
  value for a whole-array form. Before any freeze the tester was changed to 16 fixtures per seed
  (`REDUCE_NBATCH`): forms with dimensions run on the batch along a fourth dimension, whole-array forms on each
  fixture, so that the maximum covers about a thousand values, as the elementwise tester's 1,024 points do. The
  draft's numbers are not used. What the change showed: the whole-array running sum's error on the CPU is 15.6
  eps32 over 16 fixtures against 3.0 on the first one alone *(measured)*.
- *Observed on seed 1, CPU / GPU float32, in float32 epsilons (2^-23) (measured):* `sum` 4.95 / 7.53, `product`
  1.89 / 1.95, `mlx_mean` 1.04 / 1.04, `mlx_median` 0.49 / 0.49, `mlx_var` 1.77 / 3.54, `mlx_std` 1.07 / 1.62,
  `mlx_logsumexp` 1.03 / 1.05, `mlx_cumsum` 15.63 / 5.58, `mlx_cumprod` 2.79 / 2.60, `mlx_logcumsumexp`
  2.35 / 1.31, `mlx_softmax` 1.09 / 1.09, `mlx_linspace` 1.43 / 1.43, `mlx_bartlett` 0.97 / 0.97, `mlx_blackman`
  1.14 / 1.15, `mlx_hamming` 1.19 / 1.19, `mlx_hanning` 1.43 / 1.65. None reaches the 64 eps ceiling: no finding.
  CPU float64: `product` 5.07 eps64, `mlx_var` 2.52, `mlx_linspace` 2.00, `mlx_std` 1.78, `mlx_mean` 0.99, the
  rest 0; three functions MLX 0.32.4 computes in float32 on the CPU: `mlx_logsumexp` 3.7e-8, `mlx_logcumsumexp`
  4.4e-8, `mlx_softmax` 1.3e-7.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`REDUCE_TOLERANCES`), `max(2 x the larger of the CPU and GPU
  seed-1 errors, 4 eps)` of the result kind *(derived)*: float32 `sum` **1.795589924e-06** (15.06 eps32),
  `mlx_var` **8.436885142e-07** (7.08), `mlx_cumsum` **3.725346026e-06** (31.25), `mlx_cumprod`
  **6.648052118e-07** (5.58), `mlx_logcumsumexp` **5.597391568e-07** (4.70), every other function the floor
  4 eps32 = 4.768371582e-07. Float64: `product` **2.251676254e-15**, `mlx_var` **1.117111451e-15**, the floor
  4 eps64 = 8.881784197e-16 for the rest, except the three float32-computed functions, held to the float32
  floor 4.768371582e-07. The same float32 tolerances judge the GPU in 2b.

### Phase 2, reductions, scans, sorting and shape: 2026-11-24 (run mlxf_parity) - complete

- *Machine and base.* HanssMacStudio, the M5 Ultra (30 cores, 96 GB, macOS 27.2.1, GFortran 16.2.0, CMake 4.5.1,
  MLX 0.32.4, mlx-c 0.8.0); HEAD `8305556`, clean at launch. No ruling in the run's rulings file. Applied from
  the Phase 1 record: R1 (hand-configured trees under `scratch`), R3 (the timing bounds are judged at the end of
  Phase 3; the numbers here are context), R4 (calibration on both devices on seed 1 before seeds 2 and 3).
  Paths below are under `/Users/hael/agent_runs/mlxf_parity`.
- *Files.* `src/defs/mlxf_defs.f90` (six records: `mlxf_reduce_spec`, `mlxf_scan_spec`, `mlxf_pad_spec`,
  `mlxf_strided_spec`, `mlxf_count_spec`, `mlxf_linspace_spec`); `src/core/array/mlxf_array.f90` and
  `mlxf_array_operations.f90` (30 new signature helpers; `mlxf_reduce_op` and `mlxf_scan_op` take a record,
  `mlxf_concat_op` takes its axis translated); `src/core/ops/mlxf_ops.f90`, `mlxf_ops_reduce.f90` (rewritten),
  `mlxf_ops_shape.f90`, `mlxf_ops_create.f90`, the new submodule `mlxf_ops_sort.f90`, the new testers
  `mlxf_ops_reduce_tester.f90`, `mlxf_ops_sort_tester.f90`, `mlxf_ops_shape_tester.f90` and the extended
  `mlxf_ops_create_tester.f90`; `src/core/mlxf.f90`; `src/test/mlxf_test_defs.f90` (`REDUCE_TOLERANCES`,
  `REDUCE_NBATCH`), `src/test/mlxf_test_registry.f90` (rows `ops_reduce`, `ops_sort`, `ops_shape` of area `ops`),
  `test/CMakeLists.txt` (the comment on `unit_ops`'s time; no new entry, budget 8); `scripts/mlxc_parity.txt`,
  `scripts/check_rules.py` (`PARITY_PENDING` 163, `ENTRY_HELPERS`); `doc/policies/binding_contract_policy.md`
  (sections 2, 5, 10); `README.md` (API table); `doc/history/2026-11.md`; this plan (Progress). No file outside
  the table. 18 files changed and 4 added: 3,740 lines added and 262 removed in the tracked files.
- *Exit items.*
  - No `pending 2` line: the 111 are `public`. Ledger before: 125 public, 46 plumbing, 146 internal, 89
    excluded, 274 pending (Phase 2: 111, 3: 35, 4: 40, 5: 29, 6: 16, 7: 9, 8: 34). After: 236 public, 163
    pending (3: 35, 4: 40, 5: 29, 6: 16, 7: 9, 8: 34); the other classes unchanged *(exact)*.
    `PARITY_PENDING = 163`; rule `parity` passes.
  - `unit_ops` passes on both devices in both builds: 2,314 checks with both devices, 1,395 with `device=cpu`,
    921 with `device=gpu` (`scratch/keep/final_phase2/area_{Debug,Release}_ops_{both,cpu,gpu}.log`). That is the
    base's 1,536 unchanged (ops 393, ops_math 825, ops_logic 217, ops_create 101) plus ops_create's 102 new
    checks, `ops_reduce` 386, `ops_sort` 70 and `ops_shape` 220. Sub-phase 2b, the first run with seeds 2 and
    3 (09:37 EST, before the review's 20 added exact checks): `scratch/keep/phase2b_unit_ops_debug.log`, 2,294
    of 2,294; no judged check has failed in any run. Largest judged errors on seeds 2 and 3 in
    float32 epsilons *(measured)*: `mlx_cumsum` 12.44 (GPU, tolerance 31.25), `sum` 6.20 (15.06), `mlx_cumprod`
    3.52 (5.58), `mlx_var` 3.05 (7.08), `mlx_linspace` 2.88, `mlx_logcumsumexp` 2.83 (4.70), the rest below
    2.2 against the floor 4. One result sits on its bound: CPU float64 `mlx_linspace` on seed 3 is exactly
    4 eps64, the floor.
  - Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings
    (`scratch/keep/final_phase2/build_{Debug,Release}.log`; driver log `scratch/logs/final_builds.log`,
    script `scratch/scripts/final_builds.sh`). This is the third run of the script: the first
    (`scratch/logs/final_attempt1/`) passed and preceded the review's fixes; the second
    (`scratch/logs/final_attempt2/`) failed in Release on `-Wfunction-elimination` (an impure call after `.and.`
    in two testers, the trap the Phase 1 record names), fixed with a nested test before the third.
  - The existing suites keep their assertions, both builds (`scratch/keep/final_phase2/area_*`): core 82 (80
    in the Release run: the address-reuse checks),
    array 128, linalg 32, fft 57, compile 63, kernels 993, and the 1,536 of `unit_ops` named above;
    object_contracts passes in the gate. Per device as at the base: core 56 / 56 (55 without the address-reuse
    check), array 70 / 69, linalg 17 / 15, fft 29 / 28, compile 32 / 32, kernels 504 / 496.
  - Fast gate passes in both builds, 8 of 8 entries, with `scripts/check_tree.sh` first
    (`scratch/keep/final_phase2/gate_{Debug,Release}.log`).
- *Times, for context (R3).* Release configure plus build from scratch 7.293 s (1.619 + 5.674; load 3.68
  before, 3.73 after) against the bound 14.08 s; fast gate total real time 9.05 s in Release (bound 38.74 s),
  9.09 s in Debug. `unit_ops` went from 0.2 s to 0.77 s in the Release gate (1.81 s in the first run of the
  script, 0.57 s alone on a warm machine):
  the reduction sub-suite's GPU evaluations; `test/CMakeLists.txt` says so, as the test policy asks of an
  entry above 0.5 s *(measured)*.
- *Frozen tolerances:* the entry "Phase 2a" above, unchanged since. Upstream-defect lines this phase: 0.
- *Decisions under delegation.*
  - **Forms of a reduction.** Two specifics per generic: `f(a[, dim][, keepdims])` and `f(a, dims[, keepdims])`
    (`mlx_var` and `mlx_std` add `ddof`). The existing `sum(a, dim)`, `minval(a, dim)`, `minloc(a, dim)`,
    `mlx_logsumexp(a, dim)` and `mlx_cumsum(a, dim)` keep their meaning; their `dim` became optional where the
    all-dimensions form exists.
  - **`maxloc(a)` and `minloc(a)` return subscripts**, a rank-1 int32 array of size rank, as Fortran's do.
    MLX's flat position in row-major order of the reversed shape is the position in Fortran's array element
    order, so the first extremum is Fortran's and the subscripts follow from integer division in the graph;
    no copy. `keepdims` is offered with `dim` only.
  - **Where MLX flattens** (sort, argsort, partition, argpartition, topk, the scans, repeat, concatenate
    without an axis) the Fortran result is the same rank-1 array, in array element order.
  - **Three all-axes functions serve one rank of an intrinsic-shaped wrapper**, because the ledger gives them
    that Fortran name and Fortran fixes its meaning: `mlx_transpose` (reverse every axis) is `transpose` of a
    rank-2 array and `mlx_matrix_transpose` of higher ranks; `mlx_roll` (roll the flattened array) is
    `cshift(a, shift)` of a rank-1 array, since Fortran's `cshift` without `dim` shifts dimension 1;
    `mlx_softmax` (every axis) is `mlx_softmax(a)` of a rank-1 array, since the policy's default is dimension
    1. For the maintainer's read at the hold: offering the all-axes forms under their own names
    (`mlx_permute(a)` without `order`, for one) would need new ledger names.
  - **Matrices in the Fortran view, free except one.** `mlx_tril(a, k)` calls MLX's `triu` with -k and
    `mlx_triu` its `tril` (the ledger lines say so: `mlx_tril public mlx_triu`); `mlx_diag` and `mlx_eye`
    pass -k (and `mlx_eye` exchanges n and m); `mlx_diagonal` and `mlx_trace` take `dim1` and `dim2`, 1 and 2
    by default, where MLX's defaults are its first two axes, Fortran's last two dimensions. `mlx_tri` needs
    one transpose node after MLX's triangle: MLX builds the lower triangle of its own (n, m) matrix, which is
    the upper triangle in the Fortran view. A transpose is a view, not a copy, so this is not the stop of
    section 7; it is the only added node of the phase besides the index shifts.
  - **Lists of arrays are subroutine results** (`mlx_split`, `mlx_unstack`, `mlx_broadcast_arrays`,
    `mlx_meshgrid`), with an allocatable `intent(out)` array of handles, as `mlx_divmod` returns its pair: a
    function returning an allocatable array of handles is the compiler defect of
    `doc/compiler_issues/gfortran_finalize_allocatable_array_result.f90`.
  - **Defaults.** An omitted `dim` is MLX's default axis read in the Fortran view: the last dimension for
    `mlx_stack`, `mlx_unstack` and `mlx_split` (MLX's axis 0), dimension 1 for `mlx_diff` and `mlx_softmax`
    (MLX's last axis, decision 7). `cshift`'s default is Fortran's, dimension 1.
  - **`mlx_meshgrid` has no `indexing` argument**: matrix indexing in the Fortran view (grid i varies along
    dimension i), obtained by passing the list reversed with MLX's `'ij'`. MLX's `'xy'` is the same call with
    the first two arrays exchanged.
  - **`mlx_pad`**: `(a, width[, value, mode])` and `(a, low, high[, value, mode])`, widths per Fortran
    dimension; `value` is an array (MLX's own argument; zero by default). MLX's `axes` argument is not
    offered: a zero width does the same.
  - **`mlx_as_strided`** takes a Fortran shape, strides in elements per Fortran dimension and `offset` as a
    count of elements skipped (the contract's "no row-major stride" holds: both lists are reversed inside).
  - **Not offered:** the result dtype of `mlx_cumsum` and `mlx_cumprod` (MLX's optional `dtype`); `keepdims`
    for the whole-array `maxloc`/`minloc`.
  - **Corrections of the plan's premises.** `mlx_topk` returns the k largest values, not positions (decision
    8 lists "`mlx_topk` indices"): nothing to shift. `mlx_concatenate` without an axis flattens its arrays
    first, so the Fortran form without `dim` is rank 1, not "along the last dimension". `mlx_argsort` was
    stable in every test on both devices (lines of 3 to 5 elements with ties), which the policy reports
    without promising it.
  - **Helpers.** One helper per C signature class, 30 new ones, written from a table by a scratch script
    (`scratch/gen/gen_helpers.py`, kept as evidence; the repository's text is the source). The integer
    helpers (`mlxf_int2_op`, `mlxf_int3_op`, `mlxf_roll_op`, ...) take values as MLX wants them and the
    wrappers translate through `axis_of`; the reduction and scan helpers translate dimensions themselves, as
    `mlxf_reduce_op` did.
  - **The reduction tester's fixture** was enlarged once before the freeze (entry "Phase 2a").
  - **An independent review of the diff** (a read-only subagent, against MLX's source) found no translation
    error. Fixed from it: `kth` below 1 and a cut position below 1 now stop (MLX would count them from the
    end); `mlx_as_strided` makes a strided input contiguous first (`mlx_contiguous`, already plumbing), since
    MLX strides over the buffer and not over a view's elements; three tests that a missing dimension reversal
    would have passed (`mlx_flip`, `mlx_swapdims`, `mlx_number_of_elements` on a middle or symmetric choice of
    dimensions) gained a case that tells the two apart; four doc sentences were corrected. Left as they are,
    for the maintainer: argument forms without a test of their own (`ddof` with `dim`, `keepdims` on the
    whole-array form, `mlx_pad` on rank 3, `mlx_tile` with more counts than dimensions, the rank-0 branch of
    `mlx_flatten`; `precise` cannot be told from the plain softmax by value); the calibration seed is judged
    against its own doubled error, as in Phase 1, so only seeds 2 and 3 test a tolerance; `mlx_argsort`'s
    stability is asserted though MLX does not document it; `axes_of` exists in `mlxf_array_operations` and in
    `mlxf_ops_shape` (the first is private to the array module's submodules).
  - **Proposed, not applied** (skill edits need approval): section 3 of `.github/skills/mlxf-binding/SKILL.md`
    lists the helper classes and should name the new ones; its section 4 could state the flatten rule and the
    matrix rule now in the binding policy's section 2.
- *What it means, in short:* a Fortran user now has MLX's reductions, scans, sorting and shape operations
  under Fortran's conventions on both devices, with no accuracy finding. The ledger is down to 163 pending
  lines, 35 of them for Phase 3.

### Phase 3, indexing and data types: 2026-11-24 (run mlxf_parity) - complete

- *Machine and base.* HanssMacStudio, the M5 Ultra (30 cores, 96 GB, macOS 27.2.1, GFortran 16.2.0, CMake 4.5.1,
  MLX 0.32.4, mlx-c 0.8.0); HEAD `8305556` plus Phase 2's change in the working tree
  (`review/phase_2.diff`). No ruling in the run's rulings file; R1, R3 and R4 of the Phase 1 record applied.
  Paths below are under `/Users/hael/agent_runs/mlxf_parity`. The run ends here, at the hold of decision 4.
- *Files.* `src/defs/mlxf_defs.f90` (`MLX_DTYPES` gains `int8`, `int16`, `uint8`, `uint16`, `uint32`,
  `uint64`, `float16`, `bfloat16`; `mlxf_index_spec`); `src/core/array/mlxf_array.f90`,
  `mlxf_array_operations.f90` (nine helpers, `slice_bounds` shared by the slice and its update, the dtype
  check widened), `mlxf_array_transfer.f90` (int8 and int16 of `mlx_from`, `mlx_to`, `mlx_to_alloc`;
  `mlx_item`), `mlxf_array_borrow.f90` (int8 and int16 of `mlx_view` and `mlx_alloc`),
  `mlxf_array_tester.f90`; `src/core/ops/mlxf_ops.f90`, `mlxf_ops_shape.f90` (`mlx_take` without `dim`;
  `mlx_slice` a generic), the new `mlxf_ops_index.f90` and `mlxf_ops_index_tester.f90`; `src/core/mlxf.f90`;
  `src/test/mlxf_test_registry.f90` (row `ops_index`); `scripts/mlxc_parity.txt`, `scripts/check_rules.py`
  (`PARITY_PENDING` 128, `ENTRY_HELPERS`); `doc/policies/binding_contract_policy.md` (sections 5 and 10),
  `README.md`, `doc/history/2026-11.md`; this plan (a file-table row, Progress);
  `doc/implementation_notes/completed/mlxf_mlxc_parity_report.md` (new).
- *Exit items.*
  - No `pending 3` line: the 35 are `public`. Ledger before: 236 public, 163 pending (Phase 3: 35, 4: 40, 5: 29,
    6: 16, 7: 9, 8: 34). After: 271 public, 128 pending (4: 40, 5: 29, 6: 16, 7: 9, 8: 34); 46 plumbing, 146
    internal and 89 excluded unchanged *(exact)*. `PARITY_PENDING = 128`; rule `parity` passes.
  - `unit_ops` passes on both devices in both builds: 2,402 checks (1,439 with `device=cpu`, 965 with
    `device=gpu`): Phase 2's 2,314 unchanged plus `ops_index` 88
    (`scratch/keep/final_phase3/area_{Debug,Release}_ops_*.log`).
  - `unit_array` passes on both devices in both builds: 179 checks (96 CPU, 94 GPU): the base's 128 unchanged
    plus 51 (`scratch/keep/final_phase3/area_{Debug,Release}_array_*.log`).
  - The leak gate of `unit_array` covers the new kinds: `test_kind_leaks` runs, 10,000 times per device, every
    movement of int8 and int16 data (`mlx_from`, `mlx_to`, `mlx_to_alloc`, `mlx_view`, `mlx_alloc`), a
    conversion to a device-only dtype and `mlx_item` of every kind (float64 on the CPU), and asserts the active
    memory, the live count and the stale releases equal to their values before: three assertions per device,
    passing.
  - Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings; fast gate 8 of 8 in both with
    `scripts/check_tree.sh` first (`scratch/keep/final_phase3/{build,gate}_{Debug,Release}.log`, driver log
    `scratch/logs/final_builds_phase3.log`, script `scratch/scripts/final_builds_phase3.sh`). The existing
    suites keep their assertions: core 82, linalg 32, fft 57, compile 63, kernels 993; object_contracts
    passes. A first run of the script failed in Release on `-Wfunction-elimination` in the new array tests
    (`scratch/logs/final3_attempt1/`), fixed before this one.
  - **The section 6 bounds, judged (R3) against the entry "Phase 2, the base measurements on the M5 Ultra":**
    Release clean build, configure plus build from scratch at `-j 12`: 7.649 s (1.614 + 6.035; load 2.02
    before, 2.55 after) and 7.651 s (1.622 + 6.029; load 2.51 before, 2.59 after;
    `scratch/keep/final_phase3/second_release_timing.log`) against the bound **14.08 s**: met, 1.09 times
    the base's mean 7.038 s. Fast gate total real time in Release: 10.47 s and 10.51 s against the bound
    **38.74 s**: met, 1.75 s above the base's 8.735 s (`unit_array` 8.7 to 10.5 s, the new leak gate;
    `unit_ops` 0.2 to 1.9 s in the gate). No new area, so the 3 s bound has no subject; the budget stays 8.
    All *measured*.
- *Tolerances.* Phase 3 adds no floating-point family: indices, positions, shapes, moved bytes and scattered
  values are exact. The frozen tables are unchanged. Upstream-defect lines this phase: 0.
- *Decisions under delegation.*
  - **`mlxf_array_borrow.f90` joined the file table** for this phase before its edit: decision 13 names
    `mlx_view` and `mlx_alloc`, which live there. It is not part of the handle model.
  - **`mlx_item` is a checked subroutine**, `call mlx_item(a, value[, status])`: a generic cannot select on a
    function's result type, and it is data movement (binding policy section 6). It takes one element of any
    rank and refuses another kind, as `mlx_to` does, where MLX's `item` would convert.
  - **`logical(c_bool)` transfers existed already**; decision 13's third kind needed nothing.
  - **Device-only dtypes** are eight `MLX_DTYPES` members with no transfer specific, int8 and int16 among the
    transferable ones. `mlx_astype`, the constructors and every `dtype` argument accept them.
  - **Gather and scatter layouts are MLX's read in Fortran order**: the slab, then the index dimensions. The
    list forms take an array of index arrays paired with `dims`.
  - **`mlx_scatter_add` chooses by rank between two MLX functions** (`scatter_add_single` and
    `scatter_add_axis`) that would have one Fortran signature: updates of rank `rank(indices) + rank(a)` are
    slabs, anything else is element by element along `dim`. One legal input of `scatter_add_axis` (indices of
    `a`'s rank r with updates of rank 2r and r trailing extents of 1) is unreachable. For the maintainer:
    a name of its own, `mlx_scatter_add_along_dim` beside `mlx_put_along_dim`, would be cleaner and needs a
    new ledger name.
  - **`mlx_unique` always asks MLX for its three optional results** and returns four arrays; `size` is
    required because mlx-c has no dynamic form (MLX computes into `size` slots).
  - **The dynamic slice and its update are specifics of `mlx_slice` and `mlx_slice_update`**, told apart by
    `start` being an array of the graph; the ledger gives them these names.
  - **Index arrays may be of any integer dtype**; `mlx_take_along_dim` now shares the shift of the new
    wrappers (it took int32 and int64 only), and uint64 goes through int64, since MLX promotes uint64 minus a
    signed one to a float.
  - **`mlx_take(a, indices)`**: `dim` became optional; without it, positions in array element order.
  - **An independent review** (a read-only subagent, against MLX's source) found one defect, fixed: uint64
    index arrays were admitted and then became float32. It found four scatter tests that could not tell
    `max`/`min` from a plain scatter or from no scatter; their updates now lie on both sides of the array's
    values. Left without a test of their own, for the maintainer: index arrays of rank above 1 in gather and
    scatter, a slab extent above 1 along a scattered dimension, a lower-rank mask, negative strides in a
    section update, a truncating `mlx_unique`, repeated positions in the element form of `mlx_scatter_add`.
  - **Proposed, not applied** (skill edits need approval): `.github/skills/mlxf-binding/SKILL.md` section 3
    should list the helper classes of Phases 2 and 3, and section 4 the flatten rule, the matrix rule and
    "index arrays go through `zero_based`, index results through `index_result`".
- *For the maintainer's read at the hold: the public names of Phases 2 and 3.* Arrays are `type(mlx_array)`;
  `[x]` is optional and passed by keyword; `dim` is a Fortran dimension, `dims` an integer array of them;
  results are functions unless written `call`.
  - **Reductions** (Phase 2): `sum`, `product`, `maxval`, `minval`, `all`, `any`, `count`, `mlx_mean`,
    `mlx_median`, `mlx_logsumexp`: `f(a[, dim][, keepdims])` and `f(a, dims[, keepdims])`. `mlx_var`,
    `mlx_std`: the same with `[, ddof]`. `maxloc`, `minloc`: `f(a, dim[, keepdims])` and `f(a)`.
    `mlx_softmax(a[, dim][, precise])`, `mlx_softmax(a, dims[, precise])`.
  - **Scans**: `mlx_cumsum`, `mlx_cumprod`, `mlx_cummax`, `mlx_cummin`, `mlx_logcumsumexp`:
    `f(a[, dim][, reverse][, inclusive])`. `mlx_diff(a[, n][, dim])`.
  - **Sorting**: `mlx_sort(a[, dim])`, `mlx_argsort(a[, dim])`, `mlx_partition(a, kth[, dim])`,
    `mlx_argpartition(a, kth[, dim])`, `mlx_topk(a, k[, dim])`.
  - **Shape**: `mlx_squeeze(a[, dim])`, `mlx_squeeze(a, dims)`, `mlx_expand_dims(a, dim)`,
    `mlx_expand_dims(a, dims)`, `mlx_flatten(a[, start_dim][, end_dim])`, `mlx_unflatten(a, dim, shape)`,
    `mlx_broadcast_to(a, shape)`, `call mlx_broadcast_arrays(arrays, results)`, `mlx_tile(a, reps)`,
    `mlx_repeat(a, repeats[, dim])`, `mlx_pad(a, width[, value][, mode])`,
    `mlx_pad(a, low, high[, value][, mode])`, `mlx_flip(a[, dim])`, `mlx_flip(a, dims)`,
    `cshift(a, shift[, dim])`, `cshift(a, shifts, dims)`, `mlx_movedim(a, source, destination)`,
    `mlx_swapdims(a, dim1, dim2)`, `transpose(a)`, `mlx_atleast_1d(a)`, `mlx_atleast_2d(a)`,
    `mlx_atleast_3d(a)`, `mlx_as_strided(a, shape, strides[, offset])`,
    `mlx_number_of_elements(a[, dims][, inverted][, dtype])`.
  - **Lists**: `mlx_concatenate(arrays[, dim])`, `mlx_stack(arrays[, dim])`, `call mlx_unstack(a, parts[, dim])`,
    `call mlx_split(a, num, parts[, dim])`, `call mlx_split(a, indices, parts[, dim])`,
    `call mlx_meshgrid(arrays, grids[, sparse])`.
  - **Matrices and constructors**: `mlx_diag(a[, k])`, `mlx_diagonal(a[, offset][, dim1][, dim2])`,
    `mlx_trace(a[, offset][, dim1][, dim2][, dtype])`, `mlx_tril(a[, k])`, `mlx_triu(a[, k])`,
    `mlx_identity(n[, dtype])`, `mlx_eye(n[, m][, k][, dtype])`, `mlx_tri(n[, m][, k][, dtype])`,
    `mlx_linspace(start, stop[, num][, endpoint][, dtype])` (real64 bounds), `mlx_bartlett(m)`,
    `mlx_blackman(m)`, `mlx_hamming(m)`, `mlx_hanning(m)`.
  - **Indexing** (Phase 3): `mlx_take(a, indices[, dim])`, `mlx_take_along_dim(a, indices, dim)` (unchanged),
    `mlx_put_along_dim(a, indices, values, dim)`, `mlx_gather(a, indices, dim, slice_sizes)`,
    `mlx_gather(a, indices(:), dims, slice_sizes)`; `mlx_scatter`, `mlx_scatter_add`, `mlx_scatter_max`,
    `mlx_scatter_min`, `mlx_scatter_prod`: `f(a, indices, updates, dim)` and `f(a, indices(:), updates, dims)`;
    `mlx_masked_scatter(a, mask, src)`; `mlx_slice(a, lower, upper[, stride])` (unchanged),
    `mlx_slice(a, start, dims, slice_sizes)`; `mlx_slice_update(a, update, lower, upper[, stride])`,
    `mlx_slice_update(a, update, start, dims)`, `mlx_slice_update_add`, `_max`, `_min`, `_prod`:
    `f(a, update, lower, upper[, stride])`; `mlx_searchsorted(sorted, values[, side])`;
    `call mlx_unique(a, size, results[, fill])`.
  - **Data types** (Phase 3): `integer(int8)` and `integer(int16)` specifics of `mlx_from`, `mlx_to`,
    `mlx_to_alloc`, `mlx_view`, `mlx_alloc`; `call mlx_item(a, value[, status])` for the eight transfer kinds;
    `MLX_DTYPES%int8`, `%int16`, `%uint8`, `%uint16`, `%uint32`, `%uint64`, `%float16`, `%bfloat16`.
- *Where a Fortran user would expect something else* (each stated in the binding policy, sections 2, 5, 10):
  - **Names.** `count`, `all` and `any` take any dtype (nonzero is true) and `count` returns int32.
    `mlx_tril`/`mlx_triu`/`mlx_diag`/`mlx_eye`/`mlx_tri` are named as in MLX but mean the Fortran matrix:
    diagonal k > 0 is above the main diagonal, elements (i, i + k). `mlx_topk` returns values, not positions.
    `mlx_movedim` and `mlx_swapdims` are MLX's `moveaxis` and `swapaxes`. `mlx_scatter_add` covers two MLX
    functions through one name and chooses by the rank of `updates` (below).
  - **Whole-array forms.** Where NumPy flattens (sort, argsort, partition, topk, scans, repeat, concatenate
    without `dim`, `mlx_take` without `dim`) the result is rank 1 in array element order. `maxloc(a)` and
    `minloc(a)` return subscripts, as Fortran's; `sum(a)` and the other reductions without `dim` are rank 0.
    A Fortran user might expect `mlx_concatenate(arrays)` to join along some dimension: it flattens.
  - **Defaults.** `cshift(a, shift)`: dimension 1, Fortran's. `mlx_softmax(a)` and `mlx_diff(a)`: dimension 1
    (MLX's last axis). `mlx_stack`, `mlx_unstack`, `mlx_split` without `dim`: the last dimension (MLX's
    first axis), `mlx_stack`'s `dim` being a position in the result. `mlx_diagonal` and `mlx_trace`:
    dimensions 1 and 2, where MLX's default is the Fortran view's last two. `mlx_linspace`: 50 points,
    float32. `mlx_number_of_elements`: float32. `mlx_pad`: zeros. Fortran's `maxloc`/`minloc` options `mask`,
    `back` and `kind` are not offered; `keepdims` is MLX's.
  - **Index conventions.** Everything is 1-based: `kth`, the cut positions of `mlx_split` (the first index
    of each later part), `mlx_searchsorted` (1 to n + 1), `mlx_unique`'s positions and slots, the `start` of a
    dynamic slice, every gather and scatter index. Nothing checks an index against the extents (0 wraps to
    the end, as in `mlx_take_along_dim`); `kth` and cut positions below 1 stop. `mlx_as_strided`'s `offset` is
    a count of elements skipped.
  - **Layouts that are MLX's read in Fortran order.** A gather's result is the slab followed by the index
    dimensions; a scatter's `updates` likewise. `mlx_diagonal` puts the diagonal in dimension 1.
    `mlx_atleast_3d` gives (1, n, 1) and (1, m, n). `mlx_masked_scatter`'s lower-rank mask matches the last
    dimensions.
  - **Subroutines where MLX has functions**: `mlx_split`, `mlx_unstack`, `mlx_broadcast_arrays`,
    `mlx_meshgrid`, `mlx_unique`, `mlx_item` (a list of handles, or a value whose type selects the specific).
    `mlx_unique` always returns its four arrays and needs `size`, since mlx-c gives no dynamic form.
    `mlx_meshgrid` has matrix indexing only.
  - **Strict kinds.** `mlx_item` and `mlx_to` refuse another kind instead of converting; the unsigned and
    16-bit float dtypes never reach a Fortran array without `mlx_astype`.
- *What it means, in short:* the array half of MLX's API (everything of `ops.h` that is not linear algebra, a
  product, a convolution or a random draw) is reachable from Fortran in Fortran's conventions on both devices,
  with every transferable kind. 128 ledger lines remain for Phases 4 to 8; decision 27 orders the first of
  them. The maintainer reads the API above before those start.
