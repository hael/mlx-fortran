!@descr: convolutions with Fortran dimensions: channels first, then the spatial dimensions, the batch last
! MLX's channels-last layouts read in Fortran order: the input is (C, W[, H[, D]], N), the kernels are
! (C/groups, kW[, kH[, kD]], C_out) and the result is (C_out, W'[, H'[, D']], N). The options travel in a record,
! mlx_conv_spec, with one value per spatial dimension in Fortran's order (W first), reversed for MLX. Like MLX,
! these correlate the input with the kernels (no reversal of a kernel) unless flip asks for it.
module mlxf_conv
use mlxf_c_ops,  only: mlxc_conv1d, mlxc_conv2d, mlxc_conv3d, mlxc_conv_general, mlxc_conv_transpose1d, &
                       mlxc_conv_transpose2d, mlxc_conv_transpose3d
use mlxf_defs,   only: mlx_conv_spec
use mlxf_array,  only: mlx_array, mlxf_conv1d_op, mlxf_conv2d_op, mlxf_conv3d_op, mlxf_conv_general_op, &
                       mlxf_conv_transpose1d_op, mlxf_conv_transpose2d_op, mlxf_conv_transpose3d_op
use mlxf_device, only: mlxf_enter
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

end module mlxf_conv
