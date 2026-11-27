!@descr: the kernel-forms benchmark: ways of writing a Metal kernel, set beside the toys' current kernels on the GPU
! mlxf_test_exec test=bench_kernel_forms suite=<probe|tail|reduce|sizes|select|insert|waits> [key=value ...]. suite=probe asserts what the
! Metal features reached through the kernel wrapper give. The other suites check each alternative form against the
! current one on seeded inputs (mode=agree, asserted), then time them in interleaved pairs after an A-A control
! (mode=time; mode=part is one process of scripts/run_parts.sh). A key a suite does not read stops the program.
module mlxf_bench_kernel_forms
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf,                         only: mlx_array, mlx_custom_kernel, mlx_from, mlx_to, mlx_eval, mlx_async_eval, &
                                        mlx_synchronize, mlx_set_default_device, mlx_last_error, mlx_peak_memory, &
                                        mlx_reset_peak_memory, mlx_cache_memory, mlx_custom_kernel_spec, reshape, sum, &
                                        maxloc, merge, mlx_take_along_dim, mlx_put_along_dim, mlx_concatenate, &
                                        mlx_argpartition, mlx_argsort, mlx_slice, mlx_cumsum, mlx_astype, mlx_full, &
                                        mlx_take, matmul, MLX_DEVICES, MLX_DTYPES
use mlxf_test_defs,               only: POLAR_DIST_INVALID, POLAR_DIST_MAX, POLAR_DIST_VALID, POLAR_ARG_CUTOFF, &
                                        POLAR_DRAW_FLOOR, POLARFT_TAIL_ROT_BLK, FORMS_REDUCE_TOL, FORMS_INSERT_TOL, &
                                        polarft_tile_spec, OSMPL_PAD_FAC, polar_table_entries, probe_case
use mlxf_toy_polarft_workspace,   only: tail_spec
use mlxf_toy_projector_workspace, only: gather_spec
use mlxf_bench_insert_probe,      only: probe_spec, seeded_case, window_coefficients
use mlxf_oracle_polar,            only: polar_first_min, polar_draws_off
use mlxf_bench_kernel_forms_src,  only: group_sum_spec, simd_probe_spec, tgmem_probe_spec, tail_simd_spec, &
                                        tail_plain_spec, reduce_spec, sizes_in_input, select_spec, insert_pull_spec
use mlxf_test_utils,              only: assert_true, gpu_present, seeded_uniform, bits_equal, digest_bits, &
                                        set_fixed_seed, wait_for_go_file
use mlxf_test_reduce,             only: nan_maxval
implicit none
private

public :: run_bench_kernel_forms

! the keys each suite reads, blank separated; test and suite belong to the executable
character(len=*), parameter :: SUITE_KEYS(7) = [character(len=96) :: 'probe form', &
    &'tail mode seed tiles form passes nparts part nthr go', 'reduce mode seed', 'sizes mode seed form set', &
    &'select mode seed', 'insert mode seed n', 'waits mode seed']
character(len=*), parameter :: PROBE_FORMS(5) = [character(len=3) :: 'all', 'a', 'b', 'c', 'd']
character(len=*), parameter :: MODES(3)       = [character(len=5) :: 'agree', 'time', 'part']
character(len=*), parameter :: TAIL_FORMS(3)  = [character(len=2) :: 't0', 't1', 't2']
character(len=*), parameter :: RED_FORMS(4)   = [character(len=2) :: 'r0', 'r1', 'r2', 'r3']
character(len=*), parameter :: SIZE_FORMS(4)  = [character(len=9) :: 'gather g0', 'gather g1', 'insert g0', 'insert g1']
character(len=*), parameter :: SIZE_MODES(3)  = [character(len=7) :: 'agree', 'time', 'compile']
character(len=*), parameter :: G_FORMS(2)     = [character(len=2) :: 'g0', 'g1']
character(len=*), parameter :: SEL_FORMS(5)   = [character(len=3) :: 'e0', 'e1', 'e2', 'e3', 'e1n']
character(len=*), parameter :: INS_FORMS(3)   = [character(len=2) :: 'd0', 'd1', 'd2']
character(len=*), parameter :: WAIT_FORMS(2)  = [character(len=2) :: 'f0', 'f1']
integer(int64),   parameter :: DIGEST_START   = 88172645463325252_int64
real(real64),     parameter :: PI             = acos(-1._real64)
! ---- the probe: group sizes and groups of the group sum, the fixed tree's group, the SIMD launch, the
! threadgroup array's sizes by doubling (bytes), the seed
integer, parameter :: GROUP_TGS(4)  = [32, 64, 256, 1024]
integer, parameter :: GROUP_NG      = 64
integer, parameter :: TREE_TG       = 256
integer, parameter :: SIMD_N        = 256
integer, parameter :: SIMD_TG       = 64
integer, parameter :: SIMD_W        = 32
integer, parameter :: SIMD_NOUT     = 7
integer, parameter :: TGMEM_FIRST   = 4096
integer, parameter :: TGMEM_LAST    = 65536
integer, parameter :: TGMEM_THREADS = 256
integer, parameter :: PROBE_SEED    = 26
! ---- agreement and timing: runs compared for repeatability; timed evaluations per form and pair (median);
! interleaved pairs; A-A pairs
integer, parameter :: NREPEAT = 3
integer, parameter :: NTIMED  = 5
integer, parameter :: NPAIRS  = 5
integer, parameter :: NAA     = 3
! ---- the tail: K1's canonical tile (pftsz 182, rt 250, bt 64), 40 tiles, blocks of 4 tiles (64,000 pairs) for
! the rotation bound; the particles' inverse temperatures in turn; the temperature that leaves the minimum only
integer,      parameter :: TAIL_PFTSZ  = 182
integer,      parameter :: TAIL_NK     = 61
integer,      parameter :: TAIL_RT     = 250
integer,      parameter :: TAIL_BT     = 64
integer,      parameter :: TAIL_TILES  = 40
integer,      parameter :: TAIL_BLOCK  = 4
integer,      parameter :: TAIL_PASSES = 9
real(real32), parameter :: TEMP_LEVELS(4) = [1._real32, 30._real32, 420._real32, 1.e4_real32]
real(real32), parameter :: TEMP_MINIMA    = 1.e30_real32
! the rows' planted cases, by cumulative share of the pairs: no valid rotation, every seventh rotation invalid, a
! tie at the minimum 37 rotations apart, the minimum at the last rotation; a raw value that makes an entry invalid
real(real64), parameter :: SHARE_NONE  = 0.005_real64
real(real64), parameter :: SHARE_SOME  = 0.010_real64
real(real64), parameter :: SHARE_TIE   = 0.020_real64
real(real64), parameter :: SHARE_LAST  = 0.030_real64
real(real32), parameter :: RAW_INVALID = 1.e30_real32
! ---- the reduction: evaluations, sums per evaluation, terms (the last ones zero, as padding), threads a group
integer, parameter :: RED_NE    = 500
integer, parameter :: RED_NS    = 23
integer, parameter :: RED_NT    = 6144
integer, parameter :: RED_NREAL = 6136
integer, parameter :: RED_TG    = 256
! ---- the sizes: K2's canonical fused gather (box 160 padded to 320, pftsz 182, shells 2 to 62, 2,500 directions a
! launch, 64 threads a group, both parities), the npts values of the compile runs (shells dropped in eights), the
! insertion probe's kernel at n = 64 on one batch of 500 planes, its collision-free check on one plane with data
! only on pixels 6 apart (their windows never meet)
integer, parameter :: SZ_M      = 320
integer, parameter :: SZ_PFTSZ  = 182
integer, parameter :: SZ_KFROM  = 2
integer, parameter :: SZ_NK     = 61
integer, parameter :: SZ_TN     = 2500
integer, parameter :: SZ_TG     = 64
integer, parameter :: SZ_NCOMP  = 8
integer, parameter :: SZ_N      = 64
integer, parameter :: SZ_PLANES = 500
integer, parameter :: SZ_SPARSE = 6
! ---- the selection: references by particles, the K values (SIMPLE's npeaks and npeaks_inpl), the share of the
! columns with planted ties
integer,      parameter :: SEL_NREF    = 10000
integer,      parameter :: SEL_NPART   = 1024
integer,      parameter :: SEL_KS(2)   = [3, 10]
real(real64), parameter :: SEL_SHARE   = 0.01_real64
real(real32), parameter :: SEL_SENTRY  = -huge(1._real32)
! ---- the insertion: one batch of planes (the probe's MAXIMGBATCHSZ), the seeds' batches taken in turn from one
! seeded case of three batches
integer, parameter :: INS_PLANES = 500
integer, parameter :: INS_SEEDS  = 3
! ---- the waits: 40 tiles of K3's product (bt 64 by 4nk 244 by 2rt 500, 183 bins), about 30 % of the pairs
! listed (seeded), a persistent buffer of the largest count of seed 1 times 1.25, the sentinel of its tail
integer,      parameter :: WAIT_TILES = 40
integer,      parameter :: WAIT_BT    = 64
integer,      parameter :: WAIT_K4    = 244
integer,      parameter :: WAIT_RT    = 250
integer,      parameter :: WAIT_BINS  = 183
real(real32), parameter :: WAIT_SHARE = 0.3_real32
real(real64), parameter :: WAIT_CAP   = 1.25_real64
real(real32), parameter :: WAIT_SENT  = -huge(1._real32)

! a suite whose forms are timed: seconds(f) is one evaluation of form f, launched and waited for
type, abstract :: form_bench
  contains
    procedure(seconds_of), deferred :: seconds
end type form_bench

abstract interface
    function seconds_of( self, f ) result(sec)
        import :: form_bench, real64
        class(form_bench), intent(inout) :: self
        integer,           intent(in)    :: f
        real(real64) :: sec
    end function seconds_of
end interface

! the tail's tiles on the device, their variates and temperatures on the host, and the forms' kernels: 1 the
! current tail, 2 one SIMD group per pair, 3 the plain sum; 4 the current tail's rows variant
type, extends(form_bench) :: tail_bench
    integer                      :: ntiles = 0
    type(mlx_array), allocatable :: raw(:), iw(:), temps(:), u(:)
    type(mlx_array)              :: tmin, uzero, utwo, par
    type(mlx_custom_kernel)      :: kern(4)
    real(real32),    allocatable :: temps_h(:,:), u_h(:,:,:)
  contains
    procedure :: seconds => tail_seconds
end type tail_bench

! the reduction's operands x (nt, ne) and y (ns, nt), y's transpose for the graph, and the kernels of forms 1 to 3
type, extends(form_bench) :: reduce_bench
    type(mlx_array)         :: x, y, yt
    type(mlx_custom_kernel) :: kern(3)
  contains
    procedure :: seconds => reduce_seconds
end type reduce_bench

! the sizes: forms 1 and 2 the gather with sizes as templates and in an input, on both parities' cubes; 3 and 4
! the insertion's kernel likewise on one batch
type, extends(form_bench) :: sizes_bench
    type(mlx_array)         :: cube(2), hk, rot, coef, szg
    type(mlx_array)         :: ihk, irot, iom, ic, iq, icoef, szi
    type(mlx_custom_kernel) :: kern(4)
  contains
    procedure :: seconds => sizes_seconds
end type sizes_bench

! the selection's table (nref, npart) and its negation, the sentinels, the K of the run and the kernels of E2, E3
type, extends(form_bench) :: select_bench
    type(mlx_array)         :: tabd, tneg, low, high
    integer                 :: k = 0
    type(mlx_custom_kernel) :: kern(2)
  contains
    procedure :: seconds => select_seconds
end type select_bench

! the insertion of one batch at one box: the probe's kernel (form 1) and the two pulls (2, 3), the inputs of each
type, extends(form_bench) :: insert_bench
    type(mlx_array)         :: hk, rot, om, c, q, coef, pmap, par
    type(mlx_custom_kernel) :: kern(3)
  contains
    procedure :: seconds => insert_seconds
end type insert_bench

! the waits: the references' product operand, per tile the particles' operand and the variates of the listing,
! the pairs' numbers, the capacity and its positions
type, extends(form_bench) :: waits_bench
    type(mlx_array)              :: g, pairs, seq
    type(mlx_array), allocatable :: pt(:), u(:)
    integer                      :: cap = 0
  contains
    procedure :: seconds => waits_seconds
end type waits_bench

contains

    subroutine run_bench_kernel_forms( suite, found )
        character(len=*), intent(in)  :: suite
        logical,          intent(out) :: found
        found = .true.
        select case( trim(suite) )
            case( 'probe' )
                call check_keys(suite)
                call require_gpu
                call bench_probe(arg_choice('form', PROBE_FORMS))
            case( 'tail' )
                call check_keys(suite)
                call require_gpu
                call bench_tail(arg_choice('mode', MODES))
            case( 'reduce' )
                call check_keys(suite)
                call require_gpu
                call bench_reduce(arg_choice('mode', MODES(1:2)))
            case( 'sizes' )
                call check_keys(suite)
                call require_gpu
                call bench_sizes(arg_choice('mode', SIZE_MODES))
            case( 'select' )
                call check_keys(suite)
                call require_gpu
                call bench_select(arg_choice('mode', MODES(1:2)))
            case( 'insert' )
                call check_keys(suite)
                call require_gpu
                call bench_insert(arg_choice('mode', MODES(1:2)))
            case( 'waits' )
                call check_keys(suite)
                call require_gpu
                call bench_waits(arg_choice('mode', MODES(1:2)))
            case default
                found = .false.
        end select
    end subroutine run_bench_kernel_forms

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

    integer function arg_int( key, dflt )
        character(len=*), intent(in) :: key
        integer,          intent(in) :: dflt
        character(len=:), allocatable :: v
        integer                       :: ios
        arg_int = dflt
        v       = arg_str(key, '?')
        read(v, *, iostat=ios) arg_int
        if( ios /= 0 ) arg_int = dflt
    end function arg_int

    ! the value of key among choices, the first choice when the key is absent; another value stops the program
    function arg_choice( key, choices ) result(val)
        character(len=*), intent(in) :: key, choices(:)
        character(len=:), allocatable :: val
        val = arg_str(key, trim(choices(1)))
        if( any(choices == val) ) return
        write(*,'(a)') 'bench_kernel_forms: '//key//'='//val//' is not one of the values the suite reads'
        error stop 2
    end function arg_choice

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
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            ieq = index(arg, '=')
            if( ieq > 1 )then
                if( arg(1:ieq-1) == 'test' .or. arg(1:ieq-1) == 'suite' ) cycle
                if( index(' '//trim(keys)//' ', ' '//arg(1:ieq-1)//' ') > 0 ) cycle
            endif
            write(*,'(a)') 'bench_kernel_forms: suite='//trim(suite)//' does not read '//trim(arg)//' (its keys:'// &
                &trim(keys)//')'
            error stop 2
        end do
    end subroutine check_keys

    ! the forms are Metal kernels: a session without a GPU is refused
    subroutine require_gpu
        if( .not. gpu_present() )then
            write(*,'(a)') 'bench_kernel_forms: refused: the forms are Metal kernels and run on the GPU only'
            error stop 2
        endif
        call mlx_set_default_device(MLX_DEVICES%gpu)
    end subroutine require_gpu

    real(real64) function clock_s()
        integer(int64) :: c, rate
        call system_clock(c, rate)
        clock_s = real(c, real64) / real(rate, real64)
    end function clock_s

    ! ---- timing ------------------------------------------------------------------------------------------------

    ! the median of NTIMED evaluations of form f, after the peak memory was reset; peak is MLX's peak since
    real(real64) function median_seconds( b, f, peak )
        class(form_bench), intent(inout) :: b
        integer,           intent(in)    :: f
        real(real64),      intent(out)   :: peak
        real(real64) :: t(NTIMED)
        integer      :: i
        call mlx_reset_peak_memory()
        do i = 1, NTIMED
            t(i) = b%seconds(f)
        end do
        peak = real(mlx_peak_memory(), real64)
        median_seconds = median(t)
    end function median_seconds

    ! n interleaved pairs of the current form cur and the alternative alt: pair p times cur then alt when p is odd,
    ! alt then cur when even; ratios(p) is cur's median over alt's
    subroutine interleaved( b, cur, alt, ratios, label )
        class(form_bench), intent(inout) :: b
        integer,           intent(in)    :: cur, alt
        real(real64),      intent(out)   :: ratios(:)
        character(len=*),  intent(in)    :: label
        real(real64) :: tc, ta, pc, pa
        integer      :: p
        do p = 1, size(ratios)
            if( mod(p, 2) == 1 )then
                tc = median_seconds(b, cur, pc)
                ta = median_seconds(b, alt, pa)
            else
                ta = median_seconds(b, alt, pa)
                tc = median_seconds(b, cur, pc)
            endif
            ratios(p) = tc / ta
            write(*,'(a,i0,a,es11.4,a,es11.4,a,f8.4,a,es10.3,a,es10.3)') '    '//label//' pair ', p, ': ', tc, &
                &' s against ', ta, ' s, ratio ', ratios(p), '; peaks ', pc, ', ', pa
        end do
    end subroutine interleaved

    ! decision 3's verdict on five pair ratios, inconclusive within twice the A-A floor or above a 10 % floor
    function verdict( ratios, floor ) result(v)
        real(real64), intent(in) :: ratios(:), floor
        character(len=:), allocatable :: v
        real(real64)                  :: m, margin
        m = median(ratios)
        if( m >= 1.30_real64 .and. count(ratios >= 1.30_real64) >= 4 )then
            v = 'preferred'
            margin = m - 1.30_real64
        else if( m >= 0.95_real64 .and. m <= 1.05_real64 )then
            v = 'equivalent'
            margin = min(m - 0.95_real64, 1.05_real64 - m)
        else if( m < 0.95_real64 )then
            v = 'worse'
            margin = 0.95_real64 - m
        else
            v = 'inconclusive'
            margin = huge(m)
        endif
        if( floor > 0.10_real64 .or. margin < 2._real64 * floor ) v = 'inconclusive'
    end function verdict

    ! the A-A control of form f, then each alternative against cur, with its verdict
    subroutine time_forms( b, cur, alts, names )
        class(form_bench), intent(inout) :: b
        integer,           intent(in)    :: cur, alts(:)
        character(len=*),  intent(in)    :: names(:)
        real(real64) :: aa(NAA), r(NPAIRS), floor, t
        integer      :: i, f
        ! a warm-up evaluation of every form first
        t = b%seconds(cur)
        do i = 1, size(alts)
            t = b%seconds(alts(i))
        end do
        call interleaved(b, cur, cur, aa, 'A-A '//trim(names(cur)))
        floor = nan_maxval(abs(aa - 1._real64))
        write(*,'(a,f8.4,a)') '    A-A floor ', 100._real64 * floor, ' %'
        do i = 1, size(alts)
            f = alts(i)
            call interleaved(b, cur, f, r, trim(names(cur))//'/'//trim(names(f)))
            write(*,'(a,f8.4,a,i0,a)') '    '//trim(names(cur))//'/'//trim(names(f))//': median ratio ', median(r), &
                &', at or above 1.30 in ', count(r >= 1.30_real64), ' of 5: '//verdict(r, floor)
        end do
    end subroutine time_forms

    pure real(real64) function median( x )
        real(real64), intent(in) :: x(:)
        real(real64) :: s(size(x)), v
        integer      :: i, j, n
        s = x
        n = size(s)
        do i = 2, n
            v = s(i)
            j = i - 1
            do while( j >= 1 )
                if( s(j) <= v ) exit
                s(j+1) = s(j)
                j = j - 1
            end do
            s(j+1) = v
        end do
        if( mod(n, 2) == 1 )then
            median = s((n + 1) / 2)
        else
            median = 0.5_real64 * (s(n / 2) + s(n / 2 + 1))
        endif
    end function median

    ! ---- suite probe -------------------------------------------------------------------------------------------

    subroutine bench_probe( form )
        character(len=*), intent(in) :: form
        write(*,'(a)') '**** bench_kernel_forms suite=probe ****'
        if( form == 'all' .or. form == 'a' ) call probe_group_sums
        if( form == 'all' .or. form == 'b' ) call probe_simd
        if( form == 'all' .or. form == 'c' ) call probe_tree
        if( form == 'all' .or. form == 'd' ) call probe_tgmem
    end subroutine bench_probe

    ! the group sums of x (ng groups of tg values) on the device; status 0 when they were evaluated and copied
    subroutine group_sums( kern, x, sums, status )
        type(mlx_custom_kernel), intent(in)  :: kern
        real(real32),            intent(in)  :: x(:)
        real(real32),            intent(out) :: sums(:)
        integer,                 intent(out) :: status
        type(mlx_array), allocatable :: outs(:)
        type(mlx_array)              :: xd
        xd = mlx_from(x)
        call kern%apply([xd], outs, status)
        if( status == 0 ) call mlx_eval(outs(1), status=status)
        if( status == 0 ) call mlx_to(sums, outs(1), status=status)
    end subroutine group_sums

    ! (a) small integers sum exactly in any order: each group's sum is compared with the host's, bit for bit
    subroutine probe_group_sums
        type(mlx_custom_kernel)   :: kern
        real(real32), allocatable :: x(:), sums(:)
        real(real64), allocatable :: ref(:)
        integer                   :: k, tg, st, nbad, g
        do k = 1, size(GROUP_TGS)
            tg   = GROUP_TGS(k)
            x    = small_integers(GROUP_NG * tg, PROBE_SEED + k)
            allocate(ref(GROUP_NG))
            do g = 1, GROUP_NG
                ref(g) = sum(real(x((g-1)*tg+1:g*tg), real64))
            end do
            allocate(sums(GROUP_NG))
            kern = mlx_custom_kernel(group_sum_spec(GROUP_NG, tg))
            call group_sums(kern, x, sums, st)
            nbad = GROUP_NG
            if( st == 0 ) nbad = count(.not. bits_equal(sums, real(ref, real32)))
            write(*,'(a,i0,a,i0,a,i0,a,i0)') '    a: threadgroup array and barriers, groups of ', tg, ': status ', st, &
                &', exact group sums ', GROUP_NG - nbad, ' of ', GROUP_NG
            if( st /= 0 ) write(*,'(a)') '       '//mlx_last_error()
            call assert_true(st == 0 .and. nbad == 0, 'a group sum of small integers through a threadgroup array '// &
                &'with barriers is exact for every group')
            deallocate(sums, ref)
        end do
    end subroutine probe_group_sums

    ! (b) the SIMD-group functions on integers: lane and SIMD-group indices, the width, sum, minimum, inclusive
    ! prefix sum and a shuffle, each compared with the host's for every thread
    subroutine probe_simd
        type(mlx_custom_kernel)      :: kern
        type(mlx_array), allocatable :: outs(:)
        type(mlx_array)              :: xd
        real(real32),    allocatable :: x(:), res(:,:), ref(:,:)
        character(len=*), parameter  :: WHAT(SIMD_NOUT) = [character(len=25) :: 'lane index', 'SIMD-group index', &
            &'width', 'simd_sum', 'simd_min', 'simd_prefix_inclusive_sum', 'simd_shuffle']
        integer :: st, k
        x    = small_integers(SIMD_N, PROBE_SEED)
        kern = mlx_custom_kernel(simd_probe_spec(SIMD_N, SIMD_TG, SIMD_NOUT))
        xd   = mlx_from(x)
        allocate(res(SIMD_NOUT, SIMD_N))
        call kern%apply([xd], outs, st)
        if( st == 0 ) call mlx_eval(outs(1), status=st)
        if( st == 0 ) call mlx_to(res, outs(1), status=st)
        write(*,'(a,i0)') '    b: SIMD-group functions, 32 lanes, threadgroups of 64: status ', st
        if( st /= 0 )then
            write(*,'(a)') '       '//mlx_last_error()
            call assert_true(.false., 'the SIMD-group functions build and run through the kernel wrapper')
            return
        endif
        ref = simd_reference(x)
        do k = 1, SIMD_NOUT
            write(*,'(a,a25,a,i0,a,i0)') '       ', WHAT(k), ': exact for ', &
                &count(bits_equal(res(k, :), ref(k, :))), ' of ', SIMD_N
            call assert_true(all(bits_equal(res(k, :), ref(k, :))), 'the SIMD-group value '//trim(WHAT(k))// &
                &' equals the host''s for every thread')
        end do
    end subroutine probe_simd

    ! the host's values of the SIMD probe: lanes of 32 in threadgroups of 64, on small integers (exact sums)
    function simd_reference( x ) result(ref)
        real(real32), intent(in) :: x(:)
        real(real32), allocatable :: ref(:,:)
        integer                   :: i, loc, lane, b0
        allocate(ref(SIMD_NOUT, size(x)))
        do i = 1, size(x)
            loc       = mod(i - 1, SIMD_TG)
            lane      = mod(loc, SIMD_W)
            b0        = (i - 1) - lane
            ref(1, i) = real(lane, real32)
            ref(2, i) = real(loc / SIMD_W, real32)
            ref(3, i) = real(SIMD_W, real32)
            ref(4, i) = real(sum(real(x(b0+1:b0+SIMD_W), real64)), real32)
            ref(5, i) = minval(x(b0+1:b0+SIMD_W))
            ref(6, i) = real(sum(real(x(b0+1:b0+lane+1), real64)), real32)
            ref(7, i) = x(b0 + SIMD_W - lane)
        end do
    end function simd_reference

    ! (c) a fixed tree on values that are not integers: three runs in this process are equal bit for bit; the
    ! digest is for the comparison of invocations; the host's float32 tree in the same order is reported
    subroutine probe_tree
        type(mlx_custom_kernel)   :: kern
        real(real32), allocatable :: x(:), sums(:,:), host(:)
        integer(int64)            :: h
        integer                   :: r, st, nst, g
        x = real(seeded_uniform(GROUP_NG * TREE_TG, PROBE_SEED), real32)
        allocate(sums(GROUP_NG, NREPEAT))
        kern = mlx_custom_kernel(group_sum_spec(GROUP_NG, TREE_TG))
        nst  = 0
        do r = 1, NREPEAT
            call group_sums(kern, x, sums(:, r), st)
            if( st /= 0 ) nst = nst + 1
        end do
        call assert_true(nst == 0, 'the fixed tree''s runs are evaluated')
        if( nst > 0 ) return
        allocate(host(GROUP_NG))
        do g = 1, GROUP_NG
            host(g) = host_tree(x((g-1)*TREE_TG+1:g*TREE_TG))
        end do
        h    = DIGEST_START
        call digest_bits(h, transfer(sums(:, 1), [0_int32]))
        write(*,'(a,i0,a,i0,a,i0,a,i0,a)') '    c: fixed tree, groups of ', TREE_TG, ': runs 2 to ', NREPEAT, &
            &' equal to run 1 in ', count([(all(bits_equal(sums(:, r), sums(:, 1))), r = 2, NREPEAT)]), ' of ', &
            &NREPEAT - 1, ' (bit for bit)'
        write(*,'(a,i0,a,i0)') '       host float32 tree in the same order equal in ', &
            &count(bits_equal(sums(:, 1), host)), ' of ', GROUP_NG
        write(*,'(a,z16.16)') '    digest probe c tree ', h
        do r = 2, NREPEAT
            call assert_true(all(bits_equal(sums(:, r), sums(:, 1))), 'a fixed tree''s group sums are bit-repeatable '// &
                &'within a process')
        end do
    end subroutine probe_tree

    ! the device's tree on the host in float32: level by level, the lower half adds the upper half
    pure function host_tree( v ) result(s)
        real(real32), intent(in) :: v(:)
        real(real32)              :: s
        real(real32), allocatable :: w(:)
        integer                   :: m
        w = v
        m = size(w) / 2
        do while( m > 0 )
            w(1:m) = w(1:m) + w(m+1:2*m)
            m = m / 2
        end do
        s = w(1)
    end function host_tree

    ! (d) the largest threadgroup array that builds: doubling its size until the first refusal, which is
    ! recorded with its status and message; every size that builds must read back its indices
    subroutine probe_tgmem
        type(mlx_custom_kernel)      :: kern
        type(mlx_array), allocatable :: outs(:)
        type(mlx_array)              :: xd
        real(real32)                 :: x(TGMEM_THREADS), out(TGMEM_THREADS), ref(TGMEM_THREADS)
        integer                      :: nbytes, st, largest, t
        x       = 0._real32
        xd      = mlx_from(x)
        largest = 0
        nbytes  = TGMEM_FIRST
        do while( nbytes <= TGMEM_LAST )
            kern = mlx_custom_kernel(tgmem_probe_spec(nbytes, TGMEM_THREADS))
            call kern%apply([xd], outs, st)
            if( st == 0 ) call mlx_eval(outs(1), status=st)
            if( st == 0 ) call mlx_to(out, outs(1), status=st)
            if( st /= 0 )then
                write(*,'(a,i0,a,i0,a)') '    d: a threadgroup array of ', nbytes, ' B: refused, status ', st, ':'
                write(*,'(a)') '       '//mlx_last_error()
                exit
            endif
            ref = [(real(nbytes / 4 - t, real32), t = 1, TGMEM_THREADS)]
            write(*,'(a,i0,a,i0,a,i0)') '    d: a threadgroup array of ', nbytes, ' B: builds, values read back ', &
                &count(bits_equal(out, ref)), ' of ', TGMEM_THREADS
            call assert_true(all(bits_equal(out, ref)), 'a threadgroup array that builds reads back what its group '// &
                &'wrote')
            largest = nbytes
            nbytes  = 2 * nbytes
        end do
        write(*,'(a,i0,a)') '    d: the largest threadgroup array that builds: ', largest, ' B'
        if( largest == TGMEM_LAST ) write(*,'(a,i0,a)') '       no refusal up to ', TGMEM_LAST, ' B'
        call assert_true(largest >= TGMEM_FIRST, 'a threadgroup array of 4,096 B builds')
    end subroutine probe_tgmem

    ! n small integers from a fixed seed, in -8 .. 8: their sums are exact in float32 in any order
    function small_integers( n, seed ) result(x)
        integer, intent(in) :: n, seed
        real(real32), allocatable :: x(:)
        x = real(nint(8._real64 * seeded_uniform(n, seed)), real32)
    end function small_integers

    ! ---- suite tail --------------------------------------------------------------------------------------------

    subroutine bench_tail( mode )
        character(len=*), intent(in) :: mode
        type(tail_bench) :: b
        integer          :: seed
        seed = arg_int('seed', 1)
        write(*,'(a,i0)') '**** bench_kernel_forms suite=tail mode='//mode//' seed=', seed
        call tail_prepare(b, seed, arg_int('tiles', TAIL_TILES))
        select case( mode )
            case( 'agree' )
                call tail_agree(b, seed)
            case( 'time' )
                call time_forms(b, 1, [2, 3], TAIL_FORMS)
            case( 'part' )
                call tail_part(b, seed)
        end select
    end subroutine bench_tail

    ! the tiles of a seed on the device, the kernels of the three forms and the current tail's rows variant
    subroutine tail_prepare( b, seed, ntiles )
        type(tail_bench), intent(inout) :: b
        integer,          intent(in)    :: seed, ntiles
        type(polarft_tile_spec)   :: spec_t
        real(real32), allocatable :: raw(:,:,:), iw(:)
        real(real32)              :: par(8)
        integer                   :: t, st
        logical                   :: ok
        spec_t = polarft_tile_spec(pftsz=TAIL_PFTSZ, nk=TAIL_NK, rt=TAIL_RT, bt=TAIL_BT)
        b%kern(1) = mlx_custom_kernel(tail_spec(spec_t, .false.))
        b%kern(2) = mlx_custom_kernel(tail_simd_spec(spec_t))
        b%kern(3) = mlx_custom_kernel(tail_plain_spec(spec_t, ok))
        b%kern(4) = mlx_custom_kernel(tail_spec(spec_t, .true.))
        call assert_true(ok, 't2: the plain-sum form is derived from the current tail''s two compensated steps')
        par    = 0._real32
        par(1) = real(POLAR_DIST_MAX, real32)
        par(2) = POLAR_DIST_INVALID
        par(3) = POLAR_DIST_VALID
        par(4) = POLAR_ARG_CUTOFF
        par(5) = POLAR_DRAW_FLOOR
        b%par    = mlx_from(par)
        b%ntiles = ntiles
        allocate(b%raw(ntiles), b%iw(ntiles), b%temps(ntiles), b%u(ntiles), b%temps_h(TAIL_BT, ntiles), &
            &b%u_h(TAIL_RT, TAIL_BT, ntiles), raw(2 * TAIL_PFTSZ, TAIL_RT, TAIL_BT), iw(TAIL_BT))
        call set_fixed_seed(seed)
        do t = 1, ntiles
            call tail_tile(raw, iw, b%temps_h(:, t), b%u_h(:, :, t))
            b%raw(t)   = mlx_from(raw)
            b%iw(t)    = mlx_from(iw)
            b%temps(t) = mlx_from(b%temps_h(:, t))
            b%u(t)     = mlx_from(b%u_h(:, :, t))
            call mlx_eval(b%raw(t), status=st)
        end do
        b%tmin  = mlx_from(spread(TEMP_MINIMA, 1, TAIL_BT))
        b%uzero = mlx_from(spread(spread(0._real32, 1, TAIL_RT), 2, TAIL_BT))
        b%utwo  = mlx_from(spread(spread(2._real32, 1, TAIL_RT), 2, TAIL_BT))
        call mlx_eval(b%iw, status=st)
        call mlx_eval(b%temps, status=st)
        call mlx_eval(b%u, status=st)
    end subroutine tail_prepare

    ! one tile of seeded rows: per pair a smooth row d of distances about 1 with noise, as raw values that the
    ! tail's fma(raw, iw, 1) maps back to d; the planted cases by share of the pairs; temperatures in turn
    subroutine tail_tile( raw, iw, temps, u )
        real(real32), intent(out) :: raw(:,:,:), iw(:), temps(:), u(:,:)
        real(real64) :: v(6), d(size(raw, 1)), noise(size(raw, 1)), wsq
        integer      :: nrots, b, r, i, m
        nrots = size(raw, 1)
        do b = 1, size(raw, 3)
            call random_number(wsq)
            iw(b)    = real(1._real64 / (2._real64 * (0.5_real64 + 1.5_real64 * wsq)), real32)
            temps(b) = TEMP_LEVELS(mod(b - 1, size(TEMP_LEVELS)) + 1)
            do r = 1, size(raw, 2)
                call random_number(v)
                call random_number(noise)
                do i = 1, nrots
                    d(i) = 1._real64 - 0.3_real64 * v(1) * cos(2._real64 * PI * (real(i - 1, real64) - v(3) * nrots) / &
                        &nrots) - 0.1_real64 * v(2) * cos(4._real64 * PI * (real(i - 1, real64) - v(4) * nrots) / nrots) + &
                        &0.02_real64 * (noise(i) - 0.5_real64)
                end do
                raw(:, r, b) = real((d - 1._real64) / real(iw(b), real64), real32)
                if( v(5) < SHARE_NONE )then
                    raw(:, r, b) = RAW_INVALID
                else if( v(5) < SHARE_SOME )then
                    raw(1:nrots:7, r, b) = RAW_INVALID
                else if( v(5) < SHARE_TIE )then
                    m = minloc(raw(:, r, b), dim=1)
                    raw(mod(m - 1 + 37, nrots) + 1, r, b) = raw(m, r, b)
                else if( v(5) < SHARE_LAST )then
                    raw(nrots, r, b) = minval(raw(:, r, b)) - 0.01_real32
                endif
                u(r, b) = real(v(6), real32)
            end do
        end do
    end subroutine tail_tile

    ! form f on every tile, queued tile by tile; vset 0 the seed's temperatures and variates, 1 and 2 the
    ! temperature that leaves only the minimum with u 0 (the draw reaches the first minimum) and u 2 (no rotation
    ! reaches the target, so the form's own minimum is drawn);
    ! res holds the entries (dists, irots) of tile t at 2t - 1 and 2t, evaluated
    subroutine tail_queue( b, f, vset, res, status )
        type(tail_bench),             intent(inout) :: b
        integer,                      intent(in)    :: f
        integer,                      intent(in)    :: vset
        type(mlx_array), allocatable, intent(out)   :: res(:)
        integer,                      intent(out)   :: status
        type(mlx_array), allocatable :: outs(:)
        integer                      :: t
        allocate(res(2 * b%ntiles))
        do t = 1, b%ntiles
            if( vset == 1 )then
                call b%kern(f)%apply([b%raw(t), b%iw(t), b%tmin, b%uzero, b%par], outs, status)
            else if( vset == 2 )then
                call b%kern(f)%apply([b%raw(t), b%iw(t), b%tmin, b%utwo, b%par], outs, status)
            else
                call b%kern(f)%apply([b%raw(t), b%iw(t), b%temps(t), b%u(t), b%par], outs, status)
            endif
            if( status /= 0 ) return
            res(2*t-1) = outs(1)
            res(2*t)   = outs(2)
            call mlx_async_eval(outs(1:2), status=status)
            if( status /= 0 ) return
        end do
        call mlx_eval(res, status=status)
    end subroutine tail_queue

    function tail_seconds( self, f ) result(sec)
        class(tail_bench), intent(inout) :: self
        integer,           intent(in)    :: f
        real(real64)                 :: sec, t0
        type(mlx_array), allocatable :: res(:)
        integer                      :: st
        call mlx_synchronize()
        t0 = clock_s()
        call tail_queue(self, f, 0, res, st)
        sec = clock_s() - t0
        if( st /= 0 ) sec = -1._real64
    end function tail_seconds

    ! the entries of form f on the host, (rt, bt, tiles)
    subroutine tail_entries( b, f, vset, dists, irots )
        type(tail_bench),          intent(inout) :: b
        integer,                   intent(in)    :: f
        integer,                   intent(in)    :: vset
        real(real32), allocatable, intent(out)   :: dists(:,:,:)
        integer,      allocatable, intent(out)   :: irots(:,:,:)
        type(mlx_array), allocatable :: res(:)
        integer                      :: t, st
        allocate(dists(TAIL_RT, TAIL_BT, b%ntiles), irots(TAIL_RT, TAIL_BT, b%ntiles))
        call tail_queue(b, f, vset, res, st)
        call assert_true(st == 0, trim(TAIL_FORMS(f))//': every tile is evaluated')
        if( st /= 0 ) write(*,'(a)') '    '//mlx_last_error()
        do t = 1, b%ntiles
            if( st == 0 ) call mlx_to(dists(:, :, t), res(2*t-1), status=st)
            if( st == 0 ) call mlx_to(irots(:, :, t), res(2*t), status=st)
        end do
    end subroutine tail_entries

    ! decision 5 for the tail: each form repeatable; its first minima exact against the host's on the rows of the
    ! current tail's rows variant, by the draw (u 0) and by the form's own minimum (u 2);
    ! its draws held to its own rows by the oracle's rule; the alternatives against
    ! the current form: drawn rotations differing in at most POLARFT_TAIL_ROT_BLK pairs a block of 64,000, and
    ! equal distances where the rotations agree
    subroutine tail_agree( b, seed )
        type(tail_bench), intent(inout) :: b
        integer,          intent(in)    :: seed
        type(polar_table_entries)    :: ent
        real(real32),    allocatable :: d(:,:,:,:), dm(:,:,:,:,:), d2(:,:,:), dr(:,:,:), rows(:,:)
        integer,         allocatable :: ir(:,:,:,:), irm(:,:,:,:,:), ir2(:,:,:), irr(:,:,:), nblk(:)
        integer(int64)               :: h
        type(mlx_array), allocatable :: outs(:)
        integer                      :: f, r, t, ib, jr, jb, st, imin, nmin(3), ndraw(3), nrep(3), ndist(3), nrowv, m
        real(real64)                 :: row(2 * TAIL_PFTSZ)
        integer                      :: shp(3)
        ! a shape known only at run time keeps reshape's temporary off the stack
        shp = [2 * TAIL_PFTSZ, TAIL_RT, TAIL_BT]
        allocate(d(TAIL_RT, TAIL_BT, b%ntiles, 3), ir(TAIL_RT, TAIL_BT, b%ntiles, 3), dm(TAIL_RT, TAIL_BT, b%ntiles, 3, 2), &
            &irm(TAIL_RT, TAIL_BT, b%ntiles, 3, 2), dr(TAIL_RT, TAIL_BT, b%ntiles), irr(TAIL_RT, TAIL_BT, b%ntiles), &
            &rows(2 * TAIL_PFTSZ, TAIL_RT * TAIL_BT))
        nrep = 0
        do f = 1, 3
            call tail_entries(b, f, 0, d2, ir2)
            d(:, :, :, f)  = d2
            ir(:, :, :, f) = ir2
            do r = 2, NREPEAT
                call tail_entries(b, f, 0, d2, ir2)
                if( .not. (all(bits_equal(d2, d(:, :, :, f))) .and. all(ir2 == ir(:, :, :, f))) ) nrep(f) = nrep(f) + 1
            end do
            do m = 1, 2
                call tail_entries(b, f, m, d2, ir2)
                dm(:, :, :, f, m)  = d2
                irm(:, :, :, f, m) = ir2
            end do
            h = DIGEST_START
            call digest_bits(h, transfer(d(:, :, :, f), [0_int32]))
            call digest_bits(h, int(reshape(ir(:, :, :, f), [size(ir2)]), int32))
            write(*,'(a,i0,a,z16.16)') '    digest tail '//trim(TAIL_FORMS(f))//' seed=', seed, ' ', h
        end do
        ! the rows of every tile from the current tail's rows variant; the minima and the draws on them
        nmin  = 0
        ndraw = 0
        nrowv = 0
        do t = 1, b%ntiles
            call b%kern(4)%apply([b%raw(t), b%iw(t), b%temps(t), b%u(t), b%par], outs, st)
            if( st == 0 ) call mlx_eval(outs, status=st)
            if( st == 0 ) call mlx_to(dr(:, :, t), outs(1), status=st)
            if( st == 0 ) call mlx_to(irr(:, :, t), outs(2), status=st)
            if( st == 0 ) call mlx_to(rows, outs(3), status=st)
            if( st /= 0 ) nrowv = nrowv + 1
            ent%rows = reshape(rows, shp)
            do f = 1, 3
                ent%dists = d(:, :, t, f)
                ent%irots = ir(:, :, t, f)
                ndraw(f)  = ndraw(f) + polar_draws_off(ent, b%temps_h(:, t), b%u_h(:, :, t))
                do jb = 1, TAIL_BT
                    do jr = 1, TAIL_RT
                        row  = real(ent%rows(:, jr, jb), real64)
                        imin = polar_first_min(row)
                        do m = 1, 2
                            if( imin == 0 )then
                                if( irm(jr, jb, t, f, m) /= 1 .or. &
                                    &.not. bits_equal(dm(jr, jb, t, f, m), POLAR_DIST_INVALID) ) nmin(f) = nmin(f) + 1
                            else if( irm(jr, jb, t, f, m) /= imin .or. &
                                &.not. bits_equal(dm(jr, jb, t, f, m), ent%rows(imin, jr, jb)) )then
                                nmin(f) = nmin(f) + 1
                            endif
                        end do
                    end do
                end do
            end do
        end do
        call assert_true(nrowv == 0 .and. all(bits_equal(dr, d(:, :, :, 1))) .and. all(irr == ir(:, :, :, 1)), &
            &'t0: the rows variant gives the current tail''s entries')
        allocate(nblk(b%ntiles / TAIL_BLOCK))
        ndist = 0
        do f = 1, 3
            do ib = 1, size(nblk)
                nblk(ib) = count(ir(:, :, (ib-1)*TAIL_BLOCK+1:ib*TAIL_BLOCK, f) /= ir(:, :, (ib-1)*TAIL_BLOCK+1:ib*TAIL_BLOCK, 1))
            end do
            ndist(f) = count(ir(:, :, :, f) == ir(:, :, :, 1) .and. .not. bits_equal(d(:, :, :, f), d(:, :, :, 1)))
            write(*,'(a,i0,a,i0,a,i0,a,i0,a,i0,a,i0)') '    '//trim(TAIL_FORMS(f))//': repeats differing ', nrep(f), &
                &'; first minima off ', nmin(f), '; draws off its rows ', ndraw(f), '; rotations against t0 ', &
                &sum(nblk), ' (largest block ', maxval(nblk), '); distances off where they agree ', ndist(f)
            call assert_true(nrep(f) == 0, trim(TAIL_FORMS(f))//': the entries are bit-repeatable in a process')
            call assert_true(nmin(f) == 0, trim(TAIL_FORMS(f))//': the first minima equal the host''s on the rows')
            call assert_true(ndraw(f) == 0, trim(TAIL_FORMS(f))//': every draw holds on the form''s own rows')
            call assert_true(maxval(nblk) <= POLARFT_TAIL_ROT_BLK, trim(TAIL_FORMS(f))//': the drawn rotations '// &
                &'differ from t0''s in at most POLARFT_TAIL_ROT_BLK pairs of every 64,000')
            call assert_true(ndist(f) == 0, trim(TAIL_FORMS(f))//': where the rotations agree the distances are t0''s')
        end do
    end subroutine tail_agree

    ! one process of a split (scripts/run_parts.sh): the tiles made, a warm-up, then go and passes evaluations of
    ! the form; a row of ./bench_kernel_forms.tsv with the rate in column 20, the pairs in 21, MLX's peak and cache
    ! in 26 and 27 and the median pass in 30
    subroutine tail_part( b, seed )
        type(tail_bench), intent(inout) :: b
        integer,          intent(in)    :: seed
        character(len=:), allocatable :: form
        real(real64),     allocatable :: t(:)
        character(len=24)             :: cols(30)
        real(real64)                  :: w, pairs, peak, cache
        integer                       :: f, p, npass, u
        logical                       :: l_old
        form  = arg_choice('form', TAIL_FORMS)
        f     = findloc(TAIL_FORMS, form, dim=1)
        npass = arg_int('passes', TAIL_PASSES)
        pairs = real(TAIL_RT, real64) * TAIL_BT * b%ntiles
        allocate(t(npass))
        w = b%seconds(f)
        write(*,'(a,i0,a,i0)') '    part ', arg_int('part', 1), ' of ', arg_int('nparts', 1)
        call mlx_reset_peak_memory()
        if( len_trim(arg_str('go', '')) > 0 ) call wait_for_go_file(arg_str('go', ''), arg_int('part', 1), &
            &'bench_kernel_forms')
        do p = 1, npass
            t(p) = b%seconds(f)
        end do
        peak  = real(mlx_peak_memory(), real64)
        cache = real(mlx_cache_memory(), real64)
        write(*,'(a,i0,a,es11.4,a,es11.4,a)') '    passes ', npass, ', best ', minval(t), ' s, median ', median(t), ' s'
        cols     = '-'
        cols(1)  = 'tail'
        cols(2)  = form
        cols(3)  = int_str(seed)
        cols(4)  = int_str(b%ntiles)
        cols(5)  = int_str(arg_int('nparts', 1))
        cols(6)  = int_str(arg_int('part', 1))
        cols(7)  = int_str(npass)
        cols(10) = es_str(minval(t))
        cols(20) = es_str(pairs / minval(t))
        cols(21) = es_str(pairs)
        cols(26) = es_str(peak)
        cols(27) = es_str(cache)
        cols(30) = es_str(median(t))
        inquire(file='bench_kernel_forms.tsv', exist=l_old)
        open(newunit=u, file='bench_kernel_forms.tsv', position='append', action='write')
        if( .not. l_old )then
            write(u,'(*(a))') 'suite', achar(9), 'form', achar(9), 'seed', achar(9), 'tiles', achar(9), 'nparts', achar(9), &
                &'part', achar(9), 'passes', (achar(9)//'-', p = 8, 9), achar(9), 'best_s', (achar(9)//'-', p = 11, 19), &
                &achar(9), 'pairs_per_s', achar(9), 'pairs', (achar(9)//'-', p = 22, 25), achar(9), 'mlx_peak_B', achar(9), &
                &'mlx_cache_B', (achar(9)//'-', p = 28, 29), achar(9), 'median_s'
        endif
        write(u,'(*(a))') trim(cols(1)), (achar(9)//trim(cols(p)), p = 2, size(cols))
        close(u)
    end subroutine tail_part

    function int_str( i ) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16)             :: buf
        write(buf, '(i0)') i
        s = trim(buf)
    end function int_str

    function es_str( x ) result(s)
        real(real64), intent(in) :: x
        character(len=:), allocatable :: s
        character(len=24)             :: buf
        write(buf, '(es13.6)') x
        s = trim(adjustl(buf))
    end function es_str

    ! ---- suite reduce ------------------------------------------------------------------------------------------

    subroutine bench_reduce( mode )
        character(len=*), intent(in) :: mode
        type(reduce_bench)        :: b
        real(real32), allocatable :: x(:,:), y(:,:)
        integer                   :: seed, f, nt, ne, ns
        seed = arg_int('seed', 1)
        write(*,'(a,i0)') '**** bench_kernel_forms suite=reduce mode='//mode//' seed=', seed
        ! sizes held in variables keep the operands' temporaries off the stack
        nt = RED_NT
        ne = RED_NE
        ns = RED_NS
        allocate(x(nt, ne), y(ns, nt))
        x = reshape(real(seeded_uniform(nt * ne, seed), real32), [nt, ne])
        y = reshape(real(seeded_uniform(ns * nt, seed + 1000), real32), [ns, nt])
        x(RED_NREAL+1:, :) = 0._real32
        b%x  = mlx_from(x)
        b%y  = mlx_from(y)
        b%yt = mlx_from(transpose(y))
        do f = 1, 3
            b%kern(f) = mlx_custom_kernel(reduce_spec(f - 1, RED_NE, RED_NS, RED_TG))
        end do
        select case( mode )
            case( 'agree' )
                call reduce_agree(b, x, y, seed)
            case( 'time' )
                call time_forms(b, 1, [2, 3, 4], RED_FORMS)
                call time_forms(b, 4, [3], RED_FORMS)
        end select
    end subroutine bench_reduce

    ! the sums of form f (1 to 3 kernels, 4 the graph: the products, then sum over the terms), evaluated
    subroutine reduce_run( b, f, s, status )
        type(reduce_bench), intent(inout) :: b
        integer,            intent(in)    :: f
        type(mlx_array),    intent(out)   :: s
        integer,            intent(out)   :: status
        type(mlx_array), allocatable :: outs(:)
        type(mlx_array)              :: x3, y3
        if( f <= 3 )then
            call b%kern(f)%apply([b%x, b%y], outs, status)
            if( status /= 0 ) return
            s = outs(1)
        else
            x3 = reshape(b%x, [RED_NT, 1, RED_NE])
            y3 = reshape(b%yt, [RED_NT, RED_NS, 1])
            s  = sum(x3 * y3, dim=1)
        endif
        call mlx_eval(s, status=status)
    end subroutine reduce_run

    function reduce_seconds( self, f ) result(sec)
        class(reduce_bench), intent(inout) :: self
        integer,             intent(in)    :: f
        real(real64)    :: sec, t0
        type(mlx_array) :: s
        integer         :: st
        call mlx_synchronize()
        t0 = clock_s()
        call reduce_run(self, f, s, st)
        sec = clock_s() - t0
        if( st /= 0 ) sec = -1._real64
    end function reduce_seconds

    ! decision 5 for the reduction: each form bit-repeatable in a process; its largest error against the host's
    ! double sum relative to the sum of |terms| within FORMS_REDUCE_TOL (calibrated on seed 1)
    subroutine reduce_agree( b, x, y, seed )
        type(reduce_bench), intent(inout) :: b
        real(real32),       intent(in)    :: x(:,:), y(:,:)
        integer,            intent(in)    :: seed
        real(real64), allocatable :: sd(:,:), sa(:,:)
        real(real32), allocatable :: s1(:,:), s2(:,:)
        real(real64)              :: err(4)
        type(mlx_array)           :: s
        integer(int64)            :: h
        integer                   :: f, r, e, k, st, nrep
        allocate(sd(RED_NS, RED_NE), sa(RED_NS, RED_NE), s1(RED_NS, RED_NE), s2(RED_NS, RED_NE))
        err = 0._real64
        do e = 1, RED_NE
            do k = 1, RED_NS
                sd(k, e) = sum(real(x(:, e), real64) * real(y(k, :), real64))
                sa(k, e) = sum(abs(real(x(:, e), real64) * real(y(k, :), real64)))
            end do
        end do
        do f = 1, 4
            call reduce_run(b, f, s, st)
            if( st == 0 ) call mlx_to(s1, s, status=st)
            call assert_true(st == 0, trim(RED_FORMS(f))//': the sums are evaluated')
            if( st /= 0 )then
                write(*,'(a)') '    '//mlx_last_error()
                cycle
            endif
            nrep = 0
            do r = 2, NREPEAT
                call reduce_run(b, f, s, st)
                if( st == 0 ) call mlx_to(s2, s, status=st)
                if( st /= 0 .or. .not. all(bits_equal(s1, s2)) ) nrep = nrep + 1
            end do
            err(f) = nan_maxval(abs(real(s1, real64) - sd) / sa)
            h = DIGEST_START
            call digest_bits(h, transfer(s1, [0_int32]))
            write(*,'(a,i0,a,es23.16,a,z16.16)') '    '//trim(RED_FORMS(f))//': repeats differing ', nrep, &
                &'; largest error over the sum of |terms| ', err(f), '; digest ', h
            write(*,'(a,i0,a,z16.16)') '    digest reduce '//trim(RED_FORMS(f))//' seed=', seed, ' ', h
            call assert_true(nrep == 0, trim(RED_FORMS(f))//': the sums are bit-repeatable in a process')
            call assert_true(err(f) <= FORMS_REDUCE_TOL, trim(RED_FORMS(f))//': the sums are the host''s double '// &
                &'sums within FORMS_REDUCE_TOL of the sum of |terms|')
        end do
        write(*,'(a,es23.16,a,es12.5)') '    largest error of r0 to r3 ', maxval(err), '; r1 over r0 ', err(2) / err(1)
    end subroutine reduce_agree

    ! ---- suite sizes -------------------------------------------------------------------------------------------

    subroutine bench_sizes( mode )
        character(len=*), intent(in) :: mode
        type(sizes_bench) :: b
        integer           :: seed
        seed = arg_int('seed', 1)
        write(*,'(a,i0)') '**** bench_kernel_forms suite=sizes mode='//mode//' seed=', seed
        if( mode == 'compile' )then
            call sizes_compile(arg_choice('form', G_FORMS), arg_int('set', 1), seed)
            return
        endif
        call sizes_prepare(b, seed)
        select case( mode )
            case( 'agree' )
                call sizes_agree(b, seed)
            case( 'time' )
                call time_forms(b, 1, [2], SIZE_FORMS)
                call time_forms(b, 3, [4], SIZE_FORMS)
        end select
    end subroutine bench_sizes

    ! the polar points (2, npts) of the gather: shells kfrom .. kfrom + nk - 1 at pftsz angles of the half plane,
    ! scaled by the padding; and tn seeded rotation rows (2, 3, tn), the first two rows of uniform rotations
    subroutine gather_points( hk, rot, tn )
        real(real32), allocatable, intent(out) :: hk(:,:), rot(:,:,:)
        integer,                   intent(in)  :: tn
        real(real64) :: quat(4), r(3, 3), ang
        integer      :: k, i, d
        allocate(hk(2, SZ_PFTSZ * SZ_NK), rot(2, 3, tn))
        do k = 1, SZ_NK
            do i = 1, SZ_PFTSZ
                ang = real(i - 1, real64) * PI / real(SZ_PFTSZ, real64)
                hk(:, (k-1)*SZ_PFTSZ+i) = real(real(OSMPL_PAD_FAC * (SZ_KFROM + k - 1), real64) * [cos(ang), &
                    &sin(ang)], real32)
            end do
        end do
        do d = 1, tn
            call random_number(quat)
            quat = quat - 0.5_real64
            quat = quat / sqrt(sum(quat**2))
            r(1, :) = [1._real64 - 2._real64 * (quat(3)**2 + quat(4)**2), 2._real64 * (quat(2)*quat(3) - quat(1)*quat(4)), &
                &2._real64 * (quat(2)*quat(4) + quat(1)*quat(3))]
            r(2, :) = [2._real64 * (quat(2)*quat(3) + quat(1)*quat(4)), 1._real64 - 2._real64 * (quat(2)**2 + quat(4)**2), &
                &2._real64 * (quat(3)*quat(4) - quat(1)*quat(2))]
            rot(:, :, d) = real(r(1:2, :), real32)
        end do
    end subroutine gather_points

    ! a seeded cube of (m + 5)**3 complex values in -1 .. 1, one parity
    function gather_cube( m ) result(a)
        integer, intent(in) :: m
        type(mlx_array)              :: a
        complex(real32), allocatable :: c(:,:,:)
        real(real64),    allocatable :: re(:,:,:), im(:,:,:)
        integer                      :: e
        e = m + 5
        allocate(re(e, e, e), im(e, e, e))
        call random_number(re)
        call random_number(im)
        c = cmplx(2._real64 * re - 1._real64, 2._real64 * im - 1._real64, kind=real32)
        a = mlx_from(c)
    end function gather_cube

    ! the kernels with sizes as templates (the toys' specs) and in an input, and their inputs
    subroutine sizes_prepare( b, seed )
        type(sizes_bench), intent(inout) :: b
        integer,           intent(in)    :: seed
        type(mlx_custom_kernel_spec) :: g0, i0
        type(probe_case)             :: cs
        real(real32), allocatable    :: hk(:,:), rot(:,:,:)
        integer                      :: p, st
        call set_fixed_seed(seed)
        call gather_points(hk, rot, SZ_TN)
        b%hk   = mlx_from(hk)
        b%rot  = mlx_from(rot)
        b%coef = mlx_from(window_coefficients())
        do p = 1, 2
            b%cube(p) = gather_cube(SZ_M)
        end do
        g0 = gather_spec(SZ_M, size(hk, 2), SZ_TN, SZ_TG)
        b%szg     = mlx_from(int(g0%template_ints, int32))
        b%kern(1) = mlx_custom_kernel(g0)
        b%kern(2) = mlx_custom_kernel(sizes_in_input(g0))
        cs = seeded_case('sizes n=64', SZ_N, SZ_PLANES, .false.)
        i0 = probe_spec(cs, SZ_PLANES, .true.)
        b%szi     = mlx_from(int(i0%template_ints, int32))
        b%kern(3) = mlx_custom_kernel(i0)
        b%kern(4) = mlx_custom_kernel(sizes_in_input(i0))
        b%ihk   = mlx_from(cs%hk)
        b%irot  = mlx_from(cs%rot)
        b%iom   = mlx_from(cs%omega)
        b%ic    = mlx_from(cs%c)
        b%iq    = mlx_from(cs%q)
        b%icoef = mlx_from(window_coefficients())
        call mlx_eval(b%cube, status=st)
    end subroutine sizes_prepare

    ! form f's outputs, evaluated: the gather's two parities, or the insertion's numerator and density
    subroutine sizes_run( b, f, res, status )
        type(sizes_bench),            intent(inout) :: b
        integer,                      intent(in)    :: f
        type(mlx_array), allocatable, intent(out)   :: res(:)
        integer,                      intent(out)   :: status
        type(mlx_array), allocatable :: outs(:)
        integer                      :: p
        allocate(res(2))
        status = 0
        select case( f )
            case( 1, 2 )
                do p = 1, 2
                    if( f == 1 )then
                        call b%kern(1)%apply([b%cube(p), b%hk, b%rot, b%coef], outs, status)
                    else
                        call b%kern(2)%apply([b%cube(p), b%hk, b%rot, b%coef, b%szg], outs, status)
                    endif
                    if( status /= 0 ) return
                    res(p) = outs(1)
                end do
            case( 3, 4 )
                if( f == 3 )then
                    call b%kern(3)%apply([b%ihk, b%irot, b%iom, b%ic, b%iq, b%icoef], outs, status)
                else
                    call b%kern(4)%apply([b%ihk, b%irot, b%iom, b%ic, b%iq, b%icoef, b%szi], outs, status)
                endif
                if( status /= 0 ) return
                res(1) = outs(1)
                res(2) = outs(2)
        end select
        call mlx_eval(res, status=status)
    end subroutine sizes_run

    function sizes_seconds( self, f ) result(sec)
        class(sizes_bench), intent(inout) :: self
        integer,            intent(in)    :: f
        real(real64)                 :: sec, t0
        type(mlx_array), allocatable :: res(:)
        integer                      :: st
        call mlx_synchronize()
        t0 = clock_s()
        call sizes_run(self, f, res, st)
        sec = clock_s() - t0
        if( st /= 0 ) sec = -1._real64
    end function sizes_seconds

    ! the gather's samples (npts, tn, 2) or the insertion's numerator and density (3, nvox) on the host
    subroutine sizes_fetch( b, f, g, x )
        type(sizes_bench),            intent(inout) :: b
        integer,                      intent(in)    :: f
        complex(real32), allocatable, intent(out)   :: g(:,:,:)
        real(real32),    allocatable, intent(out)   :: x(:,:)
        type(mlx_array), allocatable :: res(:)
        integer,         allocatable :: shp(:)
        integer                      :: st, p
        call sizes_run(b, f, res, st)
        call assert_true(st == 0, trim(SIZE_FORMS(f))//': the outputs are evaluated')
        if( st /= 0 ) return
        if( f <= 2 )then
            shp = res(1)%shape()
            allocate(g(shp(1), shp(2), 2))
            do p = 1, 2
                call mlx_to(g(:, :, p), res(p), status=st)
            end do
        else
            shp = res(2)%shape()
            allocate(x(3, shp(1)))
            call mlx_to(x(1:2, :), res(1), status=st)
            call mlx_to(x(3, :), res(2), status=st)
        endif
    end subroutine sizes_fetch

    ! decision 5 for the sizes: the gather with sizes in an input equals the template form bit for bit on both
    ! parities; the insertion likewise on the collision-free plane, where its atomics are exact; on the batch of
    ! 500 planes, whose atomic sums change between runs, the difference is reported beside the form's own spread
    subroutine sizes_agree( b, seed )
        type(sizes_bench), intent(inout) :: b
        integer,           intent(in)    :: seed
        complex(real32), allocatable :: g0(:,:,:), g1(:,:,:), gr(:,:,:)
        real(real32),    allocatable :: x0(:,:), x1(:,:), xr(:,:), dummy(:,:)
        complex(real32), allocatable :: cdummy(:,:,:)
        integer(int64)               :: h
        integer                      :: r, nrep
        call sizes_fetch(b, 1, g0, dummy)
        call sizes_fetch(b, 2, g1, dummy)
        nrep = 0
        do r = 2, NREPEAT
            call sizes_fetch(b, 1, gr, dummy)
            if( .not. all(bits_equal(gr, g0)) ) nrep = nrep + 1
            call sizes_fetch(b, 2, gr, dummy)
            if( .not. all(bits_equal(gr, g1)) ) nrep = nrep + 1
        end do
        h = DIGEST_START
        call digest_bits(h, transfer(g0, [0_int32]))
        write(*,'(a,i0,a,i0,a,i0,a,z16.16)') '    gather: samples differing g1 against g0 ', &
            &count(.not. bits_equal(g1, g0)), ' of ', size(g0), '; repeats differing ', nrep, '; digest ', h
        write(*,'(a,i0,a,z16.16)') '    digest sizes gather seed=', seed, ' ', h
        call assert_true(all(bits_equal(g1, g0)), 'gather: sizes in an input give the template form''s samples, '// &
            &'bit for bit')
        call assert_true(nrep == 0, 'gather: both forms are bit-repeatable in a process')
        call sizes_sparse(b)
        call sizes_fetch(b, 3, cdummy, x0)
        call sizes_fetch(b, 3, cdummy, xr)
        call sizes_fetch(b, 4, cdummy, x1)
        write(*,'(a,i0,a,es10.3,a,i0,a,es10.3,a)') '    insertion, 500 planes (atomic, reported): g0 against g0 ', &
            &count(.not. bits_equal(xr, x0)), ' values differ, largest ', nan_maxval(abs(xr - x0)) / &
            &nan_maxval(abs(x0)), '; g1 against g0 ', count(.not. bits_equal(x1, x0)), ', largest ', &
            &nan_maxval(abs(x1 - x0)) / nan_maxval(abs(x0)), ' (of the largest value)'
    end subroutine sizes_agree

    ! the insertion on one plane whose data sit on pixels SZ_SPARSE apart: no voxel gets two deposits, so the atomic
    ! kernel is exact; both forms built for this batch of one, compared bit for bit and over repeats
    subroutine sizes_sparse( b )
        type(sizes_bench), intent(inout) :: b
        type(probe_case)             :: cs
        type(mlx_custom_kernel_spec) :: i0
        type(mlx_custom_kernel)      :: k0, k1
        type(mlx_array), allocatable :: outs(:)
        type(mlx_array)              :: hk, rot, om, c, q, sz
        real(real32),    allocatable :: x(:,:,:)
        integer                      :: i, r, st, nvox, ndep
        cs = seeded_case('sizes sparse n=64', SZ_N, 1, .false.)
        do i = 1, cs%npix
            if( mod(nint(cs%hk(1, i)), SZ_SPARSE) /= 0 .or. mod(nint(cs%hk(2, i)), SZ_SPARSE) /= 0 )then
                cs%c(i, :) = (0._real32, 0._real32)
                cs%q(i, :) = 0._real32
            endif
        end do
        i0   = probe_spec(cs, 1, .true.)
        nvox = i0%output_shapes(3)
        k0   = mlx_custom_kernel(i0)
        k1   = mlx_custom_kernel(sizes_in_input(i0))
        hk   = mlx_from(cs%hk)
        rot  = mlx_from(cs%rot)
        om   = mlx_from(cs%omega)
        c    = mlx_from(cs%c)
        q    = mlx_from(cs%q)
        sz   = mlx_from(int(i0%template_ints, int32))
        allocate(x(3, nvox, 3))
        do r = 1, 3
            if( r < 3 )then
                call k0%apply([hk, rot, om, c, q, b%icoef], outs, st)
            else
                call k1%apply([hk, rot, om, c, q, b%icoef, sz], outs, st)
            endif
            if( st == 0 ) call mlx_eval(outs, status=st)
            if( st == 0 ) call mlx_to(x(1:2, :, r), outs(1), status=st)
            if( st == 0 ) call mlx_to(x(3, :, r), outs(2), status=st)
            call assert_true(st == 0, 'insertion, collision-free plane: evaluated')
        end do
        ndep = count(abs(x(3, :, 1)) > 0._real32)
        write(*,'(a,i0,a,i0,a,i0)') '    insertion, collision-free plane: voxels reached ', ndep, '; g0 repeat '// &
            &'differing ', count(.not. bits_equal(x(:, :, 2), x(:, :, 1))), '; g1 against g0 differing ', &
            &count(.not. bits_equal(x(:, :, 3), x(:, :, 1)))
        call assert_true(ndep > 0 .and. all(bits_equal(x(:, :, 2), x(:, :, 1))), 'insertion, collision-free plane: '// &
            &'the template form is repeatable')
        call assert_true(all(bits_equal(x(:, :, 3), x(:, :, 1))), 'insertion, collision-free plane: sizes in an '// &
            &'input give the template form''s deposits, bit for bit')
    end subroutine sizes_sparse

    ! the first evaluation of each of SZ_NCOMP new values of npts in this process (the shells dropped in eights,
    ! set by set), then a second evaluation of the same object: the first less the second is what a new value costs
    subroutine sizes_compile( form, set, seed )
        character(len=*), intent(in) :: form
        integer,          intent(in) :: set, seed
        type(mlx_custom_kernel_spec) :: spec
        type(mlx_custom_kernel)      :: kern
        type(mlx_array), allocatable :: outs(:)
        type(mlx_array)              :: cube, hkd, rotd, coef, sz
        real(real32),    allocatable :: hk(:,:), rot(:,:,:)
        real(real64)                 :: t0, first(SZ_NCOMP), warm(SZ_NCOMP)
        integer                      :: j, npts, st
        call set_fixed_seed(seed)
        call gather_points(hk, rot, SZ_TN)
        cube = gather_cube(SZ_M)
        rotd = mlx_from(rot)
        coef = mlx_from(window_coefficients())
        call mlx_eval(cube, status=st)
        do j = 1, SZ_NCOMP
            npts = SZ_PFTSZ * (SZ_NK - j - SZ_NCOMP * (set - 1))
            hkd  = mlx_from(hk(:, 1:npts))
            spec = gather_spec(SZ_M, npts, SZ_TN, SZ_TG)
            sz   = mlx_from(int(spec%template_ints, int32))
            if( form == 'g1' ) spec = sizes_in_input(spec)
            kern = mlx_custom_kernel(spec)
            call mlx_eval(hkd, status=st)
            call mlx_eval(sz, status=st)
            call mlx_synchronize()
            t0 = clock_s()
            call compile_apply(kern, form, [cube, hkd, rotd, coef, sz], outs, st)
            first(j) = clock_s() - t0
            call mlx_synchronize()
            t0 = clock_s()
            call compile_apply(kern, form, [cube, hkd, rotd, coef, sz], outs, st)
            warm(j) = clock_s() - t0
            write(*,'(a,i0,a,f10.4,a,f10.4,a,f10.4,a)') '    '//form//' npts ', npts, ': first ', 1.e3_real64 * first(j), &
                &' ms, second ', 1.e3_real64 * warm(j), ' ms, new value ', 1.e3_real64 * (first(j) - warm(j)), ' ms'
            call assert_true(st == 0, form//': the gather of every new npts is evaluated')
        end do
        write(*,'(a,i0,a,f10.4,a,f10.4,a)') '    '//form//' set ', set, ': the first value costs ', &
            &1.e3_real64 * (first(1) - warm(1)), ' ms; the median of the next seven ', &
            &1.e3_real64 * median(first(2:) - warm(2:)), ' ms'
    end subroutine sizes_compile

    ! the gather of one launch: the template form takes the first four inputs, the input form all five
    subroutine compile_apply( kern, form, inputs, outs, status )
        type(mlx_custom_kernel), intent(in)               :: kern
        character(len=*),        intent(in)               :: form
        type(mlx_array),         intent(in)               :: inputs(:)
        type(mlx_array),         allocatable, intent(out) :: outs(:)
        integer,                 intent(out)              :: status
        if( form == 'g1' )then
            call kern%apply(inputs, outs, status)
        else
            call kern%apply(inputs(1:4), outs, status)
        endif
        if( status == 0 ) call mlx_eval(outs, status=status)
    end subroutine compile_apply

    ! ---- suite select ------------------------------------------------------------------------------------------

    subroutine bench_select( mode )
        character(len=*), intent(in) :: mode
        type(select_bench)        :: b
        real(real32), allocatable :: base(:,:), tab(:,:)
        integer                   :: seed, ik
        seed = arg_int('seed', 1)
        write(*,'(a,i0)') '**** bench_kernel_forms suite=select mode='//mode//' seed=', seed
        base   = select_table(seed)
        b%low  = mlx_full([1, SEL_NPART], SEL_SENTRY)
        b%high = mlx_full([1, SEL_NPART], huge(1._real32))
        do ik = 1, size(SEL_KS)
            b%k     = SEL_KS(ik)
            tab     = base
            call plant_ties(tab, b%k, seed)
            b%tabd     = mlx_from(tab)
            b%tneg  = -b%tabd
            b%kern(1) = mlx_custom_kernel(select_spec(.false., SEL_NPART, b%k))
            b%kern(2) = mlx_custom_kernel(select_spec(.true., SEL_NPART, b%k))
            write(*,'(a,i0)') '    K = ', b%k
            select case( mode )
                case( 'agree' )
                    call select_agree(b, tab, seed)
                case( 'time' )
                    call time_forms(b, 1, [2, 3, 4], SEL_FORMS)
                    call time_forms(b, 3, [4], SEL_FORMS)
            end select
        end do
    end subroutine bench_select

    ! the seeded table (nref, npart), uniform in 0 .. 1, rounded once to float32
    function select_table( seed ) result(tab)
        integer, intent(in) :: seed
        real(real32), allocatable :: tab(:,:)
        real(real64), allocatable :: u(:,:)
        allocate(u(SEL_NREF, SEL_NPART))
        call set_fixed_seed(seed)
        call random_number(u)
        tab = real(u, real32)
    end function select_table

    ! in SEL_SHARE of the columns (seeded): a second reference equal to the first maximum, then one outside the K
    ! best equal to the K-th
    subroutine plant_ties( tab, k, seed )
        real(real32), intent(inout) :: tab(:,:)
        integer,      intent(in)    :: k, seed
        real(real64) :: u(3)
        integer      :: p, r, im
        integer      :: idx(k)
        real(real32) :: val(k)
        call set_fixed_seed(seed + 100)
        do p = 1, size(tab, 2)
            call random_number(u)
            if( u(1) >= SEL_SHARE ) cycle
            im = maxloc(tab(:, p), dim=1)
            r  = 1 + int(u(2) * size(tab, 1))
            if( r == im ) r = mod(r, size(tab, 1)) + 1
            tab(r, p) = tab(im, p)
            call host_best(tab(:, p), idx, val)
            r = 1 + int(u(3) * size(tab, 1))
            do while( any(idx == r) )
                r = mod(r, size(tab, 1)) + 1
            end do
            tab(r, p) = val(k)
        end do
    end subroutine plant_ties

    ! the host's first-maximum rule: k rounds of the first maximum, each taken out
    pure subroutine host_best( col, idx, val )
        real(real32), intent(in)  :: col(:)
        integer,      intent(out) :: idx(:)
        real(real32), intent(out) :: val(:)
        real(real32) :: w(size(col))
        integer      :: j
        w = col
        do j = 1, size(idx)
            idx(j) = maxloc(w, dim=1)
            val(j) = w(idx(j))
            w(idx(j)) = SEL_SENTRY
        end do
    end subroutine host_best

    ! the K best of every column by form f: (idx, val), (K, npart), evaluated
    subroutine select_run( b, f, idx, val, status )
        type(select_bench), intent(inout) :: b
        integer,            intent(in)    :: f
        type(mlx_array),    intent(out)   :: idx, val
        integer,            intent(out)   :: status
        type(mlx_array), allocatable :: outs(:), ids(:), vls(:)
        type(mlx_array)              :: work, res(2)
        integer                      :: j
        status = 0
        select case( f )
            case( 1 )
                allocate(ids(b%k), vls(b%k))
                work = b%tabd
                do j = 1, b%k
                    ids(j) = maxloc(work, dim=1, keepdims=.true.)
                    vls(j) = mlx_take_along_dim(work, ids(j), dim=1)
                    work   = mlx_put_along_dim(work, ids(j), b%low, dim=1)
                end do
                idx = mlx_concatenate(ids, dim=1)
                val = mlx_concatenate(vls, dim=1)
            case( 2, 5 )
                call select_partition(b, f == 2, idx, val)
            case( 3, 4 )
                call b%kern(f-2)%apply([b%tabd], outs, status)
                if( status /= 0 ) return
                idx = outs(1)
                val = outs(2)
        end select
        res(1) = idx
        res(2) = val
        call mlx_eval(res, status=status)
    end subroutine select_run

    ! E1: the K largest by mlx_argpartition and the K-th value; with repair the boundary's ties are resolved by the
    ! running count of the equal values in index order (the lower indices kept), without it argpartition's own
    ! choice stands; the K kept in order by rank (larger value first, then lower index) through mlx_argsort
    subroutine select_partition( b, repair, idx, val )
        type(select_bench), intent(inout) :: b
        logical,            intent(in)    :: repair
        type(mlx_array),    intent(out)   :: idx, val
        type(mlx_array) :: part, pk, vk, gt, eq, g, ceq, keep, score, qk, v, rank, order
        integer         :: k, np
        k  = b%k
        np = SEL_NPART
        part  = mlx_argpartition(b%tneg, k, dim=1)
        if( repair )then
            pk    = mlx_slice(part, [k, 1], [k, np])
            vk    = mlx_take_along_dim(b%tabd, pk, dim=1)
            gt    = mlx_astype(b%tabd > vk, MLX_DTYPES%float32)
            eq    = mlx_astype(b%tabd == vk, MLX_DTYPES%float32)
            g     = sum(gt, dim=1, keepdims=.true.)
            ceq   = mlx_cumsum(eq, dim=1)
            keep  = (gt > 0.5_real32) .or. ((eq > 0.5_real32) .and. (ceq <= (real(k, real32) - g)))
            score = merge(b%tneg, b%high, keep)
            qk    = mlx_slice(mlx_argpartition(score, k, dim=1), [1, 1], [k, np])
        else
            qk = mlx_slice(part, [1, 1], [k, np])
        endif
        v     = mlx_take_along_dim(b%tabd, qk, dim=1)
        rank  = sum(mlx_astype((reshape(v, [k, 1, np]) > reshape(v, [1, k, np])) .or. ((reshape(v, [k, 1, np]) == &
            &reshape(v, [1, k, np])) .and. (reshape(qk, [k, 1, np]) < reshape(qk, [1, k, np]))), MLX_DTYPES%float32), &
            &dim=1)
        order = mlx_argsort(rank, dim=1)
        idx   = mlx_take_along_dim(qk, order, dim=1)
        val   = mlx_take_along_dim(v, order, dim=1)
    end subroutine select_partition

    function select_seconds( self, f ) result(sec)
        class(select_bench), intent(inout) :: self
        integer,             intent(in)    :: f
        real(real64)    :: sec, t0
        type(mlx_array) :: idx, val
        integer         :: st
        call mlx_synchronize()
        t0 = clock_s()
        call select_run(self, f, idx, val, st)
        sec = clock_s() - t0
        if( st /= 0 ) sec = -1._real64
    end function select_seconds

    ! decision 11's exact gate: every form's K indices and values equal the host's first-maximum rule on every
    ! column (E1 without its repair is reported); each form bit-repeatable in a process
    subroutine select_agree( b, tab, seed )
        type(select_bench), intent(inout) :: b
        real(real32),       intent(in)    :: tab(:,:)
        integer,            intent(in)    :: seed
        integer,      allocatable :: hidx(:,:), di(:,:), di2(:,:)
        real(real32), allocatable :: hval(:,:), dv(:,:), dv2(:,:)
        type(mlx_array)           :: idx, val
        integer(int64)            :: h
        integer                   :: f, p, st, nbad, nrep
        allocate(hidx(b%k, SEL_NPART), hval(b%k, SEL_NPART), di(b%k, SEL_NPART), dv(b%k, SEL_NPART), &
            &di2(b%k, SEL_NPART), dv2(b%k, SEL_NPART))
        do p = 1, SEL_NPART
            call host_best(tab(:, p), hidx(:, p), hval(:, p))
        end do
        ! the planted ties as found: columns whose first maximum, and whose K-th value, occurs more than once
        write(*,'(a,i0,a,i0)') '    columns with a tie at the first maximum ', &
            &count([(count(bits_equal(tab(:, p), hval(1, p))) > 1, p = 1, SEL_NPART)]), '; at the K-th value ', &
            &count([(count(bits_equal(tab(:, p), hval(b%k, p))) > 1, p = 1, SEL_NPART)])
        do f = 1, size(SEL_FORMS)
            call select_run(b, f, idx, val, st)
            if( st == 0 ) call mlx_to(di, idx, status=st)
            if( st == 0 ) call mlx_to(dv, val, status=st)
            call assert_true(st == 0, trim(SEL_FORMS(f))//': evaluated')
            if( st /= 0 )then
                write(*,'(a)') '    '//mlx_last_error()
                cycle
            endif
            nbad = 0
            do p = 1, SEL_NPART
                if( any(di(:, p) /= hidx(:, p)) .or. .not. all(bits_equal(dv(:, p), hval(:, p))) ) nbad = nbad + 1
            end do
            call select_run(b, f, idx, val, st)
            if( st == 0 ) call mlx_to(di2, idx, status=st)
            if( st == 0 ) call mlx_to(dv2, val, status=st)
            nrep = 0
            if( st /= 0 .or. any(di2 /= di) .or. .not. all(bits_equal(dv2, dv)) ) nrep = 1
            h = DIGEST_START
            call digest_bits(h, int(reshape(di, [size(di)]), int32))
            write(*,'(a,i0,a,i0,a,i0,a,i0,a,z16.16)') '    '//trim(SEL_FORMS(f))//': columns off the host''s rule ', &
                &nbad, ' of ', SEL_NPART, '; repeat differing ', nrep, '; K ', b%k, '; digest ', h
            write(*,'(a,i0,a,i0,a,z16.16)') '    digest select '//trim(SEL_FORMS(f))//' K=', b%k, ' seed=', seed, ' ', h
            if( f /= 5 )then
                call assert_true(nbad == 0, trim(SEL_FORMS(f))//': the K best equal the host''s first-maximum rule '// &
                    &'on every column')
                call assert_true(nrep == 0, trim(SEL_FORMS(f))//': repeatable in a process')
            endif
        end do
    end subroutine select_agree

    ! ---- suite insert ------------------------------------------------------------------------------------------

    subroutine bench_insert( mode )
        character(len=*), intent(in) :: mode
        type(insert_bench) :: b
        type(probe_case)   :: cs
        integer            :: seed, n
        seed = arg_int('seed', 1)
        n    = arg_int('n', 64)
        write(*,'(a,i0,a,i0)') '**** bench_kernel_forms suite=insert mode='//mode//' n=', n, ' seed=', seed
        if( seed < 1 .or. seed > INS_SEEDS )then
            write(*,'(a)') 'bench_kernel_forms: suite=insert reads seed= 1 to 3 (the batches of its case)'
            error stop 2
        endif
        cs = seeded_case('kernel forms insert', n, INS_SEEDS * INS_PLANES, .false.)
        call insert_prepare(b, cs, seed, .false.)
        select case( mode )
            case( 'agree' )
                call insert_agree(b, cs, seed)
            case( 'time' )
                call time_forms(b, 1, [2, 3], INS_FORMS)
                call time_forms(b, 2, [3], INS_FORMS)
        end select
    end subroutine bench_insert

    ! seed's batch of the case on the device (with absolute data, the magnitudes whose sums scale the errors), the
    ! disc's pixel map, and the three kernels
    subroutine insert_prepare( b, cs, seed, absolute )
        type(insert_bench), intent(inout) :: b
        type(probe_case),   intent(in)    :: cs
        integer,            intent(in)    :: seed
        logical,            intent(in)    :: absolute
        type(mlx_custom_kernel_spec) :: d0
        integer, allocatable         :: pmap(:,:)
        integer                      :: p0, p1, nyq, i
        p0  = (seed - 1) * INS_PLANES + 1
        p1  = seed * INS_PLANES
        nyq = cs%n / 2
        allocate(pmap(2 * nyq + 1, 2 * nyq + 1))
        pmap = -1
        do i = 1, cs%npix
            pmap(nint(cs%hk(1, i)) + nyq + 1, nint(cs%hk(2, i)) + nyq + 1) = i - 1
        end do
        b%hk   = mlx_from(cs%hk)
        b%rot  = mlx_from(cs%rot(:, :, p0:p1))
        b%om   = mlx_from(cs%omega(p0:p1))
        if( absolute )then
            b%c = mlx_from(cmplx(abs(real(cs%c(:, p0:p1))), abs(aimag(cs%c(:, p0:p1))), kind=real32))
            b%q = mlx_from(abs(cs%q(:, p0:p1)))
        else
            b%c = mlx_from(cs%c(:, p0:p1))
            b%q = mlx_from(cs%q(:, p0:p1))
        endif
        b%coef = mlx_from(window_coefficients())
        b%pmap = mlx_from(int(pmap, int32))
        d0     = probe_spec(cs, INS_PLANES, .true.)
        b%par  = mlx_from(int([d0%template_ints, nyq, INS_PLANES], int32))
        b%kern(1) = mlx_custom_kernel(d0)
        b%kern(2) = mlx_custom_kernel(insert_pull_spec(.false., d0%template_ints(4), d0%template_ints(5)))
        b%kern(3) = mlx_custom_kernel(insert_pull_spec(.true., d0%template_ints(4), d0%template_ints(5)))
    end subroutine insert_prepare

    ! form f's numerator and density, evaluated
    subroutine insert_run( b, f, res, status )
        type(insert_bench),           intent(inout) :: b
        integer,                      intent(in)    :: f
        type(mlx_array), allocatable, intent(out)   :: res(:)
        integer,                      intent(out)   :: status
        if( f == 1 )then
            call b%kern(1)%apply([b%hk, b%rot, b%om, b%c, b%q, b%coef], res, status)
        else
            call b%kern(f)%apply([b%pmap, b%rot, b%om, b%c, b%q, b%coef, b%par], res, status)
        endif
        if( status == 0 ) call mlx_eval(res, status=status)
    end subroutine insert_run

    function insert_seconds( self, f ) result(sec)
        class(insert_bench), intent(inout) :: self
        integer,             intent(in)    :: f
        real(real64)                 :: sec, t0
        type(mlx_array), allocatable :: res(:)
        integer                      :: st
        call mlx_synchronize()
        t0 = clock_s()
        call insert_run(self, f, res, st)
        sec = clock_s() - t0
        if( st /= 0 ) sec = -1._real64
    end function insert_seconds

    ! form f's (re, im, density) of every voxel on the host, (3, nvox)
    subroutine insert_fetch( b, f, x )
        type(insert_bench),        intent(inout) :: b
        integer,                   intent(in)    :: f
        real(real32), allocatable, intent(out)   :: x(:,:)
        type(mlx_array), allocatable :: res(:)
        integer,         allocatable :: shp(:)
        integer                      :: st
        call insert_run(b, f, res, st)
        call assert_true(st == 0, trim(INS_FORMS(f))//': evaluated')
        if( st /= 0 )then
            write(*,'(a)') '    '//mlx_last_error()
            return
        endif
        shp = res(2)%shape()
        allocate(x(3, shp(1)))
        call mlx_to(x(1:2, :), res(1), status=st)
        call mlx_to(x(3, :), res(2), status=st)
    end subroutine insert_fetch

    ! decision 5 for the insertion: D1 and D2 bit-repeatable, D2 equal to D1 bit for bit, D1 against D0 relative to
    ! the sum of a voxel's |terms| (each part on its own; the sums from D1 on the data's magnitudes); D0's own
    ! spread between runs reported
    subroutine insert_agree( b, cs, seed )
        type(insert_bench), intent(inout) :: b
        type(probe_case),   intent(in)    :: cs
        integer,            intent(in)    :: seed
        type(insert_bench)        :: babs
        real(real32), allocatable :: x0(:,:), x0b(:,:), x1(:,:), x1b(:,:), x2(:,:), mag(:,:)
        real(real64)              :: e10, e00
        integer(int64)            :: h
        integer                   :: r, nrep1, nrep2
        call insert_fetch(b, 1, x0)
        call insert_fetch(b, 1, x0b)
        call insert_fetch(b, 2, x1)
        call insert_fetch(b, 3, x2)
        nrep1 = 0
        nrep2 = 0
        do r = 2, NREPEAT
            call insert_fetch(b, 2, x1b)
            if( .not. all(bits_equal(x1b, x1)) ) nrep1 = nrep1 + 1
            call insert_fetch(b, 3, x1b)
            if( .not. all(bits_equal(x1b, x2)) ) nrep2 = nrep2 + 1
        end do
        call insert_prepare(babs, cs, seed, .true.)
        call insert_fetch(babs, 2, mag)
        e10 = scaled_error(x1, x0, mag)
        e00 = scaled_error(x0b, x0, mag)
        h   = DIGEST_START
        call digest_bits(h, transfer(x1, [0_int32]))
        write(*,'(a,i0,a,i0,a,i0,a,i0,a,i0)') '    voxels ', size(x1, 2), ', reached ', count(mag(3, :) > 0._real32), &
            &'; d1 repeats differing ', nrep1, '; d2 repeats differing ', nrep2, '; d2 against d1 differing ', &
            &count(.not. bits_equal(x2, x1))
        write(*,'(a,es23.16,a,es23.16,a,i0,a)') '    d1 against d0, largest over the sum of |terms| ', e10, &
            &'; d0 against d0 ', e00, ' (', count(.not. bits_equal(x0b, x0)), ' values differ)'
        write(*,'(a,i0,a,i0,a,z16.16)') '    digest insert d1 n=', cs%n, ' seed=', seed, ' ', h
        call assert_true(nrep1 == 0 .and. nrep2 == 0, 'd1 and d2: bit-repeatable in a process')
        call assert_true(all(bits_equal(x2, x1)), 'd2: the staged pull equals the pull bit for bit')
        call assert_true(e10 <= FORMS_INSERT_TOL, 'd1: the pull is the probe''s insertion within FORMS_INSERT_TOL of '// &
            &'the sum of a voxel''s |terms|')
    end subroutine insert_agree

    ! the largest |x - ref| over the sum of the magnitudes of its terms, part by part, where that sum is not zero
    function scaled_error( x, ref, mag ) result(e)
        real(real32), intent(in) :: x(:,:), ref(:,:), mag(:,:)
        real(real64) :: e
        e = nan_maxval(pack(abs(real(x, real64) - real(ref, real64)) / merge(real(mag, real64), 1._real64, &
            &mag > 0._real32), mag > 0._real32))
    end function scaled_error

    ! ---- suite waits -------------------------------------------------------------------------------------------

    subroutine bench_waits( mode )
        character(len=*), intent(in) :: mode
        type(waits_bench) :: b
        integer           :: seed
        seed = arg_int('seed', 1)
        write(*,'(a,i0)') '**** bench_kernel_forms suite=waits mode='//mode//' seed=', seed
        call waits_prepare(b, seed)
        select case( mode )
            case( 'agree' )
                call waits_agree(b, seed)
            case( 'time' )
                call time_forms(b, 1, [2], WAIT_FORMS)
        end select
    end subroutine bench_waits

    ! the tiles' operands of seed (the references' operand is common), the variates that list about 30 % of each
    ! tile's pairs, and the capacity: the largest count of seed 1 times WAIT_CAP
    subroutine waits_prepare( b, seed )
        type(waits_bench), intent(inout) :: b
        integer,           intent(in)    :: seed
        real(real64), allocatable :: a(:,:,:), v(:,:)
        integer                   :: t, cmax, np, i
        np = WAIT_BT * WAIT_RT
        call set_fixed_seed(1)
        allocate(v(WAIT_BT, WAIT_RT))
        cmax = 0
        do t = 1, WAIT_TILES
            call random_number(v)
            cmax = max(cmax, count(real(v, real32) < WAIT_SHARE))
        end do
        b%cap = ceiling(WAIT_CAP * cmax)
        call set_fixed_seed(seed)
        allocate(b%pt(WAIT_TILES), b%u(WAIT_TILES))
        do t = 1, WAIT_TILES
            call random_number(v)
            b%u(t) = mlx_from(real(v, real32))
        end do
        allocate(a(WAIT_K4, 2 * WAIT_RT, WAIT_BINS))
        call random_number(a)
        b%g = mlx_from(real(2._real64 * a - 1._real64, real32))
        deallocate(a)
        allocate(a(WAIT_BT, WAIT_K4, WAIT_BINS))
        do t = 1, WAIT_TILES
            call random_number(a)
            b%pt(t) = mlx_from(real(2._real64 * a - 1._real64, real32))
        end do
        b%pairs = mlx_from([(i, i = 1, np)])
        b%seq   = mlx_from([(i, i = 1, b%cap)])
        call mlx_eval(b%pt, status=t)
        call mlx_eval(b%g, status=t)
    end subroutine waits_prepare

    ! stage 1 of tile t: the product (bt, 2rt, bins), its rows (bt 2rt, bins), the listing mask over the pairs (bt rt)
    ! and the positions of the listed pairs in list order (1-based)
    subroutine waits_stage1( b, t, rows, mask, pos )
        type(waits_bench), intent(inout) :: b
        integer,           intent(in)    :: t
        type(mlx_array),   intent(out)   :: rows, mask, pos
        rows = reshape(matmul(b%pt(t), b%g), [2 * WAIT_BT * WAIT_RT, WAIT_BINS])
        mask = reshape(b%u(t) < WAIT_SHARE, [WAIT_BT * WAIT_RT])
        pos  = mlx_cumsum(mlx_astype(mask, MLX_DTYPES%int32))
    end subroutine waits_stage1

    ! stage 2: the listed pairs compacted into a buffer of n by their positions (the others to a slot past the end),
    ! then each listed pair's sum over the bins of both of its row halves
    function waits_stage2( b, rows, mask, pos, n ) result(total)
        type(waits_bench), intent(inout) :: b
        type(mlx_array),   intent(in)    :: rows, mask, pos
        integer,           intent(in)    :: n
        type(mlx_array) :: total
        type(mlx_array) :: list, dump, first, second
        dump   = mlx_full([WAIT_BT * WAIT_RT], n + 1)
        list   = mlx_put_along_dim(mlx_full([n + 1], 1), merge(pos, dump, mask .and. (pos <= real(n, real32))), &
            &b%pairs, dim=1)
        list   = mlx_slice(list, [1], [n])
        first  = sum(mlx_take(rows, list, dim=1), dim=2)
        second = sum(mlx_take(rows, list + mlx_full([1], WAIT_BT * WAIT_RT), dim=1), dim=2)
        total   = first + second
    end function waits_stage2

    ! F0 (f 1): per tile the count read to the host, then a buffer of that size; F1 (f 2): every tile into the
    ! persistent capacity, the tail past the tile's count set to the sentinel against the count on the device,
    ! queued, one wait for the pass; res holds each tile's sums, counts the tiles' counts, ok false on an overflow
    subroutine waits_pass( b, f, res, counts, ok )
        type(waits_bench),            intent(inout) :: b
        integer,                      intent(in)    :: f
        type(mlx_array), allocatable, intent(out)   :: res(:)
        integer,                      intent(out)   :: counts(:)
        logical,                      intent(out)   :: ok
        type(mlx_array), allocatable :: cnt(:)
        type(mlx_array)              :: rows, mask, pos, s
        integer                      :: t, st
        allocate(res(WAIT_TILES), cnt(WAIT_TILES))
        ok = .true.
        do t = 1, WAIT_TILES
            call waits_stage1(b, t, rows, mask, pos)
            cnt(t) = sum(mlx_astype(mask, MLX_DTYPES%int32))
            if( f == 1 )then
                call mlx_to(counts(t), cnt(t), status=st)
                res(t) = waits_stage2(b, rows, mask, pos, counts(t))
                call mlx_eval(res(t), status=st)
            else
                s      = waits_stage2(b, rows, mask, pos, b%cap)
                res(t) = merge(s, mlx_full([b%cap], WAIT_SENT), b%seq <= cnt(t))
                call mlx_async_eval(res(t), status=st)
                call mlx_async_eval(cnt(t), status=st)
            endif
        end do
        if( f == 2 )then
            call mlx_eval(res, status=st)
            do t = 1, WAIT_TILES
                call mlx_to(counts(t), cnt(t), status=st)
            end do
            ok = maxval(counts) <= b%cap
        endif
    end subroutine waits_pass

    ! a pass of form f; F1 redoes the pass with the capacity raised to 1.25 times the largest count on an overflow
    function waits_seconds( self, f ) result(sec)
        class(waits_bench), intent(inout) :: self
        integer,            intent(in)    :: f
        real(real64)                 :: sec, t0
        type(mlx_array), allocatable :: res(:)
        integer                      :: counts(WAIT_TILES)
        logical                      :: ok
        call mlx_synchronize()
        t0 = clock_s()
        call waits_pass(self, f, res, counts, ok)
        if( .not. ok )then
            call waits_grow(self, maxval(counts))
            call waits_pass(self, f, res, counts, ok)
        endif
        sec = clock_s() - t0
    end function waits_seconds

    subroutine waits_grow( b, cmax )
        type(waits_bench), intent(inout) :: b
        integer,           intent(in)    :: cmax
        integer :: i
        b%cap = ceiling(WAIT_CAP * cmax)
        b%seq = mlx_from([(i, i = 1, b%cap)])
    end subroutine waits_grow

    ! decision 13's equality: F1's listed sums, up to each tile's count, equal F0's bit for bit, and its tail holds
    ! the sentinel; both repeatable
    subroutine waits_agree( b, seed )
        type(waits_bench), intent(inout) :: b
        integer,           intent(in)    :: seed
        type(mlx_array), allocatable :: r0(:), r1(:)
        real(real32),    allocatable :: s0(:), s1(:)
        integer                      :: c0(WAIT_TILES), c1(WAIT_TILES), t, nbad, ntail, st, nrep, f
        integer(int64)               :: h
        logical                      :: ok
        call waits_pass(b, 1, r0, c0, ok)
        call waits_pass(b, 2, r1, c1, ok)
        if( .not. ok )then
            write(*,'(a,i0)') '    f1: overflow, capacity raised from ', b%cap
            call waits_grow(b, maxval(c1))
            call waits_pass(b, 2, r1, c1, ok)
        endif
        nbad  = 0
        ntail = 0
        h     = DIGEST_START
        do t = 1, WAIT_TILES
            allocate(s0(c0(t)), s1(b%cap))
            call mlx_to(s0, r0(t), status=st)
            call mlx_to(s1, r1(t), status=st)
            nbad  = nbad + count(.not. bits_equal(s1(1:c0(t)), s0))
            ntail = ntail + count(.not. bits_equal(s1(c0(t)+1:), WAIT_SENT))
            call digest_bits(h, transfer(s0, [0_int32]))
            deallocate(s0, s1)
        end do
        nrep = 0
        do f = 1, 2
            call waits_pass(b, f, r1, c1, ok)
            do t = 1, WAIT_TILES
                allocate(s1(merge(c0(t), b%cap, f == 1)), s0(c0(t)))
                call mlx_to(s1, r1(t), status=st)
                call mlx_to(s0, r0(t), status=st)
                if( .not. all(bits_equal(s1(1:c0(t)), s0)) ) nrep = nrep + 1
                deallocate(s0, s1)
            end do
        end do
        write(*,'(a,i0,a,i0,a,i0,a,i0)') '    counts ', minval(c0), ' to ', maxval(c0), ', capacity ', b%cap, &
            &'; counts equal in f1 ', count(c1 == c0)
        write(*,'(a,i0,a,i0,a,i0)') '    f1 against f0: listed sums differing ', nbad, '; tail entries not the '// &
            &'sentinel ', ntail, '; repeats differing ', nrep
        write(*,'(a,i0,a,z16.16)') '    digest waits f0 seed=', seed, ' ', h
        call assert_true(all(c1 == c0), 'f1: the counts on the device are f0''s')
        call assert_true(nbad == 0 .and. ntail == 0, 'f1: the listed sums equal f0''s bit for bit and the tail '// &
            &'holds the sentinel')
        call assert_true(nrep == 0, 'f0 and f1: repeatable in a process')
    end subroutine waits_agree

end module mlxf_bench_kernel_forms
