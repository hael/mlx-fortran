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
             src/core/runtime/mlxf_libc.f90
  reexport   no module under src/core uses mlxf, the user module (test code may); mlxf.f90 re-exports no
             mlxc_ name of the generated layer
  cbstop     a procedure C++ calls (a bind(c) procedure with a body) never stops: no stop, error stop or
             THROW_* inside it
  prints     library code does not print: no write(*,...), print, or write to output_unit/error_unit in
             src/core outside the error module (testers, *_tester.f90, are test code and may)
  state      no module-level variable outside the ledger: module-scope declarations are constants or
             nothing (doc/architecture_principles.md, section 2, lists the allowed state)
  arity      no procedure has more than five dummy arguments; one that needs more takes a spec type.
             Exempt: every bind(c) procedure and interface (the generated layer's, and callbacks whose
             signature C fixes; a bind(c) procedure written for any other reason is a review finding)
  ctorcall   no array constructor holds a reference to a function of the public API (the names of
             src/core/mlxf.f90's public statements): gfortran never finalizes such a result, so a handle in it
             leaks (doc/compiler_issues/gfortran_finalize_ctor_function_results.f90)
  entry      every procedure that implements a name of the user API (the public block of src/core/mlxf.f90:
             its procedures, the specifics of its generics, the bindings of its types except final) opens with
             an entry call (mlxf_enter, mlxf_guard_thread, mlxf_require_device) or a call to a guarded helper
             (ENTRY_HELPERS), whose own first statement is checked the same way: the one-thread guard and the
             initialisation run on every path, empty inputs included. The lifetime bindings (ENTRY_IF_LIVE) may
             open with the guard conditional on a live handle instead. ENTRY_EXEMPT names the exceptions
  defs       exported = defs, local = stay (SIMPLE's and XEMA's rule): a named constant (a parameter, a
             vocabulary constant included) that another module imports is declared in src/defs, unless
             DEFS_EXCEPTIONS claims it with a reason; one used only inside its module stays there. A defs
             module holds constants and behaviourless types only (no contains), imports only the generated
             layer and the intrinsic modules, writes no public statement or
             attribute and no bare private (public by default, as XEMA's defs modules), and lists every name
             it imports in a `private ::` statement, so that an installed .mod re-exports nothing it imports

Python 3.7 or newer, standard library only; it runs before the compile.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOPS = ('src', 'test')
CORE = 'src/core/'
DEFS = 'src/defs/'

CBIND_LEDGER = {}
LIBC_LEDGER = {}
PRINT_ALLOWED = ('src/core/runtime/mlxf_error.f90',)
PRINT_LEDGER = {}
# the process-global state the register allows: the handle registry, the last error and the initialisation
# flag of the library, and the assertion totals of the test library
STATE_LEDGER = {
    'src/core/runtime/mlxf_device.f90': (1, 'the initialisation flag: error handler installed, and whether MLX can allocate'),
    'src/core/runtime/mlxf_error.f90': (1, 'the last error: MLX reports it through a C callback, read by mlx_last_error'),
    'src/core/runtime/mlxf_registry.f90': (1, 'the handle registry: one table of the live MLX objects, serials and counts'),
    'src/test/mlxf_test_utils.f90': (5, 'the assertion totals and the suite and failure records of the test library'),
}
MAX_DUMMIES = 5
# (module, constant) -> reason: a constant another module imports from outside src/defs, argued here
DEFS_EXCEPTIONS = {}
ENTRY_CALLS = ('mlxf_enter', 'mlxf_guard_thread', 'mlxf_require_device')
# helpers an entry may call first instead: each must itself open with an entry call
ENTRY_HELPERS = ('mlxf_unary', 'mlxf_binary', 'weak_scalar')
# the lifetime bindings touch shared state only through a live handle: they may open with the one-thread guard
# conditional on one (between empty handles they run anywhere; nothing they do needs initialisation)
ENTRY_IF_LIVE = ('assign_array', 'kill_array')
ENTRY_EXEMPT = {
    'mlxf_version_string': 'pure: returns a build constant, touches no state and calls no MLX function',
    'mlxf_build_description': 'pure: returns build constants, touches no state and calls no MLX function',
}
USER_MODULE = CORE + 'mlxf.f90'


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


def dummies_of(stmt, name):
    """the dummy names of a procedure head (the first parenthesized list after its name)"""
    rest = stmt[stmt.lower().index(name.lower()) + len(name):].lstrip()
    if not rest.startswith('('):
        return []
    depth, inner = 0, ''
    for c in rest:
        if c == '(':
            depth += 1
            if depth == 1:
                continue
        elif c == ')':
            depth -= 1
            if depth == 0:
                break
        inner += c
    return [d.strip() for d in inner.split(',') if d.strip()]


def check_arity(rel, lines, out):
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        m = PROC_HEAD.match(stmt)
        if not m or re.search(r'\bbind\s*\(\s*c\b', stmt, re.I):
            continue
        n = len(dummies_of(stmt, m.group(2)))
        if n > MAX_DUMMIES:
            out.append('%s:%d: arity: %s has %d dummy arguments, above %d (pass a spec type)' %
                       (rel, start, m.group(2), n, MAX_DUMMIES))


def public_names(root):
    """the lower-case names of the public statements of the user module"""
    path = os.path.join(root, USER_MODULE)
    if not os.path.isfile(path):
        return set()
    names = set()
    for s in statements(read(root, USER_MODULE).split('\n')):
        m = re.match(r'^public\s*::(.*)$', s, re.I)
        if m:
            names |= set(n.strip().lower() for n in m.group(1).split(',') if n.strip())
    return names


def constructors(stmt):
    """the contents of the array constructors [...] and (/.../) of a statement (strings already blanked)"""
    out, i = [], 0
    while i < len(stmt):
        if stmt[i] == '[' or stmt.startswith('(/', i):
            close = ']' if stmt[i] == '[' else '/)'
            j, depth = i + (1 if close == ']' else 2), 1
            while j < len(stmt) and depth:
                if stmt.startswith(close, j) and depth == 1:
                    depth = 0
                    break
                if stmt[j] in '([':
                    depth += 1
                elif stmt[j] in ')]':
                    depth -= 1
                j += 1
            out.append(stmt[i + 1:j])
            i = j + 1
        else:
            i += 1
    return out


def check_ctorcall(rel, lines, api, out):
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        for body in constructors(stmt):
            for m in re.finditer(r'(?<![%\w])([a-z_]\w*)\s*\(', body, re.I):
                if m.group(1).lower() in api:
                    out.append('%s:%d: ctorcall: %s(...) inside an array constructor (a function result there is '
                               'never finalized: assign it to a variable first)' % (rel, start, m.group(1)))


def check_reexport_mlxc(root, out):
    if not os.path.isfile(os.path.join(root, USER_MODULE)):
        return
    for start, stmt in logical_lines([code_of(l) for l in read(root, USER_MODULE).split('\n')]):
        if re.match(r'^\s*(public|use)\b', stmt, re.I) and re.search(r'\bmlxc_\w+', stmt, re.I):
            out.append('%s:%d: reexport: the user module names the generated layer (%s)' %
                       (USER_MODULE, start, re.search(r'\bmlxc_\w+', stmt, re.I).group(0)))


USE_ONLY = re.compile(r'^\s*use\s*(?:,\s*intrinsic\s*::\s*|\s+)(\w+)\s*,\s*only\s*:(.*)$', re.I)


def module_of(lines):
    """the name of the module (not submodule) a file declares, lower case; None if none"""
    for s in statements(lines):
        m = re.match(r'^module\s+(\w+)$', s, re.I)
        if m:
            return m.group(1).lower()
    return None


def module_constants(lines):
    """the named constants declared in a module's specification part, lower case"""
    found, depth = set(), 0
    for s in statements(lines):
        low = s.lower()
        if re.match(r'^contains\b', low):
            break
        if re.match(r'^(abstract\s+)?interface\b', low) or re.match(r'^type\b(?!\s*\()', low):
            depth += 1
            continue
        if re.match(r'^end\s*(interface|type)\b', low):
            depth -= 1
            continue
        if depth or '::' not in s or not re.search(r'\bparameter\b', low.split('::', 1)[0]):
            continue
        names = re.sub(r'\[[^\]]*\]', '', s.split('::', 1)[1])
        names = re.sub(r'\([^()]*(\([^()]*\))?[^()]*\)', '', names)
        names = re.sub(r'=[^,]*', '', names)
        found.update(n.strip().lower() for n in names.split(',') if n.strip())
    return found


def use_imports(lines):
    """(line, module, imported names) of every use statement with an only: list; a rename yields its target"""
    out = []
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        m = USE_ONLY.match(stmt)
        if not m:
            continue
        names = [n.split('=>')[-1].strip().lower() for n in m.group(2).split(',') if n.strip()]
        out.append((start, m.group(1).lower(), names))
    return out


def check_defs(root, files, out):
    """exported = defs, local = stay; and the form of a defs module"""
    owners = {}
    for rel in files:
        if rel.startswith(DEFS):
            continue
        lines = read(root, rel).split('\n')
        mod = module_of(lines)
        if mod:
            owners[mod] = module_constants(lines)
    for rel in files:
        lines = read(root, rel).split('\n')
        me = module_of(lines)
        for start, mod, names in use_imports(lines):
            if mod == me or mod not in owners:
                continue
            for n in names:
                if n in owners[mod] and (mod, n) not in DEFS_EXCEPTIONS:
                    out.append('%s:%d: defs: %s is a constant of %s that another module imports; declare it in '
                               'src/defs (exported = defs, local = stay)' % (rel, start, n.upper(), mod))
        if not rel.startswith(DEFS):
            continue
        privates, imported = set(), set()
        for start, stmt in logical_lines([code_of(l) for l in lines]):
            low = stmt.strip().lower()
            if re.match(r'^contains\b', low):
                out.append('%s:%d: defs: a defs module holds constants and types, no procedures' % (rel, start))
            if low == 'private' or re.match(r'^public\b', low) or \
                    ('::' in low and re.search(r',\s*public\b', low.split('::', 1)[0])):
                out.append('%s:%d: defs: a defs module is public by default: no public statement or attribute, '
                           'no bare private' % (rel, start))
            m = re.match(r'^private\s*::(.*)$', low)
            if m:
                privates.update(n.strip() for n in m.group(1).split(',') if n.strip())
        for start, mod, names in use_imports(lines):
            imported.update(names)
            if not mod.startswith('mlxf_c_') and mod not in ('iso_c_binding', 'iso_fortran_env'):
                out.append('%s:%d: defs: a defs module imports only the generated layer and the intrinsic modules '
                           '(not %s)' % (rel, start, mod))
        for n in sorted(imported - privates):
            out.append('%s: defs: %s is imported but not in a private :: statement (an installed .mod would '
                       're-export it)' % (rel, n))


def api_entries(root, files, api):
    """the procedures that implement the user API: public procedures, specifics of public generics, and the
    bindings of public types (final excluded)"""
    entries = {}
    for rel in files:
        if not rel.startswith(CORE) or rel.endswith('_tester.f90'):
            continue
        stmts = statements(read(root, rel).split('\n'))
        generic = None
        ptype = None
        for st in stmts:
            low = st.lower()
            m = re.match(r'^interface\s+(\w+(?:\s*\([^)]*\))?)\s*$', low)
            if m:
                generic = re.sub(r'\s+', '', m.group(1))
                continue
            if low.startswith('end interface'):
                generic = None
                continue
            if generic and generic in api:
                m = re.match(r'^module\s+procedure\s+(.*)$', low)
                if m:
                    for n in m.group(1).split(','):
                        entries[n.strip()] = generic
                m = re.match(r'^module\b.*\b(subroutine|function)\s+(\w+)', low)
                if m:
                    entries[m.group(2)] = generic
            m = re.match(r'^type\s*(?:,[^:]*)?::\s*(\w+)\s*$|^type\s+(\w+)\s*$', low)
            if m:
                ptype = (m.group(1) or m.group(2))
                continue
            if low.startswith('end type'):
                ptype = None
                continue
            if ptype and ptype in api:
                m = re.match(r'^procedure\b[^:]*::\s*(\w+)\s*(?:=>\s*(\w+))?$', low)
                if m:
                    entries[m.group(2) or m.group(1)] = '%s%%%s' % (ptype, m.group(1))
                m = re.match(r'^generic\b[^:]*::\s*(.*?)\s*=>\s*(.*)$', low)
                if m:
                    for n in m.group(2).split(','):
                        entries[n.strip()] = re.sub(r'\s+', '', m.group(1))
    for name in api:
        entries.setdefault(name, name)
    return entries


def first_statements(root, files):
    """procedure name -> (rel, line, first executable statement) for every procedure in src/core"""
    firsts = {}
    for rel in files:
        if not rel.startswith(CORE) or rel.endswith('_tester.f90'):
            continue
        ls = logical_lines([code_of(l) for l in read(root, rel).split('\n')])
        k = 0
        while k < len(ls):
            start, st = ls[k]
            m = PROC_HEAD.match(st)
            if m and not re.match(r'^\s*module\s+procedure\b', st, re.I):
                name = m.group(2).lower()
                j = k + 1
                while j < len(ls):
                    t = ls[j][1].strip()
                    tl = t.lower()
                    if not t or tl.startswith(('use ', 'use,', 'implicit', 'import')) or \
                            (re.match(r'^(integer|real|logical|complex|character|type|class|procedure)\b', tl)
                             and '::' in t):
                        j += 1
                        continue
                    break
                # an interface body ends after its declarations: only implementations are recorded
                if j < len(ls) and not re.match(r'^end\s*(subroutine|function)\b', ls[j][1].strip(), re.I):
                    firsts.setdefault(name, (rel, ls[j][0], ls[j][1].strip()))
            k += 1
    return firsts


def check_entry(root, files, api, out):
    entries = api_entries(root, files, api)
    firsts = first_statements(root, files)
    opens = re.compile(r'^call\s+(%s)\s*\(' % '|'.join(ENTRY_CALLS + ENTRY_HELPERS), re.I)
    base = re.compile(r'^call\s+(%s)\s*\(' % '|'.join(ENTRY_CALLS), re.I)
    if_live = re.compile(r'^if\s*\(\s*c_associated\(.*\)\s*\)\s*call\s+mlxf_guard_thread\s*\(', re.I)
    for helper in ENTRY_HELPERS:
        if helper in firsts and not base.match(firsts[helper][2]):
            rel, line, st = firsts[helper]
            out.append('%s:%d: entry: the guarded helper %s does not open with an entry call' % (rel, line, helper))
    for name, public in sorted(entries.items()):
        if name not in firsts or name in ENTRY_EXEMPT or name in ENTRY_CALLS:
            continue
        rel, line, st = firsts[name]
        if name in ENTRY_IF_LIVE and if_live.match(st):
            continue
        if not opens.match(st):
            out.append('%s:%d: entry: %s (%s) does not open with an entry call (mlxf_enter first, before any '
                       'operand is touched)' % (rel, line, name, public))


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
    api = public_names(root)
    check_reexport_mlxc(root, out)
    for rel in files:
        lines = read(root, rel).split('\n')
        codes = [code_of(l) for l in lines]
        raws = [raw_code(l) for l in lines]
        check_layout(rel, lines, out)
        check_ctor(rel, codes, out)
        check_cbstop(rel, lines, out)
        check_arity(rel, lines, out)
        check_ctorcall(rel, lines, api, out)
        n = sum(1 for r in raws if BIND_MLX.search(r))
        if n:
            cbind[rel] = n
        n = sum(1 for r in raws if BIND_LIBC.search(r))
        if n and rel != CORE + 'runtime/mlxf_libc.f90':
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
    check_defs(root, files, out)
    check_entry(root, files, api, out)
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
