# Code review: refactoring, numerical hardening, consumer tools and Linux port

Reviewed **2026-11-27**, through **`07b86bc4415de1d733d062c06d08fa46db06264e`**.
**Four new findings remain open**, plus one reproduced limitation already recorded by the kernel-forms
work. The two findings of the [previous review](mlxf_quality_review_parity.md) are addressed, with the
validation qualifications below. Fresh Debug and Release fast gates both pass **13/13**, without skips;
the additional boundary probes below expose cases those gates do not cover.

This is a review record. No implementation, test, policy, skill or plan was changed to resolve a finding.

## Findings

| ID | Priority | Finding | Observed consequence |
| --- | --- | --- | --- |
| F1 | P2 | The inactive plain-norm branch contaminates differentiation of the scaled norm | Small nonzero inputs have a correct norm but NaN gradients on CPU and GPU |
| F2 | P2 | Scaling does not widen half-precision reduction intermediates | The norm and mean of 65,536 float16 ones are wrong or infinite although both answers are representable |
| F3 | P2 | A replacement checkpoint's temporary file is written before its permissions are restricted | Replacing a mode-0600 checkpoint under umask 022 exposes its new contents in a mode-0644 sibling |
| F4 | P2 | The installed checker path uses a dependency's prefix with CMake 3.29 | A supported consumer configuration succeeds, then its build fails because the checker is sought under the MLX installation |
| K1 | Known limitation | Constructor analysis collects handle names across unrelated procedures | The new installed lifetime checker rejects valid host-only arithmetic; this limitation was already recorded for the repository checker |

P2 findings merit correction in the next hardening batch. K1 is recorded separately because its analysis
limitation is already known, rather than counted as a newly discovered implementation defect.

### F1 — Make the inactive norm branch safe to differentiate

**Location:** [mlxf_linalg_matrix.f90](../../../src/core/linalg/mlxf_linalg_matrix.f90), lines 341 and
356, and especially **418–420** in `scaled_norm2`.

Both entry points construct the plain norm and pass it to `scaled_norm2`, which selects
`merge(sqrt(q)*s, plain, ok)`. For small nonzero inputs, the selected scaled value is correct, but the
plain branch squares the input to zero. Masking its result does not remove its derivative graph.

Using `mlx_value_and_grad` with this callback:

```fortran
subroutine f(a, r, status)
    type(mlx_array), intent(in) :: a(:)
    type(mlx_array), allocatable, intent(out) :: r(:)
    integer, intent(out) :: status
    allocate(r(1))
    r(1) = norm2(a(1))
    status = 0
end subroutine
```

gave the following results with checked host transfers succeeding:

| Input | Device | Norm | Gradient | Expected gradient |
| --- | --- | --- | --- | --- |
| `[1e-30, 2e-30]`, float32 | CPU and GPU | `2.23606805e-30` | `[NaN, NaN]` | Approximately `[0.4472136, 0.8944272]` |
| `[1e-200, 2e-200]`, float64 | CPU | `2.2360679774997897e-200` | `[NaN, NaN]` | Approximately `[0.4472136, 0.8944272]` |
| `[1e20, 2e20]`, float32, control | CPU and GPU | `2.23606800e20` | `[0.447213590, 0.894427180]` | Same within float32 rounding |

The small-input failure was reproduced against both Debug and Release libraries. It violates the
[binding contract](../../policies/binding_contract_policy.md)'s norm derivative `a/norm2(a)` away from
zero. These inputs and their expected derivatives are representable; this is not the documented
undefined derivative at zero.

**MLX comparison:** local `mlx/primitives.cpp:5786–5808`, `Sqrt::vjp`, computes the ordinary square-root
derivative by dividing half the cotangent by the output. In the masked plain branch the cotangent and
output are both zero, producing NaN. The upstream primitive therefore explains why selecting the stable
forward value alone does not establish a stable derivative.

**Recommended correction:** make the inactive fallback graph safe for differentiation, or provide an
explicit derivative that preserves the chosen zero/NaN/infinity behavior. Add finite-value and numerical
gradient assertions for small nonzero inputs to `test_scaled_gradients`, including dimension and
dimension-list reductions. Its current large-input cases do not exercise the underflowing fallback.

### F2 — Widen the accumulation in the scaled half-precision reductions

**Locations:** [mlxf_linalg_matrix.f90](../../../src/core/linalg/mlxf_linalg_matrix.f90), **411–420**;
[mlxf_ops_reduce.f90](../../../src/core/ops/mlxf_ops_reduce.f90), **456–460**.

The scale bounds each term, but the intermediate reduction still runs in the operand's float16 dtype.
A bounded term does not imply that a long sum is representable in that dtype, or accumulated accurately.
For the public API expression:

```fortran
x = mlx_astype(mlx_from(spread(1._real32, 1, 65536)), MLX_DTYPES%float16)
! Evaluate norm2(x) and mlx_mean(x), casting their results to float32 for host inspection.
```

the observed results were:

| Operation | Exact answer | CPU | GPU |
| --- | --- | --- | --- |
| `norm2(x)` | `256` | `128` | `+Infinity` |
| `mlx_mean(x)` | `1` | `0.25` | `+Infinity` |

Both exact answers are exactly representable in float16. The norm failure was reproduced in Debug and
Release; the mean was probed in Release. Every evaluation completed normally. Casting **the operand**
to float32 before either operation gives `256` and `1` on both devices, isolating the intermediate dtype
as a relevant difference. Casting the result afterward cannot repair it.

**MLX comparison:** local `mlx/ops.cpp:2341–2358` implements mean using a sum followed by a normalizer;
delegating the mean of the scaled half array still invokes that narrow sum. This is an incomplete
hardening of a limitation inherited from the underlying reduction, not evidence that the module moves
introduced a new upstream arithmetic regression. The new norm and mean implementations explicitly
promise to avoid range failures for representable answers, so their tests need to cover reduction
length as well as operand magnitude.

**Recommended correction:** accumulate half-precision intermediates in a wider dtype and convert the
final result back according to the public dtype contract. Exercise float16 and bfloat16 with long,
constant and mixed-magnitude inputs on both devices, all reduction forms and relevant gradients. The
reproduced numbers above concern float16; no corresponding bfloat16 failure is claimed here.

### F3 — Restrict temporary-file access before writing checkpoint contents

**Locations:** [mlxf_io.f90](../../../src/core/io/mlxf_io.f90), **355–362** in `mlxf_save_begin` and
**378–380** in `mlxf_save_end`.

The transaction records an existing destination's mode, then creates its sibling with `fopen(...,"wx")`.
That creation uses the process's normal file permissions. The old mode is applied only after MLX has
written the new contents. Thus atomic replacement preserves the final mode but can temporarily broaden
access to the checkpoint data.

A scratch probe used an existing regular file owned by the current user, mode 0600, with umask 022.
It called the same `mlxf_save_begin`, `mlxc_save` and `mlxf_save_end` sequence as the public save path,
inspecting the intermediate file without a timing race:

```text
begin status                         0
destination mode                   600
temporary mode before write        644
temporary mode after write         644
destination mode after commit      600
final status                         0
```

While the file is being written, another local user able to traverse its directory can read the new
payload from the sibling. Its hidden name does not restrict access. The existing replacement tests
check the final mode, which cannot detect this interval. The policy's documented exclusions for
ownership groups, ACLs and crash durability do not address this permission widening.

**Recommended correction:** create the temporary file with restrictive access and establish the
required permissions before any payload write. Preserve the documented final mode for both replacement
and new-file saves, handle permission-setting failures without writing data, and add a transaction-step
test that inspects the mode while the temporary file contains the payload. The review used only scratch
files belonging to the current user; no other account's files were accessed.

### F4 — Preserve the package prefix before finding dependencies

**Location:** [mlxfConfig.cmake.in](../../../cmake/mlxfConfig.cmake.in), **67**, following the
`find_package(MLXC ...)` at line 27 and the optional OpenMP discovery.

With CMake 3.29 or older, a nested generated package configuration can overwrite `PACKAGE_PREFIX_DIR`.
The MLXC package does so here. Computing `mlxf_LIFETIME_CHECKER` after dependency discovery consequently
uses MLXC's installation prefix instead of mlxf's. This affects the project's supported CMake range,
whose lower bound is 3.25.

**Reproduction:** install the reviewed Release library into `/private/tmp/mlxf-review4-prefix`, leave
MLXC under `/opt/homebrew`, and configure the following consumer with the installed mlxf config:

```cmake
cmake_minimum_required(VERSION 3.25)
project(consumer LANGUAGES Fortran)
find_package(mlxf CONFIG REQUIRED)
add_executable(consumer main.f90)
target_link_libraries(consumer PRIVATE mlxf::mlxf)
mlxf_check_lifetime(consumer)
```

`main.f90` is a valid minimal program importing `mlxf`. The same source and installed library were tested
with two CMake versions:

| Consumer CMake | Resolved checker | Configure / build |
| --- | --- | --- |
| 3.29.6 | `/opt/homebrew/share/mlxf/check_consumer.py` | Configure succeeds; build exits 2 because the file does not exist |
| 4.5.1 | `/private/tmp/mlxf-review4-prefix/share/mlxf/check_consumer.py` | Configure and build succeed; checker passes |

CMake's own installed `CMakePackageConfigHelpers.cmake` documentation, lines 88–103, explicitly explains
the pre-3.30 behavior and the package author's obligation to preserve the prefix across dependency
lookups. CMake 3.29.6 was extracted into scratch storage for this test; no system installation was changed.

**Recommended correction:** resolve and retain the checker path immediately after `@PACKAGE_INIT@`,
before dependency discovery, or use an equivalent protected package-path variable. Add an installed
consumer check using an older supported CMake and distinct prefixes for mlxf and MLXC. The existing
installed check passed with CMake 4.5, so it does not cover this compatibility boundary.

## K1 — Known constructor-checker scope limitation reaches installed consumers

**Location:** [mlxf_consumer_checks.py](../../../scripts/mlxf_consumer_checks.py), **340–350**.

`ctorexpr_findings` gathers handle names from the entire file. A handle dummy in one procedure therefore
causes a real dummy with the same name in another procedure to be classified as a handle expression:

```fortran
module consumer
    use mlxf, only: mlx_array
    implicit none
contains
    subroutine device_part(a)
        type(mlx_array), intent(in) :: a
    end subroutine
    subroutine host_part(a, b)
        real, intent(in) :: a
        real, intent(out) :: b(1)
        b = [2*a]
    end subroutine
end module
```

GNU Fortran compiles this file. `check_consumer.py` exits 1 and claims that `2*a` refers to a handle that
is never finalized. Renaming only the host procedure's dummy to `x` makes the checker exit 0. Using
`mlxf_check_lifetime(target)` makes that false finding a build failure.

The [kernel-forms report](mlxf_kernel_forms_report.md), under “Left open for the maintainer,” already
records the file-wide-name limitation, and the history records its addition to the repository's skill
guidance. This review does not count it as a new discovery. It does demonstrate the effect on the newly
installed consumer checker, whose `--rules` limitations do not identify this false-positive case.

**Recommended follow-up:** apply scope-aware name resolution to constructor analysis, with fixtures
that distinguish real and handle expressions in sibling procedures and shadowed scopes. Until then,
document this particular false positive in the installed checker's user-visible limits. A clean lint
result still cannot prove lifetime safety; that separate documented limit remains valid.

## Recheck of the previous review

| Previous finding | Current evidence | Status |
| --- | --- | --- |
| F1: CPU-only CI calls an undelivered dependency-builder option | The builder now accepts `--cpu-only`, selects CPU scratch/install defaults, skips the Metal toolchain requirement and configures `MLX_BUILD_METAL=OFF`. Its `--cpu-only --help` path succeeds. The previous report also contains the owner's cold-build validation record. | Source defect addressed; a fresh dependency build was not repeated in this review |
| F2: ring test expects unsupported sum-scatter to succeed | The unmodified current Release `distributed_ring` suite was run with two concurrent ranks. Both pass **14/14 assertions**, including the expected evaluation refusal and subsequent peer messaging. | Addressed and independently rerun |

## Scope and comparison bases

The reviewed delta is **`b2c43a4..07b86bc`**: **219 changed files, 28,972 insertions and 9,302 deletions**,
including substantial documentation and file moves. Inspection covered the core module/signature
refactor and transfer boundaries; scaled reductions, empty extrema, integer statistics and scalar
promotion; explicit index validation; checkpoint transactions and libc portability; installed consumer
checks and packaging; Linux build/CI changes; polar memo layout, route/tile state and retained K4 map
reductions; and their associated tests, contracts and run records. Benchmark and kernel-form work was
reviewed selectively for correctness checks and retained behavior, not independently remeasured.

| Comparison source | Revision/version | Use |
| --- | --- | --- |
| mlx-fortran | `07b86bc4415de1d733d062c06d08fa46db06264e` | Reviewed implementation and test snapshot |
| Local MLX, `~/src/mlx` | `5996d291ee88db9535b33eec458ca241428c0d2b`, 0.33.0 | Reduction and derivative semantics, backend behavior, I/O and build comparison |
| Local mlx-c, `~/src/mlx-c` | `a26f2d584a14ec619ae8db9a09be03becd47598a`, 0.8.0 | C signatures, status/ownership boundaries and MLX forwarding |
| Executed libraries | MLX 0.32.4 / mlx-c 0.8.0 | Libraries linked by the fresh builds and diagnostic programs |

GNU Fortran was **16.2.0**. The observed Metal device was **`applegpu_g15s`**, one GPU. Source comparison
and runtime MLX versions differ as shown; results are not a claim of validation against MLX 0.33.0.

The owner worktree was clean at the start and remained clean until this report was written. A fixed
copy of the 330 tracked files was made at `/private/tmp/mlxf-review4-src-07b86bc`; all builds and probes
used scratch storage. Only this report, its index entry and its history entry are review edits.

## Validation performed

| Check | Observed result |
| --- | --- |
| Fresh Debug and Release builds, `MLXF_WERROR=ON`, `MLXF_REQUIRE_GPU=ON`, tests enabled | Both pass; zero compiler warning lines in either build log |
| Debug fast CTest gate | **13/13 pass**, no skips, 25.45 s wall |
| Release fast CTest gate | **13/13 pass**, no skips, 10.73 s wall |
| `scripts/check_tree.sh` | Pass |
| Installed consumer and examples, GPU required | Pass, including public API imports, lifetime-checker self-tests, private-module isolation, compiler/MLXC refusal checks, and pkg-config consumers on CPU/GPU |
| Parent-project embedding | Pass; parent program runs and private module import is refused |
| MLX-free toy build | Debug and Release pass; the 135-line host table equals the Release test executable's output byte for byte |
| Two-rank ring test | **14/14 assertions per rank**, both exits 0 |
| Additional numerical probes | F1 and F2 reproduced; large-norm and float32-accumulation controls pass |
| Temporary-file mode probe | F3 reproduced at the transaction boundaries |
| Installed consumer with CMake 3.29.6 / 4.5.1 | F4 fails with 3.29.6; the 4.5.1 control passes |
| Checker scope probe | K1 rejects the valid source; the renamed-dummy control passes |

The build trees are `/private/tmp/mlxf-review4-07b86bc-debug` and
`/private/tmp/mlxf-review4-07b86bc-release`. Their configure/build/CTest logs use
`/private/tmp/mlxf-review4-{debug,release}-*.log`; installation, embedding, off-state and static checks
have corresponding `/private/tmp/mlxf-review4-*.log` files. Ring logs are under
`/private/tmp/mlxf-review4-ring/`.

Diagnostic source, executables and output are retained under `/private/tmp/mlxf-review4-probes/`:
`norm.f90` and `norm_release.f90` (F1/F2), `controls.f90` (widened-operand controls), `save_modes.f90`
(F3), `cmake-consumer/` (F4), and `scopes.f90` / `scopes_control.f90` (K1). These are local scratch
artifacts, not installed tests or portable archival links.

## Limits and quality assessment

No fresh Linux run, CPU-only dependency bootstrap, hosted CI run or second-GPU-architecture run was
performed here. The Linux and M2/M5 results in the development reports remain attributed to those
reports. The benchmark throughput claims and discarded K4 candidates were not independently measured.
The full release wrapper was not executed: this review used a fixed source copy and its constituent
build, test, installation, embedding and off-state checks, avoiding the wrapper's Git operations under
the repository's read-only Git rules. No release-tag conclusion is implied.

The separation of handle ownership, generated C signatures and operation families makes the new tree
easier to audit. The independent numerical references, explicit guard tests and installed-consumer
checks provide useful evidence, and the earlier ring defect now has a passing backend-specific test.
The remaining gap exposed here is boundary coverage: forward stability does not establish derivative
stability; a small term does not establish a safe long reduction; a correct final file mode does not
establish safe intermediate access; and a current CMake success does not establish compatibility with
the supported range. Those are concrete next checks for bringing the binding's stated contracts up to
the standard intended by this review.
