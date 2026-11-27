#!/bin/bash
# scripts/build_mlx_deps.sh -- build MLX and mlx-c as shared libraries into .deps/install from local clones.
#
#   scripts/build_mlx_deps.sh [--cpu-only] [--jobs N]
#
# Exports the pinned tags with git archive (the clones are read, never checked out or changed), builds
# them with Apple's clang, and installs both under one prefix that cmake/Dependencies.cmake searches.
# Homebrew's mlx-c (brew install mlx-c) is the alternative; this script pins the versions.
#   MLX_SRC   clone of ml-explore/mlx    (default ~/src/mlx)     MLX_REF   tag (default v0.32.4)
#   MLXC_SRC  clone of ml-explore/mlx-c  (default ~/src/mlx-c)   MLXC_REF  tag (default v0.8.0)
#   PREFIX    install prefix (default <repo>/.deps/install; with --cpu-only <repo>/.deps/install-cpu)
#   WORK      scratch directory (default <repo>/.deps/work; with --cpu-only <repo>/.deps/work-cpu)
# --cpu-only builds MLX without the Metal backend (MLX_BUILD_METAL=OFF): no Xcode, no GPU; it allocates on the CPU.
# mlx-c v0.8.0 pins MLX v0.32.4 in its own CMakeLists.txt, hence the default pair. MLX's configure
# fetches its own dependencies (metal-cpp, json, fmt) and needs the network, and the Metal toolchain unless
# --cpu-only.
# On Linux MLX is built CPU-only (--cpu-only is implied) with GCC (gcc and g++ on PATH), the libraries find each
# other through $ORIGIN, and MLX needs BLAS, LAPACK and LAPACKE's headers (Ubuntu: liblapacke-dev and either
# libopenblas-dev or libblas-dev and liblapack-dev). There MLX_SRC and MLXC_SRC may also name GitHub's archive of
# the tag (https://github.com/ml-explore/<repo>/archive/refs/tags/<tag>.tar.gz); its header's commit is recorded.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh"
JOBS=""
CPU_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j)
            [[ $# -ge 2 ]] || { echo "build_mlx_deps.sh: --jobs requires a positive integer" >&2; exit 1; }
            shift; JOBS="$1" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        --cpu-only) CPU_ONLY=1 ;;
        -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
        *) echo "build_mlx_deps.sh: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS")
OS="$(uname -s)"
case "$OS" in
    Darwin) ;;
    Linux) CPU_ONLY=1 ;;
    *) echo "build_mlx_deps.sh: macOS or Linux only (this is $OS)" >&2; exit 1 ;;
esac
MLX_SRC="${MLX_SRC:-$HOME/src/mlx}"
MLXC_SRC="${MLXC_SRC:-$HOME/src/mlx-c}"
MLX_REF="${MLX_REF:-v0.32.4}"
MLXC_REF="${MLXC_REF:-v0.8.0}"
if [[ $CPU_ONLY -eq 1 ]]; then
    PREFIX="${PREFIX:-$ROOT/.deps/install-cpu}"
    WORK="${WORK:-$ROOT/.deps/work-cpu}"
    METAL=OFF
else
    PREFIX="${PREFIX:-$ROOT/.deps/install}"
    WORK="${WORK:-$ROOT/.deps/work}"
    METAL=ON
fi

if [[ $METAL == ON ]]; then
    xcrun -sdk macosx metal --version >/dev/null 2>&1 || {
        echo "build_mlx_deps.sh: no Metal compiler; install Xcode and run: xcodebuild -downloadComponent MetalToolchain" \
            "(or build without Metal: --cpu-only)" >&2
        exit 1; }
fi
for src in "$MLX_SRC" "$MLXC_SRC"; do
    [[ $OS == Linux && -f "$src" ]] && continue
    git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || { echo "build_mlx_deps.sh: $src is not a git clone" >&2; exit 1; }
done

# linux_source SRC REF NAME: the tree of tag REF as $WORK/NAME, its commit in COMMIT; from a clone (git archive) or
# from GitHub's archive of the tag (top directory NAME-<tag without v>, the commit in its pax header)
linux_source() {
    local src="$1" ref="$2" name="$3" top commit
    if [[ -f "$src" ]]; then
        read -r top commit < <(python3 -I -c 'import sys, tarfile
try:
    t = tarfile.open(sys.argv[1])
    print(t.next().name.split("/")[0], t.pax_headers.get("comment", "-"))
except Exception:
    print("- -")' "$src")
        [[ "$top" == "$name-${ref#v}" && "$commit" =~ ^[0-9a-f]{40}$ ]] || {
            echo "build_mlx_deps.sh: $src is not GitHub's archive of $name $ref" \
                "(top directory $top, commit $commit)" >&2
            exit 1; }
        mkdir -p "$WORK/$name"
        tar -xzf "$src" -C "$WORK/$name" --strip-components=1
    else
        git -C "$src" archive --prefix="$name/" "$ref" | tar -x -C "$WORK"
        commit=$(git -C "$src" rev-parse "$ref^{commit}")
    fi
    COMMIT="$commit"
}

rm -rf "$WORK"
mkdir -p "$WORK" "$PREFIX"
if [[ $OS == Darwin ]]; then
    git -C "$MLX_SRC"  archive --prefix=mlx/   "$MLX_REF"  | tar -x -C "$WORK"
    git -C "$MLXC_SRC" archive --prefix=mlx-c/ "$MLXC_REF" | tar -x -C "$WORK"
    # MLX and mlx-c are C++ built with Apple's clang, whatever CC and CXX say (the Fortran side uses gcc).
    COMPILER_ARGS=(-DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++)
    MLX_ARGS=(-DMLX_BUILD_METAL="$METAL")
    PLATFORM_ARGS=()
else
    linux_source "$MLX_SRC" "$MLX_REF" mlx
    MLX_COMMIT="$COMMIT"
    linux_source "$MLXC_SRC" "$MLXC_REF" mlx-c
    MLXC_COMMIT="$COMMIT"
    # GCC builds both, and MLX leaves Metal out by itself off Apple. mlx-c links mlx privately and an executable's
    # run path does not reach its libraries' own dependencies, so libmlxc.so finds libmlx.so beside it ($ORIGIN).
    COMPILER_ARGS=(-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++)
    MLX_ARGS=()
    PLATFORM_ARGS=('-DCMAKE_INSTALL_RPATH=$ORIGIN')
fi
BUILD_ARGS=("${COMPILER_ARGS[@]}" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX="$PREFIX"
            ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"})
cmake -S "$WORK/mlx" -B "$WORK/build-mlx" "${BUILD_ARGS[@]}" \
    -DMLX_BUILD_TESTS=OFF -DMLX_BUILD_EXAMPLES=OFF -DMLX_BUILD_BENCHMARKS=OFF -DMLX_BUILD_PYTHON_BINDINGS=OFF \
    ${MLX_ARGS[@]+"${MLX_ARGS[@]}"}
cmake --build "$WORK/build-mlx" -j "$JOBS"
cmake --install "$WORK/build-mlx"
cmake -S "$WORK/mlx-c" -B "$WORK/build-mlx-c" "${BUILD_ARGS[@]}" \
    -DMLX_C_USE_SYSTEM_MLX=ON -DMLX_C_BUILD_EXAMPLES=OFF -DCMAKE_PREFIX_PATH="$PREFIX"
cmake --build "$WORK/build-mlx-c" -j "$JOBS"
cmake --install "$WORK/build-mlx-c"

{
    if [[ $OS == Darwin ]]; then
        echo "MLX   $MLX_REF  $(git -C "$MLX_SRC" rev-parse "$MLX_REF^{commit}")"
        echo "mlx-c $MLXC_REF $(git -C "$MLXC_SRC" rev-parse "$MLXC_REF^{commit}")"
        echo "Metal $METAL"
        echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ) with $(/usr/bin/clang --version | head -n 1)"
    else
        echo "MLX   $MLX_REF  $MLX_COMMIT"
        echo "mlx-c $MLXC_REF $MLXC_COMMIT"
        echo "Metal $METAL"
        echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ) on Linux $(uname -m) with $(g++ --version | head -n 1)"
    fi
} > "$PREFIX/mlxf_deps.txt"
cat "$PREFIX/mlxf_deps.txt"
echo "build_mlx_deps.sh: installed into $PREFIX (found by cmake/Dependencies.cmake)"
