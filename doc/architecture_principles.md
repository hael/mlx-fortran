# Architecture principles: what mlx-fortran takes from SIMPLE and XEMA

The register of the house rules mlx-fortran inherits. SIMPLE (`~/src/SIMPLE`, at `5709265cb`) is the origin;
XEMA (`~/src/X`, at `7bd4ac73`) adopted SIMPLE's architecture item by item, added rules where SIMPLE had
learned the hard way, and checks most of them with scripts. Each item below is **adopt** (as is), **adapt**
(changed deliberately, with the reason) or **reject** (with the reason). Where SIMPLE and XEMA differ, XEMA's
later rule is the default unless a library's needs argue otherwise. The binding text is in `CLAUDE.md`, the
skills and the policies; this register says where each rule came from and why it holds here. When this file
and a skill disagree, the disagreement is a defect fixed first. Written 2026-11-20 on the owner's condition
for the first unattended run ("the necessary architectural guidelines imported from SIMPLE and XEMA").

## 1. What kind of code this is

mlx-fortran is a small public library, not an application: one library target, one test executable, no
command line, no project files, no domain layers. Rules about commanders, typed requests, `parameters`,
project ownership, streaming, consoles and campaigns (SIMPLE's `ui -> exec -> commander -> strategy` flow,
XEMA's `argv -> spec -> commander -> request -> service` flow) have no object here and are not imported. What
is imported is how Fortran is written, built, tested, checked, documented and handed over.

## 2. Modules, types and lifecycle

- **Adopt (both): naming and files.** Modules `mlxf_<x>`, file name equals module name, one module or
  submodule per file, first line `!@descr: <one line>` (`scripts/check_descr.py`). Every directory holding
  Fortran carries a one-line `<dir>.inf` (`scripts/check_rules.py`, rule `inf`).
- **Adopt (XEMA): a module contains no entity of its own name.** Identifiers are case-insensitive; the
  scaffold's first build failed on `MLXF_VERSION_STRING` against `mlxf_version_string` (2026-11-20). Likewise a
  dummy that differs from an imported constant only in case shadows it: rename on import.
- **Adapt (XEMA's visibility by majority): every library module restricts.** XEMA writes no visibility
  statements in a module that exports most of what it holds, relying on every consumer's `use, only:`. A public
  library that installed its `.mod` files would make any public name of any module API; this one installs
  only `mlxf.mod`, and the restriction keeps the internal surface explicit all the same. Every module under
  `src/core/` declares one `public ::` block at the top followed by bare
  `private`, and never scatters `public` attributes (XEMA's form rule, kept). The generated layer and test code
  are not installed as API and may use the default. Users import `mlxf`.
- **Adopt (XEMA): one re-export module per layer, explicit `only:` lists.** `mlxf` is the one aggregator; no
  library module imports it; test code imports it as a user would. Only `mlxf.mod` is installed (owner's
  review of Phase 1, decision 41): no other module file reaches a consumer.
- **Adopt (XEMA, owner's review of Phase 1, decision 41): implementation submodules and capability
  folders.** A type with a large implementation is one parent module (the type, its generics, every
  procedure's interface) and submodules by concern, as XEMA's search engine; `mlxf_array` has five
  (lifetime, transfer, borrow, evaluation, elementwise), one type and one ownership implementation with
  private access inside the family. `src/core/` holds capability folders (`runtime/`, `array/`) of the one
  library target. Domain-driven design in proportion: stateless operations stay module procedures, codes
  stay constant vocabularies (decision 40), no object without state to own.
- **Adopt (both): lifecycle.** Stateful types have `new`/`kill` symmetry with an idempotent `kill` (XEMA's
  `exists` guard); value objects carry none. **Adopt (XEMA): finalizers on resource-owning types.** A type
  owning what Fortran does not manage (here: every MLX handle) declares `final` delegating to `kill`;
  allocatable-only types get none. Viable because the floor (GFortran 14) postdates GCC 13's finalization
  rewrite.
- **Adapt: handle copies.** XEMA's `copy` is a type-bound procedure; an MLX handle's copy is its defined
  assignment, which adds a Fortran-side reference (design plan, decision 8). gfortran skips that assignment for
  allocatable components of an enclosing type (`doc/compiler_issues/`), so such types assign their handle
  components explicitly; the handle registry turns a missed case into a diagnosed stop. **Widened (owner,
  2026-11-21, design plan decision 39)** after Phase 1's probes found three more gfortran finalization
  defects (also in 13.4): no function reference inside an array constructor of handles, no whole-array
  assignment of a function result to an array of handles, no self-assignment of a derived type holding
  handles. The first two leak where the registry cannot see it; `check_rules.py` checks the repository's own
  constructors (rule `ctorcall` for library functions by name, rule `ctorexpr`, 2026-11-22, for any element
  that refers to a handle and is not a bare designator: operator and generic results), and `mlx_live_count()`
  lets users assert a loop leaks nothing.
- **Adopt (XEMA): a type owns state or is a point of polymorphism**; otherwise procedures are module
  procedures named for what they act on.
- **Adopt (both): optionals.** A dummy is `optional` only if some callers omit it; `present()` is read once
  before a loop. **Adopt (XEMA):** optionals are passed by keyword at call sites.
- **Adopt (XEMA): constants in CAPITALS**, everything else lower case. **Adopt (XEMA): an enum-like family is
  one derived-type named constant, plural, with a component per code** (`MLX_DEVICES%gpu`,
  `MLX_DTYPES%float32`), whatever the number of codes, so that every family follows one pattern;
  mlx-c's enumerators in the generated layer stay as generated.
- **Adapt (XEMA's "no module-level mutable state, ever").** MLX itself is process-global (default device,
  allocator, compile cache) and the library's operators cannot take a context argument. The library's own
  process-global state is limited to the handle registry, the last error and the initialisation flag, each
  private to one module, single-threaded by the one-thread rule, and listed in `check_rules.py`'s `state`
  ledger; nothing else may be added without an owner decision. Test code's counters (the assertion totals)
  are the other ledger entry, as in XEMA.
- **Adopt (both): exported = defs, local = stay** (owner, 2026-11-21, reversing this register's first
  rejection). A named constant, a vocabulary or a behaviourless record that another module imports lives in
  `src/defs/`; one used only inside its module stays there, and a move happens on export, never in
  anticipation. One defs module, `mlxf_defs`, while the library is one bounded context; a test constant that
  several test modules share goes to `src/test/mlxf_test_defs.f90` when the first one appears. **Adopt
  (XEMA): defs modules are public by default** (no visibility statement), **adapted** for an installed
  library: every name a defs module imports (the `MLXC_*` codes its vocabularies are built from) is listed in
  a `private ::` statement, so that its `.mod` re-exports nothing. Defs modules hold no procedures and import
  only the generated layer. **Adopt (XEMA): import a name from its declaring module** (`mlxf` re-exports the
  vocabularies from `mlxf_defs`). Checked: `check_rules.py`, rule `defs`, for constants and, since the review
  of run `mlxf_m1` (owner, 2026-11-22), for types, with an exceptions table for a name argued to stay with its
  owner (empty).
- **Where a type or a constant lives** (owner's review of run `mlxf_m1`, 2026-11-22, from XEMA's AGENTS.md
  "Refactoring and module housekeeping" and SIMPLE's `simple-modern-fortran` skill):
  - *A class stays with its behaviour* (both): a type with type-bound procedures or private components is
    declared in the module that implements it, named after it where the module is its own (SIMPLE), and so
    is a type shaped like a module's private state (XEMA). Never turn a class into a public record passed to
    free procedures (SIMPLE).
  - *A behaviourless record that crosses a module boundary goes to defs* (XEMA): inputs, results and specs
    that a class takes or returns, when another module builds or reads them. Checked.
  - *A constant another module needs goes to defs* (both), and so does one that two modules declare alike:
    a duplicate is an export written twice. Checked for imports; duplicates are a review item.
  - *Tunables go to defs even when one module reads them* (SIMPLE, `simple_defs_<domain>`): a number a
    maintainer is expected to tune or a plan freezes (a tolerance, a calibration constant, a seed, a memory
    budget, a sweep grid, a tile plan, a constant mirrored from SIMPLE's production code). XEMA's "local =
    stay" governs everything else: a module keeps its logic tables (fixture shapes, poses and candidate lists
    of a test fixture, stage orders, capacities, formats) and procedure-local values. A review item.
  - *Two exceptions stay with their owner* (XEMA's (a) and (b)): constants of the module's own type, and a
    module's closed identity vocabulary or algorithm constants.
  - *Public only when imported*: a name no other module uses is private, also in a parent module whose
    submodules use it (host association reaches private names).

## 3. Writing Fortran

- **Adopt (XEMA over SIMPLE): comments use `!`, never `!>`.** One or two lines of the non-obvious (ownership,
  units, an invariant, a why). **Adopt (both):** comments are self-contained; no dates, names, measurements,
  narration, review history or citations of plans and sections in code (the owner's rule in SIMPLE). Bare
  paths are allowed only to files in this repository that a reader needs (`doc/compiler_issues/...`).
- **Adopt (XEMA): layout is checked, not argued.** `scripts/restyle_fortran.py` (aligned attribute and `::`
  columns, named ends, spacing; token-proof, per file) and `scripts/format_use_blocks.py` (`only:` in one
  column, one statement per module per run, module-scope runs ordered by layer: intrinsic, the generated
  `mlxf_c_*`, `src/core`, `src/test`) run on every touched file before handover; the static gate runs the
  use-block check tree-wide.
- **Adopt (both):** `use ..., only:` always, also in test programs; `implicit none` always; `if( cond )then`
  and `endif`; `select` arms four columns inside the `select`.
- **Adopt (XEMA): no `block`, no `goto`, no numbered labels, no `interface operator`/`interface assignment`
  blocks** (operators are type-bound generics, with `pass(rhs)` for a scalar on the left). Checked
  (`check_rules.py`, rule `layout`).
- **Adopt (both): error macros on one physical line**; a long message goes through a named variable. Checked.
- **Adopt (XEMA): never `==`/`/=` on reals.** Tests compare storage identity with a transfer-based
  `bits_equal` and mathematics with a tolerance. `-Wextra` brings `-Wcompare-reals`.
- **Adopt (XEMA): parenthesize `.eqv.`/`.neqv.` combined with `.and.`/`.or.`; Fortran does not short-circuit**
  (both): never a guard and the access it protects in one expression.
- **Adopt (XEMA): the traps that have bitten**, in the skill: `int(-128, int8)`; no `associate` over a
  parameter-array element under a runtime index; a deferred-length character is sized by assignment, never by
  `allocate` after an assignment (the scaffold's second bug, 2026-11-20); declaration initialisation implies
  `SAVE`; a component section of a record array passed to an array dummy is a hidden copy; gfortran never warns
  about an unused imported name.
- **Adopt (owner's house rule, 2026-11-21, decision 39; SIMPLE's `opt_spec` the precedent): no procedure
  has more than five dummy arguments.** One that needs more takes a spec type, constructed and validated
  once and passed whole; exempt are the generated interfaces and `bind(c)` procedures whose signature C fixes.
  Checked (`check_rules.py`, rule `arity`), in `src/` and `test/`.
- **Adopt (SIMPLE): no pointer result of a polymorphic type-bound function passed straight as an actual;
  a submodule never calls a private plain procedure of its module** (gfortran before 16 does not link it;
  `scripts/check_submodule_linkage.py`).

## 4. C interoperability (new here)

Neither house binds a C++ library through a C API on this scale; these rules are mlx-fortran's own, written in
the style of the others and checked where reading can check them.

- `bind(c)` interfaces to mlx-c exist only in the generated layer; libc entry points only in `mlxf_libc`
  (`check_rules.py`, rules `cbind` and `libc`; the scaffold's probe module is the one ledger entry until the
  generated layer replaces it).
- A Fortran procedure that C++ calls (error handler, deleter, closure trampoline) never stops: no `stop`,
  `error stop` or error macro inside a `bind(c)` procedure body (rule `cbstop`).
- Every mlx-c status is checked; MLX's errors never exit the process from inside C++.
- A raw `type(c_ptr)` never leaves the module that obtained it.
- **New here (owner, decision 39): list arguments are arrays of handles** (`type(mlx_array), intent(in) ::
  arrays(:)`), never lists of optional arguments; a caller fills them element by element or writes a
  constructor of variables.
- **New here: the generated layer's types are one module** (`mlxf_c_types`) and its interfaces one module
  per header, because mlx-c's headers refer to each other's types in a cycle; a C type the generator's one
  mapping table does not map stops the build, and so does a difference from the independent prototype list.

## 5. Errors

- **Adopt (both): the mechanism.** One small error module, a dedicated hard-error status
  (`MLXF_HARD_ERROR_STATUS`, XEMA's 86) for every stop the library makes, so a test can tell the library's
  stop from a runtime failure.
- **Adapt (XEMA's abort-only-for-programming-faults):** operators and functions stop on errors MLX reports
  while building a graph (program errors); evaluation and data movement are checked procedures that return a
  status the caller can act on (reduce a batch). XEMA's "scientific policy responses are recorded outcomes" is
  the same distinction.

## 6. Building

- **Adopt (both): GNU Fortran only, version floor 14, fail loudly; toolchain autodetect before `project()`**
  (SIMPLE's `AutoDetectGCC.cmake`, with each candidate actually searched).
- **Adopt (both): a missing dependency fails loudly too.** No `find_package(... REQUIRED)`: each miss (mlx-c,
  OpenMP, Python) is tested by its `_FOUND` variable and stops with what was searched and how to install it,
  never with CMake's list of config file names. `check_rules.py` (`findpkg`) checks it.
- **Adopt (XEMA over SIMPLE): flags on an interface target, never forced into the cache**
  (`mlxf_build_flags`), so a consumer that embeds the project keeps its own flags. **Adopt (XEMA):
  per-library module directories** (`mlxf_add_library`): the library's modules and the test executable's
  modules live apart, so installing the library never installs a test module.
- **Adopt (XEMA): zero warnings in Debug and Release**, fixed in code; `-Wall -Wextra -Wimplicit-interface`;
  class suppressions only with a reason beside the flag (`-Wno-unused-dummy-argument`, `-Wno-intrinsic-shadow`,
  `-Wno-maybe-uninitialized` as in SIMPLE); `MLXF_WERROR` for CI; `scripts/fix_warnings.py` for the mechanical
  classes.
- **Adapt (XEMA's "no `-std=`"):** `-std=f2018` stays. XEMA rejects it because it disables GNU intrinsics XEMA
  uses; a public library uses none and should stay standard Fortran for its users and for flang later.
- **Adapt (XEMA's always-on FP traps in Debug):** traps stay opt-in (`MLXF_DEBUG_TRAPS`, SIMPLE's `--traps`).
  The floating-point environment the Fortran main program sets applies to MLX's C++ CPU kernels in the same
  process, which may legitimately produce infinities.
- **Adopt (SIMPLE): on macOS, Debug checks are `bounds,do,mem`**: GFortran 16's debug runtime has crashed under
  pointer checks on C-interoperable pointers.
- **Adopt (both): sources globbed with `CONFIGURE_DEPENDS`; thin compile scripts; the configuration summary;
  Python for the build and the gate is the standard library, 3.7 or newer.**
- **Reject (XEMA): `-funroll-loops`.** SIMPLE measured no gain; the Fortran side is glue.
- **Adopt (XEMA): an installable CMake package** (`mlxf::mlxf`, a config file): Phase 5 of the design plan.

## 7. Tests

- **Adopt (both): one test executable**, area suites as CTest entries, assertions whose failure reaches the
  exit status, expected values from outside the code under test, fixed seeds, tests leave nothing behind.
- **Adopt (XEMA): checks are free, processes are budgeted.** `MLXF_CTEST_BUDGET` in `test/CMakeLists.txt` must
  equal the registered count or configuration fails; it changes only with an owner decision or a plan that
  names the new entry.
- **Adopt (XEMA): failure paths as guard groups.** Where dying is the contract (a stale handle used, an
  operation on an empty array, a call from inside an OpenMP region), the test is a member of a guard group that
  `mlxf_test_exec expect_aborts <group>` runs in child processes, accepting only `MLXF_HARD_ERROR_STATUS`;
  never raw `WILL_FAIL`. The intended stop is the last statement the child can reach.
- **Adopt (XEMA): a new check is shown to fail on the previous tree** when it comes with a fix.
- **Adopt (XEMA): hermetic; both build types; an entry above 0.5 s in Release says why.** The fast label stays
  under SIMPLE's 60 s budget.
- **Adopt (SIMPLE): `scripts/check_test_registry.py`** holds the suite registry, the testers and the CTest
  areas to each other.
- **New here: devices.** Every operation test runs on every device present; GPU results are compared with
  tolerances; `MLXF_REQUIRE_GPU` (a compile definition of the test executable, not an environment variable)
  makes a missing GPU a failure.

## 8. The static gate

- **Adopt (XEMA): `scripts/check_tree.sh`**, every check that needs no compiler, in seconds, run first by
  `scripts/run_fast_gate.sh`: `check_descr.py`, `check_rules.py` (with ledgers that may only shrink),
  `check_test_registry.py`, `check_guide_imports.py`, `check_submodule_linkage.py`, `format_use_blocks.py
  --check`; untracked sources are a warning.
- **Adopt (XEMA): every new rule a reading can check gets its check, with a planted violation shown to fail**
  (SIMPLE's plan standard says the same). Phase 1 added `arity`, `ctorcall` and, under `reexport`, the user
  module naming no `mlxc_` entity; `check_test_registry.py` also holds the guard groups to their CTest
  entries and the named-only sub-suites to their rows. The milestone-1 follow-ups added `ctorexpr`.

## 9. Documentation and records

- **Adopt (SIMPLE): plans** in `doc/implementation_notes/{planned,completed,rejected}` by
  `doc/how2s/how2write_agent_plans.md`; policies in `doc/policies/` are the living truth.
- **Adopt (XEMA): a history lane.** `doc/history/YYYY-MM.md` records owner decisions, delivered batches,
  negative results and overrides, newest first; rules go to `CLAUDE.md`, the skills and the policies, never to
  the history.
- **Adapt (XEMA's two areas):** the record agents keep is `doc/` outside `doc/user/`; the pages for library
  users (the README, and from Phase 5 `doc/user/`) are plain language, describe what the library does now, and
  carry no dates, plans or record citations.
- **Deferred (both): a generated code map** from the `!@descr:` lines, once the tree passes about thirty
  modules.

## 10. Agent workflow

- **Adopt (both): git is read-only for agents**; all work stays in the unstaged diff; the owner commits.
- **Adopt (both): the dev cycle is the agent's**: it builds Debug and Release and runs the gate itself (in an
  unattended run on its own copy; interactively through the build bridge), reports what ran, and never claims
  a result it does not have.
- **Adopt (XEMA): dead code is deleted when found**, and "dead" is proved by the compiler, not by a search
  (SIMPLE's `simple-dead-code`, XEMA's `xema-dead-code`); the probe script is deferred until the tree is large
  enough to need it.
- **Adopt (XEMA): the 30 % rule.** A second code path for the same computation needs a measured gain above
  30 %; the benchmarks compare formulations, the library and the kernels SIMPLE copies keep the winner.
- **Adopt (both): capturing lessons.** A recurring trap or safeguard becomes a rule in the skill or this
  register in the same batch, with its check where reading can check it.
- **Not imported (XEMA): `agent_cycle.sh` and the build watcher**; arun's runs and the build bridge serve the
  same purpose here.
