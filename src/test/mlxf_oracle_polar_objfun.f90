!@descr: host oracle of the polar objectives: Euclidean loss, two correlations, in-plane and reference reductions
! A half ring z(1:P, i) holds P = pftsz samples at angles 2 pi (p - 1) / N, N = 2 P, of shell kfrom + i - 1; the full
! ring is z(p + P) = conj(z(p)). Rotation irot = 1 .. N reads the reference's full ring at p - (irot - 1). A shift
! (x, y), pixels of the box in the reference's frame, multiplies the unrotated reference by the phase
! exp(+i (2 pi k / box) (x sin - y cos)) before the extension. The CTF modulus is real with period P. Direct sums
! in double precision, on intrinsic modules and mlxf_oracle_dft; the ring-transform route is a separate binding.
module mlxf_oracle_polar_objfun
use, intrinsic :: iso_fortran_env, only: real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_quiet_nan, ieee_positive_inf
use mlxf_oracle_dft, only: oracle_dft_1d, oracle_idft_1d, oracle_rel_error, oracle_finite_or_inf
implicit none

public :: oracle_polar_pair, oracle_polar_fixture, oracle_polar_score, oracle_polar_valid, oracle_polar_clamp, &
          oracle_polar_angle, oracle_polar_frame, oracle_polar_best_dist, oracle_polar_best_score, &
          oracle_polar_store, oracle_polar_greedy, oracle_polar_best_k, oracle_polar_shc, oracle_polar_selfcheck
private

real(real64),    parameter :: PI    = acos(-1._real64)
real(real64),    parameter :: TWOPI = 2._real64 * PI
complex(real64), parameter :: CZERO = (0._real64, 0._real64)
! a distance above this is invalid
real(real64), parameter :: DIST_LIMIT = -log(1.e-10_real64)
! the fixture: per size pftsz, first shell, number of shells and box; in the third the box is not twice pftsz
integer,         parameter :: NSIZE = 3
integer,         parameter :: SIZES(4, NSIZE) = reshape([16, 2, 8, 32, 12, 2, 6, 24, 12, 3, 5, 40], [4, NSIZE])
! point sources (x, y, amplitude) by columns: the two references, then a clutter pattern
real(real64),    parameter :: REF_PTS(3, 3, 2) = reshape([1.5_real64, -0.5_real64, 1._real64, -2.25_real64, &
    1._real64, 0.6_real64, 0.5_real64, 2.75_real64, -0.4_real64, -1._real64, -1.75_real64, 0.8_real64, &
    2.5_real64, 0.75_real64, 0.5_real64, 0.25_real64, -3._real64, 0.7_real64], [3, 3, 2])
real(real64),    parameter :: CLUTTER_PTS(3, 2) = reshape([3._real64, 1.25_real64, 0.5_real64, -0.75_real64, &
    -2.5_real64, 0.45_real64], [3, 2])
real(real64), parameter :: CLUTTER_AMP = 0.3_real64
! the generic particles: rotation steps and shift of their reference, rotation steps of their clutter
integer,         parameter :: PTCL_TURN(2)     = [5, 19]
real(real64),    parameter :: PTCL_SHIFT(2, 2) = reshape([0.75_real64, -1.25_real64, -1.5_real64, 0.5_real64], [2, 2])
integer,         parameter :: CLUTTER_TURN(2)  = [0, 7]
! the planted copies: rotation steps below and above pftsz, a shift in the reference's frame, one in the
! particle's frame, and the factors of the copy scaled on even and odd shells
integer,         parameter :: PLANT_TURN(2)   = [5, 21]
real(real64),    parameter :: PLANT_SHIFT(2)  = [1.25_real64, -0.75_real64]
real(real64),    parameter :: PLANT_UFRAME(2) = [0.5_real64, -1.5_real64]
real(real64),    parameter :: SCALE_EVEN      = 1._real64
real(real64),    parameter :: SCALE_ODD       = -0.5_real64
! the self-check's limits: closed forms and identities between two routes; exact checks have limit 0
real(real64),    parameter :: TOL_ROUTE = 1.e-12_real64
integer,         parameter :: NCHECK    = 25
integer,         parameter :: LABEL_LEN = 24
character(len=LABEL_LEN), parameter :: CHECK_NAMES(NCHECK) = [character(len=LABEL_LEN) :: &
    'counts', 'shift phase by hand', 'rotation by hand', 'table vs closed form', 'zero loss copy', &
    'unit correlation', 'planted rotation loss', 'planted rotation index', 'planted shift', &
    'planted rotation shift', 'particle-frame shift', 'scaled shells loss', 'scaled shells cc', &
    'scaled shells weighted', 'direct vs rings', 'cc bound', 'score clamp validity', 'angle and frame', &
    'in-plane best', 'store', 'greedy', 'best k', 'hill climb', 'zero denominators', 'arrays and band']
real(real64),    parameter :: CHECK_LIMITS(NCHECK) = [0._real64, TOL_ROUTE, 0._real64, TOL_ROUTE, TOL_ROUTE, &
    TOL_ROUTE, TOL_ROUTE, 0._real64, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, &
    TOL_ROUTE, TOL_ROUTE, TOL_ROUTE, 0._real64, 0._real64, 0._real64, 0._real64, 0._real64, 0._real64, 0._real64]

! one reference and one particle on the same shells, with the particle's CTF modulus and noise variances
type :: oracle_polar_pair
    private
    integer                      :: pftsz = 0, nk = 0, kfrom = 0, box = 0
    complex(real64), allocatable :: ref(:,:), ptcl(:,:)
    real(real64),    allocatable :: ctf(:,:), sigma2(:)
    logical                      :: exists = .false.
  contains
    procedure :: new => pair_new
    procedure :: kill => pair_kill
    procedure :: set_weights => pair_set_weights
    procedure :: geometry => pair_geometry
    procedure :: arrays => pair_arrays
    procedure :: band => pair_band
    procedure :: nrots => pair_nrots
    procedure :: rotated => pair_rotated
    procedure :: wsq => pair_wsq
    procedure :: dist => pair_dist
    procedure :: cc => pair_cc
    procedure :: cc_weighted => pair_cc_weighted
    procedure :: dists_by_rings => pair_dists_by_rings
end type oracle_polar_pair

contains

    ! a pair from half rings ref(P, nk) and ptcl(P, nk), column i the shell kfrom + i - 1; unit CTF modulus and
    ! unit noise variances until set_weights
    subroutine pair_new( self, box, kfrom, ref, ptcl )
        class(oracle_polar_pair), intent(inout) :: self
        integer,                  intent(in)    :: box, kfrom
        complex(real64),          intent(in)    :: ref(:,:), ptcl(:,:)
        call self%kill()
        self%pftsz = size(ref, 1)
        self%nk    = size(ref, 2)
        self%kfrom = kfrom
        self%box   = box
        allocate(self%ref(self%pftsz, self%nk), self%ptcl(self%pftsz, self%nk), self%ctf(self%pftsz, self%nk), &
                 self%sigma2(self%nk))
        self%ref(:,:)  = ref
        self%ptcl(:,:) = ptcl
        self%ctf    = 1._real64
        self%sigma2 = 1._real64
        self%exists = .true.
    end subroutine pair_new

    ! release the arrays; idempotent
    subroutine pair_kill( self )
        class(oracle_polar_pair), intent(inout) :: self
        if( .not. self%exists ) return
        deallocate(self%ref, self%ptcl, self%ctf, self%sigma2)
        self%pftsz  = 0
        self%nk     = 0
        self%exists = .false.
    end subroutine pair_kill

    ! the particle's CTF modulus ctf(P, nk), non-negative, and the noise variances sigma2(nk) of its half set,
    ! in the shapes of the pair; nothing is done before new
    subroutine pair_set_weights( self, ctf, sigma2 )
        class(oracle_polar_pair), intent(inout) :: self
        real(real64),             intent(in)    :: ctf(:,:), sigma2(:)
        if( .not. self%exists ) return
        self%ctf(:,:)  = ctf
        self%sigma2(:) = sigma2
    end subroutine pair_set_weights

    ! [pftsz, first shell, last shell, box]
    pure function pair_geometry( self ) result(g)
        class(oracle_polar_pair), intent(in) :: self
        integer :: g(4)
        g = [self%pftsz, self%kfrom, self%kfrom + self%nk - 1, self%box]
    end function pair_geometry

    ! copies of the pair's arrays
    subroutine pair_arrays( self, ref, ptcl, ctf, sigma2 )
        class(oracle_polar_pair),     intent(in)  :: self
        complex(real64), allocatable, intent(out) :: ref(:,:), ptcl(:,:)
        real(real64),    allocatable, intent(out) :: ctf(:,:), sigma2(:)
        allocate(ref(self%pftsz, self%nk), ptcl(self%pftsz, self%nk), ctf(self%pftsz, self%nk), sigma2(self%nk))
        ref    = self%ref
        ptcl   = self%ptcl
        ctf    = self%ctf
        sigma2 = self%sigma2
    end subroutine pair_arrays

    ! the pair restricted to the shells up to kstop
    subroutine pair_band( self, kstop, sub )
        class(oracle_polar_pair), intent(in)    :: self
        integer,                  intent(in)    :: kstop
        type(oracle_polar_pair),  intent(inout) :: sub
        integer :: nb
        nb = kstop - self%kfrom + 1
        call sub%new(self%box, self%kfrom, self%ref(:, 1:nb), self%ptcl(:, 1:nb))
        call sub%set_weights(self%ctf(:, 1:nb), self%sigma2(1:nb))
    end subroutine pair_band

    ! the number of rotations, twice pftsz
    pure function pair_nrots( self ) result(n)
        class(oracle_polar_pair), intent(in) :: self
        integer :: n
        n = 2 * self%pftsz
    end function pair_nrots

    ! the half ring of the shifted, then rotated reference: sample p reads the full ring of S A at
    ! p - (irot - 1), a wrapped sample being the conjugate of the product
    pure function pair_rotated( self, irot, shift ) result(a)
        class(oracle_polar_pair), intent(in) :: self
        integer,                  intent(in) :: irot
        real(real64),             intent(in) :: shift(2)
        complex(real64) :: a(self%pftsz, self%nk)
        integer         :: p, i, q, k
        do i = 1, self%nk
            k = self%kfrom + i - 1
            do p = 1, self%pftsz
                q = 1 + modulo(p - irot, self%nrots())
                if( q <= self%pftsz )then
                    a(p, i) = shift_phase(self, q, k, shift) * self%ref(q, i)
                else
                    a(p, i) = conjg(shift_phase(self, q - self%pftsz, k, shift) * self%ref(q - self%pftsz, i))
                endif
            end do
        end do
    end function pair_rotated

    ! the particle's weighted power, sum over shells of (k / sigma2) sum over samples of |X|**2
    pure function pair_wsq( self ) result(w)
        class(oracle_polar_pair), intent(in) :: self
        real(real64) :: w
        integer      :: i
        w = 0._real64
        do i = 1, self%nk
            w = w + shell_weight(self, i) * sum(abs(self%ptcl(:, i))**2)
        end do
    end function pair_wsq

    ! the Euclidean loss at rotation irot and shift: the weighted sum of |C R(S A) - X|**2 over the particle's
    ! weighted power, unclamped; NaN when that power is not positive
    pure function pair_dist( self, irot, shift ) result(l)
        class(oracle_polar_pair), intent(in) :: self
        integer,                  intent(in) :: irot
        real(real64),             intent(in) :: shift(2)
        real(real64)    :: l, num, wsq
        complex(real64) :: a(self%pftsz, self%nk)
        integer         :: i
        a   = self%rotated(irot, shift)
        num = 0._real64
        do i = 1, self%nk
            num = num + shell_weight(self, i) * sum(abs(self%ctf(:, i) * a(:, i) - self%ptcl(:, i))**2)
        end do
        wsq = self%wsq()
        if( wsq > 0._real64 )then
            l = num / wsq
        else
            l = ieee_value(l, ieee_quiet_nan)
        endif
    end function pair_dist

    ! the correlation without shell weights, unclamped; NaN when a power is not positive
    pure function pair_cc( self, irot, shift ) result(cc)
        class(oracle_polar_pair), intent(in) :: self
        integer,                  intent(in) :: irot
        real(real64),             intent(in) :: shift(2)
        real(real64) :: cc
        cc = correlation(self, irot, shift, .false.)
    end function pair_cc

    ! the correlation with every shell's terms weighted by its radius k, unclamped
    pure function pair_cc_weighted( self, irot, shift ) result(cc)
        class(oracle_polar_pair), intent(in) :: self
        integer,                  intent(in) :: irot
        real(real64),             intent(in) :: shift(2)
        real(real64) :: cc
        cc = correlation(self, irot, shift, .true.)
    end function pair_cc_weighted

    ! the Euclidean loss at every rotation by ring transforms: rings [z, conj(z)] of length N, the spectrum
    ! c = sum of w (FT(C**2) conj(FT(|A|**2)) - 2 FT(X C) conj(FT(S A))) on the first P + 1 bins, completed as a
    ! real signal's, and L = 1 + r / (2 N wsq) with r the unnormalised inverse
    function pair_dists_by_rings( self, shift ) result(l)
        class(oracle_polar_pair), intent(in) :: self
        real(real64),             intent(in) :: shift(2)
        real(real64)    :: l(2*self%pftsz), wsq
        complex(real64) :: c(2*self%pftsz), fc2(2*self%pftsz), fa2(2*self%pftsz), fxc(2*self%pftsz), fsa(2*self%pftsz)
        complex(real64) :: sa(self%pftsz), xc(self%pftsz)
        integer         :: i, p, b, n, np
        np = self%pftsz
        n  = 2 * np
        c  = CZERO
        do i = 1, self%nk
            do p = 1, np
                sa(p) = shift_phase(self, p, self%kfrom + i - 1, shift) * self%ref(p, i)
            end do
            xc  = self%ptcl(:, i) * self%ctf(:, i)
            fc2 = oracle_dft_1d(cmplx([self%ctf(:, i)**2, self%ctf(:, i)**2], 0._real64, real64))
            fa2 = oracle_dft_1d(cmplx([abs(self%ref(:, i))**2, abs(self%ref(:, i))**2], 0._real64, real64))
            fxc = oracle_dft_1d([xc, conjg(xc)])
            fsa = oracle_dft_1d([sa, conjg(sa)])
            c(1:np+1) = c(1:np+1) + shell_weight(self, i) * (fc2(1:np+1) * conjg(fa2(1:np+1)) - &
                                                               2._real64 * fxc(1:np+1) * conjg(fsa(1:np+1)))
        end do
        do b = 2, np
            c(n+2-b) = conjg(c(b))
        end do
        wsq = self%wsq()
        if( wsq > 0._real64 )then
            l = 1._real64 + real(n, real64) * real(oracle_idft_1d(c)) / (2._real64 * real(n, real64) * wsq)
        else
            l = ieee_value(wsq, ieee_quiet_nan)
        endif
    end function pair_dists_by_rings

    ! the generic pair of the fixture: size isize, reference iref, particle iptcl (each 1 or 2), with the
    ! particle's CTF modulus and variances set
    subroutine oracle_polar_fixture( isize, iref, iptcl, pair )
        integer,                 intent(in)    :: isize, iref, iptcl
        type(oracle_polar_pair), intent(inout) :: pair
        integer :: sz(4)
        sz = SIZES(:, isize)
        call pair%new(sz(4), sz(2), fixture_ring(sz, REF_PTS(:, :, iref), 0, [0._real64, 0._real64]), &
                      fixture_ptcl(sz, iptcl))
        call pair%set_weights(fixture_ctf(sz, iptcl), fixture_sigma2(sz, iptcl))
    end subroutine oracle_polar_fixture

    ! the score of a distance, exp(-max(0, L)); a NaN distance has a NaN score
    elemental function oracle_polar_score( dist ) result(s)
        real(real64), intent(in) :: dist
        real(real64) :: s
        if( ieee_is_nan(dist) )then
            s = dist
        else
            s = exp(-max(0._real64, dist))
        endif
    end function oracle_polar_score

    ! whether a distance is valid: not above -log(1e-10); a NaN is not
    elemental function oracle_polar_valid( dist ) result(ok)
        real(real64), intent(in) :: dist
        logical :: ok
        ok = .false.
        if( .not. ieee_is_nan(dist) ) ok = dist <= DIST_LIMIT
    end function oracle_polar_valid

    ! a correlation as its callers keep it: a negative value becomes zero, a NaN stays
    elemental function oracle_polar_clamp( cc ) result(c)
        real(real64), intent(in) :: cc
        real(real64) :: c
        if( ieee_is_nan(cc) )then
            c = cc
        else
            c = max(0._real64, cc)
        endif
    end function oracle_polar_clamp

    ! the in-plane angle of rotation irot in degrees, (irot - 1) 360 / nrots
    pure function oracle_polar_angle( irot, nrots ) result(deg)
        integer, intent(in) :: irot, nrots
        real(real64) :: deg
        deg = real(irot - 1, real64) * 360._real64 / real(nrots, real64)
    end function oracle_polar_angle

    ! the matrix M of rotation irot, rows [c, s] and [-s, c] at its in-plane angle: a shift u in the particle's
    ! frame is the shift matmul(M, u) in the reference's frame
    pure function oracle_polar_frame( irot, nrots ) result(m)
        integer, intent(in) :: irot, nrots
        real(real64) :: m(2, 2), angle
        angle   = TWOPI * real(irot - 1, real64) / real(nrots, real64)
        m(1, 1) = cos(angle)
        m(1, 2) = sin(angle)
        m(2, 1) = -sin(angle)
        m(2, 2) = cos(angle)
    end function oracle_polar_frame

    ! the in-plane best of a table of distances: the first strict minimum; 0 for an empty table
    pure function oracle_polar_best_dist( dists ) result(irot)
        real(real64), intent(in) :: dists(:)
        integer :: irot, i
        irot = min(1, size(dists))
        do i = 2, size(dists)
            if( dists(i) < dists(irot) ) irot = i
        end do
    end function oracle_polar_best_dist

    ! the in-plane best of a table of scores or correlations: the first maximum; 0 for an empty table
    pure function oracle_polar_best_score( scores ) result(irot)
        real(real64), intent(in) :: scores(:)
        integer :: irot
        irot = first_maximum(scores)
    end function oracle_polar_best_score

    ! a reference keeps its larger score and that score's tag; an equal score does not replace the kept one
    elemental subroutine oracle_polar_store( score, tag, kept_score, kept_tag )
        real(real64), intent(in)    :: score
        integer,      intent(in)    :: tag
        real(real64), intent(inout) :: kept_score
        integer,      intent(inout) :: kept_tag
        if( score > kept_score )then
            kept_score = score
            kept_tag   = tag
        endif
    end subroutine oracle_polar_store

    ! the reference with the largest score, the lowest index among equals
    pure function oracle_polar_greedy( scores ) result(iref)
        real(real64), intent(in) :: scores(:)
        integer :: iref
        iref = first_maximum(scores)
    end function oracle_polar_greedy

    ! the k references with the largest scores in descending order, the lower index first among equals; zeros
    ! beyond the number of references
    pure function oracle_polar_best_k( scores, k ) result(irefs)
        real(real64), intent(in) :: scores(:)
        integer,      intent(in) :: k
        integer :: irefs(k), i, j, best
        logical :: taken(size(scores))
        taken = .false.
        irefs = 0
        do j = 1, min(k, size(scores))
            best = 0
            do i = 1, size(scores)
                if( taken(i) ) cycle
                if( best == 0 )then
                    best = i
                else if( scores(i) > scores(best) )then
                    best = i
                endif
            end do
            irefs(j)    = best
            taken(best) = .true.
        end do
    end function oracle_polar_best_k

    ! stochastic hill climbing: the references are scored in the given order, a permutation of all of them, and
    ! the first whose score is strictly above prev_corr wins; if none is, the greedy rule decides over all.
    ! nevals counts those scored
    pure subroutine oracle_polar_shc( scores, order, prev_corr, iref, nevals )
        real(real64), intent(in)  :: scores(:)
        integer,      intent(in)  :: order(:)
        real(real64), intent(in)  :: prev_corr
        integer,      intent(out) :: iref, nevals
        integer :: j
        do j = 1, size(order)
            if( scores(order(j)) > prev_corr )then
                iref   = order(j)
                nevals = j
                return
            endif
        end do
        iref   = oracle_polar_greedy(scores)
        nevals = size(order)
    end subroutine oracle_polar_shc

    ! the checks against closed forms, hand values and the ring-transform route, as named largest errors and
    ! their limits; a limit is not applied here
    subroutine oracle_polar_selfcheck( labels, errors, limits )
        character(len=:), allocatable, intent(out) :: labels(:)
        real(real64),     allocatable, intent(out) :: errors(:), limits(:)
        integer :: isize
        allocate(character(len=LABEL_LEN) :: labels(NCHECK))
        allocate(errors(NCHECK), limits(NCHECK))
        labels = CHECK_NAMES
        limits = CHECK_LIMITS
        errors = 0._real64
        do isize = 1, NSIZE
            call check_hand(SIZES(:, isize), errors(1:3))
            call check_planted(SIZES(:, isize), errors(4:11))
            call check_scaled(SIZES(:, isize), errors(12:14))
            call check_routes(isize, errors(15:16))
            call check_band(isize, errors(25))
        end do
        call check_scalars(errors(17:18))
        call check_reductions(errors(19:23))
        call check_guards(errors(24))
    end subroutine oracle_polar_selfcheck

    ! the weight of column i's shell in the Euclidean loss: its radius over its noise variance
    pure function shell_weight( self, i ) result(w)
        class(oracle_polar_pair), intent(in) :: self
        integer,                  intent(in) :: i
        real(real64) :: w
        w = real(self%kfrom + i - 1, real64) / self%sigma2(i)
    end function shell_weight

    ! the shift's phase at sample p of shell k, at the reference's own angle
    pure function shift_phase( self, p, k, shift ) result(s)
        class(oracle_polar_pair), intent(in) :: self
        integer,                  intent(in) :: p, k
        real(real64),             intent(in) :: shift(2)
        complex(real64) :: s
        real(real64)    :: theta, arg
        theta = TWOPI * real(p - 1, real64) / real(self%nrots(), real64)
        arg   = TWOPI * real(k, real64) / real(self%box, real64) * (shift(1) * sin(theta) - shift(2) * cos(theta))
        s     = cmplx(cos(arg), sin(arg), real64)
    end function shift_phase

    ! sum Re(conj(X) C R(S A)) over the root of the reference's power sum C**2 |R(A)|**2 times the particle's
    ! power, each shell's terms weighted by its radius when weighted is set
    pure function correlation( self, irot, shift, weighted ) result(cc)
        class(oracle_polar_pair), intent(in) :: self
        integer,                  intent(in) :: irot
        real(real64),             intent(in) :: shift(2)
        logical,                  intent(in) :: weighted
        real(real64)    :: cc, cross, refpow, ptclpow, w
        complex(real64) :: a(self%pftsz, self%nk), a0(self%pftsz, self%nk)
        integer         :: i
        a       = self%rotated(irot, shift)
        a0      = self%rotated(irot, [0._real64, 0._real64])
        cross   = 0._real64
        refpow  = 0._real64
        ptclpow = 0._real64
        do i = 1, self%nk
            w = 1._real64
            if( weighted ) w = real(self%kfrom + i - 1, real64)
            cross   = cross + w * sum(real(conjg(self%ptcl(:, i)) * self%ctf(:, i) * a(:, i)))
            refpow  = refpow + w * sum(self%ctf(:, i)**2 * abs(a0(:, i))**2)
            ptclpow = ptclpow + w * sum(abs(self%ptcl(:, i))**2)
        end do
        if( refpow > 0._real64 .and. ptclpow > 0._real64 )then
            cc = cross / sqrt(refpow * ptclpow)
        else
            cc = ieee_value(cc, ieee_quiet_nan)
        endif
    end function correlation

    ! the index of the first maximum; 0 for an empty table
    pure function first_maximum( x ) result(imax)
        real(real64), intent(in) :: x(:)
        integer :: imax, i
        imax = min(1, size(x))
        do i = 2, size(x)
            if( x(i) > x(imax) ) imax = i
        end do
    end function first_maximum

    ! the fixture's ring of point sources in closed form, on the half ring of size sz: the points displaced by
    ! -shift, the ring evaluated turn rotation steps back. It uses no extension, index shift or phase of the pair
    pure function fixture_ring( sz, pts, turn, shift ) result(z)
        integer,      intent(in) :: sz(4), turn
        real(real64), intent(in) :: pts(:,:), shift(2)
        complex(real64) :: z(sz(1), sz(3))
        real(real64)    :: theta, kappa, arg
        integer         :: p, i, j, k
        z = CZERO
        do i = 1, sz(3)
            k     = sz(2) + i - 1
            kappa = TWOPI * real(k, real64) / real(sz(4), real64)
            do p = 1, sz(1)
                theta = TWOPI * real(p - 1 - turn, real64) / real(2 * sz(1), real64)
                do j = 1, size(pts, 2)
                    arg     = -kappa * ((pts(1, j) - shift(1)) * sin(theta) - (pts(2, j) - shift(2)) * cos(theta))
                    z(p, i) = z(p, i) + pts(3, j) * cmplx(cos(arg), sin(arg), real64)
                end do
                z(p, i) = z(p, i) * 4._real64 / real(4 + k, real64)
            end do
        end do
    end function fixture_ring

    ! the CTF modulus of particle iptcl: positive, period pftsz in the sample, varying with the shell
    pure function fixture_ctf( sz, iptcl ) result(c)
        integer, intent(in) :: sz(4), iptcl
        real(real64) :: c(sz(1), sz(3)), theta
        integer      :: p, i
        do i = 1, sz(3)
            do p = 1, sz(1)
                theta   = TWOPI * real(p - 1, real64) / real(2 * sz(1), real64)
                c(p, i) = 0.55_real64 + 0.35_real64 * cos(2._real64 * theta - 0.3_real64 * real(sz(2) + i - 1, real64) - &
                                                         0.9_real64 * real(iptcl - 1, real64))
            end do
        end do
    end function fixture_ctf

    ! the noise variances of particle iptcl, growing with the shell
    pure function fixture_sigma2( sz, iptcl ) result(s)
        integer, intent(in) :: sz(4), iptcl
        real(real64) :: s(sz(3))
        integer      :: i, k
        do i = 1, sz(3)
            k = sz(2) + i - 1
            if( iptcl == 1 )then
                s(i) = 0.5_real64 + 0.1_real64 * real(k, real64)
            else
                s(i) = 0.8_real64 + 0.05_real64 * real(k * k, real64)
            endif
        end do
    end function fixture_sigma2

    ! generic particle iptcl: its CTF modulus times its reference, rotated and shifted, plus clutter
    pure function fixture_ptcl( sz, iptcl ) result(x)
        integer, intent(in) :: sz(4), iptcl
        complex(real64) :: x(sz(1), sz(3))
        x = fixture_ctf(sz, iptcl) * fixture_ring(sz, REF_PTS(:, :, iptcl), PTCL_TURN(iptcl), PTCL_SHIFT(:, iptcl)) + &
            CLUTTER_AMP * fixture_ring(sz, CLUTTER_PTS, CLUTTER_TURN(iptcl), [0._real64, 0._real64])
    end function fixture_ptcl

    ! counts, the shift's phase at the two samples where it has a hand value, and a one-sample reference whose
    ! rotated copies are stated by hand
    subroutine check_hand( sz, err )
        integer,      intent(in)    :: sz(4)
        real(real64), intent(inout) :: err(3)
        type(oracle_polar_pair) :: pair
        complex(real64)         :: ones(sz(1), sz(3)), one(sz(1), sz(3)), a(sz(1), sz(3)), hand(sz(1), sz(3))
        complex(real64)         :: z, at_zero, at_quarter
        real(real64)            :: kappa
        integer                 :: np, i, t, nbad
        integer                 :: irots(6), where_p(6)
        logical                 :: flipped(6)
        np   = sz(1)
        ones = (1._real64, 0._real64)
        call pair%new(sz(4), sz(2), ones, ones)
        ! counts: rotations, the geometry and the table's shape
        nbad = 0
        if( pair%nrots() /= 2 * np ) nbad = nbad + 1
        if( any(pair%geometry() /= [np, sz(2), sz(2) + sz(3) - 1, sz(4)]) ) nbad = nbad + 1
        if( any(shape(pair%rotated(1, PLANT_SHIFT)) /= [np, sz(3)]) ) nbad = nbad + 1
        if( size(pair%dists_by_rings(PLANT_SHIFT)) /= 2 * np ) nbad = nbad + 1
        err(1) = max(err(1), real(nbad, real64))
        ! on a unit reference the table is the phase: exp(-i kappa y) at the first sample, where the angle is
        ! zero, and exp(+i kappa x) a quarter turn on
        a = pair%rotated(1, PLANT_SHIFT)
        do i = 1, sz(3)
            kappa      = TWOPI * real(sz(2) + i - 1, real64) / real(sz(4), real64)
            at_zero    = exp(cmplx(0._real64, -kappa * PLANT_SHIFT(2), real64))
            at_quarter = exp(cmplx(0._real64, kappa * PLANT_SHIFT(1), real64))
            err(2)     = max(err(2), oracle_finite_or_inf(abs(a(1, i) - at_zero)), &
                             oracle_finite_or_inf(abs(a(np/2+1, i) - at_quarter)))
        end do
        ! a reference that is z at sample 3 and zero elsewhere, rotated without a shift: the sample it lands on
        ! and whether it arrives conjugated, for six rotations
        z         = (1._real64, 2._real64)
        one       = CZERO
        one(3, :) = z
        call pair%new(sz(4), sz(2), one, one)
        irots   = [1, 4, np + 1, np + 4, 2 * np, np - 1]
        where_p = [3, 6, 3, 6, 2, 1]
        flipped = [.false., .false., .true., .true., .false., .true.]
        nbad    = 0
        do t = 1, 6
            hand = CZERO
            if( flipped(t) )then
                hand(where_p(t), :) = conjg(z)
            else
                hand(where_p(t), :) = z
            endif
            a    = pair%rotated(irots(t), [0._real64, 0._real64])
            nbad = nbad + count(.not. (abs(a - hand) <= 0._real64))
        end do
        err(3) = max(err(3), real(nbad, real64))
        call pair%kill()
    end subroutine check_hand

    ! particles planted through the closed form: the unrotated copy, two rotations, a shift, a rotation with a
    ! shift, and a shift in the particle's frame; the table R(S A), the loss, the correlations and the best index
    subroutine check_planted( sz, err )
        integer,      intent(in)    :: sz(4)
        real(real64), intent(inout) :: err(8)
        type(oracle_polar_pair) :: pair
        complex(real64)         :: x(sz(1), sz(3)), table(sz(1), sz(3))
        real(real64)            :: dists(2*sz(1)), ccs(2*sz(1)), zero(2), s(2), kappa, theta
        integer                 :: iref, t, irot, n, p, i, nbad
        zero = 0._real64
        do iref = 1, 2
            ! the unrotated copy: zero loss; unit correlations here and at every planted rotation and shift below
            call plant(pair, sz, iref, fixture_ring(sz, REF_PTS(:, :, iref), 0, zero))
            err(1) = max(err(1), table_error(pair%rotated(1, zero), fixture_ring(sz, REF_PTS(:, :, iref), 0, zero)))
            err(2) = max(err(2), root_loss(pair%dist(1, zero)))
            err(3) = max(err(3), oracle_finite_or_inf(abs(1._real64 - pair%cc(1, zero))), &
                         oracle_finite_or_inf(abs(1._real64 - pair%cc_weighted(1, zero))))
            ! a rotated copy: zero loss at the planted rotation, which is the best of every objective
            nbad = 0
            do t = 1, 2
                n = PLANT_TURN(t)
                call plant(pair, sz, iref, fixture_ring(sz, REF_PTS(:, :, iref), n, zero))
                table  = pair%rotated(n + 1, zero)
                err(1) = max(err(1), table_error(table, fixture_ring(sz, REF_PTS(:, :, iref), n, zero)))
                do irot = 1, 2 * sz(1)
                    dists(irot) = pair%dist(irot, zero)
                    ccs(irot)   = pair%cc(irot, zero)
                end do
                err(4) = max(err(4), root_loss(dists(n + 1)))
                err(3) = max(err(3), oracle_finite_or_inf(abs(1._real64 - ccs(n + 1))), &
                             oracle_finite_or_inf(abs(1._real64 - pair%cc_weighted(n + 1, zero))))
                if( oracle_polar_best_dist(dists) /= n + 1 ) nbad = nbad + 1
                if( oracle_polar_best_score(oracle_polar_score(dists)) /= n + 1 ) nbad = nbad + 1
                if( oracle_polar_best_score(ccs) /= n + 1 ) nbad = nbad + 1
            end do
            err(5) = max(err(5), real(nbad, real64))
            ! a shifted copy
            call plant(pair, sz, iref, fixture_ring(sz, REF_PTS(:, :, iref), 0, PLANT_SHIFT))
            err(1) = max(err(1), table_error(pair%rotated(1, PLANT_SHIFT), &
                                             fixture_ring(sz, REF_PTS(:, :, iref), 0, PLANT_SHIFT)))
            err(6) = max(err(6), root_loss(pair%dist(1, PLANT_SHIFT)), &
                         oracle_finite_or_inf(abs(1._real64 - pair%cc(1, PLANT_SHIFT))), &
                         oracle_finite_or_inf(abs(1._real64 - pair%cc_weighted(1, PLANT_SHIFT))))
            ! shifted, then rotated above pftsz
            n = PLANT_TURN(2)
            call plant(pair, sz, iref, fixture_ring(sz, REF_PTS(:, :, iref), n, PLANT_SHIFT))
            err(1) = max(err(1), table_error(pair%rotated(n + 1, PLANT_SHIFT), &
                                             fixture_ring(sz, REF_PTS(:, :, iref), n, PLANT_SHIFT)))
            err(7) = max(err(7), root_loss(pair%dist(n + 1, PLANT_SHIFT)))
            err(3) = max(err(3), oracle_finite_or_inf(abs(1._real64 - pair%cc(n + 1, PLANT_SHIFT))), &
                         oracle_finite_or_inf(abs(1._real64 - pair%cc_weighted(n + 1, PLANT_SHIFT))))
            ! rotated, then shifted by u in the particle's frame, the phase at the particle's own angle: the
            ! same particle as the shift matmul(M, u) in the reference's frame before the rotation
            n = PLANT_TURN(1)
            x = fixture_ring(sz, REF_PTS(:, :, iref), n, zero)
            do i = 1, sz(3)
                kappa = TWOPI * real(sz(2) + i - 1, real64) / real(sz(4), real64)
                do p = 1, sz(1)
                    theta   = TWOPI * real(p - 1, real64) / real(2 * sz(1), real64)
                    x(p, i) = x(p, i) * exp(cmplx(0._real64, kappa * (PLANT_UFRAME(1) * sin(theta) - &
                                                                     PLANT_UFRAME(2) * cos(theta)), real64))
                end do
            end do
            call plant(pair, sz, iref, x)
            s      = matmul(oracle_polar_frame(n + 1, 2 * sz(1)), PLANT_UFRAME)
            err(8) = max(err(8), root_loss(pair%dist(n + 1, s)), table_error(pair%rotated(n + 1, s), x))
        end do
        call pair%kill()
    end subroutine check_planted

    ! the pair of reference iref and the particle that is its CTF modulus times the given model
    subroutine plant( pair, sz, iref, model )
        type(oracle_polar_pair), intent(inout) :: pair
        integer,                 intent(in)    :: sz(4), iref
        complex(real64),         intent(in)    :: model(:,:)
        call pair%new(sz(4), sz(2), fixture_ring(sz, REF_PTS(:, :, iref), 0, [0._real64, 0._real64]), &
                      fixture_ctf(sz, iref) * model)
        call pair%set_weights(fixture_ctf(sz, iref), fixture_sigma2(sz, iref))
    end subroutine plant

    ! the copy scaled by a factor per shell, SCALE_EVEN or SCALE_ODD: the loss and the two correlations have
    ! closed forms in the shells' powers sum of C**2 |A|**2, which differ between the weightings
    subroutine check_scaled( sz, err )
        integer,      intent(in)    :: sz(4)
        real(real64), intent(inout) :: err(3)
        type(oracle_polar_pair) :: pair
        complex(real64)         :: ref(sz(1), sz(3)), x(sz(1), sz(3))
        real(real64)            :: ctf(sz(1), sz(3)), sigma2(sz(3)), pow(sz(3)), c(sz(3)), rk(sz(3)), zero(2)
        real(real64)            :: l_ref, cc_ref, ccw_ref
        integer                 :: iref, i
        zero = 0._real64
        do iref = 1, 2
            ref    = fixture_ring(sz, REF_PTS(:, :, iref), 0, zero)
            ctf    = fixture_ctf(sz, iref)
            sigma2 = fixture_sigma2(sz, iref)
            do i = 1, sz(3)
                rk(i)  = real(sz(2) + i - 1, real64)
                c(i)   = merge(SCALE_EVEN, SCALE_ODD, modulo(sz(2) + i - 1, 2) == 0)
                pow(i) = sum(ctf(:, i)**2 * abs(ref(:, i))**2)
                x(:, i) = c(i) * ctf(:, i) * ref(:, i)
            end do
            call pair%new(sz(4), sz(2), ref, x)
            call pair%set_weights(ctf, sigma2)
            l_ref   = sum(rk / sigma2 * (1._real64 - c)**2 * pow) / sum(rk / sigma2 * c**2 * pow)
            cc_ref  = sum(c * pow) / sqrt(sum(pow) * sum(c**2 * pow))
            ccw_ref = sum(rk * c * pow) / sqrt(sum(rk * pow) * sum(rk * c**2 * pow))
            err(1)  = max(err(1), oracle_finite_or_inf(abs(pair%dist(1, zero) - l_ref) / abs(l_ref)))
            err(2)  = max(err(2), oracle_finite_or_inf(abs(pair%cc(1, zero) - cc_ref) / abs(cc_ref)))
            err(3)  = max(err(3), oracle_finite_or_inf(abs(pair%cc_weighted(1, zero) - ccw_ref) / abs(ccw_ref)))
        end do
        call pair%kill()
    end subroutine check_scaled

    ! the generic pairs at three shifts: the direct loss at every rotation against the ring-transform route, and
    ! the bound on both correlations
    subroutine check_routes( isize, err )
        integer,      intent(in)    :: isize
        real(real64), intent(inout) :: err(2)
        type(oracle_polar_pair) :: pair
        real(real64)            :: dists(2*SIZES(1, isize)), shifts(2, 3)
        integer                 :: iref, iptcl, is, irot
        shifts(:, 1)   = 0._real64
        shifts(:, 2:3) = PTCL_SHIFT
        do iref = 1, 2
            do iptcl = 1, 2
                call oracle_polar_fixture(isize, iref, iptcl, pair)
                do is = 1, 3
                    do irot = 1, size(dists)
                        dists(irot) = pair%dist(irot, shifts(:, is))
                        err(2)      = max(err(2), bound_excess(pair%cc(irot, shifts(:, is))), &
                                          bound_excess(pair%cc_weighted(irot, shifts(:, is))))
                    end do
                    err(1) = max(err(1), oracle_rel_error(cmplx(dists, 0._real64, real64), &
                                                          cmplx(pair%dists_by_rings(shifts(:, is)), 0._real64, real64)))
                end do
            end do
        end do
        ! the bound where the correlation reaches one: a particle that is its CTF modulus times its reference
        call pair%new(SIZES(4, isize), SIZES(2, isize), fixture_ring(SIZES(:, isize), REF_PTS(:, :, 1), 0, shifts(:, 1)), &
                      fixture_ctf(SIZES(:, isize), 1) * fixture_ring(SIZES(:, isize), REF_PTS(:, :, 1), 0, shifts(:, 1)))
        call pair%set_weights(fixture_ctf(SIZES(:, isize), 1), fixture_sigma2(SIZES(:, isize), 1))
        err(2) = max(err(2), bound_excess(pair%cc(1, shifts(:, 1))), bound_excess(pair%cc_weighted(1, shifts(:, 1))))
        call pair%kill()
    end subroutine check_routes

    ! the score, the clamp and the validity of a distance; the in-plane angle and the frame matrix by hand
    subroutine check_scalars( err )
        real(real64), intent(inout) :: err(2)
        real(real64) :: m(2, 2), e(2, 2), u(2), nan
        integer      :: nbad
        nan  = ieee_value(nan, ieee_quiet_nan)
        nbad = 0
        if( .not. oracle_polar_valid(23._real64) ) nbad = nbad + 1
        if( oracle_polar_valid(23.1_real64) ) nbad = nbad + 1
        if( .not. oracle_polar_valid(DIST_LIMIT) ) nbad = nbad + 1
        if( oracle_polar_valid(nan) ) nbad = nbad + 1
        if( .not. ieee_is_nan(oracle_polar_score(nan)) ) nbad = nbad + 1
        if( .not. ieee_is_nan(oracle_polar_clamp(nan)) ) nbad = nbad + 1
        err(1) = max(err(1), real(nbad, real64), &
                     oracle_finite_or_inf(abs(oracle_polar_score(0.5_real64) - 0.60653065971263342_real64)), &
                     oracle_finite_or_inf(abs(oracle_polar_score(-0.3_real64) - 1._real64)), &
                     oracle_finite_or_inf(abs(oracle_polar_clamp(-0.3_real64))), &
                     oracle_finite_or_inf(abs(oracle_polar_clamp(0.4_real64) - 0.4_real64)), &
                     oracle_finite_or_inf(abs(DIST_LIMIT - 23.025850929940457_real64)))
        ! rotation 9 of 32 is a quarter turn: M has rows [0, 1] and [-1, 0], and maps u = (1, 0) to (0, -1)
        m      = oracle_polar_frame(9, 32)
        u      = matmul(m, [1._real64, 0._real64])
        e      = oracle_polar_frame(1, 24)
        err(2) = max(err(2), oracle_finite_or_inf(abs(oracle_polar_angle(1, 32))), &
                     oracle_finite_or_inf(abs(oracle_polar_angle(17, 32) - 180._real64)), &
                     oracle_finite_or_inf(abs(oracle_polar_angle(2, 32) - 11.25_real64)), &
                     oracle_finite_or_inf(abs(oracle_polar_angle(24, 24) - 345._real64)), &
                     oracle_finite_or_inf(abs(m(1, 1)) + abs(m(1, 2) - 1._real64) + abs(m(2, 1) + 1._real64) + abs(m(2, 2))), &
                     oracle_finite_or_inf(abs(u(1)) + abs(u(2) + 1._real64)), &
                     oracle_finite_or_inf(abs(e(1, 1) - 1._real64) + abs(e(1, 2)) + abs(e(2, 1)) + abs(e(2, 2) - 1._real64)))
    end subroutine check_scalars

    ! the reductions on hand-made tables with ties
    subroutine check_reductions( err )
        real(real64), intent(inout) :: err(5)
        real(real64) :: kept(3)
        integer      :: tags(3), iref, nevals, nbad
        ! the in-plane best: the first of two equal minima; below zero the distance and the score disagree
        nbad = 0
        if( oracle_polar_best_dist([0.4_real64, 0.2_real64, 0.2_real64, 0.5_real64]) /= 2 ) nbad = nbad + 1
        if( oracle_polar_best_score([0.4_real64, 0.7_real64, 0.7_real64, 0.5_real64]) /= 2 ) nbad = nbad + 1
        if( oracle_polar_best_dist([-0.1_real64, -0.3_real64, 0.2_real64]) /= 2 ) nbad = nbad + 1
        if( oracle_polar_best_score(oracle_polar_score([-0.1_real64, -0.3_real64, 0.2_real64])) /= 1 ) nbad = nbad + 1
        err(1) = real(nbad, real64)
        ! the store: an equal score does not replace, a larger one does, with its tag
        kept = 0.5_real64
        tags = 7
        call oracle_polar_store([0.5_real64, 0.6_real64, 0.4_real64], [1, 2, 3], kept, tags)
        err(2) = real(count(tags /= [7, 2, 7]) + &
                      count(.not. (abs(kept - [0.5_real64, 0.6_real64, 0.5_real64]) <= 0._real64)), real64)
        ! greedy: the lowest index among three equal maxima
        nbad = 0
        if( oracle_polar_greedy([0.2_real64, 0.7_real64, 0.7_real64, 0.1_real64, 0.7_real64]) /= 2 ) nbad = nbad + 1
        err(3) = real(nbad, real64)
        ! best k: descending, the lower index first among equals, zeros beyond the table
        err(4) = real(count(oracle_polar_best_k([0.5_real64, 0.9_real64, 0.5_real64, 0.9_real64, 0.1_real64, &
                                                 0.5_real64], 3) /= [2, 4, 1]) + &
                      count(oracle_polar_best_k([0.5_real64, 0.9_real64, 0.5_real64, 0.9_real64, 0.1_real64, &
                                                 0.5_real64], 5) /= [2, 4, 1, 3, 6]) + &
                      count(oracle_polar_best_k([0.3_real64, 0.8_real64], 3) /= [2, 1, 0]), real64)
        ! hill climbing: the first strictly above wins although a later one is larger; an equal score does not
        ! win; with none above every reference is scored and the greedy rule decides by index, not by visit
        nbad = 0
        call oracle_polar_shc([0.3_real64, 0.8_real64, 0.5_real64, 0.9_real64, 0.5_real64], [5, 1, 2, 4, 3], &
                              0.5_real64, iref, nevals)
        if( iref /= 2 .or. nevals /= 3 ) nbad = nbad + 1
        call oracle_polar_shc([0.3_real64, 0.8_real64, 0.5_real64, 0.9_real64, 0.5_real64], [5, 1, 2, 4, 3], &
                              0.95_real64, iref, nevals)
        if( iref /= 4 .or. nevals /= 5 ) nbad = nbad + 1
        call oracle_polar_shc([0.6_real64, 0.9_real64, 0.9_real64, 0.2_real64], [3, 4, 1, 2], 0.9_real64, iref, nevals)
        if( iref /= 2 .or. nevals /= 4 ) nbad = nbad + 1
        err(5) = real(nbad, real64)
    end subroutine check_reductions

    ! a zero particle or a zero reference has no defined objective: NaN, counted when it is not
    subroutine check_guards( err )
        real(real64), intent(inout) :: err
        type(oracle_polar_pair) :: pair
        complex(real64)         :: ref(SIZES(1, 1), SIZES(3, 1)), nothing(SIZES(1, 1), SIZES(3, 1))
        real(real64)            :: zero(2)
        integer                 :: nbad
        zero    = 0._real64
        ref     = fixture_ring(SIZES(:, 1), REF_PTS(:, :, 1), 0, zero)
        nothing = CZERO
        nbad    = 0
        call pair%new(SIZES(4, 1), SIZES(2, 1), ref, nothing)
        if( .not. ieee_is_nan(pair%dist(1, zero)) ) nbad = nbad + 1
        if( .not. ieee_is_nan(pair%cc(1, zero)) ) nbad = nbad + 1
        if( .not. ieee_is_nan(pair%cc_weighted(1, zero)) ) nbad = nbad + 1
        if( .not. all(ieee_is_nan(pair%dists_by_rings(zero))) ) nbad = nbad + 1
        call pair%new(SIZES(4, 1), SIZES(2, 1), nothing, ref)
        if( .not. ieee_is_nan(pair%cc(1, zero)) ) nbad = nbad + 1
        if( .not. ieee_is_nan(pair%cc_weighted(1, zero)) ) nbad = nbad + 1
        call pair%kill()
        err = real(nbad, real64)
    end subroutine check_guards

    ! a pair returns the arrays it was given, and its restriction to three shells returns their first three
    ! columns with the geometry of that band; mismatches by value
    subroutine check_band( isize, err )
        integer,      intent(in)    :: isize
        real(real64), intent(inout) :: err
        type(oracle_polar_pair)      :: pair, sub
        complex(real64), allocatable :: ref(:,:), ptcl(:,:), bref(:,:), bptcl(:,:)
        real(real64),    allocatable :: ctf(:,:), sigma2(:), bctf(:,:), bsigma2(:)
        complex(real64)              :: ref0(SIZES(1, isize), SIZES(3, isize)), ptcl0(SIZES(1, isize), SIZES(3, isize))
        real(real64)                 :: ctf0(SIZES(1, isize), SIZES(3, isize)), sigma0(SIZES(3, isize))
        integer                      :: sz(4), nbad
        sz     = SIZES(:, isize)
        ref0   = fixture_ring(sz, REF_PTS(:, :, 2), 0, [0._real64, 0._real64])
        ptcl0  = fixture_ptcl(sz, 1)
        ctf0   = fixture_ctf(sz, 1)
        sigma0 = fixture_sigma2(sz, 1)
        call pair%new(sz(4), sz(2), ref0, ptcl0)
        call pair%set_weights(ctf0, sigma0)
        call pair%arrays(ref, ptcl, ctf, sigma2)
        nbad = count(.not. (abs(ref - ref0) <= 0._real64)) + count(.not. (abs(ptcl - ptcl0) <= 0._real64)) + &
               count(.not. (abs(ctf - ctf0) <= 0._real64)) + count(.not. (abs(sigma2 - sigma0) <= 0._real64))
        call pair%band(sz(2) + 2, sub)
        call sub%arrays(bref, bptcl, bctf, bsigma2)
        if( any(sub%geometry() /= [sz(1), sz(2), sz(2) + 2, sz(4)]) ) nbad = nbad + 1
        if( any(shape(bref) /= [sz(1), 3]) .or. size(bsigma2) /= 3 )then
            nbad = nbad + 1
        else
            nbad = nbad + count(.not. (abs(bref - ref(:, 1:3)) <= 0._real64)) + &
                   count(.not. (abs(bptcl - ptcl(:, 1:3)) <= 0._real64)) + &
                   count(.not. (abs(bctf - ctf(:, 1:3)) <= 0._real64)) + &
                   count(.not. (abs(bsigma2 - sigma2(1:3)) <= 0._real64))
        endif
        call pair%kill()
        call sub%kill()
        err = max(err, real(nbad, real64))
    end subroutine check_band

    ! the largest difference of two tables relative to the reference table's largest magnitude
    pure function table_error( a, ref ) result(e)
        complex(real64), intent(in) :: a(:,:), ref(:,:)
        real(real64) :: e
        e = oracle_rel_error(reshape(a, [size(a)]), reshape(ref, [size(ref)]))
    end function table_error

    ! the root of a loss that should be zero, which is linear in the model's error; +Inf when not finite
    pure function root_loss( l ) result(e)
        real(real64), intent(in) :: l
        real(real64) :: e
        e = oracle_finite_or_inf(sqrt(abs(l)))
    end function root_loss

    ! how far a correlation lies outside [-1, 1]; +Inf when it is not finite
    pure function bound_excess( cc ) result(e)
        real(real64), intent(in) :: cc
        real(real64) :: e
        if( ieee_is_nan(cc) )then
            e = ieee_value(e, ieee_positive_inf)
        else
            e = max(0._real64, abs(cc) - 1._real64)
        endif
    end function bound_excess

end module mlxf_oracle_polar_objfun
