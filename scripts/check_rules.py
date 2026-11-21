#!/usr/bin/env python3
"""The rules of CLAUDE.md, the skills and doc/architecture_principles.md that a compiler does not check,
over src/ and test/. Adapted from XEMA's scripts/check_rules.py.

    scripts/check_rules.py            report every finding, exit 1 if any
    scripts/check_rules.py --list     also print each rule with the ledger it allows

A LEDGER names the files that do not follow a rule yet, with their count and the reason; a ledger may only
shrink: a file not in it, or a count above its entry, fails, and so does a count BELOW its entry (lower the
entry in the same change, so the ratchet holds what was gained).

Rules:
  layout     no `block` construct; no `goto`; no `!>` comment; no `interface operator`/`interface
             assignment` block (operators are type-bound generics); a THROW_HARD/THROW_WARN call on one
             physical line; no typed character constructor of non-literal elements passed straight as an
             argument (gfortran 15 corrupts the heap; assign it to a local first)
  inf        every directory holding Fortran has a non-empty <dir>.inf
  surface    every library module (src/core) restricts its interface: one `public ::` block and a bare
             `private`, and no `public` attribute on a declaration (installed .mod files make every public
             name API)
  cbind      `bind(c, name='mlx_...')` only in the generated layer (build/gen, never in src/)
  libc       a binding to the C library (strlen, memcpy, memset, posix_memalign, malloc, free) only in
             src/core/mlxf_libc.f90
  reexport   no module under src/core uses mlxf, the user module (test code may)
  cbstop     a procedure C++ calls (a bind(c) procedure with a body) never stops: no stop, error stop or
             THROW_* inside it
  prints     library code does not print: no write(*,...), print, or write to output_unit/error_unit in
             src/core outside the error module (testers, *_tester.f90, are test code and may)
  state      no module-level variable outside the ledger: module-scope declarations are constants or
             nothing (doc/architecture_principles.md, section 2, lists the allowed state)

Python 3.7 or newer, standard library only; it runs before the compile.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOPS = ('src', 'test')
CORE = 'src/core/'

# the scaffold's toolchain probe binds five mlx-c functions and strlen itself; the generated layer and
# mlxf_libc replace them in Phase 1 of the design plan, which deletes these entries
CBIND_LEDGER = {
    'src/core/mlxf_version.f90': (5, 'the toolchain probe, until the generated layer exists'),
}
LIBC_LEDGER = {
    'src/core/mlxf_version.f90': (1, 'the toolchain probe, until mlxf_libc exists'),
}
PRINT_ALLOWED = ('src/core/mlxf_error.f90',)
PRINT_LEDGER = {}
# the process-global state the register allows: the handle registry, the last error and the initialisation
# flag of the library, and the assertion totals of the test library
STATE_LEDGER = {
    'src/test/mlxf_test_utils.f90': (5, 'the assertion totals and the suite and failure records of the test library'),
}


def sources(root):
    out = []
    for top in TOPS:
        for d, dirs, files in os.walk(os.path.join(root, top)):
            dirs[:] = sorted(x for x in dirs if not x.startswith('.'))
            for f in sorted(files):
                if f.endswith(('.f90', '.F90')):
                    out.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, '/'))
    return out


def read(root, rel):
    with open(os.path.join(root, rel), encoding='utf-8', errors='replace') as h:
        return h.read()


def code_of(line):
    """the line without its comment and with string contents blanked"""
    out, quote = [], None
    for c in line:
        if quote:
            out.append(c if c == quote else ' ')
            if c == quote:
                quote = None
        elif c in '\'"':
            quote = c
            out.append(c)
        elif c == '!':
            break
        else:
            out.append(c)
    return ''.join(out)


BLOCK = re.compile(r'^\s*(\w+\s*:\s*)?block\s*$', re.I)
GOTO = re.compile(r'\bgo\s*to\b', re.I)
IFACE_OP = re.compile(r'^\s*interface\s+(operator|assignment)\s*\(', re.I)
THROW = re.compile(r'\bTHROW_(HARD|WARN)\s*\(')
TYPED_CTOR = re.compile(r'\[\s*character\s*\(\s*(len\s*=\s*)?[^)]*\)\s*::', re.I)
LITERAL = re.compile(r"('[^']*')+|(\"[^\"]*\")+")
STOP = re.compile(r'^\s*(error\s+)?stop\b|\bTHROW_(HARD|WARN)\b', re.I)
PRINT = re.compile(r'\bwrite\s*\(\s*(unit\s*=\s*)?(\*|6|0|output_unit|error_unit)\s*[,)]|\bprint\s*(\*|[\'"(]|\w+\s*,)', re.I)
BIND_MLX = re.compile(r'\bbind\s*\(\s*c\s*,\s*name\s*=\s*[\'"]mlx_', re.I)
LIBC_NAMES = ('strlen', 'memcpy', 'memset', 'posix_memalign', 'malloc', 'free')
BIND_LIBC = re.compile(r'\bbind\s*\(\s*c\s*,\s*name\s*=\s*[\'"](' + '|'.join(LIBC_NAMES) + r')[\'"]', re.I)
USE_MLXF = re.compile(r'^\s*use\s+mlxf\s*(,|$)', re.I)
PROC_HEAD = re.compile(r'^\s*(?!end\b)(?:(?:pure|impure|elemental|recursive|module)\s+)*'
                       r'(?:(?:integer|real|logical|complex|character|type|class|double\s+precision)\s*'
                       r'(?:\([^()]*(?:\([^()]*\))?[^()]*\))?\s+)?'
                       r'(?:(?:pure|impure|elemental|recursive)\s+)*(subroutine|function)\s+(\w+)', re.I)
PROC_END = re.compile(r'^\s*end\s*(subroutine|function)\b', re.I)


def raw_code(line):
    """the line without its comment, string contents kept (for bind(c, name='...'))"""
    out, quote = [], None
    for c in line:
        if quote:
            out.append(c)
            if c == quote:
                quote = None
        elif c in '\'"':
            quote = c
            out.append(c)
        elif c == '!':
            break
        else:
            out.append(c)
    return ''.join(out)


def logical_lines(codes):
    """(first line number, joined statement) over `&` continuations"""
    out, buf, start = [], '', None
    for n, code in enumerate(codes, 1):
        part = code.rstrip()
        if buf:
            part = part.lstrip()
            if part.startswith('&'):
                part = part[1:]
        else:
            start = n
        if part.endswith('&'):
            buf += part[:-1]
            continue
        out.append((start, buf + part))
        buf = ''
    return out


def check_layout(rel, lines, out):
    for n, raw in enumerate(lines, 1):
        code = code_of(raw)
        if BLOCK.match(code):
            out.append('%s:%d: layout: a block construct (declarations at the top; a passage that needs a scope is a procedure)' % (rel, n))
        if GOTO.search(code):
            out.append('%s:%d: layout: goto' % (rel, n))
        if raw.lstrip().startswith('!>') or re.search(r'\s!>', raw):
            out.append('%s:%d: layout: a !> comment' % (rel, n))
        if IFACE_OP.match(code):
            out.append('%s:%d: layout: an interface operator/assignment block (bind the operator as a type-bound generic)' % (rel, n))
        if THROW.search(code) and code.rstrip().endswith('&') or re.search(r'\bTHROW_(HARD|WARN)\s*(&\s*)?$', code.rstrip()):
            out.append('%s:%d: layout: a THROW macro continued over lines (use a named message variable)' % (rel, n))


def first_element(text):
    depth = 0
    for k, c in enumerate(text):
        if c in '([':
            depth += 1
        elif c in ')]':
            if depth == 0:
                return text[:k].strip()
            depth -= 1
        elif c == ',' and depth == 0:
            return text[:k].strip()
    return text.strip()


def check_ctor(rel, codes, out):
    for n, line in logical_lines(codes):
        for m in TYPED_CTOR.finditer(line):
            first = first_element(line[m.end():])
            if not first or LITERAL.fullmatch(first):
                continue
            depth = 0
            for c in line[:m.start()]:
                depth += (c == '(') - (c == ')')
            if depth > 0:
                out.append('%s:%d: layout: a typed character constructor of non-literal elements passed as an '
                           'argument (assign it to a local first)' % (rel, n))


def check_inf(root, files, out):
    for d in sorted(set(os.path.dirname(f) for f in files)):
        inf = os.path.join(d, os.path.basename(d) + '.inf')
        path = os.path.join(root, inf)
        if not os.path.isfile(path) or not read(root, inf).strip():
            out.append('%s: inf: missing or empty (one line describing the directory)' % inf)


def statements(lines):
    """the module's statements, continuations joined, comments and preprocessor lines dropped"""
    stmts, buf = [], ''
    for raw in lines:
        if raw.lstrip().startswith('#'):
            continue
        s = code_of(raw).strip()
        if buf:
            s = s[1:].lstrip() if s.startswith('&') else s
            buf += ' ' + s
        else:
            buf = s
        if buf.endswith('&'):
            buf = buf[:-1]
            continue
        if buf:
            stmts.append(buf)
        buf = ''
    return stmts


def check_surface(rel, lines, out):
    """a module (not a submodule) under src/core restricts: a public :: block, a bare private, no public attribute"""
    stmts = statements(lines)
    if not any(re.match(r'^module\s+\w+$', s, re.I) for s in stmts):
        return
    has_private = has_public = False
    depth = 0
    for s in stmts:
        low = s.lower()
        if re.match(r'^contains\b', low):
            break
        if re.match(r'^(abstract\s+)?interface\b', low) or re.match(r'^type\b(?!\s*\()', low):
            depth += 1
            continue
        if re.match(r'^end\s*(interface|type)\b', low):
            depth -= 1
            continue
        if depth:
            continue
        if low == 'private':
            has_private = True
        elif re.match(r'^public\s*::', low):
            has_public = True
        elif '::' in low and re.search(r',\s*public\b', low.split('::', 1)[0]):
            out.append('%s: surface: a public attribute on a declaration (list it in the public :: block)' % rel)
    if not (has_private and has_public):
        out.append('%s: surface: a library module declares one public :: block and a bare private' % rel)


def check_cbstop(rel, lines, out):
    """no stop inside the body of a bind(c) procedure (outside interface blocks)"""
    stmts = []
    for n, (start, s) in enumerate(logical_lines([code_of(l) for l in lines])):
        stmts.append((start, s))
    iface, inside, name = 0, False, ''
    for start, s in stmts:
        low = s.strip().lower()
        if re.match(r'^(abstract\s+)?interface\b', low):
            iface += 1
            continue
        if re.match(r'^end\s*interface\b', low):
            iface -= 1
            continue
        if iface:
            continue
        m = PROC_HEAD.match(s)
        if m and not inside and re.search(r'\bbind\s*\(\s*c\b', low):
            inside, name = True, m.group(2)
            continue
        if inside and PROC_END.match(s):
            inside = False
            continue
        if inside and STOP.search(s):
            out.append('%s:%d: cbstop: a stop inside %s, which C++ calls (return a status instead)' % (rel, start, name))


def module_variables(lines):
    stmts = statements(lines)
    found, scope, depth = [], None, 0
    for s in stmts:
        low = s.lower()
        if scope is None:
            if re.match(r'^module\s+\w+$', low) or re.match(r'^submodule\s*\(', low):
                scope = 'spec'
            continue
        if re.match(r'^contains\b', low) or re.match(r'^end\s*(sub)?module\b', low):
            scope = None
            continue
        if re.match(r'^(abstract\s+)?interface\b', low) or re.match(r'^type\b(?!\s*\()', low) or re.match(r'^enum\b', low):
            depth += 1
            continue
        if re.match(r'^end\s*(interface|type|enum)\b', low):
            depth -= 1
            continue
        if depth or '::' not in s:
            continue
        attrs = low.split('::', 1)[0]
        if re.match(r'^(public|private|protected|use|import|generic|procedure\s*::|save\s*::|external|intrinsic)\b', low):
            continue
        if re.search(r'\bparameter\b', attrs) or re.match(r'^procedure\b', attrs) and 'pointer' not in attrs:
            continue
        if not re.match(r'^(integer|real|logical|complex|character|type\s*\(|class\s*\(|double\s+precision|procedure)', attrs):
            continue
        names = re.sub(r'\[[^\]]*\]|\(/.*?/\)', '', s.split('::', 1)[1])
        names = re.sub(r'\([^()]*(\([^()]*\))?[^()]*\)', '', names)
        names = re.sub(r'=[^,]*', '', names)
        found.extend(n.strip() for n in names.split(',') if n.strip())
    return found


def ledger_check(rule, counts, ledger, out):
    for rel, n in sorted(counts.items()):
        if rel not in ledger:
            out.append('%s: %s: %d new violation(s)' % (rel, rule, n))
        elif n > ledger[rel][0]:
            out.append('%s: %s: %d, the ledger allows %d (%s)' % (rel, rule, n, ledger[rel][0], ledger[rel][1]))
        elif n < ledger[rel][0]:
            out.append('%s: %s: %d, below the ledger\'s %d - lower the entry in scripts/check_rules.py' % (rel, rule, n, ledger[rel][0]))
    for rel, (n, why) in sorted(ledger.items()):
        if rel not in counts:
            out.append('%s: %s: clean now - delete its ledger entry in scripts/check_rules.py' % (rel, rule))


def main():
    listing = '--list' in sys.argv[1:]
    root = ROOT
    files = sources(root)
    out = []
    cbind, libc, prints, state = {}, {}, {}, {}
    for rel in files:
        lines = read(root, rel).split('\n')
        codes = [code_of(l) for l in lines]
        raws = [raw_code(l) for l in lines]
        check_layout(rel, lines, out)
        check_ctor(rel, codes, out)
        check_cbstop(rel, lines, out)
        n = sum(1 for r in raws if BIND_MLX.search(r))
        if n:
            cbind[rel] = n
        n = sum(1 for r in raws if BIND_LIBC.search(r))
        if n and rel != CORE + 'mlxf_libc.f90':
            libc[rel] = n
        if rel.startswith(CORE) and not rel.endswith('_tester.f90'):
            check_surface(rel, lines, out)
            for k, c in enumerate(codes, 1):
                if USE_MLXF.match(c):
                    out.append('%s:%d: reexport: a library module uses mlxf, the user module' % (rel, k))
            if rel not in PRINT_ALLOWED:
                n = sum(len(PRINT.findall(c)) for c in codes)
                if n:
                    prints[rel] = n
        v = module_variables(lines)
        if v:
            state[rel] = len(v)
    check_inf(root, files, out)
    ledger_check('cbind', cbind, CBIND_LEDGER, out)
    ledger_check('libc', libc, LIBC_LEDGER, out)
    ledger_check('prints', prints, PRINT_LEDGER, out)
    ledger_check('state', state, STATE_LEDGER, out)
    if listing:
        print(__doc__)
        for name, ledger in (('cbind', CBIND_LEDGER), ('libc', LIBC_LEDGER), ('prints', PRINT_LEDGER),
                             ('state', STATE_LEDGER)):
            for rel, (n, why) in sorted(ledger.items()):
                print('ledger %-7s %-50s %3d  %s' % (name, rel, n, why))
    for line in out:
        print('check_rules: ' + line, file=sys.stderr)
    if not out:
        print('check_rules: %d files, every rule holds (ledgers: cbind %d, libc %d, prints %d, state %d files)'
              % (len(files), len(CBIND_LEDGER), len(LIBC_LEDGER), len(PRINT_LEDGER), len(STATE_LEDGER)))
    return 1 if out else 0


if __name__ == '__main__':
    sys.exit(main())
