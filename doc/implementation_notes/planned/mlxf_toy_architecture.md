# The polar toy as a miniature of SIMPLE's `polarft_calc` (run `mlxf_toy_arch`, on the M5 Ultra)

Status, 2026-11-24: planned; the roadmap's rank 0b. The maintainer told the batch to proceed, so decisions 1 to
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
| `src/test/mlxf_bench_polar_table.f90` | keys, digest; then the suites on the driver | 0, 3 |
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
