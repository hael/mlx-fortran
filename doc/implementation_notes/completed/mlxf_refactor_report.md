# Report: refactoring of the library and of the test tree (run `mlxf_refactor`)

Plan: [`mlxf_refactor.md`](../planned/mlxf_refactor.md) (its Progress section holds the detail, the numbers and
their logs). The roadmap's rank 2d. Run on the M5 Ultra, 2026-11-26, in a copy of the checkout at `96c5c5c`,
nothing committed; Phases 0 to 7 all DONE. One ruling (R1). The diffs per phase are in the run's review
directory, `/Users/hael/agent_runs/mlxf_refactor/review/phase_N.diff` (N = 0 to 7; `full_after_N.diff` is the
tree against the base after phase N); logs under `/Users/hael/agent_runs/mlxf_refactor/scratch/keep/phaseN/`.

## 1. The outcome

An identical change: no public name of `mlxf` changed (315, compiled against the installed module at the end of
Phases 0, 2, 3, 4, 5, 6 and 7), and no result: every unit area keeps Phase 0's count (array 193, ops 2,462,
linalg 632, fft 194, compile 63, transforms 274, fast 152, random 486, io 846, distributed 55, kernels 1,955;
core 214 plus one per device on which the registry test saw its freed address reused, 214 to 216 in every run),
the 14 identity invocations of the toys (38 digest lines, 4 history lines, 4 maps' SHA-256, the 135-line
`polarft_host` table, `seam`) equal the base's byte for byte after Phases 3, 4, 5, 6 and 7, and the off-state
table equals the base's. The Release clean build: 19.0 s at the base (two runs), 18.8 s at the end (*measured*,
the bound 26.1 s). Zero warnings in Debug and Release in every phase; the release gate passes.

| | Base | End |
| --- | --- | --- |
| `mlxf_array.f90` | 2,946 lines | 598 lines |
| `mlxf_ops.f90` | 1,573 lines, one module, 8 submodules | gone: 8 modules `mlxf_ops_<concern>`, the largest 862 lines |
| `mlxf_array_operations.f90` | 2,410 lines, 84 signature helpers | gone: every helper with its users |
| hand-written C signature classes | 98 abstract interfaces | 0: generated from `scripts/mlxc_signatures.txt` |
| largest library file | 2,946 lines | 982 (`mlxf_transfer_copy.f90`), rule `size` at 1,000 |
| `.inf` with `!@descr:` | 7 of 17 | 28 of 28 (every source directory), checked |
| code-base map | none | `doc/code_base_map.md`, generated and checked in the static gate |
| `src/test/` | 60 files at its top | 4 folders (and 3 toy folders), nothing at its top |

## 2. What changed, phase by phase

| Phase | What | Diff |
| --- | --- | --- |
| 0 | The base measured (counts, digests, two clean builds); `scripts/list_public_api.py` and `test/consumer/mlxf_api_names.f90` (315 names) compiled by `scripts/check_install.sh`; the helper table and the generics table | `phase_0.diff` |
| 1 | `!@descr:` on every `.inf`, four new ones; `scripts/check_descr.py` checks them; `scripts/generate_codeoverview.py` from XEMA writes `doc/code_base_map.md`, its `--check` in `scripts/check_tree.sh` | `phase_1.diff` |
| 2 | `scripts/restyle_fortran.py`: a blank line between interface bodies (applied, 9 files); rule `publist` with its ledger; `mlxf.f90`'s public block packed | `phase_2.diff` |
| 3 | `src/test/` in `framework/`, `oracles/`, `toys/{,polar,projector,recon}/`, `bench/` (59 moves); every path that named a moved file | `phase_3.diff` |
| 4 | `mlxf_ops` split into eight modules (`mlxf_ops_shape` with the submodule `mlxf_ops_shape_calls`); 47 one-family helpers moved into them; `mlx_slice` defined in `mlxf_ops_shape` | `phase_4.diff` |
| 5 | `mlxf_c_signatures` generated from the ledger; `mlxf_calls` (submodules `_elementwise`, `_shaped`, `_checks`) for the shared helpers; the one-family helpers in `mlxf_fft`, `mlxf_linalg`, `mlxf_linalg_matrix`, `mlxf_conv`; `mlxf_transfer` (submodules `mlxf_transfer_copy`, `_borrow`); the random, fast, io and distributed submodules in their families; `adopt` -> `mlxf_adopt`; rule `size` | `phase_5.diff` |
| 6 | `doc/how2s/how2replace_blas.md`; the bench `bench_blas` (`src/test/bench/mlxf_bench_blas.f90`), Accelerate linked to the test executable on macOS | `phase_6.diff` |
| 7 | The last-phase gates; the module map in the compile-time policy, the tree in the test policy, the roadmap, the index, the history, `README.md`; the map generator fixed for an exported tree; this report | `phase_7.diff` |

**Modules made**: `mlxf_ops_elementwise`, `mlxf_ops_math`, `mlxf_ops_logic`, `mlxf_ops_shape`, `mlxf_ops_index`,
`mlxf_ops_reduce`, `mlxf_ops_create`, `mlxf_ops_sort` (the former submodules of `mlxf_ops`, made modules in their
own files); `mlxf_calls`; `mlxf_transfer`; the generated `mlxf_c_signatures`. **Submodules made or re-parented**:
`mlxf_ops_shape_calls`, `mlxf_calls_elementwise`, `mlxf_calls_shaped`, `mlxf_calls_checks`, `mlxf_transfer_copy`,
`mlxf_transfer_borrow`, `mlxf_random_calls`, `mlxf_fast_calls`, `mlxf_io_calls`, `mlxf_distributed_calls`.

**Every helper's home** (Phase 0's 117 names public from `mlxf_array`; Progress, Phases 4 and 5, names each):
47 in the `mlxf_ops_*` modules (shape 19, index 8, reduce 8, create 8, logic 2, math 2); 28 in `mlxf_fft` (3),
`mlxf_linalg` (7), `mlxf_linalg_matrix` (11), `mlxf_conv` (7); 22 in the family submodules (random 11, fast 5, io
3, distributed 3); 17 in `mlxf_calls`; `mlxf_handle`, `mlxf_vector_import`, `mlxf_vector_export` stay with the type.

**Deleted**: `src/core/ops/mlxf_ops.f90` (split), `src/core/array/mlxf_array_operations.f90` (emptied by the
moves); one second copy, `mlxf_io`'s wrapper `mlxf_cpu_stream` of the private `cpu_stream` (the procedure itself
is now `mlxf_cpu_stream` in `mlxf_calls`). No private procedure was reported unused by the compiler.

**Library-internal renames** (none is a name of `mlxf`): `adopt` -> `mlxf_adopt`, `check_dim` -> `mlxf_check_dim`,
`slice_bounds` -> `mlxf_slice_bounds`, `cpu_stream` -> `mlxf_cpu_stream`, `optional_handle` ->
`mlxf_optional_handle`, `vector_of` -> `mlxf_vector_of`; new: `mlxf_is_empty`.

## 3. The BLAS question

`mlxf_linalg`, `mlxf_linalg_matrix` and `mlxf_conv` wrap every product, `linalg_*` and convolution function of
mlx-c 0.8.0: everything MLX has. `doc/how2s/how2replace_blas.md` maps the 19 BLAS and LAPACK routines SIMPLE calls
to `mlxf` calls, each with its wrapper and test. MLX has no float64 and no factorisation on the GPU. The crossover
(*measured*, one run, load 3.65): a single `sgemm` is faster on the GPU from n = 1,024 with the operands resident,
2,048 with the transfer from and to Fortran arrays; `cgemm` from 512; SIMPLE's polar block product (183 products
of 16 x 32 x 122), batched in one `matmul`, is 5.3 times faster than its loop of `cgemm` calls (3.9 with transfer).
A BLAS-shaped `mlx_gemm` was not added: the decision is the maintainer's (section 6).

## 4. Decisions taken under delegation

Each is recorded, with its reason, in the plan's Progress under its phase.

- **Phase 0**: the identity cases are the run's own, modelled on the toy-seam run's eleven, with a shift-map grid
  written to sit on case `1000_1`; `unit_core`'s count is 214 plus the reuse lines (the allocator decides two
  checks); the API program is compiled by `check_install.sh` directly; Accelerate for the bench.
- **Phase 1**: the `.inf` rule reaches the map's top directories and `doc/compiler_issues/`, not the root or
  `.claude/hooks/`; four descriptions found wrong were corrected; the map lists Fortran files only, as XEMA's.
- **Phase 2**: `mlxf.f90` packed as one public statement per source module; rule `publist` covers test code too;
  the skill sentence that forbids blank lines between interface bodies left for the maintainer (section 6).
- **Phase 3**: six documents gained the moved paths (added to the file table); `TOY_DIR` is `src/test/toys/`; the
  off-state project finds a toy's file by name; `CLAUDE.md`'s Structure line names the four folders.
- **Phase 4**: the moved helpers' dependencies stayed exported from `mlxf_array` for one phase; `mlxf_ops_shape`'s
  helpers in a submodule (1,220 lines together, *derived*); `axis_of`, `axes_of` public from `mlxf_ops_shape`.
- **Phase 5**: `mlxf_is_empty` (pure) in place of decision 5's `mlx_is_live`, which would have let a stale operand
  pass as absent; submodules named `<module>_<part>` (the transfer and borrow files renamed); `mlxf_calls` as a
  module with three submodules; the `mlxf_` prefix on the six internal procedures made public; `src/CMakeLists.txt`
  and `mlxf_array_tester.f90` added to the file table.
- **Phase 6**: CBLAS through `bind(c)` interfaces in the bench (a Fortran `sgemm` interface has 13 arguments);
  Accelerate on macOS only; SIMPLE's polar block shape restated in `mlxf_test_defs`; one run of the bench.
- **Phase 7**: the map generator fixed under the gate it failed; the plan stays in `planned/` until read.
- **Ruling R1** (the maintainer, after the fence refused the map in Phase 6): `doc/code_base_map.md`'s file-table
  row lists Phases 1, 3, 4, 5, 6 and 7; Phase 6 stands. Recorded in Phase 6's Progress.

## 5. Deviations from the plan

- **Counts** the plan estimated and the run measured: 88 helpers in `mlxf_array_operations.f90`, not 95 (84
  signature helpers and four checks); 10 oracle modules and a tester, not 13; SIMPLE's BLAS call sites counted as
  call statements (19 routines, `dcopy` 19, `ddot` 14, `sgemm` 11, ...), smaller than section 2's text search.
- **File table**: rows added for the six documents of Phase 3, `src/CMakeLists.txt` and the array tester (Phase 5),
  `test/CMakeLists.txt` (Phase 6), `scripts/generate_codeoverview.py` (Phase 7), the new submodule names (Phase 5),
  `scripts/check_rules.py` gained Phase 4; R1 for the map.
- **Gates not run in a phase**: Phases 1 and 2 did not repeat the identity invocations (they changed no code the
  toys run: descriptions, blank lines, a regrouped public statement) and Phase 1 did not run `check_install.sh`
  (no Fortran changed); every later phase ran both.
- **A defect found at the end**: `generate_codeoverview.py` mapped an exported tree inside the checkout as empty
  (the release gate's first run); fixed in Phase 7.
- **One failed run per phase where it happened**: Phase 5's first full run stopped at the Release build
  (`-Wfunction-elimination` on the impure `mlxf_is_empty`, made `pure`); Phase 6's first Accelerate link added a
  C-only `-F` flag (linked as `-framework Accelerate`). Both reran from scratch.

## 6. Left open for the maintainer

1. **A BLAS-shaped `mlx_gemm`** (decision 12, reserved), from section 3 and the table.
2. **Skill and `CLAUDE.md` text beyond paths** (decision 14), proposed, not applied:
   - `mlxf-modern-fortran/SKILL.md`, Layout: "Do not insert procedure separators between interface bodies"
     becomes "Separate the bodies of an interface block with one blank line (the formatter adds it)"; Modules:
     "`mlxf_array`: lifetime, transfer, borrow, evaluation, elementwise" becomes "`mlxf_array`: lifetime,
     evaluation, elementwise, closure; `mlxf_transfer`: copy, borrow".
   - `mlxf-binding/SKILL.md`, section 3: a new C signature class is a line of `scripts/mlxc_signatures.txt` (its
     abstract interface is generated into `mlxf_c_signatures`), and its helper lives in the family that calls it,
     or in `mlxf_calls` when two families do; "the abstract interface is `bind(c)` with the generated intents"
     is then true by construction.
   - `CLAUDE.md`, Structure: `array/` holds "`mlxf_array` (the type: lifetime, evaluation, operators, closure
     vectors), `mlxf_transfer` (data movement), `mlxf_calls` (the shared signature helpers)"; `ops/` "one module per
     concern"; and one line: "`doc/code_base_map.md` maps every directory and Fortran file
     (`scripts/generate_codeoverview.py`)" (decision 10).
3. **The map of the scripts**: listing `scripts/` files by their `name -- text` header lines would make the map
   cover them; not done (Phase 1).
4. **XEMA's `generate_codeoverview.py`** has the blind spot fixed here in Phase 7, if any of its gates checks an
   export inside its checkout.
5. **The commit**: the moves below replay with `git mv` to keep the files' history; then the plan moves to
   `completed/`.

## 7. Every move (old path -> new path)

- `src/test/mlxf_abi_probe.c` -> `src/test/framework/mlxf_abi_probe.c`
- `src/test/mlxf_abi_probe.h` -> `src/test/framework/mlxf_abi_probe.h`
- `src/test/mlxf_abi_tester.f90` -> `src/test/framework/mlxf_abi_tester.f90`
- `src/test/mlxf_bench_insert_probe.f90` -> `src/test/bench/mlxf_bench_insert_probe.f90`
- `src/test/mlxf_bench_polar_table.f90` -> `src/test/bench/mlxf_bench_polar_table.f90`
- `src/test/mlxf_bench_projector.f90` -> `src/test/bench/mlxf_bench_projector.f90`
- `src/test/mlxf_bench_recon_pcg.f90` -> `src/test/bench/mlxf_bench_recon_pcg.f90`
- `src/test/mlxf_oracle_dft.f90` -> `src/test/oracles/mlxf_oracle_dft.f90`
- `src/test/mlxf_oracle_gridding.f90` -> `src/test/oracles/mlxf_oracle_gridding.f90`
- `src/test/mlxf_oracle_pcg.f90` -> `src/test/oracles/mlxf_oracle_pcg.f90`
- `src/test/mlxf_oracle_polar_objfun.f90` -> `src/test/oracles/mlxf_oracle_polar_objfun.f90`
- `src/test/mlxf_oracle_polar_shiftmap.f90` -> `src/test/oracles/mlxf_oracle_polar_shiftmap.f90`
- `src/test/mlxf_oracle_polar.f90` -> `src/test/oracles/mlxf_oracle_polar.f90`
- `src/test/mlxf_oracle_pose.f90` -> `src/test/oracles/mlxf_oracle_pose.f90`
- `src/test/mlxf_oracle_projection_tester.f90` -> `src/test/oracles/mlxf_oracle_projection_tester.f90`
- `src/test/mlxf_oracle_projection.f90` -> `src/test/oracles/mlxf_oracle_projection.f90`
- `src/test/mlxf_oracle_recon_fixture.f90` -> `src/test/oracles/mlxf_oracle_recon_fixture.f90`
- `src/test/mlxf_oracle_recon_pcg.f90` -> `src/test/oracles/mlxf_oracle_recon_pcg.f90`
- `src/test/mlxf_polarft_host_fixture.f90` -> `src/test/toys/polar/mlxf_polarft_host_fixture.f90`
- `src/test/mlxf_test_defs.f90` -> `src/test/framework/mlxf_test_defs.f90`
- `src/test/mlxf_test_reduce.f90` -> `src/test/framework/mlxf_test_reduce.f90`
- `src/test/mlxf_test_registry.f90` -> `src/test/framework/mlxf_test_registry.f90`
- `src/test/mlxf_test_utils.f90` -> `src/test/framework/mlxf_test_utils.f90`
- `src/test/mlxf_toy_device_work.f90` -> `src/test/toys/mlxf_toy_device_work.f90`
- `src/test/mlxf_toy_eul_prob_tab_tester.f90` -> `src/test/toys/polar/mlxf_toy_eul_prob_tab_tester.f90`
- `src/test/mlxf_toy_eul_prob_tab.f90` -> `src/test/toys/polar/mlxf_toy_eul_prob_tab.f90`
- `src/test/mlxf_toy_pcg_solver_mlx.f90` -> `src/test/toys/recon/mlxf_toy_pcg_solver_mlx.f90`
- `src/test/mlxf_toy_pcg_solver_tester.f90` -> `src/test/toys/recon/mlxf_toy_pcg_solver_tester.f90`
- `src/test/mlxf_toy_pcg_solver.f90` -> `src/test/toys/recon/mlxf_toy_pcg_solver.f90`
- `src/test/mlxf_toy_polarft_block_mlx.f90` -> `src/test/toys/polar/mlxf_toy_polarft_block_mlx.f90`
- `src/test/mlxf_toy_polarft_block.f90` -> `src/test/toys/polar/mlxf_toy_polarft_block.f90`
- `src/test/mlxf_toy_polarft_calc_tester.f90` -> `src/test/toys/polar/mlxf_toy_polarft_calc_tester.f90`
- `src/test/mlxf_toy_polarft_calc.f90` -> `src/test/toys/polar/mlxf_toy_polarft_calc.f90`
- `src/test/mlxf_toy_polarft_core_mlx.f90` -> `src/test/toys/polar/mlxf_toy_polarft_core_mlx.f90`
- `src/test/mlxf_toy_polarft_core.f90` -> `src/test/toys/polar/mlxf_toy_polarft_core.f90`
- `src/test/mlxf_toy_polarft_host_tester.f90` -> `src/test/toys/polar/mlxf_toy_polarft_host_tester.f90`
- `src/test/mlxf_toy_polarft_memo_mlx.f90` -> `src/test/toys/polar/mlxf_toy_polarft_memo_mlx.f90`
- `src/test/mlxf_toy_polarft_memo.f90` -> `src/test/toys/polar/mlxf_toy_polarft_memo.f90`
- `src/test/mlxf_toy_polarft_shiftmap_mlx.f90` -> `src/test/toys/polar/mlxf_toy_polarft_shiftmap_mlx.f90`
- `src/test/mlxf_toy_polarft_shiftmap_tester.f90` -> `src/test/toys/polar/mlxf_toy_polarft_shiftmap_tester.f90`
- `src/test/mlxf_toy_polarft_shiftmap.f90` -> `src/test/toys/polar/mlxf_toy_polarft_shiftmap.f90`
- `src/test/mlxf_toy_polarft_tail_tester.f90` -> `src/test/toys/polar/mlxf_toy_polarft_tail_tester.f90`
- `src/test/mlxf_toy_polarft_workspace_lifecycle.f90` -> `src/test/toys/polar/mlxf_toy_polarft_workspace_lifecycle.f90`
- `src/test/mlxf_toy_polarft_workspace_score.f90` -> `src/test/toys/polar/mlxf_toy_polarft_workspace_score.f90`
- `src/test/mlxf_toy_polarft_workspace_shiftmap.f90` -> `src/test/toys/polar/mlxf_toy_polarft_workspace_shiftmap.f90`
- `src/test/mlxf_toy_polarft_workspace_tail.f90` -> `src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90`
- `src/test/mlxf_toy_polarft_workspace.f90` -> `src/test/toys/polar/mlxf_toy_polarft_workspace.f90`
- `src/test/mlxf_toy_projector_mlx.f90` -> `src/test/toys/projector/mlxf_toy_projector_mlx.f90`
- `src/test/mlxf_toy_projector_pft_batch_mlx.f90` -> `src/test/toys/projector/mlxf_toy_projector_pft_batch_mlx.f90`
- `src/test/mlxf_toy_projector_pft_batch.f90` -> `src/test/toys/projector/mlxf_toy_projector_pft_batch.f90`
- `src/test/mlxf_toy_projector_tester.f90` -> `src/test/toys/projector/mlxf_toy_projector_tester.f90`
- `src/test/mlxf_toy_projector_workspace.f90` -> `src/test/toys/projector/mlxf_toy_projector_workspace.f90`
- `src/test/mlxf_toy_projector.f90` -> `src/test/toys/projector/mlxf_toy_projector.f90`
- `src/test/mlxf_toy_reconstructor_pcg_mlx.f90` -> `src/test/toys/recon/mlxf_toy_reconstructor_pcg_mlx.f90`
- `src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90` -> `src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester_solve.f90`
- `src/test/mlxf_toy_reconstructor_pcg_tester.f90` -> `src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester.f90`
- `src/test/mlxf_toy_reconstructor_pcg_workspace.f90` -> `src/test/toys/recon/mlxf_toy_reconstructor_pcg_workspace.f90`
- `src/test/mlxf_toy_reconstructor_pcg.f90` -> `src/test/toys/recon/mlxf_toy_reconstructor_pcg.f90`
- `src/test/mlxf_toy_seam_tester.f90` -> `src/test/toys/mlxf_toy_seam_tester.f90`
- `src/core/array/mlxf_array_transfer.f90` -> `src/core/array/mlxf_transfer_copy.f90`
- `src/core/array/mlxf_array_borrow.f90` -> `src/core/array/mlxf_transfer_borrow.f90`
- `src/core/array/mlxf_array_random.f90` -> `src/core/random/mlxf_random_calls.f90`
- `src/core/array/mlxf_array_fast.f90` -> `src/core/fast/mlxf_fast_calls.f90`
- `src/core/array/mlxf_array_io.f90` -> `src/core/io/mlxf_io_calls.f90`
- `src/core/array/mlxf_array_distributed.f90` -> `src/core/distributed/mlxf_distributed_calls.f90`

## 8. The commit message

```
Refactor the library and the test tree (run mlxf_refactor, roadmap rank 2d)

Split mlxf_ops into eight modules by concern and mlxf_array into the type, mlxf_transfer and mlxf_calls;
generate the 98 C signature classes from scripts/mlxc_signatures.txt into mlxf_c_signatures; move every
signature helper to the modules that call it; check the interface layout, packed public blocks (rule
publist) and a 1,000-line limit per library file (rule size); describe every source directory in its .inf
and generate the code-base map (scripts/generate_codeoverview.py, checked in the static gate); compile the
public API list against the installed module in check_install.sh; sort src/test/ into framework/, oracles/,
toys/ and bench/; add the BLAS table and the crossover bench. No public name of mlxf and no result changed.

New files:
  doc/code_base_map.md
  doc/compiler_issues/compiler_issues.inf
  doc/how2s/how2replace_blas.md
  doc/implementation_notes/completed/mlxf_refactor_report.md
  scripts/generate_codeoverview.py
  scripts/list_public_api.py
  scripts/mlxc_signatures.txt
  scripts/probes/probes.inf
  scripts/scripts.inf
  src/core/array/mlxf_calls.f90
  src/core/array/mlxf_calls_checks.f90
  src/core/array/mlxf_calls_elementwise.f90
  src/core/array/mlxf_calls_shaped.f90
  src/core/array/mlxf_transfer.f90
  src/core/ops/mlxf_ops_shape_calls.f90
  src/src.inf
  src/test/bench/bench.inf
  src/test/bench/mlxf_bench_blas.f90
  src/test/framework/framework.inf
  src/test/oracles/oracles.inf
  src/test/toys/polar/polar.inf
  src/test/toys/projector/projector.inf
  src/test/toys/recon/recon.inf
  src/test/toys/toys.inf
  test/consumer/mlxf_api_names.f90

Deleted:
  src/core/ops/mlxf_ops.f90
  src/core/array/mlxf_array_operations.f90

Moved (old -> new):
  src/test/mlxf_abi_probe.c -> src/test/framework/mlxf_abi_probe.c
  src/test/mlxf_abi_probe.h -> src/test/framework/mlxf_abi_probe.h
  src/test/mlxf_abi_tester.f90 -> src/test/framework/mlxf_abi_tester.f90
  src/test/mlxf_bench_insert_probe.f90 -> src/test/bench/mlxf_bench_insert_probe.f90
  src/test/mlxf_bench_polar_table.f90 -> src/test/bench/mlxf_bench_polar_table.f90
  src/test/mlxf_bench_projector.f90 -> src/test/bench/mlxf_bench_projector.f90
  src/test/mlxf_bench_recon_pcg.f90 -> src/test/bench/mlxf_bench_recon_pcg.f90
  src/test/mlxf_oracle_dft.f90 -> src/test/oracles/mlxf_oracle_dft.f90
  src/test/mlxf_oracle_gridding.f90 -> src/test/oracles/mlxf_oracle_gridding.f90
  src/test/mlxf_oracle_pcg.f90 -> src/test/oracles/mlxf_oracle_pcg.f90
  src/test/mlxf_oracle_polar_objfun.f90 -> src/test/oracles/mlxf_oracle_polar_objfun.f90
  src/test/mlxf_oracle_polar_shiftmap.f90 -> src/test/oracles/mlxf_oracle_polar_shiftmap.f90
  src/test/mlxf_oracle_polar.f90 -> src/test/oracles/mlxf_oracle_polar.f90
  src/test/mlxf_oracle_pose.f90 -> src/test/oracles/mlxf_oracle_pose.f90
  src/test/mlxf_oracle_projection_tester.f90 -> src/test/oracles/mlxf_oracle_projection_tester.f90
  src/test/mlxf_oracle_projection.f90 -> src/test/oracles/mlxf_oracle_projection.f90
  src/test/mlxf_oracle_recon_fixture.f90 -> src/test/oracles/mlxf_oracle_recon_fixture.f90
  src/test/mlxf_oracle_recon_pcg.f90 -> src/test/oracles/mlxf_oracle_recon_pcg.f90
  src/test/mlxf_polarft_host_fixture.f90 -> src/test/toys/polar/mlxf_polarft_host_fixture.f90
  src/test/mlxf_test_defs.f90 -> src/test/framework/mlxf_test_defs.f90
  src/test/mlxf_test_reduce.f90 -> src/test/framework/mlxf_test_reduce.f90
  src/test/mlxf_test_registry.f90 -> src/test/framework/mlxf_test_registry.f90
  src/test/mlxf_test_utils.f90 -> src/test/framework/mlxf_test_utils.f90
  src/test/mlxf_toy_device_work.f90 -> src/test/toys/mlxf_toy_device_work.f90
  src/test/mlxf_toy_eul_prob_tab_tester.f90 -> src/test/toys/polar/mlxf_toy_eul_prob_tab_tester.f90
  src/test/mlxf_toy_eul_prob_tab.f90 -> src/test/toys/polar/mlxf_toy_eul_prob_tab.f90
  src/test/mlxf_toy_pcg_solver_mlx.f90 -> src/test/toys/recon/mlxf_toy_pcg_solver_mlx.f90
  src/test/mlxf_toy_pcg_solver_tester.f90 -> src/test/toys/recon/mlxf_toy_pcg_solver_tester.f90
  src/test/mlxf_toy_pcg_solver.f90 -> src/test/toys/recon/mlxf_toy_pcg_solver.f90
  src/test/mlxf_toy_polarft_block_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_block_mlx.f90
  src/test/mlxf_toy_polarft_block.f90 -> src/test/toys/polar/mlxf_toy_polarft_block.f90
  src/test/mlxf_toy_polarft_calc_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_calc_tester.f90
  src/test/mlxf_toy_polarft_calc.f90 -> src/test/toys/polar/mlxf_toy_polarft_calc.f90
  src/test/mlxf_toy_polarft_core_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_core_mlx.f90
  src/test/mlxf_toy_polarft_core.f90 -> src/test/toys/polar/mlxf_toy_polarft_core.f90
  src/test/mlxf_toy_polarft_host_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_host_tester.f90
  src/test/mlxf_toy_polarft_memo_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_memo_mlx.f90
  src/test/mlxf_toy_polarft_memo.f90 -> src/test/toys/polar/mlxf_toy_polarft_memo.f90
  src/test/mlxf_toy_polarft_shiftmap_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_shiftmap_mlx.f90
  src/test/mlxf_toy_polarft_shiftmap_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_shiftmap_tester.f90
  src/test/mlxf_toy_polarft_shiftmap.f90 -> src/test/toys/polar/mlxf_toy_polarft_shiftmap.f90
  src/test/mlxf_toy_polarft_tail_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_tail_tester.f90
  src/test/mlxf_toy_polarft_workspace_lifecycle.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_lifecycle.f90
  src/test/mlxf_toy_polarft_workspace_score.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_score.f90
  src/test/mlxf_toy_polarft_workspace_shiftmap.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_shiftmap.f90
  src/test/mlxf_toy_polarft_workspace_tail.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90
  src/test/mlxf_toy_polarft_workspace.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace.f90
  src/test/mlxf_toy_projector_mlx.f90 -> src/test/toys/projector/mlxf_toy_projector_mlx.f90
  src/test/mlxf_toy_projector_pft_batch_mlx.f90 -> src/test/toys/projector/mlxf_toy_projector_pft_batch_mlx.f90
  src/test/mlxf_toy_projector_pft_batch.f90 -> src/test/toys/projector/mlxf_toy_projector_pft_batch.f90
  src/test/mlxf_toy_projector_tester.f90 -> src/test/toys/projector/mlxf_toy_projector_tester.f90
  src/test/mlxf_toy_projector_workspace.f90 -> src/test/toys/projector/mlxf_toy_projector_workspace.f90
  src/test/mlxf_toy_projector.f90 -> src/test/toys/projector/mlxf_toy_projector.f90
  src/test/mlxf_toy_reconstructor_pcg_mlx.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_mlx.f90
  src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester_solve.f90
  src/test/mlxf_toy_reconstructor_pcg_tester.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester.f90
  src/test/mlxf_toy_reconstructor_pcg_workspace.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_workspace.f90
  src/test/mlxf_toy_reconstructor_pcg.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg.f90
  src/test/mlxf_toy_seam_tester.f90 -> src/test/toys/mlxf_toy_seam_tester.f90
  src/core/array/mlxf_array_transfer.f90 -> src/core/array/mlxf_transfer_copy.f90
  src/core/array/mlxf_array_borrow.f90 -> src/core/array/mlxf_transfer_borrow.f90
  src/core/array/mlxf_array_random.f90 -> src/core/random/mlxf_random_calls.f90
  src/core/array/mlxf_array_fast.f90 -> src/core/fast/mlxf_fast_calls.f90
  src/core/array/mlxf_array_io.f90 -> src/core/io/mlxf_io_calls.f90
  src/core/array/mlxf_array_distributed.f90 -> src/core/distributed/mlxf_distributed_calls.f90
```
