!@descr: Fortran callbacks, byte-exact compiled results, shapeless reuse and callback error recovery
module mlxf_compile_tester
use, intrinsic :: iso_fortran_env, only: real32, int32
use mlxf,            only: mlx_array, mlx_function, mlx_compile, mlx_from, mlx_to, mlx_eval, mlx_live_count, &
                           mlx_last_error, mlx_set_default_device, mlx_default_device
use mlxf_test_utils, only: test_devices, device_name, assert_true, assert_int, bits_equal
implicit none
private
public :: run_all_compile_tests

contains

    subroutine run_all_compile_tests
        integer, allocatable :: devs(:)
        integer              :: i, original, live0
        write(*,'(a)') '**** running all compile tests ****'
        call test_empty_functions_parallel
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            call test_compiled_shapes
            call test_callback_errors
            call test_nested_apply
            call assert_int(live0, mlx_live_count(), 'function copies and callback arrays leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_compile_tests

    ! copying, killing and finalizing empty functions inside an OpenMP region does not stop
    subroutine test_empty_functions_parallel
        integer :: i, completed(8)
        write(*,'(a)') 'test_empty_functions_parallel'
        completed = 0
        !$omp parallel do num_threads(2) default(shared) private(i) schedule(static) proc_bind(close)
        do i = 1, size(completed)
            call empty_function_scope
            completed(i) = 1
        end do
        !$omp end parallel do
        call assert_true(all(completed == 1), 'empty function assignment, kill and finalization are safe in parallel')
    end subroutine test_empty_functions_parallel

    ! an empty function copied, killed and finalized on leaving the scope
    subroutine empty_function_scope
        type(mlx_function) :: f, copy
        copy = f
        call copy%kill()
    end subroutine empty_function_scope

    ! compiled and uncompiled callbacks agree byte for byte on values that are not binary fractions, a
    ! shapeless compilation traces once over two tile shapes, and a compiled copy outlives its original
    subroutine test_compiled_shapes
        type(mlx_function)           :: f, g, copy, compiled_copy, fixed
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: plain(:), fused(:)
        real(real32),    allocatable :: x(:,:), p(:,:), q(:,:)
        integer                      :: k, n, i, st, before, compiled_traces, j
        write(*,'(a)') 'test_compiled_shapes'
        f = mlx_function(elementwise)
        copy = f
        call f%kill()
        g = mlx_compile(copy, shapeless=.true.)
        compiled_copy = g
        call g%kill()
        compiled_traces = 0
        do k = 1, 2
            n = 7
            if( k == 2 ) n = 3
            allocate(x(4, n), p(4, n), q(4, n))
            x = reshape([(real(i, real32)/10, i=1, 4*n)], shape(x))
            a = mlx_from(x)
            call copy%apply([a], plain, status=st)
            if( st /= 0 ) write(*,'(a)') mlx_last_error()
            call assert_int(0, st, 'uncompiled Fortran callback returns status zero')
            before = compiled_copy%trace_count()
            call compiled_copy%apply([a], fused, status=st)
            if( st /= 0 ) write(*,'(a)') mlx_last_error()
            call assert_int(0, st, 'compiled callback returns status zero')
            compiled_traces = compiled_traces+compiled_copy%trace_count()-before
            if( st == 0 )then
                call assert_int(2, size(fused), 'compiled callback returns both outputs')
                do j = 1, 2
                    call mlx_to(p, plain(j))
                    call mlx_to(q, fused(j))
                    call assert_true(all(bits_equal(p, q)), 'nonbinary fixture: compiled and uncompiled outputs are byte-identical')
                    if( j == 1 )then
                        call assert_true(all(bits_equal(q, x*2+1)), 'compiled affine output has independent exact reference')
                    else
                        call assert_true(all(bits_equal(q, x*x)), 'compiled square output has independent exact reference')
                    endif
                end do
            endif
            deallocate(x, p, q)
        end do
        write(*,'(a,i0)') '    shapeless traces over (4,7) and (4,3): ', compiled_traces
        call assert_int(1, compiled_traces, 'two tile sizes trace exactly once with shapeless compilation')
        call copy%kill()
        call compiled_copy%apply([a], fused, status=st)
        call assert_int(0, st, 'compiled payload survives releasing the original function')
        call compiled_copy%kill()
        call compiled_copy%kill()
        call f%new(elementwise)
        fixed = mlx_compile(f)
        call fixed%apply([a], fused, status=st)
        call assert_int(0, st, 'default shaped compilation is usable')
        if( st == 0 ) call mlx_eval(fused)
    end subroutine test_compiled_shapes

    ! a failing callback, direct or while tracing, returns a status, publishes no outputs and leaves MLX
    ! usable; missing or empty outputs are refused without stopping inside C
    subroutine test_callback_errors
        type(mlx_function)            :: f, g
        type(mlx_array)               :: a
        type(mlx_array),  allocatable :: outputs(:)
        real(real32)                  :: x(4), y(4)
        integer                       :: st
        character(len=:), allocatable :: message
        write(*,'(a)') 'test_callback_errors'
        x = 1._real32
        a = mlx_from(x)
        f = mlx_function(failing_callback)
        call f%apply([a], outputs, status=st)
        call assert_true(st /= 0, 'checked failure inside callback returns through C as a status')
        call assert_true(.not. allocated(outputs), 'failed callback publishes no outputs')
        message = mlx_last_error()
        call assert_true(len(message) > 0, 'callback failure leaves an error message')
        g = mlx_compile(f, shapeless=.true.)
        call g%apply([a], outputs, status=st)
        call assert_true(st /= 0, 'failure during compiled tracing returns a status')
        call f%new(empty_result)
        call f%apply([a], outputs, status=st)
        call assert_true(st /= 0, 'empty callback output is checked without stopping in C')
        call f%new(no_outputs)
        call f%apply([a], outputs, status=st)
        call assert_true(st /= 0, 'unallocated callback output returns a status')
        call f%new(elementwise)
        g = mlx_compile(f, shapeless=.true.)
        call g%apply([a], outputs, status=st)
        call assert_int(0, st, 'MLX remains usable after callback failures')
        if( st == 0 )then
            call mlx_to(y, outputs(1), status=st)
            call assert_int(0, st, 'recovered graph evaluates')
            call assert_true(all(bits_equal(y, 3._real32)), 'recovered graph has correct values')
        endif
    end subroutine test_callback_errors

    ! a callback that applies another function works directly and compiled
    subroutine test_nested_apply
        type(mlx_function)           :: f, g
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: outputs(:)
        real(real32)                 :: x(3), y(3)
        integer                      :: st
        write(*,'(a)') 'test_nested_apply'
        x = [0.1_real32, 0.3_real32, 0.7_real32]
        a = mlx_from(x)
        f = mlx_function(nested_callback)
        call f%apply([a], outputs, status=st)
        call assert_int(0, st, 'a callback can apply another checked function')
        if( st == 0 )then
            call mlx_to(y, outputs(1))
            call assert_true(all(bits_equal(y, 2*x+1)), 'nested apply returns independent expected values')
        endif
        g = mlx_compile(f)
        call g%apply([a], outputs, status=st)
        call assert_int(0, st, 'compiled tracing supports a nested checked apply')
        if( st == 0 )then
            call mlx_to(y, outputs(1))
            call assert_true(all(bits_equal(y, 2*x+1)), 'compiled nested apply returns expected values')
        endif
    end subroutine test_nested_apply

    ! applies a fresh function to its inputs: the nested case
    subroutine nested_callback( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_function) :: inner
        inner = mlx_function(elementwise)
        call inner%apply(inputs, outputs, status=status)
    end subroutine nested_callback

    ! outputs 2x+1 and x*x of the first input: the compiled fixture
    subroutine elementwise( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        allocate(outputs(2))
        outputs(1) = inputs(1)*2._real32+1._real32
        outputs(2) = inputs(1)*inputs(1)
        status = 0
    end subroutine elementwise

    ! fails through a checked call: a copy into an array of the wrong kind
    subroutine failing_callback( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer(int32) :: wrong_kind(4)
        allocate(outputs(0))
        call mlx_to(wrong_kind, inputs(1), status=status)
    end subroutine failing_callback

    ! returns as many empty arrays as inputs, outputs the trampoline must refuse
    subroutine empty_result( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        allocate(outputs(size(inputs)))
        status = 0
    end subroutine empty_result

    ! returns success without allocating outputs
    subroutine no_outputs( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 0
    end subroutine no_outputs
end module mlxf_compile_tester
