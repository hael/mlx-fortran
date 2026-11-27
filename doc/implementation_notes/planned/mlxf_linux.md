# Linux, CPU only, on dell2: the first step toward CUDA (run `mlxf_linux`, on dell2)

Status, 2026-11-26: planned; decisions stand as recommended under the maintainer's go of 2026-11-26 ("Yes, Linux and
CUDA should come off the not-planned list ... Any prep work we can do on dell2 would be useful"), open to his
review. Base: the commit that holds this plan (the run pins its hash in Phase 0); checked against `90f5932`.
Machine: dell2 only (Ubuntu 26.04, Intel Core Ultra 7 366H, 16 cores, 61 GB, no GPU), in a copy of the checkout,
by arun. It runs beside the K runs on the M5 and shares no machine with them. Supersedes: none. Depends on:
MLX `v0.32.4` and mlx-c `v0.8.0` building on Linux (validated: no; MLX documents a CPU-only Linux build and a
CUDA build, `docs/src/install.rst` at the tag); the roadmap's decision 19.

## 1. Why

Hans, 2026-11-26: Linux and CUDA come off the not-planned list; three machines at work have NVIDIA Blackwell GPUs,
none is reachable from here today, and dell2 is free. mlx-fortran has only ever been built on macOS. Before a CUDA
run can mean anything, the library must build and its suite must pass on Linux, and every place that assumes
Apple (Metal, unified memory, Accelerate, macOS tools, the device names) must be known. The CPU-only Linux build
is that step: it needs no GPU, and dell2 can do it now.

## 2. Contract

- **Delivers:** (1) MLX `v0.32.4` and mlx-c `v0.8.0` built CPU-only on Linux by `scripts/build_mlx_deps.sh`;
  (2) the library, `mlxf_test_exec` and the installed package building on Linux in Debug and Release with
  `MLXF_WERROR=ON` and zero warnings; (3) the fast gate and every unit area passing on the CPU device, every skip
  accounted for; (4) the install, embedding and off-state checks on Linux; (5) a Linux CPU job for CI; (6) the
  inventory of Apple assumptions the CUDA step will meet, and what that step needs from the Blackwell machines;
  (7) a report.
- **Portable fixes only.** A change is made where Linux breaks, guarded so that the macOS build is unchanged in
  behaviour. No public name of `mlxf` changes; the API list (`test/consumer/mlxf_api_names.f90`) holds.
- **No GPU, no CUDA.** Nothing here builds MLX's CUDA backend or claims anything about it.
- **No `sudo`.** The run installs nothing system-wide (arun's fence refuses `sudo`). What needs a package is
  decision 3.
- **Python** the build or the gate runs uses the standard library and nothing newer than 3.7 (dell2 has 3.14).
- **Git is read-only** for the run.

### What the check found (2026-11-26, from the M5 over ssh and in the clones, *measured*)

1. dell2: Ubuntu 26.04 LTS, kernel 7.0, 16 CPUs, 61 GB, load 0.08, 724 GB free on `/`. GCC 15.2 (`gcc`, `g++`,
   `gfortran`), CMake 4.2.3, GNU Make 4.4.1, Python 3.14.4, git 2.53; no `ninja`, no `clang`. GitHub answers
   (HTTP 200). Its own notes: `~/.claude/CLAUDE.md`, and arun's `hosts/dell2.md`.
2. BLAS and LAPACK: `libblas.so`, `liblapack.so`, `libopenblas.so` (OpenBLAS 0.3.32, OpenMP) and `cblas.h` are
   installed; **no LAPACKE header** (`lapacke.h` is in no include directory). MLX's install guide asks for
   `libblas-dev`, `liblapack-dev` and `liblapacke-dev` on Linux.
3. Run `mlxf_dell2_bringup` (2026-11-24): arun works on dell2 for this repository; the static gate passes there
   (rule `parity` finds no mlx-c headers and checks the ledger's form only); the library was never configured.
4. MLX at `v0.32.4` (`~/src/mlx`): option `MLX_BUILD_CUDA` (default OFF); the CPU backend on Linux links BLAS and
   LAPACK; a CUDA build detects the native architecture and appends `a` from SM 9.0 up, and needs cuDNN; the CUDA
   packages want toolkit 12 or newer, driver 550 or newer (580 for CUDA 13), glibc 2.35 or newer. mlx-c `0.8.0`
   exposes `mlx_fast_cuda_kernel_config` beside the Metal kernel's configuration.
5. The tree already guards some Apple parts: `cmake/CompilerConfig.cmake` (`if(APPLE)` around the RPATH and
   header-pad flags; Debug's `-fcheck=all` off Darwin), `test/CMakeLists.txt` (the ABI probe's C compiler falls
   back to the build's elsewhere than macOS; `bench_blas` links Accelerate only on Apple). Not guarded or not
   checked: `scripts/build_mlx_deps.sh` refuses anything but macOS; `release_gate.sh`, `run_parts.sh`,
   `run_fast_gate.sh`, `mlxf_build_jobs.sh` and `check_rules.py` name Darwin, `sysctl`, `dylib`, `applegpu` or
   `/opt/homebrew`; `src/core/runtime/mlxf_libc.f90` binds libc entry points whose types and constants (the
   `stat` structure, `O_*` flags, `errno`) differ between macOS and glibc (the hardening run added file checks
   there).

## 3. Decisions

1. **Scope: CPU only, the whole suite.** The library, the tests and the toys' host and graph forms on MLX's CPU
   device, as the macOS CPU-only CI job runs them (`scripts/ci_cpu_job.sh`): GPU-only checks skip with their
   own line, a no-device skip is a failure.
2. **Dependencies.** The run clones `ml-explore/mlx` and `ml-explore/mlx-c` from GitHub into its scratch and
   builds the pinned tags with `scripts/build_mlx_deps.sh`, which gains a Linux branch: GCC instead of Apple's
   clang, `MLX_BUILD_METAL` absent, `--cpu-only` implied and accepted, the macOS check replaced by a platform
   switch, `mlxf_deps.txt` naming the platform. The macOS branch keeps its commands byte for byte.
3. **LAPACKE (maintainer action, recommended).** Before the launch Hans runs on dell2
   `sudo apt-get install -y liblapacke-dev` (and `libblas-dev liblapack-dev` if absent), as MLX's guide asks.
   Fallback if not: the run builds OpenBLAS (it ships LAPACKE) from its GitHub release into scratch and points
   MLX at it, and records the cost; a CI runner would then need the same.
4. **Portability fixes, where Linux breaks.** In `cmake/`, `scripts/`, `src/core/runtime/mlxf_libc.f90` and any
   other file that refuses Linux; each guarded (`if(APPLE)`, `$<PLATFORM_ID:...>`, `uname -s`, preprocessor
   `__APPLE__`/`__linux__` in C or Fortran with `-cpp`), each listed in the report with why. A libc binding whose
   layout differs gets the platform's layout from a C helper compiled with the build's C compiler, never a
   hand-typed offset for two platforms.
5. **Tests that fail on Linux.** Diagnosed, never loosened. A failure that is MLX's on Linux (a CPU kernel that
   differs from the macOS CPU backend) becomes an Apple question with a direct mlx-c reproducer and a skip with
   its own named line, recorded; a failure of ours is fixed.
6. **CI.** `scripts/ci_linux_job.sh` (modelled on `ci_cpu_job.sh`) and a job in `.github/workflows/ci.yml` on
   `ubuntu-24.04` with gfortran 14 and 15, caching the built MLX like the macOS CPU job. Recommended: yes; the
   job is a cheap second platform for every push. The run writes it and runs the script on dell2; the hosted job
   is first seen on the maintainer's next push.
7. **What stays macOS.** `scripts/release_gate.sh` stays the GPU release gate and refuses without a Metal device,
   as today; `run_parts.sh`'s memory guard reads macOS's counters and gets a Linux branch only if the run needs
   it for a measurement (none is planned).
8. **The CUDA inventory.** Phase 5 writes, in the report, every place the CUDA step will meet with its file and
   procedure: the Metal kernel wrapper and every fused toy kernel (each needs a CUDA twin through
   `mlx_fast_cuda_kernel_*` or falls back to its graph form); device names and the GPU checks of the tests;
   unified-memory assumptions (`mlx_view`'s borrowed pointer, the cost model, the memory guard); `MLX_ENABLE_TF32`
   (MLX's default is on: our CTest sets 0); the parity ledger's exclusion of the CUDA kernel functions; and what
   a Blackwell machine needs (toolkit, driver, cuDNN, the architecture MLX detects). The CUDA plan is written from
   it when a Blackwell machine is reachable.
10. **MLX-centric port** (roadmap decision 19, Hans: "stay as close to the MLX philosophy as possible"). The
    inventory proposes the smallest change that makes the code run on CUDA through MLX itself: mlx-c's
    `mlx_fast_cuda_kernel_*` wrapped beside `mlx_metal_kernel` with the same shape of Fortran spec, so that a
    kept kernel gains a second source string and nothing else; every other difference (device names, memory,
    tests) handled where it is, not by a platform layer. It lists, per kept kernel, how far its Metal source is
    from a CUDA one (threadgroup memory and SIMD-group functions against shared memory and warp intrinsics).
9. **Compilers.** gfortran 15.2 on dell2; the CI job adds 14 (the README's floor). Nothing changes the floor.

## 4. Not in this plan

- MLX's CUDA backend, any GPU, the CUDA kernel wrapper.
- Performance on Linux (no timing is judged; build times are recorded).
- Packages for Linux distributions; other compilers than gfortran; Windows.
- Any change of behaviour on macOS.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement | static gate on dell2; the facts of section 2 re-checked; decision 3 settled |
| 1 | build script | MLX and mlx-c installed under a scratch prefix on Linux; the macOS branch byte for byte as before |
| 2 | portability | Debug and Release with `MLXF_WERROR=ON`, zero warnings, on dell2 |
| 3 | portability, tests | the fast gate and every unit area on the CPU device; skips counted and named |
| 4 | scripts and CI | `check_install.sh`, `check_embed.sh`, `check_toy_offstate.sh --exec` and `ci_linux_job.sh` pass on dell2 |
| 5 | record | the inventory; the report; `git status` shows file-table paths only |

Every phase ends with `scripts/check_tree.sh` and the formatters on touched Fortran files. The macOS side is
checked by the controller on the M5 when the result is fetched (Debug and Release, the fast gate, every unit
area, the static, install and off-state checks): the run cannot, and says so.

## 6. Acceptance

1. On dell2: Debug and Release build with zero warnings; the fast gate passes; every unit area passes on the CPU
   device with the macOS CPU-only job's counts minus the named GPU-only skips (*exact*, listed per area).
2. `check_install.sh`, `check_embed.sh`, `check_toy_offstate.sh --exec` and `ci_linux_job.sh` pass on dell2.
3. On the M5, after the fetch: the same gates as before the run, the toys' identity set byte for byte.
4. The report lists every portability change with its reason, every Linux-only skip with its question, and the
   CUDA inventory of decision 8.

## 7. Rules and stops

- No file outside the table. No test loosened. Nothing installed with `sudo`.
- A test run sets `MLX_ENABLE_TF32=0`.
- **Stops:** a fix that would change behaviour on macOS or a public name; MLX or mlx-c not building on Linux after
  one diagnosis (the error recorded); decision 3's fallback failing too; a phase over twice its box; the static
  gate failing on something the run did not touch.
- **Gates no ruling may waive:** zero warnings; the static gate; the API list; no test loosened; the macOS branch
  of the build script unchanged.

## 8. Phases

### Phase 0, the base on dell2 (box: 60 min)

Pin the base; record the machine, the tools, the BLAS and LAPACK files, whether `lapacke.h` is present; run the
static gate. Exit: the facts in Progress; decision 3 settled (installed, or the fallback chosen).

### Phase 1, MLX and mlx-c on Linux (box: 150 min)

The Linux branch of `scripts/build_mlx_deps.sh` (decision 2); clone the two repositories into scratch; build and
install into a scratch prefix; record the build's seconds, the libraries and `mlxf_deps.txt`. Exit: a prefix with
`libmlx.so`, `libmlxc.so` and mlx-c's CMake package.

### Phase 2, the library on Linux (box: 180 min)

Configure with `MLXC_ROOT` at the prefix, `MLXF_REQUIRE_GPU=OFF`, `MLXF_WERROR=ON`, `FORTLS=OFF`; fix what breaks
(decision 4). Exit: Debug and Release from scratch, zero warnings.

### Phase 3, the suite on the CPU device (box: 180 min)

The fast gate and every unit area, Debug and Release; each failure diagnosed (decision 5). Exit: acceptance 1.

### Phase 4, install, embedding, off-state and CI (box: 120 min)

The three checks on Linux; `scripts/ci_linux_job.sh` and its job in `.github/workflows/ci.yml` (decision 6).
Exit: acceptance 2.

### Phase 5, the record (box: 90 min)

The CUDA inventory (decision 8); `README.md` and `doc/how2s/how2set_up_dev.md` (Linux); the roadmap's rank, the
history, the index; the report with every change, skip and question, and a commit message without attribution
that names every new file. Exit: acceptance 4.

### File table

| File | What | Phases |
| --- | --- | --- |
| `scripts/build_mlx_deps.sh` | the Linux branch | 1 |
| `scripts/mlxf_build_jobs.sh`, `scripts/run_fast_gate.sh`, `scripts/ci_cpu_job.sh` | platform switches where Linux breaks | 1, 2, 3, 4 |
| `scripts/check_install.sh`, `scripts/check_embed.sh`, `scripts/check_toy_offstate.sh` | platform switches | 4 |
| `scripts/ci_linux_job.sh` | new: the Linux CI job | 4 |
| `scripts/check_rules.py`, `scripts/check_tree.sh` | only if a rule refuses Linux | 0, 1, 2, 3, 4 |
| `.github/workflows/ci.yml` | the Linux job | 4 |
| `CMakeLists.txt`, `cmake/` | platform guards | 2, 3, 4 |
| `src/CMakeLists.txt`, `test/CMakeLists.txt`, `test/consumer/`, `test/offstate/` | platform guards | 2, 3, 4 |
| `src/core/runtime/` | libc bindings and their C helper, if their layout differs | 2, 3 |
| `src/core/`, `src/test/` | a portability fix the diagnosis of a failing test leads to | 3 |
| `doc/collaboration/apple_questions.md` | a Linux-only MLX difference (decision 5) | 3, 5 |
| `doc/code_base_map.md` | regenerated when a described file is added | 2, 3, 4, 5 |
| `README.md`, `doc/how2s/how2set_up_dev.md` | Linux | 5 |
| `doc/policies/binding_contract_policy.md`, `doc/policies/test_environment_policy.md` | the platforms | 5 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | the rank's row | 5 |
| `doc/implementation_notes/README.md` | the index | 5 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 5 |
| `doc/implementation_notes/planned/mlxf_linux.md` | this note: Progress | 0, 1, 2, 3, 4, 5 |
| `doc/implementation_notes/completed/mlxf_linux_report.md` | new: the report with the CUDA inventory | 5 |

## Progress

Nothing has run. The run fills one subsection per phase: times, `uptime`, what was built and run, the counts, the
changes with their reasons, the skips, stops.
