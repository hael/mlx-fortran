# mlx-c parity, Phases 2 and 3: review report of run `mlxf_parity`

Status, 2026-11-26: section 10 adds Phases 5 to 9 (run `mlxf_parity_rest`): random numbers, transforms and
exported functions, the fused layers, files, streams and the distributed operations, delivered in a scratch copy
of the working tree, nothing committed. The ledger has no pending line; the report's closing tables (the
ledger by class with every exclusion, the upstream questions, the frozen tolerances) are sections 10.8 to 10.10.

Status, 2026-11-25: section 9 adds Phase 4, linear algebra, products and convolutions, delivered in a scratch
copy of the working tree, nothing committed. One gate waits for a ruling: the Release build-time bound, which
the base itself exceeds (section 9.4).

Status, 2026-11-24 (night): section 8 adds Phase 10, the kernels' wrappers (decisions 27 and 28), delivered in
a scratch copy of the working tree, nothing committed. Sections 1 to 7 are the report of Phases 2 and 3:

Status, 2026-11-24: delivered in the working tree, nothing committed. Base `8305556`, the M5 Ultra. The run
ends at the hold after Phase 3. The detail is in the Progress section of
[the plan](../planned/mlxf_mlxc_parity.md); the diffs are `/Users/hael/agent_runs/mlxf_parity/review/phase_2.diff`
and `phase_3.diff`.

## 1. What was learned

- **The Fortran view costs almost nothing here.** Of 146 mlx-c functions wrapped, one needs an extra node for
  the view itself (`mlx_tri`, one transpose, a view and not a copy). Matrices are handled by exchanging
  `tril`/`triu` and negating the diagonal number; flattening functions need nothing, because MLX's row-major
  order of the reversed shape is Fortran's array element order.
- **No accuracy finding.** Sixteen floating-point functions were calibrated on seed 1 on both devices; the
  largest tolerance is 31.25 float32 epsilons (the whole-array running sum) against the ceiling of 64. Three
  more functions compute CPU float64 in float32 (`mlx_logsumexp`, `mlx_logcumsumexp`, `mlx_softmax`), now
  listed in the binding policy.
- **A calibration needs enough samples.** One fixture per seed gave the running sum an error of 3.0 eps32; 16
  fixtures gave 15.6. The tester was changed before the freeze, and the judged seeds then passed first time.
- **No upstream defect** in either phase. Two premises of the plan were wrong: `mlx_topk` returns values, not
  positions, and `mlx_concatenate` without an axis flattens.
- **The M5 Ultra's base**: Release clean build 7.04 s, fast gate 8.7 s. After both phases: 7.65 s and 10.5 s.

## 2. What changed, phase by phase

| | Phase 2 (`phase_2.diff`) | Phase 3 (`phase_3.diff`) |
| --- | --- | --- |
| mlx-c functions made public | 111 | 35 |
| ledger pending | 274 to 163 | 163 to 128 |
| new public names | 56, and 7 extended | 16, and `mlx_take`, `mlx_slice` extended |
| signature helpers | 30 | 9 |
| testers | `ops_reduce`, `ops_sort`, `ops_shape` new; `ops_create` extended | `ops_index` new; the array tester extended |
| `unit_ops` checks | 1,536 to 2,314 | 2,314 to 2,402 |
| `unit_array` checks | 128 | 128 to 179 |

Phase 2: reductions with `dim`, `dims` or neither and `keepdims`; `maxloc`; scans; `mlx_softmax`; sorting;
shape operations; `cshift`; matrices; constructors and windows. Phase 3: gather, scatter and its four
combining forms, `mlx_put_along_dim`, `mlx_masked_scatter`, section updates, the dynamic slice,
`mlx_searchsorted`, `mlx_unique`; int8 and int16 transfers, `mlx_item`, the device-only dtypes. Both phases
update the binding policy, the README table and the history. In all, 21 tracked files changed and 7 added.

## 3. Decisions taken under delegation

All are recorded in the plan's Progress, entries "Phase 2 ... complete" and "Phase 3 ... complete". The ones
that shape the API:

1. `maxloc(a)` and `minloc(a)` return Fortran subscripts.
2. Functions that flatten in MLX return rank 1 in array element order.
3. `transpose`, `cshift` and `mlx_softmax` each serve an all-axes C function at one rank only, because the
   ledger gives it that Fortran name and Fortran or the policy fixes the name's meaning.
4. `mlx_tril` calls MLX's `triu` with -k and the reverse; `mlx_diag` and `mlx_eye` negate k; `mlx_tri` adds a
   transpose node.
5. Lists of arrays and `mlx_item` are subroutines.
6. An omitted `dim` is MLX's default axis read in the Fortran view (the last dimension for `mlx_stack`,
   `mlx_unstack`, `mlx_split`; dimension 1 for `mlx_diff`, `mlx_softmax`); `cshift`'s is Fortran's.
7. `mlx_meshgrid` has matrix indexing only; `mlx_pad` takes widths per Fortran dimension and an array value.
8. `mlx_scatter_add` chooses between two MLX functions by the rank of `updates`.
9. `mlx_unique` needs `size` and returns four arrays.
10. `mlx_item` and the transfers refuse another kind; device-only dtypes convert through `mlx_astype`.
11. The reduction tester's fixture was enlarged once before the freeze (entry "Phase 2a").

## 4. Deviations from the plan

- **A file outside the table**: `src/core/array/mlxf_array_borrow.f90`, added to the table for Phase 3 before
  its edit (decision 13's `mlx_view` and `mlx_alloc` live there).
- **Not offered**, each stated in the policy: the result dtype of `mlx_cumsum` and `mlx_cumprod`;
  `mlx_meshgrid`'s `indexing`; `mlx_pad`'s `axes`; `keepdims` for the whole-array `maxloc`/`minloc`; the
  optional flags of `mlx_unique` (always on).
- **Ledger lines that name another function than their own**: `mlx_tril public mlx_triu` and the reverse.
- **Existing internal helpers changed** (no public effect): `mlxf_reduce_op` and `mlxf_scan_op` take a record,
  `mlxf_concat_op` takes its axis translated, `mlxf_slice_op` shares `slice_bounds`; `mlx_take_along_dim`
  accepts every integer index dtype.
- **Expected and not found**: an upstream defect (decision 22 allowed three per phase); a tolerance near the
  ceiling.
- **Skill edits proposed, not applied**: the helper lists of `mlxf-binding`, sections 3 and 4.
- **Plan text read differently**: Phase 3's list names `split_sections`, which the ledger had in Phase 2
  (done there); Phase 2's names `contiguous`, already plumbing.

## 5. Evidence against the baseline

Logs under `/Users/hael/agent_runs/mlxf_parity/scratch/keep/`.

| | base (`base_meas/`) | after Phase 3 (`final_phase3/`) | bound |
| --- | --- | --- | --- |
| Release clean build | 7.091, 6.985 s | 7.649, 7.651 s | 14.08 s |
| fast gate, Release | 8.75, 8.72 s | 10.47, 10.51 s | 38.74 s |
| warnings, Debug and Release | 0 | 0 | 0 |
| fast gate entries | 8 of 8 | 8 of 8 | budget 8 |
| `unit_ops` (CPU / GPU) | 1,536 (950 / 587) | 2,402 (1,439 / 965) | |
| `unit_array` (CPU / GPU) | 128 (70 / 69) | 179 (96 / 94) | |
| core, linalg, fft, compile, kernels | 82, 32, 57, 63, 993 | unchanged | |

- Calibration and judged seeds: `phase2a_*`, `phase2b_unit_ops_debug.log`; the frozen table is
  `REDUCE_TOLERANCES` in `src/test/mlxf_test_defs.f90`.
- `scripts/check_tree.sh`, rule `parity` included, passes with Phases 2 and 3 closed.
- Each phase's diff was read by an independent read-only subagent against MLX's source. Phase 2: no
  translation error; argument checks, a contiguity fix in `mlx_as_strided` and three blind tests fixed. Phase
  3: one defect fixed (uint64 index arrays became float32) and four scatter tests that could not fail made
  discriminating.

## 6. Left open for the maintainer

- **The read at the hold** (reported, not gated): the Phase 3 Progress entry lists every public name of both
  phases with its signature, and every place where a name, an index convention or a default differs from
  what a Fortran user would expect. The choices most worth a second look: item 3 and item 8 of section 3
  (both would be cleaner with a new ledger name: `mlx_permute(a)` without `order`, a flattened roll,
  `mlx_scatter_add_along_dim`), `mlx_unique`'s four-array result, and subroutines for list results.
- **Argument forms without a test of their own**, listed in the two Progress entries (for example `ddof` with
  `dim`, index arrays of rank above 1 in gather and scatter, a lower-rank mask, negative strides in a section
  update).
- **`mlx_argsort`'s stability** is asserted on small lines though MLX documents none; the policy says not to
  rely on it.
- **Follow-up**: Phases 4 to 8 (128 pending lines), in decision 27's order; the two skill edits above; the
  plan stays in `planned/`.

## 7. A commit message

```
Parity with mlx-c, Phases 2 and 3: reductions, scans, sorting, shape, indexing, data types

146 mlx-c functions become public Fortran names in Fortran's conventions (dimensions,
1-based indices and positions, matrices as Fortran sees them), tested on both devices
against plain Fortran oracles. Reductions take dim, dims or neither and keepdims; maxloc(a)
returns subscripts; cshift has Fortran's sign; gather and scatter take 1-based index arrays.
int8 and int16 move through every transfer, mlx_item returns one element, and MLX_DTYPES
names the device-only dtypes. The parity ledger goes from 274 to 128 pending lines.
39 signature helpers, 7 spec records, submodules mlxf_ops_sort and mlxf_ops_index.
Base measurements on the M5 Ultra; build and gate bounds met.
```

## 8. Phase 10, the kernels' wrappers ahead of their turn

Delivered 2026-11-24 in a scratch copy of the maintainer's working tree on the M5 Ultra (`d0b1091` plus the
uncommitted toy refactoring), nothing committed. The detail is in the plan's Progress, entries "Phase 10,
part 1", "10a", "part 2", "10c", "part 3" and the closing "Phase 10 ... complete". Evidence paths are under
the run's root, `.../scratchpad/wrappers_work/scratch/keep`.

### 8.1 What was learned

- **A Metal kernel written as Fortran text fails softly.** A source that does not compile fails the
  evaluation with a status and the Metal compiler's line and caret in `mlx_last_error()`, and MLX evaluates
  other kernels afterwards; so do a threadgroup above the device's 1,024 threads and a float64 output
  (`part1_kernel_failures_probe.txt`, and `unit_fast`).
- **A kernel object per launch configuration costs nothing.** MLX compiles a generated source once per
  process: 60 ms for the first evaluation of a new source, 0.2 ms to build, apply and evaluate a second
  kernel object with the same source and another grid (`part1_kernel_cache_probe.txt`).
- **The Fortran view is free in all 15 wrappers:** no transpose and no copy. A real transform's half-size
  dimension is passed to MLX last; products are called with operands, lists and masks exchanged; the only
  added nodes are the shifts of 1-based lists and segments.
- **No accuracy finding.** Both devices agree with a direct real64 DFT to 2.5 float32 epsilons of the largest
  element and with real64 `matmul` to 2.1 epsilons of the dot product's scale; every frozen tolerance is the
  floor of 4 epsilons but two (4.18 and 4.02).
- **Two limits of MLX 0.32.4 a kernel plan must know:** the gathered and the masked product are float32 only
  (a status at the evaluation on float64 operands), and none of the three products takes complex operands.
- **Two reports for Apple** (questions 21 and 22): mlx-c's Metal kernel cannot choose MLX's math mode, and
  `segmented_mm` does not check that its inner extents agree.
- **A process trap:** Apple's make compares whole seconds. Mutation tests that edit, build and run in a loop
  silently tested the previous mutation until the archive and the executable were deleted before each build.

### 8.2 What changed, part by part

| | part 1, the Metal kernel | part 2, the FFT lines | part 3, the products |
| --- | --- | --- | --- |
| mlx-c functions made public | 2 (and 14 from `internal` to `plumbing`) | 10 | 3 |
| ledger pending | 128 to 126 | 126 to 116 | 116 to 113 |
| new public names | `mlx_metal_kernel`, `mlx_metal_kernel_spec` | 10 | 3 |
| helpers | `mlxf_check_dtype` shared | `mlxf_fftn_op` (was `mlxf_fft2_op`), `mlxf_freq_op`, `mlxf_axes_of` shared | `mlxf_gather_mm_op`, `mlxf_masked_mm_op`, `mlxf_zero_based` shared |
| testers | `mlxf_fast_tester` (new area `unit_fast`) | `mlxf_fft_nd_tester` | `mlxf_linalg_mm_tester` |
| checks | `unit_fast` 94 (13 CPU, 82 GPU) | `unit_fft` 57 to 194 | `unit_linalg` 32 to 94 |

22 tracked files changed and 5 added (a new folder, `src/core/fast/`, with three files). The CTest budget
goes from 8 to 9; `object_contracts` from 13 to 16 members.

### 8.3 Decisions taken under delegation

All are in the Progress entries named above. The ones that shape the API:

1. A kernel object owns its launch configuration (the whole spec is read once by `new`); `apply` takes the
   arrays and an optional `status`, as `mlx_function`'s does.
2. `mlx_metal_kernel_spec` is one record of plain components; it gained `init_value` and `verbose`, which
   decision 17 does not list.
3. The half-size dimension of a real transform is the first listed, dimension 1 by default; `n` pairs with
   `dims` in the caller's order.
4. Matrices of a gathered product are numbered from 1 in array element order over the batch dimensions;
   segments are inclusive 1-based bounds.
5. `mlx_block_masked_mm` takes the two operand masks as one array of two handles (rule `arity`).
6. Errors of transforms are judged relative to the largest element of the result, errors of products
   relative to the product of the absolute values.
7. The base is the uncommitted working tree, since the commit decision 28 names did not exist yet.

### 8.4 Deviations from the plan

- **Files outside the table:** `src/core/ops/mlxf_ops.f90`, `mlxf_ops_index.f90`, `mlxf_ops_shape.f90`, added
  to the table for Phase 10 before their edit: `zero_based` moved to the array module so that the products
  share it.
- **The module is `mlxf_fast`**, not a module of the kernel's own name; the plan names only the folder.
- **Existing internal helpers changed** (no public effect): `mlxf_fft2_op` became `mlxf_fftn_op`;
  `check_dtype`, `axes_of` and `zero_based` became the shared `mlxf_check_dtype`, `mlxf_axes_of` and
  `mlxf_zero_based`. `mlx_fft2`'s 57 checks and `unit_ops`' 2,402 are unchanged.
- **The wrapper checks more than MLX** for `mlx_segmented_mm` (ranks, inner extents, the segments' shape).
- **Expected and not found:** an upstream defect in the sense of decision 22; a tolerance near the ceiling.
- **Tests changed after their freeze, tolerances not:** the review's blind tests were made discriminating
  (other lengths, a larger masked fixture, added forms); every judged error stayed within its tolerance.
- **Skill edits proposed, not applied:** the helper list of `mlxf-binding`, section 3, still names
  `mlxf_fft2_op`.

### 8.5 Evidence against the baseline

| | base (`base/`) | after Phase 10 (`final/`) | bound |
| --- | --- | --- | --- |
| Release clean build | 8.27 s (this night, load 1.6); 7.04 s (Phase 2's base) | 8.604, 8.721 s | 14.08 s |
| fast gate, Release | 8.7 s (Phase 2's base) | 10.66, 10.77 s | 38.74 s |
| `unit_fast` in the gate | none | 0.24 s | 3 s |
| warnings, Debug and Release | 0 | 0 | 0 |
| fast gate entries | 8 of 8 | 9 of 9 | budget 9 of at most 13 |
| `unit_fast` (CPU / GPU) | none | 94 (13 / 82) | |
| `unit_fft` (CPU / GPU) | 57 (29 / 28) | 194 (101 / 94) | |
| `unit_linalg` (CPU / GPU) | 32 (17 / 15) | 94 (50 / 45) | |
| core, array, ops, compile, kernels | 82, 179, 2,402, 63, 1,063 | unchanged | |
| ledger pending | 128 | 113 | 113 |

- Calibrations and judged seeds: `phase10a_*`, `phase10b_unit_fft_debug.log`, `phase10c_*`,
  `phase10d_unit_linalg_debug.log`; the frozen tables are `FFT_TOLERANCES` and `MM_TOLERANCES`.
- Planted violations and mutations, each failing: `part1_plants.txt` (6 rule plants), `part2_mutations.txt`
  (7), `part3_mutations.txt` (6).
- Gates per part and at the end: `part1/`, `part2/`, `part3/`, `final/` (builds, gates, every area on both
  devices and on each alone).
- An independent read-only review against MLX's source: no translation or lifetime defect; one missing
  check, one borrowed message and eight blind or missing tests fixed (the closing Progress entry lists them
  and what stays untested).

### 8.6 Left open for the maintainer

- **The read of the API** (reported, not gated): the closing Progress entry lists the 15 names with their
  signatures and where a Fortran user would expect something else. Most worth a second look: the kernel
  object owning its launch configuration; `operand_masks(2)`; `dims` required for `mlx_rfft2` and optional
  for `mlx_rfftn`.
- **Not verified:** nothing was built or run in the maintainer's checkout; the change exists only in the
  scratch copy and has to be carried over (the file list is in the closing Progress entry). A kernel in a
  shapeless compiled function, kernel outputs above rank 2, template dtypes other than float32, real or
  batched operand masks and vector operands of the products have no test. The math-mode gap and
  `segmented_mm`'s missing check were read in the sources, not run.
- **Follow-up:** `mlxf_ops` keeps a second `axes_of` and three testers keep private copies of `judge` (outside
  this phase's table); `mlxf_fft_spec` keeps two-element lists of which one element is read; the skill edits
  above; Phases 4 to 8 (113 lines).

### 8.7 A commit message

```
Parity with mlx-c, Phase 10: the Metal kernel, n-dimensional FFTs, gathered and masked products

15 mlx-c functions become public Fortran names, ahead of their phases, for milestone 2's
kernels. mlx_metal_kernel builds a custom Metal kernel from a spec record and applies it
with a status; a source that does not compile fails the evaluation, not the process.
mlx_fftn, mlx_rfftn, mlx_rfft2 and their inverses transform in Fortran's layout, the real
ones with the half-size dimension first; mlx_fftshift, mlx_ifftshift, mlx_fftfreq and
mlx_rfftfreq go with them. mlx_gather_mm, mlx_block_masked_mm and mlx_segmented_mm multiply
chosen matrices, masked blocks and segments of the inner dimension. Tested on both devices
against exact references, a direct double-precision DFT and double-precision matmul; new
area unit_fast (CTest budget 9). The parity ledger goes from 128 to 113 pending lines.
```

## 9. Phase 4, linear algebra, products and convolutions

Delivered 2026-11-25 in a scratch copy of the maintainer's working tree on the M5 Ultra (`1e0ae97` plus the
uncommitted Phase 10 wrappers and three oracle modules), nothing committed. The detail is in the plan's
Progress: three entries "Phase 4a", the entries "family 1", "family 2", "family 3" and the closing "Phase 4
... complete". Evidence paths are under the run's root, `.../scratchpad/parity4_work/scratch/keep`.

### 9.1 What was learned

- **The transposed view is free for half of linear algebra and costs views for the rest.** Inverses,
  determinants and the SVD need nothing (MLX's U and Vt exchange roles, also for complex matrices); the
  Cholesky factor, the triangular inverse and the symmetric eigenvalues need the other triangle asked of MLX.
  QR, LU, the general eigenproblem and the solvers need the operand **and every returned matrix** transposed:
  three `swapaxes` nodes for `mlx_qr`, where decision 9's table lists one. No copy anywhere.
- **MLX 0.32.4 runs every factorisation on the CPU only,** and a graph that crosses the CPU and the GPU
  stream evaluates correctly; the wrappers choose the CPU stream themselves. Of the norms only the orders 2
  and -2 of a matrix and `'nuc'` need it (`phase4_behaviour_probe_tf32_0.txt`).
- **No accuracy finding.** Every backward error, residual and departure from orthogonal is below 2 n
  epsilons of its kind against section 6's 10; every product, determinant, norm and convolution is below 1.4
  float32 epsilons of its scale, so all 21 frozen tolerances are the floor of 4.
- **Three float32-only operations hide behind float64 graphs:** the Hadamard transform fails its evaluation
  on float64; a convolution is computed in float32 on float64 operands when nothing is dilated, and fails the
  evaluation otherwise (`phase4_hadamard_float64_probe.txt`, `phase4_conv_float64_probe.txt`; question 24).
- **A transposed convolution with a padding above `dilation*(k-1)` returns less than the definition**
  (`phase4_conv_transpose_padding_probe.txt`; question 23). The wrappers pass it through and the policy says
  where the formula holds.
- **The build-time bound of R3 no longer fits the tree.** The base builds in 15.03 s in Release against the
  frozen 14.08 s, before any edit of this phase: the oracle modules that entered after Phase 10's base. The
  phase adds 0.47 s.
- **A hole in rule `ctorexpr`:** a function result of a test helper imported from another file, inside a
  constructor of handles, was seen by neither constructor rule. The review found the leak in a new tester;
  the rule now counts imported handle functions.

### 9.2 What changed, family by family

| | family 1, products | family 2, matrices | family 3, convolutions |
| --- | --- | --- | --- |
| mlx-c functions made public | 10 | 20 | 7 |
| new public names | `mlx_addmm`, `mlx_inner`, `mlx_outer`, `mlx_kron`, `mlx_vecdot`, `mlx_cross`, `mlx_tensordot`, `mlx_einsum`, `mlx_hadamard_transform` | `mlx_inv`, `mlx_pinv`, `mlx_tri_inv`, `mlx_det`, `mlx_slogdet`, `mlx_cholesky`, `mlx_cholesky_inv`, `mlx_qr`, `mlx_lu`, `mlx_lu_factor`, `mlx_svd`, `mlx_eigh`, `mlx_eigvalsh`, `mlx_eig`, `mlx_eigvals`, `mlx_solve`, `mlx_solve_triangular`, `mlx_norm`, `mlx_norm_matrix`, `norm2` | `mlx_conv1d`, `mlx_conv2d`, `mlx_conv3d`, `mlx_conv_general`, `mlx_conv_transpose1d`, `mlx_conv_transpose2d`, `mlx_conv_transpose3d`, `mlx_conv_spec` |
| module | `mlxf_linalg` (extended) | `mlxf_linalg_matrix` (new) | `mlxf_conv` (new) |
| helpers | `mlxf_binary_axis_op`, `mlxf_optional_float_op`, `mlxf_addmm_op`, `mlxf_einsum_op`, `mlxf_tensordot_op` | nine `mlxf_cpu_*`, `mlxf_norm_op`, `mlxf_norm_text_op`, `mlxf_one_based` shared | seven `mlxf_conv*_op` |
| tester (sub-suite of `unit_linalg`) | `mlxf_linalg_products_tester` | `mlxf_linalg_matrix_tester` | `mlxf_conv_tester` |
| checks, both devices / CPU / GPU | 95 / 60 / 36 | 400 / 265 / 136 | 43 / 22 / 22 |

The ledger goes from 113 to 76 pending lines. 24 files changed and 5 added, all under rows of the
file table that list Phase 4. `object_contracts` goes from 16 to 19 members; the CTest budget stays 9.

### 9.3 Decisions taken under delegation

All are in the Progress entries named above. The ones that shape the API:

1. Functions with several results are subroutines (`mlx_qr`, `mlx_lu`, `mlx_lu_factor`, `mlx_svd`, `mlx_eigh`,
   `mlx_eig`, `mlx_slogdet`); `mlx_svd` has a second form for the values alone.
2. The LU permutation and the pivots are 1-based int32; `p` is MLX's permutation, `pivots` LAPACK's sequence.
3. `uplo` is a letter naming the triangle of the Fortran matrix; `upper` flags are logicals, as in MLX.
4. The CPU stream is the wrapper's choice for every CPU-only function, and by order for the norms.
5. Three norm names, as the ledger has them; `mlx_norm_matrix` defaults to dimensions 1 and 2 of any rank.
6. Products exchange their operands so that `a`'s dimensions come first; a shared dimension is passed as
   the axis `-dim`; `mlx_vecdot` keeps its name (no `dot_product`, which is outside the ledger).
7. `mlx_einsum` letters are Fortran dimensions, the unnamed result is made explicit, the ellipsis is the
   trailing dimensions.
8. Convolutions take `(input, weight[, spec])` with `type(mlxf_conv_spec)`, the plan's name, lists per
   spatial dimension with W first; a field a function does not take stops.
9. A transposed convolution's corner (question 23) is documented, not refused, and no ledger line excluded.
10. The phase was finished although the build-time bound is exceeded, because the excess is the base's; the
    stop is recorded at R3's judgment (9.4).

### 9.4 Deviations from the plan

- **Ruling R3's build bound is not met:** 15.51 s against 14.08 s, of which the base accounts for 15.03 s.
  Section 7 makes this a stop; it is recorded at the end of the phase, where R3 judges, with the ruling it
  needs (re-freeze on the present base, or shorten the oracles' compilation).
- **Decision 9's table undercounts the transposes** of `qr`, `lu`, `lu_factor`, `eig`, `solve` and
  `solve_triangular`, and does not cover complex `eigh` (a conjugate as well). Views only.
- **The wrappers of the three families were written before the first family was tested** (rule `parity`
  needs a called function public); each family was then calibrated, frozen, judged and gated in turn.
- **`index_result` moved** from `mlxf_ops` to the array module as `mlxf_one_based` (four files of
  `src/core/ops`, within the table); `unit_ops` is unchanged at 2,402.
- **Rule `ctorexpr` was extended** (9.1), with its plant.
- **float64 is not tested** for the Hadamard transform and the convolutions, which MLX does not evaluate in
  float64.
- **Tests changed after their freeze, tolerances not:** the review's four blind convolution fixtures and
  four added forms; every judged error stayed within its tolerance.
- **Expected and not found:** an accuracy finding; a function to exclude under decision 22; a copy needed by
  the Fortran view.
- **Skill edits proposed, not applied** (the helper list and three rules for `mlxf-binding`; two traps for
  `references/testing.md`).

### 9.5 Evidence against the baseline

| | base (`base/`) | after Phase 4 (`final/`) | bound |
| --- | --- | --- | --- |
| Release clean build | 15.049, 15.011, 15.041 s | 15.507, 15.510 s | 14.08 s: **not met, by the base** |
| fast gate, Release | 11.40 s | 10.85, 10.77 s | 38.74 s |
| `unit_linalg` in the gate | 0.22 s | 0.39 s | |
| warnings, Debug and Release | 0 | 0 | 0 |
| fast gate entries | 9 of 9 | 9 of 9 | budget 9 of at most 13 |
| `unit_linalg` (CPU / GPU) | 94 (50 / 45) | 632 (397 / 239) | |
| core, array, ops, fft, compile, kernels, fast | 82, 179, 2,402, 194, 63, 1,063, 94 | unchanged | |
| `object_contracts` members | 16 | 19 | |
| ledger pending | 113 | 76 | 76 |
| largest residual | | 1.96 n eps | 10 n eps |
| mutations caught | | 41 of 41 | |
| plants failing the static gate | | 7 of 7 | |

### 9.6 Left open for the maintainer

- **The ruling on the build-time bound** (9.4). Recommended at the review: re-freeze at 22.07 s, the present
  base's mean (15.03 s) plus the room Phase 2 gave above its own base (7.04 s), so that the oracles' cost is
  taken out of the judgment and parity's room stays what it was. Phase 5 is not started before the ruling.
- **The name of the convolutions' record:** the run kept the plan's `mlxf_conv_spec`; at the review it
  became `mlx_conv_spec`, the house's form for user-facing types, before the name was committed. Say so if
  the plan's name is the one wanted.
- **`dot_product`:** `mlx_vecdot` is its batched form; a generic of the intrinsic's name needs a ledger name.
- **Questions 23 and 24 for Apple** are written and not sent.
- **Untested forms** listed in the closing Progress entry (batches of five factorisations, a rectangular
  `mlx_lu_factor`, a complex `uplo='U'`, ellipses that lead or differ in rank, groups in a transposed 2D
  convolution); stops without a guard; float64 refusals measured in probes only.
- **`mlx_solve` with a batch of `a` and one `b`** stops inside MLX; the wrapper could broadcast `b` first.
- **`mlxf_linalg_matrix_tester` is the slowest file of the tree to compile** (4.0 s at `-O3`).
- **The skill edits** proposed in the closing Progress entry.

### 9.7 A commit message

```
Parity Phase 4: linear algebra, products and convolutions

37 mlx-c functions get public Fortran wrappers; the parity ledger goes from 113 to 76 pending lines.

- Products (mlxf_linalg): mlx_addmm, mlx_inner, mlx_outer, mlx_kron, mlx_vecdot, mlx_cross, mlx_tensordot,
  mlx_einsum (subscripts in Fortran's dimension order), mlx_hadamard_transform.
- Matrices (new module mlxf_linalg_matrix): mlx_inv, mlx_pinv, mlx_tri_inv, mlx_det, mlx_slogdet, mlx_cholesky,
  mlx_cholesky_inv, mlx_qr, mlx_lu, mlx_lu_factor, mlx_svd, mlx_eigh, mlx_eigvalsh, mlx_eig, mlx_eigvals,
  mlx_solve, mlx_solve_triangular, mlx_norm, mlx_norm_matrix, norm2. A matrix is dimensions 1 and 2; where
  MLX's transposed view is not free the operand and the results are transposed (views). MLX runs these on the
  CPU only, so they go to the CPU's default stream whatever the default device.
- Convolutions (new module mlxf_conv): mlx_conv1d/2d/3d, mlx_conv_general, mlx_conv_transpose1d/2d/3d, with the
  record mlx_conv_spec; input (C, W[, H[, D]], N), options per spatial dimension, W first.
- 23 signature helpers in the array module; index_result becomes the shared mlxf_one_based.
- Tests: sub-suites linalg_products, linalg_matrix and conv of unit_linalg (94 to 632 checks) on both devices:
  real64 loops for the products and convolutions at 4 float32 epsilons, residuals and orthogonality at 10 n
  epsilons for the factorisations; three guards; 41 mutations caught.
- Rule ctorexpr also counts imported functions with a handle result.
- Policy sections 7 and 10, README, questions 23 and 24 for Apple, the probe of CPU-only functions extended.

Release clean build 15.5 s (base 15.0 s): the bound frozen in Phase 2 (14.08 s) needs a new ruling.
```

## 10. Phases 5 to 9: random numbers, transforms, the fused layers, files, streams, distributed

Delivered 2026-11-26 by run `mlxf_parity_rest` in a scratch copy of the maintainer's working tree on the M5 Ultra
(`6f1af0d` plus the uncommitted, verified result of run `mlxf_toy_seam`: 50 changed and 16 untracked paths),
nothing committed. The run finished: every phase reached its exit and no stop condition of the plan's section 7
arose. The detail is in the plan's Progress, in the entries "Phase 5, the base measurements", "Phase 5, ruling
R6", "Phase 5a", "Phase 6a", "Phase 7a", the four closing entries "Phase 5" to "Phase 8 ... complete" and "Phase
9". Evidence paths are under the run's root, `.../scratchpad/parity5_work/scratch/keep`. Rulings R5 (the bounds
on this base) and R6 (the thirty scalar `max` reductions) are the run's `spec/rulings.md`.

### 10.1 What was learned

- **The ledger is closed.** Every one of mlx-c 0.8.0's 680 functions is public (399), plumbing (90), internal
  (101) or excluded with its reason (90); none is pending (10.8).
- **No accuracy finding in the new families.** The gradients, the vector-Jacobian and Jacobian-vector products
  and the six fused layers are all at the floor of 4 epsilons of their kind; the largest judged errors are 1.96
  float32 epsilons (`mlx_layer_norm`, CPU) and 1.62 (`mlx_rope`, GPU). The samplers' largest z-score over three
  seeds is 2.84 against 5 sigmas at 2^20 samples (10.10).
- **Five functions of MLX 0.32.4 read past what they were given, or return something else than their
  documentation says** (questions 29 to 31, all written, none sent):
  - a `FunctionExporter` whose trace failed ends in a segmentation fault at its next application (reproduced);
    a custom vjp that returns fewer arrays than inputs is given a cotangent as its product (read);
  - the Metal kernel of `fast::rope` reads one offset per batch from a rank-1 offset of one element: batches 2
    and up differ by 0.6 to 0.8 from the CPU's result (measured, `phase7/rope_offset_probe.txt`);
  - the array parameters of `random::normal` are not held to the sample's shape (read, then pinned by a guard);
  - `value_and_grad` returns the gradients sorted by position, whatever the order asked for (measured);
  - a save refused for its dtype has already emptied the file of that name (measured,
    `phase8/refused_save_probe.txt`).
- **Four families run on the CPU only, whatever the default device:** the multivariate normal (its root is an
  SVD), every file load ("[Load::eval_gpu] Not implemented"), and the distributed operations ("has no GPU
  implementation"). The wrappers build them on the CPU's default stream; a graph that crosses the two streams
  evaluates correctly.
- **float64 is thinner than the dtype suggests:** three samplers refuse it and two return float64 holding a
  float32 draw; the fused layers return float64 with float32 accuracy on the CPU; safetensors refuses it and
  GGUF has no float64 or int64.
- **A group of one hides most of a distributed wrapper.** MLX returns the operand of a collective without a
  node, so the peer's rank, the group handed on, the reversed shape of a receive and the stream of the node are
  invisible to the gate; the review found the wrong stream by reading. The two-process suite is written and was
  never run (10.6).
- **Which stream carries an operation cannot be tested through the public API** (it does not show in a result,
  and `mlx_stream_get_device` is internal): the stream tests prove lifetime, statuses and that work goes on.
- **Three holes in the static gate, each found by a planted violation that passed:** a stop written as the
  action of a one-line `if` in a callback (rule `cbstop`, Phase 6), a handle type without its finalizer (new rule
  `handle`, Phase 8), and, in the run's own tooling, a mutation runner that reused objects because restored
  files kept their times.
- **The independent review earned its place in every phase:** 49, 40, 3 and 52 assertions were added after it
  (and in Phases 7 and 8 most blind fixtures were replaced by discriminating ones), and four behaviours changed
  (the shape check of the array normal; the exporter's failed state and the custom vjp's count; the rope's
  offset check and the attention's scale; the stream of the distributed nodes).

### 10.2 What changed, phase by phase

| | Phase 5, random | Phase 6, transforms and export | Phase 7, fused layers | Phase 8, files, streams, distributed |
| --- | --- | --- | --- | --- |
| mlx-c functions made public | 19 | 16 | 6 | 34 |
| excluded | 0 | 0 | 1 (`mlx_fast_gated_delta_update`) | 0 |
| pending after | 57 | 41 | 34 | 0 |
| new modules | `mlxf_random` | `mlxf_transforms`, `mlxf_export` | (in `mlxf_fast`) | `mlxf_stream`, `mlxf_io`, `mlxf_distributed` |
| helper submodules of `mlxf_array` | `mlxf_array_random` (11 helpers) | (in `mlxf_compile`) | `mlxf_array_fast` (5) | `mlxf_array_io` (4), `mlxf_array_distributed` (3) |
| new types | `mlxf_random_spec` | `mlx_grad_function`, `mlx_function_exporter`, `mlx_imported_function`, `MLX_COMPILE_MODES` | `mlx_rope_spec`, `mlx_attention_spec` | `mlx_stream`, `mlx_group`, `mlxf_group_spec` |
| test area | `unit_random` (new) | `unit_transforms` (new: `transforms`, `export`) | `unit_fast` (new sub-suite `fast_layers`) | `unit_io`, `unit_distributed` (new); sub-suite `stream` of `unit_core` |
| checks, both devices / CPU / GPU | 486 / 244 / 242 | 274 / 147 / 129 | 58 / 34 / 25 | 846 / 446 / 400; 55 / 28 / 28; 33 / 25 / 25 |
| guards added (`object_contracts`) | 2 | 2 | 4 | 1 |
| mutations failing | 28 of 28, after a test was added for one that survived | 24 of 24 | 22 of 23, the other equivalent | 37 of 37, after a test was strengthened for one that survived |
| plants failing the static gate | 10 | 11 | 7 | 13 |
| policy sections | 13 | 14 | 15 | 16, 17, 18 |
| upstream question | | 29 | 30 | 31 |

Before Phase 5's first wrapper, ruling R6: 28 accumulations `x = max(x, abs(...))` in five testers became
`nan_max` or `nan_maxval`, two statements that were not error reductions were rewritten, and `NANMAX_LEDGER` is
empty; the areas' counts did not move (`r6/`).

Against the base, 31 files changed and 21 are new; none was renamed or deleted (`phase9_final/diff_base_repo.txt`).
Every file is under a row of the file table; the run added rows before the edits they cover (the five testers of
R6; the three helper submodules and `mlxf_array_evaluation.f90`; `CONTRIBUTING.md`, the quickstart and its
example; rules `cbstop` and `handle`; `scripts/check_tree.sh`).

The new public names, with their signatures, are in the four closing Progress entries under "The new public
names of the phase". In short: `mlx_random_seed`, `_key`, `_split`, `_bits`, `_uniform`, `_normal`, `_laplace`,
`_gumbel`, `_truncated_normal`, `_randint`, `_bernoulli`, `_multivariate_normal`, `_categorical`, `_permutation`;
`mlx_grad_function` and `mlx_value_and_grad`, `mlx_vjp`, `mlx_jvp`, `mlx_custom_vjp`, `mlx_custom_function`,
`mlx_checkpoint`, `mlx_depends`, `mlx_export_function`, `mlx_function_exporter`, `mlx_imported_function`,
`mlx_enable_compile`, `mlx_disable_compile`, `mlx_set_compile_mode`, `MLX_COMPILE_MODES`; `mlx_layer_norm`,
`mlx_rms_norm`, `mlx_rope`, `mlx_rope_spec`, `mlx_scaled_dot_product_attention`, `mlx_attention_spec`,
`mlx_cross_entropy`; `mlx_stream`, `mlx_new_stream`, `mlx_default_stream`, `mlx_set_default_stream`,
`mlx_synchronize(stream)`, `mlx_device_is_available`, `mlx_metal_start_capture`, `mlx_metal_stop_capture`,
`mlx_memory_limit`, `mlx_set_wired_limit`, `mlx_buffer_size`, `a%nbytes()`, `a%itemsize()`, `mlx_save`, `mlx_load`,
`mlx_save_safetensors`, `mlx_load_safetensors`, `mlx_save_gguf`, `mlx_load_gguf`, `mlx_print_graph`,
`mlx_export_to_dot`, `mlx_group`, `mlx_distributed_init`, `mlx_distributed_is_available`, `mlx_all_sum`,
`mlx_all_max`, `mlx_all_min`, `mlx_all_gather`, `mlx_sum_scatter`, `mlx_send`, `mlx_recv`, `mlx_recv_like`.

### 10.3 Decisions taken under delegation

Each is in the closing Progress entry of its phase, under "Decisions under delegation", with its reason. The
ones that shape the API:

1. *Phase 5.* A sampler takes its Fortran shape first and its key last; parameters keep mlx-c's types (arrays
   where C takes arrays, real32 where C takes `float`); `mlx_random_normal` is a generic of the scalar and the
   array form.
2. *Phase 5.* `mlx_random_split` is two subroutines under one name; `mlx_random_categorical` is one procedure
   with keywords for mlx-c's three functions; categories and `mlx_random_permutation(n)` are one-based;
   `mlx_random_randint` keeps MLX's range, `high` excluded.
3. *Phase 5.* The multivariate normal runs on the CPU's default stream; `cpu_stream` became a procedure of the
   `mlxf_array` family. An absent key is an empty handle read through `optional_handle`.
4. *Phase 5.* A quickstart row (D20) and its example block: a sample is a function of its key and shape.
5. *Phase 6.* `mlx_grad_function%apply` returns the gradients in the order of `argnums` (MLX sorts them);
   `argnums` defaults to the first input and a position below 1 stops.
6. *Phase 6.* `mlx_vjp` and `mlx_jvp` are subroutines of five dummies without `status`; `apply` is the checked
   route.
7. *Phase 6.* Custom rules are checked subroutines; mlx-c's `vmap` closure is passed null; derived functions
   share the callback's payload through two helpers of the compile module.
8. *Phase 6.* Export lives in `src/core/compile/mlxf_export.f90`, its tests in `unit_transforms`;
   `mlx_function_exporter` and `mlx_imported_function` have a checked `new` beside their constructors; an
   exporter refuses another application after a failed one.
9. *Phase 6.* Rule `cbstop` was tightened after a plant passed.
10. *Phase 7.* `mlx_fast_gated_delta_update` is excluded under decision 17 (its shapes are in no header, and the
    docstring disagrees with the code).
11. *Phase 7.* Features along dimension 1, positions along dimension 2; `eps` optional, 1e-5; two public
    records `mlx_rope_spec` and `mlx_attention_spec`; `mlx_rope` is one procedure for mlx-c's two; the
    attention's `sinks` are not offered; the mask mode is derived; a rank-1 offset whose extent is not the
    number of batches stops (MLX's GPU defect).
12. *Phase 8.* Every procedure of `mlxf_io` and `mlxf_distributed` takes `status`, beyond the signatures of
    decisions 15 and 18; the distributed helpers carry the procedure's name in `mlxf_group_spec`.
13. *Phase 8.* Loaded names and metadata come back sorted; metadata are a (2, n) character array; a name given
    twice is refused; loads and distributed nodes run on the CPU's default stream.
14. *Phase 8.* `mlx_synchronize` is a generic of two modules; the sizes live in the evaluation submodule and
    `mlx_buffer_size` evaluates first; `mlx_print_graph` without a file writes to a copy of the standard
    output's descriptor; an absent backend is `'any'`; ranks are one-based and a rank below 1 stops.
15. *Phase 8.* Streams and the runtime controls are tested as the sub-suite `stream` of `unit_core`; the
    two-process suite is the named-only `distributed_ring`; the new rule `handle`.
16. *All phases.* The independent review, the mutations and the plants were run before each closing entry, and
    their findings acted on inside the phase; tests added after a freeze changed no tolerance.

### 10.4 Deviations from the plan

- **Decisions 15 and 18 list signatures without `status`;** the wrappers of files and of distributed operations
  all take it (10.3, item 12).
- **Decision 12's `mlx_vjp` and `mlx_jvp` have no `status`** (rule `arity`); `mlx_value_and_grad` is a handle
  type with `apply`, not a function that returns a function.
- **One function left the ledger as excluded** in Phase 7, under decision 17, which reserves that choice.
- **Two rules of the static gate changed** (`cbstop` tightened, `handle` new) and `scripts/check_tree.sh` got a
  word in a comment: rows were added to the file table before each edit.
- **Phase 8's exit asks for the reported-not-gated commands in Progress:** they are there, and were not run.
- **The plan's Phase 5 is "FFTs and random";** its FFT half was delivered by Phase 10, so this run's Phase 5 is
  the random half. Likewise Phase 7's Metal kernel.
- **Expected and not found:** an accuracy finding in the transforms or the fused layers; a function to exclude
  under decision 22; a bound of R5 approached (the Release build is 0.75 s above its base against 6.57 s of
  room); a failure of an existing suite.
- **Found and not expected:** the three upstream defects of 10.1 that the wrappers now refuse; the stream of the
  distributed nodes; the two holes in the rules.
- **Files changed outside the table:** none.
- **Skill edits proposed, not applied** (four closing entries, "Proposed, not applied").

### 10.5 Evidence against the baseline

| | base (`base/`) | Phase 5 | Phase 6 | Phase 7 | Phase 8 | final (`phase9_final/`) | bound (R5) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Release clean build, s | 19.512, 19.553 | 19.746, 19.756 | 19.969, 19.916 | 20.140, 20.179 | 20.303, 20.270 | 20.267, 20.242 | 26.10 |
| fast gate, Release, s | 10.54, 10.54 | 10.44, 10.48 | 10.68, 10.69 | 10.64, 11.88 | 10.70, 10.77 | 10.70, 10.70 | 38.74 |
| new area in the Release gate, s | | `unit_random` 0.9 | `unit_transforms` 0.65 | | `unit_io` 0.25, `unit_distributed` 0.16 | random 1.00, transforms 0.74, io 0.25, distributed 0.16 | 3 |
| fast gate entries | 9 | 10 | 11 | 11 | 13 | 13 | at most 13 |
| warnings, Debug and Release | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| ledger pending | 76 | 57 | 41 | 34 | 0 | 0 | |
| `object_contracts` members | 21 | 23 | 25 | 29 | 30 | 30 | |
| release gate | | passes | passes | passes, 75 s | passes, 76 s | passes, 76 s | |

All times *measured*, each build and gate twice, serial, with the one-minute load at most 3.7 before and after;
the bound of the build is *derived* by R5 (the base's mean 19.533 s plus 7.04 s less 0.47 s). The Debug clean
build went from 7.56 s to 7.90 s.

Assertions per area, both devices / CPU / GPU, the same in Debug and Release (`phase9_final/areas_*.txt`):

| area | base | final |
| --- | --- | --- |
| `unit_core` | 181 to 183 / 156 or 157 / 156 or 157 | 215 or 216 / 181 or 182 / 181 or 182 |
| `unit_array` | 193 / 103 / 101 | 193 / 103 / 101 |
| `unit_ops` | 2,462 / 1,469 / 995 | 2,462 / 1,469 / 995 |
| `unit_linalg` | 632 / 397 / 239 | 632 / 397 / 239 |
| `unit_fft` | 194 / 101 / 94 | 194 / 101 / 94 |
| `unit_compile` | 63 / 32 / 32 | 63 / 32 / 32 |
| `unit_transforms` | | 274 / 147 / 129 |
| `unit_fast` | 94 / 13 / 82 | 152 / 47 / 107 |
| `unit_random` | | 486 / 244 / 242 |
| `unit_io` | | 846 / 446 / 400 |
| `unit_distributed` | | 55 / 28 / 28 |
| `unit_kernels` | 1,955 / 896 / 1,145 | 1,955 / 896 / 1,145 |

`unit_core` varies by two checks of its registry sub-suite that depend on the allocator's reuse of an address,
in the base as now; its gain is the sub-suite `stream`, 33 / 25 / 25. No existing assertion changed or left.

### 10.6 Left open for the maintainer

*Reported, not gated (written, never run).*

- **Two processes through MLX's ring backend:** the host file and the two commands are in the Progress entry of
  Phase 8; the suite is `test=unit_distributed suite=distributed_ring`. Homebrew's MLX 0.32.4 has the backend
  (`mlx_distributed_is_available('ring')` is true, measured). It is the only test of a peer's rank, of a group
  handed on, of `mlx_recv`'s shape and of the CPU stream of a distributed node.
- **A Metal capture opened in Xcode** (`MTL_CAPTURE_ENABLED=1`); the gate tests the refusal.

*Not verified by this run.*

- A CPU-only MLX and a session without a GPU: `mlx_synchronize()` and the stream constructors were written for
  them from MLX's source and not run there (the CI's CPU job would run the first).
- Which stream carries an operation (10.1).
- An export on one device imported on the other; grouped heads of the attention; a batched covariance of the
  multivariate normal; complex64 samples; that `mlx_depends` evaluates its dependencies; the three tracing
  compile modes told apart.

*For a ruling or a read.*

- **The API of four phases was not read at a hold.** The names and signatures are listed in the closing Progress
  entries for that read; the ones most likely to be questioned: `status` on every file and distributed
  procedure; `mlx_grad_function` as a type; the records `mlx_rope_spec` and `mlx_attention_spec` in `mlxf_defs`;
  names sorted on load; `mlx_random_randint`'s excluded `high`.
- **`mlx_fast_gated_delta_update` excluded and the attention's `sinks` not offered** (decision 17 and its
  precedent): say so if either is wanted.
- **A query of a stream's device** would make streams testable; it needs a ledger line moved from internal to
  public.
- **Rules `cbstop` and `handle`, and four names in `LIBC_NAMES`,** are changes of the gate for review.
- **Questions 29, 30 and 31 for Apple** are written and not sent.
- **The skill edits** proposed in the four closing entries.
- **The plan's place and the roadmap:** the plan is still under `planned/`, and `mlxf_roadmap.md` (rank 3) and
  `doc/implementation_notes/README.md` still describe parity as it was after Phase 3; neither is in the run's
  file table, so they were not edited.

### 10.7 A commit message

```
Parity Phases 5 to 9: random numbers, transforms, fused layers, files, streams, distributed

75 mlx-c functions get public Fortran wrappers and one is excluded; the parity ledger has no pending line
(399 public, 90 plumbing, 101 internal, 90 excluded).

- Random (new module mlxf_random): keys (mlx_random_seed, _key, _split) and the samplers _bits, _uniform, _normal,
  _laplace, _gumbel, _truncated_normal, _randint, _bernoulli, _multivariate_normal, _categorical, _permutation;
  shape first, key last, one-based categories and permutations.
- Transforms (new modules mlxf_transforms, mlxf_export): mlx_grad_function and mlx_value_and_grad, mlx_vjp, mlx_jvp,
  mlx_custom_vjp, mlx_custom_function, mlx_checkpoint, mlx_depends; mlx_export_function, mlx_function_exporter,
  mlx_imported_function; mlx_enable_compile, mlx_disable_compile, mlx_set_compile_mode with MLX_COMPILE_MODES.
- Fused layers (mlxf_fast): mlx_layer_norm, mlx_rms_norm, mlx_rope with mlx_rope_spec,
  mlx_scaled_dot_product_attention with mlx_attention_spec, mlx_cross_entropy. mlx_fast_gated_delta_update is
  excluded (its shapes are in no header).
- Streams and runtime (new module mlxf_stream): mlx_stream, mlx_new_stream, mlx_default_stream,
  mlx_set_default_stream, mlx_synchronize(stream); mlx_device_is_available, mlx_metal_start_capture and
  _stop_capture, mlx_memory_limit, mlx_set_wired_limit, mlx_buffer_size, a%nbytes(), a%itemsize().
- Files (new module mlxf_io): mlx_save and mlx_load (.npy), mlx_save_safetensors and mlx_load_safetensors,
  mlx_save_gguf and mlx_load_gguf, mlx_print_graph, mlx_export_to_dot. On disk a Fortran (m, n) array is NumPy's
  C-order (n, m); loads run on the CPU's stream.
- Distributed (new module mlxf_distributed): mlx_group, mlx_distributed_init, mlx_distributed_is_available,
  mlx_all_sum, mlx_all_max, mlx_all_min, mlx_all_gather, mlx_sum_scatter, mlx_send, mlx_recv, mlx_recv_like;
  one-based ranks; tested on the group of one process, a two-process suite by name only.
- Tests: new areas unit_random, unit_transforms, unit_io and unit_distributed, sub-suites fast_layers and stream;
  nine guards; the fast gate has 13 entries. The thirty scalar max reductions of five testers are NaN-safe and
  NANMAX_LEDGER is empty.
- Rules: cbstop also reads a stop that is the action of a one-line if; new rule handle (every handle type has a
  finalizer and a defined assignment); HANDLE_TYPES, ENTRY_IF_LIVE, ENTRY_HELPERS, CALLBACKS, LIBC_NAMES extended.
- Policy sections 13 to 18, README, CONTRIBUTING, the quickstart's row D20, questions 29 to 31 for Apple.

New files:
  src/core/array/mlxf_array_random.f90
  src/core/array/mlxf_array_fast.f90
  src/core/array/mlxf_array_io.f90
  src/core/array/mlxf_array_distributed.f90
  src/core/random/mlxf_random.f90
  src/core/random/mlxf_random_tester.f90
  src/core/random/random.inf
  src/core/transforms/mlxf_transforms.f90
  src/core/transforms/mlxf_transforms_tester.f90
  src/core/transforms/transforms.inf
  src/core/compile/mlxf_export.f90
  src/core/compile/mlxf_export_tester.f90
  src/core/fast/mlxf_fast_layers_tester.f90
  src/core/runtime/mlxf_stream.f90
  src/core/runtime/mlxf_stream_tester.f90
  src/core/io/mlxf_io.f90
  src/core/io/mlxf_io_tester.f90
  src/core/io/io.inf
  src/core/distributed/mlxf_distributed.f90
  src/core/distributed/mlxf_distributed_tester.f90
  src/core/distributed/distributed.inf

Release clean build 20.3 s (base 19.5 s, bound 26.1 s); fast gate 10.7 s (bound 38.7 s).
```

### 10.8 The ledger: final counts and every exclusion

`scripts/mlxc_parity.txt`, 680 lines (*exact*):

| class | at the run's base | final |
| --- | --- | --- |
| public | 324 | 399 |
| plumbing (called by the library, no name of its own) | 59 | 90 |
| internal (not called; reachable through a public name or not needed) | 132 | 101 |
| excluded | 89 | 90 |
| pending | 76 | 0 |

The 90 excluded lines, by the reason each carries in the ledger:

| lines | reason |
| --- | --- |
| 14 | CUDA: out of scope (Apple silicon only) |
| 12 | IO through reader/writer vtables: the generator skips `mlx_io_vtable` |
| 9 | keyword-argument closures: Fortran has no keyword dictionaries |
| 9 | GGUF metadata: typed maps with no Fortran counterpart |
| 8 | unsigned scalars: no standard Fortran type (device-only dtypes) |
| 8 | decision 2: quantised and fp8 inference formats, no Fortran data type |
| 6 + 2 | vmap: excluded with `mlx_detail_vmap`; mlx-c 0.8.0 exposes it only as `detail_` |
| 6 | one submitting thread: thread-local and thread-unsafe streams excluded |
| 4 | float16/bfloat16 scalars: no standard Fortran type (device-only dtypes) |
| 4 | `detail_`: internal API of mlx-c |
| 2 | stream registry management: one default stream per device is offered |
| 2 | custom distributed backends: not offered |
| 2 | build configuration, not API (the metallib path setters) |
| 1 | the `_payload` form serves `mlx_alloc`: its deleter tells a failed call whether MLX freed the buffer |
| 1 | decision 17: `mlx_fast_gated_delta_update`, whose shapes are not in MLX's header (this run) |

### 10.9 The upstream questions

`doc/collaboration/apple_questions.md`, all open, none sent. Those the parity plan's wrappers met:

| | question | from |
| --- | --- | --- |
| 19 | FFT length defaults in mlx-c and the Python `irfft` documentation | the earlier phases (sections 1 to 9) |
| 20 | float32 `expm1` on the GPU loses accuracy as its argument grows | the earlier phases |
| 21 | mlx-c's Metal kernel cannot choose the math mode | the earlier phases |
| 22 | `segmented_mm` does not check that the inner extents agree | the earlier phases |
| 23 | a transposed convolution with a padding above `dilation*(k-1)` returns a shorter result | Phase 4 |
| 24 | float64 convolutions and the float64 Hadamard transform do not evaluate | Phase 4 |
| 29 | an exporter read unchecked after a failed trace; the count of a custom vjp; empty lists | Phase 6, this run |
| 30 | RoPE's GPU kernel and a rank-1 offset of one element; the docstring of `gated_delta_update` | Phase 7, this run |
| 31 | a refused save empties the file; loads and distributed operations on a GPU stream; the end code of mlx-c's map iterators | Phase 8, this run |

### 10.10 The frozen tolerances of these phases

All in `src/test/mlxf_test_defs.f90`, frozen in sub-phase a on seed 1 on both devices as `max(2 x observed, 4
epsilons)` and judged in sub-phase b on seeds 2 and 3; none was changed after its freeze.

| family | constant | value | largest observed |
| --- | --- | --- | --- |
| samplers (moments, frequencies) | `RANDOM_SIGMAS`, `RANDOM_NSAMPLES` | 5 sigmas at 2^20 samples (section 6's) | z = 2.41 on seed 1, 2.84 on seeds 2 and 3 |
| `mlx_value_and_grad`, `mlx_vjp`, `mlx_jvp` | `GRAD_TOLERANCES(3)` | 4 eps32, 4 eps64: the floor | below the floor |
| `mlx_layer_norm`, `mlx_rms_norm`, `mlx_rope`, the attention (graph and fused kernel), `mlx_cross_entropy` | `FAST_TOLERANCES(6)` | 4 eps32 in both columns: the floor (float64 operands have float32 accuracy) | 1.96 eps32 (`mlx_layer_norm`, CPU), 1.62 (`mlx_rope`, GPU) |
| files, streams, distributed | none | exact comparisons (bytes, integers, statuses) | |

Upstream-defect lines among the tolerances: 0.
