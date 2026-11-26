# Toy example policy

How test-only code that stands for SIMPLE code is written. A toy works out a GPU kernel on a small example,
and it shows how that kernel would sit in SIMPLE's architecture. To do the second, it must look like SIMPLE:
the same classes, the same method names and call order, the same data conventions and the same layering.

Ruled by Hans on 2026-11-24 ("make the toy code that is supposed to emulate SIMPLE look a whole lot more
like it looks in SIMPLE ... make it a policy for any new toy examples that come in"). He accepted the three
points of section 7 the same day.

## 1. Scope

- **A toy** is test-only code under `src/test/` that stands for a piece of SIMPLE: a calculator class, a
  strategy's loop, a reconstruction step. It imports the public `mlxf` module, as a user does.
- **The library is not touched by this policy.** No SIMPLE type, constant or naming enters `src/core/` or
  `src/defs/`. The library offers general operations; only the toys speak SIMPLE's language.
- **The oracle is not a toy.** A toy's reference stays plain Fortran in double precision, which follows
  the mathematics and shares no code with the toy (test environment policy).

## 2. The mirror rule

1. **One toy type per SIMPLE class, under SIMPLE's type name.** The module is `mlxf_toy_<stem>`, where
   SIMPLE's module is `simple_<stem>`. Submodules follow SIMPLE's split by concern, for the concerns the toy
   has.

   | SIMPLE | Toy |
   | --- | --- |
   | `simple_polarft_calc`, type `polarft_calc` | `mlxf_toy_polarft_calc`, type `polarft_calc` |
   | its submodules `simple_polarft_memo`, `_block`, `_shiftmap` | `mlxf_toy_polarft_memo`, `_block`, `_shiftmap` |

2. **Procedures carry SIMPLE's names and are called in SIMPLE's order.** For the polar calculator: `new`,
   `set_ref_pft`, `set_ptcl_pft`, `memoize_refs`, `memoize_ptcls`, `score_block_posterior`,
   `setup_shiftmaps`, `gen_shiftmap`, `shiftmap_mode`, `kill`. A procedure with no counterpart in SIMPLE (the
   submission and collection of a GPU batch, a tile plan) is named for what it does and recorded as an
   addition (section 4).
3. **Dummy arguments are SIMPLE's:** the same names, meaning, units, kinds and order, for the dummies the
   toy keeps. Where SIMPLE passes its `parameters` or `builder` objects, the toy passes a small record whose
   members carry SIMPLE's member names, for the members it reads.
4. **Host data has SIMPLE's shapes and index meaning.** For example:
   - references are `(pftsz, kfromto(1):kfromto(2), nrefs)`, with the half chosen by `iseven`;
   - particles are addressed through `pinds`;
   - shifts are in pixels of the box the shift matrices act on, and rotations are indices of the angular
     grid.

   Device arrays may take any layout. The conversion is written where SIMPLE would write it, in the
   memoisation.
5. **The layering is SIMPLE's: strategy, then domain object.**
   - The calculator owns the references, the particle batch's memos and the GPU workspace.
   - A driver stands for the strategy's loop (the table fill with its seed, score, screen and refinement
     steps; the reconstruction's batch loop). It calls the calculator as SIMPLE's strategy calls its own.
   - Testers and benchmarks call the driver or the calculator, never the workspace's internals.
6. **The seam is visible.** All MLX state of a toy class sits in one component, a workspace type created in
   `new` and released in `kill`. Each mirrored method is either host code, as in SIMPLE, or a call into the
   workspace. The seam shows what integration needs to know:
   - which class owns the GPU state, and for how long (one part process, one iteration);
   - what is resident on the GPU;
   - what crosses to the host, and where the host waits.
7. **The execution model is SIMPLE's.** One process is one part with a team of OpenMP threads. MLX is called
   by one submitting thread from outside any parallel region (binding contract policy). Particles come in
   batches, as SIMPLE batches them.

## 3. What stays different, and is declared

- **Size.** Fixtures are small. A toy has no project file, no command line and no image I/O.
- **Trimmed members.** A toy carries the members and procedures its kernel needs, not the whole class.
- **The GPU route's arithmetic and layout,** which are the point of the toy.
- **mlx-fortran's house rules win over SIMPLE's form** where the two conflict: the layout and use-block
  rules, the comment rules, no `block` or `goto`, visibility, zero warnings. The one exception is the arity
  of mirrored procedures (section 7).
- **Every difference is written down.** A toy's design note has a section "Differences from SIMPLE": each
  member, procedure or argument that is trimmed, added or changed, with the reason.

## 4. The mirror ledger and its check

- `scripts/toy_mirror.txt` holds one line per public type, per type-bound procedure and per public module
  procedure of every `mlxf_toy_*` module (SIMPLE's `vol_pad2ref_pfts_opt` and `fproject_polar_batch_opt` are
  module procedures, so their toys are too): the toy's module and name, then SIMPLE's module and name, or
  `addition` with a reason. A tester's entries (`mlxf_toy_*_tester`) are the registry's and need no line. Its
  header records the SIMPLE commit that was read. Code comments never carry a commit.
- Rule `mirror` of `scripts/check_rules.py` fails when:
  - a public type, type-bound procedure or public module procedure of a `mlxf_toy_*` module is missing from the
    ledger;
  - a line names a SIMPLE counterpart but the toy's name differs from it, or its module is not
    `mlxf_toy_<stem>` beside `simple_<stem>` (`mlxf_toy_<stem>_mlx` stands beside `simple_<stem>` too when the
    seam ledger classes that module as device, and only then: section 8);
  - an `addition` line has no reason.
- The rule and the ledger enter with the first refactoring under this policy, in the same change, with a
  planted violation shown to fail.

## 5. Bringing a toy in

1. Its design note names the SIMPLE classes it mirrors, the methods kept, the seam and the differences
   ([`mlxf_kernel_families.md`](../implementation_notes/planned/mlxf_kernel_families.md) for the kernel
   families).
2. Its plan follows `doc/how2s/how2write_agent_plans.md` and pins the SIMPLE commit it reads.
3. The ledger gains the toy's lines in the change that adds the code.
4. SIMPLE is read, never edited, and no SIMPLE source file is copied in. A toy re-implements the miniature.

## 6. Existing code

Milestone 1's kernels predated this policy: they modelled a GPU workspace beside SIMPLE's calculator, under
their own names (`polar_table`, `score`, `prepare_maps`, `score_maps`). The roadmap's rank 0b refactored them
(run `mlxf_toy_arch`, 2026-11-24): the polar toy is now `polarft_calc` (`src/test/toys/polar/mlxf_toy_polarft_calc.f90`
with its submodules `_core`, `_memo`, `_block`, `_shiftmap`), its GPU workspace `polarft_workspace`
(`mlxf_toy_polarft_workspace.f90` and its submodules) and the driver `eul_prob_tab`
(`mlxf_toy_eul_prob_tab.f90`). No code is exempt any more: the ledger `scripts/toy_mirror.txt` lists every
public type and binding of the three modules, and rule `mirror` holds it to the code. The toy's differences
from SIMPLE are in [`mlxf_kernel_families.md`](../implementation_notes/planned/mlxf_kernel_families.md),
section 3. The projector of family B1 (run `mlxf_kernel_k2`, 2026-11-25: `mlxf_toy_projector` with its workspace
and `mlxf_toy_projector_pft_batch`) was written under the policy from the start; its two mirrored module
procedures (`fproject_polar_batch_opt`, `vol_pad2ref_pfts_opt`) brought public procedures into the ledger
(section 4), and its differences are in the same note's section 4.

## 7. Names, arity and drivers (Hans, 2026-11-24: "Accept all three")

- **The module prefix `mlxf_toy_`.** The test area keeps its name, `unit_kernels`, so the CTest entries do
  not move.
- **An arity exemption for mirrored procedures.** The house rule allows at most five dummy arguments.
  SIMPLE's signatures sometimes carry more (`score_block_posterior` has nine). A procedure the ledger lists
  as mirrored keeps SIMPLE's dummy list, as a `bind(c)` procedure keeps C's. Additions obey the rule. Rule
  `arity` reads the ledger for the exemption; that change enters with rule `mirror` (section 4).
- **A driver per strategy, under the strategy's name** (`eul_prob_tab` with `fill_tab_range` for the dense
  table), trimmed like the calculators.

## 8. The integration shape (Hans, 2026-11-25: "implement the toy examples in mlx-fortran in the same way so that we can model safely over here and make the integration easier downstream")

A toy class has the file layout SIMPLE's class will have once it can run on MLX, so that the integration is a
transcription. SIMPLE's precedent is its block kernel and `USE_OPENMP_OFFLOAD` (read at `d354efee2`). Run
`mlxf_toy_seam` brought the three toys to this shape (2026-11-26).

1. **Three classes of toy file.** `scripts/toy_seam.txt` gives every `mlxf_toy_*` file that is not a tester its
   class, and rule `seam` of `scripts/check_rules.py` holds the ledger to the files.

   | Class | What it is | What it may import |
   | --- | --- | --- |
   | host | a parent module, a host submodule, a driver | no MLX name: not `mlxf`, not a generated module, not a device module. It compiles without the library |
   | glue | a submodule of the class named `<host unit>_mlx` | `mlxf` and device modules, inside its one `#ifdef USE_MLX` branch only |
   | device | a module (with its submodules) that holds MLX state and kernels: a workspace, the device PCG engine | no host module of a toy class, except `mlxf_toy_device_work` and, for a device module `<stem>_mlx`, its own host half `<stem>` |

2. **One opaque component.** `mlxf_toy_device_work` declares `type, abstract :: device_work` with one deferred
   binding, `kill`. A class holds its device state as `class(device_work), allocatable` (the calculator's `ws(:)`
   is an array of two). The workspaces extend the type.
   - A holder calls `kill` on every element before it deallocates. The release of MLX handles never rests on
     the finalization of a polymorphic component.
   - What one class hands another on the device crosses as `class(device_work)` too: the projector's bank of
     sections (`projector_bank`), the reconstructor's operator (`get_pcg_operator`). The receiver resolves the
     dynamic type with `select type`; a wrong type is a refusal with a message.
3. **The glue's form.**
   - A glue procedure is a module procedure named `<host procedure>_mlx`, private to the class, declared in the
     parent in one interface block headed "MLX".
   - The host procedure's whole knowledge of the device is a guarded call, `if( self%l_mlx ) call
     <name>_mlx(self, ...)`. No dummy of such an interface has an MLX type.
   - A glue file holds its body under `#ifdef USE_MLX` and, under `#else`, stubs that set the status and the
     message "built without MLX". `USE_MLX` is set on `mlxf_test_exec`, always; it appears in glue files only,
     once per file.
   - The twin `<name>_mlx` of a mirrored procedure may keep SIMPLE's dummy list (rule `arity`).
4. **The backend is chosen at `new`,** from the member `l_mlx` of the toy's `parameters` record (an addition:
   the name of SIMPLE's parameter is the maintainer's). It defaults to true. No environment variable is read.
   - The polar calculator has a host route: `score_block_posterior` is a miniature of SIMPLE's block kernel in
     single precision, and `fill_tab_range` selects once between the host branch (the blocks under
     `!$omp parallel do`, as SIMPLE's) and the MLX branch (serial submission and collection). The host route is
     a model of control flow: it is never timed and no speed is claimed for it.
   - The projector and the reconstructor have no host route: with `l_mlx` false their `new` is refused with
     "the toy has no host route". The reconstructor's five operator procedures (`mask_mul`, `apply_normal`,
     `apply_normal_kernel`, `apply_precond`, `dot_real_volume`) keep SIMPLE's host arrays: each sends its
     volume to the device, applies the device form and brings the result back.
5. **A device engine beside a host module.** Where SIMPLE's module would gain a device engine beside its host
   one, the toy has two modules: `mlxf_toy_pcg_solver` keeps the host record (`pcg_solver_outcome`), and the
   device module `mlxf_toy_pcg_solver_mlx` has the operator and `pcg_solve` on device vectors. Both stand
   beside `simple_pcg_solver` in the mirror ledger.
6. **The build without MLX is proved by the compiler.** `test/offstate/` is a CMake project of its own: the
   host and glue files the seam ledger names, compiled without `USE_MLX`, with no path to the library's modules
   and no link to it. `scripts/check_toy_offstate.sh` builds it in Debug and Release and runs its program,
   which fills the polar host route's table and asks every class for the MLX backend (each refuses with the
   stub's message). With `--exec` the table equals, byte for byte, the one `mlxf_test_exec` writes on the host
   backend. `scripts/release_gate.sh` runs the check; it is not a CTest entry.
7. **A new toy class enters in this shape.** The change that adds it gives its files their lines in both
   ledgers, adds its cycles and refusals to sub-suite `seam`, and has the off-state program ask it for the MLX
   backend. A `pending` line is not available to new code: `SEAM_PENDING` is 0.
