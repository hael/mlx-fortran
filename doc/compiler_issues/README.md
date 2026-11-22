# Compiler issues the library works around

Reproducers of gfortran defects that bear on the handle model (`doc/policies/binding_contract_policy.md`,
"Lifetime", the unsupported uses). Each `.f90` file stands alone, is warning-free under `-Wall`, and states
the standard's requirement, the expected output and the output observed, with the date and the compiler. The
library depends on no fix, and no gate pins a defect: a compiler that fixes one must not fail the build.

Run them all (each prints its counts; compare with its header):

```bash
cd doc/compiler_issues
for f in gfortran_*.f90; do echo "== $f"; gfortran-16 -std=f2018 -Wall "$f" -o /tmp/ci && /tmp/ci; done
```

## Reporting upstream

The maintainer files reports in GCC Bugzilla (product gcc, component fortran) and adds the numbers here. An
agent files nothing. Before filing, read the related reports below: on 2026-11-22 they were found through
the gcc-bugs and fortran mailing-list archives, as Bugzilla itself could not be reached from the session.
Their current status needs a check at the source. Where a report already covers a defect, the reproducer is
added to it as a comment, not filed again.

Common fields: host and target aarch64-apple-darwin25 (macOS 26.7.3, Apple M2 Ultra; issue 5 on an M3 Pro);
GNU Fortran 16.2.0 (Homebrew GCC 16.2.0), also 13.4.0 for issues 2 to 4; flags `-std=f2018`, at `-O0 -g -fcheck=bounds,do,mem`
and at `-O3`, the same output.

### 1. Defined assignment skipped for allocatable components in intrinsic assignment

- **File:** `gfortran_alloc_component_defined_assignment.f90` (observed 2026-11-20, 16.2.0).
- **Standard:** F2018 10.2.1.3, paragraph 13: a noncoarray allocatable component whose declared type has a
  type-bound defined assignment is assigned by that defined assignment, as a plain component is.
- **Expected:** one defined assignment for the allocatable scalar component, three for the allocatable array
  component of three elements.
- **Observed:** 0 and 0. The plain component gets 1; `allocate(source=)` gets 0, which is conforming.
- **Related, likely the same defect:** PR 57696, which the 2026-08 commit for PR 110626 names as "the
  allocatable-component case"; PR 119802 (2025, "Defined assignment not called for component of derived
  type", unconfirmed then). Add this reproducer to PR 57696 rather than filing a new report.
- **Where the library meets it:** unsupported use 1 of the binding policy; the copy is diagnosed as stale.

### 2. A function result inside an array constructor is never finalized

- **File:** `gfortran_finalize_ctor_function_results.f90` (observed 2026-11-21, 16.2.0 and 13.4.0).
- **Standard:** F2018 7.5.6.3, paragraph 5: the result of a referenced nonpointer function is finalized
  after execution of the innermost executable construct that contains the reference.
- **Expected:** `call take([mk(1), mk(2)])` finalizes the two results (2); `v = [mk(3), mk(4)]` finalizes the
  two results and `v` before it is defined (4).
- **Observed:** no finalization of the results in either statement, while a result outside a constructor
  (`x = mk(1)`) is finalized.
- **Related:** the finalization meta-bug PR 37336; PR 90068 (a 2024 patch adding finalizer creation for
  array-constructor temporaries of derived-type functions, so this may be a regression or a case it did not
  cover); PR 121472 (function-result finalization, 2025 patches); PR 128856 (2026, a function result passed
  as an actual argument is not finalized when its type has a component with a type-bound defined
  assignment). File as new if none of them covers the constructor case, with "See also" to these.
- **Where the library meets it:** unsupported use 3; rules `ctorcall` and `ctorexpr` keep it out of this
  repository's code.

### 3. A scalar function result assigned to a whole array through an elemental defined assignment is not finalized

- **File:** `gfortran_finalize_scalar_result_to_array.f90` (observed 2026-11-21, 16.2.0 and 13.4.0).
- **Standard:** F2018 7.5.6.3, paragraph 5, as in issue 2.
- **Expected:** after `v(1) = mk(1)`, 1 assignment and 1 finalization; after `v = mk(2)` for `v(3)`, 3
  assignments and 1 finalization.
- **Observed:** 1 and 1 for the element; 3 and 0 for the whole array.
- **Related:** PR 121475 (2025, "Missed finalization": a function result assigned through a class defined
  assignment is finalized once instead of twice); PR 37336. File as new with "See also" if PR 121475 does not
  cover the elemental whole-array case.
- **Where the library meets it:** unsupported use 4.

### 4. Intrinsic self-assignment finalizes the right side's components before the defined assignments read them

- **File:** `gfortran_self_assignment_finalizable_components.f90` (observed 2026-11-21, 16.2.0 and 13.4.0).
- **Standard:** F2018 10.2.1.3: in intrinsic assignment the expression is evaluated before the variable is
  finalized and defined; the finalized object is the variable, and the component assignments see the value
  of the expression.
- **Expected:** after `w = w` the component's id is unchanged (5).
- **Observed:** the final procedure sees id 5, then the defined assignment sees a right side of id 0, and
  `w%c%id` ends 0.
- **Related, possibly fixed:** PR 110626 ("[13/14/15/16/17 regression] Duplicated finalization in derived":
  gfortran finalized a temporary copy in the component-wise expansion of a derived-type assignment), fixed
  on trunk in August 2026 and cherry-picked to a release branch; the commit leaves array left sides and
  allocatable components on the old path. Run this reproducer with a gfortran that has the fix (a 16.3 or
  trunk build) before filing. If it still fails, file as new with "See also" PR 110626.
- **Where the library meets it:** unsupported use 5; the owner ends stale and is diagnosed at its next use.

### 5. An allocatable array function result is freed before it is finalized

- **File:** `gfortran_finalize_allocatable_array_result.f90` (found 2026-11-22 with 16.2.0 while writing
  `mlx_function`; built with `-fsanitize=address`).
- **Standard:** F2018 7.5.6.3, paragraph 5, as in issue 2: the result is finalized after the innermost
  executable construct, and only then may its storage go.
- **Expected:** both cases print PASS.
- **Observed:** the subroutine control (an allocatable `intent(out)` array) passes. The function case
  (`call consume(q%f())`, an allocatable array result of a finalizable type through a procedure pointer)
  aborts with a heap-use-after-free in the final procedure. The merged program was rerun on 2026-11-22,
  M3 Pro / macOS 26.7.3, GNU Fortran 16.2.0, exactly with its header's
  `-std=f2018 -Wall -O0 -g -fsanitize=address` and `ASAN_OPTIONS=symbolize=0`: compile exit 0,
  zero warnings; run return code -6 (SIGABRT). Output excerpt, with process ID and address omitted:

  ```text
  subroutine with an allocatable intent(out) output: PASS
  ERROR: AddressSanitizer: heap-use-after-free
  WRITE of size 4
  ```
  The function PASS line is not reached. Full output (including addresses and stack frames):
  `/Users/elmlundho/for_claude/mlxf-review-2026-11-22/compiler-issue5.log`.
- **Related:** the finalization meta-bug PR 37336; PR 121472 (function-result finalization patches, 2025);
  PR 128856 (a function result passed as an actual argument, 2026). Check them before filing.
- **Where the library meets it:** `mlx_function`'s callback is a subroutine with an allocatable
  `intent(out)` output array (owner ruling, 2026-11-22; binding policy, closure callbacks), never a function
  returning an array of handles.

## Upstream numbers

| Issue | Report | Filed by | Date |
| --- | --- | --- | --- |
| 1 | (comment on PR 57696, pending) | | |
| 2 | (pending) | | |
| 3 | (pending) | | |
| 4 | (pending a run with the PR 110626 fix) | | |
| 5 | (pending) | | |
