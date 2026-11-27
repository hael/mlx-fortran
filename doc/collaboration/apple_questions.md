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

20. **float32 `expm1` on the GPU loses accuracy as its argument grows.** Status: open; observed 2026-11-23
    with MLX 0.32.4 and mlx-c 0.8.0 (Homebrew) on an M2 Ultra.
    - Ask: is this known? The Metal kernel's comment claims a largest error of 0.997 ulp, but its error against
      libm's double `expm1` grows with x, while `exp` on the same GPU stays within 1 epsilon. Error relative to
      `max(1, |expm1(x)|)` in float32 epsilons (2^-23), from `scripts/probes/expm1_gpu_probe.c`:

      | x | -10 | -5 | -1 | -0.25 | 0.25 | 0.5 | 1 | 2 | 3 | 5 | 8 | 9.9 |
      | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
      | `expm1`, GPU | 0.16 | 0.50 | 4.42 | 0.02 | 0.12 | 19.56 | 18.80 | 41.46 | 50.31 | 84.40 | 143.70 | 167.90 |
      | `expm1`, CPU | 0.16 | 0.00 | 0.08 | 0.02 | 0.12 | 0.06 | 0.18 | 0.14 | 0.01 | 0.18 | 0.06 | 0.19 |
      | `exp`, GPU | 0.00 | 0.00 | 0.08 | 0.02 | 0.09 | 0.34 | 0.25 | 0.12 | 0.81 | 0.18 | 0.06 | 0.19 |

      Over 1,024 seeded points of [-10, 10], three seeds, the GPU's largest error is 168.2 epsilons and the
      CPU's 0.9. Near 0 the GPU is exact to the last bit, as `expm1` should be.
    - Where: MLX `mlx/backend/metal/kernels/expm1f.h` (`expm1f_scaled_unchecked`, the reconstruction
      `fma(v, t, x) + y` after the double-float canonicalisation `x = (t - y) - s`), reached through `Expm1` in
      `unary_ops.h`. We have not isolated which step loses the bits; a compiler that reassociates the
      canonicalisation would explain an error that grows with 2^i.
    - Meanwhile: mlx-fortran keeps `mlx_expm1` and documents the GPU bound; its GPU test holds a separate
      bound (twice the observed seed-1 maximum), the CPU its ordinary one.

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

## H. Custom Metal kernels and the gathered products through mlx-c

21. **mlx-c's Metal kernel cannot choose the math mode.** Status: open; read 2026-11-24 in mlx-c 0.8.0 and
    MLX 0.32.4, not measured.
    - Ask: `mlx::core::fast::metal_kernel` takes `compile_options` (the math mode: safe, relaxed or fast), and
      `mlx_fast_metal_kernel_new` passes seven arguments and leaves it at its default. Would you take a
      setter on the kernel, or an eighth argument, so that a kernel written through C can opt into the
      relaxed mode as a Python one can?
    - Where: mlx-c `mlx/c/fast.cpp` (`mlx_fast_metal_kernel_new_`); MLX `mlx/fast.h` (`metal_kernel`),
      `docs/src/dev/custom_metal_kernels.rst` ("Math Mode").
    - Meanwhile: mlx-fortran's `mlx_metal_kernel` builds every kernel in the default safe mode; its spec has
      no member for the mode.
    - Measured 2026-11-25 (MLX 0.32.4, the probe of the fused polar tail): the safe mode honours a compensated
      sum (1 and 363 terms of 2^-25 sum to the exact value), `metal::precise::exp` is within one unit of the
      correctly rounded value and plain `exp` 62 units from it. The relaxed mode's effect is not measured.

22. **`segmented_mm` does not check that the inner extents agree.** Status: open; read 2026-11-24 in MLX
    0.32.4 and at head `5c8989446`, not run.
    - Ask: `gather_mm` and `block_masked_mm` refuse operands whose inner extents differ ("Last dimension of
      first input ... must match"); `segmented_mm` checks the two ranks, the segments' last extent and the
      dtypes only, and hands `a` of (M, K) and `b` of (K', N) to the kernels. Is the check missing by
      oversight? A segment's bounds are not checked against K either, which we take as intended.
    - Where: MLX `mlx/ops.cpp` (`segmented_mm`), `mlx/backend/cpu/masked_mm.cpp` (`segmented_mm<T>`).
    - Meanwhile: `mlx_segmented_mm` checks the ranks, the inner extents and the segments' first extent itself
      and stops; the bounds stay unchecked, as every index of the library.

## I. Convolutions and the Hadamard transform

23. **A transposed convolution with a padding above `dilation*(k-1)` returns a shorter result.** Status: open;
    measured 2026-11-25 on MLX 0.32.4, both devices.
    - Ask: `conv_transpose1d` of `[1, 2, 3, 4]` with a kernel of one element `[1]`, stride 2 and padding 1
      returns `[2, 0, 3]` (extent 3). The usual definition, `(W-1)*stride - 2*padding + dilation*(k-1) + 1 +
      output_padding`, gives extent 5 and `[0, 2, 0, 3, 0]`: the full result `[1, 0, 2, 0, 3, 0, 4]` with one
      element taken from each end. With a kernel of 3, stride 2 and padding 3 MLX returns one element where the
      definition gives three. `conv_transpose_general` turns the padding into `padding_lo = dilation*(k-1) -
      padding`, and a negative `padding_lo` makes `conv_general` slice the input before it is dilated, so each
      unit of excess removes `stride` positions instead of one. Is a padding above `dilation*(k-1)` meant to
      be refused, or to follow the definition?
    - Where: MLX `mlx/ops.cpp` (`conv_transpose_general`, the negative-padding branch of `conv_general`).
    - Meanwhile: the wrappers pass the options through, and the binding policy states the extent formula for
      a padding up to `dilation*(k-1)` only. Our tests stay inside that bound.

24. **float64 convolutions and the float64 Hadamard transform build a float64 graph and then do not evaluate
    it as one.** Status: open; measured 2026-11-25 on MLX 0.32.4, CPU.
    - Ask: on float64 operands `conv_general` returns a float64 array. With no dilation of the kernel or of
      the input (and one group beyond one dimension) the CPU evaluates it through the GEMM path in float32
      and casts the result; with a dilation, a flip or groups the slow path refuses it at the evaluation
      ("[Convolution::eval] got unsupported data type."). `hadamard_transform` keeps a float64 dtype and its
      evaluation fails too ("[hadamard] Unsupported type."). Could the operations either refuse float64 when
      the graph is built, or say in their documentation that they are float32 (and float16) operations? A
      float64 result computed in float32 is the case we would most like to see named.
    - Where: MLX `mlx/backend/cpu/conv.cpp` (`explicit_gemm_conv_*`, `dispatch_slow_conv_type`),
      `mlx/backend/cpu/hadamard.cpp`.
    - Meanwhile: the binding policy lists both as float32 operations; our tests run them in float32 on both
      devices.

## J. Three-dimensional real transforms

25. **The GPU's working memory of a padded three-dimensional real transform.** Status: open; measured
    2026-11-25 on MLX 0.32.4, M5 Ultra.
    - Ask: a forward real transform of a float32 cube of n = 256 zero-padded to 512 (`rfftn` with
      `s = (512, 512, 512)`), its inverse (`irfftn`, same lengths) and a slice back to 256 raise the peak
      memory (`get_peak_memory`, reset before) to 5.99e9 B on the GPU and 1.68e9 B on the CPU, where the
      arrays the graph names come to about 1.7e9 B (the padded cube, the 257 x 512 x 512 complex64 spectrum,
      the real result). At n = 160 (padded to 320) the GPU peaks at 1.47e9 B, the CPU at 0.41e9 B. Is the
      GPU's working set of a multi-axis real transform (per-axis passes with transposed copies, we guess) known
      in advance as a multiple of the output, and can it be bounded? The reconstruction's conjugate-gradient
      solve we are porting would hold about 1.1e9 B resident at n = 256 (from the arrays' sizes) and applies
      four such transforms per iteration, so the transform's own working memory decides how many solves fit on
      one machine.
    - Where: MLX `mlx/backend/metal/fft.cpp` (the multi-axis plan of `FFT::eval_gpu`).
    - Meanwhile: the benchmark (`mlxf_test_exec test=bench_recon_pcg suite=transform`) records the peak per
      size and device; budgets are set from the measured peak, not from the arrays' sizes.

## K. Protected updates in a kernel written through mlx-c

26. **Threadgroup memory and atomic float outputs in a kernel written through mlx-c.** Status: open; measured
    2026-11-25 on MLX 0.32.4 and mlx-c 0.8.0, M5 Ultra.
    - Ask: SIMPLE's gridding insertion adds every pixel of a plane, through a 27-point window, to two shared
      grids; planes overlap at every voxel. Through mlx-c we can write the update with `atomic_outputs`
      (`atomic_fetch_add_explicit` on `atomic<float>`), and a `threadgroup` array declared in the kernel's body
      builds and gives correct results (measured below), though MLX writes the kernel's signature and the
      documentation does not mention threadgroup memory. Two questions: (1) is threadgroup memory declared in the
      body supported for kernels built by `metal_kernel` (and is its size limit the device's), so that a block of
      the grid can be accumulated in a fixed order and written once; (2) is there a way, short of a sort, to make
      float atomic additions bit-repeatable (a deterministic mode, or a documented order within a threadgroup)?
      Measured: the atomic kernel inserting 1,000 planes of 20,336 pixels (2.84e8 deposits, 2,341,350 voxels,
      two launches of 500 planes) agrees with a double-precision oracle to the floor single-precision coordinates
      set (1.07e-4 of a voxel's terms where the window's edge weights dominate; the same 1.09e-4 from the
      coordinates alone in double precision) and varies between runs by at most 9.7e-7 of a voxel's terms, but
      1,139,762 of 2,341,350 voxels differ in their bits between two runs (43,169 when all planes share one
      orientation); 0.037 s per launch, against 0.0042 s for the same kernel with plain read-modify-write
      additions, which lose 59 % (seeded orientations) and 98 % (one orientation) of the density's mass. One
      million float atomic additions of 0.1 to one element sum to within 3.5e-6 of the exact value, closer than a
      sequential single-precision sum (9.6e-3).
    - Where: MLX `docs/src/dev/custom_metal_kernels.rst` (atomic outputs, the gradient example);
      `mlx/backend/metal/custom_kernel.cpp` (the generated signature); mlx-c `mlx/c/fast.cpp`.
      Measured 2026-11-26 on MLX 0.32.4, mlx-c 0.8.0, M5 Ultra (`mlxf_test_exec test=bench_kernel_forms
      suite=probe`, source `src/test/bench/mlxf_bench_kernel_forms_src.f90`): a `threadgroup float sh[1024]`
      declared in the body gives exact group sums of small integers with `threadgroup_barrier` for groups of 32,
      64, 256 and 1,024 threads, and wrong sums from 256 threads up without the barriers; `simd_sum`, `simd_min`,
      `simd_prefix_inclusive_sum`, `simd_shuffle` and the attributes `thread_index_in_simdgroup`,
      `simdgroup_index_in_threadgroup` and `threads_per_simdgroup` (32) are exact; a fixed tree on non-integer
      values is bit-repeatable over runs and processes; the largest array that builds is 32,768 B, and 65,536 B is
      refused at evaluation with status 1 and "Threadgroup memory size (65536) exceeds the maximum threadgroup
      memory allowed (32768)". So part (1) holds in practice on this device, with the device's limit; whether
      MLX supports it is still the question. A deterministic alternative to the atomics was measured too: one
      thread per voxel pulling from every plane, its sums equal to the atomic kernel's within the atomics' own
      run-to-run spread, is bit-repeatable but 14.5 times slower at n = 64 and 5.6 times at n = 96.
    - Meanwhile: the probes (`mlxf_test_exec test=bench_insert_probe suite=probe`, `test=bench_kernel_forms
      suite=probe` and `suite=insert`) record the numbers; the insertion's plan (K6) chooses between the atomic
      kernel, `mlx_scatter_add` and a sorted or pulled, deterministic form on its own repeatability gate.

## L. Packaging: the version of mlx-c and a session without a GPU

27. **mlx-c has no run-time query of its own version.** Status: open; read 2026-11-25 in mlx-c 0.8.0.
    - Ask: `mlx_version()` returns MLX's version; nothing returns mlx-c's. A binding generated from mlx-c's
      headers is correct only for the release it was generated from, so a consumer must check it at configure
      time (mlx-fortran's installed package refuses any mlx-c that is not the one it was built with), and a
      program cannot report or check at run time which mlx-c it loaded. Could mlx-c offer `mlx_c_version()` (or
      `MLX_C_VERSION` macros in a header), and could its CMake version file say `SameMinorVersion` while it is
      0.x, so that `find_package(MLXC 0.8)` does not accept 0.9?
    - Where: mlx-c `mlx/c/version.h` (`int mlx_version(mlx_string* str_)`); the installed `MLXCConfigVersion.cmake`
      (`SameMajorVersion`).
    - Meanwhile: `mlxfConfig.cmake` records `MLXC_VERSION` at build time and refuses a different one with
      "mlxf mlx-c mismatch"; `mlxf.pc` carries `mlxc_version`.

28. **A Metal build of MLX cannot allocate on the CPU device when no GPU opens.** Status: open; read 2026-11-25 in
    MLX v0.32.4.
    - Ask: on a Mac where Metal opens no device (a headless or sandboxed session, a virtual machine such as a
      hosted CI runner), a Metal build of MLX fails at the first allocation on either device, the CPU's
      included, because its one allocator is `metal::allocator()`, built on `metal::device(Device::gpu)`. A
      build with `-DMLX_BUILD_METAL=OFF` allocates on the heap and runs the CPU device fine. Could a Metal build
      fall back to the common (heap) allocator when no Metal device can be created, so that the CPU device keeps
      working? Homebrew's bottle is a Metal build, so hosted CI cannot test on the CPU without building MLX from
      source.
    - Where: MLX `mlx/backend/metal/allocator.cpp` (`allocator()`), `mlx/backend/metal/device_info.cpp`
      (`gpu::device_count()` wraps the same call in a `try`), `mlx/backend/no_gpu/allocator.cpp`.
    - Meanwhile: mlx-fortran's tests tell the three sessions apart (`mlx_metal_is_available()` and the GPU
      count); its CI builds MLX v0.32.4 and mlx-c v0.8.0 without Metal (`scripts/build_mlx_deps.sh --cpu-only`,
      cached) and runs the device tests on the CPU there.

## M. Transforms and exported functions

29. **A `FunctionExporter` whose trace failed is read unchecked at its next application; custom rules and empty
    lists.** Status: open; read 2026-11-26 in MLX v0.32.4 (and, for the first item, at head `5c8989446`); the first
    item reproduced with MLX 0.32.4: a second application after a failed one ends in a segmentation fault.
    - Ask: (a) `FunctionExporter::export_function` inserts an empty entry in its table before it traces the
      function and does not remove it when the trace throws (a closure that returns an error, for one); the next
      application with the same number of inputs runs `match()` on that entry and reads `fun.inputs[i]` of an
      empty vector. Could the entry be removed on failure, or the exporter refuse further use? (b)
      `CustomTransforms::vjp` appends the cotangents to what the custom rule returned and indexes the result by
      argument with no check of the rule's count, so a rule that returns fewer arrays than inputs is given a
      cotangent as its product, or reads past the end; a custom jvp that returns more arrays than outputs is
      held by an `assert` only. Could both be checked and thrown? (c) In 0.32.4 `depends` of an empty list of
      inputs and the application of a `custom_function` or `checkpoint` whose function returns no output read
      element 0 of an empty vector; the head scans for a stream instead, so we take these two as fixed.
    - Where: MLX `mlx/export.cpp` (`FunctionExporter::export_function`, `FunctionTable::emplace` and `match`);
      `mlx/primitives.cpp` (`CustomTransforms::vjp`), `mlx/transforms.cpp` (the jvp of a custom function, its
      `assert`; `custom_function`, `checkpoint`); `mlx/ops.cpp` (`depends`).
    - Meanwhile: every copy of an `mlx_function_exporter` refuses another application after a failed one, with a
      status; the trampoline of a custom vjp refuses a rule that does not return one array per input;
      `mlx_depends` stops on an empty list of inputs; the binding policy says that a custom jvp returns at most
      one array per output and that a function given custom rules or a checkpoint returns at least one output.

30. **RoPE on the GPU reads one offset per batch from a rank-1 offset of a single element; the docstring of
    `gated_delta_update`.** Status: open; the first measured 2026-11-26 with MLX 0.32.4 on an M5 Ultra (and read at
    head `5c8989446`, unchanged), the second read.
    - Ask: (a) `fast::rope` accepts an offset array of rank 1 whose size is 1 for an input of several batches, as
      it accepts a rank-0 one. The CPU fallback broadcasts it. The Metal kernel takes `offset.strides()[0]` as the
      stride whenever the offset has a dimension and reads `offset[batch_idx * offset_stride]`, so batches 2 and
      up read past the one element: on a (4, 3, 5) Fortran array (MLX `[5, 3, 4]`) the first batch agrees with the
      rank-0 offset and the other four differ by 0.6 to 0.8. Could the kernel take a stride of 0 for a size of 1,
      or `rope` refuse the shape? (b) The Python docstring of `mx.fast.gated_delta_update` gives the state as
      `[B, T, Hk, Dv]`; the code makes and returns `[B, Hv, Dv, Dk]`. Which is meant? The C++ header gives no
      shapes.
    - Where: MLX `mlx/fast.cpp` (`rope`: the check of `offset`), `mlx/backend/metal/rope.cpp` (`offset_stride`),
      `mlx/backend/metal/kernels/rope.metal`; `python/src/fast.cpp` and `mlx/fast.cpp` (`gated_delta_update`).
    - Meanwhile: `mlx_rope` stops on a rank-1 offset whose extent is not the number of batches (the guard
      `guard_rope_offset`); `mlx_fast_gated_delta_update` is not offered (the parity plan's decision 17).

## N. Files and distributed operations through mlx-c

31. **A save refused for its dtype has already emptied the file; loads and distributed operations take a stream
    they cannot use; the end code of mlx-c's map iterators.** Status: open; (a) and (b) measured 2026-11-26 with
    MLX 0.32.4 and mlx-c 0.8.0 on an M5 Ultra, the distributed half of (b) and (c) read.
    - Ask: (a) `save_safetensors` of a float64 array and `save_gguf` of an int64 array throw ("received invalid
      dtype", "dtype int64 is not supported") after the file was opened for writing: a file of that name is left
      empty (safetensors) or as a header of 24 bytes (GGUF), and what it held is lost. Could the dtypes be
      checked before the file is opened? (b) `mlx_load`, `mlx_load_safetensors` and `mlx_load_gguf` take a stream;
      given the GPU's default stream they return, and the array fails when it is evaluated ("[Load::eval_gpu]
      Not implemented"). `mlx_distributed_all_sum` and its siblings take one too, and their primitives throw
      "has no GPU implementation" in `eval_gpu`. Could mlx-c choose the CPU's stream for these, or the headers
      say that only a CPU stream is valid? (c) `mlx_map_string_to_array_iterator_next` and
      `mlx_map_string_to_string_iterator_next` return 2 when no pair is left and 1 on failure; no header says
      so. Could the convention be documented?
    - Where: MLX `mlx/io/safetensors.cpp`, `mlx/io/gguf.cpp`, `mlx/io/load.cpp`,
      `mlx/backend/metal/distributed.cpp`; mlx-c `mlx/c/io.h`, `mlx/c/distributed.h`, `mlx/c/map.cpp`.
    - Reproduced again 2026-11-26 on the M5 Ultra (`applegpu_g17d`) through mlx-fortran: a 99-byte safetensors
      checkpoint left with 0 bytes after a float64 save to its name, an 80-byte GGUF file left with 24 after an
      int64 save (the user-hardening plan's C2).
    - MLX's main branch has since answered (a): commit `1c141875c` ("Keep the existing file when save,
      save_safetensors or save_gguf fails", 2026-10-29, after 0.32.4) writes every save to `<file>.tmp<random>` and
      replaces the file only after a complete write, keeping its permissions; it follows a symbolic link and replaces
      the file the link names. Before (a) is sent, it is narrowed to asking which release carries it.
    - Meanwhile: since 2026-11-26 the library itself checks the kinds before anything is written and writes every
      array save to a hidden temporary sibling renamed over the destination only when complete (refusing symbolic
      links, hard-linked files and other users' files as destinations), so a failed save leaves the old file;
      the library builds loads and distributed nodes on the CPU's default stream whatever the default device;
      the iterators' end code is the constant `MLXF_MAP_END`.

32. **RoPE's float32 accuracy on the GPU depends on the GPU.** Status: open; measured 2026-11-26 with MLX 0.32.4.
    - Ask: the same rotary embeddings (angles up to 28 radians, offsets and frequencies given or not) are within
      2 float32 epsilons of a float64 reference on the CPU and on an M5 Ultra's GPU, and 14 to 21 epsilons off on
      an M2 Ultra's GPU. Is the kernel's angle and its cosine and sine computed with the fast Metal functions, and
      is an accurate form (or a range reduction before `fast::cos`/`fast::sin`) possible for long positions?
    - Where: MLX `mlx/backend/metal/kernels/rope.metal`.
    - Meanwhile: the tests hold `mlx_rope`'s float32 GPU results to a separate bound (`FAST_GPU_ROPE`, 41.5
      epsilons), the CPU to the floor.

## O. Numerical and index boundaries found by external consumers

33. **Integer mean and variance overflow before producing a floating result.** Status: open, not sent;
    reproduced 2026-11-26 with MLX 0.32.4 / mlx-c 0.8.0 on CPU and Metal GPU (`applegpu_g14d`), including
    direct mlx-c calls without mlx-fortran.
    - Ask: `mean` of int32 `[2000000000, 2000000000]` returns float32 `-147483648`, status 0, and `var`
      returns about `4.61168602e18` instead of zero. A constant 1024×1024 int32 image of 4096 gives mean 0
      and variance 16777216 through the binding. Could integer inputs be promoted before accumulation in
      mean, and before variance/std compute their mean? Converting the inputs to float32 first makes these
      fixtures correct; it does not promise exact conversion of every int64/uint64 value. The direct C
      reproducer (no mlx-fortran) on an M5 Ultra (`applegpu_g17d`), both streams, 2026-11-26: int32, uint32,
      int64 and uint64 inputs are wrong in `mean`, `mean_axis`, `var` and `std` (uint32 `[4e9, 4e9]` mean
      1.85251635e9; int64 `[2^62, 2^62]` mean -4.61168602e18; uint64 `[2^63, 2^63]` mean 0); int8, int16,
      uint8, uint16 and bool constants (up to 65536 elements) are right, and so is every case converted to
      float32 first (the control).
    - Where: MLX `mlx/ops.cpp`, mean/variance reductions; mlx-c `mlx_mean` and `mlx_var`. Direct C
      reproducer and control: `scripts/probes/user_statistics_probe.c` (its output is the finding); the exact
      fixtures and follow-up are retained in
      [the consolidated plan](../implementation_notes/planned/mlxf_user_hardening.md), C1.
    - Meanwhile: since 2026-11-26 the library converts integer and boolean input to float32 before
      `mlx_mean`, `mlx_var` and `mlx_std` (binding policy, section 10); the probe still shows MLX's own result.
    - Checked 2026-11-26 against MLX's main branch (`5c8989446`, 2026-11-23): `mean` still sums in the input's kind
      (`multiply(sum(a, axes), normalizer)` with only the normalizer made floating); the item stands as written. Current upstream issue/release status has not been
      checked by this review; deduplicate and rerun before submission.

34. **Euclidean norms and floating means overflow or underflow internally when the answer is representable.**
    Status: open, not sent; observed 2026-11-26 through mlx-fortran with MLX 0.32.4, both devices for float32
    and the CPU for float64, in Debug and Release.
    - Ask: norm2 of two equal float32 inputs 1e20 gives infinity and of 1e-30 gives zero, with status 0;
      the answers are approximately 1.41421359e20 and 1.41421357e-30. CPU float64 has the analogous result
      at 1e200 and 1e-200. Mean of two float32 values 2e38 is infinity. Is a scaled reduction planned, or
      should the supported input range and intermediate arithmetic be explicit in the operation docs?
    - Where: MLX `mlx/linalg.cpp`'s Euclidean norm and `mlx/ops.cpp`'s mean, reached through
      `mlxf_linalg_matrix` and `mlxf_ops_reduce`. Fixtures and closed-form references:
      [consolidated plan](../implementation_notes/planned/mlxf_user_hardening.md), C5. Direct C reproducer
      and control: `scripts/probes/user_range_probe.c`; on 2026-11-26 on an M5 Ultra (`applegpu_g17d`) it
      shows the same through mlx-c alone, for `linalg_norm_l2` and `linalg_norm` of order 2 on both streams
      (also float32 2e38 and CPU float64 1e308), the mean overflowing at float32 2e38 and CPU float64 1e308 (not
      at 1e20 or 1e200), while the controls (the norm scaled by the largest magnitude, the mean as a sum of
      halves) are within 8 epsilons in every case. It also shows `max` and `min` over an axis of extent 0
      refused ("Cannot max reduce over axis 1 with size 0"), which is MLX's documented behaviour and the
      library's to map to Fortran's identities, not a request.
    - Meanwhile: since 2026-11-26 the library scales `norm2` and the floating `mlx_mean` by the largest magnitude
      itself (binding policy, section 10); the probe still shows MLX's own result. Check current upstream status
      before filing.
    - Checked 2026-11-26 against MLX's main branch (`5c8989446`): the Euclidean norm is still
      `sqrt(sum(square(a)))` in `mlx/linalg.cpp`; the item stands as written.

35. **Unchecked indices can crash on CPU or return plausible zeros on GPU without an error.** Status: open,
    not sent; reproduced 2026-11-26 with MLX 0.32.4 / mlx-c 0.8.0 through mlx-fortran.
    - Ask: after the binding's one-based shift, `take` on five values with MLX index 5 returns zero/status
      0, and with MLX index 999999 crashes on CPU but returns zero/status 0 on GPU. Could the API document
      out-of-range access explicitly, including backend-dependent behavior, and is opt-in checked indexing
      planned? This is a request for a defined checked path, not a claim that unchecked indexing promises
      bounds validation. Negative-index wrapping is a separate convention.
    - Where: `mlx_take`, reached from the `p11_take_each.f90` probe in
      `~/for_claude/mlxf_user_review_2026-11-26/`; repeated against a fresh install by Codex. The consolidated
      plan's C3 preserves the exact fixtures and proposes explicit boundary validation. Repeated 2026-11-26 on an
      M5 Ultra, four processes per index: the GPU returns 0 with status 0 for every out-of-range index (MLX
      indices 5 to 99999999, and -6); the CPU returns 0 for MLX indices 5 to 9999, while 999999 returned
      8.9e11 in three runs and ended the process (SIGSEGV) in one, -6 ended it (SIGBUS) in three of four, and
      99999999 ended it in all four. The out-of-range read is not deterministic on the CPU.
    - Meanwhile: since 2026-11-26 the library offers an explicit check, `mlx_check_indices` (element indices and
      slab starts against caller-supplied extents, a status, one evaluation), that callers run on untrusted
      indices; the lazy operations stay unchecked. Check current upstream reports first.
    - Checked 2026-11-26 against MLX's main branch (`5c8989446`): the CPU and Metal indexing backends gained no bounds
      check since 0.32.4 (their changes concern empty outputs and 64-bit offsets); the item stands as written.

36. **Is `argpartition` (and `argsort`) stable on the GPU, and may we rely on it?** Status: open, not sent;
    measured 2026-11-26 with MLX 0.32.4 / mlx-c 0.8.0 on an M5 Ultra.
    - Ask: selecting the K largest of each column of a 10,000 by 1,024 float32 table with `argpartition` at
      the K-th position (K = 3 and 10), with 11 to 13 columns per case given a second element equal to the first
      maximum and one equal to the K-th value, the K kept always included the lower index of the tied pair, as
      a stable selection would, in every one of 12 cases (3 seeds, 2 values of K, 2 processes). The
      documentation says nothing of the order among equal keys. Is the lower index on ties guaranteed for
      `argpartition` and `argsort` on the GPU (and the CPU), or an artefact of the current kernel? If it is
      guaranteed, the repair pass we run at the boundary (a running count of the equal values in index order)
      can go.
    - Where: MLX `mlx/ops.cpp` (`argpartition`, `argsort`) and the Metal sort kernels; reached through
      `mlx_argpartition` in `src/core/ops/mlxf_ops_sort.f90`; the test is
      `mlxf_test_exec test=bench_kernel_forms suite=select` (form `e1n`), source
      `src/test/bench/mlxf_bench_kernel_forms.f90`.
    - Meanwhile: the binding contract keeps "no stability" (section 10), and every selection that needs the
      first-maximum rule repairs the boundary's ties or uses a kernel with strict comparison.

37. **The first GPU device-count query leaves the host overflow flag set.** Status: open, not sent;
    reproduced 2026-11-26 through mlx-c alone on an M2 Ultra (`applegpu_g14d`), macOS 26.7.3,
    MLX 0.32.4 / mlx-c 0.8.0, with `MLX_ENABLE_TF32=0`.
    - Ask: after `feclearexcept(FE_ALL_EXCEPT)`, `mlx_metal_is_available` returns true/status 0 without
      `FE_OVERFLOW`. After another clear, the first `mlx_device_count(&n, MLX_GPU)` returns 1/status 0
      but sets `FE_OVERFLOW`; after clearing again, the second count returns the same result without
      setting it. Can device initialization preserve the caller's floating-point environment, and is
      this expected in MLX or a Metal initialization dependency? The exact lower-level cause is not yet
      isolated; this is independent of mlx-fortran's numerical operations.
    - Where: first GPU discovery through `mlx_device_count`. A C-only probe and its output are retained
      in `~/m2_evidence/overflow_investigation/device_fenv.c` and `device_fenv.log`, with the compile
      command in `README.txt`. A temporary instrumented copy of `bench_user_costs` samples and clears
      the calling thread's overflow flag between stages: only `test_devices` sets it; the later CPU
      and GPU benchmark stages do not set it again. These instrumented timings are diagnostic only.
    - Meanwhile: distinguish this initialization flag from numerical overflow in a measured operation.
      Do not suppress all floating-point diagnostics or clear a caller's pre-existing flags. No runtime
      workaround was added. Reproduce on other configurations and check upstream reports before filing.

## P. Linux (CPU-only MLX, GCC)

38. **`mlx/c/array.h` defines an unused static variable, which GCC reports in every C file that includes
    `mlx/c/mlx.h`.** Status: open, not sent; seen 2026-11-26 with mlx-c 0.8.0 built CPU-only on Ubuntu 26.04 with
    GCC 15.2.
    - Ask: `array.h` line 42 reads `static mlx_array mlx_array_empty;`, and nothing in mlx-c's headers refers to
      it. GCC's `-Wall` (`-Wunused-variable`) warns "'mlx_array_empty' defined but not used" in every translation
      unit that includes `mlx/c/mlx.h` and does not use it, so a C consumer built with `-Wall -Werror` fails on a
      file that only includes the header. Apple's clang compiles the same header under `-Wall -Wextra -Werror`
      without it (mlx-fortran's macOS builds do so on every build), so the failure appears with GCC, on Linux.
      Could the variable go, or become a function (`mlx_array_new()` already returns an empty array), or be marked
      `__attribute__((unused))`?
    - Where: mlx-c `mlx/c/array.h:42`. Reproducer: a C file holding `#include "mlx/c/mlx.h"` and an empty `main`,
      compiled with `gcc -std=c11 -Wall -Werror -I<prefix>/include -c`: error, exit 1 (without `-Werror`: one
      warning).
    - Meanwhile: our ABI probe, the one C file of mlx-fortran that includes mlx-c's headers, reads them as system
      headers off Apple (`-isystem`, `test/CMakeLists.txt`), so the header's warning is mlx-c's and the probe's own
      code keeps `-Werror`.

39. **`gather_mm`'s fast sorted route serves one row of the left operand only: is a grouped route for larger
    left operands planned?** Status: open, not sent; seen 2026-11-27 with MLX 0.32.4 on the M5 Ultra (run
    `mlxf_kernel_k3`).
    - Ask: `GatherMM::eval_gpu` takes the sorted route (`gather_mm_rhs`) only when the left operand has one row
      and only the right list is given; one row or one column otherwise takes the matrix-vector route, and the wide
      route `gemv_wide_config` gives only to float16 and bfloat16 outputs. Every other shape takes the generic
      route, which looks every matrix up by its index and reads `sorted_indices` not at all. A product whose left
      operand is a tile of particles (16 to 64 rows) against reference tiles chosen per bin cannot use the sorted
      route. Measured: the sorted route ran at 4 times the unsorted (matrix-vector) one and equalled `matmul` bit for
      bit, but per listed pair it reached 0.40 times a plain `matmul` of gathered tiles. Is a sorted route for a
      left operand of several rows (grouped GEMM over runs of equal right indices) planned, and for float32?
    - Where: `mlx/backend/metal/matmul.cpp`, `GatherMM::eval_gpu` (at `v0.32.4`). Reproducer: the run's scratch
      probe of the four layouts (its report names it), not kept in the repository.
    - Meanwhile: the toy gathers the listed references with `mlx_gather` into tiles of the dense graph, and a
      custom kernel (a SIMD group per pair and bin) scores sparse lists.

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
