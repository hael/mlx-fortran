!@descr: tests of the polar table's shift maps: analytic ring fixtures, the direct residual oracle, mode, width, evidence
! The fixtures are analytic (no random numbers): low-harmonic Friedel-symmetric reference rings, angularly varying
! CTFs, particles as a reference shifted in its own frame, rotated and multiplied by its CTF. The oracle evaluates
! the normalised residual L = sum w |X - C R_pose|^2 / sum w |X|^2 directly at every grid point in real64, with no
! Bessel table and no transform, and the mode, width and evidence from those maps on the host.
module mlxf_kernel_polar_table_shiftmap_tester
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,                     only: mlx_set_default_device, mlx_default_device, mlx_live_count, mlx_active_memory, &
                                    mlx_synchronize, mlx_clear_cache
use mlxf_test_defs,           only: POLAR_MAP_CAP_L2, POLAR_MAP_CAP_LOG, POLAR_MAP_CAP_VAR, POLAR_MAP_LOG_CUT, &
                                    polar_table_refs, polar_table_block, polar_table_entries, polar_map_spec, &
                                    polar_map_block, polar_map_results
use mlxf_kernel_polar_table,  only: polar_table
use mlxf_kernel_polar_oracle, only: polar_full_ring, polar_dft_matrix, polar_dft_bins
use mlxf_test_utils,          only: assert_true, assert_int, device_name, bits_equal, test_devices
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

! one analytic fixture: rings (half ring, rounded), CTFs, weights per half, the memos, the grid
type :: map_fixture
    integer                      :: nrot = 0, pftsz = 0, nk = 0, box = 0, nalpha = 0, kfrom = 1
    logical                      :: perturbed = .false.
    real(real64),    allocatable :: rho(:)
    real(real64),    allocatable :: w(:,:)
    complex(real32), allocatable :: rref(:,:,:,:)
    complex(real32), allocatable :: x(:,:,:)
    real(real32),    allocatable :: ctf(:,:,:)
    real(real64),    allocatable :: ptclpow(:)
    complex(real32), allocatable :: ft_ref(:,:,:,:)
    complex(real32), allocatable :: ft_ref2(:,:,:,:)
    complex(real32), allocatable :: ctf2(:,:,:)
    complex(real32), allocatable :: xctf(:,:,:)
end type map_fixture

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
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_polar_shiftmap_tests

    subroutine run_all_polar_shiftmap_accuracy_tests
        type(map_fixture)       :: fx
        type(polar_table)       :: ws
        type(polar_map_block)   :: mb
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
                    call prepare_half(fx, h, PRIOR_SCREEN, ws)
                    mb = map_block(fx, [h], reshape([2, 7], [2, 1]), [TEMP_T, TEMP_PHYS])
                    call ws%score_maps(mb, res, st)
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
        call ws%kill()
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
        allocate(fx%w(nk, 2), fx%rref(fx%pftsz, nk, NREF, 2), fx%x(fx%pftsz, nk, NPTCL), fx%ctf(fx%pftsz, nk, NPTCL), &
            &fx%ptclpow(NPTCL))
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
        call fixture_memos(fx)
    end function make_map_fixture

    ! the memos by a double-precision DFT of the rounded rings, rounded once; the particles' weighted powers
    subroutine fixture_memos( fx )
        type(map_fixture), intent(inout) :: fx
        complex(real64), allocatable :: e(:,:), z(:)
        integer                      :: h, j, k, i, n1
        n1 = fx%pftsz + 1
        allocate(e(n1, fx%nrot))
        e  = polar_dft_matrix(fx%nrot, n1)
        if( allocated(fx%ft_ref) ) deallocate(fx%ft_ref, fx%ft_ref2, fx%ctf2, fx%xctf)
        allocate(fx%ft_ref(n1, fx%nk, NREF, 2), fx%ft_ref2(n1, fx%nk, NREF, 2), fx%ctf2(n1, fx%nk, NPTCL), &
            &fx%xctf(n1, fx%nk, NPTCL))
        do h = 1, 2
            do j = 1, NREF
                do k = 1, fx%nk
                    z = cmplx(fx%rref(:, k, j, h), kind=real64)
                    fx%ft_ref(:, k, j, h)  = cmplx(polar_dft_bins(e, polar_full_ring(z)), kind=real32)
                    z = cmplx(abs(z)**2, 0._real64, real64)
                    fx%ft_ref2(:, k, j, h) = cmplx(conjg(polar_dft_bins(e, polar_full_ring(z))), kind=real32)
                end do
            end do
        end do
        do i = 1, NPTCL
            h = 2 - mod(i, 2)
            fx%ptclpow(i) = 0._real64
            do k = 1, fx%nk
                z = cmplx(real(fx%ctf(:, k, i), real64)**2, 0._real64, real64)
                fx%ctf2(:, k, i) = cmplx(polar_dft_bins(e, polar_full_ring(z)), kind=real32)
                z = cmplx(fx%x(:, k, i), kind=real64) * real(fx%ctf(:, k, i), real64)
                fx%xctf(:, k, i) = cmplx(polar_dft_bins(e, polar_full_ring(z)), kind=real32)
                fx%ptclpow(i) = fx%ptclpow(i) + fx%w(k, h) * sum(abs(cmplx(fx%x(:, k, i), kind=real64))**2)
            end do
        end do
    end subroutine fixture_memos

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

    ! ---- the workspace ---------------------------------------------------------------------------------

    ! the references of half h as the workspace takes them
    function half_refs( fx, h ) result(refs)
        type(map_fixture), intent(in) :: fx
        integer,           intent(in) :: h
        type(polar_table_refs) :: refs
        integer                :: j
        refs%pftsz      = fx%pftsz
        refs%nk         = fx%nk
        refs%half       = h
        refs%rt         = 4
        refs%bt         = 2
        refs%generation = 1_int64
        refs%ids        = [(j, j = 1, NREF)]
        refs%ft_ref     = fx%ft_ref(:, :, :, h)
        refs%ft_ref2    = fx%ft_ref2(:, :, :, h)
    end function half_refs

    ! the maps' grid over every shell of half h, prior prior_w
    function half_spec( fx, h, prior_w ) result(spec)
        type(map_fixture), intent(in) :: fx
        integer,           intent(in) :: h
        real(real64),      intent(in) :: prior_w
        type(polar_map_spec) :: spec
        spec%box     = fx%box
        spec%kfrom   = fx%kfrom
        spec%kstop   = fx%kfrom + fx%nk - 1
        spec%nalpha  = fx%nalpha
        spec%prior_w = prior_w
        spec%rho     = fx%rho
        spec%weights = fx%w(:, h)
    end function half_spec

    ! the references of half h prepared, then the maps over every shell, prior prior_w
    subroutine prepare_half( fx, h, prior_w, ws )
        type(map_fixture), intent(in)    :: fx
        integer,           intent(in)    :: h
        real(real64),      intent(in)    :: prior_w
        type(polar_table), intent(inout) :: ws
        integer :: st
        call ws%new(half_refs(fx, h), st)
        call assert_int(0, st, 'the references are prepared: '//ws%message())
        call ws%prepare_maps(half_refs(fx, h), half_spec(fx, h, prior_w), st)
        call assert_int(0, st, 'the maps are prepared: '//ws%message())
    end subroutine prepare_half

    ! the dense block of particles pids (one half) against every reference, zero temperature, rows kept
    function dense_block( fx, pids ) result(blk)
        type(map_fixture), intent(in) :: fx
        integer,           intent(in) :: pids(:)
        type(polar_table_block) :: blk
        integer                 :: j, h
        h              = 2 - mod(pids(1), 2)
        blk%half       = h
        blk%generation = 1_int64
        blk%ref_ids    = [(j, j = 1, NREF)]
        blk%ptcl_ids   = pids
        blk%weights    = real(fx%w(:, h), real32)
        blk%ctf2       = fx%ctf2(:, :, pids)
        blk%xctf       = fx%xctf(:, :, pids)
        blk%wsq        = fx%ptclpow(pids)
        allocate(blk%temps(size(pids)), blk%u(NREF, size(pids)))
        blk%temps = 0._real32
        blk%u     = 0.5_real32
        blk%rows  = .true.
    end function dense_block

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
                worst = max(worst, abs(real(res%loss(c, b), real64) - lo) / max(1._real64, abs(lo)))
            end do
        end do
    end function loss_error

    ! the map block of particles pids (one half) against candidate lists cands(:, b)
    function map_block( fx, pids, cands, temps ) result(mb)
        type(map_fixture), intent(in) :: fx
        integer,           intent(in) :: pids(:), cands(:,:)
        real(real32),      intent(in) :: temps(2)
        type(polar_map_block) :: mb
        mb%half       = 2 - mod(pids(1), 2)
        mb%generation = 1_int64
        mb%ptcl_ids   = pids
        mb%cands      = cands
        mb%ctf2       = fx%ctf2(:, :, pids)
        mb%xctf       = fx%xctf(:, :, pids)
        mb%ptclpow    = fx%ptclpow(pids)
        allocate(mb%temps(size(pids)), mb%temps_phys(size(pids)))
        mb%temps      = temps(1)
        mb%temps_phys = temps(2)
        mb%maps       = .true.
        mb%evidence   = .true.
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
        type(polar_table)             :: ws
        type(polar_map_block)         :: mb
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
            call prepare_half(fx, h, 0._real64, ws)
            mb = map_block(fx, pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
            call ws%score_maps(mb, res, st)
            call assert_int(0, st, device_name(dev)//' maps are scored: '//ws%message())
            if( st /= 0 ) return
            worst_loss = max(worst_loss, loss_error(fx, pids, same_cands(CANDS(:, 1), size(pids)), res))
            do b = 1, size(pids)
                do c = 1, size(CANDS, 1)
                    lor = oracle_map(fx, pids(b), CANDS(c, 1))
                    rel = sqrt(sum((real(res%maps(:, :, :, c, b), real64) - lor)**2)) / sqrt(sum(lor**2))
                    worst_rel = max(worst_rel, rel)
                    worst_abs = max(worst_abs, maxval(abs(real(res%maps(:, :, :, c, b), real64) - lor)))
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
                call ws%score_maps(mb, res, st)
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
            call ws%kill()
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
        type(polar_table)         :: ws
        type(polar_map_block)     :: mb
        type(polar_map_results)   :: res
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: ent
        real(real64)              :: dmax, worst, spread
        integer, allocatable      :: pids(:)
        integer                   :: st, b, c, ir, j
        write(*,'(a)') 'test_zero_radius'
        fx   = make_map_fixture(.false., .true.)
        pids = half_pids(1)
        call prepare_half(fx, 1, 0._real64, ws)
        mb = map_block(fx, pids, same_cands([(j, j = 1, NREF)], size(pids)), [TEMP_T, TEMP_PHYS])
        call ws%score_maps(mb, res, st)
        blk = dense_block(fx, pids)
        call ws%score(blk, ent, st)
        call assert_int(0, st, 'the dense rows are scored')
        if( st /= 0 ) return
        worst  = 0._real64
        spread = 0._real64
        do b = 1, size(pids)
            do c = 1, NREF
                dmax = maxval(abs(real(ent%rows(:, c, b), real64)))
                do ir = 1, fx%nrot
                    worst  = max(worst, abs(real(res%maps(1, ir, 1, c, b), real64) - &
                        &real(ent%rows(ir, c, b), real64)) / dmax)
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
        call ws%kill()
    end subroutine test_zero_radius

    ! the folding case: 8 ring positions, box 16, shells 1..3, radii 0, 4, 8, 7 directions: the kept orders exceed
    ! both transform axes, so they must be folded, and every map matches the oracle
    subroutine test_folding( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx
        type(polar_table)         :: ws
        type(polar_map_block)     :: mb
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
            call prepare_half(fx, h, 0._real64, ws)
            norder = ws%map_order()
            call assert_true(norder > max(fx%nalpha, fx%nrot), 'the folding case keeps orders beyond both '//&
                &'transform axes')
            mb = map_block(fx, pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
            call ws%score_maps(mb, res, st)
            call assert_int(0, st, 'the folding case is scored')
            if( st /= 0 ) return
            do b = 1, size(pids)
                do c = 1, size(CANDS, 1)
                    lor   = oracle_map(fx, pids(b), CANDS(c, 1))
                    worst = max(worst, sqrt(sum((real(res%maps(:, :, :, c, b), real64) - lor)**2)) / sqrt(sum(lor**2)))
                end do
            end do
            call ws%kill()
        end do
        write(*,'(a,i0,a,es10.3)') '    folding: orders 0..', norder, ' kept; largest map error ', worst
        call assert_true(worst <= POLAR_MAP_CAP_L2, device_name(dev)//': the folded maps match the direct residual')
    end subroutine test_folding

    ! the alternating Nyquist ring, unit CTF, equal rings: loss 0 at the identity and 4 one angular step away
    subroutine test_nyquist( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polar_table)       :: ws
        type(polar_map_block)   :: mb
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
        call fixture_memos(fx)
        call prepare_half(fx, 1, 0._real64, ws)
        mb = map_block(fx, [1], reshape([1], [1, 1]), [TEMP_T, TEMP_PHYS])
        call ws%score_maps(mb, res, st)
        call assert_int(0, st, 'the Nyquist ring is scored')
        if( st /= 0 ) return
        write(*,'(a,es12.5,a,es12.5)') '    Nyquist ring: loss at the identity ', res%maps(1, 1, 1, 1, 1), &
            &', one step away ', res%maps(1, 2, 1, 1, 1)
        call assert_true(abs(res%maps(1, 1, 1, 1, 1)) <= 4._real32 * real(POLAR_MAP_CAP_L2, real32), &
            &device_name(dev)//': the Nyquist ring has loss 0 at the identity')
        call assert_true(abs(res%maps(1, 2, 1, 1, 1) - 4._real32) <= 4._real32 * real(POLAR_MAP_CAP_L2, real32), &
            &device_name(dev)//': the Nyquist ring has loss 4 one angular step away')
        call ws%kill()
    end subroutine test_nyquist

    ! the log evidence and the width against the host's log-sum-exp and grid moments of the oracle's maps: no
    ! prior, the screen's prior, and a flat likelihood (zero temperatures: the prior alone, evidence 0); the
    ! width at the physical temperature, distinct from the tempered one
    subroutine test_evidence_width( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx
        type(polar_table)         :: ws
        type(polar_map_block)     :: mb
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
            call prepare_half(fx, 1, prior_w, ws)
            mb = map_block(fx, pids, same_cands(CANDS(:, 1), size(pids)), temps)
            call ws%score_maps(mb, res, st)
            call assert_int(0, st, 'the evidence case is scored')
            if( st /= 0 ) return
            do b = 1, size(pids)
                do c = 1, size(CANDS, 1)
                    lor = oracle_map(fx, pids(b), CANDS(c, 1))
                    sm  = summarize(fx, lor, temps, prior_w)
                    worst_logz = max(worst_logz, abs(real(res%logz(c, b), real64) - sm%logz))
                    worst_var  = max(worst_var, abs(real(res%sdev(c, b), real64)**2 - sm%sdev**2))
                    if( icase == 1 )then
                        smt   = summarize(fx, lor, [temps(1), temps(1)], prior_w)
                        tdiff = max(tdiff, abs(smt%sdev**2 - sm%sdev**2))
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
            call ws%kill()
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
        type(polar_table)         :: ws
        type(polar_map_block)     :: mb
        type(polar_map_results)   :: res, again
        type(map_summary)         :: sm(7, 3)
        real(real64), allocatable :: expected(:,:,:,:,:)
        real(real64)              :: rel, varerr, logerr, losserr, bound, lo
        integer                   :: grid, c, b, st, njudged, nmodes
        write(*,'(a)') 'test_broadband_maps'
        do grid = 1, 2
            fx = make_map_fixture(grid == 2, .true., broadband=.true.)
            call prepare_half(fx, 1, PRIOR_SCREEN, ws)
            mb = map_block(fx, half_pids(1), LISTS, [TEMP_T, TEMP_PHYS])
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
            call ws%score_maps(mb, res, st)
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
                    losserr = max(losserr, abs(real(res%loss(c, b), real64)-lo)/max(1._real64, abs(lo)))
                    logerr = max(logerr, abs(real(res%logz(c, b), real64)-sm(c, b)%logz))
                    varerr = max(varerr, abs(real(res%sdev(c, b), real64)**2-sm(c, b)%sdev**2))
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
            call ws%score_maps(mb, again, st)
            call assert_true(all(bits_equal(res%loss, again%loss)) .and. all(bits_equal(res%sdev, again%sdev)) .and. &
                &all(bits_equal(res%logz, again%logz)), 'a repeated fixed configuration is bit-identical')
            deallocate(expected)
        end do
        call ws%kill()
    end subroutine test_broadband_maps

    subroutine test_width_cutoff( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx
        type(polar_table)         :: ws
        type(polar_map_block)     :: mb
        type(polar_map_results)   :: base, res
        type(map_summary)         :: sm
        real(real64), allocatable :: expected(:,:,:)
        real(real64)              :: varerr, logerr
        integer                   :: st, mode, b, c
        logical                   :: keep(3, 3)
        write(*,'(a)') 'test_width_cutoff'
        fx = make_map_fixture(.false., .true.)
        call prepare_half(fx, 1, PRIOR_SCREEN, ws)
        mb = map_block(fx, half_pids(1), same_cands(CANDS(:, 1), 3), [TEMP_T, TEMP_PHYS])
        mb%temps = [3._real32, 9._real32, 27._real32]
        mb%temps_phys = [7._real32, 30._real32, 90._real32]
        mb%ptcl_tile = 2
        call ws%score_maps(mb, base, st)
        call assert_int(0, st, 'cutoff-disabled reference succeeds')
        if( st /= 0 ) return
        varerr = 0._real64
        logerr = 0._real64
        do b = 1, 3
            do c = 1, 3
                expected = oracle_map(fx, mb%ptcl_ids(b), mb%cands(c, b))
                sm = summarize(fx, expected, [mb%temps(b), mb%temps_phys(b)], PRIOR_SCREEN)
                varerr = max(varerr, abs(real(base%sdev(c, b), real64)**2 - sm%sdev**2))
                logerr = max(logerr, abs(real(base%logz(c, b), real64) - sm%logz))
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
            call ws%score_maps(mb, res, st)
            call assert_int(0, st, 'width cutoff succeeds')
            call assert_true(all(bits_equal(res%loss, base%loss)) .and. all(res%irot == base%irot) .and. &
                &all(res%ialpha == base%ialpha) .and. all(res%irho == base%irho), 'cutoffs preserve the tempered mode')
            call assert_true(all(abs(pack(res%sdev - base%sdev, keep)) <= real(POLAR_MAP_CAP_VAR, real32)), &
                &device_name(dev)//': retained pairs preserve physical-temperature widths')
            call assert_true(all(bits_equal(pack(res%sdev, .not. keep), -1._real32)), 'rejected widths are exactly -1')
            call assert_true(all(bits_equal(res%logz, base%logz)), 'cutoffs preserve requested tempered evidence')
        end do
        mb%width_cutoff = reshape([0._real32], [1, 1])
        call ws%score_maps(mb, res, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'cutoff') > 0, 'a mismatched cutoff shape is refused')
        call ws%kill()
    end subroutine test_width_cutoff

    subroutine test_map_repreparation( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx, changed
        type(polar_table)         :: ws
        type(polar_table_refs)    :: refs
        type(polar_map_spec)      :: spec
        type(polar_map_block)     :: mb
        type(polar_map_results)   :: res
        real(real64), allocatable :: expected(:,:,:)
        real(real64)              :: worst
        integer                   :: st, mode, b, c, h
        write(*,'(a)') 'test_map_repreparation'
        fx = make_map_fixture(.false., .true.)
        do h = 1, 2
            call prepare_half(fx, h, PRIOR_SCREEN, ws)
            refs = half_refs(fx, h)
            do mode = 1, 3
                changed = fx
                if( mode == 1 ) changed%w(2, h) = 3._real64 * changed%w(2, h)
                if( mode == 2 )then
                    changed%nalpha = 9
                    changed%rho = [0._real64, .3_real64, .8_real64]
                endif
                if( mode == 3 ) changed%nk = fx%nk - 1
                call fixture_memos(changed)
                spec = half_spec(changed, h, PRIOR_SCREEN)
                spec%weights = changed%w(1:changed%nk, h)
                call ws%prepare_maps(refs, spec, st)
                call assert_int(0, st, 'same-generation maps accept changed weights, grid or band')
                mb = map_block(fx, half_pids(h), same_cands(CANDS(:, 1), size(half_pids(h))), [TEMP_T, TEMP_PHYS])
                mb%ptclpow = changed%ptclpow(half_pids(h))
                call ws%score_maps(mb, res, st)
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
            spec%rho = [1._real64, 0._real64]
            call ws%prepare_maps(refs, spec, st)
            call assert_true(st /= 0 .and. index(ws%message(), 'ascend') > 0, 'unsorted radii are explicitly refused')
            call ws%score_maps(mb, res, st)
            call assert_true(st /= 0, 'an unsorted replacement leaves no stale map state')
        end do
        call ws%kill()
    end subroutine test_map_repreparation

    subroutine test_requested_outputs( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polar_table)       :: ws
        type(polar_map_block)   :: mb
        type(polar_map_results) :: base, profiled
        integer                 :: st, mode
        write(*,'(a)') 'test_requested_outputs'
        fx = make_map_fixture(.false., .true.)
        call prepare_half(fx, 1, PRIOR_SCREEN, ws)
        mb = map_block(fx, half_pids(1), same_cands(CANDS(:, 1), 3), [TEMP_T, TEMP_PHYS])
        mb%ptcl_tile = 2
        do mode = 0, 3
            mb%maps = btest(mode, 0)
            mb%evidence = btest(mode, 1)
            mb%profile = .false.
            call ws%score_maps(mb, base, st)
            call assert_int(0, st, 'unprofiled requested outputs succeed')
            mb%profile = .true.
            call ws%score_maps(mb, profiled, st)
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
        call ws%kill()
    end subroutine test_requested_outputs

    ! candidate permutations and duplicates give the same entry for the same pair, tiles of one and of two
    ! particles (three particles: the last tile partial) the entries of one graph, and three repeats identical
    ! entries
    subroutine test_candidates_and_tiles( dev )
        integer, intent(in) :: dev
        type(map_fixture)       :: fx
        type(polar_table)       :: ws
        type(polar_map_block)   :: mb
        type(polar_map_results) :: r0, r1, r2
        integer, allocatable    :: pids(:)
        integer                 :: st, b, c, c2, rep, ptile
        logical                 :: same_idx, same_vals, ident
        write(*,'(a)') 'test_candidates_and_tiles'
        fx   = make_map_fixture(.false., .true.)
        pids = half_pids(1)
        call prepare_half(fx, 1, PRIOR_SCREEN, ws)
        mb = map_block(fx, pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
        mb%maps = .false.
        call ws%score_maps(mb, r0, st)
        call assert_true(loss_error(fx, pids, mb%cands, r0) <= POLAR_MAP_CAP_L2, device_name(dev)//': without maps, '//&
            &'every returned loss is the direct residual at the returned pose')
        ! the same pairs in another order and with a duplicate
        same_idx  = .true.
        same_vals = .true.
        do rep = 2, 3
            mb%cands = same_cands(CANDS(:, rep), size(pids))
            call ws%score_maps(mb, r1, st)
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
            call ws%score_maps(mb, r1, st)
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
            call ws%score_maps(mb, r2, st)
            ident = ident .and. all(bits_equal(r2%loss, r0%loss)) .and. all(bits_equal(r2%sdev, r0%sdev)) .and. &
                &all(bits_equal(r2%logz, r0%logz)) .and. all(r2%irot == r0%irot) .and. all(r2%irho == r0%irho) .and. &
                &all(r2%ialpha == r0%ialpha)
        end do
        call assert_true(ident, device_name(dev)//': three repeats give identical results')
        call ws%kill()
    end subroutine test_candidates_and_tiles

    ! mismatches are refused; maps need prepared references and their own preparation; references that change
    ! are invalidated, prepared again with their maps, and match the oracle of the new references
    subroutine test_refusals_rebuild( dev )
        integer, intent(in) :: dev
        type(map_fixture)         :: fx, fb
        type(polar_table)         :: ws
        type(polar_map_block)     :: mb, bad
        type(polar_map_results)   :: res
        type(polar_table_refs)    :: refs, badrefs
        type(polar_map_spec)      :: spec
        type(polar_table_entries) :: ent
        real(real64), allocatable :: lor(:,:,:)
        real(real64)              :: worst
        integer,      allocatable :: pids(:)
        integer                   :: st, b, c
        write(*,'(a)') 'test_refusals_rebuild'
        fx   = make_map_fixture(.false., .true.)
        pids = half_pids(1)
        mb   = map_block(fx, pids, same_cands(CANDS(:, 1), size(pids)), [TEMP_T, TEMP_PHYS])
        call ws%score_maps(mb, res, st)
        call assert_true(st /= 0, device_name(dev)//': a workspace without references refuses maps')
        call prepare_half(fx, 1, 0._real64, ws)
        bad = mb
        bad%half = 2
        call ws%score_maps(bad, res, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'half') > 0, device_name(dev)//': maps of the other '//&
            &'half are refused')
        bad = mb
        bad%generation = 2_int64
        call ws%score_maps(bad, res, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'generation') > 0, device_name(dev)//': maps of '//&
            &'another reference generation are refused')
        bad = mb
        bad%cands(1, 1) = NREF + 1
        call ws%score_maps(bad, res, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'candidate') > 0, device_name(dev)//': a candidate '//&
            &'outside the prepared references is refused')
        ! a refused replacement of the maps leaves no maps and the dense scoring intact; memos of another shape
        ! and another geometry are refused before any of them is read
        refs    = half_refs(fx, 1)
        spec    = half_spec(fx, 1, 0._real64)
        badrefs = refs
        badrefs%ft_ref = refs%ft_ref(:, 1:fx%nk - 1, :)
        call ws%prepare_maps(badrefs, spec, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'memos') > 0, device_name(dev)//': reference memos '//&
            &'(ft_ref) of another shape are refused')
        call ws%score_maps(mb, res, st)
        call assert_true(st /= 0, device_name(dev)//': after a refused preparation the earlier maps are gone')
        call ws%score(dense_block(fx, pids), ent, st)
        call assert_int(0, st, device_name(dev)//': a refused map preparation leaves the dense scoring intact')
        badrefs = refs
        badrefs%ft_ref2 = refs%ft_ref2(:, :, 1:NREF - 1)
        call ws%prepare_maps(badrefs, spec, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'memos') > 0, device_name(dev)//': reference memos '//&
            &'(ft_ref2) of another shape are refused')
        badrefs = refs
        badrefs%pftsz = refs%pftsz + 2
        call ws%prepare_maps(badrefs, spec, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'geometry') > 0, device_name(dev)//': references of '//&
            &'another geometry are refused')
        call ws%prepare_maps(refs, spec, st)
        call assert_int(0, st, device_name(dev)//': the maps are prepared again after the refusals')
        call ws%score_maps(mb, res, st)
        call assert_int(0, st, device_name(dev)//': the maps prepared again are scored')
        call ws%invalidate()
        call ws%score_maps(mb, res, st)
        call assert_true(st /= 0, device_name(dev)//': after invalidation maps are refused')
        ! the references change: rings scaled by 1.1 under a new generation
        fb = fx
        fb%rref = 1.1_real32 * fx%rref
        call fixture_memos(fb)
        call prepare_half(fb, 1, 0._real64, ws)
        call ws%score_maps(mb, res, st)
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
        call ws%kill()
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

    subroutine map_cycle( fx, nbad )
        type(map_fixture), intent(in)    :: fx
        integer,           intent(inout) :: nbad
        type(polar_table)       :: ws
        type(polar_map_results) :: res
        type(polar_map_block)   :: mb
        integer                 :: st
        call prepare_half(fx, 1, PRIOR_SCREEN, ws)
        mb = map_block(fx, [1, 3], same_cands(CANDS(:, 1), 2), [TEMP_T, TEMP_PHYS])
        call ws%score_maps(mb, res, st)
        nbad = nbad + merge(1, 0, st /= 0 .or. .not. allocated(res%loss))
        call ws%kill()
    end subroutine map_cycle

end module mlxf_kernel_polar_table_shiftmap_tester
