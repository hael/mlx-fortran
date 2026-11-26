# Compiler issues the library works around

Reproducers of gfortran defects the repository works around: issues 1 to 5 bear on the handle model
(`doc/policies/binding_contract_policy.md`, "Lifetime", the unsupported uses), issue 6 on test code. Each `.f90` file stands alone and states
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
- **Bugzilla check, 2026-11-22:** [PR 110626](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=110626) is
  **REOPENED**. Its comment 27 describes the scalar fix and its exclusions; comment 31 reports a remaining
  duplicated-finalization case in a type with another allocatable or pointer component. That case is not
  the same as this self-assignment reproducer. The trunk run below passes for this case; it does not settle
  the separately reopened case.
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

### 6. An empty `pack()` result passed to an assumed-rank dummy has a corrupt descriptor

- **File:** `gfortran_empty_pack_assumed_rank.f90` (found 2026-11-25 with 16.2.0, M5 Ultra, macOS on
  Darwin 27.2.0, while verifying the NaN-safe test reduction; not checked on trunk).
- **Standard:** F2018 8.5.8.7: an assumed-rank dummy takes the rank and shape of its actual, here a
  zero-size rank-1 array, so `size(x)` is 0 and `select rank` takes `rank(1)`.
- **Expected:** `empty: rank 1 size 0 arm 1`.
- **Observed:** `empty: rank 1 size -1 arm default`; the nonempty control passes.
- **Related:** not searched yet; check Bugzilla for assumed-rank and zero-size `pack` before filing.
- **Where the repository meets it:** test code only. `nan_maxval` (`src/test/framework/mlxf_test_reduce.f90`) has one
  specific per rank instead of an assumed-rank dummy, since its callers pass masked `pack()` results that
  may be empty.

## Trunk check and proposed reports, 2026-11-22

The five standalone files were compiled and executed on Compiler Explorer's x86-64 Linux gfortran trunk,
GNU Fortran 17.0.0 20261122, GCC commit `a3a3f32131a9fe59b6a3a555696b63094fdea323`. All compiled with
`-std=f2018 -Wall -v`; issue 5 also used `-O0 -g -fsanitize=address`. The outputs below are observations on
that snapshot, not a statement about every platform or release branch. Raw JSON responses, including
compiler version and output, are in `/private/tmp/mlxf-m1-codex-20261122/ce-issue<N>-result.json`.
On this trunk snapshot, `-Wall` also warns that `a2`, `a3`, and `s` in issue 1 and `x` and `v` in issue 2
are set but not used; issue 5 warns about `status` at `if( status == 0 )` after `allocate(..., stat=status)`.
Issues 3 and 4 emitted no compiler warnings. The exit values and diagnostics are retained in the JSON.

1. **Duplicate of PR 57696; add a comment there.** [PR 57696](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=57696#c0)
   is NEW and its original example is the same skipped defined assignment for an allocatable component.
   [PR 119802](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=119802#c0) is UNCONFIRMED and describes the same
   general case. Trunk output (exit 0):

   ```text
   plain component:            defined assignments = 1
   allocatable scalar comp:    defined assignments = 0
   allocatable array comp:     defined assignments = 0
   allocate(source=):          defined assignments = 0
   self assignment t = t:      defined assignments = 1
   ```

   Suggested comment: On the trunk snapshot named above, the attached reproducer also skips the component's
   defined assignment for both scalar and three-element allocatable components during intrinsic parent
   assignment; the plain component is a control. It expects 1 and 3 calls and gets 0 and 0.

2. **Related to PR 90068; file as new.** [PR 90068](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=90068#c4)
   is RESOLVED FIXED: its 2024 patch handles finalizer creation for function results in array constructors.
   This reproducer still misses final calls on the later snapshot; it may be a regression or an uncovered
   case, so link the report rather than presume a duplicate. Trunk output (exit 0):

   ```text
   x = mk(1):               finals = 2 (expected 2: the result, and x before definition)
   call take([mk(1), mk(2)]): finals = 0 (expected 2)
   v = [mk(3), mk(4)]:       finals = 2 (expected 4: two results, v before definition)
   ```

   Suggested report: Nonpointer function results referenced in an array constructor are not finalized
   after the statement. The attached standalone program counts final calls for a direct assignment, a
   constructor passed to a subroutine, and a constructor assigned to an array. See also PR 90068.

3. **Related to PR 121475; file as new.** [PR 121475](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=121475#c8)
   is RESOLVED FIXED for a scalar class-defined assignment; the array elemental-assignment case still
   misses the result's finalization on this snapshot. Trunk output (exit 0):

   ```text
   v(1) = mk(1): assignments = 1, finals = 1 (expected 1, 1)
   v = mk(2):    assignments = 3, finals = 0 (expected 3, 1)
   ```

   Suggested report: A scalar finalizable function result assigned to a whole array through an elemental
   defined assignment is not finalized. Assignment to one element finalizes it as expected. See also
   PR 121475.

4. **Fixed on the tested trunk snapshot.** The scalar self-assignment reproducer passes on commit
   `a3a3f32131a9fe59b6a3a555696b63094fdea323` (exit 0):

   ```text
   w = w
       defined assignment: lhs id 5 <- rhs id 5
   after w = w: w%c%id = 5 (expected 5)
   ```

   [PR 110626](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=110626#c27) describes the related scalar fix;
   the tested snapshot is a descendant of its trunk commit `a03222414043b7155a76f7e564fb688ac5ac7bb6`.
   Its [reopened case](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=110626#c31) concerns types with other
   allocatable or pointer components. Do not file this passing scalar case as a new trunk defect. If useful,
   tell the existing report that this self-assignment example passes on the snapshot above.

5. **Related to PR 128856; file as new.** [PR 128856](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=128856#c2)
   is RESOLVED FIXED for other function-result argument finalization contexts. This allocatable-array
   result through a procedure pointer still fails under AddressSanitizer on the snapshot, which is a
   descendant of the PR's trunk fix `284b847b3856e7d35949c6e5cdefbe3cfab8021a`. Trunk output
   (build exit 0, run exit 1; address and stack omitted):

   ```text
   subroutine with an allocatable intent(out) output: PASS
   ERROR: AddressSanitizer: heap-use-after-free
   WRITE of size 4
   ```

   Suggested report: An allocatable array result of a finalizable type returned through a procedure pointer
   and passed as an actual argument is freed before its finalizer writes to it. The included subroutine
   control passes; the function case reports heap-use-after-free with AddressSanitizer. See also PR 128856
   and the finalization tracker PR 37336.

For context, [PR 121472](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=121472#c10) is RESOLVED FIXED for an
internal compiler error involving a finalizable zero-size type; it is related background, not evidence that
the remaining failures are duplicates. [PR 37336](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=37336) is the
ASSIGNED finalization tracker. The owner files reports; none has been filed by the agent.

## Upstream numbers

| Issue | Status | Report | Filed by | Date |
| --- | --- | --- | --- | --- |
| 1 | Duplicate of PR 57696 | (comment pending) | | |
| 2 | Related to PR 90068; file as new | (pending) | | |
| 3 | Related to PR 121475; file as new | (pending) | | |
| 4 | Fixed on tested trunk snapshot | (none needed for this case) | | |
| 5 | Related to PR 128856; file as new | (pending) | | |
| 6 | Not yet searched | (pending) | | |
