#!/usr/bin/env python3
"""Bring named Fortran files into the house layout (skill mlxf-modern-fortran: aligned `::`
and intent columns, named procedure ends) without changing a token. Lifted from XEMA.

    scripts/restyle_fortran.py FILE ...           rewrite in place
    scripts/restyle_fortran.py --check FILE ...   change nothing; exit 1 if a file would change
    scripts/restyle_fortran.py --check --tree     the same over every .f90/.F90 under src/ and test/ (the static gate)
    scripts/restyle_fortran.py --ends-only FILE ... name the ends and touch nothing else
    scripts/restyle_fortran.py --case-indent FILE ... indent the arms of select blocks and touch nothing else

What it does, and nothing else:
  - `end subroutine` / `end function` / `end type` get their name;
  - a comma is followed by a space; `=` at statement level, `=>` and the
    relational operators get a space on each side where one is missing
    (existing wider spacing - a hand-aligned column - is kept; `=` inside
    parentheses, the keyword-argument form, is left as written);
  - `;` is followed by one space; `.not.` is followed by one space; a whitespace-only line is emptied;
  - a procedure statement's dummy list has a blank inside each parenthesis: `name( a, b )`;
  - procedures under `contains` (not interface bodies) are separated by one blank line, added where none is;
    a module-level `contains` has a blank line on each side, and a module-level `end type` or `end interface`
    one after it (except a type followed by a constant of that type);
  - a run of declarations at one indent has its attribute column and its `::`
    aligned; dummies and locals align apart; a line much wider than the rest
    stays out of the alignment so it cannot drag the column right. A run whose
    `::` already share a column is left as written, and a trailing comment
    keeps its column.
It never joins, splits or moves a line (the one addition is the blank line between procedures), and never
looks inside a string, a
comment, a `!$` line or a preprocessor line. The one re-indentation is
--case-indent: `case` / `type is` / `class is` arms sit four columns inside
their `select` (skill mlxf-modern-fortran), so a block whose arms are flush with it has its
whole interior moved right by four.

The proof, per file, before writing: line for line over the non-blank lines, the code with all
whitespace outside strings removed (and procedure-end names dropped) equals
the original, and every comment is unchanged. Files are named explicitly, or
--tree names every Fortran file under src/ and test/.
"""
import os
import re
import statistics
import sys

PROC = re.compile(
    r'^\s*(?!end\b)((pure|impure|elemental|recursive|module)\s+)*'
    r'((integer|real|logical|complex|character|type|class|double\s+precision)\s*(\([^()]*(\([^()]*\))?[^()]*\))?\s+)?'
    r'((pure|impure|elemental|recursive)\s+)*(subroutine|function)\s+(\w+)', re.I)
END_PROC = re.compile(r'^(\s*end\s*(subroutine|function))\b\s*(\w*)\s*$', re.I)
TYPE_DEF = re.compile(r'^\s*type\s*(,[^:]*)?::\s*(\w+)\s*$|^\s*type\s+(\w+)\s*$', re.I)
END_TYPE = re.compile(r'^(\s*end\s*type)\b\s*(\w*)\s*$', re.I)
IO_UNIT = re.compile(r'\b(write|read)\s*\([^,()]*,$', re.I)
RELATIONAL = ('==', '/=', '<=', '>=', '=>', '<', '>')


def split_code(line, in_string=None):
    """(segments, comment): segments alternate code and string text, [(is_string, text), ...]"""
    segs, cur, quote, i = [], '', in_string, 0
    while i < len(line):
        c = line[i]
        if quote:
            cur += c
            if c == quote:
                segs.append((True, cur))
                cur, quote = '', None
        elif c in '\'"':
            if cur:
                segs.append((False, cur))
            cur, quote = c, c
        elif c == '!':
            if cur:
                segs.append((False, cur))
            return segs, line[i:], None
        else:
            cur += c
        i += 1
    if cur:
        segs.append((bool(quote), cur))
    return segs, '', quote


def space_operators(code, depth, more=False):
    """one code segment with the missing operator spaces added; returns (text, depth). more: a string
    segment follows, so a comma or an operator ending this segment is still followed by text"""
    out, i, n = '', 0, len(code)

    def followed(k):
        return (k < n and code[k] not in ' \t') or (k == n and more)

    while i < n:
        c = code[i]
        if c in '([':
            depth += 1
        elif c in ')]':
            depth = max(0, depth - 1)
        if c == ',':
            out += ','
            # (:,:) stays tight, the house form of an assumed-shape rank
            tight = out.rstrip().endswith(':,') and code[i + 1:i + 2] == ':'
            # write(unit,'(A)'): an I/O control list keeps its unit tight with its format
            tight = tight or bool(IO_UNIT.search(out))
            if followed(i + 1) and not tight:
                out += ' '
            i += 1
            continue
        if c == ';':
            out += ';'
            if followed(i + 1):
                out += ' '
            i += 1
            continue
        if code[i:i + 5].lower() == '.not.':
            out += code[i:i + 5]
            i += 5
            if followed(i):
                out += ' '
            continue
        op = next((o for o in RELATIONAL if code.startswith(o, i)), None)
        if op is None and c == '=' and depth == 0:
            op = '='
        # operator(==) and assignment(=) name an operator; they are not one
        if op and out.rstrip().endswith('(') and code[i + len(op):].lstrip().startswith(')'):
            op = None
        if op is None:
            out += c
            i += 1
            continue
        if out and out[-1] not in ' \t':
            out += ' '
        out += op
        i += len(op)
        if followed(i):
            out += ' '
    return out, depth


def restyle_spacing(lines):
    out, depth, continued, quote = [], 0, False, None
    for line in lines:
        s = line.lstrip()
        if s.startswith(('#', '!')) or not s:
            out.append(line)
            continue
        if not continued:
            depth = 0
        segs, comment, quote = split_code(line, quote)
        if quote:
            raise SystemExit('a string continues across lines; not restyled')
        text = ''
        for k, (is_string, seg) in enumerate(segs):
            if is_string:
                text += seg
            else:
                more = k + 1 < len(segs) and segs[k + 1][0]
                seg, depth = space_operators(seg, depth, more)
                text += seg
        continued = text.rstrip().endswith('&')
        out.append((text + comment).rstrip())
    return out


def name_ends(lines):
    out, stack, types = [], [], []
    for line in lines:
        code = split_code(line)[0]
        flat = ''.join(t for is_s, t in code if not is_s)
        t = TYPE_DEF.match(flat.rstrip())
        if t:
            types.append(t.group(2) or t.group(3))
        et = END_TYPE.match(flat.rstrip()) if not any(is_s for is_s, _ in code) else None
        if et:
            if not types:
                raise SystemExit('an end type without its type: ' + line.strip())
            tname = types.pop()
            if et.group(2) and et.group(2).lower() != tname.lower():
                raise SystemExit('end type name does not match: ' + line.strip())
            if not et.group(2):
                comment = split_code(line)[1]
                line = et.group(1) + ' ' + tname + (('  ' + comment) if comment else '')
            out.append(line)
            continue
        m = PROC.match(flat)
        if m and not flat.lstrip().lower().startswith('end'):
            stack.append(m.group(m.lastindex))
        e = END_PROC.match(flat.rstrip()) if not any(is_s for is_s, _ in code) else None
        if e:
            if not stack:
                raise SystemExit('an end without its procedure: ' + line.strip())
            name = stack.pop()
            if e.group(3) and e.group(3).lower() != name.lower():
                raise SystemExit('end name does not match its procedure: ' + line.strip())
            if not e.group(3):
                comment = split_code(line)[1]
                line = e.group(1) + ' ' + name + (('  ' + comment) if comment else '')
        out.append(line)
    return out


SELECT = re.compile(r'^\s*(\w+\s*:\s*)?select\s+(case|type)\b', re.I)
END_SELECT = re.compile(r'^\s*end\s*select\b', re.I)
ARM = re.compile(r'^\s*(case\b|type\s+is\b|class\s+(is|default)\b)', re.I)


def indent_case_arms(lines):
    """select blocks whose arms are flush with the select get their interior moved right by four"""
    lines = list(lines)
    changed = True
    while changed:
        changed = False
        stack = []
        for k, line in enumerate(lines):
            flat = ''.join(t for is_s, t in split_code(line)[0] if not is_s)
            if SELECT.match(flat):
                stack.append([k, len(line) - len(line.lstrip()), False])
            elif END_SELECT.match(flat) and stack:
                start, col, flush = stack.pop()
                if flush:
                    for j in range(start + 1, k):
                        if lines[j].strip() and not lines[j].lstrip().startswith('#'):
                            lines[j] = '    ' + lines[j]
                    changed = True
                    break
            elif stack and ARM.match(flat) and len(line) - len(line.lstrip()) == stack[-1][1]:
                stack[-1][2] = True
    return lines


def top_level_split(text, sep):
    parts, cur, depth = [], '', 0
    for c in text:
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        if c == sep and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += c
    parts.append(cur)
    return parts


def declaration(line):
    """(indent, spec, attrs, rest) for a one-line declaration, else None"""
    s = line.lstrip()
    if not s or s.startswith(('!', '#')) or s.lower().startswith(('use ', 'use,')):
        return None
    segs, comment, quote = split_code(line)
    flat = ''.join(('\0' * len(t)) if is_s else t for is_s, t in segs)
    if flat.rstrip().endswith('&') or flat.lstrip().startswith('&'):
        return None
    depth, at = 0, -1
    for i, c in enumerate(flat):
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif c == ':' and depth == 0 and flat[i:i + 2] == '::':
            at = i
            break
    if at < 0:
        return None
    code = ''.join(t for _, t in segs)
    lhs, rest = code[:at], code[at + 2:]
    if '\0' in flat[:at] or '=' in lhs.replace('(', ' ').split(' ')[0]:
        return None
    parts = [p.strip() for p in top_level_split(lhs.strip(), ',')]
    if not re.match(r'^(integer|real|logical|complex|character|type|class|procedure|double\s+precision|generic|final)\b',
                    parts[0], re.I):
        return None
    indent = line[:len(line) - len(s)]
    # the comment keeps its column when the code still fits left of it
    return indent, parts[0], parts[1:], rest.strip(), comment, (len(line) - len(comment)) if comment else 0


def is_dummy(d):
    """a dummy argument's declaration: an intent or value attribute, or a dummy procedure (procedure(iface)
    without pointer); mlx-fortran's addition to XEMA's intent-only test, so that all dummies align together"""
    attrs = [a.lower() for a in d[2]]
    if any(a.startswith('intent') or a == 'value' for a in attrs):
        return True
    return d[1].lower().replace(' ', '').startswith('procedure(') and 'pointer' not in attrs


def align_declarations(lines):
    out, i = [], 0
    while i < len(lines):
        d = declaration(lines[i])
        if not d:
            out.append(lines[i])
            i += 1
            continue
        run, j = [], i
        dummy = is_dummy(d)
        while j < len(lines):
            e = declaration(lines[j])
            if not e or e[0] != d[0] or is_dummy(e) != dummy:
                break
            run.append(e)
            j += 1
        specw = max([len(e[1]) + 1 for e in run if e[2]] or [0])
        intents = [a for e in run for a in e[2][-1:] if a.lower().startswith('intent')]
        iw = max([len(a) for a in intents] or [0])
        lefts = []
        for e in run:
            if e[2]:
                attrs = list(e[2])
                if attrs[-1].lower().startswith('intent') and len(attrs) == 1:
                    attrs[-1] = attrs[-1].ljust(iw)
                lefts.append((e[1] + ',').ljust(specw) + ' ' + ', '.join(attrs))
            else:
                lefts.append(e[1])
        widths = [len(x.rstrip()) for x in lefts]
        limit = statistics.median(widths) + 16
        col = max([w for w in widths if w <= limit] or [0])
        # a run whose :: already share a column is somebody's alignment: keep it
        if len({lines[k].index('::') for k in range(i, j)}) == 1 and len(run) > 1:
            out.extend(lines[i:j])
            i = j
            continue
        for e, left in zip(run, lefts):
            left = left.rstrip()
            pad = left.ljust(col) if len(left) <= limit else left
            code = (e[0] + pad + ' :: ' + e[3]).rstrip()
            if e[4]:
                code = code.ljust(e[5]) if len(code) + 2 <= e[5] else code + '  '
                code += e[4]
            out.append(code)
        i = j
    return out


def space_dummy_lists(lines):
    """name( a, b ) on procedure statements whose dummy list opens and closes on the line"""
    out = []
    for line in lines:
        segs, comment = split_code(line)[:2]
        if any(is_s for is_s, _ in segs):
            out.append(line)
            continue
        code = ''.join(t for _, t in segs)
        m = PROC.match(code)
        if not m or code.lstrip().lower().startswith('end'):
            out.append(line)
            continue
        k = m.end()
        while k < len(code) and code[k] in ' \t':
            k += 1
        if k >= len(code) or code[k] != '(':
            out.append(line)
            continue
        depth, j = 0, k
        while j < len(code):
            depth += {'(': 1, ')': -1}.get(code[j], 0)
            if depth == 0:
                break
            j += 1
        inner = code[k + 1:j]
        if j >= len(code) or not inner.strip():
            out.append(line)
            continue
        code = code[:k + 1] + ' ' + inner.strip() + ' ' + code[j:]
        out.append(code + comment)
    return out


INTERFACE = re.compile(r'^\s*(abstract\s+)?interface\b', re.I)
END_INTERFACE = re.compile(r'^\s*end\s*interface\b', re.I)
AFTER_PROC = re.compile(r'^\s*(end\s*(module|submodule|program)\b|contains\b|#)', re.I)


def separate_procedures(lines):
    """one blank line after each procedure under contains that another statement or comment follows"""
    out, in_interface = [], False
    for k, line in enumerate(lines):
        out.append(line)
        flat = ''.join(t for is_s, t in split_code(line)[0] if not is_s)
        if INTERFACE.match(flat):
            in_interface = True
        elif END_INTERFACE.match(flat):
            in_interface = False
        if in_interface or not END_PROC.match(flat.rstrip()) or k + 1 >= len(lines):
            continue
        following = lines[k + 1]
        if following.strip() and not AFTER_PROC.match(following):
            out.append('')
    return out


MODULE_CONTAINS = re.compile(r'^contains\s*$', re.I)
MODULE_END_BLOCK = re.compile(r'^end\s*(interface\b|type\s+(\w+))', re.I)


def separate_module_blocks(lines):
    """the blank lines around a module-level contains and after a module-level type or interface block"""
    out = []
    for k, line in enumerate(lines):
        following = lines[k + 1] if k + 1 < len(lines) else ''
        if MODULE_CONTAINS.match(line):
            if out and out[-1].strip():
                out.append('')
            out.append(line)
            if following.strip():
                out.append('')
            continue
        out.append(line)
        m = MODULE_END_BLOCK.match(line)
        if not m or not following.strip() or MODULE_CONTAINS.match(following):
            continue
        if m.group(2) and re.match(r'^\s*type\s*\(\s*' + m.group(2) + r'\s*\)', following, re.I):
            continue
        out.append('')
    return out


def proof_form(lines):
    form, quote = [], None
    for line in lines:
        s = line.lstrip()
        if s.startswith(('#', '!')) or not s:
            form.append(line.strip())      # --case-indent moves whole-line comments with their block
            continue
        segs, comment, quote = split_code(line, quote)
        code = ''.join(t if is_s else re.sub(r'\s+', '', t) for is_s, t in segs)
        code = re.sub(r'^(end(subroutine|function|type))\w*$', r'\1', code, flags=re.I)
        form.append((code, comment.rstrip()))
    return form


def restyle(text, ends_only=False, case_indent=False):
    lines = text.split('\n')
    if case_indent:
        new = indent_case_arms(lines)
    elif ends_only:
        new = name_ends(lines)
    else:
        new = separate_module_blocks(separate_procedures(align_declarations(space_dummy_lists(
            name_ends(restyle_spacing(lines))))))
        new = [l if l.strip() else '' for l in new]
    old_form = [f for f, l in zip(proof_form(lines), lines) if l.strip()]
    new_form = [f for f, l in zip(proof_form(new), new) if l.strip()]
    if old_form != new_form:
        bad = [k + 1 for k, (a, b) in enumerate(zip(old_form, new_form)) if a != b][:5]
        raise SystemExit('internal error: tokens changed at non-blank lines ' + str(bad))
    return '\n'.join(new)


def main(argv):
    if '--help' in argv or '-h' in argv:
        print(__doc__)
        return 0
    unknown = [a for a in argv if a.startswith('-') and a not in ('--check', '--ends-only', '--case-indent', '--tree')]
    if unknown:
        sys.stderr.write('restyle_fortran.py: unknown option %s (see --help); nothing was changed\n'
                         % ', '.join(unknown))
        return 2
    check = '--check' in argv
    ends_only = '--ends-only' in argv
    case_indent = '--case-indent' in argv
    files = [a for a in argv if not a.startswith('--')]
    if '--tree' in argv:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        files += sorted(os.path.relpath(os.path.join(d, f), root) for top in ('src', 'test')
                        for d, _, names in os.walk(os.path.join(root, top))
                        for f in names if f.endswith(('.f90', '.F90')))
        os.chdir(root)
    if not files:
        raise SystemExit(__doc__)
    changed = 0
    for path in files:
        text = open(path).read()
        try:
            new = restyle(text, ends_only, case_indent)
        except SystemExit as err:
            raise SystemExit(f'{path}: {err}')
        if new != text:
            changed += 1
            print(('would restyle: ' if check else 'restyled: ') + path)
            if not check:
                open(path, 'w').write(new)
    return 1 if (check and changed) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
