!@descr: the toy reconstructor_pcg on MLX (glue): its device state, the device forms of the operator, the engine's adapter and the transfers
! Each glue procedure resolves ws to the reconstructor's workspace. The device forms of the operator's five
! procedures (on device arrays, unevaluated) are private here: the adapter the engine solves through calls them,
! and so do the glue procedures of the host forms, which send a host volume to the device, apply the device form
! and bring the result back. The body stands under USE_MLX; a build without MLX compiles the stubs, which refuse.
submodule (mlxf_toy_reconstructor_pcg) mlxf_toy_reconstructor_pcg_mlx
#ifdef USE_MLX
use mlxf,                                 only: mlx_array, mlx_from, mlx_to, mlx_is_live
use mlxf_toy_pcg_solver_mlx,              only: pcg_operator, pcg_solve
use mlxf_toy_reconstructor_pcg_workspace, only: reconstructor_pcg_workspace
implicit none

character(len=*), parameter :: WRONG_WORK = 'reconstructor_pcg: refused: the device state is not a '// &
    &'reconstructor_pcg_workspace'

! the rank-1 view of a reconstruction operator for the engine (SIMPLE's private adapter); kill lets the client go
type, extends(pcg_operator) :: reconstructor_pcg_adapter
    class(reconstructor_pcg), pointer :: client => null()
  contains
    procedure :: size    => reconstruction_vector_size
    procedure :: apply   => reconstruction_vector_apply
    procedure :: precond => reconstruction_vector_precond
    procedure :: dot     => reconstruction_vector_dot
    procedure :: kill    => reconstruction_vector_kill
end type reconstructor_pcg_adapter

contains

    module subroutine new_mlx( self, status )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(out)   :: status
        type(reconstructor_pcg_workspace), allocatable :: ws
        allocate(ws, stat=status)
        if( status /= 0 )then
            self%msg = 'reconstructor_pcg%new: the device state could not be allocated'
            return
        endif
        call ws%new(self%box)
        call ws%set_envelopes(self%env, self%invenv)
        call ws%set_ridge(self%lambda)
        call move_alloc(ws, self%ws)
    end subroutine new_mlx

    module subroutine set_window_sphere_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                if( self%l_mask )then
                    call ws%set_mask(self%mask)
                else
                    call ws%set_mask()
                endif
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine set_window_sphere_mlx

    module subroutine set_raw_accum_mlx( self, b, d )
        class(reconstructor_pcg), intent(inout) :: self
        complex(real32),          intent(in)    :: b(:,:,:)
        real(real32),             intent(in)    :: d(:,:,:)
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%set_raw_accum(b, d)
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine set_raw_accum_mlx

    module subroutine end_accum_mlx( self, rho, status )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32), pointer,    intent(inout) :: rho(:,:,:)
        integer,                  intent(out)   :: status
        type(mlx_array) :: v
        status = 1
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                v = ws%fold_rhs()
                call ws%deapod_mul(v)
                call ws%mask_mul(v)
                call ws%set_rhs(v)
                call v%kill()
                call ws%density_view(rho, status)
                if( status /= 0 ) self%msg = 'reconstructor_pcg%end_accum: the raw density cannot be read: '// &
                    &ws%message()
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine end_accum_mlx

    module subroutine end_accum_wait_mlx( self, status )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(out)   :: status
        status = 1
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%finish(status)
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine end_accum_wait_mlx

    module subroutine update_lambda_from_density_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%set_ridge(self%lambda)
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine update_lambda_from_density_mlx

    module subroutine finalize_density_accum_mlx( self, shthr, shfloor, rho_lim )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: shthr(0:), shfloor(0:)
        integer,                  intent(in)    :: rho_lim
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%build_precond(shthr, shfloor, rho_lim)
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine finalize_density_accum_mlx

    module subroutine finalize_khat_mlx( self, khat_lim )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(in)    :: khat_lim
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%build_kernel(khat_lim, real(self%dep1d, real32))
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine finalize_khat_mlx

    module subroutine calibrate_kernel_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%scale_kernel(self%padsc**2)
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine calibrate_kernel_mlx

    ! ---- the device forms of the operator: device arrays in, unevaluated device arrays out --------------------------

    ! v = P v on the device (identity without a support)
    subroutine mask_mul_device( self, v )
        class(reconstructor_pcg), intent(in)    :: self
        type(mlx_array),          intent(inout) :: v
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%mask_mul(v)
        end select
    end subroutine mask_mul_device

    ! the operator the solver sees, P H P with a support and H otherwise
    function apply_normal_device( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        type(mlx_array),          intent(in)    :: p
        type(mlx_array) :: hp, pm
        pm = p
        call mask_mul_device(self, pm)
        hp = apply_normal_kernel_device(self, pm)
        call mask_mul_device(self, hp)
    end function apply_normal_device

    ! H p = C^T F^-1 diag(Khat) F C p + lambda p; an empty result before end_accum (message)
    function apply_normal_kernel_device( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        type(mlx_array),          intent(in)    :: p
        type(mlx_array) :: hp
        if( .not. self%l_kernel )then
            self%msg = 'reconstructor_pcg%apply_normal_kernel: refused: no kernel has been built'
            return
        endif
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                hp = ws%kernel_product(p)
                call ws%add_ridge(p, hp)
            class default
                self%msg = WRONG_WORK
        end select
    end function apply_normal_kernel_device

    ! z = P E C^T F^-1 diag(pi) F C E r; P r without a preconditioner
    function apply_precond_device( self, r ) result(z)
        class(reconstructor_pcg), intent(inout) :: self
        type(mlx_array),          intent(in)    :: r
        type(mlx_array) :: z
        if( .not. self%l_precond )then
            z = r
            call mask_mul_device(self, z)
            return
        endif
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                z = ws%precond_product(r)
            class default
                self%msg = WRONG_WORK
        end select
    end function apply_precond_device

    ! the device half of a . b: the (box, box) partial sums of the lines, which the engine adds in double
    function dot_real_volume_device( self, a, b ) result(d)
        class(reconstructor_pcg), intent(in) :: self
        type(mlx_array),          intent(in) :: a, b
        type(mlx_array) :: d
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                d = ws%line_dots(a, b)
        end select
    end function dot_real_volume_device

    ! ---- the host forms: a host volume to the device, the device form, the result back ------------------------------

    ! a device volume brought to the host as (box, box, box); of size zero when the device form made none
    subroutine volume_to_host( self, yd, y )
        class(reconstructor_pcg),  intent(in)  :: self
        type(mlx_array),           intent(in)  :: yd
        real(real32), allocatable, intent(out) :: y(:,:,:)
        if( .not. mlx_is_live(yd) )then
            allocate(y(0, 0, 0))
            return
        endif
        allocate(y(self%box, self%box, self%box))
        call mlx_to(y, yd)
    end subroutine volume_to_host

    module subroutine mask_mul_mlx( self, v )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(inout) :: v(self%box, self%box, self%box)
        type(mlx_array) :: vd
        vd = mlx_from(v)
        call mask_mul_device(self, vd)
        call mlx_to(v, vd)
    end subroutine mask_mul_mlx

    module function apply_normal_mlx( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
        type(mlx_array)           :: pd, hd
        pd = mlx_from(p)
        hd = apply_normal_device(self, pd)
        call volume_to_host(self, hd, hp)
    end function apply_normal_mlx

    module function apply_normal_kernel_mlx( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
        type(mlx_array)           :: pd, hd
        pd = mlx_from(p)
        hd = apply_normal_kernel_device(self, pd)
        call volume_to_host(self, hd, hp)
    end function apply_normal_kernel_mlx

    module function apply_precond_mlx( self, r ) result(z)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: r(self%box, self%box, self%box)
        real(real32), allocatable :: z(:,:,:)
        type(mlx_array)           :: rd, zd
        rd = mlx_from(r)
        zd = apply_precond_device(self, rd)
        call volume_to_host(self, zd, z)
    end function apply_precond_mlx

    module function dot_real_volume_mlx( self, a, b ) result(d)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: a(self%box, self%box, self%box), b(self%box, self%box, self%box)
        real(real64)              :: d
        type(mlx_array)           :: ad, bd, dd
        real(real32), allocatable :: part(:)
        d  = 0._real64
        ad = mlx_from(a)
        bd = mlx_from(b)
        dd = dot_real_volume_device(self, ad, bd)
        if( .not. mlx_is_live(dd) )then
            self%msg = WRONG_WORK
            return
        endif
        allocate(part(dd%size()))
        call mlx_to(part, dd)
        d = sum(real(part, real64))
    end function dot_real_volume_mlx

    ! ---- the solve ---------------------------------------------------------------------------------------------------

    module subroutine solve_accum_mlx( self, x, options, l_outcome, result )
        class(reconstructor_pcg), target, intent(inout) :: self
        real(real32),                     intent(inout) :: x(:,:,:)
        type(pcg_solver_options),         intent(in)    :: options
        logical,                          intent(in)    :: l_outcome
        type(pcg_solver_outcome),         intent(out)   :: result
        type(reconstructor_pcg_adapter) :: op
        type(mlx_array)                 :: xd, b
        real(real64)                    :: t0
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                t0 = glue_clock_s()
                xd = mlx_from(x)
                b  = ws%rhs()
                op%client => self
                call pcg_solve(op, b, xd, options, result)
                self%nwaits     = self%nwaits + engine_waits(result)
                self%stage_s(3) = self%stage_s(3) + glue_clock_s() - t0
                if( self%solve_stopped(result, l_outcome) ) return
                t0 = glue_clock_s()
                call mlx_to(x, xd)
                self%nwaits     = self%nwaits + 1
                self%stage_s(4) = self%stage_s(4) + glue_clock_s() - t0
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine solve_accum_mlx

    ! the engine's waits, by its schedule: one before the loop (two from a used non-zero start), two per iteration
    ! done, one for an iteration stopped on an indefinite product
    integer function engine_waits( outcome ) result(n)
        type(pcg_solver_outcome), intent(in) :: outcome
        n = 0
        if( trim(outcome%stop_reason) == 'size_differs' .or. trim(outcome%stop_reason) == 'options_invalid' ) return
        n = 1
        if( trim(outcome%stop_reason) == 'zero_rhs' ) return
        n = n + 2 * outcome%iteration_count
        if( outcome%start_norm > 0._real32 .or. outcome%start_rejected ) n = n + 1
        if( trim(outcome%stop_reason) == PCG_STOP_INDEFINITE ) n = n + 1
    end function engine_waits

    ! the wall clock in seconds (the glue's own: a submodule calls no private procedure of its module)
    real(real64) function glue_clock_s() result(t)
        integer(int64) :: c, rate
        call system_clock(c, rate)
        t = real(c, real64) / real(rate, real64)
    end function glue_clock_s

    ! ---- copies and the operator handed out --------------------------------------------------------------------------

    module subroutine copy_spectra_mlx( self, khat, pre )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: khat(:,:,:), pre(:,:,:)
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%copy_spectra(khat, pre)
        end select
    end subroutine copy_spectra_mlx

    module subroutine copy_volumes_mlx( self, b_rhs )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: b_rhs(:,:,:)
        select type( ws => self%ws )
            type is( reconstructor_pcg_workspace )
                call ws%copy_rhs(b_rhs)
        end select
    end subroutine copy_volumes_mlx

    module subroutine get_pcg_operator_mlx( self, op )
        class(reconstructor_pcg), target, intent(inout) :: self
        class(device_work), allocatable,  intent(out)   :: op
        type(reconstructor_pcg_adapter), allocatable :: adapter
        allocate(adapter)
        adapter%client => self
        call move_alloc(adapter, op)
    end subroutine get_pcg_operator_mlx

    ! ---- the adapter -------------------------------------------------------------------------------------------------

    integer function reconstruction_vector_size( self ) result(n)
        class(reconstructor_pcg_adapter), intent(in) :: self
        n = 0
        if( associated(self%client) ) n = self%client%box**3
    end function reconstruction_vector_size

    subroutine reconstruction_vector_apply( self, x, y )
        class(reconstructor_pcg_adapter), intent(inout) :: self
        type(mlx_array),                  intent(in)    :: x
        type(mlx_array),                  intent(out)   :: y
        y = apply_normal_device(self%client, x)
    end subroutine reconstruction_vector_apply

    subroutine reconstruction_vector_precond( self, r, z )
        class(reconstructor_pcg_adapter), intent(inout) :: self
        type(mlx_array),                  intent(in)    :: r
        type(mlx_array),                  intent(out)   :: z
        z = apply_precond_device(self%client, r)
    end subroutine reconstruction_vector_precond

    function reconstruction_vector_dot( self, a, b ) result(d)
        class(reconstructor_pcg_adapter), intent(in) :: self
        type(mlx_array),                  intent(in) :: a, b
        type(mlx_array) :: d
        d = dot_real_volume_device(self%client, a, b)
    end function reconstruction_vector_dot

    subroutine reconstruction_vector_kill( self )
        class(reconstructor_pcg_adapter), intent(inout) :: self
        nullify(self%client)
    end subroutine reconstruction_vector_kill

#else
implicit none

character(len=*), parameter :: NO_MLX = 'reconstructor_pcg: refused: built without MLX'

contains

    module subroutine new_mlx( self, status )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(out)   :: status
        status   = 1
        self%msg = NO_MLX
    end subroutine new_mlx

    module subroutine set_window_sphere_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
        self%msg = NO_MLX
    end subroutine set_window_sphere_mlx

    module subroutine set_raw_accum_mlx( self, b, d )
        class(reconstructor_pcg), intent(inout) :: self
        complex(real32),          intent(in)    :: b(:,:,:)
        real(real32),             intent(in)    :: d(:,:,:)
        self%msg = NO_MLX
    end subroutine set_raw_accum_mlx

    module subroutine end_accum_mlx( self, rho, status )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32), pointer,    intent(inout) :: rho(:,:,:)
        integer,                  intent(out)   :: status
        nullify(rho)
        status   = 1
        self%msg = NO_MLX
    end subroutine end_accum_mlx

    module subroutine end_accum_wait_mlx( self, status )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(out)   :: status
        status   = 1
        self%msg = NO_MLX
    end subroutine end_accum_wait_mlx

    module subroutine update_lambda_from_density_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
        self%msg = NO_MLX
    end subroutine update_lambda_from_density_mlx

    module subroutine finalize_density_accum_mlx( self, shthr, shfloor, rho_lim )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: shthr(0:), shfloor(0:)
        integer,                  intent(in)    :: rho_lim
        self%msg = NO_MLX
    end subroutine finalize_density_accum_mlx

    module subroutine finalize_khat_mlx( self, khat_lim )
        class(reconstructor_pcg), intent(inout) :: self
        integer,                  intent(in)    :: khat_lim
        self%msg = NO_MLX
    end subroutine finalize_khat_mlx

    module subroutine calibrate_kernel_mlx( self )
        class(reconstructor_pcg), intent(inout) :: self
        self%msg = NO_MLX
    end subroutine calibrate_kernel_mlx

    module subroutine mask_mul_mlx( self, v )
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(inout) :: v(self%box, self%box, self%box)
        self%msg = NO_MLX
    end subroutine mask_mul_mlx

    module function apply_normal_mlx( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
        allocate(hp(0, 0, 0))
        self%msg = NO_MLX
    end function apply_normal_mlx

    module function apply_normal_kernel_mlx( self, p ) result(hp)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: p(self%box, self%box, self%box)
        real(real32), allocatable :: hp(:,:,:)
        allocate(hp(0, 0, 0))
        self%msg = NO_MLX
    end function apply_normal_kernel_mlx

    module function apply_precond_mlx( self, r ) result(z)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: r(self%box, self%box, self%box)
        real(real32), allocatable :: z(:,:,:)
        allocate(z(0, 0, 0))
        self%msg = NO_MLX
    end function apply_precond_mlx

    module function dot_real_volume_mlx( self, a, b ) result(d)
        class(reconstructor_pcg), intent(inout) :: self
        real(real32),             intent(in)    :: a(self%box, self%box, self%box), b(self%box, self%box, self%box)
        real(real64) :: d
        d        = 0._real64
        self%msg = NO_MLX
    end function dot_real_volume_mlx

    module subroutine solve_accum_mlx( self, x, options, l_outcome, result )
        class(reconstructor_pcg), target, intent(inout) :: self
        real(real32),                     intent(inout) :: x(:,:,:)
        type(pcg_solver_options),         intent(in)    :: options
        logical,                          intent(in)    :: l_outcome
        type(pcg_solver_outcome),         intent(out)   :: result
        self%msg = NO_MLX
    end subroutine solve_accum_mlx

    module subroutine copy_spectra_mlx( self, khat, pre )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: khat(:,:,:), pre(:,:,:)
    end subroutine copy_spectra_mlx

    module subroutine copy_volumes_mlx( self, b_rhs )
        class(reconstructor_pcg), intent(in)    :: self
        real(real32),             intent(inout) :: b_rhs(:,:,:)
    end subroutine copy_volumes_mlx

    module subroutine get_pcg_operator_mlx( self, op )
        class(reconstructor_pcg), target, intent(inout) :: self
        class(device_work), allocatable,  intent(out)   :: op
        self%msg = NO_MLX
    end subroutine get_pcg_operator_mlx

#endif
end submodule mlxf_toy_reconstructor_pcg_mlx
