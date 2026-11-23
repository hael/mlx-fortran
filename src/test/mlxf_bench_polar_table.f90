!@descr: benchmark of the polar table workspace at SIMPLE's sizes: accuracy block, timing sweep, profile, overlap, shift maps
! mlxf_test_exec test=bench_polar_table suite=<accuracy|time|profile|overlap|stream|shiftmap> [key=value ...]. The
! case geometry comes from a key = value file of SIMPLE's measured cases (cases=, case=), the shift maps' grid from
! another (grid=, maps=); the data are synthetic: reference rings, particles as CTF times a rotated reference plus
! noise, memos by a double-precision DFT. The accuracy mode holds the 64,000-pair block to its DFT-matrix oracle
! and the frozen bounds; the other modes append measure-only rows to ./bench_polar_table*.tsv.
module mlxf_bench_polar_table
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use, intrinsic :: iso_c_binding, only: c_int, c_double
!$ use omp_lib,               only: omp_get_max_threads
use mlxf,                     only: mlx_set_default_device, mlx_default_device, mlx_peak_memory, mlx_reset_peak_memory, &
                                    mlx_synchronize, mlx_clear_cache, mlx_device_info_size, MLX_DEVICES, &
                                    mlx_active_memory
use mlxf_test_defs,           only: POLAR_FORMS, POLAR_MAP_FORMS, POLAR_ROW_FACTOR, POLAR_BLOCK_ERR_CPU, &
                                    POLAR_BLOCK_ROT_CPU, POLAR_BLOCK_ROT_Q, POLAR_SEED_CALIBRATION, POLAR_SEED_JUDGED, &
                                    POLAR_GRID_B, POLAR_GRID_R, POLAR_BUDGET_SHARE, POLAR_CANON_BT, POLAR_CANON_RT, &
                                    POLAR_BLOCK_BT, POLAR_BLOCK_RT, POLAR_PROB_BETA, polar_table_refs, &
                                    polar_table_block, polar_table_entries, polar_map_spec, polar_map_block, &
                                    polar_map_results, polar_row_check
use mlxf_kernel_polar_table,  only: polar_table
use mlxf_kernel_polar_oracle, only: polar_dft_matrix, polar_keyed_u, polar_compare_rows, polar_draws_off, &
                                    polar_report_draws, polar_memo_rows
use mlxf_test_utils,          only: assert_true, assert_int, test_devices, device_name, set_fixed_seed, bits_equal
implicit none
private

public :: run_bench_polar_table

! the accuracy block: particles (half each half) against references per half, at SIMPLE's case geometry
integer, parameter :: BLOCK_NPTCLS = 64
integer, parameter :: BLOCK_NREFS  = 1000
! distinct reference rings generated per half; larger reference sets reuse them in turn (timing only)
integer, parameter :: POOL_RINGS = 1000
! the particles' inverse temperatures, in turn: the production median (about 420) and three around it
real(real32), parameter :: TEMP_LEVELS(4) = [1._real32, 30._real32, 420._real32, 1.e4_real32]
! the estimate's count of rotation-row temporaries a tile's tail holds at once (conservative)
integer, parameter :: TAIL_ROWS = 12

! one of SIMPLE's measured cases
type :: bench_case
    character(len=64) :: name    = ''
    integer           :: nspace  = 0
    integer           :: nstates = 0
    integer           :: nrefs   = 0
    integer           :: nptcls  = 0
    integer           :: pftsz   = 0
    integer           :: kfrom   = 0
    integer           :: kto     = 0
end type bench_case

! one shift map of SIMPLE's measured grid (blocks [map name]) and SIMPLE's full-team rate on it (two invocations)
type :: bench_map
    character(len=64) :: name    = ''
    integer           :: pftsz   = 0
    integer           :: nrots   = 0
    integer           :: kfrom   = 0
    integer           :: kscreen = 0
    integer           :: nrho    = 0
    integer           :: nalpha  = 0
    integer           :: norder  = 0
    integer           :: nrefs   = 0
    integer           :: nptcls  = 0
    integer           :: ncand   = 0
    real(real64)      :: rho_max = 0._real64
    real(real64)      :: prior_w = 0._real64
    real(real64)      :: cpu_maps_per_s(2) = -1._real64
    character(len=64) :: simple_commit = 'unknown'
    character(len=16) :: fftw_plans = 'unknown'
end type bench_map

! one shift-map configuration: the particles of a tile (each with all its candidates), the walls of the 3 repeats, the preparation of the
! references and of the maps, the profiled pass's wall and stages (construction, mode, width, copy-out), the
! MLX peak, the estimate checked against the budget, the load, the Bessel order used and the status
type :: map_timing
    integer        :: ptcl_tile   = 0
    integer        :: norder_used = 0
    real(real64)   :: walls(3)    = -1._real64
    real(real64)   :: prep(2)     = -1._real64
    real(real64)   :: pwall       = -1._real64
    real(real64)   :: stages(4)   = 0._real64
    real(real64)   :: peak        = -1._real64
    real(real64)   :: est         = -1._real64
    real           :: load1       = -1.
    integer(int64) :: terms(2) = 0_int64
    integer        :: width_pairs = 0
    real(real64)   :: cold = -1._real64, resident = -1._real64, host_bytes = -1._real64, tile_bytes = -1._real64
    character(len=:), allocatable :: status
end type map_timing

! the synthetic data of a case: each half's references (memos, global IDs 1..nrefs) and every particle's memos,
! weighted square sum over all shells (wsq) and square sum of each shell's half ring (psq)
type :: bench_data
    type(bench_case)             :: cs
    integer                      :: seed = 0
    type(polar_table_refs)       :: refs(2)
    real(real32),    allocatable :: w(:,:)
    complex(real32), allocatable :: ctf2(:,:,:)
    complex(real32), allocatable :: xctf(:,:,:)
    real(real64),    allocatable :: wsq(:)
    real(real64),    allocatable :: psq(:,:)
    real(real32),    allocatable :: temps(:)
end type bench_data

! how a half is scored: the particles of one call (outer), the CPU team of the host preparation and
! consumption, one or two slots, rows wanted, stages profiled
type :: score_plan
    integer :: outer   = 0
    integer :: team    = 1
    integer :: nslots  = 1
    logical :: rows    = .false.
    logical :: profile = .false.
end type score_plan

! a half's entries by (reference in prepared order, particle of the half in order), rows when asked, and the
! seconds of the host's preparation and consumption
type :: half_table
    real(real32), allocatable :: dists(:,:)
    integer,      allocatable :: irots(:,:)
    real(real32), allocatable :: rows(:,:,:)
    real(real64)              :: cpu_s    = 0._real64
    real(real64)              :: submit_s = 0._real64
end type half_table

! a tile plan and formulation of a workspace
type :: bench_config
    integer :: bt          = POLAR_BLOCK_BT
    integer :: rt          = POLAR_BLOCK_RT
    integer :: formulation = POLAR_FORMS%b
end type bench_config

interface
    integer(c_int) function getloadavg( loadavg, nelem ) bind(c, name='getloadavg')
        import :: c_int, c_double
        real(c_double) :: loadavg(*)
        integer(c_int), value :: nelem
    end function getloadavg
end interface

contains

    subroutine run_bench_polar_table( suite, found )
        character(len=*), intent(in)  :: suite
        logical,          intent(out) :: found
        found = .true.
        select case( trim(suite) )
            case( 'accuracy' )
                call bench_accuracy
            case( 'time' )
                call bench_time
            case( 'profile' )
                call bench_profile
            case( 'overlap' )
                call bench_overlap
            case( 'stream' )
                call bench_stream
            case( 'shiftmap' )
                call bench_shiftmap
            case default
                found = .false.
        end select
    end subroutine run_bench_polar_table

    ! ---- arguments, cases, data ------------------------------------------------------------------------

    ! the value of key=value on the command line, or dflt
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

    integer function arg_int( key, dflt )
        character(len=*), intent(in) :: key
        integer,          intent(in) :: dflt
        character(len=:), allocatable :: s
        integer                       :: ios
        s       = arg_str(key, '')
        arg_int = dflt
        if( len(s) > 0 ) read(s, *, iostat=ios) arg_int
        if( ios /= 0 ) arg_int = dflt
    end function arg_int

    ! the tile plan of bt= and rt=, and the formulation named by form= (b, the default, or c)
    function arg_config( dflt ) result(cfg)
        type(bench_config), intent(in) :: dflt
        type(bench_config)            :: cfg
        character(len=:), allocatable :: f
        cfg    = dflt
        cfg%bt = arg_int('bt', dflt%bt)
        cfg%rt = arg_int('rt', dflt%rt)
        f      = arg_str('form', 'b')
        if( f == 'c' ) cfg%formulation = POLAR_FORMS%c
    end function arg_config

    function form_name( cfg ) result(name)
        type(bench_config), intent(in) :: cfg
        character(len=:), allocatable :: name
        name = 'B+compiled'
        if( cfg%formulation == POLAR_FORMS%c ) name = 'C+compiled'
    end function form_name

    ! a case of the key = value file (blocks [case name]); stops when absent, a benchmark's usage error
    function read_case( path, name ) result(cs)
        character(len=*), intent(in) :: path, name
        type(bench_case)   :: cs
        character(len=512) :: line, key, val
        integer            :: u, ios, ieq
        logical            :: inside
        open(newunit=u, file=path, status='old', action='read', iostat=ios)
        if( ios /= 0 )then
            write(*,'(a)') 'bench_polar_table: cannot open the case file '//trim(path)//' (cases=)'
            error stop 2
        endif
        inside = .false.
        do
            read(u, '(a)', iostat=ios) line
            if( ios /= 0 ) exit
            line = adjustl(line)
            if( len_trim(line) == 0 .or. line(1:1) == '#' ) cycle
            if( line(1:1) == '[' )then
                inside = trim(line) == '[case '//trim(name)//']'
                cycle
            endif
            if( .not. inside ) cycle
            ieq = index(line, '=')
            if( ieq == 0 ) cycle
            key = adjustl(line(1:ieq-1))
            val = adjustl(line(ieq+1:))
            select case( trim(key) )
                case( 'nspace' )
                    read(val, *) cs%nspace
                case( 'nstates' )
                    read(val, *) cs%nstates
                case( 'nrefs' )
                    read(val, *) cs%nrefs
                case( 'nptcls' )
                    read(val, *) cs%nptcls
                case( 'pftsz' )
                    read(val, *) cs%pftsz
                case( 'kfrom' )
                    read(val, *) cs%kfrom
                case( 'kto' )
                    read(val, *) cs%kto
            end select
        end do
        close(u)
        cs%name = name
        if( cs%nrefs < 1 .or. cs%nptcls < 2 .or. cs%pftsz < 2 .or. cs%kto < cs%kfrom )then
            write(*,'(a)') 'bench_polar_table: no complete case '//trim(name)//' in '//trim(path)
            error stop 2
        endif
    end function read_case

    ! the half of a particle by its global ID: half 1 (SIMPLE's even half) holds the odd IDs
    pure integer function half_of( pid )
        integer, intent(in) :: pid
        half_of = 2
        if( mod(pid, 2) == 1 ) half_of = 1
    end function half_of

    function half_ptcls( nptcls, half ) result(pids)
        integer, intent(in) :: nptcls, half
        integer, allocatable :: pids(:)
        integer              :: i
        pids = [(i, i = half, nptcls, 2)]
    end function half_ptcls

    ! the first size(e,1) bins of the forward DFT of the full ring of half ring z (the samples, then their
    ! conjugates), summed in ring order as polar_dft_bins sums them; no allocation (OpenMP regions call it)
    pure subroutine ring_bins( e, z, y )
        complex(real64), intent(in)  :: e(:,:), z(:)
        complex(real64), intent(out) :: y(:)
        integer :: p, m, n
        n = size(z)
        do p = 1, size(e, 1)
            y(p) = (0._real64, 0._real64)
            do m = 1, n
                y(p) = y(p) + z(m) * e(p, m)
            end do
            do m = 1, n
                y(p) = y(p) + conjg(z(m)) * e(p, n + m)
            end do
        end do
    end subroutine ring_bins

    ! the synthetic data of a case: references per half (POOL_RINGS distinct rings, reused in turn), particles as CTF
    ! times a rotated reference of their half plus noise, shell weights k / sigma2, inverse temperatures in turn
    function make_data( cs, seed ) result(d)
        type(bench_case), intent(in) :: cs
        integer,          intent(in) :: seed
        type(bench_data)             :: d
        complex(real64), allocatable :: e(:,:), rpool(:,:,:,:), zw(:,:), yw(:,:)
        complex(real32), allocatable :: m1(:,:,:,:), m2(:,:,:,:)
        real(real32),    allocatable :: re(:,:), im(:,:), s2(:,:), ctf(:,:), noise(:,:,:)
        complex(real64), allocatable :: x(:,:), z(:)
        real(real64)                 :: amp
        integer                      :: nk, n1, nrots, npool, h, r, k, i, j, src, shift, ithr, nthr, idx
        nk    = cs%kto - cs%kfrom + 1
        n1    = cs%pftsz + 1
        nrots = 2 * cs%pftsz
        npool = min(POOL_RINGS, cs%nrefs)
        d%cs   = cs
        d%seed = seed
        call set_fixed_seed(seed)
        allocate(s2(nk, 2), re(cs%pftsz, nk), im(cs%pftsz, nk), rpool(cs%pftsz, nk, npool, 2), d%w(nk, 2))
        call random_number(s2)
        do h = 1, 2
            do k = 1, nk
                d%w(k, h) = real(real(cs%kfrom + k - 1, real64) / (0.5_real64 + real(s2(k, h), real64)), real32)
            end do
            do r = 1, npool
                call random_number(re)
                call random_number(im)
                do k = 1, nk
                    amp = exp(-real(k - 1, real64) / real(max(1, nk / 2), real64))
                    rpool(:, k, r, h) = cmplx(real(2*re(:, k) - 1, real64) * amp, real(2*im(:, k) - 1, real64) * amp, &
                        &real64)
                end do
            end do
        end do
        e = polar_dft_matrix(nrots, n1)
        nthr = 1
        !$ nthr = omp_get_max_threads()
        allocate(zw(cs%pftsz, nthr), yw(n1, nthr), m1(n1, nk, npool, 2), m2(n1, nk, npool, 2))
        ! the pool's memos: ft_ref the transform of the ring, ft_ref2 the conjugated transform of |ring|^2
        !$omp parallel do default(shared) private(idx, h, r, k, ithr) schedule(dynamic, 16) proc_bind(close)
        do idx = 1, 2 * npool * nk
            ithr = thread_index()
            h = (idx - 1) / (npool * nk) + 1
            r = mod((idx - 1) / nk, npool) + 1
            k = mod(idx - 1, nk) + 1
            zw(:, ithr) = rpool(:, k, r, h)
            call ring_bins(e, zw(:, ithr), yw(:, ithr))
            m1(:, k, r, h) = cmplx(yw(:, ithr), kind=real32)
            zw(:, ithr) = cmplx(abs(rpool(:, k, r, h))**2, 0._real64, real64)
            call ring_bins(e, zw(:, ithr), yw(:, ithr))
            m2(:, k, r, h) = cmplx(conjg(yw(:, ithr)), kind=real32)
        end do
        !$omp end parallel do
        do h = 1, 2
            d%refs(h)%pftsz = cs%pftsz
            d%refs(h)%nk    = nk
            d%refs(h)%half  = h
            d%refs(h)%ids   = [(r, r = 1, cs%nrefs)]
            allocate(d%refs(h)%ft_ref(n1, nk, cs%nrefs), d%refs(h)%ft_ref2(n1, nk, cs%nrefs))
            do r = 1, cs%nrefs
                d%refs(h)%ft_ref(:, :, r)  = m1(:, :, mod(r - 1, npool) + 1, h)
                d%refs(h)%ft_ref2(:, :, r) = m2(:, :, mod(r - 1, npool) + 1, h)
            end do
        end do
        deallocate(m1, m2)
        ! the particles: CTF in [0.2, 1), the source ring rotated by shift samples, noise at 0.3 of the shell's
        ! amplitude; wsq = sum_k w_k sum |X|^2 over the half ring
        allocate(d%ctf2(n1, nk, cs%nptcls), d%xctf(n1, nk, cs%nptcls), d%wsq(cs%nptcls), d%psq(nk, cs%nptcls), &
            &d%temps(cs%nptcls))
        allocate(ctf(cs%pftsz, nk), noise(cs%pftsz, nk, 2), x(cs%pftsz, nk), z(nrots))
        do i = 1, cs%nptcls
            h        = half_of(i)
            src      = mod(7 * i, npool) + 1
            shift    = mod(13 * i, nrots)
            call random_number(re)
            ctf = real(0.2_real64 + 0.8_real64 * real(re, real64), real32)
            call random_number(noise)
            d%wsq(i) = 0._real64
            do k = 1, nk
                amp = exp(-real(k - 1, real64) / real(max(1, nk / 2), real64))
                z(1:cs%pftsz)       = rpool(:, k, src, h)
                z(cs%pftsz+1:nrots) = conjg(rpool(:, k, src, h))
                do j = 1, cs%pftsz
                    x(j, k) = real(ctf(j, k), real64) * z(1 + mod(j - 1 - shift + nrots, nrots)) + 0.3_real64 * amp * &
                        &cmplx(real(2*noise(j, k, 1) - 1, real64), real(2*noise(j, k, 2) - 1, real64), real64)
                end do
                x(:, k)     = cmplx(cmplx(x(:, k), kind=real32), kind=real64)
                d%psq(k, i) = sum(abs(x(:, k))**2)
                d%wsq(i)    = d%wsq(i) + real(d%w(k, h), real64) * d%psq(k, i)
            end do
            do k = 1, nk
                zw(:, 1) = cmplx(real(ctf(:, k), real64)**2, 0._real64, real64)
                call ring_bins(e, zw(:, 1), yw(:, 1))
                d%ctf2(:, k, i) = cmplx(yw(:, 1), kind=real32)
                zw(:, 1) = x(:, k) * real(ctf(:, k), real64)
                call ring_bins(e, zw(:, 1), yw(:, 1))
                d%xctf(:, k, i) = cmplx(yw(:, 1), kind=real32)
            end do
            d%temps(i) = TEMP_LEVELS(mod(i - 1, size(TEMP_LEVELS)) + 1)
        end do
    end function make_data

    ! the calling thread's number from 1 (OpenMP), 1 without OpenMP
    integer function thread_index()
        !$ use omp_lib, only: omp_get_thread_num
        thread_index = 1
        !$ thread_index = omp_get_thread_num() + 1
    end function thread_index

    ! the block of particles pids (global IDs) of one half, prepared by a CPU team of team threads: memos,
    ! weights, wsq, temperatures and the pairs' variates keyed by global IDs
    function make_block( d, half, pids, generation, team ) result(blk)
        type(bench_data), intent(in) :: d
        integer,          intent(in) :: half, pids(:), team
        integer(int64),   intent(in) :: generation
        type(polar_table_block) :: blk
        integer                 :: b, r, nr, n1, nk
        nr = size(d%refs(half)%ids)
        n1 = size(d%ctf2, 1)
        nk = size(d%ctf2, 2)
        blk%half       = half
        blk%generation = generation
        blk%ref_ids    = d%refs(half)%ids
        blk%ptcl_ids   = pids
        blk%weights    = d%w(:, half)
        allocate(blk%ctf2(n1, nk, size(pids)), blk%xctf(n1, nk, size(pids)), blk%wsq(size(pids)), &
            &blk%temps(size(pids)), blk%u(nr, size(pids)))
        !$omp parallel do num_threads(team) default(shared) private(b, r) schedule(static) proc_bind(close)
        do b = 1, size(pids)
            blk%ctf2(:, :, b) = d%ctf2(:, :, pids(b))
            blk%xctf(:, :, b) = d%xctf(:, :, pids(b))
            blk%wsq(b)        = d%wsq(pids(b))
            blk%temps(b)      = d%temps(pids(b))
            do r = 1, nr
                blk%u(r, b) = real(polar_keyed_u(d%seed, pids(b), blk%ref_ids(r)), real32)
            end do
        end do
        !$omp end parallel do
    end function make_block

    ! a half scored in outer batches of plan%outer particles, one slot or two in flight; the entries are
    ! consumed into the half's table by the CPU team (by the particle's place in the half)
    function score_half( ws, d, half, plan ) result(tab)
        class(polar_table), intent(inout) :: ws
        type(bench_data),   intent(in)    :: d
        integer,            intent(in)    :: half
        type(score_plan),   intent(in)    :: plan
        type(half_table)          :: tab
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: ent
        integer, allocatable      :: pids(:), first(:)
        integer                   :: nb, k, nbat, st, slot, nr
        real(real64)              :: t0
        pids = half_ptcls(d%cs%nptcls, half)
        nr   = size(d%refs(half)%ids)
        nbat = (size(pids) + plan%outer - 1) / plan%outer
        allocate(tab%dists(nr, size(pids)), tab%irots(nr, size(pids)), first(nbat + 1))
        if( plan%rows ) allocate(tab%rows(2 * d%cs%pftsz, nr, size(pids)))
        do k = 1, nbat + 1
            first(k) = min((k - 1) * plan%outer + 1, size(pids) + 1)
        end do
        ! slot k of batch k: with two slots, batch k+1 is queued before batch k is collected
        do k = 1, nbat
            slot = 1
            if( plan%nslots == 2 ) slot = mod(k - 1, 2) + 1
            t0  = clock_s()
            blk = make_block(d, half, pids(first(k):first(k+1)-1), 1_int64, plan%team)
            blk%rows    = plan%rows
            blk%profile = plan%profile
            tab%cpu_s   = tab%cpu_s + (clock_s() - t0)
            t0 = clock_s()
            call ws%submit(blk, slot, st)
            tab%submit_s = tab%submit_s + (clock_s() - t0)
            call assert_int(0, st, 'bench_polar_table: a batch is submitted: '//ws%message())
            if( st /= 0 ) return
            if( plan%nslots == 2 .and. k > 1 ) call collect_batch(k - 1)
            if( plan%nslots == 1 ) call collect_batch(k)
        end do
        if( plan%nslots == 2 ) call collect_batch(nbat)

      contains

        subroutine collect_batch( kb )
            integer, intent(in) :: kb
            integer :: cslot, b, b0
            cslot = 1
            if( plan%nslots == 2 ) cslot = mod(kb - 1, 2) + 1
            call ws%collect(cslot, ent, st)
            call assert_int(0, st, 'bench_polar_table: a batch is collected: '//ws%message())
            if( st /= 0 ) return
            t0 = clock_s()
            nb = first(kb+1) - first(kb)
            b0 = first(kb) - 1
            !$omp parallel do num_threads(plan%team) default(shared) private(b) schedule(static) proc_bind(close)
            do b = 1, nb
                tab%dists(:, b0 + b) = ent%dists(:, b)
                tab%irots(:, b0 + b) = ent%irots(:, b)
                if( plan%rows ) tab%rows(:, :, b0 + b) = ent%rows(:, :, b)
            end do
            !$omp end parallel do
            tab%cpu_s = tab%cpu_s + (clock_s() - t0)
        end subroutine collect_batch

    end function score_half

    ! a workspace of half's references under cfg; generation 1
    subroutine prepare( ws, d, half, cfg )
        class(polar_table), intent(inout) :: ws
        type(bench_data),   intent(inout) :: d
        integer,            intent(in)    :: half
        type(bench_config), intent(in)    :: cfg
        integer :: st
        d%refs(half)%rt          = cfg%rt
        d%refs(half)%bt          = cfg%bt
        d%refs(half)%formulation = cfg%formulation
        d%refs(half)%generation  = 1_int64
        call ws%new(d%refs(half), st)
        call assert_int(0, st, 'bench_polar_table: the references are prepared: '//ws%message())
    end subroutine prepare

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

    ! the precision of MLX's float32 products in this process: full unless MLX_ENABLE_TF32 is set to non-zero
    function precision_mode() result(mode)
        character(len=:), allocatable :: mode
        character(len=32)             :: v
        integer                       :: n, st
        call get_environment_variable('MLX_ENABLE_TF32', v, n, st)
        mode = 'full'
        if( st == 0 .and. n > 0 .and. trim(v) /= '0' ) mode = 'tf32'
    end function precision_mode

    ! ---- accuracy -------------------------------------------------------------------------------------------

    ! the 64,000-pair block (BLOCK_NPTCLS particles, BLOCK_NREFS references per half, the case's geometry):
    ! the CPU calibration (block seed 1, reported) and, on every device, seed 2 against the DFT-matrix oracle and
    ! the frozen bounds, the sensitivities and schedule identity
    subroutine bench_accuracy
        type(bench_case)          :: cs
        type(bench_data)          :: d1, d2
        type(bench_config)        :: cfg
        real(real64), allocatable :: or1(:,:,:,:), or2(:,:,:,:)
        integer, allocatable      :: devs(:)
        integer                   :: i, original
        write(*,'(a)') '**** bench_polar_table suite=accuracy ****'
        cs        = read_case(arg_str('cases', 'polar_case.txt'), arg_str('case', '2500_4'))
        cs%nrefs  = BLOCK_NREFS
        cs%nptcls = BLOCK_NPTCLS
        cfg       = arg_config(bench_config())
        call test_devices(devs)
        original = mlx_default_device()
        d2  = make_data(cs, POLAR_SEED_JUDGED)
        or2 = oracle_halves(d2)
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))//', formulation '//form_name(cfg)
            if( devs(i) == MLX_DEVICES%cpu )then
                if( .not. allocated(or1) )then
                    d1  = make_data(cs, POLAR_SEED_CALIBRATION)
                    or1 = oracle_halves(d1)
                endif
                call report_block_calibration(d1, or1, cfg)
            endif
            call judge_block(device_name(devs(i)), d2, or2, cfg)
            call block_sensitivity(device_name(devs(i)), d2, or2, cfg)
            call block_identity(device_name(devs(i)), d2, cfg)
        end do
        call mlx_set_default_device(original)
    end subroutine bench_accuracy

    ! the DFT-matrix oracle's rows of both halves: (nrots, nrefs, particles of the half, half)
    function oracle_halves( d ) result(dor)
        type(bench_data), intent(in) :: d
        real(real64), allocatable :: dor(:,:,:,:)
        type(polar_table_block)   :: blk
        integer                   :: h
        allocate(dor(2 * d%cs%pftsz, d%cs%nrefs, d%cs%nptcls / 2, 2))
        do h = 1, 2
            blk = make_block(d, h, half_ptcls(d%cs%nptcls, h), 1_int64, 1)
            dor(:, :, :, h) = polar_memo_rows(d%refs(h), blk)
        end do
    end function oracle_halves

    ! both halves scored under cfg with rows, compared with the oracle; the totals of both halves
    function score_and_compare( d, dor, cfg, plan, report ) result(chk)
        type(bench_data),   intent(inout) :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        type(score_plan),   intent(in)    :: plan
        logical,            intent(in)    :: report
        type(polar_row_check)     :: chk
        type(polar_row_check)     :: c
        type(polar_table)         :: ws
        type(half_table)          :: tab
        type(polar_table_entries) :: ent
        type(polar_table_block)   :: blk
        integer                   :: h
        do h = 1, 2
            call prepare(ws, d, h, cfg)
            tab = score_half(ws, d, h, plan)
            call ws%kill()
            if( .not. allocated(tab%rows) ) return
            ent%dists = tab%dists
            ent%irots = tab%irots
            ent%rows  = tab%rows
            blk = make_block(d, h, half_ptcls(d%cs%nptcls, h), 1_int64, 1)
            c   = polar_compare_rows(dor(:, :, :, h), ent)
            c%draws_bad = polar_draws_off(ent, blk%temps, blk%u)
            chk%err        = max(chk%err, c%err)
            chk%argmin_off = chk%argmin_off + c%argmin_off
            chk%valid_off  = chk%valid_off + c%valid_off
            chk%npairs     = chk%npairs + c%npairs
            chk%draws_bad  = chk%draws_bad + c%draws_bad
            chk%mixed      = chk%mixed + c%mixed
            chk%invalid    = chk%invalid + c%invalid
            if( report ) call polar_report_draws('block', d%seed, dor(:, :, :, h), ent, blk)
        end do
    end function score_and_compare

    function canonical_plan( rows ) result(plan)
        logical, intent(in) :: rows
        type(score_plan) :: plan
        plan%outer  = BLOCK_NPTCLS / 2
        plan%team   = 1
        plan%nslots = 1
        plan%rows   = rows
    end function canonical_plan

    ! the block calibration on the CPU device, block seed 1: e_cpu and n_cpu, reported
    subroutine report_block_calibration( d, dor, cfg )
        type(bench_data),   intent(inout) :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        type(polar_row_check) :: chk
        chk = score_and_compare(d, dor, cfg, canonical_plan(.true.), .false.)
        write(*,'(a,es23.16,a,i0,a,i0,a,i0,a,i0,a,i0)') '    calibration (block seed 1, cpu, '//form_name(cfg)// &
            &'): e_cpu = ', chk%err, ', n_cpu = ', chk%argmin_off, ' of ', chk%npairs, ' pairs; validity off ', &
            &chk%valid_off, ', draws off ', chk%draws_bad, ', mixed rows ', chk%mixed
    end subroutine report_block_calibration

    ! block seed 2 on the current device against the oracle: validity, the draw on the device's rows, and the
    ! block's frozen bounds; the draws reported per temperature
    subroutine judge_block( dev, d, dor, cfg )
        character(len=*),   intent(in)    :: dev
        type(bench_data),   intent(inout) :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        type(polar_row_check) :: chk
        type(score_plan)      :: plan
        plan = canonical_plan(.true.)
        chk  = score_and_compare(d, dor, cfg, plan, .true.)
        write(*,'(a,es10.3,a,i0,a,i0,a)') '    block seed 2 ('//dev//', '//form_name(cfg)//'): row error ', chk%err, &
            &', minimising rotation differs in ', chk%argmin_off, ' of ', chk%npairs, ' pairs'
        call assert_int(BLOCK_NPTCLS * BLOCK_NREFS, chk%npairs, 'the accuracy block scores 64,000 pairs')
        call assert_int(0, chk%valid_off, dev//' block: every entry is valid or invalid as in the oracle')
        call assert_int(0, chk%draws_bad, dev//' block: the draw lies in the device row''s cumulative interval '//&
            &'within 1e-4 W, and the entry''s distance is the row''s')
        call assert_block_bounds(dev//' block '//form_name(cfg), chk)
    end subroutine judge_block

    ! the block's frozen bounds: row error at most POLAR_ROW_FACTOR e_cpu, minimising-rotation disagreements at
    ! most max(POLAR_ROW_FACTOR n_cpu, q)
    subroutine assert_block_bounds( label, chk )
        character(len=*),      intent(in) :: label
        type(polar_row_check), intent(in) :: chk
        write(*,'(a,es10.3,a,i0)') '    '//label//': error ', chk%err, ', rotations differing ', chk%argmin_off
        call assert_true(chk%err <= POLAR_ROW_FACTOR * POLAR_BLOCK_ERR_CPU, label//': the rows'' error is within '//&
            &'twice the block calibration''s e_cpu')
        call assert_true(chk%argmin_off <= max(nint(POLAR_ROW_FACTOR) * POLAR_BLOCK_ROT_CPU, POLAR_BLOCK_ROT_Q), &
            &label//': the minimising rotation differs from the oracle''s in at most max(2 n_cpu, 5) pairs')
    end subroutine assert_block_bounds

    ! tile shape, partial edges, particle position and a shuffled reference list, each
    ! judged against the frozen bounds and reported against the canonical configuration
    subroutine block_sensitivity( dev, d, dor, cfg )
        character(len=*),   intent(in)    :: dev
        type(bench_data),   intent(inout) :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        type(bench_config)    :: v
        type(polar_row_check) :: chk
        v    = cfg
        v%bt = 32
        v%rt = 1000
        chk  = score_and_compare(d, dor, v, canonical_plan(.true.), .false.)
        call assert_int(0, chk%valid_off + chk%draws_bad, dev//' tile shape 32 x 1000: validity and draws hold')
        call assert_block_bounds(dev//' tile shape 32 x 1000', chk)
        v    = cfg
        v%bt = 12
        v%rt = 300
        chk  = score_and_compare(d, dor, v, canonical_plan(.true.), .false.)
        call assert_int(0, chk%valid_off + chk%draws_bad, dev//' partial edges 12 x 300: validity and draws hold')
        call assert_block_bounds(dev//' partial edges 12 x 300', chk)
        call position_and_list(dev, d, dor, cfg)
    end subroutine block_sensitivity

    ! the particles in reversed order (every tile position changes) and the references prepared in a shuffled
    ! order (global IDs kept): judged against the bounds, entries compared by global pair with the canonical run
    subroutine position_and_list( dev, d, dor, cfg )
        character(len=*),   intent(in)    :: dev
        type(bench_data),   intent(inout) :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        type(polar_table)         :: ws
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: e0, e1
        type(polar_table_refs)    :: shuffled
        type(polar_row_check)     :: chk
        real(real64), allocatable :: dsub(:,:,:)
        integer, allocatable      :: pids(:), perm(:)
        integer                   :: st, h, n, i, r, ndiff_pos, ndiff_list
        ndiff_pos  = 0
        ndiff_list = 0
        do h = 1, 2
            pids = half_ptcls(d%cs%nptcls, h)
            n    = size(pids)
            call prepare(ws, d, h, cfg)
            blk      = make_block(d, h, pids, 1_int64, 1)
            blk%rows = .true.
            call ws%score(blk, e0, st)
            blk      = make_block(d, h, pids(n:1:-1), 1_int64, 1)
            blk%rows = .true.
            call ws%score(blk, e1, st)
            call assert_int(0, st, dev//' reversed particles are scored')
            if( st /= 0 ) return
            dsub = dor(:, :, n:1:-1, h)
            chk  = polar_compare_rows(dsub, e1)
            call assert_int(0, chk%valid_off + polar_draws_off(e1, blk%temps, blk%u), dev//' reversed particles: '//&
                &'validity and draws hold')
            call assert_block_bounds(dev//' reversed particles', chk)
            do i = 1, n
                ndiff_pos = ndiff_pos + count(.not. bits_equal(e1%dists(:, n + 1 - i), e0%dists(:, i)))
            end do
            call ws%kill()
            ! the references in a shuffled order, IDs kept: entries come back in that order
            perm = [(mod(37 * i, size(d%refs(h)%ids)) + 1, i = 0, size(d%refs(h)%ids) - 1)]
            shuffled            = d%refs(h)
            shuffled%ids        = d%refs(h)%ids(perm)
            shuffled%ft_ref     = d%refs(h)%ft_ref(:, :, perm)
            shuffled%ft_ref2    = d%refs(h)%ft_ref2(:, :, perm)
            shuffled%rt         = cfg%rt
            shuffled%bt         = cfg%bt
            shuffled%generation = 1_int64
            call ws%new(shuffled, st)
            blk          = make_block(d, h, pids, 1_int64, 1)
            blk%ref_ids  = shuffled%ids
            do i = 1, n
                do r = 1, size(perm)
                    blk%u(r, i) = real(polar_keyed_u(d%seed, pids(i), shuffled%ids(r)), real32)
                end do
            end do
            blk%rows = .true.
            call ws%score(blk, e1, st)
            call assert_int(0, st, dev//' shuffled references are scored')
            if( st /= 0 ) return
            dsub = dor(:, perm, :, h)
            chk  = polar_compare_rows(dsub, e1)
            call assert_int(0, chk%valid_off + polar_draws_off(e1, blk%temps, blk%u), dev//' shuffled references: '//&
                &'validity and draws hold')
            call assert_block_bounds(dev//' shuffled references', chk)
            ndiff_list = ndiff_list + count(.not. bits_equal(e1%dists, e0%dists(perm, :)))
            call ws%kill()
        end do
        write(*,'(a,i0,a,i0,a)') '    '//dev//' entries differing from the canonical run by global pair: reversed '//&
            &'particles ', ndiff_pos, ', shuffled references ', ndiff_list, ' (reported)'
    end subroutine position_and_list

    ! schedule identity on the block, exact: three repeats, outer batches of 32 and 16, CPU teams 1 and 24, and
    ! synchronous against two slots give identical entries by global pair
    subroutine block_identity( dev, d, cfg )
        character(len=*),   intent(in)    :: dev
        type(bench_data),   intent(inout) :: d
        type(bench_config), intent(in)    :: cfg
        type(polar_table) :: ws
        type(half_table)  :: t0, t
        type(score_plan)  :: plan
        integer           :: h, rep
        logical           :: same_rep, same_outer, same_team, same_slots
        same_rep   = .true.
        same_outer = .true.
        same_team  = .true.
        same_slots = .true.
        do h = 1, 2
            call prepare(ws, d, h, cfg)
            plan = canonical_plan(.false.)
            t0   = score_half(ws, d, h, plan)
            do rep = 1, 3
                t = score_half(ws, d, h, plan)
                same_rep = same_rep .and. same_table(t, t0)
            end do
            plan%outer = BLOCK_NPTCLS / 4
            t          = score_half(ws, d, h, plan)
            same_outer = same_outer .and. same_table(t, t0)
            plan%team  = 24
            t          = score_half(ws, d, h, plan)
            same_team  = same_team .and. same_table(t, t0)
            plan%team   = 1
            plan%outer  = BLOCK_NPTCLS / 4
            plan%nslots = 2
            t           = score_half(ws, d, h, plan)
            same_slots  = same_slots .and. same_table(t, t0)
            call ws%kill()
        end do
        call assert_true(same_rep, dev//' block identity: three repeats give identical entries')
        call assert_true(same_outer, dev//' block identity: outer batches of 32 and 16 give identical entries')
        call assert_true(same_team, dev//' block identity: CPU teams of 1 and 24 give identical entries')
        call assert_true(same_slots, dev//' block identity: two slots give the synchronous entries')
    end subroutine block_identity

    logical function same_table( a, b )
        type(half_table), intent(in) :: a, b
        same_table = allocated(a%dists) .and. allocated(b%dists)
        if( same_table ) same_table = all(shape(a%dists) == shape(b%dists))
        if( same_table ) same_table = all(bits_equal(a%dists, b%dists))
        if( same_table ) same_table = all(a%irots == b%irots)
    end function same_table

    ! ---- timing ---------------------------------------------------------------------------------------------

    ! the estimated device bytes of a configuration: both halves' resident tiles, one call's particle inputs and
    ! terms, and one tile's products, rows and tail temporaries, doubled when two slots are in flight
    real(real64) function estimate_bytes( cs, cfg, nslots )
        type(bench_case),   intent(in) :: cs
        type(bench_config), intent(in) :: cfg
        integer,            intent(in) :: nslots
        real(real64) :: n1, nk, nrots, rpad, bpad, refs, inputs, tile
        n1    = real(cs%pftsz + 1, real64)
        nk    = real(cs%kto - cs%kfrom + 1, real64)
        nrots = real(2 * cs%pftsz, real64)
        rpad  = real(((cs%nrefs + cfg%rt - 1) / cfg%rt) * cfg%rt, real64)
        bpad  = real(((cs%nptcls / 2 + cfg%bt - 1) / cfg%bt) * cfg%bt, real64)
        refs  = 2._real64 * 4._real64 * nk * rpad * n1 * 8._real64
        inputs = n1 * nk * bpad * 8._real64 * 4._real64 + rpad * bpad * 4._real64 * 2._real64
        tile   = real(cfg%bt, real64) * real(cfg%rt, real64) * (n1 * 16._real64 + nrots * 4._real64 * TAIL_ROWS)
        estimate_bytes = refs + real(nslots, real64) * (inputs + tile)
    end function estimate_bytes

    ! the sweep of decision 13's grid over one case (case=) or the cases named by cases_list=, in one
    ! formulation: configurations above the particles per half, above the references or beyond the budget are
    ! pruned before any allocation; each kept one is prepared, warmed up and timed best of 3 (both halves, all
    ! particles, from the memos through the entries in Fortran arrays)
    subroutine bench_time
        type(bench_case)              :: cs
        type(bench_data)              :: d
        type(bench_config)            :: cfg
        character(len=:), allocatable :: names
        integer,          allocatable :: bs(:), rs(:)
        integer                       :: ib, ir, ic, i0
        write(*,'(a)') '**** bench_polar_table suite=time ****'
        write(*,'(a,f0.1,a)') '    memory budget ', budget_bytes() / 1.e9_real64, ' GB (a share of the GPU''s memory_size)'
        call mlx_set_default_device(device_of_arg())
        names = arg_str('cases_list', arg_str('case', '2500_4'))
        bs    = POLAR_GRID_B
        rs    = POLAR_GRID_R
        if( arg_int('bt', 0) > 0 ) bs = [arg_int('bt', 0)]
        if( arg_int('rt', 0) > 0 ) rs = [arg_int('rt', 0)]
        i0 = 1
        do ic = 1, len(names) + 1
            if( ic <= len(names) )then
                if( names(ic:ic) /= ',' ) cycle
            endif
            cs = read_case(arg_str('cases', 'polar_case.txt'), names(i0:ic-1))
            i0 = ic + 1
            d  = make_data(cs, POLAR_SEED_JUDGED)
            do ib = 1, size(bs)
                do ir = 1, size(rs)
                    cfg    = arg_config(bench_config())
                    cfg%bt = bs(ib)
                    cfg%rt = rs(ir)
                    call time_config(d, cfg)
                end do
            end do
        end do
    end subroutine bench_time

    ! the memory budget of one configuration: POLAR_BUDGET_SHARE of the machine's memory as the GPU reports it;
    ! without that report the benchmark cannot keep its budget, a usage error
    real(real64) function budget_bytes()
        integer(int64) :: mem
        mem = mlx_device_info_size(MLX_DEVICES%gpu, 'memory_size')
        if( mem <= 0_int64 )then
            write(*,'(a)') 'bench_polar_table: the GPU reports no memory_size; the memory budget cannot be set'
            error stop 2
        endif
        budget_bytes = POLAR_BUDGET_SHARE * real(mem, real64)
    end function budget_bytes

    ! the status of a configuration pruned for the budget, with the budget in GB
    function budget_status() result(status)
        character(len=:), allocatable :: status
        character(len=32)             :: gb
        write(gb, '(f0.1)') budget_bytes() / 1.e9_real64
        status = 'pruned: estimate beyond the '//trim(gb)//' GB budget'
    end function budget_status

    integer function device_of_arg()
        device_of_arg = MLX_DEVICES%gpu
        if( arg_str('device', 'gpu') == 'cpu' ) device_of_arg = MLX_DEVICES%cpu
    end function device_of_arg

    ! one configuration of the sweep: pruned with its reason, or timed; one row of bench_polar_table.tsv
    subroutine time_config( d, cfg )
        type(bench_data),   intent(inout) :: d
        type(bench_config), intent(in)    :: cfg
        type(polar_table)             :: ws(2)
        type(half_table)              :: tab
        type(score_plan)              :: plan
        character(len=:), allocatable :: status
        real(real64)                  :: walls(3), t0, prep, est, cpu_s
        real(real64)                  :: peak
        real                          :: load1
        integer                       :: h, rep, nh
        nh     = d%cs%nptcls / 2
        est    = estimate_bytes(d%cs, cfg, 1)
        status = 'timed'
        if( cfg%bt > nh ) status = 'pruned: B above the particles per half'
        if( cfg%rt > d%cs%nrefs ) status = 'pruned: R_t above the references'
        if( status == 'timed' )then
            if( est > budget_bytes() ) status = budget_status()
        endif
        walls = -1._real64
        prep  = -1._real64
        peak  = -1._real64
        cpu_s = 0._real64
        load1 = load_average()
        if( status == 'timed' )then
            plan%outer = nh
            plan%team  = arg_int('nthr', 24)
            t0 = clock_s()
            do h = 1, 2
                call prepare(ws(h), d, h, cfg)
            end do
            call mlx_synchronize()
            prep = clock_s() - t0
            do h = 1, 2
                tab = score_half(ws(h), d, h, plan)
            end do
            call mlx_synchronize()
            call mlx_reset_peak_memory()
            do rep = 1, 3
                t0 = clock_s()
                do h = 1, 2
                    tab   = score_half(ws(h), d, h, plan)
                    cpu_s = cpu_s + tab%cpu_s
                end do
                walls(rep) = clock_s() - t0
            end do
            peak = real(mlx_peak_memory(), real64)
            do h = 1, 2
                call ws(h)%kill()
            end do
            call mlx_clear_cache()
        endif
        call write_time_row(d, cfg, [walls, prep, est, peak, cpu_s / 3._real64], load1, status)
    end subroutine time_config

    ! a row of bench_polar_table.tsv: SIMPLE's case columns by name, then the tile, formulation, device,
    ! precision, preparation and memory; vals = wall_rep1..3, prep_s, est_bytes, mlx_peak_bytes, cpu_s
    subroutine write_time_row( d, cfg, vals, load1, status )
        type(bench_data),   intent(in) :: d
        type(bench_config), intent(in) :: cfg
        real(real64),       intent(in) :: vals(7)
        real,               intent(in) :: load1
        character(len=*),   intent(in) :: status
        character(len=*), parameter :: TSV = 'bench_polar_table.tsv'
        character(len=1), parameter :: T = achar(9)
        real(real64)                :: wall, pairs, padded
        integer                     :: u, nrots, rpad, bpad
        logical                     :: l_new
        nrots  = 2 * d%cs%pftsz
        wall   = -1._real64
        if( all(vals(1:3) > 0._real64) ) wall = minval(vals(1:3))
        pairs  = real(d%cs%nrefs, real64) * real(d%cs%nptcls, real64)
        rpad   = ((d%cs%nrefs + cfg%rt - 1) / cfg%rt) * cfg%rt
        bpad   = ((d%cs%nptcls / 2 + cfg%bt - 1) / cfg%bt) * cfg%bt
        padded = 2._real64 * real(rpad, real64) * real(bpad, real64)
        inquire(file=TSV, exist=l_new)
        l_new = .not. l_new
        open(newunit=u, file=TSV, position='append', action='write', status='unknown')
        if( l_new ) write(u,'(a)') 'case'//T//'nspace'//T//'nstates'//T//'nrefs'//T//'nptcls'//T//'pftsz'//T//&
            &'nrots'//T//'kfrom'//T//'kto'//T//'B'//T//'R'//T//'formulation'//T//'device'//T//'precision'//T//&
            &'load1'//T//'wall_s'//T//'wall_rep1'//T//'wall_rep2'//T//'wall_rep3'//T//'pairs_per_s'//T//&
            &'useful_pairs'//T//'padded_pairs'//T//'prep_s'//T//'host_cpu_s'//T//'est_bytes'//T//'mlx_peak_bytes'//&
            &T//'status'
        write(u,'(a,10(a,i0),a,a,a,a,a,a,a,f6.2,4(a,f10.4),a,es12.5,2(a,es12.5),2(a,f10.4),2(a,es12.5),a,a)') &
            &trim(d%cs%name), T, d%cs%nspace, T, d%cs%nstates, T, d%cs%nrefs, T, d%cs%nptcls, T, d%cs%pftsz, T, &
            &nrots, T, d%cs%kfrom, T, d%cs%kto, T, cfg%bt, T, cfg%rt, T, form_name(cfg), T, &
            &device_name(mlx_default_device()), T, precision_mode(), T, load1, T, wall, T, vals(1), T, vals(2), T, &
            &vals(3), T, merge(pairs / wall, -1._real64, wall > 0._real64), T, pairs, T, padded, T, vals(4), T, &
            &vals(7), T, vals(5), T, vals(6), T, status
        close(u)
        write(*,'(a,i0,a,i0,a,f9.4,a,es11.4,a,es10.3,a)') '    '//trim(d%cs%name)//' '//form_name(cfg)//' B=', &
            &cfg%bt, ' R=', cfg%rt, ' wall=', wall, ' s, ', merge(pairs / wall, -1._real64, wall > 0._real64), &
            &' pairs/s, peak ', vals(6), ' B: '//status
    end subroutine write_time_row

    ! ---- profile ---------------------------------------------------------------------------------------------

    ! one configuration (case=, bt=, rt=, form=) scored with an evaluation barrier after every stage:
    ! the stages' seconds summed over both halves, and the copy-out apart; best of 3 after a warm-up
    subroutine bench_profile
        type(bench_case)            :: cs
        type(bench_data)            :: d
        type(bench_config)          :: cfg
        type(polar_table)           :: ws(2)
        type(half_table)            :: tab
        type(score_plan)            :: plan
        character(len=1), parameter :: T = achar(9)
        real(real64)                :: st0(5), st(5), best(5), wall, wbest, t0, prep, cold
        integer                     :: h, rep, u
        logical                     :: l_new
        write(*,'(a)') '**** bench_polar_table suite=profile ****'
        call mlx_set_default_device(device_of_arg())
        cs  = read_case(arg_str('cases', 'polar_case.txt'), arg_str('case', '2500_4'))
        d   = make_data(cs, POLAR_SEED_JUDGED)
        cfg = arg_config(bench_config(bt=POLAR_CANON_BT, rt=POLAR_CANON_RT))
        t0  = clock_s()
        do h = 1, 2
            call prepare(ws(h), d, h, cfg)
        end do
        call mlx_synchronize()
        prep = clock_s() - t0
        cold = 0._real64
        plan%outer   = cs%nptcls / 2
        plan%team    = arg_int('nthr', 24)
        plan%profile = .true.
        wbest = huge(wbest)
        best  = 0._real64
        do rep = 0, 3
            st0 = ws(1)%stage_seconds() + ws(2)%stage_seconds()
            t0  = clock_s()
            do h = 1, 2
                tab = score_half(ws(h), d, h, plan)
            end do
            wall = clock_s() - t0
            st   = ws(1)%stage_seconds() + ws(2)%stage_seconds() - st0
            if( rep == 0 ) cold = wall
            if( rep > 0 .and. wall < wbest )then
                wbest = wall
                best  = st
            endif
        end do
        inquire(file='bench_polar_table_profile.tsv', exist=l_new)
        l_new = .not. l_new
        open(newunit=u, file='bench_polar_table_profile.tsv', position='append', action='write', status='unknown')
        if( l_new ) write(u,'(a)') 'case'//T//'nrefs'//T//'nptcls'//T//'pftsz'//T//'B'//T//'R'//T//'formulation'//&
            &T//'device'//T//'precision'//T//'wall_s'//T//'terms_s'//T//'products_s'//T//'transform_s'//T//&
            &'distances_draw_s'//T//'concat_s'//T//'copyout_host_s'//T//'prep_s'//T//'cold_first_s'
        write(u,'(a,3(a,i0),2(a,i0),a,a,a,a,a,a,9(a,f10.4))') trim(cs%name), T, cs%nrefs, T, cs%nptcls, T, &
            &cs%pftsz, T, cfg%bt, T, cfg%rt, T, form_name(cfg), T, device_name(mlx_default_device()), T, &
            &precision_mode(), T, wbest, T, best(1), T, best(2), T, best(3), T, best(4), T, best(5), T, &
            &wbest - sum(best), T, prep, T, cold
        close(u)
        write(*,'(a,f9.4,a,5f9.4,a,f9.4)') '    profile wall ', wbest, ' s; stages ', best, '; rest (copy-out, host) ', &
            &wbest - sum(best)
        do h = 1, 2
            call ws(h)%kill()
        end do
    end subroutine bench_profile

    ! ---- overlap -------------------------------------------------------------------------------------------

    ! one configuration in outer batches of outer= particles (default 250): synchronous against two
    ! slots, best of 3 after a warm-up each; the host's seconds in the synchronous run (preparation and
    ! consumption, staging and graph building in submit) give the share the two slots hide. load= labels the
    ! row (a concurrent stream process, started apart)
    subroutine bench_overlap
        type(bench_case)            :: cs
        type(bench_data)            :: d
        type(bench_config)          :: cfg
        type(polar_table)           :: ws(2)
        type(half_table)            :: tab
        type(score_plan)            :: plan
        character(len=1), parameter :: T = achar(9)
        real(real64)                :: wsync, wover, cpu_sync, sub_sync, wall, cpu, sub, t0
        integer                     :: h, rep, u, ns
        logical                     :: l_new
        write(*,'(a)') '**** bench_polar_table suite=overlap ****'
        call mlx_set_default_device(device_of_arg())
        cs  = read_case(arg_str('cases', 'polar_case.txt'), arg_str('case', '2500_4'))
        d   = make_data(cs, POLAR_SEED_JUDGED)
        cfg = arg_config(bench_config(bt=POLAR_CANON_BT, rt=POLAR_CANON_RT))
        do h = 1, 2
            call prepare(ws(h), d, h, cfg)
        end do
        plan%outer = arg_int('outer', 250)
        plan%team  = arg_int('nthr', 24)
        wsync      = huge(wsync)
        wover      = huge(wover)
        cpu_sync   = 0._real64
        sub_sync   = 0._real64
        do ns = 1, 2
            plan%nslots = ns
            do rep = 0, 3
                cpu = 0._real64
                sub = 0._real64
                t0  = clock_s()
                do h = 1, 2
                    tab = score_half(ws(h), d, h, plan)
                    cpu = cpu + tab%cpu_s
                    sub = sub + tab%submit_s
                end do
                wall = clock_s() - t0
                if( rep == 0 ) cycle
                if( ns == 1 .and. wall < wsync )then
                    wsync    = wall
                    cpu_sync = cpu
                    sub_sync = sub
                endif
                if( ns == 2 ) wover = min(wover, wall)
            end do
        end do
        inquire(file='bench_polar_table_overlap.tsv', exist=l_new)
        l_new = .not. l_new
        open(newunit=u, file='bench_polar_table_overlap.tsv', position='append', action='write', status='unknown')
        if( l_new ) write(u,'(a)') 'case'//T//'nrefs'//T//'nptcls'//T//'B'//T//'R'//T//'outer'//T//'formulation'//&
            &T//'device'//T//'precision'//T//'load'//T//'sync_s'//T//'two_slots_s'//T//'host_cpu_sync_s'//T//&
            &'host_submit_sync_s'//T//'hidden_share'
        write(u,'(a,5(a,i0),a,a,a,a,a,a,a,a,4(a,f10.4),a,f8.4)') trim(cs%name), T, cs%nrefs, T, cs%nptcls, T, &
            &cfg%bt, T, cfg%rt, T, plan%outer, T, form_name(cfg), T, device_name(mlx_default_device()), T, &
            &precision_mode(), T, arg_str('load', 'none'), T, wsync, T, wover, T, cpu_sync, T, sub_sync, T, &
            &(wsync - wover) / max(cpu_sync + sub_sync, 1.e-9_real64)
        close(u)
        write(*,'(a,f9.4,a,f9.4,a,f9.4,a,f9.4,a,f7.3)') '    overlap: synchronous ', wsync, ' s, two slots ', &
            &wover, ' s; host in the synchronous run: preparation and consumption ', cpu_sync, ' s, staging and '//&
            &'graph building ', sub_sync, ' s; hidden share ', (wsync - wover) / max(cpu_sync + sub_sync, 1.e-9_real64)
        do h = 1, 2
            call ws(h)%kill()
        end do
    end subroutine bench_overlap

    ! a CPU memory-streaming load for seconds= with nthr= threads (a triad over arrays far beyond the caches);
    ! no MLX call, run as its own process beside an overlap measurement
    subroutine bench_stream
        real(real64), allocatable :: a(:), b(:), c(:)
        real(real64)              :: t0, secs
        integer(int64)            :: n, i
        integer                   :: nthr, sweeps
        write(*,'(a)') '**** bench_polar_table suite=stream ****'
        secs = real(arg_int('seconds', 60), real64)
        nthr = arg_int('nthr', 16)
        n    = 100000000_int64
        allocate(a(n), b(n), c(n))
        b      = 1._real64
        c      = 2._real64
        sweeps = 0
        t0     = clock_s()
        do while( clock_s() - t0 < secs )
            !$omp parallel do num_threads(nthr) default(shared) private(i) schedule(static) proc_bind(spread)
            do i = 1, n
                a(i) = b(i) + 1.5_real64 * c(i)
            end do
            !$omp end parallel do
            sweeps = sweeps + 1
        end do
        write(*,'(a,i0,a,f8.2,a)') '    stream: ', sweeps, ' triads, ', &
            &real(sweeps, real64) * 24._real64 * real(n, real64) / (clock_s() - t0) / 1.e9_real64, ' GB/s'
    end subroutine bench_stream

    ! ---- shift maps ------------------------------------------------------------------------------------------

    ! the shift maps of SIMPLE's grid (grid=, maps= a comma list, default window,screen) on the case (case=), for
    ! each tile of ptiles= particles (a comma list, default 16): both halves' references and maps prepared, a
    ! warm-up, best of 3, then one profiled pass; a row of bench_polar_table_shiftmap.tsv each
    subroutine bench_shiftmap
        type(bench_case)              :: cs
        type(bench_data)              :: d
        character(len=:), allocatable :: names, grid
        integer,          allocatable :: ptiles(:)
        integer                       :: ic, i0
        write(*,'(a)') '**** bench_polar_table suite=shiftmap ****'
        write(*,'(a,f0.1,a)') '    memory budget ', budget_bytes() / 1.e9_real64, ' GB (a share of the GPU''s memory_size)'
        call mlx_set_default_device(device_of_arg())
        cs     = read_case(arg_str('cases', 'polar_case.txt'), arg_str('case', '2500_4'))
        d%cs   = cs
        grid   = arg_str('grid', 'shiftmap_grid.txt')
        names  = arg_str('maps', 'window,screen')
        ptiles = int_list(arg_str('ptiles', '16'))
        i0 = 1
        do ic = 1, len(names) + 1
            if( ic <= len(names) )then
                if( names(ic:ic) /= ',' ) cycle
            endif
            call time_map(d, read_map(grid, names(i0:ic-1)), ptiles)
            i0 = ic + 1
        end do
    end subroutine bench_shiftmap

    ! the integers of a comma list (unreadable items skipped)
    function int_list( s ) result(v)
        character(len=*), intent(in) :: s
        integer, allocatable :: v(:)
        integer              :: ic, i0, x, ios
        allocate(v(0))
        i0 = 1
        do ic = 1, len(s) + 1
            if( ic <= len(s) )then
                if( s(ic:ic) /= ',' ) cycle
            endif
            read(s(i0:ic-1), *, iostat=ios) x
            if( ios == 0 ) v = [v, x]
            i0 = ic + 1
        end do
    end function int_list

    ! a map of the grid file (blocks [map name]); stops when absent or not on the case's geometry, a benchmark's
    ! usage error
    function read_map( path, name ) result(mp)
        character(len=*), intent(in) :: path, name
        type(bench_map)    :: mp
        character(len=512) :: line, key, val
        integer            :: u, ios, ieq
        logical            :: inside
        open(newunit=u, file=path, status='old', action='read', iostat=ios)
        if( ios /= 0 )then
            write(*,'(a)') 'bench_polar_table: cannot open the shift-map grid file '//trim(path)//' (grid=)'
            error stop 2
        endif
        inside = .false.
        do
            read(u, '(a)', iostat=ios) line
            if( ios /= 0 ) exit
            line = adjustl(line)
            if( len_trim(line) == 0 .or. line(1:1) == '#' ) cycle
            if( line(1:1) == '[' )then
                inside = trim(line) == '[map '//trim(name)//']'
                cycle
            endif
            if( .not. inside ) cycle
            ieq = index(line, '=')
            if( ieq == 0 ) cycle
            key = adjustl(line(1:ieq-1))
            val = adjustl(line(ieq+1:))
            select case( trim(key) )
                case( 'pftsz' )
                    read(val, *) mp%pftsz
                case( 'nrots' )
                    read(val, *) mp%nrots
                case( 'kfrom' )
                    read(val, *) mp%kfrom
                case( 'kscreen' )
                    read(val, *) mp%kscreen
                case( 'nrho' )
                    read(val, *) mp%nrho
                case( 'nalpha' )
                    read(val, *) mp%nalpha
                case( 'norder' )
                    read(val, *) mp%norder
                case( 'nrefs' )
                    read(val, *) mp%nrefs
                case( 'nptcls' )
                    read(val, *) mp%nptcls
                case( 'ncand' )
                    read(val, *) mp%ncand
                case( 'rho_max_px' )
                    read(val, *) mp%rho_max
                case( 'prior_w' )
                    read(val, *) mp%prior_w
                case( 'simple_commit' )
                    mp%simple_commit = trim(val)
                case( 'fftw_plans' )
                    mp%fftw_plans = trim(val)
                case( 'maps_per_s_t24' )
                    read(val, *) mp%cpu_maps_per_s
            end select
        end do
        close(u)
        mp%name = name
        if( mp%nrho < 2 .or. mp%nalpha < 1 .or. mp%ncand < 1 .or. mp%kscreen < mp%kfrom .or. &
            &.not. (mp%rho_max > 0._real64) )then
            write(*,'(a)') 'bench_polar_table: no complete map '//trim(name)//' in '//trim(path)
            error stop 2
        endif
    end function read_map

    ! the map's grid on the case's data must be SIMPLE's: the same polar geometry, references and particles
    subroutine check_map_case( cs, mp )
        type(bench_case), intent(in) :: cs
        type(bench_map),  intent(in) :: mp
        if( mp%pftsz /= cs%pftsz .or. mp%nrots /= 2 * cs%pftsz .or. mp%kfrom /= cs%kfrom .or. mp%kscreen > cs%kto &
            &.or. mp%nrefs /= cs%nrefs .or. mp%nptcls /= cs%nptcls .or. mp%ncand > cs%nrefs )then
            write(*,'(a)') 'bench_polar_table: the map '//trim(mp%name)//' is not on the case '//trim(cs%name)
            error stop 2
        endif
    end subroutine check_map_case

    ! a half's map preparation: the box from the grid's step (box / kscreen / 4), radii (i-1) rho_max / (nrho-1),
    ! the half's shell weights over the band kfrom..kscreen, the prior's weight (zero on the window)
    function map_spec( d, mp, half ) result(spec)
        type(bench_data), intent(in) :: d
        type(bench_map),  intent(in) :: mp
        integer,          intent(in) :: half
        type(polar_map_spec) :: spec
        integer              :: i, nkb
        nkb          = mp%kscreen - mp%kfrom + 1
        spec%box     = nint(4._real64 * real(mp%kscreen, real64) * mp%rho_max / real(mp%nrho - 1, real64))
        spec%kfrom   = mp%kfrom
        spec%kstop   = mp%kscreen
        spec%nalpha  = mp%nalpha
        spec%prior_w = mp%prior_w
        spec%rho     = [(real(i - 1, real64) * mp%rho_max / real(mp%nrho - 1, real64), i = 1, mp%nrho)]
        spec%weights = real(d%w(1:nkb, half), real64)
    end function map_spec

    ! a half's particles with their ncand candidates 1 + mod(i - 1 + (c - 1) (nrefs / ncand), nrefs) of particle
    ! i, the weighted square sum over the band and production's temperatures: physical pi wsq_band / (2 pftsz),
    ! tempered POLAR_PROB_BETA times it; neither maps nor evidence
    function map_block( d, mp, half ) result(mb)
        type(bench_data), intent(in) :: d
        type(bench_map),  intent(in) :: mp
        integer,          intent(in) :: half
        type(polar_map_block) :: mb
        integer, allocatable  :: pids(:)
        real(real32)          :: tphys
        integer               :: b, c, i, nb, nkb, stride
        pids   = half_ptcls(d%cs%nptcls, half)
        nb     = size(pids)
        nkb    = mp%kscreen - mp%kfrom + 1
        stride = d%cs%nrefs / mp%ncand
        mb%half       = half
        mb%generation = 1_int64
        mb%ptcl_ids   = pids
        mb%ctf2       = d%ctf2(:, :, pids)
        mb%xctf       = d%xctf(:, :, pids)
        allocate(mb%cands(mp%ncand, nb), mb%ptclpow(nb), mb%temps(nb), mb%temps_phys(nb))
        do b = 1, nb
            i = pids(b)
            do c = 1, mp%ncand
                mb%cands(c, b) = 1 + modulo(i - 1 + (c - 1) * stride, d%cs%nrefs)
            end do
            mb%ptclpow(b)    = sum(real(d%w(1:nkb, half), real64) * d%psq(1:nkb, i))
            tphys            = real(acos(-1._real64) * mb%ptclpow(b) / (2._real64 * real(d%cs%pftsz, real64)), real32)
            mb%temps(b)      = real(POLAR_PROB_BETA * real(tphys, real64), real32)
            mb%temps_phys(b) = tphys
        end do
    end function map_block

    ! both halves' blocks scored, the results kept per half
    subroutine score_maps_pass( ws, mb, res )
        type(polar_table),       intent(inout) :: ws(2)
        type(polar_map_block),   intent(in)    :: mb(2)
        type(polar_map_results), intent(inout) :: res(2)
        integer :: h, st
        do h = 1, 2
            call ws(h)%score_maps(mb(h), res(h), st)
            call assert_int(0, st, 'bench_polar_table: a half''s shift maps are scored: '//ws(h)%message())
        end do
    end subroutine score_maps_pass

    ! one map on the case: the references and the maps prepared per half (timed apart), then each tile of pairs
    ! timed (warm-up, best of 3, MLX peak) and profiled once; every result in range
    subroutine time_map( d, mp, ptiles )
        type(bench_data), intent(inout) :: d
        type(bench_map),  intent(in)    :: mp
        integer,          intent(in)    :: ptiles(:)
        type(polar_table)       :: ws(2)
        type(polar_map_block)   :: mb(2)
        type(polar_map_results) :: res(2)
        type(map_timing)        :: tm
        real(real64)            :: t0, st0(4)
        integer                 :: h, ip, rep, st
        logical                 :: fits
        real(real64)            :: trial_bytes, budget
        call check_map_case(d%cs, mp)
        do h = 1, 2
            call map_execution_args(mb(h))
        end do
        fits = .false.
        budget = budget_bytes()
        do ip = 1, size(ptiles)
            if( ptiles(ip) < 1 ) error stop 'bench_polar_table: particle tiles must be positive'
            trial_bytes = map_estimate_bytes(d%cs, mp, ptiles(ip), mp%norder, mb(1))
            fits = fits .or. trial_bytes <= budget
        end do
        if( .not. fits )then
            do ip = 1, size(ptiles)
                tm%ptcl_tile = ptiles(ip)
                tm%est = map_estimate_bytes(d%cs, mp, ptiles(ip), mp%norder, mb(1))
                tm%status = budget_status()
                call write_map_row(d, mp, tm)
            end do
            return
        endif
        ! The recorded grid order allows rejecting an impossible sweep before staging even the host memos.
        if( .not. allocated(d%xctf) ) d = make_data(d%cs, POLAR_SEED_JUDGED)
        t0 = clock_s()
        do h = 1, 2
            call prepare(ws(h), d, h, bench_config(bt=POLAR_CANON_BT, rt=POLAR_CANON_RT))
        end do
        call mlx_synchronize()
        tm%prep(1) = clock_s() - t0
        t0 = clock_s()
        do h = 1, 2
            call ws(h)%prepare_maps(d%refs(h), map_spec(d, mp, h), st)
            call assert_int(0, st, 'bench_polar_table: a half''s maps are prepared: '//ws(h)%message())
            if( st /= 0 ) return
            mb(h) = map_block(d, mp, h)
            call map_execution_args(mb(h))
            call set_width_mode(mb(h), arg_str('widths', 'all'))
        end do
        call mlx_synchronize()
        tm%prep(2)     = clock_s() - t0
        tm%norder_used = ws(1)%map_order()
        tm%terms = ws(1)%map_term_counts(mb(1))
        tm%resident = real(mlx_active_memory(), real64)
        tm%host_bytes = map_host_bytes(d, mb)
        do ip = 1, size(ptiles)
            tm%ptcl_tile  = ptiles(ip)
            tm%load1      = load_average()
            tm%est        = map_estimate_bytes(d%cs, mp, ptiles(ip), tm%norder_used, mb(1))
            tm%tile_bytes = tm%est - map_estimate_bytes(d%cs, mp, 0, tm%norder_used, mb(1))
            tm%walls      = -1._real64
            tm%pwall      = -1._real64
            tm%peak       = -1._real64
            tm%stages     = 0._real64
            tm%status     = 'timed'
            if( tm%est > budget_bytes() )then
                tm%status = budget_status()
                call write_map_row(d, mp, tm)
                cycle
            endif
            mb(:)%ptcl_tile = ptiles(ip)
            mb(:)%profile = .false.
            t0 = clock_s()
            call score_maps_pass(ws, mb, res)
            call mlx_synchronize()
            tm%cold = clock_s() - t0
            call mlx_reset_peak_memory()
            do rep = 1, 3
                t0 = clock_s()
                call score_maps_pass(ws, mb, res)
                tm%walls(rep) = clock_s() - t0
            end do
            tm%peak       = real(mlx_peak_memory(), real64)
            mb(:)%profile = .true.
            st0 = ws(1)%map_seconds() + ws(2)%map_seconds()
            t0  = clock_s()
            call score_maps_pass(ws, mb, res)
            tm%pwall  = clock_s() - t0
            tm%stages = ws(1)%map_seconds() + ws(2)%map_seconds() - st0
            tm%width_pairs = count(res(1)%sdev >= 0._real32) + count(res(2)%sdev >= 0._real32)
            do h = 1, 2
                call assert_true(results_in_range(res(h), mp), 'bench_polar_table: every '//trim(mp%name)//&
                    &' result is finite and on the grid')
            end do
                call write_map_row(d, mp, tm)
            call mlx_clear_cache()
        end do
        do h = 1, 2
            call ws(h)%kill()
        end do
        call mlx_clear_cache()
    end subroutine time_map

    ! a conservative estimate of a shift-map configuration's device bytes: the dense workspace of both halves at
    ! the canonical plan, the maps' resident data of both halves, and per particle of a tile its order-expanded
    ! weighted spectra (complex), its candidates' spectra, the contraction's output with its transform and their
    ! reordered copy, the directions' transform with its reordered copy, and the cell-sized temporaries of the
    ! reductions per pair; counted twice: the tile in use and the previous tile's buffers MLX's cache keeps
    real(real64) function map_estimate_bytes( cs, mp, ptcl_tile, norder, mb )
        type(bench_case),      intent(in) :: cs
        type(bench_map),       intent(in) :: mp
        integer,               intent(in) :: ptcl_tile, norder
        type(polar_map_block), intent(in) :: mb
        real(real64) :: ct, nt
        real(real64) :: nrots, nkb, nrefs, nord, nrho, nalpha, ncand, cells, resident, per_ptcl
        nrots    = real(mp%nrots, real64)
        nkb      = real(mp%kscreen - mp%kfrom + 1, real64)
        nrefs    = real(cs%nrefs, real64)
        nord     = real(norder + 1, real64)
        nrho     = real(mp%nrho, real64)
        nalpha   = real(mp%nalpha, real64)
        ncand    = real(mp%ncand, real64)
        cells    = nrots * nalpha * nrho
        resident = 2._real64 * estimate_bytes(cs, bench_config(bt=POLAR_CANON_BT, rt=POLAR_CANON_RT), 1) + &
            &2._real64 * (nrots + real(mp%pftsz + 1, real64)) * nkb * nrefs * 8._real64
        per_ptcl = 8._real64 * (nord * nrho * nkb * nrots + 2._real64 * nord * nkb * nrots + nkb * ncand * nrots + &
            &3._real64 * nord * nrho * ncand * nrots + 2._real64 * nalpha * nrho * ncand * nrots) + &
            &4._real64 * 10._real64 * cells * ncand
        if( mb%contraction == POLAR_MAP_FORMS%real_weights )then
            ct = real(min(mp%ncand, mb%cand_tile), real64)
            nt = real(min(norder+1, mb%order_tile), real64)
            per_ptcl = 8._real64 * (2._real64*nt*nkb*nrots + nkb*ncand*nrots + &
                &2._real64*ct*nt*nkb*nrots + 2._real64*ct*nt*nrho*nrots + &
                &3._real64*nord*nrho*ncand*nrots + 2._real64*nalpha*nrho*ncand*nrots) + &
                &4._real64*10._real64*cells*ncand
        endif
        map_estimate_bytes = resident + 2._real64 * real(ptcl_tile, real64) * per_ptcl
    end function map_estimate_bytes

    subroutine map_execution_args( mb )
        type(polar_map_block), intent(inout) :: mb
        mb%contraction = arg_int('contraction', POLAR_MAP_FORMS%weighted_particle)
        mb%cand_tile = arg_int('ctile', 16)
        mb%order_tile = arg_int('otile', 4)
        mb%compact_radii = arg_int('compact', 1) /= 0
        mb%hermitian = arg_int('hermitian', 0) /= 0
        mb%evidence = arg_int('evidence', 0) /= 0
        if( mb%cand_tile < 1 .or. mb%order_tile < 1 ) error stop 'bench_polar_table: ctile and otile must be positive'
        if( mb%contraction /= POLAR_MAP_FORMS%weighted_particle .and. &
            &mb%contraction /= POLAR_MAP_FORMS%real_weights ) error stop 'bench_polar_table: contraction=1|2'
    end subroutine map_execution_args

    ! Synthetic sensitivity modes: predetermined survivors, not a production best-so-far shortlist.
    subroutine set_width_mode( mb, mode )
        type(polar_map_block), intent(inout) :: mb
        character(len=*),      intent(in)    :: mode
        integer :: c
        select case(mode)
            case('all')
                return
            case('none', 'quarter')
                allocate(mb%width_cutoff(size(mb%cands, 1), size(mb%cands, 2)))
                mb%width_cutoff = -huge(1._real32)
                if( mode == 'quarter' )then
                    do c = 4, size(mb%cands, 1), 4
                        mb%width_cutoff(c, :) = huge(1._real32)
                    end do
                endif
            case default
                error stop 'bench_polar_table: widths=all|none|quarter'
        end select
    end subroutine set_width_mode

    real(real64) function map_host_bytes( d, mb ) result(bytes)
        type(bench_data),      intent(in) :: d
        type(polar_map_block), intent(in) :: mb(2)
        integer :: h
        bytes = real(8_int64 * (size(d%ctf2, kind=int64) + size(d%xctf, kind=int64) + &
            &size(d%wsq, kind=int64) + size(d%psq, kind=int64)) + 4_int64 * &
            &(size(d%w, kind=int64) + size(d%temps, kind=int64)), real64)
        do h = 1, 2
            bytes = bytes + real(8_int64 * (size(d%refs(h)%ft_ref, kind=int64) + &
                &size(d%refs(h)%ft_ref2, kind=int64) + size(mb(h)%ctf2, kind=int64) + &
                &size(mb(h)%xctf, kind=int64) + size(mb(h)%ptclpow, kind=int64)), real64)
        end do
    end function map_host_bytes

    logical function results_in_range( res, mp )
        type(polar_map_results), intent(in) :: res
        type(bench_map),         intent(in) :: mp
        results_in_range = all(abs(res%loss) < huge(1._real32)) .and. all(res%sdev >= 0._real32 .or. bits_equal(res%sdev, -1._real32)) .and. &
            &all(res%sdev < huge(1._real32)) .and. all(res%irot >= 1 .and. res%irot <= mp%nrots) .and. &
            &all(res%irho >= 1 .and. res%irho <= mp%nrho) .and. all(res%ialpha >= 1 .and. res%ialpha <= mp%nalpha)
    end function results_in_range

    ! a row of bench_polar_table_shiftmap.tsv: SIMPLE's shift-map columns by name (device for nthr, precision for
    ! fftw_plans, us_map_thread the device's microseconds per map), then the Bessel order used, the MLX peak,
    ! the preparation and the copy-out (the profiled pass's), and the tile, the preparation's parts, the host's
    ! share of the profiled pass per map, its wall, and SIMPLE's full-team rate with the ratio (context)
    subroutine write_map_row( d, mp, tm )
        type(bench_data), intent(in) :: d
        type(bench_map),  intent(in) :: mp
        type(map_timing), intent(in) :: tm
        character(len=*), parameter :: TSV = 'bench_polar_table_shiftmap.tsv'
        character(len=*), parameter :: FMT = '(a,5(a,i0),a,a,7(a,i0),a,f10.4,a,es12.5,a,f6.2,4(a,f10.4),a,f10.3,a,'//&
            &'es12.5,3(a,f10.3),a,a,a,i0,a,es12.5,2(a,f10.4),a,i0,2(a,f10.4),2(a,f10.3),a,f10.4,a,es12.5,a,f8.3,a,'//&
            &'es12.5,a,a)'
        character(len=1), parameter :: T = achar(9)
        real(real64)                :: wall, nmaps, us(4), cpu, rate, ratio
        integer                     :: u
        logical                     :: l_new, matched
        nmaps = real(mp%nptcls, real64) * real(mp%ncand, real64)
        wall  = minval(tm%walls)
        us    = tm%stages * 1.e6_real64 / nmaps
        cpu   = maxval(mp%cpu_maps_per_s)
        rate  = -1._real64
        if( wall > 0._real64 ) rate = nmaps / wall
        ratio = -1._real64
        matched = arg_str('widths', 'all') == 'all'
        matched = arg_int('evidence', 0) == 0 .and. matched
        matched = matched .and. mp%simple_commit /= 'unknown' .and. mp%fftw_plans == 'measure'
        if( cpu > 0._real64 .and. matched ) ratio = rate / cpu
        inquire(file=TSV, exist=l_new)
        l_new = .not. l_new
        open(newunit=u, file=TSV, position='append', action='write', status='unknown')
        if( l_new ) write(u,'(a)') 'map'//T//'nspace'//T//'nstates'//T//'nrefs'//T//'nptcls'//T//'ncand'//T//&
            &'device'//T//'pftsz'//T//'nrots'//T//'kfrom'//T//'kscreen'//T//'nrho'//T//'nalpha'//T//'norder'//T//&
            &'rho_max_px'//T//'prior_w'//T//'load1'//T//'wall_s'//T//'wall_rep1'//T//'wall_rep2'//T//'wall_rep3'//&
            &T//'us_map_thread'//T//'maps_per_s'//T//'us_construct'//T//'us_select'//T//'us_reduce'//T//&
            &'precision'//T//'norder_used'//T//'mlx_peak_bytes'//T//'prep_s'//T//'copyout_s'//T//'ptcl_tile'//T//&
            &'prep_refs_s'//T//'prep_maps_s'//T//'us_copyout'//T//'us_host'//T//'profile_wall_s'//T//&
            &'cpu_maps_per_s'//T//'ratio_cpu'//T//'est_bytes'//T//'status'//T//'mlx_revision'//T//'simple_commit'//T//&
            &'fftw_plans'//T//'width_mode'//T//'evidence'//T//'width_pairs'//T//'active_radius_orders'//T//&
            &'executed_radius_orders'//T//'cold_s'//T//'prepared_device_bytes'//T//'host_bytes'//T//'tile_cache_est_bytes'//T//&
            &'contraction'//T//'hermitian'//T//'candidate_tile'//T//'order_tile'//T//'compact_radii'
        write(u,FMT, advance='no') trim(mp%name), T, &
            &d%cs%nspace, T, d%cs%nstates, T, d%cs%nrefs, T, d%cs%nptcls, T, mp%ncand, T, &
            &device_name(mlx_default_device()), T, mp%pftsz, T, mp%nrots, T, mp%kfrom, T, mp%kscreen, T, mp%nrho, &
            &T, mp%nalpha, T, mp%norder, T, mp%rho_max, T, mp%prior_w, T, tm%load1, T, wall, T, tm%walls(1), T, &
            &tm%walls(2), T, tm%walls(3), T, wall * 1.e6_real64 / nmaps, T, rate, T, us(1), T, us(2), T, &
            &us(3), T, precision_mode(), T, tm%norder_used, T, tm%peak, T, sum(tm%prep), T, tm%stages(4), T, &
            &tm%ptcl_tile, T, tm%prep(1), T, tm%prep(2), T, us(4), T, (tm%pwall - sum(tm%stages)) * 1.e6_real64 / nmaps, &
            &T, tm%pwall, T, cpu, T, ratio, T, tm%est, T, tm%status
        write(u,'(8a,4(a,i0),4(a,es16.8),5(a,i0))') T, arg_str('revision', 'working-tree'), T, trim(mp%simple_commit), &
            &T, trim(mp%fftw_plans), T, arg_str('widths', 'all'), T, arg_int('evidence', 0), T, tm%width_pairs, &
            &T, tm%terms(1), T, tm%terms(2), T, tm%cold, T, tm%resident, T, tm%host_bytes, T, tm%tile_bytes, &
            &T, arg_int('contraction', POLAR_MAP_FORMS%weighted_particle), T, arg_int('hermitian', 0), T, arg_int('ctile', 16), &
            &T, arg_int('otile', 4), T, arg_int('compact', 1)
        close(u)
        write(*,'(a,i0,a,i0,a,f9.4,a,es11.4,a,f7.3,a,es10.3,a,f8.3,a,f8.3,a)') '    shiftmap '//trim(mp%name)//&
            &' ptcl_tile=', tm%ptcl_tile, ' norder_used=', tm%norder_used, ' wall=', wall, ' s, ', rate, &
            &' maps/s (x', ratio, ' SIMPLE full team), peak ', tm%peak, ' B, prep ', sum(tm%prep), &
            &' s, copy-out ', tm%stages(4), ' s: '//tm%status
    end subroutine write_map_row

end module mlxf_bench_polar_table
