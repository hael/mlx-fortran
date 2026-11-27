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

18. **A refused kernel falls back to its graph form** (2026-11-27, from the independent review of Parts A and K3;
    stands as recommended, open to the review). Decision 6 promises that a spec without the backend's source is
    refused "and the toy then runs its graph form", but every toy and bench builds its kernel with the function
    form, which stops on a refusal, and the testers choose the fused form on any GPU: on a CUDA GPU the first fused
    tail would stop `mlxf_test_exec` and lose every later suite. Part B therefore (a) builds each kept kernel with
    `k%new(spec, status=st)` and, on a refusal, records it and runs the graph form; (b) has each tester choose a fused
    form only where the kernel object was built, with a named skip line otherwise; (c) keeps one test per kernel that
    the refusal is a fallback, not a stop. The same holds for a twin deleted under decision 13. Part B also adds the
    index guard the fused tail has (`TAIL_INDEX_MAX`) to the pair-list kernel, whose 32-bit offsets wrap once the
    resident tiles pass 2^32 floats.

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
its tolerance note says "CUDA: measured in Part C". Decision 18's fallback and the pair-list kernel's index guard.
Exit: acceptance 2; a refused kernel runs its graph form (decision 18 (c)) in every suite that picks a fused form.

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
| `src/test/framework/mlxf_test_registry.f90` | a guard's device tag, if needed; the kernel guards renamed (decision 6) and the named-only sub-suite of the CUDA sources (decision 9) | 2, 3, 21 |
| `src/test/framework/mlxf_abi_probe.c` | the CUDA handles | 3 |
| `src/test/bench/mlxf_bench_polar_table.f90` | the memory budget on CUDA | 4 |
| `src/test/toys/`, `src/test/bench/` | each kept kernel's CUDA source; a twin deleted by decision 13 | 11, 25 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace.f90`, `src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90`, `src/test/toys/projector/mlxf_toy_projector_workspace.f90`, `src/test/bench/mlxf_bench_insert_probe.f90`, `src/test/bench/mlxf_bench_kernel_forms.f90`, `src/test/bench/mlxf_bench_kernel_forms_src.f90` | decision 6's rename and nothing else (ruled: "renamed in the same change"; section 4 otherwise keeps Part A off these files) | 3 |
| `scripts/mlxf_consumer_checks.py` | the handle type renamed (decision 6) | 3 |
| `test/mlxf_test_exec.f90` | the argument `records=` of the sub-suite `kernel_sources` (decision 9) | 3 |
| `test/consumer/` | the API list (decisions 4 and 6); the outside programs tell the CUDA sessions apart (decision 5) | 2, 3 |
| `doc/quickstart.md` | the sessions row and its example, a verbatim run of `mlxf_example_errors.f90` (decision 5) | 2 |
| `doc/api_reference.md` | regenerated (`scripts/generate_api_reference.py`): the public names of decisions 4 and 6 | 2, 3 |
| `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md` | sections 4, 8, 10, 12, 17; the fourth session | 2, 3, 5, 26 |
| `doc/how2s/how2set_up_dev.md`, `README.md` | CUDA | 5, 26 |
| `doc/collaboration/apple_questions.md` | an MLX question from E1; one found by the CUDA source check (decision 9) | 3, 21 |
| `doc/code_base_map.md` | regenerated | 2, 3, 4, 5, 11, 26 |
| `doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md` | rows | 5, 12, 26 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` | entries | 5, 12, 26 |
| `doc/implementation_notes/planned/mlxf_cuda.md` | this note: Progress | 0, 1, 2, 3, 4, 5, 10, 11, 12, 20, 21, 22, 23, 24, 25, 26 |
| `doc/implementation_notes/completed/mlxf_cuda_report.md` | new: the report, a part per run | 5, 12, 26 |

## Progress

(one entry per phase, written by the runs)

### Phase 0, the base and the probe: done (2026-11-27, 09:29 to 09:42 EST, dell2)

Run `mlxf_cuda_prep`, first session, on dell2 (Ubuntu 26.04.1, kernel 7.0.0-44, Intel Core Ultra 7 366H, 16 cores,
61 GB, no GPU). **Base `1426c10`** (this plan's commit). Its code equals `bb52e8f`, where section 2's premises were
checked: `git diff --stat bb52e8f 1426c10` touches four documents only. The rulings of 2026-11-27 are already
written into this plan (the status line, decisions 2, 6 and 13); Phase 0 applied none. Evidence:
`/home/hael/agent_runs/mlxf_cuda_prep/scratch/keep/phase0/` (`keep/phase0/` below). About 13 minutes (*measured*)
of the 60-minute box. Files changed: this note only. No source changed, so there was nothing to format, and macOS is
unaffected.

**dell2's toolchain** (*measured*, `keep/phase0/nvcc_check/nvcc_check.log`):

| Item | Found |
| --- | --- |
| CUDA toolkit | `/opt/cuda-12.9`: nvcc V12.9.86, cuBLAS 12.9.1.4, cuFFT 11.4.1.4, cuSOLVER 11.7.5.82, NVRTC 12.9.86, cudart 12.9.79; the stub `lib64/stubs/libcuda.so` |
| Driver | none: no `libcuda.so.1` on the system, no `/dev/nvidia*`, no `nvidia-smi` |
| cuDNN | 9.28.1 for CUDA 12, `/opt/cudnn-9-cuda12` (`cudnn_version.h`) |
| Host compilers | nvcc's: `gcc-14`/`g++-14` 14.3.0. The library's: GCC, G++ and GNU Fortran 15.2.0, the defaults (no `gfortran-14` installed). nvcc 12.9 refuses `g++-15` (`crt/host_config.h:143`, "gcc versions later than 14 are not supported") |
| glibc | 2.43 (Ubuntu 2.43-2ubuntu2.7). `bits/mathcalls.h:83, 85, 206` declare `cospi`, `sinpi` and `rsqrt` through `__MATHCALL_VEC`, that is with `__THROW` (`noexcept (true)` in C++). The toolkit's `crt/math_functions.h` differs from its `.orig` in exactly six lines, each declaration given `noexcept (true)` (section 2, item 2) |
| Check | the probe's `t.cu` (`cospif` and `rsqrtf` in a kernel) compiles with `-ccbin g++-14` for `sm_100a` and for `sm_120a` (exit 0 both) |
| Rest | CMake 4.2.3, Python 3.14.4 |

**The compile-only probe** (`~/cuda_probe`, read only; `logs/summary.txt` and the step logs, *measured* by the
probe, 2026-11-27). Its mlx-fortran source (`~/cuda_probe/mlxf`) equals this base apart from the four documents of
`1426c10`, so it is `bb52e8f`. The first mlx-c configure log was overwritten when the probe was resumed.

| Step | Result | Time |
| --- | --- | --- |
| MLX 0.32.4 configure: CUDA 12.9.86, host GCC 14.3, architectures `100a;120a`, cuDNN and OpenBLAS found, NCCL not | exit 0 | 67 s |
| MLX build (`-j 16`), install | exit 0 | 675 s, 0 s |
| mlx-c 0.8.0 configure, first attempt | **exit 1**. MLX's installed package runs `find_dependency(CUDNN REQUIRED)` (`share/cmake/MLX/MLXConfig.cmake:42`), and its `FindCUDNN.cmake` searches only `CUDNN_INCLUDE_PATH`, `CUDNN_LIBRARY_PATH` and the toolkit's directories, so cuDNN in `/opt` is not found: item 5a | 0 s |
| mlx-c configure with the cuDNN paths; build; install | exit 0 | 0 s, 6 s, 0 s |
| mlx-fortran configure (Release, `MLXF_WERROR=ON`, `BUILD_TESTS=ON`) | exit 0. The CUDA and cuDNN variables passed are unused: mlx-fortran finds mlx-c only | 1 s |
| mlx-fortran build | **exit 2**. The library and the 168 Fortran objects compile with no warning. The link of `mlxf_test_exec` fails: "`libcuda.so.1`, needed by `libmlx.so`, not found", then 12 undefined `cu*` driver symbols. `-rpath-link` to `lib64/stubs` cannot help, because the stub is named `libcuda.so`: item 5b | 18 s |
| By hand: `stublink/libcuda.so.1 -> /opt/cuda-12.9/lib64/stubs/libcuda.so`, `-Wl,-rpath-link` to it, reconfigure, relink | `mlxf_test_exec` linked (`mlxf_relink.log`) | - |

So MLX, mlx-c and mlx-fortran all built. The two errors are the two needs (a) and (b) of section 2, item 5, and
neither is MLX's to fix.

The probe's prefix, re-read and copied (not reused) to `scratch/keep/probe_install` (135 MB), with a stub directory
of this run's own (`scratch/keep/stublink`). It holds `libmlx.so` (99 MB, `RUNPATH $ORIGIN`) and the headers MLX
installs for NVRTC at run time (`include/cccl`, `cute`, `cutlass`). `libmlx.so` needs `libcublasLt.so.12`,
`libcufft.so.11`, `libcusolver.so.11`, `libnvrtc.so.12`, `libcuda.so.1` and `libcudnn.so.9`. `ldd` finds none of
the six on the default loader path. With the toolkit's `lib64` and cuDNN's `lib` on `LD_LIBRARY_PATH`, only the
driver's `libcuda.so.1` is missing: item 5c re-checked. The installed CMake package names no absolute path of the
probe.

**The base linked against the CUDA MLX** (`keep/phase0/build_cuda_base.sh`, `build_cuda_base_{release,debug}.log`,
*measured*). The base was configured as the probe's relink was: `MLXC_ROOT` the copied prefix and
`-Wl,-rpath-link` to the stub directory, the toolkit's `lib64` and cuDNN's `lib`, with no CUDA option of
mlx-fortran's own. Release builds in 17.2 s (load 0.85 at the start) and Debug in 4.6 s (load 1.85). Both have zero
warnings and no linker warning, and `mlxf_test_exec` links in both. Its run path names the prefix only, and the six
libraries above are unresolved at run time. Nothing was run, since dell2 has no GPU and no driver. These trees,
`scratch/build_cuda_base_{release,debug}`, are Phase 2's reference for a CUDA link.

**CPU-only builds and the suite** (*measured*). The CPU-only MLX and mlx-c prefix of run `mlxf_linux` was copied
to `scratch/keep/deps/install-cpu`: MLX `v0.32.4` `36969c0`, mlx-c `v0.8.0` `a26f2d5`, GCC 15.2, CPU only, per its
`mlxf_deps.txt`. Both trees were configured by hand (`keep/phase0/build_from_scratch.sh`: `-DBUILD_TESTS=ON
-DFORTLS=OFF -DMLXF_WERROR=ON -DMLXF_REQUIRE_GPU=OFF -DMLXC_ROOT=<prefix>`; GNU Fortran 15.2 chosen by
`AutoDetectGCC`), with `TMPDIR` in scratch. Each was built from scratch, gated by the fast gate and installed:

| Build | Build wall (load at start) | Warnings | Fast gate | CTest wall (longest entry) | Log |
| --- | --- | --- | --- | --- | --- |
| Debug | 4.9 s (0.07) | 0 | 13 of 13; `check_tree: passed` | 14.90 s (`unit_kernels` 14.85 s) | `build_debug.log`, `fast_gate_debug.log` |
| Release | 18.2 s (1.14) | 0 | 13 of 13; `check_tree: passed` | 3.64 s (`unit_kernels` 3.61 s) | `build_release.log`, `fast_gate_release.log` |

**Every unit area on the CPU device: these are the base's counts**, the reference for "CPU-only Linux counts
unchanged" in Phases 2 to 5. They were read from the CTest transcripts (`LastTest_{debug,release}.log`) by rank
2h's `area_counts.py` (`keep/phase0/area_counts.md`). They are *exact*, and Debug and Release are identical:

| Entry | Test groups | Assertions evaluated = passed | Skips | Against rank 2h's table |
| --- | --- | --- | --- | --- |
| `unit_core` | 7 | 159 | 4 GPU-only: the GPU's information, the recovery gate, the memory and wired limits, a Metal capture | equal |
| `unit_array` | 1 | 123 | none | equal |
| `unit_ops` | 8 | 1,736 | none | equal |
| `unit_linalg` | 5 | 419 | none | equal |
| `unit_fft` | 2 | 101 | none | equal |
| `unit_compile` | 1 | 32 | none | equal |
| `unit_transforms` | 2 | 153 | none | equal |
| `unit_fast` | 2 | 47 | none | equal |
| `unit_random` | 1 | 244 | none | equal |
| `unit_io` | 1 | 475 | none | equal |
| `unit_distributed` | 1 | 28 | none | equal |
| `unit_kernels` | 12 | 966 | none | +1 group, +72: K4 (`9581e64`) added `oracle_polar` (46) and checks to `polar_shiftmap` (+20), `seam` (+4) and `eul_prob_tab` (+2) |
| `object_contracts` | 34 guard members | 33 stopped with the hard-error status | 1: `guard_float64_on_gpu` | +1 member: `guard_from_unknown_size`, RB1 (`e445512`) |

That is **4,483 assertions and 34 guard members per build**, none failed, with the same five GPU-only skips as rank
2h and no other skip. Each `SKIP` line reads `GPU-only check on a CPU-only MLX build`. `unit_core`'s device
report reads `GPU devices: 0` and `Metal backend: F`, and no `SKIP: no GPU device` appears. The differences from rank 2h's table
(4,411 and 33, taken at `0f8252b`) are exactly the commits merged since then. The per-suite counts of the two
transcripts differ only in the four suites named above.

**The named-only sub-suites**, each run by name in CTest's environment (`MLX_ENABLE_TF32=0`) in its own directory
(`keep/phase0/run_named.sh`, `run_ring.sh`, `named_*.log`), *measured*:

| Sub-suite | Release | Debug |
| --- | --- | --- |
| `unit_core suite=recovery_half` | skipped, GPU-only (the recovery gate) | the same |
| `unit_kernels suite=polar_shiftmap_accuracy` | 24 of 24, 0.50 s | 24 of 24, 1.88 s |
| `unit_kernels suite=reconstructor_pcg_n32` | 48 of 48, 61.0 s (load 1.20 at the start) | 48 of 48, 253.3 s (load 1.31) |
| `unit_distributed suite=distributed_ring`, two processes on MLX's ring backend over the loopback | 14 of 14 on each rank | the same |

Every run exits 0 and leaves no file behind. The short nvcc check of the probe's `t.cu` (two single-file compiles)
ran during the Release `reconstructor_pcg_n32` run. That run's 61.0 s compares with rank 2h's 60.5 s (*measured*,
theirs).

Decisions taken under delegation:

- **Base `1426c10`, not `bb52e8f`.** The run starts from the plan's commit, whose code is `bb52e8f`'s, so section
  2's premises hold unchanged.
- **The CPU-only prefix was copied from run `mlxf_linux`, not rebuilt.** It has the same tags (commits checked in
  its `mlxf_deps.txt`), the same machine and the same compiler, and it is the prefix rank 2h's counts were taken
  on. Phase 1 builds prefixes through the script.
- **The probe's prefix was copied to `scratch/keep/probe_install`, and the base was linked against it in Debug and
  Release.** This follows the phase notes ("copy, do not reuse"). Phase 2 then has a CUDA-linked base with
  zero warnings to compare against, and Phase 1 has the probe's prefix to reproduce, both without touching
  `~/cuda_probe`.
- **The named-only sub-suites were run too.** The run's instructions name every sub-suite, and they reach MLX's
  ring backend and a long CPU solve, which the gate does not.
- **`TMPDIR` in the run's scratch** for every build and test (`scratch/tmp`: MLX's kernel cache and Open MPI's
  session directory). This keeps rank 2h's lesson: its first runs had left both under `~/tmp`.

Exit:

- The base is pinned: `1426c10`, equal in code to `bb52e8f`. Met.
- The toolkit, cuDNN, the host compilers and glibc are recorded: met (table above, `keep/phase0/nvcc_check/`).
- The probe's result is recorded: met. MLX, mlx-c and mlx-fortran built, with the two errors diagnosed as items 5a
  and 5b and worked around without MLX. Neither is a stop.
- CPU-only Debug and Release are built and every unit area is run: met. Both have zero warnings and 13 of 13 in
  the fast gate, with 4,483 assertions and 34 guard members per build and the four named-only sub-suites passing
  (`keep/phase0/`).
- The static gate passes: in both fast gates and after this entry (`keep/phase0/check_tree_end.log`).

What it means, in short:

- dell2 is ready for Part A. CUDA 12.9 with the edited header, cuDNN 9.28 and GCC 14 build MLX for Blackwell, and
  the base mlx-fortran compiles and links against that MLX with zero warnings.
- The three needs of item 5 are confirmed one by one: cuDNN's paths for every consumer of MLX's CMake package, the
  stub reached as `libcuda.so.1` for a driverless link, and the six run-time libraries outside the loader's path.
  Each is a line of `build_mlx_deps.sh --cuda` (decision 3), not a change to MLX.
- The CPU-only suite passes at the base with 4,483 checks and 34 guard members per build, which is rank 2h's count
  plus K4's and RB1's tests. Every later phase of Part A is judged against these numbers.

### Phase 1, `build_mlx_deps.sh --cuda`: done (2026-11-27, 09:41 to 10:30 EST, dell2)

Same session as Phase 0, base `1426c10`. Rulings: decision 2's rule as ruled (12.8, 12.9 and 13.0 accepted; only
12.9 can be built here). Evidence: `/home/hael/agent_runs/mlxf_cuda_prep/scratch/keep/phase1/` (`keep/phase1/`
below). About 50 minutes (*measured*) of the 150-minute box. Files changed: `scripts/build_mlx_deps.sh`,
`cmake/Dependencies.cmake` and this note; no new file.

**`scripts/build_mlx_deps.sh --cuda [--cuda-arch LIST]`** (decision 3, Linux only). Checks, all made before
anything is configured or removed:
- **The toolkit:** `CUDA_HOME` (default `/usr/local/cuda`), resolved to its real path. Its `nvcc --version` must
  be 12.8, 12.9 or 13.0; 13.1 and anything older than 12.8 are refused.
- **The host compiler:** `CUDAHOSTCXX` if given, else the newest `g++-N` or `g++` that nvcc accepts (GCC 14 at
  most for 12.x, 15 for 13.0). It is checked with `-dumpfullversion` and kept as an absolute path. The `gcc`
  beside it compiles MLX's and mlx-c's C. The same compiler builds all of MLX and mlx-c, as in the probe.
- **glibc:** with a 12.x toolkit and glibc 2.41 or newer, the six unfixed declarations of
  `crt/math_functions.h` stop the script. The message gives the fix as one `sed` command, which keeps a `.orig`
  copy. Applied to a copy of `/opt`'s `.orig`, that command reproduces Hans's edited header byte for byte
  (`keep/phase1/glibc_fix/fix_check.log`). The script never edits the toolkit.
- **cuDNN:** `CUDNN_ROOT` (made absolute; `lib`, else `lib64`) is passed as `CUDNN_INCLUDE_PATH` and
  `CUDNN_LIBRARY_PATH` to MLX and to mlx-c (item 5a). Unset, it is looked for where MLX's `FindCUDNN` looks first,
  the toolkit's `include`, then the system's. Version 9 is required.
- **The architectures:** `--cuda-arch` (`100a`, `'100a;120a'` or `100a,120a`) becomes `MLX_CUDA_ARCHITECTURES`.
  Without it, the build uses the GPU's own architecture when `nvidia-smi -L` lists a GPU. The record then shows
  `__nvcc_device_query`'s answer, which is what MLX uses, and the toolkit's `bin` goes on `PATH` because MLX runs
  that query by name. With no GPU and no `--cuda-arch`, the script refuses with a message naming `100a` and `120a`.
- **The driver:** "present" means the loader opens `libcuda.so.1` (`python3`'s `ctypes`). Without one, the prefix is
  build-only and the toolkit's stub must exist.

What it builds:
- MLX with `-DMLX_BUILD_CUDA=ON`, nvcc and its host compiler, `CUDAToolkit_ROOT`, and the libraries in
  `<prefix>/lib` on every distribution (`CMAKE_INSTALL_LIBDIR=lib`: GNUInstallDirs picks `lib64` on RPM-based ones).
- `libmlx.so` and `libmlxc.so` installed with `RUNPATH $ORIGIN:<toolkit>/lib64:<cuDNN>/lib` (item 5c).
- Then a C program is linked against the installed mlx-c and never run. Without a driver, the link goes through
  `<prefix>/cuda-stub/libcuda.so.1 -> <toolkit>/lib64/stubs/libcuda.so` with `-rpath-link` only (item 5b).
- `mlxf_deps.txt` adds the toolkit, cuDNN, the host compiler, the architectures, glibc, the driver or "build-only"
  with the stub directory, and the run-time note: MLX's NVRTC reads the toolkit's headers from `CUDA_HOME` or
  `/usr/local/cuda`.
- The prefix defaults to `.deps/install-cuda` (work: `.deps/work-cuda`). The closing line names `MLXC_ROOT` and,
  without a driver, `-DMLXF_CUDA_STUB_DIR`.

**`MLXF_CUDA_STUB_DIR`** (`cmake/Dependencies.cmake`, decision 3) is a cache path, empty by default. When it is set,
configure:
- refuses on macOS, a directory without `libcuda.so.1`, and a host whose loader opens `libcuda.so.1` (the build's
  Python and `ctypes`; there the driver needs no stub);
- adds `LINKER:-rpath-link,<dir>` to `mlxf_build_flags`, so only `mlxf_test_exec`'s link reads it, never the
  loader. The installed package does not carry it, because the flag sits behind `BUILD_INTERFACE`.

mlx-fortran's configure otherwise takes no CUDA option, as the probe showed.

**The real build on dell2** (*measured*). `keep/phase1/run_build_cuda_final.sh` ran the final script from a frozen
copy (`keep/phase1/frozen/`, sha256 `3586df83`). Inputs: the tags' archives, `CUDA_HOME=/opt/cuda-12.9`,
`CUDNN_ROOT=/opt/cudnn-9-cuda12` and `--cuda-arch '100a;120a'`. It ran with 16 jobs, exited 0 and took 518 s, from
load 0.13 at the start (`build_mlx_deps_cuda_final.log`); MLX's configure took 58.9 s. The script chose
`/usr/bin/g++-14` and `gcc-14` by itself. mlx-c configured the first time, and the link check linked through the
stub. MLX's own build prints the 784 warning lines of its `error.h` that the probe's build printed too: MLX's, as
rank 2h recorded. The probe's three steps took 748 s (*measured*, the probe's).

A first run of an earlier version (sha256 `1bcc5258`, 493 s) built `keep/deps/install-cuda`. It was compared
the same way with the same result, then deleted (`compare_prefix.log`).

**It reproduces the probe's prefix** (`keep/phase1/compare_prefix_final.log`, against the copy
`keep/probe_install`; *exact*):

| | Probe | `--cuda` |
| --- | --- | --- |
| Files | 2,065 | the same 2,065, plus `mlxf_deps.txt` and `cuda-stub/libcuda.so.1` |
| `include/`, `share/cmake/` (the MLX and MLXC packages) | | byte for byte identical |
| `libmlx.so` | `NEEDED` 12 libraries, 1,737 exported and 547 undefined symbols | the same; 99 kernels each for `sm_100a` and `sm_120a` (`cuobjdump`) |
| `libmlxc.so` | 1,282,200 B, 872 exported and 533 undefined symbols | the same |
| `RUNPATH` of both | `$ORIGIN` | `$ORIGIN:/opt/cuda-12.9/lib64:/opt/cudnn-9-cuda12/lib` |
| Not found on the default loader path (`ldd libmlxc.so`) | the six of item 5c | `libcuda.so.1` only, the driver's |

The prefix is `scratch/keep/deps/install-cuda-final`, kept for Phases 2 and 3.

**mlx-fortran against it** (`keep/phase1/build_mlxf_cuda.sh`, `build_mlxf_cuda_{release,debug}.log`, *measured*;
nothing run, since dell2 has no GPU and no driver). The trees were configured with `MLXC_ROOT` and
`-DMLXF_CUDA_STUB_DIR=<prefix>/cuda-stub` only, with no linker flags by hand.

| Build | Wall (load at start) | Warnings | `mlxf_test_exec` | Not found at run time |
| --- | --- | --- | --- | --- |
| Release | 18.4 s (4.74) | 0 | linked | `libcuda.so.1` only |
| Debug | 4.8 s (5.58) | 0 | linked | `libcuda.so.1` only |

The trees are `scratch/build_cuda_{release,debug}`. The checks of the option (`keep/phase1/cmake_checks/plants.log`):
- a stub directory without `libcuda.so.1` stops the configure at `Dependencies.cmake:123`;
- a loader that finds a `libcuda.so.1` (`LD_LIBRARY_PATH` at the stub, as where a driver is installed) stops it at
  `:129`;
- without the option, the probe's failure returns: `mlxf_test_exec` does not link, with 12 undefined `cu*` symbols.
  `ld` now misses only `libcuda.so.1`, since the run path brings the toolkit's libraries.

**macOS and CPU-only, byte for byte** (`keep/phase1/trace/trace_deps_script.sh`, `trace_run.log`). Rank 2h's
harness was extended. Stubs log every command (`cmake`, `git`, `tar`, the compilers, `nvcc`, `nvidia-smi`, the driver
probe, glibc's version), and the base script (HEAD's, kept as `keep/phase1/build_mlx_deps.base.sh`) and the new one
run on the same inputs:
- **Faked Darwin, 16 cases** (Metal, `--cpu-only`, jobs, prefixes, sources, every refusal, `CUDA_HOME` and the
  other CUDA variables set but unused): identical commands, outputs, records and directories. The exception is
  `--help`, which gains the new header lines and the usage line, as in rank 2h.
- **Linux CPU-only, 12 cases** (clones, archives, every archive refusal, an unknown option, FreeBSD, the CUDA
  variables set but unused): identical.
- **`--cuda`, 31 cases, the new script alone**, against fake toolkits: driverless with two architectures, the
  default prefix, a driver with a GPU (native), a driver without a GPU, the comma list, a bad list, CUDA 12.8,
  13.0 (GCC 15, no glibc check), 13.1, 12.6, no toolkit, `CUDAHOSTCXX` too new, given or not a GCC, system cuDNN,
  no cuDNN, a bad `CUDNN_ROOT`, a relative `CUDNN_ROOT`, cuDNN 8, no stub, a failing link, a stale stub directory
  removed where a driver is, `--cuda` with `--cpu-only`, `--cuda-arch` alone or without a value, `--cuda` on
  macOS. Each exits as intended.
- **The plant:** the unedited header with glibc 2.43 (and with 2.41) stops with the fix. The same header with
  glibc 2.39, or under CUDA 13.0, passes.

The CMake change with the option empty (`keep/phase1/cmake_checks/cpu_only_unchanged.log`): a CPU-only Release
configure with this phase's files was compared with Phase 0's tree, with tree names of equal length because CMake's
run-path padding follows the prefix length. Its 7 generated `link.txt`, `flags.make` and `build.make` files are
identical, and the only cache difference is `MLXF_CUDA_STUB_DIR:PATH=`. CPU-only Debug and Release were also rebuilt
from scratch: zero warnings, fast gate 13 of 13 with `check_tree: passed`, and counts identical to Phase 0's
(`keep/phase1/cpu_build_{debug,release}.log`, `area_counts_cpu.md`).

**Why macOS is unaffected:**
- `build_mlx_deps.sh`: every Darwin case traces identically, apart from `--help`'s text. `--cuda` is refused on
  Darwin before any command runs. The file has no bash 4 syntax: no associative arrays, case conversion,
  `mapfile`, `[[ -v ]]`, namerefs or negative indices. Here-strings, `=~` with the regex in a variable, `${x//,/;}`
  and `compgen` are bash 3.2's. This was read here and by the reviewer, and bash 3.2's parse is the controller's
  check on the M5.
- `cmake/Dependencies.cmake`: the new block runs only when `MLXF_CUDA_STUB_DIR` is set, and on macOS a set value
  is refused. Empty, it adds one cache entry and nothing to any target.

**Review.** A subagent reviewed the diff against decisions 2 and 3 without my conclusions, and found:
- one bug: the link check named `<prefix>/lib`, while GNUInstallDirs installs into `lib64` on RPM-based systems;
- nits: `nvidia-smi` pipelines that `pipefail` could abort, compiler names resolved before `PATH` changed, a stale
  stub directory, cuDNN's major and search order, the native record, the closing line.

All were fixed and traced again before the final run. Two nits stay as they are, each with its reason: the stub
variable sits beside its use in `Dependencies.cmake`, not with the boolean options, and prints a status line when
set; `--help`'s range ends on `set -euo pipefail`, as HEAD's did.

Decisions taken under delegation:

- **The prefix in the run's scratch.** `PREFIX=scratch/keep/deps/install-cuda-final` was used, not the repository's
  `.deps/install-cuda`, which the run's instructions keep out of the repository. The default prefix is shown by
  the trace case `cuda_default_prefix`.
- **The sources from the tags' archives**, as rank 2h did: the run's fence refuses cloning.
- **One compiler for all of MLX and mlx-c:** nvcc's host compiler, with its `gcc` for C, as the probe built.
  CUDA host code and the C++ then share one libstdc++ and ABI.
- **The driver test is the loader's**, `dlopen("libcuda.so.1")` through `ctypes`, in the script and in CMake. A
  driver installed outside the default paths and found through `LD_LIBRARY_PATH` counts as present.
- **The clash check reads the header**: the six declarations without `noexcept`, with a 12.x toolkit and glibc
  2.41 or newer. A compile test was not used: it would only say that something failed.
- **The link check**, a small C program linked against the installed mlx-c, is how the script "links through the
  stub" (item 5b) and proves the prefix linkable. Without a driver it is never run.
- **`<prefix>/cuda-stub`** is the stub directory. It is removed and remade by every `--cuda` build, and only made
  where no driver is.
- **`CMAKE_INSTALL_LIBDIR=lib` on the CUDA branch only** (review): the CPU-only commands stay byte for byte.
- **cuDNN 9 required**, as the plan names it. A system cuDNN is searched in `FindCUDNN`'s order.
- **CUDA 12.8 and 13.0 are traced, not built:** only 12.9 is installed here. 13.0 is first built at work
  (decision 2).
- **Every real run starts from a frozen copy of the script.** The first run executed the repository's file in
  place. An edit made while it ran was undone at once by restoring the launched bytes (sha256 checked), while
  bash was still waiting on MLX's build, and the edit was carried in a copy until the run ended.

Exit:

- `.deps/install-cuda` with `libmlx.so`, `libmlxc.so`, the CMake packages and `mlxf_deps.txt`: met. The prefix is
  `scratch/keep/deps/install-cuda-final`, built by the final script, and the default name is traced. It reproduces
  the probe's prefix (table above).
- The macOS and CPU-only branches traced byte for byte as rank 2h did: met. Of 28 cases compared, 27 are identical
  and `--help` is the one intended difference; CPU-only builds and counts are unchanged.
- Zero warnings in every mlx-fortran build; the static gate passes (`keep/phase1/check_tree_end.log`).

What it means, in short:

- One command now builds the CUDA MLX that Hans's probe built by hand. It refuses the known ways to fail before a
  12-minute build starts: the glibc clash with its fix, a toolkit MLX refuses, a host compiler nvcc refuses, a
  missing cuDNN or stub, and no architecture on a machine without a GPU.
- The run path makes the toolkit and cuDNN invisible to users. Only the driver's `libcuda.so.1` must come from the
  system, which on the work machine it will.
- On dell2 one CMake option, `MLXF_CUDA_STUB_DIR`, replaces the probe's hand-made link flags. Phase 2 builds and
  links its changes against this prefix.

### Phase 2, the backend query and the fourth session: done (2026-11-27, 10:26 to 10:55 EST, dell2)

Same session, base `1426c10`. Rulings: none specific; decisions 4 and 5 as recommended. Evidence:
`/home/hael/agent_runs/mlxf_cuda_prep/scratch/keep/phase2/` (`keep/phase2/` below). About 30 minutes (*measured*) of
the 180-minute box.

**Two rows added to the file table** before their files were edited:
- `test/consumer/` gains Phase 2. Adding a public name means regenerating `mlxf_api_names.f90`
  (`check_install.sh` runs `list_public_api.py --check`), and the outside programs classify the session themselves
  (rule `devquery`).
- `doc/quickstart.md` (Phase 2): its session example is a verbatim run of `mlxf_example_errors.f90` (rule
  `docex`).
- `doc/api_reference.md` (Phases 2 and 3) is generated and checked by the static gate, so a new public name or a
  renamed one changes it.

**MLX's facts this rests on** (*exact*, read from MLX 0.32.4's source in `scratch/keep/src` at the tag):
- On a CUDA build `gpu::is_available()` is always true, and the GPU count is `cudaGetDeviceCount`'s: 0 without a
  device, and with none visible through `CUDA_VISIBLE_DEVICES`.
- The default device is the GPU.
- The CUDA allocator's constructor calls `cudaMemGetInfo`, so without a GPU nothing allocates on either device,
  as with Metal without a device.
- A CUDA GPU's information has `device_name`, `uuid`, `architecture` (`sm_XY`), `pci_bus_id`,
  `compute_capability_major/minor`, `free_memory` and `total_memory`, but no `memory_size` or
  `max_buffer_length`.
- `libmlx.so` needs `libcuda.so.1`, so without NVIDIA's driver library a CUDA build does not load at all.
  "No driver" is therefore not a session; only "no GPU present or visible" is.

**What changed:**

| File | Change | Why macOS (and CPU-only) is unaffected |
| --- | --- | --- |
| `src/core/runtime/mlxf_device.f90` | `mlx_cuda_is_available` (public, `mlxc_cuda_is_available`). `mlxf_enter` asks both backends, and the no-device state is per backend (`METAL_WITHOUT_DEVICE`, `CUDA_WITHOUT_DEVICE`). `mlxf_require_device` stops with the Metal message unchanged, or a CUDA message ("none present, or none visible through `CUDA_VISIBLE_DEVICES`") | mlx-c 0.8.0 has `mlx_cuda_is_available` in every build (false without CUDA). On Metal and CPU-only builds the states and the refusal text are as before |
| `src/core/mlxf.f90`, `scripts/mlxc_parity.txt` | the re-export; ledger line `mlx_cuda_is_available` from `excluded` to `public` | one more public name; the API list and reference follow |
| `test/consumer/mlxf_api_names.f90`, `doc/api_reference.md` | regenerated (317 names) | generated |
| `CMakeLists.txt`, `cmake/Dependencies.cmake` | `MLXF_MLX_CUDA`: `readelf -d` of the `libmlx.so` beside libmlxc names `libcuda.so.1` (off Apple only; a status line says when no `libmlx.so` is found to read). `MLXF_REQUIRE_GPU` is declared after `include(Dependencies)` and defaults ON on Apple arm64 or with a CUDA MLX. A status hint names `-DMLXF_CUDA_STUB_DIR` when a CUDA MLX is configured where no driver loads | on APPLE the detection is skipped, so the default is the old one. Nothing between the option's old and new place reads it, and with the option given explicitly the generated files are as before |
| `src/test/framework/mlxf_test_utils.f90` | `cpu_only_mlx` is "neither backend". The no-device skip names the backend (`no_device_skip`). New `metal_check_runs(what)`: on a CUDA GPU it prints `SKIP: Metal-only check on a CUDA build: <what>`; without a GPU it acts as `gpu_check_runs` | on Metal and CPU-only every result and every skip line is what it was (the Metal skip text is unchanged) |
| `src/core/runtime/mlxf_device_tester.f90` | `test_backend` asks both backends and prints `CUDA backend:` beside `Metal backend:`. Its two assertions now cover both: "one and stable", "without a GPU backend no GPU". On the no-GPU path `cpu_only_mlx()` replaces "not Metal". On a GPU, `memory_size` and `max_buffer_length` are checked on Metal; on CUDA the skip is named and `total_memory`, `free_memory` and the `sm_` architecture get the same three assertions | assertion counts unchanged on every session; one new output line |
| `src/core/runtime/mlxf_error_tester.f90`, `mlxf_stream_tester.f90`, `src/core/io/mlxf_io_tester.f90` | the recovery gate, the memory and wired limits, the Metal capture and `unit_io`'s failed evaluation beyond the maximum buffer go through `metal_check_runs` | `metal_check_runs` is `gpu_check_runs` on Metal and CPU-only |
| `scripts/check_rules.py` | rule `devquery`: the session classifier (`mlxf_test_utils.f90`) and every outside program that asks for the GPU count must call both `mlx_metal_is_available(` and `mlx_cuda_is_available(` | a rule of the tree; holds on the changed tree |
| `test/consumer/mlxf_consumer.f90`, `mlxf_example_errors.f90`, `mlxf_example_differences.f90`, `mlxf_example_user_safety.f90` | `gpu_backend` from both queries (two statements, no impure function inside `.or.`); the CPU-only branch tests it; session and SKIP texts name Metal or CUDA | the branches taken are the same on a Mac. The printed session and SKIP texts change (decision below); exit statuses do not |
| `doc/quickstart.md` | the devices row and the session example | the example is the program's new text, verbatim |
| `scripts/ci_cpu_job.sh` | a CPU-only job needs `Metal backend: F` and `CUDA backend: F` | the macOS CPU-only job's MLX has neither backend |
| `doc/policies/test_environment_policy.md`, `doc/policies/binding_contract_policy.md` (sections 7 and 16) | the session table (Metal and CUDA, each with or without a GPU, and CPU-only), the Metal-only checks, `MLXF_REQUIRE_GPU`'s new default, the backend queries | documents |

`scripts/ci_linux_job.sh` and `src/test/framework/mlxf_test_registry.f90` needed no change. The Linux job runs
`ci_cpu_job.sh`. `guard_float64_on_gpu` keeps its `gpu` tag and runs on a CUDA GPU, since MLX refuses float64 on any
GPU stream.

**Evidence** (*measured*; the CUDA builds were built and linked, never run):

| Check | Result | Log |
| --- | --- | --- |
| CPU-only Debug, from scratch | 4.7 s (load 0.21), 0 warnings, fast gate 13 of 13, `check_tree: passed`, installed | `cpu_build_debug.log` |
| CPU-only Release, from scratch | 18.4 s (load 1.52), 0 warnings, fast gate 13 of 13, installed | `cpu_build_release.log` |
| Counts against Phase 0 | every entry, both builds: groups, assertions and SKIP lines identical (4,483 assertions, 34 guard members, the five GPU-only skips word for word); the device report adds `CUDA backend: F` | `area_counts_cpu.md`, `LastTest_cpu_*.log` |
| Named-only sub-suites (Release) | `recovery_half` the same skip, `polar_shiftmap_accuracy` 24 of 24, `distributed_ring` 14 of 14 on each rank | `named_release_*.log` |
| CUDA Release / Debug against `install-cuda-final` with `MLXF_CUDA_STUB_DIR` | 18.5 s (load 2.20) / 4.7 s, 0 warnings, `mlxf_test_exec` linked, only `libcuda.so.1` unresolved, "MLX is a CUDA build" at configure | `cuda_build_{release,debug}.log` |
| `MLXF_REQUIRE_GPU` not given | CPU-only: OFF; CUDA MLX: ON, and the definition reaches `mlxf_test_exec`; the driverless hint without the stub option | `require_gpu_default.log` |
| Rule `devquery` | before the consumers changed it failed on all four; plants on a copy of the tree: the classifier without its CUDA query fails, a consumer without it fails; restored, every rule holds | `devquery_before_consumers.log`, `devquery_plant.log` |
| `check_rules.py` with `MLXC_ROOT` (mlx-c's real headers) | every rule holds, the parity ledger included | `check_rules_with_headers.log` |
| `check_install.sh` (CPU-only Release) | passed: consumer and examples (`session: a CPU-only MLX; ...`), API list, lifetime checker, isolation, pkg-config | `check_install_release.log` |
| `check_embed.sh` | passed (the moved option under `add_subdirectory`) | `check_embed.log` |
| Static gate | passed; `doc/code_base_map.md` current | `check_tree_end.log` |

**Review.** A subagent reviewed the diff against decisions 4 and 5 and the house rules without my conclusions. It
found no bug on Metal or CPU-only sessions: counts and SKIP lines are unchanged in every tester, the rules hold, the
option move is safe and the quickstart block is verbatim. Its points, and what was done with each:
- **"No NVIDIA driver" cannot be a session**, since `libmlx.so` needs `libcuda.so.1`: corrected in the refusal
  message, the comments, the consumers, the quickstart and both policies.
- **The memory comment of the CUDA branch** wrongly named `cudaMemGetInfo` (MLX reads NVML first): corrected.
- **The detection was silent when no `libmlx.so` lay beside libmlxc**: a status line now says so.
- **Not done, with reasons:** the whole `test_limits` stays gated on Metal; the consumers' Metal SKIP text changes.
  Both are in the decisions below.
- **Phase 3's:** `mlxf_fast_tester.f90:570` (`test_cpu_refusal`) keys its expected message on `cpu_only_mlx()`, which
  is now false on CUDA. On a CUDA GPU it would expect "GPU" where MLX says "No Metal back-end". The
  threadgroup-limit assertion of the same tester is decision 7's. Both are in `src/core/fast/`, Phase 3's.

All of this was rebuilt and rerun (the table above is the final sources').

Decisions taken under delegation:

- **A CUDA build without a GPU is treated like Metal without a device:** nothing allocates, the library refuses by
  name, and the tests skip, or fail under `MLXF_REQUIRE_GPU`. This follows from MLX's allocator (above).
- **Counts held equal on Metal and CPU-only by rephrasing, not adding:** `test_backend`'s two assertions now cover
  both backends; the CUDA branch of the device information makes as many assertions as the Metal branch.
- **`test_limits` gated whole on Metal**, the memory-limit part with the wired limit. A split would add a skip
  line on CPU-only. `mlxf_memory_tester`'s own limit test still runs on any device.
- **The CUDA build is recognised from `libmlx.so`'s dynamic section.** MLX's installed headers and CMake package
  differ between CPU-only and CUDA builds only in the line `if(ON)`, while `NEEDED libcuda.so.1` is a fact of
  the library itself.
- **`MLXF_REQUIRE_GPU` declared after the dependencies**, so that its default can see them.
- **The outside programs say "Metal or CUDA"** in their session and SKIP lines, and the quickstart with them. On a
  Mac the printed text of these examples changes; their branches and exit statuses do not, and `check_install.sh`
  matches only `^SKIP`.
- **Rule `devquery` holds the classifier itself to both queries**, as well as the consumers: the classifier is
  where a missing CUDA query would misclassify every test.
- **A configure-time hint** names `MLXF_CUDA_STUB_DIR` when a CUDA MLX meets a host without a driver.
- **For the record (Phase 5):** `README.md` (lines 86, 116), `doc/how2s/how2set_up_dev.md:57`, the register
  (`doc/architecture_principles.md:221`) and the skill reference `testing.md` still describe three sessions.
  README and the setup guide are Phase 5's files; the register and the skill are proposals for Hans.

Exit:

- CPU-only counts unchanged in Debug and Release: met (table above).
- The CUDA build of the library and `mlxf_test_exec` links with zero warnings: met, Debug and Release. Nothing was
  run.
- Rule `devquery`'s plant fails: met, both plants.
- The test policy updated: met (section 4), and the binding policy's sections 7 and 16.

What it means, in short:

- The library and its tests now know four kinds of session: Metal and CUDA, each with or without a GPU, plus
  CPU-only. On a Mac and on CPU-only Linux every count and every skip line is as before.
- On a CUDA machine the Metal-only checks skip by name and CUDA's own device facts are checked in their place.
  This is code never run: Part C runs it first.
- A CUDA build of MLX is recognised at configure time and requires a GPU by default, as a development Mac does.

### Phase 3, the kernel API and its tests: done (2026-11-27, 10:50 to 11:25 EST, resumed under R1 11:25 to 11:30, dell2)

Same session, base `1426c10`. **Ruling applied** (decision 6, ruled 2026-11-27): option A, `mlx_custom_kernel` built
from `mlx_custom_kernel_spec`, "renamed in the same change. Phase 3 proceeds". Evidence:
`/home/hael/agent_runs/mlxf_cuda_prep/scratch/keep/phase3/` (`keep/phase3/` below). About 45 minutes (*measured*)
of the 180-minute box.

**The ruling reaches six K-run files.** The rename has users in `src/test/toys/` (the polar workspace and its tail,
the projector workspace) and `src/test/bench/` (the insertion probe, the kernel forms and their sources), which
section 4 otherwise keeps out of Part A. The ruling says "renamed in the same change", decision 6 notes "no user
outside this tree", and rulings override the plan where they differ. So the six files were added to the file table
for Phase 3 with "decision 6's rename and nothing else", and that is all they received:
`keep/phase3/toy_bench_rename_check.log` shows each file equal to HEAD's once the rename is reversed and whitespace
(the formatter's realigned columns: the new name is one character longer) is ignored. 126 lines in all.

**Merge note for the controller:** a K run (K3 is running) that adds a use of `mlx_metal_kernel` or its spec after
this base renames it on merging; conflicts on these 126 lines are the rename alone.

**Ruling R1 applied** (2026-11-27, after the fence's stop of this phase). The row the run added named
`..._workspace_tail.f90` and the two kernel-forms bench files without their directories. The fence matches full
paths only, so it refused `src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90` when the phase ended
(`logs/phase_3_fence.txt`) and the driver stopped the phase. R1 ruled it an omission of the table's form, not of
its scope: the row names the six files by their full paths, as the controller edited it.

Phase 3's work stood, and the phase resumed at 11:25. On the unchanged tree:
- the static gate and every rule held, the rules with mlx-c's real headers;
- the CPU-only Release tree rebuilt and passed the fast gate, 13 of 13;
- `check_cuda_sources.sh` passed again.
All of it is in `keep/phase3/gates_after_R1.log`. Every file this phase changed lies in a Phase 3 row of the
corrected table, each checked by path. Lesson for later rows: name each file by its full path from the repository
root.

**Rows added to the file table** before their files were edited:
- the six files above;
- `mlxf_test_registry.f90` gains Phase 3 (the kernel guards renamed, the named-only sub-suite);
- `scripts/mlxf_consumer_checks.py` (the installed lifetime checker's list of handle types);
- `test/mlxf_test_exec.f90` (the argument `records=`);
- `apple_questions.md` gains Phase 3 (item 40);
- `doc/api_reference.md` (added in Phase 2 for Phases 2 and 3).

**The kernel (decision 6):**
- **The spec:** `mlx_custom_kernel_spec` in `src/defs/mlxf_defs.f90` is the old spec plus `cuda_source` and
  `shared_memory` (bytes, default 0). `header` serves both backends: CUDA compiles it with NVRTC, where a plain
  function is device code. No kernel in the tree needs a separate CUDA header, so none was added (the API grows
  with a need; section 12 says when).
- **The type:** `mlx_custom_kernel` (`src/core/fast/mlxf_fast.f90`) holds Metal's kernel and launch configuration
  or CUDA's, and reads `mlx_cuda_is_available()` once when it is built. A CUDA build takes the
  `mlx_fast_cuda_kernel_*` path with `cuda_source`, `shared_memory` and the same grid, threadgroup, outputs,
  templates, initial value and verbosity. Any other build takes the old Metal path, mlx-c call for mlx-c call, a
  CPU-only MLX included.
- **The refusal:** a spec without the backend's source is refused. `call k%new(spec, status=st)` returns a status
  and a message and leaves the kernel empty, so a toy runs its graph form; without `status` it stops. The checks
  run in HEAD's order: name, source, then the rest.
- **Lifetime:** counted handle, assignment, `kill` and finalization as before, keyed on whichever handle the object
  holds. A failed build frees its configuration once.
- **Re-exports and rules:** `mlxf.f90` re-exports the two new names. Rule `entry`'s `ENTRY_IF_LIVE` lists
  `custom_kernel_assign` and `_kill`, whose guard keeps the `if( c_associated(...) ) call mlxf_guard_thread` form
  the rule reads.
- **Parity ledger:** the 13 `mlx_fast_cuda_kernel_*` lines move from `excluded` to `public` (`_new` as
  `mlx_custom_kernel`, `_apply` as `mlx_custom_kernel%apply`) and `plumbing` (the configuration). The Metal lines
  take the new name.
- **ABI probe:** it already listed `mlx_fast_cuda_kernel` and `_config` at the base (`mlxf_abi_probe.c:146-147`),
  so nothing changed there.
- **Regenerated:** the API list (317 names) and the API reference.

**The wrapper's tests (decision 7)** (`src/core/fast/mlxf_fast_tester.f90`):
- **Spec functions:** every test kernel now comes from a spec function holding both sources: the column (its
  strided form too), the two-dimensional grid, two by two, the template, the histogram, the power, iota and the
  broken one.
- **The CUDA sources:** each takes its index as `blockIdx * blockDim + threadIdx` and compares it with the extent.
  MLX's CUDA launch is `ceil(grid/threadgroup)` blocks of `min(threadgroup, grid)` threads, so the column and the
  two-dimensional grid need the guard (the grid of (6, 4) in blocks of (4, 2) runs 8 threads along x). iota's
  launch is exact. They use `atomicAdd` on plain outputs, `complex64_t`'s `real()` and `imag()`, and `scale[0]` for
  the rank-0 input.
- **The threadgroup check:** "a threadgroup above the device's limit fails" runs through `metal_check_runs`, so a
  CUDA GPU skips it by name (CUDA clips the block).
- **The CPU refusal:** it expects "GPU" in MLX's message on Metal and CUDA and "No Metal" on a CPU-only MLX, both
  true of the new path.
- **Messages:** three assertion texts follow the rename ("mlx_custom_kernel apply", "MLX has no float64 on the
  GPU", "a custom kernel").
- **Not counted in the gate:** the new checks live in the named-only sub-suite `unit_fast suite=kernel_sources`,
  out of the fast gate (acceptance 1 holds the gate to the base's counts). It checks that every applied test kernel
  carries a CUDA source, and that a spec without its backend's source is refused through `status`. With
  `records=<dir>` it writes one record per application: the spec, and the dtypes and ranks of the inputs a test
  gives it. 22 checks (*exact*).
- **The registry:** it registers the sub-suite (`NAMED_ONLY(5)`). Its two kernel guards are renamed, and the
  guard's spec carries both sources, so it stops for the missing output on either backend.

**`scripts/check_cuda_sources.sh` (decision 9, new):**
- **Records:** it runs `mlxf_test_exec test=unit_fast suite=kernel_sources records=<tmp>` from any build that runs
  here (the CPU-only one on dell2).
- **Wrapping:** it wraps each CUDA source exactly as MLX 0.32.4's `build_kernel` does, with the function named as
  MLX names it, the default header, inputs, outputs, the shape, strides and rank parameters, the templates and
  `cg`. It refuses an MLX other than 0.32.4, in `MLX_SRC` or under the build's mlx-c, until its wrapping is
  compared again.
- **Compiling:** it compiles with **NVRTC through Python's `ctypes`**, with MLX's options (`jit_module.cpp`:
  `--device-as-default-execution-space`, `--gpu-architecture`, MLX's device headers from the tag, the prefix's
  CCCL, the toolkit's headers), for `sm_100a` and `sm_120a`. It prints "compiled with NVRTC, not run".
- **Expectations:** a record marked "expect fail" (the broken source) must not compile. `--plant` adds a source
  expected to compile that does not, and the check must then fail.
- **Not in the static gate:** it needs a built `mlxf_test_exec`, a toolkit and MLX's source, which the static gate
  has none of. So `check_tree.sh` is unchanged (the table's "if it runs there").

Results (*measured*, `keep/phase3/check_cuda_sources.log`, on the Release tree):

| Record | `sm_100a` | `sm_120a` |
| --- | --- | --- |
| column, column strided, grid 2D, two by two, template (3, true), histogram, power, iota | compiled | compiled |
| template (-2, false) | MLX's: its name `custom_kernel_mlxf_test_template_float_-2_f` is not an identifier; the source compiles under `..._float__2_f` | the same |
| broken (expected not to compile) | fails, as expected | fails, as expected |
| `--plant` | the planted record fails to compile: exit 1 | the same |
| `MLX_SRC` claiming MLX 0.33.4 (a copy with `version.h` changed) | refused before anything is compiled: exit 2 | |

**Two findings.**
- **MLX question 40.** MLX's CUDA backend names a kernel `custom_kernel_<name>_<value>` and keeps the `-` of a
  negative integer template argument. The Metal path turns `-` into `_` (`make_template_hash`). So on a CUDA GPU
  the test "a negative integer parameter compiles" will fail as MLX's. Item 39 has the source lines and the
  reproducer. The test is not loosened. After its failed assertion it now returns instead of reaching an unchecked
  `mlx_to` that would have stopped the whole `unit_fast` process (the review below); on Metal and CPU-only it runs
  exactly as before.
- **NVRTC's builtins at run time.** `libnvrtc.so.12` opens `libnvrtc-builtins.so.12.9` by name and has no run
  path, so the check needs the toolkit's `lib64` on the loader path. So will MLX's JIT at run time when the toolkit
  is outside the loader's default path, as on dell2. That amends Phase 1's "only the driver comes from the
  system": the toolkit's `lib64` must be on `LD_LIBRARY_PATH` or in `ld.so.conf` (a system toolkit is usually the
  latter). It is for Phase 5's record and Part C's bring-up.

**Policies:**
- **The binding policy:** section 12 is rewritten for both sources (the spec's table, the refusal, what MLX
  generates on CUDA, the launch and its guard, errors on both backends, question 40, the gates). Sections 6 and 9
  name the new type.
- **The test policy:** the threadgroup check joins the Metal-only list, and `kernel_sources` is described among
  the named-only sub-suites.
- **`test/CMakeLists.txt`:** its comments follow.
- **`README.md:114`** still names the old type: README is Phase 5's file.

**Evidence** (*measured*; the CUDA builds were linked, never run):

| Check | Result | Log |
| --- | --- | --- |
| CPU-only Debug / Release from scratch | 0 warnings, fast gate 13 of 13 each, `check_tree: passed`, installed | `cpu_build_{debug,release}.log` |
| Counts against Phase 0 | identical in both builds: every entry's groups and assertions and every SKIP line | `area_counts_cpu.md` |
| CUDA Release / Debug | 0 warnings, `mlxf_test_exec` linked, only `libcuda.so.1` unresolved | `cuda_build_{release,debug}.log` |
| `check_cuda_sources.sh` and its plant | above | `check_cuda_sources.log` |
| `check_install.sh`, `check_embed.sh`, `check_toy_offstate.sh --exec` (CPU-only Release) | passed; the toys' host-route table equals `mlxf_test_exec`'s (135 lines) | `check_install_release.log`, `check_embed.log`, `check_toy_offstate.log` |
| Static gate | passed | `check_tree_end.log` |

**Why macOS is unaffected:**
- **The library:** without CUDA, a kernel is built, applied, copied and released with the same mlx-c calls in the
  same order as at HEAD. The checks run in HEAD's order. The one new stop, a negative `shared_memory`, needs a
  value no spec sets. Only names change: the type and its spec, and the messages' procedure names.
- **The tests:** every assertion on Metal is the one it was (three texts renamed). The threadgroup check runs on a
  Metal GPU as before (`metal_check_runs` is silent there). The template test's new `return` is taken only after a
  failure. The new checks are named-only.
- **The toys and benches:** the identifier only, so the identity set and the timing gates are untouched in
  substance.
- **The scripts:** Linux and CUDA tools, or the handle-type list. The controller's M5 run is the check.

**Review.** A subagent reviewed the diff against decisions 6, 7 and 9 without my conclusions. It confirmed the
lifecycle (no leak, double free or wrong-handle free, Metal and CUDA objects assigned either way), the CUDA sources
against MLX's generated signature and launch, the unchanged Metal and CPU-only counts, the wrapping against MLX's,
and the ledger.

Fixed after it:
- the unchecked `mlx_to` after the negative-template failure (a whole-process stop on CUDA);
- the Metal check order (restored to HEAD's);
- the script: it now refuses another MLX version, says that the MLX-caused record fails on a GPU, reads the
  records as bytes, handles `--plant` with no records, checks for a missing cache, and its `--help` prints the
  header only;
- the histogram's literals, now module constants;
- a 4-line procedure comment.

Left as decided:
- `records=` is accepted beside any test, as `device=` is.
- The hand-written list of applications in `kernel_sources`: a test that adds a kernel adds its line, and the
  comment says so.
- README is Phase 5's file.

Decisions taken under delegation:

- **The six K-run files renamed in Phase 3** under the ruling (above), the rename only, proved by reversal.
- **One shared `header`**, no `cuda_header`: no kernel needs one; NVRTC compiles the existing header.
- **A non-CUDA build keeps the Metal path**, a CPU-only MLX included, so its refusal message ("No Metal back-end")
  and every count stay as they were.
- **The refusal of a missing backend source goes through `status`** on `new`, because a toy must be able to fall
  back. The function form stops, as a constructor without a status does.
- **New checks only in a named-only sub-suite**, since acceptance 1 holds the gate to the base's counts.
- **Records from the test executable, not from the Fortran text:** the wrapper's signature depends on the input
  dtypes and ranks a test applies, which only the test knows. `mlxf_test_exec` accepts `records=`, so nothing is
  written where the sub-suite is run by hand without it.
- **NVRTC through `ctypes`, not `nvcc`:** nvcc has no `--device-as-default-execution-space`, and MLX compiles with
  NVRTC. The plan's "needs nvcc" becomes "needs the toolkit's libnvrtc".
- **MLX's naming mirrored exactly:** a failure MLX causes is reported as MLX's only when the source compiles under
  a valid name, which pins the defect and still proves the source.
- **`check_cuda_sources.sh` not in the static gate:** it cannot run without a build, a toolkit and MLX's source.

Exit:

- Acceptance 1's wrapper part: met. The wrapper's tests compile on all three builds: CPU-only Debug and Release
  run them, and CUDA Debug and Release link them. `check_cuda_sources.sh` compiles every CUDA source of the
  wrapper's tests (the MLX-caused record proven sound), and its plant fails.
- The API list and the binding policy's section 12 follow decision 6: met (`mlxf_api_names.f90` regenerated, the
  rename and the CUDA side in section 12).
- The parity ledger's CUDA kernel lines public or plumbing: met.
- The ABI probe lists the CUDA handles: met, at the base already.
- Zero warnings in every build; the static gate passes: met.

What it means, in short:

- One kernel type now carries a Metal and a CUDA source. A kept kernel gains a CUDA source and changes nothing
  else, which is the MLX-centric rule's promise. Part B writes the toys' twins into it.
- Every CUDA source of the wrapper's tests compiles for both Blackwell targets exactly as MLX will compile it.
  dell2 can check Part B's twins the same way before anyone reaches a GPU.
- Part C should expect one test to fail as MLX's (a negative template integer, question 40). It also needs the
  toolkit's `lib64` on the loader path for MLX's NVRTC.

### Phase 4, the memory guard and the session script: done (2026-11-27, 11:27 to 12:00 EST, dell2)

Same session, base `1426c10`. Rulings: none new (R1 concerned Phase 3's table row; this phase's rows already name
full paths). Evidence: `/home/hael/agent_runs/mlxf_cuda_prep/scratch/keep/phase4/` (`keep/phase4/` below). About 33
minutes (*measured*) of the 120-minute box. Files changed: `scripts/run_parts.sh`, `scripts/cuda_session.sh`
(new), `src/test/bench/mlxf_bench_polar_table.f90` (its memory budget only) and this note.

**`scripts/run_parts.sh` reads the card (decision 8).** A CUDA host is one where `nvidia-smi` answers for the first
device `CUDA_VISIBLE_DEVICES` names (an index, UUID or PCI id; device 0 when unset; none when set empty); macOS is
never one, since there host memory is the GPU's. On a CUDA host:
- **The guard** keeps its host check and adds the card's. Each earlier split's share of the card, its peak used
  memory less what the card held before it started and divided by its processes, predicts the new split with
  the rule the host guard already uses: from one split, N times its value; from two or more, the line through the
  two finest against 1/n. A split predicted above `RUN_PARTS_MEM_SHARE` of the card's free memory (`nvidia-smi
  --query-gpu=memory.used,memory.total`, total less used, now) is not run (exit 3), and so is one with no measured
  split on the card.
- **While the parts run,** the card's used memory is sampled once a second, as host memory is.
- **The series table** gains five columns at its end: the card's total, its used memory before the start, its peak,
  the parts' share of the peak, and the predicted share. The summary names the card's numbers and the compute
  processes on it before the start (decision 15's record).
- **Elsewhere** (macOS, a CPU-only Linux host) every line the script writes is as before: the same 24 columns, the
  same summary and samples.

**The polar-table bench's budget (decision 8).** `budget_bytes` reads `budget_key()`: Metal's `memory_size` as
before, or on a CUDA build the card's `total_memory`, since CUDA reports no `memory_size`. The printed line names the
key, so it is word for word the old line on Metal. On a CPU-only MLX the bench stops as before (the GPU reports no
`memory_size`), with the message naming the key. On CUDA a `device=cpu` run is budgeted from the card too, which
on a discrete card is not the host's memory: Part C reads that row with this in mind.

**`scripts/cuda_session.sh` (decisions 10, 11 and 17, new).** One command, `MLXC_ROOT` set; `CUDA_HOME`, `MLX_SRC`,
`CUDA_VISIBLE_DEVICES`, `--cases` and `--grid` as needed. It writes everything under `build/cuda_session/<date>`
(or `--out`) and packs it as `<dir>.tar.gz` without the build trees and MLX's caches.

The machine's facts it records:
- `nvidia-smi -q` and `-L`, the driver, nvcc, `mlxf_deps.txt` (cuDNN, host compiler, architectures);
- glibc, the compilers, the CPU, memory, the load;
- the commit and its count of uncommitted files.

Then, with fixed parameters and every step a row of `steps.tsv` (wall time, the load and the card's processes
before it):

| Step | What it runs |
| --- | --- |
| build | Debug and Release from scratch against `MLXC_ROOT`, warnings as errors, the tests (`MLXF_REQUIRE_GPU` ON on a GPU session) |
| E1 | the fast gate in both builds with their CTest transcripts and per-entry counts; the named-only sub-suites in Release (`distributed_ring` aside: NCCL is out of scope, decision 16); `check_cuda_sources.sh` when `MLX_SRC` and NVRTC are there |
| E2 | `bench_user_costs suite=costs device=all`, two invocations |
| E3 | `run_parts.sh` at 1, 2, 3, 4 and 6 parts (`nthr` = cores / parts) on the polar table (`suite=time`) and its maps (`suite=maps maps=screen ptiles=16`), without and with MPS (`nvidia-cuda-mps-control -d` with its pipe and logs in the session; a refusal is a SKIP line); E3's best part count is the largest summed median rate without MPS |
| E4 | at SIMPLE's sizes, two invocations each: the polar table and its maps on both devices, the projector (`suite=time`, GPU only), the PCG reconstructor at n = 160 and 256 on both devices |
| E5 | the accuracy suites on the GPU: the polar table, the projector, the reconstructor at n = 160 (the named-only accuracy sub-suites ran in E1) |
| E6 | `tail=graph` against `tail=metal` and `form=graph` against `form=fused` at one process, and the tail at E3's best part count through `run_parts.sh` |

A GPU session needs `nvidia-smi` to list a GPU and the MLX under `MLXC_ROOT` to be a CUDA build (`libmlx.so` links
`libcuda.so.1`). Elsewhere each GPU part prints `SKIP <step> (<what>): <reason>` and the CPU parts run. `--gate` runs
facts, build and E1, packs, and exits 1 on any failure (decision 17). The full session exits 1 only when the build
or E1 failed; E2 to E6 are reported, not gated (decision 11).

**Run on dell2 (exit, *measured*):**

| Run | Result | Log |
| --- | --- | --- |
| `run_parts.sh` with one part, then two, base and new script, a test double, no `nvidia-smi` | all exit 0; same header, 24 fields per row, same summary and samples layout | `run_parts_test/run_tests.log` (A) |
| the same with a fake card on `PATH` (80 GiB, 2 GiB per part) | exit 0; the card's columns; the parts' share 2 GiB and 4 GiB, the two-part split predicted at 4 GiB from the one-part one | (B) |
| plant: the same card nearly full (79,000 of 81,920 MiB used) | two parts not run by the card's guard, exit 3, with the free memory in the message | (C) |
| `cuda_session.sh`, full, a CPU-only session (`MLXC_ROOT` CPU-only, `MLX_SRC`, CUDA 12.9 for NVRTC) | exit 0 in 1,012 s (load 0.00 at the start, about 1.0 during the CPU parts): 15 steps ok, 9 SKIP lines, E1 passed; the session's fast-gate counts identical to Phase 0's in both builds | `session_full_steps.tsv`, `session_full_summary.txt`, `session_full_facts.txt`, `session_full_skips.txt`, `area_counts_session.md`, `session_full.tar.gz` |
| `cuda_session.sh --gate` (after the transcripts were added to E1) | exit 0 in 127 s (load 0.74): build and E1 passed; its tarball holds E1's logs, both CTest transcripts and the counts | `session_gate2.log`, `session_gate2_contents.txt`, `session_gate2.tar.gz` |
| the polar bench's change in the CUDA builds (`install-cuda-final`, `MLXF_CUDA_STUB_DIR`) | Release 18.0 s, Debug 4.8 s, zero warnings, `mlxf_test_exec` linked (not run) | `cuda_build_{release,debug}.log` |

The CPU parts it ran on dell2 *(measured)*:
- the fast gates: 15.9 s in Release and 15.3 s in Debug;
- `reconstructor_pcg_n32`: 60.6 s;
- the CUDA sources compiled with NVRTC: 9.6 s;
- `user_costs` on the CPU: 1.4 s and 1.1 s;
- the reconstructor on the CPU at n = 160: 80.7 s and 81.0 s;
- the reconstructor on the CPU at n = 256: 359.8 s and 361.6 s (16 threads).

**Why no benchmark ran under `run_parts.sh` on dell2.** None of the series runs on a CPU-only MLX:
- the polar table stops at its budget (the GPU's memory) and needs SIMPLE's case file;
- the projector's `suite=time` selects the GPU ("Cannot set gpu device without gpu backend");
- the kernel-forms benchmark is GPU-only (`keep/phase4/probe_bench_costs.log`).

So `run_parts.sh` ran with two parts of a test double of the launcher's protocol (`run_parts_test/bin/fake_bench`:
the ready file, the go file, a row of the series columns). The card's path ran against a fake `nvidia-smi`
(`run_parts_test/fakegpu/`). Neither is in the repository. Part C runs the real benches on the card (E3).

**Why macOS is unaffected:**
- **`run_parts.sh`:** the card's code runs only where `nvidia-smi` answers off Darwin; on macOS `CUDA_GPU` stays
  empty, and every write is the old one (test A shows it on Linux).
- **The polar bench:** `budget_key()` is `memory_size` unless MLX is a CUDA build, so the budget and the printed
  line are as before.
- **`cuda_session.sh`:** new, Linux only (it refuses elsewhere).

Decisions taken under delegation:

- **The card guarded beside the host, not instead of it:** a part holds host memory too.
- **The card's share predicted per process from a device-wide peak:** `nvidia-smi` gives the card's used memory,
  not each part's, so a split's share is divided by its parts.
- **The card's columns only on a CUDA host:** the table and summary elsewhere stay byte for byte, the macOS gates'
  readers included.
- **The polar bench on a CPU-only MLX left as it was:** MLX reports no memory for its CPU device, and the plan gives
  Part A the budget on CUDA only.
- **`run_parts.sh` tested with a test double and a fake `nvidia-smi`**, since no benchmark of the series runs on
  dell2's CPU-only MLX (above).
- **The session's fixed parameters:**
  - `nthr` = cores / parts in E3;
  - `maps=screen ptiles=16` (the suite's defaults) for the maps;
  - `case=2500_4` (the bench's default) for the polar table;
  - two invocations wherever a rate is taken;
  - the reconstructor's accuracy at n = 160;
  - `distributed_ring` not run.
  Each is written into the script's steps, so Part C changes them in one place.
- **SIMPLE's case and grid files are inputs** (`--cases`, `--grid`), not repository files: they are SIMPLE's
  measured cases, which Hans brings (no SIMPLE data in the repository). Without them the polar steps print a SKIP line.
- **The session builds its own Debug and Release trees** from the checkout, so a session is one command and its
  trees match the commit it records.

Exit:

- `run_parts.sh` with two parts run to the end on dell2: met, with a test double (the reason above), the card's path
  on a fake card, and the card's guard planted.
- `cuda_session.sh` run to the end on dell2: met. The full session ran its CPU parts and printed a SKIP line per GPU
  part; `--gate` passed.
- Zero warnings in every build; the static gate passes (`keep/phase4/check_tree_end.log`).

What it means, in short:

- At work one command builds both trees, runs E1 to E6 and packs one small tarball with the machine's facts. On
  dell2 the same command runs everything a CPU can and names each step it cannot.
- When parts share a card, the launcher now guards and records the card's memory, the resource that runs out
  first on a discrete GPU, beside the host's.
- Nothing of E2 to E6 has run on a GPU, and the polar steps wait for SIMPLE's case and grid files at work.

### Phase 5, the record: done (2026-11-27, 11:59 to 12:10 EST, dell2)

Same session, base `1426c10`. Rulings: none new; R1 (Phase 3) is recorded in the report and the history. Evidence:
`/home/hael/agent_runs/mlxf_cuda_prep/scratch/keep/phase5/` (`keep/phase5/` below). About 11 minutes (*measured*) of
the 90-minute box. Files changed: `doc/how2s/how2set_up_dev.md`, `README.md`, `doc/policies/binding_contract_policy.md`,
`doc/implementation_notes/planned/mlxf_roadmap.md`, `doc/implementation_notes/README.md`, `doc/history/2026-11.md`,
`doc/implementation_notes/completed/mlxf_cuda_report.md` (new) and this note. `doc/code_base_map.md` needed no
regeneration (`generate_codeoverview.py --check`: up to date).

**The setup guide** gains section 8, Linux with CUDA: the toolkit (12.8, 12.9 or 13.0, the driver each needs, the
runfile's components where NVIDIA's installer cannot run), cuDNN 9, nvcc's host compiler, the glibc 2.41+ edit of CUDA
12's math header (the six declarations and the one-line `sed` that keeps the original; CUDA 13.0 needs none),
`build_mlx_deps.sh --cuda` and `--cuda-arch`, the build (`MLXF_REQUIRE_GPU` ON by default, `MLXF_CUDA_STUB_DIR` on a
host without a driver), what a program needs at run time, `check_cuda_sources.sh`, `cuda_session.sh` and question 40.
Its run-time facts were checked against MLX 0.32.4's `mlx/backend/cuda/jit_module.cpp` (*exact*): NVRTC's headers from
`CUDA_HOME` or `CUDA_PATH`, else `/usr/local/cuda`; the PTX cache under the temporary directory
(`mlx/<version>/ptx`) unless `MLX_PTX_CACHE_DIR`. Its session sentence (line 57) names the four sessions, and section 7
no longer says MLX has no GPU backend in this project.

**The binding policy** says what a discrete card changes and what it does not (section 4): every rule holds; a host
access to a GPU array moves the buffer with a copy, so a view is correct and costs a transfer, and `mlx_alloc`'s
buffer is copied (`zero_copy` false); the cost per byte is E2's, measured at work. Section 8: a card's memory is its
own (MLX's limit 95 % of it and soft, `run_parts.sh` guards it), CUDA's device keys, `mlx_set_wired_limit` without
effect on CUDA. Sections 10 and 17: a graph that crosses the devices is "unified memory, no copy; on a CUDA card a
transfer MLX manages".

**README:** the sessions sentence with `mlx_cuda_is_available`, the API rows (`mlx_custom_kernel`, the backend
queries), a CUDA paragraph under Building, and the Status's link to the report.

**The roadmap** keeps rank 5's row for the three parts (Part A now "rank 5a") and gains rank 5a's row for this run;
**the index** links the report and says what Part A delivered; **the history** has the delivery and R1 (2026-11-27).

**Why macOS is unaffected:** Phase 5 changed documents only; no script, build file or source.

**Acceptance 1 on the final tree** (`keep/phase5/final_checks.sh`, output `final_checks.out`):

| Check | Result | Log |
| --- | --- | --- |
| `cuda_session.sh --gate`, CPU-only prefix, `MLX_SRC` and CUDA 12.9 for NVRTC (Debug and Release from scratch, both fast gates, the named-only sub-suites, the CUDA sources) | exit 0 in 126 s (*measured*; load 0.16 at the start, about 2 during the builds); Release 18.0 s, Debug 5.3 s; fast gates 16.0 s and 15.4 s | `session_gate5.log`, `gate5_steps.tsv`, `session_gate5.tar.gz` |
| the counts against Phase 0's | identical in both builds (*exact*): 4,483 assertions over twelve unit areas, 33 guard members ok and 1 skipped, the same five GPU-only skips | `gate5_counts.tsv` |
| `check_cuda_sources.sh` on Release's records | 10 records for each of `sm_100a` and `sm_120a`, every one as expected (question 40 named, the broken test kernel refused) | `gate5_cuda_sources.log` |
| the CUDA build of the library and `mlxf_test_exec` (`install-cuda-final`, `MLXF_CUDA_STUB_DIR`), Release and Debug | Release 17.9 s and Debug 5.0 s (*measured*, load 1.3 and 1.9), exit 0, zero warnings; `mlxf_test_exec` linked, the driver's `libcuda.so.1` the only library the loader does not find; not run (no GPU) | `cuda_build_{release,debug}.log` |
| `cuda_session.sh` to its end with GPU skip lines | Phase 4 (1,012 s, 9 SKIP lines, E1 passed), on code Phase 5 did not change | `keep/phase4/session_full_*` |
| static gate | `scripts/check_tree.sh python3` with `MLXC_ROOT` (the CPU-only prefix): passed | `check_tree_end.log` |

Exit: acceptance 1 met on dell2. Its M5 part ("unchanged") is the controller's after the fetch (section 5).

Decisions taken under delegation:

- **The guide states what was built and checked, and nothing more:** only CUDA 12.9 was built; the run-time facts
  come from MLX's source, and the guide says nothing has run on a GPU.
- **Rank 5a as a row of its own** beside rank 5, as rank 2h's delivery has one, so rank 5 keeps the plan's three
  parts.
- **The `build_mlx_deps.sh` header comment** ("only the driver's libcuda.so.1 comes from the system") is not
  Phase 5's file: left for Phase 21 and listed in the report; the guide carries the NVRTC fact meanwhile.
- **The register and the skill's testing reference** still describe Metal's sessions only: proposed in the report,
  not applied (an edit to them needs the maintainer's approval).

What it means, in short:

- Someone at a Blackwell machine can now build MLX with CUDA, the library and its tests from the setup guide and one
  script, and run the bring-up and the measurements with one command.
- The record says plainly what Part A proved without a GPU (it builds, links and compiles every kernel source as MLX
  will) and what only Part C can show (that it runs, and what transfers cost).

### After Part A (2026-11-27, the controller)

- **Independent review** of Part A merged onto K3 (a subagent reading the code, nothing built): one serious
  finding, decision 18 above (the refusal stops instead of falling back; matters first on a CUDA GPU, so it goes to
  Part B, which owns the kernels after K7); two fixed in this result: `run_parts.sh` sets `CUDA_DEVICE_ORDER=PCI_BUS_ID`
  so that an index names the same card for CUDA and `nvidia-smi` (also in `cuda_session.sh`), and an empty
  `nvidia-smi` read no longer aborts it under `set -u`; the pair-list kernel's 32-bit offsets go to Part B with
  decision 18. K3's half without a listed pair was fixed in K3's result. Sound by the review: the backend selection,
  the kernel object's lifetime, the CUDA test kernels' guards, `check_cuda_sources.sh`'s wrapping, CMake and
  `build_mlx_deps.sh`.
