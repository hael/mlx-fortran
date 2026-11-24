#!/usr/bin/env bash
# Explicit outside-project check; never registered with CTest. Optional second argument supplies a consumer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$ROOT/build}"
CONSUMER="${2:-$ROOT/test/consumer}"
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
cp "$CONSUMER/CMakeLists.txt" "$CONSUMER/mlxf_consumer.f90" "$WORK/consumer/"
# Each check runs outside the source and producer build trees; only the package config exposes modules.
cmake -S "$WORK/consumer" -B "$WORK/consumer build" \
    "-DCMAKE_Fortran_COMPILER=$FC" "-Dmlxf_DIR=$PACKAGE" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build "$WORK/consumer build" --parallel 2
MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE OMP_THREAD_LIMIT=4 \
    "$WORK/consumer build/mlxf_consumer"
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
cp -R "$PREFIX" "$WORK/incompatible prefix"
BAD="$WORK/incompatible prefix/$LIBDIR/cmake/mlxf"
"$PY" - "$BAD/mlxfConfig.cmake" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
text, count = re.subn(r'set\(mlxf_Fortran_COMPILER_VERSION "[^"]+"\)',
                      'set(mlxf_Fortran_COMPILER_VERSION "0.0.0-incompatible")', p.read_text())
assert count == 1
p.write_text(text)
PY
if cmake -S "$WORK/consumer" -B "$WORK/incompatible build" "-DCMAKE_Fortran_COMPILER=$FC" \
        "-Dmlxf_DIR=$BAD" > "$WORK/incompatible.log" 2>&1; then
    echo "check_install: incompatible compiler metadata was accepted" >&2; exit 1
fi
"$PY" - "$WORK/incompatible.log" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert 'mlxf Fortran compiler mismatch' in text and '0.0.0-incompatible' in text, text
PY
# mlx-c ships no .pc file; mlxf.pc carries its shared link dependency and optional OpenMP link flags.
PKG_CONFIG_PATH="$PREFIX/$LIBDIR/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    "$PY" - "$FC" "$WORK" "$PREFIX" "$INCDIR" <<'PY'
from pathlib import Path
import os
import shlex
import subprocess
import sys
compiler, work, prefix, incdir = sys.argv[1:]
flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', '--static', 'mlxf'], text=True))
assert '-lmlxf' in flags and '-lmlxc' in flags, flags
assert any(f.startswith('-I') and Path(f[2:]).resolve() == Path(prefix, incdir, 'mlxf') for f in flags), flags
print('pkg-config:', flags, flush=True)
subprocess.run([compiler, str(Path(work) / 'consumer/mlxf_consumer.f90')] + flags + ['-o', str(Path(work) / 'pkg consumer')], check=True, cwd=work)
subprocess.run([str(Path(work) / 'pkg consumer')], check=True, cwd=work,
               env=dict(os.environ, MLX_ENABLE_TF32='0', OMP_NUM_THREADS='1', OMP_THREAD_LIMIT='4', OMP_WAIT_POLICY='PASSIVE'))
PY
echo "check_install: passed (consumer, isolation, compiler refusal, private modules, pkg-config)"
