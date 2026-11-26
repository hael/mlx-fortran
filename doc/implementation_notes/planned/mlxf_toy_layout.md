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
| `src/test/toys/polar/mlxf_toy_polarft_block_mlx.f90` | the refusal's names after the retirement; the block's terms and banks for the workspace | 1, 2 |
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
| `doc/code_base_map.md` (the code-base map of 2d; the static gate checks it, Phase 0) | regenerated when a `!@descr:` line changes | 1, 2, 3 |
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

### Phase 0, the base, its identity cases and its rates (2026-11-26, 15:15 to 15:40, M5 Ultra)

Base `6a1a03e` (clean; it holds run `mlxf_refactor`'s result, rank 2d). Apple M5 Ultra, 30 cores, 103.1e9 B
(`hw.memsize`), macOS 27.2.1; GNU Fortran 16.2.0 (Homebrew; CMake picks `gfortran-16`), CMake 4.5.1, MLX 0.32.4,
mlx-c 0.8.0 (Homebrew; no `.deps`, no `MLXC_ROOT`); one GPU device (`applegpu_g17d`, `unit_core`: "GPU devices:
1"). Load 3.2 at the start. The rulings file is empty. Paths below are relative to the run's `scratch/keep/`. Files
changed: this plan (Progress). The runners (never committed): `tools/identity.sh` (decision 13's cases, rewritten
from the seam run's description and the refactor run's runner; inputs `tools/identity_inputs/`, the kernel runs'
`polar_case.txt` and the refactor run's `identity_grid.txt`), `tools/timing.sh` (decision 14's settings through
`scripts/run_parts.sh`), the build recipe of the run's instructions in the run's `scratch/tools/build.sh`. The
base's executable is kept as `base_exec/mlxf_test_exec` (SHA-256 `4c844f26...7ca34ab8`) and its tree as the
run's `scratch/base_release/`, the base build of Phase 4.

**Exit items.**
- **The base builds and passes** (`phase0/base_{debug,release}.{configure,build,gate,install}.log`): Debug and
  Release from scratch with `MLXF_WERROR=ON`, 0 warnings, the fast gate 13 of 13 in both (Debug 13.53 s real,
  *measured*), installed. `scripts/check_tree.sh` passes (`phase0/check_tree_base.log`).
- **The counts** (*measured*, `phase0/run_units.log`, `phase0/units_base_{release,debug}/`): `unit_core` 214
  (Release) and 216 (Debug) (the refactor run's 214 plus one line per device whose freed address the allocator
  reused), `unit_array` 193, `unit_ops` 2,462, `unit_linalg` 632, `unit_fft` 194, `unit_compile` 63,
  `unit_transforms` 274, `unit_fast` 152, `unit_random` 486, `unit_io` 846, `unit_distributed` 55, `unit_kernels`
  1,955: `polarft_calc` 327, `polar_shiftmap` 794, `eul_prob_tab` 105, `polarft_tail` 55, `oracle_projection` 44,
  `projector` 100, `projector_chain` 99, `pcg_solver` 86, `reconstructor_pcg` 192, `seam` 88, `polarft_host` 65;
  Debug and Release equal except `unit_core`. These rule for the later phases (section 5: core 214 to 216).
- **The queue re-checked.** Every path of the file table exists (the report is new); the module of each Fortran
  row is the file's (27 rows, one module, submodule or program each, names unchanged by 2d). The static gate
  checks a generated code-base map: `scripts/generate_codeoverview.py --check` holds `doc/code_base_map.md` to
  the `!@descr:` lines and the `.inf` files; it is regenerated with `python3 scripts/generate_codeoverview.py`, and
  only a changed `!@descr:` line or `.inf` file needs it. 2d's new rules (`size` on library files, `publist` on
  test code too) pass on the base and constrain no decision. The retired names: **160 matching lines (196
  occurrences) in 23 files**, not 166 (*exact*, `phase0/retired_names_base.txt`; `rg -c -w` and `git grep -c -w`
  over `src`, `scripts`, `test`); the per-file counts are equal at `b2c43a4` and at the base, and the plan's
  per-file figures (oracle 3, `mlxf_test_defs` 3, bench 11) hold. See decision under delegation 1.
- **Decision 13's identity cases twice, equal** (`tools/identity.sh` on the Release base; `phase0/identity_{a,b}/`,
  `phase0/identity_ab.log`; 107 s each): 364 lines, the two sets equal byte for byte, **SHA-256
  `e2d65e8861d23ef7d731960e17269c6ecaed23fc46d735a1dc37f0bb4d33dba5`** (*exact*; the reference copy
  `phase0/identity_base.txt`). It holds: the seam run's eleven invocations (the polar `suite=time case=1000_1`
  digests `BACBE44E34B4AAB2` graph and `A78E44BB3FCD8220` metal; `suite=accuracy case=2500_4` on the CPU (83
  assertions), the GPU (76) and the GPU's fused tail (98); `suite=shiftmap` window `5B247D6EC83DD4AD` and screen
  `F3A57CA6E86B4898`; the projector's four digest sets; the reconstruction's four history lines and maps' SHA-256);
  K3's decision 20, `suite=time case=2500_4 bt=64 rt=250 passes=3`: graph `3457E99553A08BFD`, metal
  `C65F8ECED8D9B855`; the 135 `polarft_host` lines of `unit_kernels suite=polarft_host` (Release,
  `OMP_NUM_THREADS=1`), and the off-state program's Release table, which `scripts/check_toy_offstate.sh --exec`
  found equal to them. Every line the refactor run's identity set shares with this one is equal to it.
- **Decision 14's 24 rows** (*measured*; `phase0/timing/bt<bt>_<tail>/run_parts.tsv`, one series table per bt and
  tail, the splits' `summary.txt` beside it; `uptime` before and after each in `phase0/timing/uptime.log`; the
  load gate 4, the one-minute load 3.2 to 3.95 at each go and 3.2 to 9.0 after; no other build or test of the run
  beside them). Round a then round b, each in the order 1, 3, 6 processes per series. Time from go to the last
  exit (s) and the summed median rate (pairs/s):

  | Setting (2500_4, rt 250, 9 passes) | a: time, rate | b: time, rate | A-A difference | Frozen floor | Ceiling on the base's mean |
  | --- | --- | --- | --- | --- | --- |
  | bt 64, graph, 1 x 30 | 12.833 s, 1.76010e7 | 12.812 s, 1.76429e7 | 0.16 % | 2 % | 13.079 s |
  | bt 64, graph, 3 x 10 | 13.438 s, 1.68836e7 | 13.495 s, 1.70048e7 | 0.42 % | 2 % | 13.736 s |
  | bt 64, graph, 6 x 5 | not_run (predicted 1.196e11 B) | not_run | | | |
  | bt 64, metal, 1 x 30 | 7.936 s, 3.14713e7 | 7.898 s, 3.15457e7 | 0.48 % | 2 % | 8.075 s |
  | bt 64, metal, 3 x 10 | 19.849 s, 2.92566e7 | 16.912 s, 2.93041e7 | 17.37 % | 34.73 % | 24.765 s |
  | bt 64, metal, 6 x 5 | not_run (1.524e11 and 1.562e11 B) | not_run | | | |
  | bt 16, graph, 1 x 30 | 18.014 s, 1.21095e7 | 18.003 s, 1.20956e7 | 0.06 % | 2 % | 18.369 s |
  | bt 16, graph, 3 x 10 | 17.578 s, 1.26520e7 | 17.525 s, 1.24827e7 | 0.30 % | 2 % | 17.903 s |
  | bt 16, graph, 6 x 5 | not_run (1.247e11 B) | not_run | | | |
  | bt 16, metal, 1 x 30 | 14.666 s, 1.51527e7 | 14.647 s, 1.51504e7 | 0.13 % | 2 % | 14.950 s |
  | bt 16, metal, 3 x 10 | 14.200 s, 1.60618e7 | 14.169 s, 1.60338e7 | 0.22 % | 2 % | 14.468 s |
  | bt 16, metal, 6 x 5 | not_run (1.172e11 B) | not_run | | | |

  Footprints (largest process, *measured*, equal within 0.1 % between a and b): 1 process 2.081e10 (bt 64 graph),
  2.725e10 (bt 64 metal), 2.187e10 (bt 16 graph), 2.061e10 B (bt 16 metal); 3 processes 2.011e10, 2.577e10 and
  2.628e10, 2.100e10, 1.975e10 B each. MLX peak per process 1.03e10 (bt 64 graph) to 1.67e10 B (bt 64 metal);
  summed MLX cache 3.1e9 to 2.77e10 B. The exits' spread at three processes 0.10 to 0.43 s except bt 16 graph
  run a, 2.27 s (its time equal to run b's within 0.3 %); bt 64 metal's two runs, 17 % apart in time, spread
  0.10 and 0.43 s: the three fused parts were slow together, not drifting apart. **The floors are frozen here** (decision 14; decision under delegation 2): at each setting the
  new build's median time over its two Phase 4 runs may exceed the median of the base's interleaved Phase 4 runs
  by at most the frozen floor; the last column is the same floor on Phase 0's mean, for reference.
- **Decision 6's reference** (bt 64, graph, one process, 30 threads; both runs, *measured*): maximum resident size
  17,802,821,632 and 17,802,510,336 B, peak footprint 20,814,378,472 and 20,813,870,352 B, MLX peak
  10,257,300,000 B, MLX cache 3,281,280,000 B. The fallback's line (10 %, *guessed*) is a maximum resident size
  above 1.958e10 B.

**Decisions taken under delegation.**
1. **The retired names' count is 160 lines in 23 files, and its difference from the plan's 166 is not a stop.**
   The stop guards against 2d having moved the names; the counts are equal file by file on `b2c43a4`, the commit
   the plan's check read, and on the base, so 2d moved none, and no reading (lines, occurrences 196, the per-name
   sum 189) gives 166 on `b2c43a4` itself: the plan's total is a miscount. Phase 1's retirement scan uses the
   per-file list of `phase0/retired_names_base.txt`; section 6's exception (ten oracle-type occurrences) holds as
   counted there.
2. **The A-A difference is |a - b| over the smaller of the two times,** the larger of the two readings, and the
   floor is frozen as a percentage per setting, applied in Phase 4 to the base runs interleaved with the new ones
   (decision 14's "base and new builds interleaved"); a larger base-base difference in Phase 4 does not widen it.
3. **The identity set adds the polarft_host table and the off-state table to the seam run's eleven invocations
   and K3's two:** the table is run with `OMP_NUM_THREADS=1` as `check_toy_offstate.sh` runs it, and the
   off-state program's table is taken from that script's Release build of the checkout being compared.
4. **One series table per bt and tail** for `run_parts.sh`, so that its guard predicts a split from that
   configuration's own one-process row; the load gate is 4 (the run's instruction) in place of the script's 2.

**What the base says about the later phases.** The guard refuses every six-process split at the base (each
predicted above 0.8 of the machine), so Phase 4 judges eight settings. The three-process fused split at bt 64 ran
with a predicted 8.176e10 B against the guard's 8.246e10 B (*measured*, *derived*): a margin of 7.0e8 B, 2.3e8 B
per process. Decision 8's `ft_ptcl_wterms` alone adds 3.6e8 B per process (*derived*: 122 x 183 x 2,000 x 8 B),
so unless Phase 1 lowers the host footprint (the bin-major copy and the complex staging go) the guard will refuse
that split after Phase 2. Phase 1 measures the one-process footprint of each series; a split the base ran and the
guard then refuses is decision 6's fallback condition when Phase 1's preparation causes it, and is recorded
`not_run` with its cause when Phase 2's memo does.

**What it means, in short.** The base is sound on this machine: both builds clean, the gate passes, every unit area
at its count, the identity set (now 364 lines, with K3's dense cases and both host tables) bit for bit repeatable,
and the rates repeat within 0.5 % except the three-process fused split at bt 64 (17 % between two runs, its
floor 34.7 % by decision 14's rule; the fused tail's three-part instability K1 met). The floors are frozen; the plan's retired-name total was a miscount, not a change by 2d.

### Phase 1, the reference memo, the tiles and the maps' inputs (2026-11-26, 15:40 to 16:10, M5 Ultra)

Base `6a1a03e` with Phase 0's Progress. Toolchain as Phase 0. Paths are relative to the run's `scratch/keep/`. The
rulings file is empty.

**Files changed (23):** `src/test/toys/polar/` `mlxf_toy_polarft_calc.f90`, `_core`, `_memo`, `_memo_mlx`, `_block`,
`_block_mlx`, `_shiftmap_mlx`, `mlxf_toy_polarft_workspace.f90`, `_workspace_lifecycle`, `_workspace_shiftmap`,
`mlxf_toy_eul_prob_tab.f90`, `mlxf_polarft_host_fixture.f90`, the testers `mlxf_toy_polarft_calc_tester.f90`,
`_tail_tester`, `_shiftmap_tester`, `mlxf_toy_eul_prob_tab_tester.f90`; `src/test/toys/mlxf_toy_seam_tester.f90`,
`src/test/toys/projector/mlxf_toy_projector_tester.f90`; `src/test/bench/mlxf_bench_polar_table.f90`,
`mlxf_bench_projector.f90`; `scripts/toy_mirror.txt`; `doc/code_base_map.md` (regenerated: the memo submodule's
`!@descr:` names the tiles; the file table's row of the map now names this file); this plan. Not needed:
`_core_mlx`, `_shiftmap`, `_host_tester`, the oracle, `test/offstate/` (no retired name, no call site).

**What was done.** Decision 2: `ft_ref_terms (2nk, pftsz+1, nrefs, 2)` replaces `ft_ref`, `ft_ref2` and
`ft_ref_bins`; `flush_refs` writes row kk the rounded transform of the squared modulus (no conjugation) and row
nk+kk the ring's. Decision 3: the host kernel sums `conjg(pterms(kk, b, j)) * ft_ref_terms(kk, j, iref, ieo)`;
`host_ref_bins` deleted. Decision 4: `memoize_ref_bins` and its glue retired; `memoize_refs` ends by making both
parities' tiles on the MLX backend (glue `memoize_ref_tiles_mlx`), again from the host memo when nothing waits;
`new_pipeline` refuses a calculator whose tiles are not current ("... reference tiles are not those of its
memoized references, tile plan and tail (memoize_refs)"). Decision 5: `kill_ref_tiles`, `ref_tiles_current`,
`ref_gen_tiles`; the refusals cite `memoize_refs`. Decision 6: see below. Decision 7: the device route's
`memoize_sections` makes one `memo_terms (2nk, pftsz+1, nrefs)` (the r2c transform of |z|^2 without its
conjugation, then the ring's FFT slice, each permuted to shell-major); `memo_ref`, `memo_ref2` gone;
`new_from_memos` packs it on the device. Decision 11: `prepare_maps` takes one parity's terms; `rfull` from rows
nk+1.., `ref2b` the conjugate of rows 1..nkb transposed on the host; `tile_maps` untouched. Call sites: the driver,
the host fixture, five testers, both benches (`prepare` is `set_tail_form`, `set_tile_plan`, `memoize_refs`;
`kill_ref_tiles` six times). Ledger: the line of `memoize_ref_bins` removed, the two additions renamed with their
reasons.

**Decision 6's choice: the fallback, packing on the host** (*measured*, one round of the eight settings the base
ran, `run_parts.sh`, load gate 4, nothing else running; one-process maximum resident size, peak footprint, MLX
cache; the guard's prediction for three processes):

| Build (bt 64 unless named) | Max RSS, 1 x 30 graph | Footprint, 1 x 30 graph | MLX cache, 1 x 30 graph | bt 64 metal 3 x 10: predicted | Guard |
| --- | --- | --- | --- | --- | --- |
| base (Phase 0) | 1.7803e10 B | 2.0814e10 B | 3.28e9 B | 8.176e10 B | runs (limit 8.246e10) |
| device packing (decision 6 as recommended; `phase1/timing_devpack/`) | 7.09e9 B (-60 %) | 2.3487e10 B (+12.8 %) | 1.132e10 B | 8.978e10 B | **refuses** a split the base ran |
| host packing from `ft_ref_terms` (the fallback; `phase1/timing/`) | 1.6016e10 B (-10.0 %) | 1.9026e10 B (-8.6 %) | 3.28e9 B | 7.640e10 B | runs, margin 6.1e9 B |

The device packing lowers the resident size but leaves its intermediates (conjugate, padding, permutation, the
real block) in MLX's cache beside the tiles, which the peak footprint counts and the guard predicts from: the
fallback's condition held, so `polarft_workspace%new` packs on the host straight from one parity's
`ft_ref_terms` into the real block (no complex staging: 3.57e9 B per parity at `2500_4` instead of 5.36e9,
*derived*) and uploads it once; the device route keeps its own packing in `new_from_memos`. MLX peak is equal in
every setting to the base's (1.0257e10 B at bt 64 graph). The fallback's other settings (footprint per process,
*measured*): bt 64 metal 2.547e10 B (base 2.725e10), bt 16 graph 2.008e10 (2.187e10), bt 16 metal 1.882e10
(2.061e10). The time from go to the last exit was shorter than the base's at every setting in this single round
(by 4 to 9 % at one process, *measured*; not judged here, Phase 4 judges it on interleaved pairs).

**Exit items.**
- **Decision 13's cases equal the base's** (*exact*): `phase1/identity/identity.txt`, built from scratch, SHA-256
  `e2d65e88...4d33dba5`, byte for byte `phase0/identity_base.txt` (also on the device-packing build,
  `phase1/identity_devpack/`). The comparison's plant: a copy with `BACBE44E34B4AAB2` turned to `...AAB3` fails
  `cmp` (`phase1/identity_plant.log`), removed.
- **The retirement scan** (*exact*, `tools/retired_scan.sh`, `phase1/retired_scan.log`): the retired names remain
  only as the ten oracle-type occurrences (bench 4, `mlxf_test_defs` 3, oracle 3); `memoize_ref_bins` appears
  nowhere in `src/` or `scripts/`. Its plant: a scratch file holding `ft_ref_bins` makes it fail
  (`phase1/retired_scan_plant.log`), removed.
- **Rule `mirror`'s plant**: the ledger line of `memoize_ref_bins` put back after its removal from the code fails
  `check_rules.py` ("is not a public type, binding or procedure of a toy module", `phase1/mirror_plant.log`); the
  ledger restored, every rule holds (`phase1/mirror_after.log`).
- **The counts** (*measured*, Debug and Release, `phase1/run_units.log`, `phase1/units_p1_{release,debug}/`): as
  Phase 0 except `unit_kernels` 1,947: `projector_chain` 91 (99 less the 8 assertions of the route stage
  "memoize_ref_bins": 2 devices x 2 routes x 2 assertions, counted before the edit), every other sub-suite at its
  count (`polarft_calc` 327, `polarft_tail` 55, `polar_shiftmap` 794, `eul_prob_tab` 105, `seam` 88,
  `polarft_host` 65). `unit_core` 216 (Release) and 214 (Debug), in its range.
- **`seam` and the off state**: `seam` 88 of 88 in both builds; `scripts/check_toy_offstate.sh --exec` passes, the
  host table equal to `mlxf_test_exec`'s (135 lines; `phase1/check_toy_offstate.log`).
- **Builds and gates**: Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, the fast gate in both
  (`phase1/p1b_{release,debug}.*`); `scripts/check_tree.sh` passes (`phase1/check_tree.log`); both formatters on the
  20 touched Fortran files (nothing rewritten).

**Re-pointed assertions (decision 16, one for one).** `polarft_calc`: "a calculator without reference bins
refuses a block" became "whose reference tiles were released (`kill_ref_tiles`)"; "refused when the references were
memoized again and their bins were not" became "refused when the tile plan changed after the references were
memoized"; in the rebuild, "after the references are memoized again their bins are not current" became "after the
references are set again their tiles are not current", the refusal waits for `memoize_refs`. `polarft_tail`: the
CPU refusal feeds the compiled form and sets the fused one before `memoize_refs`; the live-handle counts measure
`memoize_refs` after `kill_ref_tiles`. `eul_prob_tab`: the driver is made on the tiles `memoize_refs` made.
`projector_chain`: "a block before memoize_ref_bins is refused" became "a block before memoize_refs is refused".

**Ruling R1 (2026-11-26, the run's `spec/rulings.md`, after the driver's fence stop of Phase 1).** The fence
refused `src/test/toys/polar/mlxf_toy_polarft_block_mlx.f90`, whose refusal's generation check and message this
phase renamed from `memoize_ref_bins` / `ref_gen_bins` to `memoize_refs` / `ref_gen_tiles` (decision 4's
consequence); the file table assigned that file to Phase 2 only, an omission of the table. Ruled: its row lists
Phases 1 and 2 (edited by the controller); Phase 1's work stands. Applied here; no file changed after the ruling,
and the gates above ran on the tree as it stands (`git diff` unchanged since them).

**Decisions taken under delegation.**
1. **`memoize_refs` advances the references' generation only when references waited.** With none waiting the
   memos are unchanged, so the shift maps made from them stay valid when a benchmark re-tiles (`prepare`).
2. **`ref_tiles_current` is false while references wait**, and on the host backend `memoize_refs` marks the memo
   itself current (the kernel reads it in place); the setters of the plan, tail and route invalidate it on both
   backends, as before.
3. **The tester helper `make_calc` is deleted** (it was `feed_calc` plus the retired call); its five callers call
   `feed_calc`.
4. **Decision 6's fallback is taken as fixed** (above), and the device route's packing stays inline in
   `new_from_memos`, its one caller.

**What it means, in short.** The toys hold one reference memo in SIMPLE's layout, the host kernel reads it in place,
and `memoize_refs` makes the tiles; nothing the toys compute moved by a bit. The device packing was tried and
measured: it trades 10.7e9 B of resident host memory for 2.7e9 B more peak footprint, which made the guard refuse
a split the base ran, so the packing stays on the host, now without the complex staging, and every footprint fell.

### Phase 2, the particle terms and the seed banks (2026-11-26, 16:13 to 16:21, M5 Ultra)

Base `6a1a03e` with Phases 0 and 1. Paths are relative to the run's `scratch/keep/`. Rulings: R1 only (Phase 1).

**Files changed in this phase (10):** `src/test/toys/polar/` `mlxf_toy_polarft_calc.f90` (member `ft_ptcl_wterms`,
binding and interface `shifted_ptcl_terms`, the banks' comments), `_core` (allocation and release with the particle
memo), `_memo` (`memoize_ptcls` makes the terms), `_block` (the host kernel copies the terms or the bank;
`shifted_ptcl_terms`; the banks' refusal), `_block_mlx` (`submit` on the terms; `weights` no longer set),
`mlxf_toy_polarft_workspace.f90` (`submit`'s interface), `_workspace_score` (the gather, one upload, no device
multiply), `mlxf_toy_polarft_calc_tester.f90` (banks through `shifted_ptcl_terms`, its refusals);
`src/test/framework/mlxf_test_defs.f90` (`polarft_block_spec` without `weights`, the banks' comment);
`scripts/toy_mirror.txt` (the addition line of `shifted_ptcl_terms`). Not needed: the oracle, the host tester,
the off-state program, the bench (no bank, no retired name).

**What was done.** Decision 8: `ft_ptcl_wterms (2nk, pftsz+1, nptcls)` made at the end of `memoize_ptcls` from the
finished `ft_ctf2` and `ft_ptcl_ctf` (rows kk `sigma2_wk(k, ih) * ft_ctf2`, rows nk+kk `(-2 sigma2_wk(k, ih)) *
ft_ptcl_ctf`, single precision, the team's loop), released with the particle memo; `set_sigma2_weights` still
invalidates the particle memo. Decision 9: `polarft_workspace%submit(blk, ft_ptcl_wterms, status)` gathers the
block's columns to `(2nk, pftsz+1, bpad)` (a seed bank where `l_bank`), uploads them once and permutes a particle
tile to `(bt, 2nk, pftsz+1)`; `polarft_block_spec%weights` and the device multiply are gone. Decision 10: banks are
`(2nk, pftsz+1, nb)` particle terms in `score_block_posterior`, `set_block_banks` and the workspace's check; the
addition `shifted_ptcl_terms(iptcl, xctf, bank)` makes one from a fixture's shifted FT(X.CTF) `(pftsz+1, nk)`:
rows 1..nk the particle's terms, rows nk+1..2nk `(-2 w_k) * xctf`; it refuses a transform of another shape and a
particle outside the batch. The tester converts the oracle's raw banks (decision 12: the oracle keeps them) with
it, in one helper `toy_banks` used by its synchronous and queued blocks.

**Exit items.**
- **Decision 13's cases equal the base's** (*exact*; decision 9's prediction holds): `phase2/identity/identity.txt`,
  SHA-256 `e2d65e88...4d33dba5`, byte for byte `phase0/identity_base.txt`; the off-state check inside it passes
  (`phase2/identity/offstate.log`).
- **The bank gates of `polarft_calc`** pass at their frozen bounds as the suite runs them
  (`phase2/units_p2_{release,debug}/unit_kernels.log`): the fixture rows of seed 2 (bank and mixed particles among
  them) on the CPU and the GPU with both tails, the bank fixture's check (largest relative difference of
  weighted power 2.611e-9, *measured*, bound 1e-6), and the fused tail against the compiled one on seeds 2 and 3
  (seed 3: rows 1.190e-7, distances 6.128e-8, 0 of 96 rotations differing, *measured*). The bench's
  `suite=accuracy` (seed 2, both devices, both tails) is inside the identity set and equal. **The host backend
  has no bank gate,** at the base as now: no test hands the host kernel a bank, and decision 16 allows no new
  assertion beyond the refusals; its bank branch is a copy of the bank's column (reported, not gated).
- **The counts** (*measured*, Debug and Release equal, `phase2/run_units.log`): `unit_kernels` 1,953:
  `polarft_calc` 333 (327 plus the two refusals of `shifted_ptcl_terms` in `test_refusals`, which runs once per
  backend run: CPU graph, GPU graph, GPU fused, so 6, decision 16's "at most 6"), `projector_chain` 91 (Phase 1),
  every other sub-suite at its Phase 0 count; the other areas as Phase 0 (`unit_core` 216 in both builds).
- **Builds and gates**: Debug and Release from scratch with `MLXF_WERROR`, 0 warnings, the fast gate in both
  (`phase2/p2_{debug,release}.*`); `scripts/check_tree.sh` passes (`phase2/check_tree.log`); the retirement scan
  passes (`phase2/retired_scan.log`); the code-base map is current (no `!@descr:` changed); both formatters on the
  touched Fortran files.

**Decisions taken under delegation.**
1. **`shifted_ptcl_terms` refuses what decision 16 counts, and no more:** a stale particle memo is not a refusal
   (the bank reads the memoized terms; `memoize_ptcls` comes first, as for every block), which keeps the added
   assertions at the plan's six.
2. **The tester hands the toy banks through one helper (`toy_banks`)**, called where it scored or queued with the
   oracle's raw banks; the oracle's `polar_table_block` and its raw banks are unchanged.

**What it means, in short.** The particle terms are made once on the host, in SIMPLE's layout, and both the host
kernel and the device read them; a seed bank is a set of particle terms, as SIMPLE's shifted particle is. Nothing
moved by a bit: the device's weighting was one rounding of the same two operands, as predicted.

### Phase 3, the ledger's pin and the record of differences (2026-11-26, 16:21 to 16:25, M5 Ultra)

Base `6a1a03e` with Phases 0 to 2. Paths are relative to the run's `scratch/keep/`. Rulings: R1 only. **Files
changed in this phase (3):** `scripts/toy_mirror.txt` (the header), `doc/implementation_notes/planned/
mlxf_kernel_families.md` (section 3), this plan. No Fortran file; no build needed (none of the gates reads them
but the static gate).

**Exit items.**
- **Rule `mirror` passes with the new pin** (`phase3/check_rules.log`, `phase3/check_tree.log`): the header records
  SIMPLE commit `28c753993` and the files read (the polar calculator and its submodules, now also the driver's
  `src/main/strategies/search/probabilistic/simple_eul_prob_tab.f90`, the projector and the image files it
  inherits from, the PCG reconstruction and solver), and names the earlier pin `d354efee2`.
- **Decision 15's one-off scan** (`tools/mirror_scan.py`, reading SIMPLE through `git grep <pattern> <rev>` and
  `git show <rev>:<path>` only; `phase3/mirror_scan_28c753993.log`): **every one of the 60 mirrored lines is found
  at `28c753993`** (*exact*): 24 of `simple_polarft_calc` (types, bindings in the type's `procedure` lines, the
  module procedure `vol_pad2ref_pfts_opt` in its `public` lines), 4 of `simple_eul_prob_tab`, 9 of
  `simple_projector` (bindings inherited from `simple_image`), 1 of `simple_projector_pft_batch`, 14 of
  `simple_reconstructor_pcg` (with `simple_pcg_lattice`), 8 of `simple_pcg_solver`. The scan can fail: a copy of the
  ledger with the retired `memoize_ref_bins` line and an invented name gives 2 missing at `28c753993` and 1 at
  `d354efee2`, where `memoize_ref_bins` exists (`phase3/mirror_scan_plant_{28c753993,d354efee2}.log`). Not a gate:
  SIMPLE is not in the checkout or in CI.
- **The families note's section 3** names no retired procedure (`rg -w` over its lines for every retired name and
  `block_memo`: none). It now records: the seam's tiles made by `memoize_refs` and held until `kill_ref_tiles`; the
  host's memos (`ft_ref_terms` 3.57e9 B, the particles' memos and terms 0.71e9 B, *derived*); the part process's
  footprint on the one layout (19.03e9 and 18.32e9 B, Phase 1, *measured*, plus 0.36e9 B of particle terms,
  *derived*); differences read at `28c753993`: the memos and their names, the tiles, the counters (`ref_gen` kept),
  the seed banks, `set_sigma2_weights`, the maps' reference power order (K4's); `new_pipeline`'s `block_memo`
  difference removed (SIMPLE dropped `block_memo` too).

**Decisions taken under delegation.**
1. **The scan reads a binding of an inherited type in its parent's files** (`simple_image` for the projector,
   `simple_pcg_lattice` for the reconstruction), as the ledger's header says the toys inherit them; a module
   procedure counts when named in a `public` line or defined in a module without a bare `private`.
2. **The part process's footprint in section 3 is Phase 1's measurement** with the particle terms' size added as
   derived; Phase 4's final measurement goes to this plan and the report, not to the note, unless it differs.

**What it means, in short.** The ledger says what the toys mirror today, and every name it calls SIMPLE's is
SIMPLE's at the new pin. The note's list of differences describes the one memo layout; no retired name is left.

### Phase 4, the benchmarks on the same layout (2026-11-26, 16:23 to 17:01, M5 Ultra)

Base `6a1a03e` with Phases 0 to 3. Paths are relative to the run's `scratch/keep/`. Rulings: R1 only. **Files
changed in this phase:** this plan (Progress). The base build is Phase 0's executable (`base_exec/mlxf_test_exec`,
SHA-256 `4c844f26...`, the library linked in); the new build is the final Release tree built from scratch
(`final_exec/mlxf_test_exec`, SHA-256 `243c7da5...`).

**Exit items.**
- **The final builds** (`phase4/final_{release,debug}.*`): Release and Debug from scratch with `MLXF_WERROR`, 0
  warnings, the fast gate 13 of 13 in both; `scripts/check_tree.sh` passes (`phase4/check_tree.log`); the unit
  areas at the counts of Phase 2 (`phase4/run_units.log`: `unit_kernels` 1,953 with `polarft_calc` 333 and
  `projector_chain` 91; `unit_core` 215 in Release, 216 in Debug; every other area as Phase 0).
- **Decision 14: every setting meets its frozen floor or is `not_run` by the guard** (*measured*;
  `phase4/timing_abba.sh`, `phase4/timing_{base,new}/bt<bt>_<tail>/run_parts.tsv` with each split's `summary.txt`,
  `uptime` before and after each in `phase4/timing_{base,new}/uptime.log`; the judgement `phase4/judge14.md` by
  `tools/judge14.py`). Per setting two pairs, base and new interleaved: round 1 base then new, round 2 new then
  base, each build with its own series tables; the load gate 4, the one-minute load 2.22 to 3.99 at each go and
  3.37 to 9.01 after; nothing else of the run beside them; no split discarded or repeated. Time from go to the
  last exit, the median of each build's two runs:

  | Setting (2500_4, rt 250, 9 passes) | Base: runs, median | New: runs, median | New against base | Frozen floor | Verdict |
  | --- | --- | --- | --- | --- | --- |
  | bt 64, graph, 1 x 30 | 12.795, 12.822: 12.808 s | 12.038, 12.095: 12.067 s | -5.79 % | 2 % | met |
  | bt 64, graph, 3 x 10 | 13.404, 13.462: 13.433 s | 12.559, 12.548: 12.553 s | -6.55 % | 2 % | met |
  | bt 64, metal, 1 x 30 | 7.911, 7.892: 7.902 s | 7.143, 7.158: 7.151 s | -9.50 % | 2 % | met |
  | bt 64, metal, 3 x 10 | 15.229, 15.565: 15.397 s | 7.636, 7.660: 7.648 s | -50.33 % | 34.73 % | met |
  | bt 16, graph, 1 x 30 | 18.029, 18.037: 18.033 s | 17.280, 17.318: 17.299 s | -4.07 % | 2 % | met |
  | bt 16, graph, 3 x 10 | 17.514, 17.575: 17.544 s | 16.776, 16.779: 16.777 s | -4.37 % | 2 % | met |
  | bt 16, metal, 1 x 30 | 14.575, 14.599: 14.587 s | 13.902, 13.885: 13.893 s | -4.75 % | 2 % | met |
  | bt 16, metal, 3 x 10 | 14.206, 14.116: 14.161 s | 13.268, 13.323: 13.296 s | -6.11 % | 2 % | met |
  | the four 6 x 5 settings | not_run (predicted 1.17e11 to 1.57e11 B) | not_run (1.08e11 to 1.49e11 B) | | | not_run |

  Reported beside them (base / new, mean of two, *measured*): the largest footprint at one process 2.081e10 /
  1.883e10 B (bt 64 graph), 2.725e10 / 2.527e10 (bt 64 metal), 2.187e10 / 1.990e10 (bt 16 graph), 2.061e10 /
  1.864e10 (bt 16 metal), about 2.0e9 B less per process although the particle terms add 0.36e9 B (the host
  packing's complex staging is gone); MLX peak 1.026e10 / 0.989e10 B (bt 64 graph) and 1.671e10 / 1.635e10 B
  (bt 64 metal), the device's weighting intermediates gone; summed cache 3.28e9 / 2.92e9 B (bt 64 graph). The summed
  median rate at one process is unchanged within 0.5 % (1.766e7 / 1.765e7 pairs/s, bt 64 graph; 3.154e7 /
  3.169e7, bt 64 metal), so the shorter time from go to the last exit at one process is not the passes' own
  speed but the work around them inside the timed window. At three processes the exits spread up to 8.5 s (bt 16)
  on both builds, which makes the summed median rate unreliable there (base 1.68e7 against new 2.20e7 pairs/s at bt
  16 graph, an artefact of the spread); the judgement is on the time from go to the last exit, as decision 14 says.
  The base's three-process fused split at bt 64 took 15.2 to 15.6 s here and 16.9 to 19.8 s in Phase 0, the new
  build's 7.6 s in all four runs; a likely reading (*guessed*, not measured further): with 2.0e9 B less per
  process the three fused parts no longer press on the machine's memory (the base's guard prediction 8.18e10 B
  against the limit 8.25e10).
- **Decision 13's cases on the final build** (*exact*): `phase4/identity/identity.txt`, SHA-256
  `e2d65e88...4d33dba5`, byte for byte `phase0/identity_base.txt`; the off-state check inside it passes.

**Decisions taken under delegation.**
1. **The order of the pairs is ABBA** (round 1 base then new, round 2 new then base), so that neither build always
   runs first after the load gate; the floor is judged on the median of each build's two Phase 4 runs, as frozen.
2. **The profile's stage hypothesis (section 6) was not measured:** it is not a criterion, and the identity set and
   the rates already answer what it would explain; left for 2f's experiments.

**What it means, in short.** On SIMPLE's layout the dense benchmark is at least as fast as on the old one at every
setting the machine runs: 4 to 10 % shorter from go to the last exit at one and three processes, and twice as fast
for three fused parts at bt 64, where the old layout's footprint sat at the guard's limit. Each part process holds
about 2.0e9 B less, and nothing it computes moved.

### Phase 5, the record (2026-11-26, 17:01 to 17:10, M5 Ultra)

Base `6a1a03e` with Phases 0 to 4. Paths are relative to the run's `scratch/keep/`. Rulings: R1 only. **Files
changed in this phase (5):** the report `doc/implementation_notes/completed/mlxf_toy_layout_report.md` (new), the
roadmap's row 2e, the notes index (`doc/implementation_notes/README.md`), `doc/history/2026-11.md`, this plan.

**Exit items.**
- **The last-phase gates pass** (`phase5/gates.sh`, `phase5/gates.log`): Debug and Release from scratch with
  `MLXF_WERROR`, 0 warnings, the fast gate in both; the Release fast gate 10 times of 10 (10.37 to 11.18 s,
  *measured*, bound 38.74 s; `phase5/fast_gate_{1..10}.log`); `scripts/check_tree.sh`, `scripts/check_embed.sh`,
  `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh` and `scripts/release_gate.sh --allow-dirty`
  (`phase5/release_gate.log`, "RELEASE GATE PASSED: 6a1a03e-dirty", 77 s); the unit areas at Phase 2's counts in
  both builds (`phase5/run_units.log`: `unit_kernels` 1,953; `unit_core` 216 and 214). The release gate's work
  directory `build_release_gate/` (ignored by git) was removed after its log was copied.
- **Decision 17's list** of the sections of K3 to K7 that cite the old layout is in the report ("Left open for the
  maintainer"); the drafts are not edited.
- **The report, the roadmap's row 2e, the history entry and the index** are written; the report holds the commit
  message, which names the one new file and carries no attribution line.
- **`git status` shows paths of the file table only** (29 modified, 1 new: the report).

**What it means, in short.** The run is complete: the toys mirror SIMPLE's one memo layout, every gate of the
release passes on the working tree, nothing the toys compute moved, and the drafts of K3 to K7 have their list of
sections to revise after 2f.

## The report

Written in Phase 5 as `completed/mlxf_toy_layout_report.md`, in this order: what was learned (the identity
result, decision 6's choice, the rates on the new layout); what changed, phase by phase, with file counts;
decisions taken under delegation; deviations and every file changed outside the table; evidence against the
baseline (the identity sets' SHA-256, the counts, the 12 settings before and after with their spreads); left open
for the maintainer (decision 17's list, the reserved readings); a commit message without attribution or
co-author line that names the new file.
