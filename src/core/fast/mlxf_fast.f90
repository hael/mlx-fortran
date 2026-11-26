!@descr: MLX's fast module: fused layers along dimension 1, and custom Metal kernels behind a counted handle, applied on the GPU
! The fused layers (normalisations, rotary embeddings, attention, cross entropy) act along MLX's last axes:
! features along Fortran dimension 1, a sequence along dimension 2. The rest of this header is the kernels'.
! The source is the body of a Metal function. MLX writes the function's signature from the buffer names, the
! inputs' dtypes and the outputs' dtypes at each application, and compiles it when a result is evaluated. The
! source sees MLX's buffers, row-major and 0-based: it is the one place where a user writes MLX's layout.
module mlxf_fast
use, intrinsic :: iso_c_binding,   only: c_int, c_bool, c_size_t, c_intptr_t, c_null_ptr, c_null_char, c_associated
use, intrinsic :: iso_fortran_env, only: int64, real32
use mlxf_c_fast,       only: mlxc_fast_metal_kernel_new, mlxc_fast_metal_kernel_free, mlxc_fast_metal_kernel_apply, &
                             mlxc_fast_metal_kernel_config_new, mlxc_fast_metal_kernel_config_free, &
                             mlxc_fast_metal_kernel_config_add_output_arg, mlxc_fast_metal_kernel_config_set_grid, &
                             mlxc_fast_metal_kernel_config_set_thread_group, &
                             mlxc_fast_metal_kernel_config_set_init_value, mlxc_fast_metal_kernel_config_set_verbose, &
                             mlxc_fast_metal_kernel_config_add_template_arg_dtype, &
                             mlxc_fast_metal_kernel_config_add_template_arg_int, &
                             mlxc_fast_metal_kernel_config_add_template_arg_bool, mlxc_fast_layer_norm, &
                             mlxc_fast_rms_norm, mlxc_fast_rope, mlxc_fast_rope_dynamic, &
                             mlxc_fast_scaled_dot_product_attention, mlxc_fast_cross_entropy
use mlxf_c_signatures, only: mlxc_attention_op, mlxc_layer_norm_op, mlxc_rms_norm_op, mlxc_rope_dynamic_op, &
                             mlxc_rope_op
use mlxf_c_stream,     only: mlxc_stream_free
use mlxf_c_types,      only: mlxc_fast_metal_kernel, mlxc_fast_metal_kernel_config, mlxc_vector_array, &
                             mlxc_vector_string, mlxc_stream
use mlxf_c_vector,     only: mlxc_vector_array_new, mlxc_vector_array_free, mlxc_vector_string_new, &
                             mlxc_vector_string_append_value, mlxc_vector_string_free
use mlxf_defs,         only: mlx_metal_kernel_spec, MLX_DTYPES, mlx_rope_spec, mlx_attention_spec
use mlxf_array,        only: mlx_array, mlx_is_live, mlxf_vector_import, mlxf_vector_export
use mlxf_device,       only: mlxf_enter, mlxf_require_device, mlxf_default_stream
use mlxf_error,        only: mlxf_check, mlxf_fail, mlxf_report, mlxf_guard_thread
use mlxf_registry,     only: registry_add, registry_retain, registry_release, registry_is_live
use mlxf_calls,        only: mlxf_binary, mlxf_check_dtype, mlxf_zero_based
implicit none
public :: mlx_metal_kernel, mlx_layer_norm, mlx_rms_norm, mlx_rope, mlx_scaled_dot_product_attention, mlx_cross_entropy
private

! the eps of the normalisations when none is given
real(real32), parameter :: NORM_EPS = 1.e-5_real32

type :: mlx_metal_kernel
    private
    type(mlxc_fast_metal_kernel)        :: h
    type(mlxc_fast_metal_kernel_config) :: config
    integer(int64)                      :: serial = 0_int64
  contains
    procedure          :: new => metal_kernel_new
    procedure          :: kill => metal_kernel_kill
    procedure          :: apply => metal_kernel_apply
    procedure, private :: metal_kernel_assign
    generic            :: assignment(=) => metal_kernel_assign
    final              :: metal_kernel_final
end type mlx_metal_kernel

interface mlx_metal_kernel
    module procedure metal_kernel_from_spec
end interface mlx_metal_kernel

! the signature helpers of the fast procedures, implemented in mlxf_fast_calls
interface
    ! int f(mlx_array* res, const mlx_array x, const mlx_array weight, const mlx_array bias, float eps,
    ! const mlx_stream s)
    module subroutine mlxf_layer_norm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_layer_norm_op)   :: f
        type(mlx_array),  intent(in)    :: a(3)
        real(real32),     intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_layer_norm_op

    ! int f(mlx_array* res, const mlx_array x, const mlx_array weight, float eps, const mlx_stream s)
    module subroutine mlxf_rms_norm_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_rms_norm_op)     :: f
        type(mlx_array),  intent(in)    :: a(2)
        real(real32),     intent(in)    :: option
        character(len=*), intent(in)    :: proc
    end subroutine mlxf_rms_norm_op

    ! int f(mlx_array* res, const mlx_array x, int dims, bool traditional, mlx_optional_float base, float scale,
    ! int offset, const mlx_array freqs, const mlx_stream s)
    module subroutine mlxf_rope_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_rope_op)            :: f
        type(mlx_array),     intent(in)    :: a(2)
        type(mlx_rope_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_rope_op

    ! int f(mlx_array* res, const mlx_array x, int dims, bool traditional, mlx_optional_float base, float scale,
    ! const mlx_array offset, const mlx_array freqs, const mlx_stream s)
    module subroutine mlxf_rope_dynamic_op( r, f, a, option, proc )
        type(mlx_array),     intent(inout) :: r
        procedure(mlxc_rope_dynamic_op)    :: f
        type(mlx_array),     intent(in)    :: a(3)
        type(mlx_rope_spec), intent(in)    :: option
        character(len=*),    intent(in)    :: proc
    end subroutine mlxf_rope_dynamic_op

    ! int f(mlx_array* res, const mlx_array queries, const mlx_array keys, const mlx_array values, float scale,
    ! const char* mask_mode, const mlx_array mask_arr, const mlx_array sinks, bool force_fused, const mlx_stream s)
    module subroutine mlxf_attention_op( r, f, a, option, proc )
        type(mlx_array),          intent(inout) :: r
        procedure(mlxc_attention_op)            :: f
        type(mlx_array),          intent(in)    :: a(4)
        type(mlx_attention_spec), intent(in)    :: option
        character(len=*),         intent(in)    :: proc
    end subroutine mlxf_attention_op
end interface

contains

    ! x normalised along dimension 1: (x - mean)/sqrt(variance + eps), the mean and the variance (divided by the
    ! extent) taken over dimension 1, then times weight and plus bias, rank-1 arrays of that extent, when given
    function mlx_layer_norm( x, weight, bias, eps ) result(r)
        type(mlx_array), intent(in)           :: x
        type(mlx_array), optional, intent(in) :: weight, bias
        real(real32),    optional, intent(in) :: eps
        type(mlx_array) :: r, a(3)
        real(real32)    :: e
        call mlxf_require_device('mlx_layer_norm')
        e = NORM_EPS
        if( present(eps) ) e = eps
        a(1) = x
        call take_optional(a(2), 'mlx_layer_norm', weight)
        call take_optional(a(3), 'mlx_layer_norm', bias)
        call mlxf_layer_norm_op(r, mlxc_fast_layer_norm, a, e, 'mlx_layer_norm')
    end function mlx_layer_norm

    ! x divided by its root mean square along dimension 1, sqrt(mean(x**2) + eps), then times weight, a rank-1
    ! array of that extent, when given
    function mlx_rms_norm( x, weight, eps ) result(r)
        type(mlx_array), intent(in)           :: x
        type(mlx_array), optional, intent(in) :: weight
        real(real32),    optional, intent(in) :: eps
        type(mlx_array) :: r, a(2)
        real(real32)    :: e
        call mlxf_require_device('mlx_rms_norm')
        e = NORM_EPS
        if( present(eps) ) e = eps
        a(1) = x
        call take_optional(a(2), 'mlx_rms_norm', weight)
        call mlxf_rms_norm_op(r, mlxc_fast_rms_norm, a, e, 'mlx_rms_norm')
    end function mlx_rms_norm

    ! the rotary position embedding of x (features, positions, ...): a pair (x1, x2) of elements along dimension 1
    ! becomes (x1 cos - x2 sin, x1 sin + x2 cos) of the angle (position - 1 + offset) scale / divisor(pair), the
    ! position counted along dimension 2. offset, an integer array (rank 0, or rank 1 with one value per element
    ! of the last dimension), replaces spec%offset; freqs, one divisor per pair, replaces those of the base
    function mlx_rope( x, spec, offset, freqs ) result(r)
        type(mlx_array),     intent(in)           :: x
        type(mlx_rope_spec), optional, intent(in) :: spec
        type(mlx_array),     optional, intent(in) :: offset, freqs
        type(mlx_array)      :: r, a(3)
        type(mlx_rope_spec)  :: options
        integer, allocatable :: shape(:)
        call mlxf_require_device('mlx_rope')
        if( present(spec) ) options = spec
        shape = x%shape()
        if( size(shape) < 3 ) call mlxf_fail('mlx_rope', 'the array needs features, positions and at least one more dimension')
        if( options%features == 0 ) options%features = shape(1)
        a(1) = x
        if( present(offset) )then
            call check_offsets(offset, shape(size(shape)))
            a(2) = offset
            call take_optional(a(3), 'mlx_rope', freqs)
            call mlxf_rope_dynamic_op(r, mlxc_fast_rope_dynamic, a, options, 'mlx_rope')
        else
            call take_optional(a(2), 'mlx_rope', freqs)
            call mlxf_rope_op(r, mlxc_fast_rope, a(1:2), options, 'mlx_rope')
        endif
    end function mlx_rope

    ! attention: for queries (d, lq, heads, batch), keys (d, lk, heads, batch) and values (dv, lk, heads, batch),
    ! r(:, i, h, b) is the sum over the keys j of softmax_j(scale * dot(q(:, i), k(:, j))) * v(:, j). A boolean
    ! mask(j, i, ...) keeps key j for query i, a real one is added to the scores; it broadcasts to (lk, lq, heads,
    ! batch)
    function mlx_scaled_dot_product_attention( queries, keys, values, spec, mask ) result(r)
        type(mlx_array),          intent(in)           :: queries, keys, values
        type(mlx_attention_spec), optional, intent(in) :: spec
        type(mlx_array),          optional, intent(in) :: mask
        type(mlx_array)          :: r, a(4)
        type(mlx_attention_spec) :: options
        integer, allocatable     :: shape(:)
        call mlxf_require_device('mlx_scaled_dot_product_attention')
        if( present(spec) )then
            options%causal = spec%causal
            options%force_fused = spec%force_fused
            if( allocated(spec%scale) ) options%scale = spec%scale
        endif
        if( options%causal .and. present(mask) ) &
            &call mlxf_fail('mlx_scaled_dot_product_attention', 'a causal attention takes no mask')
        shape = queries%shape()
        if( size(shape) /= 4 ) call mlxf_fail('mlx_scaled_dot_product_attention', 'queries, keys and values are rank 4')
        if( .not. allocated(options%scale) ) options%scale = 1._real32/sqrt(real(shape(1), real32))
        a(1) = queries
        a(2) = keys
        a(3) = values
        call take_optional(a(4), 'mlx_scaled_dot_product_attention', mask)
        call mlxf_attention_op(r, mlxc_fast_scaled_dot_product_attention, a, options, 'mlx_scaled_dot_product_attention')
    end function mlx_scaled_dot_product_attention

    ! the cross entropy of logits (classes, ...) against targets (...), one-based integer classes: for each
    ! distribution along dimension 1, log(sum(exp(logits))) - logits(target), float32
    function mlx_cross_entropy( logits, targets ) result(r)
        type(mlx_array), intent(in) :: logits, targets
        type(mlx_array) :: r, classes
        call mlxf_require_device('mlx_cross_entropy')
        call mlxf_zero_based(classes, targets, 'mlx_cross_entropy')
        call mlxf_binary(r, mlxc_fast_cross_entropy, logits, classes, 'mlx_cross_entropy')
    end function mlx_cross_entropy

    ! an array of offsets is rank 0, or rank 1 with one value per batch: MLX's GPU kernel reads one value per batch
    ! from any rank-1 array, also from one that holds a single value
    subroutine check_offsets( offset, nbatch )
        type(mlx_array), intent(in) :: offset
        integer,         intent(in) :: nbatch
        integer, allocatable :: shape(:)
        shape = offset%shape()
        if( size(shape) == 0 ) return
        if( size(shape) > 1 ) call mlxf_fail('mlx_rope', 'offset has rank 0 or 1')
        if( shape(1) /= nbatch ) call mlxf_fail('mlx_rope', 'a rank-1 offset has one value per element of the last dimension')
    end subroutine check_offsets

    ! an optional array as an operand: a counted copy, or k left empty, which the helpers pass to MLX as absent;
    ! one that is given must be live
    subroutine take_optional( k, proc, a )
        type(mlx_array),  intent(inout)        :: k
        character(len=*), intent(in)           :: proc
        type(mlx_array),  optional, intent(in) :: a
        if( .not. present(a) ) return
        if( .not. mlx_is_live(a) ) call mlxf_fail(proc, 'an optional array that is given is empty or stale')
        k = a
    end subroutine take_optional

    ! the kernel a spec describes
    function metal_kernel_from_spec( spec ) result(k)
        type(mlx_metal_kernel_spec), intent(in) :: spec
        type(mlx_metal_kernel) :: k
        call mlxf_enter('mlx_metal_kernel')
        call k%new(spec)
    end function metal_kernel_from_spec

    ! builds the kernel and its launch configuration from spec, which is validated here once; an invalid spec
    ! stops. Nothing is compiled yet and no device is needed: MLX compiles the source at the first evaluation
    subroutine metal_kernel_new( self, spec )
        class(mlx_metal_kernel),     intent(inout) :: self
        type(mlx_metal_kernel_spec), intent(in)    :: spec
        character(len=*), parameter   :: PROC = 'mlx_metal_kernel new'
        integer,          allocatable :: ranks(:), dtypes(:)
        call mlxf_enter(PROC)
        call self%kill()
        call check_spec(spec, ranks, dtypes, PROC)
        self%config = config_of(spec, ranks, dtypes, PROC)
        self%h = kernel_of(spec, PROC)
        if( .not. c_associated(self%h%ctx) )then
            call mlxc_fast_metal_kernel_config_free(self%config)
            call mlxf_check(1_c_int, PROC)
        endif
        self%serial = registry_add(kernel_key(self%h))
    end subroutine metal_kernel_new

    ! the kernel's outputs for inputs, one array per input name in the spec's order, as nodes of the graph on the
    ! default device, which must be the GPU. With status a refusal returns it, outputs unallocated and MLX usable
    subroutine metal_kernel_apply( self, inputs, outputs, status )
        class(mlx_metal_kernel), intent(in)               :: self
        type(mlx_array),         intent(in)               :: inputs(:)
        type(mlx_array),         allocatable, intent(out) :: outputs(:)
        integer,                 optional, intent(out)    :: status
        character(len=*), parameter :: PROC = 'mlx_metal_kernel apply'
        type(mlxc_vector_array)     :: vin, vout
        type(mlxc_stream)           :: s
        integer                     :: st, cleanup, i
        call mlxf_require_device(PROC)
        call require_kernel(self, PROC)
        vin = mlxc_vector_array_new()
        vout = mlxc_vector_array_new()
        st = 0
        do i = 1, size(inputs)
            if( .not. mlx_is_live(inputs(i)) ) call mlxf_report(PROC, 'an input array is empty or stale', status=st)
        end do
        if( st == 0 ) call mlxf_vector_export(vin, inputs, st)
        if( st == 0 )then
            s = mlxf_default_stream(PROC)
            call mlxf_check(mlxc_fast_metal_kernel_apply(vout, self%h, vin, self%config, s), PROC, status=st)
            call mlxf_check(mlxc_stream_free(s), PROC, status=cleanup)
            if( st == 0 ) st = cleanup
        endif
        if( st == 0 ) call mlxf_vector_import(outputs, vout, st)
        call mlxf_check(mlxc_vector_array_free(vin), PROC, status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(vout), PROC, status=cleanup)
        if( st == 0 ) st = cleanup
        if( st /= 0 )then
            if( allocated(outputs) ) deallocate(outputs)
        endif
        call mlxf_check(int(st, c_int), PROC, status=status)
    end subroutine metal_kernel_apply

    ! a counted copy of the kernel; the thread guard runs only when a live handle is involved, so empty
    ! kernels may be copied anywhere
    impure elemental subroutine metal_kernel_assign( lhs, rhs )
        class(mlx_metal_kernel), intent(inout) :: lhs
        class(mlx_metal_kernel), intent(in)    :: rhs
        if( c_associated(lhs%h%ctx).or.c_associated(rhs%h%ctx) ) call mlxf_guard_thread('mlx_metal_kernel assignment')
        if( c_associated(lhs%h%ctx, rhs%h%ctx).and.lhs%serial == rhs%serial ) return
        if( c_associated(rhs%h%ctx) )then
            if( .not. registry_retain(kernel_key(rhs%h), rhs%serial) ) &
                &call mlxf_fail('mlx_metal_kernel assignment', 'stale kernel copy')
        endif
        call metal_kernel_release(lhs)
        lhs%h = rhs%h
        lhs%config = rhs%config
        lhs%serial = rhs%serial
    end subroutine metal_kernel_assign

    ! releases the handle; idempotent, and without the thread guard for an empty kernel
    impure elemental subroutine metal_kernel_kill( self )
        class(mlx_metal_kernel), intent(inout) :: self
        if( c_associated(self%h%ctx) ) call mlxf_guard_thread('mlx_metal_kernel kill')
        call metal_kernel_release(self)
    end subroutine metal_kernel_kill

    ! finalization releases as kill does
    impure elemental subroutine metal_kernel_final( self )
        type(mlx_metal_kernel), intent(inout) :: self
        call self%kill()
    end subroutine metal_kernel_final

    ! drops one count, the last freeing the mlx-c kernel and its configuration; the kernel is empty afterwards
    impure elemental subroutine metal_kernel_release( self )
        class(mlx_metal_kernel), intent(inout) :: self
        if( .not. c_associated(self%h%ctx) ) return
        if( registry_release(kernel_key(self%h), self%serial) )then
            call mlxc_fast_metal_kernel_config_free(self%config)
            call mlxc_fast_metal_kernel_free(self%h)
        endif
        self%h%ctx = c_null_ptr
        self%config%ctx = c_null_ptr
        self%serial = 0_int64
    end subroutine metal_kernel_release

    ! stops unless k holds a live kernel (empty and stale copies are refused)
    subroutine require_kernel( k, proc )
        class(mlx_metal_kernel), intent(in) :: k
        character(len=*),        intent(in) :: proc
        if( .not. c_associated(k%h%ctx) ) call mlxf_fail(proc, 'empty mlx_metal_kernel')
        if( .not. registry_is_live(kernel_key(k%h), k%serial) ) call mlxf_fail(proc, 'stale mlx_metal_kernel')
    end subroutine require_kernel

    ! the registry's key of a kernel: its context address
    integer(int64) function kernel_key( h ) result(key)
        type(mlxc_fast_metal_kernel), intent(in) :: h
        key = int(transfer(h%ctx, 0_c_intptr_t), int64)
    end function kernel_key

    ! stops unless spec describes a kernel: a name, a source, at least one output, a shape and a dtype of
    ! MLX_DTYPES per output, a positive grid and threadgroup, and a value per template name. Returns each
    ! output's rank and dtype
    subroutine check_spec( spec, ranks, dtypes, proc )
        type(mlx_metal_kernel_spec), intent(in)               :: spec
        integer,                     allocatable, intent(out) :: ranks(:), dtypes(:)
        character(len=*),            intent(in)               :: proc
        integer :: nout, i
        if( .not. allocated(spec%name) ) call mlxf_fail(proc, 'the spec has no name')
        if( len_trim(spec%name) == 0 ) call mlxf_fail(proc, 'the spec has a blank name')
        if( .not. allocated(spec%source) ) call mlxf_fail(proc, 'the spec has no source')
        if( .not. allocated(spec%output_names) ) call mlxf_fail(proc, 'the spec names no output')
        nout = size(spec%output_names)
        if( nout == 0 ) call mlxf_fail(proc, 'the spec names no output')
        if( .not. allocated(spec%output_shapes) ) call mlxf_fail(proc, 'the spec gives no output shape')
        if( any(spec%output_shapes < 0) ) call mlxf_fail(proc, 'a negative output extent')
        if( allocated(spec%output_ranks) )then
            if( size(spec%output_ranks) /= nout ) call mlxf_fail(proc, 'output_ranks needs one rank per output')
            if( any(spec%output_ranks < 0) ) call mlxf_fail(proc, 'a negative output rank')
            if( sum(spec%output_ranks) /= size(spec%output_shapes) ) &
                &call mlxf_fail(proc, 'output_shapes does not hold the extents output_ranks counts')
            ranks = spec%output_ranks
        else
            if( modulo(size(spec%output_shapes), nout) /= 0 ) &
                &call mlxf_fail(proc, 'output_shapes does not divide among the outputs; give output_ranks')
            allocate(ranks(nout), source=size(spec%output_shapes)/nout)
        endif
        if( allocated(spec%output_dtypes) )then
            if( size(spec%output_dtypes) /= nout ) call mlxf_fail(proc, 'output_dtypes needs one dtype per output')
            dtypes = spec%output_dtypes
        else
            allocate(dtypes(nout), source=MLX_DTYPES%float32)
        endif
        do i = 1, nout
            call mlxf_check_dtype(dtypes(i), proc)
        end do
        if( any(spec%grid < 1) .or. any(spec%threadgroup < 1) ) &
            &call mlxf_fail(proc, 'the grid and the threadgroup need three positive sizes')
        if( allocated(spec%template_dtype_names) .neqv. allocated(spec%template_dtypes) ) &
            &call mlxf_fail(proc, 'template_dtype_names and template_dtypes go together')
        if( allocated(spec%template_int_names) .neqv. allocated(spec%template_ints) ) &
            &call mlxf_fail(proc, 'template_int_names and template_ints go together')
        if( allocated(spec%template_bool_names) .neqv. allocated(spec%template_bools) ) &
            &call mlxf_fail(proc, 'template_bool_names and template_bools go together')
        if( allocated(spec%template_dtypes) )then
            if( size(spec%template_dtype_names) /= size(spec%template_dtypes) ) &
                &call mlxf_fail(proc, 'template_dtypes needs one dtype per name')
            do i = 1, size(spec%template_dtypes)
                call mlxf_check_dtype(spec%template_dtypes(i), proc)
            end do
        endif
        if( allocated(spec%template_ints) )then
            if( size(spec%template_int_names) /= size(spec%template_ints) ) &
                &call mlxf_fail(proc, 'template_ints needs one value per name')
        endif
        if( allocated(spec%template_bools) )then
            if( size(spec%template_bool_names) /= size(spec%template_bools) ) &
                &call mlxf_fail(proc, 'template_bools needs one value per name')
        endif
    end subroutine check_spec

    ! the mlx-c kernel of a checked spec; its context is null when MLX refuses it
    function kernel_of( spec, proc ) result(h)
        type(mlx_metal_kernel_spec), intent(in) :: spec
        character(len=*),            intent(in) :: proc
        type(mlxc_fast_metal_kernel)  :: h
        type(mlxc_vector_string)      :: vin, vout
        character(len=:), allocatable :: header
        vin = mlxc_vector_string_new()
        if( allocated(spec%input_names) ) call append_names(vin, spec%input_names, proc)
        vout = mlxc_vector_string_new()
        call append_names(vout, spec%output_names, proc)
        header = ''
        if( allocated(spec%header) ) header = spec%header
        h = mlxc_fast_metal_kernel_new(trim(spec%name)//c_null_char, vin, vout, spec%source//c_null_char, &
            &header//c_null_char, logical(spec%ensure_row_contiguous, c_bool), logical(spec%atomic_outputs, c_bool))
        call mlxf_check(mlxc_vector_string_free(vin), proc)
        call mlxf_check(mlxc_vector_string_free(vout), proc)
    end function kernel_of

    ! appends the names, trimmed, to an mlx-c vector of strings; a blank name stops
    subroutine append_names( v, names, proc )
        type(mlxc_vector_string), intent(in) :: v
        character(len=*),         intent(in) :: names(:), proc
        integer :: i
        do i = 1, size(names)
            if( len_trim(names(i)) == 0 ) call mlxf_fail(proc, 'a blank buffer name')
            call mlxf_check(mlxc_vector_string_append_value(v, trim(names(i))//c_null_char), proc)
        end do
    end subroutine append_names

    ! the mlx-c launch configuration of a checked spec: each output's shape reversed to MLX's order with its
    ! dtype, the grid and the threadgroup as given, the initial value, and the template parameters
    function config_of( spec, ranks, dtypes, proc ) result(cfg)
        type(mlx_metal_kernel_spec), intent(in) :: spec
        integer,                     intent(in) :: ranks(:), dtypes(:)
        character(len=*),            intent(in) :: proc
        type(mlxc_fast_metal_kernel_config) :: cfg
        integer                             :: i, first, last
        cfg = mlxc_fast_metal_kernel_config_new()
        if( .not. c_associated(cfg%ctx) ) call mlxf_check(1_c_int, proc)
        first = 1
        do i = 1, size(ranks)
            last = first+ranks(i)-1
            call mlxf_check(mlxc_fast_metal_kernel_config_add_output_arg(cfg, int(spec%output_shapes(last:first:-1), c_int), &
                &int(ranks(i), c_size_t), int(dtypes(i), c_int)), proc)
            first = last+1
        end do
        call mlxf_check(mlxc_fast_metal_kernel_config_set_grid(cfg, int(spec%grid(1), c_int), int(spec%grid(2), c_int), &
            &int(spec%grid(3), c_int)), proc)
        call mlxf_check(mlxc_fast_metal_kernel_config_set_thread_group(cfg, int(spec%threadgroup(1), c_int), &
            &int(spec%threadgroup(2), c_int), int(spec%threadgroup(3), c_int)), proc)
        if( allocated(spec%init_value) ) &
            &call mlxf_check(mlxc_fast_metal_kernel_config_set_init_value(cfg, spec%init_value), proc)
        call mlxf_check(mlxc_fast_metal_kernel_config_set_verbose(cfg, logical(spec%verbose, c_bool)), proc)
        if( allocated(spec%template_dtypes) )then
            do i = 1, size(spec%template_dtypes)
                if( len_trim(spec%template_dtype_names(i)) == 0 ) call mlxf_fail(proc, 'a blank template name')
                call mlxf_check(mlxc_fast_metal_kernel_config_add_template_arg_dtype(cfg, &
                    &trim(spec%template_dtype_names(i))//c_null_char, int(spec%template_dtypes(i), c_int)), proc)
            end do
        endif
        if( allocated(spec%template_ints) )then
            do i = 1, size(spec%template_ints)
                if( len_trim(spec%template_int_names(i)) == 0 ) call mlxf_fail(proc, 'a blank template name')
                call mlxf_check(mlxc_fast_metal_kernel_config_add_template_arg_int(cfg, &
                    &trim(spec%template_int_names(i))//c_null_char, int(spec%template_ints(i), c_int)), proc)
            end do
        endif
        if( allocated(spec%template_bools) )then
            do i = 1, size(spec%template_bools)
                if( len_trim(spec%template_bool_names(i)) == 0 ) call mlxf_fail(proc, 'a blank template name')
                call mlxf_check(mlxc_fast_metal_kernel_config_add_template_arg_bool(cfg, &
                    &trim(spec%template_bool_names(i))//c_null_char, logical(spec%template_bools(i), c_bool)), proc)
            end do
        endif
    end function config_of

end module mlxf_fast
