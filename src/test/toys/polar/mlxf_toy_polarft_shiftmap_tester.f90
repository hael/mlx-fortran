!@descr: tests of the toy polar calculator's shift maps: analytic ring fixtures, the direct residual oracle, mode, width, evidence
! The fixtures are analytic (no random numbers): low-harmonic Friedel-symmetric reference rings, angularly varying
! CTFs, particles as a reference shifted in its own frame, rotated and multiplied by its CTF; the calculator is
! handed the rings and memoizes them. The oracle evaluates the normalised residual L = sum w |X - C R_pose|^2 /
! sum w |X|^2 directly at every grid point in real64, with no Bessel table and no transform, and the mode, width
! and evidence from those maps on the host.
module mlxf_toy_polarft_shiftmap_tester
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,                  only: mlx_set_default_device, mlx_default_device, mlx_live_count, mlx_active_memory, &
                                 mlx_synchronize, mlx_clear_cache
use mlxf_test_defs,        only: POLAR_MAP_CAP_L2, POLAR_MAP_CAP_LOG, POLAR_MAP_CAP_VAR, POLAR_MAP_LOG_CUT, &
                                 SHIFTMAP_FULL, SHIFTMAP_SCREEN, NSHIFTMAPS, parameters, polar_map_results
use mlxf_toy_polarft_calc, only: polarft_calc
use mlxf_oracle_polar,     only: polar_full_ring
use mlxf_test_utils,       only: assert_true, assert_int, device_name, bits_equal, test_devices
use mlxf_test_reduce,      only: nan_maxval, nan_max
implicit none
private
public :: run_all_polar_shiftmap_tests, run_all_polar_shiftmap_accuracy_tests

integer, parameter :: NREF  = 7
integer, parameter :: NPTCL = 5
! the poses of the five particles: reference, rotation, radius and direction indices (1-based)
integer, parameter :: POSES(4, NPTCL) = reshape([2, 4, 3, 1, 5, 10, 4, 5, 7, 17, 2, 11, 1, 1, 1, 1, 3, 22, 4, 14], &
    &[4, NPTCL])
! the candidate lists: in order, permuted, with a duplicate
integer, parameter :: CANDS(3, 3) = reshape([7, 2, 5, 5, 7, 2, 2, 2, 7], [3, 3])
! tempered and physical inverse temperatures, the screen's prior weight
real(real32), parameter :: TEMP_T = 9._real32
real(real32), parameter :: TEMP_PHYS = 30._real32
real(real64), parameter :: PRIOR_SCREEN = 0.5_real64
! the noise of the seeded fixtures relative to each particle ring's rms
real(real64), parameter :: SEED_NOISE = 0.05_real64
! the map the tests build on their own grid over every shell: the calculator's full-band map
integer, parameter :: IMAP = SHIFTMAP_FULL

! one analytic fixture: rings (half ring, rounded), CTFs, weights per half, the grid
type :: map_fixture
    integer                      :: nrot = 0, pftsz = 0, nk = 0, box = 0, nalpha = 0, kfrom = 1
    logical                      :: perturbed = .false.
    real(real64),    allocatable :: rho(:)
    real(real64),    allocatable :: w(:,:)
    complex(real32), allocatable :: rref(:,:,:,:)
    complex(real32), allocatable :: x(:,:,:)
    real(real32),    allocatable :: ctf(:,:,:)
end type map_fixture

! a block of maps as the tests ask for it: the particles pids (one half), each one's candidate references
! cands(:, b), a tempered and a physical inverse temperature per particle, the prior's weight, the options, and
! per pair the loss above which its width is skipped
type :: map_request
    integer                   :: ptcl_tile = 16
    logical                   :: maps      = .true.
    logical                   :: evidence  = .true.
    logical                   :: profile   = .false.
    real(real64)              :: prior_w   = 0._real64
    integer,      allocatable :: ptcl_ids(:)
    integer,      allocatable :: cands(:,:)
    real(real32), allocatable :: temps(:)
    real(real32), allocatable :: temps_phys(:)
    real(real32), allocatable :: width_cutoff(:,:)
end type map_request

! the host's mode, width and evidence of a map
type :: map_summary
    integer      :: ialpha = 0, irot = 0, irho = 0
    real(real64) :: loss = 0._real64, sdev = 0._real64, logz = 0._real64, margin = 0._real64
end type map_summary

contains

    subroutine run_all_polar_shiftmap_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all polar_shiftmap tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_maps_against_oracle(devs(i), .false.)
            call test_maps_against_oracle(devs(i), .true.)
            call test_zero_radius(devs(i))
            call test_folding(devs(i))
            call test_nyquist(devs(i))
            call test_broadband_maps(devs(i))
            call test_evidence_width(devs(i))
            call test_requested_outputs(devs(i))
            call test_width_cutoff(devs(i))
            call test_map_repreparation(devs(i))
            call test_candidates_and_tiles(devs(i))
            call test_refusals_rebuild(devs(i))
            call test_lifecycle(devs(i))
            call test_mode_ties(devs(i))
            call test_seeded_widths(devs(i))
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_polar_shiftmap_tests

    subroutine run_all_polar_shiftmap_accuracy_tests
        type(map_fixture)       :: fx
        type(polarft_calc)      :: pftc
        type(map_request)       :: mb
        type(polar_map_results) :: res
        integer, allocatable    :: devs(:)
        integer                 :: original, d, grid, h, c, sample, pose(3), st
        real(real64)            :: expected, err2, norm2, err
        write(*,'(a)') '**** running all polar_shiftmap_accuracy tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do grid = 1, 2
            fx = make_map_fixture(.false., .true., production=grid, broadband=.true.)
            do d = 1, size(devs)
                call mlx_set_default_device(devs(d))
                do h = 1, 2
                    call prepare_half(fx, pftc)
                    mb = map_block([h], reshape([2, 7], [2, 1]), [TEMP_T, TEMP_PHYS])
                    mb%prior_w = PRIOR_SCREEN
                    call score_maps(pftc, mb, res, st)
                    call assert_int(0, st, 'production-geometry sample scores')
                    if( st /= 0 ) cycle
                    err2 = 0._real64
                    norm2 = 0._real64
                    do c = 1, 2
                        do sample = 0, 63
                            pose = [modulo(13*sample, fx%nalpha)+1, modulo(31*sample, fx%nrot)+1, &
                                &modulo(7*sample, size(fx%rho))+1]
                            expected = oracle_cell(fx, h, mb%cands(c, 1), pose)
                            err2 = err2 + (real(res%maps(pose(1), pose(2), pose(3), c, 1), real64)-expected)**2
                            norm2 = norm2 + expected**2
                        end do
                        pose = [res%ialpha(c, 1), res%irot(c, 1), res%irho(c, 1)]
                        expected = oracle_cell(fx, h, mb%cands(c, 1), pose)
                        call assert_true(abs(real(res%loss(c, 1), real64)-expected) <= &
                            &POLAR_MAP_CAP_L2*max(1._real64, abs(expected)), 'selected loss matches the direct residual')
                    end do
                    err = sqrt(err2/norm2)
                    write(*,'(a,a,a,i0,a,i0,a,es12.5)') '  ', device_name(devs(d)), ' grid=', grid, ' half=', h, ' error=', err
                    call assert_true(err <= POLAR_MAP_CAP_L2, 'production-geometry sampled maps satisfy the frozen cap')
                end do
            end do
        end do
        call pftc%kill
        call mlx_set_default_device(original)
    end subroutine run_all_polar_shiftmap_accuracy_tests

    ! ---- the fixtures ----------------------------------------------------------------------------------

    ! the reference ring R(theta, k, j, h) of the note, theta = 2 pi m / nrot, in real64
    pure complex(real64) function ring_value( m, nrot, k, j, h )
        integer, intent(in) :: m, nrot, k, j, h
        real(real64) :: theta, phi
        theta = 2._real64 * acos(-1._real64) * real(m, real64) / real(nrot, real64)
        phi   = real(2 * j + h, real64) / 7._real64 + real(k, real64) / 11._real64
        ring_value = cmplx(1._real64 + .03_real64 * k + .07_real64 * j + .11_real64 * h + &
            &.21_real64 * cos(2._real64 * theta + phi) + .13_real64 * cos(4._real64 * theta - phi), &
            &.31_real64 * sin(theta + phi) + .17_real64 * cos(3._real64 * theta - phi), real64)
    end function ring_value

    ! Even real and odd imaginary bins preserve R(theta+pi)=conjg(R(theta)); small-grid bins do not alias.
    pure complex(real64) function broadband_value( m, nrot, k, j, h )
        integer, intent(in) :: m, nrot, k, j, h
        integer      :: even_bins(4), odd_bins(4), b, nterms
        real(real64) :: theta, phi, re, im
        even_bins = [2, 4, 0, 0]
        odd_bins = [1, 3, 0, 0]
        nterms = 2
        if( nrot == 24 )then
            even_bins = [2, 6, 8, 10]
            odd_bins = [5, 7, 9, 11]
            nterms = 4
        else if( nrot == 364 )then
            even_bins = [12, 48, 110, 176]
            odd_bins = [11, 37, 95, 173]
            nterms = 4
        endif
        theta = 2._real64*acos(-1._real64)*real(m, real64)/real(nrot, real64)
        phi = real(3*j + 2*h + k, real64)/13._real64
        re = 0._real64
        im = 0._real64
        do b = 1, nterms
            re = re + .3_real64/real(b, real64)*cos(real(even_bins(b), real64)*theta + real(b, real64)*phi)
            im = im + .25_real64/real(b, real64)*sin(real(odd_bins(b), real64)*theta - real(b, real64)*phi)
        end do
        broadband_value = cmplx(re, im, real64)
    end function broadband_value

    ! the full ring of a stored half ring (the samples, then their conjugates), in real64
    function full_of( z ) result(f)
        complex(real32), intent(in) :: z(:)
        complex(real64) :: f(2*size(z))
        f = polar_full_ring(cmplx(z, kind=real64))
    end function full_of

    ! the shifted reference ring at rotation offset r (0-based) and shift s, on the full ring
    function posed( rfull, k, box, r, s ) result(p)
        complex(real64), intent(in) :: rfull(:)
        integer,         intent(in) :: k, box, r
        real(real64),    intent(in) :: s(2)
        complex(real64) :: p(size(rfull))
        real(real64)    :: theta, ax, ay
        integer         :: m, q, nrot
        nrot = size(rfull)
        do m = 0, nrot - 1
            q     = modulo(m - r, nrot)
            theta = 2._real64 * acos(-1._real64) * real(q, real64) / real(nrot, real64)
            ax    = 2._real64 * acos(-1._real64) * real(k, real64) * sin(theta) / real(box, real64)
            ay    = -2._real64 * acos(-1._real64) * real(k, real64) * cos(theta) / real(box, real64)
            p(m + 1) = rfull(q + 1) * exp(cmplx(0._real64, ax * s(1) + ay * s(2), real64))
        end do
    end function posed

    ! the shift of cell (irho, ialpha), reference frame
    function grid_shift( fx, irho, ialpha ) result(s)
        type(map_fixture), intent(in) :: fx
        integer,           intent(in) :: irho, ialpha
        real(real64) :: s(2), alpha
        alpha = 2._real64 * acos(-1._real64) * real(ialpha - 1, real64) / real(fx%nalpha, real64)
        s     = fx%rho(irho) * [cos(alpha), sin(alpha)]
    end function grid_shift

    ! the note's fixture (24 ring positions, shells 1..4, box 32, radii 0 to 1.5, 16 directions) or the folding
    ! case's (8 ring positions, shells 1..3, box 16, radii 0, 4, 8, 7 directions); particles posed by POSES
    function make_map_fixture( folding, perturbed, production, broadband ) result(fx)
        logical, intent(in)           :: folding, perturbed
        integer, optional, intent(in) :: production
        logical, optional, intent(in) :: broadband
        type(map_fixture)            :: fx
        complex(real64), allocatable :: rf(:), p(:)
        real(real64),    allocatable :: rho(:)
        real(real64)                 :: theta
        complex(real64)              :: z
        logical                      :: broad
        integer                      :: h, j, k, m, i, nrot, nk, box, nalpha
        broad = .false.
        if( present(broadband) ) broad = broadband
        if( folding )then
            nrot   = 8
            nk     = 3
            box    = 16
            rho    = [0._real64, 4._real64, 8._real64]
            nalpha = 7
        else
            nrot   = 24
            nk     = 4
            box    = 32
            rho    = [0._real64, .5_real64, 1._real64, 1.5_real64]
            nalpha = 16
        endif
        if( present(production) )then
            nrot = 364
            nk = 30
            box = 180
            fx%kfrom = 2
            if( production == 1 )then
                nalpha = 14
                rho = [(real(m, real64) * 4.3548_real64 / 3._real64, m = 0, 3)]
            else
                nalpha = 35
                rho = [(real(m, real64) * 14.5161_real64 / 10._real64, m = 0, 10)]
            endif
        endif
        fx%nrot      = nrot
        fx%pftsz     = nrot / 2
        fx%nk        = nk
        fx%box       = box
        fx%rho       = rho
        fx%nalpha    = nalpha
        fx%perturbed = perturbed
        allocate(fx%w(nk, 2), fx%rref(fx%pftsz, nk, NREF, 2), fx%x(fx%pftsz, nk, NPTCL), fx%ctf(fx%pftsz, nk, NPTCL))
        do k = 1, nk
            fx%w(k, 1) = real(k, real64) / (.5_real64 + .1_real64 * k)
            fx%w(k, 2) = real(k, real64) / (.8_real64 + .05_real64 * k)
        end do
        do h = 1, 2
            do j = 1, NREF
                do k = 1, nk
                    do m = 0, fx%pftsz - 1
                        z = ring_value(m, nrot, k + fx%kfrom - 1, j, h)
                        if( broad ) z = z + broadband_value(m, nrot, k + fx%kfrom - 1, j, h)
                        fx%rref(m + 1, k, j, h) = cmplx(z, kind=real32)
                    end do
                end do
            end do
        end do
        do i = 1, NPTCL
            h = 2 - mod(i, 2)
            do k = 1, nk
                do m = 0, fx%pftsz - 1
                    theta = 2._real64 * acos(-1._real64) * real(m, real64) / real(nrot, real64)
                    fx%ctf(m + 1, k, i) = real(.6_real64 + .2_real64 * cos(2._real64 * theta + .3_real64 * i) + &
                        &.1_real64 * sin(.2_real64 * k), real32)
                end do
                rf = full_of(fx%rref(:, k, POSES(1, i), h))
                ! the pose table's indices wrapped into this fixture's grid (the folding case's is smaller)
                p  = posed(rf, k + fx%kfrom - 1, box, modulo(POSES(2, i) - 1, nrot), grid_shift(fx, &
                    &modulo(POSES(3, i) - 1, size(rho)) + 1, modulo(POSES(4, i) - 1, nalpha) + 1))
                do m = 0, fx%pftsz - 1
                    theta = 2._real64 * acos(-1._real64) * real(m, real64) / real(nrot, real64)
                    p(m + 1) = real(fx%ctf(m + 1, k, i), real64) * p(m + 1)
                    if( perturbed ) p(m + 1) = p(m + 1) + .01_real64 * cmplx(cos(2._real64 * theta + .4_real64 * k), &
                        &sin(theta + .2_real64 * i), real64)
                end do
                fx%x(:, k, i) = cmplx(p(1:fx%pftsz), kind=real32)
            end do
        end do
    end function make_map_fixture

    ! ---- the oracle ------------------------------------------------------------------------------------

    ! the normalised residual of particle i against reference j of its half at every cell, (nalpha, nrot, nrho):
    ! sum_(m,k) w |X - C R_pose|^2 / sum_(m,k) w |X|^2 over the full ring, in real64
    function oracle_map( fx, i, j ) result(lmap)
        type(map_fixture), intent(in) :: fx
        integer,           intent(in) :: i, j
        real(real64) :: lmap(fx%nalpha, fx%nrot, size(fx%rho))
        integer      :: ia, ir, irho
        do irho = 1, size(fx%rho)
            do ir = 1, fx%nrot
                do ia = 1, fx%nalpha
                    lmap(ia, ir, irho) = oracle_cell(fx, i, j, [ia, ir, irho])
                end do
            end do
        end do
    end function oracle_map

    function oracle_cell( fx, i, j, pose ) result(loss)
        type(map_fixture), intent(in) :: fx
        integer,           intent(in) :: i, j, pose(3)
        real(real64)                 :: loss, num, den
        complex(real64), allocatable :: xf(:), cf(:), rf(:), shifted(:)
        integer                      :: k, h
        h = 2 - mod(i, 2)
        num = 0._real64
        den = 0._real64
        do k = 1, fx%nk
            xf = full_of(fx%x(:, k, i))
            cf = cmplx(real([fx%ctf(:, k, i), fx%ctf(:, k, i)], real64), 0._real64, real64)
            rf = full_of(fx%rref(:, k, j, h))
            shifted = posed(rf, k + fx%kfrom - 1, fx%box, pose(2)-1, grid_shift(fx, pose(3), pose(1)))
            num = num + fx%w(k, h) * sum(abs(xf-cf*shifted)**2)
            den = den + fx%w(k, h) * sum(abs(xf)**2)
        end do
        loss = num / den
    end function oracle_cell

    ! the cells' areas on the host: rings between the midpoints of neighbouring radii, the inner edge half a step
    ! below the first radius but not below 0, the outer half a step beyond the last, over the directions
    function host_areas( rho, nalpha ) result(area)
        real(real64), intent(in) :: rho(:)
        integer,      intent(in) :: nalpha
        real(real64) :: area(size(rho)), lo, hi
        integer      :: s, n
        n = size(rho)
        do s = 1, n
            if( s == 1 )then
                lo = max(0._real64, rho(1) - 0.5_real64 * (rho(min(2, n)) - rho(1)))
            else
                lo = 0.5_real64 * (rho(max(1, s - 1)) + rho(s))
            endif
            if( s == n )then
                hi = rho(n) + 0.5_real64 * (rho(n) - rho(max(1, n - 1)))
            else
                hi = 0.5_real64 * (rho(s) + rho(min(n, s + 1)))
            endif
            area(s) = acos(-1._real64) * (hi * hi - lo * lo) / real(nalpha, real64)
        end do
    end function host_areas

    ! the host's mode (the first largest log mass in Fortran order), its margin over the second largest, the
    ! width at the physical temperature (the moments of the cells' shifts, each rotation's turned by +theta into
    ! the particle's axes) and the log evidence (over every cell's prior mass), from a map lmap
    function summarize( fx, lmap, temps, prior_w ) result(sm)
        type(map_fixture), intent(in) :: fx
        real(real64),      intent(in) :: lmap(:,:,:)
        real(real32),      intent(in) :: temps(2)
        real(real64),      intent(in) :: prior_w
        type(map_summary) :: sm
        real(real64)      :: area(size(fx%rho)), l, lmax, l2, s, lph, mph, w, w0, w1(2), w2, mean(2), xy(2), th, var
        real(real64)      :: lse, pmax
        integer           :: ia, ir, irho
        area = host_areas(fx%rho, fx%nalpha)
        lmax = -huge(lmax)
        mph  = -huge(mph)
        do irho = 1, size(fx%rho)
            do ir = 1, fx%nrot
                do ia = 1, fx%nalpha
                    l = -real(temps(1), real64) * lmap(ia, ir, irho) - prior_w * fx%rho(irho)**2 + log(area(irho))
                    if( l > lmax )then
                        lmax      = l
                        sm%ialpha = ia
                        sm%irot   = ir
                        sm%irho   = irho
                    endif
                    mph = max(mph, -real(temps(2), real64) * lmap(ia, ir, irho) - prior_w * fx%rho(irho)**2 + &
                        &log(area(irho)))
                end do
            end do
        end do
        sm%loss = lmap(sm%ialpha, sm%irot, sm%irho)
        l2 = -huge(l2)
        s  = 0._real64
        w0 = 0._real64
        w2 = 0._real64
        mean = 0._real64
        do irho = 1, size(fx%rho)
            do ir = 1, fx%nrot
                w1 = 0._real64
                do ia = 1, fx%nalpha
                    l = -real(temps(1), real64) * lmap(ia, ir, irho) - prior_w * fx%rho(irho)**2 + log(area(irho))
                    if( .not. (ia == sm%ialpha .and. ir == sm%irot .and. irho == sm%irho) ) l2 = max(l2, l)
                    s   = s + exp(l - lmax)
                    lph = -real(temps(2), real64) * lmap(ia, ir, irho) - prior_w * fx%rho(irho)**2 + log(area(irho)) - mph
                    if( lph <= POLAR_MAP_LOG_CUT ) cycle
                    w  = exp(lph)
                    xy = grid_shift(fx, irho, ia)
                    w0 = w0 + w
                    w1 = w1 + w * xy
                    w2 = w2 + w * fx%rho(irho)**2
                end do
                th   = 2._real64 * acos(-1._real64) * real(ir - 1, real64) / real(fx%nrot, real64)
                mean = mean + [cos(th) * w1(1) - sin(th) * w1(2), sin(th) * w1(1) + cos(th) * w1(2)]
            end do
        end do
        sm%margin = lmax - l2
        mean      = mean / w0
        var       = w2 / w0 - sum(mean**2)
        sm%sdev   = sqrt(max(0._real64, var))
        pmax = maxval(-prior_w * fx%rho**2 + log(area))
        lse  = pmax + log(sum(real(fx%nrot, real64) * real(fx%nalpha, real64) * exp(-prior_w * fx%rho**2 + log(area) &
            &- pmax), mask=-prior_w * fx%rho**2 + log(area) - pmax > POLAR_MAP_LOG_CUT))
        sm%logz = lmax + log(s) - lse
    end function summarize

    ! ---- the calculator --------------------------------------------------------------------------------

    ! 1 when the calculator refused its last call, else 0
    integer function refused( pftc )
        type(polarft_calc), intent(in) :: pftc
        refused = merge(1, 0, len(pftc%message()) > 0)
    end function refused

    ! whether the calculator refused its last call for a reason that names word
    logical function refused_for( pftc, word )
        type(polarft_calc), intent(in) :: pftc
        character(len=*),   intent(in) :: word
        refused_for = index(pftc%message(), word) > 0
    end function refused_for

    ! the fixture's references of half h, set (not yet memoized); the calls that were refused
    integer function set_refs( pftc, fx, h ) result(nbad)
        type(polarft_calc), intent(inout) :: pftc
        type(map_fixture),  intent(in)    :: fx
        integer,            intent(in)    :: h
        integer :: j
        nbad = 0
        do j = 1, NREF
            call pftc%set_ref_pft(j, cmplx(fx%rref(:, 1:fx%nk, j, h), kind=real64), h == 1)
            nbad = nbad + refused(pftc)
        end do
    end function set_refs

    ! particle i's half, CTF and ring, set (not yet memoized); the calls that were refused
    integer function set_ptcl( pftc, fx, i ) result(nbad)
        type(polarft_calc), intent(inout) :: pftc
        type(map_fixture),  intent(in)    :: fx
        integer,            intent(in)    :: i
        call pftc%set_eo(i, mod(i, 2) == 1)
        nbad = refused(pftc)
        call pftc%set_ptcl_ctfmat(i, fx%ctf(:, 1:fx%nk, i))
        nbad = nbad + refused(pftc)
        call pftc%set_ptcl_pft(i, fx%x(:, 1:fx%nk, i))
        nbad = nbad + refused(pftc)
    end function set_ptcl

    ! a calculator of the fixture: both halves' references and every particle, set and memoized, the reference
    ! tiles made under a tile plan of 4 references and 2 particles; nbad counts the calls that were refused
    subroutine feed_calc( pftc, fx, nbad )
        type(polarft_calc), intent(inout) :: pftc
        type(map_fixture),  intent(in)    :: fx
        integer,            intent(out)   :: nbad
        integer :: h, i
        call pftc%new(parameters(pftsz=fx%pftsz, box=fx%box), NREF, [1, NPTCL], [fx%kfrom, fx%kfrom + fx%nk - 1])
        nbad = refused(pftc)
        call pftc%set_sigma2_weights(fx%w(1:fx%nk, :))
        nbad = nbad + refused(pftc)
        call pftc%set_tile_plan(2, 4)
        nbad = nbad + refused(pftc)
        do h = 1, 2
            nbad = nbad + set_refs(pftc, fx, h)
        end do
        do i = 1, NPTCL
            nbad = nbad + set_ptcl(pftc, fx, i)
        end do
        call pftc%memoize_refs
        nbad = nbad + refused(pftc)
        call pftc%memoize_ptcls
        nbad = nbad + refused(pftc)
    end subroutine feed_calc

    ! the fixture's calculator with its map over every shell on the fixture's grid
    subroutine prepare_half( fx, pftc )
        type(map_fixture),  intent(in)    :: fx
        type(polarft_calc), intent(inout) :: pftc
        integer :: nbad
        call feed_calc(pftc, fx, nbad)
        call assert_int(0, nbad, 'the references and particles are set and memoized: '//pftc%message())
        call pftc%new_shiftmap(IMAP, fx%rho, fx%nalpha, fx%kfrom + fx%nk - 1)
        call assert_int(0, refused(pftc), 'the maps are prepared: '//pftc%message())
    end subroutine prepare_half

    ! the dense rows of particles pids (one half) against every reference, zero temperature; st is 0 unless the
    ! block was refused
    subroutine dense_rows( pftc, pids, rows, st )
        type(polarft_calc),        intent(inout) :: pftc
        integer,                   intent(in)    :: pids(:)
        real(real32), allocatable, intent(out)   :: rows(:,:,:)
        integer,                   intent(out)   :: st
        real(real32), allocatable :: u(:,:), dists(:,:), temps(:)
        integer,      allocatable :: irots(:,:)
        integer                   :: j
        allocate(u(NREF, size(pids)), dists(NREF, size(pids)), irots(NREF, size(pids)), temps(size(pids)))
        u     = 0.5_real32
        temps = 0._real32
        call pftc%set_block_options(.true., .false.)
        call pftc%set_block_variates(u)
        call pftc%score_block_posterior(size(pids), pids, NREF, [(j, j = 1, NREF)], temps, dists, irots)
        st = refused(pftc)
        if( st == 0 ) call pftc%block_rows(rows)
    end subroutine dense_rows

    ! the maps of a request on the calculator's map: every particle's candidates in turn are generated, their
    ! modes read, and the results laid out (candidate, particle); st is 0 unless a call was refused
    subroutine score_maps( pftc, mb, res, st )
        type(polarft_calc),      intent(inout) :: pftc
        type(map_request),       intent(in)    :: mb
        type(polar_map_results), intent(out)   :: res
        integer,                 intent(out)   :: st
        real(real64), allocatable :: temp(:), tph(:)
        real(real32), allocatable :: loss(:), sdev(:), logz(:), maps(:,:,:,:)
        integer,      allocatable :: iref(:), iptcl(:), irot(:), irho(:), ialpha(:)
        integer                   :: ncand, nb, np, p, shp(4)
        ncand = size(mb%cands, 1)
        nb    = size(mb%cands, 2)
        np    = ncand * nb
        allocate(iptcl(np), temp(np), tph(np), irot(np), irho(np), ialpha(np), loss(np), sdev(np))
        iref = reshape(mb%cands, [np])
        do p = 1, np
            iptcl(p) = mb%ptcl_ids((p - 1) / ncand + 1)
            temp(p)  = real(mb%temps((p - 1) / ncand + 1), real64)
            tph(p)   = real(mb%temps_phys((p - 1) / ncand + 1), real64)
        end do
        call pftc%set_shiftmap_options(mb%ptcl_tile, mb%maps, mb%evidence, mb%profile)
        call pftc%gen_shiftmap(IMAP, iref, iptcl)
        st = refused(pftc)
        if( st /= 0 ) return
        if( allocated(mb%width_cutoff) )then
            call pftc%shiftmap_mode(IMAP, temp, mb%prior_w, irot, irho, ialpha, loss, temp_phys=tph, sdev=sdev, &
                &width_cutoff=reshape(mb%width_cutoff, [size(mb%width_cutoff)]))
        else
            call pftc%shiftmap_mode(IMAP, temp, mb%prior_w, irot, irho, ialpha, loss, temp_phys=tph, sdev=sdev)
        endif
        st = refused(pftc)
        if( st /= 0 ) return
        res%loss   = reshape(loss, [ncand, nb])
        res%sdev   = reshape(sdev, [ncand, nb])
        res%irot   = reshape(irot, [ncand, nb])
        res%irho   = reshape(irho, [ncand, nb])
        res%ialpha = reshape(ialpha, [ncand, nb])
        call pftc%shiftmap_evidence(logz)
        if( allocated(logz) ) res%logz = reshape(logz, [ncand, nb])
        call pftc%shiftmap_maps(maps)
        if( allocated(maps) )then
            shp      = shape(maps)
            res%maps = reshape(maps, [shp(1), shp(2), shp(3), ncand, nb])
        endif
    end subroutine score_maps

    ! the largest error of the returned losses against the direct residual at the returned pose, relative to
    ! max(1, |residual|), over every pair of a block; a pose outside the grid counts as an infinite error
    function loss_error( fx, pids, cands, res ) result(worst)
        type(map_fixture),       intent(in) :: fx
        integer,                 intent(in) :: pids(:), cands(:,:)
        type(polar_map_results), intent(in) :: res
        real(real64)              :: worst, lo
        real(real64), allocatable :: lor(:,:,:)
        integer                   :: b, c
        worst = 0._real64
        do b = 1, size(pids)
            do c = 1, size(cands, 1)
                if( res%ialpha(c, b) < 1 .or. res%ialpha(c, b) > fx%nalpha .or. res%irot(c, b) < 1 .or. &
                    &res%irot(c, b) > fx%nrot .or. res%irho(c, b) < 1 .or. res%irho(c, b) > size(fx%rho) )then
                    worst = huge(worst)
                    return
                endif
                lor   = oracle_map(fx, pids(b), cands(c, b))
                lo    = lor(res%ialpha(c, b), res%irot(c, b), res%irho(c, b))
                worst = nan_max(worst, abs(real(res%loss(c, b), real64) - lo) / max(1._real64, abs(lo)))
            end do
        end do
    end function loss_error

    ! the request of particles pids (one half) against candidate lists cands(:, b), no prior, maps and evidence
    function map_block( pids, cands, temps ) result(mb)
        integer,      intent(in) :: pids(:), cands(:,:)
        real(real32), intent(in) :: temps(2)
        type(map_request) :: mb
        mb%ptcl_ids = pids
        mb%cands    = cands
        allocate(mb%temps(size(pids)), mb%temps_phys(size(pids)))
        mb%temps      = temps(1)
        mb%temps_phys = temps(2)
    end function map_block

    ! every candidate list the same for the particles of half h
    function same_cands( list, n ) result(c)
        integer, intent(in) :: list(:), n
        integer :: c(size(list), n), b
        do b = 1, n
            c(:, b) = list
        end do
    end function same_cands

    function half_pids( h ) result(p)
        integer, intent(in) :: h
        integer, allocatable :: p(:)
        integer              :: i
        p = [(i, i = h, NPTCL, 2)]
    end function half_pids

    ! ---- the tests -------------------------------------------------------------------------------------

    ! every map of both halves against the direct oracle (normalised L2 within the cap, the largest error
    ! reported), the mode where the oracle's margin exceeds twice the map's bound, and in the noise-free case the
    ! known pose recovered by the mode at a high temperature
    subroutine test_maps_against_oracle( dev, perturbed )
        integer, intent(in) :: dev
        logical, intent(in) :: perturbed
        type(map_fixture)             :: fx
        type(polarft_calc)            :: pftc
        type(map_request)             :: mb
        type(polar_map_results)       :: res
        type(map_summary)             :: sm
        real(real64),     allocatable :: lor(:,:,:)
        real(real64)                  :: rel, worst_rel, worst_abs, bound, worst_loss
        integer,          allocatable :: pids(:)
        integer                       :: h, b, c, st, njudged, nmodes, nposes, nrecovered
        character(len=:), allocatable :: label
        label = 'noise-free'
        if( perturbed ) label = 'perturbed'
        write(*,'(a)') 'test_maps_against_oracle ('//label//')'
        fx = make_map_fixture(.false., perturbed)
        worst_rel  = 0._real64
        worst_abs  = 0._real64
        worst_loss = 0._real64
        njudged    = 0
        nmodes     = 0
        nposes     = 0
        nrecovered = 0
        do h = 1, 2
            pids = half_pids(h)
            call prepare_half(fx, pftc)
            mb = map_block(pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
            call score_maps(pftc, mb, res, st)
            call assert_int(0, st, device_name(dev)//' maps are scored: '//pftc%message())
            if( st /= 0 ) return
            worst_loss = max(worst_loss, loss_error(fx, pids, same_cands(CANDS(:, 1), size(pids)), res))
            do b = 1, size(pids)
                do c = 1, size(CANDS, 1)
                    lor = oracle_map(fx, pids(b), CANDS(c, 1))
                    rel = sqrt(sum((real(res%maps(:, :, :, c, b), real64) - lor)**2)) / sqrt(sum(lor**2))
                    worst_rel = max(worst_rel, rel)
                    worst_abs = nan_max(worst_abs, nan_maxval(abs(real(res%maps(:, :, :, c, b), real64) - lor)))
                    sm    = summarize(fx, lor, [TEMP_T, TEMP_PHYS], 0._real64)
                    bound = real(TEMP_T, real64) * POLAR_MAP_CAP_L2 * sqrt(sum(lor**2))
                    if( sm%margin > 2._real64 * bound )then
                        njudged = njudged + 1
                        if( res%ialpha(c, b) == sm%ialpha .and. res%irot(c, b) == sm%irot .and. &
                            &res%irho(c, b) == sm%irho ) nmodes = nmodes + 1
                    endif
                end do
            end do
            ! the known pose at a high temperature, where the area's weight is negligible
            if( .not. perturbed )then
                mb%temps = 1.e4_real32
                call score_maps(pftc, mb, res, st)
                do b = 1, size(pids)
                    do c = 1, size(CANDS, 1)
                        if( CANDS(c, 1) /= POSES(1, pids(b)) ) cycle
                        lor = oracle_map(fx, pids(b), CANDS(c, 1))
                        sm  = summarize(fx, lor, [1.e4_real32, TEMP_PHYS], 0._real64)
                        if( sm%margin <= 2._real64 * 1.e4_real64 * POLAR_MAP_CAP_L2 * sqrt(sum(lor**2)) ) cycle
                        nposes = nposes + 1
                        if( res%irot(c, b) == POSES(2, pids(b)) .and. res%irho(c, b) == POSES(3, pids(b)) .and. &
                            &res%ialpha(c, b) == POSES(4, pids(b)) ) nrecovered = nrecovered + 1
                    end do
                end do
            endif
            call pftc%kill
        end do
        write(*,'(a,es10.3,a,es10.3,a,i0,a,i0,a)') '    '//label//': largest map error ', worst_rel, &
            &' (normalised L2), ', worst_abs, ' (absolute); modes judged ', njudged, ', equal ', nmodes, ''
        call assert_true(worst_rel <= POLAR_MAP_CAP_L2, device_name(dev)//' '//label//': every map is within the '//&
            &'normalised L2 cap of the direct residual')
        write(*,'(a,es10.3)') '    '//label//': largest returned loss error at the returned pose ', worst_loss
        call assert_true(worst_loss <= POLAR_MAP_CAP_L2, device_name(dev)//' '//label//': every returned loss is the '//&
            &'direct residual at the returned pose')
        call assert_int(njudged, nmodes, device_name(dev)//' '//label//': the mode equals the oracle''s where its '//&
            &'margin exceeds twice the map''s bound')
        call assert_true(njudged > 0, label//': the fixture has modes clear enough to judge')
        if( .not. perturbed )then
            call assert_true(nposes >= 3, 'the noise-free fixture judges the known pose of at least three particles')
            call assert_int(nposes, nrecovered, device_name(dev)//': the noise-free maps recover the known poses')
        endif
    end subroutine test_maps_against_oracle

    ! the zero-radius map is the dense unshifted row of the same pair and does not depend on the direction
    subroutine test_zero_radius( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(map_request)         :: mb
        type(polar_map_results)   :: res
        real(real32), allocatable :: rows(:,:,:)
        real(real64)              :: dmax, worst, spread
        integer,      allocatable :: pids(:)
        integer                   :: st, b, c, ir, j
        write(*,'(a)') 'test_zero_radius'
        fx   = make_map_fixture(.false., .true.)
        pids = half_pids(1)
        call prepare_half(fx, pftc)
        mb = map_block(pids, same_cands([(j, j = 1, NREF)], size(pids)), [TEMP_T, TEMP_PHYS])
        call score_maps(pftc, mb, res, st)
        call dense_rows(pftc, pids, rows, st)
        call assert_int(0, st, 'the dense rows are scored')
        if( st /= 0 ) return
        worst  = 0._real64
        spread = 0._real64
        do b = 1, size(pids)
            do c = 1, NREF
                dmax = nan_maxval(abs(real(rows(:, c, b), real64)))
                do ir = 1, fx%nrot
                    worst  = nan_max(worst, abs(real(res%maps(1, ir, 1, c, b), real64) - &
                        &real(rows(ir, c, b), real64)) / dmax)
                    spread = max(spread, real(maxval(res%maps(:, ir, 1, c, b)) - minval(res%maps(:, ir, 1, c, b)), &
                        &real64) / dmax)
                end do
            end do
        end do
        write(*,'(a,es10.3,a,es10.3)') '    zero radius: largest difference from the dense row ', worst, &
            &', across directions ', spread
        call assert_true(worst <= POLAR_MAP_CAP_L2, device_name(dev)//': the zero-radius map is the dense unshifted row')
        call assert_true(spread <= POLAR_MAP_CAP_L2, device_name(dev)//': the zero-radius map does not depend on the '//&
            &'direction')
        call pftc%kill
    end subroutine test_zero_radius

    ! the folding case: 8 ring positions, box 16, shells 1..3, radii 0, 4, 8, 7 directions: the kept orders exceed
    ! both transform axes, so they must be folded, and every map matches the oracle
    subroutine test_folding( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(map_request)         :: mb
        type(polar_map_results)   :: res
        real(real64), allocatable :: lor(:,:,:)
        real(real64)              :: worst
        integer,      allocatable :: pids(:)
        integer                   :: st, b, c, h, norder
        write(*,'(a)') 'test_folding'
        fx    = make_map_fixture(.true., .true.)
        worst = 0._real64
        do h = 1, 2
            pids = half_pids(h)
            call prepare_half(fx, pftc)
            norder = pftc%shiftmap_order(IMAP)
            call assert_true(norder > max(fx%nalpha, fx%nrot), 'the folding case keeps orders beyond both '//&
                &'transform axes')
            mb = map_block(pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
            call score_maps(pftc, mb, res, st)
            call assert_int(0, st, 'the folding case is scored')
            if( st /= 0 ) return
            do b = 1, size(pids)
                do c = 1, size(CANDS, 1)
                    lor   = oracle_map(fx, pids(b), CANDS(c, 1))
                    worst = max(worst, sqrt(sum((real(res%maps(:, :, :, c, b), real64) - lor)**2)) / sqrt(sum(lor**2)))
                end do
            end do
            call pftc%kill
        end do
        write(*,'(a,i0,a,es10.3)') '    folding: orders 0..', norder, ' kept; largest map error ', worst
        call assert_true(worst <= POLAR_MAP_CAP_L2, device_name(dev)//': the folded maps match the direct residual')
    end subroutine test_folding

    ! the alternating Nyquist ring, unit CTF, equal rings: loss 0 at the identity and 4 one angular step away
    subroutine test_nyquist( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polarft_calc)      :: pftc
        type(map_request)       :: mb
        type(polar_map_results) :: res
        integer                 :: st, k, m
        write(*,'(a)') 'test_nyquist'
        fx = make_map_fixture(.false., .false.)
        do k = 1, fx%nk
            do m = 0, fx%pftsz - 1
                fx%rref(m + 1, k, 1, 1) = cmplx(real(1 - 2 * mod(m, 2), real32), 0._real32, real32)
            end do
            fx%x(:, k, 1)   = fx%rref(:, k, 1, 1)
            fx%ctf(:, k, 1) = 1._real32
        end do
        call prepare_half(fx, pftc)
        mb = map_block([1], reshape([1], [1, 1]), [TEMP_T, TEMP_PHYS])
        call score_maps(pftc, mb, res, st)
        call assert_int(0, st, 'the Nyquist ring is scored')
        if( st /= 0 ) return
        write(*,'(a,es12.5,a,es12.5)') '    Nyquist ring: loss at the identity ', res%maps(1, 1, 1, 1, 1), &
            &', one step away ', res%maps(1, 2, 1, 1, 1)
        call assert_true(abs(res%maps(1, 1, 1, 1, 1)) <= 4._real32 * real(POLAR_MAP_CAP_L2, real32), &
            &device_name(dev)//': the Nyquist ring has loss 0 at the identity')
        call assert_true(abs(res%maps(1, 2, 1, 1, 1) - 4._real32) <= 4._real32 * real(POLAR_MAP_CAP_L2, real32), &
            &device_name(dev)//': the Nyquist ring has loss 4 one angular step away')
        call pftc%kill
    end subroutine test_nyquist

    ! the log evidence and the width against the host's log-sum-exp and grid moments of the oracle's maps: no
    ! prior, the screen's prior, and a flat likelihood (zero temperatures: the prior alone, evidence 0); the
    ! width at the physical temperature, distinct from the tempered one
    subroutine test_evidence_width( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(map_request)         :: mb
        type(polar_map_results)   :: res
        type(map_summary)         :: sm, smt
        real(real64), allocatable :: lor(:,:,:)
        real(real64)              :: worst_logz, worst_var, prior_w, varcap, tdiff
        real(real32)              :: temps(2)
        integer,      allocatable :: pids(:)
        integer                   :: st, b, c, icase
        write(*,'(a)') 'test_evidence_width'
        fx     = make_map_fixture(.false., .true.)
        varcap = POLAR_MAP_CAP_VAR * max(1._real64, maxval(fx%rho)**2)
        tdiff  = 0._real64
        do icase = 1, 3
            prior_w = 0._real64
            temps   = [TEMP_T, TEMP_PHYS]
            if( icase >= 2 ) prior_w = PRIOR_SCREEN
            if( icase == 3 ) temps = [0._real32, 0._real32]
            worst_logz = 0._real64
            worst_var  = 0._real64
            pids = half_pids(1)
            call prepare_half(fx, pftc)
            mb = map_block(pids, same_cands(CANDS(:, 1), size(pids)), temps)
            mb%prior_w = prior_w
            call score_maps(pftc, mb, res, st)
            call assert_int(0, st, 'the evidence case is scored')
            if( st /= 0 ) return
            do b = 1, size(pids)
                do c = 1, size(CANDS, 1)
                    lor = oracle_map(fx, pids(b), CANDS(c, 1))
                    sm  = summarize(fx, lor, temps, prior_w)
                    worst_logz = nan_max(worst_logz, abs(real(res%logz(c, b), real64) - sm%logz))
                    worst_var  = nan_max(worst_var, abs(real(res%sdev(c, b), real64)**2 - sm%sdev**2))
                    if( icase == 1 )then
                        smt   = summarize(fx, lor, [temps(1), temps(1)], prior_w)
                        tdiff = nan_max(tdiff, abs(smt%sdev**2 - sm%sdev**2))
                    endif
                    if( icase == 3 ) call assert_true(abs(sm%logz) <= 1.e-12_real64, 'a flat likelihood has '//&
                        &'evidence 0 on the host')
                end do
            end do
            write(*,'(a,i0,a,es10.3,a,es10.3)') '    evidence case ', icase, ': largest log evidence error ', &
                &worst_logz, ', variance error ', worst_var
            call assert_true(worst_logz <= POLAR_MAP_CAP_LOG, device_name(dev)//': the log evidence matches the '//&
                &'host''s log-sum-exp')
            call assert_true(worst_var <= varcap, device_name(dev)//': the physical width''s variance matches the '//&
                &'host''s grid moments')
            call pftc%kill
        end do
        call assert_true(tdiff > 10._real64 * varcap, 'the physical and the tempered temperatures give widths '//&
            &'the variance cap tells apart')
    end subroutine test_evidence_width

    ! the broadband fixtures (the regular and the folding grid) with seven candidates per particle, repeats
    ! among them, a temperature pair per particle, the screen's prior and tiles of two particles (the last one
    ! partial): maps, selected losses, evidence, widths and clear modes against the oracle; a repeat is identical
    subroutine test_broadband_maps( dev )
        integer, intent(in) :: dev
        integer,      parameter   :: LISTS(7, 3) = reshape([7, 2, 5, 2, 7, 5, 1, &
            &1, 5, 7, 5, 2, 1, 7, 3, 7, 2, 3, 5, 2, 1], [7, 3])
        type(map_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(map_request)         :: mb
        type(polar_map_results)   :: res, again
        type(map_summary)         :: sm(7, 3)
        real(real64), allocatable :: expected(:,:,:,:,:)
        real(real64)              :: rel, varerr, logerr, losserr, bound, lo
        integer                   :: grid, c, b, st, njudged, nmodes
        write(*,'(a)') 'test_broadband_maps'
        do grid = 1, 2
            fx = make_map_fixture(grid == 2, .true., broadband=.true.)
            call prepare_half(fx, pftc)
            mb = map_block(half_pids(1), LISTS, [TEMP_T, TEMP_PHYS])
            mb%prior_w = PRIOR_SCREEN
            mb%temps = [3._real32, 9._real32, 27._real32]
            mb%temps_phys = [7._real32, 30._real32, 90._real32]
            mb%ptcl_tile = 2
            allocate(expected(fx%nalpha, fx%nrot, size(fx%rho), 7, 3))
            do b = 1, 3
                do c = 1, 7
                    expected(:,:,:, c, b) = oracle_map(fx, mb%ptcl_ids(b), mb%cands(c, b))
                    sm(c, b) = summarize(fx, expected(:,:,:, c, b), [mb%temps(b), mb%temps_phys(b)], PRIOR_SCREEN)
                end do
            end do
            call score_maps(pftc, mb, res, st)
            call assert_int(0, st, 'the broadband block scores')
            if( st /= 0 ) return
            rel = 0._real64
            varerr = 0._real64
            logerr = 0._real64
            losserr = 0._real64
            njudged = 0
            nmodes = 0
            do b = 1, 3
                do c = 1, 7
                    rel = max(rel, sqrt(sum((real(res%maps(:,:,:, c, b), real64)-expected(:,:,:, c, b))**2)/ &
                        &sum(expected(:,:,:, c, b)**2)))
                    lo = expected(res%ialpha(c, b), res%irot(c, b), res%irho(c, b), c, b)
                    losserr = nan_max(losserr, abs(real(res%loss(c, b), real64)-lo)/max(1._real64, abs(lo)))
                    logerr = nan_max(logerr, abs(real(res%logz(c, b), real64)-sm(c, b)%logz))
                    varerr = nan_max(varerr, abs(real(res%sdev(c, b), real64)**2-sm(c, b)%sdev**2))
                    bound = real(mb%temps(b), real64)*POLAR_MAP_CAP_L2*sqrt(sum(expected(:,:,:, c, b)**2))
                    if( sm(c, b)%margin > 2._real64*bound )then
                        njudged = njudged+1
                        if( res%ialpha(c, b) == sm(c, b)%ialpha .and. res%irot(c, b) == sm(c, b)%irot .and. &
                            &res%irho(c, b) == sm(c, b)%irho ) nmodes = nmodes+1
                    endif
                end do
            end do
            call assert_true(rel <= POLAR_MAP_CAP_L2 .and. losserr <= POLAR_MAP_CAP_L2, &
                &device_name(dev)//': the broadband maps and selected losses match the direct residual')
            call assert_true(logerr <= POLAR_MAP_CAP_LOG, 'the broadband evidence matches the host''s log-sum-exp')
            call assert_true(varerr <= POLAR_MAP_CAP_VAR*max(1._real64, maxval(fx%rho)**2), &
                &'the broadband widths match the host''s grid moments')
            call assert_int(njudged, nmodes, 'the broadband clear-margin modes equal the oracle''s')
            write(*,'(a,i0,a,i0)') '    grid ', grid, ' modes judged ', njudged
            call assert_true(njudged > 0, 'the broadband fixture has clear-margin modes to judge')
            call score_maps(pftc, mb, again, st)
            call assert_true(all(bits_equal(res%loss, again%loss)) .and. all(bits_equal(res%sdev, again%sdev)) .and. &
                &all(bits_equal(res%logz, again%logz)), 'a repeated fixed configuration is bit-identical')
            deallocate(expected)
        end do
        call pftc%kill
    end subroutine test_broadband_maps

    subroutine test_width_cutoff( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx
        type(polarft_calc)        :: pftc
        type(map_request)         :: mb
        type(polar_map_results)   :: base, res
        type(map_summary)         :: sm
        real(real64), allocatable :: expected(:,:,:)
        real(real64)              :: varerr, logerr
        integer                   :: st, mode, b, c
        logical                   :: keep(3, 3)
        write(*,'(a)') 'test_width_cutoff'
        fx = make_map_fixture(.false., .true.)
        call prepare_half(fx, pftc)
        mb = map_block(half_pids(1), same_cands(CANDS(:, 1), 3), [TEMP_T, TEMP_PHYS])
        mb%prior_w = PRIOR_SCREEN
        mb%temps = [3._real32, 9._real32, 27._real32]
        mb%temps_phys = [7._real32, 30._real32, 90._real32]
        mb%ptcl_tile = 2
        call score_maps(pftc, mb, base, st)
        call assert_int(0, st, 'cutoff-disabled reference succeeds')
        if( st /= 0 ) return
        varerr = 0._real64
        logerr = 0._real64
        do b = 1, 3
            do c = 1, 3
                expected = oracle_map(fx, mb%ptcl_ids(b), mb%cands(c, b))
                sm = summarize(fx, expected, [mb%temps(b), mb%temps_phys(b)], PRIOR_SCREEN)
                varerr = nan_max(varerr, abs(real(base%sdev(c, b), real64)**2 - sm%sdev**2))
                logerr = nan_max(logerr, abs(real(base%logz(c, b), real64) - sm%logz))
            end do
        end do
        call assert_true(varerr <= POLAR_MAP_CAP_VAR*max(1._real64, maxval(fx%rho)**2), &
            &'the uncut widths match independent heterogeneous physical moments')
        call assert_true(logerr <= POLAR_MAP_CAP_LOG, 'the uncut evidence matches independent tempered masses')
        do mode = 1, 4
            keep = .true.
            if( mode == 2 )then
                keep = .false.
                keep(1, 1) = .true.
                keep(3, 2) = .true.
                keep(2, 3) = .true.
            endif
            if( mode == 3 ) keep = .false.
            mb%width_cutoff = merge(huge(1._real32), -huge(1._real32), keep)
            ! Exact equality uses the same rounded loss as the cutoff contract; it must retain every width.
            if( mode == 4 ) mb%width_cutoff = base%loss
            mb%profile = mod(mode, 2) == 0
            call score_maps(pftc, mb, res, st)
            call assert_int(0, st, 'width cutoff succeeds')
            call assert_true(all(bits_equal(res%loss, base%loss)) .and. all(res%irot == base%irot) .and. &
                &all(res%ialpha == base%ialpha) .and. all(res%irho == base%irho), 'cutoffs preserve the tempered mode')
            call assert_true(all(abs(pack(res%sdev - base%sdev, keep)) <= real(POLAR_MAP_CAP_VAR, real32)), &
                &device_name(dev)//': retained pairs preserve physical-temperature widths')
            call assert_true(all(bits_equal(pack(res%sdev, .not. keep), -1._real32)), 'rejected widths are exactly -1')
            call assert_true(all(bits_equal(res%logz, base%logz)), 'cutoffs preserve requested tempered evidence')
        end do
        mb%width_cutoff = reshape([0._real32], [1, 1])
        call score_maps(pftc, mb, res, st)
        call assert_true(st /= 0 .and. index(pftc%message(), 'cutoff') > 0, 'a mismatched cutoff shape is refused')
        call pftc%kill
    end subroutine test_width_cutoff

    ! changed shell weights, a changed grid and a shorter band replace the map of the same references; unsorted
    ! radii are refused and leave no map
    subroutine test_map_repreparation( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx, changed
        type(polarft_calc)        :: pftc
        type(map_request)         :: mb
        type(polar_map_results)   :: res
        real(real64), allocatable :: expected(:,:,:)
        real(real64)              :: worst
        integer                   :: st, mode, b, c, h
        write(*,'(a)') 'test_map_repreparation'
        fx = make_map_fixture(.false., .true.)
        do h = 1, 2
            call prepare_half(fx, pftc)
            do mode = 1, 3
                changed = fx
                if( mode == 1 ) changed%w(2, h) = 3._real64 * changed%w(2, h)
                if( mode == 2 )then
                    changed%nalpha = 9
                    changed%rho = [0._real64, .3_real64, .8_real64]
                endif
                if( mode == 3 ) changed%nk = fx%nk - 1
                call pftc%set_sigma2_weights(changed%w(1:fx%nk, :))
                call pftc%memoize_ptcls
                call pftc%new_shiftmap(IMAP, changed%rho, changed%nalpha, fx%kfrom + changed%nk - 1)
                call assert_int(0, refused(pftc), 'the same references'' maps accept changed weights, grid or band')
                mb = map_block(half_pids(h), same_cands(CANDS(:, 1), size(half_pids(h))), [TEMP_T, TEMP_PHYS])
                mb%prior_w = PRIOR_SCREEN
                call score_maps(pftc, mb, res, st)
                call assert_int(0, st, 'rebuilt map state scores successfully')
                worst = 0._real64
                do b = 1, size(mb%ptcl_ids)
                    do c = 1, size(mb%cands, 1)
                        expected = oracle_map(changed, mb%ptcl_ids(b), mb%cands(c, b))
                        worst = max(worst, sqrt(sum((real(res%maps(:,:,:, c, b), real64)-expected)**2) / &
                            &sum(expected**2)))
                    end do
                end do
                call assert_true(worst <= POLAR_MAP_CAP_L2, device_name(dev)//': rebuilt metadata follows the direct oracle')
            end do
            call pftc%new_shiftmap(IMAP, [1._real64, 0._real64], changed%nalpha, fx%kfrom + changed%nk - 1)
            call assert_true(refused_for(pftc, 'ascend'), 'unsorted radii are explicitly refused')
            call score_maps(pftc, mb, res, st)
            call assert_true(st /= 0, 'an unsorted replacement leaves no stale map state')
        end do
        call pftc%kill
    end subroutine test_map_repreparation

    subroutine test_requested_outputs( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polarft_calc)      :: pftc
        type(map_request)       :: mb
        type(polar_map_results) :: base, profiled
        integer                 :: st, mode
        write(*,'(a)') 'test_requested_outputs'
        fx = make_map_fixture(.false., .true.)
        call prepare_half(fx, pftc)
        mb = map_block(half_pids(1), same_cands(CANDS(:, 1), 3), [TEMP_T, TEMP_PHYS])
        mb%prior_w = PRIOR_SCREEN
        mb%ptcl_tile = 2
        do mode = 0, 3
            mb%maps = btest(mode, 0)
            mb%evidence = btest(mode, 1)
            mb%profile = .false.
            call score_maps(pftc, mb, base, st)
            call assert_int(0, st, 'unprofiled requested outputs succeed')
            mb%profile = .true.
            call score_maps(pftc, mb, profiled, st)
            call assert_int(0, st, 'profiled requested outputs succeed')
            call assert_true(allocated(profiled%maps) .eqv. mb%maps, 'profiling returns maps only when requested')
            call assert_true(allocated(profiled%logz) .eqv. mb%evidence, 'profiling returns evidence only when requested')
            call assert_true(all(bits_equal(base%loss, profiled%loss)) .and. &
                &all(bits_equal(base%sdev, profiled%sdev)), device_name(dev)//': profiling preserves loss and width')
            call assert_true(all(base%irot == profiled%irot) .and. all(base%irho == profiled%irho) .and. &
                &all(base%ialpha == profiled%ialpha), 'profiling preserves selected poses')
            if( mb%evidence ) call assert_true(all(bits_equal(base%logz, profiled%logz)), 'profiling preserves evidence')
            if( mb%maps ) call assert_true(all(bits_equal(base%maps, profiled%maps)), 'profiling preserves maps')
        end do
        call pftc%kill
    end subroutine test_requested_outputs

    ! candidate permutations and duplicates give the same entry for the same pair, tiles of one and of two
    ! particles (three particles: the last tile partial) the entries of one graph, and three repeats identical
    ! entries
    subroutine test_candidates_and_tiles( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polarft_calc)      :: pftc
        type(map_request)       :: mb
        type(polar_map_results) :: r0, r1, r2
        integer, allocatable    :: pids(:)
        integer                 :: st, b, c, c2, rep, ptile
        logical                 :: same_idx, same_vals, ident
        write(*,'(a)') 'test_candidates_and_tiles'
        fx   = make_map_fixture(.false., .true.)
        pids = half_pids(1)
        call prepare_half(fx, pftc)
        mb = map_block(pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
        mb%prior_w = PRIOR_SCREEN
        mb%maps = .false.
        call score_maps(pftc, mb, r0, st)
        call assert_true(loss_error(fx, pids, mb%cands, r0) <= POLAR_MAP_CAP_L2, device_name(dev)//': without maps, '//&
            &'every returned loss is the direct residual at the returned pose')
        ! the same pairs in another order and with a duplicate
        same_idx  = .true.
        same_vals = .true.
        do rep = 2, 3
            mb%cands = same_cands(CANDS(:, rep), size(pids))
            call score_maps(pftc, mb, r1, st)
            do b = 1, size(pids)
                do c = 1, 3
                    c2 = findloc(CANDS(:, 1), CANDS(c, rep), dim=1)
                    same_idx  = same_idx .and. r1%irot(c, b) == r0%irot(c2, b) .and. r1%irho(c, b) == r0%irho(c2, b) &
                        &.and. r1%ialpha(c, b) == r0%ialpha(c2, b)
                    same_vals = same_vals .and. abs(r1%loss(c, b) - r0%loss(c2, b)) <= &
                        &real(POLAR_MAP_CAP_L2, real32) * max(1._real32, abs(r0%loss(c2, b)))
                end do
            end do
        end do
        call assert_true(same_idx, device_name(dev)//': permuted and duplicated candidates give the same modes')
        call assert_true(same_vals, device_name(dev)//': permuted and duplicated candidates give the same losses')
        ! tiles of one and of two particles (the last one partial)
        mb%cands = same_cands(CANDS(:, 1), size(pids))
        same_idx  = .true.
        same_vals = .true.
        do ptile = 1, 2
            mb%ptcl_tile = ptile
            call score_maps(pftc, mb, r1, st)
            same_idx  = same_idx .and. all(r1%irot == r0%irot) .and. all(r1%irho == r0%irho) .and. &
                &all(r1%ialpha == r0%ialpha)
            same_vals = same_vals .and. all(abs(r1%loss - r0%loss) <= real(POLAR_MAP_CAP_L2, real32) * &
                &max(1._real32, abs(r0%loss)))
        end do
        call assert_true(same_idx, device_name(dev)//': tiles of one and of two particles give the same modes')
        call assert_true(same_vals, device_name(dev)//': tiles of one and of two particles give the same losses')
        ! three repeats at fixed inputs: identical entries, bit for bit
        mb%ptcl_tile = 16
        ident    = .true.
        do rep = 1, 3
            call score_maps(pftc, mb, r2, st)
            ident = ident .and. all(bits_equal(r2%loss, r0%loss)) .and. all(bits_equal(r2%sdev, r0%sdev)) .and. &
                &all(bits_equal(r2%logz, r0%logz)) .and. all(r2%irot == r0%irot) .and. all(r2%irho == r0%irho) .and. &
                &all(r2%ialpha == r0%ialpha)
        end do
        call assert_true(ident, device_name(dev)//': three repeats give identical results')
        call pftc%kill
    end subroutine test_candidates_and_tiles

    ! what does not match the calculator's state is refused; maps need memoized references and particles and
    ! their own preparation; references that change are memoized again with their maps, which then match the
    ! oracle of the new references
    subroutine test_refusals_rebuild( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx, fb
        type(polarft_calc)        :: pftc
        type(map_request)         :: mb, bad
        type(polar_map_results)   :: res
        real(real32), allocatable :: rows(:,:,:)
        real(real64), allocatable :: lor(:,:,:)
        real(real64)              :: worst
        integer,      allocatable :: pids(:)
        integer                   :: st, b, c, nbad, kstop
        write(*,'(a)') 'test_refusals_rebuild'
        fx    = make_map_fixture(.false., .true.)
        pids  = half_pids(1)
        kstop = fx%kfrom + fx%nk - 1
        mb    = map_block(pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
        call feed_calc(pftc, fx, nbad)
        call score_maps(pftc, mb, res, st)
        call assert_true(st /= 0, device_name(dev)//': a calculator without maps refuses them')
        call prepare_half(fx, pftc)
        bad = mb
        bad%ptcl_ids(1) = 2
        call score_maps(pftc, bad, res, st)
        call assert_true(st /= 0 .and. refused_for(pftc, 'halves'), device_name(dev)//': maps of particles of '//&
            &'both halves are refused')
        nbad = set_ptcl(pftc, fx, pids(1))
        call score_maps(pftc, mb, res, st)
        call assert_true(st /= 0 .and. refused_for(pftc, 'memoize_ptcls'), device_name(dev)//': maps are refused '//&
            &'when a particle was set and the particles were not memoized again')
        call pftc%memoize_ptcls
        bad = mb
        bad%cands(1, 1) = NREF + 1
        call score_maps(pftc, bad, res, st)
        call assert_true(st /= 0 .and. refused_for(pftc, 'candidate'), device_name(dev)//': a candidate '//&
            &'outside the calculator''s references is refused')
        ! a refused replacement of the map leaves no map and the dense scoring intact
        call pftc%new_shiftmap(IMAP, fx%rho, fx%nalpha, kstop + 1)
        call assert_true(refused_for(pftc, 'band'), device_name(dev)//': a map whose last shell is beyond '//&
            &'the band is refused')
        call score_maps(pftc, mb, res, st)
        call assert_true(st /= 0, device_name(dev)//': after a refused preparation the earlier maps are gone')
        call dense_rows(pftc, pids, rows, st)
        call assert_int(0, st, device_name(dev)//': a refused map preparation leaves the dense scoring intact')
        call pftc%new_shiftmap(IMAP, fx%rho, 0, kstop)
        call assert_true(refused_for(pftc, 'direction'), device_name(dev)//': a map without a direction '//&
            &'is refused')
        call pftc%new_shiftmap(NSHIFTMAPS + 1, fx%rho, fx%nalpha, kstop)
        call assert_true(refused_for(pftc, 'no such shift map'), device_name(dev)//': a map outside the '//&
            &'calculator''s maps is refused')
        call pftc%new_shiftmap(IMAP, fx%rho, fx%nalpha, kstop)
        call assert_int(0, refused(pftc), device_name(dev)//': the maps are prepared again after the refusals')
        call score_maps(pftc, mb, res, st)
        call assert_int(0, st, device_name(dev)//': the maps prepared again are scored')
        ! the references change (rings scaled by 1.1): memoized again, their maps are stale until made again
        fb = fx
        fb%rref = 1.1_real32 * fx%rref
        nbad = set_refs(pftc, fb, 1) + set_refs(pftc, fb, 2)
        call pftc%memoize_refs
        call score_maps(pftc, mb, res, st)
        call assert_true(st /= 0, device_name(dev)//': after the references are memoized again their maps are refused')
        call prepare_half(fb, pftc)
        call score_maps(pftc, mb, res, st)
        call assert_int(0, st, 'the rebuilt maps are scored')
        if( st /= 0 ) return
        worst = 0._real64
        do b = 1, size(pids)
            do c = 1, size(CANDS, 1)
                lor   = oracle_map(fb, pids(b), CANDS(c, 1))
                worst = max(worst, sqrt(sum((real(res%maps(:, :, :, c, b), real64) - lor)**2)) / sqrt(sum(lor**2)))
            end do
        end do
        call assert_true(worst <= POLAR_MAP_CAP_L2, device_name(dev)//': the rebuilt maps follow the new references')
        call pftc%kill
    end subroutine test_refusals_rebuild

    ! after a warm cycle, 100 create/use/kill cycles of the workspace with maps return the live count and the
    ! active memory to their warm values
    subroutine test_lifecycle( dev )
        integer, intent(in) :: dev
        type(map_fixture) :: fx
        integer(int64)    :: mem0
        integer           :: live0, it, nbad
        write(*,'(a)') 'test_lifecycle (100 cycles)'
        fx   = make_map_fixture(.true., .true.)
        nbad = 0
        call map_cycle(fx, nbad)
        call mlx_synchronize()
        call mlx_clear_cache()
        mem0  = mlx_active_memory()
        live0 = mlx_live_count()
        do it = 1, 100
            call map_cycle(fx, nbad)
        end do
        call mlx_synchronize()
        call mlx_clear_cache()
        call assert_int(0, nbad, device_name(dev)//': every cycle prepares and scores its maps')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': the live count returns to its warm value')
        call assert_true(mlx_active_memory() == mem0, device_name(dev)//': the active memory returns to its warm '//&
            &'value')
    end subroutine test_lifecycle

    ! one calculator: fed, the two coarse maps set up on SIMPLE's grid (the band's last shell and the prior's
    ! weight as SIMPLE defines them), the screen's maps of two particles read, killed; nbad counts what failed
    ! after the setup
    subroutine map_cycle( fx, nbad )
        type(map_fixture), intent(in)    :: fx
        integer,           intent(inout) :: nbad
        type(polarft_calc)   :: pftc
        real(real64)         :: prior_w, temp(6), tph(6), sigma_px
        real(real32)         :: loss(6), sdev(6)
        integer              :: irot(6), irho(6), ialpha(6), kscreen, n
        call feed_calc(pftc, fx, n)
        call assert_int(0, n, 'the references and particles are set and memoized: '//pftc%message())
        sigma_px = 2._real64
        call pftc%setup_shiftmaps(sigma_px, 3._real64 * sigma_px, 4._real64, prior_w, kscreen)
        call assert_int(0, refused(pftc), 'the two coarse maps are set up: '//pftc%message())
        if( kscreen /= max(fx%kfrom + 1, (fx%kfrom + fx%nk - 1) / 2) ) nbad = nbad + 1
        if( abs(prior_w - 1._real64 / (2._real64 * sigma_px**2)) > 1.e-15_real64 ) nbad = nbad + 1
        temp = real(TEMP_T, real64)
        tph  = real(TEMP_PHYS, real64)
        call pftc%gen_shiftmap(SHIFTMAP_SCREEN, [CANDS(:, 1), CANDS(:, 1)], [1, 1, 1, 3, 3, 3])
        nbad = nbad + refused(pftc)
        call pftc%shiftmap_mode(SHIFTMAP_SCREEN, temp, prior_w, irot, irho, ialpha, loss, temp_phys=tph, sdev=sdev)
        nbad = nbad + refused(pftc)
        if( any(irot < 1 .or. irot > fx%nrot) .or. any(irho < 1) .or. any(ialpha < 1) .or. any(sdev < 0._real32) ) &
            &nbad = nbad + 1
        call pftc%kill
    end subroutine map_cycle

    ! an exact tie: constant rings, the particle its reference times the CTF, unshifted, at a high temperature: every
    ! cell of the first ring has the same loss bit for bit, at every rotation and direction, and the mode is the first
    ! of them in SIMPLE's order, (rotation 1, ring 1, direction 1)
    subroutine test_mode_ties( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polarft_calc)      :: pftc
        type(map_request)       :: mb
        type(polar_map_results) :: res
        integer                 :: st, k, j, h, i
        write(*,'(a)') 'test_mode_ties'
        fx = make_map_fixture(.false., .false.)
        do h = 1, 2
            do j = 1, NREF
                do k = 1, fx%nk
                    fx%rref(:, k, j, h) = cmplx(1._real32 + 0.1_real32 * real(k + j, real32), 0._real32, real32)
                end do
            end do
        end do
        do i = 1, NPTCL
            do k = 1, fx%nk
                fx%x(:, k, i) = fx%ctf(:, k, i) * fx%rref(:, k, 1, 2 - mod(i, 2))
            end do
        end do
        call prepare_half(fx, pftc)
        mb = map_block([1], reshape([1], [1, 1]), [1.e4_real32, TEMP_PHYS])
        call score_maps(pftc, mb, res, st)
        call assert_int(0, st, 'the tie fixture is scored')
        if( st /= 0 ) return
        write(*,'(a,3(i0,a))') '    tie fixture: mode (', res%irot(1, 1), ', ', res%irho(1, 1), ', ', res%ialpha(1, 1), ')'
        call assert_true(all(bits_equal(res%maps(:, :, 1, 1, 1), res%maps(1, 1, 1, 1, 1))), device_name(dev)//': the '//&
            &'first ring''s cells tie bit for bit')
        call assert_true(res%irot(1, 1) == 1 .and. res%irho(1, 1) == 1 .and. res%ialpha(1, 1) == 1, device_name(dev)//&
            &': a tie goes to the first cell in SIMPLE''s order')
        call pftc%kill
    end subroutine test_mode_ties

    ! a variate in [-1, 1) keyed by its indices and the seed, the same on every machine
    pure real(real64) function keyed( seed, m, k, i, part )
        integer, intent(in) :: seed, m, k, i, part
        real(real64) :: x
        x = sin(12.9898_real64 * real(m, real64) + 78.233_real64 * real(k, real64) + 37.719_real64 * real(i, real64) + &
            &4.581_real64 * real(part, real64) + 91.17_real64 * real(seed, real64)) * 43758.5453_real64
        keyed = 2._real64 * (x - real(floor(x), real64)) - 1._real64
    end function keyed

    ! the perturbed fixture with keyed noise of SEED_NOISE times each particle ring's rms, keyed by seed
    function seeded_fixture( seed ) result(fx)
        integer, intent(in) :: seed
        type(map_fixture) :: fx
        real(real64)      :: rms
        integer           :: i, k, m
        fx = make_map_fixture(.false., .true.)
        do i = 1, NPTCL
            do k = 1, fx%nk
                rms = sqrt(sum(abs(real(fx%x(:, k, i), real64))**2 + abs(aimag(fx%x(:, k, i)))**2) / &
                    &real(fx%pftsz, real64))
                do m = 1, fx%pftsz
                    fx%x(m, k, i) = fx%x(m, k, i) + cmplx(SEED_NOISE * rms * keyed(seed, m, k, i, 1), &
                        &SEED_NOISE * rms * keyed(seed, m, k, i, 2), real32)
                end do
            end do
        end do
    end function seeded_fixture

    ! on seeds 1 (calibration), 2 and 3 (judged) of the noisy fixture, each pair's width (its variance) and log
    ! evidence against the host oracle's under the frozen caps
    subroutine test_seeded_widths( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polarft_calc)      :: pftc
        type(map_request)       :: mb
        type(polar_map_results) :: res
        type(map_summary)       :: sm
        real(real64)            :: varerr, logerr
        integer                 :: seed, st, b, c
        write(*,'(a)') 'test_seeded_widths'
        do seed = 1, 3
            fx = seeded_fixture(seed)
            call prepare_half(fx, pftc)
            mb = map_block(half_pids(1), same_cands(CANDS(:, 1), size(half_pids(1))), [TEMP_T, TEMP_PHYS])
            mb%prior_w = PRIOR_SCREEN
            call score_maps(pftc, mb, res, st)
            call assert_int(0, st, 'the seeded fixture is scored: '//pftc%message())
            call pftc%kill
            if( st /= 0 ) return
            varerr = 0._real64
            logerr = 0._real64
            do b = 1, size(mb%ptcl_ids)
                do c = 1, size(mb%cands, 1)
                    sm = summarize(fx, oracle_map(fx, mb%ptcl_ids(b), mb%cands(c, b)), [TEMP_T, TEMP_PHYS], PRIOR_SCREEN)
                    varerr = nan_max(varerr, abs(real(res%sdev(c, b), real64)**2 - sm%sdev**2))
                    logerr = nan_max(logerr, abs(real(res%logz(c, b), real64) - sm%logz))
                end do
            end do
            write(*,'(a,i0,a,es10.3,a,es10.3)') '    seed ', seed, ': variance error ', varerr, ', log evidence error ', &
                &logerr
            call assert_true(varerr <= POLAR_MAP_CAP_VAR * max(1._real64, maxval(fx%rho)**2), device_name(dev)//&
                &': the seeded widths match the oracle''s within the variance cap')
            call assert_true(logerr <= POLAR_MAP_CAP_LOG, device_name(dev)//': the seeded evidence matches the oracle''s')
        end do
    end subroutine test_seeded_widths

end module mlxf_toy_polarft_shiftmap_tester
