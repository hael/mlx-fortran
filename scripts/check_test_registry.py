#!/usr/bin/env python3
"""check_test_registry.py -- the test registry, the testers and the CTest entries agree.

Three lists must agree, or a tester never runs and nothing reports it:
  - the areas of the CTest entries (set(MLXF_TEST_AREAS ...) in test/CMakeLists.txt),
  - the areas of the registry (the AREAS table and the case() branches of src/test/mlxf_test_registry.f90),
  - the tester entries: every run_all_<x>_tests a *_tester.f90 under src/ defines is called by exactly one
    run_suite row, and every row calls an entry that exists. Sub-suite names are unique within an area
    and at most 32 characters.
usage: scripts/check_test_registry.py [ROOT] [--verbose]
exit status: 0 consistent, 1 a mismatch
"""

import os
import re
import sys

CMAKE_AREAS_RE = re.compile(r"set\(\s*MLXF_TEST_AREAS\s+([^)]*)\)", re.IGNORECASE)
TABLE_RE = re.compile(r"AREAS\s*\(\s*\d+\s*\)\s*=\s*\[[^\]]*::([^\]]*)\]", re.IGNORECASE | re.DOTALL)
CASE_RE = re.compile(r"^\s*case\s*\(\s*'(\w+)'\s*\)", re.IGNORECASE)
ROW_RE = re.compile(r"call\s+run_suite\s*\(\s*'([^']+)'\s*,\s*(\w+)", re.IGNORECASE)
ENTRY_DEF_RE = re.compile(r"^\s*(?:module\s+)?subroutine\s+(run_all_\w+_tests)\b", re.IGNORECASE)


def code(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return [re.sub(r"!.*", "", line) for line in f]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    verbose = "--verbose" in sys.argv
    root = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(__file__), ".."))
    problems = []

    with open(os.path.join(root, "test", "CMakeLists.txt"), "r", encoding="utf-8") as f:
        m = CMAKE_AREAS_RE.search(f.read())
    cmake_areas = m.group(1).split() if m else []
    if not cmake_areas:
        problems.append("test/CMakeLists.txt: no set(MLXF_TEST_AREAS ...)")

    reg_path = os.path.join(root, "src", "test", "mlxf_test_registry.f90")
    reg = code(reg_path)
    m = TABLE_RE.search("".join(reg))
    table_areas = re.findall(r"'(\w+)'", m.group(1)) if m else []
    case_areas, rows, area = [], [], None
    for line in reg:
        c = CASE_RE.match(line)
        if c:
            area = c.group(1)
            case_areas.append(area)
        for name, entry in ROW_RE.findall(line):
            rows.append((area, name, entry.lower()))

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
    for entry, path in sorted(defined.items()):
        if called.get(entry, 0) != 1:
            problems.append("%s (%s) is called by %d registry rows, not one" % (entry, path, called.get(entry, 0)))

    for p in problems:
        print("check_test_registry: " + p, file=sys.stderr)
    if verbose and not problems:
        print("check_test_registry: %d areas, %d sub-suites, %d tester entries agree" %
              (len(cmake_areas), len(rows), len(defined)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
