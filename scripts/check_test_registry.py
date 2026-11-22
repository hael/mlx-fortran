#!/usr/bin/env python3
"""check_test_registry.py -- the test registry, the testers and the CTest entries agree.

Three lists must agree, or a tester never runs and nothing reports it:
  - the areas of the CTest entries (set(MLXF_TEST_AREAS ...) in test/CMakeLists.txt),
  - the areas of the registry (the AREAS table and the case() branches of src/test/mlxf_test_registry.f90),
  - the tester entries: every run_all_<x>_tests a *_tester.f90 under src/ defines is called by exactly one
    run_suite row, and every row calls an entry that exists. Sub-suite names are unique within an area
    and at most 32 characters. Every name of the registry's NAMED_ONLY table (sub-suites run only when
    suite= names them) is the name of a row.
And the guard groups agree: every `expect_aborts <group>` entry of test/CMakeLists.txt names a group of the
registry's GUARDS table, every group of the table has such an entry, and every member of the table has its
case() branch in run_guard (and no branch lacks a member).
usage: scripts/check_test_registry.py [ROOT] [--verbose]
exit status: 0 consistent, 1 a mismatch
"""

import os
import re
import sys

CMAKE_AREAS_RE = re.compile(r"set\(\s*MLXF_TEST_AREAS\s+([^)]*)\)", re.IGNORECASE)
NAMED_RE = re.compile(r"NAMED_ONLY\s*\(\s*\d+\s*\)\s*=\s*\[[^\]]*::([^\]]*)\]", re.IGNORECASE | re.DOTALL)
TABLE_RE = re.compile(r"AREAS\s*\(\s*\d+\s*\)\s*=\s*\[[^\]]*::([^\]]*)\]", re.IGNORECASE | re.DOTALL)
CASE_RE = re.compile(r"^\s*case\s*\(\s*'(\w+)'\s*\)", re.IGNORECASE)
ROW_RE = re.compile(r"call\s+run_suite\s*\(\s*'([^']+)'\s*,\s*(\w+)", re.IGNORECASE)
ENTRY_DEF_RE = re.compile(r"^\s*(?:module\s+)?subroutine\s+(run_all_\w+_tests)\b", re.IGNORECASE)
GUARD_RE = re.compile(r"guard_member\(\s*'(\w+)'\s*,\s*'(\w+)'\s*\)", re.IGNORECASE)
CMAKE_GUARD_RE = re.compile(r"expect_aborts\s+(\w+)", re.IGNORECASE)


def code(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return [re.sub(r"!.*", "", line) for line in f]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    verbose = "--verbose" in sys.argv
    root = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(__file__), ".."))
    problems = []

    with open(os.path.join(root, "test", "CMakeLists.txt"), "r", encoding="utf-8") as f:
        cmake_text = f.read()
    m = CMAKE_AREAS_RE.search(cmake_text)
    cmake_areas = m.group(1).split() if m else []
    if not cmake_areas:
        problems.append("test/CMakeLists.txt: no set(MLXF_TEST_AREAS ...)")

    reg_path = os.path.join(root, "src", "test", "mlxf_test_registry.f90")
    reg = code(reg_path)
    m = TABLE_RE.search("".join(reg))
    table_areas = re.findall(r"'(\w+)'", m.group(1)) if m else []
    case_areas, rows, area, guard_cases, proc = [], [], None, [], None
    for line in reg:
        p = re.match(r"^\s*(?:end\s+)?subroutine\s+(\w+)", line, re.IGNORECASE)
        if p:
            proc = None if line.lstrip().lower().startswith("end") else p.group(1).lower()
        c = CASE_RE.match(line)
        if c and proc == "run_area":
            area = c.group(1)
            case_areas.append(area)
        elif c and proc == "run_guard":
            guard_cases.append(c.group(1))
        for name, entry in ROW_RE.findall(line):
            rows.append((area, name, entry.lower()))
    guards = GUARD_RE.findall("".join(reg))
    guard_groups = sorted(set(g for _, g in guards))
    cmake_groups = sorted(set(CMAKE_GUARD_RE.findall(re.sub(r"#[^\n]*", "", cmake_text))))
    if guard_groups != cmake_groups:
        problems.append("guard groups differ: registry GUARDS %s, test/CMakeLists.txt expect_aborts %s" %
                        (guard_groups, cmake_groups))
    if sorted(n for n, _ in guards) != sorted(guard_cases):
        problems.append("guard members differ: registry GUARDS %s, run_guard case() %s" %
                        (sorted(n for n, _ in guards), sorted(guard_cases)))

    if cmake_areas != table_areas:
        problems.append("areas differ: test/CMakeLists.txt %s, registry AREAS %s" % (cmake_areas, table_areas))
    if table_areas != case_areas:
        problems.append("areas differ: registry AREAS %s, registry case() %s" % (table_areas, case_areas))

    defined = {}
    for d, _, names in os.walk(os.path.join(root, "src")):
        for n in names:
            if n.endswith("_tester.f90"):
                for line in code(os.path.join(d, n)):
                    e = ENTRY_DEF_RE.match(line)
                    if e:
                        defined[e.group(1).lower()] = os.path.relpath(os.path.join(d, n), root)
    called = {}
    seen = set()
    for area, name, entry in rows:
        called[entry] = called.get(entry, 0) + 1
        if len(name) > 32:
            problems.append("sub-suite name over 32 characters: %s" % name)
        if (area, name) in seen:
            problems.append("sub-suite %s appears twice in area %s" % (name, area))
        seen.add((area, name))
        if entry not in defined:
            problems.append("row %s/%s calls %s, which no tester defines" % (area, name, entry))
    m = NAMED_RE.search("".join(reg))
    if m is None and re.search(r"\bNAMED_ONLY\s*\(", "".join(reg), re.IGNORECASE):
        problems.append("NAMED_ONLY table not read: write it as NAMED_ONLY(n) = [character(len=32) :: '...', ...]")
    for name in (re.findall(r"'(\w+)'", m.group(1)) if m else []):
        if not any(n == name for _, n, _ in rows):
            problems.append("NAMED_ONLY names %s, which no run_suite row runs" % name)
    for entry, path in sorted(defined.items()):
        if called.get(entry, 0) != 1:
            problems.append("%s (%s) is called by %d registry rows, not one" % (entry, path, called.get(entry, 0)))

    for p in problems:
        print("check_test_registry: " + p, file=sys.stderr)
    if verbose and not problems:
        print("check_test_registry: %d areas, %d sub-suites, %d tester entries, %d guard groups of %d members agree" %
              (len(cmake_areas), len(rows), len(defined), len(guard_groups), len(guards)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
