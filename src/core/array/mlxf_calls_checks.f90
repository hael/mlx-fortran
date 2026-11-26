!@descr: the checks and translations the helpers share: dtypes, dimensions, sections, positions, streams
submodule(mlxf_calls) mlxf_calls_checks
use, intrinsic :: iso_c_binding,   only: c_null_ptr
use, intrinsic :: iso_fortran_env, only: int16, int32, int64, int8
use mlxf_c_device, only: mlxc_device_free, mlxc_device_new_type
use mlxf_c_ops,    only: mlxc_add, mlxc_astype, mlxc_subtract
use mlxf_c_stream, only: mlxc_get_default_stream, mlxc_stream_new
use mlxf_c_types,  only: MLXC_CPU, mlxc_device
use mlxf_defs,     only: MLX_DTYPES
use mlxf_array,    only: mlxf_handle, mlxf_is_empty
use mlxf_error,    only: mlxf_check, mlxf_fail
use mlxf_transfer, only: mlx_from
implicit none

contains

    ! stops unless dtype is a member of MLX_DTYPES: mlx-c converts it through a table it indexes unchecked
    module subroutine mlxf_check_dtype( dtype, proc )
        integer,          intent(in) :: dtype
        character(len=*), intent(in) :: proc
        if( all(dtype /= [MLX_DTYPES%bool, MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, &
            &MLX_DTYPES%uint8, MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64, MLX_DTYPES%float16, &
            &MLX_DTYPES%bfloat16, MLX_DTYPES%float32, MLX_DTYPES%float64, MLX_DTYPES%complex64]) ) &
            &call mlxf_fail(proc, 'the dtype must be a member of MLX_DTYPES')
    end subroutine mlxf_check_dtype

    ! the MLX axes of the Fortran dimensions dims of a, each checked against its rank
    module function mlxf_axes_of( a, dims, proc ) result(axes)
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dims(:)
        character(len=*), intent(in) :: proc
        integer(c_int), allocatable :: axes(:)
        integer                     :: i, nd
        nd = a%ndim()
        allocate(axes(size(dims)))
        do i = 1, size(dims)
            if( dims(i) < 1 .or. dims(i) > nd ) call mlxf_fail(proc, 'dimension outside array rank')
            axes(i) = int(nd-dims(i), c_int)
        end do
    end function mlxf_axes_of

    ! 1-based integer positions as MLX's: one subtracted in the graph, or the amounts less, broadcast along
    ! dimension 1; a non-integer array stops. uint64 goes through int64 first, since MLX promotes uint64 with a
    ! signed integer to a float
    module subroutine mlxf_zero_based( r, indices, proc, less )
        type(mlx_array),  intent(inout)        :: r
        type(mlx_array),  intent(in)           :: indices
        character(len=*), intent(in)           :: proc
        integer,          optional, intent(in) :: less(:)
        type(mlx_array) :: offset, signed
        integer         :: dtype
        dtype = indices%kind()
        if( all(dtype /= [MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, MLX_DTYPES%uint8, &
            &MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64]) ) call mlxf_fail(proc, 'indices must be integers')
        if( present(less) )then
            offset = mlx_from(int(less, int32))
        else
            offset = mlx_from(1_int32)
        endif
        if( dtype == MLX_DTYPES%uint64 )then
            call mlxf_int_op(signed, mlxc_astype, indices, MLX_DTYPES%int64, proc)
            call mlxf_binary(r, mlxc_subtract, signed, offset, proc)
        else
            call mlxf_binary(r, mlxc_subtract, indices, offset, proc)
        endif
    end subroutine mlxf_zero_based

    ! MLX's 0-based positions as Fortran's: int32, one added in the graph
    module subroutine mlxf_one_based( r, idx, proc )
        type(mlx_array),  intent(inout) :: r
        type(mlx_array),  intent(in)    :: idx
        character(len=*), intent(in)    :: proc
        type(mlx_array) :: cast, one
        call mlxf_int_op(cast, mlxc_astype, idx, MLX_DTYPES%int32, proc)
        one = mlx_from(1_int32)
        call mlxf_binary(r, mlxc_add, cast, one, proc)
    end subroutine mlxf_one_based

    ! stops unless dim is a dimension of a (1 to its rank)
    module subroutine mlxf_check_dim( a, dim, proc )
        type(mlx_array),  intent(in) :: a
        integer,          intent(in) :: dim
        character(len=*), intent(in) :: proc
        integer :: nd
        nd = a%ndim()
        if( dim < 1 .or. dim > nd ) call mlxf_fail(proc, 'dimension outside array rank')
    end subroutine mlxf_check_dim

    ! MLX's start, stop and strides (the columns of b) of the section option of a: Fortran's inclusive 1-based
    ! bounds reversed, 0-based and stop excluded; with a negative stride the stop is upper - 2, moved below
    ! -extent when negative so that MLX's negative-index rule leaves it before the first element
    module subroutine mlxf_slice_bounds( a, option, b, proc )
        type(mlx_array),       intent(in)               :: a
        type(mlxf_slice_spec), intent(in)               :: option
        integer(c_int),        allocatable, intent(out) :: b(:,:)
        character(len=*),      intent(in)               :: proc
        integer, allocatable :: sh(:)
        integer              :: n, j, k
        n = a%ndim()
        sh = a%shape()
        if( size(option%lower) /= n .or. size(option%upper) /= n .or. size(option%stride) /= n ) &
            &call mlxf_fail(proc, 'bounds and stride must match rank')
        if( any(option%stride == 0) ) call mlxf_fail(proc, 'zero stride')
        if( any(option%lower < 1) .or. any(option%lower > sh) .or. any(option%upper < 1) .or. any(option%upper > sh) ) &
            &call mlxf_fail(proc, 'slice bounds outside array')
        allocate(b(n, 3))
        do j = 1, n
            k = n+1-j
            b(j, 1) = int(option%lower(k)-1, c_int)
            b(j, 3) = int(option%stride(k), c_int)
            b(j, 2) = int(option%upper(k), c_int)
            if( b(j, 3) < 0 )then
                b(j, 2) = b(j, 2)-2
                if( b(j, 2) < 0 ) b(j, 2) = b(j, 2)-int(sh(k), c_int)
            endif
        end do
    end subroutine mlxf_slice_bounds

    ! the default stream of the CPU, where MLX runs what it implements on the CPU only whatever the default
    ! device; the caller frees it with mlxc_stream_free
    module function mlxf_cpu_stream( proc ) result(s)
        character(len=*), intent(in) :: proc
        type(mlxc_stream) :: s
        type(mlxc_device) :: dev
        dev = mlxc_device_new_type(MLXC_CPU, 0_c_int)
        s = mlxc_stream_new()
        call mlxf_check(mlxc_get_default_stream(s, dev), proc)
        call mlxf_check(mlxc_device_free(dev), proc)
    end function mlxf_cpu_stream

    ! the handle of an operand mlx-c may be given as null: null for an empty array, validated otherwise
    module function mlxf_optional_handle( a, proc ) result(h)
        type(mlx_array),  intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
        h%ctx = c_null_ptr
        if( .not. mlxf_is_empty(a) ) h = mlxf_handle(a, proc)
    end function mlxf_optional_handle

end submodule mlxf_calls_checks
