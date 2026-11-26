#!/usr/bin/env python3
"""The rules of CLAUDE.md, the skills and doc/architecture_principles.md that a compiler does not check,
over src/, test/ and the CMake files. Adapted from XEMA's scripts/check_rules.py.

    scripts/check_rules.py            report every finding, exit 1 if any
    scripts/check_rules.py --list     also print each rule with the ledger it allows

A LEDGER names the files that do not follow a rule yet, with their count and the reason; a ledger may only
shrink: a file not in it, or a count above its entry, fails, and so does a count BELOW its entry (lower the
entry in the same change, so the ratchet holds what was gained).

Rules:
  layout     no `block` construct; no `goto`; no `!>` comment; no `interface operator`/`interface
             assignment` block (operators are type-bound generics); `if( cond )then`, a blank inside each
             parenthesis of an `if`'s condition (the skill's layout); a THROW_HARD/THROW_WARN call on one
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
             signature C fixes; a bind(c) procedure written for any other reason is a review finding), and a
             procedure of a toy module (mlxf_toy_*) that the mirror ledger lists as mirrored (a binding's
             implementation or a public module procedure): it keeps
             SIMPLE's dummy list, as a bind(c) procedure keeps C's. An addition obeys the rule
  ctorcall   no array constructor holds a reference to a library function by name: the mlx_* and mlxf_*
             names of src/core/mlxf.f90's public statements (the generics that keep an intrinsic's name,
             real, max, sum, ..., are left to ctorexpr, as plain Fortran uses them in constructors too):
             gfortran never finalizes such a result, so a handle in it leaks
             (doc/compiler_issues/gfortran_finalize_ctor_function_results.f90)
  ctorexpr   an element of an array constructor that refers to a handle is a bare designator (a, v(i),
             w%r, w%r(i)): an operator result or a generic's result there ([a*2.0, b], [-a, b], [(a), b],
             [exp(a), b]) is never finalized either. The handles of a file are the names and components it
             declares type(mlx_array) or class(mlx_array), anywhere in it; the getters a%shape(), %ndim(),
             %size(), %kind(), a keyword name and the argument of an inquiry intrinsic (size, lbound, ubound,
             shape, rank, allocated, present, storage_size, ...) are not references; an implied-do is checked
             through its items; a call of a function the file defines or declares with a handle result, or
             imports by name from a file of the tree that defines it (a generic that holds one included; the
             user API's names are ctorcall's), counts as a reference (it is never bare)
  entry      every procedure that implements a name of the user API (the public block of src/core/mlxf.f90:
             its procedures, the specifics of its generics, the bindings of its types except final) opens with
             an entry call (mlxf_enter, mlxf_guard_thread, mlxf_require_device) or a call to a guarded helper
             (ENTRY_HELPERS), whose own first statement is checked the same way: the one-thread guard and the
             initialisation run on every path, empty inputs included. The lifetime bindings (ENTRY_IF_LIVE) may
             open with the guard conditional on a live handle instead. ENTRY_EXEMPT names the exceptions
  defs       exported = defs, local = stay (SIMPLE's and XEMA's rule): a named constant (a parameter, a
             vocabulary constant included) or a behaviourless derived type (no type-bound procedure, no
             private component) that another module imports is declared in src/defs, unless DEFS_EXCEPTIONS
             claims it with a reason; one used only inside its module stays there; a class (type-bound
             procedures or private components) stays with its module. Test code shares its constants and
             records through src/test/mlxf_test_defs.f90, a defs module of the same form. A defs
             module holds constants and behaviourless types only (no contains), imports only the generated
             layer and the intrinsic modules, writes no public statement or
             attribute and no bare private (public by default, as XEMA's defs modules), and lists every name
             it imports in a `private ::` statement, so that an installed .mod re-exports nothing it imports
  findpkg    no `find_package(... REQUIRED ...)` in the CMake files (CMakeLists.txt, cmake/*.cmake): a missing
             dependency is tested by its _FOUND variable and fails with a FATAL_ERROR that says what was
             searched and how to install it (SIMPLE's and XEMA's policy), never with CMake's own message
  parity     scripts/mlxc_parity.txt, the parity ledger, names every mlx-c function once: the same names as the
             headers (MLXC_ROOT, .deps/install, Homebrew, or the build's prototype list when no header is
             found), each with a known class (mlx-c PARITY_MLXC_VERSION is the minimum: headers of an older
             release fail, a newer release's added or removed names are printed as warnings); a public line's Fortran name is in the public block of mlxf.f90
             (for T%b, the type T is); a line is public or plumbing exactly when the library (src/core,
             src/defs, testers aside) calls the function; a pending line names a phase of the parity plan
             that its Progress has not closed; and the count of pending lines equals PARITY_PENDING (a ratchet:
             lower it in the same change)
  mirror     scripts/toy_mirror.txt, the mirror ledger (doc/policies/toy_example_policy.md), has one line per
             public type, per public type-bound procedure and per public module procedure of every toy module (a
             module mlxf_toy_<stem> under src/test): the toy's module and name (T, T%binding or the procedure),
             then SIMPLE's module and name, or `addition` and a reason (a tester's entries, *_tester, are the
             registry's, not the toy's, and need no line). A type, binding or procedure without a line fails; so
             does a line that names
             nothing the code has, a name listed twice, a mirrored line whose toy name differs from SIMPLE's or
             whose module is not mlxf_toy_<stem> beside simple_<stem>, an addition without a reason, and a
             ledger whose header does not record the SIMPLE commit that was read
  nanmax     test code (src/test, test/, *_tester.f90) reduces with nan_maxval (src/test/mlxf_test_reduce.f90),
             never maxval(abs(...)): maxval may skip a NaN among finite values, so an error reduced with it
             passes a corrupt element. A reduction along a dimension (dim=) builds a reference array and is
             left alone
  cmakeroot  the CMake files name the library's own directories (PROJECT_SOURCE_DIR, PROJECT_BINARY_DIR,
             CMAKE_CURRENT_*), never CMAKE_SOURCE_DIR or CMAKE_BINARY_DIR, which name a parent project's when
             mlx-fortran is added with add_subdirectory()
  fortlsoff  no editor side effects downstream: every configure line (cmake -S, cmake -B, cmake ..; a line
             continued with a backslash read whole) of scripts/release_gate.sh, scripts/check_install.sh,
             scripts/ci_*.sh, .github/workflows/ci.yml, README.md, doc/quickstart.md and
             doc/how2s/how2use_from_simple.md names -DFORTLS=OFF or configures no producer (a consumer of the
             installed package, -Dmlxf_DIR= or a consumer/ source, or the release gate's mlx-c probe), and every
             MLXF_CMAKE_ARGS they set names -DFORTLS=OFF. The developer's compile scripts are outside the rule
  devquery   test code (src/test/, *_tester.f90, test/*.f90) asks whether a GPU is present only through
             mlxf_test_utils (test_devices, gpu_present, gpu_check_runs), which tells the three situations apart
             (Metal with a GPU, Metal without one, a CPU-only MLX): a call of mlx_device_count(MLX_DEVICES%gpu)
             elsewhere is in DEVQUERY_LEDGER or fails. The outside programs of test/consumer/, which cannot use the
             test library, classify for themselves: a file that asks for the GPU count also calls
             mlx_metal_is_available
  docex      the documents' Fortran is run: every fenced fortran block of README.md, doc/quickstart.md and
             CONTRIBUTING.md is preceded by <!-- example: test/consumer/<file> --> and is a verbatim run of that
             file's lines (scripts/check_install.sh compiles and runs those programs against the installed
             package); every row | D<n> | of the quickstart's table has exactly one block ! D<n> in
             test/consumer/mlxf_example_differences.f90 or names a member of the registry's GUARDS, and every
             block ! D<n> has its row
  cbsig      the procedures C++ calls keep C's passing modes: each dummy of the four callbacks of CALLBACKS is
             declared with or without value as C passes it (a dummy the procedure ignores, which no test can
             observe, included)

Python 3.7 or newer, standard library only; it runs before the compile.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOPS = ('src', 'test')
CORE = 'src/core/'
DEFS = 'src/defs/'
# the defs module of test code: the constants several test modules share, under the same form
TEST_DEFS = 'src/test/mlxf_test_defs.f90'

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
# test code that asks MLX for the GPU count itself (rule devquery); may only shrink
DEVQUERY_LEDGER = {
    'src/core/runtime/mlxf_device_tester.f90': (2, 'tests mlx_device_count itself: a stable, non-negative count'),
}
# (module, constant) -> reason: a constant another module imports from outside src/defs, argued here
DEFS_EXCEPTIONS = {}
ENTRY_CALLS = ('mlxf_enter', 'mlxf_guard_thread', 'mlxf_require_device')
# helpers an entry may call first instead: each must itself open with an entry call
ENTRY_HELPERS = ('mlxf_unary', 'mlxf_binary', 'mlxf_weak_scalar', 'mlxf_int_op', 'mlxf_dtype_op', 'mlxf_vector_op', 'mlxf_reduce_op', 'mlxf_ternary_op', 'mlxf_take_op', 'mlxf_scan_op', 'mlxf_slice_op', 'mlxf_concat_op', 'mlxf_zeros_op', 'mlxf_range_op', 'mlxf_fft_op', 'mlxf_fftn_op', 'mlxf_freq_op', 'mlxf_close_op', 'mlxf_compare_op', 'mlxf_nan_op', 'mlxf_binary_vector_op', 'mlxf_full_op', 'mlxf_binary_int_op', 'mlxf_reduce_all_op', 'mlxf_reduce_dims_op', 'mlxf_var_all_op', 'mlxf_var_op', 'mlxf_var_dims_op', 'mlxf_int2_op', 'mlxf_int3_op', 'mlxf_trace_op', 'mlxf_scan_all_op', 'mlxf_scan_plain_op', 'mlxf_scan_plain_all_op', 'mlxf_roll_op', 'mlxf_unflatten_op', 'mlxf_vector2_op', 'mlxf_strided_op', 'mlxf_count_op', 'mlxf_window_op', 'mlxf_identity_op', 'mlxf_eye_op', 'mlxf_linspace_op', 'mlxf_linspace_endpoint_op', 'mlxf_list_op', 'mlxf_vector_list_op', 'mlxf_meshgrid_op', 'mlxf_split_op', 'mlxf_split_sections_op', 'mlxf_unstack_op', 'mlxf_unstack_dim_op', 'mlxf_pad_op', 'mlxf_pad_width_op', 'mlxf_gather_op', 'mlxf_gather_single_op', 'mlxf_slice_dynamic_op', 'mlxf_scatter_op', 'mlxf_put_op', 'mlxf_ternary_vector_op', 'mlxf_text_op', 'mlxf_slice_update_op', 'mlxf_unique_op', 'mlxf_gather_mm_op', 'mlxf_masked_mm_op', 'mlxf_cpu_unary', 'mlxf_cpu_binary', 'mlxf_cpu_flag_op', 'mlxf_cpu_compare_op', 'mlxf_cpu_pair_op', 'mlxf_cpu_pair_text_op', 'mlxf_cpu_text_op', 'mlxf_cpu_unstack_op', 'mlxf_cpu_svd_op', 'mlxf_norm_op', 'mlxf_norm_text_op', 'mlxf_binary_axis_op', 'mlxf_optional_float_op', 'mlxf_addmm_op', 'mlxf_einsum_op', 'mlxf_tensordot_op', 'mlxf_conv1d_op', 'mlxf_conv2d_op', 'mlxf_conv3d_op', 'mlxf_conv_general_op', 'mlxf_conv_transpose1d_op', 'mlxf_conv_transpose2d_op', 'mlxf_conv_transpose3d_op')
# the lifetime bindings touch shared state only through a live handle: they may open with the one-thread guard
# conditional on one (between empty handles they run anywhere; nothing they do needs initialisation)
ENTRY_IF_LIVE = ('assign_array', 'kill_array', 'function_assign', 'function_kill', 'metal_kernel_assign',
                 'metal_kernel_kill')
ENTRY_EXEMPT = {
    'mlxf_version_string': 'pure: returns a build constant, touches no state and calls no MLX function',
    'mlxf_build_description': 'pure: returns build constants, touches no state and calls no MLX function',
}
USER_MODULE = CORE + 'mlxf.f90'
HANDLE_TYPES = ('mlx_array', 'mlx_function', 'mlx_metal_kernel')
HANDLE_DECL = re.compile(r'^(type|class)\s*\(\s*(' + '|'.join(HANDLE_TYPES) + r')\s*\)(.*)$', re.I)
HANDLE_PREFIX = re.compile(r'\b(type|class)\s*\(\s*(' + '|'.join(HANDLE_TYPES) + r')\s*\)', re.I)
HANDLE_GETTERS = ('shape', 'ndim', 'size', 'kind')
INQUIRY = re.compile(r'(?<![%\w])(size|lbound|ubound|shape|rank|allocated|present|storage_size|is_contiguous|'
                     r'same_type_as|extends_type_of)\s*\(', re.I)
FIND_PACKAGE = re.compile(r'\bfind_package\s*\(([^)]*)\)', re.I)
PARITY_LEDGER = 'scripts/mlxc_parity.txt'
PARITY_PLAN = 'doc/implementation_notes/planned/mlxf_mlxc_parity.md'
PARITY_CLASSES = ('public', 'plumbing', 'internal', 'excluded', 'pending')
PARITY_PHASES = range(1, 9)
# the mlx-c release the ledger lists: the minimum; a newer one's differences are warnings, an older one fails
PARITY_MLXC_VERSION = '0.8.0'
# the pending lines of the ledger; may only shrink
PARITY_PENDING = 76
MIRROR_LEDGER = 'scripts/toy_mirror.txt'
TOY_DIR = 'src/test/'
TOY_PREFIX = 'mlxf_toy_'
SIMPLE_PREFIX = 'simple_'
MIRROR_COMMIT = re.compile(r'^#.*\bSIMPLE\b.*\bcommit\s+[0-9a-f]{7,40}\b', re.I)


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
IF_OPEN = re.compile(r'^\s*(else\s*)?if\((?!\s)', re.I)
IF_THEN = re.compile(r'[^\s(]\)\s*then\b', re.I)
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


def check_layout(rel, lines, out):
    for n, raw in enumerate(lines, 1):
        code = code_of(raw)
        if BLOCK.match(code):
            out.append('%s:%d: layout: a block construct (declarations at the top; a passage that needs a scope is a procedure)' % (rel, n))
        if GOTO.search(code):
            out.append('%s:%d: layout: goto' % (rel, n))
        if raw.lstrip().startswith('!>') or re.search(r'\s!>', raw):
            out.append('%s:%d: layout: a !> comment' % (rel, n))
        if IF_OPEN.match(code) or IF_THEN.search(code):
            out.append('%s:%d: layout: write if( cond )then, a blank inside the condition\'s parentheses' % (rel, n))
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


def check_arity(rel, lines, out, mirrored=()):
    """mirrored: the procedures of this file's toy module that keep SIMPLE's dummy list"""
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        m = PROC_HEAD.match(stmt)
        if not m or re.search(r'\bbind\s*\(\s*c\b', stmt, re.I):
            continue
        if m.group(2).lower() in mirrored:
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


def library_functions(api):
    """the public names ctorcall matches: the library's own, not the generics named after intrinsics"""
    return set(n for n in api if n.startswith(('mlx_', 'mlxf_')))


def check_ctorcall(rel, lines, api, out):
    names = library_functions(api)
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        for body in constructors(stmt):
            for m in re.finditer(r'(?<![%\w])([a-z_]\w*)\s*\(', body, re.I):
                if m.group(1).lower() in names:
                    out.append('%s:%d: ctorcall: %s(...) inside an array constructor (a function result there is '
                               'never finalized: assign it to a variable first)' % (rel, start, m.group(1)))


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


def exported_handle_functions(lines):
    """the functions with a handle result that a file defines, and the generics that hold one of them"""
    names = handle_functions(lines, handle_names(lines))
    generic = None
    for s in statements(lines):
        m = re.match(r'^interface\s+([a-z_]\w*)\s*$', s, re.I)
        if m:
            generic = m.group(1).lower()
        elif re.match(r'^end\s*interface\b', s, re.I):
            generic = None
        elif generic:
            m = re.match(r'^(?:module\s+)?procedure\b\s*(?:::)?(.*)$', s, re.I)
            if m and any(n.strip().lower() in names for n in m.group(1).split(',')):
                names.add(generic)
    return names


def imported_names(lines):
    """the lower-case names a file imports through `use ..., only:` lists (a renamed one under its local name)"""
    names = set()
    for s in statements(lines):
        m = re.match(r'^use\b.*\bonly\s*:(.*)$', s, re.I)
        if m:
            names |= set(n.split('=>')[0].strip().lower() for n in m.group(1).split(',') if n.strip())
    return names


def check_ctorexpr(rel, lines, out, tree_functions=()):
    handles = handle_names(lines)
    if not handles:
        return
    functions = handle_functions(lines, handles) | (set(tree_functions) & imported_names(lines))
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        for body in constructors(stmt):
            for e in ctor_violations(body, handles, functions):
                out.append('%s:%d: ctorexpr: %s inside an array constructor refers to a handle and is not a bare '
                           'designator (its result is never finalized: assign it to a variable first)' % (rel, start, e))


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


def module_records(lines):
    """the behaviourless derived types of a module's specification part, lower case: no type-bound procedure
    and no private component. A type with either is a class and stays with its behaviour"""
    found, name, body, depth = set(), None, [], 0
    for s in statements(lines):
        low = s.lower()
        if re.match(r'^contains\b', low) and name is None and depth == 0:
            break
        if re.match(r'^(abstract\s+)?interface\b', low):
            depth += 1
            continue
        if re.match(r'^end\s*interface\b', low):
            depth -= 1
            continue
        if depth:
            continue
        m = re.match(r'^type\s*(?:,\s*([^:]*))?::\s*(\w+)\s*$|^type\s+(\w+)\s*$', low)
        if name is None and m and not re.match(r'^type\s*\(', low):
            attrs = m.group(1) or ''
            name, body = (m.group(2) or m.group(3)), []
            if 'abstract' in attrs or re.search(r'\bbind\s*\(\s*c\b', attrs):
                name = '-'           # an abstract or interoperable type is no record of this rule
            continue
        if name is not None and re.match(r'^end\s*type\b', low):
            if name != '-' and not any(re.match(r'^contains\b', b) or re.match(r'^private\b', b) or
                                       ('::' in b and re.search(r'\bprivate\b', b.split('::', 1)[0]))
                                       for b in body):
                found.add(name)
            name = None
            continue
        if name is not None:
            body.append(low)
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


def is_defs(rel):
    """a defs module: src/defs, or the one defs module of test code"""
    return rel.startswith(DEFS) or rel == TEST_DEFS


def check_defs(root, files, out):
    """exported = defs, local = stay; and the form of a defs module"""
    owners, records = {}, {}
    for rel in files:
        if is_defs(rel):
            continue
        lines = read(root, rel).split('\n')
        mod = module_of(lines)
        if mod:
            owners[mod] = module_constants(lines)
            records[mod] = module_records(lines)
    for rel in files:
        lines = read(root, rel).split('\n')
        me = module_of(lines)
        for start, mod, names in use_imports(lines):
            if mod == me or mod not in owners:
                continue
            for n in names:
                if n in owners[mod] and (mod, n) not in DEFS_EXCEPTIONS:
                    out.append('%s:%d: defs: %s is a constant of %s that another module imports; declare it in '
                               'src/defs, or for test code in %s (exported = defs, local = stay)' % (rel, start, n.upper(), mod, TEST_DEFS))
                if n in records[mod] and (mod, n) not in DEFS_EXCEPTIONS:
                    out.append('%s:%d: defs: %s is a behaviourless type of %s that another module imports; declare it '
                               'in src/defs, or for test code in %s (a class, with type-bound procedures or private '
                               'components, stays with its module)' % (rel, start, n, mod, TEST_DEFS))
        if not is_defs(rel):
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


def cmake_files(root):
    out = []
    for d, dirs, files in os.walk(root):
        rel_d = os.path.relpath(d, root).replace(os.sep, '/')
        dirs[:] = sorted(x for x in dirs if not x.startswith('.') and not (rel_d == '.' and x.startswith('build')))
        for f in sorted(files):
            if f == 'CMakeLists.txt' or (rel_d == 'cmake' and f.endswith('.cmake')):
                out.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, '/'))
    return out


NANMAX = re.compile(r'(?<![\w%])maxval\s*\(\s*abs\s*\(', re.I)
NANMAX_HOME = 'src/test/mlxf_test_reduce.f90'
TOP_DIRS = re.compile(r'\$\{CMAKE_(SOURCE|BINARY)_DIR\}')


def check_nanmax(rel, lines, out):
    if rel == NANMAX_HOME:
        return
    if not (rel.startswith('src/test/') or rel.startswith('test/') or rel.endswith('_tester.f90')):
        return
    for start, stmt in logical_lines([code_of(l) for l in lines]):
        if NANMAX.search(stmt) and not re.search(r'\bdim\s*=', stmt, re.I):
            out.append('%s:%d: nanmax: maxval(abs(...)) may skip a NaN; reduce with nan_maxval '
                       '(mlxf_test_reduce)' % (rel, start))


def check_cmakeroot(root, out):
    for rel in cmake_files(root):
        for n, line in enumerate(read(root, rel).split('\n'), 1):
            if TOP_DIRS.search(re.sub(r'#.*', '', line)):
                out.append('%s:%d: cmakeroot: CMAKE_SOURCE_DIR or CMAKE_BINARY_DIR names a parent project when '
                           'mlx-fortran is embedded; use PROJECT_SOURCE_DIR, PROJECT_BINARY_DIR or '
                           'CMAKE_CURRENT_*' % (rel, n))
    return out


FORTLSOFF_FILES = ('scripts/release_gate.sh', 'scripts/check_install.sh', '.github/workflows/ci.yml', 'README.md',
                   'doc/quickstart.md', 'doc/how2s/how2use_from_simple.md')
CONFIGURE = re.compile(r'(^|[\s;&|(`"\'])cmake\s+(-S|-B|\.\.)(\s|$|["\'`])')
# a configure of no producer: one that finds the installed package, or whose source is a consumer or the probe
SOURCE_ARG = re.compile(r'-S\s*("[^"]*"|\'[^\']*\'|\S+)')
NO_PRODUCER_SOURCE = re.compile(r'consumer|mlxc_probe')
CMAKE_ARGS = re.compile(r'\bMLXF_CMAKE_ARGS\s*[:=]')


def fortlsoff_files(root):
    rels = [r for r in FORTLSOFF_FILES if os.path.isfile(os.path.join(root, r))]
    scripts = os.path.join(root, 'scripts')
    rels += sorted('scripts/' + f for f in os.listdir(scripts) if f.startswith('ci_') and f.endswith('.sh'))
    return rels


def check_fortlsoff(root, out):
    for rel in fortlsoff_files(root):
        lines = read(root, rel).split('\n')
        k = 0
        while k < len(lines):
            first, text = k, lines[k]
            while text.rstrip().endswith('\\') and k + 1 < len(lines):
                k += 1
                text = text.rstrip()[:-1] + ' ' + lines[k]
            k += 1
            src = SOURCE_ARG.search(text)
            producer = '-Dmlxf_DIR=' not in text and not (src and NO_PRODUCER_SOURCE.search(src.group(1)))
            if CONFIGURE.search(text) and '-DFORTLS=OFF' not in text and producer:
                out.append('%s:%d: fortlsoff: a configure of the library without -DFORTLS=OFF (the fortls target '
                           'writes into the source tree and the editor settings)' % (rel, first + 1))
            if CMAKE_ARGS.search(text) and '-DFORTLS=OFF' not in text:
                out.append('%s:%d: fortlsoff: MLXF_CMAKE_ARGS without -DFORTLS=OFF' % (rel, first + 1))
    return out


GPU_COUNT = re.compile(r'\bmlx_device_count\s*\(\s*MLX_DEVICES\s*%\s*gpu\s*\)', re.I)
METAL_QUERY = re.compile(r'\bmlx_metal_is_available\s*\(', re.I)
TEST_UTILS = 'src/test/mlxf_test_utils.f90'
CONSUMER_DIR = 'test/consumer/'


def is_test_code(rel):
    return (rel.startswith('src/test/') or rel.endswith('_tester.f90') or
            (rel.startswith('test/') and '/' not in rel[len('test/'):]))


def check_devquery(root, files, out):
    counts = {}
    for rel in files:
        codes = [code_of(l) for l in read(root, rel).split('\n')]
        n = sum(len(GPU_COUNT.findall(c)) for c in codes)
        if not n:
            continue
        if rel.startswith(CONSUMER_DIR):
            if not any(METAL_QUERY.search(c) for c in codes):
                out.append('%s: devquery: an outside program asks for the GPU count without mlx_metal_is_available: '
                           'a CPU-only MLX and a session without a GPU look alike' % rel)
        elif is_test_code(rel) and rel != TEST_UTILS:
            counts[rel] = n
    ledger_check('devquery', counts, DEVQUERY_LEDGER, out)
    return out


DOCEX_FILES = ('README.md', 'doc/quickstart.md', 'CONTRIBUTING.md')
DOCEX_MARK = re.compile(r'^<!--\s*example:\s*(test/consumer/[\w.]+\.f90)\s*-->\s*$')
DOCEX_TABLE = 'doc/quickstart.md'
DOCEX_EXAMPLE = 'test/consumer/mlxf_example_differences.f90'
DOCEX_ROW = re.compile(r'^\|\s*D(\d+)\s*\|(.*)$')
DOCEX_BLOCK = re.compile(r'^\s*!\s*D(\d+)\b')
DOCEX_GUARD = re.compile(r"guard_member\(\s*'(\w+)'", re.I)


def check_docex(root, out):
    for rel in DOCEX_FILES:
        if not os.path.isfile(os.path.join(root, rel)):
            continue
        lines = read(root, rel).split('\n')
        k = 0
        while k < len(lines):
            if not re.match(r'^```\s*fortran\s*$', lines[k].strip(), re.I):
                k += 1
                continue
            first, k = k, k + 1
            block = []
            while k < len(lines) and lines[k].strip() != '```':
                block.append(lines[k])
                k += 1
            prev = first - 1
            while prev >= 0 and not lines[prev].strip():
                prev -= 1
            m = DOCEX_MARK.match(lines[prev].strip()) if prev >= 0 else None
            if not m:
                out.append('%s:%d: docex: a fortran block without <!-- example: test/consumer/<file> --> before it'
                           % (rel, first + 1))
                continue
            src = m.group(1)
            if not os.path.isfile(os.path.join(root, src)):
                out.append('%s:%d: docex: the example %s does not exist' % (rel, first + 1, src))
                continue
            text = read(root, src).split('\n')
            n = len(block)
            if not n or not any(text[i:i + n] == block for i in range(len(text) - n + 1)):
                out.append('%s:%d: docex: the block is not a verbatim run of the lines of %s' % (rel, first + 1, src))
    if not os.path.isfile(os.path.join(root, DOCEX_TABLE)):
        return out
    guards = set(DOCEX_GUARD.findall(read(root, 'src/test/mlxf_test_registry.f90')))
    blocks = {}
    if os.path.isfile(os.path.join(root, DOCEX_EXAMPLE)):
        for line in read(root, DOCEX_EXAMPLE).split('\n'):
            m = DOCEX_BLOCK.match(line)
            if m:
                blocks[m.group(1)] = blocks.get(m.group(1), 0) + 1
    rows = set()
    for n, line in enumerate(read(root, DOCEX_TABLE).split('\n'), 1):
        m = DOCEX_ROW.match(line)
        if not m:
            continue
        row, rest = m.group(1), m.group(2)
        if row in rows:
            out.append('%s:%d: docex: row D%s twice' % (DOCEX_TABLE, n, row))
        rows.add(row)
        named = set(re.findall(r'\bguard_\w+', rest))
        unknown = named - guards
        if unknown:
            out.append('%s:%d: docex: row D%s names %s, not a member of GUARDS' % (DOCEX_TABLE, n, row,
                                                                                 ', '.join(sorted(unknown))))
        elif not named and blocks.get(row, 0) != 1:
            out.append('%s:%d: docex: row D%s has %d blocks ! D%s in %s and names no guard (one is its evidence)'
                       % (DOCEX_TABLE, n, row, blocks.get(row, 0), row, DOCEX_EXAMPLE))
    for row in sorted(set(blocks) - rows, key=int):
        out.append('%s: docex: the block ! D%s has no row in %s' % (DOCEX_EXAMPLE, row, DOCEX_TABLE))
    return out


# the procedures C++ calls and their C signatures: each dummy, passed by value (True) or by reference (False)
CALLBACKS = {
    'src/core/runtime/mlxf_error.f90': {'record_mlx_error': (('msg', True), ('data', True))},
    'src/core/compile/mlxf_compile.f90': {'invoke_callback': (('res', False), ('input', True), ('payload', True)),
                                          'delete_payload': (('payload', True),)},
    'src/core/array/mlxf_array_borrow.f90': {'release_buffer': (('rec', True),)},
}


def check_cbsig(root, out):
    for rel, procs in sorted(CALLBACKS.items()):
        lines = read(root, rel).split('\n')
        for proc, dummies in sorted(procs.items()):
            head = [k for k, l in enumerate(lines)
                    if re.search(r'\b(subroutine|function)\s+%s\s*\(' % proc, code_of(l), re.I)]
            if not head:
                out.append('%s: cbsig: %s not found' % (rel, proc))
                continue
            modes = {}
            for l in lines[head[0] + 1:]:
                c = code_of(l)
                if '::' not in c:
                    break
                attrs, names = c.split('::', 1)
                for n in re.findall(r'\b(\w+)', re.sub(r'\([^)]*\)', '', names)):
                    modes[n.lower()] = bool(re.search(r'\bvalue\b', attrs, re.I))
            for dummy, by_value in dummies:
                if modes.get(dummy) != by_value:
                    out.append('%s: cbsig: %s: dummy %s must be passed %s, as C passes it' % (
                        rel, proc, dummy, 'by value (value)' if by_value else 'by reference (no value)'))
    return out


def check_findpkg(root, out):
    for rel in cmake_files(root):
        text = '\n'.join(re.sub(r'#.*', '', l) for l in read(root, rel).split('\n'))
        for m in FIND_PACKAGE.finditer(text):
            if re.search(r'\bREQUIRED\b', m.group(1)):
                n = text.count('\n', 0, m.start()) + 1
                out.append('%s:%d: findpkg: find_package(... REQUIRED) (test its _FOUND variable and fail with '
                           'a FATAL_ERROR that says how to install it)' % (rel, n))
    return out


def version_tuple(text):
    return tuple(int(x) for x in re.findall(r'\d+', text)[:3])


def mlxc_version(root, header_dir):
    """the mlx-c release of a header directory: Homebrew's Cellar path, the package config beside the headers, or
    the build's record (build/gen/mlxf_build_info.inc); None if none says"""
    real = os.path.realpath(header_dir) if header_dir else ''
    m = re.search(r'/mlx-c/(\d+\.\d+\.\d+)/', real + '/')
    if m:
        return m.group(1)
    if header_dir:
        prefix = os.path.dirname(os.path.dirname(os.path.dirname(real)))
        for sub in ('share', 'lib'):
            cdir = os.path.join(prefix, sub, 'cmake')
            for d in (sorted(os.listdir(cdir)) if os.path.isdir(cdir) else []):
                for f in (sorted(os.listdir(os.path.join(cdir, d))) if d.upper().startswith('MLXC') else []):
                    if f.endswith('ConfigVersion.cmake'):
                        m = re.search(r'PACKAGE_VERSION\s+"([\d.]+)"', read(os.path.join(cdir, d), f))
                        if m:
                            return m.group(1)
    info = os.path.join(root, 'build', 'gen', 'mlxf_build_info.inc')
    if os.path.isfile(info):
        m = re.search(r'BUILD_INFO_MLXC\s*=\s*"([\d.]+)"', read(root, 'build/gen/mlxf_build_info.inc'))
        if m:
            return m.group(1)
    return None


def mlxc_prototypes(root):
    """the mlx-c function names of the linked headers, and where they came from; (None, None) if none found"""
    path = os.path.join(root, 'scripts', 'list_mlxc_prototypes.py')
    namespace = {'__name__': 'list_mlxc_prototypes'}
    with open(path, encoding='utf-8') as h:
        exec(compile(h.read(), path, 'exec'), namespace)
    cands = []
    if os.environ.get('MLXC_ROOT'):
        cands += [os.path.join(os.environ['MLXC_ROOT'], 'include'), os.environ['MLXC_ROOT']]
    cands += [os.path.join(root, '.deps', 'install', 'include'), '/opt/homebrew/include', '/usr/local/include']
    for cand in cands:
        d = namespace['header_dir'](cand) if os.path.isdir(cand) else None
        if d:
            names = set()
            for h in sorted(os.listdir(d)):
                if h.endswith('.h'):
                    names |= set(namespace['names_of'](read(d, h)))
            return names, d
    listed = os.path.join(root, 'build', 'gen', 'mlxc_prototypes.txt')
    if os.path.isfile(listed):
        return set(read(root, 'build/gen/mlxc_prototypes.txt').split()), 'build/gen/mlxc_prototypes.txt'
    return None, None


def mlxc_calls(root, files):
    """the mlx-c functions the library calls through the generated layer (mlxc_<x>, mlxc_internal_<x>)"""
    called = set()
    for rel in files:
        if not (rel.startswith(CORE) or rel.startswith(DEFS)) or rel.endswith('_tester.f90'):
            continue
        for n in re.findall(r'\bmlxc_(\w+)', '\n'.join(code_of(l) for l in read(root, rel).split('\n')), re.I):
            n = n.lower()
            called.add('_mlx_' + n[len('internal_'):] if n.startswith('internal_') else 'mlx_' + n)
    return called


def closed_parity_phases(root):
    """the phases whose Progress entry in the parity plan says complete"""
    if not os.path.isfile(os.path.join(root, PARITY_PLAN)):
        return set()
    text = read(root, PARITY_PLAN)
    progress = text.split('\n## Progress', 1)[1] if '\n## Progress' in text else ''
    return {int(m.group(1)) for m in re.finditer(r'^### Phase (\d+)\b[^\n]*\bcomplete\b', progress, re.M | re.I)}


def check_parity(root, files, api, out):
    rel = PARITY_LEDGER
    if not os.path.isfile(os.path.join(root, rel)):
        out.append('%s: parity: the ledger is missing' % rel)
        return
    entries, pending = {}, 0
    closed = closed_parity_phases(root)
    for k, line in enumerate(read(root, rel).split('\n'), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        f = line.split(None, 2)
        name, cls, rest = f[0], (f[1] if len(f) > 1 else ''), (f[2].strip() if len(f) > 2 else '')
        if name in entries:
            out.append('%s:%d: parity: %s listed twice' % (rel, k, name))
        if cls not in PARITY_CLASSES:
            out.append('%s:%d: parity: %s: unknown class %r' % (rel, k, name, cls))
            continue
        if cls == 'pending':
            pending += 1
            ph = rest.split(None, 1)
            if not ph or not ph[0].isdigit() or int(ph[0]) not in PARITY_PHASES or len(ph) < 2:
                out.append('%s:%d: parity: %s: a pending line names a phase (1 to 8) and the planned Fortran name'
                           % (rel, k, name))
            elif int(ph[0]) in closed:
                out.append('%s:%d: parity: %s is pending in Phase %s, which the plan\'s Progress has closed'
                           % (rel, k, name, ph[0]))
        elif cls in ('public', 'excluded') and not rest:
            out.append('%s:%d: parity: %s: a %s line names %s' % (rel, k, name, cls,
                       'its Fortran name' if cls == 'public' else 'the reason'))
        elif cls == 'public':
            fname = rest.split()[0].lower()
            owner = fname.split('%', 1)[0]
            if owner not in api:
                out.append('%s:%d: parity: %s: %s is not a public name of %s' % (rel, k, name, owner, USER_MODULE))
        entries[name] = (k, cls)
    protos, source = mlxc_prototypes(root)
    if protos is None:
        print('check_rules: parity: no mlx-c headers or prototype list found; the ledger\'s names were not compared')
    else:
        found = mlxc_version(root, None if source.endswith('.txt') else source)
        newer = found is not None and version_tuple(found) > version_tuple(PARITY_MLXC_VERSION)
        if found is not None and version_tuple(found) < version_tuple(PARITY_MLXC_VERSION):
            out.append('%s: parity: mlx-c %s at %s is older than %s, the minimum the ledger lists'
                       % (rel, found, source, PARITY_MLXC_VERSION))
        else:
            diffs = ['%s: parity: %s (in %s) has no ledger line' % (rel, n, source)
                     for n in sorted(protos - set(entries))]
            diffs += ['%s:%d: parity: %s is not an mlx-c function of %s' % (rel, entries[n][0], n, source)
                      for n in sorted(set(entries) - protos)]
            if newer:
                for d in diffs:
                    print('check_rules: warning (mlx-c %s, newer than the ledger\'s %s): %s'
                          % (found, PARITY_MLXC_VERSION, d))
            else:
                out.extend(diffs)
    called = mlxc_calls(root, files)
    for n, (k, cls) in sorted(entries.items()):
        if n in called and cls not in ('public', 'plumbing'):
            out.append('%s:%d: parity: %s is called by the library but classed %s (public or plumbing)'
                       % (rel, k, n, cls))
        elif n not in called and cls in ('public', 'plumbing'):
            out.append('%s:%d: parity: %s is classed %s but the library does not call it' % (rel, k, n, cls))
    if pending > PARITY_PENDING:
        out.append('%s: parity: %d pending lines, PARITY_PENDING allows %d (the count may only shrink)'
                   % (rel, pending, PARITY_PENDING))
    elif pending < PARITY_PENDING:
        out.append('%s: parity: %d pending lines, below PARITY_PENDING %d - lower it in scripts/check_rules.py'
                   % (rel, pending, PARITY_PENDING))


def toy_module(lines):
    """(name, is_submodule) of the toy module a file belongs to: its module, or the ancestor of its submodule;
    ('', False) when it is not one"""
    for s in statements(lines):
        m = re.match(r'^submodule\s*\(\s*(\w+)', s, re.I)
        if m:
            name = m.group(1).lower()
            return (name, True) if name.startswith(TOY_PREFIX) else ('', False)
        m = re.match(r'^module\s+(\w+)$', s, re.I)
        if m:
            name = m.group(1).lower()
            return (name, False) if name.startswith(TOY_PREFIX) else ('', False)
    return ('', False)


def split_names(text):
    return [n.strip().lower() for n in text.split(',') if n.strip()]


def toy_surface(lines):
    """the public types of a module and their public bindings: {type: {binding: implementing procedure}}"""
    types, default_public, listed_public, listed_private = {}, True, set(), set()
    cur, in_bindings, bindings_private, type_public, depth = None, False, False, {}, 0
    for s in statements(lines):
        low = s.lower()
        if cur is None:
            if re.match(r'^contains\b', low):
                break
            if re.match(r'^(abstract\s+)?interface\b', low):
                depth += 1
                continue
            if re.match(r'^end\s*interface\b', low):
                depth -= 1
                continue
            if depth:
                continue
            m = re.match(r'^type\s*((?:,\s*[\w()]+\s*)*)(?:::)?\s*(\w+)$', low)
            if m and not low.startswith('type('):
                cur = m.group(2)
                attrs = split_names(m.group(1))
                type_public[cur] = True if 'public' in attrs else False if 'private' in attrs else None
                types[cur] = {}
                in_bindings = bindings_private = False
            elif low == 'private':
                default_public = False
            elif re.match(r'^public\s*::', low):
                listed_public.update(split_names(low.split('::', 1)[1]))
            elif re.match(r'^private\s*::', low):
                listed_private.update(split_names(low.split('::', 1)[1]))
            continue
        if re.match(r'^end\s*type\b', low):
            cur = None
        elif low == 'contains':
            in_bindings = True
        elif in_bindings and low == 'private':
            bindings_private = True
        elif in_bindings:
            m = re.match(r'^(procedure|generic)\s*(?:\([^)]*\)\s*)?((?:,\s*[\w()]+\s*)*)::\s*(.*)$', low)
            if not m:
                continue
            attrs = split_names(m.group(2))
            private = 'private' in attrs or (bindings_private and 'public' not in attrs)
            if private:
                continue
            if m.group(1) == 'generic':
                types[cur][m.group(3).split('=>')[0].strip()] = ''
                continue
            for item in split_names(m.group(3)):
                name, _, impl = [x.strip() for x in item.partition('=>')]
                types[cur][name] = impl or name
    out = {}
    for t, bindings in types.items():
        public = type_public[t]
        if public is None:
            public = t in listed_public or (default_public and t not in listed_private)
        if public:
            out[t] = bindings
    return out


def toy_procedures(lines):
    """the public module procedures of a toy module: the names of its public statements that are not its types"""
    types, listed_public, depth = set(), set(), 0
    for s in statements(lines):
        low = s.lower()
        if re.match(r'^contains\b', low):
            break
        if re.match(r'^(abstract\s+)?interface\b', low):
            depth += 1
            continue
        if re.match(r'^end\s*interface\b', low):
            depth -= 1
            continue
        if depth:
            continue
        m = re.match(r'^type\s*((?:,\s*[\w()]+\s*)*)(?:::)?\s*(\w+)$', low)
        if m and not low.startswith('type('):
            types.add(m.group(2))
        elif re.match(r'^public\s*::', low):
            listed_public.update(split_names(low.split('::', 1)[1]))
    return sorted(listed_public - types)


def read_mirror(root, out):
    """the ledger's lines: {(toy module, toy name): (line number, 'mirrored' or 'addition', SIMPLE's module, SIMPLE's
    name or the reason)}; None when there is no ledger"""
    rel = MIRROR_LEDGER
    if not os.path.isfile(os.path.join(root, rel)):
        return None
    entries, has_commit = {}, False
    for k, raw in enumerate(read(root, rel).split('\n'), 1):
        line = raw.strip()
        if line.startswith('#'):
            has_commit = has_commit or bool(MIRROR_COMMIT.match(line))
            continue
        if not line:
            continue
        words = line.split()
        if len(words) < 3:
            out.append('%s:%d: mirror: a line is `<toy module> <name> <SIMPLE module> <name>` or '
                       '`<toy module> <name> addition <reason>`' % (rel, k))
            continue
        key = (words[0].lower(), words[1].lower())
        if key in entries:
            out.append('%s:%d: mirror: %s %s listed twice' % (rel, k, words[0], words[1]))
            continue
        if words[2].lower() == 'addition':
            if len(words) < 4:
                out.append('%s:%d: mirror: %s %s is an addition without a reason' % (rel, k, words[0], words[1]))
            entries[key] = (k, 'addition', '', ' '.join(words[3:]))
            continue
        if len(words) != 4:
            out.append('%s:%d: mirror: a mirrored line is `<toy module> <name> <SIMPLE module> <name>`' % (rel, k))
            continue
        entries[key] = (k, 'mirrored', words[2].lower(), words[3].lower())
        if key[1] != words[3].lower():
            out.append('%s:%d: mirror: %s is listed as mirroring %s: a mirrored name is SIMPLE\'s'
                       % (rel, k, words[1], words[3]))
        if not (key[0].startswith(TOY_PREFIX) and words[2].lower() == SIMPLE_PREFIX + key[0][len(TOY_PREFIX):]):
            out.append('%s:%d: mirror: %s is listed beside %s: the module of a mirrored name is %s<stem> beside '
                       '%s<stem>' % (rel, k, words[0], words[2], TOY_PREFIX, SIMPLE_PREFIX))
    if not has_commit:
        out.append('%s: mirror: the header does not record the SIMPLE commit that was read '
                   '(`# ... SIMPLE commit <hash>`)' % rel)
    return entries


def check_mirror(root, files, out):
    """the mirror ledger against the toy modules; returns {toy module: the procedures that keep SIMPLE's dummy
    list}, for rule arity"""
    surfaces = {}
    for rel in files:
        if not rel.startswith(TOY_DIR):
            continue
        lines = read(root, rel).split('\n')
        name, is_sub = toy_module(lines)
        if name and not is_sub:
            procedures = [] if name.endswith('_tester') else toy_procedures(lines)
            surfaces[name] = (rel, toy_surface(lines), procedures)
    entries = read_mirror(root, out)
    if entries is None:
        if surfaces:
            out.append('%s: mirror: the ledger is missing, and %d toy module(s) exist' % (MIRROR_LEDGER, len(surfaces)))
        return {}
    known, exempt = set(), {}
    for module, (rel, types, procedures) in sorted(surfaces.items()):
        names = [(p, p) for p in procedures]
        for t, bindings in sorted(types.items()):
            names += [(t, '')] + [('%s%%%s' % (t, b), i) for b, i in sorted(bindings.items())]
        for name, impl in names:
            known.add((module, name))
            if (module, name) not in entries:
                out.append('%s: mirror: %s of %s has no line in %s' % (rel, name, module, MIRROR_LEDGER))
            elif entries[(module, name)][1] == 'mirrored' and impl:
                exempt.setdefault(module, set()).add(impl)
    for (module, name), entry in sorted(entries.items(), key=lambda e: e[1][0]):
        if (module, name) not in known:
            out.append('%s:%d: mirror: %s %s is not a public type, binding or procedure of a toy module'
                       % (MIRROR_LEDGER, entry[0], module, name))
    return exempt


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
    tree_functions = set()
    for rel in files:
        tree_functions |= exported_handle_functions(read(root, rel).split('\n'))
    # the user API is ctorcall's (and its generics named after intrinsics also take plain Fortran arguments)
    tree_functions -= api
    check_reexport_mlxc(root, out)
    mirrored = check_mirror(root, files, out)
    for rel in files:
        lines = read(root, rel).split('\n')
        codes = [code_of(l) for l in lines]
        raws = [raw_code(l) for l in lines]
        check_layout(rel, lines, out)
        check_ctor(rel, codes, out)
        check_cbstop(rel, lines, out)
        check_arity(rel, lines, out, mirrored.get(toy_module(lines)[0], ()) if rel.startswith(TOY_DIR) else ())
        check_ctorcall(rel, lines, api, out)
        check_ctorexpr(rel, lines, out, tree_functions)
        check_nanmax(rel, lines, out)
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
    check_findpkg(root, out)
    check_cmakeroot(root, out)
    check_fortlsoff(root, out)
    check_devquery(root, files, out)
    check_docex(root, out)
    check_cbsig(root, out)
    check_parity(root, files, api, out)
    ledger_check('cbind', cbind, CBIND_LEDGER, out)
    ledger_check('libc', libc, LIBC_LEDGER, out)
    ledger_check('prints', prints, PRINT_LEDGER, out)
    ledger_check('state', state, STATE_LEDGER, out)
    if listing:
        print(__doc__)
        for name, ledger in (('cbind', CBIND_LEDGER), ('libc', LIBC_LEDGER), ('prints', PRINT_LEDGER),
                             ('state', STATE_LEDGER), ('devquery', DEVQUERY_LEDGER)):
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
