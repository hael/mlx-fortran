! gfortran: an allocatable array function result of a finalizable type, passed as an actual argument through a
! procedure pointer, is freed before it is finalized (a heap-use-after-free in the final procedure).
! F2018 7.5.6.3 (paragraph 5): the result of a referenced nonpointer function is finalized after execution of
! the innermost executable construct containing the reference; its storage is freed after that.
! Expected: both lines print PASS. Observed 2026-11-22 with GNU Fortran 16.2.0 (Homebrew, aarch64-apple-darwin25),
! on Apple M3 Pro, macOS 26.7.3, using the command below: compilation exit 0, zero warnings. This merged
! program printed "subroutine with an allocatable intent(out) output: PASS", then AddressSanitizer reported
! "heap-use-after-free", "WRITE of size 4" in finish during the function case. It aborted with SIGABRT
! (subprocess return code -6); the function PASS line was not reached. Full output is in
! /Users/elmlundho/for_claude/mlxf-review-2026-11-22/compiler-issue5.log.
! Build and run: gfortran-16 -std=f2018 -Wall -O0 -g -fsanitize=address \
!                gfortran_finalize_allocatable_array_result.f90 && ASAN_OPTIONS=symbolize=0 ./a.out
module callback_probe
implicit none
type :: item
    integer :: id = 0
contains
    final :: finish
end type item
abstract interface
    function callback() result(r)
        import :: item
        type(item), allocatable :: r(:)
    end function callback
end interface
type :: payload
    procedure(callback), pointer, nopass :: f => null()
end type payload
contains
    impure elemental subroutine finish( x )
        type(item), intent(inout) :: x
        x%id = 0
    end subroutine finish
    function make() result(r)
        type(item), allocatable :: r(:)
        allocate(r(2))
        r%id = 7
    end function make
    subroutine make_output( r, status )
        type(item), allocatable, intent(out) :: r(:)
        integer,                 intent(out) :: status
        allocate(r(2), stat=status)
        if( status == 0 ) r%id = 7
    end subroutine make_output
    subroutine consume( x )
        type(item), intent(in) :: x(:)
        if( any(x%id /= 7) ) error stop 'bad result'
    end subroutine consume
end module callback_probe

program p
use callback_probe, only: item, payload, make, make_output, consume
implicit none
type(payload)           :: q
type(item), allocatable :: output(:)
integer                 :: i, status
q%f => make
status = 0
do i = 1, 10
    call make_output(output, status)
    if( status /= 0 ) error stop 'allocation failed'
    call consume(output)
    deallocate(output)
end do
write(*,'(a)') 'subroutine with an allocatable intent(out) output: PASS'
do i = 1, 10
    call consume(q%f())
end do
write(*,'(a)') 'function result through a procedure pointer:       PASS'
end program p
