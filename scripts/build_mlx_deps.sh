#!/bin/bash
# scripts/build_mlx_deps.sh -- build MLX and mlx-c as shared libraries into .deps/install from local clones.
#
#   scripts/build_mlx_deps.sh [--cpu-only | --cuda [--cuda-arch LIST]] [--jobs N]
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
# --cuda (Linux) builds MLX with its CUDA backend into <repo>/.deps/install-cuda (work: .deps/work-cuda), MLX and
# mlx-c with nvcc's host compiler:
#   CUDA_HOME    the toolkit, 12.8, 12.9 or 13.0 (default /usr/local/cuda; MLX 0.32.4 refuses 13.1)
#   CUDNN_ROOT   cuDNN 9 for that CUDA (include/, lib/), passed to MLX and mlx-c; unset: the system's
#   CUDAHOSTCXX  the host compiler, a g++ (default: the newest g++-N or g++ nvcc accepts, GCC 14 for 12.x and 15
#                for 13.0); the gcc beside it compiles their C
#   --cuda-arch  MLX_CUDA_ARCHITECTURES, 100a (B200), 120a (RTX-class Blackwell) or '100a;120a'; default the GPU's
#                own, required where nvidia-smi lists no GPU
# It stops before configuring when a 12.x toolkit's crt/math_functions.h clashes with glibc 2.41 or newer (the fix
# is in its message; the toolkit is never edited). libmlx.so finds the toolkit's and cuDNN's libraries through its
# run path, so only the driver's libcuda.so.1 comes from the system. Without a driver the prefix is build-only: a
# link takes libcuda.so.1 from <prefix>/cuda-stub, the toolkit's stub (mlx-fortran: -DMLXF_CUDA_STUB_DIR=<that>).
# At run time MLX compiles kernels with NVRTC, which reads the toolkit's headers from CUDA_HOME (MLX's variable)
# or /usr/local/cuda. mlxf_deps.txt records the toolkit, cuDNN, compiler, architectures, glibc and the driver.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh"
JOBS=""
CPU_ONLY=0
CUDA=0
CUDA_ARCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j)
            [[ $# -ge 2 ]] || { echo "build_mlx_deps.sh: --jobs requires a positive integer" >&2; exit 1; }
            shift; JOBS="$1" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        --cpu-only) CPU_ONLY=1 ;;
        --cuda) CUDA=1 ;;
        --cuda-arch)
            [[ $# -ge 2 ]] || { echo "build_mlx_deps.sh: --cuda-arch requires a list of architectures (100a, '100a;120a')" >&2; exit 1; }
            shift; CUDA_ARCH="$1" ;;
        --cuda-arch=*) CUDA_ARCH="${1#*=}" ;;
        -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
        *) echo "build_mlx_deps.sh: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS")
if [[ $CUDA -eq 1 && $CPU_ONLY -eq 1 ]]; then
    echo "build_mlx_deps.sh: --cuda and --cpu-only exclude each other" >&2; exit 1
fi
if [[ $CUDA -eq 0 && -n "$CUDA_ARCH" ]]; then
    echo "build_mlx_deps.sh: --cuda-arch needs --cuda" >&2; exit 1
fi
OS="$(uname -s)"
case "$OS" in
    Darwin) ;;
    Linux) CPU_ONLY=1 ;;
    *) echo "build_mlx_deps.sh: macOS or Linux only (this is $OS)" >&2; exit 1 ;;
esac
if [[ $CUDA -eq 1 ]]; then
    [[ $OS == Linux ]] || { echo "build_mlx_deps.sh: --cuda is for Linux (MLX's CUDA backend); on macOS MLX runs on Metal" >&2; exit 1; }
    CPU_ONLY=0
fi
MLX_SRC="${MLX_SRC:-$HOME/src/mlx}"
MLXC_SRC="${MLXC_SRC:-$HOME/src/mlx-c}"
MLX_REF="${MLX_REF:-v0.32.4}"
MLXC_REF="${MLXC_REF:-v0.8.0}"
if [[ $CUDA -eq 1 ]]; then
    PREFIX="${PREFIX:-$ROOT/.deps/install-cuda}"
    WORK="${WORK:-$ROOT/.deps/work-cuda}"
    METAL=OFF
elif [[ $CPU_ONLY -eq 1 ]]; then
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

die() { echo "build_mlx_deps.sh: $*" >&2; exit 1; }

# gcc_major CXX: the major version of a GCC driver (fails for anything else)
gcc_major() {
    local v
    v=$("$1" -dumpfullversion 2>/dev/null) || return 1
    v="${v%%.*}"
    [[ "$v" =~ ^[0-9]+$ ]] || return 1
    echo "$v"
}

# cuda_setup: what a --cuda build takes from the system, checked before anything is configured or removed: the
# toolkit (CUDA_HOME, CUDA_VERSION, NVCC_LINE), the host compilers (HOST_CXX, HOST_CC), glibc against the toolkit's
# math header (GLIBC), cuDNN (CUDNN_ARGS, CUDNN_LINE), the architectures (ARCH_ARGS, ARCH_LINE), the driver (DRIVER:
# 1 when libcuda.so.1 loads) and the run path of the installed libraries (RUNPATH)
cuda_setup() {
    local gcc_max c major best=-1 hdr decl clash="" minor inc="" lib d re='^[0-9]+[a-z]?(;[0-9]+[a-z]?)*$'
    local fix='s/^(extern .*[[:space:]](rsqrtf?|sinpif?|cospif?)\((double|float) x\));/\1 noexcept (true);/'
    CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
    [[ -x "$CUDA_HOME/bin/nvcc" ]] || die "no nvcc in $CUDA_HOME/bin: set CUDA_HOME to the CUDA toolkit (12.8, 12.9 or 13.0)"
    CUDA_HOME="$(cd "$CUDA_HOME" && pwd -P)"
    NVCC_LINE="$("$CUDA_HOME/bin/nvcc" --version | grep 'release' || true)"
    CUDA_VERSION="$(sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\),.*/\1/p' <<< "$NVCC_LINE")"
    case "$CUDA_VERSION" in
        12.8|12.9) gcc_max=14 ;;
        13.0) gcc_max=15 ;;
        *) die "CUDA ${CUDA_VERSION:-of unknown version} in $CUDA_HOME: --cuda takes 12.8, 12.9 or 13.0" \
               "(Blackwell needs 12.8 or newer; MLX 0.32.4 refuses 13.1)" ;;
    esac
    if [[ -n "${CUDAHOSTCXX:-}" ]]; then
        command -v "$CUDAHOSTCXX" >/dev/null 2>&1 || die "CUDAHOSTCXX=$CUDAHOSTCXX: not found"
        major=$(gcc_major "$CUDAHOSTCXX") || die "CUDAHOSTCXX=$CUDAHOSTCXX: not a GCC driver (g++ or g++-N)"
        [[ $major -le $gcc_max ]] || die "CUDAHOSTCXX=$CUDAHOSTCXX is GCC $major; nvcc $CUDA_VERSION accepts GCC $gcc_max at most"
        HOST_CXX="$CUDAHOSTCXX"
    else
        HOST_CXX=""
        for c in $(compgen -c g++- | grep -E '^g\+\+-[0-9]+$' | sort -u) g++; do
            command -v "$c" >/dev/null 2>&1 || continue
            major=$(gcc_major "$c") || continue
            if [[ $major -le $gcc_max && $major -gt $best ]]; then
                best=$major
                HOST_CXX="$c"
            fi
        done
        [[ -n "$HOST_CXX" ]] || die "no g++ of GCC $gcc_max or older for nvcc $CUDA_VERSION: install one" \
            "(Ubuntu: g++-$gcc_max) or name it in CUDAHOSTCXX"
    fi
    case "$HOST_CXX" in
        *g++*) ;;
        *) die "CUDAHOSTCXX=$HOST_CXX: name a GCC driver (g++ or g++-N)" ;;
    esac
    # absolute paths: the toolkit's bin/ goes first on PATH later
    HOST_CXX="$(command -v "$HOST_CXX")"
    HOST_CC="${HOST_CXX%g++*}gcc${HOST_CXX##*g++}"
    [[ -x "$HOST_CC" ]] || die "no $HOST_CC beside $HOST_CXX (it compiles MLX's and mlx-c's C)"
    # glibc 2.41 declares cospi, sinpi, rsqrt and their f forms noexcept; CUDA 12.x's math header does not, and nvcc
    # then fails on every file (CUDA 13.0 has the fix)
    GLIBC="$(getconf GNU_LIBC_VERSION 2>/dev/null | sed 's/^glibc //' || true)"
    minor="${GLIBC#2.}"
    minor="${minor%%.*}"
    if [[ $CUDA_VERSION == 12.* && ${GLIBC%%.*} == 2 && "$minor" =~ ^[0-9]+$ && $minor -ge 41 ]]; then
        hdr="$CUDA_HOME/include/crt/math_functions.h"
        [[ -f "$hdr" ]] || die "no $hdr in the toolkit"
        for decl in rsqrt rsqrtf sinpi sinpif cospi cospif; do
            grep -Eq "[[:space:]]$decl\((double|float) x\);" "$hdr" && clash="$clash $decl"
        done
        if [[ -n "$clash" ]]; then
            {
                echo "build_mlx_deps.sh: CUDA $CUDA_VERSION's crt/math_functions.h declares$clash without noexcept,"
                echo "which glibc $GLIBC declares noexcept: nvcc fails on every file. The fix, once, by the toolkit's"
                echo "owner (the original kept as math_functions.h.orig):"
                echo "    sed -i.orig -E '$fix' $hdr"
                echo "or CUDA 13.0, which declares them so. This script never edits the toolkit."
            } >&2
            exit 1
        fi
    fi
    if [[ -n "${CUDNN_ROOT:-}" ]]; then
        [[ -d "$CUDNN_ROOT" ]] || die "CUDNN_ROOT=$CUDNN_ROOT: no such directory"
        CUDNN_ROOT="$(cd "$CUDNN_ROOT" && pwd -P)"
        inc="$CUDNN_ROOT/include"
        lib="$CUDNN_ROOT/lib"
        [[ -d "$lib" ]] || lib="$CUDNN_ROOT/lib64"
        [[ -f "$inc/cudnn_version.h" && -d "$lib" ]] || die "CUDNN_ROOT=$CUDNN_ROOT holds no include/cudnn_version.h and lib/"
        CUDNN_ARGS=(-DCUDNN_INCLUDE_PATH="$inc" -DCUDNN_LIBRARY_PATH="$lib")
    else
        for d in "$CUDA_HOME/include" /usr/include "/usr/include/$(uname -m)-linux-gnu"; do
            if [[ -f "$d/cudnn_version.h" ]]; then inc="$d"; break; fi
        done
        [[ -n "$inc" ]] || die "no cuDNN found (cudnn_version.h): set CUDNN_ROOT to cuDNN 9 for CUDA ${CUDA_VERSION%%.*}" \
            "(include/, lib/) or install it (Ubuntu: libcudnn9-dev-cuda-${CUDA_VERSION%%.*})"
        CUDNN_ARGS=()
    fi
    CUDNN_LINE="$(awk '/#define CUDNN_MAJOR /{a=$3} /#define CUDNN_MINOR /{b=$3} /#define CUDNN_PATCHLEVEL /{c=$3}
                       END {print a "." b "." c}' "$inc/cudnn_version.h")"
    [[ "${CUDNN_LINE%%.*}" == 9 ]] || die "cuDNN $CUDNN_LINE in $inc: --cuda takes cuDNN 9 (for CUDA ${CUDA_VERSION%%.*})"
    CUDNN_LINE="$CUDNN_LINE (${CUDNN_ROOT:-from the system, $inc})"
    if [[ -n "$CUDA_ARCH" ]]; then
        CUDA_ARCH="${CUDA_ARCH//,/;}"
        [[ "$CUDA_ARCH" =~ $re ]] || die "--cuda-arch $CUDA_ARCH: a list of architectures such as 100a or '100a;120a'"
        ARCH_ARGS=(-DMLX_CUDA_ARCHITECTURES="$CUDA_ARCH")
        ARCH_LINE="$CUDA_ARCH"
    elif [[ "$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ' || true)" -gt 0 ]]; then
        # MLX takes the first visible GPU's architecture from the toolkit's __nvcc_device_query and adds a from 90
        ARCH_ARGS=()
        ARCH_LINE="native, $("$CUDA_HOME/bin/__nvcc_device_query" 2>/dev/null || true) by __nvcc_device_query"
        ARCH_LINE="$ARCH_LINE (MLX adds a from 90); GPUs: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null \
            | paste -sd, - || true)"
    else
        die "no NVIDIA GPU on this host (nvidia-smi lists none): name the architectures to build for with" \
            "--cuda-arch: 100a (B200, GB200), 120a (RTX PRO 6000 Blackwell, RTX 50 series) or '100a;120a'"
    fi
    command -v python3 >/dev/null 2>&1 || die "no python3 to look for NVIDIA's driver (libcuda.so.1) with"
    if python3 -I -c 'import ctypes; ctypes.CDLL("libcuda.so.1")' >/dev/null 2>&1; then
        DRIVER=1
    else
        DRIVER=0
        [[ -f "$CUDA_HOME/lib64/stubs/libcuda.so" ]] || die "no NVIDIA driver here and no stub $CUDA_HOME/lib64/stubs/libcuda.so to link through"
    fi
    RUNPATH="\$ORIGIN;$CUDA_HOME/lib64${CUDNN_ROOT:+;$lib}"
}

# cuda_link_check: a C program links against the installed mlx-c, the driver's libcuda.so.1 resolved through the
# toolkit's stub (STUB_DIR, <prefix>/cuda-stub, -rpath-link only) where no driver is installed; linked, never run
cuda_link_check() {
    local stub_args=()
    STUB_DIR="$(cd "$PREFIX" && pwd)/cuda-stub"
    rm -rf "$STUB_DIR"
    if [[ $DRIVER -eq 0 ]]; then
        mkdir -p "$STUB_DIR"
        ln -s "$CUDA_HOME/lib64/stubs/libcuda.so" "$STUB_DIR/libcuda.so.1"
        stub_args=("-Wl,-rpath-link,$STUB_DIR")
    fi
    printf '%s\n' '#include <stdio.h>' '#include "mlx/c/mlx.h"' 'int main(void) {' '    mlx_string s = mlx_string_new();' \
        '    mlx_version(&s);' '    printf("%s\n", mlx_string_data(s));' '    mlx_string_free(s);' '    return 0;' '}' \
        > "$WORK/link_check.c"
    "$HOST_CC" -std=c11 -I"$PREFIX/include" "$WORK/link_check.c" -o "$WORK/link_check" -L"$PREFIX/lib" -lmlxc \
        "-Wl,-rpath-link,$PREFIX/lib" ${stub_args[@]+"${stub_args[@]}"} \
        || die "a C program does not link against the installed mlx-c ($WORK/link_check.c)"
}

MLXC_ARGS=()
if [[ $CUDA -eq 1 ]]; then
    cuda_setup
    # MLX's configure runs the toolkit's __nvcc_device_query by name for the native architecture
    export PATH="$CUDA_HOME/bin:$PATH"
fi

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
    if [[ $CUDA -eq 1 ]]; then
        # nvcc's host compiler builds all of MLX and mlx-c; MLX's installed package looks for cuDNN again in every
        # consumer, so mlx-c gets the cuDNN paths too; libmlx.so's run path reaches the toolkit and cuDNN; the
        # libraries go to <prefix>/lib on every distribution (GNUInstallDirs would pick lib64 on RPM-based ones)
        COMPILER_ARGS=(-DCMAKE_C_COMPILER="$HOST_CC" -DCMAKE_CXX_COMPILER="$HOST_CXX")
        MLX_ARGS=(-DCMAKE_INSTALL_LIBDIR=lib -DMLX_BUILD_CUDA=ON -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc"
                  -DCMAKE_CUDA_HOST_COMPILER="$HOST_CXX" -DCUDAToolkit_ROOT="$CUDA_HOME"
                  ${CUDNN_ARGS[@]+"${CUDNN_ARGS[@]}"} ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"})
        MLXC_ARGS=(-DCMAKE_INSTALL_LIBDIR=lib -DCUDAToolkit_ROOT="$CUDA_HOME" ${CUDNN_ARGS[@]+"${CUDNN_ARGS[@]}"})
        PLATFORM_ARGS=("-DCMAKE_INSTALL_RPATH=$RUNPATH")
    fi
fi
BUILD_ARGS=("${COMPILER_ARGS[@]}" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX="$PREFIX"
            ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"})
cmake -S "$WORK/mlx" -B "$WORK/build-mlx" "${BUILD_ARGS[@]}" \
    -DMLX_BUILD_TESTS=OFF -DMLX_BUILD_EXAMPLES=OFF -DMLX_BUILD_BENCHMARKS=OFF -DMLX_BUILD_PYTHON_BINDINGS=OFF \
    ${MLX_ARGS[@]+"${MLX_ARGS[@]}"}
cmake --build "$WORK/build-mlx" -j "$JOBS"
cmake --install "$WORK/build-mlx"
cmake -S "$WORK/mlx-c" -B "$WORK/build-mlx-c" "${BUILD_ARGS[@]}" \
    -DMLX_C_USE_SYSTEM_MLX=ON -DMLX_C_BUILD_EXAMPLES=OFF -DCMAKE_PREFIX_PATH="$PREFIX" \
    ${MLXC_ARGS[@]+"${MLXC_ARGS[@]}"}
cmake --build "$WORK/build-mlx-c" -j "$JOBS"
cmake --install "$WORK/build-mlx-c"
[[ $CUDA -eq 0 ]] || cuda_link_check

{
    if [[ $OS == Darwin ]]; then
        echo "MLX   $MLX_REF  $(git -C "$MLX_SRC" rev-parse "$MLX_REF^{commit}")"
        echo "mlx-c $MLXC_REF $(git -C "$MLXC_SRC" rev-parse "$MLXC_REF^{commit}")"
        echo "Metal $METAL"
        echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ) with $(/usr/bin/clang --version | head -n 1)"
    elif [[ $CUDA -eq 1 ]]; then
        echo "MLX   $MLX_REF  $MLX_COMMIT"
        echo "mlx-c $MLXC_REF $MLXC_COMMIT"
        echo "Metal $METAL"
        echo "CUDA  $CUDA_VERSION ($NVCC_LINE; $CUDA_HOME)"
        echo "cuDNN $CUDNN_LINE"
        echo "host compiler $("$HOST_CXX" --version | head -n 1) ($HOST_CXX, $HOST_CC)"
        echo "architectures $ARCH_LINE"
        echo "glibc $GLIBC"
        if [[ $DRIVER -eq 1 ]]; then
            echo "driver: libcuda.so.1 loads on this host"
        else
            echo "build-only: no NVIDIA driver (libcuda.so.1) on this host; a link takes it from $STUB_DIR" \
                "(mlx-fortran: -DMLXF_CUDA_STUB_DIR=$STUB_DIR), and a program runs only where the driver is"
        fi
        echo "run time: libmlx.so runs with RUNPATH $RUNPATH; MLX's NVRTC reads the toolkit's headers from CUDA_HOME" \
            "(MLX's variable) or /usr/local/cuda"
        echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ) on Linux $(uname -m) with $("$HOST_CXX" --version | head -n 1)"
    else
        echo "MLX   $MLX_REF  $MLX_COMMIT"
        echo "mlx-c $MLXC_REF $MLXC_COMMIT"
        echo "Metal $METAL"
        echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ) on Linux $(uname -m) with $(g++ --version | head -n 1)"
    fi
} > "$PREFIX/mlxf_deps.txt"
cat "$PREFIX/mlxf_deps.txt"
if [[ $CUDA -eq 1 && $DRIVER -eq 0 ]]; then
    echo "build_mlx_deps.sh: installed into $PREFIX, build only; mlx-fortran: MLXC_ROOT=$PREFIX -DMLXF_CUDA_STUB_DIR=$STUB_DIR"
elif [[ $CUDA -eq 1 ]]; then
    echo "build_mlx_deps.sh: installed into $PREFIX; mlx-fortran: MLXC_ROOT=$PREFIX"
else
    echo "build_mlx_deps.sh: installed into $PREFIX (found by cmake/Dependencies.cmake)"
fi
