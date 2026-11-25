!@descr: the toy polar calculator's block scoring: score_block_posterior, and the submission and collection of a block
! A block is the particles of one half against all the references of that parity. The calculator checks what
! SIMPLE's scorer checks (the memos are current, one half, known particles), gathers the block's host inputs
! and hands them to the parity's workspace; the entries come back from the device at collection. The
! synchronous scorer is a submission to the first slot and its collection.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_block
use mlxf_test_defs, only: polarft_block_spec
implicit none

contains

    module subroutine score_block_posterior( self, nb, iptcls, nr, irefs, temps, dists, irots, banks, l_bank )
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
        call queue_block(self, blk, iptcls)
        if( len(self%msg) > 0 ) return
        call self%collect_block(1, dists, irots)
    end subroutine score_block_posterior

    ! a block's checks and host inputs, then its submission to its parity's workspace: blk comes with its slot,
    ! temperatures and banks, and leaves with everything the workspace reads. The variates set for the block
    ! and the banks set for it are consumed whether it is queued or refused.
    subroutine queue_block( self, blk, iptcls )
        class(polarft_calc),      intent(inout) :: self
        type(polarft_block_spec), intent(inout) :: blk
        integer,                  intent(in)    :: iptcls(:)
        integer :: ieo, st
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
        call self%ws(ieo)%submit(blk, self%ft_ctf2, self%ft_ptcl_ctf, st)
        if( st /= 0 )then
            self%msg = self%ws(ieo)%message()
            return
        endif
        self%slot_ieo(blk%slot) = ieo
    end subroutine queue_block

    module subroutine set_block_variates( self, u )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(inout) :: u(:,:)
        self%msg = ''
        if( allocated(self%u_next) ) deallocate(self%u_next)
        if( allocated(u) ) call move_alloc(u, self%u_next)
    end subroutine set_block_variates

    module subroutine set_block_banks( self, banks, l_bank )
        class(polarft_calc), intent(inout) :: self
        complex(real32),     intent(in)    :: banks(:,:,:)
        logical,             intent(in)    :: l_bank(:)
        self%msg         = ''
        self%banks_next  = banks
        self%l_bank_next = l_bank
    end subroutine set_block_banks

    module subroutine set_block_options( self, rows, profile )
        class(polarft_calc), intent(inout) :: self
        logical,             intent(in)    :: rows, profile
        self%msg       = ''
        self%l_rows    = rows
        self%l_profile = profile
    end subroutine set_block_options

    module subroutine submit_block( self, slot, nb, iptcls, temps )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot, nb
        integer,             intent(in)    :: iptcls(nb)
        real(real32),        intent(in)    :: temps(nb)
        type(polarft_block_spec) :: blk
        self%msg  = ''
        blk%slot  = slot
        blk%temps = temps
        call queue_block(self, blk, iptcls)
    end subroutine submit_block

    module subroutine collect_block( self, slot, dists, irots )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: slot
        real(real32),        intent(inout) :: dists(:,:)
        integer,             intent(inout) :: irots(:,:)
        integer :: ieo, st
        self%msg = ''
        if( slot < 1 .or. slot > NSLOTS )then
            self%msg = 'polarft_calc%collect_block: refused: no such slot'
            return
        endif
        ieo = self%slot_ieo(slot)
        if( ieo == 0 .or. .not. self%existence )then
            self%msg = 'polarft_calc%collect_block: refused: the slot holds no block'
            return
        endif
        self%slot_ieo(slot) = 0
        call self%ws(ieo)%collect(slot, dists, irots, st)
        if( st /= 0 ) self%msg = self%ws(ieo)%message()
        call self%ws(ieo)%take_rows(self%rows)
    end subroutine collect_block

    module subroutine block_rows( self, rows )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: rows(:,:,:)
        self%msg = ''
        if( allocated(self%rows) ) call move_alloc(self%rows, rows)
    end subroutine block_rows

    pure module function stage_seconds( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(5)
        integer      :: ieo
        t = 0._real64
        if( .not. allocated(self%ws) ) return
        do ieo = 1, size(self%ws)
            t = t + self%ws(ieo)%stage_seconds()
        end do
    end function stage_seconds

end submodule mlxf_toy_polarft_block
