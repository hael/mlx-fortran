---
name: mlxf-modern-fortran
description: "Use when editing mlx-fortran's Fortran code (src/, test/): the house layout and visibility rules (taken from SIMPLE and XEMA), use-block form, naming, lifecycle, finalizers and the handle-copy restriction, C interoperability with mlx-c (bind(c) interfaces, handles by value, pointer views, callbacks that never stop), errors and the hard-error status, real comparisons, the traps that have bitten, compile-time rules, comments, threading, warnings, and the scripts that check all of it before handover."
---

# Modern Fortran in mlx-fortran

The working summary of the house rules. Where each rule came from (SIMPLE, XEMA, or new here) and why it
holds is `doc/architecture_principles.md`; `scripts/check_tree.sh` checks what reading can check.

## Layout (checked, not argued)

- `use`, `implicit none`, the `public ::` block, `private` and module-level declarations sit flush left;
  only bodies under `contains` are indented, by four; inside a derived type `contains` is indented by two.
- Separate implementation procedures under `contains` with one blank line; put one on each side of a
  module-level `contains` and after a module-level type or interface block. Keep a type's following
  constant declaration together with that type. Separate the bodies of an interface block with one blank line (the formatter adds it).
- Pad the dummy list in **subroutine/function declarations**, including interface bodies:
  `subroutine apply( self, inputs, outputs, status )` and `function make( x ) result(r)`.
  Calls keep their own form: `call apply(self, inputs, outputs, status=st)`; empty lists stay `()`.
- Write `.not. x` and put a space after commas, including before a quoted argument:
  `call mlxf_fail(proc, 'message')`. Preserve the tight I/O unit/format separator `write(u,'(A)')`
  and assumed-shape declaration `(:,:)`. Blank lines contain no whitespace.
- The full `restyle_fortran.py` pass handles these forms. The static gate checks the layout of all
  Fortran files under `src/` and `test/` with `--check --tree`.
- `if( cond )then` / `endif`, `end do`; `select` arms (`case`, `type is`, `class is`, `class default`) sit
  four columns inside the `select`, their bodies four more; `end type`, `end subroutine`, `end function`
  carry their names.
- Aligned columns: type, `optional`, `intent`, `::`; all dummies of a procedure align together (`value` and
  dummy procedures included), locals apart. Dense code, no gratuitous continuations or blank-line padding.
- No `block`, no `goto`, no numbered labels, no `interface operator`/`interface assignment` blocks: operators
  are type-bound generics (`pass(rhs)` for a scalar on the left). Intrinsic-name generics (`exp`, `sum`) are
  ordinary generic interfaces.
- Comments use `!`, never `!>`.
- **At most five dummy arguments** per procedure, in `src/` and `test/` (rule `arity`): one that needs more
  takes a spec type, a derived type holding the inputs, constructed and validated once and passed whole
  (SIMPLE's `opt_spec`). Exempt: the generated interfaces and `bind(c)` procedures whose signature C fixes.
- **List arguments are arrays of handles** (`type(mlx_array), intent(in) :: arrays(:)`), never lists of
  optional arguments.
- After the last Fortran edit, run `python3 scripts/restyle_fortran.py FILE...` and
  `python3 scripts/format_use_blocks.py FILE...` on every touched file, including new/untracked files,
  parent interfaces, submodules and testers. Use the full restyle pass: `--ends-only` and `--case-indent`
  are limited repairs, not substitutes. Then run `scripts/check_tree.sh`, which checks both formatters
  tree-wide without rewriting. Review the resulting diff against these conventions; a formatter pass
  does not replace that review. Recheck after any later edit. Rewrite only touched files, never the
  whole tree to clear an unrelated formatting finding.

## Modules and visibility

- Module name equals file name, `mlxf_` prefix, one module or submodule per file, first line
  `!@descr: <one line>`; every directory holding Fortran has a one-line `<dir>.inf`.
- **Capability folders, one library target.** `src/core/<capability>/` (`runtime/`, `array/`, later the
  operations, FFTs, ...) holds a capability's modules and their testers; a new folder gets an `.inf`, never
  a CMake target. A type with a large implementation is one parent module (the type, its generics, the
  interface of every procedure) and implementation submodules `<module>_<part>` by concern (XEMA's search
  engine; `mlxf_array`: lifetime, evaluation, elementwise, closure; `mlxf_transfer`: copy, borrow). A helper one submodule needs
  is a plain procedure local to it; one two submodules need is a separate module procedure with its
  interface in the parent.
- `use ..., only:` always (test programs too); `implicit none` always.
- **Every library module (src/core) restricts:** one `public ::` block at the top followed by bare
  `private`; never a `public` attribute on a declaration. Only `mlxf.mod` is installed; the restriction keeps the internal surface explicit.
  (XEMA's visibility by majority is not used here; test code may use either form.)
- `use` blocks have one form: `only:` in one column (intrinsic statements whose heads reach past it share a
  column of their own), continuation under the first name, one statement per module per run, module-scope
  runs ordered by layer: intrinsic, the generated `mlxf_c_*`, `src/defs`, `src/core`, `src/test`.
  `scripts/format_use_blocks.py` writes the form and checks it in the static gate.
- **Exported = defs, local = stay** (SIMPLE's and XEMA's rule): a named constant, a vocabulary or a
  behaviourless record that another module imports is declared in `src/defs/mlxf_defs.f90`; one used only in
  its module stays there. Move it when the second module needs it, not before. The defs module is public by
  default, lists every name it imports in a `private ::` statement, holds no procedures and imports only the
  generated layer. Import a constant from `mlxf_defs`, never through a module that re-exports it (test code
  imports it through `mlxf`, as users do). A test constant or record shared by test modules goes to
  `src/test/framework/mlxf_test_defs.f90`. `check_rules.py`, rule `defs` (constants and behaviourless types).
- **Where a type or constant lives**, in short (the register, section 2, has the reasons):
  - a class, with type-bound procedures or private components, stays in the module that implements it;
  - a behaviourless record that another module builds or reads goes to defs;
  - a constant another module needs, or that two modules declare alike, goes to defs;
  - a tunable goes to defs even when one module reads it: a tolerance, a calibration constant, a seed, a
    budget, a sweep grid, a tile plan, a constant mirrored from SIMPLE;
  - a logic table stays: fixture shapes, poses, candidate lists, stage orders, capacities, formats;
  - a name no other module imports is private, also in a parent whose submodules use it.
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
- An enum-like family is one derived-type named constant, plural, with a component per code
  (`MLX_DEVICES%gpu`, `MLX_DTYPES%float32`), declared in `mlxf_defs`, so that a variable holding one code
  (`device`, `dtype`) never shadows it.
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
  component (scalar or array) defines its own assignment that assigns those components element by element
  (the pattern is in `doc/policies/binding_contract_policy.md`), or is never copied by intrinsic assignment.
  No `allocate(source=)` or `mold=` on handle types; no array intrinsics (`pack`, `unpack`, `reshape`,
  `spread`, `transpose`, `merge`, `cshift`, `eoshift`) on arrays of handles.
- **gfortran mis-finalizes three more forms** (also 13.4): never a function reference inside an array
  constructor of handles (`[mlx_from(x), exp(a)]` leaks: rules `ctorcall` and `ctorexpr` check the repository's code; build
  the elements into variables, `call f([a, b])` is fine); never a whole-array assignment of a function result
  to an array of handles (`v = exp(a)` leaks; assign a variable, or element by element); never a
  self-assignment of a derived type holding handles (`w = w` releases its components first). Reproducers:
  `doc/compiler_issues/`. A defined-operator result inside a constructor (`[a*2.0, b]`) leaks the same way
  (rule `ctorexpr`: an element that refers to a handle is a bare designator); an overlapping section assignment of handles (`v(2:3) = v(1:2)`) stops as stale.
- An `optional` dummy is present at some calls and absent at others; read `present()` once before a loop.
  Optionals are passed by keyword at call sites.

## C interoperability

- `bind(c)` interfaces to mlx-c live only in the generated layer (`build/gen/mlxf_c_*.f90`, written by
  `scripts/gen_mlxc_bindings.py`); libc entry points (`strlen`, `memcpy`, `posix_memalign`, `free`) only in
  `mlxf_libc` (rules `cbind`, `libc`). Adding a wrapper: the skill `mlxf-binding`.
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
- A submodule never calls a private procedure whose body is in its module, plain or separate (gfortran before 16
  does not link a plain one, gfortran 15 on Linux not a separate one either); a separate module procedure a module
  and its submodule share has its body in the submodule (`scripts/check_submodule_linkage.py`).
- Keep function-like preprocessor macro invocations on one physical line.
- gfortran warns about no unused imported name: delete an import with the code that used it.
- `-Wfunction-elimination` (Release): an impure function as a later operand of `.and.` or `.or.` may be skipped,
  which with warnings as errors fails the build; make the function `pure` or call it in its own statement.
- In an OpenMP build every local is recursive: an intrinsic such as `reshape` with a constant target shape of
  tens of MB puts a temporary of that size on the stack and crashes; give the shape at run time.
- Rule `ctorexpr` reads names file-wide: a real array that shares a name with a handle elsewhere in the file is
  flagged; rename one of them.

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
- A comment belongs to the procedure under it: a new procedure inserted before another goes above that
  procedure's header comment, never between the comment and its procedure.

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
- A tester is `mlxf_<thing>_tester.f90` beside the module it tests, exporting only `run_all_<thing>_tests`
  (and the entry of a named-only sub-suite it owns, `NAMED_ONLY` in the registry), run from a row of
  `src/test/framework/mlxf_test_registry.f90`; `scripts/check_test_registry.py` holds rows, testers
  and CTest areas to each other.

## Building

`./compile_debug.sh` (bounds checks; `--traps` for floating-point traps) and `./compile_clean.sh` (Release)
build from scratch and run the fast gate (the static gate, then the tests); `./recompile.sh` rebuilds
incrementally. `build/bin/mlxf_test_exec test=list` lists the tests.
