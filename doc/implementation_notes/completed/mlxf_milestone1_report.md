# Milestone 1 report: the M5 Ultra's measurements and verdicts (run `mlxf_m1_m5`)

Run `mlxf_m1_m5`, 2026-11-24, 02:21–04:34 EST. Claude, unattended, on the M5 Ultra. It carried out plan
[`planned/mlxf_m1_m5.md`](mlxf_m1_m5.md), which is milestone 1's deferred Phase 5c measurements and
its Phases 6 and 7. Measured: mlx-fortran `4706ecb2b8e1a4f77c8e9b67753a66e62b3c3b47` against SIMPLE
`0a8b0903eee151700305399e8e3ff53c2c21caae`. Run HEAD `af0c23f`. No rulings were needed. Measurement and
documentation only: no source, test, script or build file changed. The detail is in the plan's Progress,
Phases 0 to 4; milestone 1's summary is in [its Progress](mlxf_milestone1.md). Milestone 1 is at
the hold of design decision 32.

**How to read the ratios** (added 2026-11-24, [roadmap](../planned/mlxf_roadmap.md) decision 3; no measured
number changes). SIMPLE never runs as one 30-thread process against the GPU. It runs as several part
processes at once (3 × 10 or 6 × 5 threads on this machine), and every part would use the GPU at the same
time. The ratios below compare standalone rates, the GPU alone against 30 threads alone. Scoring at 4.69
means the GPU alone scores 4.69 times what all 30 cores score. The maps at 0.971 and 0.683 mean the GPU
alone builds maps at that fraction of the 30 cores' rate; "negative" names decision 18's branch for a GPU
that replaces the cores, not a loss to them. These rates bound what the GPU could add to busy cores; they do
not measure it. Under a concurrent 30-thread memory-streaming load the GPU path slowed by 18 % (section 1,
item 7), and how several processes share the GPU and the memory was not measured here.

## 1. What was learned

1. **GPU scoring is a go: 4.69 times SIMPLE** on all 30 cores (Phase 2, item 7).
   - The GPU's slower invocation scores 1.76097e7 pairs/s against SIMPLE `block_prod`'s faster 3.75296e6
     (B 16).
   - Spreads are 0.33 % and 1.16 %, far from the 2.0 threshold.
   - The other cases give 4.40 to 4.83. The M2 gave 4.29 to 4.55 (context).
2. **The canonical plan is the M5's best.**
   - Formulation B with the compiled tail, at B 64 × R_t 250, is the fastest timed configuration in all four cases
     (15 timed at 2500_4) (Phase 2, item 2).
   - Formulation C is 0.92 times B and should go (decision 9).
3. **The GPU shift maps are negative on both maps**, against SIMPLE's committed kernel on 30 cores (Phase 3,
   item 4):
   - screen 0.971;
   - window 0.683.

   SIMPLE's `0a8b0903e` kernel and the 30 cores overturned the M2's lead (1.69 and 1.10). Construction is
   70 % of the GPU's time per map, and it is where the GPU loses: 1.25 and 1.54 times SIMPLE's time. The
   width reduction is already faster (the fusing note's section 1a).
4. **None of Phase 5c's graph alternatives earns its keep** (Phase 3, items 1 to 3; decision 7's 1.30 rule):
   - the Hermitian direction transform: 0.97 to 0.99 of the control;
   - the real-weights contraction: 0.58 to 0.73, after a 3 × 3 candidate/order-tile search at both
     compact settings.
5. **The accelerated mode (`MLX_ENABLE_TF32=1`) uses NAX but is not worth having.**
   - Traces show `steel_gemm_fused_nax_*` only in this mode (Phase 2, item 4; Phase 3, item 6).
   - It breaks the frozen bounds: block row error 4.2e-4 against 1.45e-6; map suites 84/654 and 44/72
     failing.
   - It gains 1 % (dense) and 0.3 to 3.5 % (maps).
6. **Memory is explained region by region** (Phase 2, item 6; Phase 3, item 7).
   - The Metal buffers' dirty pages equal MLX's active peak (10.3 to 10.7 GB).
   - The live host heap equals the benchmark's data (4.2 GiB).
   - The rest of the 21 to 23 GB footprint is freed host blocks that the allocator keeps.
   - The estimate undercounts dense small tiles (several queued at once) and overcounts the maps.
7. **Interference:** a concurrent 30-thread CPU streaming load slows the GPU path by 18 %; two slots hide
   2.4 % (Phase 2, item 5).

## 2. What changed, phase by phase

Diffs: `~/agent_runs/mlxf_m1_m5/review/phase_N.diff`.

| Phase | Files | Content |
| --- | --- | --- |
| 0 (`phase_0.diff`) | 2: `planned/mlxf_m1_m5.md`, `planned/mlxf_m5_preparation.md` | machine record, base builds and suites, HEAD's release gate, the launch audit |
| 1 (`phase_1.diff`) | 1: `planned/mlxf_m1_m5.md` | SIMPLE built and gated; CPU denominators; the case and grid files |
| 2 (`phase_2.diff`) | 1: `planned/mlxf_m1_m5.md` | dense accuracy, sweep, profile, traces, overlap, memory, verdict |
| 3 (`phase_3.diff`) | 2: `planned/mlxf_m1_m5.md`, `planned/mlxf_fusing_note.md` | Stages A and B, retention, map verdicts, accelerated mode, traces, memory, fusing note §1a |
| 4 (`phase_4.diff`) | 7 + 1 new | milestone 1's banner and summary, this note's banner, the index, history, setup-guide corrections, the follow-up's update, this report |

## 3. Decisions taken under delegation

- **What counts as "other processes"** (Phase 1, item 2). The wrapper sums `%CPU` over every process except
  the timed tree and the sampler's `top`, from a true 5-s interval of `top -l 2`, for both the 250 % wait
  and the 400 % flag. It is the stricter reading.
- **The wrapper's opt-in keys** `NOWAIT`, `EXCLUDE_PIDS` and `MAX_ATTEMPTS` (Phase 2, item 5). They let the
  stream-loaded overlap row run once without counting its deliberate load. The defaults are unchanged, and
  the Phase 1 copy is kept.
- **The dense verdict configuration judged at its own tile** (Phase 2, item 1): `accuracy bt=64 rt=250`,
  192/192. Step 1 runs the block's default tile, and decision 6 asks for a configuration "that passes its
  gates".
- **Step 3's `<64|best>` and `<250|best>` collapsed to one profile row**, because the best is the canonical
  plan (Phase 2, item 3).
- **Memory reconciled with `footprint`/`vmmap` and an RSS timeline** on extra untimed single-configuration
  invocations (Phase 2, item 6; Phase 3, item 7). The benchmark at `4706ecb` reports no MLX cache size, and
  no source may change.
- **The map verdict rows are Stage A's interleaved control pair** (Phase 3, item 4). The third and fourth
  control invocations agree with them (window 0.682 with all four).
- **Retention compares each alternative at its best ptile with the control at its best** (Phase 3, item 3).
  The equal-ptile comparison is reported as well (best 1.014).
- **The map traces use `ptiles=4,16`**, covering both maps' canonical ptiles in one invocation per mode
  (Phase 3, item 6).
- **"README.md" in decision 13 and the phase note read as the root README**, which is unchanged. The index
  file `doc/implementation_notes/README.md` was edited per step 2 and the file table, and gained a row for
  the run's note (Phase 4, item 2).

## 4. Deviations from the plan

- **Expected effects that did not occur.**
  - HEAD's release gate passed. Decision 14's example of a failure, GPU `expm1`, measured 168 eps32, inside
    HEAD's committed bound.
  - The M2's shift-map lead did not carry to the M5.
  - The accelerated mode bought no speed.
- **`nthr=30` is inert in Phase 3.** `suite=shiftmap` at `4706ecb` reads no `nthr`, which section 2 did
  not record (Phase 0 findings). The timed path is the GPU with one submitting thread, so nothing changes.
- **Additional, untimed invocations:**
  - the accuracy suite at the verdict tile;
  - the memory runs;
  - the `vmmap`/`footprint` snapshots, which slowed one screen row; it is not used as a timing.
- **The M5's CPU calibration differs from the frozen values.** It prints n_cpu 3 where 2 is frozen, and its
  e_cpu agrees to 9 digits (Phase 2, item 1). It is reported, not recalibrated; the judged counts are 0.
- **Files changed outside the table:** none. No deferrable item was skipped. Every phase finished inside
  its time box (5, 53, 32, 40 and 3 of 60, 100, 100, 110 and 60 minutes).

## 5. Evidence against the baseline

All under `~/agent_runs/mlxf_m1_m5/scratch/keep/`, with per-invocation sidecars (both hashes, SHA-256 of the
executable and inputs, environment, load, `/usr/bin/time -l`).

- **Base `4706ecb`, Debug and Release** (`phase0_logs/`, `phase0_step3/`):
  - 0 warnings with warnings as errors;
  - fast gate 8/8, 0 skips, GPU 1;
  - `recovery_half` 12, `polar_table` 231, `polar_shiftmap` 1,308 and `polar_shiftmap_accuracy` 144, all
    equal to the recorded counts, on both devices.
- **HEAD `af0c23f`** (`phase0_step4/`): release gate passed; `polar_shiftmap` 1,364 and the accuracy suite
  144.
- **SIMPLE** (`phase1_logs/`, `phase1_runs/`):
  - fast gate 15/15;
  - `block_prod` spreads ≤ 1.16 %; maps ≤ 0.68 %; team identity 0 maps differing;
  - `check` passes as its R7 defines; `fills` 0 differences; `neigh` within tolerance twice;
  - geometry equal to the M2's.
- **Dense** (`phase2_runs/`): the accuracy block passes in full precision on both devices for B and C;
  schedule identity holds; the verdict rows are clean, with a spread of 0.33 %.
- **Maps** (`phase3_runs/`): 35 timed invocations, all clean; Stage A spreads 0.01 to 3.75 %.
- **Traces** (`traces/`, about 1.5 GB): dense and maps, both modes, with readings in `*_traces_reading.txt`.
- **Inputs:** `polar_case.txt` (`90a974fa…f1d9`) and `shiftmap_grid.txt` (`aa05ca27…2eca`).

## 6. Left open for the maintainer

**Reported, not gated:**
- the overlap rows;
- the synthetic width and evidence sensitivity: quarter +6 to +10 %, none +17 to +27 %, evidence −7 to
  −8 %;
- the 10-thread context rows;
- the M2 ratios.

**Data-dependent:**
- s, f and w remain unmeasured. Decision 5's projection is tabulated in Phase 2, item 7.
- The production-equivalent CPU map cost needs w.

**Follow-ups:**
- **Remove the negative experiments** (decision 1 left the code untouched):
  - formulation C;
  - the map contraction 2 (real weights), the Hermitian transform, and the candidate/order-tile and
    compact-radius options.

  The files are `src/test/mlxf_kernel_polar_table_shiftmap{,_tester}.f90`,
  `src/test/mlxf_kernel_polar_table_lifecycle.f90` and `mlxf_kernel_polar_table_tester.f90` for C, `src/test/mlxf_bench_polar_table.f90` (`form=c`,
  `contraction`, `hermitian`, `ctile`, `otile` and `compact`) and `src/test/mlxf_test_defs.f90`
  (`POLAR_FORMS%c`, `POLAR_MAP_FORMS`, `POLAR_MAP_CTILES`, `POLAR_MAP_OTILES`).
- **Fix the benchmark's arguments and outputs:**
  - make `suite=shiftmap` either read `nthr` or reject it;
  - print `mlx_cache_memory` beside the peak, so that memory reconciles without `vmmap`;
  - fix the laptop's `arg_int` uninitialised-`ios` finding.
- **NAX:** dispatch is observed with `MLX_ENABLE_TF32=1` only, and the trace paths are in §5. No Apple
  question arises.
- **A fused construction kernel** is the only stage that could move the maps. Parity needs it 10 % (screen)
  and 46 % (window) shorter; the fusing note's §1a has the figures.
- **Moving both plans to `completed/`, the root README status line, and milestone 2 / parity Phase 4
  onward** at the hold (decision 13; design decision 32).
- The preparation follow-up's Phase 5 (combined parity integration) is still open.

## 7. Commit message

```
milestone 1 on the M5 Ultra: scoring go (4.69x SIMPLE), shift maps negative, report (run mlxf_m1_m5)

Measured mlx-fortran 4706ecb against SIMPLE 0a8b0903e at 30 threads on the M5 Ultra, all rows clean.
Dense scoring: B 64 x R_t 250, formulation B, 1.761e7 pairs/s against SIMPLE block_prod 3.753e6: go.
Shift maps: control graph 0.971 (screen) and 0.683 (window) of SIMPLE: negative; no Phase 5c
alternative retained; formulation C 0.92 of B. Accelerated mode (NAX, traced) fails the frozen gates.
Memory reconciled by region. Documentation only: Progress of mlxf_m1_m5 and milestone 1, fusing note
section 1a, M5 setup corrections, launch audit, index, history, and the milestone 1 report. At the hold.
```
