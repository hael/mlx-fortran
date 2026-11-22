!@descr: real and complex Fourier transforms along Fortran dimensions
module mlxf_fft
use mlxf_c_fft,  only: mlxc_fft_fft, mlxc_fft_ifft, mlxc_fft_rfft, mlxc_fft_irfft, mlxc_fft_fft2, mlxc_fft_ifft2
use mlxf_defs,   only: mlxf_fft_spec
use mlxf_array,  only: mlx_array, mlxf_fft_op, mlxf_fft2_op
use mlxf_device, only: mlxf_enter
use mlxf_error,  only: mlxf_fail
implicit none
public :: mlx_fft, mlx_ifft, mlx_rfft, mlx_irfft, mlx_fft2, mlx_ifft2
private

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
        type(mlxf_fft_spec)  :: spec
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
        call mlxf_fft2_op(r, mlxc_fft_fft2, a, spec, 'mlx_fft2')
    end function mlx_fft2

    ! the inverse of mlx_fft2 over dims
    function mlx_ifft2( a, dims, n, norm ) result(r)
        type(mlx_array), intent(in)           :: a
        integer,         intent(in)           :: dims(2)
        integer,         optional, intent(in) :: n(2), norm
        type(mlx_array)      :: r
        type(mlxf_fft_spec)  :: spec
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
        call mlxf_fft2_op(r, mlxc_fft_ifft2, a, spec, 'mlx_ifft2')
    end function mlx_ifft2

end module mlxf_fft
