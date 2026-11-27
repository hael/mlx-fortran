!@descr: the protected-update probe: SIMPLE's gridding insertion as one Metal kernel with atomic float32 deposits, against the oracle
! mlxf_test_exec test=bench_insert_probe suite=probe. A measurement, not a toy: one thread per (pixel, plane) adds
! its 27 weighted deposits, the numerator 4 omega W c as (real, imaginary) and the density omega W q, to float32
! outputs under atomic_outputs with init_value 0; its control is the same kernel with plain read-modify-write
! additions, as SIMPLE's offload insertion adds. The deposit rule is the oracle's (mlxf_oracle_gridding's
! lattice_insert): the plane's disc h**2 + k**2 <= nyq (nyq + 1) at loc = (h, k, 0) R, three Kaiser-Bessel taps per
! axis, a pixel skipped without data or when its three h taps are negative, on accumulators with a halo. Pixels
! whose coordinate lies within PROJ_TIE_MARGIN of a half-integer are given no data, in both. Small fixtures (the
! oracle's three planes at n = 8, 64 seeded planes at n = 16) and two collision-heavy cases at n = 160 (two batches
! of MAXIMGBATCHSZ planes, seeded orientations, then one orientation for all) report the errors over the sum of
! |terms| of a voxel, the voxels whose bits differ over repeats, the mass the control loses, the scratch memory and
! the seconds per batch.
module mlxf_bench_insert_probe
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf,                   only: mlx_array, mlx_custom_kernel, mlx_custom_kernel_spec, mlx_from, mlx_to, mlx_eval, &
                                  mlx_synchronize, mlx_set_default_device, mlx_peak_memory, mlx_reset_peak_memory, &
                                  mlx_zeros, MLX_DEVICES, MLX_DTYPES
use mlxf_test_defs,         only: KBWINSZ, KBALPHA, MAXIMGBATCHSZ, PROJ_TIE_MARGIN, PROBE_ERR_CAP, probe_case
use mlxf_oracle_gridding,   only: oracle_grid_plane, oracle_grid_lattice, oracle_grid_selfcheck
use mlxf_oracle_projection, only: oracle_proj_stencil
use mlxf_test_utils,        only: assert_true, set_fixed_seed, bits_equal
use mlxf_test_reduce,       only: nan_maxval, nan_max
implicit none
private

public :: run_bench_insert_probe, probe_spec, seeded_case, window_coefficients

character(len=1), parameter :: NL = achar(10)
real(real64),     parameter :: PI = acos(-1._real64)
! the oracle's accumulators: h from -HALO_LOW to n/2 + HALO, k and m from -(n/2 + HALO) to n/2 + HALO; the
! numerator's scale; the floor under which a pixel's data count as nothing
integer,          parameter :: HALO_LOW   = 3
integer,          parameter :: HALO       = 2
real(real32),     parameter :: NUM_SCALE  = 4._real32
real(real32),     parameter :: DATA_FLOOR = 1.e-10_real32
! the window's polynomial terms
integer, parameter :: NCOEF = 15
! the cases: the small boxes and plane counts, the large box, its batches, the repeats of the large cases
integer,          parameter :: N_ORACLE   = 8
integer,          parameter :: N_SEEDED   = 16
integer,          parameter :: NP_SEEDED  = 64
integer,          parameter :: N_LARGE    = 160
integer,          parameter :: NBATCH     = 2
integer,          parameter :: NREPEAT    = 9
integer,          parameter :: NTIMED     = 3
integer,          parameter :: PROBE_SEED = 17
! the deposits of one thread: the source the two kernels share, then the atomic and the plain additions
character(len=*), parameter :: SRC_HEAD = &
    &'const uint i = thread_position_in_grid.x;'//NL// &
    &'const uint p = thread_position_in_grid.y;'//NL// &
    &'if (i >= uint(NPIX)) return;'//NL// &
    &'const float h = hk[2 * i];'//NL// &
    &'const float k = hk[2 * i + 1];'//NL// &
    &'const complex64_t cv = c[i + uint(NPIX) * p];'//NL// &
    &'const float qv = q[i + uint(NPIX) * p];'//NL// &
    &'if (metal::fabs(cv.real) + metal::fabs(cv.imag) <= 1.0e-10f && qv <= 1.0e-10f) return;'//NL// &
    &'const float om = omega[p];'//NL// &
    &'const float twoow = coef[15];'//NL// &
    &'const float oneow = coef[16];'//NL// &
    &'int t0[3];'//NL// &
    &'float w[3][3];'//NL// &
    &'for (int a = 0; a < 3; ++a) {'//NL// &
    &'  const float loc = h * rot[9 * p + 3 * a] + k * rot[9 * p + 3 * a + 1];'//NL// &
    &'  const float b = metal::sign(loc) * metal::floor(metal::fabs(loc) + 0.5f);'//NL// &
    &'  t0[a] = int(b) - 1;'//NL// &
    &'  const float base = float(t0[a]) - loc;'//NL// &
    &'  float s = 0.0f;'//NL// &
    &'  for (int j = 0; j < 3; ++j) {'//NL// &
    &'    const float x = base + float(j);'//NL// &
    &'    const float qq = twoow * x;'//NL// &
    &'    const float u = metal::max(0.0f, 1.0f - qq * qq);'//NL// &
    &'    float pp = coef[14];'//NL// &
    &'    for (int cc = 13; cc >= 0; --cc) pp = pp * u + coef[cc];'//NL// &
    &'    w[a][j] = oneow * pp;'//NL// &
    &'    s += w[a][j];'//NL// &
    &'  }'//NL// &
    &'  for (int j = 0; j < 3; ++j) w[a][j] = w[a][j] / s;'//NL// &
    &'}'//NL// &
    &'if (t0[0] + 2 < 0) return;'//NL// &
    &'for (int l = 0; l < 3; ++l) {'//NL// &
    &'  for (int j = 0; j < 3; ++j) {'//NL// &
    &'    for (int a = 0; a < 3; ++a) {'//NL// &
    &'      const float ww = w[0][a] * w[1][j] * w[2][l];'//NL// &
    &'      const uint v = uint(t0[0] + a + HL) + uint(NH) * (uint(t0[1] + j + HK) + uint(NK) * uint(t0[2] + l + HK));'// &
    &NL// &
    &'      const float fn = ww * 4.0f * om;'//NL// &
    &'      const float fd = ww * om;'//NL
character(len=*), parameter :: SRC_ATOMIC = &
    &'      atomic_fetch_add_explicit(&num[2 * v], fn * cv.real, memory_order_relaxed);'//NL// &
    &'      atomic_fetch_add_explicit(&num[2 * v + 1], fn * cv.imag, memory_order_relaxed);'//NL// &
    &'      atomic_fetch_add_explicit(&dens[v], fd * qv, memory_order_relaxed);'//NL
character(len=*), parameter :: SRC_PLAIN = &
    &'      num[2 * v] = num[2 * v] + fn * cv.real;'//NL// &
    &'      num[2 * v + 1] = num[2 * v + 1] + fn * cv.imag;'//NL// &
    &'      dens[v] = dens[v] + fd * qv;'//NL
character(len=*), parameter :: SRC_TAIL = '    }'//NL//'  }'//NL//'}'

! the results of one insertion of a case: the numerator (2, nvox) and the density (nvox), and the batches' seconds
type :: probe_run
    real(real32), allocatable :: num(:,:)
    real(real32), allocatable :: dens(:)
    real(real64), allocatable :: secs(:)
end type probe_run

contains

    subroutine run_bench_insert_probe( mode, found )
        character(len=*), intent(in)  :: mode
        logical,          intent(out) :: found
        character(len=:), allocatable :: labels(:)
        real(real64),     allocatable :: errors(:), limits(:)
        character(len=512)            :: arg
        integer                       :: i
        found = trim(mode) == 'probe'
        if( .not. found ) return
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            if( index(arg, 'test=') == 1 .or. index(arg, 'suite=') == 1 ) cycle
            write(*,'(a)') 'bench_insert_probe: suite=probe reads no key: '//trim(arg)
            error stop 2
        end do
        write(*,'(a)') '**** bench_insert_probe suite=probe ****'
        call mlx_set_default_device(MLX_DEVICES%gpu)
        ! the oracle's self-check first
        call oracle_grid_selfcheck(labels, errors, limits)
        do i = 1, size(labels)
            call assert_true(errors(i) <= limits(i), 'oracle_grid self-check '//trim(labels(i))//' within its limit')
        end do
        write(*,'(a,i0,a,es10.3)') '    oracle_grid self-check: ', count(errors <= limits), ' of 13 within their limits; '// &
            &'largest error ', maxval(errors)
        call probe_small(oracle_case())
        call probe_small(seeded_case('seeded n=16', N_SEEDED, NP_SEEDED, .false.))
        call probe_large(seeded_case('collision-heavy, seeded orientations', N_LARGE, NBATCH * MAXIMGBATCHSZ, .false.))
        call probe_large(seeded_case('collision-heavy, one orientation', N_LARGE, NBATCH * MAXIMGBATCHSZ, .true.))
    end subroutine run_bench_insert_probe

    ! ---- the cases ---------------------------------------------------------------------------------------------

    ! the disc's pixels of a box n, in the oracle's loop order (k from -nyq to nyq - 1, h from -nyq to nyq)
    function disc_pixels( n ) result(hk)
        integer, intent(in) :: n
        real(real32), allocatable :: hk(:,:)
        integer                   :: h, k, nyq, s
        nyq = n / 2
        allocate(hk(2, (n + 1)**2))
        s = 0
        do k = -nyq, nyq - 1
            do h = -nyq, nyq
                if( h * h + k * k > nyq * (nyq + 1) ) cycle
                s = s + 1
                hk(:, s) = real([h, k], real32)
            end do
        end do
        hk = hk(:, 1:s)
    end function disc_pixels

    ! the kernel's data of every disc pixel from the oracle's half arrays (the conjugate of the mate where k > 0)
    subroutine fill_pixels( cs, p )
        type(probe_case), intent(inout) :: cs
        integer,          intent(in)    :: p
        integer :: i, h, k, nyq
        nyq = cs%n / 2
        do i = 1, cs%npix
            h = nint(cs%hk(1, i))
            k = nint(cs%hk(2, i))
            if( k <= 0 )then
                cs%c(i, p) = cmplx(cs%oc(h+nyq+1, k+nyq+1, p), kind=real32)
                cs%q(i, p) = real(cs%oq(h+nyq+1, k+nyq+1, p), real32)
            else
                cs%c(i, p) = cmplx(conjg(cs%oc(nyq+1-h, nyq+1-k, p)), kind=real32)
                cs%q(i, p) = real(cs%oq(nyq+1-h, nyq+1-k, p), real32)
            endif
        end do
    end subroutine fill_pixels

    ! a pixel of the half k <= 0 near a tie under plane p's rotation (its mate shares the distance) loses its data
    subroutine drop_ties( cs, p )
        type(probe_case), intent(inout) :: cs
        integer,          intent(in)    :: p
        real(real64) :: loc(3)
        integer      :: h, k, nyq, a
        nyq = cs%n / 2
        do k = -nyq, 0
            do h = -nyq, nyq
                do a = 1, 3
                    loc(a) = real(h, real64) * real(cs%rot(1, a, p), real64) + &
                             &real(k, real64) * real(cs%rot(2, a, p), real64)
                end do
                if( any(abs(loc - (floor(loc) + 0.5_real64)) < PROJ_TIE_MARGIN) )then
                    if( abs(cs%oq(h+nyq+1, k+nyq+1, p)) > 0._real64 .or. abs(cs%oc(h+nyq+1, k+nyq+1, p)) > 0._real64 ) &
                        &cs%ntie = cs%ntie + 1
                    cs%oc(h+nyq+1, k+nyq+1, p) = (0._real64, 0._real64)
                    cs%oq(h+nyq+1, k+nyq+1, p) = 0._real64
                endif
            end do
        end do
    end subroutine drop_ties

    ! the oracle's three planes at n = 8 (their own rotations, weights and data)
    function oracle_case() result(cs)
        type(probe_case)             :: cs
        type(oracle_grid_plane)      :: pl
        complex(real64), allocatable :: c(:,:)
        real(real64),    allocatable :: q(:,:)
        integer                      :: p
        cs%name = 'the oracle''s three planes, n=8'
        cs%n    = N_ORACLE
        cs%hk   = disc_pixels(cs%n)
        cs%npix = size(cs%hk, 2)
        allocate(cs%rot(3, 3, 3), cs%omega(3), cs%c(cs%npix, 3), cs%q(cs%npix, 3), cs%oc(cs%n+1, cs%n+1, 3), &
            &cs%oq(cs%n+1, cs%n+1, 3), c(cs%n+1, cs%n+1), q(cs%n+1, cs%n+1))
        do p = 1, 3
            call pl%new(p, cs%n)
            call pl%samples(c, q)
            cs%oc(:, :, p)  = c
            cs%oq(:, :, p)  = q
            cs%rot(:, :, p) = real(pl%rotation(), real32)
            cs%omega(p)     = real(pl%weight(), real32)
            call pl%kill()
            call drop_ties(cs, p)
            call fill_pixels(cs, p)
        end do
    end function oracle_case

    ! np seeded planes of box n: data rounded once to single precision (decaying with the radius), weights in
    ! [0.5, 1.5), rotations uniform on the sphere, or all the first one (one)
    function seeded_case( name, n, np, one ) result(cs)
        character(len=*), intent(in) :: name
        integer,          intent(in) :: n, np
        logical,          intent(in) :: one
        type(probe_case)          :: cs
        real(real64)              :: u(3), e(3), r1(3, 3), r2(3, 3), r3(3, 3), r21(3, 3), amp, ws
        real(real64), allocatable :: re(:,:), im(:,:), qq(:,:)
        integer                   :: p, h, k, nyq
        cs%name = name
        cs%n    = n
        cs%hk   = disc_pixels(n)
        cs%npix = size(cs%hk, 2)
        nyq     = n / 2
        allocate(cs%rot(3, 3, np), cs%omega(np), cs%c(cs%npix, np), cs%q(cs%npix, np), cs%oc(n+1, n+1, np), &
            &cs%oq(n+1, n+1, np), re(n+1, n+1), im(n+1, n+1), qq(n+1, n+1))
        call set_fixed_seed(PROBE_SEED + n + merge(1, 0, one))
        do p = 1, np
            if( p == 1 .or. .not. one )then
                call random_number(u)
                e   = [360._real64 * u(1), acos(2._real64 * u(2) - 1._real64) * 180._real64 / PI, 360._real64 * u(3)]
                r1  = rot_z(e(1))
                r2  = rot_y(e(2))
                r3  = rot_z(e(3))
                r21 = matmul(r2, r1)
                cs%rot(:, :, p) = real(matmul(r3, r21), real32)
            else
                cs%rot(:, :, p) = cs%rot(:, :, 1)
            endif
            call random_number(ws)
            cs%omega(p) = real(0.5_real64 + ws, real32)
            call random_number(re)
            call random_number(im)
            call random_number(qq)
            cs%oc(:, :, p) = (0._real64, 0._real64)
            cs%oq(:, :, p) = 0._real64
            do k = -nyq, 0
                do h = -nyq, nyq
                    amp = 1._real64 / (1._real64 + real(h * h + k * k, real64) / real(nyq * nyq, real64))
                    cs%oc(h+nyq+1, k+nyq+1, p) = cmplx(cmplx(amp * (2._real64 * re(h+nyq+1, k+nyq+1) - 1._real64), &
                        &amp * (2._real64 * im(h+nyq+1, k+nyq+1) - 1._real64), real64), kind=real32)
                    cs%oq(h+nyq+1, k+nyq+1, p) = real(real(amp * (0.1_real64 + qq(h+nyq+1, k+nyq+1)), real32), real64)
                end do
            end do
            call drop_ties(cs, p)
            call fill_pixels(cs, p)
        end do
    end function seeded_case

    pure function rot_z( a ) result(r)
        real(real64), intent(in) :: a
        real(real64) :: r(3, 3), c, s
        c = cos(a * PI / 180._real64)
        s = sin(a * PI / 180._real64)
        r = reshape([c, -s, 0._real64, s, c, 0._real64, 0._real64, 0._real64, 1._real64], [3, 3])
    end function rot_z

    pure function rot_y( a ) result(r)
        real(real64), intent(in) :: a
        real(real64) :: r(3, 3), c, s
        c = cos(a * PI / 180._real64)
        s = sin(a * PI / 180._real64)
        r = reshape([c, 0._real64, s, 0._real64, 1._real64, 0._real64, -s, 0._real64, c], [3, 3])
    end function rot_y

    ! ---- the oracle --------------------------------------------------------------------------------------------

    ! the oracle's numerator and density of a case (the accumulators before compression, widened from the toy's
    ! single-precision inputs), and the sum of the numerator's |terms| per voxel (the data's moduli inserted)
    subroutine oracle_insert( cs, num, dens, scale )
        type(probe_case),             intent(in)  :: cs
        complex(real64), allocatable, intent(out) :: num(:)
        real(real64),    allocatable, intent(out) :: dens(:), scale(:)
        type(oracle_grid_lattice)    :: lat, lab
        complex(real64), allocatable :: acc(:,:,:)
        real(real64),    allocatable :: den(:,:,:), mags(:,:)
        integer                      :: p, nh, nk
        nh = cs%n / 2 + HALO_LOW + HALO + 1
        nk = cs%n + 2 * HALO + 1
        call lat%new(cs%n)
        call lab%new(cs%n)
        allocate(mags(cs%n+1, cs%n+1), acc(nh, nk, nk), den(nh, nk, nk))
        do p = 1, size(cs%omega)
            call lat%insert(cs%oc(:, :, p), cs%oq(:, :, p), real(cs%rot(:, :, p), real64), real(cs%omega(p), real64))
            mags = abs(cs%oc(:, :, p))
            call lab%insert(cmplx(mags, 0._real64, real64), cs%oq(:, :, p), real(cs%rot(:, :, p), real64), &
                &real(cs%omega(p), real64))
        end do
        acc   = lat%numerator()
        num   = reshape(acc, [size(acc)])
        den   = lat%density()
        dens  = reshape(den, [size(den)])
        acc   = lab%numerator()
        scale = reshape(real(acc), [size(acc)])
        call lat%kill()
        call lab%kill()
    end subroutine oracle_insert

    ! ---- the kernels -------------------------------------------------------------------------------------------

    ! the kernel of a case for a batch of nb planes: atomic deposits, or the plain control
    function probe_spec( cs, nb, atomic ) result(spec)
        type(probe_case), intent(in) :: cs
        integer,          intent(in) :: nb
        logical,          intent(in) :: atomic
        type(mlx_custom_kernel_spec) :: spec
        integer                      :: nvox
        nvox = (cs%n / 2 + HALO_LOW + HALO + 1) * (cs%n + 2 * HALO + 1)**2
        spec%name = 'insert_plane_atomic'
        if( .not. atomic ) spec%name = 'insert_plane_plain'
        if( atomic )then
            spec%source = SRC_HEAD//SRC_ATOMIC//SRC_TAIL
        else
            spec%source = SRC_HEAD//SRC_PLAIN//SRC_TAIL
        endif
        spec%input_names        = [character(len=5) :: 'hk', 'rot', 'omega', 'c', 'q', 'coef']
        spec%output_names       = [character(len=4) :: 'num', 'dens']
        spec%grid               = [cs%npix, nb, 1]
        spec%threadgroup        = [min(256, cs%npix), 1, 1]
        spec%output_shapes      = [2, nvox, nvox]
        spec%output_ranks       = [2, 1]
        spec%output_dtypes      = [MLX_DTYPES%float32, MLX_DTYPES%float32]
        spec%init_value         = 0.
        spec%atomic_outputs     = atomic
        spec%template_int_names = [character(len=4) :: 'NPIX', 'HL', 'HK', 'NH', 'NK']
        spec%template_ints      = [cs%npix, HALO_LOW, cs%n / 2 + HALO, cs%n / 2 + HALO_LOW + HALO + 1, cs%n + 2 * HALO + 1]
    end function probe_spec

    ! one insertion of a case in batches of at most MAXIMGBATCHSZ planes, the batches' outputs added in order;
    ! the seconds of each batch (its launch and evaluation)
    subroutine insert_case( cs, atomic, run, status )
        type(probe_case), intent(in)  :: cs
        logical,          intent(in)  :: atomic
        type(probe_run),  intent(out) :: run
        integer,          intent(out) :: status
        type(mlx_custom_kernel)      :: kern
        type(mlx_array), allocatable :: outs(:)
        type(mlx_array)              :: num, dens, hk, coef, rotd, omd, cd, qd
        integer(int64)               :: t0, t1, rate
        integer                      :: np, nb, b0, ib, nbatches, nvox
        np       = size(cs%omega)
        nbatches = (np + MAXIMGBATCHSZ - 1) / MAXIMGBATCHSZ
        nvox     = (cs%n / 2 + HALO_LOW + HALO + 1) * (cs%n + 2 * HALO + 1)**2
        allocate(run%secs(nbatches))
        hk   = mlx_from(cs%hk)
        coef = mlx_from(window_coefficients())
        num  = mlx_zeros([2, nvox], dtype=MLX_DTYPES%float32)
        dens = mlx_zeros([nvox], dtype=MLX_DTYPES%float32)
        call mlx_eval(num, status=status)
        call mlx_eval(dens, status=status)
        do ib = 1, nbatches
            b0 = (ib - 1) * MAXIMGBATCHSZ + 1
            nb = min(MAXIMGBATCHSZ, np - b0 + 1)
            kern = mlx_custom_kernel(probe_spec(cs, nb, atomic))
            call mlx_synchronize()
            call system_clock(t0, rate)
            rotd = mlx_from(cs%rot(:, :, b0:b0+nb-1))
            omd  = mlx_from(cs%omega(b0:b0+nb-1))
            cd   = mlx_from(cs%c(:, b0:b0+nb-1))
            qd   = mlx_from(cs%q(:, b0:b0+nb-1))
            call kern%apply([hk, rotd, omd, cd, qd, coef], outs, status)
            if( status /= 0 ) return
            num  = num + outs(1)
            dens = dens + outs(2)
            call mlx_eval(num, status=status)
            if( status == 0 ) call mlx_eval(dens, status=status)
            if( status /= 0 ) return
            call system_clock(t1)
            run%secs(ib) = real(t1 - t0, real64) / real(rate, real64)
        end do
        allocate(run%num(2, nvox), run%dens(nvox))
        call mlx_to(run%num, num, status=status)
        if( status == 0 ) call mlx_to(run%dens, dens, status=status)
    end subroutine insert_case

    ! the window's coefficients in single precision, (beta**2/4)**j / (j!)**2 in double precision rounded once, then
    ! 2/W and 1/W (the projector's, restated)
    function window_coefficients() result(c)
        real(real32) :: c(0:NCOEF+1)
        real(real64) :: beta, t
        real(real32) :: w
        integer      :: j
        w    = 2._real32 * KBWINSZ
        beta = PI * sqrt((real(w, real64)**2 / real(KBALPHA, real64)**2) * (real(KBALPHA, real64) - 0.5_real64)**2 - &
            &0.8_real64)
        t    = 1._real64
        do j = 0, NCOEF - 1
            c(j) = real(t, real32)
            t    = t * (beta**2 / 4._real64) / real((j + 1)**2, real64)
        end do
        c(NCOEF)   = 2._real32 / w
        c(NCOEF+1) = 1._real32 / w
    end function window_coefficients

    ! ---- the measures ------------------------------------------------------------------------------------------

    ! the numerator's and the density's largest error over the sum of |terms| of the voxel (voxels with terms)
    function errors_of( run, num, dens, scale ) result(err)
        type(probe_run), intent(in) :: run
        complex(real64), intent(in) :: num(:)
        real(real64),    intent(in) :: dens(:), scale(:)
        real(real64)                 :: err(2)
        complex(real64), allocatable :: got(:)
        logical,         allocatable :: has(:)
        got    = cmplx(real(run%num(1, :), real64), real(run%num(2, :), real64), real64)
        has    = scale > 0._real64
        err(1) = nan_maxval(merge(abs(got - num) / max(scale, tiny(1._real64)), 0._real64, has))
        has    = dens > 0._real64
        err(2) = nan_maxval(merge(abs(real(run%dens, real64) - dens) / max(dens, tiny(1._real64)), 0._real64, has))
    end function errors_of

    ! a small case: the protected kernel against the oracle and itself (three runs); the control's mass
    subroutine probe_small( cs )
        type(probe_case), intent(in) :: cs
        type(probe_run)              :: run, again, plain
        complex(real64), allocatable :: num(:)
        real(real64),    allocatable :: dens(:), scale(:)
        real(real64)                 :: errn, errd, err2(2)
        integer                      :: st, i, ndiff
        character(len=240)           :: line
        call oracle_insert(cs, num, dens, scale)
        call insert_case(cs, .true., run, st)
        call assert_true(st == 0, 'probe '//trim(cs%name)//': the atomic kernel builds and runs')
        if( st /= 0 ) return
        err2  = errors_of(run, num, dens, scale)
        errn  = err2(1)
        errd = err2(2)
        ndiff = 0
        do i = 1, 2
            call insert_case(cs, .true., again, st)
            ndiff = max(ndiff, count(.not. (bits_equal(again%dens, run%dens) .and. bits_equal(again%num(1, :), &
                &run%num(1, :)) .and. bits_equal(again%num(2, :), run%num(2, :)))))
        end do
        call insert_case(cs, .false., plain, st)
        write(line,'(a,i0,a,i0,a,es10.3,a,es10.3,a,i0,a,es10.3)') '    probe '//trim(cs%name)//': ', size(cs%omega), &
            &' planes, ', cs%ntie, ' pixels near a tie given no data; numerator error ', errn, ', density error ', &
            &errd, '; voxels differing over 2 repeats ', ndiff, '; control''s lost mass ', &
            &1._real64 - sum(real(plain%dens, real64)) / sum(dens)
        write(*,'(a)') trim(line)
        write(line,'(a,es10.3)') '    the density from single-precision coordinates in double precision (reported): '// &
            &'its error against the oracle ', coordinate_floor(cs, dens)
        write(*,'(a)') trim(line)
        call assert_true(errn <= PROBE_ERR_CAP .and. errd <= PROBE_ERR_CAP, 'probe '//trim(cs%name)// &
            &': the atomic deposits within PROBE_ERR_CAP')
    end subroutine probe_small

    ! a collision-heavy case: the errors, NREPEAT repeats against run 1, the control's lost mass, the scratch, the
    ! seconds per batch (best of NTIMED), protected and unprotected
    subroutine probe_large( cs )
        type(probe_case), intent(in) :: cs
        type(probe_run)              :: run, again, plain
        complex(real64), allocatable :: num(:)
        real(real64),    allocatable :: dens(:), scale(:)
        real(real64)                 :: errn, errd, dmax, best_a, best_p, resident, peak, d, err2(2)
        integer                      :: st, i, ndiff, nworst, nvox
        character(len=320)           :: line
        write(*,'(a)') '  probe '//trim(cs%name)
        call oracle_insert(cs, num, dens, scale)
        nvox = size(dens)
        write(line,'(a,i0,a,i0,a,i0,a,f8.2,a,i0)') '    planes ', size(cs%omega), ', disc pixels ', cs%npix, &
            &', accumulator voxels ', nvox, ', deposits per voxel touched (mean) ', &
            &27._real64 * real(count_inserted(cs), real64) / real(max(1, count(dens > 0._real64)), real64), &
            &', pixels near a tie given no data ', cs%ntie
        write(*,'(a)') trim(line)
        write(line,'(a,i0)') '    deposits ', 27_int64 * int(count_inserted(cs), int64)
        write(*,'(a)') trim(line)
        call mlx_synchronize()
        call mlx_reset_peak_memory()
        call insert_case(cs, .true., run, st)
        call assert_true(st == 0, 'probe '//trim(cs%name)//': the atomic kernel builds and runs')
        if( st /= 0 ) return
        peak = real(mlx_peak_memory(), real64)
        ! the resident arrays: the two grids (and their running sums), the pixels, one batch's planes
        resident = 3._real64 * 4._real64 * real(nvox, real64) * 2._real64 + 8._real64 * real(cs%npix, real64) + &
            &real(min(MAXIMGBATCHSZ, size(cs%omega)), real64) * (8._real64 * real(cs%npix, real64) + &
            &4._real64 * real(cs%npix, real64) + 40._real64)
        err2  = errors_of(run, num, dens, scale)
        errn  = err2(1)
        errd = err2(2)
        best_a = minval(run%secs)
        ndiff  = 0
        nworst = 0
        dmax   = 0._real64
        do i = 1, NREPEAT
            call insert_case(cs, .true., again, st)
            if( i < NTIMED ) best_a = min(best_a, minval(again%secs))
            nworst = count(.not. (bits_equal(again%dens, run%dens) .and. bits_equal(again%num(1, :), run%num(1, :)) &
                &.and. bits_equal(again%num(2, :), run%num(2, :))))
            ndiff  = max(ndiff, nworst)
            d = nan_maxval(merge(abs(real(again%dens, real64) - real(run%dens, real64)) / max(dens, tiny(1._real64)), &
                &0._real64, dens > 0._real64))
            dmax = nan_max(nan_max(dmax, d), nan_maxval(merge(abs(cmplx(real(again%num(1, :), real64), &
                &real(again%num(2, :), real64), real64) - cmplx(real(run%num(1, :), real64), real(run%num(2, :), real64), &
                &real64)) / max(scale, tiny(1._real64)), 0._real64, scale > 0._real64)))
            write(line,'(a,i0,a,i0,a,i0)') '    repeat ', i, ': voxels whose bits differ from run 1 ', nworst, ' of ', &
                &nvox
            write(*,'(a)') trim(line)
        end do
        best_p = huge(1._real64)
        do i = 1, NTIMED
            call insert_case(cs, .false., plain, st)
            best_p = min(best_p, minval(plain%secs))
        end do
        write(line,'(a,es10.3,a,es10.3,a,es10.3)') '    errors over the sum of |terms|: numerator ', errn, ', density ', &
            &errd, ' (cap ', PROBE_ERR_CAP
        write(*,'(a)') trim(line)//')'
        write(line,'(a,es10.3)') '    the density from single-precision coordinates in double precision (reported): '// &
            &'its error against the oracle ', coordinate_floor(cs, dens)
        write(*,'(a)') trim(line)
        write(line,'(a,i0,a,i0,a,es10.3)') '    over ', NREPEAT, ' repeats: at most ', ndiff, &
            &' voxels differ in their bits from run 1; largest such difference ', dmax
        write(*,'(a)') trim(line)
        write(line,'(a,es10.3,a,es10.3,a,i0,a)') '    the unprotected control loses ', &
            &1._real64 - sum(real(plain%dens, real64)) / sum(dens), ' of the density''s mass and ', &
            &1._real64 - sum(abs(cmplx(real(plain%num(1, :), real64), real(plain%num(2, :), real64), real64))) / &
            &sum(abs(num)), ' of the numerator''s moduli; voxels differing from the oracle beyond the cap: ', &
            &count(merge(abs(real(plain%dens, real64) - dens) / max(dens, tiny(1._real64)), 0._real64, &
            &dens > 0._real64) > PROBE_ERR_CAP), ''
        write(*,'(a)') trim(line)
        write(line,'(a,es11.4,a,es11.4,a,es11.4,a)') '    MLX peak ', peak, ' B, resident grids and planes ', resident, &
            &' B, scratch ', peak - resident, ' B'
        write(*,'(a)') trim(line)
        write(line,'(a,f9.4,a,f9.4,a)') '    seconds per batch of 500 planes (best of 3): protected ', best_a, &
            &', unprotected ', best_p, ''
        write(*,'(a)') trim(line)
        call assert_true(st == 0, 'probe '//trim(cs%name)//': the control ran')
    end subroutine probe_large

    ! the density with the oracle's rule in double precision, but from coordinates rounded to single precision
    ! (h R(1, a) + k R(2, a) in float32, as a float32 kernel forms them): against the oracle's density, the floor
    ! that single-precision coordinates alone set on a voxel's error (reported, not judged)
    function coordinate_floor( cs, dens ) result(err)
        type(probe_case), intent(in) :: cs
        real(real64),     intent(in) :: dens(:)
        real(real64)              :: err
        real(real64), allocatable :: ref(:)
        real(real32)              :: l32
        real(real64)              :: w(3, 3), ww
        integer                   :: tap(3, 3), p, i, a, j1, j2, j3, nh, nk, hk2, v
        nh  = cs%n / 2 + HALO_LOW + HALO + 1
        nk  = cs%n + 2 * HALO + 1
        hk2 = cs%n / 2 + HALO
        allocate(ref(size(dens)), source=0._real64)
        do p = 1, size(cs%omega)
            do i = 1, cs%npix
                if( abs(real(cs%c(i, p))) + abs(aimag(cs%c(i, p))) <= DATA_FLOOR .and. cs%q(i, p) <= DATA_FLOOR ) cycle
                do a = 1, 3
                    l32 = cs%hk(1, i) * cs%rot(1, a, p)
                    l32 = l32 + cs%hk(2, i) * cs%rot(2, a, p)
                    call oracle_proj_stencil(real(l32, real64), tap(:, a), w(:, a))
                end do
                if( all(tap(:, 1) < 0) ) cycle
                do j3 = 1, 3
                    do j2 = 1, 3
                        do j1 = 1, 3
                            ww = w(j1, 1) * w(j2, 2) * w(j3, 3)
                            v  = 1 + (tap(j1, 1) + HALO_LOW) + nh * ((tap(j2, 2) + hk2) + nk * (tap(j3, 3) + hk2))
                            ref(v) = ref(v) + ww * real(cs%omega(p), real64) * real(cs%q(i, p), real64)
                        end do
                    end do
                end do
            end do
        end do
        err = nan_maxval(merge(abs(ref - dens) / max(dens, tiny(1._real64)), 0._real64, dens > 0._real64))
    end function coordinate_floor

    ! the pixels of a case that deposit: data, and an h tap that is not negative (as the oracle decides, in double
    ! precision)
    integer function count_inserted( cs )
        type(probe_case), intent(in) :: cs
        real(real64) :: loc1
        integer      :: p, i
        count_inserted = 0
        do p = 1, size(cs%omega)
            do i = 1, cs%npix
                if( abs(real(cs%c(i, p))) + abs(aimag(cs%c(i, p))) <= DATA_FLOOR .and. cs%q(i, p) <= DATA_FLOOR ) cycle
                loc1 = real(cs%hk(1, i), real64) * real(cs%rot(1, 1, p), real64) + &
                    &real(cs%hk(2, i), real64) * real(cs%rot(2, 1, p), real64)
                if( nint(loc1) + 1 < 0 ) cycle
                count_inserted = count_inserted + 1
            end do
        end do
    end function count_inserted

end module mlxf_bench_insert_probe
