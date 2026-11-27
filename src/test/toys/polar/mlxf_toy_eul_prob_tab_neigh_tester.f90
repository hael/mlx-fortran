!@descr: tests of the polar toy's reference lists: the calculator's list route against the memo oracle and the dense route, its repeatability and refusals
! The fixture is mlxf_polarft_host_fixture's (40 references, 44 particles, tiles of 8 particles and 16 references
! on the MLX backend, so lists fill partial tiles both ways). A block scored against a list of references is held
! (a) to the memo oracle's rows of the same global pairs and to the draw on its own rows, within bounds calibrated
! on seed 1 on the CPU device; (b) to the dense route's entries of the same pairs bit for bit on the host backend
! and on Apple's CPU device (cpu_matmul_shape_exact); (c) on the GPU and on another CPU device to the dense route's
! rows within the tail's row tolerance and rotation count. Entries are the same bits over repeats, the synchronous and queued calls, one or two slots in flight and
! host teams; each configuration's digest is written for the comparison of two invocations.
module mlxf_toy_eul_prob_tab_neigh_tester
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf,                        only: mlx_set_default_device, mlx_default_device, MLX_DEVICES
use mlxf_test_defs,              only: PH_PFTSZ, PH_NK, PH_NREFS, PH_NSPACE, PH_NPTCLS, PH_PREV_SPAN, POLAR_ROW_FACTOR, &
                                       POLAR_FIXTURE_ROT_Q, POLAR_SEED_CALIBRATION, POLAR_NEIGH_ERR_CPU, &
                                       POLAR_NEIGH_ROT_CPU, POLAR_NEIGH_PAIR_ROW_TOL, POLAR_NEIGH_PAIR_ROT, &
                                       POLARFT_TAILS, POLARFT_TAIL_ROW_TOL, POLARFT_TAIL_ROT_FIX, PH_NCELLS, PH_CONES, &
                                       PH_NPEAKS, NEIGH_ORDERS, POLAR_DIST_VALID, POLAR_DIST_INVALID, POLAR_DIST_MAX, &
                                       POLAR_VALID_MARGIN, parameters, polar_table_refs, polar_table_block, &
                                       polar_table_entries, polar_row_check, polarft_host_fixture, polarft_host_table, &
                                       polarft_neigh_table, polar_list_entries
use mlxf_toy_polarft_calc,       only: polarft_calc
use mlxf_toy_srchspace_map,      only: srchspace_map
use mlxf_toy_eul_prob_tab_utils, only: cone_view_dist
use mlxf_polarft_host_fixture,   only: make_polarft_host_fixture, polarft_host_half, polarft_host_calc, &
                                       fill_polarft_host_table, polarft_host_centres, fill_polarft_neigh_table, &
                                       write_polarft_neigh_table
use mlxf_oracle_polar,           only: polar_full_ring, polar_dft_matrix, polar_dft_bins, polar_keyed_u, &
                                       polar_compare_rows, polar_draws_off, polar_memo_rows, polar_draw_row
use mlxf_oracle_neigh,           only: oracle_neigh_nearest, oracle_neigh_cones, oracle_neigh_cells, &
                                       oracle_neigh_columns, oracle_neigh_pool, oracle_neigh_cover, &
                                       oracle_neigh_near_edge
use mlxf_test_reduce,            only: nan_maxval, nan_max
use mlxf_test_utils,             only: assert_true, assert_int, device_name, bits_equal, test_devices, digest_bits, &
                                       cpu_matmul_shape_exact
implicit none
private
public :: run_all_eul_prob_tab_neigh_tests

integer, parameter :: NROTS = 2 * PH_PFTSZ
integer, parameter :: NBINS = PH_PFTSZ + 1
! the fixture's seeds: the calibration's, then the judged ones
integer, parameter :: SEEDS(3) = [1, 2, 3]
! the host team the entries are compared across
integer, parameter :: NTEAM = 24
! the digest's start
integer(int64), parameter :: DIGEST0 = 88172645463325252_int64
! the lists: one reference, two, seven, a sparse list shared by blocks, 23 (two list tiles, the second partial)
! and every reference in order (the dense block)
integer, parameter :: NLISTS = 6
integer, parameter :: LIST_N(NLISTS) = [1, 2, 7, 8, 23, PH_NREFS]
! the blocks: five particles of the even half (one invalid, a partial particle tile) and twelve of the odd half
! (two particle tiles, the second partial)
integer, parameter :: NBLOCKS = 2
integer, parameter :: BLOCK_N(NBLOCKS) = [5, 12]
! the configurations: the host backend, then the MLX backend's compiled and fused tails
integer, parameter :: CFG_HOST = 1, CFG_GRAPH = 2, CFG_METAL = 3

! a block to score: its backend, particles (project indices of one half) and reference list
type :: scored_block
    logical              :: l_mlx = .false.
    integer, allocatable :: pids(:)
    integer, allocatable :: irefs(:)
end type scored_block

! one configuration's results over the blocks and lists: the worst errors and counts of the gates
type :: neigh_tally
    real(real64) :: err_oracle = 0._real64
    integer      :: rot_oracle = 0
    real(real64) :: err_full   = 0._real64
    integer      :: rot_full   = 0
    real(real64) :: err_dense  = 0._real64
    integer      :: rot_dense  = 0
    integer      :: bits_dense = 0
    real(real64) :: err_table  = 0._real64
    integer      :: rot_table  = 0
    integer      :: bits_table = 0
    integer      :: npairs     = 0
end type neigh_tally

contains

    subroutine run_all_eul_prob_tab_neigh_tests
        type(polarft_host_fixture) :: fx
        type(neigh_tally)          :: tally
        integer, allocatable       :: devs(:)
        integer                    :: is, id, original
        write(*,'(a)') '**** running all eul_prob_tab_neigh tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do is = 1, size(SEEDS)
            fx = make_polarft_host_fixture(SEEDS(is))
            call run_config(fx, CFG_HOST, 0, tally)
            do id = 1, size(devs)
                call mlx_set_default_device(devs(id))
                call run_config(fx, CFG_GRAPH, devs(id), tally)
                if( devs(id) == MLX_DEVICES%gpu ) call run_config(fx, CFG_METAL, devs(id), tally)
            end do
            call mlx_set_default_device(original)
        end do
        do is = 1, size(SEEDS)
            fx = make_polarft_host_fixture(SEEDS(is))
            call test_cells(fx)
            call run_driver(fx, CFG_HOST, 0)
            do id = 1, size(devs)
                call mlx_set_default_device(devs(id))
                call run_driver(fx, CFG_GRAPH, devs(id))
                if( devs(id) == MLX_DEVICES%gpu ) call run_driver(fx, CFG_METAL, devs(id))
            end do
            call mlx_set_default_device(original)
        end do
        fx = make_polarft_host_fixture(SEEDS(1))
        call test_orientations(fx)
        call test_refusals(fx, .false., 0)
        do id = 1, size(devs)
            call mlx_set_default_device(devs(id))
            call test_refusals(fx, .true., devs(id))
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_eul_prob_tab_neigh_tests

    ! ---- the fixture's lists, blocks and oracle ------------------------------------------------------------------

    ! list il: distinct references of 1..PH_NREFS in a scattered order (the dense list in order)
    function list_of( il ) result(irefs)
        integer, intent(in) :: il
        integer, allocatable :: irefs(:)
        integer              :: k
        select case( il )
            case( 4 )
                irefs = [(3 + 5 * (k - 1), k = 1, LIST_N(il))]
            case( NLISTS )
                irefs = [(k, k = 1, PH_NREFS)]
            case default
                irefs = [(1 + mod(17 + 7 * k, PH_NREFS), k = 1, LIST_N(il))]
        end select
    end function list_of

    ! block ib: particles of one half (project indices)
    function block_of( ib ) result(pids)
        integer, intent(in) :: ib
        integer, allocatable :: pids(:)
        integer              :: k
        if( ib == 1 )then
            pids = [(2 * k - 1, k = 1, BLOCK_N(ib))]
        else
            pids = [(2 * k + 6, k = 1, BLOCK_N(ib))]
        endif
    end function block_of

    ! the memos the oracle is handed, of every reference of half h: the transform of the ring and the conjugated
    ! transform of its squared modulus, by a double-precision DFT, rounded once
    function oracle_refs( fx, h ) result(refs)
        type(polarft_host_fixture), intent(in) :: fx
        integer,                    intent(in) :: h
        type(polar_table_refs) :: refs
        complex(real64)        :: e(NBINS, NROTS)
        integer                :: r, k
        e = polar_dft_matrix(NROTS, NBINS)
        refs%pftsz = PH_PFTSZ
        refs%nk    = PH_NK
        refs%half  = h
        refs%ids   = fx%ref_full
        allocate(refs%ft_ref(NBINS, PH_NK, PH_NREFS), refs%ft_ref2(NBINS, PH_NK, PH_NREFS))
        do r = 1, PH_NREFS
            do k = 1, PH_NK
                refs%ft_ref(:, k, r)  = cmplx(polar_dft_bins(e, polar_full_ring(fx%rref(:, k, r, h))), kind=real32)
                refs%ft_ref2(:, k, r) = cmplx(conjg(polar_dft_bins(e, polar_full_ring(cmplx(abs(fx%rref(:, k, r, h))**2, &
                    &0._real64, real64)))), kind=real32)
            end do
        end do
    end function oracle_refs

    ! the block of particles pids against the references irefs as the oracle reads it, with each pair's variate
    ! keyed by the seed and the pair's global IDs, rounded once
    function oracle_block( fx, pids, irefs ) result(blk)
        type(polarft_host_fixture), intent(in) :: fx
        integer,                    intent(in) :: pids(:), irefs(:)
        type(polar_table_block) :: blk
        complex(real64)         :: e(NBINS, NROTS)
        integer                 :: b, k, r, h
        e = polar_dft_matrix(NROTS, NBINS)
        h = polarft_host_half(pids(1))
        blk%half     = h
        blk%ref_ids  = fx%ref_full(irefs)
        blk%ptcl_ids = pids
        blk%weights  = real(fx%w(:, h), real32)
        allocate(blk%ctf2(NBINS, PH_NK, size(pids)), blk%xctf(NBINS, PH_NK, size(pids)), blk%wsq(size(pids)), &
            &blk%temps(size(pids)), blk%u(size(irefs), size(pids)))
        do b = 1, size(pids)
            blk%wsq(b) = 0._real64
            do k = 1, PH_NK
                blk%ctf2(:, k, b) = cmplx(polar_dft_bins(e, polar_full_ring(cmplx(real(fx%ctf(:, k, pids(b)), &
                    &real64)**2, 0._real64, real64))), kind=real32)
                blk%xctf(:, k, b) = cmplx(polar_dft_bins(e, polar_full_ring(cmplx(fx%x(:, k, pids(b)), kind=real64) * &
                    &real(fx%ctf(:, k, pids(b)), real64))), kind=real32)
                blk%wsq(b) = blk%wsq(b) + fx%w(k, h) * sum(abs(cmplx(fx%x(:, k, pids(b)), kind=real64))**2)
            end do
            blk%temps(b) = fx%temps(pids(b))
            do r = 1, size(irefs)
                blk%u(r, b) = real(polar_keyed_u(fx%seed, pids(b), fx%ref_full(irefs(r))), real32)
            end do
        end do
    end function oracle_block

    ! the oracle's rows of the pairs (irefs, pids)
    function oracle_rows( refs, blk, irefs ) result(dor)
        type(polar_table_refs),  intent(in) :: refs
        type(polar_table_block), intent(in) :: blk
        integer,                 intent(in) :: irefs(:)
        real(real64), allocatable :: dor(:,:,:)
        type(polar_table_refs)    :: sub
        sub%pftsz   = refs%pftsz
        sub%nk      = refs%nk
        sub%half    = refs%half
        sub%ids     = refs%ids(irefs)
        sub%ft_ref  = refs%ft_ref(:, :, irefs)
        sub%ft_ref2 = refs%ft_ref2(:, :, irefs)
        dor = polar_memo_rows(sub, blk)
    end function oracle_rows

    ! ---- scoring -------------------------------------------------------------------------------------------------

    ! a calculator of the fixture in configuration cfg (the host backend with a team of NTEAM, or the MLX backend
    ! with the compiled or fused tail), keeping full rows; msg the first refusal
    subroutine make_calc( fx, cfg, pftc, msg )
        type(polarft_host_fixture),    intent(in)    :: fx
        integer,                       intent(in)    :: cfg
        type(polarft_calc),            intent(inout) :: pftc
        character(len=:), allocatable, intent(out)   :: msg
        call polarft_host_calc(fx, parameters(pftsz=PH_PFTSZ, box=2 * PH_PFTSZ, nthr=NTEAM, l_mlx=cfg /= CFG_HOST), &
            &pftc, msg)
        if( len(msg) > 0 ) return
        if( cfg == CFG_METAL )then
            call pftc%set_tail_form(POLARFT_TAILS%metal)
            if( len(pftc%message()) == 0 ) call pftc%memoize_refs()
            msg = pftc%message()
            if( len(msg) > 0 ) return
        endif
        call pftc%set_draw_keys(fx%seed, fx%ref_full)
        call pftc%set_block_options(.true., .false.)
        msg = pftc%message()
    end subroutine make_calc

    ! the variates of the block (pids, irefs) handed to the MLX backend: keyed by the global IDs, as the host
    ! backend keys its own
    subroutine set_variates( fx, pftc, pids, irefs )
        type(polarft_host_fixture), intent(in)    :: fx
        type(polarft_calc),         intent(inout) :: pftc
        integer,                    intent(in)    :: pids(:), irefs(:)
        real(real32), allocatable :: u(:,:)
        integer                   :: b, r
        allocate(u(size(irefs), size(pids)))
        u = 0._real32
        do b = 1, size(pids)
            do r = 1, size(irefs)
                ! a list the calculator refuses may hold a reference outside the fixture
                if( irefs(r) >= 1 .and. irefs(r) <= PH_NREFS ) &
                    &u(r, b) = real(polar_keyed_u(fx%seed, pids(b), fx%ref_full(irefs(r))), real32)
            end do
        end do
        call pftc%set_block_variates(u)
    end subroutine set_variates

    ! the block sb (its particles against its reference list) scored synchronously (score_block_posterior), with
    ! its full rows; msg the refusal
    subroutine score_list( fx, pftc, sb, ent, msg )
        type(polarft_host_fixture),    intent(in)    :: fx
        type(polarft_calc),            intent(inout) :: pftc
        type(scored_block),            intent(in)    :: sb
        type(polar_table_entries),     intent(out)   :: ent
        character(len=:), allocatable, intent(out)   :: msg
        allocate(ent%dists(size(sb%irefs), size(sb%pids)), ent%irots(size(sb%irefs), size(sb%pids)))
        if( sb%l_mlx ) call set_variates(fx, pftc, sb%pids, sb%irefs)
        call pftc%score_block_posterior(size(sb%pids), sb%pids, size(sb%irefs), sb%irefs, fx%temps(sb%pids), ent%dists, &
            &ent%irots)
        msg = pftc%message()
        if( len(msg) > 0 ) return
        call pftc%block_rows(ent%rows)
        if( .not. allocated(ent%rows) ) msg = 'no rows came back'
    end subroutine score_list

    ! ---- the gates -----------------------------------------------------------------------------------------------

    ! one configuration on one seed: every block against every list, held to the oracle and to the dense entries;
    ! then repeatability (three repeats, the queued call in one or two slots, or a host team); the digest is written
    subroutine run_config( fx, cfg, dev, tally )
        type(polarft_host_fixture), intent(in)    :: fx
        integer,                    intent(in)    :: cfg, dev
        type(neigh_tally),          intent(inout) :: tally
        type(polarft_calc)               :: pftc
        type(polar_table_refs)           :: refs(2)
        type(polar_table_block)          :: blk
        type(polar_table_entries)        :: ent, dense
        type(polarft_host_table)         :: tab
        type(polar_row_check)            :: chk, chkd, chkt
        character(len=:), allocatable    :: msg, label
        real(real64),     allocatable    :: dor(:,:,:)
        integer,          allocatable    :: pids(:), irefs(:)
        integer(int64)                   :: dig
        integer,          allocatable    :: cols(:)
        integer                          :: ib, il, ndraw, nbits, h, b
        logical                          :: l_mlx, l_exact, l_table
        label = config_label(cfg, dev, fx%seed)
        write(*,'(a)') 'test_lists '//label
        l_mlx   = cfg /= CFG_HOST
        l_exact = cfg == CFG_HOST .or. (dev == MLX_DEVICES%cpu .and. cpu_matmul_shape_exact())
        tally   = neigh_tally()
        call make_calc(fx, cfg, pftc, msg)
        call assert_int(0, len(msg), label//': the calculator is made: '//msg)
        if( len(msg) > 0 )then
            call pftc%kill()
            return
        endif
        ! the dense table of the driver's fill (blocks of PFTC_BLOCK_NB, other particles side by side), with the
        ! compiled tail: the dense route of decision (b) and (c) under another grouping
        l_table    = cfg /= CFG_METAL
        tab%l_mlx  = l_mlx
        tab%nthr   = 1
        tab%l_rows = .true.
        if( l_table )then
            call fill_polarft_host_table(fx, tab)
            call assert_int(0, len(tab%msg), label//': the dense table is filled: '//tab%msg)
            l_table = len(tab%msg) == 0
        endif
        refs(1) = oracle_refs(fx, 1)
        refs(2) = oracle_refs(fx, 2)
        dig     = DIGEST0
        do ib = 1, NBLOCKS
            pids = block_of(ib)
            h    = polarft_host_half(pids(1))
            call score_list(fx, pftc, scored_block(l_mlx, pids, list_of(NLISTS)), dense, msg)
            call assert_int(0, len(msg), label//': the dense block is scored: '//msg)
            if( len(msg) > 0 ) cycle
            do il = 1, NLISTS
                irefs = list_of(il)
                call score_list(fx, pftc, scored_block(l_mlx, pids, irefs), ent, msg)
                call assert_int(0, len(msg), label//': a list is scored: '//msg)
                if( len(msg) > 0 ) cycle
                call digest_bits(dig, transfer(ent%dists, [0_int32]))
                call digest_bits(dig, int(reshape(ent%irots, [size(ent%irots)]), int32))
                ! (a) the oracle of the same global pairs, and the draw on the entry's own row
                blk   = oracle_block(fx, pids, irefs)
                dor   = oracle_rows(refs(h), blk, irefs)
                chk   = polar_compare_rows(dor, ent)
                ndraw = polar_draws_off(ent, blk%temps, blk%u)
                call assert_int(0, chk%valid_off, label//': every listed entry is valid or invalid as in the oracle')
                call assert_int(0, ndraw, label//': every listed pair''s draw holds on its own row, the variate keyed '//&
                    &'by the pair''s global IDs')
                tally%err_oracle = max(tally%err_oracle, chk%err)
                tally%rot_oracle = tally%rot_oracle + chk%argmin_off
                if( il == NLISTS )then
                    tally%err_full = max(tally%err_full, chk%err)
                    tally%rot_full = tally%rot_full + chk%argmin_off
                endif
                tally%npairs     = tally%npairs + chk%npairs
                ! the dense entries of the same pairs: exact where the route promises it, else within the tail's
                chkd  = polar_compare_rows(real(dense%rows(:, irefs, :), real64), ent)
                nbits = count(.not. bits_equal(ent%dists, dense%dists(irefs, :))) + &
                    &count(ent%irots /= dense%irots(irefs, :))
                tally%err_dense  = max(tally%err_dense, chkd%err)
                tally%rot_dense  = tally%rot_dense + count(ent%irots /= dense%irots(irefs, :))
                tally%bits_dense = tally%bits_dense + nbits
                if( l_exact )then
                    call assert_true(nbits == 0 .and. all(bits_equal(ent%rows, dense%rows(:, irefs, :))), label//&
                        &': a listed pair''s entry and row are the dense route''s, bit for bit')
                endif
                if( l_table )then
                    cols = [(findloc(tab%order, pids(b), dim=1), b = 1, size(pids))]
                    chkt = polar_compare_rows(real(tab%rows(:, irefs, cols), real64), ent)
                    nbits = count(.not. bits_equal(ent%dists, tab%dists(irefs, cols))) + &
                        &count(ent%irots /= tab%irots(irefs, cols))
                    tally%err_table  = max(tally%err_table, chkt%err)
                    tally%rot_table  = tally%rot_table + count(ent%irots /= tab%irots(irefs, cols))
                    tally%bits_table = tally%bits_table + nbits
                    if( l_exact ) call assert_true(nbits == 0 .and. all(bits_equal(ent%rows, tab%rows(:, irefs, cols))), &
                        &label//': a listed pair''s entry and row are the dense table''s, bit for bit')
                endif
            end do
        end do
        call assert_true(tally%err_oracle <= POLAR_ROW_FACTOR * POLAR_NEIGH_ERR_CPU, label//': the listed rows'' '//&
            &'error is within twice the lists'' calibrated e_cpu')
        call assert_true(tally%rot_oracle <= max(nint(POLAR_ROW_FACTOR) * POLAR_NEIGH_ROT_CPU, POLAR_FIXTURE_ROT_Q), &
            &label//': the listed pairs'' minimising rotation differs from the oracle''s in at most max(2 n_cpu, 1)')
        if( l_table .and. .not. l_exact )then
            call assert_true(tally%err_table <= POLARFT_TAIL_ROW_TOL, label//': the listed rows are the dense '//&
                &'table''s within the tail''s row tolerance')
            call assert_true(tally%rot_table <= POLARFT_TAIL_ROT_FIX, label//': the listed pairs'' drawn rotations '//&
                &'are the dense table''s but for the tail''s count')
        endif
        if( .not. l_exact )then
            call assert_true(tally%err_dense <= POLARFT_TAIL_ROW_TOL, label//': the listed rows are the dense '//&
                &'route''s within the tail''s row tolerance')
            call assert_true(tally%rot_dense <= POLARFT_TAIL_ROT_FIX, label//': the listed pairs'' drawn rotations '//&
                &'are the dense route''s but for the tail''s count')
        endif
        write(*,'(a,es10.3,a,i0,a,i0,a,es10.3,a,i0,a,i0)') '    '//label//': listed against the oracle: row error ', &
            &tally%err_oracle, ', minimising rotation differs in ', tally%rot_oracle, ' of ', tally%npairs, &
            &'; against the dense route: row error ', tally%err_dense, ', entries differing ', tally%bits_dense, &
            &', drawn rotations differing ', tally%rot_dense
        if( l_table ) write(*,'(a,es10.3,a,i0,a,i0)') '    '//label//': against the dense table: row error ', &
            &tally%err_table, ', entries differing ', tally%bits_table, ', drawn rotations differing ', tally%rot_table
        write(*,'(a,z16.16)') '    digest neigh calc '//label//' ', dig
        write(*,'(a,es23.16,a,i0,a,es23.16,a,i0)') '    '//merge('calibration', 'measured   ', &
            &fx%seed == POLAR_SEED_CALIBRATION)//' neigh '//label//': e = ', tally%err_oracle, &
            &', n = ', tally%rot_oracle, '; the dense block alone: e = ', tally%err_full, ', n = ', tally%rot_full
        call test_repeats(fx, pftc, cfg, label, dig)
        call pftc%kill()
    end subroutine run_config

    function config_label( cfg, dev, seed ) result(label)
        integer, intent(in) :: cfg, dev, seed
        character(len=:), allocatable :: label
        character(len=16)             :: s
        write(s,'(a,i0)') ' seed=', seed
        select case( cfg )
            case( CFG_HOST )
                label = 'host'//trim(s)
            case( CFG_GRAPH )
                label = device_name(dev)//' graph'//trim(s)
            case default
                label = device_name(dev)//' metal'//trim(s)
        end select
    end function config_label

    ! the digest of every block against every list again: twice more synchronously; on the MLX backend through
    ! submit_block in one slot, then with the two blocks in flight in two slots; on the host backend inside a team
    ! of NTEAM, each thread scoring its blocks
    subroutine test_repeats( fx, pftc, cfg, label, dig0 )
        type(polarft_host_fixture), intent(in)    :: fx
        type(polarft_calc),         intent(inout) :: pftc
        integer,                    intent(in)    :: cfg
        character(len=*),           intent(in)    :: label
        integer(int64),             intent(in)    :: dig0
        integer(int64) :: dig
        integer        :: rep
        logical        :: same
        same = .true.
        do rep = 1, 2
            dig  = sync_digest(fx, pftc, cfg /= CFG_HOST)
            same = same .and. dig == dig0
        end do
        call assert_true(same, label//': three repeats give one digest')
        if( cfg == CFG_HOST )then
            call assert_true(team_digest(fx, pftc) == dig0, label//': a team of 24 gives the digest of one thread')
        else
            call assert_true(queued_digest(fx, pftc, 1) == dig0, label//': the queued call in one slot gives the '//&
                &'synchronous digest')
            call assert_true(queued_digest(fx, pftc, 2) == dig0, label//': two blocks in flight in two slots give '//&
                &'the synchronous digest')
        endif
    end subroutine test_repeats

    integer(int64) function sync_digest( fx, pftc, l_mlx ) result(dig)
        type(polarft_host_fixture), intent(in)    :: fx
        type(polarft_calc),         intent(inout) :: pftc
        logical,                    intent(in)    :: l_mlx
        type(polar_table_entries)     :: ent
        character(len=:), allocatable :: msg
        integer                       :: ib, il
        dig = DIGEST0
        do ib = 1, NBLOCKS
            do il = 1, NLISTS
                call score_list(fx, pftc, scored_block(l_mlx, block_of(ib), list_of(il)), ent, msg)
                if( len(msg) > 0 ) return
                call digest_bits(dig, transfer(ent%dists, [0_int32]))
                call digest_bits(dig, int(reshape(ent%irots, [size(ent%irots)]), int32))
            end do
        end do
    end function sync_digest

    ! the blocks queued with set_block_refs and submit_block: with nslots 1 each collected before the next, with 2
    ! the two blocks of a list in flight together, collected in order; digested in the synchronous order
    integer(int64) function queued_digest( fx, pftc, nslots ) result(dig)
        type(polarft_host_fixture), intent(in)    :: fx
        type(polarft_calc),         intent(inout) :: pftc
        integer,                    intent(in)    :: nslots
        type(polar_table_entries) :: ent(NBLOCKS, NLISTS)
        integer, allocatable      :: pids(:), irefs(:)
        integer                   :: ib, il, slot
        dig = 0_int64
        do il = 1, NLISTS
            irefs = list_of(il)
            do ib = 1, NBLOCKS
                pids = block_of(ib)
                slot = 1
                if( nslots == 2 ) slot = ib
                allocate(ent(ib, il)%dists(size(irefs), size(pids)), ent(ib, il)%irots(size(irefs), size(pids)))
                call pftc%set_block_refs(irefs)
                call set_variates(fx, pftc, pids, irefs)
                call pftc%submit_block(slot, size(pids), pids, fx%temps(pids))
                if( len(pftc%message()) > 0 ) return
                if( nslots == 1 ) call pftc%collect_block(slot, ent(ib, il)%dists, ent(ib, il)%irots)
                if( len(pftc%message()) > 0 ) return
            end do
            if( nslots == 2 )then
                do ib = 1, NBLOCKS
                    call pftc%collect_block(ib, ent(ib, il)%dists, ent(ib, il)%irots)
                    if( len(pftc%message()) > 0 ) return
                end do
            endif
        end do
        dig = DIGEST0
        do ib = 1, NBLOCKS
            do il = 1, NLISTS
                call digest_bits(dig, transfer(ent(ib, il)%dists, [0_int32]))
                call digest_bits(dig, int(reshape(ent(ib, il)%irots, [size(ent(ib, il)%irots)]), int32))
            end do
        end do
    end function queued_digest

    ! the host backend's blocks scored inside a team of NTEAM threads, each (block, list) by one thread into
    ! entries allocated before the region
    integer(int64) function team_digest( fx, pftc ) result(dig)
        type(polarft_host_fixture), intent(in)    :: fx
        type(polarft_calc),         intent(inout) :: pftc
        type(polar_table_entries) :: ent(NBLOCKS, NLISTS)
        integer                   :: pids(maxval(BLOCK_N), NBLOCKS), irefs(PH_NREFS, NLISTS), ib, il, k
        do il = 1, NLISTS
            irefs(1:LIST_N(il), il) = list_of(il)
        end do
        do ib = 1, NBLOCKS
            pids(1:BLOCK_N(ib), ib) = block_of(ib)
            do il = 1, NLISTS
                allocate(ent(ib, il)%dists(LIST_N(il), BLOCK_N(ib)), ent(ib, il)%irots(LIST_N(il), BLOCK_N(ib)))
            end do
        end do
        call pftc%check_block_work(NTEAM)
        dig = 0_int64
        if( len(pftc%message()) > 0 ) return
        !$omp parallel do num_threads(NTEAM) default(shared) private(k, ib, il) schedule(static, 1) proc_bind(close)
        do k = 1, NBLOCKS * NLISTS
            ib = (k - 1) / NLISTS + 1
            il = k - (ib - 1) * NLISTS
            call pftc%score_block_posterior(BLOCK_N(ib), pids(1:BLOCK_N(ib), ib), LIST_N(il), irefs(1:LIST_N(il), il), &
                &fx%temps(pids(1:BLOCK_N(ib), ib)), ent(ib, il)%dists, ent(ib, il)%irots)
        end do
        !$omp end parallel do
        dig = DIGEST0
        do ib = 1, NBLOCKS
            do il = 1, NLISTS
                call digest_bits(dig, transfer(ent(ib, il)%dists, [0_int32]))
                call digest_bits(dig, int(reshape(ent(ib, il)%irots, [size(ent(ib, il)%irots)]), int32))
            end do
        end do
    end function team_digest

    ! the fixture's directions and previous orientations: unit vectors, the directions distinct, every previous
    ! orientation within PH_PREV_SPAN degrees of a direction
    subroutine test_orientations( fx )
        type(polarft_host_fixture), intent(in) :: fx
        real(real64) :: best, worst, dmin
        integer      :: i, j, k
        write(*,'(a)') 'test_orientations'
        worst = 0._real64
        do i = 1, PH_NPTCLS
            best = 180._real64
            do j = 1, PH_NSPACE
                best = min(best, acos(min(1._real64, dot_product(fx%prev(:, i), fx%dirs(:, j)))) * 180._real64 / &
                    &acos(-1._real64))
            end do
            worst = max(worst, best)
        end do
        dmin = 180._real64
        do j = 1, PH_NSPACE
            do k = j + 1, PH_NSPACE
                dmin = min(dmin, acos(min(1._real64, dot_product(fx%dirs(:, j), fx%dirs(:, k)))) * 180._real64 / &
                    &acos(-1._real64))
            end do
        end do
        call assert_true(all(abs(norm2(fx%dirs, 1) - 1._real64) < 1.e-12_real64) .and. &
            &all(abs(norm2(fx%prev, 1) - 1._real64) < 1.e-12_real64), 'the fixture''s orientations are unit vectors')
        call assert_true(worst <= PH_PREV_SPAN + 1.e-9_real64, 'every previous orientation lies within the span of '//&
            &'a direction')
        call assert_true(dmin > 1._real64, 'the fixture''s directions are distinct')
    end subroutine test_orientations

    ! ---- the driver -----------------------------------------------------------------------------------------------

    ! the oracle's view of the fixture: the cells of the centres (each direction's, each cell's representative),
    ! each particle's half and the cell of its previous direction
    subroutine oracle_view( fx, f2s, s2f, half, pcell )
        type(polarft_host_fixture), intent(in)  :: fx
        integer, allocatable,       intent(out) :: f2s(:), s2f(:), half(:), pcell(:)
        integer :: i
        call oracle_neigh_cells(fx%dirs, polarft_host_centres(), f2s, s2f)
        half  = [(polarft_host_half(i), i = 1, PH_NPTCLS)]
        pcell = [(f2s(oracle_neigh_nearest(fx%prev(:, i), fx%dirs)), i = 1, PH_NPTCLS)]
    end subroutine oracle_view

    ! the toy's search-space map of the fixture's cells is the oracle's; no previous orientation lies within 1e-3
    ! degrees of a cone's edge, where float32 and float64 may list differently
    subroutine test_cells( fx )
        type(polarft_host_fixture), intent(in) :: fx
        type(srchspace_map)  :: map
        real(real64)         :: centres(3, PH_NCELLS)
        real                 :: distmat(PH_NCELLS, PH_NSPACE)
        integer, allocatable :: f2s(:), s2f(:), half(:), pcell(:)
        integer              :: i, c, k
        write(*,'(a,i0)') 'test_cells seed=', fx%seed
        centres = polarft_host_centres()
        do i = 1, PH_NSPACE
            do c = 1, PH_NCELLS
                distmat(c, i) = real(cone_view_dist(centres(:, c), fx%dirs(:, i)))
            end do
        end do
        call map%new(PH_NSPACE, PH_NCELLS, distmat)
        call oracle_view(fx, f2s, s2f, half, pcell)
        call assert_true(all(map%get_full2sub_map() == f2s) .and. all(map%get_sub2full_map() == s2f), &
            &'the toy''s search-space map is the oracle''s cells')
        call assert_true(all([(count(f2s == c) > 0, c = 1, PH_NCELLS)]), 'every cell of the fixture has members')
        do k = 1, size(PH_CONES)
            call assert_int(0, oracle_neigh_near_edge(fx%dirs, fx%prev, PH_CONES(k), 1.e-3_real64), &
                &'no previous orientation lies within 1e-3 degrees of a cone''s edge')
        end do
        call map%kill()
    end subroutine test_cells

    ! one configuration's neighbourhood fills on one seed: geom at both cones and state, both block orders, each
    ! held to the oracle (columns, lists, pools, members, occupancy), its entries to the memo oracle and, on the
    ! host backend and the compiled tail, to the dense table; then repeatability
    subroutine run_driver( fx, cfg, dev )
        type(polarft_host_fixture), intent(in) :: fx
        integer,                    intent(in) :: cfg, dev
        type(polarft_host_table)      :: dense
        type(polarft_neigh_table)     :: tab
        character(len=128)            :: label
        integer                       :: im, io
        character(len=8), parameter   :: MODES(3) = [character(len=8) :: 'geom', 'geom', 'state']
        dense%l_mlx  = cfg /= CFG_HOST
        dense%nthr   = 1
        dense%l_rows = .true.
        if( cfg /= CFG_METAL ) call fill_polarft_host_table(fx, dense)
        do im = 1, size(MODES)
            do io = NEIGH_ORDERS%batch, NEIGH_ORDERS%simple
                tab        = polarft_neigh_table()
                tab%l_mlx  = cfg /= CFG_HOST
                tab%tail   = merge(POLARFT_TAILS%metal, POLARFT_TAILS%graph, cfg == CFG_METAL)
                tab%mode   = MODES(im)
                if( im <= size(PH_CONES) ) tab%cone = PH_CONES(min(im, size(PH_CONES)))
                tab%order  = io
                write(label,'(a,a,f5.1,a,i0)') config_label(cfg, dev, fx%seed)//' '//trim(tab%mode), ' cone=', &
                    &tab%cone, ' order=', io
                call check_fill(fx, tab, dense, cfg, trim(label))
                ! the cones through the pair-list kernel, on the GPU
                if( dev /= MLX_DEVICES%gpu .or. tab%mode /= 'geom' ) cycle
                tab       = polarft_neigh_table()
                tab%l_mlx = .true.
                tab%tail  = merge(POLARFT_TAILS%metal, POLARFT_TAILS%graph, cfg == CFG_METAL)
                tab%mode  = MODES(im)
                tab%cone  = PH_CONES(min(im, size(PH_CONES)))
                tab%order = io
                tab%cover = 'pairs'
                call check_fill(fx, tab, dense, cfg, trim(label)//' pairs')
            end do
        end do
        ! a cone of 0 degrees through the pair-list kernel lists no pair in either half: the fill holds no job and
        ! succeeds, as the route's does
        if( dev == MLX_DEVICES%gpu )then
            tab       = polarft_neigh_table()
            tab%l_mlx = .true.
            tab%tail  = merge(POLARFT_TAILS%metal, POLARFT_TAILS%graph, cfg == CFG_METAL)
            tab%cone  = 0._real64
            tab%cover = 'pairs'
            call fill_polarft_neigh_table(fx, tab)
            call assert_int(0, len(tab%msg), config_label(cfg, dev, fx%seed)//' geom cone=0 pairs: a half without '//&
                &'a listed pair is no job, and the fill succeeds: '//tab%msg)
        endif
    end subroutine run_driver

    ! a fill and its gates
    subroutine check_fill( fx, tab, dense, cfg, label )
        type(polarft_host_fixture), intent(in)    :: fx
        type(polarft_neigh_table),  intent(inout) :: tab
        type(polarft_host_table),   intent(in)    :: dense
        integer,                    intent(in)    :: cfg
        character(len=*),           intent(in)    :: label
        type(polarft_neigh_table) :: again
        integer(int64)            :: dig
        logical                   :: l_exact
        write(*,'(a)') 'test_driver '//label
        call fill_polarft_neigh_table(fx, tab)
        call assert_int(0, len(tab%msg), label//': the neighbourhood fill runs: '//tab%msg)
        if( len(tab%msg) > 0 ) return
        call check_lists(fx, tab, cfg, label)
        call check_entries(fx, tab, dense, cfg, label)
        dig = neigh_digest(tab)
        write(*,'(a,z16.16)') '    digest neigh fill '//label//' ', dig
        ! the host route's tables the off-state program writes too: the first cone and the state fill
        if( cfg == CFG_HOST .and. tab%mode == 'geom' .and. tab%order == NEIGH_ORDERS%simple .and. &
            &tab%cone < 0.5_real64 * (PH_CONES(1) + PH_CONES(2)) ) call write_polarft_neigh_table(fx, tab)
        if( cfg == CFG_HOST .and. tab%mode == 'state' .and. tab%order == NEIGH_ORDERS%simple ) &
            &call write_polarft_neigh_table(fx, tab)
        ! repeatability: two more fills; on the host backend teams of 4 and 24, on the MLX backend two slots
        again = tab
        call fill_polarft_neigh_table(fx, again)
        call assert_true(neigh_digest(again) == dig, label//': a repeated fill gives the digest')
        again = tab
        call fill_polarft_neigh_table(fx, again)
        call assert_true(neigh_digest(again) == dig, label//': a third fill gives the digest')
        if( cfg == CFG_HOST )then
            again      = tab
            again%nthr = 4
            call fill_polarft_neigh_table(fx, again)
            call assert_true(neigh_digest(again) == dig, label//': a team of 4 fills the table of one thread, byte '//&
                &'for byte')
            again      = tab
            again%nthr = NTEAM
            call fill_polarft_neigh_table(fx, again)
            call assert_true(neigh_digest(again) == dig, label//': a team of 24 gives the digest of one thread')
        else
            again        = tab
            again%nslots = 2
            call fill_polarft_neigh_table(fx, again)
            call assert_true(neigh_digest(again) == dig, label//': two blocks in flight give the digest of one')
        endif
        ! the dense cover (every block against every reference, the lists selected): the route's pairs, bit for bit
        ! on the host and Apple's CPU device; elsewhere the geom lists' pairs, and the pairs of the state fill reported
        again       = tab
        again%cover = 'dense'
        call fill_polarft_neigh_table(fx, again)
        l_exact = mlx_default_device() == MLX_DEVICES%cpu .and. cpu_matmul_shape_exact()
        l_exact = l_exact .or. cfg == CFG_HOST
        if( l_exact )then
            call assert_true(neigh_digest(again) == dig, label//': the dense cover selects the route''s entries, bit '//&
                &'for bit')
        else if( tab%mode == 'geom' )then
            call assert_true(nint(again%occ(1)) == nint(tab%occ(1)), label//': the dense cover lists the route''s pairs')
        endif
        write(*,'(a,i0,a,i0,a,i0)') '    '//label//': dense cover: listed ', nint(again%occ(1)), ' (route ', &
            &nint(tab%occ(1)), '), computed ', nint(again%occ(2))
    end subroutine check_fill

    ! the digest of a fill: its columns, lists, entries, pooled cells and the representatives' entries
    integer(int64) function neigh_digest( tab ) result(dig)
        type(polarft_neigh_table), intent(in) :: tab
        dig = DIGEST0
        if( len(tab%msg) > 0 .or. .not. allocated(tab%lst%refs) ) return
        call digest_bits(dig, int(tab%lst%order, int32))
        call digest_bits(dig, int(tab%lst%ptr, int32))
        call digest_bits(dig, int(tab%lst%refs, int32))
        call digest_bits(dig, transfer(tab%lst%dists, [0_int32]))
        call digest_bits(dig, int(tab%lst%irots, int32))
        if( allocated(tab%pool_cells) )then
            call digest_bits(dig, int(tab%pool_ptr, int32))
            call digest_bits(dig, int(tab%pool_cells, int32))
            call digest_bits(dig, transfer(tab%lst%rep_dists, [0_int32]))
            call digest_bits(dig, int(reshape(tab%lst%rep_irots, [size(tab%lst%rep_irots)]), int32))
        endif
    end function neigh_digest

    ! the columns, the lists, the pools and the occupancy against the oracle
    subroutine check_lists( fx, tab, cfg, label )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_neigh_table),  intent(in) :: tab
        integer,                    intent(in) :: cfg
        character(len=*),           intent(in) :: label
        type(polar_list_entries) :: ol
        integer, allocatable     :: f2s(:), s2f(:), half(:), pcell(:), cols(:), nbs(:), nrs(:), pool(:), mem(:), cov(:,:)
        integer(int64)           :: listed
        integer                  :: j, nh, k, c, s, i, bt, rt, nbad, nreps, m
        logical                  :: same
        call oracle_view(fx, f2s, s2f, half, pcell)
        cols = oracle_neigh_columns(half, pcell, tab%order)
        call assert_true(all(tab%lst%order == cols), label//': the columns are the oracle''s block order')
        if( any(tab%lst%order /= cols) ) return
        nh = count(half == 1)
        bt = 1
        rt = 1
        if( cfg /= CFG_HOST )then
            bt = 8
            rt = 16
        endif
        allocate(nbs(0), nrs(0))
        if( tab%mode == 'geom' )then
            ol   = oracle_neigh_cones(fx%dirs, PH_NREFS / PH_NSPACE, fx%prev(:, cols), tab%cone)
            same = all(tab%lst%ptr == ol%ptr)
            if( same ) same = all(tab%lst%refs == ol%refs)
            call assert_true(same, label//': every column''s list is the oracle''s cone')
            listed = int(size(ol%refs), int64)
            ! the blocks' unions
            do k = 1, 2
                do j = merge(1, nh + 1, k == 1), merge(nh, PH_NPTCLS, k == 1), tab%block_nb
                    m = min(j + tab%block_nb - 1, merge(nh, PH_NPTCLS, k == 1))
                    mem = union_of(ol, j, m)
                    if( size(mem) == 0 ) cycle
                    nbs = [nbs, m - j + 1]
                    nrs = [nrs, size(mem)]
                end do
            end do
        else
            nreps = PH_NCELLS * (PH_NREFS / PH_NSPACE)
            same  = size(tab%lst%reps) == nreps
            if( same ) same = all(tab%lst%reps == [(((s - 1) * PH_NSPACE + s2f(c), c = 1, PH_NCELLS), &
                &s = 1, PH_NREFS / PH_NSPACE)])
            call assert_true(same, label//': the representatives are the oracle''s (state, cell)')
            ! the pools: the oracle's rule on the toy's own representatives' entries
            nbad = 0
            do j = 1, PH_NPTCLS
                pool = oracle_neigh_pool(tab%lst%rep_dists(:, j), PH_NCELLS, PH_NPEAKS, pcell(cols(j)))
                if( size(pool) /= tab%pool_ptr(j + 1) - tab%pool_ptr(j) )then
                    nbad = nbad + 1
                else if( any(pool /= tab%pool_cells(tab%pool_ptr(j):tab%pool_ptr(j + 1) - 1)) )then
                    nbad = nbad + 1
                endif
            end do
            call assert_int(0, nbad, label//': every column''s pooled cells are the oracle''s rule on its entries')
            ! the members of the pooled cells, every state, ascending
            allocate(ol%ptr(PH_NPTCLS + 1), ol%refs(0))
            ol%ptr(1) = 1
            do j = 1, PH_NPTCLS
                pool = tab%pool_cells(tab%pool_ptr(j):tab%pool_ptr(j + 1) - 1)
                mem  = pack([(i, i = 1, PH_NREFS)], [(any(pool == f2s(mod(i - 1, PH_NSPACE) + 1)), i = 1, PH_NREFS)])
                ol%refs = [ol%refs, mem]
                ol%ptr(j + 1) = size(ol%refs) + 1
            end do
            same = all(tab%lst%ptr == ol%ptr)
            if( same ) same = all(tab%lst%refs == ol%refs)
            call assert_true(same, label//': every column''s members are those of its pooled cells')
            listed = int(size(ol%refs), int64) + int(nreps, int64) * int(PH_NPTCLS, int64)
            do k = 1, 2
                do j = merge(1, nh + 1, k == 1), merge(nh, PH_NPTCLS, k == 1), tab%block_nb
                    nbs = [nbs, min(j + tab%block_nb - 1, merge(nh, PH_NPTCLS, k == 1)) - j + 1]
                    nrs = [nrs, nreps]
                end do
            end do
            cov = member_cover(tab, f2s, nh, cfg)
            nbs = [nbs, cov(1, :)]
            nrs = [nrs, cov(2, :)]
            call report_oracle_pools(fx, tab, pcell(cols))
        endif
        call assert_true(nint(tab%occ(1), int64) == listed, label//': the listed pairs are the oracle''s')
        if( trim(tab%cover) == 'pairs' )then
            ! the pair-list kernel computes the listed pairs, a block per half
            call assert_true(nint(tab%occ(2), int64) == listed .and. nint(tab%occ(3)) == 2, label//': the pair-list '//&
                &'kernel computes the listed pairs only, a block per half')
        else
            call assert_true(nint(tab%occ(2), int64) == oracle_neigh_cover(nbs, nrs, bt, rt), label//': the '//&
                &'computed pairs are the oracle''s cover of the blocks, padded to the tile plan')
            call assert_true(nint(tab%occ(3)) == size(nbs), label//': the blocks scored are the oracle''s')
        endif
        write(*,'(a,i0,a,i0,a,f6.3,a,i0)') '    '//label//': listed ', nint(tab%occ(1), int64), ' computed ', &
            &nint(tab%occ(2), int64), ' occupancy ', tab%occ(1) / max(1._real64, tab%occ(2)), ' blocks ', nint(tab%occ(3))
    end subroutine check_lists

    ! the union of the lists of columns j0..j1
    function union_of( ol, j0, j1 ) result(u)
        type(polar_list_entries), intent(in) :: ol
        integer,                  intent(in) :: j0, j1
        integer, allocatable :: u(:)
        logical              :: mark(PH_NREFS)
        integer              :: r
        mark = .false.
        mark(ol%refs(ol%ptr(j0):ol%ptr(j1 + 1) - 1)) = .true.
        u = pack([(r, r = 1, PH_NREFS)], mark)
    end function union_of

    ! the member stage's blocks (particles, references; blocks) as the oracle cuts them: on the MLX backend per half and cell the columns that
    ! pooled the cell, in blocks of block_nb; on the host backend per block of the half and cell
    function member_cover( tab, f2s, nh, cfg ) result(cov)
        type(polarft_neigh_table), intent(in) :: tab
        integer,                   intent(in) :: f2s(:), nh, cfg
        integer, allocatable :: cov(:,:), nbs(:), nrs(:)
        integer              :: k, c, j, j0, j1, m, nmem, q
        allocate(nbs(0), nrs(0))
        do k = 1, 2
            j0 = merge(1, nh + 1, k == 1)
            j1 = merge(nh, PH_NPTCLS, k == 1)
            if( cfg /= CFG_HOST )then
                do c = 1, PH_NCELLS
                    nmem = (PH_NREFS / PH_NSPACE) * count(f2s == c)
                    m    = count([(pooled_cell(tab, j, c), j = j0, j1)])
                    do q = 1, m, tab%block_nb
                        nbs = [nbs, min(tab%block_nb, m - q + 1)]
                        nrs = [nrs, nmem]
                    end do
                end do
            else
                do j = j0, j1, tab%block_nb
                    do c = 1, PH_NCELLS
                        m = count([(pooled_cell(tab, q, c), q = j, min(j + tab%block_nb - 1, j1))])
                        if( m == 0 ) cycle
                        nbs = [nbs, m]
                        nrs = [nrs, (PH_NREFS / PH_NSPACE) * count(f2s == c)]
                    end do
                end do
            endif
        end do
        cov = reshape([nbs, nrs], [size(nbs), 2])
        cov = transpose(cov)
    end function member_cover

    logical function pooled_cell( tab, j, c )
        type(polarft_neigh_table), intent(in) :: tab
        integer,                   intent(in) :: j, c
        pooled_cell = any(tab%pool_cells(tab%pool_ptr(j):tab%pool_ptr(j + 1) - 1) == c)
    end function pooled_cell

    ! reported: the columns whose pool on the oracle's drawn distances (the memo oracle's rows drawn with the
    ! pair's keyed variate) differs from the toy's (a near tie or another drawn rotation moves a peak)
    subroutine report_oracle_pools( fx, tab, pcell )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_neigh_table),  intent(in) :: tab
        integer,                    intent(in) :: pcell(:)
        type(polar_table_refs)    :: refs(2)
        type(polar_table_block)   :: blk
        real(real64), allocatable :: dor(:,:,:)
        real(real32)              :: d(size(tab%lst%reps))
        integer, allocatable      :: pool(:)
        integer                   :: j, r, pid, irot, ndiff
        refs(1) = oracle_refs(fx, 1)
        refs(2) = oracle_refs(fx, 2)
        ndiff   = 0
        do j = 1, size(tab%lst%order)
            pid = tab%lst%order(j)
            blk = oracle_block(fx, [pid], tab%lst%reps)
            dor = oracle_rows(refs(polarft_host_half(pid)), blk, tab%lst%reps)
            do r = 1, size(tab%lst%reps)
                irot = polar_draw_row(dor(:, r, 1), blk%temps(1), real(blk%u(r, 1), real64))
                d(r) = POLAR_DIST_INVALID
                if( irot > 0 ) d(r) = real(dor(irot, r, 1), real32)
            end do
            pool = oracle_neigh_pool(d, PH_NCELLS, PH_NPEAKS, pcell(j))
            if( size(pool) /= tab%pool_ptr(j + 1) - tab%pool_ptr(j) )then
                ndiff = ndiff + 1
            else if( any(pool /= tab%pool_cells(tab%pool_ptr(j):tab%pool_ptr(j + 1) - 1)) )then
                ndiff = ndiff + 1
            endif
        end do
        write(*,'(a,i0,a,i0)') '    pools on the oracle''s drawn distances differ for ', ndiff, ' of ', &
            &size(tab%lst%order)
    end subroutine report_oracle_pools

    ! every listed entry (and the representatives') against the memo oracle's row at its drawn rotation:
    ! validity, and the distance within twice the lists' e_cpu of the row's largest valid |d|; on the host backend
    ! and the compiled tail against the dense table: bit for bit on the host and Apple's CPU device, within the
    ! tail's row tolerance on the GPU and another CPU device
    subroutine check_entries( fx, tab, dense, cfg, label )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_neigh_table),  intent(in) :: tab
        type(polarft_host_table),   intent(in) :: dense
        integer,                    intent(in) :: cfg
        character(len=*),           intent(in) :: label
        type(polar_table_refs)    :: refs(2)
        type(polar_table_block)   :: blk
        real(real64), allocatable :: dor(:,:,:)
        real(real64)              :: err, errt, dmax
        integer, allocatable      :: lr(:)
        real(real32), allocatable :: ld(:)
        integer,      allocatable :: li(:)
        integer                   :: j, k, pid, nvalid, nbits, nrot, col, nl
        logical                   :: l_exact
        refs(1) = oracle_refs(fx, 1)
        refs(2) = oracle_refs(fx, 2)
        l_exact = mlx_default_device() == MLX_DEVICES%cpu .and. cpu_matmul_shape_exact()
        l_exact = l_exact .or. cfg == CFG_HOST
        err     = 0._real64
        errt    = 0._real64
        nvalid  = 0
        nbits   = 0
        nrot    = 0
        do j = 1, size(tab%lst%order)
            pid = tab%lst%order(j)
            lr  = tab%lst%refs(tab%lst%ptr(j):tab%lst%ptr(j + 1) - 1)
            ld  = tab%lst%dists(tab%lst%ptr(j):tab%lst%ptr(j + 1) - 1)
            li  = tab%lst%irots(tab%lst%ptr(j):tab%lst%ptr(j + 1) - 1)
            if( allocated(tab%lst%reps) )then
                lr = [lr, tab%lst%reps]
                ld = [ld, tab%lst%rep_dists(:, j)]
                li = [li, tab%lst%rep_irots(:, j)]
            endif
            nl = size(lr)
            if( nl == 0 ) cycle
            blk = oracle_block(fx, [pid], lr)
            dor = oracle_rows(refs(polarft_host_half(pid)), blk, lr)
            do k = 1, nl
                call one_entry(dor(:, k, 1), ld(k), li(k), err, nvalid)
            end do
            if( cfg == CFG_METAL ) cycle
            col = findloc(dense%order, pid, dim=1)
            nbits = nbits + count(.not. bits_equal(ld, dense%dists(lr, col))) + count(li /= dense%irots(lr, col))
            nrot  = nrot + count(li /= dense%irots(lr, col))
            do k = 1, nl
                dmax = nan_maxval(abs(real(pack(dense%rows(:, lr(k), col), dense%rows(:, lr(k), col) < &
                    &POLAR_DIST_VALID), real64)))
                if( dmax > 0._real64 .and. ld(k) < POLAR_DIST_VALID ) errt = nan_max(errt, abs(real(ld(k), real64) - &
                    &real(dense%dists(lr(k), col), real64)) / dmax)
            end do
        end do
        call assert_int(0, nvalid, label//': every listed entry is valid or invalid as the oracle''s row at its '//&
            &'rotation')
        call assert_true(err <= POLAR_ROW_FACTOR * POLAR_NEIGH_ERR_CPU, label//': every listed distance is the '//&
            &'oracle''s within twice the lists'' e_cpu')
        if( cfg /= CFG_METAL .and. trim(tab%cover) == 'pairs' )then
            write(*,'(a,es23.16,a,i0)') '    '//merge('calibration', 'measured   ', fx%seed == POLAR_SEED_CALIBRATION)//&
                &' pairs '//label//': error against the dense table ', errt, ', rotations ', nrot
            call assert_true(errt <= POLAR_NEIGH_PAIR_ROW_TOL .and. nrot <= POLAR_NEIGH_PAIR_ROT, label//': the pair-'//&
                &'list kernel''s entries are the dense table''s within its frozen row tolerance and count')
        else if( cfg /= CFG_METAL )then
            if( l_exact )then
                call assert_int(0, nbits, label//': every listed entry is the dense table''s, bit for bit')
            else
                call assert_true(errt <= POLARFT_TAIL_ROW_TOL .and. nrot <= POLARFT_TAIL_ROT_FIX, label//&
                    &': the listed entries are the dense table''s within the tail''s row tolerance and count')
            endif
        endif
        write(*,'(a,es10.3,a,i0,a,es10.3,a,i0)') '    '//label//': against the oracle ', err, '; against the '//&
            &'dense table: entries differing ', nbits, ', error ', errt, ', rotations ', nrot
    end subroutine check_entries

    ! one entry against the oracle's row: the invalid entry (invalid, 1) where no rotation is valid, else a valid
    ! distance at the drawn rotation (the marker's neighbourhood excepted) within the error tallied
    subroutine one_entry( row, d, irot, err, nvalid )
        real(real64), intent(in)    :: row(:)
        real(real32), intent(in)    :: d
        integer,      intent(in)    :: irot
        real(real64), intent(inout) :: err
        integer,      intent(inout) :: nvalid
        real(real64) :: dmax
        if( .not. any(row < real(POLAR_DIST_VALID, real64)) )then
            if( irot /= 1 .or. .not. bits_equal(d, POLAR_DIST_INVALID) ) nvalid = nvalid + 1
            return
        endif
        if( irot < 1 .or. irot > size(row) )then
            nvalid = nvalid + 1
            return
        endif
        dmax = nan_maxval(abs(pack(row, row < real(POLAR_DIST_VALID, real64))))
        if( (row(irot) < real(POLAR_DIST_VALID, real64)) .neqv. (d < POLAR_DIST_VALID) )then
            if( abs(row(irot) - POLAR_DIST_MAX) > POLAR_VALID_MARGIN * dmax ) nvalid = nvalid + 1
            return
        endif
        if( d < POLAR_DIST_VALID ) err = nan_max(err, abs(real(d, real64) - row(irot)) / dmax)
    end subroutine one_entry

    ! ---- the refusals --------------------------------------------------------------------------------------------

    ! the lists a calculator refuses, each with its message: a reference outside 1..nrefs, a repeat, an empty list;
    ! on the MLX backend also through set_block_refs, variates of another shape than (list, particles), and the
    ! fused tail on the CPU device
    subroutine test_refusals( fx, l_mlx, dev )
        type(polarft_host_fixture), intent(in) :: fx
        logical,                    intent(in) :: l_mlx
        integer,                    intent(in) :: dev
        type(polarft_calc)            :: pftc
        type(polar_table_entries)     :: ent
        type(polarft_neigh_table)     :: tab
        character(len=:), allocatable :: msg, label
        real(real32),     allocatable :: u(:,:)
        integer,          allocatable :: pids(:)
        label = 'host'
        if( l_mlx ) label = device_name(dev)
        write(*,'(a)') 'test_refusals '//label
        call make_calc(fx, merge(CFG_GRAPH, CFG_HOST, l_mlx), pftc, msg)
        call assert_int(0, len(msg), label//': the calculator of the refusals is made: '//msg)
        if( len(msg) > 0 ) return
        pids = block_of(1)
        call score_list(fx, pftc, scored_block(l_mlx, pids, [3, 0]), ent, msg)
        call assert_true(index(msg, 'outside 1..nrefs') > 0, label//': a reference outside 1..nrefs is refused: '//msg)
        call score_list(fx, pftc, scored_block(l_mlx, pids, [3, PH_NREFS + 1]), ent, msg)
        call assert_true(index(msg, 'outside 1..nrefs') > 0, label//': a reference above nrefs is refused: '//msg)
        call score_list(fx, pftc, scored_block(l_mlx, pids, [3, 9, 3]), ent, msg)
        call assert_true(index(msg, 'repeats a reference') > 0, label//': a list with a repeat is refused: '//msg)
        call assert_true(all(ent%irots == 1) .and. all(bits_equal(ent%dists, huge(1._real32))), label//&
            &': a refused list leaves SIMPLE''s invalid entries')
        call score_list(fx, pftc, scored_block(l_mlx, pids, [integer ::]), ent, msg)
        call assert_true(index(msg, 'empty reference list') > 0, label//': an empty list is refused: '//msg)
        if( l_mlx )then
            call pftc%set_block_refs([5, 5])
            call assert_true(index(pftc%message(), 'repeats a reference') > 0, label//': set_block_refs refuses a '//&
                &'repeat')
            call pftc%set_block_refs([integer ::])
            call assert_true(index(pftc%message(), 'empty reference list') > 0, label//': set_block_refs refuses an '//&
                &'empty list')
            call pftc%set_block_refs([2, 4, 6])
            allocate(u(PH_NREFS, size(pids)))
            u = 0.5_real32
            call pftc%set_block_variates(u)
            call pftc%submit_block(1, size(pids), pids, fx%temps(pids))
            call assert_true(index(pftc%message(), 'shapes do not match') > 0, label//': variates of another shape '//&
                &'than (list, particles) are refused: '//pftc%message())
            if( dev == MLX_DEVICES%cpu )then
                call pftc%set_tail_form(POLARFT_TAILS%metal)
                if( len(pftc%message()) == 0 ) call pftc%memoize_refs()
                call assert_true(len(pftc%message()) > 0, label//': the fused tail is refused on the CPU device')
            endif
        endif
        call pftc%kill()
        ! the pair-list kernel: the cones on the MLX backend's GPU only
        tab       = polarft_neigh_table()
        tab%l_mlx = l_mlx
        tab%cover = 'pairs'
        call fill_polarft_neigh_table(fx, tab)
        if( .not. l_mlx )then
            call assert_true(index(tab%msg, 'serves the cones on the MLX backend') > 0, label//': the pair-list cover '//&
                &'is refused on the host backend: '//tab%msg)
        else if( dev == MLX_DEVICES%cpu )then
            call assert_true(index(tab%msg, 'GPU only') > 0, label//': the pair-list kernel is refused on the CPU '//&
                &'device: '//tab%msg)
        endif
        if( l_mlx )then
            tab       = polarft_neigh_table()
            tab%l_mlx = .true.
            tab%mode  = 'state'
            tab%cover = 'pairs'
            call fill_polarft_neigh_table(fx, tab)
            call assert_true(index(tab%msg, 'serves the cones') > 0, label//': the pair-list cover of the state fill '//&
                &'is refused: '//tab%msg)
            tab       = polarft_neigh_table()
            tab%l_mlx = .true.
            tab%cover = 'lists'
            call fill_polarft_neigh_table(fx, tab)
            call assert_true(index(tab%msg, 'unknown cover') > 0, label//': an unknown cover is refused: '//tab%msg)
        endif
    end subroutine test_refusals

end module mlxf_toy_eul_prob_tab_neigh_tester
