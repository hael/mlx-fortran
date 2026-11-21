!@descr: tests of mlxf_version: the toolchain links mlx-c and the MLX it loads is one mlx-c 0.8 supports
module mlxf_version_tester
use mlxf_version,    only: mlxf_version_string, mlxf_build_description, mlx_runtime_version, mlxf_runtime_description
use mlxf_test_utils, only: assert_true
implicit none
private

public :: run_all_version_tests

! mlx-c 0.8.0 pins MLX v0.32.4 (FetchContent_Declare in its CMakeLists.txt); a later MLX also serves it
integer, parameter :: MLX_FLOOR(3) = [0, 32, 4]

contains

    subroutine run_all_version_tests
        write(*,'(A)') '**** running all version tests ****'
        call test_runtime_version
        call test_build_description
        call test_runtime_description
    end subroutine run_all_version_tests

    subroutine test_runtime_version
        character(len=:), allocatable :: v
        integer :: triple(3)
        logical :: ok
        write(*,'(A)') 'test_runtime_version'
        v = mlx_runtime_version()
        write(*,'(A)') '    MLX runtime version: '//v
        call parse_version(v, triple, ok)
        call assert_true(ok, 'mlx_version returns major.minor.patch')
        if( ok ) call assert_true(version_at_least(triple, MLX_FLOOR), &
            &'the MLX loaded at run time is v0.32.4 or later, as mlx-c 0.8.0 needs')
    end subroutine test_runtime_version

    subroutine test_build_description
        character(len=:), allocatable :: d
        write(*,'(A)') 'test_build_description'
        d = mlxf_build_description()
        write(*,'(A)') '    '//d
        call assert_true(index(d, 'mlx-fortran '//mlxf_version_string()//' (') == 1, &
            &'the build description starts with the release')
        call assert_true(index(d, 'mlx-c ') > 0, 'the build description names the mlx-c it was configured with')
    end subroutine test_build_description

    subroutine test_runtime_description
        character(len=:), allocatable :: d
        write(*,'(A)') 'test_runtime_description'
        d = mlxf_runtime_description()
        write(*,'(A)') '    '//d
        call assert_true(index(d, 'MLX '//mlx_runtime_version()//';') == 1, &
            &'the runtime description starts with the MLX version loaded')
        call assert_true(index(d, 'MLX_ENABLE_TF32=') > 0, 'the runtime description reports MLX_ENABLE_TF32')
        call assert_true(index(d, 'default device ') > 0 .and. index(d, 'GPU architecture ') > 0, &
            &'the runtime description names the default device and the GPU architecture')
    end subroutine test_runtime_description

    ! the leading major.minor.patch of a version string ("0.32.5.dev20261120+bd2d1fb4" gives 0 32 5)
    subroutine parse_version( v, triple, ok )
        character(len=*), intent(in)  :: v
        integer,          intent(out) :: triple(3)
        logical,          intent(out) :: ok
        integer :: ipart, i, ndigits
        triple  = 0
        ipart   = 1
        ndigits = 0
        ok      = .false.
        do i = 1, len(v)
            if( v(i:i) >= '0' .and. v(i:i) <= '9' )then
                triple(ipart) = 10 * triple(ipart) + (ichar(v(i:i)) - ichar('0'))
                ndigits = ndigits + 1
            else if( v(i:i) == '.' .and. ndigits > 0 .and. ipart < 3 )then
                ipart   = ipart + 1
                ndigits = 0
            else
                exit
            endif
        end do
        ok = ipart == 3 .and. ndigits > 0
    end subroutine parse_version

    logical function version_at_least( v, floor )
        integer, intent(in) :: v(3), floor(3)
        integer :: i
        version_at_least = .true.
        do i = 1, 3
            if( v(i) /= floor(i) )then
                version_at_least = v(i) > floor(i)
                return
            endif
        end do
    end function version_at_least

end module mlxf_version_tester
