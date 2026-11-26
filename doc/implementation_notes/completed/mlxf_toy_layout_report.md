# Report of run `mlxf_toy_layout`: the polar toys on SIMPLE's memo layout (roadmap rank 2e)

Plan: [`mlxf_toy_layout.md`](../planned/mlxf_toy_layout.md) (its Progress holds the detail, phase by phase). Run on
the M5 Ultra, 2026-11-26, 15:15 to 17:10, unattended, from base `6a1a03e` (run `mlxf_refactor`'s result), in
a copy of the checkout; nothing committed. SIMPLE read at `28c753993` (and `d354efee2`) through `git show` and
`git grep` only; nothing of SIMPLE copied. Evidence paths are under the run's `scratch/keep/`; the diffs are the
run's `review/phase_N.diff`. One ruling (R1).

## What was learned

- **Identity holds.** The toys now hold SIMPLE's one reference memo `ft_ref_terms (2nk, pftsz+1, nrefs, 2)` and its
  particle terms `ft_ptcl_wterms`, and not one output moved: the 364-line identity set (the seam run's eleven
  invocations, K3's two dense cases at `2500_4`, the host table and the off-state table) equals the base's byte
  for byte after Phases 1, 2 and 4, SHA-256 `e2d65e8861d23ef7d731960e17269c6ecaed23fc46d735a1dc37f0bb4d33dba5`.
  Decision 9's prediction (moving the particle weighting from the device to the host changes no bit) held.
- **Decision 6: the fallback, measured.** Packing the reference tiles on the device (the recommendation) cut the
  maximum resident size from 1.780e10 to 7.09e9 B but raised the peak footprint from 2.081e10 to 2.349e10 B
  (+12.8 %): MLX's cache keeps the packing's intermediates. The memory guard then refused the three-process fused
  split at bt 64, which the base ran, so the plan's fallback was taken: the tiles are packed on the host straight
  from `ft_ref_terms`, with no complex staging (resident size -10 %, footprint -8.6 %). The device route keeps its
  own packing from the device memo.
- **The rates on the new layout.** Every setting the guard runs meets its frozen floor, and the new build is faster
  at each: 4.1 to 9.5 % shorter from go to the last exit at one and three processes, and 7.6 s against 15.4 s for
  three fused parts at bt 64 (the base's footprint sat at the guard's limit there). The passes' own median rate is
  unchanged at one process; each part holds about 2.0e9 B less, although the particle terms add 0.36e9 B.

## What changed, phase by phase

| Phase | Diff | Files | What |
| --- | --- | --- | --- |
| 0 | `review/phase_0.diff` | 1 | The base measured: builds, counts, the identity set twice, decision 14's 24 rows, the floors frozen; the plan's Progress |
| 1 | `review/phase_1.diff` | 23 | `ft_ref_terms` replaces `ft_ref`, `ft_ref2`, `ft_ref_bins`; the host kernel reads it in place; `memoize_ref_bins` retired, `memoize_refs` makes the tiles; `kill_ref_tiles`, `ref_tiles_current`, `ref_gen_tiles`; the device route's `memo_terms`; the maps' inputs; the driver refuses untiled references; call sites in the fixture, five testers, both benches; the ledger; the code-base map regenerated |
| 2 | `review/phase_2.diff` | 11 | `ft_ptcl_wterms` made in `memoize_ptcls`; the host kernel and the device read it (`polarft_block_spec%weights` and the device multiply gone); seed banks are particle terms `(2nk, pftsz+1, nb)`; the addition `shifted_ptcl_terms` |
| 3 | `review/phase_3.diff` | 3 | The ledger pinned at `28c753993`; decision 15's scan (60 of 60 found); the families note's section 3 |
| 4 | `review/phase_4.diff` | 1 | Decision 14 judged (all met), decision 13 on the final build |
| 5 | `review/phase_5.diff` | 5 | The last gates; this report; the roadmap's row 2e, the notes index, the history |

The run changed 29 tracked files and added this report: 22 Fortran files under `src/test/` (no file under
`src/core/` or `src/defs/`), `scripts/toy_mirror.txt`, `doc/code_base_map.md`, and five documents.

## Decisions taken under delegation

Each is recorded, with its reason, in the plan's Progress of the phase named.

1. Phase 0: the retired names count 160 lines (196 occurrences) in 23 files, not the plan's 166; the per-file counts
   are equal at `b2c43a4` and the base, so it is a miscount and not a change by 2d, and not a stop.
2. Phase 0: the A-A difference is taken over the smaller time; the floor is frozen as a percentage and applied to
   Phase 4's interleaved base runs.
3. Phase 0: the identity set adds the host table (one thread) and the off-state table to the seam run's and K3's
   cases; one `run_parts.sh` series table per bt and tail; the load gate 4.
4. Phase 1: `memoize_refs` advances the references' generation only when references waited (the maps stay valid
   when a benchmark re-tiles).
5. Phase 1: `ref_tiles_current` is false while references wait; on the host backend the memo is its own "tiles".
6. Phase 1: the tester helper `make_calc` deleted (its callers call `feed_calc`); the re-pointed assertions listed
   one for one in Progress.
7. Phase 1: decision 6's fallback taken as the plan fixes it; the device route's packing stays inline in
   `new_from_memos`.
8. Phase 2: `shifted_ptcl_terms` refuses a wrong shape and a particle outside the batch, not a stale memo, which
   keeps the added assertions at the plan's six.
9. Phase 2: the tester converts the oracle's raw banks through one helper, `toy_banks`.
10. Phase 3: the scan reads an inherited binding in the parent's files; a module procedure counts when public.
11. Phase 3: the families note carries Phase 1's footprint plus the particle terms' derived size.
12. Phase 4: the pairs ordered ABBA; the profile's stage hypothesis not measured (not a criterion).

## Deviations from the plan, and files outside the table

- **Ruling R1** (after the driver's fence stop of Phase 1): `mlxf_toy_polarft_block_mlx.f90` was edited in Phase 1
  (its refusal renamed with the retirement, decision 4's consequence) while the file table assigned it to Phase 2
  only; the maintainer ruled the row to list Phases 1 and 2 and Phase 1's work to stand.
- **The file table's map row** was made concrete in Phase 1 (`doc/code_base_map.md`, regenerated because the memo
  submodule's `!@descr:` names the tiles).
- **Decision 6** ended on its fixed fallback (above), with both measurements in Phase 1's Progress.
- **Not needed** from the table: `_core_mlx`, `_shiftmap`, `_host_tester`, the oracle, `test/offstate/`,
  `apple_questions.md` (no finding about MLX or mlx-c).
- **The host backend has no bank gate,** at the base as now; its bank branch is a copy of the bank's column
  (reported in Phase 2, not gated).

## Evidence against the baseline

- **Identity:** `phase0/identity_{a,b}/` (two base runs equal), `phase1/identity/`, `phase2/identity/`,
  `phase4/identity/`: all SHA-256 `e2d65e88...4d33dba5`. Plants: one flipped hexadecimal digit fails the comparison
  (`phase1/identity_plant.log`); a scratch file with `ft_ref_bins` fails the retirement scan
  (`phase1/retired_scan_plant.log`); the ledger line of `memoize_ref_bins` fails rule `mirror`
  (`phase1/mirror_plant.log`). Each plant removed.
- **Retirement:** the retired names remain only as the ten occurrences of the oracle's own input type; none in a
  toy, fixture, tester or bench; `memoize_ref_bins` nowhere in `src/` or `scripts/` (`tools/retired_scan.sh`).
- **Counts** (Debug and Release): `unit_kernels` 1,955 at the base, 1,947 after Phase 1 (`projector_chain` 99 to 91:
  the 8 assertions of its retired route stage), 1,953 after Phase 2 (`polarft_calc` 327 to 333: two refusals of
  `shifted_ptcl_terms` in each of three backend runs); every other sub-suite and area unchanged (`unit_core` 214 to
  216 by the allocator, as at the base).
- **Rates** (decision 14; `phase0/timing/`, `phase4/judge14.md`): time from go to the last exit, median of two runs.

  | Setting (2500_4, rt 250, 9 passes) | Phase 0 base, A-A | Floor | Phase 4 base | Phase 4 new | New against base | Exits' spread, base / new (s) |
  | --- | --- | --- | --- | --- | --- | --- |
  | bt 64 graph 1 x 30 | 12.822 s, 0.16 % | 2 % | 12.808 s | 12.067 s | -5.79 % | 0 / 0 |
  | bt 64 graph 3 x 10 | 13.466 s, 0.42 % | 2 % | 13.433 s | 12.553 s | -6.55 % | 0.25, 2.17 / 0.25, 2.93 |
  | bt 64 metal 1 x 30 | 7.917 s, 0.48 % | 2 % | 7.902 s | 7.151 s | -9.50 % | 0 / 0 |
  | bt 64 metal 3 x 10 | 18.380 s, 17.37 % | 34.73 % | 15.397 s | 7.648 s | -50.33 % | 0.13, 0.25 / 0.96, 1.75 |
  | bt 16 graph 1 x 30 | 18.008 s, 0.06 % | 2 % | 18.033 s | 17.299 s | -4.07 % | 0 / 0 |
  | bt 16 graph 3 x 10 | 17.551 s, 0.30 % | 2 % | 17.544 s | 16.777 s | -4.37 % | 1.67, 7.87 / 8.28, 8.48 |
  | bt 16 metal 1 x 30 | 14.657 s, 0.13 % | 2 % | 14.587 s | 13.893 s | -4.75 % | 0 / 0 |
  | bt 16 metal 3 x 10 | 14.184 s, 0.22 % | 2 % | 14.161 s | 13.296 s | -6.11 % | 2.32, 6.25 / 6.80, 6.71 |
  | the four 6 x 5 settings | not_run | | not_run | not_run | | |

  Footprint at one process (base / new): 2.081e10 / 1.883e10 B (bt 64 graph), 2.725e10 / 2.527e10 (bt 64 metal);
  MLX peak 1.026e10 / 0.989e10 B (bt 64 graph). SIMPLE's own block kernel went from 4.7 / 4.9 / 5.1 to 4.3 / 4.6 /
  5.0 thread-microseconds per pair on an M2 Ultra with its commit (*from its commit message*; context only).
- **Last gates** (Phase 5, `phase5/gates.log`): Debug and Release from scratch with `MLXF_WERROR`, 0 warnings;
  the Release fast gate 10 of 10 (10.37 to 11.18 s against the bound 38.74 s, *measured*); `scripts/check_tree.sh`,
  `scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec` (the host table equal to the executable's, 135
  lines), `scripts/check_install.sh` and `scripts/release_gate.sh --allow-dirty` ("RELEASE GATE PASSED:
  6a1a03e-dirty", Debug and Release, 77 s) pass; the unit areas at their counts (`phase5/run_units.log`).

## Left open for the maintainer

- **The reserved readings:** whether the miniature's memo now reads like SIMPLE's for the integration.
- **Decision 17's list: the sections of K3 to K7 that cite the old layout,** for their revision after 2f (line
  numbers of the drafts as they stand):
  - **K3** (`mlxf_kernel_k3.md`): the pin `d354efee2` (lines 6 and 114); "What the check found" on SIMPLE's
    `simple_eul_prob_tab_neigh.f90`, which `23eb95cc2` (no `block_memo`, the banks' shape) and `c1f255d20`
    (`prob_neigh_mode=geom`, 179 lines) changed; "The queue" (line 174: the dummy lists of `score_block_posterior`,
    whose banks are now `(2nk, pftsz+1, nb)` particle terms); decision 20 (line 458: the dense route's digests,
    now with the tiles made by `memoize_refs` and the driver refusing untiled references); "What the check found"
    on `polarft_workspace_submit` (lines 78 to 81: it now uploads the calculator's particle terms).
  - **K4** (`mlxf_kernel_k4.md`): the pin (lines 6, 66, 91, 614, 626); "What the check found" (lines 155 to 158:
    `new_shiftmap_mlx` hands one parity's `ft_ref_terms`, and `self%refs` holds the conjugated memo, not `ft_ref2`
    and `conjg(ft_ref)`); decision 5 and its memory paragraph of the maps' tables (lines 308 to 312: `conjg(ft_ref)`
    and `ft_ref2` made in `prepare_maps`, now rows nk+1.. and the conjugate of rows 1.. of the memo); the gather
    from `self%refs` (line 654); the maps' reference power keeps the toy's order, SIMPLE's changed (families note).
  - **K7** (`mlxf_kernel_k7.md`): the pin (lines 7, 43, 501, 516); "What it mirrors" (line 47: `memoize_ref_bins`,
    retired); the tile layout of `polarft_workspace_submit` (line 80: rows `ft_ref2` and `conjg(ft_ref)`, now the
    conjugated memo; lines 90 and 452); decision 6 (lines 187 to 189: the cc tiles at `memoize_ref_bins`, now at
    `memoize_refs`); Phase 2's first step (line 547) and its file-table row of the memo files (line 622); SIMPLE's
    `cc_sums` lost `l_conj` and its per-pair kernels moved to `term_sums` in `23eb95cc2`, which K7 must read at
    the new pin.
  - **K5** (`mlxf_kernel_k5.md`, lines 6 and 558) and **K6** (`mlxf_kernel_k6.md`, lines 6, 63 and 611): their pin
    only.
- **Not done here** (the plan's section 4): the cc objective and `ft_ptcl_terms` (K7), the maps' arithmetic (K4),
  `eul_prob_tab_neigh` (K3).

## Commit message

```
Polar toys on SIMPLE's memo layout (run mlxf_toy_layout, roadmap rank 2e)

The toy polarft_calc holds SIMPLE's one reference memo ft_ref_terms
(2nk, pftsz+1, nrefs, 2) and the particle terms ft_ptcl_wterms, read in
place by the host kernel and uploaded by the device; memoize_ref_bins and
the bin-major copy are retired and memoize_refs makes the device tiles
(kill_ref_tiles, ref_tiles_current); the device route keeps one memo
memo_terms; the shift maps read the memo's rows; seed banks are particle
terms made by shifted_ptcl_terms. The tiles are packed on the host
straight from the memo (decision 6's measured fallback). The mirror
ledger is pinned at SIMPLE 28c753993 and every mirrored name was found
there; the families note's list of differences follows the layout.

Nothing moved: the 364-line identity set equals the base byte for byte;
unit_kernels 1,953 (projector_chain -8 with the retired stage,
polarft_calc +6 refusals). The dense benchmark is 4 to 10 % shorter from
go to the last exit at every split the guard runs, each part holding
2.0e9 B less. No file under src/core or src/defs changed.

New file: doc/implementation_notes/completed/mlxf_toy_layout_report.md
```
