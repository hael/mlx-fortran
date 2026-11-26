# Follow-up code review: K1, K2, K8 and the review fixes

Reviewed 2026-11-25 at **`0071f5abc88b48a06b114b8dd9c8fc1247821791`**. This includes the pull during the
review, including the completed K8 implementation. **Four new findings remain open.** The five findings
in the [earlier review](mlxf_quality_review.md) were independently rechecked and their fixes verified.
This is a review record, not an implementation plan; no implementation or test source was changed.

## Scope and comparison bases

The comparison is `c6ea867..0071f5a`: 84 changed files, including documentation. Detailed inspection covered
the weak-scalar, transfer and strided-view changes; test assertions, static rules and build gates; K1's
fused posterior tail; K2's projector, fused gather and device reference route; K8's PCG engine,
reconstructor, workspace, oracle integration and tests; and the associated benchmark and run records.
Unchanged library code retains the scope and limitations of the earlier review.

| Source | Revision | Use in this review |
| --- | --- | --- |
| mlx-fortran | `0071f5a` | Implementation, policies, plans, tests and delivered reports |
| Local MLX | `5996d291e`, version 0.33.0 | Scalar semantics, custom-kernel specialization, asynchronous execution and memory-test practice |
| Local mlx-c | `a26f2d5`, version 0.8.0 | Explicit array dtypes, custom-kernel configuration and memory-query forwarding |
| Local SIMPLE | `d354efee2` | Secondary comparison for the newly mirrored projector and PCG procedures |

Runtime checks linked the installed **MLX 0.32.4 / mlx-c 0.8.0**, with GNU Fortran 16.2.0. Thus the inspected
MLX source and the executed runtime differ. CPU and Metal execution were observed; the GPU reported
`applegpu_g15s`. These are correctness checks on this machine, not a reproduction of the M5 Ultra timing
results in the kernel reports.

After the pull, tracked sources were copied to `/private/tmp/mlxf-review2-src-0071f5a`, and fresh Debug and
Release builds were made from that fixed snapshot. Earlier builds begun before the pull are excluded from
the evidence below. The owner worktree was clean; all probes and modified diagnostic executables stayed
under `/private/tmp`. Only this report, the notes index and the history entry are repository edits.

## Status of the findings (2026-11-26, run `mlxf_toy_seam`, Phase 1)

Each fix came with its regression test, shown to fail without the fix; the record is the Progress of
[`mlxf_toy_seam.md`](../planned/mlxf_toy_seam.md).

- **F1: fixed.** `history_errors` returns +infinity when a history is missing, short or not finite, and reduces with
  `nan_maxval`; `mlxf_test_reduce` gained the scalar `nan_max`; rule `nanmax` now also fails on
  `x = max(x, abs(...))`, and the 112 statements it found under `src/test` are converted. Thirty more are in five
  testers under `src/core`, held by the rule's ledger and left for a change that may edit `src/core`. The review's
  mutation now fails `reconstructor_pcg` (20 of 172 checks) and `pcg_solver` (2 of 86).
- **F2: fixed by refusal.** `set_ref_route` refuses a change once a reference is memoized (until `kill` and
  `new`); six cases (both directions, after the projection, `memoize_refs` and `memoize_ref_bins`) are refused and
  leave the rows bit for bit as they were.
- **F3: fixed.** The padded box is in the fused gather's cache key; one workspace taken from an 8-cube to a 16-cube
  equals a fresh one bit for bit and agrees with the graph form within the fixtures' gate.
- **F4: fixed.** `test_lifecycle` synchronizes before both samples; the Release fast gate with `ctest --parallel 4`
  passed 20 times of 20 (the base failed once in 20 at this assertion).

## Findings

| ID | Priority | Finding | Impact |
| --- | --- | --- | --- |
| F1 | P1 | PCG history error reductions accept NaNs | Corrupt reported histories pass numerical validation |
| F2 | P2 | Switching memoized device references to the host route uses stale host memos | Successful calls produce incorrect dense-score rows |
| F3 | P2 | The fused projector cache omits the padded volume size | Reusing the workspace at another size silently gives incorrect projections |
| F4 | P2 | The PCG lifecycle test samples active memory before stream cleanup completes | The unmodified Release fast gate fails intermittently |

P1 means the validation defect should be addressed before treating green results as trustworthy evidence.
P2 means a reproduced correctness or reliability defect to fix in the next relevant batch. These findings
are in the test-only scientific kernels and their checks, not in the installed `mlxf` API.

### F1 — Reject nonfinite PCG histories before reducing their errors

**Location:** [mlxf_toy_reconstructor_pcg_tester_solve.f90](../../../src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90),
`history_errors`, lines 126–133; related enforcement in
[check_rules.py](../../../scripts/check_rules.py), lines 958–971.

The new comparator starts each error at zero and repeatedly computes:

```fortran
e(1) = max(e(1), abs(real(oc%rel_residual_history(k), real64) - hist(k)))
e(2) = max(e(2), abs(real(oc%rel_update_history(k), real64) - step(k)))
```

With this Release compiler, a NaN operand can be ignored by scalar `max`. The earlier shared-helper fix
uses `nan_maxval`, but the new scalar accumulation bypasses it. The static rule recognizes
`maxval(abs(...))` only; the complete static gate passes this code. Bitwise repeatability also accepts
a consistently corrupted NaN payload.

**Reproduction:** in a separate copy of the PCG engine, immediately after assigning
`outcome%rel_update_history = xhist(1:n_done)`, add:

```fortran
if( n_done > 0 ) outcome%rel_update_history(1) = transfer(int(z'7fc00000'), 0._real32)
```

Relink that object into a separate Release test executable, leaving the numerical solve and all assertions
unchanged. Run `test=unit_kernels suite=reconstructor_pcg` and `suite=pcg_solver` on both devices.
**Observed: 152/152 and 84/84 checks passed, respectively, exit status 0.** The mutation corrupts a reported
history entry, not the iterate itself; the claim is that this corruption escapes validation.

**Recommendation:** check allocation, required lengths and finiteness of both histories, then reduce the
error vectors with `nan_maxval`. Audit scalar `max` error accumulations as well as `maxval` uses, including
the named-size history check and benchmark error summaries. Add negative controls that inject one NaN at
the beginning, middle and end of each history and require failure at the executable boundary. The existing
shared-helper fix should be retained; it correctly rejects the original review's injected NaN.

### F2 — Preserve reference provenance when changing routes

**Locations:** [mlxf_toy_polarft_core.f90](../../../src/test/mlxf_toy_polarft_core.f90), `set_ref_route`,
lines 217–232; [mlxf_toy_polarft_memo.f90](../../../src/test/mlxf_toy_polarft_memo.f90), `memoize_refs` and
`memoize_ref_bins`, lines 298–321 and 348–380.

Once `memoize_refs` clears `l_refs_pending`, `set_ref_route(host)` accepts a switch from the device route.
It invalidates the bins generation but does not transfer the device memos into `ft_ref`/`ft_ref2`, nor
require new projected references. The next `memoize_ref_bins` selects the host constructor and reads those
host arrays. In a new calculator they still contain zeros; in a reused one they can describe older
references. The calls report success and the bins are marked current.

**Reproduction:** reuse the existing `projector_chain` fixture and assertions, adding this call in
`chain_once` immediately after successful device-route `memoize_refs`, before building the bins:

```fortran
call pftc%set_ref_route(POLARFT_REF_ROUTES%host)
```

Only the caller sequence was changed in the scratch tester; the implementation was unmodified. The switch
returned an empty message. **Seed 1 row error became `6.555939611e-1` against a gate of `8.336e-7`.** The
same failure occurred for the graph form on CPU and GPU and the fused form on GPU, for all three seeds:
9 failed assertions out of 75. The checks that every API step succeeded still passed. Unswitched host
runs remained within their original gates.

**Recommendation:** either carry the current reference data across the transition, or explicitly refuse
the transition until references are reprojected through a supported lifecycle. Invalidating only the bins
generation is insufficient. Test both transition directions after projection, memoization and bin creation;
a transition must preserve the rows or give an explicit refusal. The current test covers a switch while
sections are pending, but not a switch after they have been memoized.

### F3 — Include volume size in the fused gather's specialization key

**Location:** [mlxf_toy_projector_workspace.f90](../../../src/test/mlxf_toy_projector_workspace.f90),
`transform`, lines 125–130, and `fused_tile`/`gather_spec`, lines 394–417.

The cached kernel is keyed by `[npts, tn, tg]`, but `gather_spec` also specializes it with `E = m + 5` and
`L = m/2 + 2`. `transform` can replace the volume and change `m` without clearing `kern`/`kern_conf`.
Projecting the same points and tile size after a resize therefore uses the old cube strides and origin.

**Reproduction on Metal:** use one `projector_workspace` in fused mode. Transform and expand an 8-cube
containing one unit voxel at `(2,1,1)`, then project two points. Repeat on that workspace with a 16-cube
containing the same unit voxel. Compare its second result with a fresh fused workspace on the 16-cube.
Use `pftsz=2`, `nk=1`, `kto=2`, `nspace=noris=1`, `refs_shape=[2,1,1]`, polar points `(1,0)` and `(0,1)`,
and the first two rows of the identity rotation.

All three projection statuses were zero. The reused workspace's second sample was approximately
`(-1.055957633e-3, 2.634020057e-4)`, while the fresh workspace returned
`(1.907133614e-3, -5.818886497e-13)`. **Maximum complex absolute difference: `2.97477562e-3`.**

This is a workspace-reuse defect. The normal `projector%new` path kills its workspace, so callers that
always recreate the projector are protected. The workspace type and its `transform` procedure are public
within the test-only modules; there is no enforced fixed-size lifetime at that boundary.

**Upstream comparison:** MLX's `mlx/backend/common/custom_kernel.cpp`, lines 314–350, includes template
arguments in the generated kernel identity; mlx-c's `mlx/c/fast.cpp`, lines 546–566, forwards the configured
template arguments on application. Upstream cannot repair a wrapper that continues to supply its old
configuration.

**Recommendation:** add `m` to the local cache key, or invalidate the cached kernels when `transform`
changes it. Test two valid volume sizes through the same workspace against fresh workspaces and the graph
form. An explicit refusal of resizing would also prevent silent wrong results if that restriction is chosen.

### F4 — Synchronize before comparing active memory in the PCG lifecycle test

**Location:** [mlxf_toy_reconstructor_pcg_tester.f90](../../../src/test/mlxf_toy_reconstructor_pcg_tester.f90),
`test_lifecycle`, lines 395–415.

The test copies the result, kills the reconstructor and output, then immediately samples
`mlx_active_memory()`. It repeats the sequence 100 times and requires the two samples to match exactly.
There is no stream synchronization before either measurement. Evaluating/copying the result does not
establish that all command-buffer references to temporaries have been retired.

**Observed without modifications:** the fresh Release fast run failed this assertion in `unit_kernels`:
1,731 of 1,732 kernel checks passed, and CTest reported 8/9 passing groups. Debug passed 9/9. A subsequent
standalone run of the unchanged Release reconstructor suite passed 152/152, demonstrating that the first
failure cannot be dismissed as a stable deterministic numerical failure.

A scratch tester retained the original assertion and recorded each immediate sample and another sample
after `mlx_synchronize()`. On the GPU, it observed:

| Measurement | Before the loop | After 100 cycles |
| --- | ---: | ---: |
| Immediately after release | 368,644 B | 384,776 B |
| After synchronization | 2,048 B | 2,048 B |

The original assertion failed again. The CPU samples were 2,048 B throughout. This demonstrates a
measurement race in this case, rather than retained memory after synchronization; it is not a general
proof that every lifecycle is leak-free.

**Upstream comparison:** MLX's `tests/gpu_tests.cpp`, lines 632–645, synchronizes before both active-memory
samples in its equivalent test. mlx-c's `mlx/c/memory.cpp`, lines 20–22, simply forwards the allocator query;
the Fortran query likewise does not imply a wait.

**Recommendation:** synchronize the relevant stream before both baseline and final samples, after releasing
the temporary objects. Keep the exact equality and live-handle assertions. Recheck Debug and Release under
the normal parallel CTest gate; weakening the memory tolerance would conceal the synchronization problem.

## Verification of the previous findings

| Earlier finding | Result at `0071f5a` |
| --- | --- |
| R1: shared numerical comparator accepts NaNs | Fixed at that location. The original `[1, NaN, 3]` case now returns positive infinity on CPU and GPU. F1 is a new scalar-reduction instance of the same failure class. |
| R2: incomplete CTest run passes the build gate | Fixed. A mock CTest printed one passing result then exited 42; the parser rejected the incomplete transcript and `run_fast_gate.sh` exited 1. The parser self-checks also ran as part of the passing static gate. |
| R3: weak half scalars promote to float32 | Fixed. Evaluated addition and `max` with `0.1_real32` retained float16 and bfloat16 dtypes on CPU and GPU. The expanded math tests passed in both builds. |
| R4: `add_subdirectory` uses the parent's paths | Fixed for the reported configure/build defect. `check_embed.sh --jobs 4` configured and built the library in its scratch parent project. |
| R5: equivalent macOS install paths compare unequal | Fixed. The full install check passed with the default `/var/folders/...` temporary path, including CMake and pkg-config consumers on CPU/GPU, module isolation and compiler-mismatch refusal. |

## Build and test evidence

Both builds used `-DFORTLS=OFF -DMLXF_WERROR=ON`, four build jobs and fresh build directories. Both completed
without compiler warnings. CTest set the repository's environment, including `MLX_ENABLE_TF32=0`,
`OMP_NUM_THREADS=1`, `OMP_WAIT_POLICY=PASSIVE` and `OMP_THREAD_LIMIT=4`. Targeted runs used the same settings.
GPU-dependent checks ran with actual Metal visibility; sandbox attempts that could not open a GPU are not
counted as passes.

| Check | Observed result |
| --- | --- |
| `scripts/check_tree.sh` | Passed |
| Debug `ctest -L fast --output-on-failure --parallel 4` | 9/9 passed; 22.99 s |
| Release same CTest command | **8/9 passed; 13.80 s; lifecycle assertion failed (F4)** |
| Unmodified Release `test=unit_kernels suite=reconstructor_pcg` rerun | 152/152 passed; 3.99 s; does not erase the original failure |
| Unmodified Release `test=unit_kernels suite=reconstructor_pcg_n32` | 96/96 passed on CPU/GPU; 103.38 s |
| `scripts/check_embed.sh --jobs 4` | Passed |
| `scripts/check_install.sh <release-build>` | Passed in full |
| Scratch NaN-history mutation | Incorrectly passed 152 reconstructor and 84 engine checks (F1) |
| Scratch caller with device-to-host route switch | 9/75 chain checks failed; switch itself succeeded (F2) |
| Reused fused workspace versus fresh workspace | Status 0 but differing results (F3) |
| Scratch lifecycle instrumentation | Immediate memory differs; synchronized memory matches (F4) |

Reproduction build directories are `/private/tmp/mlxf-review2-0071f5a-debug` and
`/private/tmp/mlxf-review2-0071f5a-release`. Configure/build/CTest logs use those prefixes with
`-configure.log`, `-build.log` and `-ctest.log`. Additional logs are
`/private/tmp/mlxf-review2-0071f5a-{static,embed,install}.log`. Probe sources, build helpers and logs are in
`/private/tmp/mlxf-review2-probes/`, notably `nan_history/`, `route/`, `lifecycle/`, `reuse.f90`,
`prior_findings.f90` and `interrupted-gate.log`. These temporary files are review-session evidence, not
durable repository test assets; the triggering changes and results are recorded above.

## Assessment and limits

The earlier binding and build-gate fixes are effective. The new kernels have independent oracles,
explicit device/form comparisons, fixed seeds, repeatability checks and documented decisions. No additional
reproduced defect was established in the K1 fused tail or the changed installed-library routines.

The main remaining weakness is state-transition and failure-detection coverage: the tests exercise fresh
objects and fixed routes well, but miss accepted transitions that produce stale state, while one new
comparator can accept nonfinite output. F4 also shows why device lifetime tests should follow upstream's
explicit synchronization practice. These four cases deserve focused regression tests before adding more
kernel variants.

The K8 R1/R2 rulings deliberately judge production's two/five iterations and report, rather than gate,
some long-run convergence and n=32 stop-iterate differences. The named n=32 pass above does **not** mean
those reported differences meet the original stricter gates; the review did not treat the owner's approved
changes of criterion as bugs. A stale `reconstructor_pcg%message()` after a recovered solve was also
observed, but its documented meaning is the last refusal, so it is not counted as a correctness finding.

The reported M5 Ultra speedups, large n=160/256 memory measurements, simultaneous-part timing and
cross-invocation benchmark repeatability were reviewed as recorded evidence, not rerun here. Linux,
alternative Fortran compilers, sanitizers, and runtime parity against a locally built MLX 0.33.0 were not
validated. Release-hardening work already planned remains planned; this review does not certify a release.
