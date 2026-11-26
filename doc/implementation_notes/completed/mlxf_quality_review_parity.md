# Code review: release hardening, toy refactoring and parity Phases 5–9

Reviewed **2026-11-26** at **`b2c43a41fe8e04d76dd73f281ec3d3f47585b5fc`**, after the latest pull.
**Two new findings remain open:** a broken cold-start path for CPU-only CI and an impossible success
expectation in the two-process distributed test. The four findings of the
[previous review](mlxf_quality_review_followup.md) are addressed. No implementation or test source was
changed in the repository during this review.

## Findings

| ID | Priority | Finding | Consequence |
| --- | --- | --- | --- |
| F1 | P1 | CPU-only CI invokes an option missing from the committed dependency builder | Every CPU matrix job fails on a dependency-cache miss, before configuration or tests |
| F2 | P2 | The ring test expects an operation the ring backend does not implement | Both processes abort before reaching the peer send/receive checks |

P1 should be fixed before relying on the new CI coverage. P2 is a reproducible defect to address in the
next distributed-test batch. Neither finding demonstrates an incorrect numerical result in the installed
Fortran wrappers.

### F1 — Deliver the dependency builder required by the CPU-only CI job

**Location:** [scripts/ci_cpu_job.sh](../../../scripts/ci_cpu_job.sh), lines 37–40; its dependency
[scripts/build_mlx_deps.sh](../../../scripts/build_mlx_deps.sh), lines 18–26 and 37–54.
The workflow's CPU job uses this path after a cache miss.

When the CPU-only prefix is absent, `ci_cpu_job.sh` invokes:

```sh
PREFIX="$PREFIX" scripts/build_mlx_deps.sh --cpu-only --jobs "$JOBS"
```

The checked-in builder accepts only `--jobs`, `-j` and help. It exits 1 on `--cpu-only`. It also still
unconditionally requires the Metal compiler and never supplies `MLX_BUILD_METAL=OFF`, so merely accepting
the option would not deliver the promised CPU-only build. MLX's own `CMakeLists.txt` defaults that option
to `ON` on this platform.

**Reproduction on the reviewed snapshot**, with an absent scratch prefix:

```sh
MLXC_ROOT=/private/tmp/mlxf-review3-missing-cpu \
  scripts/ci_cpu_job.sh Debug gfortran-16 --jobs 4
```

Observed exit **1**, before any dependency build:

```text
==== CPU-only MLX into /private/tmp/mlxf-review3-missing-cpu (scripts/build_mlx_deps.sh --cpu-only)
build_mlx_deps.sh: unknown option: --cpu-only
```

This affects all four CPU matrix combinations on a fresh runner, a cache eviction or a new cache key.
A pre-existing CPU prefix bypasses the broken branch, so successful development runs against such a
prefix do not validate the committed bootstrap. The release-hardening plan's Phase 2 progress records
an edited builder and successful CPU-only builds; those changes are absent from this revision's builder.
This is a mismatch between the delivered tree and its development record, not a failure to install Xcode
on the review machine.

**Recommended correction:** deliver the complete CPU-only branch: argument handling, Metal-toolchain
checks conditional on the selected backend, `MLX_BUILD_METAL=OFF`, and the documented prefix handling.
Then run the CI script from an empty prefix, verify `Metal backend: F` and zero no-device skips, and run
the installed consumer against that newly built prefix. Keep a cold-start check so a cached dependency
cannot conceal a missing bootstrap change.

### F2 — Test ring's refusal of sum-scatter and let peer messaging run

**Location:** [mlxf_distributed_tester.f90](../../../src/core/distributed/mlxf_distributed_tester.f90),
lines 178–186, especially the unchecked evaluation at line 184.

`run_all_distributed_ring_tests` explicitly initializes the `ring` backend, then expects
`mlx_sum_scatter` to evaluate successfully. In the local MLX source, `RingGroup::sum_scatter` in
`mlx/distributed/ring/ring.cpp`, lines 597–598, unconditionally throws
`[ring] sum_scatter not supported.` The installed MLX 0.32.4 behaves the same way. mlx-c delegates this
operation to MLX; the Fortran wrapper correctly preserves the lazy evaluation boundary.

The graph can be constructed with status zero and the expected shape. Consequently the existing status
and shape assertions pass, then `mlx_to(share, r)` without `status` terminates the process. The send and
receive assertions immediately below it are unreachable on this backend. The normal fast gate uses a
singleton group, where collectives return their operand, so it cannot expose this problem.

**Reproduction:** create `ring.json` containing

```json
[["127.0.0.1:29570"], ["127.0.0.1:29571"]]
```

Launch two copies of the Release executable concurrently, with `MLX_RANK=0` and `MLX_RANK=1`, respectively,
`MLX_HOSTFILE` set to that file's absolute path, `MLX_ENABLE_TF32=0`, and arguments
`test=unit_distributed suite=distributed_ring`. Both observed exits were **86**, with:

```text
mlxf: mlx_to: [ring] sum_scatter not supported. at mlx/c/array.cpp:352
```

**Diagnostic control:** in a separate scratch test object, replace only the sum-scatter success block
with checked evaluation that asserts a nonzero status and releases the failed result. With the other
checks unchanged, both ranks passed **12/12 assertions**, including the all-reductions, gather, one-based
peer ranks and send/receive of the asymmetric `(3, 2)` matrix. This is evidence for those bindings;
it is not a passing result for the repository's unmodified ring suite.

**Recommended correction:** make ring's unsupported operation an expected evaluation refusal, retain
the subsequent peer checks, and test successful sum-scatter separately on a backend that implements it.
Update the parity plan's runnable example and the binding policy's backend limitations accordingly.
Run the repaired two-process test before counting distributed peer behavior as validated.

## Resolution (2026-11-26, in the session on the M5 Ultra)

- **F1, fixed.** `scripts/build_mlx_deps.sh` takes `--cpu-only`: it builds MLX with `-DMLX_BUILD_METAL=OFF`, skips
  the Metal-compiler check, defaults its prefix and scratch to `.deps/install-cpu` and `.deps/work-cpu`, and
  writes `Metal OFF` into the prefix's `mlxf_deps.txt`. Cold start verified: `scripts/ci_cpu_job.sh Debug
  gfortran-16 --jobs 12` with `MLXC_ROOT` at an empty scratch prefix built MLX v0.32.4 and mlx-c v0.8.0 without
  Metal (66 s wall), passed the fast gate 13 of 13 with `Metal backend: F`, 5 GPU-only skips and 0 no-device
  skips, and passed `scripts/check_install.sh` against the new prefix (default device cpu). The CI cache key
  already hashes `scripts/build_mlx_deps.sh`, so this change forces a cold build on every runner once.
- **F2, fixed.** `run_all_distributed_ring_tests` expects the ring backend to build the `mlx_sum_scatter` node
  (status 0, shape (3, 1)) and to refuse its evaluation with a status, then runs the peer messages. Two Release
  processes on the review's `ring.json`: 14 of 14 assertions each, exit 0. The binding contract policy (section
  on distributed groups) and the parity plan's runnable example say that the ring refuses sum-scatter; the
  share is tested on the group of one (`unit_distributed` 55 of 55). Debug and Release with `MLXF_WERROR=ON`
  build without warnings; both fast gates 13 of 13; `scripts/check_tree.sh` passes.

## Scope and comparison bases

The delta is **`0071f5a..b2c43a4`**: 146 changed files, 22,292 insertions and 1,529 deletions, including
documentation. Inspection covered the new public random, transform/custom-derivative, export/import,
fused-layer, file, stream and distributed wrappers; their C-signature helpers and ownership paths;
the runtime additions; the ABI generator/probe; packaging and CI; the toy host/device separation and
the previous review fixes. Tests, policies, plans and run reports were checked against these changes.
The new K3–K7 documents describe future work; they are not evidence of delivered kernels. Unchanged code
retains the scope and limitations of the earlier reviews.

| Comparison source | Revision/version | Use |
| --- | --- | --- |
| mlx-fortran | `b2c43a4` | Reviewed implementation, tests, scripts and contracts |
| Local MLX | `5996d291ee88db9535b33eec458ca241428c0d2b`, 0.33.0 | Operation semantics, backend restrictions, lazy execution and build options |
| Local mlx-c | `a26f2d584a14ec619ae8db9a09be03becd47598a`, 0.8.0 | C signatures, ownership, status handling and forwarding to MLX |
| Executed libraries | MLX 0.32.4 / mlx-c 0.8.0 | Homebrew libraries linked by the fresh builds and probes |

The compiler was GNU Fortran **16.2.0**. Metal was visible for device validation: one GPU,
architecture **`applegpu_g15s`**. The source comparison and executed MLX versions differ as shown above.
No claim is made here about numerical or performance equivalence to a different MLX release.

The owner worktree was clean at the start. A fixed copy of tracked files was built under
`/private/tmp/mlxf-review3-src-b2c43a4`; both build trees, diagnostic objects and logs stayed under
`/private/tmp`. Only this report, its index entry and the history entry are review edits in the repository.

## Recheck of the four previous findings

| Previous finding | Evidence in this review | Status |
| --- | --- | --- |
| F1: NaN PCG histories pass error reductions | Re-injected a quiet NaN into the first reported update-history entry in a scratch copy of the current device engine. `pcg_solver` failed 2/86 assertions and `reconstructor_pcg` failed 20/192, on CPU and GPU. Finite-history checks and NaN-preserving scalar reductions are present. | Addressed |
| F2: switching reference route uses stale memos | Inspected the refusal in `set_ref_route` and the regression that tests both route directions after projection, memoization and bin preparation, comparing the resulting rows bitwise. Those tests passed in both full builds. | Addressed by refusal |
| F3: fused projector cache omits padded volume size | The cache key includes `self%m`. Independently reran the original 8-to-16 resize probe: reused and fresh fused projections had maximum difference exactly zero. The suite's graph comparison also passed. | Addressed |
| F4: lifecycle memory measurements race cleanup | Both samples now follow `mlx_synchronize()`. The affected lifecycle assertions passed in the fresh Debug and Release gates, each run with four CTest workers. | Addressed; the development report's 20-run campaigns were not repeated |

## Validation observed

| Check | Result |
| --- | --- |
| Fresh Debug build, `MLXF_WERROR=ON`, `FORTLS=OFF`, `MLXF_REQUIRE_GPU=ON` | Passed; no compiler warnings in the build log |
| Debug `ctest -L fast --output-on-failure --parallel 4` | 13/13 passed, 20.40 s wall time |
| Fresh Release build with the same options | Passed; no compiler warnings in the build log |
| Release fast CTest command | 13/13 passed, 13.81 s wall time |
| `scripts/check_tree.sh` | Passed |
| `scripts/check_install.sh <release-build> --require-gpu` | Passed: installed consumer, all three documented examples, private-module isolation, compiler/mlx-c version refusals and pkg-config consumer; CPU and GPU observed |
| `scripts/check_embed.sh --jobs 4` | Passed: parent configured, built and ran; importing a private module failed for the intended reason |
| `scripts/check_toy_offstate.sh --jobs 4 --exec <release-test-exec>` | Debug and Release built and ran without the library; the 135-line host output table matched the MLX-linked executable byte for byte |
| Cold CPU-only CI entry point | Failed before configuration: F1 |
| Unmodified two-process ring suite | Both ranks failed with exit 86: F2 |
| Scratch ring diagnostic with expected sum-scatter refusal | Both ranks passed 12/12 assertions |
| Previous-review NaN mutation and projector resize probes | Expected test failures for NaN; exact agreement for resized projector reuse |

The first off-state comparison attempt ran inside the sandbox: its standalone host builds passed, but
the comparison executable correctly failed its compiled-in GPU requirement. The complete check was
then rerun with Metal visible and passed. That environmental refusal is not counted as a code finding.

The full `release_gate.sh` orchestration and tagged-release mode were not run; the applicable build,
test, installation, embedding and off-state checks above were run separately against the fixed source
copy. No release-readiness claim rests on the development report's historical runs.

## Quality assessment and remaining limits

The delivered changes strengthen several areas that matter when comparing this binding with MLX and
mlx-c: explicit counted ownership, thin helpers around C signatures, independent numerical oracles,
checked failure paths, an ABI probe compiled with Apple's clang, and real consumer builds. The toy
separation now has direct evidence that its host code compiles and runs without MLX. The previous
numerical-validation blind spot is demonstrably closed.

The main remaining concern exposed by this review is validation of the delivered revision. A green
Metal gate cannot establish that CPU-only CI can bootstrap, and a singleton collective test cannot
validate communication between peers. Fix F1 and F2 before treating the corresponding new coverage
as complete. No further actionable wrapper defect was confirmed in this pass.

This review did not run a CPU-only MLX build, the hosted CI matrix, Linux, another Fortran compiler,
multi-machine distributed jobs or another distributed backend. It did not repeat the complete mutation
campaign, timing benchmarks, or all optional scientific suites. The parity report's other explicitly
unverified cases—including stream attribution, cross-device exported functions and a successful Metal
capture—remain unverified here. This review does not authorize or validate integration into SIMPLE.
