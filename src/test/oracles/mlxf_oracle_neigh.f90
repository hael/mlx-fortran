!@descr: host oracle of the neighbourhood lists: spiral directions, cones, cells, block orders, SIMPLE's peaks and pool, and the covers' pair counts
! Written from the description of SIMPLE's neighbourhood fill, in double precision, sharing no code with the toy:
! directions on a golden-angle spiral, the angle between unit vectors, a cone's list by exhaustive search (every
! state's references of every direction within it, ascending), the cells by the nearest centre and their
! representatives by the nearest direction, the columns of a batch in either block order, a particle's peaks and
! pooled cells from its drawn distances, and the pairs a cover of blocks computes, padded to a tile plan.
module mlxf_oracle_neigh
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_test_defs, only: NEIGH_ORDERS, polar_list_entries
implicit none
private
public :: oracle_neigh_spiral, oracle_neigh_angle, oracle_neigh_nearest, oracle_neigh_cones, oracle_neigh_cells
public :: oracle_neigh_columns, oracle_neigh_pool, oracle_neigh_cover, oracle_neigh_near_edge, oracle_neigh_selfcheck

contains

    ! n directions on the golden-angle spiral: polar angle acos(1 - (2i - 1)/n), azimuth i times the golden angle
    function oracle_neigh_spiral( n ) result(v)
        integer, intent(in) :: n
        real(real64) :: v(3, n), th, ph
        integer      :: i
        do i = 1, n
            th = acos(1._real64 - real(2 * i - 1, real64) / real(n, real64))
            ph = real(i, real64) * acos(-1._real64) * (3._real64 - sqrt(5._real64))
            v(:, i) = [sin(th) * cos(ph), sin(th) * sin(ph), cos(th)]
        end do
    end function oracle_neigh_spiral

    ! the angle (degrees) between two unit vectors, from their cross and dot products
    pure real(real64) function oracle_neigh_angle( a, b )
        real(real64), intent(in) :: a(3), b(3)
        real(real64) :: c(3)
        c = [a(2) * b(3) - a(3) * b(2), a(3) * b(1) - a(1) * b(3), a(1) * b(2) - a(2) * b(1)]
        oracle_neigh_angle = atan2(sqrt(sum(c**2)), sum(a * b)) * 180._real64 / acos(-1._real64)
    end function oracle_neigh_angle

    ! the index of the vector of set nearest to v, the first of equal angles
    pure integer function oracle_neigh_nearest( v, set )
        real(real64), intent(in) :: v(3), set(:,:)
        real(real64) :: a(size(set, 2))
        integer      :: i
        do i = 1, size(set, 2)
            a(i) = oracle_neigh_angle(v, set(:, i))
        end do
        oracle_neigh_nearest = minloc(a, dim=1)
    end function oracle_neigh_nearest

    ! every column's cone list (ptr, refs): the references (s - 1) nspace + i of every state s whose direction i lies
    ! within cone degrees of the column's previous orientation prevs(:, j), ascending
    function oracle_neigh_cones( dirs, nstates, prevs, cone ) result(lst)
        real(real64), intent(in) :: dirs(:,:), prevs(:,:), cone
        integer,      intent(in) :: nstates
        type(polar_list_entries) :: lst
        integer, allocatable     :: inside(:)
        integer                  :: j, s, i
        allocate(lst%ptr(size(prevs, 2) + 1), lst%refs(0))
        lst%ptr(1) = 1
        do j = 1, size(prevs, 2)
            inside = pack([(i, i = 1, size(dirs, 2))], [(oracle_neigh_angle(prevs(:, j), dirs(:, i)) <= cone, &
                &i = 1, size(dirs, 2))])
            lst%refs       = [lst%refs, [((s - 1) * size(dirs, 2) + inside, s = 1, nstates)]]
            lst%ptr(j + 1) = size(lst%refs) + 1
        end do
    end function oracle_neigh_cones

    ! the cells: each direction's nearest centre, and each centre's nearest direction (its representative)
    subroutine oracle_neigh_cells( dirs, centres, full2sub, sub2full )
        real(real64),         intent(in)  :: dirs(:,:), centres(:,:)
        integer, allocatable, intent(out) :: full2sub(:), sub2full(:)
        integer :: i, c
        full2sub = [(oracle_neigh_nearest(dirs(:, i), centres), i = 1, size(dirs, 2))]
        sub2full = [(oracle_neigh_nearest(centres(:, c), dirs), c = 1, size(centres, 2))]
    end subroutine oracle_neigh_cells

    ! the columns of a batch: the places of the particles of half 1, then of half 2, each half in the given order
    ! (the batch's) or, in SIMPLE's block order, ascending by the cell of the previous direction, the batch's order
    ! among equal cells
    function oracle_neigh_columns( half, cell, order ) result(cols)
        integer, intent(in) :: half(:), cell(:), order
        integer, allocatable :: cols(:), h(:)
        integer              :: k, c, i
        allocate(cols(0))
        do k = 1, 2
            h = pack([(i, i = 1, size(half))], half == k)
            if( order == NEIGH_ORDERS%simple )then
                do c = minval([cell, huge(1)]), maxval([cell, 0])
                    cols = [cols, pack(h, cell(h) == c)]
                end do
            else
                cols = [cols, h]
            endif
        end do
    end function oracle_neigh_columns

    ! SIMPLE's pool of one particle from its drawn distances to every state's representatives (state-major): per
    ! state the min(npeaks, ncells) cells of the smallest distances, ties to the lower cell; the state adds its
    ! peaks when the previous cell is one of them, else all but its last peak and the previous cell; the pool is
    ! the union in the order the states add their cells
    function oracle_neigh_pool( d, ncells, npeaks, prevcell ) result(pool)
        real(real32), intent(in) :: d(:)
        integer,      intent(in) :: ncells, npeaks, prevcell
        integer, allocatable :: pool(:), add(:)
        logical              :: taken(ncells)
        integer              :: k, s, q, c, best
        allocate(pool(0))
        k = min(npeaks, ncells)
        do s = 1, size(d) / ncells
            taken = .false.
            allocate(add(0))
            ! the k smallest by repeated selection: the first cell of the smallest distance among those not taken
            do q = 1, k
                best = 0
                do c = 1, ncells
                    if( taken(c) ) cycle
                    if( best == 0 )then
                        best = c
                    else if( real(d((s - 1) * ncells + c), real64) < real(d((s - 1) * ncells + best), real64) )then
                        best = c
                    endif
                end do
                taken(best) = .true.
                add = [add, best]
            end do
            if( .not. any(add == prevcell) ) add(k) = prevcell
            do q = 1, k
                if( .not. any(pool == add(q)) ) pool = [pool, add(q)]
            end do
            deallocate(add)
        end do
    end function oracle_neigh_pool

    ! the pairs a cover computes: blocks of nb(k) particles against lists of nr(k) references, each padded to whole
    ! tiles of bt particles and rt references (1 and 1: no padding)
    pure integer(int64) function oracle_neigh_cover( nb, nr, bt, rt )
        integer, intent(in) :: nb(:), nr(:), bt, rt
        integer :: k
        oracle_neigh_cover = 0_int64
        do k = 1, size(nb)
            oracle_neigh_cover = oracle_neigh_cover + int(bt * ((nb(k) + bt - 1) / bt), int64) * &
                &int(rt * ((nr(k) + rt - 1) / rt), int64)
        end do
    end function oracle_neigh_cover

    ! the (orientation, direction) pairs whose angle lies within tol degrees of the cone's edge, where float32 and
    ! float64 may list differently
    pure integer function oracle_neigh_near_edge( dirs, prevs, cone, tol )
        real(real64), intent(in) :: dirs(:,:), prevs(:,:), cone, tol
        integer :: j, i
        oracle_neigh_near_edge = 0
        do j = 1, size(prevs, 2)
            do i = 1, size(dirs, 2)
                if( abs(oracle_neigh_angle(prevs(:, j), dirs(:, i)) - cone) <= tol ) &
                    &oracle_neigh_near_edge = oracle_neigh_near_edge + 1
            end do
        end do
    end function oracle_neigh_near_edge

    ! the oracle's own checks as (labels, errors, limits): a cone of 180 degrees lists every direction; the mean
    ! listed fraction of cones of 10, 20 and 40 degrees around 100 axes is (1 - cos)/2 within the spiral's
    ! granularity; every direction is in one cell; two hand-made tables give the pools written beside them (a tie
    ! to the lower cell, a previous cell outside the peaks, then inside them)
    subroutine oracle_neigh_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        integer,      parameter   :: N = 2500, NAX = 100
        real(real64), parameter   :: THETA(3) = [10._real64, 20._real64, 40._real64]
        real(real64), allocatable :: dirs(:,:), axes(:,:), centres(:,:)
        integer,      allocatable :: f2s(:), s2f(:), pool(:)
        type(polar_list_entries)  :: lst
        real(real32)              :: tab(10)
        real(real64)              :: fr
        integer                   :: it, c, nbad
        allocate(character(len=64) :: labels(7))
        allocate(errors(7), limits(7))
        dirs = oracle_neigh_spiral(N)
        axes = oracle_neigh_spiral(NAX)
        lst  = oracle_neigh_cones(dirs, 2, axes(:, 1:3), 180._real64)
        labels(1) = 'a cone of 180 degrees lists every direction'
        errors(1) = real(sum(abs((lst%ptr(2:) - lst%ptr(:3)) - 2 * N)), real64)
        limits(1) = 0._real64
        do it = 1, 3
            lst = oracle_neigh_cones(dirs, 1, axes, THETA(it))
            fr  = real(size(lst%refs), real64) / real(N * NAX, real64)
            write(labels(1 + it), '(a,f4.0,a)') 'mean listed fraction of a cone of ', THETA(it), ' degrees'
            errors(1 + it) = abs(fr - (1._real64 - cos(THETA(it) * acos(-1._real64) / 180._real64)) / 2._real64)
            limits(1 + it) = 2._real64 / real(N, real64)
        end do
        centres = oracle_neigh_spiral(64)
        call oracle_neigh_cells(dirs, centres, f2s, s2f)
        nbad = count(f2s < 1 .or. f2s > 64)
        do c = 1, 64
            if( f2s(s2f(c)) /= c ) nbad = nbad + 1
        end do
        labels(5) = 'every direction in one cell, each representative in its own'
        errors(5) = real(nbad + abs(sum([(count(f2s == c), c = 1, 64)]) - N), real64)
        limits(5) = 0._real64
        ! five cells, two states, two peaks: state 1's tie between cells 2 and 3 goes to 2
        tab  = [0.5, 0.2, 0.2, 0.9, 0.1, 0.3, 0.3, 0.8, 0.8, 0.8]
        pool = oracle_neigh_pool(tab, 5, 2, 4)
        labels(6) = 'the pool of a previous cell outside the peaks is [5, 4, 1]'
        errors(6) = merge(0._real64, 1._real64, size(pool) == 3)
        if( size(pool) == 3 ) errors(6) = real(count(pool /= [5, 4, 1]), real64)
        limits(6) = 0._real64
        pool = oracle_neigh_pool(tab, 5, 2, 2)
        labels(7) = 'the pool of a previous cell among the peaks is [5, 2, 1]'
        errors(7) = merge(0._real64, 1._real64, size(pool) == 3)
        if( size(pool) == 3 ) errors(7) = real(count(pool /= [5, 2, 1]), real64)
        limits(7) = 0._real64
    end subroutine oracle_neigh_selfcheck

end module mlxf_oracle_neigh
