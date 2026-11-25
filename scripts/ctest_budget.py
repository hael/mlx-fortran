#!/usr/bin/env python3
"""ctest_budget.py -- report the fast-gate time budget.

Reads the stdout of a `ctest -L fast` run (tee it to a file; see
scripts/run_fast_gate.sh) and checks the one rule of the fast gate
(doc/policies/test_environment_policy.md): the whole run
finishes within --budget seconds of real time ("Total Test time (real)" as
ctest reports it). Budget overruns only warn; failed entries fail the check.

Writes every entry sorted by time next to the log as <log>.timing.txt, so the
numbers are kept from build to build and a suite that grows is visible, and
prints the same table unless --quiet is given. With --quiet (the compile
scripts) a passing run within budget prints nothing, so what the developer
sees is ctest's own report; the table and the problems are printed
only when there is something to fix. Exits 1 on a failed entry,
2 if the log holds no ctest results or an incomplete run: ctest's summary
line ("N% tests passed[, F tests failed] out of T") must be present and name
as many entries as the log reports. A run over budget exits successfully
when all entries pass. The caller still checks ctest's own exit status:
this script reads a transcript, it does not decide that ctest succeeded.

usage: scripts/ctest_budget.py LOG [--budget 60] [--no-budget] [--quiet]
       scripts/ctest_budget.py --self-test
"""
import argparse
import re
import sys

RE_TEST = re.compile(r'^\s*\d+/\d+\s+Test\s+#\d+:\s+(\S+)\s+\.+\s*(?:\*+)?(Passed|Failed|Timeout|Not Run|Exception|Subprocess aborted|\*\*\*[^\d]*)\s+([\d.]+)\s+sec', re.M)
RE_TOTAL = re.compile(r'^Total Test time \(real\)\s*=\s*([\d.]+)\s+sec', re.M)
RE_LABEL = re.compile(r'^(\w+)\s*=\s*([\d.]+)\s+sec\*proc', re.M)
RE_SUMMARY = re.compile(r'^\d+% tests passed(?:, (\d+) tests? failed)? out of (\d+)', re.M)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('log', nargs='?')
    ap.add_argument('--budget', type=float, default=60.0, help='seconds of real time for the whole run (default 60)')
    ap.add_argument('--no-budget', action='store_true', help='report times without warning on the budget (only failed entries count)')
    ap.add_argument('--quiet', action='store_true', help='print nothing when the run passes within budget (the table still goes to <log>.timing.txt)')
    ap.add_argument('--self-test', action='store_true', help='check the parser on complete, failed and truncated transcripts')
    a = ap.parse_args(argv)
    if a.self_test:
        return self_test()
    if a.log is None:
        ap.error('LOG is required')
    text = open(a.log, errors='replace').read()
    tests = [(name, status.strip(), float(secs)) for name, status, secs in RE_TEST.findall(text)]
    if not tests:
        print('ctest_budget: no ctest results in %s' % a.log)
        return 2
    summary = RE_SUMMARY.search(text)
    if summary is None:
        print('ctest_budget: incomplete run in %s: no ctest summary line after %d entries' % (a.log, len(tests)))
        return 2
    if int(summary.group(2)) != len(tests):
        print('ctest_budget: incomplete run in %s: ctest counts %s entries, the log reports %d' % (
            a.log, summary.group(2), len(tests)))
        return 2
    total = RE_TOTAL.search(text)
    total = float(total.group(1)) if total else sum(t[2] for t in tests)
    labels = dict((k, float(v)) for k, v in RE_LABEL.findall(text))
    tests.sort(key=lambda t: -t[2])
    lines = ['%8s  %-8s  %s' % ('sec', 'status', 'test')]
    problems = []
    for name, status, secs in tests:
        flag = ''
        if not status.startswith('Passed'):
            flag = '  <-- ' + status
            problems.append('%s: %s' % (name, status))
        lines.append('%8.2f  %-8s  %s%s' % (secs, status.split()[0], name, flag))
    lines.append('')
    over = total > a.budget and not a.no_budget
    lines.append('%d entries; total real time %.1f s (budget %.0f s)%s' % (
        len(tests), total, a.budget, '  <-- OVER BUDGET' if over else ''))
    if labels:
        lines.append('label proc-seconds: ' + ', '.join('%s %.1f' % kv for kv in sorted(labels.items())))
    out = '\n'.join(lines)
    with open(a.log + '.timing.txt', 'w') as fh:
        fh.write(out + '\n')
    if problems or over or not a.quiet:
        print(out)
    if over:
        print('\nctest_budget: WARNING: total real time %.1f s exceeds the %.0f s budget' % (total, a.budget))
    if summary.group(1) is not None and int(summary.group(1)) > 0 and not problems:
        problems.append('ctest reports %s failed entries' % summary.group(1))
    if problems:
        print('\nctest_budget: %d problem(s):' % len(problems))
        for p in problems:
            print('   ' + p)
        return 1
    if not a.quiet:
        if not over:
            print('\nctest_budget: within budget')
    return 0


def self_test():
    """the parser's verdict on transcripts: whole and passing 0 (both summary forms), a failed entry 1, and 2 for
    a truncated, an empty, an interrupted and a short run"""
    import os
    import tempfile
    entry = '%d/2 Test #%d: %s ........   Passed    1.00 sec\n'
    whole = (entry % (1, 1, 'core') + entry % (2, 2, 'ops') +
             '\n100% tests passed, 0 tests failed out of 2\n\nTotal Test time (real) =   2.00 sec\n')
    cases = [
        ('whole', whole, 0),
        ('whole, ctest 4', whole.replace('100% tests passed, 0 tests failed out of 2', '100% tests passed out of 2'), 0),
        ('failed', whole.replace('2/2 Test #2: ops ........   Passed', '2/2 Test #2: ops ........***Failed')
         .replace('100% tests passed, 0 tests failed', '50% tests passed, 1 tests failed'), 1),
        ('truncated', entry % (1, 1, 'core'), 2),
        ('empty', '', 2),
        ('interrupted', 'Test project /tmp/x\n    Start 1: core\n' + entry % (1, 1, 'core') + '    Start 2: ops\n', 2),
        ('short', entry % (1, 1, 'core') + '\n100% tests passed, 0 tests failed out of 2\n', 2),
    ]
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, text, want in cases:
            path = os.path.join(tmp, name + '.log')
            with open(path, 'w') as fh:
                fh.write(text)
            got = main([path, '--quiet'])
            if got != want:
                bad.append('%s: exit %d, expected %d' % (name, got, want))
    for b in bad:
        print('ctest_budget self-test: ' + b)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
