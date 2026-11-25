# Host oracles for the projection, insertion and PCG toys: report of run `mlxf_oracles` (dell2)

Status, 2026-11-24: Phases 0 to 4 done on dell2, unattended. The three oracle modules are "delivered on
dell2", not integrated: decision 8's Debug and Release builds under GNU Fortran 16.2 on the Mac are still to
come. The plan, with the contract and one Progress entry per phase, is
[`../planned/mlxf_oracles.md`](../planned/mlxf_oracles.md); it stays in `planned/` until the maintainer has read
it. Base `dc3f5d7`. Rulings: none. No history entry (decision 10).

## What was learned

1. **The examples note holds together for these oracles.** Sections 4B and 5 contradict themselves on no point
   an oracle needs. The *derived* cross-checks agree:
   - 8/M³ = 1/N³ for the unit point;
   - d(q) is the seven-point stencil;
   - P⁻¹ = H⁻¹ when M = N and S = I;
   - the spectrum lies in [0.25, 13.25].

   Twenty points were left open, from the transform's sign to the size of the 16³ variant. They are fixed as
   Q1 to Q20 in Phase 0's Progress.
2. **All three oracles meet decision 5 with two to three orders of margin.** The largest errors (*measured*):
   - transforms 8.0e-15, against 1e-12;
   - projection 1.3e-15, against 1e-13 or 1e-12 by check;
   - PCG 1.1e-15, against 1e-12.

   The results are the same at `-O0 -fcheck=all` and `-O2` (the last digits of a few checks differ). They are
   the same again with the repository's own CMake flag sets: Debug with `-fcheck=all -Wunused`, and Release
   with `-O3` and `-Werror`, under gfortran 15.2.
3. **Six checks were wrong as first planned or written.** Planted errors or an independent review exposed each
   one, and each was fixed before its phase closed.
   - One would have failed on correct code: "Hermitian bit for bit" is false, because signed zeros differ in
     their bits. It is now counted by value.
   - Five could not fail:
     - the packed adjoint identity cancels μ, so a wrong μ passed;
     - a plane-symmetry loop was circular;
     - a rotation was compared with its own literal;
     - the window counts coincide at n = 4 for an off-by-one window;
     - λ was shared by every PCG route, so λ = 0.5 passed all checks.

     Each now has a plant showing that it fails.
4. **gfortran 15.2 under `-Werror` gives false "(maybe-)uninitialized" warnings.** They hit an unallocated
   allocatable assigned from a function result, and a class function result passed straight on as an
   argument. Explicit allocation or a local avoids them. Decision 6's recipe keeps `-Wmaybe-uninitialized`,
   which the repository's CMake turns off, so the recipe is the stricter of the two.
5. **Behaviour of the PCG reference** (*measured*, reported and not gated): iterations to ‖r‖ ≤ 1e-14 ‖b‖ are
   - 15 for the padded case,
   - 41 with the zero face, non-monotone and under the cap of 64,
   - 1 for the unpadded case,
   - 20 for the 16³ variant, without a dense matrix.

   Cholesky of the right-hand side rounded once to single precision lands 2.0e-8 from x_true.
6. **At M = 12 no stencil reaches one voxel twice.** The note's "duplicate destinations are added" could
   therefore not fail on the fixture. It is now exercised on grids of side 2 and 3, a check the plan did not
   list.
7. **Oracles can share procedures but not constants.** Rule `defs` refuses an imported constant from a module
   other than the defs module. The three modules share four error helpers as procedures exported by
   `mlxf_oracle_dft`, and keep their thresholds local (Q2).

## What changed, phase by phase

| Phase | Files (all in the file table) | Diff | Time (box) |
| --- | --- | --- | --- |
| 0, baseline | the plan: contract C0 to C3, Q1 to Q20, threshold map | `review/phase_0.diff`, 1 file | 20 of 30 min |
| 1, transforms | `src/test/mlxf_oracle_dft.f90` (new); the plan | `review/phase_1.diff`, 2 files | 12 of 60 min |
| 2, projection and adjoint | `src/test/mlxf_oracle_projection.f90` (new); `mlxf_oracle_dft.f90` (helpers exported); the plan | `review/phase_2.diff`, 3 files | 22 of 180 min |
| 3, PCG | `src/test/mlxf_oracle_pcg.f90` (new); the plan | `review/phase_3.diff`, 2 files | 17 of 120 min |
| 4, report | this report; the plan | `review/phase_4.diff` | 5 of 30 min |

`review/` is `/home/hael/agent_runs/mlxf_oracles/review/`.

The net change:
- three new modules, 1,965 lines in all: `mlxf_oracle_dft` 292, `mlxf_oracle_projection` 911,
  `mlxf_oracle_pcg` 762;
- the plan's Progress;
- one file-table row extended;
- this report.

Nothing under `src/core/`, `scripts/` or `cmake/` changed, and none of the shared test files did.

**Exported names:**
- `mlxf_oracle_dft`:
  - the transforms `oracle_dft_1d`, `oracle_idft_1d`, `oracle_dft_3d`, `oracle_idft_3d`;
  - `oracle_dft_selfcheck`;
  - the shared helpers `oracle_flat`, `oracle_rel_error`, `oracle_finite_or_inf`, `oracle_all_finite`.
- `mlxf_oracle_projection`:
  - the fixture: `oracle_proj_phantom`, `_rotation`, `_polar_coords`, `_slice_coords`, `_queries`;
  - the stencil and field: `oracle_proj_stencil`, `_padded_field`;
  - the operators: `oracle_proj_matrix`, `_gather`, `_scatter`, `_numerator`, `_density`, `_route`;
  - the packed half: `oracle_proj_pack`, `_expand`, `_fold`, `_packed_gather`, `_packed_scatter`,
    `_multiplicity`;
  - `oracle_proj_selfcheck`.
- `mlxf_oracle_pcg`:
  - the class `oracle_pcg_problem`, with bindings `new`, `kill`, `set_cap`, `window`, `matrix`, `apply`,
    `apply_fft`, `precond`, `precond_dense` and `solve`;
  - `oracle_pcg_true`, `oracle_pcg_cholesky` and `oracle_pcg_selfcheck`.

Each self-check returns `(labels, errors, limits)` and asserts nothing.

## Decisions taken under delegation

All are recorded in the plan's Progress; the phase is named.

- **Phase 0, Q1:**
  - What: "imports intrinsic modules only" is read as "nothing outside the intrinsic modules and this plan's
    own oracles". The projection and PCG modules import procedures of `mlxf_oracle_dft`.
  - Why: decision 2's shared transform, and the house rule against a second copy of a routine.
- **Phase 0, Q2:**
  - What: the self-check's form is plain arrays, with the limits returned beside the errors.
  - Why: rule `defs` refuses exported constants and behaviourless records.
- **Phase 0, Q3 to Q20:** the transform's sign; the Rz/Ry forms; the angles and order of the samples; the
  Cartesian half slice; the boundary queries; the separable explicit G; the packed convention and μ; the PCG
  vector order and window; the zero face; the transforms of real data; the dense preconditioner check; the
  preconditioned solve; the nonzero guess; the unpadded case; −H as the refused case; 16³ meaning M = 16, N = 8.
- **Phase 0, threshold map:** each planned check is assigned one of decision 5's numbers and a measure.
  - Exact checks count mismatches by value, never bits.
  - Element checks are |Δ| over the sum of |terms|.
- **Phase 1:**
  - Inverse-impulse checks and the cubes 4³ to 16³ were added.
  - Non-finite values are reported as +Inf through `ieee_arithmetic`, and C0 was amended to name it.
  - The negative controls are planted in copies, never in the repository's file.
- **Phase 2:**
  - The shared helpers are exported from `mlxf_oracle_dft`; its file-table row was extended to Phase 2 before
    the edit.
  - A 26th check, "row duplicates", was added.
  - "Adjoint with D" goes through the module's numerator.
  - The fixed integer input sequences are recorded.
- **Phase 3:**
  - The class `oracle_pcg_problem`: the solve needs more than five arguments.
  - Status 3 for a non-finite b or x0.
  - The stop is applied before the first iteration.
  - The value counts of H pin λ and the window; they were derived by an independent Python enumeration.
  - C3 was amended: the caller computes the true residual.
- **Phase 4:** an extra, ungated compile of the modules with the repository's CMake flag sets (Debug and
  Release `-O3`) under gfortran 15.2, to inform the Mac integration.

## Deviations from the plan

- **The contract text was amended twice, in Progress:**
  - C0's imports now name `ieee_arithmetic`;
  - C3's solve outputs: the true residual is computed by the caller, the early stop, status 3.

  Section 2's "intrinsic modules only" is read as Q1 says.
- **One file was edited outside its original phase:** `mlxf_oracle_dft.f90` in Phase 2, its row extended first.
  No file outside the table was changed.
- **More checks than section 8 lists:** DFT 12, projection 26, PCG 14. No check of the plan was dropped, and no
  threshold, fixture or limit was changed or loosened.
- **Expected effects that did not occur:** none. Three checks come out exactly 0 for a reason, and each still
  fails under its plants:
  - the 1D impulse: its reference is the twiddle's own arithmetic;
  - the multiplicity identity: quarter-integer inputs;
  - the stencil against the matrix on unit vectors: dyadic products.

## Evidence against the baseline

- **The static gate.** It passes on the untouched base: `check_tree: passed`, 1.3 s, load 0.31. It passes again
  at the end of every phase, with the expected warning that the new files are untracked.
- **Phase 4, from scratch on the final tree:**
  - both levels build with no compiler output (`scratch/keep/phase4_final_build_{O0,O2}.log`);
  - all three self-checks pass;
  - their output is identical to each phase's own logs (`scratch/keep/phase4_final_run_*`).
- **The repository's CMake flag sets** compile and run all three with no warning:
  `scratch/keep/phase4_repo_flags.log`.
- **Errors at both levels** (*measured*):

  | Module | Checks | Largest at -O0 | Largest at -O2 | Limits | Plants, checks covered |
  | --- | --- | --- | --- | --- | --- |
  | `mlxf_oracle_dft` | 12 | 8.0e-15 | 8.0e-15 | 1e-12 | 10, 12 of 12 |
  | `mlxf_oracle_projection` | 26 | 1.3e-15 | 1.3e-15 | 0 / 1e-13 / 1e-12 | 23, 26 of 26 |
  | `mlxf_oracle_pcg` | 14 | 1.1e-15 | 1.0e-15 | 0 / 1e-12 | 19, 14 of 14 |

  The per-check tables are in each phase's Progress entry. The controls' logs are
  `scratch/keep/phase{1_dft,2_proj,3_pcg}_controls.log`; Phase 2's rerun of the DFT controls is
  `phase2_dft_controls_rerun.log`.
- **Compile and run times** (*measured*, load 0.15 to 0.22; `scratch/keep/phase4_timings.log`):

  | Module | Compile -O0 | Compile -O2 | Self-check run -O0 | Self-check run -O2 |
  | --- | --- | --- | --- | --- |
  | `mlxf_oracle_dft` | 0.18 s | 0.34 s | 0.01 s | 0.00 s |
  | `mlxf_oracle_projection` | 0.41 s | 1.20 s | 0.02 s | 0.01 s |
  | `mlxf_oracle_pcg` | 0.30 s | 0.86 s | 0.21 s | 0.09 s |

  The PCG run includes the reported 16³ solve. Memory stays at or below 8 MB.

## Left open for the maintainer

- **Mac integration (decision 8):**
  - Apply the diff and add the three untracked modules.
  - Build Debug and Release under GNU Fortran 16.2 with `MLXF_WERROR=ON`. The modules are globbed into
    `mlxf_test_exec`, never into the library. A 16.2 warning is fixed there.
  - Until that build passes, the oracles are "delivered on dell2".
- **Testers and comparisons**, owned by each toy's plan (K2, K6, K8):
  - a tester calling `oracle_*_selfcheck` and asserting errors ≤ limits, with its registry row;
  - the comparison of the MLX kernels with these oracles;
  - the device tolerances of the examples note (1e-4 and 1e-3), frozen in `mlxf_test_defs`.

  The oracles' own limits may move to `mlxf_test_defs` then (Q2).
- **Choices most worth a look:**
  - Q1, the shared transform: if vetoed, private copies;
  - Q19, −H standing for "deliberately indefinite";
  - Q20, 16³ read as M = 16;
  - the PCG class design and its status 3;
  - the helpers exported from `mlxf_oracle_dft` rather than a module of their own.
- **Reported, not gated:**
  - the PCG iteration counts and residual histories, in `scratch/keep/phase3_pcg_run_{O0,O2}.log`;
  - Cholesky of the single-precision b;
  - the compile and run times.
- **Not here:** the pose-objective oracle (K5, decision 1), and the history entry (decision 10). The plan moves
  to `completed/` once read.

## Suggested commit message

```text
test: host oracles for the Fourier projection, its adjoint and the PCG solve

Add plain-Fortran double-precision oracles in src/test that build without the library:
mlxf_oracle_dft (direct 1D/3D transforms and shared error helpers), mlxf_oracle_projection
(Kaiser-Bessel gather, explicit matrix from scalar geometry, scatter, numerator, density,
route and packed Hermitian half) and mlxf_oracle_pcg (stencil matrix, transform operator,
preconditioner, Cholesky and reference PCG). Each self-check is held to closed forms within
decision 5's limits, and planted errors show every check can fail. Written and checked on
dell2 (run mlxf_oracles); the Mac Debug/Release build and the testers follow.
```

## Appendix: the build recipe and the drivers (decision 6)

They live in `/home/hael/agent_runs/mlxf_oracles/scratch/keep/drivers/` and are not in the repository. The
negative-control harness (`run_controls.py`) and the plants (`plants_{dft,projection,pcg}.py`) sit beside them.

`build_level.sh`:

```bash
level="$1"; exe="$2"; shift 2          # build_level.sh O0|O2 <exe> <modules in dependency order> <driver>
case "$level" in
    O0) flags="-O0 -g -fcheck=all" ;;
    O2) flags="-O2" ;;
    *) echo "unknown level $level"; exit 2 ;;
esac
out=/home/hael/agent_runs/mlxf_oracles/scratch/build_$level
mkdir -p "$out"
objs=()
for src in "$@"; do
    obj="$out/$(basename "${src%.f90}").o"
    gfortran -std=f2018 -Wall -Wextra -Werror $flags -J "$out" -c "$src" -o "$obj" || exit 1
    objs+=("$obj")
done
gfortran $flags "${objs[@]}" -o "$out/$exe" || exit 1
```

`mlxf_oracle_dft_main.f90`. The projection driver is the same with `oracle_proj_selfcheck` and its own names:

```fortran
program mlxf_oracle_dft_main
use, intrinsic :: iso_fortran_env, only: output_unit, real64
use mlxf_oracle_dft, only: oracle_dft_selfcheck
implicit none
character(len=:), allocatable :: labels(:)
real(real64),     allocatable :: errors(:), limits(:)
integer                       :: i, nfail
logical                       :: pass
call oracle_dft_selfcheck(labels, errors, limits)
nfail = 0
do i = 1, size(labels)
    pass = errors(i) <= limits(i)
    if( .not. pass ) nfail = nfail + 1
    write(output_unit,'(A,A,ES10.3,A,ES10.3,A,A)') labels(i), ' error ', errors(i), ' limit ', limits(i), '  ', &
        merge('pass', 'FAIL', pass)
end do
write(output_unit,'(A,ES10.3,A,I0,A,I0)') 'largest error: ', maxval(errors), ', failed: ', nfail, ' of ', size(labels)
if( nfail > 0 ) error stop 1
write(output_unit,'(A)') 'oracle_dft: passed'
end program mlxf_oracle_dft_main
```

`mlxf_oracle_pcg_main.f90`. The same loop over the self-check, then the reported quantities:

```fortran
call prob%new(4, 8, 'surface', 1._real64)
h  = prob%matrix()
b  = real(real(matmul(h, reshape(oracle_pcg_true(4), [64])), real32), real64)   ! b rounded once to real32
call oracle_pcg_cholesky(h, b, xc, minpivot)                                     ! reported: |xc - x_true|
call prob%kill()
do icase = 1, 4               ! padded from 0, padded from 1, zero face, unpadded
    ...                       ! new(4, 8, 'surface' | 'face') or new(4, 4, 'identity')
    bl = prob%apply(oracle_pcg_true(4))
    call prob%solve(bl, x, hist, info)       ! reported: info, |bl - apply(x)| / |bl|, hist / |bl|
    call prob%kill()
end do
call prob%new(8, 16, 'surface', 1._real64)   ! the 16-cubed variant, without a dense matrix
bl = prob%apply(oracle_pcg_true(8))
call prob%solve(bl, x, hist, info)           ! reported: iterations, true residual, |x - x_true|
call prob%kill()
if( nfail > 0 ) error stop 1
```
