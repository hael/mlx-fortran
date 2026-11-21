---
name: mlxf-binding
description: Use when adding or changing a public wrapper of an MLX operation in mlx-fortran (src/core): when a wrapper may be added at all, finding its generated mlxc_ procedure, the helper of its C signature class, translating dimensions, indices and positions to MLX's row-major 0-based world, the registry check, weak scalars, errors, the re-export in mlxf.f90, and the two-device test it needs.
---

# Adding a wrapper to mlx-fortran

The contract is `doc/policies/binding_contract_policy.md`; how the Fortran is written, the skill
`mlxf-modern-fortran`. This is the procedure.

## 1. Is it wanted?

A public procedure enters only when a pipeline step of the current plan uses it, or a test of such a step
needs its sibling (`cumsum` for a draw, `sum` to test it). The generated layer exposes everything; wrapping
by hand is not free (API, tests, docs). No need, no wrapper.

## 2. Find the generated procedure

`build/gen/mlxf_c_<header>.f90` holds `mlxc_<name>` bound to `mlx_<name>` with the C intents: a handle
passed by value is `type(mlxc_<x>), value`, a pointer the callee sets is `intent(inout)`, a C array input is
`intent(in) :: x(*)`, an enum is `integer(c_int), value` (constants `MLXC_<X>` in `mlxf_c_types`). Read the
mlx-c header for the semantics (a missing name means the generator skipped it: see its printed skip list).
Never write a `bind(c)` interface by hand (rule `cbind`); a C type the generator does not map is a change to
its one mapping table.

## 3. Use the helper of its C signature class

- `int f(mlx_array* res, const mlx_array a, const mlx_stream s)`: `call mlxf_unary(r, mlxc_<name>, a, proc)`.
- `int f(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s)`:
  `call mlxf_binary(r, mlxc_<name>, a, b, proc)`.
- A new class (an axis argument, an output vector, ...) gets **one** new helper beside these in the
  `mlxf_array` family (interface in the parent, implementation in the submodule of its capability), taking the generated procedure as a procedure argument whose abstract interface is
  `bind(c)` with the generated intents; every wrapper of that class uses it, and it is added to
  `ENTRY_HELPERS` of `check_rules.py`. The helpers enter, validate the operands (`mlxf_handle`: empty or stale arrays stop), check that a device can allocate, take the default
  stream, check the status and register the result (`adopt`).
- **Enter first.** The first executable statement of every public procedure is the entry:
  `call mlxf_enter('<public name>')`, `call mlxf_require_device(proc)` for one that allocates, or a call
  of a helper that opens with one (rule `entry`). Nothing touches an operand before it: an empty input still
  passes the one-thread guard. `mlxf_handle` validates an operand and does not enter.
- A function result is set through the helper's first argument (`call mlxf_binary(r, ...)` with `r` the
  result variable), never by assigning a temporary: one registration, no churn.
- More than five inputs: a spec type (rule `arity`). A list of arrays: `type(mlx_array), intent(in) ::
  arrays(:)`.

## 4. Translate to MLX's world, inside the wrapper

- Fortran dimension d of a rank-r array is MLX axis `r - d`; a list of dimensions is translated element by
  element; `order` arguments of permutations are reversed and translated.
- Shapes are reversed (`reshape`, output shapes); broadcasting needs no translation (leading Fortran
  dimensions align with trailing MLX axes).
- Index values and positions are 1-based for the user: subtract 1 inside the graph for arguments, add 1 to
  index results and cast them to int32.
- Scalars are weak: build the 0-d operand with the array's kind (`weak_scalar`), so a real literal never
  changes the result's kind.

## 5. Errors

An error MLX reports while building a graph stops (`mlxf_check(ierr, proc)` without `status`): it is a
program error. Only evaluation and data movement are checked procedures with an optional `status`. A
procedure C++ calls never stops.

## 6. Publish it

Add the name to the module's `public ::` block, then to `src/core/mlxf.f90`'s `use` and `public` lists
(never an `mlxc_` or `mlxf_` helper). Document it in the binding policy when it adds a convention.

## 7. Test it on both devices

In the area's tester (`mlxf_<module>_tester.f90`, a `run_suite` row of `src/test/mlxf_test_registry.f90`):
for each device of `test_devices(devs)` (`mlx_set_default_device`), against a plain Fortran evaluation in
double precision with the tolerance of the plan's section 6, asserting the convention it translates
(dimension numbering, index base, sign, normalisation). float64 on the CPU device only. Never a function
reference inside an array constructor of handles (rule `ctorcall`): build the elements into variables.
A stop that is the contract is a member of a guard group, not an in-process test.

## 8. Before handover

`python3 scripts/restyle_fortran.py` and `python3 scripts/format_use_blocks.py` on the touched files,
`scripts/check_tree.sh`, Debug and Release builds with zero warnings and the fast gate in both.
