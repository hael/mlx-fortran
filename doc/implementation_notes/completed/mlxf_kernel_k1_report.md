# Report: K1, the fused tail of the dense score (run `mlxf_kernel_k1`), kept

**Addendum, ruling R2 (2026-11-25): kept.** The maintainer: "The fused form is fine. Memory can be increased. WE can buy machines with more memory to run more parts. I am not locked into this little testing machine", and "We can essentially control memory usage in SIMPLE by dialing down the number of parts". The fused form stays selectable with the default
`graph` (decision 20), and Phase 4's documents are updated (the plan's Progress, "Ruling R2 and Phase 4"). The
deletion below is not carried out.

**Addendum, ruling R1 (2026-11-25, 08:52 to 09:20).** R1 took option 2 of section 6: re-take `2500_4` at three
processes, five pairs, a row valid only if its parts' exit spread is at most the median of its parts' median
passes, at most three attempts per row, no valid attempt in three a stop. The first graph row failed three times
(spreads 5.79, 5.83 and 5.09 s against median passes of 0.79 to 0.80 s: one process finished 5 to 6 s ahead of
the other two each time, the time from go to the last exit 13.50 to 13.56 s as in Phase 0). **Stopped by R1,
item 5: the protocol cannot resolve that split in the machine's present state.** Under the same test Phase 3's
five graph rows are all invalid and Phase 0's seven all valid. A script defect let the first pass of the re-take
run all ten rows without the test; they are set aside, uncounted, and all ten fail the test too (reported only:
their times from go to the last exit give the fused form 1.52 to 1.59). The verdict stays open: met at `2500_1`
with six processes, unresolved at `2500_4` with three. Decision 20 and Phase 4 are not carried out; the code
stays in the working tree with the default form `graph`. H3 stands: the fused form raises a process's MLX peak by
about 6e9 B. Ruling needed: delete; keep on `2500_1` alone; or a measure of the shared split that does not rest
on per-process passes, frozen before its rows. Details: the plan's Progress, "Ruling R1 and the re-take".

Run on the M5 Ultra on 2026-11-25, 06:43 to 09:00, in the session, in a scratch copy of the maintainer's tree:
base `1e0ae97` plus the maintainer's uncommitted working tree of 2026-11-25 (44 lines of `git status`;
checksums in the run's `scratch/keep/phase0/base_checksums.txt`). Plan:
[`mlxf_kernel_k1.md`](../planned/mlxf_kernel_k1.md), Phases 0 to 3 run, Phase 4 replaced by this record because
the run stopped at decision 18's verdict. SIMPLE read at `d354efee2`; the rulings file stayed empty. Nothing is
committed. Evidence: `/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k1_work/scratch/keep/phase{0,1,2,3}/`
(below `keep/`); the journal is the run's `state/journal.md`.

## 1. What was learned

**The run stopped before the verdict was carried out; a ruling is needed.** By decision 18's letter the kernel
is deleted: at the judged split `2500_4` with three processes the median of the five fused-over-graph ratios is
1.246 (2 of 5 at or above 1.30), just below the 1.25 to 1.35 band that would have added five pairs. At the other
judged split, `2500_1` with six processes, the rule is met (median 1.742, 5 of 5). The deciding ratios rest on
graph rows whose summed median rate (1.73e7 to 2.48e7) exceeds what one GPU delivers to one process (1.77e7):
the three parts drifted apart (one exited 2 to 3.3 s after the others, against 0.35 s in Phase 0), so the sum of
per-process medians counted shared GPU time more than once. Decision 15's median assumed such passes drop out;
with 9 passes and a lag of two to three passes they do not. The graph form's time from go to the last exit was
unchanged (13.47 to 13.65 s, Phase 0: 13.46 to 13.59 s). A diagnostic graph-only row afterwards drifted again
(summed median 2.90e7): the machine's present state (12e9 B more free memory than in Phase 0), not the
interleaving with the fused form. The run therefore keeps the code and asks for a ruling (section 6).

**The fused tail is accurate and repeatable.**
| Against | Fixture (GPU; 96 pairs per seed) | Block (GPU; 64,000 pairs) |
| --- | --- | --- |
| The oracle (decision 10, bounds frozen before the plan) | seed 2: row error 2.358e-07 (bound 4.794e-07), 0 minimising rotations differing (bound 1); validity and draws hold | seed 2: 6.163e-07 (bound 1.4505e-06), 0 (bound 5) |
| The compiled form (decision 11) | seed 1 (calibration): rows 1.191e-07, 0 rotations; seeds 2 and 3: 1.192e-07 and 1.190e-07, 0 and 0 rotations | seed 1 (calibration): 6.51e-08, 1 rotation; seed 2: 6.52e-08, 2 rotations |
| Itself (decision 12) | three fills, a calculator made again, one and two slots, outer batches, the rows variant: bit for bit | the schedule identity; every bench digest equal across its runs, per part |

Frozen (*measured* then *derived*): `POLARFT_TAIL_ROW_TOL` = 2.3816146966584994e-07 (twice seed 1's, above the
2^-23 floor), `POLARFT_TAIL_ROT_FIX` = 1, `POLARFT_TAIL_ROT_BLK` = 5, `POLARFT_TAIL_TG` = 64.

**Where its rows are steady, the fused tail makes the canonical driver 1.65 to 1.80 times faster**
(*measured*, sums of the processes' median rates, interleaved pairs):

| Split | Graph | Fused | Median ratio |
| --- | --- | --- | --- |
| `2500_4`, 1 process | 1.77e7 pairs/s (pass 1.133 s) | 3.18e7 (0.628 s) | 1.804 (2 pairs) |
| `2500_4`, 3 processes (judged) | 1.73e7 to 2.48e7 (drifted; Phase 0: 1.69e7) | 2.97e7 to 3.05e7 | **1.246** (5 pairs) |
| `2500_1`, 1 process | 1.79e7 (0.280 s) | 2.96e7 (0.169 s) | 1.655 (2) |
| `2500_1`, 3 processes | 1.68e7 to 1.73e7 | 2.90e7, 2.91e7 | 1.705 (2) |
| `2500_1`, 6 processes (judged) | 1.73e7 to 1.83e7 | 3.00e7 to 3.05e7 | **1.742** (5 of 5) |

**The probe (Phase 1) settled the kernel's design in MLX 0.32.4.** One thread per pair reduces its row exactly;
the comparisons classify NaN, infinities and the limit as the graph form does; `fma` is `ieee_fma`, and the
graph form's compiled `raw * iw + 1` is not contracted (so the forms' rows differ by one unit); `metal::precise::exp`
is within 1 unit and equal to MLX's `exp`, plain `exp` in the default (safe) math mode is 62 units off; the
compensated sum is honoured; inputs of fewer than 8 elements and outputs of rank 3 work; the threadgroup does not
matter once the GPU is warm (64 kept); a new source costs 48.7 ms at its first submission; a compiled function
around the kernel gains nothing and `shapeless=.true.` refuses it ("CustomKernel cannot infer output shapes"). In
isolation the fused tail is 3.9 to 4.1 times faster per canonical tile (0.17 against 0.65 to 0.71 ms); with a
barrier after every stage it takes 0.42 s where the compiled one takes 0.94 s.

**The ceiling.** A tail that costs nothing makes the judged splits 2.98 (`2500_4`, 3) and 2.31 (`2500_1`, 6)
times faster: the compiled tail is about 0.65 s of the 1.14 s pass (H1 holds).

**H3 is refuted: the fused form raises each process's MLX peak by about 6e9 B** (10.26e9 to 16.71e9 B at
`2500_4`, 4.81e9 to 10.79e9 B at `2500_1`): a cheap tail lets the host queue more tiles ahead of the device, each
holding its products and rows. Three fused parts of `2500_4` hold 79e9 B, 0.77 of the machine, and drove its free
memory to 0.07e9 B; the guard let them run on a prediction of 81.8e9 B against a limit of 82.5e9 B. Six fused
parts of `2500_4` are predicted at 157e9 B. A queue bound (a wait every few tiles) is the obvious remedy and
belongs to K3 or K4.

**The protocol.** Phase 0's control (graph against graph, 3 pairs) was 0.0069 and 0.0063 at the judged splits,
and the median rule held there. The same rule failed in Phase 3's machine state at three processes of `2500_4`:
a control taken once does not protect a later session (section 6).

## 2. What changed, phase by phase

| Phase | What | Files |
| --- | --- | --- |
| 0 | `suite=time` reads `passes=`, writes `passes` and `wall_median_s`; `run_parts.sh` sums the median rates (`sum_median_pairs_per_s`) | 2 |
| 1 | the probes, scratch only; this note's Progress | 0 |
| 2 | the fused tail (new submodule `mlxf_toy_polarft_workspace_tail`), the form on the workspace and the calculator (`set_tail_form`), the vocabulary and constants, the suite `polarft_tail` (new tester), the GPU checks of `polarft_calc` and `eul_prob_tab` once more with the fused form, the forms' agreement on the fixture, the ledger line | 12 Fortran files and `scripts/toy_mirror.txt` |
| 3 | `tail=` in the benchmark's `accuracy`, `time` and `profile`; the estimate by form; the forms' agreement on the block; `POLARFT_TAIL_ROT_BLK` | 2 |

Counts (*measured*, Debug and Release): `unit_kernels` 1,063 to 1,281 (`polarft_calc` 107 CPU and 227 GPU = 7 + 92
per form + 36 of the forms' agreement; `eul_prob_tab` 35 per form; `polarft_tail` 6 CPU and 49 GPU); every other
area unchanged (`unit_core` 82, `unit_array` 179, `unit_ops` 2,402, `unit_linalg` 632, `unit_fft` 194,
`unit_compile` 63, `unit_fast` 94). The accuracy suite on the GPU: 76 assertions with the graph form, 98 with the
fused one. The CTest entries and their budget of 9 did not move; the Release clean build takes 15 s (16 s before).

## 3. Decisions taken under delegation

Each with its reason in the plan's Progress entry of its phase.

| Phase | Decision |
| --- | --- |
| 0 | `wall_rep1..3` are the first three passes and `wall_s` the best of all, so the row's first 28 columns keep their meaning; `sum_median_pairs_per_s` is the series table's last column; the even-count median is the mean of the middle two; decision 13's digests taken with the Phase 0 build; the baseline's best-pass rate at three processes is not comparable between runs |
| 1 | `POLARFT_TAIL_TG` = 64 (256 led only in cold rounds timed in a fixed order); `metal::precise::exp`; the first ceiling attempt void (the null build was not installed) and the ceiling run once from the start; the ceiling's guard reads copies of Phase 0's series tables; the P9 probe fixed after it read a refused apply's outputs |
| 2 | the forms' agreement on the dense fixture lives in the calculator's tester (its fixture and oracle are private there), `polarft_tail` has its own seeded data; testers pass the form as a second dummy through the fixture record; the driver's live-count check allows the two rows variants the fused workspaces keep; a refused fused form is refused where the compiled tail would be built; the two tail procedures are module procedures, not bindings (one ledger line); plant 2 is caught by the draw's 1-based conventions; two void first passes of the plants (`make` compares whole seconds) and all ten run again |
| 3 | the block's agreement runs with `tail=metal`, on the GPU only; `tail=` read by `arg_config`; the six-process `2500_4` split recorded as not run once per form; one diagnostic graph row after the verdict, kept apart; **stopped before decision 20** |

## 4. Deviations from the plan

- **Phase 4 was not run as written.** Decision 18's letter gives "deleted"; the run did not carry out decision
  20's removals, and the documents of Phase 4 (kernel families, roadmap, test policy, plans index, history,
  binding policy section 12, Apple questions) are not updated. The plan's banner says the run stopped at the
  verdict. Section 7 lists no stop for this case; the run treats it as one because the deciding rows break
  decision 15's premise and a deletion cannot be taken back by a later ruling the way a kept tree can be deleted.
- Decision 11's fixture calibration and agreement are in the calculator's tester, not in `polarft_tail`
  (section 3).
- Plant 2 fails the draw's 1-based conventions, not `test_convention` (which checks the rows' minimum).
- The ceiling and the plants each had a void first attempt (Phases 1 and 2); both are kept apart and were run
  again from the start, not repeated for a result.
- Expected and not found: H3 (the peak rises); the threadgroup mattering; padding of small inputs.
- Files outside the table: none. `test/CMakeLists.txt` and `src/test/test.inf` needed no change.

## 5. Evidence against the baseline

- **Decision 13:** the 25 digest lines (accuracy on both devices, time and profile on the GPU, time on the CPU
  device) equal the record of run `mlxf_toy_arch` in Phase 0 (twice), after Phase 2 and after Phase 3; the
  three-part digests in every graph row; the new `2500_1` digests frozen in Phase 0 and equal in every row.
- **The off-state invariant:** with the default form no kernel object exists (`polarft_tail`: 4 live handles for
  both parities' bins, the plant that makes `metal` the default fails it and moves the `time` digest to
  `C65F8ECED8D9B855`).
- **Plants:** ten on the fixture, three on the block, each failing with the named assertion, each file restored to
  its checksum (`keep/phase2/plants/`, `keep/phase3/plants/`).
- **Builds:** every phase ended with Debug and Release from scratch with `MLXF_WERROR=ON`, 0 warnings, fast gate 9
  of 9, `scripts/check_tree.sh` passing, both formatters run on every touched Fortran file.
- **Baseline:** 6.048 and 6.050 s at one process, 6.564 and 6.482 s at three (report of `mlxf_toy_arch`: 6.00 to
  6.09 and 6.36 to 6.71 s); 20.81e9 and 60.32e9 B.
- **Suites' elapsed times** (Release, both devices): `polarft_calc` 0.32 s, `eul_prob_tab` 0.10 s, `polarft_tail`
  0.07 s.

## 6. Left open for the maintainer

**The ruling the run stops on** (plan, Progress of Phase 3):
1. delete by the letter (decision 20 and the record of a negative result);
2. **recommended:** re-take the judged split `2500_4` at three processes once, five interleaved pairs, with a row
   validity test frozen before it (a row counts only if its parts exit within one median pass of each other; a
   row that fails is repeated as a discarded row is), the `2500_1` verdict standing; or
3. judge that split on the time from go to the last exit (reported: 1.56 to 1.58 in three pairs, 1.05 and 0.87
   in two that ran with the machine's memory exhausted).

**Reported, not gated.** The fused form's MLX peak (+6e9 B per process) and the summed footprint of three fused
parts (79e9 B; the roadmap's second condition met); the roadmap's first condition not met at any split; the
time from go to the last exit; the profiles' stages.

**Proposals, not edited.**
- `scripts/run_parts.sh` could report the spread of its parts' exits and mark a row whose spread exceeds a pass,
  so that the median rule's premise is checked where it is used.
- The binding policy's section 12: an output of rank 3 works (P6), and a compiled function holding a kernel
  refuses `shapeless=.true.` at the traced shape with a status (P9); Apple question 21 can record that kernels
  built through mlx-c run in the safe math mode, which honours compensated sums and leaves plain `exp` 62 units
  from the correctly rounded value. A question on output shapes for shapeless compilation of custom kernels.
- `CLAUDE.md` and the skills: none from this run beyond the `make` second-granularity trap for planted builds
  (the agent-runs skill could say: wait a second around an edit before an incremental rebuild).

## 7. A commit message

```
K1: the fused tail of the dense score as a Metal kernel (stopped at the verdict)

The polar toy's dense score gains a second form of its tail, the distances
and the posterior draw of a tile, as one custom Metal kernel per tile
(draw_posterior_rvec: one thread per pair, three sweeps of its row, a
compensated sum, fma and precise exp), beside the compiled graph form,
which stays the reference, the CPU path and the default. The form is set
by polarft_calc%set_tail_form (an addition in scripts/toy_mirror.txt) and
the benchmark's tail= key; with the default form no kernel is built and
the 25 digests of the graph form are unchanged.

New files: src/test/mlxf_toy_polarft_workspace_tail.f90 (the kernel's
source, objects and application), src/test/mlxf_toy_polarft_tail_tester.f90
(suite polarft_tail), doc/implementation_notes/completed/
mlxf_kernel_k1_report.md (the report).

The fused form meets the oracle's frozen bounds, agrees with the compiled
form within one unit (ROW_TOL 2.38e-7; 0 of 288 fixture rotations, 2 of
64,000 on the block) and is repeatable bit for bit. polarft_calc and
eul_prob_tab run their GPU checks with both forms; unit_kernels 1,063 to
1,281. suite=time gains passes= and the median columns; run_parts.sh sums
the median rates.

Timed on the M5 Ultra: 1.80 and 1.65 times the graph form's rate at one
process, 1.74 at six processes of 2500_1 (5 of 5 pairs above 1.30); at
three processes of 2500_4 the median ratio is 1.246 against graph rows
whose parts drifted apart. The run stopped before decision 20 for a
ruling. The fused form raises a process's MLX peak by about 6e9 B.

Run mlxf_kernel_k1; plan doc/implementation_notes/planned/mlxf_kernel_k1.md.
```
