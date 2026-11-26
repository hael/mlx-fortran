# The review against mlx3D, and experiments on the ways of writing a kernel (run `mlxf_kernel_forms`, on the M5 Ultra)

Status, 2026-11-26: planned; decisions stand as recommended under the maintainer's go of 2026-11-26, open to his
review. Base: the commit that holds this plan; checked against `b2c43a4` (clean tree), with mlx3D read at `7101ec3`
(`~/src/mlx3D`), MLX read at `5c8989446` (`~/src/mlx`; the installed MLX is 0.32.4) and SIMPLE not read (nothing
here depends on SIMPLE's code; the polar layout is 2e's). Supersedes: none. Revises: the advisory note
[`mlxf_mlx3d_lessons.md`](mlxf_mlx3d_lessons.md) (its Phase 5). Depends on: run 2d (validated: no, planned) and run
2e (validated: no, planned), see "The queue". Roadmap rank 2f, decision 16.

## 1. Why

The maintainer ruled on 2026-11-26 (roadmap decision 16) that the developments be "carefully" reviewed against
mlx3D, "the highly similar work", with experiments on different ways of writing the kernels, before K3 to K7 are
ruled. Every kernel in the tree today is one thread per output, reading global memory, with sizes as template
constants or read from shapes; none uses `threadgroup` memory, a SIMD-group function or a pass sized on the
device. mlx3D's production kernels use all of these. The record has three numbers that bound what any new form
can do for the kernels we already have (*measured*, K1, K2, K8 reports): the fused tail is about 0.14 s of K1's
0.628 s pass, the fused gather 0.006 s of K2's 0.0397 s pass, and removing every wait from K8's solve gains 0.3
to 0.5 %. So no form tried here can change a toy's default under the 30 % rule; what the run can change is which
form K3 to K7 write first, and which of the note's proposals rest on measurement instead of on mlx3D's practice.

## 2. Contract

- **Tests only, plus documents.** The run adds one named-only benchmark, `test=bench_kernel_forms`, and makes
  the current kernels' specs reachable from it. No file under `src/core/` or `src/defs/` changes. No toy's
  default, kernel source, launch or result changes.
- **The off-state invariant.** A program that does not name `bench_kernel_forms` runs none of the new code.
  The toys' digest lines (K1's 25, K2's 16, as 2e leaves them) are equal before and after every phase, and the
  unit areas keep the counts 2e leaves.
- **The current form is the reference.** Each experiment sets the kernel that is in the tree, built from the
  toy's own spec function (decision 4), beside one or more alternatives on the same inputs, in the same process.
- **What is kept.** A measured form is a recorded result and a preference for the K plans, never a toy change in
  this run (decision 3). The alternative kernels stay in the benchmark as the record's reproducers.

### What the check found (2026-11-26, at `b2c43a4`; mlx3D at `7101ec3`)

**Our kernels.**

- **K1's fused tail** (`mlxf_toy_polarft_workspace_tail.f90`, `tail_source`, `tail_spec`): one thread per pair,
  grid `[rt bt, 1, 1]`, threadgroup `POLARFT_TAIL_TG` = 64, three serial sweeps over the pair's row of
  `nrots` = 364 floats (pftsz 182) at `raw[e nrots + i]`, a Kahan sum of the weights, `metal::precise::exp`, the
  first minimum kept by strict comparison. Sizes come from `raw_shape`, constants from a 5-element input `par`
  (in Metal's `constant` space, policy section 12). One object per tile shape, built in
  `polarft_workspace_new_tail`; the rows variant built on first use. Tiles are queued with `mlx_async_eval`
  (`mlxf_toy_polarft_workspace_score.f90`), one wait per block at collection. Neighbouring threads read rows
  1,456 B apart: no coalescing within a SIMD group. On a canonical tile of 16,000 pairs the kernel takes 0.166
  to 0.173 ms (*measured*, K1 P10): 23.3e6 B of rows read three times in 0.17 ms is about 410 GB/s if nothing
  is cached (*derived*). The tail's spec functions are private to the submodule.
- **K2's fused gather** (`mlxf_toy_projector_workspace.f90`, `GATHER_SOURCE`, `gather_spec`, `fused_tile`): one
  thread per (point, direction), grid `[npts, tn, 1]`, threadgroup `[min(tg, npts), 1, 1]`, 27 reads of a
  `complex64_t` cube per sample at data-dependent positions, the window's weights computed per sample. Four
  template integers (`E`, `L`, `NPTS`, `PADS3`), so a new box or point count is a new Metal source. The rotation
  row of a direction is the one operand a threadgroup shares, 24 B. One wait per tile (`mlx_eval` in
  `fused_tile`); the canonical fused configuration is one tile of 2,500 directions. `gather_spec` is private.
  The projection is 0.006 s of the 0.0397 s pass (*measured*): a free gather makes the pass at most 1.18 times
  faster (*derived*: 0.0397 / 0.0337).
- **The Fourier-Bessel shift maps' device form** (`mlxf_toy_polarft_workspace_shiftmap.f90`): no custom kernel;
  `mlx_take`, `mlx_take_along_dim`, `matmul`, `mlx_irfft`, `mlx_fft`, sums and compiled functions, one
  synchronisation per tile for the cutoff decisions. **differs** from this plan's first framing: there is no kernel
  form to set beside another here. The maps are 2e's to re-layout and K4's to rewrite; this run leaves them.
- **The insertion probe** (`mlxf_bench_insert_probe.f90`, `probe_spec`): one thread per (pixel, plane), grid
  `[npix, nb, 1]`, threadgroup 256, five template integers, `atomic_outputs` with `init_value` 0, 27 deposits of
  three floats each. 0.037 s per batch of 500 planes at n = 160 against 0.0042 s for plain additions (*measured*,
  K2). `probe_spec` is private.
- **K8's graph PCG** (`mlxf_toy_reconstructor_pcg_workspace.f90`): no custom kernel; inner products as n² float32
  line sums (`line_dots`) added in double on the host; one wait per iteration of 0.17 ms; a free pointwise kernel
  bounds the gain at 1.13 to 1.19 and removing the waits at 0.3 to 0.5 % (*measured*, K8). Nothing to try here
  that K8 has not measured out.
- **The wrapper** (`src/core/fast/mlxf_fast.f90`; binding contract section 12): the launch configuration
  (grid, threadgroup, output shapes, templates, `init_value`) belongs to the kernel object, built by `config_of`
  in `new`; mlx-c's `mlx_fast_metal_kernel_apply` takes the configuration separately. `header`, `atomic_outputs`,
  `ensure_row_contiguous`, template dtypes, integers and booleans are exposed; the math mode is not (Apple
  question 21). A new object with the same source costs 0.2 ms; a new source 48.7 to 60 ms at its first
  evaluation (*measured*, parity Phase 10, K1). The policy says a `threadgroup` array with
  `threadgroup_barrier` "builds and gives correct results" (a 64-element group sum, Apple question 26). **differs:**
  no source of that probe is in the tree (`rg "threadgroup [a-z]|threadgroup_barrier|simd_" src/ test/` finds
  none), which is K7's finding 14 too; the claim is unreproducible today.
- **MLX's cache** (`mlx/backend/metal/custom_kernel.cpp`, `CustomKernel::eval_gpu`, read at `5c8989446`): the
  library is keyed by the kernel's name, the hash of the generated source and the compile options; the grid,
  threadgroup and output shapes are not in the key; templates and input dtypes are in the source. So a new grid
  never recompiles and a new template value always does. Dispatch is `dispatch_threads` (the grid counts
  threads, and a partial last group is allowed). The attributes `thread_index_in_simdgroup`,
  `simdgroup_index_in_threadgroup` and `threads_per_simdgroup` are recognised (`mlx/backend/common/custom_kernel.cpp`).

**mlx3D's kernels** (`src/mlx3d`, every `mx.fast.metal_kernel`: `splatting/rasterize.py` 3, `splatting/tiles.py`
2, `splatting/fast.py` 4, `ops/knn.py` 1, `renderer/rasterizer.py` 1, `nn/fused_mlp.py` 1).

- **Launch.** Kernel objects are module-level and built once; grid, threadgroup and output shapes are passed per
  call (`fast.py` changes the output shapes with its capacity). Threadgroups are 256 threads (`16 x 16` for
  screen tiles, `min(256, N)` for per-object kernels). No kernel uses `template=`, `header=` or
  `ensure_row_contiguous`; every size is in an int32 input (`params` or `iparams`), every float constant in a
  float32 input (`fparams`), each built per call from host values.
- **Threadgroup memory.** `rasterize.py` (forward, backward, depth), `fast.py` (`_RASTER_FAST_SRC`) and
  `ops/knn.py` stage batches of 256 records in `threadgroup` arrays between two `threadgroup_barrier`s; inactive
  threads keep looping so that every thread reaches every barrier. **differs** from the session's first check:
  `renderer/rasterizer.py` declares no `threadgroup` array; its mesh kernel reads each face of the
  tile's range from global memory per pixel. That is mlx3D's one tile kernel without staging.
- **SIMD-group functions.** None in any kernel. The only mention is the header of `rasterize.py`: a backward with
  `simd_sum` and one atomic per 32 lanes was "~3% slower" (their claim, no benchmark in the repository).
  **differs** from the note's section 4, which takes mlx3D as evidence for K5's `simd_sum` tree: mlx3D gives
  evidence for `threadgroup` memory only.
- **Atomics.** The training backward adds gradients with `atomic_fetch_add_explicit` on `atomic_outputs=True`,
  `init_value=0`: our probe's form. Their gradient test allows 1e-5 for "atomic-add ordering noise"
  (`tests/test_tiles_fast_binning.py`).
- **Register accumulation and small-K selection.** `knn.py` keeps `MAX_K` = 8 best in register arrays by
  insertion, strict comparison and the lower index on equal distance, candidates streamed through
  `threadgroup` memory; above K = 8 or off 3-D it falls back to `argpartition` plus `argsort` of the K, chunked
  at 4,096 queries. The note's P4 holds.
- **Host waits.** **differs** in part from the note's P3. `fast.py` holds no wait inside the pass but one at its
  end (`mx.eval(image, final_T, total)` then `total.item()`), and one more on the first frame to size the
  capacity; it repeats the pass on overflow. The training path waits mid-pass (`tiles.py`, `bin_gaussians`:
  `int(counts.sum().item())`), and `rasterize.py`'s `_rasterize_core` reads four sizes back with `.item()`
  inside the custom function. P3 is the viewer's path, not mlx3D's general practice.
- **Stability of the sort.** P2 relies on `mx.argsort` being stable; mlx3D guards it with a test
  (`tests/test_splatting_fast.py`, `test_argsort_is_stable`, 200,000 keys). Our policy (section 10) says MLX
  documents no stability. The "~2.5x faster binning" is their docstring's claim.
- **Fused per-object work.** `_GEOMETRY_SRC` fuses about 60 element-wise operations; their tutorial gives 3.3 ms
  to 0.4 ms for 200,000 Gaussians on an M1 Pro (their measurement). The note's P5 holds.
- **A negative result the note omits.** `nn/fused_mlp.py`: a per-thread fused MLP (one thread per row, layers in
  registers) is *slower* than MLX's matrix products; "a naive fused matvec doesn't exploit the GPU's matrix
  hardware the way a tiled GEMM does" (their header). It bears on K3's candidate B, a per-thread product kernel.
- **Other patterns.** Vector loads by casting device pointers (`float2`, `float4`, `half4`) in `fast.py`;
  `metal::exp` (not `precise`) everywhere; half-precision colours (outside our precision rule).
- **How they test.** A/B against a kept reference path by a module flag (`_USE_FAST_BIN`), bit-identical images
  where the arithmetic order is the same and fixed bounds otherwise (PSNR above 60 dB, 1e-5 on gradients); a
  test that guards an MLX behaviour they rely on. No double-precision oracle, no repeatability gate, no
  multi-process timing.
- **How they benchmark.** `examples/benchmark.py`: mean of 10 calls after 3 warm-ups, no spread, one process;
  `docs/benchmarks.md` and `docs/tutorials/fast_rendering.md` report single numbers on an M1 Pro (the fast
  renderer 1.48 to 3.72 times the training path). None of their numbers is a measurement of ours.

**What that predicts for ours** (each tested below or recorded as derived only).

| Our kernel | Nearest mlx3D pattern | What differs | Prediction |
| --- | --- | --- | --- |
| K1 tail | P5 (fused per-object), with K-free reductions | rows read one thread per pair, uncoalesced; serial sums | a SIMD group per pair reads coalesced and reduces with `simd_*`; kernel faster by an unknown factor; the pass at most 1.28 times faster (*derived*: 0.628 / 0.49) |
| K2 gather | P5 | template sizes; no shared operand worth staging | staging cannot help (*derived*: 24 B shared per group); sizes in an input cost nothing per launch (*guessed*) and save a compile per new size (*measured* 48.7 to 60 ms); pass at most 1.18 times faster |
| insertion probe | the training backward (atomics), P1 (pull) | push with atomics, not repeatable | a pull is repeatable by construction; its speed against the push is unknown at any n |
| K8 PCG | none | graph only | nothing to try (*measured* bounds) |
| shift maps | none | graph only | left to 2e and K4 |

## 3. Decisions and rulings

Numbers are never reused. Each stands as recommended under the maintainer's go of 2026-11-26, open to his review.

1. (2026-11-26, recommended) **What is reviewed.** Our six items of section 2 against mlx3D's twelve kernels and
   their Python, tests, benchmarks and documents, as the check above records. Phase 5 writes the result into the
   lessons note. Reason: this plan's first list, all of it read.

2. (2026-11-26, recommended) **Which experiments run, and which stay derived.** Six suites, one per question:
   - `probe`: `threadgroup` memory and SIMD-group functions through the wrapper (answers Apple question 26);
   - `tail`: K1's tail as it is (T0), with one SIMD group per pair (T1), and T0 with a plain sum (T2);
     candidates (b) and (g);
   - `reduce`: a K5-shaped reduction, serial per thread (R0), serial compensated (R1), threadgroup tree with
     `simd_sum` (R2), MLX's graph `sum` (R3); candidates (b) and (g);
   - `sizes`: K2's gather and the insertion kernel with template sizes (G0, today's) and with an int32 input
     (G1); candidate (c);
   - `select`: K best of a score table, by K rounds of `maxloc` (E0), `mlx_argpartition` with a tie repair
     (E1), one thread per particle with K in registers (E2), one SIMD group per particle (E3); candidate (e);
   - `insert`: at small n, the probe's atomic push (D0), a pull with one thread per voxel reading planes from
     global memory (D1), the same pull with each plane's terms staged in `threadgroup` memory (D2);
     candidates (d) and (a);
   - `waits`: a two-stage pass with a data-dependent count, a wait per tile (F0) against a persistent capacity
     with a sentinel and one wait per pass (F1); candidate (f).
   Not run, recorded as derived in Phase 5: (a) on K1's tail and K2's gather (no operand shared within a
   threadgroup above 24 B); (f) on K1, K2 and K8 (K8 measured 0.3 to 0.5 %; K1 waits once per block; K2's four
   waits are at most 0.7 ms of 39.7, 1.7 %, *derived* at 0.17 ms a wait). Reason: run each candidate where its
   mechanism exists, and nowhere its effect is already bounded below what can be resolved.

3. (2026-11-26, recommended) **The verdict is a form preference, judged on the kernel, and changes no toy.** The
   driver-level ceilings (1.28 for any tail, 1.18 for any gather, *derived* above) are below the 30 % rule, so no
   alternative can be kept in a toy; the K plans write new kernels and judge them on their own drivers. A form
   is **preferred** when the median of five interleaved pair ratios (current time over alternative time) is at
   least 1.30 with at least four of five at or above it, at one process, and, for `tail` only, the ratio from go
   to the last exit is at least 1.0 at 6 processes. A form is **equivalent** when the median lies in 0.95 to
   1.05; **worse** below 0.95; **inconclusive** otherwise. No narrow exception to "no default changes" is argued:
   none is admissible under the rule.

4. (2026-11-26, recommended) **The current kernel enters the bench through the toy's own spec.** `tail_spec`,
   `gather_spec` and `probe_spec` become public module procedures of their modules (`tail_spec` with its
   interface in `mlxf_toy_polarft_workspace`), each an addition in `scripts/toy_mirror.txt` with the reason
   "the kernel-forms bench builds the current form". The bench builds T0, G0 and D0 from them and never holds a
   copy of a current source. Alternative: a verbatim copy in the bench with a bit-identity gate against the toy;
   rejected because the copy can drift and the gate needs the toy's whole driver.

5. (2026-11-26, recommended) **Agreement before any timing.** Each alternative is checked against the current
   form on the same inputs before it is timed:
   - bit for bit where the arithmetic order is the same: T1's and T2's distances and first minima, G1 against
     G0, E0 to E3 against each other and against the host's first-maximum rule, F1 against F0;
   - otherwise within a tolerance frozen on seed 1 on the GPU before seeds 2 and 3 are judged: T1 and T2 draws
     within `POLARFT_TAIL_ROT_BLK` = 5 differing rotations per 64,000 pairs against T0 (*measured*, K1, frozen)
     and within K1's oracle bounds against `mlxf_oracle_polar` on the device's rows; R0 to R3 against a double
     sum on the host (`FORMS_REDUCE_TOL`, new); D1 and D2 against D0 (`FORMS_INSERT_TOL`, new);
   - each form is bit-repeatable over 3 runs in one process and 2 invocations, except D0 (atomics, *measured*
     not repeatable), whose spread is recorded instead.
   An alternative that fails agreement is recorded as failed and not timed. Reason: the house rule, and K2's
   lesson that a control checked on its own data passes too easily.

6. (2026-11-26, recommended) **The timing protocol** (K1's decisions 15 to 17 and its R1 lesson). Release, one
   executable for all forms, the form by key; before each suite a warm-up evaluation of every form; per pair the
   current then the alternative, then the next pair in the opposite order; five pairs, each a median of 5 timed
   evaluations; two invocations. An A-A control (the current form against itself, three pairs) runs first in each
   suite and its spread is the suite's noise floor, recorded; a verdict whose margin is inside twice that floor is
   **inconclusive**. Every timed step waits for a one-minute load of at most 4 and records `uptime`. `tail` runs
   also as 3 and 6 processes with `scripts/run_parts.sh` (`RUN_PARTS_BENCH=kernel_forms`,
   `RUN_PARTS_SUITE=tail`), each part timing 40 canonical tiles, the rate read from go to the last exit and each
   part's MLX peak reported. Nothing else is built or run while a step is timed.

7. (2026-11-26, recommended) **The probe comes first and answers Apple question 26.** Suite `probe`, on the GPU:
   (a) a group sum of float32 values that are small integers (exact in any order) through a `threadgroup` array
   and barriers, for groups of 32, 64, 256 and 1,024 threads; (b) the same with `simd_sum`, `simd_min`,
   `simd_prefix_inclusive_sum` and `simd_shuffle` on 32 lanes, with `thread_index_in_simdgroup` and
   `simdgroup_index_in_threadgroup`; (c) a non-integer group sum in a fixed tree, bit-repeatable over 3 runs and 2
   invocations; (d) the largest `threadgroup` array that builds, by doubling from 4,096 B to 65,536 B, the first
   refusal recorded with its status and message. Answers: exact (a, b), repeatable (c), the limit (d). The
   question's entry gets the source's path and the numbers; a refusal or a wrong sum becomes a stop for the
   suites that need the feature (`tail` T1, `reduce` R2, `select` E3, `insert` D2), not for the others.

8. (2026-11-26, recommended) **The tail's forms.** On 40 canonical tiles of seeded rows (K1's P10 inputs:
   16,000 pairs a tile, nrots 364, seeds 1 to 3), entries only (the rows variant is not timed):
   - T0: `tail_spec(spec, .false.)`, the kernel K1 kept;
   - T1: one SIMD group of 32 lanes per pair, grid `[32 rt bt, 1, 1]`, threadgroup 64 (two pairs); each lane
     strides the row by 32; the minimum by `simd_min` then the lowest lane holding it (first index); W by lane
     partials, then `simd_sum`; the draw by a lane-ordered `simd_prefix_inclusive_sum` over successive blocks of
     32 rotations, the first rotation at or above the target by `simd_ballot` or a lane minimum; no lane returns
     early (lanes past the end hold zeros);
   - T2: T0's source with the compensation removed (`s += y`).
   Hypotheses, frozen: T1 is preferred (*guessed*: coalesced reads, T0 at about 410 GB/s *derived*); T2 is
   equivalent in time (*guessed*: the tail is bound by reads, not by four flops a term) and within the rotation
   bound. If T1 is preferred, K7's pair stage (F1) and K4's per-pair reductions are written a SIMD group per pair;
   if not, one thread per pair stays the house form. If T2 is equivalent in time, compensated sums stay the house
   default (they cost nothing); if T2 is faster by more than 5 % and within bounds, plain sums are allowed where a
   plan's bound holds.

9. (2026-11-26, recommended) **The reduction's forms (K5's shape).** 2,000 evaluations, each 23 sums over 6,000
   float32 terms that are products of two seeded inputs (*guessed* from K5's check, finding 3: 23 sums per
   evaluation over about 6,000 pixels; Phase 0 re-reads the K5 draft and records the shape it names):
   - R0: one thread per evaluation, 23 register accumulators, the terms in index order;
   - R1: R0 with a Kahan sum per accumulator;
   - R2: one threadgroup of 256 threads per evaluation; per-thread partials over a fixed stride, `simd_sum` per
     SIMD group, then the 8 SIMD sums added in index order by thread 0 from a `threadgroup` array;
   - R3: the graph: the product, `sum` over the term dimension (MLX's reduction), evaluated.
   Hypotheses, frozen: R2 is preferred over R0 (*derived*: R0 launches 2,000 threads, below what fills the GPU;
   R2 launches 512,000); R2 is preferred over R3 (*guessed*); R0 and R2 are bit-repeatable; R1 is equivalent to
   R0 in time and its error against the double sum is at most a tenth of R0's (*guessed*). If R2 is preferred,
   K5's fused objective is written as R2 (the note's section 4 form) and K6's per-voxel sums keep one owner per
   voxel; if R3 is within 1.30 of R2, K5's graph form is its only form until its own ceiling says otherwise.

10. (2026-11-26, recommended) **Sizes in an input against template constants.** On K2's gather at the
    canonical fused configuration (2,500 directions, the npts of 2e's bench, both parities) and on the insertion
    kernel at n = 64:
    - G0: today's spec, the sizes as template integers;
    - G1: the same source with the sizes read from an int32 input of 4 (gather) or 5 (insertion) elements, in
      `constant` space (fewer than 8 elements, policy section 12).
    Measured: the per-launch time (protocol of decision 6); for 8 distinct values of `npts`, the first evaluation
    of each form (G0 compiles 8 sources, G1 one source and 8 objects), in a fresh process each, twice. Hypotheses,
    frozen: G1 is equivalent per launch (*guessed*), G0's first evaluation per new value is at least 40 ms
    (*measured* 48.7 to 60 ms per new source) and G1's at most 1 ms (*measured* 0.2 ms per object). If both hold,
    the note's proposal 4 is measured: Phase 5 proposes the line for the `mlxf-binding` skill ("sizes that
    change per call are an int32 input; templates only for constants of a run") and K3's candidate B and K6 take
    it; if G1 is worse than 0.95, templates stay for sizes of hot kernels whose value set is bounded, and the
    report gives the factor.

11. (2026-11-26, recommended) **Small-K selection.** A float32 table of 10,000 references by 1,024 particles (one
    half at K7's `2500_4` plan, *derived* in K7's decision 15), seeded, with 1 % of the columns given planted
    ties at the K-th place and at the first; K = 3 and K = 10 (SIMPLE's `npeaks` and `npeaks_inpl`, *exact*, K7):
    - E0: K rounds of `maxloc(table, dim=1)` and the chosen entry set to a sentinel by position (K7's decision 14
      graph form);
    - E1: `mlx_argpartition` at the K-th, the K-th value, a repair of the boundary ties by a cumulative count of
      the equals in index order, `mlx_argsort` of the K kept (K7's alternative);
    - E2: one thread per particle scanning its column in index order, K best in registers by insertion with
      strict comparison (K7's F2, mlx3D's P4 without staging);
    - E3: one SIMD group per particle, each lane keeping K over a strided part of the column, then a merge over
      the 32 lists by lane order with ties to the lower index.
    The gate is exact: the K indices and values equal the host's first-maximum rule on every column. Hypotheses,
    frozen: E1 without the repair fails the gate on the planted ties (*derived*, K7 finding 13); E2 is preferred
    over E0 at K = 10 (*guessed*); E3 is preferred over E2 (*guessed*: E2's reads are 40,000 B apart between
    threads). Whatever wins changes at most 4.5 % of K7's pass (*derived*, K7 finding 16): the result decides
    which form K7 builds first and whether its Phase 3 measurement of E1 is still needed, not whether a
    reduction is worth a kernel.

12. (2026-11-26, recommended) **The insertion at small n: pull against push, and staging.** The probe's deposit
    rule, n = 64, 500 seeded planes (one batch, `MAXIMGBATCHSZ`), and the same at n = 96 to read the scaling:
    - D0: the probe's atomic kernel (`probe_spec(.true.)`), today's form;
    - D1: one thread per voxel, voxel tiles of 8 x 8 x 8 (one threadgroup of 512 each); for each plane in batch
      order a test of the plane's slab against the tile's centre that all threads of the group take alike, then
      each voxel's projection on the plane and a scan of the 6 x 6 pixel box, keeping a pixel whose own stencil
      covers the voxel (the probe's rule, its coordinate expression in a shared `header`), the terms added in
      registers in plane order then scan order, one write per voxel at the end;
    - D2: D1 with each reaching plane's needed pixel patch (the box covering the tile's projection) loaded once
      into a `threadgroup` array between barriers.
    `FORMS_INSERT_TOL` is twice the largest difference of D1 from D0, relative to the sum of a voxel's |terms|,
    on seed 1 (*measured* when taken), judged on seeds 2 and 3; D2 must equal D1 bit for bit (same order).
    Hypotheses, frozen: D1 and D2 are bit-repeatable (*derived*: one owner per voxel, fixed order); D1 is at most
    3 times slower than D0 at n = 64 (*guessed*); D2 is preferred over D1 (*guessed*). Read, not judged: the
    factor D1/D0 at n = 64 and 96, extrapolated to n = 160 by the walk's n³ and the push's n² terms (*derived*
    rule written in Progress before the n = 96 run). The result feeds K6's decision 8 (the order of its forms) and
    decision 13 (the pre-pass): K6 measures the pull at n = 160 on its own gates; this run does not.

13. (2026-11-26, recommended) **No wait for a data-dependent size.** A two-stage pass over 40 tiles, each tile a
    product of K3's list shape (a `matmul` of 250 by 366 by 64, *derived* from K3's `rt` 250, 2 x 183 bins and
    `bt` 64), a mask of about 30 % of its pairs (seeded), the count, the listed pairs compacted by `mlx_cumsum`
    of the mask and `mlx_scatter`, then a sum per listed pair:
    - F0: the count read to the host per tile (`mlx_to`) and the buffer allocated at that size;
    - F1: a persistent buffer of a fixed capacity (the largest count of seed 1 times 1.25), the tail masked by a
      sentinel with `merge` against the count as a 0-d device array, tiles queued with `mlx_async_eval`, the
      counts checked after the pass's one wait, an overflow redoing the pass (mlx3D's `fast.py` form).
    Equality is bit for bit on the listed sums. Hypothesis, frozen: F1 is preferred over F0 (*guessed*: each wait
    drains the queue). If preferred, K3's candidate B and K6's sorted form size their buffers by F1; if
    equivalent, the K plans may wait per tile; Phase 5 records the cost of a wait measured inside a busy queue
    beside K8's 0.17 ms measured on an idle one.

14. (2026-11-26, recommended) **Tolerances.** New constants in `src/test/framework/mlxf_test_defs.f90`, each
    measured on seed 1 on the GPU, written in Progress with its evidence before seeds 2 and 3 run, never moved:
    `FORMS_REDUCE_TOL` (twice the largest error of R0 to R3 against the double sum on seed 1, above 2^-23 of the
    sum of |terms|) and `FORMS_INSERT_TOL` (decision 12). K1's `POLARFT_TAIL_ROW_TOL`, `POLARFT_TAIL_ROT_BLK`
    and oracle bounds are used as frozen. The bench imports oracles (`mlxf_oracle_polar`, `mlxf_oracle_gridding`
    for the probe's deposit rule); no toy imports an oracle.

15. (2026-11-26, recommended) **Every gate has a planted violation,** made in a patched copy built apart, shown
    to fail its gate, and removed: T1 skipping the last rotation; T1 with the first-index rule inverted (the last
    minimal lane); R2 without its barrier (run three times; if it never fails, recorded as "could not fail" and
    replaced by a wrong order of the SIMD sums, which fails repeatability against R2); G1 with two size entries
    swapped; E2 with `<=` for `<`; E1 without the repair; D1 dropping the conjugate pixel; D2 without its second
    barrier; F1 with the sentinel mask one short; the probe's group sum without its barrier; a ledger line of
    decision 4 removed (rule `mirror`); `kernel_forms` missing from `BENCHES` (`scripts/check_test_registry.py`).

16. (2026-11-26, recommended) **The outputs.** A table per suite in Progress and in the report (forms, times with
    their A-A floor, ratios, agreement, repeatability, peak memory); the lessons note revised (decision 17); the
    list of K3 to K7 decisions each result changes, written in the report only (the K plans are not edited);
    Apple question 26 updated and a new numbered entry (from 32) for each new finding about MLX or mlx-c.

17. (2026-11-26, recommended) **The lessons note is revised, not rewritten.** Its status line becomes "reviewed
    and measured by run `mlxf_kernel_forms`, <date>"; each **differs** of section 2 is corrected in place with
    the file and procedure; a section "What was measured" holds the six tables' verdicts; its proposed decisions
    1 to 5 each gain a line: measured, derived, or still a proposal, and which K plan owns it.

18. (2026-11-26, recommended) **The bench's shape.** `src/test/bench/mlxf_bench_kernel_forms.f90`, module
    `mlxf_bench_kernel_forms`, entry `run_bench_kernel_forms(mode, found)`, suites by `suite=`, the form by
    `form=`, a key a suite does not read stops it (K2's rule); the GPU only, refused with a message on the CPU
    device. Kernel sources are parameters built from pieces as the toys build theirs. If the file passes 700
    lines, the sources move to `src/test/bench/mlxf_bench_kernel_forms_src.f90` (module of constants and spec
    functions) in the same phase.

Defaults taken without a question: suite and form names as in decision 2; `FORMS_` as the constants' prefix;
threadgroup 64 for T1 (K1's measured indifference), 256 for R2 and E3; seeds 1, 2, 3; capacity factor 1.25
(mlx3D's); the n = 96 point of decision 12.

## 4. Not in this plan

- Any change of a toy's default, kernel source, launch configuration or result; any edit of the K3 to K7 plans
  (the run lists their revisions); K1's, K2's or K8's verdicts reopened.
- Files under `src/core/`, `src/defs/`, `test/`, `scripts/` except `scripts/toy_mirror.txt`; the
  wrapper's design (an `apply` with its own launch stays the note's proposal 5, "wait": decision 10 measures the
  cost it would save).
- The shift maps' device form (2e and K4), the PCG solve (K8 measured it out), the insertion at n = 160 (K6).
- Half precision, `custom_function` and `custom_vjp` (the note's section 6 stands), the relaxed math mode (not
  reachable through mlx-c, Apple question 21), vector loads by pointer casts (no kernel of ours reads scalars of a
  record).
- Measuring SIMPLE; production data; the skill or `CLAUDE.md` edits (proposed in the report only).

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement on the base | both builds from scratch, zero warnings; the fast gate; counts; the toys' digest lines twice; the queue re-checked |
| 1 | identical for the toys (three procedures made public); tests-only for the bench and suite `probe` | every phase's gates; the digest lines equal Phase 0's; rule `mirror` with the three lines; decision 7's answers |
| 2 | tests-only: suites `tail`, `reduce` | every phase's gates; decisions 5, 8, 9, 14 on seeds 1 (frozen) then 2 and 3; plants of decision 15 for these suites |
| 3 | tests-only: suites `sizes`, `select` | every phase's gates; decisions 5, 10, 11; their plants |
| 4 | tests-only: suites `insert`, `waits` | every phase's gates; decisions 5, 12, 13, 14; their plants |
| 5 | documents | every phase's gates and the last phase's; the report |

Every phase's gates: Debug and Release from scratch with `-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`, zero
warnings; the fast gate in both (13 entries, within its bound 38.74 s; 10.7 s today); `scripts/check_tree.sh`;
`scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` on every touched Fortran file; the unit areas at the
counts Phase 0 records (at `b2c43a4`: core 215 or 216, array 193, ops 2,462, fft 194, linalg 632, compile 63,
kernels 1,955, fast 152, random 486, transforms 274, io 846, distributed 55); this plan changes none of them. The
last phase adds `scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`,
`scripts/release_gate.sh --allow-dirty` and the Release fast gate 10 times of 10.

## 6. Acceptance

- **Frozen before the runs they judge** (Phase 0, written in Progress): decisions 3, 5, 6 and the hypotheses of
  decisions 8 to 13 with their tags as written here. `FORMS_REDUCE_TOL` and `FORMS_INSERT_TOL` frozen on seed 1
  in Phases 2 and 4 before seeds 2 and 3.
- **Numbers and their origin.** 1.30, four of five, 0.95 to 1.05: the house rule and K1's verdict shape
  (*measured* use; the band *guessed*). Ceilings 1.28 and 1.18 (*derived* from K1 and K2, *measured* inputs;
  Phase 0 re-derives them from 2e's canonical passes). `POLARFT_TAIL_ROT_BLK` 5 per 64,000 and K1's oracle bounds
  (*measured*, frozen in K1). 0.2 ms and 48.7 to 60 ms (*measured*, parity Phase 10 and K1). 0.17 ms a wait
  (*measured*, K8). 4.5 % (*derived*, K7 finding 16). Every hypothesis threshold in decisions 8 to 13 is
  *guessed* or *derived* as marked.
- **Identity.** The toys' digest lines of Phase 0 are equal after Phases 1 to 4. Bit identity where decision 5
  asks it; never rerun until it passes: an alternative that is not identical where it should be is recorded,
  diagnosed and either fixed in its source with the diagnosis in Progress, or dropped.
- **Repeatability is its own gate,** per decision 5, recorded per form.
- **Reported, not gated:** the 3- and 6-process rows of `tail` beyond decision 3's 1.0; peak memory of every
  form; the extrapolation of decision 12; the A-A floors; the plain-sum errors; mlx3D's numbers (theirs, quoted
  with their origin).

## 7. Common rules and stop conditions

- No new parameter of a toy. No floor, tolerance or assertion relaxed unless this plan says so. Fix as you go,
  with a file-table row before the edit. One submitting thread; no library call inside an OpenMP region.
- Probes beyond the bench are scratch programs in the run's `scratch/probe/`, against the phase's Release build,
  never in the repository.
- Git is read-only for the run. The run works in a copy of the checkout on the M5 Ultra, one run at a time.
- A finding about MLX or mlx-c becomes a numbered entry in `doc/collaboration/apple_questions.md` (from 32),
  written, never sent.

**Stop conditions.**
1. A path, procedure or count of "The queue" is not as listed and the difference changes a decision (a renamed
   procedure is recorded and followed; a moved kernel or a changed source is a stop).
2. Making a spec public (decision 4) changes a digest line.
3. A wrapper is missing for a form (a feature the spec cannot express): stop that form with a report; no file
   under `src/core/` or `src/defs/` changes.
4. A tolerance or a hypothesis threshold would have to move after it was frozen.
5. A file outside the table needs an edit that is not an "if needed" row.
6. The base fails its own gates or the A-A control's spread exceeds 10 % in a suite (*guessed*): the machine's
   state is recorded and the suite's verdicts become "inconclusive" without a rerun for a result.
7. A form gives wrong results on the GPU that an oracle catches and the diagnosis points at MLX (MLX issue #4603
   is the known case): stop that suite, write the Apple question, continue with the others.

**Gates no ruling may waive:** both builds without a warning; the fast gate; `scripts/check_tree.sh`; the unit
areas' counts; the toys' digest lines; the agreement of decision 5 before any timing; repeatability; the planted
violations; the last phase's checks.

## 8. Phases

### The queue

The run starts from the commit holding run 2e's verified result, which holds run 2d's. Phase 0 re-checks, and
records as found:
- **2d moves the test tree** (2d's plan fixes it): `src/test/framework/` (`mlxf_test_defs`, `mlxf_test_utils`,
  `mlxf_test_reduce`, `mlxf_test_registry`, the ABI probe), `src/test/oracles/` (every `mlxf_oracle_*`),
  `src/test/toys/` with `polar/`, `projector/`, `recon/`, and `src/test/bench/` (every `mlxf_bench_*`). Module
  names do not change. 2d splits `mlxf_array.f90` and `mlxf_ops.f90` without a public name of `mlxf` changing;
  `mlx_metal_kernel` and `mlx_metal_kernel_spec` keep their names and components.
- **2e moves the polar toys to SIMPLE's memo layout** (`ft_ref_terms (2nk, pftsz+1, nrefs, half)`): the resident
  tiles and products may change shape; the tail's input rows `(nrots, rt, bt)` and `tail_spec` are expected
  unchanged (to check); the dense baselines and K1's digest lines are re-measured by 2e, and this run's Phase 0
  takes 2e's numbers, not K1's, for the ceilings and the digests.
- The registry's `BENCHES` and `NAMED_ONLY` counts, the unit counts, the fast gate's entries and time, the last
  Apple question's number, the mirror ledger's line count.

### Phase 0, the base (box: 90 min)

1. Record the machine (`uptime`, compiler, CMake, MLX and mlx-c versions), the base hash, the queue's items.
2. Build Debug and Release from scratch; the fast gate; every unit area; record counts and times.
3. Take the toys' digest lines twice (K1's `suite=accuracy` and `suite=time` lines, K2's 16, as 2e defines them).
4. Time K1's canonical pass with `tail=metal` and K2's fused reprojection once each, to re-derive decision 3's
   ceilings from 2e's base; record the products' and transforms' share as K1 did.
5. Read the K5 draft's canonical shape for decision 9 and the K3 draft's list shape for decision 13; record.
6. Freeze in Progress decisions 3, 5, 6 and the hypotheses of 8 to 13.

Exit: both builds clean; counts and digests recorded twice and equal; the ceilings re-derived (if either reaches
1.30, Progress says so and decision 3 still holds: the K plans own a default change); the frozen block written.

### Phase 1, the exports, the bench and the probe (box: 120 min)

1. Make `tail_spec`, `gather_spec` and `probe_spec` public (decision 4), with their ledger lines.
2. Create the bench (decision 18), its `BENCHES` entry and `run_bench` case, `NAMED_ONLY` if the registry
   requires it, and the policy paragraph's line (Phase 5 writes the paragraph).
3. Suite `probe` (decision 7); run it twice in two invocations.
4. Plants: the probe's missing barrier, the ledger line, the `BENCHES` entry.

Exit: digests equal Phase 0's; rule `mirror` and `check_test_registry.py` pass and fail on their plants;
`probe` reports (a) to (d) with numbers; Apple question 26's draft update in Progress; the suites that need a
refused feature are marked stopped.

### Phase 2, the tail and the reduction (box: 180 min)

1. Suite `tail` (decision 8): agreement on seed 1 (record), then seeds 2 and 3 against the frozen bounds;
   repeatability; the A-A control; the timing; `scripts/run_parts.sh` at 1, 3 and 6 processes for T0 and T1.
2. Suite `reduce` (decision 9): `FORMS_REDUCE_TOL` frozen on seed 1, then judged; repeatability; A-A; timing.
3. Plants of decision 15 for T1, R2.

Exit: two tables in Progress with verdicts by decision 3; `FORMS_REDUCE_TOL` in `mlxf_test_defs.f90` and
Progress with its evidence; every plant failed its gate.

### Phase 3, sizes and selection (box: 120 min)

1. Suite `sizes` (decision 10): G1 equal to G0 bit for bit on both kernels; per-launch timing; the first
   evaluations of 8 values of `npts` in fresh processes, twice.
2. Suite `select` (decision 11): the exact gate for E0 to E3 at K = 3 and 10 on seeds 1 to 3; E1 without the
   repair recorded failing; timing.
3. Plants for G1, E1, E2.

Exit: two tables; the compile costs per form; the selection gate's counts (0 mismatches for every kept form).

### Phase 4, the insertion and the waits (box: 180 min)

1. Suite `insert` (decision 12): D1 and D2 at n = 64; `FORMS_INSERT_TOL` frozen on seed 1, judged on 2 and 3;
   D2 equal to D1 bit for bit; repeatability; timing; the extrapolation rule written, then n = 96.
2. Suite `waits` (decision 13): F1 equal to F0; timing at 40 tiles; the cost of one wait inside the busy queue.
3. Plants for D1, D2, F1.

Exit: two tables; `FORMS_INSERT_TOL` frozen with its evidence; the factor D1/D0 at two sizes and its
extrapolation; every plant failed.

### Phase 5, the record (box: 120 min)

1. The lessons note revised (decision 17). Apple question 26 updated; new questions from 32.
2. `doc/policies/binding_contract_policy.md` section 12, "Measured by the toys": the probe's answers and the
   sizes' costs. `doc/policies/test_environment_policy.md`: the bench's paragraph.
3. The roadmap's row 2f (delivered, the report's path), its decision 16 unchanged; the history's entry; the
   plans index (`doc/implementation_notes/README.md`).
4. The report `doc/implementation_notes/completed/mlxf_kernel_forms_report.md` in the how-to's order, with the
   list of K3 to K7 decisions each verdict changes (section "What the K plans take") and the proposals for the
   `mlxf-binding` and `mlxf-modern-fortran` skills (not applied).
5. The last phase's gates.

Exit: every document row of the file table written; the report ends with a commit message without attribution
that names every new file; the plan's status line says delivered.

### What each verdict changes, written in advance (the report fills the column "found")

| Result | K plan and decision that change |
| --- | --- |
| T1 preferred / not | K7 decision 16 (F1 a SIMD group per pair, or as written); K4 decision 9 (the reductions' launch shape) |
| T2 equivalent / faster | the house rule on compensated sums; K5's and K6's accumulation (K6 decision 19's tolerance basis) |
| R2 preferred over R0, R3 | K5's fused form and its ceiling order; the note's section 4 (K5) |
| G1 equivalent | K3 decision 10 (candidate B's sizes; "capacities are powers of two" becomes unnecessary); K6 decision 28; the `mlxf-binding` skill line |
| E2 or E3 preferred, E1 repaired or not | K7 decisions 14 and 15 (the order of forms, whether E1 is measured again) |
| D1/D0 and D2/D1 | K6 decisions 8, 12, 13 (order of the forms, the plane walk, staging as a variant) |
| F1 preferred | K3 decision 10 (candidate B), K6's sorted form, the note's P3 |
| probe refused or wrong | K7 decision 15 (F3 not built), K6 staging, K5's tree: each falls back to its graph or per-thread form |

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/bench/mlxf_bench_kernel_forms.f90` | new: the named-only bench, suites `probe`, `tail`, `reduce`, `sizes`, `select`, `insert`, `waits` | 1, 2, 3, 4 |
| `src/test/bench/mlxf_bench_kernel_forms_src.f90` | new, if needed (decision 18): the alternative kernels' sources and specs | 1, 2, 3, 4 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace.f90` | `tail_spec`'s interface made public | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90` | `tail_spec` a module procedure of the interface (no change of source or launch) | 1 |
| `src/test/toys/projector/mlxf_toy_projector_workspace.f90` | `gather_spec` public | 1 |
| `src/test/bench/mlxf_bench_insert_probe.f90` | `probe_spec` public | 1 |
| `scripts/toy_mirror.txt` | the additions of decision 4 (the probe's line only if the rule asks it of a bench) | 1 |
| `src/test/framework/mlxf_test_registry.f90` | `BENCHES`, `run_bench`, `NAMED_ONLY` if needed | 1 |
| `src/test/framework/mlxf_test_defs.f90` | `FORMS_REDUCE_TOL`, `FORMS_INSERT_TOL` | 2, 4 |
| `src/test/bench/bench.inf` | the new file's line, if 2d's layout keeps an `.inf` per folder | 1 |
| `doc/implementation_notes/planned/mlxf_mlx3d_lessons.md` | revised (decision 17) | 5 |
| `doc/collaboration/apple_questions.md` | question 26; new from 32 | 1, 5 |
| `doc/policies/binding_contract_policy.md` | section 12's measured facts | 5 |
| `doc/policies/test_environment_policy.md` | the bench's paragraph | 5 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | row 2f | 5 |
| `doc/history/2026-11.md` (or the month the run ends) | the entry | 5 |
| `doc/implementation_notes/README.md` | the index | 5 |
| `doc/implementation_notes/planned/mlxf_kernel_forms.md` | this plan: Progress, the status line | 0, 1, 2, 3, 4, 5 |
| `doc/implementation_notes/completed/mlxf_kernel_forms_report.md` | new: the report | 5 |

## Progress

(one entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was met,
log paths, decisions taken under delegation, what it means in short)

### Phase 0

### Phase 1

### Phase 2

### Phase 3

### Phase 4

### Phase 5

## The report

Written by Phase 5 as `doc/implementation_notes/completed/mlxf_kernel_forms_report.md`: what was learned (the
seven tables and the review's corrections first); what changed, phase by phase, with file counts; decisions taken
under delegation; deviations, including expected effects that did not occur and every file changed outside the
table; evidence against the baseline (digests, counts, plants, builds, loads); what the K plans take (the table
above, filled); left open for the maintainer (the skill lines, the note's proposals still open, the Apple
questions); a commit message without attribution or co-author line that names every new file.
