!@descr: assertions, suite tracking and the summary of mlxf_test_exec
! Adapted from SIMPLE's simple_test_utils: same names and output, without SIMPLE's types.
module mlxf_test_utils
use, intrinsic :: iso_fortran_env, only: output_unit, int32, int64, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
use mlxf,             only: MLX_DEVICES, MLX_DTYPES, mlx_array, mlx_from, mlx_to, reshape, mlx_device_count, &
                            mlx_default_device
use mlxf_test_defs,   only: elem_tolerance, ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED
use mlxf_test_reduce, only: nan_maxval
implicit none
private

public :: assert_true, assert_false, assert_int, assert_real, assert_double, assert_char
public :: begin_test_suite, end_test_suite, report_summary
public :: tests_run, tests_failed
public :: set_fixed_seed, bits_equal, test_devices, device_name
public :: judge_error, find_tolerance, family_seeds, seeded_uniform, seeded_array, shaped_error

integer, parameter :: MSGLEN = 512

type :: test_suite_result
    character(len=MSGLEN) :: name      = ''
    integer               :: checks    = 0
    integer               :: failures  = 0
    logical               :: completed = .false.
    integer(int64)        :: t_start   = 0_int64
    real                  :: seconds   = 0.
end type test_suite_result

type :: test_failure
    character(len=MSGLEN) :: suite   = ''
    character(len=MSGLEN) :: message = ''
end type test_failure

interface bits_equal
    module procedure bits_equal_r32, bits_equal_r64, bits_equal_c32
end interface bits_equal

! a seeded operand of any rank up to five, float64 when wide and rounded to float32 otherwise
interface seeded_array
    module procedure seeded_array1, seeded_array2, seeded_array3, seeded_array4, seeded_array5
end interface seeded_array

! a result's largest error against a reference relative to max(1, bound); the reference's shape is the shape the
! result must have, and a result of another shape or dtype gives huge
interface shaped_error
    module procedure shaped_error0, shaped_error1, shaped_error2, shaped_error3, shaped_error4, shaped_error5
end interface shaped_error

integer :: tests_run    = 0
integer :: tests_failed = 0
integer :: active_suite = 0
type(test_suite_result), allocatable :: suites(:)
type(test_failure),      allocatable :: failures(:)

contains

    ! storage identity of reals, NaN payloads and signed zeros included (never == on reals)
    elemental logical function bits_equal_r32( a, b )
        real(real32), intent(in) :: a, b
        bits_equal_r32 = transfer(a, 0_int32) == transfer(b, 0_int32)
    end function bits_equal_r32

    elemental logical function bits_equal_r64( a, b )
        real(real64), intent(in) :: a, b
        bits_equal_r64 = transfer(a, 0_int64) == transfer(b, 0_int64)
    end function bits_equal_r64

    elemental logical function bits_equal_c32( a, b )
        complex(real32), intent(in) :: a, b
        bits_equal_c32 = transfer(a, 0_int64) == transfer(b, 0_int64)
    end function bits_equal_c32

    ! the devices this run tests on: those named by device=cpu|gpu|all (default all) that can allocate.
    ! Without a GPU a Metal build of MLX allocates on neither device: the tests are skipped, and a run built
    ! with MLXF_REQUIRE_GPU records a failure instead.
    subroutine test_devices( devs )
        integer, allocatable, intent(out) :: devs(:)
        character(len=64) :: arg, which
        integer           :: i
        logical           :: gpu
        which = 'all'
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            if( index(arg, 'device=') == 1 ) which = arg(8:)
        end do
        gpu = mlx_device_count(MLX_DEVICES%gpu) > 0
        allocate(devs(0))
        if( .not. gpu )then
#ifdef MLXF_REQUIRE_GPU
            call record_assertion(.false., 'a GPU device can be opened (MLXF_REQUIRE_GPU): none in this session')
#else
            write(output_unit,'(A)') '    SKIP: no GPU device in this session; a Metal build of MLX cannot allocate'
#endif
            return
        endif
        select case( trim(which) )
            case( 'cpu' )
                devs = [MLX_DEVICES%cpu]
            case( 'gpu' )
                devs = [MLX_DEVICES%gpu]
            case default
                devs = [MLX_DEVICES%cpu, MLX_DEVICES%gpu]
        end select
    end subroutine test_devices

    function device_name( dev ) result(name)
        integer, intent(in) :: dev
        character(len=:), allocatable :: name
        name = 'cpu'
        if( dev == MLX_DEVICES%gpu ) name = 'gpu'
    end function device_name

    ! one measured error against its frozen tolerance, printed in float32 epsilons for the calibration record
    subroutine judge_error( err, tol, label, dtype, seed )
        real(real64),     intent(in) :: err, tol
        character(len=*), intent(in) :: label, dtype
        integer,          intent(in) :: seed
        character(len=160) :: line
        write(line,'(A,I0,A,ES16.9,A,F8.3,A)') '    error '//trim(label)//' '//device_name(mlx_default_device())// &
            &' '//dtype//' seed=', seed, ': ', err, ' (', err/real(epsilon(1._real32), real64), ' eps32)'
        write(output_unit,'(A)') trim(line)
        call record_assertion(err <= tol, trim(label)//' '//dtype//' within its frozen tolerance on the '// &
            &device_name(mlx_default_device()))
    end subroutine judge_error

    ! the frozen tolerances of a function in a table (zero, failing every inexact check, when it has none)
    function find_tolerance( table, name ) result(t)
        type(elem_tolerance), intent(in) :: table(:)
        character(len=*),     intent(in) :: name
        type(elem_tolerance) :: t
        integer              :: k
        t = elem_tolerance(name, 0._real64, 0._real64)
        do k = 1, size(table)
            if( trim(table(k)%name) == trim(name) ) t = table(k)
        end do
    end function find_tolerance

    ! the seeds a calibrated family runs: the calibration seed, then the judged ones
    function family_seeds() result(seeds)
        integer, allocatable :: seeds(:)
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
    end function family_seeds

    ! n values from a fixed seed, uniform in [-1, 1] and rounded once to float32, so that a float32 and a float64
    ! operand hold the same numbers
    function seeded_uniform( n, seed ) result(x)
        integer, intent(in) :: n, seed
        real(real64) :: x(n)
        call set_fixed_seed(seed)
        call random_number(x)
        x = real(real(2*x-1, real32), real64)
    end function seeded_uniform

    ! the array of Fortran shape shp that holds x in array element order: float64 when wide, else rounded to float32
    function flat_array( x, shp, wide ) result(a)
        real(real64), intent(in) :: x(:)
        integer,      intent(in) :: shp(:)
        logical,      intent(in) :: wide
        type(mlx_array) :: a, flat
        if( wide )then
            flat = mlx_from(x)
        else
            flat = mlx_from(real(x, real32))
        endif
        a = reshape(flat, shp)
    end function flat_array

    function seeded_array1( x, wide ) result(a)
        real(real64), intent(in) :: x(:)
        logical,      intent(in) :: wide
        type(mlx_array) :: a
        a = flat_array(reshape(x, [size(x)]), shape(x), wide)
    end function seeded_array1

    function seeded_array2( x, wide ) result(a)
        real(real64), intent(in) :: x(:,:)
        logical,      intent(in) :: wide
        type(mlx_array) :: a
        a = flat_array(reshape(x, [size(x)]), shape(x), wide)
    end function seeded_array2

    function seeded_array3( x, wide ) result(a)
        real(real64), intent(in) :: x(:,:,:)
        logical,      intent(in) :: wide
        type(mlx_array) :: a
        a = flat_array(reshape(x, [size(x)]), shape(x), wide)
    end function seeded_array3

    function seeded_array4( x, wide ) result(a)
        real(real64), intent(in) :: x(:,:,:,:)
        logical,      intent(in) :: wide
        type(mlx_array) :: a
        a = flat_array(reshape(x, [size(x)]), shape(x), wide)
    end function seeded_array4

    function seeded_array5( x, wide ) result(a)
        real(real64), intent(in) :: x(:,:,:,:,:)
        logical,      intent(in) :: wide
        type(mlx_array) :: a
        a = flat_array(reshape(x, [size(x)]), shape(x), wide)
    end function seeded_array5

    ! the largest error of a float32 or float64 result against ref, in array element order, relative to
    ! max(1, bound); huge when r has another shape than want, another dtype or cannot be read, or when ref or
    ! bound is not finite; +infinity when the result holds a NaN or an infinity (nan_maxval)
    function flat_error( r, want, ref, bound ) result(err)
        type(mlx_array), intent(in) :: r
        integer,         intent(in) :: want(:)
        real(real64),    intent(in) :: ref(:), bound(:)
        real(real64)              :: err
        real(real32), allocatable :: got32(:)
        real(real64), allocatable :: got(:)
        integer,      allocatable :: sh(:)
        integer                   :: st
        err = huge(1._real64)
        sh = r%shape()
        if( size(sh) /= size(want) ) return
        if( any(sh /= want) ) return
        allocate(got(size(ref)))
        if( r%kind() == MLX_DTYPES%float64 )then
            call mlx_to(got, r, status=st)
        else if( r%kind() == MLX_DTYPES%float32 )then
            allocate(got32(size(ref)))
            call mlx_to(got32, r, status=st)
            got = real(got32, real64)
        else
            return
        endif
        if( st /= 0 ) return
        if( .not. all(ieee_is_finite(ref)) ) return
        if( .not. all(ieee_is_finite(bound)) ) return
        err = 0._real64
        if( size(ref) > 0 ) err = nan_maxval(abs(got-ref)/max(1._real64, bound))
    end function flat_error

    function shaped_error0( r, ref, bound ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref, bound
        real(real64) :: err
        integer      :: none(0)
        err = flat_error(r, none, [ref], [bound])
    end function shaped_error0

    function shaped_error1( r, ref, bound ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref(:), bound(:)
        real(real64) :: err
        err = flat_error(r, shape(ref), reshape(ref, [size(ref)]), reshape(bound, [size(bound)]))
    end function shaped_error1

    function shaped_error2( r, ref, bound ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref(:,:), bound(:,:)
        real(real64) :: err
        err = flat_error(r, shape(ref), reshape(ref, [size(ref)]), reshape(bound, [size(bound)]))
    end function shaped_error2

    function shaped_error3( r, ref, bound ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref(:,:,:), bound(:,:,:)
        real(real64) :: err
        err = flat_error(r, shape(ref), reshape(ref, [size(ref)]), reshape(bound, [size(bound)]))
    end function shaped_error3

    function shaped_error4( r, ref, bound ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref(:,:,:,:), bound(:,:,:,:)
        real(real64) :: err
        err = flat_error(r, shape(ref), reshape(ref, [size(ref)]), reshape(bound, [size(bound)]))
    end function shaped_error4

    function shaped_error5( r, ref, bound ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64) :: err
        err = flat_error(r, shape(ref), reshape(ref, [size(ref)]), reshape(bound, [size(bound)]))
    end function shaped_error5

    ! seeds the intrinsic generator with a fixed, reproducible state derived from base_seed
    subroutine set_fixed_seed( base_seed )
        integer, intent(in) :: base_seed
        integer, allocatable :: seed(:)
        integer              :: n, i
        call random_seed(size=n)
        allocate(seed(n))
        do i = 1, n
            seed(i) = int(modulo(int(base_seed, int64) + 2654435761_int64 * int(i, int64), 2147483647_int64))
        end do
        call random_seed(put=seed)
    end subroutine set_fixed_seed

    subroutine begin_test_suite( name )
        character(len=*), intent(in) :: name
        type(test_suite_result) :: suite
        if( active_suite > 0 ) call end_test_suite
        suite%name = trim(name)
        if( allocated(suites) )then
            suites = [suites, suite]
        else
            allocate(suites(1))
            suites(1) = suite
        endif
        active_suite = size(suites)
        call system_clock(suites(active_suite)%t_start)
        write(output_unit,'(A)') '---- TEST SUITE: '//trim(suite%name)//' ----'
    end subroutine begin_test_suite

    subroutine end_test_suite
        character(len=MSGLEN) :: name
        character(len=32)     :: tstr
        integer               :: checks, nfailed
        integer(int64)        :: t_end, rate
        if( active_suite == 0 ) return
        call system_clock(t_end, rate)
        if( rate > 0_int64 ) suites(active_suite)%seconds = real(t_end - suites(active_suite)%t_start) / real(rate)
        write(tstr,'(F0.2,A)') suites(active_suite)%seconds, ' s'
        name    = suites(active_suite)%name
        checks  = suites(active_suite)%checks
        nfailed = suites(active_suite)%failures
        if( nfailed == 0 )then
            write(output_unit,'(A,I0,A)') 'PASS: '//trim(name)//' (', checks, ' checks, '//trim(tstr)//')'
        else
            write(output_unit,'(A,I0,A,I0,A)') 'FAIL: '//trim(name)//' (', nfailed, ' of ', checks, &
                &' checks failed, '//trim(tstr)//')'
        endif
        suites(active_suite)%completed = .true.
        active_suite = 0
    end subroutine end_test_suite

    subroutine assert_true( cond, msg )
        logical,          intent(in) :: cond
        character(len=*), intent(in) :: msg
        call record_assertion(cond, msg)
    end subroutine assert_true

    subroutine assert_false( cond, msg )
        logical,          intent(in) :: cond
        character(len=*), intent(in) :: msg
        call record_assertion(.not. cond, msg)
    end subroutine assert_false

    subroutine assert_int( expected, actual, msg )
        integer,          intent(in) :: expected, actual
        character(len=*), intent(in) :: msg
        character(len=MSGLEN) :: detail
        if( expected == actual )then
            call record_assertion(.true., msg)
        else
            write(detail,'(A,I0,A,I0)') trim(msg)//' expected=', expected, ' actual=', actual
            call record_assertion(.false., detail)
        endif
    end subroutine assert_int

    ! |expected - actual| <= tol in single precision
    subroutine assert_real( expected, actual, tol, msg )
        real(real32),     intent(in) :: expected, actual, tol
        character(len=*), intent(in) :: msg
        character(len=MSGLEN) :: detail
        if( abs(expected - actual) <= tol )then
            call record_assertion(.true., msg)
        else
            write(detail,'(A,G0,A,G0,A,G0)') trim(msg)//' expected=', expected, ' actual=', actual, ' tolerance=', tol
            call record_assertion(.false., detail)
        endif
    end subroutine assert_real

    ! |expected - actual| <= tol in double precision
    subroutine assert_double( expected, actual, tol, msg )
        real(real64),     intent(in) :: expected, actual, tol
        character(len=*), intent(in) :: msg
        character(len=MSGLEN) :: detail
        if( abs(expected - actual) <= tol )then
            call record_assertion(.true., msg)
        else
            write(detail,'(A,ES24.16,A,ES24.16,A,ES14.6)') trim(msg)//' expected=', expected, &
                &' actual=', actual, ' tolerance=', tol
            call record_assertion(.false., detail)
        endif
    end subroutine assert_double

    subroutine assert_char( expected, actual, msg )
        character(len=*), intent(in) :: expected, actual, msg
        character(len=MSGLEN) :: detail
        if( trim(expected) == trim(actual) )then
            call record_assertion(.true., msg)
        else
            detail = trim(msg)//' expected="'//trim(expected)//'" actual="'//trim(actual)//'"'
            call record_assertion(.false., detail)
        endif
    end subroutine assert_char

    subroutine record_assertion( passed, message )
        logical,          intent(in) :: passed
        character(len=*), intent(in) :: message
        type(test_failure) :: failure
        tests_run = tests_run + 1
        if( active_suite > 0 ) suites(active_suite)%checks = suites(active_suite)%checks + 1
        if( passed ) return
        tests_failed    = tests_failed + 1
        failure%message = trim(message)
        if( active_suite > 0 )then
            suites(active_suite)%failures = suites(active_suite)%failures + 1
            failure%suite = suites(active_suite)%name
        else
            failure%suite = 'unscoped'
        endif
        if( allocated(failures) )then
            failures = [failures, failure]
        else
            allocate(failures(1))
            failures(1) = failure
        endif
        write(output_unit,'(A)') 'FAIL: '//trim(failure%message)
    end subroutine record_assertion

    ! closes an open suite, prints the summary and says whether any assertion failed
    subroutine report_summary( failed )
        logical, intent(out) :: failed
        integer :: i, nsuites, npassed, nfailed
        if( active_suite > 0 ) call end_test_suite
        nsuites = 0
        npassed = 0
        nfailed = 0
        if( allocated(suites) )then
            nsuites = size(suites)
            npassed = count(suites%completed .and. suites%failures == 0)
            nfailed = count(suites%completed .and. suites%failures > 0)
        endif
        write(output_unit,'(A)') ''
        write(output_unit,'(A)') '========== MLXF TEST SUMMARY =========='
        if( tests_failed == 0 )then
            write(output_unit,'(A)') 'RESULT: PASS'
        else
            write(output_unit,'(A)') 'RESULT: FAIL'
        endif
        write(output_unit,'(A,I0,A,I0,A,I0,A)') 'Test groups: ', nsuites, ' run; ', npassed, ' passed; ', &
            &nfailed, ' failed.'
        write(output_unit,'(A,I0,A,I0,A,I0,A)') 'Assertions: ', tests_run, ' evaluated; ', &
            &tests_run - tests_failed, ' passed; ', tests_failed, ' failed.'
        if( allocated(failures) )then
            write(output_unit,'(A)') 'Failures:'
            do i = 1, size(failures)
                write(output_unit,'(A)') '  ['//trim(failures(i)%suite)//'] '//trim(failures(i)%message)
            enddo
        endif
        write(output_unit,'(A)') '======================================='
        failed = tests_failed > 0
    end subroutine report_summary

end module mlxf_test_utils
