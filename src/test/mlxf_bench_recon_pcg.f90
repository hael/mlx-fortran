!@descr: benchmark of the toy reconstructor_pcg at SIMPLE's boxes: transforms, timing, profile, probe, accuracy
! mlxf_test_exec test=bench_recon_pcg suite=<transform|time|profile|probe|accuracy> [key=value ...]: the padded
! transforms alone; the canonical driver (new, set_window_sphere, set_raw_accum, end_accum, the solve, kill) per box,
! system (P: SIMPLE's absolute ridge, R: the relative one) and rule, timed by decision 20's protocol; its stages
! and pieces; the scalars', the waits' and the transforms' shares; the device against the oracle at bench size.
! A key the suite does not read stops the program. Rows go to ./bench_recon_pcg.tsv; times never pass or fail.
module mlxf_bench_recon_pcg
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use, intrinsic :: iso_c_binding,   only: c_int, c_double
use mlxf,                       only: mlx_array, mlx_from, mlx_to, mlx_eval, mlx_view, mlx_item, mlx_rfftn, mlx_irfftn, &
                                      mlx_slice, mlx_set_default_device, mlx_peak_memory, mlx_reset_peak_memory, &
                                      mlx_active_memory, mlx_cache_memory, mlx_clear_cache, MLX_DEVICES, sum
use mlxf_test_defs,             only: RECON_PCG_BENCH_N, RECON_PCG_BENCH_MSKRAD, RECON_PCG_N_SMALL, RECON_PCG_N_NAMED, &
                                      RECON_PCG_MSKRAD_SMALL, RECON_PCG_MSKRAD_NAMED, RECON_PCG_PLANES_PER_N, &
                                      RECON_PCG_LAMBDA_REL, RECON_PCG_TOLERANCES, PCG_LAMBDA, PCG_RESID_REPLACE, &
                                      ELEM_CEILING, pcg_solver_options
use mlxf_toy_reconstructor_pcg, only: reconstructor_pcg
use mlxf_toy_pcg_solver,        only: pcg_operator, pcg_solver_outcome, pcg_solve
use mlxf_oracle_recon_fixture,  only: oracle_recon_fixture_accum
use mlxf_oracle_recon_pcg,      only: oracle_recon_problem
use mlxf_test_utils,            only: assert_true, test_devices, device_name, bits_equal, seeded_uniform
use mlxf_test_reduce,           only: nan_maxval
implicit none
private

public :: run_bench_recon_pcg

! the keys each suite reads, blank separated; test and suite belong to the executable
character(len=*), parameter :: SUITE_KEYS(5) = [character(len=96) :: 'transform n device repeats revision', &
    &'time n system rules device seed repeats out revision', 'profile n system rules device seed revision', &
    &'probe n device seed revision', 'accuracy n device seed revision']
! the rows' file and the seed of the transformed volume
character(len=*), parameter :: ROWS_FILE   = 'bench_recon_pcg.tsv'
integer,          parameter :: VOLUME_SEED = 1
! the profile's and the wait's repeats (the median taken), the probe's rules on system P, the accuracy suite's
! rules and their systems
integer,          parameter :: PROFILE_REPEATS = 10
integer,          parameter :: WAIT_REPEATS    = 100
character(len=*), parameter :: PROBE_RULES(3)  = [character(len=4) :: 'F2', 'F5', 'F50']
character(len=*), parameter :: ACC_RULES(4)    = [character(len=4) :: 'F2', 'F5', 'E', 'R4']
character(len=*), parameter :: ACC_SYSTEMS(4)  = [character(len=1) :: 'P', 'P', 'R', 'R']

! a bench fixture: the accumulators the toy receives and the oracle's (the same values widened), the generator's s
type :: bench_accum
    complex(real32), allocatable :: b32(:,:,:)
    real(real32),    allocatable :: d32(:,:,:)
    complex(real64), allocatable :: b64(:,:,:)
    real(real64),    allocatable :: d64(:,:,:)
    real(real64)                 :: t_gen = 0._real64
end type bench_accum

! one timed configuration: the suite that writes its row, the box, the system (P or R), the rule, the passes
type :: bench_case
    character(len=8) :: suite   = ''
    integer          :: n       = 0
    character(len=1) :: system  = 'P'
    character(len=8) :: rule    = ''
    integer          :: repeats = 3
end type bench_case

! one pass of the canonical driver: the map, the outcome, the seconds of end_accum (with set_raw_accum) and the solve
type :: bench_pass
    real(real32), allocatable :: x(:,:,:)
    type(pcg_solver_outcome)  :: oc
    real(real64)              :: te = 0._real64
    real(real64)              :: ts = 0._real64
end type bench_pass

! one row's measures: times (best, spread, end_accum, solve, per iteration, two halves), the true residual, the
! fixture's seconds; MLX's peak, active and cache bytes; the waits; the passes' bits; the load before and after
type :: bench_row
    real(real64)   :: t(8)   = 0._real64
    integer(int64) :: b(3)   = 0_int64
    integer        :: waits  = 0
    logical        :: same   = .true.
    real           :: load0  = -1.
    real           :: load1  = -1.
end type bench_row

! the engine's client over the toy's public procedures: rules the toy's solve_accum does not offer, and the probe
type, extends(pcg_operator) :: bench_operator
    type(reconstructor_pcg), pointer :: rec => null()
  contains
    procedure :: size    => bench_size
    procedure :: apply   => bench_apply
    procedure :: precond => bench_precond
    procedure :: dot     => bench_dot
end type bench_operator

interface
    integer(c_int) function getloadavg( loadavg, nelem ) bind(c, name='getloadavg')
        import :: c_int, c_double
        real(c_double) :: loadavg(*)
        integer(c_int), value :: nelem
    end function getloadavg
end interface

contains

    subroutine run_bench_recon_pcg( suite, found )
        character(len=*), intent(in)  :: suite
        logical,          intent(out) :: found
        found = .true.
        call check_keys(suite)
        select case( trim(suite) )
            case( 'transform' )
                call bench_transform
            case( 'time' )
                call bench_time
            case( 'profile' )
                call bench_profile
            case( 'probe' )
                call bench_probe
            case( 'accuracy' )
                call bench_accuracy
            case default
                found = .false.
        end select
    end subroutine run_bench_recon_pcg

    ! ---- arguments ---------------------------------------------------------------------------------------

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
            write(*,'(a)') 'bench_recon_pcg: suite='//trim(suite)//' does not read '//trim(arg)//' (its keys:'//&
                &trim(keys)//')'
            error stop 2
        end do
    end subroutine check_keys

    ! the integer value of key=value, or dflt when the key is absent; a value that is not an integer stops
    integer function arg_int( key, dflt )
        character(len=*), intent(in) :: key
        integer,          intent(in) :: dflt
        character(len=:), allocatable :: s
        integer                       :: ios
        arg_int = dflt
        s       = arg_str(key, '')
        if( len(s) == 0 ) return
        ios = 1
        if( verify(s, '+-0123456789') == 0 ) read(s, *, iostat=ios) arg_int
        if( ios /= 0 )then
            write(*,'(a)') 'bench_recon_pcg: '//key//'='//s//' is not an integer'
            error stop 2
        endif
    end function arg_int

    ! the boxes of n= (one), or both bench boxes
    function arg_boxes() result(ns)
        integer, allocatable :: ns(:)
        integer              :: n
        n = arg_int('n', 0)
        if( n > 0 )then
            if( modulo(n, 2) /= 0 )then
                write(*,'(a)') 'bench_recon_pcg: n= is an even box'
                error stop 2
            endif
            ns = [n]
        else
            ns = RECON_PCG_BENCH_N
        endif
    end function arg_boxes

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

    ! opens the rows' file for appending, writing the header when the file is new
    subroutine open_rows( u, header )
        integer,          intent(out) :: u
        character(len=*), intent(in)  :: header
        logical :: exists
        inquire(file=ROWS_FILE, exist=exists)
        open(newunit=u, file=ROWS_FILE, position='append', action='write')
        if( .not. exists ) write(u,'(a)') header
    end subroutine open_rows

    ! ---- suite=transform ---------------------------------------------------------------------------------

    ! per box and device: the padded forward transform, its inverse and the crop, evaluated repeats times after a
    ! warm-up; the spectrum's shape and the round trip are asserted, the rest is recorded
    subroutine bench_transform
        integer, allocatable :: devs(:), ns(:)
        integer              :: idev, in, repeats
        ns      = arg_boxes()
        repeats = max(1, arg_int('repeats', 3))
        call test_devices(devs)
        do idev = 1, size(devs)
            call mlx_set_default_device(devs(idev))
            do in = 1, size(ns)
                call transform_row(ns(in), devs(idev), repeats)
            end do
        end do
    end subroutine bench_transform

    subroutine transform_row( n, dev, repeats )
        integer, intent(in) :: n, dev, repeats
        real(real32),     allocatable :: x(:,:,:), y(:,:,:), y1(:,:,:)
        real(real64),     allocatable :: t(:)
        type(mlx_array)               :: a, s, r, c
        integer,          allocatable :: shp(:)
        integer                       :: m, k, u
        logical                       :: same
        real(real64)                  :: err, t0
        real                          :: load0, load1
        integer(int64)                :: peak, active, cache
        character(len=:), allocatable :: rev
        m = 2 * n
        allocate(x(n, n, n), y(n, n, n), y1(n, n, n), t(repeats))
        x = reshape(real(seeded_uniform(n**3, VOLUME_SEED), real32), [n, n, n])
        call mlx_clear_cache()
        a = mlx_from(x)
        call mlx_eval(a)
        load0 = load_average()
        ! the warm-up: the shape of the spectrum, Fortran's view with the halved dimension first
        s   = mlx_rfftn(a, n=[m, m, m])
        shp = s%shape()
        r   = mlx_irfftn(s, n=[m, m, m])
        c   = mlx_slice(r, [1, 1, 1], [n, n, n])
        call mlx_to(y1, c)
        call assert_true(size(shp) == 3, 'transform: the padded spectrum has rank 3')
        if( size(shp) == 3 ) call assert_true(all(shp == [m/2 + 1, m, m]), &
            'transform: the padded spectrum has the shape (m/2 + 1, m, m), the halved dimension first')
        call mlx_reset_peak_memory()
        same = .true.
        do k = 1, repeats
            t0 = clock_s()
            s  = mlx_rfftn(a, n=[m, m, m])
            r  = mlx_irfftn(s, n=[m, m, m])
            c  = mlx_slice(r, [1, 1, 1], [n, n, n])
            call mlx_eval(c)
            t(k) = clock_s() - t0
            call mlx_to(y, c)
            same = same .and. all(bits_equal(y, y1))
        end do
        peak   = mlx_peak_memory()
        active = mlx_active_memory()
        cache  = mlx_cache_memory()
        load1  = load_average()
        err    = nan_maxval(real(abs(y - x), real64)) / nan_maxval(real(abs(x), real64))
        call assert_true(err <= ELEM_CEILING, 'transform: the padded round trip returns the volume within 64 float32 '//&
            'epsilons of its largest value')
        rev = arg_str('revision', 'unknown')
        call open_rows(u, 'suite'//achar(9)//'n'//achar(9)//'m'//achar(9)//'device'//achar(9)//'spectrum_shape'//&
            &achar(9)//'roundtrip_err'//achar(9)//'best_s'//achar(9)//'spread_s'//achar(9)//'times_s'//achar(9)//&
            &'bits_equal'//achar(9)//'peak_b'//achar(9)//'active_b'//achar(9)//'cache_b'//achar(9)//'load1_before'//&
            &achar(9)//'load1_after'//achar(9)//'revision')
        write(u,'(a,i0,a,i0,a,a,a,3(i0,a),es11.4e2,a,f0.6,a,f0.6,a,*(f0.6,:,","))', advance='no') 'transform'//&
            &achar(9), n, achar(9), m, achar(9), device_name(dev), achar(9), shp(1), 'x', shp(2), 'x', shp(3), achar(9), &
            err, achar(9), minval(t), achar(9), maxval(t) - minval(t), achar(9), t
        write(u,'(a,l1,3(a,i0),2(a,f0.2),a,a)') achar(9), same, achar(9), peak, achar(9), active, achar(9), cache, &
            achar(9), load0, achar(9), load1, achar(9), rev
        close(u)
        write(*,'(a,i0,a,i0,3a,es10.3,a,f9.4,a,f9.4,a,l1,a,es10.3)') 'transform n=', n, ' m=', m, ' ', &
            device_name(dev), ': round trip ', err, ', best ', minval(t), ' s, spread ', maxval(t) - minval(t), &
            ' s, bits equal ', same, ', peak ', real(peak, real64)
    end subroutine transform_row


    ! ---- the fixture, the assembly and the rules -------------------------------------------------------------

    ! the bench fixture of box n and seed (4 n planes): the accumulators rounded once, and widened for the oracle
    subroutine bench_fixture( n, seed, acc )
        integer,           intent(in)    :: n, seed
        type(bench_accum), intent(inout) :: acc
        real(real64), allocatable :: u(:)
        real(real64)              :: t0
        t0 = clock_s()
        if( allocated(acc%b64) ) deallocate(acc%b64, acc%d64)
        allocate(acc%b64(n+1, 2*n, 2*n), acc%d64(n+1, 2*n, 2*n))
        u = seeded_uniform(3 * RECON_PCG_PLANES_PER_N * n + 3, seed)
        call oracle_recon_fixture_accum(n, u, acc%b64, acc%d64)
        acc%b32   = cmplx(real(acc%b64, real32), real(aimag(acc%b64), real32), real32)
        acc%d32   = real(acc%d64, real32)
        acc%b64   = cmplx(real(real(acc%b32), real64), real(aimag(acc%b32), real64), real64)
        acc%d64   = real(acc%d32, real64)
        acc%t_gen = clock_s() - t0
    end subroutine bench_fixture

    ! the mask radius of a box: the bench boxes', the fast and named-only boxes', else 0.35 n
    real(real32) function bench_mskrad( n )
        integer, intent(in) :: n
        integer :: i
        bench_mskrad = real(0.35_real64 * real(n, real64), real32)
        do i = 1, size(RECON_PCG_BENCH_N)
            if( RECON_PCG_BENCH_N(i) == n ) bench_mskrad = real(RECON_PCG_BENCH_MSKRAD(i), real32)
        end do
        if( n == RECON_PCG_N_SMALL ) bench_mskrad = real(RECON_PCG_MSKRAD_SMALL, real32)
        if( n == RECON_PCG_N_NAMED ) bench_mskrad = real(RECON_PCG_MSKRAD_NAMED, real32)
    end function bench_mskrad

    ! the canonical driver's untimed first steps: new and the support; system P carries SIMPLE's absolute ridge,
    ! system R the relative one
    subroutine bench_new( rec, n, system )
        type(reconstructor_pcg), intent(inout) :: rec
        integer,                 intent(in)    :: n
        character(len=*),        intent(in)    :: system
        if( system == 'P' )then
            call rec%new(n, lambda=PCG_LAMBDA)
        else
            call rec%new(n)
            call rec%set_lambda_relative(RECON_PCG_LAMBDA_REL)
        endif
        call rec%set_window_sphere(bench_mskrad(n))
    end subroutine bench_new

    ! a whole assembly up to end_accum, untimed
    subroutine bench_assemble( rec, n, system, acc )
        type(reconstructor_pcg), intent(inout) :: rec
        integer,                 intent(in)    :: n
        character(len=*),        intent(in)    :: system
        type(bench_accum),       intent(in)    :: acc
        call bench_new(rec, n, system)
        call rec%set_raw_accum(acc%b32, acc%d32)
        call rec%end_accum(.true.)
    end subroutine bench_assemble

    integer function bench_size( self ) result(n)
        class(bench_operator), intent(in) :: self
        n = self%rec%box**3
    end function bench_size

    subroutine bench_apply( self, x, y )
        class(bench_operator), intent(inout) :: self
        type(mlx_array),       intent(in)    :: x
        type(mlx_array),       intent(out)   :: y
        y = self%rec%apply_normal(x)
    end subroutine bench_apply

    subroutine bench_precond( self, r, z )
        class(bench_operator), intent(inout) :: self
        type(mlx_array),       intent(in)    :: r
        type(mlx_array),       intent(out)   :: z
        z = self%rec%apply_precond(r)
    end subroutine bench_precond

    function bench_dot( self, a, b ) result(d)
        class(bench_operator), intent(in) :: self
        type(mlx_array),       intent(in) :: a, b
        type(mlx_array) :: d
        d = self%rec%dot_real_volume(a, b)
    end function bench_dot

    ! the engine's options of a rule: F2 and F5 SIMPLE's production (exactly 2 and 5), F25 and F50 fixed
    ! iterations, E the engine's rules, R4 rtol 1e-4 with no step test and at most 200
    function rule_options( rule ) result(o)
        character(len=*), intent(in) :: rule
        type(pcg_solver_options) :: o
        select case( rule )
            case( 'F2', 'F5', 'F25', 'F50' )
                read(rule(2:), *) o%maxits
                o%rtol = 0._real32
            case( 'E' )
                o%maxits = 50
                o%rtol   = 1.e-4_real32
            case( 'R4' )
                o%maxits = 200
                o%rtol   = 1.e-4_real32
                o%xtol   = 0._real32
            case default
                write(*,'(a)') 'bench_recon_pcg: rules= is F2, F5, F25, F50, E or R4'
                error stop 2
        end select
    end function rule_options

    ! the solve of a rule from zero into x: SIMPLE's solve_accum (the shipped map), or for R4, whose step test
    ! solve_accum does not let a caller turn off, the engine on the toy's public procedures (the unshipped solution)
    subroutine solve_rule( rec, rule, x, oc )
        type(reconstructor_pcg), target, intent(inout) :: rec
        character(len=*),                intent(in)    :: rule
        real(real32),                    intent(inout) :: x(:,:,:)
        type(pcg_solver_outcome),        intent(out)   :: oc
        type(pcg_solver_options) :: o
        o = rule_options(rule)
        x = 0._real32
        if( rule == 'R4' )then
            call engine_solution(rec, o, x, oc)
        else
            call rec%solve_accum(x, maxits=o%maxits, rtol=o%rtol, outcome=oc)
        endif
    end subroutine solve_rule

    ! the engine from zero on the toy's public procedures under options o: the unshipped solution u in x
    subroutine engine_solution( rec, o, x, oc )
        type(reconstructor_pcg), target, intent(inout) :: rec
        type(pcg_solver_options),        intent(in)    :: o
        real(real32),                    intent(inout) :: x(:,:,:)
        type(pcg_solver_outcome),        intent(out)   :: oc
        type(bench_operator)      :: op
        type(mlx_array)           :: bd, xd
        real(real32), allocatable :: b(:,:,:), e(:,:,:), ie(:,:,:)
        allocate(b, e, ie, mold=x)
        call rec%copy_volumes(b, e, ie)
        op%rec => rec
        bd = mlx_from(b)
        x  = 0._real32
        xd = mlx_from(x)
        call pcg_solve(op, bd, xd, o, oc)
        call mlx_to(x, xd)
    end subroutine engine_solution

    ! the device's own true residual |b - H u| / |b| of an unshipped solution, the norms in double
    real(real64) function device_true_residual( rec, u ) result(r)
        type(reconstructor_pcg), intent(inout) :: rec
        real(real32),            intent(in)    :: u(:,:,:)
        type(mlx_array)           :: ud, hu
        real(real32), allocatable :: b(:,:,:), e(:,:,:), ie(:,:,:), h(:,:,:)
        allocate(b, e, ie, h, mold=u)
        call rec%copy_volumes(b, e, ie)
        ud = mlx_from(u)
        hu = rec%apply_normal(ud)
        call mlx_to(h, hu)
        r = norm2(real(b, real64) - real(h, real64)) / norm2(real(b, real64))
    end function device_true_residual

    ! ---- suite=time ------------------------------------------------------------------------------------------

    ! decision 20's protocol per box and rule: a warm-up pass of the canonical driver, then repeats passes and two
    ! halves back to back; per pass the seconds from set_raw_accum to the map on the host, end_accum and the solve
    ! apart; the map's bytes to out (when given) and the histories in hexadecimal, for the comparison of two
    ! invocations; the device's own true residual (the engine's unshipped solution under the same options)
    subroutine bench_time
        type(bench_accum)             :: acc
        type(bench_case)              :: bc
        character(len=8), allocatable :: rule_list(:)
        integer,          allocatable :: ns(:)
        integer                       :: in, ir
        ns        = arg_boxes()
        bc%suite  = 'time'
        bc%system = arg_str('system', 'P')
        rule_list = split_list(arg_str('rules', merge('F2,F5', 'E,R4 ', bc%system == 'P')))
        bc%repeats = max(1, arg_int('repeats', 3))
        call mlx_set_default_device(device_of_arg())
        do in = 1, size(ns)
            bc%n = ns(in)
            call bench_fixture(bc%n, arg_int('seed', 1), acc)
            deallocate(acc%b64, acc%d64)
            do ir = 1, size(rule_list)
                bc%rule = rule_list(ir)
                call time_rule(bc, acc)
            end do
        end do
    end subroutine bench_time

    subroutine time_rule( bc, acc )
        type(bench_case),  intent(in) :: bc
        type(bench_accum), intent(in) :: acc
        type(reconstructor_pcg), target :: rec
        type(bench_pass)                :: ps, first
        type(bench_row)                 :: row
        real(real64)                    :: tt(bc%repeats), te(bc%repeats), ts(bc%repeats), t0
        integer                         :: k, u_out, n
        character(len=:), allocatable   :: out
        n = bc%n
        allocate(ps%x(n, n, n))
        row%load0 = load_average()
        call driver_pass(rec, bc, acc, first)
        row%same = .true.
        call mlx_reset_peak_memory()
        do k = 1, bc%repeats
            call driver_pass(rec, bc, acc, ps)
            te(k)    = ps%te
            ts(k)    = ps%ts
            tt(k)    = ps%te + ps%ts
            row%same = row%same .and. all(bits_equal(ps%x, first%x))
        end do
        row%b(1) = mlx_peak_memory()
        row%b(2) = mlx_active_memory()
        row%b(3) = mlx_cache_memory()
        t0 = clock_s()
        call driver_pass(rec, bc, acc, ps)
        call driver_pass(rec, bc, acc, ps)
        row%t(6) = clock_s() - t0
        ! the waits, the stages and the device's own true residual, from one more assembly
        call bench_assemble(rec, n, trim(bc%system), acc)
        call solve_rule(rec, trim(bc%rule), ps%x, ps%oc)
        row%waits = rec%host_waits()
        if( trim(bc%rule) /= 'R4' ) call engine_solution(rec, rule_options(trim(bc%rule)), ps%x, ps%oc)
        row%t(7) = device_true_residual(rec, ps%x)
        call rec%kill()
        row%load1 = load_average()
        row%t(1:5) = [minval(tt), maxval(tt) - minval(tt), minval(te), minval(ts), &
                      minval(ts) / real(max(1, first%oc%iteration_count), real64)]
        row%t(8) = acc%t_gen
        out = arg_str('out', '')
        if( len(out) > 0 )then
            open(newunit=u_out, file=out//'_n'//itoa(n)//'_'//trim(bc%system)//'_'//trim(bc%rule)//'.bin', &
                 access='stream', form='unformatted', status='replace', action='write')
            write(u_out) first%x
            close(u_out)
        endif
        call write_history_hex(bc, first%oc)
        call write_row(bc, first%oc, row)
        write(*,'(a,i0,5a,i0,a,f9.4,a,f9.4,a,f9.4,a,es10.3,a,l1)') 'time n=', n, ' ', trim(bc%system), ' ', &
            trim(bc%rule), ': ', first%oc%iteration_count, ' iterations, best ', row%t(1), ' s (end_accum ', row%t(3), &
            ', solve ', row%t(4), '), peak ', real(row%b(1), real64), ', repeat bits ', row%same
    end subroutine time_rule

    ! one pass of the canonical driver: new and the support untimed, then set_raw_accum and end_accum (te), the
    ! solve to the map on the host (ts); kill
    subroutine driver_pass( rec, bc, acc, ps )
        type(reconstructor_pcg), target, intent(inout) :: rec
        type(bench_case),                intent(in)    :: bc
        type(bench_accum),               intent(in)    :: acc
        type(bench_pass),                intent(inout) :: ps
        real(real64) :: t0
        if( .not. allocated(ps%x) ) allocate(ps%x(bc%n, bc%n, bc%n))
        call bench_new(rec, bc%n, trim(bc%system))
        t0 = clock_s()
        call rec%set_raw_accum(acc%b32, acc%d32)
        call rec%end_accum(.true.)
        ps%te = clock_s() - t0
        t0 = clock_s()
        call solve_rule(rec, trim(bc%rule), ps%x, ps%oc)
        ps%ts = clock_s() - t0
        call rec%kill()
    end subroutine driver_pass

    ! the residual and update histories in hexadecimal, one line, for a diff between invocations
    subroutine write_history_hex( bc, oc )
        type(bench_case),         intent(in) :: bc
        type(pcg_solver_outcome), intent(in) :: oc
        integer :: k
        write(*,'(a,i0,5a,i0,a)', advance='no') 'history n=', bc%n, ' ', trim(bc%system), ' ', trim(bc%rule), ' ', &
            oc%iteration_count, ' '//trim(oc%stop_reason)//' residual'
        do k = 1, size(oc%rel_residual_history)
            write(*,'(a,z8.8)', advance='no') ' ', transfer(oc%rel_residual_history(k), 0_int32)
        end do
        write(*,'(a)', advance='no') ' update'
        do k = 1, size(oc%rel_update_history)
            write(*,'(a,z8.8)', advance='no') ' ', transfer(oc%rel_update_history(k), 0_int32)
        end do
        write(*,'(a)') ''
    end subroutine write_history_hex

    ! one row of key=value fields: times (best, spread, end_accum, solve, per iteration, two halves), the true
    ! residual, the fixture's seconds; MLX's peak, active and cache bytes; the waits; the passes' bits
    subroutine write_row( bc, oc, row )
        type(bench_case),         intent(in) :: bc
        type(pcg_solver_outcome), intent(in) :: oc
        type(bench_row),          intent(in) :: row
        character(len=1), parameter :: TB = achar(9)
        integer                     :: u
        call open_rows(u, 'rows of the suites other than transform: tab-separated key=value fields')
        write(u,'(a,i0,a,i0,a)', advance='no') 'suite='//trim(bc%suite)//TB//'n=', bc%n, TB//'system='// &
            trim(bc%system)//TB//'rule='//trim(bc%rule)//TB//'iterations=', oc%iteration_count, TB//'reason='// &
            trim(oc%stop_reason)
        write(u,'(a,es12.5,a,es12.5)', advance='no') TB//'reported_residual=', oc%final_rel_residual, &
            TB//'true_residual=', row%t(7)
        write(u,'(6(a,f0.6))', advance='no') TB//'best_s=', row%t(1), TB//'spread_s=', row%t(2), TB//'end_accum_s=', &
            row%t(3), TB//'solve_s=', row%t(4), TB//'per_iteration_s=', row%t(5), TB//'two_halves_s=', row%t(6)
        write(u,'(4(a,i0),a,l1,3(a,f0.2))', advance='no') TB//'peak_b=', row%b(1), TB//'active_b=', row%b(2), &
            TB//'cache_b=', row%b(3), TB//'waits=', row%waits, TB//'repeat_bits=', row%same, TB//'load1_before=', &
            row%load0, TB//'load1_after=', row%load1, TB//'fixture_s=', row%t(8)
        write(u,'(a)') TB//'device='//device_name(device_of_arg())//TB//'revision='//arg_str('revision', 'unknown')
        close(u)
    end subroutine write_row

    integer function device_of_arg()
        device_of_arg = MLX_DEVICES%gpu
        if( arg_str('device', 'gpu') == 'cpu' ) device_of_arg = MLX_DEVICES%cpu
    end function device_of_arg

    ! the comma-separated items of s
    function split_list( s ) result(items)
        character(len=*), intent(in) :: s
        character(len=8), allocatable :: items(:)
        character(len=8)              :: item
        integer                       :: i0, i
        allocate(items(0))
        i0 = 1
        do i = 1, len(s) + 1
            if( i <= len(s) )then
                if( s(i:i) /= ',' ) cycle
            endif
            if( i > i0 )then
                item  = s(i0:i-1)
                items = [items, item]
            endif
            i0 = i + 1
        end do
    end function split_list

    function itoa( i ) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16)             :: buf
        write(buf,'(i0)') i
        s = trim(buf)
    end function itoa

    real(real64) function median_of( x )
        real(real64), intent(in) :: x(:)
        real(real64) :: s(size(x)), tmp
        integer      :: i, j
        s = x
        do i = 2, size(s)
            tmp = s(i)
            j   = i - 1
            do while( j >= 1 )
                if( s(j) <= tmp ) exit
                s(j+1) = s(j)
                j      = j - 1
            end do
            s(j+1) = tmp
        end do
        median_of = s((size(s) + 1) / 2)
        if( modulo(size(s), 2) == 0 ) median_of = (s(size(s) / 2) + s(size(s) / 2 + 1)) / 2._real64
    end function median_of

    ! ---- suite=profile -------------------------------------------------------------------------------------

    ! the canonical driver once with the toy's stage seconds, then each piece alone after a warm-up, the median of
    ! PROFILE_REPEATS with an evaluation after each: the operator, the preconditioner, an inner product with its
    ! copy, the padded transform pair with its crop; it explains and does not decide
    subroutine bench_profile
        type(bench_accum)               :: acc
        type(reconstructor_pcg), target :: rec
        type(pcg_solver_outcome)        :: oc
        character(len=:), allocatable   :: system, rule
        real(real32),     allocatable   :: x(:,:,:)
        integer,          allocatable   :: ns(:)
        real(real64)                    :: st(4), tm(4)
        integer                         :: in, n
        ns     = arg_boxes()
        system = arg_str('system', 'P')
        rule   = arg_str('rules', merge('F2', 'E ', system == 'P'))
        call mlx_set_default_device(device_of_arg())
        do in = 1, size(ns)
            n = ns(in)
            call bench_fixture(n, arg_int('seed', 1), acc)
            deallocate(acc%b64, acc%d64)
            allocate(x(n, n, n))
            call bench_assemble(rec, n, system, acc)
            call solve_rule(rec, trim(rule), x, oc)
            st = rec%stage_seconds()
            tm = piece_medians(rec, n)
            call rec%kill()
            write(*,'(a,i0,5a,4(f0.6,a),i0,a)') 'profile n=', n, ' ', system, ' ', trim(rule), ': statistics and graph ', &
                st(1), ' s, finalisation wait ', st(2), ' s, engine ', st(3), ' s, map ', st(4), ' s (', &
                oc%iteration_count, ' iterations, cold)'
            write(*,'(a,i0,a,4(f0.6,a))') 'profile n=', n, ' alone (median): operator ', tm(1), ' s, preconditioner ', &
                tm(2), ' s, inner product and copy ', tm(3), ' s, transform pair ', tm(4), ' s'
            deallocate(x)
        end do
    end subroutine bench_profile

    ! the median seconds of the operator, the preconditioner, an inner product with its copy and a padded transform
    ! pair with its crop, each evaluated alone after one warm-up
    function piece_medians( rec, n ) result(tm)
        type(reconstructor_pcg), intent(inout) :: rec
        integer,                 intent(in)    :: n
        real(real64)    :: tm(4)
        type(mlx_array) :: v, y
        real(real32)    :: part(n * n)
        real(real64)    :: t(PROFILE_REPEATS + 1), t0
        integer         :: k, piece
        v = mlx_from(real(reshape(seeded_uniform(n**3, VOLUME_SEED), [n, n, n]), real32))
        call mlx_eval(v)
        do piece = 1, 4
            do k = 1, PROFILE_REPEATS + 1
                t0 = clock_s()
                select case( piece )
                    case( 1 )
                        y = rec%apply_normal(v)
                        call mlx_eval(y)
                    case( 2 )
                        y = rec%apply_precond(v)
                        call mlx_eval(y)
                    case( 3 )
                        y = rec%dot_real_volume(v, v)
                        call mlx_to(part, y)
                    case default
                        y = transform_pair(v, n)
                        call mlx_eval(y)
                end select
                t(k) = clock_s() - t0
            end do
            tm(piece) = median_of(t(2:))
        end do
    end function piece_medians

    ! the operator's transforms alone: the padded forward transform of v, its inverse and the crop
    function transform_pair( v, n ) result(y)
        type(mlx_array), intent(in) :: v
        integer,         intent(in) :: n
        type(mlx_array) :: y, s, g
        s = mlx_rfftn(v, n=[2*n, 2*n, 2*n])
        g = mlx_irfftn(s, n=[2*n, 2*n, 2*n])
        y = mlx_slice(g, [1, 1, 1], [n, n, n])
    end function transform_pair

    ! ---- suite=probe -----------------------------------------------------------------------------------------

    ! decisions 12, 13 and 18 per box on one device: the canonical driver under F2, F5 and F50 (time, waits, peak);
    ! the same solves' transforms alone with the same waits (t_fft) and f = 1 - t_fft / t_solve; the cost of a
    ! wait; every inner product of 50 iterations of system R in the forms S1 and S2 against S4, and the drift of
    ! the recursive residual without recomputation
    subroutine bench_probe
        type(bench_accum)               :: acc
        type(bench_case)                :: bc
        type(reconstructor_pcg), target :: rec
        integer, allocatable            :: ns(:)
        real(real64)                    :: t_fft, ts, wait_s
        integer                         :: in, ir, n
        ns = arg_boxes()
        call mlx_set_default_device(device_of_arg())
        bc%suite   = 'probe'
        bc%system  = 'P'
        bc%repeats = 3
        do in = 1, size(ns)
            n    = ns(in)
            bc%n = n
            call bench_fixture(n, arg_int('seed', 1), acc)
            deallocate(acc%b64, acc%d64)
            wait_s = wait_seconds(n)
                do ir = 1, size(PROBE_RULES)
                bc%rule = PROBE_RULES(ir)
                call time_rule(bc, acc)
                ts    = solve_seconds(rec, bc, acc)
                t_fft = fft_only_seconds(n, rule_options(trim(bc%rule)))
                write(*,'(a,i0,a,a,a,f0.6,a,f0.6,a,f0.4,a,f0.6,a)') 'probe n=', n, ' P ', trim(bc%rule), ': solve ', ts, &
                    ' s, transforms alone ', t_fft, ' s, f = ', 1._real64 - t_fft / ts, ', one wait ', wait_s, ' s'
            end do
            call dot_forms(rec, n, acc)
        end do
    end subroutine bench_probe

    ! the best of three solves of a case (the canonical driver's solve, timed from its start to the map on the host)
    real(real64) function solve_seconds( rec, bc, acc ) result(t)
        type(reconstructor_pcg), target, intent(inout) :: rec
        type(bench_case),                intent(in)    :: bc
        type(bench_accum),               intent(in)    :: acc
        type(bench_pass) :: ps
        integer          :: k
        t = huge(1._real64)
        do k = 1, 3
            call driver_pass(rec, bc, acc, ps)
            t = min(t, ps%ts)
        end do
    end function solve_seconds

    ! the transforms of a solve alone, with its waits: one pair and a wait before the loop, then per iteration a
    ! pair and a wait, and a pair and a wait unless no iteration follows; the best of three
    real(real64) function fft_only_seconds( n, o ) result(t)
        integer,                  intent(in) :: n
        type(pcg_solver_options), intent(in) :: o
        type(mlx_array) :: v, y, z
        real(real64)    :: t0
        integer         :: k, it
        v = mlx_from(real(reshape(seeded_uniform(n**3, VOLUME_SEED), [n, n, n]), real32))
        call mlx_eval(v)
        t = huge(1._real64)
        do k = 1, 4
            t0 = clock_s()
            z  = transform_pair(v, n)
            call mlx_eval(z)
            do it = 1, o%maxits
                y = transform_pair(z, n)
                call mlx_eval(y)
                if( it == o%maxits ) exit
                z = transform_pair(y, n)
                call mlx_eval(z)
            end do
            if( k > 1 ) t = min(t, clock_s() - t0)
        end do
    end function fft_only_seconds

    ! the cost of one wait: the evaluation and copy of n**2 partial sums whose inputs are evaluated, the median of
    ! WAIT_REPEATS
    real(real64) function wait_seconds( n ) result(t)
        integer, intent(in) :: n
        type(mlx_array) :: d, e
        real(real32)    :: part(n * n)
        real(real64)    :: ts(WAIT_REPEATS), t0
        integer         :: k
        d = mlx_from(real(reshape(seeded_uniform(n * n, VOLUME_SEED), [n, n]), real32))
        call mlx_eval(d)
        do k = 1, WAIT_REPEATS
            t0 = clock_s()
            e  = d * 1._real32
            call mlx_eval(e)
            call mlx_to(part, e)
            ts(k) = clock_s() - t0
        end do
        t = median_of(ts)
    end function wait_seconds

    ! 50 iterations of system R by the engine's recurrence (S2 forms the scalars), every inner product also by S1
    ! (one float32 sum on the device) and S4 (the host's double sum over views of the evaluated vectors); the
    ! largest relative error of each form against S4; then the drift |  |r_k| - |b - H x_k|  | / |b| at k = 5, 10,
    ! .., 50 without the recomputation
    subroutine dot_forms( rec, n, acc )
        type(reconstructor_pcg), target, intent(inout) :: rec
        integer,                         intent(in)    :: n
        type(bench_accum),               intent(in)    :: acc
        real(real64) :: es(2), drift(10)
        call bench_assemble(rec, n, 'R', acc)
        call probe_loop(rec, n, PCG_RESID_REPLACE, es, drift)
        write(*,'(a,i0,a,a,a,es11.4,a,es11.4)') 'probe n=', n, ' R ', device_name(device_of_arg()), &
            ': 250 inner products of 50 iterations, largest relative error against S4: S1 ', es(1), ', S2 ', es(2)
        call probe_loop(rec, n, huge(1), es, drift)
        write(*,'(a,i0,a,10es10.3)') 'probe n=', n, ' R drift without recomputation, k = 5 .. 50: ', drift
        call rec%kill()
    end subroutine dot_forms

    ! the engine's recurrence from zero for 50 iterations, the residual recomputed every `replace`
    subroutine probe_loop( rec, n, replace, es, drift )
        type(reconstructor_pcg), intent(inout) :: rec
        integer,                 intent(in)    :: n, replace
        real(real64),            intent(out)   :: es(2), drift(10)
        type(mlx_array)           :: b, x, r, p, hp, z, tr
        real(real32), allocatable :: bh(:,:,:), e(:,:,:), ie(:,:,:)
        real(real64)              :: rho, rho_new, phpv, alpha, dv(5), bnorm
        integer                   :: it, kd
        allocate(bh(n, n, n), e(n, n, n), ie(n, n, n))
        call rec%copy_volumes(bh, e, ie)
        b     = mlx_from(bh)
        x     = mlx_from(0._real32 * bh)
        r     = b
        z     = rec%apply_precond(r)
        p     = z
        es    = 0._real64
        drift = 0._real64
        kd    = 0
        bnorm = sqrt(dot_s4(b, b))
        rho   = dot_checked(rec, r, z, es)
        do it = 1, 50
            hp    = rec%apply_normal(p)
            phpv  = dot_checked(rec, p, hp, es)
            alpha = rho / phpv
            x     = x + real(alpha, real32) * p
            r     = r - real(alpha, real32) * hp
            if( modulo(it, replace) == 0 )then
                hp = rec%apply_normal(x)
                r  = b - hp
            endif
            dv(1) = dot_checked(rec, r, r, es)
            dv(2) = dot_checked(rec, x, x, es)
            dv(3) = dot_checked(rec, p, p, es)
            z     = rec%apply_precond(r)
            dv(4) = dot_checked(rec, r, z, es)
            if( modulo(it, 5) == 0 )then
                tr = b - rec%apply_normal(x)
                kd        = kd + 1
                drift(kd) = abs(sqrt(dot_s4(r, r)) - sqrt(dot_s4(tr, tr))) / bnorm
            endif
            rho_new = dv(4)
            p       = z + real(rho_new / rho, real32) * p
            rho     = rho_new
        end do
    end subroutine probe_loop

    ! a . b by S2 (the device's line sums added in double), its errors by S1 and S2 against S4 folded into es
    real(real64) function dot_checked( rec, a, b, es ) result(v)
        type(reconstructor_pcg), intent(inout) :: rec
        type(mlx_array),         intent(in)    :: a, b
        real(real64),            intent(inout) :: es(2)
        type(mlx_array)           :: d, s1
        real(real32), allocatable :: part(:)
        real(real32)              :: v1
        real(real64)              :: v4
        d  = rec%dot_real_volume(a, b)
        s1 = sum(a * b)
        call mlx_eval([d, s1])
        allocate(part(d%size()))
        call mlx_to(part, d)
        call mlx_item(s1, v1)
        v  = sum(real(part, real64))
        v4 = dot_s4(a, b)
        es(1) = max(es(1), abs(real(v1, real64) - v4) / abs(v4))
        es(2) = max(es(2), abs(v - v4) / abs(v4))
    end function dot_checked

    ! S4: the host's double sum of the products over views of the evaluated vectors (no copy)
    real(real64) function dot_s4( a, b ) result(v)
        type(mlx_array), intent(in) :: a, b
        real(real32), pointer :: pa(:,:,:), pb(:,:,:)
        integer               :: sa, sb
        nullify(pa, pb)
        call mlx_view(a, pa, sa)
        call mlx_view(b, pb, sb)
        if( sa /= 0 .or. sb /= 0 )then
            write(*,'(a)') 'bench_recon_pcg: S4 cannot be formed: a view of an evaluated vector was refused'
            error stop 2
        endif
        v = sum(real(pa, real64) * real(pb, real64))
    end function dot_s4

    ! ---- suite=accuracy ------------------------------------------------------------------------------------

    ! per box: the fixture, the oracle's system P, the device's assemblies under F2 and F5 (system P) and E and R4
    ! (system R); O2, O4 and O5 against the oracle; each final iterate's true residual by the oracle's apply against
    ! the device's own right-hand side (system R's ridge added on the host); gated where SIMPLE runs (F2, F5: the
    ! count, the reason and the reported residual against the true one), reported for E and R4
    subroutine bench_accuracy
        type(bench_accum)               :: acc
        type(reconstructor_pcg), target :: rec
        type(oracle_recon_problem)      :: prob
        type(pcg_solver_outcome)        :: oc
        integer, allocatable            :: ns(:)
        real(real32), allocatable       :: khat(:,:,:), pre(:,:,:), b(:,:,:), e(:,:,:), ie(:,:,:), x(:,:,:)
        real(real64), allocatable       :: kref(:,:,:), hu(:)
        real(real64)                    :: err, t0, lam_r, r
        type(pcg_solver_options)        :: o
        integer                         :: in, n, m, ir
        ns = arg_boxes()
        call mlx_set_default_device(device_of_arg())
        do in = 1, size(ns)
            n = ns(in)
            m = 2 * n
            call bench_fixture(n, arg_int('seed', 1), acc)
            t0 = clock_s()
            call prob%new(acc%d64, real(bench_mskrad(n), real64), real(PCG_LAMBDA, real64), .false.)
            write(*,'(a,i0,a,f0.1,a)') 'accuracy n=', n, ': the oracle''s system in ', clock_s() - t0, ' s'
            allocate(khat(n+1, m, m), pre(n+1, m, m), b(n, n, n), e(n, n, n), ie(n, n, n), x(n, n, n), hu(n**3))
            call bench_assemble(rec, n, 'P', acc)
            call rec%copy_spectra(khat, pre)
            call rec%copy_volumes(b, e, ie)
            kref = prob%kernel()
            err  = nan_maxval(abs(real(khat, real64) - kref(1:n+1, :, :))) / nan_maxval(abs(kref(1:n+1, :, :)))
            deallocate(kref)
            call accuracy_line('O2 kernel', n, err, tol('kernel'))
            err = rel2(real(reshape(b, [n**3]), real64), prob%rhs(acc%b64))
            call accuracy_line('O5 right-hand side', n, err, tol('rhs'))
            call rec%kill()
            ! O4: system R's ridge against 0.05 x 64 x the mean of D over the stored voxels with |q| <= n and
            ! ceiling(|q| / 2) <= 6, typed here from section 9.3
            lam_r = relative_ridge(acc%d64, n)
            call bench_assemble(rec, n, 'R', acc)
            err = abs(real(rec%get_effective_lambda(), real64) - lam_r) / lam_r
            call accuracy_line('O4 ridge', n, err, tol('ridge'))
            call rec%kill()
            do ir = 1, size(ACC_RULES)
                call bench_assemble(rec, n, ACC_SYSTEMS(ir), acc)
                call rec%copy_volumes(b, e, ie)
                call engine_solution(rec, rule_options(trim(ACC_RULES(ir))), x, oc)
                call rec%kill()
                t0 = clock_s()
                call prob%apply(real(reshape(x, [n**3]), real64), hu)
                if( ACC_SYSTEMS(ir) == 'R' ) hu = hu + (lam_r - real(PCG_LAMBDA, real64)) * &
                                              reshape(real(rec_mask(n), real64), [n**3]) * real(reshape(x, [n**3]), real64)
                r   = norm2(real(reshape(b, [n**3]), real64) - hu) / norm2(real(reshape(b, [n**3]), real64))
                err = abs(real(oc%final_rel_residual, real64) - r)
                write(*,'(a,i0,5a,i0,a,es12.5,a,es12.5,a,f0.1,a)') 'accuracy n=', n, ' ', ACC_SYSTEMS(ir), ' ', &
                    trim(ACC_RULES(ir)), ': ', oc%iteration_count, ' iterations ('//trim(oc%stop_reason)//'), true residual ', &
                    r, ', reported ', oc%final_rel_residual, ' (oracle apply ', clock_s() - t0, ' s)'
                if( ACC_SYSTEMS(ir) == 'P' )then
                    o = rule_options(trim(ACC_RULES(ir)))
                    call assert_true(oc%iteration_count == o%maxits .and. trim(oc%stop_reason) == 'fixed_iterations', &
                        'accuracy: '//trim(ACC_RULES(ir))//' runs exactly '//&
                        'its iterations at n = '//itoa(n))
                    call accuracy_line('reported residual '//trim(ACC_RULES(ir)), n, err, tol('residual history'))
                endif
            end do
            call prob%kill()
            deallocate(khat, pre, b, e, ie, x, hu)
        end do
    end subroutine bench_accuracy

    ! one judged error of the accuracy suite, printed and asserted
    subroutine accuracy_line( label, n, err, limit )
        character(len=*), intent(in) :: label
        integer,          intent(in) :: n
        real(real64),     intent(in) :: err, limit
        write(*,'(a,i0,a,a,a,es12.5,a,es10.3)') 'accuracy n=', n, ' ', label, ': ', err, ' tol ', limit
        call assert_true(err <= limit, 'accuracy: '//label//' within its frozen tolerance at n = '//itoa(n))
    end subroutine accuracy_line

    ! the binary support of a bench box (the toy's window > 0), for the host's ridge term
    function rec_mask( n ) result(msk)
        integer, intent(in) :: n
        real(real32), allocatable :: msk(:,:,:)
        type(reconstructor_pcg)   :: rec
        call rec%new(n)
        call rec%set_window_sphere(bench_mskrad(n))
        call rec%get_solve_support(msk)
        call rec%kill()
    end function rec_mask

    ! section 9.3's relative ridge: 0.05 x 64 x the mean of the packed density over the stored voxels with
    ! |q|**2 <= n**2 and ceiling(|q| / 2) <= 6
    real(real64) function relative_ridge( d, n ) result(lam)
        real(real64), intent(in) :: d(:,:,:)
        integer,      intent(in) :: n
        real(real64) :: total
        integer      :: i1, i2, i3, q2, cnt, m, k2, k3
        m     = 2 * n
        total = 0._real64
        cnt   = 0
        do i3 = 1, m
            k3 = i3 - 1
            if( k3 >= n ) k3 = k3 - m
            do i2 = 1, m
                k2 = i2 - 1
                if( k2 >= n ) k2 = k2 - m
                do i1 = 1, n + 1
                    q2 = (i1 - 1)**2 + k2**2 + k3**2
                    if( q2 > n * n ) cycle
                    if( ceiling(sqrt(real(q2, real64)) / 2._real64) > 6 ) cycle
                    total = total + d(i1, i2, i3)
                    cnt   = cnt + 1
                end do
            end do
        end do
        lam = real(RECON_PCG_LAMBDA_REL, real64) * 64._real64 * total / real(cnt, real64)
    end function relative_ridge

    ! the tolerance of a named gate: frozen, or its ceiling while it is not
    real(real64) function tol( name ) result(t)
        character(len=*), intent(in) :: name
        integer :: k
        t = -1._real64
        do k = 1, size(RECON_PCG_TOLERANCES)
            if( trim(RECON_PCG_TOLERANCES(k)%name) /= name ) cycle
            t = RECON_PCG_TOLERANCES(k)%ceiling
            if( RECON_PCG_TOLERANCES(k)%frozen > 0._real64 ) t = RECON_PCG_TOLERANCES(k)%frozen
        end do
    end function tol

    ! a relative error in the 2-norm
    real(real64) function rel2( a, ref ) result(e)
        real(real64), intent(in) :: a(:), ref(:)
        e = norm2(a - ref) / norm2(ref)
    end function rel2

end module mlxf_bench_recon_pcg
