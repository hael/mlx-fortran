!@descr: the mlx_array type: its interface; lifetime, evaluation, operators and closure vectors in submodules
! A Fortran array of shape (n1, ..., nr) is the MLX array of shape [nr, ..., n1] over the same bytes. A copy is
! the defined assignment, which counts a reference; a copy made without it (an allocatable component of a
! derived type, allocate(source=), an array intrinsic) is detected through the registry and stops at its next
! use. One type and one ownership implementation; the submodules share only what this interface declares.
module mlxf_array
use, intrinsic :: iso_c_binding,   only: c_int, c_size_t
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_c_types, only: mlxc_array, mlxc_vector_array
implicit none

public :: mlx_array, mlx_eval, mlx_async_eval
public :: mlx_buffer_size
public :: mlxf_vector_import, mlxf_vector_export
public :: mlxf_adopt, mlxf_vector_of
public :: mlx_synchronize, mlx_is_live, mlxf_is_empty, exp, mlxf_handle
private

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
    procedure                     :: nbytes => array_nbytes
    procedure                     :: itemsize => array_itemsize
    procedure                     :: kill  => kill_array
    procedure, private            :: add_aa
    procedure, private            :: add_as
    procedure, private, pass(rhs) :: add_sa
    procedure, private            :: add_ad
    procedure, private, pass(rhs) :: add_da
    procedure, private            :: pos_array
    generic                       :: operator(+) => add_aa, add_as, add_sa, add_ad, add_da, pos_array
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
    procedure, private            :: pow_aa
    procedure, private            :: pow_as
    procedure, private, pass(rhs) :: pow_sa
    procedure, private            :: pow_ad
    procedure, private, pass(rhs) :: pow_da
    generic                       :: operator(**) => pow_aa, pow_as, pow_sa, pow_ad, pow_da
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
    procedure, private            :: eqv_aa
    generic                       :: operator(.eqv.) => eqv_aa
    procedure, private            :: neqv_aa
    generic                       :: operator(.neqv.) => neqv_aa
    procedure, private            :: negate_array
    procedure, private            :: not_array
    generic                       :: operator(.not. ) => not_array
    final                         :: finalize_array
end type mlx_array

interface exp
    module function exp_array( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function exp_array
end interface exp

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

! waiting for queued work: on every device (here), or on one stream (the stream module's specific)
interface mlx_synchronize
    procedure synchronize_all
end interface mlx_synchronize

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

    module subroutine mlxf_adopt( a, h, proc, status )
        type(mlx_array),   intent(inout) :: a
        type(mlxc_array),  intent(in)    :: h
        character(len=*),  intent(in)    :: proc
        integer, optional, intent(out)   :: status
    end subroutine mlxf_adopt

    module function mlxf_handle( a, proc ) result(h)
        class(mlx_array), intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
    end function mlxf_handle

    module logical function mlx_is_live( a )
        type(mlx_array), intent(in) :: a
    end function mlx_is_live

    module pure logical function mlxf_is_empty( a )
        class(mlx_array), intent(in) :: a
    end function mlxf_is_empty

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

    module subroutine synchronize_all( status )
        integer, optional, intent(out) :: status
    end subroutine synchronize_all

    module integer(int64) function array_nbytes( self )
        class(mlx_array), intent(in) :: self
    end function array_nbytes

    module integer function array_itemsize( self )
        class(mlx_array), intent(in) :: self
    end function array_itemsize

    module function mlx_buffer_size( arrays, status ) result(n)
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        integer(int64) :: n
    end function mlx_buffer_size

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

    module function pos_array( a ) result(r)
        class(mlx_array), intent(in) :: a
        type(mlx_array) :: r
    end function pos_array

    module function pow_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function pow_aa

    module function pow_as( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real32),     intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_as

    module function pow_sa( lhs, rhs ) result(r)
        real(real32),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_sa

    module function pow_ad( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs
        real(real64),     intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_ad

    module function pow_da( lhs, rhs ) result(r)
        real(real64),     intent(in) :: lhs
        class(mlx_array), intent(in) :: rhs
        type(mlx_array) :: r
    end function pow_da

    module function eqv_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function eqv_aa

    module function neqv_aa( lhs, rhs ) result(r)
        class(mlx_array), intent(in) :: lhs, rhs
        type(mlx_array) :: r
    end function neqv_aa

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
    module function mlxf_vector_of( arrays, proc ) result(v)
        type(mlx_array),  intent(in) :: arrays(:)
        character(len=*), intent(in) :: proc
        type(mlxc_vector_array) :: v
    end function mlxf_vector_of
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
