---
name: mlxf-modern-fortran
description: Use when editing mlx-fortran's Fortran code (src/, test/): the house layout and visibility rules (taken from SIMPLE and XEMA), use-block form, naming, lifecycle, finalizers and the handle-copy restriction, C interoperability with mlx-c (bind(c) interfaces, handles by value, pointer views, callbacks that never stop), errors and the hard-error status, real comparisons, the traps that have bitten, compile-time rules, comments, threading, warnings, and the scripts that check all of it before handover.
---

# Modern Fortran in mlx-fortran

The working summary of the house rules. Where each rule came from (SIMPLE, XEMA, or new here) and why it
holds is `doc/architecture_principles.md`; `scripts/check_tree.sh` checks what reading can check.

## Layout (checked, not argued)

- `use`, `implicit none`, the `public ::` block, `private` and module-level declarations sit flush left;
  only bodies under `contains` are indented, by four; inside a derived type `contains` is indented by two.
- `if( cond )then` / `endif`, `end do`; `select` arms (`case`, `type is`, `class is`, `class default`) sit
  four columns inside the `select`, their bodies four more; `end type`, `end subroutine`, `end function`
  carry their names.
- Aligned columns: type, `optional`, `intent`, `::`; all dummies of a procedure align together (`value` and
  dummy procedures included), locals apart. Dense code, no gratuitous continuations or blank-line padding.
- No `block`, no `goto`, no numbered labels, no `interface operator`/`interface assignment` blocks: operators
  are type-bound generics (`pass(rhs)` for a scalar on the left). Intrinsic-name generics (`exp`, `sum`) are
  ordinary generic interfaces.
- Comments use `!`, never `!>`.
- Before handover, on every file you touched (never tree-wide):
  `python3 scripts/restyle_fortran.py FILE...` (token-proof; `--check`, `--case-indent`, `--ends-only`) and
  `python3 scripts/format_use_blocks.py FILE...` (`--check`). Then `scripts/check_tree.sh`.

## Modules and visibility

- Module name equals file name, `mlxf_` prefix, one module or submodule per file, first line
  `!@descr: <one line>`; every directory holding Fortran has a one-line `<dir>.inf`.
- `use ..., only:` always (test programs too); `implicit none` always.
- **Every library module (src/core) restricts:** one `public ::` block at the top followed by bare
  `private`; never a `public` attribute on a declaration. Installed `.mod` files make every public name API.
  (XEMA's visibility by majority is not used here; test code may use either form.)
- `use` blocks have one form: `only:` in one column, continuation under the first name, one statement per
  module per run, module-scope runs ordered by layer: intrinsic, the generated `mlxf_c_*`, `src/core`,
  `src/test`.
- `mlxf` is the one re-export module; no library module imports it; test code (kernels, benchmarks,
  testers of the public surface) imports it as a user would.
- A module contains no entity of its own name, and no entity that differs from an imported name only in
  case (Fortran is case-insensitive: `MLXF_VERSION_STRING` against `mlxf_version_string` broke the first
  build). Rename on import where a dummy would shadow a constant.
- No module-level mutable state beyond the register's list (the handle registry, the last error, the
  initialisation flag; the test library's totals): `check_rules.py`, rule `state`, with its ledger.
- Before writing a small helper, look for its owner: a second copy of a routine is a defect.

## Naming

- `parameter` constants in CAPITALS; everything else lower case.
- Public MLX types and procedures `mlx_<x>`; generics that extend an intrinsic keep its name and semantics;
  the generated layer's entities `mlxc_<x>` bound to `mlx_<x>`.
- An enum-like family of more than two codes is one derived-type named constant, plural, with a component
  per code (`MLX_DEVICES%gpu`), so that a variable holding one code never shadows it.
- A type owns state or is a point of polymorphism; otherwise write module procedures named for what they
  act on.

## Lifecycle and handles

- Stateful types: `new`/`kill` with an idempotent `kill` (an `exists` guard); value objects carry none.
- A type owning what Fortran does not manage (every MLX handle) declares `final` delegating to `kill`
  (final dummies are `type`, not `class`); allocatable-only types get no finalizer.
- A handle type's copy is its type-bound defined assignment (`impure elemental`, left side
  `intent(inout)`), which adds a Fortran-side reference in the registry.
- **gfortran (16.2 and earlier) skips that assignment for allocatable components** when it copies an
  enclosing derived type, and `allocate(source=)` never calls it. A derived type with an allocatable handle
  component (scalar or array) defines its own assignment that assigns those components element by element,
  or is never copied by intrinsic assignment. No `allocate(source=)` or `mold=` on handle types; no array
  intrinsics (`pack`, `unpack`, `reshape`, `spread`, `transpose`, `merge`, `cshift`, `eoshift`) on arrays of
  handles. Reproducer: `doc/compiler_issues/gfortran_alloc_component_defined_assignment.f90`.
- An `optional` dummy is present at some calls and absent at others; read `present()` once before a loop.
  Optionals are passed by keyword at call sites.

## C interoperability

- `bind(c)` interfaces to mlx-c live only in the generated layer (`build/gen/mlxf_c_*.f90`); libc entry
  points (`strlen`, `memcpy`, `posix_memalign`, `free`) only in `mlxf_libc` (rules `cbind`, `libc`; the
  scaffold's probe in `mlxf_version` is the one ledger entry until the generated layer exists).
- An mlx-c handle is a `bind(c)` type holding one `type(c_ptr) :: ctx`, passed with `value` where C takes
  it by value. `bool*` is `logical(c_bool)`; strings to C are `trim(s)//c_null_char`; strings from C are
  copied at once and the C object freed.
- A raw `type(c_ptr)` never leaves the module that obtained it. A Fortran pointer view of an MLX buffer is
  taken only after evaluation, of a row-contiguous array, and is valid until the next statement that
  assigns to, kills or ends the scope of its handle variable; it is never written through.
- Every mlx-c status is checked. **A procedure C++ calls (error handler, deleter, closure trampoline) never
  stops**: no `stop`, `error stop` or error macro inside a `bind(c)` procedure body (rule `cbstop`); it
  records and returns a status.
- Callbacks given to C are `bind(c)` module procedures (`c_funloc`) with their state in a payload.

## Errors and numbers

- One error module; every stop the library makes uses `MLXF_HARD_ERROR_STATUS`, so a test can tell the
  library's stop from a runtime failure. A macro call stays on one physical line; a long message goes
  through a named variable.
- Operators and functions stop on errors MLX reports while building a graph (program errors); evaluation
  and data movement are checked procedures with an optional `status`.
- Never `==`/`/=` on reals: tests use `bits_equal` (transfer-based) for storage identity and a tolerance for
  mathematics. Parenthesize `.eqv.`/`.neqv.` combined with `.and.`/`.or.`.
- Fortran does not short-circuit: never a guard and the access it protects in one expression; nest the `if`s.

## Traps that have bitten (all legal Fortran)

- Case-insensitive names: a module cannot contain an entity of its own name; a constant and a procedure
  that differ only in case clash; a dummy shadows an imported constant of the same spelling.
- A deferred-length character is sized by assignment (`s = repeat(' ', n)`), never by `allocate` after a
  prior assignment ("already allocated" at run time; the scaffold's second bug).
- Declaration initialisation implies `SAVE`: never initialise a local at declaration that must be fresh.
- `-128_int8` is a range error; write `int(-128, int8)`.
- No `associate` over a derived-type parameter-array element under a runtime index.
- A component section of a record array passed to an array dummy is a hidden copy-in/copy-out temporary.
- Never pass the pointer result of a polymorphic type-bound function straight on as an actual argument.
- A submodule never calls a private plain procedure of its module (gfortran before 16 does not link it;
  `scripts/check_submodule_linkage.py`).
- Keep function-like preprocessor macro invocations on one physical line.
- gfortran warns about no unused imported name: delete an import with the code that used it.

## Compile time

The rule set is `doc/policies/compile_time_policy.md`: one library target; no per-file compile options;
flags only on `mlxf_build_flags`; module-level `use` lines only for what the module itself needs; a large
derived type held inside another is an `allocatable` component.

## Comments

- File header: one `!@descr:` line, then at most 5 lines. Procedure header: at most 3 lines. In-body: 1-2
  lines saying why or stating a non-obvious invariant. If a comment is harder to read than the code, delete
  it.
- Self-contained: never cite a plan, a section number or a date in code; state the reason itself. No names,
  commit hashes, measurements, narration or rejected alternatives in code (those go to `doc/history/`).

## Threading

- MLX graphs are built and evaluated from one thread; public procedures refuse to run inside an OpenMP
  parallel region.
- Test code with OpenMP regions (a CPU consumer in a benchmark): no allocation, I/O, string building,
  object construction or `class` dispatch inside a region; per-thread buffers sized by the team in use and
  allocated before it; `default(shared)` with explicit `private`, explicit `schedule`, `proc_bind(close)`.

## Warnings

The tree builds with zero warnings in Debug and Release; fix the code, never silence the diagnostic.
`-DMLXF_WERROR=ON` turns warnings into errors (CI). For the mechanical classes:
`./compile_clean.sh 2>&1 | tee build.log`, then `python3 scripts/fix_warnings.py build.log` (dry run) or
`--apply`. Release (`-O3`) reports more than Debug, so both are part of warning hygiene.

## Testers

- Writing or editing a test: [references/testing.md](references/testing.md).
- A tester is `mlxf_<thing>_tester.f90` beside the module it tests, exporting only `run_all_<thing>_tests`,
  run from a row of `src/test/mlxf_test_registry.f90`; `scripts/check_test_registry.py` holds rows, testers
  and CTest areas to each other.

## Building

`./compile_debug.sh` (bounds checks; `--traps` for floating-point traps) and `./compile_clean.sh` (Release)
build from scratch and run the fast gate (the static gate, then the tests); `./recompile.sh` rebuilds
incrementally. `build/bin/mlxf_test_exec test=list` lists the tests.
