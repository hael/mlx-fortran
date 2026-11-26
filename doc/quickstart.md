# Quickstart: where Fortran and mlxf differ, and what the caller must do

`mlxf` keeps Fortran's view (column-major arrays, 1-based dimensions and indices, intrinsic names), but the
arithmetic is MLX's. This page lists what a Fortran programmer meets first, with the program that proves each
row, and then what the library enforces against what is left to the caller. The full contract is
[`doc/policies/binding_contract_policy.md`](policies/binding_contract_policy.md); a first program is in the
[README](../README.md).

## Dtypes and results

Each row is asserted by its block `! D<n>` of
[`test/consumer/mlxf_example_differences.f90`](../test/consumer/mlxf_example_differences.f90), which prints
`D<n>: ok` (a failed row exits 1), or, for a stop, by a member of the guard group `object_contracts`
(`mlxf_test_exec expect_abort <member>`, which accepts only the library's `error stop 86`). The consumer check
(`scripts/check_install.sh`) runs the example against the installed package on the GPU (the float64 rows on the
CPU device) and on a CPU-only MLX; `a` and `b` are int32 arrays, `x` float32, `h` float16, `z` complex64, `d`
float64, `m` boolean.

| row | Fortran spelling | Fortran gives | mlxf gives | | evidence |
| --- | --- | --- | --- | --- | --- |
| D1 | `a / b`, integer arrays | integer division, truncated: 7/2 = 3 | true division to float32: 3.5 | different | D1 |
| D2 | `mlx_floor_divide(a, b)` | (no intrinsic; `a/b` gives -7/2 = -3) | int32, floored: -4 | different | D2 |
| D3 | `matmul(a, b)`, integer matrices | an integer product | a stop: MLX multiplies inexact types only; convert with `mlx_astype` | different | `guard_matmul_integer` |
| D4 | `matmul(a, x)`, integer and real | promoted to real | promoted to float32 | same | D4 |
| D5 | `x + 0.1_real64` | real64 (mixed-kind expression) | float32: the scalar takes the array's kind | different | D5 |
| D6 | `h + 1.0` | (no half kind) | float16: the scalar is made in the half kind | (MLX's) | D6 |
| D7 | `a + 0.5_real64` | real64 | float32, whatever the real scalar's kind | different | D7 |
| D8 | `z + 1.0` | complex | complex64 | same | D8 |
| D9 | `real(d)`, `real(z)` | default real | float32, from every numeric kind | same | D9 |
| D10 | `cmplx(x, y)` | complex, components kept | complex64 `x + i*y`: exact for finite parts; an infinite `y` makes the real part NaN | different for non-finite | D10 |
| D11 | `sum(a)`, `count(m)`, `mlx_mean(a)` | integer, default integer, (no intrinsic) | int32, int32, float32 | same | D11 |
| D12 | `all(m)`, `maxloc(x)` | a logical scalar; default-integer subscripts | a rank-0 boolean array; one-based int32 subscripts of the first maximum | different (an array) | D12 |
| D13 | `mlx_round(x)` against `nint(x)` | halves away from zero: 0.5 to 1, 2.5 to 3 | halves to even: 0.5 to 0, 2.5 to 2 | different | D13 |
| D14 | `modulo(a, b)` | the divisor's sign | the divisor's sign | same | D14 |
| D15 | a float64 operation with the GPU as default device | real64 arithmetic | a stop: Metal has no float64 | different | `guard_float64_on_gpu` |
| D16 | `exp(d)` on the CPU device | real64 accuracy | float64 storage, float32 accuracy (also `sin`, `cos`, `erf`, the FFTs, ...) | different | D16 |
| D17 | `mlx_take(x, idx)` with an index 0 | out of bounds (undefined, or a runtime check) | unchecked: 0 wraps to the last element | different | D17 |
| D18 | `x > 1.5` | a logical array | a boolean array; copied out as `logical(c_bool)` | same | D18 |
| D19 | `matmul(a3, b3)`, `transpose(a3)` of rank 3 | not allowed (rank 2 only) | batched over dimensions 3 and up | different | D19 |

Scalars are weak in every binary operation that takes one (arithmetic, comparisons, `max`, `min`, `atan2`,
`modulo`, ...): a real64 literal never makes a float64 graph. Integer arrays with a real scalar give float32.

## Obligations and what is enforced

| | the caller's obligation | what the library enforces at run time |
| --- | --- | --- |
| threads | build and evaluate graphs from one thread | with `USE_OPENMP=ON` (the default) every call inside an OpenMP parallel region, at any level, stops; another host thread (pthreads, GCD, a C++ caller) is not detected, nor anything with `USE_OPENMP=OFF` |
| the error handler | leave mlx-c's error handler to the library | its first call replaces mlx-c's process-wide handler with one that records MLX's messages for `mlx_last_error()`; a host that installs its own afterwards receives the messages itself (the statuses still fail, `mlx_last_error()` is then empty); one that restores mlx-c's default makes an MLX error print and `exit(-1)` |
| errors | treat a stop as a program error; check the status of what can fail at run time | building a graph stops with `error stop 86` on any MLX error; the checked procedures (`mlx_eval`, `mlx_to`, `mlx_to_alloc`, `mlx_view`, `mlx_alloc`, `mlx_set_default_device`, `mlx_set_memory_limit`, the `apply` of functions and kernels, ...) return a status and leave the message in `mlx_last_error()` |
| callbacks | a callback of `mlx_function` returns a status and never stops | the library turns a missing or stale output into a failure; it cannot intercept a `stop` in the callback |
| memory | size work from `mlx_peak_memory()` and a budget | over-subscribed unified memory pages rather than fails; one buffer above the device's maximum fails with a status |
| `mlx_view` | the owner is a named variable: `w = exp(a)`, then `call mlx_view(w, p)`; `p` is valid until `w` changes and is never written through | a refused view leaves `p` disassociated; a view of an expression, `call mlx_view(exp(a), p)`, dangles at the end of the statement and is not detected |
| `mlx_alloc` | write through `view` only until the array is first passed to any library procedure | the buffer is handed to MLX without a copy when Metal accepts it, else copied once; later writes are not detected |
| devices | choose the device; float64 on the CPU only | three sessions: Metal with a GPU (both devices), Metal without one (headless, sandboxed, virtual: MLX cannot allocate, and the first operation that would stops), a CPU-only MLX (the CPU device); a float64 operation built on the GPU stops |
| precision | `MLX_ENABLE_TF32=0` in the environment for full float32 matrix products | the library never changes it; `mlxf_runtime_description()` reports it |

A program tells the three sessions apart with `mlx_metal_is_available()` and `mlx_device_count`, as
[`test/consumer/mlxf_example_errors.f90`](../test/consumer/mlxf_example_errors.f90) does:

<!-- example: test/consumer/mlxf_example_errors.f90 -->
```fortran
if( mlx_device_count(MLX_DEVICES%gpu) > 0 )then
    write(*,'(a)') 'session: Metal with a GPU; both devices allocate'
    call mlx_set_default_device(MLX_DEVICES%gpu)
else if( trim(arg) == 'require-gpu' )then
    error stop 'mlxf_example_errors: require-gpu, and no GPU device in this session'
else if( .not. mlx_metal_is_available() )then
    write(*,'(a)') 'session: a CPU-only MLX; the CPU device allocates'
    call mlx_set_default_device(MLX_DEVICES%cpu)
else
    write(*,'(a)') 'SKIP: mlxf_example_errors: Metal without a GPU (headless, sandboxed, virtual); MLX cannot allocate'
    stop
endif
```

The same program shows a refused copy reported through `status` and `mlx_last_error()`, and the named owner
of a view. Every fenced Fortran block of this page, the README and `CONTRIBUTING.md` is a verbatim run of a
program the consumer check compiles and runs, and every row above has its evidence (`scripts/check_rules.py`,
rule `docex`).
