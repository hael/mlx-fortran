# Report of run `mlxf_kernel_forms`: the review against mlx3D, and the ways of writing a kernel measured (roadmap rank 2f)

Plan: [`mlxf_kernel_forms.md`](../planned/mlxf_kernel_forms.md) (its Progress holds the detail, phase by phase). Run on
the M5 Ultra, 2026-11-26, unattended, from base `bb59c21` (run `mlxf_toy_layout`'s result), in a copy of the
checkout; nothing committed. No ruling. Evidence paths are under the run's `scratch/keep/phaseN/`; the diffs are the
run's `review/phase_N.diff`. MLX 0.32.4, mlx-c 0.8.0, Homebrew GCC 16.2.

## What was learned

The verdict rule (decision 3): ratio = current time over alternative time, median of five interleaved pairs of
medians of five; **preferred** at 1.30 with four of five at or above it, **equivalent** within 0.95 to 1.05,
inconclusive inside twice the A-A floor or when that floor exceeds 10 %. Every alternative was checked against the
current form before it was timed (decision 5), every gate failed on a planted violation (one could not, below).

| Suite | Question | Result (*measured*, two invocations) | Verdict |
| --- | --- | --- | --- |
| `probe` | Do threadgroup memory and SIMD-group functions work through our wrapper? (Apple question 26) | exact group sums for 32 to 1,024 threads with barriers, wrong from 256 up without them; `simd_sum`, `simd_min`, `simd_prefix_inclusive_sum`, `simd_shuffle` and the lane attributes exact; a fixed tree bit-repeatable over processes; arrays up to 32,768 B, 65,536 B refused with status 1 | available, no suite stopped |
| `tail` | K1's tail: one thread per pair (T0, the kernel K1 kept) against a SIMD group per pair (T1) and a plain sum (T2) | T0/T1 **3.28 / 3.28**, 5 of 5; first minima exact, draws within K1's 5 per 64,000; T0/T1 from go to the last exit at 6 processes 1.84 / 1.80; T0/T2 1.028 | **T1 preferred**; T2 equivalent (compensation free) |
| `reduce` | K5's shape (500 evaluations, 23 sums, 6,144 terms): serial (R0), compensated (R1), threadgroup tree with `simd_sum` (R2), MLX's graph `sum` (R3) | R0/R2 **8.13 / 8.08**; R0/R3 2.95 / 2.87; R0/R1 0.86; R3/R2 2.31 / 2.35 (its own A-A floor 10 to 19 %) | **R2 preferred**; R1 worse (but 50 to 90 times more accurate); R3/R2 inconclusive, 2.8 through R0 |
| `sizes` | Sizes as template integers (G0, today's) or in an int32 input (G1), on K2's gather and the insertion kernel | bit for bit equal; per launch 1.009 / 0.994 (gather) and 1.000 / 1.003 (insertion); a new value 42.7 / 42.0 ms as a template, 3.05 / 2.62 ms as an input | **equivalent** per launch (one gather run inconclusive by its 5 % floor); 14 to 16 times cheaper per new value |
| `select` | K7's K best of 10,000 by 1,024 at K = 3 and 10: K rounds of `maxloc` (E0), `argpartition` with tie repair (E1), a thread per particle (E2), a SIMD group per particle (E3) | all exact; E0/E3 **2.10 / 2.02** (K = 3), **4.06 / 4.12** (K = 10); E2/E3 3.5 to 4.0; E0/E1 0.16 / 0.39; E0/E2 0.51 (K = 3), 1.17 (K = 10) | **E3 preferred**; E1 worse; E1 *without* repair also exact (below) |
| `insert` | K6 at small n: the probe's atomic push (D0) against a pull with one thread per voxel (D1) and with each plane's patch staged (D2) | D1 within the push's own noise (1.3 to 2.0e-06 against `FORMS_INSERT_TOL` 3.6e-06), D2 = D1 bit for bit, both repeatable; D0/D1 0.068 (n = 64), 0.18 (n = 96); D2 9 to 47 % slower than D1; extrapolated factor at n = 160 1.66 (*derived*) | **D1 worse** at small n; staging worse |
| `waits` | K3's two-stage pass: a wait per tile (F0) against a persistent capacity with a sentinel and one wait per pass (F1) | bit for bit equal; F0/F1 **2.42 / 2.38**; a wait inside the busy queue 0.34 ms (*derived*) | **F1 preferred** |

**Corrections to the lessons note** (written in place, [`mlxf_mlx3d_lessons.md`](../planned/mlxf_mlx3d_lessons.md)):
mlx3D uses no SIMD-group function, so it is evidence for threadgroup memory only; P3 (no waits) is the viewer's path,
the training path waits mid-pass; P2 relies on a stable sort that MLX does not document; a negative result the note
omitted (`nn/fused_mlp.py`: a per-thread fused MLP is slower than MLX's matrix products); K5 reduces 23 sums, not
21; MLX's kernel library is keyed by source, never by launch configuration (read, then measured).

**Hypotheses refuted:** a new size in an input costs 2.6 to 3.1 ms, not at most 1 ms (decision 10); the pull is
14.5 times slower than the push at n = 64, not at most 3 (decision 12); staging does not beat the plain pull
(decision 12); E2 does not beat E0 at K = 10 (decision 11); R1 is 14 % slower than R0, not equivalent (decision 9);
and `argpartition` without the repair passes the exact gate, because MLX 0.32.4 resolved every planted boundary tie
to the lower index (decision 11; new Apple question 36).

**K1's tail ceiling on 2e's base reaches 1.30** (1.32 by the plan's method, 1.45 by the profile's share, *derived*,
Phase 0): with T1 3.3 times faster, a K1 driver change could pass the 30 % rule. Decision 3 keeps that for the K
plans; no toy default changed.

## What changed, phase by phase

| Phase | Diff | Files | What |
| --- | --- | --- | --- |
| 0 | `review/phase_0.diff` | 1 | the base measured: builds, counts, the 364-line identity set twice, the ceilings re-derived, the queue re-checked, K5's and K3's shapes, the frozen block |
| 1 | `review/phase_1.diff` | 13 | `tail_spec` (interface in `mlxf_toy_polarft_workspace`), `gather_spec`, `probe_spec` public with their mirror lines; the bench and its `BENCHES` entry; suite `probe`; `digest_bits` moved to `mlxf_test_utils`; the map, `bench.inf` |
| 2 | `review/phase_2.diff` | 8 | suites `tail` and `reduce`, the timing protocol, the sources module; `FORMS_REDUCE_TOL`; `wait_for_go_file` moved to `mlxf_test_utils` |
| 3 | `review/phase_3.diff` | 5 | suites `sizes` and `select`; `probe_case` moved to `mlxf_test_defs`, `seeded_case` and `window_coefficients` public |
| 4 | `review/phase_4.diff` | 4 | suites `insert` and `waits`; `FORMS_INSERT_TOL` |
| 5 | `review/phase_5.diff` | 9 | the lessons note, Apple questions 26 and 36, binding contract section 12, test policy paragraph, roadmap row 2f, history, notes index, this report, the plan's status |

The run changed 20 tracked files and added 3: 13 Fortran and script files under `src/test/` and `scripts/` (no
file under `src/core/` or `src/defs/`; no toy's source, launch or default), `doc/code_base_map.md`, and seven
documents.

## Decisions taken under delegation

Each is recorded, with its reason, in the plan's Progress of the phase named (numbers as there).

1. (Phase 0) The toys' digest lines are run 2e's 364-line identity set, by its script with only paths changed.
2. (0) K1's ceiling reported by two derivations; no new free-tail run.
3. (0) New Apple questions numbered from 36 (32 to 35 existed).
4. (0) `reduce` at K5's round: 500 evaluations, 23 sums, 6,144 terms (the draft's numbers, not the guessed 2,000).
5. (0) `waits`' tile at K3's real product (183 bins of 64 by 244 by 500), not the plan's misread 250 by 366 by 64.
6. (1) `probe_spec` alone made public, its record left for the phase that needs it (rule `defs`).
7. (1) `digest_bits` moved to `mlxf_test_utils` instead of a third copy (fix as you go).
8. (1) The probe's parts are a key `form=`; part (d) runs last.
9. (1) `bench.inf` names every bench, `blas` included.
10. (1) The test policy's paragraph written in Phase 5 (its file-table row).
11. (1) No `NAMED_ONLY` entry (the registry does not require it).
12. (2) The tail's seeded rows made by the bench (K1's P10 source is not in the record).
13. (2) The tail's first-minimum gate run at u = 0 and u = 2: a plant showed the first form could not fail.
14. (2) `RUN_PARTS_BENCH=bench_kernel_forms`, not `kernel_forms` (the script runs `test=$RUN_PARTS_BENCH`).
15. (2) T1's first index is the least rotation among the minimal lanes.
16. (2) T1's W from plain lane partials.
17. (2) `reduce` times R0 as current and adds an A-A control on R3 for R3/R2; stop 6 applied to that verdict only.
18. (2) The reduction's terms are products of two inputs read in the kernel; the last 8 terms zero.
19. (2) `wait_for_go_file` moved to `mlxf_test_utils` instead of a third copy.
20. (2) The 3- and 6-process series run twice (the first had no TSV header); the second is the record.
21. (2) The sources moved to `mlxf_bench_kernel_forms_src.f90`; the main file keeps the suites' logic (1,937 lines at the end).
22. (3) The insertion's bit-for-bit check on a collision-free plane (the current kernel's atomics vary).
23. (3) `probe_case` moved and `seeded_case`, `window_coefficients` public in Phase 3, not 4.
24. (3) A new value's compile cost is the first evaluation less the second, on disjoint value sets per run.
25. (3) `select` adds an A-A control on E2 for E2/E3.
26. (3) G1 derived at run time from the toy's spec (`sizes_in_input`).
27. (3) Identifiers `t`, `p`, `q` renamed in the bench (rule `ctorexpr` reads names file-wide).
28. (3) `sizes`' seed applies to the gather's data only.
29. (4) Each seed of `insert` is one batch of a 1,500-plane `seeded_case`.
30. (4) The sums of |terms| scaling `FORMS_INSERT_TOL` come from D1 on the data's magnitudes.
31. (4) D1 and D2 read sizes from an int32 input; plane reach 9 voxels; D2's patch 24 by 24.
32. (4) `insert` adds an A-A control on D1 for D1/D2; stop 6 applied to its one verdict above 10 %.
33. (4) The waits' stage 2 sums each listed pair's two row halves over the bins through the compacted list.
34. (5) The lessons note's section "What was measured" holds seven suites, not six (`probe` included); its
    proposed decisions became section 8.

## Deviations from the plan, and files outside the original table

- **Files added to the file table before their edit:** `mlxf_test_utils.f90` (Phases 1, 2), `mlxf_bench_polar_table.f90`
  and `mlxf_bench_projector.f90` (1, 2: the two helpers' copies deleted), `doc/code_base_map.md` (1 to 4: the static
  gate requires it). Rows extended: `mlxf_bench_insert_probe.f90` (3), `mlxf_test_defs.f90` (3).
- **Gate amended before its judged runs** (decision 13): the tail's first-minimum check made stricter after a plant
  passed it; the first agreement runs (u = 0 only) passed and are kept.
- **A plant that could not fail:** "E1 without the repair" (decision 15): MLX's `argpartition` already keeps the lower
  index; the exact gate it shares is failed by the E2 plant. Recorded, not replaced (decision 15 names a replacement
  for R2 only).
- **Verdicts made inconclusive by stop 6** (an A-A floor above 10 %): R3/R2 (both invocations) and D1/D2 at n = 96
  (one invocation), each on the extra A-A control this run added for that pair; no rerun for a result.
- **The extrapolation's frozen bounds** (decision 12) do not contain the measured extrapolation: the push grows as
  n^3 and the pull far slower than n^3 between 64 and 96. Read, not judged.
- **Timing windows of the tail's 3- and 6-process rows** are short (0.05 to 0.22 s from go to the last exit).
- **Expected effects that did not occur:** G1 under 1 ms per new value; the pull within 3 times the push; staging
  faster; E2 faster than E0 at K = 10; R1 as fast as R0; E1 without repair failing.

## Evidence against the baseline

- **Identity:** the 364-line identity set (SHA-256 `e2d65e8861d23ef7d731960e17269c6ecaed23fc46d735a1dc37f0bb4d33dba5`)
  equal to 2e's base copy in Phase 0 (twice) and after Phases 1, 2, 3, 4 and 5 (`phaseN/identity/identity.txt`).
- **Counts:** every unit area at Phase 0's count in every phase, both builds (kernels 1,953; `unit_core` 214 to 216,
  the allocator's range on record).
- **Builds:** every phase ended with Debug and Release from scratch with `MLXF_WERROR=ON`, 0 compiler warnings, the
  static gate passing, the fast gate 13 of 13; both formatters on every touched Fortran file.
- **Plants** (each in a patched copy built apart, logs under `phaseN/plants/`): the probe's missing barrier, the two
  mirror lines, the `BENCHES` entry, T1 skipping the last rotation, T1's inverted first index, R2 without its
  barrier, G1 with two sizes swapped, E2 with `>=`, D1 without the conjugate pixels, D2 without its second barrier,
  F1's sentinel mask one short: all fail; E1 without the repair could not fail (above).
- **Last gates** (Phase 5, `phase5/gates.log`): Debug and Release from scratch, 0 warnings; the Release fast gate 10
  of 10 (10.44 to 10.51 s against the bound 38.74 s); `scripts/check_tree.sh`, `scripts/check_embed.sh`,
  `scripts/check_toy_offstate.sh --exec` (135 lines equal), `scripts/check_install.sh` and
  `scripts/release_gate.sh --allow-dirty` ("RELEASE GATE PASSED: bb59c21-dirty", 79 s) pass.
- **Loads:** every timed step waited for a one-minute load of at most 4; `uptime` before and after is beside each log.

## What the K plans take

| Result | K plan and decision that change | Found |
| --- | --- | --- |
| T1 preferred / not | K7 decision 16 (F1 a SIMD group per pair, or as written); K4 decision 9 (the reductions' launch shape) | **T1 preferred (3.3)**: K7's pair stage and K4's per-pair reductions are written a SIMD group per pair; with K1's ceiling at 1.32 to 1.45, a K plan may also propose the faster tail for K1's driver on its own measurement |
| T2 equivalent / faster | the house rule on compensated sums; K5's and K6's accumulation (K6 decision 19's tolerance basis) | **equivalent (2.8 % faster)**: compensated sums stay the default where they are free; in a reduction-bound kernel they cost 14 % (R1) and buy 50 to 90 times the accuracy, a choice for each plan's tolerance |
| R2 preferred over R0, R3 | K5's fused form and its ceiling order; the note's section 4 (K5) | **R2 preferred over R0 (8.1)**, about 2.8 over R3 (verdict inconclusive by its floor): K5's fused objective is the threadgroup tree; R3 is not within 1.30 of R2 |
| G1 equivalent | K3 decision 10 (candidate B's sizes; "capacities are powers of two" becomes unnecessary); K6 decision 28; the `mlxf-binding` skill line | **equivalent per launch, 3 ms against 42 ms per new value**: K3's candidate B and K6 read sizes from an input; powers-of-two capacities are not needed to bound compiles |
| E2 or E3 preferred, E1 repaired or not | K7 decisions 14 and 15 (the order of forms, whether E1 is measured again) | **E3 preferred (2.0 to 4.1 over E0)**: K7 builds E3 first; E1 is not measured again; the repair stays (stability is not documented) |
| D1/D0 and D2/D1 | K6 decisions 8, 12, 13 (order of the forms, the plane walk, staging as a variant) | **D1/D0 = 14.5 (n = 64), 5.6 (n = 96), 1.7 extrapolated to 160; D2 slower than D1**: the atomic push stays K6's fast form, the pull its deterministic form to measure at n = 160, staging dropped |
| F1 preferred | K3 decision 10 (candidate B), K6's sorted form, the note's P3 | **F1 preferred (2.4)**: K3's candidate B and K6's sorted form size their buffers by a persistent capacity with a sentinel and one wait per pass |
| probe refused or wrong | K7 decision 15 (F3 not built), K6 staging, K5's tree: each falls back to its graph or per-thread form | **nothing refused**: every form stays available, limit 32,768 B of threadgroup memory |

## Left open for the maintainer

- **Skill proposals (not applied):**
  - `mlxf-binding`: "Sizes that change per call are an int32 input of fewer than 8 elements (constant space);
    templates only for constants of a run. Per launch the two are equal; a new template value costs a new Metal
    source (about 42 ms), a new value in an input a new object (about 3 ms)."
  - `mlxf-binding`: "A kernel that reduces to one output per item (a row, a pair, a column) gives each item a SIMD
    group or a threadgroup, not one thread: 3.3 (tail), 8.1 (reduction) and 2 to 4 (selection) times faster here;
    the per-thread form stays only where the items are many and the reduction short."
  - `mlxf-modern-fortran`, traps: "In an OpenMP build every local is recursive: an intrinsic such as `reshape` with a
    constant target shape of tens of MB puts a temporary of that size on the stack and crashes; give the shape at
    run time." And: "rule `ctorexpr` reads names file-wide: a real array that shares a name with a handle elsewhere
    in the file is flagged."
  - `references/testing.md`: "A plant must exercise the rule it targets: a gate whose expected value the code reaches
    by another path (the draw reaching the first minimum by itself) can pass a broken rule."
- **The note's proposals still open:** proposal 2 (sorted `gather_mm` for K3) and proposal 5 (`apply` with its own
  launch, now with a measured 3 ms saving per configuration).
- **Apple questions:** 26 updated with the probe's numbers (still asks whether MLX supports threadgroup memory in
  `metal_kernel`); 36 new (is `argpartition`/`argsort` stable on the GPU?). Neither is sent.
- **K1's tail:** its ceiling now reaches 1.30 and T1 is 3.3 times faster; whether a K plan proposes changing K1's
  default is the maintainer's call (decision 3 left it to the K plans).
- The plan moves to `completed/` after the maintainer's read.

## Commit message

```
Kernel forms measured against the toys' kernels (run mlxf_kernel_forms, roadmap rank 2f)

A named-only benchmark, bench_kernel_forms, builds the toys' current
kernels from their own spec functions (tail_spec, gather_spec and
probe_spec made public, mirror lines added) and sets other ways of
writing them beside them on the GPU, each checked against the current
form before it is timed in interleaved pairs after an A-A control.
Suites: probe (threadgroup memory and SIMD-group functions through the
wrapper: exact, repeatable, 32,768 B), tail (a SIMD group per pair 3.3
times faster than K1's kernel), reduce (a threadgroup tree 8.1 times
faster than one thread per evaluation), sizes (an int32 input equal per
launch, 3 ms against 42 ms per new value), select (a SIMD group per
particle 2 to 4 times faster than K rounds of maxloc), insert (the pull
exact but 6 to 15 times slower than the atomic push at small n) and
waits (one wait per pass 2.4 times faster than one per tile).
FORMS_REDUCE_TOL and FORMS_INSERT_TOL frozen on seed 1. digest_bits and
wait_for_go_file move to mlxf_test_utils; probe_case to mlxf_test_defs.
The lessons note is revised, Apple question 26 updated and 36 added.

Nothing moved: the 364-line identity set equals the base byte for byte
after every phase and every unit area keeps its count. No file under
src/core or src/defs changed; no toy default changed.

New files:
src/test/bench/mlxf_bench_kernel_forms.f90
src/test/bench/mlxf_bench_kernel_forms_src.f90
doc/implementation_notes/completed/mlxf_kernel_forms_report.md
```
