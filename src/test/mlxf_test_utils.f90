!@descr: assertions, suite tracking and the summary of mlxf_test_exec
! Adapted from SIMPLE's simple_test_utils: same names and output, without SIMPLE's types.
module mlxf_test_utils
use, intrinsic :: iso_fortran_env, only: output_unit, int64, real32, real64
implicit none
private

public :: assert_true, assert_false, assert_int, assert_real, assert_double, assert_char
public :: begin_test_suite, end_test_suite, report_summary
public :: tests_run, tests_failed
public :: set_fixed_seed

integer, parameter :: MSGLEN = 512

type :: test_suite_result
    character(len=MSGLEN) :: name      = ''
    integer               :: checks    = 0
    integer               :: failures  = 0
    logical               :: completed = .false.
    integer(int64)        :: t_start   = 0_int64
    real                  :: seconds   = 0.
end type test_suite_result

type :: test_failure
    character(len=MSGLEN) :: suite   = ''
    character(len=MSGLEN) :: message = ''
end type test_failure

integer :: tests_run    = 0
integer :: tests_failed = 0
integer :: active_suite = 0
type(test_suite_result), allocatable :: suites(:)
type(test_failure),      allocatable :: failures(:)

contains

    ! seeds the intrinsic generator with a fixed, reproducible state derived from base_seed
    subroutine set_fixed_seed( base_seed )
        integer, intent(in) :: base_seed
        integer, allocatable :: seed(:)
        integer              :: n, i
        call random_seed(size=n)
        allocate(seed(n))
        do i = 1, n
            seed(i) = int(modulo(int(base_seed, int64) + 2654435761_int64 * int(i, int64), 2147483647_int64))
        end do
        call random_seed(put=seed)
    end subroutine set_fixed_seed

    subroutine begin_test_suite( name )
        character(len=*), intent(in) :: name
        type(test_suite_result) :: suite
        if( active_suite > 0 ) call end_test_suite
        suite%name = trim(name)
        if( allocated(suites) )then
            suites = [suites, suite]
        else
            allocate(suites(1))
            suites(1) = suite
        endif
        active_suite = size(suites)
        call system_clock(suites(active_suite)%t_start)
        write(output_unit,'(A)') '---- TEST SUITE: '//trim(suite%name)//' ----'
    end subroutine begin_test_suite

    subroutine end_test_suite
        character(len=MSGLEN) :: name
        character(len=32)     :: tstr
        integer               :: checks, nfailed
        integer(int64)        :: t_end, rate
        if( active_suite == 0 ) return
        call system_clock(t_end, rate)
        if( rate > 0_int64 ) suites(active_suite)%seconds = real(t_end - suites(active_suite)%t_start) / real(rate)
        write(tstr,'(F0.2,A)') suites(active_suite)%seconds, ' s'
        name    = suites(active_suite)%name
        checks  = suites(active_suite)%checks
        nfailed = suites(active_suite)%failures
        if( nfailed == 0 )then
            write(output_unit,'(A,I0,A)') 'PASS: '//trim(name)//' (', checks, ' checks, '//trim(tstr)//')'
        else
            write(output_unit,'(A,I0,A,I0,A)') 'FAIL: '//trim(name)//' (', nfailed, ' of ', checks, &
                &' checks failed, '//trim(tstr)//')'
        endif
        suites(active_suite)%completed = .true.
        active_suite = 0
    end subroutine end_test_suite

    subroutine assert_true( cond, msg )
        logical,          intent(in) :: cond
        character(len=*), intent(in) :: msg
        call record_assertion(cond, msg)
    end subroutine assert_true

    subroutine assert_false( cond, msg )
        logical,          intent(in) :: cond
        character(len=*), intent(in) :: msg
        call record_assertion(.not. cond, msg)
    end subroutine assert_false

    subroutine assert_int( expected, actual, msg )
        integer,          intent(in) :: expected, actual
        character(len=*), intent(in) :: msg
        character(len=MSGLEN) :: detail
        if( expected == actual )then
            call record_assertion(.true., msg)
        else
            write(detail,'(A,I0,A,I0)') trim(msg)//' expected=', expected, ' actual=', actual
            call record_assertion(.false., detail)
        endif
    end subroutine assert_int

    ! |expected - actual| <= tol in single precision
    subroutine assert_real( expected, actual, tol, msg )
        real(real32),     intent(in) :: expected, actual, tol
        character(len=*), intent(in) :: msg
        character(len=MSGLEN) :: detail
        if( abs(expected - actual) <= tol )then
            call record_assertion(.true., msg)
        else
            write(detail,'(A,G0,A,G0,A,G0)') trim(msg)//' expected=', expected, ' actual=', actual, ' tolerance=', tol
            call record_assertion(.false., detail)
        endif
    end subroutine assert_real

    ! |expected - actual| <= tol in double precision
    subroutine assert_double( expected, actual, tol, msg )
        real(real64),     intent(in) :: expected, actual, tol
        character(len=*), intent(in) :: msg
        character(len=MSGLEN) :: detail
        if( abs(expected - actual) <= tol )then
            call record_assertion(.true., msg)
        else
            write(detail,'(A,ES24.16,A,ES24.16,A,ES14.6)') trim(msg)//' expected=', expected, &
                &' actual=', actual, ' tolerance=', tol
            call record_assertion(.false., detail)
        endif
    end subroutine assert_double

    subroutine assert_char( expected, actual, msg )
        character(len=*), intent(in) :: expected, actual, msg
        character(len=MSGLEN) :: detail
        if( trim(expected) == trim(actual) )then
            call record_assertion(.true., msg)
        else
            detail = trim(msg)//' expected="'//trim(expected)//'" actual="'//trim(actual)//'"'
            call record_assertion(.false., detail)
        endif
    end subroutine assert_char

    subroutine record_assertion( passed, message )
        logical,          intent(in) :: passed
        character(len=*), intent(in) :: message
        type(test_failure) :: failure
        tests_run = tests_run + 1
        if( active_suite > 0 ) suites(active_suite)%checks = suites(active_suite)%checks + 1
        if( passed ) return
        tests_failed    = tests_failed + 1
        failure%message = trim(message)
        if( active_suite > 0 )then
            suites(active_suite)%failures = suites(active_suite)%failures + 1
            failure%suite = suites(active_suite)%name
        else
            failure%suite = 'unscoped'
        endif
        if( allocated(failures) )then
            failures = [failures, failure]
        else
            allocate(failures(1))
            failures(1) = failure
        endif
        write(output_unit,'(A)') 'FAIL: '//trim(failure%message)
    end subroutine record_assertion

    ! closes an open suite, prints the summary and says whether any assertion failed
    subroutine report_summary( failed )
        logical, intent(out) :: failed
        integer :: i, nsuites, npassed, nfailed
        if( active_suite > 0 ) call end_test_suite
        nsuites = 0
        npassed = 0
        nfailed = 0
        if( allocated(suites) )then
            nsuites = size(suites)
            npassed = count(suites%completed .and. suites%failures == 0)
            nfailed = count(suites%completed .and. suites%failures > 0)
        endif
        write(output_unit,'(A)') ''
        write(output_unit,'(A)') '========== MLXF TEST SUMMARY =========='
        if( tests_failed == 0 )then
            write(output_unit,'(A)') 'RESULT: PASS'
        else
            write(output_unit,'(A)') 'RESULT: FAIL'
        endif
        write(output_unit,'(A,I0,A,I0,A,I0,A)') 'Test groups: ', nsuites, ' run; ', npassed, ' passed; ', &
            &nfailed, ' failed.'
        write(output_unit,'(A,I0,A,I0,A,I0,A)') 'Assertions: ', tests_run, ' evaluated; ', &
            &tests_run - tests_failed, ' passed; ', tests_failed, ' failed.'
        if( allocated(failures) )then
            write(output_unit,'(A)') 'Failures:'
            do i = 1, size(failures)
                write(output_unit,'(A)') '  ['//trim(failures(i)%suite)//'] '//trim(failures(i)%message)
            enddo
        endif
        write(output_unit,'(A)') '======================================='
        failed = tests_failed > 0
    end subroutine report_summary

end module mlxf_test_utils
