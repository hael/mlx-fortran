!@descr: the toy polar calculator's block scoring on MLX (glue): a block queued in its parity's workspace and collected from it
! The synchronous scorer is a submission to the first slot and its collection. A block's reference list crosses
! here: every reference in order is the dense block, any other list the workspace's list form. The body stands
! under USE_MLX; a build without MLX compiles the stubs, which refuse.
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
        dists    = huge(dists)
        irots    = 1
        self%msg = ''
        if( present(banks) .neqv. present(l_bank) )then
            self%msg = 'polarft_calc%score_block_posterior: refused: banks and l_bank go together'
            return
        endif
        blk%slot  = 1
        blk%irefs = irefs
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
                call ws(ieo)%submit(blk, self%ft_ptcl_wterms, st)
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
        integer :: i
        ieo = 0
        if( allocated(self%u_next) ) call move_alloc(self%u_next, blk%u)
        ! a pending pair list makes the block a pair-list block
        if( allocated(self%pair_ptr_next) )then
            call move_alloc(self%pair_ptr_next, blk%pair_ptr)
            if( allocated(blk%irefs) ) deallocate(blk%irefs)
            if( allocated(self%refs_next) ) call move_alloc(self%refs_next, blk%irefs)
        endif
        ! a list given with the block replaces the pending one, which is consumed either way
        if( allocated(self%refs_next) )then
            if( .not. allocated(blk%irefs) )then
                call move_alloc(self%refs_next, blk%irefs)
            else
                deallocate(self%refs_next)
            endif
        endif
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
        else if( self%ref_gen_tiles /= self%ref_gen )then
            self%msg = 'polarft_calc: refused: the reference tiles are not those of the memoized references and '//&
                &'tile plan (memoize_refs)'
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
        if( allocated(blk%pair_ptr) )then
            if( size(blk%pair_ptr) /= size(iptcls) + 1 ) self%msg = 'polarft_calc: refused: the pair list is not of '//&
                &'the block''s particles'
            if( len(self%msg) > 0 ) return
        else if( allocated(blk%irefs) )then
            self%msg = block_list_refusal(self, blk%irefs)
            if( len(self%msg) > 0 ) return
            ! every reference in order is the dense block, scored against the resident tiles
            if( size(blk%irefs) == self%nrefs )then
                if( all(blk%irefs == [(i, i = 1, self%nrefs)]) ) deallocate(blk%irefs)
            endif
        endif
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
