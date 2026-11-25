# Report: the polar toy as a miniature of SIMPLE's `polarft_calc` (run `mlxf_toy_arch`)

Run on the M5 Ultra on 2026-11-24, 19:23 to 22:30, from `441873c`, unattended, Phases 0 to 4 of
[`mlxf_toy_architecture.md`](../planned/mlxf_toy_architecture.md). Nothing is committed: the change is the
working tree, and the driver's diffs are `/Users/hael/agent_runs/mlxf_toy_arch/review/phase_<N>.diff` (and
`full_after_<N>.diff`). The plan's Progress section holds the detail of each phase; evidence is under
`/Users/hael/agent_runs/mlxf_toy_arch/scratch/keep/phase<N>/`. SIMPLE was read at `d354efee2`. The rulings
file of the run stayed empty.

## 1. What was learned

**The toy now reads as SIMPLE's code does, and computes what it computed before.** A tester or the benchmark
makes a `polarft_calc`, sets references and particles one at a time, calls `memoize_refs`, `memoize_ptcls` and
`memoize_ref_bins`, makes an `eul_prob_tab` with `new_pipeline` and calls `fill_tab_range`. All 24 digest
lines of the base (distances, rotations, map modes, losses and widths, on the GPU and on the CPU device) came
back bit for bit after every phase.

**The seam, for the read of the architecture** (case `2500_4`: 10,000 references per half, 2,000 particles,
pftsz 182, 61 shells, tile plan 64 by 250):

| Question | Answer | Origin |
| --- | --- | --- |
| Who owns the device state | `polarft_calc%ws`, one `polarft_workspace` per reference parity, made in `new`, released in `kill`. The driver and the fixtures hold no MLX handle | the code; rule `mirror` lists every binding |
| What is resident, and for how long | The reference tiles of both parities, 7.14e9 B, from `memoize_ref_bins` to `kill_ref_bins` or `kill`: one iteration of a part process. A shift map adds 2.63e9 B from `new_shiftmap` or `setup_shiftmaps` to `kill_shiftmap` | *derived* (tiles); *measured* (9.77e9 B active with a map) |
| What a block in flight adds | The MLX peak is 10.26e9 B while a half of 1,000 particles is scored; MLX keeps 3.28e9 B in its cache afterwards. With a map: peaks of 10.74e9 B (window) and 13.15e9 B (screen) | *measured* |
| What stays on the host | The memos of the references, 3.57e9 B, and of the particles, 0.36e9 B. No raw section stays | *derived* |
| Where the host waits | `memoize_ref_bins` and `new_shiftmap` (the resident data are evaluated); `collect_block` (the entries are copied out; `score_block_posterior` is a submission and its collection); `shiftmap_mode`, once per tile of particles. `submit_block` returns while the device works | the code |
| What a part process holds | 20.81e9 B of peak footprint for all the particles, 20.11e9 B for a third of them: each part holds all the references | *measured* |

**How 1, 3 and 6 part processes shared the GPU and the memory** (the dense driver, GPU, full precision; two
runs before on the base and two after; the time is from go to the last exit and holds the upload of the
references, a warm-up pass and three timed passes):

| Split | Before: time, s | After: time, s | Before: summed peak footprint, B | After | Total rate over one process's, before; after |
| --- | --- | --- | --- | --- | --- |
| 1 process, 30 threads | 6.053, 6.089 | 6.003, 5.997 | 21.130e9, 21.130e9 | 20.813e9, 20.813e9 | 1 |
| 3 processes, 10 threads | 6.707, 6.417 | 6.362, 6.421 | 60.734e9, 60.734e9 | 60.321e9, 60.320e9 | 0.986, 1.018; 0.972, 1.030 |
| 6 processes, 5 threads | not run | not run | predicted 120.6e9 | predicted 119.6e9 | not measured |

- **Three processes share the GPU without loss:** their summed rate is that of one process (1.72e7 to 1.82e7
  pairs per second against 1.76e7), and the time from go grows by 0.36 to 0.42 s. The roadmap's first
  condition (total rate below 0.8 of one process's) is **not met**.
- **Memory is the limit, not the GPU.** Three processes hold 60.3e9 B, above half the machine: the roadmap's
  second condition (summed footprint above 51.5e9 B) **is met**, before and after. The machine's free memory
  fell to 0.5e9 B (available: 33e9 B). Six processes are predicted at 119.6e9 B, above the machine's
  103.1e9 B: the guard did not start them, so nothing is known about six from measurement.
- The cause is in the last row of the seam's table: a part's footprint barely depends on its share of the
  particles. This is the measurement that reopens the question of one GPU-owning process; the verdict is
  not this run's.

**Three findings a later plan should know.**
- **On this macOS a large array that is released stays in the process's footprint** (`vmmap`: `Malloc Large
  (empty)`, still dirty). A first form of the calculator that staged every raw section and released them
  peaked at 22.99e9 B. A footprint bound therefore forbids large transients, not only resident copies
  (Progress, Phase 1).
- **The benchmark's reference rings are double precision.** Rounded to single, as SIMPLE's `set_ref_pft`
  receives its sections, they move every digest (*measured*, Phase 1).
- **The grid file's shift maps are not SIMPLE's rule's:** its radii are rounded to four decimals, and the rule
  gives 3 radii for the window where the file has 4 (*derived*, Phase 2).

## 2. What changed, phase by phase

| Phase | What | Files in its diff |
| --- | --- | --- |
| 0 | The base measured. The benchmark's keys `nparts=`, `part=`, `go=` and its digest lines; `scripts/run_parts.sh`; the bounds frozen | 3 (`review/phase_0.diff`) |
| 1 | `mlxf_toy_polarft_calc` with `_core`, `_memo`, `_block`; `mlxf_toy_polarft_workspace` with `_lifecycle`, `_score`; the dense tester on the calculator; `mlxf_oracle_polar` (renamed); `scripts/toy_mirror.txt`, rule `mirror` and the arity exemption; the benchmark's dense suites on the calculator | 18 (`review/phase_1.diff`) |
| 2 | `mlxf_toy_polarft_shiftmap`, `mlxf_toy_polarft_workspace_shiftmap`, the shift-map tester on the calculator, the benchmark's `shiftmap` suite; every `mlxf_kernel_polar_table*.f90` file removed | 19 (`review/phase_2.diff`) |
| 3 | `mlxf_toy_eul_prob_tab` with its tester (35 checks per device); every suite of the benchmark through the driver; the per-suite key check; `src/test/test.inf` | 11 (`review/phase_3.diff`) |
| 4 | The baseline again, twice; the policy's section 6, the kernel-families note, the roadmap's row, the index, the history, the root `README.md`; this report | documents only |

Lines of code (the polar toy, its testers, oracle and benchmark): 5,522 before (seven `mlxf_kernel_` files and
the benchmark), 8,513 after (thirteen `mlxf_toy_` files, the oracle and the benchmark). The growth is the
calculator's host side and interfaces (1,577 lines), the driver (535), its tester (460), and the benchmark
(1,603 to 1,902). The ledger has 71 lines: 25 mirrored (the types `polarft_calc` and `eul_prob_tab` and 23
bindings) and 46 additions (the type `polarft_workspace`, its 14 bindings, and 31 bindings of the two mirrored
types), each with its reason.

## 3. Decisions taken under delegation

Each is recorded, with its reason, in the plan's Progress entry of its phase.

| Phase | Decision |
| --- | --- |
| 0 | The digest (exclusive or and a shift-register step per 32-bit pattern); `profile` and `overlap` print one too; the guard's prediction; the summed peak footprint is what the bound judges; a part scores each half in one call; two extra baseline runs, reported only |
| 1 | The benchmark's dense suites move to the calculator already in Phase 1; `set_ref_pft` in `complex(real64)`; `banks` and `l_bank` kept; `ws` is one workspace per parity; `memoize_ref_bins` makes the device tiles; the setters stage 64 sections (CTF before section); `set_eo`, `set_ptcl_ctfmat`, `memoize_ref_bins` mirrored beyond the plan's list; twelve additions; refusals through `message()`; the suite is `polarft_calc`; rule `mirror` fails on five more faults than the policy names |
| 2 | `new_shiftmap` and `kill_shiftmap` mirrored and public; `temp_phys` kept; `gen_shiftmap` records the pairs and `shiftmap_mode` builds and reads; the prior's weight at `shiftmap_mode`; `set_sigma2_weights` in `real(real64)`; a map is stale after the references or the weights change; `parameters%box`; six additions on the calculator and seven on the workspace |
| 3 | The constructor is `new_pipeline`; the driver draws the keyed variates; the maps' temperatures as SIMPLE computes them; `set_temps`, `set_candidates`, `set_width_cutoffs`, `use_shiftmap`, `set_fill_options`, `set_fill_stages` and the batch's hand-overs as additions; four mirrored inquiries on the calculator; the key lists |
| 4 | The plan stays in `planned/` and is marked delivered; `CLAUDE.md`'s line on `src/test/` is proposed, not edited (section 6) |

## 4. Deviations from the plan

- **Decision 2 (`new` on the driver).** The driver's constructor is `new_pipeline`, SIMPLE's name: SIMPLE's
  `eul_prob_tab` has no `new`, and rule `mirror` refuses a mirrored name that differs.
- **Decision 3 (dummies dropped).** `banks`, `l_bank` and `temp_phys` are kept: the dense tester scores four
  particles from seed banks, and the maps' widths are taken at the physical temperature. Both procedures
  carry SIMPLE's full lists.
- **Decision 4 (shapes and kinds).** `set_ref_pft` takes `complex(real64)` (finding above). The device layout
  is made in `memoize_ref_bins`, not in `memoize_refs`. The host does not keep the raw sections.
- **Decision 6 and Phase 2 (the maps' grids).** The benchmark and the shift-map tester hand their grids in
  through `new_shiftmap`; `setup_shiftmaps` has SIMPLE's rule and is held to the oracle in the driver's
  tester.
- **Phases.** The benchmark was edited in Phases 1 and 2 as well (its file-table row says so): only it prints
  the digests those phases' gates need. The per-suite key check came in Phase 3, where section 8 places it,
  not in Phase 0. The old files were all gone after Phase 2.
- **Expected and not found.** The guard was expected to bind at six processes, and it did. No digest ever
  differed between two runs, so decision 9's difference rule was never used.
- **Files outside the table:** none. `scripts/check_tree.sh` and `CLAUDE.md` name things this run changed and
  were left alone (section 6).

## 5. Evidence against the baseline

- **Decision 9.** 24 digest lines frozen in Phase 0, each taken twice per device on the base; identical after
  Phases 1, 2 and 3 on both devices (`keep/phase<N>/digests_a/`), and the timing digests again in every
  process of Phase 4's baseline, the three parts included.
- **Decision 10.** `polar_table` 107 (CPU) and 99 (GPU), now `polarft_calc`; `polar_shiftmap` 397;
  `polar_shiftmap_accuracy` 24; unchanged in every phase, Debug and Release. New: `eul_prob_tab` 35 per
  device. `unit_kernels` on both devices: 993 before, 1,063 after. The CTest entries and their budget did not
  move; the fast gate takes 13.4 s of its 60 (12.2 s before).
- **Decision 11.** Bounds frozen in Phase 0: 6.161 s and 21,130,655,136 B at one process, 7.287 s and
  60,735,036,488 B at three. After: 6.003 and 5.997 s with 20,813,411,624 and 20,813,444,392 B; 6.362 and
  6.421 s with 60,321,159,904 and 60,319,669,224 B. **The bound holds at both splits that were run**
  (`keep/phase4/baseline/run_parts.tsv`). Two one-process attempts of the first run were discarded and
  repeated by decision 14 (another build or test process was seen on the machine); their numbers, 6.019 and
  6.045 s, are inside the bound as well.
- **Rules.** The four planted violations of decision 7 and five more make `scripts/check_rules.py` exit 1 with
  the fault named; the unchanged tree passes with `score_block_posterior` at ten dummies. `suite=time
  contraction=2` stops with status 2 and names the key.
- **Builds.** Every phase ended with Debug and Release from scratch with `MLXF_WERROR=ON`, no compiler
  warning, fast gate 8 of 8, `scripts/check_tree.sh` passing, both formatters leaving the touched files as
  they are.
- **Suites' elapsed times** (Release, both devices in one process, *measured* once): the dense suite 0.18 s
  before and after; `polar_shiftmap` 1.32 s before, 1.40 s after; `eul_prob_tab` 0.03 s.

## 6. Left open for the maintainer

**Reserved by the plan.** Whether the miniature reads like SIMPLE. The differences are listed in
[`mlxf_kernel_families.md`](../planned/mlxf_kernel_families.md), section 3, and one by one in
`scripts/toy_mirror.txt`.

**Decisions most likely to be overturned, and what each costs.**
- `set_ref_pft` in `complex(real64)`. The other way: round the benchmark's rings to single precision and
  freeze new digests; one line of the fixture and one kind.
- The staging of 64 sections and its rule that a particle's CTF is set before its section. It exists for the
  footprint bound alone.
- `new_shiftmap` public and the grid file's maps handed in. The other way: regenerate the grid file from
  SIMPLE's rule and freeze new map digests; then `setup_shiftmaps` serves the benchmark too.
- The driver's additions that carry the fixture's choices (`set_temps`, `set_candidates`, `use_shiftmap`,
  `set_fill_stages`): each disappears when the fixture adopts SIMPLE's own rule for that quantity, K4's pool
  selection for the candidates.

**Reported, not gated.** The second reopening condition is met (60.3e9 B at three processes); the first is
not. Six processes were not measured.

**Not done, by the file table.**
- `scripts/check_tree.sh` lists the rules of `check_rules.py` in a comment, without `mirror`.
- `CLAUDE.md` describes `src/test/` as "SIMPLE-shaped kernels and benchmarks" and does not name rule `mirror`
  or the ledger. Proposed: "`src/test/`: test-only code (assertions, the suite registry, the toys that mirror
  SIMPLE's classes, their oracle and benchmark)", and under "The library's rules" a line for the toys: names
  and dummies are SIMPLE's, `scripts/toy_mirror.txt` lists every public type and binding, rule `mirror`.
- The plan is still in `planned/`; it moves to `completed/` with the commit.
- `test/CMakeLists.txt`'s comment on the area `kernels` still says "the polar table's scoring workspace":
  it names no removed file, so the table did not open it.

**Seen on the way, outside this run.** The accuracy suite reports a CPU calibration of `e_cpu =
7.2525524211286473E-07` with 3 rotations differing, on the base and after, where the frozen constants are
`7.2525524223032628e-07` and 2. The judged runs are inside their bounds; the constants were frozen on another
machine or MLX version.

## 7. A commit message

```
Toy architecture: the polar toy as a miniature of SIMPLE's polarft_calc

The test-only polar kernels become mlxf_toy_polarft_calc (core, memo, block,
shiftmap), its GPU workspace mlxf_toy_polarft_workspace and the table driver
mlxf_toy_eul_prob_tab, under SIMPLE's names and dummy lists (read at
d354efee2). scripts/toy_mirror.txt lists every public type and binding as
mirrored or as an addition with its reason; rule mirror holds it to the code
and rule arity exempts the mirrored procedures only. The oracle is
mlxf_oracle_polar. No mlxf_kernel_ file is left.

The device arithmetic is unchanged: 24 digests of distances, rotations and
map results are identical before and after on both devices. Suites:
polarft_calc 107/99, polar_shiftmap 397, polar_shiftmap_accuracy 24, new
eul_prob_tab 35 per device.

bench_polar_table fills its tables through the driver, prints a digest per
result, takes nparts=, part= and go=, and refuses a key its suite does not
read. scripts/run_parts.sh measures simultaneous part processes. Dense
baseline on the M5 Ultra, before and after: 1 process 6.05/6.09 s and
21.13e9 B, then 6.00/6.00 s and 20.81e9 B; 3 processes 6.71/6.42 s and
60.73e9 B, then 6.36/6.42 s and 60.32e9 B; 6 processes not run (guard).

Run mlxf_toy_arch; report doc/implementation_notes/completed/
mlxf_toy_architecture_report.md.
```
