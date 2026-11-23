# mlx-fortran

A modern Fortran interface to [MLX](https://github.com/ml-explore/mlx), Apple's array framework for the
unified CPU/GPU memory of Apple silicon, built on MLX's C API
[mlx-c](https://github.com/ml-explore/mlx-c).

**Status: milestone 1, early.** The whole of mlx-c 0.8.0 is bound at the C level, generated at build time
and checked against an independent list of its 680 functions. On top of it, the Fortran layer has the
`mlx_array` type and its lifetime, data movement, evaluation and errors, plus the first operations: elementwise
arithmetic and comparisons, shape and indexing operations, reductions and scans, batched `matmul`, 1D and 2D
FFTs, and graph compilation of Fortran callbacks. That set covers the first SIMPLE pipeline (scoring and shift
maps of the polar table), which is measured on the M2 Ultra and goes to the M5 Ultra next. The API grows with
demonstrated need, so expect it to change. The plan in progress is
[`doc/implementation_notes/planned/mlxf_milestone1.md`](doc/implementation_notes/planned/mlxf_milestone1.md).

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
- **Errors.** An error MLX reports while a graph is built is a program error and stops with
  `error stop 86`. The procedures that run a graph or move data take an optional `status`, and
  `mlx_last_error()` has MLX's message. MLX's exceptions never cross into Fortran.
- **Kinds and devices.** Transfers take `real32`, `real64`, `complex64`, `int32` and `int64`. The default
  device is the GPU (`MLX_DEVICES%gpu`); float64 runs only on the CPU, as in MLX.

The full contract is [`doc/policies/binding_contract_policy.md`](doc/policies/binding_contract_policy.md).

## What is in `mlxf`

| area | names |
| --- | --- |
| arrays | `mlx_array`, `mlx_from`, `mlx_to`, `mlx_to_alloc`, `mlx_view`, `mlx_alloc`, `mlx_is_live`, `mlx_astype`, `mlx_zeros`, `mlx_arange` |
| evaluation | `mlx_eval`, `mlx_async_eval`, `mlx_synchronize` |
| operators | `+ - * /`, `< <= > >= == /=`, `.and. .or. .not.` on arrays and scalars |
| elementwise | `exp`, `sqrt`, `real`, `aimag`, `conjg`, `cmplx`, `max`, `merge` |
| shape and indexing | `reshape`, `transpose`, `mlx_permute`, `mlx_concatenate`, `mlx_slice`, `mlx_take_along_dim`, `mlx_take`, `mlx_bitcast` |
| reductions and scans | `sum`, `minval`, `minloc`, `mlx_logsumexp`, `mlx_cumsum` |
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

## Layout

| path | what |
| --- | --- |
| `src/defs/` | `mlxf_defs`: constants and vocabularies more than one module uses |
| `src/core/` | the Fortran layer, by capability: `runtime/`, `array/`, `ops/`, `linalg/`, `fft/`, `compile/`; `mlxf.f90` is the user module |
| `src/test/` | test infrastructure and SIMPLE-shaped kernels and benchmarks, built only with tests |
| `test/` | `mlxf_test_exec`, the one test executable, and the CTest entries |
| `scripts/` | the static gate, the formatters, the compile helpers, the dependency build, the C-layer generator |
| `build/gen/` | generated at build time: the `bind(c)` layer from the mlx-c headers that are linked |
| `doc/` | the binding contract and other policies, plans, history, how-tos, compiler issues, questions for the MLX team |

## License

MIT, as MLX and mlx-c. See [`LICENSE`](LICENSE).
