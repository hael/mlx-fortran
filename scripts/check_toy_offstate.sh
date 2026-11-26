#!/bin/bash
# scripts/check_toy_offstate.sh -- the toys' host files built and run without MLX.
#
#   scripts/check_toy_offstate.sh [--jobs N] [--exec MLXF_TEST_EXEC] [--fc GFORTRAN] [--keep DIR]
#
# Configures test/offstate (the host files and the glue stubs of the toy classes that scripts/toy_seam.txt names,
# without USE_MLX, with no path to the library's modules and no link to the library) in a scratch directory under
# TMPDIR, in Debug and Release with MLXF_WERROR, builds it and runs its program mlxf_offstate_exec, which fails
# when a refusal of the MLX backend is missing. The program's lines `polarft_host ...` are the table of the polar
# host route in hexadecimal. With --exec, a Release mlxf_test_exec of this checkout, the same lines of its
# sub-suite `unit_kernels suite=polarft_host` (the host backend, one thread) must equal the Release program's byte
# for byte. --fc names another GNU Fortran (the gate is the default one); --keep keeps the builds and logs in DIR.
# A relative path of an option is the caller's: it is made absolute when the option is read.
# No binary of the build may refer to an MLX symbol. Run by scripts/release_gate.sh; not a CTest entry.
# Exit 0 when both builds configure, build without a warning and run, and the tables agree when --exec is given.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
JOBS=""; EXEC=""; FC=""; KEEP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j) shift; JOBS="${1:-}" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        --exec) shift; EXEC="${1:-}" ;;
        --exec=*) EXEC="${1#*=}" ;;
        --fc) shift; FC="${1:-}" ;;
        --fc=*) FC="${1#*=}" ;;
        --keep) shift; KEEP="${1:-}" ;;
        --keep=*) KEEP="${1#*=}" ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "check_toy_offstate: unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS") || exit $?
# the script changes directory before it runs anything: a path given relative to the caller's directory is made
# absolute where the option is read (--keep below, by its cd; --fc when it is a path and not a name on PATH)
abs_file() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
if [[ -n "$EXEC" ]]; then
    if [[ ! -f "$EXEC" || ! -x "$EXEC" ]]; then
        echo "check_toy_offstate: no executable $EXEC (--exec)" >&2
        exit 2
    fi
    EXEC=$(abs_file "$EXEC")
fi
if [[ "$FC" == */* && "$FC" != /* ]]; then
    if [[ ! -x "$FC" ]]; then
        echo "check_toy_offstate: no compiler $FC (--fc)" >&2
        exit 2
    fi
    FC=$(abs_file "$FC")
fi
if [[ -n "$KEEP" ]]; then
    mkdir -p "$KEEP" || exit 2
    WORK="$(cd "$KEEP" && pwd)"
else
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/mlxf_offstate.XXXXXX") || exit 2
    trap 'rm -rf "$WORK"' EXIT
fi
args=(-DMLXF_WERROR=ON)
[[ -n "$FC" ]] && args+=("-DCMAKE_Fortran_COMPILER=$FC")
fail() { echo "check_toy_offstate: FAILED: $*" >&2; exit 1; }
for build_type in Debug Release; do
    B="$WORK/$build_type"
    rm -rf "$B"
    t0=$SECONDS
    cmake -S "$ROOT/test/offstate" -B "$B" "-DCMAKE_BUILD_TYPE=$build_type" "${args[@]}" > "$WORK/$build_type.configure.log" 2>&1 ||
        { tail -n 20 "$WORK/$build_type.configure.log"; fail "$build_type does not configure"; }
    cmake --build "$B" -j "$JOBS" > "$WORK/$build_type.build.log" 2>&1 ||
        { grep -n -B2 -A12 -E 'Error|error:' "$WORK/$build_type.build.log" | head -n 60
          fail "$build_type does not build without the library"; }
    if grep -qi 'warning' "$WORK/$build_type.build.log"; then
        grep -i -A6 'warning' "$WORK/$build_type.build.log" | head -n 40
        fail "$build_type builds with a warning"
    fi
    if nm -u "$B/mlxf_offstate_exec" 2>/dev/null | grep -qi 'mlx'; then
        nm -u "$B/mlxf_offstate_exec" | grep -i 'mlx' | head -n 10
        fail "$build_type: the program refers to an MLX symbol"
    fi
    ( cd "$B" && OMP_NUM_THREADS=1 ./mlxf_offstate_exec ) > "$WORK/$build_type.run.log" 2>&1 ||
        { tail -n 30 "$WORK/$build_type.run.log"; fail "$build_type: mlxf_offstate_exec failed"; }
    grep '^polarft_host ' "$WORK/$build_type.run.log" > "$WORK/$build_type.table.txt"
    echo "check_toy_offstate: $build_type built without the library in $((SECONDS - t0)) s and ran" \
        "($(grep -c . "$WORK/$build_type.table.txt") table lines)"
done
compared="not compared with mlxf_test_exec (no --exec)"
if [[ -n "$EXEC" ]]; then
    mkdir -p "$WORK/exec"
    ( cd "$WORK/exec" && OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=4 MLX_ENABLE_TF32=0 "$EXEC" test=unit_kernels suite=polarft_host ) \
        > "$WORK/exec.run.log" 2>&1 || { tail -n 30 "$WORK/exec.run.log"; fail "$EXEC: the sub-suite polarft_host failed"; }
    grep '^polarft_host ' "$WORK/exec.run.log" > "$WORK/exec.table.txt"
    [[ -s "$WORK/exec.table.txt" ]] || fail "$EXEC wrote no table of the host route"
    cmp "$WORK/Release.table.txt" "$WORK/exec.table.txt" ||
        fail "the host route's table differs between the build without MLX and $EXEC"
    compared="the host route's table equals mlxf_test_exec's byte for byte ($(grep -c . "$WORK/exec.table.txt") lines)"
fi
echo "check_toy_offstate: passed (Debug and Release without USE_MLX and without the library; $compared)"
