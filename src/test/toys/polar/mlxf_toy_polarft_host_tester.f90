!@descr: tests of the polar toy's host route: SIMPLE's block kernel against the ring oracle, the team's table, the fill's two branches
! The fixture is mlxf_polarft_host_fixture's, which the off-state program shares. The host backend's rows are held
! to a ring oracle (every rotation's distance directly on the full rings, in double precision, no transform) and
! its draws to its own rows, by the checks and within the bounds the MLX backend's suite has; the table is the
! same bytes whatever the team; the fill's two branches agree within those bounds. The suite also writes the host
! table's lines, which scripts/check_toy_offstate.sh compares with the off-state program's.
module mlxf_toy_polarft_host_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,                      only: mlx_set_default_device, mlx_default_device, mlx_live_count
use mlxf_test_defs,            only: PH_PFTSZ, PH_KFROM, PH_NK, PH_NREFS, PH_NPTCLS, PFTC_BLOCK_NB, POLAR_DIST_MAX, &
                                     POLAR_DIST_INVALID, POLAR_FIXTURE_ERR_CPU, POLAR_FIXTURE_ROT_CPU, &
                                     POLAR_FIXTURE_ROT_Q, POLAR_ROW_FACTOR, SHIFTMAP_WINDOW, parameters, &
                                     polar_table_entries, polar_row_check, polarft_host_fixture, polarft_host_table
use mlxf_toy_polarft_calc,     only: polarft_calc
use mlxf_toy_eul_prob_tab,     only: eul_prob_tab
use mlxf_polarft_host_fixture, only: make_polarft_host_fixture, polarft_host_half, polarft_host_calc, &
                                     fill_polarft_host_table, write_polarft_host_table
use mlxf_oracle_polar,         only: polar_keyed_u, polar_compare_rows, polar_draws_off
use mlxf_test_utils,           only: assert_true, assert_int, device_name, bits_equal, test_devices
implicit none
private
public :: run_all_polarft_host_tests

integer, parameter :: NROTS = 2 * PH_PFTSZ
! the fixture's seeds, and the team the table is compared across
integer, parameter :: SEEDS(3) = [1, 2, 3]
integer, parameter :: NTEAM    = 4

contains

    subroutine run_all_polarft_host_tests
        type(polarft_host_fixture) :: fx
        type(polarft_host_table)   :: host
        integer, allocatable       :: devs(:)
        integer                    :: is, id, original, live0
        write(*,'(a)') '**** running all polarft_host tests ****'
        live0 = mlx_live_count()
        do is = 1, size(SEEDS)
            fx = make_polarft_host_fixture(SEEDS(is))
            call host_table(fx, 1, .true., host)
            call assert_int(0, len(host%msg), 'polarft_host: the host backend fills the table: '//host%msg)
            if( len(host%msg) > 0 ) cycle
            call write_polarft_host_table(fx, host)
            call test_oracle(fx, host)
            call test_team(fx, host)
        end do
        call assert_int(live0, mlx_live_count(), 'polarft_host: the host backend made no device object')
        fx = make_polarft_host_fixture(SEEDS(1))
        call test_direct_call(fx)
        call test_refusals(fx)
        call test_devices(devs)
        original = mlx_default_device()
        do id = 1, size(devs)
            call mlx_set_default_device(devs(id))
            do is = 1, size(SEEDS)
                call test_branches(make_polarft_host_fixture(SEEDS(is)), devs(id))
            end do
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_polarft_host_tests

    ! the fixture's table on the host backend with a team of nthr
    subroutine host_table( fx, nthr, rows, tab )
        type(polarft_host_fixture), intent(in)  :: fx
        integer,                    intent(in)  :: nthr
        logical,                    intent(in)  :: rows
        type(polarft_host_table),   intent(out) :: tab
        tab%l_mlx  = .false.
        tab%nthr   = nthr
        tab%l_rows = rows
        call fill_polarft_host_table(fx, tab)
    end subroutine host_table

    ! ---- the ring oracle -----------------------------------------------------------------------------------------

    ! every rotation's distance of particle i against every reference of its half, directly on the full rings in
    ! double precision: d(r) = 1 + sum_k w_k sum_m [C_m^2 |R_(m-r+1)|^2 - 2 Re(X_m C_m conj(R_(m-r+1)))] / (2 wsq);
    ! above POLAR_DIST_MAX the invalid marker
    subroutine oracle_rows( fx, i, d )
        type(polarft_host_fixture), intent(in)  :: fx
        integer,                    intent(in)  :: i
        real(real64),               intent(out) :: d(NROTS, PH_NREFS)
        complex(real64) :: rr(NROTS, PH_NK), xc(NROTS, PH_NK)
        real(real64)    :: c2(NROTS, PH_NK), wsq, acc
        integer         :: h, ir, k, rot, m, mm
        h   = polarft_host_half(i)
        wsq = 0._real64
        do k = 1, PH_NK
            xc(1:PH_PFTSZ, k)  = cmplx(fx%x(:, k, i), kind=real64) * real(fx%ctf(:, k, i), real64)
            xc(PH_PFTSZ+1:, k) = conjg(cmplx(fx%x(:, k, i), kind=real64)) * real(fx%ctf(:, k, i), real64)
            c2(1:PH_PFTSZ, k)  = real(fx%ctf(:, k, i), real64)**2
            c2(PH_PFTSZ+1:, k) = c2(1:PH_PFTSZ, k)
            wsq = wsq + fx%w(k, h) * sum(abs(cmplx(fx%x(:, k, i), kind=real64))**2)
        end do
        do ir = 1, PH_NREFS
            do k = 1, PH_NK
                rr(1:PH_PFTSZ, k)  = fx%rref(:, k, ir, h)
                rr(PH_PFTSZ+1:, k) = conjg(fx%rref(:, k, ir, h))
            end do
            do rot = 1, NROTS
                acc = 0._real64
                do k = 1, PH_NK
                    do m = 1, NROTS
                        mm  = 1 + mod(m - rot + NROTS, NROTS)
                        acc = acc + fx%w(k, h) * (c2(m, k) * abs(rr(mm, k))**2 - &
                            &2._real64 * real(xc(m, k) * conjg(rr(mm, k)), real64))
                    end do
                end do
                d(rot, ir) = 1._real64 + acc / (2._real64 * wsq)
                if( d(rot, ir) > POLAR_DIST_MAX ) d(rot, ir) = real(POLAR_DIST_INVALID, real64)
            end do
        end do
    end subroutine oracle_rows

    ! the columns of a table that hold the particles of half h, in the batch's order
    function half_columns( tab, h ) result(cols)
        type(polarft_host_table), intent(in) :: tab
        integer,                  intent(in) :: h
        integer, allocatable :: cols(:)
        integer              :: j
        cols = pack([(j, j = 1, size(tab%order))], [(polarft_host_half(tab%order(j)) == h, j = 1, size(tab%order))])
    end function half_columns

    ! a half's entries and rows of a table, as the oracle's checks read them
    function half_entries( tab, cols ) result(ent)
        type(polarft_host_table), intent(in) :: tab
        integer,                  intent(in) :: cols(:)
        type(polar_table_entries) :: ent
        ent%dists = tab%dists(:, cols)
        ent%irots = tab%irots(:, cols)
        ent%rows  = tab%rows(:, :, cols)
    end function half_entries

    ! ---- the tests -----------------------------------------------------------------------------------------------

    ! the host backend's rows against the ring oracle and its draws on its own rows, per half, by the checks and
    ! within the bounds of the MLX backend's fixture
    subroutine test_oracle( fx, host )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_host_table),   intent(in) :: host
        type(polar_table_entries) :: ent
        type(polar_row_check)     :: chk(2)
        real(real64), allocatable :: dor(:,:,:)
        real(real32), allocatable :: u(:,:)
        integer,      allocatable :: cols(:)
        character(len=16)         :: label
        integer                   :: h, b, r
        write(label,'(a,i0)') 'host seed=', fx%seed
        write(*,'(a)') 'test_oracle '//trim(label)
        do h = 1, 2
            cols = half_columns(host, h)
            ent  = half_entries(host, cols)
            allocate(dor(NROTS, PH_NREFS, size(cols)), u(PH_NREFS, size(cols)))
            do b = 1, size(cols)
                call oracle_rows(fx, host%order(cols(b)), dor(:, :, b))
                do r = 1, PH_NREFS
                    u(r, b) = real(polar_keyed_u(fx%seed, host%order(cols(b)), fx%ref_full(r)), real32)
                end do
            end do
            chk(h)           = polar_compare_rows(dor, ent)
            chk(h)%draws_bad = polar_draws_off(ent, fx%temps(host%order(cols)), u)
            deallocate(dor, u)
        end do
        write(*,'(a,es10.3,a,i0,a,i0,a,i0,a,i0,a)') '    '//trim(label)//': row error ', maxval(chk%err), &
            &', minimising rotation differs in ', sum(chk%argmin_off), ' of ', sum(chk%npairs), ' pairs (', &
            &sum(chk%mixed), ' of mixed validity, ', sum(chk%invalid), ' invalid)'
        call assert_int(PH_NREFS * PH_NPTCLS, sum(chk%npairs), trim(label)//': the table holds every pair')
        call assert_int(0, sum(chk%valid_off), trim(label)//': every entry is valid or invalid as in the ring oracle')
        call assert_int(0, sum(chk%draws_bad), trim(label)//': u W lies in the drawn rotation''s cumulative interval '// &
            &'of the host''s row within 1e-4 W (or the fallback holds), and the entry''s distance is the row''s')
        call assert_true(maxval(chk%err) <= POLAR_ROW_FACTOR * POLAR_FIXTURE_ERR_CPU, trim(label)//': the rows'' '// &
            &'error is within twice the CPU calibration''s e_cpu')
        call assert_true(sum(chk%argmin_off) <= max(nint(POLAR_ROW_FACTOR) * POLAR_FIXTURE_ROT_CPU, &
            &POLAR_FIXTURE_ROT_Q), trim(label)//': the minimising rotation differs from the oracle''s in at most '// &
            &'max(2 n_cpu, 1) pairs')
        call assert_true(sum(chk%invalid) >= PH_NREFS, trim(label)//': the fixture has rows without a valid rotation')
    end subroutine test_oracle

    ! the table of a team of four against that of one thread: the same bytes
    subroutine test_team( fx, host )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_host_table),   intent(in) :: host
        type(polarft_host_table) :: team
        character(len=16)        :: label
        logical                  :: same
        write(label,'(a,i0)') 'host seed=', fx%seed
        write(*,'(a)') 'test_team '//trim(label)
        call host_table(fx, NTEAM, .true., team)
        same = len(team%msg) == 0
        if( same ) same = all(team%order == host%order)
        if( same ) same = all(bits_equal(team%dists, host%dists)) .and. all(team%irots == host%irots) .and. &
            &all(bits_equal(team%rows, host%rows))
        call assert_true(same, trim(label)//': a team of four fills the table of one thread, byte for byte: '//team%msg)
    end subroutine test_team

    ! one block scored by a direct call outside any region gives the fill's entries for its pairs, bit for bit: the
    ! block and the thread a pair meets change nothing
    subroutine test_direct_call( fx )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_host_table)      :: host
        type(polarft_calc)            :: pftc
        character(len=:), allocatable :: msg
        real(real32)                  :: dists(PH_NREFS, 3)
        integer                       :: irots(PH_NREFS, 3), pids(3), r, b, j
        logical                       :: same
        write(*,'(a)') 'test_direct_call'
        call host_table(fx, 1, .false., host)
        call polarft_host_calc(fx, parameters(pftsz=PH_PFTSZ, box=2 * PH_PFTSZ, l_mlx=.false.), pftc, msg)
        call pftc%set_draw_keys(fx%seed, fx%ref_full)
        ! three particles of the even half that the fill meets in different blocks
        pids = [1, 2 * PFTC_BLOCK_NB + 3, 2 * PFTC_BLOCK_NB - 1]
        call pftc%score_block_posterior(3, pids, PH_NREFS, [(r, r = 1, PH_NREFS)], fx%temps(pids), dists, irots)
        same = len(msg) == 0 .and. len(pftc%message()) == 0 .and. len(host%msg) == 0
        if( same )then
            do b = 1, 3
                j = findloc(host%order, pids(b), dim=1)
                same = same .and. all(bits_equal(dists(:, b), host%dists(:, j))) .and. all(irots(:, b) == host%irots(:, j))
            end do
        endif
        call assert_true(same, 'polarft_host: a direct call of score_block_posterior gives the fill''s entries, bit '// &
            &'for bit: '//pftc%message())
        call pftc%kill()
    end subroutine test_direct_call

    ! what the host route refuses, each with a message: a block above PFTC_BLOCK_NB, a fill without the draws' keys,
    ! a team above the calculator's, a driver whose parameters name the other backend, a shift map
    subroutine test_refusals( fx )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_calc), target    :: pftc
        type(eul_prob_tab)            :: drv
        type(parameters)              :: params
        character(len=:), allocatable :: msg
        real(real32)                  :: dists(PH_NREFS, PFTC_BLOCK_NB + 2), temps(PFTC_BLOCK_NB + 2)
        integer                       :: irots(PH_NREFS, PFTC_BLOCK_NB + 2), pids(PFTC_BLOCK_NB + 2), i, r
        write(*,'(a)') 'test_refusals'
        params = parameters(pftsz=PH_PFTSZ, box=2 * PH_PFTSZ, nthr=2, l_mlx=.false.)
        call polarft_host_calc(fx, params, pftc, msg)
        call assert_int(0, len(msg), 'polarft_host: the calculator of the refusals is made: '//msg)
        pids  = [(2 * i - 1, i = 1, PFTC_BLOCK_NB + 2)]
        temps = 1._real32
        call pftc%score_block_posterior(2, pids(1:2), PH_NREFS, [(r, r = 1, PH_NREFS)], temps(1:2), dists(:, 1:2), &
            &irots(:, 1:2))
        call assert_true(index(pftc%message(), 'set_draw_keys') > 0, 'polarft_host: a block without the draws'' '// &
            &'keys is refused')
        call assert_true(all(irots(:, 1:2) == 1) .and. all(bits_equal(dists(:, 1:2), huge(1._real32))), &
            &'polarft_host: a refused block leaves SIMPLE''s invalid entries')
        call pftc%set_draw_keys(fx%seed, fx%ref_full)
        call pftc%score_block_posterior(PFTC_BLOCK_NB + 2, pids, PH_NREFS, [(r, r = 1, PH_NREFS)], temps, dists, irots)
        call assert_true(index(pftc%message(), 'PFTC_BLOCK_NB') > 0, 'polarft_host: a block above PFTC_BLOCK_NB '// &
            &'particles is refused')
        call pftc%score_block_posterior(2, [1, 2], PH_NREFS, [(r, r = 1, PH_NREFS)], temps(1:2), dists(:, 1:2), &
            &irots(:, 1:2))
        call assert_true(index(pftc%message(), 'halves') > 0, 'polarft_host: a block that mixes the halves is refused')
        call pftc%check_block_work(3)
        call assert_true(index(pftc%message(), 'team') > 0, 'polarft_host: a team above the calculator''s is refused '// &
            &'before its region')
        ! the driver: a block size above SIMPLE's, the other backend's parameters, a shift map
        call drv%new_pipeline(params, pftc, [(i, i = 1, PH_NPTCLS)])
        call drv%set_draw_keys(fx%seed, fx%ref_full)
        call drv%set_temps(fx%temps)
        call drv%set_fill_options(PFTC_BLOCK_NB + 1, 1, .false., .false.)
        call drv%fill_tab_range(1, PH_NPTCLS)
        call assert_true(index(drv%message(), 'PFTC_BLOCK_NB') > 0, 'polarft_host: the fill refuses blocks above '// &
            &'PFTC_BLOCK_NB particles on the host backend')
        call drv%set_fill_options(PFTC_BLOCK_NB, 1, .false., .false.)
        call drv%set_candidates(reshape([(1, i = 1, PH_NPTCLS)], [1, PH_NPTCLS]))
        call drv%use_shiftmap(SHIFTMAP_WINDOW, 0._real64)
        call drv%fill_tab_range(1, PH_NPTCLS)
        call assert_true(index(drv%message(), 'refused') > 0, 'polarft_host: the fill refuses the shift maps on the '// &
            &'host backend')
        call drv%kill()
        params%l_mlx = .true.
        call drv%new_pipeline(params, pftc, [(i, i = 1, PH_NPTCLS)])
        call drv%set_draw_keys(fx%seed, fx%ref_full)
        call drv%set_temps(fx%temps)
        call drv%fill_tab_range(1, PH_NPTCLS)
        call assert_true(index(drv%message(), 'MLX backend') > 0, 'polarft_host: a driver on the MLX backend is '// &
            &'refused by a calculator on the host backend')
        call drv%kill()
        call pftc%kill()
    end subroutine test_refusals

    ! the fill's two branches on one fixture: the MLX backend's rows against the host backend's within the bounds
    ! of the MLX backend's fixture, entry by entry valid or invalid alike; the pairs whose drawn rotation differs
    ! are reported (the host draws with the variate in double precision, the device with it rounded once)
    subroutine test_branches( fx, dev )
        type(polarft_host_fixture), intent(in) :: fx
        integer,                    intent(in) :: dev
        type(polarft_host_table)  :: host, mlx
        type(polar_table_entries) :: ent
        type(polar_row_check)     :: chk(2)
        integer,      allocatable :: cols(:)
        character(len=24)         :: label
        integer                   :: h, ndraw
        write(label,'(a,i0)') device_name(dev)//' seed=', fx%seed
        write(*,'(a)') 'test_branches '//trim(label)
        call host_table(fx, NTEAM, .true., host)
        mlx%l_mlx  = .true.
        mlx%nthr   = 1
        mlx%l_rows = .true.
        call fill_polarft_host_table(fx, mlx)
        call assert_true(len(host%msg) == 0 .and. len(mlx%msg) == 0, trim(label)//': both branches fill the table: '// &
            &host%msg//mlx%msg)
        if( len(host%msg) > 0 .or. len(mlx%msg) > 0 ) return
        call assert_true(all(mlx%order == host%order), trim(label)//': both branches walk the batch in one order')
        do h = 1, 2
            cols   = half_columns(host, h)
            ent    = half_entries(mlx, cols)
            chk(h) = polar_compare_rows(real(host%rows(:, :, cols), real64), ent)
        end do
        ndraw = count(mlx%irots /= host%irots)
        write(*,'(a,es10.3,a,i0,a,i0,a,i0)') '    '//trim(label)//': the branches'' rows differ by ', maxval(chk%err), &
            &', minimising rotation in ', sum(chk%argmin_off), ' pairs, drawn rotation in ', ndraw, ' of ', &
            &sum(chk%npairs)
        call assert_int(0, sum(chk%valid_off), trim(label)//': an entry is valid or invalid on both branches')
        call assert_true(maxval(chk%err) <= POLAR_ROW_FACTOR * POLAR_FIXTURE_ERR_CPU, trim(label)//': the branches'' '// &
            &'rows agree within twice the CPU calibration''s e_cpu')
        call assert_true(sum(chk%argmin_off) <= max(nint(POLAR_ROW_FACTOR) * POLAR_FIXTURE_ROT_CPU, &
            &POLAR_FIXTURE_ROT_Q), trim(label)//': the branches'' minimising rotations differ in at most '// &
            &'max(2 n_cpu, 1) pairs')
    end subroutine test_branches

end module mlxf_toy_polarft_host_tester
