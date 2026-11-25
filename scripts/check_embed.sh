#!/bin/bash
# scripts/check_embed.sh -- mlx-fortran added to a parent project with add_subdirectory().
#
#   scripts/check_embed.sh [--jobs N]
#
# Writes a minimal parent project in a scratch directory under TMPDIR (its path holds a space), adds this
# checkout to it with tests and editor tooling off, configures it and builds the library target mlxf. It proves
# on a real configure what rule cmakeroot checks by reading: the library's helper modules, templates and
# generator are found under its own source directory, not the parent's. MLXC_ROOT, when set, is passed on.
# Run by scripts/release_gate.sh. Exit 0 when the parent configures and the library builds.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
JOBS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j) shift; JOBS="${1:-}" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "check_embed: unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS") || exit $?
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mlxf embed.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/parent"
cat > "$WORK/parent/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.25)
project(mlxf_embed_parent LANGUAGES C Fortran)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(FORTLS OFF CACHE BOOL "" FORCE)
add_subdirectory("$ROOT" mlxf)
CMAKE
args=()
[[ -n "${MLXC_ROOT:-}" ]] && args+=("-DMLXC_ROOT=$MLXC_ROOT")
if ! cmake -S "$WORK/parent" -B "$WORK/build" "${args[@]+"${args[@]}"}" > "$WORK/configure.log" 2>&1; then
    tail -n 40 "$WORK/configure.log"
    echo "check_embed: FAILED: the parent project does not configure"
    exit 1
fi
if ! cmake --build "$WORK/build" --target mlxf -j "$JOBS" > "$WORK/build.log" 2>&1; then
    tail -n 40 "$WORK/build.log"
    echo "check_embed: FAILED: the library does not build inside the parent project"
    exit 1
fi
echo "check_embed: passed (configured and built with add_subdirectory)"
