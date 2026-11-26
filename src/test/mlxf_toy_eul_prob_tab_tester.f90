!@descr: tests of the toy table driver: the fill's order, blocks and keyed draws, the two coarse maps set up by SIMPLE's rule, refusals
! The fixture is analytic (no random numbers): low-harmonic reference rings, angularly varying CTFs, particles
! as a reference of their half rotated, shifted to a cell of the window's grid and multiplied by their CTF. The
! dense entries are held to the construction (the known rotation) and, bit for bit, to the calculator scoring the
! same block with the oracle module's keyed variates; the maps to the direct residual at the returned cell,
! evaluated on the grid SIMPLE's rule gives, in real64, with no Bessel table and no transform.
module mlxf_toy_eul_prob_tab_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,                  only: mlx_set_default_device, mlx_default_device, mlx_live_count, MLX_DEVICES
use mlxf_test_defs,        only: POLAR_MAP_CAP_L2, SHIFTMAP_WINDOW, POLARFT_TAILS, parameters, polar_map_results
use mlxf_toy_polarft_calc, only: polarft_calc
use mlxf_toy_eul_prob_tab, only: eul_prob_tab
use mlxf_oracle_polar,     only: polar_full_ring, polar_keyed_u
use mlxf_test_utils,       only: assert_true, assert_int, device_name, bits_equal, test_devices, tests_run
use mlxf_test_reduce,      only: nan_max
implicit none
private
public :: run_all_eul_prob_tab_tests

integer, parameter :: NROT   = 24
integer, parameter :: PFTSZ  = NROT / 2
integer, parameter :: NK     = 4
integer, parameter :: BOX    = 32
integer, parameter :: NREF   = 5
integer, parameter :: NPTCL  = 6
integer, parameter :: NCAND  = 2
integer, parameter :: SEED   = 7
! the window of the maps (pixels) and the shift prior's width; with the box and the shells 1..NK, SIMPLE's rule
! gives the band's last shell max(1 + 1, NK / 2), radii a step of BOX / KSCREEN / 4 apart out to the window, and
! the smallest count of directions of small prime factors at or above 2 ceiling(2 pi KSCREEN TRS / BOX) + 3
real(real32), parameter :: TRS         = 8._real32
real(real32), parameter :: SHIFT_SIGMA = 4._real32
integer,      parameter :: KSCREEN     = 2
integer,      parameter :: NRHO        = 3
integer,      parameter :: NALPHA      = 12
real(real64), parameter :: RHO_STEP    = 4._real64
! the dense draws' inverse temperature: high enough that a draw is the minimising rotation
real(real32), parameter :: TEMP_SHARP = 1.e4_real32

! the analytic fixture: rings of the references (per half) and of the particles, the CTFs, the weights per half,
! each particle's source reference, rotation (0-based) and cell of the window's grid, and the tail's form
type :: tab_fixture
    real(real64)    :: w(NK, 2)
    complex(real32) :: rref(PFTSZ, NK, NREF, 2)
    complex(real32) :: x(PFTSZ, NK, NPTCL)
    real(real32)    :: ctf(PFTSZ, NK, NPTCL)
    integer         :: src(NPTCL), rot(NPTCL), irho(NPTCL), ialpha(NPTCL)
    integer         :: tail = POLARFT_TAILS%graph
end type tab_fixture

contains

    subroutine run_all_eul_prob_tab_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all eul_prob_tab tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call run_device_tests(devs(i), POLARFT_TAILS%graph)
            if( devs(i) == MLX_DEVICES%gpu )then
                write(*,'(a)') '  on the gpu, with the fused tail'
                call run_device_tests(devs(i), POLARFT_TAILS%metal)
            endif
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_eul_prob_tab_tests

    ! the device's checks with one form of the tail, and their count
    subroutine run_device_tests( dev, form )
        integer, intent(in) :: dev, form
        integer :: n0
        n0 = tests_run
        call test_fill_order_and_draws(dev, form)
        call test_blocks_slots_range(dev, form)
        call test_coarse_maps(dev, form)
        call test_refusals(dev, form)
        write(*,'(a,i0,a)') '    ', tests_run - n0, ' checks of the device'
    end subroutine run_device_tests

    ! ---- the fixture -------------------------------------------------------------------------------------

    ! the half of a particle: half 1 (SIMPLE's even half) holds the odd indices
    pure integer function half_of( i )
        integer, intent(in) :: i
        half_of = 2 - mod(i, 2)
    end function half_of

    ! a reference ring at ring position m (0-based) of shell k, reference j, half h, in real64
    pure complex(real64) function ring_value( m, k, j, h )
        integer, intent(in) :: m, k, j, h
        real(real64) :: theta, phi
        theta = 2._real64 * acos(-1._real64) * real(m, real64) / real(NROT, real64)
        phi   = real(2 * j + h, real64) / 7._real64 + real(k, real64) / 11._real64
        ring_value = cmplx(1._real64 + .03_real64 * k + .07_real64 * j + .11_real64 * h + &
            &.21_real64 * cos(2._real64 * theta + phi) + .13_real64 * cos(4._real64 * theta - phi), &
            &.31_real64 * sin(theta + phi) + .17_real64 * cos(3._real64 * theta - phi), real64)
    end function ring_value

    ! the shift of cell (irho, ialpha) of the window's grid, reference frame
    pure function grid_shift( irho, ialpha ) result(s)
        integer, intent(in) :: irho, ialpha
        real(real64) :: s(2), alpha
        alpha = 2._real64 * acos(-1._real64) * real(ialpha - 1, real64) / real(NALPHA, real64)
        s     = real(irho - 1, real64) * RHO_STEP * [cos(alpha), sin(alpha)]
    end function grid_shift

    ! the full ring rfull of shell k at rotation offset r (0-based), shifted by s in its own frame
    function posed( rfull, k, r, s ) result(p)
        complex(real64), intent(in) :: rfull(:)
        integer,         intent(in) :: k, r
        real(real64),    intent(in) :: s(2)
        complex(real64) :: p(size(rfull))
        real(real64)    :: theta, ax, ay
        integer         :: m, q
        do m = 0, NROT - 1
            q     = modulo(m - r, NROT)
            theta = 2._real64 * acos(-1._real64) * real(q, real64) / real(NROT, real64)
            ax    = 2._real64 * acos(-1._real64) * real(k, real64) * sin(theta) / real(BOX, real64)
            ay    = -2._real64 * acos(-1._real64) * real(k, real64) * cos(theta) / real(BOX, real64)
            p(m + 1) = rfull(q + 1) * exp(cmplx(0._real64, ax * s(1) + ay * s(2), real64))
        end do
    end function posed

    ! particles 1 and 2 are unshifted; the others sit on the second and third radii of the window's grid
    function make_fixture() result(fx)
        type(tab_fixture) :: fx
        complex(real64)   :: p(NROT)
        real(real64)      :: theta
        integer           :: h, j, k, m, i
        do k = 1, NK
            fx%w(k, 1) = real(k, real64) / (.5_real64 + .1_real64 * k)
            fx%w(k, 2) = real(k, real64) / (.8_real64 + .05_real64 * k)
        end do
        do h = 1, 2
            do j = 1, NREF
                do k = 1, NK
                    do m = 0, PFTSZ - 1
                        fx%rref(m + 1, k, j, h) = cmplx(ring_value(m, k, j, h), kind=real32)
                    end do
                end do
            end do
        end do
        do i = 1, NPTCL
            h            = half_of(i)
            fx%src(i)    = 1 + mod(2 * i, NREF)
            fx%rot(i)    = mod(5 * i, NROT)
            fx%irho(i)   = 1 + (i - 1) / 2
            fx%ialpha(i) = 1 + mod(3 * i, NALPHA)
            do k = 1, NK
                p = posed(polar_full_ring(cmplx(fx%rref(:, k, fx%src(i), h), kind=real64)), k, fx%rot(i), &
                    &grid_shift(fx%irho(i), fx%ialpha(i)))
                do m = 0, PFTSZ - 1
                    theta = 2._real64 * acos(-1._real64) * real(m, real64) / real(NROT, real64)
                    fx%ctf(m + 1, k, i) = real(.6_real64 + .2_real64 * cos(2._real64 * theta + .3_real64 * i) + &
                        &.1_real64 * sin(.2_real64 * k), real32)
                    fx%x(m + 1, k, i)   = cmplx(real(fx%ctf(m + 1, k, i), real64) * p(m + 1), kind=real32)
                end do
            end do
        end do
    end function make_fixture

    ! the normalised residual of particle i against reference j of its half at rotation ir (1-based) and cell
    ! (irho, ialpha), over the shells 1..KSCREEN: sum w |X - C R_pose|^2 / sum w |X|^2 on the full ring, real64
    function oracle_cell( fx, i, j, pose ) result(loss)
        type(tab_fixture), intent(in) :: fx
        integer,           intent(in) :: i, j, pose(3)
        real(real64)    :: loss, num, den
        complex(real64) :: xf(NROT), cf(NROT), shifted(NROT)
        integer         :: k, h
        h   = half_of(i)
        num = 0._real64
        den = 0._real64
        do k = 1, KSCREEN
            xf = polar_full_ring(cmplx(fx%x(:, k, i), kind=real64))
            cf = cmplx(real([fx%ctf(:, k, i), fx%ctf(:, k, i)], real64), 0._real64, real64)
            shifted = posed(polar_full_ring(cmplx(fx%rref(:, k, j, h), kind=real64)), k, pose(1) - 1, &
                &grid_shift(pose(2), pose(3)))
            num = num + fx%w(k, h) * sum(abs(xf - cf * shifted)**2)
            den = den + fx%w(k, h) * sum(abs(xf)**2)
        end do
        loss = num / den
    end function oracle_cell

    ! ---- the calculator and the driver ---------------------------------------------------------------------

    function fixture_params() result(params)
        type(parameters) :: params
        params%pftsz       = PFTSZ
        params%box         = BOX
        params%nthr        = 2
        params%shift_sigma = SHIFT_SIGMA
        params%smpd        = 1._real32
        params%trs         = TRS
    end function fixture_params

    ! 1 when the calculator refused its last call, else 0
    integer function refused( pftc )
        type(polarft_calc), intent(in) :: pftc
        refused = merge(1, 0, len(pftc%message()) > 0)
    end function refused

    ! the fixture's calculator: both halves' references and every particle, set and memoized; nbad counts the
    ! calls that were refused
    subroutine feed_calc( pftc, fx, nbad )
        type(polarft_calc), intent(inout) :: pftc
        type(tab_fixture),  intent(in)    :: fx
        integer,            intent(out)   :: nbad
        integer :: h, j, i
        call pftc%new(fixture_params(), NREF, [1, NPTCL], [1, NK])
        nbad = refused(pftc)
        call pftc%set_sigma2_weights(fx%w)
        nbad = nbad + refused(pftc)
        call pftc%set_tile_plan(2, 3)
        nbad = nbad + refused(pftc)
        call pftc%set_tail_form(fx%tail)
        nbad = nbad + refused(pftc)
        do h = 1, 2
            do j = 1, NREF
                call pftc%set_ref_pft(j, cmplx(fx%rref(:, :, j, h), kind=real64), h == 1)
                nbad = nbad + refused(pftc)
            end do
        end do
        do i = 1, NPTCL
            call pftc%set_eo(i, half_of(i) == 1)
            nbad = nbad + refused(pftc)
            call pftc%set_ptcl_ctfmat(i, fx%ctf(:, :, i))
            nbad = nbad + refused(pftc)
            call pftc%set_ptcl_pft(i, fx%x(:, :, i))
            nbad = nbad + refused(pftc)
        end do
        call pftc%memoize_refs
        nbad = nbad + refused(pftc)
        call pftc%memoize_ptcls
        nbad = nbad + refused(pftc)
    end subroutine feed_calc

    ! a driver of every particle of the calculator, with its keys and sharp temperatures; nbad counts the calls
    ! that were refused
    subroutine make_driver( tab, pftc, nbad )
        type(eul_prob_tab), intent(inout) :: tab
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(out)   :: nbad
        real(real32) :: temps(NPTCL)
        integer      :: i
        temps = TEMP_SHARP
        call tab%new_pipeline(fixture_params(), pftc, [(i, i = 1, NPTCL)])
        nbad = merge(1, 0, len(tab%message()) > 0)
        call tab%set_draw_keys(SEED, [(i, i = 1, NREF)])
        nbad = nbad + merge(1, 0, len(tab%message()) > 0)
        call tab%set_temps(temps)
        nbad = nbad + merge(1, 0, len(tab%message()) > 0)
    end subroutine make_driver

    ! ---- the tests -----------------------------------------------------------------------------------------

    ! one fill of every particle: the batch comes back with the even half first; an unshifted particle's entry
    ! against its source reference is the known rotation; every entry is the calculator's own score of the same
    ! block with the oracle module's keyed variates, bit for bit; an entry's distance is its row's at its rotation
    subroutine test_fill_order_and_draws( dev , form )
        integer, intent(in) :: dev, form
        type(tab_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(eul_prob_tab)        :: tab
        real(real32), allocatable :: dists(:,:), rows(:,:,:), u(:,:), dref(:,:)
        integer,      allocatable :: irots(:,:), order(:), iref(:,:)
        real(real32)              :: temps(3)
        integer                   :: nbad, n, j, r, h, live0, nknown, nrow
        logical                   :: same
        write(*,'(a)') 'test_fill_order_and_draws'
        fx = make_fixture()
        fx%tail = form
        call feed_calc(pftc, fx, nbad)
        call assert_int(0, nbad, 'the calculator is set and memoized: '//pftc%message())
        call make_driver(tab, pftc, n)
        call assert_int(0, n, 'the driver is made, with its keys and temperatures: '//tab%message())
        call assert_true(pftc%ref_bins_current(), 'the driver''s construction makes the reference bins')
        live0 = mlx_live_count()
        call tab%set_fill_options(NPTCL, 1, .true., .false.)
        call tab%fill_tab_range(1, NPTCL)
        call assert_int(0, len(tab%message()), device_name(dev)//': the range is filled: '//tab%message())
        call tab%batch_entries(dists, irots, order)
        call tab%batch_full_rows(rows)
        if( .not. allocated(dists) .or. .not. allocated(rows) ) return
        call assert_true(all(order == [1, 3, 5, 2, 4, 6]), device_name(dev)//': the batch holds the even half''s '//&
            &'particles first, then the odd half''s, each in the order of pinds')
        call assert_true(all(shape(dists) == [NREF, NPTCL]) .and. all(shape(rows) == [NROT, NREF, NPTCL]), &
            &'the batch''s rows are (references, particles) and its full rows (rotations, references, particles)')
        nknown = 0
        nrow   = 0
        do j = 1, NPTCL
            if( fx%irho(order(j)) == 1 )then
                if( irots(fx%src(order(j)), j) == fx%rot(order(j)) + 1 ) nknown = nknown + 1
            endif
            do r = 1, NREF
                if( bits_equal(dists(r, j), rows(irots(r, j), r, j)) ) nrow = nrow + 1
            end do
        end do
        call assert_int(2, nknown, device_name(dev)//': an unshifted particle built from its reference rotated by '//&
            &'r steps has its entry at rotation r + 1')
        call assert_int(NREF * NPTCL, nrow, device_name(dev)//': an entry''s distance is its full row''s at its rotation')
        ! the calculator scoring each half's block itself, the variates from the oracle module's generator
        same  = .true.
        temps = TEMP_SHARP
        do h = 1, 2
            allocate(u(NREF, 3), dref(NREF, 3), iref(NREF, 3))
            do j = 1, 3
                do r = 1, NREF
                    u(r, j) = real(polar_keyed_u(SEED, order(3 * (h - 1) + j), r), real32)
                end do
            end do
            call pftc%set_block_variates(u)
            call pftc%score_block_posterior(3, order(3 * (h - 1) + 1:3 * h), NREF, [(r, r = 1, NREF)], temps, dref, iref)
            same = same .and. refused(pftc) == 0 .and. all(bits_equal(dref, dists(:, 3 * (h - 1) + 1:3 * h))) .and. &
                &all(iref == irots(:, 3 * (h - 1) + 1:3 * h))
            deallocate(dref, iref)
        end do
        call assert_true(same, device_name(dev)//': the fill''s entries are the calculator''s own for the same '//&
            &'blocks and keyed variates, bit for bit')
        call assert_true(all(tab%fill_seconds() >= 0._real64) .and. sum(tab%fill_seconds()) > 0._real64, &
            &'the fill records its host seconds')
        call tab%kill
        call tab%kill
        ! the fused form's workspaces keep the rows variant the first block with rows built
        call assert_int(live0 + merge(2, 0, form == POLARFT_TAILS%metal), mlx_live_count(), device_name(dev)//&
            &': the driver holds no array of its own')
        call pftc%kill
    end subroutine test_fill_order_and_draws

    ! blocks of one tile of particles with two in flight, and a part of the range, give the entries of one
    ! block per half, bit for bit: a particle keeps its place in its tile, which is what its entry depends on
    subroutine test_blocks_slots_range( dev , form )
        integer, intent(in) :: dev, form
        type(tab_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(eul_prob_tab)        :: tab
        real(real32), allocatable :: d0(:,:), d1(:,:)
        integer,      allocatable :: i0(:,:), i1(:,:), o0(:), o1(:)
        integer                   :: nbad, n, j, j0
        logical                   :: same
        write(*,'(a)') 'test_blocks_slots_range'
        fx = make_fixture()
        fx%tail = form
        call feed_calc(pftc, fx, nbad)
        call make_driver(tab, pftc, n)
        call assert_int(0, nbad + n, 'the calculator and the driver are made')
        call tab%set_fill_options(NPTCL, 1, .false., .false.)
        call tab%fill_tab_range(1, NPTCL)
        call tab%batch_entries(d0, i0, o0)
        call tab%set_fill_options(2, 2, .false., .false.)
        call tab%fill_tab_range(1, NPTCL)
        call assert_int(0, len(tab%message()), device_name(dev)//': blocks of two particles, two in flight, are filled')
        call tab%batch_entries(d1, i1, o1)
        if( .not. allocated(d0) .or. .not. allocated(d1) ) return
        call assert_true(all(o1 == o0) .and. all(bits_equal(d1, d0)) .and. all(i1 == i0), device_name(dev)//&
            &': blocks of two particles with two in flight give the entries of one block per half')
        call tab%set_fill_options(2, 1, .false., .false.)
        call tab%fill_tab_range(1, 4)
        call assert_int(0, len(tab%message()), device_name(dev)//': a part of the range is filled')
        call tab%batch_entries(d1, i1, o1)
        if( .not. allocated(d1) ) return
        call assert_true(all(o1 == [1, 3, 2, 4]), device_name(dev)//': a part of the range comes back in the '//&
            &'batch''s order')
        same = .true.
        do j = 1, size(o1)
            j0   = findloc(o0, o1(j), dim=1)
            same = same .and. all(bits_equal(d1(:, j), d0(:, j0))) .and. all(i1(:, j) == i0(:, j0))
        end do
        call assert_true(same, device_name(dev)//': a part of the range has the whole range''s entries')
        call pftc%kill
    end subroutine test_blocks_slots_range

    ! the fill sets the two coarse maps up by SIMPLE's rule and reads each particle's candidates on the window:
    ! the band ends at the rule's shell, every mode lies on the rule's grid, and its loss is the direct residual
    ! at that cell of that grid
    subroutine test_coarse_maps( dev , form )
        integer, intent(in) :: dev, form
        type(tab_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(eul_prob_tab)        :: tab
        type(polar_map_results)   :: res
        real(real32), allocatable :: dists(:,:)
        integer,      allocatable :: irots(:,:), order(:)
        real(real64)              :: worst, lo
        integer                   :: nbad, n, i, j, c, cands(NCAND, NPTCL)
        write(*,'(a)') 'test_coarse_maps'
        fx = make_fixture()
        fx%tail = form
        call feed_calc(pftc, fx, nbad)
        call make_driver(tab, pftc, n)
        call assert_int(0, nbad + n, 'the calculator and the driver are made')
        do i = 1, NPTCL
            cands(:, i) = [fx%src(i), 1 + mod(fx%src(i), NREF)]
        end do
        call tab%set_candidates(cands)
        call assert_int(0, len(tab%message()), 'the candidates are set: '//tab%message())
        call pftc%set_shiftmap_options(2, .false., .false., .false.)
        call tab%set_fill_options(3, 1, .false., .false.)
        call tab%fill_tab_range(1, NPTCL)
        call assert_int(0, len(tab%message()), device_name(dev)//': the dense rows and the maps are filled: '//&
            &tab%message())
        call assert_int(KSCREEN, pftc%shiftmap_kstop(SHIFTMAP_WINDOW), device_name(dev)//': the window''s band ends '//&
            &'at SIMPLE''s shell max(kfrom + 1, kto / 2)')
        call tab%batch_entries(dists, irots, order)
        call tab%batch_map_results(res)
        if( .not. allocated(res%loss) .or. .not. allocated(order) ) return
        call assert_true(all(shape(res%loss) == [NCAND, NPTCL]), 'the maps'' results are (candidates, particles)')
        call assert_true(all(res%irot >= 1 .and. res%irot <= NROT) .and. all(res%irho >= 1 .and. res%irho <= NRHO) &
            &.and. all(res%ialpha >= 1 .and. res%ialpha <= NALPHA), device_name(dev)//': every mode lies on the '//&
            &'grid of SIMPLE''s rule')
        call assert_true(all(res%sdev >= 0._real32), 'every pair has a width')
        worst = 0._real64
        do j = 1, NPTCL
            do c = 1, NCAND
                lo    = oracle_cell(fx, order(j), cands(c, order(j)), [res%irot(c, j), res%irho(c, j), res%ialpha(c, j)])
                worst = nan_max(worst, abs(real(res%loss(c, j), real64) - lo) / max(1._real64, abs(lo)))
            end do
        end do
        write(*,'(a,es10.3)') '    coarse maps: largest returned loss error at the returned cell ', worst
        call assert_true(worst <= POLAR_MAP_CAP_L2, device_name(dev)//': every returned loss is the direct residual '//&
            &'at the returned cell of the grid of SIMPLE''s rule')
        ! the maps alone: the same results without the dense stage
        call tab%set_fill_stages(.false., .true.)
        call tab%fill_tab_range(1, NPTCL)
        call tab%batch_entries(dists, irots, order)
        call assert_true(len(tab%message()) == 0 .and. .not. allocated(dists), device_name(dev)//': the maps'' '//&
            &'stage runs alone and leaves no dense rows')
        call pftc%kill
    end subroutine test_coarse_maps

    ! what the driver cannot carry out is refused with its reason, and the calculator's refusals come through
    subroutine test_refusals( dev , form )
        integer, intent(in) :: dev, form
        type(tab_fixture)  :: fx
        type(polarft_calc) :: pftc
        type(eul_prob_tab) :: tab
        real(real32)       :: temps(NPTCL)
        integer            :: nbad, i
        write(*,'(a)') 'test_refusals'
        fx    = make_fixture()
        fx%tail = form
        temps = TEMP_SHARP
        call tab%fill_tab_range(1, NPTCL)
        call assert_true(index(tab%message(), 'new_pipeline') > 0, device_name(dev)//': a driver that was not '//&
            &'made refuses a fill')
        call feed_calc(pftc, fx, nbad)
        call tab%new_pipeline(fixture_params(), pftc, [(i, i = 1, NPTCL)])
        call tab%fill_tab_range(1, NPTCL)
        call assert_true(index(tab%message(), 'set_temps') > 0, device_name(dev)//': a fill without temperatures '//&
            &'is refused')
        call tab%set_temps(temps)
        call tab%fill_tab_range(1, NPTCL)
        call assert_true(index(tab%message(), 'set_draw_keys') > 0, device_name(dev)//': a fill without the keys '//&
            &'of its draws is refused')
        call tab%set_draw_keys(SEED, [(i, i = 1, NREF)])
        call tab%fill_tab_range(0, NPTCL)
        call assert_true(index(tab%message(), 'range') > 0, device_name(dev)//': a range outside the particles '//&
            &'is refused')
        call tab%set_fill_stages(.false., .true.)
        call assert_true(index(tab%message(), 'set_candidates') > 0, device_name(dev)//': the maps'' stage without '//&
            &'candidates is refused')
        call tab%set_fill_stages(.false., .false.)
        call tab%fill_tab_range(1, NPTCL)
        call assert_true(index(tab%message(), 'no stage') > 0, device_name(dev)//': a fill without a stage is refused')
        call tab%set_fill_stages(.true., .false.)
        call tab%set_fill_options(0, 1, .false., .false.)
        call assert_true(index(tab%message(), 'block') > 0, device_name(dev)//': a block without a particle is refused')
        call tab%fill_tab_range(1, NPTCL)
        call assert_int(0, len(tab%message()), device_name(dev)//': after the refusals the range is filled')
        ! a particle the calculator does not hold: the calculator's refusal is the driver's
        call tab%new_pipeline(fixture_params(), pftc, [1, 3, NPTCL + 1])
        call tab%set_draw_keys(SEED, [(i, i = 1, NREF)])
        call tab%set_temps(temps(1:3))
        call tab%fill_tab_range(1, 3)
        call assert_true(index(tab%message(), 'particle index') > 0, device_name(dev)//': a particle the '//&
            &'calculator does not hold is refused by the calculator, and the driver says so')
        call tab%kill
        call pftc%kill
    end subroutine test_refusals

end module mlxf_toy_eul_prob_tab_tester
