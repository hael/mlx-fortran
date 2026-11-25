!@descr: host oracle of the Fourier projection and its adjoint: window, explicit matrix, gather, scatter, packed half
! Padded coordinates t = 2 p R (p a row vector); per axis the stencil nint(t) - 1 .. nint(t) + 1 (half away from
! zero) with Kaiser-Bessel weights K(d) = I0(beta sqrt(1 - (d/1.5)**2)) normalised to sum to one, I0 by its power
! series. A signed frequency h of an m-grid is stored at 1 + modulo(h, m); the Hermitian half keeps h1 = 0 .. m/2
! along dimension 1. The route from a real cube is 8 G DFT(vpad) / m**3, with mlxf_oracle_dft's forward DFT.
! The edge index is the first dimension's map of a projector that cycles over -m/2 .. m/2, a period of m + 1.
module mlxf_oracle_projection
use, intrinsic :: iso_fortran_env, only: real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_value, ieee_positive_inf
use mlxf_oracle_dft,  only: oracle_dft_3d, oracle_flat, oracle_rel_error, oracle_finite_or_inf, oracle_all_finite
use mlxf_test_reduce, only: nan_maxval
implicit none

public :: oracle_proj_phantom, oracle_proj_rotation, oracle_proj_polar_coords, oracle_proj_slice_coords, &
          oracle_proj_queries, oracle_proj_stencil, oracle_proj_padded_field, oracle_proj_matrix, oracle_proj_gather, &
          oracle_proj_scatter, oracle_proj_numerator, oracle_proj_density, oracle_proj_route, oracle_proj_pack, &
          oracle_proj_expand, oracle_proj_fold, oracle_proj_packed_gather, oracle_proj_packed_scatter, &
          oracle_proj_multiplicity, oracle_proj_edge_index, oracle_proj_edge_gather, oracle_proj_selfcheck
private

real(real64),    parameter :: PI    = acos(-1._real64)
real(real64),    parameter :: TWOPI = 2._real64 * PI
complex(real64), parameter :: CZERO = (0._real64, 0._real64)
! the phantom's cube and the padding: coordinates scale by PADFAC, the route by PADFAC**3
integer,         parameter :: NBOX   = 6
integer,         parameter :: PADFAC = 2
integer,         parameter :: MPAD   = PADFAC * NBOX
! the two blobs: centres in centred coordinates, the second's amplitude and width
real(real64),    parameter :: BLOB1(3)    = [-1._real64, 0._real64, 1._real64]
real(real64),    parameter :: BLOB2(3)    = [1._real64, 1._real64, -1._real64]
real(real64),    parameter :: BLOB2_AMP   = 0.7_real64
real(real64),    parameter :: BLOB2_SIGMA = 0.7_real64
! the polar set: angles on the full ring, shells, rotations
integer,         parameter :: NANG   = 12
integer,         parameter :: NSHELL = 2
integer,         parameter :: NROT   = 3
integer,         parameter :: NPOLAR = NANG * NSHELL * NROT
! the Cartesian half slice (h, k, 0), h = 0 .. SLICE_H, k = -SLICE_K .. SLICE_K, under each rotation
integer,         parameter :: SLICE_H = 2
integer,         parameter :: SLICE_K = 2
integer,         parameter :: NSLICE  = (SLICE_H + 1) * (2 * SLICE_K + 1) * NROT
! the rotations R(i,j), written by rows: the identity, a quarter turn about z, Rz(3/5, 4/5) Ry(5/13, 12/13)
real(real64),    parameter :: R_IDENTITY(3, 3) = reshape([1._real64, 0._real64, 0._real64, 0._real64, 1._real64, &
                                                         0._real64, 0._real64, 0._real64, 1._real64], [3, 3], order=[2, 1])
real(real64),    parameter :: R_QUARTER(3, 3)  = reshape([0._real64, -1._real64, 0._real64, 1._real64, 0._real64, &
                                                         0._real64, 0._real64, 0._real64, 1._real64], [3, 3], order=[2, 1])
real(real64),    parameter :: R_OBLIQUE(3, 3)  = reshape([15._real64, -52._real64, 36._real64, 20._real64, 39._real64, &
                                                         48._real64, -60._real64, 0._real64, 25._real64], [3, 3], &
                                                         order=[2, 1]) / 65._real64
! the boundary queries, padded coordinates by columns: half-integers about zero, Nyquist and the wrap
integer, parameter :: NQUERY = 4
real(real64),    parameter :: QUERIES(3, NQUERY) = reshape([0.5_real64, -0.5_real64, 1.5_real64, -1.5_real64, &
                                                           2.5_real64, -2.5_real64, 5.5_real64, -5.5_real64, 6._real64, &
                                                           -5.5_real64, 0._real64, -6._real64], [3, NQUERY])
! the window: three points, half-width 1.5, shape parameter of a width-3 window at oversampling 2
real(real64),    parameter :: KB_HALF = 1.5_real64
real(real64),    parameter :: KB_BETA = PI * sqrt((3._real64 / 2._real64)**2 * (2._real64 - 0.5_real64)**2 - 0.8_real64)
integer,         parameter :: MAXTERM = 500
! the self-check: points of the trapezoid rule for I0, the least distance of a sample coordinate from a
! half-integer, and the limits of the transform, entry, element and adjoint checks; exact checks have limit 0
integer,         parameter :: NTRAP         = 64
real(real64),    parameter :: MIN_MARGIN    = 1.e-4_real64
real(real64),    parameter :: TOL_TRANSFORM = 1.e-12_real64
real(real64),    parameter :: TOL_ENTRY     = 1.e-13_real64
real(real64),    parameter :: TOL_ELEMENT   = 1.e-13_real64
real(real64),    parameter :: TOL_ADJOINT   = 1.e-12_real64
complex(real64), parameter :: CONSTANT      = (0.75_real64, -1.25_real64)
! the window pinned from outside KB_BETA: its weights at an integer coordinate as read elsewhere to seven
! digits, with the limit those digits allow, and pi sqrt(4.2625) typed on its own
real(real64),    parameter :: W0_READ    = 0.6906488_real64
real(real64),    parameter :: W1_READ    = 0.1546756_real64
real(real64),    parameter :: TOL_READ   = 5.e-7_real64
real(real64),    parameter :: BETA_TYPED = 6.48607653051083_real64
! coordinates whose first-dimension stencils reach the two columns beyond Nyquist on either side
integer, parameter :: NEDGE = 4
real(real64),    parameter :: EDGE_QUERIES(3, NEDGE) = reshape([6.75_real64, 0.25_real64, -6._real64, -6.75_real64, &
                                                              5.5_real64, 1.25_real64, 7.25_real64, -2.5_real64, &
                                                              3.75_real64, -7.25_real64, 6._real64, -0.5_real64], &
                                                             [3, NEDGE])
integer,         parameter :: NCHECK    = 32
integer,         parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'counts', 'margins', 'rotations', 'coordinates', 'stencil bases', 'i0 series', 'boundary weights', &
    'matrix pattern', 'matrix entries', 'gather vs matrix', 'constant field', 'scatter vs matrix', &
    'numerator vs matrix', 'density vs matrix', 'totals', 'adjoint plain', 'adjoint with D', 'packed gather', &
    'packed fold', 'packed adjoint', 'unit point', 'off-centre point', 'friedel mates', 'pack expand', &
    'multiplicity', 'row duplicates', 'window weights', 'window beta', 'pack expand phantom', 'edge index', &
    'edge samples', 'edge gather']
real(real64),    parameter :: CHECK_LIMITS(NCHECK) = [0._real64, 0._real64, TOL_ENTRY, TOL_ENTRY, 0._real64, &
    TOL_TRANSFORM, TOL_ENTRY, 0._real64, TOL_ENTRY, TOL_ELEMENT, TOL_ELEMENT, TOL_ELEMENT, TOL_ELEMENT, &
    TOL_ELEMENT, TOL_ELEMENT, TOL_ADJOINT, TOL_ADJOINT, TOL_ELEMENT, TOL_ELEMENT, TOL_ADJOINT, TOL_TRANSFORM, &
    TOL_TRANSFORM, TOL_TRANSFORM, 0._real64, TOL_ADJOINT, TOL_ENTRY, TOL_READ, TOL_ENTRY, TOL_TRANSFORM, 0._real64, &
    0._real64, TOL_ELEMENT]

contains

    ! the asymmetric two-blob phantom on the NBOX cube, at centred coordinates x = i - 1 - NBOX/2
    pure function oracle_proj_phantom() result(v)
        real(real64) :: v(NBOX, NBOX, NBOX)
        real(real64) :: x(3)
        integer      :: i1, i2, i3
        do i3 = 1, NBOX
            do i2 = 1, NBOX
                do i1 = 1, NBOX
                    x           = real([i1, i2, i3] - 1 - NBOX / 2, real64)
                    v(i1, i2, i3) = exp(-sum((x - BLOB1)**2) / 2._real64) + &
                                  BLOB2_AMP * exp(-sum((x - BLOB2)**2) / (2._real64 * BLOB2_SIGMA**2))
                end do
            end do
        end do
    end function oracle_proj_phantom

    ! rotation irot = 1, 2, 3 of the fixture; zero for any other number
    pure function oracle_proj_rotation( irot ) result(r)
        integer, intent(in) :: irot
        real(real64) :: r(3, 3)
        select case( irot )
            case( 1 )
                r = R_IDENTITY
            case( 2 )
                r = R_QUARTER
            case( 3 )
                r = R_OBLIQUE
            case default
                r = 0._real64
        end select
    end function oracle_proj_rotation

    ! the polar samples' padded coordinates 2 p R, p = (k sin a, -k cos a, 0), a = 2 pi (j - 1) / NANG: angle
    ! fastest, then shell k = 1 .. NSHELL, then rotation
    pure function oracle_proj_polar_coords() result(t)
        real(real64) :: t(3, NPOLAR)
        real(real64) :: p(3), angle
        integer      :: irot, k, ia, s
        s = 0
        do irot = 1, NROT
            do k = 1, NSHELL
                do ia = 1, NANG
                    angle   = TWOPI * real(ia - 1, real64) / real(NANG, real64)
                    p       = [real(k, real64) * sin(angle), -real(k, real64) * cos(angle), 0._real64]
                    s       = s + 1
                    t(:, s) = real(PADFAC, real64) * matmul(p, oracle_proj_rotation(irot))
                end do
            end do
        end do
    end function oracle_proj_polar_coords

    ! the Cartesian half slice's padded coordinates 2 p R, p = (h, k, 0): h fastest, then k, then rotation
    pure function oracle_proj_slice_coords() result(t)
        real(real64) :: t(3, NSLICE)
        integer      :: irot, h, k, s
        s = 0
        do irot = 1, NROT
            do k = -SLICE_K, SLICE_K
                do h = 0, SLICE_H
                    s       = s + 1
                    t(:, s) = real(PADFAC, real64) * matmul(real([h, k, 0], real64), oracle_proj_rotation(irot))
                end do
            end do
        end do
    end function oracle_proj_slice_coords

    ! the boundary queries' padded coordinates, given directly
    pure function oracle_proj_queries() result(t)
        real(real64) :: t(3, NQUERY)
        t = QUERIES
    end function oracle_proj_queries

    ! one axis's stencil: the signed frequencies nint(t) - 1, nint(t), nint(t) + 1 and their weights, which sum to one
    pure subroutine oracle_proj_stencil( t, h, w )
        real(real64), intent(in)  :: t
        integer,      intent(out) :: h(3)
        real(real64), intent(out) :: w(3)
        integer :: j
        h = nint(t) + [-1, 0, 1]
        do j = 1, 3
            w(j) = kb_window(t - real(h(j), real64))
        end do
        w = w / sum(w)
    end subroutine oracle_proj_stencil

    ! the DFT of a real cube of even side n centre-padded to m = PADFAC n, divided by m**3: the voxel at centred
    ! x = i - 1 - n/2 is placed at 1 + modulo(x, m), so the centre sits at the DFT origin
    pure function oracle_proj_padded_field( v ) result(f)
        real(real64), intent(in) :: v(:,:,:)
        complex(real64) :: f(PADFAC*size(v, 1), PADFAC*size(v, 1), PADFAC*size(v, 1))
        integer         :: n, m, i1, i2, i3, j(3)
        n = size(v, 1)
        m = PADFAC * n
        f = CZERO
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    j                   = 1 + modulo([i1, i2, i3] - 1 - n / 2, m)
                    f(j(1), j(2), j(3)) = cmplx(v(i1, i2, i3), 0._real64, real64)
                end do
            end do
        end do
        f = oracle_dft_3d(f) / real(m, real64)**3
    end function oracle_proj_padded_field

    ! the explicit matrix from scalar geometry, without the stencil: a row per sample, a column per voxel of the
    ! m-grid in Fortran order, each entry the product of the three axes' weights of that voxel
    pure function oracle_proj_matrix( t, m ) result(g)
        real(real64), intent(in) :: t(:,:)
        integer,      intent(in) :: m
        real(real64) :: g(size(t, 2), m**3)
        real(real64) :: wa(m, 3)
        integer      :: s, a, i1, i2, i3
        do s = 1, size(t, 2)
            do a = 1, 3
                wa(:, a) = axis_weights(t(a, s), m)
            end do
            do i3 = 1, m
                do i2 = 1, m
                    do i1 = 1, m
                        g(s, i1+m*(i2-1)+m*m*(i3-1)) = wa(i1, 1) * wa(i2, 2) * wa(i3, 3)
                    end do
                end do
            end do
        end do
    end function oracle_proj_matrix

    ! the gather G f at padded coordinates t from a field on a cubic grid
    pure function oracle_proj_gather( t, f ) result(y)
        real(real64),    intent(in) :: t(:,:)
        complex(real64), intent(in) :: f(:,:,:)
        complex(real64) :: y(size(t, 2))
        real(real64)    :: w(27)
        integer         :: h(3, 27), s, n, m
        m = size(f, 1)
        do s = 1, size(t, 2)
            call stencil_27(t(:, s), h, w)
            y(s) = CZERO
            do n = 1, 27
                y(s) = y(s) + w(n) * f(1+modulo(h(1, n), m), 1+modulo(h(2, n), m), 1+modulo(h(3, n), m))
            end do
        end do
    end function oracle_proj_gather

    ! the adjoint G^T y on the m-grid: each sample's 27 contributions added at their destinations
    pure function oracle_proj_scatter( t, y, m ) result(g)
        real(real64),    intent(in) :: t(:,:)
        complex(real64), intent(in) :: y(:)
        integer,         intent(in) :: m
        complex(real64) :: g(m, m, m)
        real(real64)    :: w(27)
        integer         :: h(3, 27), s, n, i1, i2, i3
        g = CZERO
        do s = 1, size(t, 2)
            call stencil_27(t(:, s), h, w)
            do n = 1, 27
                i1            = 1 + modulo(h(1, n), m)
                i2            = 1 + modulo(h(2, n), m)
                i3            = 1 + modulo(h(3, n), m)
                g(i1, i2, i3) = g(i1, i2, i3) + w(n) * y(s)
            end do
        end do
    end function oracle_proj_scatter

    ! the gridding numerator G^T (w conj(d) y) of observations y with factors d and positive weights w
    pure function oracle_proj_numerator( t, y, d, w, m ) result(g)
        real(real64),    intent(in) :: t(:,:)
        complex(real64), intent(in) :: y(:), d(:)
        real(real64),    intent(in) :: w(:)
        integer,         intent(in) :: m
        complex(real64) :: g(m, m, m)
        g = oracle_proj_scatter(t, w * conjg(d) * y, m)
    end function oracle_proj_numerator

    ! the gridding density G^T (w |d|**2): the stencil weights once, not squared
    pure function oracle_proj_density( t, d, w, m ) result(r)
        real(real64),    intent(in) :: t(:,:)
        complex(real64), intent(in) :: d(:)
        real(real64),    intent(in) :: w(:)
        integer,         intent(in) :: m
        real(real64) :: r(m, m, m)
        r = real(oracle_proj_scatter(t, cmplx(w * abs(d)**2, 0._real64, real64), m))
    end function oracle_proj_density

    ! the projection of a real cube at padded coordinates t: PADFAC**3 G DFT(vpad) / m**3, by the explicit matrix
    pure function oracle_proj_route( v, t ) result(y)
        real(real64), intent(in) :: v(:,:,:), t(:,:)
        complex(real64) :: y(size(t, 2))
        complex(real64) :: f(PADFAC*size(v, 1), PADFAC*size(v, 1), PADFAC*size(v, 1))
        f = oracle_proj_padded_field(v)
        y = real(PADFAC**3, real64) * matmul(oracle_proj_matrix(t, size(f, 1)), reshape(f, [size(f)]))
    end function oracle_proj_route

    ! the Hermitian half along dimension 1 of a full m-grid: h1 = 0 .. m/2
    pure function oracle_proj_pack( f ) result(p)
        complex(real64), intent(in) :: f(:,:,:)
        complex(real64) :: p(size(f, 1)/2+1, size(f, 2), size(f, 3))
        p = f(1:size(f, 1)/2+1, :,:)
    end function oracle_proj_pack

    ! the full m-grid of a packed half: h1 = 0 .. m/2 as stored, h1 < 0 the conjugate of the Friedel mate
    pure function oracle_proj_expand( p ) result(f)
        complex(real64), intent(in) :: p(:,:,:)
        complex(real64) :: f(size(p, 2), size(p, 2), size(p, 2))
        integer         :: m, i1, i2, i3
        m               = size(p, 2)
        f(1:m/2+1, :,:) = p
        do i3 = 1, m
            do i2 = 1, m
                do i1 = m / 2 + 2, m
                    f(i1, i2, i3) = conjg(p(mirror(i1, m), mirror(i2, m), mirror(i3, m)))
                end do
            end do
        end do
    end function oracle_proj_expand

    ! the fold of a full m-grid into the packed half, the adjoint of the expansion: h1 < 0 adds its conjugate
    ! to the Friedel mate
    pure function oracle_proj_fold( g ) result(p)
        complex(real64), intent(in) :: g(:,:,:)
        complex(real64) :: p(size(g, 1)/2+1, size(g, 2), size(g, 3))
        integer         :: m, i1, i2, i3
        m = size(g, 1)
        p = g(1:m/2+1, :,:)
        do i3 = 1, m
            do i2 = 1, m
                do i1 = m / 2 + 2, m
                    p(mirror(i1, m), mirror(i2, m), mirror(i3, m)) = p(mirror(i1, m), mirror(i2, m), mirror(i3, m)) + &
                                                                   conjg(g(i1, i2, i3))
                end do
            end do
        end do
    end function oracle_proj_fold

    ! the gather from a packed half: a stencil entry with modulo(h1, m) beyond m/2 reads the mate's conjugate
    pure function oracle_proj_packed_gather( t, p ) result(y)
        real(real64),    intent(in) :: t(:,:)
        complex(real64), intent(in) :: p(:,:,:)
        complex(real64) :: y(size(t, 2))
        real(real64)    :: w(27)
        integer         :: h(3, 27), s, n, m
        m = size(p, 2)
        do s = 1, size(t, 2)
            call stencil_27(t(:, s), h, w)
            y(s) = CZERO
            do n = 1, 27
                if( modulo(h(1, n), m) <= m / 2 )then
                    y(s) = y(s) + w(n) * p(1+modulo(h(1, n), m), 1+modulo(h(2, n), m), 1+modulo(h(3, n), m))
                else
                    y(s) = y(s) + w(n) * conjg(p(1+modulo(-h(1, n), m), 1+modulo(-h(2, n), m), 1+modulo(-h(3, n), m)))
                endif
            end do
        end do
    end function oracle_proj_packed_gather

    ! the scatter into a packed half: a contribution with modulo(h1, m) beyond m/2 adds its conjugate to the mate
    pure function oracle_proj_packed_scatter( t, y, m ) result(p)
        real(real64),    intent(in) :: t(:,:)
        complex(real64), intent(in) :: y(:)
        integer,         intent(in) :: m
        complex(real64) :: p(m/2+1, m, m)
        complex(real64) :: c
        real(real64)    :: w(27)
        integer         :: h(3, 27), s, n, j(3)
        p = CZERO
        do s = 1, size(t, 2)
            call stencil_27(t(:, s), h, w)
            do n = 1, 27
                c = w(n) * y(s)
                if( modulo(h(1, n), m) <= m / 2 )then
                    j = 1 + modulo(h(:, n), m)
                else
                    j = 1 + modulo(-h(:, n), m)
                    c = conjg(c)
                endif
                p(j(1), j(2), j(3)) = p(j(1), j(2), j(3)) + c
            end do
        end do
    end function oracle_proj_packed_scatter

    ! the multiplicity of each packed plane in the full grid: 1 at h1 = 0 and m/2, 2 between
    pure function oracle_proj_multiplicity( m ) result(mu)
        integer, intent(in) :: m
        real(real64) :: mu(m/2+1)
        mu        = 2._real64
        mu(1)     = 1._real64
        mu(m/2+1) = 1._real64
    end function oracle_proj_multiplicity

    ! the first dimension's index as a projector reads it at the grid's edge: h itself on -m/2 .. m/2 and, beyond,
    ! the cycle of length m + 1, so m/2 + 1 reads -m/2 and -m/2 - 1 reads m/2; stated for |h| <= m/2 + 2
    elemental function oracle_proj_edge_index( h, m ) result(c)
        integer, intent(in) :: h, m
        integer :: c
        c = modulo(h + m / 2, m + 1) - m / 2
    end function oracle_proj_edge_index

    ! the gather from a packed half with the edge index on dimension 1 and the periodic one on dimensions 2 and 3:
    ! a negative edge index reads the conjugate of the Friedel mate
    pure function oracle_proj_edge_gather( t, p ) result(y)
        real(real64),    intent(in) :: t(:,:)
        complex(real64), intent(in) :: p(:,:,:)
        complex(real64) :: y(size(t, 2))
        real(real64)    :: w(27)
        integer         :: h(3, 27), s, n, m, c
        m = size(p, 2)
        do s = 1, size(t, 2)
            call stencil_27(t(:, s), h, w)
            y(s) = CZERO
            do n = 1, 27
                c = oracle_proj_edge_index(h(1, n), m)
                if( c >= 0 )then
                    y(s) = y(s) + w(n) * p(1+c, 1+modulo(h(2, n), m), 1+modulo(h(3, n), m))
                else
                    y(s) = y(s) + w(n) * conjg(p(1-c, 1+modulo(-h(2, n), m), 1+modulo(-h(3, n), m)))
                endif
            end do
        end do
    end function oracle_proj_edge_gather

    ! the checks against closed forms and the explicit matrix, as named largest errors and their limits; the
    ! operator checks take the largest over the polar set, the Cartesian slice and the boundary queries
    subroutine oracle_proj_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        limits = CHECK_LIMITS
        errors = 0._real64
        call check_geometry(errors(1:7))
        call check_set(oracle_proj_polar_coords(), errors(8:20))
        call check_set(oracle_proj_slice_coords(), errors(8:20))
        call check_set(oracle_proj_queries(), errors(8:20))
        call check_route(oracle_proj_polar_coords(), errors(21:22))
        call check_route(oracle_proj_slice_coords(), errors(21:22))
        call check_route(oracle_proj_queries(), errors(21:22))
        call check_friedel(errors(23))
        call check_packing(errors(24:25))
        call check_duplicates(oracle_proj_polar_coords(), errors(26))
        call check_duplicates(oracle_proj_slice_coords(), errors(26))
        call check_duplicates(oracle_proj_queries(), errors(26))
        call check_window(errors(27:28))
        call check_phantom_half(errors(29))
        call check_edge_index(errors(30:31))
        call check_edge_gather(oracle_proj_polar_coords(), errors(32))
        call check_edge_gather(oracle_proj_slice_coords(), errors(32))
        call check_edge_gather(oracle_proj_queries(), errors(32))
        call check_edge_gather(EDGE_QUERIES, errors(32))
    end subroutine oracle_proj_selfcheck

    ! the window K(d) = I0(beta sqrt(1 - (d/1.5)**2)) inside |d| <= 1.5, zero outside
    pure function kb_window( delta ) result(k)
        real(real64), intent(in) :: delta
        real(real64) :: k
        if( abs(delta) <= KB_HALF )then
            k = i0_series(KB_BETA * sqrt(max(0._real64, 1._real64 - (delta / KB_HALF)**2)))
        else
            k = 0._real64
        endif
    end function kb_window

    ! I0 by its power series, summed until a term no longer changes the sum
    pure function i0_series( x ) result(s)
        real(real64), intent(in) :: x
        real(real64) :: s, term
        integer      :: k
        s    = 1._real64
        term = 1._real64
        do k = 1, MAXTERM
            term = term * (x / 2._real64)**2 / real(k, real64)**2
            s    = s + term
            if( term < epsilon(s) * s ) exit
        end do
    end function i0_series

    ! I0 by the trapezoid rule on one turn of exp(x cos u), which converges spectrally: an independent evaluation
    pure function i0_trapezoid( x ) result(s)
        real(real64), intent(in) :: x
        real(real64) :: s
        integer      :: j
        s = 0._real64
        do j = 0, NTRAP - 1
            s = s + exp(x * cos(TWOPI * real(j, real64) / real(NTRAP, real64)))
        end do
        s = s / real(NTRAP, real64)
    end function i0_trapezoid

    ! the 27 signed frequencies of a 3D coordinate's stencil, dimension 1 fastest, and their weights
    pure subroutine stencil_27( t, h, w )
        real(real64), intent(in)  :: t(3)
        integer,      intent(out) :: h(3, 27)
        real(real64), intent(out) :: w(27)
        real(real64) :: wa(3, 3)
        integer      :: ha(3, 3), a, j1, j2, j3, n
        do a = 1, 3
            call oracle_proj_stencil(t(a), ha(:, a), wa(:, a))
        end do
        n = 0
        do j3 = 1, 3
            do j2 = 1, 3
                do j1 = 1, 3
                    n       = n + 1
                    h(:, n) = [ha(j1, 1), ha(j2, 2), ha(j3, 3)]
                    w(n)    = wa(j1, 1) * wa(j2, 2) * wa(j3, 3)
                end do
            end do
        end do
    end subroutine stencil_27

    ! one axis's weight on each of the m voxel indices: index i collects every periodic image h = i - 1 + j m with
    ! |h - nint(t)| <= 1, weighted by the window at t - h; normalised over the indices
    pure function axis_weights( t, m ) result(wa)
        real(real64), intent(in) :: t
        integer,      intent(in) :: m
        real(real64) :: wa(m)
        integer      :: i, j, b
        b = nint(t)
        do i = 1, m
            wa(i) = 0._real64
            do j = -floor_div(-(b - 1 - (i - 1)), m), floor_div(b + 1 - (i - 1), m)
                wa(i) = wa(i) + kb_window(t - real(i - 1 + j * m, real64))
            end do
        end do
        wa = wa / sum(wa)
    end function axis_weights

    ! floor(a / m) in integers, for m > 0
    pure function floor_div( a, m ) result(q)
        integer, intent(in) :: a, m
        integer :: q
        q = (a - modulo(a, m)) / m
    end function floor_div

    ! the index of the Friedel mate on an m-grid: 1 + modulo(-(i - 1), m)
    pure function mirror( i, m ) result(j)
        integer, intent(in) :: i, m
        integer :: j
        j = 1 + modulo(1 - i, m)
    end function mirror

    ! counts, margins, rotations, hand-worked coordinates, stencil bases, I0 and the boundary weights
    subroutine check_geometry( err )
        real(real64), intent(inout) :: err(7)
        real(real64) :: tp(3, NPOLAR), ts(3, NSLICE)
        real(real64) :: r(3, 3), wq(3), wref(3), k0, k1, kh, tq
        integer      :: hq(3), irot, iq, a, j, nbad
        tp = oracle_proj_polar_coords()
        ts = oracle_proj_slice_coords()
        ! counts: the sets, the padded and packed grids, and the multiplicities covering the full grid once
        nbad = 0
        if( size(tp, 2) /= 72 ) nbad = nbad + 1
        if( size(ts, 2) /= 45 ) nbad = nbad + 1
        if( size(oracle_proj_queries(), 2) /= 4 ) nbad = nbad + 1
        if( MPAD**3 /= 1728 ) nbad = nbad + 1
        if( size(oracle_proj_pack(oracle_proj_padded_field(oracle_proj_phantom()))) /= 1008 ) nbad = nbad + 1
        if( nint(sum(oracle_proj_multiplicity(MPAD)) * real(MPAD**2, real64)) /= MPAD**3 ) nbad = nbad + 1
        err(1) = real(nbad, real64)
        ! no polar or slice coordinate within MIN_MARGIN of a half-integer
        err(2) = real(count(abs(modulo(tp, 1._real64) - 0.5_real64) < MIN_MARGIN) + &
                      count(abs(modulo(ts, 1._real64) - 0.5_real64) < MIN_MARGIN), real64)
        ! rotations: orthonormal with determinant one; the oblique equals Rz(3/5, 4/5) Ry(5/13, 12/13), the quarter
        ! turn Rz(0, 1)
        do irot = 1, NROT
            r      = oracle_proj_rotation(irot)
            err(3) = max(err(3), oracle_finite_or_inf(nan_maxval(abs(matmul(r, transpose(r)) - R_IDENTITY))), &
                         oracle_finite_or_inf(abs(det3(r) - 1._real64)))
            if( .not. all(ieee_is_finite(r)) ) err(3) = ieee_value(err(3), ieee_positive_inf)
        end do
        err(3) = max(err(3), oracle_finite_or_inf(nan_maxval(abs(matmul(rot_z(0.6_real64, 0.8_real64), &
                                                                   rot_y(5._real64 / 13._real64, 12._real64 / 13._real64)) - &
                                                            R_OBLIQUE))), &
                     oracle_finite_or_inf(nan_maxval(abs(rot_z(0._real64, 1._real64) - R_QUARTER))))
        ! coordinates worked by hand: polar sample a + 12 (k - 1) + 24 (rotation - 1), slice sample
        ! 1 + h + 3 (k + 2) + 15 (rotation - 1)
        err(4) = max(nan_maxval(abs(tp(:, 1) - [0._real64, -2._real64, 0._real64])), &
                     nan_maxval(abs(tp(:, 16) - [4._real64, 0._real64, 0._real64])), &
                     nan_maxval(abs(tp(:, 25) - [-2._real64, 0._real64, 0._real64])), &
                     nan_maxval(abs(tp(:, 28) - [0._real64, -2._real64, 0._real64])), &
                     nan_maxval(abs(tp(:, 49) + [40._real64, 78._real64, 96._real64] / 65._real64)), &
                     nan_maxval(abs(tp(:, 64) - [60._real64, -208._real64, 144._real64] / 65._real64)), &
                     nan_maxval(abs(tp(:, 51) - [15._real64 * sqrt(3._real64) - 20._real64, &
                                            -52._real64 * sqrt(3._real64) - 39._real64, &
                                            36._real64 * sqrt(3._real64) - 48._real64] / 65._real64)), &
                     nan_maxval(abs(ts(:, 33) - [-4._real64 / 13._real64, -28._real64 / 5._real64, -48._real64 / 65._real64])), &
                     nan_maxval(abs(ts(:, 29) - [4._real64, -2._real64, 0._real64])))
        ! maxval and max may pass over a NaN, so the coordinates are tested first
        if( .not. (all(ieee_is_finite(tp)) .and. all(ieee_is_finite(ts))) )then
            err(4) = ieee_value(err(4), ieee_positive_inf)
        endif
        err(4) = oracle_finite_or_inf(err(4))
        ! stencil bases by nint, half away from zero; the queries' bases and their wrapped indices
        nbad = 0
        do j = -2, 3
            call oracle_proj_stencil(real(j, real64) - 0.5_real64, hq, wq)
            if( hq(2) /= merge(j, j - 1, j > 0) ) nbad = nbad + 1
        end do
        nbad = nbad + count(base_of(QUERIES(:, 1)) /= [1, -1, 2]) + count(base_of(QUERIES(:, 2)) /= [-2, 3, -3]) + &
               count(base_of(QUERIES(:, 3)) /= [6, -6, 6]) + count(base_of(QUERIES(:, 4)) /= [-6, 0, -6])
        call oracle_proj_stencil(QUERIES(1, 3), hq, wq)
        nbad = nbad + count(1 + modulo(hq, MPAD) /= [6, 7, 8])
        call oracle_proj_stencil(QUERIES(2, 3), hq, wq)
        nbad = nbad + count(1 + modulo(hq, MPAD) /= [6, 7, 8])
        call oracle_proj_stencil(QUERIES(2, 4), hq, wq)
        nbad = nbad + count(1 + modulo(hq, MPAD) /= [12, 1, 2])
        err(5) = real(nbad, real64)
        ! I0 by its series against the trapezoid rule, at the window's arguments for |d| = 0, 0.125, .., 1.5
        do j = 0, 12
            tq     = KB_BETA * sqrt(max(0._real64, 1._real64 - (real(j, real64) / 8._real64 / KB_HALF)**2))
            err(6) = max(err(6), oracle_finite_or_inf(abs(i0_series(tq) - i0_trapezoid(tq)) / i0_trapezoid(tq)))
        end do
        ! the queries' weights against closed forms with I0 by the trapezoid rule: an integer t weighs
        ! (K1, K0, K1), a half-integer above zero (Kh, Kh, 1), below zero (1, Kh, Kh), each over its sum
        k0 = i0_trapezoid(KB_BETA)
        k1 = i0_trapezoid(KB_BETA * sqrt(1._real64 - (1._real64 / KB_HALF)**2))
        kh = i0_trapezoid(KB_BETA * sqrt(1._real64 - (0.5_real64 / KB_HALF)**2))
        do iq = 1, NQUERY
            do a = 1, 3
                tq = QUERIES(a, iq)
                call oracle_proj_stencil(tq, hq, wq)
                if( abs(tq - anint(tq)) < 0.25_real64 )then
                    wref = [k1, k0, k1]
                else if( tq > 0._real64 )then
                    wref = [kh, kh, 1._real64]
                else
                    wref = [1._real64, kh, kh]
                endif
                err(7) = max(err(7), oracle_finite_or_inf(nan_maxval(abs(wq - wref / sum(wref)))))
            end do
        end do
    end subroutine check_geometry

    ! the operator checks on one coordinate set, folded into err by maximum
    subroutine check_set( t, err )
        real(real64), intent(in)    :: t(:,:)
        real(real64), intent(inout) :: err(13)
        real(real64),    allocatable :: g(:,:), gt(:,:), row(:), w(:), mu(:)
        complex(real64), allocatable :: z(:,:,:), y(:), d(:), p(:,:,:), ps(:,:,:), a(:), b(:)
        real(real64)                 :: wn(27)
        integer                      :: hn(3, 27), s, n, ns, m, i1
        complex(real64)              :: lhs, rhs
        m  = MPAD
        ns = size(t, 2)
        allocate(g(ns, m**3), gt(m**3, ns), row(m**3), w(ns), mu(m/2+1), z(m, m, m), y(ns), d(ns), p(m/2+1, m, m), &
                 ps(m/2+1, m, m), a(ns), b(m**3))
        g  = oracle_proj_matrix(t, m)
        gt = transpose(g)
        ! the pattern and the entries: the gather's 27 weights, placed by their own indices, against the rows
        do s = 1, ns
            call stencil_27(t(:, s), hn, wn)
            row = 0._real64
            do n = 1, 27
                i1      = flat_index(1 + modulo(hn(:, n), m), m)
                row(i1) = row(i1) + wn(n)
            end do
            err(1) = max(err(1), real(count((g(s, :) > 0._real64) .neqv. (row > 0._real64)), real64))
            if( count(g(s, :) > 0._real64) /= 27 ) err(1) = max(err(1), 1._real64)
            err(2) = max(err(2), oracle_finite_or_inf(nan_maxval(abs(g(s, :) - row))))
        end do
        ! the gather against the matrix on a complex field, and on a constant
        z      = field_sequence(m)
        err(3) = max(err(3), elem_error(oracle_proj_gather(t, z), matmul(g, oracle_flat(z)), matmul(g, abs(oracle_flat(z)))))
        z      = CONSTANT
        err(4) = max(err(4), elem_error(oracle_proj_gather(t, z), [(CONSTANT, s=1, ns)], abs(CONSTANT) * sum(g, 2)), &
                     elem_error(matmul(g, oracle_flat(z)), [(CONSTANT, s=1, ns)], abs(CONSTANT) * sum(g, 2)))
        ! the scatter, the numerator and the density against the matrix's transpose
        y      = sample_sequence(ns)
        d      = factor_sequence(ns)
        w      = weight_sequence(ns)
        err(5) = max(err(5), elem_error(oracle_flat(oracle_proj_scatter(t, y, m)), matmul(gt, y), matmul(gt, abs(y))))
        err(6) = max(err(6), elem_error(oracle_flat(oracle_proj_numerator(t, y, d, w, m)), matmul(gt, w * conjg(d) * y), &
                                        matmul(gt, abs(w * d * y))))
        err(7) = max(err(7), elem_error(oracle_flat(cmplx(oracle_proj_density(t, d, w, m), 0._real64, real64)), &
                                        cmplx(matmul(gt, w * abs(d)**2), 0._real64, real64), matmul(gt, w * abs(d)**2)))
        ! the totals: each row of G sums to one, so the grids sum to the samples' sums
        err(8) = max(err(8), oracle_finite_or_inf(abs(sum(oracle_proj_numerator(t, y, d, w, m)) - sum(w * conjg(d) * y)) / &
                                           sum(abs(w * d * y))), &
                     oracle_finite_or_inf(abs(sum(oracle_proj_density(t, d, w, m)) - sum(w * abs(d)**2)) / sum(w * abs(d)**2)))
        ! the adjoint identity <G z, y> = <z, G^T y> by the gather and the scatter; with the factor D, A = D G, its
        ! adjoint is the numerator at unit weights
        z      = field_sequence(m)
        a      = oracle_proj_gather(t, z)
        b      = oracle_flat(oracle_proj_scatter(t, y, m))
        err(9) = max(err(9), adjoint_error(sum(conjg(a) * y), sum(conjg(oracle_flat(z)) * b), &
                                           cnorm(a) * cnorm(y) + cnorm(oracle_flat(z)) * cnorm(b)))
        a       = d * oracle_proj_gather(t, z)
        b       = oracle_flat(oracle_proj_numerator(t, y, d, [(1._real64, s=1, ns)], m))
        err(10) = max(err(10), adjoint_error(sum(conjg(a) * y), sum(conjg(oracle_flat(z)) * b), &
                                             cnorm(a) * cnorm(y) + cnorm(oracle_flat(z)) * cnorm(b)))
        ! the packed gather against G applied to the expansion, the packed scatter against the fold of G^T y
        p       = packed_sequence(m, 1)
        err(11) = max(err(11), elem_error(oracle_proj_packed_gather(t, p), matmul(g, oracle_flat(oracle_proj_expand(p))), &
                                          matmul(g, abs(oracle_flat(oracle_proj_expand(p))))))
        ps      = oracle_proj_packed_scatter(t, y, m)
        z       = reshape(cmplx(matmul(gt, abs(y)), 0._real64, real64), [m, m, m])
        err(12) = max(err(12), elem_error(oracle_flat(ps), oracle_flat(oracle_proj_fold(reshape(matmul(gt, y), [m, m, m]))), &
                                          real(oracle_flat(oracle_proj_fold(z)))))
        ! the packed adjoint in the inner product induced by the expansion: Re<G E p, y> = <p, fold(G^T y) / mu>_mu
        mu  = oracle_proj_multiplicity(m)
        a   = oracle_proj_packed_gather(t, p)
        lhs = cmplx(real(sum(conjg(a) * y)), 0._real64, real64)
        rhs = CZERO
        do i1 = 1, m / 2 + 1
            rhs = rhs + mu(i1) * cmplx(real(sum(conjg(p(i1, :, :)) * ps(i1, :, :) / mu(i1))), 0._real64, real64)
        end do
        err(13) = max(err(13), adjoint_error(lhs, rhs, cnorm(a) * cnorm(y) + mu_norm(p, mu) * mu_norm(ps, 1._real64 / mu)))
    end subroutine check_set

    ! the route from a real cube at the coordinates t: a unit point at the centre, and one off it
    subroutine check_route( t, err )
        real(real64), intent(in)    :: t(:,:)
        real(real64), intent(inout) :: err(2)
        real(real64),    allocatable :: g(:,:)
        real(real64)                 :: v(NBOX, NBOX, NBOX)
        complex(real64)              :: f0(MPAD, MPAD, MPAD), ref(size(t, 2))
        integer                      :: i1, i2, i3, c, x0(3)
        ! a unit point at the centred origin gives every sample 1 / NBOX**3
        c          = 1 + NBOX / 2
        v          = 0._real64
        v(c, c, c) = 1._real64
        ref        = cmplx(1._real64 / real(NBOX, real64)**3, 0._real64, real64)
        err(1)     = max(err(1), oracle_rel_error(oracle_proj_route(v, t), ref))
        ! a unit point at centred x0 has the field exp(-2 pi i h . x0 / m) / m**3
        x0                           = [1, 2, -1]
        v                            = 0._real64
        v(c+x0(1), c+x0(2), c+x0(3)) = 1._real64
        do i3 = 1, MPAD
            do i2 = 1, MPAD
                do i1 = 1, MPAD
                    f0(i1, i2, i3) = exp(cmplx(0._real64, -TWOPI * real(dot_product([i1, i2, i3] - 1, x0), real64) / &
                                             real(MPAD, real64), real64)) / real(MPAD, real64)**3
                end do
            end do
        end do
        allocate(g(size(t, 2), MPAD**3))
        g      = oracle_proj_matrix(t, MPAD)
        err(2) = max(err(2), oracle_rel_error(oracle_proj_route(v, t), real(PADFAC**3, real64) * matmul(g, oracle_flat(f0))))
    end subroutine check_route

    ! the phantom's polar samples at angle a + NANG/2 are the conjugates of those at a
    subroutine check_friedel( err )
        real(real64), intent(inout) :: err
        complex(real64) :: yp(NANG, NSHELL, NROT)
        yp  = reshape(oracle_proj_route(oracle_proj_phantom(), oracle_proj_polar_coords()), [NANG, NSHELL, NROT])
        err = max(err, oracle_rel_error(oracle_flat(yp(NANG/2+1:,:,:)), oracle_flat(conjg(yp(1:NANG/2, :,:)))))
    end subroutine check_friedel

    ! packing and expansion of an exactly Hermitian field, compared by value; the multiplicities
    subroutine check_packing( err )
        real(real64), intent(inout) :: err(2)
        complex(real64), allocatable :: f(:,:,:), fh(:,:,:), p(:,:,:), a(:,:,:), b(:,:,:)
        real(real64),    allocatable :: mu(:)
        real(real64)                 :: lhs
        integer                      :: m, i1, i2, i3, nbad
        m = MPAD
        allocate(f(m, m, m), fh(m, m, m), p(m/2+1, m, m), a(m/2+1, m, m), b(m/2+1, m, m), mu(m/2+1))
        f = oracle_proj_padded_field(oracle_proj_phantom())
        ! (F(h) + conj(F(-h))) / 2 is Hermitian in value; signed zeros differ only in their bits
        do i3 = 1, m
            do i2 = 1, m
                do i1 = 1, m
                    fh(i1, i2, i3) = (f(i1, i2, i3) + conjg(f(mirror(i1, m), mirror(i2, m), mirror(i3, m)))) / 2._real64
                end do
            end do
        end do
        ! the expansion of its half returns it, and the packed gather of its half equals the gather of it, by value:
        ! a count of differences that are not zero, which a NaN cannot pass
        p    = oracle_proj_pack(fh)
        nbad = count(.not. (abs(oracle_proj_expand(p) - fh) <= 0._real64))
        nbad = nbad + count(.not. (abs(oracle_proj_packed_gather(oracle_proj_polar_coords(), p) - &
                                       oracle_proj_gather(oracle_proj_polar_coords(), fh)) <= 0._real64))
        nbad = nbad + count(.not. (abs(oracle_proj_packed_gather(oracle_proj_slice_coords(), p) - &
                                       oracle_proj_gather(oracle_proj_slice_coords(), fh)) <= 0._real64))
        nbad = nbad + count(.not. (abs(oracle_proj_packed_gather(oracle_proj_queries(), p) - &
                                       oracle_proj_gather(oracle_proj_queries(), fh)) <= 0._real64))
        err(1) = real(nbad, real64)
        ! the multiplicities: sum of mu Re(conj(a) b) over the packed half = Re<E a, E b> over the full grid
        mu  = oracle_proj_multiplicity(m)
        a   = packed_sequence(m, 2)
        b   = packed_sequence(m, 3)
        lhs = 0._real64
        do i1 = 1, m / 2 + 1
            lhs = lhs + mu(i1) * real(sum(conjg(a(i1, :, :)) * b(i1, :, :)))
        end do
        err(2) = max(err(2), adjoint_error(cmplx(lhs, 0._real64, real64), &
                                           cmplx(real(sum(conjg(oracle_proj_expand(a)) * oracle_proj_expand(b))), &
                                                 0._real64, real64), &
                                           cnorm(oracle_flat(oracle_proj_expand(a))) * cnorm(oracle_flat(oracle_proj_expand(b)))))
    end subroutine check_packing

    ! duplicate periodic destinations within a row, which only grids of side 2 and 3 reach: the matrix collects
    ! every image of a voxel, the gather's weights are added at their indices
    subroutine check_duplicates( t, err )
        real(real64), intent(in)    :: t(:,:)
        real(real64), intent(inout) :: err
        real(real64), allocatable :: g(:,:), row(:)
        real(real64)              :: wn(27)
        integer                   :: hn(3, 27), m, s, n, c
        do m = 2, 3
            allocate(g(size(t, 2), m**3), row(m**3))
            g = oracle_proj_matrix(t, m)
            do s = 1, size(t, 2)
                call stencil_27(t(:, s), hn, wn)
                row = 0._real64
                do n = 1, 27
                    c      = flat_index(1 + modulo(hn(:, n), m), m)
                    row(c) = row(c) + wn(n)
                end do
                err = max(err, oracle_finite_or_inf(nan_maxval(abs(g(s, :) - row))))
                if( .not. (all(ieee_is_finite(g(s, :))) .and. all(ieee_is_finite(row))) )then
                    err = ieee_value(err, ieee_positive_inf)
                endif
            end do
            deallocate(g, row)
        end do
    end subroutine check_duplicates

    ! the window from outside its constant: the weights at an integer coordinate against the values read
    ! elsewhere, and at eighths of a voxel against the closed form with I0 by the trapezoid rule at the typed beta
    subroutine check_window( err )
        real(real64), intent(inout) :: err(2)
        real(real64) :: w(3), wref(3), t
        integer      :: h(3), j, a, b
        call oracle_proj_stencil(0._real64, h, w)
        err(1) = max(err(1), oracle_finite_or_inf(nan_maxval(abs(w - [W1_READ, W0_READ, W1_READ]))))
        if( .not. all(ieee_is_finite(w)) ) err(1) = ieee_value(err(1), ieee_positive_inf)
        do j = -12, 12
            t = real(j, real64) / 8._real64
            call oracle_proj_stencil(t, h, w)
            ! the base in integers, half away from zero, and the half-width typed as 3/2
            b = sign((abs(j) + 4) / 8, j)
            do a = 1, 3
                wref(a) = i0_trapezoid(BETA_TYPED * sqrt(max(0._real64, 1._real64 - ((t - real(b + a - 2, real64)) / &
                                                                                    1.5_real64)**2)))
            end do
            err(2) = max(err(2), oracle_finite_or_inf(nan_maxval(abs(w - wref / sum(wref)))))
            if( .not. all(ieee_is_finite(w)) ) err(2) = ieee_value(err(2), ieee_positive_inf)
            if( any(h /= b + [-1, 0, 1]) ) err(2) = max(err(2), 1._real64)
        end do
    end subroutine check_window

    ! the packed half of the phantom's own padded transform, Hermitian because the phantom is real: its expansion
    ! against the transform, and its packed gather against the gather of the full field
    subroutine check_phantom_half( err )
        real(real64), intent(inout) :: err
        complex(real64), allocatable :: f(:,:,:), p(:,:,:)
        allocate(f(MPAD, MPAD, MPAD), p(MPAD/2+1, MPAD, MPAD))
        f   = oracle_proj_padded_field(oracle_proj_phantom())
        p   = oracle_proj_pack(f)
        err = max(err, oracle_rel_error(oracle_flat(oracle_proj_expand(p)), oracle_flat(f)), &
                  oracle_rel_error(oracle_proj_packed_gather(oracle_proj_polar_coords(), p), &
                                   oracle_proj_gather(oracle_proj_polar_coords(), f)), &
                  oracle_rel_error(oracle_proj_packed_gather(oracle_proj_slice_coords(), p), &
                                   oracle_proj_gather(oracle_proj_slice_coords(), f)), &
                  oracle_rel_error(oracle_proj_packed_gather(oracle_proj_queries(), p), &
                                   oracle_proj_gather(oracle_proj_queries(), f)))
    end subroutine check_phantom_half

    ! the edge index against its table on three grids; then the samples the two maps read differently: none of
    ! the polar set or the slice, queries 3 and 4, and on a scan of first coordinates in eighths exactly those
    ! with |t| >= m/2 - 1/2 reach a tap whose voxel differs
    subroutine check_edge_index( err )
        real(real64), intent(inout) :: err(2)
        real(real64) :: t
        integer      :: m, h, j, nbad, hs(3)
        real(real64) :: ws(3)
        nbad = 0
        do m = 8, 16, 4
            if( oracle_proj_edge_index(-m / 2 - 2, m) /= m / 2 - 1 ) nbad = nbad + 1
            if( oracle_proj_edge_index(-m / 2 - 1, m) /= m / 2 ) nbad = nbad + 1
            if( oracle_proj_edge_index(m / 2 + 1, m) /= -m / 2 ) nbad = nbad + 1
            if( oracle_proj_edge_index(m / 2 + 2, m) /= -m / 2 + 1 ) nbad = nbad + 1
            do h = -m / 2, m / 2
                if( oracle_proj_edge_index(h, m) /= h ) nbad = nbad + 1
            end do
        end do
        err(1) = err(1) + real(nbad, real64)
        nbad = count(reads_differ(oracle_proj_polar_coords())) + count(reads_differ(oracle_proj_slice_coords())) + &
               count(reads_differ(oracle_proj_queries()) .neqv. [.false., .false., .true., .true.])
        do j = -8 * (MPAD / 2 + 1), 8 * (MPAD / 2 + 1)
            t = real(j, real64) / 8._real64
            call oracle_proj_stencil(t, hs, ws)
            if( any(modulo(oracle_proj_edge_index(hs, MPAD) - hs, MPAD) /= 0) .neqv. &
                (abs(t) >= real(MPAD / 2, real64) - 0.5_real64) ) nbad = nbad + 1
        end do
        err(2) = err(2) + real(nbad, real64)
    end subroutine check_edge_index

    ! the edge gather against a sum over the voxels of the half and of its mates, each axis weighted by voxel
    ! index: the periodic images on dimensions 2 and 3, the cycle of length m + 1 on dimension 1
    subroutine check_edge_gather( t, err )
        real(real64), intent(in)    :: t(:,:)
        real(real64), intent(inout) :: err
        complex(real64), allocatable :: p(:,:,:), y(:), ref(:)
        real(real64),    allocatable :: scale(:)
        real(real64)                 :: we(-MPAD/2:MPAD/2), w2(MPAD), w3(MPAD)
        complex(real64)              :: v
        integer                      :: m, s, a1, i2, i3
        m = MPAD
        allocate(p(m/2+1, m, m), y(size(t, 2)), ref(size(t, 2)), scale(size(t, 2)))
        p = packed_sequence(m, 1)
        y = oracle_proj_edge_gather(t, p)
        do s = 1, size(t, 2)
            we       = edge_weights(t(1, s), m)
            w2       = axis_weights(t(2, s), m)
            w3       = axis_weights(t(3, s), m)
            ref(s)   = CZERO
            scale(s) = 0._real64
            do i3 = 1, m
                do i2 = 1, m
                    do a1 = -m / 2, m / 2
                        if( a1 >= 0 )then
                            v = p(1+a1, i2, i3)
                        else
                            v = conjg(p(1-a1, mirror(i2, m), mirror(i3, m)))
                        endif
                        ref(s)   = ref(s) + we(a1) * w2(i2) * w3(i3) * v
                        scale(s) = scale(s) + we(a1) * w2(i2) * w3(i3) * abs(v)
                    end do
                end do
            end do
        end do
        err = max(err, elem_error(y, ref, scale))
    end subroutine check_edge_gather

    ! per sample, whether some tap is read at another address or with another conjugation by the edge index
    ! than by the periodic one; the addresses of dimensions 2 and 3 follow the conjugation
    pure function reads_differ( t ) result(d)
        real(real64), intent(in) :: t(:,:)
        logical      :: d(size(t, 2))
        real(real64) :: w(3)
        integer      :: h(3), s, j, c, i
        do s = 1, size(t, 2)
            call oracle_proj_stencil(t(1, s), h, w)
            d(s) = .false.
            do j = 1, 3
                c = oracle_proj_edge_index(h(j), MPAD)
                i = modulo(h(j), MPAD)
                if( i <= MPAD / 2 )then
                    if( c /= i ) d(s) = .true.
                else
                    if( c /= -modulo(-h(j), MPAD) ) d(s) = .true.
                endif
            end do
        end do
    end function reads_differ

    ! the first dimension's weight on each index -m/2 .. m/2 under the cycle of length m + 1: index a collects the
    ! taps h = a + j (m + 1) with |h - nint(t)| <= 1, weighted by the window at t - h; normalised over the indices
    pure function edge_weights( t, m ) result(we)
        real(real64), intent(in) :: t
        integer,      intent(in) :: m
        real(real64) :: we(-m/2:m/2)
        integer      :: a, j, h
        do a = -m / 2, m / 2
            we(a) = 0._real64
            do j = -1, 1
                h = a + j * (m + 1)
                if( abs(h - nint(t)) <= 1 ) we(a) = we(a) + kb_window(t - real(h, real64))
            end do
        end do
        we = we / sum(we)
    end function edge_weights

    ! the rotation about z with cosine c and sine s, R(i,j) by rows [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    pure function rot_z( c, s ) result(r)
        real(real64), intent(in) :: c, s
        real(real64) :: r(3, 3)
        r = reshape([c, -s, 0._real64, s, c, 0._real64, 0._real64, 0._real64, 1._real64], [3, 3], order=[2, 1])
    end function rot_z

    ! the rotation about y with cosine c and sine s, R(i,j) by rows [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    pure function rot_y( c, s ) result(r)
        real(real64), intent(in) :: c, s
        real(real64) :: r(3, 3)
        r = reshape([c, 0._real64, s, 0._real64, 1._real64, 0._real64, -s, 0._real64, c], [3, 3], order=[2, 1])
    end function rot_y

    ! the stencil bases of a coordinate triple, the middle frequency of each axis's stencil
    pure function base_of( t ) result(b)
        real(real64), intent(in) :: t(3)
        integer      :: b(3), h(3), a
        real(real64) :: w(3)
        do a = 1, 3
            call oracle_proj_stencil(t(a), h, w)
            b(a) = h(2)
        end do
    end function base_of

    ! the determinant of a 3 x 3 matrix
    pure function det3( r ) result(d)
        real(real64), intent(in) :: r(3, 3)
        real(real64) :: d
        d = r(1, 1) * (r(2, 2) * r(3, 3) - r(2, 3) * r(3, 2)) - r(1, 2) * (r(2, 1) * r(3, 3) - r(2, 3) * r(3, 1)) + &
            r(1, 3) * (r(2, 1) * r(3, 2) - r(2, 2) * r(3, 1))
    end function det3

    ! the column of grid index (i1, i2, i3) of an m-grid in Fortran order
    pure function flat_index( i, m ) result(c)
        integer, intent(in) :: i(3), m
        integer :: c
        c = i(1) + m * (i(2) - 1) + m * m * (i(3) - 1)
    end function flat_index

    ! the Euclidean norm of a complex vector
    pure function cnorm( a ) result(r)
        complex(real64), intent(in) :: a(:)
        real(real64) :: r
        r = sqrt(sum(abs(a)**2))
    end function cnorm

    ! the norm of a packed half in the inner product weighted per plane by c
    pure function mu_norm( p, c ) result(r)
        complex(real64), intent(in) :: p(:,:,:)
        real(real64),    intent(in) :: c(:)
        real(real64) :: r
        integer      :: i1
        r = 0._real64
        do i1 = 1, size(p, 1)
            r = r + c(i1) * sum(abs(p(i1, :, :))**2)
        end do
        r = sqrt(r)
    end function mu_norm

    ! a fixed complex field on the m-grid, from integers
    pure function field_sequence( m ) result(z)
        integer, intent(in) :: m
        complex(real64) :: z(m, m, m)
        integer         :: i1, i2, i3
        do i3 = 1, m
            do i2 = 1, m
                do i1 = 1, m
                    z(i1, i2, i3) = cmplx(modulo(7 * i1 + 3 * i2 + 5 * i3, 11) - 5, &
                                        modulo(2 * i1 + 9 * i2 + 4 * i3 + 1, 13) - 6, real64) / 4._real64
                end do
            end do
        end do
    end function field_sequence

    ! a fixed packed half of the m-grid, from integers and a seed
    pure function packed_sequence( m, seed ) result(p)
        integer, intent(in) :: m, seed
        complex(real64) :: p(m/2+1, m, m)
        integer         :: i1, i2, i3
        do i3 = 1, m
            do i2 = 1, m
                do i1 = 1, m / 2 + 1
                    p(i1, i2, i3) = cmplx(modulo(3 * i1 + 5 * i2 + 7 * i3 + seed, 11) - 5, &
                                        modulo(4 * i1 + i2 + 6 * i3 + 2 * seed, 13) - 6, real64) / 4._real64
                end do
            end do
        end do
    end function packed_sequence

    ! fixed complex samples, from integers
    pure function sample_sequence( n ) result(y)
        integer, intent(in) :: n
        complex(real64) :: y(n)
        integer         :: s
        do s = 1, n
            y(s) = cmplx(modulo(5 * s + 2, 9) - 4, modulo(3 * s + 1, 7) - 3, real64) / 4._real64
        end do
    end function sample_sequence

    ! a fixed complex diagonal factor, phases in sevenths of a turn and magnitudes 1 to 1.75
    pure function factor_sequence( n ) result(d)
        integer, intent(in) :: n
        complex(real64) :: d(n)
        integer         :: s
        do s = 1, n
            d(s) = (1._real64 + 0.25_real64 * real(modulo(s, 4), real64)) * &
                   exp(cmplx(0._real64, TWOPI * real(modulo(3 * s, 7), real64) / 7._real64, real64))
        end do
    end function factor_sequence

    ! fixed positive observation weights, 1 to 2
    pure function weight_sequence( n ) result(w)
        integer, intent(in) :: n
        real(real64) :: w(n)
        integer      :: s
        do s = 1, n
            w(s) = 1._real64 + 0.25_real64 * real(modulo(s, 5), real64)
        end do
    end function weight_sequence

    ! the largest |a - ref| over the scale of its terms, element by element; where the scale is zero the
    ! difference must be zero too; +Inf for a non-finite value or a nonzero difference without scale
    pure function elem_error( a, ref, scale ) result(e)
        complex(real64), intent(in) :: a(:), ref(:)
        real(real64),    intent(in) :: scale(:)
        real(real64) :: e
        integer      :: i
        e = 0._real64
        if( .not. (oracle_all_finite(a) .and. oracle_all_finite(ref)) )then
            e = ieee_value(e, ieee_positive_inf)
            return
        endif
        do i = 1, size(a)
            if( scale(i) > 0._real64 )then
                e = max(e, abs(a(i) - ref(i)) / scale(i))
            else if( abs(a(i) - ref(i)) > 0._real64 )then
                e = ieee_value(e, ieee_positive_inf)
            endif
        end do
        e = oracle_finite_or_inf(e)
    end function elem_error

    ! |lhs - rhs| over the scale of the two products
    pure function adjoint_error( lhs, rhs, scale ) result(e)
        complex(real64), intent(in) :: lhs, rhs
        real(real64),    intent(in) :: scale
        real(real64) :: e
        e = oracle_finite_or_inf(abs(lhs - rhs) / scale)
    end function adjoint_error

end module mlxf_oracle_projection
