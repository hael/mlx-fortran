!@descr: matrices in the Fortran view: factorisations, inverses, determinants, eigenvalues, solvers and norms
! A Fortran matrix is dimensions 1 and 2 of an array, further dimensions a batch, and MLX sees its transpose.
! Where the result for the transpose is the transpose of the result (inverses, determinants, singular values, a
! Cholesky factor with its triangle exchanged) the graph gains nothing; elsewhere the operand, the results or
! both are transposed, which is a view and never a copy. MLX computes every factorisation on the CPU, so these
! run on the CPU's default stream whatever the default device. The norms run on the default device, except those
! of the singular values.
module mlxf_linalg_matrix
use, intrinsic :: iso_c_binding, only: c_double, c_bool, c_int, c_null_char, c_size_t
use mlxf_c_array,      only: mlxc_array_free, mlxc_array_new
use mlxf_c_linalg,     only: mlxc_linalg_cholesky, mlxc_linalg_cholesky_inv, mlxc_linalg_det, mlxc_linalg_eig, &
                             mlxc_linalg_eigh, mlxc_linalg_eigvals, mlxc_linalg_eigvalsh, mlxc_linalg_inv, &
                             mlxc_linalg_lu, mlxc_linalg_lu_factor, mlxc_linalg_norm, mlxc_linalg_norm_l2, &
                             mlxc_linalg_norm_matrix, mlxc_linalg_pinv, mlxc_linalg_qr, mlxc_linalg_slogdet, &
                             mlxc_linalg_solve, mlxc_linalg_solve_triangular, mlxc_linalg_svd, mlxc_linalg_tri_inv
use mlxf_c_ops,        only: mlxc_conjugate, mlxc_flatten, mlxc_reshape, mlxc_swapaxes
use mlxf_c_signatures, only: mlxc_binary_op, mlxc_compare_op, mlxc_flag_op, mlxc_norm_op, mlxc_norm_text_op, &
                             mlxc_pair_op, mlxc_pair_text_op, mlxc_unary_op, mlxc_unary_text_op, mlxc_unstack_op, &
                             mlxc_vector_flag_op
use mlxf_c_stream,     only: mlxc_stream_free
use mlxf_c_types,      only: mlxc_array, mlxc_stream, mlxc_vector_array
use mlxf_c_vector,     only: mlxc_vector_array_free, mlxc_vector_array_new
use mlxf_defs,         only: MLX_DTYPES, mlxf_reduce_spec, mlxf_norm_spec
use mlxf_array,        only: mlx_array, mlxf_handle, mlxf_vector_import, mlxf_adopt
use mlxf_device,       only: mlxf_enter, mlxf_default_stream, mlxf_require_device
use mlxf_error,        only: mlxf_fail, mlxf_check
use mlxf_calls,        only: mlxf_axes_of, mlxf_cpu_stream, mlxf_int2_op, mlxf_one_based, mlxf_reduce_dims_op, &
                             mlxf_unary, mlxf_vector_op
implicit none
public :: mlx_inv, mlx_pinv, mlx_tri_inv, mlx_det, mlx_slogdet, mlx_cholesky, mlx_cholesky_inv, mlx_qr, mlx_lu
public :: mlx_lu_factor, mlx_svd, mlx_eigh, mlx_eigvalsh, mlx_eig, mlx_eigvals, mlx_solve, mlx_solve_triangular
public :: mlx_norm, mlx_norm_matrix, norm2
private
interface mlx_svd
    module procedure svd_factors, svd_values
end interface mlx_svd

interface mlx_norm
    module procedure norm_dim, norm_dims
end interface mlx_norm

interface norm2
    module procedure norm2_dim, norm2_dims
end interface norm2

contains

    ! the inverse of every square matrix of a
    function mlx_inv( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_cpu_unary(r, mlxc_linalg_inv, a, 'mlx_inv')
    end function mlx_inv

    ! the Moore-Penrose pseudo-inverse of every (m, n) matrix of a: (n, m), from the singular values above a cut
    function mlx_pinv( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_cpu_unary(r, mlxc_linalg_pinv, a, 'mlx_pinv')
    end function mlx_pinv

    ! the inverse of every triangular matrix of a: lower triangular unless upper, the other triangle not read
    function mlx_tri_inv( a, upper ) result(r)
        type(mlx_array), intent(in)           :: a
        logical,         optional, intent(in) :: upper
        type(mlx_array) :: r
        call mlxf_enter('mlx_tri_inv')
        call mlxf_cpu_flag_op(r, mlxc_linalg_tri_inv, a, .not. chosen(upper), 'mlx_tri_inv')
    end function mlx_tri_inv

    ! the determinant of every square matrix of a: the batch dimensions remain
    function mlx_det( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r
        call mlxf_cpu_unary(r, mlxc_linalg_det, a, 'mlx_det')
    end function mlx_det

    ! the determinant of every square matrix of a as its sign (-1, 0 or 1) and the logarithm of its magnitude
    subroutine mlx_slogdet( a, sign, logabsdet )
        type(mlx_array), intent(in)  :: a
        type(mlx_array), intent(out) :: sign, logabsdet
        type(mlx_array) :: res(2)
        call mlxf_cpu_pair_op(res, mlxc_linalg_slogdet, a, 'mlx_slogdet')
        sign = res(1)
        logabsdet = res(2)
    end subroutine mlx_slogdet

    ! the Cholesky factor of every symmetric positive definite matrix of a: the lower triangular l with
    ! a = matmul(l, transpose(l)), or with upper the upper triangular u with a = matmul(transpose(u), u)
    function mlx_cholesky( a, upper ) result(r)
        type(mlx_array), intent(in)           :: a
        logical,         optional, intent(in) :: upper
        type(mlx_array) :: r
        call mlxf_enter('mlx_cholesky')
        call mlxf_cpu_flag_op(r, mlxc_linalg_cholesky, a, .not. chosen(upper), 'mlx_cholesky')
    end function mlx_cholesky

    ! the inverse of a symmetric positive definite matrix from its Cholesky factor, as mlx_cholesky returns it
    ! (lower triangular unless upper)
    function mlx_cholesky_inv( factor, upper ) result(r)
        type(mlx_array), intent(in)           :: factor
        logical,         optional, intent(in) :: upper
        type(mlx_array) :: r
        call mlxf_enter('mlx_cholesky_inv')
        call mlxf_cpu_flag_op(r, mlxc_linalg_cholesky_inv, factor, .not. chosen(upper), 'mlx_cholesky_inv')
    end function mlx_cholesky_inv

    ! a = matmul(q, r) for every (m, n) matrix of a: q (m, k) with orthonormal columns and r (k, n) upper
    ! triangular, k the smaller of m and n
    subroutine mlx_qr( a, q, r )
        type(mlx_array), intent(in)  :: a
        type(mlx_array), intent(out) :: q, r
        type(mlx_array) :: t, res(2)
        call mlxf_enter('mlx_qr')
        call transposed(t, a, 'mlx_qr')
        call mlxf_cpu_pair_op(res, mlxc_linalg_qr, t, 'mlx_qr')
        call transposed(q, res(1), 'mlx_qr')
        call transposed(r, res(2), 'mlx_qr')
    end subroutine mlx_qr

    ! the LU factorisation with row pivoting of every (m, n) matrix of a: row i of a is row p(i) of matmul(l, u),
    ! with p a permutation of 1 to m (int32), l (m, k) unit lower triangular and u (k, n) upper triangular
    subroutine mlx_lu( a, p, l, u )
        type(mlx_array), intent(in)  :: a
        type(mlx_array), intent(out) :: p, l, u
        type(mlx_array), allocatable :: res(:)
        type(mlx_array)              :: t
        call mlxf_enter('mlx_lu')
        call transposed(t, a, 'mlx_lu')
        call mlxf_cpu_unstack_op(res, mlxc_linalg_lu, t, 'mlx_lu')
        if( size(res) /= 3 ) call mlxf_fail('mlx_lu', 'three results expected')
        call mlxf_one_based(p, res(1), 'mlx_lu')
        call transposed(l, res(2), 'mlx_lu')
        call transposed(u, res(3), 'mlx_lu')
    end subroutine mlx_lu

    ! the LU factorisation as LAPACK packs it: lu holds u in its upper triangle and l below its diagonal (the unit
    ! diagonal left out), and row i was exchanged with row pivots(i), 1-based int32, for i = 1, 2, ... in turn
    subroutine mlx_lu_factor( a, lu, pivots )
        type(mlx_array), intent(in)  :: a
        type(mlx_array), intent(out) :: lu, pivots
        type(mlx_array) :: t, res(2)
        call mlxf_enter('mlx_lu_factor')
        call transposed(t, a, 'mlx_lu_factor')
        call mlxf_cpu_pair_op(res, mlxc_linalg_lu_factor, t, 'mlx_lu_factor')
        call transposed(lu, res(1), 'mlx_lu_factor')
        call mlxf_one_based(pivots, res(2), 'mlx_lu_factor')
    end subroutine mlx_lu_factor

    ! a = matmul(u, matmul(diag(s), vt)) for every (m, n) matrix of a: u (m, m) and vt (n, n) orthogonal (unitary),
    ! s the singular values in descending order. MLX's factors of the transposed matrix are these, exchanged
    subroutine svd_factors( a, u, s, vt )
        type(mlx_array), intent(in)  :: a
        type(mlx_array), intent(out) :: u, s, vt
        type(mlx_array), allocatable :: res(:)
        call mlxf_cpu_svd_op(res, mlxc_linalg_svd, a, .true., 'mlx_svd')
        if( size(res) /= 3 ) call mlxf_fail('mlx_svd', 'three results expected')
        u = res(3)
        s = res(2)
        vt = res(1)
    end subroutine svd_factors

    ! the singular values alone, in descending order
    subroutine svd_values( a, s )
        type(mlx_array), intent(in)  :: a
        type(mlx_array), intent(out) :: s
        type(mlx_array), allocatable :: res(:)
        call mlxf_cpu_svd_op(res, mlxc_linalg_svd, a, .false., 'mlx_svd')
        if( size(res) /= 1 ) call mlxf_fail('mlx_svd', 'one result expected')
        s = res(1)
    end subroutine svd_values

    ! the eigenvalues w, ascending, and the orthonormal eigenvectors (the columns of v) of every symmetric or
    ! Hermitian matrix of a: matmul(a, v(:, j)) = w(j)*v(:, j). Only the triangle uplo names is read ('L', the
    ! default, or 'U')
    subroutine mlx_eigh( a, w, v, uplo )
        type(mlx_array),  intent(in)           :: a
        type(mlx_array),  intent(out)          :: w, v
        character(len=*), optional, intent(in) :: uplo
        type(mlx_array) :: res(2), conjugate
        call mlxf_enter('mlx_eigh')
        call mlxf_cpu_pair_text_op(res, mlxc_linalg_eigh, a, other_triangle('mlx_eigh', uplo), 'mlx_eigh')
        w = res(1)
        if( a%kind() == MLX_DTYPES%complex64 )then
            call mlxf_unary(conjugate, mlxc_conjugate, res(2), 'mlx_eigh')
            call transposed(v, conjugate, 'mlx_eigh')
        else
            call transposed(v, res(2), 'mlx_eigh')
        endif
    end subroutine mlx_eigh

    ! the eigenvalues, ascending, of every symmetric or Hermitian matrix of a, from the triangle uplo names
    function mlx_eigvalsh( a, uplo ) result(r)
        type(mlx_array),  intent(in)           :: a
        character(len=*), optional, intent(in) :: uplo
        type(mlx_array) :: r
        call mlxf_enter('mlx_eigvalsh')
        call mlxf_cpu_text_op(r, mlxc_linalg_eigvalsh, a, other_triangle('mlx_eigvalsh', uplo), 'mlx_eigvalsh')
    end function mlx_eigvalsh

    ! the eigenvalues w and the right eigenvectors (the columns of v) of every square matrix of a, both complex:
    ! matmul(a, v(:, j)) = w(j)*v(:, j)
    subroutine mlx_eig( a, w, v )
        type(mlx_array), intent(in)  :: a
        type(mlx_array), intent(out) :: w, v
        type(mlx_array) :: t, res(2)
        call mlxf_enter('mlx_eig')
        call transposed(t, a, 'mlx_eig')
        call mlxf_cpu_pair_op(res, mlxc_linalg_eig, t, 'mlx_eig')
        w = res(1)
        call transposed(v, res(2), 'mlx_eig')
    end subroutine mlx_eig

    ! the eigenvalues of every square matrix of a, complex, in the order mlx_eig returns them
    function mlx_eigvals( a ) result(r)
        type(mlx_array), intent(in) :: a
        type(mlx_array) :: r, t
        call mlxf_enter('mlx_eigvals')
        call transposed(t, a, 'mlx_eigvals')
        call mlxf_cpu_unary(r, mlxc_linalg_eigvals, t, 'mlx_eigvals')
    end function mlx_eigvals

    ! x with matmul(a, x) = b for every square matrix of a: b is a vector (rank 1) or holds the right-hand sides as
    ! the columns of matrices (dimensions 1 and 2) with a's batch dimensions after them, and x has b's shape. MLX
    ! takes no batch of a against a single b, nor the reverse
    function mlx_solve( a, b ) result(r)
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: r, ta, tb, x
        call mlxf_enter('mlx_solve')
        call transposed(ta, a, 'mlx_solve')
        if( b%ndim() >= 2 )then
            call transposed(tb, b, 'mlx_solve')
            call mlxf_cpu_binary(x, mlxc_linalg_solve, ta, tb, 'mlx_solve')
            call transposed(r, x, 'mlx_solve')
        else
            call mlxf_cpu_binary(r, mlxc_linalg_solve, ta, b, 'mlx_solve')
        endif
    end function mlx_solve

    ! x with matmul(a, x) = b for every triangular matrix of a (lower triangular unless upper, the other triangle
    ! not read), b and x as for mlx_solve; here the batch dimensions of a and b broadcast
    function mlx_solve_triangular( a, b, upper ) result(r)
        type(mlx_array), intent(in)           :: a, b
        logical,         optional, intent(in) :: upper
        type(mlx_array) :: r, ta, tb, x
        call mlxf_enter('mlx_solve_triangular')
        call transposed(ta, a, 'mlx_solve_triangular')
        if( b%ndim() >= 2 )then
            call transposed(tb, b, 'mlx_solve_triangular')
            call mlxf_cpu_compare_op(x, mlxc_linalg_solve_triangular, [ta, tb], chosen(upper), 'mlx_solve_triangular')
            call transposed(r, x, 'mlx_solve_triangular')
        else
            call mlxf_cpu_compare_op(r, mlxc_linalg_solve_triangular, [ta, b], chosen(upper), 'mlx_solve_triangular')
        endif
    end function mlx_solve_triangular

    ! the norm of order ord along dimension dim: the sum of |a|**ord to the power 1/ord, the largest (smallest)
    ! magnitude for an infinite (minus infinite) ord, the count of nonzeros for 0. Without dim, of a vector, or the
    ! matrix norm of a rank-2 array as the form with dims computes it
    function norm_dim( a, ord, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        real(c_double),  intent(in)           :: ord
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        integer         :: nd
        call mlxf_enter('mlx_norm')
        if( present(dim) )then
            call mlxf_norm_op(r, mlxc_linalg_norm, a, norm_spec(ord, [dim], keepdims), 'mlx_norm')
            return
        endif
        nd = a%ndim()
        if( nd == 1 )then
            call mlxf_norm_op(r, mlxc_linalg_norm, a, norm_spec(ord, [1], keepdims), 'mlx_norm')
        else if( nd == 2 )then
            call mlxf_norm_op(r, mlxc_linalg_norm, a, norm_spec(ord, [1, 2], keepdims), 'mlx_norm')
        else
            call mlxf_fail('mlx_norm', 'without dimensions, a vector or a matrix is needed')
        endif
    end function norm_dim

    ! over one dimension, the vector norm; over two, the matrix norm of the matrices whose rows run along dims(1)
    ! and columns along dims(2): the largest column sum of magnitudes for ord 1 (the smallest for -1), the largest
    ! row sum for an infinite ord, the largest (smallest) singular value for 2 (-2)
    function norm_dims( a, ord, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        real(c_double),  intent(in)           :: ord
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array) :: r
        call mlxf_enter('mlx_norm')
        if( size(dims) < 1 ) call mlxf_fail('mlx_norm', 'one or two dimensions are needed')
        call mlxf_norm_op(r, mlxc_linalg_norm, a, norm_spec(ord, dims, keepdims), 'mlx_norm')
    end function norm_dims

    ! the options of a norm of order ord; the orders 2 and -2 of a matrix are singular values, which MLX computes
    ! on the CPU only
    function norm_spec( ord, dims, keepdims ) result(spec)
        real(c_double), intent(in)           :: ord
        integer,        intent(in)           :: dims(:)
        logical,        optional, intent(in) :: keepdims
        type(mlxf_norm_spec) :: spec
        spec%ord = ord
        spec%dims = dims
        spec%keepdims = chosen(keepdims)
        spec%on_cpu = size(dims) == 2 .and. abs(abs(ord)-2._c_double) < tiny(1._c_double)
    end function norm_spec

    ! the matrix norm named ord of the matrices whose rows run along dims(1) and columns along dims(2), dimensions 1
    ! and 2 when absent: 'fro', the root of the sum of squared magnitudes, or 'nuc', the sum of the singular values
    function mlx_norm_matrix( a, ord, dims, keepdims ) result(r)
        type(mlx_array),  intent(in)           :: a
        character(len=*), intent(in)           :: ord
        integer,          optional, intent(in) :: dims(2)
        logical,          optional, intent(in) :: keepdims
        type(mlx_array)      :: r
        type(mlxf_norm_spec) :: spec
        call mlxf_enter('mlx_norm_matrix')
        if( len_trim(ord) > len(spec%name) ) call mlxf_fail('mlx_norm_matrix', 'the norm is ''fro'' or ''nuc''')
        spec%name = ord
        spec%dims = [1, 2]
        if( present(dims) ) spec%dims = dims
        spec%keepdims = chosen(keepdims)
        spec%on_cpu = trim(ord) == 'nuc'
        call mlxf_norm_text_op(r, mlxc_linalg_norm_matrix, a, spec, 'mlx_norm_matrix')
    end function mlx_norm_matrix

    ! the Euclidean norm along dimension dim, as Fortran's norm2 (of magnitudes for a complex array); without dim,
    ! of every element
    function norm2_dim( a, dim, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dim
        logical,         optional, intent(in) :: keepdims
        type(mlx_array)        :: r, flat, whole
        type(mlxf_reduce_spec) :: spec
        integer                :: i
        call mlxf_enter('norm2')
        if( present(dim) )then
            spec%dims = [dim]
            spec%keepdims = chosen(keepdims)
            call mlxf_reduce_dims_op(r, mlxc_linalg_norm_l2, a, spec, 'norm2')
            return
        endif
        spec%dims = [1]
        call mlxf_int2_op(flat, mlxc_flatten, a, [0, -1], 'norm2')
        if( chosen(keepdims) )then
            call mlxf_reduce_dims_op(whole, mlxc_linalg_norm_l2, flat, spec, 'norm2')
            call mlxf_vector_op(r, mlxc_reshape, whole, [(1, i=1, a%ndim())], 'norm2')
        else
            call mlxf_reduce_dims_op(r, mlxc_linalg_norm_l2, flat, spec, 'norm2')
        endif
    end function norm2_dim

    ! the Euclidean norm over one or two dimensions (the Frobenius norm of the matrices they span)
    function norm2_dims( a, dims, keepdims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(:)
        logical,         optional, intent(in) :: keepdims
        type(mlx_array)        :: r
        type(mlxf_reduce_spec) :: spec
        call mlxf_enter('norm2')
        if( size(dims) < 1 ) call mlxf_fail('norm2', 'one or two dimensions are needed')
        spec%dims = dims
        spec%keepdims = chosen(keepdims)
        call mlxf_reduce_dims_op(r, mlxc_linalg_norm_l2, a, spec, 'norm2')
    end function norm2_dims

    ! the transpose of every matrix of a, dimensions 1 and 2 exchanged: a view
    subroutine transposed( r, a, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        if( a%ndim() < 2 ) call mlxf_fail(proc, 'a matrix needs two dimensions')
        call mlxf_int2_op(r, mlxc_swapaxes, a, [-1, -2], proc)
    end subroutine transposed

    ! an optional flag, false when absent
    pure logical function chosen( flag )
        logical, optional, intent(in) :: flag
        chosen = .false.
        if( present(flag) ) chosen = flag
    end function chosen

    ! the triangle MLX reads for the triangle uplo of the Fortran matrix ('L' when absent): the other one, since
    ! MLX sees the transpose
    function other_triangle( proc, uplo ) result(text)
        character(len=*), intent(in)           :: proc
        character(len=*), optional, intent(in) :: uplo
        character(len=1) :: text
        text = 'U'
        if( .not. present(uplo) ) return
        select case( trim(uplo) )
            case('L', 'l')
                text = 'U'
            case('U', 'u')
                text = 'L'
            case default
                call mlxf_fail(proc, 'uplo is ''L'' or ''U''')
        end select
    end function other_triangle

    ! r = f(a) on the CPU's default stream whatever the default device, for a function of mlxc_unary_op's signature
    ! that MLX implements on the CPU only
    subroutine mlxf_cpu_unary( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_op)        :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res, ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_cpu_unary

    ! r = f(a, b) on the CPU's default stream, for a function of mlxc_binary_op's signature that MLX implements on
    ! the CPU only
    subroutine mlxf_cpu_binary( r, f, a, b, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_binary_op)       :: f
        type(mlx_array),  intent(in)    :: a, b
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha, hb
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        hb = mlxf_handle(b, proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res, ha, hb, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_cpu_binary

    ! r = f(a, option) on the CPU's default stream, for every int f(mlx_array* res, const mlx_array a, bool flag,
    ! const mlx_stream s) that MLX implements on the CPU only; the flag goes to MLX as given
    subroutine mlxf_cpu_flag_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_flag_op)         :: f
        type(mlx_array),  intent(in)    :: a
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res, ha, logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_cpu_flag_op

    ! r = f(a(1), a(2), option) on the CPU's default stream, for every int f(mlx_array* res, const mlx_array a,
    ! const mlx_array b, bool flag, const mlx_stream s) that MLX implements on the CPU only
    subroutine mlxf_cpu_compare_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_compare_op)      :: f
        type(mlx_array),  intent(in)    :: a(2)
        logical,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: h(2)
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        h(1) = mlxf_handle(a(1), proc)
        h(2) = mlxf_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res, h(1), h(2), logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_cpu_compare_op

    ! the two results of f(a), in MLX's order, on the CPU's default stream, for every int f(mlx_array* res_0,
    ! mlx_array* res_1, const mlx_array a, const mlx_stream s)
    subroutine mlxf_cpu_pair_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_op)         :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res(2)
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res(1) = mlxc_array_new()
        res(2) = mlxc_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res(1), res(2), ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 )then
            call mlxf_check(mlxc_array_free(res(1)), proc)
            call mlxf_check(mlxc_array_free(res(2)), proc)
        endif
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r(1), res(1), proc)
        call mlxf_adopt(r(2), res(2), proc)
    end subroutine mlxf_cpu_pair_op

    ! the two results of f(a, option), in MLX's order, on the CPU's default stream, for every int f(mlx_array* res_0,
    ! mlx_array* res_1, const mlx_array a, const char* text, const mlx_stream s)
    subroutine mlxf_cpu_pair_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_text_op)    :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res(2)
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res(1) = mlxc_array_new()
        res(2) = mlxc_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res(1), res(2), ha, trim(option)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 )then
            call mlxf_check(mlxc_array_free(res(1)), proc)
            call mlxf_check(mlxc_array_free(res(2)), proc)
        endif
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r(1), res(1), proc)
        call mlxf_adopt(r(2), res(2), proc)
    end subroutine mlxf_cpu_pair_text_op

    ! r = f(a, option) on the CPU's default stream, for every int f(mlx_array* res, const mlx_array a,
    ! const char* text, const mlx_stream s)
    subroutine mlxf_cpu_text_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_unary_text_op)   :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res, ha, trim(option)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_cpu_text_op

    ! the arrays of f(a), in MLX's order, on the CPU's default stream, for a function of mlxc_unstack_op's signature
    ! that MLX implements on the CPU only
    subroutine mlxf_cpu_unstack_op( r, f, a, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_unstack_op)                 :: f
        type(mlx_array),  intent(in)               :: a
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_vector_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res, ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_cpu_unstack_op

    ! the arrays of f(a, option), in MLX's order, on the CPU's default stream, for every int f(mlx_vector_array* res,
    ! const mlx_array a, bool flag, const mlx_stream s)
    subroutine mlxf_cpu_svd_op( r, f, a, option, proc )
        type(mlx_array),  allocatable, intent(out) :: r(:)
        procedure(mlxc_vector_flag_op)             :: f
        type(mlx_array),  intent(in)               :: a
        logical,          intent(in)               :: option
        character(len=*), intent(in)               :: proc
        type(mlxc_array)        :: ha
        type(mlxc_vector_array) :: res
        type(mlxc_stream)       :: s
        integer(c_int)          :: ierr
        integer                 :: status
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res = mlxc_vector_array_new()
        s = mlxf_cpu_stream(proc)
        ierr = f(res, ha, logical(option, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_vector_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_vector_import(r, res, status)
        call mlxf_check(mlxc_vector_array_free(res), proc)
        if( status /= 0 ) call mlxf_fail(proc, 'the results could not be adopted')
    end subroutine mlxf_cpu_svd_op

    ! the norm of order option%ord of a over the Fortran dimensions option%dims, each translated to its MLX axis in the
    ! order given (of two, the first is the rows'), on the CPU's default stream when option%on_cpu, for every
    ! int f(mlx_array* res, const mlx_array a, double ord, const int* axis, size_t axis_num, bool keepdims, const mlx_stream s)
    subroutine mlxf_norm_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_norm_op)             :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_norm_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)            :: ha
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:)
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        axes = mlxf_axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        if( option%on_cpu )then
            s = mlxf_cpu_stream(proc)
        else
            s = mlxf_default_stream(proc)
        endif
        ierr = f(res, ha, option%ord, axes, int(size(axes), c_size_t), logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_norm_op

    ! the matrix norm named option%name of a over the Fortran dimensions option%dims, as mlxf_norm_op takes them, for
    ! every int f(mlx_array* res, const mlx_array a, const char* ord, const int* axis, size_t axis_num, bool keepdims,
    ! const mlx_stream s)
    subroutine mlxf_norm_text_op( r, f, a, option, proc )
        type(mlx_array),      intent(inout) :: r
        procedure(mlxc_norm_text_op)        :: f
        type(mlx_array),      intent(in)    :: a
        type(mlxf_norm_spec), intent(in)    :: option
        character(len=*),     intent(in)    :: proc
        type(mlxc_array)            :: ha
        type(mlxc_array)            :: res
        type(mlxc_stream)           :: s
        integer(c_int)              :: ierr
        integer(c_int), allocatable :: axes(:)
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        axes = mlxf_axes_of(a, option%dims, proc)
        res = mlxc_array_new()
        if( option%on_cpu )then
            s = mlxf_cpu_stream(proc)
        else
            s = mlxf_default_stream(proc)
        endif
        ierr = f(res, ha, trim(option%name)//c_null_char, axes, int(size(axes), c_size_t), logical(option%keepdims, c_bool), s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call mlxf_adopt(r, res, proc)
    end subroutine mlxf_norm_text_op

end module mlxf_linalg_matrix
