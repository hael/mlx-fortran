!@descr: the toy projector's GPU workspace (test only): the padded transform, the expanded cube and the polar gather in two forms
! Every MLX handle of a toy projector lives here. The padded volume's transform, (M/2+1, M, M) scaled by 1/M**3,
! is held from pad_fft to expand_cmat; the expanded cube, SIMPLE's cmat_exp, from expand_cmat to kill_expanded:
! (E, E, E) with E = M + 5, the logical index h of -L .. L (L = M/2 + 2) at h + L + 1 of each dimension, made by
! device gathers from the transform under SIMPLE's cyclic maps (period M + 1 on dimension 1, M on the others) with
! the conjugate of the Friedel mate where the mapped h1 is negative. A projection reads the cube tile by tile of
! directions, either as a graph of library operations (every sample's 27 positions and weights, one mlx_take, a
! sum) or as one Metal kernel per tile with a thread per sample; both follow SIMPLE's fproject_polar_batch_opt:
! the Kaiser-Bessel window of half-width KBWINSZ by its 15-term polynomial, three taps per axis from the base
! sign(t) floor(|t| + 0.5) - 1, each axis divided by its sum, the 27 values summed and multiplied by OSMPL_PAD_FAC**3.
module mlxf_toy_projector_workspace
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf,           only: mlx_array, mlx_metal_kernel, mlx_metal_kernel_spec, mlx_from, mlx_to, mlx_eval, mlx_rfftn, &
                          mlx_take, mlx_slice, mlx_concatenate, mlx_astype, mlx_sign, mlx_zeros_like, &
                          mlx_default_device, reshape, conjg, floor, abs, max, merge, sum, MLX_DTYPES, MLX_DEVICES
use mlxf_test_defs, only: KBWINSZ, KBALPHA, OSMPL_PAD_FAC, PROJ_FORMS, PROJ_TILE_DEFAULT, PROJ_TG_DEFAULT, &
                          fproject_spec
implicit none

public :: projector_workspace
private

character(len=1), parameter :: NL = achar(10)
! the window's polynomial: terms 0 .. NCOEF - 1 of I0's series; the kernel reads them, then 2/W and 1/W
integer, parameter :: NCOEF = 15
! a Metal threadgroup holds at most this many threads on the M5 Ultra
integer, parameter :: TG_MAX = 1024
! the fused gather: one thread per (point, direction) of a tile. hk is (2, npts), rot (2, 3, T): R(1, a) of
! direction d at rot[6 d + 2 a], R(2, a) beside it; the cube is read at (h1 + L) + E ((h2 + L) + E (h3 + L)); the
! sample of point p and direction d is written at p + NPTS d
character(len=*), parameter :: GATHER_SOURCE = &
    &'const uint p = thread_position_in_grid.x;'//NL// &
    &'const uint d = thread_position_in_grid.y;'//NL// &
    &'if (p >= uint(NPTS)) return;'//NL// &
    &'const float px = hk[2 * p];'//NL// &
    &'const float py = hk[2 * p + 1];'//NL// &
    &'const float twoow = coef[15];'//NL// &
    &'const float oneow = coef[16];'//NL// &
    &'int i0[3];'//NL// &
    &'float w[3][3];'//NL// &
    &'for (int a = 0; a < 3; ++a) {'//NL// &
    &'  const float loc = px * rot[6 * d + 2 * a] + py * rot[6 * d + 2 * a + 1];'//NL// &
    &'  const float b = metal::sign(loc) * metal::floor(metal::fabs(loc) + 0.5f);'//NL// &
    &'  i0[a] = int(b) - 1;'//NL// &
    &'  const float base = float(i0[a]) - loc;'//NL// &
    &'  float s = 0.0f;'//NL// &
    &'  for (int i = 0; i < 3; ++i) {'//NL// &
    &'    const float x = base + float(i);'//NL// &
    &'    float r = 0.0f;'//NL// &
    &'    if (!(metal::fabs(x) > 1.5f)) {'//NL// &
    &'      const float q = twoow * x;'//NL// &
    &'      const float u = metal::max(0.0f, 1.0f - q * q);'//NL// &
    &'      float pp = coef[14];'//NL// &
    &'      for (int c = 13; c >= 0; --c) pp = pp * u + coef[c];'//NL// &
    &'      r = oneow * pp;'//NL// &
    &'    }'//NL// &
    &'    w[a][i] = r;'//NL// &
    &'    s += r;'//NL// &
    &'  }'//NL// &
    &'  for (int i = 0; i < 3; ++i) w[a][i] = w[a][i] / s;'//NL// &
    &'}'//NL// &
    &'float fr = 0.0f;'//NL// &
    &'float fi = 0.0f;'//NL// &
    &'for (int l = 0; l < 3; ++l) {'//NL// &
    &'  for (int j = 0; j < 3; ++j) {'//NL// &
    &'    for (int i = 0; i < 3; ++i) {'//NL// &
    &'      const float ww = w[0][i] * w[1][j] * w[2][l];'//NL// &
    &'      const uint pos = uint(i0[0] + i + L) + uint(E) * (uint(i0[1] + j + L) + uint(E) * uint(i0[2] + l + L));'// &
    &NL// &
    &'      const complex64_t c = cube[pos];'//NL// &
    &'      fr += ww * c.real;'//NL// &
    &'      fi += ww * c.imag;'//NL// &
    &'    }'//NL// &
    &'  }'//NL// &
    &'}'//NL// &
    &'out[p + uint(NPTS) * d] = complex64_t(fr * PADS3, fi * PADS3);'

! one projector's device state: m the padded box, the gather's form, its directions per tile and the fused
! kernel's threads per threadgroup; ft the padded transform and cube the expanded cube, with their flags; kern
! the fused gather's kernel objects (1 for a full tile, 2 for the last partial one) and kern_conf the launch each
! was built for (points, directions, threads per group); stage_s the seconds of the expansions and projections
type :: projector_workspace
    private
    integer                       :: m              = 0
    integer                       :: form           = PROJ_FORMS%graph
    integer                       :: tile           = PROJ_TILE_DEFAULT
    integer                       :: tg             = PROJ_TG_DEFAULT
    logical                       :: l_ft           = .false.
    logical                       :: l_cube         = .false.
    integer                       :: kern_conf(3, 2) = 0
    real(real64)                  :: stage_s(2)     = 0._real64
    type(mlx_array)               :: ft
    type(mlx_array)               :: cube
    type(mlx_array)               :: coef
    type(mlx_metal_kernel)        :: kern(2)
    character(len=:), allocatable :: msg
  contains
    procedure :: transform
    procedure :: expand
    procedure :: kill_cube
    procedure :: project
    procedure :: set_form
    procedure :: set_tile
    procedure :: copy_transform
    procedure :: has_transform
    procedure :: has_cube
    procedure :: seconds
    procedure :: set_message
    procedure :: message
    procedure :: kill
    final     :: projector_workspace_final
end type projector_workspace

contains

    ! the padded real cube (M, M, M), its origin at voxel 1, uploaded and transformed: the (M/2+1, M, M) half
    ! spectrum times the single-precision 1/M**3; evaluated, so that the stages are timed apart. The expanded cube
    ! of an earlier transform is released first.
    subroutine transform( self, rpad, status )
        class(projector_workspace), intent(inout) :: self
        real(real32),               intent(in)    :: rpad(:,:,:)
        integer,                    intent(out)   :: status
        type(mlx_array) :: x
        real(real32)    :: scale
        self%msg = ''
        call self%kill_cube()
        call self%ft%kill()
        self%l_ft = .false.
        self%m    = size(rpad, 1)
        scale     = 1._real32 / real(self%m * self%m * self%m, real32)
        x         = mlx_from(rpad)
        self%ft   = mlx_rfftn(x) * scale
        call mlx_eval(self%ft, status=status)
        if( status /= 0 )then
            self%msg = 'projector%pad_fft: the padded transform could not be evaluated'
            call self%ft%kill()
            return
        endif
        self%l_ft = .true.
    end subroutine transform

    ! the expanded cube from the transform by gathers along each dimension, evaluated; the transform is released
    subroutine expand( self, status )
        class(projector_workspace), intent(inout) :: self
        integer,                    intent(out)   :: status
        integer(int32), allocatable :: rpos(:), rneg(:), kpos(:), kneg(:), perm(:)
        type(mlx_array)             :: apos, aneg, both(2), rows
        integer                     :: e, l, h, hp, kp, npos, nneg, i
        integer(int64)              :: t0
        status = 1
        self%msg = ''
        if( .not. self%l_ft )then
            self%msg = 'projector%expand_cmat: refused: the volume has no padded transform (pad_fft)'
            return
        endif
        call self%kill_cube()
        call system_clock(t0)
        e = self%m + 5
        l = self%m / 2 + 2
        allocate(rpos(e), rneg(e), kpos(e), kneg(e), perm(e))
        npos = 0
        nneg = 0
        do h = -l, l
            ! dimension 1 cycles over -M/2 .. M/2 (period M + 1); a negative index reads the mate's conjugate
            hp = modulo(h + self%m / 2, self%m + 1) - self%m / 2
            if( hp >= 0 )then
                npos       = npos + 1
                rpos(npos) = int(1 + hp, int32)
                perm(h + l + 1) = int(npos, int32)
            else
                nneg       = nneg + 1
                rneg(nneg) = int(1 - hp, int32)
                perm(h + l + 1) = -int(nneg, int32)
            endif
            ! dimensions 2 and 3 cycle over -M/2 .. M/2 - 1 (period M), stored at 1 + modulo(k, M)
            kp = modulo(h + self%m / 2, self%m) - self%m / 2
            kpos(h + l + 1) = int(1 + modulo(kp, self%m), int32)
            kneg(h + l + 1) = int(1 + modulo(-kp, self%m), int32)
        end do
        do i = 1, e
            if( perm(i) < 0 ) perm(i) = int(npos, int32) - perm(i)
        end do
        apos    = mlx_take(self%ft, mlx_from(rpos(1:npos)), dim=1)
        apos    = mlx_take(apos, mlx_from(kpos), dim=2)
        both(1) = mlx_take(apos, mlx_from(kpos), dim=3)
        aneg    = mlx_take(self%ft, mlx_from(rneg(1:nneg)), dim=1)
        aneg    = mlx_take(aneg, mlx_from(kneg), dim=2)
        both(2) = conjg(mlx_take(aneg, mlx_from(kneg), dim=3))
        rows      = mlx_concatenate(both, dim=1)
        self%cube = mlx_take(rows, mlx_from(perm), dim=1)
        call apos%kill()
        call aneg%kill()
        call both(1)%kill()
        call both(2)%kill()
        call rows%kill()
        call mlx_eval(self%cube, status=status)
        if( status /= 0 )then
            self%msg = 'projector%expand_cmat: the expanded cube could not be evaluated'
            call self%cube%kill()
            return
        endif
        call self%ft%kill()
        self%l_ft   = .false.
        self%l_cube = .true.
        self%stage_s(1) = self%stage_s(1) + seconds_since(t0)
    end subroutine expand

    subroutine kill_cube( self )
        class(projector_workspace), intent(inout) :: self
        call self%cube%kill()
        self%l_cube = .false.
    end subroutine kill_cube

    ! the gather's form (PROJ_FORMS)
    subroutine set_form( self, form )
        class(projector_workspace), intent(inout) :: self
        integer,                    intent(in)    :: form
        self%msg = ''
        if( form /= PROJ_FORMS%graph .and. form /= PROJ_FORMS%fused )then
            self%msg = 'projector%set_fproject_form: refused: the form is one of PROJ_FORMS'
            return
        endif
        self%form = form
    end subroutine set_form

    ! the gather's directions per tile and the fused kernel's threads per threadgroup
    subroutine set_tile( self, tile, tg )
        class(projector_workspace), intent(inout) :: self
        integer,                    intent(in)    :: tile, tg
        self%msg = ''
        if( tile < 1 )then
            self%msg = 'projector%set_fproject_tile: refused: a tile holds at least one direction'
        else if( tg < 1 .or. tg > TG_MAX )then
            self%msg = 'projector%set_fproject_tile: refused: the threads per threadgroup are 1 .. 1024'
        endif
        if( len(self%msg) > 0 ) return
        self%tile = tile
        self%tg   = tg
    end subroutine set_tile

    ! the bank of sections (npts, nspace) of spec's polar points under its directions' rotation rows, tile by tile,
    ! evaluated. A refusal (message) leaves bank empty and queues nothing.
    subroutine project( self, spec, bank, status )
        class(projector_workspace), intent(inout) :: self
        type(fproject_spec),        intent(in)    :: spec
        type(mlx_array),            intent(out)   :: bank
        integer,                    intent(out)   :: status
        type(mlx_array), allocatable :: parts(:)
        type(mlx_array)              :: hkd, rt
        integer                      :: npts, ntiles, it, d0, tn
        integer(int64)               :: t0
        status = 1
        self%msg = ''
        call check_projection(self, spec)
        if( len(self%msg) > 0 ) return
        call system_clock(t0)
        npts   = size(spec%hk, 2)
        ntiles = (spec%nspace + self%tile - 1) / self%tile
        allocate(parts(ntiles))
        hkd = mlx_from(spec%hk)
        if( self%form == PROJ_FORMS%fused ) self%coef = mlx_from(window_coefficients())
        do it = 1, ntiles
            d0 = (it - 1) * self%tile + 1
            tn = min(self%tile, spec%nspace - d0 + 1)
            rt = mlx_from(spec%rot(:, :, d0:d0+tn-1))
            if( self%form == PROJ_FORMS%fused )then
                call fused_tile(self, hkd, rt, parts(it), status)
            else
                parts(it) = graph_tile(self, hkd, rt, npts, tn)
                call mlx_eval(parts(it), status=status)
            endif
            if( status /= 0 )then
                self%msg = 'projector: the projection of a tile of directions failed'
                return
            endif
        end do
        if( ntiles == 1 )then
            bank = parts(1)
        else
            bank = mlx_concatenate(parts, dim=2)
        endif
        deallocate(parts)
        call mlx_eval(bank, status=status)
        if( status /= 0 )then
            self%msg = 'projector: the bank of sections could not be evaluated'
            call bank%kill()
            return
        endif
        self%stage_s(2) = self%stage_s(2) + seconds_since(t0)
    end subroutine project

    ! the reason a projection is refused, in self%msg (empty when it may go ahead)
    subroutine check_projection( self, spec )
        class(projector_workspace), intent(inout) :: self
        type(fproject_spec),        intent(in)    :: spec
        integer :: i, a, l, dev
        dev = mlx_default_device()
        if( .not. allocated(spec%hk) .or. .not. allocated(spec%rot) )then
            self%msg = 'fproject_polar_batch_opt: refused: no polar points or rotation rows'
        else if( .not. self%l_cube )then
            self%msg = 'fproject_polar_batch_opt: refused: the projector is not expanded (expand_cmat)'
        else if( spec%nk < 1 .or. spec%pftsz < 1 .or. spec%kto < spec%nk )then
            self%msg = 'fproject_polar_batch_opt: refused: invalid kfromto'
        else if( spec%nspace < 1 )then
            self%msg = 'fproject_polar_batch_opt: refused: nspace must be at least 1'
        else if( spec%noris < spec%nspace .or. size(spec%rot, 3) < spec%nspace )then
            self%msg = 'fproject_polar_batch_opt: refused: eulspace smaller than requested nspace'
        else if( any(spec%refs_shape /= [spec%pftsz, spec%nk, spec%nspace]) )then
            self%msg = 'fproject_polar_batch_opt: refused: refs_state is not (pftsz, nk, nspace)'
        else if( size(spec%hk, 1) /= 2 .or. size(spec%hk, 2) /= spec%pftsz * spec%nk .or. size(spec%rot, 1) /= 2 .or. &
            &size(spec%rot, 2) /= 3 )then
            self%msg = 'fproject_polar_batch_opt: refused: the polar points or the rotation rows have the wrong shape'
        else if( self%form == PROJ_FORMS%fused .and. dev /= MLX_DEVICES%gpu )then
            self%msg = 'fproject_polar_batch_opt: refused: the fused gather runs on the GPU only'
        endif
        if( len(self%msg) > 0 ) return
        ! every tap must lie in the cube: nint(2 kto |(R(1,a), R(2,a))|) + 1 <= L on each axis
        l = self%m / 2 + 2
        do i = 1, spec%nspace
            do a = 1, 3
                if( nint(real(OSMPL_PAD_FAC * spec%kto, real32) * sqrt(spec%rot(1, a, i)**2 + spec%rot(2, a, i)**2)) + 1 &
                    & > l )then
                    self%msg = 'fproject_polar_batch_opt: refused: a direction reaches beyond the expanded cube'
                    return
                endif
            end do
        end do
    end subroutine check_projection

    ! one tile's samples (npts, tn) as a graph: coordinates, bases, per-axis weights, positions, one gather, a sum
    function graph_tile( self, hkd, rt, npts, tn ) result(val)
        class(projector_workspace), intent(in) :: self
        type(mlx_array),            intent(in) :: hkd, rt
        integer,                    intent(in) :: npts, tn
        type(mlx_array) :: val
        type(mlx_array) :: hx, hy, r1, r2, loc, b, i0, x, q, u, p, wr, wn, wx, wy, wz, w27, tap, ix, iy, iz, pos, g
        real(real32)    :: c(0:NCOEF+1)
        integer         :: e, l, k
        e = self%m + 5
        l = self%m / 2 + 2
        c = window_coefficients()
        hx  = reshape(mlx_slice(hkd, [1, 1], [1, npts]), [1, npts, 1])
        hy  = reshape(mlx_slice(hkd, [2, 1], [2, npts]), [1, npts, 1])
        r1  = reshape(mlx_slice(rt, [1, 1, 1], [1, 3, tn]), [3, 1, tn])
        r2  = reshape(mlx_slice(rt, [2, 1, 1], [2, 3, tn]), [3, 1, tn])
        ! the rotated padded coordinates (axis, point, direction) and the stencils' first taps
        loc = hx * r1 + hy * r2
        b   = mlx_sign(loc) * floor(abs(loc) + 0.5_real32)
        i0  = b - 1._real32
        ! the three taps' offsets from the coordinate (tap, axis, point, direction) and their window values
        x   = reshape(i0 - loc, [1, 3, npts, tn]) + mlx_from(reshape([0._real32, 1._real32, 2._real32], [3, 1, 1, 1]))
        q   = c(NCOEF) * x
        u   = max(1._real32 - q * q, 0._real32)
        p   = u * c(NCOEF-1) + c(NCOEF-2)
        do k = NCOEF - 3, 0, -1
            p = p * u + c(k)
        end do
        wr  = c(NCOEF+1) * p
        wr  = merge(wr, mlx_zeros_like(wr), abs(x) <= KBWINSZ)
        wn  = wr / sum(wr, dim=1, keepdims=.true.)
        ! the 27 weights, axis 1 fastest, and their positions in the cube (1-based, array element order)
        wx  = reshape(mlx_slice(wn, [1, 1, 1, 1], [3, 1, npts, tn]), [3, 1, 1, npts, tn])
        wy  = reshape(mlx_slice(wn, [1, 2, 1, 1], [3, 2, npts, tn]), [1, 3, 1, npts, tn])
        wz  = reshape(mlx_slice(wn, [1, 3, 1, 1], [3, 3, npts, tn]), [1, 1, 3, npts, tn])
        w27 = reshape(wx * wy * wz, [27, npts, tn])
        tap = mlx_astype(i0, MLX_DTYPES%int32) + mlx_from([int(l + 1, int32)])
        ix  = reshape(mlx_slice(tap, [1, 1, 1], [1, npts, tn]), [1, 1, 1, npts, tn]) + &
              &mlx_from(reshape([0_int32, 1_int32, 2_int32], [3, 1, 1, 1, 1]))
        iy  = reshape(mlx_slice(tap, [2, 1, 1], [2, npts, tn]), [1, 1, 1, npts, tn]) + &
              &mlx_from(reshape([-1_int32, 0_int32, 1_int32], [1, 3, 1, 1, 1]))
        iz  = reshape(mlx_slice(tap, [3, 1, 1], [3, npts, tn]), [1, 1, 1, npts, tn]) + &
              &mlx_from(reshape([-1_int32, 0_int32, 1_int32], [1, 1, 3, 1, 1]))
        pos = reshape(ix + (iy + iz * mlx_from([int(e, int32)])) * mlx_from([int(e, int32)]), [27, npts, tn])
        g   = mlx_take(self%cube, pos)
        val = sum(g * w27, dim=1) * real(OSMPL_PAD_FAC**3, real32)
    end function graph_tile

    ! one tile's samples (npts, tn) by the fused kernel of its launch, built on the first tile that needs it: the
    ! points hk (2, npts), the rotation rows rt (2, 3, tn)
    subroutine fused_tile( self, hkd, rt, val, status )
        class(projector_workspace), intent(inout) :: self
        type(mlx_array),            intent(in)    :: hkd, rt
        type(mlx_array),            intent(out)   :: val
        integer,                    intent(out)   :: status
        type(mlx_array), allocatable :: outs(:)
        integer,         allocatable :: hs(:), rs(:)
        integer                      :: slot, npts, tn
        hs   = hkd%shape()
        rs   = rt%shape()
        npts = hs(2)
        tn   = rs(3)
        slot = 1
        if( tn /= self%tile ) slot = 2
        if( any(self%kern_conf(:, slot) /= [npts, tn, self%tg]) )then
            self%kern(slot) = mlx_metal_kernel(gather_spec(self%m, npts, tn, self%tg))
            self%kern_conf(:, slot) = [npts, tn, self%tg]
        endif
        call self%kern(slot)%apply([self%cube, hkd, rt, self%coef], outs, status)
        if( status /= 0 ) return
        val = outs(1)
        call mlx_eval(val, status=status)
    end subroutine fused_tile

    ! the fused gather's kernel for npts points and tn directions of a padded box m, tg threads per group
    function gather_spec( m, npts, tn, tg ) result(spec)
        integer, intent(in) :: m, npts, tn, tg
        type(mlx_metal_kernel_spec) :: spec
        spec%name               = 'fproject_polar_batch_opt_kernel'
        spec%source             = GATHER_SOURCE
        spec%input_names        = [character(len=4) :: 'cube', 'hk', 'rot', 'coef']
        spec%output_names       = [character(len=3) :: 'out']
        spec%grid               = [npts, tn, 1]
        spec%threadgroup        = [min(tg, npts), 1, 1]
        spec%output_shapes      = [npts, tn]
        spec%output_dtypes      = [MLX_DTYPES%complex64]
        spec%template_int_names = [character(len=5) :: 'E', 'L', 'NPTS', 'PADS3']
        spec%template_ints      = [m + 5, m / 2 + 2, npts, OSMPL_PAD_FAC**3]
    end function gather_spec

    ! the window's coefficients in single precision: (beta**2/4)**j / (j!)**2, j = 0 .. NCOEF - 1, the first terms
    ! of I0's power series in beta**2 u / 4, computed in double precision and rounded once (beta SIMPLE's
    ! pi sqrt((W/alpha)**2 (alpha - 1/2)**2 - 0.8), W = 2 KBWINSZ, alpha = KBALPHA); then 2/W and 1/W as SIMPLE
    ! computes them in single precision
    function window_coefficients() result(c)
        real(real32) :: c(0:NCOEF+1)
        real(real64) :: beta, t
        real(real32) :: w
        integer      :: j
        w    = 2._real32 * KBWINSZ
        beta = acos(-1._real64) * sqrt((real(w, real64)**2 / real(KBALPHA, real64)**2) * &
               &(real(KBALPHA, real64) - 0.5_real64)**2 - 0.8_real64)
        t    = 1._real64
        do j = 0, NCOEF - 1
            c(j) = real(t, real32)
            t    = t * (beta**2 / 4._real64) / real((j + 1)**2, real64)
        end do
        c(NCOEF)   = 2._real32 / w
        c(NCOEF+1) = 1._real32 / w
    end function window_coefficients

    ! the padded transform (M/2+1, M, M) copied to the host, while it is held (between pad_fft and expand_cmat)
    subroutine copy_transform( self, cmat, status )
        class(projector_workspace),   intent(inout) :: self
        complex(real32), allocatable, intent(out)   :: cmat(:,:,:)
        integer,                      intent(out)   :: status
        status = 1
        if( .not. self%l_ft )then
            self%msg = 'projector%get_cmat: refused: no padded transform (pad_fft, before expand_cmat)'
            return
        endif
        allocate(cmat(self%m / 2 + 1, self%m, self%m))
        call mlx_to(cmat, self%ft, status=status)
        if( status /= 0 ) self%msg = 'projector%get_cmat: the transform could not be copied'
    end subroutine copy_transform

    pure logical function has_transform( self )
        class(projector_workspace), intent(in) :: self
        has_transform = self%l_ft
    end function has_transform

    pure logical function has_cube( self )
        class(projector_workspace), intent(in) :: self
        has_cube = self%l_cube
    end function has_cube

    ! the accumulated seconds of the expansions and of the projections
    pure function seconds( self ) result(t)
        class(projector_workspace), intent(in) :: self
        real(real64) :: t(2)
        t = self%stage_s
    end function seconds

    ! the projector's refusals are kept with the workspace's own, so that one message() reports either
    subroutine set_message( self, msg )
        class(projector_workspace), intent(inout) :: self
        character(len=*),           intent(in)    :: msg
        self%msg = msg
    end subroutine set_message

    pure function message( self ) result(msg)
        class(projector_workspace), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

    ! idempotent teardown: the transform, the cube, the kernels and the settings
    subroutine kill( self )
        class(projector_workspace), intent(inout) :: self
        call self%ft%kill()
        call self%cube%kill()
        call self%coef%kill()
        call self%kern(1)%kill()
        call self%kern(2)%kill()
        self%kern_conf = 0
        self%l_ft      = .false.
        self%l_cube    = .false.
        self%m         = 0
        self%form      = PROJ_FORMS%graph
        self%tile      = PROJ_TILE_DEFAULT
        self%tg        = PROJ_TG_DEFAULT
        self%stage_s   = 0._real64
        self%msg       = ''
    end subroutine kill

    subroutine projector_workspace_final( self )
        type(projector_workspace), intent(inout) :: self
        call self%kill()
    end subroutine projector_workspace_final

    real(real64) function seconds_since( t0 )
        integer(int64), intent(in) :: t0
        integer(int64) :: t1, rate
        call system_clock(t1, rate)
        seconds_since = real(t1 - t0, real64) / real(rate, real64)
    end function seconds_since

end module mlxf_toy_projector_workspace
