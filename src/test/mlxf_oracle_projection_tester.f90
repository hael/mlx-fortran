!@descr: tests of the projection's host oracles: the self-checks of the direct transforms and of the projection asserted
! The oracles return their checks as (labels, errors, limits) and assert nothing; here each error is held to its
! own limit, before any toy is judged against them. Host only: no device is involved.
module mlxf_oracle_projection_tester
use, intrinsic :: iso_fortran_env, only: real64
use mlxf_oracle_dft,        only: oracle_dft_selfcheck
use mlxf_oracle_projection, only: oracle_proj_selfcheck
use mlxf_test_utils,        only: assert_true
implicit none
private
public :: run_all_oracle_projection_tests

contains

    subroutine run_all_oracle_projection_tests
        character(len=:), allocatable :: labels(:)
        real(real64),     allocatable :: errors(:), limits(:)
        write(*,'(a)') '**** running all oracle_projection tests ****'
        call oracle_dft_selfcheck(labels, errors, limits)
        call assert_checks('oracle_dft', labels, errors, limits)
        call oracle_proj_selfcheck(labels, errors, limits)
        call assert_checks('oracle_projection', labels, errors, limits)
    end subroutine run_all_oracle_projection_tests

    ! every check within its limit, printed with its error
    subroutine assert_checks( oracle, labels, errors, limits )
        character(len=*), intent(in) :: oracle, labels(:)
        real(real64),     intent(in) :: errors(:), limits(:)
        character(len=160) :: line
        integer            :: i
        do i = 1, size(labels)
            write(line,'(a,es10.3,a,es10.3)') '    '//oracle//' '//trim(labels(i))//': error ', errors(i), &
                &' limit ', limits(i)
            write(*,'(a)') trim(line)
            call assert_true(errors(i) <= limits(i), oracle//' self-check '//trim(labels(i))//' within its limit')
        end do
    end subroutine assert_checks

end module mlxf_oracle_projection_tester
