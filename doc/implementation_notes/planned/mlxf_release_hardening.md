# Release hardening: the installed package under test (run `mlxf_release_hardening`, on the M5 Ultra)

Status, 2026-11-25: planned and ruled (Hans: "Yes, all seven", on decisions 6, 9, 12, 13, 18, 22 and 25 as
recommended); runs after K2. Decision 13 is the maintainer's to do: `brew install pkgconf gcc@14` before launch. The roadmap's rank 2b (Hans, 2026-11-25: "Yes, plan it"). Base: the commit that holds K2's
result, the review's release fixes and this note (the maintainer commits them; the run pins the hash in Phase 0
and records it). The code this note was checked against is `c6ea867` with the working tree of 2026-11-25: the
outside review's fixes and those of Codex's quality review (`completed/mlxf_quality_review.md`, R1 to R5: the
NaN-safe reduction `nan_maxval` and rule `nanmax`, rule `cmakeroot`, `scripts/check_embed.sh` in the release gate,
the install check's resolved paths). MLX is read at `v0.32.4` (`~/src/mlx`, by `git show`)
and mlx-c at `v0.8.0` (`~/src/mlx-c`). Machine: the M5 Ultra only (arun host `local`; 30 cores, 103.1 GB,
macOS 27.2.1, GNU Fortran 16.2.0, CMake 4.5.1, Homebrew mlx 0.32.4 and mlx-c 0.8.0, Python 3.9.6). Runs after
K1, K8 and K2 (roadmap decision 7), never beside them: K1 and K2 edit `test/CMakeLists.txt`,
`src/test/mlxf_test_registry.f90` and the two policies this plan edits. Supersedes: none. Depends on: the
review's release fixes (validated: yes, the history entry of 2026-11-25); `scripts/release_gate.sh` (validated:
passed on the M2 Ultra, never run on the M5); `scripts/check_install.sh` (validated: passed on an M3 Pro, never
on the M5, and it cannot run there today, see section 2).

## 1. Why

An outside review of `c6ea867` (source level, on Linux without Metal) found that what a release gate proves is
not what a user receives. The gate builds the checkout in place, so an untracked source file that CMake's glob
picks up is tested and not released; it never installs the package or links an outside program; the installed
package config checks the compiler but not the mlx-c version its frozen `bind(c)` layer was generated from;
pull requests get no numerical feedback, because the hosted macOS runners open no Metal device and every device
test skips; a user meets the Fortran/MLX differences (integer `/` is true division, `matmul` of two integers
stops, weak scalars) only in a 752-line contract; and the name ledger of 673 interfaces says nothing about the
ABI of a call. The review's five release fixes are in the working tree; this plan takes the other six items.
**Release criterion:** from a clean tagged source tree, an outside program installs and links the library
without editor side effects, gets the documented dtype and failure behaviour, and passes the installed-consumer
test on a real Apple-silicon GPU.

## 2. Contract

- **What stays identical.** The library's arithmetic and every existing suite: per area and per device the
  check counts of Phase 0, on the Metal build, after every phase. The generated layer for mlx-c's headers is
  byte-identical after the generator change of Phase 4 (sha256 of `build/gen/mlxf_c_*.f90`, taken in Phase 0).
- **The one public addition** is `mlx_metal_is_available()` (decision 9). No other public name changes.
- **Off-state invariant.** A build from the checkout with the compile scripts behaves as today: same options,
  same defaults (`FORTLS` included), same fast gate of 9 CTest entries. The release gate, the consumer check and
  the CPU-only build are separate entry points that a developer build never runs.
- **The library reads no environment variable;** the consumer and the examples take command arguments; CI
  scripts may read the runner's environment.
- **One library target;** the ABI probe's C object belongs to `mlxf_test_exec`, never to `mlxf`.
- **FORTLS is the maintainer's open decision** (ruled "stays on" at the Copilot review; raised again by this
  review). This plan does not touch the default and is independent of it: every gate, CI job and documented
  downstream command passes `-DFORTLS=OFF` explicitly (decision 3), which is correct under either outcome.

### What the check found (2026-11-25)

- **The release gate builds the checkout in place** (`scripts/release_gate.sh`, lines 36-60 at `c6ea867`): it
  refuses modified tracked files but reads `git status --untracked-files=no`, while `src/CMakeLists.txt` globs
  `*.[Ff]90` with `CONFIGURE_DEPENDS`. The static gate only warns about untracked sources
  (`scripts/check_tree.sh`, last block). It passes `-DFORTLS=OFF` (line 60) and never calls
  `scripts/check_install.sh`.
- **A snapshot loses mlx-c's in-tree hint.** `cmake/Dependencies.cmake` searches `HINTS
  "${PROJECT_SOURCE_DIR}/.deps/install"`; a build of a `git archive` export has no `.deps/` and would silently
  take Homebrew's mlx-c on a machine that uses `scripts/build_mlx_deps.sh`. The M5 has no `.deps/`.
- **The consumer check** (`scripts/check_install.sh`, 107 lines) installs an existing build, builds
  `test/consumer/` outside the tree, refuses an edited compiler version, proves `mlxf_array` and `mlxf_c_array`
  unimportable, and links through pkg-config. It configures no producer, so `FORTLS` is whatever the caller
  built with. **It needs `pkg-config`, which the M5 does not have** (`command -v pkg-config pkgconf` finds
  nothing): it exits 2 at its prerequisite check. Its recorded passes are from the M3 Pro
  (`completed/mlxf_m5_preparation_report.md`). The consumer program stops unless a GPU is present
  (`test/consumer/mlxf_consumer.f90`, line 12).
- **The package config** (`cmake/mlxfConfig.cmake.in`) checks the compiler ID and version and that `mlxc` is a
  shared library; its message names the mlx-c version ("built with @MLXC_VERSION@") but nothing compares it.
  mlx-c's own version file is `SameMajorVersion`, so at 0.x every 0.y satisfies `find_package(MLXC 0.8)`.
  mlx-c has no run-time query of its own version (`mlx_version` returns MLX's), so the check can only be made at
  configure time. `cmake/mlxf.pc.in` records the compiler but not mlx-c.
- **A Metal build of MLX cannot allocate on the CPU device without a GPU.** In MLX v0.32.4 the one allocator of
  a Metal build is `metal::allocator()`, constructed from `metal::device(Device::gpu)`
  (`mlx/backend/metal/allocator.cpp`); `gpu::device_count()` is that call wrapped in a `try`
  (`mlx/backend/metal/device_info.cpp`). A build with `-DMLX_BUILD_METAL=OFF` links `no_metal.cpp`
  (`metal::is_available()` false) and `backend/no_gpu` (a `CommonAllocator` on the heap, `device_count()` 0), and
  keeps `fast::metal_kernel` (`backend/common/metal_kernel.cpp`), which mlx-c's `fast.cpp` needs. Homebrew's
  `mlx` formula builds with Metal (the default `MLX_BUILD_METAL=ON`, the `metal-cpp` resource, `depends_on
  xcode`), so **Homebrew's mlx cannot run the CPU oracles on a runner without Metal**; a CPU-only MLX must be
  built from source.
- **The library already tells the two cases apart; the test code does not.** `mlxf_enter`
  (`src/core/runtime/mlxf_device.f90`) sets `WITHOUT_DEVICE` only when Metal is compiled in and the GPU count is
  0; a CPU-only MLX allocates. But `test_devices` (`src/test/mlxf_test_utils.f90`, 26 testers, 29 calls),
  the guard gate of `test/mlxf_test_exec.f90` (line 122) and the consumer skip or stop on a GPU count of 0
  alone. `mlx_metal_is_available` is a `plumbing` line of the parity ledger.
- **The hosted CI** (`.github/workflows/ci.yml`, 46 lines): `macos-latest`, Homebrew `gcc cmake mlx-c`, the
  compile scripts with `-DMLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON` and **without `-DFORTLS=OFF`** (the runner
  pip-installs fortls on every run), device tests skipped and counted.
- **GNU Fortran versions advertised:** "14 or newer" (`README.md`, `doc/how2s/how2use_from_simple.md`), floor
  14.0 (`cmake/CompilerConfig.cmake`), 14.2 for auto-detection (`cmake/AutoDetectGCC.cmake`). GCC 14's first
  release is 14.1; Homebrew offers `gcc@14` 14.4.0 and `gcc@15` 15.3.0 (bottled). Only 16.2.0 is installed.
- **The generated layer** (`build/gen/` of the M5's last build, mlx-c 0.8.0): 673 interfaces in 29 dummy
  classes and 6 result classes (type and passing mode; counted by a scratch script over the interfaces, *exact*):

  | Class | Interfaces | Called by the library |
  | --- | --- | --- |
  | handle struct (`{void* ctx}`) by value / by reference / array / as result | 566 / 426 / 9 / 70 | 353 / 304 / 2 / 18 |
  | `int` by value / reference / `const int*` | 157 / 10 / 84 | 119 / 2 / 64 |
  | `size_t` by value / reference / as result | 104 / 9 / 10 | 67 / 6 / 3 |
  | `bool` by value / reference / as result | 92 / 13 / 3 | 75 / 4 / **0** |
  | `float`, `double` by value | 17, 12 | 5, 9 |
  | `mlx_optional_int` / `_float` / `_dtype` by value | 6 / 4 / 5 | **0** / 2 / 4 |
  | function pointer (`c_funptr`) by value | 17 | 3 |
  | `void*` by value / `void**`, `char**` by reference / pointer result | 14 / 11 / 15 | 4 / 1 / 10 |
  | `const char*` | 62 | 16 |
  | `int8_t`..`int64_t` (the `uint` forms mapped to them), `float`, `double`, `complex64` by reference | 11 | 7 |
  | `int64_t` by value / `const int64_t*`, `const uint64_t*` / `uintptr_t` by value | 2 / 2 / 2 | **0** / 1 / **0** |
  | `int` result / no result | 570 / 5 | 349 / 3 |

  Four classes are reached by no library call: `mlx_optional_int` by value, `bool` as result, `int64_t` and
  `uintptr_t` by value. `mlxf_c_types.f90` holds 36 `bind(c)` structs (31 single-pointer handles, 2 iterators of
  two pointers, 3 optional pairs) and 23 enumerators of 4 enums. The library's own `bind(c)` procedures are 4
  callbacks (`record_mlx_error`, `invoke_callback`, `delete_payload`, `release_buffer`) and 79 abstract
  signature-class interfaces `mlxc_*_op` (`src/core/array/mlxf_array.f90`), which the compiler holds to the
  generated interfaces when a procedure is passed; the ABI risk therefore sits in the generator's mapping table
  and in the 4 callbacks. The longest call the library makes, `mlx_conv_transpose3d` (17 arguments), passes 9 on
  the stack, packed by Apple's arm64 rule, and its tests pass on the M5.
- **Documents that disagree.** The README says transfers take five kinds; the contract (section 5) says eight.
  (The test policy's guard count, nineteen against the registry's 21, was corrected with the review's fixes.)
- **Embedding configures and builds, but a parent cannot `use mlxf`.** After R4, `scripts/check_embed.sh`
  configures a parent project and builds the library target. The library's include directories hold only an
  `INSTALL_INTERFACE`; in the build tree `mlxf.mod` sits beside every private module in
  `modules/mlxf/`, so exposing that directory to a parent would let it import `mlxf_c_array` and reach a handle,
  which the installed package forbids.

## 3. Decisions and rulings

1. (2026-11-25, recommended) **Scope:** the review's six remaining items, in five working phases; the FORTLS
   default stays outside (section 2).
2. (2026-11-25, recommended) **What a clean snapshot is.** The release gate builds a source tree it exports,
   never the checkout:
   - **release mode** (no flag): `git archive HEAD` into `build_release_gate/src/`; refuses modified tracked
     files (as today); the log lists untracked files that are not ignored, which the export leaves out;
   - **`--allow-dirty`:** the working-tree content of `git ls-files --cached --others --exclude-standard`
     (deleted files left out), tag `<commit>-dirty`, every file that differs from `HEAD` listed in the log;
   - **`--require-tag`:** fails unless `HEAD` carries the tag `v<PROJECT_VERSION>` (`CMakeLists.txt`'s
     `project(VERSION)`); the tag is the maintainer's;
   - mlx-c is resolved as the checkout would resolve it (`MLXC_ROOT`, then `<checkout>/.deps/install` when
     present, then the default search) and passed as `-DMLXC_ROOT=`; the log records `MLXC_DIR` and the
     version.
   - Proven by a plant: an untracked `src/core/runtime/mlxf_planted.f90` that does not compile; release mode
     passes and names it, `--allow-dirty` fails on it.
3. (2026-11-25, recommended) **No editor side effects, checked.** Every gate, CI job and documented downstream
   configure line passes `-DFORTLS=OFF` (CI included). The release gate hashes every file of the snapshot before
   configuring and after installing, and records the modification time of the checkout's
   `.claude/settings.local.json`; a difference fails the gate. Rule `fortlsoff` in `scripts/check_rules.py`:
   every `cmake -S` or `cmake ..` line of `scripts/release_gate.sh`, `scripts/check_install.sh`,
   `scripts/ci_*.sh`, `README.md`, `doc/quickstart.md` and `doc/how2s/how2use_from_simple.md` names
   `-DFORTLS=OFF` or configures no producer. The developer's compile scripts are outside the rule.
4. (2026-11-25, recommended) **The release gate runs the consumer check** on its Debug and its Release build,
   with the consumer and the examples (decision 15) in `require-gpu` mode; a failure fails the gate. The release
   gate's skip and GPU checks stay as they are.
5. (2026-11-25, recommended) **The consumer runs where MLX can allocate.** `mlxf_consumer` takes the command
   argument `require-gpu`; without it, it runs on every device MLX can allocate on (the CPU alone on a
   CPU-only MLX), and in a Metal session without a device it exits 0 after printing `SKIP`; with it, a missing GPU
   stops it. Default: no argument.
6. (2026-11-25, ruled as recommended, Hans: "Yes, all seven") **The installed package requires the mlx-c version it was built with,
   exactly.** `mlxfConfig.cmake` refuses an mlx-c whose `MLXC_VERSION` is not `VERSION_EQUAL` the recorded one,
   with the message form of the compiler refusal ("mlxf mlx-c mismatch: built with 0.8.0; found ..."), before
   it checks the library type. `mlxf.pc` gains `mlxc_version=`. `scripts/check_install.sh` plants a mismatch in
   a copy of the installed config (recorded version `0.0.0-incompatible`) and asserts the refusal and its
   message, as it does for the compiler. The producer's warning for a non-pinned mlx-c
   (`cmake/Dependencies.cmake`) stays a warning. Recommended: exact, because the archive's interfaces were
   generated from exactly those headers and mlx-c is 0.x; the alternative is major.minor equality.
7. (2026-11-25, recommended) **The installed-consumer test is the release criterion's evidence:** the consumer
   and the three examples, built against the installed prefix with only `-Dmlxf_DIR=`, run on the GPU and the
   CPU device, from the snapshot of decision 2, inside the release gate.
8. (2026-11-25, recommended) **Three device situations, one classification,** used by `test_devices`, the guard
   gate of `mlxf_test_exec`, the consumer and the examples:

   | `mlx_metal_is_available()` | GPU count | Situation | Tests | Under `MLXF_REQUIRE_GPU` |
   | --- | --- | --- | --- | --- |
   | true | > 0 | Metal with a device | the devices asked for (`device=`) | as today |
   | true | 0 | Metal without a device (headless, sandboxed, virtual) | skip, `SKIP: no GPU device in this session` (as today) | failure (as today) |
   | false | 0 | CPU-only MLX | the CPU device; a GPU-only check skips with `SKIP: GPU-only check on a CPU-only MLX build` | failure |

   Each `GUARDS` member gets a device need (`cpu` or `gpu`); on a CPU-only MLX the `gpu` members skip with the
   same message and the others run. The device, error and memory testers' own GPU tests follow the table.
9. (2026-11-25, ruled as recommended, Hans: "Yes, all seven") **`mlx_metal_is_available()` becomes public** (mlx-c's name; the ledger
   line `plumbing` → `public`; one name in the README's "devices and memory" row; a check in
   `mlxf_device_tester`). The need: the classification of decision 8 in test code that uses `mlxf` as a user
   does, and a user who must tell a CPU-only build from a session without a device. Recommended: yes; the
   alternative is a test-only import of the generated layer, which the house rules do not allow for code under
   `src/test/`.
10. (2026-11-25, recommended) **A CPU-only MLX, pinned.** `scripts/build_mlx_deps.sh --cpu-only` builds the same
    tags (MLX `v0.32.4`, mlx-c `v0.8.0`) with `-DMLX_BUILD_METAL=OFF`, skips the Metal-compiler check, and
    installs into `.deps/install-cpu`, never `.deps/install`, which `cmake/Dependencies.cmake` searches by
    default and would put in front of Homebrew's mlx-c. A build selects it with `MLXC_ROOT`.
11. (2026-11-25, recommended) **The CPU-only build passes the fast gate** with `-DMLXF_REQUIRE_GPU=OFF`: per
    area, the CPU-device check count equals the Metal build's count with `device=cpu` (Phase 0, *exact*), less
    the checks each GPU-only member or sub-suite owns, each listed with its reason in Progress. No no-device
    `SKIP` line may appear.
12. (2026-11-25, ruled as recommended, Hans: "Yes, all seven") **Pull-request feedback runs on hosted macOS arm64 runners against a
    CPU-only MLX built from source and cached** (cache key: runner image, the two tags, the hash of
    `scripts/build_mlx_deps.sh`). Recommended, because it is the support boundary's OS and architecture and needs
    no Linux promise; the alternative, Linux runners, is cheaper and faster but builds and tests a platform the
    project does not support.
13. (2026-11-25, ruled as recommended, Hans: "Yes, all seven") **Homebrew's `pkgconf` and `gcc@14` on the M5.** The consumer check
    needs pkg-config (absent); the oldest advertised compiler needs `gcc@14` (14.4.0; the oldest GNU Fortran 14
    Homebrew offers). Homebrew is read-only for agents, so **the maintainer runs `brew install pkgconf gcc@14`
    before launch** (recommended; both are bottled). Without them, Phase 0 stops (pkg-config) and decision 14's
    oldest leg is CI-only.
14. (2026-11-25, recommended) **The compilers tested:** GNU Fortran 14.4.0 (`gcc@14`) and 16.2.0 (`gcc`),
    named in the README as tested, the advertised floor left at 14. The CI matrix is the CPU-only build under
    {14.4 Debug, 14.4 Release, 16.2 Debug, 16.2 Release}, each with the fast gate and the consumer check; the
    existing Homebrew Metal build-only jobs stay (Debug, Release; 16.2), with `-DFORTLS=OFF` added.
15. (2026-11-25, recommended) **Three example programs, compiled and run by the consumer check** against the
    installed package, in `test/consumer/`:
    - `mlxf_example_first.f90`: the README's first program (two arrays, `exp(-matmul(a, b))`, `mlx_to_alloc`
      with `status`), at most 30 lines;
    - `mlxf_example_differences.f90`: one block per row of the dtype-and-result table (decision 16), each
      asserting its row and printing `D<n>: ok`; a failed row exits 1;
    - `mlxf_example_errors.f90`: a recoverable failure through `status` and `mlx_last_error()`, the named owner
      of `mlx_view`, and the device classification of decision 8.
16. (2026-11-25, recommended) **The dtype-and-result table,** 14 to 20 rows (*guessed*), in `doc/quickstart.md`
    and summarised in the README's lead. Columns: the Fortran spelling, what Fortran gives, what `mlxf` gives,
    same or different, and the evidence (a `D<n>` block of the differences example, or a guard member for a row
    that stops). Rows drawn from the contract, each confirmed by its evidence: integer `/` is true division to
    float32 and `mlx_floor_divide` floors; `matmul` of two integers stops (`guard_matmul_integer`) and of an
    integer and a real promotes; weak scalars (a real64 scalar with a float32 array, a half array keeps its kind,
    an integer or boolean array with a real scalar gives float32, a real scalar with complex64 gives complex64);
    `real(a)` gives float32 from every numeric kind; `cmplx(x, y)` and its finite-only guarantee; the result
    kinds of `sum`, `count`, `mlx_mean`, `all`, `maxloc`; `mlx_round` half to even against `nint`; `modulo`;
    float64 only on the CPU (`guard_float64_on_gpu`) and MLX's float32 internals for some float64 functions;
    unchecked 1-based indices of `mlx_take` (0 wraps); comparisons give boolean arrays; `matmul` and `transpose`
    batch over dimensions 3 and up. A row whose evidence disagrees with the contract is a finding: the contract is
    corrected when the library is right by MLX, and the run stops when the library is wrong (section 7).
17. (2026-11-25, recommended) **Rule `docex`** in `scripts/check_rules.py`: every fenced `fortran` block of
    `README.md`, `doc/quickstart.md` and `CONTRIBUTING.md` is preceded by `<!-- example: test/consumer/<file> -->`
    and is a verbatim run of that file's lines; every `D<n>` row of the table has exactly one block `! D<n>` in
    the differences example or names a member of `GUARDS`. Planted: an edited line in a README block, an
    unmarked block, a row without evidence, a row naming an unknown guard.
18. (2026-11-25, ruled as recommended, Hans: "Yes, all seven") **Where the examples run:** in the consumer check only (the release gate
    and the CPU-only CI jobs), not in the fast gate. Recommended: the installed package is the artifact the
    examples document, the CTest budget stays 9, and every claim of the table is also tested in-tree by an area
    suite or a guard; the alternative is a tenth CTest entry `examples` that builds them in-tree.
19. (2026-11-25, recommended) **The quickstart** (`doc/quickstart.md`, at most 200 lines) holds, after the
    table, one table of **caller obligations against runtime enforcement:**
    - one submitting thread: refused inside an OpenMP parallel region (any level) when the library was built
      with `USE_OPENMP=ON`; not detected for any other host thread (pthreads, GCD, a C++ caller), nor at all
      with `USE_OPENMP=OFF`: the caller's obligation;
    - the error handler: the library's first call replaces mlx-c's process-wide handler; a host that installs its
      own afterwards takes MLX's messages from `mlx_last_error()`, and one that restores mlx-c's default makes an
      MLX error print and `exit(-1)`;
    - hard stop against recoverable error: graph building stops with `error stop 86`; the checked procedures
      (contract, section 6) return a status; a callback returns a status and never stops; over-subscribed
      unified memory pages rather than fails;
    - `mlx_view` and `mlx_alloc`: the named owner pattern and the write window, with the dangling form;
    - devices: decision 8's three situations; float64 on the CPU only; `MLX_ENABLE_TF32=0` for full precision.
20. (2026-11-25, recommended) **The README leads with a runnable program.** Its first 45 lines: one paragraph,
    the first example verbatim, the commands that build, install (`-DFORTLS=OFF`) and compile it against the
    installed package, and links to `doc/quickstart.md`, `doc/how2s/how2use_from_simple.md`,
    `test/consumer/mlxf_consumer.f90` and `CONTRIBUTING.md`. The status, the name table and the layout follow.
    Those commands are run verbatim in a scratch directory in Phase 3 and recorded. `CONTRIBUTING.md` (at most 80
    lines): build and gates, the rules and where they are checked, the test and plan forms, the policies as
    references.
21. (2026-11-25, recommended) **ABI checks by echo and by mutation.**
    - **Echo probe:** `src/test/mlxf_abi_probe.h` declares `mlx_abiprobe_*` functions in mlx-c's own types
      (the header includes `mlx/c/mlx.h`); `src/test/mlxf_abi_probe.c` implements them, returning what they
      received; `scripts/gen_mlxc_bindings.py --probe <header>` writes their interfaces with the same mapping
      table into the test build (`mlxf_c_abi_probe.f90`, importing `mlxf_c_types`); the C file is compiled by
      Apple's clang (`xcrun clang`), the compiler of Homebrew's and `build_mlx_deps.sh`'s mlx-c, as an object of
      `mlxf_test_exec` (CMake's C compiler is GCC, whose ABI would agree with GFortran's by construction).
    - **Coverage:** each of the 35 classes at least once; `int`, `bool`, `float`, `double` and the three optional
      pairs both in a register and on the stack (calls of more than 8 integer and 8 floating arguments); the two-
      pointer struct and a handle as results; size, alignment and field offsets of the 36 structs and the values
      of the 23 enumerators against C's `sizeof`, `_Alignof`, `offsetof`.
    - **Mutation:** each class's line of the mapping table, each value struct's field kinds, and each of the 4
      callbacks' passing modes (a `value` removed or added), mutated one at a time, must fail the fast gate (the
      probe or an existing test). A survivor gets a check that kills it.
    - It is the sub-suite `abi` of `unit_core`; no CTest entry is added.
22. (2026-11-25, ruled as recommended, Hans: "Yes, all seven") **If GNU Fortran 14.4 does not build the tree or pass the gate:** the run
    works around it in `src/core` when the change is at most 20 lines and changes no result, with a reproducer in
    `doc/compiler_issues/`; otherwise it records the failure, sets the CI's oldest leg to 15.3 (`gcc@15`), and the
    advertised floor is the maintainer's. Recommended as written.
23. (2026-11-25, recommended) **Rule `devquery`:** no test code (`src/test/`, `*_tester.f90`, `test/`) calls
    `mlx_device_count(MLX_DEVICES%gpu)` outside `mlxf_test_utils` and a ledger that may only shrink (today 7
    calls in 4 files, *exact*: `test/mlxf_test_exec.f90` 1, the consumer 1, the device tester 4, the error
    tester 1; Phase 2 moves the guard gate onto `mlxf_test_utils`), so that a new GPU check cannot bypass
    decision 8. Planted: a tester that skips on the GPU count.
25. (2026-11-25, ruled as recommended, Hans: "Yes, all seven") **An embedding parent sees `mlxf.mod` and nothing else.** After the
    library is built, a post-build step copies `mlxf.mod` alone into `${PROJECT_BINARY_DIR}/include/mlxf`, which
    becomes the target's `BUILD_INTERFACE` include directory (the `INSTALL_INTERFACE` is unchanged).
    `scripts/check_embed.sh` then builds and runs a parent program that uses `mlxf` (CPU device), and a second
    parent source that imports `mlxf_c_array` must fail to compile, as the consumer check proves for the installed
    package. Recommended: yes, the same isolation in the build tree as in the installed package; the alternative
    is to document that embedding builds the library but its users link the installed package.
24. (2026-11-25, recommended) **Questions for the MLX team** (`doc/collaboration/apple_questions.md`): mlx-c has no
    run-time version query of its own; a Metal build cannot allocate on the CPU device when no GPU opens.

Defaults taken without a question: the quickstart's path `doc/quickstart.md`; the example names; the tag form
`v<PROJECT_VERSION>`; the flag `--require-tag`; `.deps/install-cpu`; the CI job names; `scripts/ci_cpu_job.sh`
as the one script every CPU-only CI job runs (the workflow only calls it); the probe's file names; the
`abi` sub-suite in area `core`.

## 4. Not in this plan

- The FORTLS default (the maintainer's open decision), and every option default of the compile scripts.
- Linux, CUDA and other compilers as release promises; a Linux CI job.
- New wrappers (parity, rank 3), the kernels (rank 2), any change of a result.
- Skill and `CLAUDE.md` edits: proposed in the report, applied only on approval.
- Files out of bounds: `src/test/mlxf_toy_*`, `src/test/mlxf_oracle_*`, `src/test/mlxf_bench_*`, every plan but
  this one and the roadmap.

## 5. Change types and gates

| Phase | Kind | Gate |
| --- | --- | --- |
| 0 | measurement | both builds without a warning; the numbers of section 6 frozen in Progress |
| 1 | tests-only: packaging, gates, the consumer | decision 2's plant; decision 6's planted mismatch; rule `fortlsoff` and its plant; the release gate in `--allow-dirty` mode passes with the consumer check on both builds |
| 2 | one public addition; test infrastructure; CI | identical check counts on the Metal build; decision 11 on the CPU-only build with 16.2 and 14.4; the no-device recipe's skips as in Phase 0; rule `devquery` and its plant |
| 3 | documents and examples | rule `docex` and its four plants; the examples pass in the consumer check on the GPU and on the CPU-only build; the README's commands run verbatim |
| 4 | tests-only, and a generator option | the generated layer byte-identical; the probe passes; every mutation of decision 21 fails the gate |
| 5 | record | the release gate passes in `--allow-dirty` mode and on the base commit in release mode; the report |

Every phase ends with Debug and Release built from scratch with `MLXF_CMAKE_ARGS="-DMLXF_WERROR=ON -DFORTLS=OFF"`
and no warning, the fast gate 9 of 9 in both, `scripts/check_tree.sh` passing, `scripts/restyle_fortran.py` and
`scripts/format_use_blocks.py` (with explicit file names) on every Fortran file touched, `shellcheck` clean on
every shell script touched, and every Python file touched parsed by `ast.parse(..., feature_version=(3, 7))` and
importing the standard library only.

## 6. Acceptance

- **Frozen in Phase 0** (*measured* on the base, two runs each, the larger kept): the check count per area and
  device of the Metal build; the skip lines under the no-device recipe; the fast gate's real time (bound: the
  base's plus 3 s, *guessed*, and under the 60 s budget); the release gate's time (bound: the base's plus twice
  the consumer check's time plus 60 s, *derived* from decision 4 and *guessed* for the margin); the consumer
  check's time; the sha256 of the generated layer.
- **Exact:** decision 11's counts; decision 21's coverage (35 classes, 36 structs, 23 enumerators) and its
  mutations; the four plants of decision 17, the plants of decisions 2, 3, 6 and 23.
- **The release criterion,** met in two steps. The run: the release gate in `--allow-dirty` mode passes with no
  skip, both builds, the consumer and the three examples on the GPU, no side effect (decision 3). The session,
  right after the maintainer commits and tags: `scripts/release_gate.sh --require-tag` passes on the tag. The
  plan moves to `completed/` only after that run, and the session runs it in the turn the tag appears.
- **Reported, not gated:** the first hosted run of the workflow (only the maintainer's push proves it: its job
  times, the cache, the runner's toolchain); the CPU-only MLX's build time on the M5; lines of documentation.
- **Reserved for the maintainer:** the commit and the tag; the push; the FORTLS default; the advertised compiler
  floor if decision 22's second branch is taken; whether the README's lead reads well.

## 7. Common rules and stop conditions

- No file outside the table; no bound loosened and no test removed to pass; a fix found on the way gets a table
  row first. A test executable run directly on the GPU is run with `MLX_ENABLE_TF32=0`.
- The workflow is written, never pushed. What the run verifies of it: every step's script run on the M5 (the
  CPU-only jobs with both compilers, the Metal build-only job under the no-device recipe
  `sandbox-exec -p "(version 1)(allow default)(deny iokit-open)"`), the YAML parsed by `ruby -ryaml`. What it
  cannot: the runner image, its network and cache, the jobs' times, GitHub's evaluation of the file.
- Homebrew installs only as decision 13 rules; MLX's configure fetches its own dependencies over the network.

**Stops:**
- the base lacks K2's result or one of the reviews' fixes (`guard_strided_span`, `guard_matmul_integer`,
  `PIPESTATUS` in `scripts/run_fast_gate.sh`, `ctest_budget.py --self-test`, the 673/680 count in the README,
  `nan_maxval` with rule `nanmax`, rule `cmakeroot`, `scripts/check_embed.sh`);
- pkg-config is absent and decision 13 is not ruled (Phase 0);
- MLX `v0.32.4` or mlx-c `v0.8.0` does not build or link with `MLX_BUILD_METAL=OFF`, or the network is not
  available for MLX's fetches: Phase 2's CPU-only leg stops, the rest of the plan goes on, and the CI keeps
  build-only jobs;
- a row of the table, a probe or a mutation shows the library wrong against MLX or the contract in a path the
  library calls (a real ABI mismatch included);
- a public change beyond decision 9, a change to an existing suite's count on the Metal build, or a second
  library target would be needed;
- the static gate fails on something the run did not touch.

**Gates no ruling may waive:** no warning in Debug or Release; the static gate; the release gate's failure on a
skip and without a GPU; `mlxf` the one installed module; the library reads no environment variable; one library
target; the CTest budget of 9 (unless decision 18 is ruled otherwise); Python 3.7 and the standard library.

## 8. Phases

### Phase 0, the base and the measurements

1. Record the machine, the base commit, the toolchain, `brew list --versions mlx mlx-c gcc gcc@14 pkgconf`.
   Check the stops of section 7 that concern the base.
2. Build Debug and Release from scratch (`-DFORTLS=OFF`), each twice, timing configure, build and gate apart;
   record the check counts per area with `device=cpu` and `device=gpu`.
3. Run `scripts/release_gate.sh` (as it is) on the base, twice, timed; run `scripts/check_install.sh` on the
   Release and the Debug build, twice, timed.
4. What a clean snapshot means here: export `HEAD` with `git archive`, build Release and run the fast gate in
   it with `-DMLXC_ROOT=` set as decision 2 says; compare the library archive's members (`ar t`) and the gate's
   result with the checkout's; list what the configure, build and static gate read outside `src/` (the scripts,
   `cmake/`, the parity plan and the guide files the static gate reads).
5. Run the base's fast gate under the no-device recipe with `-DMLXF_REQUIRE_GPU=OFF`; record every skip line.
6. Re-count the ABI classes of section 2 with the scratch script (kept in the run's `scratch/keep/`), and take
   the sha256 of the generated layer.
7. Record which configure lines of the tree pass `-DFORTLS=OFF` (section 2's finding).
8. Freeze section 6's numbers in Progress, each tagged with its origin.

**Exit:** the numbers are frozen; both builds are free of warnings; the gate passes; the consumer check passes
on both builds.

### Phase 1, the installed package under test

Decision 2's export modes and mlx-c pinning; decision 3's side-effect check and rule `fortlsoff`; decision 4's
consumer check inside the release gate; decision 5's consumer argument; decision 6's version check, `mlxf.pc`'s
`mlxc_version` and the planted mismatch; decision 25's build-tree interface and the embedding parent's program
and refusal; `doc/how2s/how2use_from_simple.md` brought in line.

**Exit:** the phase's gate of section 5.

### Phase 2, CPU-only MLX, the device classification and pull-request feedback

`mlx_metal_is_available()` with its test; decision 8 in `test_devices`, the guard gate, the `GUARDS` device
column, the testers that ask for the GPU themselves and the consumer; rule `devquery`; `build_mlx_deps.sh
--cpu-only` and the CPU-only build of the tree with 16.2 and with 14.4 (decision 22 if needed);
`scripts/ci_cpu_job.sh` and the workflow of decisions 12 and 14; the test policy's section 4, the contract's
section 7 and `doc/how2s/how2set_up_dev.md`.

**Exit:** the phase's gate of section 5; the CPU-only build's per-area counts recorded against Phase 0's.

### Phase 3, the documents users meet first

The three examples and their build in `test/consumer/CMakeLists.txt` and `scripts/check_install.sh`; the table
and the quickstart; the README's lead (and its five-kind transfer line corrected to the contract's eight); the
test policy's guard count; `CONTRIBUTING.md`; rule `docex`.

**Exit:** the phase's gate of section 5.

### Phase 4, the ABI checks

The generator's `--probe` option; the probe header and C file; the clang object and the generated probe module
in `test/CMakeLists.txt`; `src/test/mlxf_abi_tester.f90` as sub-suite `abi` of `unit_core`; the mutations of
decision 21, run with the object, the archive and the executable deleted before each build (Apple's make compares
whole seconds); the test policy's line on the ABI sub-suite; the README's sentence on name coverage.

**Exit:** the phase's gate of section 5; every mutation and its failing check listed in Progress.

### Phase 5, the record

1. The release gate in `--allow-dirty` mode (both builds, the consumer and the examples on the GPU), and in
   release mode on the base commit; both logs kept.
2. The roadmap's rank 2b row; the history entry; the plans index; questions for the MLX team (decision 24); the
   register if a rule enters it.
3. The report in the order of `doc/how2s/how2write_agent_plans.md`, section 8, with the proposed skill and
   `CLAUDE.md` edits, the commands of the tagged run for the session, and a commit message with no attribution
   or co-author line.

**Exit:** both release-gate logs pass; the report exists; `git status` shows only file-table paths, the new
files named in the report.

### File table

| File | What | Phases |
| --- | --- | --- |
| `scripts/release_gate.sh` | the export modes, mlx-c pinning, the side-effect check, the consumer check | 1, 2, 5 |
| `scripts/check_install.sh` | the mlx-c mismatch plant; the consumer argument; the examples | 1, 2, 3 |
| `cmake/mlxfConfig.cmake.in` | the mlx-c version check | 1 |
| `cmake/mlxf.pc.in` | `mlxc_version` | 1 |
| `src/CMakeLists.txt` | decision 25's build-tree include directory holding `mlxf.mod` alone | 1 |
| `scripts/check_embed.sh` | decision 25: the parent program and the refused private import | 1 |
| `test/consumer/CMakeLists.txt` | the examples | 1, 3 |
| `test/consumer/mlxf_consumer.f90` | `require-gpu`; decision 8 | 1, 2 |
| `test/consumer/mlxf_example_first.f90` (new) | the README's program | 3 |
| `test/consumer/mlxf_example_differences.f90` (new) | the table's rows | 3 |
| `test/consumer/mlxf_example_errors.f90` (new) | status, the named owner, devices | 3 |
| `test/consumer/consumer.inf` | the directory's description | 3 |
| `scripts/check_rules.py` | rules `fortlsoff`, `devquery`, `docex` | 1, 2, 3 |
| `scripts/check_tree.sh` | the comment's list of rules | 1, 2, 3 |
| `src/core/runtime/mlxf_device.f90` | `mlx_metal_is_available` | 2 |
| `src/core/mlxf.f90` | its re-export | 2 |
| `scripts/mlxc_parity.txt` | its line `public` | 2 |
| `src/core/runtime/mlxf_device_tester.f90` | its test; decision 8 | 2 |
| `src/core/runtime/mlxf_error_tester.f90`, `src/core/runtime/mlxf_memory_tester.f90` | decision 8, if needed | 2 |
| `src/core/fast/mlxf_fast_tester.f90` | GPU-only checks on a CPU-only MLX, if needed | 2 |
| `src/test/mlxf_test_utils.f90` | `test_devices` | 2 |
| `test/mlxf_test_exec.f90` | the guard gate | 2 |
| `src/test/mlxf_test_registry.f90` | the `GUARDS` device column; sub-suite `abi` | 2, 4 |
| `src/test/mlxf_test_defs.f90` | the guard record, if it lives there | 2 |
| `scripts/check_test_registry.py` | the `GUARDS` form, if needed | 2 |
| `scripts/build_mlx_deps.sh` | `--cpu-only` | 2 |
| `scripts/ci_cpu_job.sh` (new) | the CPU-only CI job | 2 |
| `.github/workflows/ci.yml` | the jobs of decisions 12 and 14 | 2 |
| `doc/policies/test_environment_policy.md` | section 4; the guard count; the ABI sub-suite | 2, 3, 4 |
| `doc/policies/binding_contract_policy.md` | section 7; a corrected row, if decision 16 finds one | 2, 3 |
| `doc/how2s/how2set_up_dev.md` | the CPU-only build; the compilers | 2 |
| `doc/how2s/how2use_from_simple.md` | the version check; `-DFORTLS=OFF`; links | 1, 3 |
| `doc/quickstart.md` (new) | the table and the obligations | 3 |
| `CONTRIBUTING.md` (new) | the contributor's path | 3 |
| `README.md` | the lead; the compilers; the transfer kinds; `mlx_metal_is_available`; name coverage | 2, 3, 4 |
| `doc/compiler_issues/` (new file) | a GNU Fortran 14 reproducer, if decision 22's first branch is taken | 2 |
| `src/core/` (any file) | a GNU Fortran 14 workaround, if decision 22's first branch is taken, named in Progress | 2 |
| `scripts/gen_mlxc_bindings.py` | `--probe` | 4 |
| `scripts/list_mlxc_prototypes.py` | the probe header, if needed | 4 |
| `src/test/mlxf_abi_probe.h` (new) | the probe's prototypes | 4 |
| `src/test/mlxf_abi_probe.c` (new) | the echo functions | 4 |
| `src/test/mlxf_abi_tester.f90` (new) | sub-suite `abi` | 4 |
| `src/test/test.inf` | the directory's description | 4 |
| `test/CMakeLists.txt` | the probe's generation and clang object; comments | 4 |
| `doc/collaboration/apple_questions.md` | decision 24 | 5 |
| `doc/implementation_notes/planned/mlxf_roadmap.md` | the rank 2b row | 5 |
| `doc/implementation_notes/README.md` | the index | 5 |
| `doc/history/2026-11.md`, or `doc/history/2026-12.md` if the run ends in December | the entry | 5 |
| `doc/architecture_principles.md` | the new rules, if the register lists rules of their kind | 5 |
| `doc/implementation_notes/planned/mlxf_release_hardening.md` | this note: Progress | 0, 1, 2, 3, 4, 5 |
| `doc/implementation_notes/completed/mlxf_release_hardening_report.md` (new) | the report | 5 |

## Progress

(one entry per phase, written by the run)
