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
build/bin/mlxf_test_exec test=unit_core
```

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
