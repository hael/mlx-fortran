!@descr: the toy reconstructor_pcg (test only): a miniature of SIMPLE's PCG reconstruction from the raw accumulators to the map
! The type, its procedures and their dummy arguments carry SIMPLE's names; scripts/toy_mirror.txt lists each as
! mirrored or as an addition. SIMPLE's reconstructor_pcg extends pcg_lattice; the toy has the one type, with the
! lattice's members it reads public as in SIMPLE. The host keeps SIMPLE's host work: the envelopes, the soft window
! and its mask, the density's shell statistics, the window at the start and at the exit. All MLX state is the
! component ws, made in new and released in kill; this module sees it as class(device_work) and imports no MLX
! name, and the glue submodule mlxf_toy_reconstructor_pcg_mlx holds what needs the device: the device forms of the
! operator, the adapter the engine solves through, and the transfers. The five procedures of the operator
! (mask_mul, apply_normal, apply_normal_kernel, apply_precond, dot_real_volume) take and return host arrays, as
! SIMPLE's do: each sends its volume to the device, applies the device form and brings the result back. The toy
! has no host route: a reconstructor is made on the MLX backend or refused.
module mlxf_toy_reconstructor_pcg
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
use mlxf_test_defs,       only: KBWINSZ, KBALPHA, OSMPL_PAD_FAC, PCG_XTOL, PCG_RESID_REPLACE, PCG_RHO_FLOOR_FRAC, &
                                PCG_RHO_SAMPLED_FRAC, PCG_SUPPORT_DIV_MIN, PCG_ENVELOPE_FLOOR, PCG_STOP_INDEFINITE, &
                                pcg_solver_options, parameters
use mlxf_toy_device_work, only: device_work
use mlxf_toy_pcg_solver,  only: pcg_solver_outcome
implicit none

public :: reconstructor_pcg
private

real(real64), parameter :: PI = acos(-1._real64)
! the soft window's edge beyond the mask radius (SIMPLE's mask3D_soft), in pixels
real(real64), parameter :: SOFT_EDGE = 6._real64
! the density statistics: the native shells of the ridge's scale
integer, parameter :: DATA_SCALE_NATIVE_SHELLS = 6
! the stages timed: the density's statistics, the finalisation's graph and wait, the engine, the map's copy
integer, parameter :: NSTAGES = 4
! what a procedure that needs the device answers on the host backend
character(len=*), parameter :: NO_HOST_ROUTE = 'refused: the toy has no host route'

! SIMPLE's members under SIMPLE's names, for the members the toy has. The lattice's (public, as pcg_lattice's are
! in SIMPLE): the native and padded boxes, the padding factor and offset, the native Nyquist radius, padsc =
! padf**3, the window's half-width in taps, the deposition envelope of the padded lattice (offset from voxel 1),
! the hard support, the soft window. The reconstructor's: the ridge, absolute or relative to the data scale, the
! envelope and its guarded reciprocal on the native box, the state flags. The toy's own: msg, the reason of the
! last refusal; nwaits, the host's waits; stage_s, the stages' seconds; l_mlx, the backend taken at new; ws, the
! device state
type :: reconstructor_pcg
    private
    integer,                           public              :: box     = 0
    integer,                           public              :: boxpd   = 0
    integer,                           public              :: padf    = OSMPL_PAD_FAC
    integer,                           public              :: pad_off = 0
    integer,                           public              :: Rnat    = 0
    real(real32),                      public              :: padsc   = 1._real32
    integer,                           public              :: iwinsz  = 0
    real(real64),                      allocatable, public :: dep1d(:)
    real(real32),                      allocatable, public :: mask(:,:,:)
    real(real32),                      allocatable, public :: window(:,:,:)
    logical,                           public              :: l_mask  = .false.
    real(real32)                                           :: lambda     = 0._real32
    real(real32)                                           :: lambda_rel = 0._real32
    real(real32)                                           :: data_scale = 0._real32
    logical                                                :: l_lambda_relative = .false.
    real(real32),                      allocatable         :: env(:,:,:)
    real(real32),                      allocatable         :: invenv(:,:,:)
    logical                                                :: l_accum   = .false.
    logical                                                :: l_rhs     = .false.
    logical                                                :: l_precond = .false.
    logical                                                :: l_kernel  = .false.
    logical                                                :: exists    = .false.
    logical                                                :: l_mlx     = .false.
    integer                                                :: nwaits    = 0
    real(real64)                                           :: stage_s(NSTAGES) = 0._real64
    character(len=:),                  allocatable         :: msg
    class(device_work),                allocatable         :: ws
  contains
    procedure          :: new
    procedure          :: kill
    procedure          :: set_window_sphere
    procedure          :: mask_mul
    procedure          :: set_lambda_relative
    procedure          :: set_raw_accum
    procedure          :: end_accum
    procedure          :: apply_normal
    procedure          :: apply_normal_kernel
    procedure          :: apply_precond
    procedure          :: dot_real_volume
    procedure          :: solve_accum
    procedure          :: get_effective_lambda
    procedure          :: get_solve_support
    procedure          :: copy_spectra
    procedure          :: copy_volumes
    procedure          :: message
    procedure          :: stage_seconds
    procedure          :: host_waits
    procedure          :: get_pcg_operator
    procedure, private :: build_env
    procedure, private :: update_lambda_from_density
    procedure, private :: finalize_density_accum
    procedure, private :: finalize_khat
    procedure, private :: calibrate_kernel
    procedure, private :: window_mul
    procedure, private :: window_div
    procedure, private, nopass :: solve_stopped
    final              :: reconstructor_pcg_final
end type reconstructor_pcg

! MLX: the glue procedures, private to the class. A host procedure's whole knowledge of the device is a guarded
! call of its <name>_mlx; the bodies are in the glue submodule mlxf_toy_reconstructor_pcg_mlx, which alone imports
! the workspace and the device engine, and which a build without MLX compiles as stubs that refuse with "built
! without MLX"
interface
    ! the device state of a new reconstructor: the envelopes and the ridge
    module subroutine new_mlx( self, status )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(out)   :: status
    end subroutine new_mlx

    ! the hard support as the reconstructor holds it, uploaded or cleared
    module subroutine set_window_sphere_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
    end subroutine set_window_sphere_mlx

    ! the raw accumulators handed to the device
    module subroutine set_raw_accum_mlx( self, b, d )
        class(reconstructor_pcg), intent(inout) :: self
        complex(real32),          intent(in)    :: b(:,:,:)
        real(real32),             intent(in)    :: d(:,:,:)
    end subroutine set_raw_accum_mlx

    ! the right-hand side from the numerator (folded, deapodised, masked), and a view of the raw density for the
    ! host's statistics
    module subroutine end_accum_mlx( self, rho, status )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32), pointer,    intent(inout) :: rho(:,:,:)
        integer,                  intent(out)   :: status
    end subroutine end_accum_mlx

    ! the finalisation's one wait
    module subroutine end_accum_wait_mlx( self, status )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(out)   :: status
    end subroutine end_accum_wait_mlx

    ! the ridge as the device applies it
    module subroutine update_lambda_from_density_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
    end subroutine update_lambda_from_density_mlx

    ! the preconditioner's spectrum from the host's shell thresholds and floors, indexed 0 .. rho_lim
    module subroutine finalize_density_accum_mlx( self, shthr, shfloor, rho_lim )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: shthr(0:), shfloor(0:)
        integer,                  intent(in)    :: rho_lim
    end subroutine finalize_density_accum_mlx

    ! the kernel's spectrum inside shell khat_lim
    module subroutine finalize_khat_mlx( self, khat_lim )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(in)    :: khat_lim
    end subroutine finalize_khat_mlx

    module subroutine calibrate_kernel_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
    end subroutine calibrate_kernel_mlx

    ! the five procedures of the operator: the host volume sent to the device, the device form applied, the result
    ! brought back; a volume of size zero when the device form refuses
    module subroutine mask_mul_mlx( self, v )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(inout) :: v(self%box, self%box, self%box)
    end subroutine mask_mul_mlx

    module function apply_normal_mlx( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
    end function apply_normal_mlx

    module function apply_normal_kernel_mlx( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
    end function apply_normal_kernel_mlx

    module function apply_precond_mlx( self, r ) result(z)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: r(self%box, self%box, self%box)
        real(real32), allocatable :: z(:,:,:)
    end function apply_precond_mlx

    module function dot_real_volume_mlx( self, a, b ) result(d)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: a(self%box, self%box, self%box), b(self%box, self%box, self%box)
        real(real64) :: d
    end function dot_real_volume_mlx

    ! the engine's solve from the start in x against the right-hand side on the device, the waits and the seconds
    ! counted; the solution is copied into x unless the solve is given up (solve_stopped), which leaves x as it came
    module subroutine solve_accum_mlx( self, x, options, l_outcome, result )
        class(reconstructor_pcg), target, intent(inout) :: self
        real(real32),                     intent(inout) :: x(:,:,:)
        type(pcg_solver_options),         intent(in)    :: options
        logical,                          intent(in)    :: l_outcome
        type(pcg_solver_outcome),         intent(out)   :: result
    end subroutine solve_accum_mlx

    module subroutine copy_spectra_mlx( self, khat, pre )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: khat(:,:,:), pre(:,:,:)
    end subroutine copy_spectra_mlx

    module subroutine copy_volumes_mlx( self, b_rhs )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: b_rhs(:,:,:)
    end subroutine copy_volumes_mlx

    ! the adapter the engine solves through, bound to self
    module subroutine get_pcg_operator_mlx( self, op )
        class(reconstructor_pcg), target, intent(inout) :: self
        class(device_work), allocatable,  intent(out)   :: op
    end subroutine get_pcg_operator_mlx
end interface

contains

    ! a solve of the native box (even) on the padded lattice, with the absolute ridge lambda (default zero), on the
    ! backend params%l_mlx names (the MLX one when params is absent); a refusal (message) leaves no reconstructor.
    ! The toy has no host route.
    subroutine new( self, box, lambda, params )
        class(reconstructor_pcg),   intent(inout) :: self
        integer,                    intent(in)    :: box
        real(real32),     optional, intent(in)    :: lambda
        type(parameters), optional, intent(in)    :: params
        integer :: st
        call self%kill()
        if( box < 2 .or. modulo(box, 2) /= 0 )then
            self%msg = 'reconstructor_pcg%new: refused: the box is even and at least 2'
            return
        endif
        self%l_mlx = .true.
        if( present(params) ) self%l_mlx = params%l_mlx
        if( .not. self%l_mlx )then
            self%msg = 'reconstructor_pcg%new: '//NO_HOST_ROUTE
            return
        endif
        self%box     = box
        self%padf    = OSMPL_PAD_FAC
        self%boxpd   = self%padf * box
        self%pad_off = (self%boxpd - box) / 2
        self%Rnat    = box / 2
        self%padsc   = real(self%padf, real32)**3
        self%iwinsz  = ceiling(KBWINSZ - 0.5_real32)
        if( present(lambda) ) self%lambda = lambda
        call self%build_env()
        call new_mlx(self, st)
        if( st /= 0 )then
            call self%kill()
            return
        endif
        self%exists = .true.
    end subroutine new

    ! releases the device state, killed before it is deallocated, and the host members; idempotent
    subroutine kill( self )
        class(reconstructor_pcg), intent(inout) :: self
        if( allocated(self%ws) )then
            call self%ws%kill()
            deallocate(self%ws)
        endif
        if( allocated(self%dep1d) ) deallocate(self%dep1d)
        if( allocated(self%mask) ) deallocate(self%mask)
        if( allocated(self%window) ) deallocate(self%window)
        if( allocated(self%env) ) deallocate(self%env)
        if( allocated(self%invenv) ) deallocate(self%invenv)
        self%l_mask            = .false.
        self%l_lambda_relative = .false.
        self%l_accum           = .false.
        self%l_rhs             = .false.
        self%l_precond         = .false.
        self%l_kernel          = .false.
        self%exists            = .false.
        self%l_mlx             = .false.
        self%nwaits            = 0
        self%stage_s           = 0._real64
        self%lambda            = 0._real32
        self%lambda_rel        = 0._real32
        self%data_scale        = 0._real32
        self%box               = 0
        self%boxpd             = 0
        self%pad_off           = 0
        self%Rnat              = 0
        self%padsc             = 1._real32
        self%iwinsz            = 0
    end subroutine kill

    subroutine reconstructor_pcg_final( self )
        type(reconstructor_pcg), intent(inout) :: self
        call self%kill()
    end subroutine reconstructor_pcg_final

    ! the deposition envelope of the padded lattice, w0 + 2 w1 cos(2 pi d / boxpd) with the normalised weights of
    ! the window's centre taps, at the offset d from voxel 1; the native envelope as its product about voxel
    ! box/2 + 1 (unity there) and its reciprocal, zero where the envelope is below the floor. The device takes both
    ! when its state is made
    subroutine build_env( self )
        class(reconstructor_pcg), intent(inout) :: self
        real(real64) :: k0, k1, w0, w1, e(self%box), env(self%box, self%box, self%box)
        integer      :: i, j, k, n
        n  = self%box
        k0 = kb_window(0._real64)
        k1 = kb_window(1._real64)
        w0 = k0 / (k0 + 2._real64 * k1)
        w1 = k1 / (k0 + 2._real64 * k1)
        allocate(self%dep1d(self%boxpd))
        do i = 1, self%boxpd
            self%dep1d(i) = w0 + 2._real64 * w1 * cos(2._real64 * PI * real(i - 1, real64) / real(self%boxpd, real64))
        end do
        do i = 1, n
            e(i) = w0 + 2._real64 * w1 * cos(2._real64 * PI * real(i - 1 - n / 2, real64) / real(self%boxpd, real64))
        end do
        do k = 1, n
            do j = 1, n
                do i = 1, n
                    env(i, j, k) = e(i) * e(j) * e(k)
                end do
            end do
        end do
        self%env    = real(env, real32)
        allocate(self%invenv(n, n, n), source=0._real32)
        where( .not. (abs(env) < PCG_ENVELOPE_FLOOR) ) self%invenv = real(1._real64 / env, real32)
    end subroutine build_env

    ! the spherical support: SIMPLE's soft mask of radius mskrad (pixels) about voxel box/2 + 1 (one inside
    ! maxrad - width, a raised cosine to zero at maxrad = (min(nint(2 (mskrad + 6)), box) / 2), width = 2 (maxrad -
    ! mskrad)), and the hard mask window > 0; mskrad <= 0 clears the support
    subroutine set_window_sphere( self, mskrad )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: mskrad
        real(real64) :: win(self%box, self%box, self%box), maxrad, width, r0, r
        integer      :: i1, i2, i3, n
        if( allocated(self%mask) ) deallocate(self%mask)
        if( allocated(self%window) ) deallocate(self%window)
        self%l_mask = .false.
        if( self%l_mlx ) call set_window_sphere_mlx(self)
        if( .not. (mskrad > 0._real32) ) return
        n      = self%box
        maxrad = real(min(nint(2._real64 * (real(mskrad, real64) + SOFT_EDGE)), n) / 2, real64)
        width  = 2._real64 * (maxrad - real(mskrad, real64))
        r0     = maxrad - width
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    r = sqrt(real((i1 - 1 - n / 2)**2 + (i2 - 1 - n / 2)**2 + (i3 - 1 - n / 2)**2, real64))
                    if( r >= maxrad )then
                        win(i1, i2, i3) = 0._real64
                    else if( r > r0 )then
                        win(i1, i2, i3) = (cos(PI * (r - r0) / width) + 1._real64) / 2._real64
                    else
                        win(i1, i2, i3) = 1._real64
                    endif
                end do
            end do
        end do
        self%window = real(win, real32)
        self%mask   = merge(1._real32, 0._real32, self%window > 0._real32)
        self%l_mask = .true.
        if( self%l_mlx ) call set_window_sphere_mlx(self)
    end subroutine set_window_sphere

    ! v = P v (identity without a support), by the device; a refusal (message) leaves v as it came
    subroutine mask_mul( self, v )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(inout) :: v(self%box, self%box, self%box)
        if( self%l_mlx )then
            call mask_mul_mlx(self, v)
        else
            self%msg = 'reconstructor_pcg%mask_mul: '//NO_HOST_ROUTE
        endif
    end subroutine mask_mul

    ! the ridge as a multiple of the data scale, derived when the density is finalised
    subroutine set_lambda_relative( self, lambda_rel )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: lambda_rel
        if( .not. ieee_is_finite(lambda_rel) .or. lambda_rel < 0._real32 )then
            self%msg = 'reconstructor_pcg%set_lambda_relative: refused: lambda_rel is finite and non-negative'
            return
        endif
        self%lambda_rel        = lambda_rel
        self%data_scale        = 0._real32
        self%lambda            = 0._real32
        self%l_lambda_relative = .true.
    end subroutine set_lambda_relative

    ! the parts' raw accumulators summed, as the master holds them: the packed numerator b and density d, each
    ! (box + 1, boxpd, boxpd) with h = 0 .. boxpd/2 first; handed to the device, no host copy kept
    subroutine set_raw_accum( self, b, d )
        class(reconstructor_pcg), intent(inout) :: self
        complex(real32),          intent(in)    :: b(:,:,:)
        real(real32),             intent(in)    :: d(:,:,:)
        integer :: shp(3)
        shp = [self%box + 1, self%boxpd, self%boxpd]
        if( .not. self%exists .or. any(shape(b) /= shp) .or. any(shape(d) /= shp) )then
            self%msg = 'reconstructor_pcg%set_raw_accum: refused: the accumulators are (box + 1, boxpd, boxpd)'
            return
        endif
        if( self%l_mlx ) call set_raw_accum_mlx(self, b, d)
        self%l_accum   = .true.
        self%l_rhs     = .false.
        self%l_precond = .false.
        self%l_kernel  = .false.
    end subroutine set_raw_accum

    ! closes the accumulation: the right-hand side from the numerator, the preconditioner and the kernel from the
    ! density, one wait at the end; l_kernel = .false. (the matrix-free operator) is refused
    subroutine end_accum( self, l_kernel )
        class(reconstructor_pcg), intent(inout) :: self
        logical,                  intent(in)    :: l_kernel
        real(real32), pointer :: rho(:,:,:)
        real(real64)          :: t0
        integer               :: status
        if( .not. self%l_accum )then
            self%msg = 'reconstructor_pcg%end_accum: refused: set_raw_accum has not been called'
            return
        endif
        if( .not. l_kernel )then
            self%msg = 'reconstructor_pcg%end_accum: refused: the toy has the kernel operator only'
            return
        endif
        t0 = clock_s()
        nullify(rho)
        status = 1
        if( self%l_mlx ) call end_accum_mlx(self, rho, status)
        if( status /= 0 ) return
        call self%finalize_density_accum(rho, l_kernel)
        nullify(rho)
        if( .not. self%l_precond ) return
        call self%finalize_khat()
        self%stage_s(1) = self%stage_s(1) + clock_s() - t0
        t0 = clock_s()
        status = 1
        if( self%l_mlx ) call end_accum_wait_mlx(self, status)
        self%nwaits = self%nwaits + 1
        self%stage_s(2) = self%stage_s(2) + clock_s() - t0
        if( status /= 0 )then
            self%msg = 'reconstructor_pcg%end_accum: the finalisation failed to evaluate'
            return
        endif
        self%l_rhs   = .true.
        self%l_accum = .false.
    end subroutine end_accum

    ! the ridge's scale from the raw density (h >= 0 half): the mean over the stored voxels with |q| <= padf Rnat
    ! and ceiling(|q| / padf) within the first native shells (more when they are empty) times padsc**2; a negative
    ! or non-finite density is refused
    subroutine update_lambda_from_density( self, rho_accum )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: rho_accum(:,:,:)
        real(real64) :: shell_sum(0:self%Rnat), dsum
        integer      :: shell_count(0:self%Rnat), h, k, m, rsq, rsq_lim, shell, base_shell, scale_shell, nscale
        shell_sum   = 0._real64
        shell_count = 0
        rsq_lim     = (self%padf * self%Rnat)**2
        do m = 1, self%boxpd
            do k = 1, self%boxpd
                do h = 1, self%box + 1
                    rsq = (h - 1)**2 + signed_index(k, self%boxpd)**2 + signed_index(m, self%boxpd)**2
                    if( rsq > rsq_lim ) cycle
                    if( .not. ieee_is_finite(rho_accum(h, k, m)) .or. rho_accum(h, k, m) < 0._real32 )then
                        self%msg = 'reconstructor_pcg%end_accum: refused: invalid value in the raw density'
                        return
                    endif
                    shell = min(ceiling(sqrt(real(rsq, real64)) / real(self%padf, real64)), self%Rnat)
                    shell_sum(shell)   = shell_sum(shell) + real(rho_accum(h, k, m), real64)
                    shell_count(shell) = shell_count(shell) + 1
                end do
            end do
        end do
        base_shell  = min(DATA_SCALE_NATIVE_SHELLS, self%Rnat)
        scale_shell = base_shell
        dsum        = sum(shell_sum(0:scale_shell))
        nscale      = sum(shell_count(0:scale_shell))
        do while( .not. (dsum > 0._real64) .and. scale_shell < self%Rnat )
            scale_shell = scale_shell + 1
            dsum        = dsum + shell_sum(scale_shell)
            nscale      = nscale + shell_count(scale_shell)
        end do
        if( nscale < 1 .or. .not. (dsum > 0._real64) )then
            self%msg = 'reconstructor_pcg%end_accum: refused: the data scale of an empty density'
            return
        endif
        self%data_scale = real(dsum / real(nscale, real64) * real(self%padsc, real64)**2, real32)
        if( self%l_lambda_relative )then
            self%lambda = real(real(self%lambda_rel, real64) * dsum / real(nscale, real64) * &
                               real(self%padsc, real64)**2, real32)
        endif
        if( self%l_mlx ) call update_lambda_from_density_mlx(self)
    end subroutine update_lambda_from_density

    ! the density's shell statistics on the host (pass 1: the mean of each shell's positive densities, in double)
    ! and the preconditioner's spectrum from them on the device (pass 2)
    subroutine finalize_density_accum( self, rho_accum, l_kernel )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: rho_accum(:,:,:)
        logical,                  intent(in)    :: l_kernel
        real(real64), allocatable :: shsum(:)
        integer,      allocatable :: shcnt(:)
        real(real32), allocatable :: shfloor(:), shthr(:)
        integer                   :: h, k, m, sh, rho_lim
        self%msg = ''
        call self%update_lambda_from_density(rho_accum)
        if( len(self%msg) > 0 ) return
        rho_lim = self%padf * self%Rnat
        allocate(shsum(0:rho_lim), shcnt(0:rho_lim), shfloor(0:rho_lim), shthr(0:rho_lim))
        shsum   = 0._real64
        shcnt   = 0
        shfloor = 0._real32
        shthr   = 0._real32
        do m = 1, self%boxpd
            do k = 1, self%boxpd
                do h = 1, self%box + 1
                    sh = nint(sqrt(real((h - 1)**2 + signed_index(k, self%boxpd)**2 + signed_index(m, self%boxpd)**2, &
                                        real64)))
                    if( sh > rho_lim ) cycle
                    if( .not. (rho_accum(h, k, m) > 0._real32) ) cycle
                    shsum(sh) = shsum(sh) + real(rho_accum(h, k, m), real64)
                    shcnt(sh) = shcnt(sh) + 1
                end do
            end do
        end do
        do sh = 0, rho_lim
            if( shcnt(sh) > 0 )then
                shfloor(sh) = real(real(PCG_RHO_FLOOR_FRAC, real64) * shsum(sh) / real(shcnt(sh), real64), real32)
                shthr(sh)   = real(real(PCG_RHO_SAMPLED_FRAC, real64) * shsum(sh) / real(shcnt(sh), real64), real32)
            endif
        end do
        if( self%l_mlx ) call finalize_density_accum_mlx(self, shthr, shfloor, rho_lim)
        self%l_precond = .true.
        self%l_kernel  = l_kernel
    end subroutine finalize_density_accum

    ! the kernel spectrum: the density inside padf Rnat + ceiling(sqrt(3) (iwinsz + 1/2)), the deposition envelope
    ! divided out of its inverse transform, transformed back, calibrated
    subroutine finalize_khat( self )
        class(reconstructor_pcg), intent(inout) :: self
        integer :: khat_lim
        khat_lim = self%padf * self%Rnat + ceiling(sqrt(3._real64) * (real(self%iwinsz, real64) + 0.5_real64))
        if( self%l_mlx ) call finalize_khat_mlx(self, khat_lim)
        call self%calibrate_kernel()
    end subroutine finalize_khat

    ! the analytic scale of the kernel, padsc**2
    subroutine calibrate_kernel( self )
        class(reconstructor_pcg), intent(inout) :: self
        if( self%l_mlx ) call calibrate_kernel_mlx(self)
    end subroutine calibrate_kernel

    ! the operator the solver sees, P H P with a support and H otherwise, by the device; of size zero on a refusal
    ! (message)
    function apply_normal( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
        if( self%l_mlx )then
            hp = apply_normal_mlx(self, p)
        else
            self%msg = 'reconstructor_pcg%apply_normal: '//NO_HOST_ROUTE
            allocate(hp(0, 0, 0))
        endif
    end function apply_normal

    ! H p = C^T F^-1 diag(Khat) F C p + lambda p, by the device; of size zero before end_accum and on a refusal
    ! (message)
    function apply_normal_kernel( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
        if( self%l_mlx )then
            hp = apply_normal_kernel_mlx(self, p)
        else
            self%msg = 'reconstructor_pcg%apply_normal_kernel: '//NO_HOST_ROUTE
            allocate(hp(0, 0, 0))
        endif
    end function apply_normal_kernel

    ! z = P E C^T F^-1 diag(pi) F C E r, by the device; P r without a preconditioner; of size zero on a refusal
    ! (message)
    function apply_precond( self, r ) result(z)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: r(self%box, self%box, self%box)
        real(real32), allocatable :: z(:,:,:)
        if( self%l_mlx )then
            z = apply_precond_mlx(self, r)
        else
            self%msg = 'reconstructor_pcg%apply_precond: '//NO_HOST_ROUTE
            allocate(z(0, 0, 0))
        endif
    end function apply_precond

    ! a . b in double: the device's float32 sums of the (box, box) lines, added on the host in double as the engine
    ! adds them; zero on a refusal (message)
    function dot_real_volume( self, a, b ) result(d)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: a(self%box, self%box, self%box), b(self%box, self%box, self%box)
        real(real64) :: d
        d = 0._real64
        if( self%l_mlx )then
            d = dot_real_volume_mlx(self, a, b)
        else
            self%msg = 'reconstructor_pcg%dot_real_volume: '//NO_HOST_ROUTE
        endif
    end function dot_real_volume

    ! x = window u, the shipped map
    pure subroutine window_mul( self, v )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: v(self%box, self%box, self%box)
        if( .not. self%l_mask ) return
        v = v * self%window
    end subroutine window_mul

    ! a shipped map as a start: u = x / window where the window is at least PCG_SUPPORT_DIV_MIN, zero elsewhere
    pure subroutine window_div( self, v )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: v(self%box, self%box, self%box)
        if( .not. self%l_mask ) return
        where( self%window >= PCG_SUPPORT_DIV_MIN )
            v = v / self%window
        elsewhere
            v = 0._real32
        end where
    end subroutine window_div

    ! solves against the right-hand side of end_accum from x (a shipped map, zero for a cold start), returning the
    ! shipped map in x; maxits 50 and rtol 1e-4 by default (rtol <= 0: exactly maxits); start_max_rel_resid: a
    ! non-zero start worse than it is replaced by zero. A refusal leaves x as it came (message)
    subroutine solve_accum( self, x, maxits, rtol, rel_res_hist, niters, outcome, start_max_rel_resid )
        class(reconstructor_pcg), target,   intent(inout) :: self
        real(real32),                       intent(inout) :: x(:,:,:)
        integer,                  optional, intent(in)    :: maxits
        real(real32),             optional, intent(in)    :: rtol
        real(real32), allocatable, optional, intent(out)  :: rel_res_hist(:)
        integer,                  optional, intent(out)   :: niters
        type(pcg_solver_outcome), optional, intent(out)   :: outcome
        real(real32),             optional, intent(in)    :: start_max_rel_resid
        type(pcg_solver_options)  :: options
        type(pcg_solver_outcome)  :: result
        real(real32), allocatable :: x0(:,:,:)
        real(real64)              :: t0
        if( .not. self%l_rhs )then
            self%msg = 'reconstructor_pcg%solve_accum: refused: end_accum has not been called'
            return
        endif
        if( any(shape(x) /= self%box) )then
            self%msg = 'reconstructor_pcg%solve_accum: refused: x is (box, box, box)'
            return
        endif
        options%maxits = 50
        if( present(maxits) ) options%maxits = maxits
        options%rtol = 1.e-4_real32
        if( present(rtol) ) options%rtol = rtol
        options%xtol             = PCG_XTOL
        options%residual_replace = PCG_RESID_REPLACE
        if( present(start_max_rel_resid) ) options%start_max_rel_residual = start_max_rel_resid
        x0 = x
        call self%window_div(x)
        if( self%l_mlx ) call solve_accum_mlx(self, x, options, present(outcome), result)
        if( self%solve_stopped(result, present(outcome)) )then
            self%msg = 'reconstructor_pcg%solve_accum: the solve stopped: '//trim(result%stop_reason)
            x = x0
        else
            t0 = clock_s()
            call self%window_mul(x)
            self%stage_s(4) = self%stage_s(4) + clock_s() - t0
        endif
        if( present(niters) ) niters = result%iteration_count
        if( present(rel_res_hist) )then
            if( allocated(result%rel_residual_history) ) rel_res_hist = result%rel_residual_history
        endif
        if( present(outcome) ) outcome = result
    end subroutine solve_accum

    ! SIMPLE's absolute ridge, as the operator applies it
    pure real(real32) function get_effective_lambda( self )
        class(reconstructor_pcg), intent(in) :: self
        get_effective_lambda = self%lambda
    end function get_effective_lambda

    ! the hard support (ones without one)
    subroutine get_solve_support( self, supp )
        class(reconstructor_pcg),  intent(in)  :: self
        real(real32), allocatable, intent(out) :: supp(:,:,:)
        if( self%l_mask )then
            supp = self%mask
        else
            allocate(supp(self%box, self%box, self%box), source=1._real32)
        endif
    end subroutine get_solve_support

    ! host copies of the kernel's and the preconditioner's spectra, (box + 1, boxpd, boxpd), after end_accum
    subroutine copy_spectra( self, khat, pre )
        class(reconstructor_pcg), intent(in)  :: self
        real(real32),             intent(out) :: khat(:,:,:), pre(:,:,:)
        khat = 0._real32
        pre  = 0._real32
        if( self%l_mlx ) call copy_spectra_mlx(self, khat, pre)
    end subroutine copy_spectra

    ! host copies of the right-hand side (after end_accum), the envelope and its reciprocal, (box, box, box)
    subroutine copy_volumes( self, b_rhs, env, invenv )
        class(reconstructor_pcg), intent(in)  :: self
        real(real32),             intent(out) :: b_rhs(:,:,:), env(:,:,:), invenv(:,:,:)
        b_rhs = 0._real32
        if( self%l_mlx ) call copy_volumes_mlx(self, b_rhs)
        env    = self%env
        invenv = self%invenv
    end subroutine copy_volumes

    ! the reason of the last refusal ('' when there was none)
    function message( self ) result(msg)
        class(reconstructor_pcg), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

    ! the seconds since new of: the density's statistics with the finalisation's graph, its wait, the engine (with
    ! its waits), the map's copy and window
    function stage_seconds( self ) result(s)
        class(reconstructor_pcg), intent(in) :: self
        real(real64) :: s(NSTAGES)
        s = self%stage_s
    end function stage_seconds

    ! the host's waits for the device since new: one per finalisation, the engine's, one per map copied
    integer function host_waits( self )
        class(reconstructor_pcg), intent(in) :: self
        host_waits = self%nwaits
    end function host_waits

    ! the operator the engine solves with, as the opaque device state, for a caller that works on device vectors
    ! (a tester, a benchmark): the glue's adapter, bound to this reconstructor, which must outlive it. The holder
    ! calls kill on it before it deallocates. Not allocated on a refusal (message)
    subroutine get_pcg_operator( self, op )
        class(reconstructor_pcg), target, intent(inout) :: self
        class(device_work), allocatable,  intent(out)   :: op
        if( self%l_mlx )then
            call get_pcg_operator_mlx(self, op)
        else
            self%msg = 'reconstructor_pcg%get_pcg_operator: '//NO_HOST_ROUTE
        endif
    end subroutine get_pcg_operator

    ! whether a solve is given up, x left as it came: the engine did not run or refused, or it stopped on an
    ! indefinite product that the caller did not ask to see (l_outcome: the caller takes the outcome)
    logical function solve_stopped( result, l_outcome )
        type(pcg_solver_outcome), intent(in) :: result
        logical,                  intent(in) :: l_outcome
        solve_stopped = refused(result)
        if( trim(result%stop_reason) == PCG_STOP_INDEFINITE .and. .not. l_outcome ) solve_stopped = .true.
    end function solve_stopped

    ! whether the engine did not run, or refused the solve before iterating
    logical function refused( outcome )
        type(pcg_solver_outcome), intent(in) :: outcome
        select case( trim(outcome%stop_reason) )
            case( 'not_started', 'size_differs', 'options_invalid', 'zero_rhs', 'nonpositive_rz' )
                refused = .true.
            case default
                refused = .false.
        end select
    end function refused

    ! the signed index -m/2 .. m/2 - 1 at position i of a lattice of m
    pure integer function signed_index( i, m ) result(g)
        integer, intent(in) :: i, m
        g = i - 1
        if( g >= m / 2 ) g = g - m
    end function signed_index

    ! SIMPLE's Kaiser-Bessel window at d, I0(beta sqrt(1 - (d / KBWINSZ)**2)) with beta of the window's width
    ! 2 KBWINSZ and oversampling KBALPHA; I0 by its power series to double-precision convergence
    pure real(real64) function kb_window( d ) result(k)
        real(real64), intent(in) :: d
        real(real64) :: beta, wid, x, term
        integer      :: j
        wid  = 2._real64 * real(KBWINSZ, real64)
        beta = PI * sqrt((wid / real(KBALPHA, real64))**2 * (real(KBALPHA, real64) - 0.5_real64)**2 - 0.8_real64)
        x    = beta * sqrt(max(0._real64, 1._real64 - (d / real(KBWINSZ, real64))**2))
        k    = 1._real64
        term = 1._real64
        do j = 1, 200
            term = term * (x / 2._real64)**2 / real(j, real64)**2
            k    = k + term
            if( term < epsilon(1._real64) * k ) exit
        end do
    end function kb_window

    real(real64) function clock_s()
        integer(int64) :: c, rate
        call system_clock(c, rate)
        clock_s = real(c, real64) / real(rate, real64)
    end function clock_s

end module mlxf_toy_reconstructor_pcg
