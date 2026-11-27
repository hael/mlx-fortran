!@descr: the polar workspace's shift-map reductions: a tile's mode, widths and evidence from its maps, and their compiled callbacks
! A map's construction ends in its maps L (nalpha, nrots, nrho, pairs) of SIMPLE's cells; their reductions are
! these, apart from the construction, in SIMPLE's order: the mode (the first largest log
! mass in Fortran order) and its loss, the widths at the physical temperature under the pairs' cutoffs (one
! synchronization per tile supplies every cutoff decision), the optional evidence, and the copies to the host.
submodule (mlxf_toy_polarft_workspace) mlxf_toy_polarft_workspace_mapreduce
use, intrinsic :: iso_fortran_env, only: int32, int64
use mlxf,           only: mlx_from, mlx_to, mlx_eval, reshape, mlx_take_along_dim, mlx_take, merge, minval, minloc, &
                          sum, sqrt, exp, mlx_logsumexp, max
use mlxf_test_defs, only: POLAR_MAP_LOG_CUT
implicit none

contains

    module subroutine reduce_map_tile( self, mblk, sh, tl, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_map_block),  intent(in)    :: mblk
        type(map_shared),         intent(in)    :: sh
        type(map_tile),           intent(inout) :: tl
        integer,                  intent(out)   :: status
        type(mlx_array)              :: lp, tt, tp, idx, loss, sdev, logz, lse, width_maps, active_idx
        type(mlx_array), allocatable :: outs(:)
        real(real32),    allocatable :: t(:), tph(:), widths(:), cuts(:)
        integer,         allocatable :: active(:)
        real(real64)                 :: t0
        integer                      :: im, np, ncand, nrots, nalpha, nrho, b, nactive
        status = 0
        im     = mblk%imap
        np     = size(tl%pref)
        ncand  = size(tl%cands, 1)
        nrots  = self%maps(im)%nrots
        nalpha = self%maps(im)%nalpha
        nrho   = self%maps(im)%nrho
        lp = tl%lp
        allocate(t(np), tph(np))
        tph = 0._real32
        do b = 1, np
            t(b) = mblk%temps(mod(b - 1, ncand) + 1, tl%pptcl(b))
            if( mblk%widths ) tph(b) = mblk%temps_phys(mod(b - 1, ncand) + 1, tl%pptcl(b))
        end do
        t0   = map_clock()
        tt   = mlx_from(reshape(t, [1, 1, 1, np]))
        call self%maps(im)%map_select%apply([lp, tt, sh%cellprior], outs, status)
        if( status /= 0 )then
            self%msg = 'polarft_workspace%score_maps: a tile''s selection could not be built'
            return
        endif
        idx  = outs(1)
        loss = outs(2)
        if( mblk%profile ) call map_stage_done(self, 2, t0, [idx, loss])
        t0   = map_clock()
        allocate(tl%idx(np), tl%loss(np), tl%sdev(np), tl%logz(np))
        active = [(b, b = 1, np)]
        if( allocated(mblk%width_cutoff) )then
            ! One synchronization per tile supplies every cutoff decision; no moment graph for rejected pairs.
            call mlx_to(tl%idx, idx, status=status)
            if( status == 0 ) call mlx_to(tl%loss, loss, status=status)
            if( status /= 0 ) return
            cuts = reshape(mblk%width_cutoff(:, tl%ptcls), [np])
            active = pack(active, tl%loss <= cuts)
        endif
        if( .not. mblk%widths ) active = pack(active, .false.)
        nactive = size(active)
        if( nactive > 0 )then
            width_maps = lp
            if( nactive < np )then
                active_idx = mlx_from(int(active, int32))
                width_maps = mlx_take(lp, active_idx, 4)
            endif
            tp = mlx_from(reshape(tph(active), [1, 1, 1, nactive]))
            call self%maps(im)%map_reduce%apply([width_maps, tp, sh%cellprior, self%maps(im)%cellx, &
                &self%maps(im)%celly, self%maps(im)%cellr2, sh%cosr, sh%sinr], outs, status)
            if( status /= 0 )then
                self%msg = 'polarft_workspace%score_maps: a tile''s width reduction could not be built'
                return
            endif
            sdev = outs(1)
            if( mblk%profile ) call mlx_eval([sdev])
        endif
        ! Separate compiled graphs ensure unrequested evidence is never evaluated with the width.
        if( mblk%evidence )then
            lse = mlx_from(real(sh%lse_prior, real32))
            call self%maps(im)%map_evidence%apply([lp, tt, sh%cellprior, lse], outs, status)
            if( status /= 0 )then
                self%msg = 'polarft_workspace%score_maps: a tile''s evidence reduction could not be built'
                return
            endif
            logz = outs(1)
            if( mblk%profile ) call mlx_eval([logz])
        endif
        if( mblk%profile ) self%mstage_s(3) = self%mstage_s(3) + map_clock() - t0
        t0 = map_clock()
        if( .not. allocated(mblk%width_cutoff) )then
            call mlx_to(tl%idx, idx, status=status)
            if( status == 0 ) call mlx_to(tl%loss, loss, status=status)
        endif
        tl%sdev = -1._real32
        if( status == 0 .and. nactive > 0 )then
            allocate(widths(nactive))
            call mlx_to(widths, sdev, status=status)
            tl%sdev(active) = widths
        endif
        if( status == 0 .and. mblk%evidence ) call mlx_to(tl%logz, logz, status=status)
        if( status == 0 .and. mblk%maps )then
            allocate(tl%maps(nalpha, nrots, nrho, np))
            call mlx_to(tl%maps, lp, status=status)
        endif
        if( status /= 0 ) self%msg = 'polarft_workspace%score_maps: a tile could not be evaluated'
        ! profiled, every result is evaluated before the copies: their seconds are the transfer's
        if( mblk%profile ) self%mstage_s(4) = self%mstage_s(4) + (map_clock() - t0)
    end subroutine reduce_map_tile

    ! the compiled selection: inputs (the maps L (nalpha, nrots, nrho, np), the tempered inverse temperatures
    ! (1, 1, 1, np), the cells' prior with the log area (1, 1, nrho, 1)); outputs (the flat index of the mode, the
    ! first largest log mass in Fortran order, and its loss), each (np)
    module subroutine map_select_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
        type(mlx_array) :: flat, idx
        integer         :: shp(4), ncell, np
        status = 1
        if( size(inputs) /= 3 ) return
        shp   = inputs(1)%shape()
        ncell = shp(1) * shp(2) * shp(3)
        np    = shp(4)
        flat  = reshape(inputs(3) - inputs(1) * inputs(2), [ncell, np])
        idx   = minloc(-flat, 1)
        allocate(outputs(2))
        outputs(1) = idx
        outputs(2) = reshape(mlx_take_along_dim(reshape(inputs(1), [ncell, np]), reshape(idx, [1, np]), 1), [np])
        status = 0
    end subroutine map_select_callback

    ! Width inputs: maps, physical inverse temperatures, prior, shift x/y/radius squared and rotation cos/sin.
    ! The moments rotate each cell into the particle frame; negligible mass is cut before summing.
    module subroutine map_reduce_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
        type(mlx_array) :: lph, mp, a, w, w0, w1x, w1y, mx, my, w2, var, zero
        integer         :: shp(4), ncell, np
        status = 1
        if( size(inputs) /= 8 ) return
        shp   = inputs(1)%shape()
        ncell = shp(1) * shp(2) * shp(3)
        np    = shp(4)
        lph   = inputs(3) - inputs(1) * inputs(2)
        mp    = reshape(-minval(reshape(-lph, [ncell, np]), 1), [1, 1, 1, np])
        a     = lph - mp
        zero  = mlx_from(0._real32)
        w     = merge(exp(a), zero, a > real(POLAR_MAP_LOG_CUT, real32))
        w0    = sum(reshape(w, [ncell, np]), 1)
        w1x   = sum(sum(w * inputs(4), 3), 1)
        w1y   = sum(sum(w * inputs(5), 3), 1)
        mx    = sum(w1x * inputs(7) - w1y * inputs(8), 1)
        my    = sum(w1x * inputs(8) + w1y * inputs(7), 1)
        w2    = sum(reshape(w * inputs(6), [ncell, np]), 1)
        var   = (w2 - (mx * mx + my * my) / w0) / w0
        allocate(outputs(1))
        outputs(1) = sqrt(max(var, 0._real32))
        status = 0
    end subroutine map_reduce_callback

    ! Evidence uses the tempered temperature and the prior normalizer, independently of the width graph.
    module subroutine map_evidence_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
        integer :: shp(4), ncell
        status = 1
        if( size(inputs) /= 4 ) return
        shp = inputs(1)%shape()
        ncell = product(shp(1:3))
        allocate(outputs(1))
        outputs(1) = mlx_logsumexp(reshape(inputs(3) - inputs(1) * inputs(2), [ncell, shp(4)]), 1) - inputs(4)
        status = 0
    end subroutine map_evidence_callback

    module function map_clock() result(t)
        real(real64)   :: t
        integer(int64) :: count, rate
        call system_clock(count, rate)
        t = real(count, real64) / real(rate, real64)
    end function map_clock

    module subroutine map_stage_done( self, i, t0, arrays )
        class(polarft_workspace), intent(inout) :: self
        integer,                  intent(in)    :: i
        real(real64),             intent(in)    :: t0
        type(mlx_array),          intent(in)    :: arrays(:)
        call mlx_eval(arrays)
        self%mstage_s(i) = self%mstage_s(i) + (map_clock() - t0)
    end subroutine map_stage_done

end submodule mlxf_toy_polarft_workspace_mapreduce
