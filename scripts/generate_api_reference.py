#!/usr/bin/env python3
"""generate_api_reference.py -- doc/api_reference.md, the reference of every public name of mlxf, from the source.

The names are rank 2d's inventory (scripts/list_public_api.py: the public statements of src/core/mlxf.f90, in their
order); each is followed through the `use ..., only:` line of mlxf.f90 that imports it to its module, and there
to what it is: a generic interface and each of its specifics, a procedure, a type (its public bindings and, for an
operator, every specific), a spec type's components, or a constant and its codes. A specific's entry is its
signature, one line per dummy with the dummy's own declaration (kind, rank, intent, optional), the result of a
function, and the comment above it in the source; each name links to the section of the binding policy that holds
its contract (MODULE_SECTIONS). A name that cannot be followed, a module without a section, or a procedure whose
declaration is not found fails the generator: the reference never guesses.

usage: scripts/generate_api_reference.py [ROOT]              writes doc/api_reference.md
       scripts/generate_api_reference.py [ROOT] --check      exit 1 when doc/api_reference.md is not current
       scripts/generate_api_reference.py [ROOT] --self-test  planted changes: a changed dummy, a removed public
                                                             name, an unknown one, must each change or fail it
exit status: 0, 1 (not current, or a self-test failed), 2 (a name or declaration could not be followed).
Python 3.7, standard library only.
"""
import os
import re
import sys

# no bytecode cache beside the sources: the release gate holds the source tree unchanged by a build
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import list_public_api  # noqa: E402

OUT = os.path.join('doc', 'api_reference.md')
MODULE = os.path.join('src', 'core', 'mlxf.f90')
POLICY = 'policies/binding_contract_policy.md'
# the section of the binding policy that holds each module's contract (GitHub's anchors of its headings)
MODULE_SECTIONS = {
    'mlxf_defs': ('5. Kinds and scalars', '5-kinds-and-scalars'),
    'mlxf_version': ('7. Devices, threads, precision', '7-devices-threads-precision'),
    'mlxf_error': ('6. Errors', '6-errors'),
    'mlxf_registry': ('3. Lifetime', '3-lifetime'),
    'mlxf_device': ('7. Devices, threads, precision', '7-devices-threads-precision'),
    'mlxf_stream': ('16. Streams, device availability and Metal capture',
                    '16-streams-device-availability-and-metal-capture'),
    'mlxf_memory': ('8. Evaluation and memory', '8-evaluation-and-memory'),
    'mlxf_array': ('3. Lifetime', '3-lifetime'),
    'mlxf_transfer': ('4. Data in and out', '4-data-in-and-out'),
    'mlxf_ops_elementwise': ('5. Kinds and scalars', '5-kinds-and-scalars'),
    'mlxf_ops_math': ('10. Operations, matrices and Fourier transforms',
                      '10-operations-matrices-and-fourier-transforms'),
    'mlxf_ops_logic': ('10. Operations, matrices and Fourier transforms',
                       '10-operations-matrices-and-fourier-transforms'),
    'mlxf_ops_shape': ('10. Operations, matrices and Fourier transforms',
                       '10-operations-matrices-and-fourier-transforms'),
    'mlxf_ops_index': ('10. Operations, matrices and Fourier transforms',
                       '10-operations-matrices-and-fourier-transforms'),
    'mlxf_ops_reduce': ('10. Operations, matrices and Fourier transforms',
                        '10-operations-matrices-and-fourier-transforms'),
    'mlxf_ops_create': ('10. Operations, matrices and Fourier transforms',
                        '10-operations-matrices-and-fourier-transforms'),
    'mlxf_ops_sort': ('10. Operations, matrices and Fourier transforms',
                      '10-operations-matrices-and-fourier-transforms'),
    'mlxf_linalg': ('10. Operations, matrices and Fourier transforms',
                    '10-operations-matrices-and-fourier-transforms'),
    'mlxf_linalg_matrix': ('10. Operations, matrices and Fourier transforms',
                           '10-operations-matrices-and-fourier-transforms'),
    'mlxf_conv': ('10. Operations, matrices and Fourier transforms', '10-operations-matrices-and-fourier-transforms'),
    'mlxf_fft': ('10. Operations, matrices and Fourier transforms', '10-operations-matrices-and-fourier-transforms'),
    'mlxf_io': ('17. Arrays in files, and the text of a graph', '17-arrays-in-files-and-the-text-of-a-graph'),
    'mlxf_distributed': ('18. Distributed computing', '18-distributed-computing'),
    'mlxf_compile': ('11. Fortran callbacks and graph compilation', '11-fortran-callbacks-and-graph-compilation'),
    'mlxf_transforms': ('14. Function transforms, functions in files, compilation controls',
                        '14-function-transforms-functions-in-files-compilation-controls'),
    'mlxf_export': ('14. Function transforms, functions in files, compilation controls',
                    '14-function-transforms-functions-in-files-compilation-controls'),
    'mlxf_fast': ('15. Fused layers', '15-fused-layers'),
    'mlxf_random': ('13. Random numbers', '13-random-numbers'),
}
PREFIX = r'(?:(?:pure|impure|elemental|recursive|module)\s+)*'
TYPESPEC = r'(?:(?:integer|real|logical|complex|character|type|class)\s*(?:\((?:[^()]|\([^()]*\))*\))?\s+)?'
HEAD = re.compile(r'^\s*' + PREFIX + TYPESPEC + PREFIX + r'(function|subroutine)\s+(\w+)\s*\(([^)]*)\)'
                  r'(?:\s*result\s*\(\s*(\w+)\s*\))?', re.I)
DECL = re.compile(r'^\s*(integer|real|logical|complex|character|type\s*\(|class\s*\(|procedure\s*\(|double\s+precision)',
                  re.I)


class Unresolved(Exception):
    """a public name, a module or a declaration the generator cannot follow"""


def read(root, rel):
    with open(os.path.join(root, rel), encoding='utf-8') as h:
        return h.read()


def units(lines):
    """[(line number, statement, the comment block just above it)]: continuations joined, comments dropped"""
    out, cur, start, comment, pending = [], '', 0, [], []
    for n, raw in enumerate(lines, 1):
        stripped = raw.strip()
        if not cur and stripped.startswith('!'):
            text = stripped.lstrip('!').strip()
            if not text.startswith('@descr'):
                pending.append(text)
            continue
        code = list_public_api.statements(raw)[0] if raw.strip() else ''
        if not code.strip():
            if not cur:
                pending = []
            continue
        part = code.strip()
        if cur and part.startswith('&'):
            part = part[1:]
        if not cur:
            start, comment, pending = n, pending, []
        if part.endswith('&'):
            cur += part[:-1]
            continue
        out.append((start, re.sub(r'\s+', ' ', (cur + part).strip()), ' '.join(comment)))
        cur = ''
    return out


class Source(object):
    """the statements of every Fortran file of src/core and src/defs, and which file holds each module or submodule"""

    def __init__(self, root, override=None):
        self.files, self.units, self.of_module = [], {}, {}
        for top in ('src/core', 'src/defs'):
            for d, _, fs in os.walk(os.path.join(root, top)):
                for f in sorted(fs):
                    if not f.endswith('.f90') or f.endswith('_tester.f90'):
                        continue
                    rel = os.path.relpath(os.path.join(d, f), root)
                    text = (override or {}).get(rel)
                    if text is None:
                        text = read(root, rel)
                    self.files.append(rel)
                    self.units[rel] = units(text.split('\n'))
                    for _, s, _ in self.units[rel][:3]:
                        m = re.match(r'^module\s+(\w+)\s*$', s, re.I)
                        if m:
                            self.of_module.setdefault(m.group(1).lower(), []).insert(0, rel)
                        m = re.match(r'^submodule\s*\(\s*(\w+)\s*\)\s*\w+', s, re.I)
                        if m:
                            self.of_module.setdefault(m.group(1).lower(), []).append(rel)

    def module_files(self, module):
        if module not in self.of_module:
            raise Unresolved('module %s has no file under src/core or src/defs' % module)
        return self.of_module[module]


def imports(root, override=None):
    """{public name (lower case): [modules]} from the use lines of mlxf.f90"""
    text = (override or {}).get(MODULE) or read(root, MODULE)
    out = {}
    for s in list_public_api.statements(text):
        m = re.match(r'^\s*use\s+(\w+)\s*,\s*only\s*:(.*)$', s, re.I)
        if m:
            for n in m.group(2).split(','):
                if n.strip():
                    out.setdefault(n.strip().lower(), []).append(m.group(1).lower())
    return out


def split_top(text):
    parts, depth, cur = [], 0, ''
    for c in text:
        depth += (c in '([') - (c in ')]')
        if c == ',' and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += c
    return parts + [cur]


def procedure(src, module, name):
    """(header, [(dummy, declaration)], result declaration or None, comment) of a procedure of module or its
    submodules; the first file that declares its dummies wins (an interface body declares them as the body does)"""
    for rel in src.module_files(module):
        us = src.units[rel]
        for k, (n, s, comment) in enumerate(us):
            m = HEAD.match(s)
            if not m or m.group(2).lower() != name.lower() or re.match(r'^\s*module\s+procedure\b', s, re.I):
                continue
            kind, dummies, result = m.group(1).lower(), [d.strip() for d in m.group(3).split(',') if d.strip()], m.group(4)
            decls = {}
            for _, t, _ in us[k + 1:]:
                if re.match(r'^end\s*(function|subroutine)\b', t, re.I):
                    break
                if re.match(r'^(use|implicit|import)\b', t, re.I):
                    continue
                if not (DECL.match(t) and '::' in t):
                    break
                spec, ents = t.split('::', 1)
                for ent in split_top(ents):
                    e = re.match(r'\s*(\w+)\s*(\((?:[^()]|\([^()]*\))*\))?', ent)
                    if e:
                        decls[e.group(1).lower()] = (spec.strip() + ' :: ' + e.group(1) + (e.group(2) or '')).strip()
            missing = [d for d in dummies if d.lower() not in decls]
            if missing:
                if not decls:
                    continue
                raise Unresolved('%s: the dummies %s of %s have no declaration' % (rel, ', '.join(missing), name))
            res = None
            if kind == 'function':
                rname = (result or name).lower()
                res = decls.get(rname)
                if res is None:
                    head = re.match(r'^\s*' + PREFIX + r'(' + TYPESPEC.strip('?')[3:-1] + r')', s, re.I)
                    res = head.group(1).strip() if head else None
                if res is None:
                    raise Unresolved('%s: the result of %s has no declaration' % (rel, name))
            return (kind, [(d, decls[d.lower()]) for d in dummies], res, comment)
    raise Unresolved('no declaration of the procedure %s in module %s or its submodules' % (name, module))


def signature(name, proc):
    kind, dummies, res, _ = proc
    shown, optional = [], False
    for d, decl in dummies:
        if re.search(r'\boptional\b', decl, re.I):
            shown.append('[%s]' % d)
            optional = True
        else:
            shown.append(d)
    del optional
    head = '%s %s(%s)' % (kind, name, ', '.join(shown))
    lines = ['    ' + head]
    for d, decl in dummies:
        lines.append('        %-14s %s' % (d, decl))
    if res:
        lines.append('        %-14s %s' % ('result', res))
    return lines


def generic_specifics(src, module, name):
    """the specifics of the generic interface name in module, or None when module has no such interface"""
    for rel in src.module_files(module):
        inside, specs = False, []
        for _, s, comment in src.units[rel]:
            if re.match(r'^interface\s+%s\s*$' % re.escape(name), s, re.I):
                inside, specs, note = True, [], comment
                continue
            if inside and re.match(r'^end\s*interface\b', s, re.I):
                return specs, note
            if inside:
                m = re.match(r'^(?:module\s+)?procedure\s*(?:::)?\s*(.*)$', s, re.I)
                if m:
                    specs += [x.strip() for x in m.group(1).split(',') if x.strip()]
                m = HEAD.match(s)
                if m and not re.match(r'^\s*module\s+procedure\b', s, re.I):
                    specs.append(m.group(2))
    return None


def type_entry(src, module, name):
    """the lines of a derived type: its public bindings and operators (each operator's specifics with their
    signatures), or its components, or None when module defines no such type"""
    for rel in src.module_files(module):
        us = src.units[rel]
        for k, (_, s, comment) in enumerate(us):
            m = re.match(r'^type\s*(?:,[^:]*)?::\s*(\w+)\s*$|^type\s+(\w+)\s*$', s, re.I)
            if not m or (m.group(1) or m.group(2)).lower() != name.lower():
                continue
            lines, comps, bindings, ops = [], [], [], []
            hidden, bound = False, False
            for _, t, _ in us[k + 1:]:
                if re.match(r'^end\s*type\b', t, re.I):
                    break
                # a bare private before contains hides the components; after it, it is the bindings' default
                if re.match(r'^private\s*$', t, re.I):
                    hidden = hidden or not bound
                    continue
                if re.match(r'^contains\s*$', t, re.I):
                    bound = True
                    continue
                if re.match(r'^sequence\s*$', t, re.I):
                    continue
                g = re.match(r'^generic\s*(?:,\s*(\w+))?\s*::\s*(.*?)\s*=>\s*(.*)$', t, re.I)
                if g:
                    if (g.group(1) or '').lower() != 'private':
                        ops.append((g.group(2), [x.strip() for x in g.group(3).split(',')]))
                    continue
                p = re.match(r'^(procedure|final)\b([^:]*)::\s*(\w+)(?:\s*=>\s*(\w+))?', t, re.I)
                if p:
                    if p.group(1).lower() == 'procedure' and 'private' not in p.group(2).lower():
                        bindings.append((p.group(3), p.group(4) or p.group(3)))
                    continue
                if '::' in t and not hidden and 'private' not in t.split('::')[0].lower():
                    comps.append(t)
            lines.append('%s (a derived type)%s' % (name, ': ' + comment if comment else ''))
            for c in comps:
                lines.append('    component  ' + c)
            for b, impl in bindings:
                lines.append('    %%%s, bound to %s:' % (b, impl))
                lines += ['    ' + x for x in signature(b, procedure(src, module, impl))]
            for op, specs in ops:
                lines.append('    %s, for these operand pairs:' % op)
                for sp in specs:
                    kind, dummies, res, _ = procedure(src, module, sp)
                    lines.append('        %s' % ', '.join(decl.split('::')[0].strip().replace('intent(in)', '')
                                                         .strip(' ,') for _, decl in dummies))
            return lines
    return None


def constant_entry(src, module, name):
    for rel in src.module_files(module):
        for _, s, comment in src.units[rel]:
            m = re.match(r'^(.*?)\bparameter\b.*::\s*%s\s*=\s*(.*)$' % re.escape(name), s, re.I)
            if m:
                lines = ['%s (a named constant): %s' % (name, comment) if comment else '%s (a named constant)' % name,
                         '    ' + re.sub(r'\s+', ' ', s)]
                t = re.match(r'^\s*type\s*\(\s*(\w+)\s*\)', s, re.I)
                if t:
                    codes = type_entry(src, module, t.group(1))
                    if codes:
                        lines += ['    codes:'] + ['    ' + c for c in codes[1:]]
                return lines
    return None


def entry(src, name, modules):
    """the reference lines of one public name"""
    lines = []
    for module in modules:
        if module not in MODULE_SECTIONS:
            raise Unresolved('module %s (of %s) has no section of the binding policy in MODULE_SECTIONS' % (module, name))
        title, anchor = MODULE_SECTIONS[module]
        lines.append('*Module* `%s`; *contract:* [%s](%s#%s)' % (module, title, POLICY, anchor))
        lines.append('')
        body = []
        g = generic_specifics(src, module, name)
        if g is not None:
            specs, note = g
            body.append('generic %s%s' % (name, ': ' + note if note else ''))
            for sp in specs:
                proc = procedure(src, module, sp)
                body += signature(name, proc)
                if proc[3]:
                    body.append('        ! ' + proc[3])
        else:
            t = type_entry(src, module, name)
            if t is not None:
                body += t
            else:
                c = constant_entry(src, module, name)
                if c is not None:
                    body += c
                else:
                    proc = procedure(src, module, name)
                    body += signature(name, proc)
                    if proc[3]:
                        body.append('        ! ' + proc[3])
        lines += ['```text'] + body + ['```', '']
    return lines


def generate(root, override=None):
    names = list_public_api.public_names(root) if override is None or MODULE not in override else \
        names_of(override[MODULE])
    if not names:
        raise Unresolved('no public name in %s' % MODULE)
    src = Source(root, override)
    found = imports(root, override)
    out = ['# The mlxf API reference', '',
           'Generated from the source by `scripts/generate_api_reference.py`, never edited; `scripts/check_tree.sh` '
           'fails when it is not current. One entry per public name of `mlxf`, in the order of `src/core/mlxf.f90`: '
           'each specific with its dummies as the source declares them (`[x]` is optional, passed by keyword), the '
           'comment above it in the source, and the section of the binding policy that holds the contract (what '
           'stops, what returns a status, kinds and shapes). %d names.' % len(names), '']
    for name in names:
        modules = found.get(name.lower())
        if not modules:
            raise Unresolved('the public name %s is imported by no use line of %s' % (name, MODULE))
        out += ['## `%s`' % name, ''] + entry(src, name, modules)
    return '\n'.join(out).rstrip('\n') + '\n'


def names_of(text):
    names = []
    for s in list_public_api.statements(text):
        m = list_public_api.PUBLIC.match(s)
        if m:
            names += [n.strip() for n in m.group(1).split(',') if n.strip() and n.strip() not in names]
    return names


def self_test(root):
    base = generate(root)
    failures = []
    # a changed dummy name of a public procedure changes the reference
    rel = 'src/core/ops/mlxf_ops_index.f90'
    text = read(root, rel)
    planted = text.replace('subroutine check_indices_one( indices, extent, status )',
                           'subroutine check_indices_one( indices, length, status )', 1).replace(
        'integer,         intent(in)  :: extent\n', 'integer,         intent(in)  :: length\n', 1)
    if planted == text:
        failures.append('the planted signature change found no text to change')
    elif generate(root, {rel: planted}) == base:
        failures.append('a changed dummy did not change the reference')
    # a removed public name changes it; an unknown one fails it
    mod = read(root, MODULE)
    removed = mod.replace(', mlx_check_indices', '')
    if removed == mod or generate(root, {MODULE: removed}) == base:
        failures.append('a removed public name did not change the reference')
    unknown = mod.replace('public :: MLXF_HARD_ERROR_STATUS,', 'public :: mlx_no_such_name, MLXF_HARD_ERROR_STATUS,', 1)
    try:
        generate(root, {MODULE: unknown})
        failures.append('an unknown public name did not fail the generator')
    except Unresolved:
        pass
    for f in failures:
        print('generate_api_reference: self-test: ' + f, file=sys.stderr)
    if not failures:
        print('generate_api_reference: self-test passed (a changed dummy and a removed name change the reference, '
              'an unknown name fails it)')
    return 1 if failures else 0


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    flags = [a for a in argv[1:] if a.startswith('--')]
    root = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    try:
        if '--self-test' in flags:
            return self_test(root)
        text = generate(root)
    except Unresolved as e:
        print('generate_api_reference: %s' % e, file=sys.stderr)
        return 2
    target = os.path.join(root, OUT)
    if '--check' in flags:
        try:
            have = read(root, OUT)
        except OSError:
            have = ''
        if have != text:
            print('generate_api_reference: %s is not current; run scripts/generate_api_reference.py' % OUT,
                  file=sys.stderr)
            return 1
        print('generate_api_reference: %s is current' % OUT)
        return 0
    with open(target, 'w', encoding='utf-8') as h:
        h.write(text)
    print('generate_api_reference: wrote %s' % OUT)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
