# The polar toy as a miniature of SIMPLE's `polarft_calc` (run `mlxf_toy_arch`, on the M5 Ultra)

Status, 2026-11-24: delivered in the working tree by run `mlxf_toy_arch` (Phases 0 to 4, Progress below;
[report](../completed/mlxf_toy_architecture_report.md)); awaits the maintainer's read. Planned the same day as
the roadmap's rank 0b. The maintainer told the batch to proceed, so decisions 1 to
14 stand as recommended and any of them may be overturned at the review. Base: the maintainer's commit of
parity's Phases 2 and 3 and of this note (the run records its HEAD); the code this note was checked against is
`dc3f5d7` with run `mlxf_parity`'s diff applied. SIMPLE is read at `d354efee2`. Supersedes: none. Depends on:
the roadmap's decisions 11 and 12 (validated: ruled, 2026-11-24);
[the toy-example policy](../../policies/toy_example_policy.md) (validated: ruled, 2026-11-24; its ledger and
rule do not exist yet); milestone 1's kernels and benchmark (validated: yes, run `mlxf_m1_m5`, and rebuilt on
the base above on 2026-11-24: `unit_kernels` 993 checks, Debug and Release, no warning).

## 1. Why

Milestone 1's kernels model a GPU workspace beside SIMPLE's calculator under their own names (`polar_table`,
`score`, `prepare_maps`, `score_maps`), and the loops that stand for the table fill live in a tester and a
benchmark. Nobody can read from them how the kernel would sit in SIMPLE. The maintainer ruled that toys mirror
SIMPLE's architecture (roadmap, decision 11), and that the refactoring is bracketed by one measurement of how
several part processes share the GPU and the memory (decision 12). Every family-A deliverable (K1, K3, K4)
builds on this code, so it comes first.

## 2. Contract

- **Where the code lives:** `src/test/` only, in modules `mlxf_toy_<stem>` that import the public `mlxf`
  module as a user does. No file under `src/core/` or `src/defs/` changes.
- **What it is:** a refactoring. The device arithmetic, the graphs, the tile plans and the fixtures do not
  change. What changes is who owns what, what the procedures are called, the shapes of host data at the
  interface, and where the loops of the table fill live.
- **What it mirrors,** read at SIMPLE `d354efee2` with `git -C ~/src/SIMPLE show d354efee2:<path>` (never the
  working tree, which moves; SIMPLE is never edited and no SIMPLE source is copied in):
  - `src/main/pftc/simple_polarft_calc.f90`, type `polarft_calc`, and its submodules `simple_polarft_core`,
    `simple_polarft_memo`, `simple_polarft_block`, `simple_polarft_shiftmap`;
  - `src/main/strategies/search/probabilistic/simple_eul_prob_tab.f90`, type `eul_prob_tab`, with
    `fill_tab_range` and its contained steps.
- **Not part of it:** a new kernel, a faster kernel, the candidate pool's selection, the in-cell refinement,
  `eul_prob_tab_neigh`, `shiftmap_srch`, any wrapper.

### What the check found (2026-11-24)

- **Today's types.** `polar_table` (`src/test/mlxf_kernel_polar_table.f90`, submodules `_lifecycle`,
  `_score`, `_shiftmap`) binds `new`, `invalidate`, `kill`, `submit`, `collect`, `score`, `prepared_now`,
  `message`, `stage_seconds`, `prepare_maps`, `score_maps`, `map_order`, `map_term_counts`, `map_seconds`. Its
  records (`polar_table_refs`, `polar_table_block`, `polar_table_entries`, `polar_map_spec`,
  `polar_map_block`, `polar_map_results`) are in `src/test/mlxf_test_defs.f90`.
- **The memos are made by the fixtures.** The benchmark and the testers compute the references' and
  particles' memos with the oracle module's double-precision transform (`polar_memo_rows`) and hand them in. In
  SIMPLE the calculator makes them, in `memoize_refs` and `memoize_ptcls`.
- **SIMPLE's signatures** at `d354efee2`:
  - `new( self, params, nrefs, pfromto, kfromto, nmany_refs, fftw_measure )`;
  - `set_ref_pft( self, iref, pft, iseven )`, `set_ptcl_pft( self, iptcl, pft )`, with
    `pft(self%pftsz, self%kfromto(1):self%interpklim)` in `complex(sp)`;
  - `memoize_refs( self, eulspace )`, `memoize_ptcls( self )`, `reallocate_ptcls( self, nptcls, pinds )`;
  - `score_block_posterior( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )`, with
    `dists(nr,nb)` and `irots(nr,nb)`;
  - `setup_shiftmaps( self, sigma_px, radius_px, radius_win, prior_w, kscreen )`;
  - `gen_shiftmap( self, imap, iref, iptcl )`;
  - `shiftmap_mode( self, imap, temp, prior_w, irot, irho, ialpha, loss, temp_phys, sdev, width_cutoff )`;
  - `fill_tab_range( self, i_first, i_last )`, whose steps `seed_particle`, `seed_particle_map` and
    `finish_particle_map` are contained procedures.
- **The benchmark** (`src/test/mlxf_bench_polar_table.f90`, 1,603 lines) has the suites `accuracy`, `time`,
  `profile`, `overlap`, `stream`, `shiftmap`. It reads 16 keys; a key a suite does not read is ignored. It has
  no key that gives a process a share of the particles, and it prints no digest of its results.
- **Suites and counts on the base** (*measured*, 2026-11-24, Debug and Release): `polar_table` 107 checks on
  the CPU and 99 on the GPU, `polar_shiftmap` 397, `polar_shiftmap_accuracy` 24 (named only); the area
  `unit_kernels` evaluates 993 when run directly on both devices.
- **The machine:** 30 cores, 103.1 GB. One process scoring case `2500_4` had a peak footprint of 21.05e9 B
  with an MLX peak of 10.26e9 B (*measured*, run `mlxf_m1_m5`). Six such processes would need about 126 GB
  (*derived*), more than the machine has: decision 11's guard is expected to bind.
- **Shared test files.** Parity changed `src/test/mlxf_test_defs.f90`, `src/test/mlxf_test_registry.f90` and
  `test/CMakeLists.txt`. This run changes the first two again, which is why it starts from parity's commit.

## 3. Decisions and rulings

1. (2026-11-24, recommended) **Scope:** the polar toy becomes a miniature `polarft_calc` with a driver
   `eul_prob_tab`. No arithmetic changes.
2. (2026-11-24, recommended) **Modules,** all in `src/test/`:

   | Module (file of the same name) | Holds | From |
   | --- | --- | --- |
   | `mlxf_toy_polarft_calc` | type `polarft_calc`: the host references and particles in SIMPLE's shapes, `pinds`, and one component `ws` | new |
   | `mlxf_toy_polarft_core` (submodule) | `new`, `kill` | new |
   | `mlxf_toy_polarft_memo` (submodule) | `set_ref_pft`, `set_ptcl_pft`, `reallocate_ptcls`, `memoize_refs`, `memoize_ptcls` | the fixtures' memo code |
   | `mlxf_toy_polarft_block` (submodule) | `score_block_posterior`, and the submission and collection of a block | calls the workspace |
   | `mlxf_toy_polarft_shiftmap` (submodule) | `setup_shiftmaps`, `gen_shiftmap`, `shiftmap_mode` | calls the workspace |
   | `mlxf_toy_polarft_workspace` and its submodules | type `polarft_workspace`: every MLX handle and compiled function | `mlxf_kernel_polar_table` and its three submodules, renamed |
   | `mlxf_toy_eul_prob_tab` | type `eul_prob_tab`: `new`, `fill_tab_range`, `kill` | the loops of the testers and the benchmark |
   | `mlxf_oracle_polar` | the oracle, unchanged in content | `mlxf_kernel_polar_oracle`, renamed |

   After the run no `mlxf_kernel_*` file is left. The oracle takes the name form of the host oracles
   (`mlxf_oracle_<x>`).
3. (2026-11-24, recommended) **Names and dummies are SIMPLE's** (the policy's mirror rule, points 2 and 3).
   - A dummy the toy has no use for is dropped (`nmany_refs`, `fftw_measure`, `eulspace`, `banks`, `l_bank`,
     `temp_phys`) and listed as a difference; the dummies kept keep SIMPLE's order.
   - Where SIMPLE passes `params`, the toy passes a record `parameters` of the test definitions with SIMPLE's
     member names for the members the toy reads.
   - `gen_shiftmap` and `shiftmap_mode` keep their names and take arrays over the maps of a block (`imap`,
     `iref`, `iptcl`, `temp` and the results become rank 1). The batched form is a recorded difference.
   - A status argument is not added to a mirrored procedure. A refusal is read from an added inquiry
     (`message`, as today), and a mirrored procedure that is refused leaves its results at SIMPLE's invalid
     values.
4. (2026-11-24, recommended) **Host data has SIMPLE's shapes.**
   - References are `(pftsz, kfromto(1):kfromto(2), nrefs)` in `complex(real32)`, one array per half, set one
     at a time through `set_ref_pft`.
   - Particles are set through `set_ptcl_pft` and addressed through `pinds`.
   - The memos are made in `memoize_refs` and `memoize_ptcls` by the transform the fixtures use today, called
     from there, so that their bits do not change. The device layout is made there too.
5. (2026-11-24, recommended) **The seam.** `polarft_calc` has one component `ws` of type `polarft_workspace`,
   created in `new` and released in `kill`. Each mirrored method is host code or a call into `ws`. The
   workspace's procedures are additions, named for what they do. The report states for the seam: what is
   resident on the device and its bytes, where the host waits, and what a part process holds for an iteration.
6. (2026-11-24, recommended) **The driver.** `eul_prob_tab%fill_tab_range( self, i_first, i_last )` walks the
   particles in batches and calls the calculator in SIMPLE's order: the dense score of a block, then, when
   maps are set up, the maps and modes of the block's candidate pairs. The candidates come from the fixture,
   as today; the pool's selection and the in-cell refinement are declared differences (K4 owns them). Testers
   and the benchmark call the driver or the calculator, never `ws`.
7. (2026-11-24, recommended) **The ledger and its rule.** `scripts/toy_mirror.txt` and rule `mirror` enter in
   Phase 1 as the policy's section 4 defines them. Rule `arity` reads the ledger for the exemption of
   mirrored procedures. Each is shown to fail on a planted violation: a type-bound procedure missing from the
   ledger, a mirrored line whose toy name differs, an addition without a reason, an addition with six
   dummies; `score_block_posterior` with its SIMPLE list passes.
8. (2026-11-24, recommended) **The benchmark keeps its name and its columns** (`test=bench_polar_table`, the
   `.tsv` rows), so that the M5 records stay comparable. It gains:
   - keys `nparts=` and `part=`: the process scores its share of the case's particles, split as evenly as
     SIMPLE splits them, against all the references;
   - a key `go=<file>`: the process prepares its data, writes `<file>.ready.<part>` and starts scoring when
     `<file>` exists, so that simultaneous processes are timed on scoring and not on synthesis;
   - a digest line per timed or checked result (decision 9);
   - a per-suite list of the keys it reads. A key outside the list of the suite that runs stops the program
     with `error stop 2` and names the key. `contraction=2` is the planted violation.
9. (2026-11-24, recommended) **The refactoring is proven by identical results.** The benchmark prints a
   64-bit digest of the bit patterns of the dense entries (distances, rotations) and of the map results. In
   Phase 0 each digest is taken twice per device on the base.
   - Where the two base runs agree, the refactored code must give the same digest.
   - Where they differ, the gate for that result is the suite's frozen bounds and a largest difference from
     the base no greater than twice the difference between the two base runs (*measured* in Phase 0).
10. (2026-11-24, recommended) **Counts.** The three suites keep their counts of section 2 under whatever
    names the registry's rule gives the renamed testers. The driver's tester is a new suite of the same area;
    its count is recorded when it is written. The CTest entries and their budget do not move.
11. (2026-11-24, from the roadmap's decision 12) **The dense-driver baseline,** taken twice in Phase 0 and
    twice in Phase 4.
    - **Workload:** case `2500_4` (2,000 particles, 10,000 references, `pftsz` 182, `kfrom` 2, `kto` 62), on
      the GPU at full precision (`MLX_ENABLE_TF32=0`), tile plan 64 by 250.
    - **Splits:** 1, 3 and 6 simultaneous processes with 30, 10 and 5 threads each. Each holds all the
      references.
    - **Launcher:** `scripts/run_parts.sh` starts the processes, waits for every ready file, creates the go
      file, and records the time from go to the last exit, each process's rate, MLX peak and cache, peak
      footprint and maximum resident size, and the machine's lowest free memory sampled once a second.
    - **Guard:** before a split is run, the summed footprint is predicted from the splits already measured.
      A split predicted above 0.8 of the machine's 103.1 GB (*guessed*) is not run and is recorded as such.
    - **The refactoring's bound:** at no split that was run may the time be longer than the slower before-run
      by more than twice the difference between the two before-runs, nor the peak footprint larger than the
      larger before-run by more than twice theirs (*measured* in Phase 0, frozen there).
    - **Reported, not gated:** the roadmap's two conditions that reopen the question of one GPU-owning
      process (total rate at 3 or 6 below 0.8 of one process's; summed footprint above 51.5 GB).
12. (2026-11-24, recommended) **A file the table does not name.** The run may add a row for a new
    `src/test/mlxf_toy_*.f90` file before its first edit, with the reason in Progress. No row is added
    outside `src/test/`.
13. (2026-11-24, recommended) **Old files go by `rm`,** in the phase that removes their last use. That they
    are dead is shown by both builds passing without them.
14. (2026-11-24, recommended) **The machine is quiet for the baseline.** Nothing else is built or run on the
    M5 during Phase 0's and Phase 4's measurements; a measurement whose launcher finds another
    `mlxf_test_exec`, `cmake` or `gfortran` process is discarded and repeated.

## 4. Not in this plan

- K1's fused tail, K3's arbitrary reference sets, K4's shift lattice and pool: their own plans.
- A change to the library, the parity ledger or a wrapper.
- A verdict on a single GPU-owning process: this run reports the measurement that would reopen it.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement keys on the base; baseline | both builds without a warning; the counts of section 2 unchanged; each digest taken twice; the baseline taken twice; the bounds frozen in Progress |
| 1 | identical: the calculator's dense route, the ledger and its rules | decision 9 for the dense entries on both devices; `polar_table`'s counts; the four planted violations fail |
| 2 | identical: the shift maps | decision 9 for the map results; `polar_shiftmap` 397 and `polar_shiftmap_accuracy` 24 |
| 3 | identical: the driver, the benchmark on it, the old files removed | decision 9 for every digest through the driver; the benchmark's accuracy suite inside its frozen bounds; the key check's planted violation fails; no `mlxf_kernel_` name left |
| 4 | measurement and documentation | decision 11's bound; the report |

Every phase ends with Debug and Release built from scratch with `MLXF_CMAKE_ARGS="-DMLXF_WERROR=ON"` and no
warning, the fast gate 8 of 8 in both, `scripts/check_tree.sh` passing, and `scripts/restyle_fortran.py` and
`scripts/format_use_blocks.py` run on every Fortran file touched (the second only with explicit file names).

## 6. Acceptance

- Decisions 9, 10 and 11, with their numbers frozen in Phase 0's Progress entry before any refactored code is
  built.
- The mirror ledger lists every public type and type-bound procedure of every `mlxf_toy_*` module.
- **Reported, not gated:** the seam's table (decision 5); the two reopening conditions; lines of code before
  and after; the suites' elapsed times.
- **Reserved for the maintainer:** whether the miniature reads like SIMPLE. The report lists the
  differences, each with its reason, for that read.

## 7. Common rules and stop conditions

- No file outside the table, apart from decision 12's rows. No bound loosened and no fixture changed to pass.
- A test executable run directly on the GPU is run with `MLX_ENABLE_TF32=0`.
- The run writes its notes with the editor tools: the fence refuses a shell command whose text names a
  publish to the remote.

**Stops:**
- a digest cannot be kept without changing the arithmetic or a graph;
- decision 11's bound fails after two attempts to find the extra wait or copy;
- a mirrored name or dummy list cannot be kept under a house rule other than arity (record it and stop only if
  no declared difference resolves it);
- a change to `src/core/` or `src/defs/` would be needed;
- the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the library untouched; the
oracle shares no code with the toy; no SIMPLE source copied.

## 8. Phases

### Phase 0, the base and the baseline

1. Record the machine, the base commit and SIMPLE's commit. Build Debug and Release from scratch; run the
   gate; record the counts and compare them with section 2.
2. Copy the case and grid files of run `mlxf_m1_m5` (`~/agent_runs/mlxf_m1_m5/scratch/keep/polar_case.txt`,
   `shiftmap_grid.txt`) into the run's `scratch/keep/`; if they are gone, write the case from decision 11.
3. Add decision 8's keys and digest to the benchmark, and `scripts/run_parts.sh`. Nothing else changes.
4. Take every digest twice per device (the accuracy block, one timing configuration of `2500_4`, the two
   map suites' results). Record which are repeatable.
5. Take the baseline twice (decision 11), one process first, the guard before each larger split.
6. Freeze decision 9's and decision 11's numbers in Progress, each tagged with its origin.
7. Read SIMPLE's files of section 2 at `d354efee2` and write the dummy lists and members the toy keeps, and
   the differences, into Progress.

**Exit:** the numbers are frozen; both builds are free of warnings; the gate passes.

### Phase 1, the calculator and the dense route

`polarft_calc` with `core`, `memo` and `block`; the workspace renamed, its dense part behind `ws`; the oracle
renamed; the dense tester on the calculator; the ledger, rule `mirror` and the arity exemption with their
planted violations.

**Exit:** the phase's gate of section 5.

### Phase 2, the shift maps

`setup_shiftmaps`, `gen_shiftmap` and `shiftmap_mode` on the workspace's map part; the shift-map testers on
the calculator.

**Exit:** the phase's gate of section 5.

### Phase 3, the driver and the benchmark

`eul_prob_tab` with its tester; the benchmark's suites call the driver; the per-suite key check; the old
files removed; `src/test/test.inf` and the registry current.

**Exit:** the phase's gate of section 5; `rg mlxf_kernel_ src test scripts` finds nothing.

### Phase 4, the baseline again and the report

1. Take the baseline twice and judge it against Phase 0's bound.
2. Update the policy's section 6, the kernel-families note (section 2a and a new section "Differences from
   SIMPLE" for family A), the roadmap's rank 0b row, the plans index, the history and the root `README.md`'s
   status where it names the kernels.
3. Write the report in the order of `doc/how2s/how2write_agent_plans.md`, section 8. It includes the seam's
   table, the baseline before and after at each split, the two reopening conditions with their numbers, the
   ledger's counts of mirrored lines and additions, and a commit message.

**Exit:** the bound holds; the report exists; `scripts/check_tree.sh` passes; `git status` shows only
file-table paths.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_bench_polar_table.f90` | keys, digest; the dense suites on the calculator (Phase 1: only the benchmark prints the digests that phase's gate needs), the map suite (Phase 2); then the suites on the driver | 0, 1, 2, 3 |
| `scripts/run_parts.sh` (new) | the launcher of simultaneous part processes | 0, 4 |
| `src/test/mlxf_toy_*.f90` (new) | the calculator, its submodules, the workspace, the driver and their testers | 1, 2, 3 |
| `src/test/mlxf_oracle_polar.f90` (new) | the oracle under its new name | 1 |
| `src/test/mlxf_kernel_polar_oracle.f90` | removed | 1 |
| `src/test/mlxf_kernel_polar_table.f90` | removed when its last use is gone | 1, 2, 3 |
| `src/test/mlxf_kernel_polar_table_lifecycle.f90` | removed when its last use is gone | 1, 2, 3 |
| `src/test/mlxf_kernel_polar_table_score.f90` | removed when its last use is gone | 1, 2, 3 |
| `src/test/mlxf_kernel_polar_table_shiftmap.f90` | removed when its last use is gone | 1, 2, 3 |
| `src/test/mlxf_kernel_polar_table_tester.f90` | removed when its last use is gone | 1, 2, 3 |
| `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90` | removed when its last use is gone | 1, 2, 3 |
| `src/test/mlxf_test_defs.f90` | the records in SIMPLE's shapes; the record `parameters` | 1, 2, 3 |
| `src/test/mlxf_test_registry.f90` | the suites' modules and names | 1, 2, 3 |
| `src/test/test.inf` | the directory's description | 3 |
| `test/CMakeLists.txt` | only if a comment names a removed file | 3 |
| `scripts/toy_mirror.txt` (new) | the mirror ledger | 1, 2, 3 |
| `scripts/check_rules.py` | rule `mirror`; the arity exemption | 1 |
| `doc/policies/toy_example_policy.md` | section 6 | 4 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | section 2a; family A's differences | 4 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | the rank 0b row | 4 |
| `doc/implementation_notes/README.md` | the index | 4 |
| `doc/history/2026-11.md` | the entry | 4 |
| `README.md` | the status, where it names the kernels | 4 |
| `doc/implementation_notes/planned/mlxf_toy_architecture.md` | this note: Progress, decision 12's rows | 0, 1, 2, 3, 4 |
| `doc/implementation_notes/completed/mlxf_toy_architecture_report.md` (new) | the report | 4 |

## Progress

(one entry per phase, written by the run)

### Phase 0, the base and the baseline (2026-11-24, 19:23 to 20:20, done)

Machine: the M5 Ultra (Apple M5 Ultra, 30 cores, 103,079,215,104 B, macOS 27.2.1), gfortran 16.2.0 (Homebrew),
CMake 4.5.1, mlx-c 0.8.0 and MLX 0.32.4 (Homebrew). Base commit `441873c`; SIMPLE read at `d354efee2`. The
rulings file of the run was empty. Paths below are under `/Users/hael/agent_runs/mlxf_toy_arch/scratch`.

**Files changed:** `src/test/mlxf_bench_polar_table.f90` (1,603 to 1,771 lines), `scripts/run_parts.sh` (new),
this note.

**What was added.**
- `suite=time` reads `nparts=` and `part=` (the part's contiguous share of the particle IDs: every part takes
  `nptcls / nparts` and the first `mod(nptcls, nparts)` parts one more, which are the ranges of SIMPLE's
  `split_nobjs_even`; all the references) and `go=<file>` (after the synthesis it writes `<file>.ready.<part>`
  and polls every 10 ms until `<file>` exists; it gives up after an hour). The references go to the device after
  go, so the launcher's time holds the preparation, the warm-up pass, the three timed passes and the exit.
- One line `digest <suite> <what> <device> <16 hex digits>` per result in `accuracy`, `time`, `profile`,
  `overlap` and `shiftmap`. The digest runs over the 32-bit patterns of the distances and then the rotations
  (maps: loss, width, rotation, radius, direction, and the evidence when asked), half 1 first.
- `scripts/run_parts.sh EXEC NPARTS NTHR OUTDIR cases=FILE [key=value ...]`: decision 11's launcher, with the
  guard, decision 14's quiet check, the load wait and one row per split in a series table.
- With `nparts=1` (the default) the rows, the batches and the columns are those of the base.

**Exit items.**

| Item | How it was met | Evidence |
| --- | --- | --- |
| Both builds without a warning | Debug and Release from scratch with `MLXF_WERROR=ON`, on the base and again on the edited tree; fast gate 8 of 8 in all four; `scripts/check_tree.sh` passes; both formatters leave the benchmark unchanged | `keep/phase0/base_build_{Debug,Release}.log`, `keep/phase0/final_build_{Debug,Release}.log` |
| The counts of section 2 | On the base, Debug and Release alike (*measured*): `polar_table` 107 on the CPU and 99 on the GPU, `polar_shiftmap` 397 per device, `polar_shiftmap_accuracy` 24 per device, `unit_kernels` 993 on both devices. `unit_core` reports 1 GPU device | `keep/phase0/base_{Debug,Release}_kernels_*.log` |
| Each digest twice | Passes a and b (and c for the CPU device's two long runs) agree in every line | `keep/phase0/digests_{a,b,c}/`, `logs/digests_{a,b,c}.log` |
| The baseline twice | Runs r1 and r2; two more (r3, r4) reported | `keep/phase0/baseline/` (`run_parts.tsv`, `r<n>_n<split>_a1/`), `keep/phase0/baseline_repeat/`, `logs/baseline_r{1,2,3,4}.log` |
| The bounds frozen | Below | this entry |

**Decision 9, frozen: every digest is repeatable, so every one must come back identical** (*measured*, Release,
`MLX_ENABLE_TF32=0`, case `2500_4`; no result needs the difference rule).

| Suite and result | CPU device | GPU |
| --- | --- | --- |
| `accuracy`, block seed 1, 16 by 250 (the calibration) | `6C2823C473029BD2` | not run there |
| `accuracy`, block seed 2, at 16 by 250, 32 by 1000 and 12 by 300; one call with the particles in order; the identity's canonical table | `C8B49BC7A6676AF2` | `EF6D23726EFF3EF7` |
| `accuracy`, one call, particles reversed | `B754BBDACD79D649` | `9FADF409D4A20F7D` |
| `accuracy`, one call, references shuffled | `1D586C19F54A9F3A` | `A58EB9A70285325E` |
| `time`, `2500_4` at 64 by 250, all particles | `4B4FF8EBDEEA9837` | `3457E99553A08BFD` |
| `profile`, and `overlap` with one slot and with two, `2500_4` at 64 by 250 | not run there | `3457E99553A08BFD` |
| `time`, `nparts=3` at 64 by 250, parts 1, 2, 3 (in the baseline, r1 and r2 alike) | not run there | `B69FA174DE317D3C`, `4BFC1DA8533AB2F5`, `8921689A9191A114` |
| `shiftmap`, map `window`, `ptiles=16` | `03C5A5E6AA5AE03D` | `CCF8071F11C612F9` |
| `shiftmap`, map `screen`, `ptiles=16` | `F2C60FA721A09D16` | `3218B5567D7482E9` |

On the CPU device `time` took 411 and 424 s and `shiftmap` about 7 minutes; later phases need them once each.

**Decision 11, frozen** (*measured*; GPU, full precision, tile plan 64 by 250; one-minute load before each split
between 1.50 and 1.98; no other `mlxf_test_exec`, `cmake` or `gfortran` process in any run).

| Split | Run | Go to last exit, s | Summed rate, pairs/s | Summed peak footprint, B | Largest process, B | Summed MLX peak, B | Lowest free, B | Lowest available, B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 by 30 threads | r1 | 6.053 | 1.76644e7 | 21,130,032,592 | the same | 10,257,300,000 | 33.10e9 | 60.89e9 |
| 1 by 30 threads | r2 | 6.089 | 1.76404e7 | 21,129,721,320 | the same | 10,257,300,000 | 39.91e9 | 63.28e9 |
| 3 by 10 threads | r1 | 6.707 | 1.74211e7 | 60,733,660,016 | 20,309,537,776 | 29,713,830,000 | 0.47e9 | 33.33e9 |
| 3 by 10 threads | r2 | 6.417 | 1.79606e7 | 60,734,118,840 | 20,309,652,416 | 29,713,830,000 | 0.39e9 | 32.99e9 |
| 6 by 5 threads | r1, r2 | not run: the guard predicts 120.6e9 B, above 0.8 of the memory (82.46e9 B) | | | | | | |

The bounds Phase 4 is judged by (*derived* from the rows above: the slower or larger run plus twice the
difference of the two):

| Split | Time from go to the last exit | Summed peak footprint |
| --- | --- | --- |
| 1 | at most 6.089 + 2 x 0.036 = **6.161 s** | at most 21,130,032,592 + 2 x 311,272 = **21,130,655,136 B** |
| 3 | at most 6.707 + 2 x 0.290 = **7.287 s** | at most 60,734,118,840 + 2 x 458,824 = **60,735,036,488 B** |
| 6 | not judged: not run on the base | |

The repeats r3 and r4 on the unchanged code are inside these bounds (*measured*, reported): split 1 in 6.077 and
6.086 s with 21,130,311,480 and 21,130,065,408 B; split 3 in 6.452 and 6.401 s with 60,734,069,664 and
60,733,660,376 B.

**Reported, not gated** (the roadmap's two conditions, on the base):
- The total rate at 3 processes is 0.986 (r1) and 1.018 (r2) of one process's: above 0.8, so the first
  condition is not met. The rate is each process's best of 3 passes, summed; the time from go to the last exit
  grows by 0.33 to 0.65 s (5 to 11 %) from 1 process to 3.
- The summed footprint at 3 processes is 60.73e9 B, above 51.5e9 B: **the second condition is met on the base.**
  A part with a third of the particles still holds 20.31e9 B, against 21.13e9 B for all of them, because each
  holds all the references. The machine's free memory fell to 0.4e9 B (available: 33e9 B).

**Decisions taken under delegation.**
1. The per-suite key list and its `error stop 2` stay in Phase 3, where section 8 and section 5's gate place
   them. Phase 0 adds `nparts=`, `part=`, `go=` and the digest. Reason: step 3 of Phase 0 says "keys and digest",
   Phase 3 names "the per-suite key check" and gates its planted violation.
2. "The two map suites' results" of step 4 are read as the benchmark's `shiftmap` suite on the maps `window` and
   `screen`. Reason: the testers are not Phase 0 files and decision 9 has the benchmark print the digests.
3. The digest: each 32-bit pattern enters a 64-bit state by exclusive or, followed by one shift-register step
   (shifts 13, 7, 17). Reason: no integer multiplication, so nothing overflows; a changed bit or order changes it.
4. `profile` and `overlap` print a digest too. Reason: decision 8 asks for one per timed result, and Phase 3
   moves both suites onto the driver.
5. The guard's prediction: from one measured split, the number of processes times its largest process; from two
   or more, the number of processes times the line through the two finest splits' largest processes against the
   share 1/n. With nothing measured, a split above one process is not run.
6. The footprint the bound judges is the summed peak footprint of the split's processes (macOS's "peak memory
   footprint" of `/usr/bin/time -l`); the largest process is reported. Reason: the guard and the roadmap's
   condition both speak of the summed footprint.
7. A part's processes score each half in one call of the larger half's particles (`outer` is 334 or 333 for a
   third of 2,000). Reason: with the case's half as the batch a part's odd particle would open a second, padded
   call. With one part the batch is the case's half, as on the base.
8. Two more baseline runs (r3, r4) were taken and are reported only. Reason: the two before-runs of split 1 differ
   by 0.036 s, and the repeats show that the unchanged code stays inside a bound that narrow.
9. `free` in the launcher is macOS's free plus speculative pages, `available` adds the inactive and purgeable
   ones; both are recorded.

**What SIMPLE has at `d354efee2`, and what the toy keeps** (step 7; paths under `src/main/pftc/` unless given).

| SIMPLE's procedure and dummy list | The toy keeps | Dropped or changed, to be listed as a difference |
| --- | --- | --- |
| `new( self, params, nrefs, pfromto, kfromto, nmany_refs, fftw_measure )`, `simple_polarft_core.f90`; `params` of class `parameters`, `pfromto(2)`, `kfromto(2)` | `new( self, params, nrefs, pfromto, kfromto )`; `params` is the record `parameters` | `nmany_refs`, `fftw_measure`. SIMPLE reads `params%box_crop` (for `interpklim`), `%box` (`ldim`, the pixels the shifts are in), `%pftsz`, `%ctf`; the toy's record carries `pftsz` and `box`, and `prob_beta` for the maps' tempered temperature; `interpklim` is `kfromto(2)` |
| `kill( self )` | the same | |
| `reallocate_ptcls( self, nptcls, pinds )`, `pinds(nptcls)`; sets `pfromto` to the range of `pinds` and `self%pinds(pinds(i)) = i` | the same | |
| `set_ref_pft( self, iref, pft, iseven )`, `complex(sp) :: pft(self%pftsz, self%kfromto(1):self%interpklim)`, `logical :: iseven` | the same, with the shell range `kfromto(1):kfromto(2)` (decision 4) | the shells above `kfromto(2)` |
| `set_ptcl_pft( self, iptcl, pft )`, `pft` as above, `iptcl` the project index (stored at `pinds(iptcl)`); it also memoizes the particle's square sums | the same | |
| `memoize_refs( self, eulspace )`, `simple_polarft_memo.f90`: per parity the first `pftsz+1` bins of the forward transform of the full ring into `ft_ref`, and the conjugated transform of its squared modulus into `ft_ref2` | `memoize_refs( self )`, with the device layout | `eulspace` (the mirror path) |
| `memoize_ptcls( self )`: `ft_ptcl_ctf` from the particle times its CTF, `ft_ctf2` from the squared CTF | the same | |
| `score_block_posterior( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )`, `simple_polarft_block.f90`: `iptcls(nb)` project indices of one half, `irefs(nr)`, `real(sp) :: temps(nb)`, `real(sp), intent(out) :: dists(nr,nb)`, `integer, intent(out) :: irots(nr,nb)` | `score_block_posterior( self, nb, iptcls, nr, irefs, temps, dists, irots )` | `banks`, `l_bank`; SIMPLE's block is at most `PFTC_BLOCK_NB` = 16 particles, the toy's is the tile plan's |
| `setup_shiftmaps( self, sigma_px, radius_px, radius_win, prior_w, kscreen )`, `simple_polarft_shiftmap.f90`: `real(dp)` inputs in pixels; out `prior_w = 1 / (2 sigma_px**2)` and `kscreen = max(kfromto(1) + 1, kfromto(2) / 2)`; builds the maps `SHIFTMAP_SCREEN` and `SHIFTMAP_WINDOW` with the radial step `box / kstop / 4` | the same | SIMPLE's grid rule gives the radii and directions; the fixture's grid file gives them today, so the grids must be shown to agree or the rule is a declared difference |
| `gen_shiftmap( self, imap, iref, iptcl )` | the same names with `imap` scalar and `iref(:)`, `iptcl(:)` over the maps of a block (decision 3) | the batched form |
| `shiftmap_mode( self, imap, temp, prior_w, irot, irho, ialpha, loss, temp_phys, sdev, width_cutoff )`: `real(dp) :: temp, prior_w`; `integer, intent(out) :: irot, irho, ialpha`; `real(sp), intent(out) :: loss`; optional `temp_phys` (in), `sdev` (out), `width_cutoff` (in) | `shiftmap_mode( self, imap, temp, prior_w, irot, irho, ialpha, loss, sdev, width_cutoff )` with rank-1 `temp` and results | `temp_phys` (decision 3); the batched form |
| `fill_tab_range( self, i_first, i_last )`, `src/main/strategies/search/probabilistic/simple_eul_prob_tab.f90`; contained `cut_blocks`, `process_block( j0, j1, ithr_loc )`, `seed_particle`, `finish_particle`, `seed_particle_map( i_loc, iptcl_loc, ithr_loc, l_disk, l_prior )`, `finish_particle_map( i_loc, iptcl_loc, ithr_loc, l_disk, l_prior )` | `fill_tab_range( self, i_first, i_last )` with contained steps under SIMPLE's names | the pool's selection and the in-cell refinement (decision 6); the OpenMP loop over blocks (one submitting thread) |
| `eul_prob_tab` has no `new`: its constructor is `new_pipeline( self, params, build, pinds, block_memo )`, and `kill( self )` | to be ruled, see below | `build`, `block_memo` |

Invalid values in SIMPLE, which a refused mirrored procedure leaves (decision 3): `dists = huge(dists)` with
`irots = 1` for a row without a valid rotation; `sdev = -1.` when the mode's loss is above `width_cutoff`.

SIMPLE's order of calls (the setter-based sequence of `simple_polar_matching_bench.f90`, and production's):
`new`, `set_ref_pft` for both halves, the particles' CTF matrices, `set_ptcl_pft` and `set_eo`,
`assign_sigma2_noise` (with `memoize_sigma2_weights`), `memoize_refs`, `memoize_ptcls`, `memoize_ref_bins`; per
batch `reallocate_ptcls`, the setters and `memoize_ptcls`; then `fill_tab_range`, which calls `set_rnd_scope`,
cuts the range into blocks of one half, and per block takes `ptcl_posterior_temp` per particle, calls
`score_block_posterior` once against all the references, and then per particle `gen_shiftmap`, `shiftmap_mode`
and `shiftmap_shift` over its pool. `setup_shiftmaps` is called inside every fill, before the blocks.

**What the code will need that the plan's list does not name** (found while reading; Phase 1 takes each as a
mirrored procedure under SIMPLE's name or records it as an addition, and none changes a decision):
- the half of a particle: SIMPLE's `set_eo( self, iptcl, is_even )`, called before `set_ptcl_pft` in production;
- the shell weights: SIMPLE's `assign_sigma2_noise( self, sigma2_noise, spectra_gen )` with
  `sigma2_noise(shell, half)`, from which `memoize_sigma2_weights` makes `k / sigma2`; the fixture has the
  weights themselves;
- the CTF of a particle: SIMPLE fills `ctfmats` in `create_polar_absctfmats`; its setter
  `set_ptcl_ctfmat( self, iptcl, ctfmat )` is a private test hook. The fixture's memos need the CTF ring;
- the keyed variates: SIMPLE draws inside the kernel from `set_rnd_scope( self, scope )`; the toy is handed the
  variates of each pair by the fixture today;
- the tile plan (`bt`, `rt`), which no SIMPLE procedure or `params` member carries: an addition;
- the driver's constructor: decision 2 names `new`, SIMPLE's is `new_pipeline`. The policy's rule `mirror` would
  refuse a ledger line that maps the toy's `new` to SIMPLE's `new_pipeline`.

**What it means, in short.** The base is measured and every later phase has an exact target: 24 digest lines
and the three parts' that must not move, the three suites' counts, and two bounds per split. Three things for the phases to come.
The time bound at one process is 0.07 s wide on 6.1 s; the unchanged code met it in two repeats, and the
refactored code has no room for an extra pass over the data. The footprint bound is 0.6 MB wide on 21 GB: the
calculator cannot hold the references in SIMPLE's shape beside the memos the fixture holds today (2 halves of
`182 x 61 x 10,000` complex values are 1.78e9 B), so the memos must move into the calculator and not be kept
twice. And the six-process split does not fit this machine: it is not run before, so it is not judged after.

### Phase 1, the calculator and the dense route (2026-11-24, 20:17 to 21:10, done)

Machine and toolchain as in Phase 0; base commit `441873c` with Phase 0's working tree; the rulings file was
empty. Paths below are under `/Users/hael/agent_runs/mlxf_toy_arch/scratch`.

**Files changed.**
- New: `src/test/mlxf_toy_polarft_calc.f90` and its submodules `mlxf_toy_polarft_core.f90`, `_memo.f90`,
  `_block.f90`; `src/test/mlxf_toy_polarft_workspace.f90` with `_lifecycle.f90` and `_score.f90` (the dense
  part); `src/test/mlxf_toy_polarft_calc_tester.f90`; `src/test/mlxf_oracle_polar.f90` (the oracle, renamed,
  content unchanged); `scripts/toy_mirror.txt`.
- Removed: `src/test/mlxf_kernel_polar_oracle.f90`, `src/test/mlxf_kernel_polar_table_tester.f90`.
- Edited: `src/test/mlxf_bench_polar_table.f90` (the dense suites on the calculator), `src/test/mlxf_test_defs.f90`
  (the records `parameters`, `polarft_tile_spec`, `polarft_block_spec`; `POLARFT_STAGE_N`),
  `src/test/mlxf_test_registry.f90` (the suite `polarft_calc`), `src/test/mlxf_kernel_polar_table_shiftmap_tester.f90`
  (the oracle's module name), `scripts/check_rules.py` (rule `mirror`, the arity exemption), this note.
- Kept until the maps move (Phase 2): `src/test/mlxf_kernel_polar_table.f90` with its three submodules, which
  the shift-map tester and the benchmark's `shiftmap` suite still use. Its dense code exists twice for one
  phase.

**Exit items.**

| Item | How it was met | Evidence |
| --- | --- | --- |
| Decision 9 for the dense entries, both devices | All 24 digest lines of Phase 0 came back identical with the Release build: the 15 of `accuracy` (CPU and GPU), `time` on the GPU and on the CPU device, `profile`, `overlap` (2), and the 4 of `shiftmap`, which still runs on the old workspace. The three parts' digests of the 3-process split are identical too | `keep/phase1/digests_a/` (`logs/p1_digests_a.log`, `logs/p1_digests_cpu.log`); `keep/phase1/check_final/c1_n3_a1/summary.txt` |
| `polar_table`'s counts | The suite, now `polarft_calc`: 107 on the CPU and 99 on the GPU, Debug and Release (*measured*); `polar_shiftmap` 397 and `polar_shiftmap_accuracy` 24 per device; `unit_kernels` 993. The CPU calibration it reports is the base's to the last digit (`e_cpu = 2.3972463973750171E-07`) | `keep/phase1/{Debug,Release}_kernels_*.log` |
| The four planted violations fail | A binding missing from the ledger, a mirrored line whose toy name differs, an addition without a reason and an addition with six dummies each make `scripts/check_rules.py` exit 1 with a line that names the fault; the unchanged tree, where `score_block_posterior` has ten dummies, passes. Five more cases fail as they should: `score_block_posterior` relabelled an addition (arity), no ledger, a header without the commit, a line that names nothing, a mirrored line beside another module | `keep/phase1/planted_summary.log`, `keep/phase1/planted/<case>.log`, `keep/phase1/planted.sh` |
| Both builds, the gate, the formatters | Debug and Release from scratch with `MLXF_WERROR=ON`: no compiler warning, fast gate 8 of 8, `scripts/check_tree.sh` passes (it warns that 9 new sources are untracked, as nothing is committed); both formatters leave the 13 touched Fortran files unchanged | `keep/phase1/final_build_{Debug,Release}.log` |

**Reported: the baseline's splits on this phase's code** (*measured*, one run, load before 1.27 and 1.91; not
the judgement of decision 11, which is Phase 4's).

| Split | Go to last exit | Summed peak footprint | Phase 0's bound |
| --- | --- | --- | --- |
| 1 by 30 threads | 6.001 s | 20,896,167,208 B | 6.161 s and 21,130,655,136 B |
| 3 by 10 threads | 6.265 s | 60,445,907,488 B | 7.287 s and 60,735,036,488 B |

**What was found.**
- **The benchmark's reference rings are double precision.** Rounded to single, as a `complex(real32)`
  `set_ref_pft` would receive them, they move all 15 accuracy digests (*measured*: a
  patched copy of the tree; `keep/phase1/exp_round.log`, `exp_round.sh`). The tester's rings are single precision already.
- **On this macOS a large array that is released stays in the process's footprint.** `vmmap` lists it as
  `Malloc Large (empty)`, still dirty. A first form of the calculator staged every raw section and released
  them after memoization: 4.4e9 B were still counted when the process waited for go (8.4e9 B against the
  base's 4.1e9 B), and the peak was 22,993,435,504 B, above the bound (*measured*:
  `keep/phase1/footprint/before_fix_timeline/`; after the fix 4.0e9 B at go, `after_fix_at_go/vmmap.txt`).
  The 0.6 MB bound therefore forbids any large transient that the base did not have, not only resident copies.
- **The memos keep their bits when the calculator makes them.** Its transform is its own code (the benchmark's
  ring sum and the DFT factors' formula); it shares nothing with the oracle module.

**Decisions taken under delegation.**
1. **The benchmark's dense suites move onto the calculator in this phase,** and the file table's row says so.
   Reason: the gate asks for decision 9 on the dense entries, and only the benchmark prints the digests. Its
   `shiftmap` suite stays on the old workspace until Phase 2; the driver comes in Phase 3.
2. **`set_ref_pft` takes `complex(real64)`,** a declared difference of kind. Reason: the first finding above;
   decision 9 forbids a moved digest, and decision 3 lets a dummy differ when the difference is declared. The
   other way to settle it is the maintainer's: round the benchmark's rings and freeze new digests.
3. **`banks` and `l_bank` stay in `score_block_posterior`,** against decision 3's list of dropped dummies.
   Reason: the dense tester's fixture scores four particles from seed banks, and decision 10 fixes its counts.
   The procedure carries SIMPLE's full list of nine dummies; the banks are handed in as memos, as in SIMPLE.
4. **`ws` is an allocatable array of two workspaces, one per reference parity,** created in `new` and released
   in `kill`. Reason: the old type is one half's workspace, and SIMPLE's memos carry the parity as their last
   dimension.
5. **`memoize_ref_bins` (SIMPLE's name and list) makes the device's tiles; `memoize_refs` makes the host
   memos.** Decision 4 put the device layout into `memoize_refs`. Reason: SIMPLE builds the block scorer's
   layout in `memoize_ref_bins`, and with the two apart the launcher's time from go holds the same work as on
   the base (the upload and the scoring), while the transforms stay before go, as the synthesis did.
6. **The setters stage `POLARFT_STAGE_N` = 64 sections and memoize a full staging at once;** the raw
   references and particles are not kept. Reason: the second finding. What follows from it: a particle's CTF
   is set before its section (`set_ptcl_ctfmat`, then `set_ptcl_pft`), and `memoize_refs` and
   `memoize_ptcls` finish what is staged. A block is refused while references are set and not memoized.
7. **Mirrored beyond the plan's list:** `set_eo`, `set_ptcl_ctfmat` (a private test hook in SIMPLE),
   `memoize_ref_bins`. **Additions,** each with its reason in the ledger: `set_sigma2_weights`, `set_tile_plan`,
   `kill_ref_bins`, `ref_bins_current`, `message`, `set_block_variates` (takes the array over, no copy),
   `set_block_banks`, `set_block_options`, `submit_block`, `collect_block`, `block_rows`, `stage_seconds`.
8. **The weighted square sum is made in `memoize_ptcls`** from the shell sums `set_ptcl_pft` memoizes; SIMPLE
   makes it in `set_ptcl_pft`. Reason: it then does not depend on the order of `set_eo`, the weights and the
   section.
9. **A refusal** sets the reason that `message()` returns (empty after a call that was carried out) and leaves
   `dists` at `huge` and `irots` at 1. SIMPLE stops in these places.
10. **The suite is `polarft_calc`** (`run_all_polarft_calc_tests`, `test=unit_kernels suite=polarft_calc`).
    Its checks are the old tester's, one for one. The refusals that had no meaning without the old records
    were replaced by the calculator's own, the count unchanged: reference bins not made or not current
    (SIMPLE's `ref_gen_bins`), particles set and not memoized (SIMPLE's `ptcl_gen_memo`), a block of both
    halves, seed banks of another shape, a particle whose section is zero, a particle index outside the range.
11. **The record `parameters` has one member so far,** `pftsz`, the only one this phase's code reads.
12. **Rule `mirror` fails on five more faults than the policy names:** a line that names nothing in the code,
    a name listed twice, a mirrored line whose module is not `mlxf_toy_<stem>` beside `simple_<stem>`, a header
    without the SIMPLE commit, and toy modules without a ledger. It lists public bindings; a private binding
    needs no line.
13. **The benchmark hands the rings to the calculator as it makes them** in `time`, `profile` and `overlap`
    (`make_data(..., pftc=)`), and keeps them only in `accuracy`. Reason: the second finding. The column
    `host_cpu_s` now holds the variates' seconds only: the entries are copied once, into the table, inside the
    collection.

**Differences from SIMPLE so far** (for the kernel-families note and the report):
- `new`: no `nmany_refs`, `fftw_measure`; `params` is the record `parameters`; `interpklim` is `kfromto(2)`.
- `set_ref_pft`: `pft` in `complex(real64)`; `set_ptcl_ctfmat` is public; `memoize_refs` has no `eulspace`.
- `pfts_refs`, `pfts_ptcls` and `ctfmats` are stagings of 64 sections, not arrays of every section; the CTF
  comes before the section.
- The references of a block are all of them, in order (`irefs` = 1..`nrefs`): another list is refused. K3
  owns arbitrary lists.
- A block is all the particles handed in, of one half, of any number; SIMPLE's is at most 16 and is tiled over
  references by 32. The toy's tile plan is `set_tile_plan`'s.
- The variates come from the fixture (`set_block_variates`); SIMPLE draws them inside from `set_rnd_scope`.
- The shell weights come as `k / sigma2` (`set_sigma2_weights`); SIMPLE is given the spectra.
- Refusals with a message instead of hard errors; a `final` procedure, which the house rule asks of a type
  that owns MLX state.

**Left as it is, for the maintainer.** `scripts/check_tree.sh` lists the rules of `check_rules.py` in a comment,
without `mirror`: the file is not in the table and decision 12 allows no row outside `src/test/`.

**What it means, in short.** The dense route now reads as SIMPLE's does: `new`, the setters, `memoize_refs`,
`memoize_ptcls`, `memoize_ref_bins`, `score_block_posterior`, with every MLX handle in `ws`. Nothing the device
computes changed: every digest is the base's, on both devices. The baseline's two splits are inside Phase 0's
bounds with about 0.23e9 B to spare at one process, because the block's memos are no longer copied on the way
to the workspace. Two things the maintainer may overturn at the review: the double-precision `set_ref_pft`,
and the staging of 64 sections with its rule that the CTF comes first.

### Phase 2, the shift maps (2026-11-24, 21:05 to 21:40, done)

Machine and toolchain as in Phase 0; base commit `441873c` with the working tree of Phases 0 and 1; the rulings
file was empty. Paths below are under `/Users/hael/agent_runs/mlxf_toy_arch/scratch`.

**Files changed.**
- New: `src/test/mlxf_toy_polarft_shiftmap.f90` (the calculator's submodule), `src/test/mlxf_toy_polarft_workspace_shiftmap.f90`
  (the workspace's map part, the old submodule's device code unchanged), `src/test/mlxf_toy_polarft_shiftmap_tester.f90`.
- Removed, their last use gone: `src/test/mlxf_kernel_polar_table.f90`, `_lifecycle.f90`, `_score.f90`,
  `_shiftmap.f90`, `_shiftmap_tester.f90`. Both builds pass without them; `rg mlxf_kernel_ src test scripts`
  finds nothing.
- Edited: `src/test/mlxf_toy_polarft_calc.f90`, `_core.f90`, `_memo.f90`, `mlxf_toy_polarft_workspace.f90`,
  `_lifecycle.f90`, `mlxf_toy_polarft_calc_tester.f90` (the weights' kind), `src/test/mlxf_bench_polar_table.f90`
  (the `shiftmap` suite on the calculator), `src/test/mlxf_test_defs.f90` (`SHIFTMAP_FULL`, `_SCREEN`, `_WINDOW`,
  `NSHIFTMAPS`; `parameters%box`; the records `polarft_map_spec`, `polarft_map_block`; `polar_map_spec` and
  `polar_map_block` removed), `src/test/mlxf_test_registry.f90`, `scripts/toy_mirror.txt`, this note.

**Exit items.**

| Item | How it was met | Evidence |
| --- | --- | --- |
| Decision 9 for the map results | The four `shiftmap` digests (maps `window` and `screen`, GPU and CPU device) are Phase 0's, now through `new_shiftmap`, `gen_shiftmap` and `shiftmap_mode`; the other 20 digest lines are unchanged too, and so are the three parts' | `keep/phase2/digests_a/` (`keep/phase2/p2_digests_a.log`, `p2_digests_cpu.log`); `keep/phase2/check_final/c1_n3_a1/summary.txt` |
| `polar_shiftmap` 397, `polar_shiftmap_accuracy` 24 | Per device, Debug and Release (*measured*); `polarft_calc` 107 and 99; `unit_kernels` 993. Every error the suite reports is the base's to the digit shown (largest map error 5.077E-07, zero radius 1.287E-06, evidence 8.315E-07) | `keep/phase2/{Debug,Release}_kernels_*.log` against `keep/phase1/` |
| Both builds, the gate, the formatters | Debug and Release from scratch with `MLXF_WERROR=ON`: no compiler warning, fast gate 8 of 8, `scripts/check_tree.sh` passes; both formatters leave the touched Fortran files unchanged; the ten planted cases of rules `mirror` and `arity` behave as in Phase 1 on the longer ledger | `keep/phase2/final_build_{Debug,Release}.log`, `keep/phase2/planted_summary.log` |

**Reported: the baseline's splits on this phase's code** (*measured*, one run, load before 1.80 and 1.98).

| Split | Go to last exit | Summed peak footprint | Phase 0's bound |
| --- | --- | --- | --- |
| 1 by 30 threads | 6.006 s | 20,896,249,416 B | 6.161 s and 21,130,655,136 B |
| 3 by 10 threads | 6.369 s | 60,445,531,112 B | 7.287 s and 60,735,036,488 B |

The `shiftmap` suite on the GPU: window 0.408 s and screen 1.663 s for the 32,000 maps (Phase 0: 0.430 and
1.692 s; one run each, reported).

**What was found.**
- **The grid file's maps are not SIMPLE's rule's.** The file gives the outer radius to four decimals (4.3548
  and 14.5161 pixels), and the fixture's radii are `(i-1) rho_max / (nrho-1)`. SIMPLE's `setup_shiftmaps` makes
  radii `(i-1) box / kstop / 4`: other bits, and for the window `floor(4.3548 / 1.45161...) + 1` = 3 radii where
  the file has 4 (*derived*). A map built by the rule cannot keep the digests.
- **The prior does not belong to the map.** The old workspace took the prior's weight when the map was
  prepared; SIMPLE's `shiftmap_mode` takes it with each read. The device's functions already had it as an
  input, so it moved without a change to a graph.
- **The maps read the shell weights in double precision** (SIMPLE's `sigma2_wk8`), and the map tester's weights
  are not single-precision numbers.

**Decisions taken under delegation.**
1. **`new_shiftmap( self, imap, rho, nalpha, kstop )` is mirrored and public** (private in SIMPLE), and the
   fixtures hand their grids in through it. `setup_shiftmaps` has SIMPLE's list and SIMPLE's rule and calls
   it. Reason: the first finding. The two maps of the benchmark are `SHIFTMAP_WINDOW` and `SHIFTMAP_SCREEN`;
   the tester builds its own grid over every shell as `SHIFTMAP_FULL`.
2. **`temp_phys` stays in `shiftmap_mode`,** against decision 3's list. Reason: the width is taken at the
   physical temperature, which the fixtures give beside the tempered one; dividing the tempered one back does
   not return its bits. The procedure carries SIMPLE's ten dummies, with `temp`, the results, `temp_phys`,
   `sdev` and `width_cutoff` of rank 1 over the pairs.
3. **`gen_shiftmap` records the block's pairs; the device builds the maps when `shiftmap_mode` reads them.**
   Reason: the old code built, reduced and copied tile by tile in one call, and keeping that order keeps the
   graphs and the memory of a tile. The pairs are every particle's candidates in turn, the same number for
   each, of one half: another list is refused.
4. **`kill_shiftmap` is mirrored and public** (private in SIMPLE). **Additions:** `set_shiftmap_options` (the
   particles of a graph, every map, the evidence, the profile), `shiftmap_evidence`, `shiftmap_maps`,
   `shiftmap_order`, `shiftmap_term_counts`, `shiftmap_seconds`; on the workspace `prepare_maps`, `score_maps`,
   `kill_map`, `kill_maps`, `map_order`, `map_term_counts`, `map_seconds`.
5. **`set_sigma2_weights` takes the weights in `real(real64)`** and the block scorer reads them rounded to
   single precision. Reason: the third finding; the dense fixtures' weights are single-precision numbers, so
   nothing of theirs moves.
6. **A map is stale, and its modes refused, when the references were memoized again or the weights changed**
   after it was made; `new_shiftmap` on the same references replaces it. A refused `new_shiftmap` leaves no
   such map. Making the reference bins no longer drops the maps.
7. **The record `parameters` gains `box`,** SIMPLE's member behind `ldim`: the pixels the shifts are in.
8. **The tester's refusals** that named the old records were replaced by the calculator's own, the count
   unchanged: maps of both halves, particles set and not memoized, a candidate outside the references, a band
   beyond the shells, no direction, no such map, references memoized again. The 100 life cycles each set up
   the two coarse maps with `setup_shiftmaps` and read the screen's modes; the two assertions per cycle that
   the old preparation made are kept.
9. **The benchmark's `shiftmap` suite** feeds one calculator and makes one map at a time, with the reference
   bins made first, as the old suite prepared the dense workspace first. Its column `host_bytes` is now the
   calculator's memos (the block's copies of the particle memos are gone).

**Differences from SIMPLE added by this phase** (for the kernel-families note and the report):
- `new_shiftmap` and `kill_shiftmap` are public; a map's grid may be handed in instead of set up by rule.
- `gen_shiftmap` and `shiftmap_mode` take the pairs of a block (rank 1), every particle's candidates in turn;
  SIMPLE's take one pair and work on the calling thread's buffers.
- The maps are built when the modes are read; SIMPLE's `gen_shiftmap` fills the map.
- No `shiftmap_shift`, `shiftmap_draw` or in-cell refinement; the full map and the evidence come through
  additions.
- `sdev` is -1 for a pair above `width_cutoff`, as in SIMPLE, and for every pair of a refused call.

**For Phase 3.** `setup_shiftmaps` is exercised only inside the life-cycle check here, because the counts are
fixed: the driver's tester, whose count is free, should hold a map set up by SIMPLE's rule to the oracle. The
driver cannot keep the benchmark's map digests on `setup_shiftmaps` (the first finding): it needs the
fixture's grid through `new_shiftmap`, a declared difference.

**What it means, in short.** No `mlxf_kernel_` file is left: the toy is the calculator, its workspace, the
oracle and their testers. The maps are read as in SIMPLE (`gen_shiftmap`, then `shiftmap_mode` with the
temperature and the prior), and every result is the base's bit for bit. The dense baseline is unchanged by
this phase.

### Phase 3, the driver and the benchmark (2026-11-24, 21:35 to 22:10, done)

Machine and toolchain as in Phase 0; base commit `441873c` with the working tree of Phases 0 to 2; the rulings
file was empty. Paths below are under `/Users/hael/agent_runs/mlxf_toy_arch/scratch`.

**Files changed.**
- New: `src/test/mlxf_toy_eul_prob_tab.f90` (the driver), `src/test/mlxf_toy_eul_prob_tab_tester.f90` (the suite
  `eul_prob_tab`).
- Edited: `src/test/mlxf_bench_polar_table.f90` (every suite through the driver; the per-suite key check),
  `src/test/mlxf_toy_polarft_calc.f90`, `_core.f90`, `_shiftmap.f90` (four mirrored inquiries and one addition),
  `src/test/mlxf_test_defs.f90` (`parameters` gains `nthr`, `prob_beta`, `shift_sigma`, `smpd`, `trs`),
  `src/test/mlxf_test_registry.f90`, `src/test/test.inf`, `scripts/toy_mirror.txt`, this note.
- No old file was left to remove: the last `mlxf_kernel_` files went in Phase 2. `test/CMakeLists.txt` names no
  removed file and is unchanged.

**Exit items.**

| Item | How it was met | Evidence |
| --- | --- | --- |
| Decision 9 for every digest through the driver | All 24 digest lines of Phase 0 are identical with every suite calling `fill_tab_range`: the 15 of `accuracy`, `time` on both devices, `profile`, `overlap` (2), `shiftmap` (4); the three parts' digests of the 3-process split too | `keep/phase3/digests_a/` (`keep/phase3/p3_digests_a.log`, `p3_digests_cpu.log`); `keep/phase3/check_final/c1_n3_a1/summary.txt` |
| The accuracy suite inside its frozen bounds | 155 checks pass on both devices; row error 6.654E-07 (CPU) and 6.514E-07 (GPU), no rotation differing in 64,000 pairs, as on the base (*measured*) | `keep/phase3/digests_a/accuracy.log` |
| The key check's planted violation fails | `suite=time contraction=2` stops with status 2 and "suite=time does not read contraction=2"; so do a key of another suite (`suite=accuracy nthr=4`, `suite=shiftmap outer=3`, `suite=profile go=x`) and a word without `=`; a run with valid keys passes | `keep/phase3/keycheck/` |
| No `mlxf_kernel_` name left | `rg mlxf_kernel_ src test scripts` finds nothing | this entry |
| Counts (decision 10) | `polarft_calc` 107 and 99, `polar_shiftmap` 397, `polar_shiftmap_accuracy` 24, per device, Debug and Release. The driver's new suite `eul_prob_tab`: **35 checks per device** (*measured*, recorded here as decision 10 asks). `unit_kernels` on both devices: 1,063 = 993 + 70 | `keep/phase3/{Debug,Release}_kernels_*.log` |
| Both builds, the gate, the formatters | Debug and Release from scratch with `MLXF_WERROR=ON`: no compiler warning, fast gate 8 of 8 (13.4 and 13.6 s of its 60), `scripts/check_tree.sh` passes; both formatters leave the touched Fortran files unchanged; the ten planted cases of rules `mirror` and `arity` behave on the longer ledger | `keep/phase3/final_build_{Debug,Release}.log`, `keep/phase3/planted_summary.log` |

**Reported: the baseline's splits on this phase's code** (*measured*, one run, load before 1.84 and 1.94).

| Split | Go to last exit | Summed peak footprint | Phase 0's bound |
| --- | --- | --- | --- |
| 1 by 30 threads | 6.001 s | 20,813,543,032 B | 6.161 s and 21,130,655,136 B |
| 3 by 10 threads | 6.259 s | 60,321,864,248 B | 7.287 s and 60,735,036,488 B |

**The driver, as built.** `eul_prob_tab` holds a pointer to the calculator, the parameters, the particles
(`pinds`), their temperatures and the batch's rows; it holds no MLX state. `fill_tab_range( self, i_first,
i_last )` has SIMPLE's steps as contained procedures: `cut_blocks` (the range's particles, the even half
first, in blocks of one half), `process_block` (a block's keyed variates made by the host team, the block
queued), the block's collection into the batch's rows, and `finish_particle_map` (the block's candidate pairs
generated and their modes read). The rows are kept in the batch's order, so that a block is collected into a
contiguous part of the table without a copy.

**Decisions taken under delegation.**
1. **The constructor is `new_pipeline( self, params, pftc, pinds )`,** SIMPLE's name, not decision 2's `new`.
   Reason: rule `mirror` refuses a mirrored line whose name differs, and SIMPLE's `eul_prob_tab` has no `new`.
   SIMPLE's `build` is the calculator here (the toy has no builder), and `block_memo` is dropped: the
   construction makes the reference bins unless they are current.
2. **The driver draws the keyed variates itself,** from `set_draw_keys( seed, ref_full )`, as SIMPLE's fill
   takes its scope and passes each reference's full index. Its generator is its own code; the driver's tester
   holds its entries, bit for bit, to the calculator scoring the same blocks with the oracle module's
   variates.
3. **The maps' temperatures are SIMPLE's:** tempered `prob_beta` times `pi wsq_band / (2 pftsz)` from the
   calculator's `wsqsum_ptcl_band`, the physical one the tempered one over `prob_beta`. The benchmark no longer
   computes them, and the map digests did not move. `parameters%prob_beta` is `real(real64)` (SIMPLE's is
   single precision), the value the fixture used.
4. **What the fixture still hands in, each through an addition:** the particles' dense temperatures
   (`set_temps`), the candidates (`set_candidates`, decision 6), the width cutoffs of the benchmark's width
   modes (`set_width_cutoffs`), and its own map (`use_shiftmap( imap, prior_w )`). Without `use_shiftmap` the
   fill calls `setup_shiftmaps` with SIMPLE's arguments (`shift_sigma / smpd`, the disk of three sigma bounded
   by the box, `trs`) and reads every particle on the window; SIMPLE chooses per particle between the window
   and the screen.
5. **`set_fill_stages( dense, maps )`:** the benchmark's `shiftmap` suite runs the maps' stage alone, so that
   its rows stay comparable with the M5 records; SIMPLE's fill always runs both, and so does the default.
6. **`set_fill_options( block_nb, nslots, rows, profile )`:** the particles of a block (SIMPLE's is at most
   16), one block or two in flight, the full rows, the profile. With two in flight the overlap runs across
   the halves' boundary, which the old benchmark did not do; the entries are the same.
7. **The calculator gains** the mirrored `get_nrefs`, `get_pftsz`, `ptcl_iseven`, `wsqsum_ptcl_band` and the
   addition `shiftmap_kstop` (the band's last shell of a map the fixture handed in).
8. **The driver's tester** (count free, decision 10) holds a map set up by SIMPLE's rule to the direct
   residual on the grid the rule gives, as Phase 2 asked: largest error of a returned loss 1.808E-07 against
   the cap 1E-04 (*measured*). Its first run failed two GPU checks that were the test's mistake: blocks of one
   particle move a particle to another place of its tile, which GPU bits depend on (the old tester kept places
   as well). The checks now keep tile places; no bound was touched.
9. **The key lists** are one line per suite in the benchmark; `test` and `suite` belong to the executable.
   `suite=shiftmap` keeps its own message for `nthr=`.
10. **`src/test/test.inf`** now names the toys, their oracle and the benchmark.

**Differences from SIMPLE added by this phase** (for the kernel-families note and the report):
- `new_pipeline` takes the calculator where SIMPLE takes its builder; no `block_memo`.
- The fill is one thread walking the blocks, one or two in flight on the device; SIMPLE's is an OpenMP loop
  over the blocks.
- `finish_particle_map` works on a block's particles at once and has no pool selection, no in-cell
  refinement and no row replacement (decision 6; K4 owns them); `seed_particle_map` has nothing left to do and
  is not there.
- The blocks are of `block_nb` particles; the temperatures of the dense draw, the candidates and (when given)
  the map come from the fixture.
- No assignment (`open_assignment`, `assign_batch`), no states, no posterior diagnostics.

**What it means, in short.** The call tree now reads as SIMPLE's: a tester or the benchmark makes a
`polarft_calc`, sets and memoizes it, makes an `eul_prob_tab` with `new_pipeline` and calls `fill_tab_range`;
only the calculator touches `ws`. Every number the benchmark printed on the base it prints again, bit for
bit, and the baseline's splits have more room than before (0.32e9 B at one process). What is left is Phase 4:
the baseline twice, the documents and the report.

### Phase 4, the baseline again and the report (2026-11-24, 22:06 to 22:30, done)

Machine and toolchain as in Phase 0; base commit `441873c` with the working tree of Phases 0 to 3; the rulings
file was empty. No source file changed in this phase: the baseline ran on Phase 3's Release build. Paths below
are under `/Users/hael/agent_runs/mlxf_toy_arch/scratch`.

**Files changed.** `doc/policies/toy_example_policy.md` (section 6),
`doc/implementation_notes/planned/mlxf_kernel_families.md` (section 2a's row for family A; in section 3 "What
exists", "The seam" and "Differences from SIMPLE"), `doc/implementation_notes/planned/mlxf_roadmap.md` (the
rank 0b row), `doc/implementation_notes/README.md` (the index), `doc/history/2026-11.md` (the entry),
`README.md` (the status and the table's row for `src/test/`),
`doc/implementation_notes/completed/mlxf_toy_architecture_report.md` (new), this note (the status line and
this entry).

**Decision 11, judged** (*measured*; GPU, full precision, tile plan 64 by 250; the launcher waited for a
one-minute load of at most 2 before every split: 1.87 to 1.99).

| Split | Run | Go to last exit, s | Summed rate, pairs/s | Summed peak footprint, B | Largest process, B | Lowest free, B | Lowest available, B |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 by 30 threads | r1 | 6.003 | 1.76784e7 | 20,813,411,624 | the same | 40.34e9 | 63.24e9 |
| 1 by 30 threads | r2 | 5.997 | 1.76398e7 | 20,813,444,392 | the same | 38.71e9 | 63.37e9 |
| 3 by 10 threads | r1 | 6.362 | 1.71899e7 | 60,321,159,904 | 20,107,162,416 | 0.61e9 | 33.28e9 |
| 3 by 10 threads | r2 | 6.421 | 1.81642e7 | 60,319,669,224 | 20,107,359,384 | 0.52e9 | 34.14e9 |
| 6 by 5 threads | r1, r2 | not run: the guard predicts 119.6e9 B, above 82.46e9 B | | | | | |

| Split | Bound of Phase 0 | After, the worse of the two runs | Verdict |
| --- | --- | --- | --- |
| 1 | 6.161 s; 21,130,655,136 B | 6.003 s; 20,813,444,392 B | holds |
| 3 | 7.287 s; 60,735,036,488 B | 6.421 s; 60,321,159,904 B | holds |
| 6 | not judged | not run | |

Two one-process attempts of r1 were discarded by the launcher and repeated (decision 14: another
`mlxf_test_exec`, `cmake` or `gfortran` process was seen on the machine during the attempt; it was not this
run's). Their rows are in the series table with the status `discarded`: 6.019 and 6.045 s, 20,813,952,560 and
20,813,624,592 B, inside the bound too. Every process printed the base's digest (`3457E99553A08BFD` whole,
`B69FA174DE317D3C`, `4BFC1DA8533AB2F5`, `8921689A9191A114` for the parts).

**Reported, not gated** (the roadmap's two conditions, after the refactoring):
- The total rate at 3 processes is 0.972 (r1) and 1.030 (r2) of one process's (*derived*): the first condition
  is not met.
- The summed footprint at 3 processes is 60.32e9 B, above 51.5e9 B: **the second condition is met,** as on
  the base.

**Exit items.**

| Item | How it was met | Evidence |
| --- | --- | --- |
| The bound holds | The table above | `keep/phase4/baseline/run_parts.tsv`, `keep/phase4/baseline/r<n>_n<split>_a<k>/`, `keep/phase4/p4_baseline_r{1,2}.log` |
| The report exists | `doc/implementation_notes/completed/mlxf_toy_architecture_report.md`, in the order of the how-to's section 8, with the seam's table, the baseline before and after at each split, the two conditions, the ledger's counts (25 mirrored lines, 46 additions) and a commit message | the file |
| `scripts/check_tree.sh` passes | It does; Debug and Release were built from scratch once more with `MLXF_WERROR=ON`: no compiler warning, fast gate 8 of 8; `unit_kernels` 1,063 | `keep/phase4/final_build_{Debug,Release}.log`, `keep/phase4/Release_kernels_all.log` |
| `git status` shows only file-table paths | 36 paths, each in the table (the `mlxf_toy_*.f90` files under its pattern); no file under `src/core/` or `src/defs/` | this entry |

**Acceptance (section 6).** Decision 9: 24 digests identical after Phases 1, 2 and 3. Decision 10: the three
suites' counts unchanged; the driver's suite has 35 checks per device. Decision 11: the bound holds at the
two splits that were run. The ledger lists every public type and binding of the three toy modules (rule
`mirror`). Reported: the seam's table, the two conditions, the lines of code (5,522 before, 8,513 after), the
suites' elapsed times; all in the report.

**Decisions taken under delegation.**
1. **The plan stays in `planned/`** with its status line changed to delivered. Reason: the file table names it
   there and has no row for a move; it moves with the maintainer's commit.
2. **`CLAUDE.md` and `scripts/check_tree.sh` are not edited.** Both describe things this run changed (the
   `src/test/` line; the list of rules in a comment). Reason: neither is in the table, and decision 12 allows
   new rows under `src/test/` only. The report proposes the wording.
3. **The kernel-families note carries the seam beside the differences,** in section 3. Reason: section 2a says
   each toy's plan fixes the seam, and the families' later plans will read it there.
4. **The closing builds were run although no source changed,** as section 5 asks of every phase.

**What it means, in short.** The run is complete: the toy mirrors SIMPLE's calculator and table driver, proves
by 24 unchanged digests that it computes what it did, and costs no time and 0.3e9 B less memory per process.
The measurement the roadmap asked for is in: three part processes share the GPU without loss and hold 60e9 B
between them, and six would not fit this machine. What waits is the maintainer's read.
