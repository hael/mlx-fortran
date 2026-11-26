!@descr: the full-coverage fixture of the reconstruction's PCG solve: planes on a golden-angle spiral, two blobs, packed accumulators
! P planes in a box of n (P from the caller's variates, three per plane and three for a global rotation): normals on
! a golden-angle spiral over the hemisphere, each turned in its plane and shifted, then all turned together. A
! plane's sample at (h, k) is the two-blob phantom's continuous transform at (h, k, 0) R; the deposits follow the
! reconstruction oracle's lattice (disc, coordinate 2 (h, k, 0) R, three-tap window, wrap, factor 8) and only the
! packed half h = 0 .. m/2 is kept. Plain Fortran in double precision; the variates come from the caller.
module mlxf_oracle_recon_fixture
use, intrinsic :: iso_fortran_env, only: real64
use mlxf_oracle_projection, only: oracle_proj_stencil
use mlxf_oracle_gridding,   only: oracle_grid_plane
use mlxf_oracle_recon_pcg,  only: oracle_recon_lattice
use mlxf_test_reduce,       only: nan_maxval, nan_max
implicit none

public :: oracle_recon_fixture_accum, oracle_recon_fixture_nplanes, oracle_recon_fixture_check
private

real(real64),    parameter :: PI    = acos(-1._real64)
real(real64),    parameter :: TWOPI = 2._real64 * PI
complex(real64), parameter :: CZERO = (0._real64, 0._real64)
! the golden angle, the azimuth step of the spiral
real(real64), parameter :: GOLDEN = PI * (3._real64 - sqrt(5._real64))
! the lattice's numerator scale
real(real64), parameter :: NUM_SCALE = 8._real64
! the CTF 1 / (1 + (a h**2 + b h k + c k**2) / n**2) by its (a, b, c) and the weights, plane j taking entry
! 1 + modulo(j - 1, 3) of each; the noise variance is one
integer, parameter :: NFORM = 3
real(real64),    parameter :: CTF_FORMS(3, NFORM) = reshape([1._real64, 1._real64, 2._real64, 3._real64, -1._real64, &
                                                           1._real64, 2._real64, 2._real64, 4._real64], [3, NFORM])
real(real64), parameter :: PLANE_WEIGHTS(NFORM) = [1._real64, 0.75_real64, 1.25_real64]
! the phantom in units of n / 6: the blobs' centres, widths and amplitudes
real(real64),    parameter :: BLOB_CENTRES(3, 2) = reshape([-1._real64, 0._real64, 1._real64, 1._real64, 1._real64, &
                                                           -1._real64], [3, 2])
real(real64),    parameter :: BLOB_SIGMAS(2) = [1._real64, 0.7_real64]
real(real64),    parameter :: BLOB_AMPS(2)   = [1._real64, 0.7_real64]
real(real64),    parameter :: BLOB_UNIT      = 6._real64

! one plane of the fixture: its rotation (rows: the plane's two axes, then its normal), shift in pixels and weight,
! and on h, k = -n/2 .. n/2 its sample y and CTF t
type :: fixture_plane_data
    real(real64)                 :: rot(3, 3) = 0._real64, sh(2) = 0._real64, omega = 0._real64
    complex(real64), allocatable :: y(:,:)
    real(real64),    allocatable :: t(:,:)
end type fixture_plane_data

contains

    ! the planes a vector of variates describes: three for the global rotation, then three per plane
    pure function oracle_recon_fixture_nplanes( u ) result(np)
        real(real64), intent(in) :: u(:)
        integer :: np
        np = max(0, (size(u) - 3) / 3)
    end function oracle_recon_fixture_nplanes

    ! the packed numerator b and density d (n + 1, 2 n, 2 n) of the planes of u (variates in [-1, 1])
    subroutine oracle_recon_fixture_accum( n, u, b, d )
        integer,         intent(in)  :: n
        real(real64),    intent(in)  :: u(:)
        complex(real64), intent(out) :: b(:,:,:)
        real(real64),    intent(out) :: d(:,:,:)
        type(fixture_plane_data) :: pl
        complex(real64)          :: cs
        real(real64)             :: loc(3), w(3, 3), ww, phi, ds
        integer                  :: tap(3, 3), m, nyq, h, k, a, j, j1, j2, j3, i(3)
        m   = 2 * n
        nyq = n / 2
        b   = CZERO
        d   = 0._real64
        allocate(pl%y(-nyq:nyq, -nyq:nyq), pl%t(-nyq:nyq, -nyq:nyq))
        do j = 1, oracle_recon_fixture_nplanes(u)
            call fixture_plane(n, u, j, pl)
            do k = -nyq, nyq
                do h = -nyq, nyq
                    if( h * h + k * k > nyq * nyq ) cycle
                    loc = 2._real64 * matmul(real([h, k, 0], real64), pl%rot)
                    do a = 1, 3
                        call oracle_proj_stencil(loc(a), tap(:, a), w(:, a))
                    end do
                    if( all(tap(:, 1) > -m / 2 .and. tap(:, 1) < 0) ) cycle
                    phi = TWOPI * (real(h, real64) * pl%sh(1) + real(k, real64) * pl%sh(2)) / real(n, real64)
                    cs  = NUM_SCALE * pl%t(h, k) * exp(cmplx(0._real64, -phi, real64)) * pl%omega * pl%y(h, k)
                    ds  = pl%t(h, k)**2 * pl%omega
                    do j3 = 1, 3
                        do j2 = 1, 3
                            do j1 = 1, 3
                                i = 1 + modulo([tap(j1, 1), tap(j2, 2), tap(j3, 3)], m)
                                ! only the packed half h = 0 .. m/2 is kept
                                if( i(1) > m / 2 + 1 ) cycle
                                ww                   = w(j1, 1) * w(j2, 2) * w(j3, 3)
                                b(i(1), i(2), i(3)) = b(i(1), i(2), i(3)) + ww * cs
                                d(i(1), i(2), i(3)) = d(i(1), i(2), i(3)) + ww * ds
                            end do
                        end do
                    end do
                end do
            end do
        end do
    end subroutine oracle_recon_fixture_accum

    ! the generator against the reconstruction oracle's lattice fed the same planes: the largest difference of
    ! the packed numerator and of the packed density, each over its largest magnitude
    subroutine oracle_recon_fixture_check( n, u, err )
        integer,      intent(in)  :: n
        real(real64), intent(in)  :: u(:)
        real(real64), intent(out) :: err
        type(oracle_grid_plane)      :: plane
        type(oracle_recon_lattice)   :: lat
        type(fixture_plane_data)     :: pl
        complex(real64), allocatable :: b(:,:,:)
        real(real64),    allocatable :: d(:,:,:), s2(:,:)
        integer                      :: j
        allocate(b(n+1, 2*n, 2*n), d(n+1, 2*n, 2*n), s2(n+1, n+1), pl%y(-n/2:n/2, -n/2:n/2), pl%t(-n/2:n/2, -n/2:n/2))
        call oracle_recon_fixture_accum(n, u, b, d)
        s2 = 1._real64
        call lat%new(n)
        call plane%new(1, n)
        do j = 1, oracle_recon_fixture_nplanes(u)
            call fixture_plane(n, u, j, pl)
            call plane%set_data(pl%y, pl%t, s2)
            call plane%set_pose(pl%rot, pl%omega, pl%sh)
            call lat%insert(plane)
        end do
        err = nan_max(nan_maxval(abs(b - lat%packed_numerator())) / nan_maxval(abs(lat%packed_numerator())), &
                  nan_maxval(abs(d - lat%packed_density())) / nan_maxval(abs(lat%packed_density())))
        call plane%kill()
        call lat%kill()
    end subroutine oracle_recon_fixture_check

    ! plane j of u in a box of n, its sample y = t exp(+i phi) F((h, k, 0) R) / n**3 with F the phantom's transform;
    ! y and t come allocated on -n/2 .. n/2
    pure subroutine fixture_plane( n, u, j, pl )
        integer,                  intent(in)    :: n, j
        real(real64),             intent(in)    :: u(:)
        type(fixture_plane_data), intent(inout) :: pl
        real(real64) :: g(3, 3), r0(3, 3), z, az, psi, e1(3), e2(3), nv(3), q(3), phi
        integer      :: np, iform, h, k
        np    = oracle_recon_fixture_nplanes(u)
        g     = euler_zyz(PI * (u(1) + 1._real64), acos(u(2)), PI * (u(3) + 1._real64))
        z     = 1._real64 - (real(j, real64) - 0.5_real64) / real(np, real64)
        az    = real(j, real64) * GOLDEN
        nv    = [sqrt(1._real64 - z * z) * cos(az), sqrt(1._real64 - z * z) * sin(az), z]
        e1    = [-sin(az), cos(az), 0._real64]
        e2    = [nv(2) * e1(3) - nv(3) * e1(2), nv(3) * e1(1) - nv(1) * e1(3), nv(1) * e1(2) - nv(2) * e1(1)]
        psi   = PI * (u(3 + 3 * (j - 1) + 1) + 1._real64)
        r0(1, :) = cos(psi) * e1 + sin(psi) * e2
        r0(2, :) = -sin(psi) * e1 + cos(psi) * e2
        r0(3, :) = nv
        pl%rot   = matmul(r0, g)
        pl%sh    = u(3 + 3 * (j - 1) + 2:3 + 3 * (j - 1) + 3)
        iform    = 1 + modulo(j - 1, NFORM)
        pl%omega = PLANE_WEIGHTS(iform)
        do k = -n / 2, n / 2
            do h = -n / 2, n / 2
                q          = matmul(real([h, k, 0], real64), pl%rot)
                pl%t(h, k) = 1._real64 / (1._real64 + (CTF_FORMS(1, iform) * real(h * h, real64) + CTF_FORMS(2, iform) * &
                                                   real(h * k, real64) + CTF_FORMS(3, iform) * real(k * k, real64)) / &
                                       real(n * n, real64))
                phi        = TWOPI * (real(h, real64) * pl%sh(1) + real(k, real64) * pl%sh(2)) / real(n, real64)
                pl%y(h, k) = pl%t(h, k) * exp(cmplx(0._real64, phi, real64)) * blob_transform(q, n) / real(n, real64)**3
            end do
        end do
    end subroutine fixture_plane

    ! the phantom's continuous transform at frequency q (cycles per box of n): each blob a (2 pi s**2)**1.5
    ! exp(-2 pi**2 s**2 |q|**2 / n**2) exp(-2 pi i q.c / n), centres c and widths s in units of n / 6
    pure function blob_transform( q, n ) result(f)
        real(real64), intent(in) :: q(3)
        integer,      intent(in) :: n
        complex(real64) :: f
        real(real64)    :: s, c(3), scale
        integer         :: ib
        scale = real(n, real64) / BLOB_UNIT
        f     = CZERO
        do ib = 1, 2
            s = BLOB_SIGMAS(ib) * scale
            c = BLOB_CENTRES(:, ib) * scale
            f = f + BLOB_AMPS(ib) * (TWOPI * s * s)**1.5_real64 * &
                    exp(-2._real64 * PI * PI * s * s * sum(q * q) / real(n, real64)**2) * &
                    exp(cmplx(0._real64, -TWOPI * sum(q * c) / real(n, real64), real64))
        end do
    end function blob_transform

    ! the rotation Rz(a) Ry(b) Rz(c)
    pure function euler_zyz( a, b, c ) result(r)
        real(real64), intent(in) :: a, b, c
        real(real64) :: r(3, 3), ra(3, 3), rb(3, 3), rc(3, 3)
        ra = rot_z(a)
        rb = rot_y(b)
        rc = rot_z(c)
        r  = matmul(matmul(ra, rb), rc)
    end function euler_zyz

    pure function rot_z( a ) result(r)
        real(real64), intent(in) :: a
        real(real64) :: r(3, 3)
        r = reshape([cos(a), sin(a), 0._real64, -sin(a), cos(a), 0._real64, 0._real64, 0._real64, 1._real64], [3, 3])
    end function rot_z

    pure function rot_y( b ) result(r)
        real(real64), intent(in) :: b
        real(real64) :: r(3, 3)
        r = reshape([cos(b), 0._real64, -sin(b), 0._real64, 1._real64, 0._real64, sin(b), 0._real64, cos(b)], [3, 3])
    end function rot_y

end module mlxf_oracle_recon_fixture
