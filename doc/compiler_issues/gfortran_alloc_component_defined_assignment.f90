! gfortran: intrinsic assignment of a derived type skips the type-bound defined assignment of allocatable
! components. F2018 10.2.1.3 (paragraph 13) requires defined assignment for a noncoarray allocatable component
! whose declared type has a consistent type-bound defined assignment, as for a plain component.
!
! Observed 2026-11-20, GNU Fortran (Homebrew GCC 16.2.0) 16.2.0, aarch64-apple-darwin25, -std=f2018, with
! -O0 -g -fcheck=bounds,do,mem and with -O3 (same output):
!   plain component:            defined assignments = 1
!   allocatable scalar comp:    defined assignments = 0
!   allocatable array comp:     defined assignments = 0
!   allocate(source=):          defined assignments = 0   (conforming: ALLOCATE does not use assignment)
!   self assignment t = t:      defined assignments = 1
! Expected for the two allocatable components: 1 and 3.
!
! Build and run: gfortran -std=f2018 gfortran_alloc_component_defined_assignment.f90 && ./a.out
module h_mod
implicit none
integer :: nassign = 0
type :: h
    integer :: id = 0
contains
    procedure, private :: h_assign
    generic :: assignment(=) => h_assign
end type h
contains
    impure elemental subroutine h_assign( lhs, rhs )
        class(h), intent(inout) :: lhs
        class(h), intent(in)    :: rhs
        nassign = nassign + 1
        lhs%id  = rhs%id
    end subroutine h_assign
end module h_mod

module c_mod
use h_mod, only: h
implicit none
type :: c_plain
    type(h) :: x
end type c_plain
type :: c_alloc
    type(h), allocatable :: x
end type c_alloc
type :: c_arr
    type(h), allocatable :: x(:)
end type c_arr
end module c_mod

program gfortran_alloc_component_defined_assignment
use h_mod, only: h, nassign
use c_mod, only: c_plain, c_alloc, c_arr
implicit none
type(c_plain) :: a1, b1
type(c_alloc) :: a2, b2
type(c_arr)   :: a3, b3
type(h), allocatable :: s
type(h) :: t
a1%x%id = 7
nassign = 0
b1 = a1
print '(a,i0)', 'plain component:            defined assignments = ', nassign
allocate(a2%x)
a2%x%id = 7
nassign = 0
b2 = a2
print '(a,i0)', 'allocatable scalar comp:    defined assignments = ', nassign
allocate(a3%x(3))
a3%x%id = 7
nassign = 0
b3 = a3
print '(a,i0)', 'allocatable array comp:     defined assignments = ', nassign
t%id = 7
nassign = 0
allocate(s, source=t)
print '(a,i0)', 'allocate(source=):          defined assignments = ', nassign
nassign = 0
t = t
print '(a,i0)', 'self assignment t = t:      defined assignments = ', nassign
end program gfortran_alloc_component_defined_assignment
