!@descr: the toy polar calculator's block scoring on MLX (glue): a block queued in its parity's workspace and collected from it
! The synchronous scorer is a submission to the first slot and its collection. The body stands under USE_MLX; a
! build without MLX compiles the stubs, which refuse.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_block_mlx
#ifdef USE_MLX
use mlxf_toy_polarft_workspace, only: polarft_workspace
implicit none

character(len=*), parameter :: WRONG_WORK = 'polarft_calc: refused: the device state is not a polarft_workspace'

contains

    module subroutine score_block_posterior_mlx( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )
        class(polarft_calc),       intent(inout) :: self
        integer,                   intent(in)    :: nb, nr
        integer,                   intent(in)    :: iptcls(nb), irefs(nr)
        real(real32),              intent(in)    :: temps(nb)
        real(real32),              intent(out)   :: dists(nr, nb)
        integer,                   intent(out)   :: irots(nr, nb)
        complex(real32), optional, intent(in)    :: banks(:,:,:)
        logical,         optional, intent(in)    :: l_bank(nb)
        type(polarft_block_spec) :: blk
        integer                  :: i
        dists    = huge(dists)
        irots    = 1
        self%msg = ''
        ! the workspace's tiles hold all the references in their order
        if( present(banks) .neqv. present(l_bank) )then
            self%msg = 'polarft_calc%score_block_posterior: refused: banks and l_bank go together'
        else if( nr /= self%nrefs )then
            self%msg = 'polarft_calc%score_block_posterior: refused: the block''s reference list is not the memoized one'
        endif
        if( len(self%msg) > 0 ) return
        if( any(irefs /= [(i, i = 1, nr)]) )then
            self%msg = 'polarft_calc%score_block_posterior: refused: the block''s reference list is not the memoized one'
            return
        endif
        blk%slot  = 1
        blk%temps = temps
        if( present(banks) )then
            blk%banks  = banks
            blk%l_bank = l_bank
        endif
        call submit_block_mlx(self, blk, iptcls)
        if( len(self%msg) > 0 ) return
        call self%collect_block(1, dists, irots)
    end subroutine score_block_posterior_mlx

    module subroutine submit_block_mlx( self, blk, iptcls )
        class(polarft_calc),      intent(inout) :: self
        type(polarft_block_spec), intent(inout) :: blk
        integer,                  intent(in)    :: iptcls(:)
        integer :: ieo, st
        call prepare_block(self, blk, iptcls, ieo)
        if( len(self%msg) > 0 ) return
        select type( ws => self%ws )
            type is( polarft_workspace )
                call ws(ieo)%submit(blk, self%ft_ctf2, self%ft_ptcl_ctf, st)
                if( st /= 0 )then
                    self%msg = ws(ieo)%message()
                    return
                endif
            class default
                self%msg = WRONG_WORK
                return
        end select
        self%slot_ieo(blk%slot) = ieo
    end subroutine submit_block_mlx

    module subroutine collect_block_mlx( self, slot, ieo, dists, irots )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot, ieo
        real(real32),        intent(inout) :: dists(:,:)
        integer,             intent(inout) :: irots(:,:)
        integer :: st
        select type( ws => self%ws )
            type is( polarft_workspace )
                call ws(ieo)%collect(slot, dists, irots, st)
                if( st /= 0 ) self%msg = ws(ieo)%message()
                call ws(ieo)%take_rows(self%rows)
            class default
                self%msg = WRONG_WORK
        end select
    end subroutine collect_block_mlx

    pure module function stage_seconds_mlx( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(5)
        integer      :: ieo
        t = 0._real64
        if( .not. allocated(self%ws) ) return
        select type( ws => self%ws )
            type is( polarft_workspace )
                do ieo = 1, size(ws)
                    t = t + ws(ieo)%stage_seconds()
                end do
        end select
    end function stage_seconds_mlx

    ! a block's checks and host inputs for the workspace: blk comes with its slot, temperatures and banks, and
    ! leaves with everything the workspace reads; ieo is the block's parity. The variates set for the block and
    ! the banks set for it are consumed whether it may be queued or is refused (message)
    subroutine prepare_block( self, blk, iptcls, ieo )
        class(polarft_calc),      intent(inout) :: self
        type(polarft_block_spec), intent(inout) :: blk
        integer,                  intent(in)    :: iptcls(:)
        integer,                  intent(out)   :: ieo
        ieo = 0
        if( allocated(self%u_next) ) call move_alloc(self%u_next, blk%u)
        if( allocated(self%banks_next) .and. .not. allocated(blk%banks) )then
            call move_alloc(self%banks_next, blk%banks)
            call move_alloc(self%l_bank_next, blk%l_bank)
        endif
        if( .not. self%existence )then
            self%msg = 'polarft_calc: refused: no calculator (new)'
        else if( blk%slot < 1 .or. blk%slot > NSLOTS )then
            self%msg = 'polarft_calc: refused: no such slot'
        else if( self%l_refs_pending )then
            self%msg = 'polarft_calc: refused: references were set and not memoized (memoize_refs)'
        else if( self%ref_gen_bins /= self%ref_gen )then
            self%msg = 'polarft_calc: refused: the reference bins are not those of the memoized references and '//&
                &'tile plan (memoize_ref_bins)'
        else if( self%ptcl_gen_memo /= self%ptcl_gen )then
            self%msg = 'polarft_calc: refused: the particle memos are not those of the particles set (memoize_ptcls)'
        else if( .not. self%l_weights )then
            self%msg = 'polarft_calc: refused: no shell weights (set_sigma2_weights)'
        else if( size(iptcls) < 1 )then
            self%msg = 'polarft_calc: refused: an empty block'
        else if( any(iptcls < self%pfromto(1) .or. iptcls > self%pfromto(2)) )then
            self%msg = 'polarft_calc: refused: a particle index is outside the calculator''s range'
        else if( .not. allocated(blk%u) )then
            self%msg = 'polarft_calc: refused: no variates for the block (set_block_variates)'
        endif
        if( len(self%msg) > 0 ) return
        blk%islots = self%pinds(iptcls)
        if( any(blk%islots < 1) )then
            self%msg = 'polarft_calc: refused: a particle index is not in the batch'
            return
        endif
        if( any(self%iseven(blk%islots) .neqv. self%iseven(blk%islots(1))) )then
            self%msg = 'polarft_calc: refused: the block mixes the two halves'
            return
        endif
        ieo         = merge(REF_EVEN, REF_ODD, self%iseven(blk%islots(1)))
        blk%weights = self%sigma2_wk(:, ieo)
        blk%wsq     = self%wsqsums_ptcls(blk%islots)
        blk%rows    = self%l_rows
        blk%profile = self%l_profile
    end subroutine prepare_block

#else
implicit none

character(len=*), parameter :: NO_MLX = 'polarft_calc: refused: built without MLX'

contains

    module subroutine score_block_posterior_mlx( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )
        class(polarft_calc),       intent(inout) :: self
        integer,                   intent(in)    :: nb, nr
        integer,                   intent(in)    :: iptcls(nb), irefs(nr)
        real(real32),              intent(in)    :: temps(nb)
        real(real32),              intent(out)   :: dists(nr, nb)
        integer,                   intent(out)   :: irots(nr, nb)
        complex(real32), optional, intent(in)    :: banks(:,:,:)
        logical,         optional, intent(in)    :: l_bank(nb)
        dists    = huge(dists)
        irots    = 1
        self%msg = NO_MLX
    end subroutine score_block_posterior_mlx

    module subroutine submit_block_mlx( self, blk, iptcls )
        class(polarft_calc),      intent(inout) :: self
        type(polarft_block_spec), intent(inout) :: blk
        integer,                  intent(in)    :: iptcls(:)
        self%msg = NO_MLX
    end subroutine submit_block_mlx

    module subroutine collect_block_mlx( self, slot, ieo, dists, irots )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot, ieo
        real(real32),        intent(inout) :: dists(:,:)
        integer,             intent(inout) :: irots(:,:)
        self%msg = NO_MLX
    end subroutine collect_block_mlx

    pure module function stage_seconds_mlx( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(5)
        t = 0._real64
    end function stage_seconds_mlx

#endif
end submodule mlxf_toy_polarft_block_mlx
