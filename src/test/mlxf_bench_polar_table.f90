!@descr: benchmark of the polar table workspace at SIMPLE's sizes: accuracy block, timing sweep, profile, overlap, shift maps
! mlxf_test_exec test=bench_polar_table suite=<accuracy|time|profile|overlap|stream|shiftmap> [key=value ...]. The
! case geometry comes from a key = value file of SIMPLE's measured cases (cases=, case=), the shift maps' grid from
! another (grid=, maps=); the data are synthetic. Every suite hands the rings to the toy calculator and fills
! its tables through the toy driver; a key the suite does not read stops the program. The accuracy mode holds the 64,000-pair block to its oracle and the frozen bounds; the others append
! measure-only rows to ./bench_polar_table*.tsv. suite=time scores one part (nparts=, part=) after a go file (go=).
module mlxf_bench_polar_table
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use, intrinsic :: iso_c_binding,   only: c_int, c_double
!$ use omp_lib,            only: omp_get_max_threads
use mlxf,                  only: mlx_set_default_device, mlx_default_device, mlx_peak_memory, mlx_reset_peak_memory, &
                                 mlx_synchronize, mlx_clear_cache, mlx_device_info_size, MLX_DEVICES, &
                                 mlx_active_memory, mlx_cache_memory
use mlxf_test_defs,        only: POLAR_ROW_FACTOR, POLAR_BLOCK_ERR_CPU, POLAR_BLOCK_ROT_CPU, POLAR_BLOCK_ROT_Q, &
                                 POLAR_SEED_CALIBRATION, POLAR_SEED_JUDGED, POLAR_GRID_B, POLAR_GRID_R, &
                                 POLAR_BUDGET_SHARE, POLAR_CANON_BT, POLAR_CANON_RT, POLAR_BLOCK_BT, POLAR_BLOCK_RT, &
                                 POLAR_PROB_BETA, POLAR_DIST_VALID, POLARFT_TAILS, POLARFT_TAIL_ROW_TOL, &
                                 POLARFT_TAIL_ROT_BLK, polar_table_refs, polar_table_block, polar_table_entries, &
                                 polar_map_results, polar_row_check, parameters, SHIFTMAP_SCREEN, SHIFTMAP_WINDOW
use mlxf_toy_polarft_calc, only: polarft_calc
use mlxf_toy_eul_prob_tab, only: eul_prob_tab
use mlxf_oracle_polar,     only: polar_dft_matrix, polar_keyed_u, polar_compare_rows, polar_draws_off, &
                                 polar_report_draws, polar_memo_rows
use mlxf_test_utils,       only: assert_true, assert_int, test_devices, device_name, set_fixed_seed, bits_equal
use mlxf_test_reduce,      only: nan_maxval
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
! the estimate's count of rotation-row temporaries a tile's tail holds at once: the compiled tail's (conservative)
! and the fused one's (the inverse transform's rows it reads)
integer, parameter :: TAIL_ROWS       = 12
integer, parameter :: TAIL_ROWS_FUSED = 1
! the formulation the dense rows record: packed real products, the inverse real FFT and the compiled tail, or the
! fused one
character(len=*), parameter :: FORMULATION       = 'B+compiled'
character(len=*), parameter :: FORMULATION_FUSED = 'B+metal'
! the digest's starting state (any non-zero value), the go file's polling interval in microseconds and the
! seconds after which a process that was never told to go gives up
integer(int64), parameter :: DIGEST_START = 88172645463325252_int64
integer,        parameter :: GO_POLL_US   = 10000
real(real64),   parameter :: GO_WAIT_MAX  = 3600._real64

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
    integer           :: box     = 0
end type bench_case

! the keys each suite reads, blank separated; test and suite belong to the executable
character(len=*), parameter :: SUITE_KEYS(6) = [character(len=96) :: &
    &'accuracy cases case bt rt device tail', &
    &'time cases case cases_list bt rt device nthr nparts part go passes tail', &
    &'profile cases case bt rt device nthr tail', &
    &'overlap cases case bt rt device nthr outer load', &
    &'stream seconds nthr', &
    &'shiftmap cases case grid maps ptiles device evidence widths revision nthr']

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
! MLX peak and the cache read with it, the estimate checked against the budget, the load, the Bessel order used
! and the status
type :: map_timing
    integer        :: ptcl_tile   = 0
    integer        :: norder_used = 0
    real(real64)   :: walls(3)    = -1._real64
    real(real64)   :: prep(2)     = -1._real64
    real(real64)   :: pwall       = -1._real64
    real(real64)   :: stages(4)   = 0._real64
    real(real64)   :: peak        = -1._real64
    real(real64)   :: cache       = -1._real64
    real(real64)   :: est         = -1._real64
    real           :: load1       = -1.
    integer(int64) :: terms(2) = 0_int64
    integer        :: width_pairs = 0
    real(real64)   :: cold = -1._real64, resident = -1._real64, host_bytes = -1._real64, tile_bytes = -1._real64
    character(len=:), allocatable :: status
end type map_timing

! the synthetic data of a case: the references' global IDs 1..nrefs and their distinct rings per half (rpool,
! reused in turn), every particle's ring (x), CTF, weighted square sum over all shells (wsq) and square sum of
! each shell's half ring (psq); pfromto is the range of global particle IDs this process scores (the whole case
! unless it is one part of several). The memos (refs, ctf2, xctf) are made only for the oracle; the rings are
! not kept when a calculator takes them as they are made.
type :: bench_data
    type(bench_case)             :: cs
    integer                      :: seed = 0
    integer                      :: pfromto(2) = 0
    integer,         allocatable :: ids(:)
    complex(real64), allocatable :: rpool(:,:,:,:)
    complex(real32), allocatable :: x(:,:,:)
    real(real32),    allocatable :: ctf(:,:,:)
    type(polar_table_refs)       :: refs(2)
    real(real32),    allocatable :: w(:,:)
    complex(real32), allocatable :: ctf2(:,:,:)
    complex(real32), allocatable :: xctf(:,:,:)
    real(real64),    allocatable :: wsq(:)
    real(real64),    allocatable :: psq(:,:)
    real(real32),    allocatable :: temps(:)
end type bench_data

! how a range is filled: the particles of one block (outer), the CPU team of the host preparation, one or two
! blocks in flight, rows wanted, stages profiled, the draws reported per temperature
type :: score_plan
    integer :: outer   = 0
    integer :: team    = 1
    integer :: nslots  = 1
    logical :: rows    = .false.
    logical :: profile = .false.
    logical :: report  = .false.
end type score_plan

! a filled range's entries by (reference, particle in the batch's order: the n1 particles of half 1, then half
! 2's, each in the range's order), rows when asked, the place of each column's particle in the range, and the
! fill's host seconds of the variates and of the submissions
type :: half_table
    real(real32), allocatable :: dists(:,:)
    integer,      allocatable :: irots(:,:)
    real(real32), allocatable :: rows(:,:,:)
    integer,      allocatable :: order(:)
    integer                   :: n1       = 0
    real(real64)              :: cpu_s    = 0._real64
    real(real64)              :: submit_s = 0._real64
end type half_table

! a tile plan of a workspace, and the form of its tail
type :: bench_config
    integer :: bt   = POLAR_BLOCK_BT
    integer :: rt   = POLAR_BLOCK_RT
    integer :: tail = POLARFT_TAILS%graph
end type bench_config

! the fused tail against the compiled one on the block (see the calculator's tester): the rows' largest
! difference and the distances' where the drawn rotations agree, relative to the compiled row's largest valid |d|;
! the pairs whose drawn rotation differs, the entries of different validity, the draws that do not hold on either
! form's own rows
type :: form_check
    real(real64) :: err_rows  = 0._real64
    real(real64) :: err_dists = 0._real64
    integer      :: nrot      = 0
    integer      :: valid_off = 0
    integer      :: draws_off = 0
    integer      :: npairs    = 0
end type form_check

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

    subroutine run_bench_polar_table( suite, found )
        character(len=*), intent(in)  :: suite
        logical,          intent(out) :: found
        found = .true.
        call check_keys(suite)
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

    ! whether key=value is on the command line, whatever the value
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

    ! every key=value of the command line is one the suite reads; another stops the program with the key's name,
    ! a benchmark's usage error (an unknown suite is the caller's to report)
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
            write(*,'(a)') 'bench_polar_table: suite='//trim(suite)//' does not read '//trim(arg)//' (its keys:'//&
                &trim(keys)//')'
            error stop 2
        end do
    end subroutine check_keys

    ! the integer value of key=value on the command line, or dflt when the key is absent; a value that is not
    ! an optionally signed integer stops, a benchmark's usage error
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
            write(*,'(a)') 'bench_polar_table: '//key//'='//s//' is not an integer'
            error stop 2
        endif
    end function arg_int

    ! the tile plan of bt= and rt=
    function arg_config( dflt ) result(cfg)
        type(bench_config), intent(in) :: dflt
        type(bench_config) :: cfg
        cfg%bt   = arg_int('bt', dflt%bt)
        cfg%rt   = arg_int('rt', dflt%rt)
        cfg%tail = dflt%tail
        select case( arg_str('tail', 'graph') )
            case( 'graph' )
                cfg%tail = POLARFT_TAILS%graph
            case( 'metal' )
                cfg%tail = POLARFT_TAILS%metal
            case default
                write(*,'(a)') 'bench_polar_table: tail= is graph or metal'
                error stop 2
        end select
    end function arg_config

    ! the formulation of a configuration's dense rows
    function formulation_of( cfg ) result(f)
        type(bench_config), intent(in) :: cfg
        character(len=:), allocatable :: f
        f = FORMULATION
        if( cfg%tail == POLARFT_TAILS%metal ) f = FORMULATION_FUSED
    end function formulation_of

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

    ! the particles of a half that this process scores: those of the half inside the data's range
    function part_ptcls( d, half ) result(pids)
        type(bench_data), intent(in) :: d
        integer,          intent(in) :: half
        integer, allocatable :: pids(:), all_pids(:)
        all_pids = half_ptcls(d%cs%nptcls, half)
        pids     = pack(all_pids, all_pids >= d%pfromto(1) .and. all_pids <= d%pfromto(2))
    end function part_ptcls

    ! the range of particles of part= among nparts= balanced contiguous parts, as SIMPLE splits a population:
    ! every part takes nptcls / nparts, and the first mod(nptcls, nparts) parts one more. A part outside
    ! 1..nparts, or more parts than pairs of particles, is a benchmark's usage error
    function part_range( nptcls ) result(pfromto)
        integer, intent(in) :: nptcls
        integer :: pfromto(2)
        integer :: nparts, part, q, r
        nparts = arg_int('nparts', 1)
        part   = arg_int('part', 1)
        if( nparts < 1 .or. part < 1 .or. part > nparts .or. 2 * nparts > nptcls )then
            write(*,'(a,i0,a)') 'bench_polar_table: nparts= and part= need 1 <= part <= nparts <= ', nptcls / 2, &
                &' (two particles per part at least)'
            error stop 2
        endif
        q       = nptcls / nparts
        r       = nptcls - q * nparts
        pfromto = [(part - 1) * q + min(part - 1, r) + 1, part * q + min(part, r)]
        write(*,'(4(a,i0))') '    part ', part, ' of ', nparts, ': particles ', pfromto(1), ' to ', pfromto(2)
    end function part_range

    ! with go=<file>: the data are ready, so <file>.ready.<part> is written, and the process waits until <file>
    ! exists; simultaneous processes then start scoring together. Without the key it returns at once
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
                write(*,'(a)') 'bench_polar_table: no go file '//go//' appeared'
                error stop 2
            endif
            rc = usleep(int(GO_POLL_US, c_int))
        end do
    end subroutine wait_for_go

    ! the digest after the bit patterns of bits, in order: each pattern enters by exclusive or and the state
    ! then takes one 64-bit shift-register step, so a changed bit or a changed order changes the digest
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

    ! the digest after a table's entries: the distances' bit patterns, then the rotations
    pure subroutine digest_entries( h, dists, irots )
        integer(int64), intent(inout) :: h
        real(real32),   intent(in)    :: dists(:,:)
        integer,        intent(in)    :: irots(:,:)
        call digest_bits(h, transfer(dists, [0_int32]))
        call digest_bits(h, int(reshape(irots, [size(irots)]), int32))
    end subroutine digest_entries

    ! the digest after the shift-map results of the particles c0..c1 (columns): loss, width, the mode's
    ! rotation, radius and direction, and the log evidence when it was asked for
    pure subroutine digest_maps( h, res, c0, c1 )
        integer(int64),          intent(inout) :: h
        type(polar_map_results), intent(in)    :: res
        integer,                 intent(in)    :: c0, c1
        integer :: n
        n = size(res%loss, 1) * (c1 - c0 + 1)
        call digest_bits(h, transfer(res%loss(:, c0:c1), [0_int32]))
        call digest_bits(h, transfer(res%sdev(:, c0:c1), [0_int32]))
        call digest_bits(h, int(reshape(res%irot(:, c0:c1), [n]), int32))
        call digest_bits(h, int(reshape(res%irho(:, c0:c1), [n]), int32))
        call digest_bits(h, int(reshape(res%ialpha(:, c0:c1), [n]), int32))
        if( allocated(res%logz) ) call digest_bits(h, transfer(res%logz(:, c0:c1), [0_int32]))
    end subroutine digest_maps

    ! a digest line: the suite, what was scored, the device, and the digest in hexadecimal
    subroutine report_digest( suite, what, h )
        character(len=*), intent(in) :: suite, what
        integer(int64),   intent(in) :: h
        write(*,'(a,z16.16)') '    digest '//suite//' '//what//' '//device_name(mlx_default_device())//' ', h
    end subroutine report_digest

    ! a tile plan and a scoring schedule as a digest line's label
    function plan_label( cfg, plan ) result(label)
        type(bench_config), intent(in) :: cfg
        type(score_plan),   intent(in) :: plan
        character(len=:), allocatable :: label
        character(len=96)             :: buf
        write(buf, '(4(a,i0))') 'B=', cfg%bt, ' R=', cfg%rt, ' outer=', plan%outer, ' slots=', plan%nslots
        label = trim(buf)
    end function plan_label

    ! the digest of a filled range's entries: half 1's distances and rotations, then half 2's
    function digest_halves( tab ) result(h)
        type(half_table), intent(in) :: tab
        integer(int64) :: h
        integer        :: n
        h = DIGEST_START
        if( .not. allocated(tab%dists) ) return
        n = size(tab%dists, 2)
        if( tab%n1 > 0 ) call digest_entries(h, tab%dists(:, 1:tab%n1), tab%irots(:, 1:tab%n1))
        if( tab%n1 < n ) call digest_entries(h, tab%dists(:, tab%n1+1:n), tab%irots(:, tab%n1+1:n))
    end function digest_halves

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

    ! the synthetic data of a case: per half POOL_RINGS distinct reference rings (larger reference sets reuse
    ! them in turn), particles as CTF times a rotated reference of their half plus noise, shell weights
    ! k / sigma2, inverse temperatures in turn; with l_memos also the memos of the references and particles by a
    ! double-precision DFT (what the oracle is handed). With pftc the rings go
    ! to that calculator as they are made, memoized, and are not kept.
    subroutine make_data( d, cs, seed, l_memos, pftc )
        type(bench_data),             intent(out)   :: d
        type(bench_case),             intent(in)    :: cs
        integer,                      intent(in)    :: seed
        logical,                      intent(in)    :: l_memos
        type(polarft_calc), optional, intent(inout) :: pftc
        complex(real64), allocatable :: e(:,:), zw(:,:), yw(:,:)
        complex(real32), allocatable :: m1(:,:,:,:), m2(:,:,:,:)
        real(real32),    allocatable :: re(:,:), im(:,:), s2(:,:), ctf(:,:), noise(:,:,:)
        complex(real64), allocatable :: x(:,:), z(:)
        real(real64)                 :: amp
        integer                      :: nk, n1, nrots, npool, h, r, k, i, j, src, shift, ithr, nthr, idx, nbad
        logical                      :: l_feed
        l_feed = present(pftc)
        nbad   = 0
        nk     = cs%kto - cs%kfrom + 1
        n1     = cs%pftsz + 1
        nrots  = 2 * cs%pftsz
        npool  = min(POOL_RINGS, cs%nrefs)
        d%cs      = cs
        d%seed    = seed
        d%pfromto = [1, cs%nptcls]
        d%ids     = [(r, r = 1, cs%nrefs)]
        call set_fixed_seed(seed)
        allocate(s2(nk, 2), re(cs%pftsz, nk), im(cs%pftsz, nk), d%rpool(cs%pftsz, nk, npool, 2), d%w(nk, 2))
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
                    d%rpool(:, k, r, h) = cmplx(real(2*re(:, k) - 1, real64) * amp, real(2*im(:, k) - 1, real64) * amp, &
                        &real64)
                end do
            end do
        end do
        if( l_feed ) call begin_calc(pftc, d)
        nthr = 1
        !$ nthr = omp_get_max_threads()
        allocate(zw(cs%pftsz, nthr), yw(n1, nthr))
        if( l_memos )then
            e = polar_dft_matrix(nrots, n1)
            allocate(m1(n1, nk, npool, 2), m2(n1, nk, npool, 2))
            ! the pool's memos: ft_ref the transform of the ring, ft_ref2 the conjugated transform of |ring|^2
            !$omp parallel do default(shared) private(idx, h, r, k, ithr) schedule(dynamic, 16) proc_bind(close)
            do idx = 1, 2 * npool * nk
                ithr = thread_index()
                h = (idx - 1) / (npool * nk) + 1
                r = mod((idx - 1) / nk, npool) + 1
                k = mod(idx - 1, nk) + 1
                zw(:, ithr) = d%rpool(:, k, r, h)
                call ring_bins(e, zw(:, ithr), yw(:, ithr))
                m1(:, k, r, h) = cmplx(yw(:, ithr), kind=real32)
                zw(:, ithr) = cmplx(abs(d%rpool(:, k, r, h))**2, 0._real64, real64)
                call ring_bins(e, zw(:, ithr), yw(:, ithr))
                m2(:, k, r, h) = cmplx(conjg(yw(:, ithr)), kind=real32)
            end do
            !$omp end parallel do
            do h = 1, 2
                d%refs(h)%pftsz = cs%pftsz
                d%refs(h)%nk    = nk
                d%refs(h)%half  = h
                d%refs(h)%ids   = d%ids
                allocate(d%refs(h)%ft_ref(n1, nk, cs%nrefs), d%refs(h)%ft_ref2(n1, nk, cs%nrefs))
                do r = 1, cs%nrefs
                    d%refs(h)%ft_ref(:, :, r)  = m1(:, :, mod(r - 1, npool) + 1, h)
                    d%refs(h)%ft_ref2(:, :, r) = m2(:, :, mod(r - 1, npool) + 1, h)
                end do
            end do
            deallocate(m1, m2)
            allocate(d%ctf2(n1, nk, cs%nptcls), d%xctf(n1, nk, cs%nptcls))
        endif
        ! the particles: CTF in [0.2, 1), the source ring rotated by shift samples, noise at 0.3 of the shell's
        ! amplitude; wsq = sum_k w_k sum |X|^2 over the half ring
        allocate(d%wsq(cs%nptcls), d%psq(nk, cs%nptcls), d%temps(cs%nptcls))
        if( .not. l_feed ) allocate(d%x(cs%pftsz, nk, cs%nptcls), d%ctf(cs%pftsz, nk, cs%nptcls))
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
                z(1:cs%pftsz)       = d%rpool(:, k, src, h)
                z(cs%pftsz+1:nrots) = conjg(d%rpool(:, k, src, h))
                do j = 1, cs%pftsz
                    x(j, k) = real(ctf(j, k), real64) * z(1 + mod(j - 1 - shift + nrots, nrots)) + 0.3_real64 * amp * &
                        &cmplx(real(2*noise(j, k, 1) - 1, real64), real(2*noise(j, k, 2) - 1, real64), real64)
                end do
                x(:, k)     = cmplx(cmplx(x(:, k), kind=real32), kind=real64)
                d%psq(k, i) = sum(abs(x(:, k))**2)
                d%wsq(i)    = d%wsq(i) + real(d%w(k, h), real64) * d%psq(k, i)
            end do
            if( l_feed )then
                nbad = nbad + set_ptcl(pftc, i, cmplx(x, kind=real32), ctf)
            else
                d%x(:, :, i)   = cmplx(x, kind=real32)
                d%ctf(:, :, i) = ctf
            endif
            if( l_memos )then
                do k = 1, nk
                    zw(:, 1) = cmplx(real(ctf(:, k), real64)**2, 0._real64, real64)
                    call ring_bins(e, zw(:, 1), yw(:, 1))
                    d%ctf2(:, k, i) = cmplx(yw(:, 1), kind=real32)
                    zw(:, 1) = x(:, k) * real(ctf(:, k), real64)
                    call ring_bins(e, zw(:, 1), yw(:, 1))
                    d%xctf(:, k, i) = cmplx(yw(:, 1), kind=real32)
                end do
            endif
            d%temps(i) = TEMP_LEVELS(mod(i - 1, size(TEMP_LEVELS)) + 1)
        end do
        if( .not. l_feed ) return
        call pftc%memoize_ptcls
        call assert_int(0, nbad + refused(pftc), 'bench_polar_table: the particles are set and memoized: '//&
            &pftc%message())
        deallocate(d%rpool)
    end subroutine make_data

    ! 1 when the calculator refused its last call, else 0
    integer function refused( pftc )
        type(polarft_calc), intent(in) :: pftc
        refused = merge(1, 0, len(pftc%message()) > 0)
    end function refused

    ! one parity's references set in the order of order (reference i is ring mod(order(i) - 1, pool) + 1 of the
    ! half) and memoized
    subroutine set_refs( pftc, d, half, order )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        integer,            intent(in)    :: half, order(:)
        integer :: i, npool, nbad
        npool = size(d%rpool, 3)
        nbad  = 0
        do i = 1, size(order)
            call pftc%set_ref_pft(i, d%rpool(:, :, mod(order(i) - 1, npool) + 1, half), half == 1)
            nbad = nbad + refused(pftc)
        end do
        call pftc%memoize_refs
        call assert_int(0, nbad + refused(pftc), 'bench_polar_table: the references are set and memoized: '//&
            &pftc%message())
    end subroutine set_refs

    ! a calculator of the data's geometry with its shell weights and both parities' references, memoized
    subroutine begin_calc( pftc, d )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        integer :: h, nbad
        call pftc%new(parameters(pftsz=d%cs%pftsz, box=d%cs%box), d%cs%nrefs, [1, d%cs%nptcls], [d%cs%kfrom, d%cs%kto])
        nbad = refused(pftc)
        call pftc%set_sigma2_weights(real(d%w, real64))
        call assert_int(0, nbad + refused(pftc), 'bench_polar_table: the calculator is made: '//pftc%message())
        do h = 1, 2
            call set_refs(pftc, d, h, d%ids)
        end do
    end subroutine begin_calc

    ! particle i's half, CTF and ring handed to the calculator; the calls that were refused
    integer function set_ptcl( pftc, i, x, ctf ) result(nbad)
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(in)    :: i
        complex(real32),    intent(in)    :: x(:,:)
        real(real32),       intent(in)    :: ctf(:,:)
        call pftc%set_eo(i, half_of(i) == 1)
        nbad = refused(pftc)
        call pftc%set_ptcl_ctfmat(i, ctf)
        nbad = nbad + refused(pftc)
        call pftc%set_ptcl_pft(i, x)
        nbad = nbad + refused(pftc)
    end function set_ptcl

    ! the calculator of data that kept its rings: both parities' references and every particle, set and memoized
    subroutine feed_calc( pftc, d )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        integer :: i, nbad
        call begin_calc(pftc, d)
        nbad = 0
        do i = 1, d%cs%nptcls
            nbad = nbad + set_ptcl(pftc, i, d%x(:, :, i), d%ctf(:, :, i))
        end do
        call pftc%memoize_ptcls
        call assert_int(0, nbad + refused(pftc), 'bench_polar_table: the particles are set and memoized: '//&
            &pftc%message())
    end subroutine feed_calc

    ! the calling thread's number from 1 (OpenMP), 1 without OpenMP
    integer function thread_index()
        !$ use omp_lib, only: omp_get_thread_num
        thread_index = 1
        !$ thread_index = omp_get_thread_num() + 1
    end function thread_index

    ! the oracle's block of particles pids (global IDs) of one half, prepared by a CPU team of team threads:
    ! memos, weights, wsq, temperatures and the pairs' variates keyed by global IDs
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

    ! a driver of the particles pids on the data's calculator under plan: its draws keyed by the data's seed and
    ! the references' global IDs, the particles' temperatures the data's
    subroutine make_driver( tab, pftc, d, pids, plan )
        type(eul_prob_tab), intent(inout) :: tab
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        integer,            intent(in)    :: pids(:)
        type(score_plan),   intent(in)    :: plan
        type(parameters) :: params
        integer          :: nbad
        params%pftsz = d%cs%pftsz
        params%box   = d%cs%box
        params%nthr  = plan%team
        call tab%new_pipeline(params, pftc, pids)
        nbad = merge(1, 0, len(tab%message()) > 0)
        if( nbad == 0 )then
            call tab%set_draw_keys(d%seed, d%ids)
            nbad = nbad + merge(1, 0, len(tab%message()) > 0)
            call tab%set_temps(d%temps(pids))
            nbad = nbad + merge(1, 0, len(tab%message()) > 0)
            call tab%set_fill_options(plan%outer, plan%nslots, plan%rows, plan%profile)
            nbad = nbad + merge(1, 0, len(tab%message()) > 0)
        endif
        call assert_int(0, nbad, 'bench_polar_table: the driver is made: '//tab%message())
    end subroutine make_driver

    ! the driver's whole range filled and its entries handed over: half 1's particles, then half 2's
    subroutine fill_table( tab, pids, t )
        type(eul_prob_tab), intent(inout) :: tab
        integer,            intent(in)    :: pids(:)
        type(half_table),   intent(out)   :: t
        real(real64) :: s0(4), s1(4)
        integer      :: j
        s0 = tab%fill_seconds()
        call tab%fill_tab_range(1, size(pids))
        call assert_int(0, len(tab%message()), 'bench_polar_table: the range is filled: '//tab%message())
        if( len(tab%message()) > 0 ) return
        s1 = tab%fill_seconds()
        call tab%batch_entries(t%dists, t%irots, t%order)
        call tab%batch_full_rows(t%rows)
        t%n1       = 0
        do j = 1, size(t%order)
            if( half_of(pids(t%order(j))) == 1 ) t%n1 = t%n1 + 1
        end do
        t%cpu_s    = s1(1) - s0(1)
        t%submit_s = s1(2) - s0(2)
    end subroutine fill_table

    ! the entries and rows of the columns c0..c1 of a filled range
    function entries_of( t, c0, c1 ) result(ent)
        type(half_table), intent(in) :: t
        integer,          intent(in) :: c0, c1
        type(polar_table_entries) :: ent
        ent%dists = t%dists(:, c0:c1)
        ent%irots = t%irots(:, c0:c1)
        if( allocated(t%rows) ) ent%rows = t%rows(:, :, c0:c1)
    end function entries_of

    ! the calculator's reference bins under cfg (tile plan and tail), on the current device
    subroutine prepare( pftc, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_config), intent(in)    :: cfg
        call pftc%set_tail_form(cfg%tail)
        call pftc%set_tile_plan(cfg%bt, cfg%rt)
        call pftc%memoize_ref_bins
        call assert_int(0, refused(pftc), 'bench_polar_table: the references are prepared: '//pftc%message())
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
    ! the frozen bounds, the sensitivities and schedule identity; one calculator per seed, its reference bins
    ! made again on each device
    subroutine bench_accuracy
        type(bench_case)          :: cs
        type(bench_data)          :: d1, d2
        type(polarft_calc)        :: pftc1, pftc2
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
        if( cfg%tail == POLARFT_TAILS%metal .and. any(devs /= MLX_DEVICES%gpu) )then
            write(*,'(a)') 'bench_polar_table: suite=accuracy tail=metal runs on the GPU only (device=gpu)'
            error stop 2
        endif
        original = mlx_default_device()
        call make_data(d2, cs, POLAR_SEED_JUDGED, .true.)
        or2 = oracle_halves(d2)
        call feed_calc(pftc2, d2)
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))//', formulation '//formulation_of(cfg)
            if( devs(i) == MLX_DEVICES%cpu )then
                if( .not. allocated(or1) )then
                    call make_data(d1, cs, POLAR_SEED_CALIBRATION, .true.)
                    or1 = oracle_halves(d1)
                    call feed_calc(pftc1, d1)
                endif
                call report_block_calibration(pftc1, d1, or1, cfg)
                call pftc1%kill_ref_bins
            endif
            call judge_block(pftc2, d2, or2, cfg)
            call block_sensitivity(pftc2, d2, or2, cfg)
            call block_identity(pftc2, d2, cfg)
            call pftc2%kill_ref_bins
            if( cfg%tail == POLARFT_TAILS%metal )then
                if( .not. allocated(or1) )then
                    call make_data(d1, cs, POLAR_SEED_CALIBRATION, .true.)
                    or1 = oracle_halves(d1)
                    call feed_calc(pftc1, d1)
                endif
                call block_tail_forms(pftc1, d1, pftc2, d2, cfg)
            endif
        end do
        call mlx_set_default_device(original)
        call pftc1%kill
        call pftc2%kill
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

    ! every particle filled under cfg with rows, each half compared with the oracle; the totals of both halves
    function score_and_compare( pftc, d, dor, cfg, plan ) result(chk)
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        type(score_plan),   intent(in)    :: plan
        type(polar_row_check)     :: chk
        type(polar_row_check)     :: c
        type(eul_prob_tab)        :: tab
        type(half_table)          :: t
        type(polar_table_entries) :: ent
        type(polar_table_block)   :: blk
        character(len=16)         :: seed
        integer                   :: h, i, c0, c1
        call prepare(pftc, cfg)
        call make_driver(tab, pftc, d, [(i, i = 1, d%cs%nptcls)], plan)
        call fill_table(tab, [(i, i = 1, d%cs%nptcls)], t)
        if( .not. allocated(t%rows) ) return
        do h = 1, 2
            c0  = merge(1, t%n1 + 1, h == 1)
            c1  = merge(t%n1, size(t%dists, 2), h == 1)
            ent = entries_of(t, c0, c1)
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
            if( plan%report ) call polar_report_draws('block', d%seed, dor(:, :, :, h), ent, blk)
        end do
        write(seed, '(i0)') d%seed
        call report_digest('accuracy', 'block seed='//trim(seed)//' '//plan_label(cfg, plan), digest_halves(t))
    end function score_and_compare

    ! the fused tail against the compiled one on the GPU, on the block's both halves under cfg's tile plan, both
    ! reading the same rows of the inverse transform: block seed 1 is the calibration, printed; block seed 2 is
    ! held to the frozen tolerances, and each form's draw to its own rows
    subroutine block_tail_forms( pftc1, d1, pftc2, d2, cfg )
        type(polarft_calc), intent(inout) :: pftc1, pftc2
        type(bench_data),   intent(in)    :: d1, d2
        type(bench_config), intent(in)    :: cfg
        type(form_check) :: chk
        chk = compare_forms(pftc1, d1, cfg)
        call pftc1%kill_ref_bins
        write(*,'(a,es23.16,a,es23.16,a,i0,a,i0,a,i0,a,i0)') '    calibration (block seed 1, gpu, fused against '//&
            &'compiled): rows ', chk%err_rows, ', distances ', chk%err_dists, ', drawn rotations differing ', &
            &chk%nrot, ' of ', chk%npairs, '; validity off ', chk%valid_off, ', draws off ', chk%draws_off
        chk = compare_forms(pftc2, d2, cfg)
        call pftc2%kill_ref_bins
        write(*,'(a,es10.3,a,es10.3,a,i0,a,i0)') '    block seed 2, fused against compiled: rows ', chk%err_rows, &
            &', distances ', chk%err_dists, ', drawn rotations differing ', chk%nrot, ' of ', chk%npairs
        call assert_int(BLOCK_NPTCLS * BLOCK_NREFS, chk%npairs, 'both forms score the block''s 64,000 pairs')
        call assert_true(chk%err_rows <= POLARFT_TAIL_ROW_TOL, 'gpu block: the fused rows are the compiled ones '//&
            &'within POLARFT_TAIL_ROW_TOL')
        call assert_true(chk%nrot <= POLARFT_TAIL_ROT_BLK, 'gpu block: the drawn rotations differ in at most '//&
            &'POLARFT_TAIL_ROT_BLK pairs')
        call assert_true(chk%err_dists <= POLARFT_TAIL_ROW_TOL, 'gpu block: where the rotations agree the distances '//&
            &'agree within POLARFT_TAIL_ROW_TOL')
        call assert_int(0, chk%valid_off, 'gpu block: every entry has the same validity in both forms')
        call assert_int(0, chk%draws_off, 'gpu block: each form''s draw holds on its own rows')
    end subroutine block_tail_forms

    ! every particle of d filled with rows by both forms under cfg's tile plan, compared half by half
    function compare_forms( pftc, d, cfg ) result(chk)
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        type(bench_config), intent(in)    :: cfg
        type(form_check)          :: chk
        type(bench_config)        :: g
        type(eul_prob_tab)        :: tab
        type(half_table)          :: tg, tm
        type(polar_table_entries) :: eg, em
        type(polar_table_block)   :: blk
        type(polar_row_check)     :: c
        real(real64)              :: dmax
        integer                   :: h, i, c0, c1, ir, b
        g      = cfg
        g%tail = POLARFT_TAILS%graph
        call prepare(pftc, g)
        call make_driver(tab, pftc, d, [(i, i = 1, d%cs%nptcls)], canonical_plan(.true.))
        call fill_table(tab, [(i, i = 1, d%cs%nptcls)], tg)
        call prepare(pftc, cfg)
        call make_driver(tab, pftc, d, [(i, i = 1, d%cs%nptcls)], canonical_plan(.true.))
        call fill_table(tab, [(i, i = 1, d%cs%nptcls)], tm)
        if( .not. allocated(tg%rows) .or. .not. allocated(tm%rows) )then
            chk%valid_off = 1
            return
        endif
        do h = 1, 2
            c0  = merge(1, tg%n1 + 1, h == 1)
            c1  = merge(tg%n1, size(tg%dists, 2), h == 1)
            eg  = entries_of(tg, c0, c1)
            em  = entries_of(tm, c0, c1)
            blk = make_block(d, h, half_ptcls(d%cs%nptcls, h), 1_int64, 1)
            c   = polar_compare_rows(real(eg%rows, real64), em)
            chk%err_rows  = max(chk%err_rows, c%err)
            chk%valid_off = chk%valid_off + c%valid_off
            chk%npairs    = chk%npairs + c%npairs
            chk%nrot      = chk%nrot + count(eg%irots /= em%irots)
            chk%draws_off = chk%draws_off + polar_draws_off(eg, blk%temps, blk%u) + polar_draws_off(em, blk%temps, blk%u)
            do b = 1, size(eg%irots, 2)
                do ir = 1, size(eg%irots, 1)
                    if( eg%irots(ir, b) /= em%irots(ir, b) ) cycle
                    if( bits_equal(eg%dists(ir, b), em%dists(ir, b)) ) cycle
                    dmax = nan_maxval(pack(abs(real(eg%rows(:, ir, b), real64)), eg%rows(:, ir, b) < POLAR_DIST_VALID))
                    if( dmax > 0._real64 )then
                        chk%err_dists = max(chk%err_dists, abs(real(em%dists(ir, b), real64) - &
                            &real(eg%dists(ir, b), real64)) / dmax)
                    else
                        chk%valid_off = chk%valid_off + 1
                    endif
                end do
            end do
        end do
    end function compare_forms

    function canonical_plan( rows ) result(plan)
        logical, intent(in) :: rows
        type(score_plan) :: plan
        plan%outer  = BLOCK_NPTCLS / 2
        plan%team   = 1
        plan%nslots = 1
        plan%rows   = rows
    end function canonical_plan

    ! the block calibration on the CPU device, block seed 1: e_cpu and n_cpu, reported
    subroutine report_block_calibration( pftc, d, dor, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        type(polar_row_check) :: chk
        chk = score_and_compare(pftc, d, dor, cfg, canonical_plan(.true.))
        write(*,'(a,es23.16,a,i0,a,i0,a,i0,a,i0,a,i0)') '    calibration (block seed 1, cpu, '//formulation_of(cfg)// &
            &'): e_cpu = ', chk%err, ', n_cpu = ', chk%argmin_off, ' of ', chk%npairs, ' pairs; validity off ', &
            &chk%valid_off, ', draws off ', chk%draws_bad, ', mixed rows ', chk%mixed
    end subroutine report_block_calibration

    ! block seed 2 on the current device against the oracle: validity, the draw on the device's rows, and the
    ! block's frozen bounds; the draws reported per temperature
    subroutine judge_block( pftc, d, dor, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        character(len=:), allocatable :: dev
        type(polar_row_check)         :: chk
        type(score_plan)              :: plan
        dev  = device_name(mlx_default_device())
        plan = canonical_plan(.true.)
        plan%report = .true.
        chk  = score_and_compare(pftc, d, dor, cfg, plan)
        write(*,'(a,es10.3,a,i0,a,i0,a)') '    block seed 2 ('//dev//', '//formulation_of(cfg)//'): row error ', chk%err, &
            &', minimising rotation differs in ', chk%argmin_off, ' of ', chk%npairs, ' pairs'
        call assert_int(BLOCK_NPTCLS * BLOCK_NREFS, chk%npairs, 'the accuracy block scores 64,000 pairs')
        call assert_int(0, chk%valid_off, dev//' block: every entry is valid or invalid as in the oracle')
        call assert_int(0, chk%draws_bad, dev//' block: the draw lies in the device row''s cumulative interval '//&
            &'within 1e-4 W, and the entry''s distance is the row''s')
        call assert_block_bounds(dev//' block '//formulation_of(cfg), chk)
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
    subroutine block_sensitivity( pftc, d, dor, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        character(len=:), allocatable :: dev
        type(bench_config)            :: v
        type(polar_row_check)         :: chk
        dev  = device_name(mlx_default_device())
        v    = cfg
        v%bt = 32
        v%rt = 1000
        chk  = score_and_compare(pftc, d, dor, v, canonical_plan(.true.))
        call assert_int(0, chk%valid_off + chk%draws_bad, dev//' tile shape 32 x 1000: validity and draws hold')
        call assert_block_bounds(dev//' tile shape 32 x 1000', chk)
        v    = cfg
        v%bt = 12
        v%rt = 300
        chk  = score_and_compare(pftc, d, dor, v, canonical_plan(.true.))
        call assert_int(0, chk%valid_off + chk%draws_bad, dev//' partial edges 12 x 300: validity and draws hold')
        call assert_block_bounds(dev//' partial edges 12 x 300', chk)
        call position_and_list(pftc, d, dor, cfg)
    end subroutine block_sensitivity

    ! the particles in reversed order (every tile position changes) and the references set in a shuffled
    ! order (global IDs kept): one block per half, judged against the bounds, entries compared by global pair with
    ! the canonical run
    subroutine position_and_list( pftc, d, dor, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        real(real64),       intent(in)    :: dor(:,:,:,:)
        type(bench_config), intent(in)    :: cfg
        character(len=:), allocatable :: dev
        type(eul_prob_tab)            :: tab
        type(score_plan)              :: plan
        type(half_table)              :: t
        type(polar_table_block)       :: blk
        type(polar_table_entries)     :: e0, e1
        type(polar_row_check)         :: chk
        real(real64), allocatable     :: dsub(:,:,:)
        integer, allocatable          :: pids(:), perm(:)
        integer(int64)                :: dig(3)
        integer                       :: h, n, i, r, ndiff_pos, ndiff_list
        dev        = device_name(mlx_default_device())
        ndiff_pos  = 0
        ndiff_list = 0
        dig        = DIGEST_START
        do h = 1, 2
            pids = half_ptcls(d%cs%nptcls, h)
            n    = size(pids)
            plan = canonical_plan(.true.)
            plan%outer = n
            call prepare(pftc, cfg)
            call make_driver(tab, pftc, d, pids, plan)
            call fill_table(tab, pids, t)
            if( allocated(t%rows) )then
                e0 = entries_of(t, 1, n)
                call digest_entries(dig(1), e0%dists, e0%irots)
            endif
            call make_driver(tab, pftc, d, pids(n:1:-1), plan)
            call fill_table(tab, pids(n:1:-1), t)
            call assert_true(allocated(t%rows), dev//' reversed particles are scored')
            if( .not. allocated(t%rows) .or. .not. allocated(e0%dists) ) return
            e1  = entries_of(t, 1, n)
            blk = make_block(d, h, pids(n:1:-1), 1_int64, 1)
            call digest_entries(dig(2), e1%dists, e1%irots)
            dsub = dor(:, :, n:1:-1, h)
            chk  = polar_compare_rows(dsub, e1)
            call assert_int(0, chk%valid_off + polar_draws_off(e1, blk%temps, blk%u), dev//' reversed particles: '//&
                &'validity and draws hold')
            call assert_block_bounds(dev//' reversed particles', chk)
            do i = 1, n
                ndiff_pos = ndiff_pos + count(.not. bits_equal(e1%dists(:, n + 1 - i), e0%dists(:, i)))
            end do
            ! the references in a shuffled order, IDs kept: entries come back in that order
            perm = [(mod(37 * i, d%cs%nrefs) + 1, i = 0, d%cs%nrefs - 1)]
            call set_refs(pftc, d, h, perm)
            call prepare(pftc, cfg)
            call make_driver(tab, pftc, d, pids, plan)
            call tab%set_draw_keys(d%seed, d%ids(perm))
            call fill_table(tab, pids, t)
            call assert_true(allocated(t%rows), dev//' shuffled references are scored')
            if( .not. allocated(t%rows) ) return
            e1          = entries_of(t, 1, n)
            blk         = make_block(d, h, pids, 1_int64, 1)
            blk%ref_ids = d%ids(perm)
            do i = 1, n
                do r = 1, size(perm)
                    blk%u(r, i) = real(polar_keyed_u(d%seed, pids(i), blk%ref_ids(r)), real32)
                end do
            end do
            call digest_entries(dig(3), e1%dists, e1%irots)
            dsub = dor(:, perm, :, h)
            chk  = polar_compare_rows(dsub, e1)
            call assert_int(0, chk%valid_off + polar_draws_off(e1, blk%temps, blk%u), dev//' shuffled references: '//&
                &'validity and draws hold')
            call assert_block_bounds(dev//' shuffled references', chk)
            ndiff_list = ndiff_list + count(.not. bits_equal(e1%dists, e0%dists(perm, :)))
            ! the half's references in their own order again
            call set_refs(pftc, d, h, d%ids)
        end do
        write(*,'(a,i0,a,i0,a)') '    '//dev//' entries differing from the canonical run by global pair: reversed '//&
            &'particles ', ndiff_pos, ', shuffled references ', ndiff_list, ' (reported)'
        call report_digest('accuracy', 'one call, particles in order', dig(1))
        call report_digest('accuracy', 'one call, particles reversed', dig(2))
        call report_digest('accuracy', 'one call, references shuffled', dig(3))
    end subroutine position_and_list

    ! schedule identity on the block, exact: three repeats, blocks of 32 and 16, CPU teams 1 and 24, and
    ! one block against two in flight give identical entries by global pair
    subroutine block_identity( pftc, d, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        type(bench_config), intent(in)    :: cfg
        character(len=:), allocatable :: dev
        type(eul_prob_tab)            :: tab
        type(half_table)              :: t0, t
        type(score_plan)              :: plan
        integer, allocatable          :: pids(:)
        integer                       :: rep, i
        logical                       :: same_rep, same_outer, same_team, same_slots
        dev      = device_name(mlx_default_device())
        pids     = [(i, i = 1, d%cs%nptcls)]
        same_rep = .true.
        call prepare(pftc, cfg)
        plan = canonical_plan(.false.)
        call make_driver(tab, pftc, d, pids, plan)
        call fill_table(tab, pids, t0)
        do rep = 1, 3
            call fill_table(tab, pids, t)
            same_rep = same_rep .and. same_table(t, t0)
        end do
        plan%outer = BLOCK_NPTCLS / 4
        call make_driver(tab, pftc, d, pids, plan)
        call fill_table(tab, pids, t)
        same_outer = same_table(t, t0)
        plan%team  = 24
        call make_driver(tab, pftc, d, pids, plan)
        call fill_table(tab, pids, t)
        same_team   = same_table(t, t0)
        plan%team   = 1
        plan%outer  = BLOCK_NPTCLS / 4
        plan%nslots = 2
        call make_driver(tab, pftc, d, pids, plan)
        call fill_table(tab, pids, t)
        same_slots = same_table(t, t0)
        call assert_true(same_rep, dev//' block identity: three repeats give identical entries')
        call assert_true(same_outer, dev//' block identity: outer batches of 32 and 16 give identical entries')
        call assert_true(same_team, dev//' block identity: CPU teams of 1 and 24 give identical entries')
        call assert_true(same_slots, dev//' block identity: two slots give the synchronous entries')
        call report_digest('accuracy', 'identity '//plan_label(cfg, canonical_plan(.false.)), digest_halves(t0))
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
        tile   = real(cfg%bt, real64) * real(cfg%rt, real64) * (n1 * 16._real64 + nrots * 4._real64 * &
            &merge(TAIL_ROWS_FUSED, TAIL_ROWS, cfg%tail == POLARFT_TAILS%metal))
        estimate_bytes = refs + real(nslots, real64) * (inputs + tile)
    end function estimate_bytes

    ! the sweep of decision 13's grid over one case (case=) or the cases named by cases_list=: configurations
    ! above the particles per half, above the references or beyond the budget are pruned before any allocation;
    ! each kept one is prepared, warmed up and timed over passes= passes (default 3; both halves, all particles,
    ! from the memos through the entries in Fortran arrays): the best pass and the median
    subroutine bench_time
        type(bench_case)              :: cs
        type(bench_data)              :: d
        type(polarft_calc)            :: pftc
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
            call make_data(d, cs, POLAR_SEED_JUDGED, .false., pftc=pftc)
            d%pfromto = part_range(cs%nptcls)
            call wait_for_go
            do ib = 1, size(bs)
                do ir = 1, size(rs)
                    cfg    = arg_config(bench_config())
                    cfg%bt = bs(ib)
                    cfg%rt = rs(ir)
                    call time_config(pftc, d, cfg)
                end do
            end do
            call pftc%kill
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
    subroutine time_config( pftc, d, cfg )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(in)    :: d
        type(bench_config), intent(in)    :: cfg
        type(eul_prob_tab)            :: tab
        type(half_table)              :: t
        type(score_plan)              :: plan
        character(len=:), allocatable :: status
        integer,          allocatable :: pids(:)
        real(real64),     allocatable :: walls(:)
        real(real64)                  :: t0, prep, est, cpu_s
        real(real64)                  :: peak, cache
        real                          :: load1
        integer                       :: i, rep, nh, npasses
        ! one call per half: the whole case's half, or the larger half of a part
        nh     = d%cs%nptcls / 2
        if( d%pfromto(2) - d%pfromto(1) + 1 < d%cs%nptcls ) nh = max(size(part_ptcls(d, 1)), size(part_ptcls(d, 2)))
        est    = estimate_bytes(d%cs, cfg, 1)
        status = 'timed'
        if( cfg%bt > nh ) status = 'pruned: B above the particles per half'
        if( cfg%rt > d%cs%nrefs ) status = 'pruned: R_t above the references'
        if( status == 'timed' )then
            if( est > budget_bytes() ) status = budget_status()
        endif
        npasses = arg_int('passes', 3)
        if( npasses < 1 )then
            write(*,'(a)') 'bench_polar_table: passes= needs at least one pass'
            error stop 2
        endif
        allocate(walls(npasses))
        walls = -1._real64
        prep  = -1._real64
        peak  = -1._real64
        cache = -1._real64
        cpu_s = 0._real64
        load1 = load_average()
        if( status == 'timed' )then
            plan%outer = nh
            plan%team  = arg_int('nthr', 24)
            pids = [(i, i = d%pfromto(1), d%pfromto(2))]
            t0   = clock_s()
            call prepare(pftc, cfg)
            call make_driver(tab, pftc, d, pids, plan)
            call mlx_synchronize()
            prep = clock_s() - t0
            call fill_table(tab, pids, t)
            call mlx_synchronize()
            call mlx_reset_peak_memory()
            do rep = 1, npasses
                t0 = clock_s()
                call fill_table(tab, pids, t)
                cpu_s      = cpu_s + t%cpu_s
                walls(rep) = clock_s() - t0
            end do
            peak  = real(mlx_peak_memory(), real64)
            cache = real(mlx_cache_memory(), real64)
            call report_digest('time', trim(d%cs%name)//' '//plan_label(cfg, plan), digest_halves(t))
            call tab%kill
            call pftc%kill_ref_bins
            call mlx_clear_cache()
        endif
        call write_time_row(d, cfg, [walls(1:min(3, npasses)), [(-1._real64, i = npasses + 1, 3)], prep, est, peak, &
            &cache, cpu_s / real(npasses, real64), minval(walls), median_of(walls)], load1, status)
    end subroutine time_config

    ! the median of x (the mean of the two middle values when their number is even)
    real(real64) function median_of( x )
        real(real64), intent(in) :: x(:)
        real(real64) :: v(size(x)), s
        integer      :: i, j, n
        n = size(x)
        v = x
        do i = 2, n
            s = v(i)
            j = i - 1
            do while( j >= 1 )
                if( v(j) <= s ) exit
                v(j + 1) = v(j)
                j        = j - 1
            end do
            v(j + 1) = s
        end do
        median_of = 0.5_real64 * (v((n + 1) / 2) + v(n / 2 + 1))
    end function median_of

    ! a row of bench_polar_table.tsv: SIMPLE's case columns by name, then the tile, formulation, device,
    ! precision, preparation and memory, then the passes and their median; vals = wall_rep1..3 (the first three
    ! passes), prep_s, est_bytes, mlx_peak_bytes, mlx_cache_bytes, cpu_s, the best pass, the median pass
    subroutine write_time_row( d, cfg, vals, load1, status )
        type(bench_data),   intent(in) :: d
        type(bench_config), intent(in) :: cfg
        real(real64),       intent(in) :: vals(10)
        real,               intent(in) :: load1
        character(len=*),   intent(in) :: status
        character(len=*), parameter :: TSV = 'bench_polar_table.tsv'
        character(len=1), parameter :: T = achar(9)
        real(real64)                :: wall, wmed, pairs, padded
        integer                     :: u, nrots, rpad, bpad, np
        logical                     :: l_new
        nrots  = 2 * d%cs%pftsz
        wall   = -1._real64
        wmed   = -1._real64
        if( vals(9) > 0._real64 ) wall = vals(9)
        if( vals(10) > 0._real64 ) wmed = vals(10)
        np     = d%pfromto(2) - d%pfromto(1) + 1
        pairs  = real(d%cs%nrefs, real64) * real(np, real64)
        rpad   = ((d%cs%nrefs + cfg%rt - 1) / cfg%rt) * cfg%rt
        bpad   = ((np / 2 + cfg%bt - 1) / cfg%bt) * cfg%bt
        padded = 2._real64 * real(rpad, real64) * real(bpad, real64)
        inquire(file=TSV, exist=l_new)
        l_new = .not. l_new
        open(newunit=u, file=TSV, position='append', action='write', status='unknown')
        if( l_new ) write(u,'(a)') 'case'//T//'nspace'//T//'nstates'//T//'nrefs'//T//'nptcls'//T//'pftsz'//T//&
            &'nrots'//T//'kfrom'//T//'kto'//T//'B'//T//'R'//T//'formulation'//T//'device'//T//'precision'//T//&
            &'load1'//T//'wall_s'//T//'wall_rep1'//T//'wall_rep2'//T//'wall_rep3'//T//'pairs_per_s'//T//&
            &'useful_pairs'//T//'padded_pairs'//T//'prep_s'//T//'host_cpu_s'//T//'est_bytes'//T//'mlx_peak_bytes'//&
            &T//'mlx_cache_bytes'//T//'status'//T//'passes'//T//'wall_median_s'
        write(u,'(a,10(a,i0),a,a,a,a,a,a,a,f6.2,4(a,f10.4),a,es12.5,2(a,es12.5),2(a,f10.4),3(a,es12.5),a,a,a,i0,a,f10.4)') &
            &trim(d%cs%name), T, d%cs%nspace, T, d%cs%nstates, T, d%cs%nrefs, T, d%cs%nptcls, T, d%cs%pftsz, T, &
            &nrots, T, d%cs%kfrom, T, d%cs%kto, T, cfg%bt, T, cfg%rt, T, formulation_of(cfg), T, &
            &device_name(mlx_default_device()), T, precision_mode(), T, load1, T, wall, T, vals(1), T, vals(2), T, &
            &vals(3), T, merge(pairs / wall, -1._real64, wall > 0._real64), T, pairs, T, padded, T, vals(4), T, &
            &vals(8), T, vals(5), T, vals(6), T, vals(7), T, status, T, arg_int('passes', 3), T, wmed
        close(u)
        write(*,'(a,i0,a,i0,a,f9.4,a,es11.4,2(a,es10.3),a)') '    '//trim(d%cs%name)//' '//formulation_of(cfg)//' B=', &
            &cfg%bt, ' R=', cfg%rt, ' wall=', wall, ' s, ', merge(pairs / wall, -1._real64, wall > 0._real64), &
            &' pairs/s, peak ', vals(6), ' B, cache ', vals(7), ' B: '//status
        write(*,'(a,i0,a,f9.4,a,es11.4,a)') '    passes ', arg_int('passes', 3), ', median wall=', wmed, ' s, ', &
            &merge(pairs / wmed, -1._real64, wmed > 0._real64), ' pairs/s'
    end subroutine write_time_row

    ! ---- profile ---------------------------------------------------------------------------------------------

    ! one configuration (case=, bt=, rt=) scored with an evaluation barrier after every stage:
    ! the stages' seconds summed over both halves, and the copy-out apart; best of 3 after a warm-up
    subroutine bench_profile
        type(bench_case)            :: cs
        type(bench_data)            :: d
        type(bench_config)          :: cfg
        type(polarft_calc)          :: pftc
        type(eul_prob_tab)          :: tab
        type(half_table)            :: tb
        type(score_plan)            :: plan
        character(len=1), parameter :: T = achar(9)
        integer,        allocatable :: pids(:)
        real(real64)                :: st0(5), st(5), best(5), wall, wbest, t0, prep, cold
        integer                     :: i, rep, u
        logical                     :: l_new
        write(*,'(a)') '**** bench_polar_table suite=profile ****'
        call mlx_set_default_device(device_of_arg())
        cs  = read_case(arg_str('cases', 'polar_case.txt'), arg_str('case', '2500_4'))
        call make_data(d, cs, POLAR_SEED_JUDGED, .false., pftc=pftc)
        cfg = arg_config(bench_config(bt=POLAR_CANON_BT, rt=POLAR_CANON_RT))
        t0  = clock_s()
        call prepare(pftc, cfg)
        call mlx_synchronize()
        prep = clock_s() - t0
        cold = 0._real64
        plan%outer   = cs%nptcls / 2
        plan%team    = arg_int('nthr', 24)
        plan%profile = .true.
        pids  = [(i, i = 1, cs%nptcls)]
        call make_driver(tab, pftc, d, pids, plan)
        wbest = huge(wbest)
        best  = 0._real64
        do rep = 0, 3
            st0 = pftc%stage_seconds()
            t0  = clock_s()
            call fill_table(tab, pids, tb)
            wall = clock_s() - t0
            st   = pftc%stage_seconds() - st0
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
            &cs%pftsz, T, cfg%bt, T, cfg%rt, T, formulation_of(cfg), T, device_name(mlx_default_device()), T, &
            &precision_mode(), T, wbest, T, best(1), T, best(2), T, best(3), T, best(4), T, best(5), T, &
            &wbest - sum(best), T, prep, T, cold
        close(u)
        write(*,'(a,f9.4,a,5f9.4,a,f9.4)') '    profile wall ', wbest, ' s; stages ', best, '; rest (copy-out, host) ', &
            &wbest - sum(best)
        call report_digest('profile', trim(cs%name)//' '//plan_label(cfg, plan), digest_halves(tb))
        call pftc%kill
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
        type(polarft_calc)          :: pftc
        type(eul_prob_tab)          :: tab
        type(half_table)            :: tb
        type(score_plan)            :: plan
        character(len=1), parameter :: T = achar(9)
        integer,        allocatable :: pids(:)
        real(real64)                :: wsync, wover, cpu_sync, sub_sync, wall, cpu, sub, t0
        integer                     :: i, rep, u, ns
        logical                     :: l_new
        write(*,'(a)') '**** bench_polar_table suite=overlap ****'
        call mlx_set_default_device(device_of_arg())
        cs  = read_case(arg_str('cases', 'polar_case.txt'), arg_str('case', '2500_4'))
        call make_data(d, cs, POLAR_SEED_JUDGED, .false., pftc=pftc)
        cfg = arg_config(bench_config(bt=POLAR_CANON_BT, rt=POLAR_CANON_RT))
        call prepare(pftc, cfg)
        plan%outer = arg_int('outer', 250)
        plan%team  = arg_int('nthr', 24)
        wsync      = huge(wsync)
        wover      = huge(wover)
        cpu_sync   = 0._real64
        sub_sync   = 0._real64
        pids = [(i, i = 1, cs%nptcls)]
        do ns = 1, 2
            plan%nslots = ns
            call make_driver(tab, pftc, d, pids, plan)
            do rep = 0, 3
                t0  = clock_s()
                call fill_table(tab, pids, tb)
                cpu  = tb%cpu_s
                sub  = tb%submit_s
                wall = clock_s() - t0
                if( rep == 0 ) cycle
                if( ns == 1 .and. wall < wsync )then
                    wsync    = wall
                    cpu_sync = cpu
                    sub_sync = sub
                endif
                if( ns == 2 ) wover = min(wover, wall)
            end do
            call report_digest('overlap', trim(cs%name)//' '//plan_label(cfg, plan), digest_halves(tb))
        end do
        inquire(file='bench_polar_table_overlap.tsv', exist=l_new)
        l_new = .not. l_new
        open(newunit=u, file='bench_polar_table_overlap.tsv', position='append', action='write', status='unknown')
        if( l_new ) write(u,'(a)') 'case'//T//'nrefs'//T//'nptcls'//T//'B'//T//'R'//T//'outer'//T//'formulation'//&
            &T//'device'//T//'precision'//T//'load'//T//'sync_s'//T//'two_slots_s'//T//'host_cpu_sync_s'//T//&
            &'host_submit_sync_s'//T//'hidden_share'
        write(u,'(a,5(a,i0),a,a,a,a,a,a,a,a,4(a,f10.4),a,f8.4)') trim(cs%name), T, cs%nrefs, T, cs%nptcls, T, &
            &cfg%bt, T, cfg%rt, T, plan%outer, T, FORMULATION, T, device_name(mlx_default_device()), T, &
            &precision_mode(), T, arg_str('load', 'none'), T, wsync, T, wover, T, cpu_sync, T, sub_sync, T, &
            &(wsync - wover) / max(cpu_sync + sub_sync, 1.e-9_real64)
        close(u)
        write(*,'(a,f9.4,a,f9.4,a,f9.4,a,f9.4,a,f7.3)') '    overlap: synchronous ', wsync, ' s, two slots ', &
            &wover, ' s; host in the synchronous run: preparation and consumption ', cpu_sync, ' s, staging and '//&
            &'graph building ', sub_sync, ' s; hidden share ', (wsync - wover) / max(cpu_sync + sub_sync, 1.e-9_real64)
        call pftc%kill
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
        type(polarft_calc)            :: pftc
        character(len=:), allocatable :: names, grid
        integer,          allocatable :: ptiles(:)
        integer                       :: ic, i0
        write(*,'(a)') '**** bench_polar_table suite=shiftmap ****'
        ! no team to size (the maps run on the device with one submitting thread): nthr= is refused, not ignored
        if( arg_given('nthr') )then
            write(*,'(a)') 'bench_polar_table: suite=shiftmap takes no nthr= (the maps run on the device with one '//&
                &'submitting thread)'
            error stop 2
        endif
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
            call time_map(pftc, d, read_map(grid, names(i0:ic-1)), ptiles)
            i0 = ic + 1
        end do
        call pftc%kill
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

    ! the box of a map's grid, from its step (box / kscreen / 4)
    pure integer function map_box( mp )
        type(bench_map), intent(in) :: mp
        map_box = nint(4._real64 * real(mp%kscreen, real64) * mp%rho_max / real(mp%nrho - 1, real64))
    end function map_box

    ! the calculator's map of the grid file's map: the screen's or the window's
    pure integer function map_index( mp )
        type(bench_map), intent(in) :: mp
        map_index = SHIFTMAP_WINDOW
        if( trim(mp%name) == 'screen' ) map_index = SHIFTMAP_SCREEN
    end function map_index

    ! every particle's ncand candidates: 1 + mod(i - 1 + (c - 1) (nrefs / ncand), nrefs) of particle i
    function map_candidates( d, mp ) result(cands)
        type(bench_data), intent(in) :: d
        type(bench_map),  intent(in) :: mp
        integer :: cands(mp%ncand, d%cs%nptcls)
        integer :: i, c, stride
        stride = d%cs%nrefs / mp%ncand
        do i = 1, d%cs%nptcls
            do c = 1, mp%ncand
                cands(c, i) = 1 + modulo(i - 1 + (c - 1) * stride, d%cs%nrefs)
            end do
        end do
    end function map_candidates

    ! one fill of the maps' stage: every particle's candidates read on the map, the results handed over
    ! (candidate, particle in the batch's order: half 1's particles, then half 2's)
    subroutine score_maps_pass( tab, nptcls, res )
        type(eul_prob_tab),      intent(inout) :: tab
        integer,                 intent(in)    :: nptcls
        type(polar_map_results), intent(out)   :: res
        call tab%fill_tab_range(1, nptcls)
        call assert_int(0, len(tab%message()), 'bench_polar_table: the shift maps are filled: '//tab%message())
        call tab%batch_map_results(res)
    end subroutine score_maps_pass

    ! one map on the case: the calculator's reference bins and the map made (timed apart), then each tile of
    ! pairs timed (warm-up, best of 3, MLX peak) and profiled once; every result in range. The calculator is fed
    ! at the first map, and again when a map's box differs.
    subroutine time_map( pftc, d, mp, ptiles )
        type(polarft_calc), intent(inout) :: pftc
        type(bench_data),   intent(inout) :: d
        type(bench_map),    intent(in)    :: mp
        integer,            intent(in)    :: ptiles(:)
        type(eul_prob_tab)        :: tab
        type(parameters)          :: params
        type(polar_map_results)   :: res
        type(map_timing)          :: tm
        real(real32), allocatable :: cut(:,:)
        type(bench_case)          :: cs
        character(len=32)         :: tile
        real(real64), allocatable :: rho(:)
        real(real64)              :: t0, st0(4)
        integer(int64)            :: dig
        integer                   :: ip, rep, i, imap, n, n1
        logical                   :: fits, l_evidence
        real(real64)              :: trial_bytes, budget
        call check_map_case(d%cs, mp)
        ! read before any staging: a malformed value stops here, not after the data are made
        l_evidence = arg_int('evidence', 0) /= 0
        fits = .false.
        budget = budget_bytes()
        do ip = 1, size(ptiles)
            if( ptiles(ip) < 1 ) error stop 'bench_polar_table: particle tiles must be positive'
            trial_bytes = map_estimate_bytes(d%cs, mp, ptiles(ip), mp%norder)
            fits = fits .or. trial_bytes <= budget
        end do
        if( .not. fits )then
            do ip = 1, size(ptiles)
                tm%ptcl_tile = ptiles(ip)
                tm%est = map_estimate_bytes(d%cs, mp, ptiles(ip), mp%norder)
                tm%status = budget_status()
                call write_map_row(d, mp, tm)
            end do
            return
        endif
        ! The recorded grid order allows rejecting an impossible sweep before staging even the host memos.
        if( .not. allocated(d%wsq) .or. d%cs%box /= map_box(mp) )then
            cs     = d%cs
            cs%box = map_box(mp)
            call make_data(d, cs, POLAR_SEED_JUDGED, .false., pftc=pftc)
        endif
        imap = map_index(mp)
        t0   = clock_s()
        call prepare(pftc, bench_config(bt=POLAR_CANON_BT, rt=POLAR_CANON_RT))
        call mlx_synchronize()
        tm%prep(1) = clock_s() - t0
        t0  = clock_s()
        rho = [(real(i - 1, real64) * mp%rho_max / real(mp%nrho - 1, real64), i = 1, mp%nrho)]
        call pftc%new_shiftmap(imap, rho, mp%nalpha, mp%kscreen)
        call assert_int(0, refused(pftc), 'bench_polar_table: the map is made: '//pftc%message())
        if( refused(pftc) /= 0 ) return
        ! the driver: every particle's candidates on this map, the maps' stage alone, one block per half
        n            = d%cs%nptcls
        n1           = size(half_ptcls(n, 1))
        params%pftsz = d%cs%pftsz
        params%box   = d%cs%box
        call tab%new_pipeline(params, pftc, [(i, i = 1, n)])
        call tab%set_candidates(map_candidates(d, mp))
        call tab%set_fill_stages(.false., .true.)
        call tab%use_shiftmap(imap, mp%prior_w)
        call tab%set_fill_options(n, 1, .false., .false.)
        call assert_int(0, len(tab%message()), 'bench_polar_table: the driver is made: '//tab%message())
        call set_width_mode(cut, arg_str('widths', 'all'), mp%ncand, n)
        if( allocated(cut) ) call tab%set_width_cutoffs(cut)
        call mlx_synchronize()
        tm%prep(2)     = clock_s() - t0
        tm%norder_used = pftc%shiftmap_order(imap)
        tm%terms = pftc%shiftmap_term_counts(imap)
        tm%resident = real(mlx_active_memory(), real64)
        tm%host_bytes = map_host_bytes(d%cs)
        do ip = 1, size(ptiles)
            tm%ptcl_tile  = ptiles(ip)
            tm%load1      = load_average()
            tm%est        = map_estimate_bytes(d%cs, mp, ptiles(ip), tm%norder_used)
            tm%tile_bytes = tm%est - map_estimate_bytes(d%cs, mp, 0, tm%norder_used)
            tm%walls      = -1._real64
            tm%pwall      = -1._real64
            tm%peak       = -1._real64
            tm%cache      = -1._real64
            tm%stages     = 0._real64
            tm%status     = 'timed'
            if( tm%est > budget_bytes() )then
                tm%status = budget_status()
                call write_map_row(d, mp, tm)
                cycle
            endif
            call pftc%set_shiftmap_options(ptiles(ip), .false., l_evidence, .false.)
            t0 = clock_s()
            call score_maps_pass(tab, n, res)
            call mlx_synchronize()
            tm%cold = clock_s() - t0
            call mlx_reset_peak_memory()
            do rep = 1, 3
                t0 = clock_s()
                call score_maps_pass(tab, n, res)
                tm%walls(rep) = clock_s() - t0
            end do
            tm%peak       = real(mlx_peak_memory(), real64)
            tm%cache      = real(mlx_cache_memory(), real64)
            call pftc%set_shiftmap_options(ptiles(ip), .false., l_evidence, .true.)
            st0 = pftc%shiftmap_seconds()
            t0  = clock_s()
            call score_maps_pass(tab, n, res)
            tm%pwall  = clock_s() - t0
            tm%stages = pftc%shiftmap_seconds() - st0
            if( .not. allocated(res%loss) ) return
            tm%width_pairs = count(res%sdev >= 0._real32)
            call assert_true(results_in_range(res, mp), 'bench_polar_table: every '//trim(mp%name)//&
                &' result is finite and on the grid')
            call write_map_row(d, mp, tm)
            dig = DIGEST_START
            call digest_maps(dig, res, 1, n1)
            call digest_maps(dig, res, n1 + 1, n)
            write(tile, '(a,i0)') ' ptcl_tile=', ptiles(ip)
            call report_digest('shiftmap', trim(mp%name)//trim(tile), dig)
            call mlx_clear_cache()
        end do
        call tab%kill
        call pftc%kill_shiftmap
        call pftc%kill_ref_bins
        call mlx_clear_cache()
    end subroutine time_map

    ! a conservative estimate of a shift-map configuration's device bytes: the dense workspace of both halves at
    ! the canonical plan, the maps' resident data of both halves, and per particle of a tile its order-expanded
    ! weighted spectra (complex), its candidates' spectra, the contraction's output with its transform and their
    ! reordered copy, the directions' transform with its reordered copy, and the cell-sized temporaries of the
    ! reductions per pair; counted twice: the tile in use and the previous tile's buffers MLX's cache keeps
    real(real64) function map_estimate_bytes( cs, mp, ptcl_tile, norder )
        type(bench_case), intent(in) :: cs
        type(bench_map),  intent(in) :: mp
        integer,          intent(in) :: ptcl_tile, norder
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
        map_estimate_bytes = resident + 2._real64 * real(ptcl_tile, real64) * per_ptcl
    end function map_estimate_bytes

    ! Synthetic sensitivity modes: predetermined survivors, not a production best-so-far shortlist. cut is left
    ! unallocated when every width is wanted.
    subroutine set_width_mode( cut, mode, ncand, nptcls )
        real(real32), allocatable, intent(out) :: cut(:,:)
        character(len=*),          intent(in)  :: mode
        integer,                   intent(in)  :: ncand, nptcls
        integer :: c
        select case(mode)
            case('all')
                return
            case('none', 'quarter')
                allocate(cut(ncand, nptcls))
                cut = -huge(1._real32)
                if( mode == 'quarter' )then
                    do c = 4, ncand, 4
                        cut(c, :) = huge(1._real32)
                    end do
                endif
            case default
                error stop 'bench_polar_table: widths=all|none|quarter'
        end select
    end subroutine set_width_mode

    ! the host bytes the route holds for a case: the calculator's memos of both parities' references and of the
    ! particles, the particles' shell and weighted square sums, the shell weights and the temperatures
    real(real64) function map_host_bytes( cs ) result(bytes)
        type(bench_case), intent(in) :: cs
        integer(int64) :: n1, nk
        n1    = int(cs%pftsz + 1, int64)
        nk    = int(cs%kto - cs%kfrom + 1, int64)
        bytes = real(8_int64 * (4_int64 * n1 * nk * int(cs%nrefs, int64) + 2_int64 * n1 * nk * int(cs%nptcls, int64) + &
            &(nk + 2_int64) * int(cs%nptcls, int64)) + 4_int64 * (6_int64 * nk + int(cs%nptcls, int64)), real64)
    end function map_host_bytes

    logical function results_in_range( res, mp )
        type(polar_map_results), intent(in) :: res
        type(bench_map),         intent(in) :: mp
        results_in_range = all(abs(res%loss) < huge(1._real32)) .and. all(res%sdev >= 0._real32 .or. bits_equal(res%sdev, -1._real32)) .and. &
            &all(res%sdev < huge(1._real32)) .and. all(res%irot >= 1 .and. res%irot <= mp%nrots) .and. &
            &all(res%irho >= 1 .and. res%irho <= mp%nrho) .and. all(res%ialpha >= 1 .and. res%ialpha <= mp%nalpha)
    end function results_in_range

    ! a row of bench_polar_table_shiftmap.tsv: SIMPLE's shift-map columns by name (device for nthr, precision for
    ! fftw_plans, us_map_thread the device's microseconds per map), then the Bessel order used, the MLX peak and
    ! cache, the preparation and the copy-out (the profiled pass's), and the tile, the preparation's parts, the
    ! host's share of the profiled pass per map, its wall, and SIMPLE's full-team rate with the ratio (context)
    subroutine write_map_row( d, mp, tm )
        type(bench_data), intent(in) :: d
        type(bench_map),  intent(in) :: mp
        type(map_timing), intent(in) :: tm
        character(len=*), parameter :: TSV = 'bench_polar_table_shiftmap.tsv'
        character(len=*), parameter :: FMT = '(a,5(a,i0),a,a,7(a,i0),a,f10.4,a,es12.5,a,f6.2,4(a,f10.4),a,f10.3,a,'//&
            &'es12.5,3(a,f10.3),a,a,a,i0,2(a,es12.5),2(a,f10.4),a,i0,2(a,f10.4),2(a,f10.3),a,f10.4,a,es12.5,a,f8.3,'//&
            &'a,es12.5,a,a)'
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
            &'precision'//T//'norder_used'//T//'mlx_peak_bytes'//T//'mlx_cache_bytes'//T//'prep_s'//T//'copyout_s'//T//&
            &'ptcl_tile'//T//'prep_refs_s'//T//'prep_maps_s'//T//'us_copyout'//T//'us_host'//T//'profile_wall_s'//T//&
            &'cpu_maps_per_s'//T//'ratio_cpu'//T//'est_bytes'//T//'status'//T//'mlx_revision'//T//'simple_commit'//T//&
            &'fftw_plans'//T//'width_mode'//T//'evidence'//T//'width_pairs'//T//'active_radius_orders'//T//&
            &'executed_radius_orders'//T//'cold_s'//T//'prepared_device_bytes'//T//'host_bytes'//T//&
            &'tile_cache_est_bytes'
        write(u,FMT, advance='no') trim(mp%name), T, &
            &d%cs%nspace, T, d%cs%nstates, T, d%cs%nrefs, T, d%cs%nptcls, T, mp%ncand, T, &
            &device_name(mlx_default_device()), T, mp%pftsz, T, mp%nrots, T, mp%kfrom, T, mp%kscreen, T, mp%nrho, &
            &T, mp%nalpha, T, mp%norder, T, mp%rho_max, T, mp%prior_w, T, tm%load1, T, wall, T, tm%walls(1), T, &
            &tm%walls(2), T, tm%walls(3), T, wall * 1.e6_real64 / nmaps, T, rate, T, us(1), T, us(2), T, &
            &us(3), T, precision_mode(), T, tm%norder_used, T, tm%peak, T, tm%cache, T, sum(tm%prep), T, tm%stages(4), &
            &T, tm%ptcl_tile, T, tm%prep(1), T, tm%prep(2), T, us(4), T, &
            &(tm%pwall - sum(tm%stages)) * 1.e6_real64 / nmaps, T, tm%pwall, T, cpu, T, ratio, T, tm%est, T, tm%status
        write(u,'(8a,4(a,i0),4(a,es16.8))') T, arg_str('revision', 'working-tree'), T, trim(mp%simple_commit), &
            &T, trim(mp%fftw_plans), T, arg_str('widths', 'all'), T, arg_int('evidence', 0), T, tm%width_pairs, &
            &T, tm%terms(1), T, tm%terms(2), T, tm%cold, T, tm%resident, T, tm%host_bytes, T, tm%tile_bytes
        close(u)
        write(*,'(a,i0,a,i0,a,f9.4,a,es11.4,a,f7.3,2(a,es10.3),2(a,f8.3),a)') '    shiftmap '//trim(mp%name)//&
            &' ptcl_tile=', tm%ptcl_tile, ' norder_used=', tm%norder_used, ' wall=', wall, ' s, ', rate, &
            &' maps/s (x', ratio, ' SIMPLE full team), peak ', tm%peak, ' B, cache ', tm%cache, ' B, prep ', &
            &sum(tm%prep), ' s, copy-out ', tm%stages(4), ' s: '//tm%status
    end subroutine write_map_row

end module mlxf_bench_polar_table
