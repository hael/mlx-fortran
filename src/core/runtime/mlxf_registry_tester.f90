!@descr: tests of mlxf_registry: reference counts, serials, the diagnosis of copies made without the defined assignment
module mlxf_registry_tester
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,            only: mlx_array, mlx_from, mlx_is_live, mlx_live_count, mlx_default_device, mlx_set_default_device
use mlxf_registry,   only: registry_stale_releases
use mlxf_array,      only: mlxf_handle
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name
implicit none
private

public :: run_all_registry_tests

! a derived type with an allocatable handle component, copied by intrinsic assignment
type :: bypass_holder
    type(mlx_array), allocatable :: c
end type bypass_holder

contains

    subroutine run_all_registry_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(A)') '**** running all registry tests ****'
        call test_devices(devs)
        if( size(devs) == 0 ) return
        original = mlx_default_device()
        do i = 1, size(devs)
            write(*,'(A)') '  on the '//device_name(devs(i))
            call mlx_set_default_device(devs(i))
            call test_counts
            call test_serials
            call test_diagnosis_component
            call test_diagnosis_source
        end do
        call mlx_set_default_device(original)
        call test_cost
    end subroutine run_all_registry_tests

    subroutine test_counts
        real(real32)    :: x(3)
        type(mlx_array) :: a, b
        integer         :: live0
        logical         :: live_a, live_b
        write(*,'(A)') 'test_counts'
        x     = 1.0_real32
        live0 = mlx_live_count()
        a     = mlx_from(x)
        call assert_int(live0 + 1, mlx_live_count(), 'a new array is one live object')
        b = a
        call assert_int(live0 + 1, mlx_live_count(), 'a copy shares the object')
        call a%kill()
        live_b = mlx_is_live(b)
        live_a = mlx_is_live(a)
        call assert_true(live_b .and. .not. live_a, 'the copy outlives the killed original')
        call b%kill()
        call assert_int(live0, mlx_live_count(), 'the last release frees the object')
        call b%kill()
        call assert_int(live0, mlx_live_count(), 'kill is idempotent')
    end subroutine test_counts

    ! a stale copy keeps naming its object's address; a new object at that address has a new serial
    subroutine test_serials
        real(real32)                 :: x(3)
        type(mlx_array)              :: a, fresh(64)
        type(mlx_array), allocatable :: s
        integer(int64)               :: addr(2)
        integer                      :: i, stale0
        logical                      :: reused
        write(*,'(A)') 'test_serials'
        x      = 2.0_real32
        stale0 = registry_stale_releases()
        a      = mlx_from(x)
        allocate(s, source=a)
        addr = transfer(s, addr)
        call a%kill()
        reused = .false.
        do i = 1, size(fresh)
            fresh(i) = mlx_from(x)
            if( transfer(mlxf_handle(fresh(i), 'test_serials'), 0_int64) == addr(1) )then
                reused = .true.
                exit
            endif
        end do
        write(*,'(A,L1)') '    the freed address was reused by a new object: ', reused
        if( reused ) call assert_true(mlx_is_live(fresh(i)), 'the new object at the old address is live')
        call assert_true(.not. mlx_is_live(s), 'the stale copy is not live, even where its address was reused')
        deallocate(s)
        call assert_int(stale0 + 1, registry_stale_releases(), 'the stale copy''s finalization counts one stale release')
    end subroutine test_serials

    ! an allocatable component copied by intrinsic assignment, the original released: a conforming compiler
    ! copies it by the defined assignment, gfortran 16.2 bitwise; either way the object is freed once. The
    ! stale diagnosis itself is tested through allocate(source=), a bypass on every compiler
    subroutine test_diagnosis_component
        real(real32)        :: x(4)
        type(bypass_holder) :: h1, h2
        integer             :: stale0, live0
        write(*,'(A)') 'test_diagnosis_component'
        x      = 3.0_real32
        stale0 = registry_stale_releases()
        live0  = mlx_live_count()
        allocate(h1%c)
        h1%c = mlx_from(x)
        h2 = h1
        call assert_true(mlx_is_live(h2%c), 'before the release the copy shares the object')
        deallocate(h1%c)
        if( mlx_is_live(h2%c) )then
            ! the compiler applied the defined assignment to the component: the copy holds a counted reference
            write(*,'(A)') '    the allocatable component was copied by the defined assignment'
            call assert_int(live0 + 1, mlx_live_count(), 'a counted copy keeps the object alive')
            deallocate(h2%c)
            call assert_int(stale0, registry_stale_releases(), 'a counted copy''s release is not stale')
        else
            ! gfortran's defect: the component was copied bitwise; the registry diagnoses the copy
            write(*,'(A)') '    the allocatable component was copied bitwise (compiler defect)'
            call assert_int(live0, mlx_live_count(), 'the object was freed once, by its counted owner')
            deallocate(h2%c)
            call assert_int(stale0 + 1, registry_stale_releases(), &
                &'the bitwise copy''s finalization counts one stale release')
        endif
        call assert_int(live0, mlx_live_count(), 'the object is freed exactly once whichever way it was copied')
    end subroutine test_diagnosis_component

    ! the diagnosis gate: allocate(source=) copies without the defined assignment on every compiler
    subroutine test_diagnosis_source
        real(real64)                 :: x(2)
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: s
        integer                      :: stale0
        write(*,'(A)') 'test_diagnosis_source'
        x      = 4.0_real64
        stale0 = registry_stale_releases()
        a      = mlx_from(x)
        allocate(s, source=a)
        call a%kill()
        call assert_true(.not. mlx_is_live(s), 'a copy made by allocate(source=) is not live after the release')
        deallocate(s)
        call assert_int(stale0 + 1, registry_stale_releases(), 'its finalization counts one stale release')
    end subroutine test_diagnosis_source

    ! measured, not asserted: one registry check (mlx_is_live) and one binary operation built, with 1,000
    ! further live objects in the table
    subroutine test_cost
        integer, parameter :: NCHECK = 1000000, NOPS = 20000, NLIVE = 1000
        real(real32)       :: x(4)
        type(mlx_array)    :: a, b, c, others(NLIVE)
        integer(int64)     :: t0, t1, rate
        integer            :: i, nhits
        write(*,'(A)') 'test_cost'
        x = 1.0_real32
        a = mlx_from(x)
        b = mlx_from(x)
        do i = 1, NLIVE
            others(i) = mlx_from(x)
        end do
        nhits = 0
        call system_clock(t0, rate)
        do i = 1, NCHECK
            if( mlx_is_live(a) ) nhits = nhits + 1
        end do
        call system_clock(t1)
        write(*,'(A,F8.1,A)') '    registry check (mlx_is_live): ', 1.e9 * real(t1 - t0) / real(rate) / NCHECK, &
            &' ns per operand'
        call system_clock(t0)
        do i = 1, NOPS
            c = a + b
        end do
        call system_clock(t1)
        write(*,'(A,F8.2,A)') '    c = a + b built (no evaluation): ', 1.e6 * real(t1 - t0) / real(rate) / NOPS, &
            &' us per operation'
        call assert_int(NCHECK, nhits, 'a live array is live at every check')
    end subroutine test_cost

end module mlxf_registry_tester
