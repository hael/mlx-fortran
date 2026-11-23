#!/usr/bin/env python3
"""Put every `use` block of the Fortran sources into one form.

    scripts/format_use_blocks.py            rewrite src/ and test/ in place
    scripts/format_use_blocks.py --check    change nothing; exit 1 if a file is not in form
    scripts/format_use_blocks.py FILE ...   only these files

The form (skill mlxf-modern-fortran; lifted from XEMA):
  - within a run of consecutive use statements, `only:` sits in one column;
    intrinsic statements whose heads reach past it share a column of their own;
  - a statement wider than WIDTH continues with its names aligned under the
    first imported name;
  - a module used twice in one run is one statement;
  - a module-scope run is ordered by layer - intrinsic, the generated C layer
    (mlxf_c_*, written into the build tree), src/defs, src/core, src/test -
    and is otherwise stable, so the layering reads top to bottom. Runs inside procedures and
    runs that follow a comment keep their order.

Layout only. The tool proves it per file before writing: every non-use line
is unchanged and in place, and each run imports exactly the names it did
before. `--drop=file.f90:module:name` (repeatable) removes a dead import in
the same pass; that is the one edit that is not layout.
"""
import glob
import os
import re
import sys

WIDTH = 120
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYERS = ['defs', 'core', 'test']
GENERATED = re.compile(r'^mlxf_c_\w+$')   # the generated bind(c) layer, below every source module

USE_START = re.compile(r'^(\s*)(!\$\s+)?use(\s*,\s*intrinsic\s*::\s*|\s+)(\w+)\s*(.*)$', re.I)


def sources():
    return sorted(glob.glob(os.path.join(ROOT, 'src', '**', '*.f90'), recursive=True) +
                  glob.glob(os.path.join(ROOT, 'test', '*.f90')))


def layer_ranks():
    """module name -> rank, from the directory its file sits in"""
    ranks = {}
    for path in sources():
        rel = os.path.relpath(path, os.path.join(ROOT, 'src'))
        rank = len(LAYERS) + 1
        for i, layer in enumerate(LAYERS):
            if rel.startswith(layer + os.sep):
                rank = i + 1
                break
        ranks[os.path.splitext(os.path.basename(path))[0].lower()] = rank
    return ranks


def rank_of(module, ranks):
    """the layer rank of a module named in a use statement: generated modules sort first"""
    name = module.lower()
    if GENERATED.match(name):
        return 0.5
    return ranks.get(name)


class Use:
    def __init__(self, indent, omp, intrinsic, module, names):
        self.indent, self.omp, self.intrinsic, self.module, self.names = indent, omp, intrinsic, module, names

    def head(self):
        h = 'use, intrinsic :: ' if self.intrinsic else 'use '
        return ('!$ ' if self.omp else '') + h + self.module


def parse_statement(lines, i):
    """a use statement starting at lines[i]; returns (Use, next index) or None"""
    m = USE_START.match(lines[i])
    if not m:
        return None
    indent, omp, sep, module, rest = m.groups()
    text = rest
    j = i
    while text.rstrip().endswith('&'):
        j += 1
        if j >= len(lines) or '!' in lines[j].replace('!$', '', 1):
            return None                  # a comment inside a continuation: leave the statement alone
        nxt = lines[j].strip()
        if omp and nxt.startswith('!$'):
            nxt = nxt[2:].strip()
        text = text.rstrip()[:-1] + ' ' + nxt.lstrip('&')
    if '!' in text or ';' in text:
        return None
    text = text.strip()
    names = None
    if text:
        mo = re.match(r'^,\s*only\s*:\s*(.*)$', text, re.I)
        if not mo:
            return None                  # a rename list without only: is not ours to touch
        names = [re.sub(r'\s*=>\s*', ' => ', n.strip()) for n in mo.group(1).split(',') if n.strip()]
    return Use(indent, bool(omp), 'intrinsic' in sep.lower(), module, names), j + 1


def imports_of(run):
    """what a run imports, independent of layout: (omp, intrinsic, module) -> the names, or None for a bare use"""
    got = {}
    for u in run:
        k = (u.omp, u.intrinsic, u.module.lower())
        if u.names is None:
            got[k] = None
        elif got.get(k, ()) is not None:
            got[k] = tuple(sorted(set(got.get(k, ())) | {n.replace(' ', '').lower() for n in u.names}))
    return got


def merged(run):
    """two only-lists of one module in a run become one, names in first-seen order"""
    out, seen = [], {}
    for u in run:
        k = (u.omp, u.intrinsic, u.module.lower())
        if u.names is not None and k in seen and seen[k].names is not None:
            have = {n.replace(' ', '').lower() for n in seen[k].names}
            seen[k].names += [n for n in u.names if n.replace(' ', '').lower() not in have]
            continue
        if k not in seen:
            seen[k] = u
        out.append(u)
    return out


def emit(run, drop):
    """the formatted lines of one run"""
    indent = run[0].indent
    kept = []
    for u in run:
        if u.names is not None:
            u.names = [n for n in u.names if (u.module.lower(), n.split('=>')[0].strip().lower()) not in drop]
            if not u.names:
                continue
        kept.append(u)
    # head, comma, one space; intrinsic statements whose heads reach past that column share one of their own
    plain = [len(u.head()) for u in kept if u.names is not None and not u.intrinsic and not u.omp]
    intrinsic = [len(u.head()) for u in kept if u.names is not None and u.intrinsic and not u.omp]
    col_plain = (max(plain) if plain else 0) + 2
    col_intrinsic = max([col_plain] + [n + 2 for n in intrinsic])
    out = []
    for u in kept:
        if u.names is None:
            out.append(indent + u.head())
            continue
        col = col_intrinsic if (u.intrinsic and not u.omp) else col_plain
        lead = indent + (u.head() + ', ').ljust(col) + 'only: '
        cont = ' ' * len(lead)
        if u.omp:
            cont = indent + '!$ ' + ' ' * (len(lead) - len(indent) - 3)
        line = lead
        first = True
        for k, name in enumerate(u.names):
            piece = name + (', ' if k < len(u.names) - 1 else '')
            if not first and len(line.rstrip()) + len(piece.rstrip()) + 2 > WIDTH:
                out.append(line.rstrip() + ' &')
                line = cont
            line += piece
            first = False
        out.append(line.rstrip())
    return out


def format_text(text, ranks, drop):
    lines = text.split('\n')
    out, i = [], 0
    while i < len(lines):
        parsed = parse_statement(lines, i)
        if not parsed:
            out.append(lines[i])
            i += 1
            continue
        start, run = i, []
        while parsed and parsed[0].indent == (run[0].indent if run else parsed[0].indent):
            run.append(parsed[0])
            i = parsed[1]
            parsed = parse_statement(lines, i) if i < len(lines) else None
        before = imports_of(run)
        run = merged(run)
        follows_comment = start > 0 and lines[start - 1].lstrip().startswith('!') and \
            not lines[start - 1].lstrip().startswith('!$')
        if run[0].indent == '' and not follows_comment:
            run.sort(key=lambda u: (0 if (u.intrinsic or u.omp or rank_of(u.module, ranks) is None)
                                    else rank_of(u.module, ranks)))
        if imports_of(run) != before:
            raise SystemExit('internal error: a run lost or gained an import')
        out.extend(emit(run, drop))
    return '\n'.join(out)


def strip_uses(text):
    """the file without its use statements, for the unchanged-remainder proof"""
    lines, keep, i = text.split('\n'), [], 0
    while i < len(lines):
        parsed = parse_statement(lines, i)
        if parsed:
            i = parsed[1]
        else:
            keep.append(lines[i])
            i += 1
    return keep


def main(argv):
    check = '--check' in argv
    drop = set()
    files = []
    for a in argv:
        if a.startswith('--drop='):
            # --drop=file.f90:module:name, the dead-import removal; repeatable
            f, mod, name = a[len('--drop='):].split(':')
            drop.add((os.path.basename(f), mod.lower(), name.lower()))
        elif not a.startswith('--'):
            files.append(os.path.abspath(a))
    files = files or sources()
    ranks = layer_ranks()
    off = []
    for path in files:
        text = open(path).read()
        mine = {(m, n) for (f, m, n) in drop if f == os.path.basename(path)}
        new = format_text(text, ranks, mine)
        if strip_uses(new) != strip_uses(text):
            raise SystemExit('internal error: a non-use line moved in ' + path)
        if new != text:
            off.append(os.path.relpath(path, ROOT))
            if not check:
                open(path, 'w').write(new)
    for f in off:
        print(('not in form: ' if check else 'formatted: ') + f)
    print(f'{len(off)} of {len(files)} files ' + ('need formatting' if check else 'rewritten'))
    return 1 if (check and off) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
