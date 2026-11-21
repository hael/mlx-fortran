!@descr: the area suites of mlxf_test_exec: per area, its sub-suites in order and their tester entries
! A tester runs only from here; scripts/check_test_registry.py holds the areas to the CTest entries of
! test/CMakeLists.txt and every run_all_<x>_tests of a tester to a row.
module mlxf_test_registry
use mlxf_version_tester, only: run_all_version_tests
use mlxf_test_utils,     only: begin_test_suite, end_test_suite
implicit none
private

public :: run_area, list_areas

abstract interface
    subroutine tester_entry()
    end subroutine tester_entry
end interface

character(len=*), parameter :: AREAS(1) = [character(len=16) :: 'core']

contains

    ! runs the sub-suites of one area, or only the one named by suite (empty: all)
    subroutine run_area( area, suite, found )
        character(len=*), intent(in)  :: area, suite
        logical,          intent(out) :: found
        logical :: ran
        found = .true.
        ran   = .false.
        select case( trim(area) )
            case('core')
                call run_suite('version', run_all_version_tests, suite, ran)
            case default
                found = .false.
                return
        end select
        if( len_trim(suite) > 0 .and. .not. ran ) found = .false.
    end subroutine run_area

    subroutine list_areas
        integer :: i
        write(*,'(A)') 'mlxf_test_exec test=<name> [suite=<sub-suite>]; tests:'
        do i = 1, size(AREAS)
            write(*,'(A)') '    unit_'//trim(AREAS(i))
        end do
    end subroutine list_areas

    subroutine run_suite( name, entry, only, ran )
        character(len=*), intent(in)    :: name, only
        procedure(tester_entry)         :: entry
        logical,          intent(inout) :: ran
        if( len_trim(only) > 0 .and. trim(only) /= name ) return
        call begin_test_suite(name)
        call entry()
        call end_test_suite
        ran = .true.
    end subroutine run_suite

end module mlxf_test_registry
