#!/bin/bash
# Incremental build of an existing build/ (made by a compile_*.sh script) and install.
#
#   ./recompile.sh                 rebuild what changed; when the build has tests, the fast gate runs
#                                  before installation
#   ./recompile.sh --no-gate       rebuild and install without the gate
#   ./recompile.sh --jobs 4        limit concurrent compiler processes
#   ./recompile.sh --build-dir D   another configured build tree (or MLXF_BUILD_DIR)
# The build type and the test setting stay as the compile script configured them. A source file added
# or removed under src/ reruns cmake by itself (CONFIGURE_DEPENDS in src/CMakeLists.txt).
GATE=yes
JOBS=""
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${MLXF_BUILD_DIR:-$ROOT/build}"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-gate) GATE=no ;;
        --jobs|-j)
            shift
            if [[ $# -eq 0 || -z "$1" ]]; then echo "recompile.sh: --jobs requires a positive integer" >&2; exit 1; fi
            JOBS="$1"
            ;;
        --jobs=*) JOBS="${1#*=}" ;;
        --build-dir)
            shift
            if [[ $# -eq 0 || -z "$1" ]]; then echo "recompile.sh: --build-dir requires a directory" >&2; exit 1; fi
            BUILD="$1"
            ;;
        -h|--help)
            echo "usage: $(basename "$0") [--no-gate] [--jobs N] [--build-dir DIR]"
            exit 0
            ;;
        *) echo "recompile.sh: unknown option: $1 (see --help)" >&2; exit 1 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS") || exit $?
case "$BUILD" in /*) ;; *) BUILD="$PWD/$BUILD" ;; esac
if [[ ! -f "$BUILD/CMakeCache.txt" ]]; then
    echo "recompile.sh: no configured build in $BUILD; run ./compile_clean.sh or ./compile_debug.sh first" >&2
    exit 1
fi
make -C "$BUILD" -j"$JOBS" || exit $?
if [[ $GATE = yes ]] && grep -Eq '^BUILD_TESTS:[A-Z]+=(ON|1|YES|TRUE)$' "$BUILD/CMakeCache.txt"; then
    "$ROOT/scripts/run_fast_gate.sh" "$BUILD" || GATE_RC=$?
fi
[ "${GATE_RC:-0}" = 0 ] && { make -C "$BUILD" -j"$JOBS" install || exit $?; }
exit ${GATE_RC:-0}
