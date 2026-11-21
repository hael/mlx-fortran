#!/usr/bin/env python3
"""gen_mlxc_bindings.py -- the private bind(c) layer of mlx-fortran, generated from the mlx-c headers linked.

usage: scripts/gen_mlxc_bindings.py <dir holding mlx/c/*.h> <output dir> [--expect LIST] [--list-outputs]

Writes into <output dir>:
  mlxf_c_types.f90       every handle type of mlx-c as `type, bind(c) :: mlxc_<x>` holding one
                         `type(c_ptr) :: ctx`; the other structs (the mlx_optional_* value pairs) as bind(c)
                         types; the enumerators as named integer(c_int) constants MLXC_<X>. One module, because
                         the headers' types refer to each other in a cycle (stream.h uses vector.h's
                         mlx_vector_stream, vector.h uses stream.h's mlx_stream).
  mlxf_c_<header>.f90    per header with prototypes, the bind(c) interfaces mlxc_<x> bound to mlx_<x>
                         (mlx-c's internal _mlx_<x> become mlxc_internal_<x>).
  mlxc_coverage.txt      the generated and the skipped names, sorted.
It skips static declarations, preprocessor-excluded blocks (float16 and bfloat16 entry points; MSVC and C++
branches), variadic functions and the functions taking mlx_io_vtable (a struct of function pointers passed by
value; IO is out of scope), and prints the skip list. It exits with 2 on a C type the mapping table does not
map or a struct it does not know. With --expect LIST (the names scripts/list_mlxc_prototypes.py writes) it exits
with 3 unless the generated and skipped names together equal LIST. --list-outputs prints the .f90 files it
would write, one per line, and writes nothing. Python 3.7 or newer, standard library only.
"""
import glob
import os
import re
import sys

# ---- the one mapping table: C type (const kept where it matters) -> (Fortran type, kind of dummy) --------
# kinds: 'value' (by value), 'ref' (a pointer to one object the callee may set: intent(inout)),
# 'array_in' (a pointer to an array the callee reads: intent(in), assumed size), 'ret' (a function result)
SCALARS = {
    'int':             ('integer(c_int)', 'value'),
    'int*':            ('integer(c_int)', 'ref'),
    'const int*':      ('integer(c_int)', 'array_in'),
    'size_t':          ('integer(c_size_t)', 'value'),
    'size_t*':         ('integer(c_size_t)', 'ref'),
    'bool':            ('logical(c_bool)', 'value'),
    'bool*':           ('logical(c_bool)', 'ref'),
    'float':           ('real(c_float)', 'value'),
    'double':          ('real(c_double)', 'value'),
    'double*':         ('real(c_double)', 'ref'),
    'float*':          ('real(c_float)', 'ref'),
    'int8_t*':         ('integer(c_int8_t)', 'ref'),
    'int16_t*':        ('integer(c_int16_t)', 'ref'),
    'int32_t*':        ('integer(c_int32_t)', 'ref'),
    'int64_t*':        ('integer(c_int64_t)', 'ref'),
    'const int64_t*':  ('integer(c_int64_t)', 'array_in'),
    'const uint64_t*': ('integer(c_int64_t)', 'array_in'),
    'uint8_t*':        ('integer(c_int8_t)', 'ref'),
    'uint16_t*':       ('integer(c_int16_t)', 'ref'),
    'uint32_t*':       ('integer(c_int32_t)', 'ref'),
    'uint64_t*':       ('integer(c_int64_t)', 'ref'),
    'uintptr_t':       ('integer(c_intptr_t)', 'value'),
    'uint64_t':        ('integer(c_int64_t)', 'value'),
    'mlx_complex64_t*': ('complex(c_float_complex)', 'ref'),
    'const char*':     ('character(kind=c_char)', 'array_in'),
    'char**':          ('type(c_ptr)', 'ref'),
    'const char**':    ('type(c_ptr)', 'ref'),
    'void*':           ('type(c_ptr)', 'value'),
    'void**':          ('type(c_ptr)', 'ref'),
    'const void*':     ('type(c_ptr)', 'value'),
    'FILE*':           ('type(c_ptr)', 'value'),
}
RETURNS = {
    'int':    'integer(c_int)',
    'size_t': 'integer(c_size_t)',
    'bool':   'logical(c_bool)',
}
# a pointer result (const T*) is a type(c_ptr); handles and value structs return their bind(c) type; enums int
POINTER_RESULT = 'type(c_ptr)'
SKIP_TYPES = {'float16_t': 'a float16 entry point', 'bfloat16_t': 'a bfloat16 entry point',
              'mlx_io_vtable': 'takes mlx_io_vtable, a struct of function pointers (IO is out of scope)'}
# structs that are not handles and not value structs of mappable fields: known, skipped by SKIP_TYPES
KNOWN_UNMAPPED_STRUCTS = {'mlx_io_vtable'}
ISO_NAMES = ('c_int', 'c_size_t', 'c_bool', 'c_float', 'c_double', 'c_int8_t', 'c_int16_t', 'c_int32_t',
             'c_int64_t', 'c_intptr_t', 'c_float_complex', 'c_char', 'c_ptr', 'c_funptr', 'c_null_ptr')


class GenError(Exception):
    pass


def header_dir(path):
    for cand in (os.path.join(path, 'mlx', 'c'), path):
        if glob.glob(os.path.join(cand, '*.h')):
            return cand
    return None


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def preprocess(text):
    """(active text, excluded text): #ifdef/#ifndef/#else/#endif evaluated against the #defines seen;
    any other #if is taken as false (the float16 and compiler-specific branches)"""
    defined, stack, active, excluded = set(), [], [], []
    for line in text.split('\n'):
        s = line.strip()
        on = all(stack)
        m = re.match(r'#\s*(ifdef|ifndef|if|else|elif|endif|define)\b\s*(\w*)', s)
        if m:
            d, name = m.group(1), m.group(2)
            if d == 'ifdef':
                stack.append(name in defined)
            elif d == 'ifndef':
                stack.append(name not in defined)
            elif d == 'if':
                stack.append(False)
            elif d in ('else', 'elif'):
                stack[-1] = not stack[-1] if d == 'else' else False
            elif d == 'endif':
                stack.pop()
            elif d == 'define' and on and name:
                defined.add(name)
            continue
        if s.startswith('#'):
            continue
        (active if on else excluded).append(line)
    return '\n'.join(active), '\n'.join(excluded)


def statements(text):
    """top-level statements ended by ';' (braces of struct and enum bodies kept inside)"""
    out, buf, depth = [], [], 0
    for c in text:
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        if c == ';' and depth == 0:
            out.append(' '.join(''.join(buf).split()))
            buf = []
        else:
            buf.append(c)
    return [s for s in out if s]


def split_params(text):
    parts, depth, cur = [], 0, ''
    for c in text:
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        if c == ',' and depth == 0:
            parts.append(cur.strip())
            cur = ''
        else:
            cur += c
    if cur.strip():
        parts.append(cur.strip())
    return parts


def norm_type(t):
    """'const  mlx_array *' -> 'const mlx_array*'; a const on a by-value type is dropped"""
    t = ' '.join(t.replace('*', ' * ').split()).replace(' *', '*')
    if '*' not in t and t.startswith('const '):
        t = t[6:]
    return t


class Model:
    def __init__(self):
        self.handles = {}     # C name -> header
        self.structs = {}     # C name -> (header, [(ctype, field)])
        self.enums = {}       # C name -> (header, [(enumerator, value)])
        self.funptrs = set()  # typedef'd function pointer types
        self.aliases = {}     # typedef T name (scalar aliases): name -> T
        self.protos = []      # (header, name, ret, [params]) of active declarations
        self.excluded = []    # (header, name) declared in excluded blocks

    def parse(self, header, text):
        active, excluded = preprocess(strip_comments(text))
        # the excluded text mixes branches (an unbalanced `extern "C" {` among them): cut at ';' only
        for st in excluded.split(';'):
            st = ' '.join(st.split()).rsplit('{', 1)[-1].rsplit('}', 1)[-1].strip()
            m = re.search(r'\b(_?mlx_\w+)\s*\(', st)
            if m and not st.startswith(('typedef', 'static')):
                self.excluded.append((header, m.group(1)))
        for st in statements(active):
            st = re.sub(r'^extern\s+"C"\s*\{?', '', st).strip().lstrip('}').strip()
            if not st or st.startswith('static'):
                continue
            if st.startswith('typedef'):
                self.parse_typedef(header, st)
                continue
            m = re.match(r'^(.*?)\b(_?mlx_\w+)\s*\((.*)\)$', st, re.S)
            if not m:
                continue
            ret, name, params = norm_type(m.group(1)), m.group(2), m.group(3).strip()
            self.protos.append((header, name, ret, [] if params in ('', 'void') else split_params(params)))

    def parse_typedef(self, header, st):
        m = re.match(r'^typedef\s+struct\s+\w+\s*\{(.*)\}\s*(\w+)$', st, re.S)
        if m:
            fields = [f.strip() for f in m.group(1).split(';') if f.strip()]
            name = m.group(2)
            if fields == ['void* ctx'] or fields == ['void *ctx']:
                self.handles[name] = header
            else:
                parsed = []
                for f in fields:
                    fm = re.match(r'^(.*?)(\w+)$', f)
                    parsed.append((norm_type(fm.group(1)), fm.group(2)) if fm else (f, ''))
                self.structs[name] = (header, parsed)
            return
        if re.match(r'^typedef\s+struct\s+\w+\s+\w+$', st):
            return  # a forward declaration; the body is in another header
        m = re.match(r'^typedef\s+enum\s+\w+\s*\{(.*)\}\s*(\w+)$', st, re.S)
        if m:
            vals, nxt = [], 0
            for e in [x.strip() for x in m.group(1).split(',') if x.strip()]:
                em = re.match(r'^(\w+)\s*(?:=\s*(.+))?$', e)
                if em.group(2) is not None:
                    nxt = int(em.group(2), 0)
                vals.append((em.group(1), nxt))
                nxt += 1
            self.enums[m.group(2)] = (header, vals)
            return
        m = re.match(r'^typedef\s+.*\(\s*\*\s*(\w+)\s*\)\s*\(.*\)$', st, re.S)
        if m:
            self.funptrs.add(m.group(1))
            return
        m = re.match(r'^typedef\s+(.+?)\s+(\w+)$', st)
        if m:
            self.aliases[m.group(2)] = m.group(1)


def f_name(cname):
    if cname.startswith('_mlx_'):
        return 'mlxc_internal_' + cname[5:]
    return 'mlxc_' + cname[4:]


def enum_name(cname):
    return 'MLXC_' + cname[4:] if cname.startswith('MLX_') else 'MLXC_' + cname


def map_param(model, p, idx):
    """(Fortran declaration, dummy name, types used) of one C parameter; raises GenError if unmapped"""
    fm = re.match(r'^.*\(\s*\*\s*(\w+)\s*\)\s*\(.*\)$', p, re.S)
    if fm:
        return 'type(c_funptr), value', set(), fm.group(1)
    m = re.match(r'^(.*?)(\w+)$', p)
    if m and m.group(1).strip() and not m.group(1).strip().endswith(('struct', 'const')):
        ctype, name = norm_type(m.group(1)), m.group(2)
    else:
        ctype, name = norm_type(p), 'arg%d' % idx
    return map_ctype(model, ctype) + (name,)


def map_ctype(model, ctype):
    base = ctype.replace('const ', '').rstrip('*')
    nptr = ctype.count('*')
    const = ctype.startswith('const ')
    if ctype in SCALARS:
        ftype, kind = SCALARS[ctype]
        return declare(ftype, kind), set()
    if base in model.handles or base in model.structs:
        used = {f_name(base)}
        if nptr == 0:
            return declare('type(%s)' % f_name(base), 'value'), used
        if nptr == 1 and const:
            return declare('type(%s)' % f_name(base), 'array_in'), used
        if nptr == 1:
            return declare('type(%s)' % f_name(base), 'ref'), used
    if base in model.enums:
        if nptr == 0:
            return declare('integer(c_int)', 'value'), set()
        if nptr == 1 and not const:
            return declare('integer(c_int)', 'ref'), set()
    if base in model.funptrs and nptr == 0:
        return declare('type(c_funptr)', 'value'), set()
    raise GenError('unmapped C type "%s"' % ctype)


def declare(ftype, kind):
    if kind == 'value':
        return ftype + ', value'
    if kind == 'ref':
        return ftype + ', intent(inout)'
    if kind == 'array_in':
        return ftype + ', intent(in)'
    raise GenError('unknown kind ' + kind)


def map_return(model, ret):
    if ret == 'void':
        return None, set()
    if ret in RETURNS:
        return RETURNS[ret], set()
    if ret.endswith('*'):
        return POINTER_RESULT, set()
    if ret in model.handles or ret in model.structs:
        return 'type(%s)' % f_name(ret), {f_name(ret)}
    if ret in model.enums:
        return 'integer(c_int)', set()
    raise GenError('unmapped C result type "%s"' % ret)


def skip_reason(model, ret, params):
    text = ' '.join([ret] + params)
    if '...' in params:
        return 'variadic'
    for t, why in SKIP_TYPES.items():
        if re.search(r'\b%s\b' % t, text):
            return why
    return None


def iso_import(text):
    used = [n for n in ISO_NAMES if re.search(r'\b%s\b' % n, text)]
    return 'use, intrinsic :: iso_c_binding, only: ' + ', '.join(used) if used else ''


def types_module(model):
    lines = ['!@descr: generated from the mlx-c headers: the handle types, value structs and enumerators of mlx-c',
             '! Do not edit: scripts/gen_mlxc_bindings.py writes this file at build time.',
             'module mlxf_c_types', '@ISO@', 'implicit none', '']
    body = []
    for name in sorted(model.handles):
        body += ['! %s (%s)' % (name, model.handles[name]), 'type, bind(c) :: %s' % f_name(name),
                 '    type(c_ptr) :: ctx = c_null_ptr', 'end type %s' % f_name(name), '']
    for name in sorted(model.structs):
        header, fields = model.structs[name]
        if name in KNOWN_UNMAPPED_STRUCTS:
            continue
        body += ['! %s (%s)' % (name, header), 'type, bind(c) :: %s' % f_name(name)]
        for ctype, field in fields:
            try:
                decl, _ = map_ctype(model, ctype)
            except GenError:
                raise GenError('unknown struct %s: field "%s %s"' % (name, ctype, field))
            ftype = decl.split(',')[0]
            body.append('    %s :: %s' % (ftype, field))
        body += ['end type %s' % f_name(name), '']
    for name in sorted(model.enums):
        header, vals = model.enums[name]
        body.append('! %s (%s)' % (name, header))
        for e, v in vals:
            body.append('integer(c_int), parameter :: %s = %d_c_int' % (enum_name(e), v))
        body.append('')
    text = '\n'.join(lines + body).rstrip() + '\n\nend module mlxf_c_types\n'
    return text.replace('@ISO@', iso_import('\n'.join(body)))


def header_module(model, header, protos):
    mod = 'mlxf_c_' + header[:-2]
    used_types, ifaces = set(), []
    for name, ret, params in protos:
        fret, used = map_return(model, ret)
        used_types |= used
        decls = []
        for i, p in enumerate(params, 1):
            decl, u, dname = map_param(model, p, i)
            used_types |= u
            if decl.endswith('intent(in)'):
                dname_decl = dname + '(*)'
            else:
                dname_decl = dname
            decls.append((decl, dname_decl, dname))
        fn = f_name(name)
        args = ', '.join(d[2] for d in decls)
        kind = 'function' if fret else 'subroutine'
        head = '    %s %s(%s) bind(c, name=\'%s\')' % (kind, fn, ' ' + args + ' ' if args else '', name)
        body = [head, '        import']
        width = max([len(d[0]) for d in decls] + [len(fret or '')])
        for decl, dd, _ in decls:
            body.append('        %s :: %s' % (decl.ljust(width), dd))
        if fret:
            body.append('        %s :: %s' % (fret.ljust(width), fn))
        body.append('    end %s %s' % (kind, fn))
        ifaces.append('\n'.join(body))
    text_ifaces = '\n\n'.join(ifaces)
    lines = ['!@descr: generated from mlx-c\'s %s: bind(c) interfaces mlxc_<x> bound to mlx_<x>' % header,
             '! Do not edit: scripts/gen_mlxc_bindings.py writes this file at build time.',
             'module ' + mod]
    iso = iso_import(text_ifaces)
    if iso:
        lines.append(iso)
    if used_types:
        lines.append('use mlxf_c_types, only: ' + ', '.join(sorted(used_types)))
    lines += ['implicit none', '', 'interface', '', text_ifaces, '', 'end interface', '', 'end module ' + mod, '']
    return mod, '\n'.join(lines)


def check_names(model):
    """Fortran names are case-insensitive: no two generated entities may collide"""
    seen = {}
    names = [f_name(n) for n in model.handles] + [f_name(n) for n in model.structs]
    names += [enum_name(e) for _, vals in model.enums.values() for e, _ in vals]
    names += [f_name(p[1]) for p in model.protos]
    for n in names:
        k = n.lower()
        if k in seen and seen[k] != n:
            raise GenError('generated names collide: %s and %s' % (seen[k], n))
        if len(n) > 63:
            raise GenError('generated name longer than 63 characters: %s' % n)
        seen[k] = n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    expect = None
    if '--expect' in sys.argv:
        expect = sys.argv[sys.argv.index('--expect') + 1]
        args = [a for a in args if a != expect]
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    hdir, outdir = header_dir(args[0]), args[1]
    if hdir is None:
        print('gen_mlxc_bindings: no headers under %s' % args[0], file=sys.stderr)
        return 2
    model = Model()
    headers = sorted(os.path.basename(h) for h in glob.glob(os.path.join(hdir, '*.h')))
    for h in headers:
        with open(os.path.join(hdir, h), encoding='utf-8', errors='replace') as f:
            model.parse(h, f.read())
    by_header, skipped = {}, []
    for h, name, ret, params in model.protos:
        why = skip_reason(model, ret, params)
        if why:
            skipped.append((name, why))
        else:
            by_header.setdefault(h, []).append((name, ret, params))
    for h, name in model.excluded:
        why = 'preprocessor-excluded'
        for t, w in SKIP_TYPES.items():
            if t.replace('_t', '') in name:
                why = 'preprocessor-excluded (%s)' % w
        skipped.append((name, why))
    outputs = ['mlxf_c_types.f90'] + ['mlxf_c_%s.f90' % h[:-2] for h in sorted(by_header)]
    if '--list-outputs' in sys.argv:
        for o in outputs:
            print(os.path.join(outdir, o))
        return 0
    try:
        check_names(model)
        files = {'mlxf_c_types.f90': types_module(model)}
        for h in sorted(by_header):
            mod, text = header_module(model, h, by_header[h])
            files[mod + '.f90'] = text
    except GenError as e:
        print('gen_mlxc_bindings: error: %s' % e, file=sys.stderr)
        return 2
    os.makedirs(outdir, exist_ok=True)
    for name, text in files.items():
        with open(os.path.join(outdir, name), 'w') as f:
            f.write(text)
    generated = sorted(p[0] for ps in by_header.values() for p in ps)
    covered = sorted(set(generated) | set(n for n, _ in skipped))
    with open(os.path.join(outdir, 'mlxc_coverage.txt'), 'w') as f:
        f.write(''.join(n + '\n' for n in covered))
    print('gen_mlxc_bindings: %d interfaces in %d modules, %d handle types, %d value structs, %d enumerations; '
          'skipped %d:' % (len(generated), len(files) - 1, len(model.handles),
                           len(model.structs) - len(KNOWN_UNMAPPED_STRUCTS), len(model.enums), len(skipped)))
    for n, why in sorted(skipped):
        print('    skipped %-40s %s' % (n, why))
    if expect:
        with open(expect) as f:
            want = sorted(set(l.strip() for l in f if l.strip()))
        missing = sorted(set(want) - set(covered))
        extra = sorted(set(covered) - set(want))
        if missing or extra:
            for n in missing:
                print('gen_mlxc_bindings: coverage: %s is in the prototype list, neither generated nor skipped' % n,
                      file=sys.stderr)
            for n in extra:
                print('gen_mlxc_bindings: coverage: %s is generated or skipped but not in the prototype list' % n,
                      file=sys.stderr)
            return 3
        print('gen_mlxc_bindings: coverage: %d generated + %d skipped = %d names, the prototype list'
              % (len(generated), len(skipped), len(want)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
