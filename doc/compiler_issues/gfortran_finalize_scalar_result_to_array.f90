! gfortran: a scalar function result assigned to a whole array through a type-bound impure elemental defined
! assignment is never finalized; the same result assigned to one element is.
! F2018 7.5.6.3 (paragraph 5): the result of a referenced nonpointer function is finalized after execution of
! the innermost executable construct containing the reference.
! Expected: finals = 1 after each statement. Observed 2026-11-21 with GNU Fortran 16.2.0 and 13.4.0 (Homebrew,
! aarch64-apple-darwin25, -std=f2018, -O0 and -O3): 1 for v(1) = mk(1), 0 for v = mk(2).
! Build and run: gfortran -std=f2018 -Wall gfortran_finalize_scalar_result_to_array.f90 && ./a.out
module m
implicit none
integer :: nfinal = 0, nassign = 0
type :: t
    integer :: id = 0
contains
    procedure, private :: t_assign
    generic :: assignment(=) => t_assign
    final :: t_final
end type t
contains
    impure elemental subroutine t_assign( lhs, rhs )
        class(t), intent(inout) :: lhs
        class(t), intent(in)    :: rhs
        nassign = nassign + 1
        lhs%id = rhs%id
    end subroutine t_assign
    impure elemental subroutine t_final( x )
        type(t), intent(inout) :: x
        nfinal = nfinal + 1
        x%id = 0
    end subroutine t_final
    function mk( id ) result(x)
        integer, intent(in) :: id
        type(t) :: x
        x%id = id
    end function mk
end module m

program p
use m, only: t, mk, nfinal, nassign
implicit none
type(t) :: v(3)
nfinal = 0
nassign = 0
v(1) = mk(1)
write(*,'(a,i0,a,i0,a)') 'v(1) = mk(1): assignments = ', nassign, ', finals = ', nfinal, ' (expected 1, 1)'
nfinal = 0
nassign = 0
v = mk(2)
write(*,'(a,i0,a,i0,a)') 'v = mk(2):    assignments = ', nassign, ', finals = ', nfinal, ' (expected 3, 1)'
end program p
