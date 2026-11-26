# The polar toys catch up with SIMPLE's memo layout (run `mlxf_toy_layout`, on the M5 Ultra)

Status, 2026-11-26: planned; decisions stand as recommended under the maintainer's go of 2026-11-26, open to his
review. Base: the commit that holds this plan; checked against `b2c43a4` (clean tree). SIMPLE read at
`d354efee2` (what the toys mirror today) and at `28c753993` (its HEAD, 2026-11-26), through `git show`,
`git grep`, `git log` and `git diff` only. Roadmap rank 2e (decision 16). Machine: the M5 Ultra only (30 cores,
103.1 GB, the only GPU and the only machine that builds the library), in a copy of the checkout, one run at a
time. Supersedes: none. Depends on:

- rank 2d's verified result, committed (validated: no, it runs before this plan; "The queue" says what Phase 0
  re-checks);
- the polar toy `polarft_calc` with its driver `eul_prob_tab`, its host kernel, K1's fused tail and K2's device
  route (validated: yes, runs `mlxf_kernel_k1`, `mlxf_kernel_k2`, `mlxf_toy_seam`; `unit_kernels` 1,955);
- the identity cases of the seam run's decision 13 and K3's decision 20 (validated: yes, equal byte for byte
  over the six phases of `mlxf_toy_seam`);
- `scripts/run_parts.sh` and `bench_polar_table suite=time` (validated: yes, K1 and the seam run).

## 1. Why

SIMPLE's `23eb95cc2` (2026-11-25, "pftc: one memo layout for the references, read by every kernel") replaced the
three reference memos `ft_ref`, `ft_ref2` and `ft_ref_bins` by one, `ft_ref_terms (2nk, pftsz+1, nrefs, 2)`,
because the bin-major copy cost 6.6 GiB per part at 20,000 directions and ten parts reached a 332.8 G Slurm
ceiling (*from the commit message*). The toys mirror the layout of `d354efee2`. The maintainer ruled (decision
16) that the toys catch up "so that we are testing and benchmarking on the same layout", before the review
against mlx3D (2f) and before the drafts of K3 to K7 are revised. The run moves the toys' memos, their dummy
lists and their device uploads to SIMPLE's layout, proves that no output of the toys moves where its arithmetic
did not, and measures the dense baselines again on the new layout.

## 2. Contract

- **What changes:** the polar toy's host memos and their names (`ft_ref_terms`, `ft_ptcl_wterms`), the procedures
  that SIMPLE removed or reshaped (`memoize_ref_bins` removed; the seed banks of `score_block_posterior` shaped
  `(2nk, pftsz+1, nb)`), the workspace's inputs (one memo per parity, the particle terms), the call sites in the
  driver, the fixtures, the testers and the two benches, the mirror ledger's lines and pin.
- **What does not move (the identity invariant):** every output the toys compute. The memo values are the same
  numbers in another order; the host kernel sums the same 2nk products of each bin in the same order; the device
  tiles are made by exact operations (conjugation, negation, real and imaginary parts, permutation); the map's
  arithmetic is unchanged. The decided identity cases (decision 13) equal the base byte for byte after every
  phase.
- **The off-state invariant:** the host files build and run without the library (`test/offstate/`), and the
  host backend's table (`polarft_host` lines) equals the base's byte for byte. No line of an MLX glue body runs
  in that build.
- **Toy code only,** under SIMPLE's names, in `src/test/`. No file under `src/core/` or `src/defs/` changes; a
  missing wrapper is a stop with a report. The oracles stay independent double precision and import nothing of
  the toy.
- **Builds:** hand-configured trees with `-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`, Debug and Release.

### What the check found (2026-11-26, on `b2c43a4`, SIMPLE `d354efee2` and `28c753993`)

SIMPLE, between the two pins (34 commits; the toys' files read one by one):

| SIMPLE file (mirrored by) | Commits that touch it | Class |
| --- | --- | --- |
| `pftc/simple_polarft_calc.f90` (calculator type, bindings) | `23eb95cc2`, `0b41e99b9` | layout: members `ft_ref_terms`, `ft_ptcl_terms`, `ft_ptcl_wterms` replace `ft_ref`, `ft_ref2`, `ft_ref_bins`, `ref_gen`, `ref_gen_bins`; binding `memoize_ref_bins` removed; interface `term_sums` added. Style elsewhere |
| `pftc/simple_polarft_memo.f90` (`_memo`) | `23eb95cc2`, `0b41e99b9` | layout and behaviour: `memoize_one_ref` writes the terms; new private `memoize_ptcl_terms`, called by `memoize_ptcls` and, when the particle memo is current, by `memoize_sigma2_weights`; `memoize_shifted_ptcl` returns `(2nk, pftsz+1)` terms, weighted under euclid; `memoize_ref_bins` removed |
| `pftc/simple_polarft_block.f90` (`_block`) | `23eb95cc2`, `0b41e99b9` | layout: a full consecutive tile read in place (leading dimension `2nk (pftsz+1)`), other tiles gathered bin by bin; particle terms copied, not recomputed; "entries unchanged bit for bit" |
| `pftc/simple_polarft_corr.f90` (none) | `23eb95cc2`, `0b41e99b9` | behaviour: per-pair kernels on `term_sums`; `euclid_sums` removed; `cc_sums` loses `l_conj`; at most 6e-7 relative (*from the commit message*) |
| `pftc/simple_polarft_shiftmap.f90` (`_shiftmap`, device maps) | `23eb95cc2`, `0b41e99b9` | behaviour: reference power from the terms (euclid: `term_sums`; cc: a loop), spectra from rows nk+1..2nk |
| `pftc/simple_polarft_core.f90` (`_core`) | `23eb95cc2`, `0b41e99b9` | naming: the two counters leave `kill` |
| `pftc/simple_polar_shiftmap.f90`, `_access`, `_ctf`, `_geom`, `_ops_io` | `0b41e99b9` | style only (`git diff -w` empty) |
| `probabilistic/simple_eul_prob_tab.f90` (`mlxf_toy_eul_prob_tab`) | `23eb95cc2`, `0b41e99b9` | naming: `new_pipeline` loses `block_memo`; the seed banks' shape |
| `probabilistic/simple_eul_prob_tab_neigh.f90` (none yet; K3) | `23eb95cc2`, `c1f255d20`, `0b41e99b9` | layout (`block_memo` gone, banks), behaviour (`prob_neigh_mode=geom`, 179 lines), style (two members reordered) |
| `probabilistic/simple_eul_prob_tab_utils.f90` (none) | `c1f255d20`, `e6629a57d`, `0b41e99b9` | behaviour outside the toys: `nearest_cone_views` added; a bound of `merge_view_basins` fixed |
| `commanders/test/simple_polar_matching_bench.f90` (`mlxf_bench_polar_table`, by purpose) | `23eb95cc2`, `0b41e99b9` | behaviour of SIMPLE's bench: its own FT(X.CTF), no `memoize_ref_bins`, banks reshaped |
| `commanders/test/simple_test_polar_fixture.f90` | `0b41e99b9` | style only |
| `image/simple_projector.f90`, `_pft_batch`, `simple_image_fft.f90` | `0b41e99b9` | style only |
| `image/simple_image.f90` | `43876fe97`, `0b41e99b9` | behaviour outside the mirrored procedures (FSC's keyed phase randomisation); style |
| `volume/simple_reconstructor_pcg.f90` | `0b41e99b9`, `c1f255d20` | style; one local pointer of `solve_accum` gains `contiguous` (no dummy changes) |
| `volume/simple_pcg_lattice.f90`, `opt/simple_pcg_solver.f90` | `0b41e99b9` | style only |
| `utils/math/simple_linalg.f90` (none) | `23eb95cc2` | `cdotc_sub` added |

`0754e25cc` touches `simple_volpft_symsrch*` only; no toy mirrors them. Between `23eb95cc2` and `28c753993` the
mirrored files differ only in `simple_image.f90` (8 lines, FSC). Every mirrored name of `scripts/toy_mirror.txt`
exists at `28c753993` except `polarft_calc%memoize_ref_bins` (checked with `git show` on the bindings of
`simple_polarft_calc` and `simple_eul_prob_tab`).

The layout, as the code states it: `memoize_one_ref` writes, per reference, parity and bin p, rows 1..nk the r2c
transform of the squared modulus (the conjugate of SIMPLE's FT(REF2), whose memo was its conjugate) and rows
nk+1..2nk the transform of the ring; `memoize_refs` writes a mirror's column as the conjugate of its source's,
and a half turn negates the odd bins of rows nk+1..2nk only. The message's statement holds.

The toys, at `b2c43a4`:

- **The toy's memos are SIMPLE's of `d354efee2`.** `mlxf_toy_polarft_calc.f90`, type `polarft_calc`:
  `ft_ref`, `ft_ref2` `(pftsz+1, kfromto, nrefs, 2)`, `ft_ptcl_ctf`, `ft_ctf2`, and on the host backend
  `ft_ref_bins (2nk, nrefs, pftsz+1, 2)`, made by `host_ref_bins` (`_memo`). `flush_refs` writes `ft_ref` from a
  direct DFT in double precision rounded once, and `ft_ref2` as the conjugate of the same for `|z|^2`.
- **The host kernel sums in the order SIMPLE's layout keeps.** `_block`, `score_block_posterior`: per bin j, pair
  (b, ir), `acc` over kk = 1..2nk of `conjg(pterms(kk, b, j)) * ft_ref_bins(kk, iref, j, ieo)`; the particle
  terms are `wk * ft_ctf2` and `(-2 wk) * ft_ptcl_ctf` (or the bank). Read from `ft_ref_terms(kk, j, iref, ieo)`
  the operands and their order are the same.
- **differs** (premise as first stated: "the workspace already packs rows 1..nk and nk+1..2nk per bin"): the packing is in
  `mlxf_toy_polarft_workspace_lifecycle.f90`, `polarft_workspace_new`, and its rows are `ft_ref2` and
  `conjg(ft_ref)`: the conjugate of SIMPLE's terms. A tile is `(2nk, rt, pftsz+1, ntiles)`, references within a
  bin, packed as the real block `[[Re G, Im G], [-Im G, Re G]]` `(4nk, 2rt, pftsz+1, ntiles)`. The upload is
  therefore not a plain copy of `ft_ref_terms`: a conjugation, a transpose of bins and references, padding and
  the real packing remain, on the host (today) or on the device (decision 6).
- **The device route packs on the device already.** `new_from_memos` builds the same tiles from the device memos
  `memo_ref`, `memo_ref2` `(pftsz+1, nk, nrefs)` that `memoize_sections` makes: two codes for one packing.
- **differs** (premise as first stated: "the per-pair kernels sum one dot product per bin"): the toys have no per-pair kernel. The
  result-changing part of `23eb95cc2` has no counterpart here; SIMPLE's block kernel, the one the toy mirrors,
  kept its bits.
- **The maps read the old memos on the host and compute on the device.** `_shiftmap_mlx`, `new_shiftmap_mlx`,
  hands `ft_ref(:, :, :, ieo)` and `ft_ref2(:, :, :, ieo)` to `polarft_workspace_prepare_maps`
  (`_workspace_shiftmap`), which builds `rfull (nkb, nrots, nrefs)` from `ft_ref` and uploads
  `ref2b = ft_ref2(:, 1:nkb, :)`; `tile_maps` forms the reference power as `sum(c2 * r2 * wband, 2)` on the
  device. SIMPLE's new euclid power multiplies the weighted CTF term by the reference term, another order.
- **The device weights the particle terms.** `_workspace_score`, `polarft_workspace_submit`: uploads `ft_ctf2`
  and `ft_ptcl_ctf` (or the bank) of the block and forms `c2 * w3` and `xc * (w3 * (-2))` on the device from
  `polarft_block_spec%weights`.
- **differs** (premise as first stated: "shifted-particle banks are shaped (2nk, pftsz+1)"): the toy has no
  `memoize_shifted_ptcl`. Its banks are fixture inputs `(pftsz+1, nk, nb)`, unweighted
  (`score_block_posterior`, `set_block_banks`), made by `mlxf_toy_polarft_calc_tester.f90` from the oracle's
  `polar_dft_bins`; only that tester passes banks.
- **differs** (premise as first stated: "the block-memo arguments removed"): the toy's `new_pipeline` never had `block_memo`; it
  calls `memoize_ref_bins` itself when `ref_bins_current` is false. The toy's `memoize_ref_bins` also makes the
  device tiles on the MLX backend, a role SIMPLE's never had; `set_tile_plan`, `set_tail_form` and
  `set_ref_route` invalidate it through `ref_gen_bins`.
- **The retired names, counted** (`rg -c -w` over `ft_ref`, `ft_ref2`, `ft_ref_bins`, `memoize_ref_bins`,
  `memoize_ref_bins_mlx`, `kill_ref_bins`, `ref_bins_current`, `ref_gen_bins`, `host_ref_bins`, `memo_ref`,
  `memo_ref2`; *exact*): 166 occurrences in 23 files. Ten of them name the oracle's own input type
  `polar_table_refs` and stay (decision 12): `mlxf_oracle_polar.f90` 3, `mlxf_test_defs.f90` 3,
  `mlxf_bench_polar_table.f90` 4 (of its 11).
- **The bench's preparation.** `mlxf_bench_polar_table.f90`, `prepare`: `set_tail_form`, `set_tile_plan`,
  `memoize_ref_bins`, outside the timed passes; `kill_ref_bins` six times between configurations.
  `mlxf_bench_projector.f90` calls `memoize_ref_bins` once.
- **Sizes at `2500_4`** (*derived* from the families note's geometry: 10,000 references per half, 2,000
  particles, pftsz 182, 61 shells, tile plan 64 by 250): the reference memo is 3.57e9 B for both parities in
  either layout; the host staging of `polarft_workspace_new` is 1.79e9 B (complex tiles) plus 3.57e9 B (packed)
  per parity; the particle memo is 0.36e9 B and grows by 0.36e9 B with `ft_ptcl_wterms`.
- **The "before" in the record:** one process at `2500_4`, bt 64, rt 250: 1.77e7 pairs/s with the compiled tail
  (pass 1.133 s) and 3.18e7 with the fused tail (0.628 s) (*measured*, K1's report); the seam run's base,
  1.763595e7 summed median pairs/s through `run_parts.sh` with one process (*measured*, its decision 14); three
  graph processes from go to the last exit 13.46 to 13.59 s (*measured*, K1's Phase 0). SIMPLE's block kernel on
  an M2 Ultra went from 4.7 / 4.9 / 5.1 to 4.3 / 4.6 / 5.0 thread-microseconds per pair at 1 / 8 / 16 threads
  (*from the commit message*); the families note's 3.75e6 pairs/s for 30 threads predates it and is not
  restated (no SIMPLE measurement).

### The queue

- **2d runs first** and moves the test tree. This plan uses the layout 2d is to deliver:
  `src/test/framework/` (`mlxf_test_defs`, `_utils`, `_reduce`, `_registry`, the ABI probe),
  `src/test/oracles/` (every `mlxf_oracle_*`), `src/test/toys/` (`mlxf_toy_device_work`,
  `mlxf_toy_seam_tester`), `src/test/toys/polar/` (every `mlxf_toy_polarft_*`, `mlxf_toy_eul_prob_tab*`,
  `mlxf_polarft_host_fixture`), `src/test/toys/projector/`, `src/test/toys/recon/`, `src/test/bench/`. Module
  names do not change. 2d also splits `mlxf_array` and `mlxf_ops` without changing a public name of `mlxf`, adds
  `!@descr:` to every `.inf` and lifts the code-base map of SIMPLE and XEMA. Phase 0 re-checks: every path of
  the file table exists; the module of each row is in it; the retired names are counted as above (166 in 23
  files); whether the static gate checks a generated code-base map, and how it is regenerated.
- **2f runs after,** from the commit holding this run's verified result, and reviews the kernels against mlx3D.
  It reads the toys in the new layout.
- **K3 to K7** wait behind 2f; this run does not edit their drafts and lists in its report what they cite of
  the old layout (Phase 5).

## 3. Decisions and rulings

1. (2026-11-26, recommended) **The pin is SIMPLE's `28c753993`.** For the mirrored files it reads as
   `23eb95cc2` except `simple_image.f90`'s FSC lines, which no toy mirrors; a later pin is SIMPLE's current
   state. The commits that matter are those of the table above: `23eb95cc2` (layout), `0b41e99b9` (style),
   `c1f255d20` and `e6629a57d` (behaviour the toys do not model), `43876fe97` (outside the mirrored procedures);
   `0754e25cc` touches nothing mirrored.
2. (recommended) **One reference memo, SIMPLE's.** `ft_ref_terms (2nk, pftsz+1, nrefs, 2)` replaces `ft_ref`,
   `ft_ref2` and `ft_ref_bins`. `flush_refs` writes rows 1..nk as the rounded DFT of `|z|^2` (no conjugation)
   and rows nk+1..2nk as the rounded DFT of the ring: the same rounded numbers as today's memos (conjugation
   commutes with rounding; *exact*). Mirrors are not modelled (the toy's `memoize_refs` has no `eulspace`, a
   declared difference that stands).
3. (recommended) **The host kernel reads the memo in place.** `score_block_posterior` sums over kk = 1..2nk of
   `conjg(pterms(kk, b, j)) * ft_ref_terms(kk, j, iref, ieo)`; `host_ref_bins` and `ft_ref_bins` are deleted.
   The order of the products is unchanged, so the host entries and the `polarft_host` lines do not move
   (*exact*, by construction; checked by decision 13).
4. (recommended) **`memoize_ref_bins` is retired, and `memoize_refs` makes the device tiles.** SIMPLE removed
   the procedure and its kernels read the one memo; the device's tiles are the toy's copy of it. On the MLX
   backend `memoize_refs` ends by making both parities' tiles under the tile plan and tail set before it; with
   nothing pending it makes them again from the host memo (the bench's change of tile plan or tail: `kill_ref_*`,
   setters, `memoize_refs`). On the device route a second tiling after the memos were released is refused, as
   today. `new_pipeline` makes nothing: it refuses a calculator whose tiles are not current, with the
   calculator's reason, as SIMPLE's block kernel refuses unmemoized references. The ledger line of
   `memoize_ref_bins` goes.
5. (recommended) **The additions named for the bins take the tiles' name:** `kill_ref_bins` becomes
   `kill_ref_tiles`, `ref_bins_current` becomes `ref_tiles_current`, the counter `ref_gen_bins` becomes
   `ref_gen_tiles`; the refusal texts that cite `memoize_ref_bins` cite `memoize_refs`. The bins they were named
   for no longer exist in SIMPLE, and an addition is named for what it does. `ref_gen` stays: the toy's maps and
   tiles check it (SIMPLE dropped its counters; declared). Rejected: keeping the old names (fewer edits, a name
   that points at nothing).
6. (recommended) **The host route's upload becomes a plain copy, and the packing one device function.**
   `polarft_workspace%new` takes one parity's `ft_ref_terms (2nk, pftsz+1, nrefs)` and uploads it with one
   `mlx_from`; a private `pack_tiles` of `_workspace_lifecycle` conjugates, pads to whole tiles, permutes to
   `(2nk, rt, pftsz+1, ntiles)` and packs the real block, for both routes. The host packing loops are deleted.
   The tiles are bit for bit today's (exact operations only). Fallback, fixed now: if at `2500_4` (one process,
   graph tail) the preparation raises the process's maximum resident size by more than 10 % (*guessed*) or makes
   `run_parts.sh`'s guard refuse a split the base ran, the packing stays on the host, written from
   `ft_ref_terms` into the packed array directly (no complex staging), and the device route keeps its own; the
   choice and its numbers go to Progress.
7. (recommended) **The device route's memo is SIMPLE's layout too.** `memoize_sections` makes one device memo
   `memo_terms (2nk, pftsz+1, nrefs)`: rows 1..nk the r2c transform of `|z|^2` (today's `memo_ref2` without its
   conjugation), rows nk+1..2nk the slice of the ring's FFT; `new_from_memos` packs it with `pack_tiles`.
   `memo_ref` and `memo_ref2` go.
8. (recommended) **The particle memo gains `ft_ptcl_wterms (2nk, pftsz+1, nptcls)`,** made at the end of
   `memoize_ptcls` from the finished `ft_ctf2` and `ft_ptcl_ctf` as SIMPLE's `memoize_ptcl_terms` makes it:
   rows 1..nk `sigma2_wk(k, ih) * ft_ctf2`, rows nk+1..2nk `(-2 sigma2_wk(k, ih)) * ft_ptcl_ctf`, in single
   precision, the expressions the host kernel evaluates today. `ft_ptcl_ctf` and `ft_ctf2` stay (the maps read
   them, as SIMPLE's shell loops do). `ft_ptcl_terms` (cc) is not added: the toy is euclid only until K7.
   `set_sigma2_weights` keeps invalidating the particle memo (SIMPLE's `memoize_sigma2_weights` remakes the
   terms; the toy's addition asks for `memoize_ptcls` again; declared).
9. (recommended) **The device scores the host's particle terms.** `polarft_workspace%submit` takes
   `(blk, ft_ptcl_wterms, status)`, gathers the block's columns to `(2nk, pftsz+1, bpad)`, uploads them, and
   permutes a particle tile to `(bt, 2nk, pftsz+1)`; `polarft_block_spec%weights` and the device multiply go.
   Prediction (*derived*): the digests do not move, since a single-precision product of the same two operands is
   one IEEE rounding on the host and on either device (`w3 * (-2)` is exact). If a digest moves: stop with the
   pairs that differ and their operands; the fallback, for a ruling, keeps the device's weighting as a declared
   difference and reads rows 1..nk and nk+1..2nk unweighted.
10. (recommended) **Seed banks are particle terms.** The banks of `score_block_posterior` and
    `set_block_banks` are shaped `(2nk, pftsz+1, nb)`, the terms of the objective with a shifted cross term,
    as SIMPLE's `memoize_shifted_ptcl` returns them. A new addition `polarft_calc%shifted_ptcl_terms(iptcl,
    xctf, bank)` makes them from a fixture's shifted FT(X.CTF) `(pftsz+1, nk)`: rows 1..nk the particle's
    `ft_ptcl_wterms`, rows nk+1..2nk `(-2 sigma2_wk(k, ih)) * xctf` (reason: SIMPLE's `memoize_shifted_ptcl`
    shifts and transforms the particle itself; the toy's fixtures give the transform). The arithmetic is
    today's, so the banked entries do not move. The oracle's `polar_table_block` keeps raw banks.
11. (recommended) **The maps change their inputs, not their arithmetic.** `prepare_maps` takes one parity's
    `ft_ref_terms`; `rfull` is built from rows nk+1..nk+nkb, and `ref2b (pftsz+1, nkb, nrefs)` as the conjugate
    of rows 1..nkb transposed on the host (exact); `tile_maps` keeps `sum(c2 * r2 * wband, 2)`. SIMPLE's order
    (the weighted CTF term first) would move the map identity case in the last bits; the map's device
    arithmetic is K4's to revisit. Rejected for this run.
12. (recommended) **The oracles keep their inputs.** `polar_table_refs` (`ft_ref`, `ft_ref2`) and
    `polar_table_block` (`ctf2`, `xctf`, raw `banks`, `weights`) are the oracle's own double-precision inputs and
    need not follow SIMPLE's layout. What changes is only where a tester hands the toy a bank (decision 10) and
    where a fixture or bench called `memoize_ref_bins` (decision 4). No oracle file is edited unless a comment
    names a retired toy procedure.
13. (recommended) **Nothing is re-pinned; the identity cases are the gate.** Recorded twice in Phase 0 on the
    base, compared once after Phases 1, 2 and 4, never rerun until they pass:
    - the seam run's eleven invocations (its decision 13, named in its Progress, Phase 0): the polar digests of
      `suite=time case=1000_1 bt=64 rt=250 nthr=30 device=gpu` with `tail=graph` and `tail=metal`, of
      `suite=accuracy case=2500_4` on both devices (graph) and on the GPU (`tail=metal`), of `suite=shiftmap
      case=1000_1 maps=window,screen ptiles=16 device=gpu` on the identity grid (written again in Phase 0 from
      that entry); the projector's `suite=time` (`form=fused tile=2500 tg=64` and `form=graph`) and
      `suite=chain` on `route=device` and `route=host`; `bench_recon_pcg suite=time n=160 out=map` for
      `system=P` and `system=R`;
    - K3's decision 20: `suite=time case=2500_4 bt=64 rt=250 passes=3` with both tails;
    - the `polarft_host` lines of `unit_kernels suite=polarft_host` (Release, one thread), and the off-state
      program's table, both against the base's.
    A case that moves is a stop (section 7). It is re-pinned only by a ruling with the oracle's frozen
    tolerances holding on seeds 2 and 3 on both devices; no tolerance is loosened, and this plan adds none.
14. (recommended) **The dense baselines on the new layout.** `bench_polar_table suite=time case=2500_4 rt=250
    passes=9`, bt 16 and 64, `tail=graph` and `tail=metal`, through `scripts/run_parts.sh` at 1, 3 and 6
    processes with 30, 10 and 5 threads (12 settings). Before: Phase 0, each setting twice on the base (the A-A
    difference). After: Phase 4, base and new builds interleaved, two pairs per setting. Judged on the time from
    go to the last exit (roadmap decision 15, K1's lesson); the summed median rate, footprints, MLX peak and
    cache, and the exits' spread are reported. Floor (frozen in Progress at the end of Phase 0): at no setting
    is the new build's median time more than max(2 %, twice the larger A-A difference of that setting) above the
    base's (2 % *guessed*, the seam run's precedent; the A-A difference *measured*). A split the guard does not
    run is recorded `not_run`, not a failure. Per-part memory is reported, never a reason to reject.
15. (recommended) **The ledger's pin moves, and is checked once against SIMPLE.** The header records
    `28c753993`; Phase 3 runs a one-off scan: every mirrored line's SIMPLE module and name found at the pin with
    `git -C ~/src/SIMPLE grep` (a binding in the type's `procedure` lines, a module procedure in the module's
    `public` lines), the result in Progress. The scan is not a gate: SIMPLE is not in the checkout or in CI.
16. (recommended) **The counts move only where an assertion named a retired procedure.** Every assertion that
    called or named `memoize_ref_bins`, `kill_ref_bins` or `ref_bins_current` is re-pointed one for one, so
    `polarft_calc` (327), `polarft_tail` (55), `polar_shiftmap` (794), `eul_prob_tab` (105), `seam` (88) and
    `polarft_host` (65) keep their counts. Two exceptions, stated with their assertions in Progress: the
    projector tester's route stages lose `memoize_ref_bins` (`projector_chain`, 99, falls by the assertions of
    that stage, counted before the edit; *exact*), and `polarft_calc` gains the refusals of
    `shifted_ptcl_terms` (a wrong shape, a particle not in the batch: 2 per backend run, at most 6).
17. (recommended) **The drafts are listed, not edited.** The report names each section of K3 to K7 that cites
    the old layout (Phase 5's list) for the revision after 2f.

### Defaults taken without a question

The names `ft_ref_terms` and `ft_ptcl_wterms` (SIMPLE's); `shifted_ptcl_terms`, `kill_ref_tiles`,
`ref_tiles_current`, `ref_gen_tiles`, `memo_terms`, `pack_tiles`; the refusal texts; the report
`doc/implementation_notes/completed/mlxf_toy_layout_report.md`; the history entry in the month file of the run's
last day; the identity runner and the timing runner rewritten in the run's scratch from the seam run's
descriptions (never committed).

## 4. Not in this plan

- The cc objective and `ft_ptcl_terms` (K7); SIMPLE's per-pair kernels, `term_sums`, `cdotc_sub` (no toy
  counterpart; K7 reads them at the new pin).
- The maps' arithmetic, SIMPLE's order of the reference power (K4); `eul_prob_tab_neigh` and the geometric mode
  of `c1f255d20` (K3).
- A mirrored `memoize_shifted_ptcl`, mirrored references in `memoize_refs`, a live change of weights.
- Renaming the oracle's members; any change of the oracles' arithmetic.
- The projector and reconstruction toys beyond the two call sites of `memoize_ref_bins` (their SIMPLE files
  changed in style only).
- Editing the drafts of K3 to K7, the toy policy or the binding contract; anything under `src/core/`,
  `src/defs/`, SIMPLE, mlx, mlx-c or mlx3D; a measurement of SIMPLE.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement on the base | both builds without a warning; the counts; decision 13's cases twice; decision 14's settings twice; the queue re-checked |
| 1 | identical: the reference memo, the tiles, the maps' inputs | decision 13 byte for byte; the counts (decision 16); the retired-name scan; `seam`; `check_toy_offstate.sh --exec` |
| 2 | identical (predicted, decision 9): the particle terms and the banks | decision 13 byte for byte; the counts; the bank gates of `polarft_calc` on seeds 2 and 3 at the frozen bounds |
| 3 | documentation and ledger | rule `mirror` with the new pin; the one-off scan; the families note's section 3 |
| 4 | measurement | decision 14's floor; decision 13 on the final build |
| 5 | documentation | the report; the last-phase gates; `git status` shows file-table paths only |

Every phase ends with Debug and Release built from scratch with no warning, the fast gate in both (13 entries,
bound 38.74 s; 10.7 s today, *measured*), `scripts/check_tree.sh`, `scripts/restyle_fortran.py` and
`scripts/format_use_blocks.py` (explicit file names) on every Fortran file touched, and the unit areas at their
counts: core 215 or 216, array 193, ops 2,462, fft 194, linalg 632, compile 63, kernels 1,955 (as decision 16
changes it, with the change stated), fast 152, random 486, transforms 274, io 846, distributed 55 (*measured*,
the common record; Phase 0 re-measures on 2d's result and those numbers rule). The last phase adds
`scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`,
`scripts/release_gate.sh --allow-dirty` and the Release fast gate 10 times of 10.

## 6. Acceptance

- **Identity** (*exact*): decision 13's cases equal the base's byte for byte after Phases 1, 2 and 4.
- **Retirement** (*exact*): `rg -w` over the toy files, fixtures, testers and benches finds none of the retired
  names, except the ten oracle-type occurrences of "What the check found"; `memoize_ref_bins` appears nowhere in
  `src/` or `scripts/`.
- **Counts** (*exact*): decision 16.
- **Accuracy:** the existing gates at their frozen bounds (`POLAR_FIXTURE_ERR_CPU`, `POLAR_BLOCK_ERR_CPU`,
  `POLARFT_TAIL_ROW_TOL`, the map caps 1e-4) hold on seeds 2 and 3, both devices; they cannot move if identity
  holds, and are run as the suites run them.
- **Rates:** decision 14's floor, frozen in Progress at the end of Phase 0 before any after-run.
- **Repeatability:** the identity cases were equal twice on the base (Phase 0); the fused tail's repeatability
  assertions in `polarft_tail` and the bench's per-part digests pass.
- **Gates with plants:** the identity comparison shown to fail on a copy with one flipped hexadecimal digit;
  the retired-name scan shown to fail on a scratch file holding `ft_ref_bins`; rule `mirror` shown to fail with
  `memoize_ref_bins` left in the ledger after its removal (Phase 1). Each plant removed and recorded.
- **Reported, not gated:** the per-part footprints, MLX peaks and caches before and after; the preparation's
  maximum resident size and MLX peak at `2500_4` (decision 6); the host backend's memo bytes (the bin-major copy
  gone: 3.57e9 B less at `2500_4`, *derived*); SIMPLE's commit-message timings beside the toy's rates, as
  context only.
- **Hypotheses** (none a criterion): the rates are within the A-A difference, since no arithmetic moved; the
  stage "particle terms" of `suite=profile` shrinks by the device multiply and grows by the host gather (net
  under 1 % of a pass, *guessed*).
- **Reserved for the maintainer:** whether the miniature's memo now reads like SIMPLE's for the integration; the
  list of K3 to K7 sections to revise.

## 7. Common rules and stop conditions

- No file outside the table; a needed one gets its row (with "if needed") and a Progress line before the edit.
- No tolerance, floor or assertion relaxed; no seed changed; no case rerun until it passes.
- A test executable on the GPU runs with `MLX_ENABLE_TF32=0`. MLX is called by one submitting thread, outside
  any OpenMP region; the host loops (memos, terms, the host kernel) may use the team.
- A timed step waits for a one-minute load of at most 4, records `uptime`, and runs with no build or test beside
  it.
- Dead code found is deleted when the compiler proves it dead (Debug's unused warnings, a build without the
  symbol).
- A finding about MLX or mlx-c becomes entry 32 onward of `doc/collaboration/apple_questions.md`, never sent.
- Git is read-only. The report ends with a commit message without attribution or co-author line that names every
  new file.

**Stops:**
- a premise of "The queue" does not hold on 2d's result (a module renamed or split, the retired names counted
  otherwise than 166 in 23 files, a gate 2d added that this plan cannot satisfy);
- the base fails its own gates or a decision-13 case differs between its two base runs;
- a decision-13 case moves after Phase 1, 2 or 4 and the cause is not found within the phase's box (for
  decision 9, the evidence and the fallback go to the stop report);
- a needed wrapper is missing, or `src/core/` or `src/defs/` would change;
- a mirrored name the toys keep is missing at the pin (decision 15) and no addition line describes it;
- decision 14's floor fails at any setting after one diagnosis;
- a phase exceeds twice its box; the static gate fails on something the run did not touch.

**Gates no ruling may waive:** zero warnings in Debug and Release; the static gate; the library untouched; the
oracles share no code with the toys; no SIMPLE source copied; the frozen tolerances hold on seeds 2 and 3; the
off-state build without the library; the graph tail kept beside the fused one.

## 8. Phases

### Phase 0, the base, its identity cases and its rates (box: 150 min)

1. Record the base hash, the machine (compiler, cores, free memory, `uptime`), MLX and mlx-c versions.
2. Re-check "The queue": the file table's paths, the retired-name counts, the static gate's checks.
3. Build Debug and Release from scratch; the fast gate in both; the unit areas; keep the Release build as the
   base build for Phase 4.
4. Run decision 13's cases twice; record their lines and SHA-256; they must be equal.
5. Run decision 14's 12 settings twice; record each row with `uptime`; freeze the floor per setting in Progress.
6. Record, one process at `2500_4` graph tail, the maximum resident size and MLX peak of a run (decision 6's
   reference).

Exit: the counts, the two equal identity sets, the 24 rows and the frozen floors are in Progress; every premise
of "The queue" holds or the run stopped.

### Phase 1, the reference memo, the tiles and the maps' inputs (box: 240 min)

Decisions 2 to 7, 11 and the call sites of decision 4 (driver, host fixture, testers, both benches), the
ledger's lines of decision 5 and the removal of `memoize_ref_bins`.

1. Count the projector tester's assertions of the `memoize_ref_bins` stage before the edit (decision 16).
2. `_calc`, `_core`, `_memo`: `ft_ref_terms`; `flush_refs` as decision 2; `memoize_refs` makes the tiles
   (decision 4); the renames of decision 5; `host_ref_bins` deleted.
3. `_block`: the in-place sums of decision 3; the refusal of unmemoized references.
4. `_workspace`, `_workspace_lifecycle`, `_memo_mlx`: `new` from one parity's terms, `pack_tiles` shared with
   `new_from_memos`, `memo_terms` (decisions 6, 7). Measure decision 6's fallback condition and record it.
5. `_shiftmap_mlx`, `_workspace_shiftmap`: decision 11.
6. `mlxf_toy_eul_prob_tab.f90`, the host fixture, the testers, both benches: the call sites.
7. `scripts/toy_mirror.txt`: the removed line, the renamed additions; rule `mirror`'s plant.

Exit: decision 13's cases equal the base's; the retired-name scan as section 6 (with its plant); the counts as
decision 16; `seam` and `check_toy_offstate.sh --exec` pass; decision 6's choice and numbers are in Progress.

### Phase 2, the particle terms and the seed banks (box: 180 min)

Decisions 8 to 10.

1. `_calc`, `_core`, `_memo`: `ft_ptcl_wterms`, made in `memoize_ptcls`, released with the particle memo.
2. `_block`: the host kernel copies the particle terms; banks `(2nk, pftsz+1, nb)`; `shifted_ptcl_terms`.
3. `_block_mlx`, `_workspace_score`, `mlxf_test_defs.f90`: `submit` takes the terms; `weights` leaves
   `polarft_block_spec`; the banks' check takes the new shape.
4. `mlxf_toy_polarft_calc_tester.f90`: banks through `shifted_ptcl_terms`; its refusals (decision 16).
5. The ledger: the addition line of `shifted_ptcl_terms`; `score_block_posterior` and `set_block_banks` keep
   their lines.

Exit: decision 13's cases equal the base's; the bank gates of `polarft_calc` pass on seeds 2 and 3 on both
devices and the host backend at their frozen bounds; the counts as decision 16.

### Phase 3, the ledger's pin and the record of differences (box: 60 min)

1. `scripts/toy_mirror.txt`: the header names `28c753993` and the files read; rule `mirror` passes.
2. Decision 15's one-off scan; its result in Progress.
3. `mlxf_kernel_families.md`, section 3 (the living list of differences): the memos and their names, the tiles
   made in `memoize_refs`, the seed banks, `ref_gen` kept, `new_pipeline`'s `block_memo` difference gone (SIMPLE
   dropped `block_memo` too), the counters, `set_sigma2_weights`; the sizes of its seam paragraph.

Exit: rule `mirror` passes with the new pin; the scan finds every mirrored name or the run stopped; the families
note's section 3 names no retired procedure.

### Phase 4, the benchmarks on the same layout (box: 180 min)

1. Build the final Release tree; the base build of Phase 0 beside it.
2. Decision 14: 12 settings, base and new interleaved, two pairs each, with `uptime`; the floor judged.
3. Decision 13's cases on the final build.

Exit: every setting meets its floor or is `not_run` by the guard; the table of before and after (time to the
last exit, summed median rate, footprints, MLX peak) is in Progress; decision 13's cases equal the base's.

### Phase 5, the record (box: 120 min)

1. The last-phase gates of section 5.
2. The list for the drafts' revision (decision 17), at least: K3, "The queue" and decision 20 (the dummy list
   of `score_block_posterior`, the banks' shape, the tiles made in `memoize_refs`), and its mirror of
   `eul_prob_tab_neigh`, which `23eb95cc2` and `c1f255d20` changed; K4, "What the check found" (`new_shiftmap_mlx`
   and `ft_ref`, `ft_ref2`, `self%refs` holding `ft_ref2` and `conjg(ft_ref)`) and its memory paragraph of the
   maps' tables; K7, "What it mirrors" (`memoize_ref_bins`), the tile layout of `polarft_workspace_submit`,
   decision 6 (the cc tiles at `memoize_ref_bins`), Phase 2's first step and its file-table row of the memo
   files, and `cc_sums`' lost `l_conj`; K5 and K6, their pin only.
3. The report, the roadmap's row 2e, `doc/history/` (the month of the last day), the notes index.

Exit: the gates pass; `git status` shows paths of the file table only; the report holds the commit message.

### File table

| File (post-2d path) | What | Phases |
| --- | --- | --- |
| `src/test/toys/polar/mlxf_toy_polarft_calc.f90` | members, interfaces, renames, `shifted_ptcl_terms` | 1, 2 |
| `src/test/toys/polar/mlxf_toy_polarft_core.f90` | allocation and release of the memos, setters' invalidation | 1, 2 |
| `src/test/toys/polar/mlxf_toy_polarft_memo.f90` | `flush_refs`, `memoize_refs`, `memoize_ptcls`, retirements | 1, 2 |
| `src/test/toys/polar/mlxf_toy_polarft_memo_mlx.f90` | tiles from `memoize_refs` on both routes | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_block.f90` | in-place sums, particle terms, banks, refusals | 1, 2 |
| `src/test/toys/polar/mlxf_toy_polarft_block_mlx.f90` | the block's terms and banks for the workspace | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_core_mlx.f90` | the device route's memoization, if needed | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap.f90` | comments and refusal texts, if needed | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap_mlx.f90` | `prepare_maps` from the terms | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace.f90` | interfaces of `new`, `submit`, `prepare_maps`; `memo_terms` | 1, 2 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_lifecycle.f90` | `new`, `pack_tiles`, `memoize_sections`, `new_from_memos` | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_score.f90` | `submit` on the particle terms | 2 |
| `src/test/toys/polar/mlxf_toy_polarft_workspace_shiftmap.f90` | `prepare_maps` from the terms | 1 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab.f90` | `new_pipeline` refuses untiled references | 1 |
| `src/test/toys/polar/mlxf_polarft_host_fixture.f90` | the call of `memoize_ref_bins` | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_calc_tester.f90` | call sites, renames, banks, refusals | 1, 2 |
| `src/test/toys/polar/mlxf_toy_polarft_tail_tester.f90` | call sites, renames | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_shiftmap_tester.f90` | call site | 1 |
| `src/test/toys/polar/mlxf_toy_eul_prob_tab_tester.f90` | the driver's construction assertion | 1 |
| `src/test/toys/polar/mlxf_toy_polarft_host_tester.f90` | refusal texts, if needed | 1, 2 |
| `src/test/toys/mlxf_toy_seam_tester.f90` | call site | 1 |
| `src/test/toys/projector/mlxf_toy_projector_tester.f90` | the route stages, call site | 1 |
| `src/test/bench/mlxf_bench_polar_table.f90` | `prepare`, `kill_ref_tiles`, the memory estimate if needed | 1, 2 |
| `src/test/bench/mlxf_bench_projector.f90` | call site | 1 |
| `src/test/framework/mlxf_test_defs.f90` | `polarft_block_spec` (no `weights`, banks' comment) | 2 |
| `src/test/oracles/mlxf_oracle_polar.f90` | a comment naming a retired toy procedure, if needed | 1, 2 |
| `test/offstate/mlxf_offstate_exec.f90` | a call site, if needed | 1, 2 |
| `scripts/toy_mirror.txt` | lines of decisions 4, 5, 10; the pin | 1, 2, 3 |
| the code-base map files of 2d, if the static gate requires their regeneration | regenerated | 1, 2, 3 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | section 3 and the seam paragraph | 3 |
| `doc/implementation_notes/planned/mlxf_toy_layout.md` | Progress | 0, 1, 2, 3, 4, 5 |
| `doc/implementation_notes/completed/mlxf_toy_layout_report.md` (new) | the report | 5 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | row 2e | 5 |
| `doc/implementation_notes/README.md` | the index | 5 |
| `doc/history/2026-11.md` or `doc/history/2026-12.md` | the delivered batch | 5 |
| `doc/collaboration/apple_questions.md` | entry 32 onward, if needed | 0, 1, 2, 3, 4, 5 |

## Progress

(One entry per phase, written by the run: date, machine, base, files changed, each exit item and how it was met,
log paths, decisions taken under delegation, "what it means, in short". A later entry that supersedes an
earlier claim says so.)

## The report

Written in Phase 5 as `completed/mlxf_toy_layout_report.md`, in this order: what was learned (the identity
result, decision 6's choice, the rates on the new layout); what changed, phase by phase, with file counts;
decisions taken under delegation; deviations and every file changed outside the table; evidence against the
baseline (the identity sets' SHA-256, the counts, the 12 settings before and after with their spreads); left open
for the maintainer (decision 17's list, the reserved readings); a commit message without attribution or
co-author line that names the new file.
