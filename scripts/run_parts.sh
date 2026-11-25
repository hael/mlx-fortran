#!/bin/bash
# scripts/run_parts.sh -- one split of the dense table among simultaneous part processes, measured.
#
#   scripts/run_parts.sh EXEC NPARTS NTHR OUTDIR cases=FILE [key=value ...]
#
# Starts NPARTS processes of `EXEC test=bench_polar_table suite=time nparts=NPARTS part=<p> nthr=NTHR` (plus
# the keys given: cases=, case=, bt=, rt=), each in OUTDIR/part_<p> with OMP_NUM_THREADS=NTHR and, unless it
# is set, MLX_ENABLE_TF32=0. Every process makes its data and writes its ready file; when all are ready the
# go file is created and they score together. One row of the series table (RUN_PARTS_TSV, default
# OUTDIR/../run_parts.tsv) records the split:
#   the seconds from go to the last exit, the processes' rates (pairs per second, best of 3) and their sum,
#   the largest and the summed peak footprint, maximum resident size, MLX peak and MLX cache, the machine's
#   lowest free and available memory (sampled once a second from go), the load before and after, the status.
# OUTDIR/summary.txt has the same per process, with each digest line.
#
# Before anything starts:
#   the guard   a split above one process is not run when its summed footprint, predicted from the series
#               table's earlier rows, is above RUN_PARTS_MEM_SHARE (default 0.8) of the machine's memory:
#               from one measured split, NPARTS times its largest process; from two or more, NPARTS times
#               the line through the two finest splits' largest processes against the share 1/n. With no
#               earlier row it is not run either. Status not_run, exit 3.
#   quiet       another mlxf_test_exec, cmake or gfortran process on the machine: nothing is started,
#               exit 4. One that appears during the run gives the row the status discarded: repeat it.
#   the load    waits until the one-minute load is at most RUN_PARTS_LOAD (default 2), for at most
#               RUN_PARTS_LOAD_WAIT seconds (default 1800); then it runs and records the load.
# Exit status: 0 measured, 1 a process failed, 2 usage, 3 not run by the guard, 4 not quiet or discarded.
# Processes that are not this script's are never touched. macOS and Linux.
set -u
usage() { sed -n '2,5p' "$0" >&2; exit 2; }
[ $# -ge 5 ] || usage
EXEC=$1; NPARTS=$2; NTHR=$3; OUTDIR=$4; shift 4
case "$NPARTS$NTHR" in *[!0-9]*|'') usage ;; esac
[ "$NPARTS" -ge 1 ] && [ "$NTHR" -ge 1 ] || usage
[ -x "$EXEC" ] || { echo "run_parts: no executable $EXEC" >&2; exit 2; }
case "$EXEC" in /*) ;; *) EXEC="$PWD/$EXEC" ;; esac
KEYS=()
for kv in "$@"; do
    case "$kv" in
        nparts=*|part=*|nthr=*|go=*|test=*|suite=*) echo "run_parts: $kv is set by the launcher" >&2; exit 2 ;;
        cases=/*) KEYS+=("$kv") ;;
        cases=*) KEYS+=("cases=$PWD/${kv#cases=}") ;;
        *=*) KEYS+=("$kv") ;;
        *) usage ;;
    esac
done
[ -e "$OUTDIR" ] && { echo "run_parts: $OUTDIR exists" >&2; exit 2; }
mkdir -p "$OUTDIR" || exit 2
OUTDIR="$(cd "$OUTDIR" && pwd)"
TSV="${RUN_PARTS_TSV:-$(dirname "$OUTDIR")/run_parts.tsv}"
SHARE="${RUN_PARTS_MEM_SHARE:-0.8}"
LOAD_MAX="${RUN_PARTS_LOAD:-2}"
LOAD_WAIT="${RUN_PARTS_LOAD_WAIT:-1800}"
OS=$(uname -s)
TAB=$(printf '\t')

now() { python3 -c 'import time; print("%.3f" % time.time())'; }
load1() {
    if [ "$OS" = Darwin ]; then sysctl -n vm.loadavg | awk '{print $2}'; else awk '{print $1}' /proc/loadavg; fi
}
mem_total() {
    if [ "$OS" = Darwin ]; then sysctl -n hw.memsize; else awk '/^MemTotal:/{printf "%.0f\n", $2 * 1024}' /proc/meminfo; fi
}
# "free available" in bytes: free is what nothing uses; available adds what the system gives back on demand
mem_free() {
    if [ "$OS" = Darwin ]; then
        vm_stat | awk '/page size of/{ps = $8}
            /^Pages free:/{f = $3} /^Pages speculative:/{s = $3} /^Pages inactive:/{i = $3} /^Pages purgeable:/{p = $3}
            END{printf "%.0f %.0f\n", (f + s) * ps, (f + s + i + p) * ps}'
    else
        awk '/^MemFree:/{f = $2} /^MemAvailable:/{a = $2} END{printf "%.0f %.0f\n", f * 1024, a * 1024}' /proc/meminfo
    fi
}
# the processes that make a measurement unusable, other than this launcher's own NPARTS
foreign() {
    local n_exec n_build
    n_exec=$(pgrep -x mlxf_test_exec | wc -l | tr -d ' ')
    n_build=$( (pgrep -x cmake; pgrep -x gfortran; pgrep -x f951) | wc -l | tr -d ' ')
    echo $(( n_exec - $1 + n_build ))
}
header() {
    [ -s "$TSV" ] && return
    printf 'date\tdir\tnparts\tnthr\tstatus\tgo_to_last_exit_s\tsum_pairs_per_s\tmin_pairs_per_s\tmax_pairs_per_s\tmax_footprint_B\tsum_footprint_B\tmax_rss_B\tsum_rss_B\tmax_mlx_peak_B\tsum_mlx_peak_B\tsum_mlx_cache_B\tmin_free_B\tmin_available_B\tmem_total_B\tpredicted_sum_footprint_B\tload_before\tload_after\tkeys\n' > "$TSV"
}
row() {
    header
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$OUTDIR" "$NPARTS" "$NTHR" "$1" >> "$TSV"
}

# a row without measurements: status, predicted footprint, load before
row_unmeasured() {
    row "$1$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TAB$TOTAL$TAB$2$TAB$3$TAB$TAB${KEYS[*]}"
}

# ---- the guard ----
TOTAL=$(mem_total)
PRED=-1
if [ "$NPARTS" -gt 1 ]; then
    [ -s "$TSV" ] && PRED=$(awk -F'\t' -v N="$NPARTS" '
        NR > 1 && $5 == "ok" && $3 + 0 < N && $10 + 0 > 0 { if ($10 + 0 > fp[$3 + 0]) fp[$3 + 0] = $10 + 0 }
        END {
            a = 0; b = 0
            for (n in fp) { n += 0; if (n > b) { a = b; b = n } else if (n > a) a = n }
            if (b == 0) { print -1; exit }
            f = fp[b]
            if (a > 0) f = fp[a] + (fp[b] - fp[a]) * (1 / N - 1 / a) / (1 / b - 1 / a)
            printf "%.0f\n", N * f
        }' "$TSV")
    if [ "$PRED" = -1 ]; then
        echo "run_parts: no measured split in $TSV to predict $NPARTS processes from: not run" >&2
        row_unmeasured not_run -1 ""
        exit 3
    fi
    if awk -v p="$PRED" -v t="$TOTAL" -v s="$SHARE" 'BEGIN{exit !(p > s * t)}'; then
        echo "run_parts: $NPARTS processes are predicted to hold $PRED B, above $SHARE of $TOTAL B: not run" >&2
        row_unmeasured not_run "$PRED" ""
        exit 3
    fi
fi

# ---- quiet, and the load ----
if [ "$(foreign 0)" -gt 0 ]; then
    echo "run_parts: another mlxf_test_exec, cmake or gfortran process is running: nothing started" >&2
    rmdir "$OUTDIR" 2>/dev/null
    exit 4
fi
t0=$(date +%s)
while awk -v l="$(load1)" -v m="$LOAD_MAX" 'BEGIN{exit !(l > m)}'; do
    [ $(( $(date +%s) - t0 )) -ge "$LOAD_WAIT" ] && break
    sleep 10
done
LOAD_BEFORE=$(load1)
UP_BEFORE=$(uptime)

# ---- the processes ----
GO="$OUTDIR/go"
PIDS=()
# ends this launcher's processes by their PIDs: each part's shell, its timer and its executable
stop_parts() {
    local pid c e
    for pid in ${PIDS[@]+"${PIDS[@]}"}; do
        for c in $(pgrep -P "$pid"); do
            for e in $(pgrep -P "$c"); do kill "$e" 2>/dev/null; done
            kill "$c" 2>/dev/null
        done
        kill "$pid" 2>/dev/null
    done
}
trap 'stop_parts; exit 1' INT TERM
if [ "$OS" = Darwin ]; then TIMER="/usr/bin/time -l"; else TIMER="/usr/bin/time -v"; fi
export OMP_NUM_THREADS=$NTHR
export MLX_ENABLE_TF32="${MLX_ENABLE_TF32:-0}"
p=1
while [ $p -le "$NPARTS" ]; do
    d="$OUTDIR/part_$p"
    mkdir -p "$d"
    (
        cd "$d" || exit 1
        $TIMER "$EXEC" test=bench_polar_table suite=time nparts="$NPARTS" part=$p nthr="$NTHR" go="$GO" \
            ${KEYS[@]+"${KEYS[@]}"} > stdout.log 2> time.log
        echo $? > rc
        now > end_time
    ) &
    PIDS+=($!)
    p=$((p + 1))
done
# every ready file, or a process that ended before it was ready
nready=0
while [ $nready -lt "$NPARTS" ]; do
    sleep 0.2
    nready=$(ls "$OUTDIR"/go.ready.* 2>/dev/null | wc -l | tr -d ' ')
    if ls "$OUTDIR"/part_*/rc > /dev/null 2>&1; then
        echo "run_parts: a process ended before it was ready (see $OUTDIR/part_*/stdout.log)" >&2
        stop_parts
        row_unmeasured failed "$PRED" "$LOAD_BEFORE"
        exit 1
    fi
done
status=ok
[ "$(foreign "$NPARTS")" -gt 0 ] && status=discarded
set -- $(mem_free)
MINFREE=$1; MINAVAIL=$2
T_GO=$(now)
: > "$GO"
while [ "$(ls "$OUTDIR"/part_*/rc 2>/dev/null | wc -l | tr -d ' ')" -lt "$NPARTS" ]; do
    set -- $(mem_free)
    f=$1; a=$2
    echo "$(date '+%T')$TAB$f$TAB$a$TAB$(load1)" >> "$OUTDIR/samples.tsv"
    [ "$f" -lt "$MINFREE" ] && MINFREE=$f
    [ "$a" -lt "$MINAVAIL" ] && MINAVAIL=$a
    # a part that has already ended is not a foreign process short
    running=$(pgrep -x mlxf_test_exec | wc -l | tr -d ' ')
    n_build=$( (pgrep -x cmake; pgrep -x gfortran; pgrep -x f951) | wc -l | tr -d ' ')
    if [ "$running" -gt "$NPARTS" ] || [ "$n_build" -gt 0 ]; then status=discarded; fi
    sleep 1
done
wait
LOAD_AFTER=$(load1)
UP_AFTER=$(uptime)

# ---- the record ----
field() { awk -v pat="$1" '$0 ~ pat {print $1}' "$2" | tail -1; }
{
    echo "run_parts: $NPARTS processes, $NTHR threads each, keys: ${KEYS[*]}"
    echo "executable: $EXEC"
    echo "MLX_ENABLE_TF32=$MLX_ENABLE_TF32 OMP_NUM_THREADS=$OMP_NUM_THREADS"
    echo "uptime before: $UP_BEFORE"
    echo "uptime after:  $UP_AFTER"
    echo "go at $T_GO"
} > "$OUTDIR/summary.txt"
T_LAST=0; SUMR=0; MINR=0; MAXR=0; MAXFP=0; SUMFP=0; MAXRSS=0; SUMRSS=0; MAXPK=0; SUMPK=0; SUMCA=0
p=1
while [ $p -le "$NPARTS" ]; do
    d="$OUTDIR/part_$p"
    rc=$(cat "$d/rc"); te=$(cat "$d/end_time")
    [ "$rc" = 0 ] || status=failed
    rate=$(awk -F'\t' 'NR > 1 {v = $20} END{print v + 0}' "$d/bench_polar_table.tsv" 2>/dev/null)
    peak=$(awk -F'\t' 'NR > 1 {v = $26} END{print v + 0}' "$d/bench_polar_table.tsv" 2>/dev/null)
    cache=$(awk -F'\t' 'NR > 1 {v = $27} END{print v + 0}' "$d/bench_polar_table.tsv" 2>/dev/null)
    if [ "$OS" = Darwin ]; then
        rss=$(field 'maximum resident set size' "$d/time.log"); fp=$(field 'peak memory footprint' "$d/time.log")
    else
        rss=$(awk '/Maximum resident set size/{print $NF * 1024}' "$d/time.log"); fp=$rss
    fi
    rate=${rate:-0}; peak=${peak:-0}; cache=${cache:-0}; rss=${rss:-0}; fp=${fp:-0}
    echo "part $p: exit $rc, end $te, pairs_per_s $rate, mlx_peak_B $peak, mlx_cache_B $cache, max_rss_B $rss, peak_footprint_B $fp" >> "$OUTDIR/summary.txt"
    grep -h -E '^ +(digest|part) ' "$d/stdout.log" >> "$OUTDIR/summary.txt"
    set -- $(awk -v p=$p -v tl="$T_LAST" -v te="$te" -v sr="$SUMR" -v mn="$MINR" -v mx="$MAXR" -v r="$rate" -v mf="$MAXFP" \
    -v sf="$SUMFP" -v f="$fp" -v mr="$MAXRSS" -v srs="$SUMRSS" -v rs="$rss" -v mp="$MAXPK" -v sp="$SUMPK" -v pk="$peak" \
    -v sc="$SUMCA" -v ca="$cache" 'BEGIN{
        if (te > tl) tl = te
        if (p == 1 || r < mn) mn = r
        if (r > mx) mx = r
        if (f > mf) mf = f
        if (rs > mr) mr = rs
        if (pk > mp) mp = pk
        printf "%.3f %.5e %.5e %.5e %.0f %.0f %.0f %.0f %.0f %.0f %.0f\n", tl, sr + r, mn, mx, mf, sf + f, mr, srs + rs, mp, sp + pk, sc + ca }')
    T_LAST=$1; SUMR=$2; MINR=$3; MAXR=$4; MAXFP=$5; SUMFP=$6; MAXRSS=$7; SUMRSS=$8; MAXPK=$9; SUMPK=${10}; SUMCA=${11}
    p=$((p + 1))
done
ELAPSED=$(awk -v a="$T_GO" -v b="$T_LAST" 'BEGIN{printf "%.3f", b - a}')
{
    echo "status: $status"
    echo "go_to_last_exit_s: $ELAPSED"
    echo "sum_pairs_per_s: $SUMR (per process $MINR to $MAXR)"
    echo "peak_footprint_B: largest $MAXFP, summed $SUMFP (predicted $PRED)"
    echo "max_rss_B: largest $MAXRSS, summed $SUMRSS"
    echo "mlx_peak_B: largest $MAXPK, summed $SUMPK; mlx_cache_B summed $SUMCA"
    echo "machine: lowest free $MINFREE B, lowest available $MINAVAIL B of $TOTAL B"
    echo "load: before $LOAD_BEFORE, after $LOAD_AFTER"
} >> "$OUTDIR/summary.txt"
row "$status$TAB$ELAPSED$TAB$SUMR$TAB$MINR$TAB$MAXR$TAB$MAXFP$TAB$SUMFP$TAB$MAXRSS$TAB$SUMRSS$TAB$MAXPK$TAB$SUMPK$TAB$SUMCA$TAB$MINFREE$TAB$MINAVAIL$TAB$TOTAL$TAB$PRED$TAB$LOAD_BEFORE$TAB$LOAD_AFTER$TAB${KEYS[*]}"
cat "$OUTDIR/summary.txt"
case "$status" in
    ok) exit 0 ;;
    discarded) exit 4 ;;
    *) exit 1 ;;
esac
