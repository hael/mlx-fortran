# Report: K2, the polar projection (B1) as a toy `projector`, and the protected-update probe (run `mlxf_kernel_k2`)

Run on the M5 Ultra on 2026-11-25, 11:54 to 13:20, in the session, in a scratch copy of the maintainer's tree: base
`6a4d5f9` plus the maintainer's uncommitted working tree of 2026-11-25 with K1's kept result and K8's Phase 0
(ruling R0; 65 lines of `git status`, checksums in the run's `scratch/keep/phase0/base_checksums.txt`). Plan:
[`mlxf_kernel_k2.md`](../planned/mlxf_kernel_k2.md), Phases 0 to 6, every phase run. SIMPLE read at `d354efee2`.
Rulings: R0 only. Nothing is committed. Evidence:
`/private/tmp/claude-501/-Users-hael--claude-spares-spare-j03Dq7/b43a4d7a-d6e9-44b1-9278-f4eb389a9694/scratchpad/k2_work/scratch/keep/phase{0..5}/`;
the journal is the run's `state/journal.md`.

## 1. What was learned

**The fused gather is kept: it makes the reprojection of a state 24 times faster** (*measured*, decision 19, each
form at its canonical configuration frozen before the verdict runs: graph 64 directions per tile; fused all 2,500
directions, 64 threads per group):

| Measure | Graph | Fused | Ratio (rule: 1.30) |
| --- | --- | --- | --- |
| One process, the driver's median pass (two invocations) | 0.9765, 0.9652 s | 0.0397, 0.0395 s | **24.6, 24.4** |
| One process, go to the last exit | 5.437, 5.383 s | 1.620, 1.619 s | 3.36, 3.32 |
| Three processes, go to the last exit | 10.700, 12.696 s | 2.031, 2.014 s | **5.27, 6.30** |
| Six processes, go to the last exit (reported) | 21.061 s | 2.690 s | 7.83 |

The driver is SIMPLE's per-parity loop (`new`, `set_rmat`, `pad_fft`, `expand_cmat`, `vol_pad2ref_pfts_opt`,
`kill`) from the two host volumes to both banks evaluated on the device. In the fused driver the projection of
55.5 million samples takes 0.006 s; the pad and transform (0.019 s) and the expansion (0.0095 s) are 73 % of it.
The graph form's projection is 0.92 s.

**The device route is kept: the references go from the volume to family A's tiles without leaving the device, and
the chain between the banks and the reference bins falls from 1.05 s to 0.03 s** (32.5 and 35.1 times, decision
11; the host route's 4.06e10 double-precision multiply-adds of the ring transforms and the packing become float32
FFTs and concatenations on the device). The routes' dense rows differ by at most 1.9e-7 of the largest |d|.

**Both forms agree with the double-precision oracle.** Frozen on seed 1 before the judged seeds (*measured*):
`PROJ_FIXTURE_ERR` = 1.503e-6 of a sample's 27 terms (the phantom's edge queries on the GPU, where its spectrum is
smallest beside the transform's rounding), `PROJ_CHAIN_ERR_HOST` = 3.75e-7 and `PROJ_CHAIN_ERR_DEVICE` = 4.17e-7 of
a row's largest |d|, `PROJ_BENCH_ERR` = 1.45e-5 (the float32 coordinates near 124; the oracle reads the device's own
transform). Seeds 2 and 3 pass at most 6.5e-7, 3.9e-7 and 1.35e-5 against twice those numbers. The forms differ by
at most 4.8e-7 of a sample's terms. Every form, route and tile shape is bit for bit repeatable; different tile
shapes of a form give the same bits.

**Every control has teeth.** Nineteen plants (ten on the graph form, seven on the kernel's source, the parity
exchange and a pass-dependent bank in the chain) and three of the rule, each failing the named gate; a kernel source
that does not compile is refused with a message and leaves the projector usable. One first run taught something: the identity
control passed a sine-cosine exchange while the oracle was given the calculator's own table, and now uses the
oracle's polar coordinates.

**The probe: outcome C by decision 20's letter, B in character.** An insertion of 1,000 planes at n = 160 (2.84e8
deposits, 81 atomic float32 additions per pixel) runs 0.037 s per batch of 500 planes; plain additions run
0.0042 s and lose 59 % (seeded orientations) and 98 % (one orientation) of the density's mass. Against the
gridding oracle the atomic kernel is 1.07e-4 and 8.1e-5 of a voxel's terms off, above the cap 1e-5. But the same
deposits computed in double precision from single-precision coordinates are 1.09e-4 and 8.1e-5 off: the rounding
of `h R(1,a) + k R(2,a)` near 80 moves the window's edge weights, and every form on float32 coordinates shares that
floor. The atomic update itself varies by at most 2.4e-6 between runs, and one million atomic additions sum within
3.5e-6 of the exact value; its bits differ between runs in 49 % (seeded) and 1.8 % (one orientation) of the
voxels. K6's plan needs a ruling on which reading it takes (section 6).

**Memory** (*measured*, one process at the bench): MLX peak 1.94e9 B (fused) and 2.00e9 B (graph) for the
reprojection, 4.01e9 B (host route) and 4.69e9 B (device route) to the reference bins and a dense score; peak
footprint 4.15e9, 5.21e9, 9.36e9 and 12.69e9 B, of which MLX's buffer cache is 2.4e9 to 11.3e9 B and the
calculator's host memos 0.89e9 B (allocated by `new` on either route). Six device-route chains held 76.2e9 B of
summed footprint and left 0.76e9 B free: the roadmap's memory condition (51.5e9 B) is met there; its rate condition
is met nowhere.

**Two rate measures disagree.** With R0's two measures of a multi-process rate, the summed per-process medians and
the work over the time from go to the last exit, every row disagrees by far more than 10 % (the work rate is 0.07
to 0.88 of the summed medians): the go window holds the digests of every pass (5,000 copies of one section each)
and, for the chain, the particles and the score, and the fused passes are a small part of it. Decision 19's rule
holds on both measures.

## 2. What changed, phase by phase

| Phase | What | Files |
| --- | --- | --- |
| 0 | the base measured (counts, 16 digest lines twice, the oracles alone, six probes, the fixtures' dry run, SIMPLE read); the plan's Progress | 1 |
| 1 | the toy `projector`, its workspace with the graph form, `fproject_polar_batch_opt`, `get_kfromto`, `get_polar_coords` and `vol_pad2ref_pfts_opt` on the host route; suites `oracle_projection` and `projector`; `PROJ_FIXTURE_ERR`; rule `mirror` for public module procedures; the policy's section 4 | 5 new, 9 changed |
| 2 | the fused kernel's runs, refusals and the forms' agreement in `projector` | 2 |
| 3 | the device route (`set_ref_route`, the sections, the device memos, the tiles from them); suite `projector_chain`; the chain's tolerances | 10 |
| 4 | `bench_projector` (`time`, `chain`, `accuracy`), `get_ref_pft`, `get_cmat`; `run_parts.sh` takes the bench, suite and unit from settings; `PROJ_BENCH_ERR`; the sweeps, the verdicts and the splits | 1 new, 11 changed |
| 5 | `bench_insert_probe`; `PROBE_ERR_CAP`; Apple question 26 | 1 new, 3 changed |
| 6 | the kernel-families note, the roadmap, the toy, test and binding policies, the index, the history, `README.md`, this report | 1 new, 8 changed |

New files: `src/test/mlxf_toy_projector.f90`, `src/test/mlxf_toy_projector_workspace.f90`,
`src/test/mlxf_toy_projector_pft_batch.f90`, `src/test/mlxf_toy_projector_tester.f90`,
`src/test/mlxf_oracle_projection_tester.f90`, `src/test/mlxf_bench_projector.f90`,
`src/test/mlxf_bench_insert_probe.f90`, `doc/implementation_notes/completed/mlxf_kernel_k2_report.md`.

Counts (*measured*, Debug and Release): `unit_kernels` 1,281 to **1,496** (`oracle_projection` 44, `projector` 96: 32
on the CPU and 64 on the GPU, `projector_chain` 75); every other area unchanged (`unit_core` 80 to 82, as the
allocator reuses a freed address or not). The ledger: 40 new lines (5 calculator, 13 projector, 2 batch, 14
projector workspace, 6 polar workspace), 14 of them mirrored (two module procedures, and `get_ref_pft` and
`get_cmat` beyond section 3's table) and 26 additions.
The CTest entries and their budget of 9 did not move.

## 3. Decisions taken under delegation

Each with its reason in the plan's Progress entry of its phase.

| Phase | Decision |
| --- | --- |
| 1 | the calibration set holds the phantom's edge and boundary queries (decision 14 judges them in full); the wave control's values relative to 8 max|F| and its pattern by a threshold at half the smallest oracle value; the identity control at the oracle's own polar coordinates; the lifecycle read after `mlx_synchronize`; `pad_fft` evaluates the transform; the padded cube staged in the padded projector's `rmat`; `projector%ws` public (SIMPLE's public `cmat_exp`) with the projector's refusals kept in it; `fproject_spec` carries the points and rows; the resident form named `fproject_polar_batch_resident`; rule `mirror` asks no line for a tester's entries; `get_polar_coords` refuses through `message()` |
| 2 | the kernel objects live in the projector's workspace, built per projector (MLX compiles the source once); the window's numbers passed as a 17-element input; the kernel-source plant of a transposed rotation reads the rows as 3 by 2 |
| 3 | the chain's tolerances over both devices and both forms; the oracle rows by the ring formula in double precision; the device memos by float32 FFTs, the tiles assembled on the device, `memoize_ref_bins` after `kill_ref_bins` refused on that route; the host waits for the bank and the memos on the device route; family A's `new` unchanged (it still allocates the host memos) |
| 4 | `passes=` read by `time` and `chain`; the time suite's calculator kept over the passes, the chain's made per pass; the banks' digests by `get_ref_pft` (mirrored) after each pass, the accuracy oracle on `get_cmat` (mirrored); the chain's stage measured from the evaluated banks; decision 19 read on the median pass and on go to the last exit at one process; the bench's estimate counts 24 B per gathered term |
| 5 | pixels near a tie given no data in both kernel and oracle; the numerator's scale from the oracle on the data's moduli; the batches added by the graph; the coordinates' floor reported; the suite named `probe` |

## 4. Deviations from the plan

- **Seeds 2 and 3 were printed before the freezes.** In Phases 1 and 3 the development runs printed the judged
  seeds with the ceiling as the gate before the seed-1 builds froze the numbers. The frozen numbers come from those
  separate seed-1 builds by a rule fixed beforehand (the largest of seed 1's judged samples), so nothing was chosen
  from the prints; Progress says so.
- **Decision 8:** the kernel objects are rebuilt with each projector, so twice per state, not once per run.
- **Decision 10's waits:** the host also waits in `pad_fft` (the transform), in the projection on the device route
  (the bank) and in `memoize_refs` on the device route (the memos).
- **Section 3's table:** two more mirrored procedures, `polarft_calc%get_ref_pft` and `projector%get_cmat` (image's),
  for the bench's digests and its accuracy oracle; ledger lines say so.
- **The probe:** pixels near a tie are given no data (7,725 and 7,000 of 2e7 in the large cases), and a diagnostic
  of the coordinates' floor is reported; neither is in decision 20's text.
- **Decision 18's estimate:** the deposits per voxel are 232 over the touched voxels (the plan's 120 is over all);
  the footprints are larger than the estimates because MLX's buffer cache counts (11.3e9 B per device-route chain).
- **Expected and not found:** the probe's cap; atomic float additions correct to the cap (they are correct to the
  coordinates' floor). Found and not expected: GPU atomic float sums are more accurate than a sequential float32 sum.
- **Phase times** in the first Progress entries were corrected from the evidence's timestamps.
- Files outside the table: none.

## 5. Evidence against the baseline

- **Decision 23:** the 16 digest lines of the base (accuracy on both devices, `time` 2500_4 on the GPU) are equal
  after Phases 1, 3, 4 and 5 (`scratch/keep/phase{1,3,4,5}/digests*.log`); one split of `bench_polar_table` through
  the changed launcher writes a series row with K1's header and its numbers (1.767e7 pairs/s, 5.98 s, 20.81e9 B).
- **The off-state invariant:** a program that makes no `projector` runs none of the new device code; the family-A
  suites keep their counts (327, 794, 105, 55) in every phase.
- **Builds:** every phase ended with Debug and Release from scratch with `MLXF_WERROR=ON`, 0 warnings, the fast gate
  9 of 9, `scripts/check_tree.sh` passing, both formatters run on every touched Fortran file.
- **Plants** (`scratch/keep/phase{1,2,3}/plants/`, `phase1/rule_plants/`): each failed its gate on a patched copy of
  the tree built apart; the repository was never edited for a plant.
- **Suites' elapsed times** (Release): `oracle_projection` 0.01 s, `projector` 0.35 s, `projector_chain` 0.26 s; the
  fast gate stays at about 11 s.
- **Load:** every timed step waited for a one-minute load of at most 4 and recorded it (1.9 to 3.8).

## 6. Left open for the maintainer

**Ruled 2026-11-25** (Hans, 2026-11-25: "B for the probe, keep the defaults"): the probe is outcome B, as recommended below; the defaults stay the
graph form and the host route. Still open: whether the miniature reads like SIMPLE's reprojection.

**A ruling for K6 (the probe).** Decision 20's letter gives C: K6 starts from `mlx_scatter_add` and the sorted form.
The diagnosis gives B: the atomic kernel is correct to the floor single-precision coordinates set and is not
bit-repeatable, so K6 needs a deterministic form with the atomic kernel as its speed reference. Recommended: B, with
K6's cap judged against a reference on the kernel's own single-precision coordinates (or with coordinates computed
in double precision on the host), since no float32 form can meet 1e-5 against the double-precision oracle at n = 160.

**Reserved by the plan:** whether the miniature reads like SIMPLE's reprojection (the kernel-families note's
section 4 lists the differences).

**Reported, not gated:** the seam with measured bytes; the stages; the two rate measures and the exit spreads; the
roadmap's conditions (the memory one met by six device-route chains); 107 near ties in the accuracy suite's 177,632
samples (0.060 % of the bench's samples in the dry run).

**Proposals, not made:**
- The defaults stay the graph form and the host route (the references and the CPU path), as K1's tail does; switching
  them is the maintainer's choice, before SIMPLE's integration.
- On the device route `polarft_calc%new` still allocates and zeroes the host memos (0.89e9 B per state); a device-route
  `new` could skip them.
- `scripts/run_parts.sh` could write the exit spread and the work rate into the series table (they are in each
  split's summary now).
- The bench's per-pass digests (5,000 copies of one section) dominate the fused form's go window; a whole-bank copy
  would need one more addition.

## 7. A commit message

```
K2: the polar projection (B1) as a toy projector, and the protected-update probe

A miniature of SIMPLE's projector (new, set_rmat, get_cmat, pad_fft,
expand_cmat, is_expanded, kill_expanded, kill) with its GPU workspace, and
SIMPLE's fproject_polar_batch_opt and vol_pad2ref_pfts_opt: the padded
volume transformed on the device, SIMPLE's expanded cube made there by
gathers, and the polar gather of every (direction, shell, angle) sample in
two forms: a graph of library operations (the reference and the CPU path)
and one Metal kernel with a thread per sample. The calculator gains
get_kfromto, get_polar_coords, get_ref_pft and a device route
(set_ref_route) on which the projected bank, its ring transforms and the
reference tiles never leave the device.

New files: src/test/mlxf_toy_projector.f90,
src/test/mlxf_toy_projector_workspace.f90,
src/test/mlxf_toy_projector_pft_batch.f90,
src/test/mlxf_toy_projector_tester.f90 (suites projector, projector_chain),
src/test/mlxf_oracle_projection_tester.f90 (suite oracle_projection),
src/test/mlxf_bench_projector.f90 (test=bench_projector),
src/test/mlxf_bench_insert_probe.f90 (test=bench_insert_probe),
doc/implementation_notes/completed/mlxf_kernel_k2_report.md.

Against the double-precision projection oracle: 1.5e-6 of a sample's terms
on the fixtures (frozen on seed 1), 1.45e-5 at SIMPLE's bench, 4e-7 of a
row through family A's dense score; every control fails on its plant.
Rule mirror learns public module procedures; unit_kernels 1,281 to 1,496.

Timed on the M5 Ultra at box 160 padded to 320, pftsz 182, 61 shells,
2,500 directions: the fused gather makes the reprojection of a state 24
times faster at one process (0.040 s against 0.97 s) and 5 to 6 times from
go to the last exit at three processes; kept. The device route takes the
banks to the reference bins in 0.03 s against 1.05 s; kept. The defaults
stay the graph form and the host route.

The protected-update probe: atomic float32 deposits insert 1,000 planes at
n = 160 in 0.037 s per 500, plain additions lose 59 to 98 % of the mass;
the error 1.07e-4 is above the cap 1e-5 (outcome C) but equals the floor
of float32 coordinates (B in character); a ruling for K6. Apple question 26.

Run mlxf_kernel_k2; plan doc/implementation_notes/planned/mlxf_kernel_k2.md.
```
