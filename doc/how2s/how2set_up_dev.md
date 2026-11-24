# How to set up mlx-fortran for development

## 1. Toolchain

- macOS on Apple silicon; Xcode with the Metal toolchain only for the source build of MLX and for GPU
  profiling (section 2).
- Homebrew: `brew install gcc cmake` (GFortran 14 or newer; the scripts pick the newest `gfortran-1x`).

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
(a headless or sandboxed session, a virtual machine); `MLXF_WERROR` turns warnings into errors. The compile
scripts pass the environment variable `MLXF_CMAKE_ARGS` to CMake, as the CI does:
`MLXF_CMAKE_ARGS="-DMLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON" ./compile_clean.sh`. The build generates the
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

For arun itself, follow `SETUP.md` in the `agent_runs` checkout; the run spec supplies the machine-specific
settings.
