# User-facing hardening: consolidated review and prioritized plan

Status, 2026-11-26: **planned, for review; implementation has not started**. Hans requested the consolidation
and this plan; that request does not constitute a ruling on the proposed API changes or a launch instruction.
Written against `96c5c5c272af7b688047f841897dfc98e9f30fdf`, with the existing working-tree RoPE test adjustment
and Claude review. The implementation pins its actual base in Phase 0. Supersedes: no implementation plan;
this note is the single owner of the two user reviews' follow-up work. Related work:
[refactoring](mlxf_refactor.md), [release hardening](mlxf_release_hardening.md), and
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

Only decision 1 records a user instruction. Decisions 2–13 are **recommendations**, not claimed owner rulings;
the implementation records any accepted amendments here before changing a public contract.

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
| `doc/implementation_notes/planned/mlxf_user_hardening.md` | Single contract, decisions, acceptance and progress record | all |
| `doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md` | Ranking proposal, links, delivered evidence and rulings | planning, 0, 6 |
| `doc/collaboration/apple_questions.md`, `doc/compiler_issues/README.md` | Dedupe/record upstream evidence; GCC file only if new verified facts | planning, 0–6 |
| `scripts/probes/user_statistics_probe.c`, `scripts/probes/user_range_probe.c` (new) | Minimal direct mlx-c reproducers/controls | 0–3 |
| `src/core/ops/mlxf_ops_reduce.f90`, `src/core/ops/mlxf_ops.f90` (interfaces until moved) | C1 and floating mean, empty extrema; own helpers where practical | 1, 3 |
| `src/core/linalg/mlxf_linalg_matrix.f90` | Scaled Euclidean norms | 3 |
| `src/core/ops/mlxf_ops_reduce_tester.f90`, `src/core/linalg/mlxf_linalg_matrix_tester.f90` | Integer/range/empty regressions | 1, 3 |
| `src/core/io/mlxf_io.f90`, `src/core/io/mlxf_io_tester.f90` | Save transaction and failure-preservation tests | 1 |
| `src/core/runtime/mlxf_libc.f90` | Temporary-file/rename/cleanup calls, if needed | 1 |
| `src/core/ops/mlxf_ops_index.f90`, `src/core/ops/mlxf_ops_index_tester.f90` | Explicit bounds validation API and fixtures | 2 |
| `src/core/array/mlxf_array.f90`, `mlxf_array_elementwise.f90`, `mlxf_array_operations.f90` in that folder, or delivered rank-2d owners | Integer scalar bindings and shared helpers; no general ownership rewrite | 4; 1–3 only if shared signature/helper changes are needed |
| `src/core/array/mlxf_array_tester.f90`, `src/core/ops/mlxf_ops_logic_tester.f90`, `src/core/ops/mlxf_ops_math_tester.f90` | Scalar promotion/native-intrinsic controls; use actual owning tester after Phase 0 mapping | 4 |
| `src/defs/mlxf_defs.f90`, `src/core/mlxf.f90` | Validator spec if needed; explicit new public exports | 2, 4 |
| `src/test/mlxf_test_defs.f90`, `src/test/mlxf_test_registry.f90` (then `framework/`) | Shared frozen bounds and area/guard registration, only if needed | 1–4, 6 |
| `src/core/transforms/mlxf_transforms_tester.f90` or existing transform owner selected in Phase 0 | Derivative controls for changed compositions, if needed | 3 |
| `scripts/check_rules.py`, `scripts/check_consumer.py`, `scripts/mlxf_consumer_checks.py` (last two new) | Shared lifetime analysis, consumer entry point, planted-rule self-tests | 2 |
| `CMakeLists.txt`, `cmake/mlxfConfig.cmake.in`, `scripts/check_install.sh` | Install/check consumer tooling and new examples; optional CMake helper | 2, 4–6 |
| `README.md`, `doc/quickstart.md`, `doc/how2s/how2use_from_simple.md`, `doc/how2s/how2use_installed.md` (new) | Immediate guidance, compatible general-user entry, architecture/precision limits | 0–6 |
| `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md`, `doc/architecture_principles.md` | Current contract with implemented changes; two-architecture release rule only when adopted | 1–6 |
| `test/consumer/mlxf_example_user_safety.f90` (new), `test/consumer/CMakeLists.txt`, existing examples if needed | Installed compile/run evidence for guidance and API additions | 0–5 |
| `scripts/generate_api_reference.py`, `doc/api_reference.md` (new), rank-2d API inventory tool | Source-derived signatures, coverage and semantic links | 5 |
| `scripts/check_tree.sh` | Shared checker/reference checks and planted negative controls | 2, 5 |
| `src/test/bench/mlxf_bench_user_costs.f90` (new, only missing cases after 2d/2f) | Named-only timings; no new executable or CTest process | 5 |
| `scripts/release_gate.sh`, `test/CMakeLists.txt` | Record/check release evidence and keep process budget, if needed | 6 |
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
