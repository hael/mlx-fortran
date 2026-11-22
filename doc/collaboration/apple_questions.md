# Questions for Apple (MLX and mlx-c)

A running list of questions and reports for the MLX team, collected while building mlx-fortran and porting
SIMPLE's probabilistic table to the GPU. Each item says what we ask, why it matters to us, where we saw it
(MLX `v0.32.4`, mlx-c `v0.8.0` unless noted; MLX head checked on 2026-11-21), and what we do meanwhile. The
text above each "Meanwhile" is written so that it can be sent as it is. Status: **open** until sent, then
**asked** (with the date), then **answered** (with the answer in one line and where it went).

To add an item: give it the next number, keep the four parts, and never renumber.

## Who we are, in one paragraph (for the covering note)

SIMPLE is a cryo-EM single-particle analysis package in modern Fortran (NIH). We are writing mlx-fortran, an
MIT-licensed Fortran interface to MLX built on mlx-c: a binding layer generated from mlx-c's headers at build
time (673 functions), and a Fortran array type whose lifetime the compiler manages through a reference-counted
handle registry. Its first workload is SIMPLE's probabilistic orientation search: per particle and reference, a
complex matrix product per polar angular frequency, an inverse real FFT of length 364, a loss, and a sampled
rotation; at our largest benchmark size, 2,000 particles against 10,000 references. On an M2 Ultra the best CPU
layout does 2.9 million pairs per second on 24 cores; the target machine is an M5 Ultra.

## A. mlx-c packaging and API

1. **`MLXCConfig.cmake` passes the wrong package name.** Status: open.
   - Ask: `MLXCConfig.cmake` calls `find_package_handle_standard_args(MLX_C ...)` inside the package `MLXC`,
     so every project that uses mlx-c gets a CMake developer warning on every configure. Passing `MLXC` as the
     name fixes it. Would you take that one-line change?
   - Where: mlx-c `mlx-c.pc.in` (installed as `share/cmake/MLXC/MLXCConfig.cmake`), last line.
   - Meanwhile: `cmake/Dependencies.cmake` sets `FPHSA_NAME_MISMATCHED` around our `find_package(MLXC)`.

2. **A static `libmlxc` cannot be consumed through the exported config.** Status: open.
   - Ask: `mlxc` links `mlx` privately and the config does not `find_dependency(MLX)`, so a project that
     links a static `libmlxc` through `MLXCConfig.cmake` fails to link. Is the shared library the only
     supported way to consume mlx-c, or would the config add the dependency?
   - Where: mlx-c `CMakeLists.txt` (`target_link_libraries(mlxc PRIVATE mlx)`), `mlx-c.pc.in`.
   - Meanwhile: we require the shared library (Homebrew's bottles qualify).

3. **A machine-readable description of the C API.** Status: open.
   - Ask: mlx-c's headers are themselves generated (`python/generator.py`). For language bindings that
     generate from them (ours, Rust, Common Lisp), a JSON description of each function (name, parameters with
     their roles: result, input array, length of the preceding array, stream) would replace header parsing
     and its guesses about which `int*` is an output and which an input array. Is that something you would
     publish, or is the header the contract?
   - Where: our generator `scripts/gen_mlxc_bindings.py` keeps a mapping table and a skip list; a stray
     `static mlx_array mlx_array_empty;` in `mlx/c/array.h` (one object per translation unit) and functions
     taking `mlx_io_vtable` by value are the cases it has to special-case.
   - Meanwhile: the generator and an independent prototype list, checked against each other on every build.

4. **Stability of the C ABI and the release cadence of mlx-c.** Status: open.
   - Ask: mlx-c 0.8.0 pins MLX v0.32.4; MLX's head was 98 commits past it on 2026-11-20. Which changes to
     mlx-c's headers between minor releases should a binding expect (signatures, enum values, handle
     layouts)? Is there a planned cadence or a compatibility promise?
   - Meanwhile: we pin the pair and regenerate the binding from the headers that are linked.

## B. Devices and runtime

5. **`mlx_metal_is_available` is always true in a Metal build.** Status: open.
   - Ask: `metal::is_available()` returns `true` unconditionally, so it says that the backend was compiled
     in, not that a GPU can be opened. `mlx_device_count(MLX_GPU)` is the real probe. Is that the intended
     reading, and could the documentation (or the function) say so?
   - Where: MLX `mlx/backend/metal/metal.cpp` (`is_available`), `mlx/backend/metal/device_info.cpp`
     (`device_count`).
   - Meanwhile: the library and its tests use `mlx_device_count`.

6. **Without a Metal device, a Metal build cannot allocate even on the CPU device.** Status: open.
   - Ask: in a headless, sandboxed or virtual session (CI runners, some cluster nodes) `load_device` finds no
     device, and since the allocator of a Metal build is Metal's, CPU-device arrays fail too. Is a CPU
     allocator fallback planned, or a supported way to choose it at run time?
   - Where: MLX `mlx/backend/metal/device.cpp` (`load_device`), `mlx/backend/metal/allocator.cpp`.
   - Meanwhile: our tests skip device work when no GPU is open, and fail where a GPU is required.

7. **Errors are reported through a process-global handler.** Status: open.
   - Ask: mlx-c's default handler prints and calls `exit(-1)`; a binding installs its own and checks every
     status. Errors raised during asynchronous evaluation surface at a later call. Is there a recommended way
     to attribute an asynchronous failure to the evaluation that caused it, and is the handler meant to be
     per-thread with the thread-local streams of 0.8.0?
   - Where: mlx-c `mlx/c/error.cpp`.
   - Meanwhile: one submitting thread; checked procedures return a status and keep the last message.

## C. Precision

8. **float64 on the CPU: FFTs still run in single precision.** Status: open.
   - Ask: at v0.32.4 the CPU computed float64 `exp`, `sin` and `cos` through float32 SIMD; your #4789 (on
     head) fixes them. Every FFT still casts its input to float32 or complex64. Is double-precision FFT on the
     CPU planned (complex128 included)? SIMPLE's reference computations and some reconstruction steps need it;
     we would like to keep them on one framework.
   - Where: MLX `mlx/fft.cpp` (`in_type`, `out_type`); head `a8f66b590` for the elementwise functions.
   - Meanwhile: tests hold those operations to float32 tolerances; double-precision paths stay on the CPU in
     Fortran.

9. **Reduced-precision float32 matrix products on the M5's neural accelerators.** Status: open.
   - Ask: with `MLX_ENABLE_TF32` at its default, eligible float32 products take the NAX path at reduced
     precision, and complex64 products never do. (a) What error bound should we expect relative to full
     float32, as a function of the inner dimension? (b) Is a per-call or per-stream precision control
     planned, rather than an environment variable read once (mlx-c has no setter)? (c) Is NAX support for
     complex64 planned, or should a binding express complex products as real ones to reach it?
   - Where: MLX `mlx/backend/metal/matmul.cpp` (`use_nax`), `docs/src/usage/precision.rst`.
   - Meanwhile: correctness is established with `MLX_ENABLE_TF32=0`; the accelerated mode is measured
     separately and must pass the same tests; we benchmark a real-GEMM formulation of our complex product.

## D. Performance of SIMPLE's kernels

10. **Batched complex GEMM at our shapes.** Status: open.
    - Ask: our product is, per angular frequency p (183 of them), a (B x 122) by (122 x R) complex64 product,
      with B up to 2,000 particles and R up to 10,000 references, batched over p. Which layout (batch axis
      first or last, transposes) does the Metal GEMM prefer for complex64 at these sizes, and is a 3M-style
      (three real products) path planned?
    - Meanwhile: we time the native complex product against a packed real product.

11. **Inverse real FFT of length 364, batched by the million.** Status: open.
    - Ask: 364 = 4 x 7 x 13 is a Stockham plan with your radices; we run it on the last, contiguous axis, one row per
      particle-reference pair: up to 5 x 10^6 rows per block, 2 x 10^7 per benchmark case. Is that the shape the Metal FFT is tuned for, and would you expect a
      real matrix product against a fixed 366 x 364 DFT matrix to win at this length?
    - Where: MLX `mlx/backend/metal/fft.cpp` (`supported_radices`).
    - Meanwhile: we benchmark both.

12. **Deterministic scatter-add for reconstruction.** Status: open.
    - Ask: complex64 scatter is supported for `Sum` only, and atomic accumulation order differs from run to
      run. SIMPLE inserts every Fourier component of every particle into a 3D volume with a small window
      (27 to 64 voxels each, many collisions). Is a deterministic scatter-add (sorted, segmented) planned, or
      would you recommend building it from `argsort`, `cumsum` and gathers, or a custom kernel?
    - Where: MLX `mlx/backend/metal/indexing.cpp` (`Scatter::eval_gpu`).
    - Meanwhile: we will measure the three forms.

13. **Graph compilation called from C.** Status: open.
    - Ask: `mlx_compile` takes a closure; our closure calls back into Fortran. What is the per-call overhead
      of a compiled closure on a hot path (thousands of calls per second), and does shapeless compilation
      cover a last partial tile?
    - Meanwhile: we measure compiled against uncompiled.

## E. Memory and threads

14. **Zero-copy wrapping of host memory.** Status: open.
    - Ask: `mlx_array_new_data_managed` wraps a buffer without a copy when Metal accepts it and otherwise
      copies and calls the deleter at once. We found every page-aligned buffer rounded to whole 16 KiB pages
      accepted. Is that the documented condition, and can a buffer be wrapped read-only without page
      alignment (Fortran arrays are not page-aligned)?
    - Where: MLX `mlx/array.cpp` (the raw-pointer constructor), `mlx/backend/metal/allocator.cpp`
      (`make_buffer`).
    - Meanwhile: copying import by default; a page-aligned allocation for arrays filled in place.

15. **Bounding the working set.** Status: open.
    - Ask: over-subscribing unified memory pages rather than failing, and `set_memory_limit` makes evaluation
      wait and release cached buffers. What is the recommended way for an application that shares the
      machine's memory with its own CPU arrays to bound MLX's working set and size its tiles, and what does
      the wired limit buy on an Ultra?
    - Where: MLX `mlx/backend/metal/allocator.cpp`.
    - Meanwhile: tiles sized from `mlx_get_peak_memory` and a budget.

16. **Calling MLX from a program parallelised with OpenMP.** Status: open.
    - Ask: SIMPLE is an OpenMP program. We build and evaluate graphs from one thread and let the other
      threads consume results. With the thread-local streams of mlx-c 0.8.0, is graph construction from
      several threads on different streams supported, and does CPU work on the other cores slow GPU kernels
      through shared memory bandwidth enough to matter?
    - Meanwhile: one submitting thread; overlap is measured.

## F. The collaboration

17. **A home for mlx-fortran.** Status: open.
    - Ask: would the MLX team host mlx-fortran under ml-explore, beside mlx-swift and mlx-c, or review it as
      an independent project? It is MIT, generated from mlx-c, and tested on both devices.

18. **Profiling tools.** Status: open.
    - Ask: which tools do you use to profile MLX on the M5 (Metal System Trace, `mlx_metal_start_capture`
      traces), and is there a way to attribute GPU time to the operations of a graph without Xcode?

## G. FFT defaults across the interfaces

19. **FFT length defaults in mlx-c and the Python `irfft` documentation.** Status: open; observed
    2026-11-22 with mlx-c 0.8.0 / MLX 0.32.4.
    - Ask: should mlx-c offer an optional-length form matching Python's `n=None`, or explicitly document
      that its integer `n` must be a positive resolved length? Passing `n=-1` to `mlx_fft_fft` returns
      "Invalid FFT output size requested (-1)". Python's binding dispatches `None` to the C++ overload
      that infers the extent; there is no documented `-1` sentinel for `n` (the `-1` default is the axis).
    - The published [FFT reference](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.fft.fft.html)
      describes the input extent as its default. The published
      [IRFFT reference](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.fft.irfft.html)
      instead lists `a.shape[axis] // 2 + 1` as the default output length. The local C++ inference in
      `mlx/fft.cpp` computes `2*(extent-1)`, reached by Python's `n=None` branch in `python/src/fft.cpp`.
      Can that IRFFT documentation be corrected?
    - Meanwhile: mlx-fortran resolves omitted lengths before calling C: the input extent for FFT/IFFT/RFFT,
      `2*(extent-1)` for IRFFT, explicit `n` for an odd real output. Independent DFT tests assert those
      conventions on both devices. The original `-1` assumption was our wrapper error, not an MLX defect.

## For information (not Apple's to fix)

- gfortran mis-finalizes derived types in four patterns (allocatable components with defined assignment,
  function results in array constructors, scalar results assigned to whole arrays, self-assignment of types
  with finalizable components); reproducers are in `doc/compiler_issues/`. Any Fortran binding with
  reference-counted handles meets them; our API avoids the patterns, and we report them to GCC.

- A fifth pattern was isolated on 2026-11-22: an allocatable array function result of a finalizable type,
  used as an actual argument, is freed before finalization (AddressSanitizer heap-use-after-free).
  `doc/compiler_issues/gfortran_finalize_allocatable_array_result.f90` (issue 5 of its README) has the
  standalone reproducer and the passing explicit-output subroutine control. The owner approved checked subroutine callbacks for mlx-fortran; no upstream report
  has been filed by this work.
