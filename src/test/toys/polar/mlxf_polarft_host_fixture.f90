!@descr: the fixture of the polar host route: seeded rings, a table filled through the toy driver on either backend, the table's lines
! Plain Fortran over the toys' host modules, so that the off-state program and sub-suite polarft_host share it: it
! imports no MLX name. The values come from an integer hash of the seed, computed in double precision and rounded
! once, so that every compiler and build makes the same fixture: references per half, particles as their CTF
! times a reference of their half rotated plus noise (one particle a thousandth as strong, whose rows are
! invalid), shell weights, inverse temperatures and keys of the draws. The table is filled as SIMPLE fills it:
! calculator, setters, memoization, the driver's fill_tab_range.
module mlxf_polarft_host_fixture
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf_test_defs,        only: PH_PFTSZ, PH_KFROM, PH_NK, PH_NREFS, PH_NPTCLS, PFTC_BLOCK_NB, parameters, &
                                 polarft_host_fixture, polarft_host_table
use mlxf_toy_polarft_calc, only: polarft_calc
use mlxf_toy_eul_prob_tab, only: eul_prob_tab
implicit none

public :: make_polarft_host_fixture, polarft_host_half, polarft_host_calc, fill_polarft_host_table
public :: write_polarft_host_table
private

integer, parameter :: NROTS = 2 * PH_PFTSZ
! the particle whose signal is a thousandth of the others': every rotation of its rows is invalid
integer, parameter :: PTCL_INVALID = 5
! the particles' inverse temperatures, in turn
real(real32), parameter :: TEMP_LEVELS(4) = [0._real32, 1._real32, 30._real32, 1.e4_real32]
! the MLX backend's tile plan of the fixture (particles and references per tile): partial tiles both ways
integer, parameter :: PH_BT = 8
integer, parameter :: PH_RT = 16

contains

    ! the half of a particle: half 1 (SIMPLE's even half) holds the odd indices
    pure integer function polarft_host_half( i )
        integer, intent(in) :: i
        polarft_host_half = 2 - mod(i, 2)
    end function polarft_host_half

    ! a value in [0, 1) from the seed and three indices: a Lehmer generator over an integer key, exact
    pure real(real64) function unit_of( seed, a, b, c )
        integer, intent(in) :: seed, a, b, c
        integer(int64), parameter :: M = 2147483647_int64, G = 48271_int64
        integer(int64)            :: x
        integer                   :: i
        x = mod(int(seed, int64) * 999983_int64 + int(a, int64) * 7919_int64 + int(b, int64) * 104729_int64 + &
            &int(c, int64) * 1299709_int64, M)
        if( x == 0_int64 ) x = 1_int64
        do i = 1, 5
            x = mod(G * x, M)
        end do
        unit_of = real(x - 1_int64, real64) / real(M - 1_int64, real64)
    end function unit_of

    function make_polarft_host_fixture( seed ) result(fx)
        integer, intent(in) :: seed
        type(polarft_host_fixture) :: fx
        complex(real64)            :: full(NROTS), z
        real(real64)               :: amp(PH_NK), c
        integer                    :: h, r, i, k, j, src, shift, key
        fx%seed = seed
        allocate(fx%w(PH_NK, 2), fx%rref(PH_PFTSZ, PH_NK, PH_NREFS, 2), fx%x(PH_PFTSZ, PH_NK, PH_NPTCLS), &
            &fx%ctf(PH_PFTSZ, PH_NK, PH_NPTCLS), fx%temps(PH_NPTCLS), fx%ref_full(PH_NREFS))
        do k = 1, PH_NK
            amp(k) = exp(-real(k - 1, real64) / 6._real64)
        end do
        ! shell weights k / sigma2(k, half), sigma2 in [0.5, 1.5)
        do h = 1, 2
            do k = 1, PH_NK
                fx%w(k, h) = real(PH_KFROM + k - 1, real64) / (0.5_real64 + unit_of(seed, 1, k, h))
            end do
        end do
        do h = 1, 2
            do r = 1, PH_NREFS
                do k = 1, PH_NK
                    do j = 1, PH_PFTSZ
                        key = j + PH_PFTSZ * (k - 1)
                        fx%rref(j, k, r, h) = amp(k) * cmplx(2._real64 * unit_of(seed, 10 + h, r, key) - 1._real64, &
                            &2._real64 * unit_of(seed, 20 + h, r, key) - 1._real64, real64)
                    end do
                end do
            end do
        end do
        ! particle i: its CTF times reference src of its half rotated by shift samples, plus noise
        do i = 1, PH_NPTCLS
            h     = polarft_host_half(i)
            src   = 1 + mod(3 * i, PH_NREFS)
            shift = mod(7 * i, NROTS)
            do k = 1, PH_NK
                full(1:PH_PFTSZ)  = fx%rref(:, k, src, h)
                full(PH_PFTSZ+1:) = conjg(fx%rref(:, k, src, h))
                do j = 1, PH_PFTSZ
                    key = j + PH_PFTSZ * (k - 1)
                    c   = 0.2_real64 + 0.8_real64 * unit_of(seed, 30, i, key)
                    z   = c * full(1 + mod(j - 1 - shift + 2 * NROTS, NROTS)) + 0.3_real64 * amp(k) * &
                        &cmplx(2._real64 * unit_of(seed, 40, i, key) - 1._real64, &
                        &2._real64 * unit_of(seed, 50, i, key) - 1._real64, real64)
                    if( i == PTCL_INVALID ) z = 1.e-3_real64 * z
                    fx%ctf(j, k, i) = real(c, real32)
                    fx%x(j, k, i)   = cmplx(z, kind=real32)
                end do
            end do
            ! the levels in turn within each half (the place of the particle in its half, from 1)
            fx%temps(i) = TEMP_LEVELS(1 + mod(ishft(i + 1, -1), size(TEMP_LEVELS)))
        end do
        do r = 1, PH_NREFS
            fx%ref_full(r) = 1000 + 7 * r
        end do
    end function make_polarft_host_fixture

    ! a calculator of the fixture on the backend and with the team of params: references and particles set and
    ! memoized, the reference bins made; msg is the first refusal, empty when there was none
    subroutine polarft_host_calc( fx, params, pftc, msg )
        type(polarft_host_fixture),    intent(in)    :: fx
        type(parameters),              intent(in)    :: params
        type(polarft_calc),            intent(inout) :: pftc
        character(len=:), allocatable, intent(out)   :: msg
        integer :: h, r, i
        msg = ''
        call pftc%new(params, PH_NREFS, [1, PH_NPTCLS], [PH_KFROM, PH_KFROM + PH_NK - 1])
        call note(pftc%message())
        if( len(msg) > 0 ) return
        call pftc%set_sigma2_weights(fx%w)
        call note(pftc%message())
        if( params%l_mlx )then
            call pftc%set_tile_plan(PH_BT, PH_RT)
            call note(pftc%message())
        endif
        do h = 1, 2
            do r = 1, PH_NREFS
                call pftc%set_ref_pft(r, fx%rref(:, :, r, h), h == 1)
                call note(pftc%message())
            end do
        end do
        call pftc%reallocate_ptcls(PH_NPTCLS, [(i, i = 1, PH_NPTCLS)])
        call note(pftc%message())
        do i = 1, PH_NPTCLS
            call pftc%set_eo(i, polarft_host_half(i) == 1)
            call note(pftc%message())
            call pftc%set_ptcl_ctfmat(i, fx%ctf(:, :, i))
            call note(pftc%message())
            call pftc%set_ptcl_pft(i, fx%x(:, :, i))
            call note(pftc%message())
        end do
        call pftc%memoize_refs()
        call note(pftc%message())
        call pftc%memoize_ptcls()
        call note(pftc%message())
        call pftc%memoize_ref_bins()
        call note(pftc%message())

      contains

        subroutine note( m )
            character(len=*), intent(in) :: m
            if( len(msg) == 0 .and. len(m) > 0 ) msg = m
        end subroutine note

    end subroutine polarft_host_calc

    ! the table of the fixture, filled through the driver on the backend tab%l_mlx with a host team of tab%nthr, the
    ! full rows kept when tab%l_rows: the dense entries (references, particles in the batch's order), that order,
    ! and the first refusal in tab%msg
    subroutine fill_polarft_host_table( fx, tab )
        type(polarft_host_fixture), intent(in)    :: fx
        type(polarft_host_table),   intent(inout) :: tab
        type(polarft_calc), target :: pftc
        type(eul_prob_tab)         :: drv
        type(parameters)           :: params
        integer                    :: i
        params = parameters(pftsz=PH_PFTSZ, box=2 * PH_PFTSZ, nthr=tab%nthr, l_mlx=tab%l_mlx)
        call polarft_host_calc(fx, params, pftc, tab%msg)
        if( len(tab%msg) == 0 )then
            call drv%new_pipeline(params, pftc, [(i, i = 1, PH_NPTCLS)])
            call note(drv%message())
            call drv%set_draw_keys(fx%seed, fx%ref_full)
            call note(drv%message())
            call drv%set_temps(fx%temps)
            call note(drv%message())
            call drv%set_fill_options(PFTC_BLOCK_NB, 1, tab%l_rows, .false.)
            call note(drv%message())
            if( len(tab%msg) == 0 )then
                call drv%fill_tab_range(1, PH_NPTCLS)
                call note(drv%message())
            endif
            if( len(tab%msg) == 0 )then
                call drv%batch_entries(tab%dists, tab%irots, tab%order)
                if( tab%l_rows ) call drv%batch_full_rows(tab%rows)
            endif
            call drv%kill()
        endif
        call pftc%kill()

      contains

        subroutine note( m )
            character(len=*), intent(in) :: m
            if( len(tab%msg) == 0 .and. len(m) > 0 ) tab%msg = m
        end subroutine note

    end subroutine fill_polarft_host_table

    ! the table as lines of standard output, every value's bit pattern in hexadecimal: a header, then per particle
    ! of the batch's order its place in the fixture, its distances and its rotations. Two builds that write the
    ! same lines made the same table, byte for byte.
    subroutine write_polarft_host_table( fx, tab )
        type(polarft_host_fixture), intent(in) :: fx
        type(polarft_host_table),   intent(in) :: tab
        integer :: j, r
        write(*,'(a,i0,a,i0,a,i0)') 'polarft_host table seed=', fx%seed, ' references=', size(tab%dists, 1), &
            &' particles=', size(tab%dists, 2)
        do j = 1, size(tab%dists, 2)
            write(*,'(a,i0)', advance='no') 'polarft_host ', tab%order(j)
            do r = 1, size(tab%dists, 1)
                write(*,'(1x,z8.8)', advance='no') transfer(tab%dists(r, j), 0_int32)
            end do
            do r = 1, size(tab%irots, 1)
                write(*,'(1x,z8.8)', advance='no') int(tab%irots(r, j), int32)
            end do
            write(*,'(a)') ''
        end do
    end subroutine write_polarft_host_table

end module mlxf_polarft_host_fixture
