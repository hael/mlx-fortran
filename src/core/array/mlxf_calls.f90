!@descr: the shared signature helpers: the calls of mlx-c several families make, and the checks they share
! One helper per C signature class that more than one family calls; a helper one family calls lives in that
! family. Implemented in the submodules mlxf_calls_elementwise, mlxf_calls_shaped and mlxf_calls_checks.
module mlxf_calls
use, intrinsic :: iso_c_binding,   only: c_int
use, intrinsic :: iso_fortran_env, only: real64
use mlxf_c_signatures, only: mlxc_binary_op, mlxc_flag_op, mlxc_int2_op, mlxc_int_op, mlxc_list_op, &
                             mlxc_reduce_dims_op, mlxc_ternary_op, mlxc_unary_op, mlxc_vector_op, mlxc_zeros_op
use mlxf_c_types,      only: mlxc_array, mlxc_stream
use mlxf_defs,         only: mlxf_reduce_spec, mlxf_slice_spec
use mlxf_array,        only: mlx_array
implicit none

public :: mlxf_unary, mlxf_binary, mlxf_weak_scalar, mlxf_integer_scalar, mlxf_dtype_op, mlxf_int_op, mlxf_vector_op, mlxf_ternary_op, &
    &mlxf_zeros_op, mlxf_reduce_all_op, mlxf_reduce_dims_op, mlxf_int2_op, mlxf_list_op, mlxf_check_dtype, &
    &mlxf_axes_of, mlxf_zero_based, mlxf_one_based, mlxf_check_dim, mlxf_slice_bounds, mlxf_cpu_stream, &
    &mlxf_optional_handle, mlxf_reduced_dims, mlxf_empty_reduction
private

interface
    ! int f(mlx_array* res, const mlx_array a, const mlx_stream s)
    module subroutine mlxf_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_unary

    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s)
    module subroutine mlxf_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_binary

    ! a Fortran scalar as a 0-d array of a's kind: weak, so it never changes the result's kind (float32
    module subroutine mlxf_weak_scalar( r, a, x, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        real(real64),     intent(in)    :: x
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_weak_scalar

    ! a default-integer scalar for an operator with a: exact in an integer array's kind, int32 with booleans, weak
    module subroutine mlxf_integer_scalar( r, a, i, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: i
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_integer_scalar

    ! int f(mlx_array* res, const mlx_array a, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_dtype_op( r, f, a, dtype, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int_op)          :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: dtype
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_dtype_op

    ! int f(mlx_array* res, const mlx_array a, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int_op)          :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_int_op

    ! int f(mlx_array* res, const mlx_array a, const int* shape, size_t shape_num, const mlx_stream s)
    module subroutine mlxf_vector_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_vector_op)       :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_vector_op

    ! int f(mlx_array* res, const mlx_array condition, const mlx_array x, const mlx_array y,
    ! const mlx_stream s)
    module subroutine mlxf_ternary_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_ternary_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_ternary_op

    ! int f(mlx_array* res, const int* shape, size_t shape_num, mlx_dtype dtype, const mlx_stream s)
    module subroutine mlxf_zeros_op( r, f, shape, dtype, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_zeros_op)        :: f
        integer,          intent(in)    :: shape(:), dtype
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_zeros_op

    ! int f(mlx_array* res, const mlx_array a, bool keepdims, const mlx_stream s)
    module subroutine mlxf_reduce_all_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_flag_op)               :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_reduce_all_op

    ! int f(mlx_array* res, const mlx_array a, const int* axes, size_t axes_num, bool keepdims, const mlx_stream
    ! s)
    module subroutine mlxf_reduce_dims_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_reduce_dims_op)        :: f
        type(mlx_array),        intent(in)    :: a
        type(mlxf_reduce_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
    end subroutine mlxf_reduce_dims_op

    ! int f(mlx_array* res, const mlx_array a, int i, int j, const mlx_stream s)
    module subroutine mlxf_int2_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int2_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_int2_op

    ! int f(mlx_array* res, const mlx_vector_array arrays, const mlx_stream s)
    module subroutine mlxf_list_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_list_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_list_op

    ! stops unless dtype is a member of MLX_DTYPES: mlx-c converts it through a table it indexes unchecked
    module subroutine mlxf_check_dtype( dtype, proc )
        integer,          intent(in) :: dtype
        character(len=*), intent(in) :: proc
    end subroutine mlxf_check_dtype

    ! the MLX axes of the Fortran dimensions dims of a, each checked against its rank
    module function mlxf_axes_of( a, dims, proc ) result(axes)
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dims(:)
        character(len=*), intent(in) :: proc
        integer(c_int), allocatable :: axes(:)
    end function mlxf_axes_of

    ! 1-based integer positions as MLX's: one subtracted in the graph, or the amounts less, broadcast along
    module subroutine mlxf_zero_based( r, indices, proc, less )
        type(mlx_array),  intent(inout)        :: r
        type(mlx_array),  intent(in)           :: indices
        character(len=*), intent(in)           :: proc
        integer,          optional, intent(in) :: less(:)
    end subroutine mlxf_zero_based

    ! MLX's 0-based positions as Fortran's: int32, one added in the graph
    module subroutine mlxf_one_based( r, idx, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: idx
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_one_based

    ! stops unless dim is a dimension of a (1 to its rank)
    module subroutine mlxf_check_dim( a, dim, proc )
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dim
        character(len=*), intent(in) :: proc
    end subroutine mlxf_check_dim

    ! the Fortran dimensions a reduction takes: dim, the list dims, or every dimension of a
    module function mlxf_reduced_dims( a, dim, dims ) result(rd)
        type(mlx_array),   intent(in) :: a
        integer, optional, intent(in) :: dim, dims(:)
        integer, allocatable :: rd(:)
    end function mlxf_reduced_dims

    ! whether a reduction of a over the Fortran dimensions rd takes an extent of zero (false for an invalid list)
    module logical function mlxf_empty_reduction( a, rd )
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: rd(:)
    end function mlxf_empty_reduction

    ! MLX's start, stop and strides (the columns of b) of the section option of a: Fortran's inclusive 1-based
    module subroutine mlxf_slice_bounds( a, option, b, proc )
        type(mlx_array),       intent(in)               :: a
        type(mlxf_slice_spec), intent(in)               :: option
        integer(c_int),        allocatable, intent(out) :: b(:,:)
        character(len=*),      intent(in)               :: proc
    end subroutine mlxf_slice_bounds

    ! the default stream of the CPU, where MLX runs what it implements on the CPU only whatever the default
    module function mlxf_cpu_stream( proc ) result(s)
        character(len=*), intent(in) :: proc
        type(mlxc_stream) :: s
    end function mlxf_cpu_stream

    ! the handle of an operand mlx-c may be given as null: null for an empty array, validated otherwise
    module function mlxf_optional_handle( a, proc ) result(h)
        type(mlx_array),  intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
    end function mlxf_optional_handle
end interface

end module mlxf_calls
