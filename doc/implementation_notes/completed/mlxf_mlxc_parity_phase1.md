# mlx-c parity: completed Phases 0 and 1

Status, 2026-11-24: completed delivery record at `26387c1`. Phase 0's ledger/probes and Phase 1's
65 elementwise wrappers are delivered; 274 entries remain pending. Phases 2–9 remain in
[the active parity plan](../planned/mlxf_mlxc_parity.md), with the Phase 3 review hold unchanged.

The original phase instructions and Progress follow. Base measurements, Phase 1a calibration and
rulings R1–R4 remain authoritative for the continuing run. In particular, its build/gate timing limits
are re-judged after Phase 3 under R3; archiving this record does not waive that requirement or close
the documented GPU `expm1` upstream defect.

## Completed phase instructions

### Phase 0, the baseline and the ledger

Build Debug and Release on the base, run the fast gate, and record per-area times and the Release clean
build time (twice, for the spread). Write `scripts/mlxc_parity.txt` name by name for all prototypes. Add rule
`parity` with five plants (a missing name, an extra name, a `public` name not exported, a `pending` line of a
closed phase, a grown `pending` count) and show each one fails. Apply decision 1 to the skill, `CLAUDE.md`
and the register. Probes, each a scratch program whose output is recorded in Progress:

- which `linalg` functions refuse the GPU stream at MLX 0.32.4;
- the sign rule of `remainder`;
- `round` at .5;
- whether `vecdot` conjugates;
- the stability of `sort` and `argsort`;
- `searchsorted`'s side convention;
- whether `mlx_distributed_init` with no backend gives a singleton group.

Exit: the ledger has exactly the prototype list's names; `check_tree.sh` passes and each plant fails; the
probes are in Progress; base gates pass with their counts recorded.

### Phase 1, elementwise

The unary and binary operations, `clip`, `nan_to_num`, `isnan`/`isinf`/`isfinite`/`isposinf`/`isneginf`,
`isclose`, `allclose`, `array_equal`, `**`, `.eqv.`/`.neqv.`, the bitwise family, `sigmoid`, `square`,
`reciprocal`, `rsqrt`, `expm1`, `log1p`, `log2`, `logaddexp`, `erfinv`, `degrees`/`radians`, `divmod`,
`floor_divide`, `stop_gradient`, `mlx_copy`, `mlx_bitcast`, `full`/`ones`/`*_like`, `mlx_round`, `mlx_sign`.
Sub-phases 1a (calibrate, freeze) and 1b (judge).
Exit: no `pending 1` line; `unit_ops` passes on both devices; tolerances frozen in Progress before 1b.

## Progress

(One entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was
met, frozen numbers, log paths, decisions taken under delegation, what it means in short.)

*Before launch, 2026-11-23 (Claude, on Hans's ruling).* `mlx_take` (Phase 3) and `mlx_bitcast` (decision 6)
entered the library early, with milestone 1's decision 26, for the shift maps. They follow this plan's
conventions: decision 6's name, and decision 8's one-based, unchecked indices. Phase 0's ledger lists both as
`public`; Phases 1 and 3 have nothing left to do for them.

### Phase 0, the ledger, rule `parity` and the probes: 2026-11-23 (interactive, Claude; decision 23) - complete

- *Machine and base.* The M2 Ultra through the build bridge, for the probes only. Working tree on `c93ee0d`
  with Codex's Phase 5c edits in progress (milestone plan, fusing note, history). Phase 0 touched none of them.
  MLX 0.32.4, mlx-c 0.8.0 (Homebrew), headers also read from the `v0.8.0` clone (`a26f2d5`).
- *Files.* `scripts/mlxc_parity.txt` (new), `scripts/check_rules.py` (rule `parity`), `scripts/check_tree.sh`
  (rule list), `.github/skills/mlxf-binding/SKILL.md` (section 1), `CLAUDE.md` (the growth sentence),
  `doc/architecture_principles.md` (section 4), this plan (decision 23, Progress). No Fortran file.
- *The ledger.* 680 lines, one per prototype: 60 `public`, 46 `plumbing`, 147 `internal`, 88 `excluded`,
  339 `pending`. Pending lines by phase: 1: 65, 2: 111, 3: 35, 4: 40, 5: 29, 6: 16, 7: 9, 8: 34.
  `PARITY_PENDING = 339`. The excluded reasons are decision 2 (8 quantised and fp8 functions), CUDA (14),
  `detail_` (6, vmap among them), vmap closures (6), keyword-argument closures and exports (9), reader/writer
  vtables (12), float16/bfloat16 and unsigned scalars (12), GGUF metadata (9), thread-local and
  thread-unsafe streams (6), stream registry management (2), custom distributed backends (2), metallib paths (2).
- *Rule `parity`.* It compares the ledger with the headers it finds (MLXC_ROOT, `.deps/install`, Homebrew)
  or the build's `build/gen/mlxc_prototypes.txt`. Checks: classes, a public name in `mlxf.f90`'s public
  block (the type for `T%b`), public/plumbing exactly when the library calls the function, pending lines
  only in phases Progress has not closed, and the pending ratchet. Seven plants on a scratch copy, each
  failing with its own message and the restored copy passing: a missing name, an extra name, a public name
  not exported, a pending line in a closed phase, a grown pending count, a called function classed
  `internal`, and a `plumbing` function the library does not call. `scripts/check_tree.sh` passes on the
  working tree, against the build's list and against the `v0.8.0` headers.
  Decision 24's version handling was tested on copies of the `v0.8.0` headers with one added prototype. In
  a Cellar-style `mlx-c/0.9.0` path it gives a warning and passes. In `mlx-c/0.7.0` it fails as older than the
  minimum. In a path that names no release, the build's 0.8.0 record applies and the difference fails.
- *Decision 1 applied.* The skill's section 1, `CLAUDE.md` and the register's section 4 say the ledger is the
  need for its pending functions; outside it, no need, no wrapper. `check_guide_imports.py` passes.
- *Probes* (`scripts/probes/mlx_behaviour_probe.c`, C against Homebrew's mlx-c, both streams; bridge jobs
  `20261123-141715` and `20261123-142501`, `-Wall` clean; its header has the build line):
  - `remainder` takes the divisor's sign on both devices, float32 and int32: `[-7, 7, -7, 7] % [3, -3, -3, 3] =
    [2, -2, -1, 1]`. That is Fortran's `modulo`, so decision 6's name holds.
  - `round` rounds half to even: `[.5, 1.5, 2.5, -.5, -1.5] -> [0, 2, 2, -0, -2]`. `mlx_round` holds;
    `anint` would differ.
  - `vecdot` conjugates its first operand (`[i]·[i] = 1`); `inner` does not (`-1`). So `vecdot` along one
    dimension is Fortran's `dot_product`. *Finding for Phase 4:* rank-1 `dot_product(a, b)` can map to
    `mlx_vecdot` under decision 6's rule, with `mlx_vecdot(a, b, dim)` for the batched form. The ledger keeps
    `mlx_vecdot` until Phase 4 decides.
  - `argsort` is stable on both devices: `[1,0,1,0,1,0] -> [1,3,5,0,2,4]`, and 4,096 alternating ties stay in
    order. Larger sizes are not probed; Phase 2 tests stability at its own sizes before the policy claims it.
  - `searchsorted` sides are NumPy's: left `[0,1,4]`, right `[0,3,4]` for `[1,2,2,3]` and `[0,2,4]`. Plus 1
    gives decision 8's positions 1 to n+1.
  - *Linear algebra on the GPU stream:* every `linalg` function probed refuses it ("not yet supported on the
    GPU. Explicitly pass a CPU stream"): inv, pinv, cholesky, cholesky_inv, tri_inv, qr, eigh, eigvalsh, eig,
    eigvals, lu, lu_factor, solve, solve_triangular, det, slogdet, svd. `norm_l2` runs on the GPU;
    `norm`, `norm_matrix` and `cross` were not probed. All run on the CPU stream. Decision 9's CPU-stream rule
    therefore covers every factorisation and solve; Phase 4 probes the three left before it relies on them.
  - `mlx_distributed_init(strict=false, no backend)` gives a singleton group, size 1, rank 0, and
    `mlx_distributed_is_available(NULL)` is true. Decision 18's gated test of the singleton group holds.
- *Not done here (decision 23):* the base build and gate measurements move to Phase 1.
- *History.* The entry is left to Hans's next history edit: Codex is editing `doc/history/2026-11.md` for
  Phase 5c, and two writers on one file would race. The text: "Parity Phase 0 (Claude, interactive): ledger of
  680 mlx-c functions with rule `parity` (7 plants), decision 1 applied to the skill, `CLAUDE.md` and the
  register; probes: modulo, half-to-even, vecdot conjugates, stable argsort, NumPy searchsorted, linalg
  CPU-only except norm, singleton distributed group."
- *What it means, in short:* the parity plan now has a checked inventory. Every later phase is measured by
  pending lines going to zero under a gate, and the probes settled the open semantic questions of decisions 6,
  8, 9 and 18 before any wrapper is written.

### Phase 1, the base measurements: 2026-11-23 15:54 EST (run mlxf_parity, Claude)

- *Machine and base.* FWM-S116118, the M2 Ultra (24 cores, 192 GB, macOS 26.7.3), Homebrew GFortran 16.2.0
  (`gfortran-16`), CMake 4.2.1, Homebrew MLX 0.32.4 and mlx-c 0.8.0. HEAD `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47`;
  launch `git status --short`: ` M doc/history/2026-11.md`, ` M doc/implementation_notes/planned/mlxf_mlxc_parity.md`,
  ` M src/core/array/mlxf_array.f90`, ` M src/core/array/mlxf_array_tester.f90`, the four launch edits of
  ruling R2 (decision 25 and the file table here, Codex's history entry, a one-line use-block alignment in the
  two array files). The run keeps them and builds on them.
- *Builds (ruling R1).* The plan's `compile_debug.sh` and `compile_clean.sh` are replaced by hand-configured
  trees with the same options: `cmake -S <src> -B <tree> -DCMAKE_BUILD_TYPE=<type> -DBUILD_TESTS=ON
  -DFORTLS=OFF -DMLXF_WERROR=ON -DCMAKE_INSTALL_PREFIX=<tree>`, `cmake --build <tree> -j 12`,
  `scripts/run_fast_gate.sh <tree>`, install. The base is `git archive HEAD` in
  `scratch/keep/base_src`; four trees from scratch, serial, nothing else of the run's running
  (`scratch/scripts/base_measure.sh`, log `scratch/logs/base_measure.log`, per-step logs
  `scratch/keep/base_meas/`; paths under `/Users/elmlundho/agent_work/arun/mlxf_parity`). Zero warnings in all
  four builds. The first `unit_core` reports `GPU devices: 1`.
- *Release clean build, configure plus build, wall:* 13.14 s (3.94 + 9.21; load 3.3 before, 4.5 after) and
  16.06 s (6.20 + 9.86; load 15.5 before, 17.6 after: the one-minute average still carried the preceding
  gate and kernel runs of the script). Debug: 8.89 s and 8.91 s.
- *Fast gate, per entry (s), Release run 1 / run 2:* unit_array 10.97 / 12.27, unit_kernels 8.49 / 5.18,
  unit_compile 0.99 / 0.30, object_contracts 0.90 / 0.75, unit_ops 0.57 / 0.30, unit_core 0.49 / 0.38,
  unit_linalg 0.33 / 0.24, unit_fft 0.33 / 0.27; total real time 11.0 / 12.3 s (budget 60 s). Debug totals
  11.1 / 14.7 s.
- *Assertion counts, both devices in one process (all four builds alike):* unit_core 82, unit_array 128,
  unit_ops 389, unit_linalg 32, unit_fft 57, unit_compile 63, unit_kernels 1539; object_contracts passes.
  unit_core gave 80 once (Release run 1): its registry sub-suite adds two checks only when the allocator
  reuses a freed address (35 or 37 checks), a property of the base, not of the run. Per device (Release run 2,
  `device=cpu` / `device=gpu`, device-independent checks counted in each): core 55 / 55, array 70 / 69,
  ops 246 / 143, linalg 17 / 15, fft 29 / 28, compile 32 / 32, kernels 781 / 765.
- *Frozen bounds (section 6), from these numbers:* Release clean build (configure plus build, from scratch,
  `-j 12`) at most **29.2 s**, twice the mean 14.6 s of the two runs. Fast gate total real time in Release
  at most **41.7 s**, the mean 11.65 s plus 30 s. A new area at most 3 s in Release.

### Phase 1a, the elementwise calibration: 2026-11-23 16:09 EST (run mlxf_parity, Claude)

- *How.* `mlxf_ops_math_tester` (the unary and binary families) built in Debug with its seed list held to the
  calibration seed alone, run as `mlxf_test_exec test=unit_ops suite=ops_math device=cpu` (log
  `scratch/logs/phase1a_calibration_cpu_seed1.log`, table `scratch/keep/phase1a_errors.txt` and
  `scratch/keep/phase1a_frozen.txt`). 1,024 points per function from its domain, rounded once to float32; error
  relative to `max(1, |reference|)` against plain Fortran real64 oracles. No GPU run and no seed 2 or 3 before
  this entry. The integer, predicate and constructor families are exact and need no calibration.
- *Observed on seed 1, CPU (float32 / float64), in float32 epsilons (2^-23):* every function at most 3.2 eps32
  in float32, so none reaches the 64 eps ceiling and there is no finding. Largest: `erf` 3.19, `tan` 1.31,
  `mlx_erfinv` 1.28, `asin` 1.25, `asinh` 1.15, `mlx_log2` 1.14, `mlx_log1p` 1.10, `acos` 1.03, `mlx_rsqrt` 1.01;
  the rest below 1. Exact (0): `abs`, `floor`, `ceiling`, `aint`, `mlx_round`, `mlx_sign`, `mlx_stop_gradient`,
  `mlx_copy`, unary `+`, `min`, `mlx_floor_divide`, `mlx_divmod` (both results). In float64 every function is
  within 2 eps64 except six that MLX 0.32.4 computes in float32 on the CPU: `sin` 0.45, `cos` 0.46, `erf` 3.19,
  `mlx_sigmoid` 0.17, `mlx_erfinv` 1.28 and `mlx_logaddexp` 0.23 eps32.
- *Frozen* in `src/test/mlxf_test_defs.f90` (`ELEM_TOLERANCES`), `max(2 x observed, 4 eps)` of the result kind:
  float32 `erf` 7.614142292e-07, every other function the floor 4 eps32 = 4.768371582e-07; float64 the floor
  4 eps64 = 8.881784197e-16, except the six float32-computed functions, held to the float32 bound: `erf`
  7.614142292e-07, `sin`, `cos`, `mlx_sigmoid`, `mlx_erfinv`, `mlx_logaddexp` 4.768371582e-07. The same
  float32 tolerances judge the GPU in 1b.
- *The stop, and ruling R4 (Hans, 2026-11-23, received 22:46 EST).* The run's phase note had 1a calibrate on
  the CPU only; section 6 says seed 1 on both devices. 1b (16:12 EST, `scratch/logs/phase1b_unit_ops_debug.log`)
  then failed GPU `erf` (6.331 / 6.512 / 6.501 eps32 on seeds 1 / 2 / 3 against the frozen 6.387) and GPU
  `mlx_expm1` (168.2 eps32 on every seed), and the run stopped (16:15). R4: freeze by section 6 over both
  devices; keep `mlx_expm1` with its GPU defect documented and a separate named bound. **The GPU seed-1
  values below were observed before R4, in the same run that already showed seeds 2 and 3.**
- *Re-frozen under R4 (22:50 EST), `max(2 x the larger of the CPU and GPU seed-1 errors, 4 eps)`:* only `erf`
  changes, float32 **1.509527616e-06** (12.66 eps32, from GPU 7.547638081e-07); its float64 bound stays
  7.614142292e-07. Every other function's GPU seed-1 error is below 2 eps32 (largest `acos` 1.48, `cosh` 1.28,
  `mlx_log1p` 1.28), so its floor stands. `mlx_expm1` keeps its section 6 float32 tolerance on the CPU (the
  floor); its GPU float32 results are held to `ELEM_GPU_EXPM1` = **4.010555858e-05** (336.4 eps32), twice the
  GPU's seed-1 maximum 2.005277929e-05 (same log; the 1a log holds the CPU only). Question 20 of
  `doc/collaboration/apple_questions.md`, with `scripts/probes/expm1_gpu_probe.c`, reports the defect: the GPU
  error grows from about 20 eps32 at x = 0.5 to 168 at x = 9.9 while GPU `exp` stays below 1.
- *Re-judged (22:52 EST, Debug, both devices, seeds 1 to 3):* `unit_ops` 1,532 of 1,532
  (`scratch/logs/phase1b_rejudge_unit_ops_debug.log`): GPU `erf` 6.51 eps32 at most, GPU `mlx_expm1` 168.23.

### Phase 1, elementwise: 2026-11-23 (run mlxf_parity) - complete

- *Machine and base.* FWM-S116118, the M2 Ultra; HEAD `4706ecb` plus the launch edits of R2 (see the base
  measurements entry). Rulings applied: R1 (hand-configured build trees), R2 (launch edits), R3 (the timings
  are re-judged at the end of Phase 3; the numbers here are context), R4 (calibration on both devices, GPU
  `expm1`).
- *Files.* `src/defs/mlxf_defs.f90` (`mlxf_close_spec`, `mlxf_nan_spec`, `mlxf_shape_spec`);
  `src/core/array/mlxf_array.f90` and `mlxf_array_operations.f90` (six signature helpers, `mlxf_close_op`,
  `mlxf_compare_op`, `mlxf_nan_op`, `mlxf_binary_vector_op`, `mlxf_full_op`, `mlxf_binary_int_op`, and the
  type-bound `**`, `.eqv.`, `.neqv.`, unary `+`); `src/core/ops/mlxf_ops.f90` and the new submodules
  `mlxf_ops_math.f90`, `mlxf_ops_logic.f90`, `mlxf_ops_create.f90` with their testers; `src/core/mlxf.f90`;
  `src/test/mlxf_test_defs.f90` (`ELEM_*`), `src/test/mlxf_test_registry.f90` (rows `ops_math`, `ops_logic`,
  `ops_create` of area `ops`); `scripts/mlxc_parity.txt`, `scripts/check_rules.py` (`PARITY_PENDING` 274,
  `ENTRY_HELPERS`); `scripts/probes/expm1_gpu_probe.c` (new, R4); `doc/policies/binding_contract_policy.md`
  (sections 1, 5, 10); `README.md` (API table); `doc/collaboration/apple_questions.md` (question 20);
  `doc/history/2026-11.md`; this plan (file-table rows for `mlxf_array_tester.f90` and the probe, Progress).
- *Exit items.*
  - No `pending 1` line: all 65 are `public`; 274 pending lines remain, `PARITY_PENDING = 274`, rule `parity`
    passes.
  - Debug and Release from scratch, `-DMLXF_WERROR=ON`, zero warnings
    (`scratch/logs/final/build_{Debug,Release}.log`; driver log `scratch/logs/final_builds.log`). A first
    attempt failed in Release on `-Wfunction-elimination` (an impure call inside `.and.` in the math
    tester; `scratch/logs/final_attempt1/`); fixed with nested `if`s, then both rebuilt from scratch.
  - Fast gate passes in both (8 of 8 entries). Release total 10.4 s (unit_ops 0.66 s), configure plus build
    13.28 s, load 6.4 before and 8.6 after; Debug total 11.6 s. Within the Phase 1 bounds (29.2 s, 41.7 s);
    by R3 the bounds are judged again at the end of Phase 3.
  - `unit_ops` on both devices in both builds: 1,532 checks pass with both devices (948 with `device=cpu`, 585
    with `device=gpu`). That is the existing `ops` suite's 389, unchanged, plus `ops_math` 825, `ops_logic`
    217 and `ops_create` 101.
  - Existing areas unchanged in both builds (`scratch/logs/final/area_*`): core 82 (80 when the allocator
    reuses no freed address, as at the base), array 128, linalg 32, fft 57, compile 63, kernels 1539;
    object_contracts passes in the gate. `scripts/check_tree.sh` passes.
- *Frozen tolerances:* entry "Phase 1a, the elementwise calibration" (16:09 EST), re-frozen under R4 (22:50 EST):
  float32 `erf` 1.509527616e-06, every other function 4 eps32; float64 4 eps64 except the six float32-computed
  functions (`erf` 7.614142292e-07, `sin`, `cos`, `mlx_sigmoid`, `mlx_erfinv`, `mlx_logaddexp` 4 eps32); GPU
  `mlx_expm1` `ELEM_GPU_EXPM1` = 4.010555858e-05. Upstream-defect lines this phase: 1 (`expm1`, kept under R4).
- *Decisions under delegation.*
  - Layout: the new wrappers live in three submodules of `mlxf_ops`, `math` (unary and binary
    mathematics, `mlx_round`, `mlx_clip`, `mlx_nan_to_num`, `mlx_divmod`, `mlx_copy`, `mlx_stop_gradient`),
    `logic` (predicates, closeness, integers and bits) and `create` (constructors). The operators' bodies
    live in `mlxf_array_operations`, because `mlxf_array_elementwise` is outside the file table. Each
    submodule has a tester with one table per family (unary, binary, predicates, integers, constructors) and
    convention checks by name.
  - Scalars: the binary family and `mlx_clip` take real32 and real64 scalars on either side, as the
    operators do; no integer scalar for them, as for the operators (`a**2.0`, not `a**2`). The bitwise
    family takes a default integer, converted to the array's integer kind: on either side for `iand`, `ior`
    and `ieor`, as the shift for `shiftl` and `mlx_right_shift`.
  - Forms: `mlx_divmod` is a subroutine with two `intent(out)` results. `mlx_full` and `mlx_full_like` take an
    array or a real32, real64 or integer fill; a scalar fill is float32 or int32 unless `dtype` is given (a
    real64 value never makes float64 by itself). `mlx_nan_to_num` takes real32 replacements (C's `float`).
  - `mlxf_array.f90` imports `c_float` renamed as `c_float_kind`, because its submodule
    `mlxf_array_elementwise` imports `c_float` itself and gfortran refuses the clash.
  - The launch edit's aligned intrinsic `use` line (R2) fails `format_use_blocks.py --check`. The static gate
    is not waivable, so the formatter's form was restored in `mlxf_array.f90` and in `mlxf_array_tester.f90`,
    which is now equal to HEAD. A Phase 1 file-table row was added first.
- *What it means, in short:* Fortran users have MLX's elementwise API under Fortran names, with Fortran's
  argument order and sign conventions, on both devices. The tests found one MLX accuracy defect (GPU `expm1`),
  now documented and reported. Two thirds of the run's ledger lines remain for Phases 2 and 3.
