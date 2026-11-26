!@descr: tests of the polar calculator's fused tail: the refusal on the CPU device, the two kernels' identity, repeatability, small tiles, objects
! The data are seeded rings handed to the calculator through its setters, with one particle whose rows have no
! valid rotation. The fused form is held to itself (repeatability, its two kernels), to its own rows (the draw)
! and to the compiled form on the same rows; its agreement with the oracle and with the compiled form on the
! dense fixture is the calculator's suite, which runs its GPU checks with both forms.
module mlxf_toy_polarft_tail_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,                  only: mlx_set_default_device, mlx_default_device, mlx_live_count, MLX_DEVICES
use mlxf_test_defs,        only: POLARFT_TAILS, POLARFT_TAIL_ROT_FIX, parameters, polar_table_entries
use mlxf_toy_polarft_calc, only: polarft_calc
use mlxf_toy_eul_prob_tab, only: eul_prob_tab
use mlxf_oracle_polar,     only: polar_keyed_u, polar_draws_off
use mlxf_test_utils,       only: assert_true, assert_int, device_name, bits_equal, set_fixed_seed, test_devices
implicit none
private
public :: run_all_polarft_tail_tests

integer, parameter :: PFTSZ  = 32
integer, parameter :: NROTS  = 2 * PFTSZ
integer, parameter :: NK     = 10
integer, parameter :: NREF   = 8
integer, parameter :: NPTCL  = 12
integer, parameter :: SEED   = 11
! the canonical tile plan of the data: partial tiles on both sides
integer, parameter :: RT = 3
integer, parameter :: BT = 4
! the particle whose signal is a thousandth of the others': its rows have no valid rotation
integer, parameter :: PTCL_INVALID = 3
! the inverse temperatures, in turn
real(real32), parameter :: TEMP_LEVELS(4) = [0._real32, 1._real32, 30._real32, 1.e4_real32]
! the live handles a workspace adds when its reference bins are made with the compiled tail (the tiles and the
! compiled function), and what the fused tail adds to that (its constants; the kernel replaces the function)
integer, parameter :: LIVE_PER_WORKSPACE = 2
integer, parameter :: LIVE_FUSED_EXTRA   = 1

! seeded data: the references' rings per half, the particles' rings and CTFs, the shell weights per half, the
! inverse temperatures
type :: tail_data
    complex(real32) :: rring(PFTSZ, NK, NREF, 2)
    complex(real32) :: xring(PFTSZ, NK, NPTCL)
    real(real32)    :: ctf(PFTSZ, NK, NPTCL)
    real(real64)    :: w(NK, 2)
    real(real32)    :: temps(NPTCL)
end type tail_data

! a filled range: the entries (references, particles in the batch's order) and that order
type :: tail_fill
    real(real32), allocatable :: d(:,:)
    integer,      allocatable :: ir(:,:)
    integer,      allocatable :: o(:)
end type tail_fill

contains

    subroutine run_all_polarft_tail_tests
        integer, allocatable :: devs(:)
        type(tail_data)      :: dat
        integer              :: i, original
        write(*,'(a)') '**** running all polarft_tail tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        dat      = make_data()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            if( devs(i) == MLX_DEVICES%cpu )then
                call test_cpu_refusal(dat)
            else
                call test_kernel_identity(dat)
                call test_repeatability(dat)
                call test_small_plans(dat)
                call test_objects(dat)
            endif
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_polarft_tail_tests

    ! ---- the data --------------------------------------------------------------------------------------------

    ! the half of a particle: half 1 holds the odd indices
    pure integer function half_of( i )
        integer, intent(in) :: i
        half_of = 2 - mod(i, 2)
    end function half_of

    function half_ptcls( half ) result(pids)
        integer, intent(in) :: half
        integer, allocatable :: pids(:)
        integer              :: i
        pids = [(i, i = half, NPTCL, 2)]
    end function half_ptcls

    ! references uniform in the unit square per shell, scaled down by shell; particles: their half's reference
    ! 1 + mod(i, NREF) times a CTF in [0.2, 1), plus noise of a third of the signal
    function make_data() result(dat)
        type(tail_data) :: dat
        real(real32)    :: re(PFTSZ, NK), im(PFTSZ, NK), s2(NK, 2)
        real(real64)    :: amp(NK)
        integer         :: h, r, k, i
        call set_fixed_seed(SEED)
        do k = 1, NK
            amp(k) = exp(-real(k - 1, real64) / 6._real64)
        end do
        call random_number(s2)
        do h = 1, 2
            do k = 1, NK
                dat%w(k, h) = real(k + 1, real64) / (0.5_real64 + real(s2(k, h), real64))
            end do
            do r = 1, NREF
                call random_number(re)
                call random_number(im)
                do k = 1, NK
                    dat%rring(:, k, r, h) = cmplx(real((2*re(:, k) - 1) * amp(k), real32), &
                        &real((2*im(:, k) - 1) * amp(k), real32), real32)
                end do
            end do
        end do
        do i = 1, NPTCL
            call random_number(re)
            dat%ctf(:, :, i) = real(0.2_real64 + 0.8_real64 * real(re, real64), real32)
            call random_number(re)
            call random_number(im)
            do k = 1, NK
                dat%xring(:, k, i) = cmplx(real(dat%ctf(:, k, i) * real(dat%rring(:, k, 1 + mod(i, NREF), half_of(i))) + &
                    &(2*re(:, k) - 1) * amp(k) / 3., real32), real(dat%ctf(:, k, i) * &
                    &aimag(dat%rring(:, k, 1 + mod(i, NREF), half_of(i))) + (2*im(:, k) - 1) * amp(k) / 3., real32), real32)
            end do
            if( i == PTCL_INVALID ) dat%xring(:, :, i) = 1.e-3_real32 * dat%xring(:, :, i)
            dat%temps(i) = TEMP_LEVELS(mod(i - 1, 4) + 1)
        end do
    end function make_data

    ! 1 when the calculator refused its last call, else 0
    integer function refused( pftc )
        type(polarft_calc), intent(in) :: pftc
        refused = merge(1, 0, len(pftc%message()) > 0)
    end function refused

    ! a calculator of the data under the tile plan (rt, bt) and the tail's form, set and memoized up to the
    ! reference bins (left to the caller); nbad counts the calls that were refused
    subroutine feed_calc( pftc, dat, plan, form, nbad )
        type(polarft_calc), intent(inout) :: pftc
        type(tail_data),    intent(in)    :: dat
        integer,            intent(in)    :: plan(2), form
        integer,            intent(out)   :: nbad
        integer :: h, j, i
        call pftc%new(parameters(pftsz=PFTSZ), NREF, [1, NPTCL], [2, NK + 1])
        nbad = refused(pftc)
        call pftc%set_sigma2_weights(dat%w)
        nbad = nbad + refused(pftc)
        call pftc%set_tile_plan(plan(2), plan(1))
        nbad = nbad + refused(pftc)
        call pftc%set_tail_form(form)
        nbad = nbad + refused(pftc)
        do h = 1, 2
            do j = 1, NREF
                call pftc%set_ref_pft(j, cmplx(dat%rring(:, :, j, h), kind=real64), h == 1)
                nbad = nbad + refused(pftc)
            end do
        end do
        do i = 1, NPTCL
            call pftc%set_eo(i, half_of(i) == 1)
            call pftc%set_ptcl_ctfmat(i, dat%ctf(:, :, i))
            call pftc%set_ptcl_pft(i, dat%xring(:, :, i))
            nbad = nbad + refused(pftc)
        end do
        call pftc%memoize_refs
        nbad = nbad + refused(pftc)
        call pftc%memoize_ptcls
        nbad = nbad + refused(pftc)
    end subroutine feed_calc

    ! the particles pids of one half scored synchronously against every reference with the keyed variates, or
    ! with every variate u0 when it is present; the rows when the calculator keeps them
    subroutine score( pftc, dat, pids, ent, u0 )
        type(polarft_calc),           intent(inout) :: pftc
        type(tail_data),              intent(in)    :: dat
        integer,                      intent(in)    :: pids(:)
        type(polar_table_entries),    intent(out)   :: ent
        real(real32),       optional, intent(in)    :: u0
        real(real32), allocatable :: u(:,:)
        integer                   :: r, b
        allocate(u(NREF, size(pids)), ent%dists(NREF, size(pids)), ent%irots(NREF, size(pids)))
        do b = 1, size(pids)
            do r = 1, NREF
                u(r, b) = real(polar_keyed_u(SEED, pids(b), r), real32)
            end do
        end do
        if( present(u0) ) u = u0
        call pftc%set_block_variates(u)
        call pftc%score_block_posterior(size(pids), pids, NREF, [(r, r = 1, NREF)], dat%temps(pids), ent%dists, &
            &ent%irots)
        if( refused(pftc) == 0 ) call pftc%block_rows(ent%rows)
    end subroutine score

    logical function same_entries( a, b )
        type(polar_table_entries), intent(in) :: a, b
        same_entries = all(shape(a%dists) == shape(b%dists))
        if( same_entries ) same_entries = all(bits_equal(a%dists, b%dists)) .and. all(a%irots == b%irots)
    end function same_entries

    ! ---- the tests -----------------------------------------------------------------------------------------

    ! on the CPU device the fused form is refused where the reference bins are made, with the reason; set back
    ! to the compiled form, the calculator scores what a calculator that never had the fused form scores
    subroutine test_cpu_refusal( dat )
        type(tail_data), intent(in) :: dat
        type(polarft_calc)        :: pftc, pref
        type(polar_table_entries) :: e, eref
        integer                   :: nbad
        write(*,'(a)') 'test_cpu_refusal'
        call feed_calc(pftc, dat, [RT, BT], POLARFT_TAILS%metal, nbad)
        call assert_int(0, nbad, 'the calculator is set with the fused form: '//pftc%message())
        call pftc%memoize_ref_bins
        call assert_true(index(pftc%message(), 'GPU only') > 0, 'cpu: the fused tail is refused where the '//&
            &'reference bins are made, and message() says it runs on the GPU only')
        call assert_true(.not. pftc%ref_bins_current(), 'cpu: a refused form leaves no current reference bins')
        call pftc%set_tail_form(POLARFT_TAILS%graph)
        call pftc%memoize_ref_bins
        call assert_int(0, refused(pftc), 'cpu: set back to the compiled form, the reference bins are made')
        call score(pftc, dat, half_ptcls(1), e)
        call feed_calc(pref, dat, [RT, BT], POLARFT_TAILS%graph, nbad)
        call pref%memoize_ref_bins
        call score(pref, dat, half_ptcls(1), eref)
        call assert_true(same_entries(e, eref), 'cpu: after the refusal the compiled form scores as it does '//&
            &'without one, bit for bit')
        call pftc%set_tail_form(0)
        call assert_true(index(pftc%message(), 'POLARFT_TAILS') > 0, 'a form outside POLARFT_TAILS is refused')
        call pftc%kill
        call pref%kill
    end subroutine test_cpu_refusal

    ! the entries-only kernel and the rows variant give the same entries, bit for bit, with the keyed variates and
    ! with every u at 1.5 (no rotation reaches u W: the fallback to the minimising rotation); every entry is its
    ! row's at its rotation
    subroutine test_kernel_identity( dat )
        type(tail_data), intent(in) :: dat
        type(polarft_calc)        :: pftc
        type(polar_table_entries) :: e0, e1
        integer                   :: nbad, h, k, r, b, nrow
        real(real32)              :: u0
        write(*,'(a)') 'test_kernel_identity'
        call feed_calc(pftc, dat, [RT, BT], POLARFT_TAILS%metal, nbad)
        call pftc%memoize_ref_bins
        call assert_int(0, nbad + refused(pftc), 'the fused calculator is made: '//pftc%message())
        do k = 1, 2
            u0 = 1.5_real32
            do h = 1, 2
                call pftc%set_block_options(.false., .false.)
                if( k == 1 )then
                    call score(pftc, dat, half_ptcls(h), e0)
                else
                    call score(pftc, dat, half_ptcls(h), e0, u0=u0)
                endif
                call pftc%set_block_options(.true., .false.)
                if( k == 1 )then
                    call score(pftc, dat, half_ptcls(h), e1)
                else
                    call score(pftc, dat, half_ptcls(h), e1, u0=u0)
                endif
                call assert_int(0, refused(pftc), 'both kernels score the half')
                if( .not. allocated(e1%rows) ) return
                call assert_true(same_entries(e0, e1), 'gpu: the rows variant gives the entries-only kernel''s '//&
                    &'entries, bit for bit ('//trim(merge('keyed variates', 'u = 1.5       ', k == 1))//')')
                nrow = 0
                do b = 1, size(e1%irots, 2)
                    do r = 1, NREF
                        if( bits_equal(e1%dists(r, b), e1%rows(e1%irots(r, b), r, b)) ) nrow = nrow + 1
                    end do
                end do
                call assert_int(size(e1%irots), nrow, 'gpu: every entry''s distance is its row''s at its rotation')
            end do
        end do
        call pftc%kill
    end subroutine test_kernel_identity

    ! with the fused form, every entry is bitwise the same in three fills of one calculator, in a calculator made
    ! again, with one slot and with two, in outer batches of 6 and of 4, and with the rows variant
    subroutine test_repeatability( dat )
        type(tail_data), intent(in) :: dat
        type(polarft_calc) :: pftc, p2
        type(tail_fill)    :: f0, f
        integer            :: nbad, rep
        logical            :: same
        write(*,'(a)') 'test_repeatability'
        call feed_calc(pftc, dat, [RT, BT], POLARFT_TAILS%metal, nbad)
        call fill(pftc, dat, [NPTCL / 2, 1], .false., f0)
        call assert_true(allocated(f0%d), 'the fused calculator fills the range')
        if( .not. allocated(f0%d) ) return
        same = .true.
        do rep = 1, 3
            call fill(pftc, dat, [NPTCL / 2, 1], .false., f)
            same = same .and. same_fill(f0, f)
        end do
        call assert_true(same, 'gpu: three fills of one calculator give the same entries, bit for bit')
        call feed_calc(p2, dat, [RT, BT], POLARFT_TAILS%metal, nbad)
        call fill(p2, dat, [NPTCL / 2, 1], .false., f)
        call assert_true(same_fill(f0, f), 'gpu: a calculator made again gives the same entries')
        call fill(pftc, dat, [BT, 2], .false., f)
        call assert_true(same_fill(f0, f), 'gpu: outer batches of 4 with two slots in flight give the same entries')
        call fill(pftc, dat, [BT, 1], .false., f)
        call assert_true(same_fill(f0, f), 'gpu: outer batches of 4 with one slot give the same entries')
        call fill(pftc, dat, [NPTCL / 2, 1], .true., f)
        call assert_true(same_fill(f0, f), 'gpu: the rows variant fills the same entries as the entries-only kernel')
        call pftc%kill
        call p2%kill
    end subroutine test_repeatability

    ! the whole range filled through the driver in outer batches of sched(1) particles, sched(2) slots in flight,
    ! with or without the rows; f is left unallocated on a refusal
    subroutine fill( pftc, dat, sched, rows, f )
        type(polarft_calc), intent(inout) :: pftc
        type(tail_data),    intent(in)    :: dat
        integer,            intent(in)    :: sched(2)
        logical,            intent(in)    :: rows
        type(tail_fill),    intent(out)   :: f
        type(eul_prob_tab) :: tab
        type(parameters)   :: params
        integer            :: i
        params%pftsz = PFTSZ
        params%nthr  = 1
        call tab%new_pipeline(params, pftc, [(i, i = 1, NPTCL)])
        call tab%set_draw_keys(SEED, [(i, i = 1, NREF)])
        call tab%set_temps(dat%temps)
        call tab%set_fill_options(sched(1), sched(2), rows, .false.)
        call tab%fill_tab_range(1, NPTCL)
        if( len(tab%message()) == 0 ) call tab%batch_entries(f%d, f%ir, f%o)
        call tab%kill
    end subroutine fill

    ! two fills hold the same entries in the same order, bit for bit
    logical function same_fill( f0, f )
        type(tail_fill), intent(in) :: f0, f
        same_fill = allocated(f%d) .and. allocated(f%o)
        if( .not. same_fill ) return
        same_fill = all(shape(f%d) == shape(f0%d)) .and. all(f%o == f0%o)
        if( same_fill ) same_fill = all(bits_equal(f%d, f0%d)) .and. all(f%ir == f0%ir)
    end function same_fill

    ! tile plans down to one reference or one particle per tile: one source serves every shape; the draw holds on
    ! the kernel's own rows, and the drawn rotations are the compiled form's on the same plan within the frozen
    ! count
    subroutine test_small_plans( dat )
        type(tail_data), intent(in) :: dat
        integer,      parameter   :: RTS(2) = [1, 3], BTS(4) = [1, 4, 7, 8]
        type(polarft_calc)        :: pf, pg
        type(polar_table_entries) :: ef, eg
        real(real32), allocatable :: u(:,:)
        integer                   :: ir, ib, nbad, ndiff, ndraw, r, b
        integer,      allocatable :: pids(:)
        character(len=32)         :: plan
        write(*,'(a)') 'test_small_plans'
        pids = half_ptcls(1)
        do ir = 1, size(RTS)
            do ib = 1, size(BTS)
                write(plan, '(a,i0,a,i0)') 'rt ', RTS(ir), ', bt ', BTS(ib)
                call feed_calc(pf, dat, [RTS(ir), BTS(ib)], POLARFT_TAILS%metal, nbad)
                call pf%memoize_ref_bins
                call pf%set_block_options(.true., .false.)
                call score(pf, dat, pids, ef)
                call feed_calc(pg, dat, [RTS(ir), BTS(ib)], POLARFT_TAILS%graph, nbad)
                call pg%memoize_ref_bins
                call score(pg, dat, pids, eg)
                call assert_int(0, refused(pf) + refused(pg), 'both forms score '//trim(plan))
                if( .not. allocated(ef%rows) .or. .not. allocated(eg%irots) ) cycle
                allocate(u(NREF, size(pids)))
                do b = 1, size(pids)
                    do r = 1, NREF
                        u(r, b) = real(polar_keyed_u(SEED, pids(b), r), real32)
                    end do
                end do
                ndraw = polar_draws_off(ef, dat%temps(pids), u)
                ndiff = count(ef%irots /= eg%irots)
                deallocate(u)
                call assert_int(0, ndraw, 'gpu, '//trim(plan)//': the fused draw lies in its own row''s '//&
                    &'cumulative interval, and the entry''s distance is its row''s')
                call assert_true(ndiff <= POLARFT_TAIL_ROT_FIX, 'gpu, '//trim(plan)//': the drawn rotations are the '//&
                    &'compiled form''s in all but POLARFT_TAIL_ROT_FIX pairs')
                call pf%kill
                call pg%kill
            end do
        end do
    end subroutine test_small_plans

    ! the objects a workspace holds: with the compiled form (the default) its tiles and compiled function, with the
    ! fused form its constants in addition and a kernel in place of the function, and the rows variant once a
    ! block asks for rows; 100 cycles of making and releasing the reference bins leave no live handle
    subroutine test_objects( dat )
        type(tail_data), intent(in) :: dat
        type(polarft_calc)        :: pftc
        type(polar_table_entries) :: e
        integer                   :: nbad, live0, live1, it
        write(*,'(a)') 'test_objects'
        ! the default form, never set
        call pftc%new(parameters(pftsz=PFTSZ), NREF, [1, NPTCL], [2, NK + 1])
        call feed_default(pftc, dat, nbad)
        live0 = mlx_live_count()
        call pftc%memoize_ref_bins
        call assert_int(2 * LIVE_PER_WORKSPACE, mlx_live_count() - live0, 'gpu: by default the reference bins of '//&
            &'both parities hold their tiles and the compiled tail, and no kernel')
        call pftc%kill
        call feed_calc(pftc, dat, [RT, BT], POLARFT_TAILS%metal, nbad)
        live0 = mlx_live_count()
        call pftc%memoize_ref_bins
        call assert_int(2 * (LIVE_PER_WORKSPACE + LIVE_FUSED_EXTRA), mlx_live_count() - live0, 'gpu: with the fused '//&
            &'form each parity holds its tiles, its kernel and its constants, and no compiled tail')
        live1 = mlx_live_count()
        call pftc%set_block_options(.true., .false.)
        call score(pftc, dat, half_ptcls(1), e)
        call assert_int(1, mlx_live_count() - live1, 'gpu: the first block that asks for rows builds the rows '//&
            &'variant of its parity''s workspace, and nothing else stays')
        call score(pftc, dat, half_ptcls(1), e)
        call assert_int(1, mlx_live_count() - live1, 'gpu: a second block with rows reuses it')
        call pftc%kill_ref_bins
        call assert_int(live0, mlx_live_count(), 'gpu: releasing the reference bins releases the kernels and the '//&
            &'constants')
        do it = 1, 100
            call pftc%memoize_ref_bins
            call pftc%kill_ref_bins
        end do
        call assert_int(live0, mlx_live_count(), 'gpu: 100 cycles of making and releasing the fused reference '//&
            &'bins leave no live handle')
        call pftc%kill
    end subroutine test_objects

    ! the rest of feed_calc on a calculator already made: the default tile plan and form
    subroutine feed_default( pftc, dat, nbad )
        type(polarft_calc), intent(inout) :: pftc
        type(tail_data),    intent(in)    :: dat
        integer,            intent(out)   :: nbad
        integer :: h, j, i
        call pftc%set_sigma2_weights(dat%w)
        nbad = refused(pftc)
        do h = 1, 2
            do j = 1, NREF
                call pftc%set_ref_pft(j, cmplx(dat%rring(:, :, j, h), kind=real64), h == 1)
            end do
        end do
        do i = 1, NPTCL
            call pftc%set_eo(i, half_of(i) == 1)
            call pftc%set_ptcl_ctfmat(i, dat%ctf(:, :, i))
            call pftc%set_ptcl_pft(i, dat%xring(:, :, i))
        end do
        call pftc%memoize_refs
        call pftc%memoize_ptcls
        nbad = nbad + refused(pftc)
    end subroutine feed_default

end module mlxf_toy_polarft_tail_tester
