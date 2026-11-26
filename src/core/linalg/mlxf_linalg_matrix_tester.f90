!@descr: the factorisations, inverses, determinants, eigenvalues, solvers and norms by residuals, orthogonality and constructed spectra
! Seeded matrices on every device, float32 and on the CPU float64 as well, built in real64 from seeded orthogonal
! factors and a chosen spectrum, so that singular values and eigenvalues are known and the condition number is 6.
! Nothing is compared with a factor: a factorisation is judged by its backward error and the orthogonality of
! its factors against 10 n epsilons of the result's kind, an inverse and a solution by their residuals, and the
! shape, the triangle and the order of what comes back exactly. Determinants and norms are values, judged against
! real64 references by frozen tolerances.
module mlxf_linalg_matrix_tester
use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_positive_inf, ieee_negative_inf
use, intrinsic :: iso_fortran_env, only: output_unit, int32, real32, real64
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                            MLX_DTYPES, mlx_inv, mlx_pinv, mlx_tri_inv, mlx_det, mlx_slogdet, mlx_cholesky, &
                            mlx_cholesky_inv, mlx_qr, mlx_lu, mlx_lu_factor, mlx_svd, mlx_eigh, mlx_eigvalsh, mlx_eig, &
                            mlx_eigvals, mlx_solve, mlx_solve_triangular, mlx_norm, mlx_norm_matrix, norm2
use mlxf_test_utils,  only: assert_true, test_devices, device_name, judge_error, find_tolerance, family_seeds, &
                            seeded_uniform, seeded_array, shaped_error
use mlxf_test_defs,   only: ELEM_CEILING, MATRIX_TOLERANCES, LINALG_RESIDUAL_FACTOR, elem_tolerance
use mlxf_test_reduce, only: nan_maxval, nan_max
implicit none
private
public :: run_all_linalg_matrix_tests

! the order of the square fixtures and the extents of the rectangular ones
integer, parameter :: N = 5, LONG = 6, SHORT = 4
! the ends of every constructed spectrum: a condition number of 6
real(real64), parameter :: SPECTRUM_LOW = 0.5_real64, SPECTRUM_HIGH = 3._real64

! the elements of a real result in real64, when it has the expected shape
interface fetch
    module procedure fetch1, fetch2, fetch3
end interface fetch

! the elements of a complex result, when it has the expected shape
interface fetch_complex
    module procedure fetch_complex1, fetch_complex2
end interface fetch_complex

! the Frobenius norm
interface fro
    module procedure fro_real, fro_complex
end interface fro

contains

    subroutine run_all_linalg_matrix_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all linalg_matrix tests ****'
        call assert_true(all(MATRIX_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a determinant or a norm is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_inv
            call test_tri_inv
            call test_pinv
            call test_det
            call test_cholesky
            call test_qr
            call test_lu
            call test_lu_factor
            call test_svd
            call test_svd_complex
            call test_eigh
            call test_eigh_complex
            call test_eig
            call test_solve
            call test_solve_triangular
            call test_norms
            call test_matrix_norms
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_linalg_matrix_tests

    ! float32 on every device, float64 as well on the CPU
    integer function passes()
        passes = 1
        if( mlx_default_device() == MLX_DEVICES%cpu ) passes = 2
    end function passes

    ! a residual against the bound of a backward-stable method, LINALG_RESIDUAL_FACTOR times the order times the
    ! epsilon of the result's kind; printed in units of order times epsilon for the record (seed 0: a fixed fixture)
    subroutine judge_residual( resid, order, wide, label, seed )
        real(real64),     intent(in) :: resid
        integer,          intent(in) :: order, seed
        logical,          intent(in) :: wide
        character(len=*), intent(in) :: label
        character(len=200) :: line
        real(real64)       :: unit
        unit = order*real(epsilon(1._real32), real64)
        if( wide ) unit = order*epsilon(1._real64)
        write(line,'(A,I0,A,ES16.9,A,F8.3,A)') '    residual '//label//' '//device_name(mlx_default_device())// &
            &' '//merge('float64', 'float32', wide)//' seed=', seed, ': ', resid, ' (', resid/unit, ' n eps)'
        write(output_unit,'(A)') trim(line)
        call assert_true(resid <= LINALG_RESIDUAL_FACTOR*unit, label//' within 10 n epsilons, '// &
            &merge('float64', 'float32', wide)//' on the '//device_name(mlx_default_device()))
    end subroutine judge_residual

    ! the operand's dtype, for a result that is complex64 whatever the operand
    function operand( wide ) result(text)
        logical, intent(in) :: wide
        character(len=:), allocatable :: text
        text = ', float32 operand'
        if( wide ) text = ', float64 operand'
    end function operand

    ! a value against the frozen tolerance of its dtype
    subroutine judge( err, tol, wide, seed )
        real(real64),         intent(in) :: err
        type(elem_tolerance), intent(in) :: tol
        logical,              intent(in) :: wide
        integer,              intent(in) :: seed
        if( wide )then
            call judge_error(err, tol%f64, trim(tol%name), 'float64', seed)
        else
            call judge_error(err, tol%f32, trim(tol%name), 'float32', seed)
        endif
    end subroutine judge

    ! what MLX receives of a real64 fixture: itself in float64, its rounding in float32
    elemental function given( x, wide ) result(y)
        real(real64), intent(in) :: x
        logical,      intent(in) :: wide
        real(real64) :: y
        y = x
        if( .not. wide ) y = real(real(x, real32), real64)
    end function given

    ! count values evenly spaced over the constructed spectrum, ascending
    function spectrum( count ) result(v)
        integer, intent(in) :: count
        real(real64) :: v(count)
        integer      :: i
        do i = 1, count
            v(i) = SPECTRUM_LOW+(SPECTRUM_HIGH-SPECTRUM_LOW)*real(i-1, real64)/real(count-1, real64)
        end do
    end function spectrum

    ! an orthogonal matrix from a fixed seed: seeded columns orthonormalised twice by modified Gram-Schmidt
    function orthogonal( order, seed ) result(q)
        integer, intent(in) :: order, seed
        real(real64) :: q(order, order)
        integer      :: j, k, pass
        q = reshape(seeded_uniform(order*order, seed), [order, order])
        do j = 1, order
            do pass = 1, 2
                do k = 1, j-1
                    q(:, j) = q(:, j)-dot_product(q(:, k), q(:, j))*q(:, k)
                end do
            end do
            q(:, j) = q(:, j)/norm2(q(:, j))
        end do
    end function orthogonal

    ! an (m, k) matrix with the singular values sig, from seeded orthogonal factors
    function with_singular_values( m, k, sig, seed ) result(a)
        integer,      intent(in) :: m, k, seed
        real(real64), intent(in) :: sig(:)
        real(real64) :: a(m, k), u(m, m), v(k, k)
        integer      :: i
        u = orthogonal(m, seed)
        v = orthogonal(k, seed+1)
        a = 0._real64
        do i = 1, size(sig)
            a = a+sig(i)*spread(u(:, i), 2, k)*spread(v(:, i), 1, m)
        end do
    end function with_singular_values

    ! a symmetric matrix with the eigenvalues lam, from a seeded orthogonal factor
    function with_eigenvalues( lam, seed ) result(a)
        real(real64), intent(in) :: lam(:)
        integer,      intent(in) :: seed
        real(real64) :: a(size(lam), size(lam)), q(size(lam), size(lam))
        integer      :: i
        q = orthogonal(size(lam), seed)
        a = 0._real64
        do i = 1, size(lam)
            a = a+lam(i)*spread(q(:, i), 2, size(lam))*spread(q(:, i), 1, size(lam))
        end do
    end function with_eigenvalues

    ! a lower triangular matrix with a diagonal in 1 to 2 and small elements below it
    function lower_triangular( order, seed ) result(l)
        integer, intent(in) :: order, seed
        real(real64) :: l(order, order)
        integer      :: i, j
        l = 0.3_real64*reshape(seeded_uniform(order*order, seed), [order, order])
        do j = 1, order
            do i = 1, order
                if( i < j ) l(i, j) = 0._real64
                if( i == j ) l(i, j) = 1._real64+real(i, real64)/real(order, real64)
            end do
        end do
    end function lower_triangular

    ! the strict upper triangle of a square matrix, the rest zero
    function strict_upper( a ) result(u)
        real(real64), intent(in) :: a(:,:)
        real(real64) :: u(size(a, 1), size(a, 2))
        integer      :: i, j
        u = 0._real64
        do j = 1, size(a, 2)
            do i = 1, min(j-1, size(a, 1))
                u(i, j) = a(i, j)
            end do
        end do
    end function strict_upper

    function identity( order ) result(e)
        integer, intent(in) :: order
        real(real64) :: e(order, order)
        integer      :: i
        e = 0._real64
        do i = 1, order
            e(i, i) = 1._real64
        end do
    end function identity

    pure function fro_real( a ) result(f)
        real(real64), intent(in) :: a(:,:)
        real(real64) :: f
        f = sqrt(sum(a**2))
    end function fro_real

    pure function fro_complex( a ) result(f)
        complex(real64), intent(in) :: a(:,:)
        real(real64) :: f
        f = sqrt(sum(real(a, real64)**2+aimag(a)**2))
    end function fro_complex

    ! the determinant by Gaussian elimination with row pivoting, in real64
    function det_reference( a ) result(d)
        real(real64), intent(in) :: a(:,:)
        real(real64) :: d, w(size(a, 1), size(a, 1)), row(size(a, 1))
        integer      :: i, j, p
        w = a
        d = 1._real64
        do j = 1, size(w, 1)
            p = j-1+maxloc(abs(w(j:, j)), dim=1)
            if( p /= j )then
                row = w(j, :)
                w(j, :) = w(p, :)
                w(p, :) = row
                d = -d
            endif
            d = d*w(j, j)
            do i = j+1, size(w, 1)
                w(i, :) = w(i, :)-w(i, j)/w(j, j)*w(j, :)
            end do
        end do
    end function det_reference

    ! the lower Cholesky factor of a symmetric positive definite matrix, in real64
    function cholesky_reference( a ) result(l)
        real(real64), intent(in) :: a(:,:)
        real(real64) :: l(size(a, 1), size(a, 1))
        integer      :: i, j
        l = 0._real64
        do j = 1, size(a, 1)
            l(j, j) = sqrt(a(j, j)-sum(l(j, :j-1)**2))
            do i = j+1, size(a, 1)
                l(i, j) = (a(i, j)-sum(l(i, :j-1)*l(j, :j-1)))/l(j, j)
            end do
        end do
    end function cholesky_reference

    ! the elements of r in array element order when it is a float32 or float64 array of shape want
    subroutine fetch_flat( r, want, out, ok )
        type(mlx_array), intent(in)  :: r
        integer,         intent(in)  :: want(:)
        real(real64),    intent(out) :: out(:)
        logical,         intent(out) :: ok
        real(real32), allocatable :: got(:)
        integer,      allocatable :: sh(:)
        integer                   :: st
        ok = .false.
        out = 0._real64
        sh = r%shape()
        if( size(sh) /= size(want) ) return
        if( any(sh /= want) ) return
        if( r%kind() == MLX_DTYPES%float64 )then
            call mlx_to(out, r, status=st)
        else if( r%kind() == MLX_DTYPES%float32 )then
            allocate(got(size(out)))
            call mlx_to(got, r, status=st)
            out = real(got, real64)
        else
            return
        endif
        ok = st == 0
    end subroutine fetch_flat

    subroutine fetch1( r, out, ok )
        type(mlx_array), intent(in)  :: r
        real(real64),    intent(out) :: out(:)
        logical,         intent(out) :: ok
        call fetch_flat(r, shape(out), out, ok)
    end subroutine fetch1

    subroutine fetch2( r, out, ok )
        type(mlx_array), intent(in)  :: r
        real(real64),    intent(out) :: out(:,:)
        logical,         intent(out) :: ok
        real(real64) :: flat(size(out))
        call fetch_flat(r, shape(out), flat, ok)
        out = reshape(flat, shape(out))
    end subroutine fetch2

    subroutine fetch3( r, out, ok )
        type(mlx_array), intent(in)  :: r
        real(real64),    intent(out) :: out(:,:,:)
        logical,         intent(out) :: ok
        real(real64) :: flat(size(out))
        call fetch_flat(r, shape(out), flat, ok)
        out = reshape(flat, shape(out))
    end subroutine fetch3

    subroutine fetch_complex1( r, out, ok )
        type(mlx_array), intent(in)  :: r
        complex(real64), intent(out) :: out(:)
        logical,         intent(out) :: ok
        complex(real32) :: got(size(out))
        integer         :: st
        ok = .false.
        out = (0._real64, 0._real64)
        if( r%ndim() /= 1 ) return
        if( r%kind() /= MLX_DTYPES%complex64 ) return
        if( r%size() /= size(out) ) return
        call mlx_to(got, r, status=st)
        out = cmplx(got, kind=real64)
        ok = st == 0
    end subroutine fetch_complex1

    subroutine fetch_complex2( r, out, ok )
        type(mlx_array), intent(in)  :: r
        complex(real64), intent(out) :: out(:,:)
        logical,         intent(out) :: ok
        complex(real32) :: got(size(out, 1), size(out, 2))
        integer         :: st
        ok = .false.
        out = (0._real64, 0._real64)
        if( r%ndim() /= 2 ) return
        if( r%kind() /= MLX_DTYPES%complex64 ) return
        if( any(r%shape() /= shape(out)) ) return
        call mlx_to(got, r, status=st)
        out = cmplx(got, kind=real64)
        ok = st == 0
    end subroutine fetch_complex2

    ! the inverse of a matrix and of a batch of two: the residual of matmul(a, x) against the identity
    subroutine test_inv
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: r
        real(real64)         :: a(N, N, 2), ain(N, N, 2), x(N, N), xb(N, N, 2), resid
        integer              :: s, pass, k
        logical              :: wide, ok, shaped
        write(*,'(a)') 'test_inv'
        seeds = family_seeds()
        do s = 1, size(seeds)
            a(:, :, 1) = with_singular_values(N, N, spectrum(N), 6000*seeds(s)+1)
            a(:, :, 2) = with_singular_values(N, N, spectrum(N), 6000*seeds(s)+3)
            do pass = 1, passes()
                wide = pass == 2
                ain = given(a, wide)
                r = mlx_inv(seeded_array(a(:, :, 1), wide))
                call fetch(r, x, shaped)
                resid = fro(matmul(ain(:, :, 1), x)-identity(N))/(fro(ain(:, :, 1))*fro(x))
                r = mlx_inv(seeded_array(a, wide))
                call fetch(r, xb, ok)
                shaped = shaped .and. ok
                do k = 1, 2
                    resid = max(resid, fro(matmul(ain(:, :, k), xb(:, :, k))-identity(N))/(fro(ain(:, :, k))*fro(xb(:, :, k))))
                end do
                call judge_residual(resid, N, wide, 'mlx_inv', seeds(s))
                call assert_true(shaped, 'mlx_inv returns the shape of its operand, a batch along dimension 3 included')
            end do
        end do
    end subroutine test_inv

    ! the inverse of a triangular matrix read from the named triangle alone: the other triangle of the operand holds
    ! values that would spoil the inverse
    subroutine test_tri_inv
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: r
        real(real64)         :: l(N, N), junk(N, N), lin(N, N), x(N, N), resid
        integer              :: s, pass
        logical              :: wide, ok, shaped
        write(*,'(a)') 'test_tri_inv'
        seeds = family_seeds()
        do s = 1, size(seeds)
            l = lower_triangular(N, 6100*seeds(s)+1)
            junk = strict_upper(reshape(seeded_uniform(N*N, 6100*seeds(s)+2), [N, N]))
            do pass = 1, passes()
                wide = pass == 2
                lin = given(l, wide)
                r = mlx_tri_inv(seeded_array(l+junk, wide))
                call fetch(r, x, shaped)
                resid = fro(matmul(lin, x)-identity(N))/(fro(lin)*fro(x))
                r = mlx_tri_inv(seeded_array(transpose(l+junk), wide), upper=.true.)
                call fetch(r, x, ok)
                shaped = shaped .and. ok
                resid = max(resid, fro(matmul(transpose(lin), x)-identity(N))/(fro(lin)*fro(x)))
                call judge_residual(resid, N, wide, 'mlx_tri_inv', seeds(s))
                call assert_true(shaped, 'mlx_tri_inv returns the shape of its operand')
            end do
        end do
    end subroutine test_tri_inv

    ! the pseudo-inverse of a (6, 4) matrix of full column rank: (4, 6), a left inverse, and matmul(a, x) a
    ! projection that leaves a unchanged
    subroutine test_pinv
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: r
        real(real64)         :: a(LONG, SHORT), ain(LONG, SHORT), x(SHORT, LONG), resid
        integer              :: s, pass
        logical              :: wide, shaped
        write(*,'(a)') 'test_pinv'
        seeds = family_seeds()
        do s = 1, size(seeds)
            a = with_singular_values(LONG, SHORT, spectrum(SHORT), 6200*seeds(s)+1)
            do pass = 1, passes()
                wide = pass == 2
                ain = given(a, wide)
                r = mlx_pinv(seeded_array(a, wide))
                call fetch(r, x, shaped)
                resid = fro(matmul(x, ain)-identity(SHORT))/(fro(ain)*fro(x))
                resid = max(resid, fro(matmul(ain, matmul(x, ain))-ain)/(fro(ain)**2*fro(x)))
                call judge_residual(resid, LONG, wide, 'mlx_pinv', seeds(s))
                call assert_true(shaped, 'mlx_pinv of a (6, 4) matrix is (4, 6)')
            end do
        end do
    end subroutine test_pinv

    ! determinants of order 3 (MLX's closed form) and 5 (its factorisation), in batches of two whose second matrix
    ! is the first with two rows exchanged: the same magnitude, the other sign
    subroutine test_det
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol_det, tol_log
        type(mlx_array)      :: a, r, sgn, lad
        real(real64)         :: a3(3, 3, 2), a5(N, N, 2), ref3(2), ref5(2), err, err_log
        integer              :: s, pass, k
        logical              :: wide, signed
        write(*,'(a)') 'test_det'
        tol_det = find_tolerance(MATRIX_TOLERANCES, 'mlx_det')
        tol_log = find_tolerance(MATRIX_TOLERANCES, 'mlx_slogdet')
        seeds = family_seeds()
        do s = 1, size(seeds)
            a3(:, :, 1) = with_singular_values(3, 3, spectrum(3), 6300*seeds(s)+1)
            a5(:, :, 1) = with_singular_values(N, N, spectrum(N), 6300*seeds(s)+3)
            a3(:, :, 2) = a3([2, 1, 3], :, 1)
            a5(:, :, 2) = a5([2, 1, 3, 4, 5], :, 1)
            do pass = 1, passes()
                wide = pass == 2
                do k = 1, 2
                    ref3(k) = det_reference(given(a3(:, :, k), wide))
                    ref5(k) = det_reference(given(a5(:, :, k), wide))
                end do
                a = seeded_array(a3, wide)
                r = mlx_det(a)
                err = shaped_error(r, ref3, abs(ref3))
                call mlx_slogdet(a, sgn, lad)
                signed = shaped_error(sgn, sign(1._real64, ref3), abs(ref3)) <= 0._real64
                err_log = shaped_error(lad, log(abs(ref3)), abs(log(abs(ref3))))
                a = seeded_array(a5, wide)
                r = mlx_det(a)
                err = nan_max(err, shaped_error(r, ref5, abs(ref5)))
                call mlx_slogdet(a, sgn, lad)
                if( shaped_error(sgn, sign(1._real64, ref5), abs(ref5)) > 0._real64 ) signed = .false.
                err_log = nan_max(err_log, shaped_error(lad, log(abs(ref5)), abs(log(abs(ref5)))))
                call judge(err, tol_det, wide, seeds(s))
                call judge(err_log, tol_log, wide, seeds(s))
                call assert_true(signed, 'mlx_slogdet returns exactly 1 or -1 as the sign, opposite for two exchanged rows')
            end do
        end do
    end subroutine test_det

    ! the Cholesky factor, lower by default and upper when asked, of a symmetric positive definite matrix, and the
    ! inverse from a factor: the backward error, the other triangle exactly zero, the residual of the inverse
    subroutine test_cholesky
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: a, r
        real(real64)         :: x(N, N), xin(N, N), l(N, N), lref(N, N), lin(N, N), inv(N, N), resid, resid_inv
        integer              :: s, pass
        logical              :: wide, ok, shaped, clean
        write(*,'(a)') 'test_cholesky'
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = with_eigenvalues(spectrum(N), 6400*seeds(s)+1)
            x = 0.5_real64*(x+transpose(x))
            lref = cholesky_reference(x)
            do pass = 1, passes()
                wide = pass == 2
                xin = given(x, wide)
                a = seeded_array(x, wide)
                r = mlx_cholesky(a)
                call fetch(r, l, shaped)
                resid = fro(xin-matmul(l, transpose(l)))/fro(xin)
                clean = all(abs(strict_upper(l)) <= 0._real64)
                r = mlx_cholesky(a, upper=.true.)
                call fetch(r, l, ok)
                shaped = shaped .and. ok
                resid = max(resid, fro(xin-matmul(transpose(l), l))/fro(xin))
                if( any(abs(strict_upper(transpose(l))) > 0._real64) ) clean = .false.
                call judge_residual(resid, N, wide, 'mlx_cholesky', seeds(s))
                call assert_true(shaped, 'mlx_cholesky returns the shape of its operand')
                call assert_true(clean, 'mlx_cholesky: a = l l^T with l lower triangular, a = u^T u with u upper, the other triangle exactly zero')
                lin = given(lref, wide)
                r = mlx_cholesky_inv(seeded_array(lref, wide))
                call fetch(r, inv, shaped)
                resid_inv = fro(matmul(matmul(lin, transpose(lin)), inv)-identity(N))/(fro(matmul(lin, transpose(lin)))*fro(inv))
                r = mlx_cholesky_inv(seeded_array(transpose(lref), wide), upper=.true.)
                call fetch(r, inv, ok)
                shaped = shaped .and. ok
                resid_inv = max(resid_inv, fro(matmul(matmul(lin, transpose(lin)), inv)-identity(N))/(fro(matmul(lin, transpose(lin)))*fro(inv)))
                call judge_residual(resid_inv, N, wide, 'mlx_cholesky_inv', seeds(s))
                call assert_true(shaped, 'mlx_cholesky_inv returns the shape of its operand')
            end do
        end do
    end subroutine test_cholesky

    ! what one QR factorisation gave: the backward error, the departure of q's columns from orthonormal, and whether
    ! the factors have their shapes and r is exactly upper triangular
    subroutine qr_case( a, wide, resid, ortho, exact )
        real(real64), intent(in)    :: a(:,:)
        logical,      intent(in)    :: wide
        real(real64), intent(inout) :: resid, ortho
        logical,      intent(inout) :: exact
        type(mlx_array)           :: q, r
        real(real64), allocatable :: qv(:,:), rv(:,:), ain(:,:)
        integer                   :: m, k, kk
        logical                   :: ok
        m = size(a, 1)
        k = size(a, 2)
        kk = min(m, k)
        allocate(qv(m, kk), rv(kk, k))
        ain = given(a, wide)
        call mlx_qr(seeded_array(a, wide), q, r)
        call fetch(q, qv, ok)
        if( .not. ok ) exact = .false.
        call fetch(r, rv, ok)
        if( .not. ok ) exact = .false.
        if( any(abs(strict_upper(transpose(rv))) > 0._real64) ) exact = .false.
        resid = max(resid, fro(ain-matmul(qv, rv))/fro(ain))
        ortho = max(ortho, fro(matmul(transpose(qv), qv)-identity(kk)))
    end subroutine qr_case

    ! a = q r for a tall and a wide matrix, and for a batch of two tall ones
    subroutine test_qr
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: q, r
        real(real64)         :: tall(LONG, SHORT, 2), wider(SHORT, LONG), tin(LONG, SHORT, 2), qb(LONG, SHORT, 2), rb(SHORT, SHORT, 2)
        real(real64)         :: resid, ortho
        integer              :: s, pass, k
        logical              :: wide, ok, exact
        write(*,'(a)') 'test_qr'
        seeds = family_seeds()
        do s = 1, size(seeds)
            tall(:, :, 1) = with_singular_values(LONG, SHORT, spectrum(SHORT), 6500*seeds(s)+1)
            tall(:, :, 2) = with_singular_values(LONG, SHORT, spectrum(SHORT), 6500*seeds(s)+3)
            wider = transpose(with_singular_values(LONG, SHORT, spectrum(SHORT), 6500*seeds(s)+5))
            do pass = 1, passes()
                wide = pass == 2
                resid = 0._real64
                ortho = 0._real64
                exact = .true.
                call qr_case(tall(:, :, 1), wide, resid, ortho, exact)
                call qr_case(wider, wide, resid, ortho, exact)
                tin = given(tall, wide)
                call mlx_qr(seeded_array(tall, wide), q, r)
                call fetch(q, qb, ok)
                if( .not. ok ) exact = .false.
                call fetch(r, rb, ok)
                if( .not. ok ) exact = .false.
                do k = 1, 2
                    resid = max(resid, fro(tin(:, :, k)-matmul(qb(:, :, k), rb(:, :, k)))/fro(tin(:, :, k)))
                    ortho = max(ortho, fro(matmul(transpose(qb(:, :, k)), qb(:, :, k))-identity(SHORT)))
                end do
                call judge_residual(resid, LONG, wide, 'mlx_qr a = q r', seeds(s))
                call judge_residual(ortho, LONG, wide, 'mlx_qr orthonormal columns', seeds(s))
                call assert_true(exact, 'mlx_qr: q is (m, k) and r (k, n) with k the smaller extent, r exactly upper triangular')
            end do
        end do
    end subroutine test_qr

    ! what one LU factorisation gave: the backward error of a(i, :) = (l u)(p(i), :), and whether p is a permutation
    ! of 1 to m, l unit lower triangular and u upper triangular, exactly, with their shapes
    subroutine lu_case( a, wide, resid, exact )
        real(real64), intent(in)    :: a(:,:)
        logical,      intent(in)    :: wide
        real(real64), intent(inout) :: resid
        logical,      intent(inout) :: exact
        type(mlx_array)             :: p, l, u
        real(real64),   allocatable :: lv(:,:), uv(:,:), ain(:,:), lu(:,:)
        integer(int32), allocatable :: pv(:)
        integer                     :: m, k, kk, i, st
        logical                     :: ok
        m = size(a, 1)
        k = size(a, 2)
        kk = min(m, k)
        allocate(lv(m, kk), uv(kk, k), pv(m))
        ain = given(a, wide)
        call mlx_lu(seeded_array(a, wide), p, l, u)
        call fetch(l, lv, ok)
        if( .not. ok ) exact = .false.
        call fetch(u, uv, ok)
        if( .not. ok ) exact = .false.
        pv = 0
        st = 1
        if( p%kind() == MLX_DTYPES%int32 )then
            if( p%size() == m ) call mlx_to(pv, p, status=st)
        endif
        if( st /= 0 ) exact = .false.
        do i = 1, m
            if( count(pv == i) /= 1 ) exact = .false.
        end do
        if( .not. exact ) return
        if( any(abs(strict_upper(lv)) > 0._real64) .or. any(abs(strict_upper(transpose(uv))) > 0._real64) ) exact = .false.
        do i = 1, kk
            if( abs(lv(i, i)-1._real64) > 0._real64 ) exact = .false.
        end do
        lu = matmul(lv, uv)
        resid = max(resid, fro(ain-lu(pv, :))/fro(ain))
    end subroutine lu_case

    ! row i of a is row p(i) of l u, for a square, a tall and a wide matrix
    subroutine test_lu
        integer, allocatable :: seeds(:)
        real(real64)         :: sq(N, N), tall(LONG, SHORT), resid
        integer              :: s, pass
        logical              :: wide, exact
        write(*,'(a)') 'test_lu'
        seeds = family_seeds()
        do s = 1, size(seeds)
            sq = with_singular_values(N, N, spectrum(N), 6600*seeds(s)+1)
            tall = with_singular_values(LONG, SHORT, spectrum(SHORT), 6600*seeds(s)+3)
            do pass = 1, passes()
                wide = pass == 2
                resid = 0._real64
                exact = .true.
                call lu_case(sq, wide, resid, exact)
                call lu_case(tall, wide, resid, exact)
                call lu_case(transpose(tall), wide, resid, exact)
                call judge_residual(resid, LONG, wide, 'mlx_lu', seeds(s))
                call assert_true(exact, 'mlx_lu: p a permutation of 1 to m (int32), l (m, k) unit lower and u (k, n) upper triangular, exactly')
            end do
        end do
    end subroutine test_lu

    ! the packed factorisation: exchanging row i of a with row pivots(i), for i = 1, 2, ... in turn, gives l u with l
    ! below the diagonal of the packed array (a unit diagonal) and u on and above it
    subroutine test_lu_factor
        integer,        allocatable :: seeds(:)
        type(mlx_array)             :: lu, pivots
        real(real64)                :: a(N, N), ain(N, N), packed(N, N), l(N, N), u(N, N), row(N), resid
        integer(int32)              :: piv(N)
        integer                     :: s, pass, i, st
        logical                     :: wide, shaped, ranged
        write(*,'(a)') 'test_lu_factor'
        seeds = family_seeds()
        do s = 1, size(seeds)
            a = with_singular_values(N, N, spectrum(N), 6700*seeds(s)+1)
            do pass = 1, passes()
                wide = pass == 2
                ain = given(a, wide)
                call mlx_lu_factor(seeded_array(a, wide), lu, pivots)
                call fetch(lu, packed, shaped)
                piv = 0
                st = 1
                if( pivots%kind() == MLX_DTYPES%int32 )then
                    if( pivots%size() == N ) call mlx_to(piv, pivots, status=st)
                endif
                ranged = st == 0
                do i = 1, N
                    if( piv(i) < i .or. piv(i) > N ) ranged = .false.
                end do
                call assert_true(shaped, 'mlx_lu_factor returns the packed factors with the shape of its operand')
                call assert_true(ranged, 'mlx_lu_factor: pivots are 1-based int32 rows, pivots(i) from i to m')
                if( .not. ranged ) cycle
                do i = 1, N
                    row = ain(i, :)
                    ain(i, :) = ain(piv(i), :)
                    ain(piv(i), :) = row
                end do
                u = packed-transpose(strict_upper(transpose(packed)))
                l = identity(N)+transpose(strict_upper(transpose(packed)))
                resid = fro(ain-matmul(l, u))/fro(ain)
                call judge_residual(resid, N, wide, 'mlx_lu_factor', seeds(s))
            end do
        end do
    end subroutine test_lu_factor

    ! what one singular value decomposition gave: the backward error, the departure of u and vt from orthogonal, the
    ! error of the singular values against the constructed ones, and the shapes and the descending order
    subroutine svd_case( a, sig, wide, measured, exact )
        real(real64), intent(in)    :: a(:,:), sig(:)
        logical,      intent(in)    :: wide
        real(real64), intent(inout) :: measured(3)
        logical,      intent(inout) :: exact
        type(mlx_array)           :: u, s, vt, alone
        real(real64), allocatable :: uv(:,:), sv(:), vv(:,:), ain(:,:), back(:,:), only(:)
        integer                   :: m, k, kk, i
        logical                   :: ok
        m = size(a, 1)
        k = size(a, 2)
        kk = min(m, k)
        allocate(uv(m, m), sv(kk), vv(k, k), only(kk))
        ain = given(a, wide)
        call mlx_svd(seeded_array(a, wide), u, s, vt)
        call fetch(u, uv, ok)
        if( .not. ok ) exact = .false.
        call fetch(s, sv, ok)
        if( .not. ok ) exact = .false.
        call fetch(vt, vv, ok)
        if( .not. ok ) exact = .false.
        call mlx_svd(seeded_array(a, wide), alone)
        call fetch(alone, only, ok)
        if( .not. ok ) exact = .false.
        if( any(sv(2:) > sv(:kk-1)) ) exact = .false.
        allocate(back(m, k))
        back = 0._real64
        do i = 1, kk
            back = back+sv(i)*spread(uv(:, i), 2, k)*spread(vv(i, :), 1, m)
        end do
        measured(1) = max(measured(1), fro(ain-back)/fro(ain))
        measured(2) = max(measured(2), fro(matmul(transpose(uv), uv)-identity(m)), fro(matmul(vv, transpose(vv))-identity(k)))
        measured(3) = nan_maxval([measured(3), nan_maxval(abs(sv-sig(kk:1:-1)))/fro(ain), nan_maxval(abs(only-sig(kk:1:-1)))/fro(ain)])
    end subroutine svd_case

    ! a = u diag(s) vt for a tall and a wide matrix, with the singular values alone agreeing
    subroutine test_svd
        integer, allocatable :: seeds(:)
        real(real64)         :: tall(LONG, SHORT), measured(3)
        integer              :: s, pass
        logical              :: wide, exact
        write(*,'(a)') 'test_svd'
        seeds = family_seeds()
        do s = 1, size(seeds)
            tall = with_singular_values(LONG, SHORT, spectrum(SHORT), 6800*seeds(s)+1)
            do pass = 1, passes()
                wide = pass == 2
                measured = 0._real64
                exact = .true.
                call svd_case(tall, spectrum(SHORT), wide, measured, exact)
                call svd_case(transpose(tall), spectrum(SHORT), wide, measured, exact)
                call judge_residual(measured(1), LONG, wide, 'mlx_svd a = u s vt', seeds(s))
                call judge_residual(measured(2), LONG, wide, 'mlx_svd orthogonal u and vt', seeds(s))
                call judge_residual(measured(3), LONG, wide, 'mlx_svd singular values', seeds(s))
                call assert_true(exact, 'mlx_svd: u is (m, m), s (k) descending and vt (n, n); the values alone have s''s shape')
            end do
        end do
    end subroutine test_svd

    ! a complex (4, 3) matrix: a = u diag(s) vt with vt the conjugate transpose of v, and u unitary
    subroutine test_svd_complex
        integer, parameter :: M = 4, K = 3
        type(mlx_array)    :: u, s, vt
        complex(real32)    :: c(M, K)
        complex(real64)    :: a(M, K), uv(M, M), vv(K, K), back(M, K), gram(M, M)
        real(real64)       :: sv(K), resid, ortho
        integer            :: i
        logical            :: ok, shaped
        write(*,'(a)') 'test_svd_complex'
        c = cmplx(reshape(seeded_uniform(M*K, 7301), [M, K]), reshape(seeded_uniform(M*K, 7302), [M, K]), real32)
        a = cmplx(c, kind=real64)
        call mlx_svd(mlx_from(c), u, s, vt)
        call fetch_complex(u, uv, shaped)
        call fetch(s, sv, ok)
        shaped = shaped .and. ok
        call fetch_complex(vt, vv, ok)
        shaped = shaped .and. ok
        back = (0._real64, 0._real64)
        do i = 1, K
            back = back+sv(i)*spread(uv(:, i), 2, K)*spread(vv(i, :), 1, M)
        end do
        gram = matmul(conjg(transpose(uv)), uv)
        do i = 1, M
            gram(i, i) = gram(i, i)-1._real64
        end do
        resid = fro(a-back)/fro(a)
        ortho = fro(gram)
        call judge_residual(resid, M, .false., 'mlx_svd complex a = u s vt', 0)
        call judge_residual(ortho, M, .false., 'mlx_svd complex unitary u', 0)
        call assert_true(shaped, 'mlx_svd of a complex (4, 3) matrix: complex u (4, 4) and vt (3, 3), real s (3)')
    end subroutine test_svd_complex

    ! the eigenvalues and eigenvectors of a symmetric matrix read from one triangle: the other triangle of the
    ! operand holds values that would change them. Ascending eigenvalues against the constructed ones, the residual
    ! of a v = v diag(w), orthonormal columns, and mlx_eigvalsh the same values
    subroutine test_eigh
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: a, w, v, r
        real(real64)         :: x(N, N), xin(N, N), junk(N, N), lam(N), wv(N), vv(N, N), only(N), measured(3)
        integer              :: s, pass, form, i
        logical              :: wide, ok, exact
        write(*,'(a)') 'test_eigh'
        do i = 1, N
            lam(i) = -2._real64+5._real64*real(i-1, real64)/real(N-1, real64)
        end do
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = with_eigenvalues(lam, 6900*seeds(s)+1)
            x = 0.5_real64*(x+transpose(x))
            junk = strict_upper(reshape(seeded_uniform(N*N, 6900*seeds(s)+2), [N, N]))
            do pass = 1, passes()
                wide = pass == 2
                xin = given(x, wide)
                measured = 0._real64
                exact = .true.
                do form = 1, 3
                    if( form == 1 )then
                        a = seeded_array(x+junk, wide)
                        call mlx_eigh(a, w, v)
                        r = mlx_eigvalsh(a)
                    else if( form == 2 )then
                        a = seeded_array(x+transpose(junk), wide)
                        call mlx_eigh(a, w, v, uplo='U')
                        r = mlx_eigvalsh(a, uplo='U')
                    else
                        a = seeded_array(x+junk, wide)
                        call mlx_eigh(a, w, v, uplo='L')
                        r = mlx_eigvalsh(a, uplo='L')
                    endif
                    call fetch(w, wv, ok)
                    if( .not. ok ) exact = .false.
                    call fetch(v, vv, ok)
                    if( .not. ok ) exact = .false.
                    call fetch(r, only, ok)
                    if( .not. ok ) exact = .false.
                    if( any(wv(2:) < wv(:N-1)) ) exact = .false.
                    measured(1) = max(measured(1), fro(matmul(xin, vv)-vv*spread(wv, 1, N))/fro(xin))
                    measured(2) = max(measured(2), fro(matmul(transpose(vv), vv)-identity(N)))
                    measured(3) = nan_maxval([measured(3), nan_maxval(abs(wv-lam))/fro(xin), nan_maxval(abs(only-lam))/fro(xin)])
                end do
                call judge_residual(measured(1), N, wide, 'mlx_eigh a v = v w', seeds(s))
                call judge_residual(measured(2), N, wide, 'mlx_eigh orthonormal eigenvectors', seeds(s))
                call judge_residual(measured(3), N, wide, 'mlx_eigh and mlx_eigvalsh eigenvalues', seeds(s))
                call assert_true(exact, 'mlx_eigh: w (n) ascending and v (n, n), read from the lower triangle unless uplo is ''U''')
            end do
        end do
    end subroutine test_eigh

    ! a complex Hermitian matrix: real eigenvalues, a v = v diag(w) with the eigenvectors as columns, unitary v
    subroutine test_eigh_complex
        integer, parameter :: M = 4
        type(mlx_array)    :: w, v
        complex(real32)    :: c(M, M)
        complex(real64)    :: a(M, M), vv(M, M), gram(M, M)
        real(real64)       :: wv(M), resid, ortho
        integer            :: i
        logical            :: ok, shaped
        write(*,'(a)') 'test_eigh_complex'
        c = cmplx(reshape(seeded_uniform(M*M, 7401), [M, M]), reshape(seeded_uniform(M*M, 7402), [M, M]), real32)
        c = c+conjg(transpose(c))
        a = cmplx(c, kind=real64)
        call mlx_eigh(mlx_from(c), w, v)
        call fetch(w, wv, shaped)
        call fetch_complex(v, vv, ok)
        shaped = shaped .and. ok
        gram = matmul(conjg(transpose(vv)), vv)
        do i = 1, M
            gram(i, i) = gram(i, i)-1._real64
        end do
        resid = fro(matmul(a, vv)-vv*spread(cmplx(wv, kind=real64), 1, M))/fro(a)
        ortho = fro(gram)
        call judge_residual(resid, M, .false., 'mlx_eigh complex a v = v w', 0)
        call judge_residual(ortho, M, .false., 'mlx_eigh complex unitary v', 0)
        call assert_true(shaped, 'mlx_eigh of a Hermitian matrix: real w (n) and complex v (n, n)')
    end subroutine test_eigh_complex

    ! the largest distance from a value of one list to the nearest value of the other, both ways
    function spectra_apart( got, want ) result(d)
        complex(real64), intent(in) :: got(:), want(:)
        real(real64) :: d
        integer      :: i
        d = 0._real64
        do i = 1, size(want)
            d = nan_maxval([d, minval(abs(got-want(i))), minval(abs(want-got(i)))])
        end do
    end function spectra_apart

    ! a normal matrix that is not symmetric, with the eigenvalues 0.5 +- 2i, -1 +- 0.75i and 1.5: the eigenvalues
    ! against these, the residual of a v = v diag(w) with the right eigenvectors as columns, and mlx_eigvals the same
    ! values in the same order
    subroutine test_eig
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: a, w, v, r
        real(real64)         :: core(N, N), q(N, N), x(N, N), measured(3)
        complex(real64)      :: lam(N), wv(N), vv(N, N), only(N), xc(N, N)
        integer              :: s, pass
        logical              :: wide, ok, shaped
        write(*,'(a)') 'test_eig'
        core = 0._real64
        core(1:2, 1:2) = reshape([0.5_real64, 2._real64, -2._real64, 0.5_real64], [2, 2])
        core(3:4, 3:4) = reshape([-1._real64, 0.75_real64, -0.75_real64, -1._real64], [2, 2])
        core(5, 5) = 1.5_real64
        lam = [cmplx(0.5_real64, 2._real64, real64), cmplx(0.5_real64, -2._real64, real64), &
            &cmplx(-1._real64, 0.75_real64, real64), cmplx(-1._real64, -0.75_real64, real64), cmplx(1.5_real64, 0._real64, real64)]
        seeds = family_seeds()
        do s = 1, size(seeds)
            q = orthogonal(N, 7000*seeds(s)+1)
            x = matmul(q, matmul(core, transpose(q)))
            do pass = 1, passes()
                wide = pass == 2
                xc = cmplx(given(x, wide), kind=real64)
                a = seeded_array(x, wide)
                call mlx_eig(a, w, v)
                call fetch_complex(w, wv, shaped)
                call fetch_complex(v, vv, ok)
                shaped = shaped .and. ok
                r = mlx_eigvals(a)
                call fetch_complex(r, only, ok)
                shaped = shaped .and. ok
                measured(1) = fro(matmul(xc, vv)-vv*spread(wv, 1, N))/(fro(xc)*fro(vv))
                measured(2) = max(spectra_apart(wv, lam), spectra_apart(only, lam))/fro(xc)
                measured(3) = nan_maxval(abs(only-wv))/fro(xc)
                call judge_residual(measured(1), N, .false., 'mlx_eig a v = v w'//operand(wide), seeds(s))
                call judge_residual(measured(2), N, .false., 'mlx_eig and mlx_eigvals eigenvalues'//operand(wide), seeds(s))
                call judge_residual(measured(3), N, .false., 'mlx_eigvals in mlx_eig''s order'//operand(wide), seeds(s))
                call assert_true(shaped, 'mlx_eig: complex w (n) and v (n, n); mlx_eigvals complex (n)')
            end do
        end do
    end subroutine test_eig

    ! the backward error of a solution: the residual over the scale of the equations
    function backward_error( a, x, b ) result(eta)
        real(real64), intent(in) :: a(:,:), x(:,:), b(:,:)
        real(real64) :: eta
        eta = fro(matmul(a, x)-b)/(fro(a)*fro(x)+fro(b))
    end function backward_error

    ! a x = b for one right-hand side (a vector), for three as the columns of a matrix, and for a batch of two systems
    subroutine test_solve
        integer, parameter   :: NRHS = 3
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: r
        real(real64)         :: a(N, N, 2), ain(N, N, 2), b(N, NRHS, 2), bin(N, NRHS, 2), x1(N), x(N, NRHS), xb(N, NRHS, 2), eta
        integer              :: s, pass, k
        logical              :: wide, ok, shaped
        write(*,'(a)') 'test_solve'
        seeds = family_seeds()
        do s = 1, size(seeds)
            a(:, :, 1) = with_singular_values(N, N, spectrum(N), 7100*seeds(s)+1)
            a(:, :, 2) = with_singular_values(N, N, spectrum(N), 7100*seeds(s)+3)
            b = reshape(seeded_uniform(size(b), 7100*seeds(s)+5), shape(b))
            do pass = 1, passes()
                wide = pass == 2
                ain = given(a, wide)
                bin = given(b, wide)
                r = mlx_solve(seeded_array(a(:, :, 1), wide), seeded_array(b(:, 1, 1), wide))
                call fetch(r, x1, shaped)
                eta = backward_error(ain(:, :, 1), reshape(x1, [N, 1]), bin(:, 1:1, 1))
                r = mlx_solve(seeded_array(a(:, :, 1), wide), seeded_array(b(:, :, 1), wide))
                call fetch(r, x, ok)
                shaped = shaped .and. ok
                eta = max(eta, backward_error(ain(:, :, 1), x, bin(:, :, 1)))
                r = mlx_solve(seeded_array(a, wide), seeded_array(b, wide))
                call fetch(r, xb, ok)
                shaped = shaped .and. ok
                do k = 1, 2
                    eta = max(eta, backward_error(ain(:, :, k), xb(:, :, k), bin(:, :, k)))
                end do
                call judge_residual(eta, N, wide, 'mlx_solve', seeds(s))
                call assert_true(shaped, 'mlx_solve returns the shape of b: a vector, columns of right-hand sides, a batch')
            end do
        end do
    end subroutine test_solve

    ! triangular systems read from the named triangle alone (the other holds values that would spoil the solution),
    ! lower by default and upper when asked, for a vector and for columns of right-hand sides
    subroutine test_solve_triangular
        integer, parameter   :: NRHS = 3
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: r
        real(real64)         :: l(N, N), lin(N, N), junk(N, N), b(N, NRHS), bin(N, NRHS), x1(N), x(N, NRHS), eta
        integer              :: s, pass
        logical              :: wide, ok, shaped
        write(*,'(a)') 'test_solve_triangular'
        seeds = family_seeds()
        do s = 1, size(seeds)
            l = lower_triangular(N, 7200*seeds(s)+1)
            junk = strict_upper(reshape(seeded_uniform(N*N, 7200*seeds(s)+2), [N, N]))
            b = reshape(seeded_uniform(size(b), 7200*seeds(s)+3), shape(b))
            do pass = 1, passes()
                wide = pass == 2
                lin = given(l, wide)
                bin = given(b, wide)
                r = mlx_solve_triangular(seeded_array(l+junk, wide), seeded_array(b(:, 1), wide))
                call fetch(r, x1, shaped)
                eta = backward_error(lin, reshape(x1, [N, 1]), bin(:, 1:1))
                r = mlx_solve_triangular(seeded_array(l+junk, wide), seeded_array(b, wide))
                call fetch(r, x, ok)
                shaped = shaped .and. ok
                eta = max(eta, backward_error(lin, x, bin))
                r = mlx_solve_triangular(seeded_array(transpose(l+junk), wide), seeded_array(b, wide), upper=.true.)
                call fetch(r, x, ok)
                shaped = shaped .and. ok
                eta = max(eta, backward_error(transpose(lin), x, bin))
                call judge_residual(eta, N, wide, 'mlx_solve_triangular', seeds(s))
                call assert_true(shaped, 'mlx_solve_triangular returns the shape of b')
            end do
        end do
    end subroutine test_solve_triangular

    ! the Euclidean norm (whole, along a dimension, over two, with the reduced dimensions kept) and the vector norms
    ! of orders 1, 3, 0 and plus and minus infinity along a dimension
    subroutine test_norms
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tol2, tolp
        type(mlx_array)      :: a, r
        real(real64)         :: x(4, 3, 2), v(7), inf, err2, errp
        integer              :: s, pass
        logical              :: wide
        write(*,'(a)') 'test_norms'
        tol2 = find_tolerance(MATRIX_TOLERANCES, 'norm2')
        tolp = find_tolerance(MATRIX_TOLERANCES, 'mlx_norm')
        inf = ieee_value(1._real64, ieee_positive_inf)
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(seeded_uniform(size(x), 7300*seeds(s)+1), shape(x))
            v = seeded_uniform(size(v), 7300*seeds(s)+2)
            v(3) = 0._real64
            do pass = 1, passes()
                wide = pass == 2
                a = seeded_array(x, wide)
                r = norm2(a)
                err2 = shaped_error(r, norm2(x), norm2(x))
                r = norm2(a, keepdims=.true.)
                err2 = max(err2, shaped_error(r, reshape([norm2(x)], [1, 1, 1]), reshape([norm2(x)], [1, 1, 1])))
                r = norm2(a, dim=2)
                err2 = max(err2, shaped_error(r, norm2(x, dim=2), norm2(x, dim=2)))
                r = norm2(a, dim=3, keepdims=.true.)
                err2 = max(err2, shaped_error(r, reshape(norm2(x, dim=3), [4, 3, 1]), reshape(norm2(x, dim=3), [4, 3, 1])))
                r = norm2(a, dims=[1, 2])
                err2 = max(err2, shaped_error(r, sqrt(sum(sum(x**2, dim=1), dim=1)), sqrt(sum(sum(x**2, dim=1), dim=1))))
                call judge(err2, tol2, wide, seeds(s))
                r = mlx_norm(a, 1._real64, dim=2)
                errp = shaped_error(r, sum(abs(x), dim=2), sum(abs(x), dim=2))
                r = mlx_norm(a, 3._real64, dim=1, keepdims=.true.)
                errp = nan_max(errp, shaped_error(r, reshape(sum(abs(x)**3, dim=1)**(1._real64/3._real64), [1, 3, 2]), &
                    &reshape(sum(abs(x)**3, dim=1)**(1._real64/3._real64), [1, 3, 2])))
                r = mlx_norm(a, inf, dims=[3])
                errp = nan_max(errp, shaped_error(r, maxval(abs(x), dim=3), maxval(abs(x), dim=3)))
                r = mlx_norm(a, -inf, dim=3)
                errp = nan_max(errp, shaped_error(r, minval(abs(x), dim=3), minval(abs(x), dim=3)))
                a = seeded_array(v, wide)
                r = mlx_norm(a, 1._real64)
                errp = nan_max(errp, shaped_error(r, sum(abs(v)), sum(abs(v))))
                r = mlx_norm(a, 0._real64)
                errp = nan_max(errp, shaped_error(r, real(count(abs(v) > 0._real64), real64), 1._real64))
                call judge(errp, tolp, wide, seeds(s))
            end do
        end do
    end subroutine test_norms

    ! the matrix norms of a (4, 3) matrix with known singular values: the largest and smallest column sums (orders 1
    ! and -1) and row sums (plus and minus infinity), which exchange when the dimensions are listed as [2, 1]; the
    ! Frobenius norm; and, from the singular values, the orders 2 and -2 and the nuclear norm, over a batch as well
    subroutine test_matrix_norms
        integer, parameter   :: M = 4, K = 3
        integer, allocatable :: seeds(:)
        type(elem_tolerance) :: tolp, tolm
        type(mlx_array)      :: a, r
        real(real64)         :: x(M, K, 2), xin(M, K, 2), sig(K), inf, errp, errm, spectral
        real(real64)         :: cols(2), rows(2), fros(2)
        integer              :: s, pass, j
        logical              :: wide
        write(*,'(a)') 'test_matrix_norms'
        tolp = find_tolerance(MATRIX_TOLERANCES, 'mlx_norm')
        tolm = find_tolerance(MATRIX_TOLERANCES, 'mlx_norm_matrix')
        inf = ieee_value(1._real64, ieee_positive_inf)
        sig = spectrum(K)
        seeds = family_seeds()
        do s = 1, size(seeds)
            x(:, :, 1) = with_singular_values(M, K, sig, 7400*seeds(s)+1)
            x(:, :, 2) = with_singular_values(M, K, sig, 7400*seeds(s)+3)
            do pass = 1, passes()
                wide = pass == 2
                xin = given(x, wide)
                do j = 1, 2
                    cols(j) = maxval(sum(abs(xin(:, :, j)), dim=1))
                    rows(j) = maxval(sum(abs(xin(:, :, j)), dim=2))
                    fros(j) = fro(xin(:, :, j))
                end do
                a = seeded_array(x(:, :, 1), wide)
                r = mlx_norm(a, 1._real64)
                errp = shaped_error(r, cols(1), cols(1))
                r = mlx_norm(a, inf)
                errp = max(errp, shaped_error(r, rows(1), rows(1)))
                r = mlx_norm(a, 1._real64, dims=[2, 1])
                errp = max(errp, shaped_error(r, rows(1), rows(1)))
                r = mlx_norm(a, -1._real64)
                errp = nan_max(errp, shaped_error(r, minval(sum(abs(xin(:, :, 1)), dim=1)), cols(1)))
                r = mlx_norm(a, -inf, keepdims=.true.)
                errp = nan_max(errp, shaped_error(r, reshape([minval(sum(abs(xin(:, :, 1)), dim=2))], [1, 1]), reshape(rows(1:1), [1, 1])))
                r = mlx_norm_matrix(a, 'fro')
                errm = shaped_error(r, fros(1), fros(1))
                a = seeded_array(x, wide)
                r = mlx_norm(a, 1._real64, dims=[1, 2])
                errp = max(errp, shaped_error(r, cols, cols))
                r = mlx_norm_matrix(a, 'fro')
                errm = max(errm, shaped_error(r, fros, fros))
                r = mlx_norm_matrix(a, 'fro', dims=[2, 1], keepdims=.true.)
                errm = max(errm, shaped_error(r, reshape(fros, [1, 1, 2]), reshape(fros, [1, 1, 2])))
                call judge(errp, tolp, wide, seeds(s))
                call judge(errm, tolm, wide, seeds(s))
                r = mlx_norm(a, 2._real64, dims=[1, 2])
                spectral = shaped_error(r, [sig(K), sig(K)], fros)
                r = mlx_norm(a, -2._real64, dims=[2, 1])
                spectral = max(spectral, shaped_error(r, [sig(1), sig(1)], fros))
                r = mlx_norm_matrix(a, 'nuc')
                spectral = max(spectral, shaped_error(r, [sum(sig), sum(sig)], fros))
                a = seeded_array(x(:, :, 2), wide)
                r = mlx_norm(a, 2._real64)
                spectral = max(spectral, shaped_error(r, sig(K), fros(2)))
                r = mlx_norm_matrix(a, 'nuc', keepdims=.true.)
                spectral = max(spectral, shaped_error(r, reshape([sum(sig)], [1, 1]), reshape(fros(2:2), [1, 1])))
                call judge_residual(spectral, M, wide, 'mlx_norm 2, -2 and mlx_norm_matrix nuc', seeds(s))
            end do
        end do
    end subroutine test_matrix_norms

end module mlxf_linalg_matrix_tester
