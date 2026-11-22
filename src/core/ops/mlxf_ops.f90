!@descr: elementwise, shape, index and reduction operations in Fortran conventions
module mlxf_ops
use, intrinsic :: iso_fortran_env, only: real32, real64, int32
use mlxf_array, only: mlx_array
implicit none
public :: real, &
    &aimag, &
    &conjg, &
    &sqrt, &
    &mlx_astype, &
    &max, &
    &merge, &
    &cmplx, &
    &reshape, &
    &mlx_permute, &
    &transpose, &
    &mlx_concatenate, &
    &mlx_slice, &
    &mlx_take_along_dim, &
    &sum, &
    &minval, &
    &mlx_logsumexp, &
    &mlx_cumsum, &
    &minloc, &
    &mlx_zeros, &
    &mlx_arange
private
interface real
    module procedure real_array
end interface real

interface aimag
    module procedure aimag_array
end interface aimag

interface conjg
    module procedure conjg_array
end interface conjg

interface sqrt
    module procedure sqrt_array
end interface sqrt

interface max
    module procedure max_array, max_ass, max_sas, max_asd, max_sad
end interface max

interface merge
    module procedure merge_array
end interface merge

interface cmplx
    module procedure cmplx_array
end interface cmplx

interface reshape
    module procedure reshape_array
end interface reshape

interface transpose
    module procedure transpose_array
end interface transpose

interface sum
    module procedure sum_array
end interface sum

interface minval
    module procedure minval_array
end interface minval

interface minloc
    module procedure minloc_array
end interface minloc

interface
    module function real_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function real_array
    module function aimag_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function aimag_array
    module function conjg_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function conjg_array
    module function sqrt_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function sqrt_array
    module function mlx_astype( a, dtype ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_astype
    module function max_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
    end function max_array
    module function max_ass( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real32),    intent(in) :: b
        type(mlx_array) :: r
    end function max_ass
    module function max_sas( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real32),    intent(in) :: a
        type(mlx_array) :: r
    end function max_sas
    module function max_asd( a, b ) result(r)
        type(mlx_array), intent(in) :: a
        real(real64),    intent(in) :: b
        type(mlx_array) :: r
    end function max_asd
    module function max_sad( a, b ) result(r)
        type(mlx_array), intent(in) :: b
        real(real64),    intent(in) :: a
        type(mlx_array) :: r
    end function max_sad
    module function merge_array( tsource, fsource, mask ) result(r)
        type(mlx_array), intent(in) :: tsource, fsource, mask
        type(mlx_array) :: r
    end function merge_array
    module function cmplx_array( x, y ) result(r)
        type(mlx_array), intent(in) :: x, y
        type(mlx_array) :: r
    end function cmplx_array
    module function reshape_array( a, shape ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: shape(:)
        type(mlx_array) :: r
    end function reshape_array
    module function mlx_permute( a, order ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: order(:)
        type(mlx_array) :: r
    end function mlx_permute
    module function transpose_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function transpose_array
    module function mlx_concatenate( arrays, dim ) result(r)
        type(mlx_array), intent(in) :: arrays(:)
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_concatenate
    module function mlx_slice( a, lower, upper, stride ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: lower(:), upper(:)
        integer,         optional, intent(in) :: stride(:)
        type(mlx_array) :: r
    end function mlx_slice
    module function mlx_take_along_dim( a, indices, dim ) result(r)
        type(mlx_array), intent(in) :: a, indices
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_take_along_dim
    module function sum_array( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function sum_array
    module function minval_array( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function minval_array
    module function mlx_logsumexp( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_logsumexp
    module function mlx_cumsum( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function mlx_cumsum
    module function minloc_array( a, dim ) result(r)
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: dim
        type(mlx_array) :: r
    end function minloc_array
    module function mlx_zeros( shape, dtype ) result(r)
        integer, intent(in)           :: shape(:)
        integer, optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_zeros
    module function mlx_arange( start, stop, step, dtype ) result(r)
        real(real64), intent(in)           :: start, stop
        real(real64), optional, intent(in) :: step
        integer,      optional, intent(in) :: dtype
        type(mlx_array) :: r
    end function mlx_arange
end interface

end module mlxf_ops
