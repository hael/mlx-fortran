# The review against mlx3D, and experiments on the ways of writing a kernel (run `mlxf_kernel_forms`, on the M5 Ultra)

Status: delivered in the working tree on the M5 Ultra, 2026-11-26 (run `mlxf_kernel_forms`, Phases 0 to 5, no
ruling), [report](../completed/mlxf_kernel_forms_report.md); awaits the maintainer's read. Decisions stood as recommended
under the maintainer's go of 2026-11-26, open to his review. Base: `bb59c21` (run 2e's result, which holds 2d's);
planned against `b2c43a4`, with mlx3D read at `7101ec3` (`~/src/mlx3D`), MLX read at `5c8989446` (`~/src/mlx`; the
installed MLX is 0.32.4) and SIMPLE not read (nothing here depends on SIMPLE's code; the polar layout is 2e's).
Supersedes: none. Revises: the advisory note [`mlxf_mlx3d_lessons.md`](mlxf_mlx3d_lessons.md) (its Phase 5). Depends
on: run 2d and run 2e (both delivered, see "The queue" and Phase 0). Roadmap rank 2f, decision 16.

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
| `src/test/bench/mlxf_bench_insert_probe.f90` | `probe_spec` public; Phase 3: its record `probe_case` moved to `mlxf_test_defs` (rule `defs`: the bench builds it), `seeded_case` and `window_coefficients` public (the insertion's inputs come from the probe's own code) | 1, 3 |
| `scripts/toy_mirror.txt` | the additions of decision 4 (the probe's line only if the rule asks it of a bench) | 1 |
| `src/test/framework/mlxf_test_registry.f90` | `BENCHES`, `run_bench`, `NAMED_ONLY` if needed | 1 |
| `src/test/framework/mlxf_test_defs.f90` | `FORMS_REDUCE_TOL`, `FORMS_INSERT_TOL`; Phase 3: the insertion probe's record `probe_case` | 2, 3, 4 |
| `src/test/framework/mlxf_test_utils.f90` | added in Phase 1 (fix as you go): `digest_bits`, the benches' one digest step, public here instead of a third private copy; Phase 2: `wait_for_go_file`, the part processes' ready-and-go wait, likewise | 1, 2 |
| `src/test/bench/mlxf_bench_polar_table.f90` | added in Phase 1: its private `digest_bits` deleted, imported from `mlxf_test_utils` (same arithmetic, digests unchanged); Phase 2: its `wait_for_go` body calls `wait_for_go_file` | 1, 2 |
| `src/test/bench/mlxf_bench_projector.f90` | added in Phase 1: as the polar bench | 1, 2 |
| `src/test/bench/bench.inf` | the new file's line, if 2d's layout keeps an `.inf` per folder | 1 |
| `doc/code_base_map.md` | added in Phase 1: regenerated by `scripts/generate_codeoverview.py` (the static gate holds it to the `!@descr:` lines and `.inf` files; the new bench and `bench.inf`) | 1, 2, 3, 4 |
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

2026-11-26, 17:37 to 17:55, on the M5 Ultra (local; 30 cores, 96 GB, one GPU `applegpu_g17d`), unattended. Base
`bb59c21` (run 2e's result, which holds 2d's `6a1a03e`), clean tree. Toolchain: Homebrew GCC 16.2.0 (`gfortran-16`),
CMake 4.5.1; MLX 0.32.4 and mlx-c 0.8.0 from Homebrew (`/opt/homebrew/lib/libmlxc.dylib`). No ruling in
`spec/rulings.md`. Evidence under `/Users/hael/agent_runs/mlxf_kernel_forms/scratch/keep/phase0/` (written `phase0/`
below); the scripts under `scratch/keep/tools/` and `phase0/*.sh`.

**Files changed:** this plan (Progress) only.

**Exit items.**

- **Both builds clean.** Debug and Release from scratch with the run's recipe (`cmake -DMLXF_WERROR=ON -DFORTLS=OFF
  -DBUILD_TESTS=ON`, `cmake --build -j 12`, `scripts/run_fast_gate.sh`, install; `phase0/build.sh`): 0 warnings in
  either, the static gate passes, the fast gate 13 of 13 in both (`phase0/build_{debug,release}.log`; the two gates ran
  side by side, 12.69 and 12.11 s of tests). The Release gate alone: 11.95 s of tests, 16.6 s with the static gate,
  load 3.54 before and 3.52 after (*measured*, `phase0/fast_gate_release_alone.log`), within the bound 38.74 s.
- **Counts** (*exact*, `phase0/run_units.log`, `phase0/units_{debug,release}/`), equal in Debug and Release, every
  assertion passing: core 216, array 193, ops 2,462, linalg 632, fft 194, compile 63, transforms 274, fast 152,
  random 486, io 846, distributed 55, kernels **1,953** (not the 1,955 of section 5: 2e's Phase 1 and 2 moved
  `projector_chain` by -8 and `polarft_calc` by +6, its report). These are the counts every later phase keeps
  (core 216 or 214, the allocator's two, as 2e records). `unit_core` reports "GPU devices: 1".
- **Digests twice and equal.** The toys' digest lines as 2e defines them: run 2e's identity set (its decision 13:
  the seam run's eleven invocations, which hold K1's `accuracy` and `time` digests and the projector's, K3's two
  dense `2500_4` cases, the 135 `polarft_host` lines and the off-state table), by 2e's `tools/identity.sh` copied to
  `scratch/keep/tools/identity.sh` with only its paths changed. Runs a and b (Release, 109 and 110 s) are equal
  byte for byte and equal to 2e's own base copy: 364 lines, **SHA-256
  `e2d65e8861d23ef7d731960e17269c6ecaed23fc46d735a1dc37f0bb4d33dba5`** (*exact*; `phase0/identity_{a,b}/identity.txt`,
  `phase0/identity_ceilings.log`, the reference `phase0/identity_2e_base.txt`). Among them: polar `time 1000_1`
  `BACBE44E34B4AAB2` (graph) and `A78E44BB3FCD8220` (metal); `time 2500_4` `3457E99553A08BFD` (graph) and
  `C65F8ECED8D9B855` (metal); projector fused `time` `08C94AB3FB1D7C6C 5CCCE018F232599B`. Later phases compare
  their identity set against this file.
- **The ceilings re-derived** (Release, one process, 30 threads; load gate 4, `uptime` before and after each:
  2.89 to 3.92 before, up to 5.55 after; `phase0/ceilings/`):

  | Measure (*measured*) | Value |
  | --- | --- |
  | K1 `suite=time case=2500_4 bt=64 rt=250 passes=9`, `tail=metal`: median pass | 0.6342 s (3.15e7 pairs/s, peak 1.635e10 B), digest `C65F8ECED8D9B855` |
  | the same, `tail=graph` | 1.1313 s (1.77e7 pairs/s, peak 0.989e10 B), digest `3457E99553A08BFD` |
  | K1 `suite=profile`, `tail=metal` (a barrier after every stage): wall; terms, products, transform, distances and draw, concatenation; rest | 1.3611 s; 0.0061, 0.4799, 0.4378, **0.4144**, 0.0029; 0.0200 s |
  | K1 `suite=profile`, `tail=graph` | 1.9191 s; 0.0061, 0.5578, 0.4191, **0.9086**, 0.0029; 0.0246 s |
  | K2 `bench_projector suite=time form=fused tile=2500 tg=64`: median pass; stages of passes 1 to 3 (pad and transform, expansion, projection) | 0.0399 s; 0.0190/0.0199/0.0178, 0.0095/0.0091/0.0098, 0.0102/0.0064/0.0068 s (an earlier identical run: 0.0399 s, projection 0.0101/0.0062/0.0066, `phase0/ceilings_try1/`) |

  Shares as K1 recorded them (*derived*, profile): with the fused tail the products are 35 %, the transform 32 %
  and the tail 30 % of the profile's 1.361 s; with the graph tail 29 %, 22 % and 47 % of 1.919 s. K2: pad and
  transform 0.019 s and expansion 0.0095 s are 71 % of the 0.0399 s pass, the projection 0.0066 to 0.0068 s.
  - **K2's gather ceiling: 1.20** (*derived*: 0.0399 / (0.0399 - 0.0068) = 1.205; 1.198 with 0.0066), against the
    plan's 1.18. Below 1.30.
  - **K1's tail ceiling: 1.32 by the plan's own method, 1.45 by the profile's share** (*derived*). The plan's 1.28
    took the non-tail part as the graph pass less K1's compiled tail (about 0.65 s, *measured* in K1's free-tail
    run, not repeated here): (1.1313 - 0.65) = 0.481 s, and 0.6342 / 0.481 = 1.32. Taking the fused tail's share of
    the barriered profile instead (0.4144 of the stages' 1.3411 s, 31 %) gives 1 / (1 - 0.309) = 1.45; that share
    overstates the tail, since the pipelined pass (0.634 s) overlaps stages the profile serialises. **Either
    reaches 1.30.** As section 8 provides, decision 3 still holds: this run judges forms on the kernel and changes
    no toy; a default change of K1's tail is a K plan's to measure on its own driver (K7's or K4's), and this
    ceiling is the number it starts from.
- **The queue re-checked** (an independent read of every item of section 2 and "The queue", at `bb59c21`): the
  tail's, the gather's and the probe's sources are byte-identical to `b2c43a4` (2d moved the files without change,
  2e did not touch them). As listed: `tail_source`, `tail_spec(spec_t, rows)` (a plain procedure of the submodule
  `mlxf_toy_polarft_workspace_tail.f90`, no interface in the parent), `POLARFT_TAIL_TG` 64
  (`mlxf_test_defs.f90`), grid `[rt bt, 1, 1]`, rows `(nrots, rt, bt)` unchanged by 2e, Kahan sum,
  `metal::precise::exp`, the rows variant on first use, `mlx_async_eval` per tile and one wait per block at
  collection; `gather_spec(m, npts, tn, tg)` private in `mlxf_toy_projector_workspace.f90` with templates `E`, `L`,
  `NPTS`, `PADS3`, grid `[npts, tn, 1]`, `mlx_eval` per tile in `fused_tile`; `probe_spec(cs, nb, atomic)` private in
  `mlxf_bench_insert_probe.f90`, grid `[npix, nb, 1]`, threadgroup `min(256, npix)`, five templates, `init_value` 0;
  no custom kernel in the shift maps or the PCG; the wrapper in `src/core/fast/mlxf_fast.f90` (`config_of`, no math
  mode), `mlx_metal_kernel_spec` in `src/defs/mlxf_defs.f90` with the components section 2 names; no
  `threadgroup` array, `threadgroup_barrier` or `simd_` in any kernel source. Counts: `BENCHES` 5 (`polar_table`,
  `recon_pcg`, `projector`, `insert_probe`, `blas`), `NAMED_ONLY` 4, fast gate 13 entries, `toy_mirror.txt` 221
  lines (176 entries). Differences, none of which changes a decision (stop 1 not met):
  - `tail_spec`'s host array `par` has 8 elements of which the kernel reads 5 (`par(1:5)`); the "5-element input"
    of section 2 is the kernel's view. T0 is built by `tail_spec` itself, so nothing depends on it.
  - `run_bench` does not need a bench in `NAMED_ONLY` (that table serves `run_suite` only), so Phase 1 adds no
    `NAMED_ONLY` line; `scripts/check_test_registry.py` holds `BENCHES` equal to `run_bench`'s cases.
  - Rule `mirror` covers public names of `mlxf_toy_*` modules under `src/test/toys/` only: `tail_spec` and
    `gather_spec` need a ledger line each, `probe_spec` (a bench) none.
  - The last Apple question is **35**, not 31: new entries start at **36** (decision under delegation 3).
  - `bench.inf` already omits `blas`; Phase 1 adds the new bench there.
- **The K5 draft's shape for decision 9** (`mlxf_kernel_k5.md`, its finding 3 and decisions 6 and 10): one
  evaluation reduces **23** sums for the Euclidean objective (27 for the correlation, plus one per shell for the
  shell residual) over **6,136** pixels (*exact*: shells 2 to 62 of a box of 160), padded with zero-weight
  pixels to **6,144** (its table); a round evaluates **500** entries (its batch), at most 41 rounds a batch. The
  draft names no "2,000 evaluations". Taken (decision under delegation 4): `reduce` runs 500 evaluations of 23
  sums over 6,144 terms (the last 8 zero, as K5 pads), R0 to R3 as decision 9 writes them.
- **The K3 draft's list shape for decision 13** (`mlxf_kernel_k3.md`, "What the check found"): a tile is
  `matmul(pt, g)` with `pt (bt, 4nk, pftsz+1)` = (64, 244, 183) and `g (4nk, 2rt, pftsz+1)` = (244, 500, 183):
  183 products, one per bin, of 64 by 244 by 500, contracting over 4nk = 244 (*exact*: pftsz 182, 61 shells, rt
  250, bt 64). Section 3's "250 by 366 by 64" read the 2 x 183 bins as the contraction; they are the batch. Taken
  (decision under delegation 5): `waits` makes each tile as K3's product (183 batched 64 x 244 by 244 x 500
  products of seeded float32 operands), sums it over the bins and adds the two row halves of each reference, which
  gives the 16,000 pair scores (64 by 250) that the mask then lists; the rest of decision 13 as written.

**Decisions taken under delegation.**

1. The toys' digest lines are run 2e's 364-line identity set, run by 2e's script with only its paths changed.
   Reason: "as 2e defines them" (section 8); it holds K1's and K2's digest kinds and 2e's base copy is a third
   reference beside the two runs.
2. K1's ceiling is reported by two derivations (the plan's subtraction with K1's measured 0.65 s, and the
   profile's share) and no free-tail run is made. Reason: the plan asks a re-derivation from 2e's base, not a new
   experiment; both reach 1.30, and section 8 says what follows from that.
3. New Apple questions are numbered from 36 (decision 16 and Phase 5 say "from 32"; 32 to 35 exist). Reason:
   numbers are never reused.
4. `reduce` at K5's round: 500 evaluations, 23 sums, 6,144 terms (decision 9's 2,000 and about 6,000 were
   *guessed*; the draft gives the round as *exact*). Reason: decision 9 asks Phase 0 to record the draft's shape;
   R0's under-filling argument holds more strongly at 500 threads than at 2,000.
5. `waits`' tile at K3's product shape (above). Reason: decision 13 says "a product of K3's list shape"; its
   parenthetical shape was a misreading, and a tile some 240 times smaller (5.9e6 against 1.43e9 multiply-adds,
   *derived*) would make the queue that F0's waits drain unrepresentative of K3.

**Frozen before the runs they judge** (written 2026-11-26 17:55, before any line of the bench exists; never
moved; a needed change is stop 4):

- **Decision 3, the verdict.** Ratio = current time over alternative time. *Preferred*: the median of five
  interleaved pair ratios at least 1.30 with at least four of the five at or above 1.30, at one process; for
  `tail` also the go-to-last-exit ratio at least 1.0 at 6 processes. *Equivalent*: median in 0.95 to 1.05.
  *Worse*: median below 0.95. *Inconclusive*: otherwise, and any verdict whose margin from its threshold lies inside
  twice the suite's A-A floor (decision 6), and every verdict of a suite whose A-A spread exceeds 10 % (stop 6).
  No toy changes under any verdict.
- **Decision 5, agreement before timing.** Bit for bit: T1's and T2's distances and first minima against T0; G1
  against G0; E0 to E3 against each other and against the host's first-maximum rule; F1 against F0; D2 against D1.
  Within a tolerance: T1 and T2 draws at most `POLARFT_TAIL_ROT_BLK` = 5 differing rotations per 64,000 pairs
  against T0, and within K1's oracle bounds against `mlxf_oracle_polar` on the device's rows (frozen in K1);
  R0 to R3 against the host's double sum within `FORMS_REDUCE_TOL`; D1 and D2 against D0 within
  `FORMS_INSERT_TOL`; both new tolerances frozen on seed 1 on the GPU (decision 14: twice the largest seed-1
  difference, above 2^-23 of the sum of |terms| for the reduction) before seeds 2 and 3 are judged. Repeatability:
  every form bit-identical over 3 runs in one process and over 2 invocations, except D0 (atomics), whose spread is
  recorded. A form that fails agreement is recorded as failed and not timed.
- **Decision 6, the timing protocol.** Release; one executable, the form by key; a warm-up evaluation of every
  form before each suite; per pair the current form then the alternative, the next pair in the opposite order;
  five pairs, each a median of 5 timed evaluations; two invocations; an A-A control (current against itself, three
  pairs) first in each suite, its spread the suite's noise floor; a one-minute load of at most 4 before each timed
  step (at most 30 minutes' wait, then recorded), `uptime` before and after; nothing else of the run built or run
  meanwhile. `tail` also at 3 and 6 processes by `scripts/run_parts.sh` (`RUN_PARTS_BENCH=kernel_forms`,
  `RUN_PARTS_SUITE=tail`), 40 canonical tiles a part, the rate from go to the last exit, each part's MLX peak.
- **Hypotheses**, with their tags as section 3 writes them:
  - (8) T1 is preferred over T0 (*guessed*; T0 at about 410 GB/s, *derived*). T2 is equivalent to T0 in time
    (*guessed*) and within the rotation bound. Consequences as decision 8 writes them (a SIMD group per pair for
    K7's F1 and K4's reductions if T1 is preferred; plain sums allowed only if T2 is faster by more than 5 % and
    within bounds).
  - (9) At 500 evaluations of 23 sums over 6,144 terms: R2 is preferred over R0 (*derived*: R0 launches 500
    threads, R2 128,000); R2 is preferred over R3 (*guessed*); R0 and R2 are bit-repeatable; R1 is equivalent to R0
    in time and its error against the double sum is at most a tenth of R0's (*guessed*).
  - (10) G1 is equivalent to G0 per launch (*guessed*); G0's first evaluation per new `npts` is at least 40 ms
    (*measured* basis 48.7 to 60 ms a new source) and G1's at most 1 ms (*measured* basis 0.2 ms a new object).
  - (11) E1 without its tie repair fails the exact gate on the planted ties (*derived*, K7 finding 13); E2 is
    preferred over E0 at K = 10 (*guessed*); E3 is preferred over E2 (*guessed*).
  - (12) D1 and D2 are bit-repeatable (*derived*); D1 is at most 3 times slower than D0 at n = 64 (*guessed*); D2
    is preferred over D1 (*guessed*). The extrapolation rule to n = 160 is written in Progress before the n = 96
    run.
  - (13) At K3's tile (above): F1 is preferred over F0 (*guessed*: each wait drains the queue).

**What it means, in short.** The base is sound: both builds clean, the counts as 2e left them (kernels 1,953), the
364-line identity set equal twice and equal to 2e's. The queue holds; five small differences are recorded and
change no decision. Re-derived on 2e's base, K2's gather ceiling is 1.20 but K1's tail ceiling reaches 1.30 (1.32
to 1.45 by two derivations), so a faster tail could in principle pass the 30 % rule on K1's driver; decision 3
keeps that for the K plans. The shapes of `reduce` and `waits` follow the K5 and K3 drafts, and the verdict rule,
agreement, protocol and hypotheses are frozen.

### Phase 1

2026-11-26, about 17:50 to 18:05 by the machine's clock, on the M5 Ultra (local), unattended. Base `bb59c21` plus
Phase 0's change. No ruling. Evidence under
`/Users/hael/agent_runs/mlxf_kernel_forms/scratch/keep/phase1/` (written `phase1/` below); the builds in
`scratch/build_{debug,release}` by `phase0/build.sh`; the checks `phase1/checks.sh`.

**Files changed:** `src/test/bench/mlxf_bench_kernel_forms.f90` (new, 377 lines: suite `probe`);
`src/test/toys/polar/mlxf_toy_polarft_workspace.f90` (`tail_spec`'s interface, public);
`src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90` (`tail_spec` a module function, its body unchanged);
`src/test/toys/projector/mlxf_toy_projector_workspace.f90` (`gather_spec` public);
`src/test/bench/mlxf_bench_insert_probe.f90` (`probe_spec` public); `scripts/toy_mirror.txt` (two additions);
`src/test/framework/mlxf_test_registry.f90` (`BENCHES` 6, the `run_bench` case); `src/test/bench/bench.inf`;
`src/test/framework/mlxf_test_utils.f90`, `src/test/bench/mlxf_bench_polar_table.f90`,
`src/test/bench/mlxf_bench_projector.f90` (`digest_bits`, below); `doc/code_base_map.md` (regenerated); this plan.
The file table gained four rows before those edits (the last three files and the map).

**Exit items.**

- **Builds.** Debug and Release from scratch with `MLXF_WERROR=ON`: 0 compiler warnings (the only "warning" line is
  the static gate's note that the new file is untracked, which it stays: nothing is committed), the static gate
  passes, the fast gate 13 of 13 (12.60 s and 10.46 s of tests), installed (`phase1/build_{debug,release}.log`).
  The first attempt stopped at the static gate because `doc/code_base_map.md` did not list the new file; the map
  was regenerated (its row added first) and both builds repeated from scratch.
- **Counts** (*exact*, `phase1/checks.log`, `phase1/units_{debug,release}/`): equal to Phase 0's in every area
  (kernels 1,953) except Release `unit_core` 215 in the scripted run; three more runs of the same executable gave
  215, 216, 215 (`phase1/unit_core_rerun{1,2,3}.log`): the allocator-dependent count section 5 and 2e record (214
  to 216), not this change (no library file is touched).
- **Digests equal Phase 0's.** The 364-line identity set on the Release build: byte for byte equal to Phase 0's,
  SHA-256 `e2d65e88...4d33dba5` (*exact*, `phase1/identity/identity.txt`). Stop 2 is not met: making the specs public
  and moving `digest_bits` changed no digest.
- **Rule `mirror` and `check_test_registry.py` pass and fail on their plants** (`phase1/plants/`, each in a copy of
  the source, removed afterwards and the copy checked equal to the repository's file): rule `mirror` passes on
  the tree, and fails (status 1) with the `tail_spec` line removed ("tail_spec of mlxf_toy_polarft_workspace has
  no line in scripts/toy_mirror.txt") and with the `gather_spec` line removed; `check_test_registry.py` passes,
  and fails with `kernel_forms` removed from `BENCHES` ("benchmarks differ: ... run_bench case() [...
  'kernel_forms' ...]").
- **Suite `probe` reports (a) to (d)** (*measured*, Release, two invocations `phase1/probe/release_inv{1,2}.log`,
  and once on Debug `debug_inv1.log`; all three equal; 19 assertions passing):
  - (a) a group sum of small integers through a `threadgroup float sh[1024]` with a barrier after the store and
    after every tree level: **exact for 64 of 64 groups** at 32, 64, 256 and 1,024 threads a group.
  - (b) on threadgroups of 64: `thread_index_in_simdgroup`, `simdgroup_index_in_threadgroup`,
    `threads_per_simdgroup` (32), `simd_sum`, `simd_min`, `simd_prefix_inclusive_sum` and `simd_shuffle`: **each
    exact for 256 of 256 threads** against the host.
  - (c) the same tree on seeded non-integer values, groups of 256: three runs in a process bit for bit equal, and
    the digest **`393B09A67E8C514D` in both Release invocations and in Debug**: bit-repeatable. The host's float32
    tree in the same order is equal in 64 of 64 groups (reported).
  - (d) a `threadgroup float sh[NF]` (NF a template) builds and reads back correctly at 4,096, 8,192, 16,384 and
    **32,768 B**; **65,536 B is refused** at evaluation with status 1 and MLX's message "[metal::Device] Unable to
    load kernel custom_kernel_forms_probe_tgmem__16384_float_float / Threadgroup memory size (65536) exceeds the
    maximum threadgroup memory allowed (32768)". The refusal comes back as a status; the process continues.
  - A key the suite does not read stops it with status 2 (`phase1/probe/key_stop.log`), so does `form=z`
    (`form_stop.log`).
- **Plant: the probe's group sum without its barriers** (both removed in a patched copy built apart in Release,
  `phase1/plants/barrier_plant.diff`, `barrier_plant_run{1,2,3}.log`): the gate fails in 3 of 3 runs, groups of
  256 exact in 28, 32 and 32 of 64 and groups of 1,024 in 0 of 64 (groups of 32 and 64 stay exact: one or two
  SIMD groups, whose lanes run together). The copy and its build were deleted.
- **No suite is stopped.** No feature was refused or wrong: `tail` T1, `reduce` R2, `select` E3 and `insert` D2
  keep their forms. The limit 32,768 B bounds what D2 may stage (a 19 by 19 pixel patch of a complex and a float
  is about 4.3e3 B, *derived*) and what E3 and R2 hold (8 floats, and 32 lists of at most 10 entries).
- **Apple question 26, the draft update** (written into the question in Phase 5): "Measured 2026-11-26, MLX 0.32.4,
  mlx-c 0.8.0, M5 Ultra (`mlxf_test_exec test=bench_kernel_forms suite=probe`, source
  `src/test/bench/mlxf_bench_kernel_forms.f90`): a `threadgroup` array declared in the body of a kernel built by
  `metal_kernel` gives exact group sums with `threadgroup_barrier` for groups of 32 to 1,024 threads, and without
  the barriers wrong sums from 256 threads up; `simd_sum`, `simd_min`, `simd_prefix_inclusive_sum`,
  `simd_shuffle` and the attributes `thread_index_in_simdgroup`, `simdgroup_index_in_threadgroup` and
  `threads_per_simdgroup` (32) are exact; a fixed tree is bit-repeatable over runs and processes; the largest
  array that builds is 32,768 B, and 65,536 B is refused at evaluation with the device's limit in the message.
  So part (1) is answered by measurement on this device: supported in practice, and its limit is the device's;
  what stays open is whether MLX supports it (the documentation still does not say so). Part (2) is unchanged."
  It also replaces the unreproducible "64-element group sum" sentence with a probe whose source is in the tree.

**Decisions taken under delegation.**

6. `probe_spec` alone is made public, as decision 4 says, and not its `probe_case` argument. Reason: rule
   `defs` puts a behaviourless record another module imports in `mlxf_test_defs`, and the house rule moves it
   "when the second module needs it, not before". Phase 4's D0 needs it: Phase 4 adds a file-table row to move
   `probe_case` into `mlxf_test_defs.f90` and to make `seeded_case` and `window_coefficients` of the insertion
   probe public, so that D0's inputs come from the probe's own code.
7. `digest_bits` moved to `mlxf_test_utils` and deleted from the two benches, rather than a third private copy in
   the new bench. Reason: "a second copy of a routine is a defect", and section 7's "fix as you go". The arithmetic
   is unchanged, and the identity set proves the digests unchanged.
8. The probe's parts are a key `form=all|a|b|c|d` (default `all`), and part (d) runs last. Reason: decision 18's
   key for forms; a refused size cannot then hide parts (a) to (c).
9. `bench.inf` names every bench, `blas` included, which it had left out.
10. The test environment policy's paragraph is left to Phase 5 (its file-table row is Phase 5's only); section 8's
    "the policy paragraph's line" is read as that paragraph.
11. No `NAMED_ONLY` entry (Phase 0: the registry does not require it for a bench).

**What it means, in short.** The three current kernels' specs are reachable from the bench without one byte of
their source or launch changing (digests equal). Through our wrapper, `threadgroup` memory with barriers and the
SIMD-group functions work exactly and repeatably on the M5 Ultra up to the device's 32 KB, so every form of
Phases 2 to 4 that needs them stays in. The probe also shows that the barrier matters as soon as a group has more
than two SIMD groups, so planting a missing barrier is a test that can fail.

### Phase 2

### Phase 2

**Frozen before the runs they judge** (written 2026-11-26 18:15, after the seed-1 calibration of `reduce` and
before any run of seeds 2 and 3 or any official `tail` run; never moved):

- **`FORMS_REDUCE_TOL` = 4.7556730237612776e-07** (*measured* then *derived*): twice the largest error of R0 to R3
  against the host's double sum on seed 1 on the GPU, relative to the sum of |terms| of the sum, which is R0's
  2.3778365118806388e-07 (R1 3.21e-09, R2 8.57e-09, R3 8.54e-09); above 2^-23 = 1.19e-07. Evidence
  `scratch/keep/phase2/reduce/agree_seed1_calibration.log` (Release; the forms bit-repeatable over 3 runs). In
  `src/test/framework/mlxf_test_defs.f90`.
- **The tail's operational gate** (decision 5 made concrete for inputs that have no calculator behind them; the
  bounds are K1's, frozen there): on each seed's 40 tiles, (i) each form's entries bit-repeatable over 3 runs;
  (ii) **first minima exact**: with every temperature set to 1e30 and every variate to 0, only the minimum keeps a
  weight, so each form's entry must be the host's first minimum (`polar_first_min`) of the current tail's rows
  (from its rows variant) and that row's distance, bit for bit (none valid: rotation 1 and the invalid
  distance); (iii) each form's draws hold on those rows by the oracle's rule (`polar_draws_off` = 0, K1's check
  of a form against its own rows); (iv) against T0, drawn rotations differ in at most `POLARFT_TAIL_ROT_BLK` = 5
  pairs in every block of 4 tiles (64,000 pairs), and where the rotations agree the distances are equal bit for
  bit. The rows variant's entries must equal T0's.
  - *Amended 18:35, before any official judged run of the tail* (decision under delegation 13): gate (ii) is run
    twice, with u = 0 and with u = 2. With u = 0 the draw reaches the first minimum by its own sweep whatever
    minimum the form computed, so the plant of decision 15 "T1 with the first-index rule inverted" passed it
    (`phase2/plants/first_gate/t1_inverted.run.log`: first minima off 0). With u = 2 the target is above every
    cumulative weight, so the form draws its own minimum (the fallback), and the inverted rule is exposed. The
    expected value is unchanged (the host's first minimum); the gate only became stricter. The first agreement
    runs with the u = 0 gate alone passed on seeds 1 to 3 and are kept in `phase2/agree_first_gate/`.
- **The tail's inputs** (decision under delegation 12): K1's P10 source is not in the record, so the seeded rows
  are made here. Per pair a smooth row of distances about 1 (two cosines of amplitude up to 0.3 and 0.1 and
  random phase, plus uniform noise of width 0.02), written as the raw values that the tail's `fma(raw, iw, 1)`
  maps back to it; `iw` = 1 / (2 wsq), wsq uniform in 0.5 to 2 (the toy's form); temperatures 1, 30, 420, 1e4 in
  turn per particle (the polar bench's levels); variates uniform. Planted, by share of the pairs: 0.5 % with no
  valid rotation, 0.5 % with every seventh rotation invalid, 1 % with the minimum tied 37 rotations away, 1 % with
  the minimum at the last rotation (the planted cases make the plants of decision 15 able to fail).

2026-11-26, about 18:01 to 19:00 by the machine's clock, on the M5 Ultra (local), unattended. Base `bb59c21` plus
Phases 0 and 1. No ruling. Evidence under `/Users/hael/agent_runs/mlxf_kernel_forms/scratch/keep/phase2/` (written
`phase2/` below): `agree/` (the judged agreement), `timing/` (the timed steps, `timing.sh`, and `parts2/`, the
3- and 6-process rows, `parts.sh`), `plants/`, `final/` and `checks.log` (the final build), `dev/` (development
runs).

**Files changed:** `src/test/bench/mlxf_bench_kernel_forms.f90` (suites `tail` and `reduce`, the timing protocol;
the probe's kernels moved out); `src/test/bench/mlxf_bench_kernel_forms_src.f90` (new: every source and spec
function of the bench, decision 18); `src/test/framework/mlxf_test_defs.f90` (`FORMS_REDUCE_TOL`);
`src/test/framework/mlxf_test_utils.f90`, `src/test/bench/mlxf_bench_polar_table.f90`,
`src/test/bench/mlxf_bench_projector.f90` (`wait_for_go_file`, rows extended to Phase 2 first);
`doc/code_base_map.md` (regenerated); this plan.

**Exit items.**

- **Builds.** Debug and Release from scratch with `MLXF_WERROR=ON`: 0 compiler warnings, the static gate passes,
  the fast gate 13 of 13 (12.76 s and 10.47 s of tests), installed (`phase2/build_{debug,release}.log`).
  `scripts/check_tree.sh` passes; both formatters ran on every touched Fortran file.
- **Counts and identity** (`phase2/checks.log`): every unit area at Phase 0's count (kernels 1,953; Release
  `unit_core` 214, Debug 216: the allocator's range). The 364-line identity set is equal to Phase 0's byte for byte,
  SHA-256 `e2d65e88...4d33dba5` (`phase2/identity/identity.txt`).
- **Agreement before timing** (decision 5 as frozen above, Release, seeds 1 to 3, two invocations each,
  `phase2/agree/{tail,reduce}_s{1,2,3}_{a,b}.log`; every assertion passing, every digest equal in both
  invocations):

  | Tail, 40 tiles of 16,000 pairs | Repeats | First minima off (u 0 and 2) | Draws off own rows | Rotations against T0, total (largest block of 64,000) | Distances off where they agree |
  | --- | --- | --- | --- | --- | --- |
  | T0, seeds 1/2/3 | equal | 0/0/0 | 0/0/0 | - | - |
  | T1, seeds 1/2/3 | equal | 0/0/0 | 0/0/0 | 6 (1) / 3 (1) / 5 (2) | 0/0/0 |
  | T2, seeds 1/2/3 | equal | 0/0/0 | 0/0/0 | 15 (2) / 10 (2) / 11 (2) | 0/0/0 |

  (*measured*; the bound is 5 a block.) Digests seed 1/2/3: T0 `17697CA918F196CE`, `71650827C9C132F0`,
  `04454939B07DB3DF`; T1 `2B05E6FD4D5B2F47`, `91C8597A5F0211E9`, `D0058EC3A5687F16`; T2 `8DA7F5951B1F7F97`,
  `EB8F98BF9D24AB44`, `D5C831148A935963`. The rows variant's entries equal T0's on every seed.

  | Reduction, 500 x 23 sums over 6,144 terms | Largest error / sum of abs(terms), seeds 1/2/3 | Repeats |
  | --- | --- | --- |
  | R0 serial | 2.378e-07 / 2.860e-07 / 1.665e-07 | equal |
  | R1 serial compensated | 3.21e-09 / 3.22e-09 / 3.29e-09 | equal |
  | R2 threadgroup tree, `simd_sum` | 8.57e-09 / 9.10e-09 / 8.48e-09 | equal |
  | R3 graph `sum` | 8.54e-09 / 7.77e-09 / 6.81e-09 | equal |

  (*measured*; all within `FORMS_REDUCE_TOL` = 4.756e-07; R1's error is 0.011 to 0.020 of R0's.) R2 in Debug on
  seed 2 gives Release's digest (`phase2/final/reduce_s2_debug.log`).
- **Timing** (decision 6; Release, seed 1, one process, two invocations a and b; a warm-up of every form, A-A
  control, five interleaved pairs of medians of 5; the load at most 4 before each step: 3.62 to 3.68 before and
  after, `phase2/timing/*.uptime`; nothing else of the run meanwhile). One evaluation is the 40 tiles queued with
  `mlx_async_eval` and one wait (tail), or one launch of 500 evaluations and its wait (reduce). Ratio = current
  over alternative (*measured*):

  | Suite | A-A floor a / b | Pair | Median ratio a / b | At or above 1.30 | Times (median of 5) | MLX peak | Verdict (decision 3) |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | tail | 0.32 % / 0.06 % | T0/T1 | **3.280 / 3.283** | 5 / 5 of 5 | T0 5.64 ms, T1 1.72 ms | 9.40e8 B both | **T1 preferred** |
  | tail | | T0/T2 | 1.028 / 1.028 | 0 | T2 5.49 ms | 9.40e8 B | **T2 equivalent** |
  | reduce | 0.59 % / 0.62 % (R0) | R0/R1 | 0.859 / 0.857 | 0 | R0 2.07 ms, R1 2.41 ms | 1.35e7 B | **R1 worse** |
  | reduce | | R0/R2 | **8.129 / 8.083** | 5 / 5 | R2 0.255 ms | 1.35e7 B | **R2 preferred** |
  | reduce | | R0/R3 | 2.950 / 2.870 | 5 / 5 | R3 0.70 to 0.75 ms | 2.96e8 B | R3 preferred over R0 |
  | reduce | 10.33 % / 19.13 % (R3) | R3/R2 | 2.312 / 2.354 | 5 / 5 | | | **inconclusive** (its A-A floor is above 10 %) |

  The tail's 3- and 6-process rows (`scripts/run_parts.sh`, `RUN_PARTS_BENCH=bench_kernel_forms`,
  `RUN_PARTS_SUITE=tail`, `RUN_PARTS_LOAD=4`, 40 tiles and 9 passes a part, two rounds of opposite order;
  `phase2/timing/parts2/parts_{t0,t1}.tsv`, every row status `ok`, load 2.81 to 3.32; *measured*):

  | Processes | T0: go to last exit, a / b | T1: a / b | T0/T1 from go to last exit | Summed median rates T0 / T1 (pairs/s) | MLX peak per part |
  | --- | --- | --- | --- | --- | --- |
  | 1 | 0.086 / 0.089 s | 0.047 / 0.055 s | 1.83 / 1.62 | 1.12e8 / 3.13e8 | 9.40e8 B |
  | 3 | 0.131 / 0.129 s | 0.074 / 0.070 s | 1.77 / 1.84 | 1.88e8 / 4.55e8 | 9.40e8 B |
  | 6 | 0.219 / 0.221 s | 0.119 / 0.123 s | **1.84 / 1.80** | 1.87e8 / 4.69e8 | 9.40e8 B |

  So decision 3's 6-process condition for `tail` (at least 1.0) holds. The windows are short (9 passes of 1.7 to
  5.6 ms a part), so these rows carry process start and exit; they are reported, as section 6 says.
- **Hypotheses (frozen in Phase 0) against the result:**
  - (8) T1 preferred: **held** (3.28, *measured*; T0 runs at 0.141 ms a tile here against K1's 0.17). T2
    equivalent in time and within the rotation bound: **held** (1.028; largest block 2 of 5). So, by decision 8:
    K7's pair stage (F1) and K4's per-pair reductions are written a SIMD group per pair; compensated sums stay the
    house default (T2 is 2.8 % faster, below the 5 % that would allow plain sums).
  - (9) R2 preferred over R0: **held** (8.1). R2 preferred over R3: **inconclusive** as a verdict (R3's A-A floor);
    every one of the ten direct pairs is at 2.03 or above, and through R0 the ratio is 2.75 / 2.82 (*derived*:
    R0/R2 over R0/R3, both judged against R0's 0.6 % floor). So R3 is not within 1.30 of R2. R0 and R2
    bit-repeatable: **held**. R1 equivalent to R0 in time: **refuted** (R1 is 14 % slower, 0.857); R1's error at
    most a tenth of R0's: **held** (0.011 to 0.020). By decision 9: K5's fused objective is written as R2.
- **Plants** (decision 15, each in a patched copy built apart in Release, `phase2/plants/<plant>.diff`,
  `<plant>.run*.log`; copies and builds deleted after):
  - T1 skipping the last rotation (`nr = nrots - 1`): fails (first minima off 16,128; draws off 104,494; rotations
    against T0 111,428, largest block 11,270).
  - T1 with the first-index rule inverted (`simd_max` of the minimal lanes' rotations): passed the first form of
    gate (ii) (`plants/first_gate/`), which led to amendment 13 above; with the amended gate it fails (first
    minima off 6,357, the planted ties).
  - R2 without its barrier: fails in 3 of 3 runs (repeats differing 2 of 2, error 6.5e-2 against the 4.756e-07
    bound), so the fallback plant (a wrong order of the SIMD sums) was not needed.
- **`FORMS_REDUCE_TOL` in `mlxf_test_defs.f90` and Progress with its evidence:** above, frozen before seeds 2 and 3.

**Decisions taken under delegation** (numbers continue Phase 1's).

12. The tail's seeded rows are made by the bench (above), since K1's P10 source is not in the record.
13. Gate (ii) amended to run at u = 0 and u = 2 (above): a plant showed the first form could not fail.
14. `RUN_PARTS_BENCH=bench_kernel_forms`, not `kernel_forms` as decision 6 writes: `run_parts.sh` runs
    `test=$RUN_PARTS_BENCH` and reads `$RUN_PARTS_BENCH.tsv`.
15. T1's "first index" is the least rotation among the lanes holding the minimum (`simd_min` of their first
    rotations), not literally the lowest lane: within a block of 32 the two agree, across blocks only the least
    rotation is the row's first minimum.
16. T1's W is the `simd_sum` of plain lane partials (the plan does not say whether the lanes compensate); its draws
    meet the rotation bound.
17. `reduce` times R0 (the one-thread-per-output form of the tree's kernels) as its current form for R1, R2 and R3,
    and adds a second A-A control on R3 for the pair R3/R2 that decision 9 needs. That control's floor exceeded
    10 % in both invocations, so stop 6 was applied to the verdict judged against it (inconclusive, no rerun) and
    not to the verdicts judged against R0's 0.6 % floor.
18. The reduction's terms are products x(j, e) y(j, k) of two seeded inputs read in the kernel (12 MB and 0.6 MB),
    not a stored term array, closer to K5's terms computed in place; the last 8 of 6,144 terms are zero.
19. `wait_for_go_file` moved to `mlxf_test_utils` (the two benches' identical copies deleted), instead of a third
    copy; the identity set shows the benches unchanged.
20. The 3- and 6-process series was run twice: the first (`phase2/timing/parts_*`) recorded no rates because the
    bench's TSV had no header line, which `run_parts.sh` skips; its go-to-last-exit times (T0/T1 at 6 processes
    1.82 and 1.89) agree with the second, which is the record.
21. Decision 18's condition met: the sources moved to `mlxf_bench_kernel_forms_src.f90`; the main file keeps the
    suites' logic and is 949 lines.

**What it means, in short.** Both reductions that a K plan would write as a kernel are clearly better as a SIMD
group or threadgroup cooperating than as one thread per output: the K1 tail with a SIMD group per pair is 3.3
times faster than the kernel K1 kept, with the same first minima and draws within K1's bound, and still 1.8 times
faster from go to the last exit with six processes sharing the GPU; K5's reduction as a threadgroup tree is 8
times faster than one thread per evaluation and about 2.8 times faster than MLX's graph `sum`. Compensation is
free on the tail (2.8 %) and costs 14 % in the reduction while cutting its error 50 to 90 times. On K1's driver the
tail's ceiling (1.32 to 1.45, Phase 0) is now within reach of the 30 % rule, but no toy changes here: K7 and K4
take the form.

### Phase 3

**Frozen before the runs they judge** (written 2026-11-26 18:55, after development runs of seed 1 and before the
judged runs; no threshold here is new, decision 5's gates are made concrete):

- **`sizes`, the gather:** G1 is G0's source with each template integer read from an int32 input `sz` (`const
  int E = sz[0]; ...` before the unchanged body, derived at run time by `sizes_in_input` from the toy's
  `gather_spec`); on K2's canonical inputs (seeded cube of each parity, (m + 5)^3 with m = 320, the polar points
  of shells 2 to 62 at 182 angles, 11,102 points, 2,500 seeded directions, 64 threads a group) the samples of both
  parities equal G0's bit for bit, both forms bit-repeatable.
- **`sizes`, the insertion (decision under delegation 22):** the current kernel adds with atomics, whose sums
  change between runs (decision 5 itself exempts D0), so "bit for bit" is judged where atomics are exact: one plane
  of `seeded_case` at n = 64 whose data are kept only on pixels with h and k multiples of 6 (their 27-voxel
  windows can never meet: 6 - sqrt 3 > 2 sqrt 3), G0 repeatable and G1 equal to G0 bit for bit. On the batch of
  500 planes the G1 - G0 difference is reported beside G0's own run-to-run difference, not gated.
- **`select`:** the table is uniform in 0 to 1 (seeded, float32), 10,000 by 1,024; in 1 % of the columns (seeded,
  about 12) a second reference is set equal to the first maximum, then one outside the K best equal to the K-th
  value; the gate is exact (K indices and values bit for bit against the host's K rounds of the first maximum);
  E1 without its repair ("e1n") runs against the same gate and is reported; each form bit-repeatable in a
  process and its digests equal over two invocations.
- **The selection's order of the K kept (E1):** a rank by comparisons (larger value, then lower index) sorted
  with `mlx_argsort`; the rank is unique, so no stability of the sort is relied on.

2026-11-26, about 18:27 to 19:20 by the machine's clock, on the M5 Ultra (local), unattended. Base `bb59c21` plus
Phases 0 to 2. No ruling. Evidence under `/Users/hael/agent_runs/mlxf_kernel_forms/scratch/keep/phase3/` (written
`phase3/` below): `agree/`, `timing/` (`timing.sh`), `plants/`, `final/` and `checks.log`, `dev/`.

**Files changed:** `src/test/bench/mlxf_bench_kernel_forms.f90` (suites `sizes` and `select`);
`src/test/bench/mlxf_bench_kernel_forms_src.f90` (`sizes_in_input`, `select_spec` with E2 and E3);
`src/test/bench/mlxf_bench_insert_probe.f90` and `src/test/framework/mlxf_test_defs.f90` (`probe_case` moved to
the defs, `seeded_case` and `window_coefficients` public; rows extended to Phase 3 first); `doc/code_base_map.md`
(regenerated); this plan.

**Exit items.**

- **Builds, counts, identity.** Debug and Release from scratch with `MLXF_WERROR=ON`: 0 compiler warnings, static
  gate passing, fast gate 13 of 13 (12.78 s and 10.60 s of tests), installed (`phase3/build_{debug,release}.log`).
  Unit areas at Phase 0's counts in both builds (core 216, kernels 1,953). The identity set equals Phase 0's,
  SHA-256 `e2d65e88...4d33dba5` (`phase3/identity/`). `bench_insert_probe suite=probe`, whose record moved, passes its
  21 assertions (`phase3/final/insert_probe.log`).
- **`sizes`, G1 equal to G0 bit for bit** (`phase3/agree/sizes_s{1,2,3}_{a,b}.log`, *measured*): the gather's
  55,510,000 samples of both parities equal on seeds 1 to 3, both forms repeatable, digests (seed 1/2/3)
  `21A09F5939E59984`, `9783224DBD8AA6B4`, `55108EE161184892` in both invocations. The insertion on the
  collision-free plane (1,377 voxels reached): G0 repeatable and G1 equal bit for bit. Reported: on the batch of
  500 planes G1 against G0 differs in 221,088 to 222,120 values by at most 6.6e-07 to 1.1e-06 of the largest
  value, G0 against itself in 219,817 to 220,983 by 7.3e-07 to 8.8e-07: the same size, the atomics' order.
- **`sizes`, per launch** (decision 6; two invocations; load 2.69 to 3.81 before and after each step,
  `phase3/timing/*.uptime`; *measured*):

  | Kernel | A-A floor a / b | G0 / G1 median ratio a / b | Times (median of 5) | MLX peak | Verdict a / b |
  | --- | --- | --- | --- | --- | --- |
  | gather, 2,500 directions, both parities | 5.04 % / 1.84 % | 1.009 / 0.994 | G0 5.4 to 5.6 ms, G1 5.2 to 5.5 ms | 1.01e9 B | inconclusive (inside twice the floor) / **equivalent** |
  | insertion, n = 64, 500 planes | 0.61 % / 0.23 % | 0.9995 / 1.0026 | 2.48 to 2.56 ms both | 5.72e8 B | **equivalent / equivalent** |

- **`sizes`, the first evaluation of 8 new values of `npts`** (fresh process per form and set; set 1 npts 10,920 to
  9,646, set 2 9,464 to 8,190, shells dropped in steps, so no value is ever compiled twice; a new value's cost is
  the first evaluation less the second of the same object; `phase3/timing/compile_{g0,g1}_set{1,2}.log`,
  *measured*):

  | Form | First value in the process, set 1 / 2 | Each further new value: median of 7, set 1 / 2 (range) |
  | --- | --- | --- |
  | G0, templates (a new source per value) | 80.2 / 79.2 ms | **42.7 / 42.0 ms** (41.6 to 45.0) |
  | G1, sizes in an input (one source, a new object per value) | 10.1 / 8.8 ms | **3.05 / 2.62 ms** (2.45 to 3.61) |

  A new size costs 14 to 16 times less in G1 (*derived*: 42.7 / 3.05, 42.0 / 2.62).
- **`select`, the exact gate** (`phase3/agree/select_s{1,2,3}_{a,b}.log`, *measured*): E0, E1, E2, E3 equal the
  host's first-maximum rule on all 1,024 columns at K = 3 and K = 10 on seeds 1 to 3, repeatable, digests equal in
  both invocations (E0 seed 1: `BEACC94A718BD9CC` K = 3, `E4E74CD4818CE7D8` K = 10). Planted ties found: 11 to 13
  columns with a tie at the first maximum and 11 to 13 at the K-th value per seed and K. **E1 without its repair
  also passes, 0 columns off in every case** (below).
- **`select`, timing** (*measured*, two invocations):

  | K | Pair | A-A floor a / b | Median ratio a / b | Times (median of 5) | MLX peak | Verdict |
  | --- | --- | --- | --- | --- | --- | --- |
  | 3 | E0/E1 | 1.40 % / 2.53 % (E0) | 0.156 / 0.155 | E0 0.49 ms, E1 3.15 ms | 1.64e8 / 7.07e8 B | worse |
  | 3 | E0/E2 | | 0.519 / 0.510 | E2 0.95 ms | 8.2e7 B | worse |
  | 3 | E0/E3 | | **2.104 / 2.021** | E3 0.24 ms | 8.2e7 B | **E3 preferred** |
  | 3 | E2/E3 | 0.59 % / 5.99 % (E2) | **3.987 / 3.893** | | | **E3 preferred** |
  | 10 | E0/E1 | 0.53 % / 0.91 % (E0) | 0.386 / 0.390 | E0 1.21 ms, E1 3.15 ms | 4.51e8 / 7.08e8 B | worse |
  | 10 | E0/E2 | | 1.162 / 1.173 | E2 1.05 ms | 8.2e7 B | inconclusive (between 1.05 and 1.30) |
  | 10 | E0/E3 | | **4.064 / 4.117** | E3 0.30 ms | 8.2e7 B | **E3 preferred** |
  | 10 | E2/E3 | 5.91 % / 5.72 % (E2) | **3.558 / 3.532** | | | **E3 preferred** |

- **Hypotheses (frozen in Phase 0) against the result:**
  - (10) G1 equivalent per launch: **held** on the insertion in both invocations and on the gather in one
    (inconclusive in the other by its 5 % floor, not refuted). G0's first evaluation per new value at least 40 ms:
    **held** (42.0 and 42.7 ms, every value 41.6 or more). G1's at most 1 ms: **refuted** (2.6 to 3.1 ms; the
    first G1 value of a process 8.8 to 10.1 ms). Decision 10's "if both hold" is therefore not met as written:
    sizes in an input cost nothing per launch and a new value costs about 3 ms instead of 42 ms, but not under 1 ms.
    The report gives the factor; Phase 5 words the skill proposal from these numbers. G1 is not worse than 0.95,
    so decision 10's fallback (templates stay for hot kernels) is not triggered either.
  - (11) E1 without the repair fails the exact gate: **refuted** on MLX 0.32.4, GPU: with 11 to 13 planted ties at
    the boundary per case, `mlx_argpartition` kept the lower index every time, as a stable selection would; MLX
    documents no such order (binding contract, section 10), so this is a finding for an Apple question (Phase 5),
    and the repair stays the correct form. E2 preferred over E0 at K = 10: **not held** (1.17, inconclusive). E3
    preferred over E2: **held** (3.5 to 4.0). So by decision 11: K7 builds E3 (a SIMD group per particle) first;
    E1 is 2.6 to 6.4 times slower than E0 and need not be measured again; whatever wins changes at most 4.5 % of
    K7's pass (*derived*, K7 finding 16).
- **Plants** (each in a patched copy built apart in Release, `phase3/plants/<plant>.diff`, `<plant>.run.log`;
  copies deleted after):
  - G1 with two size entries swapped (`E` and `L`): fails (55,510,000 of 55,510,000 samples differ).
  - E2 with `>=` for `>` (its own insertion only): fails (13 columns off at K = 3, 15 at K = 10).
  - E1 without the repair (`select_partition(b, .false., ...)`): **could not fail** (0 columns off), for the reason
    of hypothesis 11 above. The exact gate it would have to fail is the one the E2 plant fails, and E1's repair is
    exercised by the 11 to 13 planted ties per case; recorded, not replaced (decision 15 names a replacement only
    for R2).

**Decisions taken under delegation** (numbers continue Phase 2's).

22. The insertion's "bit for bit" is judged on a collision-free plane (above): the current kernel's atomics change
    their sums between runs.
23. `probe_case` moved to `mlxf_test_defs` and `seeded_case` and `window_coefficients` made public in Phase 3,
    not Phase 4: `sizes` builds the insertion kernel from `probe_spec`, which takes the record (rule `defs`).
24. A new value's compile cost is the first evaluation less the second of the same object, in two runs on disjoint
    sets of `npts`, so the system's shader cache cannot serve G0 a second time (G1's single source may be served
    from it after its first build; its per-value cost does not depend on that).
25. `select` adds an A-A control on E2 for the pair E2/E3, as `reduce` did for R3/R2; its floors (0.6 to 6.0 %) are
    below 10 %.
26. G1 is derived at run time from the toy's own spec by `sizes_in_input` (the template names become constants of
    the body read from `sz`), so no source of a current kernel is copied.
27. The identifiers `t`, `p` and `q` were renamed in the bench (`tabd`, `part`, `quat`) because rule `ctorexpr`
    treats a name as a handle across the whole file.
28. The `seed=` key of `sizes` seeds the gather's data only; the insertion's planes are `seeded_case`'s own (fixed)
    seed, so its records are equal on every seed.

**What it means, in short.** Sizes as an int32 input cost nothing per launch on either kernel, and a new size
costs about 3 ms (a new object) instead of 42 ms (a new Metal source), so a kernel whose sizes change per call
should read them from an input; the hypothesis' 1 ms was too optimistic. For K7's small-K selection, a SIMD group
per particle is 2 to 4 times faster than the graph of K `maxloc` rounds and 3.5 to 4 times faster than one thread
per particle, and exact; `mlx_argpartition` is the slowest form, and on this MLX it happens to resolve boundary
ties to the lower index, which nothing guarantees.

### Phase 4

**Frozen before the runs they judge** (written 2026-11-26 18:58 by the machine's clock, after the seed-1 calibration
of `insert` at n = 64 and before any run of seeds 2 and 3 or of n = 96; never moved):

- **`FORMS_INSERT_TOL` = 3.6158061349382692e-06** (*measured* then *derived*): twice the largest difference of D1
  from D0 on seed 1 at n = 64 on the GPU, relative to the sum of the voxel's |terms| (numerator's real part,
  imaginary part and density each against its own sum; the sums made by D1 on the data's magnitudes, exact since
  the window's weights and the plane weights are positive), which is 1.8079030674691346e-06. D0 against itself in
  the same run: 1.41e-06 (216,956 of 542,754 values differ), so D1's difference is the size of the atomics' own.
  Evidence `scratch/keep/phase4/insert/agree_n64_seed1_calibration.log` (D1 and D2 repeatable, D2 equal to D1 bit
  for bit). In `src/test/framework/mlxf_test_defs.f90`.
- **The insertion's operational gate** (decision 5 made concrete): each seed is one batch of 500 planes of one
  `seeded_case` of 1,500 planes (seed s takes planes 500 (s - 1) + 1 to 500 s, decision under delegation 29,
  because `seeded_case` takes no seed and its tie-dropping must stay the probe's); D1 against D0 within
  `FORMS_INSERT_TOL`; D2 equal to D1 bit for bit; D1 and D2 bit-repeatable; D0's spread reported. The same gate holds
  at n = 96 (judged on seed 1 there, the timed configuration).
- **The extrapolation rule to n = 160** (decision 12, read, not judged): each form's time per batch is fitted as
  t(n) = t(64) (n / 64)^e with its own exponent e = log(t(96) / t(64)) / log(1.5) from the two measured sizes
  (medians of the timed pairs), and the factor D1/D0 at 160 is the ratio of the two extrapolations. The bounds
  beside it: D0 by the push's n^2 (pixels per plane) and D1 by the walk's n^3 (voxels times planes), the worst case
  for the pull; and both by n^2 (the reached work only), the best.
- **The waits' gate:** F1's listed sums up to each tile's count equal F0's bit for bit, its tail holds the
  sentinel, the counts on the device equal F0's, both repeatable; capacity = ceil(1.25 x the largest count of seed
  1's 40 tiles) = 6,129 (counts 4,717 to 4,903, *exact*), an overflow redoing the pass.

2026-11-26, about 18:43 to 19:15 by the machine's clock, on the M5 Ultra (local), unattended. Base `bb59c21` plus
Phases 0 to 3. No ruling. Evidence under `/Users/hael/agent_runs/mlxf_kernel_forms/scratch/keep/phase4/` (written
`phase4/` below): `insert/` (the calibration), `agree/`, `timing/` (`timing.sh`), `plants/`, `final/` and
`checks.log`, `dev/`.

**Files changed:** `src/test/bench/mlxf_bench_kernel_forms.f90` (suites `insert` and `waits`);
`src/test/bench/mlxf_bench_kernel_forms_src.f90` (`insert_pull_spec`: D1 and D2 from shared pieces);
`src/test/framework/mlxf_test_defs.f90` (`FORMS_INSERT_TOL`); `doc/code_base_map.md` (regenerated, unchanged
lines); this plan.

**Exit items.**

- **Builds, counts, identity.** Debug and Release from scratch with `MLXF_WERROR=ON`: 0 compiler warnings, static
  gate passing, fast gate 13 of 13 (12.66 s and 10.47 s of tests), installed (`phase4/build_{debug,release}.log`).
  Unit areas at Phase 0's counts in both builds (core 216, kernels 1,953). The identity set equals Phase 0's,
  SHA-256 `e2d65e88...4d33dba5` (`phase4/identity/`). D1's digest is the same in Debug and Release
  (`phase4/final/insert_s3_debug.log`).
- **`insert`, agreement** (`phase4/agree/insert_n{64,96}_s*_{a,b}.log`, *measured*; every assertion passing, D1's
  digests equal in both invocations):

  | Case | Voxels (reached) | D1 against D0 / sum of abs(terms), invocations a, b | D0 against D0 | D2 against D1 | Repeats D1, D2 |
  | --- | --- | --- | --- | --- | --- |
  | n = 64, seed 1 | 180,918 (93,994) | 1.32e-06, 1.75e-06 (calibration run 1.81e-06) | 1.39e-06, 1.56e-06 | 0 differing | equal |
  | n = 64, seed 2 | 180,918 (93,940) | 2.00e-06, 1.47e-06 | 1.48e-06, 1.62e-06 | 0 | equal |
  | n = 64, seed 3 | 180,918 (93,947) | 1.50e-06, 1.26e-06 | 1.35e-06, 1.30e-06 | 0 | equal |
  | n = 96, seed 1 | 550,854 (286,698) | 1.37e-06, 1.29e-06 | 2.62e-06, 1.18e-06 | 0 | equal |

  All within `FORMS_INSERT_TOL` = 3.62e-06. D1 digests: n = 64 seeds 1/2/3 `69E0B77A01359E6B`, `6456A4C92FFCE3D2`,
  `3A35338E902BB1EF`; n = 96 `FD58ED624845A5E8`. D0 changes in about 40 % of its values between runs (the atomics).
- **`waits`, agreement** (`phase4/agree/waits_s*_{a,b}.log`): on seeds 1 to 3, F1's listed sums equal F0's bit for
  bit on all 40 tiles (counts 4,664 to 4,922 against the capacity 6,129, no overflow), the tail is the sentinel,
  the device's counts are F0's, both repeatable; F0 digests `EB6BF367F880C319`, `D4A6F12F1C427DF2`,
  `3089208FBBB8DE46` in both invocations.
- **Timing** (decision 6; Release, seed 1, two invocations; load 2.02 to 3.22 before and after each step,
  `phase4/timing/*.uptime`; *measured*):

  | Suite | Pair | A-A floor a / b | Median ratio a / b | Times (median of all pairs) | MLX peak | Verdict |
  | --- | --- | --- | --- | --- | --- | --- |
  | insert n = 64 | D0/D1 | 0.85 % / 5.61 % (D0) | 0.068 / 0.070 | D0 2.56 ms, D1 37.3 ms | 2.21e7 B | **D1 worse** (14.5 times slower) |
  | insert n = 64 | D0/D2 | | 0.059 / 0.062 | D2 42.6 ms | 2.21e7 B | worse |
  | insert n = 64 | D1/D2 | 0.98 % / 0.01 % (D1) | 0.903 / 0.914 | | | **D2 worse** |
  | insert n = 96 | D0/D1 | 0.69 % / 3.13 % (D0) | 0.180 / 0.186 | D0 8.79 ms, D1 48.9 ms | 5.11e7 B | **D1 worse** (5.6 times slower) |
  | insert n = 96 | D0/D2 | | 0.125 / 0.130 | D2 67.9 ms | 5.11e7 B | worse |
  | insert n = 96 | D1/D2 | 16.79 % / 2.15 % (D1) | 0.685 / 0.681 | | | inconclusive (its A-A floor is above 10 %) / **worse** |
  | waits | F0/F1 | 1.11 % / 1.25 % (F0) | **2.418 / 2.375** | F0 23.7 ms, F1 9.96 ms a pass of 40 tiles | 5.8e8 / 1.5e9 B | **F1 preferred** |

  The cost of one wait inside the busy queue: (23.7 - 9.96) / 40 = **0.34 ms** (*derived*), beside K8's 0.17 ms on
  an idle one. F1 holds 2.6 times F0's peak (every tile's product queued at once).
- **The factor D1/D0 at two sizes and its extrapolation** (rule frozen above, *derived* from the medians): D1/D0 =
  14.5 at n = 64 and 5.6 at n = 96. Exponents e(D0) = 3.04 and e(D1) = 0.67; at n = 160, D0 41.5 ms a batch (K2
  measured 37 ms there, *measured*: the fit holds) and D1 68.8 ms, a factor of **1.66**. The frozen bounds (36.4 if
  D0 grew as n^2 and D1 as n^3, 14.5 if both as n^2) do not contain it: the measurements contradict both
  assumptions. Between 64 and 96 the push's time grows as n^3 (the cause is not measured here), and the pull's
  grows far slower than its n^3 walk; a likely reason, not measured, is that at n = 64 its launch is bound by the
  slowest tile, which meets every plane. The extrapolation is read, not judged; K6
  measures the pull at n = 160 on its own gates.
- **Hypotheses (frozen in Phase 0) against the result:**
  - (12) D1 and D2 bit-repeatable: **held**. D1 at most 3 times slower than D0 at n = 64: **refuted** (14.5 times).
    D2 preferred over D1: **refuted** (D2 is 9 to 14 % slower at n = 64 and 39 to 47 % slower at n = 96; staging the
    patch costs more than the reads it saves). So for K6 (decisions 8, 12, 13): the pull is exact and repeatable
    (each voxel's sum differs from the atomic push by no more than the push differs from itself) but much slower
    at small n, with a factor that shrinks with n (1.7 extrapolated to n = 160); staging is not worth keeping as a
    variant; the atomic push stays the fast reference.
  - (13) F1 preferred over F0: **held** (2.4). So K3's candidate B and K6's sorted form size their buffers by a
    persistent capacity with a sentinel and one wait per pass.
- **Plants** (decision 15; each in a patched copy built apart in Release, `phase4/plants/<plant>.diff`,
  `<plant>.run*.log`; copies deleted after):
  - D1 dropping the conjugate pixels (`k > 0` skipped): fails (D1 against D0 9.3e+03 of the sum of |terms|).
  - D2 without its second barrier: fails in 3 of 3 runs (repeats differing 2 of 2, 210,000 values off D1).
  - F1 with the sentinel mask one short (`<` for `<=`): fails (listed sums differing on all 40 tiles).

**Decisions taken under delegation** (numbers continue Phase 3's).

29. Each seed of `insert` is one batch of a `seeded_case` of 1,500 planes (above): the probe's case generator has
    its own fixed seed and its tie-dropping must not be bypassed.
30. The sums of a voxel's |terms| that scale `FORMS_INSERT_TOL` come from D1 run on the data's magnitudes (exact:
    the weights are positive), not from the double-precision oracle; each part (real, imaginary, density) is
    scaled by its own sum.
31. D1 and D2 read their sizes from an int32 input `par` (Phase 3's finding) and test each plane against the tile's
    centre with a reach of 9 voxels (a tile's half-diagonal 6.06 plus a voxel's 2.60, rounded up); the patch of D2
    is 24 x 24 pixels with a margin of 3, which covers the projection of an 8^3 tile (at most 21 pixels a side).
32. `insert` adds an A-A control on D1 for the pair D1/D2 and `waits` times one pass of 40 tiles as an evaluation;
    stop 6 was applied to the one verdict whose control exceeded 10 % (D1/D2 at n = 96, invocation a).
33. The waits' stage 2 sums, for each listed pair, both of its row halves over the 183 bins gathered by the listed
    index (a reduction that reads through the compacted list); the mask lists a pair when its seeded variate is
    below 0.3.

**What it means, in short.** Waiting once per pass on a persistent buffer instead of once per tile makes the
two-stage pass 2.4 times faster, and a wait inside a busy queue costs about 0.34 ms, twice K8's idle wait. The
insertion as a pull is exactly what the push computes up to the push's own rounding noise, and it is
deterministic, but at n = 64 and 96 it is 15 and 6 times slower than the atomic push; staging the plane's pixels
in threadgroup memory makes it slower still. The pull's case at n = 160 rests on K6's own measurement.

### Phase 5

2026-11-26, about 18:56 to 19:20 by the machine's clock, on the M5 Ultra (local), unattended. Base `bb59c21` plus
Phases 0 to 4. No ruling. Evidence under `/Users/hael/agent_runs/mlxf_kernel_forms/scratch/keep/phase5/`
(`gates.sh`, `gates.log` and the logs beside it).

**Files changed:** `doc/implementation_notes/planned/mlxf_mlx3d_lessons.md` (revised, decision 17);
`doc/collaboration/apple_questions.md` (question 26 updated, 36 new); `doc/policies/binding_contract_policy.md`
(section 12, "Measured by the kernel-forms benchmark"); `doc/policies/test_environment_policy.md` (the bench's
paragraph); `doc/implementation_notes/planned/mlxf_roadmap.md` (row 2f); `doc/history/2026-11.md` (the entry);
`doc/implementation_notes/README.md` (the index); `doc/implementation_notes/completed/mlxf_kernel_forms_report.md`
(new); this plan (status line, Progress).

**Exit items.**

- **Every document row of the file table written:** the seven rows above; the Fortran rows' last edits were Phase 4's.
- **The lessons note** (decision 17): status line "reviewed and measured by run `mlxf_kernel_forms`, 2026-11-26";
  the review's corrections in place, each marked **corrected** with its file and procedure (P2's stable sort, P3
  the viewer's path, mlx3D evidence for threadgroup memory only, the omitted `nn/fused_mlp.py` result, K5's 23
  sums, MLX's library key); a section "What was measured" with the seven suites' verdicts; proposed decisions 1 to
  5 each with a line (measured, measured in part, or still a proposal) and the plan that owns it.
- **Apple question 26 updated** with the probe's numbers and source path and the pull's result; **question 36**
  new (the order of `argpartition` on ties). Neither sent.
- **The last phase's gates** (`phase5/gates.log`): Debug and Release from scratch with `MLXF_WERROR=ON`, 0 compiler
  warnings (the one "warning" line is the static gate's note on the untracked new sources), fast gate 13 of 13 in
  both; the unit areas at Phase 0's counts (core 216 Debug, 214 Release: the allocator's range; kernels 1,953);
  the identity set equal to Phase 0's, SHA-256 `e2d65e88...4d33dba5`; **the Release fast gate 10 times of 10**,
  10.44 to 10.51 s of tests (*measured*, bound 38.74 s); `scripts/check_tree.sh`, `scripts/check_embed.sh`,
  `scripts/check_toy_offstate.sh --exec` (the host table equal to the executable's, 135 lines),
  `scripts/check_install.sh` and `scripts/release_gate.sh --allow-dirty` ("RELEASE GATE PASSED: bb59c21-dirty
  (mlx-fortran 0.1.0, mlx-c 0.8.0), Debug and Release, on Apple M5 Ultra, 79 s",
  `phase5/release_gate_bb59c21-dirty.log`) pass. The gate's export tree (`build_release_gate/`, ignored by git)
  was deleted after its log was copied.
- **The report** ends with a commit message without attribution that names the three new files.
- **The plan's status line says delivered.**

**Decisions taken under delegation.**

34. The lessons note's "What was measured" holds seven suites (`probe` included, decision 17 says six tables), and
    its proposed decisions became section 8.

**What it means, in short.** The record is complete: the note, the policies, the Apple questions, the roadmap, the
history and the report say what was measured and what the K plans take; every last gate passes on the final tree.

## The report

Written by Phase 5 as `doc/implementation_notes/completed/mlxf_kernel_forms_report.md`: what was learned (the
seven tables and the review's corrections first); what changed, phase by phase, with file counts; decisions taken
under delegation; deviations, including expected effects that did not occur and every file changed outside the
table; evidence against the baseline (digests, counts, plants, builds, loads); what the K plans take (the table
above, filled); left open for the maintainer (the skill lines, the note's proposals still open, the Apple
questions); a commit message without attribution or co-author line that names every new file.
