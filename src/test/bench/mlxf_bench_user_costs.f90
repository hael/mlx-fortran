!@descr: the costs a porter meets: evaluation per step against batched, element reads, copies against the shared buffer, warm compiled callbacks
! mlxf_test_exec test=bench_user_costs suite=costs [device=cpu|gpu|all]. A measurement: it asserts nothing but the
! correctness of each route, checked once outside the timing. Every case runs one warm-up and then REPEATS timed
! repeats; the median and the range of the time per call are printed with the device and MLX's runtime facts. The
! compiled callback's first application (its trace) is timed once and labelled cold.
module mlxf_bench_user_costs
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,            only: mlx_array, mlx_function, mlx_compile, mlx_from, mlx_to, mlx_item, mlx_alloc, mlx_view, &
                           mlx_eval, mlx_slice, mlx_set_default_device, mlxf_runtime_description, MLX_DEVICES, exp
use mlxf_test_utils, only: test_devices, device_name, set_fixed_seed
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
        character(len=512)   :: arg
        integer              :: i
        found = trim(mode) == 'costs'
        if( .not. found ) return
        call test_devices(devs)
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            if( trim(arg) == 'device=cpu' ) devs = [MLX_DEVICES%cpu]
            if( trim(arg) == 'device=gpu' ) devs = pack(devs, devs == MLX_DEVICES%gpu)
        end do
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '== bench_user_costs on the '//device_name(devs(i))//': '//mlxf_runtime_description()
            call cost_evaluation(device_name(devs(i)))
            call cost_reads(device_name(devs(i)))
            call cost_copies(device_name(devs(i)))
            call cost_compiled(device_name(devs(i)))
        end do
    end subroutine run_bench_user_costs

    ! a = a*0.999 + 0.001 over NSTEP steps of a small array, evaluated at every step or once at the end
    subroutine cost_evaluation( dev )
        character(len=*), intent(in) :: dev
        type(mlx_array) :: a
        real(real32)    :: x(NSMALL), y1(NSMALL), y2(NSMALL)
        real(real64)    :: t(0:REPEATS), w
        integer         :: rep, k
        call set_fixed_seed(31)
        call random_number(x)
        ! correctness, outside the timing: both routes give the same values
        call recurrence(.true., y1)
        call recurrence(.false., y2)
        if( any(abs(y1-y2) > 1.e-5_real32) ) write(*,'(a)') '    WRONG: the two evaluation routes differ'
        do k = 1, 2
            do rep = 0, REPEATS
                w = clock()
                call recurrence(k == 1, y1)
                t(rep) = (clock()-w)/NSTEP
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
        real(real32)    :: x(NSMALL), y(NSMALL), v
        real(real64)    :: t(0:REPEATS), w
        integer         :: rep, i
        call set_fixed_seed(32)
        call random_number(x)
        b = mlx_from(x)
        call mlx_eval(b)
        call mlx_item(mlx_slice(b, [17], [17]), v)
        call mlx_to(y, b)
        if( abs(v-x(17)) > 0._real32 .or. any(abs(y-x) > 0._real32) ) write(*,'(a)') '    WRONG: a read differs'
        do rep = 0, REPEATS
            w = clock()
            do i = 1, NREAD
                call mlx_item(mlx_slice(b, [i], [i]), v)
            end do
            t(rep) = (clock()-w)/NREAD
        end do
        call report('one element by mlx_item(mlx_slice)', dev, t(1:), 'per element', NREAD)
        do rep = 0, REPEATS
            w = clock()
            do i = 1, NREAD
                call mlx_to(y, b)
            end do
            t(rep) = (clock()-w)/NREAD
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
                    p = x
                    r = a*2._real32
                    call mlx_view(r, q, status=st)
                    y(1) = q(NLARGE)
                endif
                t(rep) = clock()-w
                if( rep == 0 .and. k == 1 .and. any(abs(y-3._real32) > 0._real32) ) write(*,'(a)') '    WRONG: copy route'
                if( rep == 0 .and. k == 2 .and. abs(y(1)-3._real32) > 0._real32 ) write(*,'(a)') '    WRONG: shared route'
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
        real(real64)                 :: t(0:REPEATS), w, cold
        integer                      :: rep, k, i, st
        call set_fixed_seed(33)
        call random_number(x)
        a = mlx_from(x)
        call mlx_eval(a)
        f = mlx_function(exp_affine)
        g = mlx_compile(f)
        w = clock()
        call g%apply([a], outs, status=st)
        call mlx_eval(outs)
        cold = clock()-w
        call mlx_to(z, outs(1))
        r = exp(a)*2._real32+1._real32
        call mlx_to(y, r)
        if( st /= 0 .or. any(abs(y-z) > 1.e-5_real32*abs(y)) ) write(*,'(a)') '    WRONG: the compiled form differs'
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
                            call mlx_eval(outs)
                        case default
                            call g%apply([a], outs, status=st)
                            call mlx_eval(outs)
                    end select
                end do
                t(rep) = (clock()-w)/NCALL
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
