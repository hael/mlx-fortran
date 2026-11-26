!@descr: the toy batch projector on MLX (glue): the gather through the projector's workspace, to the host or left on the device
! The resident bank crosses to the calculator as a projector_bank, an opaque object to every host file. The body
! stands under USE_MLX; a build without MLX compiles the stubs, which refuse.
submodule (mlxf_toy_projector_pft_batch) mlxf_toy_projector_pft_batch_mlx
#ifdef USE_MLX
use mlxf,                         only: mlx_array, mlx_to, reshape
use mlxf_toy_projector_workspace, only: projector_workspace, projector_bank
implicit none

character(len=*), parameter :: WRONG_WORK = 'fproject_polar_batch_opt: refused: the device state is not a '// &
    &'projector_workspace'

contains

    module subroutine fproject_polar_batch_opt_mlx( vol_pad, spec, refs_state )
        class(projector),    intent(inout) :: vol_pad
        type(fproject_spec), intent(in)    :: spec
        complex(real32),     intent(inout) :: refs_state(:,:,:)
        type(mlx_array) :: bank
        integer         :: st
        call project_bank(vol_pad, spec, bank)
        if( len(vol_pad%message()) > 0 ) return
        call mlx_to(refs_state, reshape(bank, shape(refs_state)), status=st)
        if( st /= 0 )then
            call vol_pad%set_message('fproject_polar_batch_opt: the bank could not be copied to the host')
            refs_state = cmplx(0._real32, 0._real32, real32)
        endif
    end subroutine fproject_polar_batch_opt_mlx

    module subroutine fproject_polar_batch_resident_mlx( vol_pad, spec, bank )
        class(projector),                intent(inout) :: vol_pad
        type(fproject_spec),             intent(in)    :: spec
        class(device_work), allocatable, intent(out)   :: bank
        type(projector_bank), allocatable :: made
        allocate(made)
        call project_bank(vol_pad, spec, made%sections)
        if( len(vol_pad%message()) > 0 )then
            call made%kill()
            return
        endif
        call move_alloc(made, bank)
    end subroutine fproject_polar_batch_resident_mlx

    ! the workspace's gather of spec into bank (pftsz nk, nspace), evaluated; the workspace's message becomes
    ! vol_pad's
    subroutine project_bank( vol_pad, spec, bank )
        class(projector),    intent(inout) :: vol_pad
        type(fproject_spec), intent(in)    :: spec
        type(mlx_array),     intent(out)   :: bank
        integer :: st
        select type( ws => vol_pad%ws )
            type is( projector_workspace )
                call ws%project(spec, bank, st)
                call vol_pad%set_message(ws%message())
            class default
                call vol_pad%set_message(WRONG_WORK)
        end select
    end subroutine project_bank

#else
implicit none

character(len=*), parameter :: NO_MLX = 'fproject_polar_batch_opt: refused: built without MLX'

contains

    module subroutine fproject_polar_batch_opt_mlx( vol_pad, spec, refs_state )
        class(projector),    intent(inout) :: vol_pad
        type(fproject_spec), intent(in)    :: spec
        complex(real32),     intent(inout) :: refs_state(:,:,:)
        call vol_pad%set_message(NO_MLX)
    end subroutine fproject_polar_batch_opt_mlx

    module subroutine fproject_polar_batch_resident_mlx( vol_pad, spec, bank )
        class(projector),                intent(inout) :: vol_pad
        type(fproject_spec),             intent(in)    :: spec
        class(device_work), allocatable, intent(out)   :: bank
        call vol_pad%set_message(NO_MLX)
    end subroutine fproject_polar_batch_resident_mlx

#endif
end submodule mlxf_toy_projector_pft_batch_mlx
