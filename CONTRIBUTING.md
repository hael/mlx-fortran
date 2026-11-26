# Contributing to mlx-fortran

mlx-fortran is a small library with one target, a generated C layer and a hand-written Fortran layer. Its house
rules come from SIMPLE and XEMA; [`doc/architecture_principles.md`](doc/architecture_principles.md) records which
were adopted and why. What is checked is checked by a script, so a change that breaks a rule fails before review.

## Build and gates

- Toolchain: macOS on Apple silicon, GNU Fortran 14 or newer (tested: 16.2; the CI also runs 15), CMake 3.25+,
  mlx-c as a shared library (`brew install mlx-c`, or `scripts/build_mlx_deps.sh`), `pkgconf` for the install
  check. [`doc/how2s/how2set_up_dev.md`](doc/how2s/how2set_up_dev.md) has the details.
- `./compile_debug.sh` and `./compile_clean.sh` build Debug and Release from scratch, run the fast gate between
  build and install (a failed gate installs nothing); `./recompile.sh` rebuilds incrementally. Pass
  `MLXF_CMAKE_ARGS="-DMLXF_WERROR=ON -DFORTLS=OFF"` to build as the CI does. Zero warnings in both.
- The fast gate (`scripts/run_fast_gate.sh`): the static gate `scripts/check_tree.sh`, then `ctest -L fast`, thirteen
  entries under 60 s. One area by hand: `build/bin/mlxf_test_exec test=unit_<area> [suite=] [device=cpu|gpu]`.
- `scripts/check_install.sh BUILD` installs a build and compiles and runs the consumer and the examples of
  `test/consumer/` against it; `scripts/check_embed.sh` adds the library to a parent project.
- `scripts/release_gate.sh` is what a release needs: on a Mac with a GPU it builds a snapshot of the commit
  (`git archive`) in Debug and Release, runs the fast gate and the install check on each with the GPU required,
  and fails on any skip or editor side effect. `--allow-dirty` judges the working tree, `--require-tag` the tag.
- The CI (`.github/workflows/ci.yml`) runs `scripts/ci_cpu_job.sh` against a CPU-only MLX, where the device tests
  run on the CPU, and builds against Homebrew's Metal MLX. It cannot see a GPU; the release gate can.

## The rules and where they are checked

- `scripts/check_rules.py` (in the static gate) holds every rule reading can check: layout, visibility, the
  generated layer's boundary, the entry guard, ownership traps of gfortran (`ctorcall`, `ctorexpr`), at most five
  dummy arguments, exported constants in `src/defs`, the parity ledger, NaN-safe error reductions (`nanmax`),
  CMake paths (`cmakeroot`), `-DFORTLS=OFF` downstream (`fortlsoff`), device queries in test code (`devquery`),
  the documents' examples (`docex`), the callbacks' passing modes (`cbsig`) and the finalizer and defined
  assignment of every type that holds a handle (`handle`). `python3 scripts/check_rules.py --list` prints them
  with their ledgers;
  a ledger may only shrink. A new rule comes with its check and a planted violation shown to fail.
- `scripts/check_test_registry.py`, `check_descr.py`, `check_guide_imports.py`, `check_submodule_linkage.py`,
  `format_use_blocks.py --check` and `restyle_fortran.py --check --tree` cover the rest. Before handing over, run
  `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` on every Fortran file you touched.
- Python the build or the gate runs uses the standard library and nothing newer than 3.7.
- The skills in `.github/skills/` are the working summaries: `mlxf-modern-fortran` (how the Fortran is written),
  `mlxf-binding` (adding a wrapper), `mlxf-agent-runs` (agent runs).

## Tests and plans

- A test can fail, takes its expected value from outside the code under test, names and derives its tolerances,
  and runs on every device `test_devices` returns. It joins its area as a sub-suite (a `run_suite` row of
  `src/test/framework/mlxf_test_registry.f90`); a new CTest entry needs a reason and raises the budget of 13 (the parity plan's ceiling). A stop that is
  the contract is a member of a guard group. The rules: [`doc/policies/test_environment_policy.md`](doc/policies/test_environment_policy.md).
- A change to the public API follows the parity ledger (`scripts/mlxc_parity.txt`) and the binding contract
  ([`doc/policies/binding_contract_policy.md`](doc/policies/binding_contract_policy.md)), which is the truth on
  memory order, indices, lifetime, kinds, errors and devices.
- Work for an agent is a plan in `doc/implementation_notes/planned/` written by
  [`doc/how2s/how2write_agent_plans.md`](doc/how2s/how2write_agent_plans.md): a pinned base, numbered decisions,
  an exit per phase, frozen floors, a file table and stop conditions. Decisions and delivered batches go to
  `doc/history/`; questions for the MLX team to `doc/collaboration/apple_questions.md`.

## Policies

[Binding contract](doc/policies/binding_contract_policy.md), [compile time](doc/policies/compile_time_policy.md),
[tests](doc/policies/test_environment_policy.md), [toy examples](doc/policies/toy_example_policy.md).
The library is MIT-licensed; contributions are under the same license.
