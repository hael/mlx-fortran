#!/bin/bash
# scripts/release_gate.sh -- the gate a release needs, run on an Apple-silicon Mac with a Metal GPU.
#
#   scripts/release_gate.sh [--allow-dirty] [--jobs N]
#
# The hosted CI has no Metal device: it builds with warnings as errors and runs the source checks, and its
# device tests skip. A release (a tag or a published version) needs this script's passing log instead. It
# refuses a tree with uncommitted changes to tracked files (the log names one commit) unless --allow-dirty,
# builds Debug and Release from scratch in build_release_gate/ (MLXF_REQUIRE_GPU=ON, MLXF_WERROR=ON,
# FORTLS=OFF), runs the fast gate on each, then scripts/check_embed.sh, and fails when the gate fails, when any
# test reports a skip, when no GPU device was opened or when the library cannot be embedded. The log, with the toolchain, MLX and the device, is
# build_release_gate/release_gate_<commit>.log (ignored by git, like every build_* directory).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
allow_dirty=0
JOBS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-dirty) allow_dirty=1 ;;
        --jobs|-j) shift; JOBS="${1:-}" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "release_gate: unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS") || exit $?
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "release_gate: needs an Apple-silicon Mac (this is $(uname -s) $(uname -m))" >&2
    exit 2
fi
cd "$ROOT" || exit 2
commit=$(git --no-optional-locks rev-parse --short HEAD) || exit 2
dirty=$(git --no-optional-locks status --porcelain --untracked-files=no)
if [[ -n "$dirty" && $allow_dirty -eq 0 ]]; then
    echo "release_gate: uncommitted changes to tracked files; commit them or pass --allow-dirty" >&2
    exit 2
fi
tag="$commit"
[[ -n "$dirty" ]] && tag="${commit}-dirty"
WORK="$ROOT/build_release_gate"
rm -rf "$WORK" && mkdir -p "$WORK" || exit 2
LOG="$WORK/release_gate_${tag}.log"
exec > >(tee "$LOG") 2>&1

echo "release gate of mlx-fortran ${tag}, $(date '+%F %T')"
echo "host:     $(sysctl -n machdep.cpu.brand_string 2>/dev/null), macOS $(sw_vers -productVersion 2>/dev/null)"
echo "compiler: $(gfortran --version 2>/dev/null | head -n 1)"
echo "cmake:    $(cmake --version | head -n 1)"
echo "MLX:      $(brew list --versions mlx mlx-c 2>/dev/null | tr '\n' ' ')"
[[ -n "$dirty" ]] && { echo "uncommitted changes (--allow-dirty):"; echo "$dirty"; }

failed=0
for build_type in Debug Release; do
    B="$WORK/$build_type"
    echo
    echo "==== $build_type: configure, build, fast gate"
    if ! cmake -S "$ROOT" -B "$B" -DCMAKE_BUILD_TYPE=$build_type -DBUILD_TESTS=ON -DMLXF_REQUIRE_GPU=ON \
            -DMLXF_WERROR=ON -DFORTLS=OFF; then
        failed=1; break
    fi
    if ! cmake --build "$B" -j "$JOBS"; then
        failed=1; break
    fi
    "$ROOT/scripts/run_fast_gate.sh" "$B" || failed=1
    # the full output of every test of the gate, passing ones included
    T="$B/Testing/Temporary/LastTest.log"
    nskip=0
    ngpu=0
    if [[ -f "$T" ]]; then
        nskip=$(grep -c 'SKIP' "$T")
        ngpu=$(grep -m 1 -o 'GPU devices: [0-9]*' "$T" | awk '{print $3}')
    fi
    echo "$build_type: tests reporting a skip: ${nskip}; GPU devices opened: ${ngpu:-0}"
    if [[ "$nskip" -ne 0 ]]; then
        grep 'SKIP' "$T" | sort | uniq -c
        failed=1
    fi
    [[ "${ngpu:-0}" -gt 0 ]] || failed=1
done
if [[ $failed -eq 0 ]]; then
    echo
    echo "==== the library added to a parent project (add_subdirectory)"
    "$ROOT/scripts/check_embed.sh" --jobs "$JOBS" || failed=1
fi

echo
if [[ $failed -ne 0 ]]; then
    echo "RELEASE GATE FAILED: ${tag} (log ${LOG})"
    exit 1
fi
echo "RELEASE GATE PASSED: ${tag}, Debug and Release, on $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
