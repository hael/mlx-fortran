# Host oracles for the polar objectives, the shift map and the pose objective (run `mlxf_oracles2`, on dell2)

Status, 2026-11-24: planned. The maintainer told the batch to proceed, so decisions 1 to 11 stand as
recommended and any of them may be overturned at the review. Base: the maintainer's commit of this note and of
run `mlxf_oracles`' result (the run records its HEAD). SIMPLE's mathematics is stated in section 9 as read at
`d354efee2`. Supersedes: none. Depends on: dell2 for plain Fortran (validated: yes, runs `mlxf_dell2_bringup`
and `mlxf_oracles`, 2026-11-24); `mlxf_oracle_dft` (validated: yes, delivered by `mlxf_oracles` and rebuilt on
the Mac under GNU Fortran 16.2); section 9's formulas (validated: read from SIMPLE's source by two readers,
key expressions quoted and spot-checked; not yet run against SIMPLE).

## 1. Why

Three deliverables of the kernel families still have no oracle: K4 (the shift lattice and the map
reductions), K5 (the pose objective of continuous refinement) and K7 (the cc finish and the classic
reductions). dell2 is free, cannot build the library, and has just delivered the first three oracles in 72
minutes. Writing these there puts them ahead of their kernels.

The first oracles followed the examples note. These follow SIMPLE's own mathematics, which the run cannot
read: SIMPLE is not on dell2. Section 9 therefore carries every formula the oracles need.

## 2. Contract

- **Plain Fortran, no MLX.** Each oracle is one module under `src/test/` that imports intrinsic modules and
  `mlxf_oracle_dft` only. It does not import `mlxf`, `mlxf_test_utils`, `mlxf_test_defs` or any module that
  reaches the library.
- **The mathematics is section 9's, computed directly in double precision.** An oracle evaluates the
  definitions: plain sums over samples, the rotation as an index shift on the full ring, the shift as a phase.
  It does not take SIMPLE's computational route (memoised ring transforms, the Bessel series, single
  precision) as its primary one. Where SIMPLE's route defines the result (the truncation of the Bessel
  series), that form is exported beside the direct one, under its own name.
- **Held to closed forms and second routes here, compared with MLX and with the existing polar oracle
  later.** dell2 cannot compile the existing polar oracle, which imports the assertion module. The agreement
  of the two is checked on the Mac at the review (decision 9).
- **The shared test files are not touched,** and no tester or registry row is added. Constants stay local
  to a module: rule `defs` refuses a constant imported from another oracle; procedures may be imported.
- **The house rules for Fortran hold** (skill `mlxf-modern-fortran`): layout, at most five dummy arguments
  (a record beyond), one `public ::` block, no `block`, no `==` on reals, comments that stand on their own.

### What the check found (2026-11-24)

- **The first oracles' recipe works on dell2 and on the Mac** (run `mlxf_oracles`, its report and the
  review's Progress entry): modules that import intrinsic modules and each other's procedures compile alone
  under `-std=f2018 -Wall -Wextra -Werror`, and build inside the repository's Debug and Release trees.
- **`mlxf_oracle_dft` exports** `oracle_dft_1d`, `oracle_idft_1d`, `oracle_dft_3d`, `oracle_idft_3d` (forward
  unnormalised with a negative exponent; inverse positive and normalised) and four error helpers
  (`oracle_flat`, `oracle_rel_error`, `oracle_finite_or_inf`, `oracle_all_finite`).
- **GNU Fortran 15.2 under `-Werror` gives false "(maybe-)uninitialized" warnings** on an unallocated
  allocatable assigned from a function result. Explicit allocation avoids them.
- **A check that compares a quantity with code sharing its error cannot fail.** The first run found five
  such checks by planting errors. Decision 7 asks the same here.
- **The design note was wrong about the pose objective.** It said a cubic window over 64 voxels. SIMPLE's
  `gather_packed_bspline3_window_grad` is a quadratic B-spline on three taps per axis around the nearest
  grid point (27 voxels). The note is corrected; section 9.3 has the formulas.
- **SIMPLE has two correlation objectives.** The memoised one (`gen_corrs`) has no shell weights. The direct
  double-precision one and the shift map's weight each shell by `k`. Section 9.1 gives both; the oracle
  exports both under separate names and does not choose.
- **A direct evaluation of the shift map exists already,** private to the Mac's shift-map tester. The module
  written here is independent of it and replaces it when K4's plan adds the tester.

## 3. Decisions and rulings

1. (2026-11-24, recommended) **Scope:** three oracle modules for K7, K4 and K5. No kernel, no tester.
2. (2026-11-24, recommended) **The modules,** all in `src/test/`:
   - `mlxf_oracle_polar_objfun` (K7, and the direct route K4 rests on): the Euclidean loss and the two
     correlations of section 9.1 at any rotation and shift, the in-plane reductions, and the reductions over
     references of section 9.1.5;
   - `mlxf_oracle_polar_shiftmap` (K4): the grid, the cell, the truncated Bessel form, the areas, the mode
     and the width of section 9.2;
   - `mlxf_oracle_pose` (K5): the prepared reference volume, the quadratic B-spline gather with its
     gradient, the two objectives with their gradients and matrices, the shift-only terms, and a reference
     damped least-squares solve, all of section 9.3.
3. (2026-11-24, recommended) **Each module exports its self-check** as a procedure returning labels, largest
   errors and limits, in the form of the first oracles (`oracle_dft_selfcheck(labels, errors, limits)`).
4. (2026-11-24, recommended) **Fixtures,** small and generated inside the modules from closed forms (no
   random numbers):
   - **Polar:** `pftsz` 16 (32 rotations), shells 2 to 9, box 32; two references and two particles built
     from smooth trigonometric rings; a positive real CTF modulus that depends on the angle with period
     `pftsz`; noise variances that grow with the shell. A second size, `pftsz` 12, checks that nothing is
     tied to 16.
   - **Shift map:** the polar fixture, with radii that give at least three `rho` values and an `nalpha` that
     is not a power of two.
   - **Pose:** a real volume on 16³ (padded to 32³) holding three Gaussian blobs of different widths at
     asymmetric positions; a particle generated from it at a known pose by the oracle's own model; shells 1
     to 7 for the Euclidean objective and 0 to 7 for the correlation, so that the central pixel's route is
     exercised.
5. (2026-11-24, recommended) **Thresholds,** frozen here, all in double precision:
   - identities between two exact routes (direct sums against ring transforms; the explicit 27-term gather
     against the separable one; areas against their closed sum): 1e-12 relative (*guessed*; the first
     oracles measured 1e-15 on like checks);
   - analytic derivatives against central differences, where the function is smooth along the step: 1e-7
     relative to the largest component (*guessed*: step 1e-5, truncation of order 1e-10, rounding of order
     1e-11);
   - the gather's derivative against a central difference inside one cell of the window, where the value is
     a quadratic and the difference is exact: 1e-10 relative (*guessed*);
   - the truncated Bessel form against the direct cell: 1e-6 absolute on the loss (*guessed* from the
     truncation rule, which drops orders whose Bessel value at the band's edge is below 1e-8);
   - indices, counts, grids, tie rules and reductions: exact.

   A check that misses its threshold is diagnosed, never loosened.
6. (2026-11-24, recommended) **Building on dell2:** the first oracles' recipe (`gfortran -std=f2018 -Wall
   -Wextra -Werror`, at `-O0 -g -fcheck=all` and at `-O2`), with the drivers under `scratch/keep/drivers/`
   and quoted in the report.
7. (2026-11-24, recommended) **Negative controls.** For each check, a planted error is shown to fail it,
   then removed. The plants include the traps of section 9.4, one each: a dropped conjugate on the wrapped
   half ring, the shift applied after the rotation, the `-cos` of the phase turned to `+cos`, a 0-based
   rotation index, the unweighted and the `k`-weighted correlation exchanged, the band's power replaced by
   the full power in the map, the rotation's transpose in the pose's pixel map, `floor` in place of `nint`
   in the gather, the shift phase's sign, the central pixel counted twice.
8. (2026-11-24, recommended) **Where section 9 and a check disagree.**
   - A gradient is the derivative of its objective. If section 9's gradient formula fails the
     central-difference check of section 9's objective, the objective stands, the gradient is corrected to
     its derivative, and the disagreement is recorded.
   - A matrix, a clamp, a tie rule or a truncation is SIMPLE's choice and cannot be derived. If the
     zero-residual identity of decision 10 fails for a matrix as section 9 states it, the run stops.
9. (2026-11-24, recommended) **Integration on the Mac, at the review:** the diff is applied to the
   maintainer's checkout and built in Debug and Release under GNU Fortran 16.2. There
   `mlxf_oracle_polar_objfun` is compared with the existing polar oracle's distances, and
   `mlxf_oracle_polar_shiftmap` with the shift-map tester's private evaluation, on their fixtures. The
   comparison with SIMPLE itself (one particle and reference dumped from a SIMPLE test program) is the
   maintainer's call and is listed in the report as open.
10. (2026-11-24, recommended) **Checks the pose oracle must have,** because they fix factors section 9 cannot
    prove:
    - at a particle generated by the model at the same pose (zero residual), the Euclidean objective is zero,
      its gradient is zero, the curvature scale is one, and the returned matrix equals the second
      derivative of the objective by central differences of the analytic gradient;
    - at a particle that is a positive multiple of the model, the same for the correlation objective;
    - away from the solution, each gradient equals the central difference of its objective, for all five
      parameters;
    - the shift-only terms equal entries 4 to 5 of the full terms;
    - the reference solve returns a planted pose from a displaced start (0.05 rad and 0.5 pixel) to 1e-6 rad
      and 1e-6 pixel (*guessed*), and its objective never increases on an accepted step.
11. (2026-11-24, recommended) **Time boxes** (*guessed* from the first run's 20, 12, 22, 16 and 4 minutes):
    Phase 0, 30 minutes; Phase 1, 90; Phase 2, 90; Phase 3, 180; Phase 4, 30. **The record:** Progress in
    this note; the report in `completed/mlxf_oracles2_report.md`; the history entry at the review.

Defaults taken without a question (cheap to veto): the names of the exported procedures, chosen by the run
within the house rules and listed in Progress; records for argument lists beyond five; what an objective
returns where SIMPLE has no guard (a zero denominator), recorded as a choice.

## 4. Not in this plan

- The posterior draw: the existing polar oracle has it.
- SIMPLE's particle preparation before the pose objective (normalisation, masking, phase flipping). The
  oracle starts from the Fourier pixels, the CTF modulus and the noise variances.
- The 2D variants of the reductions (`snhc`'s random rotation among improvers).
- Any comparison with SIMPLE's own output.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | baseline and contract | the static gate on the untouched copy; section 9 restated with every choice taken |
| 1 to 3 | tests-only code (new modules) | standalone builds without a warning at both levels; the self-checks inside decision 5's thresholds; each negative control failing; formatters and `scripts/check_tree.sh` |
| 4 | documentation | `scripts/check_tree.sh`; only file-table paths changed |

## 6. Acceptance

- Decision 5's thresholds, each tagged with its origin, frozen before an oracle is run.
- Decision 10's checks present and passing.
- Each self-check reports its largest error; the report tabulates them at both optimisation levels.
- **Reported, not gated:** the size of the difference between the direct cell and the truncated Bessel form
  per `rho`; the reference solve's iterations and damping history; the difference the small-shift rule of
  section 9.1.2 would make; compile and run times.
- **What dell2 cannot show:** agreement with the existing polar oracle, with an MLX kernel, and with SIMPLE.

## 7. Common rules and stop conditions

- No file outside the table. No shared test file. No threshold loosened, and no fixture changed to pass.
- `scripts/format_use_blocks.py` and `scripts/restyle_fortran.py` are called with `--check` or with explicit
  file names.
- The run writes its notes with the editor tools: the fence refuses a shell command whose text names a
  publish to the remote, a heredoc included.

**Stops:**
- section 9 is ambiguous or contradicts itself on a point an oracle needs, and decision 8 does not settle it;
- an oracle cannot meet a threshold after diagnosis;
- a module would need the library or a shared test file;
- the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no import that reaches the library; the negative controls; the static gate.

## 8. Phases

### Phase 0, the baseline and the contract

1. Record the machine and the base commit. Run `scripts/check_tree.sh` on the untouched copy.
2. Read section 9, the first oracles' report (`completed/mlxf_oracles_report.md`) and the three delivered
   modules.
3. Restate each oracle's contract in Progress: the definitions, the fixtures' sizes and counts worked by
   hand, and each point where section 9 leaves a choice, with the choice taken. Have the restatement read by
   an independent reviewer against section 9.

**Exit:** the gate passes on the base; the contract is in Progress.

### Phase 1, the polar objectives and reductions (`mlxf_oracle_polar_objfun`)

Section 9.1. The self-check includes: zero loss and unit correlation for a particle equal to the CTF times
the reference; the minimum at the planted rotation for a rotated copy; zero loss at a planted shift; the
direct sums against the ring-transform route through `mlxf_oracle_dft`; the bound |cc| ≤ 1; each reduction on
hand-made tables with ties.

**Exit:** the phase's gate of section 5.

### Phase 2, the shift map (`mlxf_oracle_polar_shiftmap`)

Section 9.2. The self-check includes: the grid's numbers worked by hand for two radii; the areas' sum; the
cell against the direct loss of Phase 1 on the band; the truncated Bessel form against the direct cell; the
mode's loop order on a table with ties; the width of a hand-made distribution; the cutoff's `-1`.

**Exit:** the phase's gate of section 5.

### Phase 3, the pose objective (`mlxf_oracle_pose`)

Section 9.3, with decision 10's checks.

**Exit:** the phase's gate of section 5.

### Phase 4, the report

The report in the order of `doc/how2s/how2write_agent_plans.md`, section 8. It includes the exported names
of each module, the table of errors at both levels, the drivers, every choice taken where section 9 left
one, every disagreement of decision 8, and what the Mac integration must do.

**Exit:** the report exists; `scripts/check_tree.sh` passes; `git status` shows only file-table paths.

## 9. SIMPLE's mathematics, as read at `d354efee2`

Stated for the oracle, not as SIMPLE codes it. File names are SIMPLE's, for the maintainer's check.

### 9.1 The polar objectives (`pftc/simple_polarft_{core,geom,memo,corr}.f90`)

**9.1.1 Geometry.** `P = pftsz` angular samples on the half ring, `N = nrots = 2 P` rotations, shells
`k = kfrom .. kto` (integers, the radius in Fourier-index units). The angle of sample `p` is
`theta_p = 2 pi (p - 1) / N`. Its Cartesian coordinate is `(h, k) = (k sin theta_p, -k cos theta_p)`.
- A complex half ring `z(1:P)` extends to the full ring by `z(p + P) = conj(z(p))`.
- The CTF modulus `C(p, k)` is real, non-negative, and extends with period `P` without a conjugate.
- The reference is rotated, never the particle. For rotation index `irot = 1 .. N`, with `n = irot - 1`:
  `R_n(A)(p) = A_full(p - n)`, indices taken modulo `N` on the full ring. For `irot ≤ P` this is
  `A(p - n)` for `p ≥ irot` and `conj(A(p - n + P))` for `p < irot`.
- The in-plane angle of `irot` is `(irot - 1) 360 / N` degrees.

**9.1.2 Shifts.** A shift `s = (x, y)`, in pixels of the box, in the reference's frame, is the phase
`S(p, k) = exp(+i (2 pi k / box)(x sin theta_p - y cos theta_p))`.
- It multiplies the unrotated reference. The product `S A` is then extended and rotated as in 9.1.1, so a
  wrapped sample is `conj(S A)`.
- `|S| = 1`: the reference's power does not depend on the shift.
- A shift `u` in the particle's frame corresponds to `s = M u` with `M = [[c, s], [-s, c]]`, `c` and `s` the
  cosine and sine of the in-plane angle of `irot`.
- SIMPLE treats shifts with `x² + y² ≤ 1e-5` as zero. The oracle applies the phase always; the difference is
  reported.

**9.1.3 The Euclidean objective.** With `X(p, k)` the particle's half ring, `sigma2(k) > 0` the noise
variances of the particle's half set, and `w_k = k / sigma2(k)`:

```
wsq      = sum_k w_k sum_{p=1..P} |X(p,k)|^2
L(n, s)  = sum_k w_k sum_{p=1..P} | C(p,k) R_n(S A)(p,k) - X(p,k) |^2 / wsq
         = 1 + (refpow(n) - 2 cross(n, s)) / wsq
refpow(n)   = sum_k w_k sum_p C(p,k)^2 |R_n(A)(p,k)|^2
cross(n, s) = sum_k w_k sum_p Re[ conj(X(p,k)) C(p,k) R_n(S A)(p,k) ]
```

- **As a distance:** `L` itself, with no lower clamp; a value above `-log(1e-10)` (23.0259) is marked
  invalid.
- **As a score:** `exp(-max(0, L))`.
- **The in-plane best:** the first strict minimum of the distance (the lowest `irot` among equals), or the
  first maximum of the score.
- **Equivalent route** (for a self-check, never the oracle's own): the ring of length `N` built as
  `[z, conj(z)]`, transformed forward; `c(b) = sum_k w_k [FT(C²)(b) conj(FT(|A|²))(b) - 2 FT(X C)(b)
  conj(FT(S A))(b)]` over bins `1 .. P + 1`; the real inverse transform `r(n)` of `c`; `L(n) = 1 + r(n) /
  (2 N wsq)` with the unnormalised inverse.

**9.1.4 The correlations.** SIMPLE has two; the oracle exports both.
- **Unweighted** (the memoised `gen_corrs`):
  `cc(n, s) = sum_k sum_p Re[conj(X) C R_n(S A)] / sqrt( sum_k sum_p C² |R_n(A)|² · sum_k sum_p |X|² )`.
- **Weighted by shell** (the direct form and the shift map): the same with `w_k = k` on the numerator and on
  the reference's sum, and `sum_k k sum_p |X|²` for the particle.
- Neither guards a zero denominator. The range is [-1, 1]; higher is better. Callers clamp a negative best
  to zero; the oracle returns the unclamped value and offers the clamp separately.

**9.1.5 Reductions over references** (`strategies/search/simple_strategy3D_*.f90`). Each reference
contributes its in-plane best score.
- **Store:** a reference keeps its larger score; an equal score does not replace the stored one.
- **Greedy:** the largest score over all references; the lowest reference index among equals.
- **Best k:** the `k` largest, in descending order. SIMPLE's order among equal scores comes from an unstable
  sort and is not defined. The oracle puts the lower index first and says so.
- **Stochastic hill climbing.** Inputs: a visiting order (a permutation of the references in which the
  previous reference has been exchanged with the last element), and
  `prev_corr = max(0, the previous reference's in-plane best at zero shift)`. The references are visited in
  order; the first whose score is strictly greater than `prev_corr` wins and the scan ends. If none is, every
  reference has been scored and the greedy rule decides.

### 9.2 The shift map (`pftc/simple_polar_shiftmap.f90`, `simple_polarft_shiftmap.f90`)

**9.2.1 Setup.** `prior_w = 1 / (2 sigma_px²)`. `kscreen = max(kfrom + 1, kto / 2)` with integer division.
Two maps share the band `kfrom .. kscreen`: the screen map with radius `radius_px` and the window map with
radius `radius_win`. Below, `kstop` is the band's last shell.

**9.2.2 Grid.**
- `step = box / kstop / 4` in real arithmetic. `nrho = floor(radius / step) + 1`; if that is below 2,
  `nrho = 2` and `step = radius`. `rho_i = (i - 1) step`.
- `nalpha` is the smallest integer whose prime factors are all in {2, 3, 5, 7} and that is at least
  `2 ceiling(2 pi kstop rho_max / box) + 3`. `alpha_j = (j - 1) 2 pi / nalpha`.
- The cell `(ialpha, irot, irho)` stands for the shift `rho_i (cos alpha_j, sin alpha_j)` in the reference's
  frame, at rotation `irot`.

**9.2.3 The cell.** The Euclidean loss of 9.1.3 on the band `kfrom .. kstop`, normalised by the band's own
power: `L = 1 + (refpow(irot) - 2 cross) / ptclpow`, with every sum over `k ≤ kstop` and
`ptclpow = sum_{k ≤ kstop} w_k sum_p |X|²`. For the correlation objective the cell is
`cross / sqrt(refpow ptclpow)` with `w_k = k`.

**9.2.4 The truncated Bessel form.** With `z_k = 2 pi k rho / box`, the phase of 9.1.2 at the cell's shift is
`exp(i z_k sin(theta_p - alpha))`, which the Jacobi-Anger expansion writes as a sum over integer orders `m`
of `J_m(z_k) exp(i m (theta_p - alpha))`. SIMPLE keeps the orders `|m| ≤ nharm(rho)` for every shell at that
`rho`, where, with `z = 2 pi kstop rho / box`: start at `m = max(0, ceiling(z))`; while `|J_m(z)| ≥ 1e-8`
increase `m`; `nharm = max(0, m - 1)`. The oracle exports the cell computed with exactly these orders, beside
the direct cell.

**9.2.5 Areas.** The cell's area is `pi (hi² - lo²) / nalpha`, where `lo` and `hi` are the midpoints between
`rho_i` and its neighbours; for the first ring `lo = max(0, rho_1 - step / 2)`, for the last
`hi = rho_n + step / 2`.

**9.2.6 The mode.** For a temperature `temp`: `l = -temp L - prior_w rho² + log(area)`. The mode is the cell
with the largest `l`, with a strict comparison in the loop order `irho` outermost, then `irot`, then
`ialpha` innermost. It returns `irot`, `irho`, `ialpha` and `loss`, the cell's `L`.

**9.2.7 The width.** If a cutoff is given and `loss` exceeds it, `sdev = -1`. Otherwise, with a physical
temperature `tphys`: `lphys = -tphys L - prior_w rho² + log(area) - max over cells of the same expression`;
cells with `lphys ≤ -40` are skipped; `w = exp(lphys)`; `w0 = sum w`; `w1(:, irot) = sum w (x, y)` with the
cell's shift in the reference's frame; `w2 = sum w rho²`;
`mean = sum over irot of matmul(w1(:, irot), M(irot)) / w0` with `M` of 9.1.2;
`sdev = sqrt(max(0, w2 / w0 - |mean|²))`.

**9.2.8 Production's temperatures.** `temp = prob_beta pi wsq_band / (2 pftsz)` and
`temp_phys = temp / prob_beta`, with `prob_beta = 0.3` and `wsq_band` the band's `ptclpow`.

### 9.3 The pose objective (`cftc/simple_cartft_calc.f90`, `interp/simple_cartesian_fourier.f90`, `utils/math/simple_lm_solver.f90`)

**9.3.1 The reference.** A real volume `v` on `box³` is embedded at the centre of `n³`, `n = 2 box` (offset
`(n - box) / 2`), with the origin at index `c = n / 2 + 1`. It is multiplied in real space by
`rho(x) rho(y) rho(z)`, `rho = kb_env / bspline_env`:
- `bspline_env(x) = 0.75 + 0.25 cos(2 pi (x - c) / n)`;
- `kb_env(x) = sum_{q = -1..1} w_q cos(2 pi q (x - c) / n)`, with `w_q = apod(q) / sum apod`, then divided by
  its value at `c`;
- `apod(x) = I0(beta sqrt(1 - (2 x / 3)²)) / 3`, `beta = pi sqrt((9/4)(1.5)² - 0.8)`. SIMPLE evaluates `I0`
  by a polynomial approximation; the oracle uses the converged series. The reader's values:
  `w_0 = 0.6906488`, `w_±1 = 0.1546756` (*derived*; the run recomputes them).

The transform is `F(q) = (1 / box³) sum_x rho rho rho v_pad(x) exp(-2 pi i q · (x - c) / n)` for integer `q`,
periodic with period `n` in each component. `v` is real, so `F(-q) = conj(F(q))`. The oracle may hold the
whole cube; SIMPLE holds the half with the first component non-negative.

**9.3.2 The particle.** Fourier pixels `observed(h, k)`, complex, for `h, k` in `-box/2 .. box/2`.
- `shell(h, k) = nint(sqrt(h² + k²))` where `h² + k² ≤ (box/2)²`; other pixels are out.
- The band is `kfrom ≤ shell ≤ kto`.
- For the Euclidean objective `w = 1 / sqrt(sigma2(shell))`; for the correlation `w = 1`.
- `X = observed w` and `T = |CTF(h, k)| w`. The CTF enters as a modulus that multiplies the model.
- The half plane is `k = -kto .. kto`, with `h` from 0 when `k > 0` and from 1 otherwise, up to `kto`. The
  central pixel is handled apart, once, and only when `kfrom = 0`.
- `Ppow = 2 sum_half |X|² + |X(0,0)|²` (the last term only when the central pixel is in the band).

**9.3.3 The pose.** A rotation matrix `R` and a shift `(s1, s2)` in pixels of the box.
- From Euler angles `(e1, e2, e3)`: `R = Rz(e3) Ry(e2) Rz(e1)`, with
  `Rz(a) = [[c, s, 0], [-s, c, 0], [0, 0, 1]]` and `Ry(a) = [[c, 0, -s], [0, 1, 0], [s, 0, c]]` (rows listed).
- The three rotation parameters are a rotation vector `omega` applied on the right:
  `R' = R exp([omega]x)`, `[omega]x = [[0, -o3, o2], [o3, 0, -o1], [-o2, o1, 0]]`. The shift parameters add.
- Pixel `(h, k)` reads the volume at `loc = 2 Rᵀ (h, k, 0)ᵀ`, that is
  `loc_j = 2 (h R(1, j) + k R(2, j))`.

**9.3.4 The gather.** Per axis, `m = nint(loc)` (halves away from zero), `t = loc - m` in [-1/2, 1/2], taps
`m - 1, m, m + 1` (wrapped with period `n`), weights `[(t - 1/2)² / 2, 3/4 - t², (t + 1/2)² / 2]` and slopes
`[t - 1/2, -2 t, t + 1/2]`. The value `V` is the sum over the 27 taps of the three weights' product times
`F`; the derivative along axis `a` replaces that axis's weight by its slope. No normalisation. The
derivatives are per unit of the padded lattice.

**9.3.5 The model and the objectives.** `wp = exp(+2 pi i (h s1 + k s2) / box) T(h, k)`; the model is
`M = wp V(loc)`; the residual is `r = M - X`.
- **Euclidean:** `L = (2 sum_half |r|² + |r_0|²) / Ppow`, where `r_0 = T(0,0) V(0) - X(0,0)` has no phase and
  enters only when `kfrom = 0`.
- **Correlation:** `cross = 2 sum_half Re(conj(X) M) + Re(conj(X_0) M_0)`,
  `mm = 2 sum_half |M|² + |M_0|²`, objective `= 1 - cross / sqrt(Ppow mm)`.
- If `Ppow` (or `mm`, for the correlation) is not above the square of the double-precision epsilon, the
  objective, gradient and matrix are NaN.

**9.3.6 The derivatives.** With `fh = 2 pi h / box`, `fk = 2 pi k / box`:
- `J_a = wp (grad V x loc)_a` for `a = 1, 2, 3`; `J_4 = i fh M`; `J_5 = i fk M`.
- Let `q = Im(conj(X) M)`, `u_a = Im(conj(J_a) M)`, `m2 = |M|²`. The sums below run over the half plane and
  are then doubled; the central pixel adds nothing to them.

  ```
  g_a  = 2 sum Re(conj(J_a) r)        g_4  = 2 sum fh q           g_5  = 2 sum fk q
  H_ab = 2 sum Re(conj(J_a) J_b)      H_a4 = -2 sum fh u_a        H_a5 = -2 sum fk u_a
  H_44 = 2 sum fh² m2                 H_45 = 2 sum fh fk m2       H_55 = 2 sum fk² m2
  ```
- **Euclidean:** gradient `= 2 g / Ppow`; matrix `= scale · 2 H / Ppow`, `H` symmetric, with
  `scale = min(20, max(0.05, wc / wpow))`, `wc = 2 sum (fh² + fk²) Re(conj(X) M)`,
  `wpow = 2 sum (fh² + fk²) m2`; the scale is applied only when `wpow` is above the floor of 9.3.5.
- **Correlation:** `G_a = 2 sum Re(conj(X) J_a)` for `a = 1, 2, 3`, `G_4 = -2 sum fh q`,
  `G_5 = -2 sum fk q`; `MG_a = 2 sum Re(conj(M) J_a)` for `a = 1, 2, 3` and `MG_4 = MG_5 = 0`;
  `Nrm = sqrt(Ppow mm)`. Gradient `= -G / Nrm + cross MG / (Nrm mm)`. Matrix
  `= scale · (H / mm - MG MGᵀ / mm²)`, with `scale = min(20, max(0.05, (wc / wpow) sqrt(mm / Ppow)))`.
- The result is the objective, the gradient in the order `(o1, o2, o3, s1, s2)`, and the 5 by 5 symmetric
  matrix.
- **Shift only:** entries 4 and 5 of the gradient and the lower right 2 by 2 block of the matrix.

**9.3.7 The reference solve** (the oracle's own, after SIMPLE's rules; in double precision).
- Scaling `sc = (0.1, 0.1, 0.1, 1, 1)`: `g_s = sc g`, `C_s = sc C sc`.
- Stop if `|g_s| < 1e-8`, or if the Cholesky factorisation of `C_s` meets a pivot not above
  `sqrt(eps) max|C_s|`.
- Step: solve `(C_s + mu diag(max(C_s,ii, sqrt(eps) max|C_s|, eps²))) d_s = -g_s`, `mu` starting at 1e-3;
  `d = sc d_s`. Cap the rotation part at 0.1 rad and the shift part at 1 pixel.
- `predicted = -g·d - dᵀ C d / 2` (unscaled). Not positive: reject. Below `1e-6 max(|f|, eps²)`: stop.
- Accept when `actual = f - f_trial > 0` and `actual / predicted ≥ 0.25`. If the ratio exceeds 0.75,
  `mu = max(mu / 2, eps)`. Stop when the step is below 1e-8 in both parts or `actual / |f| < 1e-6`.
- On a rejection `mu = min(mu m, 1 / eps)` and `m` doubles; `m` starts at 4 and returns to 4 on an
  acceptance. Eight rejections in a row end the solve. At most 40 iterations.
- The result is taken only if its objective is strictly below the start's.

### 9.4 Traps

1. The memoised correlation is unweighted; the direct correlation and the map's are weighted by `k`.
2. `w_k` holds `k`, and `sigma2` belongs to the particle's half set.
3. The shift comes first, the rotation second; the phase uses the reference's own angle; the `y` term is
   `-cos`.
4. A wrapped sample conjugates the product `S A`. The CTF modulus is never conjugated and has period `P`.
5. `irot` is 1-based.
6. The factor `2 N` of the ring-transform route is the ring's length times the two halves.
7. The map is normalised by the band's power, not the full `wsq`; `nharm` comes from `kstop`.
8. The pose's window is quadratic on 27 taps around the nearest point: not cubic, not 64, not `floor`.
9. `loc` uses `Rᵀ`; the increment is on the right; the padding factor 2 is in `loc` and nowhere else in the
   Jacobian.
10. The shift phase's sign is `+`, with the box and not the padded size, and it multiplies the model.
11. The transform's normalisation is `1 / box³` and the real-space origin is index `n / 2 + 1`.
12. The matrix is not the plain Gauss-Newton matrix: it carries the clamped scale, and the correlation's is
    the projected form.
13. The central pixel is counted once and has no Jacobian.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_oracle_polar_objfun.f90` (new) | the polar objectives and reductions | 1, 2 |
| `src/test/mlxf_oracle_polar_shiftmap.f90` (new) | the shift map | 2 |
| `src/test/mlxf_oracle_pose.f90` (new) | the pose objective and its reference solve | 3 |
| `src/test/mlxf_oracle_dft.f90` | only to export a helper two oracles would otherwise copy, its checks rerun | 1, 2, 3 |
| `doc/implementation_notes/planned/mlxf_oracles2.md` | this note: Progress | 0, 1, 2, 3, 4 |
| `doc/implementation_notes/completed/mlxf_oracles2_report.md` (new) | the report | 4 |

## Progress

(one entry per phase, written by the run)
