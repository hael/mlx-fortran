# K7, family A4: the cc objective and the classic strategies' reductions in the polar toy (run `mlxf_kernel_k7`, on the M5 Ultra)

Status, 2026-11-26: planned; ruled as recommended by Hans, 2026-11-26 ("Rule as recommended"), every decision of section 3 and the run order K4, K3, K5, K6, K7; revised after ranks 2d to 2f (runs `mlxf_refactor`, `mlxf_toy_layout`,
`mlxf_kernel_forms`). Run `mlxf_kernel_k7` on the M5 Ultra (30 cores, 103.1 GB, the only GPU and the only
machine that builds the library), in the session, in a copy of the checkout, one run at a time. Base: the
commit that holds this plan, after rank 2g's result and K6's (the run pins its hash in Phase 0 and records
it). The revision was checked against `ae7d623` (ranks 2d to 2f committed) with the three uncommitted document
edits of 2026-11-26; the draft was written at `b2c43a4`. SIMPLE is pinned at `28c753993`, the mirror ledger's
pin since rank 2e, read with `git -C ~/src/SIMPLE show 28c753993:<path>` only and never edited; between the
draft's pin `d354efee2` and this one `23eb95cc2` changed `simple_polarft_corr.f90` and `simple_polarft_memo.f90`
(findings 2, 6 and 8 are re-read there). Supersedes: none. Fifth and last of the queue K3, K4, K5, K6, K7
(roadmap decision 7), after rank 2g; section 9 says which premises the earlier runs may change. Depends on:
- the polar toy in the integration shape on SIMPLE's memo layout (validated: yes, runs `mlxf_toy_seam` and
  `mlxf_toy_layout`, `unit_kernels` 1,953 checks at `ae7d623`, seam ledger without a `pending` line);
- K1's fused tail, kept (validated: yes, `completed/mlxf_kernel_k1_report.md`; one thread per pair; the same
  reduction a SIMD group per pair measured 3.28 times faster by run `mlxf_kernel_forms`, decision 27);
- the measured kernel forms of run `mlxf_kernel_forms` (`completed/mlxf_kernel_forms_report.md`, "What the K
  plans take"): suites `tail` (decisions 16 and 27), `select` (decisions 14 and 15) and `probe` (decision 25);
- rank 2g's result (read in Phase 0: it changes `src/core/`, among it the empty `maxval` and `minval`, and may
  add assertions to unit areas);
- `mlxf_oracle_polar_objfun` (validated: standalone, 25 self-checks at `TOL_ROUTE` 1e-12,
  `completed/mlxf_oracles2_report.md`; no tester compares a kernel with it yet, which that report leaves to
  K4, K5 and K7);
- `maxloc`, `minloc`, `merge`, `max`, `min`, `mlx_take_along_dim`, `mlx_put_along_dim`, `mlx_argpartition`,
  `mlx_partition`, `mlx_topk`, `mlx_argsort`, `mlx_irfft`, `mlx_async_eval`, `type(mlx_metal_kernel)`
  (validated: public in `src/core/mlxf.f90`; `unit_ops` 2,462, `unit_fast` 152 at `ae7d623`);
- roadmap decisions 7, 8, 9, 11, 12, 15, 16 and 17, the toy-example policy (section 8 above all), the families
  note (sections 3 and 8) and the mlx3D note (pattern P4, proposed decision 3, now marked measured in part).

## 1. Why

SIMPLE's classic 3D strategies (`refine=greedy`, `shc`, `neigh`) do not use the posterior table that K1 to K4
serve. Each particle scores every reference through `polarft_calc%gen_objfun_vals`, takes the best in-plane
rotation of each (`maxloc`), and reduces across references: the best pair (`extract_peak_ori`), the best k
(`maxnloc` in `extract_peak_oris` and `inpl_srch_peaks`), or the first improvement in a random order
(`srch_shc`). Under `objfun=cc` that score is the memoised correlation of `gen_corrs`, which no toy kernel
computes: the toy calculator has the Euclidean objective only, and SIMPLE's own block kernel refuses cc
(`score_block_posterior` in `simple_polarft_block.f90`: "requires objfun=euclid"). So the cc path and the
classic reductions are the part of polar matching that has no GPU form and no block form on the CPU either.
K7 delivers both objectives as an in-plane-best table per block, and the three reductions per particle, on
the device, judged against `mlxf_oracle_polar_objfun`. Exit as accepted (families note, section 8): "both
objectives and each reduction match the oracle". What SIMPLE's classic strategies cost today per pair: no
record in hand; the dense posterior score is 1.76e7 pairs/s on the GPU against 3.75e6 on 30 threads
(*measured*, families note, section 3), which is another kernel and is quoted for scale only.

## 2. Contract

- **Where the code lives:** `src/test/` only (rank 2d's tree): `mlxf_toy_<stem>` modules in
  `src/test/toys/polar/` under SIMPLE's type and procedure names, against the public module `mlxf` as a user
  writes. Every new Fortran file opens with its `!@descr:` line and `doc/code_base_map.md` is regenerated in
  the phase that adds or removes one (the static gate checks it). No file under `src/core/` or `src/defs/` changes;
  no SIMPLE name enters them. A missing or refusing wrapper is a stop with a report.
- **What it mirrors** (read at `28c753993`; no SIMPLE source is copied):
  - `src/main/pftc/simple_polarft_corr.f90`: `gen_objfun_vals` (the objective switch on
    `params%cc_objfun`), `gen_corrs`, `gen_euclids`; since `23eb95cc2` the unshifted per-pair sums are
    `term_sums` (one dot product per bin of the reference terms and the particle terms), and `cc_sums`, which
    lost its `l_conj` argument, sums only the cross term against a reference shifted on the fly;
  - `src/main/pftc/simple_polarft_memo.f90`: `memoize_sqsum_ptcl` (the particle powers), `memoize_ptcls`
    (which makes the particle terms `ft_ptcl_terms` for cc and `ft_ptcl_wterms` for the Euclidean objective),
    `memoize_one_ref`, `memoize_refs` (`memoize_ref_bins` was removed by `23eb95cc2`; the toy retired its own
    in rank 2e);
  - `src/main/strategies/search/simple_strategy3D_srch.f90`, type `strategy3D_srch`: `new`, `prep4srch`,
    `store_solution`, `kill`;
  - `simple_strategy3D_greedy.f90`, type `strategy3D_greedy`, and `simple_strategy3D_shc.f90`, type
    `strategy3D_shc`: `new`, `srch`, `oris_assign`, `kill`;
  - `simple_strategy3D_utils.f90`: `extract_peak_ori`, `extract_peak_oris`;
  - `src/utils/math/simple_srch_sort_loc.f90` `maxnloc` and `src/utils/math/simple_math.f90` `put_last`,
    as rules the miniatures follow (they are private helpers of the toy, not mirrored names).
- **The integration owner in SIMPLE,** for the SIMPLE plan that may follow: the particle loop of
  `refine3D_exec` in `simple_strategy3D_matcher.f90` and its contained `choose_and_run_strategy`, which runs
  one strategy object per particle inside `!$omp parallel do ... schedule(dynamic)`. An MLX backend there
  scores a block of particles before the loop and lets each particle's strategy read its column.
- **What is judged:** the device and the host route against `mlxf_oracle_polar_objfun` in double precision,
  which shares no code with the toy (the toy imports no oracle module); the reductions' logic exactly;
  repeatability on one GPU configuration and tile shape as its own gate; times never pass or fail a gate.
- **Off-state invariant:** with `cc_objfun = OBJFUN_EUCLID` and no reduction requested, every existing polar
  path is byte for byte what it was: the identity invocations of the base that touch the polar toy (the
  digests on both devices and both tails, the shift maps; Phase 0 lists them and their bytes) are equal at
  every phase exit, but for decision 27's outcome if it is kept: then the dense digests move once, within
  K1's frozen bounds, and the new lines are recorded in Phase 5 and reproduced from then on. With tests excluded (`--exclude-tests`) none of this code is compiled and the library
  and its installed module are unchanged. In a build without MLX the new host files compile without the
  library and the new classes run their host route (`scripts/check_toy_offstate.sh --exec`).
- **Not part of it:** shifts (K4), reference subsets (K3), the shift search after a reduction, the 2D
  strategies, any change to SIMPLE.

### What the check found (2026-11-26, re-read at `ae7d623` and `28c753993`)

Each line names the file and procedure read; findings 2, 3, 6, 8, 13 and 14 are revised for ranks 2e and 2f. **differs** marks a premise of the families note or the mlx3D
note that the code contradicts.

1. **The toy calculator has one objective.** `mlxf_toy_polarft_calc.f90`, type `polarft_calc`: no objective
   member; the `parameters` record of `mlxf_test_defs.f90` has no `cc_objfun`, `npeaks` or `npeaks_inpl`.
2. **Cross and reference power are never separate on the device today.** `polarft_workspace_new`
   (`mlxf_toy_polarft_workspace_lifecycle.f90`), called by `memoize_refs` since rank 2e, packs on the host,
   per reference tile, the conjugated memo `conjg(ft_ref_terms)` of `2nk` rows (the memo holds conj(FT(REF2))
   on rows 1..nk and FT(REF) on rows nk+1..2nk, so the tile's rows are FT(REF2) and conj(FT(REF)), what the
   draft read as `ft_ref2` and `conjg(ft_ref)`) into a real tile (4nk, 2rt);
   `finish_tiles` makes it resident. `polarft_workspace_submit` (`mlxf_toy_polarft_workspace_score.f90`)
   uploads the calculator's particle terms `ft_ptcl_wterms` (rows 1..nk `w_k FT(CTF2)`, rows nk+1..2nk
   `-2 w_k FT(X.CTF)`, made on the host by `memoize_ptcls`), so one product gives `refpow - 2 cross` and one
   `mlx_irfft` gives the row. The correlation needs the two rows apart, hence two products and two inverse
   transforms per pair, as `gen_corrs` has: at `28c753993` its unshifted path is two `term_sums`, over rows
   1..nk and rows nk+1..2nk of `ft_ref_terms` against the same rows of the unweighted `ft_ptcl_terms`.
3. **The tail is one thread per pair.** `tail_spec` (`mlxf_toy_polarft_workspace_tail.f90`): grid
   `[rt*bt, 1, 1]`, threadgroup `[min(POLARFT_TAIL_TG, rt*bt), 1, 1]` with `POLARFT_TAIL_TG` 64, inputs `raw,
   iw, temps, u, par`, outputs `dists` (float32) and `irots` (int32) of shape (rt, bt); pair `e` reads
   `raw[e*nrots + i]` and its particle is `e / rt`. It holds no `threadgroup` memory, no barrier, no atomic.
   It reduces over rotations only (the minimum and the posterior draw); nothing reduces across references.
   Run `mlxf_kernel_forms` built the same reduction a SIMD group per pair (T1: lanes stride over the
   rotations, `simd_min` and the least rotation among the minimal lanes) and measured it 3.28 / 3.28 times
   faster, first minima exact, draws within K1's bound (suite `tail`, *measured*); `tail_spec` is public since
   that run, with its interface in `mlxf_toy_polarft_workspace.f90`.
4. **The fused tail takes transformed rows.** The products and `mlx_irfft` stay library operations in
   `polarft_workspace_submit`; the kernel is the finish and the in-plane reduction. A fused cc finish is the
   same shape with two row inputs.
5. **The device block is dense and ordered.** `score_block_posterior_mlx`
   (`mlxf_toy_polarft_block_mlx.f90`) refuses unless `irefs` is 1..nrefs in order; `polarft_workspace_collect`
   copies (rpad, bpad) entries, 8 B per padded pair, and slices to (nr, nb).
6. **SIMPLE's classic strategies reduce the memoised correlation.** `gen_objfun_vals` calls `gen_corrs` for
   `OBJFUN_CC`: no shell weight, normalised by `sqsums_ptcls(i)` (the raw particle power of
   `memoize_sqsum_ptcl`), single precision, no guard on a non-positive power (re-read at `28c753993`: the
   sums are now `term_sums` over `ft_ref_terms` and `ft_ptcl_terms`, the normalisation unchanged). The k-weighted double-precision
   form (`gen_corr_cc_for_rot_8_noshift`, `_shifted`, normalised by `ksqsums_ptcls`) is called per rotation by
   the shift optimisers after the reduction, not by a strategy's loop over references.
7. **`gen_euclids` returns a score, not a distance:** `exp(-loss)`, a negative loss recomputed directly in
   double and clamped at 0. The classic strategies therefore take the first maximum of a score for both
   objectives; the existing tail takes the minimum of a distance and draws.
8. **The toy's particle memo differs from SIMPLE's in what it stores, and its powers suffice.** `set_ptcl_pft`
   (`mlxf_toy_polarft_memo.f90`) stores `kshell_sqsums_ptcls(k, i)` unweighted per shell; SIMPLE's
   `memoize_sqsum_ptcl` stores k times it. Both particle powers (the sum, and the sum weighted by k) follow
   from the toy's member on the host in double; no new power memo is needed. The particle terms are another
   matter: the toy has `ft_ptcl_wterms` (rank 2e) and not SIMPLE's cc terms `ft_ptcl_terms` (`FT(CTF2)`,
   `FT(X.CTF)`, unweighted), which rank 2e left to this plan (decision 28).
9. **Tie rules in SIMPLE.** In-plane: `maxloc(inpl_corrs)`, the first maximum (`srch_greedy`, `srch_shc`).
   Across references: `store_solution` keeps the larger score (an equal one does not replace);
   `extract_peak_ori` takes `maxloc` of `s3D%proj_space_corrs(:, ithr)`, the lowest reference index among
   equals, and clamps a negative cc to 0 in the reported score. Best k: `maxnloc` inserts a later element
   only before a kept one it strictly exceeds, so at the boundary and among later elements the lower index
   stays and comes first; the order among equals within its first n elements is `hpsort`'s, which was not
   read. The oracles' plan (`mlxf_oracles2.md`, section 9.1.5) says SIMPLE's order among equal scores "is
   not defined"; for the boundary it is defined, as above.
10. **SIMPLE's K.** `NPEAKS_DEFAULT = 3` and `NPEAKS_INPL_DEFAULT = 10` (`src/defs/simple_defs.f90`),
    members `npeaks` and `npeaks_inpl` of the parameters. `srch_greedy_sub` reduces to `npeaks`, then
    `inpl_srch_peaks` to `min(npeaks_inpl, nsolns)`. **differs:** the mlx3D note's P4 states K ≤ 8; SIMPLE's
    larger default is 10.
11. **The hill climb's order is not keyed in SIMPLE.** `prep4srch` draws `srch_order(:, ithr)` from the
    thread's `ran_tabu` generator (`ne_ran_iarr`) and moves the previous reference last (`put_last`);
    `refine3D_exec` runs particles under `schedule(dynamic)`, so the order a particle meets depends on the
    thread and the schedule. **differs:** the families note's "first improvement in a keyed random order"
    is a property the toy introduces (decision 11), not SIMPLE's.
12. **The hill climb's rule.** `srch_shc`: the first reference in the order whose in-plane best is strictly
    above `prev_corr = max(0, the previous reference's in-plane best at zero shift)`; `nrefs_eval` counts the
    references evaluated; with no improvement the best of all is taken by `maxloc` (lowest index), as
    `oracle_polar_shc` has it. The 2D `srch_snhc` differs (a random improving rotation by `shcloc`, a fallback
    in visiting order, `prev_corr` at the previous rotation): the oracle does not cover it.
13. **`mlx_argpartition` cannot carry the tie rule by itself.** Its wrapper (`mlxf_ops_sort.f90`) leaves the
    order inside the two parts undefined, and with it the choice among equals at the boundary; the policy
    (section 10) says MLX documents no stability for `mlx_argsort`. `maxloc(a, dim)` is promised to choose the
    first equal extremum on both devices. **differs:** the mlx3D note's proposed decision 3 names
    `mlx_argpartition` as the graph form; alone it does not reproduce "ties to the lower index". Run
    `mlxf_kernel_forms` measured it at this plan's shape (K best of 10,000 by 1,024, suite `select`,
    *measured*): with the repair it is exact and 2.6 to 6.4 times slower than K rounds of `maxloc` (E1 3.15
    ms against E0 0.49 ms at K = 3 and 1.21 ms at K = 10); without the repair it also passed, because MLX
    0.32.4 kept the lower index at every planted boundary tie, an order MLX does not document (Apple question
    36), so the repair stays the correct form.
14. **A per-particle reduction inside the pair kernel needs `threadgroup` memory.** With one thread per pair
    and the pair order `e = particle * rt + reference`, a threadgroup of `rt` consecutive threads is one
    particle's references of the tile (rt 250 at the canonical plan, under the limit of 1,024, *measured*,
    policy section 12). Reducing inside the launch then needs a `threadgroup` array and a
    `threadgroup_barrier`. Run `mlxf_kernel_forms` measured the feature through the wrapper (suite `probe`,
    Apple question 26): exact group sums for 32 to 1,024 threads with the barriers, wrong from 256 threads up
    without them, a fixed tree bit-repeatable over processes, arrays up to 32,768 B (a group's 250 scores and
    rotations need 2,000 B). The draft treated it as unproven; it is proven on this machine, and no toy kernel
    uses it yet.
15. **The oracle's reach.** `oracle_polar_pair` takes one reference and one particle as rank-2
    `complex(real64)` arrays (`pair_new`) and gives `dist`, `cc` (unweighted) and `cc_weighted` (w_k = k) per
    rotation by direct sums; its ring route exists for the Euclidean loss only (`dists_by_rings`). Its
    reductions (`oracle_polar_greedy`, `_best_k`, `_shc`, `_best_score`) are not defined on NaN scores, and its
    correlation is NaN when a power is not positive, where SIMPLE has no guard (the oracles' report, Q42).
    Whether `pair_new`'s arrays are the calculator's sections in the toy's layout was not verified here
    (Phase 0, item 4).
16. **Numbers that bound the gains** (K1's Progress, *measured* at `2500_4`, one process, Euclidean draw):
    the pass 1.133 s with the compiled tail and 0.628 s with the fused one; copy-out and the host part 0.026
    to 0.028 s of a pass; in the barriered profile the products 0.55 s and the transform 0.42 s of 1.94 to
    2.00 s. A reduction on the device can save at most the copy-out and host part: 0.028 / 0.628 = 4.5 % of
    the fused pass (*derived*). Rank 2e made the dense passes 4 to 10 % shorter (*measured*, its report), so
    Phase 0 measures the pass again. The selection itself is small beside it: K rounds of `maxloc` over 10,000
    by 1,024 take 0.49 ms (K = 3) and 1.21 ms (K = 10), a SIMD group per particle 0.24 and 0.30 ms (*measured*,
    suite `select`).

## 3. Decisions and rulings

Numbers are never reused. "(ruling asked)" marks a real choice put to the maintainer with a recommendation;
the others are defaults taken without a question, open to the review.

**The objective**

1. **The selector is SIMPLE's.** The `parameters` record gains `cc_objfun` (default `OBJFUN_EUCLID`), and
   `mlxf_test_defs.f90` the constants `OBJFUN_CC = 0` and `OBJFUN_EUCLID = 1` (*exact*,
   `simple_type_defs.f90`). A calculator has one objective from `new` to `kill`, as a SIMPLE run has.
2. **The mirrored entry is `gen_objfun_vals(iref, iptcl, shift, vals)`** with SIMPLE's four dummies, a host
   procedure of the calculator in a new host submodule `mlxf_toy_polarft_corr`. It is the miniature of
   `gen_corrs` and `gen_euclids` in single precision over the host memos, safe to call from a team (it
   writes the caller's `vals` and the calling thread's work only). A shift above SIMPLE's `SHERRSQ` is
   refused ("zero shift only"): shifted rows are K4's.
3. **(ruling asked) Which correlation the kernel reproduces: the memoised one.** The table and the three
   reductions use `gen_corrs`'s form: `w_k = 1`, normalised by the raw particle power, judged against
   `oracle_polar_pair%cc`. Reason: it is the only correlation a classic strategy reduces (finding 6). The
   k-weighted direct form is one pair at one rotation in double precision inside the shift search, which this
   plan does not model; it stays the oracle's (`cc_weighted`) until a kernel has a consumer for it. The
   alternative, both, costs one more weight vector on the same contraction and a second tolerance, with no
   driver that would read it.
4. **A non-positive power gives an invalid entry.** Where the particle power or a rotation's reference power
   is not positive, the oracle returns NaN and SIMPLE divides without a guard. The toy's score for such a
   rotation is NaN on both routes; the in-plane reduction skips NaN rotations; a pair with no finite rotation
   is an invalid entry (`POLAR_SCORE_INVALID`, a negative sentinel below every score, with rotation 0), and
   no reduction selects it. A particle with no valid reference returns reference 0. The fixture plants one
   particle of zero power. What SIMPLE should do there is the oracles' Q42, reserved.
5. **The Euclidean score is SIMPLE's:** `exp(-max(0, d))` with `d` the toy's distance, the kernel's `exp`
   being `metal::precise::exp` (within one unit, *measured*, K1). The toy does not recompute a negative
   distance in double as `gen_euclids` does; it clamps at 0, as `oracle_polar_score` does. Where SIMPLE's
   recomputed loss is positive the two scores differ by that loss, which is a rounding residue of the
   single-precision row; the difference is declared, not modelled.
6. **The cc tiles are their own resident layout** (revised 2026-11-26 for rank 2e's memo). Under `OBJFUN_CC`,
   `memoize_refs` makes, per parity, two real tiles of (2nk, 2rt) per reference tile in place of the
   Euclidean (4nk, 2rt), packed on the host straight from `ft_ref_terms` as rank 2e packs the Euclidean ones
   (its decision 6's measured fallback): the packed rows 1..nk of the conjugated memo (FT(REF2)) and the
   packed rows nk+1..2nk (conj(FT(REF))). Bytes are the Euclidean layout's (*derived*: the same elements in
   two arrays; 7.14e9 B for both parities at `2500_4`, *measured*, families note, before rank 2e's 10 % cut of
   the resident size; Phase 0 measures it). The Euclidean
   layout and its arithmetic are not touched: a reordering of its rows would change the order of a sum and
   with it the base's digests. Rejected in advance: one stacked product with the particle terms doubled and
   zero-filled (no new layout, twice the product's multiply-adds, where the products were 0.55 s of a
   barriered 1.94 s, *measured*, K1).
7. **The table of a block** is, per pair, the in-plane best score (float32) and its rotation (int32, the
   first maximum, 1-based), shape (nrefs, nb), for either objective. Padded references and particles carry
   `POLAR_SCORE_INVALID`. This is the per-pair stage; the reductions of decisions 12 to 15 follow it.

**Ties and what "match" means**

8. **(ruling asked) The tie rules on the device are SIMPLE's where SIMPLE defines them, and the oracle's
   where it does not.** In-plane: the first maximum over rotations. Best pair: the lowest global reference
   index among equal scores. Best k: descending score, the lower index first among equals, zeros beyond the
   number of valid references (`oracle_polar_best_k`); this is `maxnloc`'s rule at the boundary and the
   oracle's choice inside the first n elements, where SIMPLE's order is `hpsort`'s. Hill climb: strictly
   above `prev_corr`; with no improvement the best of all by lowest index, `nevals = nrefs`. Recommended as
   written: every rule is a strict comparison in ascending index, which a host loop, `maxloc` and a kernel
   loop all give without a sort.
9. **(ruling asked) "Match the oracle" is three gates.**
   - **L, the logic, exact.** The oracle's reduction applied to the route's own score table (float32,
     promoted) equals the route's result: references, their order, rotations and `nevals`, no tolerance. It
     runs on the fixture's tables and on handmade tables with exact ties, NaN entries, K above the number of
     references and all-invalid columns.
   - **S, the scores, within a frozen tolerance.** Every finite entry of the table against `cc` or
     `oracle_polar_score(dist)`; NaN and invalid entries agree in kind. The rotation agrees exactly unless
     the oracle's scores at the two rotations differ by at most twice the tolerance.
   - **D, the decision against the oracle's own, exact except at near-ties.** A mismatch is admitted only
     when the oracle's scores explain it within twice the frozen tolerance: for the best pair and the best
     k, the two references exchanged have oracle scores within that distance; for the hill climb, some
     reference visited no later than the later of the two picks has an oracle score within that distance of
     `prev_corr`. Admitted mismatches are counted; the count is measured on seed 1 and frozen as a bound
     (the form of `POLARFT_TAIL_ROT_FIX` and `POLARFT_TAIL_ROT_BLK`), and any other mismatch fails.
   Recommended: yes. Reason: float32 scores cannot promise the double oracle's choice between two candidates
   closer than their own error, and gate L keeps the tie rule itself exact. The alternative, D exact with no
   exception, would fail on honest rounding or force a fixture without close scores, which tests less.

**The drivers**

10. **(ruling asked) The toy gains two strategies, `strategy3D_greedy` and `strategy3D_shc`,** each holding
    SIMPLE's search object `strategy3D_srch` as its component `s`, with `extract_peak_ori` and
    `extract_peak_oris` in `mlxf_toy_strategy3D_utils`. Greedy carries the best pair and, through
    `extract_peak_oris(s, npeaks)`, the best k; the hill climb carries the first improvement. Reason: they
    are the two loops SIMPLE's `refine=greedy` and `refine=shc` run per particle, and `refine=shc` itself
    uses the greedy one for a particle not yet searched. Not taken: `strategy3D_greedy_sub` (its
    neighbourhood is K3's subject) and the 2D strategies (finding 12).
    - **Host branch** (`l_mlx = .false.`): SIMPLE's shape. The particles of a range run under
      `!$omp parallel do` with `schedule(dynamic)`, one strategy object per thread made before the region,
      each calling `gen_objfun_vals` per reference in its order and `store_solution`; no allocation and no
      `class` dispatch inside the region (the strategy is selected before it, one loop per strategy).
    - **MLX branch:** one thread cuts the range into blocks of one half, as `fill_tab_range` does, submits
      each block with its reduction to the calculator (one or two in flight), collects the reduced results,
      and hands each particle's result to its strategy object, which then runs `oris_assign` as on the host.
    - **The batch owner is an addition:** type `strategy3D_batch` in `mlxf_toy_strategy3D_matcher`, the
      miniature of the particle loop of `refine3D_exec`. It is not mirrored, because `refine3D_exec` takes
      the builder, the command line and the iteration's controls, none of which the toy models; the ledger
      says so. The dummies of the mirrored `new` and `srch` are SIMPLE's (`params, spec, build` and `os,
      ithr`), the calculator standing for the builder as in `eul_prob_tab%new_pipeline`, a behaviourless
      record of `mlxf_test_defs.f90` for `spec` and for the orientations `os`.
    - Every new class has a host route; none holds device state. All device state stays in
      `polarft_workspace` behind the calculator's `ws(:)`.
11. **(ruling asked) The hill climb's order is keyed.** A particle's order is its references by ascending
    `keyed_variate(seed, iptcl, ref_full(r))` (the lower index first if two variates are equal), then the
    previous reference moved last by `put_last`'s exchange. Reason: the order must be the same on both
    backends and for every thread count, which SIMPLE's per-thread stream is not (finding 11); the toy's
    dense draw is keyed the same way. Consequence for SIMPLE, reserved: an MLX backend of `srch_shc` needs a
    keyed order there too, which changes its random stream. Each particle's previous reference comes from the
    fixture (`set_prev_refs`, an addition).
12. **(ruling asked) The hill climb is decided on the device.** The block is evaluated in full; the decision
    is a commutative reduction over the table: with `rank(r, b)` the place of reference r in particle b's
    order, the pick is the reference of smallest rank among those strictly above `prev_corr(b)`, `nevals` that
    rank, and the greedy pick with `nevals = nrefs` when none is. `prev_corr(b)` is `max(0, table(prev_ref(b),
    b))`, read on the device. What crosses: in, the ranks as int32, 4 B per padded pair (81.9e6 B per pass
    of `2500_4`, *derived*: 20.48e6 padded pairs, the bytes the variates `u` cross with today), and one
    previous reference per particle; out, one reference, rotation, score and `nevals` per particle, 16 B.
    Recommended over deciding on the host from the copied table (8 B per padded pair out, 163.8e6 B per
    pass, *derived*, K1): the three reductions then share one seam (a few entries per particle), which is
    what an integration into `refine3D_exec` needs, and the host loop stays the host branch, held to the same
    oracle. The time at stake is small either way (finding 16), so the choice is made on the seam, not on
    speed. The copied table stays available as a test option (`set_block_options`, rows kept).
13. **K is SIMPLE's:** 3 (`npeaks`) and 10 (`npeaks_inpl`), *exact*; the `parameters` record gains both
    members with those defaults. K = 1 is run as a consistency check (it equals the best pair). The fast
    fixture also runs K above the number of valid references.

**The forms**

14. **(ruling asked, with 15) The graph forms, kept always.**
    - *The pair stage:* two products over the cc tiles, two `mlx_irfft`, then per tile a compiled function:
      `cross / sqrt(refpow * ptclpow)`, NaN where a power is not positive, `maxloc` over rotations after NaN
      rotations are set below every score, `mlx_take_along_dim` for the score. For the Euclidean objective,
      the existing product and transform, then `exp(-max(0, d))` and the same reduction.
    - *Best pair:* `maxloc(table, dim=1)` and `mlx_take_along_dim`.
    - *Best k:* K rounds of `maxloc`, each followed by setting the chosen entry to the invalid sentinel by
      position (an integer comparison with the references' index ramp, or `mlx_put_along_dim`), never by
      value. The tie rule is then `maxloc`'s promise (policy, section 10), exact on both devices.
    - *Hill climb:* `merge` of the ranks with a large integer where the score is not above `prev_corr`,
      `minloc` and `minval` over references, and the best pair's result where no rank survives.
    `mlx_argpartition` is not the reference form (finding 13). The draft's measurement of it in Phase 3, as
    an alternative for K = 10 built into the toy only if the K rounds cost more than 10 % of the pass, is
    withdrawn, 2026-11-26: run `mlxf_kernel_forms` measured it with its repair at this plan's shape, exact and
    2.6 to 6.4 times slower than the K rounds (suite `select`, *measured*), and the K rounds cost 1.21 ms at K
    = 10 against a pass of about 0.6 s (finding 16). The K rounds of `maxloc` are the graph form, as that run
    found them the better graph form; `mlx_argpartition` enters neither the toy nor the bench.
15. **(ruling asked; revised 2026-11-26 by run `mlxf_kernel_forms`) The mlx3D note's proposal 3, as built
    against the tail.** Recommended: yes to its substance (the reductions run on the device, K best in
    registers by insertion with strict comparison, ties to the lower global reference index), no to its place
    (inside the pair kernel) as the first form, and a SIMD group per particle as the first fused form.
    - *First fused form of the reduction (F2), a SIMD group per particle (E3):* a second kernel object applied
      in the same graph to the block's concatenated table (rpad, bpad): each particle's column is read by one
      SIMD group, each of its 32 lanes keeping K entries in registers over a strided part of the column in
      ascending global index, then a merge over the lanes with ties to the lower global index. Launch: grid
      `[32 bpad, 1, 1]`, threadgroup 256 (8 particles), K a template integer (a constant of the run), the
      hill climb's variant reading the ranks. At `2500_4` it is 1,024 SIMD groups of 10,000 entries per half
      (*derived*). *Measured* at this shape (suite `select`, exact on seeds 1 to 3, two invocations): 2.10 /
      2.02 times faster than K rounds of `maxloc` at K = 3 and 4.06 / 4.12 at K = 10, and 3.5 to 4.0 times
      faster than one thread per particle (E2, the draft's F2, which is not built).
    - *Inside the pair launch (F3):* threadgroup `[rt, 1, 1]`, a `threadgroup` array of the group's scores
      and rotations, a barrier, one thread of the group reducing to K, and a merge of the tiles' K lists in
      tile order. It needs finding 14's feature (measured, Apple question 26), `rt` at most 1,024, and a grid
      that is a multiple of `rt`. It is built only if F2 has passed decision 17 and its own ceiling admits it;
      its group reduction is then checked in its gates (exact against a host loop, bit-repeatable over 20
      evaluations), not by a probe of its own; otherwise it is recorded as not built, with the ceilings.
    - *Fallback, named in advance:* the graph forms of decision 14, which are kept in every case.
16. **The fused pair stage (F1) is written a SIMD group per pair** (revised 2026-11-26 by run
    `mlxf_kernel_forms`). K1's kernel shape with other source pieces, in the shape that run measured fastest
    (T1): each pair is one SIMD group whose 32 lanes stride over the rotations, each lane forming the score
    (`metal::precise` functions; for cc from two row inputs and the particle's power) and keeping its first
    maximum, then `simd_max` and the least rotation among the maximal lanes give the pair's first maximum;
    outputs the score and the rotation, shape (rt, bt); grid `[32 rt bt, 1, 1]`, threadgroup 64 (T1's, K1's
    measured indifference). No `threadgroup` memory. *Why* (*measured*, suite `tail`, on K1's own reduction
    over 364 rotations per pair): 3.28 / 3.28 times faster than one thread per pair, 5 of 5 pairs, first minima
    exact, and 1.84 / 1.80 from go to the last exit at six processes. It is a different computation from
    K1's draw, so it is judged on its own; one thread per pair (`tail_spec`'s shape) is not built for F1.
17. **The keep rule, per fused form** (roadmap decision 15; K1's decision 18 is the model). The driver is
    `strategy3D_batch` on the MLX backend at the canonical tile plan (bt 64, rt 250), elapsed time of a pass
    with submission, synchronisation and collection, at equal work and with gates L, S and D passing.
    - A **ceiling** is measured first for each form: the same driver with the stage replaced by a null one
      (the pair stage writing a constant; the reduction returning the first K references). A form whose
      ceiling is below 1.30 is not built, and Progress records the ceiling as its verdict.
    - The **configurations** (objective, reduction, K, tile plan, team, passes) are frozen in Progress before
      the verdict runs.
    - A form is **kept** if the median of five interleaved pair ratios (graph time over fused time) is at
      least 1.30 with at least four of five at or above it, at one process and at 6 processes of `2500_1`,
      and at 3 processes of `2500_4` read on the time from go to the last exit; a median between 1.25 and
      1.35 adds five pairs. Both invocations of each pair are run. A row is valid by K1's ruling R1 (the
      parts' exit spread at most the median of their median passes).
    - F1 is judged for cc with the best pair (the canonical configuration) and reported for the Euclidean
      objective; F2 is judged for best k at K = 10 against the graph reduction, F1's verdict applied to both
      sides. Expected from finding 16 and suite `select`: F2's ceiling is below 1.30 (*derived*: the K rounds
      it replaces cost 1.21 ms a half at K = 10, about 0.4 % of a fused pass), so it is not built, and the
      report records E3 as the form a later consumer would build first.
18. **The bench** is a new suite of `mlxf_bench_polar_table.f90`: `suite=classic` with the keys `cases case
    cases_list bt rt device nthr nparts part go passes tail objfun reduce npeaks form` (`objfun=cc|euclid`,
    `reduce=greedy|peaks|shc`, `form=graph|metal|null` for the reduction, `tail=graph|metal|null` for the pair
    stage). A key the suite does not read stops the program, as today. Its rows go to the benchmark's table
    with the rate, the work, the MLX peak and cache and the median pass in the columns `scripts/run_parts.sh`
    reads (20, 21, 26, 27, 30), and a digest line of the reduced results. Sizes: `2500_4` and `2500_1` of the
    case file, seed `POLAR_SEED_JUDGED`. It is timed alone and as 3 and 6 simultaneous processes with
    `RUN_PARTS_SUITE=classic scripts/run_parts.sh` under its memory guard, a one-minute load of at most 4
    (`RUN_PARTS_LOAD=4`) and `uptime` recorded. Reported: the total rate, the rate per process, one
    process's footprint and MLX peak. Per-part memory is reported and never a reason to reject a faster form
    (the maintainer, 2026-11-25; roadmap decision 15).

**Accuracy, fixtures, repeatability**

19. **Tolerances.** Scores are absolute errors (both scores lie in [-1, 1]). Each is the largest error on
    seed 1 over both devices, both builds and every form, times `POLAR_ROW_FACTOR` (2), frozen in
    `mlxf_test_defs.f90` (`POLAR_CC_TOL`, `POLAR_SCORE_TOL`, and the near-tie bounds `POLAR_PEAK_NEAR`,
    `POLAR_SHC_NEAR`) and in Progress before seeds 2 and 3 are run. Ceilings: 1e-5 for each score
    (*guessed*; K1's rows were within 2.4e-7 of a row's largest distance, *measured*); a near-tie bound of at
    most 1 % of the decisions of the fixture (*guessed*). A measured value above its ceiling is a stop.
20. **The small fixture** is new and leaves `make_polarft_host_fixture` and its lines untouched:
    `make_strategy3D_fixture(seed)` in `mlxf_polarft_host_fixture.f90`, at the host fixture's sizes (pftsz
    16, kfrom 2, 6 shells, 40 references, 44 particles: 1,760 pairs), with two identical references (an exact
    tie across references if the device gives them equal bits, which Phase 2 measures and reports), one
    particle of zero power, each particle's previous reference, and for a quarter of the particles a previous
    reference that no other beats (the fallback). The oracle's side builds one `oracle_polar_pair` per pair
    (1,760 objects of 32 rotations: 5.4e6 terms in double, *derived*, negligible).
21. **Repeatability is its own gate:** on the GPU at the canonical tile plan, two invocations of the same
    executable give the same bits for the table and for every reduced result (references, rotations, scores,
    `nevals`), for each objective, each reduction and each kept form, on the small fixture (`bits_equal`)
    and at bench size (the digest lines of two `run_parts` rows). A form that is not repeatable is not kept.
    MLX issue #4603 (wrong rows from a custom kernel under the default math mode on another machine) is
    watched by gates S and L on the GPU at every phase from 2 on.
22. **The seam.** Host files (import no MLX name): `mlxf_toy_polarft_corr`, `mlxf_toy_strategy3D_srch`,
    `_utils`, `_greedy`, `_shc`, `_matcher`. Glue: the existing `mlxf_toy_polarft_block_mlx` gains the
    objective and the reduction of a block (stubs under `#else` with "built without MLX"). Device: a new
    submodule `mlxf_toy_polarft_workspace_reduce` (the graph and fused reductions) and new source pieces in
    `mlxf_toy_polarft_workspace_tail`. Both ledgers get their lines in the phase that adds the file. The
    cycles (new, kill, new again with the other objective; a block submitted and killed in flight) and the
    refusals (a reduction without ranks or previous references; K below 1; cc on tiles made for the Euclidean
    objective; a shifted `gen_objfun_vals`; the fused forms off the GPU) go to sub-suite `seam`. The
    off-state program runs both strategies on the host route for seeds 1 to 3, writes their lines for
    `scripts/check_toy_offstate.sh` to compare with `mlxf_test_exec`'s, checks a team of four against one
    thread byte for byte, and asks `strategy3D_batch` for the MLX backend, which must refuse with "built
    without MLX".
23. **The fast gate.** The new sub-suites `polarft_objfun` (gate S and the table) and `strategy3D` (gates L
    and D, the drivers, both backends) join `unit_kernels` on both devices; no CTest entry is added (13
    stay). They add at most 2.0 s to the area in Release (*guessed*; the fast gate is 10.44 to 10.51 s of a
    bound of 38.74 s, *measured*, run `mlxf_kernel_forms`); an entry above 0.5 s says why in the policy's
    table.
24. **File rows may be added** for a submodule when a toy module or tester passes 700 lines, named
    `src/test/toys/polar/mlxf_toy_<module>_<part>.f90`, each recorded in the file table by the phase that adds
    it, with the map regenerated. No other file
    outside the table.
25. **The probes** run in the run's scratch directory against the installed `mlxf`, not in the tree, their
    numbers in Progress. Probes (a) and (b), `threadgroup` memory with a barrier and `simd_sum`: withdrawn,
    2026-11-26, as probes of their own: run `mlxf_kernel_forms` measured both through the wrapper (suite
    `probe`, Apple question 26), and F3, if admitted, checks its own group reduction in its gates (decision
    15). Probe (c) stays: whether two identical references in one tile and in two tiles give equal score
    bits. A finding that contradicts suite `probe` becomes an amendment of question 26.
26. **A finding about MLX or mlx-c** (a `maxloc` that does not take the first maximum on a device; the cost
    of `mlx_argpartition` and `threadgroup` memory are measured, questions 36 and 26) is written as a numbered
    entry of `doc/collaboration/apple_questions.md` after the last one Phase 0 finds (37 and following at
    `ae7d623`), never sent.
27. **(ruling asked; added 2026-11-26 from run `mlxf_kernel_forms`) Whether K1's draw tail moves to a SIMD group
    per pair.** That run measured K1's fused tail as kept (T0, one thread per pair) against the same draw a
    SIMD group per pair (T1): 3.28 / 3.28 times faster, 5 of 5 pairs, first minima exact, draws within K1's
    frozen `POLARFT_TAIL_ROT_BLK` (5 differing rotations per 64,000 pairs), 1.84 / 1.80 times from go to the
    last exit at six processes (*measured*, suite `tail`); and K1's tail ceiling on rank 2e's base reaches 1.32
    by K1's method and 1.45 by the profile's share (*derived*), so a driver change could pass the 30 % rule.
    It changed no toy default and left the choice to the K plans; the maintainer has not ruled.
    - **Recommended: yes, in this run, as a verdict of its own.** F1 is written in T1's shape (decision 16), so
      T1 for the draw is the same pattern with K1's finish, and this run already edits
      `mlxf_toy_polarft_workspace_tail.f90`. T1 replaces T0 as `tail=metal` (one fused form, no second path)
      only if the dense canonical driver (`suite=time case=2500_4 bt=64 rt=250`, K1's protocol) is at least
      1.30 times faster with it, by decision 17's rules at one process, three of `2500_4` and six of
      `2500_1`, with the gates of `polarft_tail` and `eul_prob_tab` at K1's frozen tolerances and the
      first-minimum gate run on rows with ties across lanes (run `mlxf_kernel_forms` found that a gate without
      them let an inverted first-index rule pass). If kept, T0 is deleted, the dense digests move once (draws
      within K1's bound), and Phase 5 records the new lines as the identity from then on; K3's list route, if
      kept, inherits the form.
    - **Alternatives:** (a) leave K1's tail as it is and record the measured gain for a later plan: costs
      nothing now and leaves the gain on the tail of every dense fill; (b) a small plan of its own before K3,
      so the dense digests move before the batch rather than at its end: one more run on the M5.
28. **The particle terms of cc are SIMPLE's `ft_ptcl_terms`** (added 2026-11-26 for rank 2e's layout). Under
    `OBJFUN_CC`, `memoize_ptcls` makes `ft_ptcl_terms (2nk, pftsz+1, nptcls)` under SIMPLE's name and layout
    (rows 1..nk `FT(CTF2)`, rows nk+1..2nk `FT(X.CTF)`, unweighted), and the device's cc pair stage uploads
    them as the Euclidean one uploads `ft_ptcl_wterms`. Under `OBJFUN_EUCLID` the toy does not make them, a
    declared difference: SIMPLE makes both so that the objective may change on a live calculator, while a toy
    calculator has one objective from `new` to `kill` (decision 1); the Euclidean path's memory and bytes stay
    the base's. Size: the same as `ft_ptcl_wterms`, 0.36e9 B at `2500_4` (*derived* in rank 2e's report).

**Defaults taken without a question:** decisions 1, 2, 4 to 7, 13, 16, 18 to 26 and 28. **Rulings asked:** 3,
8, 9, 10, 11, 12, 14 with 15, 17's canonical configuration, and 27.

## 4. Not in this plan

- Shifted scores, the shift search after a reduction (`inpl_srch`, `inpl_srch_peaks`, `inpl_srch_first`,
  `l_sh_first`), and the k-weighted direct correlation they use.
- Reference subsets and neighbourhoods (`strategy3D_greedy_sub`, `eul_prob_tab_neigh`): K3's.
- The 2D strategies (`strategy2D_greedy`, `strategy2D_snhc`), `shcloc`, the mixture of `refine=shc`
  (`GREEDY_FREQ`), states, symmetry, the orientation objects beyond (reference, rotation, score, the
  evaluated fraction).
- A cc form of the posterior draw or of the shift maps (SIMPLE refuses both under cc).
- Any measurement of SIMPLE, any SIMPLE source change, any wrapper, any file under `src/core/` or
  `src/defs/`, a CTest entry, the accelerated mode (TF32), production data (`~/data`, `~/data2`).
- A change of `scripts/run_parts.sh`, of the Euclidean tiles, of the projector and reconstructor toys, or of
  K1's kept tail beyond decision 27's verdict.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement; no tree change but Progress | the base's counts and identity bytes; section 9's re-checks; the oracle's reach; the bench's baseline rows |
| 1 | new test-only code: the host route and the strategies | gates L, S, D on the host route, seeds 2 and 3 at tolerances frozen on seed 1; a team against one thread; ten planted violations fail; rules `mirror`, `seam`; the off-state program |
| 2 | new test-only code: the cc tiles and particle terms, the graph pair stage, the graph reductions, the MLX branch | gates L, S, D and decision 21 on both devices; the two backends' decisions equal under gate D's rule; ten planted violations fail; sub-suite `seam` |
| 3 | measurement; the bench's suite | decision 25's probe (c); decision 17's ceilings; decision 27's ceiling on the dense driver; configurations frozen |
| 4 | new test-only code under the 30 % rule, per form, or not entered | every gate of Phase 2 on the GPU with the fused form; decision 27's form under `polarft_tail` and `eul_prob_tab`; six planted violations fail, each where its form is built |
| 5 | measurement; possibly result-changing for the dense tail (decision 27) | decision 17's verdicts; decision 27's verdict and, if kept, the dense digests recorded anew; decision 18's table complete; decision 21 at bench size |
| 6 | documents; the last gates | the report; the release gates below; `git status` shows file-table paths only |

Every phase ends with Debug and Release built from scratch in the run's own hand-configured trees
(`-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`) with no warning, the fast gate 13 of 13 in both,
`scripts/check_tree.sh` passing, and `scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` run on
every Fortran file touched, by explicit file name (the static gate includes rank 2d's rules `publist` and
`size`, the folders' `.inf` descriptions and the code-base map). The existing areas keep the counts Phase 0
finds, Debug and Release alike (at `ae7d623`, *measured*: core 214 to 216, array 193, ops 2,462, fft 194,
linalg 632, compile 63, fast 152, random 486, transforms 274, io 846, distributed 55; rank 2g and K3 to K6 may
have changed them); `unit_kernels` is the base's count (1,953 at `ae7d623`, re-read in Phase 0) plus the new
sub-suites' counts, each existing sub-suite keeping its own (`polarft_tail` may grow by decision 27). Phase 6 adds
`scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`,
`scripts/release_gate.sh --allow-dirty`, and the Release fast gate 10 times of 10. Nothing else is built
while a step is timed.

## 6. Acceptance

**Inexact gates** (frozen by decision 19; seeds 2 and 3 judge, seed 1 calibrates):

| Gate | Error measure | Ceiling |
| --- | --- | --- |
| S, cc | largest absolute error of a finite table entry, each route and device | 1e-5 (*guessed*) |
| S, Euclidean score | the same against `oracle_polar_score` | 1e-5 (*guessed*) |
| S, rotation | mismatches not explained by twice the tolerance | 0 (*exact*) |
| D, best pair and best k | admitted near-tie exchanges of the fixture | `POLAR_PEAK_NEAR`, at most 1 % of the decisions (*guessed*) |
| D, hill climb | admitted near-threshold decisions | `POLAR_SHC_NEAR`, at most 1 % (*guessed*) |
| the two oracles | `oracle_polar_pair%dist` against the ring oracle's rows on the fixture | 1e-10 relative (*guessed*; both are double) |

**Exact gates:** gate L in every form; the kind of every NaN and invalid entry; a team of four against one
thread on the host route; the off-state lines; decision 21; the counts of section 5; every refusal's message.

**Planted violations,** each shown to fail its named gate in a scratch copy and then removed, the failing
check named in Progress (after an edit the run waits 1.2 s before `make`, K1's whole-second trap):
- Phase 1: the correlation normalised by the k-weighted power (S, cc); the in-plane choice as the last
  maximum (L, handmade rows); the hill climb's `>` as `>=` (L: `nevals` on the duplicate fixture); its
  fallback in visiting order (L); `put_last` left out (L); best k with the higher index first among equals
  (L); the invalid entry selectable (L, the zero-power particle); a variate keyed by the place in the block
  (the team gate); a ledger line removed (rule `mirror`); `use mlxf` in a host file (rule `seam`).
- Phase 2: the cross and reference-power tiles exchanged (S); the conjugate dropped from the cross tile (the
  memo's rows nk+1..2nk packed as they are, S); the particle's cc terms taken from `ft_ptcl_wterms` (S);
  a padded reference scored 0 (L: chosen where every cc is negative); the tile's local index returned for a
  reference (L); the ranks of a padded particle read (L); a chosen entry masked by value (L, duplicate
  scores); `prev_corr` without the clamp at 0 (L, a negative previous score); a term that depends on a call
  counter (decision 21); a refusal's branch removed (`seam`).
- Phase 4: the kernel's insertion with `>=` (L); plain `exp` for `precise::exp` (S, if above the frozen
  tolerance; otherwise reported as not detectable and the piece kept `precise`); the kernel scanning from the
  last reference (L); F1's least rotation among the maximal lanes inverted, on handmade rows whose ties fall
  in different lanes (L); for F3, the barrier removed (L or decision 21); for decision 27, T1 skipping the
  last rotation (the first-minimum gate of `polarft_tail`).
- Phase 5: an unread key (`error stop 2`); a part's digest altered (decision 21 at bench size).

**Hypotheses, reported with their numbers:**
- H1: the graph reductions cost under 5 % of a pass at the canonical plan (*guessed*).
- H2: F1 gains at least 30 % for cc (K1's draw tail gained 1.65 to 1.80, *measured*, and its reduction a SIMD
  group per pair was 3.3 times faster still, suite `tail`).
- H3: F2's ceiling is below 1.30 (*derived* from finding 16 and suite `select`'s 1.21 ms) and F2 is not built.
- H6: decision 27's T1 reaches 1.30 on the dense canonical driver (*derived*: K1's tail ceiling 1.32 to 1.45
  and T1 3.3 times faster than T0).
- H4: a cc pass costs at most 1.6 times the Euclidean one in the graph form (*guessed*: one more transform,
  0.42 s of a barriered 1.94 s, *measured*, K1, and the same product work).
- H5: identical references give identical score bits whatever their tile (*guessed*).

**Reported, not gated:** every time, rate and byte count; one process's footprint and MLX peak; probe (c);
the share of near-ties; the differences from SIMPLE; decision 27's rows whatever its verdict.
**Reserved for the maintainer:** whether a keyed order is acceptable in SIMPLE's `srch_shc` (decision 11);
decision 27's ruling before the go;
Q42 (the non-positive power) and Q8, Q10 of the oracles' report; the order among equals inside `maxnloc`'s
first n; whether the miniatures read like SIMPLE.

## 7. Common rules and stop conditions

- No file outside the table apart from decision 24's rows. No tolerance, ceiling, bound, seed or fixture
  changed to pass. A failing gate is a diagnosis task.
- No key, option or member beyond those named here in the toy; alternatives live in the benchmark.
- The oracle modules import no `mlxf` and no toy module; the toy imports no oracle; host files import no MLX
  name; the device modules import no host or glue module.
- An executable run directly on the GPU runs with `MLX_ENABLE_TF32=0`. Timed runs are Release, on a
  one-minute load of at most 4, with `uptime` in Progress. SIMPLE is not measured.
- Git is read-only: nothing is committed or pushed. The notes are written with the editor tools.
- A decision with a recommendation is taken and recorded in Progress, never asked, unless it is a stop.

**Stops** (a report of what was measured, the options and a recommendation; the phases that do not depend on
the stop go on):
- a public operation of the list in the header is missing or refuses a call the graph forms need;
- `maxloc(a, dim)` does not choose the first maximum on a device on the handmade ties;
- a measured tolerance or near-tie count is above its ceiling;
- gate L fails on an admitted seed and two attempts at a diagnosis do not find a defect of the toy;
- a graph form is not repeatable, with the operation that differs named;
- the oracle cannot be fed the calculator's sections (Phase 0, item 4) without a change of an oracle module
  beyond making a procedure public;
- an identity invocation of the base changes its bytes;
- section 9's re-check finds that an earlier run changed a premise in a way its decision here does not
  cover (the shape of the table, the tail's inputs, the block's reference set);
- a change to `src/core/`, `src/defs/`, `scripts/run_parts.sh` or SIMPLE would be needed; SIMPLE at
  `28c753993` contradicts a decision; the static gate fails on something the run did not touch;
- an identity digest of the base differs from `ae7d623`'s and neither rank 2g's report nor an earlier run's
  report names the change (section 9).

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
oracle shares no code with the toy; no SIMPLE source copied; tolerances and bounds frozen before the seeds
they judge; gate L exact; repeatability of every kept form; the 30 % rule for a fused form; the off-state
build.

## 8. Phases

### Phase 0, the base, the queue's re-checks and the oracle's reach (box: 90 min)

1. Pin the base's hash. Build Debug and Release from scratch; record every area's count, each sub-suite's
   count of `unit_kernels`, the fast gate's time, and the bytes of the base's identity invocations that
   touch the polar toy (twice each).
2. Section 9's re-checks, item by item, each answered in Progress with the file and procedure read.
3. Read at `28c753993` the dummy lists and the members of `strategy3D_srch` (it gained `view_solve` and
   `refine_extra_pose_continuously`'s `seed_coord` with `c1f255d20`, which the miniatures do not model),
   `strategy3D_greedy`, `strategy3D_shc`, their parent `strategy3D_pftc`, `strategy3D_spec`, `hpsort` as
   `maxnloc` calls it, and `gen_corrs`, `term_sums`, `cc_sums` and `memoize_ptcls`; record what the
   miniatures keep and what they declare as a difference. Read rule `mirror` in `scripts/check_rules.py` for
   what it compares.
4. The oracle's reach: build `oracle_polar_pair` objects from the host fixture's sections, compare its `dist`
   with the ring oracle's rows of sub-suite `polarft_host` (the comparison the oracles' report left to K4 and
   K7), and time 1,760 pairs. If the layouts differ, the bridge is a tester's helper, not an oracle change.
5. The bench's baseline: `suite=time` at `2500_4` and `2500_1`, graph and fused tails, one process, twice,
   for the pass K7's rows are read against and decision 27's verdict is judged on.

**Exit:** the counts and bytes are in Progress; every item of section 9 is answered; the oracle agrees with
the ring oracle within the ceiling; no stop condition holds; the tree is unchanged but for this note.

### Phase 1, the host route: `gen_objfun_vals` and the two strategies (box: 180 min)

1. `mlxf_test_defs.f90`: the constants and members of decisions 1 and 13, the records of decision 10, the
   fixture's record. `mlxf_polarft_host_fixture.f90`: `make_strategy3D_fixture`.
2. `mlxf_toy_polarft_corr.f90`: `gen_objfun_vals` on the host memos (the ring inverse the host block uses),
   both objectives, decision 4's rule.
3. The four strategy modules and the batch owner with its host branch; the helpers that follow `maxnloc` and
   `put_last`; the keyed order of decision 11.
4. Sub-suites `polarft_objfun` and `strategy3D` on the host route: gate S (seed 1 measured, frozen, seeds 2
   and 3 judged), gates L and D, the team gate; the off-state program and its CMake list; both ledgers.
5. The ten planted violations.

**Exit:** the gates of the row pass in Debug and Release; `scripts/check_toy_offstate.sh --exec` passes with
the new lines; the tolerances of the host route are in `mlxf_test_defs.f90` and Progress; the identity bytes
are the base's.

### Phase 2, the device in graph form: the cc tiles, the table, the reductions (box: 240 min)

1. The cc layout at `memoize_refs` (decision 6), `ft_ptcl_terms` at `memoize_ptcls` (decision 28), and their
   refusals; the Euclidean path unchanged.
2. The graph pair stage for both objectives (decision 14), queued per tile with `mlx_async_eval` as the
   dense score is; the table collected as a test option.
3. `mlxf_toy_polarft_workspace_reduce.f90`: the three graph reductions; the block's spec gains the
   objective, the reduction, K, the ranks and the previous references; the glue and the calculator's
   additions (`set_block_reduction`, `collect_block_peaks`, `set_prev_refs`); the batch owner's MLX branch.
4. The tester's device checks on both devices: gate S with the device's tolerances measured on seed 1 over
   both devices and frozen; gate L on the fixture and on handmade tables; gate D; the two backends against
   each other; decision 21; the cycles and refusals in `seam`.
5. The ten planted violations. H5 measured.

**Exit:** the gates of the row pass on both devices in Debug and Release; every tolerance and bound is frozen
in `mlxf_test_defs.f90` and Progress before seeds 2 and 3 ran; the new counts are recorded; the fast gate's
time is within decision 23 or the excess is explained in the policy's table.

### Phase 3, the probe, the bench's suite and the ceilings (box: 130 min)

1. `suite=classic` (decision 18) with the null forms; `RUN_PARTS_SUITE=classic` rows at one process.
2. Decision 25's probe (c).
3. The profile of a pass at the canonical plan for cc and the Euclidean objective: products, transforms,
   pair stage, reduction, collection (barriered, labelled as such), and the unbarriered pass; H1 and H4.
4. The ceilings of F1, F2 and F3 (decision 17), two invocations each; the dense driver's tail ceiling for
   decision 27 (a null tail in a scratch copy, K1's method), two invocations.
5. The verdict configurations frozen in Progress.

**Exit:** each fused form and decision 27's T1 have a ceiling and a line "built" or "not built, by its
ceiling" in Progress; the configurations are frozen; no gate of Phase 2 changed.

### Phase 4, the fused forms, each only if Phase 3 admits it (box: 180 min)

1. F1: the source pieces of the score and the first maximum in `mlxf_toy_polarft_workspace_tail.f90`, a SIMD
   group per pair (decision 16), its spec, its refusal off the GPU; selected by `set_tail_form`, as K1's.
2. F2, if admitted: the per-particle kernel a SIMD group per particle (E3, decision 15) in
   `mlxf_toy_polarft_workspace_reduce.f90`, selected by an addition `set_reduce_form`. F3, if admitted by
   decision 15.
3. Decision 27, if ruled yes and its ceiling admits it: K1's draw a SIMD group per pair in the same file,
   behind `tail=metal` for the verdict's runs only (T0 stays until Phase 5's verdict); the gates of
   `polarft_tail` and `eul_prob_tab` with tied rows across lanes.
4. Every gate of Phase 2 on the GPU with each fused form; decision 21; the six planted violations of the forms built.

**Exit:** each built form passes gates L, S, D and decision 21 on the GPU on seeds 2 and 3 at the frozen
tolerances (a fused form gets no tolerance of its own); the graph forms' results are unchanged; or the phase
is recorded as not entered, with the ceilings.

### Phase 5, the bench and the verdicts (box: 210 min)

1. Decision 17's verdict runs for each built form: five interleaved pairs at one process, at 6 processes of
   `2500_1` and at 3 of `2500_4`, both invocations, each row's validity checked. Decision 27's verdict on the
   dense driver by the same rules; if kept, T0 is deleted, the dense digests and the identity set are
   recorded anew twice and become the base's lines, and the gates of Phase 2 run again.
2. Decision 18's table for the kept configuration and for the graph forms: cc and Euclidean, the three
   reductions, K 3 and 10, alone and as 3 and 6 processes: total rate, rate per process, footprint, MLX peak.
3. Decision 21 at bench size. The two planted violations.
4. A form that fails its verdict is deleted from the tree with its keys, its ledger lines and its tests
   (K1's decision 20), and the gates of Phase 2 are run again.

**Exit:** every built form has a verdict by decision 17's rule, written before the next step; the table is
complete or each missing row has its `run_parts` status; the tree holds only kept forms.

### Phase 6, the record and the last gates (box: 60 min)

1. `planned/mlxf_kernel_families.md`: section 3 (A4 delivered, which correlation, the seam's measured bytes,
   "Differences from SIMPLE"), section 2a's row A, section 8's row K7.
2. `doc/policies/test_environment_policy.md` (the sub-suites, the suite `classic`, any fast entry above 0.5
   s), `doc/policies/toy_example_policy.md` where it lists the toys, the plans' index, the history,
   `src/test/toys/polar/polar.inf` and `doc/code_base_map.md` for what was kept, `test/offstate/offstate.inf`,
   the root `README.md` where it names the kernels; decision 27's outcome in the families note's row K1 and
   the roadmap.
3. The gates of section 5's last sentence, the Release fast gate 10 times of 10.
4. The report `completed/mlxf_kernel_k7_report.md` in the how-to's order: what was learned, the changes per
   phase, decisions under delegation, deviations, evidence, what is left open, and a commit message without
   an attribution or co-author line that names every new file.

**Exit:** the report exists; every gate of section 5 passes; `git status` shows file-table paths only.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/framework/mlxf_test_defs.f90` | `OBJFUN_*`, `cc_objfun`, `npeaks`, `npeaks_inpl`, the records, the block spec's members, tolerances and bounds, `POLAR_SCORE_INVALID` | 1, 2, 4 |
| `src/test/toys/polar/mlxf_polarft_host_fixture.f90` | `make_strategy3D_fixture`, its table and lines | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_calc.f90` | the interfaces of `gen_objfun_vals` and of the additions | 1, 2, 4 |
| `src/test/toys/polar/mlxf_toy_polarft_corr.f90` (new) | host submodule: `gen_objfun_vals` | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_memo.f90`, `mlxf_toy_polarft_memo_mlx.f90` | the cc layout's request at `memoize_refs`; `ft_ptcl_terms` at `memoize_ptcls` (decision 28) | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_block.f90`, `mlxf_toy_polarft_block_mlx.f90` | the block's objective and reduction; refusals; stubs | 2, 4 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace.f90` | the cc tiles, the reduction's interfaces and state | 2, 4 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_lifecycle.f90` | the cc tiles | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_score.f90` | the graph pair stage | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90` | F1's source pieces and spec; decision 27's T1 and, if kept, T0's deletion | 4, 5 |
| `src/test/toys/polar/mlxf_toy_polarft_tail_tester.f90` | decision 27's gates with ties across lanes, if it is built | 4, 5 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_reduce.f90` (new) | device submodule: the graph reductions; F2, F3 | 2, 4 |
| `src/test/toys/polar/mlxf_toy_strategy3D_srch.f90` (new) | host: type `strategy3D_srch` | 1, 2 |
| `src/test/toys/polar/mlxf_toy_strategy3D_utils.f90` (new) | host: `extract_peak_ori`, `extract_peak_oris` | 1 |
| `src/test/toys/polar/mlxf_toy_strategy3D_greedy.f90` (new) | host: type `strategy3D_greedy` | 1, 2 |
| `src/test/toys/polar/mlxf_toy_strategy3D_shc.f90` (new) | host: type `strategy3D_shc` | 1, 2 |
| `src/test/toys/polar/mlxf_toy_strategy3D_matcher.f90` (new) | host: type `strategy3D_batch`, both branches | 1, 2 |
| `src/test/toys/polar/mlxf_toy_polarft_objfun_tester.f90` (new) | sub-suite `polarft_objfun` | 1, 2, 4 |
| `src/test/toys/polar/mlxf_toy_strategy3D_tester.f90` (new) | sub-suite `strategy3D` | 1, 2, 4 |
| `src/test/toys/mlxf_toy_seam_tester.f90` | the new cycles and refusals | 2, 4 |
| `src/test/toys/polar/mlxf_toy_*.f90` (new, decision 24) | submodules past 700 lines | 1, 2, 4 |
| `src/test/bench/mlxf_bench_polar_table.f90` | `suite=classic`, its keys and rows | 3, 4, 5 |
| `src/test/framework/mlxf_test_registry.f90` | two `run_suite` rows | 1 |
| `src/test/toys/polar/polar.inf` | the folder's description: the cc objective, the strategies and their batch owner | 1, 2, 6 |
| `doc/code_base_map.md` | regenerated by `scripts/generate_codeoverview.py` in each phase that adds or removes a Fortran file or edits an `.inf` (the static gate checks it) | 1, 2, 4, 5, 6 |
| `test/offstate/CMakeLists.txt`, `mlxf_offstate_exec.f90`, `offstate.inf` | the new host files and checks | 1, 6 |
| `scripts/check_toy_offstate.sh` | only if its comparison names the lines it reads; else untouched | 1 |
| `scripts/toy_mirror.txt` | the new lines; SIMPLE's strategy files in its header | 1, 2, 4 |
| `scripts/toy_seam.txt` | seven lines (six host, one device) | 1, 2 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | sections 2a, 3 and 8 (rows K1 and K7) | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | K7's row; decision 27's outcome | 6 |
| `doc/policies/test_environment_policy.md`, `doc/policies/toy_example_policy.md` | the suites, the bench, the toys' list | 6 |
| `doc/implementation_notes/README.md` | the index | 6 |
| `README.md` | the status | 6 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 6 |
| `doc/collaboration/apple_questions.md` | if a question arises (decision 26) | 2, 3, 4, 5 |
| `doc/implementation_notes/planned/mlxf_kernel_k7.md` | this note: Progress, decision 24's rows | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/completed/mlxf_kernel_k7_report.md` (new) | the report | 6 |

## 9. The queue

Ranks 2d, 2e and 2f are delivered and committed (`ae7d623`); rank 2g, the user-facing hardening, runs next and
before the batch (roadmap decision 17). K7 runs last of the batch, from the commit that holds K6's verified
result. K5 and K6 bring their own classes and touch only the shared files. K3 and K4 edit the polar toy this
plan builds on. Rank 2g changes `src/core/` and no toy file: integer `mean`, `var` and `std` promoted first,
the Euclidean norms and floating means in a scaled form, empty `maxval` and `minval` given Fortran's
identities (the graph reductions of decision 14 reduce non-empty tables, but a padded or all-invalid column
is gated, and its result is re-checked), integer-scalar operators, saves that keep a file on failure, an index
validator; it may add assertions to unit areas. Phase 0, item 2, re-checks exactly the premises below and
records each answer; a premise changed beyond what its line allows is section 7's stop.

| Premise of this plan | Who may change it | What Phase 0 re-checks, and what follows |
| --- | --- | --- |
| A block is dense: every reference in order (finding 5) | K3 | `score_block_posterior_mlx`'s refusals and the block spec's members. If a block may list or mask references, an absent pair must carry `POLAR_SCORE_INVALID` in the table; decisions 4 and 12 to 15 then hold unchanged. If the table is no longer (rpad, bpad), stop |
| The tiles' layout and residency (finding 2) | K3 (reordered or gathered tiles), K4 (shifted references) | `polarft_workspace_new`, `finish_tiles`. Decision 6 builds its layout beside whatever the Euclidean one is; the global index of a tile's reference must still be known to the reductions |
| The tail: one thread per pair, inputs `raw, iw, temps, u, par`, outputs (rt, bt), pair order `e = particle * rt + reference` (finding 3) | K4 (a shift dimension, other source pieces, another grid) | `tail_source`, `tail_spec` (public since run `mlxf_kernel_forms`), the `tail_inputs` and `tail_outputs` records. F1 and decision 27 are written from the tail as it is then, a SIMD group per pair; K4's per-pair kernels 2 and 4 are written in the same shape, and F1 reuses their pattern if K4 kept them |
| `gen_objfun_vals` refuses a shift (decision 2) | K4 | whether a shifted row exists on either route; if so the refusal stays and the difference is recorded, since no reduction here reads a shift |
| The `parameters` record and `polarft_block_spec` members | K3, K4, K5, K6 | no name of decisions 1, 10 and 13 is taken; the record's constructor calls in the off-state program still compile |
| `SUITE_KEYS`, the table's columns and `canonical_plan` of the bench; `run_parts.sh`'s columns | K3, K4 | the suite's key table and the columns of decision 18; the canonical plan (bt 64, rt 250) |
| The fast gate: 13 entries, 10.44 to 10.51 s of 38.74 s in Release; `unit_kernels` 1,953; the other areas' counts (at `ae7d623`) | rank 2g and all four | the counts and the time; decision 23's 2.0 s is against the time found |
| The base's identity digests (the 364-line set of runs `mlxf_toy_layout` and `mlxf_kernel_forms`, SHA-256 `e2d65e88...4d33dba5` at `ae7d623`, and its successors in each run's report) | rank 2g, all four | recorded twice on the base; a change that neither rank 2g's report nor an earlier run's names is section 7's stop |
| Both ledgers, the registry (`BENCHES` 6, `NAMED_ONLY` 4 at `ae7d623`), `test/offstate/`, the folders' `.inf` files and the code-base map, the families note | all four | the lines present; the off-state program's shape; the last Apple question's number (36 at `ae7d623`) |
| K1's numbers of finding 16 | rank 2e (passes 4 to 10 % shorter), K3, K4 (a changed pass) | Phase 0, item 5, measures the pass again; decision 17's and decision 27's ceilings are measured, never taken from this note |

## Progress

(one entry per phase, written by the run: date, machine, base, `uptime` before each timed step, files
changed, each exit item and how it was met, log paths, the frozen numbers, the planted violations and the
checks they failed, decisions taken under delegation, and what it means, in short)
