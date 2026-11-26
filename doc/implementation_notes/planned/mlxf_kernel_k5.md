# K5: the pose objective of continuous refinement (B2) as a toy `cartft_calc` with its driver `cartft_pose_opt` (run `mlxf_kernel_k5`, on the M5 Ultra)

Status, 2026-11-26: planned, not ruled.

Base: the commit that holds this plan (the run pins its hash in Phase 0). Checked against `6f1af0d` with the
working tree of 2026-11-26; SIMPLE at `d354efee2`, read through `git show` only.

Depends on:

- `mlx_metal_kernel` (`src/core/fast/mlxf_fast.f90`; binding contract policy, section 12). Validated: yes for
  complex64 inputs, float32 and complex64 outputs of rank 2, two-dimensional grids, template integers
  (`unit_fast`; the toy projector's fused gather). Validated: no for a thread that loops over many pixels with
  27 reads each (Phase 0, probe A), and no in the repository for `threadgroup` memory, `threadgroup_barrier`
  and `simd_sum` (one scratch probe of the first two is recorded in the policy; no file under `src/` uses them).
- `mlx_rfftn`, `mlx_take`, `mlx_round`, `cos`, `sin`, `cmplx`, `real`, `aimag`, `sum`, `reshape`, `mlx_to`,
  `mlx_synchronize`, `mlx_peak_memory`: public in `src/core/mlxf.f90` (read). Validated: yes (their areas).
- `mlxf_oracle_pose` (`src/test/mlxf_oracle_pose.f90`). Validated: standalone only (32 checks, largest error
  7.8e-15 on identities, *measured*, `completed/mlxf_oracles2_report.md`); no tester asserts
  `oracle_pose_selfcheck` yet (*exact*: `rg oracle_pose src test scripts` finds the oracle alone).
- `scripts/run_parts.sh` with `RUN_PARTS_BENCH`, `RUN_PARTS_SUITE`, `RUN_PARTS_UNIT`. Validated: yes (K2).
- The seam's pieces: `mlxf_toy_device_work`, rules `seam`, `mirror`, `arity`, `scripts/check_toy_offstate.sh`,
  `test/offstate/`. Validated: yes (`completed/mlxf_toy_seam_report.md`).
- Roadmap decisions 7 (order), 8 (oracle and repeatability), 9 and 15 (the performance contract and the 30 %
  rule's denominator), 11 (toys mirror SIMPLE), 12 (the conditions that reopen one GPU-owning process).

## 1. Why

Continuous refinement (`refine=cont`) polishes each particle's pose by a damped Gauss-Newton solve on five
parameters: a rotation-vector increment applied on the right and two shifts. Every trial pose costs one pass
over the particle's band of the Fourier plane: at each pixel a 27-voxel quadratic B-spline gather of the
reference with its three derivatives, a phase, and the products that sum to an objective, a gradient of five
numbers and a symmetric matrix of fifteen. In SIMPLE one thread carries one particle through its whole solve
(`srch_cont` of `simple_strategy3D_cont.f90`), at most 41 passes per particle (*exact*: one seed pass in
`refine_pose`, at most one pass per iteration of `lm_solve`, 40 iterations).

The pass is about 520 flop per pixel (*derived*: about 376 for the coordinates, the nine weights and slopes,
27 complex reads and the separable contraction to a value and three derivatives; about 142 for the model,
the three Jacobians and 23 sums), so about 3.2 Mflop per pass at 6,136 pixels (*exact* count of the half
plane's pixels on shells 2 to 62 of a box of 160). The families note guessed 0.5 kflop and 3 Mflop: confirmed.

K5 delivers the pass as a device evaluation of many (particle, pose) pairs at once and the solve as a
lockstep loop: one launch and one host wait per iteration for all particles of a batch, the 5 by 5 solve of
each particle on the host in double precision. It reports what a SIMPLE plan needs: the accuracy float32
arithmetic reaches against a double-precision oracle, the recovery of planted poses, and evaluations per
second alone and as 3 and 6 processes sharing the GPU.

## 2. Contract

**Deliverable.** A toy `cartft_calc` (SIMPLE's `src/main/cftc/simple_cartft_calc.f90`) with `new`, `kill`,
`set_ref`, `new_ptcls`, the particle setters, `predict`, `pose_normal_terms` and `shift_normal_terms`, driven
by a toy `cartft_pose_opt` (`simple_cartft_pose_opt.f90`), all test-only code in `src/test/` against the
public `mlxf`. No file under `src/core` or `src/defs` changes; a missing wrapper is a stop.

**Exit** (families note, section 8): the objective, the gradient and the matrix match the host oracle; planted
poses are recovered; evaluations per second are timed, alone and as 3 and 6 processes.

**In the integration shape from the start:** host files import no MLX name; the device state is one
`class(device_work)` component; glue is a submodule `<unit>_mlx` with stubs under `#else`; both ledgers; the
off-state program asks the new class for the MLX backend; cycles and refusals in sub-suite `seam`.

### What the check found

Read on 2026-11-26. A premise of the families note or the mlx3D note that the code contradicts is
marked **differs**.

1. **differs.** `gather_packed_bspline3_window_grad` is in `src/main/interp/simple_cartesian_fourier.f90`, not in
   `cftc/simple_cartft_calc.f90` (families note, section 4). The calculator's private `gather` calls it.
2. **differs.** The optimizer's step control is in a third file the notes do not name:
   `src/utils/math/simple_lm_solver.f90` (`lm_solve`, `lm_scale_system`, the abstract `lm_problem`), with
   `spd_solve_rel` of `src/utils/math/simple_linalg.f90`. `simple_cartft_pose_opt.f90` and its submodule
   `simple_cartft_pose_opt_system.f90` hold the transaction and the problem's bindings.
3. **differs.** One evaluation does not reduce "21 numbers". `pose_normal_terms` accumulates 23 sums for the
   Euclidean objective (the residual's power, 5 gradient sums, 15 matrix sums, and the two sums of the
   regression slope, `weighted_power` and `weighted_cross`) and 27 for the correlation (the cross term, the
   prediction's power, 5 gradient sums, 3 sums of the model's gradient, 15 matrix sums, the two slope sums),
   plus one sum per shell when `shell_residual` is present. `refine_pose` always asks for the shell residual.
4. SIMPLE's arithmetic: the gather runs in single precision at coordinates rounded to single precision; the
   phase tables, the products and all sums are double precision; the finalisers
   (`finalize_euclid_normal_terms`, `finalize_cc_normal_terms`, `curvature_scale`) are double. SIMPLE's own
   sums therefore carry the floor single-precision coordinates set. The oracle is double throughout: stricter.
5. **differs.** SIMPLE has no lockstep. `lm_solve` is a loop that calls the problem's `eval` itself; a
   transaction of one particle runs to its end on one thread. A lockstep needs the loop inverted: a solve
   that stops at each evaluation request and resumes with the answer. The families note states the lockstep
   as the design; it does not say that `lm_solve` has no such form.
6. One `eval` returns the objective, the gradient and the matrix of the trial together, so a rejected trial
   costs one pass and an accepted one costs no second pass (`pose_problem_eval`). At most 41 passes.
7. **differs.** The oracle's `solve` (`pose_solve`) is not `lm_solve`: it tests the gradient before the
   pivots where `lm_solve` tests observability first; a failed damped factorisation ends it where SIMPLE
   counts a rejection; its rejection multiplier has no cap; it has no cumulative bounds (`trs`,
   `athres_cont`), no `active` mask and no priors; its statuses are its own. On its fixture none of these
   acts (four accepted steps, no rejection, the gradient's stop: *measured*, oracle report, finding 5).
8. **missing in the oracle.** The fixture's inputs (`fixture_volume`, `fixture_ctf`, `fixture_sigma2`) are
   private, so a toy cannot be fed the oracle's own fixture; a problem holds one particle; `pose_new` asks
   `kto` below `box/2`; there is no shell residual. The public interface (`new`, `set_particle`, `model`,
   `objective`, `derivatives`, `shift_derivatives`, `scale`, `power`, `solve`, `oracle_pose_reference`,
   `oracle_pose_gather`, `oracle_pose_euler`, `oracle_pose_rotate`) is enough to build fixtures (decision 13).
9. `threadgroup` memory and `threadgroup_barrier` have one scratch probe behind them and no use in the tree.
   The binding contract policy (section 12, "Measured by the toys") and Apple question 26 record that a
   `threadgroup` array with a barrier built and gave a correct 64-element group sum in a probe. No file under
   `src/` holds that probe, and `simd_sum` appears nowhere in the repository.
10. SIMPLE's batch is `nthr` times `BATCHTHRSZ` = 50 particles (`simple_strategy3D_matcher.f90`,
    `simple_defs.f90`): 1,500 at 30 threads, 500 at 10, 250 at 5 (*derived*). Defaults in
    `simple_parameters.f90`: `athres_cont` 10 degrees, `trs` 0 (with `trs = 0` only the rotation is active),
    `cont_prior` 'none'.
11. `scripts/run_parts.sh` waits for a one-minute load of at most 2 by default; the rule of the kernel plans
    is 4. The run sets `RUN_PARTS_LOAD=4`. The launcher reads the rate in column 20 of the bench's table, the
    work in 21, the MLX peak and cache in 26 and 27, the median pass in 30: the new bench keeps that layout.
12. The pose oracle's record is `completed/mlxf_oracles2_report.md` (run `mlxf_oracles2`).
13. `set_ptcl_cc` and `set_ptcl_euclid` take the CTF's parameters (`ctfparms`); `refine` takes an `ori`;
    `set_ref` takes a real cube `(box, box, box)`; `predict` returns the phase times the gathered reference on
    the full disk, without the transfer. The objective is a property of the slot (cc or Euclidean).
14. No `cartft` or pose name exists in `mlxf_test_registry.f90`, `mlxf_test_defs.f90`, either ledger or
    `test/offstate/` (*exact*, `rg`). No note under `doc/` holds a SIMPLE timing of continuous refinement
    (*exact*, `rg` for `cont_refine`, `pixel-evaluation`, `passes per solve`): no record in hand.

Not verified at writing, read by the run in Phase 0: the scaling of SIMPLE's `image%fft` (the oracle's
1 / box**3 is the specification here); the period of `cyci_1d` over `loop_lims(3)` in `set_ref`'s wrap table
(the oracle wraps with period 2 box); the floor in `lm_solve`'s predicted-reduction test; whether SIMPLE's
callers ever give two slots of a batch different `kfromto`; what rule `mirror` reads of a dummy list.

### The queue

K5 is third (roadmap decision 7: K3, K4, K5, K6, K7) and starts from the commit that holds K4's verified
result. K3 and K4 edit the polar toy; K5 brings new classes and touches none of the polar toy's files. The
files K5 shares with every earlier run are `src/test/mlxf_test_defs.f90`, `src/test/mlxf_test_registry.f90`,
`src/test/test.inf`, `src/test/mlxf_toy_seam_tester.f90`, `scripts/toy_mirror.txt`, `scripts/toy_seam.txt`,
`test/offstate/mlxf_offstate_exec.f90` and the families note. Phase 0 re-checks exactly these premises:

- the extents of `AREAS` (12), `BENCHES` (4) and `NAMED_ONLY` (4) in the registry, and the `run_bench` cases;
- the members of `parameters` (`box`, `box_crop`, `nthr`, `trs`, `nstates`, `l_mlx` are used here);
- the count of `unit_kernels` (1,955 today) and of its sub-suite `seam` (88), the fast gate's entries (13)
  and its time (10.7 s today against the bound 38.74 s);
- `SEAM_PENDING = 0` and the ledgers' line forms; the off-state program's checks;
- the launcher's column layout and settings.

A changed number is recorded in Progress and replaces the plan's; a changed form (a ledger's line form, the
registry's tables, the launcher's columns) is followed. Nothing in K5 depends on K3's or K4's results.

## 3. Decisions and rulings

Numbered, never renumbered. A decision the maintainer has not ruled carries the recommendation the run takes.

**1. Scope.** Two classes and one solver module. `cartft_calc`: the prepared references, the particle slots,
`predict`, `pose_normal_terms`, `shift_normal_terms`, and a batched evaluation (an addition). `cartft_pose_opt`:
`refine_pose` and a batched lockstep transaction (an addition). `mlxf_toy_lm_solver`: SIMPLE's damped solve in
a resumable form. Both objectives (cc and Euclidean) are carried: the oracle has both, the per-pixel products
are shared, and the difference is the list of sums and a host finaliser.

**2. Modules.**

| Module (file `src/test/<module>.f90`) | Class | Holds |
| --- | --- | --- |
| `mlxf_toy_lm_solver` | host | `lm_problem`, `lm_options`, `lm_outcome`, `lm_scale_system`, `spd_solve_rel`, the resumable solve |
| `mlxf_toy_cartft_calc` | host | the type, the host staging of references and slots, the finalisers in double |
| `mlxf_toy_cartft_calc_mlx` | glue | the `_mlx` procedures; stubs under `#else` |
| `mlxf_toy_cartft_workspace` | device | the reference bank, the slots, the pixel table, the graph form |
| `mlxf_toy_cartft_workspace_fused` | device | the fused kernel's source, spec and launch (deleted with its ledger lines if the verdict is "delete") |
| `mlxf_toy_cartft_pose_opt` | host | the type, the pose problem, the transaction, the lockstep, `right_increment_rotation` |
| `mlxf_cartft_fixture` | test | seeded volumes, particles and poses through the oracle's public interface |
| `mlxf_oracle_pose_tester` | test | asserts `oracle_pose_selfcheck`: each error within its limit |
| `mlxf_toy_cartft_calc_tester`, `mlxf_toy_cartft_pose_opt_tester` | test | sub-suites `cartft_calc`, `cartft_pose_opt` |
| `mlxf_bench_cartft` | test | `test=bench_cartft` |

`cartft_pose_opt` has no device state and no glue: every MLX object is the calculator's.

**3. Names and dummies are SIMPLE's.** Types are `real32` and `real64` where SIMPLE writes `real` and `dp`.

| Toy procedure | SIMPLE | Difference |
| --- | --- | --- |
| `cartft_calc%new( self, nstates, box, nptcls, params )` | `new` | optional last `params` names the backend, as `projector%new` |
| `kill`, `ref_exists`, `ptcl_is_valid`, `get_ptcl_npix`, `get_ptcl_power`, `new_ptcls( self, nptcls )` | same names | none |
| `set_ref( self, state, iseven, volume )` | `set_ref` | none: a real cube `(box, box, box)` |
| `set_sigma2( self, kfrom, sigma2 )` | `set_sigma2` | none |
| `set_ptcl` => `set_ptcl_cc( self, iptcl, observed, ctf, kfromto )`, `set_ptcl_euclid( self, iptcl, observed, ctf, half, kfromto )` | same names | the fourth dummy is the CTF's values on the pixels, where SIMPLE passes `ctfparms`: the toy has no CTF model |
| `predict( self, state, iseven, rotmat, shift, prediction )` | `predict` | none |
| `pose_normal_terms( self, state, iseven, iptcl, rotmat, shift, objective, gradient, hessian, shell_residual )` | same | none (10 dummies, exempt as mirrored) |
| `shift_normal_terms( self, state, iseven, iptcl, rotmat, shift, objective, gradient, hessian )` | same | none |
| `cartft_pose_opt%new( self, box, box_crop, trs, rotation_bound, maxits, rotation_scale, shift_step_bound )` | `new` | none |
| `refine_pose( self, calc, state, iseven, iptcl, rotmat, shift )`, `kill`, `get_status`, `get_objectives`, `get_shell_residual` | same names | none |
| `right_increment_rotation`, `lm_scale_system`, `spd_solve_rel` | same names | none |
| `lm_problem` with `limit_step`, `propose`, `accept`, `penalty`, `observable`, `free`, `negligible_step` | `lm_problem` | no `eval`: the evaluation is the caller's (decision 11) |

Additions (ledger lines with their reasons; five dummies at most, a record beyond):
`cartft_calc%pose_normal_terms_batch( self, batch, terms )`, `set_eval_form`, `set_eval_tile`, `eval_counts`,
`message`; `cartft_pose_opt%refine_pose_batch( self, calc, batch )`, `message`; `lm_state`, `lm_begin`,
`lm_advance`, `lm_answer`. The records `cartft_pose_batch` (per entry: slot, state, half, rotation, shift; out:
status, the seed's and the final objective, the passes) and `cartft_pose_terms` (per entry: objective,
gradient, matrix, curvature scale, optional shell residual) stand in `mlxf_test_defs.f90`, as `fproject_spec`
does. Statuses carry SIMPLE's names (`CARTFT_*`, `LM_*`) and values.

**4. The backend: `cartft_calc` refuses the host; `cartft_pose_opt` has no switch.** `new` takes
`params%l_mlx` (default true). With `l_mlx = .false.` the calculator refuses with "the toy has no host route",
as the projector and the reconstructor do. Reason: SIMPLE's host kernel exists and is validated by SIMPLE's own
testers; a miniature of it would be a second copy of the oracle's formulas in single precision, would prove
nothing this plan needs, and its timing would not be SIMPLE's. `cartft_pose_opt` is host code throughout: it
drives whatever calculator it is given and returns that calculator's refusal. The off-state program asks
`cartft_calc` for both backends ("built without MLX", "no host route") and runs the resumable solve on a
five-parameter quadratic it evaluates itself, so the optimizer's host part is shown to work without MLX.
The alternative, a host route in SIMPLE's arithmetic (about 200 lines), is not built.

**5. The prepared reference.** `set_ref` embeds the cube at the centre of the padded box M = 2 box and
multiplies it by the Kaiser-Bessel envelope over the B-spline's along each axis, on the host in double,
rounded once to float32 (SIMPLE: `center_embed_real3d`, `ref_weight`). The device transforms it (`mlx_rfftn`,
times 1 / box**3 in single precision) and expands the half spectrum to a full cube of side E = M + 3, logical
index q of -(M/2+1) .. M/2+1 at q + M/2 + 2, by device gathers with the Friedel mate's conjugate where the
first index is negative and period M on each axis (the oracle's wrap; the toy projector's `expand` is the
pattern). The kernel then reads without a wrap or a conjugate branch: with shells at most box/2 a coordinate
is at most M/2 in modulus and a tap at most M/2 + 1 (*derived*). The cubes of all states and halves are
stacked into one bank `(E, E, E, 2 nstates)` at the first evaluation after a `set_ref`.
Sizes (*derived*): at box 160, E = 323, one cube 323**3 x 8 B = 269,586,136 B, two halves 539,172,272 B; the
packed half SIMPLE keeps is 131,891,200 B a cube. At the fixture's box 16, E = 35 and a cube is 343,000 B.

**6. The particles.** A batch has one band and one objective; a slot whose `kfromto` or kind differs from
the batch's first is refused with a message (a difference from SIMPLE, whose slots are independent). The
pixel table is the half plane of the band in SIMPLE's loop order (k outer, h from 0 or 1), then the central
pixel when the band starts at shell 0, padded with zero-weight pixels to a multiple of the block length: per
pixel h, k and a multiplicity (2 for a half-plane pixel, 1 for the centre, 0 for padding). `set_ptcl` runs
SIMPLE's `fill_ptcl` on the host for its slot only (weights by `rsqrt_sigma2`, the CTF's modulus, the power in
double) and calls no library procedure, so a team may fill slots as SIMPLE's does. The upload of all stale
slots is one serial step at the first evaluation after a `set_ptcl`: `observed (npix, nptcls)` complex64 and
`transfer (npix, nptcls)` float32. At 500 slots of 6,144 pixels that is 36,864,000 B (*derived*).

**7. The evaluation's arithmetic.** Per entry (one particle at one pose) the host sends the slot's index,
the reference's index, the two rotation rows times the padding factor and the shift: 2 integers and 8 float32
numbers, computed in double and rounded once. Per pixel, in float32 on the device: the coordinate, the
nearest lattice point and the offset t, the weights and slopes of SIMPLE's quadratic B-spline, 27 reads, the
value and three derivatives, the phase from `cos` and `sin` of 2 pi (h s1 + k s2) / box, the model, the three
rotation Jacobians (the cross product of the derivative with the coordinate), and the products of finding 3.
Two differences from SIMPLE's arithmetic, both below the floor SIMPLE's own single-precision coordinates set:
the coordinate is a float32 product of float32 rows (SIMPLE rounds a double product once), and the phase is
float32 (about 1.0e-6 rad at shell 62 and a shift of 5 pixels, *derived*: 2 pi / 160 x 6e-8 x 62 x 5 x sqrt 2).
The coordinate's unit in the last place is 7.6e-6 near 124 and 9.5e-7 near 14 (*exact*). The B-spline and its
first derivative are continuous where the nearest point changes (at t = 1/2 the weights are 0, 1/2, 1/2 and
the next stencil's are 1/2, 1/2, 0 on the same voxels, *derived*), so no sample is excluded as a near tie;
control 6 of decision 16 checks it. The fallback named in advance, if the phase sets the measured floor:
SIMPLE's separable phase tables, computed on the host in double and uploaded (188 complex numbers an entry at
shell 62).

**8. Accumulation: partials in float32, added in double on the host** (the maintainer's choice a, first
half). The device reduces each sum of an entry to P partials in a fixed order; the host adds them in real64
and runs SIMPLE's finalisers in real64, as K8 answered its inner products (within 6.4e-9, *measured*, K8).
P is frozen in Phase 1 from a measured table: the error of the objective, the gradient and the matrix against
the oracle at the middle fixture for P in {1, 8, 32, 128}; the smallest P within 1.5 times the best is taken
(`CARTFT_PARTIALS`; *guessed* outcome 32). P = 1 is the float32 tree: if it is within 1.5 times the best, the
report says that double partials buy nothing measurable and the maintainer may rule for P = 1.
Why not float32 alone by default: SIMPLE's stops are relative reductions of 1e-6; a sequential float32 sum of
6,136 terms errs by about 5e-6 of the sum, a pairwise tree by about 2e-7, partials added in double by about
1e-8 (*derived*, statistical estimates: eps32 sqrt(n/3) / 2, eps32 sqrt(log2 n), and a block's error over
sqrt(P)). Compensated sums are used inside a block of the fused form (the wrapper's safe math mode honours
them: *measured*, binding contract policy). Cost: 23 x 32 x 4 B = 2,944 B an entry and round for the
Euclidean objective, 1,472,000 B for 500 entries; 27 sums and 1,728,000 B for the correlation (*derived*).

**9. What the toy returns and what the oracle judges** (choice d). `pose_normal_terms` returns what SIMPLE
returns: the normalised objective, the gradient, and the Gauss-Newton matrix times the clamped regression
slope (`curvature_scale`, clamped to 0.05 .. 20), from the raw sums by SIMPLE's two finalisers on the host.
The batched addition returns the same per entry and also the scale. The oracle judges the objective
(`objective`), the gradient and the scaled matrix (`derivatives`), the scale (`scale`), and through it the
plain Gauss-Newton matrix (the matrix over the scale). The clamp's three branches are reached by Euclidean
particles that are a multiple c of the model at the planted pose, where the slope equals c (*derived* from
the two slope sums): c = 0.02, 1, 2.5 and 40. For the correlation the slope's argument is 1 for every multiple
at the planted pose (*derived*); its fixtures use c = 2.5 at three poses, and the report says which branches
they reached. The clamp is one private function, as in SIMPLE.

**10. Two forms; the fused launch is one thread per block of pixels** (choice b).

- *Graph form* (the reference, the CPU path, always kept): per tile of entries, the coordinates, weights and
  27 positions as arrays, one `mlx_take` on the bank, the per-pixel products, and `sum` over blocks of the
  pixel dimension, giving `(sums, P, entries)`. About 4.6 MB live per entry at 6,144 pixels (*derived*: 27
  gathered complex values, four float32 weight arrays of 27, the int32 positions), so a tile of 64 entries is
  about 0.3 GB and a tile of 500 about 2.3 GB.
- *Fused form* (GPU only): `grid = [PK, entries, 1]`. One thread owns one block of `npix / PK` consecutive
  pixels of one entry, loops over them in order with a compensated sum per quantity, and writes its sums once.
  When PK is above P a device `sum` folds PK / P adjacent blocks before the copy. No two threads write one
  element, nothing is atomic, and the order is fixed: the form is repeatable by construction. PK in
  {32, 128, 512} and the threads per threadgroup in {32, 64, 256} are swept in Phase 4.
- *Not built: one threadgroup per entry reducing in `threadgroup` memory with `simd_sum`* (the mlx3D note,
  section 4). It returns float32 totals, which decision 8 does not take by default, and it rests on features
  with one scratch probe behind them. Phase 0's probe B records whether it builds, is correct and repeats,
  for Apple question 26 and the next plans. It gets a phase only if the fused form's measured copy and host
  sum of partials are 30 % or more of a round (the only time it could save).
- *Fallback named in advance.* If probe A shows that a thread looping over a block fails or is slower than
  one thread per pixel, the fused form is one thread per pixel writing its products `(sums, npix, entries)`
  and a device `sum` over blocks. It writes 23 x 6,144 x 4 B = 565,248 B an
  entry, 282.6 MB a round of 500 entries (*derived*), which is why it is the fallback and not the choice.

**11. The lockstep and the converged particles** (choice a, second half). SIMPLE's rules are kept one by
one: the scaled system, the observability test before the stationary test, the damping
(`LM_INITIAL_DAMPING` 1e-3, the diagonal's floor), an unreliable damped solve as a rejection, the step's caps
(0.1 rad, 1 pixel), the predicted reduction's tests, the acceptance ratio 0.25, the relaxation at 0.75, the
rejection multiplier from 4 with its cap, eight consecutive rejections, 40 iterations, the cumulative bounds,
the `active` mask, and the transaction's commit rule (the final objective finite and strictly below the
seed's, else the seed returned bit for bit with its status). The form differs: `lm_begin` takes the seed's
terms, `lm_advance` runs the host-only part of the iterations until a trial pose is proposed or the solve
ends, `lm_answer` takes the trial's terms. A round is: every active particle advanced (an OpenMP loop over
particles with `params%nthr` threads, no library call inside), one evaluation of all proposed trials, one
host wait at the copy of the partials, every answer fed. At most 41 rounds a batch (*exact*).
*Converged particles leave the launch.* A round evaluates the active entries only; the device takes their
slot indices as an input. In the fused form the grid's entry extent is the active count rounded up to a
multiple of 32 (*guessed*), the count is an int32 input and threads beyond it return at once, so a batch of
500 needs at most 16 kernel objects, each built once at 0.2 ms (*measured*, binding contract policy). The
work a fixed launch would waste, 1 - (evaluations / (particles x rounds)), is reported from the counters; a
fixed-shape variant is not built. Invalid slots (power at or below `NUMERIC_FLOOR`) get
`CARTFT_INVALID_PREPARATION` without an evaluation.

**12. The seam** (choice c).

| Question | Answer |
| --- | --- |
| Who owns the device state | `cartft_calc%ws`, a `class(device_work)` whose type is `cartft_workspace`; `cartft_pose_opt` owns none |
| Resident, and from when | the reference bank, from the first evaluation after `set_ref` to `kill`; the batch's slots and the pixel table, from the first evaluation after `set_ptcl` to `new_ptcls` or `kill`; the kernel objects, to `kill` |
| What crosses per round | in: 40 B an active entry; out: the partials (decision 8) |
| What stays on the host | the staging of references and slots, the addition of partials, the finalisers, the clamp, every decision of the solve, the 5 by 5 damped solve by `spd_solve_rel` in double, the poses and statuses |
| Where the host waits | once a round, at the copy of the partials (a wait costs 0.17 ms, *measured*, K8); once at each `set_ref` and upload |
| What a part process holds | 2 nstates cubes (0.54 GB at box 160 and one state), its batch's slots (37 MB at 500), the transform's working memory while a reference is prepared, a tile's intermediates in the graph form |
| What SIMPLE's loop becomes | the team's loop over particles in `simple_strategy3D_matcher.f90` becomes one serial call per batch whose rounds thread the host part; the preparation loop is unchanged |

The alternative for the reference, SIMPLE's packed half with the wrap and the conjugate in the kernel, saves
275 MB a state (*derived*) and is not built: memory per part is reported, never a reason (ruling of 2026-11-25).

**13. Fixtures** (choice e). All are built by `mlxf_cartft_fixture` through the oracle's public interface
(finding 8): a seeded cube of five Gaussian blobs, a seeded CTF array, a seeded noise spectrum, planted poses
from seeded Euler angles and shifts, and particles that are `model` at the planted pose times a multiple,
values computed in double and rounded once. Seeds 1, 2, 3.

| Fixture | Box (padded) | Shells | Pixels | Entries | Where |
| --- | --- | --- | --- | --- | --- |
| small, terms | 16 (32) | 1 .. 7 Euclidean, 0 .. 7 cc | 88, 89 (*exact*) | 4 particles (c = 1, 2.5, 0.02, 40) x 3 poses | fast gate, both devices |
| small, recovery | 16 (32) | same | same | 8 particles, noise-free, starts 0.05 to 0.15 rad and 0.5 to 2 pixels away | fast gate, both devices |
| small, noisy | 16 (32) | same | same | 4 particles, noise power 0.1 of the model's | fast gate, both devices |
| middle | 64 (128) | 2 .. 25 | 1,022 (*exact*) | 8 particles x 2 poses | named-only `cartft_calc_n64` |
| bench | 160 (320) | 2 .. 62 | 6,136 (*exact*) | batches of 1,500, 500, 250 | `test=bench_cartft` |

The starts stay inside `rotation_bound` = 10 degrees (SIMPLE's default `athres_cont`, 0.1745 rad) and
`trs` = 5 pixels (*guessed*; SIMPLE's default 0 makes the solve rotation-only, which one case of the recovery
fixture covers). The oracle's transform is by explicit sums: 3 x 128**4 = 8.1e8 complex products at the
middle fixture and 3 x 320**4 = 3.1e10 at the bench's size (*derived*); probe D decides whether the bench's
accuracy suite runs at box 160 or reports the middle fixture only.

**14. Error measures and tolerances.** With G the oracle's matrix over its scale and f0 the sum of the
model's and the particle's powers over the particle's power (the objective's scale before cancellation):

| Quantity | Measure | Ceiling on seed 1 (a larger number is a stop) |
| --- | --- | --- |
| `predict` | a pixel's error over the sum of the moduli of its 27 terms (K2's measure) | 1e-5 (*guessed*; K2's projection fixture measured 1.5e-6) |
| objective | Euclidean: the error over f0; cc: the error itself | 1e-5 (*guessed*) |
| gradient | the largest of an entry's errors over sqrt(2 G(a,a) f0) | 1e-5 (*guessed*) |
| matrix | the largest of an entry's errors over sqrt(H(a,a) H(b,b)) | 1e-5 (*guessed*) |
| scale | the relative error | 1e-5 (*guessed*) |
| shift terms | as the gradient and the matrix, on the 2 and 2 by 2 block | 1e-5 (*guessed*) |
| middle and bench sizes | the same measures | 1e-4 (*guessed*; K2 measured 1.45e-5 a sample at coordinates near 124) |

Each is measured on seed 1 on both devices, frozen in `mlxf_test_defs.f90` (`CARTFT_PRED_ERR`,
`CARTFT_OBJ_ERR`, `CARTFT_GRAD_ERR`, `CARTFT_MAT_ERR`, `CARTFT_SCALE_ERR`, `CARTFT_N64_ERR`,
`CARTFT_BENCH_ERR`) and in Progress, and judged on seeds 2 and 3 at twice the frozen number
(`POLAR_ROW_FACTOR`, the factor the projection's gates use). The fused form is judged with the same numbers.

**15. Recovery and its bound.** Errors are the oracle plan's: the rotation's
2 asin(|R - R_true|_F / (2 sqrt 2)) in radians, the shift's Euclidean norm in pixels.

- *The solve alone.* The resumable solve, fed the oracle's double-precision terms by the tester, against the
  oracle's `solve` on the noise-free fixture: the same number of accepted steps, and final poses within 1e-10
  rad and 1e-10 pixel (*guessed*; both are double; finding 7's differences do not act there).
- *Noise-free.* The lockstep recovers each planted pose within `CARTFT_REC_ROT` and `CARTFT_REC_SHIFT`,
  measured on seed 1 on both devices, frozen, judged at twice on seeds 2 and 3. Ceilings 1e-5 rad and 1e-5
  pixel (*guessed*: a hundred times the estimate 1e-7 of a float32 model's error over the fixture's lever
  arm; the oracle recovers to 1.5e-10 rad and 3.8e-11 pixel in double). Statuses and step counts are
  reported, not gated: near a zero residual float32 ends on rejections where the oracle ends on the gradient.
- *Noisy.* The toy's final pose against the oracle's `solve` from the same start: within
  `CARTFT_NOISY_ROT` and `CARTFT_NOISY_SHIFT`, measured and frozen the same way (ceilings 1e-3 rad and 1e-3
  pixel, *guessed*); every transaction ends committed.
- *Independence.* A particle's pose, status and passes do not depend on the other particles of its batch or
  on `nthr`: bit for bit in the fused form; in the graph form bit for bit if Phase 2 measures it so on
  seed 1, within the frozen recovery numbers otherwise.

**16. Controls.** Each gate has a planted violation, built in a patched copy, shown to fail, removed.

| # | Planted | Fails |
| --- | --- | --- |
| 1 | the sign of one slope weight in the device gather | the gradient and the matrix against the oracle |
| 2 | the central pixel counted twice | the correlation's objective (band from shell 0) |
| 3 | the clamp removed | the matrix and the scale of the c = 40 and c = 0.02 particles |
| 4 | the reference's envelope left out of `set_ref` | `predict` against the oracle's gather |
| 5 | the active list shifted by one after the first particle ends | independence and recovery |
| 6 | a pose planted with a coordinate within 1e-6 of a half-integer, then the stencil's base forced one down | the terms at that pose (first shown to pass unforced) |
| 7 | `LM_INITIAL_DAMPING` set to 0.1 | the solve alone against the oracle's steps |
| 8 | the shift gradient's sign | recovery |
| 9 | one bit of the second invocation's rotation rows | repeatability |
| 10 | an MLX name imported by a host file; a ledger line removed; a stub's message changed | rules `seam` and `mirror`; `check_toy_offstate.sh --exec` |
| 11 | one limit of `oracle_pose_selfcheck` halved below its measured error | sub-suite `oracle_pose` |

**17. Repeatability** (roadmap decision 8). On the GPU, for each form at its default configuration: the
partials of the small terms fixture and the poses, statuses and passes of the small recovery fixture are equal
bit for bit between two evaluations in one process and between two invocations of the executable (a digest
line each prints, compared by the run). A form that fails is not kept. A wrong or varying result that the
toy's code does not explain is treated as MLX issue #4603 until shown otherwise: reduced, recorded, stopped.

**18. The bench.** `mlxf_test_exec test=bench_cartft suite=<mode>`, keys `form`, `tile`, `blocks`, `tg`,
`batch`, `nbatch`, `objfun`, `nthr`, `nparts`, `part`, `go`, `seed`, `passes`; a key a suite does not read
stops it. Suites: `time` (the canonical driver), `sweep` (tile, blocks and threadgroup, one batch),
`accuracy` (the oracle at 8 particles and 2 poses, at box 160 if probe D allows), `stages` (seconds of
staging, upload, evaluation, copy, host solve, apart).
*The canonical driver:* one part's share of a pass of continuous refinement, from the first `set_ptcl` of the
first batch to the last pose on the host: per batch, the slots staged by a team, the upload, the lockstep to
every status. The references are set before the window; `set_ref`'s seconds are reported apart. The work is
30,000 particles a pass in every split (*guessed* size): 20 batches of `50 nthr` particles per part, so 1,500
at one process and 30 threads, 500 at three and 10, 250 at six and 5 (*derived* from SIMPLE's batch rule).
Phase 3 may scale `nbatch` so that the graph form's pass lasts between 2 s and 60 s; it is frozen then.
*Data:* 1,500 distinct particles made once before the window: the toy's `predict` at seeded planted poses,
times the CTF array, plus seeded noise at ten times the model's power per pixel (*guessed*); starts displaced
by up to 3 degrees and 2 pixels (*guessed*); `objfun` Euclidean for the verdict, cc timed and reported. If
fewer than 95 % of the transactions commit, the noise is lowered to the model's power and that is recorded
(95 % is the share SIMPLE's `cont_refine3D_1jxy` asks in the basin).
*Units:* evaluations per second (one entry over the band; the launcher's rate, `RUN_PARTS_UNIT=evals`), and
SIMPLE's own from `cartft_pose_work%write_bench`: transactions per second, passes per solve, ns per
pixel-evaluation. Five passes after one untimed pass; the median pass and the best are printed; digests are
computed after the last pass and their seconds printed (K2 found the go window dominated by digests).
Protocol: Release, nothing else built or run, one-minute load at most 4 with `uptime` recorded, MLX peak and
one process's footprint recorded, `mlx_synchronize()` before memory samples.

**19. One, three and six processes.** `scripts/run_parts.sh` with `RUN_PARTS_BENCH=bench_cartft`,
`RUN_PARTS_SUITE=time`, `RUN_PARTS_UNIT=evals`, `RUN_PARTS_LOAD=4`, for each kept form: 1 x 30, 3 x 10, 6 x 5
threads. Reported: the total rate, the rate per process, the seconds from go to the last exit, one process's
footprint and MLX peak, and roadmap decision 12's two conditions (a total rate at 3 or 6 below 0.8 of one
process's; a summed footprint above 51.5e9 B). Estimate of one process (*derived*): the bank 0.54 GB, a
reference's preparation bounded by K2's whole MLX peak at this padded box (1.94e9 B, *measured*, K2's report),
a graph tile of 64 entries 0.3 GB: under 4.5 GB, so 27 GB at six, below the launcher's guard of 82.46e9 B.
The bench refuses a tile whose derived live size is above `CARTFT_BUDGET_B` = 8e9 B (*guessed*).
Memory is reported, never a reason to reject a form.

**20. Keep or delete, and what stands for SIMPLE** (choice g). The fused form is compared with the graph
form, each at its canonical configuration (tile, blocks, threadgroup) frozen from the `sweep` suite before
the verdict runs, on the canonical driver. *Ceiling first* (start of Phase 4, before the kernel is written):
the graph form's pass over the same pass with the evaluation replaced by stored partials (a null form in a
scratch copy); below 1.30 the fused form gets no phase and the run goes to Phase 6. *Verdict:* kept if the
graph form's time is at least 1.30 times the fused form's in both invocations, at one process (the median of
five interleaved pairs' ratios of median passes) and at three (go to last exit), at equal work and with the
fused form inside the accuracy, recovery and repeatability gates; six processes are reported. Kept means
selectable by `set_eval_form` with the graph form the default; deleted means the fused module and its
ledger lines are removed.
*SIMPLE's cost:* no record in hand, and none is invented. The verdict does not use one. The report prints
the toy's rates in SIMPLE's units so that a `cont_refine3D_bench` record made later compares directly, and,
labelled as context and not as a comparator, the families note's 1.9 GFLOP/s a thread over 3.2 Mflop: about
1.7 ms a pass and thread (*derived* from two derived figures).

**21. The shell residual.** Carried, once per particle: after the lockstep ends, one more launch at the
committed poses returns the residual's power by shell (the block sums of a pixel table ordered by shell, or a
product with the shells' membership matrix), added in double; `get_shell_residual` returns it and
`pose_normal_terms` fills its optional dummy the same way. SIMPLE gets it in every pass; the solve never
reads it, so the result is the same and 61 sums a pass are saved. Judged against shell sums the tester forms
in double from the oracle's `model` (the oracle has none), within `CARTFT_OBJ_ERR` per shell over f0.

**22. The mlx3D note's proposed kernel decisions, as applied here.** Sizes that change per launch (the active
count) go in an int32 input; sizes fixed for a batch (the pixels, the block length, E, the strides) are
template integers (its proposed decision 4). Its proposed decision 5 waits for a measured rebuild cost: this
run reports the kernel objects built per batch and their seconds.

**23. A file the table does not name.** The run may add a row for a new `src/test/mlxf_toy_cartft_*.f90`,
`mlxf_cartft_*.f90` or a tester of them before its first edit, with its ledger lines. Any other unnamed file
is a stop.

**24. Counts and the fast gate's cost.** Existing sub-suites keep the counts Phase 0 finds. `unit_kernels`
gains `oracle_pose`, `cartft_calc`, `cartft_pose_opt`, and `seam` grows by the new class's cycles and
refusals; the run records each count. The new sub-suites add at most 3.0 s to `unit_kernels` in Release
(*guessed*: the oracle's self-check ran in 0.13 to 1.02 s standalone, *measured*, oracle report); an entry
above 0.5 s says why in the registry. Named-only: `cartft_calc_n64`. The process budget stays 13.

**25. Differences from SIMPLE, all recorded in the files' headers and the report.** No `ori`, so no `refine`;
no priors, stages or `refine_shift` (`shift_normal_terms` is carried and judged); the CTF as values; one band
and one objective per batch; the resumable solve; the lockstep and its serial batch call; float32 coordinates
and phases; the shell residual once; `sigma_contribution`, `score`, `write`, `read`, `set_refvol`,
`gather_ref`, the full-disk variants and `cartft_pose_work`'s type are not carried (its counters are the
batch record's). The toy clips a band at box/2 as SIMPLE does.

### Defaults taken without a question

- The expanded full cube and the stacked bank (decision 5); the pixel table in SIMPLE's loop order.
- The upload at the first evaluation after a `set_ptcl`, never inside a team's region.
- `shift_normal_terms` uses the pose evaluation's launch and keeps the shift's sums: no second kernel.
- The records in `mlxf_test_defs.f90`; `CARTFT_FORMS` beside `PROJ_FORMS`; default form `graph`.
- The oracle is not edited. Its fixture stays its own; K5's fixtures restate nothing of it but the constants
  of the solve, which are SIMPLE's.
- Probes are scratch programs outside the copy of the checkout; their numbers go to Progress.

### The choices that are the maintainer's

- **4**: `cartft_calc` refuses the host backend (recommended) or carries a host route in SIMPLE's arithmetic.
- **8**: partials added in double with P from a measured table (recommended), float32 trees, or compensated
  float32 totals on the device.
- **9**: the toy returns SIMPLE's scaled matrix and the scale beside it (recommended), or the plain matrix.
- **10**: the fused launch is one thread per block (recommended); the threadgroup reduction is probed, not built.
- **11**: converged particles leave the launch through an active list (recommended), or a fixed launch.
- **12**: what is resident and where the host waits, as the table says.
- **13, 15, 18**: the fixtures, the recovery bounds' ceilings, the bench's size, data and units.
- **20**: the fused form against the graph form; nothing stands for SIMPLE unless the maintainer supplies a
  `cont_refine3D_bench` record at box 160 before Phase 5.
- **1, 21**: both objectives; the shell residual once per particle.

## 4. Not in this plan

- Any change of `src/core`, `src/defs`, the generator or the parity ledger (315 public names, none pending).
- A measurement of SIMPLE, a change of SIMPLE, or SIMPLE's plan for this family (families note, section 9).
- A CTF model, an `ori` class, image preparation (`prepimg4align_cart`), the sigma update, symmetry, states
  above what `nstates` already allows, priors.
- B1 (the discrete search of the Cartesian objective) and the choice of seeds for the solve.
- `mlx_custom_function`: the gradient is analytic in the kernel (mlx3D note, section 4).
- A change of the polar toy, the projector, the reconstructor, or of any oracle.
- A threadgroup-reduction kernel, unless decision 10's condition is met and the maintainer rules.

## 5. Change types and gates

| Phase | Change | Gates at the phase's end |
| --- | --- | --- |
| 0 | none in the repository | the base builds in Debug and Release from scratch with zero warnings; the fast gate passes in both; counts and times recorded |
| 1 | new test-only modules, ledgers, defs, registry, `test.inf` | the gates of every phase (below); `oracle_pose` and `cartft_calc` on both devices; controls 1, 2, 3, 4, 6, 11; repeatability of the graph form; tolerances frozen |
| 2 | the solver, the driver, the off-state program, sub-suite `seam` | every phase's gates; `cartft_pose_opt` on both devices; controls 5, 7, 8, 9, 10; `scripts/check_toy_offstate.sh --exec` |
| 3 | the bench with the graph form | every phase's gates; the bench's keys refuse what they do not read; the splits recorded |
| 4 | the fused form | every phase's gates; decisions 14, 15 and 17 on the fused form; controls 1, 5 and 9 repeated on it |
| 5 | the verdict; removal if "delete" | every phase's gates; the ledgers equal the code |
| 6 | documents | every phase's gates; `scripts/check_embed.sh`, `scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`, `scripts/release_gate.sh --allow-dirty`; the Release fast gate 10 of 10 |

The gates of every phase: Debug and Release from scratch in hand-configured trees
(`-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`), zero warnings; the fast gate in both; `scripts/check_tree.sh`;
`scripts/restyle_fortran.py` and `scripts/format_use_blocks.py` on every touched Fortran file; the existing
unit areas keep their counts (core 215 or 216, array 193, ops 2,462, fft 194, linalg 632, compile 63, fast 152,
random 486, transforms 274, io 846, distributed 55; kernels as Phase 0 finds it plus this plan's sub-suites).

## 6. Acceptance

1. `oracle_pose`: the 32 checks of `oracle_pose_selfcheck` within their limits, asserted (*exact* count).
2. `predict`, the objective, the gradient, the matrix, the scale and the shift terms of both objectives
   within twice the numbers frozen on seed 1, on seeds 2 and 3, on both devices, in each kept form
   (decision 14); every frozen number below its ceiling.
3. The clamp: the scale of the c = 0.02 particle is 0.05 and of the c = 40 particle 20 within
   `CARTFT_SCALE_ERR`; the branches the correlation's fixtures reached are named.
4. The solve alone equals the oracle's steps (decision 15, first item).
5. Recovery, noisy agreement and independence (decision 15), on both devices, in each kept form.
6. Repeatability bit for bit, two evaluations and two invocations, each kept form (decision 17).
7. The accumulation table (decision 8) measured, P frozen, the table in the report.
8. The seam: host files import no MLX name; the off-state build compiles the new host and glue files and its
   program's new checks pass; `SEAM_PENDING` stays 0; both ledgers equal the code.
9. Every control of decision 16 shown to fail and removed, each with its output line in Progress.
10. Timings: the canonical driver at 1, 3 and 6 processes for each kept form, with the rates in decision 18's
    units, footprints, MLX peaks, `uptime`, and decision 12's two conditions evaluated.
11. The verdict by decision 20's rule, from configurations frozen before the verdict runs.
12. The fast gate within its bound (38.74 s) and the new cost within decision 24's 3.0 s, or the reason.

Reported, not gated: the middle and bench accuracy; statuses and step counts; passes per solve; the share of
work the active list saves; the kernel objects built per batch; probe B's result; cc's timings; `set_ref`'s
seconds; the stage seconds; the first evaluation of a new kernel source (60 ms was *measured* for another).

Reserved for the maintainer: the rulings of section 3; whether a kept fused form becomes the default; whether
SIMPLE's plan for B2 is opened (families note, section 9); what is committed.

## 7. Common rules and stop conditions

The run works on the M5 Ultra only (30 cores, 103.1 GB, the only GPU), in the session, in a copy of the
checkout, one run at a time; nothing else is built or run while a step is timed. Git is read-only: nothing
is committed or pushed. SIMPLE is read through `git -C ~/src/SIMPLE show d354efee2:<path>` only and is not
measured. No production data. A finding about MLX or mlx-c becomes a numbered entry of
`doc/collaboration/apple_questions.md` (the last is 31), written, never sent.

Stops (the run records the state, leaves the tree at the last passing phase, and reports):

- a wrapper the toy needs is missing from `mlxf`, or a `src/core` change would be needed;
- a seed-1 measurement above its ceiling (decisions 14 and 15), or a judged seed above twice the frozen number;
- the oracle and the toy disagree and the oracle is the suspect: the oracle is not edited here;
- a result that varies between runs or is wrong without a cause in the toy (MLX issue #4603 as the suspect);
- probe A fails and the named fallback fails too;
- the fused source does not compile after two corrections informed by `mlx_last_error()`;
- a file outside the file table and outside decision 23 would have to change;
- a phase passes 1.5 times its box without its exit;
- the machine cannot be made quiet for a timed step within the launcher's wait.

Gates no ruling may waive: the oracle as judge and the toy importing no oracle; tolerances frozen before the
run they judge; a planted violation for every gate; repeatability; zero warnings in Debug and Release; the
static gate; both ledgers; no MLX name in a host file; the graph form kept whatever the verdict; the 30 % rule
on the canonical driver's elapsed time with submission, waits and collection included.

## 8. Phases

### Phase 0: the base, the premises and the probes (box: 100 min)

1. Pin the base's hash. Build Debug and Release from scratch; run the fast gate in both; record the counts of
   every unit area, of `unit_kernels`' sub-suites, the fast gate's time and entries.
2. Re-check the queue's premises (section 2) and the items listed as not verified there.
3. Probe A: a kernel with `grid = [PK, 500, 1]` whose thread loops over 6,144 / PK pixels, reads 27 voxels of
   a 323**3 complex64 cube at seeded coordinates and keeps 23 compensated sums: it builds, its sums equal a
   host double sum within 1e-6 of the terms' moduli, two runs give equal bits; seconds at PK = 32, 128, 512.
4. Probe B: a `threadgroup` array, `threadgroup_barrier` and `simd_sum` reducing one entry's pixels: builds
   or not, correct or not, equal bits in two runs or not. Recorded only.
5. Probe C: `mlx_take` of 27 x 6,144 x T positions from a bank of two 323**3 cubes: seconds and MLX peak at
   T = 16, 64, 250, 500.
6. Probe D: `oracle_dft_3d` on a 320**3 cube: seconds and resident size.
7. Probe E: `mlx_rfftn` of a 320**3 real cube and the expansion to 323**3: seconds and MLX peak.

**Exit:** the base passes as found; every premise is confirmed or its new value recorded; probes A, C, D, E
have numbers, B has its three answers; the fused design (block or the fallback) and the bench accuracy's
size are fixed in Progress.

### Phase 1: the calculator in the graph form on the small and middle fixtures (box: 240 min)

1. `mlxf_cartft_fixture`, `mlxf_oracle_pose_tester` with its registry row (acceptance 1, control 11).
2. `mlxf_toy_cartft_calc`, its glue and workspace: `new`, `kill`, `set_ref`, `ref_exists`, `new_ptcls`,
   `set_sigma2`, `set_ptcl`, the getters, `predict`; the ledgers' lines; `test.inf`.
3. `predict` against the oracle's reference and gather on the full disk, the rim included (control 4).
4. The batched evaluation in the graph form, `pose_normal_terms`, `shift_normal_terms`, the finalisers.
5. The accumulation table (decision 8) at the middle fixture; P frozen.
6. Tolerances measured on seed 1 on both devices, frozen; seeds 2 and 3 judged; controls 1, 2, 3, 6.
7. Repeatability of the graph form (control 9's plant is shown in Phase 2 with the poses).

**Exit:** acceptance 1, 2, 3 and 7 hold for the graph form; `cartft_calc_n64` runs by name; the gates of
every phase pass; the frozen numbers are in Progress.

### Phase 2: the resumable solve, the lockstep and recovery (box: 210 min)

1. `mlxf_toy_lm_solver`: the rules of decision 11; the solve alone against the oracle (control 7).
2. `mlxf_toy_cartft_pose_opt`: the pose problem, `refine_pose`, `refine_pose_batch`, the active list, the
   commit rule, the statuses, the counters, the shell residual (decision 21).
3. Recovery, noisy agreement and independence on seed 1, frozen; seeds 2 and 3; controls 5, 8, 9.
4. The off-state program's checks; sub-suite `seam`'s cycles and refusals; control 10.

**Exit:** acceptance 4, 5, 6 and 8 hold for the graph form; `scripts/check_toy_offstate.sh --exec` passes;
the gates of every phase pass.

### Phase 3: the bench and the graph form's timings (box: 180 min)

1. `mlxf_bench_cartft` with its suites and keys, its table in the launcher's column layout, the `go` file.
2. The `sweep` suite for the graph form's tile; the canonical tile frozen. `nbatch` frozen.
3. The `stages` suite; the `accuracy` suite at the size probe D fixed; `CARTFT_BENCH_ERR` frozen.
4. The canonical driver at 1, 3 and 6 processes, two invocations each.

**Exit:** the graph form's rates, footprints and peaks at the three splits are in Progress with `uptime`;
the bench refuses keys it does not read; the gates of every phase pass.

### Phase 4: the fused form (box: 210 min)

1. The ceiling of decision 20 in a scratch copy. Below 1.30: record it and go to Phase 6.
2. `mlxf_toy_cartft_workspace_fused` in the design Phase 0 fixed; `set_eval_form`, `set_eval_tile`; refusal on
   the CPU device with a message.
3. Decisions 14, 15 and 17 on the fused form with the numbers frozen in Phases 1 and 2; controls 1, 5, 9.
4. The `sweep` suite over blocks, threadgroup and the entry quantum; the canonical configuration frozen.

**Exit:** the fused form passes acceptance 2, 5 and 6, or it is removed here with the reason; its canonical
configuration is in Progress before any verdict run; the gates of every phase pass.

### Phase 5: the verdict (box: 150 min)

1. Interleaved pairs graph, fused at one process, five pairs, two invocations; the same at three processes
   through the launcher (go to last exit); six processes reported.
2. The rule of decision 20 applied; decision 10's condition for the threadgroup reduction evaluated.
3. Kept: the default stays `graph`. Deleted: the fused module, its tests and its ledger lines removed, the
   build and gates repeated.

**Exit:** the verdict with every ratio it rests on is in Progress; the tree holds exactly what the verdict says; the
gates of every phase pass.

### Phase 6: the record (box: 75 min)

1. `completed/mlxf_kernel_k5_report.md`: the numbers of section 6, the findings of section 2 as they ended,
   what a SIMPLE plan for B2 would have to do (the resumable solve, the serial batch call, the upload point).
2. The families note (B2's row, the open decisions closed, the flop count), the roadmap, the toy and test
   policies, the binding contract policy's "Measured by the toys" if a wrapper fact was measured, Apple
   question 26's record of probe B (or a new entry 32), the history, the notes' README.
3. The last gates of section 5. The report ends with a commit message, without an attribution or co-author
   line, that names every new file.

**Exit:** every gate of section 5 passes; this plan moves to `completed/` with its Progress filled.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/test/mlxf_cartft_fixture.f90` | new: seeded fixtures through the oracle's public interface | 1, 2, 3 |
| `src/test/mlxf_oracle_pose_tester.f90` | new: asserts the pose oracle's self-check | 1 |
| `src/test/mlxf_toy_cartft_calc.f90` | new: host | 1, 2, 4 |
| `src/test/mlxf_toy_cartft_calc_mlx.f90` | new: glue | 1, 2, 4 |
| `src/test/mlxf_toy_cartft_workspace.f90` | new: device, the graph form | 1, 2, 4 |
| `src/test/mlxf_toy_cartft_workspace_fused.f90` | new: device, the fused form (removed on "delete") | 4, 5 |
| `src/test/mlxf_toy_cartft_calc_tester.f90` | new: sub-suites `cartft_calc`, `cartft_calc_n64` | 1, 4 |
| `src/test/mlxf_toy_lm_solver.f90` | new: host | 2 |
| `src/test/mlxf_toy_cartft_pose_opt.f90` | new: host | 2 |
| `src/test/mlxf_toy_cartft_pose_opt_tester.f90` | new: sub-suite `cartft_pose_opt` | 2, 4 |
| `src/test/mlxf_bench_cartft.f90` | new: `bench_cartft` | 3, 4, 5 |
| `src/test/mlxf_test_defs.f90` | the records, `CARTFT_FORMS`, the frozen numbers and defaults | 1, 2, 3, 4, 5 |
| `src/test/mlxf_test_registry.f90` | rows of the sub-suites, `NAMED_ONLY`, `BENCHES`, `run_bench` | 1, 2, 3 |
| `src/test/mlxf_toy_seam_tester.f90` | the new class's cycles and refusals | 2, 4 |
| `src/test/test.inf` | the directory's description | 1, 2, 3, 4 |
| `scripts/toy_mirror.txt` | the new modules' lines; the header's list of SIMPLE files read | 1, 2, 4, 5 |
| `scripts/toy_seam.txt` | the new stems with their classes | 1, 2, 4, 5 |
| `test/offstate/mlxf_offstate_exec.f90` | the calculator's refusals; the solve on a quadratic | 2 |
| `test/offstate/offstate.inf` | its description, if the program's line there names its checks | 2 |
| `doc/implementation_notes/planned/mlxf_kernel_k5.md` | Progress; moved to `completed/` at the end | 0, 1, 2, 3, 4, 5, 6 |
| `doc/implementation_notes/completed/mlxf_kernel_k5_report.md` | new: the report | 6 |
| `doc/implementation_notes/planned/mlxf_kernel_families.md` | B2 as delivered | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | K5's state | 6 |
| `doc/implementation_notes/README.md` | the index | 6 |
| `doc/policies/toy_example_policy.md` | the new classes and their backend answers | 6 |
| `doc/policies/test_environment_policy.md` | the new sub-suites, the named-only one, the bench | 6 |
| `doc/policies/binding_contract_policy.md` | "Measured by the toys", only if a wrapper fact was measured | 6 |
| `doc/collaboration/apple_questions.md` | probe B's record | 6 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the batch as delivered | 6 |

Not in the table and not to be touched: every file under `src/core`, `src/defs`, `build/gen`; the oracles;
the polar toy, the projector and the reconstructor; `scripts/check_rules.py` (no new rule is planned: the
existing rules `seam`, `mirror` and `arity` read the new lines; a rule that turns out to be needed is a stop
with its proposal); `scripts/run_parts.sh` (its settings suffice).

## Progress

(one entry per phase, written by the run)
