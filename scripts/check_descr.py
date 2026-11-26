#!/usr/bin/env python3
"""check_descr.py -- every .f90 under src/ and test/ opens with one '!@descr:' line and holds at most
one module or submodule unit (lifted from SIMPLE); every directory under src/, test/, scripts/ and
doc/compiler_issues/ that holds a source file (.f90, .F90, .c, .h, .py, .sh), and every directory between it
and that top directory, has <dir>/<dir>.inf whose first line is '!@descr: <text>' and which holds no other
'!@descr:' line (the description scripts/generate_codeoverview.py puts in the code-base map).
usage: scripts/check_descr.py [ROOT]
"""

import os
import re
import sys

TARGET_DIRS = ["src", "test"]
EXCLUDED_DIR = os.path.join("src", "extlibs")
INF_DIRS = ["src", "test", "scripts", os.path.join("doc", "compiler_issues")]
SOURCE_SUFFIXES = (".f90", ".F90", ".c", ".h", ".py", ".sh")
MODULE_RE = re.compile(
    r"^\s*module\s+(?!procedure\b|subroutine\b|function\b)(\w+)", re.IGNORECASE
)
SUBMODULE_RE = re.compile(r"^\s*submodule\s*\(", re.IGNORECASE)
END_MODULE_RE = re.compile(r"^\s*end\s+(?:sub)?module\b", re.IGNORECASE)


def file_has_descr_header(filepath):
    """
    Returns True if the first non-empty line of the file
    starts with '!@descr:' followed by a description, otherwise False
    (an empty tag names nothing in the code map).
    """
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                stripped = line.strip()
                if stripped == "":
                    continue
                return stripped.startswith("!@descr:") and stripped[len("!@descr:"):].strip() != ""
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return False

    return False


def file_has_multiline_descr(filepath):
    """
    Returns True if the file carries more than one '!@descr:' line.
    The tag is a one-liner for the code map (like the subject line of a
    commit message); further description goes in plain '!' comments below it.
    """
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            return sum(1 for line in f if line.strip().startswith("!@descr:")) > 1
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return False


def file_module_unit_count(filepath):
    """Count top-level module/submodule units without counting module procedures."""
    count = 0
    inside_unit = False
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                code = line.split("!", 1)[0]
                if not inside_unit and (MODULE_RE.match(code) or SUBMODULE_RE.match(code)):
                    count += 1
                    inside_unit = True
                elif inside_unit and END_MODULE_RE.match(code):
                    inside_unit = False
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
    return count


def inf_problem(directory):
    """
    Returns None when <directory>/<name>.inf opens with a non-empty '!@descr:' line and holds no
    second one, otherwise what is wrong.
    """
    inf = os.path.join(directory, os.path.basename(directory) + ".inf")
    if not os.path.isfile(inf):
        return "missing"
    with open(inf, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.read().splitlines()
    first = lines[0].strip() if lines else ""
    if not first.startswith("!@descr:") or first[len("!@descr:"):].strip() == "":
        return "its first line is not '!@descr: <text>'"
    if sum(1 for line in lines if line.strip().startswith("!@descr:")) > 1:
        return "more than one '!@descr:' line"
    return None


def find_inf_problems(base_dir):
    """the directories holding a source file, and those between them and their top directory, whose .inf
    is missing or carries no description"""
    wanted = set()
    for top in INF_DIRS:
        top_path = os.path.join(base_dir, top)
        if not os.path.isdir(top_path):
            continue
        for root, dirs, files in os.walk(top_path):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"
                       and not is_excluded(os.path.join(root, d), base_dir)]
            if any(f.endswith(SOURCE_SUFFIXES) for f in files):
                d = root
                while True:
                    wanted.add(d)
                    if os.path.samefile(d, top_path):
                        break
                    d = os.path.dirname(d)
    problems = []
    for d in sorted(wanted):
        problem = inf_problem(d)
        if problem:
            problems.append("%s: %s" % (os.path.join(d, os.path.basename(d) + ".inf"), problem))
    return problems


def is_excluded(path, base_dir):
    """
    Returns True if path is inside the excluded directory.
    """
    excluded_path = os.path.abspath(os.path.join(base_dir, EXCLUDED_DIR))
    path = os.path.abspath(path)
    return os.path.commonpath([path, excluded_path]) == excluded_path


def find_missing_descr(base_dir):
    missing = []
    multiline = []
    multi_unit = []

    for dirname in TARGET_DIRS:
        search_path = os.path.join(base_dir, dirname)

        if not os.path.isdir(search_path):
            continue

        for root, dirs, files in os.walk(search_path):
            # Remove excluded directory from traversal
            dirs[:] = [
                d for d in dirs
                if not is_excluded(os.path.join(root, d), base_dir)
            ]

            for file in files:
                if file.lower().endswith(".f90"):
                    full_path = os.path.join(root, file)

                    if not is_excluded(full_path, base_dir):
                        if not file_has_descr_header(full_path):
                            missing.append(full_path)
                        elif file_has_multiline_descr(full_path):
                            multiline.append(full_path)
                        if file_module_unit_count(full_path) > 1:
                            multi_unit.append(full_path)

    return missing, multiline, multi_unit


if __name__ == "__main__":
    base_directory = sys.argv[1] if len(sys.argv) > 1 else "."

    results, multiline, multi_unit = find_missing_descr(base_directory)
    inf_problems = find_inf_problems(base_directory)

    if results:
        print("Files missing a '!@descr:' header (or with an empty one):\n")
        for path in results:
            print(path)
    if multiline:
        print("Files with more than one '!@descr:' line (the tag is a one-liner;"
              " continue in plain '!' comments):\n")
        for path in multiline:
            print(path)
    if multi_unit:
        print("Files with more than one module or submodule unit:\n")
        for path in multi_unit:
            print(path)
    if inf_problems:
        print("Directory descriptions missing or without a leading '!@descr: <text>' line:\n")
        for problem in inf_problems:
            print(problem)
    if results or multiline or multi_unit or inf_problems:
        sys.exit(1)
    else:
        print("All checked .f90 files have one leading '!@descr:' and at most one module/submodule;"
              " every source directory has a described .inf.")
        sys.exit(0)
