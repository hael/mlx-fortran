# What mlx3D teaches the remaining toy kernels

Status, 2026-11-25: advisory note, not ruled. Written at `271c241`, with mlx3D read at `7101ec3`
(`~/src/mlx3D`, MIT, Python on MLX). It changes no plan; decisions at the end are proposals for the
plans of K3 to K7.

## 1. Why mlx3D is worth reading

mlx3D's hot paths solve our problems in another field. Gaussian splatting scatters irregular footprints
onto a grid (family C), samples fields at projected positions (family B), and keeps the K best of many
candidates (A4). All of it runs through `mx.fast.metal_kernel`, the call behind our `mlx_metal_kernel`.
The kernels that count are `splatting/tiles.py` (binning), `splatting/rasterize.py` (forward and backward
compositing), `splatting/fast.py` (a forward path with no host waits) and `ops/knn.py` (small-K
neighbours). Our kernels so far use one thread per output and global memory only (K1 tail, K2 gather,
K2 probe). mlx3D adds four patterns to those.

## 2. The patterns

| Pattern | Where in mlx3D | What it buys | Toy it serves |
| --- | --- | --- | --- |
| **P1. Scatter turned into a tiled gather.** Bin contributors by output tile; one threadgroup per tile streams its contributors through `threadgroup` memory in batches of 256; each thread owns one output and adds in registers in a fixed order | `_FORWARD_SRC` in `rasterize.py` | no atomics, deterministic, each output written once | K6 (form 3) |
| **P2. Cheap deterministic binning.** Emit duplicates already in the order wanted (global depth order, offsets from a prefix sum), so a *stable 32-bit* key sort is enough; get per-tile `[start, end)` by boundary detection in one kernel; downstream reads through `sort_idx`, never through gathered copies | `_bin_fast`, `_EXPAND_SRC`, `_RANGES_SRC` in `tiles.py` | 2.5 times faster binning than an int64 composite argsort plus scatter-min/max, bit-identical output (their claim) | K6 (form 2), K3 |
| **P3. No host waits inside a pass.** Data-dependent sizes go into a persistent buffer of grow-on-demand capacity; the tail is masked with a sentinel key by `where(positions < total, ...)` with `total` a 0-d device array; the capacity check rides on the pass's own evaluation and a rare overflow redoes the pass | `FastGaussianRenderer.render` in `fast.py` | the whole pass is one lazy graph | K3, K6, K5's lockstep loop |
| **P4. Small-K selection in registers.** Each thread keeps its K best (K ≤ 8) by insertion, ties broken by the lower index; candidates stream through `threadgroup` memory in blocks of 256 | `_KNN3D_SMALLK_SRC` in `knn.py` | no full score matrix, no `argpartition`, the CPU's tie rule | K7, K4's per-particle reductions |
| **P5. One fused per-object kernel.** About 60 element-wise operations of projection and culling in one pass per Gaussian; per-object invariants cached across frames | `_GEOMETRY_SRC` in `fast.py` | memory traffic, launch count | confirms K1 and K2; K6's stencils (section 3) |

Two negative results come with them. A SIMD-reduced backward (`simd_sum`, one atomic per 32 lanes) was
3 % *slower*, because their backward is bound by recomputation, not by atomics (`rasterize.py`, header).
Our probe is the opposite case: atomics cost 9 times plain additions (0.037 s against 0.0042 s a batch,
*measured*, K2). Their compaction by `argsort` of a mask (`nn/accel.py`) works but sorts all elements;
`cumsum` of the mask (their own conic path in `tiles.py`) is the cheaper form.

## 3. K6: the insertion as a pull, with no sort and no atomics

P1 needs P2 only because splats are irregular. Central sections are not: whether plane `p` reaches voxel
tile `T` is one test on the plane's distance from the tile's centre. So form 3 of the families note can
be written without binning:

- **Grid:** one threadgroup per voxel tile (8³ = 512 threads, one per voxel), about 4,600 tiles for the
  probe's 2,341,350 voxels (*derived*).
- **Planes:** every threadgroup walks the batch's planes in batch order. A plane that misses the tile is
  skipped by a test the whole threadgroup agrees on, so nothing diverges. The tests cost 2.3e6 a batch of
  500 (*derived*).
- **Per voxel and plane:** project `v` on the plane to `(h, k)`. Scan the pixels within 1.5√3 of that
  point, a 6 × 6 box. Keep a pixel when its own stencil covers `v`. Add `w · c` and `w · q` in registers.
- **Write:** the tile is written once at the end, as `prev + acc`, so a batch adds to the resident grid.
  Each voxel has one owner, so there is no race between threads or launches.

Why it is attractive:

- **Same sum, same floor.** Membership uses the probe's own rule: `round(loc) − 1 .. round(loc) + 1` per
  axis, with `loc = h·r1 + k·r2`. The pull adds the push's terms in another order. Write that expression
  once in the kernel `header`, shared by both forms, so the compiler contracts it the same way. The float32
  coordinates' floor (1.07e-4 against the oracle) is unchanged.
- **Deterministic by construction.** Each voxel's order is the planes' order, then the scan's order. Scan
  in the pixel loop's order and the CPU's order becomes reachable. That is the families note's open
  question: possible, not promised (FMA contraction).
- **Pay for the stencil once.** 58 % of the push's flops are window weights. A first kernel can write each
  pixel's `t0(3)` and nine normalised weights per plane: 48 B a pixel, 0.49 GB a batch of 500 (*derived*).
  The pull kernel then reads them. This is P5. Without it, each kept pair recomputes the three weights of
  each axis.
- **Cost.** About 1e5 active voxel visits a plane, each scanning 36 candidates. That is about 3.6e6 cheap
  rejections and the push's 5.5e5 weighted pairs, with no atomics (*guessed*: active fraction about 1/3 of
  a tile's threads). Low-frequency tiles meet every plane, so the slowest threadgroup walks the whole batch.
  That bounds the tail of a launch, not the throughput.
- **What to watch.** Idle threads where the slab is thin in a tile (try 4 × 8 × 8 or 8³). Staging the
  plane's patch, about 19 × 19 pixels for an 8³ tile, in `threadgroup` memory is P1's refinement, kept only
  above 30 %. Symmetry copies are extra planes. The disc's conjugate mates are already explicit pixels in
  the probe's data.

If a sorted form is still wanted (form 2), take P2 whole. Emit duplicates in plane order with offsets
from `mlx_cumsum`. Sort the uint32 voxel-tile key with stable `mlx_argsort`. Find ranges by boundary
detection. Read through `sort_idx`. Size the buffers by P3. Expect about 2 tile duplicates a sample at
8³ (*derived*: (1 + 2/8)³), 4e7 keys per 1,000 planes; how fast MLX sorts that many keys is unmeasured.
Integer atomics give exact counts, if a histogram is ever needed; only float sums depend on order.

## 4. The other deliverables

- **K3, arbitrary reference sets.** Treat particles as splats and reference tiles as screen tiles. Expand
  each particle into the reference tiles its list touches, sort stably by tile key (P2), and every
  reference tile gets a contiguous run of its particles in particle order. This is MoE routing, and MLX's
  answer to it is `mlx_gather_mm` with `sorted_indices=.true.` (already public; its fast route serves
  single-row left operands). Whether the dense score's products, batched over angular bins, fit that route
  is K3's first measurement. Occupancy is then 1 within a particle's run, minus the references of the tile
  outside its list.
- **K7 and K4's reductions.** Put P4 into K1's fused tail. Each tile kernel keeps the K best per particle
  in registers. A small merge across tiles, with ties going to the lower global reference index, replaces
  `mlx_argpartition` over a written table. This is SIMPLE's argmin rule. P4's structure, the query in
  registers and candidates in `threadgroup` memory, also suits the particle-side shift variant. A thread
  holds one shifted particle and the reference rings stream past; the U shifted copies are never written,
  which matters because the maps are bandwidth-bound.
- **K5, the pose objective.** One threadgroup per (particle, pose) reduces 21 numbers over about 6,000
  pixels. Use per-thread partials, then `simd_sum`, then a fixed-order sum over the SIMD groups in
  `threadgroup` memory. That is a fixed tree, repeatable, and mlx3D's evidence that `threadgroup` memory
  works applies. P3 keeps the lockstep optimizer's convergence flags on the device: one wait per iteration
  for all particles, never one per particle (a wait costs 0.17 ms, *measured*, K8). The analytic gradient
  lives in the kernel, so `mlx_custom_function` (pending 6) is not needed.

## 5. The library and the record

- **Launch configuration.** mlx3D launches one kernel object at a different grid and output shape per
  call. Our `mlx_metal_kernel` fixes the configuration in `new`, so K2 keeps a kernel per tile size. mlx-c
  keeps the kernel and the configuration apart, so an `apply` with its own launch is possible. Add it only
  if a kernel rebuild is measured to cost something; MLX should reuse the compiled library across
  configurations (unverified).
- **Templates against parameter arrays.** K2 passes sizes as template integers, which compile one pipeline
  per value. mlx3D passes them in a small int32 input (`iparams`). Use templates for constants of a run,
  and an input for sizes that change per call, such as P3's capacity and counts.
- **Apple question 26, part 1.** mlx3D's production kernels declare `threadgroup` arrays in the kernel
  body and synchronise with `threadgroup_barrier`, through the same `metal_kernel` path. That is practice,
  not a guarantee. Add it to the question's "Meanwhile" and keep asking.
- **A risk to watch.** MLX issue #4603 reports wrong rows from a custom kernel under MLX's default
  `MathModeSafe` on M3 Ultra with macOS 27.0, exact under Relaxed. The gates' repeatability and oracle
  checks would catch it. Note it before any OS upgrade on the M5.

## 6. Not taken

- Half-precision payloads (mlx3D's splat colours): the families' precision rule stands.
- `custom_function` and `custom_vjp` around kernels: no toy needs MLX's autodiff.
- SIMD-reduced atomics: deterministic forms are required for K6, so the atomic kernel stays a speed
  reference only.

## 7. Proposed decisions

1. K6's plan adds the pull (section 3) as form 3, with the stencil pre-pass as a measured variant.
   Recommended: yes. It is the only form that is deterministic, needs no sort, and may follow the CPU's
   order.
2. K3's plan measures sorted `mlx_gather_mm` on P2's runs before writing any masked-tile kernel.
   Recommended: yes.
3. K7 is delivered inside K1's fused tail (P4), with `mlx_argpartition` as the graph form. Recommended:
   yes.
4. Kernel sizes that change per call come in an int32 input, not a template (section 5). Recommended:
   yes, as a line in the `mlxf-binding` skill once K6 shows it.
5. `apply` with a launch of its own waits for a measured rebuild cost. Recommended: wait.
