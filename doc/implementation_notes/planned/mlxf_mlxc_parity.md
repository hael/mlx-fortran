# mlx-fortran: parity with mlx-c

Status, 2026-11-26 (run `mlxf_parity_rest`, closed): Phases 5 to 9 complete in a scratch copy of the working
tree, nothing committed. Every function of mlx-c 0.8.0 is classed and none is pending. Report:
[`mlxf_mlxc_parity_report.md`](../completed/mlxf_mlxc_parity_report.md), section 10; what waits for the maintainer is
its section 10.6.

Status, 2026-11-26 (morning): Phase 8 complete in the same scratch copy (files, streams, the remaining runtime
controls and the distributed operations, 34 lines public). **The ledger has no pending line:** 399 public, 90
plumbing, 101 internal, 90 excluded. Phase 9, the report, closes the run.

Status, 2026-11-26 (later still): Phase 7 complete in the same scratch copy (the fused layers of `fast`, 6 lines
public, `mlx_fast_gated_delta_update` excluded under decision 17); 34 lines pending, all for Phase 8.

Status, 2026-11-26 (later): Phase 6 complete in the same scratch copy (run `mlxf_parity_rest`: transforms, functions
in files, compilation controls, 16 lines public); 41 lines pending for Phases 7 and 8.

Status, 2026-11-26: Phase 5 complete in a scratch copy of the working tree (run `mlxf_parity_rest`: the random
keys and samplers, 19 lines public; ruling R6's thirty reductions converted); 57 lines pending for Phases 6 to 8,
which the same run continues.

Status, 2026-11-25: Phase 4 complete in a scratch copy of the working tree (linear algebra, products and
convolutions: 37 lines public); 76 lines pending for Phases 5 to 8. One gate waits for a ruling: the Release
build-time bound of R3, which the base itself exceeds (15.0 s against 14.08 s; the phase adds 0.5 s). Report:
[`mlxf_mlxc_parity_report.md`](../completed/mlxf_mlxc_parity_report.md), section 9.

Status, 2026-11-24 (night): Phase 10 complete in a scratch copy of the working tree (decisions 27 and 28: the
custom Metal kernel, the FFT lines of Phase 5, three matrix products of Phase 4); 113 lines pending for Phases
4 to 8. Report: [`mlxf_mlxc_parity_report.md`](../completed/mlxf_mlxc_parity_report.md), section 8.

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
28. (2026-11-24, recommended; stands unless overturned at the review) **Decision 27's wrappers are one run,
    Phase 10 of this plan** (run `mlxf_parity_wrappers`, on the M5 Ultra). The number only names the run's
    phase for the tooling: the 15 ledger lines keep their phases (4, 5 and 7), and rule `parity` reads a
    closed Phase 10 as closing none of them.
    - **Base:** the maintainer's commit of the toy refactoring (run `mlxf_toy_arch`), because both runs edit
      `src/test/mlxf_test_defs.f90` and `src/test/mlxf_test_registry.f90`.
    - **Starts when the maintainer has released the Phase 3 hold,** with whatever the read changed applied
      first.
      - (2026-11-24, Hans: "Release it") The hold is released. No change to the API of Phases 2 and 3 was
        asked for.
    - **Order inside the phase:** the Metal kernel, then the FFT lines, then the three matrix products. Each
      part ends with its area passing on both devices before the next begins, so that a stop leaves whole
      parts.
    - **The Metal kernel's tests go beyond Phase 7's one test,** because four deliverables (K1, K2, K5, K6)
      build on it: every member of `mlx_metal_kernel_spec` is exercised at least once; one kernel has two
      inputs and two outputs; one takes a template argument; one result is used inside a compiled function;
      and one kernel with `atomic_outputs` adds colliding integer updates, checked exactly.
    - **Rulings R1 to R4 hold.** The build and gate bounds are those frozen on the M5 in Phase 2's Progress.

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
| 1 to 8, 10 | additive API | existing suites identical in assertions and passing on both devices; new tests on both devices; ledger `pending` count down by the phase's lines; Debug and Release with `MLXF_WERROR=ON` and zero warnings |
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

### Phase 10, the kernels' wrappers ahead of their turn

Decisions 27 and 28. Three parts, in this order:
1. **The custom Metal kernel** of decision 17: `mlx_metal_kernel_spec` and `type(mlx_metal_kernel)` with
   `apply`, in the new folder `src/core/fast/` with its tester and the area `unit_fast`. Tests: Phase 7's
   (1-based column indices added to a float32 array, exact) and decision 28's.
2. **The FFT lines of Phase 5:** `mlx_fftn`, `mlx_ifftn`, `mlx_rfft2`, `mlx_irfft2`, `mlx_rfftn`,
   `mlx_irfftn`, `mlx_fftshift`, `mlx_ifftshift`, `mlx_fftfreq`, `mlx_rfftfreq`, in Fortran's dimension order
   and with Fortran's array element order for the half-size dimension, against a double-precision direct
   transform. Calibrated by ruling R4.
3. **The matrix products of Phase 4:** `mlx_gather_mm`, `mlx_block_masked_mm`, `mlx_segmented_mm`, against
   Fortran's `matmul` on the selected blocks.

The `fast` normalisations and attention of decision 17, the random half of Phase 5 and the rest of Phase 4
stay pending.

**Exit:** the 15 lines are public and the ledger's pending count is 113; `unit_fast`, `unit_fft` and
`unit_linalg` pass on both devices (the Metal kernel on the GPU; on the CPU its refusal is tested); the
existing suites keep their assertions; Debug and Release with `MLXF_WERROR=ON` and no warning; the build and
gate bounds hold; `scripts/check_tree.sh` passes. Progress lists the new names with their signatures for the
maintainer's read, as Phase 3's entry did.

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
| `scripts/mlxc_parity.txt` | the ledger (new) | 0, 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `scripts/check_rules.py` | rule `parity`; `ENTRY_HELPERS` for new helpers | 0, 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `scripts/check_rules.py` | rule `cbstop` also reads a stop that is the action of a one-line `if` (a planted `if( num == 0 ) error stop 3` in a trampoline passed the gate in Phase 6; row added by run `mlxf_parity_rest` before the edit); the handle types, lifetime bindings and callbacks of the new types (`HANDLE_TYPES`, `ENTRY_IF_LIVE`, `CALLBACKS`) | 6, 7, 8 |
| `scripts/check_rules.py` | rule `handle`: every type of `HANDLE_TYPES` is defined with a `final` procedure and a defined assignment (a planted `mlx_group` without its finalizer passed the gate in Phase 8; row added by run `mlxf_parity_rest` before the edit) | 8 |
| `scripts/check_tree.sh` | the header comment's list of rules names `handle` (row added by run `mlxf_parity_rest` in Phase 8, before the edit) | 8 |
| `scripts/probes/mlx_behaviour_probe.c` (new) | Phase 0's probes of MLX behaviour, re-run on a new MLX release or Mac; Phase 4 adds the linalg functions left unprobed | 0, 4 |
| `scripts/probes/expm1_gpu_probe.c` (new) | ruling R4: the GPU `expm1` defect's probe, quoted by the Apple entry | 1 |
| `.github/skills/mlxf-binding/SKILL.md`, `CLAUDE.md`, `doc/architecture_principles.md` | decision 1 | 0 |
| `src/core/array/mlxf_array.f90`, `mlxf_array_operations.f90` | interfaces and new signature helpers | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `src/core/array/mlxf_array_transfer.f90`, `mlxf_array_tester.f90` | decision 13 | 3 |
| `src/core/array/mlxf_array_tester.f90` | the use-block form the static gate checks (one line of the launch edit) | 1 |
| `src/core/array/mlxf_array_borrow.f90` | decision 13's `mlx_view` and `mlx_alloc` of int8 and int16, which live in the borrowing submodule and not in `mlxf_array_transfer` (row added by the run in Phase 3, before the edit) | 3 |
| `src/core/ops/*` (existing and new submodules `mlxf_ops_math`, `mlxf_ops_index`, `mlxf_ops_sort`) | operations | 1, 2, 3, 4 |
| `src/core/ops/mlxf_ops.f90`, `mlxf_ops_index.f90`, `mlxf_ops_shape.f90` | the shift of 1-based index arrays, `zero_based`, moves to the array module as `mlxf_zero_based`, where the gathered and segmented products of `src/core/linalg` share it; the index wrappers and the two takes call it there (row added by the run in Phase 10, before the edit; `mlxf_ops_shape.f90` joined it when the build named its two calls) | 10 |
| `src/core/linalg/*` | linear algebra, products, convolutions | 4, 10 |
| `src/core/fft/mlxf_fft_nd_tester.f90`, `src/core/linalg/mlxf_linalg_matrix_tester.f90`, `mlxf_linalg_mm_tester.f90`, `mlxf_linalg_products_tester.f90`, `src/core/ops/mlxf_ops_math_tester.f90` | ruling R6 of run `mlxf_parity_rest`: the thirty statements `NANMAX_LEDGER` listed go through `nan_max` or `nan_maxval`, or lose the accumulation's form; no expected value, tolerance or count moves (row added by the run before the edit) | 5 |
| `src/core/fft/*` | FFTs | 5, 10 |
| `src/core/random/*` (new) | random | 5 |
| `src/core/array/mlxf_array_random.f90` (new) | the signature helpers of the samplers, a submodule of `mlxf_array` by concern, as `mlxf_array_closure` is; `mlxf_array_operations.f90` keeps the operations' (row added by run `mlxf_parity_rest` in Phase 5, before the file was written) | 5 |
| `src/core/transforms/*` (new), `src/core/compile/*` | transforms, compile controls, export | 6 |
| `src/core/fast/*` (new) | fast, Metal kernels | 7, 10 |
| `src/core/array/mlxf_array_fast.f90` (new) | the signature helpers of the fused layers, a submodule of `mlxf_array` by concern (row added by run `mlxf_parity_rest` in Phase 7, before the file was written) | 7 |
| `src/core/io/*`, `src/core/distributed/*` (new), `src/core/runtime/mlxf_stream.f90` (new), `src/core/runtime/mlxf_device.f90`, `mlxf_memory.f90`, `mlxf_libc.f90` | decisions 14, 15, 18, 19 | 8 |
| `src/core/array/mlxf_array_io.f90`, `mlxf_array_distributed.f90` (new), `mlxf_array_evaluation.f90` | the helpers of file input and of the distributed operations, two submodules of `mlxf_array` by concern; in the evaluation submodule `mlx_synchronize` becomes a generic's specific that also waits on the default stream (`mlx_synchronize_default`), and `mlx_buffer_size` and the bindings `nbytes` and `itemsize` are implemented there (they evaluate or query an array; `mlxf_array_lifetime.f90`, the handle model, is not touched) (row added by run `mlxf_parity_rest` in Phase 8, before the edits) | 8 |
| `src/core/runtime/mlxf_stream_tester.f90` (new) | the tests of streams and of the runtime controls of decision 19, a sub-suite of `unit_core` (row added with the one above) | 8 |
| `src/core/<dir>/<dir>.inf` | per new or changed folder | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `src/defs/mlxf_defs.f90` | spec records, vocabularies | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `src/core/mlxf.f90` | re-exports | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `src/test/mlxf_test_utils.f90`, `src/test/mlxf_test_defs.f90` (if needed) | assertions for the table-driven testers; frozen tolerances | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `src/test/mlxf_test_registry.f90`, `test/CMakeLists.txt`, `scripts/run_fast_gate.sh` (if needed) | areas, budget | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md` (if needed) | the contract | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `README.md` | API table | 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `CONTRIBUTING.md`, `doc/quickstart.md`, `test/consumer/mlxf_example_differences.f90` | the count of fast entries and the budget where `CONTRIBUTING.md` states them; a row of the quickstart's table for a difference a new family brings, with its block in the example the consumer check runs (rule `docex`) (row added by run `mlxf_parity_rest` in Phase 5, before the edits) | 5, 6, 7, 8 |
| `doc/collaboration/apple_questions.md` | decision 22 | 0, 1, 2, 3, 4, 5, 6, 7, 8, 10 |
| `doc/history/2026-11.md`, `doc/history/2026-12.md` | delivered batches | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 |
| this plan (Progress), `mlxf_mlxc_parity_report.md` (new) | record | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 |

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

### Phase 10, part 1, the custom Metal kernel: 2026-11-24 22:56 EST (a scratch copy on the M5 Ultra, Claude)

- *Machine and base.* HanssMacStudio, the M5 Ultra (macOS 27.2, GFortran 16.2.0, CMake 4.5.1, Homebrew MLX 0.32.4
  and mlx-c 0.8.0). Base: `d0b1091` plus the maintainer's uncommitted toy refactoring and document edits (the
  working tree of 2026-11-24, evening; a snapshot of it is the reference of every count below). Ruling of
  `spec/rulings.md`: the hold after Phase 3 is released, the API as delivered. R1, R3 and R4 apply. Paths
  below are under the run's root, `.../scratchpad/wrappers_work`.
- *The base's counts (measured, `scratch/keep/base/`, Debug and Release alike, both devices / CPU / GPU):* core
  80 to 82 / 55 or 56 / 55 or 56 (the address-reuse checks), array 179 / 96 / 94, ops 2,402 / 1,439 / 965,
  linalg 32 / 17 / 15, fft 57 / 29 / 28, compile 63 / 32 / 32, kernels 1,063 / 539 / 531 (993 before the toy
  refactoring). `GPU devices: 1`. Zero warnings; `scripts/check_tree.sh` passes.
- *Read before the spec was fixed:* mlx-c's `fast.h` and `fast.cpp`; MLX's `docs/src/dev/custom_metal_kernels.rst`,
  `mlx/backend/common/metal_kernel.cpp`, `mlx/backend/metal/custom_kernel.cpp` and the kernel tests of
  `python/tests/test_fast.py`, all at `v0.32.4`.
- *Files.* New: `src/core/fast/mlxf_fast.f90` (module `mlxf_fast`: `type(mlx_metal_kernel)`),
  `mlxf_fast_tester.f90`, `fast.inf`. Changed: `src/defs/mlxf_defs.f90` (`mlx_metal_kernel_spec`);
  `src/core/array/mlxf_array.f90` and `mlxf_array_operations.f90` (the dtype check becomes the shared helper
  `mlxf_check_dtype`); `src/core/mlxf.f90`; `src/test/mlxf_test_registry.f90` (area `fast`, two guards);
  `test/CMakeLists.txt` (`unit_fast`, budget 9); `scripts/mlxc_parity.txt`; `scripts/check_rules.py`
  (`PARITY_PENDING` 126, `mlx_metal_kernel` among the handle types of rules `ctorcall` and `ctorexpr`, its
  assignment and `kill` among the lifetime bindings of rule `entry`); the binding policy (section 12 new;
  sections 2, 6, 9), the test policy (budget 9), `README.md`.
- *Exit items of the part.*
  - The two lines are `public`: `mlx_fast_metal_kernel_new` as `mlx_metal_kernel`, `mlx_fast_metal_kernel_apply`
    as `mlx_metal_kernel%apply`. Ledger: 128 to 126 pending (7: 9 to 7); 14 lines go from `internal` to
    `plumbing` (the kernel's `free`, the ten `config` functions, `mlx_vector_string_new`, `_append_value`,
    `_free`) *(exact)*. Rule `parity` passes.
  - `unit_fast` passes in both builds: 93 checks with both devices, 13 with `device=cpu`, 81 with `device=gpu`
    (`scratch/keep/part1/area_part1_{Debug,Release}_fast_*.log`). On the GPU every result is exact
    (`bits_equal`, or integer equality); on the CPU device the refusal is tested: a status, the message
    "[metal_kernel] Only supports the GPU", no output, and the CPU device usable afterwards.
  - Phase 7's test: `test_column_index`, x(i, j) + j on a (5, 3) float32 array, exact, with the row number as
    the negative control.
  - Decision 28's tests. Every member of `mlx_metal_kernel_spec` is exercised: `name`, `source`, `input_names`,
    `output_names`, `grid`, `threadgroup`, `output_shapes` in all; `header`, the six `template_*` members and the
    equal sharing of `output_shapes` in `test_template_and_header` (a dtype, an integer and a logical
    parameter; a second kernel with -2 and false gives the other results); `output_ranks` and `output_dtypes` in
    `test_two_inputs_two_outputs` (**two inputs and two outputs**: a (4, 3) float32 matrix and 3 weights, a
    (4, 3) float32 and a (12) int32 output); `ensure_row_contiguous` both ways in `test_strided_input` (the
    copy, the storage order without it, `elem_to_loc` without it); `atomic_outputs` and `init_value` in
    `test_atomic_outputs` (**4,096 weighted int32 updates colliding in 13 bins and in a rank-0 total, exact**,
    from 0 and from 5); `verbose` in `test_grid_2d`. **A result used inside a compiled function:**
    `test_compiled_function` (a callback builds and applies the kernel and doubles its result; `mlx_compile`
    traces it once for two arrays; compiled and uncompiled results are byte-identical and exact).
  - Beyond the plan's list: a two-dimensional grid; complex64 and rank-0 inputs; a kernel without inputs; the
    lifecycle (one live object per kernel, copies, idempotent `kill`, empty kernels in an OpenMP region); the
    refusals through `status` (a wrong number of inputs, an empty input, a float64 output; at the evaluation
    a source that does not compile and a threadgroup above the device's limit), with MLX usable after each.
    Two guards joined `object_contracts` (15 members): a spec without outputs, an empty kernel applied.
  - Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings; fast gate 9 of 9 in both with
    `scripts/check_tree.sh` first (`scratch/keep/part1/{build,gate}_part1_{Debug,Release}.log`). The existing
    areas keep the base's counts in both builds (`scratch/keep/part1/areas_part1_*.txt`). A first Release
    build failed on `-Wfunction-elimination` in the new tester (an impure call after `.and.`, the trap the
    earlier phases met), fixed with two assertions.
  - Six planted violations fail and the restored copy passes (`scratch/keep/part1_plants.txt`): the ratchet
    left at 128, a config setter the library calls classed `internal`, `mlx_metal_kernel` missing from
    `mlxf.f90`'s public block, `apply` looking at its kernel before the entry, a parenthesized kernel handle
    in an array constructor, the area missing from CTest.
  - `unit_fast` in the Release gate: 0.19 to 0.59 s beside the other entries, 0.08 s alone *(measured)*,
    against the 3 s bound of a new area.
- *The new public names.*
  - `type(mlx_metal_kernel_spec)`, a record: `name`, `source`, `header` (deferred-length characters);
    `input_names(:)`, `output_names(:)` (character arrays); `grid(3)`, `threadgroup(3)` (default `[1, 1, 1]`);
    `output_shapes(:)`, `output_ranks(:)`, `output_dtypes(:)`; `template_dtype_names(:)` with
    `template_dtypes(:)`, `template_int_names(:)` with `template_ints(:)`, `template_bool_names(:)` with
    `template_bools(:)`; `init_value` (an allocatable real32: unset means none);
    `ensure_row_contiguous = .true.`, `atomic_outputs = .false.`, `verbose = .false.`.
  - `type(mlx_metal_kernel)`: `k = mlx_metal_kernel(spec)`, `call k%new(spec)`,
    `call k%apply(inputs, outputs[, status])` (`inputs(:)` an array of handles, `outputs(:)` allocatable,
    `intent(out)`), `call k%kill()`, defined assignment, finalization.
- *What a Fortran user must know about the buffers in a kernel's source.* The source is the one place where
  MLX's layout shows: row-major, 0-based, the shape reversed. A Fortran array `a(n1, n2)` is MLX's `[n2, n1]`,
  so in the source `a_shape[0]` is n2 and `a_shape[1]` is n1, and element `a(i, j)` is
  `a[(j-1)*n1 + (i-1)]`: the buffer is the array in Fortran's array element order, and what changes is only
  how MLX's shape names the extents. Worked example, the test's kernel: for `x(5, 3)` with
  `grid = [15, 1, 1]` the thread `elem = thread_position_in_grid.x` handles element `elem + 1` of the array
  in array element order; its column is `elem / inp_shape[1] + 1` (`inp_shape[1]` is 5, the first extent) and
  its row `elem % inp_shape[1] + 1`; `out[elem] = inp[elem] + float(elem / inp_shape[1] + 1)` gives
  x(i, j) + j. With `grid = [5, 3, 1]`, `thread_position_in_grid.x` is i - 1 and `.y` is j - 1, at position
  `y*5 + x`. Three more facts: a strided input (a transpose, a section) is copied first unless
  `ensure_row_contiguous` is false, and then the source must use the strides; an input of fewer than 8
  elements arrives in Metal's `constant` address space and a rank-0 input as a reference (`scale`, not
  `scale[0]`); index values are what the program stored, so 1-based Fortran indices need `- 1` in the source.
- *Decisions under delegation.*
  - **The launch configuration belongs to the kernel object.** `new` reads the whole spec (mlx-c's kernel and
    its `config` are made once and freed together); `apply` takes only the arrays, as `mlx_function`'s does.
    Another grid or output shape is another kernel from the edited spec. That costs nothing that matters: MLX
    compiles a generated source once per process; the first evaluation of a new source took 60 ms and a second
    kernel object with the same source and another grid 0.2 ms for building, applying and evaluating
    *(measured, `scratch/keep/part1_kernel_cache_probe.txt`)*.
  - **`apply` is a checked procedure**, `(inputs, outputs[, status])`, though it builds a graph node: the
    refusal on the CPU must be testable in-process, and a callback of a compiled function must be able to
    return a kernel's failure instead of stopping inside C++ frames. `new` stops on an invalid spec, as
    `mlx_function`'s does. An empty or stale kernel stops in `apply` with or without `status`.
  - **The spec gained `init_value` and `verbose`**, which decision 17's list does not name and mlx-c's config
    has: decision 28's atomic test cannot be written without an initial value (the outputs start undefined),
    and the generated source that `verbose` prints is what one reads when a kernel does not compile.
  - **The spec is a record of plain components** in `mlxf_defs`, with no second public type: the outputs'
    shapes are one list with `output_ranks` (absent: shared equally), and the template parameters three pairs
    of lists by kind. MLX orders template parameters; the three kinds are passed dtypes first, then integers,
    then logicals, which changes nothing a source can see.
  - **Defaults:** float32 outputs, `[1, 1, 1]` for the grid and the threadgroup (both are checked to be
    positive), no header, no input.
  - **The stream is the default device's**, as for every operation; MLX refuses a CPU stream. The wrapper does
    not move a kernel to the GPU behind a CPU default.
  - **The module is `mlxf_fast`** in `src/core/fast/`, named as the mlx-c header, as `mlxf_fft` and
    `mlxf_compile` are; `mlx_layer_norm` and the others of decision 17 join it in Phase 7.
  - **`mlxf_check_dtype`** replaces the operations submodule's private `check_dtype`, so that the kernel's
    dtypes are checked by the one routine (mlx-c indexes a table with a dtype unchecked).
- *Surprises about MLX and mlx-c (the first three measured, `scratch/keep/part1_kernel_failures_probe.txt`; the
  fourth read in the sources).*
  - A source that does not compile is not an abort: `mlx_eval` returns a status, `mlx_last_error()` holds
    "[metal::Device] Unable to build metal library from source" with the Metal compiler's line and caret, and
    MLX evaluates other kernels afterwards.
  - The threadgroup is checked at the evaluation against the device's limit, 1,024 threads on the M5 Ultra,
    before the grid clips it: `threadgroup = [4096, 1, 1]` fails even with a grid of 16.
  - A float64 output is refused when the kernel is applied ("float64 is not supported on the GPU").
  - mlx-c's `mlx_fast_metal_kernel_new` passes no compile options, so a kernel is always built in MLX's
    default "safe" math mode; MLX's `compile_options` (0.32.4) is not reachable from C (question 21 of
    `doc/collaboration/apple_questions.md`).
- *What it means, in short:* a Fortran program can write a Metal kernel as text, launch it on arrays and use
  the result in a graph or a compiled function, with errors as statuses; K1, K2, K5 and K6 have their base.

### Phase 10a, the calibration of the transforms over several dimensions: 2026-11-24 23:06 EST (Claude)

- *How.* The new tester `mlxf_fft_nd_tester` (sub-suite `fft_nd` of `unit_fft`) built in Debug with its seed
  list held to the calibration seed alone and its tolerances at the ceiling, run as
  `mlxf_test_exec test=unit_fft suite=fft_nd device=cpu|gpu` (logs
  `scratch/keep/phase10a_fft_nd_{cpu,gpu}_seed1.log`, table `scratch/keep/phase10a_frozen.txt`). Both devices on
  seed 1, as R4 rules; no seed 2 or 3 ran before this entry. Each transform runs on 8 seeded (6, 5, 4) fixtures
  (`FFT_NBATCH`), uniform in [-1, 1] and rounded once to float32, in 5 to 7 forms: dimensions given or not, in
  and out of order, lengths that pad and truncate, the three norms; the form without dimensions on each fixture
  as a rank-3 array, the others on the batch along a fourth dimension. The reference is a direct DFT in real64,
  one dimension after another; an inverse real transform takes the half spectrum of a real fixture, rounded to
  complex64, and its reference is computed from the rounded spectrum (the other dimensions first, then the real
  lines along the half-size dimension).
- *The error (decision under delegation).* A transform's error is its largest element error relative to
  `max(1, the largest |reference| of the result)`, not to each element's own magnitude: an element near a zero
  of a spectrum carries the rounding of the whole transform, so an element-wise relative error would measure
  cancellation, not the function. The frequencies use the element-wise error of section 6.
- *Observed on seed 1, CPU / GPU, in float32 epsilons (measured):* `mlx_fftn` 1.068 / 1.086, `mlx_ifftn`
  1.482 / 1.547, `mlx_rfftn` 0.920 / 1.192, `mlx_irfftn` 1.830 / 2.089, `mlx_rfft2` 0.807 / 0.886, `mlx_irfft2`
  2.012 / 1.859, `mlx_fftfreq` 0.533 / 0.533, `mlx_rfftfreq` 0.533 / 0.533. A float64 input on the CPU gives the
  float32 error exactly (`mlx_rfftn` 0.920, `mlx_rfft2` 0.807): MLX transforms in float32. None is near the
  64 eps ceiling: no finding. The shifts are exact and need no calibration.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`FFT_TOLERANCES`), `max(2 x the larger of the CPU and GPU seed-1
  errors, 4 eps32)` *(derived)*: `mlx_irfftn` **4.979893410e-07** (4.177 eps32), `mlx_irfft2`
  **4.796738626e-07** (4.024 eps32), the six others the floor 4 eps32 = 4.768371582e-07. The float64 column
  holds the same values (the float32 bound).

### Phase 10, part 2, the FFT lines of Phase 5: 2026-11-24 23:11 EST (a scratch copy on the M5 Ultra, Claude)

- *Machine, base and rulings:* as part 1's entry; the tree is the base plus part 1.
- *Files.* `src/core/fft/mlxf_fft.f90` (ten wrappers; `mlx_fft2` and `mlx_ifft2` now build an
  `mlxf_fftn_spec`), the new `mlxf_fft_nd_tester.f90`; `src/defs/mlxf_defs.f90` (`mlxf_fftn_spec`);
  `src/core/array/mlxf_array.f90` and `mlxf_array_operations.f90` (`mlxf_fftn_op` replaces `mlxf_fft2_op` for the
  same C signature and takes any number of dimensions; `mlxf_freq_op`; the translation of dimensions to axes
  becomes the shared `mlxf_axes_of`); `src/core/mlxf.f90`; `src/test/mlxf_test_defs.f90` (`FFT_TOLERANCES`,
  `FFT_NBATCH`), `src/test/mlxf_test_registry.f90` (row `fft_nd` of area `fft`); `scripts/mlxc_parity.txt`,
  `scripts/check_rules.py` (`PARITY_PENDING` 116, `ENTRY_HELPERS`); the binding policy (section 10),
  `README.md`.
- *Exit items of the part.*
  - The ten lines are `public`: `mlx_fft_fftn`, `_ifftn`, `_rfft2`, `_irfft2`, `_rfftn`, `_irfftn`, `_fftshift`,
    `_ifftshift`, `_fftfreq`, `_rfftfreq`. Ledger: 126 to 116 pending (5: 29 to 19) *(exact)*.
  - `unit_fft` passes on both devices in both builds: 192 checks, 100 with `device=cpu`, 93 with `device=gpu`
    (`scratch/keep/part2/area_part2_{Debug,Release}_fft_*.log`): the existing sub-suite `fft` unchanged at 57
    (29 / 28) and the new `fft_nd` 135 (71 / 65).
  - Sub-phase 10b, seeds 2 and 3 after the freeze of entry "Phase 10a": first run 23:06 EST
    (`scratch/keep/phase10b_unit_fft_debug.log`, 188 of 188, before four exact shift checks were added). No
    judged check has failed in any run. Largest judged errors on seeds 2 and 3, in float32 epsilons
    *(measured)*: `mlx_irfftn` 2.418 (CPU, tolerance 4.177), `mlx_irfft2` 1.956 (4.024), `mlx_ifftn` 1.684,
    `mlx_fftn` 1.568 (GPU), `mlx_rfftn` 1.269 (GPU), `mlx_rfft2` 0.966, the frequencies 0.461, against the
    floor 4.
  - Exact checks: the shifts against Fortran's `cshift` (every dimension, one, two, an odd extent of a rank-2
    array; `mlx_ifftshift` undoes `mlx_fftshift` and two forward shifts along an odd extent do not);
    `mlx_fftshift(mlx_fftfreq(n))` ascends with zero at element n/2+1; `mlx_fftn` over two dimensions is
    `mlx_fft2` bit for bit; the shapes that state the half-size dimension and the inverse's default length.
  - Seven mutations of the wrappers on a scratch copy each fail the sub-suite, and the restored copy passes
    (`scratch/keep/part2_mutations.txt`): the last listed dimension halved (30 of 131 checks fail), the
    inverse's default length the extent (16), lengths not reversed with the dimensions (46), the two shifts
    exchanged (12), a shift's dimensions passed 0-based (2, then 6 of 135 after two checks were added: a shift
    along the middle dimension of a rank-3 array could not tell a translated axis from a 0-based one),
    `mlx_fftfreq` given 1/d (6).
  - Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings; fast gate 9 of 9 in both
    (`scratch/keep/part2/{build,gate}_part2_{Debug,Release}.log`); the other areas keep the base's counts and
    `unit_fast` its 93 (`scratch/keep/part2/areas_part2_*.txt`). A first Debug build failed on
    `-Winteger-division` (5/2 written with named constants in the tester), fixed with the half extents as
    constants; rule `arity` then refused two test procedures of six arguments, which now take a record.
- *Frozen tolerances:* entry "Phase 10a", unchanged since. Upstream-defect lines: 0.
- *The new public names.* `dims` and `n` are integer arrays, `[x]` optional and passed by keyword.
  - `mlx_fftn(a[, dims][, n][, norm])`, `mlx_ifftn(a[, dims][, n][, norm])`;
  - `mlx_rfftn(a[, dims][, n][, norm])`, `mlx_irfftn(a[, dims][, n][, norm])`;
  - `mlx_rfft2(a, dims[, n][, norm])`, `mlx_irfft2(a, dims[, n][, norm])`, `dims(2)` and `n(2)`;
  - `mlx_fftshift(a[, dims])`, `mlx_ifftshift(a[, dims])`;
  - `mlx_fftfreq(n[, d])`, `mlx_rfftfreq(n[, d])`, `d` real64.
- *Decisions under delegation.*
  - **The half-size dimension of a real transform is the first listed, `dims(1)`**, and dimension 1 when
    `dims` is absent: a real (n1, n2, n3) array has the (n1/2+1, n2, n3) spectrum, as FFTW's Fortran interface
    and SIMPLE's images have it. This is what the plan's "Fortran's array element order for the half-size
    dimension" is read to mean. MLX halves the last axis it is given, so the wrapper lists `dims(1)` last; for
    the default it is MLX's own default, since dimension 1 is MLX's last axis. No extra node.
  - **`n` is paired with `dims` in the caller's order**, as `mlx_fft2`'s is; with `dims` absent, with
    dimensions 1 to rank. A complex transform passes the dimensions to MLX in the caller's order (so two
    dimensions are `mlx_fft2` bit for bit) and, without `dims`, in MLX's own default order.
  - **`dims` is optional for the `n`-dimensional transforms and required for `mlx_rfft2` and `mlx_irfft2`**,
    as it is for `mlx_fft2`.
  - **One helper for the C signature of `fft2`, `fftn`, `rfft2`, `rfftn` and their inverses:** `mlxf_fft2_op`
    became `mlxf_fftn_op`, with a record of allocatable lists; `mlx_fft2` and `mlx_ifft2` pass it the same
    axes and lengths as before (their 57 checks are unchanged). `mlxf_fft_spec` keeps its two-element lists,
    of which the one-dimensional helper reads the first.
  - **`mlxf_axes_of` is the array module's translation of dimensions to axes, now shared** (the shifts need
    it). `mlxf_ops` keeps its own `axes_of`, which is outside this phase's file table: one of the two can go.
  - **The frequencies take `d` as real64** (C's `double`), as `mlx_linspace` takes its bounds.
  - **The error of a transform** is relative to the largest |reference| of its result (entry "Phase 10a").
  - **An inverse real transform is tested on lengths that change the half-size dimension only** (odd, padded,
    truncated). A length that cuts or pads another dimension makes an input that is not the half spectrum of a
    real array, where MLX defines no result; the policy says so.
- *Surprises about MLX and mlx-c:* none in the transforms; both devices agree with the direct DFT to 2.5
  float32 epsilons of the largest element. A float64 input gives the float32 result bit for bit (the same
  error to ten digits), as the policy already says of every FFT.
- *What it means, in short:* volumes and images transform in Fortran's layout, real ones with the half
  dimension first, on both devices; K2's bench and K8's PCG solve have their transforms.

### Phase 10c, the calibration of the gathered, masked and segmented products: 2026-11-24 23:21 EST (Claude)

- *How.* The new tester `mlxf_linalg_mm_tester` (sub-suite `linalg_mm` of `unit_linalg`) built in Debug with its
  seed list held to the calibration seed alone and its tolerances at the ceiling, run as
  `mlxf_test_exec test=unit_linalg suite=linalg_mm device=cpu|gpu` (logs
  `scratch/keep/phase10c_linalg_mm_{cpu,gpu}_seed1.log`, table `scratch/keep/phase10c_frozen.txt`). Both devices
  on seed 1 (R4); no seed 2 or 3 ran before this entry. Operands uniform in [-1, 1], rounded once to float32;
  the reference is real64 `matmul` of the sections a form selects. `mlx_gather_mm`: (5, 4) by (4, 6) matrices,
  6 of them in a (3, 2) batch against 5, in four forms (two rank-1 lists of 7, int32 and int64; lists that
  broadcast to (3, 4); one sorted list with the other operand in order; the other list alone).
  `mlx_block_masked_mm`: (70, 40) by (40, 50), blocks of 32 (three, two and two) in six forms (the result's
  mask, the operands', the three, the default block of 64, a real mask, a batch of two).
  `mlx_segmented_mm`: (5, 12) by (12, 6) with four segments, one empty, and a (2, 2, 3) array of segments.
- *The error (decision under delegation).* An element's error relative to `max(1, (|a| |b|)(i, j))`: the
  product of the absolute values is the scale of a dot product's rounding, as in the existing `matmul` test.
- *Observed on seed 1, CPU / GPU, in float32 epsilons (measured):* `mlx_gather_mm` 0.702 / 0.702,
  `mlx_block_masked_mm` 1.508 / 1.497, `mlx_segmented_mm` 0.723 / 0.723; float64 on the CPU, `mlx_segmented_mm`
  0.98 eps64. No finding.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`MM_TOLERANCES`), `max(2 x the larger of the CPU and GPU seed-1
  errors, 4 eps)` of the result kind *(derived)*: the float32 floor 4.768371582e-07 for the three, and the
  float64 floor 8.881784197e-16 for `mlx_segmented_mm` on the CPU. The first two have no float64 result to
  judge (MLX 0.32.4 evaluates them in float32 only).

### Phase 10, part 3, the matrix products of Phase 4: 2026-11-24 23:25 EST (a scratch copy on the M5 Ultra, Claude)

- *Machine, base and rulings:* as part 1's entry; the tree is the base plus parts 1 and 2.
- *Files.* `src/core/linalg/mlxf_linalg.f90` (three wrappers), the new `mlxf_linalg_mm_tester.f90`;
  `src/core/array/mlxf_array.f90` and `mlxf_array_operations.f90` (`mlxf_gather_mm_op`, `mlxf_masked_mm_op`,
  `mlxf_zero_based`); `src/core/ops/mlxf_ops.f90`, `mlxf_ops_index.f90`, `mlxf_ops_shape.f90` (their
  `zero_based` is now the array module's; the file-table row was added before the edit);
  `src/core/mlxf.f90`; `src/test/mlxf_test_defs.f90` (`MM_TOLERANCES`), `src/test/mlxf_test_utils.f90`
  (`judge_error`, `find_tolerance`, used by the two new testers of parts 2 and 3),
  `src/test/mlxf_test_registry.f90` (row `linalg_mm` of area `linalg`); `scripts/mlxc_parity.txt`,
  `scripts/check_rules.py` (`PARITY_PENDING` 113, `ENTRY_HELPERS`); the binding policy (section 10),
  `README.md`.
- *Exit items of the part.*
  - The three lines are `public`: `mlx_gather_mm`, `mlx_block_masked_mm`, `mlx_segmented_mm`. Ledger: 116 to
    113 pending (4: 40 to 37) *(exact)*.
  - `unit_linalg` passes on both devices in both builds: 94 checks, 50 with `device=cpu`, 45 with
    `device=gpu` (`scratch/keep/part3/area_part3_{Debug,Release}_linalg_*.log`): the existing sub-suite
    `linalg` unchanged at 32 (17 / 15) and the new `linalg_mm` 62 (33 / 30).
  - Sub-phase 10d, seeds 2 and 3 after the freeze of entry "Phase 10c": first run 23:21 EST
    (`scratch/keep/phase10d_unit_linalg_debug.log`, 94 of 94). No judged check has failed in any run. Largest
    judged errors on seeds 2 and 3, in float32 epsilons *(measured)*: `mlx_block_masked_mm` 1.534 (GPU; 2.096
    on the CPU after the review enlarged the fixture, below), `mlx_segmented_mm` 1.096, `mlx_gather_mm` 0.797,
    against the floor 4; `mlx_segmented_mm` in float64 on the CPU is exact on seeds 2 and 3.
  - Exact checks: a block a mask drops and a reversed segment are exactly zero; without lists and without
    masks the two products are `matmul` bit for bit; matrix 4 of a (5, 4, 3, 2) array is `a(:,:,1,2)`, and
    the row-major reading `a(:,:,2,2)` fails the same bound.
  - Six mutations of the wrappers on a scratch copy each fail the sub-suite, three through MLX's own shape
    errors and three through assertions, and the restored copy passes (`scratch/keep/part3_mutations.txt`):
    the lists not exchanged with the operands, b's list passed 1-based, the operand masks not exchanged, a
    segment's last index excluded, the operands of the segmented and of the masked product not exchanged.
  - `unit_ops` keeps 2,402 / 1,439 / 965 after the move of `zero_based`. Debug and Release from scratch with
    `-DMLXF_WERROR=ON`, zero warnings; fast gate 9 of 9 in both
    (`scratch/keep/part3/{build,gate}_part3_{Debug,Release}.log`, `areas_part3_*.txt`).
- *Frozen tolerances:* entry "Phase 10c", unchanged since. Upstream-defect lines: 0.
- *The new public names.*
  - `mlx_gather_mm(a, b[, lhs_indices][, rhs_indices][, sorted_indices])`: the two lists are arrays of the
    graph, of any integer dtype;
  - `mlx_block_masked_mm(a, b[, block_size][, mask_out][, operand_masks])`: `operand_masks(2)` an array of
    two handles, a's mask then b's;
  - `mlx_segmented_mm(a, b, segments)`: `segments` an integer array of the graph, (2, ...).
- *Decisions under delegation.*
  - **The Fortran view costs no transpose and no copy:** the operands are exchanged as for `matmul`, and the
    lists and operand masks with them; a mask and a list of segments in Fortran order are MLX's. The one
    added node is the shift of 1-based values (decision 8).
  - **A matrix is numbered from 1 in array element order over dimensions 3 and up**, which is MLX's flat
    index over its batch axes (the flatten rule of the policy).
  - **Segments are inclusive 1-based bounds**, `segments(1, i):segments(2, i)`, as `mlx_slice`'s: MLX's
    [start, end) is obtained by subtracting [1, 0], one node. A last index below the first is an empty
    section and gives zeros (measured on both devices for gaps up to 299,
    `scratch/keep/part3_reversed_segments_probe.txt`).
  - **`mlx_block_masked_mm` takes the two operand masks as one array of two handles**, both live: with
    `block_size`, `mask_out`, and the two operands that keeps five dummies (rule `arity`), and MLX itself
    treats the two as one group. An all-true mask leaves an operand whole. For the maintainer: three keyword
    masks with the block size inferred from their extents would read better at the call and hide a choice;
    it was not taken.
  - **`block_size` defaults to 64**, MLX's default; MLX accepts 32 and 64 and says so when another is given
    with a mask.
  - **The wrapper checks `mlx_segmented_mm`'s shapes** (two matrices, equal inner extents, a first extent of 2
    for `segments`): MLX checks no inner extent (question 22 for Apple), and the shift of the bounds would
    broadcast a (1, n) array into pairs before MLX's own shape check saw it. Found by the review.
  - **`zero_based` moved to the array module as `mlxf_zero_based`** (with the amounts to subtract as an
    option, for the segments), so that one routine shifts every index array; three files of `src/core/ops`
    joined the file table for it.
  - **The error of a product** is relative to `max(1, (|a| |b|)(i, j))` (entry "Phase 10c").
  - **`judge_error` and `find_tolerance` went to `mlxf_test_utils`** for the two new testers; the three older
    table-driven testers of `src/core/ops` keep their private copies (outside this phase's table).
- *Surprises about MLX and mlx-c.* MLX 0.32.4 evaluates the gathered and the masked product in float32 only:
  on float64 operands the graph builds and the evaluation fails on the CPU with a status, "[GatherMM::eval]
  Currently only supports float32" *(measured, `scratch/keep/part3_products_probe.txt`)*; the segmented
  product is float64 there. All three refuse complex operands when a list, a mask or segments are given
  *(read in `mlx/ops.cpp`)*: K3's complex products need the real formulation.
- *What it means, in short:* products over arbitrary pairs of matrices, over masked tiles and over segments of
  the inner dimension are one call each in Fortran's layout; K3 has its two candidates.

### Phase 10, the kernels' wrappers ahead of their turn: 2026-11-24 23:42 EST (a scratch copy on the M5 Ultra, Claude) - complete

The three parts are done; their entries above ("part 1", "10a", "part 2", "10c", "part 3") hold the detail.
This entry closes the phase and states the final numbers, which supersede the parts' where the review
changed a count.

- *Machine and base.* HanssMacStudio, the M5 Ultra (macOS 27.2, GFortran 16.2.0, CMake 4.5.1, Homebrew MLX
  0.32.4 and mlx-c 0.8.0). Base: `d0b1091` plus the maintainer's uncommitted toy refactoring and document
  edits (decision 28 names that refactoring's commit as the base; it was not yet committed). Rulings: the hold
  is released with no change to the API of Phases 2 and 3 (`spec/rulings.md`); R1, R3 and R4. The work was
  done in a copy of the working tree, never in the maintainer's checkout; nothing is committed. Paths below
  are under the run's root, `.../scratchpad/wrappers_work`.
- *Files changed* (from `diff -rq` against the base snapshot). New: `src/core/fast/` (`mlxf_fast.f90`,
  `mlxf_fast_tester.f90`, `fast.inf`), `src/core/fft/mlxf_fft_nd_tester.f90`,
  `src/core/linalg/mlxf_linalg_mm_tester.f90`. Changed: `src/defs/mlxf_defs.f90`,
  `src/core/array/mlxf_array.f90`, `mlxf_array_operations.f90`, `src/core/fft/mlxf_fft.f90`,
  `src/core/linalg/mlxf_linalg.f90`, `src/core/ops/mlxf_ops.f90`, `mlxf_ops_index.f90`, `mlxf_ops_shape.f90`
  (the row added in part 3), `src/core/mlxf.f90`, `src/test/mlxf_test_defs.f90`, `mlxf_test_registry.f90`,
  `mlxf_test_utils.f90`, `test/CMakeLists.txt`, `scripts/mlxc_parity.txt`, `scripts/check_rules.py`,
  `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md`, `README.md`,
  `doc/collaboration/apple_questions.md`, `doc/history/2026-11.md`, this plan, the report. No file outside the
  table as it now stands; the toy modules, the oracles and the benchmark are untouched.
- *Exit items.*
  - **The 15 lines are public and 113 are pending.** Ledger before: 271 public, 46 plumbing, 146 internal, 89
    excluded, 128 pending (4: 40, 5: 29, 6: 16, 7: 9, 8: 34). After: 286 public, 60 plumbing, 132 internal, 89
    excluded, 113 pending (4: 37, 5: 19, 6: 16, 7: 7, 8: 34) *(exact)*. `PARITY_PENDING = 113`; rule `parity`
    passes. The lines keep their phases; this heading closes none of Phases 4, 5 and 7.
  - **`unit_fast`, `unit_fft` and `unit_linalg` pass on both devices** in both builds
    (`scratch/keep/final/area_final_{Debug,Release}_*.log`, both devices / CPU / GPU): `unit_fast` 94 / 13 /
    82 (the Metal kernel exact on the GPU, its refusal tested on the CPU device); `unit_fft` 194 / 101 / 94
    (`fft` 57 unchanged, `fft_nd` 137); `unit_linalg` 94 / 50 / 45 (`linalg` 32 unchanged, `linalg_mm` 62).
  - **Decision 28's tests of the Metal kernel are present** (part 1's entry lists them by member).
  - **The existing suites keep their assertions** (`scratch/keep/final/areas_final_*.txt`, Debug and Release
    alike): core 82 / 56 / 56, array 179 / 96 / 94, ops 2,402 / 1,439 / 965, compile 63 / 32 / 32, kernels
    1,063 / 539 / 531, and the 57 and 32 above; `object_contracts` passes with 16 members (13 at the base).
  - **Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings**
    (`scratch/keep/final/build_final_{Debug,Release}.log`), installed, **fast gate 9 of 9 in both** with
    `scripts/check_tree.sh` first (`gate_final_*.log`).
  - **The section 6 bounds, judged (R3) against the entry "Phase 2, the base measurements on the M5 Ultra":**
    Release clean build, configure plus build from scratch at `-j 12`: 8.604 s (1.522 + 7.082; load 1.92
    before the script, 2.30 after) and 8.721 s (1.550 + 7.171; load 2.28 before, 2.89 after;
    `scratch/keep/final/second_release_timing.log`) against the bound **14.08 s**: met, 1.23 times the base's
    mean 7.038 s. Fast gate total real time in Release: 10.66 s and 10.77 s against **38.74 s**: met, 2.0 s
    above the base's 8.735 s (`unit_array` alone is the total). The new area `unit_fast`: 0.24 s in the
    Release gate (0.19 to 0.59 s over the phase's gates, 0.08 s alone) against **3 s**: met. The budget is 9
    of at most 13 (decision 21). All *measured*; the bounds *derived* in Phase 2.
  - **`scripts/check_tree.sh` passes;** `restyle_fortran.py` and `format_use_blocks.py` were run on the 16
    Fortran files touched, by name, after the last edit, and rewrote none.
- *Frozen tolerances* (`src/test/mlxf_test_defs.f90`, entries "Phase 10a" and "Phase 10c"): `FFT_TOLERANCES`:
  `mlx_irfftn` 4.979893410e-07, `mlx_irfft2` 4.796738626e-07, the six others 4 eps32 = 4.768371582e-07;
  `MM_TOLERANCES`: 4 eps32 for the three, 4 eps64 = 8.881784197e-16 for `mlx_segmented_mm` in float64. No
  tolerance moved after its freeze. Upstream-defect lines: 0.
- *The independent review* (a read-only subagent, against MLX's source; its one slip: it wrote and deleted a
  scratch copy of `ops.cpp` outside both trees). No translation error and no lifetime defect found. Fixed
  from it:
  - `mlx_segmented_mm` now checks the ranks, the inner extents and the segments' first extent (above), with a
    guard, `guard_segments_shape`;
  - a refused kernel input now says "mlx_metal_kernel apply: an input array is empty or stale" where it
    borrowed the closure's message;
  - blind tests made discriminating: the lengths without `dims` were a palindrome ([4, 8, 4], now [4, 8, 3])
    and absent from the real transforms (a form added to each); b's block mask was square ((2, 2), now
    (2, 4), the fixture (70, 40) by (40, 100)); two outputs sharing extents had equal extents ([9, 9], now
    [9, 3]); the sorted route of `mlx_gather_mm` was not reached (a form with matrices of one column added);
    a reversed segment only one apart (now 9 to 2); uint64 lists and segments added; `mlx_rfftfreq` without
    `d` added. Every judged error stays within its frozen tolerance; `mlx_block_masked_mm`'s largest went
    from 1.534 to 2.096 eps32 with the larger fixture *(measured)*.
  - the policy's wording on extra nodes, on complex operands without a list, on kernels built in callbacks
    and on shapeless compilation.
  Left as they are, for the maintainer: one of about 14 stops of a kernel's `new` has a guard; `apply` without
  `status`, a stale kernel, an output above rank 2 and a template dtype other than float32 have no test; real
  or batched operand masks, vector operands of the three products and a `block_size` MLX refuses have none;
  the FFT stops (a dimension outside the rank, a wrong number of lengths, a repeated dimension) have no
  guard; the float64 refusal of the two float32-only products is measured in a probe and not pinned by a test
  (a later MLX may lift it); a shapeless compiled function holding a kernel is not tested.
- *Decisions under delegation:* in the parts' entries. Those that shape the API: the kernel object owns its
  launch configuration and `apply` is checked; the spec gained `init_value` and `verbose`; the half-size
  dimension of a real transform is the first listed; `n` pairs with `dims` in the caller's order; lists number
  matrices from 1 in array element order; segments are inclusive; the operand masks are one array of two.
  Decisions about the run itself: the base is the uncommitted working tree; parts were gated one by one with
  both builds from scratch; mutations were run on scratch copies with the archive deleted before each build.
- *Proposed, not applied* (skill edits need approval): `.github/skills/mlxf-binding/SKILL.md`, section 3, names
  `mlxf_fft2_op`, which is now `mlxf_fftn_op`, and should list `mlxf_freq_op`, `mlxf_gather_mm_op`,
  `mlxf_masked_mm_op` and the shared `mlxf_axes_of`, `mlxf_zero_based`, `mlxf_check_dtype`; section 4 could
  say "a real transform's half-size dimension is passed last" and "operands, lists and masks of a product are
  exchanged"; `references/testing.md` could warn that Apple's make compares whole seconds.
- *The new public names of the phase, for the maintainer's read.* Arrays are `type(mlx_array)`; `[x]` is
  optional and passed by keyword; `dims` and `n` are integer arrays.
  - **Custom kernels:** `type(mlx_metal_kernel_spec)` (members in part 1's entry);
    `k = mlx_metal_kernel(spec)`, `call k%new(spec)`, `call k%apply(inputs, outputs[, status])`,
    `call k%kill()`.
  - **Transforms:** `mlx_fftn(a[, dims][, n][, norm])`, `mlx_ifftn(a[, dims][, n][, norm])`,
    `mlx_rfftn(a[, dims][, n][, norm])`, `mlx_irfftn(a[, dims][, n][, norm])`,
    `mlx_rfft2(a, dims[, n][, norm])`, `mlx_irfft2(a, dims[, n][, norm])`, `mlx_fftshift(a[, dims])`,
    `mlx_ifftshift(a[, dims])`, `mlx_fftfreq(n[, d])`, `mlx_rfftfreq(n[, d])`.
  - **Products:** `mlx_gather_mm(a, b[, lhs_indices][, rhs_indices][, sorted_indices])`,
    `mlx_block_masked_mm(a, b[, block_size][, mask_out][, operand_masks])`,
    `mlx_segmented_mm(a, b, segments)`.
- *Where a Fortran user would expect something else* (each stated in the binding policy, sections 10 and 12):
  - a kernel's source is MLX's layout: 0-based, row-major, the shape reversed (the worked example of part 1);
  - a kernel object is for one grid and one set of output shapes; another shape is another object;
  - `mlx_rfftn` halves the first listed dimension, where NumPy and MLX halve the last axis; an odd real length
    of an inverse needs `n`;
  - `mlx_fftshift` is `cshift` by minus extent/2, `mlx_ifftshift` by plus extent/2;
  - `mlx_block_masked_mm` takes its operand masks as one array of two, and blocks are of 32 or 64 only;
  - the gathered and the masked product are float32 only in MLX 0.32.4, and none of the three takes complex
    operands;
  - nothing checks a list's values or a segment's bounds against the extents.
- *What it means, in short:* the wrappers that K1 to K8 wait for exist, in Fortran's conventions, tested on
  both devices: a Metal kernel from source text, the n-dimensional and real transforms, and the gathered,
  masked and segmented products. 113 ledger lines remain for Phases 4 to 8.

### Phase 4a, the calibration of the products: 2026-11-25 00:09 EST (a scratch copy on the M5 Ultra, Claude)

- *How.* The new tester `mlxf_linalg_products_tester` (sub-suite `linalg_products` of `unit_linalg`) built in
  Debug with the seed list held to the calibration seed alone and its tolerances at the ceiling, run as
  `mlxf_test_exec test=unit_linalg suite=linalg_products device=cpu|gpu` (logs
  `scratch/keep/phase4a_products_{cpu,gpu}_seed1.log`). Both devices on seed 1 (R4); no seed 2 or 3 ran
  before this entry. Operands uniform in [-1, 1], rounded once to float32; the reference is the product
  written out in real64 loops over Fortran subscripts; an element's error is relative to `max(1,` the same
  product of the magnitudes`)`, as for the matrix products of entry "Phase 10c".
- *Observed on seed 1, CPU / GPU, in float32 epsilons (measured):* `mlx_inner` 0.643 / 0.562, `mlx_outer`
  0.111 / 0.111, `mlx_kron` 0.240 / 0.240, `mlx_vecdot` 0.479 / 0.479, `mlx_cross` 0.380 / 0.380,
  `mlx_tensordot` 0.698 / 0.698, `mlx_einsum` 0.648 / 0.648, `mlx_addmm` 0.570 / 0.570,
  `mlx_hadamard_transform` 0.436 / 0.436. float64 on the CPU: at most 0.25 eps64 (`mlx_tensordot`,
  `mlx_einsum`), the rest exact. No finding.
- *The Hadamard transform is float32 only.* The draft ran it in float64 on the CPU: the graph builds with a
  float64 dtype and the evaluation fails with a status, "[hadamard] Unsupported type."
  (`scratch/keep/phase4_hadamard_float64_probe.txt`). It is tested in float32 on both devices.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`PRODUCT_TOLERANCES`), `max(2 x the larger of the CPU and GPU
  seed-1 errors, 4 eps)` of the result kind *(derived)*: the floors, 4.768371582e-07 and 8.881784197e-16, for
  the nine.

### Phase 4, family 1, the products and Einstein sums: 2026-11-25 00:14 EST (a scratch copy on the M5 Ultra, Claude)

- *Lines made public (10):* `mlx_addmm`, `mlx_inner`, `mlx_outer`, `mlx_kron`, `mlx_vecdot`, `mlx_tensordot`
  and `mlx_tensordot_axis` (one generic), `mlx_einsum`, `mlx_hadamard_transform`; and `mlx_linalg_cross`,
  which is a product and lives with them in `mlxf_linalg`.
- *Sub-phase 4b, seeds 2 and 3 after the freeze:* `scratch/keep/phase4b_products_unit_linalg_debug.log`,
  `unit_linalg` 189 of 189 (the 94 of Phase 10 and 95 new). No judged check has failed in any run. Largest
  judged errors on seeds 2 and 3, float32 epsilons *(measured, the final Release run)*: `mlx_inner` 0.923,
  `mlx_hadamard_transform` 0.762, `mlx_tensordot` 0.701, `mlx_addmm` 0.665, `mlx_einsum` 0.638, the rest below
  0.54, against the floor 4.
- *Exact checks:* `'ij->ji'` is the transpose and `'ii->i'` the diagonal, bit for bit; `mlx_vecdot` of complex
  vectors is Fortran's `dot_product` bit for bit and `mlx_inner` the unconjugated sum; every result's shape is
  the reference's.
- *Gates of the family:* Debug and Release with `-DMLXF_WERROR=ON`, no warning, fast gate 9 of 9 in both
  (`scratch/keep/f1/gate_{base_debug,f1_release}.log`); the other areas at the base's counts
  (`scratch/keep/f1/areas_f1_Release.txt`). A first Release build failed on `-Wfunction-elimination` (two
  impure calls inside `min` after `.or.`), fixed with a local; a first static gate failed on rule `ctorexpr`,
  which took the real dummies `a`, `b` of a test function for handles (renamed).
- *Decisions under delegation.*
  - **Operands exchanged, as for `matmul`,** in `mlx_addmm`, `mlx_inner`, `mlx_outer` and `mlx_tensordot`:
    the result then has `a`'s remaining dimensions before `b`'s, and no node is added. `mlx_kron` needs no
    exchange (the Kronecker product of the transposes is the transpose of the product).
  - **`mlx_vecdot` keeps its name.** Phase 0 found that it conjugates as `dot_product` does and left the name
    to this phase; decision 6's table fixes `mlx_vecdot` and section 7 forbids a public name outside the
    ledger, so `dot_product` was not added. The default dimension is 1 (MLX's last axis).
  - **A dimension shared by two operands reaches MLX as the axis `-dim`,** which is the same Fortran
    dimension for any rank (`mlx_cross` broadcasts a batch against one vector). A new helper,
    `mlxf_binary_axis_op`, passes the integer as given; `mlxf_take_op` translates with the first operand's
    rank.
  - **`mlx_tensordot(a, b[, n])`** contracts the last n dimensions of `a` with the first n of `b`, n = 2 by
    default (MLX's Python default; mlx-c has none); `mlx_tensordot(a, b, dims_a, dims_b)` pairs listed
    dimensions.
  - **`mlx_einsum` reverses every term and always names the result.** Letters are Fortran dimensions; without
    `->` the result is the letters that occur once in ASCII order (capitals first), then the ellipsis, which
    is NumPy's rule read in Fortran order with the batch last. MLX's own default would be read reversed.
  - **`mlx_addmm` takes `alpha` and `beta` as real32** (C's `float`), `mlx_hadamard_transform` its `scale`
    likewise; an absent `scale` is MLX's `1/sqrt(n)` (the C optional is passed empty).
  - **`mlx_cross` of two 2-vectors gives 3-vectors** `(0, 0, z)`: MLX's behaviour, where NumPy gives z.
  - **`index_result` moved to the array module as `mlxf_one_based`** (the LU permutation and pivots of family
    2 need it; `mlxf_ops.f90`, `mlxf_ops_reduce.f90`, `mlxf_ops_index.f90` and `mlxf_ops_sort.f90` call it
    there). `unit_ops` keeps 2,402 / 1,439 / 965.
  - **Shared test helpers** in `mlxf_test_utils`: `family_seeds`, `seeded_uniform`, `seeded_array` (ranks 1
    to 5, float32 or float64) and `shaped_error` (the reference's shape is the shape the result must have).

### Phase 4a, the calibration of the matrix functions: 2026-11-25 00:20 EST (a scratch copy on the M5 Ultra, Claude)

- *How.* The new tester `mlxf_linalg_matrix_tester` (sub-suite `linalg_matrix`) built in Debug with the seed
  list held to the calibration seed alone and its value tolerances at the ceiling, run on each device (logs
  `scratch/keep/phase4a_matrix_{cpu,gpu}_seed1.log`: 93 and 50 checks, all passing at the first run, with no
  change to a wrapper or a fixture afterwards). No seed 2 or 3 ran before this entry.
- *Fixtures.* Matrices are built in real64 from seeded orthogonal factors (columns orthonormalised twice by
  modified Gram-Schmidt) and a chosen spectrum: singular values or eigenvalues evenly spaced in [0.5, 3]
  (condition number 6, within section 6's 1e3), eigenvalues in [-2, 3] for the symmetric eigenproblem, and a
  normal non-symmetric matrix with the eigenvalues 0.5 +- 2i, -1 +- 0.75i and 1.5 for `mlx_eig`. Orders 5,
  (6, 4) and (4, 6), batches of two. Triangular operands carry values in their other triangle that would
  spoil the result if it were read.
- *What section 6 fixes is not calibrated:* backward errors, residuals and the departure from orthogonal are
  held to `10 n eps` of the result kind (n the larger extent; `LINALG_RESIDUAL_FACTOR` in `mlxf_test_defs`).
  Observed on seed 1 in units of `n eps`, the larger of CPU and GPU float32, then CPU float64 *(measured)*:
  `mlx_inv` 0.050 / 0.054, `mlx_tri_inv` 0.011 / 0.011, `mlx_pinv` 0.129 / 0.103, `mlx_cholesky` 0.109 / 0.117,
  `mlx_cholesky_inv` 0.033 / 0.063, `mlx_qr` backward 0.148 / 0.284 and orthonormality 0.508 / 0.616, `mlx_lu`
  0.078 / 0.067, `mlx_lu_factor` 0.059 / 0.095, `mlx_svd` backward 0.469 / 1.885, orthogonality 1.071 / 0.960,
  values 0.252 / 0.168, `mlx_eigh` residual 0.689 / 0.561, orthonormality 1.165 / 1.736, values 0.389 / 0.292,
  `mlx_eig` residual 0.370, values 0.327 (complex64 results: float32 bound, float64 operands included),
  `mlx_solve` 0.058 / 0.053, `mlx_solve_triangular` 0.033 / 0.034, the norms of singular values 0.285 / 0.285;
  complex `mlx_svd` 0.513 and 1.083, complex `mlx_eigh` 0.485 and 1.034. Everything is below a fifth of the
  bound: no finding.
- *Values, calibrated.* Observed on seed 1, CPU / GPU, float32 epsilons: `mlx_det` 0.528 / 0.528, `mlx_slogdet`
  0.098 / 0.098, `norm2` 0.476 / 0.535, `mlx_norm` 0.395 / 0.607, `mlx_norm_matrix` 0.301 / 0.293; float64 on
  the CPU at most 1.14 eps64 (`mlx_det`). *Frozen* (`MATRIX_TOLERANCES`), `max(2 x observed, 4 eps)`: the
  floors of both kinds for the five.

### Phase 4, family 2, the decompositions, solvers and norms of `linalg`: 2026-11-25 00:22 EST (a scratch copy on the M5 Ultra, Claude)

- *Lines made public (20):* `mlx_linalg_inv`, `_pinv`, `_tri_inv`, `_det`, `_slogdet`, `_cholesky`,
  `_cholesky_inv`, `_qr`, `_lu`, `_lu_factor`, `_svd`, `_eigh`, `_eigvalsh`, `_eig`, `_eigvals`, `_solve`,
  `_solve_triangular`, `_norm` (`mlx_norm`), `_norm_matrix` (`mlx_norm_matrix`), `_norm_l2` (`norm2`).
- *The probe (decision 9, "never from belief"), re-run on this machine with the functions Phase 0 left out*
  (`scripts/probes/mlx_behaviour_probe.c`, output `scratch/keep/phase4_behaviour_probe_tf32_0.txt`): every
  factorisation, inverse, determinant, eigensolver and solver refuses the GPU stream; `norm_l2`, `cross`, the
  vector norms, the matrix norms of orders 1 and infinity and `'fro'` run on it; the matrix norms of orders 2
  and -2 and `'nuc'` refuse it (they call `svd`). A graph with a GPU operation before and after an inverse on
  the CPU stream evaluates and is right to 1e-8.
- *Sub-phase 4b, seeds 2 and 3:* `scratch/keep/phase4b_matrix_unit_linalg_debug.log`, `unit_linalg` 589 of 589.
  No judged check has failed in any run. Largest on seeds 2 and 3 *(measured)*: residuals 1.600 n eps (`mlx_eigh`
  orthonormality, float32, both devices) and 1.397 n eps64, against 10; values 0.826 eps32 (`mlx_det`), 0.677
  (`mlx_slogdet`), 0.639 (`mlx_norm`), against 4.
- *Exact checks:* the shapes of every factor (reduced `q` and `r`, full `u` and `vt`, batches along dimension
  3); a Cholesky factor's other triangle, `r`'s lower triangle, `l`'s unit diagonal and upper triangle, `u`'s
  lower triangle exactly zero; `p` a permutation of 1 to m and `pivots(i)` in i to m, int32; singular values
  descending, eigenvalues ascending; the sign of a determinant exactly 1 or -1, opposite after two rows are
  exchanged.
- *The translation table of decision 9, as found.* Right as written: the free functions (`inv`, `pinv`, `det`,
  `slogdet`, `svd` with U and Vt exchanged, also for complex operands) and the flipped flags (`tri_inv`,
  `cholesky`, `cholesky_inv`, `eigvalsh`; `eigh` with a transpose of the eigenvectors). **Wrong in the count
  of nodes for six functions, which the plan asked the run to report:**
  - `qr`, `lu`, `lu_factor`, `eig`, `solve` and `solve_triangular` need the operand transposed **and** every
    matrix that comes back (the table lists one node). One transpose of `a` alone gives MLX the Fortran
    matrix, but MLX's factors are then read transposed by Fortran: `q` and `r` would come back as `q^T` and
    `r^T`. So `mlx_qr` adds three transposes, `mlx_lu` three and an index shift, `mlx_lu_factor` two and a
    shift, `mlx_eig` two, `mlx_solve` and `mlx_solve_triangular` one for a vector `b` and three for a matrix
    of right-hand sides. All are views (`swapaxes`), none a copy, so this is not the stop of section 7.
  - `solve_triangular` keeps its `upper` flag, since MLX is given the Fortran matrix itself.
  - `eigvals` could be free (a matrix and its transpose have the same eigenvalues); it transposes its operand
    as the table says, so that its values come in `mlx_eig`'s order (measured equal on every seed).
  - `eigh` of a complex Hermitian matrix needs the conjugate as well as the transpose of the eigenvectors
    (MLX sees the conjugate matrix); the table speaks of real matrices.
- *Decisions under delegation.*
  - **A second module, `mlxf_linalg_matrix`,** holds the 20 wrappers (the products stay in `mlxf_linalg`).
  - **Several results are subroutine arguments:** `call mlx_qr(a, q, r)`, `call mlx_lu(a, p, l, u)`,
    `call mlx_lu_factor(a, lu, pivots)`, `call mlx_svd(a, u, s, vt)` and `call mlx_svd(a, s)` (the values
    alone: MLX's `compute_uv = false`), `call mlx_eigh(a, w, v[, uplo])`, `call mlx_eig(a, w, v)`,
    `call mlx_slogdet(a, sign, logabsdet)`.
  - **`mlx_lu` returns the permutation as MLX defines it,** row i of `a` is row `p(i)` of `l u`, 1-based
    int32; `mlx_lu_factor` returns LAPACK's interchange sequence, 1-based.
  - **The CPU stream is chosen per function, in nine helpers named `mlxf_cpu_*`,** from the probe's list; a
    private `cpu_stream` in `mlxf_array_operations` builds it from calls the ledger already classes as
    plumbing (`mlx_default_cpu_stream_new` is a Phase 8 line and was left alone). The transposes and index
    shifts stay on the default device.
  - **The norms choose their stream by order:** the CPU's for the orders 2 and -2 of a matrix and for
    `'nuc'`, the default device's otherwise (`mlxf_norm_spec%on_cpu`).
  - **Three names for the norms, as the ledger has them:** `norm2(a[, dim][, keepdims])` and
    `norm2(a, dims[, keepdims])`; `mlx_norm(a, ord[, dim][, keepdims])` and `mlx_norm(a, ord, dims[,
    keepdims])` with a real64 `ord` (C's `double`; an infinite one through `ieee_value`);
    `mlx_norm_matrix(a, ord[, dims][, keepdims])` with `'fro'` or `'nuc'`. Of two dimensions the first is the
    rows'. Without dimensions `mlx_norm` takes a vector or a matrix (dimensions 1, 2) and stops on a higher
    rank, as MLX does; `mlx_norm_matrix` defaults to dimensions 1 and 2 of any rank, the matrix dimensions of
    every other function here, where MLX takes all axes of a rank-2 array only.
  - **`norm2(a)` of a whole array flattens first** (one view): mlx-c's null axis list cannot be passed through
    the generated interface, and MLX refuses more than two axes.
  - **`uplo` is a character, `'L'` by default,** and names the triangle of the Fortran matrix; another letter
    stops.
  - **The residual of an inverse is `|a x - 1|_F / (|a|_F |x|_F)`** and of a solution the backward error
    `|a x - b|_F / (|a|_F |x|_F + |b|_F)`; eigenvalues and singular values are judged against the constructed
    spectrum relative to `|a|_F`; all under section 6's `10 n eps`. The norms of singular values are judged
    the same way and not by a calibrated tolerance.

### Phase 4a, the calibration of the convolutions: 2026-11-25 00:24 EST (a scratch copy on the M5 Ultra, Claude)

- *How.* The new tester `mlxf_conv_tester` (sub-suite `conv`) built in Debug with the seed list held to the
  calibration seed alone and its tolerances at the ceiling, run on each device (logs
  `scratch/keep/phase4a_conv_{cpu,gpu}_seed1.log`). No seed 2 or 3 ran before this entry. Inputs and kernels
  uniform in [-1, 1], rounded once to float32. The references are direct real64 sums over Fortran subscripts
  (channels, W, H, D, batch): a correlation summed over the kernel at each output position, a transposed
  convolution as every input element spread over the output, so that neither repeats MLX's method (MLX
  computes a transposed convolution as a convolution of the dilated, padded input with the reversed kernel).
  An output element's error is relative to `max(1,` the same sum of magnitudes`)`.
- *The fixture, changed once before the freeze.* The draft also ran float64 on the CPU
  (`scratch/logs/phase4a_conv_cpu_seed1_draft1.log`): every function failed there, because MLX 0.32.4 computes
  a float64 convolution in float32 when neither the kernels nor the input are dilated (and, beyond one
  dimension, the groups are one) and refuses it at the evaluation otherwise, "[Convolution::eval] got
  unsupported data type." (`scratch/keep/phase4_conv_float64_probe.txt`; MLX `backend/cpu/conv.cpp`). The
  tester was restricted to float32 on both devices; the float32 numbers of the draft and of the kept run are
  the same.
- *Observed on seed 1, CPU / GPU, float32 epsilons (measured):* `mlx_conv1d` 0.769 / 1.001, `mlx_conv2d`
  0.963 / 0.963, `mlx_conv3d` 0.903 / 0.903, `mlx_conv_general` 0.839 / 0.839, `mlx_conv_transpose1d`
  0.761 / 0.761, `mlx_conv_transpose2d` 1.092 / 1.092, `mlx_conv_transpose3d` 0.631 / 0.978. No finding.
- *Frozen* (`CONV_TOLERANCES`), `max(2 x the larger, 4 eps32)`: the float32 floor 4.768371582e-07 for the
  seven. The float64 column holds the same bound and judges nothing.

### Phase 4, family 3, the convolutions: 2026-11-25 00:26 EST (a scratch copy on the M5 Ultra, Claude)

- *Lines made public (7):* `mlx_conv1d`, `mlx_conv2d`, `mlx_conv3d`, `mlx_conv_general`,
  `mlx_conv_transpose1d`, `mlx_conv_transpose2d`, `mlx_conv_transpose3d`, in the new module `mlxf_conv` of
  `src/core/linalg/` (the file table puts the convolutions there), with the record `mlxf_conv_spec`.
- *Sub-phase 4b, seeds 2 and 3:* `scratch/keep/phase4b_conv_unit_linalg_debug.log`, `unit_linalg` 632 of 632. No
  judged check has failed in any run. Largest on seeds 2 and 3 *(measured)*: `mlx_conv2d` 1.353 eps32,
  `mlx_conv_general` 0.992, `mlx_conv_transpose2d` 0.977, against the floor 4.
- *What the forms cover:* one, two and three spatial dimensions; stride, padding, dilation and output padding
  that differ between the dimensions; a list of one value; an absent list and an absent spec; groups in one
  and two dimensions, also in a transposed convolution; for `mlx_conv_general` a padding after that differs
  from the padding before, a dilated input and reversed kernels.
- *Decisions under delegation.*
  - **`type(mlxf_conv_spec)` is the public record, under the plan's name** (decision 10), and
    `mlx_conv*(input, weight[, spec])` the signature. `CLAUDE.md` names user-facing types `mlx_<x>` and the
    kernel's record is `mlx_metal_kernel_spec`; decision 10 fixes this name, so it was kept, and the rename
    to `mlx_conv_spec` is the maintainer's to rule (one line of `mlxf_defs`, the import and the public line
    of `mlxf.f90`, the tester and the policy).
    *Taken at the review of the phase, before the name was ever committed:* the record is
    **`type(mlx_conv_spec)`**. `CLAUDE.md`'s rule for public names stands above a plan's wording, the kernel's
    record already follows it, and a rename after a release would break users. The source, the README and
    the policy carry the new name; this record keeps the old one where it tells what the run did.
  - **The lists are allocatable:** absent is the default, one value serves every spatial dimension, otherwise
    one value per dimension in Fortran's order (W first), reversed inside the helper. A list of another length
    stops; so do a field the function does not take and `groups` below 1 (MLX divides by it unchecked).
  - **`padding` is the padding before and after;** `mlx_conv_general` takes `padding_hi` for the far end when
    it is given. `dilation` is the kernel's, `input_dilation` the input's.
  - **One helper per C signature,** seven of them, each translating the record itself, as the reduction
    helpers translate dimensions.
  - **The wrappers are correlations,** as MLX's convolutions are; `flip` of `mlx_conv_general` reverses the
    kernels.
  - **A transposed convolution whose padding exceeds `dilation*(k-1)` is passed through,** not refused: MLX
    returns a shorter result there than the usual definition (measured on both devices,
    `scratch/keep/phase4_conv_transpose_padding_probe.txt`; question 23 for Apple). The policy states the
    extent formula up to that padding. It is a corner of three functions that are right elsewhere, so no
    ledger line was excluded (decision 22 speaks of a function that disagrees with its documentation; MLX's
    states no formula).

### Phase 4, linear algebra, products and convolutions: 2026-11-25 00:50 EST (a scratch copy on the M5 Ultra, Claude) - complete

The three families are done; their entries above ("4a" three times, "family 1", "family 2", "family 3") hold
the detail. This entry closes the phase and states the final numbers. **One gate of the phase is not met and
waits for a ruling: the Release build-time bound of ruling R3, which the base itself exceeds** (below).

- *Machine and base.* HanssMacStudio, the M5 Ultra (macOS 27.2.1, GFortran 16.2.0, CMake 4.5.1, Homebrew MLX
  0.32.4 and mlx-c 0.8.0). Base: the maintainer's checkout as it stood on 2026-11-24 at 23:45 EST, commit
  `1e0ae97` plus uncommitted, verified work (Phase 10's wrappers and three test-only oracle modules); a
  snapshot of it without `.git` is the reference of every count and of the diff. Ruling of `spec/rulings.md`:
  the hold after Phase 3 is released, the API as delivered. R1, R3 and R4 applied. The work was done in a copy
  of the working tree, never in the maintainer's checkout; nothing is committed. Paths below are under the
  run's root, `.../scratchpad/parity4_work`.
- *Files changed* (from `diff -rq` against the base snapshot). New: `src/core/linalg/mlxf_linalg_matrix.f90`,
  `mlxf_conv.f90`, `mlxf_linalg_products_tester.f90`, `mlxf_linalg_matrix_tester.f90`, `mlxf_conv_tester.f90`.
  Changed: `src/core/linalg/mlxf_linalg.f90`, `linalg.inf`; `src/core/array/mlxf_array.f90`,
  `mlxf_array_operations.f90` (23 helpers, `mlxf_one_based`); `src/core/ops/mlxf_ops.f90`,
  `mlxf_ops_reduce.f90`, `mlxf_ops_index.f90`, `mlxf_ops_sort.f90` (`index_result` is now the array module's);
  `src/defs/mlxf_defs.f90` (`mlxf_conv_spec`, `mlxf_norm_spec`); `src/core/mlxf.f90`;
  `src/test/mlxf_test_utils.f90`, `mlxf_test_defs.f90`, `mlxf_test_registry.f90`; `test/CMakeLists.txt` (the
  comment on the guard group); `scripts/mlxc_parity.txt`, `scripts/check_rules.py` (`PARITY_PENDING` 76,
  `ENTRY_HELPERS`, rule `ctorexpr` extended), `scripts/probes/mlx_behaviour_probe.c`;
  `doc/policies/binding_contract_policy.md` (sections 7 and 10), `doc/policies/test_environment_policy.md`
  (the guard members), `README.md`, `doc/collaboration/apple_questions.md` (questions 23 and 24),
  `doc/history/2026-11.md`, this plan, the report. No file outside the table; the toy modules, the oracles,
  the benchmark and the existing testers are untouched.
- *Exit items.*
  - **No `pending 4` line.** Ledger before: 286 public, 60 plumbing, 132 internal, 89 excluded, 113 pending
    (4: 37, 5: 19, 6: 16, 7: 7, 8: 34). After: 323 public, 76 pending (5: 19, 6: 16, 7: 7, 8: 34); plumbing,
    internal and excluded unchanged *(exact)*. `PARITY_PENDING = 76`; rule `parity` passes.
  - **`unit_linalg` passes on both devices in both builds** (`scratch/keep/final/area_{Debug,Release}_linalg_*.log`,
    `unit_linalg_by_suite.txt`; both devices / CPU / GPU): 632 / 397 / 239, that is `linalg` 32 / 17 / 15 and
    `linalg_mm` 62 / 33 / 30 unchanged, `linalg_products` 95 / 60 / 36, `linalg_matrix` 400 / 265 / 136 (197
    residuals judged), `conv` 43 / 22 / 22. The residual bounds of section 6 hold with a margin of
    five: the largest residual of any run is 1.96 n eps64 (`mlx_svd`'s backward error, float64, Release).
  - **The existing suites keep their assertions** (`scratch/keep/final/areas_{Debug,Release}.txt` against
    `scratch/keep/base/areas_base_Debug.txt`): core 80 to 82 / 55 or 56 / 55 or 56 (the address-reuse checks),
    array 179 / 96 / 94, ops 2,402 / 1,439 / 965, fft 194 / 101 / 94, compile 63 / 32 / 32, kernels 1,063 /
    539 / 531, fast 94 / 13 / 82; `object_contracts` passes with 19 members (16 at the base).
  - **Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings**
    (`scratch/keep/final/build_{Debug,Release}.log`), **fast gate 9 of 9 in both** with `scripts/check_tree.sh`
    first (`gate_{Debug,Release}.log`), installed (`install_*.log`).
  - **Ruling R3, judged against the entry "Phase 2, the base measurements on the M5 Ultra".**
    - *Fast gate total real time in Release:* 10.85 s and 10.77 s (`gate_Release.log`,
      `second_release_gate.log`; load 2.07 and 2.47 before) against **38.74 s**: met. `unit_linalg` takes 0.39 s
      in the gate. No new area, so the 3 s bound has no subject; the budget stays 9.
    - *Release clean build, configure plus build from scratch at `-j 12`:* 15.507 s (1.521 + 13.986; load 1.36
      before, 2.07 after) and 15.510 s (1.523 + 13.987; load 1.67 before, 2.47 after;
      `second_release_timing.log`) against **14.08 s**: **not met.** The base snapshot alone takes 15.049,
      15.011 and 15.041 s (`scratch/keep/base/build_basesnap_Release_{1,2,3}.log`, loads 2.6, 3.4 and 2.2
      after): the bound was exceeded before this phase's first edit, by the test-only oracle modules that
      entered after Phase 10's base (`mlxf_oracle_gridding`, `_recon_pcg`, `_projection`, `_pcg`, `_pose`
      take 2.2 to 3.5 s each to compile at `-O3`; `scratch/keep/final/release_compile_profile.txt`). **This
      phase adds 0.47 s of wall time, 3.1 % of the base** (15.509 against the base's mean 15.034). Compiled
      one file at a time the tree takes 57.2 s, about 6.6 s of it this phase's: the three new testers
      (`mlxf_linalg_matrix_tester` 4.0 s, the slowest file of the tree, `mlxf_linalg_products_tester` 1.4 s,
      `mlxf_conv_tester` 1.0 s) and 0.3 s for the three library modules. All *measured*.
    - *The stop of section 7 and what was done.* "The build-time bound exceeded" is a stop. R3 places the
      judgment at the end of the phase, and the excess is the base's, in files this phase may not edit; the
      families were therefore finished, and the stop is recorded here, at the judgment. **Ruling needed:**
      either re-freeze the build bound on the present base (twice its mean would be 30.07 s), or bring the
      oracles' compile time down (they are outside every phase's file table of this plan).
    - *Ruled* (2026-11-25, Hans: "Go", on the recommendation): **the Release clean-build bound is re-frozen at
      22.07 s** (*derived*: the present base's mean 15.03 s, *measured*, plus the 7.04 s of room Phase 2 gave
      above its own base). Phase 4 meets it at 15.51 s. Phase 5 and later are judged against 22.07 s; they
      start after the kernel runs K1, K8 and K2, which hold the M5.
  - **`scripts/check_tree.sh` passes;** `restyle_fortran.py` and `format_use_blocks.py` were run on the 17
    Fortran files touched, by name, after the last edit, and rewrote none.
- *Frozen tolerances* (`src/test/mlxf_test_defs.f90`; entries "Phase 4a" above): `PRODUCT_TOLERANCES`,
  `MATRIX_TOLERANCES` and `CONV_TOLERANCES` hold the floors, 4 eps32 = 4.768371582e-07 and 4 eps64 =
  8.881784197e-16 (the convolutions 4 eps32 in both columns); `LINALG_RESIDUAL_FACTOR = 10` is section 6's.
  No tolerance moved after its freeze. Upstream-defect lines: 0.
- *Mutations and plants.*
  - 41 mutations of the wrappers and helpers on a scratch copy, the archive, the executable and the object
    deleted before each build (`scratch/keep/phase4_mutations_final.txt`): every one fails `unit_linalg`, 33
    through assertions (2 to 33 failing checks) and 8 through MLX's own shape, axis or stream errors; the
    restored copy passes. They cover each exchange of operands, each flipped flag, each transpose, the two index
    shifts, the reversal of the convolution lists and the order of their options, and the choice of the CPU
    stream for the norms of singular values.
  - Seven planted violations fail the static gate and the restored copy passes
    (`scratch/keep/phase4_plants.txt`): the ratchet left at 113, a public name missing from `mlxf.f90`, a
    called function left pending, a wrapper that touches its operand before the entry, a helper missing from
    `ENTRY_HELPERS`, a function result of an imported test helper inside a constructor of handles, a guard
    member without its case.
- *The independent review* (a read-only subagent, against MLX's and mlx-c's source; it wrote nothing). No
  wrapper found that returns a wrong result for an input its comment declares legal. Acted on:
  - a leak in the new products tester, two function results of `seeded_array` inside a constructor of
    handles, which neither `ctorcall` nor `ctorexpr` saw. Fixed, and **rule `ctorexpr` now also counts a
    function with a handle result that a file imports by name from a file of the tree** (generics included;
    the user API stays `ctorcall`'s). The planted line fails; the tree had no other case.
  - four blind tests made discriminating (the convolution fixtures: a stride equal to the dilation, a
    palindromic stride list, a dilation equal to the output padding, a transposed convolution without a
    dilation), and forms added (`mlx_addmm` with a vector on either side, a capital letter in an unnamed
    `mlx_einsum` result, `mlx_conv2d` without a spec, a norm of singular values with the dimensions listed
    the other way). Every judged error stays within its frozen tolerance.
  - refusals added: a list of no dimensions for `norm2` and `mlx_norm` (it would reach MLX as "no reduction"),
    `groups` below 1.
  - comments and the policy corrected: `mlx_solve` needs the same batch dimensions on `a` and `b` (MLX's
    `take_along_axis`), where `mlx_solve_triangular` broadcasts; the transposed convolution's formula holds
    up to a padding of `dilation*(k-1)` (then measured, question 23); a negative padding crops; the
    transposed 3D convolution takes one group; `padding` of the record means two things.
  - Left as they are, for the maintainer: no test of batches of `mlx_lu`, `mlx_lu_factor`, `mlx_svd`,
    `mlx_eigh`, `mlx_eig`, `mlx_cholesky` and `mlx_solve_triangular` (`mlx_inv`, `mlx_qr`, `mlx_det`,
    `mlx_solve` and the norms have one), of `mlx_lu_factor` on a rectangular matrix, of a complex `uplo='U'`,
    of `norm2` on a rank-0 array, of `mlx_inner` with a scalar, of `mlx_vecdot` broadcasting, of an ellipsis
    that leads or sits in the middle or spans different ranks, of groups in `mlx_conv_transpose2d`, of
    one-value lists other than stride and padding; three of the stops have a guard (`guard_matrix_rank`,
    `guard_eigh_uplo`, `guard_conv_spec`), the others none; the float64 refusals of the Hadamard transform
    and of the convolutions are measured in probes and not pinned by a test (a later MLX may lift them).
- *Surprises about MLX and mlx-c (measured unless said).*
  - Six functions of decision 9's table need more transposes than it lists (family 2's entry).
  - The Hadamard transform and the convolutions are float32 operations that accept a float64 graph: the first
    fails its evaluation, the second computes in float32 or fails, by its options (question 24).
  - A transposed convolution with a padding above `dilation*(k-1)` returns less than the definition
    (question 23).
  - With MLX's default `MLX_ENABLE_TF32`, a 3 by 3 float32 product on the GPU is off by 7e-4 (the probe's
    mixed-stream graph, `scratch/keep/phase4_behaviour_probe.txt`); with `MLX_ENABLE_TF32=0`, 1e-8. The policy
    already says so of the precision; the probe's header now says to run it with the variable at 0.
  - `mlx_solve` refuses a batch of `a` against a single `b` (read in `mlx/linalg.cpp`, not run).
  - `mlx_eig` and `mlx_eigvals` of a float64 matrix return complex64 that is more accurate than the float32
    route (residual 0.035 n eps32): MLX computes in double and rounds the result.
- *Decisions about the run itself.* The wrappers of the three families and the ledger were written in one go
  (rule `parity` needs a called function public), then each family was calibrated, frozen, judged and gated
  in turn; had the run stopped between families, the untested family's wrappers and lines would have come
  out. Mutations and plants ran on scratch copies. The base snapshot was built (never written to) to measure
  the base's own build and gate times.
- *Proposed, not applied* (skill edits need approval): `.github/skills/mlxf-binding/SKILL.md`, section 3,
  should list the helpers of this phase (`mlxf_cpu_*`, `mlxf_norm_op`, `mlxf_norm_text_op`,
  `mlxf_binary_axis_op`, `mlxf_optional_float_op`, `mlxf_addmm_op`, `mlxf_einsum_op`, `mlxf_tensordot_op`, the
  seven `mlxf_conv*_op`) and the shared `mlxf_one_based`; section 4 could add "a matrix function transposes
  what MLX's transposed view does not give for free: say which, and never copy", "a dimension shared by two
  operands is passed as the axis `-dim`" and "a CPU-only function goes through an `mlxf_cpu_*` helper";
  `references/testing.md` could say that a name shared by a real dummy and a handle trips `ctorexpr`, and that
  a constant and a variable that differ only in case (`TALL`, `tall`) do not compile.
- *The new public names of the phase, for the maintainer's read.* Arrays are `type(mlx_array)`; `[x]` is
  optional and passed by keyword; `dim` is a Fortran dimension, `dims` an integer array of them; results are
  functions unless written `call`.
  - **Products:** `mlx_addmm(c, a, b[, alpha][, beta])` (real32 factors), `mlx_inner(a, b)`, `mlx_outer(a, b)`,
    `mlx_kron(a, b)`, `mlx_vecdot(a, b[, dim])`, `mlx_cross(a, b[, dim])`, `mlx_tensordot(a, b[, n])`,
    `mlx_tensordot(a, b, dims_a, dims_b)`, `mlx_einsum(subscripts, operands)` (`operands(:)` an array of
    handles), `mlx_hadamard_transform(a[, scale])` (real32).
  - **Matrices:** `mlx_inv(a)`, `mlx_pinv(a)`, `mlx_tri_inv(a[, upper])`, `mlx_det(a)`,
    `call mlx_slogdet(a, sign, logabsdet)`, `mlx_cholesky(a[, upper])`, `mlx_cholesky_inv(factor[, upper])`,
    `call mlx_qr(a, q, r)`, `call mlx_lu(a, p, l, u)`, `call mlx_lu_factor(a, lu, pivots)`,
    `call mlx_svd(a, u, s, vt)`, `call mlx_svd(a, s)`, `call mlx_eigh(a, w, v[, uplo])`,
    `mlx_eigvalsh(a[, uplo])`, `call mlx_eig(a, w, v)`, `mlx_eigvals(a)`, `mlx_solve(a, b)`,
    `mlx_solve_triangular(a, b[, upper])`.
  - **Norms:** `norm2(a[, dim][, keepdims])`, `norm2(a, dims[, keepdims])`, `mlx_norm(a, ord[, dim][, keepdims])`,
    `mlx_norm(a, ord, dims[, keepdims])` (`ord` real64), `mlx_norm_matrix(a, ord[, dims][, keepdims])` (`ord`
    `'fro'` or `'nuc'`, `dims(2)`).
  - **Convolutions:** `mlx_conv1d`, `mlx_conv2d`, `mlx_conv3d`, `mlx_conv_general`, `mlx_conv_transpose1d`,
    `mlx_conv_transpose2d`, `mlx_conv_transpose3d`: `f(input, weight[, spec])`; `type(mlxf_conv_spec)`:
    `stride(:)`, `padding(:)`, `dilation(:)`, `output_padding(:)`, `padding_hi(:)`, `input_dilation(:)`
    (allocatable integer lists), `groups = 1`, `flip = .false.`.
- *Where a Fortran user would expect something else* (each stated in the binding policy, sections 7 and 10):
  - the factorisations run on the CPU whatever the default device, and nothing says so at the call;
  - `mlx_lu`'s `p` is a permutation (`a(i, :) = (l u)(p(i), :)`), `mlx_lu_factor`'s `pivots` LAPACK's
    interchanges; `mlx_svd` returns full `u` and `vt` and the transposed `vt`, not `v`;
  - `mlx_eig` returns complex64 for a real matrix; `mlx_eigh`'s `uplo` is a letter, the other triangle flags
    are logicals named `upper`, as in MLX;
  - `mlx_vecdot` is `dot_product` (it conjugates), `mlx_inner` is not; `mlx_cross` of 2-vectors gives
    3-vectors; `mlx_tensordot(a, b)` contracts two dimensions by default;
  - an `mlx_einsum` letter is a Fortran dimension, an unnamed result puts capitals first, and the ellipsis is
    the trailing (batch) dimensions;
  - `mlx_norm(a, ord)` without dimensions stops above rank 2; `norm2(a, dims)` takes at most two dimensions;
    an infinite order needs `ieee_value`;
  - a convolution's layout is (C, W, H, D, N) with the kernels' output channels last, the options are a
    record whose lists are per spatial dimension with W first, and the convolutions are correlations in
    float32;
  - `mlxf_conv_spec` was the one public type whose name started with `mlxf_`; it is `mlx_conv_spec` since
    the review of the phase.
- *What it means, in short:* linear algebra, the tensor products and the convolutions of MLX are reachable
  from Fortran with matrices, dimensions and layouts as Fortran reads them, tested on both devices, with no
  accuracy finding and two reports for Apple. 76 ledger lines remain, for Phases 5 to 8. The build-time bound
  has to be ruled on before the next phase is judged against it.

### Phase 5, the base measurements: 2026-11-26 03:47 EST (run mlxf_parity_rest, Claude)

- *Machine and base.* HanssMacStudio, the M5 Ultra (30 cores, 96 GB, macOS 27.2.1), Homebrew GFortran 16.2.0,
  CMake 4.5.1, Homebrew MLX 0.32.4 and mlx-c 0.8.0. The base is commit `6f1af0d` plus the verified, not yet
  committed result of run `mlxf_toy_seam` (50 changed and 18 new files: `git status` in the run's copy shows them
  at the start; they are the base, not this run's work, and the toy files among them are not edited). A copy of
  that base without `.git` (`base/` under the run's root) is the reference of every count and of the diff. Rulings
  of the run's `spec/rulings.md`: R5 (the build and gate bounds for this base) and R6 (the thirty scalar `max`
  reductions of `NANMAX_LEDGER`, converted before Phase 5's first wrapper); R1, R3 and R4 of the Phase 1 record
  apply. Paths below are under the run's root, `.../scratchpad/parity5_work`.
- *How.* As the entry "Phase 2, the base measurements on the M5 Ultra" took them, with the base copy as the export
  in place of `git archive HEAD`: four trees from scratch (Release, Debug, Release, Debug), serial, nothing else
  of the run running, each timed step started with the one-minute load at most 4 (`scratch/scripts/base_measure.sh`
  with `scratch/scripts/lib.sh`, driver log `scratch/logs/base_measure.log`, per-step logs
  `scratch/keep/base/{build,gate}_base_{Release,Debug}_{1,2}.log`, the counts
  `scratch/keep/base/areas_base_{rel1,dbg1,rel2,dbg2}.txt` with one log per area and device beside them).
  `-DFORTLS=OFF -DMLXF_WERROR=ON`, `-j 12`. Zero warnings in the four builds; the static gate passes on the base;
  the first `unit_core` reports `GPU devices: 1`. Every number below is *measured*, the bounds *derived* from them
  by R5.
- *Release clean build, configure plus build, wall:* 19.512 s (1.509 + 18.003; load 1.86 before, 2.70 after) and
  19.553 s (1.561 + 17.992; load 3.39 before, 3.54 after): mean 19.533 s. Debug: 7.557 s and 7.577 s.
- *Fast gate, per entry (s), Release run 1 / run 2:* unit_array 10.54 / 10.53, unit_kernels 6.14 / 6.09, unit_ops
  0.86 / 0.80, object_contracts 0.81 / 0.79, unit_fft 0.30 / 0.28, unit_linalg 0.28 / 0.26, unit_core 0.28 / 0.24,
  unit_fast 0.19 / 0.17, unit_compile 0.16 / 0.14; total real time 10.54 / 10.54 s (9 of 9 entries; the script
  with its static gate 14.71 / 14.60 s; load 2.70 and 3.54 before, 2.69 and 2.97 after). Debug totals 13.18 /
  13.14 s (unit_kernels 13.17 / 13.13, unit_array 10.86 / 10.89).
- *Assertion counts, both devices in one process / `device=cpu` / `device=gpu` (the four builds alike except
  `unit_core`):* core 181 to 183 / 156 or 157 / 156 or 157 (two checks of its registry sub-suite depend on the
  allocator's reuse of an address), array 193 / 103 / 101, ops 2,462 / 1,469 / 995, linalg 632 / 397 / 239, fft
  194 / 101 / 94, compile 63 / 32 / 32, fast 94 / 13 / 82, kernels 1,955 / 896 / 1,145; `object_contracts` passes
  with 21 members. These are the counts the existing suites keep in this run.
- *The bounds of this run (R5), written before its first edit:*
  - Release clean build (configure plus build, from scratch, `-j 12`): at most **26.10 s**, the larger of 22.07 s
    and this base's mean 19.533 s plus 7.04 s less the 0.47 s Phase 4 used (26.103 s) *(derived)*.
  - Fast gate total real time in Release: at most **38.74 s**, as frozen (the base alone, 10.54 s, is below
    28.74 s, so R5's second clause does not apply).
  - A new area: at most **3 s** in Release, as frozen.
  By R3 they are judged at the end of each phase.


### Phase 5, ruling R6, the thirty scalar `max` reductions: 2026-11-26 03:50 EST (run mlxf_parity_rest, Claude)

- *What.* `NANMAX_LEDGER` of `scripts/check_rules.py` is empty. The thirty statements it counted in five testers of
  `src/core` (`mlxf_fft_nd_tester` 3, `mlxf_linalg_matrix_tester` 12, `mlxf_linalg_mm_tester` 2,
  `mlxf_linalg_products_tester` 12, `mlxf_ops_math_tester` 1) no longer have the form rule `nanmax` refuses. The
  file-table row was added before the edit.
- *How, by kind.* 25 accumulations of two operands, `x = max(x, e)`, became `x = nan_max(x, e)`; three of three
  operands (`measured(3)` twice in the singular-value and eigenvalue cases, `d` in `spectra_apart`) became
  `x = nan_maxval([x, e1, e2])`. Both come from `mlxf_test_reduce`.
- *Decision under delegation: two of the thirty are not error reductions and were rewritten without `nan_max`.*
  The rule's pattern is "an assignment whose right side opens with `max(` and holds an `abs(`", which also caught
  the floor of a scale, `bound = max(1, matmul(abs(x), abs(y)))` (`mlxf_linalg_mm_tester`), and the reference of
  `mlx_logaddexp`, `z = max(x, y) + log(1 + exp(-abs(x - y)))` (`mlxf_ops_math_tester`). `nan_max` turns a NaN into
  +infinity, which fails an error and would pass one divided by such a scale, so R6's conversion would have
  weakened the first and meant nothing for the second. The scale is now computed in one statement and floored in
  the next; the reference adds its two terms in the other order. Both give the same bits as before (an elemental
  `max` of the same operands; a commuted IEEE addition).
- *Evidence.* Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings
  (`scratch/keep/r6/build_r6_{Debug,Release}.log`); `unit_ops` 2,462 / 1,469 / 995, `unit_linalg` 632 / 397 / 239
  and `unit_fft` 194 / 101 / 94 in both builds, the base's counts (`scratch/keep/r6/areas_r6_{Debug,Release}.txt`);
  fast gate 9 of 9 in both with the static gate first (`scratch/keep/r6/gate_r6_{Debug,Release}.log`). No expected
  value, tolerance or count moved, and no check of the base fails. A planted `res%err = max(res%err, ...)` on a
  scratch copy fails rule `nanmax` and the restored copy passes (`scratch/keep/r6/r6_plant.txt`).
- *Left as they are:* accumulations the rule's pattern does not reach (`resid = max(resid, fro(...))` and the like
  in `mlxf_linalg_matrix_tester`, whose right side holds no `abs(`); R6 names the thirty.

### Phase 5a, the samplers on seed 1: 2026-11-26 04:00 EST (run mlxf_parity_rest, Claude)

- *What is measured, and what is not calibrated.* Section 6 fixes the bound of a sampler from the literature: the
  mean and the variance of a large sample within 5 standard errors of the distribution's own. Nothing is frozen
  from a measurement; `RANDOM_SIGMAS = 5` and `RANDOM_NSAMPLES = 2**20` are in `src/test/mlxf_test_defs.f90`. The
  sub-phase runs the tester on the key of seed 1 alone, on both devices (R4), and records how far the estimates
  lie, in standard errors, before seeds 2 and 3 are judged.
- *How.* The tester `mlxf_random_tester` (area `unit_random`) built in Debug with its seed list held to seed 1, run
  as `mlxf_test_exec test=unit_random device=cpu|gpu` (logs `scratch/keep/phase5/phase5a_random_{cpu,gpu}_seed1.log`:
  112 and 111 checks, all passing at the first run). A sample is brought to the host and its mean and unbiased
  variance are computed there in real64; the standard error of a mean is `sqrt(var/n)`, of a variance
  `sqrt((m4 - var**2)/n)` with m4 the distribution's fourth central moment in closed form (the truncated normal's
  by the recursion of its raw moments), of a covariance `sqrt((s_ii s_jj + s_ij**2)/n)`, of a frequency
  `sqrt(p(1-p)/n)`. No seed 2 or 3 ran before this entry.
- *Observed on seed 1, in standard errors, mean / variance (measured; the CPU and the GPU agree to the three
  decimals printed):* `mlx_random_uniform` 0.450 / 0.464, with bounds 0.059 / 0.531; `mlx_random_normal`
  0.695 / 0.673 (the same with `loc` and `scale`, an affine map of the same draw); `mlx_random_laplace`
  0.043 / 2.406; `mlx_random_gumbel` 1.343 / 2.136; `mlx_random_truncated_normal` 0.962 / 0.512; the normal with
  array parameters, per row, 0.515 / 0.605 and 1.513 / 2.119; the uniform with array bounds 1.503 / 1.396 and
  0.431 / 0.446; `mlx_random_randint` 0.682 / 1.065; `mlx_random_bernoulli` 0.353 / 0.352; `mlx_random_bits`
  1.107 / 0.368; `mlx_random_multivariate_normal` means 0.204, covariances 1.577, means of two batches 1.977;
  `mlx_random_categorical` frequencies 1.879. The largest is 2.41 against 5: no finding.

### Phase 5, FFTs and random: 2026-11-26 04:30 EST (run mlxf_parity_rest, a scratch copy on the M5 Ultra, Claude) - complete

The FFT lines of this phase were delivered by Phase 10; this entry delivers its random half and closes the phase.

- *Machine, base and rulings:* as the entry "Phase 5, the base measurements"; the tree is that base plus R6's
  conversion. Paths below are under the run's root, `.../scratchpad/parity5_work`.
- *Read before the API was fixed:* mlx-c's `random.h` and `random.cpp` at `v0.8.0`; MLX's `random.h` and
  `random.cpp` (the checkout is 141 commits after `v0.32.4`, so what the wrappers rely on was measured on the
  installed 0.32.4: the probe `scratch/probes/random_probe.c`, output `scratch/keep/phase5/random_probe.txt`).
- *Files.* New: `src/core/random/mlxf_random.f90` (module `mlxf_random`), `mlxf_random_tester.f90`, `random.inf`;
  `src/core/array/mlxf_array_random.f90` (the samplers' signature helpers, a submodule of `mlxf_array`; its
  file-table row was added before it was written). Changed: `src/defs/mlxf_defs.f90` (`mlxf_random_spec`);
  `src/core/array/mlxf_array.f90` (eleven helper interfaces, ten abstract interfaces, `cpu_stream` and
  `optional_handle` as module procedures), `mlxf_array_operations.f90` (`cpu_stream` is now the family's, three
  lines); `src/core/mlxf.f90`; `src/test/mlxf_test_defs.f90` (`RANDOM_NSAMPLES`, `RANDOM_SIGMAS`),
  `src/test/mlxf_test_registry.f90` (area `random`, guards `guard_categorical_forms` and `guard_normal_shape`);
  `test/CMakeLists.txt` (`unit_random`, budget 10); `scripts/mlxc_parity.txt`, `scripts/check_rules.py`
  (`PARITY_PENDING` 57, `ENTRY_HELPERS`, `NANMAX_LEDGER` empty); the binding policy (section 13 new; section 7),
  the test policy (budget 10, 23 guard members), `README.md`, `CONTRIBUTING.md` (ten entries),
  `doc/quickstart.md` (row D20) with its block in `test/consumer/mlxf_example_differences.f90` (the three in a
  file-table row added before the edits); the five testers of R6; this plan. No file outside the table as it now
  stands; the toy modules, the oracles, the benchmarks and `test/offstate/` are untouched.
- *Exit items.*
  - **No `pending 5` line.** Ledger before: 324 public, 59 plumbing, 132 internal, 89 excluded, 76 pending (5: 19,
    6: 16, 7: 7, 8: 34). After: 343 public, 57 pending (6: 16, 7: 7, 8: 34); plumbing, internal and excluded
    unchanged *(exact)*. `PARITY_PENDING = 57`; rule `parity` passes.
  - **`unit_fft` passes** on both devices in both builds, unchanged: 194 / 101 / 94 (both devices / CPU / GPU).
  - **`unit_random` passes on both devices in both builds:** 486 / 244 / 242
    (`scratch/keep/phase5_final/areas_random_{Debug,Release}.txt`). Sub-phase 5b, seeds 2 and 3 after the entry
    "Phase 5a": first run 04:01 EST (`scratch/keep/phase5/phase5b_unit_random_debug.log`, 435 of 435, before the
    review's 51 added checks). No judged check has failed in any run. Largest on seeds 2 and 3, in standard errors
    *(measured)*: 2.836 (`mlx_random_gumbel`, variance, seed 3), against 5.
  - **The existing suites keep their assertions** in both builds (`scratch/keep/phase5_final/areas_{Debug,Release}.txt`
    against the base's): core 181 to 183 / 156 or 157 / 156 or 157, array 193 / 103 / 101, ops 2,462 / 1,469 / 995,
    linalg 632 / 397 / 239, fft 194 / 101 / 94, compile 63 / 32 / 32, fast 94 / 13 / 82, kernels 1,955 / 896 /
    1,145; `object_contracts` passes with 23 members (21 at the base).
  - **Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings**
    (`scratch/keep/phase5_final/build_{Debug,Release}.log`), **fast gate 10 of 10 in both** with
    `scripts/check_tree.sh` first (`gate_{Debug,Release}.log`), `scripts/check_install.sh --require-gpu` on both
    trees (`install_{Debug,Release}.log`), and **`scripts/release_gate.sh --allow-dirty` passes**
    (`release_gate_6f1af0d-dirty.log`: Debug and Release from its own export, 76 s, no skip, no side effect).
    These ran on the tree before the last test was added (`test_keyed`, two assertions, written when a mutation
    survived: below); that test was then built in both trees without a warning, its area run
    (`areas_random_*.txt`) and both fast gates run again, 10 of 10 (`gate_{Release,Debug}_after_keyed.log`). The
    logs of the exit as it stood before the review's fixes are in `scratch/keep/phase5_final/before_review/`.
  - **Ruling R5, judged (R3) against the entry "Phase 5, the base measurements".** Release clean build, configure
    plus build from scratch at `-j 12`: 19.746 s (1.539 + 18.207; load 2.74 before, 3.04 after) and 19.756 s
    (1.540 + 18.216; load 2.19 before, 2.74 after; `second_release_timing.log`) against **26.10 s**: met, 0.22 s
    above the base's mean 19.533 s. Fast gate total real time in Release: 10.44 s and 10.48 s (10.53 s after the
    last test) against **38.74 s**: met (`unit_array` alone is the total). The new area `unit_random`: 0.86 and
    0.94 s in the Release gate, 0.66 s alone, against **3 s**: met; its registration comment says why it is above
    0.5 s. The budget is 10 of at most 13 (decision 21). All *measured*.
  - **`scripts/check_tree.sh` passes;** `restyle_fortran.py` and `format_use_blocks.py` were run on the Fortran
    files touched, by name, after the last edit, and rewrote none.
  - **The ABI probe needs no new class:** the wrappers pass handles by value, `int`, `float`, `size_t`, `const
    int*` and `uint64_t` by value, each of which `src/test/mlxf_abi_probe.h` already echoes.
- *Frozen tolerances:* none new; `RANDOM_SIGMAS = 5` is section 6's. Upstream-defect lines: 0.
- *Mutations and plants.*
  - 21 mutations of the wrappers and helpers on a scratch copy (`scratch/keep/phase5_final/phase5_mutations.txt`;
    runner `scratch/scripts/mutate.py`): 20 fail `unit_random`, by assertions or by a stop. **One survived:** a key
    not handed on by the helper of `mlx_random_bits` and `mlx_random_gumbel`. No test held those two to their key.
    `test_keyed` was added (eleven samplers give the same sample twice with one key), and that mutation with seven
    more of its kind, one per helper that takes a key, then fail (`phase5_mutations_keys.txt`); the restored copy
    passes. The runner's first run reused objects (it restored files with their old times, and `make` compares
    whole seconds): it was fixed to give every restored file a new time, and that run's results were discarded.
  - Ten planted violations fail the static gate and the restored copy passes
    (`scratch/keep/phase5_final/phase5_plants.txt`): the ratchet left at 76, a public name missing from `mlxf.f90`,
    a called function left pending, a wrapper that works before its entry, a helper missing from `ENTRY_HELPERS`,
    the area missing from CTest, a guard member without its case, a quickstart row without its block, a scalar
    `max` accumulation in the new tester, a function result in a constructor of handles.
- *The independent review* (a read-only subagent, against mlx-c's and MLX's source and the probe; it wrote
  nothing). No translation error, no lifetime defect and no entry defect found. Acted on:
  - **MLX 0.32.4 does not hold the array parameters of the normal to `shape`:** `mlx_random_normal([1], loc)` with
    five means returned five elements (read in `v0.32.4`'s `random.cpp`; later MLX refuses, commit `81770e8d8`).
    The wrapper now stops when the result has another shape than asked for, with the guard `guard_normal_shape`.
  - blind tests made discriminating, 49 checks: the shapes of the scalar normal and of the Laplace (a missed
    reversal in their helper was invisible), every sampler without a key (two helpers of nine were reached), the
    first draw after a seed against the second key of the split of that seed's key with a seed above 2**32, the
    key of a negative default-integer seed, the categorical forms along dimension 2, a uniform sample against
    `low + (high - low) u` of the same key (exchanged bounds were invisible), the multivariate normal without a
    shape and without a key, `dtype=` for the Gumbel, the array normal, the truncated normal and the Laplace.
  - the policy corrected: a sample may round to `high`; the float64 refusal's message per device; a keyless
    multivariate draw splits the global key on the default device; the sample sizes; `call mlx_random_split(key,
    key, sub)` stops (an aliased `intent(out)`); a default-integer seed is sign-extended.
  - Left as they are, for the maintainer: a stale array parameter stops under the name of the assignment that
    copies it, an empty `x` of `mlx_random_permutation` under `ndim`; complex64 samples of the normal, which MLX
    accepts, are not tested; a batched covariance of the multivariate normal is not tested; the bit-for-bit
    agreement of the two devices is observed, not promised.
- *Decisions under delegation.*
  - **A sampler takes its Fortran shape first and its key last:** `f(shape, parameters..., [dtype], [key])`, as
    `mlx_zeros(shape[, dtype])` and `mlx_full(shape, vals)` do. `shape` is required wherever mlx-c takes one, the
    multivariate normal's batch shape excepted; an empty shape gives a rank-0 sample.
  - **Parameters keep mlx-c's types:** arrays where C takes arrays (the bounds of the uniform, of the truncated
    normal and of the integers, `p`, `mean`, `cov`), real32 where C takes `float` (`loc` and `scale` of the normal
    and of the Laplace). The bounds of the uniform are optional, 0 and 1. `mlx_random_normal` is a generic of the
    scalar form and the array form (mlx-c's `normal` and `normal_broadcast`), told apart by the type of `loc`; in
    the array form `loc` is required and `scale` optional.
  - **Seeds are a default or a 64-bit integer** (`mlx_random_seed`, `mlx_random_key`): two specifics each, a
    default integer extended with its sign.
  - **`mlx_random_split` is two subroutines under one name:** `(key, first, second)` and `(key, num, keys)`, told
    apart by the second argument; `keys` is MLX's one array, (2, num) in the Fortran view, which `mlx_unstack`
    turns into a list. A list of handles as the result would have cost `num` nodes.
  - **`mlx_random_categorical` is one procedure with keywords,** `(logits[, dim, num_samples, shape, key])`, for
    mlx-c's three functions: a generic could not tell `(logits, dim)` from `(logits, num_samples)`. `num_samples`
    and `shape` together stop. Its default dimension is 1 (MLX's last axis, decision 7); its categories and
    `mlx_random_permutation(n)` are one-based int32 (decision 8); `mlx_random_permutation(x)` defaults to the
    last dimension (MLX's first axis, as `mlx_stack` and `mlx_split` do).
  - **`mlx_random_randint` keeps MLX's range,** `low` to `high - 1`: the values are not positions, so nothing is
    shifted.
  - **The multivariate normal runs on the CPU's default stream** (decision 9): MLX takes the root of the
    covariance by `linalg::svd`, which refuses the GPU stream (the probe). `cpu_stream`, private to
    `mlxf_array_operations` since Phase 4, became a module procedure of the `mlxf_array` family for it.
  - **An absent key is an empty handle in the helpers' last operand,** which reaches mlx-c as a null array; a key
    that is given is checked to be live in the wrapper, so an empty one never passes for "no key".
  - **A new submodule, `mlxf_array_random`,** holds the eleven helpers (by concern, as `mlxf_array_closure`),
    instead of `mlxf_array_operations` (2,410 lines); `mlxf_pair_op`, the default-device form of
    `mlxf_cpu_pair_op`, is there too.
  - **One guard for the wrappers' own stops joined at first, a second with the review** (23 members).
  - **A quickstart row, D20,** for what a Fortran user meets first: a sample is a function of its key and shape.
- *Surprises about MLX and mlx-c (measured in the probe unless said).*
  - float64 samples: `uniform`, `gumbel` and `truncated_normal` refuse the dtype on both devices; `normal` and
    `laplace` return float64 on the CPU holding the float32 draw.
  - The array parameters of `normal` are not held to the shape in 0.32.4 (above; read, then pinned by the guard).
  - One key gives the same values on the CPU and on the GPU, and a (4, 5) and a (20) sample of one key hold the
    same values.
  - `categorical` and `permutation(n)` return uint32.
- *Proposed, not applied* (skill edits need approval): `.github/skills/mlxf-binding/SKILL.md`, section 3, could
  list the samplers' helpers and say "an operand mlx-c takes as null is an empty handle read through
  `optional_handle`; the wrapper checks a present one"; `references/testing.md` could say "a mutation runner
  gives restored files a new time".
- *The new public names of the phase, for the maintainer's read.* Arrays are `type(mlx_array)`; `[x]` is optional
  and passed by keyword; `shape` is a Fortran shape; results are functions unless written `call`.
  - **Keys:** `call mlx_random_seed(seed)`, `mlx_random_key(seed)` (`seed` a default or a 64-bit integer),
    `call mlx_random_split(key, first, second)`, `call mlx_random_split(key, num, keys)`.
  - **Samplers:** `mlx_random_bits(shape[, width][, key])`, `mlx_random_uniform(shape[, low][, high][, dtype][, key])`,
    `mlx_random_normal(shape[, loc][, scale][, dtype][, key])` (real32 `loc`, `scale`),
    `mlx_random_normal(shape, loc[, scale][, dtype][, key])` (arrays),
    `mlx_random_laplace(shape[, loc][, scale][, dtype][, key])`, `mlx_random_gumbel(shape[, dtype][, key])`,
    `mlx_random_truncated_normal(shape, lower, upper[, dtype][, key])`,
    `mlx_random_randint(shape, low, high[, dtype][, key])`, `mlx_random_bernoulli(shape, p[, key])`,
    `mlx_random_multivariate_normal(mean, cov[, shape][, dtype][, key])`,
    `mlx_random_categorical(logits[, dim][, num_samples][, shape][, key])`,
    `mlx_random_permutation(x[, dim][, key])`, `mlx_random_permutation(n[, key])`.
- *Where a Fortran user would expect something else* (each stated in the binding policy, section 13):
  - there is no hidden generator state to save and restore: a key makes a draw repeatable, and the global key is
    for convenience;
  - the shape comes first, and the bounds of a uniform or integer draw are arrays (`mlx_from(-1.)` for a scalar);
  - `mlx_random_randint` excludes `high`; `mlx_random_categorical` and `mlx_random_permutation(n)` count from 1;
  - `num_samples` draws lie along a new first dimension, and the vectors of a multivariate normal along
    dimension 1;
  - samples are float32: three samplers refuse float64, two return it holding a float32 draw;
  - the multivariate normal runs on the CPU whatever the default device.
- *What it means, in short:* MLX's random numbers are reachable from Fortran in Fortran shapes, deterministic
  under a key on both devices, with every sampler's first two moments checked. 57 ledger lines remain, for Phases
  6 to 8.

### Phase 6a, the calibration of the transforms: 2026-11-26 04:34 EST (run mlxf_parity_rest, Claude)

- *How.* The new tester `mlxf_transforms_tester` (sub-suite `transforms` of the new area `unit_transforms`) built
  in Debug with its seed list held to the calibration seed alone and its tolerances at the ceiling, run as
  `mlxf_test_exec test=unit_transforms suite=transforms device=cpu|gpu` (logs
  `scratch/keep/phase6/phase6a_transforms_{cpu,gpu}_seed1.log`). Both devices on seed 1 (R4); no seed 2 or 3 ran
  before this entry. Three fixed functions on operands uniform in [-1, 1], rounded once to float32: the
  polynomial `3 x**3 - 2 x**2 + x - 5` on 48 points, `exp(a x)` on 48 pairs, and the chain
  `matmul(a, matmul(b, v))` with `a` (4, 3), `b` (3, 5), `v` (5); for `mlx_value_and_grad` their sums. The
  references are the closed-form derivatives written out in real64 (section 6: never differences); an element's
  error is relative to `max(1,` a sum of magnitudes that bounds it, or its own magnitude`)`.
- *Observed on seed 1, CPU / GPU, in float32 epsilons (measured):* `mlx_value_and_grad` 1.602 / 1.602, `mlx_vjp`
  0.922 / 0.922, `mlx_jvp` 0.551 / 0.551. float64 on the CPU, for the polynomial and the chain (MLX computes
  `exp` of float64 in float32, so `exp(a x)` is judged in float32 only): 3.32e-16 (1.50 eps64), 1.60e-16 (0.72)
  and 8.7e-17 (0.39). No finding.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`GRAD_TOLERANCES`), `max(2 x the larger of the CPU and GPU seed-1
  errors, 4 eps)` of the result kind *(derived)*: the floors, 4.768371582e-07 and 8.881784197e-16, for the three.
- *A first run of the sub-phase failed two exact checks* (`scratch/keep/phase6/` holds the second run): the
  gradients for `argnums [2, 1]` came in the order of the inputs. MLX sorts the positions (read in
  `transforms.cpp`); the wrapper now returns them in the caller's order (decision below). No tolerance was
  involved.

### Phase 6, transforms, compilation controls, export: 2026-11-26 05:01 EST (run mlxf_parity_rest, a scratch copy on the M5 Ultra, Claude) - complete

- *Machine, base and rulings:* as the entry "Phase 5, the base measurements"; the tree is that base plus R6 and
  Phase 5. Paths below are under the run's root, `.../scratchpad/parity5_work`.
- *Read before the API was fixed:* mlx-c's `transforms.h`, `closure.h`, `export.h`, `compile.h` and their sources
  at `v0.8.0`; MLX's `transforms.h` and `transforms.cpp` (the order of gradients).
- *Files.* New: `src/core/transforms/mlxf_transforms.f90` (module `mlxf_transforms`), `mlxf_transforms_tester.f90`,
  `transforms.inf`; `src/core/compile/mlxf_export.f90` (module `mlxf_export`), `mlxf_export_tester.f90`. Changed:
  `src/core/compile/mlxf_compile.f90` (the three controls; `mlxf_function_handle` and `mlxf_function_adopt`, the
  library's access to a function's closure); `src/defs/mlxf_defs.f90` (`MLX_COMPILE_MODES`); `src/core/mlxf.f90`;
  `src/test/mlxf_test_defs.f90` (`GRAD_TOLERANCES`), `src/test/mlxf_test_registry.f90` (area `transforms` with the
  sub-suites `transforms` and `export`; guards `guard_grad_argnums`, `guard_compile_mode`); `test/CMakeLists.txt`
  (`unit_transforms`, budget 11); `scripts/mlxc_parity.txt`, `scripts/check_rules.py` (`PARITY_PENDING` 41; the
  three new handle types in `HANDLE_TYPES`, their assignments and kills in `ENTRY_IF_LIVE`, the four new
  callbacks in `CALLBACKS`; rule `cbstop` reads a one-line `if`'s stop, with its file-table row); the binding
  policy (section 14 new; sections 6 and 11), the test policy (budget 11, 25 guard members), `README.md`,
  `CONTRIBUTING.md` (eleven entries), `doc/collaboration/apple_questions.md` (question 29); this plan. No file
  outside the table; `unit_compile`'s tester is untouched.
- *Exit items.*
  - **No `pending 6` line.** Ledger before: 343 public, 59 plumbing, 132 internal, 89 excluded, 57 pending (6: 16,
    7: 7, 8: 34). After: 359 public, 67 plumbing, 124 internal, 41 pending (7: 7, 8: 34); excluded unchanged
    *(exact)*. Eight lines go from `internal` to `plumbing`: `mlx_closure_value_and_grad_new` and `_free`,
    `mlx_closure_custom_new_func_payload` and `_free`, `mlx_closure_custom_jvp_new_func_payload` and `_free`,
    `mlx_function_exporter_free`, `mlx_imported_function_free`. `PARITY_PENDING = 41`; rule `parity` passes.
  - **`unit_transforms` passes on both devices in both builds:** 274 / 147 / 129 (both devices / CPU / GPU;
    `scratch/keep/phase6_final/areas_{Debug,Release}.txt`): the sub-suite `transforms` 178 / 99 / 81 and the
    sub-suite `export` 96 / 48 / 48. Sub-phase 6b, seeds 2 and 3 after the
    entry "Phase 6a": first run 04:35 EST (`scratch/keep/phase6/phase6b_unit_transforms_debug.log`, 234 of 234,
    before the review's 40 added checks). No judged check has failed in any run. Largest judged errors on seeds 2
    and 3 *(measured)*: `mlx_jvp` 1.327 eps32 (GPU), `mlx_vjp` 1.120, `mlx_value_and_grad` 1.071, against the floor
    4; float64 3.59e-16 (`mlx_value_and_grad`, 1.62 eps64), against 4 eps64.
  - **`unit_compile` is unchanged:** 63 / 32 / 32 in both builds.
  - **The existing suites keep their assertions** in both builds (`areas_{Debug,Release}.txt`): core 181 to 183 /
    157 / 157, array 193 / 103 / 101, ops 2,462 / 1,469 / 995, linalg 632 / 397 / 239, fft 194 / 101 / 94, fast
    94 / 13 / 82, random 486 / 244 / 242, kernels 1,955 / 896 / 1,145; `object_contracts` passes with 25 members.
  - **Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings**
    (`scratch/keep/phase6_final/build_{Debug,Release}.log`), **fast gate 11 of 11 in both** with
    `scripts/check_tree.sh` first (`gate_{Debug,Release}.log`), `scripts/check_install.sh --require-gpu` on both
    trees (`install_*.log`), **`scripts/release_gate.sh --allow-dirty` passes**
    (`release_gate_6f1af0d-dirty.log`, 74 s). All on the final state of the phase's sources; one comment of
    `test/CMakeLists.txt` was added afterwards (why `unit_transforms` is above 0.5 s in the gate).
  - **Ruling R5, judged (R3).** Release clean build: 19.969 s (1.544 + 18.425; load 2.30 before, 2.62 after) and
    19.916 s (1.536 + 18.380; load 2.62 before, 2.55 after) against **26.10 s**: met, 0.41 s above the base's
    mean. Fast gate total in Release: 10.68 s and 10.69 s against **38.74 s**: met. The new area
    `unit_transforms`: 0.65 and 0.63 s in the Release gate, 0.42 s alone, against **3 s**: met. The budget is 11
    of at most 13. All *measured*.
  - **`scripts/check_tree.sh` passes;** the formatters were run on the Fortran files touched, by name, after the
    last edit, and rewrote none.
  - **The ABI probe needs no new class:** the wrappers pass handles by value and by reference, `const int*` with
    `size_t`, `const char*`, `bool` and function pointers with a `void*` payload, all echoed by the probe; the
    two new trampolines receive handles by value, `const int*` and `size_t`, held by rule `cbsig`.
- *Frozen tolerances:* `GRAD_TOLERANCES`, the floors (entry "Phase 6a"). Upstream-defect lines: 0 (question 29
  reports three unchecked reads; the wrappers guard two of them and the policy states the third).
- *Mutations and plants.*
  - 24 mutations of the wrappers on a scratch copy (`scratch/keep/phase6/phase6_mutations.txt`): every one fails
    `unit_transforms`, 17 by assertions, 5 by a stop and 2 by a segmentation fault (a derived function without
    its payload; an exporter that forgets a failed trace, which is MLX's unchecked read of question 29,
    reproduced); the restored copy passes. They cover the shift and the order of `argnums`, each exchange of the
    two result lists and of the operands, the positions and the three lists the custom rules receive, a dropped
    rule, `shapeless`, a refused import, and each compilation control.
  - 11 planted violations fail the static gate and the restored copy passes
    (`scratch/keep/phase6/phase6_plants.txt`). **One did not at first:** `if( num == 0 ) error stop 3` in a
    trampoline passed, because rule `cbstop` read a stop only at the start of a statement. The rule now reads a
    one-line `if`'s stop too (file-table row added first), and the plant fails.
- *The independent review* (a read-only subagent, against mlx-c's source and MLX's at `v0.32.4`; it wrote
  nothing). No translation error in the C calls, the trampolines or the reordering of gradients. Acted on:
  - **three unchecked reads in MLX 0.32.4** (question 29): a custom vjp that returns another number of arrays
    than inputs (the trampoline now refuses it with a status); an exporter applied again after a failed trace
    (every copy now refuses, through a state the copies share; without the refusal the second application ends
    in a segmentation fault); `depends` of an empty list (the wrapper stops). A custom jvp returning more arrays
    than outputs and a rule-bearing function without outputs cannot be seen from the wrapper: the policy says so.
  - `mlx_vjp` and `mlx_jvp` are `recursive` (a callback may take a product: a derivative of a derivative), with
    a test of second derivatives both ways.
  - blind tests made discriminating, 40 checks: gradients for `argnums [2, 3, 1]` by their shapes (a
    2-permutation is its own inverse); a custom jvp given one tangent, of its second input (it always saw
    `[1, 2]`); a custom vjp that uses its three lists differently (exchanged lists were invisible); a checkpoint
    by its second run of the callback (a plain copy passed); 300 rounds of every transform with the active
    memory and the live handles compared (a leaked vector or closure was invisible to the live count); a
    shapeless exporter; a repeated position; empty exporters and imported functions in an OpenMP region.
  - the policy corrected: inside a callback only `apply(..., status=)` is checked, the other transforms stop
    under MLX's frames; an exported file records its operations' devices; what MLX's export does not serialize;
    an exporter truncates its file and refuses a signature twice; when the compile modes are read.
  - Left as they are, for the maintainer: that `mlx_depends` evaluates its dependencies is not tested; the three
    tracing compile modes are not told apart; an export on one device imported on the other is not tested; the
    scales of two derivatives in the tester are their own magnitudes (stricter than the sum of magnitudes; left,
    since the tolerances were frozen with them); payload frees cannot be observed from the public API.
- *Decisions under delegation.*
  - **`mlx_grad_function%apply` returns the gradients in the order of `argnums`.** MLX returns them in the order
    of the inputs; the handle keeps the rank of each position (an integer list beside the handle, copied by its
    assignment) and puts them back. The alternative, refusing unsorted positions, would have made the
    documented order MLX's accident.
  - **`argnums` is optional, the first input by default** (MLX's Python default); a position below 1 stops at
    construction, since MLX would count it from the end.
  - **`mlx_vjp` and `mlx_jvp` are subroutines of five dummies without `status`:** two input lists, two result
    lists and the function leave no room (rule `arity`), and a spec type for a status would be the only one of
    its kind. They stop on failure, as every graph-building procedure; `mlx_grad_function%apply`, which decision
    12 gives a status, is the checked route.
  - **Custom rules are checked subroutines** `(primals, cotangents, outputs, vjps, status)` and
    `(primals, tangents, argnums, jvps, status)`, as `mlx_function`'s callback is; the positions a jvp rule
    receives are one-based. `mlx_custom_function(f[, vjp][, jvp])` takes both as optional procedures; mlx-c's
    `vmap` closure is passed null (decision 12).
  - **Derived functions share the callback's payload,** through two helpers the compile module gives the
    library (`mlxf_function_handle`, `mlxf_function_adopt`); a function's handle stays private to its module
    otherwise.
  - **Export lives in `src/core/compile/mlxf_export.f90`** (the file table puts export with the compile
    folder), its tests in `unit_transforms` as the sub-suite `export`, so that `unit_compile` stays as it is, as
    the exit asks.
  - **`mlx_function_exporter` and `mlx_imported_function` have a checked `new`** beside their constructor
    functions (which stop): a file is the user's, and its absence must be testable in-process.
  - **`MLX_COMPILE_MODES`** is a vocabulary of `mlxf_defs`, checked before mlx-c, which indexes with it.
  - **Rule `cbstop` was tightened** (above); `scripts/check_rules.py` is in the table for the ledger and helpers,
    and the row for this was added before the edit.
- *Surprises about MLX and mlx-c.*
  - `value_and_grad` returns gradients sorted by position, whatever the order asked for (measured, then read).
  - The three unchecked reads of question 29 (read; the exporter's reproduced).
  - A checkpointed function runs its callback twice per gradient, as designed (measured: the trace count).
  - An exporter truncates its file on opening and writes each trace at once (read).
- *Proposed, not applied* (skill edits need approval): `.github/skills/mlxf-binding/SKILL.md` could gain "a handle
  type other than `mlx_array`: copy `mlx_function`, then add it to `HANDLE_TYPES`, its assignment and kill to
  `ENTRY_IF_LIVE`, its C callbacks to `CALLBACKS`"; `references/testing.md` could say "a live count does not see
  a leaked vector or closure: compare the active memory around a loop".
- *The new public names of the phase, for the maintainer's read.* Lists are arrays of handles; `[x]` is optional
  and passed by keyword; results are functions unless written `call`.
  - **Gradients:** `type(mlx_grad_function)`: `g = mlx_value_and_grad(f[, argnums])`, `call g%new(f[, argnums])`,
    `call g%apply(inputs, values, grads[, status])`, `call g%kill()`.
  - **Products:** `call mlx_vjp(f, primals, cotangents, outputs, vjps)`,
    `call mlx_jvp(f, primals, tangents, outputs, jvps)`.
  - **Custom rules and checkpoints** (each returns an `mlx_function`): `mlx_custom_vjp(f, vjp)`,
    `mlx_custom_function(f[, vjp][, jvp])`, `mlx_checkpoint(f)`.
  - **Operations:** `call mlx_depends(inputs, dependencies, outputs)` (`mlx_stop_gradient` exists since Phase 1).
  - **Files:** `call mlx_export_function(file, f, inputs[, shapeless][, status])`;
    `type(mlx_function_exporter)`: `e = mlx_function_exporter(file, f[, shapeless])`,
    `call e%new(file, f[, shapeless][, status])`, `call e%apply(inputs[, status])`, `call e%kill()`;
    `type(mlx_imported_function)`: `g = mlx_imported_function(file)`, `call g%new(file[, status])`,
    `call g%apply(inputs, outputs[, status])`, `call g%kill()`.
  - **Compilation:** `call mlx_enable_compile()`, `call mlx_disable_compile()`, `call mlx_set_compile_mode(mode)`,
    `MLX_COMPILE_MODES%disabled`, `%no_simplify`, `%no_fuse`, `%enabled`.
- *Where a Fortran user would expect something else* (each stated in the binding policy, section 14):
  - a gradient is taken of a callback's first output, which must be rank 0, and the other outputs come back too;
  - `mlx_vjp` and `mlx_jvp` have no `status`, and inside a callback a failing transform stops under MLX's frames;
  - a custom rule is not checked against the true derivative;
  - an exported function is a graph for the shapes (or ranks) it was traced with, tied to the device it was
    exported on, and custom rules are not exported;
  - the compilation controls act on functions compiled afterwards, for the whole process.
- *What it means, in short:* a Fortran program can differentiate the graphs its callbacks build, in reverse and
  forward mode and to higher order, replace a derivative, and write a function to a file and read it back, with
  errors as statuses where a caller can act on them. 41 ledger lines remain, for Phases 7 and 8.

### Phase 7a, the calibration of the fused layers: 2026-11-26 05:03 EST (run mlxf_parity_rest, Claude)

- *How.* The new tester `mlxf_fast_layers_tester` (sub-suite `fast_layers` of `unit_fast`) built in Debug with its
  seed list held to the calibration seed alone and its tolerances at the ceiling, run as
  `mlxf_test_exec test=unit_fast suite=fast_layers device=cpu|gpu` (logs
  `scratch/keep/phase7/phase7a_fast_layers_{cpu,gpu}_seed1.log`). Both devices on seed 1 (R4); no seed 2 or 3 ran
  before this entry. Operands uniform in [-1, 1], rounded once to float32 (logits times 3); the references are
  real64 loops over Fortran subscripts; an element's error is relative to `max(1, |reference|)`.
- *Observed on seed 1, CPU / GPU, in float32 epsilons (measured):* `mlx_layer_norm` 1.447 / 1.174, `mlx_rms_norm`
  1.650 / 1.144, `mlx_cross_entropy` 1.374 / 0.973, `mlx_rope` 1.490 / 1.428, `mlx_scaled_dot_product_attention`
  0.786 / 0.786. With float64 operands on the CPU the results are float64 and the errors float32's: 1.449, 1.525,
  1.234 and 0.222 float32 epsilons (`scratch/keep/phase7/fast_kinds_probe.txt` for the kinds). No finding.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`FAST_TOLERANCES`), `max(2 x the larger, 4 eps32)` *(derived)*: the
  float32 floor 4.768371582e-07 for the five, in both columns (section 6: a float64 result MLX computes in
  float32 is held to the float32 bound).
- *A sixth entry after the review, calibrated the same way* (05:14 EST; logs
  `scratch/keep/phase7/phase7a2_fast_layers_{cpu,gpu}_seed1.log`): `mlx_attention_fused`, MLX's fused attention
  kernel demanded with 64 features, which exists on the GPU only. Observed on seed 1: 0.656 float32 epsilons.
  Frozen at the floor before seeds 2 and 3 ran it. The same run judged the forms the review added to the five
  under their frozen floors: all within (the largest 1.650).

### Phase 7, fast and custom Metal kernels: 2026-11-26 05:24 EST (run mlxf_parity_rest, a scratch copy on the M5 Ultra, Claude) - complete

The custom Metal kernel of this phase was delivered by Phase 10; this entry delivers the other `fast` functions
and closes the phase.

- *Machine, base and rulings:* as the entry "Phase 5, the base measurements"; the tree is that base plus R6 and
  Phases 5 and 6. Paths below are under the run's root.
- *Read before the API was fixed:* mlx-c's `fast.h`; MLX's `fast.h` and `fast.cpp` at `v0.32.4` (`git show`): the
  checks and the fallback graphs of the five functions and of `gated_delta_update`.
- *Files.* New: `src/core/array/mlxf_array_fast.f90` (five signature helpers; file-table row first),
  `src/core/fast/mlxf_fast_layers_tester.f90`. Changed: `src/core/fast/mlxf_fast.f90` (five wrappers),
  `src/defs/mlxf_defs.f90` (`mlx_rope_spec`, `mlx_attention_spec`), `src/core/array/mlxf_array.f90` (interfaces),
  `src/core/mlxf.f90`, `src/test/mlxf_test_defs.f90` (`FAST_TOLERANCES`), `src/test/mlxf_test_registry.f90` (row
  `fast_layers` of area `fast`; guards `guard_attention_mask`, `guard_rope_offset`, `guard_optional_empty`,
  `guard_fused_on_cpu`), `test/CMakeLists.txt` (comments), `scripts/mlxc_parity.txt`, `scripts/check_rules.py`
  (`PARITY_PENDING` 34, `ENTRY_HELPERS`), the binding policy (section 15 new; section 5), the test policy (29
  guard members), `README.md`, `doc/collaboration/apple_questions.md` (question 30), this plan.
- *Exit items.*
  - **No `pending 7` line.** Ledger before: 359 public, 67 plumbing, 124 internal, 89 excluded, 41 pending (7: 7,
    8: 34). After: 365 public, 90 excluded, 34 pending (8: 34); plumbing and internal unchanged *(exact)*. Six lines
    are public (`mlx_fast_layer_norm`, `_rms_norm`, `_rope` and `_rope_dynamic` as `mlx_rope`,
    `_scaled_dot_product_attention`, `_cross_entropy`); `mlx_fast_gated_delta_update` is `excluded` under
    decision 17 (below). `PARITY_PENDING = 34`; rule `parity` passes.
  - **`unit_fast` passes on the GPU and its CPU half:** 152 / 47 / 107 in both builds
    (`scratch/keep/phase7_final/areas_{Debug,Release}.txt`): the sub-suite `fast` unchanged at 94 / 13 / 82 and
    `fast_layers` 58 / 34 / 25 (every layer on both devices; the fused attention kernel on the GPU, its refusal on
    the CPU a guard). Sub-phase 7b, seeds 2 and 3 after the entry "Phase 7a": first run 05:03 EST
    (`scratch/keep/phase7/phase7b_unit_fast_debug.log`, 149 of 149), again after the review
    (`phase7b2_unit_fast_debug.log`, 152 of 152). No judged check has failed in any run. Largest on seeds 2 and 3
    *(measured)*: `mlx_layer_norm` 1.955 eps32 (CPU), `mlx_rope` 1.623 (GPU), against the floor 4.
  - **The existing suites keep their assertions** in both builds: core 181 to 183 / 157 / 156 or 157, array 193 /
    103 / 101, ops 2,462 / 1,469 / 995, linalg 632 / 397 / 239, fft 194 / 101 / 94, compile 63 / 32 / 32,
    transforms 274 / 147 / 129, random 486 / 244 / 242, kernels 1,955 / 896 / 1,145; `object_contracts` passes
    with 29 members.
  - **Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings**
    (`scratch/keep/phase7_final/build_{Debug,Release}.log`), **fast gate 11 of 11 in both**
    (`gate_{Debug,Release}.log`), `scripts/check_install.sh --require-gpu` on both trees, and
    **`scripts/release_gate.sh --allow-dirty` passes** (`release_gate_6f1af0d-dirty.log`, 75 s), all on the final
    state of the phase.
  - **Ruling R5, judged (R3).** Release clean build: 20.140 s (1.552 + 18.588; load 1.55 before, 1.79 after) and
    20.179 s (1.538 + 18.641; load 2.47 before, 3.04 after) against **26.10 s**: met, 0.63 s above the base's
    mean. Fast gate total in Release: 10.64 s and 11.88 s (`unit_array` both times) against **38.74 s**: met. No
    new area; the budget stays 11. All *measured*.
  - **`scripts/check_tree.sh` passes;** the formatters were run on the Fortran files touched and rewrote none.
  - **The ABI probe needs no new class:** `float` and `bool` by value, `mlx_optional_float` by value and
    `const char*` are echoed by it.
- *Frozen tolerances:* `FAST_TOLERANCES`, the float32 floor for the six (entry "Phase 7a"). Upstream-defect
  lines: 0 (question 30 reports a defect in a corner of `rope`, which the wrapper refuses).
- *Mutations and plants.*
  - 23 mutations on a scratch copy, the area and the four guards run for each
    (`scratch/keep/phase7/phase7_mutations.txt`): 22 fail, 18 by assertions or MLX's own refusals and 4 by a
    guard that no longer stops. **One survives and is equivalent:** without the wrapper's refusal of a mask with
    `causal`, MLX refuses the same call with its own message and the same stop.
  - Seven planted violations fail the static gate and the restored copy passes
    (`scratch/keep/phase7/phase7_plants.txt`).
- *The independent review* (a read-only subagent, against MLX at `v0.32.4` and mlx-c; it wrote nothing). No
  translation error in the five wrappers. Acted on:
  - **A defect of MLX's GPU kernel, reproduced** (`scratch/keep/phase7/rope_offset_probe.txt`, question 30): a
    rank-1 offset of one element for several batches is read once per batch, so batches 2 and up get what lies
    behind it (differences of 0.6 to 0.8 against the rank-0 offset on the GPU, none on the CPU). `mlx_rope` now
    stops on a rank-1 offset whose extent is not the number of batches (`guard_rope_offset`).
  - `spec%scale` of the attention is an allocatable real: not set is `1/sqrt(d)`, and a zero or negative scale
    that is set is used (it was silently replaced).
  - the two comments on the frequencies said "times a frequency": they are divisors; the policy states the sense
    of the rotation, what `force_fused` refuses, the kinds a mask may have, the heads of keys and values.
  - blind tests made discriminating: three heads and a mask per head; the fused kernel (64 features, GPU,
    `force_fused`, causal and masked); the dynamic offsets with frequencies, frequencies without `traditional`,
    one position (MLX's single-step kernel), ranks 4 with partial traditional features and 5; the default base
    as a literal in the reference; guards for an empty optional array and for the fused kernel on the CPU.
  - **Not confirmed by measurement:** the review read the attention as true float64 on the CPU; measured, its
    error with float64 operands is 1e-8 (float32's, as `mlx_softmax` is), so its float64 column keeps the
    float32 floor.
  - Left as they are, for the maintainer: grouped heads (fewer key heads than query heads) are not tested;
    `guard_attention_mask` stops through MLX also without the wrapper's check (the equivalent mutant above).
- *Decisions under delegation.*
  - **`mlx_fast_gated_delta_update` is excluded** (decision 17 leaves it to the run): MLX's C++ header and mlx-c's
    give its seven arrays no shapes, its Python docstring gives some that disagree with the code (question 30);
    read from the code they are five layouts with time along MLX's second axis, a recurrence over time and two
    results. Fitting that into the policy would have meant documenting MLX from its fallback's source.
  - **Features along dimension 1, positions along dimension 2** (decision 7): nothing is translated, since
    MLX's last axes are Fortran's first dimensions. The classes of `mlx_cross_entropy` are one-based (decision
    8), shifted by `mlxf_zero_based`.
  - **`eps` is optional, 1e-5:** mlx-c has no default; this is the one MLX's own layers use.
  - **Two public records in `mlxf_defs`,** `mlx_rope_spec` and `mlx_attention_spec` (named `mlx_<x>`, as
    `mlx_conv_spec` was ruled): `mlx_rope(x[, spec][, offset][, freqs])` is one procedure for mlx-c's two
    functions (an array `offset` selects the dynamic one), and `mlx_scaled_dot_product_attention(queries, keys,
    values[, spec][, mask])` stays within five dummies.
  - **The offset of a rotary embedding is a count,** as `mlx_as_strided`'s: position 1 has angle 0.
  - **Not offered: mlx-c's `sinks` argument of the attention** (attention sinks, one logit per head): a sixth
    dummy or a bundle of arrays for a recent, niche option; null is passed. The precedent is `mlx_meshgrid`'s
    `indexing` and `mlx_pad`'s `axes`.
  - **The mask mode is derived:** `'causal'` from the spec, `'array'` when a mask is given, none otherwise.
  - **A new submodule, `mlxf_array_fast`,** for the five helpers; `optional_handle` (Phase 5) serves the
    optional weight, bias, frequencies and mask.
- *Surprises about MLX and mlx-c (measured unless said).*
  - The GPU kernel of `rope` and a one-element offset (above).
  - With float64 operands on the CPU the fused layers return float64 with float32 accuracy.
  - On the CPU device these functions are ordinary graphs, not fused nodes (read); `force_fused` stops there.
  - `gated_delta_update`'s docstring and code disagree on the state's shape (read).
- *Proposed, not applied* (skill edits need approval): `.github/skills/mlxf-binding/SKILL.md`, section 4, could
  add "a layer of `fast` acts along Fortran's first dimensions: features 1, positions 2; say which count is a
  count and which a position".
- *The new public names of the phase, for the maintainer's read.* `[x]` optional and passed by keyword.
  - `mlx_layer_norm(x[, weight][, bias][, eps])`, `mlx_rms_norm(x[, weight][, eps])` (real32 `eps`);
  - `mlx_cross_entropy(logits, targets)`;
  - `mlx_rope(x[, spec][, offset][, freqs])`, `type(mlx_rope_spec)`: `features = 0`, `traditional = .false.`,
    `base = 10000.`, `scale = 1.`, `offset = 0`;
  - `mlx_scaled_dot_product_attention(queries, keys, values[, spec][, mask])`, `type(mlx_attention_spec)`:
    `scale` (allocatable real32), `causal = .false.`, `force_fused = .false.`.
- *Where a Fortran user would expect something else* (each stated in the binding policy, section 15):
  - the layouts are (features, positions, ..., batch), the reverse of MLX's documentation;
  - `freqs` divide the angle; the offset counts positions before the first;
  - a mask is `mask(key, query, ...)`, and `causal` with a mask stops;
  - classes are one-based; the cross entropy is not averaged and is float32;
  - float64 operands give float64 results with float32 accuracy;
  - `mlx_fast_gated_delta_update` and the attention's sinks are not offered.
- *What it means, in short:* the layers MLX fuses for networks are one call each in Fortran's layout on both
  devices, with one GPU defect of MLX found, reported and refused. 34 ledger lines remain, all for Phase 8.

### Phase 8, IO, streams, distributed and the rest: 2026-11-26 06:07 EST (run mlxf_parity_rest, a scratch copy on the M5 Ultra, Claude) - complete

- *Machine, base and rulings:* as the entry "Phase 5, the base measurements"; the tree is that base plus R6 and
  Phases 5 to 7. Paths below are under the run's root. Rulings R5 and R6 reread at the start of the phase and
  before this entry.
- *Read before the API was fixed:* mlx-c's headers of streams, devices, memory, Metal, IO and its types, maps,
  graph utilities and distributed groups, and `map.cpp` (what an iterator returns at its end); MLX's
  `device.cpp` and its distributed backends (`~/src/mlx`, read only); and a C probe of what 0.32.4 does
  (`scratch/keep/phase8/phase8_probe.txt`).
- *Files.* New: `src/core/runtime/mlxf_stream.f90` and `mlxf_stream_tester.f90`; `src/core/array/mlxf_array_io.f90`
  and `mlxf_array_distributed.f90` (signature helpers); `src/core/io/mlxf_io.f90`, `mlxf_io_tester.f90`, `io.inf`;
  `src/core/distributed/mlxf_distributed.f90`, `mlxf_distributed_tester.f90`, `distributed.inf` (file-table rows
  first). Changed: `src/defs/mlxf_defs.f90` (`mlxf_group_spec`, `MLXF_MAP_END`), `src/core/runtime/mlxf_libc.f90`
  (`fopen`, `fclose`, `dup`, `fdopen`), `mlxf_device.f90` (availability, Metal capture), `mlxf_memory.f90` (memory
  limit, wired limit), `src/core/array/mlxf_array.f90` (interfaces, `nbytes`, `itemsize`, the generic
  `mlx_synchronize`), `mlxf_array_evaluation.f90` (`synchronize_all`, the sizes, `mlx_buffer_size`),
  `src/core/mlxf.f90`, `src/test/mlxf_test_registry.f90` (areas `io` and `distributed`, row `stream` of `core`,
  the named-only `distributed_ring`, `guard_send_rank`), `test/CMakeLists.txt` (budget 13),
  `scripts/mlxc_parity.txt`, `scripts/check_rules.py` (`PARITY_PENDING` 0, `HANDLE_TYPES`, `ENTRY_IF_LIVE`,
  `ENTRY_HELPERS`, `LIBC_NAMES`, the new rule `handle`), `scripts/check_tree.sh` (a comment), the binding policy
  (sections 16 to 18 new; 6, 7, 8), the test policy (budget 13, thirty guard members), `README.md`,
  `CONTRIBUTING.md`, this plan.
- *Exit items.*
  - **No `pending` line remains in the ledger.** Before: 365 public, 67 plumbing, 124 internal, 90 excluded, 34
    pending (all `pending 8`). After: **399 public, 90 plumbing, 101 internal, 90 excluded, 0 pending** (680
    lines, *exact*, counted with awk). The 34 pending lines are public; 23 lines move from internal to plumbing,
    since the library now calls them (streams, maps, GGUF handles, vectors of strings, the node namer, the
    group's handle). No line was excluded in this phase: GGUF's metadata, the thread-local streams and the
    metallib setters were excluded when the ledger was written. `PARITY_PENDING = 0`; rule `parity` passes.
  - **`unit_io` passes:** 846 / 446 / 400 (both devices / CPU / GPU) in both builds
    (`scratch/keep/phase8_final/areas_{Debug,Release}.txt`). The eight transfer kinds (float64 on the CPU) at
    ranks 0 to 4 with the extents (2, 3, 4, 2): each file is read as bytes, its NumPy header parsed in Fortran
    (the kind, the Fortran shape reversed, C order from rank 2 on), its data compared with the host array's
    bytes, the array loaded with its kind and shape and written again to the same bytes. No Python is involved.
  - **`unit_distributed` passes:** 55 / 28 / 28 in both builds, on the group of one a process launched alone
    gets.
  - **The existing suites keep their assertions** in both builds: array 193 / 103 / 101, ops 2,462 / 1,469 / 995, linalg 632 / 397 / 239, fft
    194 / 101 / 94, compile 63 / 32 / 32, transforms 274 / 147 / 129, fast 152 / 47 / 107, random 486 / 244 / 242,
    kernels 1,955 / 896 / 1,145; `unit_core` gains the sub-suite
    `stream` (33 / 25 / 25) and is 216 / 182 / 181 or 182 (the base's 181 to 183 / 156 or 157 / 156 or 157, with its
    two checks that depend on the allocator's reuse of an address, plus the sub-suite); `object_contracts` passes with 30 members.
  - **Debug and Release from scratch with `-DMLXF_WERROR=ON`, zero warnings**
    (`scratch/keep/phase8_final/build_{Debug,Release}.log`), **fast gate 13 of 13 in both**
    (`gate_{Debug,Release}.log`), `scripts/check_install.sh --require-gpu` on both trees, and
    **`scripts/release_gate.sh --allow-dirty` passes** (`release_gate_6f1af0d-dirty.log`, 76 s; `release_gate.out`), all on the final state of the phase.
  - **Ruling R5, judged (R3).** Release clean build: 20.303 s (1.545 + 18.758; load 1.75 before, 2.64 after) and
    20.270 s (1.525 + 18.745; load 1.80 before, 3.08 after) against **26.10 s**: met,
    0.75 s above the base's
    mean (19.533 s). Fast gate total in Release: 10.70 s and 10.77 s against
    **38.74 s**: met. The two new areas in the Release gate: `unit_io` 0.23 s and 0.25 s, `unit_distributed`
    0.13 s and 0.16 s
    against 3 s: met. The budget is 13 of at most 13. All *measured*.
  - **`scripts/check_tree.sh` passes;** the formatters were run on the Fortran files touched.
  - **The ABI probe needs no new class:** `FILE*`, `const char*`, `size_t*` and `bool*` results, a `bool`
    function result, handles by value and by reference, a map iterator by value and `const int*` with its count
    are echoed by it; the four libc functions are not of the generated layer.
  - **Reported, not gated (section 6): written here, never run.**
    - *Two processes on one Mac through MLX's ring backend.* The host file, one address per rank, saved as
      `ring.json`:

      ```
      [["127.0.0.1:5000"], ["127.0.0.1:5001"]]
      ```

      and, from a build tree, one command per terminal (or the first followed by `&`):

      ```
      MLX_ENABLE_TF32=0 MLX_RANK=0 MLX_HOSTFILE=ring.json test/mlxf_test_exec test=unit_distributed suite=distributed_ring
      MLX_ENABLE_TF32=0 MLX_RANK=1 MLX_HOSTFILE=ring.json test/mlxf_test_exec test=unit_distributed suite=distributed_ring
      ```

      Each process must end with all its assertions passed: the ring has two members, `mlx_all_sum`,
      `mlx_all_max` and `mlx_all_min` of a (3, 2) matrix that holds the rank, `mlx_all_gather` to (3, 4) with the
      first member's matrix first, `mlx_sum_scatter` to (3, 1) with column r of the sum on the member of rank r,
      and one message from the first member to the second (`mlx_send`, `mlx_recv_like`). The variables are those
      MLX's `ring.cpp` reads at `v0.32.4` (`MLX_RANK`, zero-based; `MLX_HOSTFILE`). Homebrew's MLX 0.32.4 has the
      ring backend: `mlx_distributed_is_available` gives true for `'any'`, `'ring'` and `'jaccl'`, false for
      `'mpi'` and `'nccl'` (*measured*, `scratch/keep/phase8/backends_available.txt`).
    - *A Metal capture opened in Xcode:* a program that calls `call mlx_metal_start_capture('trace.gputrace')`,
      evaluates on the GPU and calls `call mlx_metal_stop_capture()`, started with `MTL_CAPTURE_ENABLED=1`; the
      trace is opened in Xcode. The gate tests the refusal without the variable.
- *Frozen tolerances:* none; every comparison of the phase is exact (bytes, integers, statuses). Upstream-defect
  lines: 0.
- *Mutations and plants.*
  - 37 mutations on a scratch copy fail their area or a guard (`scratch/keep/phase8_final/mutations_io.txt` 21,
    `mutations_distributed.txt` 8 with `guard_send_rank`, `mutations_core.txt` 8); each restored copy passes. One
    survived the first run of the core set (the wired limit given returned as the previous one: the test set a
    limit and put the first back, which a setter echoing its argument also satisfies) and fails since the test
    sets two limits in a row.
  - **What a group of one cannot show is not mutated:** the peer's rank made zero-based, the group handed on, the
    reversed shape of `mlx_recv`, which collective is called. The named-only suite covers them and was never run.
  - 13 planted violations fail the static gate and the restored copy passes
    (`scratch/keep/phase8_final/plants.txt`). Three plants passed at first: two were ill-formed (a name taken
    out of `LIBC_NAMES`, which only stops the rule from seeing it; an unconditional thread guard in a `kill`,
    which the entry rule allows and a test catches, now a mutation), and **one showed a missing rule**: a handle
    type without its finalizer passed the gate. Rule `handle` now holds every type of `HANDLE_TYPES` to a `final`
    procedure and a defined assignment (file-table row first; two plants).
- *The independent review* (a read-only subagent, against mlx-c and MLX's source; it wrote nothing). Acted on:
  - **Distributed nodes are built on the CPU's default stream:** MLX's distributed primitives have no GPU
    implementation (`mlx/backend/metal/distributed.cpp` at `v0.32.4`, read), and with a GPU default device a collective over a real group would have failed its
    evaluation. Not visible on a group of one, where MLX returns the operand without a node.
  - **`mlx_synchronize()` no longer waits on a device type that has no device:** on a Metal build of MLX in a
    session without a GPU the default-stream call would have failed; it now waits on the default device's
    stream when that type has a device, then on the other type's.
  - **A name given twice is refused** by the two saves that take names (MLX's map would keep one array without
    a word).
  - **The end of an mlx-c map is told from a failure** (its iterators return 2 and 1), for arrays and for
    metadata; the constant is `MLXF_MAP_END` in `mlxf_defs`, used by two modules.
  - `fclose` runs on every path of the graph writers; a result handle is freed when its adoption fails with a
    status; `guard_send_rank` passes a status, so that only the wrapper's own check can stop it.
  - blind tests made discriminating: extents (2, 3, 4, 2), which no reversal leaves alone (the first fixture was
    (2, 3, 2, 2)); a host matrix's own bytes against the file; eight names given in no order, each back with its
    own array; the lengths of the returned names and metadata; the metadata found in the file's own text; the
    kinds GGUF returns; the buffer size of two arrays against the sum of each; twenty round trips through the
    three formats with the active memory compared; the ring suite rewritten for a matrix, the scattered sum and a
    message.
  - the policy says what the review found unsaid: `mlx_default_stream` is the default as it is now; a load is
    lazy; a refused save has already emptied the file (measured: `scratch/keep/phase8/refused_save_probe.txt`);
    which backends split a group; where the nodes run.
  - Left as they are, for the maintainer: **which stream carries an operation is not tested** (it does not show
    in a result, and the ledger keeps `mlx_stream_get_device` internal: a swap of the two default streams in
    `mlx_default_stream`, or a `mlx_set_default_stream` that did nothing, would pass the gate; the tester says
    so); a CPU-only MLX and a session without a GPU were not available for `mlx_synchronize()` and the stream
    constructors.
- *Decisions under delegation.*
  - **Every procedure of `mlxf_io` and of `mlxf_distributed` takes `status`,** beyond decision 15's and 18's
    signatures: a file is the user's and a peer is another process, so their failures must be testable
    in-process. The distributed helpers carry the procedure's name in `mlxf_group_spec` (with the group's handle,
    the peer, the shape and the dtype) to stay within five dummies.
  - **`mlx_synchronize` is a generic of two modules:** `synchronize_all` in the array module (it existed) and
    `synchronize_stream` beside the type.
  - **Sizes live in the evaluation submodule** (`a%nbytes()`, `a%itemsize()`, `mlx_buffer_size(arrays[, status])`),
    leaving the lifetime file as it is; `mlx_buffer_size` evaluates first, since MLX counts evaluated arrays only.
  - **Loaded names come back sorted,** and so does metadata: MLX keeps both in hash tables whose order means
    nothing. Metadata are a (2, n) character array; trailing blanks are not written.
  - **Loads and distributed nodes run on the CPU's default stream** (decision 9's rule for CPU-only functions).
  - **An absent backend is `'any'`:** a null pointer cannot pass the generated interface, and MLX's default is
    that string.
  - **`mlx_print_graph` without a file writes to a copy of the standard output's descriptor** (`fdopen(dup(1))`,
    after a flush of Fortran's unit), so that closing C's `FILE` leaves the standard output open. Four names
    joined `LIBC_NAMES`.
  - **`mlx_set_wired_limit(bytes[, previous, status])`** follows `mlx_set_memory_limit`; `mlx_memory_limit()` is a
    function, as the other queries.
  - **`mlx_device_is_available(device_type)`** asks about the first device of a type; an unknown type stops, as in the other device queries.
  - **Ranks, `dst` and `src` are one-based;** a rank below 1 stops in the wrapper (`guard_send_rank`), since MLX
    would take 0 for the first member.
  - **Tests of streams, availability, limits and capture are the sub-suite `stream` of `unit_core`;** two new
    areas, `io` and `distributed`, as the plan names them; the two-process suite is the named-only
    `distributed_ring`.
  - **Rule `handle`** (above).
- *Surprises about MLX and mlx-c (measured in the probes unless said).*
  - `mlx_load` built on the GPU's stream fails its evaluation ("[Load::eval_gpu] Not implemented").
  - A `.npy` file of a rank-0 or rank-1 array, or of a transposed view, says `'fortran_order': True`.
  - safetensors refuses float64; GGUF takes int8, int16, int32, float16 and float32 only; **a save refused for
    its kind leaves the file empty (safetensors) or a bare header (GGUF)**, an earlier file of that name lost.
  - A load is lazy: the data are read at evaluation (read).
  - On a group of one the collectives return their operand, a message and a split are refused, and a strict
    start fails; the ring and jaccl backends do not split (read).
  - `mlx_get_array_buffer_size` refuses arrays not yet evaluated; `mlx_set_wired_limit` refuses 2^50 bytes;
    `mlx_metal_start_capture` is refused without Metal's capture layer.
  - mlx-c's map iterators return 2 at the end and 1 on failure, a convention no header states (read).
- *Proposed, not applied* (skill edits need approval): `.github/skills/mlxf-binding/SKILL.md` could gain "a
  function MLX implements on the CPU only takes `cpu_stream`; a list mlx-c returns as a map is sorted by name
  before it is returned"; `references/testing.md` could say "a test of a setter that returns the previous value
  sets two values in a row" and "give a refusal test a status when MLX would also stop".
- *The new public names of the phase, for the maintainer's read.* `[x]` optional and passed by keyword; results
  are functions unless written `call`.
  - **Streams:** `type(mlx_stream)` (`kill`), `mlx_new_stream(device_type)`, `mlx_default_stream(device_type)`,
    `call mlx_set_default_stream(stream)`, `call mlx_synchronize(stream[, status])` beside
    `call mlx_synchronize([status])`.
  - **Runtime:** `mlx_device_is_available(device_type)`, `call mlx_metal_start_capture(path[, status])`,
    `call mlx_metal_stop_capture([status])`, `mlx_memory_limit()`,
    `call mlx_set_wired_limit(bytes[, previous][, status])`.
  - **Sizes:** `a%nbytes()` (int64), `a%itemsize()`, `mlx_buffer_size(arrays[, status])` (int64).
  - **Files:** `call mlx_save(file, a[, status])`, `mlx_load(file[, status])`,
    `call mlx_save_safetensors(file, names, arrays[, metadata][, status])`,
    `call mlx_load_safetensors(file, names, arrays[, metadata][, status])`,
    `call mlx_save_gguf(file, names, arrays[, status])`, `call mlx_load_gguf(file, names, arrays[, status])`,
    `call mlx_print_graph(arrays[, file][, status])`, `call mlx_export_to_dot(file, arrays[, status])`.
  - **Distributed:** `type(mlx_group)` (`g%rank()`, `g%size()`, `g%split(color[, key][, status])`, `kill`),
    `mlx_distributed_init([backend][, strict][, status])`, `mlx_distributed_is_available([backend])`,
    `mlx_all_sum(x[, group][, status])`, `mlx_all_max`, `mlx_all_min`, `mlx_all_gather`, `mlx_sum_scatter` (the
    same form), `mlx_send(x, dst[, group][, status])`, `mlx_recv(shape, dtype, src[, group][, status])`,
    `mlx_recv_like(x, src[, group][, status])`.
- *Where a Fortran user would expect something else* (each stated in the binding policy, sections 16 to 18):
  - operations take no stream; a stream is made the default of its device instead;
  - a file written from a Fortran (m, n) array is a NumPy (n, m) array, and reads back as (m, n) here;
  - a loaded array reads its file when it is evaluated; names come back sorted, not in the order saved;
  - float64 goes to `.npy` only; a refused save has already emptied the file;
  - files are read, and messages exchanged, on the CPU whatever the default device;
  - ranks count from 1; gathering and scattering act along the last dimension.
- *What it means, in short:* arrays move between Fortran, files and NumPy with the bytes and shapes a Fortran
  user expects, streams and the remaining runtime controls are reachable, and the distributed operations are
  wrapped and tested as far as one process can. **The ledger has no pending line:** every function of mlx-c
  0.8.0 is public, plumbing, internal or excluded with its reason. Phase 9, the report, follows.

### Phase 9, the report: 2026-11-26 06:18 EST (run mlxf_parity_rest, a scratch copy on the M5 Ultra, Claude) - complete

- *Machine, base and rulings:* as the entry "Phase 5, the base measurements"; rulings R5 and R6 reread before
  this entry. Paths below are under the run's root.
- *Files.* Changed: `doc/implementation_notes/completed/mlxf_mlxc_parity_report.md` (section 10 and its status
  line), `doc/history/2026-11.md` (one entry), `doc/collaboration/apple_questions.md` (question 31, with Phase
  8's findings), this plan. No source file.
- *Exit items.*
  - **The report exists,** in the order of `doc/how2s/how2write_agent_plans.md`, section 8: what was learned
    (10.1), what changed phase by phase (10.2), the decisions under delegation (10.3), the deviations (10.4), the
    evidence against the baseline with build and gate times (10.5), what is left open (10.6), a commit message
    that names the 21 new files (10.7); then what this phase's text asks beside: the ledger's final counts by
    class and every exclusion with its reason (10.8), the upstream questions (10.9), the frozen tolerances
    (10.10).
  - **`scripts/check_tree.sh` passes** on the final state (`scratch/keep/phase9_final/check_tree.log`).
  - **The run's finishing conditions,** on the final source state (`scratch/keep/phase9_final/`): Debug and
    Release from scratch with `-DMLXF_WERROR=ON`, zero warnings (`build_{Debug,Release}.log`); the fast gate 13
    of 13 in both (`gate_{Debug,Release}.log`); every unit area on both devices, on the CPU and on the GPU in
    both builds, 72 runs with exit status 0 (`areas_{Debug,Release}.txt`): core 215 or 216 / 181 or 182 / 181 or 182, array 193 / 103 / 101, ops 2,462 / 1,469 / 995, linalg 632 /
    397 / 239, fft 194 / 101 / 94, compile 63 / 32 / 32, transforms 274 / 147 / 129, fast 152 / 47 / 107, random
    486 / 244 / 242, io 846 / 446 / 400, distributed 55 / 28 / 28, kernels 1,955 / 896 / 1,145;
    `scripts/check_install.sh --require-gpu` on both trees; `scripts/release_gate.sh --allow-dirty` passes
    (`release_gate_6f1af0d-dirty.log`, 76 s), and again after the last edit of the documents
    (`scratch/keep/phase9_final2/`); both formatters on the 35 Fortran files the run touched or added rewrote
    none.
  - **Ruling R5, the final judgment.** Release clean build 20.267 s (1.543 + 18.724; load 1.53 before, 2.68 after) and 20.242 s
    (1.519 + 18.723; load 1.97 before, 3.63 after) against **26.10 s**: met. Fast gate total in
    Release 10.70 s and 10.70 s against **38.74 s**: met. New areas in the Release gate: `unit_random` 1.00 and 0.98 s,
    `unit_transforms` 0.59 and 0.74 s, `unit_io` 0.22 and 0.25 s, `unit_distributed` 0.13 and 0.16 s against 3 s: met. All *measured*.
- *The ledger, final (exact):* 399 public, 90 plumbing, 101 internal, 90 excluded, 0 pending, of 680 lines. At
  the run's base: 324, 59, 132, 89, 76.
- *Against the base:* 31 files changed, 21 new, none renamed or deleted
  (`scratch/keep/phase9_final/diff_base_repo.txt`); no build directory inside the copy and no process of the run
  left.
- *Decisions under delegation in this phase:* the report is a tenth section of the existing report file, as
  Phases 10 and 4 were added to it; question 31 gathers Phase 8's three upstream findings; the roadmap and the
  notes' README, which still describe parity as after Phase 3, are outside the file table and were left.
- *What it means, in short:* the parity plan's work is done as far as an agent can take it. What remains is the
  maintainer's: the read of four phases of API, the two reported-not-gated checks, the commit, and whether the
  plan now moves to `completed/`.
