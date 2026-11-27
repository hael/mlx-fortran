---
name: mlxf-agent-runs
description: "Use when the maintainer says go, proceed, launch or do it on a batch of work, and whenever agent runs are prepared, launched, watched, fetched or reviewed (arun on the M5, dell2 or dell): what is settled before the go, how the work continues after it without a question, what arms the wake-up at a run's end, what is done when a run ends or stops, the short list of things that really wait for the maintainer and what is done instead of waiting, and the mechanics of arun that have cost time."
---

# Agent runs and working after a go

When the maintainer says go, the session works until the batch is done. It does not end a turn on a question it
has a recommendation for, and it does not end a turn while a machine that has work waiting is idle. A day in
which a run finished at 10:08 and nothing was fetched, checked or started until the evening is the failure this
skill exists to prevent.

## 1. Before the go: one sitting

Everything that needs the maintainer is collected into one request, made once, before the go is asked for:

- **Every plan of the batch is drafted,** not only the first. A plan that waits on another run's result is drafted
  too, with its trigger named ("launches when run X is committed").
- **Every decision carries a recommendation,** and the decisions of all the plans are put to the maintainer
  together. Decisions closed before launch are the ones that survive review
  (`doc/how2s/how2write_agent_plans.md`, section 1), so this is the moment to get them ruled.
- **One commit request covers the batch.** `arun` copies tracked files only and agents commit only when the
  maintainer asks, so every plan file of the batch is named in one `git add` and one `git commit`, which the
  maintainer pastes or asks the session to run. A run never waits for a commit that could have been in that
  request.
- **Whatever else only the maintainer can do** (a login, data only they have, a first use of `dell`) is in the
  same request.

The go then covers all of it. If the go arrives before this sitting happened, do the sitting's work at once and
ask once; do not launch one run and come back with the next plan's questions.

## 2. After the go: no question, no idle machine

- **Launch every run that can start,** one per machine (`arun hosts` first).
- **Arm a wake-up for every run in flight:** a background command that exits when the run's driver stops, so the
  session is called back at the run's end. Check that it is armed before the turn ends. A turn never ends with a
  run in flight and no wake-up.
- **Work on while the runs run:** the next plan of the roadmap, the review of an earlier result, the housekeeping
  the roadmap lists. Only when nothing is left that does not depend on a run does the turn end, with the
  wake-ups armed and the report saying what each machine is doing.
- **A decision that comes up is taken as recommended.** Write it in the plan as "stands as recommended, open to
  the review" with its reason, and go on. It is reported, never asked.
- **Roadmap order decides what is next.** When a run ends, what it unblocked starts in the same turn.

## 3. When a run ends

In the turn that the wake-up starts, in this order:

1. `arun fetch <run>`; read `RUN_STATUS.md`, the plan's Progress and the report.
2. Rebuild the result from scratch in a scratch copy of the checkout with the run's `full.diff` applied: Debug
   and Release with `MLXF_CMAKE_ARGS="-DMLXF_WERROR=ON"`, the static gate, and the touched areas'
   `mlxf_test_exec test=unit_<area>` (with `MLX_ENABLE_TF32=0` when the executable is run directly on the GPU).
   The run's own claims are a report, not a result.
3. Read the diff for what the plan reserves for the maintainer (the API read at a hold, a default) and list it.
4. Apply the diff to the checkout with `git apply`, unless a launch from the checkout is still pending (see 5).
5. Report: what was built and run here, the results, the new (untracked) files by name, and the commit command.
6. Start what the result unblocked.

A run that STOPPED: read the stop report; what the plan delegates is ruled in `runs/<run>/rulings.md` and the run
resumed (`arun resume`); only what the plan reserves goes to the maintainer.

## 4. What really waits for the maintainer, and what is done instead of waiting

| It needs the maintainer | Done meanwhile |
| --- | --- |
| A commit (agents commit only when asked; `arun` leaves untracked files out) | The exact commands go first in the report. If the machine the work needs is free, the work is done in the session or by a subagent instead of waiting for a launch |
| A password, a login, an account | Everything that does not need it |
| A destructive or outward-facing action | Prepared, not done |
| What a plan reserves (the API read at a hold, a real-data read) | The result is verified and laid out for that read |
| A plan's stop condition | The stop report, with a recommendation |

Nothing else stops the work. In particular these do not: a decision with a recommendation, a choice between two
reasonable orders of work, a finding that can be recorded and returned to, "shall I continue".

## 5. arun mechanics that have cost time

- **Tracked files only.** Uncommitted edits to tracked files are copied; untracked files are not; files git
  ignores are. A plan must be committed before its run is launched.
- **A result with new files makes the checkout unlaunchable** until it is committed: its edits to tracked files
  are copied and its new files are not, so the copy does not build or pass the gate. Launch pending runs before
  applying a result, or have the result committed first.
- **One run per machine;** `arun launch` refuses a machine that is busy. The M5 is the only machine with a GPU
  and the only one that builds the library; timings need it quiet.
- **dell2** builds plain Fortran and runs the static gate and the formatters; it cannot build the library or any
  file that imports it (`doc/implementation_notes/planned/mlxf_dell2_bringup.md`, Progress). **dell** is the
  maintainer's production machine: its first use in a batch is asked for in the sitting of section 1.
- **The fence reads the plan's `### File table`.** Check it per phase before launch (arun's README, "Starting a
  run", step 3).
- **The mirror** (`runs/<run>/live/`) answers "how is the run doing" without ssh; it is not a wake-up.

## 6. The end of every turn in a batch

Before the turn ends, for each machine: what runs on it, whether its wake-up is armed, and if it is idle, why and
what would start it. If the answer to "why is it idle" is a question to the maintainer that has a recommendation,
take the recommendation and start the work.
