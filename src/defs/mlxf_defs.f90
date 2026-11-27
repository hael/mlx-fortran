!@descr: the constants and vocabularies more than one module uses: the hard-error status, the devices, the dtypes
! A constant another module imports lives here; one used only inside its module stays there. The vocabularies
! are one plural constant each, with a component per code, so that a variable holding one code (device, dtype)
! never shadows the family. The codes are mlx-c's, which this module imports and keeps private.
module mlxf_defs
use, intrinsic :: iso_c_binding, only: c_double, c_float, c_int64_t
use mlxf_c_types, only: MLXC_FFT_NORM_BACKWARD, MLXC_FFT_NORM_ORTHO, MLXC_FFT_NORM_FORWARD, MLXC_CPU, MLXC_GPU, &
                        MLXC_COMPILE_MODE_DISABLED, MLXC_COMPILE_MODE_NO_SIMPLIFY, MLXC_COMPILE_MODE_NO_FUSE, &
                        MLXC_COMPILE_MODE_ENABLED, MLXC_BOOL, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, &
                        MLXC_COMPLEX64, MLXC_INT8, MLXC_INT16, MLXC_UINT8, MLXC_UINT16, MLXC_UINT32, MLXC_UINT64, &
                        MLXC_FLOAT16, MLXC_BFLOAT16, mlxc_distributed_group
implicit none

private :: MLXC_FFT_NORM_BACKWARD, MLXC_FFT_NORM_ORTHO, MLXC_FFT_NORM_FORWARD
private :: mlxc_distributed_group
private :: MLXC_COMPILE_MODE_DISABLED, MLXC_COMPILE_MODE_NO_SIMPLIFY, MLXC_COMPILE_MODE_NO_FUSE, MLXC_COMPILE_MODE_ENABLED
private :: c_double, c_float, c_int64_t
private :: MLXC_CPU, MLXC_GPU, MLXC_BOOL, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, MLXC_COMPLEX64
private :: MLXC_INT8, MLXC_INT16, MLXC_UINT8, MLXC_UINT16, MLXC_UINT32, MLXC_UINT64, MLXC_FLOAT16, MLXC_BFLOAT16

! the exit status of every stop the library makes, so that a test can tell it from a runtime failure
integer, parameter :: MLXF_HARD_ERROR_STATUS = 86

! what mlx-c's map iterators return when no pair is left (0 is a pair, 1 a failure)
integer, parameter :: MLXF_MAP_END = 2

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

! what mlx_compile does to a function, for mlx_set_compile_mode: nothing (disabled: the callback runs at every
! call), everything but the simplification of the graph (no_simplify), everything but the fusion of its
! operations into kernels (no_fuse), or all of it (enabled, MLX's default)
type :: mlx_compile_mode_codes
    integer :: disabled    = int(MLXC_COMPILE_MODE_DISABLED)
    integer :: no_simplify = int(MLXC_COMPILE_MODE_NO_SIMPLIFY)
    integer :: no_fuse     = int(MLXC_COMPILE_MODE_NO_FUSE)
    integer :: enabled     = int(MLXC_COMPILE_MODE_ENABLED)
end type mlx_compile_mode_codes
type(mlx_compile_mode_codes), parameter :: MLX_COMPILE_MODES = mlx_compile_mode_codes()
type :: mlxf_slice_spec
    integer, allocatable :: lower(:), upper(:), stride(:)
end type mlxf_slice_spec

type :: mlxf_fft_spec
    integer :: dims(2) = [1, 2]
    integer :: n(2) = [-1, -1]
    integer :: norm = 0
end type mlxf_fft_spec

! a transform over several dimensions: the Fortran dimensions in the order MLX takes their axes (it halves a
! real transform along the last), the length along each, and the norm
type :: mlxf_fftn_spec
    integer, allocatable :: dims(:), n(:)
    integer              :: norm = 0
end type mlxf_fftn_spec

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

! the options of a convolution (mlx_conv1d to mlx_conv3d, mlx_conv_general, mlx_conv_transpose1d to 3d), one
! value per spatial dimension in Fortran order (dimension 2 of the input first). An absent list is the default
! (stride 1, padding 0, dilation 1, input dilation 1, output padding 0) and a list of one value serves every
! spatial dimension. padding pads both ends of the input of a convolution with zeros and takes as much from both
! ends of the result of a transposed one; mlx_conv_general alone pads the far end by padding_hi instead when it
! is present, spreads the input by input_dilation and reverses the kernel with flip. output_padding belongs to
! the transposed convolutions; groups is at least 1
type :: mlx_conv_spec
    integer, allocatable :: stride(:), padding(:), dilation(:)
    integer, allocatable :: output_padding(:), padding_hi(:), input_dilation(:)
    integer              :: groups = 1
    logical              :: flip = .false.
end type mlx_conv_spec

! what a norm takes besides its array: the order as a number or as the name of a matrix norm, the Fortran
! dimensions in the order MLX takes their axes, whether they stay with extent 1, and whether the norm is one
! MLX computes on the CPU only (those of the singular values)
type :: mlxf_norm_spec
    real(c_double)       :: ord = 2
    character(len=8)     :: name = ''
    integer, allocatable :: dims(:)
    logical              :: keepdims = .false.
    logical              :: on_cpu = .false.
end type mlxf_norm_spec

! what a sampler takes besides its arrays and its key: the Fortran shape of the sample, its dtype, a count (the
! width of random bits in bytes, the samples per distribution, the length of a permutation), the dimension of the
! categories or of a permutation, a location and a scale, and whether MLX draws the sample on the CPU only
type :: mlxf_random_spec
    integer, allocatable :: shape(:)
    integer              :: dtype = int(MLXC_FLOAT32)
    integer              :: number = 0
    integer              :: dim = 1
    real(c_float)        :: loc = 0, scale = 1
    logical              :: on_cpu = .false.
end type mlxf_random_spec

! the options of a rotary position embedding (mlx_rope): how many elements of dimension 1 are rotated, from the
! first (even; 0: all of them); traditional pairs neighbours (1, 2), (3, 4), ..., otherwise element p goes with
! element p + features/2; the base of the divisors of the angle, base**((p-1)/(features/2)) for pair p, used when
! none are given; the scale of the positions; and the number of positions before the first
type :: mlx_rope_spec
    integer       :: features = 0
    logical       :: traditional = .false.
    real(c_float) :: base = 10000._c_float
    real(c_float) :: scale = 1._c_float
    integer       :: offset = 0
end type mlx_rope_spec

! the options of mlx_scaled_dot_product_attention: the factor of the scores (not set: one over the square root
! of the queries' first extent), whether a query attends only the keys up to its own position, and whether MLX's
! fused kernel is demanded (it then stops where it has none)
type :: mlx_attention_spec
    real(c_float), allocatable :: scale
    logical                    :: causal = .false.
    logical                    :: force_fused = .false.
end type mlx_attention_spec

! what a distributed operation takes besides its array: the group (a null handle is MLX's default group), the
! zero-based rank of the peer, the Fortran shape and the dtype of what is received, and the name of the public
! procedure, for the messages
type :: mlxf_group_spec
    type(mlxc_distributed_group)  :: group
    integer                       :: peer = 0
    integer,          allocatable :: shape(:)
    integer                       :: dtype = int(MLXC_FLOAT32)
    character(len=:), allocatable :: proc
end type mlxf_group_spec

! a custom kernel and its launch (mlx_custom_kernel) for MLX's Metal or CUDA backend: the body of the Metal function
! (source) and of the CUDA function (cuda_source), declarations put before either (header; CUDA compiles it with
! NVRTC, where a plain function is device code), the names its buffers take in the sources, the thread grid and the
! threadgroup as (x, y, z) (CUDA launches whole blocks of the threadgroup, so a CUDA source guards its index), the
! dynamic shared memory of a CUDA launch in bytes, and the outputs. output_shapes holds the outputs' Fortran shapes
! one after another and output_ranks how many extents each takes (absent: the outputs share them equally); absent
! output_dtypes are float32. A template parameter is a name with a dtype, an integer or a logical. With init_value
! every output is filled with it before the kernel runs (atomic_outputs is Metal's; a CUDA source adds atomically
! to a plain output). The sources index MLX's buffers, row-major and 0-based
type :: mlx_custom_kernel_spec
    character(len=:), allocatable :: name, source, cuda_source, header
    character(len=:), allocatable :: input_names(:), output_names(:)
    integer                       :: grid(3) = [1, 1, 1], threadgroup(3) = [1, 1, 1], shared_memory = 0
    integer,          allocatable :: output_shapes(:), output_ranks(:), output_dtypes(:)
    character(len=:), allocatable :: template_dtype_names(:), template_int_names(:), template_bool_names(:)
    integer,          allocatable :: template_dtypes(:), template_ints(:)
    logical,          allocatable :: template_bools(:)
    real(c_float),    allocatable :: init_value
    logical                       :: ensure_row_contiguous = .true., atomic_outputs = .false., verbose = .false.
end type mlx_custom_kernel_spec

! what lstat says of a path (mlxf_libc's c_file_info), the link itself and not what it names: whether it exists,
! is a symbolic link or a regular file, its permission bits (with set-id and sticky), its hard links and its owner
type :: mlxf_file_info
    logical :: exists  = .false.
    logical :: link    = .false.
    logical :: regular = .false.
    integer :: mode    = 0
    integer :: nlink   = 0
    integer :: uid     = -1
end type mlxf_file_info

! a save in progress (mlxf_io's mlxf_save_begin and mlxf_save_end): the destination, its name settled once (MLX's
! suffix added where it is missing), the temporary sibling written first, and whether the destination existed, with
! its permission bits
type :: mlxf_save_target
    character(len=:), allocatable :: dest, temp
    logical                       :: existed = .false.
    integer                       :: mode    = 0
end type mlxf_save_target

end module mlxf_defs
