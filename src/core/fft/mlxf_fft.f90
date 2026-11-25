!@descr: real and complex Fourier transforms along Fortran dimensions, their shifts and their frequencies
module mlxf_fft
use, intrinsic :: iso_c_binding,   only: c_double
use, intrinsic :: iso_fortran_env, only: real64
use mlxf_c_fft,  only: mlxc_fft_fft, mlxc_fft_ifft, mlxc_fft_rfft, mlxc_fft_irfft, mlxc_fft_fft2, mlxc_fft_ifft2, &
                       mlxc_fft_fftn, mlxc_fft_ifftn, mlxc_fft_rfft2, mlxc_fft_irfft2, mlxc_fft_rfftn, mlxc_fft_irfftn, &
                       mlxc_fft_fftshift, mlxc_fft_ifftshift, mlxc_fft_fftfreq, mlxc_fft_rfftfreq
use mlxf_defs,   only: mlxf_fft_spec, mlxf_fftn_spec
use mlxf_array,  only: mlx_array, mlxf_fft_op, mlxf_fftn_op, mlxf_freq_op, mlxf_vector_op, mlxf_axes_of
use mlxf_device, only: mlxf_enter
use mlxf_error,  only: mlxf_fail
implicit none
public :: mlx_fft, mlx_ifft, mlx_rfft, mlx_irfft, mlx_fft2, mlx_ifft2, mlx_fftn, mlx_ifftn, mlx_rfft2, mlx_irfft2, &
    &mlx_rfftn, mlx_irfftn, mlx_fftshift, mlx_ifftshift, mlx_fftfreq, mlx_rfftfreq
private

! what a transform over several dimensions is: complex, real to its half spectrum, or the half spectrum to real
integer, parameter :: KIND_COMPLEX = 0, KIND_REAL = 1, KIND_REAL_INVERSE = 2

contains

    ! the complex FFT along Fortran dimension dim; n pads or truncates (default: the extent), norm is one of
    ! MLX_FFT_NORMS (default backward: the forward transform is unscaled)
    function mlx_fft( a, dim, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        integer,         optional, intent(in) :: n, norm
        type(mlx_array)      :: r
        type(mlxf_fft_spec)  :: spec
        integer, allocatable :: shape(:)
        integer              :: nd
        call mlxf_enter('mlx_fft')
        nd = a%ndim()
        if( dim < 1 .or. dim > nd ) &
            &call mlxf_fail('mlx_fft', 'dimension outside array rank')
        shape = a%shape()
        spec%dims(1) = dim
        spec%n(1) = shape(dim)
        if( present(n) ) spec%n(1) = n
        if( present(norm) ) spec%norm = norm
        call mlxf_fft_op(r, mlxc_fft_fft, a, spec, 'mlx_fft')
    end function mlx_fft

    ! the inverse complex FFT along dim; the default backward norm scales it by 1/n
    function mlx_ifft( a, dim, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        integer,         optional, intent(in) :: n, norm
        type(mlx_array)      :: r
        type(mlxf_fft_spec)  :: spec
        integer, allocatable :: shape(:)
        integer              :: nd
        call mlxf_enter('mlx_ifft')
        nd = a%ndim()
        if( dim < 1 .or. dim > nd ) &
            &call mlxf_fail('mlx_ifft', 'dimension outside array rank')
        shape = a%shape()
        spec%dims(1) = dim
        spec%n(1) = shape(dim)
        if( present(n) ) spec%n(1) = n
        if( present(norm) ) spec%norm = norm
        call mlxf_fft_op(r, mlxc_fft_ifft, a, spec, 'mlx_ifft')
    end function mlx_ifft

    ! the FFT of a real array along dim, keeping the n/2+1 non-negative frequencies
    function mlx_rfft( a, dim, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        integer,         optional, intent(in) :: n, norm
        type(mlx_array)      :: r
        type(mlxf_fft_spec)  :: spec
        integer, allocatable :: shape(:)
        integer              :: nd
        call mlxf_enter('mlx_rfft')
        nd = a%ndim()
        if( dim < 1 .or. dim > nd ) &
            &call mlxf_fail('mlx_rfft', 'dimension outside array rank')
        shape = a%shape()
        spec%dims(1) = dim
        spec%n(1) = shape(dim)
        if( present(n) ) spec%n(1) = n
        if( present(norm) ) spec%norm = norm
        call mlxf_fft_op(r, mlxc_fft_rfft, a, spec, 'mlx_rfft')
    end function mlx_rfft

    ! the inverse of mlx_rfft along dim; the default length is 2*(extent-1), so an odd length needs n
    function mlx_irfft( a, dim, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dim
        integer,         optional, intent(in) :: n, norm
        type(mlx_array)      :: r
        type(mlxf_fft_spec)  :: spec
        integer, allocatable :: shape(:)
        integer              :: nd
        call mlxf_enter('mlx_irfft')
        nd = a%ndim()
        if( dim < 1 .or. dim > nd ) &
            &call mlxf_fail('mlx_irfft', 'dimension outside array rank')
        shape = a%shape()
        spec%dims(1) = dim
        spec%n(1) = 2*(shape(dim)-1)
        if( present(n) ) spec%n(1) = n
        if( present(norm) ) spec%norm = norm
        call mlxf_fft_op(r, mlxc_fft_irfft, a, spec, 'mlx_irfft')
    end function mlx_irfft

    ! the complex FFT over the two Fortran dimensions dims, every other dimension a batch; n per dimension
    function mlx_fft2( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(2)
        integer,         optional, intent(in) :: n(2), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        integer, allocatable :: shape(:)
        integer              :: nd
        call mlxf_enter('mlx_fft2')
        nd = a%ndim()
        if( any(dims < 1) .or. any(dims > nd) ) &
            &call mlxf_fail('mlx_fft2', 'dimension outside array rank')
        shape = a%shape()
        spec%dims = dims
        spec%n = shape(dims)
        if( present(n) ) spec%n = n
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_fft2, a, spec, 'mlx_fft2')
    end function mlx_fft2

    ! the inverse of mlx_fft2 over dims
    function mlx_ifft2( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(2)
        integer,         optional, intent(in) :: n(2), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        integer, allocatable :: shape(:)
        integer              :: nd
        call mlxf_enter('mlx_ifft2')
        nd = a%ndim()
        if( any(dims < 1) .or. any(dims > nd) ) &
            &call mlxf_fail('mlx_ifft2', 'dimension outside array rank')
        shape = a%shape()
        spec%dims = dims
        spec%n = shape(dims)
        if( present(n) ) spec%n = n
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_ifft2, a, spec, 'mlx_ifft2')
    end function mlx_ifft2

    ! the complex FFT over the Fortran dimensions dims (absent: every dimension), the others batches; n gives the
    ! length along each transformed dimension, in dims' order (absent: the extents)
    function mlx_fftn( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:), n(:), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        call mlxf_enter('mlx_fftn')
        spec = transform_spec(a, KIND_COMPLEX, 'mlx_fftn', dims, n)
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_fftn, a, spec, 'mlx_fftn')
    end function mlx_fftn

    ! the inverse of mlx_fftn over dims; the default backward norm scales it by one over the product of the lengths
    function mlx_ifftn( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:), n(:), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        call mlxf_enter('mlx_ifftn')
        spec = transform_spec(a, KIND_COMPLEX, 'mlx_ifftn', dims, n)
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_ifftn, a, spec, 'mlx_ifftn')
    end function mlx_ifftn

    ! the FFT of a real array over the two Fortran dimensions dims: the result keeps the n(1)/2+1 non-negative
    ! frequencies along dims(1), the half-size dimension, and every frequency along dims(2)
    function mlx_rfft2( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(2)
        integer,         optional, intent(in) :: n(2), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        call mlxf_enter('mlx_rfft2')
        spec = transform_spec(a, KIND_REAL, 'mlx_rfft2', dims, n)
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_rfft2, a, spec, 'mlx_rfft2')
    end function mlx_rfft2

    ! the inverse of mlx_rfft2: a real array of lengths n along dims, from a spectrum that is half along dims(1);
    ! the default length along dims(1) is 2*(extent-1), so an odd length needs n
    function mlx_irfft2( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(2)
        integer,         optional, intent(in) :: n(2), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        call mlxf_enter('mlx_irfft2')
        spec = transform_spec(a, KIND_REAL_INVERSE, 'mlx_irfft2', dims, n)
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_irfft2, a, spec, 'mlx_irfft2')
    end function mlx_irfft2

    ! the FFT of a real array over the Fortran dimensions dims (absent: every dimension): the result keeps the
    ! n/2+1 non-negative frequencies along dims(1), the half-size dimension (dimension 1 when dims is absent)
    function mlx_rfftn( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:), n(:), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        call mlxf_enter('mlx_rfftn')
        spec = transform_spec(a, KIND_REAL, 'mlx_rfftn', dims, n)
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_rfftn, a, spec, 'mlx_rfftn')
    end function mlx_rfftn

    ! the inverse of mlx_rfftn: a real array of lengths n along dims, from a spectrum that is half along dims(1);
    ! the default length along dims(1) is 2*(extent-1), so an odd length needs n
    function mlx_irfftn( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:), n(:), norm
        type(mlx_array)      :: r
        type(mlxf_fftn_spec) :: spec
        call mlxf_enter('mlx_irfftn')
        spec = transform_spec(a, KIND_REAL_INVERSE, 'mlx_irfftn', dims, n)
        if( present(norm) ) spec%norm = norm
        call mlxf_fftn_op(r, mlxc_fft_irfftn, a, spec, 'mlx_irfftn')
    end function mlx_irfftn

    ! a with the zero frequency moved to the centre of each listed dimension (absent: every dimension), element
    ! extent/2 + 1: a circular shift by extent/2 towards higher indices
    function mlx_fftshift( a, dims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_fftshift')
        call mlxf_vector_op(r, mlxc_fft_fftshift, a, shift_axes(a, 'mlx_fftshift', dims), 'mlx_fftshift')
    end function mlx_fftshift

    ! the inverse of mlx_fftshift: a circular shift by extent/2 towards lower indices, which differs from
    ! mlx_fftshift along a dimension of odd extent
    function mlx_ifftshift( a, dims ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         optional, intent(in) :: dims(:)
        type(mlx_array) :: r
        call mlxf_enter('mlx_ifftshift')
        call mlxf_vector_op(r, mlxc_fft_ifftshift, a, shift_axes(a, 'mlx_ifftshift', dims), 'mlx_ifftshift')
    end function mlx_ifftshift

    ! the frequencies of the n elements of a transform, in its order (0, 1, ..., then the negative ones), in
    ! cycles per unit of the sample spacing d (default 1): float32, rank 1
    function mlx_fftfreq( n, d ) result(r)
        integer,      intent(in)           :: n
        real(real64), optional, intent(in) :: d
        type(mlx_array) :: r
        real(c_double)  :: spacing
        call mlxf_enter('mlx_fftfreq')
        spacing = 1
        if( present(d) ) spacing = d
        call mlxf_freq_op(r, mlxc_fft_fftfreq, n, spacing, 'mlx_fftfreq')
    end function mlx_fftfreq

    ! the n/2+1 non-negative frequencies of a real transform of n samples spaced d apart (default 1): float32
    function mlx_rfftfreq( n, d ) result(r)
        integer,      intent(in)           :: n
        real(real64), optional, intent(in) :: d
        type(mlx_array) :: r
        real(c_double)  :: spacing
        call mlxf_enter('mlx_rfftfreq')
        spacing = 1
        if( present(d) ) spacing = d
        call mlxf_freq_op(r, mlxc_fft_rfftfreq, n, spacing, 'mlx_rfftfreq')
    end function mlx_rfftfreq

    ! the dimensions and lengths of a transform of a as MLX takes them. A complex transform keeps the order of
    ! dims; a real one lists dims(1) last, where MLX halves. Absent dims are every dimension, the first last;
    ! absent n are the extents, and 2*(extent-1) along the half-size dimension of an inverse real transform
    function transform_spec( a, kind, proc, dims, n ) result(spec)
        type(mlx_array),  intent(in)           :: a
        integer,          intent(in)           :: kind
        character(len=*), intent(in)           :: proc
        integer,          optional, intent(in) :: dims(:), n(:)
        type(mlxf_fftn_spec) :: spec
        integer, allocatable :: shape(:), d(:), lengths(:)
        integer              :: nd, i
        nd = a%ndim()
        shape = a%shape()
        if( present(dims) )then
            d = dims
        else
            d = [(i, i=1, nd)]
        endif
        if( any(d < 1) .or. any(d > nd) ) call mlxf_fail(proc, 'dimension outside array rank')
        if( present(n) )then
            if( size(n) /= size(d) ) call mlxf_fail(proc, 'one length per transformed dimension is needed')
            lengths = n
        else
            lengths = shape(d)
            if( kind == KIND_REAL_INVERSE .and. size(d) > 0 ) lengths(1) = 2*(shape(d(1))-1)
        endif
        if( kind == KIND_COMPLEX .and. present(dims) )then
            spec%dims = d
            spec%n = lengths
        else
            spec%dims = d(size(d):1:-1)
            spec%n = lengths(size(d):1:-1)
        endif
    end function transform_spec

    ! the MLX axes of the dimensions a shift acts on: those listed, or every dimension
    function shift_axes( a, proc, dims ) result(axes)
        type(mlx_array),  intent(in)           :: a
        character(len=*), intent(in)           :: proc
        integer,          optional, intent(in) :: dims(:)
        integer, allocatable :: axes(:)
        integer              :: i
        if( present(dims) )then
            axes = mlxf_axes_of(a, dims, proc)
        else
            axes = [(i, i=0, a%ndim()-1)]
        endif
    end function shift_axes

end module mlxf_fft
