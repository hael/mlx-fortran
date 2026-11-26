# Compile-Time Policy

mlx-fortran inherits SIMPLE's compile-time policy (SIMPLE repository,
`doc/policies/compile_time_policy.md`, where the evidence for every rule is recorded) and XEMA's flag and
module-directory policy (`doc/architecture_principles.md`, section 6). The library is small, so only the
rules that apply to it are kept here; they cost nothing at run time and keep the build of a consumer such as
SIMPLE fast.

## Rules

- **One library target.** All library sources under `src/` compile into `mlxf`; no further targets for
  subsets of the sources (with CMake's Make generator a dependent target waits for the whole target it
  depends on). The test executable `mlxf_test_exec` is the one other target; it compiles the test-only
  sources (`src/test/`, `*_tester.f90`), which the library never contains.
- **Per-target module directories.** `mlxf_add_library` gives the library its own module directory under
  `build/modules/`, reachable only through its build interface; the test executable has its own. No global
  module directory: nothing imports a module it does not link, and installing the library never installs a
  test module.
- **Flags on one interface target, never in the cache.** Every compile option is on `mlxf_build_flags`
  (`cmake/CompilerConfig.cmake`); nothing is written into `CMAKE_Fortran_FLAGS*` with `FORCE`, so a user or
  an embedding project keeps its own flags.
- **No per-file compile options** for library sources. Warnings are fixed in the code; the tree builds with
  zero warnings in Debug and Release; `MLXF_WERROR` turns them into errors for the CI.
- **Release is `-O3`.** The Fortran side is glue around MLX; a new global optimisation flag needs a
  run-time benchmark that shows a gain.
- **Lean imports.** Import with `use ..., only:` and only what the module itself needs; an import used
  by one procedure goes into that procedure. Every module-level import is a build-order edge for every
  module that imports this one.
- **One re-export module.** `mlxf` is the library's public face and re-exports the public entities of
  the `mlxf_*` modules for users. No other module re-exports, and no library module imports `mlxf`;
  test code in `src/test/` uses it as a user would.
- **Heavy components are allocatable.** A large derived type held inside another is an `allocatable`
  component, allocated right before its constructor and deallocated in `kill`.
- **Generated sources stay generated.** The `bind(c)` layer is produced at build time from the mlx-c
  headers that are linked (from Phase 1 of the design plan); it is never edited or committed.
- **Bounded job counts.** The compile scripts use the available processors or
  `CMAKE_BUILD_PARALLEL_LEVEL` (`--jobs N` overrides).

## Measuring

Claim a compile-time gain only from a like-for-like comparison of two clean builds on one machine
(same compiler, build type, test setting and job count), as SIMPLE's policy describes.

## The module map of the library

The library's modules, in the order the build needs them; a submodule follows its module and is no build-order
edge for anything else, so editing an implementation recompiles only its own file. `doc/code_base_map.md` has every
file with its description (`scripts/generate_codeoverview.py`).

- **Generated** (`build/gen/`): `mlxf_c_types`, one `mlxf_c_<header>` per mlx-c header, and `mlxf_c_signatures`,
  the C signature classes of `scripts/mlxc_signatures.txt` as abstract interfaces.
- **Definitions** (`src/defs/`): `mlxf_defs`.
- **Runtime** (`src/core/runtime/`): `mlxf_libc`, `mlxf_error`, `mlxf_registry`, `mlxf_device`, `mlxf_stream`,
  `mlxf_memory`, `mlxf_version`.
- **The type** (`src/core/array/`): `mlxf_array` (the type, its lifetime, evaluation, operators and closure
  vectors; submodules `_lifetime`, `_evaluation`, `_elementwise`, `_closure`), then `mlxf_transfer` (the data
  movement generics; submodules `mlxf_transfer_copy`, `mlxf_transfer_borrow`) and `mlxf_calls` (the signature
  helpers several families share; submodules `mlxf_calls_elementwise`, `_shaped`, `_checks`).
- **Operations** (`src/core/ops/`): one module per concern, `mlxf_ops_elementwise`, `_math`, `_logic`, `_shape`
  (its helpers in the submodule `mlxf_ops_shape_calls`), `_index`, `_reduce`, `_create`, `_sort`; `_logic` and
  `_reduce` import `_elementwise`, `_reduce`, `_index` and `_sort` import `_shape`.
- **Families** (`src/core/<family>/`): `mlxf_linalg`, `mlxf_linalg_matrix`, `mlxf_conv`, `mlxf_fft`,
  `mlxf_compile`, `mlxf_export`, `mlxf_transforms`, `mlxf_random`, `mlxf_fast`, `mlxf_io`, `mlxf_distributed`; the
  last four keep their signature helpers in a submodule `mlxf_<family>_calls`. A helper one family calls is
  private to that family.
- **The user module**: `mlxf`, which imports them all and is the only module installed.

A library module or submodule file has at most 1,000 lines (`scripts/check_rules.py`, rule `size`, with
`SIZE_LEDGER` for argued exceptions); a module that would grow past it moves bodies into submodules by concern.
