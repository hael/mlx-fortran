!@descr: exported and imported functions, one trace and several, and the compilation controls, against the callback's own results
! A function is written to a file in the test's working directory, read back and applied: the imported graph
! must give the callback's values, bit for bit on arithmetic that is exact. The files are deleted. The
! compilation controls are judged by how often the callback runs.
module mlxf_export_tester
use, intrinsic :: iso_fortran_env, only: real32
use mlxf,            only: mlx_array, mlx_function, mlx_compile, mlx_export_function, mlx_function_exporter, &
                           mlx_imported_function, mlx_enable_compile, mlx_disable_compile, mlx_set_compile_mode, &
                           MLX_COMPILE_MODES, mlx_from, mlx_to, mlx_live_count, mlx_last_error, mlx_set_default_device, &
                           mlx_default_device
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, bits_equal
implicit none
private
public :: run_all_export_tests

contains

    subroutine run_all_export_tests
        integer, allocatable :: devs(:)
        integer              :: i, original, live0
        write(*,'(a)') '**** running all export tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            call test_export_import
            call test_exporter_traces
            call test_file_failures
            call test_compile_controls
            call assert_int(live0, mlx_live_count(), 'exporters, imported functions and their arrays leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_export_tests

    ! a function exported on one example and read back gives the callback's values on other values of that shape
    subroutine test_export_import
        type(mlx_function)            :: f
        type(mlx_imported_function)   :: g, copy
        type(mlx_array)               :: a, b, c
        type(mlx_array),  allocatable :: outputs(:)
        real(real32)                  :: x(3, 2), y(3, 2), z(2, 5), got(3, 2), wide(2, 5)
        integer                       :: st, live0
        character(len=*), parameter   :: FIXED = 'mlxf_export_fixed.mlxfn', LOOSE = 'mlxf_export_shapeless.mlxfn'
        write(*,'(a)') 'test_export_import'
        x = reshape([1._real32, 2._real32, 3._real32, 4._real32, 5._real32, 6._real32], [3, 2])
        y = reshape([0.5_real32, -1._real32, 8._real32, 2.25_real32, -3._real32, 7._real32], [3, 2])
        z = 1.5_real32
        a = mlx_from(x)
        b = mlx_from(y)
        c = mlx_from(z)
        f = mlx_function(affine)
        call mlx_export_function(FIXED, f, [a], status=st)
        call assert_int(0, st, 'a function is exported on an example input')
        live0 = mlx_live_count()
        g = mlx_imported_function(FIXED)
        call assert_int(live0+1, mlx_live_count(), 'an imported function is one live object')
        copy = g
        call assert_int(live0+1, mlx_live_count(), 'a copy of an imported function shares the object')
        call g%kill()
        call g%kill()
        call copy%apply([b], outputs, status=st)
        call assert_int(0, st, 'the imported function applies to other values of the exported shape')
        if( st == 0 )then
            call assert_int(2, size(outputs), 'the imported function returns the callback''s two outputs')
            call assert_true(all(outputs(1)%shape() == [3, 2]), 'an output read back has its Fortran shape')
            call mlx_to(got, outputs(1))
            call assert_true(all(bits_equal(got, 2._real32*y+1._real32)), 'the first output is 2 y + 1, bit for bit')
            call mlx_to(got, outputs(2))
            call assert_true(all(bits_equal(got, y*y)), 'the second output is y squared, bit for bit')
        endif
        call copy%apply([c], outputs, status=st)
        call assert_true(st /= 0, 'a function exported for one shape refuses another, with a status')
        call assert_true(.not. allocated(outputs), 'a refused application publishes no outputs')
        call assert_true(len(mlx_last_error()) > 0, 'the refusal leaves a message')
        call copy%kill()
        call assert_int(live0, mlx_live_count(), 'killing the last copy frees the imported function')
        call mlx_export_function(LOOSE, f, [a], shapeless=.true., status=st)
        call assert_int(0, st, 'a function is exported shapeless')
        call g%new(LOOSE, status=st)
        call assert_int(0, st, 'the shapeless export is read back through the checked constructor')
        call g%apply([c], outputs, status=st)
        call assert_int(0, st, 'a shapeless export applies to another shape of the same rank')
        if( st == 0 )then
            call mlx_to(wide, outputs(1))
            call assert_true(all(bits_equal(wide, 4._real32)), 'and gives 2 z + 1 there')
        endif
        call remove(FIXED)
        call remove(LOOSE)
    end subroutine test_export_import

    ! an exporter writes one trace per application: the file then serves each of the traced signatures
    subroutine test_exporter_traces
        type(mlx_function)            :: f
        type(mlx_function_exporter)   :: e, copy
        type(mlx_imported_function)   :: g
        type(mlx_array)               :: a, b
        type(mlx_array),  allocatable :: outputs(:)
        real(real32)                  :: x(3), y(2, 2), got(3), square(2, 2)
        integer                       :: st, live0
        character(len=*), parameter   :: TRACES = 'mlxf_export_traces.mlxfn'
        write(*,'(a)') 'test_exporter_traces'
        x = [1._real32, 2._real32, 3._real32]
        y = reshape([1._real32, -2._real32, 4._real32, 0.5_real32], [2, 2])
        a = mlx_from(x)
        b = mlx_from(y)
        f = mlx_function(affine)
        live0 = mlx_live_count()
        e = mlx_function_exporter(TRACES, f)
        call assert_int(live0+1, mlx_live_count(), 'an exporter is one live object')
        copy = e
        call e%kill()
        call copy%apply([a], status=st)
        call assert_int(0, st, 'the exporter writes a trace for a rank-1 input')
        call copy%apply([b], status=st)
        call assert_int(0, st, 'and another for a rank-2 input')
        call copy%kill()
        call copy%kill()
        call assert_int(live0, mlx_live_count(), 'killing the last copy closes the exporter')
        call g%new(TRACES, status=st)
        call assert_int(0, st, 'the file of two traces is read back')
        call g%apply([a], outputs, status=st)
        call assert_int(0, st, 'the imported function serves the first trace')
        if( st == 0 )then
            call mlx_to(got, outputs(1))
            call assert_true(all(bits_equal(got, 2._real32*x+1._real32)), 'with the callback''s values')
        endif
        call g%apply([b], outputs, status=st)
        call assert_int(0, st, 'and the second trace')
        if( st == 0 )then
            call mlx_to(square, outputs(2))
            call assert_true(all(bits_equal(square, y*y)), 'with the callback''s values in the Fortran layout')
        endif
        call remove(TRACES)
        call e%new(TRACES, f, shapeless=.true., status=st)
        call assert_int(0, st, 'a shapeless exporter is made through the checked constructor')
        call e%apply([a], status=st)
        call assert_int(0, st, 'and writes its trace')
        call e%kill()
        call g%new(TRACES, status=st)
        b = mlx_from([4._real32, 5._real32])
        call g%apply([b], outputs, status=st)
        call assert_int(0, st, 'the shapeless trace serves a rank-1 input of another extent')
        call remove(TRACES)
        f = mlx_function(failing)
        call e%new(TRACES, f, status=st)
        copy = e
        call e%apply([a], status=st)
        call assert_true(st /= 0, 'a callback that fails in an exporter returns its status')
        call copy%apply([a], status=st)
        call assert_true(st /= 0, 'after a failed trace every copy of the exporter refuses another, with a status')
        call assert_true(index(mlx_last_error(), 'make a new exporter') > 0, 'and says to make a new exporter')
        call e%kill()
        call copy%kill()
        call remove(TRACES)
    end subroutine test_exporter_traces

    ! what a file cannot give is a status, with MLX usable afterwards
    subroutine test_file_failures
        type(mlx_function)          :: f
        type(mlx_imported_function) :: g
        type(mlx_function_exporter) :: e
        type(mlx_array)             :: a
        real(real32)                :: x(3)
        integer                     :: st, live0
        write(*,'(a)') 'test_file_failures'
        x = 1._real32
        a = mlx_from(x)
        f = mlx_function(affine)
        live0 = mlx_live_count()
        call g%new('mlxf_no_such_file.mlxfn', status=st)
        call assert_true(st /= 0, 'a file that does not exist is refused with a status')
        call assert_true(len(mlx_last_error()) > 0, 'and a message')
        call assert_int(live0, mlx_live_count(), 'a refused import leaves no object')
        call mlx_export_function('mlxf_no_such_directory/f.mlxfn', f, [a], status=st)
        call assert_true(st /= 0, 'a file that cannot be written is refused with a status')
        call e%new('mlxf_no_such_directory/f.mlxfn', f, status=st)
        if( st == 0 ) call e%apply([a], status=st)
        call assert_true(st /= 0, 'an exporter to a file that cannot be written is refused, at once or at its first trace')
        call e%kill()
        f = mlx_function(failing)
        call mlx_export_function('mlxf_export_failing.mlxfn', f, [a], status=st)
        call assert_true(st /= 0, 'a callback that fails during the export returns its status')
        call remove('mlxf_export_failing.mlxfn')
    end subroutine test_file_failures

    ! with compilation disabled a compiled function runs its callback at every call; enabled, once per signature
    subroutine test_compile_controls
        type(mlx_function)           :: f, g
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: outputs(:)
        real(real32)                 :: x(3), got(3)
        integer                      :: before, modes(3), k
        write(*,'(a)') 'test_compile_controls'
        x = [1._real32, 2._real32, 3._real32]
        a = mlx_from(x)
        f = mlx_function(affine)
        call mlx_disable_compile()
        g = mlx_compile(f)
        before = g%trace_count()
        call g%apply([a], outputs)
        call g%apply([a], outputs)
        call assert_int(before+2, g%trace_count(), 'with compilation disabled the callback runs at every call')
        call mlx_to(got, outputs(1))
        call assert_true(all(bits_equal(got, 2._real32*x+1._real32)), 'and the results are the callback''s')
        call mlx_enable_compile()
        g = mlx_compile(f)
        call g%apply([a], outputs)
        before = g%trace_count()
        call g%apply([a], outputs)
        call assert_int(before, g%trace_count(), 'with compilation enabled a second call does not run the callback')
        modes = [MLX_COMPILE_MODES%no_simplify, MLX_COMPILE_MODES%no_fuse, MLX_COMPILE_MODES%enabled]
        do k = 1, 3
            call mlx_set_compile_mode(modes(k))
            g = mlx_compile(f)
            call g%apply([a], outputs)
            before = g%trace_count()
            call g%apply([a], outputs)
            call assert_int(before, g%trace_count(), 'a compile mode that traces runs the callback once')
            call mlx_to(got, outputs(2))
            call assert_true(all(bits_equal(got, x*x)), 'and gives the callback''s values')
        end do
        call mlx_set_compile_mode(MLX_COMPILE_MODES%disabled)
        g = mlx_compile(f)
        before = g%trace_count()
        call g%apply([a], outputs)
        call g%apply([a], outputs)
        call assert_int(before+2, g%trace_count(), 'the mode disabled is mlx_disable_compile')
        call mlx_set_compile_mode(MLX_COMPILE_MODES%enabled)
    end subroutine test_compile_controls

    ! deletes a file the test wrote, if it exists
    subroutine remove( file )
        character(len=*), intent(in) :: file
        integer :: unit, st
        logical :: there
        inquire(file=file, exist=there)
        if( .not. there ) return
        open(newunit=unit, file=file, status='old', iostat=st)
        if( st == 0 ) close(unit, status='delete', iostat=st)
    end subroutine remove

    ! outputs 2 x + 1 and x x of the first input: arithmetic that is exact on the fixtures
    subroutine affine( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        status = 1
        if( size(inputs) /= 1 ) return
        allocate(outputs(2))
        outputs(1) = inputs(1)*2._real32+1._real32
        outputs(2) = inputs(1)*inputs(1)
        status = 0
    end subroutine affine

    ! a callback that fails through its status
    subroutine failing( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        allocate(outputs(0))
        status = 7+0*size(inputs)
    end subroutine failing

end module mlxf_export_tester
