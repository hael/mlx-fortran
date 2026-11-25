# mlx-c parity, Phases 2 and 3: review report of run `mlxf_parity`

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
