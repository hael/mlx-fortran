!@descr: signature-class helpers of the fused layers: normalisations with optional weights, rotary embeddings, attention
! An operand mlx-c may be given as null is an empty handle here (optional_handle). The layers act along MLX's
! last axes, which are Fortran's first dimensions, so nothing is translated but the options' types.
submodule(mlxf_array) mlxf_array_fast
use, intrinsic :: iso_c_binding, only: c_null_char, c_null_ptr, c_associated
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_device,   only: mlxf_require_device, mlxf_default_stream
use mlxf_error,    only: mlxf_check
implicit none

contains

    ! r = f(a(1), a(2), a(3), option): an array, an optional weight and an optional bias, for every int
    ! f(mlx_array* res, const mlx_array x, const mlx_array weight, const mlx_array bias, float eps, const mlx_stream s)
    module subroutine mlxf_layer_norm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_layer_norm_op)   :: f
        type(mlx_array),  intent(in)    :: a(3)
        real(real32),     intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, hx, hw, hb
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        hx = mlxf_handle(a(1), proc)
        hw = optional_handle(a(2), proc)
        hb = optional_handle(a(3), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, hx, hw, hb, real(option, c_float_kind), s)
        call layer_done(r, res, s, ierr, proc)
    end subroutine mlxf_layer_norm_op

    ! r = f(a(1), a(2), option): an array and an optional weight, for every int f(mlx_array* res,
    ! const mlx_array x, const mlx_array weight, float eps, const mlx_stream s)
    module subroutine mlxf_rms_norm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_rms_norm_op)     :: f
        type(mlx_array),  intent(in)    :: a(2)
        real(real32),     intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, hx, hw
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        hx = mlxf_handle(a(1), proc)
        hw = optional_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, hx, hw, real(option, c_float_kind), s)
        call layer_done(r, res, s, ierr, proc)
    end subroutine mlxf_rms_norm_op

    ! r = f(a(1), option) with the optional frequencies a(2) and an integer offset, for every int f(mlx_array* res,
    ! const mlx_array x, int dims, bool traditional, mlx_optional_float base, float scale, int offset,
    ! const mlx_array freqs, const mlx_stream s); the base is passed only without frequencies, as MLX wants
    module subroutine mlxf_rope_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_rope_op)            :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_rope_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)          :: res, hx, hf
        type(mlxc_optional_float) :: base
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        call mlxf_require_device(proc)
        hx = mlxf_handle(a(1), proc)
        hf = optional_handle(a(2), proc)
        base = rope_base(option, hf)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, hx, int(option%features, c_int), logical(option%traditional, c_bool), base, &
            &real(option%scale, c_float_kind), int(option%offset, c_int), hf, s)
        call layer_done(r, res, s, ierr, proc)
    end subroutine mlxf_rope_op

    ! the same with an array of offsets a(2) and the optional frequencies a(3), for every int f(mlx_array* res,
    ! const mlx_array x, int dims, bool traditional, mlx_optional_float base, float scale, const mlx_array offset,
    ! const mlx_array freqs, const mlx_stream s)
    module subroutine mlxf_rope_dynamic_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_rope_dynamic_op)    :: f
        type(mlx_array),     intent(in)    :: a(3)
        type(mlx_rope_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
        type(mlxc_array)          :: res, hx, ho, hf
        type(mlxc_optional_float) :: base
        type(mlxc_stream)         :: s
        integer(c_int)            :: ierr
        call mlxf_require_device(proc)
        hx = mlxf_handle(a(1), proc)
        ho = mlxf_handle(a(2), proc)
        hf = optional_handle(a(3), proc)
        base = rope_base(option, hf)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, hx, int(option%features, c_int), logical(option%traditional, c_bool), base, &
            &real(option%scale, c_float_kind), ho, hf, s)
        call layer_done(r, res, s, ierr, proc)
    end subroutine mlxf_rope_dynamic_op

    ! r = f(a(1), a(2), a(3), option) with the optional mask a(4), for every int f(mlx_array* res,
    ! const mlx_array queries, const mlx_array keys, const mlx_array values, float scale, const char* mask_mode,
    ! const mlx_array mask_arr, const mlx_array sinks, bool force_fused, const mlx_stream s). The mask mode is
    ! 'causal' when the option asks for it, 'array' with a mask, and none otherwise; no sinks are passed, and a
    ! scale that is not set is 1
    module subroutine mlxf_attention_op( r, f, a, option, proc )
        type(mlx_array),          intent(inout) :: r
        procedure(mlxc_attention_op)            :: f
        type(mlx_array),          intent(in)    :: a(4)
        type(mlx_attention_spec), intent(in)    :: option
        character(len=*),         intent(in)    :: proc
        type(mlxc_array)              :: res, hq, hk, hv, hm, none
        type(mlxc_stream)             :: s
        character(len=:), allocatable :: mode
        real(c_float_kind)            :: scale
        integer(c_int)                :: ierr
        call mlxf_require_device(proc)
        hq = mlxf_handle(a(1), proc)
        hk = mlxf_handle(a(2), proc)
        hv = mlxf_handle(a(3), proc)
        hm = optional_handle(a(4), proc)
        none%ctx = c_null_ptr
        mode = ''
        if( c_associated(hm%ctx) ) mode = 'array'
        if( option%causal ) mode = 'causal'
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        scale = 1._c_float_kind
        if( allocated(option%scale) ) scale = real(option%scale, c_float_kind)
        ierr = f(res, hq, hk, hv, scale, mode//c_null_char, hm, none, &
            &logical(option%force_fused, c_bool), s)
        call layer_done(r, res, s, ierr, proc)
    end subroutine mlxf_attention_op

    ! the base of the rotation's frequencies as mlx-c takes it: absent when frequencies are given
    function rope_base( option, freqs ) result(base)
        type(mlx_rope_spec), intent(in) :: option
        type(mlxc_array),    intent(in) :: freqs
        type(mlxc_optional_float) :: base
        base%value = real(option%base, c_float_kind)
        base%has_value = .not. c_associated(freqs%ctx)
    end function rope_base

    ! after the C call: frees the stream, stops on MLX's error (freeing the result first) and registers the result
    subroutine layer_done( r, res, s, ierr, proc )
        type(mlx_array),   intent(inout) :: r
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_stream), intent(in)    :: s
        integer(c_int),    intent(in)    :: ierr
        character(len=*),  intent(in)    :: proc
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine layer_done

end submodule mlxf_array_fast
