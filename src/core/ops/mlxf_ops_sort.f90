!@descr: sorting, partitioning and the largest elements through the array signature helpers
! Along dim, or of the elements in array element order (a rank-1 result) without it. Positions (argsort,
! argpartition) are 1-based int32, and kth is a 1-based position, checked against 1 (MLX would count a
! smaller one from the end).
module mlxf_ops_sort
use mlxf_c_ops,     only: mlxc_argpartition, mlxc_argpartition_axis, mlxc_argsort, mlxc_argsort_axis, mlxc_partition, &
                          mlxc_partition_axis, mlxc_sort, mlxc_sort_axis, mlxc_topk, mlxc_topk_axis
use mlxf_error,     only: mlxf_fail
use mlxf_device,    only: mlxf_enter
use mlxf_array,     only: mlx_array
use mlxf_ops_shape, only: axis_of
use mlxf_calls,     only: mlxf_int2_op, mlxf_int_op, mlxf_one_based, mlxf_unary
implicit none

public :: mlx_sort, mlx_argsort, mlx_partition, mlx_argpartition, mlx_topk
private

contains

    ! the elements in ascending order
    function mlx_sort( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_sort')
        if( present(dim) )then
            call mlxf_int_op(r, mlxc_sort_axis, a, axis_of(a%ndim(), dim, 'mlx_sort'), 'mlx_sort')
        else
            call mlxf_unary(r, mlxc_sort, a, 'mlx_sort')
        endif
    end function mlx_sort

    ! the 1-based positions that sort a in ascending order
    function mlx_argsort( a, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        type(mlx_array) :: idx
        call mlxf_enter('mlx_argsort')
        if( present(dim) )then
            call mlxf_int_op(idx, mlxc_argsort_axis, a, axis_of(a%ndim(), dim, 'mlx_argsort'), 'mlx_argsort')
        else
            call mlxf_unary(idx, mlxc_argsort, a, 'mlx_argsort')
        endif
        call mlxf_one_based(r, idx, 'mlx_argsort')
    end function mlx_argsort

    ! a rearrangement with the element of sorted position kth in place: no element before it is larger and
    ! none after it smaller; the order inside the two parts is not defined
    function mlx_partition( a, kth, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: kth
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_partition')
        if( kth < 1 ) call mlxf_fail('mlx_partition', 'kth is a position from 1')
        if( present(dim) )then
            call mlxf_int2_op(r, mlxc_partition_axis, a, [kth-1, axis_of(a%ndim(), dim, 'mlx_partition')], 'mlx_partition')
        else
            call mlxf_int_op(r, mlxc_partition, a, kth-1, 'mlx_partition')
        endif
    end function mlx_partition

    ! the 1-based positions that partition a as mlx_partition does
    function mlx_argpartition( a, kth, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: kth
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        type(mlx_array) :: idx
        call mlxf_enter('mlx_argpartition')
        if( kth < 1 ) call mlxf_fail('mlx_argpartition', 'kth is a position from 1')
        if( present(dim) )then
            call mlxf_int2_op(idx, mlxc_argpartition_axis, a, [kth-1, axis_of(a%ndim(), dim, 'mlx_argpartition')], 'mlx_argpartition')
        else
            call mlxf_int_op(idx, mlxc_argpartition, a, kth-1, 'mlx_argpartition')
        endif
        call mlxf_one_based(r, idx, 'mlx_argpartition')
    end function mlx_argpartition

    ! the k largest elements, in no defined order
    function mlx_topk( a, k, dim ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: k
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_topk')
        if( present(dim) )then
            call mlxf_int2_op(r, mlxc_topk_axis, a, [k, axis_of(a%ndim(), dim, 'mlx_topk')], 'mlx_topk')
        else
            call mlxf_int_op(r, mlxc_topk, a, k, 'mlx_topk')
        endif
    end function mlx_topk

end module mlxf_ops_sort
