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
| `src/core/array/mlxf_transfer_copy.f90`, `src/core/array/mlxf_transfer_borrow.f90` | the submodules of `mlxf_transfer`, moved from `mlxf_array_transfer.f90` and `mlxf_array_borrow.f90` (submodules are named `<module>_<part>`) | 5 |
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
| `test/CMakeLists.txt` | the system's CBLAS (Accelerate on macOS) linked to `mlxf_test_exec` for the BLAS bench, `MLXF_HAVE_BLAS` (added in Phase 6) | 6 |
| `test/consumer/mlxf_api_names.f90` | new: decision 9 | 0, 4, 5 |
| `scripts/list_public_api.py` | new: decision 9 | 0 |
| `scripts/check_install.sh` | compiles the API program | 0 |
| `scripts/check_descr.py` | reads the .inf files | 1 |
| `scripts/generate_codeoverview.py` | new, from XEMA; in Phase 7, the version control asked only when the root is a checkout's top (the release gate's export) | 1, 7 |
| `scripts/check_tree.sh` | the map's `--check` | 1 |
| `scripts/scripts.inf`, `scripts/probes/probes.inf` | new | 1 |
| `doc/compiler_issues/compiler_issues.inf` | new | 1 |
| `doc/code_base_map.md` | new, generated | 1, 3, 4, 5, 6, 7 |
| `scripts/restyle_fortran.py` | rule 7(a) | 2 |
| `scripts/check_rules.py` | rules `publist`, `size`; paths; `PUBLIST_LEDGER` entries deleted as Phases 4 and 5 pack their blocks | 2, 3, 4, 5 |
| `scripts/check_toy_offstate.sh`, `scripts/check_test_registry.py`, `scripts/check_embed.sh` | paths | 3 |
| `scripts/gen_mlxc_bindings.py` | the probe's path; the signatures module | 3, 5 |
| `scripts/mlxc_signatures.txt` | new: the signature ledger | 5 |
| `src/CMakeLists.txt` | the generator's command depends on the signature ledger (added in Phase 5) | 5 |
| `src/core/array/mlxf_array_tester.f90` | imports of the helpers that left `mlxf_array` (added in Phase 5) | 5 |
| `scripts/toy_mirror.txt`, `scripts/toy_seam.txt` | comments' paths | 3 |
| `.github/skills/mlxf-modern-fortran/SKILL.md`, `.github/skills/mlxf-modern-fortran/references/testing.md`, `.github/skills/mlxf-binding/SKILL.md` | paths only (decision 14) | 3, 5 |
| `CLAUDE.md` | Structure: paths only (decision 14) | 3, 5 |
| `AGENTS.md`, `CONTRIBUTING.md`, `doc/architecture_principles.md`, `doc/how2s/how2set_up_dev.md`, `doc/how2s/how2use_from_simple.md`, `doc/compiler_issues/README.md` | paths of the moved test files only (added in Phase 3: they name files under `src/test/`) | 3 |
| `doc/policies/compile_time_policy.md`, `doc/policies/test_environment_policy.md`, `doc/policies/toy_example_policy.md`, `doc/policies/binding_contract_policy.md` | paths; the module map | 3, 5, 7 |
| `doc/how2s/how2replace_blas.md` | new: decision 12(a) | 6 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | rank 2d | 7 |
| `doc/implementation_notes/README.md` | the index | 7 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 7 |
| `README.md` | the layout | 7 |
| `doc/implementation_notes/planned/mlxf_refactor.md` | this note: Progress | 0, 1, 2, 3, 4, 5, 6, 7 |
| `doc/implementation_notes/completed/mlxf_refactor_report.md` | new: the report | 7 |

## Progress

The run fills one subsection per phase: times, `uptime`, what was built and run, the counts, the digests, the
tables of Phase 0, the moves, the planted violations and the gates that caught them, stops. Logs are under
`/Users/hael/agent_runs/mlxf_refactor/scratch/keep/phase<N>/` (below, `keep/phase<N>/`).

### Phase 0, the base and its numbers (2026-11-26, 10:25 to 10:40, M5 Ultra)

Base `96c5c5c272af7b688047f841897dfc98e9f30fdf` (the commit holding this plan); tree clean at the start; the
rulings file is empty. GNU Fortran 16.2.0 (Homebrew), CMake 4.5.1, MLX 0.32.4 and mlx-c 0.8.0 (Homebrew, shared),
Python 3.15.2 for the build (the gate's scripts hold to 3.7). Trees `scratch/build_release` and
`scratch/build_debug`, configured by the run's recipe (`-DMLXF_WERROR=ON -DFORTLS=OFF -DBUILD_TESTS=ON`).

Files changed: `scripts/list_public_api.py` (new), `test/consumer/mlxf_api_names.f90` (new, generated),
`scripts/check_install.sh` (runs the list's `--check` and compiles the program against the installed module),
`test/consumer/consumer.inf` (names the program), this note. No move.

**Exit items.**
- *Build times* (*measured*, `keep/phase0/build_timed.log`; `cmake --build -j 12` after a fresh configure, nothing
  else of the run's running): Release clean build **18.9 s** (load before 2.02, after 2.76) and **19.1 s** (before
  2.76, after 3.55); mean 19.0 s, against R5's bound of 26.1 s. Debug built after them, not timed. Zero warnings
  in both (`build_release_{1,2}.log`, `build_debug.log`).
- *Fast gate* in both (`gate_release.log`, `gate_debug.log`): the static gate passed, 13 of 13 fast entries,
  11.1 s and 13.9 s. Installs passed.
- *Counts* (*exact*, every area run alone by `mlxf_test_exec test=unit_<area>` with `MLX_ENABLE_TF32=0`, GPU
  devices 1; `units_{release,debug}/`): the same in Release and Debug and equal to section 5's list: array 193,
  ops 2,462, linalg 632, fft 194, compile 63, transforms 274, fast 152, random 486, io 846, distributed 55,
  kernels 1,955; **core 214 in Release, 216 in Debug.** Diagnosis: `unit_core`'s registry sub-suite asserts one
  check per device only when the allocator reused the freed address (`mlxf_registry_tester.f90`, `if( reused )`;
  the line `the freed address was reused by a new object: T|F` is printed per device): Release printed F, F,
  Debug T, T. The count is therefore 214 plus the number of `T` lines, which is the gate the later phases apply
  (the parity report's "215 or 216" saw one or two reuses).
- *Digests and identity lines* (*exact*, `keep/phase0/identity.sh`, Release, 14 invocations, run twice:
  `identity_a/identity.txt` and `identity_b/identity.txt` equal byte for byte, 224 lines, SHA-256
  `e83887f2...b034671`; kept as `keep/phase0/identity_base.txt`): `bench_polar_table` `suite=time case=1000_1
  bt=64 rt=250 nthr=30 device=gpu` with `tail=graph` and `tail=metal`, `suite=accuracy case=2500_4` on the CPU, the
  GPU and the GPU with `tail=metal` (83, 76 and 76 assertions), `suite=shiftmap case=1000_1 maps=window,screen
  ptiles=16 device=gpu` on `identity_grid.txt`; `bench_projector` `suite=time` (`form=fused tile=2500 tg=64` and
  `form=graph`) and `suite=chain` (`route=device`, `route=host`); `bench_recon_pcg suite=time n=160 out=map` for
  `system=P` and `system=R` (the four maps' SHA-256 and the history lines in hexadecimal); `unit_kernels
  suite=polarft_host` (135 table lines) and `suite=seam` (88 assertions). The off-state table:
  `scripts/check_toy_offstate.sh --exec` passed, Debug and Release, 135 lines equal to `mlxf_test_exec`'s byte for
  byte (`keep/phase0/offstate.log`, table SHA-256 `f0213844...815ad2075`).
- *The API check* (*exact*): `scripts/list_public_api.py` reads the `public ::` statements of `src/core/mlxf.f90`:
  **315 names**, as section 3 measured. `--write` generates `test/consumer/mlxf_api_names.f90` (one `use mlxf,
  only:` of all 315, unchanged by both formatters); `--check` fails when the program and the module differ.
  `scripts/check_install.sh` runs `--check`, then compiles the program against the installed module; on the
  Release tree it passed (`check_install_release.log`). Planted removal (`keep/phase0/plant_api/`): `mlx_kron`
  removed from `mlxf.f90` in a copy of the tree, built, installed: `check_install.sh` fails at the `--check`
  (`does not list the 314 public names`), and the compile of the unchanged program against the planted module
  fails with `Symbol 'mlx_kron' referenced at (1) not found in module 'mlxf'`. Regenerating the program after a
  removal makes both pass: the removal is then visible only as a line of the program's diff, which the review
  reads.
- *System BLAS* (decision 12(b)): **none is linked**: no CMake file of the tree names BLAS, LAPACK or
  Accelerate; `libmlxc` links Accelerate only for MLX's own use. **Accelerate is findable**: CMake's `FindBLAS`
  and `FindLAPACK` with `BLA_VENDOR=Apple` find the SDK's `Accelerate.framework`, and a probe program calling
  `sgemm` and `cgemm` (`'C'`, `'N'`) linked with `-framework Accelerate` agrees with `matmul` to 7.6e-6 and 1.6e-5
  at n = 64 (`keep/phase0/blas_probe/`). Phase 6 therefore links Accelerate to `mlxf_test_exec` only (a test
  target's link, through `FindBLAS`), not the library.

**Decision 3's table: helper, families calling it** (*measured* by `keep/phase0/helper_table.py`, word matches in
`src/` and `test/` outside `mlxf_array.f90` and outside the helper's own declaration; the per-helper counts are
in `keep/phase0/helper_table.md`). The names are the 117 `mlxf_*` names public from `mlxf_array`: 88 are defined
in `mlxf_array_operations.f90` (84 signature helpers and `mlxf_check_dtype`, `mlxf_axes_of`, `mlxf_zero_based`,
`mlxf_one_based`; the plan's "95" was an estimate), 23 in the family submodules (`_random` 11, `_fast` 5, `_io`
4, `_distributed` 3), `mlxf_weak_scalar`, `mlxf_unary`, `mlxf_binary` in `_elementwise`, `mlxf_handle` in
`_lifetime`, `mlxf_vector_import` and `mlxf_vector_export` in `_closure`. No tester calls a helper except
`mlxf_handle` (array, registry testers) and `mlxf_unary` (array tester). No helper is called by no family.
"Family" is the module that will hold the caller: the eight `mlxf_ops_*` concerns, `mlxf_linalg`,
`mlxf_linalg_matrix`, `mlxf_conv`, `mlxf_fft`, and the families of decision 5.

| Helpers | Called by |
| --- | --- |
| `mlxf_take_op`, `mlxf_slice_op`, `mlxf_concat_op`, `mlxf_range_op`, `mlxf_int3_op`, `mlxf_trace_op`, `mlxf_roll_op`, `mlxf_unflatten_op`, `mlxf_vector2_op`, `mlxf_strided_op`, `mlxf_count_op`, `mlxf_vector_list_op`, `mlxf_split_op`, `mlxf_split_sections_op`, `mlxf_unstack_op`, `mlxf_unstack_dim_op`, `mlxf_pad_op`, `mlxf_pad_width_op` (18) | `ops_shape` only |
| `mlxf_gather_op`, `mlxf_gather_single_op`, `mlxf_slice_dynamic_op`, `mlxf_scatter_op`, `mlxf_put_op`, `mlxf_ternary_vector_op`, `mlxf_text_op`, `mlxf_slice_update_op`, `mlxf_unique_op` (9) | `ops_index` only (`mlxf_slice_dynamic_op` follows `mlx_slice`, below) |
| `mlxf_reduce_op`, `mlxf_scan_op`, `mlxf_var_all_op`, `mlxf_var_op`, `mlxf_var_dims_op`, `mlxf_scan_all_op`, `mlxf_scan_plain_op`, `mlxf_scan_plain_all_op` (8) | `ops_reduce` only |
| `mlxf_full_op`, `mlxf_binary_int_op`, `mlxf_window_op`, `mlxf_identity_op`, `mlxf_eye_op`, `mlxf_linspace_op`, `mlxf_linspace_endpoint_op`, `mlxf_meshgrid_op` (8) | `ops_create` only |
| `mlxf_close_op`, `mlxf_compare_op` (2) | `ops_logic` only |
| `mlxf_nan_op`, `mlxf_binary_vector_op` (2) | `ops_math` only |
| `mlxf_gather_mm_op`, `mlxf_masked_mm_op`, `mlxf_binary_axis_op`, `mlxf_optional_float_op`, `mlxf_addmm_op`, `mlxf_einsum_op`, `mlxf_tensordot_op` (7) | `linalg` only |
| `mlxf_cpu_unary`, `mlxf_cpu_binary`, `mlxf_cpu_flag_op`, `mlxf_cpu_compare_op`, `mlxf_cpu_pair_op`, `mlxf_cpu_pair_text_op`, `mlxf_cpu_text_op`, `mlxf_cpu_unstack_op`, `mlxf_cpu_svd_op`, `mlxf_norm_op`, `mlxf_norm_text_op` (11) | `linalg_matrix` only |
| `mlxf_conv1d_op`, `mlxf_conv2d_op`, `mlxf_conv3d_op`, `mlxf_conv_general_op`, `mlxf_conv_transpose1d_op`, `mlxf_conv_transpose2d_op`, `mlxf_conv_transpose3d_op` (7) | `conv` only |
| `mlxf_fft_op`, `mlxf_fftn_op`, `mlxf_freq_op` (3) | `fft` only |
| `mlxf_pair_op`, `mlxf_random_key_op`, `mlxf_random_shape_op`, `mlxf_random_float_op`, `mlxf_random_int_op`, `mlxf_random_array_op`, `mlxf_random_axis_op`, `mlxf_random_axis_shape_op`, `mlxf_random_axis_int_op`, `mlxf_random_binary_op`, `mlxf_random_broadcast_op` (11, in `_random`) | `random` only |
| `mlxf_layer_norm_op`, `mlxf_rms_norm_op`, `mlxf_rope_op`, `mlxf_rope_dynamic_op`, `mlxf_attention_op` (5, in `_fast`) | `fast` only |
| `mlxf_load_op`, `mlxf_map_arrays`, `mlxf_gguf_arrays`, `mlxf_cpu_stream` (4, in `_io`) | `io` only |
| `mlxf_group_op`, `mlxf_group_peer_op`, `mlxf_group_recv_op` (3, in `_distributed`) | `distributed` only |
| `mlxf_int_op` | `ops_math`, `ops_shape`, `ops_sort`, `random`; other helpers |
| `mlxf_dtype_op` | `ops_create`, `ops_elementwise` |
| `mlxf_vector_op` | `fft`, `linalg_matrix`, `ops_shape` |
| `mlxf_ternary_op` | `linalg`, `ops_elementwise`, `ops_index`, `ops_math` |
| `mlxf_zeros_op` | `ops_create`, `ops_shape` |
| `mlxf_reduce_all_op` | `ops_reduce`, `ops_shape` |
| `mlxf_reduce_dims_op` | `linalg_matrix`, `ops_reduce` |
| `mlxf_int2_op` | `linalg_matrix`, `ops_shape`, `ops_sort` |
| `mlxf_list_op` | `ops_reduce`, `ops_shape` |
| `mlxf_check_dtype` | `distributed`, `fast`, `random`; other helpers |
| `mlxf_axes_of` | `fft`, `linalg`; other helpers |
| `mlxf_zero_based` | `fast`, `linalg`, `ops_index`, `ops_shape` |
| `mlxf_one_based` | `linalg_matrix`, `ops_index`, `ops_reduce`, `ops_sort`, `random` |
| `mlxf_weak_scalar` | the type's operators (`_elementwise`), `ops_elementwise`, `ops_math`; other helpers |
| `mlxf_unary` | the type's operators, `linalg_matrix`, `ops_create`, `ops_elementwise`, `ops_logic`, `ops_math`, `ops_shape`, `ops_sort` |
| `mlxf_binary` | the type's operators, `fast`, `linalg`, `ops_elementwise`, `ops_logic`, `ops_math`, `ops_reduce`, `ops_shape` |
| `mlxf_vector_import` | `compile`, `export`, `fast`, `transforms`; other helpers (stays with the type: closure vectors, decision 1) |
| `mlxf_vector_export` | `compile`, `export`, `fast`, `io`, `transforms` (stays with the type, decision 1) |
| `mlxf_handle` | every `mlxf_array` submodule, `distributed`, `fast`, `io`, `random`, transfer (stays with the type, decision 1) |

So 98 helpers have one family and move into it; 16 are shared and go to `mlxf_calls` (`mlxf_int_op`,
`mlxf_dtype_op`, `mlxf_vector_op`, `mlxf_ternary_op`, `mlxf_zeros_op`, `mlxf_reduce_all_op`,
`mlxf_reduce_dims_op`, `mlxf_int2_op`, `mlxf_list_op`, and the seven decision 3 names); `mlxf_handle` and the two
closure-vector procedures stay with the type. No single-family helper is called by another helper, so none drags a
second family in. `mlxf_unary`, `mlxf_binary` and `mlxf_weak_scalar` are called by the type's own operators
(`_elementwise`, which stays with the type): that submodule will import `mlxf_calls`, a module that itself imports
`mlxf_array` (legal for a submodule; Phase 5 checks it builds).

**Decision 6's generics that two concerns extend** (*measured* by `keep/phase0/generics_table.py` over the 71
generic interfaces of `mlxf_ops.f90` and the submodule that implements each specific): **one, `mlx_slice`**
(`slice_static` in `_shape`, `slice_dynamic` in `_index`). Every other generic's specifics sit in one submodule
(`max`, `min`, `sum` and the rest included). Recommended for Phase 4, by decision 6's rule: `mlx_slice` is defined in
`mlxf_ops_shape` and `slice_dynamic` moves there with its helper `mlxf_slice_dynamic_op` (the generic's static
form, the larger, is a shape operation; `mlx_slice_update*` stay in `_index`). Outside `mlxf_ops`, one generic name
is declared by two library modules: `mlx_synchronize` (`mlxf_array` and `mlxf_stream`, merged by `mlxf`); this
run leaves it.

**Decisions taken under delegation.**
1. *The identity cases are this run's own*, modelled on the toy-seam run's eleven (its `tools/identity.sh` is not
   on this machine): the same benchmarks and settings plus `polarft_host` and `seam`; inputs `polar_case.txt` and
   `shiftmap_grid.txt` copied from the run `mlxf_toy_arch`, and `identity_grid.txt` written here (the M5 grid's
   window and screen geometry with `nrefs = 1000` and `ncand = 4`, to sit on case `1000_1`; the first attempt
   with the unchanged M5 grid was refused, `identity_ab_run1.log`). Compared, never timed.
2. *`unit_core`'s gate is 214 plus the reuse lines*, not a fixed count (the diagnosis above): a fixed number would
   fail on the allocator, not on the code.
3. *The API program is compiled by `check_install.sh` directly* (`$FC -I<prefix>/include/mlxf -c`), not added to
   the consumer project's programs: it has nothing to run, and the compile against the installed module is the
   check. `--check` runs first, so an added public name fails until the program is regenerated.
4. *Accelerate for the bench*: linked to the test executable only, through `FindBLAS` with `BLA_VENDOR=Apple`
   (Phase 6 adds it to the file table when it gets there).

**What it means, in short.** The base builds clean in 19 s, passes every area at the plan's counts (core's two
allocator-dependent checks explained), and its toys' outputs are reproducible to the byte. Every public name of
`mlxf` is now listed and compiled against the installed module, and a removal is shown to fail. The split has
exactly one generic to resolve (`mlx_slice`); 98 helpers move into one family each, 16 are shared.

### Phase 1, descriptions and the map (2026-11-26, 10:37 to 10:55, M5 Ultra)

Base `96c5c5c` with Phase 0's changes in the tree; the rulings file is empty. Logs under `keep/phase1/`. No move.

Files changed: `scripts/generate_codeoverview.py` (new), `doc/code_base_map.md` (new, generated),
`scripts/check_descr.py`, `scripts/check_tree.sh`; `.inf` files: `src/src.inf`, `scripts/scripts.inf`,
`scripts/probes/probes.inf`, `doc/compiler_issues/compiler_issues.inf` (new), `src/core/{compile,distributed,
fft,io,linalg,ops,random,transforms}/*.inf` (the tag prepended, text unchanged), `src/core/core.inf`,
`src/core/fast/fast.inf`, `test/consumer/consumer.inf`, `test/offstate/offstate.inf` (tagged, and reworded where
the text was wrong or partial, decision 2 below); this note.

**Exit items.**
- *Every source directory has a described `.inf`* (*exact*): `scripts/check_descr.py` now also requires, under
  `src/`, `test/`, `scripts/` and `doc/compiler_issues/`, for every directory holding a `.f90`, `.F90`, `.c`, `.h`,
  `.py` or `.sh` file and every directory between it and its top directory, a `<dir>/<dir>.inf` whose first line
  is `!@descr: <text>` and that holds no second `!@descr:` line. 21 `.inf` files; the check passes.
- *The map* (*exact*): `scripts/generate_codeoverview.py` is XEMA's (`2848f6c`, 2026-11-12, itself adapted from
  SIMPLE's Perl), changed only in its header (where it came from), the top directories (`src`, `test`,
  `scripts`), the output (`doc/code_base_map.md`) and explicit UTF-8 reads and writes (`keep/phase1/
  make_codeoverview.py` makes the copy from XEMA's file; 29 differing lines). It runs under Python 3.9 (the
  system's) and 3.15, and uses nothing past 3.7. `doc/code_base_map.md`: 163 lines. `scripts/check_tree.sh` runs
  `generate_codeoverview.py --check` after `check_descr.py`.
- *Planted violations* (`keep/phase1/plants.sh`, each in a copy of the tree, `check_tree.sh` run on it;
  `keep/phase1/plants/*.log`): (a) the tag removed from `src/core/fft/fft.inf`: fails in `check_descr.py` ("its
  first line is not '!@descr: <text>'"); (b) `scripts/probes/probes.inf` deleted: fails ("missing"); (c) a word
  changed in `src/core/random/random.inf` without regenerating: fails in `generate_codeoverview.py --check`
  ("out of date"); (d) a module's `!@descr:` changed (`mlxf_fft.f90`) without regenerating: fails the same way;
  (e) everything restored: passes.
- *The gates* (*measured*): Release from scratch 18.7 s (load 1.36 before, 2.87 after; Phase 0: 19.0 s); Debug
  from scratch; zero warnings in both; the fast gate in both (13 of 13); installs passed. Every unit area
  (`keep/phase1/units_{release,debug}/`) at Phase 0's counts: array 193, ops 2,462, linalg 632, fft 194, compile
  63, transforms 274, fast 152, random 486, io 846, distributed 55, kernels 1,955, and core 215 in both = 214 + one
  reuse line `T` in each (the Phase 0 rule). GPU devices 1. No Fortran file changed, so no formatter run applies
  and the digests are not re-run (this phase touches no code that produces them).

**Decisions taken under delegation.**
1. *The `.inf` rule's reach* is the map's top directories plus `doc/compiler_issues/` (named by step 1), not the
   repository's root or `.claude/hooks/`, which hold a tracked script each but are outside the map and outside
   the file table. Directories between a source directory and its top directory are included, so that every
   directory the map shows has its description (`src/` holds no source of its own and gets `src.inf`, as step 1
   asks).
2. *Descriptions found wrong were corrected while tagging*: `core.inf` named six of the eleven capability folders;
   `fast.inf` named the custom kernels only, not the fused layers; `consumer.inf` and `offstate.inf` were
   sentences with a capital and a full stop, now the house's lower-case one-liners. The other eight kept their
   words.
3. *The map lists Fortran files only*, as XEMA's does: the scripts' own descriptions (their `name -- text`
   header lines) are not read. Listing them would be a further adaptation; proposed in the report, not done.
4. *The plants ran on copies* of the working tree (`cp -R`), never on the repository.

**What it means, in short.** Every source directory now says what it holds in the one form the map reads, the map
is generated from those lines and from the modules' headers, and the static gate fails when either changes
without the map. Nothing built changed: the counts are Phase 0's.

### Phase 2, the formatter (2026-11-26, 10:48 to 11:10, M5 Ultra)

Base `96c5c5c` with Phases 0 and 1 in the tree; the rulings file is empty. Logs under `keep/phase2/`. No move.

Files changed: `scripts/restyle_fortran.py` (rule 7(a) and its docstring), `scripts/check_rules.py` (rule `publist`,
`PUBLIST_LEDGER`), `src/core/mlxf.f90` (public statements packed), and blank lines only in
`src/core/array/mlxf_array.f90` (+265), `src/core/ops/mlxf_ops.f90` (+224), `src/core/ops/mlxf_ops_logic_tester.f90`
(+3), `src/core/ops/mlxf_ops_math_tester.f90` (+3), `src/core/ops/mlxf_ops_reduce_tester.f90` (+1),
`src/core/transforms/mlxf_transforms.f90` (+1), `src/test/mlxf_bench_polar_table.f90` (+1),
`src/test/mlxf_bench_projector.f90` (+1), `src/test/mlxf_toy_reconstructor_pcg_tester.f90` (+13); this note.

**Exit items.**
- *Rule 7(a)* (*exact*): `separate_procedures` now counts the depth of `interface ... end interface` blocks and
  puts one blank line after every interface body that another statement or comment follows, except before the
  block's `end interface` (and, as before, before `contains`, an `end module` or a preprocessor line). Under
  `contains` it does what it did. The token proof is untouched and held on every file it rewrote. Applied with
  the full pass (`restyle_fortran.py` then `format_use_blocks.py`) to the nine files `--check --tree` named;
  `--check --tree` then passes. The diffs of those nine files are added blank lines only.
- *Rule `publist`* (*exact*): a `public ::` statement continued over several lines holds more than one name on
  every physical line but its last (comment and preprocessor lines inside it are skipped). It flagged three
  files: `mlxf.f90` (211 single-name lines), `mlxf_array.f90` (105) and `mlxf_ops.f90` (153). `mlxf.f90`'s one
  continued statement (212 names) is repacked to the 120-column limit as one statement per source module of its
  names, in their order (`mlxf_ops` 154, `mlxf_linalg` 13, `mlxf_linalg_matrix` 20, `mlxf_conv` 8 with
  `mlx_conv_spec`, `mlxf_fft` 17 with `MLX_FFT_NORMS`; `keep/phase2/repack_mlxf.py`); the API list's `--check`
  passes unchanged (315 names, same order). The other two are in `PUBLIST_LEDGER` with their counts, because
  Phases 4 and 5 rewrite their public blocks (step 2); the ledger may only shrink and is to be empty after
  Phase 5. Phase 4 deletes `mlxf_ops.f90`'s entry: the file table's row of `scripts/check_rules.py` now names
  Phase 4 too.
- *Planted violations* (`keep/phase2/plants.sh`, a copy of the tree, `keep/phase2/plants/`): (a) the blank lines
  between the bodies of `mlxf_ops_logic_tester.f90`'s abstract interface removed: `check_tree.sh` fails at
  `restyle_fortran.py --check --tree`, and the restyle pass gives back the file byte for byte; (b)
  `mlxf_fft.f90`'s public block opened one name per line: fails at `check_rules.py` ("publist: 2 new
  violation(s)"); (c) a ledgered file packed further than its entry: fails ("151, below the ledger's 153 - lower
  the entry"); (d) restored: passes.
- *The gates* (*measured*): Release from scratch 19.1 s (load 1.37 before, 2.52 after); Debug from scratch; zero
  warnings in both; the fast gate in both (13 of 13); installs; `scripts/check_install.sh` on the Release tree
  passed with the API check (`check_install_release.log`). Unit areas (`units_{release,debug}/`) at Phase 0's
  counts; core 215 in Release (one reuse line `T`) and 214 in Debug (none), both 214 plus the `T` lines. GPU
  devices 1. The digests are not re-run: the phase adds blank lines and regroups a `public` statement, which
  change no code the toys run.

**Decisions taken under delegation.**
1. *`mlxf.f90` is packed by source module* (one `public ::` statement per module the names come from, a defs name
   joining the module it serves), not as one statement with comment lines naming the groups: the file already
   writes its other public names one statement per concern, and the surface rule counts consecutive statements as
   one block.
2. *Rule `publist` covers all Fortran under `src/` and `test/`*, test code included; only the library's three
   files were flagged.
3. *A skill disagreement, proposed, not edited*: `mlxf-modern-fortran`'s SKILL.md says "Do not insert procedure
   separators between interface bodies", which rule 7(a) now reverses. Decision 14 lets this run change the skills'
   paths only; the report proposes the sentence "Separate interface bodies inside an interface block with one
   blank line (the formatter adds it)".

**What it means, in short.** The formatter now writes a blank line between interface bodies and the gate holds the
tree to it; a public block of several lines is packed, checked by a rule whose ledger holds the two files Phases 4
and 5 rewrite. The build, the counts and the public API are unchanged.

### Phase 3, the test tree (2026-11-26, 10:53 to 11:10, M5 Ultra)

Base `96c5c5c` with Phases 0 to 2 in the tree; the rulings file is empty. Logs under `keep/phase3/`.

**Moves** (59, with `mv`; module names unchanged; `keep/phase3/moves.txt`), old path -> new path:

- src/test/mlxf_abi_probe.c -> src/test/framework/mlxf_abi_probe.c
- src/test/mlxf_abi_probe.h -> src/test/framework/mlxf_abi_probe.h
- src/test/mlxf_abi_tester.f90 -> src/test/framework/mlxf_abi_tester.f90
- src/test/mlxf_bench_insert_probe.f90 -> src/test/bench/mlxf_bench_insert_probe.f90
- src/test/mlxf_bench_polar_table.f90 -> src/test/bench/mlxf_bench_polar_table.f90
- src/test/mlxf_bench_projector.f90 -> src/test/bench/mlxf_bench_projector.f90
- src/test/mlxf_bench_recon_pcg.f90 -> src/test/bench/mlxf_bench_recon_pcg.f90
- src/test/mlxf_oracle_dft.f90 -> src/test/oracles/mlxf_oracle_dft.f90
- src/test/mlxf_oracle_gridding.f90 -> src/test/oracles/mlxf_oracle_gridding.f90
- src/test/mlxf_oracle_pcg.f90 -> src/test/oracles/mlxf_oracle_pcg.f90
- src/test/mlxf_oracle_polar_objfun.f90 -> src/test/oracles/mlxf_oracle_polar_objfun.f90
- src/test/mlxf_oracle_polar_shiftmap.f90 -> src/test/oracles/mlxf_oracle_polar_shiftmap.f90
- src/test/mlxf_oracle_polar.f90 -> src/test/oracles/mlxf_oracle_polar.f90
- src/test/mlxf_oracle_pose.f90 -> src/test/oracles/mlxf_oracle_pose.f90
- src/test/mlxf_oracle_projection_tester.f90 -> src/test/oracles/mlxf_oracle_projection_tester.f90
- src/test/mlxf_oracle_projection.f90 -> src/test/oracles/mlxf_oracle_projection.f90
- src/test/mlxf_oracle_recon_fixture.f90 -> src/test/oracles/mlxf_oracle_recon_fixture.f90
- src/test/mlxf_oracle_recon_pcg.f90 -> src/test/oracles/mlxf_oracle_recon_pcg.f90
- src/test/mlxf_polarft_host_fixture.f90 -> src/test/toys/polar/mlxf_polarft_host_fixture.f90
- src/test/mlxf_test_defs.f90 -> src/test/framework/mlxf_test_defs.f90
- src/test/mlxf_test_reduce.f90 -> src/test/framework/mlxf_test_reduce.f90
- src/test/mlxf_test_registry.f90 -> src/test/framework/mlxf_test_registry.f90
- src/test/mlxf_test_utils.f90 -> src/test/framework/mlxf_test_utils.f90
- src/test/mlxf_toy_device_work.f90 -> src/test/toys/mlxf_toy_device_work.f90
- src/test/mlxf_toy_eul_prob_tab_tester.f90 -> src/test/toys/polar/mlxf_toy_eul_prob_tab_tester.f90
- src/test/mlxf_toy_eul_prob_tab.f90 -> src/test/toys/polar/mlxf_toy_eul_prob_tab.f90
- src/test/mlxf_toy_pcg_solver_mlx.f90 -> src/test/toys/recon/mlxf_toy_pcg_solver_mlx.f90
- src/test/mlxf_toy_pcg_solver_tester.f90 -> src/test/toys/recon/mlxf_toy_pcg_solver_tester.f90
- src/test/mlxf_toy_pcg_solver.f90 -> src/test/toys/recon/mlxf_toy_pcg_solver.f90
- src/test/mlxf_toy_polarft_block_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_block_mlx.f90
- src/test/mlxf_toy_polarft_block.f90 -> src/test/toys/polar/mlxf_toy_polarft_block.f90
- src/test/mlxf_toy_polarft_calc_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_calc_tester.f90
- src/test/mlxf_toy_polarft_calc.f90 -> src/test/toys/polar/mlxf_toy_polarft_calc.f90
- src/test/mlxf_toy_polarft_core_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_core_mlx.f90
- src/test/mlxf_toy_polarft_core.f90 -> src/test/toys/polar/mlxf_toy_polarft_core.f90
- src/test/mlxf_toy_polarft_host_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_host_tester.f90
- src/test/mlxf_toy_polarft_memo_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_memo_mlx.f90
- src/test/mlxf_toy_polarft_memo.f90 -> src/test/toys/polar/mlxf_toy_polarft_memo.f90
- src/test/mlxf_toy_polarft_shiftmap_mlx.f90 -> src/test/toys/polar/mlxf_toy_polarft_shiftmap_mlx.f90
- src/test/mlxf_toy_polarft_shiftmap_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_shiftmap_tester.f90
- src/test/mlxf_toy_polarft_shiftmap.f90 -> src/test/toys/polar/mlxf_toy_polarft_shiftmap.f90
- src/test/mlxf_toy_polarft_tail_tester.f90 -> src/test/toys/polar/mlxf_toy_polarft_tail_tester.f90
- src/test/mlxf_toy_polarft_workspace_lifecycle.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_lifecycle.f90
- src/test/mlxf_toy_polarft_workspace_score.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_score.f90
- src/test/mlxf_toy_polarft_workspace_shiftmap.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_shiftmap.f90
- src/test/mlxf_toy_polarft_workspace_tail.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace_tail.f90
- src/test/mlxf_toy_polarft_workspace.f90 -> src/test/toys/polar/mlxf_toy_polarft_workspace.f90
- src/test/mlxf_toy_projector_mlx.f90 -> src/test/toys/projector/mlxf_toy_projector_mlx.f90
- src/test/mlxf_toy_projector_pft_batch_mlx.f90 -> src/test/toys/projector/mlxf_toy_projector_pft_batch_mlx.f90
- src/test/mlxf_toy_projector_pft_batch.f90 -> src/test/toys/projector/mlxf_toy_projector_pft_batch.f90
- src/test/mlxf_toy_projector_tester.f90 -> src/test/toys/projector/mlxf_toy_projector_tester.f90
- src/test/mlxf_toy_projector_workspace.f90 -> src/test/toys/projector/mlxf_toy_projector_workspace.f90
- src/test/mlxf_toy_projector.f90 -> src/test/toys/projector/mlxf_toy_projector.f90
- src/test/mlxf_toy_reconstructor_pcg_mlx.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_mlx.f90
- src/test/mlxf_toy_reconstructor_pcg_tester_solve.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester_solve.f90
- src/test/mlxf_toy_reconstructor_pcg_tester.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_tester.f90
- src/test/mlxf_toy_reconstructor_pcg_workspace.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg_workspace.f90
- src/test/mlxf_toy_reconstructor_pcg.f90 -> src/test/toys/recon/mlxf_toy_reconstructor_pcg.f90
- src/test/mlxf_toy_seam_tester.f90 -> src/test/toys/mlxf_toy_seam_tester.f90

Files changed besides the moves: new `.inf` files `src/test/{framework,oracles,toys,bench}/<dir>.inf` and
`src/test/toys/{polar,projector,recon}/<dir>.inf`; `src/test/test.inf` (names the folders); paths in
`test/CMakeLists.txt` (the ABI probe's two files, a comment), `test/offstate/CMakeLists.txt` (the fixture and the
test definitions by path; a toy's file found by name under `src/test/toys/`), `scripts/check_rules.py`
(`TEST_DEFS`, `NANMAX_HOME`, `TEST_UTILS`, the registry, the state ledger's key, `TOY_DIR` now `src/test/toys/`, the
docstring), `scripts/check_test_registry.py`, `scripts/gen_mlxc_bindings.py` (docstring), `scripts/toy_mirror.txt`
and `scripts/toy_seam.txt` (comments), the C header, C file and tester of the ABI probe (their own paths in comments),
`doc/policies/test_environment_policy.md` (9), `doc/policies/toy_example_policy.md` (1), `CLAUDE.md` (Structure),
`.github/skills/mlxf-modern-fortran/SKILL.md` (2), its `references/testing.md` (2),
`.github/skills/mlxf-binding/SKILL.md` (1), and, added to the file table for this phase, `CONTRIBUTING.md`,
`doc/architecture_principles.md`, `doc/compiler_issues/README.md`, `doc/how2s/how2set_up_dev.md` (2),
`doc/how2s/how2use_from_simple.md` (2); `doc/code_base_map.md` regenerated; this note. `AGENTS.md` names
`src/test/` as a folder only and is unchanged (its row stays in the table, unused).

**Exit items.**
- *Acceptance 6* (*exact*): `src/test/` holds `test.inf` and the folders `framework/` (7 files), `oracles/` (11),
  `toys/` (2, and `polar/` 21, `projector/` 6, `recon/` 8), `bench/` (4); no Fortran or C file at its top level.
  The plan's "13 oracle modules" are 10 modules and a tester (*measured*).
- *Identity with Phase 0* (*exact*): Release from scratch 18.6 s (load 1.40 before, 3.35 after); Debug from scratch;
  zero warnings in both; the fast gate in both (13 of 13); installs. Every unit area at Phase 0's counts
  (`units_{release,debug}/`): core 214 in Release (no reuse line `T`) and 215 in Debug (one), the rest equal. The
  14 identity invocations (`keep/phase0/identity.sh` on the Release build) equal `keep/phase0/identity_base.txt`
  byte for byte (`keep/phase3/identity/identity.txt`). `scripts/check_toy_offstate.sh --exec` passed in Debug and
  Release, and its table equals Phase 0's byte for byte (`offstate.log`, `offstate/exec.table.txt`).
  `scripts/check_install.sh` passed with the API check (`check_install_release.log`).
- *Rules `mirror` and `seam`* pass (part of `check_rules.py` in the static gate) with `TOY_DIR` at
  `src/test/toys/`: every toy file found, every ledger line matched.

**Decisions taken under delegation.**
1. *Six more documents get the moved paths* (`CONTRIBUTING.md`, `doc/architecture_principles.md`,
   `doc/compiler_issues/README.md`, the two how-tos; `AGENTS.md` listed and found clean): they named files under
   `src/test/` that the moves would have left stale; added to the file table first, paths only.
2. *`TOY_DIR` is `src/test/toys/`*, not `src/test/`: the toys' rules then look where the toys are, and the seam
   rule's message names that folder.
3. *The off-state project finds a toy's file by its name under `src/test/toys/`* (one match required, else a
   configure error), so the seam ledger keeps naming stems and a toy may sit in any folder below.
4. *`CLAUDE.md`'s Structure line names the four folders* in place of its words for them; nothing else in it changed.
5. Left as it was: `test_environment_policy.md`'s `src/test/mlxf_kernel_<x>.f90`, a pattern of an earlier naming
   that no move touched (proposed for the record in Phase 7).

**What it means, in short.** The test tree is sorted into its four kinds with each folder described, every path that
named a moved file follows it, and nothing built or run changed: counts, digests, the off-state table and the
public API are Phase 0's.

### Phase 4, `mlxf_ops` (2026-11-26, 11:00 to 11:40, M5 Ultra)

Base `96c5c5c` with Phases 0 to 3 in the tree; the rulings file is empty. Logs and the scripts that did the split
under `keep/phase4/` (`split_ops.py` reads the pre-phase copies in `keep/phase4/orig/` and writes the new files;
`iface_comments.py`; `inventory.py`, `helpers_deps.py`).

**Modules made** (`src/core/ops/`, file lines *exact*): `mlxf_ops_elementwise` (156; 9 public names, 7 generics),
`mlxf_ops_math` (675; 41, 25), `mlxf_ops_logic` (301; 14, 6), `mlxf_ops_shape` (862; 38, 9) with its submodule
`mlxf_ops_shape_calls` (546; the 19 shape helpers), `mlxf_ops_index` (577; 15, 7), `mlxf_ops_reduce` (808; 20, 15),
`mlxf_ops_create` (501; 14, 2), `mlxf_ops_sort` (94; 5, 0). Each of the eight files kept its path and became the
module of its name (a submodule of `mlxf_ops` before); `src/core/ops/mlxf_ops.f90` (1,797 lines) is deleted;
`src/core/ops/mlxf_ops_shape_calls.f90` is new. No file moved. Each module has its generics, one packed public
block, a bare `private`, and its procedures as plain module procedures (the `module function` prefixes dropped,
the parent's interface bodies with them). `mlxf.f90` imports the eight modules, each name from its home, the 315
public names unchanged (the API list's `--check` and compile pass). No other module imported `mlxf_ops`.

**Helpers moved in** (from `mlxf_array_operations.f90`, deleted there, their interfaces and public names deleted
from `mlxf_array.f90`; private in their new module, plain procedures): `mlxf_ops_shape_calls` 19 (`take`, `slice`,
`concat`, `range`, `int3`, `trace`, `roll`, `unflatten`, `vector2`, `strided` with its plain companion
`strided_reach`, `count`, `vector_list`, `split`, `split_sections`, `unstack`, `unstack_dim`, `pad`, `pad_width`,
`slice_dynamic`; their interfaces in `mlxf_ops_shape`, each under the comment of the C signature it serves);
`mlxf_ops_index` 8 (`gather`, `gather_single`, `scatter`, `put`, `ternary_vector`, `text`, `slice_update`,
`unique`); `mlxf_ops_reduce` 8 (`reduce`, `scan`, `var_all`, `var`, `var_dims`, `scan_all`, `scan_plain`,
`scan_plain_all`); `mlxf_ops_create` 8 (`full`, `binary_int`, `window`, `identity`, `eye`, `linspace`,
`linspace_endpoint`, `meshgrid`); `mlxf_ops_logic` 2 (`close`, `compare`); `mlxf_ops_math` 2 (`nan`,
`binary_vector`) (each `mlxf_<name>_op`). 47 helpers in all; `mlxf_array_operations.f90` went from 2,410 to 1,184
lines, `mlxf_array.f90` from 3,211 (after Phase 2) to 2,813.

**`mlx_slice`** (Phase 0's one generic of two concerns): defined in `mlxf_ops_shape`; `slice_dynamic` and its
helper `mlxf_slice_dynamic_op` moved there from the index concern, as Phase 0 recommended.

**What `mlxf_array` exports for now** (Phase 5 relocates it): the moved helpers reach the type's internals the way
the submodules did, so `mlxf_array` makes public, beside its existing names, `adopt`, `check_dim`, `vector_of`,
`slice_bounds` (a plain procedure of `mlxf_array_operations` until now, made a module procedure with its interface
in `mlxf_array.f90`: the shape and index helpers both call it) and the 47 abstract interfaces of the moved
helpers' C signature classes. None is re-exported by `mlxf`. `axis_of` and `axes_of`, the two procedures the
concerns shared inside `mlxf_ops`, are public from `mlxf_ops_shape` (the index and sort modules import them).

**Import edges between the concerns** (*measured*, `inventory.txt`): `mlxf_ops_logic` and `mlxf_ops_reduce`
import `mlx_astype` from `mlxf_ops_elementwise`; `mlxf_ops_reduce` imports `mlx_zeros` and `mlxf_ops_index`,
`mlxf_ops_sort` import `axis_of`/`axes_of` from `mlxf_ops_shape`; no cycle. Every module's imports are the names
its own code uses (picked by the script from the code's identifiers, then the compiler's verdict); three
imports of `mlxf_array.f90` (`mlxf_range_spec`, `mlxf_close_spec`, `mlxf_nan_spec`) and one of
`mlxf_array_operations.f90` (`c_null_ptr`) were left unused by the move and are deleted.

**Rules and ledgers.** `PUBLIST_LEDGER`: the `mlxf_ops.f90` entry deleted (the file is gone); `mlxf_array.f90`'s
lowered from 105 to 58 (the moved helpers' lines left its public block). `src/core/ops/ops.inf` names the eight
concerns; `doc/code_base_map.md` regenerated. Dead code (decision 13): the Debug build (`-Wall -Wunused` with
`-Werror`) reports no unused procedure; nothing deleted besides the moves.

**Exit items** (the final run, `keep/phase4/all.log`; the first, before the three import deletions, gave the same:
`all_run1.log`).
- *No file above 1,000 lines in `src/core/ops/`* (*exact*): the largest library file is `mlxf_ops_shape.f90`, 862.
- *Identity with Phase 0* (*exact*): Release from scratch 18.7 s (load 1.92 before, 2.54 after); Debug from
  scratch; zero warnings in both; the fast gate in both (13 of 13); installs. Every unit area at Phase 0's counts:
  ops 2,462, the rest equal; core 214 in Release (no reuse line `T`) and 216 in Debug (two), both 214 plus the `T`
  lines. The 14 identity invocations equal `keep/phase0/identity_base.txt` byte for byte
  (`keep/phase4/identity/identity.txt`); `check_toy_offstate.sh --exec` passed and its table equals Phase 0's.
- *The API list* (*exact*): `scripts/check_install.sh` passed, the program of 315 names compiled against the
  installed module (`check_install_release.log`).
- `scripts/check_tree.sh` passes (rules `surface`, `entry`, `publist`, `inf`, the formatters).

**Decisions taken under delegation.**
1. *The helpers' dependencies stay in `mlxf_array` for one phase, exported* (`adopt`, `check_dim`, `vector_of`,
   `slice_bounds`, 47 abstract interfaces): the plan moves the helpers in this phase and their shared
   dependencies in Phase 5 (`mlxf_calls`, `mlxf_c_signatures`, `mlxf_adopt`); exporting them under their present
   names keeps this phase a move, and Phase 5 changes only the imports.
2. *`mlxf_ops_shape` keeps its helpers in a submodule `mlxf_ops_shape_calls`*: wrappers and helpers together would
   be about 1,220 lines (*derived*); the wrappers stay in the module (they call the helpers, and a submodule may not
   call a private plain procedure of its module), the helpers' interfaces sit in the module.
3. *`axis_of` and `axes_of` keep their names*, public from `mlxf_ops_shape` and not re-exported: they are the shape
   concern's dimension translation, and the other two concerns import them by name.
4. *Line width*: `format_use_blocks.py` aligns the `only:` column after the packing, which leaves nine use lines at
   121 columns (*measured*: one in `mlxf.f90`, eight in the new modules' use blocks); no rule checks the width and the tree already has longer lines;
   left as the formatter writes them.

**What it means, in short.** `mlxf_ops` is eight modules, one per concern, each with its own generics and public
block; 47 helpers live with their only users. Nothing a user sees or a test measures changed.

### Phase 5, `mlxf_array` (2026-11-26, 11:15 to 12:50, M5 Ultra)

Base `96c5c5c` with Phases 0 to 4 in the tree; the rulings file is empty. Logs and the scripts that did the work
under `keep/phase5/` (`patch_gen.py`, `match_signatures.py`, `step1.py`, `step2.py`, `step3.py`,
`fix_imports.py`, `patch_size.py`, `plants.sh`; the pre-phase copies in `orig/`, the tree after steps 1 and 2 in
`after_step1/`, `after_step2/`). Each of steps 1 to 3 ended with a clean Debug build before the next began
(`build_debug_s{1,2,3}.log`).

**Moves** (`mv`, `keep/phase5/moves.txt`), old path -> new path:
- `src/core/array/mlxf_array_transfer.f90` -> `src/core/array/mlxf_transfer_copy.f90`
- `src/core/array/mlxf_array_borrow.f90` -> `src/core/array/mlxf_transfer_borrow.f90`
- `src/core/array/mlxf_array_random.f90` -> `src/core/random/mlxf_random_calls.f90`
- `src/core/array/mlxf_array_fast.f90` -> `src/core/fast/mlxf_fast_calls.f90`
- `src/core/array/mlxf_array_io.f90` -> `src/core/io/mlxf_io_calls.f90`
- `src/core/array/mlxf_array_distributed.f90` -> `src/core/distributed/mlxf_distributed_calls.f90`

**New files:** `scripts/mlxc_signatures.txt`; `src/core/array/mlxf_calls.f90`, `mlxf_calls_elementwise.f90`,
`mlxf_calls_shaped.f90`, `mlxf_calls_checks.f90`; `src/core/array/mlxf_transfer.f90`; and, generated at build
time, `build/gen/mlxf_c_signatures.f90`. **Deleted:** `src/core/array/mlxf_array_operations.f90` (emptied).

**Step 1, the signatures** (decision 2). `scripts/mlxc_signatures.txt` lists the 98 classes (*exact*), each with
an mlx-c function of its signature; `keep/phase5/match_signatures.py` compared every hand-written abstract
interface with the generated interface of every mlx-c function (dummy kinds, types, attributes, arrays, result;
names ignored) and found a match for all 98 (55 classes with one function, the largest with 12;
`signatures_matched.txt`), preferring a function the call sites pass. `scripts/gen_mlxc_bindings.py` writes
`mlxf_c_signatures` from it: per line the abstract interface with the characteristics of the named prototype
(`bind(c)` without a label), under the comment of the C signature written from the header; an unknown or
skipped function is a generator error. `src/CMakeLists.txt` makes the generation depend on the ledger. **No
class needed the fallback file** (`mlxf_signatures_hand.f90` is not created). The 98 hand interfaces (about 1,050
lines) left `mlxf_array.f90`; every module imports its classes from `mlxf_c_signatures`.

**Step 2, the helpers** (decision 3). `mlxf_calls` holds the 16 shared helpers of Phase 0's table and the checks
they share, its interfaces each under the comment of the C signature it serves; the bodies are in three
submodules: `mlxf_calls_elementwise` (`mlxf_unary`, `mlxf_binary`, `mlxf_weak_scalar`, 91 lines),
`mlxf_calls_shaped` (`mlxf_dtype_op`, `mlxf_int_op`, `mlxf_vector_op`, `mlxf_ternary_op`, `mlxf_zeros_op`,
`mlxf_reduce_all_op`, `mlxf_reduce_dims_op`, `mlxf_int2_op`, `mlxf_list_op`, 211) and `mlxf_calls_checks`
(`mlxf_check_dtype`, `mlxf_axes_of`, `mlxf_zero_based`, `mlxf_one_based`, `mlxf_check_dim`, `mlxf_slice_bounds`,
`mlxf_cpu_stream`, `mlxf_optional_handle`, 140). The one-family helpers moved into their family modules as
private plain procedures: `mlxf_fft` 3 (`fft`, `fftn`, `freq`, with `check_fft_norm`), `mlxf_linalg` 7
(`gather_mm`, `masked_mm`, `binary_axis`, `optional_float`, `addmm`, `einsum`, `tensordot`),
`mlxf_linalg_matrix` 11 (`cpu_unary`, `cpu_binary`, `cpu_flag`, `cpu_compare`, `cpu_pair`, `cpu_pair_text`,
`cpu_text`, `cpu_unstack`, `cpu_svd`, `norm`, `norm_text`), `mlxf_conv` 7 (the convolutions, with
`conv_operands` and `conv_list`). The operators that `mlxf_array_operations.f90` still held (unary plus, the five
powers, `.eqv.`, `.neqv.`) joined the type's other operators in `mlxf_array_elementwise`, and the emptied file
was deleted. The home of each of Phase 0's 117 names, both phases together (*exact*): 47 in the `mlxf_ops_*`
modules (Phase 4), 28 in the four modules above, 22 in the family submodules (step 3: random 11, fast 5, io 3,
distributed 3), 17 in `mlxf_calls` (the table's 16 shared and `mlxf_cpu_stream`, which `mlxf_io`'s wrapper
exported), and `mlxf_handle`, `mlxf_vector_import`, `mlxf_vector_export` stay with the type.

**Step 3, transfer and families** (decisions 4, 5, 1). `mlxf_transfer` holds the generics `mlx_from`, `mlx_to`,
`mlx_to_alloc`, `mlx_item`, `mlx_view`, `mlx_alloc` with their specifics' interfaces, `MAX_RANK`, and the two
procedures its submodules share (`data_pointer`, `itemsize`); its submodules are the former transfer and borrow
files. `mlxf.f90` imports the six generics from `mlxf_transfer` (the API list unchanged). The four family
submodules are submodules of `mlxf_random`, `mlxf_fast`, `mlxf_io`, `mlxf_distributed`, their helpers'
interfaces in those modules; `mlxf_io`'s one-line wrapper `mlxf_cpu_stream` of the private `cpu_stream` was a
second copy and is gone (the procedure is `mlxf_cpu_stream` in `mlxf_calls`). `adopt` is `mlxf_adopt`, public
from `mlxf_array` and not re-exported.

**Private access** (Phase 0 item 2: three uses outside the lifetime submodule, `c_associated(a%h%ctx)` and
`c_associated(a(i)%h%ctx)`, in `optional_handle` and two linalg helpers) is replaced by `mlxf_is_empty(a)`, a
new library-internal pure function of the lifetime submodule (`.not. c_associated(a%h%ctx)`), public from
`mlxf_array`, not from `mlxf`. Decision 5's suggestion (`mlx_is_live` or `mlxf_handle`) would have changed the
result on a stale copy (refused today, silently empty then), so the identical test was kept (decision 1 under
delegation below).

**Library-internal renames** (no `mlxf` name): `adopt` -> `mlxf_adopt`, `check_dim` -> `mlxf_check_dim`,
`slice_bounds` -> `mlxf_slice_bounds`, `cpu_stream` -> `mlxf_cpu_stream`, `optional_handle` ->
`mlxf_optional_handle`, `vector_of` -> `mlxf_vector_of` (public now that other modules call them: the house
names library-internal public procedures `mlxf_<x>`).

**Rule `size`** (decision 8, step 4): `scripts/check_rules.py` fails a library module or submodule file (`src/core`,
`src/defs`, testers excepted) above `MAX_LINES = 1000`, with `SIZE_LEDGER` for exceptions (a ratchet). The
ledger is empty: the largest library file is `mlxf_transfer_copy.f90`, 982 lines (*exact*), then
`mlxf_ops_shape.f90` 865 and `mlxf_transfer_borrow.f90` 810. `PUBLIST_LEDGER` is empty too (`mlxf_array.f90`'s
public block lost its single-name lines with the helpers). The callback table of rule `cbsig` names the borrow
file at its new path.

**`mlxf_array.f90`: 598 lines** (*exact*; 3,211 after Phase 2, 2,813 after Phase 4): the type and its bindings,
the `exp`, `mlx_eval`, `mlx_async_eval`, `mlx_synchronize` generics, the interfaces of the lifetime, evaluation,
operator and closure-vector procedures, and one packed import line per module.

**Imports.** Every touched file's module-level `use` statements were rewritten by `keep/phase5/fix_imports.py` to
the names its own code uses (for a parent, a name a submodule uses through host association is kept; a submodule
imports nothing its ancestors import), then by the two formatters.

**Planted violations** (`keep/phase5/plants.sh`, a copy of the tree, `keep/phase5/plants/`): (a) 40 lines added
to `mlxf_transfer_copy.f90` (1,022): the static gate fails at rule `size`; (b) a ledger line naming
`mlx_no_such_function`: the generator stops with exit 2 and names the line; (c) a ledger line giving
`mlxc_take_op` the signature of `mlx_add`: the Debug build fails where helpers of that class are handed their
functions ("Interface mismatch in dummy procedure 'f'"); (d) restored: the gate passes.

**Dead code** (decision 13): the Debug build (`-Wall -Wunused`, `-Werror`) reports no unused procedure; the one
second copy found (`mlxf_io`'s `mlxf_cpu_stream` wrapper) is deleted.

**Skills.** `.github/skills/mlxf-binding/SKILL.md`: the deleted file's name `mlxf_array_operations` becomes
"`mlxf_calls` and the family modules", `adopt` becomes `mlxf_adopt` (names only, decision 14). Its paragraph on
where a new C signature class goes (an abstract interface written by hand in the `mlxf_array` family) and
`CLAUDE.md`'s description of `array/` no longer match the code; the report proposes their new text.

**Exit items** (`keep/phase5/all.log`; the first full run, `all_run1_failed.log`, stopped at the Release build:
`-Wfunction-elimination` refused `mlxf_is_empty`, then impure, inside an `.or.` that the optimiser may cut short;
the function is `pure`, as it reads one component, and the second run is the one below).
- *Acceptance 1* (*exact*): `scripts/check_install.sh` passed, the 315 names compiled against the installed module.
- *Acceptance 2* (*exact*): Release from scratch and Debug from scratch, zero warnings, the fast gate in both (13 of
  13); every unit area at Phase 0's counts (core 216 in both, two reuse lines `T` each: 214 plus two); the 14
  identity invocations equal `keep/phase0/identity_base.txt` byte for byte (`keep/phase5/identity/identity.txt`);
  `check_toy_offstate.sh --exec` passed and its table equals Phase 0's.
- *Acceptance 3* (*exact*): no library file above 1,000 lines, `SIZE_LEDGER` empty; `mlxf_array.f90` 598 lines.
- *Acceptance 4*: rule 7(a) holds tree-wide (`restyle_fortran.py --check --tree`), `PUBLIST_LEDGER` empty.
- *Acceptance 7* (*measured*): the Release clean build 18.7 s (load 3.58 before, 4.07 after), against Phase 0's
  19.0 s and the bound of 26.1 s.
- *The generated signatures*: 98 of 98 classes from the ledger, none by hand.

**Decisions taken under delegation.**
1. *`mlxf_is_empty` in place of decision 5's `mlx_is_live`/`mlxf_handle`*: both would change what a stale operand
   does where mlx-c takes a null array (today it stops; with `mlx_is_live` it would pass as absent); the contract
   forbids a changed result, so the test the code made stays, behind a pure internal function of the lifetime
   submodule.
2. *Submodule names `<module>_<part>`*: the transfer and borrow files are renamed `mlxf_transfer_copy` and
   `mlxf_transfer_borrow` (the plan kept their old names), the family submodules `mlxf_<family>_calls`, as
   `mlxf_ops_shape_calls` in Phase 4; added to the file table first.
3. *`mlxf_calls` as a module with three submodules*: the module holds the interfaces and the public block, the
   submodules the bodies by group (elementwise classes, shaped classes, checks), so that editing a helper
   recompiles no user of `mlxf_calls`.
4. *Internal names*: the procedures that became public between modules took the `mlxf_` prefix (six renames
   above); none is a name of `mlxf`.
5. *The one-family helpers are private plain procedures of their family modules* (as in Phase 4), except where
   the family keeps a submodule (random, fast, io, distributed), whose helpers stay module procedures with their
   interfaces in the family module.
6. *Two files added to the file table in this phase*: `src/CMakeLists.txt` (the generation depends on the ledger)
   and `src/core/array/mlxf_array_tester.f90` (it imported `mlxf_unary` from `mlxf_array`).

**What it means, in short.** `mlxf_array` is the type and what needs its inside, in 598 lines; the 98 C signature
classes come from the headers through a ledger, and a header that changes a class fails the build; the shared
helpers have a module of their own and every other helper lives with its only user; data movement is its own
module. Nothing a user sees or a test measures changed.

### Phase 6, linear algebra against BLAS (2026-11-26, 11:30 to 11:55, M5 Ultra)

Base `96c5c5c` with Phases 0 to 5 in the tree; the rulings file is empty. Logs under `keep/phase6/`. No move.

Files changed: `doc/how2s/how2replace_blas.md` (new), `src/test/bench/mlxf_bench_blas.f90` (new),
`src/test/framework/mlxf_test_registry.f90` (the bench's row in `BENCHES` and `run_bench`),
`src/test/framework/mlxf_test_defs.f90` (`BLAS_POLAR_NB`, `_NR`, `_N2K`, `_N1`: SIMPLE's polar block product,
restated), `test/CMakeLists.txt` (added to the file table for this phase: on macOS `find_package(BLAS)` with
`BLA_VENDOR Apple`, and when found `-framework Accelerate` linked to `mlxf_test_exec` and `MLXF_HAVE_BLAS`
defined; elsewhere the bench's host route is Fortran's `matmul`), `doc/code_base_map.md`, this note. Nothing
under `src/core` or `src/defs` changed.

**Exit items.**
- *Decision 12(a), the table* (*exact*): `doc/how2s/how2replace_blas.md` has one row per BLAS or LAPACK routine
  SIMPLE calls at `28c753993` (19 routines; call sites counted again by `git grep` on call statements, which gives
  smaller numbers than section 2's text search: `dcopy` 19, `ddot` 14, `sgemm` 11, `daxpy` 6, `cgemm`, `dscal`,
  `dnrm2` 3, `ssyev`, `dsyev`, `sgesvd`, `dgesvd`, `sgetri`, `dgetri`, `dgemv` 2, `sgemv`, `ssyrk`, `sgetrf`,
  `dgetrf`, `cdotc_sub` 1). Each row names the `mlxf` procedure, read in its wrapper, and the existing test that
  checks it; where the view transposes (`'T'`, `'C'`), the transpose and the product are each tested
  (`test_reordering`, `test_matmul`, `test_addmm`) and their composition is checked by the bench against
  `cblas_cgemm('C', 'N')`. What MLX cannot do: float64 on the GPU, any factorisation on the GPU, an in-place
  update. Float64 on the CPU device was probed (`keep/phase6/f64_probe/f64_probe.log`, *measured*: `mlx_inv`,
  `mlx_eigvalsh`, `mlx_svd`, `mlx_lu_factor`, `matmul`, `mlx_inner`, `norm2` within 2.2e-16 to 7.1e-15 of Fortran
  in double precision); no unit test covers it, and the table says so.
- *Decision 12(b), the bench* (*measured*, one run, `keep/phase6/bench/bench_blas.log` and `bench_blas.tsv`;
  Release build, one process, both devices, load 3.65 before and 3.31 after, nothing else of the run's running):
  the first n at which MLX beats Accelerate, CPU device resident / transfer, GPU resident / transfer: `sgemm`
  2,048 / none up to 4,096, 1,024 / 2,048; `cgemm` 256 / 256, 512 / 512. The polar block product (183 x 16 x 32
  x 122): Accelerate's loop 1.16 ms, the GPU 0.22 ms resident and 0.30 ms with transfer (5.3 and 3.9 times
  faster), MLX's CPU 3.7 and 2.6 times. MLX's results within a relative 6.1e-6 of Accelerate's. A smoke run to
  n = 128 on the Debug build came first (`keep/phase6/smoke/`).
- *The library unchanged* (*exact*): no file under `src/core` or `src/defs` changed in this phase.
- *The gates* (*measured*, `keep/phase6/all.log`): Release from scratch 18.8 s (load 1.81 before, 2.71 after),
  Debug from scratch, zero warnings in both (the first link of Accelerate as a framework path added a C-only `-F`
  option to every Fortran compile, a warning; linked as `-framework Accelerate` it adds none); the fast gate in
  both (13 of 13); every unit area at Phase 0's counts (core 214 in Release, no reuse line `T`; 215 in Debug, one);
  the 14 identity invocations equal `keep/phase0/identity_base.txt`; `check_toy_offstate.sh --exec` passed, its
  table equal to Phase 0's; `scripts/check_install.sh` passed (315 names); the static gate passes.

**Decisions taken under delegation.**
1. *CBLAS through `bind(c)` interfaces in the bench*: `cblas_sgemm` and `cblas_cgemm` take their sizes by value,
   so their interfaces are C's; the Fortran `sgemm` would need a 13-argument interface the rule `arity` refuses.
   The interfaces live in the bench (test code) under `#ifdef MLXF_HAVE_BLAS`; rule `cbind` covers `mlx_` names only.
2. *Accelerate on macOS only*: elsewhere the test executable links no BLAS (a CPU-only CI leg is unchanged) and the
   bench compares with Fortran's `matmul`, which the row's route column names.
3. *SIMPLE's polar block shape* is the one call site the bench restates (its geometry from the M5 cases, `pftsz`
   182, k 2 to 62); the other call sites take sizes from data (`sgemm` of the flexible-fitting and learning code)
   and are covered by the square sweep.
4. *One run of the bench*, not two: decision 12(b) asks for the crossover, reported, not a floor; the run is
   recorded with its load.

**Ruling R1 applied** (2026-11-26, `spec/rulings.md`): the phase's end was refused once because the file table did
not assign `doc/code_base_map.md` to Phase 6, while the new bench file regenerated it. The maintainer ruled it an
omission of the table: the map's row now lists Phases 1, 3, 4, 5, 6 and 7 (edited by the controller), and Phase 6's
work stands. On resuming, the map was found current (`scripts/check_tree.sh` passes, its `--check` included) and no
source had changed since the gates above (the bench file was last written before the gate run), so the gates stand.

**What it means, in short.** Everything SIMPLE asks of BLAS and LAPACK has an `mlxf` call, in single precision on
either device and in double precision on the CPU. A single matrix product pays on the GPU only above n of about
1,000 to 2,000 against Accelerate; a batch of small products, SIMPLE's polar block, gains four to five times at
once. Whether a BLAS-shaped `mlx_gemm` enters the library stays the maintainer's (decision 12).

### Phase 7, the record (2026-11-26, 11:42 to 12:20, M5 Ultra)

Base `96c5c5c` with Phases 0 to 6 in the tree; ruling R1 in force. Logs under `keep/phase7/`. No move.

Files changed: `doc/policies/compile_time_policy.md` (the module map of the library), `doc/policies/test_environment_policy.md`
(the test tree's four folders; `bench_blas`; the toys' path), `doc/implementation_notes/planned/mlxf_roadmap.md`
(rank 2d delivered), `doc/implementation_notes/README.md` (the index), `doc/history/2026-11.md` (the entry),
`README.md` (the layout), `scripts/generate_codeoverview.py` (below; added to the file table for this phase), this
note, and `doc/implementation_notes/completed/mlxf_refactor_report.md` (new, the report).

**Exit items** (*measured* unless marked; `keep/phase7/all.log`):
- *The last-phase gates*: Release from scratch 18.8 s (load 1.87 before, 3.19 after; Phase 0: 19.0 s, -1 %, the
  bound 26.1 s) and Debug from scratch, zero warnings in both; the fast gate in both, then the Release fast gate 10
  times of 10 (`gate10_*.log`); every unit area at Phase 0's counts (core 216 in both, two reuse lines `T` each);
  the 14 identity invocations equal `keep/phase0/identity_base.txt` byte for byte; `scripts/check_toy_offstate.sh
  --exec` passed, its table equal to Phase 0's; `scripts/check_install.sh` passed (315 names);
  `scripts/check_embed.sh` passed; `scripts/release_gate.sh --allow-dirty` passed in 78 s, Debug and Release, no
  skip, one GPU device opened in each (`release_gate.log`, `release_gate_96c5c5c-dirty.log`).
- *The release gate's first run failed* (`release_gate_run1.log`, `release_gate_96c5c5c-dirty_run1.log`): the
  static gate of the exported tree found `doc/code_base_map.md` "out of date". The gate exports the tree into
  `build_release_gate/src`, an ignored directory of the checkout; `generate_codeoverview.py` asked the version
  control about the export's directories, which answered for the outer checkout (ignored, untracked), and the map
  came out empty. A defect of the Phase 1 adaptation (XEMA's script has the same blind spot): the script now asks
  only when the root is the top of a checkout (`in_checkout`), and otherwise maps every directory, as for a tree
  without version control. The checkout's map is unchanged (`--check` passes); the export's passes; the second
  run of the gate passed.
- *Acceptance 9* (*exact*): every new rule was shown to fail on a planted violation, then removed: the API list
  (Phase 0), the `.inf` check and the map's `--check` (Phase 1), rule 7(a) and rule `publist` with its ratchet
  (Phase 2), rule `size` and the signature ledger's unknown and wrong functions (Phase 5).
- *Acceptance 10*: the report lists every move, every module made, every helper's home, the deleted procedures
  and files, and ends with the commit message.
- *The record*: the compile-time policy holds the module map, the test policy the tree, the roadmap, the index and
  the history the delivery, `README.md` the layout.
- The working tree's changes are paths of the file table (with the rows added in Phases 3, 5, 6 and 7 and by R1).

**Decisions taken under delegation.**
1. *The map generator's fix* is in this phase, under the last-phase gate it made fail; the file table's row of the
   script gained Phase 7 first.
2. *The plan stays in `planned/`* until the maintainer's read, as the index says of the other delivered plans.

**What it means, in short.** The run is complete: every gate of the last phase passes, the release gate included,
with every count, digest and table of the base unchanged, and the record and the report written.
