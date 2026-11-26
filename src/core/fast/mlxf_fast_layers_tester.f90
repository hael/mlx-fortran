!@descr: the fused layers against plain Fortran loops: layer and RMS normalisation, cross entropy, rotary embeddings, attention
! Seeded operands on every device, float32 and on the CPU float64 as well. Each reference is written out in real64
! over Fortran subscripts (features along dimension 1, positions along dimension 2), so a result along another
! dimension has other values. A result is judged by its largest error relative to max(1, |reference|).
module mlxf_fast_layers_tester
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use, intrinsic :: iso_c_binding,   only: c_bool
use mlxf,             only: mlx_array, mlx_from, mlx_live_count, mlx_set_default_device, mlx_default_device, &
                            MLX_DEVICES, MLX_DTYPES, mlx_layer_norm, mlx_rms_norm, mlx_rope, mlx_rope_spec, &
                            mlx_scaled_dot_product_attention, mlx_attention_spec, mlx_cross_entropy
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name, judge_error, find_tolerance, &
                            family_seeds, seeded_uniform, seeded_array, shaped_error
use mlxf_test_defs,   only: ELEM_CEILING, FAST_TOLERANCES, elem_tolerance
use mlxf_test_reduce, only: nan_max
implicit none
private
public :: run_all_fast_layers_tests

! the extents of the fixtures: features, positions, an inner batch and a batch; keys and value features
integer, parameter :: ND = 8, NT = 6, NI = 3, NB = 2, NK = 5, NV = 6, NC = 5
! the features for which MLX has a fused attention kernel
integer, parameter :: NF = 64

contains

    subroutine run_all_fast_layers_tests
        integer, allocatable :: devs(:), seeds(:)
        integer              :: i, s, original, live0
        write(*,'(a)') '**** running all fast_layers tests ****'
        call assert_true(all(FAST_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a fused layer is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        seeds = family_seeds()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            do s = 1, size(seeds)
                call test_norms(seeds(s), .false.)
                call test_cross_entropy(seeds(s))
                call test_rope(seeds(s), .false.)
                call test_attention(seeds(s), .false.)
                if( devs(i) == MLX_DEVICES%gpu ) call test_fused_attention(seeds(s))
                if( devs(i) == MLX_DEVICES%cpu )then
                    call test_norms(seeds(s), .true.)
                    call test_rope(seeds(s), .true.)
                    call test_attention(seeds(s), .true.)
                endif
            end do
            call test_shapes_and_kinds
            call assert_int(live0, mlx_live_count(), 'the layers, their options and their arrays leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_fast_layers_tests

    ! the two normalisations along dimension 1, with and without weight and bias, with the default and a given eps
    subroutine test_norms( seed, wide )
        integer, intent(in) :: seed
        logical, intent(in) :: wide
        type(mlx_array)      :: a, w, b, r
        type(elem_tolerance) :: tol_layer, tol_rms
        real(real64)         :: x(ND, NT, NB), weight(ND), bias(ND), ones(ND), zeros(ND), ref(ND, NT, NB)
        real(real64)         :: err_layer, err_rms, eps
        write(*,'(a,i0,a,l1)') 'test_norms seed=', seed, ' wide=', wide
        tol_layer = find_tolerance(FAST_TOLERANCES, 'mlx_layer_norm')
        tol_rms = find_tolerance(FAST_TOLERANCES, 'mlx_rms_norm')
        x = reshape(seeded_uniform(ND*NT*NB, seed), [ND, NT, NB])
        weight = 1._real64+0.5_real64*seeded_uniform(ND, seed+10)
        bias = seeded_uniform(ND, seed+20)
        ones = 1._real64
        zeros = 0._real64
        a = seeded_array(x, wide)
        w = seeded_array(weight, wide)
        b = seeded_array(bias, wide)
        err_layer = 0._real64
        err_rms = 0._real64
        eps = real(1.e-5_real32, real64)
        r = mlx_layer_norm(a, w, b)
        ref = layer_norm_of(x, weight, bias, eps)
        err_layer = nan_max(err_layer, shaped_error(r, ref, abs(ref)))
        r = mlx_layer_norm(a)
        ref = layer_norm_of(x, ones, zeros, eps)
        err_layer = nan_max(err_layer, shaped_error(r, ref, abs(ref)))
        r = mlx_layer_norm(a, bias=b, eps=0.01_real32)
        ref = layer_norm_of(x, ones, bias, real(0.01_real32, real64))
        err_layer = nan_max(err_layer, shaped_error(r, ref, abs(ref)))
        r = mlx_layer_norm(a, weight=w)
        ref = layer_norm_of(x, weight, zeros, eps)
        err_layer = nan_max(err_layer, shaped_error(r, ref, abs(ref)))
        r = mlx_rms_norm(a, w)
        ref = rms_norm_of(x, weight, eps)
        err_rms = nan_max(err_rms, shaped_error(r, ref, abs(ref)))
        r = mlx_rms_norm(a, eps=0.01_real32)
        ref = rms_norm_of(x, ones, real(0.01_real32, real64))
        err_rms = nan_max(err_rms, shaped_error(r, ref, abs(ref)))
        call judge_error(err_layer, merge(tol_layer%f64, tol_layer%f32, wide), 'mlx_layer_norm', merge('float64', 'float32', wide), seed)
        call judge_error(err_rms, merge(tol_rms%f64, tol_rms%f32, wide), 'mlx_rms_norm', merge('float64', 'float32', wide), seed)
    end subroutine test_norms

    ! the cross entropy of logits along dimension 1 against one-based classes, the first and the last included
    subroutine test_cross_entropy( seed )
        integer, intent(in) :: seed
        type(mlx_array)      :: logits, targets, r
        type(elem_tolerance) :: tol
        real(real64)         :: l(NC, NT, NB), ref(NT, NB), err
        integer(int32)       :: t(NT, NB)
        integer              :: j, k
        write(*,'(a,i0)') 'test_cross_entropy seed=', seed
        tol = find_tolerance(FAST_TOLERANCES, 'mlx_cross_entropy')
        l = 3._real64*reshape(seeded_uniform(NC*NT*NB, seed+30), [NC, NT, NB])
        do k = 1, NB
            do j = 1, NT
                t(j, k) = int(1+modulo(j+2*k+seed, NC), int32)
                ref(j, k) = log(sum(exp(l(:, j, k))))-l(t(j, k), j, k)
            end do
        end do
        t(1, 1) = 1_int32
        t(2, 1) = int(NC, int32)
        ref(1, 1) = log(sum(exp(l(:, 1, 1))))-l(1, 1, 1)
        ref(2, 1) = log(sum(exp(l(:, 2, 1))))-l(NC, 2, 1)
        logits = seeded_array(l, .false.)
        targets = mlx_from(t)
        r = mlx_cross_entropy(logits, targets)
        err = shaped_error(r, ref, abs(ref))
        targets = mlx_from(int(t, int64))
        r = mlx_cross_entropy(logits, targets)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        call judge_error(err, tol%f32, 'mlx_cross_entropy', 'float32', seed)
    end subroutine test_cross_entropy

    ! rotary embeddings: every option, an integer and an array of offsets, given frequencies, ranks 3 and 4
    subroutine test_rope( seed, wide )
        integer, intent(in) :: seed
        logical, intent(in) :: wide
        type(mlx_array)      :: a, r, offs, fr
        type(mlx_rope_spec)  :: spec
        type(elem_tolerance) :: tol
        real(real64)         :: x(ND, NT, NB), x4(ND, NT, NI, NB), ref(ND, NT, NB), ref4(ND, NT, NI, NB), freqs(ND/2), err
        integer              :: none(NB), i
        write(*,'(a,i0,a,l1)') 'test_rope seed=', seed, ' wide=', wide
        tol = find_tolerance(FAST_TOLERANCES, 'mlx_rope')
        x = reshape(seeded_uniform(ND*NT*NB, seed+40), [ND, NT, NB])
        x4 = reshape(seeded_uniform(ND*NT*NI*NB, seed+50), [ND, NT, NI, NB])
        freqs = [1._real64, 2.5_real64, 7._real64, 20._real64]
        none = 0
        a = seeded_array(x, wide)
        err = 0._real64
        r = mlx_rope(a)
        ref = rope_of(x, mlx_rope_spec(features=ND, traditional=.false., base=10000._real32, scale=1._real32, offset=0), none)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        spec = mlx_rope_spec(features=4)
        r = mlx_rope(a, spec)
        ref = rope_of(x, spec, none)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        spec = mlx_rope_spec(features=6, traditional=.true.)
        r = mlx_rope(a, spec)
        ref = rope_of(x, spec, none)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        spec = mlx_rope_spec(features=ND, base=100._real32, scale=0.5_real32, offset=3)
        r = mlx_rope(a, spec)
        ref = rope_of(x, spec, [3, 3])
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        offs = mlx_from([2_int32, 5_int32])
        r = mlx_rope(a, spec, offset=offs)
        ref = rope_of(x, spec, [2, 5])
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        offs = mlx_from(4_int32)
        r = mlx_rope(a, offset=offs)
        ref = rope_of(x, mlx_rope_spec(features=ND), [4, 4])
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        fr = mlx_from(real(freqs, real32))
        spec = mlx_rope_spec(features=ND, traditional=.true., offset=1)
        r = mlx_rope(a, spec, freqs=fr)
        ref = rope_of(x, spec, [1, 1], freqs)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        spec = mlx_rope_spec(features=6)
        offs = mlx_from([2_int32, 5_int32])
        r = mlx_rope(a, spec, offset=offs, freqs=mlx_from(real(freqs(1:3), real32)))
        ref = rope_of(x, spec, [2, 5], freqs(1:3))
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        a = seeded_array(x(:, 1:1, :), wide)
        spec = mlx_rope_spec(features=ND, offset=3)
        r = mlx_rope(a, spec)
        ref(:, 1:1, :) = rope_of(x(:, 1:1, :), spec, [3, 3])
        err = nan_max(err, shaped_error(r, ref(:, 1:1, :), abs(ref(:, 1:1, :))))
        a = seeded_array(reshape(x4, [ND, NT, NI, 1, NB]), wide)
        spec = mlx_rope_spec(features=4, traditional=.true., scale=2._real32)
        offs = mlx_from([0_int32, 9_int32])
        r = mlx_rope(a, spec, offset=offs)
        do i = 1, NI
            ref4(:, :, i, :) = rope_of(x4(:, :, i, :), spec, [0, 9])
        end do
        err = nan_max(err, shaped_error(r, reshape(ref4, [ND, NT, NI, 1, NB]), reshape(abs(ref4), [ND, NT, NI, 1, NB])))
        a = seeded_array(x4, wide)
        offs = mlx_from([1_int32, 6_int32])
        spec = mlx_rope_spec(features=ND)
        r = mlx_rope(a, spec, offset=offs)
        do i = 1, NI
            ref4(:, :, i, :) = rope_of(x4(:, :, i, :), spec, [1, 6])
        end do
        err = nan_max(err, shaped_error(r, ref4, abs(ref4)))
        call judge_error(err, merge(tol%f64, tol%f32, wide), 'mlx_rope', merge('float64', 'float32', wide), seed)
    end subroutine test_rope

    ! attention with the default and a given scale, causal, and with a boolean and a real mask, one for every head
    ! and one per head
    subroutine test_attention( seed, wide )
        integer, intent(in) :: seed
        logical, intent(in) :: wide
        type(mlx_array)          :: q, k, v, r, m
        type(mlx_attention_spec) :: spec
        type(elem_tolerance)     :: tol
        real(real64)             :: qs(4, 3, NI, 2), ks(4, NK, NI, 2), vs(NV, NK, NI, 2), ref(NV, 3, NI, 2)
        real(real64)             :: add(NK, 3, NI), err, scale, off
        logical                  :: keep(NK, 3, NI)
        integer                  :: i, j
        write(*,'(a,i0,a,l1)') 'test_attention seed=', seed, ' wide=', wide
        tol = find_tolerance(FAST_TOLERANCES, 'mlx_attention')
        qs = reshape(seeded_uniform(size(qs), seed+60), shape(qs))
        ks = reshape(seeded_uniform(size(ks), seed+70), shape(ks))
        vs = reshape(seeded_uniform(size(vs), seed+80), shape(vs))
        q = seeded_array(qs, wide)
        k = seeded_array(ks, wide)
        v = seeded_array(vs, wide)
        scale = real(1._real32/sqrt(4._real32), real64)
        off = -real(huge(1._real32), real64)
        add = 0._real64
        err = 0._real64
        r = mlx_scaled_dot_product_attention(q, k, v)
        ref = attention_of(qs, ks, vs, scale, add)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        spec = mlx_attention_spec(scale=0.3_real32)
        r = mlx_scaled_dot_product_attention(q, k, v, spec)
        ref = attention_of(qs, ks, vs, real(0.3_real32, real64), add)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        spec = mlx_attention_spec(scale=-0.7_real32)
        r = mlx_scaled_dot_product_attention(q, k, v, spec)
        ref = attention_of(qs, ks, vs, real(-0.7_real32, real64), add)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        do i = 1, 3
            do j = 1, NK
                keep(j, i, :) = j <= i+NK-3
            end do
        end do
        spec = mlx_attention_spec(causal=.true.)
        r = mlx_scaled_dot_product_attention(q, k, v, spec)
        ref = attention_of(qs, ks, vs, scale, merge(0._real64, off, keep))
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        keep = .true.
        keep(1, 1, :) = .false.
        keep(3, 2, :) = .false.
        keep(4:5, 3, :) = .false.
        m = mlx_from(logical(keep(:, :, 1), c_bool))
        r = mlx_scaled_dot_product_attention(q, k, v, mask=m)
        ref = attention_of(qs, ks, vs, scale, merge(0._real64, off, keep))
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        keep(2, 1, 2) = .false.
        keep(5, 2, 3) = .false.
        keep(1:3, 3, 3) = .false.
        m = mlx_from(logical(keep, c_bool))
        r = mlx_scaled_dot_product_attention(q, k, v, mask=m)
        ref = attention_of(qs, ks, vs, scale, merge(0._real64, off, keep))
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        add = reshape(seeded_uniform(NK*3*NI, seed+90), [NK, 3, NI])
        m = seeded_array(add, wide)
        r = mlx_scaled_dot_product_attention(q, k, v, mask=m)
        ref = attention_of(qs, ks, vs, scale, add)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        call judge_error(err, merge(tol%f64, tol%f32, wide), 'mlx_scaled_dot_product_attention', merge('float64', 'float32', wide), seed)
    end subroutine test_attention

    ! MLX's fused attention kernel, demanded: it exists on the GPU for 64 features, and is refused elsewhere
    subroutine test_fused_attention( seed )
        integer, intent(in) :: seed
        type(mlx_array)          :: q, k, v, r, m
        type(mlx_attention_spec) :: spec
        type(elem_tolerance)     :: tol
        real(real64)             :: qs(NF, 3, 2, 1), ks(NF, NK, 2, 1), vs(NF, NK, 2, 1), ref(NF, 3, 2, 1), add(NK, 3, 2), err, off
        logical                  :: keep(NK, 3, 2)
        integer                  :: i, j
        write(*,'(a,i0)') 'test_fused_attention seed=', seed
        tol = find_tolerance(FAST_TOLERANCES, 'mlx_attention_fused')
        qs = reshape(seeded_uniform(size(qs), seed+160), shape(qs))
        ks = reshape(seeded_uniform(size(ks), seed+170), shape(ks))
        vs = reshape(seeded_uniform(size(vs), seed+180), shape(vs))
        q = seeded_array(qs, .false.)
        k = seeded_array(ks, .false.)
        v = seeded_array(vs, .false.)
        off = -real(huge(1._real32), real64)
        add = 0._real64
        err = 0._real64
        spec = mlx_attention_spec(force_fused=.true.)
        r = mlx_scaled_dot_product_attention(q, k, v, spec)
        ref = attention_of(qs, ks, vs, real(1._real32/sqrt(real(NF, real32)), real64), add)
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        do i = 1, 3
            do j = 1, NK
                keep(j, i, :) = j <= i+NK-3
            end do
        end do
        spec = mlx_attention_spec(causal=.true., force_fused=.true.)
        r = mlx_scaled_dot_product_attention(q, k, v, spec)
        ref = attention_of(qs, ks, vs, real(1._real32/sqrt(real(NF, real32)), real64), merge(0._real64, off, keep))
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        keep = .true.
        keep(1, 1, :) = .false.
        keep(3, 2, 1) = .false.
        keep(4:5, 3, 2) = .false.
        m = mlx_from(logical(keep, c_bool))
        spec = mlx_attention_spec(force_fused=.true.)
        r = mlx_scaled_dot_product_attention(q, k, v, spec, mask=m)
        ref = attention_of(qs, ks, vs, real(1._real32/sqrt(real(NF, real32)), real64), merge(0._real64, off, keep))
        err = nan_max(err, shaped_error(r, ref, abs(ref)))
        call judge_error(err, tol%f32, 'mlx_attention_fused', 'float32', seed)
    end subroutine test_fused_attention

    ! what is exact: the shapes and the kinds of the results
    subroutine test_shapes_and_kinds
        type(mlx_array) :: a, r, t
        real(real32)    :: x(4, 3, 2)
        integer(int32)  :: classes(3, 2)
        write(*,'(a)') 'test_shapes_and_kinds'
        x = 0.5_real32
        classes = 2_int32
        a = mlx_from(x)
        t = mlx_from(classes)
        r = mlx_layer_norm(a)
        call assert_true(all(r%shape() == [4, 3, 2]), 'a layer normalisation keeps the shape')
        r = mlx_rms_norm(a)
        call assert_true(all(r%shape() == [4, 3, 2]), 'an RMS normalisation keeps the shape')
        r = mlx_rope(a)
        call assert_true(all(r%shape() == [4, 3, 2]), 'a rotary embedding keeps the shape')
        r = mlx_cross_entropy(a, t)
        call assert_true(all(r%shape() == [3, 2]), 'a cross entropy loses dimension 1, the classes')
        call assert_true(r%kind() == MLX_DTYPES%float32, 'a cross entropy is float32')
    end subroutine test_shapes_and_kinds

    ! (x - mean)/sqrt(var + eps) w + b along dimension 1, the variance divided by the extent
    function layer_norm_of( x, w, b, eps ) result(y)
        real(real64), intent(in) :: x(:, :, :), w(:), b(:), eps
        real(real64) :: y(size(x, 1), size(x, 2), size(x, 3)), mean, var
        integer      :: j, k, n
        n = size(x, 1)
        do k = 1, size(x, 3)
            do j = 1, size(x, 2)
                mean = sum(x(:, j, k))/real(n, real64)
                var = sum((x(:, j, k)-mean)**2)/real(n, real64)
                y(:, j, k) = (x(:, j, k)-mean)/sqrt(var+eps)*w+b
            end do
        end do
    end function layer_norm_of

    ! x/sqrt(mean(x**2) + eps) w along dimension 1
    function rms_norm_of( x, w, eps ) result(y)
        real(real64), intent(in) :: x(:, :, :), w(:), eps
        real(real64) :: y(size(x, 1), size(x, 2), size(x, 3))
        integer      :: j, k
        do k = 1, size(x, 3)
            do j = 1, size(x, 2)
                y(:, j, k) = x(:, j, k)/sqrt(sum(x(:, j, k)**2)/real(size(x, 1), real64)+eps)*w
            end do
        end do
    end function rms_norm_of

    ! the rotary embedding of x (features, positions, batch): pair p of the first spec%features elements is
    ! rotated by the angle (t - 1 + offsets(b)) scale / frequency(p), frequency(p) = base**((p-1)/pairs) or the
    ! one given; the pairs are (p, p + pairs), or the neighbours (2p - 1, 2p) when traditional
    function rope_of( x, spec, offsets, freqs ) result(y)
        real(real64),        intent(in)           :: x(:, :, :)
        type(mlx_rope_spec), intent(in)           :: spec
        integer,             intent(in)           :: offsets(:)
        real(real64),        optional, intent(in) :: freqs(:)
        real(real64) :: y(size(x, 1), size(x, 2), size(x, 3)), theta, c, s, frequency
        integer      :: p, t, b, pairs, i1, i2
        y = x
        pairs = spec%features/2
        do b = 1, size(x, 3)
            do t = 1, size(x, 2)
                do p = 1, pairs
                    if( present(freqs) )then
                        frequency = freqs(p)
                    else
                        frequency = real(spec%base, real64)**(real(p-1, real64)/real(pairs, real64))
                    endif
                    theta = real(t-1+offsets(b), real64)*real(spec%scale, real64)/frequency
                    c = cos(theta)
                    s = sin(theta)
                    if( spec%traditional )then
                        i1 = 2*p-1
                        i2 = 2*p
                    else
                        i1 = p
                        i2 = p+pairs
                    endif
                    y(i1, t, b) = x(i1, t, b)*c-x(i2, t, b)*s
                    y(i2, t, b) = x(i1, t, b)*s+x(i2, t, b)*c
                end do
            end do
        end do
    end function rope_of

    ! r(:, i, h, b) = sum over j of softmax_j(scale dot(q(:, i, h, b), k(:, j, h, b)) + add(j, i, h)) v(:, j, h, b)
    function attention_of( q, k, v, scale, add ) result(r)
        real(real64), intent(in) :: q(:, :, :, :), k(:, :, :, :), v(:, :, :, :), scale, add(:, :, :)
        real(real64) :: r(size(v, 1), size(q, 2), size(q, 3), size(q, 4)), score(size(k, 2)), top
        integer      :: i, j, h, b
        do b = 1, size(q, 4)
            do h = 1, size(q, 3)
                do i = 1, size(q, 2)
                    do j = 1, size(k, 2)
                        score(j) = scale*dot_product(q(:, i, h, b), k(:, j, h, b))+add(j, i, h)
                    end do
                    top = maxval(score)
                    score = exp(score-top)
                    score = score/sum(score)
                    r(:, i, h, b) = matmul(v(:, :, h, b), score)
                end do
            end do
        end do
    end function attention_of

end module mlxf_fast_layers_tester
