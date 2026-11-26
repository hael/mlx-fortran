!@descr: helpers of file input: an array read on the CPU's stream, and the arrays of a map or of a GGUF file as counted handles
! MLX reads files on the CPU only, so what is read is built on the CPU's default stream whatever the default
! device. Names come back sorted, since MLX keeps them in a hash table whose order means nothing.
submodule(mlxf_array) mlxf_array_io
use, intrinsic :: iso_c_binding, only: c_null_char, c_null_ptr
use mlxf_c_types,    only: mlxc_map_string_to_array, mlxc_map_string_to_array_iterator, mlxc_io_gguf, &
                           mlxc_vector_string
use mlxf_c_array,    only: mlxc_array_new, mlxc_array_free
use mlxf_c_io_types, only: mlxc_io_gguf_get_keys, mlxc_io_gguf_get_array
use mlxf_c_map,      only: mlxc_map_string_to_array_iterator_new, mlxc_map_string_to_array_iterator_next, &
                           mlxc_map_string_to_array_iterator_free
use mlxf_c_stream,   only: mlxc_stream_free
use mlxf_c_vector,   only: mlxc_vector_string_new, mlxc_vector_string_free, mlxc_vector_string_size, &
                           mlxc_vector_string_get
use mlxf_defs,       only: MLXF_MAP_END
use mlxf_device,     only: mlxf_require_device
use mlxf_error,      only: mlxf_check
use mlxf_libc,       only: c_string_copy
implicit none

contains

    ! the default stream of the CPU for the library's file readers; the caller frees it with mlxc_stream_free
    module function mlxf_cpu_stream( proc ) result(s)
        character(len=*), intent(in) :: proc
        type(mlxc_stream) :: s
        s = cpu_stream(proc)
    end function mlxf_cpu_stream

    ! r = f(file) on the CPU's default stream, for every int f(mlx_array* res, const char* file, const mlx_stream s);
    ! with status, a failure returns with r empty
    module subroutine mlxf_load_op( r, f, file, proc, status )
        type(mlx_array),   intent(inout) :: r
        procedure(mlxc_load_op)          :: f
        character(len=*),  intent(in)    :: file, proc
        integer, optional, intent(out)   :: status
        type(mlxc_array)  :: res
        type(mlxc_stream) :: s
        integer(c_int)    :: ierr
        call mlxf_require_device(proc)
        res = mlxc_array_new()
        s = cpu_stream(proc)
        ierr = f(res, trim(file)//c_null_char, s)
        call mlxf_check(mlxc_stream_free(s), proc)
        if( ierr /= 0 )then
            call mlxf_check(mlxc_array_free(res), proc)
            call mlxf_check(ierr, proc, status)
            return
        endif
        call adopt(r, res, proc, status)
        if( present(status) )then
            if( status /= 0 ) call mlxf_check(mlxc_array_free(res), proc)
        endif
    end subroutine mlxf_load_op

    ! the arrays of an mlx-c map and their names, sorted by name; a failure returns a status and leaves both
    ! unallocated
    module subroutine mlxf_map_arrays( names, arrays, m, status )
        character(len=:),               allocatable, intent(out) :: names(:)
        type(mlx_array),                allocatable, intent(out) :: arrays(:)
        type(mlxc_map_string_to_array), intent(in)               :: m
        integer,                        intent(out)              :: status
        type(mlxc_map_string_to_array_iterator) :: it
        type(mlx_array), allocatable            :: found(:)
        character(len=:), allocatable           :: keys(:), key
        type(mlxc_array)                        :: h
        type(c_ptr)                             :: p
        integer                                 :: n, width, pass, cleanup
        integer(c_int)                          :: rc
        status = 0
        n = 0
        width = 1
        do pass = 1, 2
            if( pass == 2 )then
                allocate(found(n), stat=status)
                if( status == 0 ) allocate(character(len=width) :: keys(n), stat=status)
                if( status /= 0 ) return
                n = 0
            endif
            it = mlxc_map_string_to_array_iterator_new(m)
            do
                p = c_null_ptr
                h = mlxc_array_new()
                rc = mlxc_map_string_to_array_iterator_next(p, h, it)
                if( rc /= 0 )then
                    call mlxf_check(mlxc_array_free(h), 'map import', status=cleanup)
                    if( int(rc) /= MLXF_MAP_END ) status = int(rc)
                    exit
                endif
                n = n+1
                key = c_string_copy(p)
                if( pass == 1 )then
                    width = max(width, len(key))
                    call mlxf_check(mlxc_array_free(h), 'map import', status=cleanup)
                else
                    keys(n) = key
                    call adopt(found(n), h, 'map import', status)
                    if( status /= 0 ) call mlxf_check(mlxc_array_free(h), 'map import', status=cleanup)
                endif
                if( status /= 0 ) exit
            end do
            call mlxf_check(mlxc_map_string_to_array_iterator_free(it), 'map import', status=cleanup)
            if( status /= 0 ) return
        end do
        call sorted_by_name(names, arrays, keys, found, status)
    end subroutine mlxf_map_arrays

    ! the arrays of a GGUF file and their names, sorted by name; a failure returns a status
    module subroutine mlxf_gguf_arrays( names, arrays, g, status )
        character(len=:),   allocatable, intent(out) :: names(:)
        type(mlx_array),    allocatable, intent(out) :: arrays(:)
        type(mlxc_io_gguf), intent(in)               :: g
        integer,            intent(out)              :: status
        type(mlxc_vector_string)      :: v
        type(mlx_array), allocatable  :: found(:)
        character(len=:), allocatable :: keys(:), key
        type(mlxc_array)              :: h
        type(c_ptr)                   :: p
        integer                       :: n, i, width, pass, cleanup
        v = mlxc_vector_string_new()
        call mlxf_check(mlxc_io_gguf_get_keys(v, g), 'gguf import', status=status)
        n = 0
        if( status == 0 ) n = int(mlxc_vector_string_size(v))
        width = 1
        do pass = 1, 2
            if( status /= 0 ) exit
            if( pass == 2 )then
                allocate(found(n), stat=status)
                if( status == 0 ) allocate(character(len=width) :: keys(n), stat=status)
                if( status /= 0 ) exit
            endif
            do i = 1, n
                p = c_null_ptr
                call mlxf_check(mlxc_vector_string_get(p, v, int(i-1, c_size_t)), 'gguf import', status=status)
                if( status /= 0 ) exit
                key = c_string_copy(p)
                if( pass == 1 )then
                    width = max(width, len(key))
                    cycle
                endif
                keys(i) = key
                h = mlxc_array_new()
                call mlxf_check(mlxc_io_gguf_get_array(h, g, key//c_null_char), 'gguf import', status=status)
                if( status == 0 ) call adopt(found(i), h, 'gguf import', status)
                if( status /= 0 )then
                    call mlxf_check(mlxc_array_free(h), 'gguf import', status=cleanup)
                    exit
                endif
            end do
        end do
        call mlxf_check(mlxc_vector_string_free(v), 'gguf import', status=cleanup)
        if( status == 0 ) call sorted_by_name(names, arrays, keys, found, status)
    end subroutine mlxf_gguf_arrays

    ! names and arrays in ascending order of the names (an insertion sort of positions: the lists are short)
    subroutine sorted_by_name( names, arrays, keys, found, status )
        character(len=:), allocatable, intent(out) :: names(:)
        type(mlx_array),  allocatable, intent(out) :: arrays(:)
        character(len=*), intent(in)               :: keys(:)
        type(mlx_array),  intent(in)               :: found(:)
        integer,          intent(out)              :: status
        integer, allocatable :: order(:)
        integer              :: i, j, k, n
        n = size(keys)
        allocate(order(n), stat=status)
        if( status == 0 ) allocate(arrays(n), stat=status)
        if( status == 0 ) allocate(character(len=len(keys)) :: names(n), stat=status)
        if( status /= 0 ) return
        do i = 1, n
            k = i
            do j = i-1, 1, -1
                if( llt(keys(order(j)), keys(i)) ) exit
                order(j+1) = order(j)
                k = j
            end do
            order(k) = i
        end do
        do i = 1, n
            names(i) = keys(order(i))
            arrays(i) = found(order(i))
        end do
    end subroutine sorted_by_name

end submodule mlxf_array_io
