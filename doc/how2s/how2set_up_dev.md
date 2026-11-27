# How to set up mlx-fortran for development

## 1. Toolchain

- macOS on Apple silicon; Xcode with the Metal toolchain only for the source build of MLX and for GPU
  profiling (section 2).
- Homebrew: `brew install gcc cmake` (GFortran 14 or newer; the scripts pick the newest `gfortran-1x`).
  Tested: GNU Fortran 16.2.0, the whole tree; 14.4.0 (`brew install gcc@14`) builds the library without a
  warning and passes the installed-consumer check, but not the test executable (a `-Wuninitialized` false
  positive in `src/test/bench/mlxf_bench_polar_table.f90` and a submodule's own procedures it does not link in
  `src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester_solve.f90`), so the CI's oldest leg is 15 (`gcc@15`).
- `pkg-config` (`brew install pkgconf`) for `scripts/check_install.sh`.

## 2. MLX and mlx-c

Either of:

- **Pinned, from the local clones** (the default for development): `scripts/build_mlx_deps.sh`. It
  exports MLX `v0.32.4` and mlx-c `v0.8.0` from `~/src/mlx` and `~/src/mlx-c` with `git archive` (the
  clones are not touched), builds them as shared libraries with Apple's clang, and installs them in
  `.deps/install`, where `cmake/Dependencies.cmake` looks first after `MLXC_ROOT`. Other tags:
  `MLX_REF=... MLXC_REF=... scripts/build_mlx_deps.sh`; the pair must match (mlx-c names its MLX in
  its `CMakeLists.txt`).
- **Homebrew**: `brew install mlx-c` (it brings `mlx`; on 2026-11-20 the bottles were MLX 0.32.4 and
  mlx-c 0.8.0, the pinned pair). Found through the default prefixes once `.deps/install` is absent, or with
  `-DMLXC_ROOT=$(brew --prefix)`. Needs no Xcode. Homebrew's `mlx` depends on a `python@3.x` for its Python
  bindings, and installing it can take over the unversioned `python3` link; the libraries do not use it. If
  `python3 --version` changed, put it back with `brew unlink python@3.15` and
  `brew unlink python@3.14 && brew link python@3.14` (with your versions).

- **CPU-only, pinned**: `scripts/build_mlx_deps.sh --cpu-only` builds the same tags without the Metal backend
  (`MLX_BUILD_METAL=OFF`; no Xcode needed) into `.deps/install-cpu`, which no build searches by default:
  `MLXC_ROOT=$PWD/.deps/install-cpu`. Such an MLX has no GPU and allocates on the CPU device, so the device tests
  run on the CPU where no GPU opens, as on GitHub's runners (the CI's CPU-only jobs run
  `scripts/ci_cpu_job.sh Debug|Release gfortran-1x`, which builds it when the prefix is empty). `PREFIX=` and
  `WORK=` move the install and the scratch directory.

Xcode is needed only to build MLX from source (`build_mlx_deps.sh`) and for GPU profiling (Instruments'
Metal System Trace, and the `.gputrace` captures of `mlx_metal_start_capture`). Custom Metal kernels are
compiled at run time by the Metal framework and need no Xcode.

## 3. Build and test

```bash
./compile_debug.sh            # Debug, runtime checks; the fast gate runs before install
./compile_clean.sh            # Release
./recompile.sh                # incremental, with the gate
build/bin/mlxf_test_exec test=list
build/bin/mlxf_test_exec test=unit_core device=cpu       # device=cpu|gpu|all
build/bin/mlxf_test_exec expect_aborts object_contracts  # the guard group, each member in a child
```

Options: `MLXF_REQUIRE_GPU` (ON on Apple silicon) fails the device tests when the session cannot open a GPU
(a headless or sandboxed session, a virtual machine, or a CPU-only MLX); `MLXF_WERROR` turns warnings into
errors. The compile scripts pass the environment variable `MLXF_CMAKE_ARGS` to CMake, as the CI's Metal
build-only jobs do: `MLXF_CMAKE_ARGS="-DMLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON -DFORTLS=OFF" ./compile_clean.sh`.
The tests tell the sessions apart (`mlxf_test_utils`): Metal or CUDA with a GPU runs both devices (on CUDA the
checks of Metal's own behaviour skip by name); either without one cannot allocate and skips; a CPU-only MLX runs the
CPU device, and the checks that need the GPU or Metal's allocator skip with `SKIP: GPU-only check on a CPU-only MLX
build`. The build generates the
`bind(c)` layer from the mlx-c headers it links (`build/gen/mlxf_c_*.f90`) and fails if the generator and
the independent prototype list disagree. `unit_core`'s recovery test evaluates 1 GiB per device after the
failure; its half-batch form, `build/bin/mlxf_test_exec test=unit_core suite=recovery_half`, allocates half
of the GPU's maximum buffer length per device (65 GB on a 192 GB M2 Ultra) for a few seconds and runs only
when named.

## 4. Claude Code

The build installs the `fortls` language server in `build/tools/fortls` and registers its Claude Code
plugin for this checkout (`FORTLS=ON`, as in SIMPLE); offline it only warns.

The repository's permission settings belong in `.claude/settings.json` (SIMPLE's, with this
repository's commands); create it by hand:

```json
{
  "permissions": {
    "allow": [
      "Bash(rg:*)", "Bash(ls:*)", "Bash(find:*)", "Bash(cat:*)", "Bash(grep:*)",
      "Bash(git status)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
      "Bash(cmake:*)", "Bash(make:*)", "Bash(ctest:*)",
      "Bash(./compile_clean.sh:*)", "Bash(./compile_debug.sh:*)", "Bash(./recompile.sh:*)",
      "Bash(scripts/run_fast_gate.sh:*)", "Bash(./scripts/run_fast_gate.sh:*)",
      "Bash(build/bin/mlxf_test_exec:*)",
      "Bash(python3 scripts/check_test_registry.py:*)", "Bash(python3 scripts/check_descr.py:*)",
      "Bash(python3 scripts/check_guide_imports.py:*)"
    ],
    "deny": ["Bash(git commit:*)", "Bash(git push:*)"]
  }
}
```

## 5. Unattended runs (arun)

A plan in `doc/implementation_notes/planned/` is arun-ready (SIMPLE's `doc/how2s/how2run_autonomous_agents.md`).
Start from `templates/generic` of `~/agent_runs` with: `PROJECT=mlx-fortran`,
`LOCAL_REPO=~/src/mlx-fortran`, `PLAN=doc/implementation_notes/planned/<plan>.md`,
`PLAN_DONE=doc/implementation_notes/completed/<plan>.md`, `ALLOW_TABLE="### File table"`,
`PATH_BASE=` (paths in the table are from the repository root), `COMPANION=".f90:_tester"`,
`COPY_EXCLUDES="/build/ /build_*/ /.deps/work/"`, `TOOLS="gfortran cmake make xcrun"`,
`CHECKOUT_MARKER=compile_debug.sh`. GPU phases run on a Mac, not on the Linux box.

## 6. New Mac for a run

Prepare the machine before the run, in a Terminal session with access to its GPU. The working MLX pair is
MLX **0.32.4** and mlx-c **0.8.0**; a newer pair needs the owner's decision and revalidation. These are
the Homebrew formula versions observed on 2026-11-22, not a promise that `brew install` will keep selecting
them. Check before installing:

```bash
xcode-select --install
brew info mlx mlx-c gcc cmake fftw libtiff
```

Command Line Tools suffice for the bottled dependencies and the Fortran builds. Building MLX from source
or profiling Metal requires Xcode; for the source build also install its Metal toolchain with
`xcodebuild -downloadComponent MetalToolchain` and select Xcode with `xcode-select`. Install Homebrew using
its official instructions if it is not already present.

On that date Homebrew listed bottles for macOS 26 Apple silicon: MLX 0.32.4, mlx-c 0.8.0, GCC 16.2.0,
CMake 4.5.1, FFTW 3.3.11 and libtiff 4.7.2; libtiff brings jpeg-turbo. The MLX and mlx-c bottles were
fetched and their checksums verified. If `brew info` still shows the pinned MLX pair, install the tools and
dependencies and check what was actually installed:

```bash
brew install gcc cmake fftw libtiff mlx-c
brew list --versions gcc cmake fftw libtiff jpeg-turbo mlx mlx-c
gfortran --version
cmake --version
python3 --version
```

The build's Python floor is 3.7. Homebrew's MLX formula also brings its own Python dependency; check the
selected `python3` after installation. If the formula versions have moved, **do not install a newer pair as
the pin**. The alternative is the pinned source build in section 2, using clones containing MLX tag
`v0.32.4` and mlx-c tag `v0.8.0`, Xcode with its Metal toolchain, and network access for MLX's build
dependencies. It installs into `.deps/install` and does not replace Homebrew packages. A local Homebrew tap
with extracted historical formulae may be another option, but its bottle availability and dependency
compatibility must be checked; it is not assumed to reproduce this installation.

Use SIMPLE at the run's pin and verify it before building. The current milestone comparator is
`0a8b0903eee151700305399e8e3ff53c2c21caae` (decision 27), including the optimized shift maps and measured
FFTW planning. Earlier planner-only results at `67c6a05e2` are historical context. The independent M5
measurement uses mlx-fortran `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47`; packaging and parity work belong
to other source snapshots. If either pin is missing locally, obtain the intended source from the owner
before proceeding; a nearby commit does not reproduce that comparator. SIMPLE requires FFTW in single and double precision, TIFF, JPEG and zlib; it fetches its pinned
OpenBLAS 0.3.34 during configuration and builds it into its own cache, so the first build needs network
access. In the SIMPLE checkout:

```bash
git --no-optional-locks log -1 --format='%H %s'
./compile_clean.sh
```

Build mlx-fortran as in section 3. From Terminal, run `build/bin/mlxf_test_exec test=unit_core` and verify
that it reports one GPU device and prints its name and architecture. A sandboxed or headless session may
report zero; that is not a successful GPU validation.

Run `bash scripts/release_gate.sh` for the Debug/Release GPU-visible release checks. It does not include
the named-only production-geometry shiftmap accuracy check. In both build types also invoke:

```bash
MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE OMP_THREAD_LIMIT=4 \
  build/test/mlxf_test_exec test=unit_kernels suite=polar_shiftmap device=all
MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE OMP_THREAD_LIMIT=4 \
  build/test/mlxf_test_exec test=unit_kernels suite=polar_shiftmap_accuracy device=all
```

Substitute the actual build directory. Do not run the memory-scaled `recovery_half` suite on the laptop.
The stronger shiftmap regression fixtures are supplied as a separate test-only patch, with its SHA-256
and unchanged-source manifest in the preparation record. Validate that patch in a separate copy of the
measurement base, then build the measured executable from the unchanged baseline. Retain both source
manifests and label the correctness supplement separately; installing a newer package or building parity
work in the measurement source directory would change the experiment.

Future CPU comparisons use `fftw_plans=measure` and `nthr=` set to the machine's full CPU team, with the
planning log outside the warm loop. Keep `estimate` identity files separate. Use two independent
invocations, each with its built-in warm-up and three repeats. The launch specification must account for
both dense scoring and both shiftmap grids, all graph alternatives, requested outputs, memory and source
provenance before a measurement starts. Laptop correctness checks do not establish M5 launch readiness.

For NAX, record the `architecture` printed by that test and the macOS version. In MLX 0.32.4, device
information reports `device_name` and `architecture`, but no NAX-in-use key. Its NAX availability check
also depends on the library's build, macOS 26.2 or later and the architecture generation; on a Mac it
requires generation 17 or later. The architecture alone cannot prove the installed library enabled NAX or
that a particular operation used it. Confirm actual dispatch with a Metal capture/profile of the workload,
and record what the capture shows. For float32 matrix products, `MLX_ENABLE_TF32=0` disables that NAX path;
the variable defaults to enabled and is read once per process, so set it before starting the program.
CTest sets it to zero. The pinned sources are
[`device_info.cpp`](https://github.com/ml-explore/mlx/blob/v0.32.4/mlx/backend/metal/device_info.cpp#L25-L51),
[`device.cpp`](https://github.com/ml-explore/mlx/blob/v0.32.4/mlx/backend/metal/device.cpp#L978-L995),
[`matmul.cpp`](https://github.com/ml-explore/mlx/blob/v0.32.4/mlx/backend/metal/matmul.cpp#L960-L966) and
[`utils.h`](https://github.com/ml-explore/mlx/blob/v0.32.4/mlx/utils.h#L225-L227).

Corrections from the M5 run (`mlxf_m1_m5`, 2026-11-24):

- `scripts/release_gate.sh` needs `.git` (`rev-parse`). A `git archive` export of the measurement base is
  configured by hand with the gate's options (`-DBUILD_TESTS=ON -DMLXF_REQUIRE_GPU=ON -DMLXF_WERROR=ON
  -DFORTLS=OFF`), built, and then given `scripts/run_fast_gate.sh <tree>`. Its checks are then applied: no
  `SKIP` in `Testing/Temporary/LastTest.log`, "GPU devices: 1", and no compiler warning. The static gate
  passes without `.git`.
- SIMPLE builds offline from a `git archive` export once `.deps/downloads` and `.deps/numerics` are copied
  in from a checkout that built the same compiler's OpenBLAS. Configuration then reports "Reusing the
  cached OpenBLAS".
- At `4706ecb`, `bench_polar_table suite=shiftmap` reads no `nthr` (its timing is the GPU with one
  submitting thread), and `suite=accuracy` uses teams 1 and 24 built in. Pass `nthr` to `time`,
  `profile`, `overlap` and `stream`. After milestone 1's hold closed, `suite=shiftmap` refuses `nthr=` with
  a message, and the benchmark's rows carry `mlx_cache_bytes` beside the peak.
- **NAX dispatch from a trace:**
  - With Xcode installed, no `xcode-select` change is needed:

    ```bash
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer timeout 300 xcrun xctrace record       --template 'Metal System Trace' --time-limit 180s --output <name>.trace --launch -- <wrapper> <args>
    ```

    `<wrapper>` exports `MLX_ENABLE_TF32` and execs the executable.
  - Read the trace with `xctrace export --toc`, then export the table `metal-shader-profiler-shader-list`
    and filter its rows to the launched process. The traced process is named after the wrapper.
  - On the M5 Ultra (`applegpu_g17d`, macOS 27.2.1) the float32 products dispatch
    `steel_gemm_fused_nax_nn_float32_*` with `MLX_ENABLE_TF32=1`, and only `steel_gemm_fused_nn_float32_*`
    with `0`.

For arun itself, follow `SETUP.md` in the `agent_runs` checkout; the run spec supplies the machine-specific
settings.

## 7. Linux, CPU only

Tested on Ubuntu 26.04 (x86-64) with GNU Fortran 15.2 and 14.3, CMake 4.2 and Python 3.14, and written for
GitHub's Ubuntu 24.04 runners. A CPU-only MLX has no GPU backend (CUDA is section 8): every test runs on the CPU
device and the GPU-only checks skip, as with a CPU-only MLX on a Mac.

- **Packages:** `gfortran` 14 or newer, `gcc`, `g++`, `cmake`, `pkg-config`, and BLAS and LAPACK with LAPACKE's
  headers: `libopenblas-openmp-dev liblapacke-dev` (MLX's guide names `libblas-dev liblapack-dev liblapacke-dev`;
  OpenBLAS's development package provides the first two). GNU Fortran 14 builds and passes the whole tree on Linux
  (14.3), unlike 14.4 on macOS (section 1).
- **MLX and mlx-c:** `scripts/build_mlx_deps.sh` (CPU only: `--cpu-only` is implied; into `.deps/install-cpu`; about
  1.5 minutes on 16 cores). `MLX_SRC` and `MLXC_SRC` name clones, or GitHub's archives of the tags
  (`https://github.com/ml-explore/mlx/archive/refs/tags/v0.32.4.tar.gz`, mlx-c's likewise), whose commit the script
  checks and records in `mlxf_deps.txt`; an unattended run whose fence refuses `git clone` uses the archives. GCC
  builds both, and the installed libraries find each other through `$ORIGIN`.
- **Build:** point the build at the prefix, as for a CPU-only MLX on a Mac:
  `export MLXC_ROOT=$PWD/.deps/install-cpu` and
  `MLXF_CMAKE_ARGS="-DMLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON -DFORTLS=OFF" ./compile_clean.sh`;
  `scripts/check_install.sh` finds mlx-c through the same `MLXC_ROOT`.
- **CI:** `scripts/ci_linux_job.sh Debug|Release gfortran-1x` is the Linux job: `scripts/ci_cpu_job.sh` (the CPU-only
  MLX, the build, the fast gate, the installed consumer), then `scripts/check_embed.sh` and
  `scripts/check_toy_offstate.sh` (with `--exec` in Release).
- **At run time** MLX compiles the CPU kernels of compiled graphs with `g++`, as on a Mac (it must be on `PATH`;
  without it they run uncompiled) and caches them under `$TMPDIR/mlx/0.32.4/cpu`; where Open MPI is installed,
  `unit_distributed` starts an MPI singleton, whose session directory also goes to `$TMPDIR`. On a shared machine
  point `TMPDIR` at a scratch directory for test runs.
- **Compiler notes:** GCC built with native-language support quotes names in its messages with typographic quotes
  in a UTF-8 locale (the scripts match around them); GNU Fortran 15 on Linux gives a private module procedure whose
  body is in its module internal linkage, so a submodule cannot call it (`scripts/check_submodule_linkage.py`).

## 8. Linux with CUDA (NVIDIA)

Prepared on dell2 (Ubuntu 26.04, no GPU, no driver) with CUDA 12.9 and cuDNN 9.28: MLX, mlx-c, the library and
`mlxf_test_exec` build and link, and the tests' CUDA sources compile for Blackwell. Nothing has run on a GPU yet; the
first session is at work (`doc/implementation_notes/planned/mlxf_cuda.md`, Part C).

- **The toolkit:** CUDA 12.8, 12.9 or 13.0 (Blackwell, `sm_100`/`sm_120`, needs 12.8 or newer; MLX 0.32.4 refuses 13.1),
  with the NVIDIA driver it needs (575 or newer for 12.9, 580 for 13.0). Only 12.9 has been built so far. Where NVIDIA's
  installer cannot run (on Ubuntu 26.04 it needs `libxml2.so.2`), the runfile's components can be unpacked into a
  directory of one's own.
- **cuDNN 9** for that CUDA major (`libcudnn9-dev-cuda-12`, or the archive unpacked anywhere and named by `CUDNN_ROOT`).
- **The host compiler:** nvcc 12.x accepts GCC 14 at most, 13.0 GCC 15 (`gcc-14`/`g++-14` beside a newer GCC are fine).
  `build_mlx_deps.sh` picks the newest `g++-N` nvcc accepts, or `CUDAHOSTCXX`; it compiles all of MLX and mlx-c.
  mlx-fortran itself keeps its own GNU Fortran.
- **glibc 2.41 or newer with CUDA 12.x:** glibc declares `cospi`, `sinpi`, `rsqrt` and their `f` forms `noexcept`,
  CUDA 12's `crt/math_functions.h` does not, and nvcc fails on every file. The toolkit's owner adds `noexcept (true)`
  to the six declarations once, keeping the original:
  `sed -i.orig -E 's/^(extern .*[[:space:]](rsqrtf?|sinpif?|cospif?)\((double|float) x\));/\1 noexcept (true);/'
  <toolkit>/include/crt/math_functions.h`. `build_mlx_deps.sh --cuda` stops with this command when the header
  needs it and never edits the toolkit; CUDA 13.0 has the fix.
- **MLX and mlx-c:** `CUDA_HOME=<toolkit> CUDNN_ROOT=<cudnn> scripts/build_mlx_deps.sh --cuda` (into
  `.deps/install-cuda`; both took 9 minutes on dell2's 16 cores, and MLX's configure needs the network). On a machine
  with the GPU MLX compiles for that GPU; elsewhere name the architectures: `--cuda-arch 100a` (B200, GB200), `120a`
  (RTX-class Blackwell) or `'100a;120a'`. `libmlx.so` finds the toolkit's and cuDNN's libraries through its run path;
  `mlxf_deps.txt` records the toolkit, cuDNN, the host compiler, the architectures, glibc and the driver.
- **Build:** `MLXC_ROOT=$PWD/.deps/install-cuda`; nothing CUDA-specific is passed. CMake recognises the CUDA build (its
  `libmlx.so` links `libcuda.so.1`) and makes `MLXF_REQUIRE_GPU` default ON. On a machine without a driver the test
  executable links only through the toolkit's stub: `-DMLXF_CUDA_STUB_DIR=<prefix>/cuda-stub` (made by `--cuda`; build
  only, refused where a driver is installed).
- **At run time:** the driver's `libcuda.so.1` comes from the system. MLX compiles kernels with NVRTC, which needs the
  toolkit's headers (`CUDA_HOME` or `CUDA_PATH`, MLX's variables, unless the toolkit is `/usr/local/cuda`) and opens
  `libnvrtc-builtins` by name: a toolkit outside the loader's default path needs its `lib64` on `LD_LIBRARY_PATH` or in
  `ld.so.conf`. MLX caches the compiled kernels under `TMPDIR` (`mlx/<version>/ptx`, or `MLX_PTX_CACHE_DIR`).
  `CUDA_VISIBLE_DEVICES` selects the card; `MLX_ENABLE_TF32=0` keeps float32 products in full precision, as in CTest.
- **Checks without a GPU:** `scripts/check_cuda_sources.sh <build>` (with `CUDA_HOME` and `MLX_SRC`, MLX's source or its
  tag's archive) wraps every CUDA source of the tests' kernels as MLX does and compiles it with NVRTC for `sm_100a` and
  `sm_120a`.
- **The session at work:** `scripts/cuda_session.sh [--gate] [--cases polar_case.txt --grid shiftmap_grid.txt]` builds
  both trees, runs the bring-up and the measurements of the CUDA plan, and packs them with the machine's facts into
  `build/cuda_session/<date>.tar.gz`; `--gate` is the CUDA release check.
- **Known:** on CUDA, MLX 0.32.4 names a kernel with a negative integer template argument with a `-`, which does not
  compile (Apple question 40); one assertion of `unit_fast` ("a negative integer parameter compiles") fails there
  until MLX changes.
