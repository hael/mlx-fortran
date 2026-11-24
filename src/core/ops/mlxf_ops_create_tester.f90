!@descr: table-driven two-device checks of the constructors: ones, full and the *_like family
! Every constructor builds a Fortran (3, 4) array whose shape, kind and values are exact; a fill value's kind
! and the dtype argument decide the result's kind, and an array fill broadcasts with leading dimensions aligned.
module mlxf_ops_create_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                           MLX_DTYPES, mlx_astype, mlx_ones, mlx_full, mlx_zeros_like, mlx_ones_like, mlx_full_like
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name
implicit none
private
public :: run_all_ops_create_tests

abstract interface
    function constructor( like ) result(r)
        import :: mlx_array
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
    end function constructor
end interface

! a constructor, the value every element must hold and the kind of the result
type :: create_case
    character(len=32)                       :: label = ''
    procedure(constructor), pointer, nopass :: f     => null()
    real(real64)                            :: value = 0._real64
    integer                                 :: dtype = 0
end type create_case

contains

    subroutine run_all_ops_create_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops_create tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_constructor_family
            call test_create_conventions
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_create_tests

    ! every constructor: a Fortran (3, 4) result of the expected kind holding the expected value everywhere
    subroutine test_constructor_family
        type(create_case) :: cases(16)
        type(mlx_array)   :: like, r, f
        real(real32)      :: y(3, 4)
        integer           :: c
        write(*,'(a)') 'test_constructor_family'
        cases(1)  = create_case('mlx_ones', c_ones, 1._real64, MLX_DTYPES%float32)
        cases(2)  = create_case('mlx_ones(dtype)', c_ones_int32, 1._real64, MLX_DTYPES%int32)
        cases(3)  = create_case('mlx_full(real32)', c_full_s, 2.5_real64, MLX_DTYPES%float32)
        cases(4)  = create_case('mlx_full(real64)', c_full_d, 2.5_real64, MLX_DTYPES%float32)
        cases(5)  = create_case('mlx_full(integer)', c_full_i, 7._real64, MLX_DTYPES%int32)
        cases(6)  = create_case('mlx_full(real32, dtype)', c_full_dtype, 2._real64, MLX_DTYPES%int32)
        cases(7)  = create_case('mlx_full(array)', c_full_array, -1.5_real64, MLX_DTYPES%float32)
        cases(8)  = create_case('mlx_zeros_like', c_zeros_like, 0._real64, MLX_DTYPES%float32)
        cases(9)  = create_case('mlx_zeros_like(dtype)', c_zeros_like_int32, 0._real64, MLX_DTYPES%int32)
        cases(10) = create_case('mlx_ones_like', c_ones_like, 1._real64, MLX_DTYPES%float32)
        cases(11) = create_case('mlx_ones_like(dtype)', c_ones_like_int64, 1._real64, MLX_DTYPES%int64)
        cases(12) = create_case('mlx_full_like(real32)', c_full_like_s, 3.25_real64, MLX_DTYPES%float32)
        cases(13) = create_case('mlx_full_like(real64)', c_full_like_d, 3.25_real64, MLX_DTYPES%float32)
        cases(14) = create_case('mlx_full_like(integer)', c_full_like_i, 4._real64, MLX_DTYPES%float32)
        cases(15) = create_case('mlx_full_like(integer, dtype)', c_full_like_dtype, 4._real64, MLX_DTYPES%int64)
        cases(16) = create_case('mlx_full_like(array)', c_full_like_array, -2._real64, MLX_DTYPES%float32)
        like = mlx_from(reshape([(real(c, real32), c = 1, 12)], [3, 4]))
        do c = 1, size(cases)
            r = cases(c)%f(like)
            call assert_true(all(r%shape() == [3, 4]), trim(cases(c)%label)//' has Fortran shape (3, 4)')
            call assert_int(cases(c)%dtype, r%kind(), trim(cases(c)%label)//' has the expected kind')
            f = mlx_astype(r, MLX_DTYPES%float32)
            call mlx_to(y, f)
            call assert_true(all(abs(real(y, real64)-cases(c)%value) <= 0._real64), &
                &trim(cases(c)%label)//' holds its fill value everywhere')
        end do
    end subroutine test_constructor_family

    ! an array fill broadcasts along the trailing Fortran dimensions; float64 fills on the CPU keep a real32
    ! value's rounding and a real64 value's bits
    subroutine test_create_conventions
        type(mlx_array) :: v, r
        real(real32)    :: y(3, 4)
        real(real64)    :: z(2)
        integer         :: j
        write(*,'(a)') 'test_create_conventions'
        v = mlx_from([1._real32, 2._real32, 3._real32])
        r = mlx_full([3, 4], v)
        call mlx_to(y, r)
        call assert_true(all([(all(abs(y(:, j)-[1._real32, 2._real32, 3._real32]) <= 0._real32), j = 1, 4)]), &
            &'mlx_full broadcasts a (3) fill along dimension 2 of a (3, 4) array: r(i, j) = v(i)')
        if( mlx_default_device() /= MLX_DEVICES%cpu ) return
        r = mlx_full([2], 0.1_real64, dtype=MLX_DTYPES%float64)
        call assert_int(MLX_DTYPES%float64, r%kind(), 'mlx_full(real64, dtype=float64) is float64')
        call mlx_to(z, r)
        call assert_true(all(abs(z-0.1_real64) <= 0._real64), 'a float64 fill keeps a real64 value''s bits')
        r = mlx_full([2], 0.1_real32, dtype=MLX_DTYPES%float64)
        call mlx_to(z, r)
        call assert_true(all(abs(z-real(0.1_real32, real64)) <= 0._real64), &
            &'a float64 fill from a real32 value keeps its real32 rounding')
    end subroutine test_create_conventions

    function c_ones( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_ones(like%shape())
    end function c_ones

    function c_ones_int32( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_ones(like%shape(), dtype=MLX_DTYPES%int32)
    end function c_ones_int32

    function c_full_s( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full(like%shape(), 2.5_real32)
    end function c_full_s

    function c_full_d( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full(like%shape(), 2.5_real64)
    end function c_full_d

    function c_full_i( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full(like%shape(), 7)
    end function c_full_i

    function c_full_dtype( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full(like%shape(), 2.5_real32, dtype=MLX_DTYPES%int32)
    end function c_full_dtype

    function c_full_array( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        type(mlx_array) :: v
        v = mlx_from(-1.5_real32)
        r = mlx_full(like%shape(), v)
    end function c_full_array

    function c_zeros_like( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_zeros_like(like)
    end function c_zeros_like

    function c_zeros_like_int32( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_zeros_like(like, dtype=MLX_DTYPES%int32)
    end function c_zeros_like_int32

    function c_ones_like( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_ones_like(like)
    end function c_ones_like

    function c_ones_like_int64( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_ones_like(like, dtype=MLX_DTYPES%int64)
    end function c_ones_like_int64

    function c_full_like_s( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full_like(like, 3.25_real32)
    end function c_full_like_s

    function c_full_like_d( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full_like(like, 3.25_real64)
    end function c_full_like_d

    function c_full_like_i( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full_like(like, 4)
    end function c_full_like_i

    function c_full_like_dtype( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        r = mlx_full_like(like, 4, dtype=MLX_DTYPES%int64)
    end function c_full_like_dtype

    function c_full_like_array( like ) result(r)
        type(mlx_array), intent(in) :: like
        type(mlx_array) :: r
        type(mlx_array) :: v
        v = mlx_from(-2._real32)
        r = mlx_full_like(like, v)
    end function c_full_like_array

end module mlxf_ops_create_tester
