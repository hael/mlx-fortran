# mlx-fortran: a small Fortran array library, driven by SIMPLE's pipelines

Status, 2026-11-21: Phases 0 and 1 delivered (Progress); Phase 1 review fixes in the owner's working tree;
Phase 2 planned. This revision updates the plan only; it does not start implementation or benchmark runs.
Decision 42 adopts SIMPLE's production block scorer as the architectural template and future CPU baseline.
The original launch record follows; its measurements remain historical evidence.
Original launch, 2026-11-20, fourth revision: after an independent review (6 P1, 15 P2), after Hans's rulings 26 to 28, after
Hans's design review (the layering, the pipeline-first milestone, precision modes, the ownership hole, the
buffer protocol, graph compilation, recoverable errors, equivalent work), and after the import of SIMPLE's and
XEMA's house rules (`doc/architecture_principles.md`, rulings 35 to 37). Base:
the scaffold's first commit, made by Hans before launch (a launch precondition, section 8), SIMPLE
`5709265cb`, MLX `v0.32.4` (`36969c09`), mlx-c `v0.8.0` (`a26f2d58`). Supersedes: none. Depends on: mlx-c
0.8.0 as a shared library (validated: yes, Homebrew bottles on the M2 Ultra, pre-launch checks); the scaffold's
build and gate (validated: yes, Debug and Release on the M2 Ultra); SIMPLE's `polar_matching_bench`
(validated: yes, M3 Pro, 2026-10-21, before the full-row draw; re-measured in Phase 0).
For Phase 2, SIMPLE is pinned to `7ec7e29720b3e57c2a56a6a7ab754e6f6c57fe35`, containing the production
block scorer introduced in `5481d42c575556c11e298dfae36c51ec9a058529` (source checked, 2026-11-21;
new Mac baseline not yet measured). MLX and mlx-c pins are unchanged. Record the mlx-fortran snapshot after
the owner's Phase 1 fixes before starting Phase 2; do not run against a concurrently changing worktree.

## 1. Why

SIMPLE's collaboration with Apple ports SIMPLE to the unified-memory Macs through MLX. SIMPLE is Fortran and
MLX has no Fortran interface. Its production polar calculator now scores blocks through complex GEMM, inverse
FFTs and the existing posterior draw. SIMPLE's `prob_table_matrix_scoring_report.md` records dense scoring at
0.38-0.40 of the previous cost, dense fills about 1.4 times faster and a whole bgal run about 9 % shorter on
the Dell; these are reported CPU results, not Mac or GPU measurements. This plan builds a small, general
Fortran array library and proves its first complete pipeline against that production scorer, retaining its
domain ownership and compact table-entry boundary while measuring GPU tiling and scheduling. The earlier
`matrix_t` results and timing shares in decision 28 remain history; the prospective GPU gain needs a new
baseline and current production profile (decision 42).

## 2. Contract

### Layers

| Layer | Owns |
| --- | --- |
| SIMPLE matcher and probability tables (a later SIMPLE plan) | outer particle batches, candidate lists, seed preparation, refinement and assignment; the builder owns `polarft_calc` |
| SIMPLE `polarft_calc` (a later SIMPLE plan) | polar scoring, derived reference generations, reusable CPU/GPU workspace and resident reference tiles, exposed through a domain scoring operation |
| public `mlxf` interface | Fortran array semantics, ownership, operations, evaluation, errors |
| private generated bindings (`mlxc_*`) | exact correspondence to the linked mlx-c headers; broad, never public |
| MLX | graph execution, allocation, CPU and GPU kernels |

The generated layer covers every header it can; the public API grows only with a demonstrated need
(decision 29). The library keeps no caches of its own beyond MLX's allocator: accelerator state that is reused
(a reference tile kept on the device across particle blocks) is an `mlx_array` its caller owns.

### Invariants

- **A library, not a port.** mlx-fortran depends on mlx-c only. No SIMPLE source, type, constant or name
  enters it. SIMPLE's kernels appear here as tests and benchmarks on synthetic data of SIMPLE's sizes, in
  test-only code that is never installed. SIMPLE is read-only in this plan.
- **Fortran's view.** Users see column-major arrays, 1-based dimensions, 1-based index values and 1-based
  positions; the library translates (decisions 6, 7). A user never writes a C-order shape or a 0-based axis.
  The one exception is the source of a custom Metal kernel (decision 18).
- **No double frees, no silent use after free** (decision 8): supported uses of handles are exact (the leak
  gate); unsupported uses (bitwise copies) end in a diagnosed stop, never in corrupted memory.
- **Data movement is exact.** Copy-in, copy-out, views, reshape, transpose, permute, slices and concatenation
  preserve every byte: float32, complex64 and the integer and boolean kinds on both devices, float64 on the
  CPU device.
- **The arithmetic is MLX's.** The library converts nothing silently and adds no numerics beyond index and
  position shifts and dtype-preserving scalar operands (decisions 7, 11). Correctness is established in full
  float32 (`MLX_ENABLE_TF32=0`, decision 15); GPU results are compared with tolerances; atomic reductions on
  the GPU are not reproducible from run to run; some float64 operations run in float32 inside MLX even on the
  CPU (decision 10).
- **Off state.** A program that links the library and does not call it pays nothing; initialisation (error
  handler, device check) runs on the first call.

### What the check of the sources found (2026-11-20, at the pinned tags)

- mlx-c's headers are generated and regular: 669 to 674 prototypes by two regex counts, 267 in `ops.h`, nearly
  all `int f(mlx_array* res, ..., const mlx_stream s)`. Every handle, `mlx_device_info` included, is
  `typedef struct { void* ctx; }` passed by value. The other structs are the `mlx_optional_*` value pairs and
  `mlx_io_vtable`, a struct of function pointers passed by value to `mlx_io_reader_new` (IO is out of scope).
  The headers also hold `static mlx_array mlx_array_empty;`, `#ifdef` blocks for float16 and for MSVC, and
  function-pointer parameters written inline. Every operation this plan names exists, among them
  `mlx_cumsum`, `mlx_min_axis`, `mlx_take_along_axis`, `mlx_where`, `mlx_scatter_add`, `mlx_async_eval`,
  `mlx_compile` with `mlx_closure_new_func_payload` and `mlx_vector_array_*`, `mlx_fast_metal_kernel_*` and
  `mlx_device_count`. mlx-c exposes no setter for MLX's configuration (`MLX_ENABLE_TF32` is read from the
  environment).
- `mlx_metal_is_available` is `return true` in every Metal build; whether a GPU can be opened is
  `mlx_device_count(MLX_GPU)`. Without a device a Metal build cannot allocate on either device.
- Metal has no float64; a GPU operation with a float64 operand throws when it is built (`array.cpp`). On the
  CPU, `exp` and `sincos` compute float64 through float32 SIMD and every FFT casts to float32 or complex64.
- **Matrix units.** On GPUs with neural accelerators (NAX: macOS 26.2 or later and a recent GPU generation,
  `backend/metal/device.cpp`; the M5 has them, the M2 Ultra not) MLX runs float32 matrix products at reduced
  precision unless `MLX_ENABLE_TF32=0` (`use_nax` in `backend/metal/matmul.cpp`, `docs/src/usage/precision.rst`:
  results "can differ from a full-precision reference by several orders of magnitude more than float32
  rounding alone would explain"). Complex inputs never take the NAX path.
- complex64 GEMM has its own tile parameters on Metal; complex64 scatter is allowed for `Sum` only. The Metal
  FFT plans any size: Stockham to 4096, Rader and Bluestein to 2048, four-step beyond.
- `argpartition` returns uint32 indices; `topk` returns values only, the k largest.
- `FFTNorm::Forward` gives an unscaled inverse by scaling back by n (one extra pass); `Backward` is the 1/n
  inverse.
- `mlx_array_data_*` does not evaluate. `mlx_array_new_data_managed` wraps the caller's buffer without a copy
  only when Metal accepts it; otherwise MLX copies and calls the deleter at once.
- **Memory failures.** The Metal allocator throws only for a single buffer above `maxBufferLength`, for its
  resource limit, or when `newBuffer` fails; `set_memory_limit` makes evaluation wait and release cached
  buffers, and over-subscription of unified memory pages rather than failing.
- mlx-c's default error handler prints and calls `exit(-1)`. mlx-c's exported CMake config works only for the
  shared library. Homebrew ships MLX 0.32.4 and mlx-c 0.8.0, the pinned pair.
- **gfortran 16.2 copies allocatable handle components bitwise.** In intrinsic assignment of a derived type, a
  plain component of a type with a type-bound defined assignment gets that assignment, but an allocatable
  scalar or allocatable array component is copied without it, at `-O0` with checks and at `-O3` (probe of
  2026-11-20, Progress). F2018 10.2.1.3 requires defined assignment for allocatable components too: a
  compiler bug. `allocate(..., source=)` copies bitwise as the standard says. Self-assignment and function
  results behave.
- **SIMPLE's table entry at `5709265cb`.** The dense 3D table (`eul_prob_tab.f90`) calls `gen_posterior_val`
  or, for a seeded shift, `gen_posterior_val_bank` (the particle shifted once on its side). Per pair: the
  distances d(rot) = 1 + c2r(rot) / (2 nrots wsq) over all nrots rotations (`euclid_dists_from_crvec`; no
  clamp at 0; above -log(TINY) the invalid marker `huge`); then `draw_posterior_row` draws one rotation over
  the full row with weights exp(-T (d - d_min)) (zero where the exponent reaches 80), the variate u keyed on
  the scope, the particle and the reference (`RND_FAM_INPL`), T the particle's posterior temperature; the
  entry is (d(irot), irot). The full-row draw replaced the draw among the 20 lowest on 2026-10-24
  (`7dfea61a5`), after the October benchmark. `polar_matching_bench` at the base draws the same way
  (`pair_finish`), reports thread µs per pair for sums, inverse FFTs, and distances with the draw, and sweeps
  the teams nthr, nthr/2 and 1 itself.
- Decision 20's distances were checked in numpy (random rings, pftsz 32, nk 10): with the memo arrays as SIMPLE
  defines them (`ft_ref` the forward FFT of the full reference ring, the stored half extended by Friedel
  symmetry; `ft_ref2` the conjugate of the FFT of |R|^2; `ft_ctf2` and `ft_ptcl_ctf` the FFTs of CTF^2 and of
  X CTF), d equals sum_k w_k sum_j |X_j - C_j R_(j-r)|^2 / (2 wsq) over the full ring to 3.6e-16 relative,
  `wsq` being the self-term over the stored half ring. The DC and Nyquist bins are real when pftsz is even.

### Production block scorer checked for this revision (2026-11-21, SIMPLE `7ec7e2972`)

- `src/main/pftc/simple_polarft_block.f90`, a submodule of `simple_polarft_calc`, owns the block work's
  construction/destruction and implements `score_block_posterior`: particles of one half, an ordered list of
  reference IDs, temperatures and optional shifted-particle banks in; one distance and rotation per pair out.
  It combines the two shell sums into a product of depth `2*nk`, transposes/conjugates the products to
  contiguous angular bins, runs c2r transforms and calls the shared `draw_posterior_rvec` tail.
- `simple_polarft_memo` builds `ft_ref_bins` after reference memoization, outside the scoring region;
  `ref_gen_bins == ref_gen` is checked on scoring. The calculator owns the memo and per-thread workspace;
  `simple_matcher_memory` accounts for them. The GPU analogue needs the same explicit owner and validity
  checks, with a workspace per submitting pipeline rather than per OpenMP worker.
- `simple_eul_prob_tab%fill_tab_range` selects work and processes one block per OpenMP task: seed, score,
  refine. `simple_eul_prob_tab_neigh%fill_tab_subspace_range` uses the block scorer for the `state` mode's
  shared representatives; pooled members and `geom` cones remain per pair. The GPU schedule must split the
  CPU work from submission to obey the binding's one-thread contract.
- CPU products are always 16 particles by 32 references, with missing rows/columns padded. SIMPLE's report
  records OpenBLAS shape/column-dependent rounding and row-position invariance on the tested build; those
  findings do not establish GPU invariance. It records 70 changed posterior draws in 320,000 pairs despite
  relative loss differences of 2.5e-7 to 7e-7, and +1.7 GiB per part for the reference memo at 5,000 directions.
  Candidate sharing, posterior sensitivity and total memory therefore belong in the GPU measurements.
- `src/main/commanders/test/simple_polar_matching_bench.f90` dispatches `block_prod` to the real
  `polarft_calc%score_block_posterior`. Its timed region includes particle-term packing, products, transforms,
  draws and writing entries, with the reference memo prepared beforehand. Its internal part timings are
  uninstrumented (zeros); they must not be interpreted as measured stage costs. The driver defaults to 2,000
  particles split between halves, sweeps CPU block sizes 4, 8 and 16, and caps one-thread runs at 200 particles.
  `suite=fills` exercises production fill/assignment routes across teams, batches and parts; `suite=neigh`
  measures representatives, pooled members and cones separately.

Evidence: SIMPLE's `doc/implementation_notes/planned/prob_table_matrix_scoring_report.md`,
`simple_polarft_corr_tester%test_block_kernel`, the scorer and its production callers at the new pin.
The report's Dell results were read, not rerun for this plan revision.

## 3. Decisions and rulings

Numbered, dated, never renumbered; later rulings cite and replace by number. Decisions marked "revised" were
rewritten before launch after Hans's design review of 2026-11-20.

1. (2026-11-20, Hans) Own repository `~/src/mlx-fortran`, public, MIT (as MLX and mlx-c); SIMPLE consumes it
   as an installed package. Offering it to ml-explore for hosting is Hans's, with Apple.
2. (2026-11-20) Toolchain: GFortran 14 or newer (Homebrew GCC 16.2 on the Macs), CMake 3.25 or newer,
   `-std=f2018`; macOS on Apple silicon. flang and Linux are not gated here.
3. (2026-11-20) mlx-c 0.8.0 or newer as a shared library: Homebrew's bottles, or `scripts/build_mlx_deps.sh`
   (MLX `v0.32.4`, mlx-c `v0.8.0` from `git archive` exports; needs Xcode's Metal toolchain). Another mlx-c
   version configures with a warning; an upgrade is its own change, with the full gate.
4. (2026-11-20) Two layers.
   1. **The generated C layer.** `scripts/gen_mlxc_bindings.py` (standard library, Python 3.7 or newer) reads
      the headers of the mlx-c being linked, at build time, and writes `build/gen/mlxf_c_<header>.f90`, one
      module per header: `bind(c)` interfaces `mlxc_<name>` bound to `mlx_<name>`; handle types
      `mlxc_<type>` holding one `type(c_ptr) :: ctx`; the `mlx_optional_*` value structs as `bind(c)` types;
      enumerators as named `integer(c_int)` constants. One mapping table. It skips `static` declarations and
      preprocessor-excluded blocks, exits with 2 on an unmapped type or an unknown struct, and prints its skip
      list (variadic functions, float16 and bfloat16 entry points, `mlx_io_reader_new`). Coverage is judged
      against a list it does not make: `scripts/list_mlxc_prototypes.py` writes the prototype names, frozen in
      Progress before the generator runs; the build fails unless generated plus skipped names equal that list.
   2. **The hand-written Fortran layer** in `src/core/`, the only layer users see, through one module, `mlxf`.
      One shared helper per C signature class takes the generated procedure as a procedure argument whose
      abstract interface is `bind(c)` with the generated intents. No second generator.
5. (2026-11-20, default) Names: modules `mlxf_<x>`; the user module `mlxf`; types `mlx_array`, `mlx_device`,
   `mlx_metal_kernel`, `mlx_function` (decision 30); MLX-specific procedures `mlx_<op>`; generics that extend
   a Fortran intrinsic keep its name and semantics (`matmul`, `transpose`, `reshape`, `sum`, `minval`, `exp`,
   `conjg`, `merge`, `max`, ...), added as decision 29 admits them. Operators `+ - * / **`, unary `-`,
   comparisons giving boolean arrays, `.and. .or. .not.` on boolean arrays. Getters `a%shape()` (Fortran
   order), `a%ndim()`, `a%size()`, `a%kind()` (`a%elem_kind()` if the Phase 1 probe shows `kind` misparsed).
6. (2026-11-20) **Memory order: the shape is reversed at the boundary.** A Fortran array of shape
   (n1, ..., nr) is the MLX array of shape [nr, ..., n1] over the same bytes. Fortran dimension d is MLX axis
   r - d; `reshape` has Fortran's column-major semantics; broadcasting aligns leading Fortran dimensions (to
   broadcast along dimension 3 an operand has shape (1, 1, n)); an operation along dimension 1 runs along
   MLX's last, contiguous axis; `matmul(a, b)` has Fortran semantics on dimensions 1 and 2, is batched with
   broadcasting over dimensions 3 to r, and calls `mlx_matmul(b, a)`; `transpose(a)` swaps dimensions 1 and 2
   without a copy; `mlx_permute(a, order)`: dimension i of the result is dimension `order(i)` of `a`.
7. (2026-11-20) **Index values and positions are 1-based**, in arguments (`mlx_take_along_dim`,
   `mlx_scatter_add`, slice bounds, `kth`) and in results (`minloc`, `mlx_argsort`, ...); the wrapper shifts
   them inside the graph and casts index results to int32. Slices are `mlx_slice(a, lower, upper[, stride])`
   with inclusive bounds counted from 1.
8. (revised 2026-11-20) **Lifetime: Fortran-side reference counts, a registry, and one restriction.**
   - `mlx_array` holds a private handle and a serial number. The library's registry maps each live MLX object
     (its `ctx`) to its serial and a Fortran-side reference count. Creating an array registers it with count
     1; the type-bound defined assignment (`impure elemental`, left side `intent(inout)`) copies handle and
     serial and adds one; the `impure elemental` `final` procedure and `kill` subtract one and call
     `mlx_array_free` at zero. Every public entry validates its operands against the registry (ctx and
     serial) before calling mlx-c.
   - A bitwise copy (the gfortran bypass for allocatable components, `allocate(source=)`, array intrinsics
     that move elements of handle arrays) shares a handle without a count. When the counted owners release
     it, its entry leaves the registry; the copy's next use stops with "stale mlx_array: copied without
     defined assignment (an allocatable component of a derived type, allocate(source=), or an array
     intrinsic)"; its finalization frees nothing and counts a stale release. The serial makes a reused `ctx`
     address detectable. A bitwise copy therefore never frees twice and never reaches MLX after its object is
     gone; before that it aliases correctly.
   - **The restriction (binding policy):** a derived type with an allocatable component of a handle type
     (scalar or array) defines its own assignment that assigns those components element by element (the
     pattern is in the policy), or is never copied by intrinsic assignment. `allocate(source=)` and `mold=`
     on handle types, and array intrinsics on arrays of handles, are unsupported. Widened by decision 39
     (ruling R4) with the three finalization defects step 1's probes found: no function reference inside an
     array constructor of handles, no whole-array assignment of a function result to an array of handles
     (assign a variable, or element by element), no self-assignment of a derived type holding handles.
   - A declared, never-assigned `mlx_array` is empty: `kill` and `final` skip it, every operation refuses it.
     Every function nulls its result on entry. The registry's live count is the leak gate's counter.
   - **Gate (exact).** After a warm-up iteration, with `mlx_synchronize` and `mlx_clear_cache` before both
     reads, `mlx_get_active_memory` and the registry's live count after the loop equal their values before,
     on each device; no stale release is counted; no case crashes in the Debug build. The loop (10,000
     iterations) holds `c = exp(a*2.0 + b)` with `mlx_eval(c)`, self-assignment, `b = (a)`, an array
     constructor of variables passed on (decision 39: the supported form of a constructor), function results
     as actual arguments, `intent(out)` dummies, rank-1 and rank-3 arrays of handles (allocated, then assigned
     and reassigned element by element and from variables), a plain scalar and array
     handle component copied by intrinsic assignment of its type, an allocatable handle component copied
     through the policy's assignment pattern, and handles leaving scope in a called procedure.
   - **Gate (diagnosis).** The bypass is exercised on purpose: an allocatable handle component copied by
     intrinsic assignment, the original released; `mlx_is_live(copy)` is false, the copy's finalization
     counts one stale release, and nothing crashes. `allocate(source=)` likewise.
   - The registry's cost per operand is measured in Phase 1 and reported.
9. (revised 2026-11-20) **Data in and out: copies by default, an explicit protocol for shared buffers.**
   - `mlx_from(x)` copies a Fortran array of rank 0 to 15 (assumed rank, `contiguous`) of kind `real32`,
     `real64`, `complex(real32)`, `int32`, `int64` or `logical(c_bool)` into a new MLX array (one `memcpy`);
     a strided actual is copied in by the compiler; a zero-size array becomes an empty MLX array without
     `c_loc`. `mlx_to(y, a)` evaluates `a` and copies into an existing array of the same size and kind;
     `mlx_to_alloc(y, a)` (allocatable `y`, rank 1 to 7) allocates to `a`'s shape and copies. These are the
     dependable default.
   - **Writable initialisation:** `mlx_alloc(shape, mold, view)` gives an MLX array whose storage the caller
     fills through the Fortran pointer `view`, page-aligned host memory handed to
     `mlx_array_new_data_managed` (zero-copy when Metal accepts it, else one copy, after which `view` points
     at MLX's copy). Writes through `view` are allowed only until the array is first passed to any library
     procedure; from then on it is read-only, because a lazy graph may read it at any later evaluation.
   - **Read-only borrowing:** `mlx_view(a, p)` evaluates `a` and points `p` at its storage when it is
     row-contiguous. `p` is valid until the next statement that assigns to, kills or ends the scope of the
     variable `a` (including `a = f(a)`, after which MLX may reuse the old buffer), and is never written
     through. A borrowed array held by the caller is not donated to other operations' outputs (MLX donates
     only buffers no live array references); a test pins that a view survives unrelated evaluations.
   - The rules are the binding policy's; Phase 1 records which `mlx_alloc` sizes are zero-copy.
10. (2026-11-20) **dtypes.** real32 to float32; real64 to float64 (CPU device only); complex(real32) to
    complex64; int32, int64; logical(c_bool) to bool. complex(real64) has no specific. On the CPU, MLX computes
    some float64 operations in float32 (at `v0.32.4`: `exp`, `sin`, `cos`, every FFT); the binding policy
    lists them and the tests hold them to float32 tolerances. No silent conversion except decision 11;
    `mlx_astype(a, mold)` converts.
11. (2026-11-20) **Scalar operands are weak.** A Fortran scalar takes the array's kind when the array is real or
    complex; a real scalar with a complex64 array becomes complex64; a complex scalar with a real array makes
    the result complex64; an integer array with a real scalar gives float32. `2.0_dp` literals never make
    float64 graphs.
12. (revised 2026-11-20) **Errors: fail fast in expressions, recover in checked procedures.**
    - The library installs an mlx-c error handler that records MLX's message and returns. Operators and
      functions stop with `mlxf: <procedure>: <MLX message>` on any error: these are the errors MLX reports
      while building a graph (shape, kind, device), which are program errors.
    - Evaluation and data movement are checked procedures with an optional `integer, intent(out) :: status`
      and `mlx_last_error()` for the message: `mlx_eval`, `mlx_async_eval`, `mlx_synchronize`, `mlx_to`,
      `mlx_to_alloc`, `mlx_view`, `mlx_alloc`, `mlx_set_default_device`, `mlx_set_memory_limit`. Allocation
      and kernel failures surface there. Without `status` they stop.
    - After a failed evaluation the library and MLX stay usable. Gate: an evaluation that needs a buffer
      beyond the device's `maxBufferLength` returns a status with a message naming the allocation; the same
      graph at half the batch evaluates; the leak gate's counters hold. This is the reduce-the-batch pattern.
    - Over-subscribing unified memory does not fail, it pages: callers size their tiles from
      `mlx_peak_memory()` and a budget (decision 20), not by catching failures.
13. (2026-11-20) **Devices.** A GPU is present when `mlx_device_count(MLX_GPU) > 0`. The default device is the
    GPU; `mlx_set_default_device(MLX_CPU | MLX_GPU)`. Without a GPU a Metal build cannot allocate on either
    device: the first operation stops with a message saying so. Explicit streams are not in this plan.
14. (2026-11-20) **One submitting thread.** Graphs are built and evaluated from one thread. With `USE_OPENMP`
    (default ON) every public entry refuses to run inside an OpenMP parallel region. The caller's OpenMP code
    may work on data the library has copied out, outside any library call.
15. (revised 2026-11-20) **Precision modes.**
    - *Full precision*, `MLX_ENABLE_TF32=0`: every correctness gate and the verdict's formulation. CTest sets
      it for every entry; the benchmarks record it in every row.
    - *Accelerated*, `MLX_ENABLE_TF32=1` (MLX's default) on a GPU with NAX (the M5 Ultra): real float32
      matrix products at reduced precision. A separately recorded benchmark mode. A formulation in this mode
      counts as equivalent only if it passes the same frozen gates; adopting reduced precision in SIMPLE is a
      scientific decision that needs SIMPLE's own real-data check and is not taken here.
    - The library does not change MLX's precision (mlx-c has no setter); `mlxf_runtime_description()` reports
      the variable and the device's architecture name (`mlx_device_info`).
16. (revised 2026-11-20) **Evaluation and overlap.** `mlx_eval`, `mlx_async_eval`, `mlx_synchronize`; `mlx_to`,
    `mlx_to_alloc`, `mlx_view` evaluate. The overlap pattern, from one submitting thread: submit block n+1
    with `mlx_async_eval`, copy out block n, let the CPU (OpenMP team allowed) consume block n, repeat. CPU
    and GPU share memory bandwidth, so the benefit is measured, not assumed (Phase 2).
17. (2026-11-20) **Memory controls.** `mlx_active_memory()`, `mlx_peak_memory()`, `mlx_reset_peak_memory()`,
    `mlx_cache_memory()`, `mlx_clear_cache()`, `mlx_set_memory_limit(bytes)`, `mlx_set_cache_limit(bytes)`.
18. (2026-11-20) **Custom Metal kernels.** `mlx_metal_kernel` wraps `mlx_fast_metal_kernel_*`: name, input and
    output names, source and header as Fortran strings, grid, threadgroup, template arguments, output shapes
    in Fortran order. The Metal source itself indexes MLX's row-major, 0-based layout (the one place the user
    meets it). Only for a measured bottleneck that ordinary or compiled MLX operations cannot handle (Phase 4).
19. (2026-11-20) **Tests and benchmarks.**
    - Areas: `core` (version, initialisation, errors, devices, memory, registry), `array` (lifetime, data in
      and out, buffer protocol, shapes, dtypes), `ops`, `linalg`, `fft`, `compile`, `kernels` (the
      SIMPLE-shaped pipelines on small fixtures against double-precision oracles; fixture sizes only).
    - Every operation test runs on every device present; `mlxf_test_exec device=cpu|gpu|all` restricts it.
      Without a GPU device, device tests report a skip; CMake option `MLXF_REQUIRE_GPU` (default ON on macOS
      arm64, OFF in the CI), a compile definition of the test executable (the library reads no environment
      variable of its own), makes that skip a failure.
    - Benchmarks are measure-only entries `mlxf_test_exec test=bench_<x> [suite=<mode>]` appending rows to
      `./bench_<x>.tsv`: `bench_polar_table` (modes `time`, `profile`, `accuracy`, `overlap`), `bench_fft2`,
      `bench_gather_scatter`. Never CTest entries.
20. (revised 2026-11-20; architecture and tiling updated by decision 42) **SIMPLE's first pipeline: the polar
    table fill's scoring stage.** For particles i of one half h with
    temperatures T_i and caller variates u(i, r), and references r, over shells k = 1..nk and angular bins
    p = 1..P, P = pftsz + 1 (pftsz even), nrots = 2 pftsz:
    - c(p, i, r) = sum over k of w_k(h) [ctf2(p, k, i) ref2(p, k, r) - 2 xctf(p, k, i) conj(ref(p, k, r))];
    - d(rot, i, r) = 1 + irfft(c(., i, r))(rot) / (2 wsq_i), the inverse real FFT with the 1/nrots scaling
      (`MLX_FFT_NORM_BACKWARD`), which is SIMPLE's 1 + c2r / (2 nrots wsq_i); no clamp; d above
      -log(TINY) becomes the invalid marker `huge`;
    - the draw: d_min over the valid rotations; weights exp(-T_i (d - d_min)), zero where
      T_i (d - d_min) >= 80 or d is invalid; W the sum of the weights; irot the first rotation whose cumulative
      weight reaches max(u W, tiny), or the minimising rotation when rounding leaves none (SIMPLE's fallback);
    - the table entry (d(irot), irot), irot in 1..nrots; with no valid rotation, (huge, 1).

    This restates the shared distance/draw semantics retained by `score_block_posterior` at `7ec7e2972`
    (first checked against `gen_posterior_val` at `5709265cb`; a seed bank substitutes shifted particle
    spectra). The variates come from the caller (SIMPLE's keyed
    generator after integration; a fixed-seed generator here) as float32. The draw runs on the device: the
    table needs one entry of 8 bytes per pair (160 MB for 2,000 particles against 10,000 references), while
    full rows would be 1,456 bytes per pair and the 20 lowest are no longer what SIMPLE draws from. A
    scoring-only mode returns the full rows d (fixture and accuracy block only) for the oracle comparisons.

    Tiling and scheduling follow decision 42. Reference tiles stay resident across particle blocks; complete
    scoring tiles return compact entries, with at most two in flight for the overlap experiment. The GPU
    sweep starts at B in {64, 250, 500, 1,000, 2,000} and R_t in {64, 250, 500, 1,000, 2,500}
    (*guessed* search grid, not required production sizes); prune dimensions above the route's available
    particles per half or active references, and configurations beyond the memory budget before allocation.
    Record pruned cases and partial-tile occupancy. The budget remains a quarter of machine memory
    (*guessed*), covering the pipeline's live allocations including overlap, not just its input matrices.
    Formulations, starting with A as the direct production-algebra reference:
    - **A**: one complex64 batched `matmul` over angular bins, using a bin-major reference copy
      (2 nk, R_t, P), a permute to bins first, batched `mlx_irfft`, the distances and the draw;
    - **B**: the complex product as real float32 GEMM batched over bins (particle side packed (Re, Im) along the
      depth, B x 4 nk; reference side packed [[Re, Im], [-Im, Re]], 4 nk x 2 R_t, built once per tile), giving
      (Re c, Im c), recombined to complex64 for `mlx_irfft`; packing and recombination are timed;
    - **C**: as B, with the inverse transform written as a second real GEMM of (Re c, Im c) against a fixed
      cosine and sine matrix of 2P by nrots, so that every product is real float32 (NAX-eligible);
    - each of A, B, C with the elementwise tail (distances and draw), or the whole block function, under
      `mlx_compile` (decision 30), and without.
21. (2026-11-20) **SIMPLE's second pipeline: Cartesian FFTs of particle stacks.** `mlx_rfft2` and `mlx_irfft2`
    over dimensions 1 and 2, batched over dimension 3, at boxes 64, 128, 160, 180, 200, 256, 320, 360, 400,
    512, in batches of 512; timed against FFTW in single precision on all cores with SIMPLE's planner flag.
22. (2026-11-20) **SIMPLE's third and fourth pipelines: interpolation and reconstruction**, as a separate
    investigation (decision 33): polarisation (a gather of each polar sample's Kaiser-Bessel window from a
    particle's transform) and insertion (a scatter-add of each Fourier component into a volume and its weights
    with a three-dimensional window), windows of 3 and 4 points per dimension, boxes 160 to 360.
23. (2026-11-20, default) `bench_fft2` links FFTW 3 in single precision when CMake finds it; FFTW links only into
    `mlxf_test_exec` and is never a dependency of the library or of the gate.
24. (2026-11-20, default) The C library's `strlen`, `memcpy`, `posix_memalign` and `free` are declared once, in
    `src/core/runtime/mlxf_libc.f90`.
25. (2026-11-20, default) Kernel code that is SIMPLE's (decisions 20 to 22) is test code in `src/test/`, written
    against `mlxf` as a user's code is; it compiles into `mlxf_test_exec` only, its modules go to
    `build/modules_test`, it is never installed, and it is the starting point SIMPLE's integration plan copies.
26. (2026-11-20, Hans) The polar verdict's go threshold is 2.0 times SIMPLE's `matrix_t` (section 6).
    Decision 42 replaces the denominator with the production `block_prod` baseline; the 2.0 threshold stays.
27. (2026-11-20, Hans) The target machine is an M5 Ultra, delivered 2026-11-25. The polar verdict is judged
    there, against SIMPLE's baseline re-measured there. Until then the run uses the M2 Ultra (16 performance
    and 8 efficiency cores, 76-core GPU, 192 GB, macOS 26.7.3, no Xcode, no NAX) for Phases 0 and 1 and
    Phase 2's correctness work; its numbers are reported beside the M5 Ultra's.
28. (2026-11-20, Hans) The probabilistic table is about 60 % of the wall time in Hans's SIMPLE benchmarks: the
    whole fill (Hans, same day), its seed, its scoring and the shift refinement of the best references
    (`ts_refine`), of which decision 20 covers the scoring and the draw. The end-to-end projection therefore
    needs f, the scoring's share of the fill (`ts_score` over `ts_seed + ts_score + ts_refine` of the
    `prob_fill_profile` in a BENCH output): with a scoring speedup g the run speeds up by
    1 / (1 - 0.6 f + 0.6 f / g). If Hans names a BENCH output (rulings file), Phase 0 records f; otherwise the
    report gives the projection as a function of f. A small f makes the shift refinement the next pipeline
    (not in this plan).
    **Recorded (ruling R2, 2026-11-20; Phase 0 step 7):** Hans's BENCH directory
    (`~/for_claude/bench/BENCH/`, one solve3D run: 37,502 particles, box 240, one state, 8 stages, 134 refine3D
    iterations in 10 parts of 8 threads) gives **f = 0.23** (*measured*: score 23,459, refinement 77,877, seed 0
    thread-s, summed over all iterations and parts); 1.00 in the prob_neigh stages of 500 and 1,000 directions
    (no refinement), 0.16 to 0.29 in the dense `prob` stages, 0.28 to 0.40 in prob_neigh at 2,500 and 5,000. The
    fill on the critical path is 37 % of solve3D in that run (53 to 77 % in the dense stages), so with s = 0.37
    the ceiling of an infinitely fast score loop is 1.09 (1.16 at s = 0.6); the master's assembly is another
    36 % of solve3D. The per-stage table is in Phase 0's Progress entry; what follows for Phases 3 and 4 is
    decision 38. These measurements predate the production BLAS scorer. Decision 42 requires a current
    profile before using numerical timing shares to project a new end-to-end gain.
29. (2026-11-20, Hans's review) **The public API grows by demonstrated need.** A public procedure enters when a
    pipeline step of this plan uses it, or when it is the sibling a test of such a step needs (for example
    `cumsum` for the draw, `sum` to test it). Each phase's list below is that need; nothing else is wrapped by
    hand, however easy the generated layer makes it.
30. (2026-11-20, Hans's review) **Graph compilation, without transforms.** `mlx_function` wraps a Fortran
    function of arrays as an mlx-c closure (a `bind(c)` trampoline and a payload holding a procedure
    pointer; the trampoline never stops, it returns a status) and `mlx_compile(f, shapeless)` compiles it.
    Shapeless compilation, or padded tiles, keep the last partial tile from recompiling; neither establishes
    numerical invariance when a tile's shape or a pair's position changes (decision 42). Compilation fuses
    the elementwise tail; matrix products and FFTs stay MLX's kernels. No `grad`, `vjp` or `vmap`.
31. (2026-11-20, Hans's review) **The verdict compares equivalent completed work**: the table entries
    (d(irot), irot) of every pair with SIMPLE's draw semantics, on the GPU and in SIMPLE's `matrix_t`, which at
    the base also draws over the full row. Scoring alone (sums, inverse transform, distances) is reported
    beside it for both, and so are preparation, the copy-out, and the overlap with CPU consumption.
    Decision 42 replaces `matrix_t` with `block_prod` and specifies the production timing boundary; missing
    CPU stage timings are reported as unmeasured.
32. (2026-11-20, Hans's review) **Milestone 1 is Phases 1 and 2**: a proven handle model and one tiled polar
    pipeline with independent references and measured peak memory. The run holds after Phase 2 with an
    interim summary in Progress; Hans rules whether SIMPLE's integration plan comes before Phases 3 and 4.
33. (2026-11-20, Hans's review) **Scatter is its own investigation.** Its contention and accumulation order
    differ from dense products: insertion is measured in three forms (MLX `scatter_add`, whose atomic order
    varies; sort by voxel then a segmented sum from `argsort`, `cumsum` and gathers, which is deterministic; a
    Metal kernel), with run-to-run differences and the dependence on how many components hit one voxel
    (window size, particles per batch) reported.
34. (2026-11-20, default) The gfortran conformance bug of section 2 is reported upstream with the probe as a
    reproducer; the library does not depend on a fix.
35. (2026-11-20, Hans) **Phases 0 and 1 run unattended** (arun, on the M2 Ultra), on the condition that the
    necessary architectural guidelines are imported from SIMPLE and XEMA. They are, before launch:
    `doc/architecture_principles.md` is the register (adopt, adapt, reject, with reasons), and the skill
    `mlxf-modern-fortran`, its `references/testing.md`, `CLAUDE.md`, `AGENTS.md` and the two policies carry
    the rules. The run follows them like any other rule of the repository; a rule that blocks the plan is a
    stop, not a deviation.
36. (2026-11-20, imported from XEMA) **The static gate and its checks.** `scripts/check_tree.sh` runs first in
    the fast gate. `scripts/check_rules.py` already carries the structural rules this plan needs (`surface`,
    `cbind`, `libc`, `reexport`, `cbstop`, `prints`, `state`; ledgers that may only shrink), so no separate
    layer checker is written: Phase 1 removes `mlxf_version`'s `cbind` and `libc` ledger entries when the
    generated layer and `mlxf_libc` replace its probe, and adds the registry's, the error module's and the
    initialisation flag's module variables to the `state` ledger with their reason. A new rule reading can
    check goes into `check_rules.py` with a planted violation shown to fail. Every touched Fortran file goes
    through `restyle_fortran.py` and `format_use_blocks.py`; the tree builds with zero warnings in Debug and
    Release.
37. (2026-11-20, imported from XEMA) **Processes are budgeted; stops are guard groups.** `MLXF_CTEST_BUDGET` is
    1 at the base. This plan names the entries it adds: Phase 1 the area `array` and the guard group
    `object_contracts` (budget 3); Phase 2 the areas `ops`, `linalg`, `fft`, `compile` and `kernels`
    (budget 8); Phases 3 and 4 add checks to existing areas only. Every stop the library makes uses
    `MLXF_HARD_ERROR_STATUS` (86); the stops that are the contract (an operation on an empty array, a stale
    handle used, a library call inside an OpenMP region, a float64 operation built on the GPU) are members of
    `object_contracts`, run by `mlxf_test_exec expect_aborts object_contracts`, each in a child process,
    accepted only with that status. The 30 % rule applies to decision 20: the kernel SIMPLE copies keeps one
    formulation per precision mode, and a second only where it is more than 30 % faster.
38. (2026-11-20, Hans, ruling R3) **Phases 3 and 4 are reordered toward the measured costs.** After milestone 1
    the next pipelines are (a) the probabilistic table's shift refinement of the best references (77 % of the
    fill's thread-seconds in the BENCH run of decision 28: the polar shift maps and the gradient shift search)
    and (b) the master's assembly (37 % of refine3D in that run: the PCG solves of the reconstruction and the
    nonuniform filter of the volume assembly), in an order Hans rules at the hold of decision 32. Particle-stack
    FFTs (decision 21) and polarisation and gridding (decisions 22, 33) move behind them. The phase texts and
    file-table rows of Phases 3 and 4 stay as written until a plan revision at that hold rewrites them from
    SIMPLE's code; Phases 0 and 1 are unchanged (Phase 0 step 6 still runs).
39. (2026-11-21, Hans, ruling R4) **The answer to the Phase 1 stop: arity, list arguments, decision 8 widened.**
    Step 1's probes stand as recorded (Progress). Phase 1 resumes at step 2.
    1. *No procedure has more than five dummy arguments* (Hans's house rule), in `src/` and `test/` alike;
       one that needs more takes a spec type (a derived type holding the inputs, constructed and validated
       once, passed whole; SIMPLE's `opt_spec` is the precedent). Exempt: the generated `bind(c)` interfaces
       and `bind(c)` procedures whose signature C fixes. It binds decision 18 (`mlx_metal_kernel` configured
       through a spec type), decision 20 (the block function of test code takes a spec of the block's inputs)
       and decision 4's helpers. Checked by rule `arity` of `scripts/check_rules.py`.
    2. *List arguments are arrays of handles*, never optional-argument lists: `mlx_concatenate`, `mlx_stack`,
       `mlx_eval` and any later list-taking procedure take `type(mlx_array), intent(in) :: arrays(:)`, filled
       element by element or written as a constructor of variables.
    3. *Decision 8 is widened by the three defects found* (function results referenced inside an array
       constructor of a handle type are never finalized; a scalar function result assigned to a whole array
       of handles through the elemental defined assignment is never finalized; intrinsic self-assignment of a
       derived type with plain handle components finalizes the components before they are copied): no
       function reference inside an array constructor of handles, no whole-array assignment of a function
       result to an array of handles, no self-assignment of a derived type holding handles. The leak gate stays
       exact on every supported form; its cases that hit a defect are replaced by their supported forms
       (constructors of variables, element-wise assignment).
    4. Rule `ctorcall` of `scripts/check_rules.py`: an array constructor in `src/` or `test/` that holds a
       reference to a function of the public API (the names of `mlxf.f90`'s public block) fails.
    5. `mlx_live_count()` is public: the registry's count of live handles, so that users and SIMPLE's tests
       can assert that a loop leaks nothing.
    6. The three reproducers join `doc/compiler_issues/` beside the first; decision 34's upstream report
       covers all four. No gate test pins a compiler defect: a compiler that fixes one must not fail the build.
40. (2026-11-21, Hans, review of Phase 1) **Exported = defs, local = stay.** As in SIMPLE and XEMA, a named
    constant, a vocabulary or a behaviourless record that another module imports lives in `src/defs/`; one used
    only inside its module stays there. `src/defs/mlxf_defs.f90` holds `MLXF_HARD_ERROR_STATUS` (from
    `mlxf_error`), `MLX_DTYPES` (from `mlxf_array`) and the devices, now the vocabulary `MLX_DEVICES%cpu`,
    `%gpu` (replacing the integers `MLX_CPU`, `MLX_GPU` of `mlxf_device`, and the names of decision 13). The
    defs module is public by default and lists its imports in a `private ::` statement; rule `defs` of
    `scripts/check_rules.py` checks both. Phase 2's shared constants (the FFT normalisations as
    `MLX_FFT_NORMS`, `MAX_RANK` once `mlxf_ops` needs it) go there; tolerances shared by the kernel tests and
    the benchmarks go to `src/test/mlxf_test_defs.f90`; R4's spec types go to defs where they hold no
    behaviour. The binding policy and the register carry the rule.
41. (2026-11-21, Hans, review of Phase 1) **Capability folders, `mlxf_array` in submodules, the entry on every
    path, one installed module.** (a) `src/core/runtime/` (libc, errors, registry, devices, memory, version) and
    `src/core/array/` in the one library target. `mlxf_array` keeps the type, its generics and every
    procedure's interface; the submodules `mlxf_array_lifetime`, `_transfer`, `_borrow`, `_evaluation` and
    `_elementwise` implement them (XEMA's search engine): one type, one ownership implementation, private
    access inside the family. Stateless operations stay module procedures; the device codes stay a constant
    vocabulary (decision 40). Later capabilities get their own folders. (b) Only `mlxf.mod` is installed. (c)
    Every public procedure opens with the entry before it looks at an operand (rule `entry`), so the
    one-thread guard runs on an empty evaluation list and in `mlx_live_count` and `mlx_last_error`; the defined
    assignment, `kill` and finalization guard only with a live handle (between empty handles they run
    anywhere); `mlxf_handle` validates and does not enter. `object_contracts` grows to eight members. (d)
    `mlx_to_alloc` allocates with `stat=` and reports a failure through the status. (e) Headless, the memory
    limits skip and the device tests assert only that selecting an absent GPU returns; the allocatable-component
    test accepts a counted copy as well as gfortran's bitwise one, and the stale diagnosis is tested through
    `allocate(source=)`. Found on the way: gfortran 16.2 finalizes no OpenMP private copy (a `firstprivate`
    scalar or allocatable array of handles), so no gate member can reach the finalizer's guard; the copies are
    dropped without a release.
42. (2026-11-21, Hans) **Production block scoring is the architectural template and benchmark baseline;
    GPU tiling and scheduling are measured separately.** This revises decisions 20, 26, 28 and 31 for the
    remaining work; completed Phase 0 measurements are not relabelled as the new baseline. Scope of this
    interactive revision: this plan only, with the decision and its record here; no implementation,
    benchmark execution, policy or history-file edits.
    1. **Pinned baseline.** Use SIMPLE `7ec7e29720b3e57c2a56a6a7ab754e6f6c57fe35`, whose
       `score_block_posterior` was introduced in `5481d42c5`. Before Phase 2 implementation, build a scratch
       export, run `polar_matching_bench suite=block_prod` twice per case, its `check` and `fills` suites,
       and the `neigh` suite's representative/candidate measurements (the baseline refresh below).
       Re-measure on the M5 Ultra for the verdict. `matrix_t` and `per_pair` are historical/contextual
       comparisons, never substitutes for a failed or missing production baseline.
    2. **Owner and operation.** In SIMPLE's later integration, `builder%pftc` remains the polar-scoring
       owner. The probability tables choose particles and ordered reference IDs, seeds and temperatures;
       the calculator returns one distance/rotation per pair. A focused submodule implements GPU scoring,
       backed by an owned workspace with explicit preparation, idempotent teardown and the binding's handle
       lifetime rules. Preparation records reference generation, half, shape and active reference mapping;
       scoring validates them. Prepare outside the hot loop, rebuild after invalidation, and make backend
       preparation one coherent step so a caller cannot forget a separate memo option. Audit the matcher,
       neighbourhood table, pose student and test harness when integration is planned. Do not copy the
       CPU's 16-particle API capacity into the GPU contract. Here, model this lifecycle in the test-only
       polar pipeline owner and its implementation submodules; the library retains only generic operations,
       with no polar cache, builder dependency or new abstract backend hierarchy.
    3. **Three levels of tiling.** The matcher owns the outer particle/I/O batch and memory budget; the
       polar workspace owns B-by-R_t scoring tiles; MLX owns device kernel tiles. Group particles by half
       and references by a shared, stable candidate list. Pack and retain that active set where it fits;
       otherwise retain a bounded reference tile across particle blocks and count each reload in the timing.
       Compare resident full-reference and representative-only preparation, preserving global reference IDs.
       The GPU graph batches angular bins and transforms, keeping products, full rotation rows and the
       posterior draw on device; only compact entries cross back. Count host staging, packed references,
       particle terms, products, FFT/posterior temporaries, retained graph inputs and both overlap slots.
       Report MLX peak, host allocation estimate and process peak separately without double-counting aliased
       unified-memory buffers. No paging-based search for a tile size. CPU 16-by-32 padding is evidence
       about that BLAS, not a GPU optimum or reproducibility guarantee. Sparse pooled members and `geom`
       cones remain outside the first GPU implementation; their CPU occupancy/cost is contextual evidence.
    4. **Submission schedule.** Preserve seed -> score -> refine/assign dependencies while separating CPU
       preparation/consumption from GPU submission. One thread outside every OpenMP region creates,
       evaluates, copies and releases MLX handles. CPU teams see only ordinary Fortran input/output arrays;
       their regions never copy or finalize live handles. Start with a synchronous schedule; then measure
       two slots: prepare and queue tile n+1, copy out n, consume n on the CPU while n+1 runs. Retain each
       slot's inputs until its work completes; accumulate reference tiles as needed before refinement or
       assignment consumes a particle's complete candidates. GPU B is independent of CPU team size. A
       direct replacement inside the current OpenMP `process_block` is not the integration design.
    5. **Numerics and execution order.** Preserve half separation, optional seed banks, DC/Nyquist handling,
       normalisation, invalid markers, first-reaching posterior draws and fallbacks. Variates are keyed by
       scope and global particle/reference IDs, never tile positions. The benchmark supplies fixed variates;
       record separately the existing float32 caller-u convention versus SIMPLE's real64 keyed variate.
       Check repeated runs and scheduling/batch changes at a fixed canonical tile plan for exact entries.
       Separately measure changes in tile shape, particle row, reference column, list order and compiled
       execution against the same frozen oracle gates, reporting loss, best-rotation and sampled-rotation
       differences by temperature. Padding and stable slots may be required; choose and record the canonical
       mapping before the judged scheduling tests. Do not infer posterior stability from GEMM tolerances or
       promise bit identity between CPU/GPU backends. SIMPLE's real-data acceptance remains its later plan.
    6. **Equivalent work and practical gain.** Keep the 2.0-times go threshold, now against `block_prod`
       on the same machine and workload, from prepared memos through the returned entries. Include GPU
       per-block input construction/upload, evaluation and copy-out; report reference preparation and cold
       compilation separately, plus their amortised cost. Report dense and shared-representative routes
       separately, with useful pairs, padded slots and memory. Refresh the production profile's scoring
       fraction f and fill wall-time fraction s before projecting `1 / (1 - s*f + s*f/g)`. Thread-seconds
       alone are not a wall-time fraction; state the approximation where used. If no current matching
       profile is available, report the projection only as a function of s and f, labelled unmeasured.
       Retain the milestone-1 hold; this revision does not authorise a SIMPLE port or new defaults.

Defaults taken without a question: decisions 2, 3, 5, 23, 24, 25, 34; the area, mode and benchmark names of
decision 19; the guard group's name; the version 0.1.0.

### The design on one page

```text
build/gen/mlxf_c_<header>   generated bind(c) layer (mlxc_* names), private   decision 4.1
mlxf_libc                   strlen, memcpy, posix_memalign, free               decision 24
mlxf_error                  handler, status, last error, one-thread guard      decisions 12, 14
mlxf_registry               live handles: ctx, serial, Fortran-side counts     decision 8
mlxf_device, mlxf_memory    devices, initialisation; memory controls           decisions 13, 17
mlxf_array                  mlx_array: lifetime, data in and out, evaluation   decisions 6-11, 16
mlxf_ops, mlxf_linalg,      operations, matmul, FFTs                           decisions 5-7, 29
mlxf_fft
mlxf_compile                mlx_function, mlx_compile                          decision 30
mlxf_kernel                 Metal kernels (Phase 4)                            decision 18
mlxf                        the user module: re-exports the public names
```

Decision 20, formulation A, for one particle block and one reference tile: the algebra/API sketch checked
against decisions 5 to 11 and 29. Under decision 42, reference preparation belongs to the persistent polar
workspace, scoring to its submodule, and the outer tile/submission loop to the caller. This sketch is not a
new reference allocation per score call. The CPU scorer conjugates its product and then conjugates back;
this equivalent formulation constructs the unconjugated sums directly. `ft_ref`, `ft_ref2` (P, nk, R_t) and `ft_ctf2`,
`ft_ptcl_ctf` (P, nk, B) are SIMPLE's memo arrays of one half, `wk(nk)` the shell weights, `wsq(B)` and
`temp(B)` the particles' self-terms and temperatures, `u(B, R_t)` the variates:

```fortran
use mlxf
type(mlx_array)           :: rbin, pbin, w, c, d, wt, cs, tgt, irot, dsel, parts(2)
real(real32), allocatable :: dist(:,:)
integer,      allocatable :: rot(:,:)
! the reference tile, built once and kept on the device across particle blocks: bin-major (2nk, R_t, P)
parts(1) = mlx_from(ft_ref2)                                          ! list arguments: arrays of handles,
parts(2) = conjg(mlx_from(ft_ref))                                    ! filled element by element (decision 39)
rbin = mlx_permute(mlx_concatenate(parts, dim=2), [2, 3, 1])
! a particle block with its half's shell weights, bin-major (2nk, B, P)
w    = reshape(mlx_from(wk), [1, nk, 1])
parts(1) = w*mlx_from(ft_ctf2)
parts(2) = -2.0*w*mlx_from(ft_ptcl_ctf)
pbin = mlx_permute(mlx_concatenate(parts, dim=2), [2, 3, 1])
c    = matmul(transpose(pbin), rbin)                                  ! one batched call across P angular bins
d    = 1.0 + mlx_irfft(mlx_permute(c, [3, 1, 2]), n=nrots, dim=1) / reshape(mlx_from(2.0*wsq), [1, B, 1])
d    = merge(huge(1.0), d, d > DINVALID)                              ! (nrots, B, R_t), SIMPLE's invalid marker
wt   = reshape(mlx_from(temp), [1, B, 1]) * (d - reshape(minval(d, dim=1), [1, B, R_t]))
wt   = merge(exp(-wt), 0.0, wt < 80.0 .and. d < DINVALID)             ! draw weights
cs   = mlx_cumsum(wt, dim=1)
tgt  = max(reshape(mlx_from(u), [1, B, R_t]) * mlx_slice(cs, [nrots, 1, 1], [nrots, B, R_t]), tiny(1.0))
irot = 1 + sum(mlx_astype(cs < tgt, mold=1), dim=1)                   ! first rotation reaching the target
dsel = mlx_take_along_dim(d, reshape(irot, [1, B, R_t]), dim=1)       ! (SIMPLE's fallbacks omitted here)
call mlx_to_alloc(rot,  irot)                                         ! (B, R_t) table entries
call mlx_to_alloc(dist, reshape(dsel, [B, R_t]))
```

Nothing in it is C-ordered or 0-based; the scalars stay float32 (decision 11); the reference tile `rbin` is the
caller's (layer table). A seeded particle supplies its shifted bank in place of `ft_ptcl_ctf`. The complete
implementation handles partial tiles, canonical ID mapping, invalid rows and fallbacks, and uses the
workspace/spec interface of decisions 39 and 42. Phase 2's operation list is what this and formulations B and
C use. No individual angular bin is submitted or copied back in a Fortran loop.

## 4. Not in this plan

- **Any change to SIMPLE.** Its integration (a `USE_MLX` option, GPU workspace owned by `builder%pftc`, a
  revised table-fill schedule) is a SIMPLE plan written after milestone 1 (decisions 32, 42). The ownership
  and scheduling requirements here make that later work concrete; this plan changes no SIMPLE source.
- Transforms (`grad`, `vjp`, `jvp`, `value_and_grad`, `vmap`), neural-network layers and optimisers: a later
  plan, for SIMPLE's `learn/` students. Graph compilation is in (decision 30).
- CUDA and Linux backends; `mlx_distributed_*`; IO; graph export and import; float16 and bfloat16; quantised
  operations; the machine-learning `mlx_fast_*` kernels other than `metal_kernel`; explicit streams.
- flang and other compilers; Windows; hosting, releases and package managers.
- SIMPLE's shifted-reference kernel and its polar shift maps (`simple_polar_shiftmap`, work in flight there).
- GPU scoring of sparse pooled members and `geom` cones. The shared representatives are in scope; their
  candidate selection remains SIMPLE's. The CPU neighbourhood benchmark supplies occupancy/cost context.
- Out of bounds: `~/src/mlx`, `~/src/mlx-c` and `~/src/SIMPLE` (read only; exports in scratch).
- No other run edits this repository while a phase runs. Completed phases retain their recorded base;
  Phase 2 records a new snapshot after the owner's Phase 1 fixes and uses the SIMPLE pin of decision 42.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement only | toolchain and dependencies recorded, scaffold gate in Debug and Release, GPU visible to the run, SIMPLE baselines twice |
| 1 | new code: the handle model and the core | `unit_core`, `unit_array` on both devices; the leak and diagnosis gates; recovery gate; generator coverage; fast gate in Debug and Release |
| 2 | baseline refresh, then new code: the polar pipeline (milestone 1) | production `block_prod` baseline and fill checks; `unit_ops`, `unit_linalg`, `unit_fft`, `unit_compile`, `unit_kernels suite=polar_table` on both devices with frozen tolerances; lifecycle/scheduling checks; the verdict on the M5 Ultra |
| hold | ruling 32 | Hans's ruling recorded |
| 3 | new code: n-dimensional FFTs | `unit_fft` additions on both devices; `bench_fft2` recorded |
| 4 | new code: gather, scatter, Metal kernels | `unit_ops`, `unit_kernels` additions on both devices; `bench_gather_scatter` recorded |
| 5 | packaging | a consumer project builds and runs against the install tree |
| 6 | report | the report exists and cites every Progress entry |

## 6. Acceptance

Every number carries its origin: *exact*, *measured*, *derived*, *literature* or *guessed*. All correctness
runs are in full precision (decision 15).

- **Fast gate.** Every fast entry passes; a total over 60 s only warns (SIMPLE's budget, measured there).
- **Exact gates.** The leak and diagnosis gates (decision 8); the recovery gate (decision 12); byte identity of
  data movement; generator coverage against the frozen list.
- **Single operations.** Absolute errors scaled by the operation's natural magnitude, against plain Fortran
  double-precision evaluations: elementwise arithmetic |err| <= 1e-5 (|a| + |b|); elementwise functions on
  |x| <= 20 |err| <= 1e-5 max(1, |f(x)|); reductions over n terms |err| <= 1e-5 sum|terms|; `matmul`
  |err| <= 1e-5 sum_k |a_ik b_kj|; FFTs of length n ||err||_2 <= 1e-5 log2(n) ||x||_2; scatter-add
  |err| <= 1e-5 sum_m |contribution_m|. The factor 1e-5 is *guessed* (two orders above float32 rounding, four
  below a wrong convention). float64 on the CPU: 1e-12 for arithmetic, reductions and `matmul`; `exp`, `sin`,
  `cos` and FFTs held to the float32 tolerances (decision 10).
- **The polar pipeline: oracles.** The unit fixture keeps SIMPLE's structure at small size (pftsz 32, nk 10,
  8 references and 6 particles per half, 96 pairs, temperatures 0, 1, 30 and 1e4): random polar rings, the
  memo arrays computed from them as SIMPLE computes them (by a plain double-precision DFT), and an oracle that
  computes d from the rings directly, sum_k w_k sum_j |X_j - C_j R_(j-r)|^2 / (2 wsq) over the full ring,
  with no transform. The accuracy block (64 particles against 1,000 references at SIMPLE's sizes, 64,000
  pairs) uses a double-precision DFT-matrix oracle and runs in `bench_polar_table suite=accuracy`.
  - Rows (scoring-only mode): calibration in Phase 2a on the CPU device, fixture seed 1 and block seed 1:
    the largest error of d relative to max|d| (e_cpu) and the pairs whose minimising rotation differs from
    the oracle's (n_cpu). Frozen in a Progress entry before any GPU run, judged on seed 2 for every
    formulation: error at most 2 e_cpu (factor *guessed*); minimising-rotation disagreements at most
    max(2 n_cpu, q), q the smallest count a Poisson variable at SIMPLE's measured 1e-5 per pair (3 of 320,000,
    *measured*) exceeds with probability below 1e-4 (*guessed*): q = 1 for 96 pairs, 5 for 64,000.
  - The draw, given the device's own rows: for every pair, the drawn irot's interval of the cumulative weight
    computed in double precision from those rows contains u W within 1e-4 W (*derived*: a float32 cumulative
    sum of at most 364 non-negative terms errs by at most about 364 x 2^-24 = 2.2e-5 relative; 1e-4 leaves a
    factor 4.5), the fallbacks hold, and the entry's distance is d(irot) exactly. Reported, not gated: how
    often the device's irot differs from the oracle rows' draw with the same u, per temperature.
- **Production-contract coverage.** Exercise both halves separately, ordinary and shifted-bank particles,
  full/partial particle and reference tiles, contiguous and listed references, one and multiple states, and
  the shared-representative subset with its global IDs. Include zero-temperature, invalid-row and
  first-reaching/fallback cases. Check generation/half/shape/list mismatches before scoring, rebuild after
  reference changes, and return active-memory/live-handle counts to their warm baseline after teardown.
  Oracle expectations remain independent of the GPU packing and execution code.
- **Schedule and tile checks.** With inputs, variates, precision, formulation and canonical tile mapping
  fixed, three repeats (*exact*, following SIMPLE's block tester) and changes in outer batches, CPU team
  size and synchronous/two-slot consumption give identical entries by global pair ID. If a raw reblocking
  changes arithmetic, preserve canonical padded slots and record the mechanism; do not relax this schedule
  gate. Test GPU tile shapes and pair positions separately, including partial edges and shuffled reference
  lists; each candidate still meets the frozen row/draw gates above. Report loss errors and best/sampled
  rotation changes against the oracle and the canonical configuration, per temperature, with caller-u
  rounding separated. SIMPLE's 70/320,000 draw differences are a sensitivity observation, not a new tolerance.
- **Accelerated mode** (M5 Ultra): the same frozen gates; the report gives its errors and whether it passed.
- **Peak memory.** Record MLX peak, host staging and reference bytes, process peak and the estimated combined
  live pipeline allocations without counting aliases twice (decision 42). Include FFT/posterior scratch,
  compilation-retained arrays and both slots when overlapping. The verdict's configuration stays under the
  budget of decision 20; retained bytes and observed process growth must be reconciled before a go verdict.
- **The polar verdict** (pre-registered; on the M5 Ultra against the refreshed production baseline).
  Throughput in pairs per second for 2,500 directions times 4 states (10,000 references) against 2,000
  particles total, split between halves as SIMPLE's driver does, with every scoring block confined to one
  half: the table entries of every pair (decisions 31, 42), references resident, including GPU particle-term
  construction/upload, the complete draw and copying entries into Fortran arrays. Match memo dimensions,
  shells, dtypes, temperatures and half counts to the recorded CPU case. Count useful pairs, never padding.
  Use the best validated (B, R_t) and formulation in full precision; best of 3 after a warm-up, with two
  benchmark invocations per case to report A-A spread. Against SIMPLE's `block_prod` at all cores on the
  same machine/case, using its fastest measured CPU block size:
  - at least 2.0 times (decision 26, denominator revised by 42): **go**; recommend SIMPLE's integration plan;
  - at least 1.0 and below 2.0 times: **lead**; the report gives the profile and Hans rules;
  - below 1.0 times: **negative**; the report gives the profile and the mechanism.

  Reported beside it: reference packing/upload, cold compilation and amortised preparation; GPU stage
  timings from profile mode; production CPU fill timings where available (`block_prod` does not instrument
  internal stages); shared-representative throughput and occupancy; the accelerated mode; the M2 Ultra's
  numbers; the overlap measurement. `matrix_t` may be reported as historical context, never as the verdict's
  denominator or as production stage timings. Project end-to-end gain as `1 / (1 - s*f + s*f/g)` only from
  a matching current profile with assumptions stated, or report it as a function of unmeasured s and f.
  A synthetic scoring verdict is not a measured speedup or scientific acceptance of a SIMPLE refinement.
- **Overlap** (reported): compare synchronous and two-slot schedules at the same canonical tile plan; with
  n+1 queued from outside any OpenMP region, measure the fraction of CPU preparation/consumption hidden and
  GPU slowdown under a concurrent CPU memory-streaming load. Use ordinary Fortran arrays in CPU regions;
  keep live handles on the submitting thread. Record both-slot memory and completed-work wall time.
- **FFT pipeline**: images per second on the GPU and with FFTW, per box, and the crossover. Not gated.
- **Gather and scatter**: the tolerances above; two GPU runs of an atomic scatter-add may differ, their
  difference is recorded and lies within the tolerance; the sorted form is bit-reproducible run to run.

## 7. Common rules and stop conditions

Rules: no file outside the table (a needed file gets a row first; the report lists them); no tolerance, floor or
threshold relaxed without a ruling, each frozen in Progress before the run it judges; the house rules of
`doc/architecture_principles.md` hold (decision 35): structural rules are checked by `scripts/check_rules.py`
in the static gate, each new one with a planted violation shown to fail (decision 36), behavioural rules
(decisions 7, 8, 9, 12, 14) by tests and guard groups (decision 37); before a phase is DONE,
`scripts/check_tree.sh` passes, every touched Fortran file has been through `restyle_fortran.py` and
`format_use_blocks.py`, and Debug and Release build with zero compiler warnings; owner decisions applied and
delivered batches get an entry in `doc/history/2026-11.md`; timed runs in Release on an idle Mac with
the load recorded, best of 3 after a warm-up, the A-A spread reported, the precision mode in every row; GPU
phases on a Mac whose GPU the run's session can open; Python standard library, 3.7 or newer; Fortran per the
skill `mlxf-modern-fortran`; no commit, no push.

Stop when:

- the repository has no commit at launch;
- the dependencies are missing or not shared, or the run's session sees no GPU device;
- SIMPLE's pinned baseline does not build or the required scorer/check/fill baseline fails (Phase 0 or the
  Phase 2 refresh); record pre-existing unrelated suite failures separately, never substitute `matrix_t`;
- GFortran cannot carry a decision beyond the bug already known: a leak or double free in a case the leak gate
  covers; the registry failing to turn the bypass into a diagnosis; `bind(c)` value structs passed wrongly;
  `c_loc` of an assumed-rank array refused; a Phase 1 probe failing. Stop with a reproducer and alternatives;
- MLX contradicts a decision (an operation missing for complex64 or float32 on the GPU; `irfft`'s
  normalisation not as decision 20 states; a compiled closure that cannot call back into Fortran);
- a tolerance, floor or threshold would have to move; a file outside the table needs an edit;
- canonical scheduling cannot satisfy the exact-entry gate, or no oracle-passing GPU tile fits the live
  memory budget; stop with the offending pairs/configuration and measured memory, not a weaker gate;
- the M5 Ultra is not available when Phase 2 reaches its verdict (record the M2 Ultra's results and stop).

Gates no ruling may waive: the leak, diagnosis and recovery gates; byte identity of data movement; generator
coverage; the oracle comparisons on both devices; the frozen tolerances; the canonical-schedule identity gate.

## 8. Phases

**Launch precondition.** Hans has committed the scaffold; that commit is the base. No commit: stop.

### Phase 0, the baseline

Completed historical protocol at `5709265cb`. Its measured rows stay as recorded. For future work, decision
42 and Phase 2's baseline refresh replace step 5's CPU comparator and step 7's timing-profile assumptions;
do not repeat this old `matrix_t` protocol as the production acceptance baseline.

1. Record the machine (chip, cores, GPU cores, memory, macOS, Xcode or Command Line Tools, GFortran, CMake,
   Python, load) and the base commit.
2. The dependencies: Homebrew's `mlx-c` (record the versions; Homebrew's `mlx` depends on a `python@3.x`
   that can take over the unversioned `python3` link: record `python3 --version` before and after and
   restore it), or `scripts/build_mlx_deps.sh` where Xcode's Metal toolchain exists. Check that `libmlx` and
   `libmlxc` are shared and `mlx.metallib` is installed.
3. Build mlx-c's `examples/example.c` and `examples/example-metal-kernel.c` (from a `git archive` export of
   `~/src/mlx-c` at `v0.8.0`) against the install with clang, and run them.
4. Build the scaffold in Debug and Release, keeping each build tree as the base build; record the gate, and
   the MLX runtime version and GPU device count `mlxf_test_exec test=unit_core` prints from inside the run's
   session (0 stops the run); check that the installed `mlxf_test_exec` loads `libmlxc`.
5. The SIMPLE baseline. Export SIMPLE `5709265cb` into scratch; configure by hand in Release with tests and
   `-DFORTLS=OFF`; build; run its gate (a failure that does not stop the benchmark is recorded and left
   alone; the benchmark then runs from the build tree's `bin/`). Record the BLAS and FFTW it links. Confirm
   the keys with `simple_test_exec test=polar_matching_bench suite=list`. Run, each twice,
   `OPENBLAS_NUM_THREADS=1 simple_test_exec test=polar_matching_bench suite=<per_pair|matrix_t>
   nspace=<1000|2500> nstates=<1|4> nthr=<all cores>` (each run sweeps all, all/2 and 1 itself; add a run at
   the performance-core count when it differs from all/2). Record pairs per second, µs per pair and thread,
   the part timings and the spread; keep the TSV files. Run `suite=check nthr=<all>` once. This step runs on
   the M2 Ultra; the M5 Ultra instead uses the production-baseline refresh of decision 42.
6. Read SIMPLE's planner flag and threading model for particle-image FFTs (`simple_fftw3`, the image FFT
   setup) for decision 21.
7. If the rulings file names a SIMPLE BENCH output, record f of decision 28 from its `prob_fill_profile`
   (`ts_seed`, `ts_score`, `ts_refine`, `wall_region`); otherwise record that f is unmeasured.

Exit: the machine record and base commit; dependencies recorded and shared; the C examples run on the GPU; the
scaffold's gate passes in Debug and Release; a GPU device visible from the run's session; the installed test
executable loads; SIMPLE's baselines on the M2 Ultra recorded twice per case with their spread; the FFT
planner flag recorded.

### Phase 1, the handle model and the core

1. Probes, in scratch, recorded in Progress before the API is written: the allocatable-component bypass of
   section 2 (expected to reproduce; its result fixes the restriction of decision 8), plain array components,
   `a%kind()` as a type-bound call, a generic extending `max` and `real` with a module that uses it still
   evaluating `integer, parameter :: n = max(2, 3)`, a `contiguous` assumed-rank dummy receiving a strided
   section, and an `impure elemental` defined assignment with `final` on a type holding a `bind(c)` handle
   under self-assignment, parentheses and array constructors. A failed probe other than the known bug is a
   stop.
2. `scripts/list_mlxc_prototypes.py` writes the frozen prototype list into Progress; then the generator and
   its CMake custom command (inputs `MLX_C_INCLUDE_DIRS`, outputs into `build/gen/` and `mlxf`, rerun when a
   header or the generator changes), failing unless generated plus skipped names equal the list.
   `mlxf_version` moves to the generated interfaces and `mlxf_libc`.
3. `mlxf_libc`, `mlxf_error` (decisions 12, 14), `mlxf_registry` (decision 8), `mlxf_device` (decision 13),
   `mlxf_memory` (decision 17), `mlxf_array` (decisions 6 to 11, 16: the type, its lifetime, getters,
   `mlx_from`, `mlx_alloc`, `mlx_to`, `mlx_to_alloc`, `mlx_view`, `mlx_is_live`, `mlx_eval`,
   `mlx_async_eval`, `mlx_synchronize`, the elementwise `+ - *` and `exp` the leak gate uses), `mlxf`, and
   `mlxf_runtime_description()` (decision 15).
4. Testers: `mlxf_error_tester` (the recovery gate; a recorded message); `mlxf_registry_tester` (counts,
   serials, the diagnosis gate, the per-operand cost); `mlxf_device_tester`; `mlxf_memory_tester`;
   `mlxf_array_tester` (the leak gate; byte identity of `mlx_from`, `mlx_to`, `mlx_to_alloc` for ranks 0 to 4
   and 7, all six kinds (float64 on the CPU), odd sizes, a zero-size array, strided sections in and out, both
   devices; `(3,5)` reaches MLX as `[5,3]` and `a%shape()` returns `[3,5]`; a transposed array does not
   compare equal; `mlx_view` of a non-contiguous array returns a status; a view survives unrelated
   evaluations; the zero-copy table for `mlx_alloc` from 1 KiB to 64 MiB, multiples of 16 KiB and not).
5. `mlxf_test_exec device=cpu|gpu|all` and `mlxf_test_exec expect_aborts <group>` (decision 37: each member
   of the group in a child process through `execute_command_line`, accepted only with
   `MLXF_HARD_ERROR_STATUS`, every faulty member reported); the guard group `object_contracts` with its
   members, each confirmed once from its verbose output to stop at its own guard; the CTest entries
   `unit_array` and `object_contracts`, `MLXF_CTEST_BUDGET` 3; `MLXF_REQUIRE_GPU` (a compile definition of
   `mlxf_test_exec`) and the CI setting with `MLXF_WERROR=ON`; `MLXF_CMAKE_ARGS` in the compile scripts;
   `bits_equal` in `mlxf_test_utils`.
6. The static gate (decision 36): the `cbind` and `libc` ledger entries of `mlxf_version` deleted (the probe
   is gone); the module variables of `mlxf_registry`, `mlxf_error` and `mlxf_device` (the initialisation
   flag) entered in the `state` ledger with their reason, and nothing else; a check that `mlxf.f90`
   re-exports no `mlxc_` name added to `check_rules.py` with a planted violation shown to fail.
7. `doc/policies/binding_contract_policy.md`: decisions 6 to 18 and 29 to 30 as living rules, with the
   restriction and assignment pattern of decision 8, the buffer protocol of decision 9 and the float64 list of
   decision 10. The skill `mlxf-binding` (adding a wrapper: the generated procedure, the helper of its class,
   the axis, index and position translation, the registry check, the two-device test). `CLAUDE.md`,
   `AGENTS.md` and `doc/how2s/how2set_up_dev.md` point at them.

Exit: the probes recorded, the bypass reproduced or its absence recorded, the others passed; the frozen list in
Progress, the build passing against it and failing when one mapping is removed; `unit_core` and `unit_array`
pass on both devices in Debug and Release; the leak, diagnosis and recovery gates pass on both devices; the
registry's cost and the zero-copy table are in Progress; `mlxf_test_exec expect_aborts object_contracts`
passes and fails when one member's stop is removed; `MLXF_CTEST_BUDGET` is 3 and configuration fails at 2;
`scripts/check_tree.sh` passes with the ledgers of step 6, and the new check fails on its plant; Debug and
Release build with zero compiler warnings; the policy and the skill exist.

### Phase 2, milestone 1: the tiled polar pipeline

**Baseline refresh before step 1 (decision 42).** Keep Phase 0's logs unchanged. Record the mlx-fortran
snapshot after the owner's Phase 1 fixes, the machine, compiler, BLAS/FFTW and the pinned SIMPLE commit.

- Build SIMPLE `7ec7e29720b3e57c2a56a6a7ab754e6f6c57fe35` in scratch, Release with tests and
  `-DFORTLS=OFF`, and run its fast gate. Confirm the driver with
  `simple_test_exec test=polar_matching_bench suite=list`. Run each of the four dense cases twice:
  `OPENBLAS_NUM_THREADS=1 simple_test_exec test=polar_matching_bench suite=block_prod
  nspace=<1000|2500> nstates=<1|4> nptcls=2000 nthr=<all cores>`. The driver sweeps B = 4, 8, 16 at the
  full team, then teams all/2 and 1; add the performance-core team when distinct. Keep every TSV, load record,
  useful-pair count, B and timing spread. Label the driver's one-thread 200-particle cap; do not compare it
  as the same completed workload as the all-core verdict. Record actual polar dimensions and both-half
  reference residency for the GPU generator. Keep full-reference memo setup and memory separate from warm
  scoring; unavailable setup/stage measurements are explicitly unmeasured, never inferred from zero fields.
- Run `suite=check nthr=<all cores>` and `suite=fills nthr=<all cores>` at that pin, retaining the latter's
  default fixture sizes and all routes, including seeded/no-shift dense and `state`/`geom`. Record failures
  against their case, not just aggregate status. Run `suite=neigh nthr=<all cores>` twice with the driver's
  default late-stage sizes, preserving the representative, member and cone rows separately, their active
  list sizes, useful/wasted slots, timings and identity results. Only shared representatives become a GPU
  route here; sparse rows explain the boundary and are not a new GPU implementation target.
- Extract s, f, seed/score/refinement costs and fill wall time from an available current production profile,
  recording its SIMPLE revision, data, stages, parts, teams and timing units. The earlier BENCH run and Dell
  BLAS report are context, not a current Mac profile. Without a matching profile, record s/f as unmeasured
  and keep projections parametric; this does not block the synthetic pipeline benchmark.

Refresh exit: the production baseline is built and measured twice per dense case, required scorer/fill checks
pass, neighbourhood rows and memory facts are retained, the CPU/GPU workload and timing boundaries are written
in Progress, and any current-profile gap is explicit. None of this exit is claimed by this plan-only revision.

1. The operations decision 20 and its tests use (decision 29): `mlx_permute`, `mlx_concatenate`, `reshape`,
   `transpose`, `conjg`, the elementwise operators and comparisons with broadcasting and weak scalars,
   `.and.`, `merge`, `max`, `exp`, `minval` and `sum` along a dimension, `mlx_cumsum`, `mlx_slice`,
   `mlx_take_along_dim`, `mlx_astype`, `real`, `aimag` and `cmplx` (formulation B), `mlx_zeros` and
   `mlx_arange` (fixtures). `mlxf_linalg`: `matmul` for real and complex operands, batched and broadcast.
   `mlxf_fft`: `mlx_irfft` and `mlx_rfft` along one dimension with optional `n` and `norm`.
2. `mlxf_compile`: `mlx_function` and `mlx_compile` (decision 30), with its tester (a compiled elementwise
   function equals the uncompiled one; shapeless compilation over two tile sizes; an error inside the
   callback returns a status).
3. Testers of each operation on both devices, with the tolerances of section 6 and the conventions asserted:
   dimension numbering, broadcasting alignment, `mlx_permute`'s order, 1-based indices and positions, FFT sign
   and normalisation, the draw's first-reaching rule.
4. The test-only pipeline in `src/test/mlxf_kernel_polar_table.f90`: the workspace owner and procedure
   interfaces, with `_lifecycle` and `_score` submodules for preparation/invalidation/teardown and scoring.
   Inputs travel through a validated spec (decision 39); no second handle-ownership implementation.
   Implement A first against the production algebra, then the planned B/C and compilation experiments.
   Exercise persistent references, both halves, optional seed banks, partial tiles and ordered reference
   subsets; the dense route and shared-representative route return the same kind of compact entries. Keep
   independent fixtures/ring oracles and double-precision draw checks in the tester; the production-size
   accuracy generator uses its DFT-matrix oracle. Tester `unit_kernels suite=polar_table` stays fixture-only
   and includes lifecycle/invalid-generation and canonical-schedule checks (section 6).
   Benchmark `bench_polar_table` in `src/test/mlxf_bench_polar_table.f90` owns outer batches and submission.
   Modes: `time` (the four dense cases, 1,000 or 2,500 directions times 1 or 4 states against 2,000 particles
   split between halves, plus a shared-representative case matching the refreshed `neigh` workload; the
   decision-20 GPU tile sweep with complete memory accounting and occupancy), `profile` (evaluation barriers
   after stages, separately reported), `accuracy` (oracles, shape/position/list/compilation sensitivity),
   `overlap` (synchronous versus two slots, including complete-candidate consumption dependencies). Record
   reference preparation, cold compilation, warm entry throughput and amortised preparation separately.
5. Phase 2a: the calibration of section 6 on the CPU device, then the frozen tolerances, in a Progress entry.
   Until that entry exists the `kernels` area is not in `MLXF_TEST_AREAS` and runs only with `device=cpu`.
6. Add `kernels` to the CTest areas (with `ops`, `linalg`, `fft` and `compile`, `MLXF_CTEST_BUDGET` 8,
   decision 37); GPU runs of the tester and the accuracy block (seed 2) on the M2 Ultra; the benchmark on the
   M2 Ultra.
7. On the M5 Ultra: record the machine/dependencies and current mlx-fortran gates, repeat this phase's
   production-baseline refresh, then the benchmark in both precision modes and the verdict against
   `block_prod`. Recheck the recorded polar dimensions and half counts. Do not rerun Phase 0's historical
   `matrix_t` comparator as the acceptance baseline.
8. The interim summary for ruling 32 in Progress: what milestone 1 proved, the verdict and its branch, peak
   memory, the formulation and canonical tile plan, numerical sensitivity, current-profile gaps and what
   SIMPLE's integration would take: calculator-owned workspace and a split preparation/submission/consumption
   schedule. Leave sparse candidates and scientific default adoption to that later plan. Hold.

Exit: the production-baseline refresh is recorded on both Macs; the unit suites pass on both devices in Debug
and Release on both Macs; the Phase 2a entry precedes the first GPU run of `polar_table`; `polar_table` and the
accuracy block pass on the GPU with the frozen tolerances
for every formulation counted; the lifecycle and canonical-schedule checks pass; numerical sensitivity,
useful/padded pairs, full memory accounting and precision mode accompany the benchmark rows; the verdict
against `block_prod` is recorded with its branch; the interim summary exists. No SIMPLE source is changed.

### Phase 3, n-dimensional FFTs (after ruling 32)

1. `mlx_fft2`, `mlx_ifft2`, `mlx_rfft2`, `mlx_irfft2`, `mlx_fftn`, `mlx_ifftn`, `mlx_rfftn`, `mlx_irfftn` over given
   dimensions with optional sizes, `mlx_fftshift`, `mlx_ifftshift`, `mlx_fft`, `mlx_ifft`.
2. Tests against a double-precision DFT at sizes 7, 64, 180 and 181, both devices.
3. `bench_fft2` (decisions 21, 23), with the optional FFTW link on `mlxf_test_exec`.

Exit: the tests pass on both devices; the benchmark's rows for every box are kept, with the crossover stated.

### Phase 4, interpolation and reconstruction (after ruling 32)

1. In `mlxf_ops`: `mlx_take` by linear index, `mlx_gather`, `mlx_scatter`, `mlx_scatter_add` (complex64 and
   float32), `mlx_argsort`, and what the sorted segmented sum needs.
2. `mlxf_kernel`: `mlx_metal_kernel` and its tester (an elementwise kernel and one with atomic outputs,
   against oracles, GPU only).
3. The pipelines in `src/test/mlxf_kernel_gridding.f90` with double-precision oracles; testers
   `unit_kernels suite=polarize` and `suite=insert` (fixture sizes); `bench_gather_scatter`
   (`src/test/mlxf_bench_gather_scatter.f90`) with the three insertion forms of decision 33.

Exit: the tests pass on both devices (Metal-kernel tests on the GPU); two GPU runs of the atomic insertion
differ within the tolerance and the sorted form is bit-reproducible; the benchmark's rows are kept.

### Phase 5, packaging for consumers

1. `cmake/mlxfConfig.cmake.in` with its version file: the imported target `mlxf::mlxf`, `find_dependency(MLXC)`,
   and the Fortran compiler and version the modules were built with; a consumer configured with another
   compiler version stops at configure time. `cmake/mlxf.pc.in`.
2. `test/consumer/`: a minimal outside project that builds the README's sketch against the install tree, and
   `scripts/check_install.sh`, which installs, configures it with only `-Dmlxf_DIR=`, builds and runs it.
3. `README.md`: the API overview. `doc/how2s/how2use_from_simple.md`: how SIMPLE finds and links the library
   and owns its reference tiles.

Exit: `scripts/check_install.sh` passes; a consumer with an edited compiler version is refused; the README
sketch runs in the consumer.

### Phase 6, the report

`doc/implementation_notes/completed/mlxf_design_report.md` in the order of section 8 of
`doc/how2s/how2write_agent_plans.md`; this plan moves to `doc/implementation_notes/completed/mlxf_design.md`.

Exit: the report exists, cites every Progress entry, and lists every file changed outside the table.

### File table

Paths from the repository root. A listed `x.f90` also covers `x_tester.f90`.

| File | What | Phases |
| --- | --- | --- |
| `CMakeLists.txt` | `MLXF_REQUIRE_GPU`, packaging | 1, 5 |
| `cmake/Dependencies.cmake` | the generator's inputs if needed; the optional FFTW | 1, 3 |
| `cmake/CompilerConfig.cmake` | if needed | each |
| `cmake/mlxfConfig.cmake.in` | the package config | 5 |
| `cmake/mlxf.pc.in` | pkg-config | 5 |
| `src/CMakeLists.txt` | generated sources, install rules | 1, 5 |
| `test/CMakeLists.txt` | areas, guard groups, the budget, `MLXF_REQUIRE_GPU`, the FFTW link | 1, 2, 3, 4 |
| `test/mlxf_test_exec.f90` | `device=`, `expect_aborts`, the `bench_<x>` entries | 1, 2 |
| `test/consumer/` | the consumer project (folder) | 5 |
| `scripts/list_mlxc_prototypes.py` | the independent prototype list | 1 |
| `scripts/gen_mlxc_bindings.py` | the generator | 1, 2, 3, 4 |
| `scripts/check_rules.py` | ledgers, the re-export check, rules learned | each |
| `scripts/check_tree.sh` | if needed | each |
| `scripts/run_fast_gate.sh` | if needed | each |
| `scripts/restyle_fortran.py`, `scripts/format_use_blocks.py` | if needed | each |
| `scripts/check_test_registry.py` | guard groups; the benchmark rows | 1, 2 |
| `scripts/check_install.sh` | the consumer check | 5 |
| `scripts/build_mlx_deps.sh` | if needed | 0 |
| `compile_clean.sh`, `compile_debug.sh`, `recompile.sh` | `MLXF_CMAKE_ARGS` | 1 |
| `src/defs/mlxf_defs.f90` | exported constants and vocabularies (decision 40) | 1, 2 |
| `src/core/runtime/mlxf_libc.f90` | libc entry points | 1 |
| `src/core/runtime/mlxf_error.f90` | errors, recovery, the last error, the one-thread guard | 1 |
| `src/core/runtime/mlxf_registry.f90` | live handles, counts, serials | 1 |
| `src/core/runtime/mlxf_device.f90` | devices, the entry, initialisation | 1, 2 |
| `src/core/runtime/mlxf_memory.f90` | memory controls | 1 |
| `src/core/runtime/mlxf_version.f90` | runtime description | 1 |
| `src/core/core.inf`, `src/core/<capability>/<capability>.inf`, `src/test/test.inf`, `test/test.inf` | if needed | each |
| `src/core/array/mlxf_array.f90` | the array type, its generics and interfaces (decision 41) | 1, 2 |
| `src/core/array/mlxf_array_{lifetime,transfer,borrow,evaluation,elementwise}.f90` | its implementation submodules | 1, 2 |
| `src/core/mlxf.f90` | the user module, the only one installed | 1, 2, 3, 4 |
| `src/core/ops/mlxf_ops.f90`, `src/core/ops/mlxf_ops_*.f90` | operations (submodules) | 2, 4 |
| `src/core/linalg/mlxf_linalg.f90` | `matmul` | 2 |
| `src/core/fft/mlxf_fft.f90` | FFTs | 2, 3 |
| `src/core/compile/mlxf_compile.f90` | `mlx_function`, `mlx_compile` | 2 |
| `src/core/kernel/mlxf_kernel.f90` | Metal kernels | 4 |
| `src/test/mlxf_test_registry.f90` | areas, benchmarks | 1, 2, 3, 4 |
| `src/test/mlxf_test_utils.f90` | `bits_equal`, assertions for complex values and arrays | 1, 2 |
| `src/test/mlxf_test_defs.f90` | shared test tolerances and behaviourless input specs when exported (decision 40) | 2 |
| `src/test/mlxf_kernel_polar_table.f90` | test-only polar workspace owner/interfaces; its tester owns independent fixtures/oracles and contract checks | 2 |
| `src/test/mlxf_kernel_polar_table_{lifecycle,score}.f90` | preparation/invalidation/teardown and GPU scoring submodules, following decision 42 | 2 |
| `src/test/mlxf_bench_polar_table.f90` | outer batches, canonical GPU tile/schedule experiments, production-equivalent timing and memory accounting | 2 |
| `src/test/mlxf_bench_fft2.f90` | the FFT benchmark | 3 |
| `src/test/mlxf_kernel_gridding.f90` | polarisation and insertion, oracles | 4 |
| `src/test/mlxf_bench_gather_scatter.f90` | their benchmark | 4 |
| `doc/policies/binding_contract_policy.md` | the contract | 1, 2, 3, 4 |
| `doc/policies/README.md` | the index | 1 |
| `doc/policies/compile_time_policy.md` | if needed | each |
| `doc/policies/test_environment_policy.md` | benchmarks, `device=`, precision mode | 1, 2 |
| `.github/skills/mlxf-binding/SKILL.md` | how to add a wrapper | 1, 2, 3, 4 |
| `.github/skills/mlxf-modern-fortran/SKILL.md` | the ownership restriction; rules learned | each |
| `.github/skills/mlxf-modern-fortran/references/testing.md` | if a rule is learned | each |
| `.github/workflows/ci.yml` | `MLXF_REQUIRE_GPU=OFF` | 1 |
| `CLAUDE.md`, `AGENTS.md` | pointers | 1 |
| `README.md` | the API overview | 5 |
| `doc/how2s/how2set_up_dev.md` | new options, packaging | 1, 5 |
| `doc/how2s/how2use_from_simple.md` | the consumer guide | 5 |
| `doc/architecture_principles.md` | a rule learned (with its check) | each |
| `doc/compiler_issues/` | reproducers of compiler defects (folder; decision 39) | 1 |
| `doc/history/2026-11.md`, `doc/history/2026-12.md` | owner decisions applied, batches delivered | each |
| `doc/implementation_notes/planned/mlxf_design.md` | decisions, remaining phases and Progress; sole file of the decision-42 revision | each |
| `doc/implementation_notes/completed/mlxf_design.md` | the plan, moved | 6 |
| `doc/implementation_notes/completed/mlxf_design_report.md` | the report | 6 |

## Progress

(one entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was
met, log paths, decisions taken under delegation, what it means in short)

### Pre-launch checks, 2026-11-20 (interactive, through the build bridge; not Phase 0)

- Machine: Apple M2 Ultra, 16 performance and 8 efficiency cores, 76-core GPU (Metal 4), 192 GB, macOS 26.7.3
  (25G342); Command Line Tools only, no Xcode (no `xcrun metal`). GFortran 16.2.0 (Homebrew), CMake 4.2.1; the
  build picked miniforge's Python 3.12 for its scripts.
- Dependencies: `brew install mlx-c` poured MLX 0.32.4 and mlx-c 0.8.0 with `share/cmake/MLXC` and shared
  `libmlx.dylib`, `libmlxc.dylib` (absolute install names; they link Metal and libc++ only). It also installed
  `python@3.15`, which took over `/opt/homebrew/bin/python3` (3.14.6 to 3.15.2); restored with
  `brew unlink python@3.15` and `brew unlink python@3.14 && brew link python@3.14`; `python3` is 3.14.6 again.
  mlx-c's config prints a CMake developer warning (`find_package_handle_standard_args(MLX_C ...)` inside
  package MLXC); harmless.
- Scaffold: `./compile_debug.sh` and `./compile_clean.sh` pass the fast gate (unit_core, 5 checks, 0.3 s).
  Fixed on the way: the build-info constant `MLXF_VERSION_STRING` clashed with the function
  `mlxf_version_string` (Fortran is case-insensitive); `find_program` with `NO_CACHE` still skipped the search
  while its variable was set (now unset first); a double allocation in the C-string copy (caught by the
  gate). From the bridge's session: MLX runtime 0.32.4, one GPU device; the installed `mlxf_test_exec` runs
  (rpath `/opt/homebrew/lib`). CTest now sets `MLX_ENABLE_TF32=0`.
- Ownership probe (gfortran 16.2.0, `-std=f2018`, `-O0 -g -fcheck=bounds,do,mem` and `-O3`, identical): a type
  `h` with a type-bound `impure elemental` defined assignment and a `final`; intrinsic assignment of an
  enclosing type calls it once for a plain component, zero times for an allocatable scalar component (also
  when the left side's component is allocated) and for an allocatable array component; `allocate(s, source=t)`
  calls it zero times; `t = t` once. The standalone reproducer, warning-free under `-Wall`, is
  `doc/compiler_issues/gfortran_alloc_component_defined_assignment.f90` (the upstream report of decision 34).
- House rules imported before launch (decision 35, `doc/history/2026-11.md`): the register, the static gate
  with `check_rules.py` (every rule shown to fail on a planted violation), XEMA's formatters, flags on an
  interface target, per-target module directories, the CTest budget (shown to fail configuration at 2).
  Debug and Release build with zero warnings under `-Wall -Wextra -Wimplicit-interface -std=f2018` and pass
  the gate.
- Not done: the base commit; mlx-c's C examples; SIMPLE's baseline.

### Phase 0, the baseline: 2026-11-20 to 2026-11-21 (arun `mlxf_core`, unattended)

Machine FWM-S116118; base `86a43fae2` (the scaffold, working tree clean at start). Paths below are under
`/Users/elmlundho/agent_work/arun/mlxf_core/scratch` (`logs/` and `keep/` there). No source file edited. Files
changed: this plan (decision 28's record, decision 38, this entry) and `doc/history/2026-11.md`.

- **Exit 1, the machine and the base: met.** Apple M2 Ultra, 16 performance and 8 efficiency cores
  (`hw.ncpu` 24), 76-core GPU (Metal 4, `applegpu_g14d`), 192 GB; macOS 26.7.3 (25G342); Command Line Tools
  only (`xcrun --find metal` fails); GFortran 16.2.0 (Homebrew), CMake 4.2.1, Apple clang 21.0.0, `python3`
  3.14.6 (Homebrew `python@3.14`). Load at start 2.15 (1 min). Base `86a43fae2bfe` exported with
  `git archive` to `keep/base_src`.
- **Exit 2, the dependencies: met.** Homebrew `mlx` 0.32.4 and `mlx-c` 0.8.0, nothing installed or changed by
  the run. `libmlxc.dylib` (install name `/opt/homebrew/opt/mlx-c/lib/libmlxc.dylib`) and `libmlx.dylib` are
  shared (no static archives), with Metal, Foundation, QuartzCore, Accelerate, libc++ and libSystem;
  `mlx.metallib` is `/opt/homebrew/opt/mlx/lib/mlx.metallib` (147 MB); `share/cmake/MLXC` is installed.
  `python3 --version` 3.14.6 before and after (the run touched no link).
- **Exit 3, the C examples on the GPU: met.** mlx-c `v0.8.0` (`a26f2d584a14`) `examples/` exported, built
  with `clang -I/opt/homebrew/include -L/opt/homebrew/lib -lmlxc`. `example`: MLX 0.32.4, GPU device count 1,
  `max_buffer_length` 129,879,801,856, `max_recommended_working_set_size` 173,173,080,064, `resource_limit`
  499,000, its arithmetic on the CPU stream as written, exit 0. `example-metal-kernel`: a custom Metal kernel
  on `mlx_default_gpu_stream_new()`, exit 0 (`logs/mlxc_example.log`, `logs/mlxc_example_metal_kernel.log`).
- **Exit 4, the scaffold's gate in Debug and Release, the GPU from the run's session, the installed test
  executable: met.** `keep/base_debug`, `keep/base_release` (`build_base.sh`; `logs/build_base.log`,
  `logs/base_build_{Debug,Release}.log`): build, fast gate (`check_tree: passed`, `unit_core` passed) and
  install all exit 0; zero compiler warnings. The installed `bin/mlxf_test_exec test=unit_core`, run from
  this session in both trees: MLX runtime 0.32.4, **GPU devices: 1**, 5 of 5 checks
  (`logs/unit_core_base_{debug,release}.log`); it loads `/opt/homebrew/opt/mlx-c/lib/libmlxc.dylib` through
  the rpath `/opt/homebrew/lib`.
- **Exit 5, SIMPLE's baselines on the M2 Ultra, twice per case: met.** SIMPLE `5709265cb` exported to
  `keep/simple_src`, configured by hand (Release, `-DBUILD_TESTS=ON -DFORTLS=OFF`), built and installed into
  `keep/simple_release` (`build_simple.sh`, `logs/simple_build.log`, zero warnings). It links Homebrew FFTW
  3.3.10 (`libfftw3f`, `libfftw3`, `libfftw3f_threads`) and SIMPLE's bundled static OpenBLAS 0.3.34
  (OpenMP, `NUM_THREADS=128`, fetched by its CMake), libgomp and libgfortran of GCC 16.2. Its fast gate:
  15 of 15, 12.9 s (`logs/simple_fastgate.log`). `suite=list` names `per_pair`, `matrix_t` and `check`.
  Runs: `run_all_baseline.sh` and `run_simple_baseline.sh`, `OPENBLAS_NUM_THREADS=1`, each case in
  `simple_bench/<suite>_s<nspace>_n<nstates>_t<nthr>_r<rep>/`, all of run 1 before all of run 2; before each
  run the script waited for a 1-minute load of at most 4, and during it sampled every 30 s the CPU of every
  other process (`uptime.txt`, `sampler.txt`). One run (`matrix_t`, 1,000 x 4, `nthr=24`, run 2) saw other
  processes at 403 % of a core and was repeated (kept as `*.flagged`); in every other run they stayed at or below 304 %.
  Rows (`simple_bench/baseline_summary.tsv`; copies in `keep/simple_baseline_m2ultra/`) are the
  benchmark's best of 3 after a warm-up, 2,000 particles (200 at one thread); for `matrix_t` the tile is the
  fastest of its sweep at the full team. Pairs per second, run 1 / run 2 (*measured*):

  | case (directions x states) | team | `per_pair` | `matrix_t` | `matrix_t` µs/pair/thread |
  | --- | --- | --- | --- | --- |
  | 1,000 x 1 | 24 | 1.205e6 / 1.200e6 | 2.928e6 / 2.912e6 | 8.20 / 8.24 |
  | 1,000 x 4 | 24 | 1.207e6 / 1.207e6 | 2.906e6 / 2.908e6 | 8.26 / 8.25 |
  | 2,500 x 1 | 24 | 1.209e6 / 1.230e6 | 2.932e6 / 2.928e6 | 8.19 / 8.20 |
  | 2,500 x 4 (the verdict's case) | 24 | 1.222e6 / 1.231e6 | 2.949e6 / 2.909e6 | 8.14 / 8.25 |
  | 2,500 x 4 | 16 (performance cores) | 1.029e6 / 1.051e6 | 2.599e6 / 2.622e6 | 6.16 / 6.10 |
  | 2,500 x 4 | 12 | 8.24e5 / 8.30e5 | 1.817e6 / 1.902e6 | 6.60 / 6.31 |
  | 2,500 x 4 | 8 | 5.59e5 / 6.04e5 | 1.348e6 / 1.347e6 | 5.94 / 5.94 |
  | 2,500 x 4 | 1 | 8.35e4 / 8.21e4 | 1.754e5 / 1.733e5 | 5.70 / 5.77 |

  Spread between the two runs, (max - min) / min of pairs per second: at most 1.4 % for `matrix_t` and 2.1 %
  for `per_pair` at 24 and 16 threads over all four cases; at most 4.7 % (`matrix_t`) and 12 % (`per_pair`)
  at 12 and 8 threads. `matrix_t` is 2.40 times `per_pair` at 24 threads on the verdict's case. Part timings
  of `matrix_t` on that case in thread-µs per pair, run 1 / run 2: sums 3.09 / 3.52, inverse FFTs
  1.11 / 1.08, distances with the full-row draw 3.10 / 3.26 at 24 threads; 2.51 / 2.56, 0.90 / 0.87,
  2.59 / 2.58 at 16; 2.45 / 2.63, 0.87 / 0.76, 2.43 / 2.40 at one thread. The fastest tile at 24 threads
  is B 32 or 16, R 64 or 128, within 1.4 % of each other. Going from 16 to 24 threads adds the efficiency
  cores: 11 to 13 % more pairs per second at 34 % more thread-µs per pair. `suite=check nthr=24` once (6 cases,
  517.8 s, `simple_bench/check_t24/`, `simple_bench/check_summary.txt`): every layout reproduces its own
  one-thread rows byte for byte at 24 threads; `replica`, `blocked`, `states_inner` equal the replica's rows;
  `matrix` and `matrix_t` differ from them by at most 4.05e-7 relative, with 0, 0, 1, 0, 1 and 3 pairs whose
  minimising rotation differs (3 of 320,000 at 2,500 x 4, the 1e-5 per pair section 6 uses).
- **Exit 6, the FFT planner flag: met** (read at `5709265cb`). Particle images use single-precision FFTW
  with `FFTW_ESTIMATE` (`simple_image_core.f90`, `new`; `FFTW_MEASURE` only when `fft_measure` is passed,
  which the reconstruction's PCG and wave projector do), one r2c and one c2r plan per image object, planned
  under `!$omp critical`, no wisdom. The builder's particle images are made with `wthreads=.false.`
  (`simple_builder.f90`), so each image FFT is serial and the parallelism is an OpenMP loop over particles;
  FFTW's threads are used only for an image made with `wthreads` and a box of 200 or more. There is no
  batched ("many") plan for particle stacks. For comparison, the polar FFTs use `FFTW_MEASURE` with a wisdom
  file (`FFTW_ESTIMATE` under a fixed seed) and shared `plan_many` plans (`simple_polarft_memo.f90`).
  Decision 21's FFTW reference is therefore `FFTW_ESTIMATE`, one single-threaded plan per image size, an OpenMP
  loop over the batch on all cores.
- **Step 7, f of decision 28 (ruling R2): recorded.** `keep/bench_f.py` (standard library) on
  `~/for_claude/bench/BENCH/` (`keep/bench_f.out`). The records carry no stage number; a stage is a run of
  iterations with the same mode, `nspace`, `nstates` and `kto`, a stage's first iteration (which still
  reports the previous `kto`) counted with it; that gives solve3D's 8 stages and a closing `sigma` iteration.
  f = 23,459 / 101,336 = **0.2315** (seed 0, score 23,459, refinement 77,877 thread-s, *measured*).

  | stage | mode | directions | kto | iterations | score (thread-s) | refinement (thread-s) | f | fill on the critical path (s) | refine3D (s) | fill's share | assembly (s) |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | 1 | prob_neigh | 500 | 15 | 20 | 130 | 0 | 1.00 | 3 | 66 | 0.05 | 12 |
  | 2 | prob_neigh | 1,000 | 16 | 20 | 362 | 0 | 1.00 | 8 | 90 | 0.09 | 25 |
  | 3 | prob | 1,000 | 18 | 17 | 1,869 | 7,717 | 0.20 | 136 | 239 | 0.57 | 40 |
  | 4 | prob | 1,000 | 27 | 15 | 2,144 | 5,219 | 0.29 | 105 | 197 | 0.53 | 36 |
  | 5 | prob | 2,500 | 65 | 12 | 9,409 | 48,348 | 0.16 | 796 | 1,040 | 0.77 | 172 |
  | 6 | prob_neigh | 2,500 | 70 | 12 | 1,079 | 2,781 | 0.28 | 60 | 310 | 0.19 | 163 |
  | 7 | prob_neigh | 5,000 | 75 | 13 | 2,683 | 4,054 | 0.40 | 103 | 620 | 0.17 | 339 |
  | 8 | prob_neigh | 5,000 | 78 | 24 | 5,782 | 9,758 | 0.37 | 232 | 1,189 | 0.20 | 620 |
  | final | sigma | 2,500 | 78 | 1 | 0 | 0 | | 0 | 17 | 0 | 0 |
  | all | | | | 134 | 23,459 | 77,877 | 0.23 | 1,443 | 3,767 | 0.38 | 1,408 |

  The fill on the critical path (per iteration the slowest part's `match3D table fill`) is 1,443 s: 38.3 % of
  refine3D's 3,767 s and 36.7 % of solve3D's 3,929 s. The master's `refine3D assembly/postprocess` is 1,408 s
  (37.4 % of refine3D, 35.8 % of solve3D; the PCG assembly records sum to 940 s, the volume assembly records
  to 429 s). An infinitely fast score loop gains at most 1 / (1 - 0.367 x 0.2315) = 1.09 end to end on this
  run (1.16 at the 60 % share); at g = 2 and 4, 1.04 and 1.07. Every figure of R2 is reproduced; R3 calls the
  assembly "37 % of solve3D", which is its share of refine3D (decision 38 says so).
- **Decisions under delegation.** The load rule for timed runs ("repeat a run whose load rose above 4") was
  read as the load of other processes: the benchmark's own 24 threads raise the load average to about 24, so
  the script waited for a 1-minute load of at most 4 before each run and repeated a run in which other
  processes exceeded 400 % of a core. The benchmark's `load1` column is its own (it includes its previous
  rows), not the background. `nthr=16` was run as a second sweep (16, 8, 1) beside `nthr=24` (24, 12, 1), as
  the performance-core count differs from 24 / 2.
- **What it means, in short.** The toolchain, the shared mlx-c pair and the GPU all work from an unattended
  session, and the scaffold gates cleanly; Phase 1 can start. SIMPLE's best CPU layout scores 2.9e6
  pairs per second on the M2 Ultra's 24 cores (2.6e6 on the 16 performance cores), 2.2 times the M3 Pro's
  1.32e6, with a run-to-run spread of at most 2 % at the full teams; the verdict's 2.0 times would need about 5.9e6 here. The BENCH
  run says the score loop is under a quarter of the fill's thread time, so the first pipeline alone is worth at
  most 9 % end to end on that workload; decision 38 points the following pipelines at the shift refinement and
  the assembly.

### Phase 1, step 1, the probes: 2026-11-21 (arun `mlxf_core`, unattended) - STOPPED

Machine FWM-S116118, toolchain as in Phase 0; base `86a43fae2`. Paths below are under
`/Users/elmlundho/agent_work/arun/mlxf_core/scratch`. No source, script or build file was edited; files changed:
this entry and `doc/history/2026-11.md`. The run stopped at step 1, as section 7 and step 1 require when a
probe fails other than the known bug.

- **How the probes ran.** `keep/phase1_probes/run_probes.sh` compiles each probe with the project's flags
  (`-std=f2018 -Wall -Wextra -Wimplicit-interface ... -fopenmp`), Debug (`-O0 -g -fcheck=bounds,do,mem`) and
  Release (`-O3`), GNU Fortran 16.2.0; results are identical in both. The handle probes use a type holding a
  `bind(c)` handle (`type(c_ptr) :: ctx`) and an id, an `impure elemental` type-bound defined assignment
  (left side `intent(inout)`: retain the right side, release the left, skip self-assignment) and an
  `impure elemental` `final` (release), the reference counts of decision 8 kept per id. A case passes when
  every id it created is back at count 0 (no leak) and no release hits a zero count (no double free).
  Logs: `keep/phase1_probes/probes.log`, `probe_cases.log`, `probe_ctor.log`, `probe_trace.log`.
- **The known bug reproduces** (`doc/compiler_issues/gfortran_alloc_component_defined_assignment.f90`):
  plain component 1 defined assignment, allocatable scalar and array components 0, `allocate(source=)` 0,
  `t = t` 1, at `-O0` and `-O3`.
- **Passed:** `a%kind()` as a type-bound call; generics extending `max` and `real` with a using module still
  evaluating `integer, parameter :: n = max(2, 3)` and `real(3)` as constants; a `contiguous` assumed-rank
  dummy receiving the strided section `a(1:6:2, 2:4)` (copied in, `c_loc` valid, sum exact), a scalar (rank 0)
  and a zero-size array; `select rank` with `c_f_pointer` on an assumed-rank pointer dummy and `allocate` on an
  allocatable assumed-rank dummy (ranks 1, 2, 7; for `mlx_view` and `mlx_to_alloc`). Handle cases that pass
  (`probe_cases.log`): expressions with type-bound operators and nested function results
  (`c = (a + b) + f(a)`, `c = c + c`, an operator result as an actual argument); self-assignment `a = a` and
  `b = (a)`; function results as actual arguments, nested; `intent(out)` dummies; array constructors of
  variables, passed on and assigned; local handles leaving scope on return; plain scalar and array components
  copied by `p2 = p1`; element-by-element assignment of allocatable components through the enclosing type's
  defined assignment (the policy's pattern), when fed from variables.
- **Failed: three gfortran defects besides the known one**, identical in GNU Fortran 13.4.0 (no 14 or 15 is
  installed), each a leak or a double release in a case decision 8's leak gate covers. Standalone reproducers,
  warning-free under `-Wall`: `keep/compiler_issues/*.f90`, output in `keep/compiler_issues/reproducers.log`.
  1. *A function result referenced inside an array constructor is never finalized* (F2018 7.5.6.3, paragraph
     5): `call take([mk(1), mk(2)])` finalizes nothing; `v = [mk(3), mk(4)]` finalizes only `v`. With
     reference counts each such element keeps its count forever: "an array constructor of function results
     passed on" leaks one handle per element (`gfortran_finalize_ctor_function_results.f90`).
  2. *A scalar function result assigned to a whole array through the elemental defined assignment is never
     finalized*; assigned to one element it is: `v(1) = mk(1)` 1 assignment, 1 finalization; `v = mk(2)`
     3 assignments, 0 finalizations. "rank-1 and rank-3 arrays of handles, assigned and reassigned" leak
     one handle per such statement (`gfortran_finalize_scalar_result_to_array.f90`).
  3. *Intrinsic self-assignment `w = w` of a type with finalizable plain components finalizes the value the
     component assignments then read*: the final sees id 5, the defined assignment then sees right side 0,
     and `w%c` ends empty. With reference counts every component is released twice; the later releases hit a
     zero count (`gfortran_self_assignment_finalizable_components.f90`; in `probe_trace.log`, `p2 = p2`).
- **What it means for decision 8.** The registry would turn defect 3 into a diagnosed stale handle rather than
  a double free (the first release to zero frees once; the owner's next use stops; its finalization counts a
  stale release), so the "no double frees, no silent use after free" invariant can still be kept. Defects 1
  and 2 are leaks the registry cannot see: the count of an unfinalized result never returns to zero, so
  `mlx_get_active_memory` and the live count grow. The leak gate as decision 8 defines it (exact, with "an
  array constructor of function results passed on" and arrays of handles "assigned and reassigned") cannot
  pass with this compiler. The probe of step 1 ("defined assignment with final ... under self-assignment,
  parentheses and array constructors") fails on its array-constructor part.
- **Alternatives for Hans** (none taken; each changes decision 8 or its gate):
  1. *Widen the restriction of decision 8* to the three defects: no function reference inside an array
     constructor of handles (build the elements into variables first), no whole-array assignment of a scalar
     function result to an array of handles (assign a variable, or element by element), no intrinsic
     self-assignment of a type with plain handle components; the leak gate keeps its other cases and tests
     these patterns in their supported form. Defects 1 and 2 stay silent leaks when a user breaks the rule;
     only a scan of the user's code could find them.
  2. *Scoped release as a backstop*: a scope that records every handle created while it is open and, at
     its end, releases those the caller did not keep explicitly. This catches defects 1 and 2 at the cost of an
     explicit scope and a keep call in user code, and more process-global state (a change to the register).
  3. *Explicit ownership without finalizers*: `kill` only, no `final`, no counting assignment (copies
     share, the registry diagnoses double kills and stale use). Immune to the finalization defects, but every
     temporary of an expression leaks unless the library releases intermediate results itself, which defeats
     operators and functions as decision 5 writes them.
  4. *Report the three defects upstream* with these reproducers (decision 34 already does this for the known
     one) and keep decision 8 as written for a gfortran that finalizes correctly; the gate then waits for the
     fix.
- **What the run leaves.** The probe sources, scripts and logs (`keep/phase1_probes/`) and the reproducers
  (`keep/compiler_issues/`). The recovery-gate cost was measured in C on the way
  (`keep/phase1_probes/rec.c`): a broadcast add above `maxBufferLength` (129,879,801,856 B) fails at once with
  MLX's message naming the allocation; the same graph at half the batch (64.9 GB) evaluates in 2.3 s on the GPU
  and 4.6 s on the CPU, so decision 12's gate is affordable here but allocates half of `maxBufferLength` per
  device. Steps 2 to 7 did not start.

### Phase 1 resumed under ruling R4 (decision 39): the frozen prototype list, 2026-11-21

Recorded before the generator was written, as step 2 requires. `scripts/list_mlxc_prototypes.py` (statement
split at `;`, `<return type> <name>(...)`, typedefs and statics excluded, preprocessor blocks not evaluated)
on Homebrew's mlx-c 0.8.0 headers (`/opt/homebrew/include/mlx/c`, the 29 headers' SHA-256 digests hashed
together: `b86f7d1d...`) lists **680 names** (*exact*), SHA-256 of the sorted list, one name per line:
`2b6ca216b587d7e3c269db36fe6e844948a8110788a39728a70a3501a83350aa` (the list:
`/Users/elmlundho/agent_work/arun/mlxf_core/scratch/keep/mlxc_prototypes_0.8.0.txt`). Per header: array 65,
closure 37, compile 10, cuda 1, device 20, distributed 8, distributed_group 9, error 2, export 10, fast 33,
fft 16, graph_utils 6, io 10, io_types 22, linalg 21, map 16, memory 10, metal 5, ops 267, random 19, stream 22,
string 5, transforms 8, transforms_impl 2, vector 55, version 1 (half, mlx, optional: 0). Six are mlx-c's
internal `_mlx_*` entries (`_mlx_array_is_available`, `_mlx_array_wait`, `_mlx_array_is_contiguous`,
`_mlx_array_is_row_contiguous`, `_mlx_array_is_col_contiguous`, `_mlx_error`); four are the float16 and
bfloat16 entry points (`mlx_array_item_{float16,bfloat16}`, `mlx_array_data_{float16,bfloat16}`). 680 less
the six internal entries is 674, the upper of section 2's two counts.

### Phase 1, the handle model and the core: 2026-11-21 (arun `mlxf_core`, unattended, resumed under ruling R4)

Machine FWM-S116118 (load 2.2 to 3.1 during the timed runs); base `86a43fae2`. Paths below are under
`/Users/elmlundho/agent_work/arun/mlxf_core/scratch`. The stop of the step 1 entry above was answered by ruling
R4 (decision 39); its probes stand as recorded, and the leak gate's cases that hit a defect were replaced by
their supported forms.

Files changed: `CMakeLists.txt`, `src/CMakeLists.txt`, `test/CMakeLists.txt`, `test/mlxf_test_exec.f90`;
`scripts/list_mlxc_prototypes.py`, `scripts/gen_mlxc_bindings.py` (new), `scripts/check_rules.py`,
`scripts/check_test_registry.py`; `compile_clean.sh`, `compile_debug.sh`, `recompile.sh`,
`.github/workflows/ci.yml`; `src/core/` `mlxf_libc`, `mlxf_error`, `mlxf_registry`, `mlxf_device`,
`mlxf_memory`, `mlxf_array`, `mlxf` (new) and `mlxf_version` (rewritten), the testers `mlxf_error_tester`,
`mlxf_registry_tester`, `mlxf_device_tester`, `mlxf_memory_tester`, `mlxf_array_tester` (new) and
`mlxf_version_tester`; `src/test/mlxf_test_registry.f90`, `src/test/mlxf_test_utils.f90`;
`doc/policies/binding_contract_policy.md` (new), `doc/policies/README.md`, `doc/policies/test_environment_policy.md`,
`.github/skills/mlxf-binding/SKILL.md` (new), `.github/skills/mlxf-modern-fortran/SKILL.md` and
`references/testing.md`, `CLAUDE.md`, `AGENTS.md`, `doc/how2s/how2set_up_dev.md`, `doc/architecture_principles.md`,
`doc/compiler_issues/` (three reproducers, R4), `doc/history/2026-11.md`, this plan (decision 39, decision 8's
restriction and gate, the sketch of section 3, the file-table row of `doc/compiler_issues/`, Progress).

- **Exit 1, the probes: met** (entry above): the bypass reproduced; `a%kind()`, generic `max` and `real`,
  contiguous assumed rank with strided sections, `select rank`, and every handle case but the three defects
  passed; the three defects are decision 39's unsupported uses.
- **Exit 2, the frozen list and the generator: met.** The list (680 names) was recorded above before the
  generator was written. `scripts/gen_mlxc_bindings.py` writes `mlxf_c_types` (31 handle types, 5 value
  structs, 4 enumerations) and 26 interface modules: 673 interfaces generated, 7 skipped (`_mlx_error`,
  variadic; the four float16 and bfloat16 entry points, preprocessor-excluded; `mlx_io_reader_new` and
  `mlx_io_writer_new`, which take `mlx_io_vtable`), **673 + 7 = 680, the list** (every build:
  `logs/p1_{Debug,Release}_final.log`). The 27 modules compile warning-free under the project's flags. The
  build fails when one mapping is removed (`size_t`: `unmapped C type "size_t"`, build status 2,
  `logs/plants_build.log`); the coverage check caught a real gap while the generator was written (the
  float16 entries of excluded `#ifdef` blocks were first missed).
- **Exit 3, `unit_core` and `unit_array` on both devices in Debug and Release: met.** Clean trees
  `p1_debug`, `p1_release` (`build_p1.sh`, the run's build command): build, fast gate, install all exit 0;
  `unit_core` 68 to 70 checks (the address-reuse check of the serial runs only when MLX reuses the freed
  address), `unit_array` 80 checks (72 before the review's additions), both devices (`logs/p1_debug_unit_core.log`,
  `logs/p1_debug_unit_array.log`; `device=cpu` and `device=gpu` each select one device,
  `logs/p1_release_device_select.log`). The installed `mlxf_test_exec` loads
  `/opt/homebrew/opt/mlx-c/lib/libmlxc.dylib` and reports `MLX 0.32.4; default device gpu; GPU architecture
  applegpu_g14d; MLX_ENABLE_TF32=0`.
- **Exit 4, the leak, diagnosis and recovery gates on both devices: met.** Leak gate (`unit_array`): after a
  warm-up, 10,000 iterations per device of `c = exp(a*2.0 + b)` with `mlx_eval(c)`, `c = c`, `d = (a)`, a
  constructor of variables passed on, `mlx_eval` of an array of handles, function results as actual
  arguments, `intent(out)` dummies, rank-1 and rank-3 arrays of handles allocated and assigned element by
  element, from a function result into one element and from a variable to the whole array, plain scalar and
  array components copied by intrinsic assignment, allocatable components through the policy's assignment,
  handles leaving scope in a called procedure: active memory (after `mlx_synchronize` and
  `mlx_clear_cache`), live count and stale releases equal before and after (*exact*); 0.23 s on the CPU,
  2.0 s on the GPU (Release). Negative control on a copy: with `call take_list([exp(a), d])` (defect 1) in
  the loop the gate fails, live count 10,003 against 3 on the CPU (`logs/plant_leak.log`); the active memory
  alone would not have shown it, as the leaked results are never evaluated. The CI's settings
  (`MLXF_REQUIRE_GPU=OFF`, `MLXF_WERROR=ON`) build and pass the gate here (`logs/p1_ci_settings.log`). Diagnosis gate (`unit_core`, registry suite, per device): an allocatable
  component copied by intrinsic assignment and `allocate(source=)`, the original released: the copy is not
  live, the object was freed once, the copy's finalization counts one stale release; a new object at a
  reused address is live while the stale copy is not (the serial). Recovery gate (`unit_core`, error suite,
  per device): a broadcast add of 30,966 rows of 4 MiB returns a status with MLX's message `[metal::malloc]
  Attempting to allocate 129880817664 bytes which is greater than the maximum allowed buffer size of
  129879801856 bytes`; the same graph at 15,483 rows (64.9 GB) evaluates; MLX stays usable; live count and
  active memory return (*exact*).
- **Exit 5, the registry's cost and the zero-copy table: recorded** (Release, final code, three runs at a
  load of 2.4 to 2.7, `logs/p1_release_timed.log`, *measured*; a first set at a load of 4.7 was repeated).
  One registry check (`mlx_is_live`, with 1,000 further live objects) 9.2, 6.5, 6.8 ns per operand; building
  `c = a + b` without evaluation 2.79, 0.50, 4.13 µs, a wide spread from MLX's side of the call (its three
  operand checks are at most about 5 % of the fastest). `mlx_alloc` was zero-copy at every size, multiples of 16 KiB
  or not: 1,024, 4,096, 16,384, 20,480, 49,152, 100,000, 1,048,576, 1,052,672, 16,777,216, 67,104,768 and
  67,108,864 bytes, in all three runs (the library rounds its buffer up to whole 16 KiB pages, so the pages
  Metal maps are its own).
- **Exit 6, `expect_aborts object_contracts`: met.** Four members, each in a child (`guard=<member>`),
  each stopping with status 86 at its own guard, confirmed from the children's output
  (`logs/p1_debug_object_contracts.log`: `exp: operation on an empty mlx_array`, `exp: stale mlx_array`,
  `mlx_from: called inside an OpenMP parallel region`, `operator(+): float64 is not supported on the GPU`).
  With the OpenMP guard's stop removed the group fails (`guard_openmp_region: command status 0, exit status
  1`, group status 1, `logs/plants_build.log`).
- **Exit 7, the budget: met.** `MLXF_CTEST_BUDGET` 3 (`unit_core`, `unit_array`, `object_contracts`); at 2
  configuration fails (`3 CTest entries do not match the budget of 2`, `logs/plants_build.log`).
- **Exit 8, the static gate: met.** `scripts/check_tree.sh` passes (its only warning names the new,
  untracked sources). `check_rules.py`: the `cbind` and `libc` ledgers are empty; the `state` ledger holds
  `mlxf_registry` (the table), `mlxf_error` (the last error), `mlxf_device` (the initialisation flag) and the
  test library, one reason each; new rules `arity` and `ctorcall` (R4) and, under `reexport`, `mlxf.f90`
  naming no `mlxc_` entity, each failing on a planted violation while a six-dummy `bind(c)` procedure stays
  exempt (`logs/plant_rules.log`). `check_test_registry.py` holds the guard groups to their CTest entries and
  the members to `run_guard`, failing on two plants (`logs/plant_test_registry.log`). Every touched Fortran
  file went through `restyle_fortran.py` and `format_use_blocks.py`.
- **Exit 9, zero compiler warnings: met** in the clean Debug and Release builds (the first Release build
  showed `-Wfunction-elimination` on impure getters inside conditions and a spurious `span ... used
  uninitialized` on allocatable inputs of assumed-rank dummies, both in test code, fixed there).
- **Exit 10, the policy and the skill: met.** `doc/policies/binding_contract_policy.md` (decisions 6 to 18,
  29, 30 and 39 as living rules, the assignment pattern, the unsupported uses, the buffer protocol, the
  float64 list) and `.github/skills/mlxf-binding/SKILL.md`; `CLAUDE.md`, `AGENTS.md`,
  `doc/how2s/how2set_up_dev.md`, the policies' index and the test policy point at them. R4 is recorded in
  decision 39, the policy, the skill `mlxf-modern-fortran`, the register and the history.
- **Independent review** (a read-only reviewer, after the gates first passed) found six defects, all fixed
  and re-gated: `mlx_alloc` with a view of the wrong rank returned status 0 and no view; `mlx_view` and
  `mlx_alloc` left a previously associated pointer associated on failure and had no `rank default`; the
  address of a zero-size array was still taken (`c_loc` before the size test); the 2**31 dimension check read
  default-kind shapes; two internal mlx-c calls of `mlx_to` and `mlx_view` stopped although a `status` was
  passed; and the defined assignment and `kill` did not apply the one-thread guard. New in-process checks
  (`test_checked_failures`, 8 more in `unit_array`) pin the status paths; they were not run against the code
  before the fix, which the run did not keep. The review also found a form the plan does not name: an
  overlapping section assignment of an array of handles, `v(2:3) = v(1:2)`, stops as stale (the compiler's
  temporary is a bitwise copy; no double free; `logs/probe_overlap.log`); the binding policy lists it as
  unsupported. The final clean builds and timings above are of the fixed code.
- **Decisions taken under delegation.**
  1. The generated types are one module, `mlxf_c_types`, and the interfaces one module per header: the
     headers' types form a cycle (`stream.h` uses `vector.h`'s `mlx_vector_stream`, `vector.h` uses
     `mlx_stream`), so per-header type modules cannot compile. Decision 4.1 says one module per header for
     everything; this is the one deviation of the phase. mlx-c's internal `_mlx_<x>` become
     `mlxc_internal_<x>`.
  2. No `mlx_device` type: devices are `MLX_CPU` and `MLX_GPU` (integers equal to mlx-c's), as nothing in
     Phase 1 needs more (decision 29). Device facts are public through `mlx_device_info_size` and
     `mlx_device_info_string`, which the runtime description and the recovery gate need.
  3. The default stream is looked up per operation (the state ledger allows only the initialisation flag in
     `mlxf_device`, so no stream is cached); `mlx_to` copies a strided view into row-major order first
     (`mlx_contiguous`); `a%kind()` returns one of `MLX_DTYPES%...` (a derived-type constant, the skill's rule
     for code families).
  4. `mlx_alloc(shape, mold, view[, status, zero_copy])`: `zero_copy` says whether Metal took the buffer;
     buffers are rounded up to whole pages.
  5. The one-thread guard refuses any OpenMP region level (`omp_get_level() > 0`), so that it also holds in a
     team of one, as CTest runs with `OMP_NUM_THREADS=1`.
  6. Byte identity covers float32 at ranks 0 to 4 and 7, and the other five kinds at ranks 0, 2 and 3
     (float64 on the CPU device only), odd sizes, strided sections in and out, and a zero-size array.
  7. The guard members live in `src/test/mlxf_test_registry.f90` (its `GUARDS` table), the child is
     `mlxf_test_exec guard=<member>`; without a GPU the group is skipped, or fails under `MLXF_REQUIRE_GPU`.
     The registry's cost and the zero-copy table are printed by the testers (measured, not asserted).
  8. The recovery gate is implemented as decision 12 words it, so it allocates half of `max_buffer_length` per
     device (64.9 GB here, 7.5 s of `unit_core`'s 7.8 s); see "left open".
  9. `mlxf_version` lost its scaffold probe (`mlx_gpu_device_count`, replaced by `mlx_device_count`); the
     version tester's GPU query moved to the device tester. `recompile.sh` reconfigures the tree first when
     `MLXF_CMAKE_ARGS` is set.
- **Left open for Hans.** Whether the overlapping section assignment of handles should stay an unsupported,
  diagnosed form (as now) or be made to work (rank-1 specifics that retain every element before releasing
  any); whether operator results inside constructors (`[a*2.0, b]`, unchecked by `ctorcall`) need a check.
  The recovery gate's cost scales with the GPU's maximum buffer length (on a Mac with
  a larger one, the fast gate allocates more); the CI path without a GPU (skips) was not exercised here, as
  this session has one; the three new gfortran reproducers wait for decision 34's upstream report.
- **What it means, in short.** mlx-fortran now has its core: the whole mlx-c API generated and checked
  against an independent list on every build, and an `mlx_array` whose lifetime is exact in every
  supported form and diagnosed in the unsupported ones, on both devices, with data moving byte for byte,
  failed evaluations recoverable, and the contract's stops tested in child processes. A registry check
  costs about 10 ns; Metal took every `mlx_alloc` buffer without a copy. Phase 2 can add the operations of
  the polar pipeline through the two helpers.

### Plan revision, 2026-11-21: production block scorer (interactive; decision 42)

- **Owner request and scope.** Use SIMPLE's production BLAS block scorer as the architecture and benchmark
  reference, with GPU-specific tiling and scheduling; keep the work to this plan. Only
  `doc/implementation_notes/planned/mlxf_design.md` was edited. The existing Phase 1 changes were preserved;
  no implementation phase, SIMPLE build, benchmark or GPU measurement was started.
- **Source check.** SIMPLE's clean tree at `7ec7e29720b3e57c2a56a6a7ab754e6f6c57fe35`, including the
  scorer, reference memo, probability-table callers, memory accounting, block tester, benchmark and driver;
  the production-scoring report was read as recorded Dell evidence. The new Mac baseline remains unmeasured.
- **Applied.** Decision 42, the source findings, ownership table, decision-20 tile/formulation description,
  acceptance and stop rules, Phase 2 baseline refresh and implementation steps, and file table. The 2.0-times
  threshold stays; its comparator becomes `block_prod`. The old `matrix_t` measurements and all prior
  Progress entries remain unchanged as history. Updated end-to-end projections require a current profile.
- **Validation.** Reviewed the revision against a pre-edit copy of this already-dirty plan; checked decision
  numbering, historical records and remaining baseline references. `git --no-optional-locks diff --check --
  doc/implementation_notes/planned/mlxf_design.md` and `scripts/check_tree.sh` passed; the static gate warned
  about the owner's 20 existing untracked source files. No compilation or numerical tests were run for this
  documentation-only revision. Phase 2 remains planned.
