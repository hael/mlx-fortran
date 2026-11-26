# How to replace a BLAS or LAPACK call with mlx-fortran

SIMPLE calls BLAS and LAPACK directly. This table gives, for each routine SIMPLE calls, the `mlxf` call that does
the same in the Fortran view, what that view does with the transposes, what MLX cannot do, and the test that
checks the wrapper. Below it is the measured crossover: the sizes at which MLX's matrix product beats the
system's BLAS on the M5 Ultra.

`mlx-fortran` has no wrapper under BLAS's names. Whether a BLAS-shaped `mlx_gemm` (alpha, beta and the
transpose flags in one call) should enter the library is the maintainer's decision, to be made from this note.

## What MLX cannot do

- **No float64 on the GPU.** MLX's Metal backend has no float64, and the library refuses float64 work on the
  GPU (guard `guard_float64_on_gpu` of `mlxf_test_exec expect_aborts object_contracts`). The `d` and `z`
  routines map onto MLX's CPU device only. A probe of this run
  (`scratch/keep/phase6/f64_probe/`, *measured*) ran `mlx_inv`, `mlx_eigvalsh`, `mlx_svd`, `mlx_lu_factor`,
  `matmul`, `mlx_inner` and `norm2` on float64 on the CPU device, each within a few ulps of Fortran in double
  precision. No unit test of the library covers float64 linear algebra.
- **No LAPACK on the GPU.** MLX computes every factorisation (inverse, LU, Cholesky, QR, SVD, eigenvalues,
  solves) on the CPU, so `mlxf_linalg_matrix` runs them on the CPU's default stream whatever the default
  device (the module's header). Moving a LAPACK call into MLX therefore gains a place in a graph, not a device.
- **No in-place update.** MLX's arrays are immutable: `beta*C` in `gemm` and `y` in `axpy` produce a new array.
  The handle assignment `y = ...` replaces the old node, and nothing is copied until evaluation.

## The table

The call sites are SIMPLE's at `28c753993` (*measured* by `git grep` on `call <routine>` and on `ddot(` and
`dnrm2(`, one per call statement, under `src/`). `a`, `b`, `c`, `x`, `y` are `type(mlx_array)` holding the
Fortran arrays of the BLAS call (`mlx_from`), and the result comes back with `mlx_to`. A transposed operand is
`transpose(a)` (Fortran dimensions 1 and 2 exchanged, a view that MLX does not copy) and a conjugated one is
`conjg(a)`.

| Routine (call sites) | `mlxf` call | Transposes and the Fortran view | Checked by |
| --- | --- | --- | --- |
| `sgemm` (11) | `c = matmul(a, b)` (alpha 1, beta 0); otherwise `c = mlx_addmm(c, a, b, alpha=, beta=)` | `'T'` is `transpose(a)` or `transpose(b)`; the leading dimensions vanish: pass the section (`a(1:m, 1:k)`), which `mlx_from` copies contiguously | `matmul`: `mlxf_linalg.f90`, `matmul_array` (operands exchanged for MLX's row-major view); test `test_matmul` (`mlxf_linalg_tester`: operand order, batches) and `test_product_conventions` (`mlxf_linalg_mm_tester`). `mlx_addmm`: `test_addmm` (`mlxf_linalg_products_tester`: both factors, the defaults, `c` broadcast, a batch). `transpose`: `test_reordering` (`mlxf_ops_shape_tester`: "transpose of a matrix is Fortran's"). No test composes the two; the BLAS bench does, against `cblas_cgemm('C', 'N')` (below) |
| `cgemm` (3) | `c = matmul(conjg(transpose(a)), b)` for `('C', 'N')`; `mlx_addmm` for a real alpha and beta, or `alpha*matmul(...) + beta*c` for complex ones | `'C'` is `conjg(transpose(a))`, `'T'` is `transpose(a)`; a batch of products (SIMPLE's `do j` loop over the rotations) is one `matmul` of rank-3 arrays, batched over dimension 3 | as `sgemm`; `test_complex_products` (`mlxf_linalg_products_tester`) for complex operands. The polar block product of the bench equals `cblas_cgemm('C', 'N')` to a relative 5.3e-7 on the GPU and 4.1e-7 on the CPU (*measured*) |
| `sgemv` (1), `dgemv` (2) | `y = matmul(a, x)`, or `mlx_addmm(y, a, x, alpha=, beta=)`; `'T'` is `matmul(x, a)` | a rank-1 operand is a row on the left and a column on the right, as in Fortran's `matmul` | `mlx_addmm`'s header; `test_addmm` (a vector as `a`, a row, and as `b`, a column). `dgemv`: CPU device only (float64) |
| `ssyrk` (1) | `c = mlx_addmm(c, a, transpose(a), alpha=, beta=)` (`'N'`), or with `transpose(a)` first (`'T'`) | MLX computes the full matrix; `ssyrk` writes one triangle, so read the triangle `uplo` names | as `sgemm` |
| `ddot` (14) | `d = mlx_inner(x, y)` (a rank-0 array) | none | `mlx_inner`: `mlxf_linalg.f90` (sums over dimension 1, no conjugation); `test_inner`, `test_complex_products` ("mlx_inner does not conjugate"). CPU device only (float64) |
| `cdotc_sub` (1) | `d = mlx_vecdot(x, y)` | `mlx_vecdot` conjugates its first operand, as Fortran's `dot_product` and `cdotc` | `test_complex_products` ("mlx_vecdot conjugates its first operand: Fortran's dot_product"), `test_vecdot` |
| `dnrm2` (3) | `n = norm2(x)` | none | `norm2_dim`/`norm2_dims` (`mlxf_linalg_matrix.f90`, "as Fortran's norm2"); `test_norms`. CPU device only (float64) |
| `daxpy` (6) | `y = y + alpha*x` | none; `alpha` is a weak scalar and takes the array's kind | the operators of `mlx_array` (`mlxf_array_elementwise`); `test_weak_scalars` (`mlxf_ops_math_tester`). CPU device only (float64) |
| `dscal` (3) | `x = alpha*x` | as `daxpy` | as `daxpy` |
| `dcopy` (19) | `y = x` (the handle: shared, nothing copied) or `y = mlx_copy(x)` (a new node) | strides (`incx`) are a section of the Fortran array before `mlx_from` | the defined assignment (`mlxf_array_lifetime`, the registry tests); `mlx_copy`: `mlxf_ops_math`. A copy between host arrays stays Fortran's `y = x`: MLX gains nothing there |
| `ssyev` (2), `dsyev` (2) | `call mlx_eigh(a, w, v, uplo=)`, or `w = mlx_eigvalsh(a, uplo=)` for the values alone | `uplo` names the triangle read, as LAPACK's; the eigenvectors are the columns of `v`, ascending eigenvalues as LAPACK | `mlx_eigh`: `mlxf_linalg_matrix.f90`; `test_eigh`, `test_eigh_complex`. CPU stream always; `dsyev` float64 by the probe |
| `sgesvd` (2), `dgesvd` (2) | `call mlx_svd(a, u, s, vt)`, or `call mlx_svd(a, s)` for the values | `u` (m, m) and `vt` (n, n), the full factors (LAPACK's `jobu = jobvt = 'A'`); a thin SVD is a section of them | `svd_factors`/`svd_values`; `test_svd`, `test_svd_complex`. CPU stream always |
| `sgetrf` (1), `dgetrf` (1) | `call mlx_lu_factor(a, lu, pivots)` | packed as LAPACK packs it; `pivots` 1-based int32, row `i` exchanged with row `pivots(i)` in turn | `mlx_lu_factor`'s header; `test_lu_factor`. CPU stream always |
| `sgetri` (2), `dgetri` (2) | `ainv = mlx_inv(a)` (from `a`, not from its LU factors) | the inverse of the transpose is the transpose of the inverse: no transpose in the graph | `mlx_inv`; `test_inv`. CPU stream always |

## The crossover

`mlxf_test_exec test=bench_blas suite=crossover` (`src/test/bench/mlxf_bench_blas.f90`, run by hand, never in
CTest) times square products n = 32 to 4,096 in float32 (`sgemm`) and complex64 (`cgemm`), and SIMPLE's polar
block product (`simple_polarft_block`: `cgemm('C', 'N', 16, 32, 2nk)` repeated over the pftsz + 1 rotations; 2nk =
122 and 183 rotations at the M5 cases' geometry), on the host through the system's CBLAS (Accelerate) and through
`matmul` on MLX's CPU and GPU devices: with the data starting and ending in Fortran arrays (`transfer`:
`mlx_from`, the product, `mlx_to`) and without (`resident`: the operands evaluated on the device beforehand,
the product evaluated). Best of three after a warm-up; one process. Rows go to `./bench_blas.tsv`.

Measured on the M5 Ultra (macOS, 30 cores), 2026-11-26, one-minute load 3.65 before and 3.31 after, run
`mlxf_refactor` Phase 6 (*measured*, one run; logs in `scratch/keep/phase6/bench/`):

| Product | First n at which MLX beats Accelerate: CPU device, resident / transfer | GPU device, resident / transfer |
| --- | --- | --- |
| `sgemm` | 2,048 / none up to 4,096 | 1,024 / 2,048 |
| `cgemm` | 256 / 256 | 512 / 512 |

At n = 4,096 the GPU's `sgemm` takes 7.0 ms resident and 8.8 ms with transfer against Accelerate's 27.1 ms
(19.6 and 15.6 TFLOP/s against 5.1); its `cgemm` 52.6 and 57.4 ms against 131.5 ms. Below n = 512 every MLX
product on the GPU costs about 0.15 ms whatever its size, the price of one evaluation on the device. The
polar block product (183 products of 16 x 32 x 122) takes 1.16 ms as SIMPLE's loop of 183 `cgemm` calls, and
0.22 ms (resident) or 0.30 ms (transfer) as one batched `matmul` on the GPU: 5.3 and 3.9 times faster; on
MLX's CPU device 3.7 and 2.6 times. MLX's results differ from Accelerate's by a relative 6e-6 at most (complex,
n = 4,096).

What the numbers say: a single float32 product needs n above 1,000 to 2,000 before the GPU pays, more than
SIMPLE's call sites reach, while a batch of small products (SIMPLE's polar block) gains at once, because MLX
does the batch in one call. A product gains from MLX when it is part of a larger graph on the device or when it
is batched, not as a drop-in replacement of one `gemm`. The comparison is of one process: SIMPLE runs its
blocks on an OpenMP team, which the bench does not.
