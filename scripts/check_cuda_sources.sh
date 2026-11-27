#!/usr/bin/env bash
# scripts/check_cuda_sources.sh -- the CUDA sources of the tree's custom kernels, compiled as MLX compiles them, on
# a machine without a GPU (Linux, a CUDA toolkit; never registered with CTest).
#
#   scripts/check_cuda_sources.sh BUILD [--plant]
#
# BUILD's mlxf_test_exec writes one record per kernel application of the tests (test=unit_fast suite=kernel_sources
# records=<dir>: the spec, and the dtypes and ranks of its inputs). Any build whose mlxf_test_exec runs here serves (on
# a host without NVIDIA's driver, the CPU-only one: the records need no GPU). Each CUDA source is wrapped as MLX
# 0.32.4 wraps it (mlx/backend/cuda/custom_kernel.cpp: the function named as MLX names it, inputs as const T*, the
# shape, strides and rank of an input whose names the source uses, outputs as T*, templates as constexpr locals and
# using aliases, cooperative_groups as cg) and compiled with NVRTC as MLX compiles it at run time
# (mlx/backend/cuda/jit_module.cpp: --device-as-default-execution-space, MLX's device headers, CCCL, the toolkit's
# headers) for each architecture: compiled, not run. A record that expects no compilation must fail to compile. A
# failure MLX causes is reported as MLX's only when the same source compiles under a valid function name: a negative
# integer template argument puts '-' into the name MLX gives the function (doc/collaboration/apple_questions.md,
# item 40), and on a GPU that application fails until MLX changes. The wrapping is MLX 0.32.4's: another MLX, in
# MLX_SRC or under the build's mlx-c, is refused until the wrapping here is compared with its source. --plant adds a
# record expected to compile whose source does not: the check must then fail.
#   CUDA_HOME   the toolkit (default /usr/local/cuda): libnvrtc, its builtins and the CUDA headers
#   MLX_SRC     MLX's source tree at the pinned tag, or GitHub's archive of the tag: its device headers
#   CUDA_ARCHS  the architectures (default "sm_100a sm_120a")
# MLX's CCCL (include/cccl, absent from a CPU-only prefix: then the toolkit's) and mlx-c's dtype codes come from the
# mlx-c BUILD was configured with. Python 3.7, standard library only.
set -euo pipefail
WRAPPED_MLX=0.32.4
BUILD=""
PLANT=0
for arg in "$@"; do
    case "$arg" in
        --plant) PLANT=1 ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        -*) echo "check_cuda_sources: unknown option: $arg (see --help)" >&2; exit 2 ;;
        *) BUILD="$arg" ;;
    esac
done
[[ -n "$BUILD" ]] || { echo "check_cuda_sources: name a build tree (see --help)" >&2; exit 2; }
BUILD="$(cd "$BUILD" && pwd)"
EXE="$BUILD/test/mlxf_test_exec"
[[ -x "$EXE" ]] || { echo "check_cuda_sources: no $EXE (a build with BUILD_TESTS=ON)" >&2; exit 2; }
[[ -f "$BUILD/CMakeCache.txt" ]] || { echo "check_cuda_sources: no CMakeCache.txt in $BUILD" >&2; exit 2; }
MLXC_DIR=$(sed -n 's/^MLXC_DIR:PATH=//p' "$BUILD/CMakeCache.txt")
[[ -n "$MLXC_DIR" ]] || { echo "check_cuda_sources: no MLXC_DIR in $BUILD/CMakeCache.txt" >&2; exit 2; }
MLXC_PREFIX="$(cd "$MLXC_DIR/../../.." && pwd)"
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
NVRTC=$(ls "$CUDA_HOME"/lib64/libnvrtc.so.[0-9]* 2>/dev/null | head -n 1 || true)
[[ -n "$NVRTC" ]] || { echo "check_cuda_sources: no libnvrtc under $CUDA_HOME/lib64: set CUDA_HOME to the toolkit" >&2; exit 2; }
[[ -n "${MLX_SRC:-}" ]] || { echo "check_cuda_sources: set MLX_SRC to MLX's source tree or its tag's archive" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check_cuda_sources.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
if [[ -f "$MLX_SRC" ]]; then
    mkdir -p "$WORK/mlx"
    tar -xzf "$MLX_SRC" -C "$WORK/mlx" --strip-components=1 --wildcards '*/mlx/backend/cuda/device/*' '*/mlx/version.h'
    MLX_TREE="$WORK/mlx"
else
    MLX_TREE="$(cd "$MLX_SRC" && pwd)"
fi
[[ -f "$MLX_TREE/mlx/backend/cuda/device/utils.cuh" ]] || { echo "check_cuda_sources: no MLX device headers in $MLX_SRC" >&2; exit 2; }
SRC_VERSION=$(awk '/#define MLX_VERSION_(MAJOR|MINOR|PATCH) /{v = v (v == "" ? "" : ".") $3} END {print v}' "$MLX_TREE/mlx/version.h")
LINKED_VERSION=$(sed -n 's/^set(PACKAGE_VERSION "\(.*\)")$/\1/p' "$MLXC_PREFIX/share/cmake/MLX/MLXConfigVersion.cmake" 2>/dev/null || true)
for v in "$SRC_VERSION" "$LINKED_VERSION"; do
    [[ "$v" == "$WRAPPED_MLX" ]] || { echo "check_cuda_sources: MLX $v (MLX_SRC $SRC_VERSION, linked ${LINKED_VERSION:-unknown});" \
        "the wrapping here is MLX $WRAPPED_MLX's: compare it with mlx/backend/cuda/custom_kernel.cpp first" >&2; exit 2; }
done
mkdir -p "$WORK/records" "$WORK/run"
(cd "$WORK/run" && env MLX_ENABLE_TF32=0 OMP_NUM_THREADS=1 "$EXE" test=unit_fast suite=kernel_sources \
    "records=$WORK/records" > "$WORK/records.log" 2>&1) \
    || { cat "$WORK/records.log"; echo "check_cuda_sources: the sub-suite kernel_sources failed" >&2; exit 1; }
grep -E 'kernel applications recorded|PASS|FAIL' "$WORK/records.log" | sed 's/^/    /'
CCCL="$MLXC_PREFIX/include/cccl"
[[ -d "$CCCL" ]] || CCCL=""
LD_LIBRARY_PATH="$CUDA_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" python3 -I - "$WORK/records" "$NVRTC" \
    "$MLX_TREE" "$MLXC_PREFIX" "$CCCL" "$CUDA_HOME" "${CUDA_ARCHS:-sm_100a sm_120a}" "$PLANT" <<'PYEOF'
"""Wraps every record's CUDA source as MLX 0.32.4 does and compiles it with NVRTC; prints one line per record and
architecture, and exits 1 when a record does not end as it expects."""
import ctypes
import glob
import os
import re
import sys

records, nvrtc_path, mlx_tree, prefix, cccl, cuda_home, archs, plant = sys.argv[1:9]
archs = archs.split()

# mlx-c's dtype codes, in the order of its enum; each with the CUDA type of MLX's dtype_to_cuda_type and the name of
# its get_type_string (the hash of a dtype template argument)
CUDA_TYPES = {'BOOL': ('bool', 'bool'), 'UINT8': ('uint8_t', 'uint8_t'), 'UINT16': ('uint16_t', 'uint16_t'),
              'UINT32': ('uint32_t', 'uint32_t'), 'UINT64': ('uint64_t', 'uint64_t'), 'INT8': ('int8_t', 'int8_t'),
              'INT16': ('int16_t', 'int16_t'), 'INT32': ('int32_t', 'int32_t'), 'INT64': ('int64_t', 'int64_t'),
              'FLOAT16': ('__half', 'float16_t'), 'FLOAT32': ('float', 'float'), 'FLOAT64': ('double', 'double'),
              'BFLOAT16': ('__nv_bfloat16', 'bfloat16_t'),
              'COMPLEX64': ('mlx::core::cu::complex64_t', 'complex64_t')}
enum = open(os.path.join(prefix, 'include', 'mlx', 'c', 'array.h')).read()
body = re.search(r'typedef\s+enum\s+mlx_dtype_\s*\{([^}]*)\}', enum).group(1)
codes = [n.strip()[len('MLX_'):] for n in body.split(',') if n.strip()]
DTYPES = {i: CUDA_TYPES[name] for i, name in enumerate(codes)}

DEFAULT_HEADER = '\n#include "mlx/backend/cuda/device/utils.cuh"\n\n#include <cooperative_groups.h>\n\n'


def parse(path):
    # bytes: the Fortran writer counts the header's and the source's length in bytes
    data = open(path, 'rb').read()
    rec = {'inputs': [], 'outputs': [], 'templates': [], 'file': os.path.basename(path)}
    pos = 0
    while True:
        end = data.index(b'\n', pos)
        line, pos = data[pos:end].decode('utf-8'), end + 1
        key, _, rest = line.partition(' ')
        if key == 'name':
            rec['name'] = rest
        elif key == 'expect':
            rec['expect'] = rest
        elif key == 'input':
            name, dtype, rank = rest.split()
            rec['inputs'].append((name, int(dtype), int(rank)))
        elif key == 'output':
            name, dtype = rest.split()
            rec['outputs'].append((name, int(dtype)))
        elif key == 'template':
            kind, name, value = rest.split()
            rec['templates'].append((kind, name, value))
        elif key == 'shared_memory':
            rec['shared_memory'] = int(rest)
        elif key in ('header', 'source'):
            n = int(rest)
            rec[key] = data[pos:pos + n].decode('utf-8')
            pos += n + 1
            if key == 'source':
                return rec


def template_hash(templates):
    # MLX's template_arguments_hash (CUDA): "_<int>", "_t"/"_f", "_<type string>", nothing removed
    out = ''
    for kind, _, value in templates:
        if kind == 'int':
            out += '_%d' % int(value)
        elif kind == 'bool':
            out += '_t' if value == 'T' else '_f'
        else:
            out += '_' + DTYPES[int(value)][1]
    return out


def wrap(rec, func):
    # MLX's build_kernel (CUDA)
    src = DEFAULT_HEADER + rec['header'] + 'namespace mlx::core::cu {\n\nnamespace cg = cooperative_groups;\n\n'
    src += '__global__ void ' + func + '(\n'
    for name, dtype, rank in rec['inputs']:
        src += '    const %s* %s,\n' % (DTYPES[dtype][0], name)
        if rank > 0:
            if name + '_shape' in rec['source']:
                src += '    const __grid_constant__ Shape %s_shape,\n' % name
            if name + '_strides' in rec['source']:
                src += '    const __grid_constant__ Strides %s_strides,\n' % name
            if name + '_ndim' in rec['source']:
                src += '    const __grid_constant__ int %s_ndim,\n' % name
    for i, (name, dtype) in enumerate(rec['outputs']):
        src += '    %s* %s' % (DTYPES[dtype][0], name)
        src += ',\n' if i < len(rec['outputs']) - 1 else ') {\n'
    if rec['templates']:
        for kind, name, value in rec['templates']:
            if kind == 'int':
                src += '  constexpr int %s = %d;\n' % (name, int(value))
            elif kind == 'bool':
                src += '  constexpr bool %s = %s;\n' % (name, 'true' if value == 'T' else 'false')
            else:
                src += '  using %s = %s;\n' % (name, DTYPES[int(value)][0])
        src += '\n'
    return src + rec['source'] + '\n}\n\n} // namespace mlx::core::cu\n'


nvrtc = ctypes.CDLL(nvrtc_path)
INCLUDES = [mlx_tree, os.path.join(prefix, 'include')] + ([cccl] if cccl else []) + [os.path.join(cuda_home, 'include')]


def compile_source(src, func, arch):
    """NVRTC with MLX's options; returns (ok, log)."""
    prog = ctypes.c_void_p()
    if nvrtc.nvrtcCreateProgram(ctypes.byref(prog), src.encode(), (func + '.cu').encode(), 0, None, None) != 0:
        return False, 'nvrtcCreateProgram failed'
    name = 'mlx::core::cu::' + func
    nvrtc.nvrtcAddNameExpression(prog, name.encode())
    args = [b'--device-as-default-execution-space', ('--gpu-architecture=' + arch).encode()]
    args += [('--include-path=' + p).encode() for p in INCLUDES]
    argv = (ctypes.c_char_p * len(args))(*args)
    result = nvrtc.nvrtcCompileProgram(prog, len(args), argv)
    size = ctypes.c_size_t()
    nvrtc.nvrtcGetProgramLogSize(prog, ctypes.byref(size))
    log = ctypes.create_string_buffer(size.value + 1)
    nvrtc.nvrtcGetProgramLog(prog, log)
    nvrtc.nvrtcDestroyProgram(ctypes.byref(prog))
    return result == 0, log.value.decode(errors='replace')


recs = [parse(p) for p in sorted(glob.glob(os.path.join(records, '*.rec')),
                                 key=lambda p: int(re.findall(r'\d+', os.path.basename(p))[-1]))]
if recs and plant == '1':
    planted = dict(recs[0])
    planted.update(name='mlxf_plant_does_not_compile', expect='compile', file='plant',
                   source=recs[0]['source'] + '\nno_such_function(no_such_buffer);')
    recs.append(planted)
if not recs:
    print('check_cuda_sources: no record written')
    sys.exit(1)
failed = 0
for rec in recs:
    func = 'custom_kernel_' + rec['name'] + template_hash(rec['templates'])
    for arch in archs:
        ok, log = compile_source(wrap(rec, func), func, arch)
        if rec['expect'] == 'fail':
            verdict = 'fails to compile, as expected' if not ok else 'COMPILES, BUT IS EXPECTED TO FAIL'
            bad = ok
        elif ok:
            verdict, bad = 'compiled', False
        elif '-' in func:
            valid = re.sub(r'[^A-Za-z0-9_]', '_', func)
            ok2, log2 = compile_source(wrap(rec, valid), valid, arch)
            if ok2:
                verdict = ("MLX's: the name MLX gives the function, %s, is not an identifier (apple_questions.md, "
                           "item 40), so this application fails on a CUDA GPU; the source compiles as %s" % (func, valid))
                bad = False
            else:
                verdict, bad, log = 'FAILED to compile', True, log2
        else:
            verdict, bad = 'FAILED to compile', True
        failed += bad
        print('%-34s %-8s %s' % (rec['name'] + ' (' + rec['file'] + ')', arch, verdict))
        if bad:
            print('\n'.join('    | ' + l for l in log.strip().splitlines()[:12]))
total = len(recs) * len(archs)
print('check_cuda_sources: %d records x %d architectures, compiled with NVRTC, not run: %s' %
      (len(recs), len(archs), 'every one as expected' if not failed else '%d of %d NOT as expected' % (failed, total)))
sys.exit(1 if failed else 0)
PYEOF
