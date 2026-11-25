# Host oracles for SIMPLE's reconstruction as SIMPLE computes it: report of run `mlxf_oracles3` (the Mac)

Status, 2026-11-24: Phases 0 to 4 done, unattended, on the Mac (Apple M5 Ultra, GNU Fortran 16.2.0) by Claude
in the maintainer's session, in a scratch copy of the checkout: a dell2 launch needs the maintainer's commit of
the plan, which could not be made. Base `3b3f4fd` plus the maintainer's uncommitted tree. The plan, with the
contract and one Progress entry per phase, is [`../planned/mlxf_oracles3.md`](../planned/mlxf_oracles3.md); it
stays in `planned/` until read. Rulings: none. No history entry (decision 10). Nothing was compared with
SIMPLE, and the repository's own builds were not run (another job was being timed on the machine): the
modules were built one file at a time by decision 6's recipe only.

## What was learned

1. **Section 9 turns into code without changing a formula, with twenty points left open or implicit** (T1 to
   T20 in Phase 0's Progress). Two of them decide numbers a kernel will be judged on, and both need the
   maintainer's eye on SIMPLE:
   - **T3, the edge row of 9.1's conjugate rule.** `S(0, -k, -m)` at `k` or `m = -N/2` has three readings.
     The oracle takes the mate index modulo `N`. The independent reviewer read this as a stop of section 7;
     the run continued on the instruction to take the choices section 9 leaves. It touches 7 voxels at N = 4
     and 15 at N = 8, and the halo reading would move them by up to 4.7 % and 0.59 % of the largest stored
     value (*measured*).
   - **T1, the origin of the transforms.** Section 9 never says where `F` and `F⁻¹` put the real-space origin.
     Only the centre voxel makes the crop, the envelope, the mask and the map's correction agree.
2. **9.7's three inferences.**
   - *The first oracles' scatter is the lattice accumulator up to the factor 8 on every voxel read:*
     **confirmed**, to 7e-17 on the three fixture planes and on a fourth plane built to touch the skip's
     boundary, in both boxes; and on every voxel once the skipped windows are taken out of the scatter.
   - *The packed density is one half of a Hermitian array:* **confirmed** on the fixture, whose planes `h = 0`
     and `M/2` are Hermitian to 8e-17. It rests on Friedel-complete planes with an even CTF.
   - *The window's radius is measured from voxel `N/2 + 1`:* **neither confirmed nor refuted here.** It is a
     statement about SIMPLE's source. The oracle implements it, and a plant of the other centre (voxel `N/2`)
     fails eleven checks.
3. **Under SIMPLE's three rules the fixture's solve stops on the step test, not on the residual** (*measured*,
   reported and not gated): at N = 4 after 11 iterations with a residual of 2.1e-3, 8.7 % from the direct
   solution; at N = 8 after 27 iterations with 2.2e-3. With the step test off, `rtol` 1e-4 takes 28 iterations
   for 27 unknowns and 734 for 251 (733 at `-O2`). Decision 5's two solves therefore run with `xtol = 0`.
4. **On three planes 9.4's preconditioner makes the system harder, not easier** (*measured*,
   `keep/logs/phase3_diag_recon8.log`): the condition number goes from 55.5 to 1,106 at N = 4 and from 228 to
   3.6e11 at N = 8, where the preconditioner has 13 eigenvalues below 1e-6 of its largest on the support. This
   is a property of a fixture with three planes, but K8's toy will meet it: iteration counts on a few planes
   are not small.
5. **Two independent implementations of section 9 agree on the N = 4 system.** The Phase 0 reviewer built it in
   Python of its own before any Fortran existed: ridge 0.192, condition number 55.5, the `xtol` stop at
   iteration 11 at 8.7e-2, `rtol` at iteration 28 at 2.2e-3, the direct solution 58 % from the phantom. The
   oracle gives 0.19187, 55.47, 11 and 8.73e-2, 28 and 2.21e-3, 58.5 % (*measured*; the reviewer's numbers
   are a lead, not a log of this run).
6. **The "known target" of decision 4 is weak.** Three planes do not determine the volume: the direct solution
   lies 58 % from the phantom inside the mask at N = 4, where 19 % of the phantom's energy is outside the mask,
   and the gridding map is further off still. The scales are held by closed forms of single samples instead.
7. **Three things derived on the way.**
   - The real part of an inverse transform sees only the Hermitian part of the planes `h = 0` and `n/2`, so
     taking them as stored (T2) and reading them through their mates (9.2) cannot differ in the map, the
     right-hand side or the kernel.
   - At N <= 12 + 2 mskrad the binary mask is `r < N/2` whatever the mask radius; the radius only shapes the
     soft window.
   - 9.4's `max(D, 0)` cannot act: a negative density is below a tenth of a positive mean and gets `pi = 0`
     either way. A plant that removes it passes every check, as it must.
8. **The stored plane `h = 0` of the gridding backend is not a Hermitian half:** the pixels at `k = -N/2` have
   no mate in the inserted range, and the asymmetry reaches 4.5 % and 0.57 % of the largest stored value.
9. **The reviews found checks that could not fail, again.** A mate rule typed three times alike; a disc bound
   that decided no fixture pixel; a guard probed with its own constant; a skip boundary no fixture pixel
   reached, shown by a plant that passed all 21 checks; a recomputed residual that nothing followed past
   iteration 25. Each now has a check and a plant. Three sub-checks that were identities were removed.
10. **A residual compared relative to itself failed at `-O2` and passed at `-O0`:** two evaluations of the same
    small residual differed by 9.3e-10 of it at `-O2` and 3.4e-14 at `-O0`. It is a fused multiply-add: with
    `-ffp-contract=off` the `-O2` build gives the `-O0` digits (*measured*, `keep/logs/phase4_diag_fma.log`).
    Such comparisons are absolute now, in fractions of `|b|`.

## What changed, phase by phase

| Phase | Files (all in the file table) | Time (box) |
| --- | --- | --- |
| 0, baseline and contract | the plan: D0 to D3, T1 to T20, the counts | 34 of 30 min |
| 1, the projection's repairs | `src/test/mlxf_oracle_projection.f90` (911 to 1,111 lines); the plan | 42 of 60 min |
| 2, the gridding insertion | `src/test/mlxf_oracle_gridding.f90` (new, 1,151 lines); the plan | 35 of 150 min |
| 3, the PCG reconstruction | `src/test/mlxf_oracle_recon_pcg.f90` (new, 1,658 lines); the plan | 33 of 240 min |
| 4, report | this report; the plan; comment-only edits of the two new modules | 15 of 30 min |

Phases 1 and 2 overlap: Phase 2's module was written while Phase 1's review ran. The times are wall-clock
times of one session and include three reviews of ten to twelve minutes each. `mlxf_oracle_dft.f90` was not
edited. Nothing under `src/core/`, `scripts/` or `cmake/` changed, and none of the shared test files did.

**Exported names.**
- `mlxf_oracle_projection`, added: `oracle_proj_edge_index` (elemental), `oracle_proj_edge_gather`.
- `mlxf_oracle_gridding`:
  - the classes `oracle_grid_plane` (bindings `new`, `kill`, `set_data`, `set_pose`, `box`, `rotation`,
    `weight`, `shift`, `observed`, `ctf`, `variance`, `samples`) and `oracle_grid_lattice` (`new`, `kill`,
    `insert`, `numerator`, `density`, `compress`);
  - `oracle_grid_volume`, `oracle_grid_transform`, `oracle_grid_correct`, `oracle_grid_map`;
  - the shared helpers `oracle_grid_envelope`, `oracle_grid_reciprocal`, `oracle_grid_half_inverse`;
  - `oracle_grid_selfcheck`.
- `mlxf_oracle_recon_pcg`:
  - the classes `oracle_recon_lattice` (`new`, `kill`, `insert`, `numerator`, `density`,
    `packed_numerator`, `packed_density`) and `oracle_recon_problem` (`new`, `kill`, `apply`, `precond`,
    `rhs`, `support`, `window`, `kernel`, `spectrum`, `ridge`, `start`, `ship`, and from its abstract parent
    `set_rules` and `solve`);
  - `oracle_recon_selfcheck`.

Each self-check returns `(labels, errors, limits)` and asserts nothing.

## Decisions taken under delegation

All are in the plan's Progress; the phase is named.

- **Phase 0, T1 to T20:** the transforms' origin; the transform of a stored half; the edge of the conjugate
  rule; the two skips of 9.1; the phase of 9.1's samples; the plane data and their scale; the volume (the
  phantom is a 6-cube: its central 4-cube, and the 6-cube inside zeros at N = 8); the planes' CTFs, variances,
  weights and shifts; the mask radii 1.25 and 2.5 and `maxrad` halved as a real; `lambda_rel = 0.05`; the
  stored voxels; an empty shell; the preconditioner's symmetry on the support; the solve's returns; the warm
  start; the step test's epsilon; `c1` outside 9.6's range; the larger box; the guards; real-linear matrices.
- **Phase 0, after the review:** decision 5's solves run with the step test off; T3 kept as a choice.
- **Phase 1:** two window checks in place of one; the edge index elemental; a driver of its own.
- **Phase 2:** the shared helpers live in `mlxf_oracle_gridding`; the fixture's planes are a class; the disc is
  checked at N = 16; the explicit matrix takes each pixel's value at the pixel itself.
- **Phase 3:** the solve is written once on an abstract parent of the problem class, private to the module;
  the binding is `support`, not the `mask` of the contract; the N = 8 solve check holds the reported residual
  to the true one under the rules a system is born with, after the first form (rtol within 200 iterations)
  failed and was diagnosed; a fourth, turned plane; residuals compared in absolute terms.

## Deviations from the plan

- **Where it ran:** the Mac, not dell2, and GNU Fortran 16.2.0, not 15.2.0.
- **A stop the reviewer saw and the run did not take:** T3 (above).
- **Section 4's "warm starts with `cold_restart`":** the replacement of a bad warm start is left out; the
  non-zero start of 9.5 and the start and exit rules of 9.3 are in, each with a check.
- **Decision 2 names one check for beta;** there are two.
- **Notes edited from the shell:** one paragraph of Progress and several source edits were made by a Python
  script instead of the editor tools; and one formatter call ran with an empty file list, over the tree. It
  rewrote 0 of 62 files, and the comparison with the base shows file-table paths only.
- **No file outside the table changed.** No threshold of decision 5 was changed. No check of section 8's lists
  was dropped; one check of this run's own design was reformulated (the N = 8 solve, above).
- **Expected effects that did not occur:** the solve at SIMPLE's rules does not stop on `rtol`; the
  reconstruction does not come near the phantom.

## Evidence against the baseline

- **The static gate** passes on the untouched copy and at the end of every phase
  (`keep/logs/phase{0_check_tree_base,2_check_tree,3_check_tree,4_check_tree}.log`), with its warning that the
  oracle files are untracked.
- **The first oracles' own checks** pass at the end of every phase at both levels: transforms 12 of 12, PCG 14
  of 14, and the projection's first 26 with the digits of Phase 0.
- **Builds:** every module and driver alone, `gfortran -std=f2018 -Wall -Wextra -Werror` at
  `-O0 -g -fcheck=all` and at `-O2`: no compiler output (`keep/logs/phase4_final_build_{O0,O2}.log`).
- **Errors at both levels** (*measured*, `keep/logs/phase4_final_run_*`):

  | Module | Checks | Largest at -O0 | Largest at -O2 | Limits | Plants; failing a check; checks covered |
  | --- | --- | --- | --- | --- | --- |
  | `mlxf_oracle_dft` (untouched) | 12 | 7.984e-15 | 7.984e-15 | 1e-12 | not rerun |
  | `mlxf_oracle_pcg` (untouched) | 14 | 1.053e-15 | 1.038e-15 | 0 / 1e-12 | not rerun |
  | `mlxf_oracle_projection` | 32 | 2.140e-8 | 2.140e-8 | 0 / 1e-13 / 1e-12 / 5e-7 | 33; 32; 32 of 32 |
  | `mlxf_oracle_gridding` | 13 | 8.374e-16 | 8.793e-16 | 0 / 1e-12 | 42; 40; 13 of 13 |
  | `mlxf_oracle_recon_pcg` | 21 | 2.212e-3 | 2.212e-3 | 0 / 1e-12 / 1e-9 / 5.547e-2 | 60; 59; 21 of 21 |

  The projection's largest is `window weights` against the reader's seven digits; without it 1.3e-15. The
  reconstruction's largest is the `rtol` solve against the direct solution, limit `10 rtol cond` = 5.547e-2;
  without the two solves 4.0e-14 (the kernel against cosine sums). The solve iterated to 1e-12 lies 1.2e-12
  (`-O0`) and 3.5e-12 (`-O2`) from the direct solution, limit 1e-9.
- **Plants that fail no check:** three abort on a bounds error before the self-check returns (the edge index
  returning `h` itself; the padding factor in the gridding coordinate; no skip of the gridding pixels below
  `h = 0`), each with a milder variant that fails checks. One passes every check, as it must: the removal of
  9.4's `max(D, 0)` (finding 7). The controls were rerun on the final tree
  (`keep/logs/phase4_final_controls_{projection,gridding,recon}.log`).
- **Decision 8's cases,** all on constructed systems with counts known in advance (`stops`, exact): `rtol`
  (three eigenvalues, three iterations), `rtol` before `xtol`, `xtol` (the step 0.408 against 0.45 and 0.4),
  the step test's epsilon, `maxits`, fixed iterations, an indefinite product at once and at iteration 2 with
  `x` as the first step left it, a right-hand side that is not finite, a zero right-hand side, a first
  product that is zero, negative, or zero because the start is exact, and a non-zero start that is used. The
  recomputation: 24, 26, 31 and 52 applications for 24, 25, 30 and 50 iterations, and a changed operator
  whose residual is reported at iteration 25 and still followed at iteration 30.
- **Reported, not gated** (`keep/logs/phase4_final_run_recon_{O0,O2}.log`, digits of `-O0`):

  | | N = 4 | N = 8 |
  | --- | --- | --- |
  | ridge | 0.19187 | 0.076881 |
  | condition number of the support block | 55.47 | 227.6 |
  | SIMPLE's three rules: reason, iterations, residual | xtol, 11, 2.145e-3 | xtol, 27, 2.213e-3 |
  | `rtol` 1e-4, step test off: iterations | 28 | 734 (733 at `-O2`) |
  | `rtol` 1e-12, step test off: iterations | 43 (42 at `-O2`) | not reached in 1,000 (7.6e-5) |
  | direct solution from the phantom, in the mask | 58.5 % | not computed |
  | first oracles' operator against this one, relative | 1.53 | |
  | two index maps of 9.6 on boundary queries 3 and 4 | 3.67e-3, 4.12e-3 (M = 12) | |
- **Cost** (*measured* once each, not a benchmark): the reconstruction's self-check runs in 0.29 s at `-O0`
  and 0.08 s at `-O2`; the driver with its long reported solves in 5 s and 0.9 s.

## Left open for the maintainer

- **Rulings on SIMPLE's source,** in the order of what they move:
  1. T3: what `compress` stores on the plane `h = 0` at `k` or `m = -N/2`.
  2. T1: the real-space origin of the transforms in the map and in the right-hand side.
  3. T9: whether `maxrad` halves `min(nint(2 (mskrad + 6)), N)` in integers. No fixture reaches it, but a
     production box does whenever the rounded number is odd.
  4. T12 and T14: `pi` on a shell without a positive density; the iteration count an indefinite stop returns.
  5. The window's centre (9.7's third inference).
- **Mac integration (decision 9):** apply the diff and add the two new modules; build Debug and Release with
  `MLXF_WERROR=ON`, where the modules are globbed into `mlxf_test_exec`. That build was not run here, nor
  `-O3`, nor GNU Fortran 15.2 on dell2; only the standalone recipe under 16.2 at its two levels is clean.
- **The comparison with SIMPLE's own numbers** (decision 9): not done, the maintainer's call. The N = 4 fixture
  is small enough to dump from a SIMPLE test program.
- **Testers and registry rows** for K6 and K8, owned by their plans; the limits may move to `mlxf_test_defs`.
- **`doc/implementation_notes/README.md`** still lists this run as planned; it is outside the file table.
- **Reported, not gated:** the table above; the gridding map against the phantom; the voxels T3 decides.
- **Not here:** the history entry (decision 10); symmetry operators, priors, the shellwise floor of the
  density and `cold_restart` (section 4).

## Suggested commit message

```text
test: host oracles for SIMPLE's gridding insertion and PCG reconstruction

Add plain-Fortran double-precision oracles in src/test that build without the library:
mlxf_oracle_gridding (the gridding backend's insertion on the native grid, its compression,
density correction and map, and the fixture the reconstruction oracles share) and
mlxf_oracle_recon_pcg (the PCG backend's lattice insertion and packing, kernel spectrum,
ridge, masked operator, preconditioner, right-hand side and solve with SIMPLE's stopping
rules). mlxf_oracle_projection gains checks that pin the window's beta and the packed half
against the phantom's own transform, and SIMPLE's first-dimension index map. Every operator
is held to an explicit matrix or a closed form, every stop of the solve to a constructed
case, and planted errors show each check can fail. Written and checked on the Mac under
GNU Fortran 16.2 (run mlxf_oracles3); not yet compared with SIMPLE.
```

## Appendix: the build recipe and the drivers (decision 6)

They live in the run's scratch area, `scratch/keep/drivers/`, and are not in the repository: the build script
`build_level_mac.sh`, the drivers `mlxf_oracle_{projection3,gridding,recon_pcg}_main.f90` (the self-check loop
of the first run's drivers, then the reported quantities) and `mlxf_oracle_recon_pcg_check_main.f90` (the
self-check alone), the negative-control harness `run_controls_mac.py` and the plants
`plants_{projection3,gridding,recon}.py`. The independent enumerations are `scratch/keep/py/counts{,2,3}.py`.

`build_level_mac.sh` is the first run's recipe with this copy's paths, a wait while a timed job runs, and any
compiler output counted as a failure:

```bash
level="$1"; exe="$2"; shift 2          # build_level_mac.sh O0|O2 <exe> <modules in dependency order> <driver>
case "$level" in
    O0) flags="-O0 -g -fcheck=all" ;;
    O2) flags="-O2" ;;
esac
objs=()
for src in "$@"; do
    obj="$out/$(basename "${src%.f90}").o"
    msg=$(gfortran -std=f2018 -Wall -Wextra -Werror $flags -J "$out" -c "$src" -o "$obj" 2>&1)
    if [ $? -ne 0 ] || [ -n "$msg" ]; then echo "$msg"; exit 1; fi
    objs+=("$obj")
done
gfortran $flags "${objs[@]}" -o "$out/$exe"
```

The dependency order is `mlxf_oracle_dft`, `mlxf_oracle_projection`, `mlxf_oracle_pcg`,
`mlxf_oracle_gridding`, `mlxf_oracle_recon_pcg`.
