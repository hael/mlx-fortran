#!/usr/bin/env bash
# scripts/check_install.sh -- the installed package used from outside the project; never registered with CTest.
#
#   scripts/check_install.sh [BUILD [CONSUMER]] [--require-gpu]
#
# Installs the configured build BUILD (default build/) into a scratch prefix whose path holds spaces, builds the
# consumer project CONSUMER (default test/consumer/) against it with only -Dmlxf_DIR= and runs its programs (the
# consumer and the examples of README.md and doc/quickstart.md), compiles CONSUMER/mlxf_api_names.f90, which
# imports every public name of mlxf (scripts/list_public_api.py --check holds it to src/core/mlxf.f90), then
# checks that only mlxf.mod was installed and no producer path or flag leaked, that the private modules cannot be
# imported, that a copy of the package config naming another compiler version or another mlx-c version refuses
# the consumer with its message, and that pkg-config links the consumer. Without --require-gpu the programs run
# on every device MLX can allocate on and skip where it can allocate on none; with it (the release gate) a
# missing GPU fails them. MLXF_INSTALL_CHECK_KEEP=1 keeps the scratch directory.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
positional=()
GPU_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --require-gpu) GPU_ARGS=(require-gpu) ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        -*) echo "check_install: unknown option: $arg (see --help)" >&2; exit 2 ;;
        *) positional+=("$arg") ;;
    esac
done
BUILD="${positional[0]:-$ROOT/build}"
CONSUMER="${positional[1]:-$ROOT/test/consumer}"
BUILD="$(cd "$BUILD" && pwd)"
CONSUMER="$(cd "$CONSUMER" && pwd)"
CACHE="$BUILD/CMakeCache.txt"
[[ -f "$CACHE" ]] || { echo "check_install: no configured build at $BUILD" >&2; exit 2; }
FC=$(sed -n 's/^CMAKE_Fortran_COMPILER:[^=]*=//p' "$CACHE")
LIBDIR=$(sed -n 's/^CMAKE_INSTALL_LIBDIR:PATH=//p' "$CACHE")
INCDIR=$(sed -n 's/^CMAKE_INSTALL_INCLUDEDIR:PATH=//p' "$CACHE")
PY=$(sed -n 's/^MLXF_PYTHON3:INTERNAL=//p' "$CACHE")
[[ -x "$FC" && -x "$PY" && -n "$LIBDIR" && -n "$INCDIR" ]] || { echo "check_install: missing build metadata" >&2; exit 2; }
case "$LIBDIR:$INCDIR" in /*|*:/*|*..*) echo "check_install: use relative install directories without .." >&2; exit 2 ;; esac
command -v pkg-config >/dev/null || { echo "check_install: pkg-config is needed for the metadata check" >&2; exit 2; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mlxf install.XXXXXX")
cleanup() {
    if [[ "${MLXF_INSTALL_CHECK_KEEP:-0}" == 1 ]]; then
        echo "check_install: retained $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT
PREFIX="$WORK/prefix with spaces"
PACKAGE="$PREFIX/$LIBDIR/cmake/mlxf"
cmake --install "$BUILD" --prefix "$PREFIX" --component mlxf
mkdir "$WORK/consumer"
cp "$CONSUMER/CMakeLists.txt" "$CONSUMER"/*.f90 "$WORK/consumer/"
# Each check runs outside the source and producer build trees; only the package config exposes modules.
cmake -S "$WORK/consumer" -B "$WORK/consumer build" \
    "-DCMAKE_Fortran_COMPILER=$FC" "-Dmlxf_DIR=$PACKAGE" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build "$WORK/consumer build" --parallel 2
# the public API: every name the source declares public, imported from the installed module
"$PY" "$ROOT/scripts/list_public_api.py" "$ROOT" --check
(cd "$WORK" && "$FC" "-I$PREFIX/$INCDIR/mlxf" -c "$WORK/consumer/mlxf_api_names.f90" -o api_names.o) \
    || { echo "check_install: the installed mlxf does not export every public name" >&2; exit 1; }
run_env=(env MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE OMP_THREAD_LIMIT=4)
"${run_env[@]}" "$WORK/consumer build/mlxf_consumer" "${GPU_ARGS[@]+"${GPU_ARGS[@]}"}" | tee "$WORK/consumer.log"
# the examples the documents show. The first, the README's program, takes no argument and runs on MLX's default
# device: it runs where the consumer did not skip, and under --require-gpu that device must be the GPU
if ! grep -q '^SKIP' "$WORK/consumer.log"; then
    "${run_env[@]}" "$WORK/consumer build/mlxf_example_first" | tee "$WORK/example_first.log"
    if [[ ${#GPU_ARGS[@]} -gt 0 ]] && ! grep -q 'default device gpu' "$WORK/example_first.log"; then
        echo "check_install: mlxf_example_first did not run on the GPU" >&2; exit 1
    fi
fi
for example in mlxf_example_differences mlxf_example_errors; do
    "${run_env[@]}" "$WORK/consumer build/$example" "${GPU_ARGS[@]+"${GPU_ARGS[@]}"}"
done
"$PY" - "$PREFIX" "$BUILD" "$ROOT" "$WORK/consumer build/compile_commands.json" <<'PY'
from pathlib import Path
import sys
prefix, build, root, commands = map(Path, sys.argv[1:])
modules = sorted(p.name for p in prefix.rglob('*.mod'))
assert modules == ['mlxf.mod'], modules
assert not list(prefix.rglob('*.smod')), 'an internal submodule was installed'
for p in prefix.rglob('*'):
    if p.is_file() and p.suffix in ('.cmake', '.pc'):
        text = p.read_text()
        assert str(build) not in text, (p, 'producer build path leaked')
        assert str(root) not in text, (p, 'source path leaked')
        assert 'mlxf_build_flags' not in text, (p, 'private producer target leaked')
text = commands.read_text()
for flag in ['-Werror', '-fcheck=', '-ffpe-trap=', '-finit-real=', '-Wall', '-Wextra']:
    assert flag not in text, (flag, 'producer compile flags leaked')
assert str(build) not in text and str(root) not in text, 'consumer uses producer paths'
PY
for module in mlxf_array mlxf_c_array; do
    printf 'program internal_probe\nuse %s\nend program internal_probe\n' "$module" > "$WORK/internal.f90"
    if (cd "$WORK" && "$FC" "-I$PREFIX/$INCDIR/mlxf" -c internal.f90) > "$WORK/$module.log" 2>&1; then
        echo "check_install: internal module $module was importable" >&2; exit 1
    fi
    "$PY" - "$WORK/$module.log" "$module" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text().lower()
assert 'cannot open module file' in text and sys.argv[2] + '.mod' in text, text
PY
done
# a copy of the package config with one recorded fact planted, which the consumer's configure must refuse
refused() {
    local name="$1" pattern="$2"
    shift 2
    cp -R "$PREFIX" "$WORK/$name prefix"
    local bad="$WORK/$name prefix/$LIBDIR/cmake/mlxf"
    "$PY" - "$bad/mlxfConfig.cmake" "$pattern" <<'PY'
from pathlib import Path
import re
import sys
p, name = Path(sys.argv[1]), sys.argv[2]
text, count = re.subn(r'set\(%s "[^"]+"\)' % name, 'set(%s "0.0.0-incompatible")' % name, p.read_text())
assert count == 1, (name, count)
p.write_text(text)
PY
    if cmake -S "$WORK/consumer" -B "$WORK/$name build" "-DCMAKE_Fortran_COMPILER=$FC" \
            "-Dmlxf_DIR=$bad" > "$WORK/$name.log" 2>&1; then
        echo "check_install: a package config naming another $name was accepted" >&2; exit 1
    fi
    "$PY" - "$WORK/$name.log" "$@" <<'PY'
from pathlib import Path
import sys
text = ' '.join(Path(sys.argv[1]).read_text().split())
for want in sys.argv[2:]:
    assert want in text, (want, text)
PY
}
refused compiler mlxf_Fortran_COMPILER_VERSION 'mlxf Fortran compiler mismatch' 0.0.0-incompatible
MLXC_BUILT=$(sed -n 's/^set(mlxf_MLXC_VERSION "\([^"]*\)")$/\1/p' "$PACKAGE/mlxfConfig.cmake")
[[ -n "$MLXC_BUILT" ]] || { echo "check_install: the package config records no mlx-c version" >&2; exit 1; }
refused mlx-c mlxf_MLXC_VERSION "mlxf mlx-c mismatch: built with 0.0.0-incompatible; found ${MLXC_BUILT}"
# mlx-c ships no .pc file; mlxf.pc carries its shared link dependency, its version and optional OpenMP flags.
PKG_CONFIG_PATH="$PREFIX/$LIBDIR/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    "$PY" - "$FC" "$WORK" "$PREFIX" "$INCDIR" "$MLXC_BUILT" "${GPU_ARGS[@]+"${GPU_ARGS[@]}"}" <<'PY'
from pathlib import Path
import os
import shlex
import subprocess
import sys
compiler, work, prefix, incdir, mlxc = sys.argv[1:6]
flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', '--static', 'mlxf'], text=True))
assert '-lmlxf' in flags and '-lmlxc' in flags, flags
recorded = subprocess.check_output(['pkg-config', '--variable=mlxc_version', 'mlxf'], text=True).strip()
assert recorded == mlxc, (recorded, mlxc)
# both sides resolved: on macOS /var/folders and /private/var/folders name one directory
want = Path(prefix, incdir, 'mlxf').resolve()
assert any(f.startswith('-I') and Path(f[2:]).resolve() == want for f in flags), (flags, str(want))
print('pkg-config:', flags, 'mlxc_version=' + recorded, flush=True)
subprocess.run([compiler, str(Path(work) / 'consumer/mlxf_consumer.f90')] + flags + ['-o', str(Path(work) / 'pkg consumer')], check=True, cwd=work)
subprocess.run([str(Path(work) / 'pkg consumer')] + sys.argv[6:], check=True, cwd=work,
               env=dict(os.environ, MLX_ENABLE_TF32='0', OMP_NUM_THREADS='1', OMP_THREAD_LIMIT='4', OMP_WAIT_POLICY='PASSIVE'))
PY
echo "check_install: passed (consumer and examples${GPU_ARGS[*]:+ (require-gpu)}, isolation, compiler and mlx-c refusals, private modules, pkg-config)"
