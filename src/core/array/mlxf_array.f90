!@descr: the mlx_array type: its interface; lifetime, transfer, borrowing, evaluation and operations in submodules
! A Fortran array of shape (n1, ..., nr) is the MLX array of shape [nr, ..., n1] over the same bytes. A copy is
! the defined assignment, which counts a reference; a copy made without it (an allocatable component of a
! derived type, allocate(source=), an array intrinsic) is detected through the registry and stops at its next
! use. One type and one ownership implementation; the submodules share only what this interface declares.
module mlxf_array
use, intrinsic :: iso_c_binding, only: c_bool, c_int, c_ptr, c_size_t
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf_c_types, only: mlxc_array, mlxc_stream
implicit none

public :: mlx_array, mlx_from, mlx_to, mlx_to_alloc, mlx_view, mlx_alloc, mlx_eval, mlx_async_eval
public :: mlx_synchronize, mlx_is_live, exp, mlxf_handle, mlxf_unary, mlxf_binary, mlxc_unary_op, mlxc_binary_op
private

! the largest rank MLX takes; Fortran arrays up to rank 15 reach it through assumed rank
integer, parameter :: MAX_RANK = 15

type :: mlx_array
    private
    type(mlxc_array) :: h
    integer(int64)   :: serial = 0_int64
  contains
    procedure, private :: assign_array
    generic            :: assignment(=) => assign_array
    procedure          :: shape => array_shape
    procedure          :: ndim  => array_ndim
    procedure          :: size  => array_size
    procedure          :: kind  => array_kind
    procedure          :: kill  => kill_array
    procedure, private :: add_aa, add_as, sub_aa, sub_as, mul_aa, mul_as
    procedure, private, pass(rhs) :: add_sa, sub_sa, mul_sa
    generic            :: operator(+) => add_aa, add_as, add_sa
    generic            :: operator(-) => sub_aa, sub_as, sub_sa
    generic            :: operator(*) => mul_aa, mul_as, mul_sa
    final              :: finalize_array
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

    module subroutine adopt( a, h, proc )
        type(mlx_array),  intent(inout) :: a
        type(mlxc_array), intent(in)    :: h
        character(len=*), intent(in)    :: proc
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
end interface

end module mlxf_array
