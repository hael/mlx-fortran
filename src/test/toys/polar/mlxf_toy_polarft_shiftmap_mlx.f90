!@descr: the toy polar calculator's shift maps on MLX (glue): a map's resident data on both parities, the maps of a block, the inquiries
! The body stands under USE_MLX; a build without MLX compiles the stubs, which refuse.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_shiftmap_mlx
#ifdef USE_MLX
use mlxf_toy_polarft_workspace, only: polarft_workspace
implicit none

character(len=*), parameter :: WRONG_WORK = 'polarft_calc: refused: the device state is not a polarft_workspace'

contains

    module subroutine new_shiftmap_mlx( self, spec )
        class(polarft_calc),    intent(inout) :: self
        type(polarft_map_spec), intent(inout) :: spec
        integer :: ieo, st
        select type( ws => self%ws )
            type is( polarft_workspace )
                do ieo = 1, N_REF_PARITIES
                    spec%weights = self%sigma2_wk8(self%kfromto(1):spec%kstop, ieo)
                    call ws(ieo)%prepare_maps(spec, self%ft_ref_terms(:, :, :, ieo), st)
                    if( st /= 0 )then
                        self%msg = ws(ieo)%message()
                        call ws(REF_EVEN)%kill_map(spec%imap)
                        return
                    endif
                end do
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine new_shiftmap_mlx

    module subroutine kill_shiftmap_mlx( self, imap )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: imap
        integer :: ieo
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( polarft_workspace )
                do ieo = 1, size(ws)
                    if( imap > 0 )then
                        call ws(ieo)%kill_map(imap)
                    else
                        call ws(ieo)%kill_maps()
                    endif
                end do
        end select
    end subroutine kill_shiftmap_mlx

    module subroutine shiftmap_mode_mlx( self, mblk, res )
        class(polarft_calc),     intent(inout) :: self
        type(polarft_map_block), intent(in)    :: mblk
        type(polar_map_results), intent(out)   :: res
        select type( ws => self%ws )
            type is( polarft_workspace )
                call ws(self%sm_ieo)%score_maps(mblk, self%ft_ctf2, self%ft_ptcl_ctf, res)
                self%msg = ws(self%sm_ieo)%message()
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine shiftmap_mode_mlx

    pure module integer function shiftmap_order_mlx( self, imap )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        shiftmap_order_mlx = 0
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( polarft_workspace )
                shiftmap_order_mlx = ws(REF_EVEN)%map_order(imap)
        end select
    end function shiftmap_order_mlx

    pure module function shiftmap_term_counts_mlx( self, imap ) result(counts)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        integer(int64) :: counts(2)
        counts = 0_int64
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( polarft_workspace )
                counts = ws(REF_EVEN)%map_term_counts(imap)
        end select
    end function shiftmap_term_counts_mlx

    pure module function shiftmap_seconds_mlx( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(4)
        integer      :: ieo
        t = 0._real64
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( polarft_workspace )
                do ieo = 1, size(ws)
                    t = t + ws(ieo)%map_seconds()
                end do
        end select
    end function shiftmap_seconds_mlx

#else
implicit none

character(len=*), parameter :: NO_MLX = 'polarft_calc: refused: built without MLX'

contains

    module subroutine new_shiftmap_mlx( self, spec )
        class(polarft_calc),    intent(inout) :: self
        type(polarft_map_spec), intent(inout) :: spec
        self%msg = NO_MLX
    end subroutine new_shiftmap_mlx

    module subroutine kill_shiftmap_mlx( self, imap )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: imap
        self%msg = NO_MLX
    end subroutine kill_shiftmap_mlx

    module subroutine shiftmap_mode_mlx( self, mblk, res )
        class(polarft_calc),     intent(inout) :: self
        type(polarft_map_block), intent(in)    :: mblk
        type(polar_map_results), intent(out)   :: res
        self%msg = NO_MLX
    end subroutine shiftmap_mode_mlx

    pure module integer function shiftmap_order_mlx( self, imap )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        shiftmap_order_mlx = 0
    end function shiftmap_order_mlx

    pure module function shiftmap_term_counts_mlx( self, imap ) result(counts)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        integer(int64) :: counts(2)
        counts = 0_int64
    end function shiftmap_term_counts_mlx

    pure module function shiftmap_seconds_mlx( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(4)
        t = 0._real64
    end function shiftmap_seconds_mlx

#endif
end submodule mlxf_toy_polarft_shiftmap_mlx
