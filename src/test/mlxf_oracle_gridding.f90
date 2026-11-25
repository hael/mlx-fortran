!@descr: host oracle of the gridding insertion on the native grid: accumulators, stored half, density correction, map
! A pixel (h, k) of a plane lies at loc = (h, k, 0) R, without a padding factor; it adds 4 omega W c to the numerator
! and omega W q to the density, on accumulators with a halo and no wrap. The stored half h = 0 .. n/2 keeps the
! n-grid's range and, on h = 0, stores the conjugate at the mate. The map is the real inverse transform about the
! centre voxel, divided per axis by w0 + 2 w1 cos(2 pi x / n). The module also holds the fixture the
! reconstruction oracles share: the phantom on an n-cube, its transform, and three planes with their data.
module mlxf_oracle_gridding
use, intrinsic :: iso_fortran_env, only: real64
use mlxf_oracle_dft,        only: oracle_dft_3d, oracle_idft_3d, oracle_flat, oracle_rel_error
use mlxf_oracle_projection, only: oracle_proj_phantom, oracle_proj_rotation, oracle_proj_stencil, oracle_proj_matrix, &
                                  oracle_proj_expand
implicit none

public :: oracle_grid_plane, oracle_grid_lattice, oracle_grid_volume, oracle_grid_transform, oracle_grid_envelope, &
          oracle_grid_reciprocal, oracle_grid_half_inverse, oracle_grid_correct, oracle_grid_map, oracle_grid_selfcheck
private

real(real64),    parameter :: TWOPI = 2._real64 * acos(-1._real64)
complex(real64), parameter :: CZERO = (0._real64, 0._real64)
! the insertion: the numerator's scale; the floors under which a pixel's data, a compressed voxel, a density and
! an envelope count as nothing
real(real64),    parameter :: NUM_SCALE      = 4._real64
real(real64),    parameter :: DATA_FLOOR     = 1.e-10_real64
real(real64),    parameter :: COMPRESS_FLOOR = 1.e-10_real64
real(real64),    parameter :: RHO_FLOOR      = 1.e-6_real64
real(real64),    parameter :: ENVELOPE_FLOOR = 1.e-8_real64
! the accumulators' range: h from -HALO_LOW to n/2 + HALO, k and m from -(n/2 + HALO) to n/2 + HALO
integer,         parameter :: HALO_LOW = 3
integer,         parameter :: HALO     = 2
! the fixture's planes: the CTF 1 / (1 + (a h**2 + b h k + c k**2) / n**2) by its (a, b, c), the weight, the
! shift in pixels; the noise variance of plane i on shell s is 1 + (i + s) / 4
integer, parameter :: NPLANE = 3
real(real64),    parameter :: CTF_FORMS(3, NPLANE)    = reshape([1._real64, 1._real64, 2._real64, 3._real64, -1._real64, &
                                                               1._real64, 2._real64, 2._real64, 4._real64], [3, NPLANE])
real(real64), parameter :: PLANE_WEIGHTS(NPLANE)   = [1._real64, 0.75_real64, 1.25_real64]
real(real64),    parameter :: PLANE_SHIFTS(2, NPLANE) = reshape([0.25_real64, -0.5_real64, -0.75_real64, 0.25_real64, &
                                                               0.5_real64, 0.375_real64], [2, NPLANE])
! the self-check: the two boxes; per box, the entries of a plane's given half that carry data, the stored voxels
! inside the shell; per box and plane, the accumulator voxels its pixels touch in the stored range, at h < 0
! and in the halo; the pixels the identity plane inserts at n = 4, h = -2 .. 2 by k = -2 .. 1
integer,         parameter :: N_SMALL = 4
integer,         parameter :: N_LARGE = 8
integer,         parameter :: BAND(2)                = [13, 35]
integer,         parameter :: IN_SHELL(2)            = [39, 211]
integer,         parameter :: TOUCH_STORED(NPLANE, 2) = reshape([36, 36, 39, 120, 120, 144], [NPLANE, 2])
integer,         parameter :: TOUCH_BELOW(NPLANE, 2)  = reshape([36, 42, 56, 60, 66, 121], [NPLANE, 2])
integer,         parameter :: TOUCH_HALO(NPLANE, 2)   = reshape([33, 27, 53, 39, 33, 75], [NPLANE, 2])
logical,         parameter :: INSERTED_4(-2:2, -2:1) = reshape([.false., .true., .true., .true., .false., .false., &
                                                              .true., .true., .true., .true., .false., .true., .true., &
                                                              .true., .true., .false., .true., .true., .true., .true.], &
                                                             [5, 4])
! the boxes of the disc's check and the voxels an identity plane with data on every entry touches there
integer,         parameter :: DISC_BOX(2)     = [8, 16]
integer,         parameter :: DISC_TOUCHED(2) = [228, 570]
complex(real64), parameter :: CONSTANT  = (0.75_real64, -1.25_real64)
real(real64),    parameter :: TOL_MATRIX = 1.e-12_real64
integer,         parameter :: NCHECK    = 13
integer,         parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'fixture counts', 'fixture transform', 'fixture planes', 'identity plane', 'voxel counts', 'deposits vs matrix', &
    'unit data', 'stored half', 'h0 conjugate rule', 'pixel rules', 'density correction', 'on-grid map', 'guards']
real(real64),    parameter :: CHECK_LIMITS(NCHECK) = [0._real64, TOL_MATRIX, TOL_MATRIX, TOL_MATRIX, 0._real64, &
    TOL_MATRIX, TOL_MATRIX, TOL_MATRIX, 0._real64, 0._real64, TOL_MATRIX, TOL_MATRIX, 0._real64]

! one plane: its box, rotation, weight and shift, and on h, k = -n/2 .. n/2 its transform y, CTF t and noise
! variance s2
type :: oracle_grid_plane
    private
    integer                      :: n = 0
    real(real64)                 :: rot(3, 3) = 0._real64, omega = 0._real64, sh(2) = 0._real64
    complex(real64), allocatable :: y(:,:)
    real(real64),    allocatable :: t(:,:), s2(:,:)
    logical                      :: exists = .false.
  contains
    procedure :: new => plane_new
    procedure :: kill => plane_kill
    procedure :: set_data => plane_set_data
    procedure :: set_pose => plane_set_pose
    procedure :: box => plane_box
    procedure :: rotation => plane_rotation
    procedure :: weight => plane_weight
    procedure :: shift => plane_shift
    procedure :: observed => plane_observed
    procedure :: ctf => plane_ctf
    procedure :: variance => plane_variance
    procedure :: samples => plane_samples
end type oracle_grid_plane

! the accumulators of the insertion on the native grid, addressed by their signed indices
type :: oracle_grid_lattice
    private
    integer                      :: n = 0
    complex(real64), allocatable :: acc(:,:,:)
    real(real64),    allocatable :: dens(:,:,:)
    logical                      :: exists = .false.
  contains
    procedure :: new => lattice_new
    procedure :: kill => lattice_kill
    procedure :: insert => lattice_insert
    procedure :: numerator => lattice_numerator
    procedure :: density => lattice_density
    procedure :: compress => lattice_compress
end type oracle_grid_lattice

contains

    ! plane iplane = 1, 2 or 3 of the fixture in a box of n: y = t exp(+i phi) Fv((h, k, 0) R) / n**3, with Fv the
    ! phantom's transform and phi = 2 pi (h s1 + k s2) / n, so that t exp(-i phi) y is t**2 Fv / n**3
    subroutine plane_new( self, iplane, n )
        class(oracle_grid_plane), intent(inout) :: self
        integer,                  intent(in)    :: iplane, n
        real(real64),    allocatable :: loc(:,:)
        complex(real64), allocatable :: f(:)
        real(real64)                 :: phi
        integer                      :: ip, h, k, s
        call self%kill()
        ip         = min(max(iplane, 1), NPLANE)
        self%n     = n
        self%rot   = oracle_proj_rotation(ip)
        self%omega = PLANE_WEIGHTS(ip)
        self%sh    = PLANE_SHIFTS(:, ip)
        allocate(self%y(-n/2:n/2, -n/2:n/2), self%t(-n/2:n/2, -n/2:n/2), self%s2(-n/2:n/2, -n/2:n/2), &
                 loc(3, (n+1)**2), f((n+1)**2))
        s = 0
        do k = -n / 2, n / 2
            do h = -n / 2, n / 2
                s             = s + 1
                loc(:, s)     = matmul(real([h, k, 0], real64), self%rot)
                self%t(h, k)  = 1._real64 / (1._real64 + (CTF_FORMS(1, ip) * real(h * h, real64) + CTF_FORMS(2, ip) * &
                                                         real(h * k, real64) + CTF_FORMS(3, ip) * real(k * k, real64)) / &
                                             real(n * n, real64))
                self%s2(h, k) = 1._real64 + real(ip + nint(sqrt(real(h * h + k * k, real64))), real64) / 4._real64
            end do
        end do
        f = oracle_grid_transform(oracle_grid_volume(n), loc)
        s = 0
        do k = -n / 2, n / 2
            do h = -n / 2, n / 2
                s            = s + 1
                phi          = TWOPI * (real(h, real64) * self%sh(1) + real(k, real64) * self%sh(2)) / real(n, real64)
                self%y(h, k) = self%t(h, k) * exp(cmplx(0._real64, phi, real64)) * f(s) / real(n, real64)**3
            end do
        end do
        self%exists = .true.
    end subroutine plane_new

    ! release the plane; idempotent
    subroutine plane_kill( self )
        class(oracle_grid_plane), intent(inout) :: self
        if( .not. self%exists ) return
        if( allocated(self%y) ) deallocate(self%y)
        if( allocated(self%t) ) deallocate(self%t)
        if( allocated(self%s2) ) deallocate(self%s2)
        self%n      = 0
        self%exists = .false.
    end subroutine plane_kill

    ! replace the transform, the CTF and the variance, each (n + 1, n + 1) with (h, k) at (h + n/2 + 1, k + n/2 + 1)
    subroutine plane_set_data( self, y, t, s2 )
        class(oracle_grid_plane), intent(inout) :: self
        complex(real64),          intent(in)    :: y(:,:)
        real(real64),             intent(in)    :: t(:,:), s2(:,:)
        self%y(:,:)  = y
        self%t(:,:)  = t
        self%s2(:,:) = s2
    end subroutine plane_set_data

    ! replace the rotation, the weight and the shift
    subroutine plane_set_pose( self, r, omega, shift )
        class(oracle_grid_plane), intent(inout) :: self
        real(real64),             intent(in)    :: r(3, 3), omega, shift(2)
        self%rot   = r
        self%omega = omega
        self%sh    = shift
    end subroutine plane_set_pose

    ! the box n
    pure function plane_box( self ) result(n)
        class(oracle_grid_plane), intent(in) :: self
        integer :: n
        n = self%n
    end function plane_box

    ! the rotation R(i,j)
    pure function plane_rotation( self ) result(r)
        class(oracle_grid_plane), intent(in) :: self
        real(real64) :: r(3, 3)
        r = self%rot
    end function plane_rotation

    ! the plane's weight omega
    pure function plane_weight( self ) result(omega)
        class(oracle_grid_plane), intent(in) :: self
        real(real64) :: omega
        omega = self%omega
    end function plane_weight

    ! the plane's shift (s1, s2) in pixels
    pure function plane_shift( self ) result(s)
        class(oracle_grid_plane), intent(in) :: self
        real(real64) :: s(2)
        s = self%sh
    end function plane_shift

    ! the plane's transform y, (h, k) at (h + n/2 + 1, k + n/2 + 1)
    pure function plane_observed( self ) result(y)
        class(oracle_grid_plane), intent(in) :: self
        complex(real64) :: y(self%n+1, self%n+1)
        y = self%y
    end function plane_observed

    ! the CTF t, indexed as the transform
    pure function plane_ctf( self ) result(t)
        class(oracle_grid_plane), intent(in) :: self
        real(real64) :: t(self%n+1, self%n+1)
        t = self%t
    end function plane_ctf

    ! the noise variance, indexed as the transform
    pure function plane_variance( self ) result(s2)
        class(oracle_grid_plane), intent(in) :: self
        real(real64) :: s2(self%n+1, self%n+1)
        s2 = self%s2
    end function plane_variance

    ! the inputs of the gridding insertion on the half k <= 0, (h, k) at (h + n/2 + 1, k + n/2 + 1):
    ! c = t exp(-i phi) y / s2 and q = t**2 / s2, both zero where nint(sqrt((2h)**2 + (2k)**2)) > n
    subroutine plane_samples( self, c, q )
        class(oracle_grid_plane), intent(in)  :: self
        complex(real64),          intent(out) :: c(:,:)
        real(real64),             intent(out) :: q(:,:)
        real(real64) :: phi
        integer      :: n, h, k
        n = self%n
        c = CZERO
        q = 0._real64
        do k = -n / 2, 0
            do h = -n / 2, n / 2
                if( nint(sqrt(real(4 * h * h + 4 * k * k, real64))) > n ) cycle
                phi                = TWOPI * (real(h, real64) * self%sh(1) + real(k, real64) * self%sh(2)) / real(n, real64)
                c(h+n/2+1, k+n/2+1) = self%t(h, k) * exp(cmplx(0._real64, -phi, real64)) * self%y(h, k) / self%s2(h, k)
                q(h+n/2+1, k+n/2+1) = self%t(h, k)**2 / self%s2(h, k)
            end do
        end do
    end subroutine plane_samples

    ! empty accumulators for a box of n
    subroutine lattice_new( self, n )
        class(oracle_grid_lattice), intent(inout) :: self
        integer,                    intent(in)    :: n
        call self%kill()
        self%n = n
        allocate(self%acc(-HALO_LOW:n/2+HALO, -(n/2+HALO):n/2+HALO, -(n/2+HALO):n/2+HALO), &
                 self%dens(-HALO_LOW:n/2+HALO, -(n/2+HALO):n/2+HALO, -(n/2+HALO):n/2+HALO))
        self%acc    = CZERO
        self%dens   = 0._real64
        self%exists = .true.
    end subroutine lattice_new

    ! release the accumulators; idempotent
    subroutine lattice_kill( self )
        class(oracle_grid_lattice), intent(inout) :: self
        if( .not. self%exists ) return
        if( allocated(self%acc) ) deallocate(self%acc)
        if( allocated(self%dens) ) deallocate(self%dens)
        self%n      = 0
        self%exists = .false.
    end subroutine lattice_kill

    ! insert one plane from its samples c and q on the half k <= 0, indexed as plane_samples writes them: pixels
    ! h = -n/2 .. n/2, k = -n/2 .. n/2 - 1 inside h**2 + k**2 <= nyq (nyq + 1), a pixel with k > 0 taking the
    ! conjugate of its mate; skipped when its data are nothing, and when its three h taps are all negative
    subroutine lattice_insert( self, c, q, r, omega )
        class(oracle_grid_lattice), intent(inout) :: self
        complex(real64),            intent(in)    :: c(:,:)
        real(real64),               intent(in)    :: q(:,:), r(3, 3), omega
        complex(real64) :: cs
        real(real64)    :: qs, loc(3), w(3, 3), ww
        integer         :: tap(3, 3), nyq, h, k, a, j1, j2, j3
        nyq = self%n / 2
        do k = -nyq, nyq - 1
            do h = -nyq, nyq
                if( h * h + k * k > nyq * (nyq + 1) ) cycle
                if( k <= 0 )then
                    cs = c(h+nyq+1, k+nyq+1)
                    qs = q(h+nyq+1, k+nyq+1)
                else
                    cs = conjg(c(nyq+1-h, nyq+1-k))
                    qs = q(nyq+1-h, nyq+1-k)
                endif
                if( abs(real(cs)) + abs(aimag(cs)) <= DATA_FLOOR .and. qs <= DATA_FLOOR ) cycle
                loc = matmul(real([h, k, 0], real64), r)
                do a = 1, 3
                    call oracle_proj_stencil(loc(a), tap(:, a), w(:, a))
                end do
                if( all(tap(:, 1) < 0) ) cycle
                do j3 = 1, 3
                    do j2 = 1, 3
                        do j1 = 1, 3
                            ww = w(j1, 1) * w(j2, 2) * w(j3, 3)
                            self%acc(tap(j1, 1), tap(j2, 2), tap(j3, 3)) = self%acc(tap(j1, 1), tap(j2, 2), tap(j3, 3)) + &
                                                                         ww * NUM_SCALE * omega * cs
                            self%dens(tap(j1, 1), tap(j2, 2), tap(j3, 3)) = self%dens(tap(j1, 1), tap(j2, 2), tap(j3, 3)) + &
                                                                          ww * omega * qs
                        end do
                    end do
                end do
            end do
        end do
    end subroutine lattice_insert

    ! the numerator's accumulator, index (h, k, m) at (h + 4, k + n/2 + 3, m + n/2 + 3)
    pure function lattice_numerator( self ) result(acc)
        class(oracle_grid_lattice), intent(in) :: self
        complex(real64) :: acc(self%n/2+HALO_LOW+HALO+1, self%n+2*HALO+1, self%n+2*HALO+1)
        acc = self%acc
    end function lattice_numerator

    ! the density's accumulator, indexed as the numerator's
    pure function lattice_density( self ) result(dens)
        class(oracle_grid_lattice), intent(in) :: self
        real(real64) :: dens(self%n/2+HALO_LOW+HALO+1, self%n+2*HALO+1, self%n+2*HALO+1)
        dens = self%dens
    end function lattice_density

    ! the stored half (n/2 + 1, n, n), index (h, k, m) at (1 + h, 1 + modulo(k, n), 1 + modulo(m, n)): only
    ! h = 0 .. n/2 and k, m = -n/2 .. n/2 - 1 are read; h > 0 is taken as it is, h = 0 is stored conjugated at
    ! (0, -k, -m), the mate index taken modulo n; a voxel with nothing in both accumulators stays zero
    subroutine lattice_compress( self, s, rho )
        class(oracle_grid_lattice), intent(in)  :: self
        complex(real64),            intent(out) :: s(:,:,:)
        real(real64),               intent(out) :: rho(:,:,:)
        integer :: n, h, k, m
        n   = self%n
        s   = CZERO
        rho = 0._real64
        do m = -n / 2, n / 2 - 1
            do k = -n / 2, n / 2 - 1
                do h = 0, n / 2
                    if( abs(self%acc(h, k, m)) < COMPRESS_FLOOR .and. self%dens(h, k, m) <= COMPRESS_FLOOR ) cycle
                    if( h > 0 )then
                        s(1+h, 1+modulo(k, n), 1+modulo(m, n))   = self%acc(h, k, m)
                        rho(1+h, 1+modulo(k, n), 1+modulo(m, n)) = self%dens(h, k, m)
                    else
                        s(1, 1+modulo(-k, n), 1+modulo(-m, n))   = conjg(self%acc(h, k, m))
                        rho(1, 1+modulo(-k, n), 1+modulo(-m, n)) = self%dens(h, k, m)
                    endif
                end do
            end do
        end do
    end subroutine lattice_compress

    ! the projection oracle's phantom on the n-cube: the voxel at centred x = i - 1 - n/2 where the phantom has
    ! one, zero elsewhere
    pure function oracle_grid_volume( n ) result(v)
        integer, intent(in) :: n
        real(real64)              :: v(n, n, n)
        real(real64), allocatable :: ph(:,:,:)
        integer                   :: np, i1, i2, i3, j(3)
        allocate(ph, source=oracle_proj_phantom())
        np = size(ph, 1)
        v  = 0._real64
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    j = [i1, i2, i3] - n / 2 + np / 2
                    if( all(j >= 1 .and. j <= np) ) v(i1, i2, i3) = ph(j(1), j(2), j(3))
                end do
            end do
        end do
    end function oracle_grid_volume

    ! the transform of a cube at any frequencies q(:, s) of its n-grid, by direct sums:
    ! sum over the voxels of v(x) exp(-2 pi i q.x / n), x the centred coordinate
    pure function oracle_grid_transform( v, q ) result(f)
        real(real64), intent(in) :: v(:,:,:), q(:,:)
        complex(real64) :: f(size(q, 2))
        real(real64)    :: x(3)
        integer         :: n, s, i1, i2, i3
        n = size(v, 1)
        do s = 1, size(q, 2)
            f(s) = CZERO
            do i3 = 1, n
                do i2 = 1, n
                    do i1 = 1, n
                        x    = real([i1, i2, i3] - 1 - n / 2, real64)
                        f(s) = f(s) + v(i1, i2, i3) * exp(cmplx(0._real64, -TWOPI * dot_product(q(:, s), x) / &
                                                                real(n, real64), real64))
                    end do
                end do
            end do
        end do
    end function oracle_grid_transform

    ! the transform of the three-point window along one axis at offset d of a grid of the given period:
    ! w0 + 2 w1 cos(2 pi d / period), w0 and w1 the window's weights at an integer coordinate
    elemental function oracle_grid_envelope( d, period ) result(e)
        integer, intent(in) :: d, period
        real(real64) :: e, w(3)
        integer      :: h(3)
        call oracle_proj_stencil(0._real64, h, w)
        e = w(2) + (w(1) + w(3)) * cos(TWOPI * real(modulo(d, period), real64) / real(period, real64))
    end function oracle_grid_envelope

    ! 1 / e, and zero where |e| is below the envelope's floor
    elemental function oracle_grid_reciprocal( e ) result(r)
        real(real64), intent(in) :: e
        real(real64) :: r
        r = 0._real64
        if( .not. (abs(e) < ENVELOPE_FLOOR) ) r = 1._real64 / e
    end function oracle_grid_reciprocal

    ! the unnormalised real inverse transform of a stored half about the centre voxel: h < 0 from the conjugate
    ! mates, the planes h = 0 and n/2 as stored, the real part kept; voxel i holds the centred x = i - 1 - n/2
    pure function oracle_grid_half_inverse( p ) result(x)
        complex(real64), intent(in) :: p(:,:,:)
        real(real64)    :: x(size(p, 2), size(p, 2), size(p, 2))
        complex(real64) :: g(size(p, 2), size(p, 2), size(p, 2))
        integer         :: n, i1, i2, i3, j(3)
        n = size(p, 2)
        g = oracle_idft_3d(oracle_proj_expand(p)) * real(n, real64)**3
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    j             = 1 + modulo([i1, i2, i3] - 1 - n / 2, n)
                    x(i1, i2, i3) = real(g(j(1), j(2), j(3)))
                end do
            end do
        end do
    end function oracle_grid_half_inverse

    ! the density correction of a stored half: zero where nint(|(h, k, m)|) > n/2; elsewhere s / rho where
    ! |rho| is above its floor, else zero
    pure function oracle_grid_correct( s, rho ) result(v)
        complex(real64), intent(in) :: s(:,:,:)
        real(real64),    intent(in) :: rho(:,:,:)
        complex(real64) :: v(size(s, 1), size(s, 2), size(s, 3))
        integer         :: n, i1, i2, i3, g(3)
        n = size(s, 2)
        v = CZERO
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n / 2 + 1
                    g = [i1 - 1, signed_index(i2, n), signed_index(i3, n)]
                    if( nint(sqrt(real(dot_product(g, g), real64))) > n / 2 ) cycle
                    if( abs(rho(i1, i2, i3)) > RHO_FLOOR ) v(i1, i2, i3) = s(i1, i2, i3) / rho(i1, i2, i3)
                end do
            end do
        end do
    end function oracle_grid_correct

    ! the map of a stored half: its real inverse transform about the centre voxel, then each axis multiplied by
    ! the reciprocal of the window's transform at the offset from that voxel
    pure function oracle_grid_map( v ) result(x)
        complex(real64), intent(in) :: v(:,:,:)
        real(real64) :: x(size(v, 2), size(v, 2), size(v, 2))
        real(real64) :: re(size(v, 2))
        integer      :: n, i, i1, i2, i3
        n  = size(v, 2)
        re = oracle_grid_reciprocal(oracle_grid_envelope([(i - 1 - n / 2, i=1, n)], n))
        x  = oracle_grid_half_inverse(v)
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    x(i1, i2, i3) = x(i1, i2, i3) * re(i1) * re(i2) * re(i3)
                end do
            end do
        end do
    end function oracle_grid_map

    ! the checks against closed forms, counts and the explicit matrix, as named largest errors and their limits;
    ! the deposit checks run in both boxes and take the largest
    subroutine oracle_grid_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        limits = CHECK_LIMITS
        errors = 0._real64
        call check_fixture(N_SMALL, 1, errors(1:3))
        call check_fixture(N_LARGE, 2, errors(1:3))
        call check_hand_pixels(errors(3))
        call check_identity(errors(4))
        call check_deposits(N_SMALL, 1, errors(5:9))
        call check_deposits(N_LARGE, 2, errors(5:9))
        call check_pixel_rules(errors(10))
        call check_disc(errors(10))
        call check_correction(N_SMALL, 1, errors(11))
        call check_correction(N_LARGE, 2, errors(11))
        call check_map(errors(12))
        call check_half_inverse(errors(12))
        call check_guards(errors(13))
    end subroutine oracle_grid_selfcheck

    ! the signed index -n/2 .. n/2 - 1 stored at position i of an n-grid
    pure function signed_index( i, n ) result(g)
        integer, intent(in) :: i, n
        integer :: g
        g = i - 1
        if( g >= n / 2 ) g = g - n
    end function signed_index

    ! the fixture in a box of n: the volume against the phantom's own voxels and the counts of the planes' data;
    ! the transform at the grid's frequencies against the DFT of the volume moved to the origin, and of a unit
    ! point against its phases; the planes' Friedel symmetry and the samples against t**2 Fv / (s2 n**3)
    subroutine check_fixture( n, ibox, err )
        integer,      intent(in)    :: n, ibox
        real(real64), intent(inout) :: err(3)
        type(oracle_grid_plane)      :: plane
        real(real64),    allocatable :: ph(:,:,:), v(:,:,:), q(:,:), loc(:,:), qs(:,:), t(:,:), s2(:,:)
        complex(real64), allocatable :: f(:,:,:), ref(:), y(:,:), c(:,:), fl(:)
        integer                      :: np, lo, nbad, i1, i2, i3, j(3), s, ip, h, k, x0(3)
        allocate(ph, source=oracle_proj_phantom())
        allocate(v(n, n, n), f(n, n, n), q(3, n**3), ref(n**3), y(n+1, n+1), c(n+1, n/2+1), qs(n+1, n/2+1), &
                 t(n+1, n+1), s2(n+1, n+1), loc(3, (n+1)*(n/2+1)), fl((n+1)*(n/2+1)))
        np = size(ph, 1)
        v  = oracle_grid_volume(n)
        ! the volume: the phantom's voxels at the same centred coordinates, zeros beyond them
        nbad = 0
        if( n <= np )then
            lo   = (np - n) / 2
            nbad = nbad + count(.not. (abs(v - ph(lo+1:lo+n, lo+1:lo+n, lo+1:lo+n)) <= 0._real64))
        else
            lo   = (n - np) / 2
            nbad = nbad + count(.not. (abs(v(lo+1:lo+np, lo+1:lo+np, lo+1:lo+np) - ph) <= 0._real64))
            if( count(abs(v) > 0._real64) /= np**3 ) nbad = nbad + 1
        endif
        ! the transform at the grid's own frequencies, against the DFT of the volume with its centre at the origin
        f = CZERO
        s = 0
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    j                   = 1 + modulo([i1, i2, i3] - 1 - n / 2, n)
                    f(j(1), j(2), j(3)) = cmplx(v(i1, i2, i3), 0._real64, real64)
                    s                   = s + 1
                    q(:, s)             = real([signed_index(i1, n), signed_index(i2, n), signed_index(i3, n)], real64)
                end do
            end do
        end do
        err(2) = max(err(2), oracle_rel_error(oracle_grid_transform(v, q), oracle_flat(oracle_dft_3d(f))))
        ! a unit point at centred x0 has the transform exp(-2 pi i q.x0 / n), at frequencies off the grid too
        x0                                       = [1, -2, 0]
        v                                        = 0._real64
        v(1+n/2+x0(1), 1+n/2+x0(2), 1+n/2+x0(3)) = 1._real64
        q                                        = 0.37_real64 * q + 0.125_real64
        do s = 1, n**3
            ref(s) = exp(cmplx(0._real64, -TWOPI * dot_product(q(:, s), real(x0, real64)) / real(n, real64), real64))
        end do
        err(2) = max(err(2), oracle_rel_error(oracle_grid_transform(v, q), ref))
        v      = oracle_grid_volume(n)
        do ip = 1, NPLANE
            call plane%new(ip, n)
            y  = plane%observed()
            t  = plane%ctf()
            s2 = plane%variance()
            call plane%samples(c, qs)
            ! the given half carries data on the band only; every pixel is the conjugate of its mate
            if( count(qs > 0._real64) /= BAND(ibox) ) nbad = nbad + 1
            if( count(abs(c) > 0._real64) > BAND(ibox) ) nbad = nbad + 1
            if( plane%box() /= n ) nbad = nbad + 1
            err(3) = max(err(3), oracle_rel_error(reshape(y(n+1:1:-1, n+1:1:-1), [(n+1)**2]), &
                                                  reshape(conjg(y), [(n+1)**2])))
            ! the samples: the shift's phase cancels, leaving t**2 Fv / (s2 n**3) and t**2 / s2 on the band
            s = 0
            do k = -n / 2, 0
                do h = -n / 2, n / 2
                    s         = s + 1
                    loc(:, s) = matmul(real([h, k, 0], real64), plane%rotation())
                end do
            end do
            fl = oracle_grid_transform(v, loc)
            s  = 0
            do k = 1, n / 2 + 1
                do h = 1, n + 1
                    s = s + 1
                    if( qs(h, k) > 0._real64 )then
                        fl(s) = t(h, k)**2 * fl(s) / (s2(h, k) * real(n, real64)**3)
                        if( abs(qs(h, k) - t(h, k)**2 / s2(h, k)) > TOL_MATRIX ) nbad = nbad + 1
                    else
                        fl(s) = CZERO
                    endif
                end do
            end do
            err(3) = max(err(3), oracle_rel_error(reshape(c, [size(c)]), fl))
            call plane%kill()
        end do
        err(1) = err(1) + real(nbad, real64)
    end subroutine check_fixture

    ! one pixel of each plane worked by hand, with its CTF, variance, phase and coordinate, the plane's weight and
    ! its shift typed as numbers: plane 1 at (2, -1) and plane 2 at (1, -2) in a box of 4, plane 3 at (2, -2)
    ! in a box of 8, where the shell nint(sqrt(8)) = 3 is not the truncated root
    subroutine check_hand_pixels( err )
        real(real64), intent(inout) :: err
        type(oracle_grid_plane)      :: plane
        complex(real64), allocatable :: y(:,:), c(:,:)
        real(real64),    allocatable :: q(:,:)
        complex(real64)              :: f(1), got(3), ref(3)
        real(real64)                 :: loc(3, 1), t(3), s2(3), phi(3), locs(3, 3), omega(3), shifts(2, 3)
        integer                      :: hk(2, 3), box(3), ip, n, i1, i2, j
        hk     = reshape([2, -1, 1, -2, 2, -2], [2, 3])
        box    = [4, 4, 8]
        t      = [0.8_real64, 0.64_real64, 0.8_real64]
        s2     = [1.75_real64, 2._real64, 2.5_real64]
        phi    = [TWOPI / 4._real64, -5._real64 * TWOPI / 16._real64, TWOPI / 32._real64]
        locs   = reshape([2._real64, -1._real64, 0._real64, -2._real64, -1._real64, 0._real64, -2._real64 / 13._real64, &
                          -14._real64 / 5._real64, -24._real64 / 65._real64], [3, 3])
        omega  = [1._real64, 0.75_real64, 1.25_real64]
        shifts = reshape([0.25_real64, -0.5_real64, -0.75_real64, 0.25_real64, 0.5_real64, 0.375_real64], [2, 3])
        do ip = 1, NPLANE
            n = box(ip)
            allocate(y(n+1, n+1), c(n+1, n/2+1), q(n+1, n/2+1))
            call plane%new(ip, n)
            y = plane%observed()
            call plane%samples(c, q)
            loc(:, 1) = locs(:, ip)
            f         = oracle_grid_transform(oracle_grid_volume(n), loc) / real(n, real64)**3
            i1        = hk(1, ip) + n / 2 + 1
            i2        = hk(2, ip) + n / 2 + 1
            got       = [y(i1, i2), c(i1, i2), cmplx(q(i1, i2), 0._real64, real64)]
            ref       = [t(ip) * exp(cmplx(0._real64, phi(ip), real64)) * f(1), t(ip)**2 * f(1) / s2(ip), &
                         cmplx(t(ip)**2 / s2(ip), 0._real64, real64)]
            do j = 1, 3
                err = max(err, oracle_rel_error(got(j:j), ref(j:j)))
            end do
            err = max(err, real_error([plane%weight(), plane%shift()], [omega(ip), shifts(:, ip)]))
            call plane%kill()
            deallocate(y, c, q)
        end do
    end subroutine check_hand_pixels

    ! the identity plane at n = 4, every deposit by its closed form: on integer coordinates each axis weighs
    ! (w1, w0, w1), so the numerator is 4 omega u(g3) times the sum over the inserted pixels of
    ! u(g1 - h) u(g2 - k) c, with the inserted pixels typed as a table
    subroutine check_identity( err )
        real(real64), intent(inout) :: err
        type(oracle_grid_plane)      :: plane
        type(oracle_grid_lattice)    :: lat
        complex(real64), allocatable :: c(:,:), num(:,:,:), ref(:,:,:), den(:,:,:)
        real(real64),    allocatable :: q(:,:)
        complex(real64)              :: cs
        real(real64)                 :: w(3), u(-1:1), qs
        integer                      :: tap(3), n, nyq, h, k, g1, g2, g3
        n   = N_SMALL
        nyq = n / 2
        allocate(c(n+1, nyq+1), q(n+1, nyq+1), num(nyq+HALO_LOW+HALO+1, n+2*HALO+1, n+2*HALO+1), &
                 ref(-HALO_LOW:nyq+HALO, -(nyq+HALO):nyq+HALO, -(nyq+HALO):nyq+HALO), &
                 den(-HALO_LOW:nyq+HALO, -(nyq+HALO):nyq+HALO, -(nyq+HALO):nyq+HALO))
        call oracle_proj_stencil(0._real64, tap, w)
        u = w
        call plane%new(1, n)
        call plane%samples(c, q)
        call lat%new(n)
        call lat%insert(c, q, plane%rotation(), plane%weight())
        ref = CZERO
        den = CZERO
        do k = -nyq, nyq - 1
            do h = -nyq, nyq
                if( .not. INSERTED_4(h, k) ) cycle
                if( k <= 0 )then
                    cs = c(h+nyq+1, k+nyq+1)
                    qs = q(h+nyq+1, k+nyq+1)
                else
                    cs = conjg(c(nyq+1-h, nyq+1-k))
                    qs = q(nyq+1-h, nyq+1-k)
                endif
                do g3 = -1, 1
                    do g2 = k - 1, k + 1
                        do g1 = h - 1, h + 1
                            ref(g1, g2, g3) = ref(g1, g2, g3) + 4._real64 * plane%weight() * u(g3) * u(g1-h) * u(g2-k) * cs
                            den(g1, g2, g3) = den(g1, g2, g3) + plane%weight() * u(g3) * u(g1-h) * u(g2-k) * qs
                        end do
                    end do
                end do
            end do
        end do
        num = lat%numerator()
        err = max(err, oracle_rel_error(oracle_flat(num), reshape(ref, [size(ref)])))
        num = cmplx(lat%density(), 0._real64, real64)
        err = max(err, oracle_rel_error(oracle_flat(num), reshape(den, [size(den)])))
        call lat%kill()
        call plane%kill()
    end subroutine check_identity

    ! the three planes in a box of n: the voxels each touches; each plane's accumulators, and their sum, against
    ! the explicit matrix; numerator = 4 density at unit data; the stored half against the reference
    ! accumulators read by destination; the conjugate rule of h = 0 voxel by voxel
    subroutine check_deposits( n, ibox, err )
        integer,      intent(in)    :: n, ibox
        real(real64), intent(inout) :: err(5)
        type(oracle_grid_plane)      :: plane
        type(oracle_grid_lattice)    :: lat, one, unit
        real(real64),    allocatable :: a(:,:), q(:,:), qone(:,:), dens(:,:,:), denref(:), rho(:,:,:), rhoref(:,:,:)
        complex(real64), allocatable :: c(:,:), cone(:,:), numref(:), num(:,:,:), s(:,:,:), sref(:,:,:), numone(:), &
                                        denone(:), cp(:)
        real(real64),    allocatable :: qp(:)
        complex(real64)              :: vs
        real(real64)                 :: omega, ds
        integer                      :: nyq, nvox, npix, ip, nbad, h, k, m, km(2), d(3)
        nyq  = n / 2
        nvox = (nyq + HALO_LOW + HALO + 1) * (n + 2 * HALO + 1)**2
        npix = (n + 1) * n
        d    = [nyq + HALO_LOW + HALO + 1, n + 2 * HALO + 1, n + 2 * HALO + 1]
        allocate(a(nvox, npix), c(n+1, nyq+1), q(n+1, nyq+1), cone(n+1, nyq+1), qone(n+1, nyq+1), numref(nvox), &
                 denref(nvox), num(d(1), d(2), d(3)), dens(d(1), d(2), d(3)), s(nyq+1, n, n), sref(nyq+1, n, n), &
                 rho(nyq+1, n, n), rhoref(nyq+1, n, n), numone(nvox), denone(nvox), cp(npix), qp(npix))
        numref = CZERO
        denref = 0._real64
        nbad   = 0
        call lat%new(n)
        do ip = 1, NPLANE
            call plane%new(ip, n)
            call plane%samples(c, q)
            omega = plane%weight()
            ! unit data on the band: the voxels touched, by region, and numerator = 4 density
            qone = merge(1._real64, 0._real64, q > 0._real64)
            cone = cmplx(qone, 0._real64, real64)
            call unit%new(n)
            call unit%insert(cone, qone, plane%rotation(), omega)
            dens = unit%density()
            if( count(dens(HALO_LOW+1:HALO_LOW+nyq+1, HALO+1:HALO+n, HALO+1:HALO+n) > 0._real64) /= TOUCH_STORED(ip, ibox) )then
                nbad = nbad + 1
            endif
            if( count(dens(1:HALO_LOW, :,:) > 0._real64) /= TOUCH_BELOW(ip, ibox) ) nbad = nbad + 1
            if( count(dens > 0._real64) /= TOUCH_STORED(ip, ibox) + TOUCH_BELOW(ip, ibox) + TOUCH_HALO(ip, ibox) )then
                nbad = nbad + 1
            endif
            num    = cmplx(4._real64 * dens, 0._real64, real64)
            err(3) = max(err(3), oracle_rel_error(oracle_flat(unit%numerator()), oracle_flat(num)))
            call unit%kill()
            ! this plane alone against the explicit matrix times each pixel's value taken at the pixel itself:
            ! a real plane's transform at a mate is the conjugate, so the mate rule is not typed again
            a = explicit_weights(plane%rotation(), n)
            call direct_values(plane, cp, qp)
            call one%new(n)
            call one%insert(c, q, plane%rotation(), omega)
            num    = cmplx(one%density(), 0._real64, real64)
            numone = 4._real64 * omega * matmul(a, cp)
            denone = cmplx(omega * matmul(a, qp), 0._real64, real64)
            err(2) = max(err(2), oracle_rel_error(oracle_flat(one%numerator()), numone), &
                         oracle_rel_error(oracle_flat(num), denone))
            call one%kill()
            numref = numref + numone
            denref = denref + real(denone)
            call lat%insert(c, q, plane%rotation(), omega)
            call plane%kill()
        end do
        num    = cmplx(lat%density(), 0._real64, real64)
        err(2) = max(err(2), oracle_rel_error(oracle_flat(lat%numerator()), numref), &
                     oracle_rel_error(oracle_flat(num), cmplx(denref, 0._real64, real64)))
        ! the stored half read by destination from the reference accumulators: h > 0 its own voxel, h = 0 the
        ! conjugate of the voxel at the mate, the edge index -n/2 being its own mate
        call lat%compress(s, rho)
        sref   = CZERO
        rhoref = 0._real64
        do m = -nyq, nyq - 1
            do k = -nyq, nyq - 1
                do h = 0, nyq
                    km = [k, m]
                    if( h == 0 ) km = merge(km, -km, km == -nyq)
                    vs = numref(voxel_row([h, km(1), km(2)], n))
                    ds = denref(voxel_row([h, km(1), km(2)], n))
                    if( abs(vs) < COMPRESS_FLOOR .and. ds <= COMPRESS_FLOOR ) cycle
                    if( h == 0 ) vs = conjg(vs)
                    sref(1+h, 1+modulo(k, n), 1+modulo(m, n))   = vs
                    rhoref(1+h, 1+modulo(k, n), 1+modulo(m, n)) = ds
                end do
            end do
        end do
        err(4) = max(err(4), oracle_rel_error(oracle_flat(s), oracle_flat(sref)), &
                     oracle_rel_error(oracle_flat(cmplx(rho, 0._real64, real64)), oracle_flat(cmplx(rhoref, 0._real64, real64))))
        ! nothing of the halo or of h < 0 reaches the stored half: its density sums to the stored range's alone,
        ! and the rest of the accumulator is not empty
        dens   = lat%density()
        ds     = sum(dens(HALO_LOW+1:HALO_LOW+nyq+1, HALO+1:HALO+n, HALO+1:HALO+n))
        err(4) = max(err(4), abs(sum(rho) - ds) / ds)
        if( .not. (sum(dens) > 1.25_real64 * ds) ) nbad = nbad + 1
        err(1) = err(1) + real(nbad, real64)
        ! the conjugate rule by value, from the module's own accumulators
        nbad = 0
        num  = lat%numerator()
        do m = -nyq, nyq - 1
            do k = -nyq, nyq - 1
                do h = 0, nyq
                    vs = num(h+HALO_LOW+1, k+nyq+HALO+1, m+nyq+HALO+1)
                    ds = dens(h+HALO_LOW+1, k+nyq+HALO+1, m+nyq+HALO+1)
                    km = [k, m]
                    if( h == 0 )then
                        vs = conjg(vs)
                        km = -km
                        if( k == -nyq ) km(1) = -nyq
                        if( m == -nyq ) km(2) = -nyq
                    endif
                    if( .not. (abs(s(1+h, 1+modulo(km(1), n), 1+modulo(km(2), n)) - vs) <= 0._real64) ) nbad = nbad + 1
                    if( .not. (abs(rho(1+h, 1+modulo(km(1), n), 1+modulo(km(2), n)) - ds) <= 0._real64) ) nbad = nbad + 1
                end do
            end do
        end do
        err(5) = err(5) + real(nbad, real64)
        call lat%kill()
    end subroutine check_deposits

    ! the rules of a pixel on constructed data at n = 4 and the identity, by counts worked by hand
    subroutine check_pixel_rules( err )
        real(real64), intent(inout) :: err
        type(oracle_grid_lattice)    :: lat
        complex(real64), allocatable :: c(:,:), s(:,:,:)
        real(real64),    allocatable :: q(:,:), rho(:,:,:)
        real(real64)                 :: r(3, 3)
        integer                      :: n, nyq, nbad, icase
        n   = N_SMALL
        nyq = n / 2
        allocate(c(n+1, nyq+1), q(n+1, nyq+1), s(nyq+1, n, n), rho(nyq+1, n, n))
        r    = oracle_proj_rotation(1)
        nbad = 0
        do icase = 1, 9
            c = CZERO
            q = 0._real64
            select case( icase )
                case( 1 )
                    ! data that are nothing everywhere: no deposit
                    c = cmplx(5.e-11_real64, 0._real64, real64)
                    q = 5.e-11_real64
                case( 2 )
                    ! a numerator above the floor with a density below it: inserted
                    c = cmplx(6.e-11_real64, 6.e-11_real64, real64)
                    q = 5.e-11_real64
                case( 3 )
                    ! a density above the floor with no numerator: inserted
                    q = 2.e-10_real64
                case( 4 )
                    ! the pixel (-2, 0) alone: its taps -3, -2, -1 are all negative
                    c(1, nyq+1) = CONSTANT
                    q(1, nyq+1) = 1._real64
                case( 5 )
                    ! the pixel (-1, 0) alone: its taps -2, -1, 0 reach h = 0
                    c(2, nyq+1) = CONSTANT
                    q(2, nyq+1) = 1._real64
                case( 6 )
                    ! the sample (1, -1) alone: its pixel and the mate (-1, 1) share three voxels, 27 + 27 - 3
                    c(nyq+2, nyq) = CONSTANT
                    q(nyq+2, nyq) = 1._real64
                case( 7 )
                    ! the pixel (0, 0) with a small numerator and a smaller density: only the centre and its
                    ! face neighbours pass the compression's floor, six of them in the stored half
                    c(nyq+1, nyq+1) = cmplx(1.e-9_real64, 0._real64, real64)
                    q(nyq+1, nyq+1) = 2.e-10_real64
                case( 8 )
                    ! data at the floor itself are nothing still
                    c = cmplx(1.e-10_real64, 0._real64, real64)
                    q = 1.e-10_real64
                case default
                    ! the pixel (0, 0) with a density and no numerator: the compression keeps its 18 stored voxels
                    q(nyq+1, nyq+1) = 1._real64
            end select
            call lat%new(n)
            call lat%insert(c, q, r, 1._real64)
            call lat%compress(s, rho)
            select case( icase )
                case( 1, 4, 8 )
                    nbad = nbad + count(abs(lat%numerator()) > 0._real64) + count(lat%density() > 0._real64)
                case( 2 )
                    if( count(lat%density() > 0._real64) /= 105 ) nbad = nbad + 1
                    if( count(abs(lat%numerator()) > 0._real64) /= 105 ) nbad = nbad + 1
                case( 3 )
                    if( count(lat%density() > 0._real64) /= 105 ) nbad = nbad + 1
                    nbad = nbad + count(abs(lat%numerator()) > 0._real64)
                case( 5 )
                    if( count(lat%density() > 0._real64) /= 27 ) nbad = nbad + 1
                case( 6 )
                    if( count(lat%density() > 0._real64) /= 51 ) nbad = nbad + 1
                case( 7 )
                    if( count(lat%density() > 0._real64) /= 27 ) nbad = nbad + 1
                    if( count(abs(s) > 0._real64) /= 6 ) nbad = nbad + 1
                    if( count(rho > 0._real64) /= 6 ) nbad = nbad + 1
                case default
                    if( count(lat%density() > 0._real64) /= 27 ) nbad = nbad + 1
                    if( count(rho > 0._real64) /= 18 ) nbad = nbad + 1
                    nbad = nbad + count(abs(s) > 0._real64)
            end select
            call lat%kill()
        end do
        err = err + real(nbad, real64)
    end subroutine check_pixel_rules

    ! the disc's bound on an identity plane with data on every entry, by the voxels touched: at n = 16 the pixels
    ! with h**2 + k**2 = 72 = nyq (nyq + 1) are inserted and those with 73 are not; at n = 8 those with 20 are
    subroutine check_disc( err )
        real(real64), intent(inout) :: err
        type(oracle_grid_lattice)    :: lat
        complex(real64), allocatable :: c(:,:)
        real(real64),    allocatable :: q(:,:)
        integer                      :: n, ibox
        do ibox = 1, 2
            n = DISC_BOX(ibox)
            allocate(c(n+1, n/2+1), q(n+1, n/2+1))
            c = (1._real64, 0._real64)
            q = 1._real64
            call lat%new(n)
            call lat%insert(c, q, oracle_proj_rotation(1), 1._real64)
            if( count(lat%density() > 0._real64) /= DISC_TOUCHED(ibox) ) err = err + 1._real64
            call lat%kill()
            deallocate(c, q)
        end do
    end subroutine check_disc

    ! the density correction on constructed halves: a constant numerator over densities that cycle through
    ! values on either side of the floor and the floor itself; then the shell's count at unit density
    subroutine check_correction( n, ibox, err )
        integer,      intent(in)    :: n, ibox
        real(real64), intent(inout) :: err
        complex(real64), allocatable :: s(:,:,:), v(:,:,:), ref(:,:,:)
        real(real64),    allocatable :: rho(:,:,:)
        real(real64)                 :: cycle4(0:3)
        integer                      :: i1, i2, i3, g(3), nbad
        allocate(s(n/2+1, n, n), v(n/2+1, n, n), ref(n/2+1, n, n), rho(n/2+1, n, n))
        cycle4 = [2.e-6_real64, 5.e-7_real64, -2.e-6_real64, 1.e-6_real64]
        s      = CONSTANT
        ref    = CZERO
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n / 2 + 1
                    rho(i1, i2, i3) = cycle4(modulo(i1 + i2 + i3, 4))
                    g               = [i1 - 1, signed_index(i2, n), signed_index(i3, n)]
                    ! nint(|g|) <= n/2 is |g|**2 < (n/2 + 1/2)**2, in integers 4 |g|**2 < (n + 1)**2
                    if( 4 * dot_product(g, g) < (n + 1)**2 .and. modulo(i1 + i2 + i3, 2) == 0 )then
                        ref(i1, i2, i3) = CONSTANT / rho(i1, i2, i3)
                    endif
                end do
            end do
        end do
        v    = oracle_grid_correct(s, rho)
        err  = max(err, oracle_rel_error(oracle_flat(v), oracle_flat(ref)))
        nbad = count((abs(v) > 0._real64) .neqv. (abs(ref) > 0._real64))
        rho  = 1._real64
        v    = oracle_grid_correct(s, rho)
        if( count(abs(v) > 0._real64) /= IN_SHELL(ibox) ) nbad = nbad + 1
        err = max(err, real(nbad, real64))
    end subroutine check_correction

    ! a single on-grid sample at n = 8, pixel (2, -1) of an identity plane, its 27 voxels at h = 1 .. 3 inside the
    ! shell and its mate skipped: the map of its numerator is the plain wave 2 Re[4 omega c exp(i a)], and after
    ! the density's division each voxel holds 4 c / q, so each axis keeps (1 + 2 cos) / (w0 + 2 w1 cos)
    subroutine check_map( err )
        real(real64), intent(inout) :: err
        type(oracle_grid_lattice)    :: lat
        complex(real64), allocatable :: c(:,:), s(:,:,:), wave(:,:,:)
        real(real64),    allocatable :: q(:,:), rho(:,:,:), ref(:,:,:), x(:,:,:)
        real(real64)                 :: w(3), omega, qs, ax(N_LARGE), ang
        integer                      :: tap(3), n, nyq, i, i1, i2, i3
        n     = N_LARGE
        nyq   = n / 2
        omega = 1.25_real64
        qs    = 0.5_real64
        allocate(c(n+1, nyq+1), q(n+1, nyq+1), s(nyq+1, n, n), rho(nyq+1, n, n), wave(n, n, n), ref(n, n, n), x(n, n, n))
        c            = CZERO
        q            = 0._real64
        c(nyq+3, nyq) = CONSTANT
        q(nyq+3, nyq) = qs
        call lat%new(n)
        call lat%insert(c, q, oracle_proj_rotation(1), omega)
        call lat%compress(s, rho)
        call lat%kill()
        call oracle_proj_stencil(0._real64, tap, w)
        do i = 1, n
            ang   = TWOPI * real(i - 1 - nyq, real64) / real(n, real64)
            ax(i) = (1._real64 + 2._real64 * cos(ang)) / (w(2) + 2._real64 * w(1) * cos(ang))
        end do
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    ang             = TWOPI * real(2 * (i1 - 1 - nyq) - (i2 - 1 - nyq), real64) / real(n, real64)
                    wave(i1, i2, i3) = 2._real64 * real(CONSTANT * exp(cmplx(0._real64, ang, real64)))
                    ref(i1, i2, i3)  = 4._real64 / qs * real(wave(i1, i2, i3)) * ax(i1) * ax(i2) * ax(i3)
                end do
            end do
        end do
        x   = oracle_grid_map(s)
        err = max(err, real_error(reshape(x, [n**3]), 4._real64 * omega * reshape(real(wave), [n**3])))
        x   = oracle_grid_map(oracle_grid_correct(s, rho))
        err = max(err, real_error(reshape(x, [n**3]), reshape(ref, [n**3])))
    end subroutine check_map

    ! the real inverse of a stored half that is no half of a Hermitian array, at n = 4, against the sum it stands
    ! for, each voxel once on the planes h = 0 and n/2 and twice between; then a sample on the plane h = 0 at
    ! n = 8, pixel (0, -1) with its mate, whose numerator maps to the wave 2 Re[4 omega c exp(-2 pi i x2 / n)]
    subroutine check_half_inverse( err )
        real(real64), intent(inout) :: err
        type(oracle_grid_lattice)    :: lat
        complex(real64), allocatable :: p(:,:,:), c(:,:), s(:,:,:)
        real(real64),    allocatable :: ref(:,:,:), q(:,:), rho(:,:,:)
        real(real64)                 :: mu, ang, omega
        integer                      :: n, i1, i2, i3, j1, j2, j3, x(3)
        n = N_SMALL
        allocate(p(n/2+1, n, n), ref(n, n, n))
        do j3 = 1, n
            do j2 = 1, n
                do j1 = 1, n / 2 + 1
                    p(j1, j2, j3) = cmplx(modulo(3 * j1 + 5 * j2 + 7 * j3, 11) - 5, modulo(4 * j1 + j2 + 6 * j3, 13) - 6, &
                                          real64) / 4._real64
                end do
            end do
        end do
        ref = 0._real64
        do i3 = 1, n
            do i2 = 1, n
                do i1 = 1, n
                    x = [i1, i2, i3] - 1 - n / 2
                    do j3 = 1, n
                        do j2 = 1, n
                            do j1 = 1, n / 2 + 1
                                mu  = merge(1._real64, 2._real64, j1 == 1 .or. j1 == n / 2 + 1)
                                ang = TWOPI * real(dot_product([j1 - 1, signed_index(j2, n), signed_index(j3, n)], x), real64) / &
                                      real(n, real64)
                                ref(i1, i2, i3) = ref(i1, i2, i3) + mu * real(p(j1, j2, j3) * exp(cmplx(0._real64, ang, real64)))
                            end do
                        end do
                    end do
                end do
            end do
        end do
        err = max(err, real_error(reshape(oracle_grid_half_inverse(p), [n**3]), reshape(ref, [n**3])))
        deallocate(p, ref)
        n     = N_LARGE
        omega = 0.75_real64
        allocate(c(n+1, n/2+1), q(n+1, n/2+1), s(n/2+1, n, n), rho(n/2+1, n, n), ref(n, n, n))
        c             = CZERO
        q             = 0._real64
        c(n/2+1, n/2) = CONSTANT
        q(n/2+1, n/2) = 1._real64
        call lat%new(n)
        call lat%insert(c, q, oracle_proj_rotation(1), omega)
        call lat%compress(s, rho)
        call lat%kill()
        do i2 = 1, n
            ang         = -TWOPI * real(i2 - 1 - n / 2, real64) / real(n, real64)
            ref(:, i2, :) = 8._real64 * omega * real(CONSTANT * exp(cmplx(0._real64, ang, real64)))
        end do
        err = max(err, real_error(reshape(oracle_grid_map(s), [n**3]), reshape(ref, [n**3])))
    end subroutine check_half_inverse

    ! the guarded reciprocal on typed values: zero below 1e-8 on either side, the plain reciprocal at 1e-8 and
    ! above; and the window's transform at zero offset, where the weights sum to one
    subroutine check_guards( err )
        real(real64), intent(inout) :: err
        real(real64) :: e(8), ref(8), got(8)
        integer      :: nbad
        e    = [1.e-9_real64, -5.e-9_real64, 1.e-8_real64, 0.5_real64, -0.25_real64, 9.9e-9_real64, -9.9e-9_real64, &
                2.e-8_real64]
        ref  = [0._real64, 0._real64, 1.e8_real64, 2._real64, -4._real64, 0._real64, 0._real64, 5.e7_real64]
        got  = oracle_grid_reciprocal(e)
        nbad = count(.not. (abs(got - ref) <= TOL_MATRIX * abs(ref)))
        if( .not. (abs(oracle_grid_envelope(0, N_SMALL) - 1._real64) <= TOL_MATRIX) ) nbad = nbad + 1
        if( .not. (abs(oracle_grid_envelope(N_LARGE, N_LARGE) - 1._real64) <= TOL_MATRIX) ) nbad = nbad + 1
        err = err + real(nbad, real64)
    end subroutine check_guards

    ! the explicit insertion matrix from scalar geometry: a row per accumulator voxel in storage order, a column
    ! per pixel (h fastest, then k = -n/2 .. n/2 - 1). The weights are the projection oracle's voxel-indexed ones
    ! on a periodic grid too large to wrap; a pixel outside the disc or with loc_1 <= -3/2 has an empty column
    function explicit_weights( r, n ) result(a)
        real(real64), intent(in) :: r(3, 3)
        integer,      intent(in) :: n
        real(real64), allocatable :: a(:,:), g(:,:), loc(:,:)
        integer                   :: nyq, mbig, npix, p, h, k, v, g1, g2, g3
        nyq  = n / 2
        mbig = n + 2 * HALO + 2
        npix = (n + 1) * n
        allocate(a((nyq + HALO_LOW + HALO + 1) * (n + 2 * HALO + 1)**2, npix), g(npix, mbig**3), loc(3, npix))
        p = 0
        do k = -nyq, nyq - 1
            do h = -nyq, nyq
                p         = p + 1
                loc(:, p) = matmul(real([h, k, 0], real64), r)
            end do
        end do
        g = oracle_proj_matrix(loc, mbig)
        a = 0._real64
        p = 0
        do k = -nyq, nyq - 1
            do h = -nyq, nyq
                p = p + 1
                if( h * h + k * k > nyq * (nyq + 1) ) cycle
                if( loc(1, p) <= -1.5_real64 ) cycle
                v = 0
                do g3 = -(nyq + HALO), nyq + HALO
                    do g2 = -(nyq + HALO), nyq + HALO
                        do g1 = -HALO_LOW, nyq + HALO
                            v       = v + 1
                            a(v, p) = g(p, 1 + modulo(g1, mbig) + mbig * modulo(g2, mbig) + mbig * mbig * modulo(g3, mbig))
                        end do
                    end do
                end do
            end do
        end do
    end function explicit_weights

    ! the row of accumulator voxel g = (h, k, m) in the explicit matrix
    pure function voxel_row( g, n ) result(v)
        integer, intent(in) :: g(3), n
        integer :: v
        v = 1 + (g(1) + HALO_LOW) + (n / 2 + HALO_LOW + HALO + 1) * ((g(2) + n / 2 + HALO) + (n + 2 * HALO + 1) * &
                                                                     (g(3) + n / 2 + HALO))
    end function voxel_row

    ! what each pixel of a fixture plane inserts, evaluated at the pixel itself and not through its mate, in the
    ! explicit matrix's column order: t**2 Fv(loc) / (s2 n**3) and t**2 / s2 on the band, zero beyond it
    subroutine direct_values( plane, cp, qp )
        type(oracle_grid_plane), intent(in)  :: plane
        complex(real64),         intent(out) :: cp(:)
        real(real64),            intent(out) :: qp(:)
        real(real64), allocatable :: t(:,:), s2(:,:), loc(:,:)
        integer                   :: n, p, h, k
        n = plane%box()
        allocate(t(n+1, n+1), s2(n+1, n+1), loc(3, (n+1)*n))
        t  = plane%ctf()
        s2 = plane%variance()
        p  = 0
        do k = -n / 2, n / 2 - 1
            do h = -n / 2, n / 2
                p         = p + 1
                loc(:, p) = matmul(real([h, k, 0], real64), plane%rotation())
            end do
        end do
        cp = oracle_grid_transform(oracle_grid_volume(n), loc) / real(n, real64)**3
        p  = 0
        do k = -n / 2, n / 2 - 1
            do h = -n / 2, n / 2
                p = p + 1
                ! nint(2 sqrt(h**2 + k**2)) <= n in integers: 16 (h**2 + k**2) < (2 n + 1)**2
                if( 16 * (h * h + k * k) < (2 * n + 1)**2 )then
                    qp(p) = t(h+n/2+1, k+n/2+1)**2 / s2(h+n/2+1, k+n/2+1)
                    cp(p) = qp(p) * cp(p)
                else
                    qp(p) = 0._real64
                    cp(p) = CZERO
                endif
            end do
        end do
    end subroutine direct_values

    ! the largest |a - ref| relative to the largest |ref| of two real vectors; +Inf for a non-finite value
    pure function real_error( a, ref ) result(e)
        real(real64), intent(in) :: a(:), ref(:)
        real(real64) :: e
        e = oracle_rel_error(cmplx(a, 0._real64, real64), cmplx(ref, 0._real64, real64))
    end function real_error

end module mlxf_oracle_gridding
