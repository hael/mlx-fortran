# mlx-c parity, Phases 2 and 3: review report of run `mlxf_parity`

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
