# Refactoring of the library and of the test tree (run `mlxf_refactor`, on the M5 Ultra)

Status, 2026-11-26: planned; decisions stand as recommended under the maintainer's go of 2026-11-26, open to
his review. Base: the commit that holds this plan (the run pins its hash in Phase 0 and records it); checked
against `b2c43a4`. Machine: the M5 Ultra only (30 cores, 103.1 GB, the only GPU and the only machine that builds
the library), in a copy of the checkout, one run at a time. Supersedes: none. Depends on: nothing outside the
tree. The roadmap's rank 2d (decision 16).

## 1. Why

Hans, 2026-11-26: "`mlxf_array` is a very large module now. It is also hard to read with the interfaces crammed
together without any lines in-between. It also looks messy, like we have just piled stuff in there without much
thought. How does this need to be refactored? Same comment for: `mlxf_ops`. `.inf` files lack `!@descr`. Also
we need to lift over the code base map machinery from XEMA/SIMPLE ... `mlx_linalg` looks kind of small. Is that
really everything? I thought we would be able to replace BLAS with mlx. The test folder should be divided into
subfolders."

The library grew by phases of the parity plan, each adding the signature classes and helpers its functions
needed to the one place every family could reach. Nothing was wrong at each step; the sum is a module whose
reader cannot see its parts. This run gives each part a home named for what it does, makes the layout of an
interface block a rule the formatter enforces, gives every directory its description and the tree its map, sorts
the test tree, and answers the BLAS question with a table and a measurement. It changes no public name of `mlxf`
and no result.

## 2. Contract

- **Identical change.** No public name of `mlxf` is added, removed or changed, except as decision 9 rules; every
  unit area keeps its count and passes; the toys' digests and identity lines are unchanged bit for bit; the
  installed consumer builds and passes. A result that moves is a stop.
- **Library and tests.** `src/core/`, `src/test/`, `test/`, `scripts/`, the policies, the plans index and the
  history change. `src/defs/` changes only if a vocabulary moves with its only user (decision 5).
- **Builds:** hand-configured trees with `-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`, Debug and Release.
- **Python** the gate runs uses the standard library and nothing newer than 3.7.
- **Git is read-only.** Files move with `mv`; the report lists every move as old path, new path, so that the
  maintainer may replay them with `git mv` and keep the history (decision 11).

### What the check found (2026-11-26, at `b2c43a4`)

1. `src/core/array/mlxf_array.f90` is 2,946 lines: the type `mlx_array` and its bindings (about 230 lines); 98
   abstract interfaces of C signature classes (`mlxc_unary_op` to the last, lines 229 to 1,176 and three later
   blocks, about 1,050 lines in all); the transfer generics `mlx_from`, `mlx_to`, `mlx_to_alloc`, `mlx_item`,
   `mlx_view`, `mlx_alloc` with their kind and rank specifics (about 320 lines); and the interfaces of the
   submodule procedures (about 1,350 lines), of which 95 are the signature helpers `mlxf_<class>_op`
   implemented in `mlxf_array_operations.f90` (2,410 lines). The public block names about 110 entities.
2. **The helpers need nothing private.** In `mlxf_array_operations.f90` the type's private component is touched
   twice, both to ask whether an optional array in a list is empty (`c_associated(a(i)%h%ctx)`); everything else
   goes through `mlxf_handle` (public) and `adopt` (a module procedure of `mlxf_array`, not public, used only by
   its submodules). `mlxf_array_transfer.f90`, `_borrow`, `_elementwise`, `_evaluation`, `_fast`, `_io`,
   `_distributed`, `_closure` touch no private component; `_random` touches one; `_lifetime` all 18 uses.
3. The interface bodies of the helpers follow each other with no blank line and no comment;
   `scripts/restyle_fortran.py` separates procedures under `contains` and, by its own docstring, not interface
   bodies. The generics of `mlxf_ops.f90` are already one block each, separated by blank lines.
4. `src/core/ops/mlxf_ops.f90` is 1,573 lines: one module whose public block lists about 150 names one per
   line, 71 generic interfaces, and the interfaces of eight submodules (`_elementwise`, `_math`, `_logic`,
   `_shape`, `_index`, `_reduce`, `_create`, `_sort`; 90 to 621 lines each). The submodules share nothing but
   the module's imports.
5. **`.inf` files.** 17 exist; 10 have no `!@descr:` (`src/core/compile`, `distributed`, `fft`, `io`, `linalg`,
   `ops`, `random`, `transforms`, `test/consumer`, `test/offstate`); `src/`, `scripts/`, `scripts/probes/` and
   `doc/compiler_issues/` have none. `scripts/check_descr.py` reads Fortran files only.
6. **The map machinery.** SIMPLE: `scripts/generate_codeoverview.pl` (Perl, 322 lines), writing
   `doc/code_overview/code_base_map.md`. XEMA: `scripts/generate_codeoverview.py` (Python, 168 lines, "adapted
   from SIMPLE's"), writing `AI_notes/specification/code_base_map.md`, with `--check` run by XEMA's
   `scripts/check_tree.sh`; it reads `!@descr:` from the first 40 lines of each Fortran file and the first line
   of `<dir>/<dir>.inf`, skips directories git ignores or does not track. Its annotations need
   `from __future__ import annotations`, which 3.7 has.
7. **Linear algebra.** `mlxf_linalg` (13 products: `matmul`, `mlx_gather_mm`, `mlx_block_masked_mm`,
   `mlx_segmented_mm`, `mlx_addmm`, `mlx_inner`, `mlx_outer`, `mlx_kron`, `mlx_vecdot`, `mlx_cross`,
   `mlx_tensordot`, `mlx_einsum`, `mlx_hadamard_transform`), `mlxf_linalg_matrix` (20: inverses, determinants,
   Cholesky, QR, LU, SVD, eigen, solvers, norms) and `mlxf_conv` (7) wrap every product, `linalg_*` and
   convolution function of mlx-c 0.8.0; the parity ledger is closed (`scripts/mlxc_parity.txt`). It is
   everything MLX has. What it is not: a layer under BLAS's names. BLAS's `gemm` with `alpha`, `beta` and
   transposes is `mlx_addmm` on transposed views; MLX's GPU has no float64; MLX runs every factorisation on the
   CPU's stream (`mlxf_linalg_matrix`'s header). SIMPLE at `28c753993` calls, by a text search (*measured*,
   approximate): `sgemm` 37 times, `cgemm` 16, `cdotc_sub` 6, `dcopy` 25, `ddot` 20, `daxpy` 10, `dgemv` 4,
   others below 7; LAPACK `dsyev` 8, `ssyev` 7, `sgesvd` and `dgesvd` 6 each, `getrf`/`getri` 7.
8. **The test tree.** `src/test/` holds 60 files in one folder: the framework (defs, utils, reduce, registry,
   the ABI probe in C and its tester), 13 oracle modules, 35 toy files of four toys, 4 benches. Test sources
   are found by `GLOB_RECURSE` in `src/CMakeLists.txt`, so subfolders build without a CMake change; the
   off-state project (`test/offstate/CMakeLists.txt`) names `src/test/<stem>.f90` and two files by path; the
   ABI probe is named by path in `test/CMakeLists.txt`; `scripts/check_rules.py` names `src/test/` 15 times
   (`TEST_DEFS`, `TOY_DIR`, `NANMAX_HOME`, `TEST_UTILS`, the registry); the policies and the skills
   `mlxf-modern-fortran` and `mlxf-binding` name paths under it.
9. The compile-time policy: one library target, per-target module directories, lean `only:` imports, `mlxf`
   the one re-export module. More modules are allowed; every module-level import is a build-order edge. The
   Release clean build is 20.3 s against R5's bound of 26.1 s (*measured*, run `mlxf_parity_rest`).

## 3. Decisions

1. **What stays in `mlxf_array`.** Recommended: the type and its bindings, the operator and assignment
   interfaces, lifetime, evaluation, the closure vectors, `mlxf_handle`, `mlx_is_live`, and a library-internal
   `mlxf_adopt` (the renamed `adopt`, public from `mlxf_array`, never re-exported by `mlxf`). Target 900 lines
   or fewer for the module file (*derived* from item 1: 230 type + about 450 operator and lifetime interfaces +
   the public block and imports). Why: what needs the private component stays; everything else reaches the type
   as a user module does.
2. **The C signature classes** (item 1's 98 abstract interfaces) move to a module of their own,
   `mlxf_c_signatures`, generated by `scripts/gen_mlxc_bindings.py` from a ledger `scripts/mlxc_signatures.txt`
   (one line per class: its Fortran name and one mlx-c function that has the signature). Recommended. Why:
   the generator already parses every prototype; the ledger makes a class's signature the header's, not a hand
   copy, and the build fails when a header changes a class. Fallback, if the generator cannot emit a class (a
   `const char*` or vector argument it does not map today): that class stays hand-written in a file of its own,
   `src/core/array/mlxf_signatures_hand.f90`, listed in the ledger as hand, and the report counts them.
3. **The helpers live with their users.** Recommended: Phase 0 tabulates which family modules call each of the
   95 helpers. A helper one family calls moves into that family (private there); a helper two or more families
   call goes to `mlxf_calls` (`src/core/array/mlxf_calls.f90` with submodules by signature group, none above
   decision 8's limit). `mlxf_check_dtype`, `mlxf_zero_based`, `mlxf_one_based`, `mlxf_axes_of`,
   `mlxf_weak_scalar`, `mlxf_unary`, `mlxf_binary` go to `mlxf_calls`. Each helper's interface gets a one-line
   comment of the C signature it serves (it has one today above its body).
4. **Transfer and borrowing.** Recommended: a module `mlxf_transfer` (`src/core/array/`) with the generics
   `mlx_from`, `mlx_to`, `mlx_to_alloc`, `mlx_item`, `mlx_view`, `mlx_alloc`, its submodules the present
   `_transfer` and `_borrow`. Why: item 2, they need no private access; they are a third of the type module's
   interfaces.
5. **The family submodules of `mlxf_array`** (`_random`, `_fast`, `_io`, `_distributed`) become submodules of
   their family modules (`mlxf_random`, `mlxf_fast`, `mlxf_io`, `mlxf_distributed`). Recommended. `_random`'s one
   private access is replaced by `mlx_is_live` or `mlxf_handle`. `_elementwise` stays with the type (it
   implements the operators).
6. **`mlxf_ops` becomes eight modules**, one per present submodule (`mlxf_ops_elementwise`, `_math`, `_logic`,
   `_shape`, `_index`, `_reduce`, `_create`, `_sort`), each with its own generics, its own public block and its
   procedures in the module or in submodules where it exceeds decision 8's limit; `mlxf.f90` imports them.
   Recommended. A generic that two of them extend (a name like `max` with specifics in two concerns) is defined
   in one and the other's specifics move there; Phase 0 lists such names. Alternative rejected: keep one
   `mlxf_ops` with eight submodules and only reformat; it keeps a 150-name interface the reader must scan.
7. **Layout rules, checked.** Recommended, each in `scripts/restyle_fortran.py` (applied) and `--check`:
   (a) one blank line between interface bodies inside an `interface ... end interface` block; (b) a public
   block of more than one line packs names to the 120-column limit, one concern per line group, a comment
   line naming the group allowed inside the continuation. Rule (b) is applied by hand in the split and checked
   by `scripts/check_rules.py` (rule `publist`: no continuation line of a public block holds a single name
   unless it is the last).
8. **A size limit, checked.** A library module or submodule file (`src/core/`, `src/defs/`, not a tester) has at
   most 1,000 lines (*guessed*: the largest file after the split by decisions 1 to 6 is expected near 800; the
   three files above it today are the ones this run splits). Rule `size` in `scripts/check_rules.py`, with a
   ledger `SIZE_LEDGER` for exceptions that may only shrink; the run's target is an empty ledger. Testers are
   not limited (the largest is 1,124 lines).
9. **The public API is frozen and checked.** Phase 0 writes `test/consumer/mlxf_api_names.f90`, a program that
   imports every public name of `mlxf` with `use mlxf, only:` (315 names, *measured* from `src/core/mlxf.f90` at
   `b2c43a4`), generated by `scripts/list_public_api.py` from `mlxf.f90`; `scripts/check_install.sh` compiles it
   against the installed module. Recommended as a permanent check: an addition then updates the list in the
   same change, a removal fails. No name changes in this run.
10. **`.inf` files and the code-base map.** Recommended: every directory holding a tracked source file
    (`.f90`, `.F90`, `.c`, `.h`, `.py`, `.sh`) has `<dir>/<dir>.inf` whose first line is `!@descr: <text>`;
    `scripts/check_descr.py` checks it. `scripts/generate_codeoverview.py` is taken from XEMA (`--root`, `--out`,
    `--check`; the included top directories `src`, `test`, `scripts`), writes `doc/code_base_map.md`, and
    `scripts/check_tree.sh` runs its `--check`. The header of the copied script says where it came from, as
    `doc/how2s/how2write_agent_plans.md` does. `CLAUDE.md` gains one line pointing at the map (proposed in the
    report, applied only on the maintainer's word).
11. **The test tree.** Recommended layout (the K3 to K7 drafts and the plans of ranks 2e and 2f assume it):
    - `src/test/framework/`: `mlxf_test_defs`, `mlxf_test_utils`, `mlxf_test_reduce`, `mlxf_test_registry`,
      `mlxf_abi_probe.c`, `mlxf_abi_probe.h`, `mlxf_abi_tester`;
    - `src/test/oracles/`: every `mlxf_oracle_*` module and tester;
    - `src/test/toys/`: `mlxf_toy_device_work`, `mlxf_toy_seam_tester`; `toys/polar/` (`mlxf_toy_polarft_*`,
      `mlxf_toy_eul_prob_tab*`, `mlxf_polarft_host_fixture`); `toys/projector/` (`mlxf_toy_projector*`);
      `toys/recon/` (`mlxf_toy_reconstructor_pcg*`, `mlxf_toy_pcg_solver*`);
    - `src/test/bench/`: every `mlxf_bench_*`.
    Each folder has its `.inf`. Module names do not change. The library's own testers stay beside the modules
    they test. Paths change in `test/CMakeLists.txt`, `test/offstate/CMakeLists.txt`,
    `scripts/check_rules.py`, `scripts/check_toy_offstate.sh`, `scripts/check_test_registry.py`,
    `scripts/gen_mlxc_bindings.py` (its probe path), the ledgers' comments, the policies, `CLAUDE.md`'s Structure
    and the two skills. The skills and `CLAUDE.md` change only in their paths (decision 14).
12. **Linear algebra against BLAS.** Recommended, in two parts.
    (a) A table, `doc/how2s/how2replace_blas.md`: for each BLAS and LAPACK routine SIMPLE calls (item 7), the
    `mlxf` call that does the same (`sgemm`, `cgemm` → `mlx_addmm` or `matmul` on views; `cdotc_sub` →
    `mlx_vecdot` with conjugation or `sum(conjg(a)*b)`; `dsyev` → `mlx_eigh` on the CPU stream in float32 only;
    ...), what the Fortran view does with the transposes, and what MLX cannot do (float64 on the GPU; LAPACK in
    double on the GPU at all).
    (b) A crossover measurement, named-only `test=bench_blas` (`src/test/bench/mlxf_bench_blas.f90`):
    `sgemm` and `cgemm` through Accelerate (linked through the system's BLAS the build already finds, or the
    bench is host-only if none is linked: Phase 0 says which) against `matmul`/`mlx_addmm` on the GPU, data
    starting and ending in Fortran arrays, for square sizes 32 to 4,096 and the shapes SIMPLE's call sites
    use where the reading finds them (the polar block product `(2nk) x 16 x 64` and the like), one call and
    batched. Reported: the size at which the GPU first wins with transfer, and without. No wrapper is added in
    this run: whether a BLAS-shaped `mlx_gemm` enters the library is the maintainer's from the table (reserved).
13. **Dead code.** A private procedure the compiler reports unused (`-Wunused-function` in Debug) after the
    split is deleted in the same phase; the report lists it. A public name is never "dead" in this run.
14. **Paths in skills and `CLAUDE.md`.** The maintainer's instruction to divide the test folder covers the path
    edits it forces in `.github/skills/mlxf-modern-fortran/` (SKILL.md and `references/testing.md`),
    `.github/skills/mlxf-binding/SKILL.md` and `CLAUDE.md`'s Structure section: paths only, no other word.
    Recommended. Anything beyond paths is proposed in the report.
15. **Order.** The cheap and independent first: `.inf` and the map (Phase 1), the formatter rules (Phase 2),
    the test tree (Phase 3), `mlxf_ops` (Phase 4), `mlxf_array` (Phase 5), linear algebra (Phase 6). Phase 4
    before 5 because `mlxf_ops`' modules are the first users decision 3's table moves helpers into.

## 4. Not in this plan

- Any new public name, renamed public name or changed dummy list of `mlxf` (decision 9).
- A BLAS-shaped wrapper (decision 12 reserves it).
- The toys' memo layout (rank 2e) and the kernel forms (rank 2f).
- Splitting testers, or moving the library's testers into `src/test/`.
- `src/defs/` beyond a vocabulary that moves with its only user.

## 5. Change types and gates

| Phase | Kind | Gate beyond the common ones |
| --- | --- | --- |
| 0 | measurement; one new check | the API list compiles against the installed module; the helper table; the digests |
| 1 | documentation and a gate script | every source directory has a described `.inf`; the map's `--check` passes, and fails with a description changed |
| 2 | formatter | `restyle_fortran.py --check --tree` passes after applying; its token proof holds; the new rule fails on a planted block |
| 3 | moves | identical: every count, every digest; `check_toy_offstate.sh --exec`; rule `mirror` and `seam` pass |
| 4 | refactor, identical | the API list; every count and digest; no file above 1,000 lines in `src/core/ops/` |
| 5 | refactor, identical | the same for `src/core/array/`; the generated signatures; `SIZE_LEDGER` empty or each entry argued |
| 6 | documentation and a bench | the table's every row cites the `mlxf` procedure; the bench runs on both devices; nothing in the library changes |
| 7 | record | the last-phase gates |

Common to every phase: Debug and Release from scratch, zero warnings; the fast gate in both; the unit areas at
their counts (core 215 or 216, array 193, ops 2,462, fft 194, linalg 632, compile 63, kernels 1,955, fast 152,
random 486, transforms 274, io 846, distributed 55); `scripts/check_tree.sh`; the formatters on every touched
Fortran file; the Release clean build's seconds recorded. The last phase adds `scripts/check_embed.sh`,
`scripts/check_toy_offstate.sh --exec`, `scripts/check_install.sh`, `scripts/release_gate.sh --allow-dirty` and
the Release fast gate 10 times of 10.

## 6. Acceptance

1. The public API list of Phase 0 compiles against the installed module at every phase's end (*exact*).
2. Every unit area passes with Phase 0's counts; the digests of Phase 0 are reproduced bit for bit (*exact*).
3. No library module or submodule file above 1,000 lines, or each one in `SIZE_LEDGER` with its reason
   (decision 8). `mlxf_array.f90` at or below 900 lines (*derived*, decision 1).
4. Every interface block's bodies are separated by one blank line; every public block packed (decision 7).
5. Every source directory has a described `.inf`; `doc/code_base_map.md` exists and its `--check` is in the
   static gate.
6. `src/test/` holds no Fortran or C file at its top level.
7. The Release clean build is at most R5's bound of 26.1 s (*measured* bound); the run records the change
   against Phase 0 (expected within ±10 %, *guessed*; a larger change is reported, not a stop below the bound).
8. Decision 12's table and the crossover numbers, both devices, with `uptime`.
9. Every new rule has a planted violation shown to fail, then removed.
10. The report lists every file moved (old, new), every module made, every helper's new home, every deleted
    private procedure, and ends with a commit message without attribution that names every new file.

## 7. Common rules and stop conditions

- No file outside the table. No test changed to pass; a count that moves is a diagnosis, not an update.
- A test executable run directly on the GPU sets `MLX_ENABLE_TF32=0`.
- A timed step (Phase 0's and the last phase's build times, Phase 6's bench) waits for a one-minute load of at
  most 4 and records `uptime`.
- Git is read-only; moves are `mv`.

**Stops:**
- a unit count or digest moves, and one diagnosis finds no defect of the move;
- a public name would have to change for the split to compile (a generic two modules extend in a way decision
  6 cannot resolve): stop with the name and the options;
- gfortran refuses a construct the split needs (a compiler bug: reproducer in `doc/compiler_issues/`, then
  stop);
- the Release clean build exceeds 26.1 s;
- the generator cannot emit more than 10 of the 98 classes (decision 2's fallback then becomes the main path:
  stop for a ruling);
- a phase exceeds twice its box; the static gate fails on something the run did not touch.

**Gates no ruling may waive:** zero warnings; the static gate; the API list; the unit counts and digests; the
library's results unchanged; no new public name.

## 8. Phases

### Phase 0, the base and its numbers (box: 90 min)

1. Pin the base; record `uptime`, the compiler, MLX and mlx-c. Build Debug and Release from scratch; record the
   Release clean build's seconds twice.
2. Every unit area and the fast gate in both; record the counts. Record the toys' digests and identity lines
   (`polarft_host` table, the dense digests, `seam`, the off-state table).
3. `scripts/list_public_api.py` and `test/consumer/mlxf_api_names.f90`; wire into `scripts/check_install.sh`;
   show it fails with one name removed.
4. The helper table of decision 3 (helper, families calling it) and the generics of decision 6 that two
   concerns extend; write both into Progress.
5. Whether a system BLAS is linked or findable for decision 12's bench.

Exit: counts, digests, build times, the API check and the two tables in Progress.

### Phase 1, descriptions and the map (box: 60 min)

1. `!@descr:` on the first line of the 10 `.inf` files without one; new `.inf` for `src/`, `scripts/`,
   `scripts/probes/`, `doc/compiler_issues/` if it holds sources (it holds reproducers: yes).
2. `scripts/check_descr.py` reads `.inf` files (decision 10); planted violation.
3. `scripts/generate_codeoverview.py` from XEMA, adapted (paths, output, top directories); `doc/code_base_map.md`;
   `--check` in `scripts/check_tree.sh`; planted violation (a description changed without regenerating).

Exit: acceptance 5; the gates.

### Phase 2, the formatter (box: 60 min)

1. `scripts/restyle_fortran.py`: rule 7(a), within its token proof; apply to the tree; `--check` passes.
2. Rule `publist` in `scripts/check_rules.py` with its planted violation; the public blocks it flags are
   repacked only where Phases 4 and 5 will not rewrite them anyway (the others are packed there).

Exit: acceptance 4 for files outside `mlxf_array.f90` and `mlxf_ops.f90`; the gates.

### Phase 3, the test tree (box: 90 min)

1. The moves of decision 11 with `mv`; the `.inf` of each new folder.
2. Paths in `test/CMakeLists.txt`, `test/offstate/CMakeLists.txt`, the scripts, the ledgers' comments, the
   policies, `CLAUDE.md`'s Structure and the two skills (paths only, decision 14).
3. Build both from scratch; every count; the digests; `check_toy_offstate.sh --exec`.

Exit: acceptance 6; identity with Phase 0; the gates.

### Phase 4, `mlxf_ops` (box: 150 min)

1. The eight modules of decision 6, each with its generics, packed public block and procedures; the helpers
   decision 3 assigns to one of them move in (from `mlxf_array_operations.f90`, deleted from there).
2. `mlxf.f90` imports the eight modules; the modules that imported `mlxf_ops` import what they use.
3. Dead private procedures (decision 13). Build, counts, digests, API list.

Exit: no file above 1,000 lines in `src/core/ops/`; identity with Phase 0; the gates.

### Phase 5, `mlxf_array` (box: 240 min)

1. `scripts/mlxc_signatures.txt` and the generator's emission of `mlxf_c_signatures` (decision 2), with its
   fallback file if needed; the hand interfaces removed from `mlxf_array.f90`.
2. `mlxf_calls` with the shared helpers (decision 3); the remaining helpers to their families.
3. `mlxf_transfer` (decision 4); the family submodules to their families (decision 5); `adopt` becomes
   `mlxf_adopt`.
4. Rule `size` with `SIZE_LEDGER` (decision 8) and its planted violation.
5. Dead private procedures. Build, counts, digests, API list, the Release clean build's seconds.

Exit: acceptance 1 to 4 and 7; the gates.

### Phase 6, linear algebra against BLAS (box: 120 min)

1. The table of decision 12(a), each row checked by reading the wrapper and, where the view transposes, by a
   test that already exists (cited) or a sentence why none is needed.
2. The bench of decision 12(b), named-only; both devices; one process; the crossover.

Exit: acceptance 8; the library unchanged in this phase; the gates.

### Phase 7, the record (box: 60 min)

The last-phase gates. `doc/policies/compile_time_policy.md` (the module map of the library),
`doc/policies/test_environment_policy.md` (the tree), the roadmap's rank 2d, the history, the index, `README.md`
where it shows the layout. The report with acceptance 10.

Exit: acceptance 9 and 10; `git status` shows paths of the file table only.

### File table

| File | What | Phases |
| --- | --- | --- |
| `src/core/array/mlxf_array.f90` | the type, operators, lifetime, evaluation | 2, 4, 5 |
| `src/core/array/`, `src/core/mlxf.f90` | the formatter's blank lines between interface bodies | 2 |
| `src/core/array/mlxf_array_operations.f90` | emptied by the moves, then deleted | 4, 5 |
| `src/core/array/mlxf_array_lifetime.f90`, `src/core/array/mlxf_array_elementwise.f90`, `src/core/array/mlxf_array_evaluation.f90`, `src/core/array/mlxf_array_closure.f90` | follow the split | 5 |
| `src/core/array/mlxf_array_transfer.f90`, `src/core/array/mlxf_array_borrow.f90` | submodules of `mlxf_transfer` | 5 |
| `src/core/array/mlxf_transfer.f90` | new: the transfer module | 5 |
| `src/core/array/mlxf_calls.f90`, `src/core/array/mlxf_calls_*.f90` | new: the shared helpers | 5 |
| `src/core/array/mlxf_signatures_hand.f90` | new, only if decision 2's fallback is needed | 5 |
| `src/core/array/mlxf_array_random.f90`, `src/core/array/mlxf_array_fast.f90`, `src/core/array/mlxf_array_io.f90`, `src/core/array/mlxf_array_distributed.f90` | moved to their families (decision 5) | 2, 5 |
| `src/core/random/`, `src/core/fast/`, `src/core/io/`, `src/core/distributed/` | the moved submodules; imports; the folders' .inf files | 1, 2, 4, 5 |
| `src/core/array/array.inf` | the folder's description | 1, 5 |
| `src/core/ops/` | the eight modules, their submodules, the testers' imports, the folder's .inf | 1, 2, 4, 5 |
| `src/core/linalg/`, `src/core/fft/`, `src/core/compile/`, `src/core/transforms/`, `src/core/runtime/` | imports; the folders' .inf files | 1, 2, 4, 5 |
| `src/core/mlxf.f90` | imports of the new modules; no name changes | 4, 5 |
| `src/core/core.inf`, `src/defs/` | descriptions; the formatter; a vocabulary that moves with its only user | 1, 2, 5 |
| `src/src.inf` | new | 1 |
| `src/test/` | the moves of decision 11; the folders' .inf files; imports; the bench's registration | 1, 2, 3, 4, 5, 6 |
| `src/test/bench/mlxf_bench_blas.f90` | new: decision 12(b) | 6 |
| `test/CMakeLists.txt`, `test/offstate/`, `test/consumer/`, `test/test.inf` | paths; the API program; descriptions; the formatter | 0, 1, 2, 3 |
| `test/consumer/mlxf_api_names.f90` | new: decision 9 | 0, 4, 5 |
| `scripts/list_public_api.py` | new: decision 9 | 0 |
| `scripts/check_install.sh` | compiles the API program | 0 |
| `scripts/check_descr.py` | reads the .inf files | 1 |
| `scripts/generate_codeoverview.py` | new, from XEMA | 1 |
| `scripts/check_tree.sh` | the map's `--check` | 1 |
| `scripts/scripts.inf`, `scripts/probes/probes.inf` | new | 1 |
| `doc/compiler_issues/compiler_issues.inf` | new | 1 |
| `doc/code_base_map.md` | new, generated | 1, 3, 4, 5, 7 |
| `scripts/restyle_fortran.py` | rule 7(a) | 2 |
| `scripts/check_rules.py` | rules `publist`, `size`; paths | 2, 3, 5 |
| `scripts/check_toy_offstate.sh`, `scripts/check_test_registry.py`, `scripts/check_embed.sh` | paths | 3 |
| `scripts/gen_mlxc_bindings.py` | the probe's path; the signatures module | 3, 5 |
| `scripts/mlxc_signatures.txt` | new: the signature ledger | 5 |
| `scripts/toy_mirror.txt`, `scripts/toy_seam.txt` | comments' paths | 3 |
| `.github/skills/mlxf-modern-fortran/SKILL.md`, `.github/skills/mlxf-modern-fortran/references/testing.md`, `.github/skills/mlxf-binding/SKILL.md` | paths only (decision 14) | 3, 5 |
| `CLAUDE.md` | Structure: paths only (decision 14) | 3, 5 |
| `doc/policies/compile_time_policy.md`, `doc/policies/test_environment_policy.md`, `doc/policies/toy_example_policy.md`, `doc/policies/binding_contract_policy.md` | paths; the module map | 3, 5, 7 |
| `doc/how2s/how2replace_blas.md` | new: decision 12(a) | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | rank 2d | 7 |
| `doc/implementation_notes/README.md` | the index | 7 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 7 |
| `README.md` | the layout | 7 |
| `doc/implementation_notes/planned/mlxf_refactor.md` | this note: Progress | 0, 1, 2, 3, 4, 5, 6, 7 |
| `doc/implementation_notes/completed/mlxf_refactor_report.md` | new: the report | 7 |

## Progress

Nothing has run. The run fills one subsection per phase: times, `uptime`, what was built and run, the counts,
the digests, the tables of Phase 0, the moves, the planted violations and the gates that caught them, stops.
