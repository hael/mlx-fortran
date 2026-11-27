#!/usr/bin/env bash
# scripts/check_install.sh -- the installed package used from outside the project; never registered with CTest.
#
#   scripts/check_install.sh [BUILD [CONSUMER]] [--require-gpu]
#
# Installs the configured build BUILD (default build/) into a scratch prefix whose path holds spaces, builds the
# consumer project CONSUMER (default test/consumer/) against it with only -Dmlxf_DIR= and runs its programs (the
# consumer and the examples of README.md and doc/quickstart.md), compiles CONSUMER/mlxf_api_names.f90, which
# imports every public name of mlxf (scripts/list_public_api.py --check holds it to src/core/mlxf.f90), runs the
# installed lifetime checker (self-test, the consumer programs, a planted leak, its path resolved before mlx-c's
# package can rewrite the prefix), then
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
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
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
# from the scratch directory: mlxf_example_user_safety writes (and removes) its files in the current directory
for example in mlxf_example_differences mlxf_example_errors mlxf_example_user_safety; do
    (cd "$WORK" && "${run_env[@]}" "$WORK/consumer build/$example" "${GPU_ARGS[@]+"${GPU_ARGS[@]}"}")
done
# the installed lifetime checker, run outside the repository on the installed files alone (-I: no script
# directory, no PYTHONPATH): its self-test, the consumer programs (clean; the consumer build ran it through
# mlxf_check_lifetime too) and a planted leak, which it must report with its file, line and rule
DATADIR=$(sed -n 's/^CMAKE_INSTALL_DATADIR:PATH=//p' "$CACHE")
CHECKER="$PREFIX/${DATADIR:-share}/mlxf/check_consumer.py"
[[ -x "$CHECKER" && -f "$(dirname "$CHECKER")/mlxf_consumer_checks.py" ]] || { echo "check_install: the lifetime checker was not installed" >&2; exit 1; }
(cd "$WORK" && "$PY" -I "$CHECKER" --self-test)
(cd "$WORK" && "$PY" -I "$CHECKER" consumer/*.f90)
printf 'program leak\nuse mlxf, only: mlx_array, mlx_concatenate, exp\ntype(mlx_array) :: a, b, c\nc = mlx_concatenate([a, exp(b)])\nend program leak\n' > "$WORK/leak.f90"
if (cd "$WORK" && "$PY" -I "$CHECKER" leak.f90) > "$WORK/leak.log" 2>&1; then
    echo "check_install: the planted leak passed the installed lifetime checker" >&2; exit 1
fi
grep -q '^leak.f90:4: ctorexpr: ' "$WORK/leak.log" || { cat "$WORK/leak.log"; echo "check_install: the lifetime checker did not report the planted leak" >&2; exit 1; }
# and through mlxf_check_lifetime: a project holding the leak must fail to build
mkdir "$WORK/leak project"
cp "$WORK/leak.f90" "$WORK/leak project/"
printf 'cmake_minimum_required(VERSION 3.25)\nproject(leak LANGUAGES Fortran)\nfind_package(mlxf CONFIG REQUIRED)\nadd_executable(leak leak.f90)\ntarget_link_libraries(leak PRIVATE mlxf::mlxf)\nmlxf_check_lifetime(leak)\n' > "$WORK/leak project/CMakeLists.txt"
cmake -S "$WORK/leak project" -B "$WORK/leak build" "-DCMAKE_Fortran_COMPILER=$FC" "-Dmlxf_DIR=$PACKAGE" > "$WORK/leak build.log" 2>&1
if cmake --build "$WORK/leak build" >> "$WORK/leak build.log" 2>&1; then
    echo "check_install: a project holding the planted leak built through mlxf_check_lifetime" >&2; exit 1
fi
grep -q 'leak.f90:4: ctorexpr: ' "$WORK/leak build.log" || { cat "$WORK/leak build.log"; echo "check_install: mlxf_check_lifetime did not report the planted leak" >&2; exit 1; }
# the checker's path is resolved before any dependency is found: a nested package configuration of CMake 3.29 or
# older rewrites PACKAGE_PREFIX_DIR to its own prefix (newer CMake restores it after a nested find_package, so no
# consumer here can show it): in the installed config, mlxf_LIFETIME_CHECKER is set before the first find_package
"$PY" - "$PACKAGE/mlxfConfig.cmake" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
checker = text.find('set(mlxf_LIFETIME_CHECKER')
first = re.search(r'^\s*find_(package|dependency)\(', text, re.M)
if checker < 0 or (first is not None and first.start() < checker):
    sys.exit('check_install: the installed config resolves the lifetime checker after a dependency is found, where '
             'CMake 3.29 or older has rewritten PACKAGE_PREFIX_DIR')
PY
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
echo "check_install: passed (consumer and examples${GPU_ARGS[*]:+ (require-gpu)}, lifetime checker, isolation, compiler and mlx-c refusals, private modules, pkg-config)"
