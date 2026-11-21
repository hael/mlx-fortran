# mlx-fortran

mlx-fortran is a modern Fortran interface to MLX, Apple's array framework for the unified CPU/GPU memory
of Apple silicon. It binds MLX's C API (mlx-c) and is meant for the public (MIT) and for SIMPLE, the cryo-EM
package it was started for. It is a small library with one target, a generated C layer and a hand-written
Fortran layer. Its house rules are SIMPLE's and XEMA's (`~/src/X`, which adopted SIMPLE's architecture item
by item and checks most of it): `doc/architecture_principles.md` is the register of what was adopted,
adapted or rejected, and why.

## Where the decisions are

- `doc/implementation_notes/planned/mlxf_design.md` is the design plan: its numbered decisions are the
  contract until Phase 1 writes them into `doc/policies/binding_contract_policy.md`; from then the policy
  is the truth and the plan is history.
- `doc/architecture_principles.md`: the house rules' origin and reasons. A disagreement between it and a
  skill is a defect fixed first.
- `doc/policies/`: the compile-time and test policies.
- `doc/history/YYYY-MM.md`: owner decisions, delivered batches, negative results, overrides; newest first.
- `doc/how2s/how2write_agent_plans.md`: how a plan for an agent is written (from SIMPLE).

## Use the repo skills

Skills live in `.claude/skills/` (a symlink to `.github/skills/`, shared with Copilot and Codex).
`src/CLAUDE.md` imports `mlxf-modern-fortran`, which loads the first time a file under `src/` is read; its
`references/testing.md` is the test rules in short. Edit the `SKILL.md`, never the importing `CLAUDE.md`;
`scripts/check_guide_imports.py` (in the static gate) catches a broken import.

## Structure

- `src/core/`: the hand-written Fortran layer (`mlxf_*` modules) and its testers.
- `src/test/`: test-only code (assertions, the suite registry, SIMPLE-shaped kernels and benchmarks).
  It and every `*_tester.f90` compile into `mlxf_test_exec`, never into the library.
- `test/`: `mlxf_test_exec`, the one test executable, and the CTest entries with their budget.
- `scripts/`: the static gate (`check_tree.sh` and its checks), the formatters (`restyle_fortran.py`,
  `format_use_blocks.py`), `fix_warnings.py`, the compile helpers, `build_mlx_deps.sh`, and from Phase 1
  the generator of the C layer.
- `build/gen/`: generated at build time, never edited: the build facts (`mlxf_build_info.inc`) and, from
  Phase 1, the `bind(c)` layer generated from the mlx-c headers that are linked.
- `doc/`: the register, plans (`implementation_notes/{planned,completed,rejected}`), policies, history,
  how-tos, `compiler_issues/` (reproducers of compiler bugs the library works around).

## The library's rules

- Public names: MLX-specific types and procedures `mlx_<x>`; generics that extend Fortran intrinsics keep the
  intrinsic's name (`matmul`, `sum`, `exp`); modules `mlxf_<x>`; the generated layer's entities `mlxc_<x>`.
  Users import `mlxf`.
- No SIMPLE type, constant or naming enters the library. SIMPLE is the first consumer and decides what is
  built first; the API stays general and grows only with a demonstrated need.
- The Fortran view is Fortran's: column-major arrays, 1-based dimensions, indices and positions. Translating
  to MLX's row-major, 0-based world is the library's job, never the user's.
- Every call of mlx-c checks its status; MLX's errors never exit the process from inside C++, and a
  procedure C++ calls never stops.

## Engineering defaults

- Prefer existing patterns (this repository's, then SIMPLE's and XEMA's) over new abstractions; keep changes
  scoped. A second code path for the same computation needs a measured gain above 30 %.
- Preserve dirty worktree changes that are not part of the task.
- Use `rg` / `rg --files` first when searching.
- Build and test as part of the development cycle: `./compile_debug.sh` and `./compile_clean.sh` from
  scratch (both run the fast gate, the static gate first, before installing), `./recompile.sh`
  incrementally. Debug and the gate after every step; Release and the gate before a handover. Run the
  touched area's `build/bin/mlxf_test_exec test=unit_<area>`. Report what was built and run, and the
  results; never claim a result you do not have.
- Before handover: `scripts/check_tree.sh`, and `scripts/restyle_fortran.py` and
  `scripts/format_use_blocks.py` on every Fortran file you touched. Zero compiler warnings in Debug and
  Release.
- mlx-c is found under `MLXC_ROOT`, `.deps/install` (`scripts/build_mlx_deps.sh`) or Homebrew
  (`brew install mlx-c`); it must be the shared library.
- The library reads no environment variable of its own; MLX's (`MLX_ENABLE_TF32`) are MLX's, and CTest sets
  `MLX_ENABLE_TF32=0`.
- Python the build or the gate runs uses the standard library and nothing newer than 3.7.
- A plan for an agent follows `doc/how2s/how2write_agent_plans.md`: pinned base, numbered quantified
  decisions, an exit per phase, floors tagged by origin and frozen before the run they judge, a file
  table, stop conditions.
- Every rule reading can check gets its check in `scripts/check_rules.py` in the same change, with a planted
  violation shown to fail; a ledger may only shrink.
- Dead code found during work is deleted; "dead" is proved by the compiler, not by a search.
- Never commit or push; git is read-only for agents. The maintainer decides what is committed and pushed:
  leave changes in the working tree and say which are ready.

## Fortran conventions (the skill has the full set)

- `use ..., only: ...` imports; `implicit none`; every library module restricts its interface with one
  `public ::` block and a bare `private`.
- One module or submodule per file, opened by one `!@descr:` line; a `<dir>.inf` per Fortran directory.
- Comments use `!`, never `!>`; they are self-contained and never cite plans, sections or dates.
- Constants in CAPITALS; optionals passed by keyword; no `block`, `goto` or operator interface blocks; no
  `==` on reals.
- Stateful types have `new`/`kill` symmetry; a type holding an MLX handle also has a `final` procedure and
  a defined assignment that adds a reference. A derived type with an allocatable handle component assigns
  that component explicitly (gfortran skips the defined assignment there).
- No calls into the library from inside an OpenMP parallel region.

## Compile time

`doc/policies/compile_time_policy.md` is the rule set: one library target, flags only on
`mlxf_build_flags` (never forced into the cache), per-target module directories, no per-file compile
options, lean module-level imports with `only:`, `mlxf` the one public re-export module.

## Maintaining this config

After a significant task, propose small updates to `.github/skills/`, the register and this file when a
pattern or guardrail is worth capturing, with its check where reading can check it. Apply skill edits only
when explicitly requested or approved. Keep them concise and aligned with what the repository does.
