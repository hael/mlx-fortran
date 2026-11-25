# Host oracles for the projection, insertion and PCG toys (run `mlxf_oracles`, on dell2)

Status, 2026-11-24: planned; the maintainer told the batch to proceed, so decisions 1 to 10 stand as
recommended and any of them may be overturned at the review. Base: the maintainer's commit of this note
on top of `8305556` (the run records its HEAD). Supersedes: none. Depends on: dell2 for plain Fortran
(validated: yes, run `mlxf_dell2_bringup`, 2026-11-24); the fixtures and oracle design of
[`mlxf_scientific_examples.md`](mlxf_scientific_examples.md), sections 4 (part B), 5 and 6 (validated: design
reviewed; a Python check of them ran on the laptop; no Fortran exists).

## 1. Why

Every toy of the [kernel families](mlxf_kernel_families.md) is judged against an independent host oracle in
double precision, and no kernel can start before its oracle exists. Three of them need no GPU, no MLX and
no decision that is still open: the projection gather (K2), its adjoint the insertion (K6), and the PCG solve
(K8). Their mathematics is fixed in the scientific examples note. The M5 Ultra is taken by parity and then by
the toy refactoring, while dell2 is idle and builds plain Fortran (*measured*: its bring-up compiled and ran
a standalone double-precision module without a warning, and the static gate passes there in 1.3 s). Writing
the oracles there puts them ahead of the kernels instead of in their way.

## 2. Contract

- **Plain Fortran, no MLX.** Each oracle is one module under `src/test/` that imports intrinsic modules
  only. It does not import `mlxf`, `mlxf_test_utils` or any module that reaches the library, so it compiles
  on dell2.
- **Independent of every kernel.** An oracle follows the mathematics of the examples note. It shares no
  index, weight or layout code with a toy, and it does not mirror SIMPLE's implementation.
- **Held to closed forms here, compared with MLX later.** On dell2 each oracle is checked against closed
  forms and explicit constructions. Its comparison with a kernel waits for the Mac.
- **The shared test files are not touched.** `src/test/mlxf_test_defs.f90`, `mlxf_test_utils.f90` and
  `mlxf_test_registry.f90` belong to the parity run while it runs. An oracle keeps its constants local.
- **No tester and no registry row yet.** A tester needs the assertion module, which imports the library. The
  Mac-side integration (decision 8) adds them.
- **The house rules for Fortran hold** (skill `mlxf-modern-fortran`): layout, at most five dummy arguments,
  one `!@descr:` line, both formatters, `scripts/check_tree.sh`.

### What the check found (2026-11-24)

- **dell2** (run `mlxf_dell2_bringup`, *measured*): GNU Fortran 15.2.0, Python 3.14.4, 16 cores, 61 GB.
  - `scripts/check_tree.sh` passes on the repository there; its rule `parity` skips only the header
    comparison.
  - Both formatters work, also on a file outside the tree.
  - The library and the test executable cannot be configured: CMake stops at mlx-c.
  - A file of `src/test/` that imports `mlxf_test_utils` cannot be compiled. Today's polar oracle is one,
    through `bits_equal` alone.
- **The Mac compiles with GNU Fortran 16.2**, dell2 with 15.2. The oracles are single modules without
  submodules, so the linkage trap of compilers before 16 does not arise.
- **Test sources are globbed** (`src/CMakeLists.txt`): a new module under `src/test/` joins `mlxf_test_exec`
  on the Mac at the next configuration. A warning there fails the build, so the Mac build is part of
  decision 8.
- **The stop hook runs the static gate** whenever `src/` differs from HEAD. On dell2 it passes, so the hook
  works as on the Mac.
- **The mathematics is written:** the examples note, section 5 (the projection operator, its Kaiser-Bessel
  weights, the padded transform, the adjoint, the density, the packed Hermitian half) and section 4, part B
  (the PCG operator, its preconditioner, the explicit stencil matrix, the manufactured solution).

## 3. Decisions and rulings

1. (2026-11-24, recommended) **Scope:** three oracle modules and one shared transform. The oracle of the pose
   objective (K5) is not here: its mathematics is not fixed yet, and it gets its own plan.
2. (2026-11-24, recommended) **The modules,** all in `src/test/`:
   - `mlxf_oracle_dft`: direct discrete Fourier transforms in complex double precision, 1D and 3D, forward
     and inverse, for the small sizes of the fixtures;
   - `mlxf_oracle_projection`, for K2 and K6:
     - the geometry of the examples note's section 5 and the Kaiser-Bessel weights from a converged series;
     - the explicit matrix G;
     - the forward gather, the adjoint, the density;
     - the packing and expansion of the Hermitian half;
   - `mlxf_oracle_pcg`, for K8:
     - the explicit matrix of section 4, part B, and the preconditioner by transform sums;
     - the manufactured solution and right-hand side;
     - a Cholesky solve and a reference conjugate-gradient solve in double precision.
3. (2026-11-24, recommended) **Each module exports its self-check** as a procedure that returns named largest
   errors, never as assertions. A scratch driver calls it on dell2; a tester calls it on the Mac later.
4. (2026-11-24, recommended) **Fixtures** are the examples note's, unchanged:
   - **Projection:** the two-blob phantom on 6³ padded to 12³; the three explicit rotations; 12 angles on
     shells 1 and 2 (72 polar samples); the Cartesian slice and boundary cases.
   - **PCG:** N = 4 padded to 8 (64 unknowns), with its spatial window, `lambda` = 0.25 and the manufactured
     solution; the unpadded case; the 16³ variant.
5. (2026-11-24, recommended) **Thresholds for the self-checks,** frozen here, all in double precision:
   - transforms against closed forms, relative to the largest magnitude: 1e-12 (*guessed*; the bring-up
     measured 5.3e-15 at n = 31);
   - the adjoint identity: `|<G z, y> - <z, G^H y>|` ≤ 1e-12 · (‖G z‖‖y‖ + ‖z‖‖G^H y‖) (*guessed*);
   - the matrix G against the gather, element by element: 1e-13 (*guessed*);
   - the Cholesky solution against the manufactured one, and the operator against the explicit matrix:
     1e-12 normwise (*guessed*, the examples note's table);
   - indices, counts, masks and packing: exact.

   A check that misses its threshold is diagnosed, never loosened.
6. (2026-11-24, recommended) **Building on dell2:** the bring-up's recipe.
   - Each module is compiled alone with `gfortran -std=f2018 -Wall -Wextra -Werror`, once with
     `-O0 -g -fcheck=all` and once with `-O2`, with modules written into a scratch directory.
   - The drivers live under `scratch/keep/drivers/` and are quoted in the report. They do not enter the
     repository.
7. (2026-11-24, recommended) **Negative controls.** For each oracle, one planted error per check is shown to
   fail it, then removed. For example: a transposed rotation, a dropped conjugation, a missing factor of 8,
   C-order addressing, a wrong sign in the stencil.
8. (2026-11-24, recommended) **Integration on the Mac, after the run.** At review the diff is applied to the
   maintainer's checkout and built in Debug and Release. A warning under GNU Fortran 16.2 is fixed there.
   The oracles are "delivered on dell2" until that build passes, and each toy's plan adds the tester.
9. (2026-11-24, recommended) **Time boxes** (*guessed*): Phase 0, 30 minutes; Phase 1, 60; Phase 2, 180;
   Phase 3, 120; Phase 4, 30.
10. (2026-11-24, recommended) **The record:** Progress in this note; the report in
    `completed/mlxf_oracles_report.md`. The history entry is written at review, not by the run, because the
    parity run edits the same history file.

Defaults taken without a question (cheap to veto): the prefix `mlxf_oracle_`; one module per oracle without
submodules; the names of the exported procedures, which the run chooses within the house rules and lists in
Progress.

## 4. Not in this plan

- Any toy kernel, any MLX call, any tester or registry row.
- `src/test/mlxf_test_defs.f90`, `mlxf_test_utils.f90`, `mlxf_test_registry.f90`, `src/core/`, `scripts/`,
  `cmake/`, the ledgers.
- The polar oracle that exists, and the question of moving `bits_equal` out of `mlxf_test_utils`.
- The oracle of the pose objective (K5).
- SIMPLE: it is neither read nor built.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | baseline | the static gate on the untouched copy; the build recipe on a trial module |
| 1 to 3 | tests-only code (new modules) | standalone builds without a warning at `-O0 -fcheck=all` and `-O2`; the self-checks inside decision 5's thresholds; each negative control failing; formatters and `scripts/check_tree.sh` |
| 4 | documentation | `scripts/check_tree.sh`; only file-table paths changed |

## 6. Acceptance

- Decision 5's thresholds, each tagged with its origin, frozen before any oracle is run.
- Each self-check reports its largest error; the report tabulates them at both optimisation levels.
- **Reported, not gated:** the reference conjugate-gradient solve's iteration count and residual history; the
  compile and run times on dell2.
- **What dell2 cannot show:** that the modules build without a warning under GNU Fortran 16.2, and that they
  agree with an MLX kernel. Decision 8 and the toys' plans cover those.

## 7. Common rules and stop conditions

- No file outside the table. No shared test file. No threshold loosened, and no fixture changed to pass.
- The run writes its notes with the editor tools: the fence refuses a shell command whose text names a
  publish to the remote, a heredoc included (bring-up finding).
- `scripts/format_use_blocks.py` rewrites the tree when given an option it does not know (bring-up finding):
  it is called only as `--check` or with explicit file names.

**Stops:**
- the examples note's mathematics is ambiguous or contradicts itself on a point an oracle needs;
- an oracle cannot meet a threshold after diagnosis;
- a module would need the library or a shared test file;
- the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no import that reaches the library; the negative controls; the static gate.

## 8. Phases

### Phase 0, the baseline on dell2

1. Record the machine and the base commit. Run `scripts/check_tree.sh` on the untouched copy.
2. Read the examples note's sections 4 (part B), 5 and 6, and the kernel-families note's sections on
   families B, C and D.
3. Restate each oracle's mathematical contract in Progress: the definitions, the fixture's sizes and counts
   worked by hand (72 samples, 1,728 padded voxels, 64 unknowns), and each point where the note leaves a
   choice, with the choice taken.
4. Build and run a trial module with decision 6's recipe.

**Exit:** the gate passes on the base; the contract is in Progress; the recipe's two builds run.

### Phase 1, the transforms (`mlxf_oracle_dft`)

Forward and inverse direct transforms in 1D and 3D, with their normalisation stated. Self-checks: single
modes; a constant; Parseval's identity; forward then inverse; an unequal `6 x 8 x 10` case that catches
swapped dimensions.

**Exit:** both builds without a warning; the self-checks inside decision 5; one negative control per check;
formatters and the static gate pass.

### Phase 2, the projection and its adjoint (`mlxf_oracle_projection`)

1. Geometry: the polar sample coordinates, the three rotations written out, the padded coordinates, the
   stencil base by `nint`, and the signed-frequency addressing.
2. Weights: the Kaiser-Bessel window from a converged series, normalised per axis.
3. The explicit matrix G from scalar geometry; the forward gather; the route from the real phantom to the
   projection with its scale.
4. The adjoint, the density, and the packed Hermitian half with its multiplicity weights.
5. Self-checks: the matrix against the gather; a constant Fourier field; the unit point at the origin; the
   adjoint identity, plain and with a complex diagonal factor; the numerator and the density separately; the
   packed half against the full grid; the boundary queries.

**Exit:** as Phase 1's, for these checks.

### Phase 3, the PCG problem (`mlxf_oracle_pcg`)

1. The explicit matrix from the stencil, the window and `lambda`; its symmetry and positive curvature.
2. The preconditioner from transform sums.
3. The manufactured solution, the right-hand side, the Cholesky solve.
4. A reference conjugate-gradient solve with its residual history; the unpadded case, which must solve in
   one step; the zero right-hand side; the indefinite case refused.
5. The 16³ variant, with its operator applied without a dense matrix and checked against the 8³ one's
   construction rules.

**Exit:** as Phase 1's, for these checks.

### Phase 4, the report

The report in the order of `doc/how2s/how2write_agent_plans.md`, section 8. It includes:
- the exported names of each module;
- the table of errors at both optimisation levels;
- the drivers;
- what the Mac integration must do (decision 8).

**Exit:** the report exists; `scripts/check_tree.sh` passes; `git status` shows only file-table paths.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_oracle_dft.f90` (new) | the direct transforms | 1 |
| `src/test/mlxf_oracle_projection.f90` (new) | the projection, its adjoint, the density, the packed half | 2 |
| `src/test/mlxf_oracle_pcg.f90` (new) | the PCG problem's matrix, preconditioner and reference solves | 3 |
| `doc/implementation_notes/planned/mlxf_oracles.md` | this note: Progress | 0, 1, 2, 3, 4 |
| `doc/implementation_notes/completed/mlxf_oracles_report.md` (new) | the report | 4 |

## Progress

(one entry per phase, written by the run)
