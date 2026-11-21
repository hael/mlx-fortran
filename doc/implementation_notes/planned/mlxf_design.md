# mlx-fortran: a small Fortran array library, driven by SIMPLE's pipelines

Status, 2026-11-20: planned; Phases 0 and 1 authorised as an unattended run on the M2 Ultra (decision 35).
Fourth revision of the day: after an independent review (6 P1, 15 P2), after Hans's rulings 26 to 28, after
Hans's design review (the layering, the pipeline-first milestone, precision modes, the ownership hole, the
buffer protocol, graph compilation, recoverable errors, equivalent work), and after the import of SIMPLE's and
XEMA's house rules (`doc/architecture_principles.md`, rulings 35 to 37). Base:
the scaffold's first commit, made by Hans before launch (a launch precondition, section 8), SIMPLE
`5709265cb`, MLX `v0.32.4` (`36969c09`), mlx-c `v0.8.0` (`a26f2d58`). Supersedes: none. Depends on: mlx-c
0.8.0 as a shared library (validated: yes, Homebrew bottles on the M2 Ultra, pre-launch checks); the scaffold's
build and gate (validated: yes, Debug and Release on the M2 Ultra); SIMPLE's `polar_matching_bench`
(validated: yes, M3 Pro, 2026-10-21, before the full-row draw; re-measured in Phase 0).

## 1. Why

SIMPLE's collaboration with Apple ports SIMPLE to the unified-memory Macs through MLX. SIMPLE is Fortran and
MLX has no Fortran interface; Swift, Rust, R and Common Lisp bind its C API, mlx-c. Probabilistic scoring is
about 60 % of SIMPLE's wall time in Hans's benchmarks (decision 28), and the dense table's Euclidean scoring
is arithmetic-bound on the Mac: on an M3 Pro the production per-pair routine scored 3.55e5 particle-reference
pairs per second at 11 threads and the best CPU layout (`matrix_t`: one complex matrix product per angular
bin, then a batched inverse real FFT) 1.32e6 (SIMPLE,
`doc/implementation_notes/completed/polar_matching_layout_bench_report.md`). That is a batched complex GEMM
followed by a batched inverse FFT, the work a GPU does best. This plan builds a small, general Fortran array
library on MLX whose public API grows as SIMPLE's complete pipelines need it, and proves it on the first one:
the tiled polar table fill, from memoised spectra to the table entries, against independent references and
with measured peak memory.

## 2. Contract

### Layers

| Layer | Owns |
| --- | --- |
| SIMPLE integration (a later SIMPLE plan) | particle batches, reference caches held by SIMPLE's builders, reconstruction policy, scientific tolerances |
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
     on handle types, and array intrinsics on arrays of handles, are unsupported.
   - A declared, never-assigned `mlx_array` is empty: `kill` and `final` skip it, every operation refuses it.
     Every function nulls its result on entry. The registry's live count is the leak gate's counter.
   - **Gate (exact).** After a warm-up iteration, with `mlx_synchronize` and `mlx_clear_cache` before both
     reads, `mlx_get_active_memory` and the registry's live count after the loop equal their values before,
     on each device; no stale release is counted; no case crashes in the Debug build. The loop (10,000
     iterations) holds `c = exp(a*2.0 + b)` with `mlx_eval(c)`, self-assignment, `b = (a)`, an array
     constructor of function results passed on, function results as actual arguments, `intent(out)` dummies,
     rank-1 and rank-3 arrays of handles (allocated, then assigned and reassigned), a plain scalar and array
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
20. (revised 2026-11-20) **SIMPLE's first pipeline: the polar table fill.** For particles i of one half h with
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

    This restates `gen_posterior_val` and `draw_posterior_row` at `5709265cb` (unshifted kernel; the seeded
    bank is the same kernel on shifted particle arrays). The variates come from the caller (SIMPLE's keyed
    generator after integration; a fixed-seed generator here) as float32. The draw runs on the device: the
    table needs one entry of 8 bytes per pair (160 MB for 2,000 particles against 10,000 references), while
    full rows would be 1,456 bytes per pair and the 20 lowest are no longer what SIMPLE draws from. A
    scoring-only mode returns the full rows d (fixture and accuracy block only) for the oracle comparisons.

    Tiling: reference tiles of R_t stay on the device across particle blocks of B (the caller owns them); the
    entries of each block and tile are copied out and consumed before the next; the benchmark sweeps
    B in {250, 500, 1,000, 2,000} and R_t in {250, 500, 1,000, 2,500} and records each configuration's
    `mlx_peak_memory`, keeping it under a quarter of the machine's memory (*guessed* budget). Formulations:
    - **A**: complex64 `matmul` per bin over a bin-major reference copy (2 nk, R_t, P), a permute to bins
      first, `mlx_irfft`, the distances and the draw;
    - **B**: the complex product as one real float32 GEMM per bin (particle side packed (Re, Im) along the
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
    `src/core/mlxf_libc.f90`.
25. (2026-11-20, default) Kernel code that is SIMPLE's (decisions 20 to 22) is test code in `src/test/`, written
    against `mlxf` as a user's code is; it compiles into `mlxf_test_exec` only, its modules go to
    `build/modules_test`, it is never installed, and it is the starting point SIMPLE's integration plan copies.
26. (2026-11-20, Hans) The polar verdict's go threshold is 2.0 times SIMPLE's `matrix_t` (section 6).
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
29. (2026-11-20, Hans's review) **The public API grows by demonstrated need.** A public procedure enters when a
    pipeline step of this plan uses it, or when it is the sibling a test of such a step needs (for example
    `cumsum` for the draw, `sum` to test it). Each phase's list below is that need; nothing else is wrapped by
    hand, however easy the generated layer makes it.
30. (2026-11-20, Hans's review) **Graph compilation, without transforms.** `mlx_function` wraps a Fortran
    function of arrays as an mlx-c closure (a `bind(c)` trampoline and a payload holding a procedure
    pointer; the trampoline never stops, it returns a status) and `mlx_compile(f, shapeless)` compiles it.
    Shapeless compilation, or padded tiles, keep the last partial tile from recompiling. Compilation fuses
    the elementwise tail; matrix products and FFTs stay MLX's kernels. No `grad`, `vjp` or `vmap`.
31. (2026-11-20, Hans's review) **The verdict compares equivalent completed work**: the table entries
    (d(irot), irot) of every pair with SIMPLE's draw semantics, on the GPU and in SIMPLE's `matrix_t`, which at
    the base also draws over the full row. Scoring alone (sums, inverse transform, distances) is reported
    beside it for both, and so are preparation, the copy-out, and the overlap with CPU consumption.
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

Decision 20, formulation A, for one particle block and one reference tile, as SIMPLE would write it after
integration: the design check of decisions 5 to 11 and 29. `ft_ref`, `ft_ref2` (P, nk, R_t) and `ft_ctf2`,
`ft_ptcl_ctf` (P, nk, B) are SIMPLE's memo arrays of one half, `wk(nk)` the shell weights, `wsq(B)` and
`temp(B)` the particles' self-terms and temperatures, `u(B, R_t)` the variates:

```fortran
use mlxf
type(mlx_array)           :: rbin, pbin, w, c, d, wt, cs, tgt, irot, dsel
real(real32), allocatable :: dist(:,:)
integer,      allocatable :: rot(:,:)
! the reference tile, built once and kept on the device across particle blocks: bin-major (2nk, R_t, P)
rbin = mlx_permute(mlx_concatenate([mlx_from(ft_ref2), conjg(mlx_from(ft_ref))], dim=2), [2, 3, 1])
! a particle block with its half's shell weights, bin-major (2nk, B, P)
w    = reshape(mlx_from(wk), [1, nk, 1])
pbin = mlx_permute(mlx_concatenate([w*mlx_from(ft_ctf2), -2.0*w*mlx_from(ft_ptcl_ctf)], dim=2), [2, 3, 1])
c    = matmul(transpose(pbin), rbin)                                  ! per bin (B,2nk) x (2nk,R_t): (B, R_t, P)
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
caller's (layer table). Phase 2's operation list is exactly what this and formulations B and C use.

## 4. Not in this plan

- **Any change to SIMPLE.** Its integration (a `USE_MLX` option, reference tiles owned by SIMPLE's builders, a
  device path for the table fill) is a SIMPLE plan written after milestone 1 (decision 32).
- Transforms (`grad`, `vjp`, `jvp`, `value_and_grad`, `vmap`), neural-network layers and optimisers: a later
  plan, for SIMPLE's `learn/` students. Graph compilation is in (decision 30).
- CUDA and Linux backends; `mlx_distributed_*`; IO; graph export and import; float16 and bfloat16; quantised
  operations; the machine-learning `mlx_fast_*` kernels other than `metal_kernel`; explicit streams.
- flang and other compilers; Windows; hosting, releases and package managers.
- SIMPLE's shifted-reference kernel and its polar shift maps (`simple_polar_shiftmap`, work in flight there).
- Out of bounds: `~/src/mlx`, `~/src/mlx-c` and `~/src/SIMPLE` (read only; exports in scratch).
- No other run edits this repository while this plan runs; the base stays the launch commit.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement only | toolchain and dependencies recorded, scaffold gate in Debug and Release, GPU visible to the run, SIMPLE baselines twice |
| 1 | new code: the handle model and the core | `unit_core`, `unit_array` on both devices; the leak and diagnosis gates; recovery gate; generator coverage; fast gate in Debug and Release |
| 2 | new code: the polar pipeline (milestone 1) | `unit_ops`, `unit_linalg`, `unit_fft`, `unit_compile`, `unit_kernels suite=polar_table` on both devices with frozen tolerances; the verdict on the M5 Ultra |
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
- **Accelerated mode** (M5 Ultra): the same frozen gates; the report gives its errors and whether it passed.
- **Peak memory.** Every benchmark configuration's `mlx_peak_memory` is recorded; the verdict's configuration
  stays under the budget of decision 20.
- **The polar verdict** (pre-registered; on the M5 Ultra against the Phase 0 baseline re-measured there).
  Throughput in pairs per second for 2,500 directions times 4 states (10,000 references) against 2,000
  particles of one half: the table entries of every pair (decision 31), references resident, including each
  particle block's upload and the copy of the entries into Fortran arrays; the best (B, R_t) and the fastest
  formulation that passes the frozen gates in full precision; best of 3 after a warm-up, with the A-A spread.
  Against SIMPLE's `matrix_t` at all cores on the same case:
  - at least 2.0 times (decision 26): **go**; the report recommends SIMPLE's integration plan for the fill;
  - at least 1.0 and below 2.0 times: **lead**; the report gives the profile and Hans rules;
  - below 1.0 times: **negative**; the report gives the profile and the mechanism.

  Reported beside it: scoring alone (GPU stages from the profile mode; SIMPLE's sums and inverse-FFT thread µs
  from the benchmark's part timings; SIMPLE's distances are timed together with its draw, so its scoring-only
  number is a lower bound); the accelerated mode; the M2 Ultra's numbers; the overlap measurement; and the
  end-to-end gain of decision 28, 1 / (1 - 0.6 f + 0.6 f / g), for the measured g and the recorded f, or as a
  function of f (at f = 1 it is 1.43 at g = 2, 1.82 at g = 4 and at most 2.5; at f = 0.5, 1.18, 1.29 and at
  most 1.43).
- **Overlap** (reported): with block n+1 submitted asynchronously, the fraction of a CPU workload as long as one
  GPU block that is hidden; and the GPU's slowdown under a concurrent CPU memory-streaming load.
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
- SIMPLE's base does not build or `polar_matching_bench` fails (Phase 0);
- GFortran cannot carry a decision beyond the bug already known: a leak or double free in a case the leak gate
  covers; the registry failing to turn the bypass into a diagnosis; `bind(c)` value structs passed wrongly;
  `c_loc` of an assumed-rank array refused; a Phase 1 probe failing. Stop with a reproducer and alternatives;
- MLX contradicts a decision (an operation missing for complex64 or float32 on the GPU; `irfft`'s
  normalisation not as decision 20 states; a compiled closure that cannot call back into Fortran);
- a tolerance, floor or threshold would have to move; a file outside the table needs an edit;
- the M5 Ultra is not available when Phase 2 reaches its verdict (record the M2 Ultra's results and stop).

Gates no ruling may waive: the leak, diagnosis and recovery gates; byte identity of data movement; generator
coverage; the oracle comparisons on both devices; the frozen tolerances.

## 8. Phases

**Launch precondition.** Hans has committed the scaffold; that commit is the base. No commit: stop.

### Phase 0, the baseline

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
   the M2 Ultra and again on the M5 Ultra (decision 27).
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
4. The pipeline in `src/test/mlxf_kernel_polar_table.f90`: formulations A, B and C, compiled and not, over
   blocks and tiles; the fixture with its ring oracle and the double-precision draw check; the
   production-size generator with its DFT-matrix oracle. Tester `unit_kernels suite=polar_table` (fixture
   only). Benchmark `bench_polar_table` in `src/test/mlxf_bench_polar_table.f90`, modes `time` (the four cases
   1,000 or 2,500 directions times 1 or 4 states against 2,000 particles, the (B, R_t) sweep with peak memory,
   every formulation), `profile` (an evaluation barrier after each stage, reported apart), `accuracy` (the
   block against its oracle), `overlap` (decision 16 and section 6).
5. Phase 2a: the calibration of section 6 on the CPU device, then the frozen tolerances, in a Progress entry.
   Until that entry exists the `kernels` area is not in `MLXF_TEST_AREAS` and runs only with `device=cpu`.
6. Add `kernels` to the CTest areas (with `ops`, `linalg`, `fft` and `compile`, `MLXF_CTEST_BUDGET` 8,
   decision 37); GPU runs of the tester and the accuracy block (seed 2) on the M2 Ultra; the benchmark on the
   M2 Ultra.
7. On the M5 Ultra: Phase 0 steps 1, 2, 4 and 5 there, the gates, the benchmark in both precision modes, the
   verdict.
8. The interim summary for ruling 32 in Progress: what milestone 1 proved, the verdict and its branch, peak
   memory, the formulation, what SIMPLE's integration would take. Hold.

Exit: the unit suites pass on both devices in Debug and Release on both Macs; the Phase 2a entry precedes the
first GPU run of `polar_table`; `polar_table` and the accuracy block pass on the GPU with the frozen tolerances
for every formulation counted; the benchmark rows with peak memory and precision mode are kept; the verdict is
recorded with its branch; the interim summary exists.

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
| `src/core/mlxf_libc.f90` | libc entry points | 1 |
| `src/core/mlxf_error.f90` | errors, recovery, `MLXF_HARD_ERROR_STATUS`, the one-thread guard | 1 |
| `src/core/mlxf_registry.f90` | live handles, counts, serials | 1 |
| `src/core/mlxf_device.f90` | devices, initialisation | 1, 2 |
| `src/core/core.inf`, `src/test/test.inf`, `test/test.inf` | if needed | each |
| `src/core/mlxf_memory.f90` | memory controls | 1 |
| `src/core/mlxf_array.f90` | the array type, data in and out, evaluation | 1, 2 |
| `src/core/mlxf_version.f90` | moves to the generated layer; runtime description | 1 |
| `src/core/mlxf.f90` | the re-export module | 1, 2, 3, 4 |
| `src/core/mlxf_ops.f90`, `src/core/mlxf_ops_*.f90` | operations (submodules) | 2, 4 |
| `src/core/mlxf_linalg.f90` | `matmul` | 2 |
| `src/core/mlxf_fft.f90` | FFTs | 2, 3 |
| `src/core/mlxf_compile.f90` | `mlx_function`, `mlx_compile` | 2 |
| `src/core/mlxf_kernel.f90` | Metal kernels | 4 |
| `src/test/mlxf_test_registry.f90` | areas, benchmarks | 1, 2, 3, 4 |
| `src/test/mlxf_test_utils.f90` | `bits_equal`, assertions for complex values and arrays | 1, 2 |
| `src/test/mlxf_kernel_polar_table.f90` | the first pipeline, its fixtures and oracles | 2 |
| `src/test/mlxf_bench_polar_table.f90` | its benchmark | 2 |
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
| `doc/history/2026-11.md`, `doc/history/2026-12.md` | owner decisions applied, batches delivered | each |
| `doc/implementation_notes/planned/mlxf_design.md` | Progress | each |
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
