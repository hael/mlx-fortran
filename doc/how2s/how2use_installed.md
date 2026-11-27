# Use the installed library

The guide for any Fortran program that uses mlx-fortran from its installed package. It says what the library
needs, how a project links it, and the few rules a program must keep: precision and devices, errors, ownership,
threads and costs. Every name has its entry in the generated [API reference](../api_reference.md); the full
contract is the [binding policy](../policies/binding_contract_policy.md); the first program is in the
[README](../../README.md) and the differences from plain Fortran in the [quickstart](../quickstart.md). The
SIMPLE-specific integration notes stay in [how2use_from_simple.md](how2use_from_simple.md).

## What it needs

| | supported | not supported |
| --- | --- | --- |
| compiler | GNU Fortran 14 or newer; a consumer uses **the exact compiler version** the library was built with (the package refuses another: "mlxf Fortran compiler mismatch") | other compilers (ifx, flang, LFortran): CMake refuses them |
| MLX | **shared** mlx-c, exactly the release the library was built with (0.8.0 with MLX 0.32.4 today; "mlxf mlx-c mismatch" otherwise) | a static `libmlxc`, another mlx-c release |
| platform | macOS on Apple silicon with Metal (the GPU and the CPU device); a CPU-only MLX build (the CPU device alone) | other platforms |
| threads | **one thread** builds and evaluates graphs; with OpenMP (on by default) every library call inside a parallel region, at any level, stops | calls from several threads: another host thread (pthreads, GCD, C++) is not detected |
| build | CMake 3.25 or newer, or pkg-config | |
| optional | Python 3.7 or newer, for the lifetime checker | |

An OpenMP code keeps its parallel regions for its own host work and calls the library outside them; data the
library copied out may be processed in parallel.

## Install and link

```bash
cmake -S . -B build_release -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DFORTLS=OFF
cmake --build build_release --parallel
cmake --install build_release --prefix "$HOME/local/mlxf" --component mlxf
```

```cmake
find_package(mlxf CONFIG REQUIRED)               # -Dmlxf_DIR=$HOME/local/mlxf/lib/cmake/mlxf
target_link_libraries(my_application PRIVATE mlxf::mlxf)
mlxf_check_lifetime(my_application)              # optional: the lifetime checker before each build
```

Import only `mlxf`, with an `only:` list; it is the one installed module. pkg-config users read
`pkg-config --cflags --libs --static mlxf` and must check its `fortran_compiler_version` and `mlxc_version`
themselves (the CMake package checks both). The installed check, `scripts/check_install.sh`, does all of this
from a scratch prefix, and [how2use_from_simple.md](how2use_from_simple.md) gives the details of embedding.

## Precision and devices

| kind | on the GPU | on the CPU device | to and from Fortran |
| --- | --- | --- | --- |
| float32 (`real(real32)`) | yes; full float32 products need `MLX_ENABLE_TF32=0` in the environment (MLX's default may use TF32) | yes | `mlx_from`, `mlx_to`, `mlx_view`, `mlx_alloc`, `mlx_item` |
| float64 (`real(real64)`) | **no**: an operation built on the GPU stops (Metal has no float64) | yes, but `exp`, `sin`, `cos`, `erf`, the FFTs and the fused layers compute in float32 (float64 storage, float32 accuracy); the FFTs return float32 | as float32 |
| complex64 (`complex(real32)`) | yes | yes | as float32 |
| complex128 (`complex(real64)`) | no | no | no transfer exists (MLX has no complex128) |
| float16, bfloat16, unsigned integers | yes | yes | none: convert with `mlx_astype` first |
| int8 to int64, boolean | yes | yes | as float32; `mlx_mean`, `mlx_var`, `mlx_std` of integers compute in float32 |

Nothing falls back silently from one device or kind to another: choose the device with `mlx_set_default_device`,
keep float64 work on the CPU device, and convert kinds explicitly. Mixed scalars are weak: a real or default-integer
scalar takes the array's kind (quickstart, rows D5 to D8 and D21).

## Errors

| when | what happens | what to write |
| --- | --- | --- |
| building a graph (every operator and function: a shape mismatch, float64 on the GPU, a bound outside the array, an integer scalar a kind cannot hold) | `error stop 86` with a message; a later `status` cannot catch it | validate inputs first: shapes and extents on the host, untrusted indices with `mlx_check_indices` |
| evaluating, copying out, files, devices, memory limits, the `apply` of a function or kernel | a returned `status` and the message in `mlx_last_error()`, if `status` is given (else a stop); MLX stays usable | pass `status=` and check it |
| inside an `mlx_function` callback | the callback must never stop: it returns a status | use only operations that cannot fail on its inputs |

Construction errors are not recoverable in this release: a design for checked construction exists and is
deferred (it is not a feature). A host that must survive bad input validates before it builds.

## Ownership

`type(mlx_array)` holds a counted handle: assignment shares it, finalization releases it, and `mlx_live_count()`
reports what is alive. gfortran mis-finalizes a few forms (a function result in a list of handles, `[a, exp(b)]`;
a result assigned to a whole array of handles, `v = exp(a)`; and others): the installed
`<prefix>/share/mlxf/check_consumer.py` (or `mlxf_check_lifetime` in CMake) reports each with its line and the
safe spelling, and lists what it cannot see. A pointer from `mlx_view(w, p)` is valid while the named array `w` is
unchanged; a buffer from `mlx_alloc` may be written only until the array is first passed to the library.

## Costs

Every evaluation crosses to the device and waits for it, so a loop that evaluates at every step pays that wait at
every step. Measured on an Apple M5 Ultra (MLX 0.32.4, `MLX_ENABLE_TF32=0`, a Release build), by
`mlxf_test_exec test=bench_user_costs suite=costs`, median of five repeats after a warm-up, with the range; a
measurement of this machine, not a promise:

| what | GPU | CPU device |
| --- | --- | --- |
| a small step (`a = a*0.999 + 0.001`, 4096 float32) evaluated at every step | 152 to 216 µs per step | 11.6 to 13.1 µs |
| the same steps evaluated once at the end | 6.5 to 7.3 µs per step | 4.4 to 4.9 µs |
| one element read by `mlx_item(mlx_slice(a, [i], [i]))` | 19.1 to 19.5 µs per element | 10.5 to 12.5 µs |
| all 4096 elements read by one `mlx_to` (evaluated array) | 0.15 µs per copy | 0.15 µs |
| `2*a` of 64 MiB in by `mlx_from` and out by `mlx_to` | 3.1 to 3.2 ms (42 GB/s of data in and out) | 2.8 to 2.9 ms (47 GB/s) |
| the same through a buffer from `mlx_alloc`, written once, read by `mlx_view` (no copy) | 4.5 to 4.8 ms (28 to 30 GB/s: allocating and filling the fresh buffer dominates) | 4.8 ms (28 GB/s) |
| `exp(x)*2 + 1` on 4096 values, called directly and evaluated | 157 µs per call | 13.6 to 15.1 µs |
| the same through `mlx_function`, and compiled (warm) | 157 µs, 142 µs | 15.2 to 15.6 µs, 11.4 to 11.5 µs |
| the compiled function's first application (its trace; cold) | 140 ms in a fresh process, 1.3 ms once MLX's kernel cache is warm | 0.35 to 0.38 ms |

The two values of each cell are the medians of two runs of the benchmark (load 3.7 to 4.0).

What follows from it: build a batch of work and evaluate it once (`mlx_eval`, or the copy-out that evaluates);
read many elements with one `mlx_to`, never with `mlx_item` in a loop; on the GPU, small operations cost the
evaluation's wait, not their arithmetic; compilation pays off for a callback applied many times, after a first
application that can cost a large fraction of a second; `mlx_alloc` saves a copy only when the data are produced
into its buffer once, not when a host array must be copied into it anyway. A long loop that never evaluates is the opposite mistake: every step and
every scalar stays alive in the graph until it runs, and a few hundred thousand steps exhaust Metal's resources.
Evaluate at the loop's own batch boundary and watch `mlx_active_memory()` and `mlx_peak_memory()`; the right
cadence depends on the work and the machine, and none is universal (quickstart, row S5).
