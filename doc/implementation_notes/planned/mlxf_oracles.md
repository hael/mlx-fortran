# Host oracles for the projection, insertion and PCG toys (run `mlxf_oracles`, on dell2)

Status, 2026-11-24: delivered by run `mlxf_oracles` on dell2 (19:13 to 20:25) and built on the Mac at the
review (Progress, last entry); it stays in `planned/` until the maintainer has read it. Decisions 1 to 10
stood as recommended, on the maintainer's word to proceed, and any of them may be overturned at the review. Base: the maintainer's commit of this note
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
| `src/test/mlxf_oracle_dft.f90` (new) | the direct transforms; from Phase 2 also the error helpers the three oracles share | 1, 2 |
| `src/test/mlxf_oracle_projection.f90` (new) | the projection, its adjoint, the density, the packed half | 2 |
| `src/test/mlxf_oracle_pcg.f90` (new) | the PCG problem's matrix, preconditioner and reference solves | 3 |
| `doc/implementation_notes/planned/mlxf_oracles.md` | this note: Progress | 0, 1, 2, 3, 4 |
| `doc/implementation_notes/completed/mlxf_oracles_report.md` (new) | the report | 4 |

## Progress

(one entry per phase, written by the run)

### Phase 0, the baseline: done (2026-11-24, 19:13 to 19:33 EST, dell2)

One unattended session of run `mlxf_oracles`. Machine: dell2, Ubuntu 26.04, Intel Core Ultra 7 366H (16
cores), 61 GB; load 0.27 at the start, below 0.35 throughout (*measured*). Base: `dc3f5d7` (this note's
commit), clean at the start. Rulings: none. Toolchain found: GNU Fortran 15.2.0 (Ubuntu 15.2.0-16ubuntu1) in
`/usr/bin`, Python 3.14; no module system and no build tree of this repository (nothing here builds the
library). Files changed: this note's Progress only. Evidence: `/home/hael/agent_runs/mlxf_oracles/scratch/keep/`
(`keep/` below). Numbers are *measured* (read from a log) unless tagged; fixture constants are *exact*.

**Exit.**
1. *The gate passes on the base:* met. `scripts/check_tree.sh` on the untouched copy exits 0 with
   `check_tree: passed`, 1.3 s at load 0.31. `keep/phase0_check_tree_base.log`.
2. *The contract is in Progress:* met, below (C0 to C3, the choices Q1 to Q20, the threshold map).
3. *The recipe's two builds run:* met. A trial module (`keep/phase0_trial/mlxf_oracle_trial.f90`, house
   layout, intrinsic imports only) and its driver (`keep/drivers/mlxf_oracle_trial_main.f90`) compiled file
   by file by `keep/drivers/build_level.sh`, decision 6's recipe: `gfortran -std=f2018 -Wall -Wextra -Werror`
   with `-O0 -g -fcheck=all` or `-O2`, modules into `scratch/build_O0` or `scratch/build_O2`. No compiler
   output and exit 0 at both levels (0.07 s and 0.11 s); both runs print `trial: passed`.
   `keep/phase0_trial_build_{O0,O2}.log`, `keep/phase0_trial_run_{O0,O2}.log`. Both formatters accept the two
   files (`format_use_blocks.py` rewrote the driver's `use` line once).

**Dry runs** (the trial computes them with loops of its own; same logs):
- The projection fixture: 72 polar samples, smallest distance of a padded coordinate from a half-integer
  2.154e-2; 45 Cartesian slice samples (Q7), 2.308e-2; both above the examples note's 1e-4 (*guessed* there).
  1,728 padded voxels and 64 PCG unknowns, as section 8 works them.
- The window: β = 6.4860765305108297 (*derived* by its formula, printed); I0 by its power series agrees with
  the trapezoid rule on its periodic integral (64 points) within 4.1e-16 relative at δ = 0, 0.5, 1, 1.5,
  where I0 = 104.94, 74.69, 23.50 and 1: the examples note's "105 at its centre, 1 at its edge".
- The gate on a new module, in a scratch copy of the tracked tree (deleted after): an intrinsic-only module in
  `src/test/` with no tester and no registry row passes `check_tree.sh`; a second module importing a
  *procedure* of the first passes; importing a *constant* of it fails rule `defs` ("a constant of
  mlxf_oracle_trial that another module imports"). `keep/phase0_gate_dryrun_{trial_in_src_test,
  procedure_import,constant_import}.log`.

#### C0, common to the three modules

- `src/test/mlxf_oracle_{dft,projection,pcg}.f90`, one module each, no submodule. Imports: `iso_fortran_env`
  only, plus procedures of `mlxf_oracle_dft` in the other two (Q1). (Amended in Phase 1: also
  `ieee_arithmetic`, an intrinsic module as section 2 allows, for the finiteness tests.)
- Exported: procedures only. Every constant (π, sizes, fixtures, thresholds) is a local `parameter`: section 2
  keeps them out of `mlxf_test_defs`, and the dry run shows that an imported constant fails rule `defs`. No
  exported derived type unless it is a class (type-bound procedures or private components): `defs` flags an
  imported behaviourless type the same way. No module-level variable (rule `state`).
- The self-check (decision 3, Q2): `<x>_selfcheck( labels, errors, limits )`, with
  `character(len=:), allocatable, intent(out) :: labels(:)` and `real(real64), allocatable, intent(out) ::
  errors(:), limits(:)`. `errors(i)` is check i's largest error in the measure of the threshold map below,
  `limits(i)` its decision-5 number; an exact check reports its mismatch count and the limit 0. The module
  asserts nothing, prints nothing and never stops; the caller (driver, later the tester) compares.
- Storage: Fortran order, dimension 1 fastest. A 0-based index or frequency m is stored at 1 + m; a signed
  frequency h of an M-grid at 1 + modulo(h, M). Inputs other than the fixtures are fixed integer sequences,
  never `random_number` (examples note, decision 8); each phase records the ones it defines.

#### C1, `mlxf_oracle_dft` (Phase 1)

- Forward unnormalised, negative exponent: X(k) = Σ_m x(m) exp(−2πi km/n). Inverse with positive exponent and
  1/n: x(m) = (1/n) Σ_k X(k) exp(+2πi km/n). In 3D, the product of the three, the inverse normalised by
  n1·n2·n3 (the examples note: "F unnormalised, inverse normalised by M³"; the sign is Q3). Complex double,
  direct sums (no fast algorithm), the phase reduced as modulo(k·m, n) in integers.
- Sizes in use: 4, 8, 12 and 16 per dimension, and 6 × 8 × 10.
- Closed forms: an impulse at m0 → exp(−2πi k m0/n); a mode exp(+2πi k0 m/n) → n δ(k, k0); a constant c →
  n c δ(k, 0); Parseval Σ|X|² = n Σ|x|²; inverse after forward = identity; in 6 × 8 × 10, a mode and an
  impulse at (1, 2, 3), distinct per axis, so a swap of two dimensions changes the result.

#### C2, `mlxf_oracle_projection` (Phase 2)

- **Phantom**, N = 6: voxel (i1, i2, i3), i = 1..6, at the centred x_a = i_a − 1 − N/2 ∈ {−3, ..., 2};
  v = exp(−|x − (−1, 0, 1)|²/2) + 0.7 exp(−|x − (1, 1, −1)|²/(2 · 0.7²)); 216 voxels.
- **Padding and centre**, M = 12, 1,728 voxels: centred x goes to padded index x + 1 + M/2 (the phantom at 4..9);
  moving the centre to the DFT origin puts it at 1 + modulo(x, M) (x = −3..2 → 10, 11, 12, 1, 2, 3).
  Fpad = DFT(vshift)/M³; the projection is 8 · G · Fpad.
- **Rotations**, R(i, j) by rows (Q4): the identity; the quarter turn about z, [[0, −1, 0], [1, 0, 0], [0, 0, 1]];
  the oblique Rz(3/5, 4/5) · Ry(5/13, 12/13) = (1/65) [[15, −52, 36], [20, 39, 48], [−60, 0, 25]], with
  Rz(c, s) = [[c, −s, 0], [s, c, 0], [0, 0, 1]] and Ry(c, s) = [[c, 0, s], [0, 1, 0], [−s, 0, c]]. Its rows are
  orthogonal with squared norms 4225/4225 (*exact*, worked by hand).
- **Polar samples:** angle θ_a = 2π(a − 1)/12, a = 1..12 (Q5); shells k = 1, 2;
  p = (k sin θ, −k cos θ, 0); t = 2 p R, t_j = 2 Σ_i p_i R(i, j). Output (12, 2, 3) = (angle, shell, rotation),
  Fortran order (Q6): 72 samples (*exact*). |t| ≤ 4, so |h| ≤ 5: polar stencils reach neither Nyquist nor a
  wrap. θ_{a+6} = θ_a + π, so every sample has its Friedel mate in the set.
- **Cartesian half slice** (Q7): p = (h, k, 0), h = 0..2, k = −2..2, the same rotations, t = 2 p R: 45 samples.
  Identity and quarter turn give even integers; the oblique gives ((6h + 8k)/13, (6k − 8h)/5, (72h + 96k)/65),
  never a half-integer. Its stencils reach Nyquist and wrap: (h, k) = (2, −2) has t_2 = −5.6, stencil −7..−5.
- **Boundary queries** (Q8), padded coordinates given directly, exactly representable: q1 = (0.5, −0.5, 1.5),
  q2 = (−1.5, 2.5, −2.5), q3 = (5.5, −5.5, 6), q4 = (−5.5, 0, −6). Bases by `nint`: (1, −1, 2), (−2, 3, −3),
  (6, −6, 6), (−6, 0, −6) (*exact*). They pin ±0.5, ±1.5, ±2.5, both signs about zero, h < 0, h = 0, Nyquist
  (±6 → index 7) and the wrap (7 → index 8, −7 → index 6).
- **Window:** K(δ) = I0(β √(1 − (δ/1.5)²)) for |δ| ≤ 1.5 (inclusive), else 0; β = π √((3/2)² (2 − 0.5)² − 0.8);
  I0 by its power series Σ_j ((x/2)^j/j!)², summed until a term is below ε times the sum. Per axis: b = nint(t)
  (half away from zero), h ∈ {b − 1, b, b + 1}, w(h) = K(t − h)/Σ_{m=−1..1} K(t − b − m).
  G(s, v) = w1 w2 w3 on the 27 stencil voxels, duplicate destinations added.
- **Explicit G** (Q9): rows the samples in output order; columns the 12³ voxels in Fortran order,
  1 + (i1 − 1) + 12 (i2 − 1) + 144 (i3 − 1). Built separably from scalar geometry by a loop over voxel indices,
  not over the stencil: G(s, v) = Π_a W_a(s, i_a), W_a(s, i) = Σ over h ≡ i − 1 (mod M) with
  |h − nint(t_a)| ≤ 1 of w(h). For the polar set 72 × 1,728 = 124,416 entries, 27 nonzero per row, all
  positive (K ≥ 1 in the window; M = 12 leaves no duplicate in a row) (*derived*).
- **Gather:** per sample, the 27 weights and indices 1 + modulo(h, M), Σ w F.
- **Adjoint, numerator, density:** G^H y = G^T y (G is real), by scattering each sample's 27 contributions
  with addition. A = D G with a complex diagonal D. Numerator G^T (w conj(D) y), density G^T (w |D|²), with
  positive observation weights w: the stencil weights once, not diag(A^H W A).
- **Packed half** (Q10), along dimension 1: P(i1, i2, i3), i1 = 1..M/2 + 1 = 7 (h1 = 0..6), 7 · 12 · 12 =
  1,008 entries; packing copies the full grid's i1 = 1..7. Expansion E: i1 ≤ 7 reads P; i1 = 8..12
  (h1 = −5..−1) is conj(P(−h)), −h addressed by 1 + modulo(−h, M) on every axis. The h1 = 0 and Nyquist planes
  are stored whole; on a Hermitian field they satisfy P(h1, h2, h3) = conj(P(h1, −h2, −h3)). The packed gather
  reads P where modulo(h1, M) ≤ M/2, else conj(P(−h)). The fold, the packed adjoint's accumulation: a
  contribution c at a full index j with j1 ≤ 7 adds to P(j), else conj(c) adds to P(−h). Multiplicity μ = 1 on
  i1 = 1 and 7, μ = 2 on i1 = 2..6; the induced inner product <a, b>_μ = Σ μ Re(conj(a) b) = Re<E a, E b>; the
  packed adjoint is μ⁻¹ fold, so Re<G E p, y> = <p, μ⁻¹ fold(G^T y)>_μ.
- **Fixed inputs** of the checks: a complex field on the 12³ grid, complex samples y, the factor D and the
  weights w, all from integer sequences that Phase 2 defines and records.

#### C3, `mlxf_oracle_pcg` (Phase 3)

- **Sizes:** N = 4, M = 8: 64 unknowns, 512 padded voxels (*exact*). x(i, j, k) with zero-based i, j, k = 0..3
  along dimensions 1, 2, 3; vector order u = 1 + i + 4j + 16k (Q11).
- **C** embeds at offset (M − N)/2 = 2 (indices 3..6), the projection's centred rule; C^T crops the same
  entries. The operator is shift-invariant, so the offset only places the crop.
- **S** (Q12): 1 on the 8 interior voxels (every index 1 or 2), 0.5 on the 56 surface voxels (some index 0 or
  3). The zero-face case (Q13) sets S = 0 on the 16 voxels with i = 0 and keeps the rest: 16 at 0, 40 at 0.5,
  8 at 1.
- **d**(q) = 1 + 4 (sin²(π q1/M) + sin²(π q2/M) + sin²(π q3/M)), q = 0..M − 1 (d is even and M-periodic, so
  signed or unsigned q agree); λ = 0.25.
- **H** = S C^T F⁻¹ diag(d) F C S + λ I. Explicit: H(u, u') = S_u A(u, u') S_u' + λ δ(u, u'), A = 7 on the
  diagonal and −1 between face neighbours inside the 4-cube; the crop removes the rest, and at offset 2 no
  periodic wrap is reached. 144 neighbour pairs, 288 off-diagonal entries, 352 nonzeros (*derived*); exactly
  symmetric (integers times halves). 1 ≤ d ≤ 13 and 0 ≤ S ≤ 1 put the spectrum in [0.25, 13.25], condition
  at most 53 (*derived*, examples note).
- **P⁻¹** = C^T F⁻¹ diag(1/(d + λ)) F C, by `mlxf_oracle_dft`'s 3D sums on 8³ (Q14: the complex transform of
  real data; the imaginary part of the result is held to the transform threshold, then dropped). Its
  independent check (Q15): C^T (K_M + λ I)⁻¹ C, where K_M is the explicit 512 × 512 periodic stencil matrix of
  the 8³ grid, inverted through its Cholesky factor.
- **Manufactured:** x_true(i, j, k) = (1 + modulo(3i + 5j + 7k, 11))/11; b = H x_true in real64; b32 = b
  rounded once to real32. Cholesky of the explicit H: the solve with b is gated against x_true; the solve with
  b32 is reported (the rounding difference), not gated.
- **Reference solve** (Q16): preconditioned conjugate gradients with P⁻¹, real64. r0 = b − H x0, z = P⁻¹ r,
  p = z; per step q = H p and κ = pᵀq; κ ≤ 0 refuses (status "not positive definite") before any division;
  α = rᵀz/κ. Stop when ‖r‖₂ ≤ 1e-14 ‖b‖₂ (*guessed*) or after 64 iterations (the examples note's design cap;
  status "iteration limit"). b = 0 returns x = 0 after zero iterations, whatever x0. It returns x, the
  iteration count, the status, the history of ‖r‖, and the true residual by the explicit matrix. (Amended in
  Phase 3:
  - the caller computes the true residual with the explicit matrix, because the solve's five arguments are
    taken;
  - a guess whose r0 already meets the stop rule is returned after no iteration;
  - a b or x0 that is not finite is refused, with status 3.)
- **Cases:** the padded case from x0 = 0 and from x0(i, j, k) = modulo(2i + 3j + k, 5)/5 (Q17); the zero-face
  case; the unpadded case (Q18: M = N = 4, S = I, C = I, the periodic stencil on 4³ with 6 distinct neighbours,
  448 nonzeros; P⁻¹ = H⁻¹ exactly, so one step); the zero right-hand side; the iteration limit (cap 2 on the
  padded case); the case that is not positive definite (Q19: −H, refused at the first step).
- **16³ variant** (Q20): M = 16, N = 8: 512 unknowns, 4,096 padded voxels, offset 4; the same rules for C, S,
  d, λ and x_true (i, j, k = 0..7). Its operator is a stencil applied without a dense matrix, checked against
  the dense H at N = 4 and against the transform route at N = 8, on x_true and on fixed vectors Phase 3
  records. Its PCG solve (cap 512) is reported, not gated.

#### Choices where the examples note leaves one (Q1 to Q20)

Taken here under delegation, cheap to veto; Phases 1 to 3 implement them as written.

- **Q1.** Section 2's "imports intrinsic modules only" is read as: nothing outside the intrinsic modules and
  this plan's own oracle modules, which import intrinsic modules only. Decision 2 makes `mlxf_oracle_dft` the
  one shared transform, the house rule calls a second copy of a routine a defect, and the sentence's stated
  purpose (compiles on dell2, never reaches the library) holds. Vetoed, Phases 2 and 3 carry private copies.
- **Q2.** The self-check's form above: plain arrays rather than a returned record, because `defs` refuses a
  behaviourless type or a constant another module imports, and `mlxf_test_defs` is out of bounds. The
  thresholds therefore live in each module; the Mac integration may move them to `mlxf_test_defs`.
- **Q3.** The forward transform's exponent is negative (MLX's, FFTW's). The note fixes only the
  normalisation; nothing in its checks depends on the sign except through the stated closed forms.
- **Q4.** Rz and Ry as written above (active, right-handed). The note names their cosines and sines only.
- **Q5.** The angles start at θ = 0 and step by 2π/12 over the full ring.
- **Q6.** The order of the samples: angle fastest, then shell, then rotation.
- **Q7.** The "short Cartesian central slice": the half slice h = 0..2, k = −2..2 under the three rotations.
- **Q8.** The boundary queries q1 to q4 above.
- **Q9.** The explicit G is separable over the voxel indices (a different code path from the gather);
  columns in Fortran order.
- **Q10.** The packed convention above: the planes h1 = 0 and Nyquist stored whole, μ = 1 there and 2 inside,
  the packed adjoint μ⁻¹ fold in the induced inner product; μ is checked on its own (threshold map).
- **Q11.** The PCG vector order, i fastest.
- **Q12.** "Boundary voxels" are the surface voxels of the N-cube (some index 0 or N − 1).
- **Q13.** The face zeroed in the separate case is i = 0 of dimension 1.
- **Q14.** The PCG's transforms are complex transforms of real data, the imaginary part checked, then dropped.
- **Q15.** P⁻¹'s independent construction: the inverse of the explicit periodic stencil plus λ on the M-grid.
- **Q16.** The reference solve is preconditioned (the unpadded case's one step needs the preconditioner), with
  the stop rule and statuses above.
- **Q17.** The nonzero initial guess modulo(2i + 3j + k, 5)/5.
- **Q18.** The unpadded case is M = N = 4 with S = I.
- **Q19.** The "deliberately indefinite" case is −H. On a matrix with eigenvalues of both signs, the step at
  which pᵀHp first falls to zero or below depends on the preconditioned direction, so the refusal would not be
  a fixed gate; −H refuses at the first step for every direction, which is the guard under test.
- **Q20.** "16³" is the padded size, M = 16 and N = 8: this plan calls the base problem "the 8³ one", whose
  padded size is 8. The note writes only "16 × 16 × 16". Its PCG cap is its 512 unknowns.

The examples note does not contradict itself on any point these oracles need (*derived*: 8/M³ = 1/N³ = 1/216
for the unit point; d = 7 − 2 Σ cos(2πq/M) is the seven-point stencil; with M = N and S = I, P⁻¹ = H⁻¹; the
spectrum bound; I0(0) = 1 against I0(β) = 104.94).

#### Threshold map (decision 5's numbers, applied to the checks)

| Check | Measure | Limit |
| --- | --- | --- |
| DFT closed forms, round trip, 6 × 8 × 10; I0 series against the trapezoid rule; the phantom route: a unit point at the centre gives 1/N³, a unit point at x0 = (1, 2, −1) matches its closed-form field exp(−2πi h·x0/M)/M³ through G, Friedel mates are conjugate; the imaginary part in the PCG transforms | max \|error\| / max \|reference\| (Parseval: \|Δ\| / (n Σ\|x\|²)) | 1e-12 |
| rotated coordinates against values worked by hand (catches a transposed R); boundary-query weights against their closed forms with I0 from the trapezoid rule; G's entries against the gather's weights | max \|error\| (entries and weights ≤ 1, coordinates in padded units ≤ 6) | 1e-13 |
| G against the gather on a complex field; a constant field (G c = c); the scatter against G^T y; numerator and density against G^T, and their totals (Σ numerator = Σ w conj(D) y, Σ density = Σ w \|D\|², since each row of G sums to 1); the packed gather and the fold against the full grid | per element, \|Δ\| / Σ\|terms\| | 1e-13 |
| adjoint identity: plain, with D, packed with μ; the multiplicities themselves, <a, b>_μ = Re<E a, E b> on fixed packed vectors (the packed identity alone cannot fail on a wrong μ, since μ · μ⁻¹ is exact for μ = 1, 2) | \|<G z, y> − <z, G^H y>\| / (‖G z‖ ‖y‖ + ‖z‖ ‖G^H y‖); for μ, \|Δ\| / (‖E a‖ ‖E b‖) | 1e-12 |
| H by transforms against the explicit H; the stencil without a matrix against both; P⁻¹ by sums against the Cholesky inverse; Cholesky(b) against x_true; PCG against Cholesky and its true residual; the unpadded case's one-step solution | normwise, ‖Δ‖ / ‖reference‖ | 1e-12 |
| counts, bases, indices, nonzero patterns, packing and expansion of an exactly Hermitian field ((F(h) + conj(F(−h)))/2 is Hermitian exactly in value, but not bit for bit: where the imaginary parts cancel, one side holds +0 and its conjugate −0, so the mismatches are counted by value, \|a − b\| > 0, never by bit pattern), symmetry of the explicit H, the zero right-hand side's exact zero (it shows only that the solver's b = 0 branch exists), statuses and iteration counts (unpadded 1, limit 2, −H refused at 1), positive curvature (every Cholesky pivot > 0; λ ≤ vᵀHv/vᵀv ≤ 13.25 for the basis vectors and x_true) | mismatch count | 0 |
| reported, not gated: Cholesky(b32) − x_true; PCG iteration counts and residual histories; the 16³ solve; compile and run times | | |

The examples note's controls map to these checks: a transposed R to the hand-worked coordinates; an omitted
conjugation to the adjoint identity with D; a dropped repeated destination to the scatter and the totals;
C-order flattening to G against the gather; an omitted factor 8 to the unit point; a mishandled negative
frequency to the boundary queries and the packed half; a wrong stencil sign to H against the transforms.

**Review.** An independent read-only review of this entry (a subagent, 19:26 to 19:32, given the examples
note and this entry, not my reasoning) re-derived the counts, β, the window values, the margins, the
rotation, the slice coordinates, the bases and wrap indices, the packed algebra, the PCG claims and the
Friedel mates, and found them right. It found two errors, corrected above before any oracle exists: the
symmetrised field is Hermitian in value, not bit for bit (signed zeros), and the packed adjoint identity
cannot fail on a wrong μ, so μ got a check of its own. Its own short Python simulation (not a log of this
run, a lead only) solved the padded case in 15 iterations and the unpadded case in one step at a relative
residual of 3.1e-16.

**Decisions taken under delegation:** Q1 to Q20 above.

**What it means, in short:** dell2 is ready for the three modules. The gate passes on the base, decision 6's
recipe builds and runs plain Fortran here without a warning at both levels, and the gate accepts a new
module in `src/test/` and an oracle importing another's procedures, but not its constants. The examples note is
consistent on every point the oracles need; the contract above fixes the twenty points it leaves open, and the
threshold map assigns each check one of decision 5's numbers before any oracle exists.

### Phase 1, the transforms (`mlxf_oracle_dft`): done (2026-11-24, 19:32 to 19:45 EST, dell2)

One unattended session. Machine dell2 as in Phase 0, load at most 0.17 (*measured*). Base `dc3f5d7`, the
working tree holding Phase 0's entry. Rulings: none. Files changed: `src/test/mlxf_oracle_dft.f90` (new, 284
lines); this note (this entry, and C0's import line amended). Evidence under `keep/` as in Phase 0. Numbers
are *measured* unless tagged; the limits are decision 5's (*guessed* there, frozen before this run).

**Conventions, fixed for Phases 2 and 3** (the module's header says the same):
- forward, unnormalised, negative exponent: X(k) = Σ_m x(m) exp(−2πi km/n);
- inverse, positive exponent, normalised by n: x(m) = (1/n) Σ_k X(k) exp(+2πi km/n);
- in 3D the product over the three dimensions, the inverse normalised by n1·n2·n3;
- a 0-based index k is stored at k + 1, dimension 1 fastest; complex double, direct sums (twiddles with the
  product k·m reduced modulo n in integers, explicit sums in a fixed order, the 3D one dimension after the
  other).

**Exported names:** `oracle_dft_1d(x)`, `oracle_idft_1d(x)` (pure functions of a `complex(real64)` vector),
`oracle_dft_3d(x)`, `oracle_idft_3d(x)` (of a rank-3 array; the result has the argument's shape), and
`oracle_dft_selfcheck(labels, errors, limits)` (C0's form). Imports: `iso_fortran_env`, `ieee_arithmetic`.

**The self-check:** 12 checks, each error the largest over its cases; a non-finite result reports +Inf (every
value is tested first, since `maxval` may pass over a NaN). 1D at n = 4, 6, 8, 10, 12, 16; 3D on 6 × 8 × 10
and 4³, 8³, 12³, 16³. Impulses at 0-based position (1, 2, 3) and modes at frequency (1, 2, 3), distinct per
axis; the 1D ones at 1 (the inverse impulse at 2). Inputs are fixed integer sequences, no random draw.

| Check | Closed form | -O0 | -O2 | Limit |
| --- | --- | --- | --- | --- |
| dft1 impulse | exp(−2πi k m0/n) | 0 | 0 | 1e-12 |
| dft1 mode | n δ(k, k0) | 1.7e-16 | 1.7e-16 | 1e-12 |
| dft1 constant | n c δ(k, 0) | 1.4e-16 | 1.4e-16 | 1e-12 |
| dft1 parseval | Σ\|X\|² = n Σ\|x\|² | 1.5e-16 | 1.5e-16 | 1e-12 |
| dft1 round trip | inverse(forward(x)) = x | 4.2e-16 | 4.2e-16 | 1e-12 |
| idft1 impulse | exp(+2πi k0 m/n)/n | 1.1e-15 | 1.1e-15 | 1e-12 |
| dft3 impulse | exp(−2πi Σ k_a m_a/n_a) | 7.9e-15 | 7.9e-15 | 1e-12 |
| dft3 mode | n1 n2 n3 δ(k, k0) | 3.9e-16 | 3.9e-16 | 1e-12 |
| dft3 constant | n1 n2 n3 c δ(k, 0) | 1.4e-16 | 1.4e-16 | 1e-12 |
| dft3 parseval | Σ\|X\|² = n1 n2 n3 Σ\|x\|² | 8.4e-16 | 8.4e-16 | 1e-12 |
| dft3 round trip | inverse(forward(x)) = x | 9.2e-16 | 9.2e-16 | 1e-12 |
| idft3 impulse | exp(+2πi Σ k_a m_a/n_a)/(n1 n2 n3) | 8.0e-15 | 8.0e-15 | 1e-12 |

The errors are relative to the reference's largest magnitude (Parseval: to n Σ|x|²), as the threshold map
says. The two levels print the same digits. The largest, 8.0e-15, comes mostly from the 3D references, whose
phases are not reduced modulo n; it is 125 times below the limit. The 1D impulse is exact because its
reference is the same cos/sin arithmetic as the twiddle; it still fails under three plants below.

**Exit.**
1. *Both builds without a warning:* met. `keep/drivers/build_level.sh` at `-O0 -g -fcheck=all` and `-O2`
   (`-std=f2018 -Wall -Wextra -Werror`), module and driver: no compiler output, exit 0.
   `keep/phase1_dft_build_{O0,O2}.log`.
2. *The self-checks inside decision 5:* met, 12 of 12 at both levels, table above; the driver
   `keep/drivers/mlxf_oracle_dft_main.f90` exits 0 (a NaN error cannot pass its comparison). 0.01 s and
   0.00 s wall, 4 MB, load 0.04. `keep/phase1_dft_run_{O0,O2}.log`.
3. *One negative control per check:* met. `keep/drivers/run_controls.py` plants each error of
   `keep/drivers/plants_dft.py` in a copy (under `scratch/controls_dft/`; the repository's file is never
   written, so no plant needs removing), builds it at `-O0 -fcheck=all` without a warning, and runs the
   driver; the unplanted copy passes first. Ten plants: the forward sign in 1D and in 3D; the inverse
   without 1/n in 1D, and normalised by n1 in 3D; the 3D result in C order, and with dimensions 2 and 3
   swapped; frequencies stored one place off; the forward scaled by 1/√n in 1D and in 3D; a division by zero
   (every check reports +Inf). Every check fails under at least two plants, every plant fails at least two
   checks, and the driver exits 1 each time: "12 of 12 checks covered". `keep/phase1_dft_controls.log`.
4. *Formatters and the static gate:* met. Both formatters ran on the module and the driver; their `--check`
   passes. `scripts/check_tree.sh` passes, with its warning that the new file is not tracked yet, which is
   expected until the maintainer adds it. `keep/phase1_check_tree_end.log`.

**Review.** A read-only subagent reviewed the module against the skill and C0/C1. It confirmed the signs,
normalisation, index base and closed forms. It found three things, fixed before the final builds and runs
above:
- `rel_error` tested only the result for non-finite values, not the reference; it now tests both.
- Some assignment columns were misaligned after the formatter's pass.
- C0 named `iso_fortran_env` alone; it is amended to name `ieee_arithmetic` too.

**Decisions taken under delegation:**
- Two inverse-impulse checks were added to the plan's list (single modes, constant, Parseval, round trip,
  6 × 8 × 10). They pin the inverse's sign and normalisation on their own, where the round trip alone would
  pass a sign error made in both directions.
- The cubes 4³ to 16³ were added to the 6 × 8 × 10 case, because Phases 2 and 3 use those sizes.
- A non-finite result is reported as +Inf through `ieee_arithmetic`. The examples note asks for NaN and Inf
  to be checked explicitly.
- The negative controls are planted in copies, never in the repository's file.

**What it means, in short:** the shared transform exists and is held to its closed forms at both
optimisation levels, with errors below 1e-14 and every check shown able to fail. Phases 2 and 3 can build on
its conventions, written above and in its header. Its build under GNU Fortran 16.2 waits for the Mac
(decision 8).

### Phase 2, the projection and its adjoint (`mlxf_oracle_projection`): done (2026-11-24, 19:44 to 20:06 EST, dell2)

One unattended session. Machine dell2 as in Phase 0, load at most 0.24 (*measured*). Base `dc3f5d7`, the
working tree holding Phases 0 and 1. Rulings: none.

**Files changed:**
- `src/test/mlxf_oracle_projection.f90`: new, 911 lines.
- `src/test/mlxf_oracle_dft.f90`: four shared error helpers exported. The file table's row now lists Phase 2,
  added before the edit.
- This note: the file-table row and this entry.

Evidence is under `keep/` as before. Numbers are *measured* unless tagged; the limits are decision 5's
(*guessed* there, frozen before this run), the margin floor is the examples note's (*guessed* there).

**What the module implements:** contract C2 and choices Q4 to Q10, as written in Phase 0.
- The geometry: t = 2 p R, with p a row vector.
- The stencil: the `nint` base (half away from zero) and three points per axis.
- The weights: K(δ) = I0(β √(1 − (δ/1.5)²)) with I0 from its power series, normalised per axis.
- Addressing: 1 + modulo(h, m).
- The route: 8 G DFT(vpad)/m³, with the centre moved to the DFT origin.
- The packed half along dimension 1, with the fold as the expansion's adjoint and μ = 1, 2, …, 2, 1.

The explicit matrix is built per voxel from scalar geometry. For each axis and voxel index i, `axis_weights`
adds the window at every periodic image h = i − 1 + j m with |h − nint(t)| ≤ 1, then normalises over the
indices. It never calls the stencil routine or the gather it is checked against.

**Exported names:**
- *Fixture:* `oracle_proj_phantom`, `oracle_proj_rotation(irot)`, `oracle_proj_polar_coords`,
  `oracle_proj_slice_coords`, `oracle_proj_queries` (padded coordinates as (3, n) arrays, in Q6's and Q7's order).
- *Stencil and field:* `oracle_proj_stencil(t, h, w)` (one axis), `oracle_proj_padded_field(v)`.
- *Operators:* `oracle_proj_matrix(t, m)`, `oracle_proj_gather(t, f)`, `oracle_proj_scatter(t, y, m)`,
  `oracle_proj_numerator(t, y, d, w, m)`, `oracle_proj_density(t, d, w, m)`, `oracle_proj_route(v, t)`.
- *Packed half:* `oracle_proj_pack(f)`, `oracle_proj_expand(p)`, `oracle_proj_fold(g)`,
  `oracle_proj_packed_gather(t, p)`, `oracle_proj_packed_scatter(t, y, m)`, `oracle_proj_multiplicity(m)`.
- *Self-check:* `oracle_proj_selfcheck(labels, errors, limits)`.
- *Newly exported from `mlxf_oracle_dft`:* `oracle_flat`, `oracle_rel_error`, `oracle_finite_or_inf`,
  `oracle_all_finite`.

**Fixed inputs of the checks** (integers, no random draw; i, s are 1-based storage indices):
- field z(i1, i2, i3) = ((7i1 + 3i2 + 5i3) mod 11 − 5 + i((2i1 + 9i2 + 4i3 + 1) mod 13 − 6))/4;
- samples y(s) = ((5s + 2) mod 9 − 4 + i((3s + 1) mod 7 − 3))/4;
- factor D(s) = (1 + (s mod 4)/4) exp(2πi ((3s) mod 7)/7);
- weights w(s) = 1 + (s mod 5)/4;
- packed vectors ((3i1 + 5i2 + 7i3 + c) mod 11 − 5 + i((4i1 + i2 + 6i3 + 2c) mod 13 − 6))/4, c = 1, 2, 3;
- the constant field (0.75, −1.25).

**The self-check:** 26 checks. The operator checks take the largest error over the polar set, the Cartesian
slice and the boundary queries. A non-finite value reports +Inf, and exact counts are taken as "not ≤ 0", which a
NaN cannot pass.

| Check | Against | Measure | -O0 | -O2 | Limit |
| --- | --- | --- | --- | --- | --- |
| counts | 72, 45, 4, 1,728, 1,008 and Σ μ m² = m³ | mismatches | 0 | 0 | 0 |
| margins | polar and slice coordinates ≥ 1e-4 from a half-integer | count | 0 | 0 | 0 |
| rotations | orthonormal, det 1; the oblique = Rz(3/5, 4/5) Ry(5/13, 12/13), the quarter turn = Rz(0, 1) | abs | 2.2e-16 | 2.2e-16 | 1e-13 |
| coordinates | nine samples worked by hand | abs | 2.4e-16 | 2.4e-16 | 1e-13 |
| stencil bases | ±0.5, ±1.5, ±2.5; the queries' bases; wrap indices | mismatches | 0 | 0 | 0 |
| i0 series | trapezoid rule, δ = 0 to 1.5 by 1/8 | rel | 6.2e-16 | 6.0e-16 | 1e-12 |
| boundary weights | (K1, K0, K1), (Kh, Kh, 1), (1, Kh, Kh) over their sums, I0 by the trapezoid rule | abs | 2.8e-17 | 1.1e-16 | 1e-13 |
| matrix pattern | 27 positive entries per row, at the gather's indices | mismatches | 0 | 0 | 0 |
| matrix entries | the gather's weights at their indices | abs | 1.1e-16 | 1.1e-16 | 1e-13 |
| gather vs matrix | G z | per element | 2.8e-16 | 3.6e-16 | 1e-13 |
| constant field | G c = c, by the gather and the matrix | per element | 9.2e-16 | 9.2e-16 | 1e-13 |
| scatter vs matrix | G^T y | per element | 4.8e-16 | 4.8e-16 | 1e-13 |
| numerator vs matrix | G^T (w conj(D) y) | per element | 4.2e-16 | 4.2e-16 | 1e-13 |
| density vs matrix | G^T (w \|D\|²) | per element | 5.0e-16 | 5.0e-16 | 1e-13 |
| totals | Σ numerator = Σ w conj(D) y, Σ density = Σ w \|D\|² | over Σ\|terms\| | 1.3e-15 | 1.3e-15 | 1e-13 |
| adjoint plain | <G z, y> = <z, G^T y>, gather and scatter | adjoint | 2.0e-17 | 2.0e-17 | 1e-12 |
| adjoint with D | <D G z, y> = <z, numerator at w = 1> | adjoint | 1.7e-17 | 1.7e-17 | 1e-12 |
| packed gather | G E p | per element | 2.7e-16 | 2.7e-16 | 1e-13 |
| packed fold | fold(G^T y) | per element | 4.0e-16 | 4.0e-16 | 1e-13 |
| packed adjoint | Re<G E p, y> = <p, μ⁻¹ fold(G^T y)>_μ | adjoint | 3.2e-18 | 3.2e-18 | 1e-12 |
| unit point | every sample 1/N³ = 1/216 | rel | 7.5e-16 | 7.5e-16 | 1e-12 |
| off-centre point | 8 G of exp(−2πi h·x0/M)/M³, x0 = (1, 2, −1) | rel | 9.6e-16 | 1.0e-15 | 1e-12 |
| friedel mates | the phantom's samples at θ + π = conjugates at θ | rel | 9.2e-16 | 1.0e-15 | 1e-12 |
| pack expand | E(pack(Fh)) = Fh; packed gather of pack(Fh) = gather of Fh, three sets | mismatches by value | 0 | 0 | 0 |
| multiplicity | Σ μ Re(conj(a) b) = Re<E a, E b> | adjoint | 0 | 0 | 1e-12 |
| row duplicates | the matrix against the gather's weights on grids of side 2 and 3 | abs | 1.1e-16 | 1.1e-16 | 1e-13 |

"Per element" is |Δ| over the sum of |terms| of that element; "adjoint" is the threshold map's measure. The
largest error is 1.3e-15 (the totals), 80 times below its limit. The two levels differ only in the last digits
of five checks. The multiplicity check comes out exactly 0 because its inputs are quarter-integers, whose
products and sums are exact; it fails under the plants below all the same.

**Exit.**
1. *Both builds without a warning:* met. `keep/drivers/build_level.sh` builds `mlxf_oracle_dft`, the module
   and the driver `keep/drivers/mlxf_oracle_projection_main.f90` at `-O0 -g -fcheck=all` and at `-O2`; there is
   no compiler output. `keep/phase2_proj_build_{O0,O2}.log`.
   - The first build failed under `-Werror` with "‘g.offset’ may be used uninitialized". gfortran says this
     about an unallocated allocatable array assigned from a function result.
   - The fix is to allocate those arrays explicitly, or to use explicit-shape locals. Nothing was silenced.
2. *The self-checks inside decision 5:* met, 26 of 26 at both levels, table above. 0.02 s and 0.01 s wall,
   8 MB, load 0.23. `keep/phase2_proj_run_{O0,O2}.log`.
3. *One negative control per check:* met, "26 of 26 checks covered". `keep/drivers/run_controls.py` and
   `keep/drivers/plants_projection.py` use 23 plants, in copies of the module, built at `-O0 -fcheck=all`;
   the unplanted copy passes first. They include the examples note's controls:
   - transpose R: the oblique rotation written transposed, and the sample as a column vector;
   - omit conjugation: in the numerator, the packed gather, the packed scatter and the expansion;
   - drop a repeated scatter destination;
   - C-order flattening: in the matrix, the gather and the padded field;
   - omit the factor 8;
   - mishandle a negative frequency: half-up rounding of the base, and the packed conjugations.

   Some plants are narrow: the sample as a column vector fails only "coordinates", the padded field with
   dimensions 1 and 3 swapped only "off-centre point", one periodic image per voxel only "row duplicates".
   A NaN window fails 19 checks. Every plant makes the driver exit 1. `keep/phase2_proj_controls.log`.
4. *Formatters and the static gate:* met. Both formatters ran on the two modules and the driver, and their
   `--check` passes. `scripts/check_tree.sh` passes; its warning names the two new untracked files, which is
   expected. `keep/phase2_check_tree_end.log`.

The DFT module changed, so its Phase 1 checks were rerun:
- builds at both levels, without a warning;
- the same 12 errors digit for digit (`keep/phase2_dft_rerun_{O0,O2}.log`);
- its controls, 12 of 12 covered (`keep/phase2_dft_controls_rerun.log`).

**Review.** A read-only subagent reviewed the module against section 5 of the examples note, C2, the threshold
map and the skill. It found no mathematical defect. It confirmed the coordinates, stencil, window, addressing,
route, adjoint, conjugation, numerator, density, packing, fold, μ, and the nine hand-worked coordinates. It also
confirmed that the matrix never calls the stencil or the gather. Its findings were all fixed before the final
builds, runs and controls above:
- `flat`, `finite_or_inf`, `all_finite` and `max_rel` copied procedures of `mlxf_oracle_dft`. The house rule
  calls a second copy a defect, so they are now exported from that module.
- The rotation and coordinate errors could pass over a NaN. They now test the arrays for finiteness first.
- The "pack expand" count could pass a NaN. It now counts "not ≤ 0".
- A loop checked the conjugate symmetry of the h1 = 0 and Nyquist planes of a field built Hermitian. It
  could not fail, so it was replaced by the packed gather of the half against the gather of the full field.
- The quarter turn was compared with a copy of its own literal. Both rotations are now compared with the
  general Rz and Ry forms.

**Decisions taken under delegation:**
- *The shared helpers.* They are exported from `mlxf_oracle_dft` instead of a new module: they are that module's own
  error measures, and its file-table row was extended to Phase 2 before the edit. Phase 3 imports them too.
- *A 26th check, "row duplicates".* At M = 12 a stencil never reaches one voxel twice, so the examples note's
  "combine duplicate periodic destinations by addition" could not fail on the fixture. The check runs the
  matrix against the gather's weights on grids of side 2 and 3, where it does reach one voxel twice; plant p23
  shows it can fail.
- *The "adjoint with D" check goes through `oracle_proj_numerator` at unit weights,* not a conjugation written
  in the check. A conjugation dropped in the module therefore fails it.
- *The fixed inputs* are the integer sequences above.

**What it means, in short:** the projection oracle K2 and K6 will be judged against exists. Its explicit
matrix, built without the gather, agrees with the gather, scatter, numerator, density and packed half within
1.3e-15 at both levels. The adjoint identities hold to 2e-17, and the route reproduces the unit points' closed
forms. Every check fails under at least one planted error. Its build under GNU Fortran 16.2 and its comparison
with MLX wait for the Mac (decision 8).

### Phase 3, the PCG problem (`mlxf_oracle_pcg`): done (2026-11-24, 20:06 to 20:23 EST, dell2)

One unattended session. Machine dell2 as in Phase 0, load at most 0.27 (*measured*). Base `dc3f5d7`, the
working tree holding Phases 0 to 2. Rulings: none.

**Files changed:**
- `src/test/mlxf_oracle_pcg.f90`: new, 762 lines.
- This note: C3's sentence on the solve's outputs, amended, and this entry.

Evidence is under `keep/` as before. Numbers are *measured* unless tagged; the limits are decision 5's
(*guessed* there, frozen before this run), the stop rule 1e-14 and the caps are C3's.

**What the module implements:** contract C3 with choices Q11 to Q20.
- *A class* `oracle_pcg_problem`: an n-cube centre-embedded in a periodic m-grid, with its window, its sign
  (−1 for −H) and the cap of its solve.
- *Explicit matrix:* `matrix` builds it from the stencil rule itself: the centre 7, −1 for each periodic face
  neighbour whose position falls inside the embedded cube, the window on both sides, λ on the diagonal. It never
  applies the operator to basis vectors.
- *The operator two more ways:* without a matrix (`apply`, circular shifts on the m-grid), and by transforms
  (`apply_fft`, `mlxf_oracle_dft`'s 3D sums with d(q) = 1 + 4 Σ sin²(πq/m)).
- *The preconditioner two ways:* by transforms (`precond`), and as C^T (K_M + λI)⁻¹ C through the Cholesky
  factor of the explicit periodic stencil matrix of the m-grid (`precond_dense`).
- *The reference solve:* preconditioned conjugate gradients (`solve`).

The class exists because the solve needs the operator, its sign, the window and a cap, which is more than five
arguments. A class with type-bound procedures stays in its module under rule `defs`. It has `new` and an
idempotent `kill`; it holds only allocatable components, so it has no finaliser.

**Exported names:**
- *The type* `oracle_pcg_problem`, with bindings `new(n, m, window, sgn)` (window `'identity'`, `'surface'` or
  `'face'`), `kill`, `set_cap(cap)`, `window()`, `matrix()`, `apply(x)`, `apply_fft(x, y, imag)`,
  `precond(r, z, imag)`, `precond_dense()` and `solve(b, x, hist, info)`.
- *The solve's outputs:* `info` = [iterations done, status]. The statuses are 0 converged, 1 iteration limit,
  2 pᵀHp ≤ 0 met before its division, and 3 b or x not finite.
- *Free procedures:* `oracle_pcg_true(n)`, `oracle_pcg_cholesky(a, b, x, minpivot)` and
  `oracle_pcg_selfcheck(labels, errors, limits)`.
- *Imported from `mlxf_oracle_dft`:* `oracle_dft_3d`, `oracle_idft_3d` and `oracle_finite_or_inf`.

**Fixed inputs:** x_true and the nonzero guess Q17 as in C3; the 16³ checks also use (modulo(3i + 7j + 2k + c,
13) − 6)/6, c = 1, 2. The entry counts of H by value come from an independent Python enumeration of the
stencil rule (*derived*):

| Case | Diagonal 7.25 / 2 / 0.25 | Off-diagonal −1 / −0.5 / −0.25 |
| --- | --- | --- |
| padded | 8 / 56 / 0 | 24 / 48 / 216 |
| zero face | 8 / 40 / 16 | 24 / 40 / 144 |
| unpadded | 64 / 0 / 0 | 384 / 0 / 0 |

| Check | Against | Measure | -O0 | -O2 | Limit |
| --- | --- | --- | --- | --- | --- |
| counts | the windows (8/56, 16/40/8, 64, and 216/296 at n = 8) by value and voxel by voxel; 352 and 448 nonzeros; H's entries by value (table above), which pin λ | mismatches | 0 | 0 | 0 |
| symmetry | H = Hᵀ by value, three cases | mismatches | 0 | 0 | 0 |
| curvature | every Cholesky pivot > 0; λ ≤ vᵀHv/vᵀv ≤ 13.25 for the unit vectors and x_true | violations | 0 | 0 | 0 |
| transforms vs matrix | H by transforms, column by column, four cases including −H | normwise | 7.6e-17 | 1.8e-16 | 1e-12 |
| stencil vs matrix | H by the stencil without a matrix | normwise | 0 | 0 | 1e-12 |
| stencil vs transforms 16 | at n = 8, m = 16, on x_true and two fixed vectors | normwise | 3.0e-16 | 2.9e-16 | 1e-12 |
| imaginary parts | of every inverse transform | max rel | 3.8e-16 | 4.3e-16 | 1e-12 |
| precond vs cholesky | P⁻¹ by transforms against C^T (K_M + λI)⁻¹ C, m = 8 and the unpadded m = 4 | normwise | 2.6e-16 | 3.1e-16 | 1e-12 |
| cholesky vs true | Cholesky(H, H x_true) against x_true, three cases | normwise | 2.0e-16 | 2.2e-16 | 1e-12 |
| pcg vs cholesky | the solve from 0 and from Q17's guess, padded and zero face | normwise | 8.4e-16 | 8.8e-16 | 1e-12 |
| pcg true residual | \|b − H x\| / \|b\| by the explicit matrix | normwise | 1.1e-15 | 1.0e-15 | 1e-12 |
| unpadded one step | the solve capped at one iteration against x_true, and its true residual | normwise | 3.8e-16 | 2.6e-16 | 1e-12 |
| statuses | see the list below | mismatches | 0 | 0 | 0 |
| zero rhs | b = 0 from a nonzero guess: x = 0 exactly after no iteration | mismatches | 0 | 0 | 0 |

The cases of "statuses":
- the unpadded case converges after exactly 1 iteration;
- the padded case capped at 2 stops at the limit after 2;
- −H is refused at the first step, with the guess untouched;
- an exact guess is returned after 0 iterations;
- a NaN in b is refused as not finite;
- the padded and zero-face solves converge.

The largest error is 1.1e-15, 950 times below its limit. "Stencil vs matrix" is exactly 0: on unit vectors
both routes compute the same small dyadic products.

**Reported, not gated** (from the driver, `keep/drivers/mlxf_oracle_pcg_main.f90`; -O2 numbers below):
- At -O0 the iteration counts are the same. The true residuals differ at rounding level: 7.2e-16, 7.6e-16,
  1.1e-15, 3.2e-16 and 6.4e-15.
- The Cholesky solution for b rounded once to single precision: relative error 2.0e-8 against x_true; smallest
  pivot 1.89.
- Iterations of the reference solve to ‖r‖ ≤ 1e-14 ‖b‖, with the true residual by the stencil:

  | Case | Start | Iterations | True residual |
  | --- | --- | --- | --- |
  | padded | 0 | 15 | 7.2e-16 |
  | padded | x0 = 1 (the driver's guess, not Q17's) | 15 | 7.0e-16 |
  | zero face | 0 | 41 | 9.1e-16 |
  | unpadded | 0 | 1 | 3.2e-16 |
  | 16³ variant | 0 | 20 | 6.4e-15 |

  The 16³ variant's solution is 1.2e-14 from x_true. The full residual histories are in the run logs.
  - The padded case falls about tenfold every two iterations.
  - The zero face's history is not monotone, which the examples note allows. Its 41 iterations stay under the
    64 cap.
- Wall time 0.21 s at -O0 and 0.09 s at -O2, 6 MB, load 0.27.

**Exit.**
1. *Both builds without a warning:* met. `keep/drivers/build_level.sh` builds `mlxf_oracle_dft`, the module
   and the driver at `-O0 -g -fcheck=all` and `-O2`; there is no compiler output. `keep/phase3_pcg_build_{O0,O2}.log`.
   - At -O2, a class function result passed straight as an argument (`window()`) met gfortran's false
     "used uninitialized".
   - The fix is to store it in a local. Nothing was silenced.
2. *The self-checks inside decision 5:* met, 14 of 14 at both levels, table above. `keep/phase3_pcg_run_{O0,O2}.log`.
3. *One negative control per check:* met, "14 of 14 checks covered". `keep/drivers/plants_pcg.py` uses 19
   plants in copies, `keep/phase3_pcg_controls.log`. Among them:
   - the plan's wrong stencil sign, in the explicit matrix and in the stencil without a matrix;
   - an asymmetric window product, and neighbours weighted −2;
   - the spectrum's period m − 1;
   - the preconditioner without λ;
   - the back substitution reading the wrong triangle;
   - steepest descent, and the iterate updated along z;
   - no curvature guard, no zero-RHS branch, no stop before the first iteration, and a NaN b taken for zero;
   - λ = −0.25 and λ = 0.5;
   - a window off by one;
   - the dense preconditioner's sign;
   - an imaginary input;
   - a division by zero.

   The window plant passed every check at first: at n = 4 its counts coincide with the right ones (8 and 56).
   "Counts" now compares the window voxel by voxel too, and the plant fails it.
4. *Formatters and the static gate:* met. Both formatters ran on the module and the driver, and their
   `--check` passes. `scripts/check_tree.sh` passes, with the expected warning for the three untracked new
   files. `keep/phase3_check_tree_end.log`.

**Review.** A read-only subagent reviewed the module against part B of the examples note, C3, the threshold map
and the skill. It confirmed the embedding, the crop, S on both sides, the stencil and d(q), the preconditioner,
the Cholesky factor and substitutions, the recurrences, the guard before the division, the statuses and the
counts. It found three defects and two smaller points, all fixed before the final runs above:
- *The stop rule was never applied to r0.* An exact guess gave κ = 0 and status 2. The solve now returns the
  guess after no iteration; plant q17 shows the new status check fails without it.
- *A NaN b was taken for b = 0.* The test `.not. (‖b‖ > 0)` is true for NaN, so it reported "converged". The
  zero test is now `‖b‖ ≤ 0`, and a non-finite b or x0 returns status 3; plant q18.
- *No check pinned λ.* Every route shares it, so λ = 0.5 passed everything. H's entries are now counted by value
  against the derived table; plant q19.
- *The 8-cube's window was not counted.* It now is.
- *C3 said the solve returns the true residual.* It cannot, its five arguments being taken. C3 is amended: the
  caller computes it with the explicit matrix, as the self-check does.

**Decisions taken under delegation:**
- *The class design*, for the reason above.
- *Status 3 for a non-finite b or x0*, added to C3's statuses after the review.
- *The stop before the first iteration.*
- *The value-count table of H*, derived by an independent script, which pins λ and the window.
- *The reported solves.* The driver's second padded case starts from x0 = 1, not from Q17's guess; Q17's guess
  is used in the gated check.

**What it means, in short:** the PCG oracle K8 will be judged against exists. Its explicit stencil matrix, the
same operator without a matrix and by transforms, and the preconditioner by transforms and by a Cholesky inverse
agree within 3.1e-16. Its Cholesky and PCG solutions reach x_true and each other within 1e-15. The solve's
contract (one step when unpadded, the limit, the refusal of −H before dividing, the zero and non-finite
right-hand sides) holds exactly, and every check fails under at least one planted error. The 16³ variant runs
without a dense matrix in 20 iterations. Its build under GNU Fortran 16.2 and its comparison with MLX wait for
the Mac (decision 8).

### Phase 4, the report: done (2026-11-24, 20:22 to 20:27 EST, dell2)

One unattended session. Machine dell2, load at most 0.22 (*measured*). Base `dc3f5d7`, the working tree
holding Phases 0 to 3. Rulings: none. Files changed:
- `doc/implementation_notes/completed/mlxf_oracles_report.md` (new);
- this entry.

No history entry (decision 10).

**Final evidence, on the tree as left:**
- **The rebuild.** All three modules and their drivers, built from empty module directories at `-O0 -g
  -fcheck=all` and `-O2`, give no compiler output (`keep/phase4_final_build_{O0,O2}.log`). The self-checks pass
  (DFT 12, projection 26, PCG 14), and their output is identical to each phase's own logs
  (`keep/phase4_final_run_*`).
- **The repository's CMake flag sets** (*measured*, an extra probe that gates nothing):
  - the flags: `cmake/CompilerConfig.cmake`'s Debug set (`-fcheck=all -Wunused -Wuninitialized`) and Release
    set (`-O3`), with `-Werror`;
  - the result: all three modules and drivers build without a warning under gfortran 15.2, and the
    self-checks pass;
  - the log: `keep/phase4_repo_flags.log`.
- **Compile and run times** (*measured*, load 0.15 to 0.22, `keep/phase4_timings.log`):
  - compiling a module takes 0.18 to 0.41 s at -O0 and 0.34 to 1.20 s at -O2;
  - running a self-check takes 0.00 to 0.21 s;
  - memory stays at or below 8 MB.

**Exit.**
1. *The report exists:* met, `doc/implementation_notes/completed/mlxf_oracles_report.md`. It follows section 8
   of `doc/how2s/how2write_agent_plans.md` and holds:
   - what was learned; the changes by phase, pointing to `review/phase_N.diff`;
   - the decisions and deviations; the evidence; what is left open; a commit message;
   - the drivers and the build recipe, quoted (decision 6);
   - the exported names, the table of errors at both levels, and what the Mac integration must do (decision 8).
2. *`scripts/check_tree.sh` passes:* met. `keep/phase4_check_tree_end.log`.
3. *`git status` shows only file-table paths:* met. The paths are the plan, the three oracle modules and the
   report. `keep/phase4_final_git_status.log`.

**Decision taken under delegation:** the extra compile with the repository's own flag sets. It is not a gate,
but it removes one unknown from decision 8's Mac build: the flags and `-O3` are covered, the compiler version
is not.

**What it means, in short:** the run is complete. Three plain-Fortran oracles exist, are held to closed forms
with every check shown able to fail, and are documented for review. What remains is the maintainer's: the
reading, the Mac Debug and Release build under GNU Fortran 16.2, and the toys' testers.

### The Mac integration at the review (2026-11-24, 20:30, the M5 Ultra, Claude in the maintainer's session)

Decision 8, done in a scratch copy of the checkout at `c129772` with the run's `full.diff` applied
(*measured*):

- **Standalone, decision 6's recipe under GNU Fortran 16.2.0** (`-std=f2018 -Wall -Wextra -Werror`, at
  `-O0 -g -fcheck=all` and at `-O2`), with the run's own drivers fetched from dell2: no compiler output for
  any module or driver. The self-checks pass at both levels: transforms 12 of 12 (largest error 7.98e-15),
  projection 26 of 26 (1.26e-15), PCG 14 of 14 (1.05e-15 at `-O0`, 1.04e-15 at `-O2`). These are dell2's
  numbers under 15.2.0 to the digits printed.
- **In the repository's builds** (the three modules compile into `mlxf_test_exec`): Debug and Release from
  scratch with `MLXF_WERROR=ON`, no warning; the fast gate 8 of 8 in both; `unit_kernels` 993 checks
  unchanged; `scripts/check_tree.sh` passes; both formatters report the three files in form.
- **Not done here:** testers and registry rows. The modules have no caller in the test executable until the
  toys' plans (K2, K6, K8) add theirs, so nothing in the gate runs the self-checks yet.

### The review against SIMPLE's source (2026-11-24, 20:50, Claude in the maintainer's session)

The run could not read SIMPLE. An independent reader compared the three modules with SIMPLE at `d354efee2`,
by reading only. **No internal error was found:** the fold is the expansion's transpose, the scatter the
gather's, the numerator's conjugation and the transforms' signs and normalisations are right, and the explicit
matrices share no code with what they check.

**The oracles follow the examples note, and SIMPLE differs from it in six places.** A toy that mirrors SIMPLE
would fail these oracles there, or pass them while computing something else. None is declared as a
difference from SIMPLE in the contract above (it declares the formulas, not SIMPLE's).

1. **K6, the insertion.** The oracle's scatter is the adjoint of the padded gather: padded coordinates,
   periodic wrap, Friedel fold. That is the PCG lattice's geometry. `insert_plane_oversamp` of the gridding
   backend deposits on the native grid without the padding factor, scales the data by 4, drops the deposits
   that leave the grid or fall at `h < 0`, and skips samples beyond the Nyquist disk.
2. **K8, the operator.** The oracle solves `H = S K S + lambda I` with a soft window `S` inside the operator.
   SIMPLE's solver sees `P (K + lambda I) P` with a binary mask `P`; the soft window only multiplies the
   result.
3. **K8, the preconditioner.** The oracle's is the reciprocal of the operator's own diagonal and is positive
   definite. SIMPLE's `apply_precond` brackets the transforms by the Kaiser-Bessel envelope, uses the density
   plus a shell floor, is zero where nothing was measured or outside the data sphere, and closes with the
   mask.
4. **K8, the solve.** SIMPLE's `pcg_solve` stops on a relative residual of 1e-4, on a step test, or after 50
   iterations, recomputes the residual every 25 iterations, and throws on a zero right-hand side or a
   non-positive first product. The oracle iterates to 1e-14 with its own statuses.
5. **The packed adjoint.** The oracle folds the `h < 0` half into its mate with multiplicities. SIMPLE reads
   the stored half and relies on both Friedel mates having been scattered. The two agree only for
   Friedel-complete, conjugate-symmetric input (declared here as Q10).
6. **The projector's wrap along the first dimension.** The oracle wraps with period M. SIMPLE's `cyci_1d`
   wraps over `[-M/2, M/2]`, a period of M + 1, so the tap at `M/2 + 1` reads `-M/2`. Only the two boundary
   queries of the fixture reach it.

**Two checks are weaker than they look.**
- No check pins the window's `beta`: the gather, the matrix and both window checks take the same constant. Its
  formula does equal SIMPLE's.
- "pack expand" builds its Hermitian field with the mirror the expansion uses, and nothing compares it with
  the phantom's transform.

**What follows.** The oracles stand for what they state: the projection inside the grid (K2), the adjoint
pair, and the PCG lattice's insertion. Before K6 and K8 are planned they gain SIMPLE's forms beside the
note's (the gridding insertion with its density correction, the masked operator, SIMPLE's preconditioner and
stopping rules), and the two weak checks are replaced. That is run `mlxf_oracles3` on dell2 ([`mlxf_oracles3.md`](mlxf_oracles3.md)), whose section 9 holds
SIMPLE's formulas as the same reader extracted them.

