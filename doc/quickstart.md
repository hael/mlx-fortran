# Quickstart: where Fortran and mlxf differ, and what the caller must do

`mlxf` keeps Fortran's view (column-major arrays, 1-based dimensions and indices, intrinsic names), but the
arithmetic is MLX's. This page lists what a Fortran programmer meets first, with the program that proves each
row, and then what the library enforces against what is left to the caller. The full contract is
[`doc/policies/binding_contract_policy.md`](policies/binding_contract_policy.md), every name has its entry in the
[API reference](api_reference.md), the requirements and the precision, error and cost tables are in
[installed use](how2s/how2use_installed.md); a first program is in the [README](../README.md).

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
| D20 | `call random_number(x)` against `mlx_random_uniform(shape, key=key)` | the processor's generator, its state hidden | float32, a function of the key and the shape: the same key gives the same sample; without a key MLX's global key, which `mlx_random_seed` sets and each draw advances | different | D20 |
| D21 | `a + 1`, `2 * x`, an integer array or a real one with a default integer | integer arithmetic; a real result | the scalar takes the array's kind: int32 + 1 is int32 (exact, never through real32), 2 * float32 stays float32, a boolean array with 1 gives int32; a value the array's integer kind cannot hold (int8 with 300, an unsigned kind with -1) stops instead of wrapping | same, and a stop where Fortran would overflow | D21 |

Scalars are weak in every binary operation that takes one (arithmetic, comparisons, `max`, `min`, `atan2`,
`modulo`, ...): a real64 literal never makes a float64 graph. Integer arrays with a real scalar give float32; with a
default-integer scalar (`k + 1`, `2 * k`, `k > 0`) they keep their kind, exactly (row D21).

## Limits of the present library, and what to write instead

These are behaviours of the library as it is today (MLX 0.32.4, mlx-c 0.8.0, GNU Fortran 16.2), measured on both
devices; rows marked fixed say what the library now does, and for the others, until their fixes land, the spelling
in the last column is the safe one. Each row is a
block `! S<n>` of [`test/consumer/mlxf_example_user_safety.f90`](../test/consumer/mlxf_example_user_safety.f90),
which the consumer check compiles and runs against the installed package.

| row | what goes wrong today | write instead |
| --- | --- | --- |
| S1 | (fixed) `mlx_mean`, `mlx_var` and `mlx_std` convert integer and boolean input to float32 before the arithmetic, so a large total no longer wraps; int64 and uint64 values beyond 2^24 are rounded to float32 first, so the statistics have float32's precision, not integer exactness | `mlx_mean(k)` directly |
| S2 | (fixed) a save is written to a temporary file beside its destination and renamed over it only when complete: a refused or failed save (safetensors float64, GGUF other than int8, int16, int32, float16, float32, an evaluation or a write that fails) leaves the old file byte for byte; a symbolic link, a hard-linked file, a directory or another user's file is refused as destination | save over the checkpoint; the promise covers a save that returns a failure, not a crash or a power loss (nothing is flushed to disk with fsync), after which a hidden temporary file may remain |
| S3 | an index outside 1 through the extent is not checked by the operations: `mlx_take` of index 6 from five values returns 0 with status 0; on the CPU device a far index (1000000) returns another value or ends the process, and so may a negative one; index 0 wraps to the last element (row D17) | `call mlx_check_indices(ix, extent, status)` once on untrusted indices, before they reach a graph (never inside a compiled callback); the binding policy's section 10 gives the check for each index-taking operation |
| S4 | a function result inside an array constructor of handles, `[a, exp(b)]` or `[a, b*2.0]`, and a function result assigned to a whole array of handles, `v = exp(a)`, are never finalized by gfortran: 1000 rounds keep 1000 handles and 250 MiB alive, silently | name the result first (`t = exp(b)`, then `[a, t]`); assign arrays of handles element by element; run the installed `share/mlxf/check_consumer.py` on your sources, or `mlxf_check_lifetime(<target>)` in CMake, which reports these forms with their line (and lists what it cannot see) |
| S5 | a loop that never evaluates keeps every step and every scalar operand alive: `a = a*0.999 + 0.001` evaluates after 100000 steps and stops while it is built at 300000 on an M5 Ultra's GPU (`[metal::malloc] Resource limit (499000) exceeded`) | evaluate at a batch boundary (`call mlx_eval(t)` every 1000 steps); the limit depends on the machine and the graph, so never rely on a count |
| S6 | a reduction is a rank-0 array, not a Fortran logical: `if( all(a > 0.) )` does not compile | `call mlx_item(all(x > 0.), positive, status=status)`, then test `positive` |
| S7 | (fixed) `norm2` and `mlx_mean` of floating and complex arrays scale by the largest magnitude before they sum, so two float32 values of 1e20 (or 1e-30) have a finite, nonzero norm and two of 2e38 a finite mean (MLX alone gave infinity, 0 and infinity); `maxval` and `minval` of an empty extent return Fortran's `-huge` and `huge` (for integers -huge-1 and huge) in the operand's kind, where they stopped | `norm2(x)`, `mlx_mean(x)` and `maxval(x)` directly; the gradient of `norm2` at zero is not finite, as for any Euclidean norm |

Errors while a graph is built stop the program (`error stop 86`) and cannot be caught by a later `status`; a
caller that must survive bad input validates it before building (S3), and float64 work is placed on the CPU device
(row D15). Integer statistics need no conversion:

<!-- example: test/consumer/mlxf_example_user_safety.f90 -->
```fortran
raw = 2000000000
k = mlx_from(raw)
m = mlx_mean(k)
```

Untrusted indices are checked once, and a function result is named before it joins a list:

<!-- example: test/consumer/mlxf_example_user_safety.f90 -->
```fortran
ix = mlx_from([2, 1])
call mlx_check_indices(ix, 2, status)
if( status /= 0 ) error stop 'mlxf_example_user_safety: S3 '//mlx_last_error()
t = mlx_take(x, ix)
```

<!-- example: test/consumer/mlxf_example_user_safety.f90 -->
```fortran
t = exp(x)
c = mlx_concatenate([x, t])
do i = 1, 2
    v(i) = exp(x)
end do
```

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
