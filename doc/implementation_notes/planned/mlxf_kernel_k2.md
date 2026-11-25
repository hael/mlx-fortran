# K2: the polar projection (B1) as a toy `projector`, and the protected-update probe (run `mlxf_kernel_k2`, on the M5 Ultra)

Status, 2026-11-25: planned and ruled (the maintainer's go); run in the session on the M5 Ultra, in order K1, K8, K2. Base: the commit that holds this plan (the maintainer commits it with the pending
work; the run pins the hash in Phase 0 and records it). The code this note was checked against is `1e0ae97` with
the working tree of 2026-11-25 (parity Phases 4 and 10, the polar and pose oracles). SIMPLE is read at
`d354efee2`. Machine: the M5 Ultra only (arun host `local`; 30 cores, 103.1 GB, the only GPU). Supersedes:
none. Depends on:

- the custom Metal kernel wrapper `type(mlx_metal_kernel)` (validated: yes, parity Phase 10, `unit_fast` 94;
  **not** validated: a complex64 output, a float32 atomic output, an output above rank 2);
- `mlx_rfftn`, `mlx_take` without a dimension, `mlx_fft`, `mlx_rfft` (validated: yes, `unit_fft` 194 and
  `unit_ops` 2,402; **not** validated at 320³ nor for 7.5e7 gathered positions);
- the polar toy `polarft_calc` with its driver (validated: yes, run `mlxf_toy_arch`, `unit_kernels` 1,063);
- the oracles `mlxf_oracle_dft`, `mlxf_oracle_projection` (32 self-checks) and `mlxf_oracle_gridding` (13)
  (validated: standalone under GNU Fortran 16.2 at `-O0` and `-O2`; **not** asserted in the fast gate yet);
- `scripts/run_parts.sh` (validated: for `bench_polar_table suite=time` only);
- the roadmap's decisions 8, 9, 11, 14 and 15 (ruled or standing as recommended, 2026-11-24).

It is not a dependency of K1, nor K1 of it, but both edit the polar toy: K2 launches from the commit that holds
K1's result, never beside it (section 2, "The queue").

## 1. Why

Family B is the gather from the padded 3D Fourier volume, and B1 is its first member: the reprojection model
that fills family A's references. SIMPLE's CPU does this work at about 12 ns per sample at the margin
(*derived* in the design note from a recorded run): 2,500 directions of pftsz 182 and 61 shells are 27,755,000
samples per parity, 0.33 thread-seconds. The projection alone is therefore not where the GPU earns its place.
What K2 buys is measured elsewhere: a part process holds 20.8e9 B for 10,000 references per parity, of which
7.14e9 B are device tiles uploaded from 3.57e9 B of host memos (*measured* and *derived*, run `mlxf_toy_arch`),
and three parts already hold 60.3e9 B of 103.1e9 B. If the references are projected on the device, transformed
there and packed there, they never exist on the host. K2 builds the gather with no write conflicts (the pattern
K5's pose objective and K6's insertion reuse), proves it against the host matrix oracle, and measures the chain
volume → B1 → ring transforms → A's reference tiles. Roadmap decision 14 places one probe right after it: a
protected update on a collision-heavy fixture, before K6 is planned on the premise of an easy win.

## 2. Contract

- **Where the code lives:** `src/test/` only, as `mlxf_toy_<stem>` modules under SIMPLE's names, written against
  the public module `mlxf`. No file under `src/core/` or `src/defs/` changes. A missing wrapper is a stop with a
  report, never a private binding.
- **What it mirrors,** read with `git -C ~/src/SIMPLE show d354efee2:<path>` (never the working tree; nothing
  is copied in):
  - `src/main/image/simple_projector.f90`, type `projector` (`expand_cmat`, `kill_expanded`, `is_expanded`),
    with the four procedures it inherits from `image` that the reprojection calls (`new`, `kill`, `set_rmat`,
    `pad_fft` of `src/main/image/simple_image_fft.f90`);
  - `src/main/image/simple_projector_pft_batch.f90`, `fproject_polar_batch_opt`;
  - `src/main/pftc/simple_polarft_core.f90`, `vol_pad2ref_pfts_opt` (a public module procedure of
    `simple_polarft_calc`), with `get_kfromto` and `get_polar_coords` of the calculator;
  - reading references only: `apod_fast_device` (`src/main/interp/simple_kbinterpol.f90`), `cyci_1d`
    (`src/utils/math/simple_math_ft.f90`), `loop_lims` (`src/main/image/simple_ftiter.f90`),
    `read_mask_filter_reproject_refvols` (`src/main/strategies/search/simple_matcher_refvol_utils.f90`); for the
    probe `insert_plane_oversamp` (`src/main/volume/simple_reconstructor.f90`) and `insert_slices_batch`
    (`src/main/volume/simple_reconstructor_openmpoffload.f90`).
- **Two forms, in order:** a graph form from library operations, kept always (it is the reference and the CPU
  path); then one fused Metal kernel, kept only by decision 19's rule.
- **Judged against** `mlxf_oracle_projection` in double precision, which shares no index, weight or layout code
  with the toy. The toy imports no oracle module; only testers and the benchmark do.
- **The off-state invariant.** A program that makes no `projector` runs no line of this plan's device code: the
  polar toy's suites keep their counts and the dense driver's digests of Phase 0 come back bit for bit after
  every phase (decision 23). Without `set_ref_route` (decision 11) the calculator memoizes on the host as today.
- **Float32 and complex64 only** on the device, full precision (`MLX_ENABLE_TF32=0`); no accelerated mode.

### What the check found (2026-11-25)

Each line is a premise of the brief or of the design note, checked against the code. Lines marked **differs**
changed a decision below.

- **The driver does not go through `set_ref_pft` (differs).** `vol_pad2ref_pfts_opt( self, vol_pad, eulspace,
  state, iseven )` passes the section `self%pfts_refs(:, kfromto(1):kfromto(2), iref_from:iref_to, ieo)` to
  `fproject_polar_batch_opt` as `refs_state`, with `iref_from = (state - 1) * nspace + 1`. `set_ref_pft` is not
  called; `memoize_refs` is called later by the matcher. It is a module procedure, not a type-bound one.
- **The batch projector reads the expanded volume without any wrap.** The wrap is in `expand_cmat`: per
  dimension, an index outside `loop_lims(3)` goes through `cyci_1d`. The limits are `-M/2 .. M/2` on dimension 1
  (period M + 1) and `-M/2 .. M/2 - 1` on dimensions 2 and 3 (period M): the oracle's `oracle_proj_edge_index`.
  The expanded array is the full cube `-(M/2 + 2) .. M/2 + 2` on each dimension, (M + 5)³ complex values, the
  conjugate half made by `get_fcomp` (the conjugate of the stored mate when `h < 0`).
- **The window** (`KBWINSZ` = 1.5, `KBALPHA` = `OSMPL_PAD_FAC` = 2, `simple_defs.f90`): Kaiser-Bessel, half-width
  1.5, three taps per axis at `nint(loc) - 1 .. nint(loc) + 1` (`iwinsz` = 1, `wdim` = 3; more than 3 is a hard
  error). A weight is `(1/3) P(u)`, `u = max(0, 1 - (2x/3)²)`, `P` the first 15 terms of I0's power series in
  `beta² u / 4` by Horner's rule in single precision, `beta = pi sqrt(4.2625)`. The three weights of an axis
  are divided by their sum. The sample is the weighted sum of 27 values times `PAD_FAC³` = 8.
- **Per direction** the host takes rows 1 and 2 of the rotation matrix; **per polar point** it takes
  `hkcoords = 2 (k sin a, -k cos a)`, `a = 2 pi (irot - 1) / (2 pftsz)`, once for all directions; **per sample**
  the kernel rotates (`loc_j = px R(1,j) + py R(2,j)`), rounds, weighs and gathers. About 480 flop and 27 reads.
- **`new` refuses `kfromto(2) > fdim(box_crop) - 1 = box_crop/2`.** With `|loc| <= 2 kto <= M/2` the taps reach
  `M/2 + 1`: inside the halo, and beyond the periodic range only on the shell `k = N/2`. Section 9.7 of the
  oracles plan listed this as not read.
- **The bench's box.** Case `2500_4` is SIMPLE's `polar_matching_bench`: native box 180 at 2.055 Å, cropped box
  160, mask diameter 270 Å, limit 6 Å (`PMB_*`). The projection acts on the cropped box: N = 160, padded
  M = `box_croppd` = 2 `round2even`(2 · 80) = 320, expanded side 325. `magic_pftsz` of the cropped mask radius
  58 gives 182; shells 2 to 62 are 61. No tap comes nearer than 35 voxels to the edge (2 · 62 + 1 = 125 of 160).
- **Sizes at the bench** (*derived*): 11,102 points per direction; 27,755,000 samples per parity; a bank of
  sections 222,040,000 B per parity; the expanded cube 274,625,000 B (the design note's 132 MB is the Hermitian
  half, 131,891,200 B: **differs**); the padded real cube 131,072,000 B; 13.3 GFLOP per parity.
- **Rule `mirror` covers public types and bindings only (differs).** A ledger line that names a public module
  procedure fails as "not a public type or binding". Both mirrored procedures here are module procedures.
- **`scripts/run_parts.sh` starts `bench_polar_table suite=time` and refuses `test=` and `suite=` (differs).**
- **No oracle self-check is asserted in the gate.** The oracles' reports leave the testers to K2, K6 and K8.
- **What the two insertions show** (for decision 20). `insert_plane_oversamp` sweeps the h-lines of one plane
  in 6 colours (`stride = ceiling(sqrt(3) * 3)`), so that concurrent lines never share a window: its result is
  the same at any thread count. `insert_slices_batch` runs one GPU thread per plane and symmetry copy
  (`collapse(2)`), each doing its whole plane serially, and adds to the shared grids with plain
  read-modify-write: two planes that meet in a voxel can lose an update. Batches are 500 planes
  (`MAXIMGBATCHSZ`).
- **`oracle_proj_route` takes any even cube and any coordinates,** with the padding factor 2 fixed; its explicit
  matrix has M³ columns, so it serves boxes up to 8. `oracle_proj_gather` and `oracle_proj_edge_gather` need no
  matrix. The edge queries are private to the oracle: a tester restates the four coordinates.
- **Half-integer coordinates.** The window is 1 at its edge against 105 at its centre, so the interpolant jumps
  by 3e-3 to 1.3e-2 where a coordinate crosses a half-integer (the examples note's decision 11, *measured* in
  its review). A float32 coordinate near 124 is known to 7.6e-6: at the bench about 1 sample in 20,000 lies
  that close to a jump (*derived*), where the toy and a double-precision oracle may round apart.
- **The toy's host memoization is a direct transform:** 4.06e10 complex multiply-adds for 2,500 references in
  both parities (*derived*: 2 × 183 × 364 × 61 × 2,500 × 2). SIMPLE uses FFTW there.
- **Measured for the kernel wrapper** (parity, entry "Phase 10"): another grid or output shape is another
  kernel object (0.2 ms, against 60 ms for a new source); a threadgroup above 1,024 fails at the evaluation;
  outputs tested are float32 and int32, of rank at most 2; atomic outputs are tested for int32 only; inputs
  may be complex64; mlx-c cannot set the math mode.

### The queue

- **K1 (the fused tail, run `mlxf_kernel_k1`) edits files this plan edits:** `mlxf_toy_polarft_calc.f90`,
  `_core.f90`, `_memo.f90`, `mlxf_toy_polarft_workspace.f90`, `_lifecycle.f90`, `scripts/run_parts.sh`,
  `mlxf_test_defs.f90`, `mlxf_test_registry.f90` and `scripts/toy_mirror.txt` (its draft's file table). One run
  at a time on the M5: K2 launches from the commit that holds K1's result. If K1's tail is kept, the tiles
  this plan makes on the device are built as K1's lifecycle builds them, with the tail's kernels; Phase 3
  reads K1's report first. If K2 is launched before K1, the same holds the other way round.
- K5 and K6 reuse this plan's `projector` and its bench. They are written after K2's report.

## 3. Decisions and rulings

**Ruled (2026-11-25, Hans: "Go", on the request that set out these decisions with their recommendations): every decision of this section as recommended.** The order of the runs is K1, then K8, then K2, one at a time on the M5 Ultra, each from the state that holds the previous one's verified result.

All dated 2026-11-25 and recommended; none is ruled yet. The block's last paragraph lists the ones that are
real choices.

1. **Scope.** The toy `projector` with `fproject_polar_batch_opt`, driven by a miniature `vol_pad2ref_pfts_opt`;
   a graph form and a fused form of the gather; the hand-over of the projected references to family A; a bench at
   2,500 directions; then the probe of decision 20. Nothing of B2, C or D.
2. **Modules,** all in `src/test/`:

   | Module (file of the same name) | Holds |
   | --- | --- |
   | `mlxf_toy_projector` | type `projector`: the real volume, its box and padding, and one component `ws` |
   | `mlxf_toy_projector_workspace` | type `projector_workspace`: the device volume, the expanded cube, the kernel objects, a bank in flight |
   | `mlxf_toy_projector_pft_batch` | `fproject_polar_batch_opt` and its device-resident form |
   | `mlxf_toy_polarft_calc`, `_core`, `_memo` (existing) | `vol_pad2ref_pfts_opt`, `get_kfromto`, `get_polar_coords`; the device route of decision 11 |
   | `mlxf_toy_polarft_workspace`, `_lifecycle` (existing) | the tiles made from device sections |
   | `mlxf_toy_projector_tester` | suites `projector` and `projector_chain` |
   | `mlxf_oracle_projection_tester` | suite `oracle_projection`: the 12 and 32 self-checks asserted |
   | `mlxf_bench_projector` | `test=bench_projector`, suites `time`, `accuracy`, `chain` |
   | `mlxf_bench_insert_probe` | `test=bench_insert_probe` (decision 20) |

3. **Names and dummies are SIMPLE's.**

   | SIMPLE at `d354efee2` | The toy keeps | Dropped or changed (a declared difference) |
   | --- | --- | --- |
   | `image%new( self, ldim, smpd, wthreads )` | `projector%new( self, ldim, smpd )` | `wthreads`; the toy's `projector` does not extend an `image` class |
   | `image%set_rmat( self, rmat, ft )` | the same | |
   | `image%pad_fft( self, self_out )` | the same | the transform is the device's (`mlx_rfftn`), divided by M³ |
   | `projector%expand_cmat( self )`, `kill_expanded( self )`, `is_expanded( self )`, `image%kill( self )` | the same | `cmat_exp` is a device array inside `ws`, not a public member |
   | `fproject_polar_batch_opt( vol_pad, eulspace, nspace, pftc, refs_state, mirr_proj )` | `( vol_pad, eulspace, nspace, pftc, refs_state )`, `refs_state(pftsz, nk, nspace)` in `complex(real32)` | `mirr_proj` (SIMPLE's default is `no`); `eulspace` is `real(real32) :: eulspace(3, 3, nspace)`, the matrices `get_mat` returns |
   | `vol_pad2ref_pfts_opt( self, vol_pad, eulspace, state, iseven )` | the same five | it fills the calculator through its staging or its workspace (decision 11), not a member section |
   | `polarft_calc%get_kfromto( self )`, `get_polar_coords( self, dim, coords )` | the same | |

   The record `parameters` gains `nspace`, `nstates` and `box_crop` under SIMPLE's names. A refusal is read from
   `message()`, as in family A; a refused projection leaves `refs_state` at zero.
4. **Layouts in Fortran's view.**

   | Array | Shape and index meaning | Kind |
   | --- | --- | --- |
   | The volume handed in | `rmat(N, N, N)`, voxel `i` at centred `x = i - 1 - N/2`: the origin is voxel `N/2 + 1`, as in `pad_fft` and SIMPLE's masks | `real(real32)` |
   | The padded transform | `(M/2 + 1, M, M)`, `h = 0 .. M/2` at `1 + h`; `k`, `m` at `1 + modulo(k, M)`; scaled by `1/M³` | complex64, device |
   | The expanded cube | `(E, E, E)`, `E = M + 5`, `L = M/2 + 2`; `(h, k, m)` at `(h + L + 1, k + L + 1, m + L + 1)`, position `1 + (h + L) + E (k + L) + E² (m + L)` | complex64, device |
   | The directions | `eulspace(3, 3, nspace)`; a sample's coordinate is the row vector `2 (px, py, 0)` times `eulspace(:, :, i)` | `real(real32)` |
   | The polar points | `hkcoords(2, pftsz, nk)`: `2 k sin a` and `-2 k cos a`, `irot` fastest; point `p = irot + pftsz (kk - 1)` | float32 |
   | The result | `refs_state(pftsz, nk, nspace)`, shell `kk = k - kfromto(1) + 1`: SIMPLE's `refs_state` | complex64 |

   The device holds the result of a tile as `(pftsz * nk, T)` and reshapes it, which moves nothing.
5. **Precision.** Device arrays are float32 and complex64. Double precision is used on the host for three
   things only: the fixtures' inputs before they are rounded once, the 15 window coefficients
   `(beta²/4)^j / (j!)²` (computed, rounded once, never pasted from SIMPLE), and the oracle. The oracle is given
   the toy's single-precision inputs widened: the rotation matrices and the table `get_polar_coords` returns.
6. **The interpolation is SIMPLE's,** as "What the check found" states it: the window, the three taps, the
   polynomial, the normalisation per axis, the factor 8, and the stencil base `sign(t) floor(|t| + 0.5)` (the
   examples note's decision 11: Fortran's `nint`, never a half-to-even `round`). The edge map of dimension 1 has
   period M + 1 and lives in `expand_cmat`, as in SIMPLE.
7. **The graph form,** on either device, for a tile of T directions:
   - `loc` `(3, npts, T)` from `hkcoords` and the tile's rotation rows by broadcasting; the bases by decision 6;
   - the per-axis weights `(3, 3, npts, T)` by Horner's rule in graph operations, each axis divided by its sum;
   - the positions `(27, npts, T)` in int32 by decision 4's formula, and the weights `(27, npts, T)` as the
     product of the three axes;
   - one `mlx_take(cube, positions)` without a dimension, a multiplication, `sum` over dimension 1, times 8.

   Its cost is the gathered operand, directions × points × 27 (*derived*): 5,995,080,000 B for a whole parity,
   so it is tiled. A tile of 250 directions holds 599,508,000 B of gathered values and 299,754,000 B each of
   positions and weights, 1.20e9 B in flight; a tile of 64 holds 0.31e9 B. Tiles are evaluated one at a time.
8. **The fused kernel.**
   - **Inputs:** the expanded cube (complex64, read by position), `hkcoords` flattened to `(2, npts)`, the tile's
     rotation rows `(2, 3, T)`. `E` and `L` are template integers.
   - **Launch:** `grid = [npts, T, 1]`, one thread per sample: `thread_position_in_grid.x` is the point less
     one, `.y` the direction less one. `threadgroup = [g, 1, 1]`, `g` from the sweep {32, 64, 256, 1024}, never
     above 1,024.
   - **Per thread:** decision 6's steps in SIMPLE's order of operations, the 27 values read at
     `ix + E (iy + E iz)`, real and imaginary parts accumulated apart, the result written at `x + npts * y`.
     No bounds test in the kernel: the host refuses a direction unless
     `nint(2 kto sqrt(R(1,j)² + R(2,j)²)) + 1 <= L` on each axis j, which a rotation always meets under
     SIMPLE's limit on `kto`. The toy does not test that a matrix is a rotation, and neither does SIMPLE; the
     edge fixture uses that.
   - **Output:** complex64 `(npts, T)`, rank 2. A complex64 output is untested: Phase 2 tests it first. If it is
     refused, the output is float32 `(2 npts, T)` read as complex by `mlx_bitcast`, or by `cmplx` of two slices.
   - **One kernel object per launch configuration:** at most two per run configuration (the full tile and the
     last partial one), built once in the workspace and reused over the tiles and the parities; one source, so
     one Metal compilation per process. A tile of one direction hands in 6 rotation numbers, which MLX passes
     in Metal's `constant` address space (fewer than 8 elements): the phantom's tail of 1 exercises it.
   - The kernel is not placed inside a compiled function, and no output is above rank 2.
9. **Tiling over directions.** The graph form's tile is bounded by memory (decision 7); the fused form's is not
   (its only device array beyond the inputs is the output, 222,040,000 B for all 2,500 directions).
   Sweeps, once each, best of 3: graph T in {64, 250}; fused T in {250, 2500} by `g` in {32, 64, 256, 1024}.
   T = 250 is family A's reference tile (`POLAR_CANON_RT`). The fastest configuration of each form is frozen in
   Progress before the verdict runs and is that form's canonical one.
10. **The seam.**

    | Question | Answer |
    | --- | --- |
    | Who owns the device state | `projector%ws`, made in `new`, released in `kill`; the projected bank passes to `polarft_calc%ws(ieo)` inside `vol_pad2ref_pfts_opt`. No tester, benchmark or driver holds a handle |
    | What is resident, and from when | From `expand_cmat` to `kill_expanded`: the expanded cube, 274,625,000 B at the bench (39,304 B at M = 12), one parity's at a time, as SIMPLE kills each padded volume after its projection. The padded transform (131,891,200 B) and the padded real cube are released at the end of `expand_cmat` |
    | What the projection adds | A bank of 222,040,000 B per parity; in flight, a graph tile (1.20e9 B at T = 250) or nothing |
    | What stays on the host | The two real volumes, 16,384,000 B each. The padded real cube is staged once on the host (131,072,000 B) and uploaded |
    | Where the host waits | `expand_cmat` (the cube is evaluated, so that the projection is timed apart); `fproject_polar_batch_opt` (it evaluates and copies `refs_state` out); on the device route nowhere before `memoize_ref_bins` |
    | What a part process holds | Every part projects every direction: decision 18's estimates |
11. **The hand-over to family A: both routes, the host one as the reference.**
    - **The host route** uses today's entries only. `vol_pad2ref_pfts_opt` calls `fproject_polar_batch_opt`, which
      copies `refs_state` out, and hands each section to `set_ref_pft` widened to `complex(real64)`; `memoize_refs`
      and `memoize_ref_bins` are unchanged. Per state it moves 444,080,000 B down and 1,786,080,000 B up, holds
      893,040,000 B of host memos, and computes 4.06e10 complex multiply-adds on the host (*derived*).
    - **The device route** is an addition, `set_ref_route`, recorded as a difference. `vol_pad2ref_pfts_opt` leaves
      the bank on the device; `memoize_refs` makes the ring transforms there (the full ring `[z; conj z]` by
      `mlx_fft`, bins 1 to pftsz + 1; the squared modulus by `mlx_rfft`, conjugated); `memoize_ref_bins` packs the
      tiles there, tile by tile of `rt` references. Nothing crosses to the host. After `memoize_ref_bins` the
      device holds the tiles alone (1,786,080,000 B for both parities, as on the host route); the sections and
      the device memos are released. A shift map on this route is refused (K4's).
    - The chained test runs both. The device route is a second path for the same computation: it is kept only
      if the chain's elapsed time, from the evaluated banks to the reference bins ready, is at least 1.30 times
      shorter than the host route's at the bench, in both invocations (the standing rule). Otherwise it is
      deleted and the report says so.
12. **Fixtures.**

    | Fixture | Box, padding | Polar set | Directions | Oracle |
    | --- | --- | --- | --- | --- |
    | Phantom (fast gate) | the oracle's 6-cube, M = 12 | pftsz 6, shells 1 to 2 | the oracle's three rotations, tile T = 2 (a tail of 1) | `oracle_proj_route` (the explicit matrix) |
    | Seeded (fast gate) | a seeded 8-cube, M = 16 | pftsz 8, shells 1 to 3 | 6 seeded rotations, T = 4 | `oracle_proj_route` |
    | Edge (fast gate) | the phantom | shell 1, the angle of 90° | four matrices whose first row is half an edge query, and four for the boundary queries | `oracle_proj_edge_gather` on the packed phantom |
    | Chain (fast gate) | two seeded 16-cubes (even, odd), M = 32 | pftsz 16, shells 2 to 7 | 6 seeded rotations per parity, 4 particles per parity | `oracle_proj_gather` on `oracle_proj_padded_field`, then `mlxf_oracle_polar` |
    | Bench (named only) | N = 160, M = 320, seeded blobs inside radius 58 | pftsz 182, shells 2 to 62 | 2,500 on a spiral, in-plane angle 0 | `oracle_proj_edge_gather` on the device's own padded transform, for 16 directions |

    Seed 1 calibrates; seeds 2 and 3 are judged (`ELEM_SEED_CALIBRATION`, `ELEM_SEEDS_JUDGED`).
13. **Tolerances are measured, then frozen.** Each is taken on seed 1 on both devices, written into
    `src/test/mlxf_test_defs.f90` and into Progress with its evidence, and only then are seeds 2 and 3 run. The
    gate is twice the frozen number (the factor of family A's rows, `POLAR_ROW_FACTOR`).

    | Constant | What it bounds | Measure | Ceiling, above which the run stops |
    | --- | --- | --- | --- |
    | `PROJ_FIXTURE_ERR` | a sample against the oracle, phantom and seeded fixtures, both forms | `|toy - oracle|` over the sum of `|w f|` of its 27 terms; the largest over the samples decision 14 judges | 1e-5 (*guessed*: the examples note's cap for interpolation) |
    | `PROJ_BENCH_ERR` | the same at the bench's geometry (`suite=accuracy`) | the same | 1e-4 (*guessed*: coordinates 20 times larger) |
    | `PROJ_CHAIN_ERR_HOST`, `PROJ_CHAIN_ERR_DEVICE` | the dense rows of the chain, per route | family A's: a pair's largest distance error over the largest `|d|` of its oracle row | 1e-4 (*guessed*) |

    The Hermitian control's bound is twice the fixture gate (*derived*: two independent errors). Exact checks:
    which outputs are non-zero for a one-voxel spectrum, the counts, the shapes, the near-tie count.
14. **Near ties.** A sample is near a tie when a coordinate, computed in double precision from the toy's inputs,
    lies within `PROJ_TIE_MARGIN` = 1e-4 of a half-integer (*guessed* in the examples note; 13 times the float32
    spacing at 124). Such a sample is not judged by decision 13's tolerances; the tester counts them on the
    host and asserts the count. The fast fixtures have none: a seeded rotation that makes one is redrawn. The
    boundary and edge queries are exact half-integers and quarter-integers and are judged in full. At the
    bench the count is reported with the judged remainder.
15. **Controls,** each a gate with a planted violation shown to fail and then removed:

    | Control | What it pins | Planted violation |
    | --- | --- | --- |
    | Identity rotation, constant spectrum | every sample is 8 times the constant: normalisation per axis | weights not normalised; the factor 8 omitted |
    | Identity rotation, phantom | the polar angle's origin and sense | sine and cosine exchanged |
    | A single plane wave (a real wave on the M-grid, padded by 1: one Fourier voxel and its mate) | index order and the weights: non-zero outputs equal the oracle's matrix pattern, values its weights | positions in C order; the rotation transposed |
    | Hermitian symmetry (a direction and its turn by 180° in the plane) | the conjugate half of the expanded cube | no conjugate for `h < 0` |
    | The boundary queries (±0.5, ±1.5, ±2.5, ±5.5, 6) | the stencil base | half-to-even rounding |
    | The edge map (the oracle's four edge queries; the shell k = N/2 at 90°) | period M + 1 on dimension 1, M on the others | period M on dimension 1 |
    | The tolerance has teeth | | one window coefficient changed by 1e-4 of itself |
    | The chain | parity and reference order | the two parities exchanged |
16. **Repeatability is its own gate.** On one GPU configuration and tile shape, three projections of the same
    inputs, each from a fresh graph, give the same bits (`bits_equal`), for each form, on the fast fixtures and
    at the bench (the digests of the three timed passes and of the two invocations). A planted sample that
    depends on the pass shows the gate fails. Whether two tile shapes give the same bits is reported.
17. **The bench** is `mlxf_test_exec test=bench_projector suite=<s> [key=value ...]`, Release.
    - `suite=time`: one state, both parities, from the two real volumes on the host to the two banks evaluated
      on the device. Keys: `form=graph|fused`, `tile=`, `tg=`, `nspace=` (2,500), `nthr=`, `nparts=`, `part=`,
      `go=`, `seed=`. It prints the stages (pad and transform, expansion, projection), `mlx_peak_memory`,
      `mlx_active_memory`, `mlx_cache_memory`, and a digest of each bank.
    - `suite=chain`: the same, then decision 11's route (`route=host|device`) to the reference bins, and a dense
      score of 64 particles per parity with its digest.
    - `suite=accuracy`: judges `PROJ_BENCH_ERR` on 16 of the directions; it asserts and can fail.
    - A key the suite does not read stops with status 2 and names the key, as in `bench_polar_table`.
    - **Protocol:** an idle machine; wait until the one-minute load is at most 4 and record `uptime` before
      every timed step; `MLX_ENABLE_TF32=0`; a warm-up pass, then the best of 3; two invocations; no other
      `mlxf_test_exec`, `cmake` or `gfortran` process (a measurement that finds one is discarded and repeated).
18. **As SIMPLE runs: 1, 3 and 6 processes,** with 30, 10 and 5 threads, started by `scripts/run_parts.sh`.
    - Every process projects all 2,500 directions of both parities: a part holds all the references.
    - **Estimate of one process** (*derived*; the transforms' working memory is *guessed* at 0.3e9 B): for
      `suite=time`, 0.27e9 B (cube) + 0.44e9 B (banks) + 0.26e9 B (padded cube and transform) + 0.3e9 B, plus
      1.20e9 B for a graph tile: at most 2.5e9 B. For `suite=chain` on the host route, the tiles (1.79e9 B),
      the host memos (0.89e9 B), the tiles' host staging (1.34e9 B, which stays in the footprint once released
      on this macOS) and a bank's copy (0.22e9 B) come on top: at most 7e9 B.
    - **The guard, before any part is started:** the bench refuses a configuration whose derived device bytes
      exceed `PROJ_BUDGET_B` = 8e9 B per process (*guessed*). The launcher's own guard then predicts the summed
      footprint from the splits already measured and does not run a split above 0.8 of 103.1 GB (82.46e9 B).
      Predicted from the estimate: 21e9 B at 3 and 42e9 B at 6 for the chain, 7.5e9 B and 15e9 B for
      `suite=time`: every split is expected to run. A split that is not run is recorded as such.
    - **Reported per split:** the time from go to the last exit; samples per second in total and per process;
      one process's peak footprint and MLX peak; the machine's lowest free memory. Reported, not gated: the
      roadmap's two conditions (total rate below 0.8 of one process's; summed footprint above 51.5e9 B).
19. **The keep-or-delete rule of the fused kernel** (roadmap decision 15).
    - **The canonical driver** is one state's reprojection as `read_mask_filter_reproject_refvols` runs it: per
      parity `new`, `set_rmat`, `pad_fft`, `expand_cmat`, `vol_pad2ref_pfts_opt`, `kill`, ending when both banks
      are evaluated on the device. It is `suite=time`'s elapsed time, upload, transform, expansion and
      evaluation included. The projection stage's own time explains the result; it does not decide.
    - **Kept** if the driver's time with the graph form is at least 1.30 times its time with the fused form, each
      at its canonical configuration, in both invocations, at one process and at three (time from go to the
      last exit). Six processes are reported.
    - **Equal work and accuracy:** the same volumes and directions; both forms inside `PROJ_BENCH_ERR`'s gate.
    - **Otherwise deleted** in Phase 4, by `rm` and by removing its lines, with the measurement and its
      mechanism in the report. The graph form stays in either case.
20. **The probe** (roadmap decision 14), the last working phase. It is a measurement with a report, not a
    deliverable of family C, and it adds no toy class.
    - **The one protected update:** SIMPLE's offload insertion with its missing protection. `insert_slices_batch`
      runs one GPU thread per plane and symmetry copy and adds to shared voxels of the two grids with plain
      read-modify-write, so planes that overlap lose updates. The probe's kernel launches one thread per (pixel,
      plane) and adds its 27 weighted deposits with `atomic_fetch_add_explicit` to float32 outputs under
      `atomic_outputs` and `init_value` 0: the numerator as `(2, nvox)` (real and imaginary parts), the density
      as `(nvox)`: 81 atomic additions per pixel.
    - **Its control:** the same kernel without atomics (`+=`), which shows what SIMPLE's offload loses.
    - **Fallbacks, in order,** if a float32 atomic output does not build: a uint32 atomic output with a
      compare-and-exchange loop on the float's bits; then `mlx_scatter_add` on the flattened grid.
    - **Fixtures.** Small: the oracle's three planes at N = 8, and 64 seeded planes at N = 16. Collision-heavy:
      N = 160 (2,341,350 accumulator voxels), two of SIMPLE's batches of 500 planes (`MAXIMGBATCHSZ`), 10,373
      inserted pixels per plane, 2.8e8 deposits, 120 per voxel on average (*derived*); once with seeded
      orientations and once with all 1,000 planes in one orientation, where every voxel is hit by every plane.
    - **Measured against `oracle_grid_lattice`** (`insert`, `numerator`, `density`, on the accumulators before
      compression): the numerator's and the density's largest error over the sum of `|terms|` of the voxel,
      against `PROBE_ERR_CAP` = 1e-5 (*guessed*, the examples note's cap; a probe's bound, not K6's); the number
      of voxels whose bits differ between run 1 and each of 9 repeats, and the largest such difference; the
      share of the mass the unprotected control loses; `mlx_peak_memory` less the resident grids and planes
      (the scratch); seconds per batch, protected and unprotected, one process, best of 3.
    - **Outcomes, fixed before the run:**

      | Outcome | Condition | What K6's plan takes from it |
      | --- | --- | --- |
      | A | inside the cap and bit-repeatable in all repeats on both large cases | the easy win holds: K6 starts from the atomic kernel |
      | B | inside the cap, not bit-repeatable | the speed is there, the family's repeatability gate is not met: K6 needs a deterministic form, and the atomic kernel is its speed reference |
      | C | outside the cap, or no atomic form builds | the premise fails: K6 starts from `mlx_scatter_add` and the sorted form |

    - The code is one module, `mlxf_bench_insert_probe`, reached as `test=bench_insert_probe`. It stays until
      K6's plan takes it over or removes it.
21. **What "protected" can mean in a Metal kernel, given what mlx-c exposes.**

    | Form | Exposed by | Correct | Repeatable | Scratch |
    | --- | --- | --- | --- | --- |
    | Atomic float additions | `atomic_outputs` (read in MLX's `custom_metal_kernels.rst`, whose gradient example adds floats; *measured* here for int32 only) | yes, to rounding | not expected: the order of additions varies | none |
    | Atomic integer additions of fixed-point values | the same, int32 (*measured* exact for 4,096 colliding updates) | to the fixed point's resolution | yes, by construction | none; needs a range analysis |
    | `mlx_scatter_add` | the library (form 1 of family C) | yes | not promised (binding policy) | 27 positions and updates per pixel: 4.5e9 B per 1,000 planes (*derived*) |
    | Sort by voxel (`mlx_argsort`), then segment sums in a fixed order | the library, or a kernel with one thread per voxel reading its run | yes | yes | the sorted keys and values, as above |
    | Threadgroup memory, one group per block of the grid | not exposed: MLX writes the kernel's signature, and a `threadgroup` array declared in the body is untested | unknown | unknown | unknown |

    The probe tries the first row. The fifth is a question for Apple: it enters
    `doc/collaboration/apple_questions.md` under the next free number, "threadgroup memory and atomic float
    outputs in a kernel written through mlx-c", with what the probe measured.
22. **Rule `mirror` learns public module procedures.** A ledger line may name a public procedure of a toy
    module (`<toy module> <procedure> <SIMPLE module> <procedure>`), the rule requires a line for each, and rule
    `arity` exempts the mirrored ones. Planted violations: a public procedure without a line; a mirrored line
    whose name differs; an addition with six dummies. The policy's section 4 says so in the same change.
23. **Family A does not move.** Phase 0 takes the digests of `bench_polar_table` (`accuracy` on both devices,
    `time` for `2500_4` at 64 by 250 on the GPU) twice on the base. Where the two agree, every later phase that
    edits a family-A file must give the same digest; the suites `polarft_calc`, `polar_shiftmap`,
    `polar_shiftmap_accuracy` and `eul_prob_tab` keep the counts Phase 0 records.
24. **A file the table does not name.** The run may add a row for a new `src/test/mlxf_toy_*.f90` file before
    its first edit, with the reason in Progress. No row is added outside `src/test/`.
25. **Counts.** The existing areas keep their counts (`unit_kernels` 1,063 or the base's, `unit_fast` 94,
    `unit_fft` 194, `unit_linalg` 632, `unit_ops` 2,402, `unit_array` 179, `unit_compile` 63, `unit_core` 80 to
    82). The new suites join `unit_kernels`; their counts are recorded when written. The CTest budget stays 9.
    A suite above 0.5 s in Release says why in its registration comment; the fast gate stays under its 60 s.
26. **Differences from SIMPLE, declared** (the ledger carries each addition's reason; the design note's
    section 4 takes this list in Phase 6):
    - **Types.** `projector` does not extend an `image` class: it carries the four `image` procedures the
      reprojection calls. `eulspace` is an array of rotation matrices, not an `oris` object.
    - **Dummies dropped:** `wthreads`, `mirr_proj`.
    - **Members.** `cmat_exp` is a device array in `ws`, not a public member; the padded transform is not kept
      after `expand_cmat`; there is no `kbwin` object (the window is the standard one, its coefficients computed).
    - **The transform** of `pad_fft` is the device's, not FFTW's; the expansion is made by device gathers.
    - **The fill.** SIMPLE writes the bank into a section of `pfts_refs`. The toy has a staging of 64 sections:
      the host route goes through `set_ref_pft` (in `complex(real64)`, family A's declared kind), the device
      route hands the bank to the workspace.
    - **The loop** of `read_mask_filter_reproject_refvols` (per state and parity: `new`, `pad_fft`,
      `expand_cmat`, `vol_pad2ref_pfts_opt`, `kill`) is written by the tester and the benchmark in SIMPLE's
      order; there is no centring, mask, filter or low-resolution blend.
    - **Tiles and forms:** `set_fproject_form`, `set_fproject_tile`; SIMPLE has one loop nest and an offload
      directive.
    - **Refusals** with `message()` where SIMPLE stops; `final` procedures where the house rule asks for them.

Defaults taken without a question: the module, suite and constant names above; the additions' names
(`set_ref_route`, `set_fproject_form`, `set_fproject_tile`, `fproject_seconds`, `message`), each with its reason
in the ledger; the spiral of the bench (a golden-angle spiral, not `build_refspiral`'s mirrored halves); the
blobs of the bench volume; the digest of family A's benchmark for the banks; the particles of the chain
fixture as family A's tester makes them.

**The choices that are the maintainer's,** each with what the other way costs:

- **11, the hand-over.** Recommended: both routes, the host one as the reference, the device one kept above
  30 %. Host only: no family-A file changes, and the chain says nothing about residency.
- **19, the canonical driver.** Recommended: one state's reprojection to the evaluated banks. Ending at the
  reference bins instead would let the ring transforms and the packing dilute the kernel's gain.
- **3, `eulspace` as matrices, no `mirr_proj`, no toy `image`.** A toy `oris` and `image` would read closer to
  SIMPLE and add two modules with no kernel in them.
- **4 and 10, the device volume is SIMPLE's expanded cube** (274.6e6 B). A Hermitian half (131.9e6 B) or a
  cube cropped to the reach of `kto` (126.5e6 B at 62 shells) halves it and puts the edge logic in the kernel.
- **14, near ties are counted, not judged.** Judging them against both one-sided oracle values is stricter and
  needs an oracle entry that does not exist.
- **20, the probe's update is the atomic kernel.** `mlx_scatter_add` is quicker to write and measures the
  library's form; the sorted form is the deterministic one and is K6's largest piece.
- **22, the policy's ledger gains public procedures.** The other way is to make both procedures type-bound,
  which SIMPLE's are not.

## 4. Not in this plan

- B2 (K5), the insertion's three forms (K6), the PCG solve (K8), arbitrary reference sets (K3), the shift maps
  on device-resident references (K4).
- `mirr_proj`, symmetry, several states in one call, masking and filtering of the volumes, `build_refspiral`.
- The scalar projectors (`fproject`, `interp_fcomp`), a Hermitian-half or cropped device volume, a kernel that
  writes ring transforms or tiles directly.
- A change to the library, the parity ledger or a wrapper; any change to SIMPLE.
- A verdict on one GPU-owning process, and a comparison with SIMPLE's CPU rate: neither is measured here.
- For the probe: compression, density correction, the stored half, timings at 3 and 6 processes, a second
  protected form beyond the fallbacks.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement on the base; scratch probes | both builds without a warning; counts recorded; decision 23's digests twice; the six probes answered |
| 1 | tests-only: new toy code, the graph form | `oracle_projection` asserted; `projector` on both devices: decision 13's first row frozen on seed 1, then seeds 2 and 3; decision 15's controls with their plants; decision 16; decision 22's plants; decision 23 |
| 2 | tests-only: the fused kernel | the same gates on the GPU for the fused form, under the tolerance frozen in Phase 1; its refusal on the CPU device; decision 16 |
| 3 | result-changing for the device route only; identical for family A's existing entries | `projector_chain` on both devices and both routes: the chain's tolerances frozen on seed 1, then seeds 2 and 3; the parity plant; decision 23 |
| 4 | measurement; possibly a deletion | `suite=accuracy` frozen on seed 1, judged on seed 2; the sweeps; decision 19's verdict; decision 11's; decision 18's splits |
| 5 | measurement: the probe | the probe's numbers and its outcome A, B or C; the control loses mass |
| 6 | documentation | the report; `scripts/check_tree.sh`; `git status` shows file-table paths only |

Every phase ends with Debug and Release built from scratch with `-DMLXF_WERROR=ON` (in the run's own trees, by
the recipe of the run's prompt) and no warning, the fast gate 9 of 9 in both,
`scripts/check_tree.sh` passing, `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` run on every
Fortran file touched (the second only with explicit file names), and decision 25's counts.

## 6. Acceptance

- **The exit of the design note's row K2:** the host matrix oracle and the controls pass (Phases 1 and 2); the
  chained test with A passes (Phase 3); the projection is timed at 2,500 directions, pftsz 182 and 61 shells,
  alone and at 3 and 6 processes (Phase 4).
- **Numbers:** decisions 13, 14, 16, 19 and 11's keep rule, each frozen in Progress before the run it judges.
  A tolerance is never taken from the run it judges, a seed is never changed to pass, and a failing gate on
  seed 2 or 3 is a diagnosis, not a new calibration.
- **The mirror ledger** lists every public type, binding and public procedure of the new toy modules.
- **Reported, not gated:** the seam's table with measured bytes; the stages' seconds; the two reopening
  conditions; whether tile shapes change bits; the count of near ties at the bench; the suites' elapsed times;
  the probe's numbers.
- **Hypotheses, each with its test** (*guessed*; none is a criterion): the fused projection is several times
  faster than the graph gather (`suite=time`, the projection stage); the transform and the expansion are a
  large share of the fused driver (the stages); three processes share the GPU without loss, as the dense
  score did (decision 18); the device route removes seconds of host work (`suite=chain`); atomic float
  additions are correct and not bit-repeatable (Phase 5).
- **Reserved for the maintainer:** whether the miniature reads like SIMPLE's reprojection; the ruling K6 needs
  after outcome B (is repeatability required of the insertion that is kept).

## 7. Common rules and stop conditions

- No file outside the table, apart from decision 24's rows. No bound loosened, no fixture changed to pass.
- A test executable run directly on the GPU is run with `MLX_ENABLE_TF32=0`.
- MLX is called by one submitting thread, outside any OpenMP region; the host loops (padding, coordinates,
  fixtures) may use the team.
- A large host array is not staged and released where a footprint is measured: on this macOS it stays counted.
- Git is read-only. The run writes its notes with the editor tools.

**Stops:**
- a Phase 0 probe shows that neither the complex64 output nor its float32 fallback works, or that `mlx_take`
  cannot address the expanded cube at the bench: a missing or insufficient wrapper, reported;
- a tolerance measured on seed 1 is above its ceiling of decision 13;
- a control fails on the unplanted code after one attempt to find the fault in the toy (the oracle is not
  edited: a suspected oracle fault is a stop with the evidence);
- a digest of decision 23 moves;
- a change to `src/core/` or `src/defs/` would be needed;
- SIMPLE's code contradicts a decision of section 3 in a way no declared difference resolves;
- one bench process exceeds `PROJ_BUDGET_B`, or the machine cannot run the one-process bench;
- the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
oracle shares no code with the toy; no SIMPLE source copied; a tolerance frozen before the run it judges; the
graph form kept; the repeatability gate for a form that is kept.

## 8. Phases

### Phase 0, the base and the probes

1. Record the machine, the toolchain, the base commit and SIMPLE's commit. Build Debug and Release from scratch;
   run the gate; record every area's count and compare with decision 25.
2. Take decision 23's digests twice; record which are repeatable.
3. Build the oracle modules alone by their reports' recipe and run the three self-checks (12, 32, 13).
4. Scratch probes against the installed library, outside the repository, each a few lines, each answered in
   Progress with its log:
   - a Metal kernel with a complex64 output of rank 2; if refused, the float32 form with `mlx_bitcast`;
   - a float32 atomic output with colliding `atomic_fetch_add_explicit`; if refused, the uint32 loop;
   - `mlx_take` without a dimension on a complex64 array of 34,328,125 elements with 74,938,500 positions
     (one tile of 250), on both devices: seconds and `mlx_peak_memory`;
   - `mlx_rfftn` of a 320³ real array on the GPU: seconds, peak, and its error on a seeded 16³ cube against
     `oracle_dft_3d`;
   - the stencil base: `sign(t) floor(|t| + 0.5)` on ±0.5, ±1.5, ±2.5 in a graph and in a kernel;
   - a `threadgroup` array declared in a kernel's body: does it build (for decision 21's question only).
5. Dry-run the fixtures on the host: the near-tie counts of decision 12's fast fixtures (must be 0 after
   redraws) and of the bench's spiral; the samples the edge fixture reaches.
6. Read SIMPLE's files of section 2 again at `d354efee2` and write into Progress the dummy lists kept and
   every difference found beyond section 3's table.

**Exit:** the base's counts and digests are in Progress; every probe has an answer and none meets a stop; both
builds are free of warnings; the gate passes.

### Phase 1, the graph form on the small fixtures

1. `mlxf_oracle_projection_tester` and its registry row: the self-checks asserted against their own limits.
2. Rule `mirror`'s extension with its planted violations (decision 22); the policy's section 4.
3. `mlxf_toy_projector`, `mlxf_toy_projector_workspace`, `mlxf_toy_projector_pft_batch` with the graph form;
   `get_kfromto`, `get_polar_coords` and `vol_pad2ref_pfts_opt` on the calculator, host route; the ledger lines.
4. `mlxf_toy_projector_tester`, suite `projector`: the phantom, seeded and edge fixtures on both devices.
   Calibrate `PROJ_FIXTURE_ERR` on seed 1 on both devices, freeze it, then run seeds 2 and 3.
5. Decision 15's controls, each with its plant shown to fail; decision 16's three repeats; the lifecycle (100
   cycles of `new`, `pad_fft`, `expand_cmat`, a projection, `kill`: `mlx_live_count` and active memory return).

**Exit:** the suite passes on both devices at the frozen tolerance for seeds 1 to 3; every plant fails and the
restored tree passes; decision 23 holds; the phase's gates of section 5.

### Phase 2, the fused kernel

1. The kernel of decision 8 in the workspace, selected by `set_fproject_form`; its kernel objects per launch
   configuration; the refusal on the CPU device through `message()`.
2. The suite `projector` runs the fused form on the GPU through the same fixtures, tolerance, controls and
   plants as Phase 1 (the plants are applied to the kernel's source), with tiles of 2 and 1, and 4 and 2.
3. Decision 16 for the fused form; the two forms' largest difference from each other is reported.

**Exit:** the fused form passes every gate of Phase 1 on the GPU under the tolerance frozen there; a kernel
source that does not compile and a threadgroup of 2,048 are refused with a message and leave the workspace
usable; the phase's gates.

### Phase 3, the chained test with A

1. The host route end to end on the chain fixture: project both parities, `memoize_refs`, `memoize_ref_bins`,
   a dense block with its rows, against the oracle chain. Calibrate `PROJ_CHAIN_ERR_HOST` on seed 1 on both
   devices, freeze, run seeds 2 and 3.
2. The device route (decision 11): `set_ref_route`, the ring transforms and the tiles on the device; the same
   test; `PROJ_CHAIN_ERR_DEVICE` calibrated and frozen the same way. The two routes' rows are compared with
   each other and the difference reported.
3. The parity plant; a block scored before `memoize_ref_bins` on either route is refused; a shift map on the
   device route is refused; decision 16 for the chain (three runs, the rows' bits).

**Exit:** `projector_chain` passes on both devices, both routes and both forms (the fused one on the GPU) for
seeds 1 to 3; decision 23 holds; the phase's gates.

### Phase 4, the bench and the verdict

1. `mlxf_bench_projector` with its three suites and key lists; `scripts/run_parts.sh` takes the bench, the
   suite and the rate's unit from settings, with today's as the defaults and its columns unchanged (the polar
   bench's rows must come out as before: one split of `bench_polar_table` is run to show it); `BENCHES`.
2. `suite=accuracy`: calibrate `PROJ_BENCH_ERR` on seed 1 on both devices (the CPU device with the graph form on
   the 16 directions), freeze, judge seed 2 for both forms.
3. The sweeps of decision 9; freeze each form's canonical configuration.
4. The verdict of decision 19: `suite=time` for each form, two invocations, at one process and at three.
5. Decision 18's splits for the form that is kept (and for the graph form): 1, 3 and 6 processes, the guard
   before each.
6. `suite=chain` at one process, both routes, two invocations: decision 11's verdict; then 3 and 6 processes
   for the route that is kept.
7. Apply the verdicts: a path that is not kept is removed with its ledger lines and tests, and both builds pass
   without it.

**Exit:** the verdicts are in Progress with their numbers and load records; every split was run or recorded as
not run; the digests of repeated passes agree; the phase's gates.

### Phase 5, the protected-update probe

1. `mlxf_bench_insert_probe`: the kernel, its unprotected control, the fixtures of decision 20, the
   `oracle_grid_selfcheck` asserted before the oracle is used.
2. The small fixtures on the GPU; then the two collision-heavy cases: the errors, the 9 repeats, the lost mass,
   the scratch, the seconds.
3. Name the outcome A, B or C. Write the Apple question (decision 21) with the numbers.

**Exit:** the probe's table is in Progress; the outcome is named by decision 20's conditions; the unprotected
control differs from the oracle on the one-orientation case (if it does not, the fixture does not collide and
the probe is not finished); the phase's gates.

### Phase 6, the record

1. The kernel-families note: section 2a's row B1, section 4 (the seam's table with measured bytes, "Differences
   from SIMPLE", the numbers, the open decision on the intermediate array closed), section 5 (the probe's
   outcome), section 8's row. The roadmap's rank 2 row and decision 14. The toy policy, the test policy, the
   index, the history, the root `README.md` where it names the toys.
2. The report, in the order of `doc/how2s/how2write_agent_plans.md`, section 8, with: the seam's table; the
   timings at each split; both verdicts; the probe's table and outcome; the ledger's counts; the list of new
   files by name; a commit message without an attribution or co-author line.

**Exit:** the report exists; `scripts/check_tree.sh` passes; `git status` shows only file-table paths.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_toy_projector.f90` (new) | the toy `projector` | 1, 2, 3, 4 |
| `src/test/mlxf_toy_projector_workspace.f90` (new) | its device state: the cube, the graph form, the kernel | 1, 2, 3, 4 |
| `src/test/mlxf_toy_projector_pft_batch.f90` (new) | `fproject_polar_batch_opt` | 1, 2, 3, 4 |
| `src/test/mlxf_toy_projector_tester.f90` (new) | suites `projector`, `projector_chain` | 1, 2, 3, 4 |
| `src/test/mlxf_oracle_projection_tester.f90` (new) | suite `oracle_projection` | 1 |
| `src/test/mlxf_toy_polarft_calc.f90` | the interfaces of the mirrored additions and of `set_ref_route` | 1, 3, 4 |
| `src/test/mlxf_toy_polarft_core.f90` | `vol_pad2ref_pfts_opt`, `get_kfromto`, `get_polar_coords` | 1, 3, 4 |
| `src/test/mlxf_toy_polarft_memo.f90` | the device route of `memoize_refs` and `memoize_ref_bins` | 3, 4 |
| `src/test/mlxf_toy_polarft_workspace.f90` | the interface of the tiles made from device sections | 3, 4 |
| `src/test/mlxf_toy_polarft_workspace_lifecycle.f90` | those tiles | 3, 4 |
| `src/test/mlxf_toy_polarft_shiftmap.f90` | the refusal of a map on the device route, if needed | 3 |
| `src/test/mlxf_bench_projector.f90` (new) | the bench | 4 |
| `src/test/mlxf_bench_insert_probe.f90` (new) | the probe | 5 |
| `src/test/mlxf_test_defs.f90` | the tolerances, the constants mirrored from SIMPLE, `parameters`' new members | 1, 2, 3, 4, 5 |
| `src/test/mlxf_test_registry.f90` | the suites' rows; `BENCHES` | 1, 3, 4, 5 |
| `src/test/test.inf` | the directory's description | 1, 5 |
| `test/CMakeLists.txt` | the comment on the area `kernels`, if it names the suites | 1 |
| `scripts/toy_mirror.txt` | the ledger's lines | 1, 2, 3, 4 |
| `scripts/check_rules.py` | rule `mirror` for public procedures; the arity exemption | 1 |
| `scripts/run_parts.sh` | the bench, the suite and the rate's unit as settings, today's as the defaults; the columns unchanged | 4 |
| `scripts/check_test_registry.py` | only if the two new benches' rows need it | 4, 5 |
| `doc/policies/toy_example_policy.md` | section 4 (public procedures); section 6 | 1, 6 |
| `doc/policies/binding_contract_policy.md` | section 12, if Phase 0 measured what it lists as not tested (a complex64 output, a float32 atomic output) | 6 |
| `doc/policies/test_environment_policy.md` | the area `kernels`; the benches | 6 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | sections 2a, 4, 5 and 8 | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | the rank 2 row; decision 14's result | 6 |
| `doc/collaboration/apple_questions.md` | the question of decision 21 | 5 |
| `doc/implementation_notes/README.md` | the index | 6 |
| `doc/history/2026-11.md` | the entry | 6 |
| `README.md` | the status, where it names the toys | 6 |
| `doc/implementation_notes/planned/mlxf_kernel_k2.md` | this note: Progress, decision 24's rows | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/completed/mlxf_kernel_k2_report.md` (new) | the report | 6 |

## Progress

(one entry per phase, written by the run)
