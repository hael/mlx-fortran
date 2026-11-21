!@descr: the one test executable: mlxf_test_exec test=<unit_area|list> [suite=<sub-suite>]
! Exits with status 1 when an assertion fails, 2 on a usage error.
program mlxf_test_exec
use mlxf_test_registry, only: run_area, list_areas
use mlxf_test_utils,    only: report_summary
implicit none
character(len=256) :: arg, test, suite
integer            :: i
logical            :: found, failed
test  = ''
suite = ''
do i = 1, command_argument_count()
    call get_command_argument(i, arg)
    if( index(arg, 'test=') == 1 )then
        test = arg(6:)
    else if( index(arg, 'suite=') == 1 )then
        suite = arg(7:)
    else
        write(*,'(A)') 'mlxf_test_exec: unknown argument '//trim(arg)
        call list_areas
        error stop 2
    endif
end do
if( len_trim(test) == 0 .or. trim(test) == 'list' )then
    call list_areas
    stop
endif
if( index(test, 'unit_') /= 1 )then
    write(*,'(A)') 'mlxf_test_exec: unknown test '//trim(test)
    call list_areas
    error stop 2
endif
call run_area(test(6:), suite, found)
if( .not. found )then
    write(*,'(A)') 'mlxf_test_exec: no test '//trim(test)//' with suite "'//trim(suite)//'"'
    call list_areas
    error stop 2
endif
call report_summary(failed)
if( failed ) error stop 1
end program mlxf_test_exec
