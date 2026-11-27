# Report of run `mlxf_linux`: Linux, CPU only, on dell2, and the inventory for CUDA (roadmap rank 2h)

Plan: [`mlxf_linux.md`](../planned/mlxf_linux.md) (its Progress holds the detail, phase by phase). Run on dell2
(Ubuntu 26.04.1, kernel 7.0, Intel Core Ultra 7 366H, 16 CPUs, 61 GB, no GPU), 2026-11-26, 22:39 to 23:48 EST,
unattended, from base `0f8252b` (the plan's commit), in a copy of the checkout; nothing committed. No ruling. GCC and
GNU Fortran 15.2, CMake 4.2.3, MLX 0.32.4 and mlx-c 0.8.0 built CPU-only by the run. Evidence paths are under
`/home/hael/agent_runs/mlxf_linux/scratch/keep/phaseN/`; the diffs are the run's `review/phase_N.diff`.

## What was learned

1. **mlx-fortran runs on Linux.** MLX 0.32.4 and mlx-c 0.8.0 build CPU-only on Ubuntu 26.04 with GCC 15.2 and the
   system's OpenBLAS 0.3.32 in 92 s on 16 cores; the library and `mlxf_test_exec` build in Debug and Release with
   `MLXF_WERROR=ON` and no warning; the whole suite passes on the CPU device, 4,411 checks and 33 guard members per
   build, identical in Debug and Release, plus the four named-only sub-suites (MLX's ring backend between two
   processes included). The only skips are the five GPU-only checks a CPU-only MLX skips on any system; no test
   needed a Linux-only skip, and no MLX CPU kernel behaved differently from what the tests expect.
2. **One real bug, two build breaks and one check.** `mlxf_libc` read macOS's `struct stat` at fixed offsets, which
   on glibc are the device number and the link count: a save over an existing file was refused, and `unit_io` failed
   and crashed. mlx-c's `array.h` defines an unused static, which GCC turns into an error in the `-Werror` ABI probe
   (Apple question 38). GNU Fortran 15 on Linux gives a private separate module procedure whose body is in its
   module internal linkage, so the reconstructor's tester did not link, and the static gate's linkage check had
   said that form was safe. `check_embed.sh` matched a message whose quotes GCC writes differently on Linux.
3. **GNU Fortran 14 is fine on Linux.** 14.3 (Ubuntu's package, unpacked into scratch) builds the whole tree and
   passes every CI step in both build types, unlike 14.4 on macOS.
4. **MLX takes two things from the system at run time:** `g++`, with which it compiles the CPU kernels of compiled
   graphs and caches them under `TMPDIR` (on every system but Windows; a Mac's comes with the Command Line Tools),
   and, where Open MPI is installed, Open MPI itself, which `unit_distributed` starts (an MPI singleton writing
   under `TMPDIR`).
5. **The run could not clone.** arun's fence refuses `git clone`; the pinned tags came as GitHub's archives, checked
   against the tags' commits, and the Linux branch of `build_mlx_deps.sh` accepts them.
6. **The CUDA step** (section "The CUDA inventory" below) meets: every custom Metal kernel, each needing a CUDA
   source through mlx-c's CUDA kernel API or its graph form; the tests' GPU classification, which knows Metal only;
   MLX's CUDA backend's own requirements (toolkit, driver, cuDNN, the native architecture).

## The CUDA inventory (decisions 8 and 10)

What the CUDA step (the roadmap's rank 5) meets, read from this tree and from MLX 0.32.4's and mlx-c 0.8.0's
sources (the tag archives in `scratch/keep/src/`; MLX paths below are relative to its source). It is the input
of the CUDA plan; nothing of it was built or run on a GPU here.

### A. What a Blackwell machine needs (MLX's CUDA backend)

- **Build:** `-DMLX_BUILD_CUDA=ON` (default OFF, `CMakeLists.txt:38`); the CUDA toolkit 12.0 or newer, **13.1
  refused** by MLX's configure (`CMakeLists.txt:159-168`), and cuDNN (`find_package(CUDNN REQUIRED)`; Ubuntu:
  `libcudnn9-dev-cuda-12`, `docs/src/install.rst:258-285`); NVIDIA driver 550.54.14 or newer (580 for CUDA 13),
  glibc 2.35 or newer (`install.rst:35-59`); BLAS, LAPACK and LAPACKE as for the CPU build. MLX's configure
  downloads CCCL 3.1.3, NVTX 3.1.1, cudnn-frontend 1.16.0 and CUTLASS 4.4.2 (`mlx/backend/cuda/CMakeLists.txt:260-324`).
- **Architecture:** MLX compiles for the native GPU (CMake's `__nvcc_device_query`) and appends `a` from 9.0 up
  (`mlx/backend/cuda/CMakeLists.txt:169-186`): a Blackwell B200 is `100a`, an RTX-class Blackwell `120a`; set
  `MLX_CUDA_ARCHITECTURES` to build on a machine whose GPU is not the target. Code for an `a` target runs on that
  architecture only, and `sm_100`/`sm_120` need toolkit 12.8 or newer (*literature*: NVIDIA's, not MLX's source);
  MLX's own wheels list `90a`, `100a`, `120a` and `121a` (`setup.py:122-136`).
- **`scripts/build_mlx_deps.sh`** needs a CUDA mode beside the CPU-only one (`-DMLX_BUILD_CUDA=ON`, the
  architecture recorded in `mlxf_deps.txt`); at run time `libmlx.so` needs the CUDA runtime, cuBLAS and cuDNN on
  the loader's path (`cmake/Dependencies.cmake` names only mlx-c's directory).
- **mlx-c** builds unchanged on top; it exposes `mlx_cuda_is_available` (`mlx/c/cuda.h:31`) and the CUDA kernel
  API (`mlx/c/fast.h:40-97`).
- **At run time** MLX compiles gathers, scatters, slices, compiled graphs and custom kernels with NVRTC: it needs
  the CUDA headers (`CUDA_HOME`, `CUDA_PATH` or `/usr/local/cuda`) and CCCL beside `libmlx.so`
  (`<prefix>/include/cccl`, which MLX installs), and caches PTX under `TMPDIR` (`MLX_PTX_CACHE_DIR`;
  `mlx/backend/cuda/jit_module.cpp:66-119`). Launches are recorded into CUDA graphs and committed in batches
  (`MLX_USE_CUDA_GRAPHS`, default 1): a kernel's launch error appears at evaluation, not where the operation was
  built (`mlx/backend/cuda/device.cpp:180-258`, `event.cu:333-346`). The memory limit defaults to 95 % of the
  GPU's memory and is soft (`allocator.cpp:153-197`).
- **A Grace (aarch64) host:** 64 KiB pages (the zero-copy input assumes 16 KiB, section D) and the 16-bit `mode_t`
  of `c_chmod`/`c_mkdir` (section E) are the two ABI points to check there; everything else built here is
  architecture-neutral Fortran and C.

### B. The custom kernels: the wrapper and every kernel

**The wrapper.** `mlx_metal_kernel` (`src/core/fast/mlxf_fast.f90:40-56, 236-492`) is built from the record
`mlx_metal_kernel_spec` (`src/defs/mlxf_defs.f90:230-246`: name, source, header, input and output names, `grid` and
`threadgroup`, output shapes, ranks and dtypes, templates, `init_value`, `ensure_row_contiguous`,
`atomic_outputs`, `verbose`) and applied on the GPU's default stream; the contract is
`binding_contract_policy.md` section 12. mlx-c's CUDA kernel (`mlx/c/fast.h:40-97`) has the same configuration
functions one for one and one different argument to its constructor: **`int shared_memory`** (dynamic shared
memory in bytes, fixed per kernel object; above 48,000 B MLX raises the function's limit,
`mlx/backend/cuda/custom_kernel.cpp:369-377`) **in place of `atomic_outputs`** (a CUDA source calls `atomicAdd` on a
plain output). MLX wraps a CUDA source in a `__global__` function with `cooperative_groups` as `cg` and MLX's device
helpers (`elem_to_loc`), passes every input as `const T*` (0-d ones too) and shapes as fixed arrays of 10, turns
template arguments into `constexpr` locals and `using` aliases, and compiles with NVRTC at the first evaluation
(cached in memory; `MLX_PTX_CACHE_DIR`, default under `TMPDIR`); it documents CUDA kernels only in the Python
docstring (`python/src/fast.cpp:572-650`). Two launch rules differ from Metal's and matter to every source: **CUDA
launches `ceil(grid/threadgroup)` whole blocks, so a source must guard its own index** (Metal dispatches exactly the
grid, `custom_kernel.cpp:353-357` against `metal/custom_kernel.cpp:95-99`), and **CUDA does not check the block
size** against the device's limit.

**The kernels built from Metal source**, 31 names assigned in the tree (*exact*: the literal `%name =` assignments,
`scratch/keep/phase5/kernel_names.txt`), and some variants built from them (`_sizes`):

| Kernel | Where (`src/test/`) | Status | Metal features | A CUDA twin |
| --- | --- | --- | --- | --- |
| `draw_posterior_rvec` and `_rows` (K1, the polar tail: distances, first minimum, compensated sum of `exp`, the drawn rotation) | `toys/polar/mlxf_toy_polarft_workspace_tail.f90:18-145`; graph form `tail_graph`, `..._workspace_score.f90:233-268`; selector `POLARFT_TAILS` (default `graph`) | **kept** (K1 report, ruling R2) | one thread per pair, `thread_position_in_grid.x`, `fma`, `metal::precise::exp`, an index guard; no threadgroup memory, SIMD functions or atomics | near: built-ins renamed, `expf`/`fmaf`; the row tolerance `POLARFT_TAIL_ROW_TOL`, frozen on Metal with `precise::exp`, re-measured (NVRTC contracts `a*b+c` by default) |
| `fproject_polar_batch_opt_kernel` (K2, the projector's fused gather: rotation, Kaiser-Bessel window, 27-tap complex sum) | `toys/projector/mlxf_toy_projector_workspace.f90:33-78, 392-430`; graph form `graph_tile` (`:343-388`), selector `PROJ_FORMS` (default `graph`) | **kept** (K2 report) | two-dimensional grid, template ints `E, L, NPTS, PADS3`, `complex64_t` with `.real`/`.imag` members, an index guard | near: `complex64_t` is `cuda::std::complex<float>` with `.real()`/`.imag()` methods; templates become `constexpr` locals unchanged; the block limit 1,024 is the toy's own |
| `insert_plane_atomic` and `_plain` (the insertion probe, K6's speed reference and its control) | `bench/mlxf_bench_insert_probe.f90:48-95, 327-386` | not kept (ruled B: K6 starts from `mlx_scatter_add`) | `atomic_outputs`, `atomic_fetch_add_explicit`, `init_value` | `atomicAdd` on a plain output, `init_value` kept; `atomic_outputs` has no CUDA field |
| 14 forms of `bench_kernel_forms` (group sum, SIMD probe, threadgroup-memory probe, the tail per SIMD group, reductions, sizes as input, selections, the pulled insertion) | `bench/mlxf_bench_kernel_forms_src.f90` | measurements; T1, R2, E3 and D1 handed to K3 to K7 (kernel-forms report) | threadgroup arrays and barriers, `simd_sum/min/max`, `simd_prefix_inclusive_sum`, `simd_shuffle`/`simd_broadcast`, the SIMD width 32 written into the arithmetic | `__shared__` and `__syncthreads()`; `cg::reduce` or `__shfl_*_sync` (the warp is 32 too, so the arithmetic carries); `cg::inclusive_scan` needs an extra header in `header` |
| the kernels of the wrapper's tests (`mlxf_test_add_column`, `_grid_2d`, `_histogram`, `_template`, ...) and of the projector tester's refusals | `src/core/fast/mlxf_fast_tester.f90:94-543`, `framework/mlxf_test_registry.f90:423-431`, `toys/projector/mlxf_toy_projector_tester.f90` | the wrapper's tests | as above, plus a two-dimensional grid that the threadgroup does not divide | the CUDA wrapper's own tests; `column_spec` and `_grid_2d` have no index guard (they would write past the output on CUDA), the "threadgroup above the limit fails" assertion (`:530-537`) does not hold where CUDA clips the block |

**So the CUDA step owes two twins**, K1's tail (one source with its `rows` switch) and K2's gather; every other
computation keeps or falls back to its graph form, and with the default forms (`graph`) no kernel object is built
at all. Neither kept kernel uses threadgroup memory or SIMD-group functions, so their distance to CUDA is the
built-ins, the math functions and K2's complex type; the K3 to K7 forms handed on (T1, R2, E3, D1) are the ones that
use SIMD groups and threadgroup memory, and their plans write their CUDA sources from the start.

### C. Device classification, device information and the GPU checks of the tests

- **The tests know Metal only.** `cpu_only_mlx()` is `.not. mlx_metal_is_available()`
  (`src/test/framework/mlxf_test_utils.f90:131-134`): a CUDA build would classify itself as CPU-only, and its GPU
  checks would skip. A fourth session is needed (CUDA with or without a GPU), through `mlx_cuda_is_available`,
  which the parity ledger excludes today (`scripts/mlxc_parity.txt:184`); `mlxf_device.f90:41-53` (the
  no-device refusal) and `scripts/check_rules.py` rule `devquery` (it requires `mlx_metal_is_available` beside a
  GPU count, `:883-910`) follow the same three-session model. `MLXF_REQUIRE_GPU` defaults ON only on Apple arm64
  (`CMakeLists.txt:26-34`): a CUDA build should set it ON.
- **Assertions that fail on a CUDA GPU as written:** `mlxf_device_tester.f90:46` asserts `metal .or. .not. gpu`;
  `scripts/ci_cpu_job.sh:64` takes `Metal backend: F` as proof of a CPU-only MLX, which a CUDA build also prints.
- **Device information:** a CUDA build reports `device_name`, `uuid`, `architecture` (`sm_XY`, against Metal's
  `applegpu_*`), `pci_bus_id`, the compute capability, `free_memory` and `total_memory`
  (`mlx/backend/cuda/device_info.cpp:130-198`), **no `memory_size` and no `max_buffer_length`** (Metal's,
  `mlx/backend/metal/device_info.cpp:47-50`). Readers of those keys: `mlxf_device_tester.f90:112-118` (asserts
  `0 < max_buffer_length <= memory_size`), `mlxf_io_tester.f90:452-462` (the GPU branch, no guard for a missing
  key), `mlxf_error_tester.f90:78-82` (the recovery gate, which skips), the polar-table bench's memory budget
  (`mlxf_bench_polar_table.f90:1284-1293`, where `memory_size` stands for the machine's memory, true only of
  unified memory).
- **GPU-only checks that are Metal's:** the recovery gate (one maximum buffer serving both devices, Metal's message
  `allocate ... maximum`, `mlxf_error_tester.f90:62-140`), the wired limit (`mlxf_stream_tester.f90:107-131`; on
  CUDA `set_wired_limit` does nothing and returns 0, `mlx/backend/cuda/allocator.cpp:453-456`) and the Metal
  capture (`mlxf_stream_tester.f90:133-150`) are gated by "a GPU opens" (`gpu_check_runs`), so on a CUDA GPU they
  would run and fail: each needs a Metal gate, and the test policy's GPU-only list a Metal-only part.
  `guard_float64_on_gpu` holds: MLX refuses float64 on any GPU stream at array construction
  (`mlx/array.cpp:30-38`), CUDA included; only its comment says "Metal".
- **`mlx_cuda_is_available` is true on any CUDA build, with or without a GPU**
  (`mlx/backend/cuda/device_info.cpp:226-228`): the fourth session's test is "CUDA build, GPU count > 0"; the GPU
  count is `cudaGetDeviceCount` (index i is CUDA device i; `CUDA_VISIBLE_DEVICES` applies), where Metal's is
  always 1.
- **Tolerances calibrated on Apple GPUs** (`mlxf_test_defs.f90:255-265`, `:442`, `:550-554`) are recalibrated on
  the CUDA device under the frozen-tolerance rule; the tile plan measured on the M2 Ultra (`:33`) is re-measured.

### D. Memory: unified on Apple silicon, managed or copied on CUDA

- **MLX on CUDA** allocates GPU arrays in device memory (`cudaMallocAsync`/`cudaMalloc`,
  `mlx/backend/cuda/allocator.cpp:207-214`); the first host access (`Buffer::raw_ptr`) moves the buffer, with a
  copy, into unified memory: managed (`cudaMallocManaged`) where the GPU has concurrent managed access, else pinned
  host memory (`:36-66`, `:290-300`, `:413-419`). So `mlx_view`'s borrowed pointer and the copies of `mlx_to`
  (`mlxf_transfer_borrow.f90:27-63`, `mlxf_transfer_copy.f90:140-211`) stay correct, but a view costs a migration,
  and the contract's "unified memory, no copy" (`binding_contract_policy.md`, sections 4, 8, 10, 17) becomes a
  transfer MLX manages.
- **Zero-copy input** (`mlx_alloc`'s page-aligned buffer, `PAGE_BYTES = 16384`,
  `mlxf_transfer_borrow.f90:14, 566-627`) is Metal's `newBufferWithBytesNoCopy`; on CUDA expect a copy (`zero_copy`
  false), and 16 KiB is not a whole page on a 64 KiB-page aarch64 kernel (a Grace host).
- **The cost model** (`doc/how2s/how2use_installed.md:78-105`, measured on the M5; tool
  `src/test/bench/mlxf_bench_user_costs.f90`) is re-measured on the CUDA machine: the copy and view rows change with
  PCIe or NVLink-C2C.
- **The memory guard** (`scripts/run_parts.sh:65-128`) reads host memory only (`/proc/meminfo` on Linux), which
  is the GPU's on Apple silicon and not on a discrete GPU: it needs a device counter (`nvidia-smi` or MLX's peak).

### E. Precision, CPU-only operations, distributed, files

- **`MLX_ENABLE_TF32`** (MLX's, default 1, `mlx/utils.h:225-227`) switches cuBLAS to `CUBLAS_COMPUTE_32F_FAST_TF32`
  (`mlx/backend/cuda/gemms/cublas_gemm.cpp:22`) and cuDNN's convolutions to TF32 (`mlx/backend/cuda/conv.cpp:139`)
  on CUDA as NAX does on the M5: CTest's `MLX_ENABLE_TF32=0` (`test/CMakeLists.txt`) carries over unchanged.
- **CPU-only linear algebra:** MLX runs QR, SVD, the inverse, the pseudo-inverse, LU and the solvers on the CPU
  only on CUDA too (`mlx/linalg.cpp:14-21`); only `linalg::cholesky` may run on a CUDA GPU, in float32
  (`check_cpu_or_cuda_stream`, `mlx/linalg.cpp:23-33, 352`; `mlx/backend/cuda/cholesky.cu:70-72`). Fourier
  transforms run on cuFFT in single precision; sorts, partitions, gathers and scatters have CUDA kernels. The
  library's CPU-stream helpers (`mlxf_calls_checks.f90:119-129`, `mlxf_linalg_matrix.f90`) stay as they are; on a
  discrete GPU their crossing costs a transfer.
- **Distributed:** MLX has an NCCL backend (`mlx/distributed/nccl/`, `distributed.cpp:106-121`); the library pins
  the collectives to the CPU stream "since Metal has none" (`src/core/distributed/mlxf_distributed_calls.f90:1-4`),
  which on CUDA with NCCL would want the GPU stream.
- **Parity ledger:** `mlx_cuda_is_available` and the 13 `mlx_fast_cuda_kernel_*` functions are `excluded`, "CUDA:
  out of scope (Apple silicon only)" (`scripts/mlxc_parity.txt:184, 263-275`); rule `parity` refuses an excluded
  function the library calls (`check_rules.py:1161-1165`), so the wrapper's change reclassifies them in the same
  change. The ABI probe (`src/test/framework/mlxf_abi_probe.c:148-149`) lists the Metal kernel handles; the CUDA
  ones join it.
- **The release gate** (`scripts/release_gate.sh:36-39, 65, 138-167`) refuses anything but an Apple-silicon Mac and
  fails on any skip: a CUDA release check is a branch or a script of its own (`nvidia-smi` and `/proc/cpuinfo` for
  the host facts).
- **From Linux** (this run): the `stat` layout is handled by the C helper; `c_chmod`/`c_mkdir` pass `mode_t` as 16
  bits, harmless on x86-64 (gfortran zero-extends, the kernel masks) and to be checked on an aarch64 host;
  MLX's `g++` at run time and the system Open MPI (above).

### F. The MLX-centric port (decision 10)

The smallest change that runs the tree on CUDA through MLX itself, with no platform layer (roadmap decision 19):

1. **A CUDA kernel beside the Metal one, the same shape of spec.** mlx-c's CUDA kernel takes the same configuration
   (grid and threadgroup in threads, output shapes and dtypes, templates, `init_value`, `ensure_row_contiguous`,
   `verbose`) and one different argument, so the spec gains a CUDA source and a shared-memory size, and the kernel
   object applies whichever backend MLX was built with (`mlx_metal_is_available` / `mlx_cuda_is_available`, read
   once at construction). A kept kernel's spec function then sets one more source string, and nothing else changes:
   its graph form, its selector, its tests. Whether that is one record with two sources or a second record of the
   same shape, and the public names, are rank 5's decisions; the parity ledger's 14 CUDA lines become public or
   plumbing in the same change, and the ABI probe lists the CUDA handles.
2. **Two twins:** K1's tail (with `rows`) and K2's gather, each a translation of built-ins, math functions and (K2)
   the complex type, judged against its graph form by the 30 % rule on the Blackwell GPU (rank 5's row), with its
   tolerances re-measured there; K3 to K7 write both sources from the start.
3. **A fourth session in the tests and the policies:** CUDA with a GPU (both devices) or without one, through
   `mlx_cuda_is_available` and the GPU count; `MLXF_REQUIRE_GPU` ON on a CUDA build; the Metal-only checks (the
   recovery gate, the wired limit, the capture, `memory_size` and `max_buffer_length`, the threadgroup-limit
   assertion of the wrapper's tests) gated on Metal; `test_backend`'s assertion and `ci_cpu_job.sh`'s
   `Metal backend: F` test made backend-aware; the wrapper tests' kernels given index guards.
4. **Build and run:** `build_mlx_deps.sh` gains a CUDA mode (`-DMLX_BUILD_CUDA=ON`, the architecture recorded);
   the CUDA runtime, cuBLAS and cuDNN on the loader's path; a CUDA release check on the Blackwell machine (hosted
   runners have no GPU), modelled on `release_gate.sh`.
5. **Measured again, not changed:** the cost model, the memory guard's counter (the device's memory, not the
   host's), the tolerances and tile plans calibrated on Apple GPUs.
6. **Unchanged:** every graph form, the transfers and views (MLX migrates the buffers), the CPU-only linear
   algebra helpers, `MLX_ENABLE_TF32=0` in CTest, the C helper for `lstat`.

What rank 5 needs from a Blackwell machine before its plan: the GPU's compute capability and model, the host's
architecture (x86-64 or Grace), the NVIDIA driver, the CUDA toolkit (12.x, not 13.1) and cuDNN versions, and
whether the user may install packages (cuDNN, `liblapacke-dev`) or must build in user space as this run did.

## What changed, phase by phase

| Phase | Diff | What |
| --- | --- | --- |
| 0, the base | `review/phase_0.diff` | Progress only: the machine, the tools, BLAS/LAPACK/LAPACKE (decision 3 settled: installed by Hans before the launch), the static gate, section 2's findings re-checked (two corrections), the fence's refusal of `git clone` |
| 1, MLX and mlx-c | `review/phase_1.diff` | `scripts/build_mlx_deps.sh`: the Linux branch (platform switch, GCC, CPU-only implied, `$ORIGIN`, tag archives, `mlxf_deps.txt` naming the platform); the prefix built in 92 s |
| 2, the library | `review/phase_2.diff` | the `lstat` C helper (**new** `src/core/runtime/mlxf_libc_lstat.c`, `mlxf_libc.f90`), C sources in the library (`src/CMakeLists.txt`, `cmake/CompilerConfig.cmake`), the ABI probe's `-isystem` (`test/CMakeLists.txt`), the tester's helpers moved and `check_submodule_linkage.py` extended, the code-base map; Debug and Release from scratch, zero warnings |
| 3, the suite | `review/phase_3.diff` | the fast gate and every unit area in both builds, the named-only sub-suites; Apple question 38 |
| 4, checks and CI | `review/phase_4.diff` | `check_embed.sh` (the quotes), **new** `scripts/ci_linux_job.sh`, the `linux` job of `.github/workflows/ci.yml`; the install, embed and off-state checks and the CI job pass, the job with GNU Fortran 15.2 and 14.3 |
| 5, the record | `review/phase_5.diff` | this report with the CUDA inventory; `README.md`, `doc/how2s/how2set_up_dev.md` (section 7, Linux), the two policies, the roadmap's row, the index, the history |

**Every portability change and why** (each with why macOS is unaffected in the plan's Progress):

| File | Change | Why |
| --- | --- | --- |
| `scripts/build_mlx_deps.sh` | Linux branch | it refused anything but macOS (decision 2); macOS's commands traced identical |
| `src/core/runtime/mlxf_libc_lstat.c` (new), `mlxf_libc.f90` | `lstat` through a C helper | the fixed offsets of macOS's `struct stat` are wrong on glibc (decision 4) |
| `src/CMakeLists.txt`, `cmake/CompilerConfig.cmake` | `core/*.c` in the library; Fortran options scoped to Fortran, C warnings | the helper is the library's first C source; Fortran flags byte-identical in five configurations |
| `test/CMakeLists.txt` | `-isystem` before the ABI probe's `-I`, off Apple | GCC errors on mlx-c's unused static under `-Werror` |
| `src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester.f90`, `..._tester_solve.f90` | six helpers' bodies moved into the submodule | GNU Fortran 15 on Linux does not link them from the submodule |
| `scripts/check_submodule_linkage.py` | finds private separate procedures with module bodies | it declared that form safe; planted violation shown to fail |
| `scripts/check_embed.sh` | message matched around the quotes | GCC's typographic quotes on Linux |
| `scripts/ci_linux_job.sh` (new), `.github/workflows/ci.yml` | the Linux CI job | decision 6 |

**Skips:** none Linux-only. The five GPU-only skips (`unit_core`: the GPU's information, the recovery gate, the
memory and wired limits, a Metal capture; `guard_float64_on_gpu`) are those of any CPU-only MLX. **Questions:**
Apple question 38 (mlx-c's unused static); MLX's `mlx/error.h` deprecation warnings under GCC 15 (300 in the MLX
build) not filed, since a `TODO` in that file names them.

## Decisions taken under delegation

| Decision | Reason | Where |
| --- | --- | --- |
| The pinned tags fetched as GitHub's archives, and the Linux branch accepts an archive in place of a clone | the fence refuses `git clone`; content equal to `git archive` of the tag's commit, which is checked | Progress, Phases 0 and 1 |
| `RUNPATH $ORIGIN` on the installed libraries, Linux only | mlx-c links MLX privately; an executable's run path does not reach `libmlx.so` (measured twice) | Phase 1 |
| GCC from `PATH`, not `CC`/`CXX`, for MLX | mirrors the macOS branch's fixed clang | Phase 1 |
| The `lstat` helper returns the facts, not offsets | no layout in Fortran; SIMPLE's `simple_posix.c` pattern | Phase 2 |
| C sources of `src/core` are library sources; Fortran options scoped to Fortran | the helper needs C; one target kept | Phase 2 |
| mlx-c's headers as system headers for the ABI probe off Apple | the warning is mlx-c's; the probe keeps `-Werror` | Phase 2 |
| The tester's helpers moved and the linkage checker extended (two file-table rows added) | the build needs it; the checker exists to catch this | Phase 2 |
| `c_chmod`/`c_mkdir`'s 16-bit mode left as is | gfortran zero-extends, the kernel masks: harmless on x86-64 (inventory) | Phase 2 |
| The named-only sub-suites run too | the run's instructions name every sub-suite | Phase 3 |
| Acceptance 1's comparison by construction, the exact one the controller's | the macOS CPU-only job's counts at this base are on the M5 | Phase 3 |
| `ci_linux_job.sh` runs `ci_cpu_job.sh` and adds embed and off-state | one path for both platforms; the two checks run nowhere else on Linux | Phase 4 |
| `check_embed.sh` matches around the quotes | as `check_install.sh` already does | Phase 4 |
| gfortran 14 tested from unpacked Ubuntu packages | the CI's 14 leg known to pass before it was written | Phase 4 |
| CI packages: OpenBLAS (OpenMP) and LAPACKE, the runner's CMake and g++, gfortran 15 from the toolchain PPA | the combination tested on dell2; noble's archive stops at 14 | Phase 4 |
| The test policy's list of GPU-only checks corrected to five, and its linkage rule widened | the transcripts show five; the checker now enforces the wider rule | Phase 5 |

## Deviations from the plan

- **Decision 2's "the run clones"** could not be carried out: the archives replaced the clones (above). The clone
  path of the script is the CI's and was traced, not run, here.
- **Files added to the table:** the reconstructor tester's two files and `scripts/check_submodule_linkage.py`
  (Phase 2), each before it was edited.
- **Acceptance 1's exact comparison** with the macOS CPU-only job is the controller's (Phase 3).
- **Outside the run's directory:** Phase 3's tests ran with the default `TMPDIR` (`~/tmp`) and left MLX's kernel
  cache and Open MPI's session directory there; both were created by this run and removed in Phase 4, and every
  later run used scratch. Read-only use of the `eman2` environment's Python to parse the workflow.
- **Section 2's findings corrected:** `dylib` and `applegpu` are named nowhere outside `doc/`; `mlxf_libc` binds no
  `O_*` flag and no `errno`.

## Evidence against the baseline

- The static gate passes after every phase (`keep/phaseN/check_tree*.log`); with `MLXC_ROOT` set, rule `parity`
  compares its ledger with real mlx-c 0.8.0 headers on Linux for the first time, and every rule holds.
- macOS's side, checked here without a Mac: the build script's macOS commands traced identical in 13 of 14 cases
  (`--help` gains four lines); the generated Fortran flags byte-identical in five configurations; every other
  change sits behind a branch macOS does not take or accepts exactly what it accepted (the embed pattern test).
- Linux: Debug 4.9 s and Release 17.9 s builds from scratch, zero warnings; fast gate 13 of 13 in both; per-area
  counts in the plan's Phase 3 table; `check_install.sh`, `check_embed.sh`, `check_toy_offstate.sh --exec` and
  `ci_linux_job.sh` (four legs) pass. The base `mlxf_libc` fails `unit_io` on Linux and the fix passes it.
- The off-state table (135 lines) is kept for comparison with the M5's: `keep/phase4/offstate_release_table.txt`.

## Left open for the maintainer

- **The controller's macOS gates on the M5** (acceptance 3): Debug and Release, the fast gate, every unit area, the
  static, install and off-state checks, the toys' identity set; in particular `unit_io` (the `lstat` helper now runs
  on macOS too, compiled by the build's C compiler), `/bin/bash` 3.2 on the new code of `build_mlx_deps.sh`, and
  the macOS CPU-only job's counts against Phase 3's table.
  *Done 2026-11-27, merged onto `9581e64` (rank 2 K4 committed):* Debug and Release from scratch with `MLXF_WERROR`,
  zero warnings, the fast gate 13 of 13 in each, all twelve unit areas pass at the checkout's counts (`unit_io` 905),
  `check_tree`, `check_install`, `check_embed`, `check_toy_offstate --exec`; `/bin/bash` 3.2 parses the new
  `build_mlx_deps.sh` and runs its `--help`. The off-state table of the M5's Debug build equals this run's byte for
  byte (SHA-256 `f1e71b11`); the M5's Release table differs in the last bits of 129 of 135 lines (the compiler's
  optimization on arm64, not a Linux difference; each build still equals its own `mlxf_test_exec`). The macOS
  CPU-only job's counts were not run (no CPU-only MLX on the M5). The mlx-c question is Apple question 38: 37 was
  taken by the M2's overflow flag while the run ran.
- **The first hosted run of the Linux CI job** (the runner's g++ 13 building MLX, the PPA, noble's gfortran 14.2).
  The macOS CPU job's cache key hashes `build_mlx_deps.sh`, so its cached MLX is rebuilt once.
- **Proposed, not applied** (a skill or register edit needs your approval): the rule "a submodule never calls a
  private plain procedure of its module" in `.github/skills/mlxf-modern-fortran/SKILL.md` and
  `doc/architecture_principles.md` should read "a private procedure whose body is in its module (plain or
  separate)", as the test policy and the checker now do.
- **Clones or the archive input:** with a ruling that lets a run clone into its scratch, the archive input of
  `build_mlx_deps.sh` could be dropped.
- **Apple question 38** is open, not sent.
- **Rank 5**, CUDA, is planned from the inventory above when a Blackwell machine is reachable.
- The plan moves to `completed/` after your read.

## Commit message

```
Linux, CPU only: MLX and mlx-c on Linux, the suite on the CPU device, a Linux CI job (run mlxf_linux, roadmap rank 2h)

scripts/build_mlx_deps.sh gains a Linux branch: MLX and mlx-c built
CPU-only with GCC, the libraries found through $ORIGIN, from clones or
GitHub's archives of the tags (commit checked and recorded); the macOS
commands are unchanged. On Linux mlxf_libc read macOS's struct stat at
fixed offsets (a save over an existing file was refused); lstat now goes
through a C helper, the library's first C source, so the Fortran build
options are scoped to Fortran and C gets its own warnings. The ABI probe
reads mlx-c's headers as system headers off Apple (GCC errors on an
unused static of array.h, Apple question 38). gfortran 15 on Linux does
not link a private separate procedure whose body is in the module from a
submodule: the reconstructor tester's six helpers move into the
submodule, and check_submodule_linkage.py finds that form. check_embed.sh
matches GCC's message around its quotes. scripts/ci_linux_job.sh and a
Linux CI job (Ubuntu 24.04, gfortran 14 and 15) run the CPU-only job,
the embedding and the toys without MLX. README, the setup guide (Linux),
the two policies, the roadmap, the history and the index follow; the
report carries the inventory for the CUDA step.

On dell2 every unit area passes on the CPU device in Debug and Release
(4,411 checks, 33 guard members, five GPU-only skips, none Linux-only),
with gfortran 15.2 and 14.3; the install, embed and off-state checks
pass.

New files:
src/core/runtime/mlxf_libc_lstat.c
scripts/ci_linux_job.sh
doc/implementation_notes/completed/mlxf_linux_report.md
```
