# Release hardening: the report (run `mlxf_release_hardening`)

Status, 2026-11-25: delivered in the working tree on the M5 Ultra, base `0071f5a`; Phases 0 to 5 done. The
plan ([`planned/mlxf_release_hardening.md`](../planned/mlxf_release_hardening.md)) moves to `completed/` after
`scripts/release_gate.sh --require-tag` passes on the maintainer's tag. Every number and log path is in the plan's
Progress; `K` there is the run's `scratch/keep/`.

## 1. What was learned

- **The old gate tested the checkout, not the release.** An untracked source that does not compile failed the old
  gate in release mode (it builds the checkout in place) and passes the new one, which builds `git archive HEAD`
  and names the file it leaves out; `--allow-dirty` builds the working tree and fails on it.
- **The plan's premise about embedding was wrong in the other direction.** `mlxf_add_library` already exposed the
  library's whole module directory as a build interface: at the base a parent project could `use mlxf_c_array`.
  The build interface is now `<build>/include/mlxf` with `mlxf.mod` alone; `check_embed.sh` builds and runs a
  parent program and requires the private import to fail (it failed on the base and on a wide-open control).
- **GNU Fortran 14.4 serves the library but not the test tree.** The library builds without a warning and the
  installed consumer passes on the Metal and the CPU-only MLX; the test executable fails on a `-Wuninitialized`
  false positive (`src/test/mlxf_bench_polar_table.f90`) and on unlinked procedures of a submodule's own
  (`src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90`; GNU Fortran before 16, a form
  `check_submodule_linkage.py` does not look for). Both files are out of bounds; decision 22's second branch.
- **A CPU-only MLX runs the whole fast gate on the CPU.** Built from the pinned tags with `MLX_BUILD_METAL=OFF` in
  41 s, it skips only three GPU-only checks (the GPU's device information, the recovery gate of the Metal
  allocator, `guard_float64_on_gpu`) and owns 8 checks of `core`; every other area counts what the Metal build
  counts on its CPU device. MLX built for the running minor macOS release makes every Fortran link warn; the
  dependency script now targets the major release.
- **The README's first program failed as a user runs it.** Without `MLX_ENABLE_TF32=0`, MLX multiplies float32
  matrices on the M5's GPU at TF32 precision (0.637698 against 0.637628); the program now checks at 1e-3.
- **The table holds.** All 19 rows where Fortran and `mlxf` differ were confirmed against MLX 0.32.4 on the GPU
  and on the CPU-only MLX; no row contradicted the contract.
- **The generated layer's ABI holds, and its tests can now say so.** 33 echo functions compiled by Apple's clang
  cover every class of argument and result (in registers and on the stack), 36 structs and 23 enumerators; all 63
  mutations of the mapping table, the structs' fields and the callbacks' passing modes break the build (37) or
  the gate (26). One mutant was equivalent (an ignored dummy's passing mode) and is killed by a static rule.
- **An optimizer trap, not an ABI fault:** a returned address compared with a local variable's address that had
  been passed inside an `intent(in)` array compared false at `-O3` although the values were equal. The library
  never compares so (its handles come from C); the probe avoids it.
- **The base's flaky test** (K8's lifecycle check reads the active memory without synchronizing) failed 6 gate
  runs of about 40 and 3 of 12 CTest runs under load, never with the two synchronizations added in a scratch copy
  (0 of 12). Ruling R1 governed it; run `mlxf_toy_seam` owns the fix.

## 2. What changed, phase by phase

- Phase 1 (13 files): the release gate's snapshot modes, mlx-c pinning and side-effect check; the consumer check
  inside it with `--require-gpu`; the mlx-c version check of the package config and `mlxc_version` in `mlxf.pc`;
  the build-tree interface; the embedding check's program and refusal; rule `fortlsoff`; the consumer's argument.
- Phase 2 (21 files, 1 new): `mlx_metal_is_available()`; the three-session classification in the test library, the
  guard gate (a device column in `GUARDS`), the testers and the consumer; rule `devquery`; `build_mlx_deps.sh
  --cpu-only`; `scripts/ci_cpu_job.sh` and the workflow; the test policy, the contract and the setup guide.
- Phase 3 (11 files, 5 new): three example programs, `doc/quickstart.md`, the README's lead, `CONTRIBUTING.md`,
  rule `docex`.
- Phase 4 (11 files, 3 new): the generator's `--probe`, the probe's header, C file and tester, its build in
  `test/CMakeLists.txt`, rule `cbsig`.
- Phase 5 (6 files, 1 new): the history, the roadmap, the plans index, questions 27 and 28 for the MLX team, the
  register, this report.

## 3. Decisions taken under delegation

Each with its Progress entry: P0-a (the fast gate's time is CTest's), P0-b (`core` counted less MLX's address
reuse); P1-a (the toy tester left alone, the flake rerun; confirmed by R1), P1-b (the gate runs the snapshot's own
scripts; `--require-gpu` after the positional arguments), P1-c (`fortlsoff` reads the workflow; `ci.yml` edited in
Phase 1), P1-d (the build interface set in `src/CMakeLists.txt`; the test executable's module directory in
`test/CMakeLists.txt`), P1-e (a scratch `git clone` for release mode); P2-a (named additions to the Metal counts),
P2-b (`devquery`'s ledger for test code, a classification requirement for `test/consumer/`), P2-c (the GPU-only
skip's form), P2-d (the recovery gate GPU-only on a CPU-only MLX), P2-e (the deployment target; `WORK=`), P2-f
(decision 22's second branch); P3-a (the first example takes no argument), P3-b (`docex` also fails a block without
a row), P3-c (the first example's tolerance); P4-a (layout facts generated, C's by hand), P4-b (mutations on fresh
copies, restyled), P4-c (`cbsig` for the equivalent mutant), P4-d (field sizes in the layout check).

## 4. Deviations from the plan

- Files beyond their rows' phases, with the rows updated: `test/CMakeLists.txt` in Phase 1 (decision 25),
  `.github/workflows/ci.yml` in Phase 1 (rule `fortlsoff`). No file outside the table.
- The CI's oldest leg is GNU Fortran 15 (`gcc@15`), not 14.4, by decision 22; that leg is unverified here
  (Homebrew is read-only and `gcc@15` is not installed).
- Rule `devquery` holds `test/consumer/` to the classification instead of to its ledger (P2-b); its ledger holds
  the device tester alone (2 calls, from the base's 7 in 4 files).
- A fifth rule, `cbsig`, entered (decision 21: "a survivor gets a check that kills it").
- "Identical counts on the Metal build" is met as Phase 0's counts plus the plan's named additions: `core` +2
  (decision 9) and +99 (the `abi` sub-suite), per device and in `all`; every other area identical.
- Decision 16's 14 to 20 rows (*guessed*): 19.

## 5. Evidence against the baseline

- Release gate: base 59.25 s (*measured*); `--allow-dirty` 63.38 s, passed, against the bound 123.15 s; release mode on
  `0071f5a` passed (second run; the first failed at the K8 assertion alone).
- Fast gate (CTest real): base Debug 12.68 s, Release 10.75 s; final 12.52 s and 10.47 s (bounds 15.68 and 13.75 s).
- Consumer check: base 1.95 s; with the mlx-c refusal and the examples 2.5 s.
- 0 warnings in every Debug and Release build of the tree with GNU Fortran 16.2, on the Metal and the CPU-only MLX.
- The generated layer: 27 files byte-identical to Phase 0.
- Plants: decision 2 (the untracked source), decision 3 (side effects; rule `fortlsoff`, six plants), decision 6 (the
  mlx-c refusal), decision 23 (`devquery`, five), decision 17 (`docex`, six), `cbsig` (three); decision 25's two
  controls.
- The no-device recipe: the 34 skip lines of Phase 0, unchanged.
- Ruling R1 occurrences: 6 gate runs failed at the K8 lifecycle assertion alone (Phase 0 Release build 1; Phase 1
  `--allow-dirty` attempt 1 and the release-mode plant attempt 1; Phase 4 two Release gates; Phase 5 release mode
  attempt 1; and none in Phases 2 and 3), each passing on its rerun; 3 of 12 in a CTest load loop (Phase 1).

## 6. Left open for the maintainer

- Reported, not gated: the first hosted run of the workflow (job times, the cache, the runner's toolchain, the
  `gcc@15` leg); the CPU-only MLX's build time on a runner; whether the README's lead reads well.
- Reserved: the commit (with `scripts/ci_cpu_job.sh` executable) and the tag `v0.1.0`; the push; the FORTLS default;
  the advertised compiler floor (14 builds the library, not the tests).
- The session, in the turn the tag appears: `scripts/release_gate.sh --require-tag`, then the plan to `completed/`.
- Follow-ups: run `mlxf_toy_seam` (the K8 synchronizations, a diff is in `K/p1/flakefix.diff`); the two GNU Fortran 14
  defects in test code; `check_submodule_linkage.py` to look at a submodule's own plain procedures; a GNU Fortran
  report of the folded comparison (`K/p4/escape_finding.txt`).

## 7. Commit message

```
Release hardening: the installed package under test, CPU-only CI, quickstart, ABI probe

The release gate builds a snapshot of the commit (git archive; --allow-dirty the
working tree; --require-tag), pins the mlx-c the checkout finds, runs the snapshot's
fast gate, the install check with the consumer and three examples on the GPU and the
embedding check, and fails on editor side effects. The package config refuses another
mlx-c; mlxf.pc records mlxc_version. An embedding parent sees mlxf.mod alone.
mlx_metal_is_available() is public; the tests, the guard gate and the consumer tell
three sessions apart, so a CPU-only MLX (build_mlx_deps.sh --cpu-only) runs the fast
gate on a hosted runner (ci_cpu_job.sh, the workflow's CPU jobs). doc/quickstart.md
lists 19 differences between Fortran and mlxf, each proven by an example block or a
guard; the README leads with a program the gate runs; CONTRIBUTING.md. An ABI probe
compiled by Apple's clang checks every argument and result class, the structs and the
enumerators; 63 mutations of the mapping table and the callbacks fail the gate. Rules
fortlsoff, devquery, docex and cbsig.

New files: CONTRIBUTING.md, doc/quickstart.md, scripts/ci_cpu_job.sh,
src/test/mlxf_abi_probe.c, src/test/mlxf_abi_probe.h, src/test/mlxf_abi_tester.f90,
test/consumer/mlxf_example_differences.f90, test/consumer/mlxf_example_errors.f90,
test/consumer/mlxf_example_first.f90,
doc/implementation_notes/completed/mlxf_release_hardening_report.md.
```
