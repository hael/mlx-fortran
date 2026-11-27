# User-facing hardening: consolidated review and prioritized plan

Status, 2026-11-27: **Phases 0 to 6 delivered; second-architecture validation closed.** The M5 Ultra
(`applegpu_g17d`, original run under rulings R0 to R2) and M2 Ultra (`applegpu_g14d`, verified follow-up) satisfy
decision 12's architecture coverage. The C11 benchmark correctness fix is also validated. RB1 (empty host-array
constructors) is closed (2026-11-27, Hans's ruling (a): `mlx_from` refuses an array of unknown size, guard
`guard_from_unknown_size`); RB2 (a clean tagged release gate) is withdrawn: when to tag a release is the maintainer's decision, outside the plans (hans, 2026-11-27). The plan
stays in `planned/` for the deferred follow-ups (C7, documented limits, residual test gaps). Report: [`completed/mlxf_user_hardening_report.md`](../completed/mlxf_user_hardening_report.md).
Originally planned on 2026-11-26 at Hans's request.
Written against `96c5c5c272af7b688047f841897dfc98e9f30fdf`, with the existing working-tree RoPE test adjustment
and Claude review. The implementation pins its actual base in Phase 0. Supersedes: no implementation plan;
this note is the single owner of the two user reviews' follow-up work. Related work:
[refactoring](mlxf_refactor.md), [release hardening](../completed/mlxf_release_hardening.md), and
[kernel-form measurements](mlxf_kernel_forms.md). No simultaneous edits to their shared files.

## 1. Why and consolidated findings

The installed package and normal numerical paths work, but ordinary user code can receive incorrect integer
statistics without an error, lose a checkpoint on a failed save, read out of bounds, or leak through accepted
Fortran syntax. Correctness and data preservation come before convenience and broader adoption. A documented
restriction can still be a serious adoption risk; it is distinguished below from an implementation defect.

**Sources and limits.** Claude's [review](../completed/mlxf_user_review.md), findings U1–U10, is preserved as
written. Its programs are in `~/for_claude/mlxf_user_review_2026-11-26/`. Codex's independent investigation is
recorded here as N1–N4, corresponding to sections 1–4 of
`/tmp/mlxf_codex_user_review_2026-11-26/REVIEW.txt`; its sources, direct mlx-c reproducer and logs are in that
directory and `review_bundle.zip`. These external paths are evidence locations, not build dependencies: the
essential fixtures and observations below survive their removal. Phase 0 admits durable reproducers and tests
with the fixes. No claim is made about the current status of an upstream issue beyond the versions observed.

Codex built and installed Release and Debug with GNU Fortran 16.2.0, MLX 0.32.4 and mlx-c 0.8.0 on macOS
26.7.3, GPU architecture `applegpu_g14d`, with `MLX_ENABLE_TF32=0`. The static gate, all 13 Release fast entries
(40.21 s) and the installed-package checks passed. Fifty-five external cases per build had identical exit
classifications: 34 zero, 21 nonzero, including deliberate guards and reproduced defects, not 21 independent
bugs. The full Debug CTest suite was **not** run in that investigation. Normal slices and updates (1,120
combinations per device/build), factorization residuals, supported output-list lifetimes, singular-solve
recovery and truncated-file refusal passed. No library code was changed by that review.

Priorities below are user impact, not an allegation that every behavior violates the current contract.
"Library" is work mlx-fortran can deliver; "upstream" identifies the cause or capability owner. A local
mitigation need not wait for upstream, and an upstream report does not close the local item.

| ID / priority | Consolidated evidence | Cause / current contract | Library work | Upstream work | Documentation / closure |
| --- | --- | --- | --- | --- | --- |
| C1 / P1 | N1: a constant 1024×1024 int32 image of 4096 gives mean 0 and variance 16777216, both status 0. Two values of 2000000000 give mean -147483648 and variance about 4.61168602e18. Both devices/builds; direct mlx-c reproduces | MLX accumulates the mean in an integer kind before floating normalization; variance inherits the bad mean. Supported input, incorrect mathematics | Promote integer inputs before `mlx_mean`, `mlx_var` and `mlx_std`; test every overload and integer dtype; preserve the documented result dtype | Apple question 33; direct C reproducer and explicit-cast control | Explain input versus accumulation precision; exact fixtures pass and regress when the fix is removed |
| C2 / P1 | N2: replacing a valid 96-byte safetensors checkpoint with float64 returns failure and leaves 0 bytes; GGUF has the analogous earlier report | Upstream writer opens/truncates before dtype validation; explicitly documented in contract §17 | Preflight dtype and structure; make array saves replace the destination only after successful writing to a temporary sibling | Existing Apple question 31(a), not a duplicate issue | Distinguish failure preservation from power-loss durability; original bytes survive each failed write |
| C3 / P1 | U1, independently reproduced: index 6 of a five-element array returns zero/status 0; index 1000000 crashes on CPU and returns zero/status 0 on GPU | Upstream unchecked indexing; contract delegates validation to caller. Invalid-input memory hazard, not a valid-index regression | Explicit checked validation for untrusted indices, preserving the existing lazy route; include slab bounds and avoid overflow in validation | Apple question 35: document the unchecked behavior and ask about checked support | First-page examples validate once at the input boundary; no clamping that silently changes the request |
| C4 / P1 | U2: 1000 iterations with `[a, exp(b)]` leak 1000 handles and about 250 MiB; function results assigned to whole handle arrays leak too. Supported forms pass | gfortran finalization defects, **not MLX**; unsupported uses in contract §3 and design decisions 8/39 | Ship consumer-side lifetime diagnostics based on existing `ctorcall`/`ctorexpr`; cover whole-array result assignment and borrowed temporaries where statically identifiable | GCC reproducers and existing-report deduplication under `doc/compiler_issues/README.md` | Safe spelling beside each hazard; explicitly state limits of static analysis and runtime counters |
| C5 / P2 | N3: float32 norm2 of two 1e20 values is infinity, of two 1e-30 values is zero; CPU float64 similarly at 1e200/1e-200. Mean of two 2e38 float32 values is infinity; all status 0 | Backend intermediate overflow/underflow; supported finite inputs with representable answers | One robust implementation for Euclidean norms and floating means, tested for range, zero and non-finite inputs; measure its cost | Apple question 34; distinguish measured Fortran results from direct C verification still to be added for this item | Dtype, range and accuracy are separate guarantees; finite-domain correctness is gated |
| C6 / P2 | N4: maxval/minval of shape (0,3), dim=1, stop with 86; native Fortran returns identity values. Sum/product and maxloc/minloc already handle emptiness | MLX semantics exposed under Fortran intrinsic names; empty static slices are separately disallowed by the documented bounds contract | Supply Fortran empty-extrema identities and preserve shape/kind; define empty slices separately, without weakening bounds checks | No upstream fix required for Fortran compatibility | Add empty-array rows; empty mean/variance NaN is a mathematical edge case, not the same bug |
| C7 / P2, P1 for embedding | U3: graph-construction errors terminate; `status` at later evaluation cannot catch an earlier stop | Deliberate library error policy, design decision 12; not an MLX exception escaping accidentally | Design a bounded checked graph-building API, starting with construction, slicing and arithmetic; decide concrete signatures before implementation | No prerequisite upstream change established | Error-phase table and host-embedding example; retain existing fail-fast operators, reject global "record and continue" |
| C8 / P2 | U5: float64 GPU operations stop; some CPU operations keep float64 storage at float32 accuracy; FFT changes dtype; real64 solve is accurate in the observed fixture | Mixed hardware limitations and MLX implementation choices; documented in scattered sections | No silent device/dtype fallback; capability examples and explicit dispatch guidance | Existing questions 8 and 24; recheck any claimed newer-version fixes before citing them | One precision/device matrix: storage, result dtype, arithmetic accuracy and execution device |
| C9 / P2 | U6: `a+1`, `2*a`, integer-array + integer scalar, direct printing, host `if(all(...))`, subscripting syntax and complex(real64) transfer fail to compile | Missing overloads plus deliberate array-handle semantics; complex128 backend support is absent | Add default-integer arithmetic/comparison scalars with specified weak promotion. Evaluate explicit print/host-test helpers only after their sync/error contract is written | Complex128 is an upstream capability request, not a Fortran overload fix | Compile/run examples for supported spellings; keep reductions lazy, show `mlx_item` for host decisions |
| C10 / P2 | U4: a long unevaluated recurrence reached Metal's resource limit near 250000 operations in Claude's probe; not independently rerun by Codex | Graph retains intermediates/scalar buffers; hardware/version/workload resource limit, not a universal step threshold | Bounded-evaluation example and memory instrumentation; no hidden automatic evaluation inside operators | Document/backend inquiry if a minimal resource-limit report adds information; no promised limit increase | Teach evaluation at application batch boundaries; never publish 250000 as a safe limit |
| C11 / P2 guidance | U7: Claude measured about 181 µs per tiny GPU evaluation, 21 µs per scalar read and 14 GB/s copies on its machine | Cost of dispatch/synchronization/copies, not correctness defects or portable performance guarantees | Reuse the benchmark infrastructure for batching, transfers, views and compilation; coordinate with ranks 2d/2f | Escalate only a reproducible backend anomaly, not the existence of overhead | A measured cost model with hardware, size, cold/warm state and boundaries; avoid claimed BLAS replacement speedups |
| C12 / P3 | U8: name tables but no procedure reference; maintenance history dominates; generic install guide is named for SIMPLE | Library documentation and tooling | Source-derived signature/reference generation after rank 2d, reusing its public API inventory | None | General-user landing page, searchable arguments/kinds/errors, tested examples; keep old install links working |
| C13 / P3 | U9: GNU Fortran, exact producer/consumer compiler version, platform and one-submitting-thread restrictions | Deliberate compatibility/ownership policy, not failures to detect | Keep existing checks; no threading, compiler or platform expansion in this plan | Track compiler defects separately; no MLX ticket for the exact-compiler policy | Put the compatibility matrix and OpenMP consequence before installation |
| C14 / P2 | U10: RoPE test bound calibrated on M5 failed on M2; owner's existing adjustment is in the tree | GPU-dependent backend numerical behavior plus insufficient validation coverage | Adversarial fixtures and release evidence on two GPU architectures; preserve the owner's change and its attribution | Existing Apple question 32 | Separate measured backend differences, mathematical bounds and supported-device claims; do not loosen unrelated tolerances |

### What checking the code changed

- `mean_array/mean_dims`, `var_array/var_dims` and `std_array/std_dims` in `mlxf_ops_reduce` delegate directly
  to MLX; integer mean's output kind is tested, but the large-total fixtures above are absent. The fix belongs
  with these operations, not in the general integer `sum`, which keeps its current semantics.
- `norm2_dim/norm2_dims` in `mlxf_linalg_matrix` delegate to MLX's norm. Their normal-range tests do not
  establish range robustness. General p-norms, gradients at zero, and complex magnitudes need separate checks.
- `mlx_save_safetensors` validates names and metadata but calls the writer before any dtype preflight;
  `mlx_save_gguf` has the same exposure. `mlxf_libc` has no temporary-file/rename support yet. Array saves and
  function export have different lifecycles; do not claim that fixing one fixes the other.
- Bounds shifts are centralized in `mlxf_zero_based`, but that helper has no source extent or slab size.
  It cannot implement a correct universal bounds check by itself.
- Existing lifetime rules inspect repository sources; `check_rules.py` has no supported arbitrary-consumer
  entry point. Its analysis is a starting point, not a complete Fortran parser.
- Apple question 31 already owns save truncation, 32 owns RoPE, 8/24 own precision limitations. GCC reporting
  has its own policy. Current upstream issue status was not searched for this planning change.
- Rank 2d will move the signature helpers, transfer code, operations and test infrastructure. The file table
  below names current owners and requires remapping to their delivered locations before implementation.

## 2. Contract and scope boundaries

The binding policy remains the current truth until an implementing phase updates it. Preserve column-major
layout, one-based public dimensions, handle ownership, the one-submitting-thread rule, explicit device
selection, lazy operators, checked C statuses, one library target and `mlxf.mod` as the sole installed module.
No new mutable global policy or library environment variable is introduced. No implicit evaluation is added
to ordinary indexing or arithmetic. Checked validation evaluates only when explicitly requested.

The existing unchecked indexing path keeps its results and scheduling for valid input. Supported lifetime
forms keep their live-count and memory guarantees. Unaffected numerical paths retain their existing tests;
changed arithmetic is judged against independent oracles, not against known-wrong baseline bytes. Intended
result changes are limited to C1, C5 and C6, plus newly admitted scalar overloads. Failed saves preserve old
content; valid output bytes and lazy-load rules remain compatible. No toy default or scientific policy changes.

Dependencies: the reviewed baseline and installed consumer (validated: yes); reusable signature helpers and
status machinery (yes); consumer checker extraction, transactional save helper and checked-index API (not
implemented); rank 2d's resulting layout/API inventory (planned, not validated here); second-architecture
release access (must be confirmed, not inferred from a prior report).

## 3. Decisions and recommendations

Decision 1 records a user instruction. Decisions 3 to 9 were **ruled as recommended** by Hans on 2026-11-26
("Yes, as recommended", on the list: integer statistics in float32; saves through a temporary file renamed into
place, symlink destinations refused and permissions kept; a public index validator returning a status, no
automatic check; a consumer lifetime checker; scaled norms and empty extrema; default-integer scalar operators;
recoverable graph construction as a design with examples only). Decisions 2 and 10 to 13 stand as recommended.
The implementation records any later amendment here before changing a public contract.

1. (2026-11-26, Hans) Consolidate both reviews and write a prioritized plan distinguishing library,
   upstream and documentation work. Deliver this note and its index/roadmap/history links; no fixes launched.
2. **Order.** Phase 0 puts urgent guidance beside the reproductions; Phase 1 fixes statistics and saves;
   Phase 2 supplies index/lifetime safeguards; Phase 3 fixes numerical range and empty extrema; Phase 4 handles
   small API improvements and the recoverable-error design; Phase 5 completes the reference and cost guide;
   Phase 6 closes release validation. Draft upstream reports alongside the owning phase, never on its critical
   path. Recommend Phases 0–2 before another public release. Rank 2d's existing implementation slot is not
   silently displaced: serialize source work immediately before it if unstarted, otherwise remap after it.
   Ranks 2d→2e→2f retain their relative order; performance/reference work consumes their results.
3. **Integer statistics.** Promote all signed/unsigned integer and boolean inputs to the documented float32
   result domain **before** mean/variance/std arithmetic. Leave real/complex dtype policy unchanged. No hidden
   float64 GPU fallback. Test int64/uint64 rounding as floating conversion, not a promise of exact integer
   statistics beyond float32's precision. `sum` and `product` do not change.
4. **Array-save transaction.** Strengthen existing `mlx_save`, `mlx_save_safetensors` and `mlx_save_gguf`
   without changing their call signatures: preflight, create a unique temporary sibling, write successfully,
   then rename into place. Resolve `.npy`'s implicit suffix once before choosing paths; cleanup never removes
   the destination. Use libc bindings only through `mlxf_libc`, no shell commands or global counter. Specify
   symlink/permissions semantics before implementation; recommend refusing symlink destinations, preserving
   existing regular-file permissions, and refusing targets that cannot be replaced safely. Atomic replacement
   means preservation on a returned failure, not an fsync/power-loss durability promise. Incremental
   `mlx_function_exporter` is outside this change and retains its separate incomplete-file warning.
5. **Explicit index validation.** Recommend a checked preflight API returning `status` for one-based element
   indices and slab starts against caller-supplied extents/sizes, with a spec record if needed to stay within
   five arguments. It evaluates validity once and lets callers reuse unchanged validated indices. Empty index
   lists are valid; nonempty indices into extent zero are not. Cover signed/unsigned kinds without narrowing;
   compare a start with `extent - slab_size + 1` only after validating extents/sizes. Index 0 is rejected here
   even though existing unchecked indexing wraps it. No global bounds toggle, implicit clamp, or automatic
   check at every kernel call. Freeze signatures and tracing restrictions in Phase 2 before implementation.
6. **Lifetime tooling.** Extract reusable analysis shared by the repository rules and an installed consumer
   checker; do not fork two implementations. Python standard library, 3.7+, caller-selected files, optional
   CMake invocation. Diagnose known patterns with file/line and safe alternatives; document aliasing,
   preprocessing and incomplete type-information limits. Cover constructors, whole-array function assignment,
   allocatable-component copies, overlapping assignments and borrowed temporaries in the coverage matrix;
   classify unsupported detection explicitly. Never promise that a clean lint proves a program leak-free.
7. **Range/empty semantics.** Replace the Euclidean norm computation with a scaled form that handles zeros,
   empty reductions, complex values and NaN/Inf explicitly; preserve laziness and result shapes/kinds. Address
   overflow of floating means in the same numerical phase. Do not retain a numerically wrong "fast" default
   as a second path. Define zero-size maxval/minval identities in the operand dtype and shapes as Fortran;
   device-only dtypes need an explicit extrema mapping. Empty-slice semantics are a separate design item;
   do not admit out-of-range nonempty slices to make an empty example pass.
8. **Scalar usability.** Add default-integer `+ - * / **` and comparisons, both operand orders. Integer-array
   promotion remains integral where MLX defines it; real/complex arrays follow weak-scalar rules. No conversion
   of an integer scalar through real32 before an integer operation. Freeze a matrix including values outside
   a narrow dtype's range, boolean operands, division and exponentiation before coding; an unrepresentable
   weak scalar is diagnosed rather than silently wrapped. No change to existing real-scalar specifics.
9. **Recoverable graph construction.** Preserve current operators and their error stop 86 contract. Design
   checked procedure forms with explicit result/status for the small initial set in C7, no global error mode
   and no silent empty-result propagation. Include callback safety, output state on failure, message lifetime
   and recovery in the contract. This phase delivers the design and examples/prototypes; implementation of a
   second public graph-building surface requires a recorded API decision here. Printing or host logical
   helpers likewise must declare their evaluation boundary; existing `mlx_item` remains the documented path.
10. **Docs are part of each fix.** Phase 0 warns about present behavior; each implementing phase updates its
    policy and executable examples in the same change. Phase 5 generates signatures from source plus concise
    semantic annotations linked to policy sections, rather than maintaining a second hand-written contract.
    A dtype table distinguishes default Fortran real (normally real32) from scientific applications that
    deliberately use real64; do not call real64 the language's default.
11. **Upstream ownership.** Prepare minimal direct C reproducers for MLX, standalone Fortran ones for GCC;
    record version/device/flags, expected/actual result and a passing control. Existing questions are reused.
    Check the current upstream release and issue tracker before submission or dependency-upgrade claims;
    submission is not authorized by this planning request. GCC reports follow the maintainer-owned policy.
    A workaround is removed only after its regression fixtures pass against the adopted dependency version.
12. **Validation.** Keep the 13 CTest process budget: add assertions to existing area sub-suites and hard stops
    to the guard group. Add numerical-domain fixtures, not just more random samples from [-2,2]. Run Debug and
    Release, installed consumers and two distinct Metal GPU architectures before claiming release readiness;
    CPU-only CI remains a separate gate. Missing second-machine evidence leaves Phase 6 open.
13. **Performance.** The reported timings are measurements, not acceptance floors. Record before/after costs
    of added correctness work and an explicit-validator call; do not require a correctness fix to beat a wrong
    implementation. Any retained alternative implementation still needs the standing measured >30% gain.
    No promise of automatic acceleration for scalar loops, double precision, or CPU-only decompositions.

Defaults taken without a question: this note's name and C1–C14 identifiers; tests join existing areas;
upstream entries stay open/unsent. Public API names, semantics and queue changes are recommendations above,
not disguised implementation defaults.

## 4. Not in this plan

- SIMPLE integration or toy kernel changes, general BLAS replacement, new compiler/platform support,
  multi-threaded submission, global recoverable-error state, automatic graph evaluation or silent dtype/device
  conversion. Keep the established default FORTLS decision outside this work.
- A promise to implement float64 Metal, complex128, or MLX compiler fixes locally; a dependency upgrade without
  compatibility and numerical evidence; upstream submissions made on the user's behalf.
- A wholesale rewrite of handle ownership or a claim that lint repairs gfortran. No prohibition test may fail
  merely because a future compiler correctly finalizes a formerly broken form.
- A global change to all `mlx_norm` p-norm algorithms under the Euclidean-norm fix, or a claim that all save and
  function-export formats become transactional in Phase 1. Uncovered surfaces remain explicitly listed.
- Changes to the owner's current RoPE tolerance patch or skills. Any later need for skill changes is proposed
  separately; no edits to the importing `CLAUDE.md` files.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | Evidence/docs only | Base builds/gates recorded; exact defect fixtures fail on the base; urgent examples use supported forms |
| 1 | Result-changing and I/O failure semantics | Integer statistics against external references; original-file byte preservation; unit_ops/unit_io and installed consumer |
| 2 | Additive API/tooling; unchecked route unchanged | Validated bounds matrix, failing diagnostic plants and passing controls; no added wait without opt-in |
| 3 | Result-changing numerics/empty semantics | Dynamic-range and empty-shape fixtures; normal-range residuals, gradient checks for changed differentiable ops |
| 4 | Additive overloads; error API design | Compile/run promotion matrix; native Fortran generics unaffected; explicit design decision before error-API implementation |
| 5 | Docs/tooling/measurement | Reference coverage and stale-output check; executable examples; repeatable timing protocol, no speed pass/fail |
| 6 | Validation/report | Both builds, installed and CPU-only checks, two GPU architectures, unchanged test budget, no unresolved P1 local acceptance |

## 6. Acceptance and evidence rules

Numbers below are fixture definitions, derived mathematical answers or proposed bounds; historical timing
and memory observations are labelled *measured* in section 1. Freeze new numerical bounds in Phase 0 before
judging any fix. A calibration failure is diagnosed, never handled by increasing a tolerance until green.

| Item | Acceptance, reference and origin |
| --- | --- |
| C1 exact cases | Constant 1024×1024 int32 image 4096: mean 4096, variance/std 0; two int32 values 2000000000: mean 2000000000, variance/std 0. Values are exactly representable in float32 (*derived*). Test all/dim/dims, keepdims and a valid nonzero ddof; include signed cancellation and each supported integer dtype. Float32 conversion rounding for int64/uint64 is the stated oracle, not the overflowing integer sum |
| C1 general cases | Existing independent reduction oracle and its frozen bounds, extended to integer-domain fixtures converted once according to the contract. `std` must be covered even though the original reproduction measured mean/variance only |
| C2 failure preservation | Destination bytes identical before/after dtype, metadata/name, evaluation, write and rename failures; no partial destination on failure if absent initially; temporary cleanup checked. Success loads to expected values and preserves canonical output bytes. Non-hermetic disk-full scenarios use a deterministic test seam in the existing test executable, not a new public failure switch |
| C3 bounds | Exact accept/reject matrix: first/last valid element, 0, negative, extent+1, large signed/unsigned values, empty source/index, slab ending at boundary or one past, duplicates, lists of dimensions, invalid dtype/shape and overflow-prone starts. Invalid values never reach the memory-reading/writing operation after a failed preflight |
| C4 lifetime | 1000 rounds of each supported counterpart, active memory after synchronization/cache clearing and live counts equal to warm baseline (*fixture count*); static planted unsafe forms fail and safe equivalents pass. No required leak or crash on a compiler that fixes the upstream defect |
| C5 range | Two equal inputs at real32 1e20/1e-30 and CPU real64 1e200/1e-200: finite nonzero norm, oracle sqrt(2)*abs(x), relative error ≤8 result-kind epsilons (*derived conservative bound for the finite two-value scaled operations*). Real32 mean [2e38,2e38] remains finite and within 8 epsilons. Add mixed magnitudes, signed cancellation, zero, empty, NaN, Inf, complex and normal-range cases with predeclared scale-aware bounds; never use an absolute floor of 1 to pass a tiny expected norm |
| C6 empties | Shape (0,3) reduced over dim=1 yields three dtype-correct -huge/+huge identities; also scalar all-dimension and keepdims/list forms, non-reduced zero extents, integer limits and accepted device-only dtypes. Rank and shape exact; NaN mean/variance distinguished from rejected inputs |
| C9 overloads | `a+1`, `2*a`, integer array + integer scalar, both operand orders for each admitted operator; kind/value matrix, rank-0 and narrow-kind boundaries. Native host intrinsics continue compiling. Each accepted form previously lacking a specific is demonstrated as such on the base |
| Docs/tooling | Every U1–U10 and N1–N4 maps to a C row and a closure action. Every exported public name has a reference entry after Phase 5, including types/specs and links to bindings; unsupported parsing fails the generator. A planted source/API change fails the stale-reference check; every tutorial program builds against installed `mlxf` |
| Release evidence | Zero compiler warnings; static and fast gates; 13 CTest entries (*existing policy*), fast tier within its 60 s budget (*existing policy*); installed-package check; no fake GPU passes or missing-device skips counted as passes. Two GPU architecture identifiers with separate compiler/dependency facts and numerical logs (*proposed coverage requirement*) |

Use fixed seeds already owned by the test framework for general fixtures. Exact identity cases are run twice
on the base; affected scientific toy entries are measured twice before/after if their operations change.
Existing mathematical error bounds remain in force; known-wrong integer/range/empty outcomes are the explicit
exclusions from before/after identity. A fresh baseline is required after source movement or dependency changes.

## 7. Common rules and stop conditions

Preserve owner changes; git remains read-only and every implementation change stays unstaged. No hidden
global state, environment switch, unbudgeted test executable or private module installed. Follow the binding
and Fortran skills when implementing; libc calls stay in their owner, and signature helpers follow their
post-refactor owners. A new statically checkable rule gets a checker and a planted violation in the same phase.

Stop the affected implementation phase for a conflicting active edit, missing required device/fixture,
undecided public signature, a changed error/lifetime contract outside the numbered recommendations, a needed
file outside the table, a tolerance that would have to move, or a path by which a failed save can still damage
the original. Record the concrete finding and continue independent authorized work. Add/remap file-table rows
before editing, never infer approval for a broader API. Do not stop merely because a baseline defect is the
one this phase is meant to fix.

No ruling may waive correctness against the independent oracle, original-file preservation, supported-form
lifetime checks, checked C statuses, the one-thread rule, failing negative controls, or honest device evidence.
If two-architecture evidence is missing, local fixes can be reported separately; release readiness cannot.

## 8. Phases and file ownership

### Phase 0 — Preserve the evidence and publish immediate guidance

Pin the actual base and dirty-file manifest; reconcile with rank 2d and confirm access to the required devices.
Build Debug and Release with the fast and installed gates, record base failures separately, run affected toy
entries twice where appropriate. Reconstruct the exact fixtures above even if scratch archives have gone.
Prepare direct mlx-c controls for C1/C5 and GCC-only controls for C4. Check each new regression on the base;
keep failing reproducers outside the ordinary fast suite until their fix is in the same change.

Publish the present-day safety/precision/error boundaries and safe alternatives in the quickstart and contract:
explicit integer conversion before statistics, new filenames for checkpoints, validated indices, safe handle
lists, explicit evaluation in long loops and host extraction with `mlx_item`. Record backend reports in the
Apple/GCC trackers; no submission. The new mean/variance defect is not yet part of the policy and must be named.

**Exit:** baseline facts and acceptance bounds recorded here, all C rows assigned, reproducible fixtures admitted,
and immediate guidance/examples verified. An inaccessible GPU is named, not silently replaced by a skip.

### Phase 1 — Correct statistics and preserve checkpoints

Implement C1 at the reduction owner, sharing input preparation across mean/var/std without changing sum.
Implement C2 for the three array-save formats, with deterministic failure injection confined to tests. Test
valid saved bytes, dtype preflight, existing/absent targets, `.npy` suffixes, paths with spaces, temp cleanup,
rename failure, permissions and the declared symlink behavior. Keep function-export warnings explicit.

**Exit:** C1/C2 acceptance passes on available CPU/GPU in both builds, the regression fails with each fix
removed, current policies/examples match, and no unrelated result or serialization format changes.

### Phase 2 — Give consumers explicit bounds and lifetime safeguards

Freeze the validator's small public API, covering element and slab bounds; list which index-taking wrappers
its recipes cover (take/put, gather/scatter, dynamic slices, gathered/segmented products and class targets),
and which low-level operations such as `as_strided` retain a separate unsafe contract. Validate before compiled
tracing or untrusted-input ingestion; do not insert host waits into a traced callback. Reuse only unchanged
index values/extents after successful validation.

Extract and install the consumer checker with one shared analysis implementation. Add positive/negative
fixtures including renamed imports and compiler preprocessing limitations; test installation without access to
repository-private files. A list of undetectable forms remains part of its user contract.

**Exit:** C3/C4 acceptance passes; the old valid unchecked route adds no validation/evaluation; the installed
consumer can run the checker; diagnostics state the limits of what was checked. No upstream compiler fix needed.

### Phase 3 — Make numerical boundaries explicit and robust

Implement robust Euclidean norms and floating means, then empty extrema. Test all scalar/dim/list/keepdims
forms and preserve dtype/device choices. Test value/gradient behavior away from singular points for changed
graph compositions; state zero/non-finite derivative limits instead of assuming equivalence. Check ordinary
and extreme complex values without overflowing while computing the scaling magnitude itself. Measure new costs.
Record the empty-slice API decision here; documentation may be its chosen closure if a change is not justified.

**Exit:** C5/C6 mathematical, non-finite and shape cases pass; normal-range and affected toy checks retain their
existing bounds; local implementation cost is reported; the backend and Fortran-compatibility changes are clear.

### Phase 4 — Remove first-expression friction; design recovery deliberately

Freeze and implement C9's default-integer scalar matrix, with installed-consumer compilation coverage.
For C7, write concrete checked-procedure signatures, output/error rules, callback examples and a prototype
assessment into this same note. Record the decision to implement or defer each proposed host print/logical
helper; do not replace lazy reductions with eager host values. API expansion for checked graph construction is
an explicit recorded follow-up decision with its acceptance and file rows before any implementation.

**Exit:** admitted integer expressions compile and pass; existing expressions retain behavior; C7 has a concrete
reviewable design and disposition. A documented deferral is not called recoverable-error support, and that
adoption limitation remains visible in the final report.

### Phase 5 — Complete the user reference and explain the cost model

After rank 2d, reuse its API inventory for generated signatures and per-name reference coverage. Provide a
neutral installed-use entry point while keeping `how2use_from_simple.md` links valid. Move maintenance status
below the public use path. Add consolidated precision, errors, ownership, threading and compatibility tables.
Reuse existing benchmark infrastructure and rank 2f results; add only missing user-cost cases (batch evaluation,
scalar reads, copies versus allocation/views, warm compiled callbacks) with fixed fixtures and correctness
checks outside timing. Take at least three repeats after warm-up, report their range/median (*measurement
protocol*, not a speed floor), and label cold-start separately. Show a bounded lazy loop; no universal cadence.

**Exit:** C8/C10–C13 documentation is executable/current, full reference coverage/staleness checks pass, and
performance numbers identify their machine and measurement boundary. No unsupported performance guarantee.

### Phase 6 — Validate across devices and hand over

Run the full static/Debug/Release/installed gates and CPU-only CI path. Obtain the same fixed-fixture evidence
on two distinct Metal architectures, including the owner's RoPE cases; record results per device and retain
existing tolerances unless a separately diagnosed change is accepted. Run affected SIMPLE-shaped toy checks
without changing their policy. Review new tests for large-total integers, near-zero/near-overflow values,
empty shapes, failed replacement and supported lifetimes. Track backend versions and upstream issue status.

**Exit:** release evidence of section 6 exists, every P1 local action is closed or explicitly blocks readiness,
and the report distinguishes implemented protection, remaining documented limits, API deferrals and unsent/
open upstream reports. Write `completed/mlxf_user_hardening_report.md`, link the evidence and update the
roadmap/history/index. Do not mark this whole plan complete merely because the first two fixes pass.

### File table

Paths are verified against the pinned base unless marked new/proposed. Rank 2d's moves are followed by owner
routine names; record the resulting paths before the first implementation edit. Rows are permissions for the
future implementation phases, not claims that these files changed in this planning task.

| File / owner | Work | Phases |
| --- | --- | --- |
| `doc/implementation_notes/planned/mlxf_user_hardening.md` | Single contract, decisions, acceptance and progress record | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md` | Ranking proposal, links, delivered evidence and rulings | planning, 0, 6 |
| `doc/collaboration/apple_questions.md`, `doc/compiler_issues/README.md` | Dedupe/record upstream evidence; GCC file only if new verified facts | planning, 0, 1, 2, 3, 4, 5, 6 |
| `scripts/probes/user_statistics_probe.c`, `scripts/probes/user_range_probe.c` (new) | Minimal direct mlx-c reproducers/controls | 0, 1, 2, 3 |
| `src/core/ops/mlxf_ops_reduce.f90` | C1 and floating mean, empty extrema; own helpers where practical | 1, 3 |
| `src/core/linalg/mlxf_linalg_matrix.f90` | Scaled Euclidean norms | 3 |
| `src/core/ops/mlxf_ops_reduce_tester.f90`, `src/core/linalg/mlxf_linalg_matrix_tester.f90` | Integer/range/empty regressions | 1, 3 |
| `src/core/io/mlxf_io.f90`, `src/core/io/mlxf_io_tester.f90` | Save transaction and failure-preservation tests | 1 |
| `src/core/runtime/mlxf_libc.f90` | Temporary-file/rename/cleanup calls, if needed | 1 |
| `src/core/ops/mlxf_ops_index.f90`, `src/core/ops/mlxf_ops_index_tester.f90` | Explicit bounds validation API and fixtures | 2 |
| `src/core/ops/mlxf_ops_index.f90` (Phase 5) | one comment Phase 2 left above the validator, moved back above `section`, which it describes (found by the reference generator) | 5 |
| `src/core/array/mlxf_array.f90`, `src/core/array/mlxf_array_elementwise.f90`, `src/core/array/mlxf_calls.f90`, `src/core/array/mlxf_calls_elementwise.f90` | Integer scalar bindings and shared helpers; no general ownership rewrite | 4; 1, 2, 3 only if shared signature/helper changes are needed |
| `src/core/array/mlxf_array_tester.f90`, `src/core/ops/mlxf_ops_logic_tester.f90`, `src/core/ops/mlxf_ops_math_tester.f90` | Scalar promotion/native-intrinsic controls; use actual owning tester after Phase 0 mapping | 4 |
| `src/defs/mlxf_defs.f90` | Validator spec if needed; Phase 1's behaviourless types shared by modules (a file's facts, a save in progress: rule `defs`) | 1, 2, 4 |
| `src/core/mlxf.f90` | Explicit new public exports | 2, 4 |
| `src/test/framework/mlxf_test_defs.f90`, `src/test/framework/mlxf_test_registry.f90` | Shared frozen bounds and area/guard registration, only if needed; Phase 5 registers the named-only benchmark `bench_user_costs` | 1, 2, 3, 4, 5, 6 |
| `src/core/transforms/mlxf_transforms_tester.f90` or existing transform owner selected in Phase 0 | Derivative controls for changed compositions, if needed | 3 |
| `scripts/check_rules.py`, `scripts/check_consumer.py`, `scripts/mlxf_consumer_checks.py` (last two new) | Shared lifetime analysis, consumer entry point, planted-rule self-tests | 2 |
| `CMakeLists.txt`, `cmake/mlxfConfig.cmake.in` | Install/check consumer tooling and new examples; optional CMake helper | 2, 4, 5, 6 |
| `scripts/check_install.sh` | Runs the consumer examples, Phase 0's safety example from its first appearance | 0, 2, 4, 5, 6 |
| `README.md`, `doc/quickstart.md`, `doc/how2s/how2use_from_simple.md`, `doc/how2s/how2use_installed.md` (new) | Immediate guidance, compatible general-user entry, architecture/precision limits | 0, 1, 2, 3, 4, 5, 6 |
| `doc/policies/binding_contract_policy.md` | Current contract with implemented changes; Phase 0 names the present limits (C1, C2, C3, C5, C6, C10) | 0, 1, 2, 3, 4, 5, 6 |
| `doc/policies/test_environment_policy.md`, `doc/architecture_principles.md` | Current contract with implemented changes; two-architecture release rule only when adopted | 1, 2, 3, 4, 5, 6 |
| `test/consumer/mlxf_example_user_safety.f90` (new), `test/consumer/CMakeLists.txt`, existing examples if needed | Installed compile/run evidence for guidance and API additions | 0, 1, 2, 3, 4, 5 |
| `test/consumer/mlxf_api_names.f90` | the public API list of rank 2d: every new public name in the same change (ruling R1) | 2, 4 |
| `test/consumer/mlxf_example_differences.f90` | the quickstart's D rows a phase adds, run by rule `docex` (ruling R2) | 0, 1, 2, 3, 4, 5 |
| `doc/code_base_map.md` (generated by `scripts/generate_codeoverview.py`) | Regenerated when a phase adds a Fortran file | 0, 1, 2, 3, 4, 5, 6 |
| `scripts/generate_api_reference.py`, `doc/api_reference.md` (new), rank-2d API inventory tool | Source-derived signatures, coverage and semantic links | 5 |
| `scripts/check_tree.sh` | Shared checker/reference checks and planted negative controls | 2, 5 |
| `src/test/bench/mlxf_bench_user_costs.f90` (new, only missing cases after 2d/2f) | Named-only timings; no new executable or CTest process | 5 |
| `src/test/bench/bench.inf` | the bench directory's description names the new benchmark | 5 |
| `scripts/release_gate.sh`, `test/CMakeLists.txt` | Record/check release evidence and keep process budget, if needed | 6 |
| `scripts/check_rules.py`, `scripts/check_consumer.py`, `scripts/generate_api_reference.py` (Phase 6) | write no bytecode cache beside the sources when they import their sibling modules (the release gate found `scripts/__pycache__` in its snapshot) | 6 |
| `src/core/ops/mlxf_ops_reduce_tester.f90`, `src/core/io/mlxf_io_tester.f90`, `src/core/linalg/mlxf_linalg_matrix_tester.f90`, `src/core/transforms/mlxf_transforms_tester.f90`, `src/core/ops/mlxf_ops_logic_tester.f90` (Phase 6) | the review of the new tests: exact reads of integer extrema, size checks against vacuous passes, exact-sum constant fixtures, ddof on varying data, an unchecked status, a framework seed, two misplaced comments; no bound relaxed | 6 |
| `doc/implementation_notes/completed/mlxf_user_hardening_report.md` (new at closure) | Findings, phase results, rulings, deviations, evidence and unresolved limitations | 6 |

## Progress

### 2026-11-26 — Consolidation and plan only (Codex)

Read both reviews, the binding/design decisions, plan standard, roadmap, refactoring plan and current owners.
Mapped all ten Claude findings and four independent findings into C1–C14; preserved their measured versus
unverified distinctions and embedded the decisive fixtures. Added a proposed roadmap entry, index/history
links and new open upstream questions without sending anything. Existing question 31 owns checkpoint loss;
question 32 and the owner's RoPE patch retain their attribution. No library/test implementation changed, no
new numerical result or upstream fix is claimed, and no implementation phase has been marked complete.

Validation: `scripts/check_tree.sh` and `git diff --check` passed. A targeted documentation check passed
for all changed-document links, C1–C14 and U1–U10/N1–N4 coverage, the required plan sections and all seven
phase exits. Hashes confirmed that the owner's two modified Fortran files and Claude review were untouched;
edits to the existing Apple tracker and notes index were insertion-only. No compilation or numerical tests
were rerun for this documentation-only change. Historical build/test results above belong to the preceding
investigation and are not a substitute for Phase 0.

### 2026-11-26 — Phase 0: base pinned, defects reproduced, bounds frozen, guidance published (Claude, run `mlxf_user_hardening`)

**Machine and base.** Apple M5 Ultra (30 cores, 96 GB), GPU `applegpu_g17d`, macOS 27.2.1; Homebrew GNU Fortran
16.2.0 (`gfortran-16`), CMake 4.5.1, MLX 0.32.4 and mlx-c 0.8.0 (shared, Homebrew). Base
`ae7d62367facaffc88a2262f8cb9b34ffcd88cfc` (rank 2f's result); dirty at the start, preserved: this note, the roadmap
and `doc/history/2026-11.md` (the owner's ruling R0 and its records). Ruling R0 (decisions 3 to 9 as recommended) is
already recorded in section 3; Phase 0 changes no decision. Evidence is under
`/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/` (below `keep/`).

**Rank 2d reconciled.** Ranks 2d, 2e and 2f are delivered (commits `6a1a03e`, `bb59c21`, `ae7d623`): every path of the
file table exists at the base under the name it gives (checked one by one), so no row is remapped. Owners selected
here: the derivative controls of Phase 3 go to `src/core/transforms/mlxf_transforms_tester.f90`; Phase 4's scalar
promotion tests to `src/core/array/mlxf_array_tester.f90` (operators) and `src/core/ops/mlxf_ops_logic_tester.f90`
(comparisons). Two rows gained Phase 0 before their edit: `scripts/check_install.sh` (it names the examples it runs)
and `doc/policies/binding_contract_policy.md` (Phase 0 names the present limits in the contract, as its text asks).

**Base builds and gates** (the run's recipe: hand-configured trees, `-DMLXF_WERROR=ON -DFORTLS=OFF`, `-j 12`): Debug
and Release built with 0 warnings, fast gate 13 of 13 (Release 12.1 s of its 60 s budget, *measured*), installed;
`scripts/check_install.sh` passed on Debug and on Release with `--require-gpu` (`base_check_install.log`).
`mlxf_test_exec test=unit_core` sees 1 GPU device. No base failure. The toys' 364-line identity set (run
`mlxf_kernel_forms`' `identity.sh`, paths changed, copied to `keep/tools/`) run twice on the base Release build:
`identity/identity_ab.log`, compared with that run's Phase 5 copy (SHA-256 `e2d65e88...4d33dba5`).

**Reproductions on the base** (each run twice per build; Debug and Release agree except where marked). Fortran
programs against the installed package in `keep/repro/` (`run_repro.sh`; logs `base_repro_{release,debug}_run{1,2}.log`),
direct mlx-c probes `scripts/probes/user_statistics_probe.c` and `user_range_probe.c` (`c1_direct_probe_run{1,2}.log`,
`c5_c6_direct_probe_run{1,2}.log`, the two runs identical), compile probes `keep/repro/c9/` (`base_c9_compile.log`),
GCC controls (`base_gcc_c4_controls.log`).

| Row | Holds on the base? | Observed (*measured*) |
| --- | --- | --- |
| C1 | yes, both devices, both builds, and through mlx-c alone | image 4096: mean 0, var 16777216, std 4096, also dim/dims/keepdims/ddof=1; pair 2e9: mean -147483648, var 4.61168602e18 (9.22337204e18 with ddof=1), std 2.14748365e9. Direct C: int32, uint32, int64, uint64 wrong in mean, mean_axis, var, std; int8, int16, uint8, uint16, bool right; every case right after a float32 conversion; signed cancellation right. 36 WRONG cases of `repro_numeric` are C1 + C5 |
| C2 | yes | safetensors 99 B → 0 B after a float64 save, GGUF 80 B → 24 B after an int64 save, status 1 each |
| C3 | yes; the CPU's out-of-range read is not deterministic | GPU: Fortran indices 6 to 100000000 and -5 give 0, status 0. CPU: 6 to 10000 give 0; 1000000 gave 8.86e11 (3 runs) or SIGSEGV (1); -5 SIGBUS in 3 of 4 runs (0 once); 100000000 SIGSEGV in 4 of 4. 0 and -1 wrap as documented |
| C4 | yes (gfortran, not MLX) | 1000 rounds: `[a, exp(b)]`, `[a, b*2.0]`, `v = exp(a)` each +1000 live, +250 MiB; the three supported counterparts +0, +0 MiB. GCC issues 2 and 3 reproduce at -O0 with checks and at -O3 |
| C5 | yes, both devices; direct C too | norm2 f32 [1e20,1e20] inf, [1e-30,1e-30] 0 (all and dim=1 forms); f64 CPU 1e200 inf, 1e-200 0; mean f32 [2e38,2e38] inf. Direct C adds f32 2e38 and f64 1e308 norms, f64 1e308 mean; the scaled controls are within 8 epsilons everywhere |
| C6 | yes | `maxval`/`minval` of (0,3), dim=1, `error stop 86` ("Cannot max reduce over axis 1 with size 0"); MLX refuses it directly too. gfortran gives -huge/+huge for reals, -huge-1/+huge for integers, shape (3) (`c6_gfortran_empty_identities.log`) |
| C7 | yes (the documented policy) | (3)+(4) stops 86 at `operator(+)` before any later `status` |
| C8 | yes | sin f64 on CPU: float64 kind, largest error 4.6e-7 on [0.01, 10]; irfft(rfft(f64)) float32, refused into real64 ("differ in kind"), 2.4e-6 into real32; solve f64 residual 4.4e-16; sin f64 on the GPU stops 86 |
| C9 | yes | refused by gfortran: `a + 1`, `2 * a`, int32 array + `1_int32`, int32 array + `1`, `print *, a`, `if( all(a > 0.) )`, `a(2:3)`, `mlx_from` of complex(real64); the controls (real scalars, assignment) compile |
| C10 | yes | 100000 steps evaluate; 300000 stop 86 at `operator(+)`: `[metal::malloc] Resource limit (499000) exceeded` |
| C11 | not rerun | a cost model, not a defect; measured in Phase 5 under its timing protocol |
| C12, C13 | yes (reading) | README leads with status; the install guide is `how2use_from_simple.md`; GNU Fortran only, the exact-version refusals pass in `check_install.sh` |
| C14 | on the M5 only | `unit_fast` (RoPE) passes here; the second architecture is not available to this run (Phase 6) |

**Bounds frozen before any fix** (origin in brackets; they judge Phases 1 and 3 and do not move):

- C1 exact fixtures (image 4096, pair 2e9, every form above, both devices): |result - answer| ≤ eps32·max(1, |answer|)
  (*derived*: the values, every partial sum and the divisions by 2^20 and 2 are exact in float32, so one epsilon is
  margin for a reciprocal multiply). Signed cancellation [2e9,-2e9,2e9,-2e9]: mean the same bound, var and std
  ≤ eps32·|answer| (*derived*: one rounding of 4e18). Every integer dtype (int8 to int64, uint8 to uint64, bool):
  oracle = each element converted to float32, then the statistic in real64 on the host; bound eps32·max(1, |answer|)
  for constant fixtures (*derived*), and the existing `REDUCE_TOLERANCES` rows of `mlx_mean`, `mlx_var`, `mlx_std`
  for general integer fixtures (*existing frozen bound*). The result dtype stays float32.
- C5: two equal values (f32 1e20, 1e-30; CPU f64 1e200, 1e-200): finite, nonzero, |r - sqrt(2)|x|| ≤ 8·eps_k·sqrt(2)|x|
  (*derived*, the plan's). f32 mean [2e38,2e38] within 8 eps32 (*derived*). General finite real vectors of n ≤ 1024
  elements, any magnitudes: relative error ≤ (n + 2)·eps_k against a real64 (for f64: scaled real64) host oracle
  (*derived*: recursive summation of n squares, (n-1)·eps, halved by the square root, plus the scale's division and
  product), never an absolute floor; zeros → exactly 0; empty → exactly 0 (Fortran's `norm2`); a NaN → NaN; an
  infinity and no NaN → +inf. Complex: the same bound with 2 more epsilons for the magnitude, inputs up to 1e30 in
  each part without overflow of the scale. Floating mean of n ≤ 1024 values: |r - mean| ≤ (n + 2)·eps_k·mean(|x|)
  (*derived*, the summation bound relative to the magnitudes, which covers cancellation). The normal-range rows of
  `REDUCE_TOLERANCES` and `MATRIX_TOLERANCES` (`norm2`) stay in force (*existing frozen bound*).
- C6: exact. maxval/minval of a zero extent equal gfortran's intrinsic on the same-kind zero-size array: real32 and
  real64 -huge/+huge, int8 to int64 -huge-1/+huge; device-only dtypes by their own limits (uint: 0 and the largest
  value; float16, bfloat16: minus and plus their largest finite value; bool: false and true); shape and rank exact,
  also for the all-dimension, keepdims and list forms (*exact*, `c6_gfortran_empty_identities.log`).
- C2: byte-for-byte equality of the destination after every returned failure (*exact*). C3, C4, C9: the matrices of
  section 6, exact (*exact*; C4's counts are fixture counts).

**C rows assigned** (closure owner; upstream entries open and unsent):

| Row | Phase | Closure |
| --- | --- | --- |
| C1 | 1 | promote before mean/var/std; regression fixtures above; Apple 33 |
| C2 | 1 | transactional array saves; Apple 31(a) |
| C3 | 2 | explicit validator; Phase 0 guidance S3; Apple 35 |
| C4 | 2 | consumer lifetime checker; guidance S4; GCC issues 2 and 3 |
| C5, C6 | 3 | scaled norms and means, empty extrema; guidance S7; Apple 34 |
| C7 | 4 | design and disposition only (decision 9) |
| C8 | 5 | precision/device matrix (contract and quickstart rows D15, D16 now) |
| C9 | 4 | default-integer scalar operators; S6's `mlx_item` spelling now |
| C10 | 5 | bounded-loop example and instrumentation; guidance S5 and contract section 8 now |
| C11 | 5 | cost model, timing protocol |
| C12, C13 | 5 | reference, neutral install entry, compatibility table |
| C14 | 6 | two-architecture evidence; owner's RoPE patch untouched; Apple 32 |

**Guidance published.** The quickstart's new section "Limits of the present library, and what to write instead"
(rows S1 to S7: integer statistics, saves over a file, unchecked indices, handle lists, long loops, host decisions,
wide-range norms and empty extrema), each a block of the new `test/consumer/mlxf_example_user_safety.f90`, which
`test/consumer/CMakeLists.txt` builds and `scripts/check_install.sh` runs (from its scratch directory, since the
example writes two files); its three quoted blocks are checked verbatim by rule `docex`. The README points to it
before its status text; the install guide too. The contract names the present limits where they live: unchecked
indices read outside the buffer (section 10), the integer-statistics defect and empty extrema (reductions), the
norm and mean range (norms), the checkpoint advice (section 17) and the unevaluated-graph limit (section 8). The
Apple tracker's 31, 33, 34, 35 carry this run's reproductions and point to the two probes (the `/tmp` evidence is
gone); `doc/compiler_issues/README.md` records issues 2 and 3 observed again on the M5. Nothing was sent.

**Decisions taken under delegation.** (1) The failing reproducers stay outside the fast suite and the test
executable: Fortran programs in the run's `keep/repro/` and the two C probes (run by hand, exit 0, their output the
finding); Phase 1 and 3 admit them as assertions with their fixes. (2) The example's checkpoint advice is "save
under a new name": Fortran has no standard rename, and a later phase makes the saves replace atomically. (3) C11's
costs are not re-measured here (a timing protocol belongs to Phase 5). (4) The guidance quotes measured behaviour
with its versions rather than predicting later fixes.

**Exit.** Baseline facts and frozen bounds: above. All C rows assigned: above. Reproducible fixtures admitted: the
probes in `scripts/probes/`, the example in `test/consumer/`, the reproducers in the run's `keep/repro/`, each failing
(or printing the defect) on the base. Immediate guidance verified: see the closing builds below. GPU: present.

**Closing builds** (Phase 0's tree, from scratch with the recipe): Debug and Release 0 warnings, fast gate 13 of 13
on both (Release 10.5 s, *measured*; `phase0_fast_gate_{debug,release}.log`, after `doc/code_base_map.md` was
regenerated for the new example, which the first gate run caught: `phase0_build_*.log`); `scripts/check_install.sh`
passed on Debug and on Release with `--require-gpu`, running `mlxf_example_user_safety` on the GPU
(`phase0_check_install_{debug,release}.log`); `scripts/check_tree.sh` passed (`phase0_check_tree.log`; its only
warning is the untracked new example, which the maintainer's commit resolves); `scripts/check_rules.py` holds every
rule, `docex` included; both formatters leave the example unchanged; `git diff --check` clean. No library source
changed, so the toy identity set needs no rerun.

**Files changed:** `README.md`, `doc/quickstart.md`, `doc/how2s/how2use_from_simple.md`,
`doc/policies/binding_contract_policy.md`, `doc/collaboration/apple_questions.md`, `doc/compiler_issues/README.md`,
`doc/code_base_map.md`, `scripts/check_install.sh`, `test/consumer/CMakeLists.txt`, this note; new:
`scripts/probes/user_statistics_probe.c`, `scripts/probes/user_range_probe.c`,
`test/consumer/mlxf_example_user_safety.f90`.

**What it means, in short.** Every defect of C1 to C10 still holds on the pinned base, four of them now shown through
mlx-c alone or through gfortran alone; the CPU's out-of-range read is worse than reported (a plausible nonzero value,
or a crash, from run to run). The numbers Phases 1 and 3 will be judged by are frozen above, and a user reading the
README or quickstart today meets each hazard with a spelling that the consumer check proves works.

### 2026-11-26 — Phase 1: integer statistics corrected, array saves made transactional (Claude, run `mlxf_user_hardening`)

Machine, toolchain and base as Phase 0 (M5 Ultra `applegpu_g17d`, GNU Fortran 16.2.0, MLX 0.32.4, mlx-c 0.8.0, base
`ae7d623` with Phase 0's tree). Evidence under `/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/phase1/`
(below `phase1/`). Ruling R0's decisions 3 and 4 are what this phase implements, as recommended; no other decision
changed.

**C1 (decision 3).** `mlxf_ops_reduce` gains one private helper, `statistic_operand`, called by the six specifics
of `mlx_mean`, `mlx_var` and `mlx_std`: a boolean, signed or unsigned integer operand is converted to float32
(`mlx_astype`) before the reduction; real and complex operands pass unchanged; `sum` and `product` are untouched; the
result stays float32. `test_integer_statistics` (`mlxf_ops_reduce_tester.f90`, every device) asserts Phase 0's frozen
C1 bounds: the image of 4096 and the pair 2e9 in all/dim/dims/keepdims/ddof=1 forms, signed cancellation, a constant
of each of the nine integer and boolean kinds (int64 2^62, uint32 4e9, uint64 2^63 included), each within one float32
epsilon of max(1, |answer|) (*derived* bound), the result kind float32; general int32 and int64 fixtures in
[-2e9, 2e9] (float32-exact integers, the family's seeds) against the family's oracle, judged by the frozen
`REDUCE_TOLERANCES` on the data scaled by 1e-9, which maps them onto the family's domain [-2, 2] (*existing frozen
bound*, unchanged). Largest errors, both builds and devices: mean 1.40, std 1.58, var 2.76 float32 epsilons
(*measured*), against 4, 4 and 7.08.

**C2 (decision 4).** Semantics fixed before the code, as recommended: the three array saves keep their signatures;
each checks names/metadata and the format's kinds (safetensors: no float64; GGUF: int8, int16, int32, float16,
float32 only) and refuses with "nothing was written", evaluates its arrays, settles the destination's name once (the
suffix `.npy`, `.safetensors` or `.gguf` added where missing, as MLX does for all three), refuses a symbolic link, a
non-regular file, a file with another hard link and another user's file, creates a hidden sibling
`.<name>.mlxf<pid>-<k>.tmp<suffix>` with `fopen(..., "wx")` (first free k of 100), lets MLX write it, gives it the
old file's permission bits and renames it over the destination; any failure unlinks the sibling and never the
destination. No fsync: the promise is preservation on a returned failure, not durability (decision 4). New libc
bindings in `mlxf_libc` (rename, unlink, chmod, lstat, getpid, geteuid; symlink, link, mkdir, rmdir for the tests),
all non-variadic; `c_file_info` reads macOS arm64's `struct stat` at its checked offsets (mode at byte 4, links at 6,
owner at 16; verified with clang's `offsetof`, and the tests read back a mode of 640). The two steps are
`mlxf_save_begin` and `mlxf_save_end` of `mlxf_io`, module-public but not exported by `mlxf`: the test seam the
plan names, driven by the tester, with no switch or global state. `mlx_function_exporter` is unchanged and keeps its
incomplete-file warning. `test_replacement` (`mlxf_io_tester.f90`, every device) checks the original bytes after a
refused kind, names, metadata, a failed evaluation (GPU: one buffer beyond `max_buffer_length`), a failed write, a
failed rename (existing and absent destination) and exhausted temporary names; canonical bytes on success; mode 640
kept; a new file's mode equal to a program-created file's; `.npy` added once to a name with spaces; symlink, hard link
and directory refused; no temporary file left. Another user's file is not testable without a second account.

**Plants** (a patched copy built apart, `plants/plant.sh`, logs `plants/plant_c{1,2}_*.log`): C1 with the conversion
removed fails 70 of 2636 `unit_ops` assertions; C2 with the transaction and the kind preflights removed fails 17 of
901 `unit_io` assertions. Both on the final tests.

**Gates** (from scratch with the recipe): Debug and Release 0 warnings, fast gate 13 of 13 (Release 12.1 s,
*measured*), installed; `check_install.sh` passed on Debug and on Release with `--require-gpu` (the example's S1 and
S2 now exercise the fixed behaviour); every unit area passed in both builds (`units_{debug,release}_*.log`); the
static gate passed (`check_tree.log`); both formatters on every touched Fortran file. A first Release build failed on
`-Werror=function-elimination` (impure `contents`/`exists` as operands of `.and.` in the new io test), fixed by
evaluating them into variables (`p1_build_try1.log`). Phase 0's installed reproducers against the new Release
install (`repro_after_release.log`): every C1 case correct on both devices, both refused saves leave 99 and 80 bytes
intact; the 12 remaining WRONG cases are C5's (Phase 3). The toy identity set is byte for byte the base's (364 lines,
SHA-256 `e2d65e88...4d33dba5`, `identity.log`).

**Costs** (decision 13; `timing/costs.f90`, `timing/costs.log`; median of 5 repeats after 3 warm-ups, two
interleaved before/after rounds, GPU, Release, one-minute load 3.7 to 3.9 before each, *measured*): `mlx_mean` of a
1024×1024 int32 array with its evaluation 162 to 227 µs before, 170 to 171 µs after (the float32 control 158 µs both);
`mlx_var` 189 to 192 µs both; a 16-byte safetensors save over a file 46 to 54 µs before, 131 to 133 µs after (about
80 µs of lstat, temporary file, permissions and rename); a 4 MiB save 381 to 385 µs after against 422 to 450 µs before
(safetensors), 352 to 380 against 421 to 423 (npy): writing a fresh file and renaming it is not slower here than
truncating and rewriting the old one. These are measurements, not floors.

**Decisions taken under delegation.** (1) A hard-linked destination is refused (a rename would leave the other links
with the old bytes), and another user's file too (its ownership cannot be kept); recorded in the contract. (2) A save
into a directory the program cannot write now fails even over a writable file (the sibling lives there). (3) The
kinds MLX 0.32.4 refuses are checked by the library before writing; MLX's main branch (commit `1c141875c`, after
0.32.4) has its own temporary-file save, which follows symlinks: noted in Apple question 31, whose request (a) is to be
narrowed to its release. (4) The transaction's steps are the test seam (no failure switch). (5) Two behaviourless
types (`mlxf_file_info`, `mlxf_save_target`) live in `src/defs/mlxf_defs.f90` as rule `defs` requires; the file-table
row gained Phase 1 before the edit. (6) The general integer fixtures reuse the family's tolerances on scaled data
rather than new bounds.

**Files changed:** `src/core/ops/mlxf_ops_reduce.f90`, `src/core/ops/mlxf_ops_reduce_tester.f90`,
`src/core/io/mlxf_io.f90`, `src/core/io/mlxf_io_tester.f90`, `src/core/runtime/mlxf_libc.f90`, `src/defs/mlxf_defs.f90`,
`test/consumer/mlxf_example_user_safety.f90`, `doc/policies/binding_contract_policy.md`, `doc/quickstart.md`,
`README.md`, `doc/how2s/how2use_from_simple.md`, `doc/collaboration/apple_questions.md`, `doc/code_base_map.md`, this
note. No new file.

**Exit.** C1/C2 acceptance passes on the CPU and the GPU in both builds; the regression fails with each fix removed;
the contract, quickstart, README, install guide and example describe the new behaviour; no serialization format
changed (every existing byte-level round trip and the canonical-bytes check pass) and no other area's result
changed.

**What it means, in short.** Integer statistics are now right wherever float32 can represent the answer, and a failed
save no longer costs the old checkpoint: the two P1 defects that could hurt a user silently are closed locally,
with tests that fail if either fix is removed.

### 2026-11-26 — Phase 2: an explicit index check and a consumer lifetime checker (Claude, run `mlxf_user_hardening`)

Machine, toolchain and base as Phase 0, with Phases 0 and 1 in the tree. Evidence under
`/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/phase2/` (below `phase2/`). Ruling R0's decisions 5 and 6
are what this phase implements, as recommended.

**C3: the validator's API, frozen here** (R0: names frozen in Phase 2, listed for the maintainer's read). One new
public generic, **`mlx_check_indices`**, in `mlxf_ops_index`, exported by `mlxf`:
`call mlx_check_indices(indices, extent, status)` (elements, `1 <= i <= extent`),
`call mlx_check_indices(indices, extent, size, status)` (slab starts, `1 <= i <= extent - size + 1`, after
`1 <= size <= extent`), and the list forms `(indices(:), extents(:), status)` and
`(indices(:), extents(:), sizes(:), status)`, each array against its own extent (the first failure named). `indices`
is an `mlx_array` of any integer kind, signed or unsigned, and any shape; extents and sizes are default integers;
`status` is required (it never stops on bad values; a stale or empty handle stops as everywhere). It reduces the
indices to their smallest and largest value in their own kind, moves both to int64 (a uint64 value at or above 2^62
is refused first, by a shift), evaluates once and compares on the host: no narrowing, no overflow. Empty index arrays
pass without an evaluation; index 0 is refused; a nonempty array into an extent of 0, a negative extent and a
non-integer array are refused. It is not to be called inside a compiled or traced callback (a host wait). The
operations themselves are unchanged: no validation, no evaluation, no global switch. The recipes and the coverage
(take, take/put along a dimension, gather and the scatters with one index array or a list, the dynamic slice and
its update, `mlx_gather_mm`, `mlx_segmented_mm`, `mlx_cross_entropy`'s classes), with `mlx_as_strided` left to its
own unsafe contract, are in the binding policy's section 10. `test_index_check` (`mlxf_ops_index_tester.f90`,
every device) runs the C3 matrix of section 6: 112 checks, `ops_index` 88 → 200 (*exact*), including index
100000000 kept from the CPU's `mlx_take`, accepted indices reused, and `mlx_take` still unchecked and lazy.

**C4: the consumer checker.** The lifetime analysis of `check_rules.py` (statements, constructors, a file's handles,
rules `ctorcall` and `ctorexpr`) moved verbatim into `scripts/mlxf_consumer_checks.py`; `check_rules.py` imports it,
so the repository's rules and the consumer checker are one implementation (old and new `check_rules.py` give the
same findings on a tree with planted `ctorcall` and `ctorexpr` violations: `plant_rules_{old,new}.txt`). The module
adds the consumer rules, with names resolved in each procedure's scope: `ctorcall` (for names imported from `mlxf`,
renamed imports and a whole `use mlxf` included), `ctorexpr`, `wholefunc`, `viewexpr`, `overlap`, `alloccomp`,
`allocsrc`, `arrayintr`, `selfassign`; its docstring and the binding policy (section 3) give the coverage matrix and
what is not detected (other files' handles, aliasing, macros and inactive preprocessor branches, fixed form, OpenMP
copies). `scripts/check_consumer.py FILE...` reports file, line, rule and safe spelling, exits 1 on a finding,
`--rules` prints the limits and every run's summary states them; `--self-test` runs 21 planted fixtures (every
rule's unsafe form found and its safe form clean, renamed imports, a whole `use mlxf`, scopes, a component view,
the preprocessor's limit, another file's handles unseen). Installed into `<prefix>/share/mlxf/` with its module;
`mlxf_check_lifetime(<target>)` in the package config runs it before a target builds (a finding fails the build).
`check_tree.sh` runs the self-test and the consumer programs (clean); `check_install.sh` runs the installed copy
with `python3 -I` from the scratch prefix (no repository file reachable): self-test, consumer programs, a planted
leak reported as `leak.f90:4: ctorexpr`, and the same leak failing a project's build through `mlxf_check_lifetime`;
the consumer project itself now builds through it. On Phase 0's runtime reproducer it reports exactly the three
forms that leak at run time and none of the three supported ones (`checker_on_repro_lifetime.log`,
`repro_lifetime_after.log`: supported forms +0 live, +0 MiB over 1000 rounds; *measured*). Run over this
repository's own sources (not part of any gate) it finds 6 forms, all genuine: three deliberate bitwise-copy guard
tests and three test classes with allocatable handle components that are never assigned. `check_rules.py`'s rule
`libc` now also names Phase 1's bindings (rename, unlink, chmod, lstat, getpid, geteuid, symlink, link, mkdir,
rmdir).

**Plants** (`plants/`): the validator without its lower-bound refusal fails 18 of 200 `ops_index` assertions; the
shared `ctorexpr` analysis disabled fails the checker's self-test and silences `check_rules.py` on a planted
`[x, x*2.0]`: the two tools share one implementation.

**Gates** (from scratch with the recipe, `build_chain.log`): Debug and Release 0 warnings, fast gate 13 of 13
(Release 10.6 s, *measured*), installed; `check_install.sh` passed on Debug and on Release with `--require-gpu`; every
unit area passed in both builds (`units_*`); `check_tree.sh` passed; both formatters on every touched Fortran file;
`list_public_api.py --check` holds (`test/consumer/mlxf_api_names.f90` regenerated, 316 names). A first Release build
failed on `-Werror=function-elimination` (`indices%size()` as an operand of `.or.`), fixed by a separate test
(`try1/`). The toy identity set is byte for byte the base's (`identity.log`).

**Costs** (decision 13; `timing/costs.f90`, `timing/costs.log`; GPU, Release, median of 5 after 3 warm-ups, two
rounds, one-minute load 3.6 before, *measured*): `mlx_check_indices` 145 to 152 µs on 16 indices and 169 to 173 µs on
1048576, against 150 µs and 161 µs for the `mlx_take` it guards with its evaluation: one check costs about one
evaluated take, dominated by the wait, which is why it is explicit and done once.

**Decisions taken under delegation.** (1) One generic name with four forms rather than separate element/slab names;
`status` required. (2) Extents are default integers, as every shape argument of the library; a flat position in an
array of more than `huge(1)` elements is checked per dimension instead (documented). (3) The validator takes an
`mlx_array` (the data the operations take), not a host array, which a caller checks with `any` already. (4) uint64
values at or above 2^62 are refused without a comparison against the extent (no real extent reaches 2^62). (5) The
consumer checker resolves names per scope; the repository's two rules keep their file-wide reading unchanged. (6) The
checker is installed under `share/mlxf/`; the CMake helper is a function of the package config, optional to call.

**Found, outside the plan's rows.** `mlx_from` of a zero-size host array stops ("Attempting to allocate
18446744073709551612 bytes", on the CPU device as well): an unsigned underflow in the transfer of an empty array.
`mlxf_transfer` is in no phase's file table; the test builds its empty index array with `mlx_zeros([0])`. Left for
the report as a follow-up.

**Files changed:** `src/core/ops/mlxf_ops_index.f90`, `src/core/ops/mlxf_ops_index_tester.f90`, `src/core/mlxf.f90`,
`scripts/check_rules.py`, `scripts/check_install.sh`, `scripts/check_tree.sh`, `CMakeLists.txt`,
`cmake/mlxfConfig.cmake.in`, `test/consumer/CMakeLists.txt`, `test/consumer/mlxf_api_names.f90`,
`test/consumer/mlxf_example_user_safety.f90`, `doc/policies/binding_contract_policy.md`, `doc/quickstart.md`,
`README.md`, `doc/how2s/how2use_from_simple.md`, `doc/collaboration/apple_questions.md`, `doc/compiler_issues/README.md`,
this note; new: `scripts/check_consumer.py`, `scripts/mlxf_consumer_checks.py`.

**Exit.** C3: the matrix passes on both devices in both builds; a refused index never reaches the operation. C4: the
static plants fail and the safe forms pass, the supported forms hold their live count and memory; the old unchecked
route adds no validation or evaluation (the operations' code is unchanged); the installed consumer runs the
checker, from the shell and through CMake; every diagnostic and `--rules` state what was not checked. No compiler
fix is needed.

**What it means, in short.** A user now has one explicit call that keeps untrusted indices from reading outside an
array, and a checker, installed with the package, that turns the silent gfortran leaks into build-time messages
with the line and the fix, while saying plainly what it cannot see.

**Ruling R1 (2026-11-26, after the fence stop of Phase 2).** The driver's file fence refused
`test/consumer/mlxf_api_names.f90`, which rank 2d's API check (`list_public_api.py --check`) requires to list every
new public name, and which the file table remapped after rank 2d had omitted. Hans ruled that a row assigns it to
Phases 2 and 4 (added to the file table by the controller); Phase 2's work stands. Applied: the tree was left as it
was, the row is in the table, and the gates were re-run on the unchanged sources after the ruling: both builds up to
date with no recompilation, fast gate 13 of 13 in Debug and Release, `check_install.sh --require-gpu` passed on
Release (`phase2/r1_*.log`). The fence's report named no other file.

### 2026-11-26 — Phase 3: scaled Euclidean norms and floating means, Fortran's empty extrema (Claude, run `mlxf_user_hardening`)

Machine, toolchain and base as Phase 0, with Phases 0 to 2 in the tree. Evidence under
`/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/phase3/` (below `phase3/`). Ruling R0's decision 7 is what
this phase implements, as recommended; the bounds are Phase 0's, frozen before this change.

**C5.** One scale, shared: `mlxf_reduce_scale` in `mlxf_ops_reduce` (module-public, not exported) takes the largest
magnitude over the reduced dimensions, of the real and imaginary parts for a complex array so that the scale itself
cannot overflow, stops its gradient, and marks where it is finite and positive (elsewhere the divisor is 1).
`norm2` (`mlxf_linalg_matrix`, every form) is `s*sqrt(sum((a/s)**2))` and the floating or complex `mlx_mean`
(`mlxf_ops_reduce`) is `s*mean(a/s)`; where the scale is zero or not finite MLX's plain result stands (0, +infinity,
NaN as IEEE arithmetic gives them). Integer operands, the integer-converted means of Phase 1, `mlx_norm` of every
order, an invalid dimension list (refused under the wrapper's own name) and empty reductions keep MLX's path. One
implementation: no fast unscaled default is retained (decision 7). Tests, each against Phase 0's bounds:
`test_norm2_range` (`linalg_matrix` 400 → 442 checks): two equal values 1e20 and 1e-30 (float32, every device) and
1e200 and 1e-200 (float64, CPU) within 8 epsilons in all/dim/keepdims/list forms, a (2, 2) Frobenius and row case,
1024 values of mixed magnitudes (1e-30 to 1e37) and signs within (n+2) epsilons of a real64 reference, relative, 16
values near the bottom of the range, complex parts 1e30 and 3+4i within (n+4) epsilons, float16 values whose squares
float16 cannot hold, zeros and empty reductions exactly 0, NaN NaN, an infinity +infinity. `test_mean_range`
(`ops_reduce`): float32 2e38 pairs in five forms and float64 1e308 within 8 epsilons, 1024 mixed values (eight of
3e38) within (n+2) epsilons of the mean of the magnitudes, signed cancellation, complex parts at 2e38, zeros, NaN,
infinities, and the empty mean NaN (not a refusal). The normal-range family bounds (`REDUCE_TOLERANCES`,
`MATRIX_TOLERANCES`) hold unchanged: largest float32 errors mean 1.1–1.3 and norm2 0.69–0.97 epsilons (*measured*).

**Derivatives** (`mlxf_transforms_tester.f90`, `test_scaled_gradients`, every seed, both devices, float64 on the
CPU): the gradient of `norm2` is `x/norm2(x)` and of `mlx_mean` `1/n`, within `mlx_value_and_grad`'s frozen tolerance
(largest 0.88 float32 epsilons, *measured*), also for `x` scaled by 1e20 (float32) and 1e200 (float64), where the
plain norm's square overflowed. At zero the gradient of `norm2` is not finite (printed, not judged): a Euclidean norm
has no derivative there, MLX's included; stated in the contract.

**C6.** `maxval` and `minval` over an extent of zero (`dim`, a list, or the whole array, kept or not) return
Fortran's identities in the operand's kind and the reduction's shape: -huge/+huge for float32 and float64,
-huge-1/+huge for int8 to int64, 0 and the largest value for uint8 to uint64, ∓65504 for float16, ∓3.38953139e38 for
bfloat16, false/true for booleans; a complex operand is refused as before; a reduction over nonzero extents of an
empty array keeps MLX's empty result. `test_empty_extrema`: the thirteen ordered kinds in every form, exactly
(`ops_reduce` 560 → 764 checks with the mean tests). **The empty-slice decision** (this phase records it): no API
change; documentation is the closure. Along an extent of zero no bound is valid, the dimension is used whole, and no
bound outside 1 through extent is admitted (contract, section 10).

**Plants** (`plants/`, built apart): the scale forced to 1 (MLX's plain sums) fails 28 of 442 `linalg_matrix` and
17 of 764 `ops_reduce` assertions; the empty-extremum identity skipped makes `ops_reduce` stop with 86, the base's
behaviour. (They ran on the tree before two Release-only fixes below, which reorder operands and change no
semantics.)

**Gates** (from scratch with the recipe, `build_chain.log`): Debug and Release 0 warnings, fast gate 13 of 13
(Release 10.6 s, *measured*), installed; `check_install.sh` passed on Debug and on Release with `--require-gpu` (the
example's S7 now calls `norm2` of 1e20 and `maxval` of an empty array directly); every unit area passed in both
builds; `check_tree.sh` passed; both formatters on every touched Fortran file. The first Release build failed on
`-Werror=function-elimination` twice over (`a%ndim()` and `r%shape()`/`r%kind()` as later operands of `.or.`/`.and.`),
fixed by separate tests (`try1/`). Phase 0's installed reproducers (`repro_after_release.log`): 0 WRONG cases (every
C5 case correct on both devices), `maxval`/`minval` of (0, 3) no longer stop. The toy identity set is byte for byte
the base's (`identity.log`): the toys' device `minval` calls take non-empty extents, whose path is unchanged.

**Costs** (decision 13; `timing/costs.f90`, `timing/costs.log`; the before binary built from the Phase 2 library;
GPU, Release, a 1024×1024 float32 array, each call with its evaluation, median of 5 after 3 warm-ups, two
interleaved rounds, one-minute load 3.8 before, *measured*): `norm2` of every element 163–208 µs before, 231–233 µs
after; along dimension 1 162–163 → 221–236 µs; `mlx_mean` 159 → 228–234 µs; along dimension 1 155–156 → 222–227 µs;
`maxval` along dimension 1, the control, 152–154 µs both. The scaled forms cost about one more reduction pass, some
70 µs per evaluated call here (about +45 %), against a wrong answer at the ends of the range. Not floors.

**Decisions taken under delegation.** (1) The scale of a complex array is taken from its real and imaginary parts
(not `abs`), which cannot overflow. (2) The scale's gradient is stopped, which makes the derivative exact without
differentiating the maximum. (3) Non-finite or zero scales fall back to MLX's plain result inside the same
implementation, so IEEE behaviour for zeros, NaN and infinities is MLX's. (4) Half kinds keep their own arithmetic
(no float32 accumulation added). (5) `mlxf_ops_reduce.f90` reached the size limit of 1000 lines exactly; my additions
were compacted rather than the limit raised (rule `size`, no ledger entry). (6) The empty-slice item is closed by
documentation.

**Files changed:** `src/core/ops/mlxf_ops_reduce.f90`, `src/core/ops/mlxf_ops_reduce_tester.f90`,
`src/core/linalg/mlxf_linalg_matrix.f90`, `src/core/linalg/mlxf_linalg_matrix_tester.f90`,
`src/core/transforms/mlxf_transforms_tester.f90`, `test/consumer/mlxf_example_user_safety.f90`,
`doc/policies/binding_contract_policy.md`, `doc/quickstart.md`, `README.md`, `doc/how2s/how2use_from_simple.md`,
`doc/collaboration/apple_questions.md`, this note. No new file.

**Exit.** C5/C6 mathematical, non-finite and shape cases pass on both devices in both builds; normal-range and toy
checks keep their bounds and bytes; the local cost is reported; the backend difference (MLX's plain sums, question
34) and the Fortran-compatibility change (empty extrema) are in the contract.

**What it means, in short.** Norms and means near the ends of the floating range are now right instead of infinite
or zero, at the cost of one extra reduction pass, and an empty maxval or minval gives what a Fortran programmer
expects instead of stopping the program.

### 2026-11-26 — Phase 4, frozen before coding: the default-integer scalar matrix (C9, decision 8)

Ruling R0's decision 8, as recommended. Frozen here, before the first line of code, and judged as written:

- **Surface.** The type-bound generics `operator(+)`, `(-)`, `(*)`, `(/)`, `(**)`, `(<)`, `(<=)`, `(>)`, `(>=)`,
  `(==)` and `(/=)` of `mlx_array` gain a default-integer scalar on either side: 22 private specifics
  (`add_ai`/`add_ia` and their siblings). **No new public name**: the operators are the public surface, so
  `test/consumer/mlxf_api_names.f90` does not change. Other integer kinds (`int64` scalars) are not admitted.
- **Integer arrays** (int8 to int64, uint8 to uint64): the scalar is made in the array's own kind, never through
  real32, so the result keeps the array's kind (`+ - * **`) or is boolean (comparisons); `/` is MLX's true division,
  float32, as `a / b` of two integer arrays is (quickstart D1). A scalar outside the kind's range (int8 with 300,
  any unsigned kind with a negative value, uint8 with 256, uint16 with 65536) is not wrapped: the operator stops
  with `error stop 86` and says so, as every graph-building error does. A negative integer exponent follows MLX
  (documented, not judged).
- **Real and complex arrays** (float16, bfloat16, float32, float64, complex64): the scalar is weak, as a real one is
  today: it takes the array's kind (`h + 1` stays float16, `z + 1` complex64, `d + 1` float64 on the CPU).
- **Boolean arrays**: the scalar is int32 and MLX promotes the booleans to int32 (`m + 1` is int32; `m == 1`
  compares as int32).
- **Matrix judged** (exact values and kinds, both operand orders, every device; `unit_array` and `unit_ops`'s
  logic sub-suite): int32 `[-7, 0, 7]` with 2 for the five arithmetic operators (`/` gives `[-3.5, 0, 3.5]` float32,
  `**` gives `[49, 0, 49]`, `2 ** [0, 1, 3]` gives `[1, 2, 8]`) and the six comparisons; int8 `[100, -100] + 27` →
  `[127, -73]` int8; uint8 `[200] + 55` → 255 uint8; int64 `[2**40] + 1` → 1099511627777 int64 exactly; float32,
  float16, complex64 and (CPU) float64 arrays keep their kind; boolean `[T, F] + 1` → `[2, 1]` int32; a rank-0 array
  stays rank 0; the stops for int8 with 300, uint8 with -1 and uint8 with 256 are guards of `object_contracts`.
  Native Fortran expressions on intrinsic types (`1 + 2`, an integer array plus an integer, `count`, `matmul` of
  real arrays) keep compiling and giving Fortran's results, in the tester and in the installed consumer.

### 2026-11-26 — Phase 4, C7: recoverable graph construction, the design and its disposition (decision 9)

Ruling R0: a design with examples only; no second public graph-building surface is implemented. What follows is
that design, a prototype's assessment, and the decision it leaves to the maintainer.

**Where errors arise today.** Building a graph (every operator and function) stops with `error stop 86` on any
MLX error: a shape mismatch, a float64 operation on the GPU, a slice bound outside the array, a dtype outside
`MLX_DTYPES`. Evaluation, transfer, files, callbacks' `apply`, devices and memory limits are checked procedures that
return a status. A callback of `mlx_function` must never stop (C++ calls it), so today it may use only operations
that cannot fail on its inputs. That is the strongest case for C7: the embedding host and the callback writer need
the construction step to report, not stop.

**Two designs, each with its own failure contract.**

- *A, checked procedures.* A small set of subroutines with an explicit result and a required status, beside the
  operators, which keep their fail-fast contract (no global mode):
  `call mlx_add_checked(a, b, r, status)` and `mlx_subtract_checked`, `mlx_multiply_checked`, `mlx_divide_checked`
  (each also with a real or default-integer scalar for `b`), `call mlx_slice_checked(a, lower, upper, r, status)`
  (a stride through the static `mlx_slice` only, to stay within five arguments), and
  `call mlx_from_checked(x, r, status)` for the transfer kinds (an allocation that fails). On failure: `r` keeps
  what it held (a fresh `r` stays empty, `mlx_is_live(r)` false), the inputs are untouched, no partial node exists,
  `status` is 1 and `mlx_last_error()` holds MLX's message until the next failure. An empty `r` passed on to an
  ordinary operator stops, as every empty array does: there is no silent propagation of empty results.
- *B, validators.* In the style of Phase 2's `mlx_check_indices`, checks of metadata only, without an evaluation,
  run before the ordinary operators: `call mlx_check_broadcast(a, b, status)` (Fortran's leading dimensions
  aligned), `call mlx_check_section(a, lower, upper, status)` and `call mlx_check_device(a, status)` (a float64 array
  with the GPU as the default device). Their limit: they cover the failures the library can predict, not every
  error MLX may raise.

**Callback safety, message lifetime, recovery.** Inside an `mlx_function` callback a checked form lets the callback
return the status it got: the callback never stops, as the contract requires. The message needs one rule the
prototype exposed: mlx-c replaces the callback's own message with "mlx_closure returned a non-zero value", so a
design must keep the callback's message (the first error of a failed `apply`, or both). After any failure the
library and MLX stay usable; a failed construction leaves no live handle.

**Example** (the host-embedding pattern the design serves; design A's names, not part of the library):

```text
call mlx_add_checked(a, b, r, status)        ! a user-supplied shape that may not broadcast
if( status /= 0 )then
    call report_to_host(mlx_last_error())     ! the host keeps running; a and b are unchanged
    return
endif
call mlx_eval(r, status=status)              ! evaluation keeps its own checked form
```

**Prototype assessment** (scratch only, never in the library: `phase4/c7_prototype/`, a copy of the library with a
module holding `proto_add_checked` and `proto_check_broadcast`; `prototype_run.log`, *measured* on the M5's GPU):
(3) + (4) returned status 1 with MLX's broadcast message and left `r` empty; float64 + float64 on the GPU returned
status 1; the next (3) + (3) evaluated to 2, 4, 6; the validator refused (3) with (4) without an evaluation; a
callback built on the checked add returned status 1 from `apply` (the message was mlx-c's, the gap noted above); no
live handle was left. A checked form costs one binding per operation over the existing helpers (`mlxf_check`
already takes a status); a validator costs a host comparison of shapes.

**Disposition.** Deferred: implementing either design is a second public surface that R0 excludes from this run.
Recommended to the maintainer as a follow-up, in this order: B's three validators first (they extend Phase 2's
pattern, add no second form of any operation, and cover the three failures a user meets first), then A's checked
binary operations for callback writers once a SIMPLE callback needs them, with the message rule above. Its rows, if
ruled: `src/core/ops/mlxf_ops_shape.f90` and `mlxf_ops_elementwise.f90` (or a new `mlxf_ops_checked.f90`),
`src/core/mlxf.f90`, `test/consumer/mlxf_api_names.f90`, the shape and elementwise testers, the contract's section 6;
its acceptance: each validator's accept/reject matrix exact, no evaluation added, the guards unchanged. Until then
the quickstart and the contract keep saying what holds today: construction errors stop. This is not recoverable-
error support, and the report says so.

**Host printing and host logical helpers** (decided here, as the phase asks): **deferred**. A `write(formatted)`
for `mlx_array` would evaluate inside an I/O statement, where an MLX failure can neither stop cleanly nor return a
status; a logical `all`/`any` would hide a wait for the device inside an expression that reads as lazy, against the
rule that reductions stay lazy and evaluation is explicit. `mlx_item` (and `mlx_to`) remain the documented path, as
row S6 of the quickstart shows.

### 2026-11-26 — Phase 4: default-integer scalar operators delivered; C7 designed and deferred (Claude, run `mlxf_user_hardening`)

Machine, toolchain and base as Phase 0, with Phases 0 to 3 in the tree. Evidence under
`/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/phase4/` (below `phase4/`). Ruling R0's decisions 8 and 9 as
recommended; the C9 matrix was frozen above before coding; R1's row for `mlxf_api_names.f90` was not needed (no
public name added).

**C9.** `mlxf_integer_scalar` (`mlxf_calls`, implemented in `mlxf_calls_elementwise`) makes the scalar: exact in an
integer array's kind (built from int32 through `mlx_from` and converted, never through a real kind; out of range a
stop naming the value), int32 with a boolean array, weak (`mlxf_weak_scalar`) with a real or complex one. The 22
specifics (`add_ai`, `add_ia`, ... `ne_ia`) are bound to the eleven operator generics of `mlx_array`
(`mlxf_array.f90`, bodies in `mlxf_array_elementwise.f90`), each opening with `mlxf_enter` (rule `entry`). The
frozen matrix passes on both devices in both builds: `test_integer_scalars` (`unit_array` 193 → 232 checks: the
five arithmetic operators both orders, int8/uint8/int64 at their limits, true division, the integer power, booleans
to int32, float32/float16/complex64/float64 kept, rank 0, a native integer expression unchanged) and
`test_integer_comparisons` (`ops_logic` 217 → 249: the six comparisons both orders, int8 at 127, int64 16777217 told
from 16777216, float32, booleans); three guards (`guard_scalar_int8`, `guard_scalar_unsigned`, `guard_scalar_uint8`,
`object_contracts` 30 → 33 members, one CTest entry as before). Installed consumer: quickstart row D21 with its block
in `mlxf_example_differences.f90`, run by `check_install.sh` on both builds; Phase 0's compile probes
(`c9_compile_after.log` against `base_c9_compile.log`): `a + 1`, `2 * a`, an int32 array plus `1_int32` and plus `1`
now compile, as the four forms the base refused; `print *, a`, `if( all(a > 0.) )`, `a(2:3)` and `mlx_from` of
complex(real64) are still refused (deferred or upstream, below). Plant (`plants/`): the range check removed, the
three guards no longer stop (`expect_abort` fails for each).

**C7.** Designed, prototyped in scratch and deferred (the section above): designs A (checked procedures) and B
(validators), callback and message rules, the prototype's results, the recommended follow-up with its rows and
acceptance. Host printing and logical helpers deferred, with reasons; `mlx_item` stays the documented path.

**Gates** (from scratch with the recipe, `build_chain.log`): Debug and Release 0 warnings, fast gate 13 of 13,
installed; `check_install.sh` passed on Debug and on Release with `--require-gpu`; every unit area passed in both
builds; `check_tree.sh` passed (rules `entry`, `docex`, `parity` included); both formatters on every touched Fortran
file. The toy identity set is byte for byte the base's (`identity.log`).

**Costs** (decision 13): none recorded. This phase adds new specifics and changes no existing path; the real-scalar
operators and every operation the toys use compile to the same calls as before (the identity set shows their results
unchanged).

**Decisions taken under delegation.** (1) The integer scalar is built through `mlx_from` and `mlx_astype`'s
binding, not `mlx_array_new_int`, which the parity ledger classes internal (the ledger is outside this phase's
files). (2) A boolean array with an integer scalar promotes to int32 (the scalar is not converted to boolean, which
would turn 2 into true). (3) Only the default integer kind is admitted, as decision 8 says; `int64` scalars are not.
(4) A negative integer exponent follows MLX and is documented, not judged. (5) C7's follow-up recommendation is B's
validators before A's checked forms.

**Files changed:** `src/core/array/mlxf_array.f90`, `src/core/array/mlxf_array_elementwise.f90`,
`src/core/array/mlxf_calls.f90`, `src/core/array/mlxf_calls_elementwise.f90`, `src/core/array/mlxf_array_tester.f90`,
`src/core/ops/mlxf_ops_logic_tester.f90`, `src/test/framework/mlxf_test_registry.f90`,
`test/consumer/mlxf_example_differences.f90`, `doc/policies/binding_contract_policy.md`, `doc/quickstart.md`, this
note. No new file.

**Exit.** The admitted integer expressions compile and pass; existing expressions keep their behaviour (every unit
area, the identity set); C7 has a concrete, reviewable design and disposition; the deferral is not called
recoverable-error support, and construction errors still stop.

**What it means, in short.** `a + 1` and `2*k > 0` now work as a Fortran programmer expects, exactly in the array's
integer kind and refusing to wrap; recoverable graph construction has a concrete, prototyped design waiting for the
maintainer's decision.

**Ruling R2 (2026-11-26, after the fence stop of Phase 4).** The driver's file fence refused
`test/consumer/mlxf_example_differences.f90`, which must hold the block of the quickstart's new row D21 (rule
`docex`) and which the file table had not foreseen. Hans ruled that a row assigns it to Phases 0 to 5 (added to the
file table by the controller); Phase 4's work stands. Applied: the tree was left as it was, the row is in the table,
and the gates were re-run on the unchanged sources: both builds up to date with no recompilation, fast gate 13 of 13
in Debug and Release, `check_install.sh --require-gpu` passed on Release (`phase4/r2_*.log`). The fence's report named
no other file.

### 2026-11-26 — Phase 5: the generated reference, the installed-use guide and the cost model (Claude, run `mlxf_user_hardening`)

Machine, toolchain and base as Phase 0, with Phases 0 to 4 in the tree. Evidence under
`/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/phase5/` (below `phase5/`). Rulings R0 to R2 apply; none
changes this phase. Three rows gained Phase 5 before their edit: the test registry (to register the benchmark),
`src/test/bench/bench.inf`, and `mlxf_ops_index.f90` for one comment (below).

**C12, the reference.** `scripts/generate_api_reference.py` writes `doc/api_reference.md` from the source: rank
2d's inventory (`list_public_api.py`) gives the 316 public names in order; each is followed through `mlxf.f90`'s use
line to its module and resolved there as a generic (every specific), a procedure, a type (public bindings with their
signatures, every operator's operand pairs, public components), a spec type or a constant (its codes). Each specific
shows its dummies as declared (kind, rank, intent, `[optional]`), its result and the comment above it, and each name
links to the binding policy's section for its module. An unresolvable name, a module without a section or an
undeclared dummy fails it (exit 2). `check_tree.sh` runs `--self-test` (a changed dummy and a removed public name
change the output; an unknown public name fails it) and `--check` (stale output fails). A plant on a copy of the tree
(`mlx_save`'s dummy renamed) fails `--check` (`plant_reference.log`). Every public name has its entry (316 of 316,
*exact*). The generator found one defect of this run: Phase 2 had inserted the validator between `section` and its
comment, so `mlx_check_indices` read "the bounds record of a section"; the comment is back above `section`.

**C8, C10, C11, C13, the guide.** `doc/how2s/how2use_installed.md` (new) is the neutral entry: the compatibility
table (exact compiler version, exact shared mlx-c, macOS on Apple silicon or a CPU-only MLX, one submitting thread
and the OpenMP consequence), install and link (CMake with `mlxf_check_lifetime`, pkg-config), one precision/device
matrix (storage, result kind, accuracy and device for every kind, float64 and complex128 included), an errors table
(what stops, what returns a status, callbacks), ownership in short (the checker, views, `mlx_alloc`), and the cost
model below with the bounded-loop advice (evaluate at the batch boundary, watch `mlx_active_memory()` and
`mlx_peak_memory()`; no universal cadence, quickstart row S5). `how2use_from_simple.md` keeps its links and points to
it; the README now leads with use (the first program, building, the links to the guide and the reference, the limits)
and its status paragraph moved to a section of its own below the API table; the quickstart links both.

**C11, the costs.** `src/test/bench/mlxf_bench_user_costs.f90` (new, `mlxf_test_exec test=bench_user_costs
suite=costs`, named-only: no new executable, no CTest entry) measures the four cases rank 2f's benches lack: per-step
against batched evaluation, element reads against one copy, `mlx_from`/`mlx_to` against `mlx_alloc`/`mlx_view` for
64 MiB, and a callback called directly, through `mlx_function` and compiled (warm, and its first application labelled
cold), each route's correctness checked once outside the timing, five repeats after a warm-up, median and range.
Two runs on the Release build (`bench_user_costs.log`; GPU and CPU device; load 3.7 to 4.0 before each, *measured*):
on the GPU an evaluated small step costs 152–216 µs against 6.5–7.3 µs batched; an element read by `mlx_item` 19 µs
against 0.15 µs for all 4096 by `mlx_to`; 64 MiB in and out 3.1–3.2 ms (42 GB/s) by copies and 4.5–4.8 ms through a
fresh `mlx_alloc` buffer (its allocation and fill dominate); `exp(x)*2+1` 157 µs direct or through `mlx_function` and
142 µs compiled; the compiled first application 140 ms in a fresh process, 1.3 ms with MLX's kernel cache warm. The
table is in the guide; Claude's review measured 181 µs, 21 µs and 14 GB/s on the M2 Ultra, of the same order. These
are measurements of this machine, not floors.

**Gates** (from scratch with the recipe, `build_chain.log`): Debug and Release 0 warnings, fast gate 13 of 13,
installed; `check_install.sh` passed on Debug and on Release with `--require-gpu`; every unit area passed in both
builds; `check_tree.sh` passed with the reference's checks (`check_tree_final.log`, after the last document edit);
both formatters on every touched Fortran file. The toy identity set is byte for byte the base's (`identity.log`).

**Decisions taken under delegation.** (1) The reference is plain generated Markdown with one fenced block per name,
linked to the policy's sections rather than duplicating them (decision 10: no second hand-written contract). (2) A
type's private components are left out (a bare `private` before `contains`). (3) The cost benchmark reports medians
of two runs in the guide and keeps both runs' lines in the log. (4) The guide's name is `how2use_installed.md`, as
the file table names it; the SIMPLE guide keeps its name and links.

**Files changed:** `scripts/check_tree.sh`, `src/test/framework/mlxf_test_registry.f90`, `src/test/bench/bench.inf`,
`src/core/ops/mlxf_ops_index.f90` (a comment), `README.md`, `doc/quickstart.md`, `doc/how2s/how2use_from_simple.md`,
`doc/code_base_map.md`, this note; new: `scripts/generate_api_reference.py`, `doc/api_reference.md`,
`doc/how2s/how2use_installed.md`, `src/test/bench/mlxf_bench_user_costs.f90`.

**Exit.** C8 and C10 to C13 are documented in the guide and the reference, current by construction (the reference by
its checks, the examples by `docex` and the installed check); full reference coverage and the staleness check pass;
the performance numbers name the machine, the build, the boundary and the protocol; no performance is promised.

**What it means, in short.** A user can now find every name with its arguments and kinds, learn from one page what
the library needs and where its precision, error and ownership limits are, and see what a step, a read, a copy and
a compiled call cost on real hardware.

### 2026-11-26 — Phase 6: validation and hand-over (Claude, run `mlxf_user_hardening`)

Machine, toolchain and base as Phase 0, with Phases 0 to 5 in the tree. Evidence under
`/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/phase6/` (below `phase6/`). Rulings R0 to R2 apply.

**Gates on the final sources** (`chain.sh`, `chain.out`): Debug and Release from scratch with `MLXF_WERROR=ON`, 0
warnings, fast gate 13 of 13 (Release 10.6 s of 60, *measured*), every unit area in both builds (`units_*`), the
installed consumer on Debug and on Release with `--require-gpu`, `check_tree.sh`; `release_gate.sh --allow-dirty`
passed (`release_gate_final.log`: the snapshot's Debug and Release, their fast gates and installed consumers on the
GPU, `check_embed.sh`, `check_toy_offstate.sh`, no side effect); `ci_cpu_job.sh` passed in Release and in Debug
against a CPU-only MLX 0.32.4 / mlx-c 0.8.0 (`ci_cpu_final_*.log`), built in scratch from the exported sources the
maintainer's `build_mlx_deps.sh --cpu-only` had left in `~/src/mlx-fortran/.deps/work-cpu` (copied, read only),
with that script's flags (`build_cpu_deps.sh`, `build_cpu_deps.log`). The toy identity set is byte for byte the
base's (`identity.log`); the release gate's off-state table equals the executable's (135 lines). RoPE's cases pass
in `unit_fast` on this GPU (`applegpu_g17d`).

**Found and fixed in this phase.** (1) The first release gate failed: the builds wrote `scripts/__pycache__` into the
snapshot, because Phase 2's `check_rules.py` and `check_consumer.py` and Phase 5's `generate_api_reference.py`
import sibling modules (`release_gate_try1.log`). Each now sets `sys.dont_write_bytecode` first; the second gate
passed with no side effect. (2) An independent review of the new tests against section 6 (a read-only subagent, its
findings listed in this entry's evidence) found checks weaker than the frozen bounds; the testers were tightened,
no bound loosened: the empty integer extrema compared exactly in int64 (they had passed through float32), size and
rank checks against vacuous passes, constant fixtures shrunk so that every partial sum is exact in float32 (int16 and
uint16 to 4096 elements, int32 2e9 to 8: the frozen one-epsilon bound assumes exact sums), `ddof=1` on varying data
(8e18 and its root), a GGUF save's status and a chmod's result asserted, the framework's seed in `test_norm2_range`,
and two comments put back above the procedures they describe. A first Release build of the tightened testers failed on
`-Werror=function-elimination` (`try_final1/`), fixed by separate statements. Gaps the review named and left open:
one operand order only for the narrow-kind and real integer-scalar cases, a few slab-form edge cases of the validator,
no load-back of a replaced checkpoint, no evaluation failure on the CPU device.

**Upstream status** (`doc/collaboration/apple_questions.md`): checked against MLX's main branch `5c8989446`
(2026-11-23): question 31's request (a) is met there by commit `1c141875c` (saves through a temporary file, symlinks
followed); 33 (integer mean), 34 (Euclidean norm) and 35 (unchecked indices) are unchanged. Nothing was sent.

**At the end of this M5 run, the second Metal GPU architecture was open** (closed by the 2026-11-27 closeout
entry below). This run has the M5 Ultra only. Decision 12 requires the fixed-fixture
evidence, RoPE's cases included, on two distinct architectures before release readiness is claimed; it is not
claimed. What it needs: `scripts/release_gate.sh` and every unit area on another generation (the M2 Ultra of the user
review), with its `applegpu_*` identifier, compiler and dependency facts and numerical logs. The two-architecture rule
is not written into the test-environment policy, since it is not adopted until a second machine runs it.

**P1 local actions**: C1 (Phase 1), C2 (Phase 1), C3 (Phase 2) and C4 (Phase 2) are closed locally, each with its
plant. **Documented limits remaining**: construction errors stop (C7 deferred), float64 on the GPU, complex128,
compiler/platform/thread restrictions, unchecked indexing without the explicit call, the lifetime checker's blind spots.

**Decisions taken under delegation.** (1) The CPU-only MLX built in scratch from the maintainer's exported sources
rather than from a fresh export of the read-only clones. (2) The testers tightened in this phase, rather than the gaps
only reported. (3) The two-architecture rule left out of the policy until adopted. (4) The plan stays in `planned/`,
its status updated, since release readiness is open.

**Files changed:** `scripts/check_rules.py`, `scripts/check_consumer.py`, `scripts/generate_api_reference.py`,
`src/core/ops/mlxf_ops_reduce_tester.f90`, `src/core/io/mlxf_io_tester.f90`,
`src/core/linalg/mlxf_linalg_matrix_tester.f90`, `src/core/transforms/mlxf_transforms_tester.f90`,
`src/core/ops/mlxf_ops_logic_tester.f90`, `doc/collaboration/apple_questions.md`,
`doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md`,
this note; new: `doc/implementation_notes/completed/mlxf_user_hardening_report.md`.

**Exit.** Section 6's release evidence exists for this machine (both builds, installed, CPU-only, the gate, the test
budget unchanged at 13 entries), every P1 local action is closed, and the report distinguishes protection, documented
limits, the C7 deferral and the open upstream drafts. Release readiness is not claimed: the second architecture is
missing, as decision 12 foresees.

**What it meant at this run's handover.** The hardening was validated on this machine; the second GPU
generation was still missing. The 2026-11-27 closeout supersedes that release assessment.

### 2026-11-27 — C11 benchmark correctness follow-up, before implementation (Codex)

Requested by Hans: make incorrect or nonfinite benchmark results fail the process, keep timings non-gating,
and rerun on the M2 Ultra. Base `0f8252b2d2bd7dc0e76cd29cf54e785b64b68b59`; the existing unstaged Apple tracker
and history additions are preserved. Baseline sources and evidence are retained under
`/tmp/mlxf_bench_user_costs_fix_2026-11-27/`; the two unmodified M2 measurements are in `~/m2_evidence/`.

**Contract and decisions.** Retain the four workloads, five timed repeats after a warm-up, public command,
13-entry CTest budget and device selection through `test_devices`. Use `mlxf_test_utils` assertions so the
existing executable exits 1 when correctness fails. Check finite values and whole outputs outside the timed
intervals, including after each repetition; use a double-precision Fortran recurrence and `exp(x)*2+1` as
independent references, exact comparisons for reads and the constant 3 copy fixture. Preserve the existing
`1e-5` numerical bound (recorded here before validation, inherited from the benchmark); no bound on timings.
Check status and allocation/shape before consuming a returned view or callback output. Do not suppress or
clear the upstream initialization overflow flag (Apple question 37).

**Files and change type.** Test-only: `src/test/bench/mlxf_bench_user_costs.f90`; the named numerical bound in
`src/test/framework/mlxf_test_defs.f90`; this living note and `doc/history/2026-11.md`. No library or public API
change, no extra executable or CTest entry in the repository, no benchmark failure-injection CLI.

**Implementation and validation exit.** In scratch copies, first show finite-wrong and NaN callback results
can leave the original executable at status 0. After the change, finite-wrong, NaN and infinity results,
including errors away from a shared view's last element, and failed statuses must produce assertion failures
and nonzero exits without invalid access. Artificially slow timing values must still pass. Format both touched
Fortran files, run the static gate, build Debug and Release with zero warnings and their 13-entry fast gates,
and run the benchmark on both M2 devices in both builds (two Release measurements). Keep fault-injected sources
and binaries outside the repository; record their exit codes and summaries. Stop and report rather than widen
the numerical bound or change a library contract if a valid fixture fails it.

### 2026-11-27 — C11 fix validated on the M2 Ultra (Codex)

**Delivered.** `bench_user_costs` now registers one assertion suite per selected device and checks the finite,
complete results after each repetition, outside its timed interval. The recurrence has an independent
double-precision host reference using the same float32 coefficients; the three expression routes use the
host's double-precision `exp(x)*2+1`. Reads and the constant copy fixture are checked bit for bit. The shared
route checks its entire result view, rather than only its last element. Status, allocation and shape checks
guard returned pointers and callback outputs before use; their successful paths record no timed assertions.
The numerical bound is the previous float32 `1e-5`, named `USER_COST_TOL` in the test definitions. No timing
bound, public API, library implementation or CTest entry changed. Device selection now relies solely on
`test_devices`, preserving its headless/CPU-only session checks.

**Failure-path evidence.** Temporary source mutations of the baseline returned `RESULT: PASS`, zero assertions
and exit 0 for both a finite-wrong callback result and a NaN result. On the fixed sources in both Debug and
Release, nine mutants each returned exit 1 with a recorded assertion: finite-wrong callback output, NaN,
infinity, a NaN in element 5 of the large shared result, failed allocation status with a null view, failed
callback status with no outputs, an absent output list, an empty output list, and an output of the wrong size.
A clock scaled by one million passed in both builds (159 assertions on the CPU): timing remains non-gating.
These mutations ran on the CPU device; their timings are not performance measurements. No failure-injection
switch or extra repository executable was added.

**M2 execution.** Apple M2 Ultra, `applegpu_g14d`, GNU Fortran 16.2.0, MLX 0.32.4 / mlx-c 0.8.0;
`MLX_ENABLE_TF32=0`, one OpenMP thread. The normal benchmark ran on both CPU and GPU in Debug and twice in
Release: each returned exit 0, two passing test groups, **318 assertions passed, zero failed**. The builds
emitted zero warnings (the separate Debug build had `MLXF_WERROR=ON`); their full fast gates passed **13/13**
in 24.94 s Debug and 14.22 s Release, measured. The Release executable is installed in `build/bin` as well as
the build-tree executable in `build/test`. The upstream device-initialization overflow flag is unchanged;
finite-value assertions judge results, not sticky flags left by initialization.

**Evidence and exit.** `~/m2_evidence/bench_correctness_2026-11-27/` holds normal logs, build/gate logs, source
hashes, baseline sources, the mutation runner and per-mutation sources/logs/exit-code tables. Scratch build
and probe binaries remain in `/tmp/mlxf_bench_user_costs_fix_2026-11-27/`. The top-level
`~/m2_evidence/bench_user_costs.log` and `bench_user_costs_run2.log` are the fixed Release runs; their originals
are preserved under `previous_benchmark_logs/` in the evidence folder. Both Fortran formatters, the static
gate and whitespace checks passed. This closes the C11 correctness-validation follow-up recorded in the
2026-11-26 history entry. Files changed in this follow-up: `src/test/bench/mlxf_bench_user_costs.f90`,
`src/test/framework/mlxf_test_defs.f90`, this note and `doc/history/2026-11.md`; prior Apple tracker edits kept.

### 2026-11-27 — Second-architecture validation closed; remaining release conditions (Codex)

Hans requested the M2 results be reconciled into this plan and its report, the second-architecture check closed,
and remaining release blockers listed. **Decision 12's second-Metal-architecture condition is closed.** This
supersedes the M5-only handover's missing-machine statements; it does not declare a tagged release complete.

| Evidence | M5 Ultra, original run | M2 Ultra, follow-up |
| --- | --- | --- |
| Provenance | Claude's recorded Phase 6 evidence under `/Users/hael/agent_runs/mlxf_user_hardening/scratch/keep/phase6/` | Local logs inspected by Codex under `~/m2_evidence/` |
| Device / OS | `applegpu_g17d`, macOS 27.2.1 | `applegpu_g14d`, macOS 26.7.3 |
| Compiler / dependencies | GNU Fortran 16.2.0, MLX 0.32.4, mlx-c 0.8.0 | GNU Fortran 16.2.0, MLX 0.32.4, mlx-c 0.8.0 |
| Debug and Release | Recorded zero-warning builds, 13/13 fast gates, all unit areas | Snapshot release gate at `0f8252b` passed both builds, 13/13 each; the benchmark fix's later builds also passed 13/13 each |
| Installed package | Recorded `--require-gpu` checks in both builds | Both snapshot installs passed consumers/examples on CPU and GPU, package isolation/refusals and pkg-config |
| Complete release gate | Recorded `release_gate_final.log` passed with `--allow-dirty`, embedding and MLX-free toy checks included | `release_gate_0f8252b.log`: passed in 173 s, embedding and MLX-free toy checks included, no snapshot/editor side effects |
| Numerical evidence | Recorded independent-reference checks, RoPE included; CPU-only Debug/Release CI is separately recorded | Twelve directly run Release unit areas: 8,201 assertions, zero failures; `unit_fast` 152/152, RoPE GPU seeds 1/2/3 at 20.730/14.239/18.203 eps32, below the unchanged 41.5-eps32 bound |

`MLX_ENABLE_TF32=0` was used. M5 evidence is the original run's record, not a newly executed M5 run by Codex.
The M2 full snapshot is `0f8252b2d2bd7dc0e76cd29cf54e785b64b68b59`; `src/core` and `src/defs` are unchanged
from the hardening commit `90f5932`. The later unstaged changes affect the benchmark, one test tolerance and
records, not library implementation. Their separate M2 evidence is in `bench_correctness_2026-11-27/`:
Debug and two Release benchmark runs, 318/318 assertions per run on CPU and GPU, nine failing mutations per
build, and a passing non-gating timing control. This later evidence does not replace a final tagged snapshot gate.

**Remaining release blockers.**

| ID | Owner and condition | Required closure |
| --- | --- | --- |
| RB1 | Compiler / library transfer boundary: empty host-array constructors still violate binding-policy section 4. `mlx_from([integer(int32) ::])` and its real32 counterpart exit 86 on both M2 devices. Named zero-length real32, int32 and int64 arrays pass. A Fortran-only assumed-rank probe returns size/shape `-1` for the constructor at both `-O0` and `-O3` with GNU Fortran 16.2.0; named-array control is `0`. This narrows the Phase 2 report and belongs to the corrupt-empty-descriptor family in compiler issue 6, not an MLX numerical operation. | Prefer a safe transfer-boundary fix with named-array and empty-expression regression cases in Debug/Release on CPU/GPU, preserving empty shape and avoiding a giant allocation request. A temporary unsupported-form restriction instead requires an explicit contract decision and matching user documentation; none has been adopted. |
| RB2 | Release artifact: HEAD `0f8252b` is untagged, and the benchmark fix/records remain unstaged. The successful M2 full release gate predates the benchmark fix and was not run with `--require-tag`. | After RB1 is resolved, the maintainer commits the intended candidate and tags the project version; `scripts/release_gate.sh --require-tag` must pass from that clean tagged tree. This is the existing rank-2b release criterion, not another architecture measurement. |

Update, 2026-11-27: RB1 closed by `mlx_from`'s refusal of an array of unknown size (Hans's ruling (a)); RB2
withdrawn: when to tag a release is the maintainer's decision, outside the plans (hans, 2026-11-27).

RB1 is a confirmed release-contract problem outside the original C1–C14 implementation rows; it is not a
reason to reopen the completed architecture test. No additional original P1 local acceptance failure was
found. C7's deferred recoverable graph-construction API, documented dtype/compiler/thread limits, residual
test-coverage improvements and upstream drafts remain follow-ups, not additional release gates. Apple question
37's initialization overflow flag is separate from benchmark result correctness and remains an unsent upstream
item. First hosted-CI observations retain the release-hardening plan's explicitly non-gating status.

**Reproducers and records.** `~/m2_evidence/closeout_2026-11-27/` holds the empty-host-array consumer, its ten
per-device/form logs and exit codes (six passing named-array controls, four failing constructor cases), and the
Fortran-only descriptor reproducer/logs. The library was not changed during this closeout. Updated records:
this plan, its report, the roadmap, implementation-note index, history and compiler issue 6. Static, whitespace
and local-link checks validate this documentation change; prior benchmark source edits are preserved.
