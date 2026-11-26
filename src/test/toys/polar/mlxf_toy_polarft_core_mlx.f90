!@descr: the toy polar calculator's core on MLX (glue): the device state of a new calculator, the device route's projected bank
! The body stands under USE_MLX; a build without MLX compiles the stubs, which refuse.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_core_mlx
#ifdef USE_MLX
use mlxf_toy_polarft_workspace,   only: polarft_workspace
use mlxf_toy_projector_workspace, only: projector_bank
use mlxf_toy_projector_pft_batch, only: fproject_polar_batch_resident
implicit none

character(len=*), parameter :: WRONG_WORK = 'polarft_calc: refused: the device state is not a polarft_workspace'
character(len=*), parameter :: WRONG_BANK = 'vol_pad2ref_pfts_opt: refused: the projected bank is not a projector_bank'

contains

    module subroutine new_mlx( self, status )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(out)   :: status
        allocate(polarft_workspace :: self%ws(N_REF_PARITIES), stat=status)
        if( status /= 0 ) self%msg = 'polarft_calc%new: the device state could not be allocated'
    end subroutine new_mlx

    module subroutine vol_pad2ref_pfts_opt_mlx( self, vol_pad, eulspace, state, iseven )
        class(polarft_calc), intent(inout) :: self
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        integer,             intent(in)    :: state
        logical,             intent(in)    :: iseven
        class(device_work), allocatable :: bank
        integer                         :: iref_from, ieo, st
        iref_from = (state - 1) * self%nspace + 1
        ieo       = merge(REF_EVEN, REF_ODD, iseven)
        ! the bank stays on the device, with the parity's workspace, until memoize_refs
        call fproject_polar_batch_resident(vol_pad, eulspace, self%nspace, self, bank)
        if( len(vol_pad%message()) > 0 )then
            self%msg = vol_pad%message()
            return
        endif
        st = 1
        if( allocated(bank) )then
            ! what the projector's class hands over is resolved here, with this class's own device state
            select type( bank )
                type is( projector_bank )
                    select type( ws => self%ws )
                        type is( polarft_workspace )
                            call ws(ieo)%set_sections(bank%sections, iref_from, self%nrefs, st)
                            if( st /= 0 ) self%msg = ws(ieo)%message()
                        class default
                            self%msg = WRONG_WORK
                    end select
                class default
                    self%msg = WRONG_BANK
            end select
            call bank%kill()
            deallocate(bank)
        else
            self%msg = WRONG_BANK
        endif
        if( st /= 0 ) return
        self%l_refs_pending = .true.
    end subroutine vol_pad2ref_pfts_opt_mlx

#else
implicit none

character(len=*), parameter :: NO_MLX = 'polarft_calc: refused: built without MLX'

contains

    module subroutine new_mlx( self, status )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(out)   :: status
        status   = 1
        self%msg = NO_MLX
    end subroutine new_mlx

    module subroutine vol_pad2ref_pfts_opt_mlx( self, vol_pad, eulspace, state, iseven )
        class(polarft_calc), intent(inout) :: self
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        integer,             intent(in)    :: state
        logical,             intent(in)    :: iseven
        self%msg = NO_MLX
    end subroutine vol_pad2ref_pfts_opt_mlx

#endif
end submodule mlxf_toy_polarft_core_mlx
