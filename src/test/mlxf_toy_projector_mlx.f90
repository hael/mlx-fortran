!@descr: the toy projector on MLX (glue): its device state, the padded transform, the expanded cube and the gather's settings
! Each procedure resolves ws to the projector's workspace and keeps the workspace's message with the projector's.
! The body stands under USE_MLX; a build without MLX compiles the stubs, which refuse.
submodule (mlxf_toy_projector) mlxf_toy_projector_mlx
#ifdef USE_MLX
use mlxf_toy_projector_workspace, only: projector_workspace
implicit none

character(len=*), parameter :: WRONG_WORK = 'projector: refused: the device state is not a projector_workspace'

contains

    module subroutine new_mlx( self, status )
        class(projector), intent(inout) :: self
        integer,          intent(out)   :: status
        allocate(projector_workspace :: self%ws, stat=status)
        if( status /= 0 ) self%msg = 'projector%new: the device state could not be allocated'
    end subroutine new_mlx

    module subroutine get_cmat_mlx( self, cmat, status )
        class(projector),             intent(inout) :: self
        complex(real32), allocatable, intent(out)   :: cmat(:,:,:)
        integer,                      intent(out)   :: status
        status = 1
        select type( ws => self%ws )
            type is( projector_workspace )
                call ws%copy_transform(cmat, status)
                if( status /= 0 ) self%msg = ws%message()
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine get_cmat_mlx

    module subroutine pad_fft_mlx( self_out, status )
        class(projector), intent(inout) :: self_out
        integer,          intent(out)   :: status
        status = 1
        select type( ws => self_out%ws )
            type is( projector_workspace )
                call ws%transform(self_out%rmat, status)
                self_out%msg = ws%message()
            class default
                self_out%msg = WRONG_WORK
        end select
    end subroutine pad_fft_mlx

    module subroutine expand_cmat_mlx( self )
        class(projector), intent(inout) :: self
        integer :: st
        select type( ws => self%ws )
            type is( projector_workspace )
                call ws%expand(st)
                self%msg = ws%message()
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine expand_cmat_mlx

    pure module logical function is_expanded_mlx( self )
        class(projector), intent(in) :: self
        is_expanded_mlx = .false.
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( projector_workspace )
                is_expanded_mlx = ws%has_cube()
        end select
    end function is_expanded_mlx

    module subroutine kill_expanded_mlx( self )
        class(projector), intent(inout) :: self
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( projector_workspace )
                call ws%kill_cube()
        end select
    end subroutine kill_expanded_mlx

    module subroutine set_fproject_form_mlx( self, form )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: form
        select type( ws => self%ws )
            type is( projector_workspace )
                call ws%set_form(form)
                self%msg = ws%message()
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine set_fproject_form_mlx

    module subroutine set_fproject_tile_mlx( self, tile, tg )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: tile, tg
        select type( ws => self%ws )
            type is( projector_workspace )
                call ws%set_tile(tile, tg)
                self%msg = ws%message()
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine set_fproject_tile_mlx

    pure module function fproject_seconds_mlx( self ) result(t)
        class(projector), intent(in) :: self
        real(real64) :: t(2)
        t = 0._real64
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( projector_workspace )
                t = ws%seconds()
        end select
    end function fproject_seconds_mlx

#else
implicit none

character(len=*), parameter :: NO_MLX = 'projector: refused: built without MLX'

contains

    module subroutine new_mlx( self, status )
        class(projector), intent(inout) :: self
        integer,          intent(out)   :: status
        status   = 1
        self%msg = NO_MLX
    end subroutine new_mlx

    module subroutine get_cmat_mlx( self, cmat, status )
        class(projector),             intent(inout) :: self
        complex(real32), allocatable, intent(out)   :: cmat(:,:,:)
        integer,                      intent(out)   :: status
        status   = 1
        self%msg = NO_MLX
    end subroutine get_cmat_mlx

    module subroutine pad_fft_mlx( self_out, status )
        class(projector), intent(inout) :: self_out
        integer,          intent(out)   :: status
        status       = 1
        self_out%msg = NO_MLX
    end subroutine pad_fft_mlx

    module subroutine expand_cmat_mlx( self )
        class(projector), intent(inout) :: self
        self%msg = NO_MLX
    end subroutine expand_cmat_mlx

    pure module logical function is_expanded_mlx( self )
        class(projector), intent(in) :: self
        is_expanded_mlx = .false.
    end function is_expanded_mlx

    module subroutine kill_expanded_mlx( self )
        class(projector), intent(inout) :: self
        self%msg = NO_MLX
    end subroutine kill_expanded_mlx

    module subroutine set_fproject_form_mlx( self, form )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: form
        self%msg = NO_MLX
    end subroutine set_fproject_form_mlx

    module subroutine set_fproject_tile_mlx( self, tile, tg )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: tile, tg
        self%msg = NO_MLX
    end subroutine set_fproject_tile_mlx

    pure module function fproject_seconds_mlx( self ) result(t)
        class(projector), intent(in) :: self
        real(real64) :: t(2)
        t = 0._real64
    end function fproject_seconds_mlx

#endif
end submodule mlxf_toy_projector_mlx
