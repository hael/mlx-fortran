!@descr: the toy polar calculator's shift maps: new_shiftmap, setup_shiftmaps, gen_shiftmap, shiftmap_mode and their inquiries
! A map is a polar grid of shifts (radii and directions) over the shells kfromto(1)..kstop; the workspaces of
! both parities hold its resident data. gen_shiftmap takes the pairs of a block, every particle's candidates in
! turn, and shiftmap_mode reads their modes: the calculator checks what SIMPLE's checks (the memos are current,
! one half, known particles and references), gathers the block's host inputs and hands them through the glue to
! the parity's workspace, which builds the maps and reduces them on the device. The maps run on the MLX backend
! only.
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_shiftmap
use mlxf_test_defs, only: SHIFTMAP_SCREEN, SHIFTMAP_WINDOW
implicit none

contains

    module subroutine new_shiftmap( self, imap, rho, nalpha, kstop )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: imap
        real(real64),        intent(in)    :: rho(:)
        integer,             intent(in)    :: nalpha, kstop
        type(polarft_map_spec) :: spec
        if( .not. self%existence )then
            self%msg = 'polarft_calc%new_shiftmap: refused: no calculator (new)'
            return
        endif
        if( imap < 1 .or. imap > NSHIFTMAPS )then
            self%msg = 'polarft_calc%new_shiftmap: refused: no such shift map'
            return
        endif
        if( .not. self%l_mlx )then
            self%msg = 'polarft_calc%new_shiftmap: refused: the toy''s shift maps run on the MLX backend only'
            return
        endif
        if( self%route == POLARFT_REF_ROUTES%device )then
            self%msg = 'polarft_calc%new_shiftmap: refused: the maps read the host memos, which the device route does '// &
                &'not make'
            return
        endif
        ! the map's earlier state goes first: a refusal leaves no such map
        self%map_ref_gen(imap) = -1_int64
        if( self%sm_imap == imap ) self%sm_imap = 0
        call kill_shiftmap_mlx(self, imap)
        if( kstop <= self%kfromto(1) .or. kstop > self%kfromto(2) )then
            self%msg = 'polarft_calc%new_shiftmap: refused: the map''s last shell must lie in the band'
        else if( self%ldim(1) < 2 )then
            self%msg = 'polarft_calc%new_shiftmap: refused: the calculator has no box (the parameters'' box)'
        else if( .not. self%l_weights )then
            self%msg = 'polarft_calc%new_shiftmap: refused: no shell weights (set_sigma2_weights)'
        else if( self%l_refs_pending )then
            self%msg = 'polarft_calc%new_shiftmap: refused: references were set and not memoized (memoize_refs)'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        spec%imap   = imap
        spec%box    = self%ldim(1)
        spec%kfrom  = self%kfromto(1)
        spec%kstop  = kstop
        spec%nalpha = nalpha
        spec%rho    = rho
        call new_shiftmap_mlx(self, spec)
        if( len(self%msg) > 0 ) return
        self%map_ref_gen(imap) = self%ref_gen
        self%map_wk_gen(imap)  = self%wk_gen
        self%map_kstop(imap)   = kstop
    end subroutine new_shiftmap

    module subroutine setup_shiftmaps( self, sigma_px, radius_px, radius_win, prior_w, kscreen )
        class(polarft_calc), intent(inout) :: self
        real(real64),        intent(in)    :: sigma_px, radius_px, radius_win
        real(real64),        intent(out)   :: prior_w
        integer,             intent(out)   :: kscreen
        prior_w = 0._real64
        kscreen = 0
        if( .not. self%existence )then
            self%msg = 'polarft_calc%setup_shiftmaps: refused: no calculator (new)'
        else if( .not. (sigma_px > 0._real64) )then
            self%msg = 'polarft_calc%setup_shiftmaps: refused: the prior needs a positive width'
        else if( .not. (radius_px > 0._real64) )then
            self%msg = 'polarft_calc%setup_shiftmaps: refused: the disk needs a positive radius'
        else if( .not. (radius_win > 0._real64) )then
            self%msg = 'polarft_calc%setup_shiftmaps: refused: the window needs a positive radius'
        else if( self%ldim(1) < 2 )then
            self%msg = 'polarft_calc%setup_shiftmaps: refused: the calculator has no box (the parameters'' box)'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        prior_w = 1._real64 / (2._real64 * sigma_px**2)
        kscreen = max(self%kfromto(1) + 1, self%kfromto(2) / 2)
        call build_map(SHIFTMAP_SCREEN, kscreen, radius_px)
        if( len(self%msg) > 0 ) return
        call build_map(SHIFTMAP_WINDOW, kscreen, radius_win)

      contains

        ! one map on SIMPLE's grid: radii a quarter of the band's wavelength apart out to radius (the origin and
        ! the rim when the disk is below one step), and a direction count that resolves the ring at the outer
        ! radius
        subroutine build_map( imap, kstop, radius )
            integer,      intent(in) :: imap, kstop
            real(real64), intent(in) :: radius
            real(real64), allocatable :: rhos(:)
            real(real64)              :: step
            integer                   :: nrho, i, nalpha
            step = real(self%ldim(1), real64) / real(kstop, real64) / 4._real64
            nrho = floor(radius / step) + 1
            if( nrho < 2 )then
                nrho = 2
                step = radius
            endif
            allocate(rhos(nrho))
            do i = 1, nrho
                rhos(i) = real(i - 1, real64) * step
            end do
            nalpha = smooth_count(2 * ceiling(2._real64 * acos(-1._real64) * real(kstop, real64) * rhos(nrho) / &
                &real(self%ldim(1), real64)) + 3)
            call self%new_shiftmap(imap, rhos, nalpha, kstop)
        end subroutine build_map

    end subroutine setup_shiftmaps

    ! the smallest count at or above nmin whose prime factors are 2, 3, 5 and 7 (the lengths a transform is fast at)
    pure integer function smooth_count( nmin ) result(n)
        integer, intent(in) :: nmin
        integer :: r, f
        n = max(1, nmin)
        do
            r = n
            do f = 2, 7
                if( f == 4 .or. f == 6 ) cycle
                do while( mod(r, f) == 0 )
                    r = r / f
                end do
            end do
            if( r == 1 ) exit
            n = n + 1
        end do
    end function smooth_count

    module subroutine kill_shiftmap( self )
        class(polarft_calc), intent(inout) :: self
        self%msg         = ''
        self%map_ref_gen = -1_int64
        self%map_wk_gen  = -1_int64
        self%map_kstop   = 0
        self%sm_imap     = 0
        if( self%l_mlx ) call kill_shiftmap_mlx(self, 0)
    end subroutine kill_shiftmap

    module subroutine gen_shiftmap( self, imap, iref, iptcl )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: imap
        integer,             intent(in)    :: iref(:), iptcl(:)
        integer, allocatable :: islots(:)
        integer              :: np, ncand, nb, b
        self%sm_imap = 0
        np           = size(iptcl)
        if( .not. self%existence )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: no calculator (new)'
        else if( imap < 1 .or. imap > NSHIFTMAPS )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: no such shift map'
        else if( np < 1 .or. size(iref) /= np )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: a pair is a reference and a particle, and there is one at least'
        else if( any(iptcl < self%pfromto(1) .or. iptcl > self%pfromto(2)) )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: a particle index is outside the calculator''s range'
        else if( any(iref < 1 .or. iref > self%nrefs) )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: a candidate is not among the calculator''s references'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        islots = self%pinds(iptcl)
        if( any(islots < 1) )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: a particle index is not in the batch'
            return
        endif
        if( any(self%iseven(islots) .neqv. self%iseven(islots(1))) )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: the pairs mix the two halves'
            return
        endif
        ! every particle's candidates in turn, the same number for each
        ncand = 1
        do while( ncand < np )
            if( iptcl(ncand + 1) /= iptcl(1) ) exit
            ncand = ncand + 1
        end do
        nb = np / ncand
        if( nb * ncand /= np )then
            self%msg = 'polarft_calc%gen_shiftmap: refused: the pairs are every particle''s candidates in turn, '//&
                &'the same number for each'
            return
        endif
        do b = 1, nb
            if( any(iptcl((b - 1) * ncand + 1:b * ncand) /= iptcl((b - 1) * ncand + 1)) )then
                self%msg = 'polarft_calc%gen_shiftmap: refused: the pairs are every particle''s candidates in turn, '//&
                    &'the same number for each'
                return
            endif
        end do
        self%sm_islots = islots(1:np:ncand)
        self%sm_cands  = reshape(iref, [ncand, nb])
        self%sm_ieo    = merge(REF_EVEN, REF_ODD, self%iseven(islots(1)))
        self%sm_imap   = imap
    end subroutine gen_shiftmap

    ! the particle's weighted square sum over the shells kfromto(1)..kstop, batch slot i of half ih
    pure real(real64) function wsqsum_band( self, i, ih, kstop )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: i, ih, kstop
        wsqsum_band = sum(self%sigma2_wk8(self%kfromto(1):kstop, ih) * self%kshell_sqsums_ptcls(self%kfromto(1):kstop, i))
    end function wsqsum_band

    pure module function wsqsum_ptcl_band( self, iptcl, kstop ) result(wsq)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: iptcl, kstop
        real(real64) :: wsq
        integer      :: i
        wsq = 0._real64
        i   = ptcl_slot(self, iptcl)
        if( i == 0 .or. kstop < self%kfromto(1) .or. kstop > self%kfromto(2) ) return
        wsq = wsqsum_band(self, i, merge(REF_EVEN, REF_ODD, self%iseven(i)), kstop)
    end function wsqsum_ptcl_band

    pure module integer function shiftmap_kstop( self, imap )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        shiftmap_kstop = 0
        if( imap < 1 .or. imap > NSHIFTMAPS ) return
        if( self%map_ref_gen(imap) >= 0_int64 ) shiftmap_kstop = self%map_kstop(imap)
    end function shiftmap_kstop

    module subroutine shiftmap_mode( self, imap, temp, prior_w, irot, irho, ialpha, loss, temp_phys, sdev, width_cutoff )
        class(polarft_calc),    intent(inout) :: self
        integer,                intent(in)    :: imap
        real(real64),           intent(in)    :: temp(:), prior_w
        integer,                intent(out)   :: irot(:), irho(:), ialpha(:)
        real(real32),           intent(out)   :: loss(:)
        real(real64), optional, intent(in)    :: temp_phys(:)
        real(real32), optional, intent(out)   :: sdev(:)
        real(real32), optional, intent(in)    :: width_cutoff(:)
        type(polarft_map_block) :: mblk
        type(polar_map_results) :: res
        integer                 :: np, ncand, nb, b
        irot   = 1
        irho   = 1
        ialpha = 1
        loss   = huge(loss)
        if( present(sdev) ) sdev = -1._real32
        if( allocated(self%sm_logz) ) deallocate(self%sm_logz)
        if( allocated(self%sm_maps) ) deallocate(self%sm_maps)
        if( allocated(self%sm_shifts) ) deallocate(self%sm_shifts)
        if( .not. self%existence )then
            self%msg = 'polarft_calc%shiftmap_mode: refused: no calculator (new)'
        else if( imap < 1 .or. imap > NSHIFTMAPS )then
            self%msg = 'polarft_calc%shiftmap_mode: refused: no such shift map'
        else if( self%l_refs_pending )then
            self%msg = 'polarft_calc%shiftmap_mode: refused: references were set and not memoized (memoize_refs)'
        else if( self%map_ref_gen(imap) /= self%ref_gen .or. self%map_wk_gen(imap) /= self%wk_gen )then
            self%msg = 'polarft_calc%shiftmap_mode: refused: no shift map of the memoized references and shell '//&
                &'weights (new_shiftmap, setup_shiftmaps)'
        else if( self%ptcl_gen_memo /= self%ptcl_gen )then
            self%msg = 'polarft_calc%shiftmap_mode: refused: the particle memos are not those of the particles set '//&
                &'(memoize_ptcls)'
        else if( self%sm_imap /= imap )then
            self%msg = 'polarft_calc%shiftmap_mode: refused: no pairs were generated on this map (gen_shiftmap)'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        ncand = size(self%sm_cands, 1)
        nb    = size(self%sm_cands, 2)
        np    = ncand * nb
        if( size(temp) /= np .or. size(irot) /= np .or. size(irho) /= np .or. size(ialpha) /= np .or. size(loss) /= np )then
            self%msg = 'polarft_calc%shiftmap_mode: refused: the shapes are not those of the generated pairs'
            return
        endif
        mblk%widths = present(temp_phys) .and. present(sdev)
        if( mblk%widths )then
            if( size(temp_phys) /= np .or. size(sdev) /= np )then
                self%msg = 'polarft_calc%shiftmap_mode: refused: the shapes are not those of the generated pairs'
                return
            endif
            mblk%temps_phys = reshape(real(temp_phys, real32), [ncand, nb])
        endif
        if( present(width_cutoff) )then
            if( size(width_cutoff) /= np )then
                self%msg = 'polarft_calc%shiftmap_mode: refused: a width cutoff per generated pair'
                return
            endif
            mblk%width_cutoff = reshape(width_cutoff, [ncand, nb])
        endif
        mblk%imap      = imap
        mblk%ptcl_tile = self%sm_ptcl_tile
        mblk%maps      = self%sm_l_maps
        mblk%evidence  = self%sm_l_evidence
        mblk%profile   = self%sm_l_profile
        mblk%prior_w   = prior_w
        mblk%islots    = self%sm_islots
        mblk%cands     = self%sm_cands
        mblk%temps     = reshape(real(temp, real32), [ncand, nb])
        allocate(mblk%ptclpow(nb))
        do b = 1, nb
            mblk%ptclpow(b) = wsqsum_band(self, self%sm_islots(b), self%sm_ieo, self%map_kstop(imap))
        end do
        if( self%l_mlx ) call shiftmap_mode_mlx(self, mblk, res)
        if( len(self%msg) > 0 ) return
        irot   = reshape(res%irot, [np])
        irho   = reshape(res%irho, [np])
        ialpha = reshape(res%ialpha, [np])
        loss   = reshape(res%loss, [np])
        if( mblk%widths ) sdev = reshape(res%sdev, [np])
        if( allocated(res%logz) ) call move_alloc(res%logz, self%sm_logz)
        if( allocated(res%maps) ) call move_alloc(res%maps, self%sm_maps)
        if( allocated(res%shifts) ) call move_alloc(res%shifts, self%sm_shifts)
    end subroutine shiftmap_mode

    module subroutine set_shiftmap_options( self, ptcl_tile, maps, evidence, profile )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: ptcl_tile
        logical,             intent(in)    :: maps, evidence, profile
        self%msg           = ''
        self%sm_ptcl_tile  = ptcl_tile
        self%sm_l_maps     = maps
        self%sm_l_evidence = evidence
        self%sm_l_profile  = profile
    end subroutine set_shiftmap_options

    module subroutine shiftmap_shifts( self, xy )
        class(polarft_calc),       intent(inout) :: self
        real(real64), allocatable, intent(out)   :: xy(:,:)
        integer :: shp(3)
        if( .not. self%l_mlx )then
            self%msg = 'polarft_calc%shiftmap_shifts: refused: the toy''s shift maps run on the MLX backend only'
            return
        endif
        self%msg = ''
        if( .not. allocated(self%sm_shifts) ) return
        shp = shape(self%sm_shifts)
        xy  = reshape(self%sm_shifts, [2, shp(2) * shp(3)])
    end subroutine shiftmap_shifts

    module subroutine shiftmap_evidence( self, logz )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: logz(:)
        self%msg = ''
        if( allocated(self%sm_logz) ) logz = reshape(self%sm_logz, [size(self%sm_logz)])
    end subroutine shiftmap_evidence

    module subroutine shiftmap_maps( self, maps )
        class(polarft_calc),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: maps(:,:,:,:)
        integer :: shp(5)
        self%msg = ''
        if( .not. allocated(self%sm_maps) ) return
        shp  = shape(self%sm_maps)
        maps = reshape(self%sm_maps, [shp(1), shp(2), shp(3), shp(4) * shp(5)])
    end subroutine shiftmap_maps

    pure module integer function shiftmap_order( self, imap )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        shiftmap_order = 0
        if( self%l_mlx ) shiftmap_order = shiftmap_order_mlx(self, imap)
    end function shiftmap_order

    pure module function shiftmap_term_counts( self, imap ) result(counts)
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: imap
        integer(int64) :: counts(2)
        counts = 0_int64
        if( self%l_mlx ) counts = shiftmap_term_counts_mlx(self, imap)
    end function shiftmap_term_counts

    pure module function shiftmap_seconds( self ) result(t)
        class(polarft_calc), intent(in) :: self
        real(real64) :: t(4)
        t = 0._real64
        if( self%l_mlx ) t = shiftmap_seconds_mlx(self)
    end function shiftmap_seconds

end submodule mlxf_toy_polarft_shiftmap
