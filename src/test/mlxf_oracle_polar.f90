!@descr: the polar fixtures' shared tools: ring DFT, keyed variates, the memo-level oracle, checks of rows and draws
! Double precision throughout. The memo-level oracle evaluates every rotation's distance from the memos by a
! direct inverse real DFT (no FFT), as the production scorer defines it; the checks hold a device's rows to an
! oracle's and its draws to its own rows. Used by the workspace's tester and by the benchmark.
module mlxf_oracle_polar
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
!$ use omp_lib,      only: omp_get_thread_num, omp_get_max_threads
use mlxf_test_defs,  only: POLAR_DIST_MAX, POLAR_DIST_INVALID, POLAR_DIST_VALID, POLAR_ARG_CUTOFF, POLAR_DRAW_FLOOR, &
                           POLAR_DRAW_TOL, POLAR_VALID_MARGIN, polar_table_refs, polar_table_block, &
                           polar_table_entries, polar_row_check
use mlxf_test_utils, only: bits_equal
implicit none
private

public :: polar_full_ring, polar_dft_matrix, polar_dft_bins, polar_keyed_u, polar_first_min
public :: polar_row_weights, polar_draw_row, polar_compare_rows, polar_draws_off, polar_report_draws
public :: polar_memo_rows

contains

    ! the full ring of a half ring: the samples, then their conjugates
    function polar_full_ring( z ) result(f)
        complex(real64), intent(in) :: z(:)
        complex(real64) :: f(2*size(z))
        f(1:size(z))  = z
        f(size(z)+1:) = conjg(z)
    end function polar_full_ring

    ! the forward DFT's factors (negative exponent) of the first nbins bins of a ring of n samples
    function polar_dft_matrix( n, nbins ) result(e)
        integer, intent(in) :: n, nbins
        complex(real64) :: e(nbins, n)
        real(real64)    :: angle
        integer         :: p, m
        do m = 1, n
            do p = 1, nbins
                angle   = -2._real64 * acos(-1._real64) * real(mod((p - 1) * (m - 1), n), real64) / real(n, real64)
                e(p, m) = cmplx(cos(angle), sin(angle), real64)
            end do
        end do
    end function polar_dft_matrix

    ! the first size(e,1) bins of the forward DFT of the full ring f, no scale, summed in ring order
    function polar_dft_bins( e, f ) result(y)
        complex(real64), intent(in) :: e(:,:), f(:)
        complex(real64) :: y(size(e, 1))
        integer         :: p, m
        do p = 1, size(e, 1)
            y(p) = (0._real64, 0._real64)
            do m = 1, size(f)
                y(p) = y(p) + f(m) * e(p, m)
            end do
        end do
    end function polar_dft_bins

    ! a deterministic variate in [0,1) keyed by a seed and the pair's global IDs, never by tile position (a
    ! Lehmer generator over the key)
    real(real64) function polar_keyed_u( seed, pid, rid )
        integer, intent(in) :: seed, pid, rid
        integer(int64), parameter :: M = 2147483647_int64, A = 48271_int64
        integer(int64)            :: x
        integer                   :: i
        x = mod(int(seed, int64) * 1000003_int64 + int(pid, int64) * 7919_int64 + int(rid, int64) * 104729_int64, M)
        if( x == 0_int64 ) x = 1_int64
        do i = 1, 4
            x = mod(A * x, M)
        end do
        polar_keyed_u = real(x - 1_int64, real64) / real(M - 1_int64, real64)
    end function polar_keyed_u

    ! the first minimum of the valid entries of a row (0: none valid)
    pure integer function polar_first_min( row )
        real(real64), intent(in) :: row(:)
        real(real64) :: dmin
        integer      :: m
        polar_first_min = 0
        dmin            = huge(dmin)
        do m = 1, size(row)
            if( row(m) < real(POLAR_DIST_VALID, real64) .and. row(m) < dmin )then
                dmin            = row(m)
                polar_first_min = m
            endif
        end do
    end function polar_first_min

    ! a row's posterior weights exp(-T (d - dmin)), zero where invalid or where the argument reaches the cutoff
    pure subroutine polar_row_weights( row, temp, w )
        real(real64), intent(in)  :: row(:)
        real(real32), intent(in)  :: temp
        real(real64), intent(out) :: w(:)
        real(real64) :: dmin, arg
        integer      :: m
        dmin = minval(row, mask=row < real(POLAR_DIST_VALID, real64))
        do m = 1, size(row)
            w(m) = 0._real64
            if( row(m) < real(POLAR_DIST_VALID, real64) )then
                arg = real(max(0._real32, temp), real64) * (row(m) - dmin)
                if( arg < real(POLAR_ARG_CUTOFF, real64) ) w(m) = exp(-arg)
            endif
        end do
    end subroutine polar_row_weights

    ! the posterior draw of a row in double precision (the rule the device applies): the first rotation whose
    ! cumulative weight reaches max(u W, tiny), else the minimising rotation; 1 when no rotation is valid
    pure integer function polar_draw_row( row, temp, u )
        real(real64), intent(in) :: row(:), u
        real(real32), intent(in) :: temp
        real(real64) :: w(size(row)), cum, tgt
        integer      :: imin, m
        imin           = polar_first_min(row)
        polar_draw_row = 1
        if( imin == 0 ) return
        call polar_row_weights(row, temp, w)
        tgt            = max(u * sum(w), real(POLAR_DRAW_FLOOR, real64))
        cum            = 0._real64
        polar_draw_row = imin
        do m = 1, size(row)
            cum = cum + w(m)
            if( w(m) > 0._real64 .and. cum >= tgt )then
                polar_draw_row = m
                return
            endif
        end do
    end function polar_draw_row

    ! a device's rows against an oracle's, pair by pair: the largest error of a valid entry relative to the
    ! largest valid |d| of the pair's oracle row, the pairs whose minimising rotation differs, the entries whose
    ! validity differs away from the invalid distance (within POLAR_VALID_MARGIN of it float32 and float64 may
    ! differ), and the rows of mixed validity and without a valid rotation
    function polar_compare_rows( dor, ent ) result(chk)
        real(real64),              intent(in) :: dor(:,:,:)
        type(polar_table_entries), intent(in) :: ent
        type(polar_row_check) :: chk
        real(real64)          :: dmax, dev, e
        integer               :: ir, b, m, nvalid, nrots
        logical               :: vo, vd
        nrots = size(dor, 1)
        do b = 1, size(dor, 3)
            do ir = 1, size(dor, 2)
                chk%npairs = chk%npairs + 1
                nvalid     = count(dor(:, ir, b) < real(POLAR_DIST_VALID, real64))
                if( nvalid > 0 .and. nvalid < nrots ) chk%mixed = chk%mixed + 1
                if( nvalid == 0 ) chk%invalid = chk%invalid + 1
                dmax = maxval(abs(dor(:, ir, b)), mask=dor(:, ir, b) < real(POLAR_DIST_VALID, real64))
                e    = 0._real64
                do m = 1, nrots
                    dev = real(ent%rows(m, ir, b), real64)
                    vo  = dor(m, ir, b) < real(POLAR_DIST_VALID, real64)
                    vd  = dev < real(POLAR_DIST_VALID, real64)
                    if( vo .and. vd )then
                        e = max(e, abs(dev - dor(m, ir, b)) / dmax)
                    else if( vo .neqv. vd )then
                        if( vo )then
                            if( abs(dor(m, ir, b) - POLAR_DIST_MAX) > POLAR_VALID_MARGIN * dmax ) &
                                &chk%valid_off = chk%valid_off + 1
                        else
                            chk%valid_off = chk%valid_off + 1
                        endif
                    endif
                end do
                chk%err = max(chk%err, e)
                if( polar_first_min(dor(:, ir, b)) /= polar_first_min(real(ent%rows(:, ir, b), real64)) ) &
                    &chk%argmin_off = chk%argmin_off + 1
            end do
        end do
    end function polar_compare_rows

    ! the draw given the device's own rows: u W in the drawn rotation's cumulative interval within
    ! POLAR_DRAW_TOL W, or the fallback to the minimising rotation when no rotation reaches it; (invalid, 1)
    ! without a valid rotation; and the entry's distance is the row's distance at the drawn rotation, bit for bit
    integer function polar_draws_off( ent, temps, u )
        type(polar_table_entries), intent(in) :: ent
        real(real32),              intent(in) :: temps(:), u(:,:)
        real(real64) :: row(size(ent%rows, 1)), w(size(ent%rows, 1)), cum0, cum1, tgt, tol
        integer      :: ir, b, irot, imin
        logical      :: ok
        polar_draws_off = 0
        do b = 1, size(ent%irots, 2)
            do ir = 1, size(ent%irots, 1)
                row  = real(ent%rows(:, ir, b), real64)
                irot = ent%irots(ir, b)
                imin = polar_first_min(row)
                if( imin == 0 )then
                    ok = irot == 1 .and. bits_equal(ent%dists(ir, b), POLAR_DIST_INVALID)
                else if( irot < 1 .or. irot > size(row) )then
                    ok = .false.
                else
                    call polar_row_weights(row, temps(b), w)
                    tgt  = max(real(u(ir, b), real64) * sum(w), real(POLAR_DRAW_FLOOR, real64))
                    tol  = POLAR_DRAW_TOL * sum(w)
                    cum1 = sum(w(1:irot))
                    cum0 = cum1 - w(irot)
                    ok   = w(irot) > 0._real64 .and. cum0 - tol <= tgt .and. tgt <= cum1 + tol
                    if( .not. ok ) ok = irot == imin .and. tgt >= sum(w) - tol
                    if( ok ) ok = bits_equal(ent%dists(ir, b), ent%rows(irot, ir, b))
                endif
                if( .not. ok ) polar_draws_off = polar_draws_off + 1
            end do
        end do
    end function polar_draws_off

    ! reported, not gated: per temperature of the block, the pairs whose device rotation differs from the draw
    ! on the oracle's rows with the same float32 variate, and the oracle draws that change when the real64
    ! keyed variate (seed) is rounded to float32
    subroutine polar_report_draws( label, seed, dor, ent, blk )
        character(len=*),          intent(in) :: label
        integer,                   intent(in) :: seed
        real(real64),              intent(in) :: dor(:,:,:)
        type(polar_table_entries), intent(in) :: ent
        type(polar_table_block),   intent(in) :: blk
        real(real32), allocatable :: levels(:)
        integer,      allocatable :: ndiff(:), nu(:), npairs(:)
        real(real64)              :: u32, u64
        integer                   :: ir, b, it, lev
        allocate(levels(0))
        do b = 1, size(blk%temps)
            if( .not. any(bits_equal(levels, blk%temps(b))) ) levels = [levels, blk%temps(b)]
        end do
        allocate(ndiff(size(levels)), nu(size(levels)), npairs(size(levels)))
        ndiff  = 0
        nu     = 0
        npairs = 0
        do b = 1, size(dor, 3)
            lev = 0
            do it = 1, size(levels)
                if( bits_equal(levels(it), blk%temps(b)) ) lev = it
            end do
            do ir = 1, size(dor, 2)
                u32 = real(blk%u(ir, b), real64)
                u64 = polar_keyed_u(seed, blk%ptcl_ids(b), blk%ref_ids(ir))
                npairs(lev) = npairs(lev) + 1
                if( polar_draw_row(dor(:, ir, b), blk%temps(b), u32) /= ent%irots(ir, b) ) ndiff(lev) = ndiff(lev) + 1
                if( polar_draw_row(dor(:, ir, b), blk%temps(b), u32) /= &
                    &polar_draw_row(dor(:, ir, b), blk%temps(b), u64) ) nu(lev) = nu(lev) + 1
            end do
        end do
        do it = 1, size(levels)
            write(*,'(a,es8.1,a,i0,a,i0,a,i0)') '    '//label//' T=', levels(it), ': device rotation /= '//&
                &'oracle rows'' draw in ', ndiff(it), ' of ', npairs(it), '; float32 u changes the oracle draw in ', &
                &nu(it)
        end do
    end subroutine polar_report_draws

    ! every rotation's distance of every pair from the memos, by a direct inverse real DFT in double
    ! precision: c(p) = sum_k w_k [ctf2 ft_ref2 - 2 xctf conj(ft_ref)] (the bank where l_bank), then
    ! d(n) = 1 + irdft(c)(n) / (2 wsq), the imaginary parts of the first and last bins ignored as an inverse real
    ! transform ignores them; above POLAR_DIST_MAX the invalid marker. OpenMP over the pairs.
    function polar_memo_rows( refs, blk ) result(d)
        type(polar_table_refs),  intent(in) :: refs
        type(polar_table_block), intent(in) :: blk
        real(real64),    allocatable :: d(:,:,:)
        real(real64),    allocatable :: cs(:,:), sn(:,:), wgt(:)
        complex(real64), allocatable :: c(:,:)
        complex(real64)              :: x
        real(real64)                 :: acc, ang
        integer                      :: nb, nr, n1, nrots, nk, ip, b, ir, p, k, n, ithr, nthr
        nb    = size(blk%ctf2, 3)
        nr    = size(refs%ids)
        n1    = refs%pftsz + 1
        nrots = 2 * refs%pftsz
        nk    = refs%nk
        allocate(d(nrots, nr, nb), cs(n1, nrots), sn(n1, nrots), wgt(n1))
        do n = 1, nrots
            do p = 1, n1
                ang      = 2._real64 * acos(-1._real64) * real(mod((p - 1) * (n - 1), nrots), real64) / &
                    &real(nrots, real64)
                cs(p, n) = cos(ang)
                sn(p, n) = sin(ang)
            end do
        end do
        ! the inverse real DFT's weights: the first and last bins once, the others twice (their conjugates)
        wgt     = 2._real64 / real(nrots, real64)
        wgt(1)  = 1._real64 / real(nrots, real64)
        wgt(n1) = 1._real64 / real(nrots, real64)
        nthr = 1
        !$ nthr = omp_get_max_threads()
        allocate(c(n1, nthr))
        !$omp parallel do default(shared) private(ip, b, ir, p, k, n, x, acc, ithr) schedule(static) proc_bind(close)
        do ip = 1, nb * nr
            ithr = 1
            !$ ithr = omp_get_thread_num() + 1
            b  = (ip - 1) / nr + 1
            ir = ip - (b - 1) * nr
            do p = 1, n1
                c(p, ithr) = (0._real64, 0._real64)
            end do
            do k = 1, nk
                do p = 1, n1
                    x = cmplx(blk%xctf(p, k, b), kind=real64)
                    if( allocated(blk%l_bank) )then
                        if( blk%l_bank(b) ) x = cmplx(blk%banks(p, k, b), kind=real64)
                    endif
                    c(p, ithr) = c(p, ithr) + real(blk%weights(k), real64) * &
                        &(cmplx(blk%ctf2(p, k, b), kind=real64) * cmplx(refs%ft_ref2(p, k, ir), kind=real64) - &
                        &2._real64 * x * conjg(cmplx(refs%ft_ref(p, k, ir), kind=real64)))
                end do
            end do
            do n = 1, nrots
                acc = 0._real64
                do p = 1, n1
                    if( p == 1 .or. p == n1 )then
                        acc = acc + wgt(p) * real(c(p, ithr), real64) * cs(p, n)
                    else
                        acc = acc + wgt(p) * (real(c(p, ithr), real64) * cs(p, n) - aimag(c(p, ithr)) * sn(p, n))
                    endif
                end do
                d(n, ir, b) = 1._real64 + acc / (2._real64 * blk%wsq(b))
                if( d(n, ir, b) > POLAR_DIST_MAX ) d(n, ir, b) = real(POLAR_DIST_INVALID, real64)
            end do
        end do
        !$omp end parallel do
    end function polar_memo_rows

end module mlxf_oracle_polar
