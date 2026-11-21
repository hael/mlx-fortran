#!/usr/bin/env bash
# scripts/check_tree.sh -- the static gate: every check that needs no compiler, in seconds, so that a broken
# rule stops a build before it starts instead of in review. Lifted from XEMA.
#
#     scripts/check_tree.sh [PYTHON]        (default: python3)
#
# Runs, and fails on the first that fails:
#   check_descr.py              one leading !@descr: line and at most one module or submodule per file
#   check_rules.py              the rules reading can check (layout, inf, surface, cbind, libc, reexport,
#                               cbstop, prints, state, arity, ctorcall, defs), with ledgers that may only shrink
#   check_test_registry.py      the suite registry, the testers and the CTest areas agree
#   check_guide_imports.py      every folder CLAUDE.md import names a file
#   check_submodule_linkage.py  no submodule calls a private plain procedure of its module
#   format_use_blocks.py        the one form of every use block, tree-wide
# then warns, never fails, about Fortran sources under src/ and test/ that git does not track: the targets
# glob their sources, so such a file builds here and is missing from a commit. restyle_fortran.py stays per
# file (run it on every file you touched). scripts/run_fast_gate.sh runs this first.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="${1:-python3}"
cd "$ROOT" || exit 2
tmp=$(mktemp "${TMPDIR:-/tmp}/mlxf_check_tree.XXXXXX")
run() {
    "$PY" -I "$@" > "$tmp" 2>&1
    local st=$?
    if [ "$st" -ne 0 ]; then
        cat "$tmp"
        echo "check_tree: FAILED: $*"
        rm -f "$tmp"
        exit 1
    fi
    rm -f "$tmp"
}
run scripts/check_descr.py "$ROOT"
run scripts/check_rules.py
run scripts/check_test_registry.py "$ROOT"
run scripts/check_guide_imports.py "$ROOT"
run scripts/check_submodule_linkage.py "$ROOT"
run scripts/format_use_blocks.py --check
if git -C "$ROOT" --no-optional-locks rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    untracked=$(git -C "$ROOT" --no-optional-locks ls-files --others --exclude-standard -- src test |
        grep -E '\.([Ff](90|08)|inc|c|h)$')
    if [ -n "$untracked" ]; then
        echo "check_tree: warning: $(echo "$untracked" | wc -l | tr -d ' ') source file(s) git does not track build here and are missing from a commit:" >&2
        echo "$untracked" | head -n 20 | sed 's/^/    /' >&2
    fi
fi
echo "check_tree: passed"
