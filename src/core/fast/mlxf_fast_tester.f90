!@descr: custom Metal kernels against exact Fortran references: buffer layout, several buffers, templates, atomics, compiled use, refusals
module mlxf_fast_tester
use, intrinsic :: iso_fortran_env, only: real32, int32
use mlxf,            only: mlx_array, mlx_metal_kernel, mlx_metal_kernel_spec, mlx_function, mlx_compile, mlx_from, &
                           mlx_to, mlx_item, mlx_eval, mlx_live_count, mlx_last_error, mlx_set_default_device, &
                           mlx_default_device, MLX_DEVICES, MLX_DTYPES, transpose
use mlxf_test_utils, only: test_devices, device_name, assert_true, assert_int, bits_equal, cpu_only_mlx
implicit none
private
public :: run_all_fast_tests

character(len=*), parameter :: NL = new_line('a')

contains

    subroutine run_all_fast_tests
        integer, allocatable :: devs(:)
        integer              :: i, original, live0
        write(*,'(a)') '**** running all fast tests ****'
        call test_empty_kernels_parallel
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            call test_lifecycle
            if( devs(i) == MLX_DEVICES%gpu )then
                call test_column_index
                call test_grid_2d
                call test_two_inputs_two_outputs
                call test_template_and_header
                call test_strided_input
                call test_atomic_outputs
                call test_complex_and_scalar_inputs
                call test_compiled_function
                call test_refused_applications
            else
                call test_cpu_refusal
            endif
            call assert_int(live0, mlx_live_count(), 'kernels, their copies and their arrays leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_fast_tests

    ! copying, killing and finalizing empty kernels inside an OpenMP region does not stop
    subroutine test_empty_kernels_parallel
        integer :: i, completed(8)
        write(*,'(a)') 'test_empty_kernels_parallel'
        completed = 0
        !$omp parallel do num_threads(2) default(shared) private(i) schedule(static) proc_bind(close)
        do i = 1, size(completed)
            call empty_kernel_scope
            completed(i) = 1
        end do
        !$omp end parallel do
        call assert_true(all(completed == 1), 'empty kernel assignment, kill and finalization are safe in parallel')
    end subroutine test_empty_kernels_parallel

    ! an empty kernel copied, killed and finalized on leaving the scope
    subroutine empty_kernel_scope
        type(mlx_metal_kernel) :: k, copy
        copy = k
        call copy%kill()
    end subroutine empty_kernel_scope

    ! a kernel is one live object however many copies share it, building one needs no GPU, and kill is idempotent
    subroutine test_lifecycle
        type(mlx_metal_kernel)      :: k, copy
        type(mlx_metal_kernel_spec) :: spec
        integer                     :: live0
        write(*,'(a)') 'test_lifecycle'
        live0 = mlx_live_count()
        spec = column_spec([5, 3])
        k = mlx_metal_kernel(spec)
        call assert_int(live0+1, mlx_live_count(), 'a kernel and its launch configuration are one live object')
        copy = k
        call assert_int(live0+1, mlx_live_count(), 'a copy shares the kernel')
        call k%kill()
        call k%kill()
        call assert_int(live0+1, mlx_live_count(), 'the copy keeps the kernel alive after the original is killed twice')
        call k%new(spec)
        call k%new(spec)
        call assert_int(live0+2, mlx_live_count(), 'building over a live kernel releases the one it held')
        copy = k
        call assert_int(live0+1, mlx_live_count(), 'assigning over the last copy frees its kernel')
        call copy%kill()
        call k%kill()
        call assert_int(live0, mlx_live_count(), 'killing every copy frees the kernel')
    end subroutine test_lifecycle

    ! the spec of a kernel that adds to each element of a rank-2 float32 array the 1-based number of its column
    ! (its second Fortran subscript): in the source the columns are MLX's first axis, of stride inp_shape[1]
    function column_spec( shape ) result(spec)
        integer, intent(in) :: shape(2)
        type(mlx_metal_kernel_spec) :: spec
        spec%name = 'mlxf_test_add_column'
        spec%input_names = ['inp']
        spec%output_names = ['out']
        spec%source = 'uint elem = thread_position_in_grid.x;'//NL//&
            &'out[elem] = inp[elem] + float(elem / inp_shape[1] + 1);'
        spec%grid = [product(shape), 1, 1]
        spec%threadgroup = [64, 1, 1]
        spec%output_shapes = shape
    end function column_spec

    ! x(i, j) + j for a (5, 3) array: element (i, j) of a Fortran array is buffer position (j-1)*n1 + (i-1) in the
    ! source, and the shape the source sees is the Fortran shape reversed
    subroutine test_column_index
        type(mlx_metal_kernel)       :: k
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: outputs(:)
        real(real32)                 :: x(5, 3), y(5, 3), by_column(5, 3), by_row(5, 3)
        integer                      :: i, j, st
        write(*,'(a)') 'test_column_index'
        do j = 1, 3
            do i = 1, 5
                x(i, j) = real(i+5*(j-1), real32)/4
                by_column(i, j) = x(i, j)+real(j, real32)
                by_row(i, j) = x(i, j)+real(i, real32)
            end do
        end do
        k = mlx_metal_kernel(column_spec(shape(x)))
        a = mlx_from(x)
        call k%apply([a], outputs, status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'a kernel applies on the GPU with status zero')
        if( st /= 0 ) return
        call assert_int(1, size(outputs), 'one output name gives one array')
        call assert_true(all(outputs(1)%shape() == shape(x)), 'an output shape given in Fortran order is the result''s shape')
        call assert_int(MLX_DTYPES%float32, outputs(1)%kind(), 'an output is float32 when no dtype is given')
        call k%kill()
        call mlx_to(y, outputs(1), status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'the kernel compiles and evaluates after its object is killed: the graph keeps what it needs')
        call assert_true(all(bits_equal(y, by_column)), 'element (i, j) is buffer position (j-1)*n1 + (i-1): the 1-based column is added exactly')
        call assert_true(.not. all(bits_equal(y, by_row)), 'the row number in place of the column number does not compare equal')
    end subroutine test_column_index

    ! a grid of (n1, n2, 1) threads: Metal's x runs along Fortran dimension 1 and y along dimension 2 when the
    ! source writes position y*n1 + x; the threadgroup is given per grid direction; verbose prints MLX's source
    subroutine test_grid_2d
        type(mlx_metal_kernel)       :: k
        type(mlx_metal_kernel_spec)  :: spec
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: outputs(:)
        real(real32)                 :: x(6, 4), y(6, 4), expected(6, 4)
        integer                      :: i, j, st
        write(*,'(a)') 'test_grid_2d'
        do j = 1, 4
            do i = 1, 6
                x(i, j) = real(i-j, real32)/8
                expected(i, j) = x(i, j)+real(10*i+j, real32)
            end do
        end do
        spec%name = 'mlxf_test_grid_2d'
        spec%input_names = ['inp']
        spec%output_names = ['out']
        spec%source = 'uint i = thread_position_in_grid.x;'//NL//&
            &'uint j = thread_position_in_grid.y;'//NL//&
            &'uint pos = j * threads_per_grid.x + i;'//NL//&
            &'out[pos] = inp[pos] + float(10 * (i + 1) + (j + 1));'
        spec%grid = [6, 4, 1]
        spec%threadgroup = [4, 2, 1]
        spec%output_shapes = shape(x)
        spec%output_dtypes = [MLX_DTYPES%float32]
        spec%verbose = .true.
        k = mlx_metal_kernel(spec)
        a = mlx_from(x)
        call k%apply([a], outputs, status=st)
        call assert_int(0, st, 'a verbose kernel on a two-dimensional grid applies')
        if( st /= 0 ) return
        call mlx_to(y, outputs(1), status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'a kernel on a two-dimensional grid evaluates')
        call assert_true(all(bits_equal(y, expected)), 'grid x is Fortran dimension 1 and grid y dimension 2 at position y*n1 + x')
    end subroutine test_grid_2d

    ! two inputs (a matrix and one weight per column, the short one in Metal's constant address space) and two
    ! outputs of different rank and dtype, their shapes listed one after another with output_ranks
    subroutine test_two_inputs_two_outputs
        type(mlx_metal_kernel)       :: k
        type(mlx_metal_kernel_spec)  :: spec
        type(mlx_array)              :: a, w
        type(mlx_array), allocatable :: outputs(:)
        real(real32)                 :: x(4, 3), weights(3), y(4, 3), expected(4, 3)
        integer(int32)               :: positions(12)
        integer                      :: i, j, st
        write(*,'(a)') 'test_two_inputs_two_outputs'
        weights = [0.5_real32, -2._real32, 8._real32]
        do j = 1, 3
            do i = 1, 4
                x(i, j) = real(3*i-j, real32)/2
                expected(i, j) = x(i, j)+weights(j)
            end do
        end do
        spec%name = 'mlxf_test_two_by_two'
        spec%input_names = [character(len=8) :: 'values', 'weights']
        spec%output_names = [character(len=9) :: 'sums', 'positions']
        spec%source = 'uint elem = thread_position_in_grid.x;'//NL//&
            &'sums[elem] = values[elem] + weights[elem / values_shape[1]];'//NL//&
            &'positions[elem] = int(elem) + 1;'
        spec%grid = [size(x), 1, 1]
        spec%threadgroup = [12, 1, 1]
        spec%output_ranks = [2, 1]
        spec%output_shapes = [4, 3, 12]
        spec%output_dtypes = [MLX_DTYPES%float32, MLX_DTYPES%int32]
        k = mlx_metal_kernel(spec)
        a = mlx_from(x)
        w = mlx_from(weights)
        call k%apply([a, w], outputs, status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'a kernel with two inputs and two outputs applies')
        if( st /= 0 ) return
        call assert_int(2, size(outputs), 'two output names give two arrays, in the names'' order')
        call assert_true(all(outputs(1)%shape() == [4, 3]), 'the first output takes the first two extents of output_shapes')
        call assert_true(all(outputs(2)%shape() == [12]), 'the second output takes the extent that follows')
        call assert_int(MLX_DTYPES%int32, outputs(2)%kind(), 'the second output has the second dtype')
        call mlx_eval(outputs, status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'both outputs evaluate together')
        if( st /= 0 ) return
        call mlx_to(y, outputs(1))
        call mlx_to(positions, outputs(2))
        call assert_true(all(bits_equal(y, expected)), 'the second input is indexed by the column of the first: x(i, j) + w(j)')
        call assert_true(all(positions == [(i, i=1, 12)]), 'the int32 output holds each element''s position in array element order')
    end subroutine test_two_inputs_two_outputs

    ! a dtype, an integer and a logical template parameter and a header function; two outputs share the listed
    ! extents equally; a second kernel with other template values gives other results from the same source
    subroutine test_template_and_header
        type(mlx_metal_kernel)       :: k
        type(mlx_metal_kernel_spec)  :: spec
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: outputs(:)
        real(real32)                 :: x(9), plain(9), flipped(3)
        integer                      :: i, st
        write(*,'(a)') 'test_template_and_header'
        x = [(real(i-4, real32)/16, i=1, 9)]
        spec%name = 'mlxf_test_template'
        spec%input_names = ['inp']
        spec%output_names = [character(len=7) :: 'plain', 'flipped']
        spec%header = 'inline float mlxf_test_twice(float v) { return v + v; }'
        spec%source = 'uint elem = thread_position_in_grid.x;'//NL//&
            &'T v = inp[elem];'//NL//&
            &'plain[elem] = mlxf_test_twice(v) + T(SHIFT);'//NL//&
            &'if (elem < 3) { flipped[elem] = NEGATE ? -v : v; }'
        spec%grid = [size(x), 1, 1]
        spec%threadgroup = [9, 1, 1]
        spec%output_shapes = [9, 3]
        spec%template_dtype_names = ['T']
        spec%template_dtypes = [MLX_DTYPES%float32]
        spec%template_int_names = ['SHIFT']
        spec%template_ints = [3]
        spec%template_bool_names = ['NEGATE']
        spec%template_bools = [.true.]
        a = mlx_from(x)
        k = mlx_metal_kernel(spec)
        call k%apply([a], outputs, status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'a kernel with template parameters and a header applies')
        if( st /= 0 ) return
        call assert_true(all(outputs(1)%shape() == [9]), 'outputs without output_ranks share the extents equally: the first')
        call assert_true(all(outputs(2)%shape() == [3]), 'outputs without output_ranks share the extents equally: the second')
        call mlx_eval(outputs, status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'the templated source and its header compile')
        if( st /= 0 ) return
        call mlx_to(plain, outputs(1))
        call mlx_to(flipped, outputs(2))
        call assert_true(all(bits_equal(plain, 2*x+3)), 'the header function and the integer parameter: 2x + 3')
        call assert_true(all(bits_equal(flipped, -x(:3))), 'the logical parameter selects the negated branch')
        spec%template_ints = [-2]
        spec%template_bools = [.false.]
        call k%new(spec)
        call k%apply([a], outputs, status=st)
        call assert_int(0, st, 'the same source applies with other template values')
        if( st /= 0 ) return
        call mlx_to(plain, outputs(1), status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'a negative integer parameter compiles')
        call mlx_to(flipped, outputs(2))
        call assert_true(all(bits_equal(plain, 2*x-2)), 'the second integer value: 2x - 2')
        call assert_true(all(bits_equal(flipped, x(:3))), 'the second logical value selects the other branch')
    end subroutine test_template_and_header

    ! a transposed array is a strided view. By default MLX copies it, so the source sees the array's own elements
    ! in order; with ensure_row_contiguous false the source must go through the strides, else it reads storage order
    subroutine test_strided_input
        type(mlx_metal_kernel)       :: k
        type(mlx_metal_kernel_spec)  :: spec
        type(mlx_array)              :: a, t
        type(mlx_array), allocatable :: outputs(:)
        real(real32)                 :: x(3, 5), y(5, 3), logical_order(5, 3), storage_order(5, 3)
        integer                      :: i, j, st
        write(*,'(a)') 'test_strided_input'
        do j = 1, 5
            do i = 1, 3
                x(i, j) = real(i+3*(j-1), real32)/4
            end do
        end do
        do j = 1, 3
            do i = 1, 5
                logical_order(i, j) = x(j, i)+real(j, real32)
                storage_order(i, j) = real(i+5*(j-1), real32)/4+real(j, real32)
            end do
        end do
        a = mlx_from(x)
        t = transpose(a)
        spec = column_spec([5, 3])
        k = mlx_metal_kernel(spec)
        call k%apply([t], outputs, status=st)
        call assert_int(0, st, 'a kernel applies to a strided view')
        if( st /= 0 ) return
        call mlx_to(y, outputs(1))
        call assert_true(all(bits_equal(y, logical_order)), 'by default the source sees a strided input''s elements in array element order')
        spec%ensure_row_contiguous = .false.
        call k%new(spec)
        call k%apply([t], outputs, status=st)
        call assert_int(0, st, 'the same source applies without the copy')
        if( st /= 0 ) return
        call mlx_to(y, outputs(1))
        call assert_true(all(bits_equal(y, storage_order)), 'without the copy a source that ignores the strides reads the buffer in storage order')
        spec%name = 'mlxf_test_add_column_strided'
        spec%source = 'uint elem = thread_position_in_grid.x;'//NL//&
            &'uint loc = elem_to_loc(elem, inp_shape, inp_strides, inp_ndim);'//NL//&
            &'out[elem] = inp[loc] + float(elem / inp_shape[1] + 1);'
        call k%new(spec)
        call k%apply([t], outputs, status=st)
        call assert_int(0, st, 'a source that uses the strides applies without the copy')
        if( st /= 0 ) return
        call mlx_to(y, outputs(1), status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'a source that uses the input''s shape, strides and rank compiles')
        call assert_true(all(bits_equal(y, logical_order)), 'through the strides the uncopied view gives the array''s own elements')
    end subroutine test_strided_input

    ! 4,096 weighted updates collide in 13 bins and in one rank-0 total: atomic int32 outputs add them exactly, on
    ! top of the initial value; the bins are 1-based in Fortran and the source subtracts one
    subroutine test_atomic_outputs
        integer,         parameter   :: NUPDATES = 4096, NBINS = 13
        type(mlx_metal_kernel)       :: k
        type(mlx_metal_kernel_spec)  :: spec
        type(mlx_array)              :: abins, aweights
        type(mlx_array), allocatable :: outputs(:)
        integer(int32)               :: bins(NUPDATES), weights(NUPDATES), hist(NBINS), expected(NBINS), total
        integer                      :: i, st
        write(*,'(a)') 'test_atomic_outputs'
        expected = 0
        do i = 1, NUPDATES
            bins(i) = int(1+modulo(7*i+i/5, NBINS), int32)
            weights(i) = int(1+modulo(i, 3), int32)
            expected(bins(i)) = expected(bins(i))+weights(i)
        end do
        spec%name = 'mlxf_test_histogram'
        spec%input_names = [character(len=7) :: 'bins', 'weights']
        spec%output_names = [character(len=5) :: 'hist', 'total']
        spec%source = 'uint elem = thread_position_in_grid.x;'//NL//&
            &'atomic_fetch_add_explicit(&hist[bins[elem] - 1], weights[elem], memory_order_relaxed);'//NL//&
            &'atomic_fetch_add_explicit(&total[0], weights[elem], memory_order_relaxed);'
        spec%grid = [NUPDATES, 1, 1]
        spec%threadgroup = [256, 1, 1]
        spec%output_ranks = [1, 0]
        spec%output_shapes = [NBINS]
        spec%output_dtypes = [MLX_DTYPES%int32, MLX_DTYPES%int32]
        spec%atomic_outputs = .true.
        spec%init_value = 0.
        abins = mlx_from(bins)
        aweights = mlx_from(weights)
        k = mlx_metal_kernel(spec)
        call k%apply([abins, aweights], outputs, status=st)
        call assert_int(0, st, 'a kernel with atomic outputs applies')
        if( st /= 0 ) return
        call mlx_to(hist, outputs(1), status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'atomic int32 outputs compile and evaluate')
        call assert_true(all(hist == expected), 'colliding atomic integer updates sum exactly from an initial value of zero')
        call assert_int(0, outputs(2)%ndim(), 'an output of rank 0 takes no extent of output_shapes')
        call mlx_item(outputs(2), total)
        call assert_int(sum(weights), int(total), 'every thread adds to the rank-0 output: the total is exact')
        spec%init_value = 5.
        call k%new(spec)
        call k%apply([abins, aweights], outputs, status=st)
        call assert_int(0, st, 'the kernel applies with another initial value')
        if( st /= 0 ) return
        call mlx_to(hist, outputs(1))
        call assert_true(all(hist == expected+5), 'the outputs start from init_value: every bin holds five more')
    end subroutine test_atomic_outputs

    ! a complex64 input is a buffer of complex64_t with members real and imag, and a rank-0 input is a reference,
    ! used without a subscript; no input names at all is a kernel that only writes
    subroutine test_complex_and_scalar_inputs
        type(mlx_metal_kernel)       :: k
        type(mlx_metal_kernel_spec)  :: spec, iota
        type(mlx_array)              :: z, s, none(0)
        type(mlx_array), allocatable :: outputs(:)
        complex(real32)              :: c(8)
        real(real32)                 :: power(8), expected(8)
        integer(int32)               :: counted(8)
        integer                      :: i, st
        write(*,'(a)') 'test_complex_and_scalar_inputs'
        do i = 1, 8
            c(i) = cmplx(real(i, real32)/2, real(3-i, real32)/4, real32)
            expected(i) = 2*(real(c(i))**2+aimag(c(i))**2)
        end do
        spec%name = 'mlxf_test_power'
        spec%input_names = [character(len=5) :: 'z', 'scale']
        spec%output_names = ['power']
        spec%source = 'uint elem = thread_position_in_grid.x;'//NL//&
            &'power[elem] = scale * (z[elem].real * z[elem].real + z[elem].imag * z[elem].imag);'
        spec%grid = [8, 1, 1]
        spec%threadgroup = [8, 1, 1]
        spec%output_shapes = [8]
        z = mlx_from(c)
        s = mlx_from(2._real32)
        k = mlx_metal_kernel(spec)
        call k%apply([z, s], outputs, status=st)
        call assert_int(0, st, 'a kernel with a complex64 and a rank-0 input applies')
        if( st /= 0 ) return
        call mlx_to(power, outputs(1), status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'complex64_t members and a scalar reference compile')
        call assert_true(all(bits_equal(power, expected)), 'the scaled squared modulus of each complex element is exact')
        iota%name = 'mlxf_test_iota'
        iota%output_names = ['out']
        iota%source = 'out[thread_position_in_grid.x] = int(thread_position_in_grid.x) + 1;'
        iota%grid = [8, 1, 1]
        iota%output_shapes = [8]
        iota%output_dtypes = [MLX_DTYPES%int32]
        call k%new(iota)
        call k%apply(none, outputs, status=st)
        if( st /= 0 ) write(*,'(a)') mlx_last_error()
        call assert_int(0, st, 'a kernel without inputs applies to an empty list')
        if( st /= 0 ) return
        call mlx_to(counted, outputs(1), status=st)
        call assert_int(0, st, 'a kernel without inputs evaluates')
        call assert_true(all(counted == [(i, i=1, 8)]), 'a kernel without inputs writes its output with the default threadgroup')
    end subroutine test_complex_and_scalar_inputs

    ! a kernel applied inside a callback: its result feeds an operation of the graph, the compiled function
    ! traces once for two arrays of one shape and gives the uncompiled results
    subroutine test_compiled_function
        type(mlx_function)           :: f, g
        type(mlx_array)              :: a
        type(mlx_array), allocatable :: plain(:), fused(:)
        real(real32)                 :: x(5, 3), p(5, 3), q(5, 3), expected(5, 3)
        integer                      :: i, j, pass, st, before, traces
        write(*,'(a)') 'test_compiled_function'
        f = mlx_function(kernel_callback)
        g = mlx_compile(f)
        traces = 0
        do pass = 1, 2
            do j = 1, 3
                do i = 1, 5
                    x(i, j) = real(pass*i-j, real32)/8
                    expected(i, j) = 2*(x(i, j)+real(j, real32))
                end do
            end do
            a = mlx_from(x)
            call f%apply([a], plain, status=st)
            if( st /= 0 ) write(*,'(a)') mlx_last_error()
            call assert_int(0, st, 'a callback that applies a kernel returns status zero')
            before = g%trace_count()
            call g%apply([a], fused, status=st)
            if( st /= 0 ) write(*,'(a)') mlx_last_error()
            call assert_int(0, st, 'the compiled callback that applies a kernel returns status zero')
            traces = traces+g%trace_count()-before
            if( st /= 0 ) cycle
            call mlx_to(p, plain(1))
            call mlx_to(q, fused(1), status=st)
            if( st /= 0 ) write(*,'(a)') mlx_last_error()
            call assert_int(0, st, 'the compiled graph holding a kernel evaluates')
            call assert_true(all(bits_equal(q, expected)), 'the kernel''s result doubled inside the compiled function is exact')
            call assert_true(all(bits_equal(p, q)), 'compiled and uncompiled results are byte-identical')
        end do
        call assert_int(1, traces, 'two arrays of one shape trace the kernel callback once')
    end subroutine test_compiled_function

    ! builds the column kernel for its input's shape, applies it and doubles the result
    subroutine kernel_callback( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,         intent(out)              :: status
        type(mlx_metal_kernel)       :: k
        type(mlx_array), allocatable :: columns(:)
        k = mlx_metal_kernel(column_spec(inputs(1)%shape()))
        call k%apply(inputs, columns, status=status)
        if( status /= 0 ) return
        allocate(outputs(1))
        outputs(1) = columns(1)*2._real32
    end subroutine kernel_callback

    ! what a kernel refuses comes back as a status with a message, publishes no output and leaves MLX usable: a
    ! wrong number of inputs, an empty input, a float64 output, and at the evaluation a source that does not
    ! compile and a threadgroup above the device's limit
    subroutine test_refused_applications
        type(mlx_metal_kernel)        :: k
        type(mlx_metal_kernel_spec)   :: spec
        type(mlx_array)               :: a, never
        type(mlx_array),  allocatable :: outputs(:)
        real(real32)                  :: x(5, 3), y(5, 3)
        integer                       :: st
        character(len=:), allocatable :: message
        write(*,'(a)') 'test_refused_applications'
        x = 1._real32
        a = mlx_from(x)
        spec = column_spec(shape(x))
        k = mlx_metal_kernel(spec)
        call k%apply([a, a], outputs, status=st)
        call assert_true(st /= 0, 'more inputs than input names return a status')
        call assert_true(.not. allocated(outputs), 'a refused application publishes no output')
        message = mlx_last_error()
        call assert_true(index(message, 'inputs') > 0, 'the refusal names the inputs')
        call k%apply([never], outputs, status=st)
        call assert_true(st /= 0, 'an empty input array returns a status')
        call assert_true(.not. allocated(outputs), 'an empty input publishes no output')
        message = mlx_last_error()
        call assert_true(index(message, 'mlx_metal_kernel apply') > 0, 'the refusal of an empty input names the kernel''s apply')
        spec%name = 'mlxf_test_broken'
        spec%source = 'out[thread_position_in_grid.x] = no_such_buffer[0];'
        call k%new(spec)
        call k%apply([a], outputs, status=st)
        call assert_int(0, st, 'a source is not compiled when the kernel is applied')
        if( st == 0 )then
            call mlx_eval(outputs, status=st)
            call assert_true(st /= 0, 'a source that does not compile fails the evaluation with a status')
            message = mlx_last_error()
            call assert_true(index(message, 'no_such_buffer') > 0, 'the compiler''s message names the undeclared identifier')
        endif
        spec = column_spec(shape(x))
        spec%threadgroup = [1024, 1024, 1]
        call k%new(spec)
        call k%apply([a], outputs, status=st)
        call assert_int(0, st, 'a threadgroup is not checked when the kernel is applied')
        if( st == 0 )then
            call mlx_eval(outputs, status=st)
            call assert_true(st /= 0, 'a threadgroup above the device''s limit fails the evaluation with a status')
        endif
        spec%output_dtypes = [MLX_DTYPES%float64]
        spec%threadgroup = [64, 1, 1]
        call k%new(spec)
        call k%apply([a], outputs, status=st)
        call assert_true(st /= 0, 'a float64 output is refused with a status: Metal has no float64')
        call k%new(column_spec(shape(x)))
        call k%apply([a], outputs, status=st)
        call assert_int(0, st, 'a kernel applies after the refusals')
        if( st /= 0 ) return
        call mlx_to(y, outputs(1), status=st)
        call assert_int(0, st, 'MLX evaluates a kernel after a failed compilation')
        call assert_true(all(bits_equal(y(:, 3), 4._real32)), 'the recovered kernel gives the expected values')
    end subroutine test_refused_applications

    ! on the CPU device a kernel is built but not applied: the refusal is a status and a message, no output, and
    ! the CPU device stays usable
    subroutine test_cpu_refusal
        type(mlx_metal_kernel)        :: k
        type(mlx_array)               :: a, b
        type(mlx_array),  allocatable :: outputs(:)
        real(real32)                  :: x(5, 3), y(5, 3)
        integer                       :: st
        character(len=:), allocatable :: message
        write(*,'(a)') 'test_cpu_refusal'
        x = 0.25_real32
        a = mlx_from(x)
        k = mlx_metal_kernel(column_spec(shape(x)))
        call k%apply([a], outputs, status=st)
        call assert_true(st /= 0, 'on the CPU device a Metal kernel is refused with a status')
        call assert_true(.not. allocated(outputs), 'the CPU refusal publishes no output')
        message = mlx_last_error()
        if( cpu_only_mlx() )then
            call assert_true(index(message, 'No Metal') > 0, 'on a CPU-only MLX the refusal says there is no Metal backend')
        else
            call assert_true(index(message, 'GPU') > 0, 'the refusal says that a Metal kernel needs the GPU')
        endif
        b = a+a
        call mlx_to(y, b, status=st)
        call assert_int(0, st, 'the CPU device evaluates after the refusal')
        call assert_true(all(bits_equal(y, 0.5_real32)), 'the CPU result after the refusal is exact')
    end subroutine test_cpu_refusal

end module mlxf_fast_tester
