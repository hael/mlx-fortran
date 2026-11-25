# K8, family D: the PCG solve of the reconstruction as a toy `reconstructor_pcg` (run `mlxf_kernel_k8`, on the M5 Ultra)

Status, 2026-11-25: planned and ruled (the maintainer's go); run in the session on the M5 Ultra, in order K1, K8, K2. **Run `mlxf_kernel_k8` stopped in Phase 0 (2026-11-25, 09:48): decision 10's F2 fails at 4N, 8N and 16N planes (section 7); a ruling is asked at the end of Phase 0's Progress. Ruled (R1, Progress): F2 reported, not gated; the solver judged at 2 and 5 iterations, as SIMPLE runs it; resumes at Phase 1 after K2.** Run `mlxf_kernel_k8` on the M5 Ultra (arun host `local`), one run at a time on
it. Base: the commit that holds this plan (the run pins its hash in Phase 0 and records it); the plan was
checked against the working tree of 2026-11-25 on `1e0ae97`, the maintainer's uncommitted work included.
SIMPLE is read at `d354efee2` with `git -C ~/src/SIMPLE show d354efee2:<path>`, never its working tree, and
is never edited. Supersedes: none. Depends on:
- `mlx_rfftn`, `mlx_irfftn`, `mlx_fftshift` (validated: yes, public in the working tree, sub-suite `fft_nd` of
  `unit_fft` on both devices; no transform larger than (6, 5, 4) has been run or timed);
- `mlxf_oracle_recon_pcg`, `mlxf_oracle_gridding`, `mlxf_oracle_pcg`, `mlxf_oracle_dft` (validated: yes,
  standalone under GNU Fortran 16.2 at `-O0` and `-O2`, 21, 13, 14 and 12 checks; no tester calls them yet);
- `type(mlx_metal_kernel)` (validated: yes, `unit_fast` 94; needed by Phase 4 only, which may not be entered);
- the roadmap's decisions 6, 8, 9 and 11 and the toy-example policy (validated: ruled, 2026-11-24), and its
  decision 15 (stands as recommended, open to the review).

## 1. Why

The maintainer's stake (roadmap, decision 6): "The PCG solve should definitely go on the GPU. It is made for
it. If it can be made to run very fast, we might just use it all the time". In the solve3D record of
2026-11-20 (37,502 particles, box 240, 134 iterations, on another machine) the PCG assembly records summed to
940 s of 3,929 s (*measured*, `completed/mlxf_design.md`, Progress of Phase 0); how that splits into
finalisation and solve is not in the record here. The solve is 3D real transforms, pointwise work and five
inner products per iteration on volumes that can stay on the device; it needs `mlx_rfftn` and `mlx_irfftn`
and nothing else from the library. No transform of the sizes concerned (320³, 512³) has been timed with MLX,
so every time below is to be measured, not estimated.

## 2. Contract

- **Where the code lives:** `src/test/` only. Toy code in modules `mlxf_toy_<stem>` under SIMPLE's type and
  procedure names, written against the public module `mlxf` as a user writes. No file under `src/core/` or
  `src/defs/` changes. A missing or refusing wrapper is a stop with a report, never a private binding.
- **What it mirrors** (read at `d354efee2`; no SIMPLE source is copied):
  - `src/main/volume/simple_reconstructor_pcg.f90`, type `reconstructor_pcg`: `new`, `kill`,
    `set_lambda_relative`, `end_accum` with `finalize_density_accum`, `update_lambda_from_density`,
    `finalize_khat`, `calibrate_kernel` and `build_env`; `apply_normal`, `apply_normal_kernel`,
    `apply_precond`, `dot_real_volume`, `add_ridge`, `deapod_mul`, `window_mul`, `window_div`; `solve_accum`
    with `solve_core`; the private adapter `reconstructor_pcg_adapter`;
  - `src/main/volume/simple_pcg_lattice.f90`, type `pcg_lattice`: the geometry (`box`, `boxpd`, `padf`,
    `pad_off`, `Rnat`, `padsc`), `set_window_sphere`, `install_support`, `mask_mul`,
    `divide_deposition_plane`;
  - `src/main/opt/simple_pcg_solver.f90`: the abstract type `pcg_operator` (`size`, `apply`, `precond`,
    `dot`), the records `pcg_solver_options` and `pcg_solver_outcome`, and `pcg_solve`.
- **The integration owner in SIMPLE,** for the SIMPLE plan that may follow, not for this one: the master's
  assembly in `src/main/strategies/parallelization/simple_rec3D_pcg_strategy.f90`, which makes one
  `reconstructor_pcg` per half, sums the parts' raw accumulators into it, and calls `end_accum` and
  `solve_with_cold_restart`. The toy's canonical driver is that sequence.
- **What is judged:** the device against host oracles in double precision that share no code with the toy;
  repeatability on one GPU configuration as a gate of its own; times never pass or fail.
- **Off-state:** with tests excluded (`--exclude-tests`) none of this code is compiled; the library and its
  installed module are byte-for-byte what they were.
- **Not part of it:** the lattice insertion (K6), the matrix-free operator, symmetry, the ML and atomicity
  priors, warm starts with `cold_restart`, raw-accumulator files, a change to SIMPLE.

### What the check found (2026-11-25)

**SIMPLE at `d354efee2`.**
- **The operator is `P (K + lambda I) P`** (`apply_normal`: `mask_mul` on the input, the kernel operator, then
  `mask_mul` on the result; `apply_normal_kernel`: `embed_fft`, a multiplication of the packed transform by the
  real `Khat`, `ifft_crop`, then `add_ridge`). The mask is binary, `window > 0` (`install_support`).
- **The preconditioner** (`apply_precond`) is `P E Cᵀ F⁻¹ diag(pi) F C E`: the envelope `env`, the same pad and
  transforms around a multiplication by `precond`, the envelope again, then the mask.
- **Every transform is of the padded size.** `box` is the native box (`params%box_crop` in
  `simple_rec3D_pcg_strategy.f90`), `boxpd = padf * box` with `padf = OSMPL_PAD_FAC = 2` (`simple_defs.f90`),
  and the work image is `boxpd³`. The design note's N = 160 and 256 are therefore **native** boxes; their
  padded lattices are 320³ and 512³. This confirms the note's assumption that all transforms are (2N)³.
- **What is real space and what is Fourier space.** On the native box, single precision: the unknown `x`, the
  right-hand side `b_rhs`, the Krylov vectors `r`, `p`, `hp`, `z` (owned by `pcg_solve`), `mask`, `window`,
  `env`, `invenv`. On the packed half of the padded lattice, real, shape `cdim = [boxpd/2 + 1, boxpd, boxpd]`:
  `Khat` and `precond`. The first dimension is the halved one.
- **How `Khat` is built** (`finalize_density_accum`, `finalize_khat`, `calibrate_kernel`): the packed density
  inside `nint(|q|) <= padf * Rnat + ceiling(sqrt(3) (iwinsz + 0.5))` = N + 3; an inverse transform; a
  division by the separable deposition envelope (`divide_deposition_plane`, zero where it is at most 1e-8); a
  forward transform; the real part; times `padsc**2` = 64. Two transforms.
- **The inner product** (`dot_real_volume`) is `sum(real(a,dp) * real(b,dp))`: products and sum in double. The
  engine applies `alpha` and `beta` to the vectors after rounding them to single.
- **The engine's rules** (`simple_pcg_solver.f90`): `PCG_XTOL = 1.5e-2`, `PCG_RESID_REPLACE = 25`; the defaults
  of `pcg_solver_options` are `maxits = 50`, `rtol = 1.0e-4`, `xtol = PCG_XTOL`, `residual_replace = 25`, and
  `solve_core` sets the same 50 and 1.0e-4 when its caller passes none. Per iteration: `apply`, the curvature
  test, the update, the recomputation of `r = b - H x` when the iteration is a multiple of 25, five inner
  products, the `rtol` test before the `xtol` test, then `precond`. Both tests run only when `rtol > 0`.
- **Production does not use those rules.** The reconstruction calls `solve_with_cold_restart(job%x,
  job%l_nonzero, params%maxits_pcg, params%rtol, ...)` (`solve_prepared_half_job`), and the defaults are
  `maxits_pcg = 2` and `rtol = 0.` (`simple_parameters.f90`): **exactly two iterations, neither test active**
  (`stop_reason` "fixed_iterations"). The final reconstruction takes at least 5 (`FINAL_PCG_MAXITS_FLOOR`,
  `simple_solve3D_utils.f90`). The base solve starts from zero every iteration. The rules `rtol` 1e-4, `xtol`
  1.5e-2, 50 iterations apply to a caller that passes nothing; no production caller does.
- **Production's ridge is absolute:** `pcgop%new(params%box_crop, params%smpd_crop, PCG_LAMBDA)` with
  `PCG_LAMBDA = 1.0e-3`; `set_lambda_relative` is called by test commanders only. The oracle's fixture uses a
  relative ridge of 0.05.
- **Transforms per solve:** 2 + 4m for m iterations from zero (one `precond` before the loop, an `apply` and
  a `precond` per iteration, the last `precond` for a diagnostic only), plus 2 per recomputation. The design
  note's "10 at 2 iterations" holds.
- **Where the solve runs.** In the master's assembly (`simple_rec3D_pcg_strategy.f90`): "the full local
  allocation while the workers are idle" (`rec3D_master_nthr`: `min(32, nparts * nthr)`, at most the
  processors), the even and the odd half as two concurrent sections with half the threads each
  (`solve_distributed_half_pair`). On the M5: 15 threads per half. Its times go to
  `BENCH/PCG_ASSEMBLE_BENCH.txt` ("pcg_assemble base operator finalize", "pcg_assemble base solve even half",
  "pcg_assemble base solve iters even").

**The oracles.**
- `mlxf_oracle_recon_pcg` implements the system above (its section 9 in `planned/mlxf_oracles3.md`) with the
  engine's rules as constants (`RTOL_RECON`, `XTOL_RECON`, `MAXITS_RECON`, `RECOMPUTE_EVERY`), a solve whose
  rules can be set (`set_rules`; `rtol <= 0` asks for exactly `maxits` iterations), and the packed arrays in
  the shape `(m/2 + 1, m, m)`.
- On its three-plane fixture (*measured*, `completed/mlxf_oracles3_report.md`): under the engine's rules the
  solve stops on `xtol` at iteration 11 at N = 4, 8.7 % from the direct solution, and at iteration 27 at N = 8;
  the preconditioner raises the condition number from 55.5 to 1,106 (N = 4) and from 228 to 3.6e11 (N = 8).
- **The oracles cannot run at bench size as they are.** Their transforms are direct sums: 3 M⁴ complex
  multiply-adds per 3D transform, 3.1e10 at M = 320 and 2.1e11 at M = 512 (*derived*). `oracle_grid_plane%new`
  transforms the phantom by a direct sum over n³ voxels at (n + 1)² points: 1.1e12 exponentials at n = 256
  (*derived*). No oracle module has an OpenMP directive (*exact*, `rg`).
- `mlxf_oracle_pcg` is the examples note's stencil problem, `H = S Cᵀ F⁻¹ diag(d) F C S + lambda I` with a soft
  window `S`. It is not SIMPLE's operator; it has what the reconstruction fixture lacks, a manufactured
  solution.

**The library and the tests.**
- `mlx_rfftn(a[, dims][, n][, norm])` keeps the half-size dimension first (dimension 1 when `dims` is absent)
  and pads with zeros to `n`; the default norm is backward. Frozen errors on (6, 5, 4) fixtures: 4 float32
  epsilons, 4.18 for `mlx_irfftn` (*measured*, parity Progress, "Phase 10a").
- `unit_kernels` has four suites (`polarft_calc`, `polar_shiftmap`, `polar_shiftmap_accuracy`,
  `eul_prob_tab`); the registry's `BENCHES` holds `polar_table`, `NAMED_ONLY` two names; the CTest budget is 9.
- `scripts/run_parts.sh` starts `bench_polar_table` only. This run does not use it.

## 3. Decisions and rulings

**Ruled (2026-11-25, Hans: "Go", on the request that set out these decisions with their recommendations): every decision of this section as recommended.** No `BENCH/PCG_ASSEMBLE_BENCH.txt` was named, so decision 21's gap stands: no SIMPLE record is set beside the toy's times. The order of the runs is K1, then K8, then K2, one at a time on the M5 Ultra, each from the state that holds the previous one's verified result.

All dated 2026-11-25 and recommended, unless a ruling is cited. The maintainer's rulings are asked for
decisions 1, 3, 8, 11, 21 and 22.

1. **Scope: one half's assembly after the reduction, from the raw packed accumulators to the shipped map.**
   The toy takes the packed numerator `B` and density `D` of the padded lattice, as the master holds them after
   it has summed the parts' files, and does what `end_accum(.true.)` and `solve_accum` do: the right-hand side
   (1 transform), the preconditioner's spectrum, the ridge, `Khat` (2 transforms), the solve, the window. The
   operator is the kernel operator only.
2. **Modules,** all new, in `src/test/`:

   | Module (file of the same name) | Holds |
   | --- | --- |
   | `mlxf_toy_pcg_solver` | the abstract type `pcg_operator`, the type `pcg_solver_outcome`, `pcg_solve` |
   | `mlxf_toy_reconstructor_pcg` | the type `reconstructor_pcg`: host members under SIMPLE's names, one component `ws`, the private adapter |
   | `mlxf_toy_reconstructor_pcg_workspace` | the type `reconstructor_pcg_workspace`: every MLX handle and compiled function of the operator |
   | `mlxf_toy_pcg_solver_tester`, `mlxf_toy_reconstructor_pcg_tester` | the suites `pcg_solver`, `reconstructor_pcg` and the named-only `reconstructor_pcg_n32` |
   | `mlxf_oracle_recon_fixture` | the full-coverage fixture (decision 9): plain Fortran in double, no MLX |
   | `mlxf_bench_recon_pcg` | the benchmark `bench_recon_pcg` (decision 19) |

   The record `pcg_solver_options` goes where rule `defs` sends a behaviourless record another module builds:
   `src/test/mlxf_test_defs.f90`. A module is split into submodules by concern when it passes 700 lines
   (decision 23 covers the rows).
3. **One toy type; the lattice is folded in.** SIMPLE's `reconstructor_pcg` extends `pcg_lattice`. The toy has
   the one type `reconstructor_pcg`, with the lattice's members it reads and `set_window_sphere` and `mask_mul`
   bound to it; the ledger's lines name them as `reconstructor_pcg`'s, which they are by inheritance. A toy
   `pcg_lattice` of its own waits for a toy that needs the lattice's gather and scatter (family C).
4. **Names and dummies are SIMPLE's, with these changes,** each a line of the differences (decision 5):
   - `new( self, box, lambda )`: `smpd` and `fft_nthreads` are dropped (nothing reads them).
   - `end_accum( self, l_kernel )`: `d_raw` is dropped; `l_kernel = .false.` is refused.
   - `solve_accum( self, x, maxits, rtol, rel_res_hist, niters, outcome, start_max_rel_resid )` keeps SIMPLE's
     eight dummies (the ledger's arity exemption), `x` a host `real(real32)` volume in and out.
     `solve_core` is folded into it: a private procedure may not have eight dummies.
   - `apply_normal( self, p ) result(hp)`, `apply_normal_kernel( self, p ) result(hp)`,
     `apply_precond( self, r ) result(z)`: the volumes are `type(mlx_array)`, the results unevaluated.
     `apply_precond` is public, where SIMPLE's is private behind `apply_preconditioner`.
   - `dot_real_volume( self, a, b ) result(d)`: `d` is a `type(mlx_array)`, the device half of the inner
     product (decision 12); the engine finishes it on the host.
   - `pcg_operator`'s deferred `apply`, `precond` and `dot` take and return handles; `pcg_solve( op, b, x,
     options, outcome )` takes `b` and `x` as handles.
   - `pcg_solver_options` keeps `maxits`, `rtol`, `xtol`, `residual_replace`, `start_max_rel_residual`;
     `pcg_solver_outcome` keeps `stop_reason`, `iteration_count`, `requested_maxits`, `initial_rel_residual`,
     `final_rel_residual`, `final_rel_update`, `failure_curvature`, `failure_iteration`, `converged`,
     `start_rejected`, `rhs_norm`, `start_norm`, the residual and update histories and `iteration_seconds`.
   - Where SIMPLE stops (`THROW_HARD`: a zero right-hand side, a non-positive first `r·z`, sizes that differ,
     `maxits < 1`), the toy returns with `x` untouched and a reason in `stop_reason` and in an added inquiry
     `message`; no status argument is added to a mirrored procedure.
   - Additions, each with its reason in the ledger: `set_raw_accum( self, b, d )` (stands for the reduction of
     the parts' files; the inverse of SIMPLE's `get_raw_accum`), `message`, `stage_seconds`, `host_waits`, and
     the workspace's bindings.
5. **The seam,** which the report restates with measured bytes:
   - **Who owns the device state.** `reconstructor_pcg%ws`, an allocatable `reconstructor_pcg_workspace`,
     allocated in `new` and released in `kill`. The engine holds `x`, `r`, `p`, `hp` and `z` as local handles
     for the length of one `pcg_solve`, as SIMPLE's engine owns its Krylov vectors. Nothing else holds a handle.
   - **What is resident,** from `end_accum` to `kill`: `Khat`, the preconditioner's spectrum, the envelope,
     the mask and `b_rhs`; during a solve the five vectors as well. 2.63e8 B at N = 160 and 1.08e9 B at N = 256
     (*derived*, decision 20's table).
   - **What crosses.** In: `B` and `D` once (`set_raw_accum`; no host copy is kept), a non-zero start. Out: per
     host wait the partial sums of the inner products (N² float32 values each); at the end the map.
   - **Where the host waits.** Once at the end of `end_accum`; in `pcg_solve` once before the loop, twice per
     iteration (decision 13) and once for the map: 2m + 2 for m iterations.
   - **Host work that stays host work:** the shell statistics of the density (the preconditioner's floors and
     thresholds, the ridge's scale), in double, as in `finalize_density_accum` and
     `update_lambda_from_density`; the window and the mask; the stop tests.
6. **Layouts, in Fortran's view.**
   - A native volume is `(N, N, N)` float32, the first index fastest, voxel `N/2 + 1` the centre: SIMPLE's
     `rmat(1:box, 1:box, 1:box)`.
   - A spectrum of the padded lattice is `(M/2 + 1, M, M)`, M = 2N: **dimension 1 is the halved one**,
     element `h + 1` for h = 0 .. M/2, and dimensions 2 and 3 hold k and m at `1 + modulo(k, M)`. This is
     SIMPLE's packed `cmat` (`cdim = [fdim(boxpd), boxpd, boxpd]`, the physical addresses of
     `finalize_density_accum`), the oracle's packed shape, and `mlx_rfftn`'s default. `Khat`, the
     preconditioner's spectrum, `B` and `D` pass between the three without a permutation. The plane
     h = M/2 holds what the lattice stores for -M/2.
   - `mlx_irfftn` reads the half spectrum of a real array: of the planes h = 0 and h = M/2 only the Hermitian
     part enters (binding policy, section 10; the oracle report's finding 7). The fixture's planes are
     Friedel-complete with even CTFs, so the packed arrays are Hermitian there.
7. **The device arithmetic of one application** (the graph form; its bits are the toy's, its values the
   oracle's):
   - **Operator:** `u = mask * p`; `s = mlx_rfftn(u, n=[M, M, M])`; `s * Khat`; `mlx_irfftn`; the first N
     elements of each dimension (`mlx_slice`); `+ lambda * u`; `* mask`.
   - **The embedding is at the corner, through the transform's length.** SIMPLE embeds at the centre (offset
     N/2). The two operators are equal: the centre embedding is the corner embedding followed by a translation
     of the periodic lattice, and a translation commutes with a Fourier multiplier (*derived*). The explicit
     matrix, built with the centre embedding, is the check.
   - **Preconditioner:** `mlx_rfftn(env * r, n=[M, M, M])`; times the spectrum; `mlx_irfftn`; the crop; `* env`;
     `* mask`.
   - **`Khat`:** `D` inside the cut N + 3; `mlx_irfftn`; times the reciprocal of `e_M(d1) e_M(d2) e_M(d3)`,
     d the offset from voxel 1, zero where the product is at most 1e-8; `mlx_rfftn`; the real part; times 64.
   - **Right-hand side:** the unscaled inverse transform of `B` (`norm = MLX_FFT_NORMS%forward`);
     `mlx_fftshift` over the three dimensions, which puts the origin at voxel M/2 + 1; the centre N-cube; times
     the reciprocal envelope (zero where the envelope is below 1e-8); times the mask.
   - **Counts:** `end_accum` 3 transforms; a solve of m iterations from zero 4m + 2 floor(m/25) (the toy does
     not precondition after its last iteration, which SIMPLE does for a diagnostic): 8 at m = 2, 20 at m = 5,
     204 at m = 50.
8. **Two systems and five rule sets,** from what the check found:

   | | Ridge | Rules | Why |
   | --- | --- | --- | --- |
   | System P | absolute, 1.0e-3 (`PCG_LAMBDA`) | **F2**: exactly 2 iterations; **F5**: exactly 5 | SIMPLE as it runs (`maxits_pcg`, `FINAL_PCG_MAXITS_FLOOR`) |
   | System R | relative, 0.05 (the oracle's `LAMBDA_REL`) | **E**: `rtol` 1e-4, `xtol` 1.5e-2, at most 50; **R4**: `rtol` 1e-4, `xtol` off, at most 200; **T**: decision 15's tight rule | the engine's own rules; a residual that float32 can reach |

   System P's ridge is far below float32's resolution of the operator (about 1e-7 of the data scale on the
   bench fixture, *guessed*: 1e-3 over 64 times a mean density of order 100), so a residual target has no
   meaning there: it is run as SIMPLE runs it and judged iterate by iterate. "The time to the same true
   residual" is read on system R, and for system P as the time of the same number of iterations.
9. **Fixtures: full angular coverage, by one rule at every size.**
   - **Planes:** P = 4N. The normals are a golden-angle spiral on the hemisphere, `z_j = 1 - (j - 1/2) / P`,
     azimuth `j` times the golden angle; an in-plane angle, a shift in [-1, 1] pixels and a global rotation
     come from `seeded_uniform` (the tester hands the numbers in). Weights cycle 1, 0.75, 1.25; the CTF is the
     oracle's form `1 / (1 + (a h² + b h k + c k²) / N²)` with its three coefficient sets in turn; the noise
     variance is 1.
   - **Why 4N:** a lattice voxel at radius rho lies inside the three-tap window of the planes whose normals
     are within 1.5 / rho of its equator: P · 1.5 / rho of them on average, 6 at rho = N (*derived*).
   - **Data:** two Gaussian blobs, the examples note's phantom scaled by N/6; a plane's sample is the
     continuous transform at `(h, k, 0) R`, a closed form. Nothing is compared with the phantom.
   - **The generator** (`mlxf_oracle_recon_fixture`) deposits by the rules of the oracle's lattice (the disc
     `h² + k² <= (N/2)²`, `loc = 2 (h, k, 0) R`, the window from `oracle_proj_stencil`, the skip, the wrap, the
     factor 8, the packing) and is held to `oracle_recon_lattice` on the same planes at N = 8 and N = 32 within
     1e-12 (the oracle's `TOL_MATRIX`). The oracle is given `B` and `D` rounded once to the device's
     precision, the values the toy receives.
   - **Sizes:**

     | | N | M | P | `mskrad` | Unknowns in the mask | Where |
     | --- | --- | --- | --- | --- | --- | --- |
     | small | 8 | 16 | 32 | 2.5 | 251 (*exact*, the oracle's `IN_MASK`) | fast gate, both devices |
     | named-only | 32 | 64 | 128 | 8 | r < 14, about 11,500 (*derived*) | `suite=reconstructor_pcg_n32` |
     | bench | 160 | 320 | 640 | 56 | r < 62, 1.0e6 (*derived*) | `bench_recon_pcg` |
     | bench | 256 | 512 | 1,024 | 90 | r < 96, 3.7e6 (*derived*) | `bench_recon_pcg` |

     The bench radii are 0.35 N (*guessed*). The design note's 16³ named-only variant becomes N = 32, where the
     mask radius decides the mask; the stencil problem's 8-in-16 case runs in the fast gate.
   - **Seeds:** 1 calibrates; 2 and 3 are judged (`family_seeds`). The bench uses seed 1.
10. **The fixture is accepted in Phase 0, by the oracle, before any device code exists.** At N = 8, seeds 1 to
    3, both systems:
    - **F1, coverage:** at most 2 % of the stored voxels with `nint(|q|) <= N` have a zero in the
      preconditioner's spectrum (*guessed*).
    - **F2, the preconditioner helps** (system R; system P's numbers are recorded): the condition number of
      the preconditioned support block is not above that of the support block itself (eigenvalues of
      `Lᵀ H L`, `M = L Lᵀ` on the support; over the range where `M` has eigenvalues below 1e-10 of its
      largest).
    - **F3, float32 has room on system R:** the support block's condition number is at most 1e3 (*derived*:
      a relative residual of about 1e3 · 6e-8 is below `rtol`).
    - **Margins:** for rule E on each seed, the test that stops the oracle clears its threshold by at least
      5 % at the stop iteration, and neither test is within 5 % of firing earlier (*guessed*). A seed that
      fails this is declared in Phase 0's Progress as "stop iteration reported, not gated"; nothing is added to
      that list later, and no seed is changed.
    - **No tie in the preconditioner:** no stored voxel's density is within 1e-6 relative of its shell's
      threshold (*guessed*).
    - If F1 or F2 fails, P is doubled, to 8N and then 16N, at every size. If 16N fails: stop.
11. **The oracle's use, its limits, and what the run may add to it.**
    - At N = 8: explicit matrices, Cholesky, eigenvalues. At N = 32: `apply`, `precond`, `rhs` and `solve`,
      without matrices. At N = 160 and 256: `new`, `rhs` and `apply`, once each per judged iterate, in the
      benchmark's `suite=accuracy` only (decision 19), in Release.
    - The run may make `dense_matrices`, `support_index`, `symmetric_eigenvalues` and `reference_spectrum`
      of `mlxf_oracle_recon_pcg` public under `oracle_recon_` names. No statement of its arithmetic changes;
      its 21 checks keep their errors to the printed digits.
    - The iterate after k iterations is the oracle's solve under `set_rules(0, 0, k)`. The step quantity of
      iteration k is `|x_k - x_(k-1)| / max(|x_k|, epsilon)`, from two iterates.
    - **Cost at bench size** (*guessed* from the multiply-add counts of section 2: 45 s per transform at
      M = 320, 5 min at M = 512; Phase 0 times one of each): `suite=accuracy` needs 2 transforms for the
      kernel, 1 for the right-hand side and 2 per judged iterate, 11 for four iterates: 8 min at N = 160,
      55 min at N = 256. One oracle system serves both ridges: the ridge's term is added on the host.
12. **The scalars of the recurrence are formed on the host in double precision from device partial sums.**
    - **S2, the form built first:** `dot_real_volume` returns `sum(a * b, dim=1)`, N² float32 partial sums of
      N products each. The engine evaluates the dots of one wait together, copies them out and adds each in
      double. `alpha`, `beta` and the tests are host doubles; `alpha` and `beta` reach the device rounded once
      to float32, as in SIMPLE.
    - **Why not SIMPLE's expression:** the device has no float64. S2's products are rounded to float32 and
      each partial is a float32 sum of N terms; only the last N² additions are exact.
    - **The yardstick, S4:** the host's `sum(real(a, real64) * real(b, real64))` over views of the evaluated
      vectors (`mlx_view`; unified memory, no copy). It is SIMPLE's arithmetic exactly. It is the probe's
      reference and the last rung of the ladder.
    - **The alternatives:** S1, `sum(a * b)` on the device in float32; S3, compensated on the device (an
      error-free product by splitting, a compensated sum over the partials).
    - **The rule, fixed here** (Phase 3 measures every dot of 50 iterations of system R at N = 160 and 256 on
      the GPU, and of the small fixture on both devices, against S4): a form is *accurate* when its largest
      relative error is at most 1e-6 (*derived*: 16 float32 epsilons, the order of the rounding the float32
      updates put into a vector, and four orders below the 5 % margins of decision 10). S2 stays if it is
      accurate. If it is not, S3 replaces it if accurate, else S4. S1 replaces S2 only as part of a form of
      decision 13 that earns its place. If gate (a) fails in Phase 2 and the diagnosis is the scalars, this
      ladder is climbed there, with the same measurement recorded.
    - **The drift, recorded with the same runs:** `| |r_k| - |b - H x_k| | / |b|` for k = 5, 10, .., 50 with
      the recomputation off, both residuals formed on the device and the norm by S4; at k = 50 at N = 160 once
      by the oracle. The drift comes from the float32 updates of `x` and `r`, whatever forms the scalars; it
      says whether a recomputation every 25 iterations suffices. Hypothesis: at most 1e-5 at k = 25.
13. **The host waits twice per iteration; fewer waits must earn their place.**
    - **W2, the form built first:** the first wait returns `p · H p` (for `alpha`), the second the four dots
      after the update and the preconditioning (`r · r`, `x · x`, `p · p`, `r · z`). `alpha` depends on the
      first and `beta` on the second, so two host doubles per iteration need two waits.
    - **Alternatives,** written in the benchmark only (`suite=probe`): W1, `beta` formed on the device in
      float32 and one wait per iteration; W0, both scalars on the device and no wait, possible only under
      F2 and F5, with the m iterations as one graph; C, the iteration's two sub-graphs as compiled functions
      (`mlx_compile`), which fuses the pointwise chains.
    - **The rule** (roadmap decision 15): an alternative enters the toy only if it gains more than 30 % on the
      canonical driver's elapsed time (decision 20) at N = 256 and is not slower at N = 160, passes the gates
      of decisions 14, 15 and 17 at their frozen tolerances, and, for W1 and W0, reaches a true residual within
      10 % of W2's after 2, 5, 25 and 50 iterations. Otherwise it is deleted from the benchmark and recorded
      with its numbers and mechanism.
    - **Several iterations as one graph:** only where no host decision separates them, that is under F2 and
      F5 with both scalars on the device (W0). Under a stop rule one wait per iteration is the least.
    - **The cost of a wait** is measured on its own: the evaluation and copy of N² already computed partial
      sums, the median of 100. Hypothesis: under 1 % of an iteration at N >= 160.
14. **Gates of the operator** (Phase 1; N = 8 on both devices and seeds 1 to 3 unless said; the error measure
    and the ceiling of each are in section 6):
    - **O1** the mask equals the oracle's `support` exactly; the window, the envelope and the reciprocal
      envelope match `window` and the oracle's envelope.
    - **O2** `Khat` against `kernel()`; **O3** the preconditioner's spectrum against `spectrum()`, its zeros
      exactly; **O4** the relative ridge against `ridge()`; **O5** `b_rhs` against `rhs()`.
    - **O6** the operator against the explicit matrix, column by column (512 unit vectors, built unevaluated
      and evaluated 64 at a time); the rows and columns outside the mask are zero exactly.
    - **O7** symmetry on fixed vectors, `<u, H v> = <H u, v>`, also at N = 32.
    - **O8** the preconditioner against its dense matrix, and its symmetry on the support.
    - **O9** `dot_real_volume`, finished by the engine's collection, against the host's double sum of the same
      float32 vectors (judged in Phase 2, when the engine exists).
    - **O10** at N = 32 (named-only): O2 to O5 against the oracle, the operator and the preconditioner on 8
      fixed vectors against `apply` and `precond`.
15. **Gates of the solve** (Phase 2):
    - **The engine on constructed systems,** a test-only operator with small dense matrices, all exact: three
      eigenvalues stop on `rtol` after three iterations; `rtol` before `xtol` when both hold; `xtol` at a step
      of 0.408 against 0.45 and not against 0.4; the epsilon of the step test; `maxits`; fixed iterations; an
      indefinite product at the first iteration and at the second, with `x` as the first step left it; a zero
      right-hand side; a first `r · z` that is zero or negative; a non-zero start that is used; a start
      rejected by `start_max_rel_residual`; 24, 26, 31 and 52 operator applications for 24, 25, 30 and 50
      iterations; an operator changed at iteration 25 whose recomputed residual is reported there.
    - **The stencil problem** (`mlxf_oracle_pcg`; a test-only operator of 60 lines from library transforms):
      the operator against the explicit 64 × 64 matrix; from zero and from the oracle's non-zero guess the
      solution and the true residual, recomputed by the host matrix, against Cholesky on the right-hand side
      rounded once to float32; the zero face; the unpadded case, one iteration; -H refused before its
      division; the cap of two iterations; N = 8 in M = 16 against the oracle's matrix-free route.
    - **(a) The device reproduces the host's iteration** (system R, rule E): for every k up to the oracle's
      stop iteration K, the iterate, the relative residual and the step quantity agree with the oracle's within
      the frozen tolerances; the device stops at K by the same test (exact, on the seeds decision 10 admits).
    - **(a') The same under SIMPLE's production settings** (system P, rules F2 and F5): the iterates k = 1 .. 5
      and their residuals.
    - **(b) Past SIMPLE's rule, the solution is the direct one** (system R, rule T: `rtol_t`, `xtol` off, at
      most 200 iterations): the true residual, recomputed by the explicit matrix in double from the device's
      solution, is at most `rtol_t`; the residual the solve reports agrees with it; the solution agrees with
      Cholesky on the support block. `rtol_t` is 10 times the lowest true residual the device reaches in 200
      iterations on seed 1 on either device (*measured* in Phase 2), and may not exceed 1e-4.
    - **(a) and the true residual at N = 32:** k = 1, 2, 5 and K against the oracle; the final true residual by
      the oracle's `apply`.
    - **Start and ship:** a shipped map as the start (`window_div`), the map shipped (`window_mul` once),
      against the oracle's `start` and `ship`.
16. **Tolerances: measured, then frozen, never moved.** Each inexact gate is first run on seed 1 on both
    devices with its tolerance at its ceiling and its seed list held to seed 1. The frozen value is twice the
    larger of the two devices' errors, not below the floor (4 float32 epsilons, 4.77e-7, for a relative
    error) and not above the ceiling. It is written to `RECON_PCG_TOLERANCES` in `src/test/mlxf_test_defs.f90`
    and to Progress before seeds 2 and 3 run on either device. A measured value above its ceiling is a stop.
17. **Repeatability is a gate of the form that is kept.** In the fast gate: the small fixture's assembly under
    rule E, three times from `new` to `kill` in one process, on each device: the map, the residual history and
    the update history bit for bit (`bits_equal`), the iteration count and the reason equal. At bench size:
    `suite=time` writes the map's bytes (`out=`) and prints the history in hexadecimal; two invocations are
    compared with `cmp` and `diff`, per system and rule. A form that fails is not kept.
18. **A fused Metal kernel gets a phase only if the pointwise work is large enough to pay.**
    - Phase 3 measures `f = 1 - t_fft / t_solve` on the canonical driver for the form Phase 3 keeps, with
      `t_fft` the time of the solve's transforms alone (the same pads, lengths, crops and waits, nothing else).
    - **Phase 4 is entered only if f >= 0.30 at N = 160 or N = 256** (*derived*: below 0.23 a pointwise kernel
      of no cost at all gains less than 30 %; at 0.30 it must remove 77 % of the pointwise time).
    - If entered: one kernel for the multiplication by `Khat`, one for the two updates with their line
      partial sums (one thread per line of N, a fixed order). By the wrapper's measured facts: a kernel object
      per size, since the grid belongs to the object; float32 outputs only, flattened to rank 1, the complex
      product written as float32 pairs (a complex output is untested); no threadgroup above 1,024.
    - It is kept only above 30 % on the canonical driver's elapsed time at N = 256, not slower at N = 160,
      with every gate passed on the GPU. The graph form stays in any case: the reference and the CPU path.
    - Not entered is a result, recorded with f.
19. **The benchmark** `mlxf_test_exec test=bench_recon_pcg suite=<mode> [key=value ...]`, rows appended to
    `./bench_recon_pcg.tsv`:
    - `suite=transform` (Phase 0): one padded forward and inverse transform with its crop, per size and device:
      shapes, round-trip error, time, MLX peak.
    - `suite=probe` (Phase 3): decisions 12, 13 and 18's measurements.
    - `suite=profile`: the canonical driver with a wait after each stage; it explains and does not decide.
    - `suite=time`: decision 20's protocol.
    - `suite=accuracy`: judges like a test. The fixture, the oracle's system, the device's assembly under F2,
      F5, E and R4; O2, O4 and O5 at bench size; each final iterate's true residual by the oracle's `apply`
      against the device's own right-hand side.
    - Keys: `n=`, `system=P|R`, `rules=F2|F5|E|R4`, `device=`, `seed=`, `repeats=`, `out=`, `revision=`. Each
      suite lists the keys it reads; another key stops the program with `error stop 2` and names it.
20. **Timing: one process, alone, as the master runs it.**
    - **Why alone.** The solve runs in the master's assembly between iterations, when the part processes have
      exited and the master has every thread (what the check found). No part shares the GPU or the memory
      then, so there is no 3-process or 6-process case to time (design note, sections 7 and 9).
    - **The canonical driver:** `new`, `set_window_sphere`, `set_raw_accum`, `end_accum(.true.)`,
      `solve_accum` from zero, `kill`, timed from before `set_raw_accum` to the map on the host. `end_accum`
      and `solve_accum` are also reported apart, as SIMPLE's "operator finalize" and "solve" lines are.
    - **Protocol:** Release; `MLX_ENABLE_TF32=0`; nothing else built or run on the machine (decision 24); a
      one-minute load of at most 4 before each timed step, `uptime` recorded; one warm-up pass, then the best
      of three and their spread; two invocations, whose difference is the noise floor.
    - **Reported per size, system and rule:** iterations, stop reason, the true residual (the device's own
      recomputation, and the oracle's from `suite=accuracy`), seconds of `end_accum`, of `solve_accum`, per
      iteration, and of two halves back to back; MLX peak, active and cache memory; the process's peak
      footprint and maximum resident size from `/usr/bin/time -l`.
    - **Memory, one half** (*derived*; float32 and complex64):

      | | N = 160 | N = 256 |
      | --- | --- | --- |
      | `Khat` and the preconditioner's spectrum, two arrays of `(N + 1)(2N)²` float32 | 1.32e8 B | 5.39e8 B |
      | envelope, mask, `b_rhs` | 4.9e7 B | 2.01e8 B |
      | `x`, `r`, `p`, `hp`, `z` | 8.2e7 B | 3.36e8 B |
      | **resident during a solve** | **2.63e8 B** | **1.08e9 B** |
      | one application's transients: padded real, spectrum, product, inverse | 5.26e8 B | 2.15e9 B |
      | host, handed in: `B` (complex64) and `D` | 1.98e8 B | 8.09e8 B |
      | SIMPLE's CPU solve, about 170 N³ B (design note) | 7.0e8 B | 2.85e9 B |

      MLX's working memory inside a transform is unknown. Hypothesis: an MLX peak of at most 4.3e9 B at
      N = 256 (resident, the transients and one more spectrum). The fixture's generator holds 3.2e9 B of double
      accumulators at N = 256 and the oracle about six complex double lattices of 2.15e9 B (*guessed*).
    - **Guard:** N = 256 is run only if N = 160's measured peak footprint times 4.1 is below 0.8 of the
      machine's 103.1 GB.
21. **The CPU reference, and what may be claimed.**
    - **The host oracle's PCG is not a comparator:** it is unthreaded and its transforms are direct sums, hours
      per solve at N = 160 (*derived*). It is absent as a timing.
    - **Measured here:** the same graph form on MLX's CPU device, same fixture, same rules, one process, with
      its CPU utilisation recorded; at N = 256 for F2 only, and only if a pass is predicted under 30 minutes.
      It answers what the GPU adds to MLX's own CPU path. It is not SIMPLE.
    - **SIMPLE itself is not measured** (roadmap rule 4). If the maintainer names a
      `BENCH/PCG_ASSEMBLE_BENCH.txt` of the latest code in the run's rulings file, Phase 0 records its box,
      threads per half, iterations and the seconds of "base operator finalize" and "base solve" per half, and
      the report sets them beside the toy's, scaled by M³ log M when the boxes differ (*derived*, labelled). If
      none is named the gap stands and is said: no record of a PCG solve at box 160 or 256 is in hand.
    - **Not claimed:** a speedup of SIMPLE; anything about a map; that more iterations help under system P;
      behaviour with the ML prior, symmetry or a density mask; that two halves batch.
    - **What makes family D different,** to be said in the report: here the alternative to the GPU really is
      all the cores, since they are idle; and both could work at once, one half each, which is not measured.
22. **One half at a time.** One `reconstructor_pcg` solves one half, as one `pcgop` does in SIMPLE. Two halves
    are timed back to back in one process. Solving the halves or several states as one batch in lockstep is
    not in this plan; the report gives what that design needs (one half's resident and peak bytes, the share of
    the waits).
23. **Rows the run may add.** A new `src/test/mlxf_toy_*.f90` file (a submodule of decision 2's modules) gets
    its row before its first edit, with the reason in Progress. No row is added outside `src/test/`. A losing
    alternative is deleted from the benchmark in the phase that measures it; that it is dead is shown by both
    builds.
24. **The machine is quiet for timed steps.** A measurement during which another `mlxf_test_exec`, `cmake` or
    `gfortran` process ran is discarded and repeated.

Defaults taken without a question: the module, suite and benchmark names; the named-only size; the bench mask
radii; the weights, CTF forms and shifts of the planes; the line as the partial sum's block; the time boxes.

## 4. Not in this plan

- The lattice insertion and its repeatability (K6). The fixture's host loop is not a kernel.
- Batched halves and states (decision 22); a process that serves several solves.
- SIMPLE's ML-regularised pair, its closed-form shrink, the atomicity prior, symmetry, `set_window_volume`.
- Any measurement of SIMPLE, any SIMPLE source change, any wrapper, any file under `src/core/` or `src/defs/`.
- `scripts/run_parts.sh`, `src/test/mlxf_bench_polar_table.f90` and the polar toy's files.
- The accelerated mode (TF32, NAX).
- A CTest entry: the suites join `unit_kernels`, and the process budget stays 9 (`test/CMakeLists.txt` is not
  touched).

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement; test-only code (the fixture module, the oracle's exports, `suite=transform`) | the base's counts; the oracle's 21 checks to their digits; the fixture against the lattice; decision 10; the numbers frozen in Progress |
| 1 | new test-only code: the operator | decision 14 on seeds 2 and 3 at tolerances frozen on seed 1; seven planted violations fail; rule `mirror` |
| 2 | new test-only code: the engine and the solve | decision 15 and decision 17's fast form; nine planted violations fail |
| 3 | measurement; the benchmark's alternatives | decisions 12, 13 and 18 applied as written; Phase 1's and 2's gates again if the form changed |
| 4 | new test-only code under the 30 % rule, or not entered | decision 18; every gate on the GPU |
| 5 | measurement | `suite=accuracy` passes; decision 17 at bench size; decision 20's table complete |
| 6 | documents | the report; `scripts/check_tree.sh`; `git status` shows file-table paths only |

Every phase ends with Debug and Release built from scratch with `-DMLXF_WERROR=ON` (in the run's own trees, by
the recipe of the run's prompt) and no warning, the fast gate 9 of 9 in both,
`scripts/check_tree.sh` passing, and `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` run on
every Fortran file touched, by explicit file name. The existing areas keep their counts: `unit_fast` 94,
`unit_fft` 194, `unit_linalg` 632, `unit_ops` 2,402, `unit_array` 179, `unit_compile` 63, `unit_core` 80 to 82;
`unit_kernels` is 1,063 plus the new suites' counts, each recorded when it is written. The named-only
`unit_kernels suite=reconstructor_pcg_n32` is run by name, on both devices and in both builds, at the exits of
Phases 1 and 2, of Phases 3 and 4 if the form changed, and of Phase 5.

## 6. Acceptance

**Inexact gates,** each frozen by decision 16. "Relative" is a 2-norm (Frobenius for a matrix) over the
reference's; ceilings are *guessed*, from the examples note's section 6, unless tagged.

| Gate | Error measure | Ceiling |
| --- | --- | --- |
| O1 window, envelope | largest element error | 4.77e-7 (*derived*: host doubles rounded once) |
| O2 `Khat` | largest element error over the largest \|reference\| | 1e-4 |
| O3 spectrum, non-zero entries | largest relative element error | 4.77e-7 (*derived*) |
| O4 ridge | relative | 1e-6 (*derived*: one float32 rounding of a double) |
| O5 right-hand side | relative | 1e-4 |
| O6 operator, O8 preconditioner | relative | 1e-4 |
| O7 symmetry | the defect over ‖u‖ ‖H v‖ + ‖H u‖ ‖v‖ | 1e-5 |
| O9 inner product | relative | 1e-6 (*derived*, decision 12) |
| stencil: operator; solution; true residual | relative; relative; in units of \|b\| | 1e-4; 1e-3; 1e-4 |
| (a), (a') iterate | largest over k of the relative error | 1e-3 |
| (a), (a') residual history | largest over k, in units of \|b\| | 2e-6 (*derived*: 0.02 `rtol`, under half of decision 10's margin) |
| (a) step quantity | largest over k, absolute | 3e-4 (*derived*: 0.02 `xtol`) |
| (b) reported against true residual | in units of \|b\| | 0.1 `rtol_t` (*derived*) |
| (b) solution against Cholesky | relative | the smaller of 1e-3 and 10 `rtol_t` times the condition number (*derived*, the oracle's rule) |

**Exact gates:** the mask; the zeros of the preconditioner's spectrum; zeros outside the mask; every count,
reason and stop iteration of decision 15; decision 17. **Planted violations,** each shown to fail its gate on a
scratch copy and then removed, with the failing check named in Progress:
- Phase 1: the crop moved by one voxel (O6); the kernel's scale 64 as 8 (O2); the ridge applied to the
  unmasked input (O6's zeros); the envelope left out on one side of the preconditioner (O8); the
  preconditioner's threshold 0.1 as 0.01 (O3); `mlx_fftshift` left out of the right-hand side (O5); a public
  binding missing from the ledger (rule `mirror`).
- Phase 2: `beta` as `rho' / kappa` ((a) at k = 2); the recomputation every 24 (the application counts); the
  step test without `|alpha|` (the `xtol` case); `xtol` tested before `rtol` (their order); the curvature
  tested after the update ("x as it was"); the window applied twice at exit (ship); the window's floor 0.1 as
  0 (start); a term that depends on a call counter added to the map (decision 17); the stencil's window left
  off one side (its operator gate).
- Phase 5: an iterate stopped one iteration early (`suite=accuracy`); an unread key (`error stop 2`).

**Reported, not gated:** every time and byte count; the condition numbers; the iteration counts of rules E and
R4 at each size; the drift; decision 21's ratios, labelled; the true residuals of system P.
**Reserved for the maintainer:** whether the miniature reads like SIMPLE (the report lists the differences);
what "very fast" means for SIMPLE; the rulings on SIMPLE's source that the oracle left open (T1 of the
oracles' report: the transforms' origin).

## 7. Common rules and stop conditions

- No file outside the table, apart from decision 23's rows. No tolerance, ceiling, margin or fixture changed
  to pass; no seed changed. A failing gate is a diagnosis task.
- No new key, option or member beyond those named here, in the toy. Alternatives live in the benchmark.
- The oracle and the fixture module import no `mlxf` module and no toy module; the toy imports no oracle.
- An executable run directly on the GPU runs with `MLX_ENABLE_TF32=0`. Timed runs are Release.
- The run writes its notes with the editor tools. Git is read-only: nothing is committed or pushed.
- An MLX or mlx-c question the work meets (a transform's working memory, the order of a device sum, the cost
  of an evaluation) gets its entry in `doc/collaboration/apple_questions.md`.

**Stops:**
- a wrapper is missing, refuses a call of decision 7, or `suite=transform` fails at 320³ or 512³ on a device;
- the fixture fails decision 10 at 16N planes;
- a measured tolerance is above its ceiling, or `rtol_t` would exceed 1e-4;
- the device stops at another iteration or by another test than the oracle on an admitted seed, and two
  attempts at a diagnosis do not find a defect of the toy;
- the graph form is not repeatable (decision 17), with the operation that differs named;
- the yardstick S4 cannot be formed (a view of an evaluated vector is refused), or S2 and S3 both fail
  decision 12's rule and S4 fails a gate of decision 15;
- `suite=accuracy` at N = 256 is predicted above 4 hours after it is cut to F2 and R4, or decision 20's guard
  refuses N = 256;
- a change to `src/core/`, `src/defs/` or SIMPLE would be needed; SIMPLE at `d354efee2` contradicts a
  decision; the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
oracle shares no code with the toy; no SIMPLE source copied; tolerances frozen before the seeds they judge;
repeatability of the kept form; the 30 % rule for a second path.

## 8. Phases

### Phase 0, the base, the oracle's reach and the fixtures' conditioning (box: 90 min)

1. Record the machine, the base commit, SIMPLE's commit and the rulings file. Build Debug and Release from
   scratch; run the gate; record the counts of section 5.
2. Check the premises of "What the check found" with `rg` and `git show` at `d354efee2`, and write what the
   check changed. If the rulings file names a BENCH record, read it (decision 21).
3. Add `mlxf_bench_recon_pcg` with `suite=transform` and run it at N = 160 and 256 on both devices: the
   spectrum's shape `(M/2 + 1, M, M)`, the round-trip error, the first times, the MLX peak, three evaluations'
   bits.
4. Make decision 11's four procedures public. Add `mlxf_oracle_recon_fixture`. Run the oracle's 21 checks;
   compare the generator with the lattice at N = 8 and 32.
5. Decision 10 at N = 8, seeds 1 to 3, both systems: F1 to F3, the margins, the ties; for each rule the
   oracle's iterations, reason and residual; the same counts at N = 32 by the matrix-free route.
6. Time one `oracle_dft_3d` at M = 320 and at M = 512 in Release, and one `apply` at N = 160; predict
   `suite=accuracy`'s durations.
7. Freeze in Progress, each number with its origin: P, the admitted seeds, the oracle's counts, the predicted
   durations. Write the dummy lists and members the toy keeps, read from SIMPLE.

**Exit:** the fixture is accepted; the numbers are frozen; both builds are free of warnings; no solver code
exists yet.

### Phase 1, the operator against the explicit matrix (box: 180 min)

`reconstructor_pcg` with its workspace: `new`, `kill`, `set_window_sphere`, `set_lambda_relative`,
`set_raw_accum`, `end_accum`, `mask_mul`, `apply_normal`, `apply_normal_kernel`, `apply_precond`,
`dot_real_volume`, `message`; the ledger's lines; the suites `reconstructor_pcg` and `reconstructor_pcg_n32`
with decision 14's gates. Calibrate on seed 1 on both devices, freeze, then judge seeds 2 and 3.

**Exit:** O1 to O8 and O10 pass at frozen tolerances on both devices; the seven plants of section 6 fail; rule
`mirror` passes; 100 cycles of `new`, `end_accum`, one application and `kill` leave `mlx_live_count` and the
active memory where they were.

### Phase 2, the solve on the small fixture (box: 180 min)

`mlxf_toy_pcg_solver` and `solve_accum`; the suite `pcg_solver` (the constructed systems, the stencil
problem); in `reconstructor_pcg` the gates (a), (a'), (b), start and ship, and decision 17's fast form; in
`reconstructor_pcg_n32` the gates at N = 32. `rtol_t` is measured and frozen first.

**Exit:** O9 and every gate of decision 15 pass on seeds 2 and 3 on both devices; the nine plants fail; each new
fast suite takes under 0.5 s in Release or its registration says why, and the two add at most 5 s to
`unit_kernels` in Release (*guessed*; the measured times are recorded).

### Phase 3, the probe: scalar precision, waits, and the transforms' share (box: 150 min)

In the benchmark's `suite=probe` and `suite=profile`, on the GPU at N = 160 and 256, quiet machine:
1. the canonical driver under F2, F5 and 50 fixed iterations: time, waits, MLX peak, active and cache memory;
2. `t_fft` and f (decision 18); the stage profile;
3. the cost of a wait (decision 13);
4. every dot of 50 iterations by S1, S2, S3 and S4, and the drift (decision 12);
5. W1, W0 and C: times, true residuals after 2, 5, 25 and 50 iterations, peak memory (decision 13).

Then apply the rules as written. A form that enters the toy passes Phase 1's and Phase 2's gates at the
frozen tolerances; if it does not, the earlier form stays.

**Exit:** each rule's outcome is in Progress with its numbers; the benchmark holds no losing alternative; the
decision on Phase 4 is recorded with f.

### Phase 4, the fused pointwise kernels, only if decision 18's condition holds (box: 180 min)

The two kernels of decision 18 behind the workspace, chosen by the device (the CPU device keeps the graph
form). All gates of Phases 1 and 2 on the GPU; decision 17; the canonical driver's times, interleaved with the
graph form's, three repeats each way.

**Exit:** the fused form is kept above 30 % or removed, with its numbers; or "not entered" stands.

### Phase 5, the bench at N = 160 and 256, and the verdict (box: 210 min)

1. `suite=accuracy` at N = 160, then at N = 256 (decision 20's guard first).
2. `suite=time` on the GPU: both sizes, systems P (F2, F5) and R (E, R4), two invocations each with `out=`;
   `cmp` and `diff` (decision 17).
3. `suite=time` on the CPU device, as decision 21 bounds it.
4. The verdict table: per size, system, rule and device the row of decision 20, the SIMPLE record's line
   beside it if one was named, and decision 21's sentences on what the numbers do and do not say.

**Exit:** `suite=accuracy` passes at both sizes; the two invocations agree bit for bit; the table is complete
or each missing cell says why; the two Phase 5 plants fail.

### Phase 6, the record (box: 45 min)

1. `planned/mlxf_kernel_families.md`: section 6 gains the seam with measured bytes, "Differences from
   SIMPLE" and the numbers in hand; section 2a's row and section 8's K8 row follow.
2. `doc/policies/test_environment_policy.md` (the new suites and the benchmark), the plans' index, the
   history, `src/test/test.inf`, the root `README.md` where it names the kernels.
3. The report `completed/mlxf_kernel_k8_report.md`, in the order of the how-to's section 8: what was
   learned, the changes per phase, decisions under delegation, deviations, evidence, what is left open, and a
   commit message without an attribution or co-author line that names every new file.

**Exit:** the report exists; `scripts/check_tree.sh` passes; `git status` shows file-table paths only.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_bench_recon_pcg.f90` (new) | the benchmark and its suites | 0, 3, 4, 5 |
| `src/test/mlxf_oracle_recon_fixture.f90` (new) | the full-coverage fixture | 0 |
| `src/test/mlxf_oracle_recon_pcg.f90` | four procedures made public under `oracle_recon_` names; nothing else | 0 |
| `src/test/mlxf_toy_reconstructor_pcg.f90` (new) | the toy type | 1, 2, 3, 4 |
| `src/test/mlxf_toy_reconstructor_pcg_workspace.f90` (new) | the device state | 1, 2, 3, 4 |
| `src/test/mlxf_toy_reconstructor_pcg_tester.f90` (new) | the suites `reconstructor_pcg`, `reconstructor_pcg_n32` | 1, 2, 3, 4 |
| `src/test/mlxf_toy_pcg_solver.f90` (new) | the engine | 2, 3 |
| `src/test/mlxf_toy_pcg_solver_tester.f90` (new) | the suite `pcg_solver` | 2, 3 |
| `src/test/mlxf_toy_*.f90` (new, decision 23) | submodules of the three toy modules, if a module passes 700 lines | 1, 2, 3, 4 |
| `src/test/mlxf_test_defs.f90` | `pcg_solver_options`, `RECON_PCG_TOLERANCES`, the fixtures' constants | 0, 1, 2, 3, 4 |
| `src/test/mlxf_test_registry.f90` | three `run_suite` rows, one `NAMED_ONLY` name, one `BENCHES` name | 0, 1, 2 |
| `src/test/test.inf` | the directory's description | 6 |
| `scripts/toy_mirror.txt` | the ledger's lines; SIMPLE's files in its header | 1, 2, 3, 4 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | sections 2a, 6 and 8 | 6 |
| `doc/policies/test_environment_policy.md` | the suites and the benchmark | 6 |
| `doc/implementation_notes/README.md` | the index | 6 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 6 |
| `README.md` | the status, where it names the kernels | 6 |
| `doc/collaboration/apple_questions.md` | if a question arises | 0, 3, 4, 5 |
| `doc/implementation_notes/planned/mlxf_kernel_k8.md` | this note: Progress, decision 23's rows | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/completed/mlxf_kernel_k8_report.md` (new) | the report | 6 |

`src/test/mlxf_test_defs.f90`, `src/test/mlxf_test_registry.f90` and `scripts/toy_mirror.txt` are shared with
the other kernel runs: this run starts from a commit that holds every earlier run's result.

## Progress

(one entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was
met, log paths, decisions taken under delegation, and what it means, in short)

### Phase 0, the base, the oracle's reach and the fixtures' conditioning: stopped at decision 10 (2026-11-25, 09:16 to 09:48 EST, M5 Ultra, in the session)

**Stopped by section 7: "the fixture fails decision 10 at 16N planes".** F2 fails at 4N, 8N and 16N on every seed,
and more planes cannot make it pass: the preconditioner of 9.4 is zero beyond `nint(|q|) = N` by design, and the
support's vectors that live there (about 32 of 251 at N = 8) get preconditioned eigenvalues near 1e-4 against a
median of 39. F1, F3, the ties and the oracle's other numbers are in hand. No solver code exists. The ruling
needed is at the end of this entry.

**Machine and base.** M5 Ultra (30 cores, 103,079,215,104 B), GNU Fortran 16.2.0, CMake 4.5.1, MLX 0.32.4
(mlx-c 0.8.0, Homebrew). Base: `6a4d5f9c063d03bedcaa979d7670082693a5055b` plus the maintainer's uncommitted
working tree (60 lines of `git status --porcelain`), copied to the run's `repo`. SIMPLE read at `d354efee2`
(`git show`). The rulings file is empty: no `BENCH/PCG_ASSEMBLE_BENCH.txt` is named, so decision 21's gap stands.
Load before the first step 1.58 (one-minute), the machine otherwise idle. Logs below are under `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k8_work/scratch/keep`.

**Files changed:** `src/test/mlxf_oracle_recon_pcg.f90` (four generic interfaces and one `public` line, nothing
else: `keep/mlxf_oracle_recon_pcg.base.f90` is the base copy), `src/test/mlxf_oracle_recon_fixture.f90` (new),
`src/test/mlxf_bench_recon_pcg.f90` (new, `suite=transform` only), `src/test/mlxf_test_defs.f90`
(`RECON_PCG_BENCH_N`), `src/test/mlxf_test_registry.f90` (`BENCHES` gains `recon_pcg`, its `case`),
`doc/collaboration/apple_questions.md` (question 25), this entry.

| Exit item | Result | Evidence |
| --- | --- | --- |
| Base builds | Debug and Release from scratch with `MLXF_WERROR=ON`: 0 warnings, fast gate 9 of 9 | `p0_{debug,release}.{build,gate}.log` |
| Base counts (*measured*, both builds) | `unit_fast` 94, `unit_fft` 194, `unit_linalg` 632, `unit_ops` **2,462**, `unit_array` **193**, `unit_compile` 63, `unit_core` 81 (Debug) and 82 (Release), `unit_kernels` **1,281**; GPU devices 1. Section 5's 2,402, 179 and 1,063 are older trees': the base holds the maintainer's later work and K1's suites. These are the counts later phases keep | `p0_counts.log` |
| Premises at `d354efee2` (step 2) | every bullet of "What the check found" re-read and confirmed: `apply_normal` masks in and out, `install_support` `window > 0`, `khat_lim = padf Rnat + ceiling(sqrt(3) (iwinsz + 0.5))` = N + 3 (`KBWINSZ` 1.5, `OSMPL_PAD_FAC` 2), `dot_real_volume` in double, the engine's defaults and order, `maxits_pcg=2`, `rtol=0.`, `FINAL_PCG_MAXITS_FLOOR = 5`, `PCG_LAMBDA = 1.0e-3`, `solve_with_cold_restart(job%x, job%l_nonzero, params%maxits_pcg, params%rtol, ...)`, `set_window_sphere(params%msk_crop)`. Nothing changed | `git show` copies in `scratch/simple_*.f90` (reading only) |
| `suite=transform` at 320³ and 512³ (step 3) | see the table below; shape, round trip and three evaluations' bits hold on both devices; no stop | `p0_transform/` |
| The oracle's 21 checks (step 4) | 21 of 21 at `-O0 -g -fcheck=all` and `-O2`, the digits of the oracles' report (`solve rtol` 2.2119e-3 and 2.2121e-3 against 5.5473e-2) | `p0_oracle_selfcheck_O{0,2}.log` |
| The generator against the lattice (step 4) | largest relative difference **0** (bit equal) on the packed numerator and density, seeds 1 to 3, at N = 8 (4N, 8N, 16N planes) and N = 32 (4N); limit 1e-12 | `p0_decision10_n{8,32}_p*.log` |
| Decision 10 at N = 8 (step 5) | **F2 fails at 4N, 8N and 16N**: stop | below |
| The oracle's cost (step 6) | below | `p0_oracle_timing.log` |
| Both builds at the exit | Debug and Release from scratch with `MLXF_WERROR=ON`: 0 warnings, fast gate 9 of 9 (11.2 s and 10.7 s), `scripts/check_tree.sh` passing, both formatters run on the five Fortran files touched (0 rewritten); every count as at the base except `unit_core` 80 in Debug (81 at the base: inside section 5's 80 to 82); `suite=transform n=8` passes on both devices on the exit build | `p0exit_{debug,release}.*` |

**`suite=transform`** (*measured*, Release, `MLX_ENABLE_TF32=0`, load 1.55 to 1.60; one warm-up, three
evaluations; the forward real transform of the n-cube zero-padded to m, its inverse, the crop):

| n (m) | Device | Spectrum (Fortran's view) | Round trip / max | Best of 3 | Spread | Bits of 3 | MLX peak | Cache after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 160 (320) | CPU | 161 x 320 x 320 | 4.77e-7 | 0.2821 s | 0.0016 s | equal | 4.10e8 B | 1.47e8 B |
| 256 (512) | CPU | 257 x 512 x 512 | 5.96e-7 | 1.2297 s | 0.0009 s | equal | 1.68e9 B | 6.04e8 B |
| 160 (320) | GPU | 161 x 320 x 320 | 2.50e-6 | 0.0057 s | 0.0054 s | equal | 1.47e9 B | 1.20e9 B |
| 256 (512) | GPU | 257 x 512 x 512 | 1.91e-6 | 0.0127 s | 0.0040 s | equal | 5.99e9 B | 4.92e9 B |

The process's footprint over the four rows: 7.61e9 B peak, 3.12e9 B maximum resident (`/usr/bin/time -l`). The
GPU's peak for one transform pair at 512 already passes decision 20's hypothesis for the whole solve (at most
4.3e9 B): MLX's working memory inside a GPU transform is about 3.5 times the arrays the graph names (question 25 of
`doc/collaboration/apple_questions.md`). The GPU's round trip at 320 is 21 float32 epsilons of the largest value
(4 on the CPU).

**Decision 10** (*measured*, N = 8, M = 16, mask radius 2.5, 251 unknowns; system R: relative ridge 0.05; the
oracle given B and D rounded once to float32):

| Planes | Seed | F1 zeros in `nint(|q|) <= N` | cond(H_s) | cond(Lᵀ H L) | F2 | F3 | Rule E: K, reason, `step/xtol` at K; least before K | Least tie |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4N = 32 | 1 | 27 of 1,359, 1.99 % | 122.0 | 1.30e6 | fails | holds | 16, xtol, 0.921; **1.041** | 1.9e-2 |
| 4N | 2 | 18, 1.32 % | 122.0 | 1.34e6 | fails | holds | 14, xtol, 0.844; 1.291 | 3.2e-2 |
| 4N | 3 | 20, 1.47 % | 121.6 | 1.32e6 | fails | holds | 16, xtol, 0.854; 1.198 | 2.9e-3 |
| 8N = 64 | 1, 2, 3 | 0.15, 0.29, 0.22 % | 122.1, 122.0, 122.3 | 1.20e6, 1.27e6, 1.24e6 | fails | holds | 15, 11, 15, xtol; 0.841, **0.980**, 0.897; 1.151, 1.399, 1.081 | 4.5e-2 or more |
| 16N = 128 | 1, 2, 3 | 0.07, 0, 0 % | 122.3, 121.9, 122.3 | 1.30e6, 1.33e6, 1.29e6 | fails | holds | 15, 14, 14, xtol; 0.817, **0.961**, 0.841; **1.002**, **1.050**, 1.138 | 5.0e-2 or more |

Bold: a margin under 5 % (decision 10). Under rule R4 the oracle reaches `rtol` at 127, 105 and 110 iterations
(4N), with the reported residual equal to the true one. **System P** (ridge 1e-3, recorded): cond(H_s) 5.6e5 to
7.6e5, and on seed 1 at 4N **the support block is indefinite** (least eigenvalue -3.45e-5): the kernel spectrum's
small negative bins are not lifted by an absolute ridge of 1e-3; at 8N and 16N its least eigenvalue is 1.0e-3 to
1.1e-3. F2 and F5 run their two and five iterations; residuals 2.27e-2, 2.05e-2, 2.11e-2 after 2 and 6.9e-3 to
7.6e-3 after 5 (4N).

**N = 32** (4N = 128 planes, mask radius 8, matrix-free, `p0_decision10_n32_p4.log`): F1 0.71 to 0.77 %; least
tie 1.3e-4; rule E stops on `xtol` at 33, 40 and 40 iterations (residual 1.30e-3, 1.10e-3, 1.12e-3); **rule R4
does not reach `rtol` in 200 iterations** (2.45e-4 to 2.47e-4, reason `maxits`); F2 and F5 as at N = 8
(2.66e-2 to 2.68e-2, 7.55e-3 to 7.76e-3).

**Why F2 fails** (`p0_f2diag.log`, a scratch driver, double precision, the support block of system R):

| | Seed 1, 4N | Seed 2, 4N | Seed 3, 4N | Seed 1, 16N |
| --- | --- | --- | --- | --- |
| CG without a preconditioner: iterations to 1e-4, 1e-8 | 22, 51 | 21, 51 | 21, 50 | 19, 51 |
| CG with 9.4's preconditioner: iterations to 1e-4, 1e-8 | 127, 596 | 104, 589 | 110, 599 | 91, 533 |
| Preconditioned eigenvalues: least, median, largest | 8.2e-5, 39.1, 106 | 7.6e-5, 39.2, 101 | 8.2e-5, 39.3, 109 | 6.8e-5, 34.8, 88 |
| Eigenvalues below 1e-2 of the median; their vectors' energy at `nint(|q|) > N` | 32; 98.6 % | 32; 98.7 % | 33; 98.5 % | 31; 98.9 % |
| The condition number without them | 253 | 239 | 271 | 220 |

The preconditioner sets `pi = 0` beyond `nint(|q|) = N` (SIMPLE's `finalize_density_accum`: "A singular (PSD)
preconditioner keeps the Krylov space out of them"), but a vector of the spherical support cannot be band-limited:
the mask, the crop and the envelope leave its support block nonsingular (least eigenvalue 5e-5 of 10, far above
decision 10's 1e-10 cut), so about 13 % of the directions get eigenvalues near 1e-4. Even without them the
preconditioned number (220 to 271) is twice the plain one (122). More planes change nothing (16N: 91 iterations
against 19). **On this fixture SIMPLE's preconditioner makes conjugate gradients five to six times slower to 1e-4
and about twelve times slower to 1e-8.** Two independent measures agree (the eigenvalues; the iteration counts).

**The oracle's cost** (*measured*, `-O2`, wall clock, one each): `oracle_dft_3d` 33.4 s at M = 320 and 364.7 s at M =
512; at N = 160 the fixture (640 planes) 4.9 s, the oracle's `new` 66.3 s (two transforms), one `apply` 66.4 s. Predicted
`suite=accuracy` (decision 11's 11 transforms): about 6 min at N = 160 (11 x 33.4 s) and 67 min at N = 256 (11 x 365 s), plus the host loops (*derived* from the single timings; under section 7's 4 hours).

**Frozen (would be, at P = 4N):** the fixture as written (4N planes, the generator bit equal to the lattice);
admitted seeds for rule E's margins: 2 and 3 (seed 1, the calibration seed, "stop iteration reported, not
gated": 1.041 before K); the oracle's counts above. **Not frozen:** P itself, which decision 10 moves to 8N and 16N
on F2's failure and which no P satisfies.

**Decisions taken under delegation.**
1. The four exports are generic interfaces of the module's own procedures under `oracle_recon_` names: no call
   site, no statement of arithmetic changed (renaming would have rewritten five call sites).
2. The fixture's variates: three for a global rotation (z-y-z angles, the second through `acos` so the rotation
   is uniform), then three per plane (the in-plane angle, the two shifts), all from `seeded_uniform` in [-1, 1];
   the sample's convention is the oracle plane's (`t exp(+i phi) F / n³`), the noise variance 1, the phantom's
   centres and widths in units of n/6; the generator keeps only the packed half (half the memory); the fixture's
   plane is a private record so that no procedure passes five dummies.
3. F2's `L` from LAPACK's `dsyev` (Accelerate) on the support block of 9.4's matrix, in a scratch driver only;
   the condition numbers from the oracle's Jacobi eigenvalues; the margins' step quantity from fixed-iteration
   solves `set_rules(0, 0, k)` (decision 11's rule).
4. Steps 3, 4 and 6 were completed after the stop was found: they do not depend on the fixture's acceptance and
   inform the ruling. No code of Phase 1 was written.
5. `suite=transform` asserts the spectrum's shape and the round trip within 64 float32 epsilons
   (`ELEM_CEILING`), a convention test; times are recorded. `mlxf_test_defs.f90` gets only the constant code
   reads (`RECON_PCG_BENCH_N`); the fixtures' other constants wait for the code that reads them.
6. The run's own copies of the polar benchmark's argument helpers are in the new benchmark: that file is outside
   this plan (section 4), so they could not be shared.

**Ruling needed** (one of):
1. **Recommended:** F2 becomes reported, not gated (it measures SIMPLE's preconditioner, not the fixture's
   coverage, and no fixture passes it); P stays 4N (F1 holds on every seed, rule E's margins admit seeds 2 and 3);
   the run resumes at Phase 1 from this state. The finding goes to the report as a question for SIMPLE.
2. F2 is redefined before the resume (for example: the preconditioned condition number without the eigenvalues
   below 1e-2 of the median, whose vectors lie beyond `nint(|q|) = N`, against twice the plain one), frozen now.
   On the numbers above that form would pass (220 to 271 against 2 x 122 = 244) on seeds 1 and 2 at 4N and fail
   on seed 3 (271): it is not recommended without a margin of its own.
3. K8 waits until the preconditioner of 9.4 is reviewed in SIMPLE (the toy would reproduce a preconditioner
   that slows the solve).

**What it means, in short:** the transforms K8 needs work at 320³ and 512³ on both devices (12.7 ms per padded
pair at 512 on the GPU, 1.23 s on the CPU), but one pair peaks at 6.0e9 B of MLX memory on the GPU. The oracle and
the new fixture agree to the bit. The fixture is not accepted, because SIMPLE's preconditioner, reproduced by the
oracle, conditions the full-coverage system worse than no preconditioner; the plan's own rule makes that a stop.

**Not done, plainly:** no solver, operator or tester code; no tolerance calibrated; no plant (Phase 0 has none);
Phase 6's documents. The report file `completed/mlxf_kernel_k8_report.md` was not written: this session's harness
refuses report files from the run's agent, so the report went to the maintainer's session as text; this entry is
the record.

### Ruling R1 (2026-11-25)

The maintainer, on the stop: "My only comment on K8: we never run more than 5 iterations of PCG in SIMPLE,
ever." The rest stands as recommended, open to the review (the run's `spec/rulings.md`):
1. **F2 is reported, not gated:** a condition number governs convergence over many iterations, and SIMPLE runs
   2 (`maxits_pcg`) and at most 5 (`FINAL_PCG_MAXITS_FLOOR`). The fixture is accepted at P = 4N; seeds 2 and 3
   judged, seed 1 calibrates.
2. **System P under F2 and F5 judges the solver,** iterate by iterate k = 1 .. 5 against the oracle (gate
   (a')). Added, reported: at N = 8 and 32 the iterates' error after 2 and 5 iterations against the exact
   solution, with and without the preconditioner, on both systems.
3. **System R and rules E, R4 and T stay** as tests of the engine (stopping logic, the true residual float32
   reaches, decisions 14 to 17), gated as written; no timing verdict rests on them.
4. **Timing verdicts** (decision 18, the bench's comparisons) are read at 2 and 5 iterations of system P;
   25, 50 and 200 iterations are reported. W1 and W0 are judged within 10 % of W2's true residual after 2 and
   5 iterations, 25 and 50 reported.
5. **Order:** K8 resumes at Phase 1 after run `mlxf_kernel_k2` (one timed run at a time on the M5).
