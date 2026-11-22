# mlx-fortran agent instructions

These instructions apply to the entire repository. `CLAUDE.md` holds the repository rules and
`doc/architecture_principles.md` where they came from (SIMPLE and XEMA); this file points Codex and Copilot
at the same sources.

## Initialize before editing

1. Inspect the branch and worktree: `git --no-optional-locks branch --show-current` and
   `git --no-optional-locks status --short --branch`. The owner's uncommitted work is in the tree; preserve
   it and do not report it as yours.
2. Read `CLAUDE.md` and `doc/architecture_principles.md`.
3. For Fortran changes read `.github/skills/mlxf-modern-fortran/SKILL.md`; for tests also its
   `references/testing.md`.
4. Read `doc/policies/binding_contract_policy.md` (the binding contract), the plan in progress
   `doc/implementation_notes/planned/mlxf_milestone1.md`, and the decisions block of the design plan
   `doc/implementation_notes/completed/mlxf_design.md` that it cites by number. To add a wrapper of an MLX
   operation, read `.github/skills/mlxf-binding/SKILL.md`.

## Git

Git is read-only: only `log`, `status`, `diff`, `show`, `ls-files`, `grep`, `blame`, with
`--no-optional-locks`. Never `add`, `commit`, `stash`, `mv`, `rm`, `checkout`, `reset`, `rebase`, branch or
history operations; never `git add -A`. Every change stays in the unstaged diff, where the owner reviews it;
a rename or deletion the change needs is done with `mv`/`rm` or described for the owner.

## Development notes

- A pre-implementation design record is one living note (contract, plan, rulings, validation,
  progress) in `doc/implementation_notes/planned/`, written by `doc/how2s/how2write_agent_plans.md`.
  No parallel specification and plan documents for the same development.
- Owner decisions, delivered batches, negative results and overrides go to `doc/history/YYYY-MM.md`.

## Tests

- The rules are `doc/policies/test_environment_policy.md`. A test can fail: it ends in
  `mlxf_test_utils` assertions whose failure reaches the exit status. Checks are free, processes are
  budgeted (`MLXF_CTEST_BUDGET`).
- A unit test is an `mlxf_<thing>_tester.f90` next to the code it tests, registered as a sub-suite
  of an area suite; `mlxf_test_exec` is the only test executable; a stop that is the contract is tested
  in a guard group (`expect_aborts`).
- Expected values come from outside the code under test; seeds are fixed; tests leave no files behind.

## Validation

- Compile and run tests as part of the development cycle (`./compile_debug.sh`, `./compile_clean.sh`,
  `./recompile.sh`, `build/bin/mlxf_test_exec test=unit_<area>`); the static gate is
  `scripts/check_tree.sh`. Report what was built and run, and the results.
- Do not claim a GPU test passed unless its output on a machine with a Metal device was observed.
