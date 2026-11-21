#!/bin/bash
# scripts/build_mlx_deps.sh -- build MLX and mlx-c as shared libraries into .deps/install from local clones.
#
#   scripts/build_mlx_deps.sh [--jobs N]
#
# Exports the pinned tags with git archive (the clones are read, never checked out or changed), builds
# them with Apple's clang, and installs both under one prefix that cmake/Dependencies.cmake searches.
# Homebrew's mlx-c (brew install mlx-c) is the alternative; this script pins the versions.
#   MLX_SRC   clone of ml-explore/mlx    (default ~/src/mlx)     MLX_REF   tag (default v0.32.4)
#   MLXC_SRC  clone of ml-explore/mlx-c  (default ~/src/mlx-c)   MLXC_REF  tag (default v0.8.0)
#   PREFIX    install prefix (default <repo>/.deps/install)
# mlx-c v0.8.0 pins MLX v0.32.4 in its own CMakeLists.txt, hence the default pair. MLX's configure
# fetches its own dependencies (metal-cpp, json, fmt) and needs the network and the Metal toolchain.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh"
JOBS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j)
            [[ $# -ge 2 ]] || { echo "build_mlx_deps.sh: --jobs requires a positive integer" >&2; exit 1; }
            shift; JOBS="$1" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "build_mlx_deps.sh: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS")
MLX_SRC="${MLX_SRC:-$HOME/src/mlx}"
MLXC_SRC="${MLXC_SRC:-$HOME/src/mlx-c}"
MLX_REF="${MLX_REF:-v0.32.4}"
MLXC_REF="${MLXC_REF:-v0.8.0}"
PREFIX="${PREFIX:-$ROOT/.deps/install}"
WORK="$ROOT/.deps/work"

[[ "$(uname -s)" == Darwin ]] || { echo "build_mlx_deps.sh: macOS only (the Metal backend)" >&2; exit 1; }
xcrun -sdk macosx metal --version >/dev/null 2>&1 || {
    echo "build_mlx_deps.sh: no Metal compiler; install Xcode and run: xcodebuild -downloadComponent MetalToolchain" >&2
    exit 1; }
for src in "$MLX_SRC" "$MLXC_SRC"; do
    git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || { echo "build_mlx_deps.sh: $src is not a git clone" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK" "$PREFIX"
git -C "$MLX_SRC"  archive --prefix=mlx/   "$MLX_REF"  | tar -x -C "$WORK"
git -C "$MLXC_SRC" archive --prefix=mlx-c/ "$MLXC_REF" | tar -x -C "$WORK"

# MLX and mlx-c are C++ built with Apple's clang, whatever CC and CXX say (the Fortran side uses gcc).
CLANG_ARGS=(-DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++
            -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX="$PREFIX")
cmake -S "$WORK/mlx" -B "$WORK/build-mlx" "${CLANG_ARGS[@]}" \
    -DMLX_BUILD_TESTS=OFF -DMLX_BUILD_EXAMPLES=OFF -DMLX_BUILD_BENCHMARKS=OFF -DMLX_BUILD_PYTHON_BINDINGS=OFF
cmake --build "$WORK/build-mlx" -j "$JOBS"
cmake --install "$WORK/build-mlx"
cmake -S "$WORK/mlx-c" -B "$WORK/build-mlx-c" "${CLANG_ARGS[@]}" \
    -DMLX_C_USE_SYSTEM_MLX=ON -DMLX_C_BUILD_EXAMPLES=OFF -DCMAKE_PREFIX_PATH="$PREFIX"
cmake --build "$WORK/build-mlx-c" -j "$JOBS"
cmake --install "$WORK/build-mlx-c"

{
    echo "MLX   $MLX_REF  $(git -C "$MLX_SRC" rev-parse "$MLX_REF^{commit}")"
    echo "mlx-c $MLXC_REF $(git -C "$MLXC_SRC" rev-parse "$MLXC_REF^{commit}")"
    echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ) with $(/usr/bin/clang --version | head -n 1)"
} > "$PREFIX/mlxf_deps.txt"
cat "$PREFIX/mlxf_deps.txt"
echo "build_mlx_deps.sh: installed into $PREFIX (found by cmake/Dependencies.cmake)"
