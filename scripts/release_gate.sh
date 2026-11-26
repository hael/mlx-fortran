#!/bin/bash
# scripts/release_gate.sh -- the gate a release needs, run on an Apple-silicon Mac with a Metal GPU.
#
#   scripts/release_gate.sh [--allow-dirty] [--require-tag] [--jobs N]
#
# It builds a source tree it exports, never the checkout. Release mode (no flag) refuses uncommitted changes to
# tracked files and exports HEAD with git archive; the log lists the untracked files that the export leaves
# out. --allow-dirty exports the working tree's files that git tracks or does not ignore (deleted files left
# out), tags the log <commit>-dirty and lists every file that differs from HEAD. --require-tag fails unless HEAD
# carries the tag v<VERSION of CMakeLists.txt's project()>. mlx-c is the one the checkout would find (MLXC_ROOT,
# then .deps/install, then CMake's default search) and is passed on as MLXC_ROOT. In build_release_gate/ it builds
# the export in Debug and Release from scratch (MLXF_REQUIRE_GPU=ON, MLXF_WERROR=ON, FORTLS=OFF) and runs the
# export's own fast gate and consumer check (scripts/check_install.sh, --require-gpu) on each, then its
# scripts/check_embed.sh and scripts/check_toy_offstate.sh (the toys' host files without MLX). It fails when one of
# them fails, when any test reports a skip, when no GPU device was opened, and when the builds changed a file of the
# export or the checkout's .claude/settings.local.json. The log, with the toolchain, mlx-c and the device, is
# build_release_gate/release_gate_<tag>.log (ignored by git).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/mlxf_build_jobs.sh" || exit $?
allow_dirty=0
require_tag=0
JOBS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-dirty) allow_dirty=1 ;;
        --require-tag) require_tag=1 ;;
        --jobs|-j) shift; JOBS="${1:-}" ;;
        --jobs=*) JOBS="${1#*=}" ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "release_gate: unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done
JOBS=$(mlxf_build_jobs "$JOBS") || exit $?
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "release_gate: needs an Apple-silicon Mac (this is $(uname -s) $(uname -m))" >&2
    exit 2
fi
cd "$ROOT" || exit 2
git_() { git --no-optional-locks "$@"; }
commit=$(git_ rev-parse --short HEAD) || exit 2
version=$(sed -n '/^project(/,/)/s/^ *VERSION \([0-9][0-9.]*\).*/\1/p' CMakeLists.txt | head -n 1)
[[ -n "$version" ]] || { echo "release_gate: no VERSION in the project() of CMakeLists.txt" >&2; exit 2; }
if [[ $require_tag -eq 1 ]] && ! git_ tag --points-at HEAD | grep -qx "v$version"; then
    echo "release_gate: HEAD ($commit) does not carry the tag v$version (--require-tag)" >&2
    exit 2
fi
if [[ -n "$(git_ status --porcelain --untracked-files=no)" && $allow_dirty -eq 0 ]]; then
    echo "release_gate: uncommitted changes to tracked files; commit them or pass --allow-dirty" >&2
    exit 2
fi
# every file that differs from HEAD (modified, deleted, untracked), and the untracked files git does not ignore
changed=$(git_ status --porcelain --untracked-files=all)
untracked=$(git_ ls-files --others --exclude-standard)
tag="$commit"
[[ $allow_dirty -eq 1 && -n "$changed" ]] && tag="${commit}-dirty"
WORK="$ROOT/build_release_gate"
SRC="$WORK/src"
rm -rf "$WORK" && mkdir -p "$SRC" || exit 2
LOG="$WORK/release_gate_${tag}.log"
exec > >(tee "$LOG") 2>&1

echo "release gate of mlx-fortran ${version} at ${tag}, $(date '+%F %T')"
echo "host:     $(sysctl -n machdep.cpu.brand_string 2>/dev/null), macOS $(sw_vers -productVersion 2>/dev/null)"
echo "compiler: $(gfortran --version 2>/dev/null | head -n 1)"
echo "cmake:    $(cmake --version | head -n 1)"
echo "MLX:      $(brew list --versions mlx mlx-c 2>/dev/null | tr '\n' ' ')"

# ---- mlx-c as the checkout would resolve it, pinned for every configure below ------------------------------
if [[ -n "${MLXC_ROOT:-}" ]]; then
    how="MLXC_ROOT"; hint="$MLXC_ROOT"
elif [[ -d "$ROOT/.deps/install/share/cmake/MLXC" ]]; then
    how=".deps/install"; hint="$ROOT/.deps/install"
else
    how="CMake's default search"; hint=""
fi
mkdir -p "$WORK/mlxc_probe"
cat > "$WORK/mlxc_probe/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.25)
project(mlxc_probe LANGUAGES NONE)
set(FPHSA_NAME_MISMATCHED TRUE)
find_package(MLXC CONFIG QUIET)
if(NOT MLXC_FOUND)
    message(FATAL_ERROR "no mlx-c package config found")
endif()
get_filename_component(_prefix "${MLXC_DIR}/../../.." ABSOLUTE)
file(WRITE "${PROJECT_BINARY_DIR}/mlxc.txt" "${_prefix}\n${MLXC_DIR}\n${MLXC_VERSION}\n")
CMAKE
probe_args=()
[[ -n "$hint" ]] && probe_args+=("-DMLXC_ROOT=$hint")
if ! cmake -S "$WORK/mlxc_probe" -B "$WORK/mlxc_probe/build" "${probe_args[@]+"${probe_args[@]}"}" \
        > "$WORK/mlxc_probe/configure.log" 2>&1; then
    cat "$WORK/mlxc_probe/configure.log"
    echo "RELEASE GATE FAILED: ${tag}: no mlx-c found (${how})"
    exit 1
fi
{ read -r mlxc_prefix; read -r mlxc_dir; read -r mlxc_version; } < "$WORK/mlxc_probe/build/mlxc.txt"
export MLXC_ROOT="$mlxc_prefix"
echo "mlx-c:    ${mlxc_version}, MLXC_DIR=${mlxc_dir} (${how}), passed on as MLXC_ROOT=${mlxc_prefix}"

# ---- the snapshot ---------------------------------------------------------------------------------------
if [[ $allow_dirty -eq 0 ]]; then
    git_ archive HEAD | tar -x -C "$SRC" || { echo "RELEASE GATE FAILED: ${tag}: git archive"; exit 1; }
    echo "snapshot: git archive of ${commit}"
    if [[ -n "$untracked" ]]; then
        echo "untracked files the snapshot leaves out:"
        while IFS= read -r f; do echo "    $f"; done <<< "$untracked"
    fi
else
    # tracked and not-ignored untracked files as they are in the working tree; a deleted file is left out
    git_ ls-files -z --cached --others --exclude-standard |
        while IFS= read -r -d '' f; do [[ -e "$f" || -L "$f" ]] && printf '%s\0' "$f"; done |
        tar -c --null -T - -f - | tar -x -C "$SRC" || { echo "RELEASE GATE FAILED: ${tag}: working-tree export"; exit 1; }
    echo "snapshot: the working tree on ${commit} (--allow-dirty)"
    if [[ -n "$changed" ]]; then
        echo "files that differ from ${commit}:"
        while IFS= read -r f; do echo "    $f"; done <<< "$changed"
    fi
fi
# side effects: every file of the snapshot and the checkout's editor settings, before and after
manifest() {
    (cd "$SRC" && find . -type d | sort && find . -type l | sort | while IFS= read -r l; do
        echo "$l -> $(readlink "$l")"; done && find . -type f -print0 | sort -z | xargs -0 shasum -a 256)
}
settings="$ROOT/.claude/settings.local.json"
stamp() { if [[ -e "$settings" ]]; then stat -f '%m %z' "$settings"; else echo absent; fi; }
manifest > "$WORK/snapshot_before.txt"
settings_before=$(stamp)
echo "snapshot: $(grep -c '^[0-9a-f]\{64\} ' "$WORK/snapshot_before.txt") files hashed;" \
    ".claude/settings.local.json: ${settings_before}"

failed=0
for build_type in Debug Release; do
    B="$WORK/$build_type"
    echo
    echo "==== $build_type: configure, build, fast gate"
    if ! cmake -S "$SRC" -B "$B" -DCMAKE_BUILD_TYPE=$build_type -DBUILD_TESTS=ON -DMLXF_REQUIRE_GPU=ON \
            -DMLXF_WERROR=ON -DFORTLS=OFF "-DMLXC_ROOT=$mlxc_prefix"; then
        failed=1; break
    fi
    built=$(sed -n 's/^MLXC_DIR:PATH=//p' "$B/CMakeCache.txt")
    if [[ "$built" != "$mlxc_dir" ]]; then
        echo "$build_type: configured with mlx-c at ${built}, not ${mlxc_dir}"
        failed=1; break
    fi
    if ! cmake --build "$B" -j "$JOBS"; then
        failed=1; break
    fi
    "$SRC/scripts/run_fast_gate.sh" "$B" || failed=1
    # the full output of every test of the gate, passing ones included
    T="$B/Testing/Temporary/LastTest.log"
    nskip=0
    ngpu=0
    if [[ -f "$T" ]]; then
        nskip=$(grep -c 'SKIP' "$T")
        ngpu=$(grep -m 1 -o 'GPU devices: [0-9]*' "$T" | awk '{print $3}')
    fi
    echo "$build_type: tests reporting a skip: ${nskip}; GPU devices opened: ${ngpu:-0}"
    if [[ "$nskip" -ne 0 ]]; then
        grep 'SKIP' "$T" | sort | uniq -c
        failed=1
    fi
    [[ "${ngpu:-0}" -gt 0 ]] || failed=1
    echo
    echo "==== $build_type: the installed package and outside programs on the GPU (check_install.sh)"
    "$SRC/scripts/check_install.sh" "$B" "$SRC/test/consumer" --require-gpu || failed=1
done
if [[ $failed -eq 0 ]]; then
    echo
    echo "==== the library added to a parent project (add_subdirectory)"
    "$SRC/scripts/check_embed.sh" --jobs "$JOBS" || failed=1
    "$SRC/scripts/check_toy_offstate.sh" --jobs "$JOBS" --exec "$WORK/Release/test/mlxf_test_exec" || failed=1
fi

echo
manifest > "$WORK/snapshot_after.txt"
if ! diff "$WORK/snapshot_before.txt" "$WORK/snapshot_after.txt" > "$WORK/snapshot_diff.txt"; then
    echo "side effects: the builds changed the snapshot:"
    sed 's/^/    /' "$WORK/snapshot_diff.txt" | head -n 40
    failed=1
else
    echo "side effects: none in the snapshot"
fi
settings_after=$(stamp)
if [[ "$settings_after" != "$settings_before" ]]; then
    echo "side effects: .claude/settings.local.json of the checkout changed (${settings_before} -> ${settings_after})"
    failed=1
else
    echo "side effects: none in the checkout's .claude/settings.local.json"
fi

echo
if [[ $failed -ne 0 ]]; then
    echo "RELEASE GATE FAILED: ${tag} after ${SECONDS} s (log ${LOG})"
    exit 1
fi
echo "RELEASE GATE PASSED: ${tag} (mlx-fortran ${version}, mlx-c ${mlxc_version}), Debug and Release, on" \
    "$(sysctl -n machdep.cpu.brand_string 2>/dev/null), ${SECONDS} s"
