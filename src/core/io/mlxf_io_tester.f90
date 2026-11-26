!@descr: arrays in files: byte-identical .npy round trips of every transfer kind and rank, the header's reversed shape, safetensors, GGUF, graph text, sizes
! A saved file is read here as bytes: its NumPy header is parsed in Fortran and its data compared with the bytes
! of the host array, so nothing of MLX judges what MLX wrote. Files are written in the working directory and
! deleted.
module mlxf_io_tester
use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
use, intrinsic :: iso_c_binding,   only: c_bool
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_astype, mlx_is_live, mlx_live_count, mlx_last_error, &
                           mlx_active_memory, mlx_eval, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                           MLX_DTYPES, reshape, transpose, mlx_save, mlx_load, mlx_save_safetensors, &
                           mlx_load_safetensors, mlx_save_gguf, mlx_load_gguf, mlx_print_graph, mlx_export_to_dot, &
                           mlx_buffer_size
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, bits_equal
implicit none
private
public :: run_all_io_tests

! the extents of the round-trip fixtures by rank, 0 to 4 (no shape of rank 2 or more reads the same reversed),
! and their sizes
integer, parameter :: EXTENTS(4) = [2, 3, 4, 2]
integer, parameter :: NMAX = 48

! what a .npy file must hold: the bytes of its elements, its Fortran shape and NumPy's name of its kind
type :: npy_expectation
    integer(int8), allocatable :: bytes(:)
    integer,       allocatable :: shape(:)
    character(len=4)           :: descr = ''
    logical                    :: c_order = .true.
end type npy_expectation

contains

    subroutine run_all_io_tests
        integer, allocatable :: devs(:)
        integer              :: i, original, live0
        write(*,'(a)') '**** running all io tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            live0 = mlx_live_count()
            call test_npy_round_trips(devs(i))
            call test_host_matrix
            call test_strided_view
            call test_safetensors(devs(i))
            call test_gguf
            call test_name_order
            call test_failures
            call test_no_growth
            call test_sizes
            call test_graph_text
            call assert_int(live0, mlx_live_count(), 'saved and loaded arrays leave no live handles')
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_io_tests

    ! every transfer kind at ranks 0 to 4: the file's header, its bytes, the array read back and a second file
    ! written from it
    subroutine test_npy_round_trips( device )
        integer, intent(in) :: device
        real(real32)        :: r32(NMAX)
        real(real64)        :: r64(NMAX)
        complex(real32)     :: c32(NMAX)
        integer(int8)       :: i8(NMAX)
        integer(int16)      :: i16(NMAX)
        integer(int32)      :: i32(NMAX)
        integer(int64)      :: i64(NMAX)
        logical(c_bool)     :: flags(NMAX)
        type(mlx_array)     :: flat
        integer             :: rank, n, k
        write(*,'(a)') 'test_npy_round_trips'
        do k = 1, NMAX
            r32(k) = real(k, real32)/7._real32-1.5_real32
            r64(k) = real(k, real64)/7._real64-1.5_real64
            c32(k) = cmplx(real(k, real32)/3._real32, -real(k, real32)/11._real32, real32)
            i8(k) = int(5*k-120, int8)
            i16(k) = int(1000*k-24000, int16)
            i32(k) = int(100000*k-2400000, int32)
            i64(k) = int(k, int64)*4000000000_int64-96000000000_int64
            flags(k) = modulo(k, 3) == 0
        end do
        do rank = 0, 4
            n = product(EXTENTS(1:rank))
            if( rank == 0 )then
                flat = mlx_from(r32(1))
            else
                flat = mlx_from(r32(1:n))
            endif
            call round_trip(flat, npy_expectation(transfer(r32(1:n), i8), EXTENTS(1:rank), '<f4'))
            if( device == MLX_DEVICES%cpu )then
                flat = mlx_from(r64(1:n))
                if( rank == 0 ) flat = reshape(flat, [integer ::])
                call round_trip(flat, npy_expectation(transfer(r64(1:n), i8), EXTENTS(1:rank), '<f8'))
            endif
            flat = mlx_from(c32(1:n))
            if( rank == 0 ) flat = reshape(flat, [integer ::])
            call round_trip(flat, npy_expectation(transfer(c32(1:n), i8), EXTENTS(1:rank), '<c8'))
            flat = mlx_from(i8(1:n))
            if( rank == 0 ) flat = reshape(flat, [integer ::])
            call round_trip(flat, npy_expectation(i8(1:n), EXTENTS(1:rank), '|i1'))
            flat = mlx_from(i16(1:n))
            if( rank == 0 ) flat = reshape(flat, [integer ::])
            call round_trip(flat, npy_expectation(transfer(i16(1:n), i8), EXTENTS(1:rank), '<i2'))
            flat = mlx_from(i32(1:n))
            if( rank == 0 ) flat = reshape(flat, [integer ::])
            call round_trip(flat, npy_expectation(transfer(i32(1:n), i8), EXTENTS(1:rank), '<i4'))
            flat = mlx_from(i64(1:n))
            if( rank == 0 ) flat = reshape(flat, [integer ::])
            call round_trip(flat, npy_expectation(transfer(i64(1:n), i8), EXTENTS(1:rank), '<i8'))
            flat = mlx_from(flags(1:n))
            if( rank == 0 ) flat = reshape(flat, [integer ::])
            call round_trip(flat, npy_expectation(transfer(flags(1:n), i8), EXTENTS(1:rank), '|b1'))
        end do
    end subroutine test_npy_round_trips

    ! a host matrix saved as it is: the file's data are the matrix's own bytes under its shape reversed
    subroutine test_host_matrix
        type(mlx_array)             :: a
        type(npy_expectation)       :: found
        real(real32)                :: x(2, 3)
        integer(int8)               :: one(1)
        integer                     :: st
        logical                     :: same
        character(len=*), parameter :: FILE = 'mlxf_io_matrix.npy'
        write(*,'(a)') 'test_host_matrix'
        x = reshape([1._real32, 2._real32, 3._real32, 4._real32, 5._real32, 6._real32], [2, 3])
        a = mlx_from(x)
        call mlx_save(FILE, a, status=st)
        call assert_int(0, st, 'a host matrix of shape (2, 3) is saved')
        call read_npy(FILE, found, st)
        call assert_int(0, st, 'in C order')
        if( st == 0 )then
            call assert_true(all(found%shape == [3, 2]), 'under the shape (3, 2), its Fortran shape reversed')
            same = size(found%bytes) == 24
            if( same ) same = all(found%bytes == transfer(x, one))
            call assert_true(same, 'and the data are the matrix''s 24 bytes as Fortran stores them')
        endif
        call remove(FILE)
    end subroutine test_host_matrix

    ! a transposed view is written without a copy, in NumPy's Fortran order, and reads back as the transpose
    subroutine test_strided_view
        type(mlx_array)             :: a, t, back
        type(npy_expectation)       :: found
        real(real32)                :: x(2, 3), got(3, 2)
        integer                     :: st
        character(len=*), parameter :: FILE = 'mlxf_io_view.npy'
        write(*,'(a)') 'test_strided_view'
        x = reshape([1._real32, 2._real32, 3._real32, 4._real32, 5._real32, 6._real32], [2, 3])
        a = mlx_from(x)
        t = transpose(a)
        call mlx_save(FILE, t, status=st)
        call assert_int(0, st, 'a transposed view is saved')
        call read_npy(FILE, found, st)
        call assert_true(st /= 0 .and. .not. found%c_order, 'MLX writes it in NumPy''s Fortran order, the bytes it already has')
        call assert_true(all(found%shape == [2, 3]), 'under the Fortran shape of the view, (3, 2), reversed')
        back = mlx_load(FILE, status=st)
        call assert_int(0, st, 'and it is loaded')
        if( st == 0 )then
            call assert_true(all(back%shape() == [3, 2]), 'with the transpose''s Fortran shape')
            call mlx_to(got, back)
            call assert_true(all(bits_equal(got, transpose(x))), 'and the transpose''s values')
        endif
        call remove(FILE)
    end subroutine test_strided_view

    ! saves flat in the shape expected, reads the file as bytes and as an array, and writes the array again
    subroutine round_trip( flat, want )
        type(mlx_array),       intent(in) :: flat
        type(npy_expectation), intent(in) :: want
        type(mlx_array)               :: a, back
        type(npy_expectation)         :: first, second
        integer                       :: st
        logical                       :: same
        character(len=:), allocatable :: what
        character(len=32)             :: label
        character(len=*), parameter   :: FIRST_FILE = 'mlxf_io_first.npy', SECOND_FILE = 'mlxf_io_second.npy'
        write(label,'(a,i0)') want%descr//' of rank ', size(want%shape)
        what = trim(label)
        a = reshape(flat, want%shape)
        call mlx_save(FIRST_FILE, a, status=st)
        call assert_int(0, st, what//': saved')
        call read_npy(FIRST_FILE, first, st)
        call assert_int(0, st, what//': the file is a .npy file of format 1.0, in C order from rank 2 on')
        if( st /= 0 ) return
        call assert_true(first%descr == want%descr, what//': the header names the kind')
        same = size(first%shape) == size(want%shape)
        if( same ) same = all(first%shape == want%shape(size(want%shape):1:-1))
        call assert_true(same, what//': the header holds the Fortran shape reversed')
        same = size(first%bytes) == size(want%bytes)
        if( same ) same = all(first%bytes == want%bytes)
        call assert_true(same, what//': the data are the host array''s bytes, in array element order')
        back = mlx_load(FIRST_FILE, status=st)
        call assert_int(0, st, what//': loaded')
        if( st /= 0 ) return
        call assert_true(back%kind() == a%kind(), what//': read back with its kind')
        same = back%ndim() == size(want%shape)
        if( same ) same = all(back%shape() == want%shape)
        call assert_true(same, what//': read back with its Fortran shape')
        call mlx_save(SECOND_FILE, back, status=st)
        call read_npy(SECOND_FILE, second, st)
        same = st == 0
        if( same ) same = size(second%bytes) == size(first%bytes) .and. size(second%shape) == size(first%shape)
        if( same ) same = all(second%bytes == first%bytes) .and. all(second%shape == first%shape) .and. second%descr == first%descr
        call assert_true(same, what//': the array read back writes the same file')
        call remove(FIRST_FILE)
        call remove(SECOND_FILE)
    end subroutine round_trip

    ! a .npy file of format 1.0 as its kind, its shape as written (NumPy's order), its order and its data bytes;
    ! status 1 for anything else, a Fortran-order file of rank 2 or more included (below rank 2 the order of a
    ! file means nothing, and MLX writes "Fortran" there)
    subroutine read_npy( file, found, status )
        character(len=*),      intent(in)  :: file
        type(npy_expectation), intent(out) :: found
        integer,               intent(out) :: status
        character(len=:), allocatable :: header, list
        character(len=10)             :: start
        integer(int8)                 :: len2(2)
        integer                       :: unit, hlen, total, i, j, n, io
        status = 1
        open(newunit=unit, file=file, access='stream', form='unformatted', status='old', action='read', iostat=io)
        if( io /= 0 ) return
        inquire(unit=unit, size=total)
        read(unit, iostat=io) start
        if( io == 0 .and. start(2:6) == 'NUMPY' .and. iachar(start(1:1)) == 147 .and. iachar(start(7:7)) == 1 )then
            len2 = transfer(start(9:10), len2)
            hlen = iand(int(len2(1)), 255)+256*iand(int(len2(2)), 255)
            allocate(character(len=hlen) :: header)
            read(unit, iostat=io) header
            n = total-10-hlen
            if( io == 0 .and. n >= 0 )then
                i = index(header, "'descr': '")
                found%descr = header(i+10:i+12)
                i = index(header, "'shape': (")+10
                j = i+index(header(i:), ')')-2
                list = header(i:j)
                found%shape = numbers_of(list)
                found%c_order = index(header, "'fortran_order': False") > 0
                allocate(found%bytes(n))
                read(unit, iostat=io) found%bytes
                if( io == 0 .and. (found%c_order .or. size(found%shape) <= 1) ) status = 0
            endif
        endif
        close(unit)
    end subroutine read_npy

    ! the integers of a list written "2, 3, " (none for an empty list)
    function numbers_of( list ) result(values)
        character(len=*), intent(in) :: list
        integer, allocatable :: values(:)
        integer              :: i, value
        logical              :: inside
        allocate(values(0))
        value = 0
        inside = .false.
        do i = 1, len(list)
            if( list(i:i) >= '0' .and. list(i:i) <= '9' )then
                value = 10*value+iachar(list(i:i))-iachar('0')
                inside = .true.
            else
                if( inside ) values = [values, value]
                value = 0
                inside = .false.
            endif
        end do
        if( inside ) values = [values, value]
    end function numbers_of

    ! named arrays and metadata through a safetensors file: names sorted, kinds, shapes and values kept
    subroutine test_safetensors( device )
        integer, intent(in) :: device
        type(mlx_array)               :: w, b, c, wide
        type(mlx_array),  allocatable :: arrays(:)
        character(len=:), allocatable :: names(:), meta(:, :)
        character(len=12)             :: pairs(2, 2)
        real(real32)                  :: weights(3, 2), got(3, 2)
        integer(int32)                :: bias(4), gotb(4)
        integer(int16)                :: count(1), gotc(1)
        integer                       :: st
        character(len=*), parameter   :: FILE = 'mlxf_io_test.safetensors'
        write(*,'(a)') 'test_safetensors'
        weights = reshape([0.5_real32, -1._real32, 2.25_real32, 4._real32, -8.5_real32, 16._real32], [3, 2])
        bias = [7, -3, 0, 11]
        count = 42_int16
        w = mlx_from(weights)
        b = mlx_from(bias)
        c = mlx_from(count(1))
        pairs(:, 1) = [character(len=12) :: 'writer', 'mlxf']
        pairs(:, 2) = [character(len=12) :: 'format', 'pt']
        call mlx_save_safetensors(FILE, [character(len=8) :: 'weights', 'bias', 'count'], [w, b, c], metadata=pairs, status=st)
        call assert_int(0, st, 'three named arrays and two pairs of metadata are saved')
        call mlx_load_safetensors(FILE, names, arrays, metadata=meta, status=st)
        call assert_int(0, st, 'and loaded')
        if( st == 0 )then
            call assert_int(3, size(arrays), 'three arrays come back')
            call assert_int(7, len(names), 'the names are as long as the longest of them, weights')
            call assert_int(6, len(meta), 'and the metadata as long as its longest string')
            call assert_true(all(names == [character(len=8) :: 'bias', 'count', 'weights']), 'their names come back sorted')
            call assert_true(arrays(3)%kind() == MLX_DTYPES%float32, 'the float32 array keeps its kind')
            call assert_true(all(arrays(3)%shape() == [3, 2]), 'and its Fortran shape')
            call mlx_to(got, arrays(3))
            call assert_true(all(bits_equal(got, weights)), 'and its values, bit for bit')
            call assert_true(arrays(1)%kind() == MLX_DTYPES%int32, 'the int32 array keeps its kind')
            call mlx_to(gotb, arrays(1))
            call assert_true(all(gotb == bias), 'and its values')
            call assert_int(0, arrays(2)%ndim(), 'the rank-0 array comes back rank 0')
            call mlx_to(gotc, arrays(2))
            call assert_true(gotc(1) == 42_int16, 'with its int16 value')
            call assert_true(all(shape(meta) == [2, 2]), 'two pairs of metadata come back')
            call assert_true(all(meta(1, :) == [character(len=12) :: 'format', 'writer']), 'sorted by their first string')
            call assert_true(all(meta(2, :) == [character(len=12) :: 'pt', 'mlxf']), 'each with its second')
        endif
        call assert_true(index(contents(FILE), '"writer":"mlxf"') > 0, 'the file itself holds the pair writer, mlxf')
        call mlx_load_safetensors(FILE, names, arrays, status=st)
        call assert_int(0, st, 'the file loads without asking for its metadata')
        if( device == MLX_DEVICES%cpu )then
            wide = mlx_astype(w, MLX_DTYPES%float64)
            call mlx_save_safetensors(FILE, ['wide'], [wide], status=st)
            call assert_true(st /= 0, 'a float64 array, which safetensors as MLX writes it lacks, is refused with a status')
        endif
        call remove(FILE)
    end subroutine test_safetensors

    ! named arrays through a GGUF file, in the kinds GGUF has; a kind it lacks is a status
    subroutine test_gguf
        type(mlx_array)               :: w, b, big
        type(mlx_array),  allocatable :: arrays(:)
        character(len=:), allocatable :: names(:)
        real(real32)                  :: weights(3, 2), got(3, 2)
        integer(int32)                :: bias(4), gotb(4)
        integer                       :: st
        character(len=*), parameter   :: FILE = 'mlxf_io_test.gguf'
        write(*,'(a)') 'test_gguf'
        weights = reshape([0.5_real32, -1._real32, 2.25_real32, 4._real32, -8.5_real32, 16._real32], [3, 2])
        bias = [7, -3, 0, 11]
        w = mlx_from(weights)
        b = mlx_from(bias)
        call mlx_save_gguf(FILE, [character(len=8) :: 'weights', 'bias'], [w, b], status=st)
        call assert_int(0, st, 'a float32 and an int32 array are saved to GGUF')
        call mlx_load_gguf(FILE, names, arrays, status=st)
        call assert_int(0, st, 'and loaded')
        if( st == 0 )then
            call assert_true(all(names == [character(len=8) :: 'bias', 'weights']), 'their names come back sorted')
            call assert_int(7, len(names), 'as long as the longest of them, without the blanks they were given with')
            call assert_true(arrays(1)%kind() == MLX_DTYPES%int32, 'the int32 array keeps its kind')
            call assert_true(arrays(2)%kind() == MLX_DTYPES%float32, 'the float32 array keeps its kind')
            call assert_true(all(arrays(2)%shape() == [3, 2]), 'the matrix keeps its Fortran shape')
            call mlx_to(got, arrays(2))
            call assert_true(all(bits_equal(got, weights)), 'and its values, bit for bit')
            call mlx_to(gotb, arrays(1))
            call assert_true(all(gotb == bias), 'the int32 array keeps its values')
        endif
        big = mlx_astype(b, MLX_DTYPES%int64)
        call mlx_save_gguf(FILE, ['big'], [big], status=st)
        call assert_true(st /= 0, 'an int64 array, which GGUF as MLX writes it lacks, is refused with a status')
        call assert_true(len(mlx_last_error()) > 0, 'and a message')
        call remove(FILE)
    end subroutine test_gguf

    ! eight arrays saved under names in no order come back sorted by name, each name with its own array
    subroutine test_name_order
        integer,          parameter   :: N = 8
        character(len=5), parameter   :: GIVEN(N) = [character(len=5) :: 'mu', 'alpha', 'zeta', 'beta', 'nu', 'eta', 'omega', 'chi']
        character(len=5), parameter   :: SORTED(N) = [character(len=5) :: 'alpha', 'beta', 'chi', 'eta', 'mu', 'nu', 'omega', &
            &'zeta']
        integer,          parameter   :: PLACE(N) = [5, 1, 8, 2, 6, 4, 7, 3]
        type(mlx_array)               :: saved(N)
        type(mlx_array),  allocatable :: arrays(:)
        character(len=:), allocatable :: names(:)
        real(real32)                  :: value(1), got(N)
        integer                       :: i, st, format
        logical                       :: paired
        character(len=*), parameter   :: FILES(2) = [character(len=25) :: 'mlxf_io_names.safetensors', 'mlxf_io_names.gguf']
        write(*,'(a)') 'test_name_order'
        do i = 1, N
            value = real(i, real32)
            saved(i) = mlx_from(value)
        end do
        do format = 1, 2
            if( format == 1 )then
                call mlx_save_safetensors(trim(FILES(1)), GIVEN, saved, status=st)
                if( st == 0 ) call mlx_load_safetensors(trim(FILES(1)), names, arrays, status=st)
            else
                call mlx_save_gguf(trim(FILES(2)), GIVEN, saved, status=st)
                if( st == 0 ) call mlx_load_gguf(trim(FILES(2)), names, arrays, status=st)
            endif
            call assert_int(0, st, trim(FILES(format))//': eight named arrays are saved and loaded')
            if( st /= 0 ) cycle
            paired = size(arrays) == N
            if( paired ) paired = all(names == SORTED)
            call assert_true(paired, trim(FILES(format))//': the eight names come back sorted')
            if( .not. paired ) cycle
            do i = 1, N
                call mlx_to(value, arrays(i))
                got(i) = value(1)
            end do
            ! the array saved i-th comes back at the place of its name
            call assert_true(all(nint(got(PLACE)) == [(i, i = 1, N)]), trim(FILES(format))//': each name with its own array')
            call remove(trim(FILES(format)))
        end do
    end subroutine test_name_order

    ! round trips repeated through the three formats leave the memory MLX holds for arrays where it was
    subroutine test_no_growth
        integer, parameter            :: NTRIPS = 20
        type(mlx_array)               :: a, back
        type(mlx_array),  allocatable :: arrays(:)
        character(len=:), allocatable :: names(:)
        real(real32)                  :: x(64, 32)
        integer(int64)                :: before, after
        integer                       :: trip, st, failures
        write(*,'(a)') 'test_no_growth'
        x = 0.5_real32
        a = mlx_from(x)
        failures = 0
        before = 0_int64
        do trip = 0, NTRIPS
            call mlx_save('mlxf_io_growth.npy', a, status=st)
            if( st == 0 ) back = mlx_load('mlxf_io_growth.npy', status=st)
            if( st == 0 ) call mlx_eval(back)
            if( st /= 0 ) failures = failures+1
            call mlx_save_safetensors('mlxf_io_growth.safetensors', ['a'], [a], status=st)
            if( st == 0 ) call mlx_load_safetensors('mlxf_io_growth.safetensors', names, arrays, status=st)
            if( st == 0 ) call mlx_eval(arrays)
            if( st /= 0 ) failures = failures+1
            call mlx_save_gguf('mlxf_io_growth.gguf', ['a'], [a], status=st)
            if( st == 0 ) call mlx_load_gguf('mlxf_io_growth.gguf', names, arrays, status=st)
            if( st == 0 ) call mlx_eval(arrays)
            if( st /= 0 ) failures = failures+1
            ! the first trip fills what stays allocated between trips
            if( trip == 0 ) before = mlx_active_memory()
        end do
        after = mlx_active_memory()
        call assert_int(0, failures, 'twenty round trips through .npy, safetensors and GGUF succeed')
        call assert_true(after <= before, 'and leave the active memory where the first trip left it')
        call remove('mlxf_io_growth.npy')
        call remove('mlxf_io_growth.safetensors')
        call remove('mlxf_io_growth.gguf')
    end subroutine test_no_growth

    ! what a file cannot give is a status, with MLX usable afterwards
    subroutine test_failures
        type(mlx_array)               :: a, r, empty
        type(mlx_array),  allocatable :: arrays(:)
        character(len=:), allocatable :: names(:)
        real(real32)                  :: x(3)
        integer                       :: st, live0
        logical                       :: there
        character(len=4)              :: triple(3, 1)
        write(*,'(a)') 'test_failures'
        triple = 'none'
        call remove('mlxf_io_bad.safetensors')
        call remove('mlxf_io_bad.gguf')
        x = 1._real32
        a = mlx_from(x)
        live0 = mlx_live_count()
        r = mlx_load('mlxf_no_such_file.npy', status=st)
        call assert_true(st /= 0, 'a .npy file that does not exist is refused with a status')
        call assert_true(.not. mlx_is_live(r), 'and no array is returned')
        call assert_true(len(mlx_last_error()) > 0, 'with a message')
        call mlx_save('mlxf_no_such_directory/a.npy', a, status=st)
        call assert_true(st /= 0, 'a file that cannot be written is refused with a status')
        call mlx_save('mlxf_io_empty.npy', empty, status=st)
        call assert_true(st /= 0, 'an empty array is refused with a status')
        call mlx_load_safetensors('mlxf_no_such_file.safetensors', names, arrays, status=st)
        call assert_true(st /= 0, 'a safetensors file that does not exist is refused with a status')
        call assert_true(.not. allocated(arrays), 'and leaves the list unallocated')
        call mlx_load_gguf('mlxf_no_such_file.gguf', names, arrays, status=st)
        call assert_true(st /= 0, 'a GGUF file that does not exist is refused with a status')
        call mlx_save_safetensors('mlxf_io_bad.safetensors', ['one', 'two'], [a], status=st)
        call assert_true(st /= 0, 'two names for one array are refused with a status')
        call mlx_save_safetensors('mlxf_io_bad.safetensors', ['one', 'one'], [a, a], status=st)
        call assert_true(st /= 0, 'a name given twice is refused with a status')
        call assert_true(index(mlx_last_error(), 'twice') > 0, 'that says so')
        call mlx_save_safetensors('mlxf_io_bad.safetensors', ['one'], [a], metadata=triple, status=st)
        call assert_true(st /= 0, 'metadata that are not pairs are refused with a status')
        call mlx_save_gguf('mlxf_io_bad.gguf', ['one', 'one'], [a, a], status=st)
        call assert_true(st /= 0, 'and so it is for GGUF')
        inquire(file='mlxf_io_bad.safetensors', exist=there)
        call assert_true(.not. there, 'the refused save wrote no file')
        call remove('mlxf_io_bad.safetensors')
        call remove('mlxf_io_bad.gguf')
        call mlx_export_to_dot('mlxf_no_such_directory/g.dot', [a], status=st)
        call assert_true(st /= 0, 'a graph file that cannot be opened is refused with a status')
        call assert_int(live0, mlx_live_count(), 'the refusals leave no live handle')
        call mlx_save('mlxf_io_after', a, status=st)
        call assert_int(0, st, 'MLX remains usable, and a name without .npy is saved')
        r = mlx_load('mlxf_io_after.npy', status=st)
        call assert_int(0, st, 'under that name with .npy added')
        call remove('mlxf_io_after.npy')
    end subroutine test_failures

    ! the bytes of an element, of an array and of the buffers arrays hold
    subroutine test_sizes
        type(mlx_array) :: a, b, c
        real(real32)    :: x(5, 3)
        integer(int16)  :: n(7)
        integer         :: st
        integer(int64)  :: bytes, first, second
        write(*,'(a)') 'test_sizes'
        x = 1._real32
        n = 3_int16
        a = mlx_from(x)
        b = mlx_from(n)
        call assert_int(4, a%itemsize(), 'a float32 element is 4 bytes')
        call assert_true(a%nbytes() == 60_int64, 'a (5, 3) float32 array is 60 bytes')
        call assert_int(2, b%itemsize(), 'an int16 element is 2 bytes')
        call assert_true(b%nbytes() == 14_int64, 'an int16 array of 7 is 14 bytes')
        c = mlx_astype(a, MLX_DTYPES%complex64)
        call assert_int(8, c%itemsize(), 'a complex64 element is 8 bytes')
        call assert_true(c%nbytes() == 120_int64, 'a (5, 3) complex64 array is 120 bytes')
        bytes = mlx_buffer_size([a, b], status=st)
        call assert_int(0, st, 'the buffers of two arrays are sized')
        call assert_true(bytes >= 74_int64, 'and hold at least the arrays'' 60 and 14 bytes')
        first = mlx_buffer_size([a], status=st)
        second = mlx_buffer_size([b], status=st)
        call assert_true(bytes == first+second, 'the size of two arrays'' buffers is the sum of each one''s')
        bytes = mlx_buffer_size([c], status=st)
        call assert_int(0, st, 'an array not yet evaluated is evaluated first')
        call assert_true(bytes >= 120_int64, 'and its buffer holds at least its 120 bytes')
    end subroutine test_sizes

    ! the text of a graph names its operations, and the dot form is a digraph
    subroutine test_graph_text
        type(mlx_array)               :: a, b, c
        real(real32)                  :: x(3)
        integer                       :: st
        character(len=:), allocatable :: text
        character(len=*), parameter   :: TEXT_FILE = 'mlxf_io_graph.txt', DOT_FILE = 'mlxf_io_graph.dot'
        write(*,'(a)') 'test_graph_text'
        x = 2._real32
        a = mlx_from(x)
        b = a*a
        c = b+a
        call mlx_print_graph([c], file=TEXT_FILE, status=st)
        call assert_int(0, st, 'the graph of an expression is written as text')
        text = contents(TEXT_FILE)
        call assert_true(index(text, 'Multiply') > 0, 'the text names the product')
        call assert_true(index(text, 'Add') > 0, 'and the sum')
        call assert_int(0, index(text, 'digraph'), 'and is not the dot form')
        call mlx_export_to_dot(DOT_FILE, [c], status=st)
        call assert_int(0, st, 'the graph is written in dot')
        text = contents(DOT_FILE)
        call assert_true(index(text, 'digraph') > 0, 'the dot file holds a digraph')
        call assert_true(index(text, 'Multiply') > 0, 'that names the product')
        call mlx_print_graph([c], status=st)
        call assert_int(0, st, 'without a file the graph goes to the standard output')
        call remove(TEXT_FILE)
        call remove(DOT_FILE)
    end subroutine test_graph_text

    ! the whole text of a file (empty when it cannot be read)
    function contents( file ) result(text)
        character(len=*), intent(in) :: file
        character(len=:), allocatable :: text
        integer                       :: unit, n, io
        text = ''
        open(newunit=unit, file=file, access='stream', form='unformatted', status='old', action='read', iostat=io)
        if( io /= 0 ) return
        inquire(unit=unit, size=n)
        text = repeat(' ', n)
        read(unit, iostat=io) text
        close(unit)
    end function contents

    ! deletes a file the test wrote, if it exists
    subroutine remove( file )
        character(len=*), intent(in) :: file
        integer :: unit, st
        logical :: there
        inquire(file=file, exist=there)
        if( .not. there ) return
        open(newunit=unit, file=file, status='old', iostat=st)
        if( st == 0 ) close(unit, status='delete', iostat=st)
    end subroutine remove

end module mlxf_io_tester
