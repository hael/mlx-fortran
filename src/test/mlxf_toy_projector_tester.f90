!@descr: tests of the toy projector: the polar gather against the host oracle, its controls, repeatability, its lifecycle
! The fixtures run SIMPLE's reprojection loop (new, set_rmat, pad_fft, expand_cmat, the batch projection, kill) on
! small volumes and are held to mlxf_oracle_projection in double precision, which is given the toy's
! single-precision inputs widened: the volume, the rotation matrices and the polar table the calculator returns.
! A sample's error is |toy - oracle| over the sum of the magnitudes of its 27 terms (times the factor 8), the
! largest over the judged samples; the gate is POLAR_ROW_FACTOR times the frozen PROJ_FIXTURE_ERR. Samples near a
! tie of the stencil's rounding are counted on the host (the fast fixtures have none) and not judged.
module mlxf_toy_projector_tester
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,                         only: mlx_set_default_device, mlx_default_device, mlx_live_count, mlx_active_memory, &
                                        mlx_synchronize, MLX_DEVICES
use mlxf_test_defs,               only: OSMPL_PAD_FAC, PROJ_FORMS, PROJ_TIE_MARGIN, PROJ_FIXTURE_ERR, POLAR_ROW_FACTOR, &
                                        ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED, POLARFT_REF_ROUTES, &
                                        PROJ_CHAIN_ERR_HOST, PROJ_CHAIN_ERR_DEVICE, POLAR_DIST_MAX, POLAR_DIST_INVALID, &
                                        parameters, polar_table_entries, polar_row_check
use mlxf_toy_polarft_calc,        only: polarft_calc, vol_pad2ref_pfts_opt
use mlxf_toy_projector,           only: projector
use mlxf_toy_projector_pft_batch, only: fproject_polar_batch_opt
use mlxf_oracle_projection,       only: oracle_proj_phantom, oracle_proj_rotation, oracle_proj_route, &
                                        oracle_proj_stencil, oracle_proj_polar_coords, oracle_proj_padded_field, &
                                        oracle_proj_pack, oracle_proj_edge_gather, oracle_proj_edge_index, &
                                        oracle_proj_matrix, oracle_proj_gather
use mlxf_oracle_polar,            only: polar_full_ring, polar_compare_rows
use mlxf_test_utils,              only: assert_true, assert_int, device_name, bits_equal, set_fixed_seed, test_devices
use mlxf_test_reduce,             only: nan_maxval
implicit none
private
public :: run_all_projector_tests, run_all_projector_chain_tests

real(real64), parameter :: PI = acos(-1._real64)
! the seeded fixture's draws start from this base plus 1,000 times the seed; the controls' from their own
integer, parameter :: SEED_BASE    = 101
integer, parameter :: CONTROL_SEED = 7
! the edge fixture: the oracle's four edge queries and four boundary queries (padded coordinates, by columns)
real(real64), parameter :: EDGE_QUERIES(3, 4) = reshape([6.75_real64, 0.25_real64, -6._real64, -6.75_real64, &
    &5.5_real64, 1.25_real64, 7.25_real64, -2.5_real64, 3.75_real64, -7.25_real64, 6._real64, -0.5_real64], [3, 4])
real(real64), parameter :: BOUNDARY_QUERIES(3, 4) = reshape([0.5_real64, -0.5_real64, 1.5_real64, -1.5_real64, &
    &2.5_real64, -2.5_real64, 5.5_real64, -5.5_real64, 6._real64, -5.5_real64, 0._real64, -6._real64], [3, 4])
! the plane wave of the index control: its frequency on the 12-grid
integer, parameter :: WAVE(3) = [2, -3, 1]
! the lifecycle's cycles
integer, parameter :: NCYCLES = 100
! the chain: two seeded 16-cubes (the even and the odd volume), pftsz 16, shells 2 to 7, six directions, four
! particles per parity; the calculator's tile plan (references and particles per tile, partial tiles both ways)
integer, parameter :: CH_N       = 16
integer, parameter :: CH_PFTSZ   = 16
integer, parameter :: CH_NROTS   = 2 * CH_PFTSZ
integer, parameter :: CH_KFROM   = 2
integer, parameter :: CH_KTO     = 7
integer, parameter :: CH_NK      = CH_KTO - CH_KFROM + 1
integer, parameter :: CH_NSPACE  = 6
integer, parameter :: CH_NPTCLS  = 8
integer, parameter :: CH_RT      = 4
integer, parameter :: CH_BT      = 3
integer, parameter :: CH_SEED    = 301

! a fixture: the volume (n, n, n) and its padded box m, the polar set (pftsz, shells kfromto), the directions'
! matrices (3, 3, ndir) in single precision; the gather's form, directions per tile and threads per group
type :: proj_fixture
    character(len=32)         :: name = ''
    integer                   :: n          = 0
    integer                   :: m          = 0
    integer                   :: pftsz      = 0
    integer                   :: kfromto(2) = 0
    integer                   :: form       = PROJ_FORMS%graph
    integer                   :: tile       = 1
    integer                   :: tg         = 64
    real(real32), allocatable :: vol(:,:,:)
    real(real32), allocatable :: rots(:,:,:)
end type proj_fixture

! the chain's fixture: the two volumes, the directions, the shell weights of each half, the particles (rings,
! CTFs, weighted square sums, inverse temperatures) and the oracle's sections of both parities in double precision
type :: chain_fixture
    integer                      :: seed = 0
    real(real32),    allocatable :: vols(:,:,:,:)
    real(real32),    allocatable :: rots(:,:,:)
    real(real64),    allocatable :: w(:,:)
    complex(real32), allocatable :: xring(:,:,:)
    real(real32),    allocatable :: ctf(:,:,:)
    real(real64),    allocatable :: wsq(:)
    real(real32),    allocatable :: temps(:)
    complex(real64), allocatable :: yo(:,:,:,:)
end type chain_fixture

! one run of the chain: the route of the references, the gather's form, and the rows of each half against all
! six references (rotations, references, particles of the half)
type :: chain_run
    integer                   :: route = POLARFT_REF_ROUTES%host
    integer                   :: form  = PROJ_FORMS%graph
    real(real32), allocatable :: rows(:,:,:,:)
end type chain_run

contains

    subroutine run_all_projector_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all projector tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_fixtures(PROJ_FORMS%graph)
            call test_controls(PROJ_FORMS%graph)
            call test_repeatability(PROJ_FORMS%graph)
            call test_lifecycle(PROJ_FORMS%graph)
            if( devs(i) == MLX_DEVICES%gpu )then
                call test_fixtures(PROJ_FORMS%fused)
                call test_controls(PROJ_FORMS%fused)
                call test_repeatability(PROJ_FORMS%fused)
                call test_lifecycle(PROJ_FORMS%fused)
                call test_forms_agree()
            endif
            call test_fused_refusals(devs(i))
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_projector_tests

    ! ---- the fixtures --------------------------------------------------------------------------------------------

    ! the oracle's phantom on the 6-cube, padded to 12; pftsz 6, shells 1 and 2; the oracle's three rotations,
    ! two directions per tile (a tail of one)
    function phantom_fixture( form ) result(fx)
        integer, intent(in) :: form
        type(proj_fixture) :: fx
        integer            :: i
        fx%form    = form
        fx%name    = 'phantom'
        fx%n       = 6
        fx%m       = 12
        fx%pftsz   = 6
        fx%kfromto = [1, 2]
        fx%tile    = 2
        fx%vol     = real(oracle_proj_phantom(), real32)
        allocate(fx%rots(3, 3, 3))
        do i = 1, 3
            fx%rots(:, :, i) = real(oracle_proj_rotation(i), real32)
        end do
    end function phantom_fixture

    ! a seeded 8-cube in [-1/2, 1/2), padded to 16; pftsz 8, shells 1 to 3; six seeded rotations, four per tile
    function seeded_fixture( seed, form ) result(fx)
        integer, intent(in) :: seed, form
        type(proj_fixture) :: fx
        real(real64)       :: v(8, 8, 8)
        fx%form    = form
        fx%name    = 'seeded'
        fx%n       = 8
        fx%m       = 16
        fx%pftsz   = 8
        fx%kfromto = [1, 3]
        fx%tile    = 4
        call set_fixed_seed(SEED_BASE + 1000 * seed)
        call random_number(v)
        fx%vol  = real(v - 0.5_real64, real32)
        fx%rots = seeded_rotations(6, fx%pftsz, fx%kfromto)
    end function seeded_fixture

    ! rotations from Euler angles uniform on the sphere (SIMPLE's euler2m, double precision, rounded once); a
    ! rotation that puts a sample of the polar set near a tie is drawn again
    function seeded_rotations( n, pftsz, kfromto ) result(rots)
        integer, intent(in) :: n, pftsz, kfromto(2)
        real(real32), allocatable :: rots(:,:,:)
        real(real32)              :: hk(2, pftsz, kfromto(2) - kfromto(1) + 1)
        real(real64)              :: u(3), e(3)
        integer                   :: i
        allocate(rots(3, 3, n))
        hk = polar_table(pftsz, kfromto)
        do i = 1, n
            do
                call random_number(u)
                e = [360._real64 * u(1), acos(2._real64 * u(2) - 1._real64) * 180._real64 / PI, 360._real64 * u(3)]
                rots(:, :, i) = real(euler2m(e), real32)
                if( count_ties(rots(:, :, i:i), hk) == 0 ) exit
            end do
        end do
    end function seeded_rotations

    ! SIMPLE's euler2m: rotmat(e3, z) rotmat(e2, y) rotmat(e1, z), angles in degrees
    pure function euler2m( e ) result(r)
        real(real64), intent(in) :: e(3)
        real(real64) :: r(3, 3), r1(3, 3), r2(3, 3), r3(3, 3), r21(3, 3)
        r1  = rot_z(e(1))
        r2  = rot_y(e(2))
        r3  = rot_z(e(3))
        r21 = matmul(r2, r1)
        r   = matmul(r3, r21)
    end function euler2m

    pure function rot_z( a ) result(r)
        real(real64), intent(in) :: a
        real(real64) :: r(3, 3), c, s
        c = cos(a * PI / 180._real64)
        s = sin(a * PI / 180._real64)
        r = reshape([c, -s, 0._real64, s, c, 0._real64, 0._real64, 0._real64, 1._real64], [3, 3])
    end function rot_z

    pure function rot_y( a ) result(r)
        real(real64), intent(in) :: a
        real(real64) :: r(3, 3), c, s
        c = cos(a * PI / 180._real64)
        s = sin(a * PI / 180._real64)
        r = reshape([c, 0._real64, s, 0._real64, 1._real64, 0._real64, -s, 0._real64, c], [3, 3])
    end function rot_y

    ! the padded polar points (2, pftsz, nk) of a calculator of this polar set, as fproject_polar_batch_opt forms them
    function polar_table( pftsz, kfromto ) result(hk)
        integer, intent(in) :: pftsz, kfromto(2)
        real(real32)       :: hk(2, pftsz, kfromto(2) - kfromto(1) + 1)
        type(polarft_calc) :: pftc
        real(real32)       :: tmp(kfromto(1):kfromto(2), pftsz)
        call pftc%new(parameters(pftsz=pftsz), 1, [1, 1], kfromto)
        call pftc%get_polar_coords(1, tmp)
        hk(1, :,:) = real(OSMPL_PAD_FAC, real32) * transpose(tmp)
        call pftc%get_polar_coords(2, tmp)
        hk(2, :,:) = real(OSMPL_PAD_FAC, real32) * transpose(tmp)
        call pftc%kill()
    end function polar_table

    ! the samples' padded coordinates (3, pftsz nk ndir) in double precision from the single-precision inputs,
    ! in the order of the bank (angle, shell, direction)
    function sample_coords( hk, rots ) result(t)
        real(real32), intent(in) :: hk(:,:,:), rots(:,:,:)
        real(real64), allocatable :: t(:,:)
        integer                   :: i, k, p, s, a
        allocate(t(3, size(hk, 2) * size(hk, 3) * size(rots, 3)))
        s = 0
        do i = 1, size(rots, 3)
            do k = 1, size(hk, 3)
                do p = 1, size(hk, 2)
                    s = s + 1
                    do a = 1, 3
                        t(a, s) = real(hk(1, p, k), real64) * real(rots(1, a, i), real64) + &
                                  &real(hk(2, p, k), real64) * real(rots(2, a, i), real64)
                    end do
                end do
            end do
        end do
    end function sample_coords

    ! the samples with a coordinate within PROJ_TIE_MARGIN of a half-integer
    integer function count_ties( rots, hk ) result(n)
        real(real32), intent(in) :: rots(:,:,:), hk(:,:,:)
        real(real64), allocatable :: t(:,:)
        integer                   :: s
        t = sample_coords(hk, rots)
        n = 0
        do s = 1, size(t, 2)
            if( any(abs(t(:, s) - (floor(t(:, s)) + 0.5_real64)) < PROJ_TIE_MARGIN) ) n = n + 1
        end do
    end function count_ties

    ! ---- the toy's projection, as SIMPLE's reprojection loop runs it ---------------------------------------------

    ! the bank (pftsz, nk, ndir) of fx under its gather's form, tile and threads per group; msg the refusal, if any
    subroutine toy_project( fx, refs, msg )
        type(proj_fixture),            intent(in)  :: fx
        complex(real32), allocatable,  intent(out) :: refs(:,:,:)
        character(len=:), allocatable, intent(out) :: msg
        type(polarft_calc) :: pftc
        type(projector)    :: vol, vol_pad
        integer            :: ndir
        ndir = size(fx%rots, 3)
        allocate(refs(fx%pftsz, fx%kfromto(2) - fx%kfromto(1) + 1, ndir))
        call pftc%new(parameters(pftsz=fx%pftsz, box=fx%n, nspace=ndir, box_crop=fx%n), ndir, [1, 1], fx%kfromto)
        call vol%new([fx%n, fx%n, fx%n], 1._real32)
        call vol%set_rmat(fx%vol, .false.)
        call vol_pad%new([fx%m, fx%m, fx%m], 1._real32)
        call vol_pad%set_fproject_form(fx%form)
        call vol_pad%set_fproject_tile(fx%tile, fx%tg)
        call vol%pad_fft(vol_pad)
        call vol_pad%expand_cmat()
        call fproject_polar_batch_opt(vol_pad, fx%rots, ndir, pftc, refs)
        msg = vol_pad%message()
        call vol_pad%kill()
        call vol_pad%kill_expanded()
        call vol%kill()
        call pftc%kill()
    end subroutine toy_project

    ! ---- the oracle ----------------------------------------------------------------------------------------------

    ! every sample's oracle value 8 G F and its scale, 8 times the sum of |w f| of its 27 terms: on the periodic
    ! grid, or with the edge map of dimension 1 (edge)
    subroutine oracle_samples( fx, edge, t, y, scale )
        type(proj_fixture),           intent(in)  :: fx
        logical,                      intent(in)  :: edge
        real(real64),                 intent(in)  :: t(:,:)
        complex(real64), allocatable, intent(out) :: y(:)
        real(real64),    allocatable, intent(out) :: scale(:)
        complex(real64), allocatable :: f(:,:,:), p(:,:,:)
        real(real64)                 :: w(3, 3), fac
        integer                      :: h(3, 3), s, i, j, l, c, m
        fac = real(OSMPL_PAD_FAC**3, real64)
        m   = OSMPL_PAD_FAC * fx%n
        allocate(f(m, m, m), p(m / 2 + 1, m, m))
        f   = oracle_proj_padded_field(real(fx%vol, real64))
        if( edge )then
            p = oracle_proj_pack(f)
            y = fac * oracle_proj_edge_gather(t, p)
        else
            y = oracle_proj_route(real(fx%vol, real64), t)
        endif
        allocate(scale(size(t, 2)))
        do s = 1, size(t, 2)
            do i = 1, 3
                call oracle_proj_stencil(t(i, s), h(:, i), w(:, i))
            end do
            scale(s) = 0._real64
            do l = 1, 3
                do j = 1, 3
                    do i = 1, 3
                        if( edge )then
                            c = oracle_proj_edge_index(h(i, 1), m)
                            if( c >= 0 )then
                                scale(s) = scale(s) + abs(w(i, 1) * w(j, 2) * w(l, 3)) * &
                                    &abs(p(1 + c, 1 + modulo(h(j, 2), m), 1 + modulo(h(l, 3), m)))
                            else
                                scale(s) = scale(s) + abs(w(i, 1) * w(j, 2) * w(l, 3)) * &
                                    &abs(p(1 - c, 1 + modulo(-h(j, 2), m), 1 + modulo(-h(l, 3), m)))
                            endif
                        else
                            scale(s) = scale(s) + abs(w(i, 1) * w(j, 2) * w(l, 3)) * &
                                &abs(f(1 + modulo(h(i, 1), m), 1 + modulo(h(j, 2), m), 1 + modulo(h(l, 3), m)))
                        endif
                    end do
                end do
            end do
            scale(s) = fac * scale(s)
        end do
    end subroutine oracle_samples

    ! the largest error of the judged samples (mask) of a bank against the oracle, relative to each sample's scale
    function bank_error( refs, y, scale, mask ) result(err)
        complex(real32), intent(in) :: refs(:,:,:)
        complex(real64), intent(in) :: y(:)
        real(real64),    intent(in) :: scale(:)
        logical,         intent(in) :: mask(:)
        real(real64)                 :: err
        complex(real32), allocatable :: flat(:)
        real(real64),    allocatable :: e(:)
        flat = reshape(refs, [size(refs)])
        e    = abs(cmplx(flat, kind=real64) - y) / max(scale, tiny(1._real64))
        err  = nan_maxval(merge(e, 0._real64, mask))
    end function bank_error

    ! one error against the gate, printed for the calibration record
    subroutine judge( err, bound, label )
        real(real64),     intent(in) :: err, bound
        character(len=*), intent(in) :: label
        character(len=200) :: line
        write(line,'(a,es16.9,a,es10.3)') '    error '//label//' '//device_name(mlx_default_device())//': ', err, &
            &' gate ', bound
        write(*,'(a)') trim(line)
        call assert_true(err <= bound, label//' within its gate on the '//device_name(mlx_default_device()))
    end subroutine judge

    function form_name( form ) result(name)
        integer, intent(in) :: form
        character(len=:), allocatable :: name
        name = 'graph'
        if( form == PROJ_FORMS%fused ) name = 'fused'
    end function form_name

    ! the toy's bank of fx against the oracle; returns the error (huge on a refusal)
    function fixture_error( fx, edge, mask_in ) result(err)
        type(proj_fixture), intent(in) :: fx
        logical,            intent(in) :: edge
        logical, optional,  intent(in) :: mask_in(:)
        real(real64)                  :: err
        complex(real32),  allocatable :: refs(:,:,:)
        complex(real64),  allocatable :: y(:)
        real(real64),     allocatable :: t(:,:), scale(:)
        logical,          allocatable :: mask(:)
        character(len=:), allocatable :: msg
        call toy_project(fx, refs, msg)
        err = huge(1._real64)
        call assert_int(0, len(msg), trim(fx%name)//' '//form_name(fx%form)//' projected without a refusal: '//msg)
        if( len(msg) > 0 ) return
        t = sample_coords(polar_table(fx%pftsz, fx%kfromto), fx%rots)
        call oracle_samples(fx, edge, t, y, scale)
        allocate(mask(size(y)), source=.true.)
        if( present(mask_in) ) mask = mask_in
        err = bank_error(refs, y, scale, mask)
    end function fixture_error

    ! ---- the suite's parts ---------------------------------------------------------------------------------------

    ! the phantom, the seeded cube of every seed and the edge queries against the oracle
    subroutine test_fixtures( form )
        integer, intent(in) :: form
        type(proj_fixture) :: fx
        real(real64)       :: gate, err
        integer            :: seeds(3), is
        write(*,'(a)') 'test_fixtures '//form_name(form)
        gate = POLAR_ROW_FACTOR * PROJ_FIXTURE_ERR
        fx   = phantom_fixture(form)
        call assert_int(0, count_ties(fx%rots, polar_table(fx%pftsz, fx%kfromto)), 'the phantom has no near tie')
        err = fixture_error(fx, .false.)
        call judge(err, gate, 'projector '//form_name(form)//' phantom')
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
        do is = 1, size(seeds)
            fx = seeded_fixture(seeds(is), form)
            call assert_int(0, count_ties(fx%rots, polar_table(fx%pftsz, fx%kfromto)), 'the seeded cube has no near tie')
            err = fixture_error(fx, .false.)
            call judge(err, gate, 'projector '//form_name(form)//' seeded seed='//achar(48 + seeds(is)))
        end do
        call test_edge(form, gate)
    end subroutine test_fixtures

    ! the edge fixture: shell 1 at 90 degrees under matrices whose first row is half a query (the second row 0, so
    ! the sample's coordinate is the query exactly), and the shell N/2 at 90 degrees under the identity; only the
    ! samples at 90 degrees are judged, against the oracle's edge gather on the packed phantom
    subroutine test_edge( form, gate )
        integer,      intent(in) :: form
        real(real64), intent(in) :: gate
        type(proj_fixture)   :: fx
        logical, allocatable :: mask(:)
        real(real64)         :: err
        integer              :: q, i
        fx         = phantom_fixture(form)
        fx%name    = 'edge'
        fx%kfromto = [1, 1]
        deallocate(fx%rots)
        allocate(fx%rots(3, 3, 8), source=0._real32)
        do q = 1, 4
            fx%rots(1, :, q)     = real(EDGE_QUERIES(:, q) / 2._real64, real32)
            fx%rots(1, :, 4 + q) = real(BOUNDARY_QUERIES(:, q) / 2._real64, real32)
        end do
        ! the samples at 90 degrees: angle 1 + pftsz/2 of each direction
        allocate(mask(fx%pftsz * 8), source=.false.)
        do i = 1, 8
            mask((i - 1) * fx%pftsz + 1 + fx%pftsz / 2) = .true.
        end do
        err = fixture_error(fx, .true., mask)
        call judge(err, gate, 'projector '//form_name(form)//' edge and boundary queries')
        ! the shell N/2 at 90 degrees: the tap M/2 + 1 of dimension 1
        fx%kfromto = [fx%n / 2, fx%n / 2]
        deallocate(fx%rots)
        allocate(fx%rots(3, 3, 1))
        fx%rots(:, :, 1) = real(oracle_proj_rotation(1), real32)
        deallocate(mask)
        allocate(mask(fx%pftsz), source=.false.)
        mask(1 + fx%pftsz / 2) = .true.
        err = fixture_error(fx, .true., mask)
        call judge(err, gate, 'projector '//form_name(form)//' shell N/2 at the edge')
    end subroutine test_edge

    ! decision 15's controls: the constant spectrum, the phantom's identity rotation, the plane wave, the
    ! Hermitian pairs (the boundary and edge queries are test_edge's)
    subroutine test_controls( form )
        integer, intent(in) :: form
        write(*,'(a)') 'test_controls '//form_name(form)
        call control_constant(form)
        call control_identity(form)
        call control_wave(form)
        call control_hermitian(form)
    end subroutine test_controls

    ! a padded transform that is c everywhere (c M**3 at the origin of the volume): under the identity every sample
    ! is 8 c, which pins the normalisation of each axis and the factor 8
    subroutine control_constant( form )
        integer, intent(in) :: form
        real(real32),     parameter   :: C = 0.75_real32
        type(proj_fixture)            :: fx
        complex(real32),  allocatable :: refs(:,:,:)
        character(len=:), allocatable :: msg
        real(real64)                  :: err
        fx = phantom_fixture(form)
        fx%vol = 0._real32
        fx%vol(fx%n / 2 + 1, fx%n / 2 + 1, fx%n / 2 + 1) = C * real(fx%m, real32)**3
        fx%rots = fx%rots(:, :, 1:1)
        call toy_project(fx, refs, msg)
        err = nan_maxval(abs(cmplx(reshape(refs, [size(refs)]), kind=real64) - 8._real64 * real(C, real64))) / &
            &(8._real64 * real(C, real64))
        call judge(err, POLAR_ROW_FACTOR * PROJ_FIXTURE_ERR, 'control '//form_name(form)//' constant spectrum')
    end subroutine control_constant

    ! the phantom under the identity alone, against the oracle at its own polar coordinates (2 p, p = (k sin a,
    ! -k cos a, 0) on the full ring of 12 angles), not the calculator's table: the origin and sense of the angle
    subroutine control_identity( form )
        integer, intent(in) :: form
        type(proj_fixture)            :: fx
        complex(real32),  allocatable :: refs(:,:,:)
        character(len=:), allocatable :: msg
        complex(real64),  allocatable :: y(:)
        real(real64),     allocatable :: tall(:,:), t(:,:), scale(:)
        integer                       :: k, p, s
        fx      = phantom_fixture(form)
        fx%rots = fx%rots(:, :, 1:1)
        call toy_project(fx, refs, msg)
        call assert_int(0, len(msg), 'control identity projected without a refusal: '//msg)
        if( len(msg) > 0 ) return
        ! the oracle's samples of rotation 1: angle fastest over the full ring (2 pftsz), then shells 1 and 2
        tall = oracle_proj_polar_coords()
        allocate(t(3, fx%pftsz * 2))
        s = 0
        do k = 1, 2
            do p = 1, fx%pftsz
                s = s + 1
                t(:, s) = tall(:, (k - 1) * 2 * fx%pftsz + p)
            end do
        end do
        call oracle_samples(fx, .false., t, y, scale)
        call judge(bank_error(refs, y, scale, [(.true., s = 1, size(y))]), POLAR_ROW_FACTOR * PROJ_FIXTURE_ERR, &
            &'control '//form_name(form)//' identity rotation')
    end subroutine control_identity

    ! a real wave on the 12-grid, padded by 1: its spectrum is 1/2 at WAVE and at its mate. Under four seeded
    ! rotations the non-zero samples are exactly those whose stencil touches one of them (the oracle's matrix
    ! pattern), with the values of the matrix's weights
    subroutine control_wave( form )
        integer, intent(in) :: form
        type(proj_fixture)            :: fx
        complex(real32),  allocatable :: refs(:,:,:)
        character(len=:), allocatable :: msg
        real(real64),     allocatable :: t(:,:), g(:,:), want(:)
        logical,          allocatable :: on(:)
        real(real64)                  :: x(3), thr, err
        integer                       :: i, j, k, ip, im, nmis
        fx%form    = form
        fx%name    = 'wave'
        fx%n       = 12
        fx%m       = 12
        fx%pftsz   = 8
        fx%kfromto = [1, 2]
        fx%tile    = 4
        allocate(fx%vol(12, 12, 12))
        do k = 1, 12
            do j = 1, 12
                do i = 1, 12
                    x = real([i, j, k] - 1 - 6, real64)
                    fx%vol(i, j, k) = real(cos(2._real64 * PI * sum(real(WAVE, real64) * x) / 12._real64), real32)
                end do
            end do
        end do
        call set_fixed_seed(CONTROL_SEED)
        fx%rots = seeded_rotations(4, fx%pftsz, fx%kfromto)
        call toy_project(fx, refs, msg)
        call assert_int(0, len(msg), 'control wave projected without a refusal: '//msg)
        if( len(msg) > 0 ) return
        t  = sample_coords(polar_table(fx%pftsz, fx%kfromto), fx%rots)
        g  = oracle_proj_matrix(t, 12)
        ip = flat_of(WAVE, 12)
        im = flat_of(-WAVE, 12)
        want = real(OSMPL_PAD_FAC**3, real64) * 0.5_real64 * (g(:, ip) + g(:, im))
        thr  = 0.5_real64 * minval(want, mask=want > 0._real64)
        on   = abs(cmplx(reshape(refs, [size(refs)]), kind=real64)) > thr
        nmis = count(on .neqv. (want > 0._real64))
        call assert_true(count(want > 0._real64) > 0 .and. thr > 1.e-5_real64, &
            &'control wave: the wave reaches some samples, well above the transform''s rounding')
        call assert_int(0, nmis, 'control '//form_name(form)//' wave: the non-zero samples are the matrix''s pattern')
        ! the values relative to the largest sample the wave can give, 8 max|F|: the transform's rounding, which
        ! every one of the 27 terms carries, scales with it, not with the one or two terms that are not zero
        err = nan_maxval(abs(cmplx(reshape(refs, [size(refs)]), kind=real64) - want)) / &
            &(real(OSMPL_PAD_FAC**3, real64) * 0.5_real64)
        call judge(err, POLAR_ROW_FACTOR * PROJ_FIXTURE_ERR, 'control '//form_name(form)//' wave values')
    end subroutine control_wave

    ! the column of the oracle's matrix of signed frequency h on the m-grid
    pure integer function flat_of( h, m )
        integer, intent(in) :: h(3), m
        integer :: j(3)
        j = 1 + modulo(h, m)
        flat_of = j(1) + m * (j(2) - 1) + m * m * (j(3) - 1)
    end function flat_of

    ! a direction and its turn by 180 degrees in the plane: every sample of the turned one is the conjugate of the
    ! direction's (a real volume), which pins the conjugate half of the expanded cube; held to twice the gate
    subroutine control_hermitian( form )
        integer, intent(in) :: form
        type(proj_fixture)            :: fx
        complex(real32),  allocatable :: refs(:,:,:)
        complex(real64),  allocatable :: y(:)
        real(real64),     allocatable :: t(:,:), scale(:), e(:)
        character(len=:), allocatable :: msg
        real(real32),     allocatable :: rots(:,:,:)
        integer                       :: nd, ns
        fx = seeded_fixture(ELEM_SEED_CALIBRATION, form)
        call set_fixed_seed(CONTROL_SEED + 1)
        rots = seeded_rotations(3, fx%pftsz, fx%kfromto)
        deallocate(fx%rots)
        allocate(fx%rots(3, 3, 6))
        fx%rots(:, :, 1:3)    = rots
        fx%rots(:, :, 4:6)    = rots
        fx%rots(1:2, :, 4:6)  = -rots(1:2, :, :)
        fx%tile = 6
        call toy_project(fx, refs, msg)
        call assert_int(0, len(msg), 'control Hermitian projected without a refusal: '//msg)
        if( len(msg) > 0 ) return
        t = sample_coords(polar_table(fx%pftsz, fx%kfromto), fx%rots(:, :, 1:3))
        call oracle_samples(fx, .false., t, y, scale)
        nd = 3
        ns = size(refs, 1) * size(refs, 2)
        e  = abs(cmplx(reshape(refs(:, :, 4:6), [ns * nd]), kind=real64) - &
            &conjg(cmplx(reshape(refs(:, :, 1:3), [ns * nd]), kind=real64))) / max(scale, tiny(1._real64))
        call judge(nan_maxval(e), 2._real64 * POLAR_ROW_FACTOR * PROJ_FIXTURE_ERR, &
            &'control '//form_name(form)//' Hermitian pairs')
    end subroutine control_hermitian

    ! three projections of the same inputs, each from a fresh projector, give the same bits
    subroutine test_repeatability( form )
        integer, intent(in) :: form
        type(proj_fixture)            :: fxs(2)
        complex(real32),  allocatable :: r1(:,:,:), r2(:,:,:)
        character(len=:), allocatable :: msg
        integer                       :: f, pass
        logical                       :: same
        write(*,'(a)') 'test_repeatability '//form_name(form)
        fxs(1) = phantom_fixture(form)
        fxs(2) = seeded_fixture(ELEM_SEED_CALIBRATION, form)
        do f = 1, 2
            call toy_project(fxs(f), r1, msg)
            same = len(msg) == 0
            do pass = 2, 3
                call toy_project(fxs(f), r2, msg)
                same = same .and. len(msg) == 0
                if( same ) same = all(bits_equal(r1, r2))
            end do
            call assert_true(same, 'repeatability '//form_name(form)//' '//trim(fxs(f)%name)// &
                &': three projections from fresh graphs give the same bits')
        end do
    end subroutine test_repeatability

    ! the two forms' banks of the same inputs: their largest difference relative to the sample's scale, reported
    ! (each form is held to the oracle on its own)
    subroutine test_forms_agree
        type(proj_fixture)            :: fx
        complex(real32),  allocatable :: rg(:,:,:), rf(:,:,:)
        complex(real64),  allocatable :: y(:)
        real(real64),     allocatable :: t(:,:), scale(:), e(:)
        character(len=:), allocatable :: msg
        character(len=160)            :: line
        integer                       :: is
        write(*,'(a)') 'test_forms_agree'
        do is = 1, 2
            if( is == 1 )then
                fx = phantom_fixture(PROJ_FORMS%graph)
            else
                fx = seeded_fixture(ELEM_SEED_CALIBRATION, PROJ_FORMS%graph)
            endif
            call toy_project(fx, rg, msg)
            fx%form = PROJ_FORMS%fused
            call toy_project(fx, rf, msg)
            t = sample_coords(polar_table(fx%pftsz, fx%kfromto), fx%rots)
            call oracle_samples(fx, .false., t, y, scale)
            e = abs(cmplx(reshape(rf, [size(rf)]), kind=real64) - cmplx(reshape(rg, [size(rg)]), kind=real64)) / &
                &max(scale, tiny(1._real64))
            write(line,'(a,es12.5,a,i0,a,i0)') '    forms '//trim(fx%name)//': largest difference ', nan_maxval(e), &
                &', samples whose bits differ ', count(.not. bits_equal(rf, rg)), ' of ', size(rf)
            write(*,'(a)') trim(line)
            call assert_true(len(msg) == 0, 'forms agree: the fused form projected the '//trim(fx%name))
        end do
    end subroutine test_forms_agree

    ! the fused form refused on the CPU device, a threadgroup above 1,024 refused, both through message(); the
    ! projector then projects in the graph form, and on the GPU a fused projection is followed by a graph one on
    ! the same expanded projector
    subroutine test_fused_refusals( dev )
        integer, intent(in) :: dev
        type(proj_fixture)            :: fx
        type(polarft_calc)            :: pftc
        type(projector)               :: vol, vol_pad
        complex(real32),  allocatable :: refs(:,:,:)
        write(*,'(a)') 'test_fused_refusals'
        fx = phantom_fixture(PROJ_FORMS%fused)
        allocate(refs(fx%pftsz, fx%kfromto(2) - fx%kfromto(1) + 1, size(fx%rots, 3)))
        call pftc%new(parameters(pftsz=fx%pftsz, box=fx%n, nspace=3, box_crop=fx%n), 3, [1, 1], fx%kfromto)
        call vol%new([fx%n, fx%n, fx%n], 1._real32)
        call vol%set_rmat(fx%vol, .false.)
        call vol_pad%new([fx%m, fx%m, fx%m], 1._real32)
        call vol%pad_fft(vol_pad)
        call vol_pad%expand_cmat()
        call vol_pad%set_fproject_tile(fx%tile, 2048)
        call assert_true(index(vol_pad%message(), 'refused') > 0, 'a threadgroup of 2,048 is refused with a message')
        call vol_pad%set_fproject_form(PROJ_FORMS%fused)
        call fproject_polar_batch_opt(vol_pad, fx%rots, 3, pftc, refs)
        if( dev == MLX_DEVICES%cpu )then
            call assert_true(index(vol_pad%message(), 'GPU only') > 0, 'the fused form is refused on the CPU device')
            call assert_true(all(bits_equal(refs, cmplx(0._real32, 0._real32, real32))), &
                &'a refused projection leaves refs_state at zero')
        else
            call assert_int(0, len(vol_pad%message()), 'the fused form projects on the GPU: '//vol_pad%message())
        endif
        call vol_pad%set_fproject_form(PROJ_FORMS%graph)
        call fproject_polar_batch_opt(vol_pad, fx%rots, 3, pftc, refs)
        call assert_int(0, len(vol_pad%message()), 'the projector is usable afterwards: '//vol_pad%message())
        call vol_pad%kill()
        call vol%kill()
        call pftc%kill()
    end subroutine test_fused_refusals

    ! NCYCLES cycles of new, pad_fft, expand_cmat, a projection and kill leave the live handles and the active
    ! memory where they were
    subroutine test_lifecycle( form )
        integer, intent(in) :: form
        type(proj_fixture)            :: fx
        complex(real32),  allocatable :: refs(:,:,:)
        character(len=:), allocatable :: msg
        character(len=96)             :: line
        integer(int64)                :: mem0, mem1
        integer                       :: live0, live1, i
        write(*,'(a)') 'test_lifecycle '//form_name(form)
        fx = phantom_fixture(form)
        call toy_project(fx, refs, msg)
        ! the device releases a buffer when the work that used it completes: wait for it before each reading
        call mlx_synchronize()
        live0 = mlx_live_count()
        mem0  = mlx_active_memory()
        do i = 1, NCYCLES
            call toy_project(fx, refs, msg)
        end do
        call mlx_synchronize()
        live1 = mlx_live_count()
        mem1  = mlx_active_memory()
        write(line,'(a,i0,a,i0)') ' (bytes before ', mem0, ', after ', mem1
        call assert_int(live0, live1, 'lifecycle '//form_name(form)//': the live handles return after 100 cycles')
        call assert_true(mem1 == mem0, 'lifecycle '//form_name(form)//': the active memory returns after 100 cycles'// &
            &trim(line)//')')
    end subroutine test_lifecycle

    ! ---- the chain: the projected references through family A ----------------------------------------------

    subroutine run_all_projector_chain_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all projector_chain tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_chain_rows(PROJ_FORMS%graph)
            if( devs(i) == MLX_DEVICES%gpu ) call test_chain_rows(PROJ_FORMS%fused)
            call test_chain_refusals()
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_projector_chain_tests

    ! the half of a particle: half 1 (the even references) holds the odd indices
    pure integer function chain_half( i )
        integer, intent(in) :: i
        chain_half = 2 - mod(i, 2)
    end function chain_half

    ! the seeded chain: two volumes, six seeded directions without a near tie, the oracle's sections of both
    ! parities, then particles made from them (a CTF times a rotated section of the particle's half, plus noise)
    function chain_fixture_of( seed ) result(fx)
        integer, intent(in) :: seed
        type(chain_fixture)          :: fx
        real(real64),    allocatable :: v(:,:,:), t(:,:)
        complex(real64), allocatable :: f(:,:,:), y(:)
        real(real64)                 :: s2(CH_NK, 2), re(CH_PFTSZ, CH_NK), noise(CH_PFTSZ, CH_NK, 2), amp
        complex(real64)              :: full(CH_NROTS), z(CH_PFTSZ)
        integer                      :: h, i, k, j, src, shift
        fx%seed = seed
        call set_fixed_seed(CH_SEED + 1000 * seed)
        allocate(fx%vols(CH_N, CH_N, CH_N, 2), v(CH_N, CH_N, CH_N), f(2 * CH_N, 2 * CH_N, 2 * CH_N))
        do h = 1, 2
            call random_number(v)
            fx%vols(:, :, :, h) = real(v - 0.5_real64, real32)
        end do
        fx%rots = seeded_rotations(CH_NSPACE, CH_PFTSZ, [CH_KFROM, CH_KTO])
        ! the oracle's sections (angle, shell, direction, parity): 8 G F of the padded transform
        t = sample_coords(polar_table(CH_PFTSZ, [CH_KFROM, CH_KTO]), fx%rots)
        allocate(fx%yo(CH_PFTSZ, CH_NK, CH_NSPACE, 2))
        do h = 1, 2
            f = oracle_proj_padded_field(real(fx%vols(:, :, :, h), real64))
            y = real(OSMPL_PAD_FAC**3, real64) * oracle_proj_gather(t, f)
            fx%yo(:, :, :, h) = reshape(y, [CH_PFTSZ, CH_NK, CH_NSPACE])
        end do
        ! shell weights k / sigma2, sigma2 in [0.5, 1.5)
        call random_number(s2)
        allocate(fx%w(CH_NK, 2))
        do h = 1, 2
            do k = 1, CH_NK
                fx%w(k, h) = real(CH_KFROM + k - 1, real64) / (0.5_real64 + s2(k, h))
            end do
        end do
        allocate(fx%xring(CH_PFTSZ, CH_NK, CH_NPTCLS), fx%ctf(CH_PFTSZ, CH_NK, CH_NPTCLS), fx%wsq(CH_NPTCLS), &
            &fx%temps(CH_NPTCLS))
        do i = 1, CH_NPTCLS
            h     = chain_half(i)
            src   = 1 + mod(3 * i, CH_NSPACE)
            shift = mod(5 * i, CH_NROTS)
            call random_number(re)
            call random_number(noise)
            fx%ctf(:, :, i) = real(0.2_real64 + 0.8_real64 * re, real32)
            do k = 1, CH_NK
                full = polar_full_ring(fx%yo(:, k, src, h))
                amp  = sqrt(sum(abs(full)**2) / real(CH_NROTS, real64))
                do j = 1, CH_PFTSZ
                    z(j) = real(fx%ctf(j, k, i), real64) * full(1 + mod(j - 1 - shift + 2 * CH_NROTS, CH_NROTS))
                end do
                z = z + 0.3_real64 * amp * cmplx(2._real64 * noise(:, k, 1) - 1._real64, &
                    &2._real64 * noise(:, k, 2) - 1._real64, real64)
                fx%xring(:, k, i) = cmplx(z, kind=real32)
            end do
            fx%wsq(i) = 0._real64
            do k = 1, CH_NK
                fx%wsq(i) = fx%wsq(i) + fx%w(k, h) * sum(abs(cmplx(fx%xring(:, k, i), kind=real64))**2)
            end do
            fx%temps(i) = 1._real32
        end do
    end function chain_fixture_of

    ! the oracle's rows of half h: every rotation's distance on the full rings in double precision,
    ! d(r) = 1 + sum_k w_k sum_m [C_m**2 |R_(m-r+1)|**2 - 2 Re(X_m C_m conj(R_(m-r+1)))] / (2 wsq); above
    ! POLAR_DIST_MAX the invalid marker
    function chain_oracle_rows( fx, h ) result(d)
        type(chain_fixture), intent(in) :: fx
        integer,             intent(in) :: h
        real(real64), allocatable :: d(:,:,:)
        integer,      allocatable :: pids(:)
        complex(real64)           :: rr(CH_NROTS), xx(CH_NROTS)
        real(real64)              :: cc(CH_NROTS), acc
        integer                   :: b, ir, i, k, rot, m, mm
        pids = [(i, i = h, CH_NPTCLS, 2)]
        allocate(d(CH_NROTS, CH_NSPACE, size(pids)))
        do b = 1, size(pids)
            i = pids(b)
            do ir = 1, CH_NSPACE
                do rot = 1, CH_NROTS
                    acc = 0._real64
                    do k = 1, CH_NK
                        rr = polar_full_ring(fx%yo(:, k, ir, h))
                        xx = polar_full_ring(cmplx(fx%xring(:, k, i), kind=real64))
                        cc(1:CH_PFTSZ)          = real(fx%ctf(:, k, i), real64)
                        cc(CH_PFTSZ+1:CH_NROTS) = cc(1:CH_PFTSZ)
                        do m = 1, CH_NROTS
                            mm  = 1 + mod(m - rot + CH_NROTS, CH_NROTS)
                            acc = acc + fx%w(k, h) * (cc(m)**2 * abs(rr(mm))**2 - &
                                &2._real64 * real(xx(m) * cc(m) * conjg(rr(mm)), real64))
                        end do
                    end do
                    d(rot, ir, b) = 1._real64 + acc / (2._real64 * fx%wsq(i))
                    if( d(rot, ir, b) > POLAR_DIST_MAX ) d(rot, ir, b) = real(POLAR_DIST_INVALID, real64)
                end do
            end do
        end do
    end function chain_oracle_rows

    ! a calculator of the chain: the shell weights, the route, the tile plan, the rows kept
    subroutine chain_calc( pftc, route )
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(in)    :: route
        call pftc%new(parameters(pftsz=CH_PFTSZ, box=CH_N, nspace=CH_NSPACE, nstates=1, box_crop=CH_N), CH_NSPACE, &
            &[1, CH_NPTCLS], [CH_KFROM, CH_KTO])
        call pftc%set_ref_route(route)
        call pftc%set_tile_plan(CH_BT, CH_RT)
        call pftc%set_block_options(.true., .false.)
    end subroutine chain_calc

    ! SIMPLE's reprojection of both parities of state 1 into the calculator: per parity new, set_rmat, pad_fft,
    ! expand_cmat, vol_pad2ref_pfts_opt, kill; nbad counts the refusals
    subroutine chain_reproject( pftc, fx, form, nbad )
        type(polarft_calc),  intent(inout) :: pftc
        type(chain_fixture), intent(in)    :: fx
        integer,             intent(in)    :: form
        integer,             intent(inout) :: nbad
        type(projector) :: vol, vol_pad
        integer         :: h
        do h = 1, 2
            call vol%new([CH_N, CH_N, CH_N], 1._real32)
            call vol%set_rmat(fx%vols(:, :, :, h), .false.)
            call vol_pad%new([2 * CH_N, 2 * CH_N, 2 * CH_N], 1._real32)
            call vol_pad%set_fproject_form(form)
            call vol_pad%set_fproject_tile(4, 64)
            call vol%pad_fft(vol_pad)
            call vol_pad%expand_cmat()
            call vol_pad2ref_pfts_opt(pftc, vol_pad, fx%rots, 1, h == 1)
            if( len(pftc%message()) > 0 )then
                nbad = nbad + 1
                write(*,'(a)') '    refused: '//pftc%message()
            endif
            call vol_pad%kill()
            call vol_pad%kill_expanded()
            call vol%kill()
        end do
    end subroutine chain_reproject

    ! the particles of the batch set and memoized
    subroutine chain_particles( pftc, fx, nbad )
        type(polarft_calc),  intent(inout) :: pftc
        type(chain_fixture), intent(in)    :: fx
        integer,             intent(inout) :: nbad
        integer :: i
        call pftc%set_sigma2_weights(fx%w)
        call pftc%reallocate_ptcls(CH_NPTCLS, [(i, i = 1, CH_NPTCLS)])
        do i = 1, CH_NPTCLS
            call pftc%set_eo(i, chain_half(i) == 1)
            call pftc%set_ptcl_ctfmat(i, fx%ctf(:, :, i))
            call pftc%set_ptcl_pft(i, fx%xring(:, :, i))
            if( len(pftc%message()) > 0 ) nbad = nbad + 1
        end do
        call pftc%memoize_ptcls()
    end subroutine chain_particles

    ! one run of the chain: projection, memoize_refs, memoize_ref_bins, particles, then each half's block with its
    ! full rows; nbad counts the refusals
    subroutine chain_once( fx, run, nbad )
        type(chain_fixture), intent(in)    :: fx
        type(chain_run),     intent(inout) :: run
        integer,             intent(out)   :: nbad
        type(polarft_calc)        :: pftc
        real(real32), allocatable :: u(:,:), dists(:,:), rows(:,:,:)
        integer,      allocatable :: irots(:,:), pids(:)
        integer                   :: h, i
        nbad = 0
        call chain_calc(pftc, run%route)
        call chain_reproject(pftc, fx, run%form, nbad)
        call pftc%memoize_refs()
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
        call chain_particles(pftc, fx, nbad)
        call pftc%memoize_ref_bins()
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
        allocate(run%rows(CH_NROTS, CH_NSPACE, CH_NPTCLS / 2, 2))
        do h = 1, 2
            pids = [(i, i = h, CH_NPTCLS, 2)]
            allocate(u(CH_NSPACE, size(pids)), dists(CH_NSPACE, size(pids)), irots(CH_NSPACE, size(pids)))
            u = 0.5_real32
            call pftc%set_block_variates(u)
            call pftc%score_block_posterior(size(pids), pids, CH_NSPACE, [(i, i = 1, CH_NSPACE)], fx%temps(pids), &
                &dists, irots)
            if( len(pftc%message()) > 0 ) nbad = nbad + 1
            call pftc%block_rows(rows)
            if( allocated(rows) )then
                run%rows(:, :, :, h) = rows
            else
                nbad = nbad + 1
            endif
            deallocate(dists, irots)
            if( allocated(u) ) deallocate(u)
        end do
        call pftc%kill()
    end subroutine chain_once

    function route_name( route ) result(name)
        integer, intent(in) :: route
        character(len=:), allocatable :: name
        name = 'host'
        if( route == POLARFT_REF_ROUTES%device ) name = 'device'
    end function route_name

    ! both routes on the seeds: each half's rows against the oracle's, then the routes against each other and the
    ! repeatability of three runs
    subroutine test_chain_rows( form )
        integer, intent(in) :: form
        type(chain_fixture)       :: fx
        type(chain_run)           :: runs(2), again
        type(polar_table_entries) :: ent
        type(polar_row_check)     :: chk
        real(real64), allocatable :: d(:,:,:)
        real(real64)              :: err, gate, diff, dmax
        character(len=200)        :: line
        integer                   :: seeds(3), is, ir, h, nbad, pass, noff
        logical                   :: same
        write(*,'(a)') 'test_chain_rows '//form_name(form)
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
        do is = 1, size(seeds)
            fx = chain_fixture_of(seeds(is))
            call assert_int(0, count_ties(fx%rots, polar_table(CH_PFTSZ, [CH_KFROM, CH_KTO])), &
                &'the chain''s directions have no near tie')
            do ir = 1, 2
                runs(ir)%route = merge(POLARFT_REF_ROUTES%host, POLARFT_REF_ROUTES%device, ir == 1)
                runs(ir)%form  = form
                if( allocated(runs(ir)%rows) ) deallocate(runs(ir)%rows)
                call chain_once(fx, runs(ir), nbad)
                call assert_int(0, nbad, 'chain '//route_name(runs(ir)%route)//' '//form_name(form)// &
                    &': every step carried out')
                err  = 0._real64
                noff = 0
                do h = 1, 2
                    d        = chain_oracle_rows(fx, h)
                    ent%rows = runs(ir)%rows(:, :, :, h)
                    chk      = polar_compare_rows(d, ent)
                    err      = max(err, chk%err)
                    noff     = noff + chk%argmin_off + chk%valid_off
                end do
                gate = POLAR_ROW_FACTOR * merge(PROJ_CHAIN_ERR_HOST, PROJ_CHAIN_ERR_DEVICE, ir == 1)
                write(line,'(a,i0,a,i0,a)') ' seed=', seeds(is), ' (minimising rotations or validities off: ', &
                    &noff, ')'
                write(*,'(a)') '   '//trim(line)
                call judge(err, gate, 'chain '//route_name(runs(ir)%route)//' '//form_name(form)//' rows seed='// &
                    &achar(48 + seeds(is)))
            end do
            ! the two routes' rows: their largest difference relative to the host route's largest |d|, reported
            dmax = nan_maxval(abs(real(runs(1)%rows, real64)))
            diff = nan_maxval(abs(real(runs(1)%rows, real64) - real(runs(2)%rows, real64))) / dmax
            write(line,'(a,i0,a,es12.5,a,i0,a,i0)') '    routes seed=', seeds(is), ': largest row difference ', diff, &
                &', rows'' values whose bits differ ', count(.not. bits_equal(runs(1)%rows, runs(2)%rows)), ' of ', &
                &size(runs(1)%rows)
            write(*,'(a)') trim(line)
        end do
        ! decision 16 for the chain: three runs of each route give the same rows, bit for bit
        fx = chain_fixture_of(ELEM_SEED_CALIBRATION)
        do ir = 1, 2
            same = .true.
            do pass = 1, 3
                again%route = runs(ir)%route
                again%form  = form
                if( allocated(again%rows) ) deallocate(again%rows)
                call chain_once(fx, again, nbad)
                if( pass == 1 )then
                    runs(ir)%rows = again%rows
                else
                    same = same .and. nbad == 0 .and. all(bits_equal(again%rows, runs(ir)%rows))
                endif
            end do
            call assert_true(same, 'chain '//route_name(runs(ir)%route)//' '//form_name(form)// &
                &': three runs give the same rows, bit for bit')
        end do
    end subroutine test_chain_rows

    ! on either route a block scored before memoize_ref_bins is refused; on the device route the shift maps and a
    ! change of route while the sections wait are refused
    subroutine test_chain_refusals
        type(chain_fixture)           :: fx
        type(polarft_calc)            :: pftc
        real(real32),     allocatable :: u(:,:), dists(:,:)
        integer,          allocatable :: irots(:,:)
        real(real64)                  :: prior_w
        integer                       :: ir, nbad, kscreen, i
        complex(real32)               :: pft(CH_PFTSZ, CH_KFROM:CH_KTO)
        complex(real32),  allocatable :: odd_bank(:,:,:), cmat(:,:,:)
        complex(real64),  allocatable :: f(:,:,:)
        type(proj_fixture)            :: pfx
        type(projector)               :: vol, vol_pad
        character(len=:), allocatable :: msg
        write(*,'(a)') 'test_chain_refusals'
        fx = chain_fixture_of(ELEM_SEED_CALIBRATION)
        ! the odd volume's bank by the batch projector, as the chain's projections make it
        pfx%name    = 'chain odd'
        pfx%n       = CH_N
        pfx%m       = 2 * CH_N
        pfx%pftsz   = CH_PFTSZ
        pfx%kfromto = [CH_KFROM, CH_KTO]
        pfx%tile    = 4
        pfx%vol     = fx%vols(:, :, :, 2)
        pfx%rots    = fx%rots
        call toy_project(pfx, odd_bank, msg)
        ! get_cmat: the padded transform between pad_fft and expand_cmat, against the oracle's packed field
        call vol%new([CH_N, CH_N, CH_N], 1._real32)
        call vol%set_rmat(fx%vols(:, :, :, 2), .false.)
        call vol_pad%new([2 * CH_N, 2 * CH_N, 2 * CH_N], 1._real32)
        call vol%pad_fft(vol_pad)
        cmat = vol_pad%get_cmat()
        allocate(f(2 * CH_N, 2 * CH_N, 2 * CH_N))
        f = oracle_proj_padded_field(real(fx%vols(:, :, :, 2), real64))
        call judge(nan_maxval(abs(cmplx(cmat, kind=real64) - f(1:CH_N+1, :,:))) / nan_maxval(abs(f)), &
            &POLAR_ROW_FACTOR * PROJ_FIXTURE_ERR, 'get_cmat: the padded transform')
        call vol_pad%expand_cmat()
        cmat = vol_pad%get_cmat()
        call assert_true(size(cmat) == 0 .and. index(vol_pad%message(), 'refused') > 0, &
            &'get_cmat after expand_cmat is refused')
        call vol_pad%kill()
        call vol%kill()
        do ir = 1, 2
            nbad = 0
            call chain_calc(pftc, merge(POLARFT_REF_ROUTES%host, POLARFT_REF_ROUTES%device, ir == 1))
            call chain_reproject(pftc, fx, PROJ_FORMS%graph, nbad)
            ! the projected section of a reference is the one the toy projects; once memoized the host route has
            ! only memos
            call pftc%get_ref_pft(2, .false., pft)
            call assert_true(all(bits_equal(pft, odd_bank(:, :, 2))), 'get_ref_pft on the '// &
                &route_name(merge(POLARFT_REF_ROUTES%host, POLARFT_REF_ROUTES%device, ir == 1))// &
                &' route returns the projected section')
            if( ir == 2 )then
                call pftc%set_ref_route(POLARFT_REF_ROUTES%host)
                call assert_true(index(pftc%message(), 'refused') > 0, &
                    &'the route cannot change while the projected sections wait')
            endif
            call pftc%memoize_refs()
            if( ir == 1 )then
                call pftc%get_ref_pft(2, .false., pft)
                call assert_true(index(pftc%message(), 'refused') > 0, &
                    &'get_ref_pft of a memoized reference is refused on the host route')
            endif
            call chain_particles(pftc, fx, nbad)
            allocate(u(CH_NSPACE, 4), dists(CH_NSPACE, 4), irots(CH_NSPACE, 4))
            u = 0.5_real32
            call pftc%set_block_variates(u)
            call pftc%score_block_posterior(4, [1, 3, 5, 7], CH_NSPACE, [(i, i = 1, CH_NSPACE)], fx%temps(1:4), &
                &dists, irots)
            call assert_true(index(pftc%message(), 'refused') > 0, 'a block before memoize_ref_bins is refused on '// &
                &'the '//route_name(merge(POLARFT_REF_ROUTES%host, POLARFT_REF_ROUTES%device, ir == 1))//' route')
            if( ir == 2 )then
                call pftc%setup_shiftmaps(1._real64, 2._real64, 1._real64, prior_w, kscreen)
                call assert_true(index(pftc%message(), 'device route') > 0, 'a shift map on the device route is refused')
                call pftc%new_shiftmap(1, [0._real64, 1._real64], 8, CH_KTO)
                call assert_true(index(pftc%message(), 'device route') > 0, &
                    &'new_shiftmap on the device route is refused')
            endif
            call assert_int(0, nbad, 'the refusals'' chain was set up')
            deallocate(dists, irots)
            if( allocated(u) ) deallocate(u)
            call pftc%kill()
        end do
    end subroutine test_chain_refusals

end module mlxf_toy_projector_tester
