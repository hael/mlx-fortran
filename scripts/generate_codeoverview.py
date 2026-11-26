#!/usr/bin/env python3
"""Generate the code-base map from !@descr: headers and directory .inf files.

Copied from XEMA (`scripts/generate_codeoverview.py` at 2848f6c, 2026-11-12), which adapted it from SIMPLE's
scripts/generate_codeoverview.pl; changed here only in the top directories (src, test, scripts), the output
(doc/code_base_map.md) and the text encodings. Walks the source tree, reads a one-line description from the
first lines of each Fortran file, reads directory descriptions from <dir>/<dir>.inf, and writes a single
markdown tree. Directories git ignores, or does not track and that hold no Fortran source or .inf, are left out.

Usage:
    python3 scripts/generate_codeoverview.py            # writes doc/code_base_map.md
    python3 scripts/generate_codeoverview.py --check    # non-zero if out of date (scripts/check_tree.sh)
    options: --root DIR (default: the repository), --out FILE

Run after adding, moving or renaming modules or directories, or changing a description. Python 3.7 or newer,
standard library only.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SCAN_LINES = 40
FORTRAN_SUFFIXES = {".f90", ".F90", ".f08", ".F08"}
INCLUDED_TOP_DIRS = ("src", "test", "scripts")
EXCLUDED_DIRS = {".git", "build", "__pycache__", ".venv", "data", ".idea", ".vscode"}
DESCR_RE = re.compile(r"^\s*!\s*@descr?:\s*(.+?)\s*$", re.IGNORECASE)


_IN_CHECKOUT = {}


def in_checkout(root: Path) -> bool:
    """Whether root is the top of a git checkout. A tree exported into an ignored directory of another checkout
    (scripts/release_gate.sh builds its export under build_release_gate/) is not: git would answer for the outer
    checkout, which ignores and does not track the export, and the map would come out empty."""
    if root not in _IN_CHECKOUT:
        try:
            out = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            top = out.stdout.decode("utf-8", "replace").strip()
            _IN_CHECKOUT[root] = out.returncode == 0 and Path(top).resolve() == root.resolve()
        except OSError:
            _IN_CHECKOUT[root] = False
    return _IN_CHECKOUT[root]


def is_git_ignored(path: Path, root: Path) -> bool:
    """Transient run folders (dated benchmark/parity/checkpoint directories)
    are gitignored and must not enter the committed map."""
    if not in_checkout(root):
        return False
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-q", str(path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return result.returncode == 0
    except OSError:
        return False


_TRACKED_DIRS = {}


def tracked_dirs(root: Path):
    """Directories holding a file git tracks, or None outside a git checkout."""
    if not in_checkout(root):
        return None
    if root not in _TRACKED_DIRS:
        try:
            out = subprocess.run(["git", "-C", str(root), "--no-optional-locks", "ls-files", "-z"],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            dirs = None
            if out.returncode == 0:
                dirs = set()
                for f in out.stdout.decode("utf-8", "replace").split("\0"):
                    parent = (root / f).parent
                    while parent != root and parent not in dirs:
                        dirs.add(parent)
                        parent = parent.parent
            _TRACKED_DIRS[root] = dirs
        except OSError:
            _TRACKED_DIRS[root] = None
    return _TRACKED_DIRS[root]


def is_transient(path: Path, root: Path) -> bool:
    """A directory outside the map: gitignored, or untracked and holding no
    Fortran source or .inf (a scratch or run directory not yet ignored), so an
    owner's work in progress never makes the committed map read as stale."""
    if is_git_ignored(path, root):
        return True
    dirs = tracked_dirs(root)
    if dirs is None or path in dirs:
        return False
    return not any(p.suffix in FORTRAN_SUFFIXES or p.suffix == ".inf" for p in path.rglob("*") if p.is_file())


def file_description(path: Path) -> str:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for _, line in zip(range(SCAN_LINES), handle):
                match = DESCR_RE.match(line)
                if match:
                    return match.group(1)
    except OSError:
        pass
    return ""


def dir_description(path: Path) -> str:
    inf = path / f"{path.name}.inf"
    if inf.is_file():
        try:
            line = inf.read_text(encoding="utf-8", errors="replace").strip().splitlines()[0].strip()
            match = DESCR_RE.match(line)
            return match.group(1) if match else line
        except (OSError, IndexError):
            return ""
    return ""


def render(path: Path, root: Path, depth: int, lines: list[str]) -> None:
    indent = "  " * depth
    descr = dir_description(path)
    suffix = f" — {descr}" if descr else ""
    lines.append(f"{indent}- **{path.name}/**{suffix}")

    entries = sorted(path.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
    for entry in entries:
        if entry.name in EXCLUDED_DIRS or entry.name.startswith("."):
            continue
        if entry.is_dir():
            if is_transient(entry, root):
                continue
            render(entry, root, depth + 1, lines)
        elif entry.suffix in FORTRAN_SUFFIXES:
            descr = file_description(entry)
            suffix = f" — {descr}" if descr else ""
            lines.append(f"{'  ' * (depth + 1)}- `{entry.name}`{suffix}")


def build(root: Path) -> str:
    lines = [
        "<!-- AUTO-GENERATED by scripts/generate_codeoverview.py; do not edit by hand. -->",
        "",
        "# Code base map",
        "",
        "One line per module, taken from its `!@descr:` header; directory",
        "descriptions come from `<dir>/<dir>.inf`. Regenerate with",
        "`python3 scripts/generate_codeoverview.py`.",
        "",
    ]
    for top in INCLUDED_TOP_DIRS:
        directory = root / top
        if directory.is_dir():
            render(directory, root, 0, lines)
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--out", default=None)
    parser.add_argument("--check", action="store_true",
                        help="exit non-zero if the committed map is stale")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    out = Path(args.out) if args.out else root / "doc" / "code_base_map.md"
    content = build(root)

    if args.check:
        current = out.read_text(encoding="utf-8") if out.is_file() else ""
        if current != content:
            print(f"{out} is out of date; run scripts/generate_codeoverview.py",
                  file=sys.stderr)
            return 1
        print(f"{out} is up to date")
        return 0

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content, encoding="utf-8")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
