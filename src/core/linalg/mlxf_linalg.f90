!@descr: products with Fortran dimensions: matrix products (batched, gathered, masked, segmented, added), inner, outer, Kronecker and cross products, contractions and Einstein sums
! A Fortran matrix is dimensions 1 and 2 of an array and MLX sees it transposed, so every matrix product is called
! with its operands exchanged: MLX's product of the transposes is the transpose of the Fortran product. The same
! exchange puts the dimensions of an inner product, an outer product and a contraction in Fortran's order, a's
! before b's. A selection of matrices, a mask, a segment, a dimension and a subscript are given as Fortran reads
! them.
module mlxf_linalg
use, intrinsic :: iso_c_binding,   only: c_bool, c_int, c_null_char, c_size_t, c_float_kind => c_float
use, intrinsic :: iso_fortran_env, only: real32
use mlxf_c_array,      only: mlxc_array_free, mlxc_array_new
use mlxf_c_linalg,     only: mlxc_linalg_cross
use mlxf_c_ops,        only: mlxc_matmul, mlxc_gather_mm, mlxc_block_masked_mm, mlxc_segmented_mm, mlxc_addmm, &
                             mlxc_einsum, mlxc_hadamard_transform, mlxc_inner, mlxc_kron, mlxc_outer, mlxc_tensordot, &
                             mlxc_tensordot_axis, mlxc_vecdot
use mlxf_c_signatures, only: mlxc_addmm_op, mlxc_einsum_op, mlxc_gather_mm_op, mlxc_masked_mm_op, &
                             mlxc_optional_float_op, mlxc_take_op, mlxc_tensordot_op
use mlxf_c_stream,     only: mlxc_stream_free
use mlxf_c_types,      only: mlxc_array, mlxc_optional_float, mlxc_stream, mlxc_vector_array
use mlxf_c_vector,     only: mlxc_vector_array_free
use mlxf_array,        only: mlx_array, mlx_is_live, mlxf_handle, mlxf_is_empty, mlxf_vector_of, mlxf_adopt
use mlxf_device,       only: mlxf_enter, mlxf_default_stream, mlxf_require_device
use mlxf_error,        only: mlxf_fail, mlxf_check
use mlxf_calls,        only: mlxf_axes_of, mlxf_binary, mlxf_ternary_op, mlxf_zero_based
implicit none
public :: matmul, mlx_gather_mm, mlx_block_masked_mm, mlx_segmented_mm, mlx_addmm, mlx_inner, mlx_outer, mlx_kron
public :: mlx_vecdot, mlx_cross, mlx_tensordot, mlx_einsum, mlx_hadamard_transform
private
interface matmul
    module procedure matmul_array
end interface matmul

interface mlx_tensordot
    module procedure tensordot_count, tensordot_dims
end interface mlx_tensordot

contains

    ! Fortran's matmul(a, b), batched over dimensions 3 and up: in MLX's reversed view of the bytes this is
    ! matmul(b, a)
    function matmul_array( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_matmul, b, a, 'matmul')
    end function matmul_array

    ! the products of chosen matrices: r(:,:,i) = matmul(a(:,:,lhs_indices(i)), b(:,:,rhs_indices(i))), the index
    ! arrays broadcast together and their shape following dimensions 1 and 2. An index is the 1-based number of a
    ! matrix in array element order over dimensions 3 and up; absent indices take every matrix of the operand
    function mlx_gather_mm( a, b, lhs_indices, rhs_indices, sorted_indices ) result(r)
        type(mlx_array), intent(in)           :: a, b
        type(mlx_array), optional, intent(in) :: lhs_indices, rhs_indices
        logical,         optional, intent(in) :: sorted_indices
        type(mlx_array) :: r, ops(4)
        logical         :: sorted
        call mlxf_enter('mlx_gather_mm')
        ops(1) = b
        ops(2) = a
        if( present(rhs_indices) ) call mlxf_zero_based(ops(3), rhs_indices, 'mlx_gather_mm')
        if( present(lhs_indices) ) call mlxf_zero_based(ops(4), lhs_indices, 'mlx_gather_mm')
        sorted = .false.
        if( present(sorted_indices) ) sorted = sorted_indices
        call mlxf_gather_mm_op(r, mlxc_gather_mm, ops, sorted, 'mlx_gather_mm')
    end function mlx_gather_mm

    ! matmul(a, b) with blocks of block_size rows and columns (32 or 64; default 64) left out: mask_out(i, j) keeps
    ! or zeroes block (i, j) of the result, operand_masks(1) the blocks of a and operand_masks(2) those of b before
    ! the product. A mask is boolean (false zeroes), or real and multiplies its block
    function mlx_block_masked_mm( a, b, block_size, mask_out, operand_masks ) result(r)
        type(mlx_array), intent(in)           :: a, b
        integer,         optional, intent(in) :: block_size
        type(mlx_array), optional, intent(in) :: mask_out, operand_masks(2)
        type(mlx_array) :: r, ops(5)
        integer         :: block
        call mlxf_enter('mlx_block_masked_mm')
        ops(1) = b
        ops(2) = a
        if( present(mask_out) )then
            if( .not. mlx_is_live(mask_out) ) call mlxf_fail('mlx_block_masked_mm', 'empty or stale mask_out')
            ops(3) = mask_out
        endif
        if( present(operand_masks) )then
            if( .not. mlx_is_live(operand_masks(1)) ) call mlxf_fail('mlx_block_masked_mm', 'empty or stale mask of a')
            if( .not. mlx_is_live(operand_masks(2)) ) call mlxf_fail('mlx_block_masked_mm', 'empty or stale mask of b')
            ops(4) = operand_masks(2)
            ops(5) = operand_masks(1)
        endif
        block = 64
        if( present(block_size) ) block = block_size
        call mlxf_masked_mm_op(r, mlxc_block_masked_mm, ops, block, 'mlx_block_masked_mm')
    end function mlx_block_masked_mm

    ! the product of two matrices cut along the inner dimension: r(:,:,i) = matmul(a(:, s1:s2), b(s1:s2, :)) with
    ! s1 = segments(1, i) and s2 = segments(2, i), inclusive and 1-based; an empty section gives zeros. The
    ! segments' dimensions 2 and up follow dimensions 1 and 2 of the result
    function mlx_segmented_mm( a, b, segments ) result(r)
        type(mlx_array), intent(in) :: a, b, segments
        type(mlx_array)      :: r, bounds
        integer, allocatable :: sa(:), sb(:), ss(:)
        call mlxf_enter('mlx_segmented_mm')
        sa = a%shape()
        sb = b%shape()
        ss = segments%shape()
        if( size(sa) /= 2 .or. size(sb) /= 2 ) call mlxf_fail('mlx_segmented_mm', 'two matrices of rank 2 are needed')
        if( sa(2) /= sb(1) ) call mlxf_fail('mlx_segmented_mm', 'the inner extents of a and b differ')
        if( size(ss) < 1 ) call mlxf_fail('mlx_segmented_mm', 'segments needs a first dimension of extent 2')
        if( ss(1) /= 2 ) call mlxf_fail('mlx_segmented_mm', 'segments needs a first dimension of extent 2')
        call mlxf_zero_based(bounds, segments, 'mlx_segmented_mm', less=[1, 0])
        call mlxf_ternary_op(r, mlxc_segmented_mm, [b, a, bounds], 'mlx_segmented_mm')
    end function mlx_segmented_mm

    ! alpha*matmul(a, b) + beta*c in one node, c broadcast to the product; alpha and beta are 1 when absent. A
    ! rank-1 a is a row and a rank-1 b a column, as for Fortran's matmul
    function mlx_addmm( c, a, b, alpha, beta ) result(r)
        type(mlx_array), intent(in)           :: c, a, b
        real(real32),    optional, intent(in) :: alpha, beta
        type(mlx_array) :: r
        real(real32)    :: scale(2)
        call mlxf_enter('mlx_addmm')
        scale = 1
        if( present(alpha) ) scale(1) = alpha
        if( present(beta) ) scale(2) = beta
        call mlxf_addmm_op(r, mlxc_addmm, [c, b, a], scale, 'mlx_addmm')
    end function mlx_addmm

    ! the sums of products over dimension 1 of both arrays, without conjugation: r(i..., j...) is the sum over k of
    ! a(k, i...)*b(k, j...), a's remaining dimensions before b's; with a scalar, the product
    function mlx_inner( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_inner, b, a, 'mlx_inner')
    end function mlx_inner

    ! r(i, j) = a(i)*b(j) over the elements of a and of b in array element order: (size of a, size of b)
    function mlx_outer( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_outer, b, a, 'mlx_outer')
    end function mlx_outer

    ! the Kronecker product: every element of a times the whole of b, r((i-1)*p + k, (j-1)*q + l) = a(i, j)*b(k, l)
    ! for a (p, q) matrix b; each extent is the product of the two, a lower rank padded with trailing extents of 1
    function mlx_kron( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r
        call mlxf_binary(r, mlxc_kron, a, b, 'mlx_kron')
    end function mlx_kron

    ! the dot products of the vectors along dimension dim (1 when absent) of two arrays of one rank, the first
    ! conjugated as Fortran's dot_product does; the other dimensions broadcast
    function mlx_vecdot( a, b, dim ) result(r)
        type(mlx_array), intent(in)           :: a, b
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_vecdot')
        call mlxf_binary_axis_op(r, mlxc_vecdot, [a, b], -shared_dim(a, b, 'mlx_vecdot', dim), 'mlx_vecdot')
    end function mlx_vecdot

    ! the cross products of the vectors of 3 (or 2, the third component zero) elements along dimension dim (1 when
    ! absent); the other dimensions broadcast
    function mlx_cross( a, b, dim ) result(r)
        type(mlx_array), intent(in)           :: a, b
        integer,         optional, intent(in) :: dim
        type(mlx_array) :: r
        call mlxf_enter('mlx_cross')
        call mlxf_binary_axis_op(r, mlxc_linalg_cross, [a, b], -shared_dim(a, b, 'mlx_cross', dim), 'mlx_cross')
    end function mlx_cross

    ! a dimension both arrays have (1 when absent). MLX takes it negated: its axis -d is Fortran dimension d of an
    ! array of any rank
    integer function shared_dim( a, b, proc, dim )
        type(mlx_array),  intent(in)           :: a, b
        character(len=*), intent(in)           :: proc
        integer,          optional, intent(in) :: dim
        integer :: nd
        shared_dim = 1
        if( present(dim) ) shared_dim = dim
        nd = min(a%ndim(), b%ndim())
        if( shared_dim < 1 .or. shared_dim > nd ) call mlxf_fail(proc, 'dimension outside array rank')
    end function shared_dim

    ! the contraction of the last n dimensions of a with the first n of b, in order (n = 2 when absent; 1 is matmul
    ! for matrices, 0 the outer product): the remaining dimensions of a, then those of b
    function tensordot_count( a, b, n ) result(r)
        type(mlx_array), intent(in)           :: a, b
        integer,         optional, intent(in) :: n
        type(mlx_array) :: r
        integer         :: paired
        call mlxf_enter('mlx_tensordot')
        paired = 2
        if( present(n) ) paired = n
        call mlxf_binary_axis_op(r, mlxc_tensordot_axis, [b, a], paired, 'mlx_tensordot')
    end function tensordot_count

    ! the contraction of dimension dims_a(i) of a with dimension dims_b(i) of b for every i: the remaining dimensions
    ! of a, then those of b, each in its order
    function tensordot_dims( a, b, dims_a, dims_b ) result(r)
        type(mlx_array), intent(in) :: a, b
        integer,         intent(in) :: dims_a(:), dims_b(:)
        type(mlx_array)      :: r
        integer, allocatable :: axes(:,:)
        call mlxf_enter('mlx_tensordot')
        if( size(dims_a) /= size(dims_b) ) call mlxf_fail('mlx_tensordot', 'as many dimensions of a as of b are needed')
        allocate(axes(size(dims_a), 2))
        axes(:, 1) = mlxf_axes_of(b, dims_b, 'mlx_tensordot')
        axes(:, 2) = mlxf_axes_of(a, dims_a, 'mlx_tensordot')
        call mlxf_tensordot_op(r, mlxc_tensordot, [b, a], axes, 'mlx_tensordot')
    end function tensordot_dims

    ! Einstein summation: in subscripts each operand has one letter per dimension, in Fortran's order, a repeated
    ! letter is summed over and '...' stands for the dimensions not named (they broadcast, aligned from the first).
    ! After '->' come the letters of the result; without it, the letters that occur once, capitals first and each
    ! case in alphabetical order, then the ellipsis
    function mlx_einsum( subscripts, operands ) result(r)
        character(len=*), intent(in) :: subscripts
        type(mlx_array),  intent(in) :: operands(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_einsum')
        call mlxf_einsum_op(r, mlxc_einsum, operands, row_major_subscripts(subscripts), 'mlx_einsum')
    end function mlx_einsum

    ! Fortran's subscripts as MLX takes them: the labels of every operand and of the result reversed, an ellipsis
    ! kept whole, and the result always explicit (MLX's own default would be read in reverse alphabetical order)
    function row_major_subscripts( subscripts ) result(text)
        character(len=*), intent(in) :: subscripts
        character(len=:), allocatable :: text, s, inputs, out
        integer                       :: arrow, i, first, code
        s = ''
        do i = 1, len(subscripts)
            if( subscripts(i:i) /= ' ' ) s = s//subscripts(i:i)
        end do
        arrow = index(s, '->')
        if( arrow > 0 )then
            inputs = s(:arrow-1)
            out = s(arrow+2:)
        else
            inputs = s
            out = ''
            do code = iachar('A'), iachar('z')
                if( count_of(inputs, achar(code)) == 1 .and. is_letter(achar(code)) ) out = out//achar(code)
            end do
            if( index(inputs, '...') > 0 ) out = out//'...'
        endif
        text = ''
        first = 1
        do i = 1, len(inputs)+1
            if( i <= len(inputs) )then
                if( inputs(i:i) /= ',' ) cycle
            endif
            text = text//reversed_labels(inputs(first:i-1))//','
            first = i+1
        end do
        text = text(:len(text)-1)//'->'//reversed_labels(out)
    end function row_major_subscripts

    ! how many times a letter occurs in the subscripts
    pure integer function count_of( text, letter )
        character(len=*), intent(in) :: text
        character(len=1), intent(in) :: letter
        integer :: i
        count_of = 0
        do i = 1, len(text)
            if( text(i:i) == letter ) count_of = count_of+1
        end do
    end function count_of

    pure logical function is_letter( c )
        character(len=1), intent(in) :: c
        is_letter = (c >= 'A' .and. c <= 'Z') .or. (c >= 'a' .and. c <= 'z')
    end function is_letter

    ! the labels of one operand from the last to the first, '...' being one label
    pure function reversed_labels( term ) result(text)
        character(len=*), intent(in) :: term
        character(len=len(term)) :: text
        integer                  :: k, n
        text = ''
        n = 0
        k = len(term)
        do while( k >= 1 )
            if( k >= 3 )then
                if( term(k-2:k) == '...' )then
                    text(n+1:n+3) = '...'
                    n = n+3
                    k = k-3
                    cycle
                endif
            endif
            text(n+1:n+1) = term(k:k)
            n = n+1
            k = k-1
        end do
    end function reversed_labels

    ! the Walsh-Hadamard transform along dimension 1, whose extent n is a power of two, times scale (1/sqrt(n) when
    ! absent, which makes the transform its own inverse)
    function mlx_hadamard_transform( a, scale ) result(r)
        type(mlx_array), intent(in)           :: a
        real(real32),    optional, intent(in) :: scale
        type(mlx_array) :: r
        call mlxf_optional_float_op(r, mlxc_hadamard_transform, a, 'mlx_hadamard_transform', option=scale)
    end function mlx_hadamard_transform

    ! r = f(a(1), a(2)) with the matrices of each operand chosen by the 0-based index arrays a(3) and a(4), an
    ! empty one being none, for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! const mlx_array lhs_indices, const mlx_array rhs_indices, bool sorted_indices, const mlx_stream s)
    subroutine mlxf_gather_mm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_gather_mm_op)    :: f
        type(mlx_array),  intent(in)    :: a(4)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(4)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: i
        call mlxf_require_device(proc)
        do i = 1, 4
            if( i <= 2 .or. .not. mlxf_is_empty(a(i)) ) h(i) = mlxf_handle(a(i), proc)
        end do
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), h(3), h(4), logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_gather_mm_op

    ! r = f(a(1), a(2)) with blocks of option rows and columns masked: a(3) masks the result, a(4) and a(5) the
    ! operands, an empty one being none, for every int f(mlx_array* res, const mlx_array a, const mlx_array b,
    ! int block_size, const mlx_array mask_out, const mlx_array mask_lhs, const mlx_array mask_rhs, const mlx_stream s)
    subroutine mlxf_masked_mm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_masked_mm_op)    :: f
        type(mlx_array),  intent(in)    :: a(5)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(5)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: i
        call mlxf_require_device(proc)
        do i = 1, 5
            if( i <= 2 .or. .not. mlxf_is_empty(a(i)) ) h(i) = mlxf_handle(a(i), proc)
        end do
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), int(option, c_int), h(3), h(4), h(5), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_masked_mm_op

    ! r = f(a(1), a(2), option) for a function of mlxc_take_op's signature whose integer goes to MLX as given: an axis
    ! already translated (a negative one counts from the last, so that it serves operands of different ranks) or a count
    subroutine mlxf_binary_axis_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_take_op)         :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), int(option, c_int), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_binary_axis_op

    ! r = f(a, option), an absent option being MLX's default, for every int f(mlx_array* res, const mlx_array a,
    ! mlx_optional_float scale, const mlx_stream s)
    subroutine mlxf_optional_float_op( r, f, a, proc, option )
        type(mlx_array),  intent(inout)        :: r
        procedure(mlxc_optional_float_op)      :: f
        type(mlx_array),  intent(in)           :: a
        character(len=*), intent(in)           :: proc
        real(real32),     optional, intent(in) :: option
        type(mlxc_array)          :: ha
        type(mlxc_optional_float) :: scale
        type(mlxc_array)          :: res
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        scale%value = 0
        scale%has_value = present(option)
        if( present(option) ) scale%value = real(option, c_float_kind)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, scale, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_optional_float_op

    ! r = option(1)*(a(2) times a(3)) + option(2)*a(1), a matrix product in MLX's view, for every int f(mlx_array* res,
    ! const mlx_array c, const mlx_array a, const mlx_array b, float alpha, float beta, const mlx_stream s)
    subroutine mlxf_addmm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_addmm_op)        :: f
        type(mlx_array),  intent(in)    :: a(3)
        real(real32),     intent(in)    :: option(2)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(3)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        integer           :: i
        call mlxf_require_device(proc)
        do i = 1, 3
            h(i) = mlxf_handle(a(i), proc)
        end do
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), h(3), real(option(1), c_float_kind), real(option(2), c_float_kind), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_addmm_op

    ! r = f(option, a), the subscripts already in MLX's axis order, for every int f(mlx_array* res,
    ! const char* subscripts, const mlx_vector_array operands, const mlx_stream s)
    subroutine mlxf_einsum_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_einsum_op)       :: f
        type(mlx_array),  intent(in)    :: a(:)
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_vector_array) :: v
        type(mlxc_array)        :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        call mlxf_require_device(proc)
        if( size(a) == 0 ) call mlxf_fail(proc, 'empty list')
        v = mlxf_vector_of(a, proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, trim(option)//c_null_char, v, s)
        call mlxf_check(mlxc_vector_array_free(v), proc)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_einsum_op

    ! r = f(a(1), a(2)) contracting the axes option(:, 1) of a(1) with the axes option(:, 2) of a(2), as MLX takes them,
    ! for every int f(mlx_array* res, const mlx_array a, const mlx_array b, const int* axes_a, size_t axes_a_num,
    ! const int* axes_b, size_t axes_b_num, const mlx_stream s)
    subroutine mlxf_tensordot_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_tensordot_op)    :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option(:,:)
        character(len=*), intent(in)    :: proc
        type(mlxc_array)            :: h(2)
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:,:)
        integer(c_size_t)           :: n
        call mlxf_require_device(proc)
        if( size(option, 2) /= 2 ) call mlxf_fail(proc, 'two lists of axes are needed')
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        axes = int(option, c_int)
        n = int(size(axes, 1), c_size_t)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, h(1), h(2), axes(:, 1), n, axes(:, 2), n, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_tensordot_op

end module mlxf_linalg
