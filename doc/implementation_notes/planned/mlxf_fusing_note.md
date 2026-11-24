# mlx-fortran: fusing, and what follows the shift maps' particle tiles

Status, 2026-11-24: active roadmap, not a separate implementation plan. Phase 5c's graph alternatives
are implemented and validated, and run `mlxf_m1_m5` measured them on the M5 Ultra: none is retained, and the
fresh requested-output profile is section 1a. Completed implementation evidence is in
[the M2 record](../completed/mlxf_milestone1_m2.md), based on mlx-fortran `c93ee0d` and SIMPLE `0a8b0903e`. Metal work remains later, after its wrapper and fresh profiles. Originally written by Claude
at Hans's request after decisions 25 and 26; updated by Codex's review of SIMPLE's committed optimizations.

## 1. Why

The shift maps are built from public `mlxf` operations only, a rule of milestone 1 ("the arithmetic is MLX's").
The following historical profile is the particle-tile form before `mlx_bitcast`/`mlx_take`: building both
coarse maps cost about 2.6 s, of which the matrix product was 0.42 s. It is not a profile of the current
code, and the old unpack cost must not be counted as a remaining saving.

| step (s) | cost |
| --- | --- |
| the order-expanded spectra Z | 0.39 |
| the particle's order gather | 0.13 |
| the candidates' gather and packing | 0.10 |
| the real matrix product | 0.42 |
| the product unpacked to complex (subsequently replaced by bitcast) | 0.49 |
| the transform over the ring position | 0.29 |
| the order's phase | 0.22 |
| the fold and the direction transforms | 0.42 |
| the final reordering | 0.22 |

These are profiled steps summed over both maps, case 2500_4, M2 Ultra, on a loaded machine. Measured
afterwards with `mlx_bitcast` and `mlx_take` (milestone-1 Progress, 2026-11-23): window 4.90e4 and screen
1.28e4 maps/s, 1.10 and 1.69 times SIMPLE `67c6a05e2` at 24 threads; 54 µs of construction per screen map.
The earlier 71 µs construction and 24 µs selection/reduction figures belong to the pre-bitcast profile.
Phase 5c has now split width and evidence into separate compiled graphs and corrected the requested-output
barriers. Its graph alternatives and cutoff handling pass correctness validation. Hans deferred benchmarking
on this machine on 2026-11-23, so there is no fresh requested-work profile and no measured winner yet. Compilation did not remove all
intermediates in the measured forms. The profile does not yet establish that a custom kernel is needed;
the graph experiments below come first.

## 1a. The M5 Ultra's requested-output profile (run `mlxf_m1_m5`, Phase 3)

Measured on the M5 Ultra at mlx-fortran `4706ecb` against SIMPLE `0a8b0903e` (30 threads, measured FFTW plans),
case 2500_4, all widths, no evidence, full precision, the control graph (weighted-particle contraction, complex
direction transform) at each map's best particle tile; µs per map of wall time, mean of two invocations
(*measured*; the GPU's stages from the benchmark's requested-output profile, SIMPLE's as its thread-µs over 30):

| map | side | construction | selection | width reduction | copy-out and host | total | maps/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| screen | GPU, ptile 4 | 34.7 | 4.8 | 11.5 | 1.3 | 50.1 | 1.99e4 |
| screen | SIMPLE | 27.8 | 3.1 | 17.8 | | 48.7 | 2.05e4 |
| window | GPU, ptile 16 | 9.4 | 1.0 | 1.9 | 1.2 | 13.4 | 7.46e4 |
| window | SIMPLE | 6.1 | 0.5 | 2.5 | | 9.2 | 1.09e5 |

- The control builds the maps at 0.97 (screen) and 0.68 (window) of SIMPLE's committed kernel on the same
  machine: the M2's lead (1.69 and 1.10 against the previous SIMPLE kernel at 24 threads) is gone.
- **Construction dominates** (69 % of the screen's and 70 % of the window's GPU time) and is where the GPU
  loses: 1.25 times SIMPLE's on the screen, 1.54 times on the window. The width reduction is already faster
  than SIMPLE's (0.65 and 0.76 times its time). Selection is small. The copy-out is negligible; the fixed
  host part (about 1.2 µs per map) matters only on the window.
- **The graph alternatives did not help**: the real-weights contraction is 0.61 to 0.73 of the control on
  the screen even at its best candidate and order tiles (16 × 8), and the Hermitian direction transform is
  0.97 to 0.99. The compact radius slots cut executed radius-order slots (screen 363 to 229-265) without
  making contraction 2 competitive. They are recommended for removal (the run's report names the files).
- **The accelerated mode** (NAX matrix products, confirmed by trace) raises the rates by 0.3 to 3.5 % and
  fails the frozen map caps, so it changes nothing here.
- So the remaining candidate is a **fused construction kernel** (item 3 below): it is the only stage large
  enough to move either map past SIMPLE (*derived* from the table's stage sums, the other stages unchanged: parity needs
  construction 10 % shorter on the screen and 46 % shorter on the window; a 2.0 go needs 81 % and 95 %). No speedup is assumed; item 3's 30 % rule and gates stand. A fused selection and reduction
  (item 4) has at most the reduction's 23 % (screen) to gain.

**Reading and direction** (added 2026-11-24, [roadmap](mlxf_roadmap.md) decisions 3 and 6). The ratios above
compare standalone rates: SIMPLE runs as several part processes that share the GPU, so a GPU map at 0.68 to
0.97 of the 30 cores' rate is capacity the GPU could add, at most, to busy cores. The maps' formulation is replaced, not tuned further:
family A of [`mlxf_kernel_families.md`](mlxf_kernel_families.md) builds them as the dense score at a lattice
of particle shifts. Items 1 and 3 below stand as history for the Fourier-Bessel form; item 2, the Metal-kernel
wrapper, is now the roadmap's rank 1b.

## 2. What is needed, in order

1. **SIMPLE's optimizations in the graph model first.** Milestone-1 decision 27 and Phase 5c own the
   implementation sequence, gates, tile search and files. Keep particle-shift reuse, compare the current
   weighted-Z product with streamed per-order products against real Bessel weights, skip inactive radius/order
   slots where profitable, and test coefficient folding plus a Hermitian-half direction transform with
   existing `mlx_irfft`. Cache prepared tables under their actual dependencies. Correct the optional-output
   profile and model `width_cutoff` separately from the all-width benchmark. Implementation and correctness
   validation are delivered; keep these paths experimental until the deferred measurements. Re-profile against the final
   committed SIMPLE kernel, whose CPU row bound is not a GPU scheduling rule.
2. **The Metal-kernel wrapper, when the remaining profile justifies a kernel.** Phase 7 of
   `mlxf_mlxc_parity.md` (its decision 17): `mlx_metal_kernel_spec`
   and `type(mlx_metal_kernel)` with `apply`, over mlx-c's `fast_metal_kernel` (the generated layer binds it
   already). MLX compiles a kernel's source at run time, so no Xcode is needed. No pipeline kernel comes
   before this wrapper exists and has its own tests.
3. **The fused shift-map construction**, test code in `src/test/`, compared with Phase 5c's winning graph.
   - *Inputs:* a tile's packed particle spectra, its candidates' spectra, the Bessel weights and the order
     shift. Optionally the order's phase, which would merge the transforms.
   - *Output:* G' or H as complex64, in the layout the fold and the transforms read.
   - *What it could remove:* materialized weighted spectra or per-order products and final reordering,
     according to the measured winning graph. The old complex unpack is already replaced by bitcast.
   - *Tiling:* threadgroups over (order and radius, candidate, ring position), each particle's spectra in
     threadgroup memory.
   - *Correctness:* judged by the existing oracle and decision 17's frozen caps, on the GPU only. A Metal
     kernel has no CPU path, so the CPU calibration cannot run it. The negative controls are planted in the
     kernel's source as they are in the graph today.
   - *Decision rule:* the existing rule requiring a measured gain above 30 percent decides whether the
     additional path is kept.
4. **The fused selection and reduction:** measure a stable tiled reduction of the requested outputs (mode,
   optional physical moments and evidence), including cutoff behavior. Use the new profile rather than the
   historical 19 µs reduction figure. A one-pass implementation is a hypothesis and must preserve stable
   normalization, the physical/tempered distinction and the first-mode tie rule. The same gates apply.
5. **The dense table:** the formulation-B tail is compiled already, and a fused distance-and-draw kernel is
   measured before it is written. The dense table already runs at 4.5 times SIMPLE on the M2 Ultra (context),
   so it has the lowest priority.
6. **Timing:** each kernel is timed against the graph form it replaces, on the same machine and case, best of 3
   after a warm-up, two invocations. Both are reported. The graph form stays in the code as the reference
   and the fallback.

## 3. What does not carry

- **To SIMPLE's CPU code:** neither the kernel nor the particle tiles carry. The tiles fold the Bessel weights into
  the particle side and pay a complex product per radius, about 1.7 times SIMPLE's operations, which only a GPU's
  matrix units repay. What carries is the contraction: SIMPLE's per-order shell sums over every magnitude as one
  real `sgemm` (2 nrots x shells by shells x magnitudes), with the real weights kept. A prototype in a scratch
  SIMPLE export (2026-11-23, M2 Ultra, 24 threads, SIMPLE 67c6a05e2 measured plans) built the screen map 35 %
  faster and raised the bench's maps/s 1.28 times (screen) and 1.13 times (window), at float32 rounding level
  against the pin. The resulting 1.33 (screen) and 0.97 (window) GPU/CPU ratios were prototype context.
  Hans adopted the CPU change the same day; it is now committed in SIMPLE `0a8b0903e`, including active-radius
  ranges, cached weights, bounded SGEMM rows and fused Hermitian packing. Its final record reports x1.28
  screen and x1.16 window throughput against the previous CPU kernel (not the prototype's x1.13 window).
  See SIMPLE's `polar_shift_search.md`, entry 2026-11-23. The M5 verdict uses this committed comparator;
  fresh matched runs are required, rather than deriving a new GPU ratio from separate timings. The prototype's
  report is in `~/for_claude/bench/simple_sm_gemm_2026-11-23/REPORT.md` on the M2 Ultra.
- **To other backends:** a Metal kernel binds the code to Apple GPUs. MLX's CUDA backend would need its own
  kernel, and the graph form keeps working everywhere.
- **To the M5 verdict:** it is judged on library operations, as milestone 1 says. A kernel's numbers are
  reported beside it, never instead of it.

## 4. Smaller items met on the way

- `mlx_take` and `mlx_bitcast` entered early (milestone 1 decision 26). The rest of the parity ledger waits
  for its plan.
- The FFT over a non-leading dimension and the 364-point FFT (4 x 7 x 13) of SIMPLE's case deserve a layout
  profile. Padding to a power of two alone changes the rotation grid; any proposed replacement must recover
  the original samples and normalization before timing is meaningful. A verified mixed-radix limitation
  goes to `doc/collaboration/apple_questions.md`.
- The particle's order gather (`mlx_take_along_dim` with a per-(m', n) index) is element-wise. A layout with
  the ring position slowest would make it a slab gather.
