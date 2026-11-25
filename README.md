# mlx-fortran

A modern Fortran interface to [MLX](https://github.com/ml-explore/mlx), Apple's array framework for the
unified CPU/GPU memory of Apple silicon, built on MLX's C API
[mlx-c](https://github.com/ml-explore/mlx-c).

**Status: milestone 1 closed; the library is growing toward parity with mlx-c.** The whole of mlx-c 0.8.0 is
bound at the C level, generated at build time
and checked against an independent list of its 680 functions. That check is name coverage, not ABI
verification: an interface is proven against the C library only where a test calls it. On top of it, the Fortran layer has the
`mlx_array` type and its lifetime, data movement, evaluation and errors, plus the first operations: elementwise
arithmetic and comparisons, shape and indexing operations, reductions and scans, batched `matmul`, 1D and 2D
FFTs, and graph compilation of Fortran callbacks. That set covers the first SIMPLE-shaped pipeline (scoring
and shift maps of the polar table), measured on the M2 and M5 Ultra
([report](doc/implementation_notes/completed/mlxf_milestone1_report.md)); its test-only model is a miniature of
SIMPLE's `polarft_calc` with the table driver `eul_prob_tab`
([report](doc/implementation_notes/completed/mlxf_toy_architecture_report.md)). The API is still growing, so expect
it to change. The work to come is ranked in the
[roadmap](doc/implementation_notes/planned/mlxf_roadmap.md).
See the [implementation-notes index](doc/implementation_notes/README.md) for active work and completed records.

## What it is for

MLX builds lazy graphs of array operations and runs them on the CPU or the GPU of an Apple-silicon Mac
without copying data between the two. mlx-fortran expresses that model in Fortran's own terms:
column-major arrays, 1-based dimensions and indices, `matmul`, `sum` and `exp` that work on device arrays,
and handles whose lifetime the compiler manages. It is developed first for
[SIMPLE](https://github.com/hael/SIMPLE), the cryo-EM package, and its first kernels are SIMPLE's, but it
does not depend on SIMPLE.

```fortran
use mlxf, only: mlx_array, mlx_from, mlx_to_alloc, matmul, exp
type(mlx_array) :: a, b, c
real, allocatable :: x(:,:), y(:,:), z(:,:)
! ... fill x(m,k) and y(k,n)
a = mlx_from(x)              ! an MLX array holding a copy of the Fortran (m,k) array
b = mlx_from(y)
c = exp(-matmul(a, b))       ! a lazy graph on the default device (the GPU)
call mlx_to_alloc(z, c)      ! evaluates, allocates z(m,n) and copies
```

## The Fortran view

- **Memory order and indices.** Shapes, dimensions, indices and positions are Fortran's: column-major and
  1-based. Translating to MLX's row-major, 0-based world is the library's job, never the user's.
- **Lifetime.** `type(mlx_array)` holds a counted MLX handle. Assignment adds a reference and finalization
  releases it. A few expression forms that gfortran fails to finalize are listed as unsupported, with
  reproducers in [`doc/compiler_issues/`](doc/compiler_issues/). `mlx_live_count()` reports handles still
  alive.
- **Evaluation.** Operations build a graph; `mlx_eval`, `mlx_async_eval`, `mlx_to`, `mlx_to_alloc` and
  `mlx_view` run it. `mlx_alloc` and `mlx_view` share memory with Fortran without a copy.
- **Borrowing.** `mlx_view(w, p)` points `p` at the storage of a named `mlx_array` `w`, valid while `w` is
  unchanged. Never view an expression (`mlx_view(exp(a), p)`): its result dies at the end of the statement
  and `p` dangles. Assign it first: `w = exp(a)`, then `call mlx_view(w, p)`.
- **One thread, one error handler.** Build and evaluate graphs from one thread; a library call inside an
  OpenMP parallel region stops. At its first call the library installs a process-wide mlx-c error handler
  that records MLX's messages; a program that installs its own handler takes those errors from the library.
- **Errors.** An error MLX reports while a graph is built is a program error and stops with
  `error stop 86`. The procedures that run a graph or move data take an optional `status`, and
  `mlx_last_error()` has MLX's message. MLX's exceptions never cross into Fortran.
- **Kinds and devices.** Transfers take `real32`, `real64`, `complex64`, `int32` and `int64`. The default
  device is the GPU (`MLX_DEVICES%gpu`); float64 runs only on the CPU, as in MLX.

The full contract is [`doc/policies/binding_contract_policy.md`](doc/policies/binding_contract_policy.md).

## What is in `mlxf`

| area | names |
| --- | --- |
| arrays | `mlx_array`, `mlx_from`, `mlx_to`, `mlx_to_alloc`, `mlx_item`, `mlx_view`, `mlx_alloc`, `mlx_is_live`, `mlx_astype`, `mlx_copy`, `mlx_zeros`, `mlx_ones`, `mlx_full`, `mlx_zeros_like`, `mlx_ones_like`, `mlx_full_like`, `mlx_arange`, `mlx_linspace`, `mlx_identity`, `mlx_eye`, `mlx_tri`, `mlx_meshgrid`, `mlx_bartlett`, `mlx_blackman`, `mlx_hamming`, `mlx_hanning` |
| evaluation | `mlx_eval`, `mlx_async_eval`, `mlx_synchronize` |
| operators | `+ - * / **`, `< <= > >= == /=`, `.and. .or. .not. .eqv. .neqv.` on arrays and scalars |
| elementwise | `abs`, `exp`, `sqrt`, `log`, `log10`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `erf`, `floor`, `ceiling`, `aint`, `modulo`, `min`, `max`, `merge`, `real`, `aimag`, `conjg`, `cmplx`, `mlx_round`, `mlx_sign`, `mlx_sigmoid`, `mlx_square`, `mlx_reciprocal`, `mlx_rsqrt`, `mlx_expm1`, `mlx_log1p`, `mlx_log2`, `mlx_erfinv`, `mlx_degrees`, `mlx_radians`, `mlx_logaddexp`, `mlx_floor_divide`, `mlx_divmod`, `mlx_clip`, `mlx_nan_to_num`, `mlx_stop_gradient` |
| tests and predicates | `mlx_isnan`, `mlx_isinf`, `mlx_isfinite`, `mlx_isposinf`, `mlx_isneginf`, `mlx_isclose`, `mlx_allclose`, `mlx_array_equal` |
| integers and bits | `iand`, `ior`, `ieor`, `not`, `shiftl`, `mlx_right_shift` (arithmetic) |
| shape and indexing | `reshape`, `transpose`, `mlx_permute`, `mlx_movedim`, `mlx_swapdims`, `mlx_squeeze`, `mlx_expand_dims`, `mlx_flatten`, `mlx_unflatten`, `mlx_atleast_1d`, `mlx_atleast_2d`, `mlx_atleast_3d`, `mlx_broadcast_to`, `mlx_broadcast_arrays`, `mlx_tile`, `mlx_repeat`, `mlx_pad`, `mlx_flip`, `cshift`, `mlx_concatenate`, `mlx_stack`, `mlx_unstack`, `mlx_split`, `mlx_slice`, `mlx_slice_update` (and `_add`, `_max`, `_min`, `_prod`), `mlx_take_along_dim`, `mlx_put_along_dim`, `mlx_take`, `mlx_gather`, `mlx_scatter` (and `_add`, `_max`, `_min`, `_prod`), `mlx_masked_scatter`, `mlx_searchsorted`, `mlx_unique`, `mlx_as_strided`, `mlx_bitcast`, `mlx_number_of_elements` |
| matrices | `mlx_diag`, `mlx_diagonal`, `mlx_trace`, `mlx_tril`, `mlx_triu` (diagonal k > 0 above the main diagonal of the Fortran matrix) |
| reductions | `sum`, `product`, `maxval`, `minval`, `all`, `any`, `count`, `maxloc`, `minloc`, `mlx_mean`, `mlx_median`, `mlx_var`, `mlx_std`, `mlx_logsumexp` (one dimension, a list or all; `keepdims`), `mlx_softmax` (`maxloc` and `minloc`: one dimension, or the whole array's subscripts) |
| scans and sorting | `mlx_cumsum`, `mlx_cumprod`, `mlx_cummax`, `mlx_cummin`, `mlx_logcumsumexp`, `mlx_diff`, `mlx_sort`, `mlx_argsort`, `mlx_partition`, `mlx_argpartition`, `mlx_topk` |
| linear algebra | `matmul` (batched) |
| Fourier transforms | `mlx_fft`, `mlx_ifft`, `mlx_rfft`, `mlx_irfft`, `mlx_fft2`, `mlx_ifft2`, `MLX_FFT_NORMS` |
| compilation | `mlx_function` (from a Fortran callback), `mlx_compile` |
| devices and memory | `mlx_device_count`, `mlx_default_device`, `mlx_set_default_device`, `mlx_device_info_*`, `mlx_active_memory`, `mlx_peak_memory`, `mlx_reset_peak_memory`, `mlx_cache_memory`, `mlx_clear_cache`, `mlx_set_memory_limit`, `mlx_set_cache_limit` |
| runtime | `mlx_last_error`, `mlx_live_count`, `mlx_runtime_version`, `mlxf_version_string`, `mlxf_build_description`, `mlxf_runtime_description`, `MLX_DTYPES`, `MLX_DEVICES`, `MLXF_HARD_ERROR_STATUS` |

Fortran intrinsics that the library extends (`matmul`, `sum`, `exp`, ...) keep their names. Everything that
is MLX-specific is `mlx_<x>`.

## Building

Requirements: macOS on Apple silicon, CMake 3.25+, GFortran 14+ (`brew install gcc cmake`), and mlx-c as a
shared library, either `brew install mlx-c` (no Xcode needed) or the pinned source build
`scripts/build_mlx_deps.sh` (MLX v0.32.4 and mlx-c v0.8.0 from local clones; needs Xcode's Metal toolchain).

```bash
./compile_clean.sh                        # Release build, static and fast test gates, install into build/
./compile_debug.sh                        # the same in Debug
./recompile.sh                            # incremental
build/bin/mlxf_test_exec test=unit_core   # one area: core, array, ops, linalg, fft, compile, kernels
```

Both builds treat warnings as errors in CI (`-DMLXF_WERROR=ON`). Only `mlxf.mod` and the library are
installed. [`doc/how2s/how2set_up_dev.md`](doc/how2s/how2set_up_dev.md) has the details.

By default (`FORTLS=ON`) a build also installs the Fortran language server fortls (pip, into the build tree)
and registers its Claude Code plugin for this checkout; offline it only warns. Downstream and offline builds
can pass `-DFORTLS=OFF`.

The CI on GitHub's macOS runners builds both configurations and runs the source checks, but the runners have
no Metal device, so the device tests skip there. A release needs `scripts/release_gate.sh` on an Apple-silicon
Mac with a GPU: Debug and Release from scratch with `MLXF_REQUIRE_GPU=ON`, the fast gate on each, and a
failure on any skip; its log names the commit, the toolchain, MLX and the device.

## Layout

| path | what |
| --- | --- |
| `src/defs/` | `mlxf_defs`: constants and vocabularies more than one module uses |
| `src/core/` | the Fortran layer, by capability: `runtime/`, `array/`, `ops/`, `linalg/`, `fft/`, `compile/`; `mlxf.f90` is the user module |
| `src/test/` | test infrastructure, the toys that mirror SIMPLE's classes (`polarft_calc`, `eul_prob_tab`) and their benchmark, built only with tests |
| `test/` | `mlxf_test_exec`, the one test executable, and the CTest entries |
| `scripts/` | the static gate, the formatters, the compile helpers, the dependency build, the C-layer generator |
| `build/gen/` | generated at build time: the `bind(c)` layer from the mlx-c headers that are linked |
| `doc/` | the binding contract and other policies, plans, history, how-tos, compiler issues, questions for the MLX team |

## License

MIT, as MLX and mlx-c. See [`LICENSE`](LICENSE).
