! gfortran: an empty pack() result passed to an assumed-rank dummy arrives with a corrupt descriptor, so size()
! reports -1 and select rank does not take the rank(1) arm.
! F2018 8.5.8.7 and 16.9.140: the dummy has the rank and shape of the actual, here a zero-size array of rank 1;
! size(x) is 0 and select rank selects rank(1).
! Expected: "nonempty: rank 1 size 5 arm 1" and "empty: rank 1 size 0 arm 1".
! Observed 2026-11-25 with GNU Fortran 16.2.0 (Homebrew, aarch64-apple-darwin27, -std=f2018, -O0):
! "nonempty: rank 1 size 5 arm 1" and "empty: rank 1 size -1 arm default".
! Build and run: gfortran -std=f2018 -Wall gfortran_empty_pack_assumed_rank.f90 && ./a.out
module m
implicit none
contains
    subroutine show( label, x )
        character(len=*), intent(in) :: label
        real,             intent(in) :: x(..)
        character(len=7) :: arm
        select rank( x )
            rank(1)
                arm = '1'
            rank default
                arm = 'default'
        end select
        write(*,'(a,a,i0,a,i0,a,a)') label, ': rank ', rank(x), ' size ', size(x), ' arm ', trim(arm)
    end subroutine show
end module m

program empty_pack_assumed_rank
use m, only: show
implicit none
real :: v(5)
v = 1.
call show('nonempty', pack(v, v > 0.))
call show('empty', pack(v, v > 9.))
end program empty_pack_assumed_rank
