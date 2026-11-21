!@descr: errors: the mlx-c error handler, the hard-error stop, checked statuses, the last error and the one-thread guard
! Operators and functions stop on an error MLX reports while building a graph (a program error); checked
! procedures (evaluation, data movement) return a status when the caller passes one. Every stop the library
! makes is error stop MLXF_HARD_ERROR_STATUS, so that a test can tell it from a runtime failure.
module mlxf_error
use, intrinsic :: iso_c_binding, only: c_char, c_int, c_ptr, c_funloc, c_null_ptr, c_null_funptr
use, intrinsic :: iso_fortran_env, only: error_unit
use mlxf_c_error, only: mlxc_set_error_handler
use mlxf_defs,    only: MLXF_HARD_ERROR_STATUS
use mlxf_libc,    only: c_string_copy
implicit none

public :: mlx_last_error, mlxf_fail, mlxf_check, mlxf_report, mlxf_install_error_handler
public :: mlxf_guard_thread
private

! the message of the last error MLX or the library reported; process-global like MLX's own state
character(len=:), allocatable :: last_message

contains

    ! the message of the last error MLX or the library reported (empty if none)
    function mlx_last_error() result(msg)
        character(len=:), allocatable :: msg
        call mlxf_guard_thread('mlx_last_error')
        msg = last_or_empty()
    end function mlx_last_error

    function last_or_empty() result(msg)
        character(len=:), allocatable :: msg
        if( allocated(last_message) )then
            msg = last_message
        else
            msg = ''
        endif
    end function last_or_empty

    ! installs the handler that records MLX's messages instead of printing them and exiting
    subroutine mlxf_install_error_handler()
        call mlxc_set_error_handler(c_funloc(record_mlx_error), c_null_ptr, c_null_funptr)
    end subroutine mlxf_install_error_handler

    ! called by mlx-c from C++: records the message and returns, never stops
    subroutine record_mlx_error( msg, data ) bind(c)
        type(c_ptr), value :: msg, data
        last_message = c_string_copy(msg)
    end subroutine record_mlx_error

    ! stops with the library's hard-error status: mlxf: <procedure>: <message>
    subroutine mlxf_fail( proc, msg )
        character(len=*), intent(in) :: proc, msg
        write(error_unit,'(a)') 'mlxf: '//proc//': '//msg
        flush(error_unit)
        error stop MLXF_HARD_ERROR_STATUS, quiet = .true.
    end subroutine mlxf_fail

    ! an mlx-c status: 0 passes; otherwise the status is returned when the caller asked for it, else a stop
    subroutine mlxf_check( ierr, proc, status )
        integer(c_int),    intent(in)  :: ierr
        character(len=*),  intent(in)  :: proc
        integer, optional, intent(out) :: status
        if( present(status) ) status = int(ierr)
        if( ierr == 0 .or. present(status) ) return
        call mlxf_fail(proc, last_or_empty())
    end subroutine mlxf_check

    ! a failure the library finds itself in a checked procedure: recorded as the last error, then as mlxf_check
    subroutine mlxf_report( proc, msg, status )
        character(len=*),  intent(in)  :: proc, msg
        integer, optional, intent(out) :: status
        last_message = proc//': '//msg
        if( present(status) )then
            status = 1
            return
        endif
        call mlxf_fail(proc, msg)
    end subroutine mlxf_report

    ! graphs are built and evaluated from one thread: refuse a call from inside an OpenMP parallel region
    subroutine mlxf_guard_thread( proc )
        !$ use omp_lib, only: omp_get_level
        character(len=*), intent(in) :: proc
        !$ if( omp_get_level() > 0 ) call mlxf_fail(proc, 'called inside an OpenMP parallel region; graphs are '//&
        !$     &'built and evaluated from one thread')
    end subroutine mlxf_guard_thread

end module mlxf_error
