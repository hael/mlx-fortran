!@descr: the toy polar calculator's memoization on MLX (glue): the device route's sections and memos, the resident reference tiles
! The body stands under USE_MLX; a build without MLX compiles the stubs, which refuse.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_memo_mlx
#ifdef USE_MLX
use mlxf_test_defs,             only: polarft_tile_spec
use mlxf_toy_polarft_workspace, only: polarft_workspace
implicit none

character(len=*), parameter :: WRONG_WORK = 'polarft_calc: refused: the device state is not a polarft_workspace'

contains

    module subroutine get_ref_pft_mlx( self, iref, iseven, pft )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iref
        logical,             intent(in)    :: iseven
        complex(real32),     intent(inout) :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
        integer :: ieo, st
        ieo = merge(REF_EVEN, REF_ODD, iseven)
        select type( ws => self%ws )
            type is( polarft_workspace )
                call ws(ieo)%get_section(iref, pft, st)
                if( st /= 0 ) self%msg = ws(ieo)%message()
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine get_ref_pft_mlx

    module subroutine memoize_refs_mlx( self )
        class(polarft_calc), intent(inout) :: self
        integer :: ieo, st
        select type( ws => self%ws )
            type is( polarft_workspace )
                do ieo = 1, N_REF_PARITIES
                    if( .not. ws(ieo)%has_sections() ) cycle
                    call ws(ieo)%memoize_sections(self%pftsz, self%nk, st)
                    if( st /= 0 )then
                        self%msg = ws(ieo)%message()
                        return
                    endif
                end do
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine memoize_refs_mlx

    module subroutine memoize_ref_bins_mlx( self )
        class(polarft_calc), intent(inout) :: self
        type(polarft_tile_spec) :: spec
        integer                 :: ieo, st
        spec%pftsz = self%pftsz
        spec%nk    = self%nk
        spec%rt    = self%rt
        spec%bt    = self%bt
        spec%tail  = self%tail
        select type( ws => self%ws )
            type is( polarft_workspace )
                do ieo = 1, N_REF_PARITIES
                    if( self%route == POLARFT_REF_ROUTES%device )then
                        ! the device route: the tiles from the device memos, which they replace
                        call ws(ieo)%new_from_memos(spec, st)
                    else
                        call ws(ieo)%new(spec, self%ft_ref(:, :, :, ieo), self%ft_ref2(:, :, :, ieo), st)
                    endif
                    if( st /= 0 )then
                        self%msg = ws(ieo)%message()
                        return
                    endif
                end do
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine memoize_ref_bins_mlx

#else
implicit none

character(len=*), parameter :: NO_MLX = 'polarft_calc: refused: built without MLX'

contains

    module subroutine get_ref_pft_mlx( self, iref, iseven, pft )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iref
        logical,             intent(in)    :: iseven
        complex(real32),     intent(inout) :: pft(self%pftsz, self%kfromto(1):self%kfromto(2))
        self%msg = NO_MLX
    end subroutine get_ref_pft_mlx

    module subroutine memoize_refs_mlx( self )
        class(polarft_calc), intent(inout) :: self
        self%msg = NO_MLX
    end subroutine memoize_refs_mlx

    module subroutine memoize_ref_bins_mlx( self )
        class(polarft_calc), intent(inout) :: self
        self%msg = NO_MLX
    end subroutine memoize_ref_bins_mlx

#endif
end submodule mlxf_toy_polarft_memo_mlx
