! gfortran: a function result referenced inside an array constructor is never finalized.
! F2018 7.5.6.3 (paragraph 5): "If an executable construct references a nonpointer function, the result is
! finalized after execution of the innermost executable construct containing the reference."
! Expected: the counts in parentheses. Observed 2026-11-21 with GNU Fortran 16.2.0 and
! 13.4.0 (Homebrew, aarch64-apple-darwin25, -std=f2018, -O0 and -O3): finals = 0 for both statements, while a
! result outside a constructor (x = mk()) is finalized once.
! Build and run: gfortran -std=f2018 -Wall gfortran_finalize_ctor_function_results.f90 && ./a.out
module m
implicit none
integer :: nfinal = 0
type :: t
    integer :: id = 0
contains
    final :: t_final
end type t
contains
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
    subroutine take( x )
        type(t), intent(in) :: x(:)
        if( any(x%id < 0) ) write(*,'(a)') 'negative id'
    end subroutine take
end module m

program p
use m, only: t, mk, take, nfinal
implicit none
type(t), allocatable :: v(:)
type(t)              :: x
allocate(v(2))
nfinal = 0
x = mk(1)
write(*,'(a,i0,a)') 'x = mk(1):               finals = ', nfinal, ' (expected 2: the result, and x before definition)'
nfinal = 0
call take([mk(1), mk(2)])
write(*,'(a,i0,a)') 'call take([mk(1), mk(2)]): finals = ', nfinal, ' (expected 2)'
nfinal = 0
v = [mk(3), mk(4)]
write(*,'(a,i0,a)') 'v = [mk(3), mk(4)]:       finals = ', nfinal, ' (expected 4: two results, v before definition)'
end program p
