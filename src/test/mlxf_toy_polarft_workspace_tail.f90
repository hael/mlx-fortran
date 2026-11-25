!@descr: the polar workspace's fused tail: a Metal kernel per tile for the distances and the posterior draw of every pair
! One thread per pair reads the pair's row of the inverse transform in three sweeps: the distances with the
! invalid marker and the first minimum, the weights' compensated sum W, and the same sum again up to the first
! rotation that reaches max(u W, floor). The source sees MLX's layout: the rows (nrots, rt, bt) are MLX's
! [bt, rt, nrots], so pair e of the array element order of (rt, bt) reads raw[e nrots + i]. The rows variant
! writes every distance too. A kernel object is for one tile shape, so a workspace holds one per variant.
submodule (mlxf_toy_polarft_workspace) mlxf_toy_polarft_workspace_tail
use mlxf,           only: mlx_from, mlx_default_device, mlx_metal_kernel_spec, reshape, MLX_DEVICES, MLX_DTYPES
use mlxf_test_defs, only: POLAR_DIST_MAX, POLAR_DIST_INVALID, POLAR_DIST_VALID, POLAR_ARG_CUTOFF, POLAR_DRAW_FLOOR, &
                          POLARFT_TAILS, POLARFT_TAIL_TG
implicit none

character(len=1), parameter :: NL = achar(10)
! the largest pair index times nrots a thread computes in 32-bit unsigned arithmetic
integer(int64), parameter :: TAIL_INDEX_MAX = 4294967295_int64
! the setup and the first sweep up to the distance of rotation i with its marker; par holds the limit, the
! invalid distance, the bound of a valid one, the weight's cutoff and the draw's floor
character(len=*), parameter :: SRC_HEAD = &
    &'uint e = thread_position_in_grid.x;'//NL// &
    &'uint nrots = raw_shape[2];'//NL// &
    &'uint rt = raw_shape[1];'//NL// &
    &'if (e >= raw_shape[0] * rt) return;'//NL// &
    &'uint base = e * nrots;'//NL// &
    &'float w = iw[e / rt];'//NL// &
    &'float tmp = temps[e / rt];'//NL// &
    &'float uu = u[e];'//NL// &
    &'float dmax = par[0];'//NL// &
    &'float dbad = par[1];'//NL// &
    &'float dvalid = par[2];'//NL// &
    &'float cut = par[3];'//NL// &
    &'float flr = par[4];'//NL// &
    &'float dmin = dbad;'//NL// &
    &'uint imin = 0;'//NL// &
    &'for (uint i = 0; i < nrots; ++i) {'//NL// &
    &'  float d = fma(raw[base + i], w, 1.0f);'//NL// &
    &'  if (!(d <= dmax)) d = dbad;'//NL
! the rows variant's statement
character(len=*), parameter :: SRC_ROWS = '  rows[base + i] = d;'//NL
! the first minimum among the valid rotations
character(len=*), parameter :: SRC_MIN = &
    &'  if (d < dvalid && d < dmin) { dmin = d; imin = i; }'//NL// &
    &'}'//NL
! the weight of rotation i, from its distance computed again, added to s with the compensation c
character(len=*), parameter :: SRC_WEIGHT = &
    &'  float d = fma(raw[base + i], w, 1.0f);'//NL// &
    &'  if (!(d <= dmax)) d = dbad;'//NL// &
    &'  if (!(d < dvalid)) continue;'//NL// &
    &'  float a = (d - dmin) * tmp;'//NL// &
    &'  if (!(a < cut)) continue;'//NL// &
    &'  float y = metal::precise::exp(-a) - c;'//NL// &
    &'  float t = s + y;'//NL// &
    &'  c = (t - s) - y;'//NL// &
    &'  s = t;'//NL
! the rotation drawn when no rotation reaches the target: the minimising one (rotation 1 without a valid one)
character(len=*), parameter :: SRC_FALLBACK = 'uint pick = imin;'//NL
! the entry: the distance at the drawn rotation, by the same operation as the row's, and the rotation 1-based
character(len=*), parameter :: SRC_ENTRY = &
    &'float dp = fma(raw[base + pick], w, 1.0f);'//NL// &
    &'if (!(dp <= dmax)) dp = dbad;'//NL// &
    &'dists[e] = dp;'//NL// &
    &'irots[e] = int(pick) + 1;'//NL

contains

    ! the source of the entries-only kernel, or with rows of the rows variant; both from the same pieces
    function tail_source( rows ) result(src)
        logical, intent(in) :: rows
        character(len=:), allocatable :: src
        src = SRC_HEAD
        if( rows ) src = src//SRC_ROWS
        src = src//SRC_MIN//'float s = 0.0f;'//NL//'float c = 0.0f;'//NL//'for (uint i = 0; i < nrots; ++i) {'//NL//&
            &SRC_WEIGHT//'}'//NL//'float tgt = metal::max(uu * s, flr);'//NL//SRC_FALLBACK//'s = 0.0f;'//NL//&
            &'c = 0.0f;'//NL//'for (uint i = 0; i < nrots; ++i) {'//NL//SRC_WEIGHT//&
            &'  if (s >= tgt) { pick = i; break; }'//NL//'}'//NL//SRC_ENTRY
    end function tail_source

    ! the kernel of a tile (nrots, rt, bt) of the tile plan: one thread per pair, grid [rt bt, 1, 1]; with rows
    ! the third output holds every distance as (nrots, rt bt)
    function tail_spec( spec_t, rows ) result(spec)
        type(polarft_tile_spec), intent(in) :: spec_t
        logical,                 intent(in) :: rows
        type(mlx_metal_kernel_spec) :: spec
        integer                     :: np, nrots
        np               = spec_t%rt * spec_t%bt
        nrots            = 2 * spec_t%pftsz
        spec%name        = 'draw_posterior_rvec'
        spec%source      = tail_source(rows)
        spec%input_names = [character(len=5) :: 'raw', 'iw', 'temps', 'u', 'par']
        spec%grid        = [np, 1, 1]
        spec%threadgroup = [min(POLARFT_TAIL_TG, np), 1, 1]
        if( rows )then
            spec%name          = 'draw_posterior_rvec_rows'
            spec%output_names  = [character(len=5) :: 'dists', 'irots', 'rows']
            spec%output_shapes = [spec_t%rt, spec_t%bt, spec_t%rt, spec_t%bt, nrots, np]
            spec%output_ranks  = [2, 2, 2]
            spec%output_dtypes = [MLX_DTYPES%float32, MLX_DTYPES%int32, MLX_DTYPES%float32]
        else
            spec%output_names  = [character(len=5) :: 'dists', 'irots']
            spec%output_shapes = [spec_t%rt, spec_t%bt, spec_t%rt, spec_t%bt]
            spec%output_ranks  = [2, 2]
            spec%output_dtypes = [MLX_DTYPES%float32, MLX_DTYPES%int32]
        endif
    end function tail_spec

    module subroutine polarft_workspace_new_tail( self, spec, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_tile_spec),  intent(in)    :: spec
        integer,                  intent(out)   :: status
        real(real32) :: par(8)
        status = 1
        if( mlx_default_device() /= MLX_DEVICES%gpu )then
            self%msg = 'polarft_workspace%new: refused: the fused tail (metal) runs on the GPU only'
            return
        endif
        if( int(spec%rt, int64) * int(spec%bt, int64) * int(2 * spec%pftsz, int64) > TAIL_INDEX_MAX )then
            self%msg = 'polarft_workspace%new: refused: a tile''s rows do not fit the fused tail''s 32-bit index'
            return
        endif
        par    = 0._real32
        par(1) = real(POLAR_DIST_MAX, real32)
        par(2) = POLAR_DIST_INVALID
        par(3) = POLAR_DIST_VALID
        par(4) = POLAR_ARG_CUTOFF
        par(5) = POLAR_DRAW_FLOOR
        self%tail_par    = mlx_from(par)
        self%tail_kernel = mlx_metal_kernel(tail_spec(spec, .false.))
        self%tail_form   = POLARFT_TAILS%metal
        status = 0
    end subroutine polarft_workspace_new_tail

    module subroutine polarft_workspace_metal_tail( self, tin, rows, tout, status )
        class(polarft_workspace), intent(inout) :: self
        type(tail_inputs),        intent(in)    :: tin
        logical,                  intent(in)    :: rows
        type(tail_outputs),       intent(out)   :: tout
        integer,                  intent(out)   :: status
        type(mlx_array), allocatable :: outs(:)
        if( rows )then
            ! the rows variant, built on the first block that asks for the rows
            if( .not. self%l_tail_rows )then
                self%tail_kernel_rows = mlx_metal_kernel(tail_spec(polarft_tile_spec(pftsz=self%pftsz, nk=self%nk, &
                    &rt=self%rt, bt=self%bt), .true.))
                self%l_tail_rows      = .true.
            endif
            call self%tail_kernel_rows%apply([tin%raw, tin%iw, tin%temps, tin%u, self%tail_par], outs, status)
        else
            call self%tail_kernel%apply([tin%raw, tin%iw, tin%temps, tin%u, self%tail_par], outs, status)
        endif
        if( status /= 0 )then
            self%msg = 'polarft_workspace%submit: the fused distances and draw failed'
            return
        endif
        tout%dists = outs(1)
        tout%irots = outs(2)
        if( rows ) tout%rows = reshape(outs(3), [self%nrots, self%rt, self%bt])
    end subroutine polarft_workspace_metal_tail

end submodule mlxf_toy_polarft_workspace_tail
