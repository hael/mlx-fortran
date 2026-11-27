!@descr: the safe spellings of today's limits, and what the library now protects: integer statistics, checkpoints, untrusted indices, handle lists, long loops, host tests, wide-range norms
! mlxf_example_user_safety [require-gpu]: each block shows a limit of the present library and the spelling that
! avoids it, or a protection the library now gives, and checks the result; runs on the GPU where one opens (float64 on the CPU device), on the CPU device
! of a CPU-only MLX, and prints SKIP where MLX cannot allocate (a failure under require-gpu). It writes and removes
! a file in the current directory.
program mlxf_example_user_safety
use, intrinsic :: iso_fortran_env, only: real32, real64, int32
use, intrinsic :: iso_c_binding,   only: c_bool
use mlxf, only: mlx_array, mlx_from, mlx_to, mlx_item, mlx_eval, mlx_mean, mlx_take, mlx_concatenate, &
                mlx_check_indices, mlx_save_safetensors, mlx_live_count, mlx_last_error, mlx_device_count, &
                mlx_metal_is_available, mlx_set_default_device, MLX_DEVICES, exp, abs, all, maxval, norm2, mlx_zeros
implicit none
type(mlx_array)      :: k, m, x, t, c, ix, v(2), w(1)
real(real32)         :: mean, y(2), nrm, s
integer(int32)       :: raw(2)
logical(c_bool)      :: positive
character(len=32)    :: arg
integer              :: status, i, n0, u, nbytes, n0bytes
call get_command_argument(1, arg)
if( mlx_device_count(MLX_DEVICES%gpu) > 0 )then
    call mlx_set_default_device(MLX_DEVICES%gpu)
else if( trim(arg) == 'require-gpu' )then
    error stop 'mlxf_example_user_safety: require-gpu, and no GPU device in this session'
else if( .not. mlx_metal_is_available() )then
    call mlx_set_default_device(MLX_DEVICES%cpu)
else
    write(*,'(a)') 'SKIP: mlxf_example_user_safety: Metal without a GPU (headless, sandboxed, virtual)'
    stop
endif
n0 = mlx_live_count()
! S1 integer statistics: mlx_mean, mlx_var and mlx_std convert integer input to float32 first, so a large total
! cannot wrap (int64 values beyond 2**24 are rounded to float32 on the way)
raw = 2000000000
k = mlx_from(raw)
m = mlx_mean(k)
call mlx_item(m, mean, status=status)
if( status /= 0 .or. abs(mean - 2.e9) > 0. ) error stop 'mlxf_example_user_safety: S1 integer mean'
! S2 checkpoints: a save is written to a temporary file and renamed over its destination only when complete, so a
! save that fails (float64 in safetensors, here) leaves the old checkpoint as it was
x = mlx_from([1., 2.])
call mlx_save_safetensors('mlxf_safety_ckpt.safetensors', ['x'], [x], status=status)
if( status /= 0 ) error stop 'mlxf_example_user_safety: S2 first save'
inquire(file='mlxf_safety_ckpt.safetensors', size=nbytes)
call mlx_set_default_device(MLX_DEVICES%cpu)
w(1) = mlx_from([1._real64, 2._real64])
call mlx_save_safetensors('mlxf_safety_ckpt.safetensors', ['x'], w, status=status)
if( status == 0 ) error stop 'mlxf_example_user_safety: S2 a float64 safetensors save was accepted'
write(*,'(a)') 'S2 refused, the old checkpoint kept: '//mlx_last_error()
inquire(file='mlxf_safety_ckpt.safetensors', size=n0bytes)
if( n0bytes /= nbytes ) error stop 'mlxf_example_user_safety: S2 the old checkpoint changed'
call remove_file('mlxf_safety_ckpt.safetensors')
call w(1)%kill()
if( mlx_device_count(MLX_DEVICES%gpu) > 0 ) call mlx_set_default_device(MLX_DEVICES%gpu)
! S3 untrusted indices: mlx_check_indices checks them once against the extent before they reach a graph; the
! operations check none, and an index out of range reads outside the array (a zero, another element, or a crash)
ix = mlx_from([2, 1])
call mlx_check_indices(ix, 2, status)
if( status /= 0 ) error stop 'mlxf_example_user_safety: S3 '//mlx_last_error()
t = mlx_take(x, ix)
call mlx_to(y, t, status=status)
if( status /= 0 .or. any(abs(y - [2., 1.]) > 0.) ) error stop 'mlxf_example_user_safety: S3 take'
call mlx_check_indices(mlx_from([3]), 2, status)
if( status == 0 ) error stop 'mlxf_example_user_safety: S3 index 3 of an extent of 2 was accepted'
! S4 lists of handles: name each function result first, then list the variables; [x, exp(x)] or v = exp(x) leaks,
! and the installed check_consumer.py (mlxf_check_lifetime in CMake) reports such forms
t = exp(x)
c = mlx_concatenate([x, t])
do i = 1, 2
    v(i) = exp(x)
end do
call mlx_eval(c, status=status)
if( status /= 0 ) error stop 'mlxf_example_user_safety: S4 evaluation'
! S5 long loops: evaluate at a batch boundary; an unevaluated graph keeps every step (and every scalar) alive
t = x
do i = 1, 20000
    t = t * 0.999 + 0.001
    if( mod(i, 1000) == 0 ) call mlx_eval(t)
end do
call mlx_to(y, t, status=status)
if( status /= 0 .or. any(abs(y - (1. + ([1., 2.] - 1.) * 0.999**20000)) > 1.e-3) ) &
    error stop 'mlxf_example_user_safety: S5 recurrence'
! S6 host decisions: a reduction is a rank-0 array; mlx_item brings it to the host
call mlx_item(all(x > 0.), positive, status=status)
if( status /= 0 .or. .not. positive ) error stop 'mlxf_example_user_safety: S6 all'
! S7 wide-range norms and empty extrema: norm2 and mlx_mean scale by the largest magnitude, so values near the ends
! of the range give a finite norm (the plain sum of squares overflows above about 1e19 in float32); maxval of an
! empty extent is Fortran's -huge, in the operand's kind
x = mlx_from([1.e20, 1.e20])
call mlx_item(norm2(x), nrm, status=status)
if( status /= 0 .or. abs(nrm - sqrt(2.) * 1.e20) > 8. * epsilon(1.) * sqrt(2.) * 1.e20 ) &
    error stop 'mlxf_example_user_safety: S7 norm2 of 1e20'
t = maxval(mlx_zeros([0]))
call mlx_item(t, s, status=status)
if( status /= 0 .or. abs(s + huge(1.)) > 0. ) error stop 'mlxf_example_user_safety: S7 maxval of an empty array'
call k%kill()
call ix%kill()
call m%kill()
call x%kill()
call t%kill()
call c%kill()
call v%kill()
if( mlx_live_count() /= n0 ) error stop 'mlxf_example_user_safety: handles left alive'
write(*,'(a)') 'mlxf_example_user_safety: passed'

contains

    subroutine remove_file( name )
        character(len=*), intent(in) :: name
        logical :: there
        inquire(file=name, exist=there)
        if( .not. there ) return
        open(newunit=u, file=name, status='old')
        close(u, status='delete')
    end subroutine remove_file
end program mlxf_example_user_safety
