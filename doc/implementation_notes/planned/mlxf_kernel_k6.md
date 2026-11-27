# K6, family C: the insertion of particle planes into the Fourier volume as a toy `reconstructor` (run `mlxf_kernel_k6`, on the M5 Ultra)

Status, 2026-11-26: planned; ruled as recommended by Hans, 2026-11-26 ("Rule as recommended"), every decision of section 3 and the run order K4, K3, K5, K6, K7; revised after ranks 2d to 2f (runs `mlxf_refactor`, `mlxf_toy_layout`,
`mlxf_kernel_forms`).
Base: the commit that holds this plan, after rank 2g's result and K5's (the run pins its hash in Phase 0 and
records it). The revision was checked against `ae7d623` (ranks 2d to 2f committed) with the three uncommitted
document edits of 2026-11-26; the draft was written at `b2c43a4`. SIMPLE is pinned at `28c753993`, the mirror
ledger's pin since rank 2e, read with `git -C ~/src/SIMPLE show 28c753993:<path>`, never its working tree, and
never edited; none of the SIMPLE files this plan reads changed between the draft's pin `d354efee2` and this one
(checked with `git diff -w`). Supersedes: none. Depends on:
- `type(mlx_metal_kernel)` and `mlx_metal_kernel_spec` (validated: yes, `unit_fast` 152; complex64 inputs and
  outputs, float32 atomic outputs and rank-2 outputs *measured* in K2's Phase 0; an int32 input that carries
  sizes, on the insertion kernel and on a pull of one thread per voxel at n = 64 and 96, `threadgroup` arrays
  up to 32,768 B with barriers, *measured* by run `mlxf_kernel_forms`, `completed/mlxf_kernel_forms_report.md`,
  suites `sizes`, `insert` and `probe`; a launch grid that is not a multiple of the threadgroup, never run:
  Phase 0);
- `mlx_scatter_add`, `mlx_take`, `mlx_async_eval`, `mlx_argsort` (validated: public in `src/core/mlxf.f90`;
  `mlx_scatter_add` with complex64 updates and 1.4e8 positions never run on either device: Phase 0);
- `mlxf_oracle_gridding` and `mlxf_oracle_projection` (validated: yes, standalone under GNU Fortran 16.2 at
  `-O0` and `-O2`, 13 checks of `oracle_grid_selfcheck`; only `mlxf_bench_insert_probe` calls the gridding
  oracle's lattice today, no tester does);
- `mlxf_bench_insert_probe` (validated: K2's Phase 5, the table in `mlxf_kernel_k2.md`'s Progress; since run
  `mlxf_kernel_forms` its `probe_spec`, `seeded_case` and `window_coefficients` are public and
  `mlxf_bench_kernel_forms.f90` imports them, and its `probe_case` record lives in `mlxf_test_defs.f90`);
- the measured forms of the insertion at small n (run `mlxf_kernel_forms`, suite `insert`): the atomic push
  (D0), a pull with one thread per voxel (D1) and that pull with each plane's patch staged in `threadgroup`
  memory (D2), section 1 and decisions 7, 8 and 24;
- rank 2g's result (read in Phase 0: it changes `src/core/` and may add assertions to unit areas);
- the roadmap's decisions 8, 9, 11, 14 (ruled B, 2026-11-25), 15, 16 and 17, the toy-example policy with both
  ledgers, and `mlxf_toy_device_work` (validated: the seam run's report, `SEAM_PENDING` = 0).

## 1. Why

The insertion of particle planes into the 3D Fourier volume (`rec_backend=gridding`) is the last step of a
part's reconstruction that has no deterministic GPU form. K2's probe showed that one thread per pixel with
atomic additions inserts a batch of 500 planes at n = 160 in 0.037 s (*measured*, K2 Phase 5) and that two runs
differ in 1,139,762 of 2,341,350 voxels (*measured*, same table). The maintainer ruled B: K6 needs a
deterministic form, and the atomic kernel is a speed reference only. The mlx3D note proposes the form: a pull,
one thread per voxel, each voxel written once. This plan builds the toy `reconstructor` in the integration
shape, a graph form as reference, the pull as the candidate to keep, and measures what determinism costs
against the atomic kernel. SIMPLE's own insertion is not measured here and no record of it is in hand, so the
run reports rates and claims no gain over SIMPLE.

The expected outcome, before the decisions (revised 2026-11-26 by run `mlxf_kernel_forms`). SIMPLE's cost as
derived, 0.05 s per batch of 500 on 30 threads at perfect scaling (unmeasured, decision 26), is close to the
atomic kernel's *measured* 0.037 s. The plain pull (one thread per voxel, 8 x 8 x 8 tiles, a slab test per
plane that a tile's threads take alike, the 6 x 6 scan) was measured at small n: exact against the push
within the push's own noise (1.8e-6 of a voxel's |terms| against the push's 1.4e-6 against itself) and
repeatable, but 14.5 times slower than the push at n = 64 and 5.6 times at n = 96 (*measured*, suite
`insert`, 500 planes); staging each plane's patch in `threadgroup` memory made it 9 to 47 % slower still. The
factor shrinks with n: extrapolated, 68.8 ms against 41.5 ms a batch at n = 160, a factor of 1.66 (*derived*
from the two sizes; the push grew as n^3 between them, the pull far slower than its n^3 walk; the
extrapolation lies outside the bounds that run froze, so it is read, not judged). The plan therefore expects
a deterministic insertion within a small multiple of the atomic kernel at n = 160, which this run measures;
the draft's derived 3 to 4 times with the pre-pass and the lists, and 27 times for the plain pull, are
withdrawn as predictions (decision 24).

## 2. Contract

- The run works on the M5 Ultra only (30 cores, 103.1 GB, the only GPU), in the session, in a copy of the
  checkout, one run at a time. Builds are hand-configured trees with `-DMLXF_WERROR=ON -DFORTLS=OFF
  -DBUILD_TESTS=ON`. Git is read-only.
- Toy code lives in `src/test/` only (rank 2d's tree): the toy in `src/test/toys/recon/` as `mlxf_toy_<stem>`
  under SIMPLE's names, its fixture in `src/test/oracles/`, its bench in `src/test/bench/`, against the public
  `mlxf`. No file under `src/core/` or `src/defs/` changes. A missing wrapper is a stop, not a workaround.
  Every new Fortran file opens with its `!@descr:` line, and `doc/code_base_map.md` is regenerated in the
  phase that adds or removes one (the static gate checks it).
- The toy has the integration shape from its first build: host files that compile without the library, glue
  `<unit>_mlx` with stubs under `#else`, device modules behind one `class(device_work)`, both ledgers, cycles
  and refusals in sub-suite `seam`, and the off-state program asking the new class for the MLX backend.
- Results are judged against `mlxf_oracle_gridding` in double precision. The toy imports no oracle. The oracle
  is not edited.
- Tolerances are measured on seed 1 on both devices, frozen in `src/test/framework/mlxf_test_defs.f90` and in Progress
  before seeds 2 and 3 are run, and judged on seeds 2 and 3. Every gate has a planted violation shown to fail.
- A form is kept only if it is repeatable bit for bit on one GPU configuration and tile shape, over repeats
  and over two invocations (roadmap decision 14, ruled B).
- A second code path for the same computation needs a measured gain above 30 % on the canonical driver
  (roadmap decision 15), with the ceiling measured first and the configurations frozen before the verdict runs.
  Under ruling B the pull is the GPU's first path, not a second one: the rule judges the pull's variants, never
  the pull against the graph form (decisions 16 and 24).
- No production data. SIMPLE is not measured: a statement about SIMPLE's cost carries its origin.
- The report ends with a commit message without an attribution or co-author line that names every new file.

### What the check found (2026-11-26)

Read in SIMPLE at `d354efee2` and in the working tree of `b2c43a4`; re-read at `28c753993` (no file read here
changed) and at `ae7d623` (items 4, 10, 12 and 13 revised). A premise of the design notes that the code
contradicts is marked **differs**.

1. `reconstructor` (`src/main/volume/simple_reconstructor.f90`) extends `image`. `alloc_rho` sets the Friedel
   limits `lims = loop_lims(2)` and the expanded bounds `ldim_exp(1,:) = [lims(1,1) - wdim, dim]`,
   `ldim_exp(2:3,:) = [-dim, dim]` with `dim = maxval(abs(lims)) + ceiling(KBWINSZ)`. `cmat_exp` and `rho_exp`
   are public ("only made public for the sake of GPU implementation"). The oracle's lattice
   (`lattice_insert` of `src/test/oracles/mlxf_oracle_gridding.f90`) holds h from -3 to n/2 + 2 and k, m from
   -(n/2 + 2) to n/2 + 2, a shape of (n/2 + 6, n + 5, n + 5): 86 x 165 x 165 = 2,341,350 voxels at n = 160
   (*exact*, the probe's count). The values behind `loop_lims(2)` were taken from the oracle's layout, not read
   in `simple_ftiter.f90` beyond the procedure's modes.
2. `insert_plane_oversamp(self, se, o, fpl, w)` works on the **native** lattice: `loc = (h, k, 0) R` with no
   padding factor, three taps per axis at `nint(loc) - 1` to `nint(loc) + 1`, weights by `apod_fast`
   normalised per axis by a reciprocal of their sum (internal `kb_apod_vecs_3d_fast`), the deposit
   `ww = wx(ix) * (wy(iy) * wz(iz))`, `cmat_exp += comp * ww` with `comp = 4 w c`, `rho_exp += ctfval * ww`.
   Pixels lie in the disc `h*h + k*k <= nyq*(nyq + 1)`; k > 0 reads the conjugate of the mate; a sample at or
   under `TINY` = 1e-10 is skipped; a pixel whose three h taps are all negative is skipped. The oracle's
   `lattice_insert` states the same rule in double precision.
3. The order in which `insert_plane_oversamp` adds to one voxel is fixed: symmetry copy, then the colour
   `l = 0 .. stride - 1` of the h line with `stride = ceiling(sqrt(3.) * wdim)` = 6, then k ascending. Lines of
   one colour are 6 apart and a voxel hears from at most 6 consecutive h lines (decision 7), so two threads of
   the `!$omp do schedule(static,1)` never add to one voxel and the result does not depend on the thread count.
4. **differs.** SIMPLE has three statements of the deposit and they do not give the same bits. The CPU path
   forms `loc(a) = hrow(a) + real(k) * r2a` and multiplies by a reciprocal of the weights' sum.
   `insert_slices_batch` (`src/main/volume/simple_reconstructor_openmpoffload.f90`) forms `loc` by repeated
   addition of `r2` along k, divides by the sums, multiplies `wx(i) * (wyz * comp)`, takes its composite rows as
   `rotmats(:,:,i)` times `symmats(:,:,isym)`, and carries no per-plane weight `w`. The probe's kernel
   (`SRC_HEAD` of `src/test/bench/mlxf_bench_insert_probe.f90`) forms `h * rot[..] + k * rot[.. + 1]` with the
   contraction left to the compiler, divides by the sums and multiplies `w[0][a] * w[1][j] * w[2][l]`.
5. **differs.** `sampl_dens_correct` is not part of a part's work. `calc_3Drec`
   (`src/main/strategies/search/simple_matcher_3Drec.f90`) ends a state's half with
   `write_state_half_partial`, which calls `compress_exp` and `write_raw_accum`. `sampl_dens_correct` is called
   by `restore_base` and `restore_final`, which `simple_volassemble_strategy.f90` calls in the master. The
   families note's section 2a lists it among the methods kept; the toy keeps it and the driver does not call it.
6. `calc_3Drec` holds one `recvol` per state and half at a time (`init_state_half_rec`,
   `update_state_half_rec`, `write_state_half_partial`, `kill_state_half_rec`), in batches of `MAXIMGBATCHSZ`
   = 500 (`src/defs/simple_defs.f90`). `update_state_half_rec` inserts the batch's planes one by one. A batch is
   therefore homogeneous in state and half on the CPU path. Only `calc_3Drec_gpu` mixes the halves in a batch
   (`even(i)` chooses the grid) and falls back to `calc_3Drec` for several states.
7. A prepared plane (`fplane_type` of `src/defs/simple_type_defs.f90`, filled by `gen_fplane4rec` of
   `src/main/image/simple_image_ctf.f90`) holds `cmplx_plane` and `ctfsq_plane` on the native lattice for
   k <= 0 only, zero beyond the Nyquist shell, with `frlims`, `shconst` and `nyq`.
8. **differs.** K6's output does not feed K8's `set_raw_accum`. `set_raw_accum` of
   `src/test/toys/recon/mlxf_toy_reconstructor_pcg.f90` refuses arrays that are not `(box + 1, boxpd, boxpd)`: the padded
   lattice, filled in SIMPLE by `reconstructor_pcg`'s own scatter (`scatter_window_pair`, coordinate
   `2 (h, k, 0) R`, wrap, numerator scale 8, disc `nyq*nyq`, as `oracle_recon_fixture_accum` states it). The
   gridding accumulators are `(n/2 + 1, n, n)` on the native lattice with scale 4 and a halo instead of a wrap.
9. **differs.** The insertion is not the adjoint of K2's projector on K2's grids. The projector's cube
   (`src/test/toys/projector/mlxf_toy_projector_workspace.f90`) is the full `(M + 5)**3` on the padded lattice. The gather
   that is adjoint to the insertion in SIMPLE is the reconstructor's own (`project_fplane`), which no toy
   models. The adjoint identity is therefore tested against an explicit host matrix (decision 20).
10. **differs.** The mlx3D note's arithmetic for the pull (its section 3) is corrected in decision 7: 4,851
    tiles, not about 4,600; 1.24e9 plane tests a batch when every thread tests every plane, not 2.3e6; 2.84e5
    weighted pairs a plane, not 5.5e5; about 4.7e4 reached voxels a plane, not 1e5; and a cost the note does
    not count, the 27-fold repetition of the window's arithmetic, which made the stencil pre-pass the expected
    faster form by several times. Run `mlxf_kernel_forms` then measured the plain pull itself (section 1): its
    time is not its flop count's, so the pre-pass's gain is measured here, not expected (decisions 7 and 24).
11. `mlx_scatter_add` was read in `~/src/mlx` at `5c8989446`, which may not be the installed 0.32.4:
    `mlx/backend/cpu/indexing.cpp` copies the source and loops over the updates in order;
    `mlx/backend/metal/indexing.cpp` copies the source and its kernels add with
    `mlx_atomic_fetch_add_explicit`. Expected: repeatable on the CPU device, not on the GPU. Not measured.
12. mlx3D was read in `~/src/mlx3D` at `7101ec3`. What the mlx3D note says of its code holds where it was
    checked: sizes in an int32 input `iparams` (`splatting/tiles.py`, `splatting/fast.py`); `threadgroup`
    memory with `threadgroup_barrier` in production kernels (`ops/knn.py`, `splatting/rasterize.py`). Run
    `mlxf_kernel_forms` corrected the note (P3, the waits, is the viewer's path; mlx3D uses no SIMD-group
    function) and measured both features through our wrapper (Apple question 26).
13. The tree at `ae7d623`: `unit_kernels` 1,953 checks; fast gate 13 entries, 10.44 to 10.51 s in Release
    (run `mlxf_kernel_forms`), bound 38.74 s; `BENCHES(6)` and `NAMED_ONLY(4)` in
    `src/test/framework/mlxf_test_registry.f90`; `scripts/toy_seam.txt` 26 files;
    `test/offstate/mlxf_offstate_exec.f90` asks `polarft_calc`, `projector` and `reconstructor_pcg`;
    `scripts/check_toy_offstate.sh --exec` compares the table of the one sub-suite `polarft_host`; test sources
    are found by a glob in `src/CMakeLists.txt`; the test tree's folders (`framework/`, `oracles/`,
    `toys/{polar,projector,recon}/`, `bench/`) each have an `.inf` the static gate checks; the last Apple
    question is 36.

### The queue

Ranks 2d, 2e and 2f are delivered and committed (`ae7d623`); rank 2g, the user-facing hardening, runs next and
before this batch (roadmap decision 17). Then the five kernel plans run in the order K3, K4, K5, K6, K7, one at
a time, each on the tree the earlier ones left. K3, K4 and K7 edit the polar toy; K5 and K6 bring new classes.
All five edit `src/test/framework/mlxf_test_defs.f90`, `src/test/framework/mlxf_test_registry.f90`, the
folders' `.inf` files, `doc/code_base_map.md`, `scripts/toy_mirror.txt`, `scripts/toy_seam.txt`,
`test/offstate/` and the families note.

Rank 2g changes `src/core/` and no test file: integer statistics, the Euclidean norms and floating means in a
scaled form, empty extrema, integer-scalar operators, saves that keep a file on failure, an index validator.
It may raise the counts of `unit_ops`, `unit_io`, `unit_linalg`, `unit_array` and `unit_core`; it changes no
operation this plan calls (`mlx_scatter_add`, `mlx_take`, the kernels). K6 reads no file of the polar toy, so
K3 and K4 change no design premise of this plan. Rank 2g, they and K5 may change these, and Phase 0 re-checks
exactly these and records each value it finds:
- rank 2g's report: what it changed of the list below;
- the count of `unit_kernels` (1,953 at `ae7d623`), the fast gate's entries and seconds, and the other areas'
  counts;
- the sizes of `BENCHES` and `NAMED_ONLY` and the rows of area `kernels` in the registry;
- the members of `parameters` and the constants of `mlxf_test_defs.f90` (a name this plan adds may be taken);
- the line format and the line counts of both ledgers, and `SEAM_PENDING` = 0;
- the classes the off-state program asks, and what `scripts/check_toy_offstate.sh --exec` compares;
- the settings of `scripts/run_parts.sh` (`RUN_PARTS_BENCH`, `RUN_PARTS_SUITE`, `RUN_PARTS_UNIT`,
  `RUN_PARTS_LOAD`, `RUN_PARTS_MEM`) and the columns of its BENCH.tsv;
- the last number in `doc/collaboration/apple_questions.md` (36 at `ae7d623`);
- that `src/test/bench/mlxf_bench_insert_probe.f90`, `mlxf_oracle_gridding.f90` and `mlxf_toy_device_work.f90`
  are as this plan read them (the procedures named in "What the check found"), and which files import the
  probe's public names (`mlxf_bench_kernel_forms.f90` at `ae7d623`, decision 18).

## 3. Decisions and rulings

Numbers are never reused. A decision marked **(maintainer)** is listed again at the end of the section.

**1. What the toy mirrors.** The class `reconstructor` with `new_accumulator`, `reset_exp`,
`insert_plane_oversamp`, `compress_exp`, `sampl_dens_correct`, `dealloc_exp` and `kill`, and the driver
`calc_3Drec` with its steps `update_state_half_rec` and `write_state_half_partial`. Not mirrored: the image
the class extends, the FFTW memory, `apply_weight`, the I/O, `expand_exp`, `project_fplane`, `restore_base`,
`floor_rho_shellwise`, `prep_imgs4rec` (prepared planes are the toy's input), `insert_extra_poses`, the
grouping of particles by weights, and several states (one state, both halves). Dummy lists are SIMPLE's,
trimmed to what the toy models, as `reconstructor_pcg%new` is in the ledger today.

**2. Files and seam classes.** Host: `mlxf_toy_reconstructor` (the class) and `mlxf_toy_matcher_3Drec` (the
driver; a host file, since it calls the class only). Glue: `mlxf_toy_reconstructor_mlx`. Device:
`mlxf_toy_reconstructor_workspace` (type `reconstructor_workspace`, extends `device_work`) with the submodules
`mlxf_toy_reconstructor_workspace_graph` and `mlxf_toy_reconstructor_workspace_pull`. The class holds its device
state as one scalar `class(device_work), allocatable :: ws` (a scalar component is finalized, an array one is
not: the seam report). Tester: `mlxf_toy_reconstructor_tester`. If the tree's rules refuse the capital in
`mlxf_toy_matcher_3Drec`, the file is `mlxf_toy_matcher_3drec` and the ledger line says so.

**3. Records.** `mlxf_test_defs.f90` gains `fplane_type` under SIMPLE's name and members (`cmplx_plane`,
`ctfsq_plane`, `frlims`, `nyq`), and three records that stand for classes the toy does not model, as
`parameters` does today: `ori` (the rotation matrix, the state, the half, the weight), `sym` (`nsym` and the
`nsym` matrices that `get_sym_rmat` returns) and `builder` (`pgrpsyms`, the orientations, and the stack of
prepared planes that stands for `reads%read` and `prep_imgs4rec`). `parameters` gains no member unless Phase 1
shows the driver reads one that is missing; the member is then SIMPLE's name and is recorded.

**4. The lattice and the layout.** The Fortran view is the oracle's: `cmat_exp` and `rho_exp` of shape
(n/2 + 6, n + 5, n + 5) with h from -3; the packed half (n/2 + 1, n, n) with (h, k, m) at
(1 + h, 1 + modulo(k, n), 1 + modulo(m, n)). On the device the grids are flat in the Fortran order, voxel
`v = (h + 3) + NH*((k + HK) + NK*(m + HK))` with `NH = n/2 + 6`, `NK = n + 5`, `HK = n/2 + 2`, as the probe's
kernel writes them. The box is even and at least 4; another box is refused with a message.

**5. The deposit rule.** SIMPLE's CPU path, item 2 of the check: the disc, the conjugate for k > 0, the data
floor, the skip of pixels whose h taps are all negative, the normalisation by a reciprocal, the product
`wx * (wy * wz)`, then `comp * ww` and `q * ww`, with the per-plane weight `w`. The composite rotation of a
symmetry copy is the product the offload path forms, rows of the particle's matrix times the symmetry matrix,
made on the host in single precision. How `sym%apply_ori` composes (through `ori%compose` and Euler angles)
was not read to the end; the toy does not model it and the ledger says so. The window is the 15-term
polynomial of `apod_fast` (`src/main/interp/simple_kbinterpol.f90`), whose coefficients the toys already hold.

**6. Coordinates are pinned.** The derivative of the window's logarithm at |x| = 1.5 is about 14 (*derived*:
10.5 x 1.33), so one float32 unit in the last place of a coordinate near 80 (7.6e-6) moves an edge weight by
about 1e-4, and a contracted against an uncontracted `h r1 + k r2` moves it by about 5e-5 (*derived*, half of
that). A reference "on the kernel's own coordinates" is therefore only as good as its coordinate bits. The
pull's coordinate lives once, in the kernel's header, as `fma(k, r2, h * r1)` per axis: one rounding per
operation and nothing left to the compiler. This is also the form GNU Fortran most likely emits for SIMPLE's
`hrow(a) + real(k) * r2a` at `-O3` on arm64 (*guessed*: no disassembly was read). The host states it with
`ieee_fma` of `ieee_arithmetic`, or, if GNU Fortran 16.2 lacks it (not verified by a compile), in double
precision with one conversion per operation. Phase 0 compares the kernel's coordinates with the host's on
1e6 seeded triples, bit for bit. Fallback named in advance: a kernel of the same header that writes
`loc (3, npix, np)`, from which the tester's reference reads the coordinates. The graph form adds two rounded
products (library operations cannot fuse), so its coordinates may differ from the pull's in the last place;
each form is judged against the reference on its own coordinate rule and the forms' mutual difference is
reported, never gated below the coordinates' floor.

**7. The mlx3D note's proposal 1: the pull as form 3, the stencil pre-pass as a measured variant
(maintainer).** Recommended: yes, with the note's arithmetic corrected as follows, every figure at n = 160 and a
batch of 500 planes.
- Tiles of 8 x 8 x 8 over (86, 165, 165) are 11 x 21 x 21 = 4,851 (*exact*), 2,483,712 threads; the note's
  4,600 is 2,341,350 / 512 without the edges. Tiles of 4 x 8 x 8 are 9,702 with the same thread count.
- A plane test costs 4,851 x 500 = 2.43e6 only if it is made once per tile. Without memory shared in a
  threadgroup every thread walks every plane: 2,483,712 x 500 = 1.24e9 tests (*derived*). Decision 12 follows.
- Membership: a voxel v hears pixel (h, k) only if `v - nint(loc)` is in {-1, 0, 1} on each axis, so
  `|v - loc|` is at most 1.5 per axis and at most 1.5 sqrt(3) = 2.598 in length. With orthonormal rows the
  pixel lies within 2.598 of the voxel's projection (v . r1, v . r2), an interval of length 5.196 per axis that
  holds 5 or 6 integers: the 6 x 6 scan is right, and a half-width of 2.599 for rounding still gives 6. The
  bound needs orthonormal rows, so the pull refuses a batch whose rows fail `|r1 . r1 - 1|`, `|r2 . r2 - 1|`,
  `|r1 . r2|` <= 1e-5 (*guessed*).
- A plane has 20,336 disc pixels (*measured*, Apple question 26) of which 10,530 deposit
  (*measured*: 284,313,105 deposits / 27 / 1,000 planes, K2 Phase 5): 2.84e5 weighted pairs a plane, not
  5.5e5 (27 x 20,336, without the skip of negative h taps).
- A plane reaches about 4.7e4 voxels of the half grid (*derived*: 10,530 pixels of unit area times a mean slab
  thickness 3 E(|n1| + |n2| + |n3|) = 4.5), not 1e5; about 6 pixels contribute to a reached voxel (27 / 4.5).
  A plane meets about 370 of the 4,851 tiles (*derived*: a slab of half-thickness 3.5 sqrt(3) + 2.598 = 8.66
  over half a disc of radius 82), so a tile hears about 38 of 500 planes, and about 0.3 of a hit tile's threads
  pass the voxel's own slab test (5.2 / 17.3; the note guessed 1/3).
- The cost the note does not count: the push evaluates a pixel's nine window values once for its 27 deposits;
  a pull that recomputes them per contributing pair evaluates them 27 times. With the families note's 550 flop
  a sample, 319 of them the window (*derived* there), a batch is 2.9e9 flop pushed and about 7e10 pulled
  (*derived*: 1.42e8 pairs x 339, plus 9.9e8 candidate tests x 20; the candidates are 4.7e4 x 500 voxel and
  plane pairs x 5.2 / 4.5 for the conservative slab x 36), a factor of about 24. With the pre-pass (base and
  nine weights stored per pixel, 48 B x 20,336 x 500 = 0.49e9 B, which agrees with the note) the pull is about
  1e10 (*derived*: 3.2e9 for the pre-pass over all 20,336 pixels, 9.9e8 candidate reads x 5, 1.42e8 pairs
  x 10), a factor of about 3. The operation counts are *guessed* per item. The plain pull is built first
  because it is the smaller.
- *Measured since* (run `mlxf_kernel_forms`, suite `insert`, 500 planes, *measured*): the plain pull took 37.3
  ms against the push's 2.56 ms at n = 64 (14.5 times) and 48.9 ms against 8.79 ms at n = 96 (5.6 times), with
  1.66 extrapolated to n = 160 (section 1). The arithmetic above predicts neither the factor nor its fall with
  n, so it no longer ranks the forms: the draft's expectation that the pre-pass is the form kept is withdrawn,
  and the pre-pass is kept only by decision 24's measured verdict on the driver at n = 160.

**8. The forms, and the order that lets a cheap negative end one early (maintainer).** Recommended:
- G, the graph form: coordinates, bases, weights and the 27 products from library operations in tiles of 50
  planes (*derived*: 27 x 20,336 x 16 B = 8.8e6 B of deposits a plane, 0.44e9 B a tile), added with
  `mlx_scatter_add`. It is the reference and the form of the CPU device. Built first, Phase 1.
- A, the atomic kernel (the push): stays in `mlxf_bench_insert_probe`, never enters the toy, the fast reference
  only (revised 2026-11-26: it was 5.6 to 14.5 times faster than the plain pull at n = 64 and 96, *measured*,
  suite `insert`; its seconds per batch are measured beside the pull's in the same session, decision 27).
- P, the pull (decision 10), Phase 2: the deterministic GPU form ruling B asks for, measured at n = 160 on its
  own gates (the run that measured it at small n left n = 160 to this plan), kept on accuracy, repeatability
  and the identities, with no speed rule against the graph form (decision 16). Then its variants in Phase 3,
  in this order: the stencil pre-pass (decision 13), the tile lists (decision 12), a tile shape other than the
  default (decision 11), each kept only above 30 % over the form kept so far (decision 24).
- Staging each plane's needed patch in `threadgroup` memory (the mlx3D note's P1 refinement, D2 of suite
  `insert`): dropped, not a variant. It equalled the plain pull bit for bit and was 9 to 14 % slower at n = 64
  and 39 to 47 % slower at n = 96 (*measured*): staging costs more than the reads it saves.
- S, sort then one thread per voxel reading its run of sorted deposits: the fallback named in advance, built
  only if the pull fails its repeatability or accuracy gate after two attempts at a diagnosis. Its buffers take
  a persistent capacity (the largest count of seed 1 times 1.25) with the tail masked by a sentinel against a
  count on the device and one host wait per pass, never per tile: 2.42 / 2.38 times faster than a wait per
  tile (*measured*, suite `waits`); its sort does not rely on `mlx_argsort`'s stability (Apple question 36).
  Phase 0 times `mlx_argsort` of 1.42e8 uint32 keys once, so the fallback's floor is known before it is
  needed.
- Rejected on arithmetic: segmented sums by differences of `mlx_cumsum` (a float32 running sum over 1.4e8 terms
  loses the small segments), and 36 collision-free scatters a plane by (h mod 6, k mod 6) (deterministic by
  construction, but each scatter copies the grids: 28.1e6 B x 36 x 500 = 0.5e12 B a batch, *derived*).
- Early ends. If the plain pull's null walk (Phase 0) costs more than 10 times the atomic kernel's 0.037 s
  (not expected: the whole plain pull is extrapolated at 1.66 times the push at n = 160, section 1), Phase 2
  builds the pull with tile lists from the start, the plain walk is not built, and the lists are then part of
  the pull, not a variant. If the variants'
  ceiling of decision 24 is below 1.30, Phase 3 is not entered. If the insertion costs more than decision 24's
  multiple of the atomic kernel's seconds, the run stops for a ruling (section 7).

**9. Identity with the CPU's order of summation, or repeatability (maintainer; the families note's open
decision).** Recommended: repeatability is the gate, and the pull adds in SIMPLE's order so that identity is
not foreclosed. The pull can promise: the same bits for the same inputs on one GPU configuration, for any tile
shape and batch split, because a voxel's sum depends on nothing but the order of planes, copies, colours and
k (item 3 of the check). It cannot promise SIMPLE's bits: those also need SIMPLE's coordinate and weight
expressions under the same contraction on both sides, which neither the Metal compiler nor GNU Fortran at
`-O3` documents. What more costs: a host float32 miniature with pinned contraction (the host route of
decision 15 with `ieee_fma` and no optimiser contraction) and a gate of bit identity against it, about one
phase. The run reports the count of voxels that differ between the pull and the host route and the largest
difference; it gates neither.

**10. The pull.** One kernel object per box and tile shape. One thread per voxel of the grid, launched over
(NH, NK, NK) with the tile as threadgroup; if a grid that is not a multiple of the threadgroup is refused
(Phase 0; MLX calls `dispatch_threads(grid_dims, group_dims)` in `custom_kernel.cpp` at `5c8989446`), the grid
is padded to 2,483,712 threads and a thread outside the lattice returns. Inputs: the stored `num` (complex64)
and `dens` (float32); the batch's planes as SIMPLE packs them, k <= 0 with the mate read for k > 0
((n/2 + 1) x (n + 1) x 12 B x 500 = 78e6 B a batch at n = 160, *derived*); the composite rows
`rot (2, 3, ncopies)` in the order plane, then symmetry copy; the weights; `coef(17)`; and `iparams`, an int32
input with the count of plane copies (decision 28). Template integers carry the box only. The thread walks the
plane copies in order; for each, the test of decision 12 (a), then the voxel's slab test `|v . n| <= 2.599`
with the normal n = r1 x r2, then the 6 x 6 candidates in SIMPLE's order (colour of h, then k ascending), each
tested by the header's one stencil function; a contributing pixel's term is added to a register that starts
from the stored value. Each voxel is written once. The kernel uses registers and device memory only: no
`threadgroup` memory, no barrier, no `simd_sum` (the features are available, Apple question 26, but staging
measured slower, decision 8). This is the pull run `mlxf_kernel_forms` measured as D1 at n = 64 and 96 (its
source, `insert_pull_spec` in `src/test/bench/mlxf_bench_kernel_forms_src.f90`, is read, not imported: the
toy writes its own kernel in SIMPLE's colour order and with decision 6's pinned coordinate).
Rounding to the nearest integer is `round` (half away from zero, as `nint`), never `rint`.

**11. Tile shape, batch size, and how a batch adds to the resident grids (maintainer for the default).**
Recommended: the tile is 8 x 8 x 8 by default (512 threads). The shapes 4 x 8 x 8 and 4 x 4 x 4 (256 and 64
threads; all under the 1,024 limit) are variants, judged last against the form kept so far, and one of them
replaces the default only above 30 % (decision 24). The batch is SIMPLE's 500 planes (`MAXIMGBATCHSZ`); a last
batch of fewer planes uses the same object through `iparams`. A batch adds by reading the stored grids as inputs
and writing new ones (28.1e6 B a half, *derived*: 2,341,350 x 12 B), the register starting from the stored
value: no graph addition, and the sum of two batches has the order of one batch of all the planes. The gate:
1,000 planes in batches of 500, of 250 and of 1 give the same bits.

**12. The plane walk.** Three ways, in this order. (a) Every thread tests every plane copy against its
tile's centre, a test the tile's threads take alike so nothing diverges (the walk of suite `insert`'s D1,
*measured* exact and repeatable at n = 64 and 96), then against its own voxel: no extra input, 1.24e9 tile
tests a batch (*derived*). (b) Tile lists from the host: per tile the plane copies whose slab meets
it, in order, as int32 inputs `tcount (ntiles)` and `tlist (ncopies, ntiles)` (9.7e6 B a batch at 8 x 8 x 8,
*derived*: 4,851 x 500 x 4 B), made on the host from the rotations alone (2.43e6 tests in double precision, no
device wait); a thread walks its tile's about 38 copies (9.4e7 slab tests a batch, *derived*). The list's tile
and the launch's threadgroup are equal by default and need not be. (c) Lists built in `threadgroup` memory:
not in this plan. The feature works through the wrapper (Apple question 26, *measured*), but staging per tile
in `threadgroup` memory was slower than the plain pull at small n (decision 8), and MLX issue #4603 stays a
risk; it is proposed in the report only if (b)'s host time is above 10 % of the driver (*guessed*). Variant (b)
is judged second, after the pre-pass, against the form kept so far (decision 24).

**13. The stencil pre-pass.** A second kernel, one thread per pixel and plane copy, writes the base
`t0 (3, npix, ncopies)` as int32 and the nine normalised weights `w9 (9, npix, ncopies)` as float32 from the
same header (0.49e9 B a batch of 500, *derived*; times `nsym` with symmetry, so the batch of the pre-pass is
cut to `PROJ_BUDGET_B`). The pull then reads a candidate's base, compares, and reads three weights. The bits
equal the plain pull's, since both call one function with the same inputs, and that equality is a gate. It
is the variant judged first, against the plain pull (decision 24): decision 7's arithmetic gives it the
largest gain, though the measured pull no longer follows that arithmetic, so the gain is the verdict's to
find. If a rank-3 output is refused, the outputs are rank 2 (*measured* to work, K2 Phase 0).

**14. The seam: what lives where (maintainer).** Recommended:
- On the device from `new_accumulator` to `kill`: the two expanded grids of the half (28.1e6 B at n = 160), the
  kernel objects, the window's coefficients, and the batch in flight.
- A part process holds one `reconstructor` per state and half at a time, as `calc_3Drec` does; the next
  half's object is made after `kill_state_half_rec`. Three or six parts hold three or six such objects on the
  one GPU, each under 1e9 B with the pre-pass (*derived*: 0.49e9 + 78e6 + 4 x 28.1e6 B).
- In, per batch: the packed planes, the composite rows, the weights (and the tile lists). Out, once per half:
  the packed numerator and density (n/2 + 1, n, n) after `compress_exp` on the device (`mlx_take` through a
  host-made index map, a conjugation mask and the two floors): 81 x 160 x 160 x 12 B = 24.9e6 B (*derived*).
- The host waits once per batch, after it has packed the next batch, where `insert_all_slices` has its
  `taskwait`, and once at the end of the half. `insert_plane_oversamp` on the device is a batch of one plane;
  the batch entry is the addition `insert_planes_batch`, named in the mirror ledger for what
  `update_state_half_rec`'s loop does. `mlx_async_eval` submits; if it gives no measured gain on the driver the
  submission is a plain `mlx_eval` and the report says so.

**15. Host route, or refusal of `l_mlx = .false.` (maintainer).** Recommended: a host route. The host
`insert_plane_oversamp` is SIMPLE's loop in miniature (single precision, SIMPLE's colours under OpenMP),
with `compress_exp` and `sampl_dens_correct` in plain Fortran. Reasons: the driver's branch on `l_mlx` is what
integration edits; the off-state build can run it; it is the float32 comparator in SIMPLE's order that
decision 9 reports. It is never timed and no speed is claimed for it. Cost: about 250 lines (*guessed*) and
one more table for `scripts/check_toy_offstate.sh --exec`, which today compares the sub-suite `polarft_host`
only (the script gains the sub-suite `reconstructor_host`). The alternative: `new_accumulator` refuses
`l_mlx = .false.` with a message, as `projector` and `reconstructor_pcg` do; cheaper by that file and the
script's edit.

**16. What is kept: the graph form always, the pull on its gates, no speed rule between them (maintainer).**
The common rule keeps the graph form always; ruling B admits only a repeatable form on the GPU. Recommended:
- The graph form is kept always, as the reference of the tests and as the route of the CPU device. Its
  repeatability on the CPU device is *measured* (expected, item 11 of the check); if it fails there, the
  operation that differs is named and the run stops (section 7). On the GPU it is a test reference only, with
  its repeatability *measured* and reported.
- The pull is the deterministic GPU form the ruling asks for. It is kept when it passes the accuracy gate
  (decision 17), the repeatability gate (decision 22) and the identities (decisions 11, 13 and 20). No speed
  rule decides it against the graph form. Under ruling B the GPU has one admissible path, so the pull is the
  GPU's first path. A comparison with the graph form on the CPU device could not fail and would tell nothing:
  that route adds through the one sequential loop of `mlx_scatter_add` (item 11 of the check).
- The 30 % rule judges the pull's variants only (decision 24). Whether the insertion is worth a plan for
  SIMPLE is the maintainer's to decide from decision 24's table; the run draws no verdict on it.

**17. The accuracy reference under ruling B, and the cap (maintainer).** Recommended: at n = 160 a form is
judged against a host reference in double precision that deposits from the form's own float32 coordinates
(the probe's `coordinate_floor`, extended from the density to the numerator), error over the sum of the
absolute terms. Ceilings: 1e-5 on the seeded fixture (*guessed*: `PROBE_ERR_CAP`; a float32 sum of about 232
terms a voxel, *measured* mean of K2 Phase 5) and 1e-4 on the one-orientation fixture (*derived*: n e / 4 with
n = 6,509 terms a voxel, *measured*, and e = 6.0e-8). The tolerance is the error measured on seed 1 times 2
(`POLAR_ROW_FACTOR`'s rule) and must lie under the ceiling. The error against the double oracle is reported
beside the coordinates' floor (1.07e-4, *measured*, K2 Phase 5) and is not gated. If the one-orientation
fixture exceeds its ceiling, the register becomes a compensated sum (two more registers; determinism kept,
SIMPLE's order of bits given up) and the report says so: named in advance, not built otherwise. The basis of
the choice (run `mlxf_kernel_forms`, *measured*): the plain pull differed from the push by 1.8e-6 of a voxel's
|terms| at n = 64 on seed 1 (`FORMS_INSERT_TOL` = 3.6e-6, twice that), the size of the push's own spread
(1.4e-6 between two of its runs); compensation costs 2.8 % where a kernel is bound by other work and 14 %
where the sums are the kernel, for 50 to 90 times the accuracy. The pull adds about 6 terms a voxel and plane
behind a stencil test, so a compensated register would cost little; it stays the fallback because it
gives up the bits of SIMPLE's order (decision 9).

**18. Fixtures and seeds.** A new test module `mlxf_oracle_insert_fixture` takes the probe's fixture out of
`mlxf_bench_insert_probe` (`disc_pixels`, `fill_pixels`, `drop_ties`, `oracle_case`, `seeded_case`,
`oracle_insert`, `coordinate_floor`) with the seed as an argument, and adds symmetry copies and the packing of
planes for k <= 0. The probe imports it and keeps `PROBE_SEED` = 17; its exit is its own table again: 284,313,105
and 281,043,000 deposits (*exact*) and the errors to the printed digits. Since run `mlxf_kernel_forms` the
probe's `seeded_case` and `window_coefficients` are public and `mlxf_bench_kernel_forms.f90` imports them with
`probe_spec`, and the record `probe_case` lives in `mlxf_test_defs.f90`: a name that moves keeps its public
spelling, the kernel-forms bench's import is re-pointed in the same phase, and `bench_kernel_forms
suite=insert` reproduces its digests (n = 64, seed 1, `69E0B77A01359E6B`, *measured*) after the move. Small fixtures, in the fast gate: the
oracle's three planes at n = 8; 64 seeded planes at n = 16 with weights, both halves and two symmetry copies
(a twofold axis). Bench fixtures: n = 160, 1,000 seeded planes and 1,000 planes of one orientation. Seed 1
calibrates, seeds 2 and 3 judge (`ELEM_SEED_CALIBRATION`, `ELEM_SEEDS_JUDGED`). A pixel within
`PROJ_TIE_MARGIN` = 1e-4 of a half-integer coordinate carries no data in the toy's input and in the oracle's;
the count of such pixels is printed and not judged.

**19. The tolerance table.** Frozen as constants `REC_INS_*` in `mlxf_test_defs.f90` and in Progress before
seeds 2 and 3 run. Each row is per form and device, for the numerator and the density separately.

| Row | Compared | Ceiling | Origin of the ceiling |
|---|---|---|---|
| T1 | n = 8 and 16 against `oracle_grid_lattice` | 1e-5 | *guessed*; the probe *measured* 1.73e-6 and 6.52e-6 |
| T2 | n = 8 and 16 against the reference on the form's coordinates | 2e-6 | *guessed*: under 100 terms a voxel |
| T3 | n = 160 seeded, the same reference | 1e-5 | decision 17 |
| T4 | n = 160 one orientation, the same reference | 1e-4 | decision 17 |
| T5 | the packed half and the corrected volume against the oracle's | T1's | elements near a floor counted |
| T6 | the adjoint identity, relative | 1e-5 | *guessed*: float32 inner products of under 1e5 terms |

For T5 an element whose density is within a factor 1 +- 1e-3 of `COMPRESS_FLOOR` or `RHO_FLOOR` is counted,
not judged (*guessed* margin). The error against the double oracle at n = 160 is reported in every row's line.
A reference point for T3 and T4, not a bound (*measured*, run `mlxf_kernel_forms`, n = 64, seed 1): the plain
pull against the atomic push differed by 1.8e-6 of a voxel's |terms|, the push against itself by 1.4e-6; the
accumulation stays a plain float32 register in SIMPLE's order unless decision 17's fallback is taken.

**20. The identities.** (a) Adjoint: for seeded planes z and a seeded volume y at n = 8 and 16,
`<G z, y> = <z, W y>` with W the explicit matrix the tester builds in double precision from the public
`oracle_proj_matrix` on a grid too large to wrap, as the oracle's private `explicit_weights` does; numerator
(with its scale 4 and the weights) and density separately. (b) `compress_exp` against `lattice_compress` and
`sampl_dens_correct` against `oracle_grid_correct`, each from its own accumulators, including the oracles'
T3 fixture (the conjugate rule on the edge row, 7 voxels at n = 4 and 15 at n = 8). (c) The stored plane
h = 0 of the packed half is not a Hermitian half (the oracles' finding 8); no test assumes it is.
(d) `oracle_grid_selfcheck`'s 13 checks are asserted in a sub-suite `oracle_gridding`.

**21. Controls, each a planted violation shown to fail and then removed.** Weights not normalised; the scale
4 as 8; the conjugate for k > 0 omitted; the skip of negative h taps omitted; the voxel index in C order;
`rint` for `round`; a symmetry copy dropped; the halves exchanged; the conjugate rule of h = 0 in
`compress_exp` omitted; a batch that replaces the stored grid instead of adding to it; one window coefficient
moved by 1e-4; the scan cut to 5 x 5; the colour order reversed (for the gate of decision 11, not for
accuracy); a term that depends on the pass (for decision 22); a ledger line removed; a host file that imports
`mlxf`. The report lists each with the gate that caught it.

**22. Repeatability.** For each form and device: three insertions of the bench fixtures from a fresh object
in one process, and two invocations, compared through a 64-bit checksum of the grids' bit patterns that the
bench prints. One GPU configuration (this machine, `MLX_ENABLE_TF32=0`) and the frozen tile shape. Also
reported: whether the three tile shapes and the three batch splits give the same checksum (expected, decision
9), and the count of voxels that differ between two runs of the graph form on the GPU. The plant is decision
21's pass-dependent term.

**23. The bench.** `test=bench_reconstructor`, named-only, Release, `MLX_ENABLE_TF32=0`. Fixture: decision
18's at n = 160, two batches of 500. Unit: plane copies per second, and seconds per batch of 500. The
canonical driver is one half of `calc_3Drec`: from prepared planes on the host through `new_accumulator`, the
batches (packing, submission, wait), `compress_exp`, the copy of the packed accumulators to the host (in the
place of `write_raw_accum`) and `kill_state_half_rec`. Splits, judged on the driver and reported per part:
packing on the host, upload and submission, the insertion's evaluation, compression, the copy out, object
construction. Suites: `probe` (Phase 0), `sweep` (tile shapes, batch of the pre-pass), `accuracy`, `repeat`,
`driver`. Nine passes, the first three dropped, the median reported with the spread (the probe's `NREPEAT` and
`NTIMED`). Each timed run waits for a one-minute load of at most 4 and records `uptime`.

**24. The variants' verdict, the table for the maintainer, and the early stop (maintainer for the mark).**
- The ceiling of the variants is measured first, at the end of Phase 2: the driver with the kept pull against
  the driver with a null insertion that uploads the batch and returns the stored grids. If that ratio is below
  1.30 no variant can pass and Phase 3 is not entered.
- A variant passes when the driver time of the form kept so far is at least 1.30 times the variant's, in both
  invocations, at one process and at three processes read on the time from go to the last exit. Six processes
  are reported. The order: the stencil pre-pass against the plain pull; the tile lists against the form kept
  so far; then 4 x 8 x 8 and 4 x 4 x 4 against the form kept so far with the default tile. Each variant's
  configuration (the pre-pass's batch, the list's tile) is frozen in Progress before its verdict runs. A
  variant that does not pass is removed from the toy.
- The table, laid out without a verdict: the kept form's seconds per batch of 500 and plane copies per second
  on the canonical driver, alone and at 3 and 6 parts (total rate, rate per process, the time from go to the
  last exit), beside (a) the atomic kernel's seconds per batch *measured* in the same session, which is what
  determinism costs; (b) the graph form's on both devices; (c) SIMPLE's cost as decision 26 derives it,
  labelled derived and unmeasured.
- One line registered for the report, not a gate: the factor between the kept form's insertion split and
  the atomic kernel's seconds per batch. The estimate (revised 2026-11-26): 1.66 for the plain pull at n = 160
  (*derived* by run `mlxf_kernel_forms` from its measured 14.5 at n = 64 and 5.6 at n = 96; read, not judged,
  as that run left it). The draft's estimate from decision 7's arithmetic (about 27 for the plain pull, 6 with
  the pre-pass, 3.5 with the pre-pass and the tile lists, at the atomic kernel's 7.8e10 flop/s) is kept
  beside it as the refuted prediction it is at small n. The report says which estimate held at n = 160.
- The early stop, a stop for a ruling and never a silent end. The mark is 40 times the atomic kernel's seconds
  per batch *measured* in the session (1.5 s at 0.037 s): the cost of the batch on one SIMPLE thread as
  decision 26 derives it, above which the whole GPU inserts slower than one core by the only figures in hand.
  After Phase 2: if the plain pull's insertion split is above 180 times (40 x 4.5, the pre-pass's *derived*
  gain 27 / 6), no variant is built. After the pre-pass: if the best form is above 40 times, the tile lists and
  the tile shapes are not built. In both cases the run finishes the accuracy and repeatability gates of what
  is built, lays out this decision's table at one process, and stops (section 7). The marks stand as the
  maintainer's; the measured small-n factors (5.6 at n = 96, falling with n) put both far away, so the stop is
  not expected.

**25. Parts.** `scripts/run_parts.sh` with 1, 3 and 6 processes of `bench_reconstructor suite=driver`, 30, 10
and 5 threads, its memory guard on. Reported: the total rate, the rate per process, one process's footprint
and MLX's peak, the time from go to the last exit. Memory per part is reported and is never a reason to reject
a form.

**26. SIMPLE's cost.** No measured record of `insert_plane_oversamp` is in hand. *Derived* from the families
note's derived figures: 10,530 depositing pixels x 550 flop = 5.8e6 flop a plane; at about 1.9e9 flop/s a
thread, 3 ms a plane and 1.5 thread-seconds a batch of 500, 0.05 s on 30 threads if the colours' six parallel
loops per plane scaled perfectly, which nothing measured supports. The report prints the toy's rates beside
these figures with their origin and draws no ratio from them.

**27. The atomic kernel as speed reference.** `bench_insert_probe suite=probe` is run in the same session,
under the same load rule, on the same fixture, and its seconds per batch are set beside the pull's insertion
split. The factor is decision 24's registered line; a pull slower than the atomic kernel is not a failure
of a gate. The probe's
kernel sources and its printed table are not changed (decision 18 moves its fixture only).

**28. The mlx3D note's proposal 4: sizes that change per call go in an int32 input, not a template
(maintainer).** Recommended: yes, now *measured* (revised 2026-11-26): on the insertion probe's kernel and on
K2's gather, sizes in an int32 input of fewer than 8 elements gave the same bits and the same time per launch
as template integers, and a new value cost 3.05 / 2.62 ms against 42.7 / 42.0 ms as a template (run
`mlxf_kernel_forms`, suite `sizes`; MLX keys its kernel library by the source, never by the launch
configuration). So K6 does not measure the template form again: batches of 500, 250, 3 and 1 plane copies go
through one kernel object with `iparams`, and the workspace counts the kernel objects it builds and the
seconds of their first evaluations. Capacities need not be powers of two. The skill line for `mlxf-binding`
is run `mlxf_kernel_forms`'s proposal, which the report cites with K6's counts; the run edits no skill. Not
verified here: that inputs of another shape through the same object need no new object (Phase 0).

**29. The mlx3D note's proposal 5: `apply` with its own launch waits for a measured cost of rebuilding
(maintainer).** Recommended: wait. A new object of an existing source costs 2.6 to 3.1 ms at its first
evaluation (*measured*, run `mlxf_kernel_forms`), which is what an `apply` would save per configuration. K6
counts the kernel objects built per driver and the seconds spent building them. The proposal is raised again
only if that exceeds 1 % of the driver (*guessed*).

**30. No chained test with K8 (maintainer).** Item 8 of the check: the gridding accumulators are not what
`set_raw_accum` takes. Recommended: no chained test in this plan; the report says what the pull would need to
serve `reconstructor_pcg`'s scatter (the coordinate factor 2, the wrap in place of the halo, the scale 8, the
disc `nyq*nyq`) as a follow-up for the roadmap.

**31. Protected.** No oracle and no existing `mlxf_toy_*` file is edited, except
`mlxf_toy_seam_tester.f90`, which gains the new class's cycles and refusals and loses none of its checks.
`mlxf_bench_insert_probe.f90` changes only by decision 18. The run may add a row to the file table for a new
`src/test/toys/recon/mlxf_toy_reconstructor_*.f90` submodule it needs, with the reason in Progress and both ledgers
updated in the same step.

**32. Apple questions.** The run writes, and never sends: an amendment of question 12 (deterministic
scatter-add) with the measured cost of the pull against the atomic kernel; an entry on the repeatability of
`mlx_scatter_add` per device if Phase 0 measures something the documentation does not say; an entry on
contraction in a kernel's source (whether an explicit `fma` is honoured and whether `a * b + c` is contracted
in the mode mlx-c compiles in, beside question 21) if Phase 0's coordinate probe finds a difference. Question
26 already carries run `mlxf_kernel_forms`'s measurements and is not amended unless this run measures
something new of `threadgroup` memory (it plans no such measurement). A sorted fallback relies on no
stability of `mlx_argsort` (question 36). New entries start at the number after the last one Phase 0 finds
(37 at `ae7d623`).

**33. Time boxes.** Each phase has a box in minutes. At the box the run writes what is done and what is not,
and either finishes within a quarter of the box more or stops with the diagnosis. A box is never met by
loosening a gate.

### Defaults taken without a question

- One state, both halves, in the toy and in its fixtures.
- complex64 for the numerator on the device; float32 `(2, nvox)` if a complex64 input and output of 2,341,350
  elements is refused in Phase 0.
- The tile of the graph form is 50 planes; the run may change it for memory and records the value.
- The checksum of decision 22 is the 64-bit wrapping sum of the elements' bit patterns times their positions.
- Names of sub-suites: `reconstructor`, `reconstructor_n16`, `reconstructor_host`, `oracle_gridding`.
- The probe's fixture moves; the alternative, a second copy of it, is rejected as duplication.

### The choices that are the maintainer's

7 (the pull with the corrected arithmetic, its prediction withdrawn by the measured pull), 8 (the forms and
their order: the atomic push the fast reference, the pull the deterministic form measured at n = 160, staging
dropped, a sorted fallback with a persistent capacity), 9 (repeatability, not identity), 11
(the default tile; other shapes as variants), 14 (what resides, what crosses, where the host waits), 15 (a host
route), 16 (the graph form kept always, the pull kept on its gates, no speed rule between them), 17 (the
reference and its ceilings), 24 (the mark of the early stop, 40 times the atomic kernel's seconds per batch, and
the table from which the maintainer judges whether the insertion is worth a plan for SIMPLE), 28, 29, and 30 (no
chained test with K8). Each stands as recommended unless ruled otherwise before the go. Revised 2026-11-26
by run `mlxf_kernel_forms`: 7, 8, 12, 24 (the estimates), 28 (now measured) and 29.

## 4. Not in this plan

- Any change to `src/core/`, `src/defs/`, a skill, a rule of a policy, or SIMPLE. The toy and test policies
  gain only the lines that list the new toy, its sub-suites and its bench (Phase 5).
- The insertion of `reconstructor_pcg` on the padded lattice (decision 30), and a chained test with K8.
- `threadgroup` memory, `threadgroup_barrier` and `simd_sum` in a toy: staging measured slower (decision 8),
  lists in `threadgroup` memory not built (decision 12 (c)).
- The sorted form, unless decision 8's condition is met; the compensated register, unless decision 17's is;
  staging a plane's patch in `threadgroup` memory (measured slower, decision 8).
- The preparation of planes (`prep_imgs4rec`, `gen_fplane4rec`), several states, `insert_extra_poses`.
- The division by the density in the driver (item 5 of the check), `restore_base` and the regularisation.
- A box other than n = 160 in the bench. A measurement of SIMPLE. Production data.

## 5. Change types and gates

Every phase ends with: Debug and Release from scratch in hand-configured trees with `-DMLXF_WERROR=ON
-DFORTLS=OFF -DBUILD_TESTS=ON`, zero warnings; the fast gate in both; `scripts/check_tree.sh`;
`scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` on every touched Fortran file (the static gate
includes rank 2d's rules `publist` and `size`, the folders' `.inf` descriptions and the code-base map); and
the unit areas at the counts Phase 0 finds (at `ae7d623`, *measured*: core 214 to 216, array 193, ops 2,462,
fft 194, linalg 632, compile 63, fast 152, random 486, transforms 274, io 846, distributed 55, kernels 1,953;
rank 2g, K3, K4 and K5 may have changed them), with `unit_kernels` at Phase 0's count plus the checks this run
adds, the sum recorded per phase.

| Change | Gate beyond the common ones |
|---|---|
| A host file of the toy | imports no MLX name; line in both ledgers; compiles in the off-state project |
| The glue submodule | `mlxf` only inside its `#ifdef USE_MLX` branch; every stub returns "built without MLX" |
| A device module or submodule | imports no host or glue module but `mlxf_toy_device_work`; one `kill` frees all |
| A kernel source | row-major, 0-based indices stated in a comment; a status on a source that does not compile |
| A tester suite | both devices where the form runs on both; under 0.5 s or the reason in its registration |
| The pull | decisions 17 and 22 and the identities; no speed rule against the graph form (decision 16) |
| A variant of the pull | the plain pull's bits; decision 24's verdict; removed from the toy if it fails it |
| A tolerance or constant | in `mlxf_test_defs.f90` and in Progress before the seeds it judges |
| The bench | named-only; the fast gate's 13 entries and its bound of 38.74 s unchanged |
| A ledger | rule `mirror` or `seam` passes, and fails with a line removed |
| The fixture's move | the probe prints its K2 table again (decision 18) |
| The last phase | `scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`, |
| | `scripts/release_gate.sh --allow-dirty`, and the Release fast gate 10 times of 10 |

## 6. Acceptance

1. The toy `reconstructor` and `calc_3Drec` exist in the integration shape; both ledgers hold every public
   name; `seam` cycles `new_accumulator` and `kill` 100 times per backend with MLX's active memory returning
   to its start, and holds the refusals (a batch before `new_accumulator`, an odd box, rows that are not a
   rotation, a plane of another box, `l_mlx` on a build without MLX).
2. The graph form passes T1, T2, T5 and T6 on both devices on seeds 2 and 3, and T3 and T4 on both devices.
3. Decision 16's premise is measured: the graph form's repeatability on each device, with counts.
4. The pull passes T1 to T6 on the GPU, the batch-split and tile-shape identities of decisions 11 and 22, and
   repeatability over three repeats and two invocations. It is kept on these gates alone (decision 16).
5. The variants' ceiling and the plain pull's factor to the atomic kernel are in Progress before Phase 3 is
   entered, skipped, or ended by decision 24's early stop.
6. Each variant built (pre-pass, lists, tile shapes, in that order) has its verdict by decision 24 against the
   form kept so far, and its bits equal the plain pull's.
7. Every control of decision 21 is shown to fail and is removed.
8. Decision 24's table is laid out without a verdict: the kept form at 1, 3 and 6 processes with the splits,
   footprints and `uptime`, beside the atomic kernel's seconds per batch of the same session, the graph form's
   on both devices and SIMPLE's derived cost labelled as such; and the registered line, the measured factor
   beside the estimate.
9. Decisions 28 and 29 have their counts; the report cites run `mlxf_kernel_forms`'s proposed skill line
   with them.
10. The Apple questions of decision 32 are written. The families note's section 5 (family C), its section 8
    row K6 and the roadmap's item for K6 carry the results, the corrected premises (items 5, 8, 9 of the
    check) and the ruling's outcome; `doc/history/2026-11.md` has the batch.
11. The gates of section 5 pass at the last phase, and the report follows the how-to's order and ends with
    the commit message.

## 7. Common rules and stop conditions

- No file outside the table, apart from decision 31's rows. No tolerance, ceiling, margin, fixture or seed
  changed to pass. A failing gate is a diagnosis task.
- No form, key or member beyond those named here in the toy. Alternatives live in the bench.
- The oracle and the fixture module import no `mlxf` module and no toy module; the toy imports no oracle.
- A direct run on the GPU sets `MLX_ENABLE_TF32=0`. Timed runs are Release, alone on the machine, after the
  load rule of decision 23.
- A measurement is written into Progress in the turn it is made, with the command.
- The run writes with the editor tools. Git is read-only: nothing is committed or pushed.

**Stops:**
- a wrapper the plan uses is missing or refuses a call of decisions 8, 10 or 14;
- Phase 0 finds a premise of "The queue" changed in a way a decision depends on (a name taken, a ledger's
  format, the probe or the oracle changed), and the change is not a rename the run can follow;
- the kernel's coordinates do not equal the host's bit for bit and the fallback of decision 6 also fails;
- the graph form is not repeatable on the CPU device (decision 16), with the operation that differs named;
- a measured tolerance is above its ceiling on seed 1, after decision 17's named fallback where it applies;
- the pull fails repeatability, a batch-split identity or an accuracy gate, and two attempts at a diagnosis
  find no defect of the toy (the report then says what the sorted form would cost, from Phase 0's number);
- a kernel fails at evaluation for a reason that is not the source (a status with no message that names it);
- decision 24's early stop: the plain pull's insertion split is above 180 times the atomic kernel's seconds
  per batch of the same session, or the best form after the pre-pass is above 40 times; the run stops for a
  ruling with the table at one process, the gates of what is built passed;
- a process of `run_parts.sh` is refused by the memory guard at 3 processes;
- a change to `src/core/`, `src/defs/`, a rule of a policy or SIMPLE would be needed; SIMPLE at `28c753993`
  contradicts a decision; the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
toy imports no oracle and the oracle no toy; no SIMPLE source copied; tolerances frozen before the seeds they
judge; repeatability of every kept form; the 30 % rule for a second path; the ledgers hold every public name.

## 8. Phases

### Phase 0, the base, the queue's premises and the probes (box: 110 min)

Pin the base hash. Re-check the list of "The queue" and record each value. Build Debug and Release from
scratch and run every unit area and the fast gate; record the counts. Then the probes, in a suite `probe` of
the new bench (the file's first content), each with its number in Progress:
1. `mlx_scatter_add` on a collision fixture (the probe's seeded case at n = 16 and at n = 160, one batch):
   repeatability on each device over three runs and two invocations, complex64 updates accepted, seconds.
2. The coordinate bits (decision 6): a kernel with the header's `fma` form and one with the plain expression,
   against the host's two statements, on 1e6 seeded triples; counts of differing bits.
3. The kernel object's inputs (decisions 10 and 28; the int32 size input is measured, run
   `mlxf_kernel_forms`): a second call with inputs of another shape through the same object; a grid of (86,
   165, 165) with a threadgroup of (8, 8, 8); complex64 input and output of 2,341,350 elements.
4. The null walk (decision 8): a kernel of one thread per voxel that runs the 500 slab tests and writes the
   stored value, timed at n = 160, with and without tile lists.
5. `mlx_argsort` of 1.42e8 uint32 keys, seconds and peak memory, once.

Exit: the base is green and recorded; every premise of the queue is recorded as found; each probe has its
number or its refusal; the decisions that a probe changes (6's fallback, 8's early end, 10's padding, the
complex64 default) are settled in Progress before Phase 1.

### Phase 1, the class in the integration shape and the graph form (box: 270 min)

The records of decision 3. The fixture module (decision 18) and the probe's import of it, with the probe's
table printed again. The host class and driver, the glue with its stubs, the workspace with the graph form
(insertion, `compress_exp`, `sampl_dens_correct`), and the host route if decision 15 is ruled so. Both
ledgers, the off-state program, the sub-suite `seam`. The tester's suites on the small fixtures: T1, T2, T5,
T6, decision 20, and the controls of decision 21 that concern the rule. Tolerances measured on seed 1 on both
devices, frozen, then seeds 2 and 3. At n = 160 in the bench: T3 and T4 for the graph form on both devices,
its repeatability per device, and its driver's seconds per batch on both devices.

Exit: acceptance 1 to 3; the frozen tolerances in Progress; section 5's gates.

### Phase 2, the pull (box: 210 min)

The kernel of decision 10 with the plane walk Phase 0 chose, behind the same class and glue. The small
fixtures on the GPU against the frozen tolerances, the batch-split identity of decision 11, the remaining
controls of decision 21, then T3 and T4 at n = 160 and the repeatability gate of decision 22. The count of
voxels that differ from the host route and from the graph form, reported. Then, on the driver at one process:
the pull's splits, the atomic kernel's seconds per batch in the same session, the variants' ceiling against
the null insertion, and the factor of decision 24's registered line.

Exit: acceptance 4 and 5; the pull is kept on its gates, whatever its speed; section 5's gates. A failure of a
gate after two diagnoses is decision 8's condition for the sorted form, which is a stop with its estimated
cost, not a silent change of plan. A factor above 180 is decision 24's early stop.

### Phase 3, the pull's variants: the stencil pre-pass, tile lists, the tile shape (box: 210 min)

Not entered if the variants' ceiling is below 1.30. Each variant in decision 24's order behind a constant of
the workspace: built, held to the plain pull's bits on the small fixtures and at n = 160, its configuration
frozen in Progress, then timed on the driver against the form kept so far, at one process in both
invocations and, if it passes there, at three processes. A variant that does not pass is removed from the toy
in this phase, with its numbers kept in Progress. After the pre-pass the best form's factor to the atomic
kernel is checked against decision 24's mark of 40.

Exit: acceptance 6; the kept form named in Progress (pre-pass or not and its batch, lists or not, the tile
shape); no code of a rejected variant left in the tree; section 5's gates.

### Phase 4, the bench, the parts and the table (box: 210 min)

Suites `accuracy` and `repeat` on the kept form, seeds 2 and 3. Suite `driver` for the kept form and for the
graph form on both devices, two invocations each, then the kept form at 3 and 6 processes with
`run_parts.sh`. The probe's atomic kernel under the same load rule in the same session. The measurements of
decisions 28 and 29 (the kernel objects' counts and first evaluations). Decision 24's table and its
registered line, written with both estimates beside the measurement before the table is tidied.

Exit: acceptance 8 and 9; the table in Progress with both invocations' numbers and no verdict on the
insertion's worth; section 5's gates.

### Phase 5, the record (box: 60 min)

The Apple questions of decision 32. The families note, the roadmap's item, the history, the index, the toy
and test policies' lists, the folders' `.inf` files and `doc/code_base_map.md` for what was kept, and the
plan's Progress. The last-phase gates of section 5. The report in the how-to's order: what was
learned, what changed per phase, decisions under delegation, deviations, evidence, left open, the commit
message naming every new file.

Exit: acceptance 10 and 11.

### File table

| File | What | Phases |
|---|---|---|
| `src/test/toys/recon/mlxf_toy_reconstructor.f90` | new, host: the class, its host route if ruled | 1, 2 |
| `src/test/toys/recon/mlxf_toy_reconstructor_mlx.f90` | new, glue: `<name>_mlx` procedures and stubs | 1, 2, 3 |
| `src/test/toys/recon/mlxf_toy_reconstructor_workspace.f90` | new, device: the type, lifecycle, sources' header | 1, 2, 3 |
| `src/test/toys/recon/mlxf_toy_reconstructor_workspace_graph.f90` | new, device: graph insertion, compression, correction | 1 |
| `src/test/toys/recon/mlxf_toy_reconstructor_workspace_pull.f90` | new, device: the pull and its variants | 2, 3 |
| `src/test/toys/recon/mlxf_toy_matcher_3Drec.f90` | new, host: `calc_3Drec` and its steps | 1, 2 |
| `src/test/toys/recon/mlxf_toy_reconstructor_tester.f90` | new: the suites of decisions 19 to 22 | 1, 2, 3 |
| `src/test/toys/mlxf_toy_seam_tester.f90` | the new class's cycles and refusals in sub-suite `seam` | 1, 2 |
| `src/test/oracles/mlxf_oracle_insert_fixture.f90` | new: the probe's fixture, copies, packing, references | 1, 2 |
| `src/test/bench/mlxf_bench_reconstructor.f90` | new: `probe`, `sweep`, `accuracy`, `repeat`, `driver` | 0, 1, 2, 3, 4 |
| `src/test/bench/mlxf_bench_insert_probe.f90` | imports the fixture; nothing else | 1 |
| `src/test/bench/mlxf_bench_kernel_forms.f90` | its import of the probe's public names re-pointed if decision 18 moves them; nothing else | 1 |
| `src/test/framework/mlxf_test_defs.f90` | records of decision 3, `REC_INS_*`, form constants | 1, 2, 3, 4 |
| `src/test/framework/mlxf_test_registry.f90` | the bench in `BENCHES` and `NAMED_ONLY`; the suites of `kernels` | 0, 1, 2 |
| `src/test/toys/recon/recon.inf` | the folder's description: the gridding reconstructor and its driver | 1, 5 |
| `src/test/oracles/oracles.inf` | the folder's description: the insertion's fixture | 1 |
| `src/test/bench/bench.inf` | the folder's description: the new bench | 0, 5 |
| `doc/code_base_map.md` | regenerated by `scripts/generate_codeoverview.py` in each phase that adds or removes a Fortran file or edits an `.inf` (the static gate checks it) | 0, 1, 2, 3, 5 |
| `scripts/toy_mirror.txt` | header sentence for the files read; a line per public name | 1, 2, 3 |
| `scripts/toy_seam.txt` | a line per new toy file | 1, 2 |
| `test/offstate/mlxf_offstate_exec.f90` | asks `reconstructor` for the MLX backend; the host table if ruled | 1 |
| `test/offstate/CMakeLists.txt` | only if a non-toy file must be named | 1 |
| `scripts/check_toy_offstate.sh` | only with decision 15's host route: the second table | 1 |
| `doc/collaboration/apple_questions.md` | decision 32 | 5 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | family C, row K6, section 2a row C | 5 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | K6's item and decision 14's outcome | 5 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the batch, negative results | 5 |
| `doc/policies/toy_example_policy.md` | the new toy in the toys' list | 5 |
| `doc/policies/test_environment_policy.md` | the new sub-suites and the bench | 5 |
| `doc/implementation_notes/README.md` | the index | 5 |
| `doc/implementation_notes/completed/mlxf_kernel_k6_report.md` | new: the report | 5 |
| `doc/implementation_notes/planned/mlxf_kernel_k6.md` | Progress | 0, 1, 2, 3, 4, 5 |

## Progress

The run fills this section: per phase the dates and times, the base hash, what the queue's re-check found, each
probe's number, the frozen tolerances and configurations before the runs they judge, the tables, the rulings
taken under delegation, the deviations, and the planted violations with the gate that caught each.
