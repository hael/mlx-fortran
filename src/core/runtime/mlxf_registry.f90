!@descr: the handle registry: each live MLX object (its ctx address) with a serial and a Fortran-side reference count
! An open-addressing hash table with linear probing and tombstones. A key is the address of an MLX object;
! the serial tells a new object at a reused address from the one a stale copy still names. Not thread-safe:
! the library is called from one thread.
module mlxf_registry
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_error, only: mlxf_report, mlxf_guard_thread
implicit none

public :: mlx_live_count, registry_add, registry_retain, registry_release, registry_is_live, registry_stale_releases
private

integer(int64), parameter :: EMPTY = 0_int64, TOMB = -1_int64
integer,        parameter :: MIN_CAPACITY = 1024

type :: handle_table
    integer(int64), allocatable :: keys(:), serials(:)
    integer,        allocatable :: counts(:)
    integer                     :: nlive = 0, nused = 0, nstale = 0
    integer(int64)              :: last_serial = 0_int64
end type handle_table

! the live MLX objects of the process: the one table the library keeps, like MLX's own allocator state
type(handle_table) :: table

contains

    ! the number of live MLX objects the library holds: equal before and after a loop that leaks nothing
    integer function mlx_live_count()
        call mlxf_guard_thread('mlx_live_count')
        mlx_live_count = table%nlive
    end function mlx_live_count

    ! the releases of handles no longer registered: copies made without the defined assignment
    integer function registry_stale_releases()
        registry_stale_releases = table%nstale
    end function registry_stale_releases

    ! registers a new MLX object with count 1 and returns its serial. A failure (the object registered already,
    ! a table that cannot grow) stops, or with status returns serial 0 and leaves the object unregistered: the
    ! C trampolines of the callbacks take that path, since they must not stop
    function registry_add( key, status ) result(serial)
        integer(int64),    intent(in)  :: key
        integer, optional, intent(out) :: status
        integer(int64) :: serial
        integer        :: slot
        serial = 0_int64
        if( present(status) ) status = 0
        if( .not. allocated(table%keys) )then
            if( .not. rehash(MIN_CAPACITY) )then
                call mlxf_report('registry', 'the handle table could not be allocated', status)
                return
            endif
        endif
        if( 2 * (table%nused + 1) > size(table%keys) )then
            if( .not. rehash(max(MIN_CAPACITY, 4 * table%nlive)) )then
                call mlxf_report('registry', 'the handle table could not grow', status)
                return
            endif
        endif
        if( find(key) > 0 )then
            call mlxf_report('registry', 'an MLX object registered twice', status)
            return
        endif
        slot = free_slot(key)
        if( table%keys(slot) == EMPTY ) table%nused = table%nused + 1
        table%last_serial  = table%last_serial + 1_int64
        serial             = table%last_serial
        table%keys(slot)    = key
        table%serials(slot) = serial
        table%counts(slot)  = 1
        table%nlive         = table%nlive + 1
    end function registry_add

    ! adds one reference to a live object; false when the handle is not live (a stale copy)
    logical function registry_retain( key, serial )
        integer(int64), intent(in) :: key, serial
        integer :: slot
        slot = find(key)
        registry_retain = .false.
        if( slot == 0 ) return
        if( table%serials(slot) /= serial ) return
        table%counts(slot) = table%counts(slot) + 1
        registry_retain = .true.
    end function registry_retain

    ! removes one reference: true when it was the last one (the caller frees the MLX object); a release of
    ! a handle that is not live frees nothing and counts a stale release
    logical function registry_release( key, serial )
        integer(int64), intent(in) :: key, serial
        integer :: slot
        registry_release = .false.
        slot = find(key)
        if( slot > 0 )then
            if( table%serials(slot) /= serial ) slot = 0
        endif
        if( slot == 0 )then
            table%nstale = table%nstale + 1
            return
        endif
        table%counts(slot) = table%counts(slot) - 1
        if( table%counts(slot) > 0 ) return
        table%keys(slot) = TOMB
        table%nlive      = table%nlive - 1
        registry_release = .true.
    end function registry_release

    logical function registry_is_live( key, serial )
        integer(int64), intent(in) :: key, serial
        integer :: slot
        registry_is_live = .false.
        slot = find(key)
        if( slot == 0 ) return
        registry_is_live = table%serials(slot) == serial
    end function registry_is_live

    ! the slot holding key, 0 if none
    integer function find( key )
        integer(int64), intent(in) :: key
        integer :: slot, n
        find = 0
        if( .not. allocated(table%keys) ) return
        slot = home(key)
        do n = 1, size(table%keys)
            if( table%keys(slot) == EMPTY ) return
            if( table%keys(slot) == key )then
                find = slot
                return
            endif
            slot = next_slot(slot)
        end do
    end function find

    ! the first empty or deleted slot on key's probe sequence
    integer function free_slot( key )
        integer(int64), intent(in) :: key
        integer :: slot, n
        slot = home(key)
        do n = 1, size(table%keys)
            if( table%keys(slot) == EMPTY .or. table%keys(slot) == TOMB ) exit
            slot = next_slot(slot)
        end do
        free_slot = slot
    end function free_slot

    ! object addresses are 16-byte aligned: drop the low bits, mix the high ones in
    integer function home( key )
        integer(int64), intent(in) :: key
        home = int(modulo(ieor(shiftr(key, 4), shiftr(key, 19)), int(size(table%keys), int64))) + 1
    end function home

    integer function next_slot( slot )
        integer, intent(in) :: slot
        next_slot = slot + 1
        if( next_slot > size(table%keys) ) next_slot = 1
    end function next_slot

    ! rebuilds the table at a new capacity without its tombstones; false, the table unchanged, when the new
    ! arrays cannot be allocated
    logical function rehash( capacity ) result(ok)
        integer, intent(in) :: capacity
        integer(int64), allocatable :: keys(:), serials(:), new_keys(:), new_serials(:)
        integer,        allocatable :: counts(:), new_counts(:)
        integer                     :: i, slot, st
        allocate(new_keys(capacity), new_serials(capacity), new_counts(capacity), stat=st)
        ok = st == 0
        if( .not. ok ) return
        if( allocated(table%keys) )then
            call move_alloc(table%keys, keys)
            call move_alloc(table%serials, serials)
            call move_alloc(table%counts, counts)
        endif
        call move_alloc(new_keys, table%keys)
        call move_alloc(new_serials, table%serials)
        call move_alloc(new_counts, table%counts)
        table%keys    = EMPTY
        table%serials = 0_int64
        table%counts  = 0
        table%nused   = 0
        if( .not. allocated(keys) ) return
        do i = 1, size(keys)
            if( keys(i) == EMPTY .or. keys(i) == TOMB ) cycle
            slot = free_slot(keys(i))
            table%keys(slot)    = keys(i)
            table%serials(slot) = serials(i)
            table%counts(slot)  = counts(i)
            table%nused         = table%nused + 1
        end do
    end function rehash

end module mlxf_registry
