!@descr: the convolutions and transposed convolutions over one to three spatial dimensions against direct real64 sums in Fortran's layout
! Seeded float32 inputs and kernels on every device (MLX computes a float64 convolution in float32 when its
! options allow, and refuses it otherwise). The references are written
! over Fortran subscripts (channels, W, H, D, batch): a correlation as a sum over the kernel at each output
! position, a transposed convolution as every input element spread over the output, so that neither repeats how
! MLX computes them. Stride, padding and dilation differ between the spatial dimensions, so that options given in
! another order give another shape or other values. A result is judged by its largest error relative to
! max(1, the same sum of magnitudes).
module mlxf_conv_tester
use, intrinsic :: iso_fortran_env, only: real64
use mlxf,            only: mlx_array, mlx_set_default_device, mlx_default_device, reshape, mlx_conv_spec, mlx_conv1d, &
                           mlx_conv2d, mlx_conv3d, mlx_conv_general, mlx_conv_transpose1d, mlx_conv_transpose2d, &
                           mlx_conv_transpose3d
use mlxf_test_utils, only: assert_true, test_devices, device_name, judge_error, find_tolerance, family_seeds, &
                           seeded_uniform, seeded_array, shaped_error
use mlxf_test_defs,  only: ELEM_CEILING, CONV_TOLERANCES, elem_tolerance
implicit none
private
public :: run_all_conv_tests

! a convolution as the references take it, per spatial dimension in Fortran's order (W, H, D): the stride, the
! padding before (lo) and after (hi), the dilation of the kernel (dil) and of the input (idil), the output padding
! of a transposed convolution (opad), the groups, and whether the kernel is reversed
type :: conv_case
    integer :: stride(3) = 1, lo(3) = 0, hi(3) = 0, dil(3) = 1, idil(3) = 1, opad(3) = 0
    integer :: groups = 1
    logical :: flip = .false.
end type conv_case

contains

    subroutine run_all_conv_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all conv tests ****'
        call assert_true(all(CONV_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a convolution is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_conv1d
            call test_conv2d
            call test_conv3d
            call test_conv_general
            call test_conv_transpose1d
            call test_conv_transpose2d
            call test_conv_transpose3d
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_conv_tests

    ! the largest error of a function's forms against its frozen float32 tolerance
    subroutine judge( err, tol, seed )
        real(real64),         intent(in) :: err
        type(elem_tolerance), intent(in) :: tol
        integer,              intent(in) :: seed
        call judge_error(err, tol%f32, trim(tol%name), 'float32', seed)
    end subroutine judge

    ! the correlation of x (C, W, H, D, N) with the kernels w (C/groups, kW, kH, kD, C_out): the input spread by
    ! idil and padded with zeros, then at each output position the sum over the kernel (reversed with flip) and the
    ! channels of the output channel's group. bound is the same sum of magnitudes
    subroutine conv_reference( x, w, o, y, bound )
        real(real64),    intent(in)               :: x(:,:,:,:,:), w(:,:,:,:,:)
        type(conv_case), intent(in)               :: o
        real(real64),    allocatable, intent(out) :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64), allocatable :: xp(:,:,:,:,:)
        real(real64)              :: term
        integer                   :: ext(3), kk(3), de(3), pe(3), oe(3), j(3), kw(3), p(3), k(3)
        integer                   :: d, n, oc, cc, g, cg, co, p1, p2, p3, k1, k2, k3
        cg = size(w, 1)
        co = size(w, 5)
        do d = 1, 3
            ext(d) = size(x, d+1)
            kk(d) = size(w, d+1)
            de(d) = (ext(d)-1)*o%idil(d)+1
            pe(d) = de(d)+o%lo(d)+o%hi(d)
            oe(d) = (pe(d)-o%dil(d)*(kk(d)-1)-1)/o%stride(d)+1
        end do
        allocate(xp(size(x, 1), pe(1), pe(2), pe(3), size(x, 5)), y(co, oe(1), oe(2), oe(3), size(x, 5)))
        xp = 0._real64
        xp(:, o%lo(1)+1:o%lo(1)+de(1):o%idil(1), o%lo(2)+1:o%lo(2)+de(2):o%idil(2), o%lo(3)+1:o%lo(3)+de(3):o%idil(3), :) = x
        y = 0._real64
        bound = y
        do n = 1, size(x, 5)
            do oc = 1, co
                g = (oc-1)/(co/o%groups)
                do p3 = 1, oe(3)
                    do p2 = 1, oe(2)
                        do p1 = 1, oe(1)
                            do k3 = 1, kk(3)
                                do k2 = 1, kk(2)
                                    do k1 = 1, kk(1)
                                        p = [p1, p2, p3]
                                        k = [k1, k2, k3]
                                        j = (p-1)*o%stride+(k-1)*o%dil+1
                                        kw = k
                                        if( o%flip ) kw = kk+1-k
                                        do cc = 1, cg
                                            term = xp(g*cg+cc, j(1), j(2), j(3), n)*w(cc, kw(1), kw(2), kw(3), oc)
                                            y(oc, p(1), p(2), p(3), n) = y(oc, p(1), p(2), p(3), n)+term
                                            bound(oc, p(1), p(2), p(3), n) = bound(oc, p(1), p(2), p(3), n)+abs(term)
                                        end do
                                    end do
                                end do
                            end do
                        end do
                    end do
                end do
            end do
        end do
    end subroutine conv_reference

    ! the transposed convolution of x with the kernels w: input element i adds x(c, i)*w(c', k, o) to output element
    ! (i-1)*stride - padding + (k-1)*dilation + 1 where the output reaches, the output's extent being
    ! (extent-1)*stride - 2*padding + dilation*(k-1) + 1 + output padding
    subroutine transpose_reference( x, w, o, y, bound )
        real(real64),    intent(in)               :: x(:,:,:,:,:), w(:,:,:,:,:)
        type(conv_case), intent(in)               :: o
        real(real64),    allocatable, intent(out) :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64) :: term
        integer      :: ext(3), kk(3), oe(3), t(3), p(3), k(3)
        integer      :: d, n, oc, cc, g, cg, co, p1, p2, p3, k1, k2, k3
        cg = size(w, 1)
        co = size(w, 5)
        do d = 1, 3
            ext(d) = size(x, d+1)
            kk(d) = size(w, d+1)
            oe(d) = (ext(d)-1)*o%stride(d)-2*o%lo(d)+o%dil(d)*(kk(d)-1)+1+o%opad(d)
        end do
        allocate(y(co, oe(1), oe(2), oe(3), size(x, 5)))
        y = 0._real64
        bound = y
        do n = 1, size(x, 5)
            do p3 = 1, ext(3)
                do p2 = 1, ext(2)
                    do p1 = 1, ext(1)
                        do k3 = 1, kk(3)
                            do k2 = 1, kk(2)
                                do k1 = 1, kk(1)
                                    p = [p1, p2, p3]
                                    k = [k1, k2, k3]
                                    t = (p-1)*o%stride-o%lo+(k-1)*o%dil+1
                                    if( any(t < 1) .or. any(t > oe) ) cycle
                                    do oc = 1, co
                                        g = (oc-1)/(co/o%groups)
                                        do cc = 1, cg
                                            term = x(g*cg+cc, p(1), p(2), p(3), n)*w(cc, k(1), k(2), k(3), oc)
                                            y(oc, t(1), t(2), t(3), n) = y(oc, t(1), t(2), t(3), n)+term
                                            bound(oc, t(1), t(2), t(3), n) = bound(oc, t(1), t(2), t(3), n)+abs(term)
                                        end do
                                    end do
                                end do
                            end do
                        end do
                    end do
                end do
            end do
        end do
    end subroutine transpose_reference

    ! the options of a case as the wrappers take them, for nsp spatial dimensions: form 'c' is a convolution
    ! (stride, padding, dilation, groups), 'g' the general one (with the padding after, the input's dilation and
    ! the flip), 't' a transposed one (with the output padding)
    function spec_of( o, nsp, form ) result(spec)
        type(conv_case),  intent(in) :: o
        integer,          intent(in) :: nsp
        character(len=1), intent(in) :: form
        type(mlx_conv_spec) :: spec
        spec%stride = o%stride(:nsp)
        spec%padding = o%lo(:nsp)
        spec%dilation = o%dil(:nsp)
        spec%groups = o%groups
        if( form == 'g' )then
            spec%padding_hi = o%hi(:nsp)
            spec%input_dilation = o%idil(:nsp)
            spec%flip = o%flip
        else if( form == 't' )then
            spec%output_padding = o%opad(:nsp)
        endif
    end function spec_of

    ! an operand of the references, (C, W, H, D, N) with trailing spatial extents of 1, as the array of nsp spatial
    ! dimensions a wrapper takes, rounded to float32
    function operand( x, nsp ) result(a)
        real(real64), intent(in) :: x(:,:,:,:,:)
        integer,      intent(in) :: nsp
        type(mlx_array)      :: a
        integer, allocatable :: sh(:)
        sh = shape(x)
        a = reshape(seeded_array(x, .false.), [sh(:nsp+1), sh(5)])
    end function operand

    ! a result's largest error against a reference held with three spatial dimensions; huge unless the result has
    ! the reference's channels, its first nsp spatial extents and its batch
    function conv_error( r, nsp, y, bound ) result(err)
        type(mlx_array), intent(in) :: r
        integer,         intent(in) :: nsp
        real(real64),    intent(in) :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)         :: err
        integer, allocatable :: sh(:), want(:)
        err = huge(1._real64)
        sh = shape(y)
        want = [sh(:nsp+1), sh(5)]
        sh = r%shape()
        if( size(sh) /= size(want) ) return
        if( any(sh /= want) ) return
        err = shaped_error(reshape(r, shape(y)), y, bound)
    end function conv_error

    ! seeded values in the shape of an operand
    function drawn( sh, seed ) result(x)
        integer, intent(in) :: sh(5), seed
        real(real64) :: x(sh(1), sh(2), sh(3), sh(4), sh(5))
        x = reshape(seeded_uniform(product(sh), seed), sh)
    end function drawn

    ! one spatial dimension: two groups with a stride, a padding and a dilation; and the defaults, without a spec
    subroutine test_conv1d
        integer,      allocatable :: seeds(:)
        type(elem_tolerance)      :: tol
        type(conv_case)           :: o
        type(mlx_array)           :: r
        real(real64), allocatable :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)              :: x(4, 11, 1, 1, 2), w(2, 3, 1, 1, 6), wfull(4, 3, 1, 1, 5), err
        integer                   :: s
        write(*,'(a)') 'test_conv1d'
        tol = find_tolerance(CONV_TOLERANCES, 'mlx_conv1d')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = drawn(shape(x), 8000*seeds(s)+1)
            w = drawn(shape(w), 8000*seeds(s)+2)
            wfull = drawn(shape(wfull), 8000*seeds(s)+3)
            o = conv_case(groups=2)
            o%stride(1) = 3
            o%lo(1) = 1
            o%hi(1) = 1
            o%dil(1) = 2
            call conv_reference(x, w, o, y, bound)
            r = mlx_conv1d(operand(x, 1), operand(w, 1), spec_of(o, 1, 'c'))
            err = conv_error(r, 1, y, bound)
            call conv_reference(x, wfull, conv_case(), y, bound)
            r = mlx_conv1d(operand(x, 1), operand(wfull, 1))
            err = max(err, conv_error(r, 1, y, bound))
            call judge(err, tol, seeds(s))
        end do
    end subroutine test_conv1d

    ! two spatial dimensions with a stride, a padding and a dilation that differ between W and H; one value for
    ! both dimensions; three groups of one channel; and the defaults, without a spec
    subroutine test_conv2d
        integer,      allocatable :: seeds(:)
        type(elem_tolerance)      :: tol
        type(conv_case)           :: o
        type(mlx_array)           :: r
        real(real64), allocatable :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)              :: x(3, 9, 7, 1, 2), w(3, 3, 2, 1, 4), wg(1, 3, 2, 1, 6), err
        integer                   :: s
        write(*,'(a)') 'test_conv2d'
        tol = find_tolerance(CONV_TOLERANCES, 'mlx_conv2d')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = drawn(shape(x), 8100*seeds(s)+1)
            w = drawn(shape(w), 8100*seeds(s)+2)
            wg = drawn(shape(wg), 8100*seeds(s)+3)
            o = conv_case()
            o%stride(:2) = [2, 1]
            o%lo(:2) = [1, 2]
            o%hi(:2) = [1, 2]
            o%dil(:2) = [1, 2]
            call conv_reference(x, w, o, y, bound)
            r = mlx_conv2d(operand(x, 2), operand(w, 2), spec_of(o, 2, 'c'))
            err = conv_error(r, 2, y, bound)
            o = conv_case()
            o%stride(:2) = 2
            o%lo(:2) = 1
            o%hi(:2) = 1
            call conv_reference(x, w, o, y, bound)
            r = mlx_conv2d(operand(x, 2), operand(w, 2), mlx_conv_spec(stride=[2], padding=[1]))
            err = max(err, conv_error(r, 2, y, bound))
            o = conv_case(groups=3)
            o%stride(:2) = [1, 2]
            call conv_reference(x, wg, o, y, bound)
            r = mlx_conv2d(operand(x, 2), operand(wg, 2), spec_of(o, 2, 'c'))
            err = max(err, conv_error(r, 2, y, bound))
            call conv_reference(x, w, conv_case(), y, bound)
            r = mlx_conv2d(operand(x, 2), operand(w, 2))
            err = max(err, conv_error(r, 2, y, bound))
            call judge(err, tol, seeds(s))
        end do
    end subroutine test_conv2d

    ! three spatial dimensions, each with its own stride, padding and dilation
    subroutine test_conv3d
        integer,      allocatable :: seeds(:)
        type(elem_tolerance)      :: tol
        type(conv_case)           :: o
        type(mlx_array)           :: r
        real(real64), allocatable :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)              :: x(2, 6, 5, 4, 2), w(2, 3, 2, 2, 3), err
        integer                   :: s
        write(*,'(a)') 'test_conv3d'
        tol = find_tolerance(CONV_TOLERANCES, 'mlx_conv3d')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = drawn(shape(x), 8200*seeds(s)+1)
            w = drawn(shape(w), 8200*seeds(s)+2)
            o = conv_case()
            o%stride = [2, 1, 3]
            o%lo = [1, 0, 2]
            o%hi = o%lo
            o%dil = [1, 1, 2]
            call conv_reference(x, w, o, y, bound)
            r = mlx_conv3d(operand(x, 3), operand(w, 3), spec_of(o, 3, 'c'))
            err = conv_error(r, 3, y, bound)
            call conv_reference(x, w, conv_case(), y, bound)
            r = mlx_conv3d(operand(x, 3), operand(w, 3))
            err = max(err, conv_error(r, 3, y, bound))
            call judge(err, tol, seeds(s))
        end do
    end subroutine test_conv3d

    ! the general form: two dimensions with different paddings before and after, the input spread and the kernels
    ! reversed; one dimension with groups and reversed kernels; three dimensions with the defaults but the padding
    ! after
    subroutine test_conv_general
        integer,      allocatable :: seeds(:)
        type(elem_tolerance)      :: tol
        type(conv_case)           :: o
        type(mlx_array)           :: r
        real(real64), allocatable :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)              :: x2(3, 6, 5, 1, 2), w2(3, 3, 2, 1, 4), x1(4, 9, 1, 1, 2), w1(2, 3, 1, 1, 4)
        real(real64)              :: x3(2, 5, 4, 3, 1), w3(2, 2, 2, 2, 3), err
        integer                   :: s
        write(*,'(a)') 'test_conv_general'
        tol = find_tolerance(CONV_TOLERANCES, 'mlx_conv_general')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x2 = drawn(shape(x2), 8300*seeds(s)+1)
            w2 = drawn(shape(w2), 8300*seeds(s)+2)
            x1 = drawn(shape(x1), 8300*seeds(s)+3)
            w1 = drawn(shape(w1), 8300*seeds(s)+4)
            x3 = drawn(shape(x3), 8300*seeds(s)+5)
            w3 = drawn(shape(w3), 8300*seeds(s)+6)
            o = conv_case(flip=.true.)
            o%stride(:2) = [2, 1]
            o%lo(:2) = [1, 2]
            o%hi(:2) = [0, 3]
            o%dil(:2) = [1, 2]
            o%idil(:2) = [2, 1]
            call conv_reference(x2, w2, o, y, bound)
            r = mlx_conv_general(operand(x2, 2), operand(w2, 2), spec_of(o, 2, 'g'))
            err = conv_error(r, 2, y, bound)
            o = conv_case(groups=2, flip=.true.)
            o%stride(1) = 2
            o%lo(1) = 2
            o%hi(1) = 2
            call conv_reference(x1, w1, o, y, bound)
            r = mlx_conv_general(operand(x1, 1), operand(w1, 1), mlx_conv_spec(stride=[2], padding=[2], groups=2, flip=.true.))
            err = max(err, conv_error(r, 1, y, bound))
            o = conv_case()
            o%hi = [1, 0, 2]
            call conv_reference(x3, w3, o, y, bound)
            r = mlx_conv_general(operand(x3, 3), operand(w3, 3), mlx_conv_spec(padding_hi=[1, 0, 2]))
            err = max(err, conv_error(r, 3, y, bound))
            call judge(err, tol, seeds(s))
        end do
    end subroutine test_conv_general

    ! one spatial dimension: a stride, a padding, a dilation and an output padding; two groups; the defaults
    subroutine test_conv_transpose1d
        integer,      allocatable :: seeds(:)
        type(elem_tolerance)      :: tol
        type(conv_case)           :: o
        type(mlx_array)           :: r
        real(real64), allocatable :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)              :: x(4, 7, 1, 1, 2), w(4, 3, 1, 1, 5), wg(2, 3, 1, 1, 6), err
        integer                   :: s
        write(*,'(a)') 'test_conv_transpose1d'
        tol = find_tolerance(CONV_TOLERANCES, 'mlx_conv_transpose1d')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = drawn(shape(x), 8400*seeds(s)+1)
            w = drawn(shape(w), 8400*seeds(s)+2)
            wg = drawn(shape(wg), 8400*seeds(s)+3)
            o = conv_case()
            o%stride(1) = 3
            o%lo(1) = 1
            o%dil(1) = 2
            o%opad(1) = 2
            call transpose_reference(x, w, o, y, bound)
            r = mlx_conv_transpose1d(operand(x, 1), operand(w, 1), spec_of(o, 1, 't'))
            err = conv_error(r, 1, y, bound)
            o = conv_case(groups=2)
            o%stride(1) = 2
            call transpose_reference(x, wg, o, y, bound)
            r = mlx_conv_transpose1d(operand(x, 1), operand(wg, 1), spec_of(o, 1, 't'))
            err = max(err, conv_error(r, 1, y, bound))
            call transpose_reference(x, w, conv_case(), y, bound)
            r = mlx_conv_transpose1d(operand(x, 1), operand(w, 1))
            err = max(err, conv_error(r, 1, y, bound))
            call judge(err, tol, seeds(s))
        end do
    end subroutine test_conv_transpose1d

    ! two spatial dimensions, each with its own stride, padding, dilation and output padding
    subroutine test_conv_transpose2d
        integer,      allocatable :: seeds(:)
        type(elem_tolerance)      :: tol
        type(conv_case)           :: o
        type(mlx_array)           :: r
        real(real64), allocatable :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)              :: x(3, 5, 4, 1, 2), w(3, 3, 2, 1, 4), err
        integer                   :: s
        write(*,'(a)') 'test_conv_transpose2d'
        tol = find_tolerance(CONV_TOLERANCES, 'mlx_conv_transpose2d')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = drawn(shape(x), 8500*seeds(s)+1)
            w = drawn(shape(w), 8500*seeds(s)+2)
            o = conv_case()
            o%stride(:2) = [2, 3]
            o%lo(:2) = [1, 0]
            o%dil(:2) = [1, 2]
            o%opad(:2) = [0, 2]
            call transpose_reference(x, w, o, y, bound)
            r = mlx_conv_transpose2d(operand(x, 2), operand(w, 2), spec_of(o, 2, 't'))
            err = conv_error(r, 2, y, bound)
            call judge(err, tol, seeds(s))
        end do
    end subroutine test_conv_transpose2d

    ! three spatial dimensions, each with its own stride, padding, dilation and output padding
    subroutine test_conv_transpose3d
        integer,      allocatable :: seeds(:)
        type(elem_tolerance)      :: tol
        type(conv_case)           :: o
        type(mlx_array)           :: r
        real(real64), allocatable :: y(:,:,:,:,:), bound(:,:,:,:,:)
        real(real64)              :: x(2, 4, 3, 2, 2), w(2, 3, 2, 2, 3), err
        integer                   :: s
        write(*,'(a)') 'test_conv_transpose3d'
        tol = find_tolerance(CONV_TOLERANCES, 'mlx_conv_transpose3d')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = drawn(shape(x), 8600*seeds(s)+1)
            w = drawn(shape(w), 8600*seeds(s)+2)
            o = conv_case()
            o%stride = [2, 1, 3]
            o%lo = [0, 1, 1]
            o%dil = [2, 1, 1]
            o%opad = [1, 0, 2]
            call transpose_reference(x, w, o, y, bound)
            r = mlx_conv_transpose3d(operand(x, 3), operand(w, 3), spec_of(o, 3, 't'))
            err = conv_error(r, 3, y, bound)
            call judge(err, tol, seeds(s))
        end do
    end subroutine test_conv_transpose3d

end module mlxf_conv_tester
