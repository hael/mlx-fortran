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
| none | `bench_<x>` | by hand | benchmarks: measure-only modes, and accuracy modes that hold frozen gates too large for the fast gate; never registered with CTest |

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

The current process budget is **8**: areas `core`, `array`, `ops`, `linalg`, `fft`, `compile`, `kernels`, plus
the `object_contracts` guard group (ten members, including invalid FFT normalizations). The compile suite also
checks empty local handles in a two-thread OpenMP region; no live MLX work is submitted there. The operation areas compare both devices with independent Fortran
references; `array` also runs 10,000 evaluated iterations per new operation family and checks exact
active memory, live handles and stale releases. The compile area checks byte identity for exactly
representable compiled/uncompiled arithmetic on each device, shapeless trace reuse and callback error
recovery; the array area also runs 10,000 compiled calls and verifies complete closure teardown.
The kernels area holds test-only models of SIMPLE's pipelines written against `mlxf` as a user writes
(`src/test/mlxf_kernel_<x>.f90`); its sub-suite `polar_table` checks the polar table's scoring workspace
on a seeded fixture against a double-precision ring oracle, on both devices, with row bounds calibrated
on the CPU device and frozen in `src/test/mlxf_test_defs.f90` before the first GPU run; the draw on the
device's own rows, refusals of mismatched blocks, schedule identity and the workspace's lifecycle. Its
sub-suite `polar_shiftmap` checks the workspace's shift maps on analytic fixtures against a direct
double-precision residual at every cell, with caps confirmed on the CPU device and frozen there before the
first GPU run: the maps, the mode where its margin is clear, the zero radius, the folding of orders beyond the
directions, the Nyquist ring, the width and the log evidence against the host's moments, candidate order and
tiles, refusals and rebuilds, and 100 prepare-score-invalidate cycles. The shift-map suite also checks both
contractions and direction transforms, active-radius/padded order tiles, requested-output profiling, changed
weights/grid/band, strict width cutoffs and exact teardown. `unit_kernels suite=polar_shiftmap_accuracy` is
named-only: a direct-residual sample at the production window/screen geometry, on both devices and for every
graph combination. It uses the same frozen caps, has assertions, and is outside the fast CTest process budget.
Constants several test modules share live in `src/test/mlxf_test_defs.f90`, a defs module (rule `defs`).

**Benchmarks** are `mlxf_test_exec test=bench_<x> suite=<mode> [key=value ...]`, listed in the registry's
`BENCHES` table and reached through `run_bench` (`check_test_registry.py` holds the two to each other). They
run by hand, never in CTest, and append rows to `./bench_<x>*.tsv` in the working directory. A mode that
measures asserts nothing. A mode that judges, such as `bench_polar_table suite=accuracy` (the polar table's
64,000-pair block against its DFT-matrix oracle, at SIMPLE's sizes), uses the assertions of `mlxf_test_utils`
and fails the process like a test. Its bounds are calibrated on the CPU device and frozen in
`src/test/mlxf_test_defs.f90` before its first GPU run. `bench_polar_table suite=shiftmap` measures the shift
maps on SIMPLE's grid (read from a key = value file of SIMPLE's rows) with SIMPLE's column names. Timed runs
follow the plan's rules: Release, an idle machine with the load recorded, best of 3 after a warm-up, two
invocations, and the precision mode in every row. The shift-map options `contraction=1|2`, `hermitian=0|1`,
`ctile=`, `otile=` and `compact=0|1` select test-model experiments. `widths=quarter|none` selects synthetic
cutoff survivors; `widths=all evidence=0` is the matched baseline. Cutoff/evidence rows do not claim an
all-width CPU speedup. Grid files must carry fresh `simple_commit`, `fftw_plans` and full-team rates before
ratios are used; `revision=` identifies the measured mlx-fortran tree. Performance runs are currently deferred
by the owner; running either accuracy suite is correctness validation, not a throughput benchmark.

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
- A member is a row of the `GUARDS` table and a `case` of `run_guard` in `src/test/mlxf_test_registry.f90`;
  the child is `mlxf_test_exec guard=<member>`, and `mlxf_test_exec expect_abort <member>` runs one member as
  the group does. The group `object_contracts` holds the stops of the binding contract (an operation on an
  empty array, a stale handle used, a call inside an OpenMP region, a float64 operation built on the GPU, and
  the one-thread guard on the paths that touch no operand: an empty evaluation list, `mlx_live_count`,
  `mlx_last_error`, a live private copy released in a region).
  Without a GPU the members are not run (each would stop for that reason instead of its own): a skip, or a
  failure under `MLXF_REQUIRE_GPU`.
- No test pins a compiler defect: a compiler that fixes one must not fail the build. A test that meets a
  defect accepts the conforming result as well (the allocatable handle component: a counted copy or the
  diagnosed bitwise one) and tests the diagnosis through a bypass every compiler takes (`allocate(source=)`).

## 4. Devices

- MLX runs an operation on the CPU device or the GPU device (Metal). A test of an operation runs on
  every device present; `mlxf_test_exec device=cpu|gpu|all` (default `all`) restricts it. A tester takes
  its devices from `test_devices(devs)` of `mlxf_test_utils`.
- Whether a GPU is present is `mlx_device_count(MLX_DEVICES%gpu) > 0`, not `mlx_metal_is_available`, which only says
  that the Metal backend was compiled in. In a headless, sandboxed or virtual session the count is 0, and a
  Metal build of MLX then cannot allocate arrays on either device: tests that need a device report a skip,
  the memory limits (the Metal allocator's) included. A test asserts no more about an absent device than
  that the call returns: MLX 0.32 accepts an absent GPU as the default device and fails only at the first
  allocation. The headless gate is reproduced on a Mac with
  `sandbox-exec -p "(version 1)(allow default)(deny iokit-open)"` around a build configured with
  `-DMLXF_REQUIRE_GPU=OFF`.
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
  why in its registration comment. A test that is too slow for the fast label is shrunk or optimized (a
  smaller fixture, fewer iterations, a cheaper form of the same check), as long as it can still fail on the
  guarantee it names.
- **Named-only sub-suites** (owner ruling, 2026-11-22): where a gate is shrunk, a full form whose cost grows
  with the machine (the recovery gate's half-batch evaluation allocates half the GPU's maximum buffer) may be
  kept as a sub-suite listed in the registry's `NAMED_ONLY` table. Its area runs it only when `suite=` names
  it, and `test=list` lists it. The fast gate keeps a form that tests the same guarantee at a fixed cost. A
  plan names the points where the named-only form runs (a new machine, a phase exit);
  `check_test_registry.py` holds every `NAMED_ONLY` name to a `run_suite` row. Today: `unit_core
  suite=recovery_half`.
- Both build types: a change to tests is verified in Debug and Release.

## 6. Testers

- `mlxf_<thing>_tester.f90` beside the module it tests: a `private` module exporting only
  `run_all_<thing>_tests`, which prints `**** running all <thing> tests ****`; each `test_<what>` prints
  its name first. A tester that owns a named-only sub-suite (section 5) also exports that sub-suite's
  `run_all_<name>_tests`. No `stop` or `error stop` in a tester outside a guard-group member.
- A tester that needs private entities is a submodule of the module it tests; no entity is public only
  for a tester. A submodule calls no private plain procedure of its module (gfortran before 16 does not
  link it; `scripts/check_submodule_linkage.py`).
- Deleting a test needs a kept test that reaches the same branch with the same assertion.

## 7. Python

Python the build or the gate runs uses the standard library and nothing newer than 3.7, the floor of
`find_package(Python3 3.7 ...)` in `cmake/Dependencies.cmake`. Passing on macOS does not show a breach.
