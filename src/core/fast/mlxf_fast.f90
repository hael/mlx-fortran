!@descr: custom Metal kernels: a kernel's source and launch configuration behind a counted handle, applied to arrays on the GPU
! The source is the body of a Metal function. MLX writes the function's signature from the buffer names, the
! inputs' dtypes and the outputs' dtypes at each application, and compiles it when a result is evaluated. The
! source sees MLX's buffers, row-major and 0-based: it is the one place where a user writes MLX's layout.
module mlxf_fast
use, intrinsic :: iso_c_binding,   only: c_int, c_bool, c_size_t, c_intptr_t, c_null_ptr, c_null_char, c_associated
use, intrinsic :: iso_fortran_env, only: int64
use mlxf_c_types,  only: mlxc_fast_metal_kernel, mlxc_fast_metal_kernel_config, mlxc_vector_array, mlxc_vector_string, &
                         mlxc_stream
use mlxf_c_fast,   only: mlxc_fast_metal_kernel_new, mlxc_fast_metal_kernel_free, mlxc_fast_metal_kernel_apply, &
                         mlxc_fast_metal_kernel_config_new, mlxc_fast_metal_kernel_config_free, &
                         mlxc_fast_metal_kernel_config_add_output_arg, mlxc_fast_metal_kernel_config_set_grid, &
                         mlxc_fast_metal_kernel_config_set_thread_group, mlxc_fast_metal_kernel_config_set_init_value, &
                         mlxc_fast_metal_kernel_config_set_verbose, &
                         mlxc_fast_metal_kernel_config_add_template_arg_dtype, &
                         mlxc_fast_metal_kernel_config_add_template_arg_int, &
                         mlxc_fast_metal_kernel_config_add_template_arg_bool
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_c_vector, only: mlxc_vector_array_new, mlxc_vector_array_free, mlxc_vector_string_new, &
                         mlxc_vector_string_append_value, mlxc_vector_string_free
use mlxf_defs,     only: mlx_metal_kernel_spec, MLX_DTYPES
use mlxf_array,    only: mlx_array, mlx_is_live, mlxf_vector_import, mlxf_vector_export, mlxf_check_dtype
use mlxf_device,   only: mlxf_enter, mlxf_require_device, mlxf_default_stream
use mlxf_error,    only: mlxf_check, mlxf_fail, mlxf_report, mlxf_guard_thread
use mlxf_registry, only: registry_add, registry_retain, registry_release, registry_is_live
implicit none
public :: mlx_metal_kernel
private

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

contains

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
