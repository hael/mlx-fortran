# CUDA on NVIDIA Blackwell: prepared on dell2, measured at work (runs `mlxf_cuda_prep`, `mlxf_cuda_twins`, `mlxf_cuda_blackwell`)

Status, 2026-11-27: planned; ruled by Hans the same day (his answers to the four questions put to him): decision 6
option A (`mlx_custom_kernel`), decision 2 "decide at work" (amended below), decision 13 as recommended, and every
other decision as recommended. Base: `bb52e8f` (the Linux port and K4 committed), every premise below checked there. Supersedes: none.
Depends on: rank 2h's Linux build and its CUDA inventory (validated: yes, `completed/mlxf_linux_report.md`, sections
A to F); MLX `v0.32.4` with CUDA 12.9 building on dell2 for `100a;120a` (validated: yes, built
and linked under mlx-fortran in the compile-only probe of 2026-11-27, `~/cuda_probe/logs/` on dell2, section 2,
item 5); the roadmap's decisions 19 and 20.

## 1. Why

Hans, 2026-11-27: SIMPLE will run on both platforms, the Mac first; the three Blackwell machines at work are PCIe
cards in x86 hosts and cannot be reached from here. Everything mlx-fortran knows about cost was measured on unified
memory, where a copy to or from the GPU is nearly free and the GPU's memory is the machine's. On a PCIe card a
transfer crosses the bus, a host read of a GPU array migrates it, and every part process competes for the card's own
memory. Rank 2h listed what a CUDA build meets (its report, section F: the kernel wrapper, a fourth test session,
the Metal-only checks, the memory guard, two kernel twins) and nothing of it has been built or run. Since nothing
at work is reachable, every part that does not need a GPU is done and checked here first, so that the session at
work is bring-up and measurement only.

## 2. Contract

- **Three runs, one plan.** Part A (`mlxf_cuda_prep`, dell2, phases 0 to 5) prepares the tree; Part B
  (`mlxf_cuda_twins`, dell2, phases 10 to 12) writes the CUDA sources of the kept kernels after K7; Part C
  (`mlxf_cuda_blackwell`, one Blackwell machine at work, phases 20 to 26) builds, runs and measures there. Each
  launches from the commit holding the previous one's verified result.
- **MLX-centric** (roadmap decision 19): MLX's own CUDA backend; a kept kernel gains a CUDA source beside its Metal
  one through mlx-c's CUDA kernel and nothing else; the graph forms stay the portable path; no toy or library code
  branches on the platform outside the kernel sources and the tests' device checks.
- **macOS unchanged in behaviour.** The Metal session's counts, the toys' identity set (`e2d65e88`) and every
  timing gate are as at the base; the controller checks them on the M5 after Parts A and B.
- **Linux CPU-only unchanged** in counts (rank 2h's table, updated by every K run since).
- **No GPU here.** Parts A and B build and link against a CUDA MLX on dell2 and run nothing on a GPU; a claim about
  CUDA behaviour is Part C's, and the report says which numbers are which.
- **No production data.** The toys' synthetic fixtures only, at work too.
- Git read-only; Python 3.7 standard library for anything the build or gate runs; the house rules of `CLAUDE.md`.

### What the check found (2026-11-27, at `bb52e8f`, *measured*)

1. dell2: CUDA 12.9.1 toolkit (no driver) in `/opt/cuda-12.9`, merged from the runfile's components because
   NVIDIA's installer needs `libxml2.so.2` and Ubuntu 26.04 has `libxml2.so.16` only; cuDNN 9.28.1 for CUDA 12 in
   `/opt/cudnn-9-cuda12`; `gcc-14`/`g++-14` beside GCC 15 (nvcc 12.9 accepts host compilers up to GCC 14).
2. glibc 2.43 declares `cospi`, `sinpi`, `rsqrt` and their `f` forms `noexcept`; CUDA 12.9's
   `crt/math_functions.h` does not, and nvcc fails on any file. Hans added `noexcept (true)` to the six
   declarations (original kept as `math_functions.h.orig`); a test kernel then builds for `sm_100a` and `sm_120a`,
   and MLX 0.32.4 configures with CUDA (nvcc 12.9.86, host GCC 14.3, cuDNN and OpenBLAS found, architectures
   `100a;120a`, 67 s). glibc 2.41 or newer needs the same edit; CUDA 13.0 has it, 13.1 is refused by MLX.
3. The kernel API: `mlx_metal_kernel` (`src/core/fast/mlxf_fast.f90`) built from `mlx_metal_kernel_spec`
   (`src/defs/mlxf_defs.f90`); readers of `mlx_metal_is_available`: `mlxf_device.f90`, `mlxf.f90`,
   `mlxf_test_utils.f90` (`cpu_only_mlx`), `mlxf_device_tester.f90`, `mlxf_fast_tester.f90`. The parity ledger
   excludes `mlx_cuda_is_available` and the 13 `mlx_fast_cuda_kernel_*` lines (`scripts/mlxc_parity.txt:184,
   263-275`).
4. Kept fused kernels at the base: K1's tail (`draw_posterior_rvec`, `_rows`) and K2's gather
   (`fproject_polar_batch_opt_kernel`); every other computation runs its graph form by default. K3 is running on
   the M5; K5 to K7 follow; K7 judges K1's tail again (its decision 27).
5. The compile-only probe on dell2 (`~/cuda_probe/probe.sh`, logs in `~/cuda_probe/logs/`, *measured*): MLX
   0.32.4 with CUDA for `100a;120a` configures in 67 s and builds in 675 s on 16 cores with no compile error;
   mlx-c 0.8.0 builds on it; mlx-fortran at `bb52e8f` (Release, `MLXF_WERROR=ON`, `BUILD_TESTS=ON`) compiles with
   no warning, and `mlxf_test_exec` links. Three things were needed: (a) MLX's installed CMake package looks for
   cuDNN again in every consumer, so `CUDNN_INCLUDE_PATH` and `CUDNN_LIBRARY_PATH` go to mlx-c's configure too
   (mlx-fortran finds mlx-c only and needs neither); (b) `libmlx.so` needs the driver's `libcuda.so.1`, which a
   machine without a driver lacks: the link resolves against the toolkit's stub through a directory holding
   `libcuda.so.1 -> <toolkit>/lib64/stubs/libcuda.so` and `-Wl,-rpath-link` to it (build only; never on a
   loader path); (c) at run time `libmlx.so` needs `libcublasLt.so.12`, `libcufft.so.11`, `libcusolver.so.11`,
   `libnvrtc.so.12`, `libcudnn.so.9` and the driver's `libcuda.so.1`, none on the default loader path when the
   toolkit and cuDNN sit in `/opt`.
6. The benchmarks Part C runs: `bench_user_costs`, `bench_polar_table` (suites `time` and `maps`),
   `bench_projector`, `bench_recon_pcg`; `scripts/run_parts.sh` runs N part processes together, and its memory
   guard reads host memory only.

## 3. Decisions

1. **Three runs** (section 2). Part A starts on dell2 now, beside the K runs on the M5; Part B after K7's result is
   committed, so that it writes the CUDA source of every kernel K1 to K7 kept, once; Part C when Hans is at a
   Blackwell machine with Part B committed. *Recommended:* it keeps dell2 busy, keeps Part A off the files the K
   runs edit, and writes each twin once.
2. **Toolkit, chosen at work** (ruled 2026-11-27, Hans: "Decide at work"). Parts A and B build with CUDA 12.9,
   cuDNN 9 for CUDA 12 and host GCC 14 on dell2. Part C chooses in Phase 20 from `nvidia-smi` and what the machine
   holds, by this rule, fixed now: (a) a toolkit already installed there that MLX accepts (12.8 or newer, not 13.1)
   and the driver supports is used, with the cuDNN 9 that matches its major version; (b) else CUDA 13.0 if the driver
   is 580 or newer (no glibc edit, GCC 15 accepted), installed in user space as on dell2; (c) else CUDA 12.9 if the
   driver is 575 to 579; (d) a driver below 575 is a stop (decision 15). The choice and its reason go to Progress.
   Part A's `--cuda` therefore supports CUDA 12.8 to 12.9 and 13.0 (the host-compiler and glibc checks by
   version); only 12.9 can be built here, so 13.0 is first built at work and the report says so.
3. **`scripts/build_mlx_deps.sh --cuda`** (Linux only): `-DMLX_BUILD_CUDA=ON`; the toolkit from `CUDA_HOME`
   (default `/usr/local/cuda`), cuDNN from `CUDNN_ROOT` (passed as `CUDNN_INCLUDE_PATH`/`CUDNN_LIBRARY_PATH`), the
   host compiler from `CUDAHOSTCXX` (default: the newest `g++-N` nvcc accepts); `MLX_CUDA_ARCHITECTURES` from
   `--cuda-arch` (default: native where a GPU is present, else refused with a message naming `100a`/`120a`); the
   prefix `.deps/install-cuda`; `mlxf_deps.txt` records toolkit, cuDNN, host compiler, architectures and glibc. The
   script checks the glibc/`math_functions.h` clash before configuring and stops with the fix in its message; it
   never edits the toolkit. It passes the cuDNN paths to mlx-c's configure as well (item 5a); on a host without a
   driver (`--cuda-arch` given, no `libcuda.so.1` found) it links through the stub as in item 5b and writes into
   `mlxf_deps.txt` that the result is build-only; it installs `libmlx.so` with a run path to the toolkit's
   `lib64` and cuDNN's `lib` (item 5c), so that nothing needs `LD_LIBRARY_PATH` but the driver, which is the
   system's. mlx-fortran's own configure needs no CUDA option; a driverless link of `mlxf_test_exec` takes the
   stub directory through `MLXF_CUDA_STUB_DIR` in `cmake/` (build-only, refused when a driver is present). The macOS and CPU-only branches keep their commands byte for byte.
4. **A backend query in the library.** `mlx_cuda_is_available` becomes public beside `mlx_metal_is_available`
   (ledger line 184 public); `mlxf_device`'s no-device refusal and `MLXF_REQUIRE_GPU` (ON on a CUDA build) learn
   the CUDA build. On CUDA the GPU count is `cudaGetDeviceCount`'s and `CUDA_VISIBLE_DEVICES` applies.
5. **A fourth test session.** The tests classify a session as Metal, CUDA with a GPU, CUDA without a GPU, or CPU-only
   MLX (`mlxf_test_utils.f90`); the Metal-only checks (the recovery gate, the wired limit, the Metal capture, the
   `memory_size` and `max_buffer_length` keys, the threadgroup-limit assertion of the wrapper's tests) are gated on
   Metal with a named skip line; `test_backend`'s assertion, `ci_cpu_job.sh`'s `Metal backend: F` test and rule
   `devquery` of `check_rules.py` become backend-aware, the rule shown to fail on a plant. The test policy's
   session list gains the fourth session.
6. **The kernel's public shape** (ruled 2026-11-27, Hans: option A). Options:
   - **A, ruled:** one backend-neutral type `mlx_custom_kernel` built from `mlx_custom_kernel_spec`, the
     present spec plus `cuda_source` and `shared_memory` (bytes, default 0); construction reads the backend MLX
     was built with once and uses its source; a spec without that backend's source refuses with a message, and the
     toy then runs its graph form. `mlx_metal_kernel` and its spec are renamed in the same change (no user outside
     this tree, no release tagged; the API list and the binding policy's section 12 follow). One name, one object,
     no branch in the callers: the MLX-centric rule's "adds a CUDA source and changes nothing else".
   - **B:** keep `mlx_metal_kernel` and add `mlx_cuda_kernel` with the same spec, as MLX's Python API does
     (`metal_kernel`, `cuda_kernel`); every caller then chooses one by backend, which is the platform branch the
     MLX-centric rule forbids in toy code.
   - **C:** keep the name `mlx_metal_kernel` and let it hold CUDA too: no API change, a misleading name.
7. **The wrapper's tests** run on both backends: each test kernel gets a CUDA source; `column_spec` and `_grid_2d`
   get index guards (CUDA launches whole blocks, rank 2h's report B); the "threadgroup above the limit fails"
   assertion is Metal-only (CUDA clips the block). On dell2 the CUDA sources are compiled, not run (decision 9).
8. **The memory guard reads the device.** `scripts/run_parts.sh` takes the card's free memory from `nvidia-smi
   --query-gpu=memory.used,memory.total` on a CUDA host (host memory stays the guard on Apple silicon), and the
   series table gains the device's peak; the polar-table bench's `memory_size` budget becomes the device's total on
   CUDA.
9. **CUDA sources checked without a GPU.** `scripts/check_cuda_sources.sh` (new, Linux, needs `nvcc`) extracts
   every CUDA source string of the tree's kernel specs, wraps it as MLX does (`mlx/backend/cuda/custom_kernel.cpp`
   at the tag: the `__global__` signature, `cooperative_groups` as `cg`, inputs as `const T*`, shapes as fixed
   arrays, templates as `constexpr` locals) and compiles it for `sm_100a` and `sm_120a`. A plant (a source that
   does not compile) shows it fails. It says "compiled, not run" in its output.
10. **The session script.** `scripts/cuda_session.sh` (new) runs Part C's measurements from one command with fixed
    parameters, writes every log and table under one directory with the machine's facts (`nvidia-smi -q`, driver,
    toolkit, cuDNN, glibc, CPU, memory, load, the commit) and packs it as a tarball Hans brings home. On a host
    without a CUDA GPU it runs the CPU parts and prints a skip line per GPU part, which is how dell2 tests it.
11. **Experiments at work, in order** (Part C), each *reported, not gated*, against numbers recorded on the M5 at the
    same commit:
    - **E1 bring-up:** the fast gate and every unit area on the CUDA device, Debug and Release.
    - **E2 transfer cost model:** `bench_user_costs` (copy, view, call overhead, evaluation), the seconds per byte
      across PCIe that turn rank 4's seam traffic into a predicted cost (roadmap decision 20).
    - **E3 parts sharing one card:** `run_parts.sh` with 1, 2, 3, 4 and 6 parts on the polar table and the shift
      maps, without and with MPS (NVIDIA's server for sharing one GPU, started in user space with
      `nvidia-cuda-mps-control -d` if allowed); summed rate, device memory per part.
    - **E4 the toys' graph forms at SIMPLE's sizes:** the polar table and maps, the projector, the PCG
      reconstructor at N = 160 and 256; rates against the M5's and against the same host's CPU device.
    - **E5 precision:** the toys' accuracy suites on the CUDA device with `MLX_ENABLE_TF32=0`, their tolerances
      re-measured (decision 12).
    - **E6 the kernel twins:** each kept kernel's CUDA source against its graph form by the 30 % rule (roadmap
      decision 15), at one process and at the part count E3 finds best.
12. **Tolerances on CUDA.** A tolerance calibrated on an Apple GPU (`mlxf_test_defs.f90`) that fails on CUDA is
    re-measured in Phase 21 the way the test policy calibrates (on seed 1 on the CUDA device with the margin rule
    the tolerance's own comment states, frozen, then seeds 2 and 3 judged) and recorded as a CUDA value beside the
    Metal one; never loosened for both.
13. **Twins: keep or delete** (ruled 2026-11-27 as recommended). A CUDA source that does not reach 1.30 against its graph form on the Blackwell card
    at the best part count is deleted in Phase 25 (the graph form stays, as on Metal); a kept one stays in the spec
    with its re-measured tolerance. The Metal kernel's keep is not reopened by a CUDA loss.
14. **Claude at work.** Part C runs as an arun run with `HOST=local` on the Blackwell machine. Before its launch Hans
    (on that machine): installs Claude Code and signs in; clones `mlx-fortran` at the commit holding Part B and
    `agent_runs`; confirms the toolkit and cuDNN (or installs both in user space, as on dell2) and GitHub access
    for MLX's configure; and checks with his workplace that Claude Code may run there. The run returns its result
    by `arun fetch` there; Hans brings the review directory and the session tarball home, and the controller verifies
    the macOS side here.
15. **Part C's machine.** One card, not shared with other users while E2 to E6 time it (the load and `nvidia-smi`'s
    processes recorded before each); `CUDA_VISIBLE_DEVICES` pins it. The run never touches the driver, never
    installs system packages, and builds in its own directory.
16. **Distributed on CUDA** (NCCL) is not touched: the collectives stay on the CPU stream, as now.
17. **The CUDA release check** is Part C's script, not `release_gate.sh` (which stays Apple's): `cuda_session.sh
    --gate` runs E1 alone and exits non-zero on any failure.

Defaults taken without a question: the run names; the prefix `.deps/install-cuda`; the session directory
`build/cuda_session/<date>`; the part counts 1, 2, 3, 4, 6.

## 4. Not in this plan

- NVIDIA hosts with Grace CPUs (64 KiB pages; rank 2h's report D), other GPU generations, CUDA 13.1, multi-GPU work,
  NCCL.
- Any change to a graph form, a toy's algorithm or a timing gate on the Mac.
- SIMPLE: its integration (rank 4) is designed on the Mac (roadmap decision 20); Part C's numbers inform it.
- Packages, a hosted CUDA CI (hosted runners have no GPU).
- Part A edits no file a K run edits (`src/test/toys/`, `src/test/bench/` other than the polar table's memory
  budget, `src/test/oracles/`, `scripts/toy_*.txt`); Part B's toy files wait for K7.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement | the probe's builds recorded; dell2's CPU-only suite at the base's counts |
| 1 | build script | `build_mlx_deps.sh --cuda` reproduces the probe's prefix; macOS and CPU-only branches byte for byte |
| 2 | library, tests | CPU-only Linux counts unchanged; the library and `mlxf_test_exec` build and link against CUDA MLX on dell2 with zero warnings; rule `devquery` plant fails |
| 3 | API, tests | decision 6's shape; the wrapper's tests compile on all three builds; `check_cuda_sources.sh` passes with its plant failing |
| 4 | scripts | `run_parts.sh` and `cuda_session.sh` run on dell2 (CPU parts, GPU skip lines) |
| 5 | record | report, docs; `git status` shows file-table paths only |
| 10 | measurement | Part B's base: K7 committed; the kept kernels listed |
| 11 | kernel sources | each kept kernel's CUDA source compiles in `check_cuda_sources.sh`; macOS identity set unchanged |
| 12 | record | report section, Progress |
| 20 | measurement | the machine's facts; decision 2's toolkit choice; base suite on the CPU device |
| 21 | bring-up | E1: every unit area on the CUDA device; tolerances re-measured and frozen (decision 12) |
| 22 | measurement | E2 and E5 |
| 23 | measurement | E3 |
| 24 | measurement | E4 |
| 25 | kernel keep | E6 and decision 13 |
| 26 | record | report, session tarball |

After Parts A and B the controller runs on the M5 what it runs after every run: Debug and Release from scratch, the
fast gate, every unit area, the static, install, embed and off-state checks, and the toys' identity set.

## 6. Acceptance

1. Part A: on dell2, Debug and Release of the CPU-only build pass at the base's counts; the CUDA build of the
   library and `mlxf_test_exec` links with zero warnings; `check_cuda_sources.sh` compiles every CUDA source of the
   wrapper's tests; `cuda_session.sh` runs to its end with GPU skip lines. On the M5: unchanged (section 5).
2. Part B: every kept kernel's CUDA source compiles for `sm_100a` and `sm_120a`; macOS identity set unchanged.
3. Part C: E1 passes on the CUDA device in Debug and Release, every skip named and every re-measured tolerance
   recorded with its evidence; E2 to E5 tabulated against the M5 (*measured*, both sides at the same commit); E6
   decided by the 30 % rule (*rule*, roadmap decision 15) at a part count E3 measured. A failure of E1 that is
   MLX's is a question for the MLX team with an mlx-c reproducer (`doc/collaboration/apple_questions.md`), never a
   loosened test.
4. Reported, not gated: E2 to E5's numbers and what they predict for rank 4 (the seam's bytes times E2's seconds
   per byte); Hans reads them.

## 7. Rules and stops

- No file outside the table; no test loosened; `MLX_ENABLE_TF32=0` in every test and timed run; nothing installed
  with `sudo`; the toolkit never edited by a run.
- **Stops:** the CUDA MLX does not build on dell2 after one diagnosis; a change would alter macOS behaviour or a
  public name other than decision 6's; at work, a driver below the toolkit's need, a card in use by others, or no
  network for MLX's configure; a phase over twice its box; a tolerance that would have to move on Metal.
- **Gates no ruling may waive:** zero warnings on every build; the static gate; the API list (decision 6's change
  only); the macOS identity set; no test loosened; the graph forms unchanged.

## 8. Phases

### Part A, run `mlxf_cuda_prep` (dell2)

#### Phase 0, the base and the probe (box: 60 min)

Pin the base; record dell2's toolkit, cuDNN, host compilers and glibc; record the compile-only probe's result
(`~/cuda_probe/logs/summary.txt`: which of MLX, mlx-c and mlx-fortran built, the errors if any); build the CPU-only
Debug and Release and run every unit area. Exit: the facts and counts in Progress; if the probe failed, the cause
diagnosed and recorded (a stop if it is MLX's and cannot be worked around under decision 3).

#### Phase 1, `build_mlx_deps.sh --cuda` (box: 150 min)

Decision 3. Exit: `.deps/install-cuda` with `libmlx.so`, `libmlxc.so`, the CMake packages and `mlxf_deps.txt`; the
macOS and CPU-only branches traced byte for byte as rank 2h did.

#### Phase 2, the backend query and the fourth session (box: 180 min)

Decisions 4 and 5. Exit: CPU-only counts unchanged in Debug and Release; the CUDA build of the library and
`mlxf_test_exec` links with zero warnings; rule `devquery`'s plant fails; the test policy updated.

#### Phase 3, the kernel API and its tests (box: 180 min)

Decisions 6, 7 and 9. Exit: acceptance 1's wrapper part; the API list and the binding policy's section 12 follow
decision 6; the parity ledger's CUDA kernel lines public or plumbing; the ABI probe lists the CUDA handles.

#### Phase 4, the memory guard and the session script (box: 120 min)

Decisions 8 and 10. Exit: `run_parts.sh` with two parts and `cuda_session.sh` run to the end on dell2.

#### Phase 5, the record (box: 90 min)

`doc/how2s/how2set_up_dev.md` (a CUDA section: toolkit, cuDNN, host compiler, the glibc edit, `--cuda`), the
binding policy (the transfers on a discrete GPU: correct, priced by E2), the roadmap's rank 5a row, the index, the
history, the report with a commit message without attribution naming every new file. Exit: acceptance 1.

### Part B, run `mlxf_cuda_twins` (dell2, after K7)

#### Phase 10, the base (box: 30 min)

Pin the base (K7 committed); list every kept kernel from the K reports and the specs in the tree. Exit: the list.

#### Phase 11, the CUDA sources (box: 150 min)

Each kept kernel's spec gains its CUDA source (built-ins renamed, `expf`/`fmaf`, the complex type, an index guard);
its tolerance note says "CUDA: measured in Part C". Exit: acceptance 2.

#### Phase 12, the record (box: 45 min)

Exit: the report's section, Progress, a commit message.

### Part C, run `mlxf_cuda_blackwell` (one Blackwell machine at work)

#### Phase 20, the machine (box: 60 min)

Record the facts (decision 10's list); choose the toolkit by decision 2's rule; check the glibc edit if 12.x; build the CPU-only Release
and run its suite. Exit: the facts; no stop of decision 15.

#### Phase 21, bring-up (box: 240 min)

`build_mlx_deps.sh --cuda` (native architecture); Debug and Release; the fast gate and every unit area on the CUDA
device; each failure diagnosed; Apple-calibrated tolerances re-measured and frozen (decision 12). Exit: E1.

#### Phase 22, transfers and precision (box: 90 min)

E2 and E5 through `cuda_session.sh`. Exit: their tables in Progress.

#### Phase 23, parts sharing the card (box: 150 min)

E3, without and with MPS. Exit: the series table, device memory per part, the best part count.

#### Phase 24, the toys at SIMPLE's sizes (box: 150 min)

E4. Exit: the rate table against the M5 and the host's CPU device.

#### Phase 25, the twins (box: 120 min)

E6, decision 13. Exit: each twin kept or deleted with its numbers.

#### Phase 26, the record (box: 90 min)

The report (what was learned first; what each number predicts for rank 4), the session tarball's path, the
roadmap, the history, the index. Exit: acceptance 3.

### File table

| File | What | Phases |
| --- | --- | --- |
| `scripts/build_mlx_deps.sh` | `--cuda` | 1, 21 |
| `scripts/check_cuda_sources.sh` | new: CUDA sources compiled as MLX wraps them | 3, 11, 21 |
| `scripts/cuda_session.sh` | new: Part C's measurements, the session tarball, `--gate` | 4, 21, 22, 23, 24, 25 |
| `scripts/run_parts.sh` | the device's memory on CUDA | 4, 23 |
| `scripts/ci_cpu_job.sh`, `scripts/ci_linux_job.sh` | backend-aware checks | 2 |
| `scripts/check_rules.py`, `scripts/check_tree.sh` | rule `devquery` backend-aware; the new script in the gate if it runs there | 2, 3 |
| `scripts/mlxc_parity.txt` | the CUDA lines public or plumbing | 2, 3 |
| `CMakeLists.txt`, `cmake/`, `src/CMakeLists.txt`, `test/CMakeLists.txt` | `MLXF_REQUIRE_GPU` on CUDA; the CUDA build; `MLXF_CUDA_STUB_DIR` | 1, 2, 3, 21 |
| `src/core/runtime/mlxf_device.f90`, `src/core/runtime/mlxf_device_tester.f90` | the backend query; the no-device refusal | 2, 21 |
| `src/core/runtime/mlxf_error_tester.f90`, `src/core/runtime/mlxf_stream_tester.f90`, `src/core/io/mlxf_io_tester.f90` | Metal-only checks gated | 2, 21 |
| `src/core/mlxf.f90` | the re-exports of decisions 4 and 6 | 2, 3 |
| `src/core/fast/` | the kernel type and its tests | 3, 21 |
| `src/defs/mlxf_defs.f90` | the kernel spec | 3 |
| `src/test/framework/mlxf_test_utils.f90` | the fourth session | 2, 21 |
| `src/test/framework/mlxf_test_defs.f90` | CUDA tolerances beside the Metal ones | 21 |
| `src/test/framework/mlxf_test_registry.f90` | a guard's device tag, if needed | 2, 21 |
| `src/test/framework/mlxf_abi_probe.c` | the CUDA handles | 3 |
| `src/test/bench/mlxf_bench_polar_table.f90` | the memory budget on CUDA | 4 |
| `src/test/toys/`, `src/test/bench/` | each kept kernel's CUDA source; a twin deleted by decision 13 | 11, 25 |
| `test/consumer/` | the API list (decision 6) | 3 |
| `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md` | sections 4, 8, 10, 12, 17; the fourth session | 2, 3, 5, 26 |
| `doc/how2s/how2set_up_dev.md`, `README.md` | CUDA | 5, 26 |
| `doc/collaboration/apple_questions.md` | an MLX question from E1 | 21 |
| `doc/code_base_map.md` | regenerated | 2, 3, 4, 5, 11, 26 |
| `doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md` | rows | 5, 12, 26 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` | entries | 5, 12, 26 |
| `doc/implementation_notes/planned/mlxf_cuda.md` | this note: Progress | 0, 1, 2, 3, 4, 5, 10, 11, 12, 20, 21, 22, 23, 24, 25, 26 |
| `doc/implementation_notes/completed/mlxf_cuda_report.md` | new: the report, a part per run | 5, 12, 26 |

## Progress

(one entry per phase, written by the runs)
