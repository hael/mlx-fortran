#!/bin/bash
# scripts/check_embed.sh -- mlx-fortran added to a parent project with add_subdirectory().
#
#   scripts/check_embed.sh [--jobs N]
#
# Writes a minimal parent project in a scratch directory under TMPDIR (its path holds a space), adds this
# checkout to it with tests and editor tooling off, configures it and builds the library target mlxf. It proves
# on a real configure what rule cmakeroot checks by reading: the library's helper modules, templates and
# generator are found under its own source directory, not the parent's. Then the parent's own program, which
# uses mlxf, is built against the library's build tree and run on the CPU device, and a second parent source
# that imports the private module mlxf_c_array must fail to compile: the build tree, like the installed package,
# shows a parent mlxf.mod and nothing else. MLXC_ROOT, when set, is passed on. Run by scripts/release_gate.sh.
# Exit 0 when the parent configures, the library and the program build, the program passes and the import fails.
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
add_executable(parent_program parent_program.f90)
target_link_libraries(parent_program PRIVATE mlxf)
add_executable(parent_private parent_private.f90)
target_link_libraries(parent_private PRIVATE mlxf)
CMAKE
cat > "$WORK/parent/parent_program.f90" <<'FORTRAN'
program parent_program
use, intrinsic :: iso_fortran_env, only: real32
use mlxf, only: mlx_array, mlx_from, mlx_to_alloc, mlx_set_default_device, mlx_live_count, MLX_DEVICES
implicit none
type(mlx_array)           :: a, b
real(real32), allocatable :: y(:)
integer                   :: st
call mlx_set_default_device(MLX_DEVICES%cpu)
a = mlx_from([1._real32, 2._real32, 3._real32])
b = a * 2._real32 + 1._real32
call mlx_to_alloc(y, b, status=st)
if( st /= 0 ) error stop 'parent_program: transfer failed'
if( .not. all(abs(y - [3._real32, 5._real32, 7._real32]) <= 0._real32) ) error stop 'parent_program: wrong values'
call a%kill()
call b%kill()
if( mlx_live_count() /= 0 ) error stop 'parent_program: a handle leaked'
write(*,'(a)') 'parent_program passed'
end program parent_program
FORTRAN
printf 'program parent_private\nuse mlxf_c_array, only: mlxc_array_new\nend program parent_private\n' \
    > "$WORK/parent/parent_private.f90"
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
if ! cmake --build "$WORK/build" --target parent_program -j "$JOBS" > "$WORK/program.log" 2>&1; then
    tail -n 40 "$WORK/program.log"
    echo "check_embed: FAILED: a parent program that uses mlxf does not build"
    exit 1
fi
if ! (cd "$WORK" && MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 "$WORK/build/parent_program"); then
    echo "check_embed: FAILED: the parent program failed"
    exit 1
fi
if cmake --build "$WORK/build" --target parent_private > "$WORK/private.log" 2>&1; then
    echo "check_embed: FAILED: a parent source imported the private module mlxf_c_array"
    exit 1
fi
if ! tr '[:upper:]' '[:lower:]' < "$WORK/private.log" | grep -q "cannot open module file 'mlxf_c_array.mod'"; then
    tail -n 40 "$WORK/private.log"
    echo "check_embed: FAILED: the private import failed for another reason than the missing module"
    exit 1
fi
echo "check_embed: passed (configured and built with add_subdirectory; the parent's program ran; mlxf_c_array refused)"
