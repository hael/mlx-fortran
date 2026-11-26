!@descr: the toy reconstructor_pcg's device state (test only): the kernel and preconditioner spectra, envelopes, mask, right-hand side
! Every MLX handle of the toy reconstructor lives here. A native volume is (n, n, n) float32; a spectrum of the padded
! lattice is (m/2 + 1, m, m), m = 2 n, the halved dimension first, k and m of dimensions 2 and 3 at 1 + modulo(k, m).
! The operator embeds a volume at the corner of the padded cube through the transform's length and crops the corner
! back: the centre embedding differs by a translation of the periodic lattice, which a Fourier multiplier does not
! see. The raw accumulators are held from set_raw_accum until finish evaluates what they made and releases them.
module mlxf_toy_reconstructor_pcg_workspace
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,                 only: mlx_array, mlx_from, mlx_to, mlx_view, mlx_eval, mlx_rfftn, mlx_irfftn, mlx_fftshift, &
                                mlx_slice, mlx_take, mlx_zeros_like, mlx_ones_like, mlx_arange, mlx_round, mlx_astype, &
                                MLX_FFT_NORMS, MLX_DTYPES, reshape, real, cmplx, sqrt, abs, max, merge, sum
use mlxf_test_defs,       only: PCG_ENVELOPE_FLOOR
use mlxf_toy_device_work, only: device_work
implicit none

public :: reconstructor_pcg_workspace
private

! the device state of one half: n the native box, m the padded one, lambda the ridge; the raw packed accumulators bacc and dacc until
! finish; khat and pre the kernel's and the preconditioner's spectra; env and invenv the envelope and its guarded
! reciprocal, mask the binary support (none: no support), b_rhs the right-hand side; msg the last refusal. It
! extends device_work, the opaque type the reconstructor holds it as
type, extends(device_work) :: reconstructor_pcg_workspace
    private
    integer                       :: n         = 0
    integer                       :: m         = 0
    logical                       :: l_raw     = .false.
    logical                       :: l_mask    = .false.
    logical                       :: l_final   = .false.
    real(real32)                  :: lambda    = 0._real32
    type(mlx_array)               :: bacc
    type(mlx_array)               :: dacc
    type(mlx_array)               :: khat
    type(mlx_array)               :: pre
    type(mlx_array)               :: env
    type(mlx_array)               :: invenv
    type(mlx_array)               :: mask
    type(mlx_array)               :: b_rhs
    character(len=:), allocatable :: msg
  contains
    procedure :: new
    procedure :: kill
    procedure :: set_envelopes
    procedure :: set_mask
    procedure :: set_raw_accum
    procedure :: density_view
    procedure :: fold_rhs
    procedure :: set_rhs
    procedure :: build_precond
    procedure :: build_kernel
    procedure :: scale_kernel
    procedure :: finish
    procedure :: kernel_product
    procedure :: precond_product
    procedure :: mask_mul
    procedure :: deapod_mul
    procedure :: set_ridge
    procedure :: add_ridge
    procedure :: line_dots
    procedure :: rhs
    procedure :: copy_spectra
    procedure :: copy_rhs
    procedure :: is_final
    procedure :: set_message
    procedure :: message
    final     :: reconstructor_pcg_workspace_final
end type reconstructor_pcg_workspace

contains

    ! the state of a native box of n on the padded lattice of 2 n; nothing on the device yet
    subroutine new( self, n )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        integer,                            intent(in)    :: n
        call self%kill()
        self%n = n
        self%m = 2 * n
    end subroutine new

    ! releases every handle; idempotent
    subroutine kill( self )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        call self%bacc%kill()
        call self%dacc%kill()
        call self%khat%kill()
        call self%pre%kill()
        call self%env%kill()
        call self%invenv%kill()
        call self%mask%kill()
        call self%b_rhs%kill()
        self%l_raw   = .false.
        self%l_mask  = .false.
        self%l_final = .false.
        self%n       = 0
        self%m       = 0
    end subroutine kill

    subroutine reconstructor_pcg_workspace_final( self )
        type(reconstructor_pcg_workspace), intent(inout) :: self
        call self%kill()
    end subroutine reconstructor_pcg_workspace_final

    ! the envelope E of the native box and its guarded reciprocal, both (n, n, n)
    subroutine set_envelopes( self, env, invenv )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        real(real32),                       intent(in)    :: env(:,:,:), invenv(:,:,:)
        self%env    = mlx_from(env)
        self%invenv = mlx_from(invenv)
    end subroutine set_envelopes

    ! the binary support P (n, n, n); without an argument the support is cleared
    subroutine set_mask( self, mask )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        real(real32), optional,             intent(in)    :: mask(:,:,:)
        call self%mask%kill()
        self%l_mask = present(mask)
        if( self%l_mask ) self%mask = mlx_from(mask)
    end subroutine set_mask

    ! the raw packed accumulators, numerator b and density d (m/2 + 1, m, m), copied to the device
    subroutine set_raw_accum( self, b, d )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        complex(real32),                    intent(in)    :: b(:,:,:)
        real(real32),                       intent(in)    :: d(:,:,:)
        self%bacc  = mlx_from(b)
        self%dacc  = mlx_from(d)
        self%l_raw = .true.
    end subroutine set_raw_accum

    ! a read-only view of the raw density on the device, valid until finish or kill; status non-zero without one
    subroutine density_view( self, p, status )
        class(reconstructor_pcg_workspace), intent(in)    :: self
        real(real32), pointer,              intent(inout) :: p(:,:,:)
        integer,                            intent(out)   :: status
        nullify(p)
        status = 1
        if( .not. self%l_raw ) return
        call mlx_view(self%dacc, p, status)
    end subroutine density_view

    ! the unscaled inverse transform of the raw numerator with its origin moved to voxel m/2 + 1, and the centre
    ! n-cube of it (SIMPLE's fold of the accumulator, its inverse transform and its centre crop)
    function fold_rhs( self ) result(v)
        class(reconstructor_pcg_workspace), intent(in) :: self
        type(mlx_array) :: v, g, s
        integer         :: m, n, lo
        m  = self%m
        n  = self%n
        lo = n / 2 + 1
        g  = mlx_irfftn(self%bacc, n=[m, m, m], norm=MLX_FFT_NORMS%forward)
        s  = mlx_fftshift(g)
        v  = mlx_slice(s, [lo, lo, lo], [lo + n - 1, lo + n - 1, lo + n - 1])
    end function fold_rhs

    ! the right-hand side, held to kill
    subroutine set_rhs( self, v )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        type(mlx_array),                    intent(in)    :: v
        self%b_rhs = v
    end subroutine set_rhs

    ! the preconditioner's spectrum from the raw density: on a voxel of shell s = nint(|q|) <= rho_lim, with d the
    ! density floored at zero, 1 / (d + shfloor(s)) where d >= shthr(s) and the sum is positive, else zero; zero
    ! beyond rho_lim. shthr and shfloor are indexed 0 .. rho_lim
    subroutine build_precond( self, shthr, shfloor, rho_lim )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        real(real32),                       intent(in)    :: shthr(0:), shfloor(0:)
        integer,                            intent(in)    :: rho_lim
        type(mlx_array) :: sh, thr, flo, d, denom, zero, tab_thr, tab_flo
        real(real32)    :: t(0:rho_lim+1), f(0:rho_lim+1)
        t(0:rho_lim)   = shthr(0:rho_lim)
        f(0:rho_lim)   = shfloor(0:rho_lim)
        t(rho_lim + 1) = huge(1._real32)
        f(rho_lim + 1) = 0._real32
        sh       = shell_index(self, rho_lim + 1)
        tab_thr  = mlx_from(t)
        tab_flo  = mlx_from(f)
        thr      = mlx_take(tab_thr, sh)
        flo      = mlx_take(tab_flo, sh)
        d        = max(self%dacc, 0._real32)
        zero     = mlx_zeros_like(d)
        denom    = merge(d + flo, zero, d >= thr)
        self%pre = merge(1._real32 / denom, zero, denom > 0._real32)
    end subroutine build_precond

    ! the kernel spectrum before its scale: the raw density inside shell khat_lim, its inverse transform divided by
    ! the deposition envelope dep(d1) dep(d2) dep(d3) at the offset d from voxel 1 (zero where that product is at
    ! most the floor), transformed again; the real part
    subroutine build_kernel( self, khat_lim, dep )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        integer,                            intent(in)    :: khat_lim
        real(real32),                       intent(in)    :: dep(:)
        type(mlx_array) :: sh, dcut, zero, psf, e1, e2, e3, prod, recip, spec, ones
        integer         :: m
        m     = self%m
        sh    = shell_of(self)
        zero  = mlx_zeros_like(self%dacc)
        dcut  = merge(self%dacc, zero, sh <= real(khat_lim, real32))
        psf   = mlx_irfftn(cmplx(dcut, zero), n=[m, m, m])
        e1    = mlx_from(reshape(dep, [m, 1, 1]))
        e2    = mlx_from(reshape(dep, [1, m, 1]))
        e3    = mlx_from(reshape(dep, [1, 1, m]))
        prod  = e1 * e2 * e3
        ones  = mlx_ones_like(prod)
        recip = merge(ones / prod, mlx_zeros_like(prod), abs(prod) > real(PCG_ENVELOPE_FLOOR, real32))
        spec  = mlx_rfftn(psf * recip)
        self%khat = real(spec)
    end subroutine build_kernel

    ! the kernel spectrum times a scale
    subroutine scale_kernel( self, scale )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        real(real32),                       intent(in)    :: scale
        self%khat = self%khat * scale
    end subroutine scale_kernel

    ! evaluates the spectra and the right-hand side together (the one wait of the finalisation) and releases the
    ! raw accumulators; status non-zero on a failed evaluation
    subroutine finish( self, status )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        integer,                            intent(out)   :: status
        call mlx_eval([self%khat, self%pre, self%b_rhs], status)
        if( status /= 0 ) return
        call self%bacc%kill()
        call self%dacc%kill()
        self%l_raw   = .false.
        self%l_final = .true.
    end subroutine finish

    ! C^T F^-1 diag(Khat) F C u: the corner embedding through the transform's length, the corner crop
    function kernel_product( self, u ) result(hu)
        class(reconstructor_pcg_workspace), intent(in) :: self
        type(mlx_array),                    intent(in) :: u
        type(mlx_array) :: hu, s, g
        integer         :: m, n
        m  = self%m
        n  = self%n
        s  = mlx_rfftn(u, n=[m, m, m])
        g  = mlx_irfftn(s * self%khat, n=[m, m, m])
        hu = mlx_slice(g, [1, 1, 1], [n, n, n])
    end function kernel_product

    ! P E C^T F^-1 diag(pi) F C E r
    function precond_product( self, r ) result(z)
        class(reconstructor_pcg_workspace), intent(in) :: self
        type(mlx_array),                    intent(in) :: r
        type(mlx_array) :: z, s, g, c
        integer         :: m, n
        m = self%m
        n = self%n
        s = mlx_rfftn(self%env * r, n=[m, m, m])
        g = mlx_irfftn(s * self%pre, n=[m, m, m])
        c = mlx_slice(g, [1, 1, 1], [n, n, n])
        z = c * self%env
        call self%mask_mul(z)
    end function precond_product

    ! v = P v (identity without a support)
    subroutine mask_mul( self, v )
        class(reconstructor_pcg_workspace), intent(in)    :: self
        type(mlx_array),                    intent(inout) :: v
        if( self%l_mask ) v = v * self%mask
    end subroutine mask_mul

    ! v = E^-1 v
    subroutine deapod_mul( self, v )
        class(reconstructor_pcg_workspace), intent(in)    :: self
        type(mlx_array),                    intent(inout) :: v
        v = v * self%invenv
    end subroutine deapod_mul

    ! the ridge lambda, in single precision as the operator applies it
    subroutine set_ridge( self, lambda )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        real(real32),                       intent(in)    :: lambda
        self%lambda = lambda
    end subroutine set_ridge

    ! hp = hp + lambda p
    subroutine add_ridge( self, p, hp )
        class(reconstructor_pcg_workspace), intent(in)    :: self
        type(mlx_array),                    intent(in)    :: p
        type(mlx_array),                    intent(inout) :: hp
        hp = hp + self%lambda * p
    end subroutine add_ridge

    ! the inner product's device half of two native volumes: a(:, j, k) . b(:, j, k), one float32 sum per line of
    ! n, (n, n) partial sums
    function line_dots( self, a, b ) result(d)
        class(reconstructor_pcg_workspace), intent(in) :: self
        type(mlx_array),                    intent(in) :: a, b
        type(mlx_array) :: d
        d = sum(reshape(a * b, [self%n, self%n, self%n]), dim=1)
    end function line_dots

    ! the right-hand side
    function rhs( self ) result(b)
        class(reconstructor_pcg_workspace), intent(in) :: self
        type(mlx_array) :: b
        b = self%b_rhs
    end function rhs

    ! host copies of the kernel's and the preconditioner's spectra (m/2 + 1, m, m)
    subroutine copy_spectra( self, khat, pre )
        class(reconstructor_pcg_workspace), intent(in)  :: self
        real(real32),                       intent(out) :: khat(:,:,:), pre(:,:,:)
        call mlx_to(khat, self%khat)
        call mlx_to(pre, self%pre)
    end subroutine copy_spectra

    ! a host copy of the right-hand side (n, n, n)
    subroutine copy_rhs( self, b )
        class(reconstructor_pcg_workspace), intent(in)  :: self
        real(real32),                       intent(out) :: b(:,:,:)
        call mlx_to(b, self%b_rhs)
    end subroutine copy_rhs

    ! whether the spectra and the right-hand side are made
    logical function is_final( self )
        class(reconstructor_pcg_workspace), intent(in) :: self
        is_final = self%l_final
    end function is_final

    subroutine set_message( self, msg )
        class(reconstructor_pcg_workspace), intent(inout) :: self
        character(len=*),                   intent(in)    :: msg
        self%msg = msg
    end subroutine set_message

    ! the reason of the last refusal or failure ('' when there was none)
    function message( self ) result(msg)
        class(reconstructor_pcg_workspace), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

    ! the shells of the packed half as 1-based indices into a table of shells 0 .. top - 1, shells from top on at
    ! the table's last entry, top + 1
    function shell_index( self, top ) result(idx)
        class(reconstructor_pcg_workspace), intent(in) :: self
        integer,                            intent(in) :: top
        type(mlx_array) :: idx, s
        s   = shell_of(self)
        s   = merge(mlx_zeros_like(s) + real(top, real32), s, s > real(top, real32))
        idx = mlx_astype(s + 1._real32, MLX_DTYPES%int32)
    end function shell_index

    ! the shell nint(|q|) of every voxel of the packed half, float32, exact for the boxes concerned (|q|**2 below
    ! 2**24, and no integer's square root lies within float32 rounding of a half-integer there)
    function shell_of( self ) result(s)
        class(reconstructor_pcg_workspace), intent(in) :: self
        type(mlx_array) :: s, h, k, k2, h2, q2
        integer         :: m
        m   = self%m
        h   = mlx_arange(0._real64, real(m / 2 + 1, real64), dtype=MLX_DTYPES%float32)
        k   = mlx_arange(0._real64, real(m, real64), dtype=MLX_DTYPES%float32)
        k   = merge(k - real(m, real32), k, k >= real(m / 2, real32))
        h2  = reshape(h * h, [m / 2 + 1, 1, 1])
        k2  = k * k
        q2  = h2 + reshape(k2, [1, m, 1]) + reshape(k2, [1, 1, m])
        s   = mlx_round(sqrt(q2))
    end function shell_of

end module mlxf_toy_reconstructor_pcg_workspace
