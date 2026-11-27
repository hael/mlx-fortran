#!/usr/bin/env bash
# scripts/cuda_session.sh -- the CUDA plan's measurements on one CUDA machine from one command, packed to carry home.
#
#   scripts/cuda_session.sh [--gate] [--out DIR] [--cases FILE] [--grid FILE]
#
# The experiments of doc/implementation_notes/planned/mlxf_cuda.md (decision 11), each with fixed parameters, every
# log and table under one directory (default build/cuda_session/<date>):
#   facts  the machine: nvidia-smi -q and -L, the driver, the toolkit, cuDNN, glibc, the compilers, the CPU, memory,
#          the load, the commit and its uncommitted files, the mlx-c prefix's mlxf_deps.txt
#   build  Debug and Release trees from scratch against MLXC_ROOT (warnings as errors, the tests; MLXF_REQUIRE_GPU on
#          a GPU session)
#   E1     bring-up: the fast gate in both builds, the named-only sub-suites in Release (distributed_ring aside), and
#          the CUDA sources compiled as MLX compiles them (scripts/check_cuda_sources.sh, when MLX_SRC is given)
#   E2     transfer costs: bench_user_costs suite=costs on both devices, two invocations
#   E3     parts sharing one card: scripts/run_parts.sh at 1, 2, 3, 4 and 6 parts (nthr = cores / parts) on the polar
#          table (suite time) and the shift maps (suite maps), without and with MPS when nvidia-cuda-mps-control starts
#   E4     the toys' graph forms at SIMPLE's sizes on the GPU and on the host's CPU device, two invocations each: the
#          polar table and maps, the projector (GPU only: its suite=time selects the GPU), the PCG reconstructor at
#          n = 160 and 256
#   E5     precision: the accuracy suites on the GPU
#   E6     the kernel twins: each kept kernel's form against its graph form at one process, and the polar tail's at
#          E3's best part count
# A GPU session needs nvidia-smi to list a GPU and MLXC_ROOT's MLX to be a CUDA build (its libmlx.so links
# libcuda.so.1). Elsewhere a step that needs the GPU prints a SKIP line and the CPU parts run. The polar table and
# its maps need --cases and --grid (SIMPLE's case and grid files). Every step records its wall time, the load and the
# card's processes before it (steps.tsv). The directory is packed as <dir>.tar.gz without the build trees and MLX's
# caches. --gate runs facts, build and E1 alone and exits 1 on any failure: the CUDA release check. Exit status: 1
# when the build or E1 failed, 2 on a usage error, else 0 (E2 to E6 are reported, not gated). MLX_ENABLE_TF32=0.
#   MLXC_ROOT             the mlx-c prefix (scripts/build_mlx_deps.sh --cuda; without a GPU, one whose MLX runs here)
#   CUDA_HOME             the toolkit (default /usr/local/cuda): nvcc's version, NVRTC for the source check
#   MLX_SRC               MLX's source tree or its tag's archive, for the source check (without it, skipped)
#   CUDA_VISIBLE_DEVICES  pins the card
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE=0
OUT=""
CASES=""
GRID=""
usage() { sed -n '2,5p' "$0" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gate) GATE=1 ;;
        --out) [[ $# -ge 2 ]] || usage; shift; OUT="$1" ;;
        --cases) [[ $# -ge 2 ]] || usage; shift; CASES="$1" ;;
        --grid) [[ $# -ge 2 ]] || usage; shift; GRID="$1" ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) usage ;;
    esac
    shift
done
[[ "$(uname -s)" == Linux ]] || { echo "cuda_session: Linux only" >&2; exit 2; }
[[ -n "${MLXC_ROOT:-}" && -d "$MLXC_ROOT" ]] || { echo "cuda_session: set MLXC_ROOT to the mlx-c prefix" >&2; exit 2; }
MLXC_ROOT="$(cd "$MLXC_ROOT" && pwd)"
for f in "$CASES" "$GRID"; do
    [[ -z "$f" || -f "$f" ]] || { echo "cuda_session: no file $f" >&2; exit 2; }
done
[[ -n "$CASES" ]] && CASES="$(cd "$(dirname "$CASES")" && pwd)/$(basename "$CASES")"
[[ -n "$GRID" ]] && GRID="$(cd "$(dirname "$GRID")" && pwd)/$(basename "$GRID")"
OUT="${OUT:-$ROOT/build/cuda_session/$(date +%Y-%m-%d_%H%M%S)}"
[[ -e "$OUT" ]] && { echo "cuda_session: $OUT exists" >&2; exit 2; }
mkdir -p "$OUT/tmp" || exit 2
OUT="$(cd "$OUT" && pwd)"
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
NCORES=$(nproc)
export MLX_ENABLE_TF32=0 TMPDIR="$OUT/tmp"
# CUDA numbers the cards by PCI bus, as nvidia-smi does, so that an index in CUDA_VISIBLE_DEVICES names the card the
# facts and the memory guard read
export CUDA_DEVICE_ORDER=PCI_BUS_ID
RELEASE="$OUT/build/release"
DEBUG="$OUT/build/debug"
EXE="$RELEASE/test/mlxf_test_exec"

load1() { awk '{print $1}' /proc/loadavg; }
now() { date +%s.%N; }
# a GPU session: nvidia-smi lists a GPU and the MLX under MLXC_ROOT is a CUDA build
GPU=0
if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -q '^GPU '; then
    readelf -d "$MLXC_ROOT/lib/libmlx.so" 2>/dev/null | grep -q 'libcuda\.so\.1' && GPU=1
fi
gpu_apps() { nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null | tr '\n' ';'; }

STEPS="$OUT/steps.tsv"
printf 'step\twhat\tstatus\twall_s\tload_before\tlog\n' > "$STEPS"
FAILED_E1=0
# skip STEP WHAT REASON: the step's SKIP line and its row
skip() {
    echo "SKIP $1 ($2): $3" | tee -a "$OUT/skips.txt"
    printf '%s\t%s\tskipped\t0\t%s\t%s\n' "$1" "$2" "$(load1)" "$3" >> "$STEPS"
}
# run_step STEP WHAT LOG CMD...: CMD in $OUT/STEP/run, its output in $OUT/STEP/LOG with the load and the card's
# processes before it and the load after it; a row of steps.tsv; returns CMD's status
run_step() {
    local step=$1 what=$2 log=$3 d lb t0 t1 rc st
    shift 3
    d="$OUT/$step"
    mkdir -p "$d/run"
    lb=$(load1)
    {
        echo "== $what"
        echo "start $(date '+%F %T') load: $(uptime)"
        [[ $GPU -eq 1 ]] && echo "card processes before: $(gpu_apps)"
        echo "command: $*"
    } > "$d/$log"
    t0=$(now)
    (cd "$d/run" && "$@") >> "$d/$log" 2>&1
    rc=$?
    t1=$(now)
    echo "exit $rc, end $(date '+%F %T') load: $(uptime)" >> "$d/$log"
    st=ok
    [[ $rc -eq 0 ]] || st=failed
    printf '%s\t%s\t%s\t%.1f\t%s\t%s\n' "$step" "$what" "$st" "$(awk -v a="$t0" -v b="$t1" 'BEGIN{print b - a}')" \
        "$lb" "$step/$log" >> "$STEPS"
    echo "$step: $what: $st"
    return $rc
}

# ---- facts ----
{
    echo "date: $(date '+%F %T %Z')"
    echo "host: $(hostname)"
    echo "session: $([[ $GPU -eq 1 ]] && echo GPU || echo 'CPU only (no CUDA GPU, or MLX is not a CUDA build): the GPU parts skip')"
    echo "commit: $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "uncommitted files: $(git -C "$ROOT" status --short 2>/dev/null | wc -l)"
    echo "os: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}") $(uname -r) $(uname -m)"
    echo "cpu: $(lscpu 2>/dev/null | sed -n 's/^Model name: *//p' | head -n 1), $NCORES cores"
    echo "memory: $(free -b | awk '/^Mem:/{print $2}') B"
    echo "load: $(uptime)"
    echo "glibc: $(getconf GNU_LIBC_VERSION 2>/dev/null)"
    echo "gfortran: $(gfortran --version 2>/dev/null | head -n 1)"
    echo "gcc: $(gcc --version 2>/dev/null | head -n 1)"
    echo "cmake: $(cmake --version 2>/dev/null | head -n 1)"
    echo "toolkit: $("$CUDA_HOME/bin/nvcc" --version 2>/dev/null | grep release || echo "no nvcc in $CUDA_HOME/bin")"
    echo "driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1 || true)"
    echo "gpus: $(nvidia-smi -L 2>/dev/null | tr '\n' ';' || true)"
    echo "card processes: $(gpu_apps)"
    echo "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES-unset}"
    echo "MLX_ENABLE_TF32: $MLX_ENABLE_TF32"
    echo "MLXC_ROOT: $MLXC_ROOT"
    echo "cases: ${CASES:-none}; grid: ${GRID:-none}"
    echo "---- mlxf_deps.txt"
    cat "$MLXC_ROOT/mlxf_deps.txt" 2>/dev/null || echo "none"
} > "$OUT/facts.txt"
nvidia-smi -q > "$OUT/facts_nvidia_smi_q.txt" 2>&1 || echo "no nvidia-smi" > "$OUT/facts_nvidia_smi_q.txt"
cat "$OUT/facts.txt"

# ---- build ----
REQ=OFF
[[ $GPU -eq 1 ]] && REQ=ON
build_tree() {  # build_tree TYPE TREE
    cmake -S "$ROOT" -B "$2" -DCMAKE_BUILD_TYPE="$1" -DBUILD_TESTS=ON -DFORTLS=OFF -DMLXF_WERROR=ON \
        -DMLXF_REQUIRE_GPU=$REQ -DMLXC_ROOT="$MLXC_ROOT" -DCMAKE_INSTALL_PREFIX="$2" && cmake --build "$2" -j "$NCORES"
}
run_step build "Release from scratch" release.log build_tree Release "$RELEASE" || FAILED_E1=1
run_step build "Debug from scratch" debug.log build_tree Debug "$DEBUG" || FAILED_E1=1

# ---- E1: bring-up ----
if [[ $FAILED_E1 -eq 0 ]]; then
    run_step E1 "fast gate, Release" gate_release.log "$ROOT/scripts/run_fast_gate.sh" "$RELEASE" || FAILED_E1=1
    run_step E1 "fast gate, Debug" gate_debug.log "$ROOT/scripts/run_fast_gate.sh" "$DEBUG" || FAILED_E1=1
    for pair in unit_core:recovery_half unit_kernels:polar_shiftmap_accuracy unit_kernels:reconstructor_pcg_n32 \
            unit_fast:kernel_sources; do
        run_step E1 "${pair%%:*} suite=${pair#*:}, Release" "named_${pair#*:}.log" env OMP_NUM_THREADS=1 \
            "$EXE" "test=${pair%%:*}" "suite=${pair#*:}" || FAILED_E1=1
    done
    if [[ -n "${MLX_SRC:-}" ]] && ls "$CUDA_HOME"/lib64/libnvrtc.so.[0-9]* > /dev/null 2>&1; then
        run_step E1 "CUDA sources compiled with NVRTC, Release's records" cuda_sources.log env CUDA_HOME="$CUDA_HOME" \
            "$ROOT/scripts/check_cuda_sources.sh" "$RELEASE" || FAILED_E1=1
    else
        skip E1 "CUDA sources compiled with NVRTC" "needs MLX_SRC and the toolkit's libnvrtc"
    fi
    # the fast gate's transcripts, and their counts per entry
    cp "$RELEASE/Testing/Temporary/LastTest.log" "$OUT/E1/LastTest_release.log"
    cp "$DEBUG/Testing/Temporary/LastTest.log" "$OUT/E1/LastTest_debug.log"
    python3 -I - "$OUT/E1/LastTest_release.log" "$OUT/E1/LastTest_debug.log" > "$OUT/E1/counts.tsv" <<'PYEOF'
import re
import sys
print('build\tentry\tgroups_run\tgroups_failed\tassertions\tassertions_failed\tguard_members_ok\tskips')
for path, build in zip(sys.argv[1:], ('release', 'debug')):
    rows, name = {}, None
    for line in open(path, errors='replace'):
        m = re.match(r'\d+/\d+ Testing: (\S+)', line)
        if m:
            name = m.group(1)
            rows[name] = ['', '', '', '', 0, 0]
            continue
        if name is None:
            continue
        m = re.match(r'Test groups: (\d+) run; \d+ passed; (\d+) failed', line)
        if m:
            rows[name][0:2] = m.groups()
        m = re.match(r'Assertions: (\d+) evaluated; \d+ passed; (\d+) failed', line)
        if m:
            rows[name][2:4] = m.groups()
        if re.match(r'\s+ok\s+guard_', line):
            rows[name][4] += 1
        if 'SKIP' in line:
            rows[name][5] += 1
    for name in sorted(rows):
        print('\t'.join([build, name] + [str(v) for v in rows[name]]))
PYEOF
else
    skip E1 "bring-up" "the build failed"
fi
pack() {
    local parent base
    parent=$(dirname "$OUT")
    base=$(basename "$OUT")
    (cd "$parent" && find "$base" -type f -size -50M ! -path "$base/build/*" ! -path "$base/tmp/*" -print0 \
        | tar --null -czf "$base.tar.gz" -T -)
    echo "cuda_session: packed $OUT.tar.gz"
}
if [[ $GATE -eq 1 ]]; then
    pack
    [[ $FAILED_E1 -eq 0 ]] && echo "cuda_session --gate: passed" || echo "cuda_session --gate: FAILED (steps.tsv)"
    exit $FAILED_E1
fi

if [[ ! -x "$EXE" ]]; then
    skip E2-E6 "the measurements" "no Release build"
    pack
    exit 1
fi

# ---- E2: transfer costs ----
if [[ $GPU -eq 1 ]]; then
    for k in 1 2; do run_step E2 "bench_user_costs suite=costs device=all, invocation $k" "user_costs_$k.log" \
        "$EXE" test=bench_user_costs suite=costs device=all; done
else
    for k in 1 2; do run_step E2 "bench_user_costs suite=costs device=cpu, invocation $k" "user_costs_cpu_$k.log" \
        "$EXE" test=bench_user_costs suite=costs device=cpu; done
    skip E2 "bench_user_costs on the GPU" "no CUDA GPU in this session"
fi

# ---- E3: parts sharing one card ----
BEST_N=1
series() {  # series SUITE UNIT MPS: one table of 1, 2, 3, 4 and 6 parts
    local suite=$1 unit=$2 mps=$3 n nthr keys
    keys=(cases="$CASES" passes=3)
    [[ $suite == maps ]] && keys+=(grid="$GRID" maps=screen ptiles=16)
    for n in 1 2 3 4 6; do
        nthr=$(( NCORES / n ))
        [[ $nthr -ge 1 ]] || nthr=1
        run_step E3 "$suite at $n parts, MPS $mps" "${suite}_mps_${mps}_n$n.log" env RUN_PARTS_BENCH=bench_polar_table \
            RUN_PARTS_SUITE="$suite" RUN_PARTS_UNIT="$unit" RUN_PARTS_TSV="$OUT/E3/${suite}_mps_$mps.tsv" \
            "$ROOT/scripts/run_parts.sh" "$EXE" "$n" "$nthr" "$OUT/E3/${suite}_mps_$mps/n$n" "${keys[@]}"
    done
}
if [[ $GPU -eq 0 ]]; then
    skip E3 "parts sharing one card" "no CUDA GPU in this session"
elif [[ -z "$CASES" || -z "$GRID" ]]; then
    skip E3 "parts sharing one card" "needs --cases and --grid"
else
    series time pairs off
    series maps maps off
    export CUDA_MPS_PIPE_DIRECTORY="$OUT/tmp/mps_pipe" CUDA_MPS_LOG_DIRECTORY="$OUT/E3/mps_log"
    mkdir -p "$CUDA_MPS_PIPE_DIRECTORY" "$CUDA_MPS_LOG_DIRECTORY"
    if command -v nvidia-cuda-mps-control > /dev/null 2>&1 && nvidia-cuda-mps-control -d > "$OUT/E3/mps_start.log" 2>&1; then
        series time pairs on
        series maps maps on
        echo quit | nvidia-cuda-mps-control > "$OUT/E3/mps_stop.log" 2>&1
    else
        skip E3 "parts sharing one card with MPS" "nvidia-cuda-mps-control did not start (E3/mps_start.log)"
    fi
    unset CUDA_MPS_PIPE_DIRECTORY CUDA_MPS_LOG_DIRECTORY
    # the best part count: the largest summed median rate of the polar table without MPS
    BEST_N=$(awk -F'\t' 'NR > 1 && $5 == "ok" && $24 + 0 > best {best = $24 + 0; n = $3} END {print (n + 0 > 0 ? n : 1)}' \
        "$OUT/E3/time_mps_off.tsv" 2>/dev/null || echo 1)
fi

# ---- E4: the toys' graph forms at SIMPLE's sizes ----
twice() {  # twice STEP WHAT LOG CMD...: two invocations into one run directory
    local step=$1 what=$2 log=$3 k
    shift 3
    for k in 1 2; do run_step "$step" "$what, invocation $k" "${log}_$k.log" "$@"; done
}
if [[ $GPU -eq 1 && -n "$CASES" && -n "$GRID" ]]; then
    twice E4 "polar table suite=time device=gpu" polar_time_gpu "$EXE" test=bench_polar_table suite=time \
        cases="$CASES" device=gpu passes=3
    twice E4 "polar table suite=maps device=gpu" polar_maps_gpu "$EXE" test=bench_polar_table suite=maps \
        cases="$CASES" grid="$GRID" maps=screen device=gpu passes=3
    twice E4 "polar table suite=time device=cpu" polar_time_cpu "$EXE" test=bench_polar_table suite=time \
        cases="$CASES" device=cpu nthr="$NCORES" passes=3
    twice E4 "polar table suite=maps device=cpu" polar_maps_cpu "$EXE" test=bench_polar_table suite=maps \
        cases="$CASES" grid="$GRID" maps=screen device=cpu nthr="$NCORES" passes=3
elif [[ $GPU -eq 1 ]]; then
    skip E4 "the polar table and its maps" "needs --cases and --grid"
else
    skip E4 "the polar table and its maps, both devices" "their memory budget is the GPU's: no CUDA GPU in this session"
fi
if [[ $GPU -eq 1 ]]; then
    twice E4 "projector suite=time" projector_time "$EXE" test=bench_projector suite=time passes=3
    for n in 160 256; do
        twice E4 "reconstructor n=$n device=gpu" "recon_${n}_gpu" "$EXE" test=bench_recon_pcg suite=time n=$n device=gpu
    done
else
    skip E4 "projector suite=time" "no CUDA GPU in this session"
    for n in 160 256; do skip E4 "reconstructor n=$n device=gpu" "no CUDA GPU in this session"; done
fi
skip E4 "projector on the CPU device" "its suite=time selects the GPU"
for n in 160 256; do
    twice E4 "reconstructor n=$n device=cpu" "recon_${n}_cpu" env OMP_NUM_THREADS="$NCORES" "$EXE" \
        test=bench_recon_pcg suite=time n=$n device=cpu
done

# ---- E5: precision ----
if [[ $GPU -eq 1 ]]; then
    if [[ -n "$CASES" ]]; then
        run_step E5 "polar table suite=accuracy device=gpu" polar_accuracy.log "$EXE" test=bench_polar_table \
            suite=accuracy cases="$CASES" device=gpu
    else
        skip E5 "polar table suite=accuracy" "needs --cases"
    fi
    run_step E5 "projector suite=accuracy device=gpu" projector_accuracy.log "$EXE" test=bench_projector \
        suite=accuracy device=gpu
    run_step E5 "reconstructor suite=accuracy n=160 device=gpu" recon_accuracy.log "$EXE" test=bench_recon_pcg \
        suite=accuracy n=160 device=gpu
else
    skip E5 "the accuracy suites on the GPU" "no CUDA GPU in this session"
fi

# ---- E6: the kernel twins ----
if [[ $GPU -eq 1 && -n "$CASES" ]]; then
    for tail in graph metal; do
        twice E6 "polar table suite=time tail=$tail" "polar_tail_$tail" "$EXE" test=bench_polar_table suite=time \
            cases="$CASES" device=gpu tail=$tail passes=3
    done
    for form in graph fused; do
        twice E6 "projector suite=time form=$form" "projector_$form" "$EXE" test=bench_projector suite=time \
            form=$form passes=3
    done
    if [[ $BEST_N -gt 1 ]]; then
        cp "$OUT/E3/time_mps_off.tsv" "$OUT/E6/tail_parts.tsv"
        for tail in graph metal; do
            run_step E6 "polar table tail=$tail at $BEST_N parts" "tail_${tail}_parts.log" env \
                RUN_PARTS_BENCH=bench_polar_table RUN_PARTS_SUITE=time RUN_PARTS_TSV="$OUT/E6/tail_parts.tsv" \
                "$ROOT/scripts/run_parts.sh" "$EXE" "$BEST_N" $(( NCORES / BEST_N > 0 ? NCORES / BEST_N : 1 )) \
                "$OUT/E6/tail_${tail}_n$BEST_N" cases="$CASES" passes=3 tail=$tail
        done
    else
        skip E6 "the polar tail at E3's best part count" "E3 found no count above one"
    fi
elif [[ $GPU -eq 1 ]]; then
    skip E6 "the kernel twins" "needs --cases"
else
    skip E6 "the kernel twins" "no CUDA GPU in this session"
fi

# ---- the record ----
{
    echo "cuda_session: $(date '+%F %T'), $([[ $GPU -eq 1 ]] && echo 'a GPU session' || echo 'a CPU-only session')"
    echo "E1: $([[ $FAILED_E1 -eq 0 ]] && echo passed || echo FAILED)"
    echo "steps: $(awk -F'\t' 'NR > 1 {n[$3]++} END {for (s in n) printf "%s %d; ", s, n[s]}' "$STEPS")"
} | tee "$OUT/summary.txt"
pack
exit $FAILED_E1
