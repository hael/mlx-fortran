!@descr: the user module of mlx-fortran: re-exports the public names of the mlxf_* modules
! Users write `use mlxf` (with an only: list). The generated mlxc_* layer and the library's mlxf_* helpers
! stay private to the library.
module mlxf
use mlxf_defs,          only: MLXF_HARD_ERROR_STATUS, MLX_DEVICES, MLX_DTYPES, MLX_FFT_NORMS, mlx_metal_kernel_spec, &
                              mlx_conv_spec
use mlxf_version,       only: mlxf_version_string, mlxf_build_description, mlx_runtime_version, &
                              mlxf_runtime_description
use mlxf_error,         only: mlx_last_error
use mlxf_registry,      only: mlx_live_count
use mlxf_device,        only: mlx_device_count, mlx_default_device, mlx_set_default_device, mlx_device_info_size, &
                              mlx_device_info_string
use mlxf_memory,        only: mlx_active_memory, mlx_peak_memory, mlx_reset_peak_memory, mlx_cache_memory, &
                              mlx_clear_cache, mlx_set_memory_limit, mlx_set_cache_limit
use mlxf_array,         only: mlx_array, mlx_from, mlx_to, mlx_to_alloc, mlx_item, mlx_view, mlx_alloc, mlx_eval, &
                              mlx_async_eval, mlx_synchronize, mlx_is_live, exp
use mlxf_ops,           only: real, aimag, conjg, sqrt, mlx_astype, mlx_bitcast, max, merge, cmplx, reshape, &
                              mlx_permute, transpose, mlx_concatenate, mlx_slice, mlx_take_along_dim, mlx_take, sum, &
                              minval, mlx_logsumexp, mlx_cumsum, minloc, mlx_zeros, mlx_arange, abs, sin, cos, tan, &
                              sinh, cosh, tanh, log, log10, erf, asin, acos, atan, asinh, acosh, atanh, floor, ceiling, &
                              aint, mlx_sign, mlx_sigmoid, mlx_square, mlx_reciprocal, mlx_rsqrt, mlx_expm1, mlx_log1p, &
                              mlx_log2, mlx_erfinv, mlx_degrees, mlx_radians, mlx_stop_gradient, mlx_copy, mlx_isnan, &
                              mlx_isinf, mlx_isfinite, mlx_isposinf, mlx_isneginf, mlx_round, mlx_clip, mlx_nan_to_num, &
                              atan2, modulo, min, mlx_logaddexp, mlx_floor_divide, mlx_divmod, mlx_isclose, &
                              mlx_allclose, mlx_array_equal, iand, ior, ieor, not, shiftl, mlx_right_shift, mlx_ones, &
                              mlx_full, mlx_zeros_like, mlx_ones_like, mlx_full_like, product, maxval, all, any, count, &
                              maxloc, mlx_mean, mlx_median, mlx_var, mlx_std, mlx_cumprod, mlx_cummax, mlx_cummin, &
                              mlx_logcumsumexp, mlx_softmax, mlx_sort, mlx_argsort, mlx_partition, mlx_argpartition, &
                              mlx_topk, mlx_squeeze, mlx_expand_dims, mlx_flatten, mlx_unflatten, mlx_broadcast_to, &
                              mlx_broadcast_arrays, mlx_tile, mlx_repeat, mlx_pad, mlx_flip, cshift, mlx_movedim, &
                              mlx_swapdims, mlx_split, mlx_stack, mlx_unstack, mlx_atleast_1d, mlx_atleast_2d, &
                              mlx_atleast_3d, mlx_diag, mlx_diagonal, mlx_trace, mlx_tril, mlx_triu, mlx_diff, &
                              mlx_as_strided, mlx_number_of_elements, mlx_identity, mlx_eye, mlx_tri, mlx_linspace, &
                              mlx_meshgrid, mlx_bartlett, mlx_blackman, mlx_hamming, mlx_hanning, mlx_gather, &
                              mlx_scatter, mlx_scatter_add, mlx_scatter_max, mlx_scatter_min, mlx_scatter_prod, &
                              mlx_put_along_dim, mlx_masked_scatter, mlx_searchsorted, mlx_unique, mlx_slice_update, &
                              mlx_slice_update_add, mlx_slice_update_max, mlx_slice_update_min, mlx_slice_update_prod
use mlxf_linalg,        only: matmul, mlx_gather_mm, mlx_block_masked_mm, mlx_segmented_mm, mlx_addmm, mlx_inner, &
                              mlx_outer, mlx_kron, mlx_vecdot, mlx_cross, mlx_tensordot, mlx_einsum, &
                              mlx_hadamard_transform
use mlxf_linalg_matrix, only: mlx_inv, mlx_pinv, mlx_tri_inv, mlx_det, mlx_slogdet, mlx_cholesky, mlx_cholesky_inv, &
                              mlx_qr, mlx_lu, mlx_lu_factor, mlx_svd, mlx_eigh, mlx_eigvalsh, mlx_eig, mlx_eigvals, &
                              mlx_solve, mlx_solve_triangular, mlx_norm, mlx_norm_matrix, norm2
use mlxf_conv,          only: mlx_conv1d, mlx_conv2d, mlx_conv3d, mlx_conv_general, mlx_conv_transpose1d, &
                              mlx_conv_transpose2d, mlx_conv_transpose3d
use mlxf_fft,           only: mlx_fft, mlx_ifft, mlx_rfft, mlx_irfft, mlx_fft2, mlx_ifft2, mlx_fftn, mlx_ifftn, &
                              mlx_rfft2, mlx_irfft2, mlx_rfftn, mlx_irfftn, mlx_fftshift, mlx_ifftshift, mlx_fftfreq, &
                              mlx_rfftfreq
use mlxf_compile,       only: mlx_function, mlx_compile
use mlxf_fast,          only: mlx_metal_kernel
implicit none

public :: mlxf_version_string, mlxf_build_description, mlx_runtime_version, mlxf_runtime_description
public :: MLXF_HARD_ERROR_STATUS, MLX_DEVICES, MLX_DTYPES, mlx_last_error, mlx_live_count
public :: mlx_device_count, mlx_default_device, mlx_set_default_device, mlx_device_info_size
public :: mlx_device_info_string
public :: mlx_active_memory, mlx_peak_memory, mlx_reset_peak_memory, mlx_cache_memory, mlx_clear_cache
public :: mlx_set_memory_limit, mlx_set_cache_limit
public :: mlx_array, mlx_from, mlx_to, mlx_to_alloc, mlx_item, mlx_view, mlx_alloc, mlx_eval, mlx_async_eval
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
    &product, &
    &maxval, &
    &all, &
    &any, &
    &count, &
    &maxloc, &
    &mlx_mean, &
    &mlx_median, &
    &mlx_var, &
    &mlx_std, &
    &mlx_cumprod, &
    &mlx_cummax, &
    &mlx_cummin, &
    &mlx_logcumsumexp, &
    &mlx_softmax, &
    &mlx_sort, &
    &mlx_argsort, &
    &mlx_partition, &
    &mlx_argpartition, &
    &mlx_topk, &
    &mlx_squeeze, &
    &mlx_expand_dims, &
    &mlx_flatten, &
    &mlx_unflatten, &
    &mlx_broadcast_to, &
    &mlx_broadcast_arrays, &
    &mlx_tile, &
    &mlx_repeat, &
    &mlx_pad, &
    &mlx_flip, &
    &cshift, &
    &mlx_movedim, &
    &mlx_swapdims, &
    &mlx_split, &
    &mlx_stack, &
    &mlx_unstack, &
    &mlx_atleast_1d, &
    &mlx_atleast_2d, &
    &mlx_atleast_3d, &
    &mlx_diag, &
    &mlx_diagonal, &
    &mlx_trace, &
    &mlx_tril, &
    &mlx_triu, &
    &mlx_diff, &
    &mlx_as_strided, &
    &mlx_number_of_elements, &
    &mlx_identity, &
    &mlx_eye, &
    &mlx_tri, &
    &mlx_linspace, &
    &mlx_meshgrid, &
    &mlx_bartlett, &
    &mlx_blackman, &
    &mlx_hamming, &
    &mlx_hanning, &
    &mlx_gather, &
    &mlx_scatter, &
    &mlx_scatter_add, &
    &mlx_scatter_max, &
    &mlx_scatter_min, &
    &mlx_scatter_prod, &
    &mlx_put_along_dim, &
    &mlx_masked_scatter, &
    &mlx_searchsorted, &
    &mlx_unique, &
    &mlx_slice_update, &
    &mlx_slice_update_add, &
    &mlx_slice_update_max, &
    &mlx_slice_update_min, &
    &mlx_slice_update_prod, &
    &matmul, &
    &mlx_gather_mm, &
    &mlx_block_masked_mm, &
    &mlx_segmented_mm, &
    &mlx_addmm, &
    &mlx_inner, &
    &mlx_outer, &
    &mlx_kron, &
    &mlx_vecdot, &
    &mlx_cross, &
    &mlx_tensordot, &
    &mlx_einsum, &
    &mlx_hadamard_transform, &
    &mlx_inv, &
    &mlx_pinv, &
    &mlx_tri_inv, &
    &mlx_det, &
    &mlx_slogdet, &
    &mlx_cholesky, &
    &mlx_cholesky_inv, &
    &mlx_qr, &
    &mlx_lu, &
    &mlx_lu_factor, &
    &mlx_svd, &
    &mlx_eigh, &
    &mlx_eigvalsh, &
    &mlx_eig, &
    &mlx_eigvals, &
    &mlx_solve, &
    &mlx_solve_triangular, &
    &mlx_norm, &
    &mlx_norm_matrix, &
    &norm2, &
    &mlx_conv1d, &
    &mlx_conv2d, &
    &mlx_conv3d, &
    &mlx_conv_general, &
    &mlx_conv_transpose1d, &
    &mlx_conv_transpose2d, &
    &mlx_conv_transpose3d, &
    &mlx_conv_spec, &
    &mlx_fft, &
    &mlx_ifft, &
    &mlx_rfft, &
    &mlx_irfft, &
    &mlx_fft2, &
    &mlx_ifft2, &
    &mlx_fftn, &
    &mlx_ifftn, &
    &mlx_rfft2, &
    &mlx_irfft2, &
    &mlx_rfftn, &
    &mlx_irfftn, &
    &mlx_fftshift, &
    &mlx_ifftshift, &
    &mlx_fftfreq, &
    &mlx_rfftfreq, &
    &MLX_FFT_NORMS
public :: mlx_function, mlx_compile
public :: mlx_metal_kernel, mlx_metal_kernel_spec
private

end module mlxf
