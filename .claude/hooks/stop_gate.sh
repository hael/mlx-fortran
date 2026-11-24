#!/usr/bin/env bash
# Claude Code Stop hook (.claude/settings.json): runs the static gate, scripts/check_tree.sh, when src/, test/
# or scripts/ differ from HEAD, so an agent's turn does not end with the gate failing. The first failure goes
# back to Claude (exit 2) to fix; if the gate still fails at the next stop, the user is warned and the turn
# ends, so the hook never loops. Reads the hook's JSON input on stdin; needs only git and python3.
set -u
input=$(cat)
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root" || exit 0
[ -n "$(git --no-optional-locks status --porcelain -- src test scripts 2> /dev/null)" ] || exit 0
if out=$(scripts/check_tree.sh 2>&1); then
    exit 0
fi
if printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    python3 -I -c 'import json, sys; print(json.dumps({"systemMessage": sys.argv[1]}))' \
        "Static gate still fails after one retry: $(printf '%s\n' "$out" | tail -n 1)"
    exit 0
fi
{
    echo "scripts/check_tree.sh fails on the working tree. Fix what your changes broke (restyle_fortran.py and"
    echo "format_use_blocks.py fix layout and use blocks); if the failure is in files you did not touch, say so"
    echo "instead of changing them. Gate output:"
    printf '%s\n' "$out" | tail -n 40
} >&2
exit 2
