!@descr: transforms over several dimensions, the real ones' half-size dimension, the shifts and the frequencies against direct double-precision transforms
! Each transform runs on seeded (6, 5, 4) arrays, a batch of them along a fourth dimension, in several forms
! (dimensions given or not, in several orders, lengths that pad and truncate, the three norms) against a direct
! DFT in real64, one dimension after another. A result is judged by its largest error relative to
! max(1, the largest |reference| of the result): an element near a zero of a spectrum carries the rounding of the
! whole transform, so an element's own magnitude is no scale for it. The shifts are exact.
module mlxf_fft_nd_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                            MLX_DTYPES, MLX_FFT_NORMS, mlx_fft2, mlx_fftn, mlx_ifftn, mlx_rfft2, mlx_irfft2, mlx_rfftn, &
                            mlx_irfftn, mlx_fftshift, mlx_ifftshift, mlx_fftfreq, mlx_rfftfreq
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name, set_fixed_seed, bits_equal, &
                            judge_error, find_tolerance
use mlxf_test_defs,   only: ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED, ELEM_CEILING, FFT_TOLERANCES, FFT_NBATCH, &
                            elem_tolerance
use mlxf_test_reduce, only: nan_maxval, nan_max
implicit none
private
public :: run_all_fft_nd_tests

! the fixture's extents; a form with dimensions runs on a batch of fixtures along dimension 4
integer, parameter :: N1 = 6, N2 = 5, N3 = 4, NB = FFT_NBATCH
! half of each extent, rounded down: a shift's step, and one less than the size of a half spectrum
integer, parameter :: H1 = 3, H2 = 2, H3 = 2
! what a transform is: complex forward or inverse, real to its half spectrum, the half spectrum to real
integer, parameter :: T_FORWARD = 1, T_INVERSE = 2, T_REAL = 3, T_REAL_INVERSE = 4

! one way of calling a transform: nd dimensions (0: none given, every dimension of a rank-3 array), the lengths
! along them when has_n, and the norm
type :: fft_form
    integer :: nd = 0
    integer :: dims(3) = 0
    logical :: has_n = .false.
    integer :: n(3) = 0
    integer :: norm = 0
end type fft_form

! a transform under test: its public name, what it is, and whether its real input is passed as float64
type :: fft_case
    character(len=10) :: name       = ''
    integer           :: kind       = T_FORWARD
    logical           :: as_float64 = .false.
end type fft_case

! what the forms of one function gave: the largest error, and whether every result had its expected shape
type :: form_result
    real(real64) :: err    = 0._real64
    logical      :: shaped = .true.
end type form_result

contains

    subroutine run_all_fft_nd_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all fft_nd tests ****'
        call assert_true(all(FFT_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a transform is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_transform_family
            call test_frequencies
            call test_shifts
            call test_transform_conventions
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_fft_nd_tests

    ! the seeds every family runs: the calibration seed, then the judged ones
    function family_seeds() result(seeds)
        integer, allocatable :: seeds(:)
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
    end function family_seeds

    ! the fixture from a fixed seed, uniform in [-1, 1] and rounded once to float32
    subroutine draw( x, seed )
        real(real64), intent(out) :: x(:,:,:,:)
        integer,      intent(in)  :: seed
        call set_fixed_seed(seed)
        call random_number(x)
        x = real(real(2*x-1, real32), real64)
    end subroutine draw

    ! the direct DFT of every line of x along dimension dim, to length n: a line is truncated or zero-padded to n
    ! first; the exponent is negative forward and positive inverse, as MLX's, and nothing is scaled
    function dft_lines( x, dim, n, inverse ) result(y)
        complex(real64), intent(in) :: x(:,:,:,:)
        integer,         intent(in) :: dim, n
        logical,         intent(in) :: inverse
        complex(real64), allocatable :: y(:,:,:,:), xp(:,:,:,:), yp(:,:,:,:)
        real(real64)                 :: angle, sgn
        integer                      :: perm(4), sh(4), j, k
        perm = [1, 2, 3, 4]
        perm(1) = dim
        perm(dim) = 1
        sh = shape(x)
        xp = reshape(x, sh(perm), order=perm)
        sgn = -1
        if( inverse ) sgn = 1
        allocate(yp(n, size(xp, 2), size(xp, 3), size(xp, 4)))
        yp = cmplx(0.d0, 0.d0, real64)
        do k = 1, n
            do j = 1, min(n, size(xp, 1))
                angle = sgn*2*acos(-1.d0)*real(modulo((j-1)*(k-1), n), real64)/real(n, real64)
                yp(k, :, :, :) = yp(k, :, :, :)+xp(j, :, :, :)*cmplx(cos(angle), sin(angle), real64)
            end do
        end do
        sh(dim) = n
        y = reshape(yp, sh, order=perm)
    end function dft_lines

    ! the real lines of length n whose half spectra are the lines of s along dimension dim, unscaled: the half
    ! spectrum is truncated or zero-padded to n/2+1 frequencies, the positive ones count twice, and the imaginary
    ! parts of the zero and the Nyquist frequency do not enter
    function real_lines( s, dim, n ) result(y)
        complex(real64), intent(in) :: s(:,:,:,:)
        integer,         intent(in) :: dim, n
        real(real64),    allocatable :: y(:,:,:,:), yp(:,:,:,:)
        complex(real64), allocatable :: sp(:,:,:,:)
        real(real64)                 :: angle, weight
        integer                      :: perm(4), sh(4), j, k
        perm = [1, 2, 3, 4]
        perm(1) = dim
        perm(dim) = 1
        sh = shape(s)
        sp = reshape(s, sh(perm), order=perm)
        allocate(yp(n, size(sp, 2), size(sp, 3), size(sp, 4)))
        yp = 0
        do j = 1, n
            do k = 1, min(n/2+1, size(sp, 1))
                weight = 2
                if( k == 1 .or. 2*(k-1) == n ) weight = 1
                angle = 2*acos(-1.d0)*real(modulo((j-1)*(k-1), n), real64)/real(n, real64)
                yp(j, :, :, :) = yp(j, :, :, :)+weight*real(sp(k, :, :, :)*cmplx(cos(angle), sin(angle), real64), real64)
            end do
        end do
        sh(dim) = n
        y = reshape(yp, sh, order=perm)
    end function real_lines

    ! the dimensions and the lengths a form transforms an array of shape sh with: every dimension of the first
    ! three when none is given; the extents when no length is given, and 2*(extent-1) along the half-size
    ! dimension, the first listed, of an inverse real transform
    subroutine form_layout( form, kind, sh, d, lengths )
        type(fft_form), intent(in)               :: form
        integer,        intent(in)               :: kind, sh(4)
        integer,        allocatable, intent(out) :: d(:), lengths(:)
        if( form%nd == 0 )then
            d = [1, 2, 3]
        else
            d = form%dims(:form%nd)
        endif
        if( form%has_n )then
            lengths = form%n(:size(d))
        else
            lengths = sh(d)
            if( kind == T_REAL_INVERSE ) lengths(1) = 2*(sh(d(1))-1)
        endif
    end subroutine form_layout

    ! the scale of a norm for a transform of p elements
    function norm_scale( norm, p, inverse ) result(scale)
        integer, intent(in) :: norm, p
        logical, intent(in) :: inverse
        real(real64) :: scale
        scale = 1
        if( norm == MLX_FFT_NORMS%ortho ) scale = 1/sqrt(real(p, real64))
        if( norm == MLX_FFT_NORMS%forward .and. .not. inverse ) scale = 1/real(p, real64)
        if( norm == MLX_FFT_NORMS%backward .and. inverse ) scale = 1/real(p, real64)
    end function norm_scale

    ! the reference of a complex transform, or of a real one to its half spectrum, of w in a form: the DFT along
    ! each dimension in turn; a real transform keeps the first lengths(1)/2+1 frequencies of the first listed
    function spectrum_reference( w, kind, form ) result(ref)
        complex(real64), intent(in) :: w(:,:,:,:)
        integer,         intent(in) :: kind
        type(fft_form),  intent(in) :: form
        complex(real64), allocatable :: ref(:,:,:,:), half(:,:,:,:)
        integer,         allocatable :: d(:), lengths(:)
        integer                      :: k, sh(4), perm(4)
        call form_layout(form, kind, shape(w), d, lengths)
        ref = w
        do k = 1, size(d)
            ref = dft_lines(ref, d(k), lengths(k), kind == T_INVERSE)
        end do
        ref = ref*norm_scale(form%norm, product(lengths), kind == T_INVERSE)
        if( kind /= T_REAL ) return
        perm = [1, 2, 3, 4]
        perm(1) = d(1)
        perm(d(1)) = 1
        sh = shape(ref)
        half = reshape(ref, sh(perm), order=perm)
        half = half(:lengths(1)/2+1, :, :, :)
        sh(d(1)) = lengths(1)/2+1
        ref = reshape(half, sh, order=perm)
    end function spectrum_reference

    ! the reference of an inverse real transform of the half spectra s in a form: the inverse DFT along the other
    ! dimensions, then the real lines along the first listed, the half-size one
    function real_reference( s, form ) result(ref)
        complex(real64), intent(in) :: s(:,:,:,:)
        type(fft_form),  intent(in) :: form
        real(real64),    allocatable :: ref(:,:,:,:)
        complex(real64), allocatable :: tmp(:,:,:,:)
        integer,         allocatable :: d(:), lengths(:)
        integer                      :: k
        call form_layout(form, T_REAL_INVERSE, shape(s), d, lengths)
        tmp = s
        do k = 2, size(d)
            tmp = dft_lines(tmp, d(k), lengths(k), .true.)
        end do
        ref = real_lines(tmp, d(1), lengths(1))*norm_scale(form%norm, product(lengths), .true.)
    end function real_reference

    ! the transform a name calls, in a form: an unallocated list is an absent argument
    function transformed( name, a, form ) result(r)
        character(len=*), intent(in) :: name
        type(mlx_array),  intent(in) :: a
        type(fft_form),   intent(in) :: form
        type(mlx_array)      :: r
        integer, allocatable :: dims(:), n(:)
        integer              :: nlengths
        nlengths = 3
        if( form%nd > 0 )then
            dims = form%dims(:form%nd)
            nlengths = form%nd
        endif
        if( form%has_n ) n = form%n(:nlengths)
        select case( name )
            case( 'mlx_fftn' )
                r = mlx_fftn(a, dims=dims, n=n, norm=form%norm)
            case( 'mlx_ifftn' )
                r = mlx_ifftn(a, dims=dims, n=n, norm=form%norm)
            case( 'mlx_rfftn' )
                r = mlx_rfftn(a, dims=dims, n=n, norm=form%norm)
            case( 'mlx_irfftn' )
                r = mlx_irfftn(a, dims=dims, n=n, norm=form%norm)
            case( 'mlx_rfft2' )
                r = mlx_rfft2(a, form%dims(:2), n=n, norm=form%norm)
            case( 'mlx_irfft2' )
                r = mlx_irfft2(a, form%dims(:2), n=n, norm=form%norm)
        end select
    end function transformed

    ! the error of a result against its reference, relative to max(1, the largest |reference|); the shape is
    ! compared first, without the batch dimension of extent 1 that a rank-3 input's reference carries
    subroutine compare( r, ref, res )
        type(mlx_array),   intent(in)    :: r
        complex(real64),   intent(in)    :: ref(:,:,:,:)
        type(form_result), intent(inout) :: res
        complex(real32), allocatable :: got(:)
        integer,         allocatable :: sh(:), want(:)
        integer                      :: st
        sh = r%shape()
        want = shape(ref)
        if( size(sh) == 3 ) want = want(:3)
        if( size(sh) /= size(want) )then
            res%shaped = .false.
            return
        endif
        if( any(sh /= want) )then
            res%shaped = .false.
            return
        endif
        allocate(got(size(ref)))
        if( r%kind() == MLX_DTYPES%complex64 )then
            call mlx_to(got, r, status=st)
        else
            call real_values(r, got, st)
        endif
        if( st /= 0 )then
            res%shaped = .false.
            return
        endif
        res%err = nan_max(res%err, nan_maxval(abs(cmplx(got, kind=real64)-reshape(ref, [size(ref)])))/max(1._real64, nan_maxval(abs(ref))))
    end subroutine compare

    ! the elements of a float32 result as complex values
    subroutine real_values( r, got, st )
        type(mlx_array), intent(in)  :: r
        complex(real32), intent(out) :: got(:)
        integer,         intent(out) :: st
        real(real32) :: values(size(got))
        call mlx_to(values, r, status=st)
        got = cmplx(values, 0._real32, real32)
        if( st /= 0 ) got = cmplx(0._real32, 0._real32, real32)
    end subroutine real_values

    ! one function over its forms on the fixture w (the real part alone for a real transform): a form with
    ! dimensions on the whole batch, the form without on each fixture as a rank-3 array
    subroutine run_forms( c, w, forms, res )
        type(fft_case),    intent(in)    :: c
        complex(real64),   intent(in)    :: w(:,:,:,:)
        type(fft_form),    intent(in)    :: forms(:)
        type(form_result), intent(inout) :: res
        integer :: k, b, lo, hi
        do k = 1, size(forms)
            lo = 1
            hi = size(w, 4)
            do b = 1, merge(size(w, 4), 1, forms(k)%nd == 0)
                if( forms(k)%nd == 0 )then
                    lo = b
                    hi = b
                endif
                call run_form(c, w(:, :, :, lo:hi), forms(k), res)
            end do
        end do
    end subroutine run_forms

    ! one form on the arrays w: of rank 3 when the form gives no dimension. An inverse real transform takes the
    ! half spectrum of w's real part along the form's first dimension, rounded to complex64, and its reference is
    ! computed from the rounded spectrum
    subroutine run_form( c, w, form, res )
        type(fft_case),    intent(in)    :: c
        complex(real64),   intent(in)    :: w(:,:,:,:)
        type(fft_form),    intent(in)    :: form
        type(form_result), intent(inout) :: res
        type(mlx_array)              :: a, r
        type(fft_form)               :: natural
        complex(real64), allocatable :: input(:,:,:,:), ref(:,:,:,:)
        select case( c%kind )
            case( T_FORWARD, T_INVERSE )
                input = w
                ref = spectrum_reference(input, c%kind, form)
            case( T_REAL )
                input = cmplx(real(w, real64), 0.d0, real64)
                ref = spectrum_reference(input, c%kind, form)
            case default
                natural = form
                natural%has_n = .false.
                natural%norm = MLX_FFT_NORMS%backward
                input = spectrum_reference(cmplx(real(w, real64), 0.d0, real64), T_REAL, natural)
                input = cmplx(cmplx(input, kind=real32), kind=real64)
                ref = cmplx(real_reference(input, form), 0.d0, real64)
        end select
        call operand(input, c%kind == T_REAL, c%as_float64, form%nd == 0, a)
        r = transformed(trim(c%name), a, form)
        call compare(r, ref, res)
    end subroutine run_form

    ! the MLX array of a transform's input: its real part alone (float32, or float64) or complex64, of rank 3
    ! when the batch dimension, of extent 1, is dropped
    subroutine operand( input, real_part, as_float64, rank3, a )
        complex(real64), intent(in)  :: input(:,:,:,:)
        logical,         intent(in)  :: real_part, as_float64, rank3
        type(mlx_array), intent(out) :: a
        integer :: sh(4)
        sh = shape(input)
        if( real_part .and. as_float64 .and. rank3 )then
            a = mlx_from(reshape(real(input, real64), sh(1:3)))
        else if( real_part .and. as_float64 )then
            a = mlx_from(real(input, real64))
        else if( real_part .and. rank3 )then
            a = mlx_from(reshape(real(input, real32), sh(1:3)))
        else if( real_part )then
            a = mlx_from(real(input, real32))
        else if( rank3 )then
            a = mlx_from(reshape(cmplx(input, kind=real32), sh(1:3)))
        else
            a = mlx_from(cmplx(input, kind=real32))
        endif
    end subroutine operand

    ! the forms of the complex transforms: no dimension, the lengths alone, every dimension in order and out of
    ! order, two of them, one, and lengths that pad and truncate; the three norms
    subroutine complex_forms( forms )
        type(fft_form), allocatable, intent(out) :: forms(:)
        allocate(forms(7))
        forms(1) = fft_form(0, [0, 0, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(2) = fft_form(0, [0, 0, 0], .true., [4, 8, 3], MLX_FFT_NORMS%ortho)
        forms(3) = fft_form(3, [1, 2, 3], .false., [0, 0, 0], MLX_FFT_NORMS%ortho)
        forms(4) = fft_form(2, [3, 1, 0], .false., [0, 0, 0], MLX_FFT_NORMS%forward)
        forms(5) = fft_form(1, [2, 0, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(6) = fft_form(3, [2, 3, 1], .true., [8, 3, 6], MLX_FFT_NORMS%backward)
        forms(7) = fft_form(2, [1, 2, 0], .true., [4, 7, 0], MLX_FFT_NORMS%forward)
    end subroutine complex_forms

    ! the forms of the real transforms to a half spectrum: the half-size dimension is the first listed, 1, 2 or 3,
    ! of even and odd length, padded and truncated
    subroutine real_forms( forms )
        type(fft_form), allocatable, intent(out) :: forms(:)
        allocate(forms(8))
        forms(1) = fft_form(0, [0, 0, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(2) = fft_form(3, [1, 2, 3], .false., [0, 0, 0], MLX_FFT_NORMS%ortho)
        forms(3) = fft_form(2, [2, 3, 0], .false., [0, 0, 0], MLX_FFT_NORMS%forward)
        forms(4) = fft_form(2, [3, 1, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(5) = fft_form(1, [1, 0, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(6) = fft_form(3, [2, 1, 3], .true., [8, 3, 5], MLX_FFT_NORMS%backward)
        forms(7) = fft_form(1, [2, 0, 0], .true., [7, 0, 0], MLX_FFT_NORMS%ortho)
        forms(8) = fft_form(0, [0, 0, 0], .true., [8, 3, 5], MLX_FFT_NORMS%forward)
    end subroutine real_forms

    ! the forms of the inverse real transforms: the default length 2*(extent-1) along the half-size dimension, an
    ! odd length, and a half spectrum padded and truncated; the other dimensions keep their extents
    subroutine real_inverse_forms( forms )
        type(fft_form), allocatable, intent(out) :: forms(:)
        allocate(forms(8))
        forms(8) = fft_form(0, [0, 0, 0], .true., [9, 5, 4], MLX_FFT_NORMS%forward)
        forms(1) = fft_form(0, [0, 0, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(2) = fft_form(3, [1, 2, 3], .false., [0, 0, 0], MLX_FFT_NORMS%ortho)
        forms(3) = fft_form(2, [2, 3, 0], .true., [5, 4, 0], MLX_FFT_NORMS%forward)
        forms(4) = fft_form(2, [3, 1, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(5) = fft_form(1, [1, 0, 0], .true., [6, 0, 0], MLX_FFT_NORMS%backward)
        forms(6) = fft_form(2, [1, 2, 0], .true., [9, 5, 0], MLX_FFT_NORMS%backward)
        forms(7) = fft_form(3, [2, 3, 1], .true., [3, 4, 6], MLX_FFT_NORMS%ortho)
    end subroutine real_inverse_forms

    ! the forms of the two-dimensional real transforms, always with their two dimensions; for the inverse the
    ! lengths, when given, change the half-size dimension only
    subroutine two_dim_forms( forms, inverse )
        type(fft_form), allocatable, intent(out) :: forms(:)
        logical,        intent(in)               :: inverse
        allocate(forms(5))
        forms(1) = fft_form(2, [1, 2, 0], .false., [0, 0, 0], MLX_FFT_NORMS%backward)
        forms(2) = fft_form(2, [2, 1, 0], .false., [0, 0, 0], MLX_FFT_NORMS%ortho)
        forms(3) = fft_form(2, [3, 2, 0], .false., [0, 0, 0], MLX_FFT_NORMS%forward)
        forms(4) = fft_form(2, [2, 3, 0], .true., [8, 3, 0], MLX_FFT_NORMS%backward)
        forms(5) = fft_form(2, [1, 3, 0], .true., [5, 6, 0], MLX_FFT_NORMS%ortho)
        if( .not. inverse ) return
        forms(2) = fft_form(2, [2, 1, 0], .true., [5, 6, 0], MLX_FFT_NORMS%ortho)
        forms(4) = fft_form(2, [2, 3, 0], .true., [8, 4, 0], MLX_FFT_NORMS%backward)
        forms(5) = fft_form(2, [1, 3, 0], .true., [3, 4, 0], MLX_FFT_NORMS%ortho)
    end subroutine two_dim_forms

    ! every transform against its direct reference on each seed, over all its forms: complex64 and float32 inputs
    ! on every device, float64 inputs to the forward transforms on the CPU
    subroutine test_transform_family
        character(len=10), parameter :: NAMES(6) = [character(len=10) :: 'mlx_fftn', 'mlx_ifftn', 'mlx_rfftn', &
            &'mlx_irfftn', 'mlx_rfft2', 'mlx_irfft2']
        integer,        parameter   :: KINDS(6) = [T_FORWARD, T_INVERSE, T_REAL, T_REAL_INVERSE, T_REAL, T_REAL_INVERSE]
        type(fft_form), allocatable :: forms(:)
        integer,        allocatable :: seeds(:)
        type(form_result)           :: res
        type(elem_tolerance)        :: tol
        real(real64)                :: x(N1, N2, N3, NB), y(N1, N2, N3, NB)
        complex(real64)             :: w(N1, N2, N3, NB)
        integer                     :: c, k
        write(*,'(a)') 'test_transform_family'
        seeds = family_seeds()
        do k = 1, size(seeds)
            do c = 1, size(NAMES)
                call draw(x, 3000*seeds(k)+2*c)
                call draw(y, 3000*seeds(k)+2*c+1)
                w = cmplx(x, y, real64)
                select case( c )
                    case( 1, 2 )
                        call complex_forms(forms)
                    case( 3 )
                        call real_forms(forms)
                    case( 4 )
                        call real_inverse_forms(forms)
                    case default
                        call two_dim_forms(forms, KINDS(c) == T_REAL_INVERSE)
                end select
                tol = find_tolerance(FFT_TOLERANCES, NAMES(c))
                res = form_result()
                call run_forms(fft_case(NAMES(c), KINDS(c), .false.), w, forms, res)
                call judge_error(res%err, tol%f32, NAMES(c), 'float32', seeds(k))
                call assert_true(res%shaped, trim(NAMES(c))//': every form has its shape, the half-size dimension the first listed')
                if( KINDS(c) /= T_REAL ) cycle
                if( mlx_default_device() /= MLX_DEVICES%cpu ) cycle
                res = form_result()
                call run_forms(fft_case(NAMES(c), KINDS(c), .true.), w, forms, res)
                call judge_error(res%err, tol%f64, NAMES(c), 'float64', seeds(k))
            end do
        end do
    end subroutine test_transform_family

    ! the frequencies of a transform against k/(n d) in real64, for even and odd n and seeded spacings: an error
    ! relative to max(1, |reference|); the order is the transform's, the negative frequencies last
    subroutine test_frequencies
        integer,      parameter   :: LENGTHS(4) = [1, 8, 9, 64]
        integer,      allocatable :: seeds(:)
        type(mlx_array)           :: r
        type(elem_tolerance)      :: tol_full, tol_half
        real(real32), allocatable :: got(:)
        real(real64), allocatable :: ref(:)
        real(real64)              :: u(size(LENGTHS)), d, err_full, err_half
        integer                   :: k, i, j, n, st
        logical                   :: shaped
        write(*,'(a)') 'test_frequencies'
        tol_full = find_tolerance(FFT_TOLERANCES, 'mlx_fftfreq')
        tol_half = find_tolerance(FFT_TOLERANCES, 'mlx_rfftfreq')
        seeds = family_seeds()
        do k = 1, size(seeds)
            call set_fixed_seed(5000*seeds(k))
            call random_number(u)
            err_full = 0
            err_half = 0
            shaped = .true.
            do i = 1, size(LENGTHS)
                n = LENGTHS(i)
                d = real(real(0.05d0+2*u(i), real32), real64)
                r = mlx_fftfreq(n, d=d)
                ref = [(real(j, real64), j=0, (n-1)/2), (real(j, real64), j=-(n/2), -1)]/(real(n, real64)*d)
                if( r%size() /= n ) shaped = .false.
                if( r%kind() /= MLX_DTYPES%float32 ) shaped = .false.
                if( .not. shaped ) cycle
                allocate(got(n))
                call mlx_to(got, r, status=st)
                if( st /= 0 ) shaped = .false.
                err_full = nan_max(err_full, nan_maxval(abs(real(got, real64)-ref)/max(1._real64, abs(ref))))
                deallocate(got)
                r = mlx_rfftfreq(n, d=d)
                ref = [(real(j, real64), j=0, n/2)]/(real(n, real64)*d)
                if( r%size() /= n/2+1 ) shaped = .false.
                if( .not. shaped ) cycle
                allocate(got(n/2+1))
                call mlx_to(got, r, status=st)
                if( st /= 0 ) shaped = .false.
                err_half = nan_max(err_half, nan_maxval(abs(real(got, real64)-ref)/max(1._real64, abs(ref))))
                deallocate(got)
            end do
            call judge_error(err_full, tol_full%f32, 'mlx_fftfreq', 'float32', seeds(k))
            call judge_error(err_half, tol_half%f32, 'mlx_rfftfreq', 'float32', seeds(k))
            call assert_true(shaped, 'the frequencies are float32, n of them and n/2+1 for the real transform')
        end do
    end subroutine test_frequencies

    ! the shifts are circular shifts by extent/2: Fortran's cshift by -extent/2 and by +extent/2 along each listed
    ! dimension, bit for bit; they differ along a dimension of odd extent, where two forward shifts do not cancel
    subroutine test_shifts
        type(mlx_array) :: a, r
        real(real64)    :: x(N1, N2, N3, 1)
        real(real32)    :: v(N1, N2, N3), got(N1, N2, N3), want(N1, N2, N3), got2(N2, N3)
        integer         :: st
        write(*,'(a)') 'test_shifts'
        call draw(x, 7001)
        v = real(x(:, :, :, 1), real32)
        a = mlx_from(v)
        r = mlx_fftshift(a)
        want = cshift(cshift(cshift(v, -H1, 1), -H2, 2), -H3, 3)
        call mlx_to(got, r, status=st)
        call assert_int(0, st, 'a shift over every dimension keeps the shape')
        call assert_true(all(bits_equal(got, want)), 'mlx_fftshift without dims is cshift by -extent/2 along every dimension')
        r = mlx_ifftshift(a)
        want = cshift(cshift(cshift(v, H1, 1), H2, 2), H3, 3)
        call mlx_to(got, r)
        call assert_true(all(bits_equal(got, want)), 'mlx_ifftshift without dims is cshift by +extent/2 along every dimension')
        r = mlx_fftshift(a, dims=[2])
        want = cshift(v, -H2, 2)
        call mlx_to(got, r)
        call assert_true(all(bits_equal(got, want)), 'mlx_fftshift along dimension 2 leaves the other dimensions alone')
        r = mlx_ifftshift(a, dims=[3, 2])
        want = cshift(cshift(v, H2, 2), H3, 3)
        call mlx_to(got, r)
        call assert_true(all(bits_equal(got, want)), 'mlx_ifftshift along dimensions 3 and 2')
        r = mlx_ifftshift(mlx_fftshift(a))
        call mlx_to(got, r)
        call assert_true(all(bits_equal(got, v)), 'mlx_ifftshift undoes mlx_fftshift, odd extents included')
        r = mlx_fftshift(mlx_fftshift(a, dims=[2]), dims=[2])
        call mlx_to(got, r)
        call assert_true(.not. all(bits_equal(got, v)), 'two forward shifts along an odd extent do not give the array back')
        a = mlx_from(v(1, :, :))
        r = mlx_fftshift(a, dims=[1])
        call mlx_to(got2, r)
        call assert_true(all(bits_equal(got2, cshift(v(1, :, :), -H2, 1))), 'mlx_fftshift along dimension 1 of a (5, 4) array shifts the odd extent by -2')
        r = mlx_ifftshift(a, dims=[1])
        call mlx_to(got2, r)
        call assert_true(all(bits_equal(got2, cshift(v(1, :, :), H2, 1))), 'mlx_ifftshift along dimension 1 of a (5, 4) array shifts the odd extent by +2')
    end subroutine test_shifts

    ! the conventions by name: shifted frequencies ascend with zero at element n/2+1; two dimensions of mlx_fftn
    ! are mlx_fft2; a real transform halves the first listed dimension; the inverse's default length
    subroutine test_transform_conventions
        type(mlx_array) :: a, r, f
        real(real64)    :: x(N1, N2, N3, 1)
        real(real32)    :: v(N1, N2, N3), f8(8), f9(9)
        complex(real32) :: p(N1, N2, N3), q(N1, N2, N3)
        integer         :: j
        write(*,'(a)') 'test_transform_conventions'
        f = mlx_fftfreq(8)
        r = mlx_fftshift(f)
        call mlx_to(f8, r)
        call assert_true(all(bits_equal(f8, [(real(j, real32)/8, j=-4, 3)])), 'shifted frequencies of 8 samples ascend from -4/8, zero at element 5')
        f = mlx_fftfreq(9, d=0.5d0)
        r = mlx_fftshift(f)
        call mlx_to(f9, r)
        call assert_true(abs(f9(5)) <= 0._real32, 'shifted frequencies of 9 samples have zero at element 9/2+1')
        call assert_true(all(f9(2:) > f9(:8)), 'shifted frequencies of 9 samples ascend')
        call draw(x, 7002)
        v = real(x(:, :, :, 1), real32)
        a = mlx_from(v)
        r = mlx_fftn(a, dims=[1, 2])
        call mlx_to(p, r)
        r = mlx_fft2(a, [1, 2])
        call mlx_to(q, r)
        call assert_true(all(bits_equal(p, q)), 'mlx_fftn over dimensions 1 and 2 is mlx_fft2, bit for bit')
        r = mlx_rfftn(a)
        call assert_true(all(r%shape() == [H1+1, N2, N3]), 'mlx_rfftn without dims halves dimension 1')
        r = mlx_rfftn(a, dims=[3, 1, 2])
        call assert_true(all(r%shape() == [N1, N2, H3+1]), 'mlx_rfftn halves the first listed dimension, here 3')
        r = mlx_rfft2(a, [2, 3])
        call assert_true(all(r%shape() == [N1, H2+1, N3]), 'mlx_rfft2 halves the first of its two dimensions')
        r = mlx_irfftn(mlx_rfftn(a))
        call assert_true(all(r%shape() == [N1, N2, N3]), 'mlx_irfftn gives 2*(extent-1) along the half-size dimension by default')
        r = mlx_irfft2(mlx_rfft2(a, [2, 3]), [2, 3])
        call assert_true(all(r%shape() == [N1, 2*H2, N3]), 'mlx_irfft2 of an odd length needs n: the default is the even length below')
        f = mlx_rfftfreq(8)
        call mlx_to(f8(:5), f)
        call assert_true(all(bits_equal(f8(:5), [(real(j, real32)/8, j=0, 4)])), 'mlx_rfftfreq of 8 samples without d is 0 to 4 eighths')
        r = mlx_irfft2(mlx_rfft2(a, [2, 3]), [2, 3], n=[N2, N3])
        call assert_true(all(r%shape() == [N1, N2, N3]), 'mlx_irfft2 with n gives the odd length back')
    end subroutine test_transform_conventions

end module mlxf_fft_nd_tester
