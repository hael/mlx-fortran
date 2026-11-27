#!/bin/bash
# scripts/ci_linux_job.sh -- one Linux CI job: the tree against a CPU-only MLX, its fast gate, the installed consumer,
# the library inside a parent project and the toys without MLX.
#
#   scripts/ci_linux_job.sh BUILD_TYPE FORTRAN_COMPILER [--jobs N]      (BUILD_TYPE Debug or Release)
#
# The Linux job of .github/workflows/ci.yml runs this script and nothing else. Its first part is
# scripts/ci_cpu_job.sh, as the macOS CPU-only jobs run it: the prefix is MLXC_ROOT, or .deps/install-cpu, built by
# scripts/build_mlx_deps.sh when it holds no mlx-c (on Linux MLX is built CPU-only; MLX_SRC and MLXC_SRC name the
# clones); the tree configured in build_ci_<type>/ and built; the fast gate with no no-device skip and the GPU-only
# skips counted; the install and scripts/check_install.sh. Then what scripts/release_gate.sh adds on a Mac and no
# other Linux job runs: scripts/check_embed.sh (the library inside a parent project, built with add_subdirectory)
# and scripts/check_toy_offstate.sh (the toys' host files in Debug and Release without MLX), whose table must equal
# the job's mlxf_test_exec's byte for byte in a Release job (--exec). MLX's CPU backend compiles the kernels of
# compiled graphs with g++ at run time and caches them under TMPDIR. Exit 0 when every part passes.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
positional=()
JOBS_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j) shift; JOBS_ARGS=(--jobs "${1:-}") ;;
        --jobs=*) JOBS_ARGS=(--jobs "${1#*=}") ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        -*) echo "ci_linux_job: unknown option: $1 (see --help)" >&2; exit 2 ;;
        *) positional+=("$1") ;;
    esac
    shift
done
[[ ${#positional[@]} -eq 2 ]] || { echo "usage: scripts/ci_linux_job.sh Debug|Release FORTRAN_COMPILER [--jobs N]" >&2; exit 2; }
TYPE="${positional[0]}"
FC_NAME="${positional[1]}"
case "$TYPE" in Debug|Release) ;; *) echo "ci_linux_job: build type Debug or Release, not $TYPE" >&2; exit 2 ;; esac
[[ "$(uname -s)" == Linux ]] || { echo "ci_linux_job: Linux only; on macOS run scripts/ci_cpu_job.sh" >&2; exit 2; }
FC=$(command -v "$FC_NAME") || { echo "ci_linux_job: no Fortran compiler $FC_NAME" >&2; exit 2; }
cd "$ROOT" || exit 2
export MLXC_ROOT="${MLXC_ROOT:-$ROOT/.deps/install-cpu}"
"$ROOT/scripts/ci_cpu_job.sh" "$TYPE" "$FC_NAME" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} || { echo "ci_linux_job: FAILED ($TYPE, $FC_NAME)"; exit 1; }
B="$ROOT/build_ci_$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')"
failed=0
echo "==== the library inside a parent project (check_embed.sh)"
"$ROOT/scripts/check_embed.sh" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} || failed=1
echo "==== the toys without MLX (check_toy_offstate.sh)"
offstate=(--fc "$FC")
[[ "$TYPE" == Release ]] && offstate+=(--exec "$B/test/mlxf_test_exec")
"$ROOT/scripts/check_toy_offstate.sh" "${offstate[@]}" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} || failed=1
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo ""
        echo "Linux: the library inside a parent project and the toys without MLX $([[ $failed -eq 0 ]] && echo passed || echo FAILED)."
    } >> "$GITHUB_STEP_SUMMARY"
fi
if [[ $failed -ne 0 ]]; then
    echo "ci_linux_job: FAILED ($TYPE, $FC_NAME)"
    exit 1
fi
echo "ci_linux_job: passed ($TYPE, $FC_NAME)"
