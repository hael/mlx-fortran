#!/bin/bash
# scripts/ci_cpu_job.sh -- one CPU-only CI job: the tree against a CPU-only MLX, its fast gate and the consumer check.
#
#   scripts/ci_cpu_job.sh BUILD_TYPE FORTRAN_COMPILER [--jobs N]      (BUILD_TYPE Debug or Release)
#
# Every CPU-only job of .github/workflows/ci.yml runs this script and nothing else, so that the M5 runs what a
# runner runs. MLX built without Metal (scripts/build_mlx_deps.sh --cpu-only) allocates on the CPU device where no
# GPU opens, as on a hosted macOS runner, so the device tests run there on the CPU instead of skipping. The prefix
# is MLXC_ROOT, or .deps/install-cpu, built when it holds no mlx-c (MLX_SRC and MLXC_SRC name the clones; the
# workflow caches the prefix). The tree is configured in build_ci_<type>/ with MLXF_REQUIRE_GPU=OFF,
# MLXF_WERROR=ON and FORTLS=OFF, built, gated and installed, then scripts/check_install.sh runs the consumer. The
# job fails when any of them fails, when the build did not link the CPU-only MLX, or when a test reports the
# no-device skip (a session that cannot allocate: the CPU-only MLX would not be in use). GPU-only checks skip
# with their own line, which is counted and reported.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
positional=()
JOBS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j) shift; JOBS="${1:-}" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        -*) echo "ci_cpu_job: unknown option: $1 (see --help)" >&2; exit 2 ;;
        *) positional+=("$1") ;;
    esac
    shift
done
[[ ${#positional[@]} -eq 2 ]] || { echo "usage: scripts/ci_cpu_job.sh Debug|Release FORTRAN_COMPILER [--jobs N]" >&2; exit 2; }
TYPE="${positional[0]}"
FC_NAME="${positional[1]}"
case "$TYPE" in Debug|Release) ;; *) echo "ci_cpu_job: build type Debug or Release, not $TYPE" >&2; exit 2 ;; esac
FC=$(command -v "$FC_NAME") || { echo "ci_cpu_job: no Fortran compiler $FC_NAME" >&2; exit 2; }
JOBS=$(mlxf_build_jobs "$JOBS") || exit $?
cd "$ROOT" || exit 2
PREFIX="${MLXC_ROOT:-$ROOT/.deps/install-cpu}"
if [[ ! -d "$PREFIX/share/cmake/MLXC" ]]; then
    echo "==== CPU-only MLX into $PREFIX (scripts/build_mlx_deps.sh --cpu-only)"
    PREFIX="$PREFIX" scripts/build_mlx_deps.sh --cpu-only --jobs "$JOBS" || exit 1
fi
export MLXC_ROOT="$PREFIX"
[[ -f "$PREFIX/mlxf_deps.txt" ]] && cat "$PREFIX/mlxf_deps.txt"
B="$ROOT/build_ci_$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')"
rm -rf "$B"
echo "==== $TYPE with $("$FC" --version | head -n 1): configure, build"
cmake -S "$ROOT" -B "$B" -DCMAKE_BUILD_TYPE="$TYPE" -DBUILD_TESTS=ON -DMLXF_REQUIRE_GPU=OFF -DMLXF_WERROR=ON \
    -DFORTLS=OFF "-DMLXC_ROOT=$PREFIX" "-DCMAKE_Fortran_COMPILER=$FC" "-DCMAKE_INSTALL_PREFIX=$B" || exit 1
built=$(sed -n 's/^MLXC_DIR:PATH=//p' "$B/CMakeCache.txt")
case "$built" in
    "$PREFIX"/*) ;;
    *) echo "ci_cpu_job: configured with mlx-c at $built, not the CPU-only prefix $PREFIX" >&2; exit 1 ;;
esac
cmake --build "$B" -j "$JOBS" || exit 1
failed=0
echo "==== fast gate"
scripts/run_fast_gate.sh "$B" || failed=1
T="$B/Testing/Temporary/LastTest.log"
nodevice=0
gpuonly=0
if [[ -f "$T" ]]; then
    nodevice=$(grep -c 'SKIP: no GPU device' "$T")
    gpuonly=$(grep -c 'SKIP: GPU-only check on a CPU-only MLX build' "$T")
    grep -q 'Metal backend: F' "$T" || { echo "ci_cpu_job: the tests did not run on a CPU-only MLX"; failed=1; }
fi
echo "$TYPE: GPU-only checks skipped: ${gpuonly}; no-device skips: ${nodevice}"
grep 'SKIP' "$T" 2>/dev/null | sort | uniq -c
[[ "$nodevice" -eq 0 ]] || failed=1
if [[ $failed -eq 0 ]]; then
    cmake --install "$B" > /dev/null || failed=1
    echo "==== the installed package and outside programs on the CPU (check_install.sh)"
    scripts/check_install.sh "$B" || failed=1
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "### CPU-only MLX, $TYPE, $("$FC" --version | head -n 1)"
        echo ""
        echo "GPU-only checks skipped: **${gpuonly}**; no-device skips: **${nodevice}** (must be 0)."
        echo "The device tests ran on the CPU device; the GPU's are the release gate's (scripts/release_gate.sh)."
    } >> "$GITHUB_STEP_SUMMARY"
fi
if [[ $failed -ne 0 ]]; then
    echo "ci_cpu_job: FAILED ($TYPE, $FC_NAME)"
    exit 1
fi
echo "ci_cpu_job: passed ($TYPE, $FC_NAME)"
