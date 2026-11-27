!@descr: the polar workspace's list tiles: a block's reference list gathered from the resident tiles into tiles of the same plan
! The resident tiles (4nk, 2rt, pftsz+1, tiles) are read as (4nk, rt, 2, pftsz+1, tiles), a view: one gather of
! 4nk-element slabs, indexed by each listed reference's column and tile, the half (the Re or the Im column of the
! packed block) and the bin, writes the list tiles in the resident layout, so that the dense route's tile graph
! scores them unchanged and the resident tiles are never copied. The pair-list kernel scores listed pairs only:
! a SIMD group per (pair, bin) sums the particle's packed terms against the reference's two packed columns of the
! resident tiles; the inverse transform and the tail (either form) follow on the listed rows.
submodule (mlxf_toy_polarft_workspace) mlxf_toy_polarft_workspace_lists
use, intrinsic :: iso_fortran_env, only: int32
use mlxf,           only: mlx_from, mlx_gather, reshape, mlx_slice, mlx_concatenate, mlx_irfft, mlx_async_eval, cmplx, &
                          real, aimag, mlx_default_device, MLX_DEVICES, MLX_DTYPES
use mlxf_test_defs, only: polarft_tile_spec, POLARFT_TAILS
implicit none

character(len=1), parameter :: NL = achar(10)
! the kernel's grid: 32 threads per (pair, bin), at most this many in one launch
integer(int64), parameter :: PAIR_GRID_MAX = 2147483647_int64
! the pair-list kernel. sz holds the pairs, the bins, 4nk and the tiles' rt; pp each pair's particle in the block
! and pr its reference (0-based). MLX's layouts: pt [particles][bins][4nk], bank [tiles][bins][2rt][4nk], o
! [pairs][bins][2]; a SIMD group per (pair, bin), each lane summing every 32nd term; groups past the pairs return
character(len=*), parameter :: PAIR_SRC = &
    &'uint g = thread_position_in_grid.x / 32;'//NL// &
    &'uint lane = thread_index_in_simdgroup;'//NL// &
    &'uint np = sz[0]; uint n1 = sz[1]; uint gk = sz[2]; uint rt = sz[3];'//NL// &
    &'if (g >= np * n1) return;'//NL// &
    &'uint e = g / n1; uint k = g - e * n1;'//NL// &
    &'uint p = pp[e]; uint r = pr[e]; uint c = r % rt; uint t = r / rt;'//NL// &
    &'uint ia = (p * n1 + k) * gk;'//NL// &
    &'uint ib = ((t * n1 + k) * 2 * rt + c) * gk;'//NL// &
    &'uint ic = ib + rt * gk;'//NL// &
    &'float sre = 0.0f; float sim = 0.0f;'//NL// &
    &'for (uint i = lane; i < gk; i += 32) { float x = pt[ia + i]; sre = fma(x, bank[ib + i], sre); '// &
    &'sim = fma(x, bank[ic + i], sim); }'//NL// &
    &'sre = simd_sum(sre); sim = simd_sum(sim);'//NL// &
    &'if (lane == 0) { o[2 * g] = sre; o[2 * g + 1] = sim; }'//NL

contains

    module subroutine polarft_workspace_list_tiles( self, irefs, status )
        class(polarft_workspace), intent(inout) :: self
        integer,                  intent(in)    :: irefs(:)
        integer,                  intent(out)   :: status
        integer, allocatable :: icol(:,:,:,:), itile(:,:,:,:), ihalf(:,:,:,:), ibin(:,:,:,:)
        type(mlx_array)      :: view, idx(4), g
        integer              :: nr, nlt, n1, gk, c, t, r, p
        status = 0
        if( allocated(self%list_refs) )then
            if( size(self%list_refs) == size(irefs) )then
                if( all(self%list_refs == irefs) ) return
            endif
        endif
        call polarft_workspace_drop_list(self)
        nr  = size(irefs)
        nlt = (nr + self%rt - 1) / self%rt
        n1  = self%pftsz + 1
        gk  = 4 * self%nk
        allocate(icol(self%rt, 1, 1, nlt), itile(self%rt, 1, 1, nlt), ihalf(1, 2, 1, 1), ibin(1, 1, n1, 1))
        do t = 1, nlt
            do c = 1, self%rt
                ! the last tile's padding repeats the first listed reference: its entries are never read
                r = irefs(1)
                if( (t - 1) * self%rt + c <= nr ) r = irefs((t - 1) * self%rt + c)
                icol(c, 1, 1, t)  = mod(r - 1, self%rt) + 1
                itile(c, 1, 1, t) = (r - 1) / self%rt + 1
            end do
        end do
        ihalf(1, :, 1, 1) = [1, 2]
        ibin(1, 1, :, 1)  = [(p, p = 1, n1)]
        view   = reshape(self%refs, [gk, self%rt, 2, n1, self%ntiles])
        idx(1) = mlx_from(icol)
        idx(2) = mlx_from(ihalf)
        idx(3) = mlx_from(ibin)
        idx(4) = mlx_from(itile)
        g      = mlx_gather(view, idx, [2, 3, 4, 5], [gk, 1, 1, 1, 1])
        ! the slabs come in the indices' order (column, half, bin, tile): the resident layout of nlt tiles
        self%list_tiles = reshape(g, [gk, 2 * self%rt, n1, nlt])
        self%list_refs  = irefs
    end subroutine polarft_workspace_list_tiles

    module subroutine polarft_workspace_drop_list( self )
        class(polarft_workspace), intent(inout) :: self
        call self%list_tiles%kill()
        if( allocated(self%list_refs) ) deallocate(self%list_refs)
        call self%pair_kernel%kill()
        call self%pair_tail%kill()
        self%pair_cap   = 0
        self%pair_grown = 0
    end subroutine polarft_workspace_drop_list

    ! the pair-list kernel of cap pairs: its source, launch shape and output, zero past the pairs it is given
    function pair_spec( self, cap ) result(spec)
        class(polarft_workspace), intent(in) :: self
        integer,                  intent(in) :: cap
        type(mlx_custom_kernel_spec) :: spec
        spec%name          = 'polar_pair_products'
        spec%source        = PAIR_SRC
        spec%input_names   = [character(len=4) :: 'bank', 'pt', 'pp', 'pr', 'sz']
        spec%output_names  = [character(len=1) :: 'o']
        spec%output_shapes = [2, self%pftsz + 1, cap]
        spec%output_ranks  = [3]
        spec%output_dtypes = [MLX_DTYPES%float32]
        spec%grid          = [32 * cap * (self%pftsz + 1), 1, 1]
        spec%threadgroup   = [256, 1, 1]
        spec%init_value    = 0.
    end function pair_spec

    module subroutine polarft_workspace_submit_pairs( self, blk, ft_ptcl_wterms, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_block_spec), intent(in)    :: blk
        complex(real32),          intent(in)    :: ft_ptcl_wterms(:,:,:)
        integer,                  intent(out)   :: status
        type(mlx_array), allocatable :: outs(:)
        complex(real32), allocatable :: terms(:,:,:)
        real(real32),    allocatable :: piw(:,:,:), ptm(:,:,:), pu(:,:)
        integer,         allocatable :: pcol(:), pref(:)
        type(mlx_array)              :: pt, ptp, o, c, raw, parts(2), sz, ipp, ipr, aiw, atm, au
        integer                      :: nb, np, n1, b, q, st, slot
        status = 1
        slot   = blk%slot
        self%msg = pair_refusal(self, blk, shape(ft_ptcl_wterms))
        if( len(self%msg) > 0 ) return
        nb = size(blk%islots)
        np = size(blk%irefs)
        n1 = self%pftsz + 1
        ! the capacity: the kernels are made for 1.25 times the pairs, and again when a list outgrows them
        if( np > self%pair_cap )then
            if( self%pair_cap > 0 ) self%pair_grown = self%pair_grown + 1
            self%pair_cap = max(np, (5 * np + 3) / 4)
            if( 32_int64 * int(self%pair_cap, int64) * int(n1, int64) > PAIR_GRID_MAX )then
                self%pair_cap = 0
                self%msg = 'polarft_workspace%submit: refused: the pair list exceeds the pair-list kernel''s grid'
                return
            endif
            self%pair_kernel = mlx_custom_kernel(pair_spec(self, self%pair_cap))
            self%pair_tail   = mlx_custom_kernel(tail_spec(polarft_tile_spec(pftsz=self%pftsz, nk=self%nk, rt=1, &
                &bt=self%pair_cap), .false.))
        endif
        ! the block's particle terms, and per pair its particle, reference, 1/(2 wsq), inverse temperature and
        ! variate, padded to the capacity (the padding's entries are never read)
        allocate(terms(2 * self%nk, n1, nb), pcol(self%pair_cap), pref(self%pair_cap), piw(1, 1, self%pair_cap), &
            &ptm(1, 1, self%pair_cap), pu(1, self%pair_cap))
        pcol = 0
        pref = 0
        piw  = 0._real32
        ptm  = 0._real32
        pu   = 0._real32
        do b = 1, nb
            terms(:, :, b) = ft_ptcl_wterms(:, :, blk%islots(b))
            do q = blk%pair_ptr(b), blk%pair_ptr(b + 1) - 1
                pcol(q)      = b - 1
                pref(q)      = blk%irefs(q) - 1
                piw(1, 1, q) = real(1._real64 / (2._real64 * blk%wsq(b)), real32)
                ptm(1, 1, q) = max(0._real32, blk%temps(b))
                pu(1, q)     = blk%u(1, q)
            end do
        end do
        pt       = mlx_from(terms)
        parts(1) = real(pt)
        parts(2) = aimag(pt)
        ptp      = mlx_concatenate(parts, 1)
        sz       = mlx_from(int([np, n1, 4 * self%nk, self%rt], int32))
        ipp      = mlx_from(int(pcol, int32))
        ipr      = mlx_from(int(pref, int32))
        aiw      = mlx_from(piw)
        atm      = mlx_from(ptm)
        au       = mlx_from(pu)
        call self%pair_kernel%apply([self%refs, ptp, ipp, ipr, sz], outs, st)
        if( st /= 0 )then
            self%msg = 'polarft_workspace%submit: the pair-list kernel failed'
            return
        endif
        o   = outs(1)
        c   = cmplx(reshape(mlx_slice(o, [1, 1, 1], [1, n1, self%pair_cap]), [n1, self%pair_cap]), &
            &reshape(mlx_slice(o, [2, 1, 1], [2, n1, self%pair_cap]), [n1, self%pair_cap]))
        raw = reshape(mlx_irfft(c, 1, n=self%nrots), [self%nrots, 1, self%pair_cap])
        ! the tail of the listed rows in the workspace's form: the fused kernel of the capacity, or the compiled one
        if( self%tail_form == POLARFT_TAILS%metal )then
            call self%pair_tail%apply([raw, aiw, atm, au, self%tail_par], outs, st)
            if( st == 0 )then
                self%slots(slot)%dists = outs(1)
                self%slots(slot)%irots = outs(2)
            endif
        else
            call self%tail%apply([raw, aiw, atm, au], outs, st)
            if( st == 0 )then
                self%slots(slot)%dists = outs(2)
                self%slots(slot)%irots = outs(3)
            endif
        endif
        if( st /= 0 )then
            self%msg = 'polarft_workspace%submit: the pair list''s distances and draw failed'
            return
        endif
        call mlx_async_eval([self%slots(slot)%dists, self%slots(slot)%irots])
        self%slots(slot)%busy   = .true.
        self%slots(slot)%l_rows = .false.
        self%slots(slot)%nrefs  = 1
        self%slots(slot)%nptcls = np
        self%slots(slot)%nrots  = self%nrots
        self%slots(slot)%rpad   = 1
        self%slots(slot)%bpad   = self%pair_cap
        status = 0
    end subroutine polarft_workspace_submit_pairs

    ! the reason a pair-list block cannot be queued, or an empty string; shpt the shape of the particles' terms
    function pair_refusal( self, blk, shpt ) result(msg)
        class(polarft_workspace), intent(in) :: self
        type(polarft_block_spec), intent(in) :: blk
        integer,                  intent(in) :: shpt(3)
        character(len=:), allocatable :: msg
        integer                       :: nb, np
        msg = ''
        if( blk%slot < 1 .or. blk%slot > POLARFT_NSLOTS )then
            msg = 'polarft_workspace%submit: no such slot'
        else if( self%slots(blk%slot)%busy )then
            msg = 'polarft_workspace%submit: the slot holds a block not yet collected'
        else if( .not. self%prepared )then
            msg = 'polarft_workspace%submit: refused: no prepared reference tiles'
        else if( mlx_default_device() /= MLX_DEVICES%gpu )then
            msg = 'polarft_workspace%submit: refused: the pair-list kernel runs on the GPU only'
        else if( .not. allocated(blk%islots) .or. .not. allocated(blk%wsq) .or. .not. allocated(blk%temps) .or. &
            &.not. allocated(blk%u) .or. .not. allocated(blk%irefs) )then
            msg = 'polarft_workspace%submit: refused: the block lacks an input'
        else if( allocated(blk%banks) .or. blk%rows )then
            msg = 'polarft_workspace%submit: refused: the pair-list kernel takes no seed banks and keeps no rows'
        endif
        if( len(msg) > 0 ) return
        nb = size(blk%islots)
        np = size(blk%irefs)
        if( size(blk%pair_ptr) /= nb + 1 .or. np < 1 .or. any(shpt /= [2 * self%nk, self%pftsz + 1, shpt(3)]) .or. &
            &size(blk%wsq) /= nb .or. size(blk%temps) /= nb .or. any(shape(blk%u) /= [1, np]) )then
            msg = 'polarft_workspace%submit: refused: the pair list''s shapes do not match the block'
        else if( blk%pair_ptr(1) /= 1 .or. blk%pair_ptr(nb + 1) /= np + 1 .or. &
            &any(blk%pair_ptr(2:) < blk%pair_ptr(:nb)) )then
            msg = 'polarft_workspace%submit: refused: the pair list''s pointers are not a partition of the references'
        else if( any(blk%irefs < 1 .or. blk%irefs > self%nrefs) )then
            msg = 'polarft_workspace%submit: refused: a reference of the list is not prepared'
        endif
    end function pair_refusal

end submodule mlxf_toy_polarft_workspace_lists
