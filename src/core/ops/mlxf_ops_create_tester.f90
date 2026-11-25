!@descr: table-driven two-device checks of the constructors: ones, fills, the *_like family, matrices, grids, windows
! Every constructor builds an array whose shape, kind and values are exact; a fill value's kind and the dtype
! argument decide the result's kind, and an array fill broadcasts with leading dimensions aligned. linspace and
! the windows are judged against real64 formulas by the frozen tolerances of mlxf_test_defs.
module mlxf_ops_create_tester
use, intrinsic :: iso_fortran_env, only: real32, real64
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                            MLX_DTYPES, mlx_astype, mlx_ones, mlx_full, mlx_zeros_like, mlx_ones_like, mlx_full_like, &
                            mlx_identity, mlx_eye, mlx_tri, mlx_linspace, mlx_meshgrid, mlx_bartlett, mlx_blackman, &
                            mlx_hamming, mlx_hanning
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name
use mlxf_test_defs,   only: ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED, REDUCE_TOLERANCES, elem_tolerance
use mlxf_test_reduce, only: nan_maxval
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
            call test_matrices
            call test_meshgrid
            call test_spaced_values
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

    ! whether r is rank 1 with n elements
    logical function is_vector( r, n )
        type(mlx_array), intent(in) :: r
        integer,         intent(in) :: n
        is_vector = r%ndim() == 1
        if( is_vector ) is_vector = r%size() == n
    end function is_vector

    ! whether r has Fortran shape wshape and, in array element order, the values want
    logical function holds( r, wshape, want )
        type(mlx_array), intent(in) :: r
        integer,         intent(in) :: wshape(:)
        real(real32),    intent(in) :: want(:)
        type(mlx_array)      :: f
        real(real32)         :: y(size(want))
        integer, allocatable :: got(:)
        got = r%shape()
        holds = size(got) == size(wshape)
        if( holds ) holds = all(got == wshape)
        if( .not. holds ) return
        f = mlx_astype(r, MLX_DTYPES%float32)
        call mlx_to(y, f)
        holds = all(abs(y-want) <= 0._real32)
    end function holds

    ! identity, eye and tri in the Fortran view: k > 0 is above the main diagonal, elements (i, i + k)
    subroutine test_matrices
        type(mlx_array) :: r
        real(real32)    :: e(3, 4), t(3, 4), sq(3, 3)
        integer         :: i, j, k
        write(*,'(a)') 'test_matrices'
        do j = 1, 3
            do i = 1, 3
                sq(i, j) = merge(1._real32, 0._real32, i == j)
            end do
        end do
        r = mlx_identity(3)
        call assert_true(holds(r, [3, 3], reshape(sq, [9])), 'mlx_identity(n) is the n by n identity')
        call assert_int(MLX_DTYPES%float32, r%kind(), 'mlx_identity is float32 by default')
        r = mlx_identity(3, dtype=MLX_DTYPES%int32)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_identity(dtype) has the dtype asked for')
        r = mlx_eye(3)
        call assert_true(holds(r, [3, 3], reshape(sq, [9])), 'mlx_eye(n) is the n by n identity')
        do k = -1, 2
            do j = 1, 4
                do i = 1, 3
                    e(i, j) = merge(1._real32, 0._real32, j == i+k)
                    t(i, j) = merge(1._real32, 0._real32, j <= i+k)
                end do
            end do
            r = mlx_eye(3, 4, k)
            call assert_true(holds(r, [3, 4], reshape(e, [12])), 'mlx_eye(n, m, k) is (n, m) with ones at (i, i + k)')
            r = mlx_tri(3, 4, k)
            call assert_true(holds(r, [3, 4], reshape(t, [12])), 'mlx_tri(n, m, k) is (n, m) with ones where j <= i + k')
        end do
        r = mlx_eye(3, k=1)
        call assert_true(holds(r, [3, 3], [0._real32, 0._real32, 0._real32, 1._real32, 0._real32, 0._real32, 0._real32, &
            &1._real32, 0._real32]), 'mlx_eye(n, k=1) is square with ones at (i, i + 1)')
        r = mlx_eye(3, 4, dtype=MLX_DTYPES%int32)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_eye(dtype) has the dtype asked for')
        r = mlx_tri(3)
        call assert_true(holds(r, [3, 3], [1._real32, 1._real32, 1._real32, 0._real32, 1._real32, 1._real32, 0._real32, &
            &0._real32, 1._real32]), 'mlx_tri(n) is the lower triangle of ones of a Fortran matrix')
        r = mlx_tri(2, 3, dtype=MLX_DTYPES%int32)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_tri(dtype) has the dtype asked for')
    end subroutine test_matrices

    ! matrix indexing in the Fortran view: grid i has shape (n1, ..., nk) and varies along dimension i
    subroutine test_meshgrid
        type(mlx_array)              :: u, v, w
        type(mlx_array), allocatable :: grids(:)
        real(real32)                 :: x(2), y(3), z(4), g(2, 3, 4)
        integer                      :: i, j, k
        logical                      :: ok
        write(*,'(a)') 'test_meshgrid'
        x = [1._real32, 2._real32]
        y = [10._real32, 20._real32, 30._real32]
        z = [100._real32, 200._real32, 300._real32, 400._real32]
        u = mlx_from(x)
        v = mlx_from(y)
        w = mlx_from(z)
        call mlx_meshgrid([u, v], grids)
        ok = size(grids) == 2
        call assert_true(ok, 'mlx_meshgrid returns one grid per array')
        if( ok )then
            call assert_true(holds(grids(1), [2, 3], [((x(i), i=1, 2), j=1, 3)]), &
                &'mlx_meshgrid: the first grid has shape (n1, n2) and varies along dimension 1')
            call assert_true(holds(grids(2), [2, 3], [((y(j), i=1, 2), j=1, 3)]), &
                &'mlx_meshgrid: the second grid varies along dimension 2')
        endif
        call mlx_meshgrid([u, v, w], grids)
        ok = size(grids) == 3
        call assert_true(ok, 'mlx_meshgrid of three arrays returns three grids')
        if( ok )then
            do k = 1, 4
                do j = 1, 3
                    do i = 1, 2
                        g(i, j, k) = z(k)
                    end do
                end do
            end do
            call assert_true(holds(grids(3), [2, 3, 4], reshape(g, [24])), 'mlx_meshgrid: the third grid varies along dimension 3')
            call assert_true(holds(grids(1), [2, 3, 4], [(x, i=1, 12)]), 'mlx_meshgrid: the first of three grids varies along dimension 1')
        endif
        call mlx_meshgrid([u, v, w], grids, sparse=.true.)
        ok = size(grids) == 3
        call assert_true(ok, 'a sparse mlx_meshgrid returns three grids')
        if( ok )then
            call assert_true(holds(grids(1), [2, 1, 1], x), 'a sparse grid has extent 1 outside its dimension: (n1, 1, 1)')
            call assert_true(holds(grids(2), [1, 3, 1], y), 'the second sparse grid has shape (1, n2, 1)')
            call assert_true(holds(grids(3), [1, 1, 4], z), 'the third sparse grid has shape (1, 1, n3)')
        endif
    end subroutine test_meshgrid

    ! the frozen tolerance of a function (zero, failing every check, when it has none)
    function tolerance_of( name ) result(t)
        character(len=*), intent(in) :: name
        type(elem_tolerance) :: t
        integer              :: k
        t = elem_tolerance(name, 0._real64, 0._real64)
        do k = 1, size(REDUCE_TOLERANCES)
            if( trim(REDUCE_TOLERANCES(k)%name) == trim(name) ) t = REDUCE_TOLERANCES(k)
        end do
    end function tolerance_of

    ! r against ref, the error relative to max(1, |ref|) printed in float32 epsilons and judged by tol
    subroutine judge( r, ref, tol, label )
        type(mlx_array),  intent(in) :: r
        real(real64),     intent(in) :: ref(:), tol
        character(len=*), intent(in) :: label
        real(real32), allocatable :: y32(:)
        real(real64), allocatable :: y(:)
        real(real64)              :: err
        character(len=160)        :: line
        err = huge(1._real64)
        if( r%size() == size(ref) )then
            allocate(y(size(ref)))
            if( r%kind() == MLX_DTYPES%float64 )then
                call mlx_to(y, r)
            else
                allocate(y32(size(ref)))
                call mlx_to(y32, r)
                y = real(y32, real64)
            endif
            err = nan_maxval(abs(y-ref)/max(1._real64, abs(ref)))
        endif
        write(line,'(A,ES16.9,A,F8.3,A)') '    error '//trim(label)//' '//device_name(mlx_default_device())//': ', err, &
            &' (', err/real(epsilon(1._real32), real64), ' eps32)'
        write(*,'(A)') trim(line)
        call assert_true(err <= tol, trim(label)//' within its frozen tolerance on the '//device_name(mlx_default_device()))
    end subroutine judge

    ! linspace and the windows against real64 formulas; the seed sets the number of points and the interval, so
    ! that the judged seeds run sizes the calibration did not
    subroutine test_spaced_values
        type(elem_tolerance)      :: tol
        type(mlx_array)           :: r
        real(real64), allocatable :: ref(:), c(:)
        real(real64), parameter   :: PI = 3.14159265358979323846_real64
        integer                   :: seeds(3), k, i, m
        real(real64)              :: lo, hi
        character(len=24)         :: tag
        write(*,'(a)') 'test_spaced_values'
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
        do k = 1, size(seeds)
            m = 32*seeds(k)+31
            lo = -1.5_real64*seeds(k)
            hi = 2.25_real64*seeds(k)
            write(tag,'(A,I0)') ' seed=', seeds(k)
            tol = tolerance_of('mlx_linspace')
            ref = [(lo+(hi-lo)*real(i, real64)/real(m-1, real64), i=0, m-1)]
            r = mlx_linspace(lo, hi, m)
            call judge(r, ref, tol%f32, 'mlx_linspace float32'//trim(tag))
            ref = [(lo+(hi-lo)*real(i, real64)/real(m, real64), i=0, m-1)]
            r = mlx_linspace(lo, hi, m, endpoint=.false.)
            call judge(r, ref, tol%f32, 'mlx_linspace(endpoint=.false.) float32'//trim(tag))
            if( mlx_default_device() == MLX_DEVICES%cpu )then
                r = mlx_linspace(lo, hi, m, endpoint=.false., dtype=MLX_DTYPES%float64)
                call judge(r, ref, tol%f64, 'mlx_linspace(endpoint=.false.) float64'//trim(tag))
                ref = [(lo+(hi-lo)*real(i, real64)/real(m-1, real64), i=0, m-1)]
                r = mlx_linspace(lo, hi, m, dtype=MLX_DTYPES%float64)
                call judge(r, ref, tol%f64, 'mlx_linspace float64'//trim(tag))
            endif
            c = [(2._real64*PI*real(i, real64)/real(m-1, real64), i=0, m-1)]
            tol = tolerance_of('mlx_bartlett')
            r = mlx_bartlett(m)
            call judge(r, 1._real64-abs(c/PI-1._real64), tol%f32, 'mlx_bartlett'//trim(tag))
            tol = tolerance_of('mlx_blackman')
            r = mlx_blackman(m)
            call judge(r, 0.42_real64-0.5_real64*cos(c)+0.08_real64*cos(2._real64*c), tol%f32, 'mlx_blackman'//trim(tag))
            tol = tolerance_of('mlx_hamming')
            r = mlx_hamming(m)
            call judge(r, 0.54_real64-0.46_real64*cos(c), tol%f32, 'mlx_hamming'//trim(tag))
            tol = tolerance_of('mlx_hanning')
            r = mlx_hanning(m)
            call judge(r, 0.5_real64-0.5_real64*cos(c), tol%f32, 'mlx_hanning'//trim(tag))
        end do
        r = mlx_linspace(0._real64, 1._real64)
        call assert_true(is_vector(r, 50), 'mlx_linspace has 50 points by default')
        call assert_int(MLX_DTYPES%float32, r%kind(), 'mlx_linspace is float32 by default')
        r = mlx_hanning(8)
        call assert_true(is_vector(r, 8), 'a window of m points is rank 1 of size m')
        call assert_int(MLX_DTYPES%float32, r%kind(), 'a window is float32')
    end subroutine test_spaced_values

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
