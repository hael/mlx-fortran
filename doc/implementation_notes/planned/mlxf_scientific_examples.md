# Three scientific examples for mlx-fortran

Status, 2026-11-22: design ready for review; implementation not started. Requested by Hans as a
hermetic sandbox and public examples for the Apple Silicon GPU work. SIMPLE source pin:
`7ec7e29720b3e57c2a56a6a7ab754e6f6c57fe35`. mlx-fortran source pin:
`0d3537b5996d1fb74e5beb9ba151a044cf109411`, plus the uncommitted milestone-1 planning and test-policy
updates inspected on 2026-11-22. Record the eventual implementation base afresh; this is not a claim
that those working-tree updates are in that commit.

Depends on [milestone 1](mlxf_milestone1.md): core delivered; operations, polar pipeline and its
`unit_kernels` area not yet implemented in the inspected tree. This note owns the three-example
sandbox. Milestone 1 continues to own its dense polar pipeline, calibration and performance verdict;
reuse that work, do not implement it twice. This design does not launch or broaden the pending run.

## 1. Purpose and grouping

Use three small scientific problems to exercise the computation and data movement of SIMPLE without
requiring SIMPLE, FFTW, image files, a downloaded model or an external data set at test time:

| Example | Scientific story | SIMPLE work represented | Main MLX operations |
| --- | --- | --- | --- |
| 1. Polar matching and shift maps | Identify a rotated, translated noisy image | Dense polar search; candidate shiftmap construction, mode and uncertainty | Batched complex products, 1D/2D FFTs, reductions, scans |
| 2. Spectral volume processing | Filter a volume locally and solve a regularized inverse problem | NU candidate filtering/composition; PCG operator, preconditioner and iteration | 3D FFTs, spectral multiplication, masks, vector updates, dot products |
| 3. Fourier projection and its adjoint | Cut views through a Fourier volume and put observations back | Volume reprojection; gridding and PCG accumulator setup | Coordinate transforms, normalized interpolation, gather and scatter |

PCG and NU share example 2 because they reuse volume transforms and residency. Reprojection and gridding
share example 3 because a matched forward/adjoint pair supplies a particularly strong correctness test.
These are three worked examples, with several small assertions each, not three monolithic integration tests.

The PorF and exp_gate BENCH folders Hans supplied support prioritizing example 1: table fill is 73.15%
and 81.24% of summed matcher worker time. Within fill thread-seconds, scoring is 14.45%/8.51%, shiftmap
construction 34.96%/57.28%, and map selection/posterior reduction 10.38%/15.54%. These nested map timers
must not be added to the containing refinement timer. NU filtering totals 463.56/291.71 elapsed seconds.
Both runs use gridding; neither measures PCG. These profiles motivate scope, not GPU speedup promises.
Their producing commit and machine are not recorded in the supplied files; they do not replace milestone
1's pinned, same-machine production baseline. Local evidence: `~/for_claude/bench/{PorF,exp_gate}/BENCH`.

## 2. Decisions and contract

1. (2026-11-22, Hans) Define three hermetic examples, include volume reprojection, use SIMPLE's kernels
   and tests as the design basis, and make the result useful to other mlx-fortran users.
2. (2026-11-22, design default) The grouping is the table above. The first delivery remains dense scoring
   through milestone 1; shiftmaps complete the first scientific example. Reprojection is an early,
   independent gather exercise once the indexing primitives exist. Scatter follows its forward operator.
3. (2026-11-22, design default) All scientific code is test-only in `src/test/`, importing the public
   `mlxf` interface. The library acquires only general array operations. No new executable, application
   framework, backend hierarchy, dependency on a sibling checkout, or installed cryo-EM API.
4. (2026-11-22, design default) Each example has one fixture generator, a plain-Fortran real64/complex(real64)
   reference, a device implementation, an asserting tester and a measure-only benchmark. Expected results
   never call MLX, the optimized stencil builder, or the implementation under test. Generate inputs once, round to the device's input
   precision, and evaluate the oracle on those same rounded inputs.
5. (2026-11-22, design default) Ordinary array operations first. Compile or fuse only after a measured
   bottleneck. No custom Metal kernel is a prerequisite for a working example. Inputs and outputs use
   Fortran order, dimensions and 1-based positions throughout.
6. (2026-11-22, design default) Correctness uses float32/complex64 on each device with
   `MLX_ENABLE_TF32=0`; reference arithmetic is host Fortran real64. Do not use MLX's CPU FFT as a
   double-precision oracle. GPU float64 is unavailable. Preserve milestone 1's separately specified
   schedule-identity gate; new arithmetic checks use tolerances, with exact checks for indices and data
   movement. Atomic scatter is not promised to be repeatable bit for bit.
7. (2026-11-22, design default) Fixed-cost checks join `unit_kernels`; no additional CTest process beyond
   milestone 1's planned budget of 8. Primitive wrapper tests join `unit_ops`/`unit_fft`. Larger correctness
   variants use named-only sub-suites where needed; timings use `bench_*`, never CTest or a speed threshold.
8. (2026-11-22, design default) Every test is in memory, single submitting thread, bounded independently of
   device memory and core count, and leaves no files. Use analytic inputs or a specified fixed integer
   sequence, not processor-dependent `random_number` sequences. Benchmarks alone may write requested TSVs.

Defaults taken without a question: example names, fixture dimensions, provisional error caps, proposed
sub-suite names and the order below. No existing milestone-1 acceptance rule is replaced.

The off-state contract is unchanged: compiling with tests excluded adds none of the example code to the
library. Fresh implementations of the equations belong to mlx-fortran; source links below are design
references, not an instruction to copy SIMPLE's modules or test harness into the public library.

## 3. Example 1: polar matching and shift maps

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
  the error bound. Flat/tied rows use the first Fortran-order position, explicitly tested separately.
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

## 4. Example 2: spectral volume processing

### A. A filter bank with local composition

Use an `8 x 8 x 8` periodic real volume, indexed by `x,y,z=0:7`:

```
v = cos(2*pi*x/8) + .5*sin(2*pi*(y+z)/8) + .25*cos(2*pi*(2*x+z)/8)
e = v + .125*sin(2*pi*3*x/8)
o = v + .125*cos(2*pi*3*y/8)
B_l(q) = 1/sqrt(1+(abs(q)/cutoff_l)**8), cutoff = [1,2,3]
e_l = inverse_DFT(B_l * DFT(e)); o_l likewise
```

The two perturbations are diagnostic signals, not a statistical model of independent experimental noise.
The specified Butterworth bank is a small illustrative bank, not a replica of SIMPLE's whole NU policy.
Transform each half once, apply the bank in bounded tiles, and compose output voxels using 1-based labels.
First prescribe a label field with all three labels (three x-slabs), a spherical support and label 1
outside support. Then separately test the cross-half cost
`u_l=((e-o_l)**2+(e_l-o)**2)/(2*sigma0**2)` for a fixed `sigma0=.5`, and first-minimum selection.
Do not entangle filtering correctness with an unimplemented Potts optimizer or noise estimator.

The oracle attenuates each known Fourier mode by its analytic filter value; a small separable host DFT
provides a second check. For the objective, evaluate the scalar formula directly. For composition, compare
each output voxel with its independently calculated candidate, including outside-support voxels.

Assert DC gain one, real output/Hermitian symmetry, filter attenuation, every label exercised, and streamed
versus all-at-once composition. Constants and single modes isolate normalization. An unequal `6 x 8 x 10`
case catches swapped dimensions. Wrong FFT scale, wrong label base and swapped half inputs are controls.
This captures the measured expensive filtering/composition work; it does not assert NU scientific quality.

### B. A small PCG problem with a genuinely independent solution

Use `N=4`, padded `M=8`: 64 unknowns. `C` center-embeds an N-cube in an M-cube; `C^T` crops exactly the
same entries. `F` is an unnormalized forward DFT with inverse normalized by `M**3`. `S` is a diagonal
spatial window: 1 at interior voxels, .5 at boundary voxels; a separate case zeros one face. Define

```
d(q) = 1 + 4*(sin(pi*qx/M)**2 + sin(pi*qy/M)**2 + sin(pi*qz/M)**2)
lambda = .25
H = S C^T F^-1 diag(d) F C S + lambda I
P^-1 = C^T F^-1 diag(1/(d+lambda)) F C
```

Both H and the preconditioner are symmetric positive definite, even with zero entries in S. Since
`1 <= d <= 13` and `0 <= S <= 1`, `lambda_min(H)>=.25` and `lambda_max(H)<=13.25`: condition number at
most 53 (derived). This resembles the padded convolution, support and spectral preconditioning in PCG
without depending on the approximate reconstruction kernel or on example 3's gridding implementation.

The independent H is **not built by applying the device operator to basis vectors**. On the M-grid its
spectral part is exactly the seven-point periodic stencil `7*v - six neighbours`. Build that explicit
64-by-64 cropped/windowed matrix in host real64, with lambda on the diagonal. Manufacture
`x_true(i,j,k)=real(1+modulo(3*i+5*j+7*k,11),real64)/11.0_real64`, for zero-based i,j,k, then form `b=H*x_true` on the host.
Round b once for the device and solve that rounded system independently by host Cholesky; report the
rounding difference from x_true separately. Form the reference preconditioner with host DFT sums.

The device implementation keeps volume vectors resident, runs the FFT operator/preconditioner and PCG
updates through `mlxf`, and copies only scalar decisions per iteration. Host orchestration of these
scalars is allowed. A CPU-real64 dot-product fallback is diagnostic and must count full-vector access and
synchronization; it is not a device-resident performance result.

Assertions: H*x versus the stencil matrix; symmetry and positive curvature; P^-1 versus the host formula;
solution and **true residual recomputed by the host matrix** versus Cholesky; nonzero initial guess;
zero RHS; iteration-limit status and a deliberately indefinite case rejected before division by p^T H p.
The unpadded, S=I case has an exact spectral preconditioner and should solve in one mathematical step;
judge its residual with rounding tolerance. Do not require Euclidean residuals to decrease every iteration
or CPU/GPU iteration counts to be identical. Stop at 64 iterations for the small SPD case (design cap).

A `16 x 16 x 16` named-only variant exercises residency/iteration overhead. Benchmarks scale volume size
without constructing a dense matrix; correctness remains anchored to the small oracle.

## 5. Example 3: Fourier projection and its adjoint

Use a real `6 x 6 x 6` asymmetric two-blob phantom, with centered coordinates `x=i-1-N/2`:
`v=exp(-|x-(-1,0,1)|^2/2)+.7*exp(-|x-(1,1,-1)|^2/(2*.7^2))`. Center-pad to `12^3` (factor 2).
Use three proper rotation matrices: identity, a 90-degree z rotation, and
`Rz(c=3/5,s=4/5) * Ry(c=5/13,s=12/13)`. Write the matrices explicitly in the fixture.
Polar output uses 12 full-ring angles and shells 1:2: 72 samples. Add a short Cartesian central slice
case and explicit boundary queries as separate assertions.

### Operator and reference

SIMPLE's polar sample coordinates are `(k*sin(theta), -k*cos(theta), 0)`. Row vectors multiply R on the
right, and padded coordinates are twice that result. For a coordinate t on each axis, choose
`nint(t)+[-1,0,1]` (Fortran's half-away-from-zero rule). Compute separable three-point Kaiser-Bessel
weights, normalized to sum to one **on each axis**:

```
K(delta) = I0(beta*sqrt(1-(delta/1.5)**2)) for abs(delta)<=1.5, else 0
beta = pi*sqrt((3.0/2.0)**2*(2.0-.5)**2-.8)
G(sample,voxel) = wx*wy*wz for its 27 stencil entries
```

Combine duplicate periodic destinations by addition. Address signed Fourier coordinates with
`1+modulo(h,M)` in an unshifted Fourier array. Build an independent small explicit G on the host from
scalar geometry and a converged real64 I0 series; it must not consume device indices or weights.
The device builds its geometry/weights through ordinary operations (a documented polynomial/series),
gathers 27 coefficients and reduces. CPU-prepared stencils are a bring-up comparator only; timing names
whether geometry is prepared or included. Constant Fourier fields check normalization; arbitrary complex
fields and oblique views test the whole interpolation, not only axis-aligned special cases.

For the full volume-to-projection route, center-pad the real phantom, move the center to the DFT origin,
and use `Fpad=DFT(vpad)/M**3`. Output is `8 * G*Fpad`, reproducing SIMPLE's padding-scale compensation.
The independent reference is a direct host DFT followed by the host matrix. A unit point at the centered
origin gives every sample `1/N**3` (derived). Do not compare off-grid KB interpolation directly with an
analytic continuous projection: interpolation error is a different quantity from implementation error.

First test the full complex Fourier-grid gather and its Euclidean adjoint:
`<G*z,y>=<z,G^H*y>`. Test both operands against the independently assembled matrix; an adjoint identity
alone could pass if both sides shared the same wrong coordinates. Then include a complex diagonal
CTF/phase factor D, `A=D*G`, to require conjugation in the adjoint. Add positive observation weights.
For gridding, test the raw numerator `G^H*(w*conjg(D)*y)` and density `G^T*(w*abs(D)**2)` separately.
The density uses the stencil weights once; it is **not** the diagonal of `A^H W A`, which squares them.
Start with MLX scatter-add; measure collisions and repeated-run differences. Deterministic accumulation
is a later subcase with an explicit ordering/tree, not an assumed property of sorting and cumsum.

Finally pack the volume's Hermitian half along dimension 1 and compare with full-grid expansion. Negative
h conjugates the Friedel mate, and h=0/Nyquist planes need their remaining conjugate symmetries. For the
packed adjoint, use the real inner product induced by full expansion, including multiplicity weights;
fold conjugate contributions rather than dropping the negative half. The full-grid explicit operator is
the oracle for this convention. Test h<0, h=0, Nyquist, wraparound stencil neighbours, and half-integer
coordinates on both sides of zero. No out-of-range read is hidden by clamping.

Controls: transpose R, omit conjugation, drop a repeated scatter destination, use C-order flattening,
omit the factor 8, or mishandle a negative frequency. The corresponding gate must fail. Reprojection's
forward gather can be completed and benchmarked before scatter is implemented.

## 6. Common validation and performance contract

All fixture sizes above are design choices, not measured optimum sizes. Before the first GPU judgment,
run each reference against a closed form or independent construction, then the unfused CPU-device
implementation twice, and freeze named tolerances in the existing `mlxf_test_defs`. The existing polar
calibration remains authoritative. Initial caps for the **new** cases are below; they are provisional,
not results. A cap that cannot survive an unchanged CPU reference is a finding, not permission to widen it.

| Quantity | Initial cap and origin |
| --- | --- |
| Scalar/matrix sums and interpolation | `1e-5 * sum(abs(terms))`, milestone-1 inherited guessed factor; use both absolute and normwise checks near zero |
| FFT chains and complete shiftmap/filter/operator output | normalized L2 error `1e-4`, guessed cap for these small float32 chains; record max error too |
| Shiftmap log evidence, CDF and moments | calibrated against direct host grid sums at each temperature, with absolute caps `1e-4` in log/CDF units and `1e-4*max(1,rho_max**2)` for variance (guessed); inherited dense-draw rules unchanged |
| Adjoint/symmetry defect | `1e-5*(norm(Gz)*norm(y)+norm(z)*norm(G^H y))`, inherited 1e-5 scale; no division by a nearly cancelling inner product |
| PCG true relative residual and relative solution error | `1e-4` and `1e-3`, guessed small-SPD gates; zero RHS judged absolutely; host Cholesky/stencil agreement `1e-12` normwise |
| Indices, masks, padding exclusion, data movement | exact, derived from their discrete contracts; require winner margins for floating-point argmin |

For nonzero reference arrays use `norm(error)/norm(reference)`; for a zero reference use the input/operator
scale from the appropriate row. No arbitrary `max(1,norm(reference))` may hide a small physical signal.
Check NaN/Inf explicitly. Plant each listed negative control and prove the gate fails. Check three repeated
evaluations, non-divisible tile tails, and synchronous/two-slot consumption at fixed inputs. After a bounded
100-cycle workspace create/use/kill exercise, synchronize, release graphs and clear caches: live handles
and active owned allocations return to baseline. The existing 10,000-cycle library leak gate stays intact.

Benchmark exactly the tested implementation at larger sizes. Separate one-time preparation/compilation,
resident compute, scalar synchronization, output transfer and end-to-end time. Synchronize timed work;
warm up once and report three completed measurements and spread, not graph-construction time. Record
runtime/compiler/device versions, precision, shape, useful versus padded work, MLX peak and host staging.
Use a fixed caller memory budget and prune tiles before allocation; never make a fast test scale to the
machine's memory limit. Synthetic timing does not establish SIMPLE end-to-end speedup or scientific parity.

## 7. Implementation sequence and repository fit

These are future commands, not commands available in the inspected core-only checkout:

```
mlxf_test_exec test=unit_kernels suite=polar_table device=all     # milestone 1
mlxf_test_exec test=unit_kernels suite=polar_shiftmap device=all
mlxf_test_exec test=unit_kernels suite=spectral_volume device=all
mlxf_test_exec test=unit_kernels suite=fourier_projection device=all
```

`polar_table` and `polar_shiftmap` are the two parts of one public example. The proposed measure-only
entries are the existing planned `bench_polar_table` (extended with shiftmap mode), `bench_spectral_volume`
and `bench_fourier_projection`. Reuse milestone 1's dispatcher. No three extra driver programs.

| Phase | Work and exit | Kind |
| --- | --- | --- |
| 0 | Pin the implementation tree after the milestone-1 work settles; Debug/Release baseline gates, source-reference check, oracle dry runs and CPU calibration. Record unmet primitives rather than calling them available. Exit: fixtures, negative controls and tolerance records are reviewable; no GPU result claimed. | Reference/tests |
| 1 | Reuse delivered polar_table, add shiftmap construction against the full direct grid, then mode/width/evidence. Exit: both devices, layout/tail/half/lifetime cases and frozen numerical gates pass. | Test kernels plus required general operations |
| 2 | Build the reprojection gather, host G and padding/Hermitian tests. It can proceed after indexing/FFT primitives, independently of the volume solve. Exit: forward oracle and controls pass; preparation and resident timings separated. | Test kernel/general operations |
| 3 | Add spectral filter bank/composition, then stencil-backed H and PCG. Exit: analytic attenuation, explicit matrix, Cholesky, true residual and termination gates pass on both devices. | Test kernels/general operations |
| 4 | Add adjoint/scatter, density and packed-half duality tests. Exit: matrix and adjoint gates pass; collision and repeatability results recorded without a deterministic-scatter claim. | Test kernel/general operations |
| 5 | Publish three tutorials pointing to the actual source and test commands; run benchmarks at bounded sizes. Exit: clean Debug/Release gates, public-API-only examples and measured results; no production SIMPLE changes. | Documentation/measurement |

Primitive requirements beyond milestone 1: 2D/3D complex and real FFTs with explicit dimensions/norm;
indexed gather and scatter-add; elementary functions/minimum-position operations needed by these formulas.
Use mlx-c's existing FFT and indexing interfaces, with Fortran dimension/index translation in the wrapper.
Add a wrapper only when its phase needs it, together with its area test. There is no need for autodiff,
neural-network layers, a GPU Bessel function or an MLX-provided PCG solver.

[MLX documents n-dimensional FFTs](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.fft.fftn.html);
the local mlx-c 0.8.0 `mlx/c/fft.h` exposes the complex/real n-dimensional forms and `mlx/c/ops.h` exposes
gather/scatter. Availability upstream is not availability in the present Fortran public API.

### File table for the future implementation

| File | Responsibility | Phase |
| --- | --- | --- |
| `src/test/mlxf_kernel_polar_table*.f90` | Existing milestone-1 owner and fixture; extend with candidate shiftmap workspace, not another scorer | 1 |
| `src/test/mlxf_polar_shiftmap_tester.f90` | Direct angular oracle, physical moments and failure controls | 0,1 |
| `src/test/mlxf_kernel_spectral_volume.f90`, `mlxf_spectral_volume_tester.f90` | Filter bank, PCG example, scalar formulas and explicit stencil/Cholesky reference | 0,3 |
| `src/test/mlxf_kernel_fourier_projection.f90`, `mlxf_fourier_projection_tester.f90` | Forward/adjoint, independent G, Hermitian and scale tests | 0,2,4 |
| `src/test/mlxf_test_dft.f90` | Shared host real64/complex(real64) DFT reference, only when the second consumer exists | 0-3 |
| `src/test/mlxf_test_defs.f90`, `mlxf_test_registry.f90` | Frozen constants and sub-suite/benchmark registration | 0-4 |
| `src/test/mlxf_bench_polar_table.f90`, `mlxf_bench_spectral_volume.f90`, `mlxf_bench_fourier_projection.f90` | Measure-only entries using the tested kernels | 1-5 |
| `src/core/fft/`, `src/core/ops/` and their area testers | Only the generic operations a phase actually needs, after milestone 1 creates these owners | 1-4 |
| `src/core/array/` helper interfaces/submodules, `src/core/mlxf.f90`, `src/defs/mlxf_defs.f90` | Signature-class helpers and public exports/constants as needed; no ownership-model redesign | 1-4 |
| `doc/user/examples/{polar_matching,spectral_volume,fourier_projection}.md` | Three tutorials with equations, runnable commands, interpretation and scale-up instructions | 5 |
| This note; `doc/history/YYYY-MM.md` | One evolving contract and its delivery record | each |

Before each implementation exit: static gate, touched-source formatters, zero-warning Debug and Release
builds, fast gate and both-device outputs. Respect `test_devices`/`MLXF_REQUIRE_GPU`; a skip is not a GPU
pass. If fixed-cost coverage outgrows the fast tier, register a named-only extension with a small fast
counterpart testing the same contract, not a new unbudgeted process.

Stop and diagnose: a required primitive unavailable in the linked mlx-c or an unsupported dtype, wrong baseline pin, shared oracle
logic, a tolerance/control conflict, a handle-lifetime defect, or reliance on atomic order for a claimed
identity. Update this file's table before expanding scope. No acceptance number may be relaxed to pass.
A future SIMPLE integration still needs its real-data and scientific gates; these examples establish the
numerical and binding contracts, not that integration's acceptance.

## 8. SIMPLE source and test anchors

Paths below are relative to the pinned SIMPLE checkout and are reading references only. Tests consume
none of these files. Inspect routine names again when implementation starts.

| Example | Production anchors | Test patterns to carry over |
| --- | --- | --- |
| Polar | `src/main/pftc/simple_polarft_block.f90` (`score_block_posterior`); `simple_polarft_shiftmap.f90` (`gen_shiftmap_kernel`, `shiftmap_draw`, `shiftmap_mode`); `simple_polar_shiftmap.f90` | `simple_polarft_shiftmap_tester.f90`: Nyquist, beyond-ring orders, physical width, cache lifecycle; `simple_polar_shiftmap_tester.f90`: phase-ramp closed form, peak recovery, cell areas; `src/main/commanders/test/simple_test_polar_fixture.f90`: shift/rotation conventions |
| Spectral | `src/main/nu_filt/simple_nu_filter_bank.f90`, `simple_nu_filter_apply.f90`; `src/main/volume/simple_reconstructor_pcg.f90` (`apply_normal_kernel`, `apply_precond`, `dot_real_volume`); `src/main/opt/simple_pcg_solver.f90` | `simple_nu_filter_tester.f90`: `test_objective_closed_form`, `test_composition_per_label`; `src/main/commanders/test/simple_commanders_test_highlevel_pcg.f90`: operator/solver gates, rounded-scale and streaming checks |
| Projection | `src/main/image/simple_projector_pft_batch.f90` (`fproject_polar_batch_opt`); `simple_projector.f90`; `src/main/interp/simple_kbinterpol.f90`; `src/main/volume/simple_pcg_lattice.f90` | `simple_pcg_lattice_tester.f90`: adjoint and independent geometry checks; `src/main/interp/simple_cartesian_fourier_tester.f90`: Fourier addressing; `src/main/image/simple_image_tester.f90`: origins/normalization |

Relevant existing SIMPLE entry points: `test=unit_pftc_align2D3D`, `test=unit_reconstruction`,
`test=unit_image`, `test=pcg_recon`, and `test=polar_matching_bench`. They informed the design; they are
not runtime dependencies or substitutes for an independent oracle in mlx-fortran.

## Progress

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
