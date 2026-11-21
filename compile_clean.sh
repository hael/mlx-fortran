#!/bin/bash
# Clean release build and install into build/.
#
#   ./compile_clean.sh                  library and tests; the fast test gate runs before installation
#   ./compile_clean.sh --exclude-tests  library only, no gate
#   ./compile_clean.sh --jobs 4         limit concurrent compiler processes
# mlx-c is found as cmake/Dependencies.cmake says (MLXC_ROOT, .deps/install, Homebrew).
# MLXF_CMAKE_ARGS (environment, optional) adds CMake options to the configuration, e.g.
#   MLXF_CMAKE_ARGS="-DMLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON" (the CI's setting).
BUILD_TESTS=ON
JOBS=""
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
while [[ $# -gt 0 ]]; do
    case "$1" in
        --exclude-tests) BUILD_TESTS=OFF ;;
        --jobs|-j)
            shift
            if [[ $# -eq 0 || -z "$1" ]]; then echo "compile_clean.sh: --jobs requires a positive integer" >&2; exit 1; fi
            JOBS="$1"
            ;;
        --jobs=*) JOBS="${1#*=}" ;;
        -h|--help)
            echo "usage: $(basename "$0") [--exclude-tests] [--jobs N]"
            echo "Default jobs: available CPUs, or CMAKE_BUILD_PARALLEL_LEVEL when set."
            exit 0
            ;;
        *) echo "compile_clean.sh: unknown option: $1 (see --help)" >&2; exit 1 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS") || exit $?
cd "$ROOT" || exit 1
rm -rf build
mkdir build
cd build
# MLXF_CMAKE_ARGS is split into words on purpose
# shellcheck disable=SC2086
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=${BUILD_TESTS} ${MLXF_CMAKE_ARGS:-} || exit $?
make -j"$JOBS" || exit $?
# A failed gate is a failed build and installs nothing; its status is the script's status.
if [ "$BUILD_TESTS" = ON ]; then "$ROOT/scripts/run_fast_gate.sh" "$PWD" || GATE_RC=$?; fi
[ "${GATE_RC:-0}" = 0 ] && { make -j"$JOBS" install || exit $?; }
exit ${GATE_RC:-0}
