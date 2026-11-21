! gfortran: intrinsic self-assignment w = w of a derived type whose plain components have a final procedure
! and a type-bound defined assignment finalizes the components of a copy of the right side before the
! defined assignments read it, so every component is released and then assigned its finalized value.
! F2018 10.2.1.3: in intrinsic assignment expr is evaluated before the variable is finalized and defined;
! the finalized object must be the variable, and the component assignments must see the value of expr.
! Expected: after w = w the component ids are unchanged (5) and each was finalized at most once as part of
! the variable. Observed 2026-11-21 with GNU Fortran 16.2.0 and 13.4.0 (Homebrew, aarch64-apple-darwin25, -std=f2018,
! -O0 and -O3): finals see id 5, then the defined assignment sees rhs id 0, and w%c%id ends 0.
! Build and run: gfortran -std=f2018 -Wall gfortran_self_assignment_finalizable_components.f90 && ./a.out
module m
implicit none
type :: c
    integer :: id = 0
contains
    procedure, private :: c_assign
    generic :: assignment(=) => c_assign
    final :: c_final
end type c
type :: wrap
    type(c) :: c
end type wrap
contains
    impure elemental subroutine c_assign( lhs, rhs )
        class(c), intent(inout) :: lhs
        class(c), intent(in)    :: rhs
        write(*,'(a,i0,a,i0)') '    defined assignment: lhs id ', lhs%id, ' <- rhs id ', rhs%id
        lhs%id = rhs%id
    end subroutine c_assign
    impure elemental subroutine c_final( x )
        type(c), intent(inout) :: x
        write(*,'(a,i0)') '    final: id ', x%id
        x%id = 0
    end subroutine c_final
end module m

program p
use m, only: wrap
implicit none
type(wrap) :: w
w%c%id = 5
write(*,'(a)') 'w = w'
w = w
write(*,'(a,i0,a)') 'after w = w: w%c%id = ', w%c%id, ' (expected 5)'
end program p
