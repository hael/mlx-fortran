!@descr: signature-class helpers of the samplers: a Fortran shape, operands, an optional key, the default or the CPU stream
! A sampler's last array is its key. An empty handle there is no key: mlx-c then receives a null array and MLX
! draws from its global key. Shapes arrive in Fortran order and are reversed; a dimension is translated to
! MLX's axis here.
submodule(mlxf_array) mlxf_array_random
use, intrinsic :: iso_c_binding, only: c_associated, c_null_ptr
use mlxf_c_array,  only: mlxc_array_new, mlxc_array_free
use mlxf_c_stream, only: mlxc_stream_free
use mlxf_device,   only: mlxf_require_device, mlxf_default_stream
use mlxf_error,    only: mlxf_check
implicit none

contains

    ! the handle of an operand mlx-c may be given as null: null for an empty array, validated otherwise
    module function optional_handle( a, proc ) result(h)
        type(mlx_array),  intent(in) :: a
        character(len=*), intent(in) :: proc
        type(mlxc_array) :: h
        h%ctx = c_null_ptr
        if( c_associated(a%h%ctx) ) h = mlxf_handle(a, proc)
    end function optional_handle

    ! the two results of f(a), in MLX's order, on the default device, for every int f(mlx_array* res_0,
    ! mlx_array* res_1, const mlx_array a, const mlx_stream s)
    module subroutine mlxf_pair_op( r, f, a, proc )
        type(mlx_array),  intent(inout) :: r(2)
        procedure(mlxc_pair_op)         :: f
        type(mlx_array),  intent(in)    :: a
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: ha
        type(mlxc_array)  :: res(2)
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a, proc)
        res(1) = mlxc_array_new()
        res(2) = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res(1), res(2), ha, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 )then
            call mlxf_check(mlxc_array_free(res(1)), proc)
            call mlxf_check(mlxc_array_free(res(2)), proc)
        endif
        call mlxf_check(ierr, proc)
        call adopt(r(1), res(1), proc)
        call adopt(r(2), res(2), proc)
    end subroutine mlxf_pair_op

    ! r = f(seed) for every int f(mlx_array* res, uint64_t seed); the seed's 64 bits go to MLX as they are
    module subroutine mlxf_random_key_op( r, f, seed, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_random_key_op)   :: f
        integer(int64),   intent(in)    :: seed
        character(len=*), intent(in)    :: proc
        type(mlxc_array) :: res
        integer(c_int)   :: ierr
        call mlxf_require_device(proc)
        res = mlxc_array_new()
        ierr = f(res, int(seed, c_int64_t))
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine mlxf_random_key_op

    ! r = f(shape, option%number) with the key a(1), for every int f(mlx_array* res, const int* shape,
    ! size_t shape_num, int number, const mlx_array key, const mlx_stream s): the number is a width or a dtype
    module subroutine mlxf_random_shape_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_shape_op)       :: f
        type(mlx_array),        intent(in)    :: a(1)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: res, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        hk = optional_handle(a(1), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlx_shape(option), int(size(option%shape), c_size_t), int(option%number, c_int), hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_shape_op

    ! r = f(shape, dtype, loc, scale) with the key a(1), for every int f(mlx_array* res, const int* shape,
    ! size_t shape_num, mlx_dtype dtype, float loc, float scale, const mlx_array key, const mlx_stream s)
    module subroutine mlxf_random_float_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_float_op)       :: f
        type(mlx_array),        intent(in)    :: a(1)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: res, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call mlxf_check_dtype(option%dtype, proc)
        hk = optional_handle(a(1), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlx_shape(option), int(size(option%shape), c_size_t), int(option%dtype, c_int), option%loc, &
            &option%scale, hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_float_op

    ! r = f(option) with the key a(1), for every int f(mlx_array* res, int x, const mlx_array key, const mlx_stream s)
    module subroutine mlxf_random_int_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_random_int_op)   :: f
        type(mlx_array),  intent(in)    :: a(1)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        hk = optional_handle(a(1), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, int(option, c_int), hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_int_op

    ! r = f(a(1), shape) with the key a(2), for every int f(mlx_array* res, const mlx_array p, const int* shape,
    ! size_t shape_num, const mlx_array key, const mlx_stream s)
    module subroutine mlxf_random_array_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_array_op)       :: f
        type(mlx_array),        intent(in)    :: a(2)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: res, ha, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a(1), proc)
        hk = optional_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, mlx_shape(option), int(size(option%shape), c_size_t), hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_array_op

    ! r = f(a(1)) along Fortran dimension option with the key a(2), for every int f(mlx_array* res,
    ! const mlx_array x, int axis, const mlx_array key, const mlx_stream s)
    module subroutine mlxf_random_axis_op( r, f, a, option, proc )
        type(mlx_array),  intent(inout) :: r
        procedure(mlxc_random_axis_op)  :: f
        type(mlx_array),  intent(in)    :: a(2)
        integer,          intent(in)    :: option
        character(len=*), intent(in)    :: proc
        type(mlxc_array)  :: res, ha, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a(1), proc)
        call check_dim(a(1), option, proc)
        hk = optional_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a(1)%ndim()-option, c_int), hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_axis_op

    ! r = f(a(1), shape) along Fortran dimension option%dim with the key a(2), for every int f(mlx_array* res,
    ! const mlx_array logits, int axis, const int* shape, size_t shape_num, const mlx_array key, const mlx_stream s)
    module subroutine mlxf_random_axis_shape_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_axis_shape_op)  :: f
        type(mlx_array),        intent(in)    :: a(2)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: res, ha, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a(1), proc)
        call check_dim(a(1), option%dim, proc)
        hk = optional_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a(1)%ndim()-option%dim, c_int), mlx_shape(option), int(size(option%shape), c_size_t), hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_axis_shape_op

    ! r = f(a(1), option%number) along Fortran dimension option%dim with the key a(2), for every int
    ! f(mlx_array* res, const mlx_array logits, int axis, int num_samples, const mlx_array key, const mlx_stream s)
    module subroutine mlxf_random_axis_int_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_axis_int_op)    :: f
        type(mlx_array),        intent(in)    :: a(2)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: res, ha, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        ha = mlxf_handle(a(1), proc)
        call check_dim(a(1), option%dim, proc)
        hk = optional_handle(a(2), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, ha, int(a(1)%ndim()-option%dim, c_int), int(option%number, c_int), hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_axis_int_op

    ! r = f(a(1), a(2), shape, dtype) with the key a(3), on the CPU's default stream when option%on_cpu, for every
    ! int f(mlx_array* res, const mlx_array a, const mlx_array b, const int* shape, size_t shape_num,
    ! mlx_dtype dtype, const mlx_array key, const mlx_stream s)
    module subroutine mlxf_random_binary_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_binary_op)      :: f
        type(mlx_array),        intent(in)    :: a(3)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: res, ha, hb, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call mlxf_check_dtype(option%dtype, proc)
        ha = mlxf_handle(a(1), proc)
        hb = mlxf_handle(a(2), proc)
        hk = optional_handle(a(3), proc)
        res = mlxc_array_new()
        if( option%on_cpu )then
            s = cpu_stream(proc)
        else
            s = mlxf_default_stream(proc)
        endif
        ierr = f(res, ha, hb, mlx_shape(option), int(size(option%shape), c_size_t), int(option%dtype, c_int), hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_binary_op

    ! r = f(shape, dtype, a(1), a(2)) with the key a(3), for every int f(mlx_array* res, const int* shape,
    ! size_t shape_num, mlx_dtype dtype, const mlx_array loc, const mlx_array scale, const mlx_array key,
    ! const mlx_stream s); an empty a(1) or a(2) is MLX's default (0 and 1)
    module subroutine mlxf_random_broadcast_op( r, f, a, option, proc )
        type(mlx_array),        intent(inout) :: r
        procedure(mlxc_random_broadcast_op)   :: f
        type(mlx_array),        intent(in)    :: a(3)
        type(mlxf_random_spec), intent(in)    :: option
        character(len=*),       intent(in)    :: proc
        type(mlxc_array)  :: res, hloc, hscale, hk
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        call mlxf_check_dtype(option%dtype, proc)
        hloc = optional_handle(a(1), proc)
        hscale = optional_handle(a(2), proc)
        hk = optional_handle(a(3), proc)
        res = mlxc_array_new()
        s = mlxf_default_stream(proc)
        ierr = f(res, mlx_shape(option), int(size(option%shape), c_size_t), int(option%dtype, c_int), hloc, hscale, hk, s)
        call finish(r, res, s, ierr, proc)
    end subroutine mlxf_random_broadcast_op

    ! a sample's Fortran shape as MLX takes it: reversed
    function mlx_shape( option ) result(shape)
        type(mlxf_random_spec), intent(in) :: option
        integer(c_int), allocatable :: shape(:)
        shape = int(option%shape(size(option%shape):1:-1), c_int)
    end function mlx_shape

    ! after the C call: frees the stream, stops on MLX's error (freeing the result first) and registers the result
    subroutine finish( r, res, s, ierr, proc )
        type(mlx_array),   intent(inout) :: r
        type(mlxc_array),  intent(inout) :: res
        type(mlxc_stream), intent(in)    :: s
        integer(c_int),    intent(in)    :: ierr
        character(len=*),  intent(in)    :: proc
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        call mlxf_check(ierr, proc)
        call adopt(r, res, proc)
    end subroutine finish

end submodule mlxf_array_random
