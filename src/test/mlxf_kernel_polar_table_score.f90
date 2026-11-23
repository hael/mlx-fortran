!@descr: the polar table workspace's scoring: block validation, the per-tile graph (formulations b, c), the draw, copy-out
! Per particle tile and reference tile, every angular bin's complex sums of the particle terms (bt, 2nk) and the
! tile (2nk, rt) are one real product of packed (Re, Im) parts, batched over the bins; the inverse real transform
! (an FFT for b, a real product with a fixed matrix for c) gives the rows, and the compiled tail (the distances
! and the posterior draw) picks each pair's rotation on the device. Tiles are always full (padded), so a pair's
! entry depends on its tile position only, never on the outer batch or slot.
submodule (mlxf_kernel_polar_table) mlxf_kernel_polar_table_score
use, intrinsic :: iso_fortran_env, only: int64
use mlxf,           only: mlx_from, mlx_to, mlx_eval, mlx_async_eval, mlx_slice, mlx_permute, mlx_concatenate, reshape, &
                          matmul, mlx_irfft, merge, minval, minloc, sum, max, exp, real, aimag, cmplx, mlx_cumsum, &
                          mlx_take_along_dim
use mlxf_test_defs, only: POLAR_DIST_MAX, POLAR_DIST_INVALID, POLAR_DIST_VALID, POLAR_ARG_CUTOFF, POLAR_DRAW_FLOOR
implicit none

! the inputs of one tile's sums: particle terms (bt, 2nk, pftsz+1) complex, or packed (bt, 4nk, pftsz+1) real;
! the reference tile (2nk, rt, pftsz+1) complex, or packed (4nk, 2rt, pftsz+1) real
type :: tile_inputs
    type(mlx_array) :: pt
    type(mlx_array) :: g
end type tile_inputs

! the inputs of a tile's tail: the inverse transform's rows (nrots, rt, bt), 1/(2 wsq) and inverse
! temperatures (1, 1, bt), variates (rt, bt)
type :: tail_inputs
    type(mlx_array) :: raw
    type(mlx_array) :: iw
    type(mlx_array) :: temps
    type(mlx_array) :: u
end type tail_inputs

! a tile's distances (nrots, rt, bt) and its entries (rt, bt)
type :: tail_outputs
    type(mlx_array) :: rows
    type(mlx_array) :: dists
    type(mlx_array) :: irots
end type tail_outputs

contains

    module subroutine polar_table_submit( self, blk, slot, status )
        class(polar_table),      intent(inout) :: self
        type(polar_table_block), intent(in)    :: blk
        integer,                 intent(in)    :: slot
        integer,                 intent(out)   :: status
        complex(real32), allocatable :: ctf2(:,:,:), xctf(:,:,:)
        real(real32),    allocatable :: iw(:), temps(:), u(:,:)
        type(mlx_array), allocatable :: dcol(:), icol(:), rcol(:), drow(:), irow(:), rrow(:)
        type(mlx_array)              :: c2, xc, w3, wt, wx, pt, ptj, iwa, ta, ua, dd, ii, rr, prod
        type(tile_inputs)            :: inp
        type(tail_inputs)            :: tin
        type(tail_outputs)           :: tout
        real(real64)                 :: t0
        integer                      :: nb, n1, nbt, bpad, rpad, j, t, b, b0, b1, r0, ierr, gk, gr
        status = 1
        call check_block(self, blk, slot, self%msg)
        if( len(self%msg) > 0 ) return
        n1   = self%pftsz + 1
        nb   = size(blk%ctf2, 3)
        nbt  = (nb + self%bt - 1) / self%bt
        bpad = nbt * self%bt
        rpad = self%ntiles * self%rt
        ! the block staged on the host, padded to whole tiles: padded particles score zero sums
        allocate(ctf2(n1, self%nk, bpad), xctf(n1, self%nk, bpad), iw(bpad), temps(bpad), u(rpad, bpad), stat=ierr)
        if( ierr /= 0 )then
            self%msg = 'polar_table%submit: the host staging of the block could not be allocated'
            return
        endif
        ctf2  = cmplx(0._real32, 0._real32, real32)
        xctf  = cmplx(0._real32, 0._real32, real32)
        iw    = 0._real32
        temps = 0._real32
        u     = 0._real32
        do b = 1, nb
            ctf2(:,:, b) = blk%ctf2(:,:, b)
            xctf(:,:, b) = blk%xctf(:,:, b)
            if( allocated(blk%l_bank) )then
                if( blk%l_bank(b) ) xctf(:,:, b) = blk%banks(:,:, b)
            endif
            iw(b)    = real(1._real64 / (2._real64 * blk%wsq(b)), real32)
            temps(b) = max(0._real32, blk%temps(b))
        end do
        u(1:self%nrefs, 1:nb) = blk%u
        t0 = clock_s()
        ! the particle terms of every bin, on the device: w_k CTF2 on rows 1..nk, -2 w_k X.CTF on rows nk+1..2nk
        c2  = mlx_from(ctf2)
        xc  = mlx_from(xctf)
        w3  = mlx_from(reshape(blk%weights, [1, self%nk, 1]))
        wt  = c2 * w3
        wx  = xc * (w3 * (-2._real32))
        pt  = mlx_concatenate([wt, wx], 2)
        iwa = mlx_from(reshape(iw, [1, 1, bpad]))
        ta  = mlx_from(reshape(temps, [1, 1, bpad]))
        ua  = mlx_from(u)
        if( blk%profile ) call stage_done(self, 1, t0, [pt, iwa, ta, ua])
        ! the reference tile's rows and columns in the resident (packed) layout
        gk = 4 * self%nk
        gr = 2 * self%rt
        allocate(dcol(self%ntiles), icol(self%ntiles), rcol(self%ntiles), drow(nbt), irow(nbt), rrow(nbt))
        do j = 1, nbt
            b0  = (j - 1) * self%bt + 1
            b1  = j * self%bt
            ptj    = mlx_permute(mlx_slice(pt, [1, 1, b0], [n1, 2 * self%nk, b1]), [3, 2, 1])
            inp%pt = packed_terms(ptj)
            tin%iw    = mlx_slice(iwa, [1, 1, b0], [1, 1, b1])
            tin%temps = mlx_slice(ta, [1, 1, b0], [1, 1, b1])
            do t = 1, self%ntiles
                r0     = (t - 1) * self%rt + 1
                inp%g  = reshape(mlx_slice(self%refs, [1, 1, 1, t], [gk, gr, n1, t]), [gk, gr, n1])
                tin%u  = mlx_slice(ua, [r0, b0], [r0 + self%rt - 1, b1])
                t0     = clock_s()
                prod   = matmul(inp%pt, inp%g)
                if( blk%profile ) call stage_done(self, 2, t0, [prod])
                t0      = clock_s()
                tin%raw = inverse_transform(self, prod)
                if( blk%profile ) call stage_done(self, 3, t0, [tin%raw])
                t0 = clock_s()
                call apply_tail(self, tin, tout, status)
                if( status /= 0 ) return
                if( blk%profile ) call stage_done(self, 4, t0, [tout%dists, tout%irots])
                dcol(t) = tout%dists
                icol(t) = tout%irots
                ! the rows are held only when asked for: every tile's rows would stay alive otherwise
                if( blk%rows ) rcol(t) = tout%rows
                ! each tile is queued as it is built, so that MLX holds one tile's temporaries at a time, not
                ! those of every tile of the block
                if( blk%rows )then
                    call mlx_async_eval([tout%dists, tout%irots, tout%rows])
                else
                    call mlx_async_eval([tout%dists, tout%irots])
                endif
            end do
            drow(j) = mlx_concatenate(dcol, 1)
            irow(j) = mlx_concatenate(icol, 1)
            if( blk%rows ) rrow(j) = mlx_concatenate(rcol, 2)
        end do
        t0 = clock_s()
        dd = mlx_concatenate(drow, 2)
        ii = mlx_concatenate(irow, 2)
        if( blk%rows )then
            rr = mlx_concatenate(rrow, 3)
            call mlx_async_eval([dd, ii, rr])
        else
            call mlx_async_eval([dd, ii])
        endif
        if( blk%profile ) call stage_done(self, 5, t0, [dd, ii])
        self%slots(slot)%dists  = dd
        self%slots(slot)%irots  = ii
        if( blk%rows ) self%slots(slot)%rows = rr
        self%slots(slot)%busy   = .true.
        self%slots(slot)%l_rows = blk%rows
        self%slots(slot)%nrefs  = self%nrefs
        self%slots(slot)%nptcls = nb
        self%slots(slot)%nrots  = self%nrots
        self%slots(slot)%rpad   = rpad
        self%slots(slot)%bpad   = bpad
        status = 0
    end subroutine polar_table_submit

    ! seconds of a monotonic clock
    real(real64) function clock_s()
        integer(int64) :: count, rate
        call system_clock(count, rate)
        clock_s = real(count, real64) / real(rate, real64)
    end function clock_s

    ! a profiled stage: its arrays evaluated (a barrier), its seconds added to stage_s(i)
    subroutine stage_done( self, i, t0, arrays )
        class(polar_table), intent(inout) :: self
        integer,            intent(in)    :: i
        real(real64),       intent(in)    :: t0
        type(mlx_array),    intent(in)    :: arrays(:)
        call mlx_eval(arrays)
        self%stage_s(i) = self%stage_s(i) + (clock_s() - t0)
    end subroutine stage_done

    ! the particle terms (bt, 2nk, P) as the real (bt, 4nk, P) of their real and imaginary parts, so that one
    ! real product with the packed tile gives (Re c, Im c)
    function packed_terms( pt ) result(pr)
        type(mlx_array), intent(in) :: pt
        type(mlx_array) :: pr
        type(mlx_array) :: re, im
        re = real(pt)
        im = aimag(pt)
        pr = mlx_concatenate([re, im], 2)
    end function packed_terms

    ! the rows (nrots, rt, bt) of a tile's packed sums (bt, 2rt, P): for b, recombined to complex sums and the
    ! inverse real FFT; for c, the real and imaginary parts against the inverse transform's matrix
    function inverse_transform( self, prod ) result(raw)
        class(polar_table), intent(in) :: self
        type(mlx_array),    intent(in) :: prod
        type(mlx_array) :: raw
        type(mlx_array) :: c, re, im, x, xp, xr, r2
        integer         :: shp(3), bt, rt, n1
        shp = prod%shape()
        bt  = shp(1)
        n1  = shp(3)
        rt  = shp(2) / 2
        re = mlx_slice(prod, [1, 1, 1], [bt, rt, n1])
        im = mlx_slice(prod, [1, rt + 1, 1], [bt, 2 * rt, n1])
        if( self%formulation == POLAR_FORMS%b )then
            c   = mlx_permute(cmplx(re, im), [3, 2, 1])
            raw = mlx_irfft(c, 1, n=self%nrots)
        else
            x   = mlx_concatenate([re, im], 3)
            xp  = mlx_permute(x, [3, 2, 1])
            xr  = reshape(xp, [2 * n1, rt * bt])
            r2  = matmul(self%imat, xr)
            raw = reshape(r2, [self%nrots, rt, bt])
        endif
    end function inverse_transform

    ! the tail of a tile through the compiled function
    subroutine apply_tail( self, tin, tout, status )
        class(polar_table), intent(inout) :: self
        type(tail_inputs),  intent(in)    :: tin
        type(tail_outputs), intent(out)   :: tout
        integer,            intent(out)   :: status
        type(mlx_array), allocatable :: outs(:)
        call self%tail%apply([tin%raw, tin%iw, tin%temps, tin%u], outs, status)
        if( status /= 0 )then
            self%msg = 'polar_table%submit: the compiled distances and draw failed'
            return
        endif
        tout%rows  = outs(1)
        tout%dists = outs(2)
        tout%irots = outs(3)
    end subroutine apply_tail

    ! the compiled tail's callback: inputs (raw, 1/(2 wsq), temperatures, variates), outputs (rows, distances,
    ! rotations); a wrong number of inputs returns a status
    module subroutine polar_tail_callback( inputs, outputs, status )
        type(mlx_array),              intent(in)  :: inputs(:)
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        integer,                      intent(out) :: status
        type(tail_inputs)  :: tin
        type(tail_outputs) :: tout
        status = 1
        if( size(inputs) /= 4 ) return
        tin%raw   = inputs(1)
        tin%iw    = inputs(2)
        tin%temps = inputs(3)
        tin%u     = inputs(4)
        call tail_graph(tin, tout)
        allocate(outputs(3))
        outputs(1) = tout%rows
        outputs(2) = tout%dists
        outputs(3) = tout%irots
        status = 0
    end subroutine polar_tail_callback

    ! the distances with the invalid marker, and the draw: the first rotation whose cumulative weight reaches
    ! max(u W, tiny), else the minimising rotation; a row without a valid rotation gives (invalid, 1)
    subroutine tail_graph( tin, tout )
        type(tail_inputs),  intent(in)  :: tin
        type(tail_outputs), intent(out) :: tout
        type(mlx_array) :: d, big, zero, one, bad, valid, dv, dmin, arg, keep, wgt, wsum, cum, tgt
        type(mlx_array) :: reach, miss, first, anyr, imin, irot, pick
        integer         :: shp(3), rt, bt
        shp  = tin%raw%shape()
        rt   = shp(2)
        bt   = shp(3)
        d    = tin%raw * tin%iw + 1._real32
        big  = mlx_from(POLAR_DIST_INVALID)
        zero = mlx_from(0._real32)
        one  = mlx_from(1._real32)
        ! above the invalid distance, or not a number (the production draw skips a non-finite distance too)
        bad   = .not. (d <= real(POLAR_DIST_MAX, real32))
        d     = merge(big, d, bad)
        valid = d < POLAR_DIST_VALID
        dv    = merge(d, big, valid)
        dmin  = reshape(minval(dv, 1), [1, rt, bt])
        arg   = (dv - dmin) * tin%temps
        keep  = valid .and. (arg < POLAR_ARG_CUTOFF)
        wgt   = merge(exp(-arg), zero, keep)
        wsum  = sum(wgt, 1)
        cum   = mlx_cumsum(wgt, 1)
        tgt   = reshape(max(tin%u * wsum, POLAR_DRAW_FLOOR), [1, rt, bt])
        reach = cum >= tgt
        miss  = merge(zero, one, reach)
        first = minloc(miss, 1)
        anyr  = minval(miss, 1) < 0.5_real32
        imin  = minloc(dv, 1)
        irot  = merge(first, imin, anyr)
        pick  = mlx_take_along_dim(d, reshape(irot, [1, rt, bt]), 1)
        tout%rows  = d
        tout%dists = reshape(pick, [rt, bt])
        tout%irots = irot
    end subroutine tail_graph

    ! the reason blk cannot be scored in slot, or an empty string: nothing about the block is assumed
    subroutine check_block( self, blk, slot, msg )
        class(polar_table),            intent(in)  :: self
        type(polar_table_block),       intent(in)  :: blk
        integer,                       intent(in)  :: slot
        character(len=:), allocatable, intent(out) :: msg
        integer :: n1, nb
        msg = ''
        if( slot < 1 .or. slot > POLAR_TABLE_NSLOTS )then
            msg = 'polar_table%submit: no such slot'
        else if( self%slots(slot)%busy )then
            msg = 'polar_table%submit: the slot holds a block not yet collected'
        else if( .not. self%prepared )then
            msg = 'polar_table%submit: refused: no prepared references (new after invalidation)'
        else if( blk%generation /= self%generation )then
            msg = 'polar_table%submit: refused: the block''s reference generation differs from the prepared one'
        else if( blk%half /= self%half )then
            msg = 'polar_table%submit: refused: the block''s half differs from the prepared one'
        else if( .not. allocated(blk%ref_ids) )then
            msg = 'polar_table%submit: refused: the block names no reference list'
        endif
        if( len(msg) > 0 ) return
        if( size(blk%ref_ids) /= self%nrefs )then
            msg = 'polar_table%submit: refused: the block''s reference list differs from the prepared one'
            return
        endif
        if( any(blk%ref_ids /= self%ids) )then
            msg = 'polar_table%submit: refused: the block''s reference list differs from the prepared one'
            return
        endif
        if( .not. allocated(blk%ctf2) .or. .not. allocated(blk%xctf) .or. .not. allocated(blk%weights) .or. &
            &.not. allocated(blk%wsq) .or. .not. allocated(blk%temps) .or. .not. allocated(blk%u) .or. &
            &.not. allocated(blk%ptcl_ids) )then
            msg = 'polar_table%submit: refused: the block lacks an input'
            return
        endif
        n1 = self%pftsz + 1
        nb = size(blk%ctf2, 3)
        if( nb < 1 .or. any(shape(blk%ctf2) /= [n1, self%nk, nb]) .or. any(shape(blk%xctf) /= [n1, self%nk, nb]) &
            &.or. size(blk%weights) /= self%nk .or. size(blk%wsq) /= nb .or. size(blk%temps) /= nb .or. &
            &size(blk%ptcl_ids) /= nb .or. any(shape(blk%u) /= [self%nrefs, nb]) )then
            msg = 'polar_table%submit: refused: the block''s shapes do not match the prepared references'
            return
        endif
        if( allocated(blk%banks) .neqv. allocated(blk%l_bank) )then
            msg = 'polar_table%submit: refused: banks and l_bank go together'
            return
        endif
        if( allocated(blk%banks) )then
            if( any(shape(blk%banks) /= [n1, self%nk, nb]) .or. size(blk%l_bank) /= nb )then
                msg = 'polar_table%submit: refused: the banks do not match the block'
                return
            endif
        endif
        if( any(.not. (blk%wsq > 0._real64)) )then
            msg = 'polar_table%submit: refused: a particle''s weighted square sum is not positive'
        else if( any(blk%ptcl_ids < 1) )then
            msg = 'polar_table%submit: refused: particle IDs are global and positive'
        endif
    end subroutine check_block

    module subroutine polar_table_collect( self, slot, entries, status )
        class(polar_table),        intent(inout) :: self
        integer,                   intent(in)    :: slot
        type(polar_table_entries), intent(out)   :: entries
        integer,                   intent(out)   :: status
        real(real32), allocatable :: dd(:,:), rr(:,:,:)
        integer,      allocatable :: ii(:,:)
        integer                   :: nr, nb
        status = 1
        if( slot < 1 .or. slot > POLAR_TABLE_NSLOTS )then
            self%msg = 'polar_table%collect: no such slot'
            return
        endif
        if( .not. self%slots(slot)%busy )then
            self%msg = 'polar_table%collect: the slot holds no block'
            return
        endif
        associate( s => self%slots(slot) )
            nr = s%nrefs
            nb = s%nptcls
            allocate(dd(s%rpad, s%bpad), ii(s%rpad, s%bpad))
            call mlx_to(dd, s%dists, status=status)
            if( status == 0 ) call mlx_to(ii, s%irots, status=status)
            if( status == 0 .and. s%l_rows )then
                allocate(rr(s%nrots, s%rpad, s%bpad))
                call mlx_to(rr, s%rows, status=status)
            endif
            if( status == 0 )then
                entries%dists = dd(1:nr, 1:nb)
                entries%irots = ii(1:nr, 1:nb)
                if( s%l_rows ) entries%rows = rr(:, 1:nr, 1:nb)
            else
                self%msg = 'polar_table%collect: the block could not be evaluated'
            endif
            call s%dists%kill()
            call s%irots%kill()
            call s%rows%kill()
            s%busy = .false.
        end associate
    end subroutine polar_table_collect

    module subroutine polar_table_score( self, blk, entries, status )
        class(polar_table),        intent(inout) :: self
        type(polar_table_block),   intent(in)    :: blk
        type(polar_table_entries), intent(out)   :: entries
        integer,                   intent(out)   :: status
        call self%submit(blk, 1, status)
        if( status /= 0 ) return
        call self%collect(1, entries, status)
    end subroutine polar_table_score

end submodule mlxf_kernel_polar_table_score
