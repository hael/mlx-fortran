#!/bin/bash
# scripts/run_fast_gate.sh -- the build-time test gate on a build with tests (BUILD_TESTS=ON).
#
#   scripts/run_fast_gate.sh [BUILD_DIR]        (default: build)
#
# First the static gate, scripts/check_tree.sh (file headers and unit boundaries, the rules reading can
# check, test registry, guide imports, submodule linkage, use-block form; a warning for untracked sources);
# a failure stops the gate before any test runs. Then `ctest -L fast` in BUILD_DIR with half
# the cores rounded up, teed to BUILD_DIR/test_runs/ctest_fast.log and handed to scripts/ctest_budget.py,
# which is silent when the gate passes within its 60 s budget, warns on an overrun and fails on a failed
# entry. The per-entry timings are kept beside the log (ctest_fast.log.timing.txt).
#
# Called by every compile_*.sh between `make` and `make install` unless --exclude-tests is given (a failed
# gate installs nothing), and by `make check`. The gate fails when ctest fails or when the transcript is not a
# complete run (the budget checker); the checker only reports times otherwise. Lifted from SIMPLE.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$ROOT/build}"
case "$BUILD" in /*) ;; *) BUILD="$ROOT/$BUILD" ;; esac
[ -f "$BUILD/CTestTestfile.cmake" ] || { echo "run_fast_gate: no CTest configuration in $BUILD (built with --exclude-tests? rebuild without it)" >&2; exit 2; }
if command -v nproc >/dev/null 2>&1; then ncpu=$(nproc); else ncpu=$(sysctl -n hw.ncpu); fi
jobs=$(( (ncpu + 1) / 2 )); [ "$jobs" -lt 1 ] && jobs=1
# The build's interpreter (MLXF_PYTHON3, cmake/Dependencies.cmake), not the python3 on PATH.
PY=$(sed -n 's/^MLXF_PYTHON3:INTERNAL=//p' "$BUILD/CMakeCache.txt")
[ -x "$PY" ] || { echo "run_fast_gate: no MLXF_PYTHON3 in $BUILD/CMakeCache.txt (reconfigure); using python3" >&2; PY=python3; }
# the static gate first (it also warns about untracked sources)
"$ROOT/scripts/check_tree.sh" "$PY" || exit 1
mkdir -p "$BUILD/test_runs"
LOG="$BUILD/test_runs/ctest_fast.log"
( cd "$BUILD" && ctest -L fast --output-on-failure --parallel "$jobs" --timeout 600 2>&1 ) | tee "$LOG"
ctest_status=${PIPESTATUS[0]}
"$PY" "$ROOT/scripts/ctest_budget.py" "$LOG" --budget 60 --quiet
budget_status=$?
if [ "$ctest_status" -ne 0 ]; then
    echo "run_fast_gate: ctest exited with status $ctest_status" >&2
    exit 1
fi
exit "$budget_status"
