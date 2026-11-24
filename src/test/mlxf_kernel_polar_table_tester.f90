!@descr: tests of the polar table workspace: the fixture, the ring oracle, the draw, the contract, schedule identity
! The fixture is analytic in its rules and seeded in its values: references, particles and CTFs on rings of
! PFTSZ samples (half of the full ring, the other half the conjugate), memos by a double-precision DFT rounded
! once to single precision. The ring oracle computes every rotation's distance directly on the full rings, in
! double precision, with no transform; the draw is checked in double precision on the device's own rows.
module mlxf_kernel_polar_table_tester
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,                     only: mlx_set_default_device, mlx_default_device, mlx_live_count, mlx_active_memory, &
                                    mlx_synchronize, mlx_clear_cache, MLX_DEVICES
use mlxf_test_defs,           only: POLAR_DIST_MAX, POLAR_DIST_INVALID, POLAR_DIST_VALID, POLAR_FIXTURE_ERR_CPU, &
                                    POLAR_FIXTURE_ROT_CPU, POLAR_ROW_FACTOR, POLAR_FIXTURE_ROT_Q, &
                                    POLAR_SEED_CALIBRATION, POLAR_SEED_JUDGED, polar_table_refs, polar_table_block, &
                                    polar_table_entries, polar_row_check
use mlxf_kernel_polar_table,  only: polar_table
use mlxf_kernel_polar_oracle, only: polar_full_ring, polar_dft_matrix, polar_dft_bins, polar_keyed_u, polar_first_min, &
                                    polar_row_weights, polar_compare_rows, polar_draws_off, polar_report_draws
use mlxf_test_utils,          only: assert_true, assert_false, assert_int, device_name, set_fixed_seed, bits_equal, &
                                    test_devices
implicit none
private
public :: run_all_polar_table_tests

integer, parameter :: PFTSZ  = 32
integer, parameter :: NK     = 10
integer, parameter :: KFROM  = 2
integer, parameter :: NROTS  = 2 * PFTSZ
integer, parameter :: NBINS  = PFTSZ + 1
integer, parameter :: NREFS  = 8
integer, parameter :: NPTCLS = 12
! the fixture's inverse temperatures, and the level of each particle by its place in its half
real(real32), parameter :: TEMP_LEVELS(4) = [0._real32, 1._real32, 30._real32, 1.e4_real32]
integer,      parameter :: PLACE_LEVEL(6) = [1, 2, 3, 4, 3, 2]
integer,      parameter :: ALL_REFS(NREFS) = [1, 2, 3, 4, 5, 6, 7, 8]
! the particle whose signal is a thousandth of the others': every rotation of its rows is invalid
integer, parameter :: PTCL_INVALID = 5
! the particles scored from a seed bank, one per half: each is the reference translated by a 2D shift in its own
! frame, and its bank the same particle translated back, as the production calculator's shifted particle
integer, parameter :: PTCL_BANK(2) = [3, 8]
! the box of the translation phase: shell k at angle theta moves by exp(i 2 pi k (sin theta sx - cos theta sy) / BOX)
integer, parameter :: BOX = 2 * PFTSZ
! the particles whose rows straddle the invalid distance (inverse temperatures 1 and 0): banks as above, the
! particle scaled so that a rotation off the alignment sits just above the invalid distance
integer, parameter :: PTCL_MIXED(2) = [11, 2]
! the off-alignment distance the mixed particles' scale aims at, just above the invalid distance
real(real64), parameter :: MIXED_DIST = 24._real64
! the canonical tile plan of the fixture: partial tiles on both sides (8 = 3 + 3 + 2 references, 6 = 4 + 2)
integer, parameter :: RT = 3
integer, parameter :: BT = 4

! one seeded fixture: rings of the references (per half), the particles, their banks and CTFs, and the memos
type :: fixture
    integer                      :: seed = 0
    real(real32),    allocatable :: w(:,:)
    complex(real32), allocatable :: rring(:,:,:,:)
    complex(real32), allocatable :: xring(:,:,:)
    complex(real32), allocatable :: bring(:,:,:)
    real(real64),    allocatable :: shifts(:,:)
    real(real32),    allocatable :: ctf(:,:,:)
    logical,         allocatable :: l_bank(:)
    real(real32),    allocatable :: temps(:)
    real(real64),    allocatable :: wsq(:)
    complex(real32), allocatable :: ft_ref(:,:,:,:)
    complex(real32), allocatable :: ft_ref2(:,:,:,:)
    complex(real32), allocatable :: ctf2(:,:,:)
    complex(real32), allocatable :: xctf(:,:,:)
    complex(real32), allocatable :: banks(:,:,:)
end type fixture

! a scored case: one half's references ids (global, in order) and particles pids under the tile plan (rt, bt)
type :: selection
    integer              :: half     = 1
    integer, allocatable :: ids(:)
    integer, allocatable :: pids(:)
    integer              :: tiles(2) = [RT, BT]
end type selection

contains

    subroutine run_all_polar_table_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all polar_table tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        call test_oracle_self_check
        call test_bank_fixture
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            if( devs(i) == MLX_DEVICES%cpu ) call report_calibration
            call test_fixture_rows(devs(i))
            call test_fallbacks(devs(i))
            call test_convention(devs(i))
            call test_lists_and_tiles(devs(i))
            call test_refusals(devs(i))
            call test_rebuild(devs(i))
            call test_schedule_identity(devs(i))
            call test_lifecycle(devs(i))
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_polar_table_tests

    ! ---- the fixture -------------------------------------------------------------------------------------

    ! the half of a particle by its global ID: half 1 (SIMPLE's even half) holds the odd IDs, as in its benchmark
    integer function half_of( pid )
        integer, intent(in) :: pid
        half_of = 2
        if( mod(pid, 2) == 1 ) half_of = 1
    end function half_of

    ! the global IDs of the particles of one half, in order
    function half_ptcls( half ) result(pids)
        integer, intent(in) :: half
        integer, allocatable :: pids(:)
        integer              :: i
        pids = [(i, i = half, NPTCLS, 2)]
    end function half_ptcls

    function make_fixture( seed ) result(fx)
        integer, intent(in) :: seed
        type(fixture)   :: fx
        real(real32)    :: re(PFTSZ, NK), im(PFTSZ, NK), noise(PFTSZ, NK, 4), s2(NK, 2)
        complex(real64) :: z(PFTSZ), f(NROTS), ph(PFTSZ, NK)
        real(real64)    :: amp(NK), sig, pow
        integer         :: h, r, i, k, j, src, shift
        fx%seed = seed
        call set_fixed_seed(seed)
        allocate(fx%w(NK, 2), fx%rring(PFTSZ, NK, NREFS, 2), fx%xring(PFTSZ, NK, NPTCLS), &
            &fx%bring(PFTSZ, NK, NPTCLS), fx%ctf(PFTSZ, NK, NPTCLS), fx%l_bank(NPTCLS), fx%temps(NPTCLS), &
            &fx%wsq(NPTCLS), fx%shifts(2, NPTCLS))
        do k = 1, NK
            amp(k) = exp(-real(k - 1, real64) / 6._real64)
        end do
        ! shell weights k / sigma2(k, half), sigma2 in [0.5, 1.5)
        call random_number(s2)
        do h = 1, 2
            do k = 1, NK
                fx%w(k, h) = real(KFROM + k - 1, real32) / (0.5_real32 + s2(k, h))
            end do
        end do
        do h = 1, 2
            do r = 1, NREFS
                call random_number(re)
                call random_number(im)
                do k = 1, NK
                    fx%rring(:, k, r, h) = cmplx(real((2*re(:, k) - 1) * amp(k), real32), &
                        &real((2*im(:, k) - 1) * amp(k), real32), real32)
                end do
            end do
        end do
        ! particle i: its CTF times reference src of its half rotated by shift samples, plus noise; a particle
        ! with a bank is that signal translated by its 2D shift in its own frame before the noise, and its bank is
        ! the same particle translated back (shifted by -shift), which keeps its weighted power
        do i = 1, NPTCLS
            h     = half_of(i)
            src   = mod(3 * i, NREFS) + 1
            shift = mod(7 * i, NROTS)
            fx%l_bank(i)    = any(PTCL_BANK == i) .or. any(PTCL_MIXED == i)
            fx%shifts(:, i) = 0._real64
            if( fx%l_bank(i) ) fx%shifts(:, i) = [1.25_real64 + 0.5_real64 * mod(i, 3), &
                &-1.75_real64 - 0.5_real64 * mod(i, 2)]
            ph = translation_phase(fx%shifts(:, i))
            call random_number(re)
            fx%ctf(:, :, i) = real(0.2_real64 + 0.8_real64 * real(re, real64), real32)
            call random_number(noise)
            do k = 1, NK
                f = polar_full_ring(cmplx(fx%rring(:, k, src, h), kind=real64))
                do j = 1, PFTSZ
                    z(j) = real(fx%ctf(j, k, i), real64) * f(1 + mod(j - 1 - shift + 2*NROTS, NROTS))
                end do
                z = z * ph(:, k) + 0.3_real64 * amp(k) * cmplx(2*noise(:, k, 1) - 1, 2*noise(:, k, 2) - 1, real64)
                if( i == PTCL_INVALID ) z = 1.e-3_real64 * z
                fx%xring(:, k, i) = cmplx(z, kind=real32)
            end do
            if( any(PTCL_MIXED == i) )then
                ! the scale that puts the source reference's off-alignment distance at MIXED_DIST
                sig = 0._real64
                pow = 0._real64
                do k = 1, NK
                    sig = sig + real(fx%w(k, h), real64) * sum(real(fx%ctf(:, k, i), real64)**2 * &
                        &abs(cmplx(fx%rring(:, k, src, h), kind=real64))**2)
                    pow = pow + real(fx%w(k, h), real64) * sum(abs(cmplx(fx%xring(:, k, i), kind=real64))**2)
                end do
                fx%xring(:, :, i) = cmplx(sqrt(sig / ((MIXED_DIST - 1._real64) * pow)) * &
                    &cmplx(fx%xring(:, :, i), kind=real64), kind=real32)
            endif
            ! the bank: the particle (as scaled) translated back, in double precision, rounded once
            do k = 1, NK
                fx%bring(:, k, i) = cmplx(cmplx(fx%xring(:, k, i), kind=real64) * conjg(ph(:, k)), kind=real32)
            end do
            fx%temps(i)  = TEMP_LEVELS(PLACE_LEVEL((i - h) / 2 + 1))
            fx%wsq(i)    = 0._real64
            do k = 1, NK
                fx%wsq(i) = fx%wsq(i) + real(fx%w(k, h), real64) * sum(abs(cmplx(fx%xring(:, k, i), kind=real64))**2)
            end do
        end do
        call make_memos(fx)
    end function make_fixture

    ! the translation by shift (pixels) in a ring's own frame, per ring position and shell: the production
    ! calculator's shift matrix, exp(i 2 pi k (sin theta_p sx - cos theta_p sy) / BOX), theta_p = 2 pi (p-1) / NROTS
    function translation_phase( shift ) result(ph)
        real(real64), intent(in) :: shift(2)
        complex(real64) :: ph(PFTSZ, NK)
        real(real64)    :: theta, arg
        integer         :: p, k
        do k = 1, NK
            do p = 1, PFTSZ
                theta    = 2._real64 * acos(-1._real64) * real(p - 1, real64) / real(NROTS, real64)
                arg      = 2._real64 * acos(-1._real64) * real(KFROM + k - 1, real64) * &
                    &(sin(theta) * shift(1) - cos(theta) * shift(2)) / real(BOX, real64)
                ph(p, k) = cmplx(cos(arg), sin(arg), real64)
            end do
        end do
    end function translation_phase

    ! the production memos of the rings by double-precision DFTs, rounded once to single precision
    subroutine make_memos( fx )
        type(fixture), intent(inout) :: fx
        complex(real64) :: z(PFTSZ), emat(NBINS, NROTS)
        integer         :: h, r, i, k
        emat = polar_dft_matrix(NROTS, NBINS)
        allocate(fx%ft_ref(NBINS, NK, NREFS, 2), fx%ft_ref2(NBINS, NK, NREFS, 2), fx%ctf2(NBINS, NK, NPTCLS), &
            &fx%xctf(NBINS, NK, NPTCLS), fx%banks(NBINS, NK, NPTCLS))
        do h = 1, 2
            do r = 1, NREFS
                do k = 1, NK
                    z = cmplx(fx%rring(:, k, r, h), kind=real64)
                    fx%ft_ref(:, k, r, h)  = cmplx(polar_dft_bins(emat, polar_full_ring(z)), kind=real32)
                    z = cmplx(abs(z)**2, 0._real64, real64)
                    fx%ft_ref2(:, k, r, h) = cmplx(conjg(polar_dft_bins(emat, polar_full_ring(z))), kind=real32)
                end do
            end do
        end do
        do i = 1, NPTCLS
            do k = 1, NK
                z = cmplx(real(fx%ctf(:, k, i), real64)**2, 0._real64, real64)
                fx%ctf2(:, k, i)  = cmplx(polar_dft_bins(emat, polar_full_ring(z)), kind=real32)
                z = cmplx(fx%xring(:, k, i), kind=real64) * real(fx%ctf(:, k, i), real64)
                fx%xctf(:, k, i)  = cmplx(polar_dft_bins(emat, polar_full_ring(z)), kind=real32)
                z = cmplx(fx%bring(:, k, i), kind=real64) * real(fx%ctf(:, k, i), real64)
                fx%banks(:, k, i) = cmplx(polar_dft_bins(emat, polar_full_ring(z)), kind=real32)
            end do
        end do
    end subroutine make_memos

    ! the preparation of one half's references ids under the tile plan (rt, bt)
    function make_refs( fx, half, ids, tiles, generation ) result(refs)
        type(fixture),  intent(in) :: fx
        integer,        intent(in) :: half, ids(:), tiles(2)
        integer(int64), intent(in) :: generation
        type(polar_table_refs) :: refs
        refs%pftsz      = PFTSZ
        refs%nk         = NK
        refs%half       = half
        refs%rt         = tiles(1)
        refs%bt         = tiles(2)
        refs%generation = generation
        refs%ids        = ids
        refs%ft_ref     = fx%ft_ref(:, :, ids, half)
        refs%ft_ref2    = fx%ft_ref2(:, :, ids, half)
    end function make_refs

    ! the block of particles pids of one half against the references ids, its variates keyed by global IDs
    function make_block( fx, half, ids, pids, generation ) result(blk)
        type(fixture),  intent(in) :: fx
        integer,        intent(in) :: half, ids(:), pids(:)
        integer(int64), intent(in) :: generation
        type(polar_table_block) :: blk
        integer                 :: r, b
        blk%half       = half
        blk%generation = generation
        blk%ref_ids    = ids
        blk%ptcl_ids   = pids
        blk%weights    = fx%w(:, half)
        blk%ctf2       = fx%ctf2(:, :, pids)
        blk%xctf       = fx%xctf(:, :, pids)
        blk%banks      = fx%banks(:, :, pids)
        blk%l_bank     = fx%l_bank(pids)
        blk%wsq        = fx%wsq(pids)
        blk%temps      = fx%temps(pids)
        allocate(blk%u(size(ids), size(pids)))
        do b = 1, size(pids)
            do r = 1, size(ids)
                blk%u(r, b) = real(polar_keyed_u(fx%seed, pids(b), ids(r)), real32)
            end do
        end do
        blk%rows = .true.
    end function make_block

    ! ---- the ring oracle ---------------------------------------------------------------------------------

    ! every rotation's distance of every pair, directly on the full rings in double precision:
    ! d(r) = 1 + sum_k w_k sum_m [C_m^2 |R_(m-r+1)|^2 - 2 Re(X_m C_m conj(R_(m-r+1)))] / (2 wsq), the
    ! particle's own wsq also where its bank X replaces it; above POLAR_DIST_MAX the invalid marker
    function oracle_rows( fx, half, ids, pids ) result(d)
        type(fixture), intent(in) :: fx
        integer,       intent(in) :: half, ids(:), pids(:)
        real(real64), allocatable :: d(:,:,:)
        complex(real64)           :: rr(NROTS), xx(NROTS)
        real(real64)              :: cc(NROTS), acc
        integer                   :: b, ir, i, k, rot, m, mm
        allocate(d(NROTS, size(ids), size(pids)))
        do b = 1, size(pids)
            i = pids(b)
            do ir = 1, size(ids)
                do rot = 1, NROTS
                    acc = 0._real64
                    do k = 1, NK
                        rr = polar_full_ring(cmplx(fx%rring(:, k, ids(ir), half), kind=real64))
                        if( fx%l_bank(i) )then
                            xx = polar_full_ring(cmplx(fx%bring(:, k, i), kind=real64))
                        else
                            xx = polar_full_ring(cmplx(fx%xring(:, k, i), kind=real64))
                        endif
                        cc(1:PFTSZ)       = real(fx%ctf(:, k, i), real64)
                        cc(PFTSZ+1:NROTS) = cc(1:PFTSZ)
                        do m = 1, NROTS
                            mm  = 1 + mod(m - rot + NROTS, NROTS)
                            acc = acc + real(fx%w(k, half), real64) * (cc(m)**2 * abs(rr(mm))**2 - &
                                &2._real64 * real(xx(m) * cc(m) * conjg(rr(mm)), real64))
                        end do
                    end do
                    d(rot, ir, b) = 1._real64 + acc / (2._real64 * fx%wsq(i))
                    if( d(rot, ir, b) > POLAR_DIST_MAX ) d(rot, ir, b) = real(POLAR_DIST_INVALID, real64)
                end do
            end do
        end do
    end function oracle_rows

    ! the oracle's two forms agree: for a particle without a bank, the expanded sums equal
    ! sum_k w_k sum_m |X_m - C_m R_(m-r+1)|^2 / (2 wsq), the distance's definition
    subroutine test_oracle_self_check
        type(fixture)             :: fx
        real(real64), allocatable :: d(:,:,:)
        complex(real64)           :: rr(NROTS), xx(NROTS)
        real(real64)              :: cc(NROTS), acc, worst
        integer                   :: pid, half, rot, k, m, mm
        write(*,'(a)') 'test_oracle_self_check'
        fx    = make_fixture(POLAR_SEED_CALIBRATION)
        pid   = 4
        half  = half_of(pid)
        d     = oracle_rows(fx, half, [1, 4], [pid])
        worst = 0._real64
        do rot = 1, NROTS
            acc = 0._real64
            do k = 1, NK
                rr = polar_full_ring(cmplx(fx%rring(:, k, 4, half), kind=real64))
                xx = polar_full_ring(cmplx(fx%xring(:, k, pid), kind=real64))
                cc(1:PFTSZ)       = real(fx%ctf(:, k, pid), real64)
                cc(PFTSZ+1:NROTS) = cc(1:PFTSZ)
                do m = 1, NROTS
                    mm  = 1 + mod(m - rot + NROTS, NROTS)
                    acc = acc + real(fx%w(k, half), real64) * abs(xx(m) - cc(m) * rr(mm))**2
                end do
            end do
            worst = max(worst, abs(acc / (2._real64 * fx%wsq(pid)) - d(rot, 2, 1)))
        end do
        call assert_true(worst <= 1.e-12_real64 * maxval(abs(d(:, 2, 1))), 'the ring oracle''s expanded sums '//&
            &'equal the squared distance of particle and rotated reference over twice the weighted square sum')
        call assert_true(minloc(d(:, 1, 1), dim=1) /= minloc(d(:, 2, 1), dim=1) .or. &
            &abs(d(1, 1, 1) - d(1, 2, 1)) > 0._real64, 'the oracle''s rows differ between references')
    end subroutine test_oracle_self_check

    ! the banks are their particles translated back, as the production calculator's shifted particle: a bank
    ! keeps its particle's weighted power, and against its source reference its row is least at the known
    ! rotation and lower there than the translated particle's own row anywhere (a reversed shift sign or a wrong
    ! frame would translate it further instead of back)
    subroutine test_bank_fixture
        type(fixture)             :: fx, fo
        real(real64), allocatable :: db(:,:,:), dp(:,:,:)
        real(real64)              :: pow, worst_pow
        integer                   :: n, i, h, src, shift, k, nmin, nlow
        write(*,'(a)') 'test_bank_fixture'
        fx        = make_fixture(POLAR_SEED_CALIBRATION)
        fo        = fx
        fo%l_bank = .false.
        worst_pow = 0._real64
        nmin      = 0
        nlow      = 0
        do n = 1, size(PTCL_BANK)
            i     = PTCL_BANK(n)
            h     = half_of(i)
            src   = mod(3 * i, NREFS) + 1
            shift = mod(7 * i, NROTS)
            call assert_true(all(abs(fx%shifts(:, i)) > 0.5_real64), 'a bank''s shift has two components of at least '//&
                &'half a pixel')
            pow = 0._real64
            do k = 1, NK
                pow = pow + real(fx%w(k, h), real64) * sum(abs(cmplx(fx%bring(:, k, i), kind=real64))**2)
            end do
            worst_pow = max(worst_pow, abs(pow - fx%wsq(i)) / fx%wsq(i))
            db = oracle_rows(fx, h, [src], [i])
            dp = oracle_rows(fo, h, [src], [i])
            if( minloc(db(:, 1, 1), dim=1) == shift + 1 ) nmin = nmin + 1
            if( db(shift + 1, 1, 1) < minval(dp(:, 1, 1)) ) nlow = nlow + 1
        end do
        write(*,'(a,es10.3)') '    banks: largest relative difference of weighted power from the particle''s ', worst_pow
        call assert_true(worst_pow <= 1.e-6_real64, 'a bank keeps its particle''s weighted power (to single-precision '//&
            &'rounding)')
        call assert_int(size(PTCL_BANK), nmin, 'every bank''s row against its source reference is least at the '//&
            &'known rotation')
        call assert_int(size(PTCL_BANK), nlow, 'every bank aligns better than its translated particle does')
    end subroutine test_bank_fixture

    ! ---- comparisons -------------------------------------------------------------------------------------

    ! ---- scoring a case ----------------------------------------------------------------------------------

    ! one workspace: the half's references sel%ids prepared, the particles sel%pids scored synchronously
    subroutine score_case( fx, sel, blk, ent )
        type(fixture),             intent(in)  :: fx
        type(selection),           intent(in)  :: sel
        type(polar_table_block),   intent(out) :: blk
        type(polar_table_entries), intent(out) :: ent
        type(polar_table) :: ws
        integer           :: st
        call ws%new(make_refs(fx, sel%half, sel%ids, sel%tiles, 1_int64), st)
        call assert_int(0, st, 'the references are prepared: '//ws%message())
        blk = make_block(fx, sel%half, sel%ids, sel%pids, 1_int64)
        call ws%score(blk, ent, st)
        call assert_int(0, st, 'the block is scored: '//ws%message())
        call ws%kill()
    end subroutine score_case

    function selection_of( half, ids, pids, tiles ) result(sel)
        integer, intent(in) :: half, ids(:), pids(:), tiles(2)
        type(selection) :: sel
        sel%half  = half
        sel%ids   = ids
        sel%pids  = pids
        sel%tiles = tiles
    end function selection_of

    ! a case scored and held to the oracle: the validity of every entry, the draw on the device's rows; with
    ! gated, the fixture's frozen row bounds. Returns the comparison for the calibration's totals.
    function judge( label, fx, sel, gated ) result(chk)
        character(len=*), intent(in) :: label
        type(fixture),    intent(in) :: fx
        type(selection),  intent(in) :: sel
        logical,          intent(in) :: gated
        type(polar_row_check)     :: chk
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: ent
        real(real64), allocatable :: dor(:,:,:)
        call score_case(fx, sel, blk, ent)
        if( .not. allocated(ent%rows) ) return
        dor = oracle_rows(fx, sel%half, sel%ids, sel%pids)
        chk = polar_compare_rows(dor, ent)
        chk%draws_bad = polar_draws_off(ent, blk%temps, blk%u)
        call assert_int(0, chk%valid_off, label//': every entry is valid or invalid as in the ring oracle')
        call assert_int(0, chk%draws_bad, label//': u W lies in the drawn rotation''s cumulative interval of the '//&
            &'device''s row within 1e-4 W (or the fallback holds), and the entry''s distance is the row''s')
        if( .not. gated ) return
        write(*,'(a,es10.3,a,i0,a,i0,a)') '    '//label//': row error ', chk%err, ', minimising rotation differs in ', &
            &chk%argmin_off, ' of ', chk%npairs, ' pairs'
        call assert_within_fixture_bounds(label, chk)
        call polar_report_draws(label, fx%seed, dor, ent, blk)
    end function judge

    ! the fixture's frozen gates: row error at most POLAR_ROW_FACTOR e_cpu, minimising-rotation disagreements at
    ! most max(POLAR_ROW_FACTOR n_cpu, q)
    subroutine assert_within_fixture_bounds( label, chk )
        character(len=*),      intent(in) :: label
        type(polar_row_check), intent(in) :: chk
        call assert_true(chk%err <= POLAR_ROW_FACTOR * POLAR_FIXTURE_ERR_CPU, label//': the rows'' error is within '//&
            &'twice the CPU calibration''s e_cpu')
        call assert_true(chk%argmin_off <= max(nint(POLAR_ROW_FACTOR) * POLAR_FIXTURE_ROT_CPU, POLAR_FIXTURE_ROT_Q), &
            &label//': the minimising rotation differs from the oracle''s in at most max(2 n_cpu, 1) pairs')
    end subroutine assert_within_fixture_bounds

    ! ---- the tests -----------------------------------------------------------------------------------------

    ! the fixture's calibration on the CPU device, fixture seed 1, both halves, all references: reported
    subroutine report_calibration
        type(fixture)         :: fx
        type(polar_row_check) :: chk(2)
        integer               :: h
        write(*,'(a)') 'report_calibration'
        fx = make_fixture(POLAR_SEED_CALIBRATION)
        do h = 1, 2
            chk(h) = judge('calibration', fx, selection_of(h, ALL_REFS, half_ptcls(h), [RT, BT]), .false.)
        end do
        write(*,'(a,es23.16,a,i0,a,i0,a,i0,a,i0,a)') '    calibration (fixture seed 1, cpu): e_cpu = ', &
            &maxval(chk%err), ', n_cpu = ', sum(chk%argmin_off), ' of ', sum(chk%npairs), ' pairs (', sum(chk%mixed), &
            &' of mixed validity, ', sum(chk%invalid), ' invalid)'
    end subroutine report_calibration

    ! fixture seed 2, both halves, all references, the canonical tile plan: the oracle rows and the draw
    subroutine test_fixture_rows( dev )
        integer, intent(in) :: dev
        type(fixture)         :: fx
        type(polar_row_check) :: chk(2)
        integer               :: h
        write(*,'(a)') 'test_fixture_rows'
        fx = make_fixture(POLAR_SEED_JUDGED)
        do h = 1, 2
            chk(h) = judge(device_name(dev)//' fixture', fx, selection_of(h, ALL_REFS, half_ptcls(h), [RT, BT]), &
                &.true.)
        end do
        write(*,'(a,es10.3,a,i0,a,i0,a)') '    seed 2: row error ', maxval(chk%err), ', minimising rotation '//&
            &'differs in ', sum(chk%argmin_off), ' of ', sum(chk%npairs), ' pairs'
        call assert_int(NREFS*NPTCLS, sum(chk%npairs), 'the fixture scores 8 references and 6 particles per half')
        call assert_true(sum(chk%mixed) >= 2, 'the fixture has rows of mixed validity (the mixed particles)')
        call assert_true(sum(chk%invalid) >= NREFS, 'the fixture has rows without a valid rotation')
    end subroutine test_fixture_rows

    ! the draw's fallbacks: u = 0 draws the first rotation of positive weight, u >= 1 (no rotation reaches it)
    ! the minimising rotation, a row without a valid rotation gives (invalid, 1); and the cutoff: a rotation
    ! whose weight argument is 82 has no weight, so u = 0 skips it even where it comes first
    subroutine test_fallbacks( dev )
        integer, intent(in) :: dev
        type(fixture)             :: fx
        type(polar_table)         :: ws
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: ent
        real(real64)              :: w(NROTS), row(NROTS), d2
        integer                   :: st, ir, b, nfirst, nmin, ninv, nrows_valid, m, imin, i2, pick_r, pick_b
        write(*,'(a)') 'test_fallbacks'
        fx = make_fixture(POLAR_SEED_JUDGED)
        call ws%new(make_refs(fx, 1, ALL_REFS, [RT, BT], 1_int64), st)
        call assert_int(0, st, 'the references are prepared')
        blk   = make_block(fx, 1, ALL_REFS, half_ptcls(1), 1_int64)
        blk%u = 0._real32
        call ws%score(blk, ent, st)
        call assert_int(0, st, 'u = 0 is scored')
        if( st /= 0 ) return
        nfirst      = 0
        ninv        = 0
        nrows_valid = 0
        do b = 1, size(ent%irots, 2)
            do ir = 1, size(ent%irots, 1)
                row = real(ent%rows(:, ir, b), real64)
                if( polar_first_min(row) == 0 )then
                    if( ent%irots(ir, b) == 1 .and. bits_equal(ent%dists(ir, b), POLAR_DIST_INVALID) ) &
                        &ninv = ninv + 1
                    cycle
                endif
                nrows_valid = nrows_valid + 1
                call polar_row_weights(row, blk%temps(b), w)
                m = findloc(w > 0._real64, .true., dim=1)
                if( ent%irots(ir, b) == m ) nfirst = nfirst + 1
            end do
        end do
        call assert_int(NREFS*6 - nrows_valid, ninv, device_name(dev)//': a row without a valid rotation gives '//&
            &'(invalid, 1)')
        call assert_true(ninv >= NREFS, 'the invalid particle''s rows have no valid rotation')
        call assert_int(nrows_valid, nfirst, device_name(dev)//': u = 0 draws the first rotation of positive weight')
        blk%u = 1.5_real32
        call ws%score(blk, ent, st)
        call assert_int(0, st, 'u = 1.5 is scored')
        if( st /= 0 ) return
        nmin = 0
        do b = 1, size(ent%irots, 2)
            do ir = 1, size(ent%irots, 1)
                row = real(ent%rows(:, ir, b), real64)
                if( polar_first_min(row) == 0 ) cycle
                if( ent%irots(ir, b) == polar_first_min(row) ) nmin = nmin + 1
            end do
        end do
        call assert_int(nrows_valid, nmin, device_name(dev)//': when no rotation reaches u W the draw falls back '//&
            &'to the first minimising rotation')
        ! the cutoff: a pair whose second-lowest distance comes before its minimum; its particle's temperature
        ! puts that rotation's argument at 82, so with u = 0 the minimum, not the earlier rotation, is drawn
        pick_r = 0
        pick_b = 0
        do b = 1, size(ent%irots, 2)
            do ir = 1, size(ent%irots, 1)
                row  = real(ent%rows(:, ir, b), real64)
                imin = polar_first_min(row)
                if( imin <= 1 .or. pick_r > 0 ) cycle
                if( count(row < real(POLAR_DIST_VALID, real64)) < NROTS ) cycle
                i2 = minloc(row, dim=1, mask=[(m /= imin, m = 1, NROTS)])
                d2 = row(i2)
                if( i2 < imin .and. d2 - row(imin) > 1.e-3_real64 )then
                    pick_r = ir
                    pick_b = b
                endif
            end do
        end do
        call assert_true(pick_r > 0, 'the fixture has a row whose second-lowest distance comes first')
        if( pick_r == 0 ) return
        row = real(ent%rows(:, pick_r, pick_b), real64)
        imin = polar_first_min(row)
        d2   = minval(row, mask=[(m /= imin, m = 1, NROTS)])
        blk%temps(pick_b) = real(82._real64 / (d2 - row(imin)), real32)
        blk%u = 0._real32
        call ws%score(blk, ent, st)
        call assert_int(0, st, 'the cutoff case is scored')
        if( st /= 0 ) return
        call assert_int(imin, ent%irots(pick_r, pick_b), device_name(dev)//': a rotation whose weight argument '//&
            &'reaches the cutoff (82 >= 80) has no weight: u = 0 draws the minimum, not the earlier rotation')
        call ws%kill()
    end subroutine test_fallbacks

    ! the rotation convention against the construction: an ordinary particle built from reference src rotated
    ! by shift samples has its minimising rotation against src at shift + 1, on the device's rows
    subroutine test_convention( dev )
        integer, intent(in) :: dev
        type(fixture)             :: fx
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: ent
        integer                   :: h, b, pid, nok, nchecked
        integer, allocatable      :: pids(:)
        write(*,'(a)') 'test_convention'
        fx       = make_fixture(POLAR_SEED_JUDGED)
        nok      = 0
        nchecked = 0
        do h = 1, 2
            pids = half_ptcls(h)
            call score_case(fx, selection_of(h, ALL_REFS, pids, [RT, BT]), blk, ent)
            if( .not. allocated(ent%rows) ) return
            do b = 1, size(pids)
                pid = pids(b)
                if( fx%l_bank(pid) .or. pid == PTCL_INVALID ) cycle
                nchecked = nchecked + 1
                if( polar_first_min(real(ent%rows(:, mod(3*pid, NREFS) + 1, b), real64)) == mod(7*pid, NROTS) + 1 ) &
                    &nok = nok + 1
            end do
        end do
        call assert_int(7, nchecked, 'seven ordinary particles are checked')
        call assert_int(nchecked, nok, device_name(dev)//': a particle built from its reference rotated by shift '//&
            &'samples has its minimum at rotation shift + 1')
    end subroutine test_convention

    ! ordered reference lists with global IDs: one state's references (1..4), the shared representatives
    ! [7, 2, 5] in that order, and full tiles (rt 8, bt 6) instead of partial ones: each held to the oracle
    subroutine test_lists_and_tiles( dev )
        integer, intent(in) :: dev
        type(fixture)         :: fx
        type(polar_row_check) :: chk
        write(*,'(a)') 'test_lists_and_tiles'
        fx  = make_fixture(POLAR_SEED_JUDGED)
        chk = judge(device_name(dev)//' one state', fx, selection_of(2, [1, 2, 3, 4], half_ptcls(2), [RT, BT]), &
            &.true.)
        call assert_int(4*6, chk%npairs, 'one state''s four references score 24 pairs')
        chk = judge(device_name(dev)//' representatives', fx, selection_of(1, [7, 2, 5], half_ptcls(1), [RT, BT]), &
            &.true.)
        call assert_int(3*6, chk%npairs, 'three listed representatives score 18 pairs')
        chk = judge(device_name(dev)//' full tiles', fx, selection_of(2, ALL_REFS, half_ptcls(2), [NREFS, 6]), &
            &.true.)
        call assert_int(NREFS*6, chk%npairs, 'full tiles score 48 pairs')
    end subroutine test_lists_and_tiles

    ! mismatches are refused before scoring, and a refused block queues nothing
    subroutine test_refusals( dev )
        integer, intent(in) :: dev
        type(fixture)             :: fx
        type(polar_table)         :: ws
        type(polar_table_block)   :: blk, bad
        type(polar_table_entries) :: ent
        integer                   :: st, live0
        write(*,'(a)') 'test_refusals'
        fx  = make_fixture(POLAR_SEED_JUDGED)
        blk = make_block(fx, 1, ALL_REFS, half_ptcls(1), 7_int64)
        call ws%score(blk, ent, st)
        call assert_true(st /= 0, device_name(dev)//': a workspace without references refuses a block')
        call ws%new(make_refs(fx, 1, ALL_REFS, [RT, BT], 7_int64), st)
        live0 = mlx_live_count()
        bad   = blk
        bad%generation = 8_int64
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'generation') > 0, device_name(dev)//': a block of '//&
            &'another reference generation is refused')
        bad      = make_block(fx, 2, ALL_REFS, half_ptcls(2), 7_int64)
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'half') > 0, device_name(dev)//': a block of the '//&
            &'other half is refused')
        bad      = blk
        bad%ctf2 = blk%ctf2(:, 1:NK-1, :)
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'shapes') > 0, device_name(dev)//': a block of '//&
            &'another shape is refused')
        bad         = blk
        bad%ref_ids = [2, 1, 3, 4, 5, 6, 7, 8]
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'list') > 0, device_name(dev)//': a block naming '//&
            &'the references in another order is refused')
        bad         = blk
        bad%ref_ids = [1, 2, 3]
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'list') > 0, device_name(dev)//': a block naming '//&
            &'another list of references is refused')
        bad = blk
        deallocate(bad%l_bank)
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'banks') > 0, device_name(dev)//': banks without '//&
            &'their flags are refused')
        bad        = blk
        bad%wsq(2) = 0._real64
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'square sum') > 0, device_name(dev)//': a particle '//&
            &'without a positive weighted square sum is refused')
        bad             = blk
        bad%ptcl_ids(1) = 0
        call ws%score(bad, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'particle IDs') > 0, device_name(dev)//': particle '//&
            &'IDs that are not global and positive are refused')
        call ws%submit(blk, 3, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'slot') > 0, device_name(dev)//': a slot outside 1..2 '//&
            &'is refused')
        call ws%collect(0, ent, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'slot') > 0, device_name(dev)//': collecting a slot '//&
            &'outside 1..2 is refused')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': refused blocks queue no array')
        call ws%submit(blk, 1, st)
        call assert_int(0, st, 'a matching block is queued')
        call ws%submit(blk, 1, st)
        call assert_true(st /= 0, device_name(dev)//': a busy slot refuses a second block')
        call ws%collect(1, ent, st)
        call assert_int(0, st, 'the queued block is collected')
        call ws%collect(1, ent, st)
        call assert_true(st /= 0, device_name(dev)//': an empty slot has nothing to collect')
        call ws%kill()
    end subroutine test_refusals

    ! references that change are invalidated and prepared again: the old generation is refused, the new one
    ! matches the oracle of the new references and differs from the old entries
    subroutine test_rebuild( dev )
        integer, intent(in) :: dev
        type(fixture)             :: fa, fb
        type(polar_table)         :: ws
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: ea, eb
        real(real64), allocatable :: dor(:,:,:)
        type(polar_row_check)     :: chk
        integer                   :: st
        write(*,'(a)') 'test_rebuild'
        fa  = make_fixture(POLAR_SEED_JUDGED)
        fb  = make_fixture(POLAR_SEED_JUDGED + 10)
        call ws%new(make_refs(fa, 2, ALL_REFS, [RT, BT], 1_int64), st)
        call assert_int(0, st, 'the first references are prepared')
        blk = make_block(fa, 2, ALL_REFS, half_ptcls(2), 1_int64)
        call ws%score(blk, ea, st)
        call assert_int(0, st, 'the first generation is scored')
        if( st /= 0 ) return
        call ws%invalidate()
        call assert_false(ws%prepared_now(), device_name(dev)//': an invalidated workspace holds no references')
        call ws%score(blk, eb, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'no prepared') > 0, device_name(dev)//': after '//&
            &'invalidation a block is refused')
        ! the particles stay; the references change (fixture B's) under generation 2
        call ws%new(make_refs(fb, 2, ALL_REFS, [RT, BT], 2_int64), st)
        call assert_int(0, st, 'the changed references are prepared')
        call ws%score(blk, eb, st)
        call assert_true(st /= 0 .and. index(ws%message(), 'generation') > 0, device_name(dev)//': a block of '//&
            &'the old generation is refused by the rebuilt references')
        blk%generation = 2_int64
        call ws%score(blk, eb, st)
        call assert_int(0, st, 'the new generation is scored')
        if( st /= 0 ) return
        fb%xring = fa%xring
        fb%bring = fa%bring
        fb%ctf   = fa%ctf
        fb%wsq   = fa%wsq
        fb%w(:, 2) = fa%w(:, 2)
        dor = oracle_rows(fb, 2, ALL_REFS, half_ptcls(2))
        chk = polar_compare_rows(dor, eb)
        call assert_int(0, chk%valid_off, device_name(dev)//': the rebuilt entries'' validity matches the new oracle')
        call assert_within_fixture_bounds(device_name(dev)//' rebuilt', chk)
        call assert_true(any(.not. bits_equal(ea%rows, eb%rows)), device_name(dev)//': the rebuilt rows differ '//&
            &'from the old ones')
        call ws%kill()
    end subroutine test_rebuild

    ! with inputs, variates and the canonical tile plan fixed, entries are identical by global pair in three
    ! repeats, for outer batches of 6 and of 4 (then 2) particles, and synchronous against two slots
    subroutine test_schedule_identity( dev )
        integer, intent(in) :: dev
        type(fixture)             :: fx
        type(polar_table)         :: ws
        type(polar_table_block)   :: blk, b1, b2
        type(polar_table_entries) :: e0, e, e1, e2
        integer                   :: h, rep, st, nbad, pids(6)
        logical                   :: same
        write(*,'(a)') 'test_schedule_identity'
        fx = make_fixture(POLAR_SEED_JUDGED)
        do h = 1, 2
            pids = half_ptcls(h)
            nbad = 0
            call ws%new(make_refs(fx, h, ALL_REFS, [RT, BT], 1_int64), st)
            nbad = nbad + merge(1, 0, st /= 0)
            blk      = make_block(fx, h, ALL_REFS, pids, 1_int64)
            blk%rows = .false.
            call ws%score(blk, e0, st)
            nbad = nbad + merge(1, 0, st /= 0)
            same = nbad == 0
            do rep = 1, 3
                call ws%score(blk, e, st)
                if( st /= 0 .or. .not. same )then
                    same = .false.
                    cycle
                endif
                same = all(bits_equal(e%dists, e0%dists)) .and. all(e%irots == e0%irots)
            end do
            call assert_true(same, device_name(dev)//': three repeats give identical entries')
            b1      = make_block(fx, h, ALL_REFS, pids(1:4), 1_int64)
            b2      = make_block(fx, h, ALL_REFS, pids(5:6), 1_int64)
            b1%rows = .false.
            b2%rows = .false.
            call ws%score(b1, e1, st)
            nbad = nbad + merge(1, 0, st /= 0)
            call ws%score(b2, e2, st)
            nbad = nbad + merge(1, 0, st /= 0)
            call assert_int(0, nbad, device_name(dev)//': the identity runs are scored')
            if( nbad /= 0 ) return
            call assert_true(same_entries(e1, e2, e0), device_name(dev)//': outer batches of 6 and of 4 give '//&
                &'identical entries by global pair')
            call ws%submit(b1, 1, st)
            nbad = nbad + merge(1, 0, st /= 0)
            call ws%submit(b2, 2, st)
            nbad = nbad + merge(1, 0, st /= 0)
            call ws%collect(1, e1, st)
            nbad = nbad + merge(1, 0, st /= 0)
            call ws%collect(2, e2, st)
            nbad = nbad + merge(1, 0, st /= 0)
            call assert_int(0, nbad, device_name(dev)//': both slots are submitted and collected')
            if( nbad /= 0 ) return
            call assert_true(same_entries(e1, e2, e0), device_name(dev)//': two slots in flight give the '//&
                &'synchronous entries')
            call ws%kill()
        end do
    end subroutine test_schedule_identity

    ! the entries of particles 1..4 (e1) and 5..6 (e2) equal those of the whole block (e0), bit for bit
    logical function same_entries( e1, e2, e0 )
        type(polar_table_entries), intent(in) :: e1, e2, e0
        same_entries = all(bits_equal(e1%dists, e0%dists(:, 1:4)))
        if( same_entries ) same_entries = all(e1%irots == e0%irots(:, 1:4))
        if( same_entries ) same_entries = all(bits_equal(e2%dists, e0%dists(:, 5:6)))
        if( same_entries ) same_entries = all(e2%irots == e0%irots(:, 5:6))
    end function same_entries

    ! after a warm cycle, create/use/kill cycles and a workspace left to finalization return the live count and
    ! the active memory to their warm values; kill twice is harmless
    subroutine test_lifecycle( dev )
        integer, intent(in) :: dev
        type(fixture)  :: fx
        integer(int64) :: mem0
        integer        :: live0, it, nbad
        write(*,'(a)') 'test_lifecycle'
        fx   = make_fixture(POLAR_SEED_JUDGED)
        nbad = 0
        call lifecycle_cycle(fx, .true., nbad)
        call mlx_synchronize()
        call mlx_clear_cache()
        mem0  = mlx_active_memory()
        live0 = mlx_live_count()
        do it = 1, 3
            call lifecycle_cycle(fx, .true., nbad)
        end do
        call lifecycle_cycle(fx, .false., nbad)
        call mlx_synchronize()
        call mlx_clear_cache()
        call assert_int(0, nbad, device_name(dev)//': every cycle prepares, submits and collects')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': the live count returns to its warm value')
        call assert_true(mlx_active_memory() == mem0, device_name(dev)//': the active memory returns to its warm '//&
            &'value')
    end subroutine test_lifecycle

    ! one workspace: prepared, a block queued in each slot and collected; killed twice, or left to finalization;
    ! nbad counts the calls that failed
    subroutine lifecycle_cycle( fx, l_kill, nbad )
        type(fixture), intent(in)    :: fx
        logical,       intent(in)    :: l_kill
        integer,       intent(inout) :: nbad
        type(polar_table)         :: ws
        type(polar_table_block)   :: blk
        type(polar_table_entries) :: e
        integer                   :: st
        call ws%new(make_refs(fx, 1, ALL_REFS, [RT, BT], 1_int64), st)
        nbad = nbad + merge(1, 0, st /= 0)
        blk = make_block(fx, 1, ALL_REFS, half_ptcls(1), 1_int64)
        call ws%submit(blk, 1, st)
        nbad = nbad + merge(1, 0, st /= 0)
        call ws%submit(blk, 2, st)
        nbad = nbad + merge(1, 0, st /= 0)
        call ws%collect(2, e, st)
        nbad = nbad + merge(1, 0, st /= 0 .or. .not. allocated(e%dists))
        call ws%collect(1, e, st)
        nbad = nbad + merge(1, 0, st /= 0 .or. .not. allocated(e%dists))
        if( l_kill )then
            call ws%kill()
            call ws%kill()
        endif
    end subroutine lifecycle_cycle

end module mlxf_kernel_polar_table_tester
