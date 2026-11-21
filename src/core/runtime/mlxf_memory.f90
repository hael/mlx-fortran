!@descr: MLX's memory controls: active, peak and cache memory, the cache and memory limits
! Unified memory pages rather than failing when over-subscribed: callers size their work from the peak
! memory and a budget, and set_memory_limit makes evaluation wait and release cached buffers.
module mlxf_memory
use, intrinsic :: iso_c_binding, only: c_int, c_size_t
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_memory, only: mlxc_get_active_memory, mlxc_get_peak_memory, mlxc_reset_peak_memory, mlxc_get_cache_memory, &
                         mlxc_clear_cache, mlxc_set_memory_limit, mlxc_set_cache_limit
use mlxf_error,    only: mlxf_check
use mlxf_device,   only: mlxf_enter
implicit none

public :: mlx_active_memory, mlx_peak_memory, mlx_reset_peak_memory, mlx_cache_memory, mlx_clear_cache
public :: mlx_set_memory_limit, mlx_set_cache_limit
private

abstract interface
    function mlxc_size_query( res ) bind(c)
        import :: c_size_t, c_int
        integer(c_size_t), intent(inout) :: res
        integer(c_int) :: mlxc_size_query
    end function mlxc_size_query
end interface

contains

    ! bytes held by live arrays
    function mlx_active_memory() result(n)
        integer(int64) :: n
        call mlxf_enter('mlx_active_memory')
        n = size_query(mlxc_get_active_memory, 'mlx_active_memory')
    end function mlx_active_memory

    ! the largest active memory since the start or the last reset
    function mlx_peak_memory() result(n)
        integer(int64) :: n
        call mlxf_enter('mlx_peak_memory')
        n = size_query(mlxc_get_peak_memory, 'mlx_peak_memory')
    end function mlx_peak_memory

    subroutine mlx_reset_peak_memory()
        call mlxf_enter('mlx_reset_peak_memory')
        call mlxf_check(mlxc_reset_peak_memory(), 'mlx_reset_peak_memory')
    end subroutine mlx_reset_peak_memory

    ! bytes MLX keeps cached for reuse
    function mlx_cache_memory() result(n)
        integer(int64) :: n
        call mlxf_enter('mlx_cache_memory')
        n = size_query(mlxc_get_cache_memory, 'mlx_cache_memory')
    end function mlx_cache_memory

    subroutine mlx_clear_cache()
        call mlxf_enter('mlx_clear_cache')
        call mlxf_check(mlxc_clear_cache(), 'mlx_clear_cache')
    end subroutine mlx_clear_cache

    ! the memory limit evaluation keeps to by waiting and releasing cached buffers; returns the previous limit
    subroutine mlx_set_memory_limit( bytes, previous, status )
        integer(int64),           intent(in)  :: bytes
        integer(int64), optional, intent(out) :: previous
        integer,        optional, intent(out) :: status
        integer(c_size_t) :: old
        call mlxf_enter('mlx_set_memory_limit')
        old = 0
        call mlxf_check(mlxc_set_memory_limit(old, int(bytes, c_size_t)), 'mlx_set_memory_limit', status)
        if( present(previous) ) previous = int(old, int64)
    end subroutine mlx_set_memory_limit

    ! the cache limit; returns the previous limit
    subroutine mlx_set_cache_limit( bytes, previous )
        integer(int64),           intent(in)  :: bytes
        integer(int64), optional, intent(out) :: previous
        integer(c_size_t) :: old
        call mlxf_enter('mlx_set_cache_limit')
        old = 0
        call mlxf_check(mlxc_set_cache_limit(old, int(bytes, c_size_t)), 'mlx_set_cache_limit')
        if( present(previous) ) previous = int(old, int64)
    end subroutine mlx_set_cache_limit

    function size_query( query, proc ) result(n)
        procedure(mlxc_size_query)   :: query
        character(len=*), intent(in) :: proc
        integer(int64)    :: n
        integer(c_size_t) :: v
        v = 0
        call mlxf_check(query(v), proc)
        n = int(v, int64)
    end function size_query

end module mlxf_memory
