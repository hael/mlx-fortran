# mlx-fortran: fusing, and what follows the shift maps' particle tiles

Status, 2026-11-23: a note, not a plan. A plan written from it follows `doc/how2s/how2write_agent_plans.md`
and pins its own base. Written by Claude at Hans's request, after the particle-tile shift maps (milestone 1,
decisions 25 and 26).

## 1. Why

The shift maps are built from public `mlxf` operations only, a rule of milestone 1 ("the arithmetic is MLX's").
At the particle-tile form, building the maps of both of SIMPLE's coarse maps costs about 2.6 s. The matrix
product is 0.42 s of that; the rest moves data.

| step (s) | cost |
| --- | --- |
| the order-expanded spectra Z | 0.39 |
| the particle's order gather | 0.13 |
| the candidates' gather and packing | 0.10 |
| the real matrix product | 0.42 |
| the product unpacked to complex (now a free bitcast) | 0.49 |
| the transform over the ring position | 0.29 |
| the order's phase | 0.22 |
| the fold and the direction transforms | 0.42 |
| the final reordering | 0.22 |

These are profiled steps summed over both maps, case 2500_4, M2 Ultra, on a loaded machine. Measured
afterwards with `mlx_bitcast` and `mlx_take` (milestone-1 Progress, 2026-11-23): window 4.90e4 and screen
1.28e4 maps/s, 1.10 and 1.69 times SIMPLE at 24 threads; 54 µs of construction per screen map. The selection and the reduction, each compiled, add about 24 µs per screen map,
against 71 µs to build it. Graph compilation (`mlx_compile`) fuses elementwise operations only. Neither the
compiled tail nor an earlier compiled product removed the materialised intermediates. A kernel that keeps
them in registers and threadgroup memory is the remaining lever.

## 2. What is needed, in order

1. **The Metal-kernel wrapper.** Phase 7 of `mlxf_mlxc_parity.md` (its decision 17): `mlx_metal_kernel_spec`
   and `type(mlx_metal_kernel)` with `apply`, over mlx-c's `fast_metal_kernel` (the generated layer binds it
   already). MLX compiles a kernel's source at run time, so no Xcode is needed. No pipeline kernel comes
   before this wrapper exists and has its own tests.
2. **The fused shift-map construction**, test code in `src/test/`, a third form beside the particle-tile one.
   - *Inputs:* a tile's packed particle spectra, its candidates' spectra, the Bessel weights and the order
     shift. Optionally the order's phase, which would merge the transforms.
   - *Output:* G' or H as complex64, in the layout the fold and the transforms read.
   - *What it removes:* Z (2 nkb x nord nrho x nrots per particle) is never materialised, along with the
     unpack and the final reordering.
   - *Tiling:* threadgroups over (order and radius, candidate, ring position), each particle's spectra in
     threadgroup memory.
   - *Correctness:* judged by the existing oracle and decision 17's frozen caps, on the GPU only. A Metal
     kernel has no CPU path, so the CPU calibration cannot run it. The negative controls are planted in the
     kernel's source as they are in the graph today.
   - *Decision rule:* the 30 % rule of decision 12 decides whether it replaces the graph form.
3. **The fused selection and reduction:** one pass over a pair's cells for the mode, the width's moments and
   the log evidence, in place of a dozen passes; about 19 µs of 95 µs per screen map today. The same gates
   apply.
4. **The dense table:** the formulation-B tail is compiled already, and a fused distance-and-draw kernel is
   measured before it is written. The dense table already runs at 4.5 times SIMPLE on the M2 Ultra (context),
   so it has the lowest priority.
5. **Timing:** each kernel is timed against the graph form it replaces, on the same machine and case, best of 3
   after a warm-up, two invocations. Both are reported. The graph form stays in the code as the reference
   and the fallback.

## 3. What does not carry

- **To SIMPLE's CPU code:** neither the kernel nor the particle tiles carry. The tiles fold the Bessel weights into
  the particle side and pay a complex product per radius, about 1.7 times SIMPLE's operations, which only a GPU's
  matrix units repay. What carries is the contraction: SIMPLE's per-order shell sums over every magnitude as one
  real `sgemm` (2 nrots x shells by shells x magnitudes), with the real weights kept. A prototype in a scratch
  SIMPLE export (2026-11-23, M2 Ultra, 24 threads, SIMPLE 67c6a05e2 measured plans) built the screen map 35 %
  faster and raised the bench's maps/s 1.28 times (screen) and 1.13 times (window), at float32 rounding level
  against the pin. Against that CPU form this library's graph form leads 1.33 times on the screen map and trails
  slightly (0.97) on the window map, which makes the fused kernel the GPU's lever for this stage. The CPU change
  is SIMPLE's own plan, judged by its `polar_matching_bench suite=shiftmap` and its map tests; the report is in
  `~/for_claude/bench/simple_sm_gemm_2026-11-23/REPORT.md` on the M2 Ultra.
- **To other backends:** a Metal kernel binds the code to Apple GPUs. MLX's CUDA backend would need its own
  kernel, and the graph form keeps working everywhere.
- **To the M5 verdict:** it is judged on library operations, as milestone 1 says. A kernel's numbers are
  reported beside it, never instead of it.

## 4. Smaller items met on the way

- `mlx_take` and `mlx_bitcast` entered early (milestone 1 decision 26). The rest of the parity ledger waits
  for its plan.
- The FFT over a non-leading dimension, and the 364-point FFT (4 x 7 x 13) of SIMPLE's case, are worth a
  probe against a padded power-of-two length. The question goes to `doc/collaboration/apple_questions.md`
  if MLX's mixed-radix path turns out slow.
- The particle's order gather (`mlx_take_along_dim` with a per-(m', n) index) is element-wise. A layout with
  the ring position slowest would make it a slab gather.
