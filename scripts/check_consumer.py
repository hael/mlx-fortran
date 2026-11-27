#!/usr/bin/env python3
"""check_consumer.py -- the lifetime checker for programs that use mlxf: reports the forms gfortran leaks or copies
bitwise when they hold mlx_array handles, each with its file, line and safe spelling. Installed with the package
(<prefix>/share/mlxf/), with its analysis module mlxf_consumer_checks.py, which the repository's own rules
(scripts/check_rules.py) share.

usage: check_consumer.py FILE...           check the named Fortran files (.f90, .F90, ...), each read alone
       check_consumer.py --rules           print the rules and what the checker cannot see
       check_consumer.py --self-test       run the planted fixtures: every rule's unsafe form found, its safe form not

exit status: 0 nothing found, 1 findings, 2 usage or an unreadable file. A clean result covers only the forms of
--rules in the files given; it is no proof that a program leaks nothing (mlx_live_count() at run time is).
Python 3.7 or newer, standard library only.
"""
import os
import sys

# no bytecode cache beside the sources: the release gate holds the source tree unchanged by a build
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mlxf_consumer_checks as checks  # noqa: E402

LIMITS = ('checked: the forms of --rules, in each file alone; not checked: handles declared in other files, '
          'aliasing, macros and inactive preprocessor branches (read as written), forms not listed')

# (name, source, the rules it must report, in any order): each rule's unsafe form, its safe form, a renamed
# import, a whole `use mlxf` and the preprocessor's limit
FIXTURES = [
    ('ctorcall', '''
program p
use mlxf, only: mlx_array, mlx_from, mlx_concatenate
type(mlx_array) :: a, c
real :: x(3)
c = mlx_concatenate([a, mlx_from(x)])
end program p
''', ['ctorcall']),
    ('ctorcall renamed', '''
program p
use mlxf, only: mlx_array, from => mlx_from, cat => mlx_concatenate
type(mlx_array) :: a, c
real :: x(3)
c = cat([a, from(x)])
end program p
''', ['ctorcall']),
    ('ctorcall whole module', '''
program p
use mlxf
type(mlx_array) :: a, c
real :: x(3)
c = mlx_concatenate([a, mlx_from(x)])
end program p
''', ['ctorcall']),
    ('ctorcall safe', '''
program p
use mlxf, only: mlx_array, from => mlx_from, cat => mlx_concatenate
type(mlx_array) :: a, b, c
real :: x(3)
b = from(x)
c = cat([a, b])
end program p
''', []),
    ('ctorexpr', '''
program p
use mlxf, only: mlx_array, mlx_concatenate, exp
type(mlx_array) :: a, b, c
c = mlx_concatenate([a, exp(b)])
c = mlx_concatenate([a, b*2.0])
c = mlx_concatenate([-a, b])
end program p
''', ['ctorexpr', 'ctorexpr', 'ctorexpr']),
    ('ctorexpr renamed generic', '''
program p
use mlxf, only: mlx_array, mlx_concatenate, e => exp
type(mlx_array) :: a, b, c
c = mlx_concatenate([a, e(b)])
end program p
''', ['ctorexpr']),
    ('ctorexpr safe', '''
program p
use mlxf, only: mlx_array, mlx_concatenate, exp
type(mlx_array) :: a, b, c, t, v(2)
integer :: s(2)
t = exp(b)
c = mlx_concatenate([a, t, v(1), v(2)])
s = [a%ndim(), size(v)]
end program p
''', []),
    ('ctorexpr sibling scopes', '''
module m
use mlxf, only: mlx_array
implicit none
contains
    subroutine device_part(a)
        type(mlx_array), intent(in) :: a
    end subroutine device_part
    subroutine host_part(a, b)
        real, intent(in) :: a
        real, intent(out) :: b(1)
        b = [2*a]
    end subroutine host_part
end module m
''', []),
    ('ctorexpr host and shadowed scopes', '''
module m
use mlxf, only: mlx_array, mlx_concatenate
implicit none
type(mlx_array) :: g
contains
    subroutine uses_host(c)
        type(mlx_array), intent(inout) :: c
        c = mlx_concatenate([c, g*2.0])
    end subroutine uses_host
    subroutine shadows(b)
        real, intent(out) :: b(1)
        real :: g
        g = 1.0
        b = [2*g]
    end subroutine shadows
end module m
''', ['ctorexpr']),
    ('wholefunc', '''
program p
use mlxf, only: mlx_array, exp
type(mlx_array) :: a, v(3)
type(mlx_array), allocatable :: w(:)
v = exp(a)
v(1:2) = a*2.0
allocate(w(3))
w(:) = exp(a)
end program p
''', ['wholefunc', 'wholefunc', 'wholefunc']),
    ('wholefunc safe', '''
program p
use mlxf, only: mlx_array, exp
type(mlx_array) :: a, t, v(3), u(3)
integer :: i
t = exp(a)
v = t
u = v
do i = 1, 3
    v(i) = exp(a)
end do
end program p
''', []),
    ('viewexpr', '''
program p
use, intrinsic :: iso_fortran_env, only: real32
use mlxf, only: mlx_array, view => mlx_view, exp
type(mlx_array) :: a
real(real32), pointer :: q(:)
call view(exp(a), q)
end program p
''', ['viewexpr']),
    ('viewexpr safe', '''
program p
use, intrinsic :: iso_fortran_env, only: real32
use mlxf, only: mlx_array, mlx_view, exp
type(mlx_array) :: a, w
real(real32), pointer :: q(:)
w = exp(a)
call mlx_view(w, q)
end program p
''', []),
    ('viewexpr component', '''
module m
use, intrinsic :: iso_fortran_env, only: real32
use mlxf, only: mlx_array, mlx_view
type :: box
    type(mlx_array) :: r
end type box
contains
    subroutine look( b, p )
        type(box), intent(in) :: b
        real(real32), pointer :: p(:)
        call mlx_view(b%r, p)
    end subroutine look
end module m
''', []),
    ('scopes, a scalar here and an array elsewhere', '''
module m
use mlxf, only: mlx_array, mlx_from, exp
contains
    subroutine one( x )
        real, intent(in) :: x(3)
        type(mlx_array) :: a
        a = mlx_from(x)
    end subroutine one
    subroutine two( b )
        type(mlx_array), intent(in) :: b
        type(mlx_array) :: a(2)
        a = exp(b)
    end subroutine two
end module m
''', ['wholefunc']),
    ('overlap', '''
program p
use mlxf, only: mlx_array
type(mlx_array) :: v(4)
v(2:3) = v(1:2)
end program p
''', ['overlap']),
    ('alloccomp', '''
module m
use mlxf, only: mlx_array
implicit none
type :: holder
    type(mlx_array), allocatable :: arr(:)
end type holder
end module m
''', ['alloccomp']),
    ('alloccomp safe', '''
module m
use mlxf, only: mlx_array
implicit none
type :: holder
    type(mlx_array), allocatable :: arr(:)
  contains
    procedure, private :: holder_assign
    generic            :: assignment(=) => holder_assign
end type holder
type :: plain
    type(mlx_array) :: a
end type plain
contains
    impure elemental subroutine holder_assign( lhs, rhs )
        class(holder), intent(inout) :: lhs
        class(holder), intent(in)    :: rhs
    end subroutine holder_assign
end module m
''', []),
    ('allocsrc', '''
program p
use mlxf, only: mlx_array
type(mlx_array) :: a
type(mlx_array), allocatable :: b, c(:)
allocate(b, source=a)
allocate(c(3), mold=a)
end program p
''', ['allocsrc', 'allocsrc']),
    ('arrayintr', '''
program p
use mlxf, only: mlx_array, reshape
type(mlx_array) :: v(4), w(2, 2), a, r
w = reshape(v, [2, 2])
v = cshift(v, 1)
r = reshape(a, [2, 2])
end program p
''', ['arrayintr', 'arrayintr']),
    ('selfassign', '''
program p
use mlxf, only: mlx_array
type :: pair
    type(mlx_array) :: a, b
end type pair
type(pair) :: w
type(mlx_array) :: x
w = w
x = x
end program p
''', ['selfassign']),
    ('preprocessor, an inactive branch is read as written', '''
program p
use mlxf, only: mlx_array, mlx_from, mlx_concatenate
type(mlx_array) :: a, c
real :: x(3)
#if 0
c = mlx_concatenate([a, mlx_from(x)])
#endif
end program p
''', ['ctorcall']),
    ('handles of another file are not seen', '''
program p
use mlxf, only: mlx_concatenate
use other, only: a, b
c = mlx_concatenate([a, b*2.0])
end program p
''', []),
]


def self_test():
    failures = 0
    for name, source, want in FIXTURES:
        found = checks.check_lines(name, source.split('\n'))
        rules = sorted(f.split(': ', 2)[1] for f in found)
        if rules != sorted(want):
            failures += 1
            print('check_consumer: self-test %r: expected %s, found %s' % (name, sorted(want), rules), file=sys.stderr)
            for f in found:
                print('    ' + f, file=sys.stderr)
    covered = set(r for _, _, want in FIXTURES for r in want)
    missing = set(checks.CONSUMER_RULES) - covered
    if missing:
        failures += 1
        print('check_consumer: self-test: no planted fixture for %s' % ', '.join(sorted(missing)), file=sys.stderr)
    if failures:
        return 1
    print('check_consumer: self-test passed (%d fixtures, every rule planted and found, its safe form clean)'
          % len(FIXTURES))
    return 0


def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return 0 if argv else 2
    if argv[0] == '--rules':
        print(checks.__doc__)
        return 0
    if argv[0] == '--self-test':
        return self_test()
    findings, status = [], 0
    for path in argv:
        try:
            with open(path, encoding='utf-8', errors='replace') as h:
                lines = h.read().split('\n')
        except OSError as e:
            print('check_consumer: cannot read %s: %s' % (path, e), file=sys.stderr)
            status = 2
            continue
        findings += checks.check_lines(path, lines)
    for f in findings:
        print(f)
    print('check_consumer: %d file(s), %d finding(s); %s' % (len(argv), len(findings), LIMITS),
          file=sys.stderr if findings else sys.stdout)
    if status:
        return status
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
