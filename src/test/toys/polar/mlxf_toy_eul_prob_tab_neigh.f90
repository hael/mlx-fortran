!@descr: the toy neighbourhood driver (test only): a miniature of SIMPLE's eul_prob_tab_neigh that scores each particle's reference list through the polar calculator
! SIMPLE's fill_tab_neigh_range in two of its modes. geom: each particle's list is every state's references whose
! direction lies within the cone around the particle's previous orientation. state: the representatives of every
! state's cells for every particle, then on the host each particle's peaks and pooled cells by SIMPLE's rule from
! the drawn distances, then the members of the pooled cells. Unlike SIMPLE, which scores cones and members per
! pair, the toy covers the lists by blocks on both backends, as SIMPLE's bench does: a block of particles is
! scored against the union of their lists and the pairs no particle asked for are discarded. Blocks are cut in
! the batch's order or in SIMPLE's (by half, then by the cell of the previous direction). The host backend's team
! scores the blocks from inside a parallel region; on the MLX backend one thread queues them, one or two in
! flight. The driver holds no MLX state and imports no MLX name.
module mlxf_toy_eul_prob_tab_neigh
!$ use omp_lib,                  only: omp_get_thread_num
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_test_defs,              only: PFTC_BLOCK_NB, NEIGH_ORDERS, parameters, polar_list_entries
use mlxf_toy_polarft_calc,       only: polarft_calc, keyed_variate
use mlxf_toy_eul_prob_tab,       only: eul_prob_tab
use mlxf_toy_eul_prob_tab_utils, only: cone_view_dist
implicit none

public :: eul_prob_tab_neigh
private

! the fill's statistics (fill_occupancy): listed pairs, computed pairs, blocks, the host step's seconds, the
! representatives' listed and computed pairs, the largest and the mean list of a block (the members' or the cones'),
! the pooled cells per particle and the poolers per cell (of a half)
integer, parameter :: NSTATS = 10

! the modes the toy models, SIMPLE's prob_neigh_mode values
character(len=*), parameter :: MODE_GEOM  = 'geom'
character(len=*), parameter :: MODE_STATE = 'state'

! the work of one fill: jobs, each a set of columns (particles of the batch) scored against one reference list,
! the list's entries going to the representatives' table (stage 1 of state) or to the columns' lists
type :: neigh_jobs
    integer              :: n = 0
    integer, allocatable :: cptr(:)
    integer, allocatable :: cols(:)
    integer, allocatable :: rptr(:)
    integer, allocatable :: refs(:)
end type neigh_jobs

! SIMPLE's driver with the toy's members: the directions (unit vectors, 3 x nspace) and the particles' previous
! orientations (3 x particles in the order of pinds), the subspace (each direction's cell, each cell's
! representative), the mode, the cone (degrees), the peaks per state and the block order; the last fill's listed
! entries (lst), every column's pooled cells (pool_ptr, pool_cells) and its statistics (stats: the computed pairs
! padded to the tile plan on the MLX backend; the host step from the representatives' collection to the first block
! of members). With the dense cover every block is scored against every reference and the lists are selected from
! those entries: the baseline a list route is judged against.
type, extends(eul_prob_tab) :: eul_prob_tab_neigh
    integer                       :: nspace     = 0
    integer                       :: nstates    = 0
    integer                       :: ncells     = 0
    real(real64),     allocatable :: dirs(:,:)
    real(real64),     allocatable :: prev(:,:)
    integer,          allocatable :: full2sub(:)
    integer,          allocatable :: sub2full(:)
    character(len=:), allocatable :: mode
    real(real64)                  :: cone       = 0._real64
    integer                       :: npeaks     = 0
    integer                       :: border     = NEIGH_ORDERS%simple
    type(polar_list_entries)      :: lst
    integer,          allocatable :: pool_ptr(:)
    integer,          allocatable :: pool_cells(:)
    logical                       :: l_dense_cover = .false.
    logical                       :: l_pairs       = .false.
    real(real64)                  :: stats(NSTATS) = 0._real64
  contains
    procedure :: new_neigh_pipeline
    procedure :: fill_tab_range => fill_tab_neigh_range
    procedure :: kill           => kill_neigh
    procedure :: set_eulspace
    procedure :: set_subspace
    procedure :: set_neigh_options
    procedure :: set_neigh_cover
    procedure :: batch_list_entries
    procedure :: batch_pooled_cells
    procedure :: fill_occupancy
end type eul_prob_tab_neigh

contains

    ! the driver of the particles pinds (project indices, all held by the calculator), as eul_prob_tab's, with no
    ! directions, subspace or mode yet; a refusal (message) leaves the driver not existing
    subroutine new_neigh_pipeline( self, params, pftc, pinds )
        class(eul_prob_tab_neigh),  intent(inout) :: self
        type(parameters),           intent(in)    :: params
        type(polarft_calc), target, intent(inout) :: pftc
        integer,                    intent(in)    :: pinds(:)
        call self%kill()
        call self%eul_prob_tab%new_pipeline(params, pftc, pinds)
    end subroutine new_neigh_pipeline

    ! idempotent: the neighbourhood's state, then eul_prob_tab's
    subroutine kill_neigh( self )
        class(eul_prob_tab_neigh), intent(inout) :: self
        if( allocated(self%dirs) ) deallocate(self%dirs)
        if( allocated(self%prev) ) deallocate(self%prev)
        if( allocated(self%full2sub) ) deallocate(self%full2sub)
        if( allocated(self%sub2full) ) deallocate(self%sub2full)
        if( allocated(self%mode) ) deallocate(self%mode)
        if( allocated(self%pool_ptr) ) deallocate(self%pool_ptr)
        if( allocated(self%pool_cells) ) deallocate(self%pool_cells)
        call drop_lists(self%lst)
        self%nspace  = 0
        self%nstates = 0
        self%ncells  = 0
        self%cone    = 0._real64
        self%npeaks  = 0
        self%border  = NEIGH_ORDERS%simple
        self%stats   = 0._real64
        self%l_dense_cover = .false.
        self%l_pairs       = .false.
        call self%eul_prob_tab%kill()
    end subroutine kill_neigh

    subroutine drop_lists( lst )
        type(polar_list_entries), intent(inout) :: lst
        if( allocated(lst%order) ) deallocate(lst%order)
        if( allocated(lst%ptr) ) deallocate(lst%ptr)
        if( allocated(lst%refs) ) deallocate(lst%refs)
        if( allocated(lst%dists) ) deallocate(lst%dists)
        if( allocated(lst%irots) ) deallocate(lst%irots)
        if( allocated(lst%reps) ) deallocate(lst%reps)
        if( allocated(lst%rep_dists) ) deallocate(lst%rep_dists)
        if( allocated(lst%rep_irots) ) deallocate(lst%rep_irots)
    end subroutine drop_lists

    ! the directions (3 x nspace unit vectors; reference (state - 1) nspace + i has direction i, so nspace divides
    ! the calculator's references) and each particle's previous orientation (3 x particles, in the order of pinds)
    subroutine set_eulspace( self, dirs, prev )
        class(eul_prob_tab_neigh), intent(inout) :: self
        real(real64),              intent(in)    :: dirs(:,:), prev(:,:)
        if( .not. self%existence )then
            self%msg = 'eul_prob_tab_neigh%set_eulspace: refused: no driver (new_neigh_pipeline)'
            return
        endif
        if( size(dirs, 1) /= 3 .or. size(dirs, 2) < 1 .or. size(prev, 1) /= 3 .or. size(prev, 2) /= self%nptcls )then
            self%msg = 'eul_prob_tab_neigh%set_eulspace: refused: directions (3, nspace) and orientations (3, particles)'
            return
        endif
        if( mod(self%nrefs, size(dirs, 2)) /= 0 )then
            self%msg = 'eul_prob_tab_neigh%set_eulspace: refused: the references are not states of nspace directions'
            return
        endif
        self%msg     = ''
        self%dirs    = dirs
        self%prev    = prev
        self%nspace  = size(dirs, 2)
        self%nstates = self%nrefs / self%nspace
        if( allocated(self%full2sub) ) deallocate(self%full2sub)
        if( allocated(self%sub2full) ) deallocate(self%sub2full)
        self%ncells = 0
    end subroutine set_eulspace

    ! the subspace: each direction's cell (1..ncells) and each cell's representative direction (ncells), as
    ! srchspace_map gives them
    subroutine set_subspace( self, full2sub, sub2full )
        class(eul_prob_tab_neigh), intent(inout) :: self
        integer,                   intent(in)    :: full2sub(:), sub2full(:)
        if( .not. allocated(self%dirs) )then
            self%msg = 'eul_prob_tab_neigh%set_subspace: refused: no directions (set_eulspace)'
            return
        endif
        if( size(full2sub) /= self%nspace .or. size(sub2full) < 1 )then
            self%msg = 'eul_prob_tab_neigh%set_subspace: refused: one cell per direction and a cell at least'
            return
        endif
        if( any(full2sub < 1 .or. full2sub > size(sub2full)) .or. any(sub2full < 1 .or. sub2full > self%nspace) )then
            self%msg = 'eul_prob_tab_neigh%set_subspace: refused: a cell or a representative out of range'
            return
        endif
        self%msg      = ''
        self%full2sub = full2sub
        self%sub2full = sub2full
        self%ncells   = size(sub2full)
    end subroutine set_subspace

    ! the fill's mode (SIMPLE's prob_neigh_mode: geom or state), the cone of geom (degrees, 0 to 180), the peaks
    ! per state of state and the block order (NEIGH_ORDERS)
    subroutine set_neigh_options( self, mode, cone, npeaks, order )
        class(eul_prob_tab_neigh), intent(inout) :: self
        character(len=*),          intent(in)    :: mode
        real(real64),              intent(in)    :: cone
        integer,                   intent(in)    :: npeaks, order
        if( mode /= MODE_GEOM .and. mode /= MODE_STATE )then
            self%msg = 'eul_prob_tab_neigh%set_neigh_options: refused: an unknown mode (geom or state)'
        else if( .not. (cone >= 0._real64 .and. cone <= 180._real64) )then
            self%msg = 'eul_prob_tab_neigh%set_neigh_options: refused: a cone outside 0 to 180 degrees'
        else if( npeaks < 1 )then
            self%msg = 'eul_prob_tab_neigh%set_neigh_options: refused: a peak at least'
        else if( order /= NEIGH_ORDERS%batch .and. order /= NEIGH_ORDERS%simple )then
            self%msg = 'eul_prob_tab_neigh%set_neigh_options: refused: an unknown block order'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        self%mode   = mode
        self%cone   = cone
        self%npeaks = npeaks
        self%border = order
    end subroutine set_neigh_options

    ! the cover of the following fills: route, the lists' unions (the list route); dense, every reference (the dense
    ! fill followed by the selection of the listed entries); pairs, the listed pairs only (the pair-list kernel, the
    ! cones on the MLX backend's GPU)
    subroutine set_neigh_cover( self, cover )
        class(eul_prob_tab_neigh), intent(inout) :: self
        character(len=*),          intent(in)    :: cover
        if( cover /= 'route' .and. cover /= 'dense' .and. cover /= 'pairs' )then
            self%msg = 'eul_prob_tab_neigh%set_neigh_cover: refused: an unknown cover (route, dense or pairs)'
            return
        endif
        self%msg           = ''
        self%l_dense_cover = cover == 'dense'
        self%l_pairs       = cover == 'pairs'
    end subroutine set_neigh_cover

    ! a job appended (columns, list), the arrays grown by doubling
    pure subroutine push_job( jb, cols, refs )
        type(neigh_jobs), intent(inout) :: jb
        integer,          intent(in)    :: cols(:), refs(:)
        integer, allocatable :: tmp(:)
        integer              :: nc, nr
        if( .not. allocated(jb%cptr) )then
            allocate(jb%cptr(64), jb%rptr(64), jb%cols(1024), jb%refs(4096))
            jb%cptr(1) = 1
            jb%rptr(1) = 1
            jb%n       = 0
        endif
        nc = jb%cptr(jb%n + 1) - 1
        nr = jb%rptr(jb%n + 1) - 1
        if( jb%n + 2 > size(jb%cptr) )then
            allocate(tmp(2 * size(jb%cptr)))
            tmp(1:jb%n + 1) = jb%cptr(1:jb%n + 1)
            call move_alloc(tmp, jb%cptr)
            allocate(tmp(2 * size(jb%rptr)))
            tmp(1:jb%n + 1) = jb%rptr(1:jb%n + 1)
            call move_alloc(tmp, jb%rptr)
        endif
        if( nc + size(cols) > size(jb%cols) )then
            allocate(tmp(max(2 * size(jb%cols), nc + size(cols))))
            tmp(1:nc) = jb%cols(1:nc)
            call move_alloc(tmp, jb%cols)
        endif
        if( nr + size(refs) > size(jb%refs) )then
            allocate(tmp(max(2 * size(jb%refs), nr + size(refs))))
            tmp(1:nr) = jb%refs(1:nr)
            call move_alloc(tmp, jb%refs)
        endif
        jb%cols(nc + 1:nc + size(cols)) = cols
        jb%refs(nr + 1:nr + size(refs)) = refs
        jb%n = jb%n + 1
        jb%cptr(jb%n + 1) = nc + size(cols) + 1
        jb%rptr(jb%n + 1) = nr + size(refs) + 1
    end subroutine push_job

    ! seconds of a monotonic clock
    real(real64) function clock_s()
        integer(int64) :: count, rate
        call system_clock(count, rate)
        clock_s = real(count, real64) / real(rate, real64)
    end function clock_s

    ! the index of the direction nearest to v (the first of equal distances)
    pure integer function nearest_dir( dirs, v )
        real(real64), intent(in) :: dirs(:,:), v(3)
        real(real64) :: d, best
        integer      :: i
        nearest_dir = 1
        best        = huge(best)
        do i = 1, size(dirs, 2)
            d = cone_view_dist(v, dirs(:, i))
            if( d < best )then
                best        = d
                nearest_dir = i
            endif
        end do
    end function nearest_dir

    ! the place of r in the ascending list seg, 0 when it is not there
    pure integer function place_in( seg, r )
        integer, intent(in) :: seg(:), r
        integer :: lo, hi, mid
        place_in = 0
        lo = 1
        hi = size(seg)
        do while( lo <= hi )
            mid = (lo + hi) / 2
            if( seg(mid) == r )then
                place_in = mid
                return
            else if( seg(mid) < r )then
                lo = mid + 1
            else
                hi = mid - 1
            endif
        end do
    end function place_in

    ! SIMPLE's peaks and pool of one particle from its drawn distances to every state's representatives
    ! (state-major, ncells a state): per state the npeaks cells of the smallest distances (an equal distance after
    ! those kept, so the earlier cell wins); the state's peaks when they hold the previous cell, else its best
    ! npeaks - 1 and the previous cell; the union over the states in that order, without repeats
    pure function pool_of( d, ncells, npeaks, prevcell ) result(pool)
        real(real32), intent(in)  :: d(:)
        integer,      intent(in)  :: ncells, npeaks, prevcell
        integer, allocatable :: pool(:)
        real(real32)         :: pd(ncells)
        integer              :: pk(ncells), k, nk, s, c, q, add(ncells), nadd, npool
        allocate(pool(ncells))
        k     = min(npeaks, ncells)
        npool = 0
        do s = 1, size(d) / ncells
            nk = 0
            do c = 1, ncells
                associate( dc => d((s - 1) * ncells + c) )
                    if( nk == k )then
                        if( .not. (dc < pd(k)) ) cycle
                        nk = k - 1
                    endif
                    q = nk + 1
                    do while( q > 1 )
                        if( .not. (pd(q - 1) > dc) ) exit
                        q = q - 1
                    end do
                    pk(q+1:nk+1) = pk(q:nk)
                    pd(q+1:nk+1) = pd(q:nk)
                    pk(q) = c
                    pd(q) = dc
                    nk    = nk + 1
                end associate
            end do
            if( any(pk(1:k) == prevcell) )then
                nadd       = k
                add(1:k)   = pk(1:k)
            else
                nadd           = k
                add(1:k-1)     = pk(1:k-1)
                add(k)         = prevcell
            endif
            do q = 1, nadd
                if( any(pool(1:npool) == add(q)) ) cycle
                npool       = npool + 1
                pool(npool) = add(q)
            end do
        end do
        pool = pool(1:npool)
    end function pool_of

    ! the particles i_first..i_last of pinds in the mode set: the columns in the batch's order (the even half
    ! first), within each half in the block order, cut into blocks of one half; their lists scored by blocks,
    ! each column's listed entries kept; for state the representatives first, the pools on the host, then the
    ! members. A refusal (message) ends the fill.
    subroutine fill_tab_neigh_range( self, i_first, i_last )
        class(eul_prob_tab_neigh), intent(inout) :: self
        integer,                   intent(in)    :: i_first, i_last
        type(neigh_jobs)          :: jobs
        integer,      allocatable :: blocks(:,:), prevcell(:), cptr(:), crefs(:), mptr(:), mrefs(:), fi(:,:)
        real(real32), allocatable :: fd(:,:)
        integer                   :: n, nblocks, j, bt_rt(2)
        logical                   :: l_mlx
        if( .not. self%existence )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: no driver (new_neigh_pipeline)'
            return
        endif
        l_mlx = self%params%l_mlx
        if( i_first < 1 .or. i_last > self%nptcls .or. i_last < i_first )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: the range is not in the driver''s particles'
        else if( .not. allocated(self%temps) )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: no temperatures (set_temps)'
        else if( .not. self%l_keys )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: no keys of the draws (set_draw_keys)'
        else if( .not. allocated(self%dirs) )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: no directions (set_eulspace)'
        else if( .not. allocated(self%mode) )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: no mode (set_neigh_options)'
        else if( self%ncells < 1 .and. (self%mode == MODE_STATE .or. self%border == NEIGH_ORDERS%simple) )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: the state fill and SIMPLE''s block order need '//&
                &'the subspace (set_subspace)'
        else if( self%l_pairs .and. (self%mode /= MODE_GEOM .or. .not. l_mlx) )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: the pair-list kernel serves the cones on the MLX '//&
                &'backend'
        else if( .not. l_mlx .and. self%block_nb > PFTC_BLOCK_NB )then
            self%msg = 'eul_prob_tab_neigh%fill_tab_range: refused: on the host backend a block holds at most '//&
                &'PFTC_BLOCK_NB particles (set_fill_options)'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        if( .not. l_mlx )then
            call self%pftc%check_block_work(self%params%nthr)
            self%msg = self%pftc%message()
            if( len(self%msg) > 0 ) return
        endif
        bt_rt = [1, 1]
        if( l_mlx ) bt_rt = self%pftc%get_tile_plan()
        n = i_last - i_first + 1
        call drop_lists(self%lst)
        if( allocated(self%pool_ptr) ) deallocate(self%pool_ptr)
        if( allocated(self%pool_cells) ) deallocate(self%pool_cells)
        self%stats = 0._real64
        call self%pftc%set_block_options(.false., .false.)
        call cut_blocks
        ! the dense cover's entries of every reference (references, columns)
        if( self%l_dense_cover ) allocate(fd(self%nrefs, n), fi(self%nrefs, n))
        if( self%mode == MODE_GEOM )then
            call cone_lists(cptr, crefs)
            call geom_jobs(jobs)
            call set_lists(cptr, crefs)
            call score_jobs(jobs, .false.)
            if( self%l_dense_cover .and. len(self%msg) == 0 ) call select_lists
        else
            ! the representatives of every state's cells, in the order (state, cell), shared by every block
            call rep_list
            call rep_jobs(jobs)
            allocate(self%lst%rep_dists(size(self%lst%reps), n), self%lst%rep_irots(size(self%lst%reps), n))
            call score_jobs(jobs, .true.)
            if( len(self%msg) > 0 ) return
            self%stats(4) = clock_s()
            if( self%l_dense_cover ) call select_reps
            call pools
            call cell_lists(mptr, mrefs)
            call member_lists(cptr, crefs)
            call set_lists(cptr, crefs)
            if( self%l_dense_cover )then
                call select_lists
                self%stats(4) = clock_s() - self%stats(4)
                return
            endif
            call member_jobs(jobs)
            self%stats(4) = clock_s() - self%stats(4)
            call score_jobs(jobs, .false.)
        endif

      contains

        ! the columns (porder) and the blocks: per half the range's particles in the batch's order, or ordered by
        ! the cell of the previous direction (a stable sort), cut into blocks of at most block_nb
        subroutine cut_blocks
            integer, allocatable :: idx(:), key(:)
            integer              :: i, half, j0, nh, a, b, tmp
            if( allocated(self%porder) ) deallocate(self%porder)
            allocate(self%porder(n), blocks(2, n), prevcell(n), idx(n), key(n))
            j       = 0
            nblocks = 0
            do half = 1, 2
                j0 = j
                do i = i_first, i_last
                    if( self%pftc%ptcl_iseven(self%pinds(i)) .neqv. (half == 1) ) cycle
                    j              = j + 1
                    self%porder(j) = i
                end do
                nh = j - j0
                if( self%ncells > 0 )then
                    ! the cell of each particle's previous direction, by the host team
                    !$omp parallel do num_threads(self%params%nthr) default(shared) private(a) schedule(static) &
                    !$omp proc_bind(close)
                    do a = 1, nh
                        key(a) = self%full2sub(nearest_dir(self%dirs, self%prev(:, self%porder(j0 + a))))
                        idx(a) = self%porder(j0 + a)
                    end do
                    !$omp end parallel do
                    if( self%border == NEIGH_ORDERS%simple )then
                        ! insertion sort by the cell, stable
                        do a = 2, nh
                            b = a
                            do while( b > 1 )
                                if( key(b - 1) <= key(b) ) exit
                                tmp = key(b); key(b) = key(b - 1); key(b - 1) = tmp
                                tmp = idx(b); idx(b) = idx(b - 1); idx(b - 1) = tmp
                                b = b - 1
                            end do
                        end do
                    endif
                    self%porder(j0 + 1:j0 + nh) = idx(1:nh)
                    prevcell(j0 + 1:j0 + nh)    = key(1:nh)
                else
                    prevcell(j0 + 1:j0 + nh) = 0
                endif
                do i = 1, nh, self%block_nb
                    nblocks            = nblocks + 1
                    blocks(:, nblocks) = [j0 + i, j0 + min(i + self%block_nb - 1, nh)]
                end do
            end do
            self%lst%order = self%porder
        end subroutine cut_blocks

        ! every column's cone list: every state's references whose direction lies within the cone of its
        ! previous orientation, ascending
        subroutine cone_lists( ptr, refs )
            integer, allocatable, intent(out) :: ptr(:), refs(:)
            logical, allocatable :: inside(:,:)
            integer              :: jj, i, s, k
            allocate(ptr(n + 1), inside(self%nspace, n))
            ! the directions within each column's cone, by the host team
            !$omp parallel do num_threads(self%params%nthr) default(shared) private(jj, i) schedule(static) &
            !$omp proc_bind(close)
            do jj = 1, n
                do i = 1, self%nspace
                    inside(i, jj) = cone_view_dist(self%prev(:, self%porder(jj)), self%dirs(:, i)) <= self%cone
                end do
            end do
            !$omp end parallel do
            ptr(1) = 1
            do jj = 1, n
                ptr(jj + 1) = ptr(jj) + self%nstates * count(inside(:, jj))
            end do
            allocate(refs(ptr(n + 1) - 1))
            do jj = 1, n
                k = ptr(jj)
                do s = 1, self%nstates
                    do i = 1, self%nspace
                        if( .not. inside(i, jj) ) cycle
                        refs(k) = (s - 1) * self%nspace + i
                        k       = k + 1
                    end do
                end do
            end do
        end subroutine cone_lists

        ! the columns' lists of the fill with room for their entries
        subroutine set_lists( ptr, refs )
            integer, intent(in) :: ptr(:), refs(:)
            self%lst%ptr  = ptr
            self%lst%refs = refs
            allocate(self%lst%dists(size(refs)), self%lst%irots(size(refs)))
            self%lst%dists = huge(1._real32)
            self%lst%irots = 1
            self%stats(1)  = self%stats(1) + real(size(refs), real64)
        end subroutine set_lists

        ! the dense cover: every column's listed entries selected from its entries of every reference
        subroutine select_lists
            integer :: jj, k
            do jj = 1, n
                do k = self%lst%ptr(jj), self%lst%ptr(jj + 1) - 1
                    self%lst%dists(k) = fd(self%lst%refs(k), jj)
                    self%lst%irots(k) = fi(self%lst%refs(k), jj)
                end do
            end do
        end subroutine select_lists

        ! the dense cover: the representatives' entries selected
        subroutine select_reps
            integer :: jj
            do jj = 1, n
                self%lst%rep_dists(:, jj) = fd(self%lst%reps, jj)
                self%lst%rep_irots(:, jj) = fi(self%lst%reps, jj)
            end do
        end subroutine select_reps

        ! every reference in order, the dense cover's list
        function every_ref() result(refs)
            integer :: refs(self%nrefs), r
            refs = [(r, r = 1, self%nrefs)]
        end function every_ref

        ! geom: a job per block, its list the union of its columns' cone lists (every reference with the dense cover)
        subroutine geom_jobs( jb )
            type(neigh_jobs), intent(out) :: jb
            logical :: mark(self%nrefs)
            integer :: kb, jj, r
            if( self%l_pairs )then
                ! the pair list: a job per half that lists a pair, its columns' lists one after the other
                jj = count([(in_half(r, 1), r = 1, n)])
                if( cptr(jj + 1) > cptr(1) ) call push_job(jb, [(r, r = 1, jj)], crefs(cptr(1):cptr(jj + 1) - 1))
                if( cptr(n + 1) > cptr(jj + 1) ) call push_job(jb, [(r, r = jj + 1, n)], &
                    &crefs(cptr(jj + 1):cptr(n + 1) - 1))
                return
            endif
            do kb = 1, nblocks
                mark = .false.
                do jj = blocks(1, kb), blocks(2, kb)
                    mark(crefs(cptr(jj):cptr(jj + 1) - 1)) = .true.
                end do
                if( self%l_dense_cover )then
                    call push_job(jb, [(jj, jj = blocks(1, kb), blocks(2, kb))], every_ref())
                else if( any(mark) )then
                    call push_job(jb, [(jj, jj = blocks(1, kb), blocks(2, kb))], pack([(r, r = 1, self%nrefs)], mark))
                endif
            end do
        end subroutine geom_jobs

        ! the representatives' list (state, cell), and its listed pairs
        subroutine rep_list
            integer :: s, c
            self%lst%reps = [((((s - 1) * self%nspace + self%sub2full(c)), c = 1, self%ncells), s = 1, self%nstates)]
            self%stats(1) = self%stats(1) + real(size(self%lst%reps), real64) * real(n, real64)
            self%stats(5) = real(size(self%lst%reps), real64) * real(n, real64)
        end subroutine rep_list

        ! state, first stage: a job per block, its list the representatives (every reference with the dense cover)
        subroutine rep_jobs( jb )
            type(neigh_jobs), intent(out) :: jb
            integer :: kb, jj
            do kb = 1, nblocks
                if( self%l_dense_cover )then
                    call push_job(jb, [(jj, jj = blocks(1, kb), blocks(2, kb))], every_ref())
                else
                    call push_job(jb, [(jj, jj = blocks(1, kb), blocks(2, kb))], self%lst%reps)
                endif
            end do
        end subroutine rep_jobs

        ! the host step: every column's pooled cells by SIMPLE's rule from its drawn representatives' distances;
        ! the pooled cells per column and the poolers per cell of a half that has one
        subroutine pools
            integer, allocatable :: pool(:)
            integer              :: npool, jj, c, half, npairs, ncells_used
            allocate(self%pool_ptr(n + 1), self%pool_cells(n * self%ncells))
            self%pool_ptr(1) = 1
            do jj = 1, n
                pool  = pool_of(self%lst%rep_dists(:, jj), self%ncells, self%npeaks, prevcell(jj))
                npool = size(pool)
                self%pool_cells(self%pool_ptr(jj):self%pool_ptr(jj) + npool - 1) = pool(1:npool)
                self%pool_ptr(jj + 1) = self%pool_ptr(jj) + npool
            end do
            self%pool_cells = self%pool_cells(1:self%pool_ptr(n + 1) - 1)
            npairs      = size(self%pool_cells)
            ncells_used = 0
            do half = 1, 2
                do c = 1, self%ncells
                    if( any([(pooled(jj, c) .and. in_half(jj, half), jj = 1, n)]) ) ncells_used = ncells_used + 1
                end do
            end do
            self%stats(9)  = real(npairs, real64) / real(n, real64)
            self%stats(10) = real(npairs, real64) / real(max(1, ncells_used), real64)
        end subroutine pools

        logical function in_half( jj, half )
            integer, intent(in) :: jj, half
            in_half = self%pftc%ptcl_iseven(self%pinds(self%porder(jj))) .eqv. (half == 1)
        end function in_half

        ! every cell's members of every state, ascending (cell c's are refs(ptr(c):ptr(c+1)-1))
        subroutine cell_lists( ptr, refs )
            integer, allocatable, intent(out) :: ptr(:), refs(:)
            integer :: c, r, k, cnt(self%ncells)
            cnt = 0
            do r = 1, self%nrefs
                c      = self%full2sub(mod(r - 1, self%nspace) + 1)
                cnt(c) = cnt(c) + 1
            end do
            allocate(ptr(self%ncells + 1), refs(self%nrefs))
            ptr(1) = 1
            do c = 1, self%ncells
                ptr(c + 1) = ptr(c) + cnt(c)
            end do
            cnt = 0
            do r = 1, self%nrefs
                c      = self%full2sub(mod(r - 1, self%nspace) + 1)
                k      = ptr(c) + cnt(c)
                refs(k) = r
                cnt(c) = cnt(c) + 1
            end do
        end subroutine cell_lists

        ! every column's member list: the members of every state of its pooled cells, ascending
        subroutine member_lists( ptr, refs )
            integer, allocatable, intent(out) :: ptr(:), refs(:)
            logical :: mark(self%nrefs)
            integer :: jj, r, k, q, c
            allocate(ptr(n + 1))
            ptr(1) = 1
            do jj = 1, n
                k = 0
                do q = self%pool_ptr(jj), self%pool_ptr(jj + 1) - 1
                    c = self%pool_cells(q)
                    k = k + mptr(c + 1) - mptr(c)
                end do
                ptr(jj + 1) = ptr(jj) + k
            end do
            allocate(refs(ptr(n + 1) - 1))
            mark = .false.
            do jj = 1, n
                do q = self%pool_ptr(jj), self%pool_ptr(jj + 1) - 1
                    c = self%pool_cells(q)
                    mark(mrefs(mptr(c):mptr(c + 1) - 1)) = .true.
                end do
                k = ptr(jj)
                do r = 1, self%nrefs
                    if( .not. mark(r) ) cycle
                    refs(k) = r
                    k       = k + 1
                    mark(r) = .false.
                end do
            end do
        end subroutine member_lists

        ! state, second stage. On the MLX backend cell by cell: the columns of each half that pooled the cell, in
        ! blocks of block_nb, against the cell's members of every state; on the host backend per block and cell
        ! (SIMPLE's bench): the block's columns that pooled the cell
        subroutine member_jobs( jb )
            type(neigh_jobs), intent(out) :: jb
            integer, allocatable :: cols(:)
            integer              :: half, c, kb, jj, k
            if( l_mlx )then
                do half = 1, 2
                    do c = 1, self%ncells
                        cols = pack([(jj, jj = 1, n)], [(pooled(jj, c) .and. in_half(jj, half), jj = 1, n)])
                        do k = 1, size(cols), self%block_nb
                            call push_job(jb, cols(k:min(k + self%block_nb - 1, size(cols))), mrefs(mptr(c):mptr(c + 1) - 1))
                        end do
                    end do
                end do
            else
                do kb = 1, nblocks
                    do c = 1, self%ncells
                        cols = pack([(jj, jj = blocks(1, kb), blocks(2, kb))], [(pooled(jj, c), jj = blocks(1, kb), &
                            &blocks(2, kb))])
                        if( size(cols) == 0 ) cycle
                        call push_job(jb, cols, mrefs(mptr(c):mptr(c + 1) - 1))
                    end do
                end do
            endif
        end subroutine member_jobs

        logical function pooled( jj, c )
            integer, intent(in) :: jj, c
            pooled = any(self%pool_cells(self%pool_ptr(jj):self%pool_ptr(jj + 1) - 1) == c)
        end function pooled

        ! the jobs scored: on the MLX backend queued one or two in flight, each with its list and the keyed
        ! variates; on the host backend by the team, one job a thread; each job's entries to the representatives'
        ! table (rep) or to its columns' lists, the pairs no column asked for discarded
        subroutine score_jobs( jb, rep )
            type(neigh_jobs), intent(in) :: jb
            logical,          intent(in) :: rep
            real(real64) :: comp
            integer      :: k, nr
            do k = 1, jb%n
                nr   = jb%rptr(k + 1) - jb%rptr(k)
                comp = real(padded(jb%cptr(k + 1) - jb%cptr(k), bt_rt(1)) * padded(nr, bt_rt(2)), real64)
                ! the pair-list kernel computes the listed pairs only
                if( self%l_pairs ) comp = real(nr, real64)
                self%stats(2) = self%stats(2) + comp
                if( rep )then
                    self%stats(6) = self%stats(6) + comp
                else
                    self%stats(7) = max(self%stats(7), real(nr, real64))
                    self%stats(8) = self%stats(8) + real(nr, real64) / real(max(1, jb%n), real64)
                endif
            end do
            self%stats(3) = self%stats(3) + real(jb%n, real64)
            if( l_mlx )then
                do k = 1, jb%n
                    call submit_job(jb, k, slot_of(k))
                    if( len(self%msg) > 0 ) return
                    if( self%nslots == 2 .and. k > 1 ) call collect_job(jb, k - 1, rep)
                    if( self%nslots == 1 ) call collect_job(jb, k, rep)
                    if( len(self%msg) > 0 ) return
                end do
                if( self%nslots == 2 .and. jb%n > 0 ) call collect_job(jb, jb%n, rep)
            else
                call host_jobs(jb, rep)
            endif
        end subroutine score_jobs

        pure integer(int64) function padded( m, t )
            integer, intent(in) :: m, t
            padded = int((m + t - 1) / t, int64) * int(t, int64)
        end function padded

        pure integer function slot_of( k )
            integer, intent(in) :: k
            slot_of = 1
            if( self%nslots == 2 ) slot_of = mod(k - 1, 2) + 1
        end function slot_of

        ! job k queued in slot: its list, its columns' particles and temperatures, the variates keyed by the
        ! particle and the reference's full index, made by the host team
        subroutine submit_job( jb, k, slot )
            type(neigh_jobs), intent(in) :: jb
            integer,          intent(in) :: k, slot
            real(real32), allocatable :: u(:,:), temps_b(:)
            integer,      allocatable :: iptcls_b(:), refs(:)
            integer                   :: b, r, nb, nr
            nb       = jb%cptr(k + 1) - jb%cptr(k)
            nr       = jb%rptr(k + 1) - jb%rptr(k)
            refs     = jb%refs(jb%rptr(k):jb%rptr(k + 1) - 1)
            iptcls_b = self%pinds(self%porder(jb%cols(jb%cptr(k):jb%cptr(k + 1) - 1)))
            temps_b  = self%temps(self%porder(jb%cols(jb%cptr(k):jb%cptr(k + 1) - 1)))
            if( self%l_pairs )then
                call submit_pairs(jb, k, slot, refs)
                return
            endif
            allocate(u(nr, nb))
            !$omp parallel do num_threads(self%params%nthr) default(shared) private(b, r) schedule(static) proc_bind(close)
            do b = 1, nb
                do r = 1, nr
                    u(r, b) = real(keyed_variate(self%rnd_seed, iptcls_b(b), self%ref_full(refs(r))), real32)
                end do
            end do
            !$omp end parallel do
            call self%pftc%set_block_refs(refs)
            if( len(self%pftc%message()) == 0 ) call self%pftc%set_block_variates(u)
            if( len(self%pftc%message()) == 0 ) call self%pftc%submit_block(slot, nb, iptcls_b, temps_b)
            self%msg = self%pftc%message()
        end subroutine submit_job

        ! a pair-list job queued: its pointers into the concatenated lists, each pair's variate keyed by the
        ! particle and the reference's full index, made by the host team
        subroutine submit_pairs( jb, k, slot, refs )
            type(neigh_jobs), intent(in) :: jb
            integer,          intent(in) :: k, slot, refs(:)
            real(real32), allocatable :: u(:,:), temps_b(:)
            integer,      allocatable :: iptcls_b(:)
            integer,      allocatable :: ptrl(:)
            integer                   :: b, q, nb, c0
            iptcls_b = self%pinds(self%porder(jb%cols(jb%cptr(k):jb%cptr(k + 1) - 1)))
            temps_b  = self%temps(self%porder(jb%cols(jb%cptr(k):jb%cptr(k + 1) - 1)))
            nb   = size(iptcls_b)
            c0   = jb%cols(jb%cptr(k))
            ptrl = cptr(c0:c0 + nb) - cptr(c0) + 1
            allocate(u(1, size(refs)))
            !$omp parallel do num_threads(self%params%nthr) default(shared) private(b, q) schedule(static) proc_bind(close)
            do b = 1, nb
                do q = ptrl(b), ptrl(b + 1) - 1
                    u(1, q) = real(keyed_variate(self%rnd_seed, iptcls_b(b), self%ref_full(refs(q))), real32)
                end do
            end do
            !$omp end parallel do
            call self%pftc%set_block_pairs(ptrl, refs)
            if( len(self%pftc%message()) == 0 ) call self%pftc%set_block_variates(u)
            if( len(self%pftc%message()) == 0 ) call self%pftc%submit_block(slot, nb, iptcls_b, temps_b)
            self%msg = self%pftc%message()
        end subroutine submit_pairs

        ! job k collected and its entries placed
        subroutine collect_job( jb, k, rep )
            type(neigh_jobs), intent(in) :: jb
            integer,          intent(in) :: k
            logical,          intent(in) :: rep
            real(real32), allocatable :: d(:,:)
            integer,      allocatable :: ir(:,:)
            integer                   :: nb, nr, q0
            nb = jb%cptr(k + 1) - jb%cptr(k)
            nr = jb%rptr(k + 1) - jb%rptr(k)
            if( self%l_pairs )then
                ! the pair list's entries (1, pairs) are the columns' lists one after the other
                allocate(d(1, nr), ir(1, nr))
                call self%pftc%collect_block(slot_of(k), d, ir)
                self%msg = self%pftc%message()
                if( len(self%msg) > 0 ) return
                q0 = self%lst%ptr(jb%cols(jb%cptr(k)))
                self%lst%dists(q0:q0 + nr - 1) = d(1, :)
                self%lst%irots(q0:q0 + nr - 1) = ir(1, :)
                return
            endif
            allocate(d(nr, nb), ir(nr, nb))
            call self%pftc%collect_block(slot_of(k), d, ir)
            self%msg = self%pftc%message()
            if( len(self%msg) > 0 ) return
            call place(jb, k, rep, d, ir)
        end subroutine collect_job

        ! the host backend: every job by one thread of the team, into that thread's buffers allocated before the
        ! region, its entries placed in its columns' lists (no two jobs write one entry)
        subroutine host_jobs( jb, rep )
            type(neigh_jobs), intent(in) :: jb
            logical,          intent(in) :: rep
            real(real32), allocatable :: bd(:,:)
            integer,      allocatable :: bi(:,:)
            integer                   :: k, ithr, mx, kk
            mx = 1
            do kk = 1, jb%n
                mx = max(mx, (jb%cptr(kk + 1) - jb%cptr(kk)) * (jb%rptr(kk + 1) - jb%rptr(kk)))
            end do
            allocate(bd(mx, self%params%nthr), bi(mx, self%params%nthr))
            !$omp parallel do num_threads(self%params%nthr) default(shared) private(k, ithr) schedule(dynamic) &
            !$omp proc_bind(close)
            do k = 1, jb%n
                ithr = 1
                !$ ithr = omp_get_thread_num() + 1
                call host_job(jb, k, rep, bd(:, ithr), bi(:, ithr))
            end do
            !$omp end parallel do
        end subroutine host_jobs

        ! one job on the calling thread: no allocation
        subroutine host_job( jb, k, rep, bd, bi )
            type(neigh_jobs), intent(in)    :: jb
            integer,          intent(in)    :: k
            logical,          intent(in)    :: rep
            real(real32),     intent(inout) :: bd(:)
            integer,          intent(inout) :: bi(:)
            real(real32) :: temps_b(PFTC_BLOCK_NB)
            integer      :: iptcls_b(PFTC_BLOCK_NB), nb, nr, b
            nb = jb%cptr(k + 1) - jb%cptr(k)
            nr = jb%rptr(k + 1) - jb%rptr(k)
            do b = 1, nb
                iptcls_b(b) = self%pinds(self%porder(jb%cols(jb%cptr(k) + b - 1)))
                temps_b(b)  = self%temps(self%porder(jb%cols(jb%cptr(k) + b - 1)))
            end do
            call self%pftc%score_block_posterior(nb, iptcls_b(1:nb), nr, jb%refs(jb%rptr(k):jb%rptr(k + 1) - 1), &
                &temps_b(1:nb), bd(1:nr * nb), bi(1:nr * nb))
            call place(jb, k, rep, bd(1:nr * nb), bi(1:nr * nb))
        end subroutine host_job

        ! job k's entries (list, columns; in array element order) to the representatives' table or to its columns' lists
        subroutine place( jb, k, rep, d, ir )
            type(neigh_jobs), intent(in) :: jb
            integer,          intent(in) :: k
            logical,          intent(in) :: rep
            real(real32),     intent(in) :: d(*)
            integer,          intent(in) :: ir(*)
            integer :: nr, b, r, jj, p, e
            nr = jb%rptr(k + 1) - jb%rptr(k)
            do b = 1, jb%cptr(k + 1) - jb%cptr(k)
                jj = jb%cols(jb%cptr(k) + b - 1)
                do r = 1, nr
                    e = (b - 1) * nr + r
                    if( self%l_dense_cover )then
                        fd(jb%refs(jb%rptr(k) + r - 1), jj) = d(e)
                        fi(jb%refs(jb%rptr(k) + r - 1), jj) = ir(e)
                    else if( rep )then
                        self%lst%rep_dists(r, jj) = d(e)
                        self%lst%rep_irots(r, jj) = ir(e)
                    else
                        p = place_in(self%lst%refs(self%lst%ptr(jj):self%lst%ptr(jj + 1) - 1), jb%refs(jb%rptr(k) + r - 1))
                        if( p == 0 ) cycle
                        self%lst%dists(self%lst%ptr(jj) + p - 1) = d(e)
                        self%lst%irots(self%lst%ptr(jj) + p - 1) = ir(e)
                    endif
                end do
            end do
        end subroutine place

    end subroutine fill_tab_neigh_range

    ! hands over the last fill's listed entries (see polar_list_entries)
    subroutine batch_list_entries( self, lst )
        class(eul_prob_tab_neigh), intent(inout) :: self
        type(polar_list_entries),  intent(out)   :: lst
        self%msg = ''
        if( allocated(self%lst%order) ) call move_alloc(self%lst%order, lst%order)
        if( allocated(self%lst%ptr) ) call move_alloc(self%lst%ptr, lst%ptr)
        if( allocated(self%lst%refs) ) call move_alloc(self%lst%refs, lst%refs)
        if( allocated(self%lst%dists) ) call move_alloc(self%lst%dists, lst%dists)
        if( allocated(self%lst%irots) ) call move_alloc(self%lst%irots, lst%irots)
        if( allocated(self%lst%reps) ) call move_alloc(self%lst%reps, lst%reps)
        if( allocated(self%lst%rep_dists) ) call move_alloc(self%lst%rep_dists, lst%rep_dists)
        if( allocated(self%lst%rep_irots) ) call move_alloc(self%lst%rep_irots, lst%rep_irots)
    end subroutine batch_list_entries

    ! the last state fill's pooled cells: column j's are cells(ptr(j):ptr(j+1)-1), in the rule's order
    subroutine batch_pooled_cells( self, ptr, cells )
        class(eul_prob_tab_neigh), intent(inout) :: self
        integer, allocatable,      intent(out)   :: ptr(:), cells(:)
        self%msg = ''
        if( allocated(self%pool_ptr) ) ptr = self%pool_ptr
        if( allocated(self%pool_cells) ) cells = self%pool_cells
    end subroutine batch_pooled_cells

    ! the last fill's statistics: listed pairs, computed pairs (on the MLX backend padded to the tile plan), blocks
    ! scored, the host step's seconds, the representatives' listed and computed pairs, the largest and the mean
    ! list of a block (cones' unions or a cell's members), the pooled cells per particle and the poolers per cell
    pure function fill_occupancy( self ) result(occ)
        class(eul_prob_tab_neigh), intent(in) :: self
        real(real64) :: occ(NSTATS)
        occ = self%stats
    end function fill_occupancy

end module mlxf_toy_eul_prob_tab_neigh
