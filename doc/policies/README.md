# Policies

The living descriptions of how mlx-fortran is built, tested and bound to MLX. A plan says which policy
it changes and updates it in the same phase; when a plan and a policy disagree, the policy is the truth.
Where each house rule came from (SIMPLE, XEMA, or new here) is `doc/architecture_principles.md`.

| policy | what it rules |
| --- | --- |
| `compile_time_policy.md` | one target, no per-file flags, lean imports, the one re-export module |
| `test_environment_policy.md` | what a test is, the fast gate, devices, testers |
| `binding_contract_policy.md` | memory order, indices, lifetime, errors, threading, precision (written by Phase 1 of the design plan) |
