!@descr: the constants and vocabularies more than one module uses: the hard-error status, the devices, the dtypes
! A constant another module imports lives here; one used only inside its module stays there. The vocabularies
! are one plural constant each, with a component per code, so that a variable holding one code (device, dtype)
! never shadows the family. The codes are mlx-c's, which this module imports and keeps private.
module mlxf_defs
use mlxf_c_types, only: MLXC_CPU, MLXC_GPU, MLXC_BOOL, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, &
                        MLXC_COMPLEX64
implicit none

private :: MLXC_CPU, MLXC_GPU, MLXC_BOOL, MLXC_INT32, MLXC_INT64, MLXC_FLOAT32, MLXC_FLOAT64, MLXC_COMPLEX64

! the exit status of every stop the library makes, so that a test can tell it from a runtime failure
integer, parameter :: MLXF_HARD_ERROR_STATUS = 86

! the device types the device procedures take and return
type :: mlx_device_codes
    integer :: cpu = int(MLXC_CPU)
    integer :: gpu = int(MLXC_GPU)
end type mlx_device_codes
type(mlx_device_codes), parameter :: MLX_DEVICES = mlx_device_codes()

! the element types a%kind() returns
type :: mlx_dtype_codes
    integer :: bool      = int(MLXC_BOOL)
    integer :: int32     = int(MLXC_INT32)
    integer :: int64     = int(MLXC_INT64)
    integer :: float32   = int(MLXC_FLOAT32)
    integer :: float64   = int(MLXC_FLOAT64)
    integer :: complex64 = int(MLXC_COMPLEX64)
end type mlx_dtype_codes
type(mlx_dtype_codes), parameter :: MLX_DTYPES = mlx_dtype_codes()

end module mlxf_defs
