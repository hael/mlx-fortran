---
name: mlxf-binding
description: "Use when adding or changing a public wrapper of an MLX operation in mlx-fortran (src/core): when a wrapper may be added at all, finding its generated mlxc_ procedure, the helper of its C signature class, translating dimensions, indices and positions to MLX's row-major 0-based world, the registry check, weak scalars, errors, the re-export in mlxf.f90, and the two-device test it needs."
---

# Adding a wrapper to mlx-fortran

The contract is `doc/policies/binding_contract_policy.md`; how the Fortran is written, the skill
`mlxf-modern-fortran`. This is the procedure.

## 1. Is it wanted?

A public procedure enters only when a pipeline step of the current plan uses it, or a test of such a step
needs its sibling (`cumsum` for a draw, `sum` to test it), or the parity ledger `scripts/mlxc_parity.txt`
lists its mlx-c function as `pending` (parity with mlx-c is a goal; MLX's documented API is the need). Use
the ledger's planned Fortran name, and change its line to `public` (or `plumbing`) in the same change:
rule `parity` fails until the line and the code agree, and the pending count only shrinks. The generated
layer exposes everything; wrapping by hand is not free (API, tests, docs). Outside the ledger: no need, no
wrapper.

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
- Added classes in `mlxf_calls` and the family modules: `mlxf_int_op` (dtype/integer), `mlxf_vector_op` (shape or
  axes), `mlxf_reduce_op` (dimension, removes it), `mlxf_scan_op` (inclusive forward scan),
  `mlxf_ternary_op` (three operands), `mlxf_take_op`, `mlxf_concat_op`, `mlxf_slice_op`,
  `mlxf_zeros_op`, `mlxf_range_op`, and `mlxf_fft_op` / `mlxf_fft2_op`. Multi-option requests use
  the behaviourless records in `mlxf_defs`; these helpers all perform entry, validation and adoption.
  The FFT wrappers resolve omitted lengths before calling mlx-c, whose C entry requires explicit lengths.
  `mlxf_weak_scalar` accepts real64; real32 public operands widen into it without losing their original rounding.
- A new class (an axis argument, an output vector, ...) is a line of `scripts/mlxc_signatures.txt` (its name and
  one mlx-c function with the signature); its abstract interface is generated into `mlxf_c_signatures`, so it is
  `bind(c)` with the generated intents by construction. It gets **one** new helper, in the family module that calls
  it, or in `mlxf_calls` when two families do, taking the generated procedure as a procedure argument; every wrapper of that class uses it, and it is added to
  `ENTRY_HELPERS` of `check_rules.py`. The helpers enter, validate the operands (`mlxf_handle`: empty or stale arrays stop), check that a device can allocate, take the default
  stream, check the status and register the result (`mlxf_adopt`).
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
- Scalars are weak: build the 0-d operand with the array's kind (`mlxf_weak_scalar`), so a real literal never
  changes the result's kind.

## 5. Errors

An error MLX reports while building a graph stops (`mlxf_check(ierr, proc)` without `status`): it is a
program error. Only evaluation and data movement are checked procedures with an optional `status`. A
procedure C++ calls never stops.

## 6. Publish it

Add the name to the module's `public ::` block, then to `src/core/mlxf.f90`'s `use` and `public` lists
(never an `mlxc_` or `mlxf_` helper). Document it in the binding policy when it adds a convention.

## 7. Test it on both devices

In the area's tester (`mlxf_<module>_tester.f90`, a `run_suite` row of `src/test/framework/mlxf_test_registry.f90`):
for each device of `test_devices(devs)` (`mlx_set_default_device`), against a plain Fortran evaluation in
double precision with the tolerance of the plan's section 6, asserting the convention it translates
(dimension numbering, index base, sign, normalisation). float64 on the CPU device only. Never a function
reference or operator result inside an array constructor of handles (rules `ctorcall`, `ctorexpr`): build
the elements into variables.
A stop that is the contract is a member of a guard group, not an in-process test.

## 8. Before handover

Follow [the modern Fortran layout and formatting steps](../mlxf-modern-fortran/SKILL.md#layout-checked-not-argued)
after the last edit. Include the parent interfaces, signature helper, wrapper and tester, including
new/untracked files; a wrapper-only formatting pass is incomplete. `scripts/check_tree.sh` checks both
formatters tree-wide. Debug and Release build with zero warnings and pass the fast gate.


## Closure callbacks

`mlx_function` takes a checked subroutine `(inputs, outputs, status)`, with an allocatable output array.
Never return an allocatable array of finalizable handles from the callback: GNU Fortran 16.2 frees that
function result before finalization (reproducer: `doc/compiler_issues/gfortran_finalize_allocatable_array_result.f90`).
The C trampoline imports and exports vectors through `mlxf_array_closure`, checks every status and returns
it to C; callbacks validate their arguments and return failures, never stop. A new `mlxc_array_new()`
output handle may have a null context until an mlx-c getter fills it; check the getter status before adoption.
