!@descr: the user module of mlx-fortran: re-exports the public names of the mlxf_* modules
! Users write `use mlxf` (with an only: list). The generated mlxc_* layer and the library's mlxf_* helpers
! stay private to the library.
module mlxf
use mlxf_defs,     only: MLXF_HARD_ERROR_STATUS, MLX_DEVICES, MLX_DTYPES, MLX_FFT_NORMS
use mlxf_version,  only: mlxf_version_string, mlxf_build_description, mlx_runtime_version, mlxf_runtime_description
use mlxf_error,    only: mlx_last_error
use mlxf_registry, only: mlx_live_count
use mlxf_device,   only: mlx_device_count, mlx_default_device, mlx_set_default_device, mlx_device_info_size, &
                         mlx_device_info_string
use mlxf_memory,   only: mlx_active_memory, mlx_peak_memory, mlx_reset_peak_memory, mlx_cache_memory, mlx_clear_cache, &
                         mlx_set_memory_limit, mlx_set_cache_limit
use mlxf_array,    only: mlx_array, mlx_from, mlx_to, mlx_to_alloc, mlx_view, mlx_alloc, mlx_eval, mlx_async_eval, &
                         mlx_synchronize, mlx_is_live, exp
use mlxf_ops,      only: real, aimag, conjg, sqrt, mlx_astype, mlx_bitcast, max, merge, cmplx, reshape, mlx_permute, &
                         transpose, mlx_concatenate, mlx_slice, mlx_take_along_dim, mlx_take, sum, minval, &
                         mlx_logsumexp, mlx_cumsum, minloc, mlx_zeros, mlx_arange, abs, sin, cos, tan, sinh, cosh, &
                         tanh, log, log10, erf, asin, acos, atan, asinh, acosh, atanh, floor, ceiling, aint, mlx_sign, &
                         mlx_sigmoid, mlx_square, mlx_reciprocal, mlx_rsqrt, mlx_expm1, mlx_log1p, mlx_log2, &
                         mlx_erfinv, mlx_degrees, mlx_radians, mlx_stop_gradient, mlx_copy, mlx_isnan, mlx_isinf, &
                         mlx_isfinite, mlx_isposinf, mlx_isneginf, mlx_round, mlx_clip, mlx_nan_to_num, atan2, modulo, &
                         min, mlx_logaddexp, mlx_floor_divide, mlx_divmod, mlx_isclose, mlx_allclose, mlx_array_equal, &
                         iand, ior, ieor, not, shiftl, mlx_right_shift, mlx_ones, mlx_full, mlx_zeros_like, &
                         mlx_ones_like, mlx_full_like
use mlxf_linalg,   only: matmul
use mlxf_fft,      only: mlx_fft, mlx_ifft, mlx_rfft, mlx_irfft, mlx_fft2, mlx_ifft2
use mlxf_compile,  only: mlx_function, mlx_compile
implicit none

public :: mlxf_version_string, mlxf_build_description, mlx_runtime_version, mlxf_runtime_description
public :: MLXF_HARD_ERROR_STATUS, MLX_DEVICES, MLX_DTYPES, mlx_last_error, mlx_live_count
public :: mlx_device_count, mlx_default_device, mlx_set_default_device, mlx_device_info_size
public :: mlx_device_info_string
public :: mlx_active_memory, mlx_peak_memory, mlx_reset_peak_memory, mlx_cache_memory, mlx_clear_cache
public :: mlx_set_memory_limit, mlx_set_cache_limit
public :: mlx_array, mlx_from, mlx_to, mlx_to_alloc, mlx_view, mlx_alloc, mlx_eval, mlx_async_eval
public :: mlx_synchronize, mlx_is_live, exp
public :: real, &
    &aimag, &
    &conjg, &
    &sqrt, &
    &mlx_astype, &
    &mlx_bitcast, &
    &max, &
    &merge, &
    &cmplx, &
    &reshape, &
    &mlx_permute, &
    &transpose, &
    &mlx_concatenate, &
    &mlx_slice, &
    &mlx_take_along_dim, &
    &mlx_take, &
    &sum, &
    &minval, &
    &mlx_logsumexp, &
    &mlx_cumsum, &
    &minloc, &
    &mlx_zeros, &
    &mlx_arange, &
    &abs, &
    &sin, &
    &cos, &
    &tan, &
    &sinh, &
    &cosh, &
    &tanh, &
    &log, &
    &log10, &
    &erf, &
    &asin, &
    &acos, &
    &atan, &
    &asinh, &
    &acosh, &
    &atanh, &
    &floor, &
    &ceiling, &
    &aint, &
    &mlx_sign, &
    &mlx_sigmoid, &
    &mlx_square, &
    &mlx_reciprocal, &
    &mlx_rsqrt, &
    &mlx_expm1, &
    &mlx_log1p, &
    &mlx_log2, &
    &mlx_erfinv, &
    &mlx_degrees, &
    &mlx_radians, &
    &mlx_stop_gradient, &
    &mlx_copy, &
    &mlx_isnan, &
    &mlx_isinf, &
    &mlx_isfinite, &
    &mlx_isposinf, &
    &mlx_isneginf, &
    &mlx_round, &
    &mlx_clip, &
    &mlx_nan_to_num, &
    &atan2, &
    &modulo, &
    &min, &
    &mlx_logaddexp, &
    &mlx_floor_divide, &
    &mlx_divmod, &
    &mlx_isclose, &
    &mlx_allclose, &
    &mlx_array_equal, &
    &iand, &
    &ior, &
    &ieor, &
    &not, &
    &shiftl, &
    &mlx_right_shift, &
    &mlx_ones, &
    &mlx_full, &
    &mlx_zeros_like, &
    &mlx_ones_like, &
    &mlx_full_like, &
    &matmul, &
    &mlx_fft, &
    &mlx_ifft, &
    &mlx_rfft, &
    &mlx_irfft, &
    &mlx_fft2, &
    &mlx_ifft2, &
    &MLX_FFT_NORMS
public :: mlx_function, mlx_compile
private

end module mlxf
