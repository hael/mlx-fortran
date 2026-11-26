!@descr: distributed groups and collectives on the group of one process, and, by name only, a ring of two processes
! A process the gate launches alone gets a group of one: the collectives return their operand, a message has no
! peer and is refused with a status. The sub-suite distributed_ring is for two processes launched through MLX's
! ring backend and is never run by the gate.
module mlxf_distributed_tester
use, intrinsic :: iso_fortran_env, only: real32
use mlxf,            only: mlx_array, mlx_group, mlx_distributed_init, mlx_distributed_is_available, mlx_all_sum, &
                           mlx_all_max, mlx_all_min, mlx_all_gather, mlx_sum_scatter, mlx_send, mlx_recv, &
                           mlx_recv_like, mlx_from, mlx_to, mlx_is_live, mlx_live_count, mlx_last_error, &
                           mlx_set_default_device, mlx_default_device, MLX_DTYPES
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, bits_equal
implicit none
private
public :: run_all_distributed_tests, run_all_distributed_ring_tests

contains

    subroutine run_all_distributed_tests
        integer, allocatable :: devs(:)
        integer              :: i, original, live0
        write(*,'(a)') '**** running all distributed tests ****'
        call test_empty_groups_parallel
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            call test_group_of_one
            call test_refusals
            call assert_int(live0, mlx_live_count(), 'groups and their arrays leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_distributed_tests

    ! copying, killing and finalizing empty groups inside an OpenMP region does not stop
    subroutine test_empty_groups_parallel
        integer :: i, completed(8)
        write(*,'(a)') 'test_empty_groups_parallel'
        completed = 0
        !$omp parallel do num_threads(2) default(shared) private(i) schedule(static) proc_bind(close)
        do i = 1, size(completed)
            call empty_group_scope
            completed(i) = 1
        end do
        !$omp end parallel do
        call assert_true(all(completed == 1), 'empty group assignment, kill and finalization are safe in parallel')
    end subroutine test_empty_groups_parallel

    ! an empty group copied, killed and finalized on leaving the scope
    subroutine empty_group_scope
        type(mlx_group) :: g, copy
        copy = g
        call copy%kill()
    end subroutine empty_group_scope

    ! the group of a process launched alone: size 1, rank 1, and collectives that return their operand
    subroutine test_group_of_one
        type(mlx_group) :: g, copy
        type(mlx_array) :: a, r
        real(real32)    :: x(3, 2), y(3, 2)
        integer         :: live0, st
        write(*,'(a)') 'test_group_of_one'
        x = reshape([1._real32, -2._real32, 3.5_real32, 4._real32, 0.25_real32, -6._real32], [3, 2])
        a = mlx_from(x)
        r = a+a
        live0 = mlx_live_count()
        g = mlx_distributed_init(status=st)
        call assert_int(0, st, 'a process launched alone gets a group without strict')
        call assert_int(live0+1, mlx_live_count(), 'a group is one live object')
        copy = g
        call assert_int(live0+1, mlx_live_count(), 'a copy of a group shares the object')
        call g%kill()
        call g%kill()
        call assert_int(1, copy%size(), 'the group of a process launched alone has one member')
        call assert_int(1, copy%rank(), 'whose rank is 1: ranks are one-based')
        r = mlx_all_sum(a, copy)
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x)), 'mlx_all_sum over a group of one is its operand')
        r = mlx_all_sum(a)
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x)), 'and so it is in MLX''s default group, when none is given')
        r = mlx_all_max(a, copy)
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x)), 'mlx_all_max over a group of one is its operand')
        r = mlx_all_min(a)
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x)), 'mlx_all_min over a group of one is its operand')
        r = mlx_all_gather(a, copy)
        call assert_true(all(r%shape() == [3, 2]), 'mlx_all_gather over a group of one keeps the shape')
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x)), 'and the values')
        r = mlx_sum_scatter(a, status=st)
        call assert_int(0, st, 'mlx_sum_scatter over a group of one returns status zero')
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x)), 'and its operand')
        call copy%kill()
        call assert_int(live0, mlx_live_count(), 'killing the last copy frees the group')
    end subroutine test_group_of_one

    ! what a group of one cannot do is a status: a message, a split, a strict start, an unknown backend
    subroutine test_refusals
        type(mlx_group) :: g, sub, none
        type(mlx_array) :: a, r
        real(real32)    :: x(3)
        integer         :: st, live0
        write(*,'(a)') 'test_refusals'
        x = 1._real32
        a = mlx_from(x)
        g = mlx_distributed_init(status=st)
        live0 = mlx_live_count()
        r = mlx_send(a, 1, g, status=st)
        call assert_true(st /= 0, 'a message to a member of a group of one is refused with a status')
        call assert_true(.not. mlx_is_live(r), 'and returns no array')
        call assert_true(index(mlx_last_error(), 'singleton') > 0, 'MLX says the group is a singleton')
        r = mlx_recv([3], MLX_DTYPES%float32, 1, status=st)
        call assert_true(st /= 0, 'receiving in a group of one is refused with a status')
        r = mlx_recv_like(a, 1, g, status=st)
        call assert_true(st /= 0, 'receiving the like of an array in a group of one is refused with a status')
        sub = g%split(0, status=st)
        call assert_true(st /= 0, 'a group of one cannot be split: a status')
        none = mlx_distributed_init(strict=.true., status=st)
        call assert_true(st /= 0, 'with strict, a process no backend launched gets no group: a status')
        none = mlx_distributed_init('no-such-backend', status=st)
        call assert_true(st /= 0, 'a backend MLX does not know is refused with a status')
        call assert_true(.not. mlx_distributed_is_available('no-such-backend'), 'and is not available')
        call assert_true(mlx_distributed_is_available() .eqv. mlx_distributed_is_available('any'), 'no name asks for any backend')
        call assert_int(live0, mlx_live_count(), 'the refusals leave no live handle')
        r = mlx_all_sum(a, g, status=st)
        call assert_int(0, st, 'MLX remains usable after the refusals')
    end subroutine test_refusals

    ! two processes on one Mac through MLX's ring backend, each started with MLX_RANK and MLX_HOSTFILE: the sum,
    ! the gathering and the scattered sum of a matrix that holds the process's rank, and a message from the first
    ! member to the second. Never run by the gate
    subroutine run_all_distributed_ring_tests
        type(mlx_group) :: g
        type(mlx_array) :: a, r
        real(real32)    :: x(3, 2), y(3, 2), both(3, 4), share(3, 1)
        integer         :: st, rank, i, j
        logical         :: shaped
        write(*,'(a)') '**** running all distributed_ring tests ****'
        g = mlx_distributed_init('ring', strict=.true., status=st)
        call assert_int(0, st, 'the ring backend starts (MLX_RANK and MLX_HOSTFILE are set)')
        if( st /= 0 )then
            write(*,'(a)') '    '//mlx_last_error()
            return
        endif
        call assert_int(2, g%size(), 'the ring has two members')
        rank = g%rank()
        call assert_true(rank == 1 .or. rank == 2, 'this process''s rank is 1 or 2')
        ! element (i, j) of the member of rank r is 100 r + 10 j + i
        do j = 1, 2
            do i = 1, 3
                x(i, j) = real(100*rank+10*j+i, real32)
            end do
        end do
        a = mlx_from(x)
        r = mlx_all_sum(a, g)
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, 2._real32*x+real(100*(3-2*rank), real32))), &
            &'mlx_all_sum is the sum of both members'' matrices')
        r = mlx_all_max(a, g)
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x+real(100*(2-rank), real32))), 'mlx_all_max is the second member''s matrix')
        r = mlx_all_min(a, g)
        call mlx_to(y, r)
        call assert_true(all(bits_equal(y, x-real(100*(rank-1), real32))), 'mlx_all_min is the first member''s matrix')
        r = mlx_all_gather(a, g)
        shaped = all(r%shape() == [3, 4])
        call assert_true(shaped, 'two (3, 2) matrices gather along the last dimension: (3, 4)')
        if( shaped )then
            call mlx_to(both, r)
            call assert_true(all(bits_equal(both(:, 1:2), x-real(100*(rank-1), real32))), 'the first member''s matrix comes first')
            call assert_true(all(bits_equal(both(:, 3:4), x+real(100*(2-rank), real32))), &
                &'the second member''s matrix comes second')
        endif
        r = mlx_sum_scatter(a, g, status=st)
        call assert_int(0, st, 'mlx_sum_scatter returns status zero')
        shaped = st == 0
        if( shaped ) shaped = all(r%shape() == [3, 1])
        call assert_true(shaped, 'each of two members keeps one of the sum''s two columns: (3, 1)')
        if( shaped )then
            call mlx_to(share, r)
            call assert_true(all(bits_equal(share(:, 1), 2._real32*x(:, rank)+real(100*(3-2*rank), real32))), &
                &'the member of rank r keeps column r of the sum')
        endif
        ! the first member sends its matrix, the second receives it
        if( rank == 1 )then
            r = mlx_send(a, 2, g, status=st)
            call assert_int(0, st, 'the first member sends its matrix to the second')
            call mlx_to(y, r)
            call assert_true(all(bits_equal(y, x)), 'and the result of the send is the matrix sent')
        else
            r = mlx_recv_like(a, 1, g, status=st)
            call assert_int(0, st, 'the second member receives the like of its matrix from the first')
            call mlx_to(y, r)
            call assert_true(all(bits_equal(y, x-100._real32)), 'and gets the first member''s matrix')
        endif
    end subroutine run_all_distributed_ring_tests

end module mlxf_distributed_tester
