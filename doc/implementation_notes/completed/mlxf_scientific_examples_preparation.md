# Scientific examples: completed design and host-reference preparation

Status, 2026-11-24: completed preparation record, split at `26387c1`. Example 1 was delivered through
milestone 1; the independent host references for examples 2 and 3 are delivered. Device implementations
of those later examples, their calibration and tutorials remain in
[the active scientific-examples note](../planned/mlxf_scientific_examples.md).

The original example-1 design and dated Progress are retained below. They are historical: later milestone
decisions corrected the evidence normalizer, aligned Bessel truncation with SIMPLE and added the cutoff.
Use [milestone 1](mlxf_milestone1.md) for that active contract and its
[completed delivery record](mlxf_milestone1_m2.md) for implementation evidence.
The old scratch-artifact concern is addressed by the durable host-reference reconstruction recorded below;
it does not imply future GPU tests have run.

## 3. Example 1: polar matching and shift maps

Delivered by milestone 1 (decisions 15 to 18, Phase 5b). This section is the design reference it cites.

### Fixture and mathematical contract

Retain milestone 1's dense fixture: half-ring length 32, 10 shells, 8 references and 6 particles per half,
96 valid pairs, temperatures 0, 1, 30 and 1e4. Extend its workspace and fixture rather than creating another
scorer. For shiftmap mechanics add a smaller case: full ring `Nrot=24`, shells 1:4, box 32, 5 particles,
7 references in each of two distinct halves; particle IDs alternate halves. Use candidate IDs
`[7,2,5]`, then a permutation and a duplicate, to exercise sparse non-contiguous mapping and tail tiles.

Build asymmetric rings from explicit low angular harmonics. For `theta=2*pi*m/Nrot`, `m=0:Nrot-1`, a
suitable family is

```
phi = (2*j+h)/7.0 + k/11.0
R(m,k,j,h) = 1 + .03*k + .07*j + .11*h
           + .21*cos(2*theta+phi) + .13*cos(4*theta-phi)
           + i*(.31*sin(theta+phi) + .17*cos(3*theta-phi))
```

It obeys `R(theta+pi)=conjg(R(theta))`; form the rounded second half by conjugation. CTFs are real, angularly varying and pi-periodic; start with
`C_i(m,k)=.6+.2*cos(2*theta+.3*i)+.1*sin(.2*k)`. Half spectra are
`sigma2(k,1)=.5+.1*k`, `sigma2(k,2)=.8+.05*k`, with `w=k/sigma2`.
A particle is a selected reference shifted in its own frame, then rotated, then multiplied by its CTF.
Use zero perturbation for the truth case and
`.01*(cos(2*theta+.4*k)+i*sin(theta+.2*i))` for a perturbed case. Fix particle 1 to reference 2, rotation
index 4 and shift `[1,0]`; choose other poses by a written integer table, not the optimized generator.

Use SIMPLE's angular convention explicitly: `a_x=2*pi*k*sin(theta)/box`,
`a_y=-2*pi*k*cos(theta)/box`. With zero-based rotation offset `r`, let `q=modulo(m-r,Nrot)`:

```
Rpose(m,k) = R(q,k,j,h) * exp(i*(a_x(q,k)*sx + a_y(q,k)*sy))
L(r,s;i,j) = sum_(m,k) w(k,h)*abs(X_i(m,k)-C_i(m,k)*Rpose(m,k))**2
            / sum_(m,k) w(k,h)*abs(X_i(m,k))**2
```

Both sums cover the full ring. This is equivalent to a half-ring ratio; do not lose or add a factor two.
The denominator must be positive; an all-zero particle is a rejected fixture/input, not a NaN result.
At zero shift the device route is the existing batched contraction, inverse real FFT and dense row tail.
Its output includes the Nyquist angular bin.

Shift radii are `[0,.5,1,1.5]` pixels; 16 directions, `alpha=2*pi*a/16`. The device route computes the
Fourier-Bessel weighted shell contractions and a batched 2D transform over rotation/direction, keeping
radius and candidate pair as batch dimensions. Precompute Bessel weights on the CPU in real64 and round
once; GPU Bessel evaluation is not required. The defining identity is
`exp(i*z*sin(theta-alpha)) = sum_n J_n(z)*exp(i*n*(theta-alpha))`.
The oracle evaluates the residual above directly at **every** grid point, without Bessel tables or FFTs.
For `zmax=2*pi*kmax*rho_max/box`, choose the smallest K for which
`r=zmax/(2*(K+2))<1` and
`2*exp(zmax**2/(4*(K+2)))*(zmax/2)**(K+1)/factorial(K+1)/(1-r) <= 1e-12`.
This conservative absolute phase-tail bound follows by bounding the Bessel power series and then its
remaining orders by a geometric series (derived target, below the float32 error budget). Compute it in
log form for larger K; verify the retained expansion against direct phases before using it. Modulo
folding must retain orders beyond either FFT axis. Truncation never comes from observed GPU error.

Return mode, loss and physical posterior width for each candidate, plus optional log evidence. For cell
`(a,r,rho)`, use `ell=-T*L-prior_w*rho**2+log(area_rho)`. Annular cell boundaries are midpoints between
radii, zero at the inner origin and half a step beyond the outer radius; divide each annulus by the
number of directions. Include the area of the origin cells. Define
`logz=logsumexp_(a,r,rho)(ell)-logsumexp_(a,rho)(-prior_w*rho**2+log(area_rho))`,
as in SIMPLE: a flat loss L gives `logz=log(Nrot)-T*L`. Width is the square root of the trace of
shift covariance **in the particle frame**, after applying the ordinary column-vector 2D rotation by
`+2*pi*r/Nrot` to the reference-frame shift (the convention in the direct residual above). Compute width
at `T_phys`, not automatically at the mode's tempered `T`.

Production currently uses `shiftmap_mode`; stochastic disk draws are a separate optional diagnostic.
Dense in-plane sampling remains part of milestone 1. Use supplied uniform variates keyed by global IDs;
do not substitute an MLX RNG or promise GPU/CPU equality for draws arbitrarily close to a CDF boundary.

### Assertions and useful failure cases

- All distance rows and all small shiftmaps match direct residuals; the zero-radius map is the dense
  unshifted row and is independent of shift direction. Compare intermediate contractions as well as poses.
- The noise-free case recovers its known pose when the independent best/second-best margin exceeds twice
  the error bound. Flat/tied rows use the first Fortran-order position, explicitly tested separately. A map
  of more than one dimension is flattened with the library's Fortran-order `reshape` first, since MLX's
  arg-minimum follows row-major order; MLX's tie rule on the GPU is established by the test, not assumed.
- The alternating Nyquist ring has loss 0 at identity and 4 after one angular step (unit CTF, equal rings).
  A second case uses `Nrot=8`, box 16, shells 1:3, radii `[0,4,8]`, and
  `Nalpha=7`, with the tail rule requiring orders beyond both FFT axes, to catch omitted folding.
- Direct log-sum-exp and grid moments check evidence and width. Include zero prior, a flat likelihood,
  distinct physical/tempered temperatures, and a width-cutoff equality and rejection.
- Half-specific references, weights and changed-reference invalidation; candidate permutations, duplicate
  IDs, tiles with one live entry, and a non-divisible particle/candidate count. Padding never enters a draw.
- CDF and draw tests retain milestone 1's calibrated gates. An exact four-equal-weight case checks the
  specified boundary convention; non-boundary variates check indices; sensitive draws report CDF error.
- Negative controls: omit Nyquist, reverse shift sign, mix halves, omit cell area, use the tempered
  temperature for physical width. Each must fail its relevant assertion before the test is accepted.

Keep full maps on device through mode/moment reductions; copy compact results back. A map-copy-to-CPU
version is useful for validation and precision diagnosis, but include that copy/synchronization in its
benchmark. Continuous shift/pose optimization is outside this example.

## Progress

2026-11-23, durable host preparation (Codex, M5 preparation Phase 4):

- The old `/private/tmp/check_mlxf_toy_design.py` and log were absent on this laptop. Reconstructed
  self-contained standard-library probes from the equations above, with source anchors checked at this
  note's existing SIMPLE pin `7ec7e2972` (available locally). The later M5 comparator pin `0a8b0903e`
  remains absent locally; no equivalence to its optimized kernels is inferred.
- Portable evidence is retained under
  `~/agent_work/mlxf_m5_preparation/4706ecb/host_references/`: `check_mlxf_host_references.py`,
  `manifest.json`, `host-reference-results.json`, `run.log` and six isolated negative-control copies/logs.
  Run with `python3 check_mlxf_host_references.py` in a writable directory; no package installation or
  sibling checkout is needed. Source SHA-256:
  `cbd573db5b3e193d94db72f17d297d62add04420870189586bee9a0630ef03f6`.
- All **247** host checks pass at the unchanged initial real64 normwise cap `1e-12`. The largest normalized
  error is `4.018729e-15`. The scripts record every reference norm, error and explicit scale used for zero
  references. This does not calibrate or validate any future float32/device tolerance.
- Spectral checks cover both specified shapes, analytic attenuation versus host DFT, Hermitian reality,
  DC, every label, outside support, streamed composition and the two half-specific cost terms. Analytic
  comparisons use the specified ideal modes; rounded-input comparisons explicitly include the filtered
  quantization residual. Thus float32 input rounding is not mistaken for a real64 operator error.
- For both the ordinary window and zero-face variant, the full explicit 64-by-64 stencil matrix agrees
  with the independently transformed padded basis at `6.92e-16` / `6.70e-16` relative norm. Cholesky has
  positive pivots; true matrix residuals for the rounded RHS are `2.12e-16` / `1.33e-16` relative norm.
  The solution's difference from the unrounded manufactured input is separately recorded (about
  `1.02e-7` / `1.10e-7` in absolute norm). No candidate/device PCG operator supplies an expected answer;
  the optional host PCG dry run was unnecessary and was not implemented.
- Projection checks cover all three proper rotations, scalar I0-series geometry, 72 polar samples and a
  Cartesian slice, direct padded DFT sums, centered-point compensation, complex adjoint/observation
  weights, density versus squared stencil, duplicate periodic destinations, signed and Nyquist/zero-plane
  addressing, packed expansion and the real multiplicity-weighted adjoint. Fixture distance from a
  half-integer is at least `0.021539` (above the unchanged `1e-4` safeguard); exact boundary queries are
  checked separately. The padded DFT comparison is `2.34e-16` and packed adjoint `1.64e-16` normalized.
- Wrong inverse scale, label origin, half inputs, padding compensation, adjoint conjugation and packed
  multiplicity each fail their named assertion and exit 1 in an independent source copy. The positive
  source exits 0; commands, source hashes, expected failures and logs are in the manifest.
- Dependencies remain explicit: full 3D FFT wrappers belong to parity Phase 5; projection needs the
  existing gather plus stencil arithmetic; the adjoint needs complex/real scatter-add and later collision
  assessment. No new wrapper, scientific Fortran source, registry entry or CTest process was added.
  Device implementations, residency, performance and scientific validation remain at the existing hold.

2026-11-22: inspected SIMPLE kernels and tester routines, mlx-fortran's public core, current test registry,
binding/test policies and milestone-1 plan. Defined three examples and their boundaries; no Fortran,
wrapper, CTest or production code changed. All implementation phases remain pending. Documentation
validation and mathematical dry runs are recorded below.

Host-only mathematical dry run (Python standard library, in scratch): the 24-angle fixture recovered
reference-frame shift `[1,0]` and rotation index 4 with zero loss; the runner-up pose loss was 0.0089094.
At the main fixture's largest phase argument, the order-12 Bessel expansion differed from the direct
phase by 3.22e-13. The padded FFT PCG operator matched the independent stencil matrix to 7.62e-16
relative; real64 PCG reached a 1.59e-11 true residual in 12 iterations and agreed with Cholesky to
1.78e-11. Filter-bank DFT/analytic agreement was below 2e-15 relative. Normalized KB weights summed
to one within 2.22e-16, and the centered-point padding scale was exactly the stated `1/6**3` to
double precision. These check the proposed equations; they are not Fortran, float32, MLX or GPU test
results, do not calibrate device tolerances, and do not complete implementation Phase 0. Scratch evidence:
`/private/tmp/check_mlxf_toy_design.py` and `/private/tmp/check_mlxf_toy_design.log`.

Documentation validation: all 19 referenced SIMPLE source files and the relative milestone link exist;
Markdown fences and whitespace checked; `git diff --check` and mlx-fortran's `scripts/check_tree.sh`
passed. The pre-existing history text was preserved exactly. SIMPLE remained clean. No compilation was
needed for this documentation-only change; Debug/Release and device gates remain implementation exits.

2026-11-22, review and integration (interactive):
- The review `mlxf_scientific_examples_review.md` checked the derivations numerically and found them sound.
  It also checked the SIMPLE conventions at `7ec7e2972` and found them faithful.
- On Hans's ruling, example 1 moved into milestone 1 (decision 9 here; decisions 15 to 18 and Phase 5b
  there).
- Applied here from the review:
  - the scheduling rule (decision 10);
  - the stencil rounding and fixture margin (decision 11);
  - the primitive list per phase;
  - tester names that sit beside their modules;
  - the Fortran-order arg-minimum note;
  - the home of the frozen tolerances;
  - the use of the PorF and exp_gate profiles once their commit is recorded.
- Still open: the dry-run evidence in `/private/tmp` on the Mac is cleared by a reboot. Copy
  `check_mlxf_toy_design.py` and its log to `~/agent_work/` or into the repository. The plan-form
  conversion (pinned base, change type per phase, stop list, gates no ruling may waive) happens at the hold.

2026-11-22, example 1 delivered (run `mlxf_m1`, Phase 5b of milestone 1, M2 Ultra):
- The shift maps live in `src/test/mlxf_kernel_polar_table_shiftmap.f90`, a submodule of the polar table
  workspace. It prepares the Bessel weights (host real64, K from the tail rule at 1e-12, rounded once) with
  the references. Per tile of pairs, on the device: one real contraction over the shells per order, the
  orders folded onto the directions, the 2D transform, then the mode, the width at the physical temperature
  and the log evidence. Only the compact results come back (the maps when asked).
- The tester `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90` (sub-suite `polar_shiftmap` of
  `kernels`) uses this section's fixtures and a direct real64 residual oracle. Its caps (decision 17 there)
  were confirmed on the CPU device and frozen in `src/test/mlxf_test_defs.f90` before the first GPU run.
  It passes 574 checks on both devices. The five negative controls of the section each failed their
  assertion when planted.
- `bench_polar_table suite=shiftmap` measures SIMPLE's window and screen grids. The milestone plan's Phase 5b
  Progress entry has the numbers and logs.
- Findings against this note:
  - With SIMPLE's normaliser (`shiftmap_prior` over every cell, rotations included), a flat likelihood gives
    log evidence -T L, not log(Nrot) - T L.
  - The tail rule keeps more orders than SIMPLE's `JTOL` (K 21 against 16 on the window, 41 against 32 on the
    screen).
  - No CDF cap applies: the maps return their modes.
  - `width_cutoff` is not implemented; the width is computed for every candidate, as SIMPLE's benchmark does.
