!@descr: the mlx_array type: its interface; lifetime, transfer, borrowing, evaluation and operations in submodules
! A Fortran array of shape (n1, ..., nr) is the MLX array of shape [nr, ..., n1] over the same bytes. A copy is
! the defined assignment, which counts a reference; a copy made without it (an allocatable component of a
! derived type, allocate(source=), an array intrinsic) is detected through the registry and stops at its next
! use. One type and one ownership implementation; the submodules share only what this interface declares.
module mlxf_array
use, intrinsic :: iso_c_binding,   only: c_bool, c_int, c_ptr, c_size_t, c_double
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf_c_types, only: mlxc_array, mlxc_stream, mlxc_vector_array, mlxc_optional_dtype
use mlxf_defs,    only: mlxf_slice_spec, mlxf_fft_spec, mlxf_range_spec
implicit none

public :: mlx_array, mlx_from, mlx_to, mlx_to_alloc, mlx_view, mlx_alloc, mlx_eval, mlx_async_eval
public :: mlxf_int_op, &
    &mlxf_vector_op, &
    &mlxf_reduce_op, &
    &mlxf_ternary_op, &
    &mlxf_take_op, &
    &mlxf_scan_op, &
    &mlxf_slice_op, &
    &mlxf_concat_op, &
    &mlxf_zeros_op, &
    &mlxf_range_op, &
    &mlxf_fft_op, &
    &mlxf_fft2_op
public :: mlxf_vector_import, mlxf_vector_export
public :: mlxf_weak_scalar
public :: mlx_synchronize, mlx_is_live, exp, mlxf_handle, mlxf_unary, mlxf_binary, mlxc_unary_op, mlxc_binary_op
private

! the largest rank MLX takes; Fortran arrays up to rank 15 reach it through assumed rank
integer, parameter :: MAX_RANK = 15

type :: mlx_array
    private
    type(mlxc_array) :: h
    integer(int64)   :: serial = 0_int64
  contains
    procedure, private            :: assign_array
    generic                       :: assignment(=) => assign_array
    procedure                     :: shape => array_shape
    procedure                     :: ndim  => array_ndim
    procedure                     :: size  => array_size
    procedure                     :: kind  => array_kind
    procedure                     :: kill  => kill_array
    procedure, private            :: add_aa
    procedure, private            :: add_as
    procedure, private, pass(rhs) :: add_sa
    procedure, private            :: add_ad
    procedure, private, pass(rhs) :: add_da
    generic                       :: operator(+) => add_aa, add_as, add_sa, add_ad, add_da
    procedure, private            :: sub_aa
    procedure, private            :: sub_as
    procedure, private, pass(rhs) :: sub_sa
    procedure, private            :: sub_ad
    procedure, private, pass(rhs) :: sub_da
    generic                       :: operator(-) => sub_aa, sub_as, sub_sa, sub_ad, sub_da, negate_array
    procedure, private            :: mul_aa
    procedure, private            :: mul_as
    procedure, private, pass(rhs) :: mul_sa
    procedure, private            :: mul_ad
    procedure, private, pass(rhs) :: mul_da
    generic                       :: operator(*) => mul_aa, mul_as, mul_sa, mul_ad, mul_da
    procedure, private            :: div_aa
    procedure, private            :: div_as
    procedure, private, pass(rhs) :: div_sa
    procedure, private            :: div_ad
    procedure, private, pass(rhs) :: div_da
    generic                       :: operator(/) => div_aa, div_as, div_sa, div_ad, div_da
    procedure, private            :: lt_aa
    procedure, private            :: lt_as
    procedure, private, pass(rhs) :: lt_sa
    procedure, private            :: lt_ad
    procedure, private, pass(rhs) :: lt_da
    generic                       :: operator(<) => lt_aa, lt_as, lt_sa, lt_ad, lt_da
    procedure, private            :: le_aa
    procedure, private            :: le_as
    procedure, private, pass(rhs) :: le_sa
    procedure, private            :: le_ad
    procedure, private, pass(rhs) :: le_da
    generic                       :: operator(<=) => le_aa, le_as, le_sa, le_ad, le_da
    procedure, private            :: gt_aa
    procedure, private            :: gt_as
    procedure, private, pass(rhs) :: gt_sa
    procedure, private            :: gt_ad
    procedure, private, pass(rhs) :: gt_da
    generic                       :: operator(>) => gt_aa, gt_as, gt_sa, gt_ad, gt_da
    procedure, private            :: ge_aa
    procedure, private            :: ge_as
    procedure, private, pass(rhs) :: ge_sa
    procedure, private            :: ge_ad
    procedure, private, pass(rhs) :: ge_da
    generic                       :: operator(>=) => ge_aa, ge_as, ge_sa, ge_ad, ge_da
    procedure, private            :: eq_aa
    procedure, private            :: eq_as
    procedure, private, pass(rhs) :: eq_sa
    procedure, private            :: eq_ad
    procedure, private, pass(rhs) :: eq_da
    generic                       :: operator(==) => eq_aa, eq_as, eq_sa, eq_ad, eq_da
    procedure, private            :: ne_aa
    procedure, private            :: ne_as
    procedure, private, pass(rhs) :: ne_sa
    procedure, private            :: ne_ad
    procedure, private, pass(rhs) :: ne_da
    generic                       :: operator(/=) => ne_aa, ne_as, ne_sa, ne_ad, ne_da
    procedure, private            :: land_aa
    generic                       :: operator(.and.) => land_aa
    procedure, private            :: lor_aa
    generic                       :: operator(.or.) => lor_aa
    procedure, private            :: negate_array
    procedure, private            :: not_array
    generic                       :: operator(.not. ) => not_array
    final                         :: finalize_array
end type mlx_array

abstract interface
    ! int f(mlx_array* res, const mlx_array a, const mlx_stream s)
    function mlxc_unary_op( res, a, s ) bind(c)
        import :: mlxc_array, mlxc_stream, c_int
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_unary_op
    end function mlxc_unary_op

    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s)
    function mlxc_binary_op( res, a, b, s ) bind(c)
        import :: mlxc_array, mlxc_stream, c_int
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_array),  value         :: a, b
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_binary_op
    end function mlxc_binary_op
end interface

abstract interface
    ! int f(mlx_array* res, const mlx_array a, mlx_dtype dtype, const mlx_stream s)
    function mlxc_int_op( res, a, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_int_op
    end function mlxc_int_op
    ! int f(mlx_array* res, const mlx_array a, const int* shape, size_t shape_num, const mlx_stream s)
    function mlxc_vector_op( res, a, shape, shape_num, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), intent(in)      :: shape(*)
        integer(c_size_t), value        :: shape_num
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_vector_op
    end function mlxc_vector_op
    ! int f(mlx_array* res, const mlx_array a, int axis, bool keepdims, const mlx_stream s)
    function mlxc_reduce_op( res, a, axis, keepdims, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), value           :: axis
        logical(c_bool), value          :: keepdims
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_reduce_op
    end function mlxc_reduce_op
    ! int f(mlx_array* res, const mlx_array condition, const mlx_array x, const mlx_array y,
    ! const mlx_stream s)
    function mlxc_ternary_op( res, condition, x, y, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: condition
        type(mlxc_array), value         :: x
        type(mlxc_array), value         :: y
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_ternary_op
    end function mlxc_ternary_op
    ! int f(mlx_array* res, const mlx_array a, const mlx_array indices, int axis, const mlx_stream s)
    function mlxc_take_op( res, a, indices, axis, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        type(mlxc_array), value         :: indices
        integer(c_int), value           :: axis
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_take_op
    end function mlxc_take_op
    ! int f(mlx_array* res, const mlx_array a, int axis, bool reverse, bool inclusive,
    ! mlx_optional_dtype dtype, const mlx_stream s)
    function mlxc_scan_op( res, a, axis, reverse, inclusive, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout)  :: res
        type(mlxc_array), value          :: a
        integer(c_int), value            :: axis
        logical(c_bool), value           :: reverse
        logical(c_bool), value           :: inclusive
        type(mlxc_optional_dtype), value :: dtype
        type(mlxc_stream), value         :: s
        integer(c_int) :: mlxc_scan_op
    end function mlxc_scan_op
    ! int f(mlx_array* res, const mlx_array a, const int* start, size_t start_num, const int* stop,
    ! size_t stop_num, const int* strides, size_t strides_num, const mlx_stream s)
    function mlxc_slice_op( res, a, start, start_num, stop, stop_num, strides, strides_num, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), intent(in)      :: start(*)
        integer(c_size_t), value        :: start_num
        integer(c_int), intent(in)      :: stop(*)
        integer(c_size_t), value        :: stop_num
        integer(c_int), intent(in)      :: strides(*)
        integer(c_size_t), value        :: strides_num
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_slice_op
    end function mlxc_slice_op
    ! int f(mlx_array* res, const mlx_vector_array arrays, int axis, const mlx_stream s)
    function mlxc_concat_op( res, arrays, axis, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_vector_array), value  :: arrays
        integer(c_int), value           :: axis
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_concat_op
    end function mlxc_concat_op
    ! int f(mlx_array* res, const int* shape, size_t shape_num, mlx_dtype dtype, const mlx_stream s)
    function mlxc_zeros_op( res, shape, shape_num, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        integer(c_int), intent(in)      :: shape(*)
        integer(c_size_t), value        :: shape_num
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_zeros_op
    end function mlxc_zeros_op
    ! int f(mlx_array* res, double start, double stop, double step, mlx_dtype dtype, const mlx_stream s)
    function mlxc_range_op( res, start, stop, step, dtype, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        real(c_double), value           :: start
        real(c_double), value           :: stop
        real(c_double), value           :: step
        integer(c_int), value           :: dtype
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_range_op
    end function mlxc_range_op
    ! int f(mlx_array* res, const mlx_array a, int n, int axis, mlx_fft_norm norm, const mlx_stream s)
    function mlxc_fft_op( res, a, n, axis, norm, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), value           :: n
        integer(c_int), value           :: axis
        integer(c_int), value           :: norm
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_fft_op
    end function mlxc_fft_op
    ! int f(mlx_array* res, const mlx_array a, const int* n, size_t n_num, const int* axes,
    ! size_t axes_num, mlx_fft_norm norm, const mlx_stream s)
    function mlxc_fft2_op( res, a, n, n_num, axes, axes_num, norm, s ) bind(c)
        import
        type(mlxc_array), intent(inout) :: res
        type(mlxc_array), value         :: a
        integer(c_int), intent(in)      :: n(*)
        integer(c_size_t), value        :: n_num
        integer(c_int), intent(in)      :: axes(*)
        integer(c_size_t), value        :: axes_num
        integer(c_int), value           :: norm
        type(mlxc_stream), value        :: s
        integer(c_int) :: mlxc_fft2_op
    end function mlxc_fft2_op
end interface

interface exp
    module function exp_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function exp_array
end interface exp

interface mlx_from
    module function from_r32( x ) result(a)
        real(real32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_r32

    module function from_r64( x ) result(a)
        real(real64), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_r64

    module function from_c32( x ) result(a)
        complex(real32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_c32

    module function from_i32( x ) result(a)
        integer(int32), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i32

    module function from_i64( x ) result(a)
        integer(int64), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i64

    module function from_l( x ) result(a)
        logical(c_bool), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_l
end interface mlx_from

interface mlx_to
    module subroutine to_r32( y, a, status )
        real(real32),    target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_r32

    module subroutine to_r64( y, a, status )
        real(real64),    target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_r64

    module subroutine to_c32( y, a, status )
        complex(real32), target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_c32

    module subroutine to_i32( y, a, status )
        integer(int32),  target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i32

    module subroutine to_i64( y, a, status )
        integer(int64),  target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i64

    module subroutine to_l( y, a, status )
        logical(c_bool), target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_l
end interface mlx_to

interface mlx_to_alloc
    module subroutine to_alloc_r32( y, a, status )
        real(real32),    allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_r32

    module subroutine to_alloc_r64( y, a, status )
        real(real64),    allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_r64

    module subroutine to_alloc_c32( y, a, status )
        complex(real32), allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_c32

    module subroutine to_alloc_i32( y, a, status )
        integer(int32),  allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i32

    module subroutine to_alloc_i64( y, a, status )
        integer(int64),  allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i64

    module subroutine to_alloc_l( y, a, status )
        logical(c_bool), allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_l
end interface mlx_to_alloc

interface mlx_view
    module subroutine view_r32( a, p, status )
        type(mlx_array), intent(in)             :: a
        real(real32),    pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_r32

    module subroutine view_r64( a, p, status )
        type(mlx_array), intent(in)             :: a
        real(real64),    pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_r64

    module subroutine view_c32( a, p, status )
        type(mlx_array), intent(in)             :: a
        complex(real32), pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_c32

    module subroutine view_i32( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int32),  pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i32

    module subroutine view_i64( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int64),  pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i64

    module subroutine view_l( a, p, status )
        type(mlx_array), intent(in)             :: a
        logical(c_bool), pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_l
end interface mlx_view

interface mlx_alloc
    module function alloc_r32( fshape, mold, view, status, zero_copy ) result(a)
        integer,      intent(in)             :: fshape(:)
        real(real32), intent(in)             :: mold
        real(real32), pointer, intent(inout) :: view(..)
        integer,      optional, intent(out)  :: status
        logical,      optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_r32

    module function alloc_r64( fshape, mold, view, status, zero_copy ) result(a)
        integer,      intent(in)             :: fshape(:)
        real(real64), intent(in)             :: mold
        real(real64), pointer, intent(inout) :: view(..)
        integer,      optional, intent(out)  :: status
        logical,      optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_r64

    module function alloc_c32( fshape, mold, view, status, zero_copy ) result(a)
        integer,         intent(in)             :: fshape(:)
        complex(real32), intent(in)             :: mold
        complex(real32), pointer, intent(inout) :: view(..)
        integer,         optional, intent(out)  :: status
        logical,         optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_c32

    module function alloc_i32( fshape, mold, view, status, zero_copy ) result(a)
        integer,        intent(in)             :: fshape(:)
        integer(int32), intent(in)             :: mold
        integer(int32), pointer, intent(inout) :: view(..)
        integer,        optional, intent(out)  :: status
        logical,        optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i32

    module function alloc_i64( fshape, mold, view, status, zero_copy ) result(a)
        integer,        intent(in)             :: fshape(:)
        integer(int64), intent(in)             :: mold
        integer(int64), pointer, intent(inout) :: view(..)
        integer,        optional, intent(out)  :: status
        logical,        optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i64

    module function alloc_l( fshape, mold, view, status, zero_copy ) result(a)
        integer,         intent(in)             :: fshape(:)
        logical(c_bool), intent(in)             :: mold
        logical(c_bool), pointer, intent(inout) :: view(..)
        integer,         optional, intent(out)  :: status
        logical,         optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_l
end interface mlx_alloc

interface mlx_eval
    module subroutine eval_one( a, status )
        type(mlx_array), intent(in)            :: a
        integer,         optional, intent(out) :: status
    end subroutine eval_one

    module subroutine eval_list( arrays, status )
        type(mlx_array), intent(in)            :: arrays(:)
        integer,         optional, intent(out) :: status
    end subroutine eval_list
end interface mlx_eval

interface mlx_async_eval
    module subroutine async_eval_one( a, status )
        type(mlx_array), intent(in)            :: a
        integer,         optional, intent(out) :: status
    end subroutine async_eval_one

    module subroutine async_eval_list( arrays, status )
        type(mlx_array), intent(in)            :: arrays(:)
        integer,         optional, intent(out) :: status
    end subroutine async_eval_list
end interface mlx_async_eval

! the procedures the type binds, the helpers the submodules share, and mlx_synchronize
interface
    module impure elemental subroutine assign_array( lhs, rhs )
        class(mlx_array), intent(inout) :: lhs
        class(mlx_array), intent(in)    :: rhs
    end subroutine assign_array

    module impure elemental subroutine kill_array( self )
        class(mlx_array), intent(inout) :: self
    end subroutine kill_array

    module impure elemental subroutine finalize_array( self )
        type(mlx_array), intent(inout) :: self
    end subroutine finalize_array

    module subroutine adopt( a, h, proc, status )
        type(mlx_array),   intent(inout) :: a
        type(mlxc_array),  intent(in)    :: h
        character(len=*),  intent(in)    :: proc
        integer, optional, intent(out)   :: status
    end subroutine adopt

    module function mlxf_handle( a, proc ) result(h)
        class(mlx_array), intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
    end function mlxf_handle

    module logical function mlx_is_live( a )
        type(mlx_array), intent(in) :: a
    end function mlx_is_live

    module function array_shape( self ) result(s)
        class(mlx_array), intent(in) :: self
        integer, allocatable :: s(:)
    end function array_shape

    module integer function array_ndim( self )
        class(mlx_array), intent(in) :: self
    end function array_ndim

    module integer(int64) function array_size( self )
        class(mlx_array), intent(in) :: self
    end function array_size

    module integer function array_kind( self )
        class(mlx_array), intent(in) :: self
    end function array_kind

    module function data_pointer( h, dtype ) result(p)
        type(mlxc_array), intent(in) :: h
        integer(c_int),   intent(in) :: dtype
        type(c_ptr) :: p
    end function data_pointer

    module pure integer(c_size_t) function itemsize( dtype )
        integer(c_int), intent(in) :: dtype
    end function itemsize

    module subroutine mlx_synchronize( status )
        integer, optional, intent(out) :: status
    end subroutine mlx_synchronize

    module subroutine mlxf_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_unary

    module subroutine mlxf_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_binary

    module function add_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function add_aa
    module function add_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function add_as
    module function add_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function add_sa
    module function add_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function add_ad
    module function add_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function add_da
    module function sub_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function sub_aa
    module function sub_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_as
    module function sub_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_sa
    module function sub_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_ad
    module function sub_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function sub_da
    module function mul_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function mul_aa
    module function mul_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_as
    module function mul_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_sa
    module function mul_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_ad
    module function mul_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function mul_da
    module function div_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function div_aa
    module function div_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function div_as
    module function div_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function div_sa
    module function div_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function div_ad
    module function div_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function div_da
    module function lt_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function lt_aa
    module function lt_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_as
    module function lt_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_sa
    module function lt_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_ad
    module function lt_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function lt_da
    module function le_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function le_aa
    module function le_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function le_as
    module function le_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function le_sa
    module function le_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function le_ad
    module function le_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function le_da
    module function gt_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function gt_aa
    module function gt_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_as
    module function gt_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_sa
    module function gt_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_ad
    module function gt_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function gt_da
    module function ge_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function ge_aa
    module function ge_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_as
    module function ge_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_sa
    module function ge_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_ad
    module function ge_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ge_da
    module function eq_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function eq_aa
    module function eq_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_as
    module function eq_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_sa
    module function eq_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_ad
    module function eq_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function eq_da
    module function ne_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function ne_aa
    module function ne_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_as
    module function ne_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_sa
    module function ne_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_ad
    module function ne_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function ne_da
    module function land_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function land_aa
    module function lor_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function lor_aa
    module function negate_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function negate_array
    module function not_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function not_array
end interface

interface
    module subroutine mlxf_weak_scalar( r, a, x, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        real(real64),     intent(in)    :: x
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_weak_scalar
end interface

interface
    module subroutine mlxf_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_int_op)          :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_int_op
    module subroutine mlxf_vector_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_vector_op)       :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_vector_op
    module subroutine mlxf_reduce_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_reduce_op)       :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_reduce_op
    module subroutine mlxf_ternary_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_ternary_op)      :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_ternary_op
    module subroutine mlxf_take_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_take_op)         :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_take_op
    module subroutine mlxf_scan_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_scan_op)         :: f
        type(mlx_array),  intent(in)    :: a
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_scan_op
    module subroutine mlxf_slice_op( r, f, a, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_slice_op)             :: f
        type(mlx_array),       intent(in)    :: a
        type(mlxf_slice_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_slice_op
    module subroutine mlxf_concat_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_concat_op)       :: f
        type(mlx_array),  intent(in)    :: a(:)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_concat_op
    module subroutine mlxf_zeros_op( r, f, shape, dtype, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_zeros_op)        :: f
        integer,          intent(in)    :: shape(:), dtype
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_zeros_op
    module subroutine mlxf_range_op( r, f, option, proc )
        type(mlx_array),       intent(inout) :: r
        procedure(mlxc_range_op)             :: f
        type(mlxf_range_spec), intent(in)    :: option
        character(len=*),      intent(in)    :: proc
    end subroutine mlxf_range_op
    module subroutine mlxf_fft_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_fft_op)             :: f
        type(mlx_array),     intent(in)    :: a
        type(mlxf_fft_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_fft_op
    module subroutine mlxf_fft2_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_fft2_op)            :: f
        type(mlx_array),     intent(in)    :: a
        type(mlxf_fft_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_fft2_op
    module subroutine check_dim( a, dim, proc )
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dim
        character(len=*), intent(in) :: proc
    end subroutine check_dim
    module function vector_of( arrays, proc ) result(v)
        type(mlx_array),  intent(in) :: arrays(:)
        character(len=*), intent(in) :: proc
        type(mlxc_vector_array) :: v
    end function vector_of
end interface

interface
    module subroutine mlxf_vector_import( arrays, v, status )
        type(mlx_array),         allocatable, intent(out) :: arrays(:)
        type(mlxc_vector_array), intent(in)               :: v
        integer,                 intent(out)              :: status
    end subroutine mlxf_vector_import
    module subroutine mlxf_vector_export( v, arrays, status )
        type(mlxc_vector_array), intent(inout) :: v
        type(mlx_array),         intent(in)    :: arrays(:)
        integer,                 intent(out)   :: status
    end subroutine mlxf_vector_export
end interface

end module mlxf_array
