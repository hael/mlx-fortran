# Code review against MLX and mlx-c

Reviewed 2026-11-25. **Status: review delivered; five findings open.**
The review changed no implementation. This record contains findings and recommended remediation; it is
not an implementation plan or a claim that the findings have been fixed.

## Scope and comparison bases

The review covered the runtime and handle ownership, array lifetime and transfers, layout and indexing
conventions, operation wrappers, linear algebra and convolutions, FFTs, compilation callbacks, custom
Metal kernels, generated C bindings, test infrastructure and numerical oracles, and build/install
integration. The binding contract and repository policies were the local requirements; the MLX and mlx-c
sources supplied the upstream behavior and API contracts.

| Source | Reviewed revision | Version |
| --- | --- | --- |
| mlx-fortran | `c6ea867` | 0.1.0 |
| MLX, local `~/src/mlx` | `5996d291e` | 0.33.0 |
| mlx-c, local `~/src/mlx-c` | `a26f2d5` | 0.8.0 |

Runtime validation linked the installed **MLX 0.32.4 and mlx-c 0.8.0**, using GNU Fortran 16.2.0. The
local MLX checkout and linked runtime therefore differ. Metal execution was observed on a device reporting
architecture `applegpu_g15s`. No hardware model or performance equivalence is inferred from that identifier.

The worktree was clean at the start and end of the code review. Builds and probes used separate directories
under `/private/tmp`.

## Assessment

Five issues were reproduced. Two allow validation to report success when it should fail, so they should be
fixed before green builds are used as evidence of reliability comparable to upstream. One issue violates
the scalar dtype contract; two affect build and installation verification.

The ownership model, independent numerical oracles, checked error boundaries, and installed-module isolation
provide a solid foundation. The demonstrated priority is to strengthen failure detection and dtype boundary
coverage. Planned API omissions and documented compiler restrictions were not counted as defects.

| ID | Priority | Finding | Status |
| --- | --- | --- | --- |
| R1 | P1 | Numerical error checks can accept NaN-corrupted results | Open |
| R2 | P1 | An interrupted CTest run can pass the build gate | Open |
| R3 | P2 | Weak real scalars promote float16/bfloat16 arrays to float32 | Open |
| R4 | P2 | CMake embedding through `add_subdirectory` fails | Open |
| R5 | P2 | Installation verification rejects equivalent macOS temporary paths | Open |

P1 means fix in the next hardening batch because validation can give false assurance. P2 means a
reproducible correctness or integration defect that should be scheduled for repair.

## R1 — Reject unexpected nonfinite values before reducing numerical errors

**Location:** [src/test/mlxf_test_utils.f90](../../../src/test/mlxf_test_utils.f90), `flat_error`,
lines 228–229 at the reviewed revision.

The helper computes:

```fortran
err = 0._real64
if( size(ref) > 0 ) err = maxval(abs(got-ref)/max(1._real64, bound))
```

It does not check whether the copied result contains NaNs. With the reviewed compiler, `maxval` can ignore
a NaN among finite errors. A probe using the actual test helper constructed an MLX float32 array containing
`[1, NaN, 3]`, compared it with `[1, 2, 3]` using unit bounds, and passed the result to `judge_error`:

```fortran
x = [1._real32, ieee_value(0._real32, ieee_quiet_nan), 3._real32]
a = mlx_from(x)
err = shaped_error(a, [1._real64, 2._real64, 3._real64], &
    [1._real64, 1._real64, 1._real64])
call judge_error(err, 1.e-6_real64, 'NaN injection', 'float32', 1)
```

**Observed:** `err = 0`, `tests_failed = 0`, on the CPU device. A corrupt element passed the numerical check.

The shared helper is used by matrix-product, factorization and convolution tests. Standalone `max`/`maxval`
error aggregations also warrant inspection; the probe establishes the shared-helper defect, not that every
numerical test has the same defect. Upstream MLX's `mlx/ops.cpp`, `allclose`/`isclose` around lines 2145–2193,
uses elementwise comparisons and explicit nonfinite handling rather than this maximum-error shortcut.

**Recommended remediation:** explicitly reject unexpected nonfinite results before reducing errors. Validate
the finite-reference and bound assumptions as well. Where NaNs or infinities are expected, check their
positions and signs under a separate explicit contract. Add negative controls with one corrupted element
among otherwise correct elements, including different positions, and verify that failure reaches the process
exit status. Audit other numerical error reductions for the same failure mode.

## R2 — Propagate CTest failures and reject incomplete results

**Locations:** [scripts/run_fast_gate.sh](../../../scripts/run_fast_gate.sh), lines 29–30;
[scripts/ctest_budget.py](../../../scripts/ctest_budget.py), lines 38–43 and 75.

The gate pipes CTest through `tee`, then returns the budget parser's status. It does not propagate CTest's
exit status. The parser accepts any nonempty set of matching test-result lines and substitutes the sum of
their timings when the final total is missing. It does not require a complete run.

A scratch executable named `ctest`, placed first on `PATH`, printed the following and exited with status 42:

```text
Test project /tmp/interrupted
    Start 1: unit_core
1/9 Test #1: unit_core ........................   Passed    0.52 sec
    Start 2: unit_array
```

The actual `scripts/run_fast_gate.sh` was run against a configured scratch build with that substitute.
**Observed: the gate exited 0.** The parser separately described the same log as one entry within budget.

This permits an interrupted run with passing partial output to authorize the compile scripts' subsequent
installation. Passing ordinary CTest runs do not exercise this failure path.

**Recommended remediation:** capture and propagate CTest's status through the pipeline, including failure
to enter the build directory. Reject incomplete or unrecognized result logs. Add negative controls for a
nonzero CTest exit after partial success, an empty log, a truncated summary and a reported failed test.
Enabling `pipefail` alone is insufficient if the script continues and later returns the parser's success.

## R3 — Preserve half-precision dtypes for weak real scalars

**Location:** [src/core/array/mlxf_array_elementwise.f90](../../../src/core/array/mlxf_array_elementwise.f90),
`mlxf_weak_scalar`, lines 67–73.

The helper constructs float64 and complex64 scalars explicitly, then falls back to float32 for every other
array dtype. That fallback includes float16 and bfloat16.

For each half format, the probe constructed `a` by converting `mlx_from([1._real32, 2._real32])`, then
evaluated the result dtypes of:

```fortran
b = a + 0.1_real32
b = max(a, 0.1_real32)
```

**Observed on both CPU and GPU:** both expressions produced float32 for float16 and bfloat16 input arrays.
This changes precision and result storage size.

The [binding contract](../../policies/binding_contract_policy.md), section 5, states that a Fortran scalar
takes the array's kind when the array is real or complex. Upstream MLX's `python/src/utils.cpp`, `to_array`
and `to_arrays` around lines 8–86, constructs a weak floating scalar using the floating array's dtype.
mlx-c receives explicit arrays, so preserving this weak-scalar rule is the Fortran binding's responsibility.

**Recommended remediation:** construct or convert the scalar to the array's floating dtype before invoking
the binary operation. Expand scalar tests across float16, bfloat16, float32, CPU float64 and complex64, with
both operand positions where supported. Assert result dtypes as well as values. The math weak-scalar tests
at `src/core/ops/mlxf_ops_math_tester.f90:222–258` currently exercise float32 arrays only.

## R4 — Resolve CMake source paths relative to mlx-fortran

**Locations:** [CMakeLists.txt](../../../CMakeLists.txt), lines 4 and 64;
[src/CMakeLists.txt](../../../src/CMakeLists.txt), lines 23–24.

These paths use `CMAKE_SOURCE_DIR`, which names the top-level project when mlx-fortran is embedded.
A minimal parent project was configured with GNU Fortran 16.2:

```cmake
cmake_minimum_required(VERSION 3.25)
project(embed LANGUAGES Fortran C)
set(BUILD_TESTS OFF CACHE BOOL "")
set(FORTLS OFF CACHE BOOL "")
add_subdirectory(/Users/elmlundho/src/mlx-fortran mlxf)
```

**Observed:** configuration failed to find `AutoDetectGCC`, `CompilerConfig`, `Dependencies`, the build-info
template and the binding generator because it searched under the parent source directory. This affects
source embedding; installed CMake package consumers passed the separate checks below.

**Recommended remediation:** scope helper, template and generator paths to the library's own source root,
using current-list/current-source directories and project-scoped paths as appropriate. Add a minimal parent
configuration/build check. This also supports the embedding intent in the
[compile-time policy](../../policies/compile_time_policy.md).

## R5 — Canonicalize both sides of the install include-path comparison

**Location:** [scripts/check_install.sh](../../../scripts/check_install.sh), line 101.

The pkg-config check compares `Path(f[2:]).resolve()` with `Path(prefix, incdir, 'mlxf')`, resolving only
the first path. On macOS the default temporary directory can be under `/var/folders`, an alias of
`/private/var/folders`. Equivalent include paths consequently compare unequal.

**Observed:** `scripts/check_install.sh /private/tmp/mlxf-review-release` failed at this assertion under
the session's default `TMPDIR`. With `TMPDIR=/private/tmp`, the complete installation check passed,
including both consumer mechanisms on CPU and GPU. This was a validation-script failure, not evidence
that the installed library was broken.

**Recommended remediation:** resolve both paths, or compare filesystem identity. Retain coverage for spaces
in the installation prefix and add coverage for a temporary directory reached through a symlink.

## Validation performed

Clean scratch builds used CMake directly, `FORTLS=OFF` and `MLXF_WERROR=ON`. This avoided installation into
the owner's normal build tree. For each of Debug and Release:

```sh
cmake -S . -B /private/tmp/mlxf-review-debug -DCMAKE_BUILD_TYPE=Debug -DFORTLS=OFF -DMLXF_WERROR=ON
cmake --build /private/tmp/mlxf-review-debug --parallel 8
ctest --test-dir /private/tmp/mlxf-review-debug -L fast --output-on-failure --parallel 4
```

The Release invocation substituted `Release` and `/private/tmp/mlxf-review-release`.

| Check | Observed result |
| --- | --- |
| `scripts/check_tree.sh` | Passed |
| Clean Debug and Release builds | Passed with warnings treated as errors |
| Debug fast CTest suite | 9/9 groups; 4,709 assertions and 19 guard cases; 11.39 s |
| Release fast CTest suite | 9/9 groups; 4,709 assertions and 19 guard cases; 11.02 s |
| Device coverage in both fast runs | CPU and observed Metal execution; no skips |
| Release `test=unit_kernels suite=polar_shiftmap_accuracy device=all` | 48/48 assertions on CPU/GPU |
| Installed CMake and pkg-config consumers | Passed on CPU/GPU with canonical `TMPDIR` |
| Installed module isolation and compiler-mismatch refusal | Passed |

The first sandboxed CTest attempt could not open a GPU and failed under `MLXF_REQUIRE_GPU`; the successful
runs above used a session with Metal access. GPU success is based on those observed runs.

The separate `recovery_half` memory-stress suite, the 64,000-pair polar accuracy mode, full upstream test
suites and performance benchmarks were not executed. This review does not establish numerical correctness
for every dtype/shape combination or performance parity with upstream. The passing tests above remain
subject to R1's demonstrated assertion weakness.

Session-local evidence was retained under `/private/tmp`:

- `mlxf-review-debug-{configure,build,ctest-metal}.log`
- `mlxf-review-release-{configure,build,ctest-metal}.log`
- `mlxf-review-install.log` and `mlxf-review-install-canonical.log`
- `mlxf-review-polar-accuracy.log`
- `mlxf-review-probes/`: NaN and scalar probe sources/binaries, partial CTest fixture and embedding fixture/log

Those temporary artifacts are supporting evidence, not repository dependencies. The reproductions and
observed outcomes needed to understand each finding are recorded above.
