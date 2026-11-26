!@descr: data movement between Fortran arrays and mlx_arrays: copies, scalars, read-only views and writable buffers
! mlx_from, mlx_to, mlx_to_alloc and mlx_item copy (submodule mlxf_transfer_copy); mlx_view borrows the
! evaluated buffer and mlx_alloc lends MLX page-aligned Fortran memory (submodule mlxf_transfer_borrow).
module mlxf_transfer
use, intrinsic :: iso_c_binding,   only: c_bool, c_int, c_ptr, c_size_t
use, intrinsic :: iso_fortran_env, only: int16, int32, int64, int8, real32, real64
use mlxf_c_types, only: mlxc_array
use mlxf_array,   only: mlx_array
implicit none

public :: mlx_from, mlx_to, mlx_to_alloc, mlx_item, mlx_view, mlx_alloc
private

! the largest rank MLX takes; Fortran arrays up to rank 15 reach it through assumed rank
integer, parameter :: MAX_RANK = 15

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

    module function from_i8( x ) result(a)
        integer(int8), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i8

    module function from_i16( x ) result(a)
        integer(int16), target, contiguous, intent(in) :: x(..)
        type(mlx_array) :: a
    end function from_i16

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

    module subroutine to_i8( y, a, status )
        integer(int8),   target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i8

    module subroutine to_i16( y, a, status )
        integer(int16),  target, contiguous, intent(inout) :: y(..)
        type(mlx_array), intent(in)                        :: a
        integer,         optional, intent(out)             :: status
    end subroutine to_i16

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

    module subroutine to_alloc_i8( y, a, status )
        integer(int8),   allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i8

    module subroutine to_alloc_i16( y, a, status )
        integer(int16),  allocatable, target, intent(inout) :: y(..)
        type(mlx_array), intent(in)                         :: a
        integer,         optional, intent(out)              :: status
    end subroutine to_alloc_i16

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

interface mlx_item
    module subroutine item_r32( a, value, status )
        type(mlx_array), intent(in)            :: a
        real(real32),    intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_r32

    module subroutine item_r64( a, value, status )
        type(mlx_array), intent(in)            :: a
        real(real64),    intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_r64

    module subroutine item_c32( a, value, status )
        type(mlx_array), intent(in)            :: a
        complex(real32), intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_c32

    module subroutine item_i8( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int8),   intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i8

    module subroutine item_i16( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int16),  intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i16

    module subroutine item_i32( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int32),  intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i32

    module subroutine item_i64( a, value, status )
        type(mlx_array), intent(in)            :: a
        integer(int64),  intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_i64

    module subroutine item_l( a, value, status )
        type(mlx_array), intent(in)            :: a
        logical(c_bool), intent(out)           :: value
        integer,         optional, intent(out) :: status
    end subroutine item_l
end interface mlx_item

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

    module subroutine view_i8( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int8),   pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i8

    module subroutine view_i16( a, p, status )
        type(mlx_array), intent(in)             :: a
        integer(int16),  pointer, intent(inout) :: p(..)
        integer,         optional, intent(out)  :: status
    end subroutine view_i16

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

    module function alloc_i8( fshape, mold, view, status, zero_copy ) result(a)
        integer,       intent(in)             :: fshape(:)
        integer(int8), intent(in)             :: mold
        integer(int8), pointer, intent(inout) :: view(..)
        integer,       optional, intent(out)  :: status
        logical,       optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i8

    module function alloc_i16( fshape, mold, view, status, zero_copy ) result(a)
        integer,        intent(in)             :: fshape(:)
        integer(int16), intent(in)             :: mold
        integer(int16), pointer, intent(inout) :: view(..)
        integer,        optional, intent(out)  :: status
        logical,        optional, intent(out)  :: zero_copy
        type(mlx_array) :: a
    end function alloc_i16

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

interface
    ! the data of an evaluated array as a C pointer of its dtype, for a Fortran pointer over it
    module function data_pointer( h, dtype ) result(p)
        type(mlxc_array), intent(in) :: h
        integer(c_int),   intent(in) :: dtype
        type(c_ptr) :: p
    end function data_pointer

    ! the bytes of one element of an MLX dtype
    module pure integer(c_size_t) function itemsize( dtype )
        integer(c_int), intent(in) :: dtype
    end function itemsize
end interface

end module mlxf_transfer
