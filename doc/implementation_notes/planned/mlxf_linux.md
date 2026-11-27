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
| `src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester.f90`, `src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester_solve.f90` | added in Phase 2: the helpers the submodule calls get their bodies there (gfortran 15 on Linux does not link a private procedure whose body is in the module from a submodule) | 2 |
| `scripts/check_submodule_linkage.py` | added in Phase 2: the static gate finds that form too | 2 |
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

The run fills one subsection per phase: times, `uptime`, what was built and run, the counts, the changes with their
reasons, the skips, stops.

### Phase 0, the base on dell2: done (2026-11-26, 22:39 to 22:48 EST, dell2)

One unattended session of run `mlxf_linux`, in the run's copy of the checkout. **Base pinned:
`0f8252b2d2bd7dc0e76cd29cf54e785b64b68b59`** (this note's commit), clean at the start. It differs from `90f5932`,
against which section 2 was checked, in four documents only (`doc/history/2026-11.md`,
`doc/implementation_notes/README.md`, this note, the roadmap), so section 2's findings about the code apply to it
unchanged. Rulings: none (the run's `spec/rulings.md` is empty). Files changed: this note's Progress, nothing else.
Evidence: `/home/hael/agent_runs/mlxf_linux/scratch/keep/phase0/` (`keep/phase0/` below) and
`/home/hael/agent_runs/mlxf_linux/scratch/keep/src/` (`keep/src/`). The phase took about 9 minutes (*measured*) of
its 60-minute box (*guessed*); the load stayed at or below 0.55 (*measured*). Every number below is *measured*
(read from a log) unless tagged otherwise.

1. **Machine and tools** (`keep/phase0/machine.log`, written by `keep/phase0/collect_facts.sh`). dell2, Ubuntu
   26.04.1 LTS, kernel 7.0.0-44 (the bring-up saw -43), Intel Core Ultra 7 366H, 16 CPUs at one thread per core,
   61 GB of memory and 31 GB of swap, load 0.28 a minute after a boot; 724 GB free on `/`, 788 GB on `/data2`. GCC,
   G++ and GNU Fortran 15.2.0 (Ubuntu 15.2.0-16ubuntu1), CMake 4.2.3, GNU Make 4.4.1, Python 3.14.4, git 2.53.0;
   `pkg-config` (pkgconf) and `curl` present; no `ninja`, no `clang`. GitHub answers (HTTP 200). The environment sets
   no `CC`, `CXX`, `FC`, `CMAKE_*`, `MLX*`, `OMP_*` or `OPENBLAS*` variable; `TMPDIR` is `$HOME/tmp`. mlx-fortran was
   never built here (the bring-up's configuration stopped at mlx-c); the run builds with the system GCC, which
   `cmake/AutoDetectGCC.cmake` selects as `gfortran-15` and `gcc-15` (bring-up probe 7), in trees configured by hand
   under the run's scratch.
2. **BLAS, LAPACK and LAPACKE** (`machine.log`). Installed: `libopenblas0-openmp` and `libopenblas-openmp-dev`
   0.3.32+ds-5, `liblapacke` and `liblapacke-dev` 3.12.1-7ubuntu1 (with `libtmglib3`, `libtmglib-dev`).
   `libblas-dev` and `liblapack-dev` are not installed and are not needed: `libblas.so`, `liblapack.so` and
   `libopenblas.so` resolve through Ubuntu's alternatives to OpenBLAS's `openblas-openmp/libblas.so.3`,
   `liblapack.so.3` and `libopenblasp-r0.3.32.so`, and `cblas.h` (`/usr/include/x86_64-linux-gnu/`) is OpenBLAS's.
   **`lapacke.h` is present:** `/usr/include/lapacke.h` and `/usr/include/lapack.h` come from `liblapacke-dev`, which
   `apt-get install -y liblapacke-dev` installed at 22:36:49, requested by hael, two minutes before the run
   (`/var/log/apt/history.log`, quoted in `machine.log`). Section 2's finding 2 ("no LAPACKE header") is superseded
   by that install.
3. **Decision 3 settled: installed; the fallback is not needed.** MLX `v0.32.4` includes `lapack.h` (it looks for
   `lapacke.h` only to find the include directory) and calls the Fortran LAPACK entry points through it
   (`mlx/backend/cpu/lapack.h`). A probe (`keep/phase0/lapack_probe/`, log `probe.log`) copies MLX's CPU-backend
   lookups for Linux from its top-level `CMakeLists.txt` into a scratch project and compiles MLX's `lapack.h`
   preamble: `find_package(LAPACK)` and `find_package(BLAS)` both find `/usr/lib/x86_64-linux-gnu/libopenblas.so`,
   `lapacke.h` is found in `/usr/include`, `cblas.h` in `/usr/include/x86_64-linux-gnu`; `LAPACK_GLOBAL` is defined
   (LAPACK 3.12's prototypes, the form MLX expects); `sgetrf` of a 2×2 matrix (pivot 2, U(1,1) = 6, *exact*) and
   `cblas_sgemm` (7, 10, 15, 22, *exact*) give the right values, and the program links `libopenblas.so.0` only. A
   hosted `ubuntu-24.04` runner needs the packages MLX's guide names (`libblas-dev liblapack-dev liblapacke-dev`):
   Phase 4.
4. **Static gate on the untouched base: passes.** `scripts/check_tree.sh` exits 0 with `check_tree: passed` in
   6.3 s wall (load 0.18), `keep/phase0/check_tree.log`. Rule `parity` still finds no mlx-c headers here
   (`parity: no mlx-c headers or prototype list found; the ledger's names were not compared`) and checks the
   ledger's form; `check_rules.py` reports 144 files, every rule holding (ledgers: cbind 0, libc 0, prints 0,
   state 4 files). No rule refuses Linux: `check_rules.py` and `check_tree.sh` are not changed.
5. **Section 2's findings re-checked.**
   - Finding 1 (the machine): holds (item 1).
   - Finding 2: superseded by the install (item 2).
   - Finding 3 (the bring-up): holds; the static gate passes and `parity` behaves as described (item 4).
   - Finding 4 (MLX at `v0.32.4`), read in GitHub's archive of the tag (below): `MLX_BUILD_CUDA` defaults OFF
     (`CMakeLists.txt:38`); on Linux the CPU backend finds and links LAPACK and BLAS (`CMakeLists.txt:326-349`); a
     CUDA build takes the native architecture and appends `a` from 90 up (`mlx/backend/cuda/CMakeLists.txt:169-186`)
     and builds cuDNN helpers; `docs/src/install.rst` asks for driver 550.54.14 or newer (580 for CUDA 13), toolkit
     12.0 or newer, glibc 2.35 or newer, and `libblas-dev liblapack-dev liblapacke-dev` on Linux; mlx-c `v0.8.0`'s
     `mlx/c/fast.h` declares `mlx_fast_cuda_kernel_config_new` beside `mlx_fast_metal_kernel_config_new`. Holds.
     Added: MLX's CPU-only configure downloads json (an archive URL), fmt 12.1.0 and gguf-tools (CMake's
     `FetchContent` from their repositories), as on macOS; Phase 1 needs the network.
   - Finding 5 (the Apple parts of the tree), searched with `rg` at the base: holds for the guarded parts
     (`cmake/CompilerConfig.cmake:24,55-56,77,84`; `test/CMakeLists.txt:33,72`; `CMakeLists.txt:28` makes
     `MLXF_REQUIRE_GPU` default ON on Apple arm64 only) and for the unguarded ones (`build_mlx_deps.sh:49` refuses
     anything but Darwin, and the script builds with `/usr/bin/clang`; `release_gate.sh:36` refuses off Apple
     silicon; `run_parts.sh` switches on `uname -s`; `run_fast_gate.sh:21` and `mlxf_build_jobs.sh:9` call `sysctl`
     only when `nproc` (and `getconf`) fail; `check_rules.py:1070` lists `/opt/homebrew/include` among its header
     candidates). Two corrections: no file outside `doc/` names `dylib` or `applegpu`; and
     `src/core/runtime/mlxf_libc.f90` binds no `O_*` flag and no `errno`. Its one layout assumption is macOS's
     `struct stat`, read from a 256-byte buffer at hand-typed offsets in `c_file_info` (`st_mode` the uint16 at
     byte 4, `st_nlink` the uint16 at 6, `st_uid` the uint32 at 16). On this machine
     (`keep/phase0/stat_probe/stat_offsets.log`, gcc 15.2, glibc, x86_64) `struct stat` is 144 bytes with
     `st_nlink` 8 bytes at 16, `st_mode` 4 bytes at 24 and `st_uid` 4 bytes at 28; `S_IFMT`, `S_IFLNK` and
     `S_IFREG` are the same octal values. So `c_file_info` reads the wrong bytes on Linux: decision 4's C helper,
     Phase 2. Strict `-std=c11` hides `S_IF*` there; the helper needs `_XOPEN_SOURCE` (or `-std=gnu11`).

A finding outside section 2, and the decision it leaves to Phase 1:

- **The run cannot clone.** arun's fence refuses every git subcommand that is not read-only, `clone` included,
  wherever the words stand in a shell command (inside an `echo` or a heredoc too, so notes and workflow files that
  name such a command are written with the editor tools). No clone of MLX or mlx-c exists on dell2. The pinned tags
  were therefore fetched as GitHub's archives with `curl`, each into its own directory:
  `keep/src/mlx_v0.32.4_tgz/mlx-v0.32.4.tar.gz` (4,535,793 bytes, SHA-256
  `0276db8d7bf1af8db6d4ae25c7c550abea4d5b3b6a16207610a5d4a0c19fe1a0`) and
  `keep/src/mlxc_v0.8.0_tgz/mlx-c-v0.8.0.tar.gz` (179,941 bytes, SHA-256
  `ea6251d37968ec3a7975982d2eb38b008ee2a6bfa75bee1132cae178a39765e2`). Each archive's
  commit (the pax header GitHub writes) equals the tag's commit as GitHub's API reports it: MLX
  `36969c094354086e15d2a327a9c50feb20b9cf11`, mlx-c `a26f2d584a14ec619ae8db9a09be03becd47598a`
  (`keep/phase0/archives.log`). They were unpacked for reading only (`keep/src/tree_mlx/`, `keep/src/tree_mlxc/`);
  nothing was built. `scripts/build_mlx_deps.sh` reads git clones (`git archive`), so decision 2's "the run clones"
  cannot be carried out as written. Recommended for Phase 1, which takes it under delegation: the Linux branch also
  accepts GitHub's archive of the tag in place of a clone, unpacks it into the work directory and records the
  archive's commit in `mlxf_deps.txt`; a clone (the CI's path) is exported with `git archive` as on macOS, and the
  macOS branch is untouched. A ruling that lets a run clone into its scratch, or clones the maintainer makes at
  `~/src/mlx` and `~/src/mlx-c` on dell2, would make that input unnecessary; the run does not wait for one.

Decisions taken under delegation:

- The pinned tags were fetched in Phase 0, as archives rather than clones (the fence), because re-checking finding 4
  needs MLX's source and Phase 1 then starts from verified sources. Read only.

Exit:

- The facts in Progress: met, items 1 to 5 with their logs.
- Decision 3 settled: met, installed by the maintainer before the launch; MLX's lookups resolve and the fallback is
  not needed (items 2 and 3).
- Static gate on dell2: met (item 4), and again after this entry (`keep/phase0/check_tree_end.log`; load 0.55 in
  `final_git_status.log`).
- `git status` shows this note as the only modified file: met, `keep/phase0/final_git_status.log`.

What it means, in short:

- dell2 has everything MLX's CPU build needs on Linux: GCC 15.2, CMake 4.2, OpenBLAS 0.3.32 with LAPACK, and, since
  the maintainer's install, the LAPACKE headers. No package is missing and no OpenBLAS is built.
- The one obstacle is how the sources arrive: the run cannot clone. The tags' archives are in hand and verified;
  Phase 1 builds from them.
- The first fix Linux needs in the library is already known: `mlxf_libc`'s `stat` offsets (Phase 2).

### Phase 1, MLX and mlx-c on Linux: done (2026-11-26, 22:48 to 23:02 EST, dell2)

Same session as Phase 0, base `0f8252b`. Rulings: none. Files changed: `scripts/build_mlx_deps.sh` (the Linux
branch) and this note's Progress. Evidence: `/home/hael/agent_runs/mlxf_linux/scratch/keep/phase1/`
(`keep/phase1/` below); the installed prefix is `/home/hael/agent_runs/mlxf_linux/scratch/keep/deps/install-cpu`
(`<prefix>` below), kept for Phases 2 to 4. About 15 minutes (*measured*) of the 150-minute box (*guessed*).

**The Linux branch of `scripts/build_mlx_deps.sh`** (decision 2), each change with why macOS is unaffected:

1. *A platform switch replaces the macOS check.* `case "$(uname -s)"`, right after the job count: `Darwin` does
   nothing, `Linux` sets `CPU_ONLY=1` (decision 2's "`--cpu-only` implied and accepted": on Linux the defaults are
   those of `--cpu-only`, `PREFIX=<repo>/.deps/install-cpu`, `WORK=<repo>/.deps/work-cpu`, `Metal OFF`, and the
   Metal-toolchain check is not taken), anything else is refused ("macOS or Linux only"). On macOS the switch only
   moves the `uname -s` call from after the defaults (which run no command) to before them.
2. *Compilers and MLX's flags.* On Linux GCC builds both (`-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++`, from
   `PATH`, fixed as the macOS branch fixes `/usr/bin/clang`) and `-DMLX_BUILD_METAL` is absent: MLX itself sets it
   OFF on any system but Darwin and iOS (MLX `v0.32.4`, `CMakeLists.txt:59-78`). The macOS lines are kept, inside
   `if [[ $OS == Darwin ]]`; the argument array is assembled from parts (`COMPILER_ARGS`, `MLX_ARGS`,
   `PLATFORM_ARGS`) whose macOS contents and order equal the old `CLANG_ARGS` and flags.
3. *`$ORIGIN` on Linux* (decision under delegation, below): `-DCMAKE_INSTALL_RPATH=$ORIGIN`, so that
   `libmlxc.so` finds `libmlx.so` beside it. Linux only (`PLATFORM_ARGS` is empty on macOS, where install names
   and `@rpath` do this already).
4. *The sources* (decision under delegation, below): on Linux `MLX_SRC` and `MLXC_SRC` may name a clone, exported
   at the tag with `git archive` as on macOS, or GitHub's archive of the tag (`linux_source`). An archive is
   accepted only if its top directory is `<repo>-<tag without v>` and its pax header holds a 40-hex commit, which
   `mlxf_deps.txt` records. On macOS a file given as a source is still refused as "not a git clone" (traced).
5. *`mlxf_deps.txt` names the platform* on Linux: `built <date> on Linux <arch> with <g++ --version>`; the macOS
   lines are unchanged, inside the `Darwin` branch.
6. *The header* gains four lines on Linux (CPU only, GCC, `$ORIGIN`, the packages MLX needs, the archive input),
   and `--help` prints them (`sed -n '2,21p'` for `'2,17p'`): on macOS `--help` prints those four lines more and
   nothing else changes.

**The macOS branch, byte for byte** (the gate): `keep/phase1/trace/trace_deps_script.sh` runs the base script
(`git show HEAD:`, kept as `keep/phase1/build_mlx_deps.base.sh`) and the new one under a faked Darwin, with
`uname`, `git`, `tar`, `cmake`, `xcrun`, `date` and `g++` replaced by stubs that log their arguments, and compares
the command traces, standard output and error, exit status, the written `mlxf_deps.txt` and the directories
created. **13 of 14 cases identical** (*measured*, in each of seven runs once the harness's own artifacts were
fixed: a diagnostic's line number, a sort before the path substitution, the stubs of a pipe racing on one log;
the last run is on the final script, whose SHA-256 heads `keep/phase1/trace/trace_run.log`): Metal
default, `--cpu-only`, `--jobs N` and `--jobs=N` with `PREFIX` and `WORK`, other refs and sources, a missing Metal
toolchain with and without `--cpu-only`, no clone, a file given as a source, an unknown option, `--jobs` missing
or invalid, x86_64 under `--cpu-only`. The 14th, `--help`, differs by the four new lines only. The same harness
traces the Linux branch: clones (default and given prefix, `--cpu-only` accepted), the two archives (the right
commits read from them), and refusals of a swapped pair, a wrong tag, a non-archive and a system that is neither.
The harness runs bash 5.3; `/bin/bash` on macOS is 3.2, so the new code on the macOS path uses only 3.2 forms
(the one empty-array expansion is `${a[@]+"${a[@]}"}`); the controller's run on the M5 is the check. One side
effect on CI: the macOS CPU job's cache key hashes this script, so the first push rebuilds the cached CPU-only MLX
once.

**The build** (`keep/phase1/build_mlx_deps.log`, `/usr/bin/time -v`): `scripts/build_mlx_deps.sh --jobs 16` with
`MLX_SRC` and `MLXC_SRC` at the two archives (Phase 0), `PREFIX=<prefix>`, `WORK` in scratch; 22:56:23 to 22:57:55,
**92.3 s wall**, 463.9 s user, 15.8 s system, 519 % CPU, peak RSS 1.01 GB, exit 0 (*measured*; load 2.48 at the
start, from the aborted first launch below, 3.14 at the end). MLX's configure found BLAS and LAPACK in
`libopenblas.so`, `lapacke.h` in `/usr/include`, `cblas.h` in `/usr/include/x86_64-linux-gnu`, and downloaded json
and gguf-tools. GCC 15.2 printed 300 warnings, all `-Wdeprecated-declarations` from MLX's own `mlx/error.h`
(`std::atomic_load` on a `shared_ptr`, deprecated in GCC 15's library): MLX's code, which mlx-fortran never
compiles; recorded, not ours to fix. A first launch at 22:54:59 was stopped after a minute by the run itself
(its process group only) because the script had been rewrapped while it ran; the build above is a clean second
run of the final script (`keep/phase1/build_mlx_deps.used.sh`, SHA-256 `fb254cbd…aaf7bb` in
`build_mlx_deps.used.sha256`). The work directory (104 MB) was deleted afterwards.

**The prefix** (`keep/phase1/prefix_facts.log`): `lib/libmlx.so` (22,100,656 bytes) and `lib/libmlxc.so`
(1,291,184 bytes), both `RUNPATH $ORIGIN`; `libmlx.so` needs `libopenblas.so.0` (OpenBLAS 0.3.32, OpenMP, which
brings `libgomp` and `libgfortran`), `libmlxc.so` needs `libmlx.so`, which `ldd` finds in `<prefix>/lib`; mlx-c's
CMake package `share/cmake/MLXC/MLXCConfig.cmake` (version 0.8.0) and MLX's `share/cmake/MLX/`; `include/mlx/`;
`mlxf_deps.txt`:

    MLX   v0.32.4  36969c094354086e15d2a327a9c50feb20b9cf11
    mlx-c v0.8.0 a26f2d584a14ec619ae8db9a09be03becd47598a
    Metal OFF
    built 2026-11-27T03:57:55Z on Linux x86_64 with g++ (Ubuntu 15.2.0-16ubuntu1) 15.2.0

**A consumer of the prefix** (`keep/phase1/smoke/`): a C program linked with `-lmlxc` only reports MLX 0.32.4,
Metal unavailable, one CPU device, no GPU device, and on the CPU stream inverts a 2×2 matrix through LAPACK
(`-0.5 0.5 1 -0.666667`, the exact inverse within 1e-5, *exact* reference) and multiplies it back through BLAS to
the identity (`smoke.log`). It compiles with one warning from mlx-c's own header (`array.h:42`,
`static mlx_array mlx_array_empty` unused, `-Wunused-variable` under `-Wall`): Phase 2 watches the C ABI probe of
`test/CMakeLists.txt`, which includes mlx-c's headers.

**Static gate:** `scripts/check_tree.sh` passes after the change (`keep/phase1/check_tree.log`). With
`MLXC_ROOT=<prefix>`, `check_rules.py` finds mlx-c's headers on dell2 for the first time and rule `parity` compares
its ledger with mlx-c 0.8.0's prototypes: every rule holds (`keep/phase1/check_rules_with_headers.log`).

Decisions taken under delegation:

- **Sources from GitHub's tag archives, not clones** (Phase 0's recommendation, taken): arun's fence refuses
  `git clone`, so decision 2's "the run clones" cannot be carried out on dell2. The Linux branch accepts the archive
  in place of a clone, checks that it is the tag's (top directory, commit in the header) and records its commit;
  a clone (the hosted CI's path, Phase 4) is exported exactly as on macOS. The archive's content equals `git archive`
  of the same commit, which is what the clone path builds. Alternative, not taken: stop for a ruling that lets the
  run clone, or for clones the maintainer makes on dell2; with either, the archive input could be dropped again.
- **`RUNPATH $ORIGIN` on the installed libraries, Linux only.** mlx-c links MLX privately, so a consumer links
  `libmlxc.so` alone, and on Linux the executable's run path does not reach a library's own dependencies (the
  linker writes `DT_RUNPATH`). Measured twice: a toy pair of libraries without `$ORIGIN` fails to load from an
  executable whose run path names their directory (exit 127) and loads with it
  (`keep/phase1/runpath_probe/run_probe.log`); and with MLX's own libraries, `libmlxc.so` alone in one directory
  and `libmlx.so` in a second directory that only the executable's run path names, loading fails with
  `libmlx.so: cannot open shared object file` (exit 127, `keep/phase1/smoke/split.log`). (`LD_DEBUG` credits
  the shared directory to the executable's run path because glibc keeps one entry per directory, first named by
  the executable: `smoke/ld_debug_libmlx.log`.) Without `$ORIGIN`, every Linux consumer of the prefix would need
  `LD_LIBRARY_PATH` or to link `libmlx.so` itself.
- **GCC from `PATH`, not `CC`/`CXX`**, mirroring the macOS branch's fixed compiler; its version is recorded.

Exit:

- A prefix with `libmlx.so`, `libmlxc.so` and mlx-c's CMake package: met (`keep/phase1/prefix_facts.log`).
- The build's seconds, the libraries and `mlxf_deps.txt` recorded: met (above).
- The macOS branch byte for byte as before: met for every command, output and file the branch issues
  (`keep/phase1/trace/trace_run.log`); `--help` gains the Linux paragraph. The controller rebuilds on the M5.
- Static gate: met, also after this entry (`keep/phase1/check_tree_end.log`); `git status` shows the script and
  this note only (`keep/phase1/final_git_status.log`).

What it means, in short:

- MLX 0.32.4 and mlx-c 0.8.0 build CPU-only on Linux with GCC 15.2 and the system OpenBLAS in a minute and a half
  on 16 cores, untouched; the pinned pair works from a plain C program.
- The script builds on Linux the same way it builds on macOS, with two Linux-only additions forced by the
  platform (`$ORIGIN`) and by the run's fence (tag archives); macOS runs the same commands as before.
- Phase 2 configures mlx-fortran with `MLXC_ROOT=<prefix>`.

### Phase 2, the library on Linux: done (2026-11-26, 23:01 to 23:16 EST, dell2)

Same session, base `0f8252b`. Rulings: none. Evidence: `/home/hael/agent_runs/mlxf_linux/scratch/keep/phase2/`
(`keep/phase2/` below). Trees configured by hand as the run prescribes (`-DBUILD_TESTS=ON -DFORTLS=OFF
-DMLXF_WERROR=ON -DMLXF_REQUIRE_GPU=OFF -DMLXC_ROOT=<prefix>`), kept for Phase 3: `scratch/build_debug`,
`scratch/build_release`. About 15 minutes (*measured*) of the 180-minute box (*guessed*). Files changed:
`cmake/CompilerConfig.cmake`, `src/CMakeLists.txt`, `test/CMakeLists.txt`, `src/core/runtime/mlxf_libc.f90`, **new**
`src/core/runtime/mlxf_libc_lstat.c`, `src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester.f90` and
`..._tester_solve.f90`, `scripts/check_submodule_linkage.py`, `doc/code_base_map.md` (regenerated), this note (two
file-table rows, Progress).

**What broke, in the order the builds met it** (configuration itself passed at once: `AutoDetectGCC` takes
`gfortran-15` and `gcc-15`, mlx-c 0.8.0 is found at the prefix, `keep/phase2/configure_debug.log`; the library
`libmlxf.a` compiled in Debug with `-Werror` and no warning on the first try, `build_debug.try1.log`):

1. **The ABI probe stops on mlx-c's header.** `test/CMakeLists.txt` compiles `src/test/framework/mlxf_abi_probe.c`
   with `-Wall -Wextra -Werror`; mlx-c's `mlx/c/array.h:42` defines `static mlx_array mlx_array_empty;`, which GCC
   reports as unused (`-Werror=unused-variable`) in every file that includes it; Apple's clang does not warn about
   an unused static of a header. Fix: off Apple, `-isystem <mlx-c include>` precedes the unchanged
   `"-I<mlx-c include>"`; GCC then reads the directory as a system directory (its documented rule for a directory
   named by both), so the dependency's header is quiet and the probe's own code keeps every warning. *macOS:* the
   `APPLE` branch sets the new variable empty, which expands to no argument: the probe's command is the same
   arguments as before. The header's static is an mlx-c question for Phase 3's record (decision 5).
2. **The test executable does not link** (`build_debug.log`): the submodule
   `mlxf_toy_reconstructor_pcg_tester_solve` calls six private separate module procedures whose bodies are in its
   module (`tol`, `assemble`, `fixed_volume`, `rel2`, `report`, `device_name_now`), and gfortran 15.2 on Linux gives
   them local linkage (`t` in `nm`), so the submodule's object finds none of them. A 30-line reproducer
   (`keep/phase2/submodule_repro/`, `repro.log`) shows the rule at `-O0` and `-O2`: a private separate procedure
   with its body in the module does not link from a submodule; one with its body in the submodule does, also from
   the module. `scripts/check_submodule_linkage.py` stated the opposite ("separate module procedures link") and
   let it through. Fix: the six bodies move, text unchanged, from the module into the submodule (their interfaces
   stay in the module; `mlx_default_device`, imported for `device_name_now` alone, moves into it;
   `keep/phase2/move_helpers.py`); the checker now also counts a private separate module procedure whose body is in
   the module. Planted violation (`keep/phase2/linkage_check.log`): on a copy of `src/` with the two tester files
   as at the base, the extended checker names exactly the six calls the linker named (exit 1), the base checker
   finds nothing (exit 0); on the changed tree the extended checker passes. *macOS:* the tester's procedures and
   calls are the same; the checker is platform-free and the tree passes it. The two files and the checker were not
   in the file table: two rows were added for Phase 2 before they were edited.
3. **`mlxf_libc`'s `stat` layout** (Phase 0, item 5): `c_file_info` read macOS's `struct stat` at hand-typed
   offsets; on glibc x86_64 bytes 4 to 7 lie in `st_dev` and bytes 16 to 19 in `st_nlink` (Phase 0's layout), so
   the mode came from the device number and the owner from the link count. Measured on the Release tree built
   with the base `mlxf_libc.f90` and nothing else changed: `unit_io` fails "a save begun over the checkpoint has
   its own temporary file" (the save refuses the existing destination) and the process then dies with SIGSEGV, exit 139
   (`keep/phase2/unit_io_prev.log`). Fix (decision 4): a C helper, **`src/core/runtime/mlxf_libc_lstat.c`**,
   `mlxf_lstat_facts(path, ftype, perm, nlink, uid)`, calls `lstat` and returns the file type (link, regular,
   other), the permission bits with set-id and sticky, the hard links and the owner, read by the C compiler from
   the platform's own `struct stat` (the pattern of SIMPLE's `src/fileio/simple_posix.c`); `mlxf_libc.f90` binds it
   (`bind(c, name='mlxf_lstat_facts')`) in place of `lstat`, and `STAT_BYTES`, the `S_IF*` constants, `unsigned16`
   and the `c_int8_t` import go. With it `unit_io` passes, 475 of 475 assertions, exit 0, no file left behind
   (`keep/phase2/unit_io_release.log`). The helper compiles clean under GCC 15 with `-std=c11` and `-std=gnu11`,
   `-Wall -Wextra -Wpedantic -Wconversion -Werror` (`keep/phase2/draft/`); the hard-link count is compared in
   `uintmax_t` so that no compiler sees a comparison that is always false where `nlink_t` is 16 bits (macOS).
   *macOS:* `c_file_info` returns the same facts, which the C compiler now reads from the same three fields the
   offsets named; the helper is built there too (decision 4: no hand-typed offset for two platforms); the
   controller's `unit_io` on the M5 is the check.
4. **A C source in the library** needs two build changes. `src/CMakeLists.txt` globs `core/*.c` into `mlxf`
   (`src/test/`'s C, the ABI probe, stays with `test/CMakeLists.txt`). `cmake/CompilerConfig.cmake` puts the
   Fortran options, unchanged and in their order, into a list given under `$<COMPILE_LANGUAGE:Fortran>` (GCC's C
   compiler refuses `-std=f2018`), and gives C sources `-Wall -Wextra`, with `-Werror` under `MLXF_WERROR`.
   *macOS and Linux alike:* the generated `flags.make` of `mlxf` and `mlxf_test_exec` in five configurations
   (Debug, Release, Debug with `MLXF_DEBUG_TRAPS`, RelWithDebInfo, Release without `MLXF_WERROR`) are byte for byte
   the same before and after the change (`keep/phase2/flags_before/`, `flags_after_scoping/`, an empty
   `flags_scoping_diff.log`); the expressions that test the platform (`$<PLATFORM_ID:Darwin>`) are unchanged
   elements of the list. The one new compile on macOS is the helper's.

Checked and not changed: `c_chmod` and `c_mkdir` pass the mode as a 16-bit integer by value, macOS's `mode_t`;
glibc's is 32 bits. gfortran 15.2 zero-extends the value into the 32-bit register at `-O0` and `-O3` (`movzwl`,
`keep/phase2/draft/abi16/`), and the kernel keeps only the low twelve mode bits, so nothing breaks on x86-64 Linux;
recorded for the CUDA inventory (an aarch64 Linux host is the next ABI).

**The exit builds, from scratch** (`keep/phase2/build_from_scratch.sh`: `rm -rf` the tree, configure, build with
`-j 16` under `/usr/bin/time -v`):

| Build | Log | Wall | CPU (user) | Load at start | Exit | Warnings |
| --- | --- | --- | --- | --- | --- | --- |
| Debug | `build_debug_scratch.log` | 4.9 s | 24.1 s | 0.22 | 0 | 0 |
| Release | `build_release_scratch.log` | 17.9 s | 102.8 s | 0.29 | 0 | 0 |

(*measured*; 167 objects each, the ABI probe's besides; `-Werror` on Fortran and C, and no `warning:` and no
`CMake Warning` line in either log.) `mlxf_test_exec test=list` starts from the Release tree and finds
`libmlxc.so` and `libmlx.so`. The static gate passes after the changes (`keep/phase2/check_tree_end.log`; its one
warning names the new, untracked `mlxf_libc_lstat.c`, which the commit adds); both formatters leave the three
touched Fortran files unchanged.

Decisions taken under delegation:

- **The C helper calls `lstat` and returns the facts**, rather than reporting offsets for Fortran to read: no
  layout reasoning stays in Fortran, it follows SIMPLE's C wrappers of `stat`, and it serves both platforms.
- **C sources of `src/core` are library sources** with their own warnings; the Fortran options are scoped to
  Fortran. Alternative not taken: a configure-time `try_run` writing the offsets into the generated include
  (keeps the library pure Fortran, but reads bytes of variable width in Fortran).
- **mlx-c's headers as system headers for the ABI probe off Apple**: the warning is mlx-c's, the probe's own code
  keeps `-Werror`.
- **The helpers' bodies moved into the submodule and the linkage checker extended** (two file-table rows added):
  the checker exists to catch exactly what does not link on Linux, and the planted violation shows it now does.
  The rule's text in the skill, the register (`doc/architecture_principles.md`) and the test policy still says "a
  private plain procedure"; the policy is Phase 5's, the skill and the register are proposed to the maintainer in
  the report (a skill edit needs his approval).
- **`c_chmod`/`c_mkdir` left as they are** (measured harmless here; inventory).

Exit:

- Debug and Release from scratch with `MLXF_WERROR=ON`, zero warnings: met (table above).
- The static gate and the formatters on the touched Fortran files: met.

What it means, in short:

- mlx-fortran builds on Linux with gfortran 15.2 in both build types without a warning; the library's Fortran
  needed no change for the compiler.
- Linux needed three fixes: a C helper for `lstat` (a real bug: saves over an existing file were refused), the
  probe reading mlx-c's headers as a dependency's, and six tester helpers moved where gfortran 15 links them, with
  the static gate now catching that form.
- Phase 3 runs the fast gate and every unit area on these two trees.

### Phase 3, the suite on the CPU device: done (2026-11-26, 23:15 to 23:25 EST, dell2)

Same session, base `0f8252b`, on Phase 2's two trees (unchanged since they were built from scratch). Rulings: none.
Evidence: `/home/hael/agent_runs/mlxf_linux/scratch/keep/phase3/` (`keep/phase3/` below). About 10 minutes
(*measured*) of the 180-minute box (*guessed*). Files changed: `doc/collaboration/apple_questions.md` (item 38) and
this note; no source and no test changed, so the formatters had nothing to run on.

**The fast gate** (`scripts/run_fast_gate.sh <tree>`: the static gate, then `ctest -L fast` with 8 jobs and the
60-second budget check): **Debug 13 of 13 passed**, CTest 13.77 s, `unit_kernels` the longest at 13.73 s
(`fast_gate_debug.log`, load 0.17 at the start); **Release 13 of 13 passed**, CTest 2.98 s
(`fast_gate_release.log`, load 0.28) (*measured*). Both CTest transcripts are kept (`LastTest_debug.log`,
`LastTest_release.log`): every entry ran with `GPU devices: 0` and `Metal backend: F`, and no line `SKIP: no GPU
device` appears, as `scripts/ci_cpu_job.sh` requires of a CPU-only job.

**Every unit area on the CPU device**, counts read from the transcripts by `keep/phase3/area_counts.py`
(`area_counts_fast_gate.md`), *exact*, **Debug and Release identical**:

| Entry | Test groups | Assertions evaluated = passed | Skips (each `SKIP: GPU-only check on a CPU-only MLX build: ...`) |
| --- | --- | --- | --- |
| `unit_core` | 7 | 159 | 4: the information of the GPU; the recovery gate (the maximum buffer of the Metal allocator); the memory and wired limits (Metal's allocator); a Metal capture |
| `unit_array` | 1 | 123 | none |
| `unit_ops` | 8 | 1,736 | none |
| `unit_linalg` | 5 | 419 | none |
| `unit_fft` | 2 | 101 | none |
| `unit_compile` | 1 | 32 | none |
| `unit_transforms` | 2 | 153 | none |
| `unit_fast` | 2 | 47 | none |
| `unit_random` | 1 | 244 | none |
| `unit_io` | 1 | 475 | none |
| `unit_distributed` | 1 | 28 | none |
| `unit_kernels` | 11 | 894 | none |
| `object_contracts` | 33 guard members | 32 stopped with the hard-error status | 1: `guard_float64_on_gpu` |

That is 4,411 assertions per build, none failed, and five skips, each a GPU-only check by the tree's own
classification (`doc/policies/test_environment_policy.md`); **no Linux-only skip**, so decision 5 had nothing to
diagnose. The Debug build here checks with `-fcheck=all` (macOS: `bounds,do,mem`) and found nothing.

**The named-only sub-suites**, run by name in CTest's environment in their own directories (`run_named.sh`,
`run_ring.sh`), Release and Debug, *measured*:

| Sub-suite | Release | Debug |
| --- | --- | --- |
| `unit_core suite=recovery_half` | skipped, GPU-only (the recovery gate) | the same |
| `unit_kernels suite=polar_shiftmap_accuracy` | 24 of 24, 0.5 s | 24 of 24, 1.7 s |
| `unit_kernels suite=reconstructor_pcg_n32` | 48 of 48, 60.5 s | 48 of 48, 236 s |
| `unit_distributed suite=distributed_ring`, two processes on MLX's ring backend over the loopback (`MLX_RANK` 0 and 1, `MLX_HOSTFILE` `[["127.0.0.1:p"], ["127.0.0.1:p+1"]]`) | 14 of 14 on each rank | the same |

Every run exits 0 and leaves no file behind (`named_*.log`).

**Against the macOS CPU-only job.** That job's counts for this base exist only on the M5: the CI job
(`scripts/ci_cpu_job.sh`) was last run there by run `mlxf_user_hardening` (Phase 6, `ci_cpu_final_*.log`) at
`90f5932`, whose sources equal this base's, and the run's fence keeps it from reaching that machine. No test
branches on the platform: the only preprocessor conditions in the test code are `USE_MLX`, `MLXF_REQUIRE_GPU` and
the BLAS benchmark's `MLXF_HAVE_BLAS`, and a CPU-only MLX classifies the session the same way on both systems. So
the counts above are what that job must show, check for check; the controller compares them on the M5 with
`scripts/ci_cpu_job.sh` at the fetched tree (Phase 4 makes the same job runnable on Linux).

**An mlx-c question** (decision 5, `doc/collaboration/apple_questions.md`, new section P, item 38): `mlx/c/array.h`
defines `static mlx_array mlx_array_empty;`, which GCC's `-Wall` reports in every C file that includes
`mlx/c/mlx.h` (Phase 2's ABI probe failure). Direct reproducer: a file that only includes the header fails
`gcc -std=c11 -Wall -Werror` (`keep/phase3/mlxc_header_repro/repro.log`). Not filed: MLX's own
`mlx/error.h` warnings under GCC 15 (`std::atomic_load` on a `shared_ptr`, 300 lines in Phase 1's build), which a
`TODO` in that file already names; they are recorded in the report instead.

Decisions taken under delegation:

- **The named-only sub-suites were run too**, although the gate does not: the run's instructions name "every unit
  area and sub-suite", and `distributed_ring` and `reconstructor_pcg_n32` exercise MLX's ring backend and a long
  CPU solve, which the gate does not reach.
- **Acceptance 1's comparison** is read as: the same counts as the macOS CPU-only job, whose skips are the same
  five GPU-only checks; the exact comparison is the controller's, since the job's counts at this base are on the M5.

Exit (acceptance 1):

- Debug and Release with zero warnings: met in Phase 2 (`keep/phase2/build_*_scratch.log`), the trees unchanged.
- The fast gate passes: met, both builds.
- Every unit area passes on the CPU device, counts listed per area, the skips named: met; equality with the macOS
  CPU-only job's counts holds by construction and is checked by the controller.
- The static gate after the phase: passes (`keep/phase3/check_tree_end.log`).

What it means, in short:

- The whole suite, 4,411 checks and 33 guard members per build plus the four named-only sub-suites, passes on
  Linux's CPU device in Debug and Release; the only skips are the five GPU-only checks a CPU-only MLX skips on any
  system.
- Linux brought no numerical difference: no MLX CPU kernel behaves differently from what the tests expect, and
  MLX's ring backend works between two processes on one Linux machine.

### Phase 4, install, embedding, off-state and CI: done (2026-11-26, 23:24 to 23:35 EST, dell2)

Same session, base `0f8252b`, on Phase 2's trees, installed into themselves. Rulings: none. Evidence:
`/home/hael/agent_runs/mlxf_linux/scratch/keep/phase4/` (`keep/phase4/` below). About 11 minutes (*measured*) of the
120-minute box (*guessed*). Every check ran with `TMPDIR` in the run's scratch. Files changed:
`scripts/check_embed.sh`, **new** `scripts/ci_linux_job.sh`, `.github/workflows/ci.yml`, this note.
`scripts/check_install.sh`, `scripts/check_toy_offstate.sh`, `scripts/ci_cpu_job.sh`, `scripts/run_fast_gate.sh`
and `scripts/mlxf_build_jobs.sh` needed no change on Linux.

**The three checks:**

1. **`scripts/check_install.sh`, unchanged: passes**, on the Release and the Debug tree (`check_install_release.log`,
   `check_install_debug.log`): the consumer and the four examples on the CPU device ("default device cpu", "every
   row holds, on the cpu"), the installed lifetime checker and its planted leak, isolation, the compiler and mlx-c
   refusals, the private modules, pkg-config. The first try (`check_install_release.no_mlxc_root.log`) stopped at
   the consumer's configure because the installed `mlxfConfig.cmake` looks for mlx-c through `MLXC_ROOT` or CMake's
   default prefixes, and the prefix in scratch is neither: the same on macOS for any prefix outside Homebrew, which
   is why `ci_cpu_job.sh` exports `MLXC_ROOT`; not a Linux difference.
2. **`scripts/check_embed.sh`: one fix, then passes** (`check_embed.try1.log`, `check_embed.log`). The parent
   project configured, built the library (its C helper too: the parent enables C) and ran its program; the
   private import failed as it must, but the script's own `grep` for `cannot open module file 'mlxf_c_array.mod'`
   missed, because Ubuntu's GCC, built with native-language support, writes typographic quotes in a UTF-8 locale
   (`‘mlxf_c_array.mod’`). The line is now matched around the quotes (`cannot open module file .*mlxf_c_array\.mod`).
   *macOS:* `keep/phase4/embed_pattern_check.log` runs both patterns on three messages: the ASCII-quoted one (as
   on macOS) matches both, the UTF-8 one only the new, another module's message neither; so the check accepts and
   refuses on macOS exactly what it did.
3. **`scripts/check_toy_offstate.sh --exec <Release mlxf_test_exec>`, unchanged: passes** (`check_toy_offstate.log`):
   Debug and Release built without MLX and without the library, without a warning, no MLX symbol, 135 table lines
   each, and the host route's table equal to `mlxf_test_exec`'s byte for byte. The Debug and Release tables are
   identical; the table is kept for the controller (`keep/phase4/offstate_release_table.txt`, SHA-256
   `f1e71b11b6dfd8337a806bbf59abfeb39db8d50d8e4d29184f8f7acfb10a4a23`), whose release gate on the M5 produces the
   same 135 lines: whether gfortran and libm on the two systems give the same bytes is for that comparison.

**`scripts/ci_linux_job.sh`** (new, decision 6): `BUILD_TYPE FORTRAN_COMPILER [--jobs N]`, Linux only (it refuses
elsewhere and names `ci_cpu_job.sh`). It runs `scripts/ci_cpu_job.sh` as the macOS CPU-only jobs do, which needed no
change (the prefix `MLXC_ROOT` or `.deps/install-cpu`, built by `build_mlx_deps.sh` when empty; configure in
`build_ci_<type>/`; the check that the CPU-only prefix was linked; the fast gate with no no-device skip and the
GPU-only skips counted; install; `check_install.sh`), then what `release_gate.sh` adds on a Mac and no other Linux
job runs: `check_embed.sh`, and `check_toy_offstate.sh --fc <the job's compiler>` with `--exec` in a Release job.
On dell2 against the scratch prefix, *measured* (wall, load at the start):

| Job | Log | Result | Fast gate | Wall | Load |
| --- | --- | --- | --- | --- | --- |
| Release, gfortran 15.2 | `ci_linux_release_gf15.log` | passed | 13/13, 6.9 s; 5 GPU-only skips, 0 no-device | 39.4 s | 0.14 |
| Debug, gfortran 15.2 | `ci_linux_debug_gf15.log` | passed | 13/13, 8.0 s; the same skips | 27.6 s | 1.25 |
| Release, gfortran 14.3 | `ci_linux_release_gf14.log` | passed | 13/13, 3.2 s; the same skips | 35.9 s | 1.89 |
| Debug, gfortran 14.3 | `ci_linux_debug_gf14.log` | passed | 13/13, 8.1 s; the same skips | 28.0 s | 2.01 |

gfortran 14 is not installed on dell2: Ubuntu 26.04's packages of 14.3.0 (`gfortran-14`, `gcc-14`, `cpp-14`, their
`x86-64-linux-gnu` parts, `gcc-14-base`, `libgcc-14-dev`, `libgfortran-14-dev`, `14.3.0-14ubuntu1`) were fetched
with `apt-get download` and unpacked into scratch (no `sudo`, nothing system-wide), their runtime links pointed at
the system's shared runtimes as an installed `gfortran-14` would use, and deleted after the runs. With it the whole
tree builds without a warning in both build types and every check passes: neither failure that GNU Fortran 14.4
showed on macOS (the `-Wuninitialized` false positive in `mlxf_bench_polar_table.f90`, the unlinked procedures of
`mlxf_toy_reconstructor_pcg_tester_solve`) appears with 14.3 on Linux. In the 14.3 jobs `check_embed.sh` configured
with the newest gfortran on `PATH` (15.2), as `AutoDetectGCC` chooses; on the runner that is the job's own.

**The workflow** (`.github/workflows/ci.yml`): a job `linux` on `ubuntu-24.04`, matrix {Debug, Release} ×
{gfortran-14, gfortran-15}: checkout; `apt-get install` of the compiler, `pkg-config`, `libopenblas-openmp-dev` and
`liblapacke-dev` (OpenBLAS's OpenMP build with LAPACK and the LAPACKE headers, the combination tested on dell2),
gfortran-15 from the toolchain PPA `ppa:ubuntu-toolchain-r/test` (Launchpad publishes `gcc-15`
`15.2.0-14ubuntu1~24~ppa1` for noble; the archive's `gcc-14` is `14.2.0-4ubuntu2~24.04.1`, both read from Launchpad's API); the CPU-only MLX
cached under the same key as the macOS jobs' (the runner's OS differs, so the caches do not collide); the clones on
a miss; `scripts/ci_linux_job.sh`. The runner's own CMake, Python and g++ serve (MLX's build, and MLX's CPU backend,
which compiles the kernels of compiled graphs with `g++` at run time). The workflow's name gains "and Linux x86-64";
the `cpu` and `metal-build` jobs are unchanged (`git diff` removes no other line). The file parses with PyYAML
(the `eman2` environment's interpreter, read only), three jobs, the Linux job's matrix and step as intended
(`keep/phase4/ci_yaml_check.log`). **Not verifiable here** (first seen on the maintainer's next push): the hosted
runner, its g++ 13 building MLX 0.32.4, the PPA install, noble's gfortran 14.2 (14.3 was tested), the cache.

**Found on the way** (for the report and the inventory):

- MLX's CPU backend compiles the kernels of compiled graphs at run time with `g++ -std=c++17 -O3 -fPIC -shared`
  when `g++ --version` succeeds, and caches them under `std::filesystem::temp_directory_path()/mlx/0.32.4/cpu`
  (MLX `mlx/backend/cpu/jit_compiler.cpp`, `compiled.cpp`); without `g++` compiled graphs run uncompiled on the CPU.
- MLX opens `libmpi.so` at run time (`mlx/distributed/mpi/mpi.cpp`); on dell2, where Open MPI 5 is installed,
  `unit_distributed` starts an MPI singleton, which writes a session directory under `TMPDIR`
  (`keep/phase4/distributed_mpi_probe.log`); the group is still one process and the tests pass.
- Phase 3's runs used the default `TMPDIR` (`~/tmp`) and left there MLX's kernel cache (55 entries) and Open MPI's
  session directory (6 entries), all created during this run: both were removed, and every later run used scratch.

Decisions taken under delegation:

- **`ci_linux_job.sh` runs `ci_cpu_job.sh`** rather than copying it: that script needed no change for Linux, and one
  path keeps the two platforms' jobs alike; the Linux job adds the embedding and off-state checks, which a Mac
  runs in its release gate and nothing on Linux would run otherwise.
- **`check_embed.sh` matches around the quotes** rather than forcing `LC_ALL=C` or branching on the platform: it is
  what `check_install.sh` already does for the same message.
- **gfortran 14 tested from unpacked Ubuntu packages** before decision 6's 14 leg was written, so that the leg is
  known to pass rather than guessed.
- **The CI's packages** are the combination tested on dell2 (OpenBLAS OpenMP, LAPACKE), with the runner's own CMake
  and g++; gfortran 15 from the toolchain PPA, since noble's archive stops at 14.

Exit (acceptance 2):

- `check_install.sh`, `check_embed.sh`, `check_toy_offstate.sh --exec` and `ci_linux_job.sh` pass on dell2: met
  (logs above), `ci_linux_job.sh` in both build types with gfortran 15.2, and with 14.3 as well.
- The static gate after the phase: passes (`keep/phase4/check_tree_end.log`; its warning names the untracked
  `mlxf_libc_lstat.c` of Phase 2, which the commit adds with `scripts/ci_linux_job.sh`).

What it means, in short:

- The installed package, the embedded library and the toys without MLX all work on Linux; one check needed its
  message match freed from the compiler's choice of quotes.
- A Linux CI job exists and passes here in all four of its legs; the hosted run is the maintainer's next push.
- On Linux MLX reaches for two things a Mac may not have: `g++` at run time for compiled CPU graphs, and a system
  Open MPI when one is installed.

### Phase 5, the record: done (2026-11-26, 23:34 to 23:48 EST, dell2)

Same session, base `0f8252b`. Rulings: none. About 14 minutes (*measured*) of the 90-minute box
(*guessed*). Files changed: `README.md`, `doc/how2s/how2set_up_dev.md`, `doc/policies/binding_contract_policy.md`,
`doc/policies/test_environment_policy.md`, `doc/implementation_notes/planned/mlxf_roadmap.md` (rank 2h's row),
`doc/implementation_notes/README.md` (the index), `doc/history/2026-11.md`, this note, and **new**
`doc/implementation_notes/completed/mlxf_linux_report.md` (the report with the CUDA inventory).

- **The CUDA inventory** (decisions 8 and 10) is the report's section "The CUDA inventory". It was read from the
  code and from MLX 0.32.4's and mlx-c 0.8.0's sources (the tag archives of Phase 0) by three read-only subagents
  in parallel (the custom Metal kernels; every other Apple assumption of the tree; MLX's CUDA backend), and its
  decisive facts were checked again directly in MLX's source: `MLX_ENABLE_TF32` (default 1) switches cuBLAS and
  cuDNN to TF32 on CUDA too; the CUDA build's device information has no `memory_size` and no
  `max_buffer_length`; GPU buffers live in device memory and move to unified (managed or pinned) memory at the
  first host access; float64 runs on the CUDA GPU; only `linalg::cholesky` of the CPU-only factorisations runs on
  the CUDA GPU; mlx-c's CUDA kernel takes a shared-memory size where the Metal one takes `atomic_outputs`.
- **Documents:** the README states the Linux requirements and the Linux CI job; the setup guide gains section 7,
  Linux; the binding contract gains a platforms bullet (section 7) and names every Linux build a CPU-only
  session; the test policy names the Linux classification and job, corrects its list of GPU-only checks from three
  to the five the transcripts show, and widens the submodule-linkage rule to what the checker now enforces (a
  private procedure whose body is in its module, plain or separate). The roadmap's row 2h, the index and the
  history record the delivery.
- **A correction of Phase 4's last line:** MLX compiles the CPU kernels of compiled graphs with `g++` on every
  system but Windows, macOS included (no Apple branch in `mlx/backend/cpu/jit_compiler.cpp`; a Mac's `g++` comes
  with the Command Line Tools). So `g++` at run time is not a Linux difference; the system Open MPI is.

Decisions taken under delegation:

- **The test policy's list of GPU-only checks corrected to five** (it named three; the memory and wired limits and
  the Metal capture had become GPU-only checks since): a policy that is the truth states what the transcripts show.
- **The linkage rule widened in the test policy only**; the skill and the register are proposed in the report,
  since a skill edit needs the maintainer's approval.
- **The plan stays in `planned/`** until the maintainer's read and the controller's macOS check, as the earlier
  runs' plans did.

Exit (acceptance 4):

- The report lists every portability change with its reason (its table "Every portability change and why"), every
  Linux-only skip with its question (none; the one question, Apple question 38, is listed), and the CUDA
  inventory of decision 8 with decision 10's proposal: met.
- `git status` shows file-table paths only: met (`keep/phase5/final_git_status.log`).
- The static gate passes (`keep/phase5/check_tree_end.log`).

What it means, in short:

- The Linux step is recorded where the next reader looks: the README, the setup guide, the two policies, the
  roadmap, the history.
- The CUDA plan (rank 5) can be written from the report's inventory: what MLX's CUDA backend needs, what in the
  tree assumes Metal, and, kernel by kernel, what a CUDA twin takes.
