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

(one entry, written by the run)
