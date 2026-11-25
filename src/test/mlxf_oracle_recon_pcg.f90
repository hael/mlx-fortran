!@descr: host oracle of the reconstruction as its conjugate-gradient solver sees it: lattice, kernel, operator, solve
! A plane's pixel at loc = 2 (h, k, 0) R adds 8 omega W t exp(-i phi) y / s2 to the numerator and omega W t**2 / s2
! to the density of a periodic m-grid, m = 2 n; the half h = 0 .. m/2 is packed as it is. The operator is
! H = P (C^T F^-1 diag(Khat) F C + lambda) P with a binary mask P and Khat formed from the packed density; the
! preconditioner is P E C^T F^-1 diag(pi) F C E. The solve is preconditioned conjugate gradients stopped on the
! residual, on the step or on the count, its residual recomputed every 25 iterations.
module mlxf_oracle_recon_pcg
use, intrinsic :: iso_fortran_env, only: real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_value, ieee_positive_inf, ieee_quiet_nan
use mlxf_oracle_dft,        only: oracle_dft_3d, oracle_idft_3d, oracle_flat, oracle_rel_error, oracle_finite_or_inf
use mlxf_oracle_projection, only: oracle_proj_stencil, oracle_proj_matrix, oracle_proj_scatter, oracle_proj_pack, &
                                  oracle_proj_expand, oracle_proj_fold, oracle_proj_rotation
use mlxf_oracle_pcg,        only: oracle_pcg_cholesky
use mlxf_oracle_gridding,   only: oracle_grid_plane, oracle_grid_envelope, oracle_grid_reciprocal, &
                                  oracle_grid_half_inverse
use mlxf_test_reduce,       only: nan_maxval
implicit none

public :: oracle_recon_lattice, oracle_recon_problem, oracle_recon_selfcheck
public :: oracle_recon_dense_matrices, oracle_recon_support_index, oracle_recon_symmetric_eigenvalues, &
          oracle_recon_reference_spectrum
private

real(real64),    parameter :: PI    = acos(-1._real64)
real(real64),    parameter :: TWOPI = 2._real64 * PI
complex(real64), parameter :: CZERO = (0._real64, 0._real64)
! the lattice: the numerator's scale
real(real64), parameter :: NUM_SCALE = 8._real64
! the kernel: its scale, the shells kept beyond n, the floor of the window transform's product
real(real64),    parameter :: KERNEL_SCALE = 64._real64
integer,         parameter :: KERNEL_CUT   = 3
real(real64),    parameter :: KERNEL_FLOOR = 1.e-8_real64
! the ridge's mean runs over |q| <= n with ceiling(|q| / 2) <= RIDGE_SHELLS
integer, parameter :: RIDGE_SHELLS = 6
! the preconditioner: a density below PRE_KEEP of its shell's mean is left out, the others are floored by
! PRE_FLOOR of that mean
real(real64),    parameter :: PRE_KEEP  = 0.1_real64
real(real64),    parameter :: PRE_FLOOR = 0.01_real64
! the mask: the soft edge added to the radius, and the least window a start is divided by
real(real64),    parameter :: EDGE_WIDTH  = 6._real64
real(real64),    parameter :: START_FLOOR = 0.1_real64
! the solve: the reconstruction's rules, the interval of the residual's recomputation, the reasons returned
real(real64),    parameter :: RTOL_RECON      = 1.e-4_real64
real(real64),    parameter :: XTOL_RECON      = 1.5e-2_real64
integer,         parameter :: MAXITS_RECON    = 50
integer,         parameter :: RECOMPUTE_EVERY = 25
integer,         parameter :: REASON_RTOL          = 1
integer,         parameter :: REASON_XTOL          = 2
integer,         parameter :: REASON_MAXITS        = 3
integer,         parameter :: REASON_FIXED         = 4
integer,         parameter :: REASON_INDEFINITE    = 5
integer,         parameter :: REASON_ZERO_RHS      = 6
integer,         parameter :: REASON_FIRST_PRODUCT = 7
! the self-check: the two boxes with their mask radii and the relative ridge; per box and plane, the lattice
! voxels a plane touches and those of them that are read; per box, the mask's voxels, the voxels a start is
! divided on, the ridge's set, and the full-lattice voxels the kernel's cut keeps
integer,         parameter :: N_SMALL = 4
integer,         parameter :: N_LARGE = 8
real(real64),    parameter :: MSKRAD(2)        = [1.25_real64, 2.5_real64]
real(real64),    parameter :: LAMBDA_REL       = 0.05_real64
integer,         parameter :: TOUCHED(3, 2)    = reshape([132, 132, 219, 408, 408, 611], [3, 2])
integer,         parameter :: TOUCH_READ(3, 2) = reshape([99, 99, 141, 351, 351, 451], [3, 2])
integer,         parameter :: IN_MASK(2)       = [27, 251]
integer,         parameter :: IN_START(2)      = [19, 171]
integer,         parameter :: IN_RIDGE(2)      = [151, 1151]
integer,         parameter :: KEPT_FULL(2)     = [512, 3961]
! the limits: an operator or a deposit loop against its explicit matrix, a solve iterated to TOL_TIGHT against
! the direct solution; the solve at the reconstruction's rtol is held to SOLVE_FACTOR rtol cond
real(real64),    parameter :: TOL_MATRIX   = 1.e-12_real64
real(real64),    parameter :: TOL_TIGHT    = 1.e-12_real64
real(real64),    parameter :: TOL_SOLVE    = 1.e-9_real64
real(real64),    parameter :: SOLVE_FACTOR = 10._real64
integer,         parameter :: NCHECK    = 21
integer,         parameter :: ICHECK_RTOL = 16
integer,         parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'lattice counts', 'accumulator vs scatter', 'accumulator vs matrix', 'packing', 'packed hermitian', &
    'mask and window', 'kernel spectrum', 'ridge', 'operator vs dense', 'operator symmetry', 'null space', &
    'precond vs dense', 'precond symmetry', 'right-hand side', 'start and ship', 'solve rtol', 'solve to 1e-12', &
    'solve residuals', 'solve reasons', 'stops', 'recomputed residual']
real(real64),    parameter :: CHECK_LIMITS(NCHECK) = [0._real64, TOL_MATRIX, TOL_MATRIX, 0._real64, TOL_MATRIX, &
    0._real64, TOL_MATRIX, TOL_MATRIX, TOL_MATRIX, TOL_MATRIX, 0._real64, TOL_MATRIX, TOL_MATRIX, TOL_MATRIX, &
    TOL_MATRIX, 0._real64, TOL_SOLVE, TOL_MATRIX, 0._real64, 0._real64, TOL_MATRIX]

! the dense matrices of the operator and the preconditioner, the support's unknowns, a symmetric matrix's
! eigenvalues and the preconditioner's spectrum typed apart, exported under the module's prefix
interface oracle_recon_dense_matrices
    module procedure dense_matrices
end interface oracle_recon_dense_matrices

interface oracle_recon_support_index
    module procedure support_index
end interface oracle_recon_support_index

interface oracle_recon_symmetric_eigenvalues
    module procedure symmetric_eigenvalues
end interface oracle_recon_symmetric_eigenvalues

interface oracle_recon_reference_spectrum
    module procedure reference_spectrum
end interface oracle_recon_reference_spectrum

! the accumulators of the lattice insertion on the periodic m-grid, a signed index q stored at 1 + modulo(q, m)
type :: oracle_recon_lattice
    private
    integer                      :: n = 0
    complex(real64), allocatable :: acc(:,:,:)
    real(real64),    allocatable :: dens(:,:,:)
    logical                      :: exists = .false.
  contains
    procedure :: new => lattice_new
    procedure :: kill => lattice_kill
    procedure :: insert => lattice_insert
    procedure :: numerator => lattice_numerator
    procedure :: density => lattice_density
    procedure :: packed_numerator => lattice_packed_numerator
    procedure :: packed_density => lattice_packed_density
end type oracle_recon_lattice

! a linear system as the solve sees it, an operator and a preconditioner on vectors, with the solve's rules
type, abstract :: recon_system
    private
    real(real64) :: rtol   = RTOL_RECON
    real(real64) :: xtol   = XTOL_RECON
    integer      :: maxits = MAXITS_RECON
  contains
    procedure(system_product), deferred :: apply
    procedure(system_product), deferred :: precond
    procedure, non_overridable :: set_rules => system_set_rules
    procedure, non_overridable :: solve => system_solve
end type recon_system

abstract interface
    subroutine system_product( self, x, y )
        import :: recon_system, real64
        class(recon_system), intent(inout) :: self
        real(real64),        intent(in)    :: x(:)
        real(real64),        intent(out)   :: y(:)
    end subroutine system_product
end interface

! the reconstruction's system on the n-cube, its unknown (i1, i2, i3) at vector element i1 + n (i2 - 1) +
! n**2 (i3 - 1): the mask, the soft window, the envelope E, the kernel spectrum and the preconditioner's
! spectrum on the m-grid, and the ridge
type, extends(recon_system) :: oracle_recon_problem
    private
    integer                   :: n = 0
    real(real64)              :: lambda = 0._real64
    real(real64), allocatable :: pmask(:,:,:), pwin(:,:,:), env(:,:,:), khat(:,:,:), pre(:,:,:)
    logical                   :: exists = .false.
  contains
    procedure :: new => problem_new
    procedure :: kill => problem_kill
    procedure :: apply => problem_apply
    procedure :: precond => problem_precond
    procedure :: rhs => problem_rhs
    procedure :: support => problem_support
    procedure :: window => problem_window
    procedure :: kernel => problem_kernel
    procedure :: spectrum => problem_spectrum
    procedure :: ridge => problem_ridge
    procedure :: start => problem_start
    procedure :: ship => problem_ship
end type oracle_recon_problem

! a small dense system for the solve's constructed cases: y = A x and z = B x, the operator's applications
! counted, and from application `first` on the operator is A + shift I
type, extends(recon_system) :: dense_system
    real(real64), allocatable :: a(:,:), b(:,:)
    real(real64)              :: shift  = 0._real64
    integer                   :: first  = huge(1)
    integer                   :: napply = 0
  contains
    procedure :: apply => dense_apply
    procedure :: precond => dense_precond
end type dense_system

contains

    ! empty accumulators for a box of n, on the grid of m = 2 n
    subroutine lattice_new( self, n )
        class(oracle_recon_lattice), intent(inout) :: self
        integer,                     intent(in)    :: n
        call self%kill()
        self%n = n
        allocate(self%acc(2*n, 2*n, 2*n), self%dens(2*n, 2*n, 2*n))
        self%acc    = CZERO
        self%dens   = 0._real64
        self%exists = .true.
    end subroutine lattice_new

    ! release the accumulators; idempotent
    subroutine lattice_kill( self )
        class(oracle_recon_lattice), intent(inout) :: self
        if( .not. self%exists ) return
        if( allocated(self%acc) ) deallocate(self%acc)
        if( allocated(self%dens) ) deallocate(self%dens)
        self%n      = 0
        self%exists = .false.
    end subroutine lattice_kill

    ! insert one plane of the same box: every pixel h, k = -n/2 .. n/2 inside h**2 + k**2 <= (n/2)**2, each
    ! Friedel mate a pixel of its own, with phi = 2 pi (h s1 + k s2) / n; a window whose three h taps lie
    ! strictly between -m/2 and 0 is skipped
    subroutine lattice_insert( self, plane )
        class(oracle_recon_lattice), intent(inout) :: self
        type(oracle_grid_plane),     intent(in)    :: plane
        complex(real64), allocatable :: y(:,:)
        real(real64),    allocatable :: t(:,:), s2(:,:)
        complex(real64)              :: cs
        real(real64)                 :: r(3, 3), sh(2), omega, loc(3), w(3, 3), ww, phi, ds
        integer                      :: tap(3, 3), n, m, nyq, h, k, a, j1, j2, j3, i(3)
        n   = self%n
        m   = 2 * n
        nyq = n / 2
        if( plane%box() /= n ) return
        allocate(y(-nyq:nyq, -nyq:nyq), t(-nyq:nyq, -nyq:nyq), s2(-nyq:nyq, -nyq:nyq))
        y(:,:)  = plane%observed()
        t(:,:)  = plane%ctf()
        s2(:,:) = plane%variance()
        r       = plane%rotation()
        sh      = plane%shift()
        omega   = plane%weight()
        do k = -nyq, nyq
            do h = -nyq, nyq
                if( h * h + k * k > nyq * nyq ) cycle
                loc = 2._real64 * matmul(real([h, k, 0], real64), r)
                do a = 1, 3
                    call oracle_proj_stencil(loc(a), tap(:, a), w(:, a))
                end do
                if( all(tap(:, 1) > -m / 2 .and. tap(:, 1) < 0) ) cycle
                phi = TWOPI * (real(h, real64) * sh(1) + real(k, real64) * sh(2)) / real(n, real64)
                cs  = NUM_SCALE * t(h, k) * exp(cmplx(0._real64, -phi, real64)) * omega * y(h, k) / s2(h, k)
                ds  = t(h, k)**2 * omega / s2(h, k)
                do j3 = 1, 3
                    do j2 = 1, 3
                        do j1 = 1, 3
                            ww                         = w(j1, 1) * w(j2, 2) * w(j3, 3)
                            i                          = 1 + modulo([tap(j1, 1), tap(j2, 2), tap(j3, 3)], m)
                            self%acc(i(1), i(2), i(3))  = self%acc(i(1), i(2), i(3)) + ww * cs
                            self%dens(i(1), i(2), i(3)) = self%dens(i(1), i(2), i(3)) + ww * ds
                        end do
                    end do
                end do
            end do
        end do
    end subroutine lattice_insert

    ! the numerator's accumulator on the m-grid
    pure function lattice_numerator( self ) result(acc)
        class(oracle_recon_lattice), intent(in) :: self
        complex(real64) :: acc(2*self%n, 2*self%n, 2*self%n)
        acc = self%acc
    end function lattice_numerator

    ! the density's accumulator on the m-grid
    pure function lattice_density( self ) result(dens)
        class(oracle_recon_lattice), intent(in) :: self
        real(real64) :: dens(2*self%n, 2*self%n, 2*self%n)
        dens = self%dens
    end function lattice_density

    ! the packed numerator: the planes h = 0 .. m/2 as they are, h = m/2 being the plane stored for -m/2
    pure function lattice_packed_numerator( self ) result(p)
        class(oracle_recon_lattice), intent(in) :: self
        complex(real64) :: p(self%n+1, 2*self%n, 2*self%n)
        p = oracle_proj_pack(self%acc)
    end function lattice_packed_numerator

    ! the packed density, by the same rule
    pure function lattice_packed_density( self ) result(p)
        class(oracle_recon_lattice), intent(in) :: self
        real(real64) :: p(self%n+1, 2*self%n, 2*self%n)
        p = self%dens(1:self%n+1, :,:)
    end function lattice_packed_density

    ! the solve's rules: the residual's and the step's tolerances and the iteration limit; rtol <= 0 asks for
    ! exactly maxits iterations
    subroutine system_set_rules( self, rtol, xtol, maxits )
        class(recon_system), intent(inout) :: self
        real(real64),        intent(in)    :: rtol, xtol
        integer,             intent(in)    :: maxits
        self%rtol   = rtol
        self%xtol   = xtol
        self%maxits = maxits
    end subroutine system_set_rules

    ! preconditioned conjugate gradients from the start in x, whose residual is not tested; info = [iterations,
    ! reason]: 1 rtol, 2 xtol, 3 maxits, 4 fixed iterations, 5 indefinite product (x as it was), 6 zero right-hand
    ! side, 7 non-positive first product (x untouched in both); hist holds |r| / |b| at the start and per iteration
    subroutine system_solve( self, b, x, hist, info )
        class(recon_system),       intent(inout) :: self
        real(real64),              intent(in)    :: b(:)
        real(real64),              intent(inout) :: x(:)
        real(real64), allocatable, intent(out)   :: hist(:)
        integer,                   intent(out)   :: info(2)
        real(real64) :: r(size(b)), z(size(b)), p(size(b)), q(size(b)), h(0:max(self%maxits, 0))
        real(real64) :: bnorm, rho, rho_new, kappa, alpha
        integer      :: it
        info = [0, REASON_ZERO_RHS]
        allocate(hist(0))
        bnorm = sqrt(sum(b * b))
        if( bnorm <= 0._real64 ) return
        if( nan_maxval(abs(x)) > 0._real64 )then
            call self%apply(x, q)
            r = b - q
        else
            r = b
        endif
        call self%precond(r, z)
        p       = z
        rho     = sum(r * z)
        info(2) = REASON_FIRST_PRODUCT
        if( rho <= 0._real64 ) return
        h(0)    = sqrt(sum(r * r)) / bnorm
        info(2) = merge(REASON_MAXITS, REASON_FIXED, self%rtol > 0._real64)
        do it = 1, self%maxits
            call self%apply(p, q)
            kappa = sum(p * q)
            if( .not. (ieee_is_finite(kappa) .and. kappa > 0._real64) )then
                info(2) = REASON_INDEFINITE
                exit
            endif
            alpha = rho / kappa
            x     = x + alpha * p
            r     = r - alpha * q
            if( modulo(it, RECOMPUTE_EVERY) == 0 )then
                call self%apply(x, q)
                r = b - q
            endif
            info(1) = it
            h(it)   = sqrt(sum(r * r)) / bnorm
            if( self%rtol > 0._real64 )then
                if( h(it) <= self%rtol )then
                    info(2) = REASON_RTOL
                    exit
                endif
                if( abs(alpha) * sqrt(sum(p * p)) / max(sqrt(sum(x * x)), epsilon(1._real64)) <= self%xtol )then
                    info(2) = REASON_XTOL
                    exit
                endif
            endif
            if( it == self%maxits ) exit
            call self%precond(r, z)
            rho_new = sum(r * z)
            p       = z + (rho_new / rho) * p
            rho     = rho_new
        end do
        hist = h(0:info(1))
    end subroutine system_solve

    ! the system of a packed density (m/2 + 1, m, m): the mask of radius mskrad (none when it is not positive),
    ! the kernel spectrum, the preconditioner's spectrum, and the ridge, given as it is or, when relative, as a
    ! multiple of 64 times the density's mean over the ridge's set
    subroutine problem_new( self, dens, mskrad, ridge, relative )
        class(oracle_recon_problem), intent(inout) :: self
        real(real64),                intent(in)    :: dens(:,:,:), mskrad, ridge
        logical,                     intent(in)    :: relative
        real(real64), allocatable :: d(:,:,:), psf(:,:,:)
        real(real64)              :: em(size(dens, 2)), en(size(dens, 2)/2), total
        integer                   :: n, m, i, i1, i2, i3, q2, cnt
        call self%kill()
        m      = size(dens, 2)
        n      = m / 2
        self%n = n
        allocate(self%pmask(n, n, n), self%pwin(n, n, n), self%env(n, n, n), self%khat(m, m, m), self%pre(m, m, m), &
                 d(m/2+1, m, m), psf(m, m, m))
        self%pwin  = soft_window(n, mskrad)
        self%pmask = merge(1._real64, 0._real64, self%pwin > 0._real64)
        ! the envelope on the n-cube: the window's transform on the m-grid at the offset from the centre voxel
        en = oracle_grid_envelope([(i - 1 - n / 2, i=1, n)], m)
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    self%env(i1, i2, i3) = en(i1) * en(i2) * en(i3)
                end do
            end do
        end do
        ! the density kept inside the cut, and its mean over the ridge's set
        total = 0._real64
        cnt   = 0
        do i3 = 1, m
            do i2 = 1, m
                do i1 = 1, m / 2 + 1
                    q2            = (i1 - 1)**2 + signed_index(i2, m)**2 + signed_index(i3, m)**2
                    d(i1, i2, i3) = dens(i1, i2, i3)
                    if( nint(sqrt(real(q2, real64))) > n + KERNEL_CUT ) d(i1, i2, i3) = 0._real64
                    if( in_ridge_set(q2, n) )then
                        total = total + d(i1, i2, i3)
                        cnt   = cnt + 1
                    endif
                end do
            end do
        end do
        ! the kernel spectrum: the density's point spread about the origin, divided by the window's transform
        ! at the offset from the origin, transformed back
        psf = real(oracle_idft_3d(oracle_proj_expand(cmplx(d, 0._real64, real64))))
        em  = oracle_grid_envelope([(i - 1, i=1, m)], m)
        do i3 = 1, m
            do i2 = 1, m
                do i1 = 1, m
                    psf(i1, i2, i3) = psf(i1, i2, i3) * kernel_reciprocal(em(i1) * em(i2) * em(i3))
                end do
            end do
        end do
        self%khat   = KERNEL_SCALE * real(oracle_dft_3d(cmplx(psf, 0._real64, real64)))
        self%lambda = ridge
        if( relative ) self%lambda = ridge * KERNEL_SCALE * total / real(cnt, real64)
        self%pre    = real(oracle_proj_expand(cmplx(precond_half(dens, n), 0._real64, real64)))
        self%exists = .true.
    end subroutine problem_new

    ! release the system; idempotent
    subroutine problem_kill( self )
        class(oracle_recon_problem), intent(inout) :: self
        if( .not. self%exists ) return
        if( allocated(self%pmask) ) deallocate(self%pmask)
        if( allocated(self%pwin) ) deallocate(self%pwin)
        if( allocated(self%env) ) deallocate(self%env)
        if( allocated(self%khat) ) deallocate(self%khat)
        if( allocated(self%pre) ) deallocate(self%pre)
        self%n      = 0
        self%exists = .false.
    end subroutine problem_kill

    ! the operator: y = P (C^T F^-1 diag(Khat) F C (P x) + lambda (P x)), C the embedding at offset n/2
    subroutine problem_apply( self, x, y )
        class(oracle_recon_problem), intent(inout) :: self
        real(real64),                intent(in)    :: x(:)
        real(real64),                intent(out)   :: y(:)
        complex(real64) :: g(2*self%n, 2*self%n, 2*self%n)
        real(real64)    :: u(self%n, self%n, self%n)
        integer         :: n, lo, hi
        n  = self%n
        lo = n / 2 + 1
        hi = n / 2 + n
        u  = self%pmask * reshape(x, [n, n, n])
        g  = CZERO
        g(lo:hi, lo:hi, lo:hi) = cmplx(u, 0._real64, real64)
        g  = oracle_idft_3d(oracle_dft_3d(g) * self%khat)
        y  = reshape(self%pmask * (real(g(lo:hi, lo:hi, lo:hi)) + self%lambda * u), [n**3])
    end subroutine problem_apply

    ! the preconditioner: z = P E C^T F^-1 diag(pi) F C (E r)
    subroutine problem_precond( self, x, y )
        class(oracle_recon_problem), intent(inout) :: self
        real(real64),                intent(in)    :: x(:)
        real(real64),                intent(out)   :: y(:)
        complex(real64) :: g(2*self%n, 2*self%n, 2*self%n)
        integer         :: n, lo, hi
        n  = self%n
        lo = n / 2 + 1
        hi = n / 2 + n
        g  = CZERO
        g(lo:hi, lo:hi, lo:hi) = cmplx(self%env * reshape(x, [n, n, n]), 0._real64, real64)
        g  = oracle_idft_3d(oracle_dft_3d(g) * self%pre)
        y  = reshape(self%pmask * self%env * real(g(lo:hi, lo:hi, lo:hi)), [n**3])
    end subroutine problem_precond

    ! the right-hand side of a packed numerator: b = P E^-1 C^T m**3 F^-1[num], the inverse transform real and
    ! about the centre voxel, E^-1 zero where |E| is below its floor
    function problem_rhs( self, num ) result(b)
        class(oracle_recon_problem), intent(in) :: self
        complex(real64),             intent(in) :: num(:,:,:)
        real(real64) :: b(self%n**3)
        real(real64) :: g(2*self%n, 2*self%n, 2*self%n)
        integer      :: n, lo, hi
        n  = self%n
        lo = n / 2 + 1
        hi = n / 2 + n
        g  = oracle_grid_half_inverse(num)
        b  = reshape(self%pmask * oracle_grid_reciprocal(self%env) * g(lo:hi, lo:hi, lo:hi), [n**3])
    end function problem_rhs

    ! the binary mask P on the n-cube, one where the soft window is positive
    pure function problem_support( self ) result(p)
        class(oracle_recon_problem), intent(in) :: self
        real(real64) :: p(self%n, self%n, self%n)
        p = self%pmask
    end function problem_support

    ! the soft window on the n-cube
    pure function problem_window( self ) result(w)
        class(oracle_recon_problem), intent(in) :: self
        real(real64) :: w(self%n, self%n, self%n)
        w = self%pwin
    end function problem_window

    ! the kernel spectrum Khat on the m-grid
    pure function problem_kernel( self ) result(k)
        class(oracle_recon_problem), intent(in) :: self
        real(real64) :: k(2*self%n, 2*self%n, 2*self%n)
        k = self%khat
    end function problem_kernel

    ! the preconditioner's spectrum pi on the m-grid
    pure function problem_spectrum( self ) result(p)
        class(oracle_recon_problem), intent(in) :: self
        real(real64) :: p(2*self%n, 2*self%n, 2*self%n)
        p = self%pre
    end function problem_spectrum

    ! the ridge lambda
    pure function problem_ridge( self ) result(lambda)
        class(oracle_recon_problem), intent(in) :: self
        real(real64) :: lambda
        lambda = self%lambda
    end function problem_ridge

    ! the solve's start from a shipped volume: x / window where the window is at least its floor, else zero
    pure function problem_start( self, x ) result(u)
        class(oracle_recon_problem), intent(in) :: self
        real(real64),                intent(in) :: x(:)
        real(real64) :: u(size(x)), w(size(x))
        w = reshape(self%pwin, [size(x)])
        u = 0._real64
        where( w >= START_FLOOR ) u = x / w
    end function problem_start

    ! the volume shipped: the soft window times the solution, applied once
    pure function problem_ship( self, u ) result(x)
        class(oracle_recon_problem), intent(in) :: self
        real(real64),                intent(in) :: u(:)
        real(real64) :: x(size(u))
        x = reshape(self%pwin, [size(u)]) * u
    end function problem_ship

    ! y = A x, or (A + shift I) x from application `first` on; the applications are counted
    subroutine dense_apply( self, x, y )
        class(dense_system), intent(inout) :: self
        real(real64),        intent(in)    :: x(:)
        real(real64),        intent(out)   :: y(:)
        self%napply = self%napply + 1
        y           = matmul(self%a, x)
        if( self%napply >= self%first ) y = y + self%shift * x
    end subroutine dense_apply

    ! z = B x
    subroutine dense_precond( self, x, y )
        class(dense_system), intent(inout) :: self
        real(real64),        intent(in)    :: x(:)
        real(real64),        intent(out)   :: y(:)
        y = matmul(self%b, x)
    end subroutine dense_precond

    ! the signed index -m/2 .. m/2 - 1 stored at position i of an m-grid
    pure function signed_index( i, m ) result(g)
        integer, intent(in) :: i, m
        integer :: g
        g = i - 1
        if( g >= m / 2 ) g = g - m
    end function signed_index

    ! the radii of the soft window in a box of n: the outer radius, the width of the edge, the inner radius; the
    ! outer radius is half the rounded length in integer arithmetic, so an odd length loses its half
    pure subroutine window_radii( n, mskrad, maxrad, width, r0 )
        integer,      intent(in)  :: n
        real(real64), intent(in)  :: mskrad
        real(real64), intent(out) :: maxrad, width, r0
        maxrad = real(min(nint(2._real64 * (mskrad + EDGE_WIDTH)), n) / 2, real64)
        width  = 2._real64 * (maxrad - mskrad)
        r0     = maxrad - width
    end subroutine window_radii

    ! the soft window on the n-cube, r the distance from voxel n/2 + 1: zero from the outer radius on, one up
    ! to the inner radius, a raised cosine between; one everywhere when the mask radius is not positive
    pure function soft_window( n, mskrad ) result(win)
        integer,      intent(in) :: n
        real(real64), intent(in) :: mskrad
        real(real64) :: win(n, n, n), maxrad, width, r0, r
        integer      :: i1, i2, i3
        win = 1._real64
        if( .not. (mskrad > 0._real64) ) return
        call window_radii(n, mskrad, maxrad, width, r0)
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    r = sqrt(real(sum(([i1, i2, i3] - 1 - n / 2)**2), real64))
                    if( r >= maxrad )then
                        win(i1, i2, i3) = 0._real64
                    else if( r > r0 )then
                        win(i1, i2, i3) = (cos(PI * (r - r0) / width) + 1._real64) / 2._real64
                    endif
                end do
            end do
        end do
    end function soft_window

    ! whether a stored voxel of squared radius q2 enters the ridge's mean: |q| <= n and ceiling(|q| / 2) within
    ! its shells
    pure function in_ridge_set( q2, n ) result(in)
        integer, intent(in) :: q2, n
        logical :: in
        in = q2 <= n * n .and. ceiling(sqrt(real(q2, real64)) / 2._real64) <= RIDGE_SHELLS
    end function in_ridge_set

    ! 1 / e, and zero where |e| is at most the kernel's floor
    elemental function kernel_reciprocal( e ) result(r)
        real(real64), intent(in) :: e
        real(real64) :: r
        r = 0._real64
        if( abs(e) > KERNEL_FLOOR ) r = 1._real64 / e
    end function kernel_reciprocal

    ! the preconditioner's spectrum on the packed half: on a shell s = nint(|q|) <= n, with mu the mean of the
    ! shell's positive densities and d = max(D, 0), 1 / (d + PRE_FLOOR mu) where d >= PRE_KEEP mu, else zero;
    ! zero beyond n and on a shell without a positive density
    pure function precond_half( dens, n ) result(pre)
        real(real64), intent(in) :: dens(:,:,:)
        integer,      intent(in) :: n
        real(real64) :: pre(size(dens, 1), size(dens, 2), size(dens, 3))
        real(real64) :: total(0:n), mu(0:n), d
        integer      :: cnt(0:n), m, i1, i2, i3, s, pass
        m     = size(dens, 2)
        total = 0._real64
        cnt   = 0
        mu    = 0._real64
        pre   = 0._real64
        do pass = 1, 2
            do i3 = 1, m
                do i2 = 1, m
                    do i1 = 1, m / 2 + 1
                        s = nint(sqrt(real((i1 - 1)**2 + signed_index(i2, m)**2 + signed_index(i3, m)**2, real64)))
                        if( s > n ) cycle
                        if( pass == 1 )then
                            if( dens(i1, i2, i3) > 0._real64 )then
                                total(s) = total(s) + dens(i1, i2, i3)
                                cnt(s)   = cnt(s) + 1
                            endif
                        else if( mu(s) > 0._real64 )then
                            d = max(dens(i1, i2, i3), 0._real64)
                            if( d >= PRE_KEEP * mu(s) ) pre(i1, i2, i3) = 1._real64 / (d + PRE_FLOOR * mu(s))
                        endif
                    end do
                end do
            end do
            if( pass == 1 )then
                where( cnt > 0 ) mu = total / real(cnt, real64)
            endif
        end do
    end function precond_half

    ! the checks against the first oracles' scatter, explicit matrices, closed forms, counts and direct
    ! solutions, as named largest errors and their limits; the limit of the solve at the reconstruction's rtol
    ! is computed from the support block's condition number
    subroutine oracle_recon_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        limits = CHECK_LIMITS
        errors = 0._real64
        call check_lattice(N_SMALL, 1, errors(1:5))
        call check_lattice(N_LARGE, 2, errors(1:5))
        call check_mask(errors(6))
        call check_kernel(errors(7:8))
        call check_operators(errors(9:13))
        call check_spectrum(errors(12))
        call check_rhs(errors)
        call check_window_rules(errors(15))
        call check_solves(errors(16:19), limits(ICHECK_RTOL))
        call check_large(errors)
        call check_stops(errors(20))
        call check_recompute(errors(21))
    end subroutine oracle_recon_selfcheck

    ! the three fixture planes on a lattice, and the system of its packed density with the box's mask radius and
    ! the relative ridge
    subroutine fixture( n, lat, prob )
        integer,                    intent(in)    :: n
        type(oracle_recon_lattice), intent(inout) :: lat
        type(oracle_recon_problem), intent(inout) :: prob
        type(oracle_grid_plane) :: plane
        integer                 :: ip
        call lat%new(n)
        do ip = 1, 3
            call plane%new(ip, n)
            call lat%insert(plane)
            call plane%kill()
        end do
        call prob%new(lat%packed_density(), MSKRAD(merge(1, 2, n == N_SMALL)), LAMBDA_REL, .true.)
    end subroutine fixture

    ! the lattice in a box of n, per plane: the accumulators against 8 times the first oracles' scatter on the
    ! voxels read, and on all once the skipped windows leave the scatter; against the explicit matrix; the voxels
    ! touched at unit data. Then the packing and its two self-mated planes
    subroutine check_lattice( n, ibox, err )
        integer,      intent(in)    :: n, ibox
        real(real64), intent(inout) :: err(5)
        type(oracle_grid_plane)      :: plane
        type(oracle_recon_lattice)   :: three, one
        real(real64),    allocatable :: t(:,:), d(:), g(:,:), tc(:,:), s2(:,:), den(:,:,:), pd(:,:,:), ones(:,:)
        complex(real64), allocatable :: a(:), y(:,:), acc(:,:,:), sc(:,:,:), sk(:,:,:), sd(:,:,:), pk(:,:,:), fold(:,:,:)
        logical,         allocatable :: keep(:)
        real(real64)                 :: phi, omega, c, rot(3, 3)
        integer                      :: m, nyq, npix, ip, p, h, k, nbad, i1, i2, i3, hw, j2, j3
        m    = 2 * n
        nyq  = n / 2
        npix = (n + 1)**2
        c    = real(n - 1, real64) / real(n, real64)
        rot  = reshape([c, sqrt(1._real64 - c**2), 0._real64, -sqrt(1._real64 - c**2), c, 0._real64, 0._real64, 0._real64, &
                        1._real64], [3, 3])
        allocate(t(3, npix), d(npix), a(npix), keep(npix), g(npix, m**3), tc(n+1, n+1), s2(n+1, n+1), y(n+1, n+1), &
                 acc(m, m, m), den(m, m, m), sc(m, m, m), sk(m, m, m), sd(m, m, m), pk(m/2+1, m, m), pd(m/2+1, m, m), &
                 fold(m/2+1, m, m), ones(n+1, n+1))
        nbad = 0
        ones = 1._real64
        call three%new(n)
        do ip = 1, 4
            if( ip <= 3 )then
                call plane%new(ip, n)
                call three%insert(plane)
            else
                ! a fourth plane, turned about z so that pixel (-n/2, 0) lies at -m/2 + 1 exactly: its window
                ! reaches the plane -m/2 and is the last one kept
                call plane%new(1, n)
                call plane%set_pose(rot, 0.75_real64, [0.25_real64, -0.5_real64])
            endif
            call one%new(n)
            call one%insert(plane)
            acc   = one%numerator()
            den   = one%density()
            y     = plane%observed()
            tc    = plane%ctf()
            s2    = plane%variance()
            omega = plane%weight()
            ! each pixel's coordinate and data typed here, and whether its window is kept: one whose first
            ! coordinate lies in (-m/2 + 3/2, -3/2] has its three taps strictly between -m/2 and 0
            p    = 0
            a    = CZERO
            d    = 0._real64
            keep = .false.
            do k = -nyq, nyq
                do h = -nyq, nyq
                    p       = p + 1
                    t(:, p) = 2._real64 * matmul(real([h, k, 0], real64), plane%rotation())
                    if( h * h + k * k > nyq * nyq ) cycle
                    phi     = TWOPI * dot_product(real([h, k], real64), plane%shift()) / real(n, real64)
                    a(p)    = tc(h+nyq+1, k+nyq+1) * exp(cmplx(0._real64, -phi, real64)) * omega * y(h+nyq+1, k+nyq+1) / &
                              s2(h+nyq+1, k+nyq+1)
                    d(p)    = tc(h+nyq+1, k+nyq+1)**2 * omega / s2(h+nyq+1, k+nyq+1)
                    keep(p) = .not. (t(1, p) > -real(m / 2, real64) + 1.5_real64 .and. t(1, p) <= -1.5_real64)
                end do
            end do
            sc = oracle_proj_scatter(t, a, m)
            sd = oracle_proj_scatter(t, cmplx(d, 0._real64, real64), m)
            sk = oracle_proj_scatter(t, merge(CZERO, a, keep), m)
            err(2) = max(err(2), oracle_rel_error(oracle_flat(acc(1:m/2+1, :,:)), 8._real64 * oracle_flat(sc(1:m/2+1, :,:))), &
                         oracle_rel_error(oracle_flat(cmplx(den(1:m/2+1, :,:), 0._real64, real64)), &
                                          oracle_flat(sd(1:m/2+1, :,:))), &
                         oracle_rel_error(oracle_flat(acc), 8._real64 * oracle_flat(sc - sk)))
            ! the explicit matrix of the periodic grid, the skipped pixels' columns left out
            g      = oracle_proj_matrix(t, m)
            err(3) = max(err(3), oracle_rel_error(oracle_flat(acc), 8._real64 * matmul(merge(a, CZERO, keep), g)), &
                         oracle_rel_error(oracle_flat(cmplx(den, 0._real64, real64)), &
                                          cmplx(matmul(merge(d, 0._real64, keep), g), 0._real64, real64)))
            call one%kill()
            ! unit data: the voxels touched, those of them read, and numerator = 8 density
            call plane%set_data(cmplx(ones, 0._real64, real64), ones, ones)
            call plane%set_pose(plane%rotation(), 1._real64, [0._real64, 0._real64])
            call one%new(n)
            call one%insert(plane)
            den = one%density()
            if( ip <= 3 )then
                if( count(den > 0._real64) /= TOUCHED(min(ip, 3), ibox) ) nbad = nbad + 1
                if( count(den(1:m/2+1, :,:) > 0._real64) /= TOUCH_READ(min(ip, 3), ibox) ) nbad = nbad + 1
            endif
            err(2) = max(err(2), oracle_rel_error(oracle_flat(one%numerator()), &
                                                  oracle_flat(cmplx(8._real64 * den, 0._real64, real64))))
            call one%kill()
            call plane%kill()
        end do
        err(1) = err(1) + real(nbad, real64)
        ! the packing by value: plane h of the half is the accumulator's plane at the signed index h, and h = m/2
        ! the one at -m/2; it is not the first oracles' fold, which adds the mates
        acc  = three%numerator()
        den  = three%density()
        pk   = three%packed_numerator()
        pd   = three%packed_density()
        fold = oracle_proj_fold(acc)
        nbad = 0
        do i3 = 1, m
            do i2 = 1, m
                do i1 = 1, m / 2 + 1
                    hw = i1 - 1
                    if( hw == m / 2 ) hw = -m / 2
                    if( .not. (abs(pk(i1, i2, i3) - acc(1+modulo(hw, m), i2, i3)) <= 0._real64) ) nbad = nbad + 1
                    if( .not. (abs(pd(i1, i2, i3) - den(1+modulo(hw, m), i2, i3)) <= 0._real64) ) nbad = nbad + 1
                end do
            end do
        end do
        if( count(abs(pk - fold) > 0._real64) == 0 ) nbad = nbad + 1
        err(4) = err(4) + real(nbad, real64)
        ! the planes h = 0 and m/2 of the packed arrays are halves of a Hermitian array: the density even, the
        ! numerator the conjugate of itself at the mate
        do i1 = 1, m / 2 + 1, m / 2
            do i3 = 1, m
                do i2 = 1, m
                    j2     = 1 + modulo(1 - i2, m)
                    j3     = 1 + modulo(1 - i3, m)
                    err(5) = max(err(5), abs(pd(i1, i2, i3) - pd(i1, j2, j3)) / maxval(pd), &
                                 abs(pk(i1, i2, i3) - conjg(pk(i1, j2, j3))) / nan_maxval(abs(pk)))
                end do
            end do
        end do
        ! max may pass over a NaN, so the packed arrays are tested first
        if( .not. (all(ieee_is_finite(pd)) .and. all(ieee_is_finite(real(pk))) .and. all(ieee_is_finite(aimag(pk)))) )then
            err(5) = ieee_value(err(5), ieee_positive_inf)
        endif
        err(5) = oracle_finite_or_inf(err(5))
        call three%kill()
    end subroutine check_lattice

    ! the mask and the soft window in both boxes: the mask against the integer points inside the radius n/2 and
    ! their count; at n = 4 the window against its four values typed from the raised cosine with inner radius
    ! 1/2 and width 3/2; no support without a radius; the radii where the rounded branch decides
    subroutine check_mask( err )
        real(real64), intent(inout) :: err
        type(oracle_recon_lattice) :: lat
        type(oracle_recon_problem) :: prob
        real(real64), allocatable  :: p(:,:,:), w(:,:,:)
        real(real64)               :: typed(0:3), maxrad, width, r0
        integer                    :: ibox, n, nbad, i1, i2, i3, r2
        nbad  = 0
        typed = [1._real64, 0.75_real64, (cos(PI * (sqrt(2._real64) - 0.5_real64) / 1.5_real64) + 1._real64) / 2._real64, &
                 (cos(PI * (sqrt(3._real64) - 0.5_real64) / 1.5_real64) + 1._real64) / 2._real64]
        do ibox = 1, 2
            n = merge(N_SMALL, N_LARGE, ibox == 1)
            allocate(p(n, n, n), w(n, n, n))
            call fixture(n, lat, prob)
            p = prob%support()
            w = prob%window()
            if( count(p > 0._real64) /= IN_MASK(ibox) ) nbad = nbad + 1
            if( count(w >= 0.1_real64) /= IN_START(ibox) ) nbad = nbad + 1
            do i3 = 1, n
                do i2 = 1, n
                    do i1 = 1, n
                        r2 = sum(([i1, i2, i3] - 1 - n / 2)**2)
                        if( (4 * r2 < n * n) .neqv. (abs(p(i1, i2, i3) - 1._real64) <= 0._real64) ) nbad = nbad + 1
                        if( 4 * r2 >= n * n .and. .not. (abs(p(i1, i2, i3)) <= 0._real64) ) nbad = nbad + 1
                        if( ibox == 1 .and. r2 <= 3 )then
                            if( .not. (abs(w(i1, i2, i3) - typed(r2)) <= TOL_MATRIX) ) nbad = nbad + 1
                        endif
                        if( 4 * r2 >= n * n .and. .not. (abs(w(i1, i2, i3)) <= 0._real64) ) nbad = nbad + 1
                    end do
                end do
            end do
            ! without a radius there is no support: the mask and the window are one everywhere
            call prob%new(lat%packed_density(), 0._real64, LAMBDA_REL, .true.)
            p = prob%support()
            w = prob%window()
            nbad = nbad + count(.not. (abs(p - 1._real64) <= 0._real64)) + count(.not. (abs(w - 1._real64) <= 0._real64))
            call prob%kill()
            call lat%kill()
            deallocate(p, w)
        end do
        ! the radii: in a box of 32 the rounded 2 (mskrad + 6) decides, 22 and 23 on either side of 5.25, and
        ! both halve to 11; a large radius is cut at the box
        call window_radii(32, 5._real64, maxrad, width, r0)
        if( .not. (abs(maxrad - 11._real64) + abs(width - 12._real64) + abs(r0 + 1._real64) <= TOL_MATRIX) ) nbad = nbad + 1
        call window_radii(32, 5.3_real64, maxrad, width, r0)
        if( .not. (abs(maxrad - 11._real64) + abs(width - 11.4_real64) + abs(r0 + 0.4_real64) <= TOL_MATRIX) ) nbad = nbad + 1
        call window_radii(32, 20._real64, maxrad, width, r0)
        if( .not. (abs(maxrad - 16._real64) <= TOL_MATRIX) ) nbad = nbad + 1
        err = err + real(nbad, real64)
    end subroutine check_mask

    ! the kernel spectrum against cosine sums over the packed half and over the voxels, and its cut recovered
    ! from the kernel of a unit density; the guarded reciprocal on typed values. Then the ridge against the mean
    ! over a set typed in integers, its count, a ridge given, and the set's rule where ceiling(|q| / 2) decides
    subroutine check_kernel( err )
        real(real64), intent(inout) :: err(2)
        type(oracle_recon_lattice) :: lat
        type(oracle_recon_problem) :: prob
        real(real64), allocatable  :: dens(:,:,:), khat(:,:,:), psf(:,:,:), drec(:,:,:), got(:), kref(:)
        real(real64)               :: w(3), em(2*N_LARGE), mu, total, e(4), ref(4)
        integer                    :: tap(3), ibox, n, m, i, i1, i2, i3, j1, j2, j3, nk, nr, cnt, q2, step, ng
        call oracle_proj_stencil(0._real64, tap, w)
        nk = 0
        nr = 0
        do ibox = 1, 2
            n    = merge(N_SMALL, N_LARGE, ibox == 1)
            m    = 2 * n
            step = merge(1, 3, ibox == 1)
            allocate(dens(m/2+1, m, m), khat(m, m, m), psf(m, m, m), drec(m, m, m), got(m**3), kref(m**3))
            call fixture(n, lat, prob)
            dens = lat%packed_density()
            do i = 1, m
                em(i) = w(2) + 2._real64 * w(1) * cos(TWOPI * real(i - 1, real64) / real(m, real64))
            end do
            ! the ridge: 64 lambda_rel times the mean of the density over |q|**2 <= n**2 and |q|**2 <= 144
            total = 0._real64
            cnt   = 0
            do i3 = 1, m
                do i2 = 1, m
                    do i1 = 1, m / 2 + 1
                        q2 = (i1 - 1)**2 + signed_index(i2, m)**2 + signed_index(i3, m)**2
                        if( q2 <= n * n .and. q2 <= 144 )then
                            total = total + dens(i1, i2, i3)
                            cnt   = cnt + 1
                        endif
                    end do
                end do
            end do
            if( cnt /= IN_RIDGE(ibox) ) nr = nr + 1
            err(2) = max(err(2), oracle_finite_or_inf(abs(prob%ridge() - 64._real64 * 0.05_real64 * total / real(cnt, real64)) / &
                                                      prob%ridge()))
            ! a ridge given is kept as it is
            call prob%new(dens, MSKRAD(ibox), 0.375_real64, .false.)
            err(2) = max(err(2), abs(prob%ridge() - 0.375_real64))
            ! at n = 4 no voxel lies beyond the cut; at n = 8 the density is raised by one so that the cut
            ! decides, and the reference is taken at every third index
            if( ibox == 2 ) dens = dens + 1._real64
            call prob%new(dens, MSKRAD(ibox), LAMBDA_REL, .true.)
            khat = prob%kernel()
            ! the point spread by cosine sums over the stored voxels inside the cut, each once on the planes
            ! h = 0 and m/2 and twice between, divided by the window's transform; then 64 times its cosine sum
            do i3 = 1, m
                do i2 = 1, m
                    do i1 = 1, m
                        psf(i1, i2, i3) = 0._real64
                        do j3 = 1, m
                            do j2 = 1, m
                                do j1 = 1, m / 2 + 1
                                    q2 = (j1 - 1)**2 + signed_index(j2, m)**2 + signed_index(j3, m)**2
                                    ! nint(|q|) <= n + 3 in integers: 4 |q|**2 < (2 n + 7)**2
                                    if( 4 * q2 >= (2 * n + 7)**2 ) cycle
                                    mu = merge(1._real64, 2._real64, j1 == 1 .or. j1 == m / 2 + 1)
                                    psf(i1, i2, i3) = psf(i1, i2, i3) + mu * dens(j1, j2, j3) * &
                                        cos(TWOPI * real((j1 - 1) * (i1 - 1) + (j2 - 1) * (i2 - 1) + (j3 - 1) * (i3 - 1), &
                                                         real64) / real(m, real64))
                                end do
                            end do
                        end do
                        psf(i1, i2, i3) = psf(i1, i2, i3) / (real(m, real64)**3 * em(i1) * em(i2) * em(i3))
                    end do
                end do
            end do
            ng = 0
            do i3 = 1, m, step
                do i2 = 1, m, step
                    do i1 = 1, m, step
                        ng       = ng + 1
                        got(ng)  = khat(i1, i2, i3)
                        kref(ng) = 0._real64
                        do j3 = 1, m
                            do j2 = 1, m
                                do j1 = 1, m
                                    kref(ng) = kref(ng) + 64._real64 * psf(j1, j2, j3) * &
                                        cos(TWOPI * real((j1 - 1) * (i1 - 1) + (j2 - 1) * (i2 - 1) + (j3 - 1) * (i3 - 1), &
                                                         real64) / real(m, real64))
                                end do
                            end do
                        end do
                    end do
                end do
            end do
            err(1) = max(err(1), matrix_error(reshape(got(1:ng), [ng, 1]), reshape(kref(1:ng), [ng, 1])))
            ! a unit density: undoing the kernel's steps recovers the density the cut kept, one or zero on the
            ! full lattice
            dens = 1._real64
            call prob%new(dens, MSKRAD(ibox), LAMBDA_REL, .true.)
            psf = real(oracle_idft_3d(cmplx(prob%kernel() / 64._real64, 0._real64, real64)))
            do i3 = 1, m
                do i2 = 1, m
                    do i1 = 1, m
                        psf(i1, i2, i3) = psf(i1, i2, i3) * em(i1) * em(i2) * em(i3)
                    end do
                end do
            end do
            drec = real(oracle_dft_3d(cmplx(psf, 0._real64, real64)))
            if( count(drec > 0.5_real64) /= KEPT_FULL(ibox) ) nk = nk + 1
            err(1) = max(err(1), oracle_finite_or_inf(nan_maxval(abs(drec - anint(drec)))))
            call prob%kill()
            call lat%kill()
            deallocate(dens, khat, psf, drec, got, kref)
        end do
        e   = [1.e-8_real64, 1.1e-8_real64, -1.e-9_real64, 0.5_real64]
        ref = [0._real64, 1._real64 / 1.1e-8_real64, 0._real64, 2._real64]
        nk  = nk + count(.not. (abs(kernel_reciprocal(e) - ref) <= TOL_MATRIX * abs(ref)))
        ! the ridge's set where its second rule decides: in a box of 16, |q| = 12 is in and |q|**2 = 145 out
        if( .not. in_ridge_set(144, 16) ) nr = nr + 1
        if( in_ridge_set(145, 16) ) nr = nr + 1
        if( in_ridge_set(256, 16) ) nr = nr + 1
        if( .not. in_ridge_set(16, 4) ) nr = nr + 1
        if( in_ridge_set(17, 4) ) nr = nr + 1
        err(1) = max(err(1), real(nk, real64))
        err(2) = max(err(2), real(nr, real64))
    end subroutine check_kernel

    ! the operator and the preconditioner at n = 4, column by column, against their dense matrices; their
    ! symmetry, the preconditioner's on the support; outside the mask the operator's rows and columns are zero,
    ! and its support block is positive definite
    subroutine check_operators( err )
        real(real64), intent(inout) :: err(5)
        type(oracle_recon_lattice) :: lat
        type(oracle_recon_problem) :: prob
        real(real64), allocatable  :: hd(:,:), pd(:,:), ho(:,:), po(:,:), e(:), hs(:,:), xs(:), ev(:)
        real(real64)               :: minpivot
        integer,      allocatable  :: idx(:)
        integer                    :: n, nn, u, nbad
        n  = N_SMALL
        nn = n**3
        allocate(hd(nn, nn), pd(nn, nn), ho(nn, nn), po(nn, nn), e(nn))
        call fixture(n, lat, prob)
        call dense_matrices(prob%kernel(), reference_spectrum(lat%packed_density(), n), prob%ridge(), hd, pd)
        do u = 1, nn
            e    = 0._real64
            e(u) = 1._real64
            call prob%apply(e, ho(:, u))
            call prob%precond(e, po(:, u))
        end do
        err(1) = max(err(1), matrix_error(ho, hd))
        err(2) = max(err(2), matrix_error(ho, transpose(ho)))
        err(4) = max(err(4), matrix_error(po, pd))
        ! the support: the unknowns at integer points inside the radius n/2
        idx  = support_index(n)
        nbad = 0
        do u = 1, nn
            if( any(idx == u) ) cycle
            nbad  = nbad + count(abs(ho(:, u)) > 0._real64) + count(abs(ho(u, :)) > 0._real64)
            ! the preconditioner has the mask on its left only: its columns outside the support are set aside
            po(:, u) = 0._real64
        end do
        err(5) = max(err(5), matrix_error(po, transpose(po)))
        ! positive definite on the support: every Cholesky pivot and every eigenvalue positive, the eigenvalues
        ! adding up to the trace and their squares to the squared norm
        allocate(hs(size(idx), size(idx)), xs(size(idx)), ev(size(idx)))
        hs = hd(idx, idx)
        call oracle_pcg_cholesky(hs, hs(:, 1), xs, minpivot)
        if( .not. (minpivot > 0._real64) ) nbad = nbad + 1
        ev = symmetric_eigenvalues(hs)
        if( .not. (minval(ev) > 0._real64) ) nbad = nbad + 1
        if( .not. (abs(sum(ev) - sum([(hs(u, u), u=1, size(idx))])) <= 1.e-10_real64 * sum(ev)) ) nbad = nbad + 1
        if( .not. (abs(sum(ev**2) - sum(hs**2)) <= 1.e-10_real64 * sum(hs**2)) ) nbad = nbad + 1
        if( size(idx) /= IN_MASK(1) ) nbad = nbad + 1
        err(3) = err(3) + real(nbad, real64)
        call prob%kill()
        call lat%kill()
    end subroutine check_operators

    ! the preconditioner's spectrum itself, in both boxes: the fixture's against the reference; zero and finite
    ! on a density of zeros, where no shell has a mean; and on a density of -1 with one voxel of 2 at (2, 0, 0),
    ! whose shell then has the mean 2, it is 1 / 2.02 at that voxel and at its mate and zero elsewhere
    subroutine check_spectrum( err )
        real(real64), intent(inout) :: err
        type(oracle_recon_lattice) :: lat
        type(oracle_recon_problem) :: prob
        real(real64), allocatable  :: dens(:,:,:), pre(:,:,:)
        integer                    :: ibox, n, m, nbad
        nbad = 0
        do ibox = 1, 2
            n = merge(N_SMALL, N_LARGE, ibox == 1)
            m = 2 * n
            allocate(dens(m/2+1, m, m), pre(m, m, m))
            call fixture(n, lat, prob)
            dens = lat%packed_density()
            pre  = prob%spectrum()
            err  = max(err, matrix_error(reshape(pre, [m**3, 1]), reshape(reference_spectrum(dens, n), [m**3, 1])))
            dens = 0._real64
            call prob%new(dens, MSKRAD(ibox), 1._real64, .false.)
            pre  = prob%spectrum()
            nbad = nbad + count(.not. (abs(pre) <= 0._real64))
            dens          = -1._real64
            dens(3, 1, 1) = 2._real64
            call prob%new(dens, MSKRAD(ibox), 1._real64, .false.)
            pre = prob%spectrum()
            if( count(.not. (abs(pre) <= 0._real64)) /= 2 ) nbad = nbad + 1
            err = max(err, oracle_finite_or_inf(abs(pre(3, 1, 1) - 1._real64 / 2.02_real64)), &
                      oracle_finite_or_inf(abs(pre(m-1, 1, 1) - 1._real64 / 2.02_real64)))
            call prob%kill()
            call lat%kill()
            deallocate(dens, pre)
        end do
        err = max(err, real(nbad, real64))
    end subroutine check_spectrum

    ! the right-hand side in both boxes against the sum its packed numerator stands for, each stored voxel once
    ! on the planes h = 0 and m/2 and twice between; then one on-lattice sample at n = 4 by its closed form, with
    ! the hand values of its accumulators
    subroutine check_rhs( err )
        real(real64), intent(inout) :: err(:)
        type(oracle_recon_lattice)   :: lat, single
        type(oracle_recon_problem)   :: prob
        type(oracle_grid_plane)      :: plane
        complex(real64), allocatable :: pk(:,:,:), y(:,:), acc(:,:,:)
        real(real64),    allocatable :: ref(:), ones(:,:), den(:,:,:)
        complex(real64)              :: a
        real(real64)                 :: w(3), x(3), mu, ang
        integer                      :: tap(3), ibox, n, m, i1, i2, i3, j1, j2, j3, u
        call oracle_proj_stencil(0._real64, tap, w)
        do ibox = 1, 2
            n = merge(N_SMALL, N_LARGE, ibox == 1)
            m = 2 * n
            allocate(pk(m/2+1, m, m), ref(n**3))
            call fixture(n, lat, prob)
            pk = lat%packed_numerator()
            u  = 0
            do i3 = 1, n
                do i2 = 1, n
                    do i1 = 1, n
                        u      = u + 1
                        x      = real([i1, i2, i3] - 1 - n / 2, real64)
                        ref(u) = 0._real64
                        if( .not. (sum(x**2) < real(n * n, real64) / 4._real64) ) cycle
                        do j3 = 1, m
                            do j2 = 1, m
                                do j1 = 1, m / 2 + 1
                                    mu     = merge(1._real64, 2._real64, j1 == 1 .or. j1 == m / 2 + 1)
                                    ang    = TWOPI * dot_product(real([j1 - 1, signed_index(j2, m), signed_index(j3, m)], &
                                                                      real64), x) / real(m, real64)
                                    ref(u) = ref(u) + mu * real(pk(j1, j2, j3) * exp(cmplx(0._real64, ang, real64)))
                                end do
                            end do
                        end do
                        ref(u) = ref(u) / product(w(2) + 2._real64 * w(1) * cos(TWOPI * x / real(m, real64)))
                    end do
                end do
            end do
            err(14) = max(err(14), matrix_error(reshape(prob%rhs(pk), [n**3, 1]), reshape(ref, [n**3, 1])))
            if( ibox == 1 )then
                ! pixel (1, -1) of an identity plane with t = 0.8, s2 = 1.6, omega = 1.25 and the shift (1/4, -1/2):
                ! phi = 3 pi / 8, the numerator's factor 8 * 0.8 * 1.25 / 1.6 = 5, the density's 0.5
                allocate(y(n+1, n+1), ones(n+1, n+1), acc(m, m, m), den(m, m, m))
                ones            = 1._real64
                y               = CZERO
                y(n/2+2, n/2)   = (0.75_real64, -1.25_real64)
                y(n/2, n/2+2)   = conjg(y(n/2+2, n/2))
                call plane%new(1, n)
                call plane%set_data(y, 0.8_real64 * ones, 1.6_real64 * ones)
                call plane%set_pose(oracle_proj_rotation(1), 1.25_real64, [0.25_real64, -0.5_real64])
                call single%new(n)
                call single%insert(plane)
                a       = 5._real64 * exp(cmplx(0._real64, -3._real64 * PI / 8._real64, real64)) * y(n/2+2, n/2)
                ! its taps are h = 1 .. 3 and its mate's window is skipped: the voxel (2, -2, 0) holds w0**3 a and
                ! w0**3 / 2, and b = P 2 Re[a exp(2 pi i (2 x1 - 2 x2) / m)]
                acc     = single%numerator()
                den     = single%density()
                err(2)  = max(err(2), oracle_finite_or_inf(abs(acc(3, m-1, 1) - w(2)**3 * a) / abs(a)), &
                              oracle_finite_or_inf(abs(den(3, m-1, 1) - 0.5_real64 * w(2)**3)))
                u = 0
                do i3 = 1, n
                    do i2 = 1, n
                        do i1 = 1, n
                            u      = u + 1
                            x      = real([i1, i2, i3] - 1 - n / 2, real64)
                            ref(u) = 0._real64
                            if( sum(x**2) < real(n * n, real64) / 4._real64 )then
                                ang    = TWOPI * (2._real64 * x(1) - 2._real64 * x(2)) / real(m, real64)
                                ref(u) = 2._real64 * real(a * exp(cmplx(0._real64, ang, real64)))
                            endif
                        end do
                    end do
                end do
                err(14) = max(err(14), matrix_error(reshape(prob%rhs(single%packed_numerator()), [n**3, 1]), &
                                                    reshape(ref, [n**3, 1])))
                call single%kill()
                call plane%kill()
                deallocate(y, ones, acc, den)
            endif
            call prob%kill()
            call lat%kill()
            deallocate(pk, ref)
        end do
    end subroutine check_rhs

    ! the start and the exit at n = 4, where the eight corners of the mask lie under the start's floor: the
    ! shipped volume is the typed window times the solution; a start is divided where the window is at least
    ! 0.1 and zero elsewhere, so it undoes the shipping on those 19 voxels only
    subroutine check_window_rules( err )
        real(real64), intent(inout) :: err
        type(oracle_recon_lattice) :: lat
        type(oracle_recon_problem) :: prob
        real(real64)               :: u(N_SMALL**3), x(N_SMALL**3), s(N_SMALL**3), w(N_SMALL**3), typed(0:3)
        integer                    :: n, i1, i2, i3, r2, j, nbad
        n     = N_SMALL
        typed = [1._real64, 0.75_real64, (cos(PI * (sqrt(2._real64) - 0.5_real64) / 1.5_real64) + 1._real64) / 2._real64, &
                 (cos(PI * (sqrt(3._real64) - 0.5_real64) / 1.5_real64) + 1._real64) / 2._real64]
        call fixture(n, lat, prob)
        j = 0
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    j    = j + 1
                    r2   = sum(([i1, i2, i3] - 1 - n / 2)**2)
                    w(j) = 0._real64
                    if( r2 <= 3 ) w(j) = typed(r2)
                    u(j) = real(modulo(3 * i1 + 7 * i2 + 2 * i3, 13) - 6, real64) / 6._real64 + 2._real64
                end do
            end do
        end do
        x    = prob%ship(u)
        s    = prob%start(x)
        err  = max(err, matrix_error(reshape(x, [n**3, 1]), reshape(w * u, [n**3, 1])), &
                   matrix_error(reshape(s, [n**3, 1]), reshape(merge(u, 0._real64, w >= 0.1_real64), [n**3, 1])))
        nbad = 0
        if( count(abs(s) > 0._real64) /= IN_START(1) ) nbad = nbad + 1
        if( count(abs(x) > 0._real64) /= IN_MASK(1) ) nbad = nbad + 1
        err  = max(err, real(nbad, real64))
        call prob%kill()
        call lat%kill()
    end subroutine check_window_rules

    ! the fixture's solves at n = 4 against the Cholesky solution on the support block of the dense matrix: at
    ! the reconstruction's rtol with the step test off, within 10 rtol cond; iterated to 1e-12; the residual the
    ! solve reports against the true one, which meets the tolerance; the reasons, and zeros outside the support
    subroutine check_solves( err, limit )
        real(real64), intent(inout) :: err(4)
        real(real64), intent(out)   :: limit
        type(oracle_recon_lattice) :: lat
        type(oracle_recon_problem) :: prob
        real(real64), allocatable  :: hd(:,:), pd(:,:), b(:), x(:), hs(:,:), xs(:), ev(:), hist(:)
        integer,      allocatable  :: idx(:)
        real(real64)               :: minpivot, res
        integer                    :: n, nn, info(2), nbad
        n  = N_SMALL
        nn = n**3
        allocate(hd(nn, nn), pd(nn, nn), b(nn), x(nn))
        call fixture(n, lat, prob)
        call dense_matrices(prob%kernel(), reference_spectrum(lat%packed_density(), n), prob%ridge(), hd, pd)
        b   = prob%rhs(lat%packed_numerator())
        idx = support_index(n)
        allocate(hs(size(idx), size(idx)), xs(size(idx)), ev(size(idx)))
        hs = hd(idx, idx)
        call oracle_pcg_cholesky(hs, b(idx), xs, minpivot)
        ev    = symmetric_eigenvalues(hs)
        limit = SOLVE_FACTOR * RTOL_RECON * maxval(ev) / minval(ev)
        nbad  = 0
        ! at the reconstruction's rtol, the step test off
        call prob%set_rules(RTOL_RECON, 0._real64, 4 * MAXITS_RECON)
        x = 0._real64
        call prob%solve(b, x, hist, info)
        err(1) = max(err(1), oracle_finite_or_inf(norm2(x(idx) - xs) / norm2(xs)))
        res    = norm2(b - matmul(hd, x)) / norm2(b)
        if( info(2) /= REASON_RTOL ) nbad = nbad + 1
        if( size(hist) == info(1) + 1 .and. info(1) > 0 )then
            err(3) = max(err(3), oracle_finite_or_inf(abs(hist(size(hist)) - res)), &
                         oracle_finite_or_inf(max(res - RTOL_RECON, 0._real64)), oracle_finite_or_inf(abs(hist(1) - 1._real64)))
        else
            nbad = nbad + 1
        endif
        nbad = nbad + count(abs(x) > 0._real64) - count(abs(x(idx)) > 0._real64)
        ! iterated to 1e-12
        call prob%set_rules(TOL_TIGHT, 0._real64, 20 * MAXITS_RECON)
        x = 0._real64
        call prob%solve(b, x, hist, info)
        err(2) = max(err(2), oracle_finite_or_inf(norm2(x(idx) - xs) / norm2(xs)))
        if( info(2) /= REASON_RTOL ) nbad = nbad + 1
        err(4) = err(4) + real(nbad, real64)
        call prob%kill()
        call lat%kill()
    end subroutine check_solves

    ! the box of 8, without dense matrices, on fixed vectors: <u, H v> = <H u, v>; nothing comes back outside the
    ! mask and H ignores what lies there; the preconditioner is symmetric on the support. Then the solve under
    ! the rules a system is born with, whatever stops it
    subroutine check_large( err )
        real(real64), intent(inout) :: err(:)
        type(oracle_recon_lattice) :: lat
        type(oracle_recon_problem) :: prob
        real(real64), allocatable  :: u(:), v(:), hu(:), hv(:), p(:), b(:), x(:), hist(:)
        real(real64)               :: res
        integer                    :: n, nn, info(2), nbad
        n  = N_LARGE
        nn = n**3
        allocate(u(nn), v(nn), hu(nn), hv(nn), p(nn), b(nn), x(nn))
        call fixture(n, lat, prob)
        p = reshape(prob%support(), [nn])
        u = fixed_vector(nn, 1)
        v = fixed_vector(nn, 2)
        call prob%apply(u, hu)
        call prob%apply(v, hv)
        err(10) = max(err(10), oracle_finite_or_inf(abs(sum(u * hv) - sum(hu * v)) / (norm2(u) * norm2(hv))))
        nbad    = count(abs(hu) > 0._real64 .and. .not. (p > 0._real64))
        call prob%apply((1._real64 - p) * u, hv)
        nbad    = nbad + count(abs(hv) > 0._real64)
        call prob%precond(p * u, hu)
        call prob%precond(p * v, hv)
        err(13) = max(err(13), oracle_finite_or_inf(abs(sum(p * u * hv) - sum(hu * p * v)) / (norm2(u) * norm2(hv))))
        nbad    = nbad + count(abs(hu) > 0._real64 .and. .not. (p > 0._real64))
        err(11) = err(11) + real(nbad, real64)
        ! the residual it reports is the true one, the history holds the start and one entry per iteration,
        ! and nothing is solved for outside the mask
        b       = prob%rhs(lat%packed_numerator())
        x       = 0._real64
        call prob%solve(b, x, hist, info)
        nbad = count(abs(x) > 0._real64 .and. .not. (p > 0._real64))
        if( info(2) < REASON_RTOL .or. info(2) > REASON_MAXITS .or. info(1) > MAXITS_RECON ) nbad = nbad + 1
        if( size(hist) == info(1) + 1 .and. info(1) > 0 )then
            call prob%apply(x, hu)
            res     = norm2(b - hu) / norm2(b)
            err(18) = max(err(18), oracle_finite_or_inf(abs(hist(size(hist)) - res)))
        else
            nbad = nbad + 1
        endif
        err(19) = err(19) + real(nbad, real64)
        call prob%kill()
        call lat%kill()
    end subroutine check_large

    ! every stop of the solve on three unknowns whose iterates are known in rationals: with diag(1, 2, 3), the
    ! identity as preconditioner and b = (1, 1, 1), the residuals are 1 / sqrt(6), sqrt(2) / 10 and 0, the steps
    ! 1, 0.408 and 0.125 of |x|, and x is (1/2, 1/2, 1/2), then (9/10, 3/5, 3/10), then (1, 1/2, 1/3)
    subroutine check_stops( err )
        real(real64), intent(inout) :: err
        type(dense_system)        :: sys, born
        real(real64), allocatable :: hist(:)
        real(real64)              :: b(3), x(3), x2(3), x3(3)
        integer                   :: info(2), nbad
        nbad = 0
        b    = 1._real64
        x2   = [0.9_real64, 0.6_real64, 0.3_real64]
        x3   = [1._real64, 0.5_real64, 1._real64 / 3._real64]
        ! rtol: three distinct eigenvalues are solved in three iterations; the history holds the start too
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0._real64, 50)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [3, REASON_RTOL]) + far(x, x3) + wrong([size(hist), sys%napply], [4, 3])
        if( size(hist) == 4 ) nbad = nbad + far(hist(1:3), [1._real64, 1._real64 / sqrt(6._real64), sqrt(2._real64) / 10._real64])
        ! rtol before xtol when both hold at iteration 3
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0.2_real64, 50)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [3, REASON_RTOL]) + far(x, x3)
        ! xtol: the step of iteration 2 is 0.408 of |x|, within 0.45; at 0.4 the solve goes on to iteration 3,
        ! where the residual stops it
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-30_real64, 0.45_real64, 50)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [2, REASON_XTOL]) + far(x, x2)
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0.4_real64, 50)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [3, REASON_RTOL]) + far(x, x3)
        ! an iterate smaller than the machine epsilon is measured against the epsilon: with a right-hand side
        ! of 1e-30 the first step, whose ratio to |x| is one, passes the step test
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-30_real64, 0.45_real64, 50)
        x = 0._real64
        call sys%solve(1.e-30_real64 * b, x, hist, info)
        nbad = nbad + wrong(info, [1, REASON_XTOL]) + far(x, 0.5e-30_real64 * b)
        ! maxits
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0._real64, 2)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [2, REASON_MAXITS]) + far(x, x2) + wrong([size(hist), sys%napply], [3, 2])
        ! a fixed number of iterations: with rtol at zero or below neither test is made
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(0._real64, 0.45_real64, 3)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [3, REASON_FIXED]) + far(x, x3)
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(-1._real64, 0.45_real64, 2)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [2, REASON_FIXED]) + far(x, x2)
        ! an indefinite product at once: the operator negated, the start as it was
        call dense_new(sys, [-1._real64, -2._real64, -3._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0._real64, 50)
        x = [0.5_real64, -0.25_real64, 2._real64]
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [0, REASON_INDEFINITE]) + count(abs(x - [0.5_real64, -0.25_real64, 2._real64]) > 0._real64) + &
               wrong([size(hist)], [1])
        ! an indefinite product at iteration 2: with diag(1, 2, -1) the first step reaches (3/2, 3/2, 3/2) and
        ! the second direction (3, 3/2, 6) has the product -22.5; x stays as the first step left it
        call dense_new(sys, [1._real64, 2._real64, -1._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0._real64, 50)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [1, REASON_INDEFINITE]) + far(x, [1.5_real64, 1.5_real64, 1.5_real64]) + &
               wrong([size(hist), sys%napply], [2, 2])
        ! a right-hand side that is not finite stops as indefinite at once
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0._real64, 50)
        x = 0._real64
        call sys%solve([1._real64, ieee_value(1._real64, ieee_quiet_nan), 1._real64], x, hist, info)
        nbad = nbad + wrong(info, [0, REASON_INDEFINITE]) + count(abs(x) > 0._real64)
        ! a zero right-hand side is an error, the start untouched and the operator not applied
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        x = x2
        call sys%solve(0._real64 * b, x, hist, info)
        nbad = nbad + wrong(info, [0, REASON_ZERO_RHS]) + count(abs(x - x2) > 0._real64) + wrong([size(hist), sys%napply], [0, 0])
        ! a first product that is not positive is an error: a preconditioner that returns zero, one that is
        ! negative, and a start that already solves the system exactly, since the start's residual is not tested
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 0._real64)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [0, REASON_FIRST_PRODUCT]) + count(abs(x) > 0._real64) + wrong([size(hist)], [0])
        call dense_new(sys, [1._real64, 2._real64, 3._real64], -1._real64)
        x = 0._real64
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [0, REASON_FIRST_PRODUCT]) + count(abs(x) > 0._real64)
        call dense_new(sys, [1._real64, 2._real64, 4._real64], 1._real64)
        x = [1._real64, 0.5_real64, 0.25_real64]
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [0, REASON_FIRST_PRODUCT]) + count(abs(x - [1._real64, 0.5_real64, 0.25_real64]) > 0._real64) + &
               wrong([sys%napply], [1])
        ! a non-zero start is used: from (1, 0, 0) the residual (0, 1, 1) lies in two eigenvectors, so two
        ! iterations solve it, after one application for the start
        call dense_new(sys, [1._real64, 2._real64, 3._real64], 1._real64)
        call sys%set_rules(1.e-8_real64, 0._real64, 50)
        x = [1._real64, 0._real64, 0._real64]
        call sys%solve(b, x, hist, info)
        nbad = nbad + wrong(info, [2, REASON_RTOL]) + far(x, x3) + wrong([size(hist), sys%napply], [3, 3])
        ! the rules a system is born with, before any are set, are the reconstruction's
        if( .not. (abs(born%rtol - 1.e-4_real64) + abs(born%xtol - 1.5e-2_real64) <= 0._real64) ) nbad = nbad + 1
        if( born%maxits /= 50 ) nbad = nbad + 1
        err = err + real(nbad, real64)
    end subroutine check_stops

    ! the residual recomputed at every 25th iteration, on diag(1 .. 80) with b = 1 and fixed iteration counts: the
    ! operator's applications are the iterations plus one per recomputation; under an operator that changes at
    ! its 26th application the reported residual is the changed operator's, at iteration 25 and still at 30
    subroutine check_recompute( err )
        real(real64), intent(inout) :: err
        integer, parameter        :: NSYS = 80
        type(dense_system)        :: sys
        real(real64), allocatable :: hist(:)
        real(real64)              :: b(NSYS), x(NSYS), d(NSYS), ref
        integer                   :: info(2), nbad, i, icase, its(6), napply(6)
        d      = [(real(i, real64), i=1, NSYS)]
        b      = 1._real64
        its    = [24, 25, 30, 50, 25, 30]
        napply = [24, 26, 31, 52, 26, 31]
        nbad   = 0
        do icase = 1, 6
            call dense_new(sys, d, 1._real64)
            ref = 0._real64
            ! the first four cases keep the operator; the last two change it from its 26th application on, and
            ! the residual of the last holds only if the recomputed one carried the recursion on
            if( icase > 4 )then
                sys%first = 26
                sys%shift = 0.5_real64
                ref       = 0.5_real64
            endif
            call sys%set_rules(0._real64, 0._real64, its(icase))
            x = 0._real64
            call sys%solve(b, x, hist, info)
            nbad = nbad + wrong(info, [its(icase), REASON_FIXED]) + wrong([sys%napply], [napply(icase)])
            ref  = norm2(b - (d + ref) * x) / norm2(b)
            ! compared in absolute terms: the residuals are fractions of |b|, and a fused multiply-add in one of
            ! the two evaluations moves a small residual by more than 1e-12 of itself
            if( size(hist) == info(1) + 1 .and. info(1) > 0 )then
                err = max(err, oracle_finite_or_inf(abs(hist(size(hist)) - ref)))
            else
                nbad = nbad + 1
            endif
        end do
        err = max(err, real(nbad, real64))
    end subroutine check_recompute

    ! a dense system with the operator diag(d) and the preconditioner scale I, its counter at zero
    subroutine dense_new( sys, d, scale )
        type(dense_system), intent(inout) :: sys
        real(real64),       intent(in)    :: d(:), scale
        integer :: i
        if( allocated(sys%a) ) deallocate(sys%a)
        if( allocated(sys%b) ) deallocate(sys%b)
        allocate(sys%a(size(d), size(d)), sys%b(size(d), size(d)))
        sys%a = 0._real64
        sys%b = 0._real64
        do i = 1, size(d)
            sys%a(i, i) = d(i)
            sys%b(i, i) = scale
        end do
        sys%shift  = 0._real64
        sys%first  = huge(1)
        sys%napply = 0
        call sys%set_rules(RTOL_RECON, XTOL_RECON, MAXITS_RECON)
    end subroutine dense_new

    ! the number of entries in which two integer lists differ
    pure function wrong( a, ref ) result(c)
        integer, intent(in) :: a(:), ref(:)
        integer :: c
        c = count(a /= ref)
    end function wrong

    ! 1 when a vector is farther than the matrix limit from its reference, relative to it, or not finite
    pure function far( a, ref ) result(c)
        real(real64), intent(in) :: a(:), ref(:)
        integer :: c
        c = merge(0, 1, matrix_error(reshape(a, [size(a), 1]), reshape(ref, [size(ref), 1])) <= TOL_MATRIX)
    end function far

    ! the dense matrices of the operator and of the preconditioner from scalar definitions: the transform pair as
    ! its cosine sum over the lattice, sum of s(q) cos(2 pi q.(x_u - x_v) / m) / m**3; the mask as the integer
    ! points inside the radius n/2; the envelope as the product of the window's transforms at centred coordinates
    subroutine dense_matrices( khat, pre, lambda, hd, pd )
        real(real64), intent(in)  :: khat(:,:,:), pre(:,:,:), lambda
        real(real64), intent(out) :: hd(:,:), pd(:,:)
        real(real64), allocatable :: kt(:,:,:), pt(:,:,:), pm(:), ev(:)
        integer,      allocatable :: xs(:,:)
        real(real64)              :: w(3), c
        integer                   :: tap(3), n, m, u, v, i1, i2, i3, d1, d2, d3, dx(3)
        m = size(khat, 1)
        n = m / 2
        allocate(kt(-(n-1):n-1, -(n-1):n-1, -(n-1):n-1), pt(-(n-1):n-1, -(n-1):n-1, -(n-1):n-1), pm(n**3), ev(n**3), &
                 xs(3, n**3))
        call oracle_proj_stencil(0._real64, tap, w)
        kt = 0._real64
        pt = 0._real64
        do d3 = -(n - 1), n - 1
            do d2 = -(n - 1), n - 1
                do d1 = -(n - 1), n - 1
                    do i3 = 1, m
                        do i2 = 1, m
                            do i1 = 1, m
                                c = cos(TWOPI * real((i1 - 1) * d1 + (i2 - 1) * d2 + (i3 - 1) * d3, real64) / real(m, real64))
                                kt(d1, d2, d3) = kt(d1, d2, d3) + khat(i1, i2, i3) * c
                                pt(d1, d2, d3) = pt(d1, d2, d3) + pre(i1, i2, i3) * c
                            end do
                        end do
                    end do
                end do
            end do
        end do
        kt = kt / real(m, real64)**3
        pt = pt / real(m, real64)**3
        u  = 0
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    u        = u + 1
                    xs(:, u) = [i1, i2, i3] - 1 - n / 2
                    pm(u)    = merge(1._real64, 0._real64, 4 * sum(xs(:, u)**2) < n * n)
                    ev(u)    = product(w(2) + 2._real64 * w(1) * cos(TWOPI * real(xs(:, u), real64) / real(m, real64)))
                end do
            end do
        end do
        do v = 1, n**3
            do u = 1, n**3
                dx       = xs(:, u) - xs(:, v)
                hd(u, v) = pm(u) * kt(dx(1), dx(2), dx(3)) * pm(v)
                pd(u, v) = pm(u) * ev(u) * pt(dx(1), dx(2), dx(3)) * ev(v)
            end do
            hd(v, v) = hd(v, v) + lambda * pm(v)
        end do
    end subroutine dense_matrices

    ! the preconditioner's spectrum on the full lattice, typed apart from the module's: the shells by integer
    ! bounds, (2 s - 1)**2 <= 4 |q|**2 < (2 s + 1)**2; each lattice voxel reads the stored voxel that holds it,
    ! itself for h >= 0, the plane m/2 for h = -m/2, its mate otherwise
    pure function reference_spectrum( dens, n ) result(pre)
        real(real64), intent(in) :: dens(:,:,:)
        integer,      intent(in) :: n
        real(real64) :: pre(2*n, 2*n, 2*n)
        real(real64) :: mu(0:n), total, d
        integer      :: m, s, cnt, i1, i2, i3, g(3), q(3), q2
        m = 2 * n
        do s = 0, n
            total = 0._real64
            cnt   = 0
            do i3 = 1, m
                do i2 = 1, m
                    do i1 = 1, m / 2 + 1
                        q2 = (i1 - 1)**2 + signed_index(i2, m)**2 + signed_index(i3, m)**2
                        if( 4 * q2 >= (2 * s + 1)**2 ) cycle
                        if( s > 0 .and. 4 * q2 < (2 * s - 1)**2 ) cycle
                        if( dens(i1, i2, i3) > 0._real64 )then
                            total = total + dens(i1, i2, i3)
                            cnt   = cnt + 1
                        endif
                    end do
                end do
            end do
            mu(s) = 0._real64
            if( cnt > 0 ) mu(s) = total / real(cnt, real64)
        end do
        pre = 0._real64
        do i3 = 1, m
            do i2 = 1, m
                do i1 = 1, m
                    g = [signed_index(i1, m), signed_index(i2, m), signed_index(i3, m)]
                    if( g(1) >= 0 )then
                        q = g
                    else if( g(1) == -m / 2 )then
                        q = [m / 2, g(2), g(3)]
                    else
                        q = -g
                    endif
                    d  = max(dens(1+q(1), 1+modulo(q(2), m), 1+modulo(q(3), m)), 0._real64)
                    q2 = q(1)**2 + signed_index(1+modulo(q(2), m), m)**2 + signed_index(1+modulo(q(3), m), m)**2
                    do s = 0, n
                        if( 4 * q2 >= (2 * s + 1)**2 ) cycle
                        if( mu(s) > 0._real64 .and. d >= 0.1_real64 * mu(s) )then
                            pre(i1, i2, i3) = 1._real64 / (d + 0.01_real64 * mu(s))
                        endif
                        exit
                    end do
                end do
            end do
        end do
    end function reference_spectrum

    ! the unknowns of the n-cube at integer points inside the radius n/2, in vector order
    pure function support_index( n ) result(idx)
        integer, intent(in) :: n
        integer, allocatable :: idx(:)
        integer              :: all(n**3), cnt, u, i1, i2, i3
        cnt = 0
        u   = 0
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    u = u + 1
                    if( 4 * sum(([i1, i2, i3] - 1 - n / 2)**2) < n * n )then
                        cnt      = cnt + 1
                        all(cnt) = u
                    endif
                end do
            end do
        end do
        allocate(idx(cnt))
        idx = all(1:cnt)
    end function support_index

    ! the eigenvalues of a symmetric matrix by cyclic Jacobi rotations
    pure function symmetric_eigenvalues( a ) result(ev)
        real(real64), intent(in) :: a(:,:)
        real(real64) :: ev(size(a, 1))
        real(real64) :: b(size(a, 1), size(a, 1)), bp(size(a, 1)), bq(size(a, 1)), theta, t, c, s, off
        integer      :: n, sweep, p, q
        n = size(a, 1)
        b = a
        do sweep = 1, 100
            off = 0._real64
            do q = 2, n
                off = off + sum(b(1:q-1, q)**2)
            end do
            if( .not. (off > (1.e-15_real64 * norm2(a))**2) ) exit
            do p = 1, n - 1
                do q = p + 1, n
                    if( .not. (abs(b(p, q)) > 0._real64) ) cycle
                    theta   = (b(q, q) - b(p, p)) / (2._real64 * b(p, q))
                    t       = sign(1._real64, theta) / (abs(theta) + sqrt(theta**2 + 1._real64))
                    c       = 1._real64 / sqrt(t**2 + 1._real64)
                    s       = t * c
                    bp      = b(:, p)
                    bq      = b(:, q)
                    b(:, p) = c * bp - s * bq
                    b(:, q) = s * bp + c * bq
                    bp      = b(p, :)
                    bq      = b(q, :)
                    b(p, :) = c * bp - s * bq
                    b(q, :) = s * bp + c * bq
                end do
            end do
        end do
        do p = 1, n
            ev(p) = b(p, p)
        end do
    end function symmetric_eigenvalues

    ! |a - ref| over |ref| in the Frobenius norm; +Inf when a value is not finite
    pure function matrix_error( a, ref ) result(e)
        real(real64), intent(in) :: a(:,:), ref(:,:)
        real(real64) :: e
        e = ieee_value(e, ieee_positive_inf)
        if( all(ieee_is_finite(a)) .and. all(ieee_is_finite(ref)) ) e = oracle_finite_or_inf(norm2(a - ref) / norm2(ref))
    end function matrix_error

    ! a fixed vector from integers, (modulo(3 i + 7 seed, 13) - 6) / 6 + modulo(i, 5) / 10
    pure function fixed_vector( n, seed ) result(x)
        integer, intent(in) :: n, seed
        real(real64) :: x(n)
        integer      :: i
        do i = 1, n
            x(i) = real(modulo(3 * i + 7 * seed, 13) - 6, real64) / 6._real64 + real(modulo(i * seed, 5), real64) / 10._real64
        end do
    end function fixed_vector

end module mlxf_oracle_recon_pcg
