# K3: arbitrary reference sets for polar matching (A2), with the toy driver `eul_prob_tab_neigh` (run `mlxf_kernel_k3`, on the M5 Ultra)

Status, 2026-11-26: planned; ruled as recommended by Hans, 2026-11-26 ("Rule as recommended"), every decision of section 3 and the run order K4, K3, K5, K6, K7; revised after ranks 2d to 2f (runs `mlxf_refactor`, `mlxf_toy_layout`,
`mlxf_kernel_forms`). Base: the commit that holds this plan, after rank 2g's result and K4's (the user-facing hardening,
`mlxf_user_hardening.md`; the maintainer commits this plan with the pending work, and the run pins the hash in
Phase 0 and records it). The revision was checked against `ae7d623` (ranks 2d to 2f committed) with the three
uncommitted document edits of 2026-11-26; the draft was written at `b2c43a4`. SIMPLE is pinned at `28c753993`,
the mirror ledger's pin since rank 2e, and every SIMPLE fact below was re-read there with `git show` and
`git grep`. MLX's source was read in `~/src/mlx` at `v0.32.4-141-g5c8989446`, with
`mlx/backend/metal/matmul.cpp` compared at tag `v0.32.4` (the installed MLX is 0.32.4). Machine: the M5 Ultra
only (30 cores, 103.1 GB, the only GPU and the only machine that builds the library), in the session, in a copy
of the checkout, one run at a time. Supersedes: none. Depends on:

- the polar toy `polarft_calc` on SIMPLE's memo layout (one reference memo `ft_ref_terms (2nk, pftsz+1, nrefs,
  2)`, the particle terms `ft_ptcl_wterms`, device tiles made by `memoize_refs`) with its driver `eul_prob_tab`,
  its host kernel and K1's fused tail (validated: yes, runs `mlxf_kernel_k1`, `mlxf_toy_seam` and
  `mlxf_toy_layout`, `unit_kernels` 1,953 at `ae7d623`; **not** validated: any reference list but 1..nrefs on
  the MLX backend, which `score_block_posterior_mlx` refuses today);
- `mlx_gather_mm`, `mlx_take`, `mlx_argsort`, `mlx_cumsum` (validated: yes, `unit_linalg` 632 and `unit_ops`
  2,462 at `ae7d623`, counts rank 2g may raise; **not** validated: `mlx_gather_mm` at the dense score's shapes
  or against `matmul` bit for bit; `mlx_argsort`'s stability, which MLX does not document, binding contract
  policy and Apple question 36);
- the measured kernel forms of run `mlxf_kernel_forms` (`completed/mlxf_kernel_forms_report.md`, "What the K
  plans take"): sizes in an int32 input (suite `sizes`), one wait per pass with a persistent capacity (suite
  `waits`, measured at this plan's own tile), threadgroup memory and SIMD-group functions (suite `probe`);
- the oracle `mlxf_oracle_polar` (validated: yes, sub-suites `polarft_calc`, `eul_prob_tab` and the bench's
  `suite=accuracy`; it scores every reference, and a listed pair's oracle row is the dense row of that pair);
- `scripts/run_parts.sh` (validated: `bench_polar_table suite=time`, and other benches through
  `RUN_PARTS_BENCH`, `RUN_PARTS_SUITE`, `RUN_PARTS_UNIT`; **not** validated for a new suite of the polar bench);
- the custom Metal kernel wrapper `type(mlx_metal_kernel)` (validated: yes, parity Phase 10, K1, K2 and run
  `mlxf_kernel_forms`: `threadgroup` arrays up to 32,768 B with `threadgroup_barrier`, and `simd_sum`,
  `simd_min`, `simd_prefix_inclusive_sum`, `simd_shuffle`, exact and repeatable through the wrapper, Apple
  question 26; the list route needs none of them, candidate B of decision 10 may);
- rank 2g's result (validated when its report is read in Phase 0: it changes `src/core/` and may add
  assertions to unit areas, section 2, "The queue");
- the roadmap's decisions 7, 8, 9, 11, 12, 15, 16 and 17.

## 1. Why

- The dense score computes every reference for every particle. SIMPLE's neighbourhood refinement
  (`refine=*neigh*`) scores a small part: at its defaults (`simple_parameters_phases.f90`: 20,000 directions,
  500 subspaces; `simple_parameters.f90`: `athres_cont` 10 degrees) a 10-degree cone holds 0.76 % of the
  directions (*derived*: (1 - cos 10°)/2 = 0.00760), 152 of 20,000 per state.
- Scoring a list by the dense kernel and discarding the rest costs the dense time. On case `2500_4` (10,000
  references per half, 2,000 particles, 2e7 pairs) that is 1.14 s a pass with the graph tail and 0.63 s with
  the fused one (*measured*, K1's report), for 152,000 listed pairs at 10 degrees (*derived*: 2,000 x 4 x 19).
  Thirty threads at the dense block rate of 3.75e6 pairs/s (*measured*, families note) would take 0.041 s
  (*derived*).
- So the GPU needs a route that computes little more than the listed pairs. The measure is occupancy: listed
  pairs over computed pairs. The break-even against 30 threads is about 21 % with the graph tail (*derived* in
  the families note: 3.75e6 / 1.76e7) and about 12 % with the fused tail (*derived*: 3.75e6 / 3.18e7).
- The design note names the tools (`mlx_gather_mm`, `mlx_block_masked_mm`) and leaves open what a pair's bits
  may depend on and the tile shapes. The mlx3D note proposes a first measurement. This plan settles the first
  by reading (section 2), fixes the measurement that replaces it, and delivers the route, its driver, the
  occupancies and the rates.
- **What K3 can and cannot tell SIMPLE.** SIMPLE's production fills send only the shared representative list
  through anything block-shaped today; members and cones are scored per pair (section 2). K3 can say at which
  occupancy and batch size a block-shaped GPU route of those lists beats the dense GPU fill and 30 threads'
  block rate; it cannot say that such a route beats SIMPLE's per-pair path, whose rate at this geometry is
  not on record, nor what restructuring the fill around blocks would cost SIMPLE.

## 2. Contract

- **Delivers:** (1) the MLX route of `polarft_calc%score_block_posterior` for any reference list `irefs`, as
  SIMPLE's and the toy's host kernels take one; (2) the toy driver `eul_prob_tab_neigh` under SIMPLE's names,
  filling cone lists (SIMPLE's mode `geom`) and its mode `state` (the representatives, then the members of
  each particle's pooled cells, decision 25) on both backends; (3) a suite `neigh` of `bench_polar_table`
  with the occupancy and the rate for cone-shaped sets, with and without orientation order, and for the
  `state` fill, alone and as 3 and 6 processes; (4) the verdicts of
  decisions 9 and 10; (5) a report.
- **Exit as accepted** (families note, section 8, row K3): listed pairs equal the dense kernel's (decision 7
  says in which sense); occupancy and rate reported for cone-shaped sets, with and without orientation order.
- **Toy code only.** New code is in `src/test/toys/polar/` as `mlxf_toy_<stem>` modules written against the
  public module `mlxf`, its oracle in `src/test/oracles/`, its bench suite in `src/test/bench/` (rank 2d's test
  tree). No file under `src/core/` or `src/defs/` changes. A missing wrapper is a stop with a report. Every new
  Fortran file opens with its `!@descr:` line, its folder's `.inf` names it where the description lists files,
  and `doc/code_base_map.md` is regenerated with `scripts/generate_codeoverview.py` in the phase that adds it
  (the static gate checks the map).
- **Builds:** hand-configured trees with `-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`, Debug and Release,
  as the delivered plans prescribe. Nothing else is built while a step is timed.
- **SIMPLE is not measured.** Its numbers come from the notes; where none is in hand the comparison stays open.
  No production data.

### What the check found (2026-11-26, re-read at `ae7d623`)

The toy as it stands (rank 2e put it on SIMPLE's memo layout; the paths are rank 2d's,
`src/test/toys/polar/`):

- **The host kernel already takes any list.** `mlxf_toy_polarft_block.f90`, `score_block_posterior`: any
  `irefs` inside 1..nrefs, at most `PFTC_BLOCK_NB` (16) particles, tiles of `PFTC_BLOCK_NR` (32) references
  whose terms are read in place from the memo `ft_ref_terms(:, bin, iref, parity)`, the particle terms from
  `ft_ptcl_wterms` (or a seed bank of shape (2nk, pftsz+1, nb) where `l_bank`), the draw keyed by
  `keyed_variate(seed, iptcls(b), ref_full(iref))`.
- **The MLX route refuses every list but the memoized one.** `mlxf_toy_polarft_block_mlx.f90`,
  `score_block_posterior_mlx`: unless `nr == nrefs` and `irefs` is 1..nr it sets "the block's reference list
  is not the memoized one". No tester asserts that message (searched in `src/test/`).
- **The device computes whole tiles.** `mlxf_toy_polarft_workspace_score.f90`, `polarft_workspace_submit`: the
  block's particle terms (the calculator's `ft_ptcl_wterms`, or the seed bank where `l_bank`) are gathered on
  the host into (2nk, pftsz+1, bpad) and uploaded; per particle tile and reference tile one packed real product
  `matmul(pt, g)` with `pt` (bt, 4nk, pftsz+1) and `g` (4nk, 2rt, pftsz+1) cut from the resident tiles by
  `mlx_slice`, then the inverse transform, the tail and one `mlx_async_eval` per tile. The resident tiles are
  made by `memoize_refs` and packed on the host straight from the conjugated memo `ft_ref_terms`
  (`polarft_workspace_new`, rank 2e's measured fallback), or from the device memo on the device route
  (`new_from_memos`). Its header says tiles are always full (padded), "so a pair's entry depends on its tile
  position only". `check_block` requires variates of shape (nrefs, nb).
- **The driver draws a variate for every reference.** `mlxf_toy_eul_prob_tab.f90`, `fill_tab_range`,
  contained `process_block`: `u(r, b)` from the global IDs for all `nrefs`, then `set_block_variates` and
  `submit_block`. The keys are global on both backends, so a listed pair's variate is the dense pair's.
- **The bench already shuffles references and reverses particles.** `mlxf_bench_polar_table.f90`,
  `position_and_list`: judged against the frozen bounds, the entries that differ from the canonical run by
  global pair reported. *Measured*: on the M2 (run `mlxf_milestone1_m2`) the CPU device gave identical bits in
  every case; on the GPU reversed particles changed 7,596 of 64,000 entries and shuffled references none. On
  the M5 (run `mlxf_m1_m5`) reversed particles changed 2,872 of 64,000 on the GPU and none on the CPU; for
  shuffled references on the M5 there is no record in hand. The cause is not established in the record.
- **The bench's keys are checked.** `check_keys` stops with status 2 on a key a suite does not read
  (`SUITE_KEYS`); a new suite needs its own row there.

MLX's gathered product (`mlx/ops.cpp`, `gather_mm`; `mlx/backend/metal/matmul.cpp`, `GatherMM::eval_gpu`;
`mlx/backend/cpu/masked_mm.cpp`, `GatherMM::eval_cpu`; the wrapper `mlx_gather_mm` in
`src/core/linalg/mlxf_linalg.f90`):

- The GPU has four routes: a sorted route (one row in MLX's left operand, no list on the left, the right list
  ascending), a matrix-vector route (one row or one column), a wide route that `gemv_wide_config` gives only
  to float16 and bfloat16 outputs, and a generic route (a GEMM kernel that looks every matrix up by its index
  and copies nothing). The CPU loops over the output matrices, float32 only.
- **differs** (mlx3D note, section 4 and proposal 2): the dense score's products do not fit the sorted route.
  A tile product has 2rt = 500 rows and bt = 64 columns at the canonical plan, so it takes the generic route,
  where `sorted_indices` is not read. In the Fortran view the sorted route needs `b` with one column and only
  `lhs_indices`, ascending: `r(:,1,i) = matmul(a(:,:,lhs(i)), b(:,1,i))`, one column of 4nk values per
  (particle, bin, reference tile). At `2500_4` that is 183 products per particle and tile against 7,320
  matrices (*derived*: 183 bins x 40 tiles of 250). The measurement the note asks for can be made only in that
  layout; decision 2 names what replaces it.
- `mlx_block_masked_mm` masks blocks of 32 or 64 rows or columns and returns exact zeros for a dropped block
  (binding contract policy). A dropped block of a product is a dropped tile part; it does not select
  references inside a tile. `mlx_segmented_mm` is rank 2 only. Neither is used by this plan's default form.

SIMPLE at `28c753993` (the draft read `d354efee2`; `simple_eul_prob_tab_neigh.f90` changed since by
`23eb95cc2`, one memo layout, and `c1f255d20`, `cont_view` through `prob_neigh_mode=geom`; what follows is
re-read at the pin, and the two changes are named where they act):

- **What changed between the pins.** `23eb95cc2` removed `memoize_ref_bins` and the `block_memo` argument of
  `new_pipeline` and `new_neigh_pipeline` (the block kernel reads `ft_ref_terms` in place), and every seed
  bank is now a particle's terms of shape (2nk, pftsz+1, slots) (`alloc_seed_bank`, the state mode's banks,
  `score_block_posterior`'s `banks`). `c1f255d20` added a branch at the head of `fill_tab_neigh_range`: with
  `l_cont_view` and mode `geom`, `fill_geom_views` takes per particle the `topk` nearest cone views
  (`nearest_cone_views`, `simple_eul_prob_tab_utils.f90`) and refines each continuously
  (`strategy3D_srch%refine_extra_pose_continuously`), with no block kernel and no per-pair cone scan;
  `assign_geom_views` merges the solved views into basins. `refine3D_local` with `refine=prob_neigh` now sets
  `geom` only when no mode is given and admits `state` when `cont_view` is active. Neither change touches the
  block kernel's interface, the `state` fill's stages, or `geom` without `cont_view`, which this plan models;
  the `cont_view` branch is a declared difference (decision 11).
- **differs** (design note, section 3, "per-particle lists, covered by tiles"): SIMPLE's
  neighbourhood driver never sends a per-particle list through the block kernel. In
  `simple_eul_prob_tab_neigh.f90`, `fill_tab_neigh_range` dispatches on `prob_neigh_mode` (after the
  `cont_view` branch above):
  - `state` (the parameter's default, and what `exec_classify3D_refs` of `simple_commanders_refine3D.f90`
    sets when none is given; `refine3D_local` with `refine=prob_neigh` sets `geom` when none is given):
    `fill_tab_subspace_range`, contained `cut_blocks_state` orders the batch by half and by the subspace cell
    of the previous direction and cuts blocks of at most `PFTC_BLOCK_NB`; `process_block_state` calls
    `score_block_posterior` with `rep_full`, every active state's subspace representatives in the order
    (state, cell), **the same list for every block**. Then `finish_particle_state`, per particle:
    - **The peaks** (`consider_peak_subspace`): per state the `npeak_target` = min(`npeaks`, nsubs) cells (3
      by `NPEAKS_DEFAULT`) whose representatives have the smallest **drawn** distance, the block kernel's
      entry at the keyed in-plane draw. Ties: a distance equal to the worst kept one does not enter, and an
      equal one is placed after those already kept, so the earlier cell wins. The cells are data: they come
      from the representatives' scores and from the draw.
    - **The pool** (`build_pooled_neighborhood`, `add_pooled_subspace`): per state, its peaks if the cell of
      the previous direction (`subspace_full2sub_map(prev_proj)`) is among them, else its best
      `npeak_target` - 1 and that cell; the union over the active states without repeats, at most
      min(nsubs, `npeak_target` x nstates) cells; **the same pooled cells for every active state.** That is
      3 cells with one state and 3 to 9 with four (*derived*: the previous cell and 2 per state).
    - **The members** (`evaluate_neighborhood`): every reference of every active state whose direction maps
      to a pooled cell (`sub_ref_list` of `init_eval_subspace_ws`, ascending reference index), each scored
      **per pair** (`score_seeded_ref`); a representative that maps to its own cell is scored again. At the
      defaults that is 120 references with one state and 480 to 1,440 with four (*derived*: cells x 40 x
      states). Two particles that pooled the same cell share exactly its members.
  - `geom`: `process_particle_subspace` per particle, `evaluate_cone`: every active state's references whose
    view distance (`cone_view_dist`, `simple_eul_prob_tab_utils.f90`) from the previous orientation is within
    the cone (the particle's slot `cone` with its mirror view, else `athres_cont`), cells out of reach skipped
    (`cone_cell_radii`, `cone_reachable_cells`), references in ascending index, each scored **per pair**.
  - `shc` and `snhc`: `fill_tab_stoch_range`, per pair with a stopping rule.
- **What the lists are.** Sizes at the defaults: the representative list is nstates x 500; a cell has about
  40 members (*derived*: 20,000 / 500) and the pooled members are counted above; a 10-degree cone is 152
  references per state (*derived* above). Order: ascending reference index, state by state. Overlap: the
  representative list is shared by all; pooled lists share whole cells; two cones whose axes are 5, 10 and
  20 degrees apart share 69 %, 39 % and 0 % of a 10-degree cone (*derived*, the planar lens
  (2/pi)(acos x - x sqrt(1 - x²)) at x = 0.25, 0.5, 1).
- `src/utils/math/simple_neighs.f90` holds pixel neighbourhoods (`neigh_8`,
  `neigh_4_3D`); it builds no reference list. The cells come from `simple_builder.f90` (`eulspace_sub`,
  `sym_dist_table`) and `simple_srchspace_map.f90` (`new_from_distmat`: `full2sub_map` and `sub2full_map` by
  `minloc`); the cones from the three `cone_*` procedures above.
- **SIMPLE's block kernel promises more than the device does.** `simple_polarft_block.f90`,
  `score_block_posterior`: the product always has the shape `PFTC_BLOCK_NB` x `PFTC_BLOCK_NR`, so that "a
  pair's value depends on neither its block nor its thread" (its header). A full tile of consecutive
  references is read in place from `ft_ref_terms`, a bin's columns one reference apart; any other tile is
  gathered bin by bin (at `28c753993`; the entries are unchanged bit for bit by `23eb95cc2`, its message).
- **SIMPLE has measured tiles on lists, on the CPU.** `simple_polar_matching_bench.f90`, type
  `polar_neigh_bench`: `neigh_blocks` cuts production's blocks (by half and previous cell, at most
  `PFTC_BLOCK_NB`); contained `block_cells` then calls the block kernel once per block and cell, with every
  state's members of the cell as the list and, as particles, those of the block that pooled the cell (or
  whose cone reaches it). For the members no computed pair is unasked: the waste count is 0, and what is
  lost is the kernel's fixed 16 x 32 product, which `count_call` adds up beside the pairs. For the cones the
  entries outside a particle's cone are counted as wasted. *Measured* on the M5 at 30 threads (run
  `mlxf_m1_m5`): block over per-pair wall 0.71 to 0.79 for the representatives, 3.2 to 3.6 for the members,
  4.0 to 7.7 for the cones. The absolute per-pair rates: no record in hand.

### The queue

- **The order after rank 2g.** Ranks 2d, 2e and 2f are delivered and committed (`ae7d623`); rank 2g, the
  user-facing hardening, runs next and before this batch (roadmap decision 17). Then the batch K3, K4, K5, K6,
  K7, one run at a time on the M5, each from the commit that holds the previous run's verified result. K3 is
  the first of the batch; it launches from the commit that holds this plan and rank 2g's result. No earlier
  run of the batch can change its premises. What can: rank 2g and the commit itself.
- **What rank 2g may change.** It changes `src/core/` and no toy file: integer `mean`, `var` and `std`
  promoted before the arithmetic, the Euclidean norms and floating means in a scaled form, empty `maxval` and
  `minval` given Fortran's identities, integer-scalar operators, failed saves that keep the file, and an index
  validator; it may add assertions to unit areas (`unit_ops`, `unit_io`, `unit_linalg`, `unit_array`,
  `unit_core`). So the area counts of decision 21 may rise, and a toy path that reduces with one of those
  operations may change its bits. Phase 0 reads 2g's report, records every area's count as found (they
  replace decision 21's), and records the identity digests twice on the base: the 364-line identity set of
  runs `mlxf_toy_layout` and `mlxf_kernel_forms` (SHA-256 `e2d65e88...4d33dba5` at `ae7d623`) and decision
  20's lines. A digest that differs from `ae7d623`'s is recorded with the operation 2g's report names and is
  the base from then on; one that differs with no such operation named is a stop.
- Phase 0 re-checks exactly these: the unit counts of decision 21; the dense route's digest lines of decision
  20; the dummy lists of `score_block_posterior`, `submit_block`, `collect_block` and `set_block_banks` in
  `mlxf_toy_polarft_calc.f90` (banks of shape (2nk, pftsz+1, nb), particle terms, since rank 2e); the members
  of `POLARFT_TAILS`; `SUITE_KEYS` (6 rows of length 96); the 26 lines of `scripts/toy_seam.txt` (18 host
  and glue files) and `SEAM_PENDING` 0; `AREAS` (12), `BENCHES` (6) and `NAMED_ONLY` (4) of the registry; the
  last Apple question's number (36 at `ae7d623`).
- If the order is changed and K4 or K7 runs first, the same list is re-checked, and K3 reads that run's
  report before Phase 2: K4 edits the map stage of the same driver and workspace; K7 adds tail forms.
- **What K3 leaves for the later runs.** K4 and K7 edit `mlxf_toy_polarft_*`, `mlxf_toy_eul_prob_tab*` and
  `mlxf_bench_polar_table.f90` after it. K3 changes no existing dummy list and no existing suite's keys; the
  dense digests do not move (decision 20). K7's tail forms must also serve list tiles: K3's report names the
  one place where the tail is applied to them. Run `mlxf_kernel_forms` measured K1's tail written a SIMD group
  per pair 3.3 times faster than K1's one thread per pair; whether K1's default moves to that form is K7's
  decision 27, so K3 uses K1's tail as it is, and a list route kept here inherits whatever K7 keeps.
- **K7 and the peaks.** Choosing a particle's best `npeaks` cells is the best-k reduction K7 plans for the
  device. In K3 it is a host step between the two stages of a `state` fill (decision 25), in one procedure
  of the driver, with its seconds reported; K7's plan decides whether it moves to the device.

**A reason for another order** (a recommendation for the maintainer's ruling; the plan is not written around
it). K4 could run before K3. K3's derived outcome at the 10-degree cone is an occupancy near or below the
break-even, and SIMPLE sends only the representative list through its block kernel today, while K4's shift
maps are in every fill and are slower on the GPU than in SIMPLE (7.46e4 against 1.09e5 maps/s on the window,
*measured*, families note). K4 does not depend on K3. Against it: the member stage of `state` is derived well
above the break-even (decision 6), K3 changes no existing dummy list, and either order works.

## 3. Decisions and rulings

Decisions 1 to 10 and 25 are put to the maintainer, each with a recommendation; until ruled, the
recommendation stands. Decisions 11 to 24 are defaults taken without a question.

1. **What "arbitrary sets" means under SIMPLE's names (to rule).** The list is `score_block_posterior`'s
   `irefs`: one list for the block's particles, entries `dists(nr, nb)`. A particle's own list is the
   driver's: it cuts blocks, gives each the union of its particles' lists and discards the pairs no particle
   asked for, as SIMPLE's `block_cells` does. Recommended: yes. Reason: it is SIMPLE's interface, the host
   kernel has it, and occupancy is then a property of the driver's cover that can be counted on the host. The
   alternative, a per-particle list interface of the calculator, has no counterpart in SIMPLE.

2. **The mlx3D note's proposal 2 (to rule).** Its measurement cannot be made on the dense score's products
   as they stand (section 2). Recommended: keep its intent, no list kernel before a measurement, and replace
   the measurement by Phase 1's probe of four layouts of the product, as scratch programs outside the
   repository, at the geometry of `2500_4` (pftsz 182, 61 shells), float32, GPU, each timed over at least 20
   evaluations after 3 warm-up ones:
   - **L1, cover:** today's `matmul` of whole resident tiles, for the tile pairs a list touches. Nothing new
     to measure but the rate per tile shape; read from `suite=time bt= rt=` on the base.
   - **L2, gathered union:** the list's references gathered by `mlx_take` into list tiles, then today's
     `matmul`. Measured: the gather's seconds per reference (357,216 B each, *derived*: 244 x 183 x 2 x 4),
     and the product's rate on list tiles of 64 and 250 references.
   - **L3, one generic `mlx_gather_mm`:** the tile pairs of L1 or L2 as one call with two index lists, against
     the loop of `matmul`. Measured: the rate, and the count of elements whose bits differ from `matmul`'s on
     each device.
   - **L4, the sorted single-column route:** the note's proposal in the only layout the code admits.
     Measured: the rate per pair.

3. **The graph form (to rule).** One form is built, chosen by a rule frozen here. Recommended default: **L2**.
   - Rule: from Phase 1's rates, predict the canonical pass (decision 9) for L1 with the references in cell
     order, L2, and each of them with L3's call, on seed 1's lists at cones of 10 and 20 degrees and for
     the `state` fill of decision 25. The smallest sum of the three predictions wins. A candidate within
     10 % of L2 loses to L2. L4 replaces the winner's product only if its rate per listed pair is above 1.30
     times the winner's.
   - Reasons for the default: its occupancy is the driver's own, whatever the order of the references on
     their spiral; it serves the shared representative list at occupancy 1, where L1 has one representative
     in a tile of 40 members; it changes no resident layout.
   - What L2 costs: a listed pair sits at another reference position than in the dense tile (decision 7), and
     every block copies its union (the list tiles stay while the next block's list is the same, so a shared
     list is gathered once per fill).

4. **Whether a pair's arithmetic may depend on its tile (to rule).** Recommended: yes on the device, no on the
   host backend, and the promise is stated in three parts:
   - Device, fixed lists, particle order, tile plan, device and build: entries are bit for bit the same over
     three repeats, two invocations, host teams of 1 and 24 and one or two slots (decision 16).
   - Device, another list, order or tile plan: a pair's entry is within the frozen bounds of the oracle; its
     bits are not promised. This is the record's schedule-identity rule (`mlxf_milestone1.md`), and the M5's
     GPU changed 2,872 of 64,000 entries with the particles' positions.
   - Host backend: a pair's entry is the same bits in any list, block and team, as SIMPLE's kernel promises
     (gate 7(b) on the toy's host kernel, with its plant in decision 15).

5. **The tile shapes (to rule).** Recommended: particle tiles bt 16 and 64 (`POLAR_BLOCK_BT`,
   `POLAR_CANON_BT`), list tiles of 64 and 250 references (`POLAR_GRID_R`'s first two), every tile padded to
   its shape as today. The canonical shape is the pair (bt, rt) with the smallest median pass on seed 1, one
   per configuration of decision 9, frozen in Progress before any judged run. Reason: a small particle tile
   raises occupancy and lowers the product's rate; only the measurement balances them.

6. **The fixture's lists (to rule).** Recommended:
   - **Directions:** the golden-angle spiral of `nspace` directions per state (polar angle
     acos(1 - (2i - 1)/n), azimuth i times the golden angle, as `spiral` of `mlxf_bench_projector.f90` makes
     it), c1, no mirror view.
   - **Previous orientations,** two sets from the seed: *uniform* on the sphere, and *clustered* (half of the
     particles within 20 degrees of one of 4 seeded axes, *guessed*, the other half uniform). The verdicts use
     the uniform set, the worse case for overlap.
   - **Lists:** cones of 10, 20 and 40 degrees (0.76 %, 3.0 % and 11.7 % of the directions, *derived*:
     (1 - cos θ)/2); and for `state` 64 cells of the directions (*derived*: 2,500 / 40, SIMPLE's default
     ratio of members to cells), their centres on a spiral of their own, the cells by the nearest representative as
     `new_from_distmat` makes them, `npeaks` 3: the shared list of 256 representatives, then each
     particle's pooled cells' members, 39 a cell and state on average.
   - **Order:** blocks cut in the batch's order, and in SIMPLE's order (`cut_blocks_state`: by half, then by
     the cell of the previous direction).
   - **Reported, not gated:** each configuration's occupancy (listed over computed pairs, padding included),
     beside the break-even of 21 % (graph tail) and 12 % (fused tail), and the rate against 3.75e6 pairs/s.
   - **Expected** (*derived*; hypotheses, not criteria): with 1,000 uniform particles per half, a block of bt
     particles that are neighbours covers bt/1000 of the sphere, a cap of 14.5 degrees (bt 16) or 29.3 degrees
     (bt 64); the union of their cones is the cap widened by the cone:

     | Cone | bt 16, ordered | bt 64, ordered | bt 16, batch order | bt 64, batch order |
     | --- | --- | --- | --- | --- |
     | 10 degrees | 16.8 % | 6.7 % | 6.6 % | 2.0 % |
     | 20 degrees | 34.2 % | 17.3 % | 7.8 % | 3.5 % |
     | 40 degrees | 55.7 % | 36.2 % | 13.6 % | 11.7 % |

     Arithmetic of the first row: (1 - cos 24.53°)/2 = 4.51 %, 0.760 / 4.51; (1 - cos 39.31°)/2 = 11.31 %;
     batch order, the union of independent cones, 1 - (1 - 0.0076)^16 = 11.5 % and 1 - (1 - 0.0076)^64 =
     38.6 %. Real blocks are not caps, so the ordered columns are upper estimates. At SIMPLE's default cone
     the GPU is expected near or below the break-even on this case; the deliverable is the measured number.
   - **Expected for the cover by cell** (*derived*; hypotheses): a cell pooled by m particles of a half, with
     n = 156 listed references (39 x 4), has the occupancy (m / (bt ceil(m/bt))) x (n / (rt ceil(n/rt))),
     1 before padding. With 1,000 uniform particles per half and p pooled cells each, m is 15.6 p on
     average: 141 at p = 9, 47 at p = 3. At m = 141: 79.5 % (bt 16, rt 64), 59.7 % (bt 64, rt 64), 61.1 %
     (bt 16, rt 250), 45.8 % (bt 64, rt 250); arithmetic of the first: 141/144 x 156/192. A part of 3 or 6
     processes holds a third or a sixth of the particles, so m falls to 47 and 23 and the occupancy at bt
     64 with it (47/64 and 23/64 of the particle tile): the splits show where the cover stops paying. The
     fill lists 512,000 pairs (representatives) and up to 2.81e6 (members at p = 9), 16.6 % of the dense.

7. **What the listed pairs must equal (to rule).** Recommended: three gates, in this order of strength.
   - **(a) The oracle, within frozen bounds, on both devices and both tails:** every listed pair's row and
     draw against `polar_memo_rows`'s row of the same global pair (`polar_compare_rows`, `polar_draws_off`),
     under bounds measured on seed 1 by the dense rule (decision 14).
   - **(b) The dense kernel, bit for bit, where the route can promise it:** the list 1..nrefs gives the dense
     route's entries (it is the dense route); on the host backend every listed pair equals the dense entry of
     that pair; on the CPU device the same, if Phase 1 counts 0 differing entries on seed 1 (the M2's record
     predicts it).
   - **(c) The dense kernel on the GPU, within the tail's frozen row tolerance and rotation count**
     (`POLARFT_TAIL_ROW_TOL`, `POLARFT_TAIL_ROT_FIX`, `POLARFT_TAIL_ROT_BLK`), with the count of entries whose
     bits differ reported per device. If Phase 1 counts 0 on the GPU as well, (c) becomes bit for bit and is
     frozen so.
   - Why not bit for bit everywhere: a listed reference sits at another tile position than in the dense
     run, and the record never forces identity across positions (decision 4). Why not the tolerance alone:
     where identity holds by construction, a tolerance would hide a wrong reference with a similar ring.

8. **The second driver (to rule).** Recommended: the toy gains `eul_prob_tab_neigh`, a type that extends
   `eul_prob_tab` as SIMPLE's does (toy policy, section 7: a driver per strategy, under the strategy's name).
   - Bindings under SIMPLE's names: `new_neigh_pipeline`, `fill_tab_range`, `kill`.
   - Modes, SIMPLE's `prob_neigh_mode` values: `geom` (the cones) and `state`, complete in its block stage
     and, if decision 25 is ruled so, its member stage. Not modelled: `shc` and `snhc`, the shift seeds and
     seed banks, the refinement of the best neighbours (`refine_best_neighbors`), the assignment.
   - **Host branch:** the same blocks and union lists through the host kernel `score_block_posterior` on the
     OpenMP team, as `fill_tab_range`'s `fill_host` does for the dense table; blocks are cut to at most
     `PFTC_BLOCK_NB` particles there. Declared difference: SIMPLE scores cones and members per pair; the toy
     has no per-pair scorer and covers by blocks on both backends, as SIMPLE's bench does in `block_cells`.
   - **MLX branch:** the union list handed to the calculator with the block, two slots in flight as today.
   - Supporting host modules: `mlxf_toy_eul_prob_tab_utils` (`cone_view_dist`, c1 and no mirror) and
     `mlxf_toy_srchspace_map` (type `srchspace_map`: `new`, `get_full2sub_map`, `get_sub2full_map`, `kill`).

9. **The keep rule of the list route, and the canonical driver (to rule).** Recommended:
   - **Canonical driver:** `eul_prob_tab_neigh%fill_tab_range` on case `2500_4`, uniform orientations,
     SIMPLE's block order, decision 5's canonical shape, seed 2, the steady pass (`passes=`, the median
     pass, K1's protocol), in two configurations (decision 25): mode `geom` at the 10-degree cone (SIMPLE's
     `athres_cont`), and the whole `state` fill. The elapsed time holds the block cuts, the lists, the peaks
     and pools, the variates, the submissions, the synchronisation and the collection.
   - **The list route is a second path for the dense kernel's computation** (house rule: above 30 %). It is
     kept if the canonical driver is at least 1.30 times faster with it than with the dense fill of the same
     particles followed by the selection of the listed entries, by decision 18's protocol. *Derived*: it
     computes about 1/20 of the pairs at the expected occupancy, so the hypothesis is a factor above 5.
   - **Reported beside it, not a keep rule:** the rate against 30 threads' dense block rate, and the measured
     occupancy against the break-even. A list route slower than 30 threads is still kept by the rule above:
     it is the reference for K7 and for larger cases.
   - The list route is kept if either configuration reaches 1.30; both verdicts are recorded.

10. **The fused form (to rule).** Recommended: it is entered only by its ceiling, measured first, and one
    candidate is built.
    - **The list route uses K1's tail in both forms from the start** (`tail=graph|metal`, one kernel object
      per tile shape). That is no new kernel.
    - **Candidate A, the masked tail:** K1's kernel with a mask input, so that an unlisted pair returns at
      once. Its ceiling at the dense plan is 1.28 (*derived* from K1's report: a fused pass of 0.628 s, of
      which the product and the transform are 1.14 - 0.65 = 0.49 s), below the rule. It is built only if the
      ceiling measured on the canonical configuration (a null tail in a scratch copy, K1's method) is at
      least 1.30.
    - **Candidate B, the pair-list kernel** (revised 2026-11-26 by run `mlxf_kernel_forms`): the product row
      of each listed pair and bin from the resident tiles and the block's particle terms; `mlx_irfft` and the
      tail follow on the listed rows only. Occupancy is 1 for any list and no order matters.
      - *Sizes:* the pair list's count and the capacity reach the kernel in an int32 input of fewer than 8
        elements, never as template integers: equal per launch and 3.05 / 2.62 ms against 42.7 / 42.0 ms per
        new value (*measured*, suite `sizes`, on K2's gather and the insertion kernel). Capacities need not be
        powers of two (the draft's rule, withdrawn with the cost it bounded).
      - *Buffers:* the pair list lives in a persistent buffer of a fixed capacity (the largest count of seed 1
        times 1.25), its tail masked by a sentinel against the count on the device, with one host wait per
        pass, never one per tile or block: 2.42 / 2.38 times faster than a wait per tile at this plan's own
        tile (183 bins of 64 by 244 by 500, *measured*, suite `waits`); it holds 2.6 times the per-tile form's
        MLX peak, which is reported and is no reason to reject it. A count above the capacity redoes the
        pass at a larger capacity and is counted.
      - *Launch shape:* the scratch probe of its product times two forms, a thread per (pair, bin) and a
        SIMD group per (pair, bin) summing the 2nk shell terms with `simd_sum`; the faster is the candidate.
        Reasons: every per-item reduction run `mlxf_kernel_forms` measured was faster a SIMD group per item
        (3.3 for K1's tail, 2 to 4 for the selection), and mlx3D found a per-thread fused matrix-vector product
        slower than MLX's matrix products (lessons note, section 2), which is B's risk.
      - Its ceiling is the canonical pass over the same pass at occupancy 1 (a shared list of the same size).
        It is built only if that ceiling is at least 1.30 and the probe of its product alone predicts a
        canonical pass at least 1.30 times shorter than the list route's.
    - The ceilings are measured on both configurations of decision 9, and a kernel is judged and kept per
      mode. If both candidates qualify, the larger ceiling is tried first and the other is not built. If
      neither qualifies, Phase 5 is recorded as entered and not built, with the ceilings.
    - A kernel that is built is kept only at 1.30 on the canonical driver by decision 18's protocol, under
      decision 7's gates with (c) frozen on seed 1 for it, and decision 16.
    - The wrapper's facts kept to (*measured*, parity Phase 10, K1, K2 and run `mlxf_kernel_forms`): no
      float64; threadgroups up to 1,024 threads (an evaluation above fails); MLX's kernel library is keyed by
      the source and never by the launch configuration, a new object of an existing source costs 2.6 to 3.1
      ms at its first evaluation and a new source about 42 ms; `threadgroup` arrays up to 32,768 B with
      `threadgroup_barrier`, and the SIMD-group functions, exact and bit-repeatable through the wrapper (Apple
      question 26). No probe of these features is planned: a kernel of this plan that uses one re-checks it in
      its own gates (decision 16's repeatability and gate 7(a)), not in a phase of its own.
    - MLX issue #4603 (wrong rows from a custom kernel under the default math mode on another machine) is
      a risk for both tails on list tiles: gate 7(a) and decision 16 are run on the GPU for each.

### Defaults taken without a question

11. **Declared differences from SIMPLE,** each a line of the report: c1 only and no mirror view; one cone per
    fill, not a slot per particle; cones and members scored by blocks, not per pair; the peaks taken once
    per half, after its representatives' entries are collected (the rule sees one particle's entries, so the
    cells are those SIMPLE's per-block order gives); no cell-reach pruning (the toy lists
    by a direct distance to every direction); the directions and the previous orientations come from the
    fixture through a setter, SIMPLE reads `build%eulspace` and `build%spproj_field`; the fill hands its
    listed entries over, SIMPLE keeps a table for its assignment (`open_assignment`, `assign_batch`,
    `close_assignment` are not modelled); the `cont_view` branch of `geom` (`fill_geom_views`,
    `assign_geom_views`, added by `c1f255d20`) is not modelled: it solves continuous views per particle and
    sends nothing through a block kernel.

12. **Files and classes** (seam ledger; toy policy, section 8).
    - Host, new: `mlxf_toy_eul_prob_tab_neigh`, `mlxf_toy_eul_prob_tab_utils`, `mlxf_toy_srchspace_map`. They
      import no MLX name. They hold no device state, so they have no glue and no backend of their own: the
      driver takes the backend of the calculator it is given, as `eul_prob_tab` does, and has a host route
      (decision 8). The two helpers are plain host code on both backends.
    - Device, new: `mlxf_toy_polarft_workspace_lists`, a submodule of `mlxf_toy_polarft_workspace`: the list
      tiles and the list form of `submit`. The state stays behind the calculator's one
      `class(device_work), allocatable` component.
    - Glue, edited: `mlxf_toy_polarft_block_mlx` (the list crosses here; the refusal goes; the stubs stay).
    - The ledger grows from 26 to 30 lines, host and glue files from 18 to 21; `SEAM_PENDING` stays 0.
    - Sub-suite `seam`: 1,000 cycles of `new_neigh_pipeline` and `kill` around a list fill leave the
      registry's count, on both devices; the refusals of decision 15.
    - The off-state program fills the cone and `state` tables of the small fixture on the host route, writes
      their lines (compared with `mlxf_test_exec`'s by `scripts/check_toy_offstate.sh`), and asks for a fill
      on a calculator that refused the MLX backend: the driver reports the calculator's "built without MLX".

13. **The calculator's additions** (mirror ledger, kind `addition`, each with its reason): `set_block_refs`
    (the list of the next block queued by `submit_block`, which is held to five dummies) and, only if L1 wins
    decision 3, `set_ref_order`. `score_block_posterior`, `submit_block`, `collect_block`,
    `set_block_variates` keep their dummy lists; the variates and the entries of a listed block have the
    shape (nr, nb). The driver's additions: `set_eulspace` (directions and previous orientations),
    `set_subspace` (the cells' map and representatives; SIMPLE reads `build%subspace_inds` and
    `build%subspace_full2sub_map`), `set_neigh_options` (mode, cone, `npeaks`, block order),
    `batch_list_entries`, `batch_pooled_cells`, `fill_occupancy`.

14. **Tolerances.** Measured on seed 1 on both devices, on the small fixture and at the bench, by the dense
    rule: the bound on a listed row's error is `POLAR_ROW_FACTOR` (2) times the CPU device's measured error,
    the rotation bound max(2 n_cpu, the fixture's or the block's quantum). Frozen as `POLAR_NEIGH_ERR_CPU`,
    `POLAR_NEIGH_ROT_CPU`, `POLAR_NEIGH_BLOCK_ERR_CPU` and `POLAR_NEIGH_BLOCK_ROT_CPU` in `mlxf_test_defs.f90`
    and in Progress, then judged on seeds 2 and 3, at the bench as well. Ceiling: a seed-1 error above 2 times
    the dense route's on the same fixture and device is a stop (*guessed*: the arithmetic per pair is the
    dense one at another position). The host backend is judged against the ring oracle of sub-suite
    `polarft_host` under that suite's bounds.

15. **Planted violations,** each shown to fail its gate and removed, the failing line in Progress:
    - a gathered reference off by one position: gate 7(a) and 7(b) fail;
    - a variate keyed by the list position instead of `ref_full(irefs(r))`: `polar_draws_off` is not 0;
    - the cone doubled in the toy: the lists differ from the oracle's (decision 17);
    - computed pairs counted without the padding: the occupancy differs from the oracle's count;
    - a variate keyed with the pass's number: decision 16 fails;
    - the previous cell left out of a pool, a tie given to the later cell, a pool not shared by the states:
      the pooled cells differ from the oracle's rule on the same entries;
    - a cell's members kept for a particle that did not pool it: the listed entries differ from the oracle's;
    - a host kernel tile gathered from the wrong column: decision 4's host promise fails;
    - a host file importing `mlxf`, a file missing from the seam ledger, a public binding missing from the
      mirror ledger: rules `seam` and `mirror` fail;
    - a stub's message changed: `scripts/check_toy_offstate.sh --exec` fails.
    Refusals asserted with their messages: a reference outside 1..nrefs; a list with a repeated reference; an
    empty list; variates of another shape than (nr, nb); an unknown mode; a cone outside 0 to 180 degrees; a
    fill before `set_eulspace`; a fused tail on the CPU device.

16. **Repeatability is its own gate.** For every configuration that is timed or kept: three repeats in one
    process, two invocations, host teams of 1 and 24, one and two slots give one digest of the listed entries
    (`digest_entries` over distances and rotations in list order, and for `state` the pooled cells), on each
    device, on the GPU for both tails and for a kernel of decision 10. A digest that differs is a stop.

17. **The oracle of the lists.** New module `mlxf_oracle_neigh` in double precision, sharing no code with the
    toy: the spiral, the angular distance from unit vectors, the cone lists by exhaustive search, the cells by
    the nearest representative, the block cuts of both orders, the peaks and the pool by SIMPLE's rule
    (written from section 2's description, applied to entries handed in), and the occupancy of a cover. The
    pooled cells are data: the toy's must equal the rule applied to the toy's own collected representative
    entries (a gate); the pools the rule gives on the oracle's drawn distances are compared and the
    particles that differ counted (reported: a near tie or another drawn rotation moves a peak). The fixture
    refuses a direction within 1e-3 degrees of a cone's edge (*guessed*, SIMPLE's `REACH_TOL`), so that
    float32 and float64 list the same references. Self-checks in sub-suite `oracle_neigh`: a cone of 180
    degrees lists every direction; the listed fraction is (1 - cos θ)/2 within the spiral's granularity; every
    direction is in one cell; a hand-made table with a tie and a previous cell outside the peaks gives the
    pool written beside it.

18. **The verdict protocol** (K1's decisions 15 to 20, unchanged): the two configurations frozen in Progress
    before any judged run; a ceiling first; the steady pass with `passes=` chosen on seed 1 so that the timed
    loop lasts at least 10 s (odd, at most 201), the median pass; interleaved pairs a, b, a, b; 5 judged pairs
    and 2 reported; kept at a median ratio of at least 1.30 with at least 4 of 5 pairs; a median inside 1.25
    to 1.35 adds five pairs; a control of a configuration against itself (3 pairs) within 0.10; both
    invocations. With parts sharing the GPU the ratio is read on the time from go to the last exit (ruling R1
    of K1), never on the sum of per-process median rates.

19. **Timed as SIMPLE runs.** `scripts/run_parts.sh` with `RUN_PARTS_SUITE=neigh`, `RUN_PARTS_LOAD=4`, a fresh
    series table per configuration, 1, 3 and 6 processes at 30, 10 and 5 threads, on `2500_4`. If the guard
    does not run 6 processes of `2500_4` (the dense route's part holds 20.81e9 B, *measured*, and 6 were
    predicted at 119.58e9 B), 6 run on `2500_1` as in K1 and the row says so. Reported: the total rate in
    listed pairs per second, the rate per process, one process's footprint and MLX peak, `uptime` before each
    step, and for `state` the poolers per cell and the occupancy of each split. Memory per part is reported and
    never a reason to reject a faster form.

20. **The dense route does not move.** Phase 0 records, twice, the digest lines of `suite=accuracy` (both
    devices, both tails on the GPU) and of `suite=time case=2500_4 bt=64 rt=250 passes=3` (both tails), on
    rank 2e's layout: the tiles made by `memoize_refs` from `ft_ref_terms` and packed on the host, the driver
    refusing untiled references (`ref_tiles_current`). They are the base's lines, after rank 2g (section 2,
    "The queue"), not the draft's; every later phase reproduces them. A digest that moves is a stop.

21. **Counts.** The unit areas keep the counts Phase 0 finds on the base in Debug and Release. At `ae7d623`
    (*measured*, runs `mlxf_refactor`, `mlxf_toy_layout` and `mlxf_kernel_forms`): core 214 to 216 (the
    allocator decides two checks), array 193, ops 2,462, fft 194, linalg 632, compile 63, fast 152, random
    486, transforms 274, io 846, distributed 55; rank 2g may raise ops, io, linalg, array and core, and Phase
    0's counts replace these. In `unit_kernels` (1,953 at `ae7d623`) the ten sub-suites other than `seam` keep
    theirs (`polarft_calc` 333, `polar_shiftmap` 794, `eul_prob_tab` 105, `polarft_tail` 55,
    `oracle_projection` 44, `projector` 100, `projector_chain` 91, `pcg_solver` 86, `reconstructor_pcg` 192,
    `polarft_host` 65); `seam` grows from 88; the new sub-suites `eul_prob_tab_neigh` and `oracle_neigh` add
    theirs. Each phase records the new total. The fast gate keeps 13 entries and stays under 38.74 s (10.44 to
    10.51 s in Release, *measured*, run `mlxf_kernel_forms`); the new sub-suites may add 2 s (*guessed*).

22. **The small fixture** is `mlxf_polarft_host_fixture`'s (pftsz 16, 6 shells, 40 references, 44 particles),
    with the references' directions and the particles' previous orientations added from hash streams of their
    own, so that the fixture's existing values and the dense table's off-state lines stay byte for byte.
    The 40 references are read as 2 states of 20 directions; the previous orientations lie within 10 degrees
    of a direction, so no cone is empty. Cones of 30 and 60 degrees (about 1 and 5 directions per state,
    *derived*: 6.7 % and 25 % of 20); 4 cells of 5 members, `npeaks` 2 (2 or 3 pooled cells); particle tiles
    of 8, list tiles of 16, both orders, partial tiles both ways.

23. **The bench** is a suite `neigh` of `bench_polar_table` with its row in `SUITE_KEYS` (whose length of
    96 grows): `cases case bt rt device nthr nparts part go passes tail mode cone order orient lists check
    npeaks cells`. `lists=route` is the list route,
    `lists=dense` the dense fill with selection (decision 9's baseline). Rows go to `bench_polar_table.tsv`
    with the columns `run_parts.sh` reads unchanged (rate 20, work 21, MLX peak 26, cache 27, median pass 30;
    the work is listed pairs) and the list's columns appended: listed pairs, computed pairs, occupancy,
    blocks, the largest and the mean union, the pooled cells per particle, the poolers per cell. `check=1`
    judges accuracy on the 64,000-pair block as `suite=accuracy` does and times nothing.

24. **Probes and records.** Probes are scratch programs under the run's `scratch/probe/`, linked against the
    installed library, never added to the repository. A finding about MLX or mlx-c becomes an entry after the
    last one Phase 0 finds in `doc/collaboration/apple_questions.md` (37 and following at `ae7d623`), written
    and not sent: expected is the sorted route's reach (one row, one list, and a wide route for 16-bit floats
    only: is a grouped route for larger left operands planned). If a sort is used, its stability is question
    36's, amended with what the run measured, not a new entry; no gate relies on it.

### Added by amendment, 2026-11-26

25. **The member stage of `state`, and the canonical configuration (to rule).** Recommended: model it, and
    judge both configurations.
    - **The two-stage fill.** Stage R: the representatives as one list for every block of the half, gathered
      once, the entries collected. Host step: each particle's peaks and pool by SIMPLE's rule (section 2)
      from the collected drawn distances. Stage M: cell by cell, every state's members of the cell as the
      list, against the particles of the half that pooled it, in SIMPLE's order; on the host backend per
      block and cell, as `block_cells` does. No computed pair is unasked: the occupancy is 1 before padding.
    - **Why:** it is the mode SIMPLE's parameter defaults to and `exec_classify3D_refs` sets; its lists are
      unions of whole cells, which cones are not; its derived occupancy is 46 to 80 % at one process
      (decision 6), above the break-even, where the 10-degree cone's is 7 to 17 %.
    - **What lists that are data cost:** a pool depends on the entries' bits near a tie. The gates are
      decision 17's rule on the toy's own entries, exactly; decision 7 on the pairs the toy listed; decision
      16 over both stages and the pools. The dense baseline of decision 9 forms its pools from its own
      entries: listed pairs that differ by more than 1 % between the two configurations are a stop (*guessed*).
    - **The canonical configuration, three choices:**
      - *The cone only* (the plan before the amendment): no member stage; 1,170 min in all. It tells SIMPLE
        about `refine3D_local`'s `geom` only, where the derived occupancy is poor.
      - *The `state` fill only:* the member stage in the driver, the pool in the oracle, the bench's mode; no
        new file; Phase 3 +60 min, Phase 4 +45 min. It tells SIMPLE whether its default mode's fill pays as
        blocks on the GPU, and from how many poolers per cell.
      - *Both judged* (recommended): the same, with a second verdict and second splits; Phase 4 +90 min and
        Phase 5 +30 min, 1,350 min in all. The keep rule is decision 9's, on either; the report puts the two
        occupancies side by side, which is what a design of SIMPLE's GPU route needs.
    - **The peaks stay on the host** in K3 (the queue): the 256 entries per particle are collected anyway,
      the rule has an order of ties and a previous cell, and K7 owns the device's best-k. The seconds from
      the collection of stage R to the first submission of stage M are reported.

## 4. Not in this plan

- SIMPLE's per-pair scorers, its stochastic modes, the shift seeds and seed banks, the refinement of the
  best neighbours and the assignment.
- Point groups other than c1, mirror views, a cone per particle.
- The shift maps on lists (K4) and other objectives or reductions on list tiles (K7).
- A bound on the dense route's queue (K1's report: "belongs to K3 or K4"). The list driver keeps at most two
  blocks in flight; the dense route's tiles ahead are left to K4. The list route's MLX peak is reported.
- `mlx_block_masked_mm` and `mlx_segmented_mm` as product routes (section 2).
- Any change of the dense route's defaults, of `src/core/` or of `src/defs/`.
- A comparison with SIMPLE's per-pair rates: no record in hand.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement on the base | both builds without a warning; decision 21's counts; decision 20's digests twice; the queue's list re-checked |
| 1 | measurement: scratch probes | decision 2's four layouts measured; the bit counts of decision 2 and of Phase 1's step 5; decision 3's rule applied and the form frozen |
| 2 | tests-only: the list route of the calculator | sub-suite `eul_prob_tab_neigh`, calculator part: decision 7's gates on seed 1 frozen, then seeds 2 and 3, both devices, both tails, and the host backend; decisions 15 and 16; decision 20 |
| 3 | tests-only: the driver, the oracle of lists, the seam | `oracle_neigh`; the lists, the pooled cells and the occupancy against the oracle; decision 7 through the driver on both backends; `seam`; `scripts/check_toy_offstate.sh --exec`; decisions 15, 16, 20 |
| 4 | measurement; possibly a deletion | `suite=neigh` accuracy frozen on seed 1, judged on seeds 2 and 3; decision 5's shape frozen; decision 6's table measured; decision 9's two verdicts; decision 19's splits |
| 5 | tests-only or nothing | the two ceilings; a built kernel under decisions 7, 15, 16 and 18; else the record of not building |
| 6 | documentation | the report; the last-phase gates; `git status` shows file-table paths only |

Every phase ends with Debug and Release built from scratch with `-DMLXF_WERROR=ON` and no warning, the fast
gate in both, `scripts/check_tree.sh` passing (since rank 2d it also checks rule `publist`, rule `size`, every
folder's `.inf` description and `doc/code_base_map.md`), `scripts/restyle_fortran.py` and
`scripts/format_use_blocks.py` run on every Fortran file touched (the second with explicit file names), and
decision 21's counts. The last
phase adds `scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`,
`scripts/release_gate.sh --allow-dirty` and the Release fast gate 10 times of 10.

## 6. Acceptance

- **The exit of the design note's row K3:** decision 7's gates pass on seeds 2 and 3 (Phases 2 and 3) and at
  the bench (Phase 4); decision 6's table is filled with measured occupancies and rates for the
  three cones, both orders, both orientation sets and both particle tiles, and for the `state` fill at 1, 3
  and 6 processes (Phase 4).
- **Numbers:** decisions 5, 7, 9, 10, 14 and 18, each frozen in Progress before the run it judges. A tolerance
  is never taken from the run it judges, a seed is never changed to pass, and a failing gate on seed 2 or 3 is
  a diagnosis, not a new calibration.
- **Both ledgers** list every new file and every public type, binding and procedure of the new toy modules.
- **Reported, not gated:** decision 6's occupancies beside the break-even; the rates against 3.75e6 pairs/s;
  the entries whose bits differ from the dense kernel's, per device; Phase 1's rates of the four layouts; the
  gather's share of a pass; the footprints and MLX peaks; the shared list's rate; the stages' seconds.
- **Hypotheses, each with its test** (*derived* or *guessed*; none is a criterion): decision 6's table; the
  list route beats the dense fill with selection by more than 5 at the 10-degree cone (decision 9); the
  shared representative list runs at the dense rate per computed pair, 4.7 times 30 threads (*derived*:
  1.76e7 / 3.75e6); the `state` fill runs above 45 % occupancy at one process and beats 30 threads' block
  rate, and its occupancy falls with the number of parts; at the 10-degree cone on `2500_4` the GPU does not
  beat 30 threads' block rate; three and six processes share the GPU without loss on the time from go to the
  last exit; the gather is under a third of a pass (*guessed*); candidate A's ceiling stays under 1.30;
  candidate B's is far above it at the cone (1 over the occupancy) and near it for the `state` fill.
- **Reserved for the maintainer:** whether the miniature reads like SIMPLE's neighbourhood fill; what the
  measured occupancies mean for a GPU route of `refine=*neigh*` in SIMPLE (the block stage of `state`, its
  members by cell, the cones).

## 7. Common rules and stop conditions

- No file outside the table. No bound loosened, no fixture changed to pass.
- A test executable run directly on the GPU is run with `MLX_ENABLE_TF32=0`.
- MLX is called by one submitting thread, outside any OpenMP region; the host loops (lists, block cuts,
  variates, the host kernel) may use the team.
- A timed step waits for a one-minute load of at most 4 and records `uptime`; no build or test runs beside it.
- A large host array is not staged and released where a footprint is measured.
- Git is read-only. The run writes its notes with the editor tools; its report ends with a commit message
  that carries no attribution or co-author line and names every new file.

**Stops:**
- a premise of "The queue" does not hold on the base;
- the route needs a wrapper the public module does not have, or a change of `src/core/` or `src/defs/`;
- Phase 1 finds that no layout computes a list of 152,000 pairs at `2500_4` faster than the dense pass
  (decision 9's hypothesis fails before anything is built): reported, with the four rates;
- a tolerance measured on seed 1 is above decision 14's ceiling;
- a gate of decision 7 fails on the unplanted code after one attempt to find the fault in the toy (the
  existing oracle is not edited: a suspected oracle fault is a stop with the evidence);
- a digest of decision 16 or 20 moves; or Phase 0 finds an identity digest that differs from `ae7d623`'s
  with no operation of rank 2g's report to explain it (section 2, "The queue");
- the `state` fill's listed pairs differ by more than 1 % between the list route and the dense baseline;
- SIMPLE's code contradicts a decision of section 3 in a way no declared difference resolves;
- one bench process exceeds `POLAR_BUDGET_SHARE` of the machine's memory, or the one-process bench cannot run;
- a phase exceeds twice its box;
- the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
oracles share no code with the toy; no SIMPLE source copied; a tolerance frozen before the run it judges; the
graph form kept; the repeatability gate for every form that is kept; the dense route's digests.

## 8. Phases

### Phase 0, the base and its numbers (box: 90 min)

1. Record the base's hash, `uptime`, the compiler and the versions of MLX and mlx-c. Build Debug and Release
   from scratch in the run's trees; no warning.
2. Run the fast gate in both and every unit area; record decision 21's counts and the fast gate's seconds.
   Read rank 2g's report and record what it changed of the queue's list (section 2).
3. Copy `polar_case.txt` of run `mlxf_toy_arch` (`~/agent_runs/mlxf_toy_arch/scratch/keep/`, SHA-256
   `90a974fa...f1d9`) into the run's `scratch/keep/`; check the sum.
4. Record decision 20's digests and the 364-line identity set (its script from run `mlxf_toy_layout`) twice,
   and the dense pass of `2500_4` at bt 16 and 64 with rt 64 and 250, both tails, `passes=9` (L1's rates, and
   the baseline of decision 9; rank 2e made these passes 4 to 10 % shorter than K1's report, so K1's numbers
   in section 1 are context only).
5. Re-check the queue's list (section 2).

Exit: the counts, the digests and the rates are in Progress; the premises hold.

### Phase 1, the probe of the product's layouts (box: 150 min)

1. Write the four scratch programs of decision 2 under `scratch/probe/`. Each prints its shapes, the route's
   rate and the load.
2. L2: the gather's seconds per reference for unions of 64, 250, 500 and 1,000, and whether the gather can
   address the listed references without a copy of the bank (a copy of the whole bank per block is a stop).
3. L3: the generic `mlx_gather_mm` against the loop of `matmul` at the same tile pairs; the elements whose
   bits differ, on each device.
4. L4: the single-column route's rate per pair, and the confirmation by its rate that the sorted route runs.
5. The bit question of decision 7: a block scored with a reference at two positions of a tile, both devices,
   seed 1; the count of entries that differ.
6. Make seed 1's lists with a scratch copy of the oracle's rule; predict decision 3's passes; freeze the form
   and the promise of decision 7(b) and (c) in Progress.

Exit: the four rates, the two bit counts, the chosen form and the frozen promises are in Progress. No file of
the repository but this note has changed.

### Phase 2, the list route of the calculator on the small fixture (box: 240 min)

1. `mlxf_toy_polarft_workspace_lists.f90`: the list tiles and the list form of `submit`, with the tail of the
   workspace in both forms. `mlxf_toy_polarft_block_mlx.f90`: the list crosses, the refusal goes.
   `mlxf_toy_polarft_calc.f90`: `set_block_refs` (and `set_ref_order` if L1 was chosen). Both ledgers.
2. The fixture's directions and orientations (decision 22); `polarft_host` keeps 65 and its lines.
3. Sub-suite `eul_prob_tab_neigh`, calculator part: lists of 1, 2, 7 and 40 references and a sparse shared
   list, through `score_block_posterior` and through `submit_block` and `collect_block`; decision 7(a)
   measured on seed 1 on both devices and frozen (decision 14); then seeds 2 and 3; 7(b) and 7(c); the host
   backend's promise; decision 16; the refusals; the plants of decision 15 that concern the calculator.

Exit: the gates pass on seeds 2 and 3 on both devices, both tails and the host backend; the plants failed and
are removed; decision 20's digests are reproduced.

### Phase 3, the driver, the oracle of the lists and the seam (box: 270 min)

1. `mlxf_oracle_neigh.f90` with its self-checks (sub-suite `oracle_neigh`).
2. `mlxf_toy_srchspace_map.f90`, `mlxf_toy_eul_prob_tab_utils.f90`, `mlxf_toy_eul_prob_tab_neigh.f90`:
   decisions 8 and 25: mode `geom`; mode `state` in its two stages with the host step between them; both
   branches, both block orders, `fill_occupancy`.
3. The driver's part of sub-suite `eul_prob_tab_neigh`: the lists, the block cuts and the occupancy equal the
   oracle's; the pooled cells equal the oracle's rule on the toy's entries, the pools on the oracle's
   distances compared and counted; decision 7 through the driver on both devices and the host backend; the
   host table of a team of 4 equals that of one thread byte for byte; decision 16; the refusals and the
   remaining plants.
4. Sub-suite `seam`: the cycles and the refusals of decision 12. The off-state program and
   `scripts/check_toy_offstate.sh --exec`.

Exit: the lists and occupancies equal the oracle's; the gates pass on seeds 2 and 3; the seam and off-state
checks pass; both ledgers are complete; the fast gate's seconds are recorded.

### Phase 4, the bench: occupancy, rates and the list route's verdicts (box: 330 min)

1. `suite=neigh` in `mlxf_bench_polar_table.f90` (decision 23). Accuracy on the block: measured on seed 1 on
   both devices, frozen, judged on seeds 2 and 3.
2. On seed 1, one process: the median pass for bt 16 and 64 with list tiles of 64 and 250 at the 10-degree
   cone, ordered, and for the `state` fill; freeze decision 5's canonical shape, `passes=` and the
   configurations of decision 9.
3. Decision 9's two verdicts by decision 18's protocol, both invocations. If the list route is not kept, its files
   stay only as far as the driver's host route needs them; the report says what was removed.
4. Decision 6's table on seed 2: three cones and the shared list, two orders, two orientation sets, bt 16 and
   64, both tails: listed pairs, computed pairs, occupancy, the median pass, the rate, MLX peak; for the
   `state` fill each stage's pairs, the poolers per cell and the host step's seconds.
5. Decision 19's splits for both canonical configurations, each tail.

Exit: the verdict, the table and the splits are in Progress with their `uptime` lines; every timed
configuration passed decision 16.

### Phase 5, the fused form, by its ceiling (box: 210 min)

1. Measure candidate A's ceiling (a null tail in a scratch copy) and candidate B's (the pass at occupancy 1)
   on both canonical configurations; record them.
2. If neither is at least 1.30: record "entered, not built" with the numbers and go to Phase 6.
3. Else probe the chosen candidate in a scratch program (for B: the product's rate on seed 1's pair list;
   a source that does not compile or a grid above the launch limits is a recorded failure, not a retry
   loop), apply decision 10's condition, and build it into the workspace only if it holds.
4. A built kernel: decision 7's gates with (c) frozen on seed 1, decisions 15 and 16 on the GPU, its refusal
   on the CPU device, then decision 18's verdict against the list route's faster tail and decision 19's
   splits. A kernel below 1.30 is deleted and the record kept.

Exit: the ceilings and the verdict, or the record of not building; decision 20's digests reproduced.

### Phase 6, the record (box: 60 min)

1. The last-phase gates of section 5, with the Release fast gate 10 times of 10.
2. The report `doc/implementation_notes/completed/mlxf_kernel_k3_report.md`: what was built, every number
   with its origin, the declared differences, the hypotheses and what the tests said, what the maintainer
   rules, and the commit message.
3. The families note (sections 2a, 3 and 8: the open decisions answered, the row K3), the roadmap's row, the
   toy and test policies, the history, the index, `README.md`, and the Apple entries of decision 24.

Exit: `scripts/check_tree.sh` passes; `git status` shows paths of the file table only.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab_neigh.f90` (new) | the toy driver `eul_prob_tab_neigh`: the cones, the two stages of `state`, the pool | 3, 4 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab_utils.f90` (new) | `cone_view_dist` | 3 |
| `src/test/toys/polar/mlxf_toy_srchspace_map.f90` (new) | the toy `srchspace_map` | 3 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_lists.f90` (new) | the list tiles, the list form of `submit`, a kernel of decision 10 | 2, 4, 5 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab_neigh_tester.f90` (new) | sub-suite `eul_prob_tab_neigh` | 2, 3, 5 |
| `src/test/oracles/mlxf_oracle_neigh.f90` (new) | the oracle of the lists and of the pool | 3 |
| `src/test/oracles/mlxf_oracle_neigh_tester.f90` (new) | sub-suite `oracle_neigh` | 3 |
| `src/test/toys/polar/mlxf_toy_polarft_calc.f90` | the interfaces of `set_block_refs` and of the list's glue | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_block.f90` | the host side of `set_block_refs`; the refusals of a list | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_block_mlx.f90` | the list crosses to the workspace; the refusal goes | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace.f90` | the interfaces of the list submodule; the list tiles' handles | 2, 5 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_score.f90` | the tile's graph shared with the list form | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_lifecycle.f90` | the list tiles released with the others | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90` | the tail on list tiles; candidate A's mask if built | 2, 5 |
| `src/test/toys/polar/mlxf_toy_polarft_memo.f90`, `src/test/toys/polar/mlxf_toy_polarft_memo_mlx.f90` | only if L1 wins decision 3: the references' order | 2 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab.f90` | what the extension needs visible, no dummy list changed | 3 |
| `src/test/toys/polar/mlxf_polarft_host_fixture.f90` | the directions, the orientations, the cone table and its lines | 2, 3 |
| `src/test/toys/mlxf_toy_seam_tester.f90` | the driver's cycles and refusals | 3 |
| `src/test/bench/mlxf_bench_polar_table.f90` | suite `neigh` | 4, 5 |
| `src/test/framework/mlxf_test_defs.f90` | the tolerances, the fixture's members, `parameters`' new members, the modes | 2, 3, 4, 5 |
| `src/test/framework/mlxf_test_registry.f90` | the two sub-suites' rows | 2, 3 |
| `src/test/toys/polar/polar.inf` | the folder's description: the second driver and its helpers | 2, 3 |
| `src/test/oracles/oracles.inf` | the folder's description: the oracle of lists | 3 |
| `doc/code_base_map.md` | regenerated by `scripts/generate_codeoverview.py` for every new Fortran file and `.inf` change, and for a file deleted (the static gate checks it) | 2, 3, 4, 5 |
| `test/CMakeLists.txt` | the comment on the area `kernels`, if it names the sub-suites | 3 |
| `test/offstate/mlxf_offstate_exec.f90` | the cone table on the host route; the driver's refusal | 3 |
| `test/offstate/CMakeLists.txt` | only if a source outside the ledger is needed | 3 |
| `scripts/toy_mirror.txt` | the ledger's lines | 2, 3, 5 |
| `scripts/toy_seam.txt` | four new lines | 2, 3 |
| `scripts/check_toy_offstate.sh` | the cone table's lines compared, if the comparison names its lines | 3 |
| `doc/policies/toy_example_policy.md` | section 7: the second driver | 6 |
| `doc/policies/test_environment_policy.md` | the area `kernels`; the suite `neigh` | 6 |
| `doc/policies/binding_contract_policy.md` | the gathered product, if Phase 1 measured what it does not state | 6 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | sections 2a, 3 and 8 | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | the row of K3 | 6 |
| `doc/implementation_notes/planned/mlxf_mlx3d_lessons.md` | proposal 2's outcome | 6 |
| `doc/collaboration/apple_questions.md` | entries 32 and following | 6 |
| `doc/implementation_notes/README.md` | the index | 6 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 6 |
| `README.md` | the status, where it names the toys | 6 |
| `doc/implementation_notes/planned/mlxf_kernel_k3.md` | this note: Progress | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/completed/mlxf_kernel_k3_report.md` (new) | the report | 6 |

## Progress

Nothing has run. The run fills one subsection per phase: times, machine, `uptime`, what was built and run,
every number with its origin, the values frozen before the runs they judge, the plants' failing lines, stops.
