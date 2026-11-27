"""The lifetime analysis shared by the repository's rules (scripts/check_rules.py, rules ctorcall and ctorexpr) and
the consumer checker (scripts/check_consumer.py, installed with the package): one implementation of how a Fortran
file is read (statements, constructors, the handles it declares) and of each lifetime rule.

The rules a consumer's sources are checked against (CONSUMER_RULES), each for a form gfortran 16.2 and earlier
leaks or corrupts silently (doc/policies/binding_contract_policy.md, section 3, "Unsupported"; the reproducers are
in doc/compiler_issues/), each finding with the safe spelling:

  ctorcall   a function of mlxf (an mlx_* or mlxf_* name imported from mlxf, a renamed import under its local
             name) referenced inside an array constructor: [a, mlx_from(x)]
  ctorexpr   an element of an array constructor that refers to a handle and is not a bare designator:
             [a*2.0, b], [-a, b], [(a), b], [exp(a), b], a renamed generic [e(a), b]
  wholefunc  a function result or expression assigned to a whole array (or a section) of handles: v = exp(a),
             v(1:2) = a*2.0
  viewexpr   mlx_view of an expression, call mlx_view(exp(a), p): the result dies at the end of the statement
  overlap    an overlapping section assignment of an array of handles, v(2:3) = v(1:2)
  alloccomp  a derived type with an allocatable handle component and no type-bound defined assignment: its
             intrinsic assignment is a bitwise copy of the component
  allocsrc   allocate(..., source=...) or mold= of a handle variable: a bitwise copy
  arrayintr  an array intrinsic (pack, unpack, spread, transpose, reshape, merge, cshift, eoshift) applied to an
             array of handles: a bitwise copy
  selfassign intrinsic self-assignment w = w of a variable whose derived type holds handle components

What a reading of the source cannot see, and so is never reported (a clean result is no proof that a program
leaks nothing; mlx_live_count() at run time is the check of record):
  - handles the file does not declare: a variable, component or function result whose type comes from another
    module or file than the ones checked (each file is read alone; a type's components are known only when the
    type is defined in the same file);
  - aliasing: pointers, associate names, dummies passed on, a handle reached through a procedure argument;
  - generic resolution: a renamed or user generic that returns a handle is seen only as a function of mlxf
    (ctorcall) or through its handle arguments (ctorexpr);
  - preprocessing: directives are not evaluated (code in an inactive #if branch is checked too) and macros are
    not expanded (a macro that expands to an unsafe form is not seen);
  - fixed-form source, INCLUDE files, statements split by ";" inside one line are read as one statement;
  - OpenMP private copies of handles, and any form not listed above.

Python 3.7 or newer, standard library only.
"""
import re

HANDLE_TYPES = ('mlx_array', 'mlx_function', 'mlx_metal_kernel', 'mlx_grad_function', 'mlx_function_exporter',
                'mlx_imported_function', 'mlx_stream', 'mlx_group')
HANDLE_DECL = re.compile(r'^(type|class)\s*\(\s*(' + '|'.join(HANDLE_TYPES) + r')\s*\)(.*)$', re.I)
HANDLE_PREFIX = re.compile(r'\b(type|class)\s*\(\s*(' + '|'.join(HANDLE_TYPES) + r')\s*\)', re.I)
HANDLE_GETTERS = ('shape', 'ndim', 'size', 'kind')
INQUIRY = re.compile(r'(?<![%\w])(size|lbound|ubound|shape|rank|allocated|present|storage_size|is_contiguous|'
                     r'same_type_as|extends_type_of)\s*\(', re.I)

PROC_HEAD = re.compile(r'^\s*(?!end\b)(?:(?:pure|impure|elemental|recursive|module)\s+)*'
                       r'(?:(?:integer|real|logical|complex|character|type|class|double\s+precision)\s*'
                       r'(?:\([^()]*(?:\([^()]*\))?[^()]*\))?\s+)?'
                       r'(?:(?:pure|impure|elemental|recursive)\s+)*(subroutine|function)\s+(\w+)', re.I)


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


def logical_lines(codes):
    """(first line number, joined statement) over `&` continuations; a blank, comment-only or preprocessor
    line inside a continuation is skipped, as the compiler skips it"""
    out, buf, start = [], '', None
    for n, code in enumerate(codes, 1):
        part = code.rstrip()
        if buf and (not part.strip() or part.lstrip().startswith('#')):
            continue
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


def split_top(text):
    """text split at the commas outside parentheses and brackets"""
    parts, depth, cur = [], 0, []
    for c in text:
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        if c == ',' and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(c)
    parts.append(''.join(cur))
    return parts


def matching(text, i):
    """the index of the bracket closing the one at text[i], or -1"""
    depth = 0
    for j in range(i, len(text)):
        if text[j] in '([':
            depth += 1
        elif text[j] in ')]':
            depth -= 1
            if depth == 0:
                return j
    return -1


def handle_names(lines):
    """the lower-case names a file declares of a handle type: variables, dummies and components"""
    names = set()
    for s in statements(lines):
        m = HANDLE_DECL.match(s)
        if not m:
            continue
        rest = m.group(3)
        if re.match(r'\s*(function|subroutine|pure|impure|elemental|recursive|module)\b', rest, re.I):
            continue
        if '::' in rest:
            rest = rest.split('::', 1)[1]
        elif rest.lstrip().startswith(','):
            continue
        for ent in split_top(rest):
            n = re.match(r'\s*([a-z_]\w*)', ent, re.I)
            if n:
                names.add(n.group(1).lower())
    return names


def handle_functions(lines, handles):
    """the lower-case names of the functions a file defines or declares whose result is a handle"""
    names = set()
    for s in statements(lines):
        m = PROC_HEAD.match(s)
        if not m or m.group(1).lower() != 'function':
            continue
        name = m.group(2).lower()
        r = re.search(r'\bresult\s*\(\s*(\w+)\s*\)', s, re.I)
        result = r.group(1).lower() if r else name
        if HANDLE_PREFIX.search(s[:m.start(1)]) or result in handles:
            names.add(name)
    return names


def blank_inquiries(expr):
    """expr with the argument lists of inquiry intrinsics blanked (their result is an integer or logical)"""
    out = expr
    for m in INQUIRY.finditer(expr):
        j = matching(expr, m.end() - 1)
        if j > 0:
            out = out[:m.end()] + ' ' * (j - m.end()) + out[j:]
    return out


def handle_refs(expr, handles, functions=()):
    """the identifiers of expr that refer to a handle, or call a function whose result is one"""
    expr = blank_inquiries(expr)
    refs = []
    for m in re.finditer(r'[a-z_]\w*', expr, re.I):
        k = m.start()
        if k > 0 and (expr[k - 1].isalnum() or expr[k - 1] == '_'):
            continue
        if k > 1 and expr[k - 1] == '.' and expr[k - 2].isdigit():
            continue
        name = m.group(0).lower()
        if name not in handles and name not in functions:
            continue
        after = expr[m.end():]
        if re.match(r'\s*=(?!=)', after):
            continue
        rest = after.lstrip()
        if rest.startswith('('):
            j = matching(rest, 0)
            rest = rest[j + 1:] if j > 0 else rest
        g = re.match(r'\s*%\s*([a-z_]\w*)\s*\(', rest, re.I)
        if g and g.group(1).lower() in HANDLE_GETTERS:
            continue
        refs.append(m.group(0))
    return refs


def designator_parts(expr):
    """[(name, subscripts), ...] of a designator name[(...)][%name[(...)]]..., or None"""
    e, parts = expr.strip(), []
    while True:
        m = re.match(r'([a-z_]\w*)\s*', e, re.I)
        if not m:
            return None
        e, sub = e[m.end():], ''
        if e.startswith('('):
            j = matching(e, 0)
            if j < 0:
                return None
            e, sub = e[j + 1:].lstrip(), e[1:j]
        parts.append((m.group(1).lower(), sub))
        if not e:
            return parts
        if not e.startswith('%'):
            return None
        e = e[1:].lstrip()


def implied_do_items(elem):
    """the items of an implied-do (items, i = a, b), or None when elem is not one"""
    e = elem.strip()
    if not e.startswith('(') or matching(e, 0) != len(e) - 1:
        return None
    inner = split_top(e[1:-1])
    for k, part in enumerate(inner):
        if k > 0 and re.match(r'\s*[a-z_]\w*\s*=(?!=)', part, re.I):
            return inner[:k]
    return None


def ctor_violations(body, handles, functions=()):
    """the elements of a constructor body that refer to a handle without being a bare designator"""
    body = body.strip()
    if body.startswith('/'):
        body = body[1:]
    top = split_top(body)
    if top and '::' in top[0]:
        top[0] = top[0].split('::', 1)[1]
    bad = []
    for elem in top:
        e = elem.strip()
        items = implied_do_items(e)
        if items is not None:
            bad += ctor_violations(','.join(items), handles, functions)
            continue
        if e.startswith('[') and matching(e, 0) == len(e) - 1:
            bad += ctor_violations(e[1:-1], handles, functions)
            continue
        if not handle_refs(e, handles, functions):
            continue
        parts = designator_parts(e)
        if parts and parts[-1][0] in handles and parts[-1][0] not in functions and \
                not any(handle_refs(sub, handles, functions) for _, sub in parts):
            continue
        bad.append(e)
    return bad


def imported_names(lines):
    """the lower-case names a file imports through `use ..., only:` lists (a renamed one under its local name)"""
    names = set()
    for s in statements(lines):
        m = re.match(r'^use\b.*\bonly\s*:(.*)$', s, re.I)
        if m:
            names |= set(n.split('=>')[0].strip().lower() for n in m.group(1).split(',') if n.strip())
    return names


CONSUMER_RULES = ('ctorcall', 'ctorexpr', 'wholefunc', 'viewexpr', 'overlap', 'alloccomp', 'allocsrc', 'arrayintr',
                  'selfassign')
ARRAY_INTRINSICS = ('pack', 'unpack', 'spread', 'transpose', 'reshape', 'merge', 'cshift', 'eoshift')
SAFE = {
    'ctorcall': 'assign the result to a variable first, then list the variable',
    'ctorexpr': 'assign the expression to a variable first, then list the variable',
    'wholefunc': 'assign a variable (w = t after t = exp(a)) or each element (v(i) = exp(a))',
    'viewexpr': 'assign the expression to a named variable w, then call mlx_view(w, p); p is valid while w is unchanged',
    'overlap': 'assign element by element in a safe order, or through a second array',
    'alloccomp': 'give the type a type-bound defined assignment that copies the component (binding policy, section 3)',
    'allocsrc': 'allocate without source= or mold=, then assign',
    'arrayintr': 'build the new array of handles element by element',
    'selfassign': 'leave w = w out (it changes nothing), or give the type a defined assignment',
}


def ctorcall_findings(lines, names):
    """(line, name) for each reference to one of names (lower case) inside an array constructor"""
    found = []
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        for body in constructors(stmt):
            for m in re.finditer(r'(?<![%\w])([a-z_]\w*)\s*\(', body, re.I):
                if m.group(1).lower() in names:
                    found.append((start, m.group(1)))
    return found


def ctorexpr_findings(lines, functions=()):
    """(line, element) for each element of a constructor that refers to a handle without being a bare designator"""
    handles = handle_names(lines)
    if not handles:
        return []
    functions = handle_functions(lines, handles) | set(functions)
    found = []
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        for body in constructors(stmt):
            for e in ctor_violations(body, handles, functions):
                found.append((start, e))
    return found


def mlxf_imports(lines):
    """the names a file imports from mlxf: {local: remote} (lower case), and whether a `use mlxf` without an only
    list makes every public name visible under its own name"""
    names, everything = {}, False
    for s in statements(lines):
        m = re.match(r'^use\s*(?:,\s*non_intrinsic\s*)?(?:::)?\s*mlxf\s*(,\s*only\s*:(.*))?$', s, re.I)
        if not m:
            continue
        if m.group(1) is None:
            everything = True
            continue
        for item in m.group(2).split(','):
            if not item.strip():
                continue
            local, _, remote = item.partition('=>')
            local = local.strip().lower()
            names[local] = (remote.strip() or local).lower()
    return names, everything


def library_names(lines):
    """the local names under which the file sees mlxf's own functions (mlx_*, mlxf_*), and the local name of
    mlx_view"""
    imports, everything = mlxf_imports(lines)
    names = set(l for l, r in imports.items() if r.startswith(('mlx_', 'mlxf_')))
    views = set(l for l, r in imports.items() if r == 'mlx_view')
    if everything:
        views.add('mlx_view')
    return names, views, everything


def handle_holders(lines):
    """the lower-case names of the derived types the file defines that hold a handle component, each with whether
    it binds a defined assignment and the lines of its allocatable handle components"""
    types, cur = {}, None
    for n, stmt in logical_lines([code_of(l) for l in lines]):
        s = stmt.strip()
        m = re.match(r'^type\s*(?:,[^:]*)?::\s*([a-z_]\w*)\s*$|^type\s+([a-z_]\w*)\s*$', s, re.I)
        if m:
            cur = (m.group(1) or m.group(2)).lower()
            types[cur] = {'handles': False, 'assign': False, 'alloc': []}
            continue
        if cur is None:
            continue
        if re.match(r'^end\s*type\b', s, re.I):
            cur = None
            continue
        if re.match(r'^generic\b.*\bassignment\s*\(\s*=\s*\)', s, re.I):
            types[cur]['assign'] = True
        d = HANDLE_DECL.match(s)
        if d:
            types[cur]['handles'] = True
            attrs = d.group(3).split('::', 1)[0] if '::' in d.group(3) else ''
            if re.search(r'\ballocatable\b', attrs, re.I):
                types[cur]['alloc'].append(n)
    return dict((k, v) for k, v in types.items() if v['handles'])


def assignment_sides(stmt):
    """(left, right) of an assignment statement, or None (pointer assignment, declarations and keyword lists are
    not assignments)"""
    s = stmt.strip()
    m = re.match(r'^(?:\d+\s+)?((?:[a-z_]\w*)(?:\s*\([^=]*?\))?(?:\s*%\s*[a-z_]\w*(?:\s*\([^=]*?\))?)*)\s*=(?![=>])(.*)$',
                 s, re.I)
    if not m or re.match(r'^(if|where|forall|do|call|print|write|read|integer|real|logical|character|complex|'
                         r'type|class|parameter|data)\b', s, re.I):
        return None
    return m.group(1).strip(), m.group(2).strip()


UNIT_HEAD = re.compile(r'^\s*(?:program|(?:sub)?module(?!\s+procedure\b))\b\s*(?:\([^)]*\)\s*)?[a-z_]\w*\s*$', re.I)
UNIT_END = re.compile(r'^\s*end\s*(program|module|submodule|function|subroutine|procedure)?\b(?!\s*(do|if|type|'
                      r'interface|select|where|forall|associate|block|critical|enum)\b)', re.I)
TYPE_SPEC = re.compile(r'^\s*(integer|real|logical|complex|character|double\s+precision|type\s*\(\s*([a-z_]\w*)\s*\)|'
                       r'class\s*\(\s*([a-z_]\w*)\s*\))', re.I)


def declared(stmt, holders):
    """{name: kind} of a declaration statement with '::' (kind 'harray', 'hscalar', 'holder' or 'other'), or {}"""
    m = TYPE_SPEC.match(stmt)
    if not m or '::' not in stmt:
        return {}
    tname = (m.group(2) or m.group(3) or '').lower()
    attrs, ents = stmt.split('::', 1)
    dimensioned = re.search(r'\bdimension\s*\(', attrs, re.I) is not None
    out = {}
    for ent in split_top(ents):
        n = re.match(r'\s*([a-z_]\w*)\s*(\()?', ent, re.I)
        if not n:
            continue
        if tname in HANDLE_TYPES:
            kind = 'harray' if dimensioned or n.group(2) else 'hscalar'
        elif tname in holders:
            kind = 'holder'
        else:
            kind = 'other'
        out[n.group(1).lower()] = kind
    return out


def check_lines(label, lines):
    """the findings of CONSUMER_RULES on a file's lines, as 'label:line: rule: message (safe spelling)'. Names
    are resolved in the scope of each statement: a procedure's declarations hide its host's"""
    out = []

    def say(n, rule, what):
        out.append('%s:%d: %s: %s (%s)' % (label, n, rule, what, SAFE[rule]))
    names, views, everything = library_names(lines)
    known = _ANY_LIBRARY if everything else names
    for n, name in ctorcall_findings(lines, known):
        say(n, 'ctorcall', '%s(...) inside an array constructor: a function result there is never finalized' % name)
    for n, e in ctorexpr_findings(lines):
        say(n, 'ctorexpr', '%s inside an array constructor refers to a handle and is not a bare designator: never '
                           'finalized' % e.strip())
    handles = handle_names(lines)
    holders = handle_holders(lines)
    for t, info in sorted(holders.items()):
        if info['alloc'] and not info['assign']:
            for n in info['alloc']:
                say(n, 'alloccomp', 'type %s holds an allocatable handle component and binds no defined assignment: '
                                    'its intrinsic assignment copies the handle bitwise' % t)
    functions = handle_functions(lines, handles)
    scopes = [{}]
    in_type = False

    def kind(name):
        for scope in reversed(scopes):
            if name in scope:
                return scope[name]
        return None

    def refers(expr):
        """whether expr refers to a handle or calls a function of mlxf"""
        calls = re.findall(r'(?<![%\w])([a-z_]\w*)\s*\(', expr, re.I)
        return bool(handle_refs(expr, handles, functions)) or any(c.lower() in known for c in calls)
    for n, stmt in logical_lines([code_of(l) for l in lines]):
        s = stmt.strip()
        if not s:
            continue
        if re.match(r'^type\s*(?:,[^:]*)?::\s*[a-z_]\w*\s*$|^type\s+[a-z_]\w*\s*$', s, re.I):
            in_type = True
            continue
        if in_type:
            in_type = not re.match(r'^end\s*type\b', s, re.I)
            continue
        if UNIT_HEAD.match(s) or (PROC_HEAD.match(s) and not re.match(r'^\s*module\s+procedure\b', s, re.I)):
            scopes.append({})
            continue
        if UNIT_END.match(s):
            if len(scopes) > 1:
                scopes.pop()
            continue
        decl = declared(s, holders)
        if decl:
            scopes[-1].update(decl)
            continue
        call = re.match(r'^call\s+([a-z_]\w*)\s*\((.*)\)\s*$', s, re.I)
        if call and (call.group(1).lower() in views or (everything and call.group(1).lower() == 'mlx_view')):
            first = split_top(call.group(2))[0]
            fparts = designator_parts(first)
            # a component (w%r) is known by its type's declaration, a variable by its scope
            named = fparts and (kind(fparts[-1][0]) in ('harray', 'hscalar') if len(fparts) == 1 else
                                fparts[-1][0] in handles and fparts[-1][0] not in functions)
            if not named:
                say(n, 'viewexpr', 'mlx_view of the expression %s: its result dies at the end of the statement and '
                                   'the pointer dangles' % first.strip())
        if re.match(r'^allocate\s*\(', s, re.I) and re.search(r'\b(source|mold)\s*=', s, re.I):
            inner = s[s.index('(') + 1:s.rindex(')')]
            objs = [e for e in split_top(inner) if re.match(r'\s*[a-z_]', e, re.I) and not re.match(r'\s*\w+\s*=', e)]
            if any(kind(re.match(r'\s*([a-z_]\w*)', e, re.I).group(1).lower()) in ('harray', 'hscalar', 'holder')
                   for e in objs):
                say(n, 'allocsrc', 'allocate with source= or mold= of a handle: a bitwise copy')
        copied = False
        for m in re.finditer(r'(?<![%\w])(' + '|'.join(ARRAY_INTRINSICS) + r')\s*\(', s, re.I):
            j = matching(s, m.end() - 1)
            if j < 0:
                continue
            first = split_top(s[m.end():j])[0].strip()
            if re.fullmatch(r'[a-z_]\w*(\s*\(\s*:?\s*\))?', first, re.I) and \
                    kind(re.match(r'[a-z_]\w*', first, re.I).group(0).lower()) == 'harray':
                say(n, 'arrayintr', '%s of the array of handles %s: a bitwise copy of each handle' % (m.group(1), first))
                copied = True
        sides = assignment_sides(s)
        if not sides:
            continue
        left, right = sides
        lparts = designator_parts(left)
        if not lparts:
            continue
        lname, lsub = lparts[0]
        if len(lparts) == 1 and kind(lname) == 'harray' and (not lsub or ':' in lsub):
            rparts = designator_parts(right)
            whole_var = rparts is not None and kind(rparts[-1][0]) in ('harray', 'hscalar') and \
                not any(refers(sub) for _, sub in rparts)
            if rparts and len(rparts) == 1 and rparts[0][0] == lname and lsub and ':' in lsub and ':' in rparts[0][1]:
                say(n, 'overlap', 'the section assignment %s = %s copies the right side without the defined '
                                  'assignment: the result is stale' % (left, right))
            elif not whole_var and not copied and not right.lstrip().startswith(('[', '(/')) and refers(right):
                say(n, 'wholefunc', '%s = %s assigns one result to every element of an array of handles: never '
                                    'finalized' % (left, right))
        if len(lparts) == 1 and not lsub and kind(lname) == 'holder' and \
                re.fullmatch(r'\(?\s*%s\s*\)?' % re.escape(lname), right, re.I):
            say(n, 'selfassign', 'intrinsic self-assignment of %s, whose type holds handles: its components are '
                                 'released before they are copied' % lname)
    return out


class _AnyLibrary(object):
    """every mlx_* and mlxf_* name: what a `use mlxf` without an only list makes visible"""

    def __contains__(self, name):
        return name.startswith(('mlx_', 'mlxf_'))


_ANY_LIBRARY = _AnyLibrary()
