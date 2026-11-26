!@descr: convolutions with Fortran dimensions: channels first, then the spatial dimensions, the batch last
! MLX's channels-last layouts read in Fortran order: the input is (C, W[, H[, D]], N), the kernels are
! (C/groups, kW[, kH[, kD]], C_out) and the result is (C_out, W'[, H'[, D']], N). The options travel in a record,
! mlx_conv_spec, with one value per spatial dimension in Fortran's order (W first), reversed for MLX. Like MLX,
! these correlate the input with the kernels (no reversal of a kernel) unless flip asks for it.
module mlxf_conv
use, intrinsic :: iso_c_binding, only: c_bool, c_int, c_size_t
use mlxf_c_array,      only: mlxc_array_free, mlxc_array_new
use mlxf_c_ops,        only: mlxc_conv1d, mlxc_conv2d, mlxc_conv3d, mlxc_conv_general, mlxc_conv_transpose1d, &
                             mlxc_conv_transpose2d, mlxc_conv_transpose3d
use mlxf_c_signatures, only: mlxc_conv1d_op, mlxc_conv2d_op, mlxc_conv3d_op, mlxc_conv_general_op, &
                             mlxc_conv_transpose1d_op, mlxc_conv_transpose2d_op, mlxc_conv_transpose3d_op
use mlxf_c_stream,     only: mlxc_stream_free
use mlxf_c_types,      only: mlxc_array, mlxc_stream
use mlxf_defs,         only: mlx_conv_spec
use mlxf_array,        only: mlx_array, mlxf_handle, mlxf_adopt
use mlxf_device,       only: mlxf_enter, mlxf_default_stream, mlxf_require_device
use mlxf_error,        only: mlxf_check, mlxf_fail
implicit none
public :: mlx_conv1d, mlx_conv2d, mlx_conv3d, mlx_conv_general, mlx_conv_transpose1d, mlx_conv_transpose2d
public :: mlx_conv_transpose3d
private

contains

    ! the correlation of a (C, W, N) input with (C/groups, kW, C_out) kernels: element w' of the result's dimension 2
    ! sums input(:, (w'-1)*stride - padding + (k-1)*dilation + 1, n)*weight(:, k, o) over the channels and k, where the
    ! input reaches (zeros outside); spec gives stride, padding, dilation and groups. A negative padding crops the
    ! input instead
    function mlx_conv1d( input, weight, spec ) result(r)
        type(mlx_array),     intent(in)           :: input, weight
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_array) :: r
        call mlxf_enter('mlx_conv1d')
        call mlxf_conv1d_op(r, mlxc_conv1d, [input, weight], options(spec), 'mlx_conv1d')
    end function mlx_conv1d

    ! the same over two spatial dimensions: a (C, W, H, N) input and (C/groups, kW, kH, C_out) kernels
    function mlx_conv2d( input, weight, spec ) result(r)
        type(mlx_array),     intent(in)           :: input, weight
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_array) :: r
        call mlxf_enter('mlx_conv2d')
        call mlxf_conv2d_op(r, mlxc_conv2d, [input, weight], options(spec), 'mlx_conv2d')
    end function mlx_conv2d

    ! the same over three spatial dimensions: a (C, W, H, D, N) input and (C/groups, kW, kH, kD, C_out) kernels;
    ! MLX takes one group only
    function mlx_conv3d( input, weight, spec ) result(r)
        type(mlx_array),     intent(in)           :: input, weight
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_array) :: r
        call mlxf_enter('mlx_conv3d')
        call mlxf_conv3d_op(r, mlxc_conv3d, [input, weight], options(spec), 'mlx_conv3d')
    end function mlx_conv3d

    ! the general form over one to three spatial dimensions, by the rank of input: padding before and padding_hi
    ! (padding when absent) after each dimension, the input spread by input_dilation (zeros between its elements) and
    ! the kernels by dilation, groups, and with flip the kernels reversed along every spatial dimension
    function mlx_conv_general( input, weight, spec ) result(r)
        type(mlx_array),     intent(in)           :: input, weight
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_array) :: r
        call mlxf_enter('mlx_conv_general')
        call mlxf_conv_general_op(r, mlxc_conv_general, [input, weight], options(spec), 'mlx_conv_general')
    end function mlx_conv_general

    ! the transposed convolution of a (C, W, N) input with (C/groups, kW, C_out) kernels: input element w adds
    ! input(:, w, n)*weight(:, k, o) to element (w-1)*stride - padding + (k-1)*dilation + 1 of the result's dimension 2, whose
    ! extent is (W-1)*stride - 2*padding + dilation*(kW-1) + 1 + output_padding. This holds for a padding up to
    ! dilation*(kW-1): beyond it MLX crops whole input elements and returns less
    function mlx_conv_transpose1d( input, weight, spec ) result(r)
        type(mlx_array),     intent(in)           :: input, weight
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_array) :: r
        call mlxf_enter('mlx_conv_transpose1d')
        call mlxf_conv_transpose1d_op(r, mlxc_conv_transpose1d, [input, weight], options(spec), 'mlx_conv_transpose1d')
    end function mlx_conv_transpose1d

    ! the same over two spatial dimensions: a (C, W, H, N) input and (C/groups, kW, kH, C_out) kernels
    function mlx_conv_transpose2d( input, weight, spec ) result(r)
        type(mlx_array),     intent(in)           :: input, weight
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_array) :: r
        call mlxf_enter('mlx_conv_transpose2d')
        call mlxf_conv_transpose2d_op(r, mlxc_conv_transpose2d, [input, weight], options(spec), 'mlx_conv_transpose2d')
    end function mlx_conv_transpose2d

    ! the same over three spatial dimensions: a (C, W, H, D, N) input and (C/groups, kW, kH, kD, C_out) kernels;
    ! MLX takes one group only
    function mlx_conv_transpose3d( input, weight, spec ) result(r)
        type(mlx_array),     intent(in)           :: input, weight
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_array) :: r
        call mlxf_enter('mlx_conv_transpose3d')
        call mlxf_conv_transpose3d_op(r, mlxc_conv_transpose3d, [input, weight], options(spec), 'mlx_conv_transpose3d')
    end function mlx_conv_transpose3d

    ! the options given, or the defaults: stride 1, no padding, dilation 1, one group
    function options( spec ) result(chosen)
        type(mlx_conv_spec), optional, intent(in) :: spec
        type(mlx_conv_spec) :: chosen
        if( present(spec) ) chosen = spec
    end function options

    ! the convolution of a(1) with the kernels a(2) over one spatial dimension, with the stride, padding, dilation and
    ! groups of option, for every function of mlx_conv1d's signature
    subroutine mlxf_conv1d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv1d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(1), pd(1), dl(1)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 1, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. allocated(option%output_padding) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general, output_padding to the transposed convolutions')
        st = conv_list(option%stride, 1, 1, proc)
        pd = conv_list(option%padding, 1, 0, proc)
        dl = conv_list(option%dilation, 1, 1, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), pd(1), dl(1), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_conv1d_op

    ! the convolution over two spatial dimensions: option's lists, given per Fortran dimension, reach MLX reversed, for
    ! every function of mlx_conv2d's signature
    subroutine mlxf_conv2d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv2d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(2), pd(2), dl(2)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 2, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. allocated(option%output_padding) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general, output_padding to the transposed convolutions')
        st = conv_list(option%stride, 2, 1, proc)
        pd = conv_list(option%padding, 2, 0, proc)
        dl = conv_list(option%dilation, 2, 1, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), pd(1), pd(2), dl(1), dl(2), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_conv2d_op

    ! the convolution over three spatial dimensions, option's lists reversed, for every function of mlx_conv3d's signature
    subroutine mlxf_conv3d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv3d_op)          :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(3), pd(3), dl(3)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 3, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. allocated(option%output_padding) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general, output_padding to the transposed convolutions')
        st = conv_list(option%stride, 3, 1, proc)
        pd = conv_list(option%padding, 3, 0, proc)
        dl = conv_list(option%dilation, 3, 1, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), st(3), pd(1), pd(2), pd(3), dl(1), dl(2), dl(3), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_conv3d_op

    ! the general convolution over one to three spatial dimensions: padding before and after (padding_hi, or the same),
    ! the kernel's and the input's dilation, groups and a reversed kernel, option's lists reversed, for every function of
    ! mlx_conv_general's signature
    subroutine mlxf_conv_general_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_conv_general_op)    :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_conv_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)            :: h(2)
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: st(:), lo(:), hi(:), dl(:), il(:)
        integer(c_size_t)           :: n
        integer                     :: nsp
        call mlxf_require_device(proc)
        nsp = a(1)%ndim()-2
        call conv_operands(h, a, nsp, option%groups, proc)
        if( allocated(option%output_padding) ) call mlxf_fail(proc, 'output_padding belongs to the transposed convolutions')
        st = conv_list(option%stride, nsp, 1, proc)
        lo = conv_list(option%padding, nsp, 0, proc)
        if( allocated(option%padding_hi) )then
            hi = conv_list(option%padding_hi, nsp, 0, proc)
        else
            hi = lo
        endif
        dl = conv_list(option%dilation, nsp, 1, proc)
        il = conv_list(option%input_dilation, nsp, 1, proc)
        n = int(nsp, c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st, n, lo, n, hi, n, dl, n, il, n, int(option%groups, c_int), logical(option%flip, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_conv_general_op

    ! the transposed convolution over one spatial dimension, with the stride, padding, dilation, output padding and
    ! groups of option, for every function of mlx_conv_transpose1d's signature
    subroutine mlxf_conv_transpose1d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose1d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(1), pd(1), dl(1), op(1)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 1, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general')
        st = conv_list(option%stride, 1, 1, proc)
        pd = conv_list(option%padding, 1, 0, proc)
        dl = conv_list(option%dilation, 1, 1, proc)
        op = conv_list(option%output_padding, 1, 0, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), pd(1), dl(1), op(1), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_conv_transpose1d_op

    ! the transposed convolution over two spatial dimensions, option's lists reversed, for every function of
    ! mlx_conv_transpose2d's signature
    subroutine mlxf_conv_transpose2d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose2d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(2), pd(2), dl(2), op(2)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 2, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general')
        st = conv_list(option%stride, 2, 1, proc)
        pd = conv_list(option%padding, 2, 0, proc)
        dl = conv_list(option%dilation, 2, 1, proc)
        op = conv_list(option%output_padding, 2, 0, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), pd(1), pd(2), dl(1), dl(2), op(1), op(2), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_conv_transpose2d_op

    ! the transposed convolution over three spatial dimensions, option's lists reversed, for every function of
    ! mlx_conv_transpose3d's signature
    subroutine mlxf_conv_transpose3d_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout)  :: r
        procedure(mlxc_conv_transpose3d_op) :: f
        type(mlx_array),     intent(in)     :: a(2)
        type(mlx_conv_spec), intent(in)     :: option
        character(len=*),    intent(in)     :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer(c_int)    :: st(3), pd(3), dl(3), op(3)
        call mlxf_require_device(proc)
        call conv_operands(h, a, 3, option%groups, proc)
        if( allocated(option%padding_hi) .or. allocated(option%input_dilation) .or. option%flip ) &
            &call mlxf_fail(proc, 'padding_hi, input_dilation and flip belong to mlx_conv_general')
        st = conv_list(option%stride, 3, 1, proc)
        pd = conv_list(option%padding, 3, 0, proc)
        dl = conv_list(option%dilation, 3, 1, proc)
        op = conv_list(option%output_padding, 3, 0, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), st(1), st(2), st(3), pd(1), pd(2), pd(3), dl(1), dl(2), dl(3), op(1), op(2), op(3), int(option%groups, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_conv_transpose3d_op

    ! the handles of a convolution's input a(1) and kernels a(2), both of rank n + 2 for n spatial dimensions (1 to
    ! 3); MLX divides by the groups unchecked, so they are checked here
    subroutine conv_operands( h, a, n, groups, proc )
        type(mlxc_array), intent(out) :: h(2)
        type(mlx_array),  intent(in)  :: a(2)
        integer,          intent(in)  :: n, groups
        character(len=*), intent(in)  :: proc
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        if( groups < 1 ) call mlxf_fail(proc, 'groups must be at least 1')
        if( n < 1 .or. n > 3 ) call mlxf_fail(proc, 'a convolution has one to three spatial dimensions: an input of rank 3 to 5')
        if( a(1)%ndim() /= n+2 ) call mlxf_fail(proc, 'the input needs the rank (channels, the spatial dimensions, batch)')
        if( a(2)%ndim() /= n+2 ) call mlxf_fail(proc, 'the kernels need the rank (input channels, the spatial dimensions, kernels)')
    end subroutine conv_operands

    ! one list of a convolution's options as MLX takes it: a value per spatial dimension, the Fortran order reversed;
    ! an absent list is fill everywhere and a list of one value serves every dimension
    function conv_list( list, n, fill, proc ) result(v)
        integer, allocatable, intent(in) :: list(:)
        integer,              intent(in) :: n, fill
        character(len=*),     intent(in) :: proc
        integer(c_int) :: v(n)
        v = int(fill, c_int)
        if( .not. allocated(list) ) return
        if( size(list) == 1 )then
            v = int(list(1), c_int)
        else if( size(list) == n )then
            v = int(list(n:1:-1), c_int)
        else
            call mlxf_fail(proc, 'a list of the convolution spec needs one value, or one per spatial dimension')
        endif
    end function conv_list

end module mlxf_conv
