# Report of run `mlxf_cuda_prep`: CUDA, Part A, the preparation on dell2 without a GPU (roadmap rank 5a)

Plan: [`mlxf_cuda.md`](../planned/mlxf_cuda.md), Part A, Phases 0 to 5 (its Progress holds the detail, phase by
phase). Run on dell2 (Ubuntu 26.04.1, kernel 7.0, Intel Core Ultra 7 366H, 16 CPUs, 61 GB, no GPU and no NVIDIA
driver), 2026-11-27, 09:29 to 12:10 EST, unattended, from base `1426c10` (the plan's commit), in a copy of the
checkout; nothing committed. One ruling, R1 (below). CUDA 12.9.1 in `/opt/cuda-12.9` (six declarations of its
`crt/math_functions.h` given `noexcept (true)` by Hans for glibc 2.43), cuDNN 9.28.1, `g++-14` as nvcc's host
compiler, GCC and GNU Fortran 15.2, CMake 4.2; MLX 0.32.4 and mlx-c 0.8.0 built by the run. Evidence paths are under
`/home/hael/agent_runs/mlxf_cuda_prep/scratch/keep/phaseN/`; the diffs are the run's `review/phase_N.diff`
(`/home/hael/agent_runs/mlxf_cuda_prep/review/`). **Nothing has run on a GPU:** every CUDA build was built and
linked, never run, and every statement below about behaviour on a card is code Part C runs first.

## What was learned

1. **MLX with CUDA builds on dell2 from one command.** `scripts/build_mlx_deps.sh --cuda --cuda-arch '100a;120a'`
   builds MLX 0.32.4 and mlx-c 0.8.0 for both Blackwell targets in 518 s (*measured*) and reproduces Hans's hand
   probe file for file (2,065 files, headers and CMake packages identical, 99 cubins per architecture; *exact*). It
   refuses the known failures before the 9-minute build: a toolkit MLX refuses, a host compiler nvcc refuses, the
   glibc 2.41+ clash with CUDA 12's math header (with the one-line fix, never applied by the script), no cuDNN 9, no
   stub, no architecture on a machine without a GPU.
2. **What a CUDA program needs at run time from outside the prefix** is the driver's `libcuda.so.1` and, found here,
   the toolkit's `lib64` on the loader path: MLX compiles kernels with NVRTC, which opens `libnvrtc-builtins` by
   name. The setup guide says so; the script's header comment still says "only the driver" (left for Phase 21).
3. **A CUDA build without a GPU cannot allocate,** as Metal without a device cannot (MLX's allocator asks
   `cudaMemGetInfo` at start-up). The library and the tests treat it so: four sessions, Metal or CUDA with or
   without a GPU, plus CPU-only. Without a driver a CUDA build does not even load, so dell2 links through the
   toolkit's stub (`MLXF_CUDA_STUB_DIR`, build only).
4. **One kernel type carries both sources** (decision 6, option A): `mlx_custom_kernel` from
   `mlx_custom_kernel_spec` with `cuda_source` and `shared_memory`; the backend is read once at construction. A
   kept kernel gains a CUDA source and changes nothing else.
5. **The tests' CUDA sources compile for `sm_100a` and `sm_120a` exactly as MLX will compile them,** checked on a
   machine without a GPU by `scripts/check_cuda_sources.sh` (MLX 0.32.4's wrapping, NVRTC with MLX's options). It
   found an MLX defect: a negative integer template argument puts `-` into the kernel's function name on CUDA
   ([Apple question 40](../../collaboration/apple_questions.md)); one assertion of `unit_fast` will fail at work
   until MLX changes.
6. **Part C is one command:** `scripts/cuda_session.sh` records the machine, builds both trees, runs E1 to E6 and
   packs a small tarball; `--gate` is the CUDA release check. On dell2 it ran every CPU part and printed a SKIP line
   for each GPU part. `run_parts.sh` now guards the card's memory beside the host's.
7. **Nothing changed on the base's counts:** CPU-only Debug and Release pass with 4,483 checks and 34 guard members
   per build and the same five GPU-only skips, after every phase.

## What changed, phase by phase

| Phase | Diff | What |
| --- | --- | --- |
| 0, the base and the probe | `review/phase_0.diff` | Progress only: the toolchain, the probe's result (its two errors diagnosed as the plan's items 5a and 5b), the base's CPU-only counts, the base linked against the probe's prefix |
| 1, `--cuda` | `review/phase_1.diff` | `scripts/build_mlx_deps.sh` (`--cuda`, `--cuda-arch`, the checks, cuDNN paths, run paths, the stub and the link check, `mlxf_deps.txt`); `cmake/Dependencies.cmake` (`MLXF_CUDA_STUB_DIR`) |
| 2, the backend query and the fourth session | `review/phase_2.diff` | `mlx_cuda_is_available` (`mlxf_device`, `mlxf.f90`, the parity ledger); the refusals per backend; `MLXF_REQUIRE_GPU` ON for a CUDA MLX (`CMakeLists.txt`, `cmake/Dependencies.cmake`); the session classifier and `metal_check_runs` (`mlxf_test_utils`, four testers); rule `devquery` (`check_rules.py`); `ci_cpu_job.sh`; the outside programs, the quickstart, the API reference; the two policies |
| 3, the kernel API and its tests | `review/phase_3.diff` | `mlx_custom_kernel` and its spec (`mlxf_fast`, `mlxf_defs`, `mlxf.f90`), `mlx_metal_kernel` renamed in six toy and bench files and the consumer checks (126 lines, the rename only); a CUDA source for every test kernel and the named-only sub-suite `kernel_sources` (`mlxf_fast_tester`, the registry, `mlxf_test_exec`'s `records=`); **new** `scripts/check_cuda_sources.sh`; the parity ledger's 13 CUDA kernel lines; Apple question 40; binding policy section 12 |
| 4, the memory guard and the session script | `review/phase_4.diff` | `scripts/run_parts.sh` (the card's memory: guard, samples, five columns on a CUDA host only); the polar bench's budget on CUDA; **new** `scripts/cuda_session.sh` |
| 5, the record | `review/phase_5.diff` | the setup guide's section 8 (CUDA), the binding policy (transfers on a discrete card, sections 4, 8, 10, 17), `README.md`, the roadmap's rank 5a row, the index, the history; this report |

**Why macOS is unaffected,** file by file in Progress. In short: the CUDA branches of the scripts and of CMake run
only on Linux with `--cuda`, `MLXF_CUDA_STUB_DIR` or a `libmlx.so` that links `libcuda.so.1`; the build script's
macOS and CPU-only commands traced identical (27 of 28 cases, `--help` the intended difference); the kernel type
takes Metal's path on every non-CUDA build, with the same calls in the same order; every Metal-only check runs on
Metal as before (`metal_check_runs` is true there); `run_parts.sh` writes byte for byte as before where
`nvidia-smi` does not answer. What does change on a Mac: the public name (`mlx_metal_kernel` became
`mlx_custom_kernel`, as ruled) and the printed session text of the outside programs ("Metal or CUDA"; their
branches and exit statuses are unchanged).

## Decisions taken under delegation

| Decision | Reason | Where |
| --- | --- | --- |
| Base `1426c10` (the plan's commit) | its code equals `bb52e8f`, where section 2 was checked | Progress, Phase 0 |
| The CPU-only prefix copied from run `mlxf_linux`; the probe's prefix copied, the base linked against it | same tags, machine and compiler; "copy, do not reuse"; a CUDA-linked base to compare with | Phase 0 |
| The named-only sub-suites run in every count; `TMPDIR` in the run's scratch | the run's instructions name every sub-suite; rank 2h's lesson | Phase 0 |
| Prefixes in the run's scratch; sources from the tags' archives | the repository's `.deps` is not the run's; the fence refuses cloning | Phase 1 |
| One host compiler (nvcc's, with its `gcc`) for all of MLX and mlx-c | one libstdc++ and ABI, as the probe built | Phase 1 |
| The driver detected by the loader (`dlopen("libcuda.so.1")`), in the script and in CMake | the question is whether a program would load | Phase 1 |
| The glibc clash detected by reading the header, and stopped with the fix, never applied | the toolkit is never edited by a run (section 7) | Phase 1 |
| `CMAKE_INSTALL_LIBDIR=lib` on the CUDA branch only (review) | RPM distributions install to `lib64`; the CPU-only commands stay byte for byte | Phase 1 |
| Every real build from a frozen copy of the script | an edit while bash read the running script was undone (sha256 checked) | Phase 1 |
| A CUDA build without a GPU treated as Metal without a device | MLX's allocator cannot start without one | Phase 2 |
| Counts kept equal by rephrasing, not adding (`test_backend`, the device keys) | acceptance 1 holds the gate to the base's counts | Phase 2 |
| A CUDA MLX recognised from `libmlx.so`'s `NEEDED libcuda.so.1`; `MLXF_REQUIRE_GPU` declared after the dependencies | the installed headers and package differ by nothing usable; the default must see them | Phase 2 |
| Rule `devquery` holds the classifier itself to both queries | a missing CUDA query there misclassifies every test | Phase 2 |
| One shared `header`, no `cuda_header`; a non-CUDA build keeps the Metal path | no kernel needs one; CPU-only messages and counts unchanged | Phase 3 |
| A missing backend source refused through `new`'s `status` | a toy must be able to fall back | Phase 3 |
| New checks only in the named-only sub-suite `kernel_sources` | the gate's counts stay the base's | Phase 3 |
| Records written by the test executable (`records=`), not parsed from Fortran | the wrapping depends on the dtypes and ranks a test applies | Phase 3 |
| NVRTC through `ctypes`, not nvcc | MLX compiles with NVRTC and an option nvcc lacks | Phase 3 |
| A failure counted as MLX's only when the source compiles under a valid name | pins the defect and still proves the source | Phase 3 |
| `check_cuda_sources.sh` not in the static gate | it needs a build, a toolkit and MLX's source | Phase 3 |
| The card guarded beside the host; its share per process from the device-wide peak | a part holds both; `nvidia-smi` gives no per-process figure | Phase 4 |
| The card's columns only on a CUDA host | every other reader of the table stays byte for byte | Phase 4 |
| The session's fixed parameters (`nthr` = cores / parts, the suites' defaults, two invocations, n = 160 for accuracy, no `distributed_ring`) | written once in the script, changed in one place at work | Phase 4 |
| SIMPLE's case and grid files as inputs (`--cases`, `--grid`), not repository files | no SIMPLE data in the repository | Phase 4 |
| The setup guide's CUDA section states what was built (12.9 only) and what was checked against MLX's source (`CUDA_HOME` or `CUDA_PATH`, the PTX cache) | the guide is read at work, where nothing here has been run | Phase 5 |
| The roadmap's rank 5 row keeps the three parts and gains a rank 5a row for this run | one row per delivered run, as rank 2h | Phase 5 |

## Deviations from the plan

- **Ruling R1 (Phase 3).** The row the run added for decision 6's rename named `..._workspace_tail.f90` and the two
  kernel-forms bench files without their directories; the fence matches full paths, refused the tail file, and the
  driver stopped the phase. Hans ruled it an omission of the table's form, not of its scope ("renamed in the same
  change"): the controller rewrote the row with the six full paths, Phase 3's work stood, and the run resumed,
  re-ran its gates on the unchanged tree and recorded the ruling (Progress, Phase 3; history, 2026-11-27).
- **Files added to the table, each before its edit:** `test/consumer/` gained Phase 2; `doc/quickstart.md` (2),
  `doc/api_reference.md` (2, 3), the six toy and bench files (3, under R1), `scripts/mlxf_consumer_checks.py` (3),
  `test/mlxf_test_exec.f90` (3), and Phase 3 on `doc/collaboration/apple_questions.md` and the registry.
- **Decision 9's "nvcc" became NVRTC** (above): nvcc cannot compile the source as MLX does.
- **`run_parts.sh` was run with a test double and a fake `nvidia-smi`,** not a real benchmark: none of the series runs
  on a CPU-only MLX (the polar table's budget and the projector's timing need the GPU). Part C runs the real ones.
- **The ABI probe needed no change:** it listed `mlx_fast_cuda_kernel` and its config at the base already.
- **CUDA 12.8 and 13.0 are traced, not built:** only 12.9 is on dell2; 13.0 is first built at work (decision 2).
- **Process:** in Phase 3 a wait matched an old completion marker and the CUDA builds were started again beside a
  finished chain; they did not overlap (recorded in Phase 3's Progress).

## Evidence against the baseline

- **The base's CPU-only suite** (Phase 0): Debug 4.9 s and Release 18.2 s from scratch, zero warnings, fast gate 13 of
  13, 4,483 checks and 34 guard members per build, five GPU-only skips, four named-only sub-suites pass
  (`keep/phase0/`). After Phases 2, 3, 4 and 5 the counts and skip lines are identical in both builds
  (`keep/phase2/area_counts_cpu.md`, `keep/phase3/area_counts_cpu.md`, `keep/phase4/area_counts_session.md`,
  `keep/phase5/`).
- **The CUDA link:** the base linked against the probe's prefix with zero warnings (Phase 0); after Phases 1 to 5 the
  library and `mlxf_test_exec` link against the script's prefix in Debug and Release with zero warnings
  (`keep/phase5/cuda_build_{release,debug}.log`; not run).
- **The build script:** the `--cuda` prefix equals the probe's (`keep/phase1/compare_prefix_final.log`); the macOS and
  CPU-only branches traced (`keep/phase1/trace/`); 31 `--cuda` cases traced, the clash's plant refused.
- **The kernel sources:** `check_cuda_sources.sh` compiles every record, 10 records for each of `sm_100a` and
  `sm_120a`, with the one expected non-compilation and question 40 named; its plant exits 1; another MLX version
  exits 2 (`keep/phase3/`).
- **The install checks:** `check_install.sh`, `check_embed.sh` and `check_toy_offstate.sh` (135 lines) pass
  (Phases 2 and 3).
- **The session:** `cuda_session.sh` ran to its end on dell2 in 1,012 s (15 steps ok, 9 SKIP lines, E1 passed;
  `keep/phase4/session_full_*`), and `--gate` passed on the final tree (`keep/phase5/session_gate5.log`).
- **The static gate** passes after every phase (`keep/phaseN/check_tree*.log`); rule `devquery`'s plants fail.

## Left open for the maintainer

- **The controller's macOS gates on the M5** (section 5): Debug and Release from scratch, the fast gate, every unit
  area, the static, install, embed and off-state checks, the toys' identity set. In particular: the renamed kernel
  type on Metal (`unit_fast`, the toys' kernel forms), the Metal-only checks under `metal_check_runs`, `/bin/bash`
  3.2 on the new code of `build_mlx_deps.sh` and `run_parts.sh`, and the outside programs' new session text.
- **Merging with the K runs:** a K run that adds a use of `mlx_metal_kernel` or its spec after this base renames it
  on merging; conflicts on the six toy and bench files are the rename alone (126 lines).
- **Apple question 40** is open, not sent.
- **For Part C (at work):** bring SIMPLE's `polar_case.txt` and `shiftmap_grid.txt` for the polar steps; put the
  toolkit's `lib64` on the loader path unless the toolkit is in a default one; expect the one `unit_fast` assertion
  of question 40 to fail; read the polar bench's `device=cpu` rows on CUDA knowing their budget is the card's.
- **For Phase 21:** the header comment of `build_mlx_deps.sh` should name NVRTC's builtins beside the driver.
- **Proposed, not applied** (a register or skill edit needs your approval): `doc/architecture_principles.md:221` and
  `.github/skills/mlxf-modern-fortran/references/testing.md:55-57` describe the sessions as Metal's only; they
  should read "Metal or CUDA, each with or without a GPU, and a CPU-only MLX", with `MLXF_REQUIRE_GPU` ON by default
  on a CUDA build as on a development Mac. `apple_questions.md` items 21 and 28 (lines 215 and 343) keep the old
  names as history.
- **Parts B and C:** Part B (`mlxf_cuda_twins`, dell2, after K7) writes the kept kernels' CUDA sources and checks them
  with `check_cuda_sources.sh`; Part C (`mlxf_cuda_blackwell`, at work) runs `cuda_session.sh` on a card.

## Commit message

```
CUDA, Part A: MLX with CUDA built, the backend query, one kernel type for Metal and CUDA, the session script (run mlxf_cuda_prep, roadmap rank 5a)

scripts/build_mlx_deps.sh --cuda builds MLX 0.32.4 and mlx-c 0.8.0 with
CUDA 12.8 to 13.0 and cuDNN 9 for the named Blackwell architectures, with
run paths to the toolkit and cuDNN; it checks the toolkit, nvcc's host
compiler and the glibc clash of CUDA 12's math header first, and on a
host without a driver makes the stub directory mlx-fortran links through
(MLXF_CUDA_STUB_DIR, build only). mlx_cuda_is_available joins the
backend query; a CUDA build without a GPU is refused by name as Metal
without one is, the tests tell four sessions apart, Metal-only checks
skip by name on CUDA, and MLXF_REQUIRE_GPU defaults ON for a CUDA MLX.
mlx_metal_kernel becomes mlx_custom_kernel, whose spec holds a Metal and
a CUDA source (ruled); every test kernel has a CUDA source, and
scripts/check_cuda_sources.sh compiles them as MLX does with NVRTC for
sm_100a and sm_120a without a GPU (Apple question 40: a negative integer
template argument breaks MLX's kernel name on CUDA). run_parts.sh guards
the card's memory on a CUDA host; scripts/cuda_session.sh runs the CUDA
plan's measurements from one command and packs them. The setup guide
gains a CUDA section; the binding policy prices transfers on a discrete
card; README, the policies, the roadmap, the history and the index
follow. Ruling R1: the rename's file-table row names its six files by
full path.

On dell2 (no GPU) the CPU-only suite passes in Debug and Release at the
base's counts (4,483 checks, 34 guard members); the CUDA build of the
library and mlxf_test_exec links with zero warnings; nothing has run on
a GPU.

New files:
scripts/check_cuda_sources.sh
scripts/cuda_session.sh
doc/implementation_notes/completed/mlxf_cuda_report.md
```
