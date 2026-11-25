# Host oracles for the polar objectives, the shift map and the pose objective (run `mlxf_oracles2`, on dell2)

Status, 2026-11-24: delivered in the maintainer's session on the Mac (Progress) and rebuilt at the review
(Progress, last entry); it stays in `planned/` until the maintainer has read it. Decisions 1 to 11 stood as
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
| `src/test/mlxf_oracle_polar_objfun.f90` (new) | the polar objectives and reductions | 1, 2, 3 (a NaN guard; row extended by the run) |
| `src/test/mlxf_oracle_polar_shiftmap.f90` (new) | the shift map | 2, 3 (a comment; row extended by the run) |
| `src/test/mlxf_oracle_pose.f90` (new) | the pose objective and its reference solve | 3 |
| `src/test/mlxf_oracle_dft.f90` | only to export a helper two oracles would otherwise copy, its checks rerun | 1, 2, 3 |
| `doc/implementation_notes/planned/mlxf_oracles2.md` | this note: Progress | 0, 1, 2, 3, 4 |
| `doc/implementation_notes/completed/mlxf_oracles2_report.md` (new) | the report | 4 |

## Progress

(one entry per phase, written by the run)

### Phase 0, the baseline and the contract: done (2026-11-24, 21:12 to 21:40 EST, the Mac)

**Where and why.** The work was done on the Mac (Mac Studio, 30 cores, macOS 27.2, GNU Fortran 16.2.0 of
Homebrew, Python 3), in a scratch copy of the repository inside the maintainer's own session, not on dell2: the
commit a dell2 launch needs could not be made (git is read-only for agents). Base: `3b3f4fd` plus the
maintainer's uncommitted tree (this note, run `mlxf_oracles`' three modules and report), kept as a snapshot
beside the copy. Rulings: none. Nothing builds the library; no CMake, compile script or `mlxf_test_exec` is
run, and a timed job of the maintainer is waited for before each batch of builds. Evidence: `scratch/keep/`
of the run's work folder (`keep/` below). Numbers are *measured* unless tagged; fixture constants are *exact*.

**Exit.**
1. *The gate passes on the base:* met. `scripts/check_tree.sh` on the untouched copy: `check_tree: passed`,
   3.1 s, load 1.3, with the expected warning that the first run's three modules are untracked.
   `keep/logs/phase0_check_tree_base.log`.
2. *The contract is in Progress:* met, below (C0 to C3, the choices Q1 to Q46, the threshold map).
3. *Read by an independent reviewer against section 9:* a read-only subagent; its findings and what they
   changed are at the end of this entry.

**Dry run of the fixtures** (`keep/phase0/fixture_dry_run.py`, standard-library Python, no Fortran; log beside
it). The numbers the self-checks state as hand-worked were worked by hand first and agree with it:
- Pose, box 16: full-plane pixels per shell 0 to 7 are 1, 8, 12, 16, 32, 28, 40, 40 (177 in all); the half
  plane of shells 1 to 7 holds 88; the sum of count / 2^shell over shells 1 to 7 is 12.8125.
- Shift map, box 32, band 2 to 4 (`kscreen = max(3, 9 / 2) = 4`), `step = 2`: radius 5 gives `nrho = 3`,
  `rho_max = 4`, the bound 2 ceiling(pi) + 3 = 11 and `nalpha = 12`; radius 7 gives 4, 6, 13 and 14; radius
  1.5 gives the fallback `nrho = 2`, `step = 1.5`, the bound 7 and `nalpha = 7`. `nharm` per ring: 0, 10, 13,
  16 (and 0, 9 for the fallback). The areas sum to pi (rho_max + step / 2)^2: 25 pi, 49 pi, 5.0625 pi.
- The envelope's weights: beta = 6.486076530511, `w_0 = 0.6906487786`, `w_1 = 0.1546756107`: the reader's
  seven decimals hold.
- The pose's half-integer margins. The window's second derivative jumps where a coordinate is a
  half-integer, so a central difference is smooth only if no coordinate comes within the step's move
  (1.5e-4 lattice units for 1e-5 rad at shell 7, *derived*). The first candidate pose, Euler (0.7, 1.1,
  -0.4), had a margin of 4.5e-4; a scan of round triples (`keep/phase0/pose_margin_scan.py`) gave (0.6, 1.0,
  -0.4), with 6.0e-3 at the planted and 6.2e-3 at the displaced pose. That is the fixture (Q36).

#### C0, common to the three modules

- One module each in `src/test/`, no submodule. Imports: `iso_fortran_env`, `ieee_arithmetic`, procedures of
  `mlxf_oracle_dft`, and in the shift map the class and procedures of `mlxf_oracle_polar_objfun` (Q1). No
  constant crosses a module; no module-level variable; no exported behaviourless type.
- The self-check is `<x>_selfcheck( labels, errors, limits )` in the first oracles' form (decision 3): it
  asserts nothing, prints nothing and never stops. An exact check reports its mismatch count against the
  limit 0; a non-finite value reports +Inf.
- Storage is Fortran's: dimension 1 fastest, indices 1-based. Fixtures are closed forms, never
  `random_number`.

#### C1, `mlxf_oracle_polar_objfun` (Phase 1), section 9.1

- **Geometry.** `P = pftsz`, `N = 2 P`, `theta_p = 2 pi (p - 1) / N`. A half ring is stored as `z(1:P, 1:nk)`,
  the second index the shell `kfrom + i - 1`. The full ring is `z(p + P) = conj(z(p))`; the CTF modulus is
  real with period `P`. Rotation `irot = 1 .. N` with `n = irot - 1`: `R_n(A)(p) = A_full(1 + modulo(p - 1
  - n, N))`. The in-plane angle is `(irot - 1) 360 / N` degrees.
- **Shift.** `s = (x, y)` in pixels of the box, in the reference's frame: `S(p, k) = exp(+i (2 pi k / box)
  (x sin theta_p - y cos theta_p))` multiplies the unrotated half ring; `S A` is then extended (conjugated on
  the wrapped half) and rotated. `s = M u` for a shift `u` in the particle's frame, `M = [[c, s], [-s, c]]`
  by rows at the angle of `irot`.
- **Euclidean.** `w_k = k / sigma2(k)` with `k` the shell's integer radius; `wsq = sum_k w_k sum_p |X|^2`;
  `L(n, s) = sum_k w_k sum_p |C R_n(S A) - X|^2 / wsq`, computed as that plain sum of squared residuals. The
  distance is `L` unclamped; it is valid when `L <= -log(1e-10)`; the score is `exp(-max(0, L))`.
- **Correlations.** Unweighted: `sum Re[conj(X) C R_n(S A)] / sqrt(sum C^2 |R_n(A)|^2 sum |X|^2)`. Weighted:
  the same with `k` on every shell's term, the particle's sum included. Unclamped; `max(0, .)` is a separate
  function.
- **The ring-transform route,** exported under its own name and used only by the self-check: rings
  `[z, conj(z)]` of length `N`, forward transforms of `C^2`, `|A|^2`, `X C` and `S A` by `oracle_dft_1d`,
  `c(b) = sum_k w_k [FT(C^2) conj(FT(|A|^2)) - 2 FT(X C) conj(FT(S A))]` on bins 1 to `P + 1`, completed by
  `c(N - b) = conj(c(b))`, the unnormalised inverse `r(n)`, `L(n) = 1 + r(n) / (2 N wsq)`.
- **In-plane best.** Distance: the first strict minimum. Score and correlation: the first maximum (Q8).
- **Reductions.** Store: replace only if strictly larger. Greedy: the largest, the lowest index among
  equals. Best k: descending, the lower index first among equals. Stochastic hill climbing: visit `order`,
  the first score strictly above `prev_corr` wins; if none, the greedy rule over all (Q10).
- **Fixture.** Rings of point sources: `ring(theta, k) = e(k) sum_j a_j exp(-i (2 pi k / box) (x_j sin theta
  - y_j cos theta))`, `e(k) = 4 / (4 + k)`, which is Hermitian on the full ring by construction. Rotating by
  `n` evaluates it at `theta_p - 2 pi n / N`; shifting by `s` displaces every point to `(x_j - x, y_j - y)`:
  a closed form of `R_n(S A)` that uses no extension, no index shift and no phase of the module. Sizes: `P`
  16, shells 2 to 9, box 32 (16 x 8 samples a half ring, 32 rotations); and `P` 12, shells 2 to 7, box 24.
  References: points (x, y, a) = (1.5, -0.5, 1), (-2.25, 1, 0.6), (0.5, 2.75, -0.4) and (-1, -1.75, 0.8),
  (2.5, 0.75, 0.5), (0.25, -3, 0.7); a third pattern (3, 1.25, 0.5), (-0.75, -2.5, 0.45) as clutter. CTF
  modulus of particle i: `0.55 + 0.35 cos(2 theta_p - 0.3 k - 0.9 (i - 1))`, in [0.2, 0.9]. Variances:
  `0.5 + 0.1 k` and `0.8 + 0.05 k^2`. Generic particles: `C_1` times reference 1 at `n = 5`, `s = (0.75,
  -1.25)` plus 0.3 clutter; `C_2` times reference 2 at `n = 19`, `s = (-1.5, 0.5)` plus 0.3 clutter at
  `n = 7`. Planted particles, all from the closed form: the unrotated copy; rotations `n = 5` and `n = 21`
  (one below and one above `P`); the shift (1.25, -0.75); `n = 21` with that shift; a shift (0.5, -1.5) in
  the particle's frame applied after the rotation `n = 5`; and the copy scaled per shell by `c_k` = 1 on even
  and -0.5 on odd shells, whose loss and two correlations have closed forms in the shells' powers
  `sum_p C^2 |A|^2` that differ between the weightings.
- **Reductions' tables** (hand-made, with ties): greedy on (0.2, 0.7, 0.7, 0.1, 0.7) is 2; best 3 of (0.5,
  0.9, 0.5, 0.9, 0.1, 0.5) is 2, 4, 1 and best 5 is 2, 4, 1, 3, 6; store of (0.5, 0.6, 0.4) over (0.5, 0.5,
  0.5) keeps the first and the third; hill climbing on (0.3, 0.8, 0.5, 0.9, 0.5) with `prev_corr = 0.5` and
  order 5, 1, 2, 4, 3 takes 2 after three scores, with 0.95 falls back to 4 after five, and on (0.6, 0.9, 0.9,
  0.2) with 0.9 and order 3, 4, 1, 2 falls back to 2; distances (0.4, 0.2, 0.2, 0.5) give 2; distances (-0.1,
  -0.3, 0.2) give 2 by distance and 1 by score.

#### C2, `mlxf_oracle_polar_shiftmap` (Phase 2), section 9.2

- **Setup.** `prior_w = 1 / (2 sigma_px^2)`; `kscreen = max(kfrom + 1, kto / 2)` in integers. A map is built
  for a band `kfrom .. kstop` and one radius (Q16).
- **Grid.** `step = box / kstop / 4`; `nrho = floor(radius / step) + 1`, or 2 with `step = radius`;
  `rho_i = (i - 1) step`; `nalpha` the smallest 7-smooth integer at least `2 ceiling(2 pi kstop rho_max /
  box) + 3` with `rho_max = rho_nrho` (Q17); `alpha_j = (j - 1) 2 pi / nalpha`. Cell `(ialpha, irot, irho)` is
  the shift `rho_i (cos alpha_j, sin alpha_j)` in the reference's frame at rotation `irot`.
- **Cell.** `L = 1 + (refpow(irot) - 2 cross) / ptclpow` on the band, `ptclpow` the band's own power, with
  the phase written `exp(i z_k sin(theta - alpha))`, `z_k = 2 pi k rho / box` (Q19). Correlation cell:
  `cross / sqrt(refpow ptclpow)` with `w_k = k`.
- **Truncated Bessel form.** The phase replaced by `sum over |m| <= nharm(rho) of J_m(z_k) exp(i m (theta -
  alpha))` in `cross`; `nharm` from `z = 2 pi kstop rho / box`: start at `max(0, ceiling(z))`, increase while
  `|J_m(z)| >= 1e-8`, `nharm = max(0, m - 1)` (Q20).
- **Areas.** `pi (hi^2 - lo^2) / nalpha`, midpoints, `lo = max(0, rho_1 - step / 2)` on the first ring and
  `hi = rho_n + step / 2` on the last.
- **Mode.** `l = -temp L - prior_w rho^2 + log(area)`; the first strict maximum in the loop order `irho`,
  `irot`, `ialpha` (innermost); returns `irot`, `irho`, `ialpha` and the cell's `L`.
- **Width.** -1 if a cutoff is given and `loss` exceeds it; else the weights `exp(lphys)` of the cells above
  -40, `w0`, `w1(:, irot)`, `w2`, `mean = sum over irot of matmul(w1(:, irot), M(irot)) / w0`,
  `sdev = sqrt(max(0, w2 / w0 - |mean|^2))`.
- **Temperatures.** `temp = 0.3 pi wsq_band / (2 pftsz)`, `temp_phys = temp / 0.3`.
- **Fixture.** The polar fixtures' pairs; box 32 with radii 5, 7 and 1.5 (numbers above), box 24 (band 2 to 3,
  `step = 2`) with radii 5 and 9 (`nrho` 3 and 5, `nalpha` 12 and 18). Hand-made tables for the mode and the
  width (Q25).

#### C3, `mlxf_oracle_pose` (Phase 3), section 9.3

- **Reference.** `v` on `box^3` at offset `(n - box) / 2` in `n^3`, `n = 2 box`, origin `c = n / 2 + 1`;
  multiplied by `rho(x) rho(y) rho(z)`, `rho = kb_env / bspline_env`, as 9.3.1 writes them, `I0` by its
  converged series; `F(q) = (1 / box^3) sum_x rho rho rho v_pad exp(-2 pi i q . (x - c) / n)`, the whole
  cube, `q` stored at `1 + modulo(q, n)` (Q27), by `oracle_dft_3d` on the volume rolled to the origin.
- **Particle.** Pixels `(h, k)`, `-box/2 .. box/2`; `shell = nint(sqrt(h^2 + k^2))` inside `h^2 + k^2 <=
  (box/2)^2`; band `kfrom .. kto`; `w = 1 / sqrt(sigma2(shell))` (Euclidean) or 1 (correlation); `X =
  observed w`, `T = |CTF| w`; half plane `k = -kto .. kto`, `h` from 0 when `k > 0` and from 1 otherwise, to
  `kto`; the central pixel apart, once, only when `kfrom = 0`; `Ppow = 2 sum_half |X|^2 + |X(0,0)|^2`.
- **Pose.** `R = Rz(e3) Ry(e2) Rz(e1)` with 9.3.3's matrices; increment `R exp([omega]x)` on the right;
  `loc_j = 2 (h R(1, j) + k R(2, j))`.
- **Gather.** Per axis `m = nint(loc)`, `t = loc - m`, taps `m - 1, m, m + 1` wrapped, weights `[(t - 1/2)^2
  / 2, 3/4 - t^2, (t + 1/2)^2 / 2]`, slopes `[t - 1/2, -2 t, t + 1/2]`; value and three derivatives.
- **Model and objectives.** `M = exp(+2 pi i (h s1 + k s2) / box) T V(loc)`, `r = M - X`; Euclidean `(2
  sum_half |r|^2 + |r_0|^2) / Ppow`; correlation `1 - cross / sqrt(Ppow mm)`; NaN for the objective, the
  gradient and the matrix when `Ppow` (or `mm`) is not above `epsilon^2`.
- **Derivatives.** `J_a = wp (grad V x loc)_a`, `J_4 = i fh M`, `J_5 = i fk M`; `g`, `H`, `G`, `MG`, `wc`,
  `wpow` as 9.3.6 writes them, each "2 sum" being the half-plane sum doubled once (Q30). Euclidean: gradient
  `2 g / Ppow`, matrix `scale 2 H / Ppow`, `scale = min(20, max(0.05, wc / wpow))`. Correlation: gradient `-G
  / Nrm + cross MG / (Nrm mm)`, matrix `scale (H / mm - MG MG^T / mm^2)`, `scale = min(20, max(0.05, (wc /
  wpow) sqrt(mm / Ppow)))`. Shift only: entries 4 and 5 and the lower right block, computed from `q` and
  `m2` without the gather's derivative.
- **Solve.** 9.3.7's rules, in the order of Q34.
- **Fixture.** Volume 16^3 (`n = 32`, `c = 17`), centred coordinate `x = i - 9`: three Gaussian blobs
  (amplitude; centre; sigma) = (1; 1.5, -1, 0.5; 1.2), (0.7; -2, 1.5, -1; 1.6), (0.5; 0.5, 2, 2.5; 0.9). CTF
  `-sin(0.3 + 0.09 h^2 + 0.07 k^2 + 0.02 h k)`, of which the module takes the modulus. `sigma2(shell) = 1 +
  0.25 shell`. Planted pose: Euler (0.6, 1.0, -0.4), shift (0.8, -1.3). Displaced start: `omega = 0.05 (2,
  -1, 2) / 3` on the right (0.05 rad) and the shift plus (0.3, -0.4) (0.5 pixel). The multiple of decision
  10: 2.5. Bands: 1 to 7 (Euclidean), 0 to 7 (correlation).

#### Choices where section 9 or the plan leaves one (decisions taken under delegation)

- **Q1.** "Imports intrinsic modules and `mlxf_oracle_dft` only" is read as the first run read it: nothing
  outside the intrinsic modules and this plan's own oracles. The shift map imports the polar module, because
  Phase 2's exit compares its cell with Phase 1's direct loss and decision 2 calls that module "the direct
  route K4 rests on". No module reaches the library.
- **Q2.** Each module's public state is one class with private components (rule `defs` refuses an imported
  record; rule `arity` refuses more than five dummies): `oracle_polar_pair`, `oracle_shiftmap`,
  `oracle_pose_problem`, each with `new` and `kill`.
- **Q3.** Polar arrays: `ref(P, nk)`, `ptcl(P, nk)`, `ctf(P, nk)`, `sigma2(nk)`; the shell of column `i` is
  `kfrom + i - 1`. A pair starts with unit CTF and unit variances until `set_weights`.
- **Q4.** A zero denominator (`wsq`, a correlation's product of powers) returns a quiet NaN, set explicitly so
  that it does not depend on the floating-point traps. SIMPLE has no guard.
- **Q5.** Validity of a distance: `L <= -log(1e-10)`; a NaN is invalid.
- **Q6.** The small-shift rule is not applied; the self-check's driver reports the largest change of `L` a
  shift with `x^2 + y^2 = 1e-5` makes (reported, not gated).
- **Q7.** The clamp `max(0, cc)` is the function `oracle_polar_clamp`; the correlations return the unclamped
  value.
- **Q8.** The in-plane best of a correlation is its first maximum, the rule 9.1.3 gives for the score.
- **Q9.** Best k with `k` above the number of references returns 0 in the surplus entries.
- **Q10.** The hill climb's fallback is the greedy rule as 9.1.5 states it (the lowest reference index among
  equals, not the first visited). It also returns the number of references scored.
- **Q11.** The store is elemental over references and carries an integer tag (the in-plane index).
- **Q12.** The ring-transform route returns `L` for all `N` rotations at one shift; it completes `c` beyond
  bin `P + 1` by Hermitian symmetry, which is what a real inverse transform of the half spectrum does.
- **Q13.** Measures. An identity between two routes: the largest difference over the table compared, relative
  to the table's largest magnitude. A closed form that is zero or one on a quantity already normalised (`L`,
  `1 - cc`): the absolute value. Counts and indices: mismatches.
- **Q14.** The bound `|cc| <= 1` is reported as `max(0, |cc| - 1)` over every rotation, both pairs, three
  shifts and the unit-correlation copy, against 1e-12.
- **Q15.** `w_k` uses the shell's radius `kfrom + i - 1`, never the column index.
- **Q16.** `kstop` is an argument of the map; `oracle_shiftmap_kscreen` gives production's value.
- **Q17.** `rho_max` in `nalpha`'s bound is the grid's last ring `(nrho - 1) step`, not the radius.
- **Q18.** The map is given the pair's arrays for `kfrom .. kto` and restricts them to the band itself, so
  that the band's power is the map's doing.
- **Q19.** The cell does not call the polar module: it is the expanded form of 9.2.3 with the phase in its
  polar form, on index arithmetic of its own. Its comparison with Phase 1's sum of squared residuals is then
  a comparison of two routes. The duplication of a few lines is the price of a check that can fail.
- **Q20.** `J_m` is the intrinsic `bessel_jn` (Fortran 2008), checked against the trapezoid rule on
  `(1 / 2 pi) int cos(m t - z sin t) dt`; `J_-m = (-1)^m J_m`. The truncated phase enters `cross` only:
  `refpow` has no phase in 9.1.3.
- **Q21.** The truncated form is exported for both objectives; decision 5's 1e-6 is applied to the loss and,
  for want of another number, to the correlation.
- **Q22.** The mode and the width work on a table `lmap(nalpha, nrots, nrho)` the caller gives, so hand-made
  tables reach them. The mode returns `[irot, irho, ialpha]` in 9.2.6's order. The prior is a state of the
  map (`set_prior(sigma_px)`), zero until set.
- **Q23.** The width's maximum is over every cell of the table; its `loss` is the caller's (the mode's);
  `cutoff` is optional.
- **Q24.** The matrix `M(irot)` of the width is the polar module's procedure (one owner); the width's check is
  a closed form that does not use it.
- **Q25.** Ties for the mode. Within a ring equal `L` gives equal `l`. Across rings the areas differ, so an
  exact tie is made with `L = -1e30` at the tied cells: the prior and the area are then absorbed by rounding.
  Four tied cells are placed so that each of the five wrong loop orders, and a non-strict comparison, returns
  a different cell from the right one.
- **Q26.** The temperatures are a subroutine of `(wsq_band, pftsz)`; `prob_beta = 0.3` is local.
- **Q27.** `F` is held as the whole cube.
- **Q28.** Pose API: `objective( r, shift )`, `derivatives( r, shift, grad, mat )`, `shift_derivatives( r,
  shift, grad, mat )`, `scale( r, shift )`, `model( ctf, r, shift )`, `power()`, `npixels()`, `solve( r, shift,
  trace, status )`; the objective kind ('euclid' or 'cc') is fixed by `new`.
- **Q29.** Pixel arrays are `(box + 1, box + 1)` with pixel `(h, k)` at `(h + box/2 + 1, k + box/2 + 1)`;
  `sigma2(1 + shell)`; the CTF is given signed and the module takes its modulus.
- **Q30.** In 9.3.6 "the sums run over the half plane and are then doubled" and each formula starts with "2
  sum": the 2 is that doubling, once. *Derived:* only then is `2 g / Ppow` the derivative of 9.3.5's `L`;
  the central differences of decision 10 judge it.
- **Q31.** When `wpow` is not above `epsilon^2` the scale is one.
- **Q32.** The gather exported is the separable one of 9.3.4. The self-check's explicit 27-term gather is
  written from the quadratic B-spline kernel `b(d) = 3/4 - d^2` for `|d| <= 1/2`, `(|d| - 3/2)^2 / 2` up to
  3/2, by the distance to each of the 27 nearest lattice points, with its own rounding; it calls nothing of
  the separable one.
- **Q33.** The rotation increment is Rodrigues' formula, checked against the exponential's power series.
- **Q34.** The solve, where 9.3.7 leaves the order open. Per iteration (a trial step, accepted or not, counts
  as one of the 40): (1) stop if `|g_s| < 1e-8` (Euclidean norm); (2) stop if the Cholesky factorisation of
  `C_s` meets a pivot not above `sqrt(eps) max|C_s|`; (3) solve the damped system, unscale, cap each part's
  Euclidean norm separately by scaling that part; (4) `predicted <= 0` is a rejection, `predicted < 1e-6
  max(|f|, eps^2)` a stop; (5) accept when `actual > 0` and `actual / predicted >= 0.25`, halve `mu` above
  0.75, reset the multiplier; then stop if both parts of the step are below 1e-8 or `actual / |f| < 1e-6`,
  `f` being the objective the step started from; (6) on a rejection, a non-finite trial objective included,
  `mu = min(mu m, 1 / eps)`, `m` doubles, and the eighth in a row ends the solve. The trace is, per
  iteration, the objective held after it, the `mu` of its step and 1 or 0 for accepted; the status names the
  stop.
- **Q35.** Pose errors: rotation `2 asin(|R - R_true|_F / (2 sqrt 2))` in radians, shift the Euclidean norm
  of the difference in pixels.
- **Q36.** The fixtures' numbers, as listed in C1 to C3. The planted Euler angles were moved from (0.7, 1.1,
  -0.4) to (0.6, 1.0, -0.4) by the margin scan above, before any oracle existed.
- **Q37.** Central differences use steps of 1e-5 rad and 1e-5 pixel (decision 5's step). A check `margins`
  counts coordinates within 1e-3 lattice units of a half-integer at the two poses (limit 0); 1e-3 is
  *derived*: six times the largest move of a step.
- **Q38.** The gather's derivative inside one cell is differenced with a step of 1/16 at offsets `|t| <=
  3/8`: the value is a quadratic there, so any step is exact and a large one keeps rounding small.
- **Q39.** One number outside decision 5: the recomputed `w_0`, `w_1` against 9.3.1's printed values, 5e-8
  (*derived*: half a unit of the seventh decimal printed).
- **Q40.** Checks beyond section 8's lists, each a closed form or a second route: for the polar module the
  particle-frame shift, the per-shell scaled copy and the planted rotation with shift; for the shift map
  `bessel_jn` against its integral, the 7-smooth sizes, the temperatures and the correlation cell; for the
  pose the transform against a triple sum, the gather at lattice points against the transform of the
  volume times `kb_env` (exact, because the three taps' transform is `bspline_env`), the model at
  rotations that land on lattice points against an explicit sum, the powers by pixel counts, both
  objectives against plain full-plane sums, the clamped scale, and the NaN floor.

#### Threshold map (decision 5's numbers, assigned before any oracle is run)

| Class | Limit | Checks |
| --- | --- | --- |
| exact | 0 mismatches | counts, grids, `nalpha`, `nharm`, `kscreen`, margins, reductions, in-plane bests, the mode, the cutoff's -1, the NaN floor, the solve's monotone history |
| two exact routes or a closed form | 1e-12 | direct sums against ring transforms; planted rotations and shifts; unit correlation; the bound; the cell against Phase 1's loss; areas; `bessel_jn` against its integral; the width; the temperatures; the transform; the gather against the explicit one and at lattice points; the model at lattice rotations; powers; objectives against full-plane sums; zero residual (value, gradient, scale); the shift-only terms; the clamped scale |
| derivative against central differences | 1e-7 of the largest component | each gradient away from the solution; each matrix at zero residual against differences of the gradient |
| the gather's derivative inside a cell | 1e-10 | one check |
| truncated Bessel form | 1e-6 absolute | the loss cell, the correlation cell |
| the solve | 1e-6 rad, 1e-6 pixel | the planted pose, both objectives |
| printed weights | 5e-8 | `w_0`, `w_1` (Q39) |

#### The independent review (a read-only subagent, 21:26 to 21:37) and what it changed

It re-derived and confirmed: the ring route and its `2 N`; the closed-form fixture; `s = M u` and the
direction of `matmul(w1, M)`; Q30; the correlation's matrix as the exact second derivative at a positive
multiple of the model; the lattice-point identity of Q40; every hand-worked number. No blocking finding, and
no contradiction inside section 9. Its "should fix" findings are taken as follows, before any module exists:

- **Q41, checks that could not fail or shared an error, rewritten.**
  - Zero loss and unit correlation are quadratic in the model's error, so 1e-12 on them passes an error of
    1e-6: each planted check also compares the table `R_n(S A)` itself with the closed form (linear), and the
    Euclidean value is gated as `sqrt(L)`.
  - The fixture and the module could share a sign or an angle origin: hand values are added, `S(p = 1) =
    exp(-2 pi i k y / box)` and `S(p = P/2 + 1) = exp(+2 pi i k x / box)` on a unit reference, and a
    one-sample reference whose rotated copies are stated by hand (conjugated on the wrapped half).
  - The areas' sum telescopes: per-ring values are added (`pi (step / 2)^2 / nalpha` on the first ring,
    `2 pi rho_i step / nalpha` elsewhere).
  - Both grids had `box / kstop = 8`, which an integer division passes: a grid with box 32 and `kstop = 5` is
    added (`step = 1.6`; radius 5 gives `nrho = 4`, `rho_max = 4.8`, the bound 13, `nalpha = 14`, areas
    summing to 31.36 pi), and `kscreen` is also checked at `kfrom = 5`, `kto = 9` (6, the other branch).
  - The 1e-6 of the truncated form would pass `|m| < nharm`: the truncated cell is also compared at 1e-12
    with a sum retyped in the check over the orders `-nharm .. nharm`, `J` by its integral.
  - The tied tables erase the prior and the area: two tables without ties are added (constant `L` with
    `sigma_px = sqrt(10)` on the four rings 0, 2, 4, 6, where the terms -0.05 rho^2 + log(area) peak on the
    third ring; and one lower cell that the temperature must lift above it). The -40 skip is pinned by a
    table whose surviving mass is on `rho = 0` (a cell at -41 must leave `sdev` exactly 0; one at -39 has a
    closed form).
  - The lattice-point gather shared `kb_env`: the check retypes `w_0 + 2 w_1 cos` with `I0` by the trapezoid
    rule, and includes coordinates of +-16, which wrap.
  - Euclidean zero residual holds for any Jacobian and for an inverted scale: the multiple `X = lambda M` is
    added (`L = (1 - 1 / lambda)^2`, scale `lambda` at 2.5, 20 at 40, 0.05 at 0.02 and at -1).
  - The lattice-rotation model states `loc` by hand: Euler (pi/2, 0, 0) reads `2 (-k, h, 0)` and (pi/2, pi/2,
    0) reads `2 (-k, 0, -h)`, so the Euler order and the transpose are not shared with the check.
  - The Euclidean power with the centre (band 0 to 7, 13.8125) is added; the temperatures are compared with
    decimal literals.
- **Q42.** The NaN floor of the correlation is read as: `Ppow` not above the floor, or `mm` not above it.
- **Q43.** Section 9 does not say how a correlation cell enters the mode and the width. They take the table
  they are given; nothing is exported for a correlation map beyond its cells.
- **Q44.** The reductions are not defined on a NaN score; the oracle assumes finite scores.
- **Q45.** When the solve's result is not strictly below the start, the start pose is returned with the
  status of the stop.
- **Q46.** "Closed form at 1e-12" extends decision 5's first class (two exact routes) to closed forms and
  hand values; said here because decision 5 does not.
- **Not changed, the reviewer dissenting.** Q17: it holds that `rho_max` is SIMPLE's and cannot be derived
  (radius 7 gives `nalpha` 14 by the last ring and 15 by the radius), and that this is a stop. The run keeps
  Q17 as a choice, because 9.2.2 defines the rings in the sentence before and calls the radius `radius`; it is
  the first item of "left open for the maintainer". Q1: it asks for a ruling on the import; recorded as a
  decision under delegation and listed in the report.
- **Text made exact.** The ring route in 1-based storage: bins `b = 1 .. P + 1`, completed by `c(N + 2 - b) =
  conj(c(b))` for `b = 2 .. P`, and `N` times `oracle_idft_1d`. The cell's angle is the reference's own; the
  width uses `tphys`, the mode `temp`.

**What it means, in short.** The base passes the gate, every formula of section 9 has one reading written
down, the fixtures' numbers are worked before the code, and the points section 9 leaves open are closed as
Q1 to Q46. Section 9 contradicts itself nowhere an oracle needs; its one loose wording (the "2 sum" of
9.3.6) is settled by derivation and will be judged by decision 10's central differences. Its one name without
a definition (`rho_max`) is read as the last ring and flagged.

### Phase 1, the polar objectives and reductions: done (2026-11-24, 21:38 to 21:59 EST, the Mac)

Machine, base and rulings as in Phase 0; load 1.2 to 2.5. Files changed: `src/test/mlxf_oracle_polar_objfun.f90`
(new, 910 lines) and this note. `mlxf_oracle_dft.f90` is untouched (no helper needed exporting). Evidence under
`keep/`: the driver `drivers/mlxf_oracle_polar_main.f90`, the build recipe `drivers/build_level_mac.sh` (the
first run's, with this folder's paths and the wait for the timed job), `drivers/build_and_run.sh`, the plants
`drivers/plants_polar.py`, the first run's harness `drivers/run_controls.py` unchanged.

**Exit** (section 5's gate for a new module).
1. *Standalone builds without a warning at both levels:* met. `gfortran -std=f2018 -Wall -Wextra -Werror`, at
   `-O0 -g -fcheck=all` and at `-O2`, each file alone, no compiler output. `keep/logs/phase1_polar_build_{O0,
   O2}.log`.
2. *The self-check inside decision 5's thresholds:* met, 25 of 25 at both levels, largest error 1.9e-15 at
   `-O0` and 2.6e-15 at `-O2` against 1e-12. `keep/logs/phase1_polar_run_{O0,O2}.log`.
3. *Each negative control failing:* met. 40 plants, each fails at least one check; every one of the 25 checks is
   failed by at least one plant. `keep/logs/phase1_polar_controls.log`.
4. *Formatters and the static gate:* met. `restyle_fortran.py` and `format_use_blocks.py` on the file by name,
   then `scripts/check_tree.sh`: passed (the new file is listed as untracked).
   `keep/logs/phase1_check_tree.log`.
5. *Read by an independent reviewer against section 9:* a read-only subagent; below.

**Exported names.** The class `oracle_polar_pair` with the bindings `new( box, kfrom, ref, ptcl )`, `kill`,
`set_weights( ctf, sigma2 )`, `geometry`, `arrays`, `band( kstop, sub )`, `nrots`, `rotated( irot, shift )`,
`wsq`, `dist( irot, shift )`, `cc( irot, shift )`, `cc_weighted( irot, shift )` and `dists_by_rings( shift )`;
the procedures `oracle_polar_fixture`, `oracle_polar_score`, `oracle_polar_valid`, `oracle_polar_clamp`,
`oracle_polar_angle`, `oracle_polar_frame`, `oracle_polar_best_dist`, `oracle_polar_best_score`,
`oracle_polar_store`, `oracle_polar_greedy`, `oracle_polar_best_k`, `oracle_polar_shc` and
`oracle_polar_selfcheck`.

**Argument conventions, as Phase 2 uses them.**
- `ref(P, nk)`, `ptcl(P, nk)`, `ctf(P, nk)`: half rings, sample `p` at the angle `2 pi (p - 1) / (2 P)`, column
  `i` the shell `kfrom + i - 1`; `sigma2(nk)`. `geometry()` is `[pftsz, kfrom, kto, box]`.
- `irot` is 1-based, 1 to `2 P`; `irot = 1` is no rotation; the reference is rotated, never the particle.
- `shift(2) = (x, y)` in pixels of the box, in the reference's frame, applied before the rotation.
  `matmul(oracle_polar_frame(irot, nrots), u)` is the reference-frame shift of a particle-frame shift `u`.
- `dist` is the sum of squared residuals over `wsq`, unclamped; `rotated` is the half ring of `R_n(S A)`
  without the CTF; `band(kstop, sub)` is the pair on the shells up to `kstop`.

**The checks** (*measured*; the limit is decision 5's 1e-12 where it is not 0):

| Check | `-O0` | `-O2` | Limit |
| --- | --- | --- | --- |
| counts | 0 | 0 | 0 |
| shift phase by hand | 0 | 0 | 1e-12 |
| rotation by hand | 0 | 0 | 0 |
| table vs closed form | 1.3e-15 | 1.3e-15 | 1e-12 |
| zero loss copy | 0 | 0 | 1e-12 |
| unit correlation | 2.2e-16 | 2.2e-16 | 1e-12 |
| planted rotation loss | 9.2e-16 | 9.0e-16 | 1e-12 |
| planted rotation index | 0 | 0 | 0 |
| planted shift | 3.6e-16 | 2.3e-16 | 1e-12 |
| planted rotation shift | 9.3e-16 | 9.9e-16 | 1e-12 |
| particle-frame shift | 7.2e-16 | 6.3e-16 | 1e-12 |
| scaled shells loss | 2.6e-16 | 3.4e-16 | 1e-12 |
| scaled shells cc | 1.9e-15 | 2.6e-15 | 1e-12 |
| scaled shells weighted | 7.6e-16 | 7.6e-16 | 1e-12 |
| direct vs rings | 5.6e-16 | 5.1e-16 | 1e-12 |
| cc bound | 2.2e-16 | 0 | 1e-12 |
| score clamp validity | 0 | 0 | 1e-12 |
| angle and frame | 1.2e-16 | 1.2e-16 | 1e-12 |
| in-plane best, store, greedy, best k, hill climb | 0 | 0 | 0 |
| zero denominators | 0 | 0 | 0 |
| arrays and band | 0 | 0 | 0 |

Three values are exactly 0 for a reason, and each still fails under its plants: the phase by hand (at the
first sample and a quarter turn on, the module's argument is the hand value's own arithmetic); the zero loss
of the copy (the particle is the same product the model forms); the score, the clamp and the limit (the
same intrinsic calls on the same literals).

**The traps of section 9.4 that belong here, each planted and failing** (plant, checks failed):
- 1, the correlations exchanged (`t5`): 2, the two scaled-shell correlations.
- 2, the weight `w_k` (`w1` without `k`, `w2` with the column index, `w3` without `sigma2`): the scaled-shell
  loss.
- 3, the shift after the rotation (`t2`): 5; the `-cos` turned to `+cos` (`t3`): 6.
- 4, the conjugate dropped on the wrapped half (`t1`): 8; the CTF rotated with the reference (`p19`): 5.
- 5, a 0-based rotation index (`t4`): 14.
- 6, `N` for `2 N` in the ring route (`t6`): 1, direct against rings.

**Reported, not gated.** The small-shift rule (Q6): a shift of length sqrt(1e-5), which SIMPLE treats as
zero, changes `L` by up to 3.0e-3 over the twelve generic pairs and all rotations (*measured*, both levels).

**Decisions taken under delegation.**
- A third fixture size, `pftsz` 12, shells 3 to 7, box 40, was added after the review: in the two sizes of C1
  the box equals the number of rotations, so exchanging them in the phase passed every check. C1's sizes are
  unchanged. The plant `p28` shows the exchange failing now.
- The fixture's generic pair is exported (`oracle_polar_fixture( isize, iref, iptcl, pair )`), as the first
  oracles export theirs: the shift map's self-check and the driver need it.
- `geometry`, `arrays` and `band` were added for the shift map (Q18, Q19), with a check of their own.
- The score and the clamp return NaN on a NaN argument explicitly: `max(0, NaN)` depends on the processor.
  The reductions stay undefined on NaN scores (Q44).
- `set_weights` does nothing before `new` and assigns into the pair's shapes; `kill` zeroes the sizes.
- The hill climb's `order` is taken to be a permutation of all references (9.1.5 says so); `nevals` is then
  the number scored.

**The independent review** (a read-only subagent, 21:46 to 21:55) confirmed every item of 9.1 line by line
(geometry, both branches of the rotation, the phase, `w_k`, the loss, the correlations, the ring route with
its lag and `2 N`, the reductions, `s = M u`), the closed form of the fixture and the three closed forms of
the scaled copy, found no out-of-bounds index for either size and no house-rule violation. Its four "should
fix" findings were applied before this entry: the third size above; the correlations' values at the planted
rotations and at the rotation with a shift (the reference's power at `n /= 0` had only the best index to
judge it; plant `p29`); NaN through the score and the clamp (plants `p30`, `p31`); every term of the scalar
checks through `oracle_finite_or_inf`, so that a NaN cannot be dropped by `max`. Its notes are recorded as
they stand: "direct vs rings" shares the phase, the weights and `wsq` with the direct route and judges the
extension, the index shift, the lag and `2 N` only (the phase and the weights rest on the hand values, the
closed-form table and the scaled copy); a few terms are identities (the shape of a result, the unrotated
table against the array given).

**What it means, in short.** The polar oracle computes 9.1 as written, agrees with a closed form that shares
none of its machinery to 1e-15, and each of the six traps that concern it is shown to break a check. Not
shown here: agreement with the existing polar oracle, with an MLX kernel, and with SIMPLE (section 6).

### Phase 2, the shift map: done (2026-11-24, 21:59 to 22:28 EST, the Mac)

Machine, base and rulings as in Phase 0. Files changed: `src/test/mlxf_oracle_polar_shiftmap.f90` (new, 951
lines) and this note. `mlxf_oracle_polar_objfun.f90` was not edited in this phase (its `geometry`, `arrays`,
`band` and `oracle_polar_frame` were written in Phase 1 for this one); `mlxf_oracle_dft.f90` is untouched.
Evidence under `keep/`: the driver `drivers/mlxf_oracle_shiftmap_main.f90`, the plants
`drivers/plants_shiftmap.py`, the hand numbers `phase0/phase2_hand_numbers.log` (the Phase 0 script's
functions on the seven maps, before the module was written).

**Exit.**
1. *Standalone builds without a warning at both levels:* met; the three modules and the driver, each alone,
   no compiler output. `keep/logs/phase2_shiftmap_build_{O0,O2}.log`.
2. *The self-check inside decision 5's thresholds:* met, 21 of 21 at both levels.
   `keep/logs/phase2_shiftmap_run_{O0,O2}.log`.
3. *Each negative control failing:* met. 66 plants, each fails at least one check; each of the 21 checks is
   failed by at least one plant. `keep/logs/phase2_shiftmap_controls.log`.
4. *Formatters and the static gate:* met. `keep/logs/phase2_check_tree.log`.
5. *Read by an independent reviewer against section 9:* a read-only subagent; below.

**Exported names.** The class `oracle_shiftmap` with the bindings `new( pair, kstop, radius )`, `kill`,
`set_prior( sigma_px )`, `dims` (`[nalpha, rotations, nrho]`), `step`, `rho( irho )`, `alpha( ialpha )`,
`area( irho )`, `nharm( irho )`, `ptclpow`, `cell( ialpha, irot, irho )`, `cell_cc`, `cell_bessel`,
`cell_cc_bessel`, `table( truncated )`, `mode( lmap, temp, best, loss )` and `width( lmap, tphys, loss,
cutoff )`; the procedures `oracle_shiftmap_kscreen`, `oracle_shiftmap_temps` and
`oracle_shiftmap_selfcheck`.

**The self-check's maps and their hand-worked numbers** (*derived* by hand and by the Phase 0 script; the
module's grid is compared with them, and the cells' shifts are made from them, not from the module):

| Fixture, band | Radius | Step | `nrho` | `nalpha` | `nharm` per ring |
| --- | --- | --- | --- | --- | --- |
| box 32, 2 to 4 | 5 | 2 | 3 | 12 | 0, 10, 13 |
| box 32, 2 to 4 | 7 | 2 | 4 | 14 | 0, 10, 13, 16 |
| box 32, 2 to 4 | 1.5 | 1.5 | 2 | 7 | 0, 9 |
| box 24, 2 to 3 | 5 | 2 | 3 | 12 | 0, 10, 13 |
| box 24, 2 to 3 | 9 | 2 | 5 | 18 | 0, 10, 13, 16, 19 |
| box 32, 2 to 5 | 5 | 1.6 | 4 | 14 | 0, 10, 13, 16 |
| box 40, 3 to 4 | 6 | 2.5 | 3 | 12 | 0, 10, 13 |

**The checks** (*measured*):

| Check | `-O0` | `-O2` | Limit |
| --- | --- | --- | --- |
| kscreen, smooth sizes, grid counts, nharm by hand | 0 | 0 | 0 |
| grid values | 0 | 4.4e-16 | 1e-12 |
| areas per ring | 2.6e-16 | 2.6e-16 | 1e-12 |
| areas sum | 2.9e-16 | 2.9e-16 | 1e-12 |
| bessel vs integral | 5.9e-16 | 5.3e-16 | 1e-12 |
| band power | 0 | 0 | 1e-12 |
| cell vs direct loss | 7.5e-16 | 7.5e-16 | 1e-12 |
| cc cell vs direct cc | 1.2e-15 | 1.3e-15 | 1e-12 |
| bessel vs direct cell | 2.1e-9 | 2.1e-9 | 1e-6 |
| bessel cc vs direct | 1.1e-9 | 1.1e-9 | 1e-6 |
| bessel vs retyped sum | 1.1e-15 | 1.0e-15 | 1e-12 |
| mode ties, mode by terms, width cutoff, zero power | 0 | 0 | 0 |
| width by hand | 8.9e-16 | 8.9e-16 | 1e-12 |
| width skip | 1.6e-16 | 1.6e-16 | 1e-12 |
| temperatures | 0 | 0 | 1e-12 |

The band power is exactly 0 because the map and the polar module sum the same terms in the same order; the
temperatures because the literals are the same products. Both fail under their plants (`t7a`, `c12`; `k03`,
`k04`).

**The traps of section 9.4 that belong here, each planted and failing.** 7, the band's power replaced by the
full power (`t7a`): 4 checks (band power, both cells against the direct sums, the retyped sum); `nharm` taken
from another shell than `kstop` (`t7b`): 2 (nharm by hand, the retyped sum). 1, the correlation cell without
its shell weights (`t1`): the correlation cell against Phase 1's weighted correlation.

**Reported, not gated: the truncated form against the direct cell, per ring** (*measured*, the largest
absolute difference over rotations and directions, the same at both levels to three digits):

| Map | `rho` | `nharm` | Loss | Correlation |
| --- | --- | --- | --- | --- |
| box 32, band 2 to 4, radius 7 | 0 | 0 | 0 | 0 |
| | 2 | 10 | 3.0e-12 | 2.9e-12 |
| | 4 | 13 | 1.2e-13 | 1.2e-13 |
| | 6 | 16 | 4.7e-14 | 4.8e-14 |
| box 24, band 2 to 3, radius 9 | 0 | 0 | 0 | 0 |
| | 2 | 10 | 6.7e-12 | 6.0e-12 |
| | 4 | 13 | 9.9e-11 | 8.6e-11 |
| | 6 | 16 | 8.6e-10 | 6.1e-10 |
| | 8 | 19 | 2.1e-9 | 1.1e-9 |

The first dropped order has `|J|` between 1.3e-9 and 5.4e-9 (*derived*), and the fixtures carry little of
their signal at orders beyond ten, so the difference sits three to eight orders below decision 5's 1e-6.
That limit is therefore loose on these fixtures: it would pass a series one order short. The order count is
pinned instead by "nharm by hand" and by "bessel vs retyped sum" at 1e-12 (plants `b03`, one order short,
and `b07`, one order more, each fail it and nothing else).

**Decisions taken under delegation.**
- **Q47.** NaN in a table: the mode passes over NaN cells and returns zeros and a NaN loss when there is no
  other; the width of a table holding a NaN is NaN. Section 9 gives no rule; `max` on a NaN depends on the
  processor, so the choice is made explicit.
- The grid's real values (step, radii, directions) are compared with the hand numbers at 1e-12, not as exact:
  `3 x 1.6` is not the double nearest to 4.8. The counts stay exact.
- `bessel_jn` against its integral is judged on the absolute difference: the trapezoid rule's own rounding
  (1e-16) forbids a relative measure near the floor of 1e-8. The smallest margin of an `nharm` decision is
  `J_19(2 pi) = 1.39e-8` against 1e-8 (*derived*).
- `kstop` must be one of the pair's shells and a table must have the shape `dims()`; neither is tested for.
- Seven maps instead of the two radii of section 8, the third size and `kstop = 5` among them (Q41).
- The -40 of the width is pinned at -41, at -39 and at exactly -40: at losses near -2^52 a log weight is an
  integer, so two cells can be made to differ by exactly 40.

**The independent review** (a read-only subagent, 22:10 to 22:20) found no departure from 9.2 and no blocking
point. It re-derived the grid, the cell (the phase at the full ring's own angle equals the conjugate on the
wrapped half, for the truncated sum too), `bessel_phase` for even and odd orders, the areas, the mode, the
width line by line, every row of the hand tables, the four expected modes and the five expected widths, and
that each of the five wrong loop orders and a non-strict comparison give another cell. Its "should fix"
findings were applied before this entry:
- NaN was swallowed by `max` in the mode and the width: Q47, with two checks and the plants `m12`, `w11`.
- The loops' extents were not pinned (no winner or weight beyond rotation 9 or direction 4): a mode table won
  at the last cell (14, 32, 4), and the width's second cell moved to direction 10 and rotation 25 (three
  quarter turns, the same hand value); plants `m11`, `w09`.
- The retyped sum pinned the orders from below only: it now also runs on a pair whose reference and particle
  are single samples, where every order weighs alike; plant `b07`.
- The floor at exactly -40 (above), plant `w10`; the width at -39 measured relative to its value.

**What it means, in short.** The shift map computes 9.2 as written; its cell, in the expanded form with the
polar phase, agrees to 1e-15 with Phase 1's sum of squared residuals on the band; the truncated form keeps
exactly SIMPLE's orders; and the mode and the width are held to hand-made tables. The one reading that the
run could not check is Q17 (`rho_max` as the last ring): plant `g06` shows what the other reading would give
(`nalpha` 15 for 14 at radius 7).

### Phase 3, the pose objective: done (2026-11-24, 22:28 to 23:19 EST, the Mac)

Machine, base and rulings as in Phase 0. Files changed: `src/test/mlxf_oracle_pose.f90` (new, 1,755 lines),
this note, and two small edits outside their phases, each with its file-table row extended (the first after
the edit, the second before): one comment of `src/test/mlxf_oracle_polar_shiftmap.f90` (a procedure header of
four lines cut to three), and a NaN guard in `oracle_polar_valid` of `src/test/mlxf_oracle_polar_objfun.f90`
(below, "the repository's flag sets"). `mlxf_oracle_dft.f90` is untouched. Evidence under `keep/`: the driver
`drivers/mlxf_oracle_pose_main.f90`, the plants `drivers/plants_pose.py`, `drivers/wait_timed_job.sh`,
`drivers/repo_flags.sh`.

**Exit.**
1. *Standalone builds without a warning at both levels:* met. `keep/logs/phase3_pose_build_{O0,O2}.log`.
2. *The self-check inside its thresholds:* met, 32 of 32 at both levels.
   `keep/logs/phase3_pose_run_{O0,O2}.log`.
3. *Each negative control failing:* met. 76 plants, each fails at least one check; each of the 32 checks is
   failed by at least one plant. `keep/logs/phase3_pose_controls.log`.
4. *Formatters and the static gate:* met. `keep/logs/phase3_check_tree.log`.
5. *Decision 10's checks present and passing:* met, bullet by bullet below.
6. *Read by an independent reviewer against section 9:* a read-only subagent; below.

**Exported names.** The class `oracle_pose_problem` with the bindings `new( vol, kfrom, kto, objective )`,
`kill`, `set_particle( observed, ctf, sigma2 )`, `npixels`, `power`, `model( ctf, r, shift )`, `objective( r,
shift )`, `derivatives( r, shift, grad, mat )`, `shift_derivatives( r, shift, grad, mat )`, `scale( r, shift )`
and `solve( r, shift, trace, status )`; the procedures `oracle_pose_euler`, `oracle_pose_rotate`,
`oracle_pose_reference`, `oracle_pose_gather`, `oracle_pose_fixture`, `oracle_pose_fixture_pose` and
`oracle_pose_selfcheck`.

**Decision 10, bullet by bullet** (*measured*, the larger of the two levels):
1. Zero residual, Euclidean: root of the loss, largest gradient entry and scale less one, 2.2e-16 together;
   the matrix against central differences of the analytic gradient, 3.0e-10 of the largest entry (limit 1e-7).
2. A particle 2.5 times the model, correlation: objective, gradient and scale less one, 3.3e-16; the matrix
   against central differences, 2.9e-10.
3. Away from the solution, all five parameters: gradient against central differences of the objective, 2.9e-10
   (Euclidean) and 4.5e-10 (correlation).
4. The shift-only terms against entries 4 and 5 and the lower right block: 2.5e-16 and 3.9e-16.
5. The solve from the displaced start (0.05 rad, 0.5 pixel): 1.5e-10 rad and 3.8e-11 pixel left (Euclidean),
   5.1e-11 rad and 1.1e-11 pixel (correlation), against 1e-6. "Never increases on an accepted step" is met
   on the recorded history only: the trace's objectives fall on every accepted step, and the returned pose is
   re-evaluated, but the intermediate poses are not (the reviewer's point: the recorded test restates the
   acceptance rule).

**Decision 8: no disagreement.** Every gradient formula of 9.3.6 is the derivative of its objective to
3e-10 to 4.5e-10, and both matrices are the second derivatives at zero residual to 3e-10, with the factors
read as Q30 reads them (the plants `p12` and `p13`, the other reading, fail). No formula of section 9 was
corrected.

**The checks** (*measured*):

| Check | `-O0` | `-O2` | Limit |
| --- | --- | --- | --- |
| counts, margins, nan floor, solve history, solve at solution, solve rules | 0 | 0 | 0 |
| i0 series | 4.1e-16 | 4.1e-16 | 1e-12 |
| kb weights printed | 2.1e-8 | 2.1e-8 | 5e-8 |
| envelopes by hand | 1.1e-16 | 1.1e-16 | 1e-12 |
| euler and increment | 2.2e-16 | 2.9e-16 | 1e-12 |
| transform vs sum | 1.7e-15 | 1.7e-15 | 1e-12 |
| hermitian | 1.3e-15 | 1.1e-15 | 1e-12 |
| gather vs kernel sum | 1.2e-16 | 1.2e-16 | 1e-12 |
| gather at lattice | 4.2e-15 | 4.2e-15 | 1e-12 |
| gather slope in cell | 9.1e-16 | 1.4e-15 | 1e-10 |
| model at lattice | 3.3e-15 | 3.3e-15 | 1e-12 |
| powers by count | 0 | 0 | 1e-12 |
| objectives vs plane | 5.2e-15 | 7.8e-15 | 1e-12 |
| euclid zero residual | 2.2e-16 | 2.2e-16 | 1e-12 |
| euclid multiple | 1.2e-15 | 1.7e-15 | 1e-12 |
| euclid matrix | 3.0e-10 | 3.0e-10 | 1e-7 |
| euclid gradient | 2.8e-10 | 2.9e-10 | 1e-7 |
| cc zero residual | 3.3e-16 | 2.2e-16 | 1e-12 |
| cc multiple | 3.6e-16 | 1.1e-17 | 1e-12 |
| cc matrix | 2.9e-10 | 2.9e-10 | 1e-7 |
| cc gradient | 3.6e-10 | 4.5e-10 | 1e-7 |
| shift terms euclid | 2.5e-16 | 2.5e-16 | 1e-12 |
| shift terms cc | 2.3e-16 | 3.9e-16 | 1e-12 |
| solve euclid rotation (rad) | 1.5e-10 | 1.5e-10 | 1e-6 |
| solve euclid shift (pixel) | 3.8e-11 | 3.8e-11 | 1e-6 |
| solve cc rotation (rad) | 5.1e-11 | 5.1e-11 | 1e-6 |
| solve cc shift (pixel) | 1.1e-11 | 1.1e-11 | 1e-6 |

The powers by count are exactly 0: the sums are of exact binary fractions.

**What the first runs showed, and what was done** (logs kept beside the final ones):
- The first run at `-O0` failed 2 of 31 (`keep/logs/phase3_pose_run_O0_first.log`).
  - "gather vs kernel sum", 2.0: a sign error in the check's own kernel slope (`sign(a, b)` returns `|a|`
    with the sign of `b`). The oracle's gather was right; the helper was corrected.
  - "gather at lattice", 2.9e-9: the error was measured per point, relative to that point's value, on the
    fixture's smooth volume, whose transform at the three wrapped lattice points is 1e-7 of its peak. Q13's
    measure (the largest difference over the table's largest value) was restored, and the three gather
    checks and the transform check now also run on a broadband volume (an integer sequence), where the
    wrapped points carry signal: under Q13's measure a smooth volume would have hidden an error there. The
    limit 1e-12 is unchanged; the same change brought "transform vs sum" from 4.6e-13 (per point) to 1.7e-15.
- The first `-O2` build stopped on a false "used uninitialized" of GNU Fortran 16.2 (`matmul` of two
  function results inlined; `keep/logs/phase3_pose_build_O2_first.log`). The three rotations are now held in
  locals. This is the class of warning section 2 records for 15.2.
- The first `-O2` run failed "solve history" (`keep/logs/phase3_pose_run_O2_history_fail.log`): the check
  compared the returned objective with the held one to a tolerance proportional to the held value, which at
  `-O2` is -2.2e-16 for the correlation (one minus a correlation that rounds above one). The tolerance is now
  1e-12 of the start's objective. The solve itself was unchanged.

**The traps of section 9.4 that belong here, each planted and failing** (plant, checks failed): 8, `floor`
for `nint` (`t8`, 5). 9, the transposed rotation in the pixel map (`t9a`, 12), the increment on the left
(`t9b`, 10), the padding factor once more in the Jacobian (`t9c`, 6). 10, the phase's sign (`t10a`, 11) and
the padded size in it (`t10b`, 6). 11, the transform's normalisation (`t11a`, 3) and the origin one index
off (`t11b`, 4). 12, the matrix without its scale (`t12a`, 2), the correlation's without its projection
(`t12b`, 2), the scale without its clamp (`t12c`, 3). 13, the central pixel counted twice in the power
(`t13a`, 1) and in the objective's sums (`t13b`, 2).

**Reported, not gated: the reference solve** (*measured* at `-O0`; `-O2` is the same but for the correlation's
last two objectives, 1.3e-15 and -2.2e-16, which are rounding; the full traces are in the run logs):

| Objective | Start | Iterations | Rejections | Damping, per iteration | Objective held after each | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Euclidean | 7.4e-2 | 4 | 0 | 1e-3, 5e-4, 2.5e-4, 1.25e-4 | 1.7e-4, 2.8e-8, 1.7e-14, 4.9e-21 | 0, small gradient |
| correlation | 4.3e-2 | 4 | 0 | 1e-3, 5e-4, 2.5e-4, 1.25e-4 | 1.5e-4, 6.4e-9, 1.6e-15, 0 | 0, small gradient |

The fixture's solve never rejects a step and never meets a cap. To reach those rules a second scenario was
added ("solve rules"): particles 40 and 400 times the model, where the clamp at 20 leaves the matrix too
small. There the first steps are capped (0.1 rad, 1 pixel) and rejected three or four times in a row, the
damping climbs by 4, 8, 16, 32 and falls by halves, and the solve ends on a small predicted decrease after 15
iterations. These solves do not return to the planted pose, and should not: for a particle 40 times the
model the Euclidean loss prefers a slice of higher power (0.9467 against 0.9506 at the planted pose). They
are judged by replaying 9.3.7's rules on the trace.

**Decisions taken under delegation.**
- **Q48.** The solve's trace holds seven numbers per iteration (objective held, damping, accepted, the two
  step lengths, the predicted decrease, the trial objective), so that every rule can be replayed from it.
- **Q49.** Numbers outside decision 5, each frozen before the run that it judged except where said:
  `MIN_MARGIN` 1e-3 (*derived*, Q37); the printed weights' 5e-8 (*derived*, Q39); a first step recomputed by
  another elimination, 1e-9 (*derived*: five equations of condition number up to 1e4); a short step (both
  lengths below 1e-3) whose predicted decrease is above 1e-10 must decrease the objective by the prediction
  to 1e-2 (*derived* from the size of the cubic term, but written after the fixture's trace had been seen,
  where the two agree to the four digits printed: it is a coarse net for a wrong prediction formula, which
  plant `s08` shows it catches, not a measured tolerance).
- The explicit gather of the self-check sums the kernel over four lattice points per axis (64 terms, at most
  27 not zero) by their distances, so it holds no rounding rule at all; Q32 had said 27 points.
- A broadband volume for the reference's checks, beside the fixture's (above).
- The fixture is exported (`oracle_pose_fixture`, `oracle_pose_fixture_pose`), for the driver and a later
  tester.
- `new` and `set_particle` do not validate their arguments (a cube of even side, `0 <= kfrom <= kto <
  box/2`, pixel arrays of side `box + 1`, `kto + 1` variances); an objective other than 'cc' is Euclidean.
- The floor of 9.3.5 is tested from both sides: powers 1e-24 times smaller leave the correlation unchanged,
  1e-40 times smaller give NaN.

**What no check reaches or pins** (stated so that it is not taken as verified):
- In the solve: the stop on a pivot (status 3), eight rejections in a row (status 4; three and four in a row
  are exercised), the limit of 40 iterations (status 5), the stop on a small step or a small relative
  decrease (status 1), a rejection because the predicted decrease is not positive or the trial is not
  finite, and the two bounds of the damping.
- "Taken only if strictly below the start's": the objective held is below the start's exactly when a step
  was accepted, so the rule cannot fire.
- The scaling `sc`: by construction it cancels in the step and acts only through the floors of the damped
  diagonal and the norm of the gradient's stop; the value 1e-8 of that stop is pinned from above only.
- "Hermitian" cannot fail for a real volume except through the transform itself.

**The independent review** (a read-only subagent, 22:50 to 23:04) found no departure from 9.3 and no blocking
point. It re-derived the reference's embedding and transform, the window's weights (0.6907, 0.1547), the
pixel counts, the Euler product and both quarter-turn matrices, the two hand coordinates, the gather, every
sum of 9.3.6 with `J_1` to `J_3` component by component from `R exp([omega]x)`, the correlation's matrix as
the exact second derivative at a positive multiple, the shift-only terms, the multiples' closed forms, and
every rule of 9.3.7 and Q34 in order; and that the central difference of the local gradient is the second
derivative where the gradient is zero. Its "should fix" findings were applied before this entry:
- two procedure headers of four lines (and one found in the shift map);
- the floor's size was not pinned (a floor of epsilon passed): the two-sided test above, plant `p43`;
- the scale under the weighted-power floor was only tested for not being NaN: now one, plant `p44`;
- the rules' replay used the solve's own prediction and lengths: the first step is now recomputed from the
  derivatives by another elimination (the damped diagonal, the caps as scalings, the prediction; plants
  `s15`, `s16`, `s08`), a trial below the predicted stop is counted (plant `s17`), and the fixture's solves
  must end on an accepted step by the gradient's or the step's stop;
- an exact equality between two evaluations of an objective near zero residual: now 1e-12 of the start's
  objective;
- the weights of the scale's two sums were pinned by the same formula typed twice: a particle that is the
  model times a factor per shell is added, its scale against a full-plane sum (plant `p45`);
- two `maxval` that a single NaN could pass; a division by a zero objective; an underflow in the increment's
  second coefficient for a tiny rotation vector.

**The repository's flag sets** (an extra, ungated compile to inform decision 9's integration; no CMake is
run; `keep/drivers/repo_flags.sh`, `keep/logs/phase3_repo_flags.log`). The three modules of this plan and
`mlxf_oracle_dft`, each file alone, with the flags of `cmake/CompilerConfig.cmake` and `-Werror` under GNU
Fortran 16.2:
- Debug (`-O0 -g -fbacktrace -Wuninitialized -Wunused -fcheck=bounds,do,mem`): no warning; 25, 21 and 32
  checks pass.
- Release (`-O3`): no warning; all pass, with the `-O2` numbers.
- Debug with the traps of `MLXF_DEBUG_TRAPS` (`-ffpe-trap=invalid,zero,overflow -finit-real=snan`): no
  warning. The first run trapped in `oracle_polar_valid`, which compared a NaN that the self-check hands it
  on purpose; the function now tests for NaN first (its result is unchanged: a NaN is invalid). After that
  all three self-checks pass under the traps, which also shows that no passing path reads a real before
  setting it.

After the guard every build, self-check and control of the three modules was rerun from scratch on the
finished tree (Phase 4's entry has the numbers).

**An incident of the run, not of the oracles.** One command waited three minutes on itself: the wait for the
maintainer's timed job matched, with `pgrep -f`, a sibling subshell whose command line quoted the pattern.
No build ran during the wait. The wait is now `keep/drivers/wait_timed_job.sh`, whose pattern cannot match
its own text. No timed job was ever found running before a batch of builds.

**What it means, in short.** The pose oracle computes 9.3 as written; decision 10's factors are fixed by
checks that the other readings fail; the gather, the model and the powers are held to closed forms and hand
values; and the solve recovers the planted pose in four steps. Its rules are replayed on a harder case, and
the rules that no case reaches are listed above.

### Phase 4, the report: done (2026-11-24, 23:19 to 23:24 EST, the Mac)

Documentation only. Files changed: `doc/implementation_notes/completed/mlxf_oracles2_report.md` (new) and
this note. No Fortran file was edited in this phase; the final verification below was started at the end of
Phase 3, after its last edit, and read here.

**Exit.**
1. *The report exists:* met, in the order of `doc/how2s/how2write_agent_plans.md`, section 8: what was
   learned; what changed, phase by phase, with the exported names; the decisions taken under delegation, the
   choices where section 9 left one first; the deviations; the evidence, with the table of errors at both
   levels; what is left open, with what the Mac integration must do; a commit message; the drivers.
2. *`scripts/check_tree.sh` passes:* met; it lists six untracked sources, the first run's three and this
   run's three. `keep/logs/phase4_check_tree.log`.
3. *Only file-table paths changed:* met. Against the base snapshot, `diff -rq` shows this note changed and
   four files new: the three modules and the report. `git status` shows the same on top of the maintainer's
   own uncommitted files. `keep/logs/phase4_diff_against_base.log`.

**The final verification, from scratch on the finished tree** (`keep/drivers/final_verify.sh`; *measured*):
- Both levels build `mlxf_oracle_dft`, the three new modules and the four drivers, each file alone, with no
  compiler output: `keep/logs/phase4_final_build_{O0,O2}.log` are empty.
- The four self-checks pass: 12, 25, 21 and 32 checks. The three new ones print the lines of their phases'
  logs, digit for digit. `keep/logs/phase4_final_run_{dft,polar,shiftmap,pose}_main_{O0,O2}.log`.
- The controls: 40, 66 and 76 plants, every one failing at least one check; 25 of 25, 21 of 21 and 32 of 32
  checks covered. `keep/logs/phase4_{polar,shiftmap,pose}_controls.log`.
- Both formatters with `--check` on the three files: nothing to format.
- Compile and run times: 0.2 to 0.5 s a module at `-O0` and 0.5 to 1.0 s at `-O2`; 0.1 to 0.5 s a
  self-check. `keep/logs/phase4_timings.log`.

**Totals.** Three modules, 3,616 lines (911, 950, 1,755); 78 checks; 182 plants; largest errors as the report
tabulates them. Time: 26, 21, 29, 51 and 5 minutes against boxes of 30, 90, 90, 180 and 30 (the report was
drafted while Phase 3's final verification ran).

**Decisions taken under delegation in this phase:** none beyond the report's wording. Two scratch
explorations of the solve that Phase 3 ran without keeping their output were rerun and their output kept
(`keep/logs/phase3_explore_{far_start,hard}.log`), so that the report's finding 5 has a log behind it.

**What it means, in short.** The three oracles are written, checked standalone at both levels and under the
repository's own flag sets, and every check is shown to fail under a plant. What is not shown is what the
plan reserves for the Mac integration and for the maintainer: the build inside the repository's trees, the
agreement with the existing polar oracle and the shift-map tester, with an MLX kernel, and with SIMPLE; and
the readings Q17, Q34 and Q42, which only SIMPLE's source can settle.

### The review (2026-11-24, 23:35, Claude in the maintainer's session)

- **Rebuilt** (*measured*, GNU Fortran 16.2, `-std=f2018 -Wall -Wextra -Werror` at `-O0 -g -fcheck=all` and
  `-O2`, the run's drivers): no compiler output; the polar objectives 25 of 25 (largest error 1.9e-15 and
  2.6e-15), the shift map 21 of 21 (2.1e-9, the truncated Bessel form against the direct cell), the pose
  objective 32 of 32.
- **The contested choice is SIMPLE's.** The run took `rho_max` as the grid's last ring where section 9.2.2 did
  not define it, and its own reviewer read that as a stop. SIMPLE's `build_map` computes the number of
  directions from `rhos(nrho)`, the last ring (`pftc/simple_polarft_shiftmap.f90` at `d354efee2`).
- **No formula of section 9 was contradicted by a check** (decision 8): the gradients agree with central
  differences to 4.5e-10 and the matrices with second derivatives at zero residual to 3.0e-10.
- **The shift map imports the polar module's procedures,** which the contract's first bullet did not allow for.
  Rule `defs` permits it, and it removes a copy of the direct loss.
- **Decision 9's comparison, done the same evening** (*measured*, a scratch driver linked against the test
  executable's objects; two geometries, pftsz 16 and 32, with the data rounded once to single precision so
  that both sides read the same numbers). **The two sides agree to rounding.**
  - Distances, 1,152 of them: against the existing polar oracle as called, 4.0e-8 at most, which is its
    single-precision memos; against a double-precision replica of its route, 2.2e-15. Row `n` is `irot = n`,
    and a banked particle's shift `u` is the new oracle's `M(irot) u`.
  - Shift-map cells, 90,624 of them, against the tester's own evaluation: 1.8e-15. The areas are identical.
    Mode and width in 288 cases: no index differs; the loss within 8.9e-16, the width within 2.1e-14.
  - Differences of convention, none changing a value: the validity limit is `-log(1e-10)` taken in double
    here and in single there (23.0258509299 against 23.0258509166); the tester's rotation argument is 0-based;
    the tester sums the full ring where this oracle sums the half.
  - Not comparable, for want of a double-precision counterpart: the correlations, the reductions over
    references, the truncated Bessel values and the width cutoff.
- **Branches of the reference solve that no check reaches,** from the run's report: the pivot stop, eight
  rejections in a row, the limit of 40 iterations, the small-step stop and the damping's bounds. The fixture's
  solve takes four steps and never rejects.

