# Review of the mlx-fortran roadmap

2026-11-24. Advisory review of the [roadmap](mlxf_roadmap.md), not a change to its rulings.

**Keep the four kernel families, the public-API-first rule and the independent host oracles.**
Milestone 1 makes a strong case for dense scoring and a good case for dropping accelerated precision.
The biggest unanswered question is not whether another GPU kernel can be faster in isolation. It is
whether a SIMPLE-shaped driver finishes useful work sooner when several parts share the GPU and memory.
The existing dense scorer can answer much of that before a new wrapper or fused kernel is written.

## 1. Measure added capacity with the scorer already in hand

The [milestone 1 report](../completed/mlxf_milestone1_report.md) measured dense GPU scoring at 4.69 times
the standalone rate of 30 CPU threads. That is not a measurement of the throughput the GPU *adds* while
the cores are busy. A concurrent CPU streaming load slowed the GPU path by 18%; one benchmark process
had a 21-23 GB footprint despite an MLX active peak of 10.3-10.7 GB. Neither number tells us the
whole-machine cost of six parts.

Use rank 0b to benchmark the same fixed total workload before and after the refactor. Split it among
one, three and six parts, including representative host preparation and collection. Record time until
the last part finishes, GPU and host work completed, per-part footprint and peak machine memory pressure.
Use matched CPU records where available; label unmatched results as toy throughput, not SIMPLE speedup.
Before timing, state what loss of throughput or breach of the memory budget would reopen the question
of a single GPU-owning process. This also gives the refactor a stronger check than unchanged suite
counts: an extra host wait or resident copy can pass every numerical test.

## 2. Let each toy start when its public wrappers are ready

Keep the Phase 3 API review. After it, rank 1b need not block every toy until its *last* wrapper lands.
The [kernel deliverables](mlxf_kernel_families.md) give narrower dependencies: K1 needs the Metal
wrapper and the refactored polar toy; K2 needs Metal and a real FFT for its benchmark; K8 needs the
forward and inverse real FFTs, but neither Metal nor the gathered matrix products. Use those dependencies
in the ranking, subject to the existing rule on disjoint files and maintainer review.

Accept the proposed K8 slot after K2. Before budgeting PCG, reconcile the transform count in section 6
of the kernel note: `2 + 4m` at two iterations gives 10, while the next line says 21 per half. State
which setup or solve steps are included before using either estimate. Judge the solver by **time to
the same true residual**, with iteration count and peak memory alongside it. A cheaper dot product
can lose overall if convergence takes longer. Make the master-only timing exception explicit in the
readiness criteria: PCG runs when the parts are idle, unlike families A to C.

## 3. Decide what correctness means before comparing speed

- **K4, shift lattice.** Reference-side shifts target the existing map cells; particle-side shifts
  target agreement in distribution. A correct particle-side calculation can still change which
  candidates survive screening. If exact cells are required, select reference-side shifts. If not,
  freeze a decision-level test before timing: compare mode displacement and candidate retention on
  representative and near-tie cases against a stated statistical bound.
- **K6, gridding insertion.** SIMPLE's offload prototype demonstrates opportunity, not the speed of a
  correct scatter: its shared-voxel updates are unprotected. The family-wide rule gates repeatability,
  while the K6 exit only records it. Decide whether bitwise repeatability on one GPU configuration is
  required; do not conflate it with reproducing the CPU's summation order. After K2, try one protected
  update on a collision-heavy fixture, checking numerator, density, repeatability and peak scratch
  memory. This tests the premise of an easy win without moving the whole K6 deliverable forward.

## 4. Apply the retention rule to the work the caller receives

K1 targets a tail that took 0.90 of 1.93 seconds **with a barrier after each stage**. Even taking those
times as additive, a 1.30x faster tail gives only `1.93 / (1.03 + 0.90 / 1.30)`, or about 1.12x on the
whole score. That is an illustration, not a prediction for the asynchronous driver.

Name the denominator for the 30% rule before the run. Use tail timing to explain the result, but
decide whether to maintain the second path from the canonical driver's elapsed time at equal work and
accuracy, including submission, synchronization and collection. Keep the graph as the reference.

**Next decision:** approve the dense-driver baseline as part of rank 0b while parity proceeds. Its
result should inform the sharing model and memory budget before K1 tuning; it need not delay the API
review or require changes to SIMPLE.
