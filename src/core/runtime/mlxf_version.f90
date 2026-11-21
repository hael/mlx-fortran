!@descr: versions of mlx-fortran, of the mlx-c it was built against and of the MLX it runs on; the runtime description
module mlxf_version
use mlxf_c_types,   only: mlxc_string
use mlxf_c_string,  only: mlxc_string_new, mlxc_string_data, mlxc_string_free
use mlxf_c_version, only: mlxc_version
use mlxf_defs,      only: MLX_DEVICES
use mlxf_libc,      only: c_string_copy
use mlxf_error,     only: mlxf_check
use mlxf_device,    only: mlxf_enter, mlx_device_count, mlx_default_device, mlx_device_info_string
implicit none

public :: mlxf_version_string, mlxf_build_description, mlx_runtime_version, mlxf_runtime_description
private

#include "mlxf_build_info.inc"

contains

    ! the mlx-fortran release
    pure function mlxf_version_string() result(v)
        character(len=:), allocatable :: v
        v = BUILD_INFO_RELEASE
    end function mlxf_version_string

    ! the release, build type and Fortran compiler, and the mlx-c the library was configured with
    pure function mlxf_build_description() result(d)
        character(len=:), allocatable :: d
        d = 'mlx-fortran '//BUILD_INFO_RELEASE//' ('//BUILD_INFO_BUILD_TYPE//', '//BUILD_INFO_FC//&
            &', mlx-c '//BUILD_INFO_MLXC//')'
    end function mlxf_build_description

    ! the version of the MLX library loaded at run time
    function mlx_runtime_version() result(v)
        character(len=:), allocatable :: v
        type(mlxc_string)             :: str
        call mlxf_enter('mlx_runtime_version')
        str = mlxc_string_new()
        call mlxf_check(mlxc_version(str), 'mlx_runtime_version')
        v = c_string_copy(mlxc_string_data(str))
        call mlxf_check(mlxc_string_free(str), 'mlx_runtime_version')
    end function mlx_runtime_version

    ! what decides MLX's arithmetic here: its version, the default device, the GPU's architecture and
    ! MLX_ENABLE_TF32 (MLX's own variable: unset or 1 lets GPUs with matrix units multiply float32 at reduced
    ! precision; the library never changes it)
    function mlxf_runtime_description() result(d)
        character(len=:), allocatable :: d, dev, arch, tf32
        character(len=64)             :: buf
        integer                       :: n, stat
        call mlxf_enter('mlxf_runtime_description')
        dev = 'cpu'
        if( mlx_default_device() == MLX_DEVICES%gpu ) dev = 'gpu'
        arch = 'none'
        if( mlx_device_count(MLX_DEVICES%gpu) > 0 ) arch = mlx_device_info_string(MLX_DEVICES%gpu, 'architecture')
        call get_environment_variable('MLX_ENABLE_TF32', buf, length=n, status=stat)
        tf32 = 'unset'
        if( stat == 0 ) tf32 = buf(1:min(n, len(buf)))
        d = 'MLX '//mlx_runtime_version()//'; default device '//dev//'; GPU architecture '//arch//&
            &'; MLX_ENABLE_TF32='//tf32
    end function mlxf_runtime_description

end module mlxf_version
