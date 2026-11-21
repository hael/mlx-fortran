# Test Environment Policy

What a test is in mlx-fortran, where it goes and what runs when. A short version of SIMPLE's test policy
with XEMA's test-admission rules (`doc/architecture_principles.md`, section 7) and the rules a library on two
devices adds. The rules in short, for writing a test, are in
`.github/skills/mlxf-modern-fortran/references/testing.md`.

## 1. The environment

One test executable, `mlxf_test_exec`, built by every compile script unless it is given `--exclude-tests`
(CMake option `BUILD_TESTS`, default ON). It compiles the test-only sources (`src/test/` and every
`*_tester.f90`); the library `mlxf` never contains them. Every test is reached through
`mlxf_test_exec test=<name> [suite=<sub-suite>]`; `test=list` lists what exists.

| label | entries | when | what |
| --- | --- | --- | --- |
| `fast` | one `unit_<area>` per area, and the guard groups | every compile script, between build and install | unit tests: hermetic, in-process (guard groups: one child per member), one thread, seconds |
| none | `bench_<x>` | by hand | measure-only benchmarks; never pass/fail, never registered with CTest |

**The fast gate is part of the build.** `scripts/run_fast_gate.sh` runs between `make` and
`make install`: first the static gate `scripts/check_tree.sh` (`check_descr.py`, `check_rules.py`,
`check_test_registry.py`, `check_guide_imports.py`, `check_submodule_linkage.py`, `format_use_blocks.py
--check`, a warning for untracked sources), then `ctest -L fast` with half the cores, then
`ctest_budget.py`, which fails the build on a failed entry and only warns when the gate takes more than
60 s of real time. A failed gate installs nothing. Each fast entry has a 600 s CTest deadline and runs with
`OMP_NUM_THREADS=1`, `OMP_WAIT_POLICY=PASSIVE`, `OMP_THREAD_LIMIT=4` and `MLX_ENABLE_TF32=0`.

**Checks are free, processes are budgeted.** A CTest entry is an isolation unit, not an assertion.
`MLXF_CTEST_BUDGET` in `test/CMakeLists.txt` must equal the registered count or configuration fails; it
changes only with an owner decision or a plan that names the new entry, recorded in `doc/history/`.

## 2. What a test is

- It can fail, and its failure reaches the exit status (`mlxf_test_utils` assertions; `mlxf_test_exec`
  exits 1 when one failed).
- Its expected value comes from outside the code under test: a closed form, a brute force in plain
  Fortran (double precision where it matters), an exact array operation, or numbers from an emulation
  pasted with a note on how they were made.
- Its tolerances are named and derived from the arithmetic, or measured on the CPU device and frozen
  before the test is used as a gate. A tolerance widened until a test passed is a finding.
- It asserts conventions: memory order, index base, dimension numbering, FFT sign and normalisation.
- Storage identity is compared with `bits_equal` (transfer-based), never `==` on reals.
- Its random draws come from fixed seeds.
- Four kinds, never mixed: identity (bytes equal), correctness (against an independent value),
  robustness (a distribution over seeds), performance (timings, never pass/fail).
- A test that comes with a fix is shown to fail on the tree before the fix.

## 3. Failure paths

- A stop that is the library's contract (a stale handle used, an operation on an empty array, a call from
  inside an OpenMP region) is tested by a member of a guard group, run by
  `mlxf_test_exec expect_aborts <group>` in its own child process and accepted only when it exits with
  `MLXF_HARD_ERROR_STATUS`; the parent reports every faulty member. Never a raw `WILL_FAIL`: it accepts
  any non-zero exit, a broken fixture or a runtime check included. One guard group is one CTest entry.
- The intended stop is the last statement the child can reach, and its fixture is proven by a passing
  sibling. Errors a checked procedure reports through `status` are tested in-process.

## 4. Devices

- MLX runs an operation on the CPU device or the GPU device (Metal). A test of an operation runs on
  every device present; `mlxf_test_exec device=cpu|gpu|all` (from Phase 1 of the design plan; default
  `all`) restricts it.
- Whether a GPU is present is `mlx_device_count(MLX_GPU) > 0`, not `mlx_metal_is_available`, which only says
  that the Metal backend was compiled in. In a headless, sandboxed or virtual session the count is 0, and a
  Metal build of MLX then cannot allocate arrays on either device: tests that need a device report a skip.
- CMake option `MLXF_REQUIRE_GPU` (default ON on macOS arm64, OFF in the CI), a compile definition of the
  test executable, turns that skip into a failure, so a development Mac can never pass the gate without
  running the device tests.
- GPU results are compared with tolerances, never bytes: the GPU computes in float32 and complex64 only,
  and atomic reductions sum in an order that changes from run to run. Identity tests (bytes) are for
  pure data movement; float64 is tested on the CPU device only.

## 5. Where a test goes

- In the area of the code it tests, as a sub-suite (a `run_suite` row of
  `src/test/mlxf_test_registry.f90`). A new area is a row in `AREAS`, a `case` branch, an entry of
  `MLXF_TEST_AREAS` in `test/CMakeLists.txt` and a budget raise, kept in step by
  `scripts/check_test_registry.py`.
- Fast tier only if it is hermetic (no network, no user file, no dependence on core count, load or
  clock), runs in-process on one thread, and leaves no files behind. An entry above 0.5 s in Release says
  why in its registration comment. Never shrink a test until it fits; give it its own label instead.
- Both build types: a change to tests is verified in Debug and Release.

## 6. Testers

- `mlxf_<thing>_tester.f90` beside the module it tests: a `private` module exporting only
  `run_all_<thing>_tests`, which prints `**** running all <thing> tests ****`; each `test_<what>` prints
  its name first. No `stop` or `error stop` in a tester outside a guard-group member.
- A tester that needs private entities is a submodule of the module it tests; no entity is public only
  for a tester. A submodule calls no private plain procedure of its module (gfortran before 16 does not
  link it; `scripts/check_submodule_linkage.py`).
- Deleting a test needs a kept test that reaches the same branch with the same assertion.

## 7. Python

Python the build or the gate runs uses the standard library and nothing newer than 3.7, the floor of
`find_package(Python3 3.7 ...)` in `cmake/Dependencies.cmake`. Passing on macOS does not show a breach.
