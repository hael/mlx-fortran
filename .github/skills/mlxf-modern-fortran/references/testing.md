# Writing a test in mlx-fortran: the rules in short

The rule set is `doc/policies/test_environment_policy.md` (from SIMPLE's test policy and XEMA's test
admission rules; `doc/architecture_principles.md`, section 7).

## What a test is

- It can fail, and its failure reaches the exit status: assertions of `mlxf_test_utils`, one per
  guarantee, the message stating the guarantee ("a Fortran (3,5) array reaches MLX as shape [5,3]
  without a copy", not "shape test 2").
- The expected value comes from outside the code under test: a closed form, a brute force in plain
  Fortran in the test (double precision where it matters), an exact array operation, or numbers from
  an emulation (numpy, MLX in Python) pasted with a comment saying how they were made. Never the
  routine's own output.
- Tolerances are named and derived from the arithmetic, or measured on the CPU device and frozen before the
  run they judge. A tolerance widened until the test passed is a finding.
- Storage identity is compared with `bits_equal` (`mlxf_test_utils`, real32, real64, complex64), never `==`
  on reals.
- Conventions are asserted: memory order, index base, dimension numbering, sign of transforms,
  normalisation of FFTs.
- A negative control where cheap (a transposed input does not compare equal; a freed handle is not live).
- Every random draw from a fixed seed (`set_fixed_seed`, and MLX's own key for MLX draws).
- Not a test: a program that only runs, prints or times. Benchmarks are measure-only entries
  (`test=bench_<x>`), never pass/fail and never in CTest.

## Checks are free, processes are budgeted

- Default: add checks to the existing area suite; a new component's tester joins its area as a sub-suite
  (a `run_suite` row), not as a new CTest entry.
- A new CTest entry needs a reason in its registration comment (a new area the plan names, a guard group,
  resource needs that make sharing a process unsafe) and raises `MLXF_CTEST_BUDGET` in
  `test/CMakeLists.txt`, which configuration holds to the registered count.

## Failure paths: guard groups

- Where dying is the contract (a stale handle used, an operation on an empty array, a call from inside an
  OpenMP region), the test is a member of a guard group run by `mlxf_test_exec expect_aborts <group>`: each
  member in its own child process (`mlxf_test_exec guard=<member>`), accepted only with
  `MLXF_HARD_ERROR_STATUS`. Never a raw `WILL_FAIL`. A member is a row of the `GUARDS` table and a `case` of
  `run_guard` in `src/test/mlxf_test_registry.f90`.
- The intended stop is the last statement the child can reach, its fixture is proven by a passing sibling,
  and the verbose output is read once to confirm it dies at that guard.
- Everything a checked procedure reports through `status` is tested in-process, not by aborting.

## Devices

- A test of an operation runs on every device `test_devices(devs)` returns (`mlxf_test_utils`: the
  `device=` selection, the skip without a GPU, the failure under `MLXF_REQUIRE_GPU`). A GPU is present when
  `mlx_device_count(MLX_DEVICES%gpu) > 0`; without one a Metal build of MLX cannot allocate on either device, so
  device tests report a skip, which `MLXF_REQUIRE_GPU` (ON on a development Mac) turns into a failure.
  Anything that reaches the Metal allocator (the memory limits too) needs a device. Headless on a Mac:
  `sandbox-exec -p "(version 1)(allow default)(deny iokit-open)"` around a `-DMLXF_REQUIRE_GPU=OFF` build.
- GPU results are compared with tolerances, never bytes: float32 only, and atomic reductions
  (scatter-add) sum in an order that changes from run to run. float64 exists on the CPU device only.
- CTest runs with `MLX_ENABLE_TF32=0`: full float32 matrix products.

## Where it goes

- The area of the code it tests (`unit_<area>`), as a sub-suite (`run_suite` row) of that area.
- Fast tier only if: it can fail; it is hermetic (no network, no user file, no dependence on core count,
  load or clock); it runs in-process on one thread; it leaves no files behind. An entry above 0.5 s in
  Release says why in its registration comment; the whole fast label stays under 60 s.

## A tester

- `mlxf_<thing>_tester.f90` beside the module, one-line `!@descr:` naming what it tests; a `private`
  module exporting only `run_all_<thing>_tests`, which prints `**** running all <thing> tests ****`; each
  `test_<what>` prints its name first. A form of a gate whose cost grows with the machine is a named-only
  sub-suite (registry table `NAMED_ONLY`, run only by `suite=<name>`), and its tester also exports its entry.
- No `stop` or `error stop` in a tester outside a guard-group member.
- No function reference or operator result inside an array constructor of handles (rules `ctorcall`,
  `ctorexpr`), at most five dummy
  arguments (rule `arity`); no test pins a compiler defect (a compiler that fixes it must not fail the
  build): accept the conforming result too, and test a diagnosis through a bypass every compiler takes.
- Register it with a `run_suite` row in `src/test/mlxf_test_registry.f90`; a new area also needs its
  entry in `AREAS`, a `case` branch, the CTest list in `test/CMakeLists.txt` and the budget.
- An import three or more tests share sits at module scope; one a single test needs stays inside that test.

## Before handing over

- `scripts/check_tree.sh` (the static gate); the touched files through `restyle_fortran.py` and
  `format_use_blocks.py`; then the build and the fast gate in Debug and Release.
- A test that comes with a fix is run on the previous tree and shown to fail there; one that passes on both
  proves nothing about the change.
- A test that finds a defect: the fix lands in the same change and the test pins it. Deleting a test needs a
  kept test that reaches the same branch with the same assertion.
