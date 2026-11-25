# K1: the fused tail of the dense score (run `mlxf_kernel_k1`, on the M5 Ultra)

Status, 2026-11-25: **delivered; kept by the maintainer's ruling R2** (Progress, "Ruling R2 and Phase 4"; report [`mlxf_kernel_k1_report.md`](../completed/mlxf_kernel_k1_report.md)): the fused tail is 1.65 to 1.80 times the compiled tail's rate, selectable, the default `graph`. Planned and ruled (the maintainer's go); run in the session on the M5 Ultra, in order K1, K8, K2. Deliverable K1 (A1) of [`mlxf_kernel_families.md`](mlxf_kernel_families.md),
the roadmap's rank 2. Base: the commit that holds this plan (the maintainer commits it with the pending work:
the Metal kernel wrapper, the n-dimensional FFTs, the linear algebra and the oracles; the run pins its hash in
Phase 0). The code this note was checked against is `1e0ae97` with the working tree of 2026-11-25. SIMPLE is
read at `d354efee2`. Supersedes: none. Depends on:
- the custom Metal kernel wrapper, `type(mlx_metal_kernel)` (validated: yes, parity Phase 10, `unit_fast`);
- the refactored polar toy and its dense-driver baseline (validated: yes, run `mlxf_toy_arch`);
- the roadmap's decisions 8, 9 and 12 (validated: ruled) and 15 (validated: no; it stands as recommended
  since the maintainer's go of 2026-11-24 and is open to the review).

## 1. Why

The dense score is the one GPU kernel that is proved: 1.76e7 pairs per second on the M5 Ultra, 4.69 times
SIMPLE's 30-thread rate (*measured*, run `mlxf_m1_m5`). Its last stage, the distances and the posterior draw,
is the largest in the profile: 0.90 of 1.93 s with an evaluation barrier after each stage, before the
products (0.56 s) and the inverse transform (0.42 s) (*measured*). That stage is about twenty array
operations over a tile's rows, compiled into one function: it streams twelve row-sized temporaries per tile
where the result is 8 bytes per pair. A custom Metal kernel can read each pair's row once and write the
entry. K1 writes that kernel on the best-understood toy, and it is the first use of the Metal kernel wrapper
by a toy: what it learns about threadgroups, kernel objects and repeatability serves K2, K4, K5 and K6.

The kernel is kept only if the canonical driver gains more than 30 % (roadmap, decisions 9 and 15). The
profile cannot say whether it will: the barriers cost 0.8 s, and the pass that is judged takes 1.13 s without
them (*measured*). Section 2 restates decision 15's target on that pass; Phase 1 measures the ceiling before
the kernel is written.

## 2. Contract

- **Where the code lives:** `src/test/` only, in the toy's modules (`mlxf_toy_polarft_*`), written against
  the public `mlxf` module as a user writes. No file under `src/core/` or `src/defs/` changes. A missing
  wrapper is a stop with a report, never a private binding.
- **What it adds:** a second form of the dense score's tail, selected at run time. The graph form stays, as
  the reference, the CPU path and the default.
- **The off-state invariant.** With the form `graph` (the default) the new code that may run is: the storage
  of the form in the calculator, one comparison where the workspace is prepared and one where a tile's tail is
  applied. No kernel object is built and no Metal source is compiled. It is proved by the digests of the
  graph form (decision 13), which must not move, and by the workspace's count of live handles.
- **What does not change:** the mirrored procedures and their dummy lists (`score_block_posterior` first),
  the tile plans, the particle terms, the products, the inverse transform, the driver, the fixtures, the
  oracle, every frozen bound of `src/test/mlxf_test_defs.f90`.
- **What it mirrors.** Nothing new at the calculator's interface. Inside the workspace the kernel computes,
  for every pair of a tile, what SIMPLE's `draw_posterior_rvec` computes for one pair
  (`src/main/pftc/simple_polarft_corr.f90`: `euclid_dists_from_crvec`, then `draw_posterior_row` of
  `src/main/strategies/search/probabilistic/simple_eul_prob_tab_utils.f90`). The kernel takes that name.

### What the check found (2026-11-25)

- **What the tail is in the toy.** `polarft_workspace_submit` (`src/test/mlxf_toy_polarft_workspace_score.f90`)
  builds, per particle tile and reference tile, the packed product (`matmul`), the rows by
  `inverse_transform` (`mlx_irfft` over the bins, `n = nrots`) and then `apply_tail`. The tail is
  `tail_graph`, reached through `polar_tail_callback` and the compiled function `self%tail`, which
  `polarft_workspace_new` (`_lifecycle`) makes with `mlx_compile(f, shapeless=.false.)`. Its inputs are the
  rows `raw` (nrots, rt, bt), `iw` = 1/(2 wsq) and the inverse temperatures (1, 1, bt), and the variates
  (rt, bt). It computes:
  1. the distance `d = raw * iw + 1` for every rotation, the invalid marker where `d` is not at most
     `POLAR_DIST_MAX` (a NaN included);
  2. the row's minimum over the valid rotations and its first position;
  3. the weights `exp(-(d - dmin) * temp)` where valid and the argument is below `POLAR_ARG_CUTOFF` (80),
     their sum W and their cumulative sum over the rotations;
  4. the first rotation whose cumulative weight reaches `max(u W, POLAR_DRAW_FLOOR)`, else the minimising
     rotation; a row without a valid rotation gives (invalid, 1);
  5. the distance at the drawn rotation.

  Every reduction runs over dimension 1, the rotations. The outputs are `dists` (rt, bt) float32, `irots`
  (rt, bt) and, only when the block asks for them, the rows `d` (nrots, rt, bt). Each tile is queued with
  `mlx_async_eval`; the tiles' entries are concatenated on the device.
- **What leaves the GPU.** `polarft_workspace_collect` copies `dists` and `irots` (rpad, bpad) to the host:
  8 B per padded pair, 163.8e6 B per pass of case `2500_4` (*derived*: 2 halves of 10,000 by 1,024). The
  copy-out and the host's part took 0.026 to 0.028 s of a pass (*measured*). The rows leave only in the
  testers and the accuracy suite.
- **What SIMPLE's tail is.** `score_block_posterior` (`src/main/pftc/simple_polarft_block.f90`) runs one
  `cgemm` per bin per tile of `PFTC_BLOCK_NR` = 32 references for at most `PFTC_BLOCK_NB` = 16 particles, one
  batched inverse transform per particle and tile, and then per pair a keyed variate (`rnd_keyed` of
  `rnd_draw_key`) and `draw_posterior_rvec`. Its caller is `process_block`, contained in `fill_tab_range`
  (`src/main/strategies/search/probabilistic/simple_eul_prob_tab.f90`), which stores each pair as
  `prob_dense_entry(dist, irot)` in `rows_batch`: the same 8 B per pair.
- **How the toy's tail differs from SIMPLE's.**
  - SIMPLE forms the distance in double precision (`1 + r / norm`, `norm` = wsq times 2 nrots, FFTW's
    unnormalised transform) and rounds it once; the toy forms it in float32 from `iw` rounded to float32 and
    MLX's normalised transform.
  - SIMPLE sums the weights and the cumulative weights in double precision in one order; the graph form sums
    in float32 in MLX's orders, `sum` and `mlx_cumsum` separately.
  - SIMPLE skips a non-finite distance; the graph form marks a NaN and a distance above the limit invalid,
    and would take a distance of minus infinity as valid. Seen, not changed here.
  - The variates are the fixture's, handed in per block; SIMPLE draws them inside the scorer.
- **Which objective the tail serves.** `score_block_posterior` stops unless `objfun=euclid`. The tail is the
  Euclidean loss with the shell weights k / sigma2 and its posterior draw. It serves neither of SIMPLE's two
  correlations: not the memoised unweighted one of `gen_corrs`, nor the k-weighted one of the direct and
  shift-map paths (`gen_corr_cc_for_rot_8_noshift`). The correlation finish is K7's (A4).
- **What decision 15's target rests on.** Its arithmetic (1.93 / (1.03 + 0.90 / x) = 1.3 at x about 2.0) takes
  the barriered stages as additive. The pass the driver runs has no barrier and takes 1.13 s (*measured*: "the
  barriers cost 0.8 s against the 1.13 s unbarriered pass"). On it, a 30 % gain is a saving of 0.26 s
  (*derived*: 1.13 (1 - 1/1.3)). How much of the 1.13 s the tail takes is not known.
- **What the baseline's two numbers hold.** The time from go to the last exit (6.00 to 6.09 s) holds the
  upload of the references (1.09 s), a cold pass (2.09 s) and three timed passes (*measured*): a pass that
  gains 30 % moves it by 15 to 21 % (*derived*). The summed rate takes each process's best of three passes; at
  3 or 6 processes a best pass may be one that ran after the others had finished.
- **The oracles.** `mlxf_oracle_polar` holds the ring oracle of the rows and the draw in double precision on
  the device's own rows (`polar_draw_row`, `polar_draws_off`, tolerance `POLAR_DRAW_TOL` = 1e-4 W, and the
  entry's distance bit for bit that of its row). `mlxf_oracle_polar_objfun` holds the Euclidean loss and both
  correlations by direct sums; it has no posterior draw (its report says so).
- **Counts on the base** (*measured*, runs `mlxf_toy_arch` and the parity phases): suite `polarft_calc` 107
  checks on the CPU device and 99 on the GPU, `eul_prob_tab` 35 per device, `unit_kernels` 1,063, `unit_fast`
  94, `unit_fft` 194, `unit_linalg` 632, `unit_ops` 2,402, `unit_array` 179, `unit_compile` 63, `unit_core`
  80 to 82.
- **The kernel wrapper** (*measured*, parity Phase 10; `doc/policies/binding_contract_policy.md`, section 12).
  A kernel object owns its launch configuration: another grid or output shape is another object, 0.2 ms; the
  first evaluation of a new source took 60 ms. No float64 output. A threadgroup above 1,024 threads fails at
  the evaluation. A source that does not compile fails the evaluation with a status. An input of fewer than
  8 elements arrives in Metal's `constant` address space. A kernel inside a compiled function is tested for
  the traced shapes; a shapeless reuse and outputs above rank 2 are not. mlx-c builds every kernel in MLX's
  default math mode.
- **The queue.** K3 and K4 edit the same workspace files and build on this tail: they start after K1's
  result is committed. The rest of parity touches `src/test/mlxf_test_defs.f90` and the registry: one run at a
  time on the M5.

## 3. Decisions and rulings

**Ruled (2026-11-25, Hans: "Go", on the request that set out these decisions with their recommendations): every decision of this section as recommended.** Decision 18's judged splits, reserved in section 6, are ruled with the rest. The order of the runs is K1, then K8, then K2, one at a time on the M5 Ultra, each from the state that holds the previous one's verified result.

1. (2026-11-25, recommended) **The tail is the distances and the draw.** The kernel starts from the rows the
   inverse transform returns and ends at the entries. The inverse real transform stays `mlx_irfft`. The design
   note's A1 names the transform as part of the kernel. A direct inverse transform in a kernel costs 364 by
   183 complex multiply-adds per pair, about 5.3e5 flop, 1.1e13 per pass of 2.0e7 pairs: about 1.6 s at the
   rate the products reach (*derived*: 3.7e12 flop in their 0.56 s), against a transform stage of 0.42 s. It
   is not written here.
2. (2026-11-25, recommended) **Two forms, selected at run time.**
   - `POLARFT_TAILS` in `src/test/mlxf_test_defs.f90` has the members `graph` and `metal`.
   - `polarft_calc%set_tail_form( self, form )` is an addition (ledger: SIMPLE has one CPU kernel). It marks
     the reference bins stale, as `set_tile_plan` does; the form travels to the workspace in
     `polarft_tile_spec`.
   - The default is `graph` on every device. With `metal` on the CPU device `memoize_ref_bins` refuses with a
     reason in `message()`, and the calculator scores with `graph` after the form is set back.
   - The driver does not change: it holds no MLX state.
3. (2026-11-25, recommended) **What the kernel reads and writes,** per tile; float32 and int32 only, no
   float64, and no complex64 (the complex stage ends before the inverse transform). Sizes at the canonical
   plan 64 by 250 with nrots 364 (*derived*):

   | Buffer | Fortran shape | dtype | Elements | Bytes | What |
   | --- | --- | --- | --- | --- | --- |
   | in `raw` | (nrots, rt, bt) | float32 | 5,824,000 | 23.3e6 | the inverse transform's rows; a pair's row is contiguous |
   | in `iw` | (1, 1, bt) | float32 | 64 | 256 | 1 / (2 wsq) per particle |
   | in `temps` | (1, 1, bt) | float32 | 64 | 256 | inverse temperature per particle, not negative |
   | in `u` | (rt, bt) | float32 | 16,000 | 64,000 | the pair's variate |
   | in `par` | (8) | float32 | 8 | 32 | `POLAR_DIST_MAX`, `POLAR_DIST_INVALID`, `POLAR_DIST_VALID`, `POLAR_ARG_CUTOFF`, `POLAR_DRAW_FLOOR`, three zeros |
   | out `dists` | (rt, bt) | float32 | 16,000 | 64,000 | the distance at the drawn rotation |
   | out `irots` | (rt, bt) | int32 | 16,000 | 64,000 | the drawn rotation, 1-based |
   | out `rows` | (nrots, rt * bt) | float32 | 5,824,000 | 23.3e6 | every distance with the invalid marker; rows variant only (decision 7) |

   The outputs have the graph form's shapes and dtypes, so the concatenation and the copy-out do not change
   (the dtype of the graph form's `irots` is read in Phase 1; int32 is expected). Padded pairs are computed
   as the graph form computes them: equal work.
4. (2026-11-25, recommended) **One thread per pair; the threadgroup stays under the limit by construction.**
   - The grid is `[rt * bt, 1, 1]`: 16,000 threads at the canonical plan, 12 on the fixture (rt 3, bt 4),
     5.0e6 at the largest plan of the sweep's grid. Thread `e` handles the pair at array element order
     `e + 1` of (rt, bt) and loops over its own row of nrots values. No threadgroup memory, no barrier, no
     atomic output.
   - The threadgroup is `[min(POLARFT_TAIL_TG, rt * bt), 1, 1]`. `POLARFT_TAIL_TG` is chosen in Phase 1 among
     32, 64, 128, 256, 512 and 1,024 (the device's limit, *measured*) by the isolated timing of a canonical
     tile, and frozen there. If no candidate is faster than 64 by more than 3 %, it is 64, the wrapper
     tests' value.
   - The workspace refuses a plan whose `rt * bt * nrots` does not fit a 32-bit unsigned index (4.29e9;
     the canonical plan uses 5.8e6).
5. (2026-11-25, recommended) **The kernel's arithmetic,** per pair, in three sweeps of its row:
   1. `d = fma(raw, iw, 1)`; the invalid marker where `d` is not at most the limit; the first minimum among
      the valid rotations. One operation defines the distance, so the entry's distance and the row's are the
      same bits wherever they are computed.
   2. the weights as in the graph form, their sum W by a compensated sum in float32;
   3. the same compensated sum again, stopping at the first rotation where it reaches `max(u W, floor)`; if
      none does, the minimising rotation. A row without a valid rotation gives (invalid, 1).

   The weights are recomputed in the third sweep; no array of nrots values is held per thread. W and the
   cumulative sum come from one sequence of operations, so they agree at the last rotation (the graph form's
   two reductions need not). The comparisons are the graph form's, so the forms classify a distance alike,
   minus infinity included. If Phase 1 shows that the default math mode does not honour the compensation,
   the sums are plain sequential float32 sums (relative error at most 364 x 2^-24 = 2.2e-5, *derived*, inside
   the draw's 1e-4), and Progress says so.
6. (2026-11-25, recommended) **One source, one object per workspace.**
   - The source is one character constant. It reads nrots, rt and bt from `raw_shape` and `u_shape`, and the
     constants from `par`, which the workspace builds once from `mlxf_test_defs`. One Metal compilation
     therefore serves every tile plan and both parities: 60 ms once per process (*measured* for a first
     source), at the first tile's evaluation, inside the warm-up pass and outside the timed passes.
   - Tiles are always full, so a workspace has one tile shape: one kernel object per workspace, two per
     calculator, built in `polarft_workspace_new` (so in `memoize_ref_bins`, once per tile plan) where the
     compiled tail is built today, and released with the tiles. That is 0.4 ms (*derived*: 2 by 0.2 ms)
     beside an upload of 1.09 s.
   - With the form `metal` the workspace builds no compiled tail; with `graph` it builds no kernel.
7. (2026-11-25, recommended) **The rows come from the kernel too.** The checks read the device's own rows
   and require the entry's distance to be its row's, bit for bit. When a block asks for the rows, the
   workspace applies a second kernel, the rows variant: the same statements plus one that writes `d`, with a
   third output of rank 2, (nrots, rt * bt), reshaped to (nrots, rt, bt) in the graph. It is a second source
   (60 ms once, in tests and the accuracy suite only) and a second object per workspace, built on the first
   block that asks. The two sources are assembled from the same character constants. Their entries must be
   identical bit for bit (decision 12). The design does not use an output above rank 2.
8. (2026-11-25, recommended) **The kernel is applied directly, outside any compiled function.** A compiled
   function around one kernel node has nothing to fuse, and a kernel object is for one shape, so a shapeless
   trace has no use for it. Phase 1 measures the per-tile time of the kernel applied directly and inside a
   function compiled with `shapeless=.false.`, and records what a shapeless function does at the traced shape
   and at another. The kernel moves inside only if that is at least 10 % faster per tile (*guessed*
   threshold; not expected); the choice is frozen in Phase 1.
9. (2026-11-25, recommended) **Residency and waits do not change.** Resident: the reference tiles of both
   parities, 7.14e9 B, as today; the two kernel objects and two arrays of 8 values are added. A tile in
   flight holds its rows (23.3e6 B), the copy of its variates and its entries, where the graph form's
   estimate counts twelve row-sized temporaries (0.326e9 B a tile against 0.070e9 B, *derived* from the
   benchmark's formula). The host waits where it waits today: in `memoize_ref_bins` and in `collect_block`.
   `submit_block` returns while the device works. Phase 1 records where the 60 ms of the first compilation
   lands.
10. (2026-11-25, from the roadmap's decision 8) **Against the oracle the fused form meets the bounds that are
    already frozen;** none is added and none moves. They were calibrated on the CPU device with the graph
    form (*measured*); a Metal kernel has no CPU path, so it is judged on the GPU only.
    - Fixture (suite `polarft_calc`, seed 2): row error at most 2 x 2.3972e-7 = 4.794e-7; the minimising
      rotation differs in at most max(2 x 0, 1) = 1 pair; no entry of wrong validity; no draw outside its
      interval by more than 1e-4 W; the entry's distance is its row's.
    - Block (`bench_polar_table suite=accuracy`, seed 2, 64,000 pairs): row error at most 2 x 7.2526e-7 =
      1.4505e-6; at most max(2 x 2, 5) = 5 pairs.
    - The graph form on the GPU measured 6.514e-7 and 0 pairs on the block (*measured*, run `mlxf_m1_m5`).
11. (2026-11-25, recommended) **Against the graph form the tolerances are measured on seed 1 on the GPU,
    frozen, and judged on seeds 2 and 3** (the fixture) and on the seed-2 block. Both forms read the same
    rows `raw`.
    - `POLARFT_TAIL_ROW_TOL`: the largest difference of the two forms' rows, in the normalisation of
      `polar_compare_rows`. Frozen as twice the seed-1 value and not below 2^-23 = 1.19e-7 (*derived*: one
      unit in the last place, the fused multiply-add against a product and a sum).
    - `POLARFT_TAIL_ROT_FIX` and `POLARFT_TAIL_ROT_BLK`: the pairs whose drawn rotation differs between the
      forms. Frozen as max(2 n, q) with n the seed-1 count and q the house floors 1 (fixture) and 5 (block).
    - Where the rotations agree, the distances agree within the row tolerance. Where they differ, each
      form's draw must hold on its own rows (decision 10), so a difference is two valid draws at a boundary
      of the cumulative weights.
    - The constants are written to `src/test/mlxf_test_defs.f90` and to Progress, with the file's checksum,
      before the first run on seed 2 with the form `metal`.
12. (2026-11-25, from the roadmap's decision 8) **Repeatability is its own gate,** bit for bit, on one GPU
    configuration and tile shape, with the form `metal`:
    - the fixture: three fills of one calculator, a calculator made again, one slot and two, outer batches of
      different sizes, the rows variant against the entries-only kernel: every entry `bits_equal`;
    - every threadgroup candidate of decision 4 gives the same bits (Phase 1);
    - the block: the accuracy suite's schedule identity (three repeats, outer batches, teams, two slots);
    - the bench: every digest of `suite=time` equal in two invocations, per part.
13. (2026-11-25, recommended) **The graph form is proved unchanged by its digests.** The digest lines of
    `bench_polar_table` that run `mlxf_toy_arch` froze for the dense suites are taken twice on the base in
    Phase 0 (GPU: `accuracy`, `time` at one part and at three, `profile`; CPU device: `accuracy`, and `time`
    once). Where they equal the recorded ones they are the target; if both Phase 0 runs agree with each other
    and not with the record, they are frozen anew with a note. After Phases 2 and 3 the form `graph` gives
    the same lines.
14. (2026-11-25, recommended) **Every gate has a planted violation,** made by a temporary edit of the
    kernel's source or of the tester, shown to fail with the assertion named, and reverted; the file's
    checksum before and after, and the failing output, are kept. The plants:
    1. `+ 1` dropped from the distance: the rows' bound fails;
    2. the rotation written 0-based: the convention check fails;
    3. the variate read at the transposed position: the draw check fails;
    4. the cutoff comparison removed: the fallback test's cutoff assertion fails;
    5. the invalid marker not applied: the validity count fails;
    6. the temperature ignored: the forms' rotation bound fails;
    7. the rows variant's statement for the fallback changed to rotation 1: the identity of the two kernels
       fails on the fixture's rows that fall back (u at or above 1);
    8. one bit flipped in a repeat's copy: the repeatability comparison fails;
    9. the default form set to `metal`: the graph form's digests and the live-handle count fail;
    10. the new addition's line removed from `scripts/toy_mirror.txt`: rule `mirror` fails.
15. (2026-11-25, recommended) **What is timed: the steady pass of the canonical driver.** A pass is one fill
    of the process's particles through `eul_prob_tab%fill_tab_range`, both halves, from the memos to the
    entries in Fortran arrays: the variates, the staging, the submission, the device's work, the
    synchronisation and the copy-out (decision 15's denominator). `suite=time` gains the key `passes=`
    (default 3, the rows of today) and two columns at the end of its row: the passes and their median wall.
    - A process's rate is its pairs over its median pass. The median leaves out a pass that ran before the
      others started or after they finished.
    - A split's rate is the sum of its processes' rates; a split's pass time is the case's pairs over it.
    - `passes=9` on case `2500_4` and `passes=36` on `2500_1`: about 10 s of timed passes for one process
      (*derived*: 9 x 1.13 s; 36 x 0.28 s).
    - The time from go to the last exit, the best-of-passes rate, each process's footprint and MLX peak and
      the machine's lowest free memory are reported beside it, as in the baseline.
16. (2026-11-25, recommended) **The splits, and six processes on a reference set that fits.**
    - Case `2500_4` (2,000 particles, 10,000 references per half), tile plan 64 by 250, GPU, full precision:
      1 process of 30 threads and 3 of 10. Six of 5 are not run: the guard predicts 119.6e9 B against 0.8 x
      103.08e9 = 82.46e9 B (*measured* prediction of run `mlxf_toy_arch`). The launcher is called once per
      form to record `not_run`.
    - Case `2500_1` (2,000 particles, 2,500 references per half: one state of 2,500 directions; in the case
      file since run `mlxf_m1_m5`, 1.784e7 pairs per second at one process, *measured*), the same plan: 1, 3
      and 6 processes. The tile shape, and so each tile's tail and the kernel objects, are those of
      `2500_4`; a part holds a quarter of the references. Six parts are predicted at 30e9 to 46e9 B
      (*derived*: 16.5e9 of a part's 20.1e9 B scale with the references; the rest is taken as unchanged for
      the upper figure). The guard decides from the measured splits of that case, with its own series table.
    - Each process holds all the references, as a SIMPLE part does. A part's halves are padded to whole
      tiles: 15 % more pairs are computed at 3 parts of `2500_4` and at 6 of `2500_1` than at one
      (*derived*: 384 for 333 or 334; 192 for 166 or 167), in both forms alike.
    - The roadmap's two conditions of decision 12 (total rate below 0.8 of one process's; summed footprint
      above 51.5e9 B) are reported at every split, not gated. `2500_1` gives the first measurement of six
      parts sharing the GPU.
17. (2026-11-25, recommended) **The timing protocol.** Release, one executable for both forms, the form by
    the key `tail=`. `scripts/run_parts.sh` with `RUN_PARTS_LOAD=4`: a one-minute load of at most 4 before a
    split, `uptime` recorded before and after, no other `mlxf_test_exec`, `cmake` or `gfortran` process (a
    discarded row is repeated). The forms are interleaved, graph first: g, f, g, f, ... Each adjacent pair of
    runs gives one ratio, the fused split rate over the graph split rate.
    - Judged splits (decision 18): 5 pairs each.
    - Reported splits: 2 pairs each.
18. (2026-11-25, recommended; the maintainer's ruling is asked) **The verdict, fixed before the first timed
    row.**
    - **Judged splits:** the two that are SIMPLE's execution model and that the machine can run: 3 processes
      on `2500_4` and 6 processes on `2500_1`. One process on either case, and 3 on `2500_1`, are reported
      and explain.
    - **Kept** if, at both judged splits, the median of the five ratios is at least 1.30 and at least four of
      the five are at least 1.30.
    - **A median between 1.25 and 1.35** at a judged split: five more pairs are taken there, once, and the
      rule is applied to the ten (median at least 1.30, at least eight of ten).
    - **Equal accuracy:** the form `metal` has passed decisions 10 to 12 at the fixture and at the block
      before any timed row.
    - **Otherwise deleted** (decision 20), with the negative result recorded.
    - A stage's timing (`suite=profile`, the isolated tile of Phase 1) explains the result; it does not
      decide.
19. (2026-11-25, recommended) **The ceiling is measured before the kernel is written.** In a copy of the tree
    under the run's scratch directory, never in the run's tree, the body of `tail_graph` is replaced by a
    null tail (the distance of rotation 1 and rotation 1 for every pair, so that the inverse transform is
    still evaluated) and the judged splits are timed against the unchanged tail, 3 pairs each, by decision
    17's protocol. The ratio is what a tail that costs nothing would gain.
    - If its median is below 1.30 at either judged split, no kernel can meet decision 18: Phases 2 and 3 are
      not run, and Phase 4 records the negative result. That is the plan's outcome, not a deviation.
    - Otherwise the ceiling is recorded and the kernel is written whatever the isolated timings say.
20. (2026-11-25, recommended) **What kept and deleted mean.**
    - **Kept:** the fused form stays selectable (`set_tail_form`, `tail=metal`); the default stays `graph`
      (no default before a read on real data; that is SIMPLE's plan). K4 may build on the kernel.
    - **Deleted:** `src/test/mlxf_toy_polarft_workspace_tail.f90` and
      `src/test/mlxf_toy_polarft_tail_tester.f90` go by `rm`; `set_tail_form`, `POLARFT_TAILS`,
      `POLARFT_TAIL_*`, the key `tail=`, the registry row and the ledger lines go with them. That nothing
      else used them is shown by both builds passing, the digests of decision 13 and `unit_kernels` back at
      1,063. The key `passes=`, the median columns and the launcher's column stay: K3 and K4 time with them.
    - The negative result goes to `doc/history/2026-11.md` in the form of SIMPLE's decision log: the
      hypothesis, the fixture, the target set before the run, the measurement that decided, one sentence of
      lesson. The run marks this plan's banner "measured out" and proposes its move to `rejected/`; the
      maintainer moves it with the commit.
21. (2026-11-25, recommended) **A file the table does not name.** The run may add a row for a new
    `src/test/mlxf_toy_*.f90` file before its first edit, with the reason in Progress. No row is added
    outside `src/test/`.
22. (2026-11-25, recommended) **The probes are scratch programs,** Fortran against the Phase 0 Release
    build's module directory and library (as `scripts/check_install.sh` builds its consumer), under the run's
    `scratch/probe/`. They are not added to the repository; their sources and outputs are kept under
    `scratch/keep/phase1/`. What K1 depends on becomes a test in Phase 2.

Defaults taken without a question: the names `POLARFT_TAILS`, `POLARFT_TAIL_TG`, `POLARFT_TAIL_ROW_TOL`,
`POLARFT_TAIL_ROT_FIX`, `POLARFT_TAIL_ROT_BLK`, `set_tail_form`, the submodule
`mlxf_toy_polarft_workspace_tail`, the suite `polarft_tail`, the keys `tail=` and `passes=`; the kernel's
name `draw_posterior_rvec` and its buffer names; the third fixture seed 3; `passes=9` and `passes=36`; the
3 % and 10 % thresholds of decisions 4 and 8.

## 4. Not in this plan

- The inverse transform, the products or the particle terms in a kernel; a change to the tile plans; a
  whole tile compiled as one function.
- A threadgroup that shares one pair's row among its threads, threadgroup memory, atomic outputs: K4 and K6.
- A reduction across references on the device (the best k, the pool): K7 and K4. Arbitrary reference sets:
  K3. The correlation finish: K7.
- The comparison of `mlxf_oracle_polar_objfun` with the ring oracle on the dense fixture: its report gives
  it to K4 and K7.
- A change to the library, the parity ledger, a wrapper, `unit_fast`. A probe's finding about the wrapper is
  reported for the parity plan; the binding policy's section 12 is edited only where it states as untested
  what Phase 1 measured.
- A verdict on a single GPU-owning process: the splits' numbers are reported for it.
- SIMPLE: read at `d354efee2`, never edited, no source copied. Results are toy throughput, not SIMPLE
  speedup.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement keys on the base; baseline | the counts of section 2; decision 13's digests taken twice; with `passes=3` the rows and digests of the base; the baseline and the graph-against-graph control taken; the numbers frozen in Progress |
| 1 | measurement only: probes and the ceiling; no repository file but this note | the probe table complete; the choices of decisions 4, 5 and 8 frozen; decision 19 applied |
| 2 | result-changing on the form `metal`; identical on the form `graph` | decisions 10 to 12 on the fixture, seeds 2 and 3; decision 13's digests; the plants of decision 14; `polarft_calc` 99 and `eul_prob_tab` 35 on the GPU with the fused form |
| 3 | measurement, and the accuracy suite on the form | decisions 10 to 12 on the block before any timed row; decision 18's verdict |
| 4 | documentation, or deletion | kept: the record; deleted: decision 20's proof |

Every phase that changes a source file ends with Debug and Release built from scratch with
`MLXF_CMAKE_ARGS="-DMLXF_WERROR=ON"` and no warning, the fast gate 9 of 9 in both, `scripts/check_tree.sh`
passing, `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` run on every Fortran file touched
(with explicit file names), and the other unit areas at the counts of section 2. `unit_kernels` keeps its
1,063 checks and gains the fused form's; the new count is recorded when it is first measured and held
afterwards. The CTest entries and their budget of 9 do not move.

## 6. Acceptance

- **The exit of K1** (design note, section 8): the polar-table checks pass on the GPU with the fused tail at
  their recorded counts (`polarft_calc` 99, `eul_prob_tab` 35, the accuracy suite's GPU count as Phase 0
  records it with the graph form), and the verdict of decision 18 is taken at 1, 3 and 6 processes as
  decision 16 runs them.
- **Frozen before the run they judge:**
  - decision 10's bounds: frozen before this plan (*measured*, CPU calibration);
  - decision 11's three constants: Phase 2 (fixture) and Phase 3 (block), from seed 1 (*measured* then);
  - decision 13's digests and the graph-against-graph control: Phase 0 (*measured* then);
  - decision 4's threadgroup and decision 5's sums: Phase 1 (*measured* then);
  - decision 18's rule: this section (1.30 is the house rule; the 4 of 5 and the 1.25 to 1.35 band are
    *guessed*).
- **The control of the protocol.** In Phase 0 the judged splits are run graph against graph, 3 pairs each.
  The largest distance of a ratio from 1 is the noise of the protocol. If it is above 0.10 (*guessed*) at a
  judged split, the protocol cannot resolve 30 % there: stop.
- **Hypotheses, each with its measurement** (none is a criterion):
  - H1: the compiled tail takes at least 0.26 s of the 1.13 s pass. Tested by the ceiling (decision 19).
  - H2: the fused tail of a canonical tile takes less than half the compiled tail's time. Tested by the
    isolated tile of Phase 1 and by `suite=profile` in Phase 3.
  - H3: the MLX peak of a process falls, by at most 1.8e9 B of 10.26e9 B (*derived*: about 7 tiles in
    flight, 0.256e9 B each). Tested by the peaks of Phase 3.
- **Reported, not gated:** the splits that are not judged; the times from go to the last exit; the
  footprints, MLX peaks and caches; the roadmap's two conditions; the tightest tolerance at which each form's
  draws hold; the pairs whose drawn rotation differs from the draw on the oracle's rows; the profile's
  stages; the Release clean-build time before and after; the suites' elapsed times.
- **Reserved for the maintainer:** decision 18's choice of the judged splits; whether the kernel's place in
  the workspace reads as integration would need it.

## 7. Common rules and stop conditions

- No file outside the table, apart from decision 21's rows. No bound loosened, no fixture or seed changed to
  pass, no timed run repeated until it passes: the repeats are those of decisions 17 and 18.
- A test executable run directly on the GPU is run with `MLX_ENABLE_TF32=0`.
- Nothing is built on the M5 while a split is timed.
- The run writes its notes with the editor tools. Git is read-only: nothing is committed.
- A failing acceptance is a diagnosis task: the mechanism is found and written down before anything else.

**Stops:**
- a count of section 2 or a digest of decision 13 is not met on the base, or the two Phase 0 runs of a
  digest disagree;
- Phase 0's control is above 0.10 at a judged split;
- the guard does not start a split that decision 16 plans to run (3 processes on `2500_4`; any split of
  `2500_1`);
- the fused form cannot meet a bound of decision 10, or a frozen constant of decision 11 on seed 2 or 3,
  after the mechanism is diagnosed;
- the fused form is not repeatable bit for bit;
- the kernel needs something the wrapper does not offer, or a change to `src/core/` or `src/defs/`;
- a digest of the graph form moves;
- the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
graph form kept and unchanged; the oracle shares no code with the toy; no SIMPLE source copied; the bounds of
decision 10; the repeatability gate; the 30 % of decision 18.

## 8. Phases

### Phase 0, the base and the baseline

1. Record the machine (`uptime`, the compiler, CMake, MLX and mlx-c versions), the base commit and SIMPLE's
   commit. Build Debug and Release from scratch; run the gate; record every area's count and compare with
   section 2.
2. Copy `polar_case.txt` of run `mlxf_toy_arch` (`~/agent_runs/mlxf_toy_arch/scratch/keep/`) into the run's
   `scratch/keep/`; if it is gone, write the cases `2500_4` and `2500_1` from decision 16 (pftsz 182, kfrom
   2, kto 62).
3. Add `passes=` and the two columns to `suite=time`, and the launcher's reading of the median rate with its
   column `sum_median_pairs_per_s`. Nothing else changes. Show that `passes=3` gives the base's rows and
   digests, and that a key the suite does not read still stops the program.
4. Take decision 13's digests twice. Record the accuracy suite's assertion count on the GPU at 16 by 250 and
   at 64 by 250.
5. Take the baseline as run `mlxf_toy_arch` took it (`2500_4`, default passes, 1 and 3 processes, the guard
   at 6), twice. Reported against its report: 6.00 to 6.09 s and 6.36 to 6.71 s, 20.8e9 and 60.3e9 B.
6. Take the graph form by this plan's protocol: `2500_4` at 1 and 3 with `passes=9`; `2500_1` at 1, 3 and 6
   with `passes=36`, each split's guard first; then the control of section 6 at the two judged splits.
7. Run `suite=profile` twice at the canonical plan.
8. Freeze in Progress, each number with its origin: the digests, the counts, the control, each split's rate,
   pass time, footprint and MLX peak with the graph form.

**Exit:** the numbers are frozen; both builds are free of warnings; the gate passes; no stop condition holds.

### Phase 1, the probe

No repository file changes but this note. The probes run on the Phase 0 Release build (decision 22). Each
line of the table below is filled in Progress with what was measured and the file that holds it.

| | Property | What is recorded | What it settles |
| --- | --- | --- | --- |
| P1 | a thread loops over its row of a rank-3 input and reduces it (first minimum and its position), with `raw_shape` | exact agreement with Fortran on a seeded (364, 250, 64) array | the form of decision 4 |
| P2 | comparisons in the default math mode on rows holding a NaN, plus and minus infinity and values at the limit | the classification against the graph form's | decision 5's comparisons |
| P3 | `fma(raw, iw, 1)` and `exp` | bits against Fortran's `ieee_fma`; the largest difference of `exp` from Fortran's, in units of the last place, over 1e6 arguments in [-80, 0] | decision 11's expectation |
| P4 | a compensated sum: 1 followed by 363 terms of 2^-25 | the plain sum (1 expected) and the compensated one (1 + 363 x 2^-25 rounded, expected) | compensated or plain sums (decision 5) |
| P5 | small inputs: bt of 1, 4, 7 and 8; rt of 1 and 3 | whether one source compiles and gives the graph form's entries at each | whether `iw`, `temps` and `u` need padding to 8 elements |
| P6 | outputs: float32 and int32 of rank 2; a float32 output of rank 3 | the results; the rank-3 one for K2 and K5 only | decision 7 holds without it |
| P7 | the threadgroup candidates of decision 4, and a grid of `[rt, bt, 1]` | the time of one canonical tile, median of 5 after a warm-up, for each; the entries' bits across all | `POLARFT_TAIL_TG` |
| P8 | compilation and objects | the first evaluation of the source; a second object with another output shape; the rows variant's source; whether the first compilation is paid in the submission or at the wait under `mlx_async_eval` | decision 6's costs |
| P9 | the kernel in a compiled function | per-tile time directly and inside `shapeless=.false.`; with `shapeless=.true.`, the status, shapes and values at the traced shape and at (364, 100, 16) | decision 8 |
| P10 | the isolated tail: 40 canonical tiles of seeded rows, the compiled graph tail against the prototype kernel | time per tile for each; the entries' bits in three runs and two processes; the dtype of the graph form's `irots` | H2; decisions 3 and 12 |
| P11 | the ceiling (decision 19) | the three ratios at each judged split, and at one process on `2500_4` | H1; whether Phases 2 and 3 run |

The prototype source of P10 is Phase 2's source. A property that fails where the design depends on it (P1,
P2, P5, P6's rank-2 outputs) is a stop unless the table names the fallback.

**Exit:** the table is complete; `POLARFT_TAIL_TG`, the kind of sum and the kernel's place are frozen in
Progress; decision 19's outcome is stated.

### Phase 2, the kernel on the small fixture

1. The submodule `mlxf_toy_polarft_workspace_tail`: the source's constants, the two kernels' specs, their
   construction and release, the application of a tile's tail. `apply_tail` selects the form;
   `polarft_workspace_new` builds what the form needs. `set_tail_form` on the calculator, the vocabulary and
   `POLARFT_TAIL_TG` in the test definitions, the ledger's line.
2. The tester `mlxf_toy_polarft_tail_tester.f90`, suite `polarft_tail` of the area `kernels`: the refusal on
   the CPU device and the return to `graph`; the forms' agreement; the identity of the two kernels;
   repeatability; the small tile plans of P5; the kernel objects' count and their release (100 cycles of
   `memoize_ref_bins` and `kill_ref_bins` leave no live handle); the seed-1 calibration, printed.
3. The suites `polarft_calc` and `eul_prob_tab` run their GPU checks once more with the form `metal`.
4. Build Debug and Release. Run the calibration on seed 1; write decision 11's fixture constants to
   `mlxf_test_defs.f90` and to Progress with the checksum; only then run seeds 2 and 3.
5. Make the plants of decision 14, one at a time, and keep their outputs.
6. Take decision 13's digests with the form `graph` (the CPU device's `time` once).

**Exit:** with the form `metal` on the GPU, `polarft_calc` passes its 99 checks and `eul_prob_tab` its 35 in
Debug and Release; `polarft_tail` passes; the ten plants fail and the restored tree passes; the digests are
those of Phase 0; `scripts/check_rules.py` passes with the new ledger line; the phase's gates of section 5.

### Phase 3, the bench and the verdict

1. The benchmark reads `tail=` in `accuracy`, `time` and `profile`; its estimate counts one row-sized array
   per tile for the form `metal`. The accuracy suite gains the forms' agreement on the block: the seed-1
   calibration printed, the seed-2 block judged. Build both; take decision 13's digests again.
2. **Accuracy first.** `suite=accuracy tail=metal device=gpu` at 16 by 250 and at 64 by 250. First the
   calibration; `POLARFT_TAIL_ROT_BLK` (and the row constant, if the block's seed-1 value is the larger) are
   frozen in `mlxf_test_defs.f90` and Progress; then the judged run. Every assertion of the graph form's
   count passes, the forms' agreement passes, the schedule identity passes. Planted: plants 1, 6 and 8 of
   decision 14 at this size.
3. `suite=profile tail=graph` and `tail=metal`, twice each: the stages, for the report.
4. **Timing.** By decisions 15 to 17, the forms interleaved: `2500_4` at 1 process (2 pairs) and 3 (5
   pairs); `2500_1` at 1 and 3 (2 pairs each) and 6 (5 pairs). The guard is evaluated before each split
   above one process; `2500_4` at 6 is recorded as not run. Every digest of a form is equal across its runs.
5. Apply decision 18. Fill the verdict table in Progress: per split and form the rates, pass times,
   footprints, MLX peaks, the ratios, their median and count at or above 1.30, the roadmap's two conditions.

**Exit:** step 2 passed before step 4 started; the verdict is stated with its numbers and the files that hold
them; no timed row was taken with another build or test process on the machine.

### Phase 4, the record

1. **Kept:** nothing is removed. **Deleted,** or decision 19's early outcome: decision 20's removals and
   proof, then both builds and the gate.
2. Update the documents: the kernel-families note (section 3: what exists, the seam's line on a block in
   flight, the tail among the differences; section 8: K1's row with the result), the roadmap (the rank 2 row;
   under decision 15, what was measured on the unbarriered pass), the test policy's paragraph on the area
   `kernels` and on the benchmark's keys, the plans index, the history (the result, kept or negative, in
   decision 20's form), the binding policy's section 12 and the Apple questions where Phase 1 measured what
   they leave open.
3. Write the report `doc/implementation_notes/completed/mlxf_kernel_k1_report.md` in the order of
   `doc/how2s/how2write_agent_plans.md`, section 8. It holds the probe table, the three hypotheses with their
   measurements, the verdict table, the tolerances with their seed-1 values, the decisions taken under
   delegation, the proposals for `CLAUDE.md` and the skills (not edited), and a commit message that names
   every new file and carries no attribution or co-author line.
4. Mark this plan's banner delivered, or measured out.

**Exit:** the report exists; `scripts/check_tree.sh` passes; both builds are free of warnings and the gate
passes; `git status` shows only file-table paths.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_bench_polar_table.f90` | `passes=` and the median columns (0); `tail=`, the estimate by form, the forms' agreement in `accuracy` (3); `tail=` removed if the form is deleted (4) | 0, 3, 4 |
| `scripts/run_parts.sh` | the median rate read and summed; the column `sum_median_pairs_per_s` | 0 |
| `src/test/mlxf_toy_polarft_workspace_tail.f90` (new) | the fused tail: the source, the kernel objects, the application; removed if deleted | 2, 4 |
| `src/test/mlxf_toy_polarft_workspace.f90` | the form, the kernel components, the interfaces of the tail's module procedures | 2, 4 |
| `src/test/mlxf_toy_polarft_workspace_lifecycle.f90` | the kernels built and released with the tiles | 2, 4 |
| `src/test/mlxf_toy_polarft_workspace_score.f90` | `apply_tail` selects the form; the rows variant when a block asks for rows | 2, 4 |
| `src/test/mlxf_toy_polarft_calc.f90` | `set_tail_form` (addition), the form's member | 2, 4 |
| `src/test/mlxf_toy_polarft_core.f90` | `set_tail_form`'s body | 2, 4 |
| `src/test/mlxf_toy_polarft_memo.f90` | the form into the tile spec in `memoize_ref_bins` | 2, 4 |
| `src/test/mlxf_toy_polarft_tail_tester.f90` (new) | the suite `polarft_tail`; removed if deleted | 2, 3, 4 |
| `src/test/mlxf_toy_polarft_calc_tester.f90` | the GPU checks once more with the fused form | 2, 4 |
| `src/test/mlxf_toy_eul_prob_tab_tester.f90` | the GPU checks once more with the fused form | 2, 4 |
| `src/test/mlxf_test_defs.f90` | `POLARFT_TAILS`, `POLARFT_TAIL_TG`, the three tolerances, the member of `polarft_tile_spec` | 2, 3, 4 |
| `src/test/mlxf_test_registry.f90` | the row `polarft_tail` | 2, 4 |
| `src/test/test.inf` | if needed | 2, 4 |
| `test/CMakeLists.txt` | only if a comment names the area's suites | 2, 4 |
| `scripts/toy_mirror.txt` | the addition's line | 2, 4 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | section 3 and K1's row of section 8 | 4 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | the rank 2 row; the note under decision 15 | 4 |
| `doc/policies/test_environment_policy.md` | the area `kernels` and the benchmark's keys | 4 |
| `doc/policies/binding_contract_policy.md` | section 12, if Phase 1 measured what it states as untested | 4 |
| `doc/collaboration/apple_questions.md` | if a question arises or an answer is measured | 4 |
| `doc/implementation_notes/README.md` | the index | 4 |
| `doc/history/2026-11.md` | the entry | 4 |
| `doc/implementation_notes/planned/mlxf_kernel_k1.md` | this note: Progress, decision 21's rows, the banner | 0, 1, 2, 3, 4 |
| `doc/implementation_notes/completed/mlxf_kernel_k1_report.md` (new) | the report | 4 |

## Progress

(one entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was
met, log paths, decisions taken under delegation, what it means in short)

### Phase 0, the base and the baseline (2026-11-25, 06:45 to 07:24, M5 Ultra, in the session)

**Machine and base.** M5 Ultra (Mac17,15, 30 cores, 103,079,215,104 B), macOS 27.2.1, GNU Fortran 16.2.0, CMake
4.5.1, MLX 0.32.4 and mlx-c 0.8.0 (Homebrew). Base: `1e0ae97` plus the maintainer's uncommitted working tree of
2026-11-25 (44 lines of `git status --short`; checksums of the 121 files under `src`, `scripts`, `test` in
`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/base_checksums.txt`). SIMPLE read at `d354efee2`. Load before the run 1.6 to 1.8 (another process
of the maintainer's).

**Files changed:** `src/test/mlxf_bench_polar_table.f90` (`suite=time` reads `passes=`, default 3; the best pass
is the wall as before, `wall_rep1..3` are the first three passes; two columns at the end of the row, `passes` and
`wall_median_s`; one stdout line with the median), `scripts/run_parts.sh` (each part's median rate, the useful
pairs over the median pass; their sum in `summary.txt` and as the last column `sum_median_pairs_per_s` of the
series table). Nothing else.

| Exit item | Result | Evidence |
| --- | --- | --- |
| Builds on the base | Debug and Release from scratch with `MLXF_WERROR=ON`: 0 warnings, fast gate 9 of 9 | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/build_{Debug,Release}.log` |
| Counts of section 2 (*measured*, both builds) | `unit_core` 82, `unit_array` 179, `unit_ops` 2,402, `unit_linalg` 632, `unit_fft` 194, `unit_compile` 63, `unit_fast` 94, `unit_kernels` 1,063; `polarft_calc` 107 (CPU) and 99 (GPU), `eul_prob_tab` 35 per device. GPU devices: 1 | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/counts_{Release,Debug}.txt` |
| Builds with `passes=` | Debug and Release from scratch: 0 warnings, gate 9 of 9; `scripts/check_tree.sh` passes; both formatters leave the benchmark as it is | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0p/build_{Debug,Release}.log`, `check_tree.log` |
| `passes=3` gives the base's rows and digests | The first 28 columns of the row have the base's layout and values (estimate, peak 1.02573e10 B, cache 3.28128e9 B; walls differ as walls do); digest `3457E99553A08BFD` in both | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/step3/{base,p3}/` |
| A key the suite does not read stops | `suite=time tail=metal` and `suite=profile passes=3` stop with status 2 naming the key; `passes=0` stops too | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/step3/keys_stop.log` |
| Decision 13's digests, twice | Runs a and b equal to each other and to the record of run `mlxf_toy_arch` in every line: `accuracy` CPU (8 lines: `6C2823C473029BD2`, `C8B49BC7A6676AF2` x5, `B754BBDACD79D649`, `1D586C19F54A9F3A`) and GPU (7 lines: `EF6D23726EFF3EF7` x5, `9FADF409D4A20F7D`, `A58EB9A70285325E`); `time` and `profile` GPU `3457E99553A08BFD`; `time` CPU device `4B4FF8EBDEEA9837` (once); `time` at three parts `B69FA174DE317D3C`, `4BFC1DA8533AB2F5`, `8921689A9191A114` (in 9 runs) | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/digests_{a,b}/`, `digests_ab.log`; the parts' in `baseline/`, `protocol/`, `control/` |
| The accuracy suite's GPU count | 76 assertions at 16 by 250 and at 64 by 250 (`device=gpu`); row error 6.514E-07, 0 of 64,000 rotations differing | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/accuracy_counts/` |
| Baseline as run `mlxf_toy_arch` took it, twice | 1 process: 6.048 and 6.050 s, 20.814e9 and 20.813e9 B; 3 processes: 6.564 and 6.482 s, 60.320e9 B summed (lowest free 0.37e9 and 0.47e9 B); 6 processes not run, predicted 119.58e9 B. Against the report's 6.00 to 6.09 s, 6.36 to 6.71 s, 20.8e9 and 60.3e9 B: inside | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/baseline/run_parts.tsv` |
| Graph form by the protocol | the table below | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/protocol/run_parts_2500_{4,1}.tsv` |
| Control of the protocol (graph against graph, 3 pairs) | `2500_4` at 3: ratios 0.9960, 0.9931, 1.0024, largest distance from 1 **0.0069**; `2500_1` at 6: 1.0063, 1.0010, 0.9977, **0.0063**. Both far below 0.10: no stop | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/control.txt` |
| `suite=profile`, twice | wall 1.940 and 2.001 s; stages (terms, products, transform, distances and draw, concatenation) 0.011, 0.551, 0.423, **0.924**, 0.003 s and 0.011, 0.580, 0.430, 0.950, 0.003 s | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase0/profile/p{1,2}/` |

**Frozen: the graph form by the protocol** (*measured*, Release, GPU, full precision, tile plan 64 by 250; the
rate is the sum of the processes' median rates; the pass time is the case's pairs over it):

| Split | Median rate, pairs/s | Pass time, s | Best-pass rate | Go to last exit, s | Summed footprint, B | Largest footprint | Summed MLX peak, B | Lowest free, B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `2500_4`, 1 x 30, `passes=9` | 1.7501e7 | 1.143 | 1.7575e7 | 12.923 | 20.814e9 | 20.814e9 | 10.257e9 | 40.0e9 |
| `2500_4`, 3 x 10 (and the 6 control runs) | 1.6910e7 (1.672e7 to 1.698e7) | 1.183 | 1.92e7 (1.84e7 to 2.13e7) | 13.586 (13.46 to 13.58) | 60.322e9 | 20.108e9 | 29.714e9 | 0.48e9 |
| `2500_4`, 6 x 5 | not run: the guard predicts 119.58e9 B | | | | | | | |
| `2500_1`, 1 x 30, `passes=36` | 1.7687e7 | 0.283 | 1.7909e7 | 10.957 | 8.333e9 | 8.333e9 | 4.810e9 | 51.7e9 |
| `2500_1`, 3 x 10 | 1.6984e7 | 0.294 | 2.07e7 | 11.406 | 23.703e9 | 7.901e9 | 13.673e9 | 37.1e9 |
| `2500_1`, 6 x 5 (and the 6 control runs) | 1.7258e7 (1.681e7 to 1.694e7) | 0.290 | 3.43e7 (3.16e7 to 3.75e7) | 11.709 (11.60 to 11.75) | 45.929e9 | 7.660e9 | 26.155e9 | 14.4e9 |

The new digests of `2500_1` are frozen too: one process `DE754C8B7BDA20E0`; three parts `D853F44ECE19A074`,
`E1AED46E2ACB3AB7`, `C80A13726E0622D6`; six parts `2CE5436CE15ED479`, `2E613BA0C9DC2076`, `B668679C721AE151`,
`237586C19654BBD6`, `EDD04C521081D36C`, `074EAED918B2753C` (identical in all 7 runs).

**The roadmap's two conditions, reported:** total rate over one process's: `2500_4` at 3, 0.966; `2500_1` at 3,
0.960, at 6, 0.976 (*derived*): the first condition (below 0.8) is not met. Summed footprint above 51.5e9 B:
met at 3 processes of `2500_4` (60.3e9 B), not met by `2500_1` (45.9e9 B at six).

**Decisions taken under delegation.**
1. `wall_rep1..3` keep the first three passes and `wall_s` is the best of all passes, so the row's first 28
   columns keep their meaning at any `passes=`; `host_cpu_s` is the mean over the passes. Reason: the base's rows
   come back unchanged at `passes=3`, and the series table's readers keep their columns.
2. `sum_median_pairs_per_s` is the series table's last column, after `keys`. Reason: the guard and every reader
   address the earlier columns by position.
3. The median of an even number of passes is the mean of the two middle ones (not used: 3, 9 and 36 are odd).
4. The digests of decision 13 were taken with the Phase 0 build (`passes=` added), not the bare base: step 3
   shows the two give the same rows and digest, and the record is the target.
5. The baseline's best-pass rate at three processes (3.70e7 in run 1, 1.74e7 in run 2) is not comparable between
   runs: a part's best of three passes may run while the others idle. The median of 9 is stable (control above).

**What it means, in short.** The base is the record's: every digest, every count, the baseline. The protocol
resolves the judged splits to better than 1 % (control 0.0069 and 0.0063 against the 0.10 stop), so a 30 %
change is far above its noise. Three or six processes give 0.96 to 0.98 of one process's rate; six parts of
`2500_1` fit in 45.9e9 B. With the barriers the tail is 0.92 to 0.95 s of the profile's 1.94 to 2.00 s.

### Phase 1, the probe (2026-11-25, 06:55 to 07:58, M5 Ultra)

No repository file changed but this note. The probes are scratch programs built against the Phase 0 Release build
(`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase1/k1_probe.f90`, `k1_probe_mod.f90`, `build.sh`); the prototype source in `k1_probe_mod.f90` is Phase 2's.

| | Measured | Origin, file | Settles |
| --- | --- | --- | --- |
| P1 | One thread per pair over its row of a (364, 250, 64) input through `raw_shape`: first minimum and position equal to Fortran's `minval`/`minloc` in all 2 x 16,000 values, ties included | *measured*, `out_p1.txt` | decision 4's form holds |
| P2 | Rows with NaN, +inf, -inf, the limit and its neighbours, `huge`: the kernel's rows equal the graph form's in every bit (0 of 4,368 differ), the entries too; -inf stays valid in both and is drawn; a row of only NaN and +inf gives (invalid, 1) in both | *measured*, `out_p2.txt` | decision 5's comparisons |
| P3 | `fma(raw, iw, 1)` equals `ieee_fma` in all 1e6 cases; the graph form's compiled `raw * iw + 1` is not contracted (29 % of the cases differ from `ieee_fma` by a unit); `metal::precise::exp` is within 1 unit of Fortran's `exp` and bit for bit the graph form's `exp` (1e6 of 1e6); plain `exp` in the default math mode is 62 units off | *measured*, `out_p3.txt` | the source uses `metal::precise::exp`; the forms' rows differ by one unit at most (decision 11's floor) |
| P4 | 1 then 363 terms of 2^-25: plain sum 1 exactly, compensated sum 1.0000108480453491, the expected value bit for bit. MLX 0.32.4 builds custom kernels in its default, safe math mode and the compensation is honoured | *measured*, `out_p4.txt` | **compensated sums** (decision 5) |
| P5 | bt 1, 4, 7, 8 by rt 1, 3: one source compiles at every shape, inputs of fewer than 8 elements included; rotations equal to the graph form's in every pair, distances within one unit | *measured*, `out_p5.txt` | no padding of `iw`, `temps`, `u` |
| P6 | float32 and int32 outputs of rank 2 and a float32 output of rank 3 are correct; the rank-3 rows equal the rank-2 rows reshaped; `irots` is int32 (dtype 7) | *measured*, `out_p6.txt` | decision 7 holds; rank 3 works (for K2 and K5) |
| P7 | One canonical tile, median of 5 after a warm-up, three runs of two rounds: compiled graph tail 0.74 to 2.13 ms; the kernel, warm, 0.28 to 0.43 ms at every threadgroup (32: 0.284 to 0.492; 64: 0.283 to 1.031; 128: 0.283 to 0.447; 256: 0.282 to 0.430; 512: 0.292 to 0.578; 1,024: 0.322 to 0.492; grid [rt, bt, 1]: 0.282 to 1.059). In the four rounds of runs 2 and 3 no candidate is faster than 64 by more than 1 %; in the first run 256 led, the candidates being timed in a fixed order while the GPU clock rose (64 at 1.03 ms in its first round). Entries bit for bit equal across all threadgroups and the 2-D grid | *measured*, `out_p7.txt`, `out_p7_run2.txt`, `out_p7_run3.txt` | **`POLARFT_TAIL_TG` = 64** |
| P8 | A new source's first evaluation: 48.7 ms, paid inside the submission (`apply` and `mlx_async_eval`), 4.8 ms at the wait; the same source again, a new object: 1.09 ms applied and evaluated; another output shape: 1.01 ms; the rows variant's first evaluation 25.8 ms in the submission; building an object alone 0.033 ms | *measured*, `out_p8.txt` | decision 6's costs: the compilation lands in the first tile's submission, in the warm-up pass |
| P9 | Per tile directly 0.47 to 0.51 ms, inside a function compiled with `shapeless=.false.` 0.47 to 1.05 ms (no gain); `shapeless=.true.` refuses already at the traced shape, with a status: "[Primitive::output_shapes] CustomKernel cannot infer output shapes" (the other shape is therefore not reached) | *measured*, `out_p9.txt` | **the kernel is applied directly** (decision 8) |
| P10 | 40 canonical tiles queued as the workspace queues them: compiled graph tail 0.650 and 0.709 ms per tile (median of 5, two processes), the prototype 0.166 and 0.173 ms: **3.9 to 4.1 times faster** (H2 holds). Entries' digests `6E7B0D3FE3C7A27D` (kernel) and `3812EA910C00B9E7` (graph) in three runs and two processes. Of the 640,000 pairs the drawn rotations differ in 7; where they agree the distances differ by at most 1.19e-7 (one unit). The graph form's `irots` is int32 | *measured*, `out_p10.txt`, `out_p10b.txt` | H2; decisions 3 and 12 |
| P11 | The ceiling: below | *measured*, `ceiling/` | decision 19 |

**P11, the ceiling** (*measured*, decision 17's protocol; the null tail gives rotation 1 and its distance, the
inverse transform still evaluated; build `scratch/ceiling/build_Release`, diff `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase1/null_tail.diff`; the rate is
the sum of the processes' median rates):

| Split | Graph | Null tail | Ratios | Median |
| --- | --- | --- | --- | --- |
| `2500_4`, 1 x 30 | 1.751e7, 1.751e7, 1.747e7 | 4.094e7, 4.097e7, 4.117e7 | 2.338, 2.339, 2.356 | **2.339** |
| `2500_4`, 3 x 10 (judged) | 1.688e7, 1.678e7, 1.682e7 | 5.032e7, 3.822e7, 5.698e7 | 2.981, 2.277, 3.387 | **2.981** |
| `2500_1`, 6 x 5 (judged) | 1.701e7, 1.692e7, 1.712e7 | 3.995e7, 3.912e7, 3.925e7 | 2.348, 2.312, 2.293 | **2.312** |

With the null tail each part of `2500_4` peaked at 25.1e9 B (75.0e9 B summed at three processes) and the machine's
free memory fell to 0.07e9 B, which explains that split's spread. A tail that costs nothing removes 0.65 s of the
1.14 s pass (*derived*: 1.143 s at 1.75e7 pairs/s against 0.488 s at 4.10e7).

**Decision 19: the medians at the judged splits are 2.98 and 2.31, both above 1.30. Phases 2 and 3 run.** H1
holds: the compiled tail takes about 0.65 s of the 1.14 s pass, far above 0.26 s.

**Frozen:** `POLARFT_TAIL_TG` = 64 (*measured*, P7); compensated sums (*measured*, P4); the kernel applied directly
(*measured*, P9); `metal::precise::exp` in the source (*measured*, P3).

**Decisions taken under delegation.**
1. `POLARFT_TAIL_TG` = 64 although the first P7 run favoured 256: the candidates were timed in a fixed order while
   the GPU warmed; two further runs of the probe (a probe judges nothing) show every candidate within 1 % of 64
   once warm, so the rule's default holds.
2. The source uses `metal::precise::exp`, not `exp`: the graph form's `exp` is MLX's precise one (P3), and in the
   default math mode plain `exp` is 62 units off.
3. The first ceiling attempt is void: the null build had not been installed, so its runs stopped at the
   launcher's usage check (status 2) while the graph runs ran. It is kept in `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase1/ceiling_attempt1_no_null_exe/`;
   the whole ceiling was then run once from the start. No row was repeated for its result.
4. The ceiling's series tables start as copies of Phase 0's, so that the guard predicts from the measured splits
   of each case.
5. P9 first crashed in the probe's own code (it read the outputs of the refused shapeless apply); the probe now
   checks the status. The library returned the status, as its contract says.

**What it means, in short.** Everything the kernel depends on works in MLX 0.32.4 as designed: exact reductions,
the graph form's classification, `fma` and a precise `exp`, honoured compensation, small and rank-3 outputs. In
isolation the fused tail is about four times faster than the compiled one on a canonical tile, and a tail that
costs nothing would make the judged splits 2.3 to 3.0 times faster: the 30 % rule is reachable, so the kernel is
written.

### Phase 2, the kernel on the small fixture (2026-11-25, 07:40 to 08:05, M5 Ultra)

**Files changed** (all in the file table): new `src/test/mlxf_toy_polarft_workspace_tail.f90` (the source in
pieces, the two kernels' specs, `polarft_workspace_new_tail`, `polarft_workspace_metal_tail`) and
`src/test/mlxf_toy_polarft_tail_tester.f90` (suite `polarft_tail`); `mlxf_toy_polarft_workspace.f90` (the form,
the kernel components and the constants array, the types `tail_inputs` and `tail_outputs` moved up from the
scoring submodule, the two interfaces), `_lifecycle.f90` (one comparison: the fused tail's objects or the
compiled function; their release), `_score.f90` (`apply_tail` takes the block's `rows` and makes one comparison),
`mlxf_toy_polarft_calc.f90` and `_core.f90` (`set_tail_form`, the member `tail`, reset by `kill`),
`_memo.f90` (the form into the tile spec), `mlxf_test_defs.f90` (`POLARFT_TAILS`, `POLARFT_TAIL_TG`, the three
tolerances, `polarft_tile_spec%tail`), `mlxf_test_registry.f90` (the row `polarft_tail`),
`mlxf_toy_polarft_calc_tester.f90` and `mlxf_toy_eul_prob_tab_tester.f90` (every GPU check once more with the
fused form; the calculator's tester also the forms' agreement), `scripts/toy_mirror.txt` (the line of
`set_tail_form`). No row was added to the table; `test.inf` and `test/CMakeLists.txt` needed no change.

**The calibration and the freeze** (*measured*, GPU, fixture seed 1, both halves, 96 pairs; identical in Debug
and Release): the fused rows against the compiled ones 1.1908073483292497e-07 (one unit), the distances where the
rotations agree 6.24e-08, drawn rotations differing **0**, validity off 0, draws off 0
(`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2w/kernels_dbg.log`). Frozen before any run of seeds 2 and 3 with the fused form, in
`src/test/mlxf_test_defs.f90` (sha1 `73a4a1452d9dba3becdf3cb3d79bcb803d0289c8`):
- `POLARFT_TAIL_ROW_TOL` = max(2 x 1.1908e-07, 2^-23) = **2.3816146966584994e-07** (*measured* then *derived*);
- `POLARFT_TAIL_ROT_FIX` = max(2 x 0, 1) = **1** (*derived*);
- `POLARFT_TAIL_ROT_BLK`: written as -1 here, frozen in Phase 3 from the block's seed 1.

| Exit item | Result | Evidence |
| --- | --- | --- |
| Decision 10 with the fused form (fixture, seed 2, GPU) | row error 2.358e-07 (bound 4.794e-07), minimising rotation differs in 0 of 96 (bound 1), every entry of the right validity, every draw in its interval, every entry's distance its row's; also the one-state, representatives and full-tile cases and the rebuild | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2/build_*.log`, `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2w/counts_*/polarft_calc_gpu.log` |
| Decision 11 on seeds 2 and 3 | seed 2: rows 1.192e-07, distances 1.142e-07, rotations differing 0 of 96; seed 3: 1.190e-07, 6.13e-08, 0 of 96; each form's draws hold on its own rows; same validity | same |
| Decision 12 on the fixture | `polarft_tail`: three fills of one calculator, a calculator made again, outer batches of 4 with one slot and with two, the rows variant: every entry bit for bit; the rows variant against the entries-only kernel with the keyed variates and with u = 1.5 (fallback): bit for bit. The calculator's schedule identity (three repeats, outer 6 against 4 and 2, two slots) passes with the fused form. P7: every threadgroup the same bits | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2w/counts_*/polarft_tail_gpu.log` |
| `polarft_calc` 99 and `eul_prob_tab` 35 with the fused form, Debug and Release | GPU: 7 shared checks + 92 per form (graph 92, fused 92) + 36 of the forms' agreement = 227; `eul_prob_tab` 35 per form (70 on the GPU). CPU unchanged: 107 and 35 | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2w/counts_{Debug,Release}.txt` |
| `polarft_tail` | 6 checks on the CPU device (the refusal: "refused: the fused tail (metal) runs on the GPU only", no current bins, back to `graph` it scores as a calculator that never had the fused form, bit for bit; a form outside `POLARFT_TAILS` refused), 49 on the GPU (identity, repeatability, eight small tile plans of P5 with the draw on own rows and the rotations within `POLARFT_TAIL_ROT_FIX` of the compiled form's, objects: default bins hold 4 live handles and no kernel, fused bins 6, the rows variant +1 once, release back to the start, 100 cycles of making and releasing the fused bins leave no live handle) | same |
| `unit_kernels` | 1,063 before, **1,281** now (*measured*: +92 and +36 in `polarft_calc`, +35 in `eul_prob_tab`, +55 `polarft_tail`); every other area at its count of section 2 | same |
| Decision 13 with the form `graph` | all 25 lines of Phase 0 (accuracy both devices, time and profile on the GPU, time on the CPU device) identical | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2/digests_graph/`, `digests_graph_compare.txt` |
| The ten plants of decision 14 | each fails with the named assertion and the restored file has its checksum again (table below) | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2/plants/` |
| Builds | Debug and Release from scratch with `MLXF_WERROR=ON`: 0 warnings, fast gate 9 of 9; `scripts/check_tree.sh` passes (rule `mirror` with the new line); both formatters on the 12 touched files leave them as they are. Release clean build 15 s (16 s before) | `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase2/build_{Debug,Release}.log`, `check_tree.log` |

**The plants** (each a temporary edit, the suite run on a Debug tree, then the file restored; sha1 before and after
equal in every case; `plantN.log`, `plantN.diff`):

| # | Plant | Fails |
| --- | --- | --- |
| 1 | `+ 1` dropped from the first sweep's distance | "the rows' error is within twice the CPU calibration's e_cpu", validity, draws, seed 3's row tolerance (27 of 227) |
| 2 | the rotation written 0-based | the 1-based conventions: "a row without a valid rotation gives (invalid, 1)", "u = 0 draws the first rotation of positive weight", the fallback to the first minimising rotation, the draws (14) |
| 3 | the variate read at the transposed position | "u W lies in the drawn rotation's cumulative interval ...", the forms' rotation bound and own-row draws on seeds 2 and 3 (10) |
| 4 | the cutoff comparison removed | "a rotation whose weight argument reaches the cutoff (82 >= 80) has no weight" (1) |
| 5 | the invalid marker not applied in the first sweep | "every entry is valid or invalid as in the ring oracle" (actual 995), minimising rotation, draws (23) |
| 6 | the temperature ignored | "the drawn rotations differ in at most POLARFT_TAIL_ROT_FIX pairs" (seeds 2, 3), own-row draws, the cutoff test (11) |
| 7 | the rows variant's fallback statement set to rotation 1 | "the rows variant gives the entries-only kernel's entries, bit for bit (u = 1.5)" (2 of 49) |
| 8 | one bit flipped in a repeat's copy | "three fills of one calculator give the same entries, bit for bit" (1) |
| 9 | the default form set to `metal` (the member and its reset in `kill`) | "by default the reference bins of both parities hold their tiles and the compiled tail, and no kernel" (expected 4, actual 6); `suite=time` digest `C65F8ECED8D9B855` instead of `3457E99553A08BFD` |
| 10 | the ledger line of `set_tail_form` removed | `check_rules: ... mirror: polarft_calc%set_tail_form of mlxf_toy_polarft_calc has no line in scripts/toy_mirror.txt` |

**Decisions taken under delegation.**
1. The forms' agreement on the dense fixture (seed 1 printed, seeds 2 and 3 judged) is in the calculator's tester,
   run after its GPU checks with the fused form; the suite `polarft_tail` uses its own seeded data. Reason: the
   fixture and its ring oracle are private procedures of the calculator's tester, a tester exports only its entry,
   and a second copy of the fixture would be a defect. The fused pass's own 92 checks are printed per pass
   ("92 checks of the device"), so its count stays readable.
2. Each tester runs its device checks through `run_device_tests(dev, form)`; a test takes the form as a second
   dummy and puts it on the fixture record, whose `feed_calc` sets it. Reason: no module state in a tester
   (rule `state`), and the tests keep their bodies.
3. The driver's tester's live-count check ("the driver holds no array of its own") allows the two rows variants
   the fused form's workspaces keep after the first fill with rows (decision 7 builds them there and keeps them
   with the tiles); with the compiled form it is unchanged.
4. A refused fused form is refused in `polarft_workspace%new` at the place where the compiled tail is built (after
   the upload of the tiles, which are then dropped), so the preparation makes one comparison of the form.
5. `polarft_workspace_new_tail` and `polarft_workspace_metal_tail` are module procedures with interfaces in the
   parent, not type-bound procedures, so the ledger gains one line only (`set_tail_form`).
6. Plant 2 is caught by the 1-based rotation conventions of the draw (the (invalid, 1) rule and the first-rotation
   draws); `test_convention` checks the rows' minimum, which the plant does not touch.
7. Two first passes of the plants are void and kept apart (`plants/first_pass_unlogged_builds/`,
   `second_pass_stale/`): the plant tree's `make` compares whole seconds, so an edit made in the second of the
   previous build was not rebuilt and some plants ran another plant's binary. The script now waits 1.2 s around
   every edit and logs every build; all ten plants were run again from the start.

**What it means, in short.** The fused tail computes the compiled one's rows to one unit and draws the same
rotations on all 288 fixture pairs of seeds 1 to 3; it holds the oracle's frozen bounds, is repeatable bit for
bit, and refuses the CPU device with a reason. With the default form nothing of it is built, and the graph form's
25 digests did not move.

### Phase 3, the bench and the verdict (2026-11-25, 08:05 to 08:50, M5 Ultra): stopped at the verdict, a ruling is needed

**Files changed:** `src/test/mlxf_bench_polar_table.f90` (`tail=` in `accuracy`, `time` and `profile`, set on the
calculator before the reference bins; the formulation column `B+metal` for the fused form; the estimate counts one
row-sized array per tile for it; `suite=accuracy tail=metal` runs on the GPU only and adds the forms' agreement on
the block: seed 1 printed, seed 2 judged), `src/test/mlxf_test_defs.f90` (`POLARFT_TAIL_ROT_BLK`).

**Accuracy before any timed row** (*measured*, Release, `device=gpu tail=metal`, at 16 by 250 and at 64 by 250,
identical; `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/accuracy_calibration/`, `accuracy_judged/`):
- the calibration, block seed 1: rows 6.5133e-08, distances 6.4989e-08, drawn rotations differing **1** of 64,000,
  validity and draws 0. Frozen before the judged run: `POLARFT_TAIL_ROT_BLK` = max(2 x 1, 5) = **5**; the row
  constant stays (the block's 6.51e-08 is below the fixture's 1.19e-07). `mlxf_test_defs.f90` sha1
  `2571d9086b5ce0f17774e47d53ee4b4471cfd20e`;
- the judged block, seed 2: against the oracle row error 6.163e-07 (bound 1.4505e-06), 0 of 64,000 minimising
  rotations differing (bound 5), validity and draws hold; against the compiled form rows 6.518e-08, distances
  6.518e-08, 2 of 64,000 drawn rotations differing (bound 5); the schedule identity (three repeats, outer batches,
  teams, two slots) holds. 98 assertions, the graph form's 76 among them;
- planted at this size (`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/plants/`): plant 1 fails the rows' bound, the forms' row tolerance and
  `POLARFT_TAIL_ROT_BLK`; plant 6 fails `POLARFT_TAIL_ROT_BLK` and the draws; plant 8 fails "three repeats give
  identical entries". Each file restored to its checksum.

**Decision 13 again:** all 25 digest lines of Phase 0 identical with the Phase 3 builds
(`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/digests_graph_compare.txt`, `digests_graph_final_compare.txt`). Builds: Debug and Release from scratch,
0 warnings, gate 9 of 9, `scripts/check_tree.sh` passes (`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/../phase3w2/`).

**Profile** (*measured*, `2500_4`, 64 by 250, with a barrier after every stage; `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/profile/`): graph 1.959 and
1.960 s, stages 0.011/0.016, 0.543/0.553, 0.423/0.421, **0.942/0.945**, 0.003; metal 1.370 and 1.372 s, stages 0.011,
0.483/0.484, 0.430/0.426, **0.421/0.426**, 0.003. The fused tail's stage is 0.45 of the compiled one's (H2 holds
in the driver too); digests `3457E99553A08BFD` and `C65F8ECED8D9B855`.

**The timed rows** (*measured*, decisions 15 to 17: `run_parts.sh` with `RUN_PARTS_LOAD=4`, the forms interleaved,
graph first, every row status `ok` at its first attempt; the rate is the sum of the processes' median rates;
`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/timing/run_parts_2500_{4,1}.tsv`, `verdict_table.txt`, `ratios.txt`):

| Split | Graph median rates | Fused median rates | Ratios | Median | At or above 1.30 |
| --- | --- | --- | --- | --- | --- |
| `2500_4`, 1 x 30 | 1.767e7, 1.763e7 | 3.180e7, 3.188e7 | 1.799, 1.808 | 1.804 | 2 of 2 |
| `2500_4`, 3 x 10 (**judged**) | 2.381e7, 2.484e7, 2.428e7, 1.969e7, 1.727e7 | 2.967e7, 3.045e7, 2.986e7, 3.012e7, 3.038e7 | 1.246, 1.226, 1.230, 1.530, 1.759 | **1.246** | **2 of 5** |
| `2500_4`, 6 x 5 | not run (guard: 157.3e9 B predicted, once per form) | | | | |
| `2500_1`, 1 x 30 | 1.785e7, 1.787e7 | 2.957e7, 2.953e7 | 1.656, 1.653 | 1.655 | 2 of 2 |
| `2500_1`, 3 x 10 | 1.726e7, 1.683e7 | 2.898e7, 2.913e7 | 1.679, 1.730 | 1.705 | 2 of 2 |
| `2500_1`, 6 x 5 (**judged**) | 1.830e7, 1.748e7, 1.731e7, 1.733e7, 1.741e7 | 2.996e7, 3.046e7, 3.048e7, 3.004e7, 3.038e7 | 1.637, 1.742, 1.761, 1.733, 1.745 | **1.742** | **5 of 5** |

| Split, form | Pass time, s | Go to last exit, s | Summed footprint, B (largest part) | Summed MLX peak, B | Lowest free, B |
| --- | --- | --- | --- | --- | --- |
| `2500_4` 1, graph / fused | 1.133 / 0.628 | 12.79, 12.81 / 7.84, 7.87 | 20.81e9 / 27.25e9 | 10.26e9 / 16.71e9 | 52.2e9 / 45.8e9 |
| `2500_4` 3, graph / fused | 0.840 (see below) / 0.664 | 13.47 to 13.65 / 15.72, 12.88, 8.63, 8.58, 8.62 | 60.32e9 (20.11e9) / 78.97e9 to 79.29e9 (26.43e9) | 29.71e9 / 48.88e9 | 12.4e9 to 19.5e9 / 0.07e9 to 0.91e9 |
| `2500_1` 1, graph / fused | 0.280 / 0.169 | 10.84, 10.85 / 6.82, 6.84 | 8.33e9 / 14.29e9 | 4.81e9 / 10.79e9 | 71.7e9 / 65.5e9 |
| `2500_1` 3, graph / fused | 0.293 / 0.172 | 11.40, 11.42 / 7.02, 7.03 | 23.70e9 / 41.19e9 | 13.67e9 / 31.24e9 | 56.3e9 / 37.6e9 |
| `2500_1` 6, graph / fused | 0.287 / 0.165 | 11.53 to 11.55 / 6.98 to 7.05 | 45.91e9 / 56.54e9 (9.43e9) | 26.15e9 / 37.10e9 | 31.6e9 / 21.2e9 |

Every digest of a form is equal across its runs, per part: the graph form's are Phase 0's; the fused form's are
`C65F8ECED8D9B855` (`2500_4`, one process), `34BBD65AE23203EC`, `6CF6DEE670DC243B`, `9C32AC826157933B` (three
parts), `D8FCFBC0F5B54449` (`2500_1`, one), `746743FD562476AF`, `D3961EB3718F3E06`, `D850E2864A45F40B` (three),
`15BA6DB8F0F31469`, `F9085BCB4FFD1CEF`, `BEEC195C1C8F8ADF`, `66424F246C1BB3A0`, `65AFA458BFCBD4B2`,
`FBCB2EDC4D435CE7` (six).

**Decision 18 by its letter.** At `2500_1` at six processes the rule is met (median 1.742, 5 of 5). At `2500_4` at
three it is not: median 1.246, below the 1.25 to 1.35 band that would add five pairs, and 2 of 5 at or above 1.30.
By the letter the outcome is **deleted**.

**The diagnosis (section 7: a failing acceptance is diagnosed first): the judged split's graph rows are not a
steady-state rate, so the protocol could not resolve the ratio there.**
- The graph form's summed median rate at three processes was 2.38e7, 2.48e7, 2.43e7, 1.97e7 and 1.73e7. Three
  processes share one GPU, whose rate with one process is 1.77e7 (*measured*, the same session); Phase 0's seven
  graph rows of this split measured 1.672e7 to 1.698e7 (the control: largest distance 0.0069). Rates up to 41 %
  above one GPU's cannot be a shared steady state.
- The mechanism: the parts desynchronised. In Phase 0 the three parts exited within 0.35 s of each other; in
  Phase 3's graph rows one part exited 2 to 3.3 s after the others (`timing/g_2500_4_n3_*_a1/part_*/end_time`).
  A part that runs its passes while another is idle, or alone after the others finished, has a median pass far
  below the shared one (0.43 to 0.64 s against 1.18 s in Phase 0), so the sum of medians counts the same GPU time
  more than once. Decision 15 assumed the median leaves such passes out; with 9 passes and a lag of two to three
  passes it does not.
- What the graph form actually took did not change: the time from go to the last exit was 13.47 to 13.65 s, as in
  Phase 0 (13.46 to 13.59 s). The fused rows did not desynchronise in the same way (their summed medians,
  2.97e7 to 3.05e7, are 0.93 to 0.96 of the fused form's one-process 3.18e7).
- The machine's state had changed since Phase 0: free memory during the graph rows 12.4e9 to 19.5e9 B against
  0.47e9 B in Phase 0 (at one process 52.2e9 B free against Phase 0's 40.0e9 B: the machine's other load had
  shrunk; 3.2e9 B of swap in use after the fused rows). One further graph-only row at three processes, taken after the verdict for
  the diagnosis only and not counted (`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/diagnosis/dg_2500_4_n3_1_a1`), desynchronised again: one part exited
  5.4 s before the others, summed median 2.90e7, go to last exit 13.54 s. So the effect is the machine's present
  state under the median rule, not the interleaving with the fused form.
- Reported, not deciding: against Phase 0's frozen graph rate of this split (1.691e7) the five fused rows give
  1.75 to 1.80; on the time from go to the last exit, pairs 3 to 5 give 1.56 to 1.58, pair 2 1.05, pair 1 0.87
  (that fused row ran with 0.07e9 B free: see H3).

**H3 is refuted.** The fused form raised a process's MLX peak from 10.26e9 to 16.71e9 B (`2500_4`) and from
4.81e9 to 10.79e9 B (`2500_1`), not lowered it: a cheaper tail lets the host queue more tiles ahead of the device,
each holding its products and rows. Three fused parts of `2500_4` hold 79e9 B, 0.77 of the machine (the guard let
them run at a prediction of 81.8e9 B, just under its 82.5e9 B), and drove free memory to 0.07e9 to 0.91e9 B.
The roadmap's conditions: total rate over one process's, fused, 0.93 to 0.96 at `2500_4` 3 and 0.98 to 1.03 at
`2500_1` 3 and 6 (the first condition is not met); summed footprint above 51.5e9 B: met by the fused form at
`2500_4` 3 (79.0e9) and `2500_1` 6 (56.5e9), by the graph form at `2500_4` 3 only.

**The stop, and the ruling needed.** The plan's rule is mechanical, and by it the kernel goes. The run does not
carry out decision 20's deletion, because the deciding ratio rests on rows that the plan's own premise (decision
15) excludes, and because the deletion cannot be undone by a ruling while the code is kept until one. Nothing was
repeated to pass, and no row was dropped. The maintainer rules one of:
1. **delete by the letter** (decision 20, then Phase 4's record of a negative result);
2. (recommended) **re-take the judged split `2500_4` at three processes once, five pairs, with a validity test
   frozen before it** (for example: a row counts only if its parts exit within one median pass of each other, and
   a row that fails is repeated, as a discarded row is), keeping the other split's verdict; or
3. judge that split on the time from go to the last exit, which the plan reports and does not judge.

**Decisions taken under delegation.**
1. The forms' agreement on the block lives in the accuracy suite with `tail=metal`, which runs on the GPU only
   (a usage stop otherwise): the compiled form is the CPU path, and decision 10 judges the fused form on the GPU.
2. `tail=` is read by `arg_config`, so every suite that reads it sets it the same way, and a value other than
   `graph` or `metal` stops.
3. The 2500_4 six-process split was called once per form and recorded as not run (157.3e9 B predicted from the
   fused one-process row, which the guard takes as the largest part).
4. One diagnostic graph row was taken after the verdict, labelled and kept apart, to tell the machine's state
   from the interleaving. It judges nothing.
5. Stopped before decision 20 (above).

**What it means, in short.** The fused tail is accurate (the oracle's bounds, the compiled form within one unit
and 2 rotations in 64,000) and repeatable, and wherever the rows are steady it is 1.65 to 1.80 times faster: at one
process, at three processes of `2500_1` and at the judged six (5 of 5 above 1.30). At the other judged split the
graph rows overstate the compiled form's rate because the parts drifted apart, and the median ratio fell to
1.246. The kernel also raises each process's peak by about 6e9 B. Whether it is kept is the maintainer's ruling.

### Phase 4, the record (2026-11-25, 08:55 to 09:00)

Phase 4 is replaced by the stop of Phase 3. Done: the report
[`mlxf_kernel_k1_report.md`](../completed/mlxf_kernel_k1_report.md) in the order of the how-to's section 8 with
its commit message; this note's banner. Not done, pending the ruling: decision 20's removals or the record of a
kept form, and the documents of Phase 4's step 2 (kernel families, roadmap, test policy, plans index, history,
binding policy section 12, Apple questions); the report lists what each would say. The working tree holds only
paths of the file table (`git status`: 13 modified and 2 new under `src/test` and `scripts` beyond the base's 44
lines, and the report). `scripts/check_tree.sh` passes; Debug and Release were last built from scratch at the end
of Phase 3, 0 warnings, gate 9 of 9.

### Ruling R1 and the re-take (2026-11-25, 08:52 to 09:20, M5 Ultra): stopped, the protocol cannot resolve the split

**R1** (`spec/rulings.md` of the run, the session under the maintainer's go; stands as recommended, open to the
review): option 2 of the stop. Reason, as ruled: the deciding graph rows of `2500_4` at three processes summed to
up to 1.41 times one GPU's rate, which decision 15's premise excludes, so the letter would decide on a quantity
the plan did not mean to measure; the rule, the 30 % and every floor are unchanged, and a deletion stays possible
after the re-take. Frozen before the first re-taken row: a row of that split counts only if its parts' exit
spread (latest `end_time` minus earliest) is at most the median of its parts' median passes; an invalid row is
discarded and repeated, at most 3 attempts; five new pairs, graph first, decision 17's protocol, the judged
Release executable (`scratch/build_phase3w2_Release`, not rebuilt); decision 18 unchanged on the new five;
`2500_1` at six keeps its verdict; no valid attempt in three is a stop.

**The old rows under test 1** (reported, not counted; `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/old_rows_validity.txt`): Phase 3's five graph rows
all invalid (spreads 3.34, 2.18, 2.08, 2.00, 1.64 s against median passes 0.97 to 1.02 s); its fused rows valid
in 3 of 5 (0.35, 1.42, 0.48, 0.66, 0.53 s against 0.60 to 0.65 s). Phase 0's seven graph rows of the split all
valid (spreads 0.09 to 0.41 s against 1.18 to 1.20 s).

**The re-take** (`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/retake/`, `retake.log`, `retake2.log`):
- Row g1 (graph, pair 1): attempt 1 spread 5.789 s against a median pass of 0.792 s, invalid; attempt 2 5.828
  against 0.788, invalid; attempt 3 5.094 against 0.803, invalid. **No valid attempt in three: stop (R1, item 5).**
  In each attempt one part exited 7.7 to 8.4 s after go and the other two at 13.5 s: the GPU served one graph
  process ahead of the others for most of the run. The time from go to the last exit was 13.56, 13.55, 13.50 s,
  Phase 0's value.
- A defect of the run's script, found when the verdict was read: the first pass of the re-take tested the
  validity on the launcher's output file instead of the row's directory, got an empty answer and took it as
  valid, so it ran all ten rows without repeating any. Those rows were taken out of the protocol's order
  (after an invalid row g1) and are set aside, not counted, in `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase3/retake/void_unchecked_rows_2_to_5/`;
  checked afterwards, all ten are invalid under test 1 (graph spreads 5.28 to 5.79 s against 0.78 to 0.79 s;
  fused 1.19 to 2.08 s against 0.46 to 0.74 s; `void_rows_validity.txt`). The script was corrected (it tests the
  directory and accepts only an explicit "valid") and the re-take continued with row g1's attempts 2 and 3.

**What it means.** In the machine's present state the compiled form's three processes do not share the GPU
evenly, and the fused form's not quite either, so no per-process median gives a shared rate at this split; the
protocol cannot resolve the 30 % here (as Phase 0's control stop). The verdict is open: `2500_1` at six is
met; `2500_4` at three is unresolved. Decision 20 and Phase 4 were not carried out; the code stays in the
working tree, the default form `graph`. **H3 stands either way:** the fused form raises a process's MLX peak by
about 6e9 B. A ruling is needed: delete; keep on `2500_1` alone; or a measure of the shared split that does not
rest on per-process passes (the time from go to the last exit, or one process scoring the three parts' work in
turn), frozen before its rows.

### Ruling R2 and Phase 4 (2026-11-25)

**R2** (the maintainer, on the stop of the re-take): "The fused form is fine. Memory can be increased. WE can buy machines with more memory to run more parts. I am not locked into this little testing machine", and "We can essentially control memory usage in SIMPLE by dialing down the number of parts". Before it, on the measure: "the whole cryo-EM reference
matching problem is embarrassingly parallel so any gains we can maintain with many parts is linear speedup".
**The fused form is kept** under decision 20: it stays selectable (`set_tail_form`, `tail=metal`), the default
stays `graph`, K4 may build on it. The rows of `2500_4` at three processes stay unresolved by the per-process
protocol; the time from go to the last exit (1.52 to 1.59) and the met split (`2500_1` at six, 1.742) carry the
ruling. H3's +6e9 B per process is reported, not judged: SIMPLE trades memory against the number of parts.

**Phase 4, done:** step 1, nothing removed; step 2, the kernel-families note (section 3: the submodule `_tail`,
the peak with the fused tail, the form among the differences, A1 delivered; section 8: K1's row with the
result), the roadmap (the rank 2 row; under decision 15, what K1 measured and how a rate of several parts is
read), the test policy (the sub-suite `polarft_tail`, the keys `tail=` and `passes=`), the plans index, the
history (the result in decision 20's form), the binding policy's section 12 (the shapeless refusal, the math
mode, a rank-3 output in a probe) and Apple question 21 (the safe mode measured); step 3, the report's addendum;
step 4, the banner. The plan stays in `planned/` while K2 and K4 cite it, and moves to `completed/` with the
batch's last commit, its links updated in the same change.
