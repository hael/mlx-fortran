#!/usr/bin/env python3
"""list_mlxc_prototypes.py -- the names of every function prototype in the mlx-c headers.

The coverage reference of the generated bind(c) layer (scripts/gen_mlxc_bindings.py): the build fails unless
the generator's generated and skipped names together equal this list. It is deliberately simple and shares no
code with the generator: comments are stripped, the text is cut into statements at ';', and a statement that
is not a typedef or a static declaration and has the form `<return type> <name>(<anything>)` declares <name>.
Preprocessor-excluded blocks are not evaluated: every declared name is listed.

usage: scripts/list_mlxc_prototypes.py <dir holding mlx/c/*.h, or mlx/c itself> [-o FILE] [--counts]
  prints (or writes to FILE) one name per line, sorted; --counts prints the count per header and the total
exit status: 0, or 2 when no header is found. Python 3.7 or newer, standard library only.
"""
import glob
import os
import re
import sys

PROTO = re.compile(r'^[A-Za-z_][\w\s\*]*?[\s\*](_?mlx_\w+)\s*\(.*\)$', re.S)


def header_dir(path):
    for cand in (os.path.join(path, 'mlx', 'c'), path):
        if glob.glob(os.path.join(cand, '*.h')):
            return cand
    return None


def names_of(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    text = re.sub(r'//[^\n]*', ' ', text)
    text = '\n'.join(l for l in text.split('\n') if not l.lstrip().startswith('#'))
    out = []
    for stmt in text.split(';'):
        stmt = ' '.join(stmt.split())
        # drop what precedes the statement in the same chunk: braces of extern "C" and of struct bodies
        stmt = stmt.rsplit('}', 1)[-1].rsplit('{', 1)[-1].strip()
        if not stmt or stmt.startswith(('typedef', 'static', 'extern')):
            continue
        m = PROTO.match(stmt)
        if m:
            out.append(m.group(1))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    out_file = None
    if '-o' in sys.argv:
        out_file = sys.argv[sys.argv.index('-o') + 1]
        args = [a for a in args if a != out_file]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    d = header_dir(args[0])
    if d is None:
        print('list_mlxc_prototypes: no headers under %s' % args[0], file=sys.stderr)
        return 2
    per_header, names = {}, []
    for h in sorted(glob.glob(os.path.join(d, '*.h'))):
        with open(h, encoding='utf-8', errors='replace') as f:
            found = names_of(f.read())
        per_header[os.path.basename(h)] = len(found)
        names.extend(found)
    names = sorted(set(names))
    if '--counts' in sys.argv:
        for h, n in sorted(per_header.items()):
            print('%-24s %4d' % (h, n))
        print('%-24s %4d' % ('total (unique)', len(names)))
        return 0
    text = ''.join(n + '\n' for n in names)
    if out_file:
        with open(out_file, 'w') as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
