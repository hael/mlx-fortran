!@descr: the constants and vocabularies more than one module uses: the hard-error status, the devices, the dtypes
! A constant another module imports lives here; one used only inside its module stays there. The vocabularies
! are one plural constant each, with a component per code, so that a variable holding one code (device, dtype)
! never shadows the family. The codes are mlx-c's, which this module imports and keeps private.
module mlxf_defs
use, intrinsic :: iso_c_binding, only: c_double, c_float, c_int64_t
use mlxf_c_types, only: MLXC_FFT_NORM_BACKWARD, MLXC_FFT_NORM_ORTHO, MLXC_FFT_NORM_FORWARD, MLXC_CPU, MLXC_GPU, &
                        MLXC_BOOL, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, MLXC_COMPLEX64, MLXC_INT8, &
                        MLXC_INT16, MLXC_UINT8, MLXC_UINT16, MLXC_UINT32, MLXC_UINT64, MLXC_FLOAT16, MLXC_BFLOAT16
implicit none

private :: MLXC_FFT_NORM_BACKWARD, MLXC_FFT_NORM_ORTHO, MLXC_FFT_NORM_FORWARD
private :: c_double, c_float, c_int64_t
private :: MLXC_CPU, MLXC_GPU, MLXC_BOOL, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, MLXC_COMPLEX64
private :: MLXC_INT8, MLXC_INT16, MLXC_UINT8, MLXC_UINT16, MLXC_UINT32, MLXC_UINT64, MLXC_FLOAT16, MLXC_BFLOAT16

! the exit status of every stop the library makes, so that a test can tell it from a runtime failure
integer, parameter :: MLXF_HARD_ERROR_STATUS = 86

! the device types the device procedures take and return
type :: mlx_device_codes
    integer :: cpu = int(MLXC_CPU)
    integer :: gpu = int(MLXC_GPU)
end type mlx_device_codes
type(mlx_device_codes), parameter :: MLX_DEVICES = mlx_device_codes()

! the element types a%kind() returns; the unsigned integers and the 16-bit floats exist on the device only (no
! Fortran kind transfers them: convert with mlx_astype)
type :: mlx_dtype_codes
    integer :: bool      = int(MLXC_BOOL)
    integer :: int32     = int(MLXC_INT32)
    integer :: int64     = int(MLXC_INT64)
    integer :: float32   = int(MLXC_FLOAT32)
    integer :: float64   = int(MLXC_FLOAT64)
    integer :: complex64 = int(MLXC_COMPLEX64)
    integer :: int8      = int(MLXC_INT8)
    integer :: int16     = int(MLXC_INT16)
    integer :: uint8     = int(MLXC_UINT8)
    integer :: uint16    = int(MLXC_UINT16)
    integer :: uint32    = int(MLXC_UINT32)
    integer :: uint64    = int(MLXC_UINT64)
    integer :: float16   = int(MLXC_FLOAT16)
    integer :: bfloat16  = int(MLXC_BFLOAT16)
end type mlx_dtype_codes
type(mlx_dtype_codes), parameter :: MLX_DTYPES = mlx_dtype_codes()

type :: mlx_fft_norm_codes
    integer :: backward = int(MLXC_FFT_NORM_BACKWARD)
    integer :: ortho = int(MLXC_FFT_NORM_ORTHO)
    integer :: forward = int(MLXC_FFT_NORM_FORWARD)
end type mlx_fft_norm_codes
type(mlx_fft_norm_codes), parameter :: MLX_FFT_NORMS = mlx_fft_norm_codes()
type                                :: mlxf_slice_spec
    integer, allocatable :: lower(:), upper(:), stride(:)
end type mlxf_slice_spec

type :: mlxf_fft_spec
    integer :: dims(2) = [1, 2]
    integer :: n(2) = [-1, -1]
    integer :: norm = 0
end type mlxf_fft_spec

type :: mlxf_range_spec
    real(c_double) :: start = 0, stop = 0, step = 1
    integer        :: dtype = int(MLXC_FLOAT32)
end type mlxf_range_spec

! the tolerances of an elementwise closeness test: |a - b| <= atol + rtol |b|, NaNs equal when equal_nan
type :: mlxf_close_spec
    real(c_double) :: rtol = 1.e-5_c_double, atol = 1.e-8_c_double
    logical        :: equal_nan = .false.
end type mlxf_close_spec

! the replacements of NaN and of the infinities; an infinity without has_* keeps the dtype's largest finite
type :: mlxf_nan_spec
    real(c_float) :: nan = 0, posinf = 0, neginf = 0
    logical       :: has_posinf = .false., has_neginf = .false.
end type mlxf_nan_spec

! a Fortran-order shape and an element type, for constructors that also take an array
type :: mlxf_shape_spec
    integer, allocatable :: shape(:)
    integer              :: dtype = int(MLXC_FLOAT32)
end type mlxf_shape_spec

! what a reduction takes besides its array: one dimension (dim) or a list (dims), whether the reduced dimensions
! stay with extent 1, and the delta degrees of freedom of a variance
type :: mlxf_reduce_spec
    integer              :: dim = 1
    integer, allocatable :: dims(:)
    logical              :: keepdims = .false.
    integer              :: ddof = 0
end type mlxf_reduce_spec

! a scan's dimension, its direction (reverse: from the last element) and whether an element counts itself
type :: mlxf_scan_spec
    integer :: dim = 1
    logical :: reverse = .false., inclusive = .true.
end type mlxf_scan_spec

! the widths of a padding: low and high per Fortran dimension, or one width for both sides of every dimension;
! mode is MLX's: 'constant' (the fill value), 'edge' (the border value repeated), ...; MLX checks it
type :: mlxf_pad_spec
    integer, allocatable :: low(:), high(:)
    integer              :: width = 0
    character(len=16)    :: mode = 'constant'
end type mlxf_pad_spec

! a strided view: its Fortran shape, the stride of each dimension in elements, and the elements skipped first
type :: mlxf_strided_spec
    integer,            allocatable :: shape(:)
    integer(c_int64_t), allocatable :: strides(:)
    integer(c_int64_t)              :: offset = 0
end type mlxf_strided_spec

! the dimensions whose extents are multiplied, whether the reciprocal is returned, and the result's dtype
type :: mlxf_count_spec
    integer, allocatable :: dims(:)
    logical              :: inverted = .false.
    integer              :: dtype = int(MLXC_FLOAT32)
end type mlxf_count_spec

! num evenly spaced values from start to stop, stop included when endpoint holds
type :: mlxf_linspace_spec
    real(c_double) :: start = 0, stop = 1
    integer        :: num = 50
    logical        :: endpoint = .true.
    integer        :: dtype = int(MLXC_FLOAT32)
end type mlxf_linspace_spec

! the axes and the slice sizes of a gather or a dynamic slice, as MLX takes them
type :: mlxf_index_spec
    integer, allocatable :: axes(:), sizes(:)
end type mlxf_index_spec

end module mlxf_defs
