!@descr: tests of the neighbourhood lists' host oracle: its self-checks asserted
! The oracle returns its checks as (labels, errors, limits) and asserts nothing; here each error is held to its own
! limit, before the toy's driver is judged against the oracle. Host only: no device is involved.
module mlxf_oracle_neigh_tester
use, intrinsic :: iso_fortran_env, only: real64
use mlxf_oracle_neigh, only: oracle_neigh_selfcheck
use mlxf_test_utils,   only: assert_true
implicit none
private
public :: run_all_oracle_neigh_tests

contains

    subroutine run_all_oracle_neigh_tests
        character(len=:), allocatable :: labels(:)
        real(real64),     allocatable :: errors(:), limits(:)
        character(len=160)            :: line
        integer                       :: i
        write(*,'(a)') '**** running all oracle_neigh tests ****'
        call oracle_neigh_selfcheck(labels, errors, limits)
        do i = 1, size(labels)
            write(line,'(a,es10.3,a,es10.3)') '    oracle_neigh '//trim(labels(i))//': error ', errors(i), ' limit ', &
                &limits(i)
            write(*,'(a)') trim(line)
            call assert_true(errors(i) <= limits(i), 'oracle_neigh self-check '//trim(labels(i))//' within its limit')
        end do
    end subroutine run_all_oracle_neigh_tests

end module mlxf_oracle_neigh_tester
