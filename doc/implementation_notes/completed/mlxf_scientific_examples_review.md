# Review: the three scientific examples (`mlxf_scientific_examples.md`)

Archive disposition, 2026-11-24: completed review of the original design. Findings and recommendations
below retain their original date. The durable host-reference work addresses the scratch-evidence issue;
see [the preparation record](mlxf_scientific_examples_preparation.md). Future implementation and conversion
to plan form remain in [the active examples note](../planned/mlxf_scientific_examples.md).

Status, 2026-11-22: review of the note at mlx-fortran `2862201`, against SIMPLE `7ec7e2972` (the note's pin;
the checkout had no later commit). Reviewer: Claude (interactive session), for Hans. **Applied the same
day:** Hans pulled example 1 into milestone 1 (its decisions 15 to 18, Phase 5b). Findings 1, 2, 5 and 8 are
in the note's decisions 10 and 11 and its text. Findings 3, 4 and 6 are in both plans. Finding 7 is open
(copy the dry run), and finding 9 waits for the hold.

## Verdict

The proposal is sound, and its mathematics checks out. It is faithful to SIMPLE where it claims to be, and
its tests are built the right way: every expected value comes from an independent host construction,
never from the code under test. It needs four small corrections before implementation (P2 below) and one
scheduling rule. The best home for it is the plan that follows milestone 1: it covers, in the measured
order, the first four items of milestone 1's roadmap (section 9 of `mlxf_milestone1.md`).

## What was checked

- **The derivations, numerically** (Python with numpy, in the session's scratch):
  - The ring family is Friedel-symmetric to 6e-16.
  - The Bessel tail bound is valid and tight: at z = 1.18, 2.95 and 9.42 it picks K = 12, 17 and 30, with
    bounds of 3.5e-13, 4.0e-13 and 4.2e-13 against actual truncation errors of 3.2e-13, 3.0e-13 and
    1.6e-13. This matches the note's dry run (order 12, 3.22e-13).
  - The spectral PCG operator equals the seven-point stencil to 7e-15, with d in [1, 13], so the bounds
    0.25 and 13.25 (condition number 53) hold.
  - The unpadded preconditioner is exact, so one step suffices.
  - Kaiser-Bessel `beta` = 6.486.
  - The padding scale `8 * G * Fpad` = 1/N³ for a centred unit point.
  - The full-ring loss equals SIMPLE's distance d (decision 20 of the design plan).
- **The SIMPLE conventions it relies on**, read at the pin:
  - Polar coordinates `(k sinθ, −k cosθ)` and phase factor 2π/box (`simple_polarft_core.f90`: `DPI` is π,
    `A = DPI/(box/2)`).
  - The KB window: `nint(loc) − 1 .. + 1`, `beta` as written, and `apod` returning I0(0) = 1 at |x| = 1.5
    (`simple_kbinterpol.f90`, `simple_projector_pft_batch.f90`).
  - Shift-cell areas between midpoints, half a step past the ends, clamped at zero
    (`simple_polar_shiftmap.f90`).
  - The shiftmap's Fourier-Bessel form, transformed in 2D over (order, rotation) with the orders folded
    modulo `nalpha` (`simple_polarft_shiftmap.f90`).
- **Its fit with the repository:** the test policy (budget, named-only sub-suites, testers), the skills,
  and milestone 1's decisions, file table and run rules.

## Findings

### P2: correct before implementation

1. **The interpolation window is discontinuous, so a float32 coordinate can pick a different stencil.**
   - SIMPLE's three-point KB kernel equals 1 at its window edge (I0(0)), against 105 at its centre. The
     interpolant therefore jumps at half-integer coordinates. On a smooth test field the jump is 3e-3 to
     1.3e-2, three orders of magnitude above the 1e-5 cap.
   - This is SIMPLE's own behaviour and is copied faithfully. The risk is only a device coordinate (float32)
     landing on the other side of a half-integer from its real64 twin.
   - The note's rotations never produce an exact half-integer (2a/65 cannot equal (2n+1)/2), so only a near
     miss can do it.
   - Rounding is a second trap. Fortran's `nint` rounds half away from zero; numpy-style `round`, which MLX
     follows (to be confirmed against MLX), rounds half to even.
   - **Fix:**
     - The fixture asserts on the host that every sample coordinate lies at least 1e-4 from a half-integer
       (*guessed*: well above float32 coordinate error at |t| ≤ 12). The explicit boundary queries are the
       only exception, and they use exactly representable half-integers.
     - The device computes the stencil base as `sign(t) * floor(abs(t) + 0.5)`.
     - A convention test pins 0.5, 1.5, 2.5 and their negatives.
2. **It cannot run beside milestone 1's run.** Example phases 0, 1 and 4 edit files that milestone 1's
   Phases 2 to 5 create or own: the `kernels` area, `src/test/mlxf_test_registry.f90`,
   `src/test/mlxf_test_defs.f90` and `src/test/mlxf_kernel_polar_table*.f90`. Under milestone 1's
   decision 6, a change the run did not make is a stop. Phase 1 of the examples also extends files that do
   not exist before milestone 1's Phase 4. **Rule:** example work starts after milestone 1's Phase 5, or
   between its two runs. It never starts while `mlxf_m1` is running.
3. **It needs more operations than milestone 1 adds.** Milestone 1's decision 8 adds only `mlx_rfft` and
   `mlx_irfft`. Each example adds its own list:
   - **Example 1:** a complex FFT (batched 1D, or 2D) for the shift maps, `logsumexp`, a minimum position
     (`minloc`), and `sqrt`.
   - **Example 2:** the 3D real and complex FFTs and their inverses.
   - **Example 3:** `floor`, `abs` and `sign` (for the rounding), a gather (`mlx_take` and its siblings),
     `mlx_scatter_add`, and the n-D FFTs.

   The note already says "a wrapper only when its phase needs it", so this is decision 29 at work. The
   converted plan should list the operations per phase, with their area testers and file rows.
4. **The tester names and placement break the tester rule** (a tester sits beside the module it tests, as
   `mlxf_<module>_tester.f90`).
   - `src/test/mlxf_polar_shiftmap_tester.f90` has no module `mlxf_polar_shiftmap`, and
     `mlxf_spectral_volume_tester.f90` sits beside `mlxf_kernel_spectral_volume.f90`.
   - **Suggested:**
     - the shift map becomes a submodule `mlxf_kernel_polar_table_shiftmap.f90` of milestone 1's workspace
       owner, which matches the note's own "extend, not another scorer";
     - its checks become the sub-suite `polar_shiftmap` of the owner's tester;
     - the other two kernels get `mlxf_kernel_spectral_volume_tester.f90` and
       `mlxf_kernel_fourier_projection_tester.f90`.

### P3: wording and record

5. **The tolerances' home does not exist yet.** The note says "the existing `mlxf_test_defs`", but that
   module is new in milestone 1's Phase 4.
6. **"First Fortran-order position" needs care on maps of more than one dimension.** MLX's arg-minimum over
   a flattened array follows MLX's row-major order. Flatten with the library's Fortran-order `reshape`
   first. Whether MLX's GPU arg-minimum breaks ties at the first index is for the note's tie test to
   establish. Do not assume it.
7. **The dry-run evidence is in `/private/tmp` on the Mac**, which a reboot clears. Copy
   `check_mlxf_toy_design.py` and its log somewhere durable (`~/agent_work/` or the repository).
8. **The PorF and exp_gate profiles have no producing commit or machine.** If Hans records them and they
   are at or after `7ec7e2972`, they can serve as milestone 1's decision 5 profile. They would make f
   *measured* instead of parametric.
9. **For an unattended run, the note needs the plan-guide form:**
   - a pinned base;
   - a change type per phase;
   - stop conditions and the gates no ruling may waive, written as a list;
   - every library file named in the file table.

   As a design for interactive work it is ready once 1 to 4 are fixed.

## What the profiles say about priorities

By the note's own numbers, dense scoring is 14.5 % (PorF) and 8.5 % (exp_gate) of the fill's
thread-seconds, while building the shift maps is 35 % and 57 %. Milestone 1's verdict is about the scoring
alone. It is the right first proof of the binding and the pipeline, but on these workloads its end-to-end
value is small whatever the speedup. The shift maps (example 1) carry the larger share. That is design
decision 38's ruling (R3) again, now measured on the production scorer.

## Recommended integration

1. **Milestone 2 = this note**, converted to plan form at the milestone-1 hold (design decision 32). It
   replaces the first four items of milestone 1's roadmap:
   - shift refinement → example 1;
   - the assembly (PCG solves and the NU filter) → example 2;
   - n-D FFTs, gather and scatter → examples 2 and 3.

   Packaging and SIMPLE's integration stay on the roadmap. Section 9 of `mlxf_milestone1.md` then points
   to this note.
2. **Order:** milestone 1's Phases 0 and 2 to 5 (M2 Ultra), then 6 and 7 (M5 Ultra), then the hold. After
   it, the examples' Phases 0 to 5 in the note's order: shift maps, reprojection gather, spectral and PCG,
   adjoint and scatter, tutorials.
3. **One choice for Hans: pull example 1 forward.** It would become a milestone-1 Phase 5b on the M2 Ultra,
   so that the M5 Ultra session measures scoring and shift maps on the same day. It costs a broadening
   ruling:
   - decision 8 gains a complex FFT, `logsumexp` and a minimum position;
   - one phase;
   - file rows;
   - a later M5 verdict.

   The gain is that the Apple case rests on the larger share of the fill. Without the ruling, milestone 1
   stays as pinned and example 1 opens milestone 2.
