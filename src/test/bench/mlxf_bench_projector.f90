!@descr: benchmark of the toy projector at SIMPLE's sizes: the reprojection of one state timed, chained to family A, and judged
! mlxf_test_exec test=bench_projector suite=<time|chain|accuracy> [key=value ...]. The case is SIMPLE's
! polar_matching_bench after cropping: box 160 padded to 320, pftsz 182, shells 2 to 62, the directions a
! golden-angle spiral with in-plane angle 0 (nspace=, 2,500 by default); the volumes are seeded blobs inside the
! radius 58. suite=time runs the canonical driver (per parity new, set_rmat, pad_fft, expand_cmat,
! vol_pad2ref_pfts_opt on the device route, kill) until both banks are evaluated; suite=chain continues to the
! reference tiles on the host or device route and scores 64 particles per parity; both append a row to
! ./bench_projector.tsv (the series columns scripts/run_parts.sh reads: samples per second 20, samples 21, MLX peak
! 26, cache 27, median pass 30) after a go file (go=). suite=accuracy holds 16 directions to the oracle on the
! device's own padded transform and asserts. A key the suite does not read stops the program.
module mlxf_bench_projector
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use, intrinsic :: iso_c_binding,   only: c_int, c_double
use mlxf,                         only: mlx_set_default_device, mlx_default_device, mlx_peak_memory, &
                                        mlx_reset_peak_memory, mlx_synchronize, mlx_active_memory, mlx_cache_memory, &
                                        MLX_DEVICES
use mlxf_test_defs,               only: OSMPL_PAD_FAC, PROJ_FORMS, PROJ_TILE_DEFAULT, PROJ_TG_DEFAULT, PROJ_TIE_MARGIN, &
                                        PROJ_BUDGET_B, PROJ_BENCH_ERR, POLAR_ROW_FACTOR, POLAR_CANON_BT, &
                                        POLAR_CANON_RT, POLARFT_REF_ROUTES, parameters
use mlxf_toy_polarft_calc,        only: polarft_calc, vol_pad2ref_pfts_opt
use mlxf_toy_projector,           only: projector
use mlxf_toy_projector_pft_batch, only: fproject_polar_batch_opt
use mlxf_oracle_projection,       only: oracle_proj_stencil, oracle_proj_edge_gather, oracle_proj_edge_index
use mlxf_test_utils,              only: assert_true, set_fixed_seed
use mlxf_test_reduce,             only: nan_maxval
implicit none
private

public :: run_bench_projector

! the case: the cropped box, its padding, the polar set, the default directions, the sampling distance
integer,      parameter :: BOX_CROP = 160
integer,      parameter :: BOX_PD   = OSMPL_PAD_FAC * BOX_CROP
integer,      parameter :: PFTSZ    = 182
integer,      parameter :: KFROM    = 2
integer,      parameter :: KTO      = 62
integer,      parameter :: NK       = KTO - KFROM + 1
integer,      parameter :: NSPACE   = 2500
real(real32), parameter :: SMPD     = 2.055_real32 * 180._real32 / 160._real32
! the volumes: blobs inside this radius (voxels), their number, widths and amplitudes, the noise of each parity
real(real64), parameter :: BLOB_RADIUS  = 58._real64
integer,      parameter :: NBLOBS       = 48
real(real64), parameter :: BLOB_SIG(2)  = [2._real64, 6._real64]
real(real64), parameter :: BLOB_AMP(2)  = [0.3_real64, 1._real64]
real(real64), parameter :: PARITY_NOISE = 0.05_real64
! the accuracy suite's directions: one in every ACC_STRIDE of the spiral
integer,      parameter :: NACC       = 16
integer,      parameter :: ACC_STRIDE = 156
! the chain's dense score: particles per parity
integer, parameter :: NPTCL_HALF = 64
! the golden angle in degrees
real(real64), parameter :: GOLDEN = 180._real64 * (3._real64 - sqrt(5._real64))
real(real64), parameter :: PI     = acos(-1._real64)
! the transforms' working memory, guessed, for the estimate of a process's device bytes
real(real64), parameter :: FFT_WORK_B = 0.3e9_real64
! the digest's starting state, the go file's polling interval (microseconds) and the longest wait for it (s)
integer(int64), parameter :: DIGEST_START = 88172645463325252_int64
integer,        parameter :: GO_POLL_US   = 10000
real(real64),   parameter :: GO_WAIT_MAX  = 3600._real64
! the keys each suite reads, blank separated; test and suite belong to the executable
character(len=*), parameter :: SUITE_KEYS(3) = [character(len=96) :: &
    &'time form tile tg nspace nthr nparts part go seed passes', &
    &'chain route form tile tg nspace nthr nparts part go seed passes', &
    &'accuracy form tile tg device seed']

! one configuration: the gather's form, directions per tile, threads per group, the route, the directions, the
! seed of the volumes, the timed passes
type :: bench_config
    integer      :: form   = PROJ_FORMS%graph
    integer      :: tile   = PROJ_TILE_DEFAULT
    integer      :: tg     = PROJ_TG_DEFAULT
    integer      :: route  = POLARFT_REF_ROUTES%device
    integer      :: nspace = NSPACE
    integer      :: seed   = 1
    integer      :: passes = 3
    real(real64) :: est    = 0._real64
end type bench_config

! one timed pass: its seconds to the evaluated banks (the driver) and, for the chain, to the reference tiles;
! the stages (pad and transform, expansion, projection), the chain's own stage (the banks to the tiles) and the
! dense score; the banks' digests (even, odd) and the score's
type :: pass_result
    real(real64)   :: wall      = 0._real64
    real(real64)   :: stages(3) = 0._real64
    real(real64)   :: chain     = 0._real64
    real(real64)   :: score     = 0._real64
    real(real64)   :: tv2r      = 0._real64
    integer        :: nbad      = 0
    integer(int64) :: dig(3)    = 0_int64
end type pass_result

! the case's data: the two volumes (even, odd) and the directions' matrices
type :: bench_data
    real(real32), allocatable :: vols(:,:,:,:)
    real(real32), allocatable :: eul(:,:,:)
end type bench_data

interface
    integer(c_int) function getloadavg( loadavg, nelem ) bind(c, name='getloadavg')
        import :: c_int, c_double
        real(c_double) :: loadavg(*)
        integer(c_int), value :: nelem
    end function getloadavg

    integer(c_int) function usleep( useconds ) bind(c, name='usleep')
        import :: c_int
        integer(c_int), value :: useconds
    end function usleep
end interface

contains

    subroutine run_bench_projector( suite, found )
        character(len=*), intent(in)  :: suite
        logical,          intent(out) :: found
        found = .true.
        call check_keys(suite)
        select case( trim(suite) )
            case( 'time' )
                call bench_time(.false.)
            case( 'chain' )
                call bench_time(.true.)
            case( 'accuracy' )
                call bench_accuracy
            case default
                found = .false.
        end select
    end subroutine run_bench_projector

    ! ---- arguments ---------------------------------------------------------------------------------------------

    function arg_str( key, dflt ) result(val)
        character(len=*), intent(in) :: key, dflt
        character(len=:), allocatable :: val
        character(len=512)            :: arg
        integer                       :: i
        val = dflt
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            if( index(arg, key//'=') == 1 ) val = trim(arg(len(key)+2:))
        end do
    end function arg_str

    logical function arg_given( key )
        character(len=*), intent(in) :: key
        character(len=512) :: arg
        integer            :: i
        arg_given = .false.
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            if( index(arg, key//'=') == 1 ) arg_given = .true.
        end do
    end function arg_given

    ! every key=value of the command line is one the suite reads; another stops the program with the key's name
    subroutine check_keys( suite )
        character(len=*), intent(in) :: suite
        character(len=512) :: arg
        character(len=96)  :: keys
        integer            :: i, ieq
        keys = ''
        do i = 1, size(SUITE_KEYS)
            if( index(SUITE_KEYS(i), trim(suite)//' ') == 1 ) keys = SUITE_KEYS(i)(len_trim(suite) + 1:)
        end do
        if( len_trim(keys) == 0 ) return
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            ieq = index(arg, '=')
            if( ieq > 1 )then
                if( arg(1:ieq-1) == 'test' .or. arg(1:ieq-1) == 'suite' ) cycle
                if( index(' '//trim(keys)//' ', ' '//arg(1:ieq-1)//' ') > 0 ) cycle
            endif
            write(*,'(a)') 'bench_projector: suite='//trim(suite)//' does not read '//trim(arg)//' (its keys:'// &
                &trim(keys)//')'
            error stop 2
        end do
    end subroutine check_keys

    integer function arg_int( key, dflt )
        character(len=*), intent(in) :: key
        integer,          intent(in) :: dflt
        character(len=:), allocatable :: s
        integer                       :: ios
        arg_int = dflt
        if( .not. arg_given(key) ) return
        s   = arg_str(key, '')
        ios = 1
        if( verify(s, '+-0123456789') == 0 ) read(s, *, iostat=ios) arg_int
        if( ios /= 0 )then
            write(*,'(a)') 'bench_projector: '//key//'='//s//' is not an integer'
            error stop 2
        endif
    end function arg_int

    ! the configuration of the command line
    function arg_config() result(cfg)
        type(bench_config) :: cfg
        select case( arg_str('form', 'graph') )
            case( 'graph' )
                cfg%form = PROJ_FORMS%graph
            case( 'fused' )
                cfg%form = PROJ_FORMS%fused
            case default
                write(*,'(a)') 'bench_projector: form= is graph or fused'
                error stop 2
        end select
        select case( arg_str('route', 'device') )
            case( 'host' )
                cfg%route = POLARFT_REF_ROUTES%host
            case( 'device' )
                cfg%route = POLARFT_REF_ROUTES%device
            case default
                write(*,'(a)') 'bench_projector: route= is host or device'
                error stop 2
        end select
        cfg%tile   = arg_int('tile', PROJ_TILE_DEFAULT)
        cfg%tg     = arg_int('tg', PROJ_TG_DEFAULT)
        cfg%nspace = arg_int('nspace', NSPACE)
        cfg%seed   = arg_int('seed', 1)
        cfg%passes = arg_int('passes', 3)
        if( cfg%tile < 1 .or. cfg%tg < 1 .or. cfg%nspace < 1 .or. cfg%passes < 1 )then
            write(*,'(a)') 'bench_projector: tile=, tg=, nspace= and passes= are at least 1'
            error stop 2
        endif
    end function arg_config

    ! ---- the case ----------------------------------------------------------------------------------------------

    ! the volume of a parity (1 even, 2 odd): NBLOBS Gaussian blobs inside BLOB_RADIUS, the same for both parities
    ! (from seed), plus each parity's own noise inside the radius; double precision, rounded once
    function make_volume( seed, parity ) result(v)
        integer, intent(in) :: seed, parity
        real(real32), allocatable :: v(:,:,:)
        real(real64), allocatable :: w(:,:,:)
        real(real64)              :: c(3, NBLOBS), sig(NBLOBS), amp(NBLOBS), u(5), x(3), r2
        integer                   :: b, i, j, k, lo(3), hi(3), h
        call set_fixed_seed(7919 * seed)
        do b = 1, NBLOBS
            do
                call random_number(u)
                c(:, b) = (2._real64 * u(1:3) - 1._real64) * BLOB_RADIUS
                sig(b)  = BLOB_SIG(1) + (BLOB_SIG(2) - BLOB_SIG(1)) * u(4)
                amp(b)  = BLOB_AMP(1) + (BLOB_AMP(2) - BLOB_AMP(1)) * u(5)
                if( norm2(c(:, b)) + 2._real64 * sig(b) <= BLOB_RADIUS ) exit
            end do
        end do
        allocate(w(BOX_CROP, BOX_CROP, BOX_CROP), source=0._real64)
        do b = 1, NBLOBS
            lo = max(1, floor(c(:, b) - 4._real64 * sig(b)) + 1 + BOX_CROP / 2)
            hi = min(BOX_CROP, ceiling(c(:, b) + 4._real64 * sig(b)) + 1 + BOX_CROP / 2)
            do k = lo(3), hi(3)
                do j = lo(2), hi(2)
                    do i = lo(1), hi(1)
                        x  = real([i, j, k] - 1 - BOX_CROP / 2, real64)
                        r2 = sum((x - c(:, b))**2)
                        w(i, j, k) = w(i, j, k) + amp(b) * exp(-r2 / (2._real64 * sig(b)**2))
                    end do
                end do
            end do
        end do
        call set_fixed_seed(7919 * seed + parity)
        do h = 1, BOX_CROP
            do j = 1, BOX_CROP
                do i = 1, BOX_CROP
                    x = real([i, j, h] - 1 - BOX_CROP / 2, real64)
                    if( sum(x**2) <= BLOB_RADIUS**2 )then
                        call random_number(u(1))
                        w(i, j, h) = w(i, j, h) + PARITY_NOISE * (2._real64 * u(1) - 1._real64)
                    endif
                end do
            end do
        end do
        v = real(w, real32)
    end function make_volume

    ! the spiral of n directions: polar angle acos(1 - (2i - 1)/n), azimuth i times the golden angle, in-plane angle
    ! 0, as SIMPLE's euler2m (double precision, rounded once)
    function spiral( n ) result(rots)
        integer, intent(in) :: n
        real(real32), allocatable :: rots(:,:,:)
        real(real64)              :: r1(3, 3), r2(3, 3), r21(3, 3), th, ph
        integer                   :: i
        allocate(rots(3, 3, n))
        do i = 1, n
            ph  = modulo(real(i, real64) * GOLDEN, 360._real64) * PI / 180._real64
            th  = acos(1._real64 - real(2 * i - 1, real64) / real(n, real64))
            r1  = reshape([cos(ph), -sin(ph), 0._real64, sin(ph), cos(ph), 0._real64, 0._real64, 0._real64, 1._real64], &
                &[3, 3])
            r2  = reshape([cos(th), 0._real64, sin(th), 0._real64, 1._real64, 0._real64, -sin(th), 0._real64, cos(th)], &
                &[3, 3])
            r21 = matmul(r2, r1)
            rots(:, :, i) = real(r21, real32)
        end do
    end function spiral

    ! the device bytes a process plans for (derived): the expanded cube, the two banks, the padded transform and
    ! cube, the transforms' work, a graph tile in flight (27 terms per sample: values, weights, positions and their
    ! products); for the chain the tiles of both parities, a bank's copy and, on the host route, the tiles' host
    ! staging and memos
    real(real64) function estimate_bytes( cfg, chain )
        type(bench_config), intent(in) :: cfg
        logical,            intent(in) :: chain
        real(real64) :: npts, e, b
        npts = real(PFTSZ * NK, real64)
        e    = real(BOX_PD + 5, real64)
        b    = 8._real64 * e**3 + 2._real64 * 8._real64 * npts * real(cfg%nspace, real64) + &
            &8._real64 * real(BOX_PD / 2 + 1, real64) * real(BOX_PD, real64)**2 + 4._real64 * real(BOX_PD, real64)**3 + &
            &FFT_WORK_B
        if( cfg%form == PROJ_FORMS%graph ) b = b + 27._real64 * npts * real(min(cfg%tile, cfg%nspace), real64) * 24._real64
        if( chain )then
            b = b + 2._real64 * 4._real64 * real(4 * NK, real64) * real(2 * POLAR_CANON_RT, real64) * &
                &real(PFTSZ + 1, real64) * real((cfg%nspace + POLAR_CANON_RT - 1) / POLAR_CANON_RT, real64)
            b = b + 8._real64 * npts * real(cfg%nspace, real64)
        endif
        estimate_bytes = b
    end function estimate_bytes

    ! ---- the driver --------------------------------------------------------------------------------------------

    ! SIMPLE's reprojection of state 1, both parities, into pftc; the seconds of vol_pad2ref_pfts_opt (tv2r) and
    ! the stages; nbad counts the refusals
    subroutine reproject( pftc, dat, cfg, res )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: dat
        type(bench_config), intent(in)    :: cfg
        type(pass_result),  intent(inout) :: res
        type(projector) :: vol, vol_pad
        real(real64)    :: t0
        integer         :: h
        res%tv2r = 0._real64
        do h = 1, 2
            call vol%new([BOX_CROP, BOX_CROP, BOX_CROP], SMPD)
            call vol%set_rmat(dat%vols(:, :, :, h), .false.)
            call vol_pad%new([BOX_PD, BOX_PD, BOX_PD], SMPD)
            call vol_pad%set_fproject_form(cfg%form)
            call vol_pad%set_fproject_tile(cfg%tile, cfg%tg)
            call vol%pad_fft(vol_pad)
            call vol_pad%expand_cmat()
            t0 = clock_s()
            call vol_pad2ref_pfts_opt(pftc, vol_pad, dat%eul, 1, h == 1)
            res%tv2r = res%tv2r + clock_s() - t0
            if( len(pftc%message()) > 0 )then
                res%nbad = res%nbad + 1
                write(*,'(a)') '    refused: '//pftc%message()
            endif
            res%stages = res%stages + vol_pad%fproject_seconds()
            call vol_pad%kill()
            call vol_pad%kill_expanded()
            call vol%kill()
        end do
    end subroutine reproject

    ! a calculator of the case for cfg's directions and route
    subroutine new_calc( pftc, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_config), intent(in)    :: cfg
        call pftc%new(parameters(pftsz=PFTSZ, box=BOX_CROP, nspace=cfg%nspace, nstates=1, box_crop=BOX_CROP), &
            &cfg%nspace, [1, 2 * NPTCL_HALF], [KFROM, KTO])
        call pftc%set_ref_route(cfg%route)
        call pftc%set_tile_plan(POLAR_CANON_BT, POLAR_CANON_RT)
    end subroutine new_calc

    ! the digests of both banks, from the calculator's sections (the device route) reference by reference
    subroutine bank_digests( pftc, nspace, dig )
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(in)    :: nspace
        integer(int64),     intent(out)   :: dig(2)
        complex(real32) :: pft(PFTSZ, KFROM:KTO)
        integer         :: h, i
        do h = 1, 2
            dig(h) = DIGEST_START
            do i = 1, nspace
                call pftc%get_ref_pft(i, h == 1, pft)
                call digest_bits(dig(h), transfer(pft, [0_int32]))
            end do
        end do
    end subroutine bank_digests

    ! the particles of the chain's dense score: 64 seeded rings per parity, shell weights k / sigma2
    subroutine set_particles( pftc, seed )
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(in)    :: seed
        real(real32) :: re(PFTSZ, NK), im(PFTSZ, NK), s2(NK, 2)
        real(real64) :: w(NK, 2)
        integer      :: i, k
        call set_fixed_seed(104729 * seed)
        call random_number(s2)
        do k = 1, NK
            w(k, :) = real(KFROM + k - 1, real64) / (0.5_real64 + real(s2(k, :), real64))
        end do
        call pftc%set_sigma2_weights(w)
        call pftc%reallocate_ptcls(2 * NPTCL_HALF, [(i, i = 1, 2 * NPTCL_HALF)])
        do i = 1, 2 * NPTCL_HALF
            call random_number(re)
            call random_number(im)
            call pftc%set_eo(i, mod(i, 2) == 1)
            call pftc%set_ptcl_pft(i, cmplx(2._real32 * re - 1._real32, 2._real32 * im - 1._real32, real32))
        end do
        call pftc%memoize_ptcls()
    end subroutine set_particles

    ! each parity's 64 particles against every reference; the digest of the entries
    subroutine dense_score( pftc, nspace, dig, nbad )
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(in)    :: nspace
        integer(int64),     intent(out)   :: dig
        integer,            intent(inout) :: nbad
        real(real32), allocatable :: u(:,:), dists(:,:)
        integer,      allocatable :: irots(:,:), pids(:), refs(:)
        integer                   :: h, i
        dig  = DIGEST_START
        refs = [(i, i = 1, nspace)]
        allocate(dists(nspace, NPTCL_HALF), irots(nspace, NPTCL_HALF))
        do h = 1, 2
            pids = [(i, i = h, 2 * NPTCL_HALF, 2)]
            allocate(u(nspace, NPTCL_HALF), source=0.5_real32)
            call pftc%set_block_variates(u)
            call pftc%score_block_posterior(NPTCL_HALF, pids, nspace, refs, [(1._real32, i = 1, NPTCL_HALF)], dists, &
                &irots)
            if( len(pftc%message()) > 0 ) nbad = nbad + 1
            call digest_bits(dig, transfer(dists, [0_int32]))
            call digest_bits(dig, int(reshape(irots, [size(irots)]), int32))
            if( allocated(u) ) deallocate(u)
        end do
    end subroutine dense_score

    ! suite=time (chain false) or suite=chain: a warm-up pass, then the timed passes; one row of bench_projector.tsv
    subroutine bench_time( chain )
        logical, intent(in) :: chain
        type(bench_config)             :: cfg
        type(polarft_calc)             :: pftc
        type(pass_result), allocatable :: res(:)
        type(bench_data)               :: dat
        real(real64)                   :: t0, t1
        character(len=:),  allocatable :: suite
        integer                        :: ip, nbad, ibest
        suite = merge('chain', 'time ', chain)
        write(*,'(a)') '**** bench_projector suite='//trim(suite)//' ****'
        call mlx_set_default_device(MLX_DEVICES%gpu)
        cfg = arg_config()
        if( .not. chain ) cfg%route = POLARFT_REF_ROUTES%device
        cfg%est = estimate_bytes(cfg, chain)
        write(*,'(a,es11.4,a,es11.4,a)') '    estimated device bytes ', cfg%est, ' (budget ', PROJ_BUDGET_B, ')'
        if( cfg%est > PROJ_BUDGET_B )then
            write(*,'(a)') 'bench_projector: the configuration is above PROJ_BUDGET_B: not run'
            allocate(res(1))
            call write_row(trim(suite), cfg, res, 1, 'over_budget')
            error stop 3
        endif
        allocate(dat%vols(BOX_CROP, BOX_CROP, BOX_CROP, 2))
        dat%vols(:, :, :, 1) = make_volume(cfg%seed, 1)
        dat%vols(:, :, :, 2) = make_volume(cfg%seed, 2)
        dat%eul = spiral(cfg%nspace)
        if( .not. chain ) call new_calc(pftc, cfg)
        call wait_for_go
        call mlx_reset_peak_memory()
        allocate(res(0:cfg%passes))
        nbad = 0
        do ip = 0, cfg%passes
            if( chain )then
                call new_calc(pftc, cfg)
                t0 = clock_s()
                call reproject(pftc, dat, cfg, res(ip))
                t1 = clock_s()
                call pftc%memoize_refs()
                if( len(pftc%message()) > 0 ) nbad = nbad + 1
                res(ip)%wall  = clock_s() - t0
                res(ip)%chain = (res(ip)%tv2r - res(ip)%stages(3)) + (t0 + res(ip)%wall - t1)
                call set_particles(pftc, cfg%seed)
                t1 = clock_s()
                call dense_score(pftc, cfg%nspace, res(ip)%dig(3), nbad)
                res(ip)%score = clock_s() - t1
                call pftc%kill()
            else
                t0 = clock_s()
                call reproject(pftc, dat, cfg, res(ip))
                res(ip)%wall = clock_s() - t0
                call bank_digests(pftc, cfg%nspace, res(ip)%dig(1:2))
            endif
            write(*,'(a,i0,a,f9.4,a,3f9.4,a,2f9.4,3(a,z16.16))') '    pass ', ip, ': ', res(ip)%wall, ' s; stages ', &
                &res(ip)%stages, '; chain, score ', res(ip)%chain, res(ip)%score, '; digests ', res(ip)%dig(1), ' ', &
                &res(ip)%dig(2), ' ', res(ip)%dig(3)
            flush(6)
        end do
        call mlx_synchronize()
        nbad = nbad + sum(res%nbad)
        call assert_true(nbad == 0, 'bench_projector: every step of the driver carried out')
        ibest = minloc(res(1:)%wall, 1)
        write(*,'(a,i0,a,f9.4,a)') '    best pass ', ibest, ': ', res(ibest)%wall, ' s'
        call write_row(trim(suite), cfg, res, ibest, merge('ok    ', 'failed', nbad == 0))
        if( .not. chain ) call pftc%kill()
    end subroutine bench_time

    ! one row of bench_projector.tsv and the digest lines
    subroutine write_row( suite, cfg, res, ibest, status )
        character(len=*),   intent(in) :: suite, status
        type(bench_config), intent(in) :: cfg
        type(pass_result),  intent(in) :: res(0:)
        integer,            intent(in) :: ibest
        character(len=*), parameter   :: TSV = 'bench_projector.tsv'
        character(len=1), parameter   :: T = achar(9)
        real(real64),     allocatable :: walls(:)
        real(real64)                  :: samples, wbest, wmed, rep(3)
        integer                       :: u, np, i, ip
        logical                       :: l_new
        np      = ubound(res, 1)
        samples = 2._real64 * real(cfg%nspace, real64) * real(PFTSZ * NK, real64)
        rep     = -1._real64
        wbest   = -1._real64
        wmed    = -1._real64
        if( np >= 1 )then
            walls = res(1:np)%wall
            do i = 1, min(3, np)
                rep(i) = walls(i)
            end do
            wbest = res(ibest)%wall
            call sort_real(walls)
            if( mod(np, 2) == 1 )then
                wmed = walls((np + 1) / 2)
            else
                wmed = 0.5_real64 * (walls(np / 2) + walls(np / 2 + 1))
            endif
        endif
        ip = max(0, min(ibest, np))
        inquire(file=TSV, exist=l_new)
        l_new = .not. l_new
        open(newunit=u, file=TSV, position='append', action='write', status='unknown')
        if( l_new ) write(u,'(a)') 'suite'//T//'nspace'//T//'pftsz'//T//'nk'//T//'box'//T//'boxpd'//T//'form'//T// &
            &'tile'//T//'tg'//T//'route'//T//'device'//T//'precision'//T//'nthr'//T//'nparts'//T//'part'//T//'load1'// &
            &T//'wall_s'//T//'wall_rep1'//T//'wall_rep2'//T//'samples_per_s'//T//'samples'//T//'pad_fft_s'//T// &
            &'expand_s'//T//'project_s'//T//'est_bytes'//T//'mlx_peak_bytes'//T//'mlx_cache_bytes'//T//'status'//T// &
            &'passes'//T//'wall_median_s'//T//'wall_rep3'//T//'chain_s'//T//'score_s'//T//'mlx_active_bytes'//T// &
            &'digest_even'//T//'digest_odd'//T//'digest_score'
        write(u,'(a,5(a,i0),a,a,2(a,i0),a,a,a,a,a,a,3(a,i0),a,f6.2,3(a,f10.4),a,es12.5,a,es12.5,3(a,f10.4),'// &
            &'3(a,es12.5),a,a,a,i0,a,f10.4,a,f10.4,2(a,f10.4),a,es12.5,3(a,z16.16))') &
            &suite, T, cfg%nspace, T, PFTSZ, T, NK, T, BOX_CROP, T, BOX_PD, T, form_name(cfg%form), T, cfg%tile, T, &
            &cfg%tg, T, route_name(cfg%route), T, 'gpu', T, precision_mode(), T, arg_int('nthr', 1), T, &
            &arg_int('nparts', 1), T, arg_int('part', 1), T, load_average(), T, wbest, T, rep(1), T, rep(2), T, &
            &merge(samples / wbest, -1._real64, wbest > 0._real64), T, samples, T, res(ip)%stages(1), T, &
            &res(ip)%stages(2), T, res(ip)%stages(3), T, cfg%est, T, real(mlx_peak_memory(), real64), T, &
            &real(mlx_cache_memory(), real64), T, trim(status), T, cfg%passes, T, wmed, T, rep(3), T, res(ip)%chain, &
            &T, res(ip)%score, T, real(mlx_active_memory(), real64), T, res(ip)%dig(1), T, res(ip)%dig(2), T, &
            &res(ip)%dig(3)
        close(u)
        write(*,'(a,es12.5,a,es12.5,a,f9.4,a,es11.4,2(a,es10.3))') '    samples ', samples, ', best ', &
            &merge(samples / wbest, -1._real64, wbest > 0._real64), ' samples/s, median pass ', wmed, ' s; est ', cfg%est, &
            &' B, peak ', real(mlx_peak_memory(), real64), ' B, cache ', real(mlx_cache_memory(), real64)
        do i = 1, np
            write(*,'(a,i0,3(a,z16.16))') '    digest '//suite//' pass ', i, ' ', res(i)%dig(1), ' ', res(i)%dig(2), ' ', &
                &res(i)%dig(3)
        end do
    end subroutine write_row

    ! ---- accuracy ----------------------------------------------------------------------------------------------

    ! NACC directions of the spiral projected from the even volume of seed=, on device=, against the oracle's edge
    ! gather on the device's own padded transform (get_cmat) in double precision: a sample's error over the sum of
    ! |w f| of its 27 terms, near ties counted apart; judged against the frozen PROJ_BENCH_ERR's gate
    subroutine bench_accuracy
        type(bench_config)           :: cfg
        type(polarft_calc)           :: pftc
        type(projector)              :: vol, vol_pad
        real(real32),    allocatable :: eul(:,:,:), sel(:,:,:), vols(:,:,:), tmp(:,:)
        complex(real32), allocatable :: cmat(:,:,:), refs(:,:,:)
        complex(real64), allocatable :: p(:,:,:), y(:)
        real(real64),    allocatable :: t(:,:), scale(:), e(:)
        logical,         allocatable :: tie(:)
        real(real32)                 :: hk(2, PFTSZ, NK)
        real(real64)                 :: w(3, 3), err
        integer                      :: h(3, 3), i, j, l, s, c, k, ip, a, ntie
        character(len=200)           :: line
        write(*,'(a)') '**** bench_projector suite=accuracy ****'
        cfg = arg_config()
        if( arg_str('device', 'gpu') == 'cpu' )then
            call mlx_set_default_device(MLX_DEVICES%cpu)
        else
            call mlx_set_default_device(MLX_DEVICES%gpu)
        endif
        eul = spiral(NSPACE)
        allocate(sel(3, 3, NACC))
        do i = 1, NACC
            sel(:, :, i) = eul(:, :, 1 + (i - 1) * ACC_STRIDE)
        end do
        vols = make_volume(cfg%seed, 1)
        call pftc%new(parameters(pftsz=PFTSZ, box=BOX_CROP, nspace=NACC, box_crop=BOX_CROP), NACC, [1, 1], [KFROM, KTO])
        call vol%new([BOX_CROP, BOX_CROP, BOX_CROP], SMPD)
        call vol%set_rmat(vols, .false.)
        call vol_pad%new([BOX_PD, BOX_PD, BOX_PD], SMPD)
        call vol_pad%set_fproject_form(cfg%form)
        call vol_pad%set_fproject_tile(cfg%tile, cfg%tg)
        call vol%pad_fft(vol_pad)
        cmat = vol_pad%get_cmat()
        call vol_pad%expand_cmat()
        allocate(refs(PFTSZ, NK, NACC))
        call fproject_polar_batch_opt(vol_pad, sel, NACC, pftc, refs)
        call assert_true(len(vol_pad%message()) == 0 .and. size(cmat) > 0, 'bench_projector accuracy: projected: '// &
            &vol_pad%message())
        call vol_pad%kill()
        call vol%kill()
        ! the samples' coordinates in double precision from the single-precision inputs
        allocate(tmp(KFROM:KTO, PFTSZ))
        call pftc%get_polar_coords(1, tmp)
        hk(1, :,:) = real(OSMPL_PAD_FAC, real32) * transpose(tmp)
        call pftc%get_polar_coords(2, tmp)
        hk(2, :,:) = real(OSMPL_PAD_FAC, real32) * transpose(tmp)
        call pftc%kill()
        allocate(t(3, PFTSZ * NK * NACC), tie(PFTSZ * NK * NACC))
        s = 0
        do i = 1, NACC
            do k = 1, NK
                do ip = 1, PFTSZ
                    s = s + 1
                    do a = 1, 3
                        t(a, s) = real(hk(1, ip, k), real64) * real(sel(1, a, i), real64) + &
                                  &real(hk(2, ip, k), real64) * real(sel(2, a, i), real64)
                    end do
                    tie(s) = any(abs(t(:, s) - (floor(t(:, s)) + 0.5_real64)) < PROJ_TIE_MARGIN)
                end do
            end do
        end do
        ! the oracle on the device's own transform, widened
        allocate(p(BOX_PD / 2 + 1, BOX_PD, BOX_PD))
        p = cmplx(cmat, kind=real64)
        deallocate(cmat)
        y = real(OSMPL_PAD_FAC**3, real64) * oracle_proj_edge_gather(t, p)
        allocate(scale(size(y)))
        do s = 1, size(y)
            do a = 1, 3
                call oracle_proj_stencil(t(a, s), h(:, a), w(:, a))
            end do
            scale(s) = 0._real64
            do l = 1, 3
                do j = 1, 3
                    do i = 1, 3
                        c = oracle_proj_edge_index(h(i, 1), BOX_PD)
                        if( c >= 0 )then
                            scale(s) = scale(s) + abs(w(i, 1) * w(j, 2) * w(l, 3)) * &
                                &abs(p(1 + c, 1 + modulo(h(j, 2), BOX_PD), 1 + modulo(h(l, 3), BOX_PD)))
                        else
                            scale(s) = scale(s) + abs(w(i, 1) * w(j, 2) * w(l, 3)) * &
                                &abs(p(1 - c, 1 + modulo(-h(j, 2), BOX_PD), 1 + modulo(-h(l, 3), BOX_PD)))
                        endif
                    end do
                end do
            end do
            scale(s) = real(OSMPL_PAD_FAC**3, real64) * scale(s)
        end do
        e    = abs(cmplx(reshape(refs, [size(refs)]), kind=real64) - y) / max(scale, tiny(1._real64))
        ntie = count(tie)
        err  = nan_maxval(merge(e, 0._real64, .not. tie))
        write(line,'(a,i0,a,i0,a,i0,a,es16.9,a,es10.3)') '    accuracy '//form_name(cfg%form)//' seed=', cfg%seed, &
            &': near ties ', ntie, ', judged ', size(e) - ntie, ', error ', err, ' gate ', POLAR_ROW_FACTOR * PROJ_BENCH_ERR
        write(*,'(a)') trim(line)//' on the '//merge('cpu', 'gpu', mlx_default_device() == MLX_DEVICES%cpu)
        write(line,'(a,es12.5)') '    accuracy: the near ties'' largest error (reported) ', &
            &nan_maxval(merge(e, 0._real64, tie))
        write(*,'(a)') trim(line)
        call assert_true(err <= POLAR_ROW_FACTOR * PROJ_BENCH_ERR, 'bench_projector accuracy within PROJ_BENCH_ERR''s gate')
    end subroutine bench_accuracy

    ! ---- helpers -----------------------------------------------------------------------------------------------

    ! with go=<file>: the data are ready, so <file>.ready.<part> is written, and the process waits until <file>
    ! exists; without the key it returns at once
    subroutine wait_for_go
        character(len=:), allocatable :: go
        character(len=16)             :: part
        real(real64)                  :: t0
        integer                       :: u
        integer(c_int)                :: rc
        logical                       :: l_go
        if( .not. arg_given('go') ) return
        go = arg_str('go', '')
        write(part, '(i0)') arg_int('part', 1)
        open(newunit=u, file=go//'.ready.'//trim(part), action='write', status='replace')
        write(u,'(a)') 'ready'
        close(u)
        write(*,'(a)') '    ready; waiting for '//go
        flush(6)
        t0 = clock_s()
        do
            inquire(file=go, exist=l_go)
            if( l_go ) exit
            if( clock_s() - t0 > GO_WAIT_MAX )then
                write(*,'(a)') 'bench_projector: no go file '//go//' appeared'
                error stop 2
            endif
            rc = usleep(int(GO_POLL_US, c_int))
        end do
    end subroutine wait_for_go

    ! each pattern enters by exclusive or and the state takes one 64-bit shift-register step
    pure subroutine digest_bits( h, bits )
        integer(int64), intent(inout) :: h
        integer(int32), intent(in)    :: bits(:)
        integer :: i
        do i = 1, size(bits)
            h = ieor(h, iand(int(bits(i), int64), 4294967295_int64))
            h = ieor(h, ishft(h, 13))
            h = ieor(h, ishft(h, -7))
            h = ieor(h, ishft(h, 17))
        end do
    end subroutine digest_bits

    ! insertion sort, ascending (a few passes)
    pure subroutine sort_real( x )
        real(real64), intent(inout) :: x(:)
        real(real64) :: v
        integer      :: i, j
        do i = 2, size(x)
            v = x(i)
            j = i - 1
            do while( j >= 1 )
                if( .not. (x(j) > v) ) exit
                x(j + 1) = x(j)
                j = j - 1
            end do
            x(j + 1) = v
        end do
    end subroutine sort_real

    real(real64) function clock_s()
        integer(int64) :: count, rate
        call system_clock(count, rate)
        clock_s = real(count, real64) / real(rate, real64)
    end function clock_s

    real function load_average()
        real(c_double) :: l(3)
        load_average = -1.
        if( getloadavg(l, 3_c_int) >= 1 ) load_average = real(l(1))
    end function load_average

    function precision_mode() result(mode)
        character(len=:), allocatable :: mode
        character(len=32)             :: v
        integer                       :: n, st
        call get_environment_variable('MLX_ENABLE_TF32', v, n, st)
        mode = 'full'
        if( st == 0 .and. n > 0 .and. trim(v) /= '0' ) mode = 'tf32'
    end function precision_mode

    function form_name( form ) result(name)
        integer, intent(in) :: form
        character(len=:), allocatable :: name
        name = 'graph'
        if( form == PROJ_FORMS%fused ) name = 'fused'
    end function form_name

    function route_name( route ) result(name)
        integer, intent(in) :: route
        character(len=:), allocatable :: name
        name = 'host'
        if( route == POLARFT_REF_ROUTES%device ) name = 'device'
    end function route_name

end module mlxf_bench_projector
