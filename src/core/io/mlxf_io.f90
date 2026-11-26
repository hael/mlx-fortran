!@descr: arrays in files: NumPy's .npy, safetensors and GGUF, and the text of a graph
! On disk the bytes are MLX's: a Fortran (m, n) array is the C-order (n, m) array of a NumPy reader, the same
! bytes in the same order, and it reads back as (m, n). Files are read on the CPU's stream, where MLX reads them,
! whatever the default device. Every procedure here is checked: with status a failure returns with MLX usable.
module mlxf_io
use, intrinsic :: iso_c_binding,   only: c_int, c_ptr, c_null_ptr, c_null_char, c_associated
use, intrinsic :: iso_fortran_env, only: output_unit
use mlxf_c_graph_utils, only: mlxc_node_namer_new, mlxc_node_namer_free, mlxc_print_graph, mlxc_export_to_dot
use mlxf_c_io,          only: mlxc_load, mlxc_save, mlxc_load_safetensors, mlxc_save_safetensors, mlxc_load_gguf, &
                              mlxc_save_gguf
use mlxf_c_io_types,    only: mlxc_io_gguf_new, mlxc_io_gguf_free, mlxc_io_gguf_set_array
use mlxf_c_map,         only: mlxc_map_string_to_array_new, mlxc_map_string_to_array_free, &
                              mlxc_map_string_to_array_insert, mlxc_map_string_to_string_new, &
                              mlxc_map_string_to_string_free, mlxc_map_string_to_string_insert, &
                              mlxc_map_string_to_string_iterator_new, mlxc_map_string_to_string_iterator_next, &
                              mlxc_map_string_to_string_iterator_free
use mlxf_c_signatures,  only: mlxc_load_op
use mlxf_c_stream,      only: mlxc_stream_free
use mlxf_c_types,       only: mlxc_stream, mlxc_vector_array, mlxc_map_string_to_array, mlxc_map_string_to_string, &
                              mlxc_map_string_to_string_iterator, mlxc_io_gguf, mlxc_node_namer
use mlxf_c_vector,      only: mlxc_vector_array_new, mlxc_vector_array_free
use mlxf_defs,          only: MLXF_MAP_END
use mlxf_array,         only: mlx_array, mlx_is_live, mlxf_handle, mlxf_vector_export
use mlxf_device,        only: mlxf_require_device
use mlxf_error,         only: mlxf_check, mlxf_report
use mlxf_libc,          only: c_fopen, c_fclose, c_dup, c_fdopen, c_string_copy
use mlxf_calls,         only: mlxf_cpu_stream
implicit none
public :: mlx_save, mlx_load, mlx_save_safetensors, mlx_load_safetensors, mlx_save_gguf, mlx_load_gguf, mlx_print_graph, &
    &mlx_export_to_dot
private

! the signature helpers of the io procedures, implemented in mlxf_io_calls
interface
    ! int f(mlx_array* res, const char* file, const mlx_stream s)
    module subroutine mlxf_load_op( r, f, file, proc, status )
        type(mlx_array),   intent(inout) :: r
        procedure(mlxc_load_op)          :: f
        character(len=*),  intent(in)    :: file, proc
        integer, optional, intent(out)   :: status
    end subroutine mlxf_load_op

    module subroutine mlxf_map_arrays( names, arrays, m, status )
        character(len=:),               allocatable, intent(out) :: names(:)
        type(mlx_array),                allocatable, intent(out) :: arrays(:)
        type(mlxc_map_string_to_array), intent(in)               :: m
        integer,                        intent(out)              :: status
    end subroutine mlxf_map_arrays

    module subroutine mlxf_gguf_arrays( names, arrays, g, status )
        character(len=:),   allocatable, intent(out) :: names(:)
        type(mlx_array),    allocatable, intent(out) :: arrays(:)
        type(mlxc_io_gguf), intent(in)               :: g
        integer,            intent(out)              :: status
    end subroutine mlxf_gguf_arrays
end interface

contains

    ! writes a, evaluated, to file in NumPy's .npy format; MLX adds '.npy' to a name that does not end with it
    subroutine mlx_save( file, a, status )
        character(len=*),  intent(in)  :: file
        type(mlx_array),   intent(in)  :: a
        integer, optional, intent(out) :: status
        call mlxf_require_device('mlx_save')
        if( .not. live_arrays([a], 'mlx_save', status) ) return
        call mlxf_check(mlxc_save(trim(file)//c_null_char, mlxf_handle(a, 'mlx_save')), 'mlx_save', status)
    end subroutine mlx_save

    ! the array of a .npy file, whose name is given whole; with status, a failure returns an empty array. The
    ! data are read when the array is evaluated: the file must stay as it is until then
    function mlx_load( file, status ) result(a)
        character(len=*),  intent(in)  :: file
        integer, optional, intent(out) :: status
        type(mlx_array) :: a
        call mlxf_load_op(a, mlxc_load, file, 'mlx_load', status)
    end function mlx_load

    ! writes arrays under their names to a safetensors file, with metadata, pairs of strings (1, i) and (2, i),
    ! when given. Trailing blanks of names and strings are not written
    subroutine mlx_save_safetensors( file, names, arrays, metadata, status )
        character(len=*),  intent(in)           :: file, names(:)
        type(mlx_array),   intent(in)           :: arrays(:)
        character(len=*),  optional, intent(in) :: metadata(:, :)
        integer, optional, intent(out)          :: status
        type(mlxc_map_string_to_array)  :: m
        type(mlxc_map_string_to_string) :: meta
        integer                         :: st, cleanup, i
        call mlxf_require_device('mlx_save_safetensors')
        if( .not. named_arrays(names, arrays, 'mlx_save_safetensors', status) ) return
        if( present(metadata) )then
            if( size(metadata, 1) /= 2 )then
                call mlxf_report('mlx_save_safetensors', 'metadata are pairs: a (2, n) array of strings', status)
                return
            endif
        endif
        m = mlxc_map_string_to_array_new()
        meta = mlxc_map_string_to_string_new()
        st = 0
        do i = 1, size(arrays)
            if( st == 0 ) call mlxf_check(mlxc_map_string_to_array_insert(m, trim(names(i))//c_null_char, &
                &mlxf_handle(arrays(i), 'mlx_save_safetensors')), 'mlx_save_safetensors', status=st)
        end do
        if( present(metadata) )then
            do i = 1, size(metadata, 2)
                if( st == 0 ) call mlxf_check(mlxc_map_string_to_string_insert(meta, trim(metadata(1, i))//c_null_char, &
                    &trim(metadata(2, i))//c_null_char), 'mlx_save_safetensors', status=st)
            end do
        endif
        if( st == 0 ) call mlxf_check(mlxc_save_safetensors(trim(file)//c_null_char, m, meta), 'mlx_save_safetensors', &
            &status=st)
        call mlxf_check(mlxc_map_string_to_array_free(m), 'mlx_save_safetensors cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_map_string_to_string_free(meta), 'mlx_save_safetensors cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(int(st, c_int), 'mlx_save_safetensors', status)
    end subroutine mlx_save_safetensors

    ! the arrays of a safetensors file and their names, sorted by name, and its metadata as pairs of strings
    ! (1, i) and (2, i), sorted by the first; with status, a failure returns with the lists unallocated
    subroutine mlx_load_safetensors( file, names, arrays, metadata, status )
        character(len=*),  intent(in)                         :: file
        character(len=:),  allocatable, intent(out)           :: names(:)
        type(mlx_array),   allocatable, intent(out)           :: arrays(:)
        character(len=:),  allocatable, optional, intent(out) :: metadata(:, :)
        integer, optional, intent(out)                        :: status
        type(mlxc_map_string_to_array)  :: m
        type(mlxc_map_string_to_string) :: meta
        type(mlxc_stream)               :: s
        integer                         :: st, cleanup
        call mlxf_require_device('mlx_load_safetensors')
        m = mlxc_map_string_to_array_new()
        meta = mlxc_map_string_to_string_new()
        s = mlxf_cpu_stream('mlx_load_safetensors')
        call mlxf_check(mlxc_load_safetensors(m, meta, trim(file)//c_null_char, s), 'mlx_load_safetensors', status=st)
        call mlxf_check(mlxc_stream_free(s), 'mlx_load_safetensors cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st == 0 ) call mlxf_map_arrays(names, arrays, m, st)
        if( st == 0 .and. present(metadata) ) call string_pairs(metadata, meta, st)
        call mlxf_check(mlxc_map_string_to_array_free(m), 'mlx_load_safetensors cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_map_string_to_string_free(meta), 'mlx_load_safetensors cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st /= 0 )then
            if( allocated(names) ) deallocate(names)
            if( allocated(arrays) ) deallocate(arrays)
        endif
        call mlxf_check(int(st, c_int), 'mlx_load_safetensors', status)
    end subroutine mlx_load_safetensors

    ! writes arrays under their names to a GGUF file, without metadata; MLX writes the kinds GGUF has
    subroutine mlx_save_gguf( file, names, arrays, status )
        character(len=*),  intent(in)  :: file, names(:)
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        type(mlxc_io_gguf) :: g
        integer            :: st, cleanup, i
        call mlxf_require_device('mlx_save_gguf')
        if( .not. named_arrays(names, arrays, 'mlx_save_gguf', status) ) return
        g = mlxc_io_gguf_new()
        st = 0
        do i = 1, size(arrays)
            if( st == 0 ) call mlxf_check(mlxc_io_gguf_set_array(g, trim(names(i))//c_null_char, &
                &mlxf_handle(arrays(i), 'mlx_save_gguf')), 'mlx_save_gguf', status=st)
        end do
        if( st == 0 ) call mlxf_check(mlxc_save_gguf(trim(file)//c_null_char, g), 'mlx_save_gguf', status=st)
        call mlxf_check(mlxc_io_gguf_free(g), 'mlx_save_gguf cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(int(st, c_int), 'mlx_save_gguf', status)
    end subroutine mlx_save_gguf

    ! the arrays of a GGUF file and their names, sorted by name; its metadata are not read
    subroutine mlx_load_gguf( file, names, arrays, status )
        character(len=*),  intent(in)               :: file
        character(len=:),  allocatable, intent(out) :: names(:)
        type(mlx_array),   allocatable, intent(out) :: arrays(:)
        integer, optional, intent(out)              :: status
        type(mlxc_io_gguf) :: g
        type(mlxc_stream)  :: s
        integer            :: st, cleanup
        call mlxf_require_device('mlx_load_gguf')
        g = mlxc_io_gguf_new()
        s = mlxf_cpu_stream('mlx_load_gguf')
        call mlxf_check(mlxc_load_gguf(g, trim(file)//c_null_char, s), 'mlx_load_gguf', status=st)
        call mlxf_check(mlxc_stream_free(s), 'mlx_load_gguf cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st == 0 ) call mlxf_gguf_arrays(names, arrays, g, st)
        call mlxf_check(mlxc_io_gguf_free(g), 'mlx_load_gguf cleanup', status=cleanup)
        if( st == 0 ) st = cleanup
        if( st /= 0 )then
            if( allocated(names) ) deallocate(names)
            if( allocated(arrays) ) deallocate(arrays)
        endif
        call mlxf_check(int(st, c_int), 'mlx_load_gguf', status)
    end subroutine mlx_load_gguf

    ! writes the graph that computes arrays as text, one line per operation, to file, or to the standard output
    subroutine mlx_print_graph( arrays, file, status )
        type(mlx_array),   intent(in)           :: arrays(:)
        character(len=*),  optional, intent(in) :: file
        integer, optional, intent(out)          :: status
        call mlxf_require_device('mlx_print_graph')
        call write_graph(arrays, .false., 'mlx_print_graph', file, status)
    end subroutine mlx_print_graph

    ! writes the graph that computes arrays to file in Graphviz's dot language
    subroutine mlx_export_to_dot( file, arrays, status )
        character(len=*),  intent(in)  :: file
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        call mlxf_require_device('mlx_export_to_dot')
        call write_graph(arrays, .true., 'mlx_export_to_dot', file, status)
    end subroutine mlx_export_to_dot

    ! the graph of arrays through C's FILE, as text or as dot; without a file, a copy of the standard output's
    ! descriptor, so that closing the FILE leaves the standard output open
    subroutine write_graph( arrays, dot, proc, file, status )
        type(mlx_array),   intent(in)           :: arrays(:)
        logical,           intent(in)           :: dot
        character(len=*),  intent(in)           :: proc
        character(len=*),  optional, intent(in) :: file
        integer, optional, intent(out)          :: status
        type(mlxc_vector_array) :: v
        type(mlxc_node_namer)   :: namer
        type(c_ptr)             :: f
        integer                 :: st, cleanup
        integer(c_int)          :: closed
        if( .not. live_arrays(arrays, proc, status) ) return
        if( present(file) )then
            f = c_fopen(trim(file)//c_null_char, 'w'//c_null_char)
        else
            flush(output_unit)
            f = c_fdopen(c_dup(1_c_int), 'w'//c_null_char)
        endif
        if( .not. c_associated(f) )then
            call mlxf_report(proc, 'the file could not be opened for writing', status)
            return
        endif
        v = mlxc_vector_array_new()
        namer = mlxc_node_namer_new()
        call mlxf_vector_export(v, arrays, st)
        if( st == 0 )then
            if( dot )then
                call mlxf_check(mlxc_export_to_dot(f, namer, v), proc, status=st)
            else
                call mlxf_check(mlxc_print_graph(f, namer, v), proc, status=st)
            endif
        endif
        call mlxf_check(mlxc_node_namer_free(namer), proc, status=cleanup)
        if( st == 0 ) st = cleanup
        call mlxf_check(mlxc_vector_array_free(v), proc, status=cleanup)
        if( st == 0 ) st = cleanup
        closed = c_fclose(f)
        if( closed /= 0 .and. st == 0 ) call mlxf_report(proc, 'the file could not be closed', status=st)
        call mlxf_check(int(st, c_int), proc, status)
    end subroutine write_graph

    ! whether every array is live; an empty or stale one is reported (the status, or a stop)
    logical function live_arrays( arrays, proc, status )
        type(mlx_array),   intent(in)  :: arrays(:)
        character(len=*),  intent(in)  :: proc
        integer, optional, intent(out) :: status
        integer :: i
        live_arrays = .true.
        if( present(status) ) status = 0
        do i = 1, size(arrays)
            if( .not. mlx_is_live(arrays(i)) ) live_arrays = .false.
        end do
        if( .not. live_arrays ) call mlxf_report(proc, 'an array is empty or stale', status)
    end function live_arrays

    ! whether names and arrays pair up, no name is given twice (MLX would keep one of the two arrays without a
    ! word) and every array is live; anything else is reported
    logical function named_arrays( names, arrays, proc, status )
        character(len=*),  intent(in)  :: names(:), proc
        type(mlx_array),   intent(in)  :: arrays(:)
        integer, optional, intent(out) :: status
        integer :: i, j
        named_arrays = size(names) == size(arrays)
        if( .not. named_arrays )then
            call mlxf_report(proc, 'one name per array is needed', status)
            return
        endif
        do i = 2, size(names)
            do j = 1, i-1
                if( trim(names(i)) == trim(names(j)) ) named_arrays = .false.
            end do
        end do
        if( .not. named_arrays )then
            call mlxf_report(proc, 'a name is given twice', status)
            return
        endif
        named_arrays = live_arrays(arrays, proc, status)
    end function named_arrays

    ! the pairs of an mlx-c map of strings as a (2, n) array, sorted by the first of each pair
    subroutine string_pairs( pairs, meta, status )
        character(len=:),                allocatable, intent(out) :: pairs(:, :)
        type(mlxc_map_string_to_string), intent(in)               :: meta
        integer,                         intent(out)              :: status
        type(mlxc_map_string_to_string_iterator) :: it
        character(len=:), allocatable            :: found(:, :), key, val
        type(c_ptr)                              :: pk, pv
        integer                                  :: n, width, pass, i, j, k, cleanup
        integer(c_int)                           :: rc
        integer, allocatable                     :: order(:)
        status = 0
        n = 0
        width = 1
        do pass = 1, 2
            if( pass == 2 )then
                allocate(character(len=width) :: found(2, n), stat=status)
                if( status /= 0 ) return
                n = 0
            endif
            it = mlxc_map_string_to_string_iterator_new(meta)
            do
                pk = c_null_ptr
                pv = c_null_ptr
                rc = mlxc_map_string_to_string_iterator_next(pk, pv, it)
                if( rc /= 0 )then
                    if( int(rc) /= MLXF_MAP_END ) status = int(rc)
                    exit
                endif
                n = n+1
                key = c_string_copy(pk)
                val = c_string_copy(pv)
                if( pass == 1 )then
                    width = max(width, len(key), len(val))
                else
                    found(1, n) = key
                    found(2, n) = val
                endif
            end do
            call mlxf_check(mlxc_map_string_to_string_iterator_free(it), 'metadata import', status=cleanup)
            if( status /= 0 ) return
        end do
        allocate(order(n), stat=status)
        if( status == 0 ) allocate(character(len=width) :: pairs(2, n), stat=status)
        if( status /= 0 ) return
        do i = 1, n
            k = i
            do j = i-1, 1, -1
                if( llt(found(1, order(j)), found(1, i)) ) exit
                order(j+1) = order(j)
                k = j
            end do
            order(k) = i
        end do
        do i = 1, n
            pairs(:, i) = found(:, order(i))
        end do
    end subroutine string_pairs

end module mlxf_io
