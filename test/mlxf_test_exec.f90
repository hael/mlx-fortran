!@descr: the one test executable: mlxf_test_exec test=<unit_area|list> [suite=] [device=], expect_abort(s), guard=
! Exits with status 1 when an assertion or a guard member fails, 2 on a usage error. expect_aborts <group> runs
! every member of a guard group in its own child process (guard=<member>) and accepts only the library's
! hard-error status; expect_abort <member> does the same for one member.
program mlxf_test_exec
use mlxf,               only: MLXF_HARD_ERROR_STATUS
use mlxf_test_registry, only: run_area, list_areas, run_guard, guard_members, guard_need, run_bench
use mlxf_test_utils,    only: report_summary, gpu_present, cpu_only_mlx
implicit none
character(len=256) :: arg, test, suite, guard
integer            :: i
logical            :: found, failed
test  = ''
suite = ''
guard = ''
if( command_argument_count() == 2 )then
    call get_command_argument(1, arg)
    if( trim(arg) == 'expect_aborts' .or. trim(arg) == 'expect_abort' )then
        call get_command_argument(2, test)
        if( trim(arg) == 'expect_aborts' )then
            call expect_aborts(test)
        else
            call expect_abort(test)
        endif
        stop
    endif
endif
! the test first: a benchmark reads its own key=value arguments, in any order
do i = 1, command_argument_count()
    call get_command_argument(i, arg)
    if( index(arg, 'test=') == 1 ) test = arg(6:)
end do
do i = 1, command_argument_count()
    call get_command_argument(i, arg)
    if( index(arg, 'test=') == 1 )then
        cycle
    else if( index(arg, 'suite=') == 1 )then
        suite = arg(7:)
    else if( index(arg, 'guard=') == 1 )then
        guard = arg(7:)
    else if( index(arg, 'device=') /= 1 .and. index(test, 'bench_') /= 1 )then
        write(*,'(A)') 'mlxf_test_exec: unknown argument '//trim(arg)
        call list_areas
        error stop 2
    endif
end do
if( len_trim(guard) > 0 )then
    call run_guard(guard, found)
    if( .not. found )then
        write(*,'(A)') 'mlxf_test_exec: no guard member '//trim(guard)
        error stop 2
    endif
    write(*,'(A)') 'mlxf_test_exec: guard member '//trim(guard)//' returned without stopping'
    error stop 1
endif
if( len_trim(test) == 0 .or. trim(test) == 'list' )then
    call list_areas
    stop
endif
if( index(test, 'bench_') == 1 )then
    call run_bench(test(7:), suite, found)
    if( .not. found )then
        write(*,'(A)') 'mlxf_test_exec: no benchmark '//trim(test)//' with mode "'//trim(suite)//'"'
        call list_areas
        error stop 2
    endif
    call report_summary(failed)
    if( failed ) error stop 1
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

contains

    ! runs every member of a group in a child; each must stop with the library's hard-error status
    subroutine expect_aborts( group )
        character(len=*), intent(in) :: group
        character(len=32), allocatable :: members(:)
        integer                        :: k, nbad, nrun
        members = guard_members(group)
        if( size(members) == 0 )then
            write(*,'(A)') 'mlxf_test_exec: no guard group '//trim(group)
            call list_areas
            error stop 2
        endif
        if( .not. session_allocates() ) return
        nbad = 0
        nrun = 0
        do k = 1, size(members)
            if( .not. member_runs(members(k)) ) cycle
            nrun = nrun + 1
            if( .not. stops_as_guard(members(k)) ) nbad = nbad + 1
        end do
        if( nbad > 0 )then
            write(*,'(A,I0,A,I0,A)') 'FAIL: '//trim(group)//': ', nbad, ' of ', nrun, &
                &' guard members did not stop with the hard-error status'
            error stop 1
        endif
        write(*,'(A,I0,A)') 'PASS: '//trim(group)//': ', nrun, ' guard members stopped with the hard-error status'
    end subroutine expect_aborts

    subroutine expect_abort( member )
        character(len=*), intent(in) :: member
        logical :: ok
        if( .not. session_allocates() ) return
        if( .not. member_runs(member) ) return
        ok = stops_as_guard(member)
        if( .not. ok ) error stop 1
    end subroutine expect_abort

    ! the guard members need a session that allocates: on Metal without a GPU every member would stop for that
    ! reason instead of its own. A CPU-only MLX allocates on the CPU. MLXF_REQUIRE_GPU makes a missing GPU a failure
    logical function session_allocates()
        session_allocates = gpu_present()
        if( session_allocates ) return
#ifdef MLXF_REQUIRE_GPU
        write(*,'(A)') 'FAIL: a GPU device can be opened (MLXF_REQUIRE_GPU): none in this session'
        error stop 1
#else
        session_allocates = cpu_only_mlx()
        if( .not. session_allocates ) write(*,'(A)') 'SKIP: no GPU device in this session; the guard members are not run'
#endif
    end function session_allocates

    ! a member whose fixture needs the GPU skips on a CPU-only MLX; the others run
    logical function member_runs( member )
        character(len=*), intent(in) :: member
        member_runs = trim(guard_need(member)) /= 'gpu'
        if( .not. member_runs ) member_runs = gpu_present()
        if( .not. member_runs ) write(*,'(A)') '    SKIP: GPU-only check on a CPU-only MLX build: '//trim(member)
    end function member_runs

    logical function stops_as_guard( member )
        character(len=*), intent(in) :: member
        character(len=1024) :: arg0
        integer             :: stat, cmdstat
        call get_command_argument(0, arg0)
        stat    = -1
        cmdstat = -1
        call execute_command_line('"'//trim(arg0)//'" guard='//trim(member), exitstat=stat, cmdstat=cmdstat)
        stops_as_guard = cmdstat == 0 .and. stat == MLXF_HARD_ERROR_STATUS
        if( stops_as_guard )then
            write(*,'(A)') '    ok    '//trim(member)//': stopped with the hard-error status'
        else
            write(*,'(A,I0,A,I0)') '    FAIL  '//trim(member)//': command status ', cmdstat, ', exit status ', stat
        endif
    end function stops_as_guard

end program mlxf_test_exec
