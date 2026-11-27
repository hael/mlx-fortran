!@descr: the costs a porter meets: evaluation per step against batched, element reads, copies against the shared buffer, warm compiled callbacks
! mlxf_test_exec test=bench_user_costs suite=costs [device=cpu|gpu|all]. A measurement: it asserts nothing but the
! correctness of each route, checked outside the timing. Every case runs one warm-up and then REPEATS timed
! repeats; the median and the range of the time per call are printed with the device and MLX's runtime facts. The
! compiled callback's first application (its trace) is timed once and labelled cold.
module mlxf_bench_user_costs
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
use mlxf,             only: mlx_array, mlx_function, mlx_compile, mlx_from, mlx_to, mlx_item, mlx_alloc, mlx_view, &
                            mlx_eval, mlx_slice, mlx_set_default_device, mlxf_runtime_description, exp
use mlxf_test_defs,   only: USER_COST_TOL
use mlxf_test_reduce, only: nan_maxval
use mlxf_test_utils,  only: test_devices, device_name, set_fixed_seed, begin_test_suite, end_test_suite, assert_true, &
                            assert_int, bits_equal
implicit none
private

public :: run_bench_user_costs

! the timed repeats after one warm-up, the steps of the recurrence, the element reads, the calls of a callback,
! the extent of the small array, and the elements of the large one (64 MiB of float32)
integer, parameter :: REPEATS = 5, NSTEP = 200, NREAD = 200, NCALL = 200, NSMALL = 4096
integer, parameter :: NLARGE = 16777216

contains

    subroutine run_bench_user_costs( mode, found )
        character(len=*), intent(in)  :: mode
        logical,          intent(out) :: found
        integer, allocatable :: devs(:)
        integer              :: i
        found = trim(mode) == 'costs'
        if( .not. found ) return
        call test_devices(devs)
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            call begin_test_suite('user_costs_'//device_name(devs(i)))
            write(*,'(a)') '== bench_user_costs on the '//device_name(devs(i))//': '//mlxf_runtime_description()
            call cost_evaluation(device_name(devs(i)))
            call cost_reads(device_name(devs(i)))
            call cost_copies(device_name(devs(i)))
            call cost_compiled(device_name(devs(i)))
            call end_test_suite()
        end do
    end subroutine run_bench_user_costs

    ! a = a*0.999 + 0.001 over NSTEP steps of a small array, evaluated at every step or once at the end
    subroutine cost_evaluation( dev )
        character(len=*), intent(in) :: dev
        type(mlx_array) :: a
        real(real32)    :: x(NSMALL), y1(NSMALL), y2(NSMALL)
        real(real64)    :: t(0:REPEATS), w, ref(NSMALL)
        integer         :: rep, k, step
        call set_fixed_seed(31)
        call random_number(x)
        ! the host recurrence uses the same representable coefficients in double precision
        ref = real(x, real64)
        do step = 1, NSTEP
            ref = ref*real(0.999_real32, real64)+real(0.001_real32, real64)
        end do
        call recurrence(.true., y1)
        call recurrence(.false., y2)
        if( .not. check_values(y1, ref, USER_COST_TOL, 'per-step recurrence') ) return
        if( .not. check_values(y2, ref, USER_COST_TOL, 'batched recurrence') ) return
        do k = 1, 2
            do rep = 0, REPEATS
                w = clock()
                call recurrence(k == 1, y1)
                t(rep) = (clock()-w)/NSTEP
                if( .not. check_values(y1, ref, USER_COST_TOL, 'evaluated recurrence') ) return
            end do
            if( k == 1 )then
                call report('evaluation at every step', dev, t(1:), 'per step', NSTEP)
            else
                call report('steps evaluated once at the end', dev, t(1:), 'per step', NSTEP)
            endif
        end do
    contains
        subroutine recurrence( each, y )
            logical,      intent(in)  :: each
            real(real32), intent(out) :: y(:)
            integer :: s
            a = mlx_from(x)
            do s = 1, NSTEP
                a = a*0.999_real32+0.001_real32
                if( each ) call mlx_eval(a)
            end do
            call mlx_to(y, a)
        end subroutine recurrence

    end subroutine cost_evaluation

    ! NREAD single elements read with mlx_item of a one-element slice, against one copy of the whole array
    subroutine cost_reads( dev )
        character(len=*), intent(in) :: dev
        type(mlx_array) :: b
        real(real32)    :: x(NSMALL), y(NSMALL), values(NREAD)
        real(real64)    :: t(0:REPEATS), w
        integer         :: rep, i
        call set_fixed_seed(32)
        call random_number(x)
        b = mlx_from(x)
        call mlx_eval(b)
        do rep = 0, REPEATS
            w = clock()
            do i = 1, NREAD
                call mlx_item(mlx_slice(b, [i], [i]), values(i))
            end do
            t(rep) = (clock()-w)/NREAD
            if( .not. check_values(values, real(x(:NREAD), real64), 0._real64, 'element reads') ) return
        end do
        call report('one element by mlx_item(mlx_slice)', dev, t(1:), 'per element', NREAD)
        do rep = 0, REPEATS
            w = clock()
            do i = 1, NREAD
                call mlx_to(y, b)
            end do
            t(rep) = (clock()-w)/NREAD
            if( .not. check_values(y, real(x, real64), 0._real64, 'whole-array read') ) return
        end do
        call report('the whole 4096-element array by mlx_to', dev, t(1:), 'per copy', NREAD)
    end subroutine cost_reads

    ! r = 2a on 64 MiB of float32: in by mlx_from and out by mlx_to (two copies), against a buffer made by mlx_alloc,
    ! written through its view, and the result read through mlx_view (no copy where Metal accepts the buffer)
    subroutine cost_copies( dev )
        character(len=*), intent(in) :: dev
        type(mlx_array)           :: a, r
        real(real32), allocatable :: x(:), y(:)
        real(real32), pointer     :: p(:), q(:)
        real(real64)              :: t(0:REPEATS), w
        integer                   :: rep, k, st
        logical                   :: zero
        allocate(x(NLARGE), y(NLARGE))
        x = 1.5_real32
        do k = 1, 2
            do rep = 0, REPEATS
                w = clock()
                if( k == 1 )then
                    a = mlx_from(x)
                    r = a*2._real32
                    call mlx_to(y, r)
                else
                    a = mlx_alloc([NLARGE], 1._real32, p, status=st, zero_copy=zero)
                    if( .not. view_ok(p, st, 'shared input') ) return
                    p = x
                    r = a*2._real32
                    call mlx_view(r, q, status=st)
                    if( .not. view_ok(q, st, 'shared result') ) return
                    y(1) = q(NLARGE)
                endif
                t(rep) = clock()-w
                if( k == 1 )then
                    if( .not. check_constant(y, 3._real32, 'copy result') ) return
                else
                    if( .not. check_constant(q, 3._real32, 'shared result') ) return
                endif
                nullify(q)
                call r%kill()
                call a%kill()
                nullify(p)
            end do
            if( k == 1 )then
                call report('2a of 64 MiB: mlx_from, mlx_to', dev, t(1:), 'per round trip', 1)
            else
                call report('2a of 64 MiB: mlx_alloc, mlx_view', dev, t(1:), 'per round trip', 1)
                write(*,'(a,l1)') '    the mlx_alloc buffer was shared without a copy: ', zero
            endif
            write(*,'(a,f8.2,a)') '    that is ', 2._real64*4._real64*NLARGE/median(t(1:))/1.e9_real64, &
                &' GB/s of array data in and out'
        end do
    end subroutine cost_copies

    ! exp(x)*2 + 1 on a small array: the operations called directly, a Fortran callback applied through
    ! mlx_function, and the same function compiled; the compiled form's first application is its trace (cold)
    subroutine cost_compiled( dev )
        character(len=*), intent(in) :: dev
        type(mlx_function)           :: f, g
        type(mlx_array)              :: a, r
        type(mlx_array), allocatable :: outs(:)
        real(real32)                 :: x(NSMALL), y(NSMALL), z(NSMALL)
        real(real64)                 :: t(0:REPEATS), w, cold, ref(NSMALL)
        integer                      :: rep, k, i, st
        call set_fixed_seed(33)
        call random_number(x)
        ref = exp(real(x, real64))*2._real64+1._real64
        a = mlx_from(x)
        call mlx_eval(a)
        f = mlx_function(exp_affine)
        g = mlx_compile(f)
        w = clock()
        call g%apply([a], outs, status=st)
        if( .not. outputs_ok(outs, st, 'cold compiled callback') ) return
        call mlx_eval(outs)
        cold = clock()-w
        call mlx_to(z, outs(1))
        if( .not. check_values(z, ref, USER_COST_TOL, 'cold compiled callback') ) return
        write(*,'(a,f10.2,a)') '    cold: the compiled function''s first application (its trace) ', 1.e6_real64*cold, ' us'
        do k = 1, 3
            do rep = 0, REPEATS
                w = clock()
                do i = 1, NCALL
                    select case( k )
                        case( 1 )
                            r = exp(a)*2._real32+1._real32
                            call mlx_eval(r)
                        case( 2 )
                            call f%apply([a], outs, status=st)
                            if( .not. outputs_ok(outs, st, 'uncompiled callback') ) return
                            call mlx_eval(outs)
                        case default
                            call g%apply([a], outs, status=st)
                            if( .not. outputs_ok(outs, st, 'warm compiled callback') ) return
                            call mlx_eval(outs)
                    end select
                end do
                t(rep) = (clock()-w)/NCALL
                if( k == 1 )then
                    call mlx_to(y, r)
                else
                    call mlx_to(y, outs(1))
                endif
                if( .not. check_values(y, ref, USER_COST_TOL, 'evaluated expression') ) return
            end do
            select case( k )
                case( 1 )
                    call report('exp(x)*2+1 called directly, evaluated', dev, t(1:), 'per call', NCALL)
                case( 2 )
                    call report('the same through mlx_function', dev, t(1:), 'per call', NCALL)
                case default
                    call report('the same compiled, warm', dev, t(1:), 'per call', NCALL)
            end select
        end do
    end subroutine cost_compiled

    ! finite, correctly shaped results against independent host values; zero tolerance means byte identity
    logical function check_values( got, ref, tol, label ) result(ok)
        real(real32),     intent(in) :: got(:)
        real(real64),     intent(in) :: ref(:), tol
        character(len=*), intent(in) :: label
        ok = size(got) == size(ref)
        call assert_true(ok, label//' has the expected size')
        if( .not. ok ) return
        ok = all(ieee_is_finite(got))
        call assert_true(ok, label//' is finite')
        if( .not. ok ) return
        if( tol <= 0._real64 )then
            ok = all(bits_equal(got, real(ref, real32)))
        else
            ok = nan_maxval(abs(real(got, real64)-ref)/max(1._real64, abs(ref))) <= tol
        endif
        call assert_true(ok, label//' matches the host reference')
    end function check_values

    ! every element of the large copy fixture, including elements not read by the timed shared-view route
    logical function check_constant( got, ref, label ) result(ok)
        real(real32),     intent(in) :: got(:), ref
        character(len=*), intent(in) :: label
        ok = all(ieee_is_finite(got))
        call assert_true(ok, label//' is finite')
        if( .not. ok ) return
        ok = all(bits_equal(got, ref))
        call assert_true(ok, label//' matches the constant host reference')
    end function check_constant

    ! only failure records an assertion here, keeping the successful safety checks inside timing small
    logical function view_ok( view, status, label ) result(ok)
        real(real32),     pointer, intent(in) :: view(:)
        integer,          intent(in)          :: status
        character(len=*), intent(in)          :: label
        ok = .false.
        if( status /= 0 )then
            call assert_int(0, status, label//' succeeds')
            return
        endif
        if( .not. associated(view) )then
            call assert_true(.false., label//' returns an associated view')
            return
        endif
        if( size(view) /= NLARGE )then
            call assert_int(NLARGE, size(view), label//' has the expected size')
            return
        endif
        ok = .true.
    end function view_ok

    ! a callback failure or missing result is recorded before evaluation or indexing its output list
    logical function outputs_ok( outputs, status, label ) result(ok)
        type(mlx_array),  allocatable, intent(in) :: outputs(:)
        integer,          intent(in)              :: status
        character(len=*), intent(in)              :: label
        ok = .false.
        if( status /= 0 )then
            call assert_int(0, status, label//' succeeds')
            return
        endif
        if( .not. allocated(outputs) )then
            call assert_true(.false., label//' returns an allocated output list')
            return
        endif
        if( size(outputs) /= 1 )then
            call assert_int(1, size(outputs), label//' returns one output')
            return
        endif
        if( outputs(1)%ndim() /= 1 )then
            call assert_true(.false., label//' returns a vector')
            return
        endif
        if( outputs(1)%size() /= NSMALL )then
            call assert_true(.false., label//' returns the expected array size')
            return
        endif
        ok = .true.
    end function outputs_ok

    ! the callback: exp(x)*2 + 1 of the one input
    subroutine exp_affine( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 0
        allocate(outputs(1))
        outputs(1) = exp(inputs(1))*2._real32+1._real32
    end subroutine exp_affine

    ! one line: the case, the device, the median and range of the repeats in microseconds per unit
    subroutine report( label, dev, t, unit, calls )
        character(len=*), intent(in) :: label, dev, unit
        real(real64),     intent(in) :: t(:)
        integer,          intent(in) :: calls
        write(*,'(4x,a,a,a,a,f12.2,a,f12.2,a,f12.2,a,a,a,i0,a,i0,a)') label, ' [', dev, ']: median ', &
            &1.e6_real64*median(t), ' us, range ', 1.e6_real64*minval(t), ' to ', 1.e6_real64*maxval(t), ' us ', unit, &
            &' (', size(t), ' repeats of ', calls, ' after a warm-up)'
    end subroutine report

    ! the median of a few values
    function median( t ) result(m)
        real(real64), intent(in) :: t(:)
        real(real64) :: m, s(size(t)), v
        integer      :: i, j
        s = t
        do i = 2, size(s)
            v = s(i)
            j = i-1
            do while( j >= 1 )
                if( s(j) <= v ) exit
                s(j+1) = s(j)
                j = j-1
            end do
            s(j+1) = v
        end do
        m = s((size(s)+1)/2)
    end function median

    ! the wall clock in seconds
    function clock() result(secs)
        real(real64)   :: secs
        integer(int64) :: c, rate
        call system_clock(c, rate)
        secs = real(c, real64)/real(rate, real64)
    end function clock

end module mlxf_bench_user_costs
