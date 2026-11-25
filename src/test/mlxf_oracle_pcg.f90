!@descr: host oracle of the PCG problem: stencil matrix, transform operator, preconditioner, Cholesky and PCG solves
! H = S C^T F^-1 diag(d) F C S + lambda I on an n-cube centre-embedded in a periodic m-grid, d(q) = 1 + 4 sum of
! sin(pi q / m)**2, so the spectral part is the seven-point stencil 7 v - six neighbours; the preconditioner is
! C^T F^-1 diag(1 / (d + lambda)) F C. Unknown (i, j, k), 0-based, is vector element 1 + i + n j + n**2 k. The
! transforms are mlxf_oracle_dft's; the solve is preconditioned conjugate gradients in double precision.
module mlxf_oracle_pcg
use, intrinsic :: iso_fortran_env, only: real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_value, ieee_positive_inf, ieee_quiet_nan
use mlxf_oracle_dft, only: oracle_dft_3d, oracle_idft_3d, oracle_finite_or_inf
implicit none

public :: oracle_pcg_problem, oracle_pcg_true, oracle_pcg_cholesky, oracle_pcg_selfcheck
private

real(real64), parameter :: PI     = acos(-1._real64)
real(real64), parameter :: LAMBDA = 0.25_real64
! the stencil of the spectral part: the centre and each of the six face neighbours
real(real64), parameter :: CENTRE    = 7._real64
real(real64), parameter :: NEIGHBOUR = -1._real64
! the window: one inside, a half on the surface of the n-cube
real(real64), parameter :: S_INSIDE  = 1._real64
real(real64), parameter :: S_SURFACE = 0.5_real64
! the solve stops when the updated residual falls to TOL_STOP times |b|; its statuses
real(real64), parameter :: TOL_STOP        = 1.e-14_real64
integer,      parameter :: STATUS_CONVERGED = 0
integer,      parameter :: STATUS_LIMIT     = 1
integer,      parameter :: STATUS_NOT_SPD   = 2
integer,      parameter :: STATUS_NOT_FINITE = 3
! the self-check: the fixture's sizes, the bound on the spectrum, and the limits of the transform and normwise
! checks; exact checks have limit 0
integer,      parameter :: N_SMALL = 4
integer,      parameter :: M_SMALL = 8
integer,      parameter :: N_LARGE = 8
integer,      parameter :: M_LARGE = 16
real(real64), parameter :: SPECTRUM_MAX  = 13.25_real64
! the explicit matrices' entries by value in the padded, zero-face and unpadded cases: diagonal 7.25, 2 and 0.25,
! off-diagonal -1, -1/2 and -1/4
integer,      parameter :: DIAG_725(3) = [8, 8, 64]
integer,      parameter :: DIAG_2(3)   = [56, 40, 0]
integer,      parameter :: DIAG_025(3) = [0, 16, 0]
integer,      parameter :: OFF_1(3)    = [24, 24, 384]
integer,      parameter :: OFF_05(3)   = [48, 40, 0]
integer,      parameter :: OFF_025(3)  = [216, 144, 0]
real(real64), parameter :: TOL_TRANSFORM = 1.e-12_real64
real(real64), parameter :: TOL_NORM      = 1.e-12_real64
integer,      parameter :: NCHECK    = 14
integer,      parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'counts', 'symmetry', 'curvature', 'transforms vs matrix', 'stencil vs matrix', 'stencil vs transforms 16', &
    'imaginary parts', 'precond vs cholesky', 'cholesky vs true', 'pcg vs cholesky', 'pcg true residual', &
    'unpadded one step', 'statuses', 'zero rhs']
real(real64), parameter :: CHECK_LIMITS(NCHECK) = [0._real64, 0._real64, 0._real64, TOL_NORM, TOL_NORM, TOL_NORM, &
    TOL_TRANSFORM, TOL_NORM, TOL_NORM, TOL_NORM, TOL_NORM, TOL_NORM, 0._real64, 0._real64]

! one problem: an n-cube in an m-grid with its window, the sign of the operator (-1 makes it negative definite)
! and the iteration cap of its solve
type :: oracle_pcg_problem
    private
    integer                   :: n = 0, m = 0, offset = 0, cap = 0
    real(real64)              :: sgn = 1._real64
    real(real64), allocatable :: s(:,:,:)
    logical                   :: exists = .false.
  contains
    procedure :: new => pcg_new
    procedure :: kill => pcg_kill
    procedure :: set_cap => pcg_set_cap
    procedure :: window => pcg_window
    procedure :: matrix => pcg_matrix
    procedure :: apply => pcg_apply
    procedure :: apply_fft => pcg_apply_fft
    procedure :: precond => pcg_precond
    procedure :: precond_dense => pcg_precond_dense
    procedure :: solve => pcg_solve
end type oracle_pcg_problem

contains

    ! an n-cube in an m-grid (m = n, or m >= n + 2 with m - n even); window 'identity', 'surface' (1 inside, 1/2
    ! on the surface) or 'face' (the surface window with the face i = 0 set to zero); sgn = 1 or -1
    subroutine pcg_new( self, n, m, window, sgn )
        class(oracle_pcg_problem), intent(inout) :: self
        integer,                   intent(in)    :: n, m
        character(len=*),          intent(in)    :: window
        real(real64),              intent(in)    :: sgn
        integer :: i, j, k
        call self%kill()
        self%n      = n
        self%m      = m
        self%offset = (m - n) / 2
        self%cap    = n**3
        self%sgn    = sgn
        allocate(self%s(0:n-1, 0:n-1, 0:n-1))
        do k = 0, n - 1
            do j = 0, n - 1
                do i = 0, n - 1
                    select case( window )
                        case( 'identity' )
                            self%s(i, j, k) = S_INSIDE
                        case( 'surface', 'face' )
                            if( any([i, j, k] == 0) .or. any([i, j, k] == n - 1) )then
                                self%s(i, j, k) = S_SURFACE
                            else
                                self%s(i, j, k) = S_INSIDE
                            endif
                            if( window == 'face' .and. i == 0 ) self%s(i, j, k) = 0._real64
                        case default
                            self%s(i, j, k) = 0._real64
                    end select
                end do
            end do
        end do
        self%exists = .true.
    end subroutine pcg_new

    ! release the window; idempotent
    subroutine pcg_kill( self )
        class(oracle_pcg_problem), intent(inout) :: self
        if( .not. self%exists ) return
        if( allocated(self%s) ) deallocate(self%s)
        self%exists = .false.
    end subroutine pcg_kill

    ! the iteration cap of the solve; new sets it to the number of unknowns
    subroutine pcg_set_cap( self, cap )
        class(oracle_pcg_problem), intent(inout) :: self
        integer,                   intent(in)    :: cap
        self%cap = cap
    end subroutine pcg_set_cap

    ! the window S on the n-cube
    pure function pcg_window( self ) result(s)
        class(oracle_pcg_problem), intent(in) :: self
        real(real64) :: s(self%n, self%n, self%n)
        s = self%s
    end function pcg_window

    ! the explicit matrix from the stencil: H(u, v) = S_u A(u, v) S_v + lambda on the diagonal, times the sign, with A
    ! the centre on the diagonal and NEIGHBOUR between unknowns whose embedded positions are periodic face
    ! neighbours of the m-grid; neighbours outside the cube are cropped, coinciding ones added
    pure function pcg_matrix( self ) result(h)
        class(oracle_pcg_problem), intent(in) :: self
        real(real64) :: h(self%n**3, self%n**3)
        integer      :: g(3), e(3), q(3), u, v, i, j, k, a, side
        h = 0._real64
        do k = 0, self%n - 1
            do j = 0, self%n - 1
                do i = 0, self%n - 1
                    u      = unknown([i, j, k], self%n)
                    h(u, u) = h(u, u) + self%s(i, j, k) * CENTRE * self%s(i, j, k)
                    g      = self%offset + [i, j, k]
                    do a = 1, 3
                        do side = -1, 1, 2
                            e    = 0
                            e(a) = side
                            q    = modulo(g + e, self%m) - self%offset
                            if( all(q >= 0 .and. q <= self%n - 1) )then
                                v      = unknown(q, self%n)
                                h(u, v) = h(u, v) + self%s(i, j, k) * NEIGHBOUR * self%s(q(1), q(2), q(3))
                            endif
                        end do
                    end do
                    h(u, u) = h(u, u) + LAMBDA
                end do
            end do
        end do
        h = self%sgn * h
    end function pcg_matrix

    ! the operator without a matrix: S x embedded in the m-grid, the periodic stencil by circular shifts, the crop,
    ! S again, plus lambda x, times the sign
    pure function pcg_apply( self, x ) result(y)
        class(oracle_pcg_problem), intent(in) :: self
        real(real64),              intent(in) :: x(:,:,:)
        real(real64) :: y(self%n, self%n, self%n)
        real(real64) :: g(self%m, self%m, self%m), kg(self%m, self%m, self%m)
        integer      :: a, lo, hi
        lo = self%offset + 1
        hi = self%offset + self%n
        g  = 0._real64
        g(lo:hi, lo:hi, lo:hi) = self%s * x
        kg = CENTRE * g
        do a = 1, 3
            kg = kg + NEIGHBOUR * (cshift(g, 1, a) + cshift(g, -1, a))
        end do
        y = self%sgn * (self%s * kg(lo:hi, lo:hi, lo:hi) + LAMBDA * x)
    end function pcg_apply

    ! the operator by transforms, S C^T F^-1 diag(d) F C S x + lambda x times the sign; imag is the largest
    ! imaginary part of the inverse transform relative to its largest magnitude, dropped from y
    subroutine pcg_apply_fft( self, x, y, imag )
        class(oracle_pcg_problem), intent(in)  :: self
        real(real64),              intent(in)  :: x(:,:,:)
        real(real64),              intent(out) :: y(:,:,:)
        real(real64),              intent(out) :: imag
        complex(real64) :: g(self%m, self%m, self%m)
        integer         :: lo, hi
        lo = self%offset + 1
        hi = self%offset + self%n
        g  = (0._real64, 0._real64)
        g(lo:hi, lo:hi, lo:hi) = cmplx(self%s * x, 0._real64, real64)
        g    = oracle_idft_3d(oracle_dft_3d(g) * spectrum(self%m))
        imag = imag_share(g)
        y    = self%sgn * (self%s * real(g(lo:hi, lo:hi, lo:hi)) + LAMBDA * x)
    end subroutine pcg_apply_fft

    ! the preconditioner by transforms, z = C^T F^-1 diag(1 / (d + lambda)) F C r; imag as for apply_fft
    subroutine pcg_precond( self, r, z, imag )
        class(oracle_pcg_problem), intent(in)  :: self
        real(real64),              intent(in)  :: r(:,:,:)
        real(real64),              intent(out) :: z(:,:,:)
        real(real64),              intent(out) :: imag
        complex(real64) :: g(self%m, self%m, self%m)
        integer         :: lo, hi
        lo = self%offset + 1
        hi = self%offset + self%n
        g  = (0._real64, 0._real64)
        g(lo:hi, lo:hi, lo:hi) = cmplx(r, 0._real64, real64)
        g    = oracle_idft_3d(oracle_dft_3d(g) / (spectrum(self%m) + LAMBDA))
        imag = imag_share(g)
        z    = real(g(lo:hi, lo:hi, lo:hi))
    end subroutine pcg_precond

    ! the preconditioner's matrix without transforms: C^T (K + lambda I)^-1 C, with K the explicit periodic stencil
    ! matrix of the m-grid, through its Cholesky factor; a column per unknown
    function pcg_precond_dense( self ) result(pinv)
        class(oracle_pcg_problem), intent(in) :: self
        real(real64)              :: pinv(self%n**3, self%n**3)
        real(real64), allocatable :: kl(:,:), rhs(:), sol(:)
        real(real64)              :: minpivot
        integer                   :: m, g(3), e(3), u, v, i, j, k, a, side, c(self%n**3)
        m = self%m
        allocate(kl(m**3, m**3), rhs(m**3), sol(m**3))
        kl = 0._real64
        do k = 0, m - 1
            do j = 0, m - 1
                do i = 0, m - 1
                    u       = unknown([i, j, k], m)
                    kl(u, u) = kl(u, u) + CENTRE + LAMBDA
                    do a = 1, 3
                        do side = -1, 1, 2
                            e       = 0
                            e(a)    = side
                            v       = unknown(modulo([i, j, k] + e, m), m)
                            kl(u, v) = kl(u, v) + NEIGHBOUR
                        end do
                    end do
                end do
            end do
        end do
        call cholesky_factor(kl, minpivot)
        ! the grid positions of the unknowns
        do k = 0, self%n - 1
            do j = 0, self%n - 1
                do i = 0, self%n - 1
                    g                            = self%offset + [i, j, k]
                    c(unknown([i, j, k], self%n)) = unknown(g, m)
                end do
            end do
        end do
        do u = 1, self%n**3
            rhs       = 0._real64
            rhs(c(u)) = 1._real64
            if( minpivot > 0._real64 )then
                sol = cholesky_solve_factored(kl, rhs)
            else
                sol = ieee_value(minpivot, ieee_positive_inf)
            endif
            pinv(:, u) = sol(c)
        end do
    end function pcg_precond_dense

    ! preconditioned conjugate gradients from the guess in x; info = [iterations done, status]: 0 converged
    ! (|r| <= TOL_STOP |b|, b = 0 giving x = 0), 1 iteration limit, 2 p^T H p <= 0 met before its division,
    ! 3 b or x not finite; hist holds |r| before each iteration and after the last
    subroutine pcg_solve( self, b, x, hist, info )
        class(oracle_pcg_problem), intent(in)    :: self
        real(real64),              intent(in)    :: b(:,:,:)
        real(real64),              intent(inout) :: x(:,:,:)
        real(real64), allocatable, intent(out)   :: hist(:)
        integer,                   intent(out)   :: info(2)
        real(real64) :: r(self%n, self%n, self%n), z(self%n, self%n, self%n), p(self%n, self%n, self%n)
        real(real64) :: q(self%n, self%n, self%n), h(0:self%cap)
        real(real64) :: bnorm, rz, rz_new, kappa, alpha, imag
        integer      :: it
        info  = [0, STATUS_CONVERGED]
        bnorm = norm2(b)
        if( bnorm <= 0._real64 )then
            x    = 0._real64
            hist = [0._real64]
            return
        endif
        r    = b - self%apply(x)
        h(0) = norm2(r)
        ! a non-finite b or x0 is refused; a guess that already meets the stop rule is returned as it is
        if( .not. ieee_is_finite(h(0)) )then
            info(2) = STATUS_NOT_FINITE
            hist    = h(0:0)
            return
        endif
        if( h(0) <= TOL_STOP * bnorm )then
            hist = h(0:0)
            return
        endif
        call self%precond(r, z, imag)
        p  = z
        rz = sum(r * z)
        info(2) = STATUS_LIMIT
        do it = 1, self%cap
            q     = self%apply(p)
            kappa = sum(p * q)
            if( .not. (kappa > 0._real64) )then
                info(2) = STATUS_NOT_SPD
                exit
            endif
            alpha   = rz / kappa
            x       = x + alpha * p
            r       = r - alpha * q
            h(it)   = norm2(r)
            info(1) = it
            if( h(it) <= TOL_STOP * bnorm )then
                info(2) = STATUS_CONVERGED
                exit
            endif
            call self%precond(r, z, imag)
            rz_new = sum(r * z)
            p      = z + (rz_new / rz) * p
            rz     = rz_new
        end do
        hist = h(0:info(1))
    end subroutine pcg_solve

    ! the manufactured solution (1 + modulo(3i + 5j + 7k, 11)) / 11 on the n-cube, i, j, k 0-based
    pure function oracle_pcg_true( n ) result(x)
        integer, intent(in) :: n
        real(real64) :: x(n, n, n)
        integer      :: i, j, k
        do k = 0, n - 1
            do j = 0, n - 1
                do i = 0, n - 1
                    x(i+1, j+1, k+1) = real(1 + modulo(3 * i + 5 * j + 7 * k, 11), real64) / 11._real64
                end do
            end do
        end do
    end function oracle_pcg_true

    ! the solution of a x = b through the Cholesky factor of a symmetric a; minpivot is the smallest pivot before
    ! its root, x holds +Inf when one is not positive
    subroutine oracle_pcg_cholesky( a, b, x, minpivot )
        real(real64), intent(in)  :: a(:,:), b(:)
        real(real64), intent(out) :: x(:)
        real(real64), intent(out) :: minpivot
        real(real64), allocatable :: l(:,:)
        allocate(l(size(a, 1), size(a, 2)))
        l = a
        call cholesky_factor(l, minpivot)
        if( minpivot > 0._real64 )then
            x = cholesky_solve_factored(l, b)
        else
            x = ieee_value(minpivot, ieee_positive_inf)
        endif
    end subroutine oracle_pcg_cholesky

    ! the checks against the explicit matrix, the Cholesky solutions and the solve's contract, as named largest
    ! errors and their limits
    subroutine oracle_pcg_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        type(oracle_pcg_problem) :: pad, face, flat, neg, large
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        limits = CHECK_LIMITS
        errors = 0._real64
        call pad%new(N_SMALL, M_SMALL, 'surface', 1._real64)
        call face%new(N_SMALL, M_SMALL, 'face', 1._real64)
        call flat%new(N_SMALL, N_SMALL, 'identity', 1._real64)
        call neg%new(N_SMALL, M_SMALL, 'surface', -1._real64)
        call large%new(N_LARGE, M_LARGE, 'surface', 1._real64)
        call check_structure(pad, face, flat, large, errors(1:3))
        call check_operators(pad, errors(4:8))
        call check_operators(face, errors(4:8))
        call check_operators(flat, errors(4:8))
        call check_operators(neg, errors(4:8))
        call check_large(large, errors(6:7))
        call check_solves(pad, errors(9:14))
        call check_solves(face, errors(9:14))
        call check_flat(flat, errors(9:14))
        call check_contract(pad, neg, errors(13:14))
        call pad%kill()
        call face%kill()
        call flat%kill()
        call neg%kill()
        call large%kill()
    end subroutine oracle_pcg_selfcheck

    ! counts of the windows and the matrices' nonzeros, symmetry, and positive curvature
    subroutine check_structure( pad, face, flat, large, err )
        type(oracle_pcg_problem), intent(in)    :: pad, face, flat, large
        real(real64),             intent(inout) :: err(3)
        real(real64), allocatable :: h(:,:), x(:), diag(:)
        real(real64)              :: sl(N_LARGE, N_LARGE, N_LARGE)
        real(real64)              :: minpivot, rq
        real(real64)              :: sp(N_SMALL, N_SMALL, N_SMALL), sf(N_SMALL, N_SMALL, N_SMALL), si(N_SMALL, N_SMALL, N_SMALL)
        real(real64)              :: expect
        integer                   :: nbad, icase, u, i, j, k
        ! the windows: 8 inside and 56 on the surface; with the face, 16 zero, 40 half, 8 one
        sp   = pad%window()
        sf   = face%window()
        si   = flat%window()
        nbad = count_ne(count_value(sp, S_INSIDE), 8) + count_ne(count_value(sp, S_SURFACE), 56) + &
               count_ne(count_value(sf, 0._real64), 16) + count_ne(count_value(sf, S_SURFACE), 40) + &
               count_ne(count_value(sf, S_INSIDE), 8) + count_ne(count_value(si, S_INSIDE), 64)
        ! and voxel by voxel: one where every index lies in 1 .. n - 2, a half elsewhere, zero on the face i = 0
        do k = 0, N_SMALL - 1
            do j = 0, N_SMALL - 1
                do i = 0, N_SMALL - 1
                    expect = merge(1._real64, 0.5_real64, minval([i, j, k]) >= 1 .and. maxval([i, j, k]) <= N_SMALL - 2)
                    if( .not. (abs(sp(i+1, j+1, k+1) - expect) <= 0._real64) ) nbad = nbad + 1
                    if( i == 0 ) expect = 0._real64
                    if( .not. (abs(sf(i+1, j+1, k+1) - expect) <= 0._real64) ) nbad = nbad + 1
                end do
            end do
        end do
        ! the nonzeros: 64 diagonal and 288 neighbour entries in the cropped cube, 64 and 384 when periodic
        nbad = nbad + count_ne(count(.not. (abs(pad%matrix()) <= 0._real64)), 352) + &
               count_ne(count(.not. (abs(flat%matrix()) <= 0._real64)), 448)
        ! the window of the 8-cube: 216 inside, 296 on the surface
        sl   = large%window()
        nbad = nbad + count_ne(count_value(sl, S_INSIDE), 216) + count_ne(count_value(sl, S_SURFACE), 296)
        allocate(h(N_SMALL**3, N_SMALL**3), x(N_SMALL**3), diag(N_SMALL**3))
        do icase = 1, 3
            select case( icase )
                case( 1 )
                    h = pad%matrix()
                case( 2 )
                    h = face%matrix()
                case default
                    h = flat%matrix()
            end select
            ! the entries by value, worked by hand, which pin lambda and the window: diagonals 7 + 1/4 inside,
            ! 7/4 + 1/4 on the surface, 1/4 on the zero face; neighbours -1, -1/2, -1/4 as both, one or neither of
            ! the pair lies inside
            diag = [(h(u, u), u=1, N_SMALL**3)]
            nbad = nbad + count_ne(count_exact(diag, 7.25_real64), DIAG_725(icase)) + &
                   count_ne(count_exact(diag, 2._real64), DIAG_2(icase)) + &
                   count_ne(count_exact(diag, 0.25_real64), DIAG_025(icase)) + &
                   count_ne(count_exact(reshape(h, [size(h)]), -1._real64), OFF_1(icase)) + &
                   count_ne(count_exact(reshape(h, [size(h)]), -0.5_real64), OFF_05(icase)) + &
                   count_ne(count_exact(reshape(h, [size(h)]), -0.25_real64), OFF_025(icase))
            ! symmetric by value: its entries are integers times halves
            err(2) = err(2) + real(count(.not. (abs(h - transpose(h)) <= 0._real64)), real64)
            ! positive curvature: every Cholesky pivot positive; the Rayleigh quotients of the unit vectors and of
            ! x_true between lambda and the spectrum's bound
            call oracle_pcg_cholesky(h, h(:, 1), x, minpivot)
            if( .not. (minpivot > 0._real64) ) err(3) = err(3) + 1._real64
            do u = 1, N_SMALL**3
                if( .not. (h(u, u) >= LAMBDA .and. h(u, u) <= SPECTRUM_MAX) ) err(3) = err(3) + 1._real64
            end do
            x  = reshape(oracle_pcg_true(N_SMALL), [N_SMALL**3])
            rq = dot_product(x, matmul(h, x)) / dot_product(x, x)
            if( .not. (rq >= LAMBDA .and. rq <= SPECTRUM_MAX) ) err(3) = err(3) + 1._real64
        end do
        err(1) = real(nbad, real64)
    end subroutine check_structure

    ! the explicit matrix against the transform route and the stencil without a matrix, column by column; the
    ! preconditioner by transforms against the Cholesky inverse
    subroutine check_operators( prob, err )
        type(oracle_pcg_problem), intent(in)    :: prob
        real(real64),             intent(inout) :: err(5)
        real(real64), allocatable :: h(:,:), hf(:,:), hs(:,:), pf(:,:), e(:,:,:), y(:,:,:)
        real(real64)              :: imag
        integer                   :: n, u
        n = N_SMALL
        allocate(h(n**3, n**3), hf(n**3, n**3), hs(n**3, n**3), pf(n**3, n**3), e(n, n, n), y(n, n, n))
        h = prob%matrix()
        do u = 1, n**3
            e = reshape(unit_vector(u, n**3), [n, n, n])
            call prob%apply_fft(e, y, imag)
            hf(:, u) = reshape(y, [n**3])
            err(4)   = max(err(4), oracle_finite_or_inf(imag))
            y        = prob%apply(e)
            hs(:, u) = reshape(y, [n**3])
            call prob%precond(e, y, imag)
            pf(:, u) = reshape(y, [n**3])
            err(4)   = max(err(4), oracle_finite_or_inf(imag))
        end do
        err(1) = max(err(1), norm_rel(hf, h))
        err(2) = max(err(2), norm_rel(hs, h))
        if( prob%sgn > 0._real64 ) err(5) = max(err(5), norm_rel(pf, prob%precond_dense()))
    end subroutine check_operators

    ! the stencil without a matrix against the transform route at n = 8, m = 16, on x_true and fixed vectors
    subroutine check_large( prob, err )
        type(oracle_pcg_problem), intent(in)    :: prob
        real(real64),             intent(inout) :: err(2)
        real(real64) :: x(N_LARGE, N_LARGE, N_LARGE), y(N_LARGE, N_LARGE, N_LARGE), imag
        integer      :: iv
        do iv = 0, 2
            if( iv == 0 )then
                x = oracle_pcg_true(N_LARGE)
            else
                x = fixed_vector(N_LARGE, iv)
            endif
            call prob%apply_fft(x, y, imag)
            err(1) = max(err(1), norm_rel(prob%apply(x), y))
            err(2) = max(err(2), oracle_finite_or_inf(imag))
        end do
    end subroutine check_large

    ! Cholesky against the manufactured solution; the solve from zero and from a nonzero guess against Cholesky,
    ! and its true residual by the explicit matrix
    subroutine check_solves( prob, err )
        type(oracle_pcg_problem), intent(in)    :: prob
        real(real64),             intent(inout) :: err(6)
        real(real64), allocatable :: h(:,:), hist(:)
        real(real64)              :: xt(N_SMALL**3), b(N_SMALL**3), xc(N_SMALL**3), x(N_SMALL, N_SMALL, N_SMALL), minpivot
        integer                   :: info(2), iguess
        allocate(h(N_SMALL**3, N_SMALL**3))
        h  = prob%matrix()
        xt = reshape(oracle_pcg_true(N_SMALL), [N_SMALL**3])
        b  = matmul(h, xt)
        call oracle_pcg_cholesky(h, b, xc, minpivot)
        err(1) = max(err(1), norm_rel(xc, xt))
        do iguess = 0, 1
            if( iguess == 0 )then
                x = 0._real64
            else
                x = initial_guess(N_SMALL)
            endif
            call prob%solve(reshape(b, [N_SMALL, N_SMALL, N_SMALL]), x, hist, info)
            err(2) = max(err(2), norm_rel(reshape(x, [N_SMALL**3]), xc))
            err(3) = max(err(3), oracle_finite_or_inf(norm2(b - matmul(h, reshape(x, [N_SMALL**3]))) / norm2(b)))
            if( info(2) /= STATUS_CONVERGED ) err(5) = err(5) + 1._real64
        end do
    end subroutine check_solves

    ! the unpadded case, S = I: the preconditioner is H^-1, so one iteration reaches x_true; the solve converges
    ! after one iteration
    subroutine check_flat( prob, err )
        type(oracle_pcg_problem), intent(inout) :: prob
        real(real64),             intent(inout) :: err(6)
        real(real64), allocatable :: h(:,:), hist(:)
        real(real64)              :: xt(N_SMALL**3), b(N_SMALL**3), xc(N_SMALL**3), x(N_SMALL, N_SMALL, N_SMALL), minpivot
        integer                   :: info(2)
        allocate(h(N_SMALL**3, N_SMALL**3))
        h  = prob%matrix()
        xt = reshape(oracle_pcg_true(N_SMALL), [N_SMALL**3])
        b  = matmul(h, xt)
        call oracle_pcg_cholesky(h, b, xc, minpivot)
        err(1) = max(err(1), norm_rel(xc, xt))
        ! one iteration exactly: the solution and its true residual
        call prob%set_cap(1)
        x = 0._real64
        call prob%solve(reshape(b, [N_SMALL, N_SMALL, N_SMALL]), x, hist, info)
        err(4) = max(err(4), norm_rel(reshape(x, [N_SMALL**3]), xt), &
                     oracle_finite_or_inf(norm2(b - matmul(h, reshape(x, [N_SMALL**3]))) / norm2(b)))
        ! with the full cap it stops converged after one iteration
        call prob%set_cap(N_SMALL**3)
        x = 0._real64
        call prob%solve(reshape(b, [N_SMALL, N_SMALL, N_SMALL]), x, hist, info)
        err(5) = err(5) + real(count_ne(info(1), 1) + count_ne(info(2), STATUS_CONVERGED), real64)
    end subroutine check_flat

    ! the iteration limit, the refusal of a negative definite operator before its division, and the zero
    ! right-hand side
    subroutine check_contract( pad, neg, err )
        type(oracle_pcg_problem), intent(inout) :: pad
        type(oracle_pcg_problem), intent(in)    :: neg
        real(real64),             intent(inout) :: err(2)
        real(real64), allocatable :: hist(:)
        real(real64)              :: b(N_SMALL, N_SMALL, N_SMALL), x(N_SMALL, N_SMALL, N_SMALL), x0(N_SMALL, N_SMALL, N_SMALL)
        real(real64)              :: bnan(N_SMALL, N_SMALL, N_SMALL)
        integer                   :: info(2)
        b = pad%apply(oracle_pcg_true(N_SMALL))
        ! the padded case capped at two iterations stops at the limit
        call pad%set_cap(2)
        x = 0._real64
        call pad%solve(b, x, hist, info)
        err(1) = err(1) + real(count_ne(info(1), 2) + count_ne(info(2), STATUS_LIMIT), real64)
        call pad%set_cap(N_SMALL**3)
        ! -H: refused at the first iteration, the guess untouched
        x0 = initial_guess(N_SMALL)
        x  = x0
        call neg%solve(b, x, hist, info)
        err(1) = err(1) + real(count_ne(info(1), 0) + count_ne(info(2), STATUS_NOT_SPD) + &
                               count(.not. (abs(x - x0) <= 0._real64)), real64)
        ! an exact guess: returned as it is after no iteration
        x = oracle_pcg_true(N_SMALL)
        call pad%solve(b, x, hist, info)
        err(1) = err(1) + real(count_ne(info(1), 0) + count_ne(info(2), STATUS_CONVERGED) + &
                               count(.not. (abs(x - oracle_pcg_true(N_SMALL)) <= 0._real64)), real64)
        ! a NaN in b: refused as not finite, the guess untouched
        bnan          = b
        bnan(1, 1, 1) = ieee_value(bnan(1, 1, 1), ieee_quiet_nan)
        x             = x0
        call pad%solve(bnan, x, hist, info)
        err(1) = err(1) + real(count_ne(info(1), 0) + count_ne(info(2), STATUS_NOT_FINITE) + &
                               count(.not. (abs(x - x0) <= 0._real64)), real64)
        ! b = 0: x = 0 exactly after no iteration, whatever the guess
        x = x0
        call pad%solve(0._real64 * b, x, hist, info)
        err(2) = err(2) + real(count_ne(info(1), 0) + count_ne(info(2), STATUS_CONVERGED) + &
                               count(.not. (abs(x) <= 0._real64)), real64)
    end subroutine check_contract

    ! the 0-based position (i, j, k) of an n-cube as vector element 1 + i + n j + n**2 k
    pure function unknown( ijk, n ) result(u)
        integer, intent(in) :: ijk(3), n
        integer :: u
        u = 1 + ijk(1) + n * ijk(2) + n * n * ijk(3)
    end function unknown

    ! d(q) = 1 + 4 sum over the axes of sin(pi q / m)**2 on the m-grid, q = 0 .. m - 1
    pure function spectrum( m ) result(d)
        integer, intent(in) :: m
        real(real64) :: d(m, m, m)
        real(real64) :: s(m)
        integer      :: q, i, j, k
        do q = 0, m - 1
            s(q+1) = sin(PI * real(q, real64) / real(m, real64))**2
        end do
        do k = 1, m
            do j = 1, m
                do i = 1, m
                    d(i, j, k) = 1._real64 + 4._real64 * (s(i) + s(j) + s(k))
                end do
            end do
        end do
    end function spectrum

    ! the largest imaginary part relative to the largest magnitude
    pure function imag_share( g ) result(r)
        complex(real64), intent(in) :: g(:,:,:)
        real(real64) :: r
        r = 0._real64
        if( maxval(abs(g)) > 0._real64 ) r = maxval(abs(aimag(g))) / maxval(abs(g))
        if( .not. (all(ieee_is_finite(real(g))) .and. all(ieee_is_finite(aimag(g)))) ) r = ieee_value(r, ieee_positive_inf)
    end function imag_share

    ! the lower Cholesky factor of a symmetric matrix, in place; minpivot is the smallest pivot before its root,
    ! and the factorisation stops at the first that is not positive
    pure subroutine cholesky_factor( a, minpivot )
        real(real64), intent(inout) :: a(:,:)
        real(real64), intent(out)   :: minpivot
        real(real64) :: piv
        integer      :: i, j, n
        n        = size(a, 1)
        minpivot = huge(minpivot)
        do j = 1, n
            piv      = a(j, j) - sum(a(j, 1:j-1)**2)
            minpivot = min(minpivot, piv)
            if( .not. (piv > 0._real64) )then
                minpivot = min(minpivot, 0._real64)
                return
            endif
            a(j, j) = sqrt(piv)
            do i = j + 1, n
                a(i, j) = (a(i, j) - sum(a(i, 1:j-1) * a(j, 1:j-1))) / a(j, j)
            end do
        end do
    end subroutine cholesky_factor

    ! x from L L^T x = b with the lower factor in l, by forward and back substitution
    pure function cholesky_solve_factored( l, b ) result(x)
        real(real64), intent(in) :: l(:,:), b(:)
        real(real64) :: x(size(b)), w(size(b))
        integer      :: i, n
        n = size(b)
        do i = 1, n
            w(i) = (b(i) - sum(l(i, 1:i-1) * w(1:i-1))) / l(i, i)
        end do
        do i = n, 1, -1
            x(i) = (w(i) - sum(l(i+1:n, i) * x(i+1:n))) / l(i, i)
        end do
    end function cholesky_solve_factored

    ! |a - ref| over |ref|, Frobenius for matrices; +Inf when a value is not finite
    pure function norm_rel( a, ref ) result(e)
        real(real64), intent(in) :: a(..), ref(..)
        real(real64) :: e
        e = ieee_value(e, ieee_positive_inf)
        select rank( a )
            rank( 1 )
                select rank( ref )
                    rank( 1 )
                        if( all(ieee_is_finite(a)) .and. all(ieee_is_finite(ref)) ) &
                            e = oracle_finite_or_inf(norm2(a - ref) / norm2(ref))
                end select
            rank( 2 )
                select rank( ref )
                    rank( 2 )
                        if( all(ieee_is_finite(a)) .and. all(ieee_is_finite(ref)) ) &
                            e = oracle_finite_or_inf(norm2(a - ref) / norm2(ref))
                end select
            rank( 3 )
                select rank( ref )
                    rank( 3 )
                        if( all(ieee_is_finite(a)) .and. all(ieee_is_finite(ref)) ) &
                            e = oracle_finite_or_inf(norm2(a - ref) / norm2(ref))
                end select
        end select
    end function norm_rel

    ! the number of window entries equal to value (the values 0, 1/2, 1 are exact)
    pure function count_value( s, value ) result(c)
        real(real64), intent(in) :: s(:,:,:), value
        integer :: c
        c = count(abs(s - value) < 0.25_real64)
    end function count_value

    ! the number of entries equal to value, compared by value
    pure function count_exact( a, value ) result(c)
        real(real64), intent(in) :: a(:), value
        integer :: c
        c = count(abs(a - value) <= 0._real64)
    end function count_exact

    ! 1 when two integers differ, else 0
    pure function count_ne( a, b ) result(c)
        integer, intent(in) :: a, b
        integer :: c
        c = merge(1, 0, a /= b)
    end function count_ne

    ! unit vector u of length n
    pure function unit_vector( u, n ) result(e)
        integer, intent(in) :: u, n
        real(real64) :: e(n)
        e    = 0._real64
        e(u) = 1._real64
    end function unit_vector

    ! the nonzero initial guess modulo(2i + 3j + k, 5) / 5, i, j, k 0-based
    pure function initial_guess( n ) result(x)
        integer, intent(in) :: n
        real(real64) :: x(n, n, n)
        integer      :: i, j, k
        do k = 0, n - 1
            do j = 0, n - 1
                do i = 0, n - 1
                    x(i+1, j+1, k+1) = real(modulo(2 * i + 3 * j + k, 5), real64) / 5._real64
                end do
            end do
        end do
    end function initial_guess

    ! a fixed vector from integers, (modulo(3i + 7j + 2k + seed, 13) - 6) / 6, i, j, k 0-based
    pure function fixed_vector( n, seed ) result(x)
        integer, intent(in) :: n, seed
        real(real64) :: x(n, n, n)
        integer      :: i, j, k
        do k = 0, n - 1
            do j = 0, n - 1
                do i = 0, n - 1
                    x(i+1, j+1, k+1) = real(modulo(3 * i + 7 * j + 2 * k + seed, 13) - 6, real64) / 6._real64
                end do
            end do
        end do
    end function fixed_vector

end module mlxf_oracle_pcg
