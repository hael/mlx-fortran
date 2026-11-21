#!/bin/bash
# Clean debug build (runtime checks including bounds) and install into build/.
#
#   ./compile_debug.sh                  library and tests; the fast test gate runs before installation
#   ./compile_debug.sh --exclude-tests  library only, no gate
#   ./compile_debug.sh --traps          add floating-point traps and signalling-NaN initialisation
BUILD_TESTS=ON
DEBUG_TRAPS=OFF
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
for arg in "$@"; do
    case "$arg" in
        --exclude-tests) BUILD_TESTS=OFF ;;
        --traps) DEBUG_TRAPS=ON ;;
        -h|--help)
            echo "usage: $(basename "$0") [--exclude-tests] [--traps]"
            echo "Default jobs: available CPUs, or CMAKE_BUILD_PARALLEL_LEVEL when set."
            exit 0
            ;;
        *) echo "$(basename "$0"): unknown option: $arg (see --help)" >&2; exit 1 ;;
    esac
done
JOBS=$(mlxf_build_jobs) || exit $?
cd "$ROOT" || exit 1
rm -rf build
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=${BUILD_TESTS} -DMLXF_DEBUG_TRAPS=${DEBUG_TRAPS} || exit $?
make -j"$JOBS" || exit $?
# A failed gate is a failed build and installs nothing; its status is the script's status.
if [ "$BUILD_TESTS" = ON ]; then "$ROOT/scripts/run_fast_gate.sh" "$PWD" || GATE_RC=$?; fi
[ "${GATE_RC:-0}" = 0 ] && { make -j"$JOBS" install || exit $?; }
exit ${GATE_RC:-0}
