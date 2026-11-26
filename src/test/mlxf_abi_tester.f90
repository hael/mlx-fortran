!@descr: the ABI probe: every argument and result class of the generated bind(c) layer echoed by C, and the C layouts
! The probe's interfaces are generated with the library's mapping table (scripts/gen_mlxc_bindings.py --probe) and
! its functions compiled by Apple's clang (src/test/mlxf_abi_probe.c): a type or passing mode the table maps
! differently from C reads back something else. The structs' sizes, alignments and field offsets and the
! enumerators' values are compared with C's by name. No MLX call: it runs in every session.
module mlxf_abi_tester
use, intrinsic :: iso_c_binding, only: c_int, c_int8_t, c_int16_t, c_int32_t, c_int64_t, c_intptr_t, c_size_t, c_bool, &
                                       c_float, c_double, c_float_complex, c_char, c_ptr, c_funptr, c_null_char, &
                                       c_null_ptr, c_loc, c_funloc, c_associated, c_f_pointer
use mlxf_c_types,     only: mlxc_array, mlxc_map_string_to_array_iterator, mlxc_optional_int, mlxc_optional_float, &
                            mlxc_optional_dtype, MLXC_COMPLEX64, MLXC_FLOAT16
use mlxf_c_abi_probe, only: mlxc_abiprobe_int, mlxc_abiprobe_bool, mlxc_abiprobe_float, mlxc_abiprobe_double, &
                            mlxc_abiprobe_size, mlxc_abiprobe_uint64, mlxc_abiprobe_uintptr, mlxc_abiprobe_dtype, &
                            mlxc_abiprobe_optional_int, mlxc_abiprobe_optional_float, mlxc_abiprobe_optional_dtype, &
                            mlxc_abiprobe_stack, mlxc_abiprobe_stack_optional, mlxc_abiprobe_refs, mlxc_abiprobe_urefs, &
                            mlxc_abiprobe_int_array, mlxc_abiprobe_int64_arrays, mlxc_abiprobe_handle, &
                            mlxc_abiprobe_handle_ref, mlxc_abiprobe_handles, mlxc_abiprobe_iterator, &
                            mlxc_abiprobe_iterator_echo, mlxc_abiprobe_pointer, mlxc_abiprobe_pointer_ref, &
                            mlxc_abiprobe_file, mlxc_abiprobe_int_result, mlxc_abiprobe_chars, mlxc_abiprobe_strlen, &
                            mlxc_abiprobe_string, mlxc_abiprobe_funptr, mlxc_abiprobe_size_result, &
                            mlxc_abiprobe_bool_result, mlxc_abiprobe_void, mlxc_abiprobe_struct_layout, &
                            mlxc_abiprobe_enum_value, mlxf_abi_struct_layout, mlxf_abi_enumerator, MLXF_ABI_NSTRUCTS, &
                            MLXF_ABI_NENUMS
use mlxf_test_utils,  only: assert_true
implicit none
private

public :: run_all_abi_tests

contains

    subroutine run_all_abi_tests
        write(*,'(a)') '**** running all abi tests ****'
        call test_scalars
        call test_optional_pairs
        call test_stack
        call test_references
        call test_arrays
        call test_handles
        call test_pointers
        call test_results
        call test_layouts
    end subroutine run_all_abi_tests

    ! int, bool, float, double, size_t, uint64_t, uintptr_t and an enum by value in a register, back by reference
    subroutine test_scalars
        integer(c_int)            :: i
        logical(c_bool)           :: b1, b2
        real(c_float)             :: f
        real(c_double)            :: d
        integer(c_size_t)         :: z
        integer(c_int64_t)        :: u
        integer(c_int), target    :: x
        type(c_ptr)               :: p
        integer(c_int)            :: e, st(9)
        write(*,'(a)') 'test_scalars'
        b1    = .false.
        b2    = .true.
        st(1) = mlxc_abiprobe_int(i, -123456789_c_int)
        st(2) = mlxc_abiprobe_bool(b1, .true._c_bool)
        st(3) = mlxc_abiprobe_bool(b2, .false._c_bool)
        st(4) = mlxc_abiprobe_float(f, 1.25e-3_c_float)
        st(5) = mlxc_abiprobe_double(d, -3.25e-9_c_double)
        st(6) = mlxc_abiprobe_size(z, 2_c_size_t**40 + 3)
        st(7) = mlxc_abiprobe_uint64(u, 2_c_int64_t**62 + 5)
        st(8) = mlxc_abiprobe_uintptr(p, transfer(c_loc(x), 0_c_intptr_t))
        st(9) = mlxc_abiprobe_dtype(e, MLXC_COMPLEX64)
        call assert_true(all(st == 0), 'the scalar probes return 0')
        call assert_true(i == -123456789_c_int, 'an int by value reaches C and comes back by reference')
        call assert_true(logical(b1 .and. .not. b2), 'a bool by value, both values, by reference')
        call assert_true(transfer(f, 0_c_int32_t) == transfer(1.25e-3_c_float, 0_c_int32_t), 'a float by value, bit for bit')
        call assert_true(transfer(d, 0_c_int64_t) == transfer(-3.25e-9_c_double, 0_c_int64_t), &
            &'a double by value, bit for bit')
        call assert_true(z == 2_c_size_t**40 + 3, 'a size_t by value above 32 bits')
        call assert_true(u == 2_c_int64_t**62 + 5, 'a uint64_t by value above 32 bits')
        call assert_true(c_associated(p, c_loc(x)), 'a uintptr_t by value comes back as the address it holds')
        call assert_true(e == MLXC_COMPLEX64, 'an enum by value and by reference')
    end subroutine test_scalars

    ! the three optional pairs by value in a register and back through a pointer to the struct
    subroutine test_optional_pairs
        type(mlxc_optional_int)   :: oi
        type(mlxc_optional_float) :: of
        type(mlxc_optional_dtype) :: od
        integer(c_int)            :: st(3)
        write(*,'(a)') 'test_optional_pairs'
        st(1) = mlxc_abiprobe_optional_int(oi, mlxc_optional_int(-77_c_int, .true._c_bool))
        st(2) = mlxc_abiprobe_optional_float(of, mlxc_optional_float(6.5_c_float, .true._c_bool))
        st(3) = mlxc_abiprobe_optional_dtype(od, mlxc_optional_dtype(MLXC_FLOAT16, .false._c_bool))
        call assert_true(all(st == 0), 'the optional-pair probes return 0')
        call assert_true(oi%value == -77_c_int .and. oi%has_value, 'mlx_optional_int by value: its value and its flag')
        call assert_true(transfer(of%value, 0_c_int32_t) == transfer(6.5_c_float, 0_c_int32_t) .and. of%has_value, &
            &'mlx_optional_float by value: its value and its flag')
        call assert_true(od%value == MLXC_FLOAT16 .and. .not. od%has_value, &
            &'mlx_optional_dtype by value: its value and its flag')
    end subroutine test_optional_pairs

    ! after eight integer-class and eight floating-point arguments the rest go on the stack, packed by their size
    subroutine test_stack
        integer(c_int)            :: i
        logical(c_bool)           :: b
        real(c_float)             :: f
        real(c_double)            :: d
        type(mlxc_optional_int)   :: oi
        type(mlxc_optional_float) :: of
        type(mlxc_optional_dtype) :: od
        integer(c_int)            :: st
        write(*,'(a)') 'test_stack'
        b  = .false.
        st = mlxc_abiprobe_stack(i, b, f, d, 1_c_int, 2_c_int, 3_c_int, 4_c_int, 1.5_c_double, 2.5_c_double, &
            &3.5_c_double, 4.5_c_double, 5.5_c_double, 6.5_c_double, 7.5_c_double, 8.5_c_double, .true._c_bool, -31_c_int, &
            &2.5e7_c_float, -3.25e-9_c_double)
        call assert_true(st == 0, 'the eight integer and eight floating-point fillers arrive in their registers')
        call assert_true(b .and. i == -31_c_int .and. transfer(f, 0_c_int32_t) == transfer(2.5e7_c_float, 0_c_int32_t) .and. &
            &transfer(d, 0_c_int64_t) == transfer(-3.25e-9_c_double, 0_c_int64_t), &
            &'a bool, an int, a float and a double on the stack, packed, arrive whole')
        st = mlxc_abiprobe_stack_optional(oi, of, od, 1_c_int, 2_c_int, 3_c_int, 4_c_int, 5_c_int, &
            &mlxc_optional_int(41_c_int, .true._c_bool), mlxc_optional_float(-0.75_c_float, .true._c_bool), &
            &mlxc_optional_dtype(MLXC_COMPLEX64, .true._c_bool))
        call assert_true(st == 0 .and. oi%value == 41_c_int .and. oi%has_value .and. of%has_value .and. &
            &transfer(of%value, 0_c_int32_t) == transfer(-0.75_c_float, 0_c_int32_t) .and. od%value == MLXC_COMPLEX64 .and. &
            &od%has_value, 'the three optional pairs on the stack arrive whole')
    end subroutine test_stack

    ! pointers to int8 to int64 (signed and unsigned), float, double and complex64: C doubles each value
    subroutine test_references
        integer(c_int8_t)        :: a8, u8
        integer(c_int16_t)       :: a16, u16
        integer(c_int32_t)       :: a32, u32
        integer(c_int64_t)       :: a64, u64
        real(c_float)            :: f
        real(c_double)           :: d
        complex(c_float_complex) :: z
        integer(c_int)           :: st
        write(*,'(a)') 'test_references'
        a8  = -21_c_int8_t
        a16 = -3000_c_int16_t
        a32 = -200000000_c_int32_t
        a64 = -2_c_int64_t**40
        f   = 1.5_c_float
        d   = 2.25_c_double
        z   = (1.5_c_float, -2.0_c_float)
        st  = mlxc_abiprobe_refs(a8, a16, a32, a64, f, d, z)
        call assert_true(st == 0 .and. a8 == -42_c_int8_t .and. a16 == -6000_c_int16_t .and. a32 == -400000000_c_int32_t &
            &.and. a64 == -2_c_int64_t**41, 'int8_t, int16_t, int32_t and int64_t by reference')
        call assert_true(transfer(f, 0_c_int32_t) == transfer(3.0_c_float, 0_c_int32_t) .and. &
            &transfer(d, 0_c_int64_t) == transfer(4.5_c_double, 0_c_int64_t), 'float and double by reference')
        call assert_true(transfer(z, 0_c_int64_t) == transfer((3.0_c_float, -4.0_c_float), 0_c_int64_t), &
            &'complex64 by reference, both parts')
        u8  = 50_c_int8_t
        u16 = 1000_c_int16_t
        u32 = 100000000_c_int32_t
        u64 = 10_c_int64_t**12
        st  = mlxc_abiprobe_urefs(u8, u16, u32, u64)
        call assert_true(st == 0 .and. u8 == 100_c_int8_t .and. u16 == 2000_c_int16_t .and. u32 == 200000000_c_int32_t &
            &.and. u64 == 2_c_int64_t * 10_c_int64_t**12, 'uint8_t, uint16_t, uint32_t and uint64_t by reference')
    end subroutine test_references

    ! arrays the callee reads: const int*, const int64_t* and const uint64_t*, with their length by value
    subroutine test_arrays
        integer(c_int)     :: s
        integer(c_int64_t) :: s64
        integer(c_int)     :: st(2)
        write(*,'(a)') 'test_arrays'
        st(1) = mlxc_abiprobe_int_array(s, [3_c_int, -1_c_int, 4_c_int, 1_c_int, 5_c_int], 5_c_size_t)
        st(2) = mlxc_abiprobe_int64_arrays(s64, [2_c_int64_t**33, -5_c_int64_t], [7_c_int64_t, 2_c_int64_t**34], 2_c_size_t)
        call assert_true(all(st == 0), 'the array probes return 0')
        call assert_true(s == 42_c_int, 'a const int array is read element by element')
        call assert_true(s64 == 2_c_int64_t**33 - 3_c_int64_t + 2_c_int64_t**35, &
            &'const int64_t and const uint64_t arrays are read element by element')
    end subroutine test_arrays

    ! a handle by value, by reference, in an array and as a result; the two-pointer iterator by value and as result.
    ! The handles hold addresses C never dereferences, not addresses of local variables: once such an address has
    ! been passed inside an intent(in) array, the optimizer may fold a later comparison with it
    subroutine test_handles
        type(mlxc_array)                        :: h, r
        type(mlxc_array)                        :: hs(3)
        type(mlxc_map_string_to_array_iterator) :: it
        type(c_ptr)                             :: p, q, a1, a2, a3
        integer(c_int)                          :: st
        write(*,'(a)') 'test_handles'
        a1 = transfer(int(z'10000', c_intptr_t), a1)
        a2 = transfer(int(z'20000', c_intptr_t), a2)
        a3 = transfer(int(z'30000', c_intptr_t), a3)
        h%ctx = a1
        r = mlxc_abiprobe_handle(h)
        call assert_true(c_associated(r%ctx, a1), 'a handle by value comes back as a handle result')
        r%ctx = a2
        st    = mlxc_abiprobe_handle_ref(r, h)
        call assert_true(st == 0 .and. c_associated(r%ctx, a1), 'a handle by reference')
        hs(1)%ctx = a1
        hs(2)%ctx = a2
        hs(3)%ctx = a3
        st = mlxc_abiprobe_handles(r, hs, 3_c_size_t)
        call assert_true(st == 0 .and. c_associated(r%ctx, a3), 'an array of handles: C reads the last one')
        it = mlxc_abiprobe_iterator(a1, a2)
        call assert_true(c_associated(it%ctx, a1) .and. c_associated(it%map_ctx, a2), &
            &'a two-pointer struct as a result: both pointers')
        st = mlxc_abiprobe_iterator_echo(p, q, it)
        call assert_true(st == 0 .and. c_associated(p, a1) .and. c_associated(q, a2), &
            &'a two-pointer struct by value: both pointers')
    end subroutine test_handles

    ! void* by value and as result, void** and char** by reference, const char*, a function pointer
    subroutine test_pointers
        integer(c_int), target          :: x
        type(c_ptr)                     :: p
        integer(c_size_t)               :: n
        integer(c_int)                  :: r
        character(kind=c_char), pointer :: s(:)
        character(kind=c_char), target  :: word(9)
        type(c_ptr)                     :: q
        integer(c_int)                  :: st
        write(*,'(a)') 'test_pointers'
        word = transfer('abi probe', word)
        p = mlxc_abiprobe_pointer(c_loc(x))
        call assert_true(c_associated(p, c_loc(x)), 'a void* by value comes back as result')
        st = mlxc_abiprobe_pointer_ref(p, c_loc(x))
        call assert_true(st == 0 .and. c_associated(p, c_loc(x)), 'a void** by reference')
        st = mlxc_abiprobe_file(p, c_loc(x))
        call assert_true(st == 0 .and. c_associated(p, c_loc(x)), 'a FILE* by value')
        st = mlxc_abiprobe_strlen(n, 'abi probe'//c_null_char)
        call assert_true(st == 0 .and. n == 9_c_size_t, 'a const char* reaches C as a NUL-terminated string')
        st = mlxc_abiprobe_string(p, 1_c_int)
        call assert_true(st == 0 .and. c_associated(p), 'a char** by reference is set')
        if( c_associated(p) )then
            call c_f_pointer(p, s, [9])
            call assert_true(all(s == transfer('abi probe', s)), 'the char** points at C''s string')
        endif
        q  = c_null_ptr
        st = mlxc_abiprobe_chars(q, c_loc(word))
        call assert_true(st == 0 .and. c_associated(q, c_loc(word(5))), 'a char** by reference and a char* by value')
        st = mlxc_abiprobe_funptr(r, c_funloc(abi_triple), 14_c_int)
        call assert_true(st == 0 .and. r == 42_c_int, 'a function pointer by value: C calls the Fortran procedure with its argument')
    end subroutine test_pointers

    ! size_t and bool results, and a function without a result
    subroutine test_results
        integer(c_int)    :: r, i
        integer(c_size_t) :: z
        logical(c_bool)   :: b1, b2
        write(*,'(a)') 'test_results'
        i = mlxc_abiprobe_int_result(-123456789_c_int)
        call assert_true(i == -123456789_c_int, 'an int result, negative and above 16 bits')
        z = mlxc_abiprobe_size_result(2_c_size_t**41)
        call assert_true(z == 2_c_size_t**41 + 1, 'a size_t result above 32 bits')
        b1 = mlxc_abiprobe_bool_result(.false._c_bool)
        b2 = mlxc_abiprobe_bool_result(.true._c_bool)
        call assert_true(logical(b1 .and. .not. b2), 'a bool result, both values')
        r = 0
        call mlxc_abiprobe_void(r, 6_c_int)
        call assert_true(r == 7_c_int, 'a function without a result, called as a subroutine')
    end subroutine test_results

    ! every bind(c) struct's size, alignment, field offsets and sizes, and every enumerator's value, against C's
    subroutine test_layouts
        character(len=64) :: name
        integer(c_size_t) :: size, align, fields(4), csize, calign, c(4)
        integer(c_int)    :: value, cvalue, st
        integer           :: k, nstruct, nenum
        write(*,'(a)') 'test_layouts'
        nstruct = 0
        do k = 1, MLXF_ABI_NSTRUCTS
            call mlxf_abi_struct_layout(k, name, size, align, fields)
            st = mlxc_abiprobe_struct_layout(trim(name)//c_null_char, csize, calign, c(1), c(2), c(3), c(4))
            if( st /= 0 )then
                call assert_true(.false., trim(name)//': C knows the struct (add it to src/test/mlxf_abi_probe.c)')
                cycle
            endif
            call assert_true(size == csize .and. align == calign .and. all(fields == c), &
                &trim(name)//': size, alignment, field offsets and field sizes equal C''s')
            nstruct = nstruct + 1
        end do
        nenum = 0
        do k = 1, MLXF_ABI_NENUMS
            call mlxf_abi_enumerator(k, name, value)
            cvalue = -1
            st     = mlxc_abiprobe_enum_value(trim(name)//c_null_char, cvalue)
            call assert_true(st == 0 .and. value == cvalue, trim(name)//': the enumerator has C''s value')
            nenum = nenum + 1
        end do
        write(*,'(a,i0,a,i0,a)') '    ', nstruct, ' structs and ', nenum, ' enumerators against C'
    end subroutine test_layouts

    ! the procedure C calls through the function pointer: three times its argument
    integer(c_int) function abi_triple( v ) bind(c)
        integer(c_int), value :: v
        abi_triple = 3_c_int * v
    end function abi_triple

end module mlxf_abi_tester
