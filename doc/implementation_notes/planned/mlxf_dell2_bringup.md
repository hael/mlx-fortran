# dell2 bring-up for mlx-fortran runs (run `mlxf_dell2_bringup`)

Status, 2026-11-24: planned; one phase, to run before any work is sent to dell2. Base: `09da56c`. Supersedes:
none. Depends on: arun on dell2 (validated: yes for SIMPLE's runs; no for this repository, which is what this
plan checks). Documentation only: the run edits this note's Progress and nothing else in the repository.

## 1. Why

The first batch of the [roadmap](mlxf_roadmap.md) sends CPU-only work to dell2: the plain-Fortran oracles of
the toy kernels. mlx-fortran has never been copied to a Linux machine. Its library builds on macOS only,
because MLX needs Metal. Before a plan relies on dell2, one short run establishes what works there with this
repository: arun end to end, the static gate under Linux, and a standalone gfortran build of Fortran that
needs no MLX.

## 2. Contract

- **Documentation only.** No file of the repository changes except this note's Progress. Probes and their
  logs live under the run's `scratch/keep/`.
- **Nothing is fixed.** A check that fails on dell2 is a finding, recorded with its output. The run does not
  edit a script, a hook or a source to make it pass.
- **No MLX.** The library is not built. One CMake configuration of the repository is attempted in a scratch
  tree, to record how it stops.
- dell2's SIMPLE checkout and data are not used.

### What the check found (2026-11-24, from the Mac, *measured*)

- `ssh dell2` works without a prompt. The machine was idle (load 0.00) with 724 GB free.
- Tools: GNU Fortran 15.2.0, CMake 4.2.3, Python 3.14.4, git 2.53.0; `rsync`, `flock`, `timeout` and `setsid`
  are present.
- Claude Code 2.1.331 is installed there and answered a one-turn prompt with the machine's own credentials
  (`~/.config/arun/env` exists).
- arun copies tracked files only, so this plan is committed before the launch.
- The static gate (`scripts/check_tree.sh`) runs seven Python checks and needs only `python3` and git. Its
  rule `parity` reads mlx-c's headers, which dell2 does not have: whether the gate passes there is unknown.
- The repository's stop hook (`.claude/hooks/stop_gate.sh`) runs that gate whenever `src/`, `test/` or
  `scripts/` differ from HEAD. A later run that writes Fortran on dell2 will meet it at every stop, so the
  gate's behaviour under Linux decides how such a run is set up.

## 3. Decisions

1. (2026-11-24, recommended) **Scope:** one phase of probes on dell2, recorded in Progress. No report file:
   the Progress entry is the record, and this note moves to `completed/` when the maintainer has read it.
2. (2026-11-24, recommended) **The probes** are those of section 5, in that order, each with its command, exit
   status and the last lines of its output kept under `scratch/keep/`.
3. (2026-11-24, recommended) **The standalone Fortran probe** is written by the run under `scratch/keep/`: a
   module in the house layout that computes a small discrete Fourier transform in double precision and
   checks it against its closed form, with a main program that prints the largest error. It is compiled
   with `gfortran -std=f2018 -Wall -Wextra -Werror -O2`. It stands for the kind of code the oracles are.
4. (2026-11-24, recommended) **Time box:** 30 minutes (*guessed*).

## 4. Not in this plan

- Any oracle, kernel or library code.
- Any change that makes a failing check pass on Linux.
- A Linux build of MLX or of the library.

## 5. Phases

### Phase 0, the probes

1. Record the machine: hostname, OS, cores, memory, load, the tool versions above, and the preflight's
   record (`logs/preflight.txt`).
2. Run `scripts/check_tree.sh` on the copied repository, untouched. Record its exit status and output. If it
   fails, name the failing check and say whether the cause is Linux, the missing mlx-c headers, or the
   Python version.
3. Run each of the gate's seven checks on its own (`python3 -I scripts/<check> ...`, as `check_tree.sh` calls
   them) and record which pass.
4. Run the two formatters in check mode on one existing Fortran file of `src/test/`
   (`scripts/restyle_fortran.py --check <file>` and `scripts/format_use_blocks.py --check <file>`).
5. Compile `src/test/mlxf_kernel_polar_oracle.f90` on its own with `gfortran -fsyntax-only`, and record what
   it needs that is missing (its modules import the library through the test utilities).
6. Write, compile and run decision 3's standalone probe. Record the compile line, any warning, and the
   printed error.
7. Attempt one CMake configuration of the repository into `scratch/keep/cmake_probe/` and record how it
   stops.
8. Write the Progress entry: every probe's outcome, the files changed (this note only), and "what it means"
   for a run that writes plain-Fortran oracles on dell2: what gate it can use, and what it cannot build.

**Exit:**
- the Progress entry holds the outcome of probes 1 to 7 with their log paths;
- `git status` in the run's copy shows this note as the only modified file;
- no probe was "fixed".

**Stop:** a probe would need an edit outside this note, or dell2 cannot run a session at all (the preflight
fails).

### File table

| File | What | Phases |
| --- | --- | --- |
| `doc/implementation_notes/planned/mlxf_dell2_bringup.md` | this note: Progress | 0 |

## Progress

### Phase 0, the probes: done (2026-11-24, 09:03 to 09:11 EST, dell2)

One unattended session of run `mlxf_dell2_bringup`. Base: the run's copy at `8305556` (this note's commit,
the one after `09da56c`), clean at the start. Rulings: none. Files changed: this note's Progress, nothing else.
Evidence: `/home/hael/agent_runs/mlxf_dell2_bringup/scratch/keep/` (`keep/` below), one log per probe with
its command, exit status and the last 30 lines of its output. The probes took 4 minutes (*measured*, 09:03:41
to 09:07:20) of the 30-minute box (*guessed*); the load stayed below 0.1 throughout (*measured*). Every
number below is *measured* (read from a log) unless tagged otherwise; the probe's parameters (`a`, the sizes
n, the flags) and the counts of the layout rules are *exact*.

Decision under delegation: no review report file. arun's generic last-phase instructions ask for
`completed/mlxf_dell2_bringup_report.md`; decision 1, fixed for this run, makes this entry the record, and the
exit wants this note as the only modified file. Decision 1 holds.

1. **Machine.** dell2, Ubuntu 26.04.1 LTS, kernel 7.0.0-43, Intel Core Ultra 7 366H with 16 CPUs at one
   thread per core, 61 GB of memory and 31 GB of swap, load 0.08; 724 GB free on `/`, 788 GB on `/data2`.
   GNU Fortran 15.2.0, CMake 4.2.3, GNU Make 4.4.1, Python 3.14.4, git 2.53.0, Claude Code 2.1.331; `rsync`,
   `flock`, `timeout`, `setsid` and `rg` present. The preflight passed: the session logs in, and the fence
   refuses a write outside the file table and a publish to the remote. `keep/probe1_machine.log` (it holds
   `logs/preflight.txt`).
2. **Static gate on the untouched copy: passes.** `scripts/check_tree.sh` exits 0 with `check_tree: passed`
   in 1.3 s (load 0.06). Neither Linux, the missing mlx-c headers nor Python 3.14 stops it.
   `keep/probe2_check_tree.log`.
3. **The seven checks one by one: all exit 0.** `check_descr.py`, `check_rules.py`, `check_test_registry.py`,
   `check_guide_imports.py`, `check_submodule_linkage.py`, `format_use_blocks.py --check` (0 of 51 files)
   and `restyle_fortran.py --check --tree`. Rule `parity` finds no mlx-c headers (it looks under
   `MLXC_ROOT`, `.deps/install/include`, `/opt/homebrew/include`, `/usr/local/include`, then
   `build/gen/mlxc_prototypes.txt`), prints `parity: no mlx-c headers or prototype list found; the ledger's
   names were not compared`, and still checks the ledger's own form; `check_rules.py` reports 52 files with
   every rule holding. `keep/probe3_checks.log`.
4. **Formatters in check mode** on `src/test/mlxf_kernel_polar_oracle.f90`: both exit 0.
   `keep/probe4_formatters.log`.
5. **The polar oracle alone** (`gfortran -fsyntax-only -std=f2018 -fopenmp`, modules into `keep/`) **stops**,
   exit 1: `Cannot open module file 'mlxf_test_defs.mod'`. One step further, same log: `mlxf_test_defs.f90`
   compiles alone (intrinsic modules only); `mlxf_test_utils.f90` stops at `mlxf.mod`, the library, and
   without `-cpp` warns three times `Illegal preprocessor directive` (`#ifdef MLXF_REQUIRE_GPU`); the oracle
   then stops at `mlxf_test_utils.mod`. What it misses is the library, reached only through `mlxf_test_utils`
   and for one name, `bits_equal`, a transfer-based comparison that needs no MLX.
   `keep/probe5_oracle_syntax.log`.
6. **Standalone DFT probe: no warning, passes.** `keep/probe6_dft/`: module `mlxf_probe_dft` (a direct DFT of
   `a**m`, its closed form `(1 - a**n) / (1 - a exp(-2 pi i k / n))`, the largest difference), program
   `mlxf_probe_dft_main`, `probe6_dft.inf`. Compile line `gfortran -std=f2018 -Wall -Wextra -Werror -O2`:
   module, program and link exit 0 with no output. Run with `a = 0.9 exp(0.3 i)`: largest error 6.3e-16 at
   n = 8, 5.3e-15 at 16 and 31, against a tolerance of 1e-12 (*guessed*); 0.004 s, load 0.00.
   Layout: `restyle_fortran.py --check` and `format_use_blocks.py --check` accept files outside the
   repository; their first pass flagged the program (a padded non-intrinsic `use`, declarations outside the
   constants' `::` column), which took the formatters' own output, and both then exit 0. `check_descr.py` and
   `check_rules.py` walk only the repository's `src/` and `test/`, so their rules were applied by hand: one
   leading `!@descr:` and a header of at most five lines; one module per file, named as its file with
   `mlxf_`; a one-line `.inf`; `use, only:`; `implicit none`; one `public ::` block, then a bare `private`;
   constants in capitals; bodies indented by four, padded dummy lists, named ends, the `if( )` form, aligned
   columns; at most two dummies; no `==` on reals, no `block` or `goto`; `!` comments that cite nothing.
   `keep/probe6_standalone_dft.log`.
7. **CMake configuration: stops after 0.3 s**, exit 1. `cmake -S <repo> -B keep/cmake_probe
   -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=ON` (the options of `compile_clean.sh`): AutoDetectGCC picks
   `/usr/bin/gfortran-15` and `gcc-15` (15.2.0), both identify, then `cmake/Dependencies.cmake:48` stops with
   its own message: mlx-c needed and none found (`MLXC_ROOT` not set, `.deps/install` absent, no `brew` on
   `PATH`). OpenMP and the generated layer are not reached; nothing was written into the repository.
   `keep/probe7_cmake_configure.log`, the whole output in `keep/probe7_cmake_configure.full.log`.

Findings, recorded and not fixed (section 2); evidence in `keep/findings.log` unless named:

- `scripts/format_use_blocks.py` skips options it does not know: `--help` ran its tree-wide rewrite (it
  printed `0 of 51 files rewritten` and the tree stayed clean). A mistyped `--check` would rewrite the tree.
- The copy holds `.claude/settings.local.json`, git-ignored and dated 01:52, before the copy (written on the
  Mac by the fortls target, *derived* from `.gitignore`'s note and its content). It enables a plugin from
  `/Users/hael/src/mlx-fortran/build/claude-plugins`, which does not exist here. Section 2's "arun copies
  tracked files only" does not hold for it.
- arun's fence refuses a shell command whose text names a publish to the remote anywhere, a heredoc of
  notes included; a run writes its notes with the editor tools (the run's `state/journal_phase_0.md`,
  09:05).
- `~/.claude/CLAUDE.md` gives dell2 8 GB of swap; `free` reports 31 GB.
- dell2's gfortran is 15.2.0; the repository's notes name 16.2 on the Mac. A trap the skill marks for
  gfortran before 16 (a submodule calling a private plain procedure of its module does not link) applies
  here; `check_submodule_linkage.py` checks it.

What it means, in short, for a run that writes plain-Fortran oracles on dell2:

- **Gate:** `scripts/check_tree.sh` works here as on the Mac, in about a second, so the stop hook that runs
  it whenever `src/`, `test/` or `scripts/` differ from HEAD works too. One limit: `parity` cannot compare its
  ledger with mlx-c's headers here, so such a run leaves the ledger and the bindings alone. The formatters
  work, also on files outside the tree.
- **Cannot build:** the library, `mlxf_test_exec`, any CTest or `compile_*.sh`/`recompile.sh` (configuration
  stops at mlx-c), nor any file of `src/test/` that imports `mlxf_test_utils` or `mlxf`; today that includes
  the polar oracle, through `bits_equal` alone.
- **Can build:** plain Fortran that uses intrinsic modules and `mlxf_test_defs`, compiled file by file with
  gfortran 15.2 (`-std=f2018 -Wall -Wextra -Werror`, `-J` into a scratch directory, `-cpp` for a file with
  `#ifdef`), linked into a small driver and run. An oracle can be held to a closed form here; its comparison
  with MLX waits for the Mac.
- **Open for the maintainer:** whether an oracle meant to compile on dell2 may import `mlxf_test_utils`, or
  `bits_equal` moves to a module free of the library; whether the 15.2/16.2 compiler difference matters for
  the oracles; and the two findings above about the formatter's options and the copied local settings.

Exit:

- Probes 1 to 7 are recorded above with their log paths: met.
- `git status` shows this note as the only modified file: met, `keep/final_git_status.log`.
- No probe was fixed: met. No script, hook or source was edited; the one layout change was to the probe's
  own file in `keep/`, which decision 3 asks to follow the house layout.
